#!/usr/bin/env python3
"""
extro_st_data.py -- the pictures of the ST extro in ST format, at build
time (docs/05c-ST.md, "ST extro"; decision S1-S3, docs/11 7.9: 200 rows
centred, 16 colours per picture, pictures precomputed).

Reads Thalion's `Ambermoon_extro` (unpacked by tools/amiga_programm.py) and
writes to `build/st_extro/`, never into the repository:

    extro_st_pictures.bin  per picture A, then X: 200 lines x 160 bytes
                           each, 4 planes word-interleaved
    extro_st_data.i        the table St_pictures and the incbin
    extro_<n>_*.png        to look at: Thalion's picture, the ST picture,
                           the ST text colours (Thalion's colours shown
                           for the ST registers)

**What Thalion does per picture** (hunk 1 $250-$2FA, docs/11 5.3): clear
the background (320 x 256 x 5), the picture (width in words, height,
brightening, 32 colours, planes row-interleaved) centred into it: byte
offset (20 - width) & ~1, row offset (256 - height) / 2.  `$2B2E` then
computes the text plane B: every pixel gets the colour nearest to its own
colour brightened by the picture's value per channel (clamped at 15, the
squared distance, the first colour on a tie).  The scroll text shows
mask ? B : background.

**For the ST** per picture:
  - Amiga rows FIRST..FIRST+199 (S1, centred as on the Falcon at VGA);
  - 16 representative Amiga colours (the fairy's way, V3:
    fantasy_st_data.choose_reps), weighted by the picture and the text
    colours, each counting half; register r shows the fade of its
    representative, so Thalion's fades work unchanged;
  - A: each pixel's colour mapped to the nearest representative; colour 0
    alone in register 0 (S2);
  - B: the register nearest to Thalion's text colour of the pixel, chosen
    from the same 16 (S2), and never the pixel's own register where
    Thalion's text colour differs from the pixel's colour, so the text
    does not vanish;
  - X = A xor B, so the mix is A xor (X and mask).

DEVIATION (goals 1 and 2), docs/17-deviations.md D3: precomputed graphics,
16 colours.
"""

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import amiga_programm as ap             # noqa: E402
import fantasy_st_data as fsd           # noqa: E402

OUT = os.path.join(ap.BUILD, "st_extro")
AMIGA_ROWS = 256
FIRST = 28                  # Amiga row of ST line 0: 256 -> 200 centred
ST_LINES = 200
PLANES = 5
LISTS = (0x40, 0x6C, 0x98)  # hunk 2: the three ends' lists {text, picture}
ENTRY = 28                  # St_pictures: Thalion's picture, A, X, 16 reps


def pictures(h2, h2rel):
    """Hunk-3 offsets of the pictures the three lists name, in order."""
    out = []
    for base in LISTS:
        o = base
        while o in h2rel:
            if h2rel.get(o + 4) != 3:
                raise ap.Fehler(f"hunk 2 ${o + 4:x}: no picture in hunk 3")
            p = struct.unpack_from(">I", h2, o + 4)[0]
            if p not in out:
                out.append(p)
            o += 8
        if struct.unpack_from(">I", h2, o)[0]:
            raise ap.Fehler(f"hunk 2 ${o:x}: the list does not end with 0")
    return out


def background(h3, p):
    """Thalion's background for picture p: 256 rows of 320 colours."""
    w, h = struct.unpack_from(">HH", h3, p)
    data = p + 70
    x0 = ((20 - w) & ~1) * 8
    y0 = (AMIGA_ROWS - h) // 2
    rows = [[0] * 320 for _ in range(AMIGA_ROWS)]
    for y in range(h):
        planes = [h3[data + (y * PLANES + q) * 2 * w:
                     data + (y * PLANES + q + 1) * 2 * w] for q in range(PLANES)]
        for x in range(16 * w):
            b, m = x >> 3, 0x80 >> (x & 7)
            rows[y0 + y][x0 + x] = sum(1 << q for q in range(PLANES)
                                       if planes[q][b] & m)
    return rows


def brightened(pal, add):
    """Thalion's $2B2E/$2FDC: colour n -> its text colour."""
    out = []
    for n in range(32):
        t = [min(15, c + add) for c in fsd.colour(pal[n])]
        best, bi = 10000, 0
        for i in range(32):
            d = sum((a - b) ** 2 for a, b in zip(fsd.colour(pal[i]), t))
            if d < best:
                best, bi = d, i
        out.append(bi)
    return out


def nearest_register(c, colours, reps, without=None):
    return min((r for r in range(1, 16) if r != without),
               key=lambda r: (fsd.distance(c, colours[reps[r]]), r))


def convert(h3, p):
    add = struct.unpack_from(">H", h3, p + 4)[0]
    pal = [struct.unpack_from(">H", h3, p + 6 + 2 * i)[0] for i in range(32)]
    colours = [fsd.colour(w) for w in pal]
    bright = brightened(pal, add)
    rows = background(h3, p)[FIRST:FIRST + ST_LINES]
    ha, hb = [0] * 32, [0] * 32
    for row in rows:
        for c in row:
            ha[c] += 1
            hb[bright[c]] += 1
    ha[0] = hb[0] = 0       # register 0 is colour 0's anyway
    weights = [a + b for a, b in zip(fsd.normalised(ha), fsd.normalised(hb))]
    reps = fsd.choose_reps(colours, weights)
    reps += [0] * (16 - len(reps))
    map_a = [0] + [nearest_register(colours[n], colours, reps)
                   for n in range(1, 32)]
    map_b = []
    for n in range(32):
        t = bright[n]
        r = map_a[t] if t else 0
        if r == map_a[n] and colours[t] != colours[n]:
            r = nearest_register(colours[t], colours, reps, without=map_a[n])
        map_b.append(r)
    a = b"".join(fsd.st_line([map_a[c] for c in row]) for row in rows)
    b = b"".join(fsd.st_line([map_b[c] for c in row]) for row in rows)
    x = bytes(i ^ j for i, j in zip(a, b))
    return dict(pal=pal, reps=reps, rows=rows, bright=bright, map_a=map_a,
                map_b=map_b, a=a, x=x, add=add,
                used=sum(1 for v in ha if v) + (1 if any(0 in r for r in rows) else 0))


def save_pngs(n, e):
    try:
        import st_palettes
    except ImportError:
        return
    try:
        flat = [c for row in e["rows"] for c in row]
        amiga = [st_palettes.rgb_amiga(w) for w in e["pal"]]
        regs = [st_palettes.rgb_amiga(e["pal"][e["reps"][r]]) for r in range(16)]
        w, h = 320, ST_LINES
        base = os.path.join(OUT, f"extro_{n}")
        st_palettes.save_png(flat, w, h, amiga, base + "_thalion.png")
        st_palettes.save_png([e["bright"][c] for c in flat], w, h, amiga,
                             base + "_thalion_text.png")
        st_palettes.save_png([e["map_a"][c] for c in flat], w, h, regs,
                             base + "_st.png")
        st_palettes.save_png([e["map_b"][c] for c in flat], w, h, regs,
                             base + "_st_text.png")
    except ImportError:         # no PIL: the pictures are only to look at
        pass


def main():
    p = ap.PROGRAMME["extro"]
    try:
        d = open(os.path.join(ap.AMBERFILES, p["datei"]), "rb").read()
        hunks = ap.gepackt_lesen(d)
        ap.aufbau_pruefen(p, hunks)
        offsets = pictures(hunks[2]["daten"], hunks[2]["rel"])
    except ap.Fehler as e:
        sys.exit(f"extro_st_data: {p['datei']}: {e}")
    h3 = hunks[3]["daten"]

    os.makedirs(OUT, exist_ok=True)
    blob = bytearray()
    with open(os.path.join(OUT, "extro_st_data.i"), "w") as f:
        f.write("; build/st_extro/extro_st_data.i -- written by "
                "tools/extro_st_data.py\n; from Ambermoon_extro (Thalion); "
                "do not edit, not for the repository.\n\n")
        f.write(f"ST_PICTURES\tequ\t{len(offsets)}\n")
        f.write(f"ST_FIRST\tequ\t{FIRST}\t\t; Amiga row of ST line 0\n")
        f.write(f"ST_PICTURE\tequ\t{ENTRY}\t\t; an entry of St_pictures\n\n")
        f.write("\tSECTION\tExtro_data,data\n")
        f.write("; per picture: Thalion's picture, A, X (ST format), the "
                "Amiga colour of each register\nSt_pictures:\n")
        for n, o in enumerate(offsets):
            e = convert(h3, o)
            save_pngs(n, e)
            f.write(f"\tdc.l\tExtro_h3+${o:x}\n")
            f.write(f"\tdc.l\tSt_picture_data+{len(blob)},"
                    f"St_picture_data+{len(blob) + len(e['a'])}\n")
            f.write("\tdc.b\t" + ",".join(str(r) for r in e["reps"]) + "\n")
            blob += e["a"] + e["x"]
            w, h = struct.unpack_from(">HH", h3, o)
            print(f"  ST extro: picture {n} ({16 * w} x {h}, brightening "
                  f"{e['add']}): {e['used']} colours -> 16 registers")
        f.write("\tdc.l\t0\n")
        f.write("St_picture_data:\n\tincbin\t\"extro_st_pictures.bin\"\n")
    with open(os.path.join(OUT, "extro_st_pictures.bin"), "wb") as f:
        f.write(blob)


if __name__ == "__main__":
    main()

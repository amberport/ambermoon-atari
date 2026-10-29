#!/usr/bin/env python3
"""
fantasy_st_data.py -- graphics of the ST fantasy intro in ST format, at
build time (docs/05c-ST.md, "ST fairy intro, plan", step 3; the intro
exception of goal 1 allows graphics in ST format and precomputation).

Reads what tools/fantasy_auszug.py wrote from Thalion's `Fantasy_intro`
(`build/fantasy_grafik.bin`, `build/fantasy_daten.i`) and three tables from
Thalion's unchanged `FAIRY.S` (`$AMBER_URCODE`).  Writes to
`build/st_fantasy/`, never into the repository:

    fantasy_st_background.bin  the background, ST lines 0..ST_LINES-1 =
                               Amiga rows FIRST..255, 4 planes
                               word-interleaved, 160 bytes a line
    fantasy_st_fairy.bin       the fairy, 23 frames x 71 rows x 4 groups,
                               unshifted; per group the mask and planes 0-3
                               (5 words).  FANTASY_ST.S preshifts it at
                               program start (user 2026-10-23)
    fantasy_st_logo.bin        the "Fantasy" logo, 83 rows x 13 groups x 4
                               planes
    fantasy_st_data.i          the incbins, the colour tables of both bands,
                               the fairy's group count per frame, the sizes
    fantasy_st_stars.i         the stars as compiled code: one routine per
                               image and shift, a0 = ST address of the top
                               row's first group

Colours (V3, user 2026-10-22): two bands of 16 ST registers, split where
Thalion's copper splits (Amiga row 134; above it only the background).  Per
band 16 *representative* Amiga colours are chosen (k-medoids over the
colours used there); every Amiga colour maps to the nearest one.  Each ST
register then shows the fade of its representative, so Thalion's fades
work unchanged.  Lower band weights: background, fairy, logo, stars and
dust count equally (each one's histogram sums to 1), so the few pixels of
the fairy are not outvoted by the background.  Amiga colour 0 stays ST
register 0 (border, and "nothing" for Thalion's plot routines).

Tables in fantasy_st_data.i:
    St_rep_upper, St_rep_lower  16 bytes: Amiga colour of each ST register
    St_map_upper, St_map_lower  32 bytes: ST register of each Amiga colour

The fairy, logo and stars lie below row 134 only (Thalion's flight path
keeps the fairy's top row at 138 or lower, the logo starts at 146, stars and
dust are cut at 134), so they take the lower band's table.

DEVIATION (goals 1 and 2), docs/17-deviations.md D3: precomputed graphics.

**--falcon** (E30, user 2026-10-25: one tool for both machines; Falcon
Tempo's wish, docs/05b): the same pictures from the same extraction for the
Falcon, without colour reduction, to `build/falcon_fantasy/`:

    falcon_fantasy_background.bin  all 256 Amiga rows, 8 planes word-
                                   interleaved, 320 bytes a line; colour =
                                   Amiga colour, plane 5 = the band (1 from
                                   row 134), planes 6-7 = 0
    falcon_fantasy_fairy.bin       the fairy unshifted, as for the ST but
                                   planes 0-3 = the sprite value (the
                                   program preshifts and sets plane 4)
    falcon_fantasy_logo.bin        the logo, 83 rows x 13 groups x 5 planes
                                   (Amiga colour)
    falcon_fantasy_stars.i         the stars as code for that layout, a0 =
                                   Falcon address of the top row's first
                                   group (rows below 134: plane 5 set)
    falcon_fantasy_data.i          the incbins and the sizes, own names

The names in quotes ("elfe", "overfunkel", "Flugbahn" ...) are Thalion's
(FAIRY.S) or those of tools/fantasy_auszug.py and stay as they are.
"""

import os
import re
import sys
import paths

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
OUT = os.path.join(BUILD, "st_fantasy")
FALCON_OUT = os.path.join(BUILD, "falcon_fantasy")
SOURCE = paths.urcode()

FIRST = 22              # Amiga row of ST line 0 (picture position B)
AMIGA_ROWS = 256
ST_LINES = AMIGA_ROWS - FIRST
SPLIT = 134             # Amiga row where the lower band starts
PLANES = 5
BPSCANL = 200           # bytes per Amiga row, 5 planes of 40
FAIRY_FRAMES = 23       # fairy frames, 73*32 bytes each: 8 sprites
FAIRY_FRAME = 73 * 32
FAIRY_ROWS = 71
FAIRY_TOP = 138         # highest row of the fairy on the flight path
BIG_IMAGES = 12         # sparkle stars (overfunkel), 9 rows, 180 bytes each
SMALL_IMAGES = 3        # small stars (stars), 5 rows, 100 bytes each
LOGO_ROWS = 83          # logo (flogo), 26 bytes a plane row
LOGO_WIDTH = 26
BIG_IMAGE = 9 * PLANES * 4
SMALL_IMAGE = 5 * PLANES * 4
# Colour distance: first whether a channel moves by 2 levels or more (the
# measure of the analysis in docs/05c), then the squared differences
SHIFTED = 100
FALCON_LINE = 320       # bytes a Falcon line: 20 groups of 8 planes
FALCON_BAND = 32        # plane 5: the lower band


class Error(Exception):
    pass


def read_data():
    """Offsets into fantasy_grafik.bin and Farbwechsel_register."""
    path = os.path.join(BUILD, "fantasy_daten.i")
    where = {}
    changes = None
    lines = open(path, encoding="latin1").read().splitlines()
    for i, z in enumerate(lines):
        m = re.match(r"(\w+)\s+equ\s+Fantasy_grafik\+\$([0-9a-fA-F]+)", z)
        if m:
            where[m.group(1)] = int(m.group(2), 16)
        if z.startswith("Farbwechsel_register:"):
            values = re.match(r"\s*dc\.w\s+(.*)", lines[i + 1]).group(1)
            changes = [int(w.strip().lstrip("$"), 16)
                       for w in values.split(",")]
    for n in ("Palette_unten_quelle", "Palette_oben_quelle", "stars", "elfe",
              "background", "overfunkel", "flogo"):
        if n not in where:
            raise Error(f"{n} not in {path}")
    if not changes or changes[-1] != 0xFFFF:
        raise Error(f"Farbwechsel_register not in {path}")
    return where, [w // 2 for w in changes[:-1]]


def read_table(text, name):
    """dc.w values after the label `name` in FAIRY.S, up to the next line
    that is not dc.w."""
    lines = text.splitlines()
    for i, z in enumerate(lines):
        if z.split(";")[0].strip().rstrip(":") == name:
            values = []
            for z2 in lines[i + 1:]:
                m = re.match(r"\s*dc\.w\s+([^;]*)", z2)
                if not m:
                    break
                for w in m.group(1).split(","):
                    w = w.strip()
                    if not re.fullmatch(r"-?\d+(\*\d+)?", w):
                        raise Error(f"FAIRY.S {name}: cannot read '{w}'")
                    a, _, b = w.partition("*")
                    values.append(int(a) * (int(b) if b else 1))
            return values
    raise Error(f"FAIRY.S: table {name} not found")


def word(g, o):
    return (g[o] << 8) | g[o + 1]


def colour(w):
    return ((w >> 8) & 15, (w >> 4) & 15, w & 15)


def distance(a, b):
    q = sum((x - y) ** 2 for x, y in zip(a, b))
    return q + SHIFTED if max(abs(x - y) for x, y in zip(a, b)) >= 2 else q


def amiga_pixels(g, base, row):
    """The 320 colours of one Amiga row of the background."""
    o = base + row * BPSCANL
    planes = [g[o + p * 40:o + p * 40 + 40] for p in range(PLANES)]
    out = []
    for x in range(320):
        b, m = x >> 3, 0x80 >> (x & 7)
        out.append(sum(1 << p for p in range(PLANES) if planes[p][b] & m))
    return out


def normalised(h):
    s = sum(h)
    return [v / s for v in h] if s else h


def histograms(g, where, fairy):
    """Weights of the 32 Amiga colours per band."""
    bg = where["background"]
    upper, lower = [0] * 32, [0] * 32
    for y in range(FIRST, AMIGA_ROWS):
        for c in amiga_pixels(g, bg, y):
            (upper if y < SPLIT else lower)[c] += 1

    fairy_h = [0] * 32      # attached sprite pairs: colour 16 + 4-bit value
    for f in range(FAIRY_FRAMES):
        frame = where["elfe"] + f * 73 * 32
        for k in range(4):
            even = frame + 2 * k * 73 * 4
            odd = even + 73 * 4
            for r in range(FAIRY_ROWS):
                d = [word(g, even + 4 + 4 * r), word(g, even + 6 + 4 * r),
                     word(g, odd + 4 + 4 * r),
                     word(g, odd + 6 + 4 * r)]
                for x in range(16):
                    m = 0x8000 >> x
                    v = sum(1 << b for b in range(4) if d[b] & m)
                    if v:
                        fairy_h[16 + v] += 1

    logo = [0] * 32         # the logo replaces the background, 0 included
    for r in range(LOGO_ROWS):
        o = where["flogo"] + r * PLANES * LOGO_WIDTH
        planes = [g[o + p * LOGO_WIDTH:o + (p + 1) * LOGO_WIDTH]
                  for p in range(PLANES)]
        for x in range(LOGO_WIDTH * 8):
            b, m = x >> 3, 0x80 >> (x & 7)
            logo[sum(1 << p for p in range(PLANES) if planes[p][b] & m)] += 1

    # stars: per line (row * 5 + plane) a data word and a mask word
    def star(base, rows, weight, h):
        for r in range(rows):
            for x in range(16):
                m = 0x8000 >> x
                o = base + r * PLANES * 4
                if not any(word(g, o + p * 4 + 2) & m for p in range(PLANES)):
                    continue
                h[sum(1 << p for p in range(PLANES)
                      if word(g, o + p * 4) & m)] += weight

    stars = [0] * 32
    count = [0] * BIG_IMAGES
    for row in range(0, len(fairy["mani_tab"]), 16):
        for w in fairy["mani_tab"][row:row + 16]:
            if w < 0:
                break
            count[w] += 1
    for i, n in enumerate(count):
        if n:
            star(where["overfunkel"] + i * 9 * 20, 9, n, stars)
    for i in range(SMALL_IMAGES):
        star(where["stars"] + i * 100, 5, 1, stars)

    dust = [0] * 32         # colour * 4 in puls_tab, puls_tab2
    for w in fairy["puls_tab"] + fairy["puls_tab2"]:
        if w > 0:
            dust[w // 4] += 1

    lower = [sum(t) for t in zip(*(normalised(h) for h in
                                   (lower, fairy_h, logo, stars, dust)))]
    return normalised(upper), lower


def cost(colours, weights, reps):
    return sum(w * min(distance(colours[i], colours[r]) for r in reps)
               for i, w in enumerate(weights) if w)


def choose_reps(colours, weights):
    """16 representatives, colour 0 first; k-medoids (greedy, then swap)."""
    used = [i for i, w in enumerate(weights) if w and i]
    if len(used) <= 15:
        return [0] + used
    reps = [0]
    while len(reps) < 16:
        reps.append(min((i for i in used if i not in reps),
                        key=lambda i: cost(colours, weights, reps + [i])))
    better = True
    while better:
        better = False
        now = cost(colours, weights, reps)
        for k in range(1, 16):
            for i in used:
                if i in reps:
                    continue
                new = reps[:k] + [i] + reps[k + 1:]
                if cost(colours, weights, new) < now - 1e-12:
                    reps, now, better = new, cost(colours, weights, new), True
    return [0] + sorted(reps[1:])


def colour_map(colours, reps):
    return [min(range(16), key=lambda r: (distance(colours[i],
                                                   colours[reps[r]]),
                                          r)) for i in range(32)]


def st_line(pixels):
    """320 colours 0..15 -> 160 bytes, 4 planes word-interleaved."""
    out = bytearray()
    for group in range(20):
        words = [0] * 4
        for x in range(16):
            c = pixels[group * 16 + x]
            for p in range(4):
                if c & (1 << p):
                    words[p] |= 0x8000 >> x
        for w in words:
            out += bytes((w >> 8, w & 255))
    return out


def words_out(*w):
    return b"".join(bytes((x >> 8, x & 255)) for x in w)


def fairy_st(g, where, k):
    """The fairy unshifted: per frame and row four groups (mask, planes
    0-3).  Attached sprite pairs: pair n is pixels 16n..16n+15, the even
    sprite gives bits 0 and 1, the odd one bits 2 and 3, colour 16 + value,
    value 0 transparent.  Also the groups each frame needs once shifted by
    up to 15 pixels.  k maps colour 16 + value to the planes; the Falcon's
    takes the value itself (Falcon_value)."""
    out = bytearray()
    groups = []
    for f in range(FAIRY_FRAMES):
        frame = where["elfe"] + f * FAIRY_FRAME
        right = 0
        for r in range(FAIRY_ROWS):
            for n in range(4):
                even = frame + 2 * n * 73 * 4
                odd = even + 73 * 4
                d = [word(g, even + 4 + 4 * r), word(g, even + 6 + 4 * r),
                     word(g, odd + 4 + 4 * r),
                     word(g, odd + 6 + 4 * r)]
                mask, planes = 0, [0] * 4
                for x in range(16):
                    m = 0x8000 >> x
                    v = sum(1 << b for b in range(4) if d[b] & m)
                    if not v:
                        continue
                    mask |= m
                    right = max(right, 16 * n + x)
                    for p in range(4):
                        if k[16 + v] & (1 << p):
                            planes[p] |= m
                out += words_out(mask, *planes)
        groups.append(max(4, (right + 15) // 16 + 1))
    return out, groups


def check_flight_path(g, where):
    """The fairy must stay in the lower band: Flugbahn is x, y pairs,
    12345 marks the magic, and the fairy's rows are y..y+70."""
    o, top = where["Flugbahn"], 999
    while o < where["sprite_00"]:
        if word(g, o + 4) == 12345:
            o += 8
            continue
        top = min(top, word(g, o + 2))
        o += 4
    if top < SPLIT:
        raise Error(f"the fairy reaches row {top}, above the colour split "
                    f"{SPLIT}: she would need the upper band's colours")
    return top


def logo_falcon(g, where):
    """The logo for the Falcon: per row 13 groups of 5 plane words, the
    Amiga colour (the program adds the band)."""
    out = bytearray()
    for r in range(LOGO_ROWS):
        o = where["flogo"] + r * PLANES * LOGO_WIDTH
        for group in range(LOGO_WIDTH // 2):
            out += b"".join(bytes(g[o + p * LOGO_WIDTH + 2 * group:
                                    o + p * LOGO_WIDTH + 2 * group + 2])
                            for p in range(PLANES))
    return out


def falcon_line(pixels):
    """320 colours 0..63 -> 320 bytes, 8 planes word-interleaved."""
    out = bytearray()
    for group in range(20):
        words = [0] * 8
        for x in range(16):
            c = pixels[group * 16 + x]
            for p in range(6):
                if c & (1 << p):
                    words[p] |= 0x8000 >> x
        out += words_out(*words)
    return out


def falcon(g, where, fairy):
    """--falcon: the Falcon's files (header)."""
    os.makedirs(FALCON_OUT, exist_ok=True)
    bg = bytearray()
    for y in range(AMIGA_ROWS):
        band = FALCON_BAND if y >= SPLIT else 0
        bg += falcon_line([band + c for c in
                           amiga_pixels(g, where["background"], y)])
    open(os.path.join(FALCON_OUT, "falcon_fantasy_background.bin"),
         "wb").write(bg)
    check_flight_path(g, where)
    fairy_b, groups = fairy_st(g, where, Falcon_value)
    open(os.path.join(FALCON_OUT, "falcon_fantasy_fairy.bin"),
         "wb").write(fairy_b)
    logo = logo_falcon(g, where)
    open(os.path.join(FALCON_OUT, "falcon_fantasy_logo.bin"),
         "wb").write(logo)
    # the stars lie below row 134: Amiga colour plus the band
    stars, cycles = stars_i(g, where, [FALCON_BAND + c for c in range(32)],
                            "Falcon", "Falcon_star_routines", 6,
                            FALCON_LINE)
    open(os.path.join(FALCON_OUT, "falcon_fantasy_stars.i"),
         "w").write(stars)
    with open(os.path.join(FALCON_OUT, "falcon_fantasy_data.i"), "w") as f:
        f.write("; generated by tools/fantasy_st_data.py --falcon -- do not "
                "edit\n")
        f.write("; source: Fantasy_intro (Thalion), unpacked at build time\n\n")
        f.write(f"FALCON_DATA_ROWS\tequ\t{AMIGA_ROWS}\n")
        f.write(f"FALCON_DATA_LINE\tequ\t{FALCON_LINE}\n")
        f.write(f"FALCON_DATA_SPLIT\tequ\t{SPLIT}\t\t; plane 5 from here\n")
        f.write(f"FALCON_FAIRY_FRAMES\tequ\t{FAIRY_FRAMES}\n")
        f.write(f"FALCON_FAIRY_FRAME\tequ\t{FAIRY_FRAME}\t; bytes a frame "
                f"in elfe\n")
        f.write(f"FALCON_FAIRY_ROWS\tequ\t{FAIRY_ROWS}\n")
        f.write(f"FALCON_FAIRY_GROUPS\tequ\t4\t\t; a row unshifted: mask, "
                f"planes 0-3\n")
        f.write(f"FALCON_LOGO_GROUPS\tequ\t{LOGO_WIDTH // 2}\t; 5 planes\n")
        f.write(f"FALCON_LOGO_ROWS\tequ\t{LOGO_ROWS}\n")
        f.write(f"FALCON_STARS_BIG\tequ\t{BIG_IMAGES}\n")
        f.write(f"FALCON_STARS_SMALL\tequ\t{SMALL_IMAGES}\n")
        f.write(f"FALCON_BIG_IMAGE\tequ\t{BIG_IMAGE}\n")
        f.write(f"FALCON_SMALL_IMAGE\tequ\t{SMALL_IMAGE}\n\n")
        f.write("\tSECTION\tFee_daten,data\n")
        f.write("Falcon_background:\n\tincbin\t"
                "\"falcon_fantasy_background.bin\"\n")
        dc_b(f, "Falcon_fairy_groups", groups)
        f.write("\teven\n")
        f.write("Falcon_fairy:\n\tincbin\t\"falcon_fantasy_fairy.bin\"\n")
        f.write("Falcon_logo:\n\tincbin\t\"falcon_fantasy_logo.bin\"\n")
    big = [sum(t) / 16 for n, t in cycles.items() if "big" in n]
    print(f"  Falcon fairy: background {len(bg)} bytes, fairy "
          f"{len(fairy_b)}, logo {len(logo)}; stars {len(stars)} bytes of "
          f"source, big ones {min(big):.0f}-{max(big):.0f} cycles "
          f"-> build/falcon_fantasy/")


# the fairy for the Falcon: planes 0-3 = the sprite value (colour 16 + v)
Falcon_value = [c - 16 if c >= 16 else 0 for c in range(32)]


def logo_st(g, where, k):
    """The logo in ST format, 13 groups, all colours (it replaces the
    background, 0 included)."""
    out = bytearray()
    for r in range(LOGO_ROWS):
        o = where["flogo"] + r * PLANES * LOGO_WIDTH
        planes = [g[o + p * LOGO_WIDTH:o + (p + 1) * LOGO_WIDTH]
                  for p in range(PLANES)]
        pixels = []
        for x in range(LOGO_WIDTH * 8):
            b, m = x >> 3, 0x80 >> (x & 7)
            pixels.append(k[sum(1 << p for p in range(PLANES)
                                if planes[p][b] & m)])
        for group in range(LOGO_WIDTH // 2):
            w = [0] * 4
            for x in range(16):
                for p in range(4):
                    if pixels[16 * group + x] & (1 << p):
                        w[p] |= 0x8000 >> x
            out += words_out(*w)
    return out


def star_pixels(g, base, rows):
    """Rows of 16 pixels: None where the mask is clear, else the Amiga
    colour.  Per line (row * 5 + plane) a data word and a mask word."""
    out = []
    for r in range(rows):
        o = base + r * PLANES * 4
        line = []
        for x in range(16):
            m = 0x8000 >> x
            if not any(word(g, o + p * 4 + 2) & m for p in range(PLANES)):
                line.append(None)
            else:
                line.append(sum(1 << p for p in range(PLANES)
                                if word(g, o + p * 4) & m))
        out.append(line)
    return out


def star_routine(name, pixels, s, k, nplanes=4, line=160):
    """One star at shift s as code: per row, group and plane only the words
    the star touches, `or` where the plane is set under the whole mask,
    `and` where it is clear, both where it is mixed.  k maps the Amiga
    colour to the screen's; nplanes of them are written, the group has
    2 * planes(line) bytes."""
    lines, cycles = [f"{name}:"], 16
    group_bytes = line // 20
    for r, row in enumerate(pixels):
        for group in range(2):
            m, planes = 0, [0] * nplanes
            for x, c in enumerate(row):
                if c is None or (x + s) >> 4 != group:
                    continue
                bit = 0x8000 >> ((x + s) & 15)
                m |= bit
                for p in range(nplanes):
                    if k[c] & (1 << p):
                        planes[p] |= bit
            if not m:
                continue
            for p in range(nplanes):
                offset = r * line + group * group_bytes + p * 2
                target = f"{offset}(a0)" if offset else "(a0)"
                clocks = 20 if offset else 16
                if planes[p] != m:
                    lines.append(f"\tand.w\t#${~m & 0xFFFF:04X},{target}")
                    cycles += clocks
                if planes[p]:
                    lines.append(f"\tor.w\t#${planes[p]:04X},{target}")
                    cycles += clocks
    lines.append("\trts")
    return lines, cycles


def reciprocal(step, count):
    """k with (i * step * k) >> 16 == i for i < count: the image number
    from the offset of its start by mulu and swap, as FANTASY_ST.S does
    it."""
    k = -(-65536 // step)
    for i in range(count):
        if (i * step * k) >> 16 != i:
            raise Error(f"no reciprocal for {step} x {count}")
    return k


def stars_i(g, where, k, prefix="St", table="Star_routines", nplanes=4,
            line=160):
    """fantasy_st_stars.i: 12 big and 3 small stars x 16 shifts, and the
    table Star_routines (big ones first).  The Falcon's the same with its
    names and layout."""
    images = [(f"{prefix}_big{i}", star_pixels(g, where["overfunkel"]
                                               + i * BIG_IMAGE, 9))
              for i in range(BIG_IMAGES)]
    images += [(f"{prefix}_small{i}", star_pixels(g, where["stars"]
                                                  + i * SMALL_IMAGE, 5))
               for i in range(SMALL_IMAGES)]
    code, names, cycles = [], [], {}
    for name, pixels in images:
        for s in range(16):
            z, t = star_routine(f"{name}_{s}", pixels, s, k, nplanes, line)
            code += z
            names.append(f"{name}_{s}")
            cycles.setdefault(name, []).append(t)
    text = ["; generated by tools/fantasy_st_data.py -- do not edit",
            "; the stars of FAIRY.S (overfunkel, stars) as code, lower band",
            "", "\tSECTION\tFee_code,code", f"{table}:"]
    for i in range(0, len(names), 4):
        text.append("\tdc.l\t" + ",".join(names[i:i + 4]))
    return "\n".join(text + code) + "\n", cycles


def dc_b(f, name, values):
    f.write(f"{name}:\n\tdc.b\t" + ",".join(str(v) for v in values) + "\n")


def main():
    where, changes = read_data()
    g = open(os.path.join(BUILD, "fantasy_grafik.bin"), "rb").read()
    fairy_s = open(os.path.join(SOURCE, "FAIRY.S"), encoding="latin1").read()
    fairy = {n: read_table(fairy_s, n)
             for n in ("mani_tab", "puls_tab", "puls_tab2")}
    if "--falcon" in sys.argv[1:]:
        falcon(g, where, fairy)
        return

    upper_w = [word(g, where["Palette_oben_quelle"] + 2 * i)
               for i in range(32)]
    lower_w = [word(g, where["Palette_unten_quelle"] + 2 * i)
               if i in changes else upper_w[i] for i in range(32)]
    upper_c = [colour(w) for w in upper_w]
    lower_c = [colour(w) for w in lower_w]

    h_upper, h_lower = histograms(g, where, fairy)
    rep_upper = choose_reps(upper_c, h_upper)
    rep_lower = choose_reps(lower_c, h_lower)
    rep_upper += [0] * (16 - len(rep_upper))
    rep_lower += [0] * (16 - len(rep_lower))
    k_upper = colour_map(upper_c, rep_upper)
    k_lower = colour_map(lower_c, rep_lower)

    os.makedirs(OUT, exist_ok=True)
    bg = bytearray()
    for y in range(FIRST, AMIGA_ROWS):
        k = k_upper if y < SPLIT else k_lower
        bg += st_line([k[c] for c in amiga_pixels(g, where["background"], y)])
    open(os.path.join(OUT, "fantasy_st_background.bin"), "wb").write(bg)

    check_flight_path(g, where)
    fairy_b, groups = fairy_st(g, where, k_lower)
    open(os.path.join(OUT, "fantasy_st_fairy.bin"), "wb").write(fairy_b)
    logo = logo_st(g, where, k_lower)
    open(os.path.join(OUT, "fantasy_st_logo.bin"), "wb").write(logo)
    stars, cycles = stars_i(g, where, k_lower)
    open(os.path.join(OUT, "fantasy_st_stars.i"), "w").write(stars)
    buffer = sum(gr * FAIRY_ROWS * 10 * 16 for gr in groups)

    with open(os.path.join(OUT, "fantasy_st_data.i"), "w") as f:
        f.write("; generated by tools/fantasy_st_data.py -- do not edit\n")
        f.write("; source: Fantasy_intro (Thalion), unpacked at build time\n\n")
        f.write(f"ST_DATA_FIRST\tequ\t{FIRST}\t\t; Amiga row of ST line 0\n")
        f.write(f"ST_DATA_LINES\tequ\t{ST_LINES}\n")
        f.write(f"ST_DATA_SPLIT\tequ\t{SPLIT}\n")
        f.write(f"ST_FAIRY_FRAMES\tequ\t{FAIRY_FRAMES}\n")
        f.write(f"ST_FAIRY_FRAME\tequ\t{FAIRY_FRAME}\t\t; bytes a frame in elfe\n")
        f.write(f"ST_FAIRY_ROWS\tequ\t{FAIRY_ROWS}\n")
        f.write(f"ST_FAIRY_BUFFER\tequ\t{buffer}\t; 16 preshifts, all frames\n")
        f.write(f"ST_LOGO_GROUPS\tequ\t{LOGO_WIDTH // 2}\n")
        f.write(f"ST_LOGO_ROWS\tequ\t{LOGO_ROWS}\n")
        f.write(f"ST_STARS_BIG\tequ\t{BIG_IMAGES}\n")
        f.write(f"ST_STARS_SMALL\tequ\t{SMALL_IMAGES}\n")
        f.write(f"ST_BIG_IMAGE\tequ\t{BIG_IMAGE}\n")
        f.write(f"ST_SMALL_IMAGE\tequ\t{SMALL_IMAGE}\n")
        f.write(f"ST_BIG_RECIP\tequ\t"
                f"{reciprocal(BIG_IMAGE, BIG_IMAGES)}"
                f"\t; image = offset * this >> 16\n")
        f.write(f"ST_SMALL_RECIP\tequ\t"
                f"{reciprocal(SMALL_IMAGE, SMALL_IMAGES)}\n\n")
        f.write("\tSECTION\tFee_daten,data\n")
        f.write("St_background:\n\tincbin\t\"fantasy_st_background.bin\"\n")
        dc_b(f, "St_rep_upper", rep_upper)
        dc_b(f, "St_rep_lower", rep_lower)
        dc_b(f, "St_map_upper", k_upper)
        dc_b(f, "St_map_lower", k_lower)
        dc_b(f, "St_fairy_groups", groups)
        f.write("\teven\n")
        f.write("St_fairy:\n\tincbin\t\"fantasy_st_fairy.bin\"\n")
        f.write("St_logo:\n\tincbin\t\"fantasy_st_logo.bin\"\n")

    used_u = sum(1 for w in h_upper if w)
    used_l = sum(1 for w in h_lower if w)
    print(f"  ST fairy: background {len(bg)} bytes; colours used above row "
          f"{SPLIT} {used_u}, below {used_l}, 16 ST registers each")
    big = [sum(t) / 16 for n, t in cycles.items() if "big" in n]
    print(f"  ST fairy: fairy {len(fairy_b)} bytes, {buffer} once preshifted; "
          f"logo {len(logo)} bytes; stars {len(stars)} bytes of source, "
          f"big ones {min(big):.0f}-{max(big):.0f} cycles")


if __name__ == "__main__":
    try:
        main()
    except (Error, OSError) as e:
        sys.exit("fantasy_st_data.py: " + str(e))

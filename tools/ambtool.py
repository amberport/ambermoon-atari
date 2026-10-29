#!/usr/bin/env python3
"""
ambtool.py -- entpackt Ambermoon-Datendateien (Amiga-Original).

Formate
=======

JH-Verschlüsselung (Jurie Horneman)
    16-Bit-XOR mit fortlaufendem Schlüssel.  Der Schlüsselstrom ist ein
    linearer Kongruenzgenerator:

        k  <-  (k * 17 + 87) mod 65536

    Der Startschlüssel ist
      * bei Einzeldateien:  word[0] XOR word[1]   (word[0] == "JH" == $4A48),
        Nutzdaten ab Offset 4
      * bei AMNC-Containern: die Eintragsnummer (ab 1)

    Der Generator wurde hier aus `Palettes.amb` zurückgerechnet: 49 Einträge
    à 32 Farben, jede Farbe im Format $0RGB, also High-Nibble immer 0.  Das
    ergibt 6272 Bit Randbedingung — (17, 87) ist die einzige Lösung.

LOB-Kompression (Lothar Becks)
    LZ77/LZSS-Variante.  Header: "\\x01LOB", dann ein u32, dessen oberstes
    Byte konstant 6 ist und dessen untere 24 Bit die entpackte Größe angeben.
    Optional folgt ein u32 mit der gepackten Größe (in Blöcken innerhalb von
    Containern und bei JH-umhüllten Dateien).

    Die Daten bestehen aus Chunks: 1 Headerbyte, danach 8 Anweisungen.  Jedes
    Headerbit (MSB zuerst) bedeutet 1 = Literalbyte, 0 = Rückverweis.  Ein
    Rückverweis sind zwei Bytes `AB CD`: Länge = B + 3 (also 3..18),
    Abstand = $ACD (12 Bit).

Container
    AMNC   u16 Anzahl, u32 Größen[], dann Blöcke; Blöcke JH-verschlüsselt
           mit Schlüssel = Eintragsnummer.  "C" = crypted.
    AMNP   wie AMNC, Blöcke aber LOB-gepackt; Größe 0 = leerer Eintrag.
    AMBR   roh, unkomprimiert.
    AMPC   wie AMBR, Blöcke optional LOB-gepackt.

Amiga-Hunk-Executable
    Beginnt mit $000003F3.  Wird gebraucht für Fantasy_intro,
    Ambermoon_intro, Ambermoon_extro und AM2_CPU — die sind nicht gepackt.

Quellen: Amberworld (Oliver Gantert), Pyrdacor/Ambermoon FileSpecs.
"""

import argparse
import json
import os
import struct
import sys

# --------------------------------------------------------------------------
# JH
# --------------------------------------------------------------------------

JH_MUL = 17
JH_ADD = 87


def jh_decrypt(data, key):
    """16-Bit-XOR mit LCG-Schlüsselstrom."""
    out = bytearray(len(data))
    k = key & 0xFFFF
    n = len(data) & ~1
    for i in range(0, n, 2):
        p = ((data[i] << 8) | data[i + 1]) ^ k
        out[i] = (p >> 8) & 0xFF
        out[i + 1] = p & 0xFF
        k = (k * JH_MUL + JH_ADD) & 0xFFFF
    if len(data) & 1:
        # Thalion's Crypt_block (HULL/VARIOUS.S) rounds the length up, so an
        # odd last byte is XORed with the high byte of the next key (map
        # texts then end in a space, maps in zeros; finding 274).
        out[-1] = data[-1] ^ (k >> 8)
    return bytes(out)


# --------------------------------------------------------------------------
# LOB
# --------------------------------------------------------------------------

LOB_MAGIC = b"\x01LOB"


def lob_decompress(src, decoded_size):
    out = bytearray(decoded_size)
    di = 0
    si = 0
    n = len(src)
    while di < decoded_size:
        if si >= n:
            raise ValueError(f"LOB: Eingabe zu kurz (bei {di}/{decoded_size})")
        header = src[si]
        si += 1
        for _ in range(8):
            if (header & 0x80) == 0:                      # Rückverweis
                if si + 1 >= n:
                    raise ValueError("LOB: abgeschnittener Rückverweis")
                b0 = src[si]
                si += 1
                length = (b0 & 0x0F) + 3
                offset = ((b0 << 4) & 0xFF00) | src[si]
                si += 1
                mi = di - offset
                if mi < 0:
                    raise ValueError(f"LOB: Rückverweis vor Pufferanfang ({mi})")
                for _ in range(length):
                    if di >= decoded_size:
                        break
                    out[di] = out[mi]
                    di += 1
                    mi += 1
            else:                                          # Literal
                if si >= n:
                    raise ValueError("LOB: abgeschnittenes Literal")
                out[di] = src[si]
                si += 1
                di += 1
            if di >= decoded_size:
                break
            header = (header << 1) & 0xFF
    return bytes(out)


def lob_raw_size(block):
    return struct.unpack(">I", block[4:8])[0] & 0x00FFFFFF


def lob_unpack(block):
    """Entpackt einen LOB-Block. Gibt (daten, entpackte_groesse).

    Nach dem 8-Byte-Header folgt optional ein u32 mit der gepackten Größe.
    Er ist genau dann vorhanden, wenn er exakt `len(block) - 12` ergibt.
    """
    if not block.startswith(LOB_MAGIC):
        raise ValueError("kein LOB-Block")
    iterations = block[0]
    raw_size = lob_raw_size(block)
    body = 8
    if len(block) >= 12:
        if struct.unpack(">I", block[8:12])[0] == len(block) - 12:
            body = 12
    data = lob_decompress(block[body:], raw_size)
    for _ in range(iterations - 1):
        if not data.startswith(LOB_MAGIC):
            break
        data, _ = lob_unpack(data)
    return data, raw_size


# --------------------------------------------------------------------------
# Container
# --------------------------------------------------------------------------

CONTAINERS = ("AMNC", "AMNP", "AMBR", "AMPC")
CONTAINER_MAGIC = tuple(c.encode() for c in CONTAINERS)
HUNK_MAGIC = b"\x00\x00\x03\xf3"


def identify(data):
    if data[:4] in CONTAINER_MAGIC:
        return data[:4].decode()
    if data[:4] == LOB_MAGIC:
        return "LOB"
    if data[:2] == b"JH":
        return "JH"
    if data[:4] == HUNK_MAGIC:
        return "HUNK"
    return "RAW"


def unpack_entry(block, index, kind):
    """Ein Containerblock -> Klartext.  index ist 1-basiert.

    AMNP ist der interessante Fall: nur die ersten 8 Byte (LOB-Magic und
    entpackte Größe) liegen im Klartext.  Alles danach ist JH-verschlüsselt
    mit der Eintragsnummer als Startschlüssel, und beginnt mit einem u32,
    das die gepackte Größe angibt — sie entspricht immer `Blockgröße - 12`.
    """
    if not block:
        return b""

    if kind == "AMNC":
        return jh_decrypt(block, index)

    if block.startswith(LOB_MAGIC):
        raw_size = lob_raw_size(block)
        if kind == "AMNP":
            body = jh_decrypt(block[8:], index)
            csize = struct.unpack(">I", body[:4])[0]
            if csize != len(block) - 12:
                raise ValueError(
                    f"AMNP-Eintrag {index}: gepackte Größe {csize} passt nicht "
                    f"zu Blockgröße {len(block)}")
            return lob_decompress(body[4:], raw_size)
        return lob_unpack(block)[0]

    if block[:2] == b"JH":
        w0, w1 = struct.unpack(">HH", block[:4])
        return jh_decrypt(block[4:], w0 ^ w1)

    return block


def unpack(data):
    """Datei -> Liste von Einträgen (bytes).  Einzeldateien ergeben eine Liste
    mit genau einem Element."""
    kind = identify(data)

    if kind == "JH":
        w0, w1 = struct.unpack(">HH", data[:4])
        inner = jh_decrypt(data[4:], w0 ^ w1)
        if inner.startswith(LOB_MAGIC):
            return kind + "+LOB", [lob_unpack(inner)[0]]
        return kind, [inner]

    if kind == "LOB":
        return kind, [lob_unpack(data)[0]]

    if kind in CONTAINERS:
        count = struct.unpack(">H", data[4:6])[0]
        sizes = struct.unpack(f">{count}I", data[6:6 + count * 4])
        off = 6 + count * 4
        out = []
        for i, s in enumerate(sizes):
            block = data[off:off + s]
            off += s
            out.append(unpack_entry(block, i + 1, kind))
        return kind, out

    return kind, [data]


# --------------------------------------------------------------------------
# Amiga-Hunks
# --------------------------------------------------------------------------

HUNK_NAMES = {0x3E9: "CODE", 0x3EA: "DATA", 0x3EB: "BSS"}
MEM_NAMES = {0: "ANY", 1: "CHIP", 2: "FAST"}


def read_hunks(data):
    """Zerlegt ein Amiga-Hunk-Executable. Gibt Liste von dicts."""
    if data[:4] != HUNK_MAGIC:
        raise ValueError("kein Amiga-Hunk-Executable")
    u = lambda o: struct.unpack(">I", data[o:o + 4])[0]
    o = 4
    while u(o) != 0:                      # Namensliste residenter Bibliotheken
        o += 4 * (u(o) + 1)
    o += 4
    count = u(o)
    first, last = u(o + 4), u(o + 8)
    o += 12
    sizes = []
    for _ in range(count):
        v = u(o)
        sizes.append((v & 0x3FFFFFFF, (v >> 30) & 3))
        o += 4

    hunks = []
    idx = 0
    while o < len(data) and idx <= last - first:
        htype = u(o) & 0x3FFFFFFF
        o += 4
        if htype == 0x3EB:                                  # BSS
            n = u(o) * 4
            o += 4
            hunks.append(dict(index=idx, type="BSS", size=n, mem=sizes[idx][1],
                              data=b""))
        elif htype in (0x3E9, 0x3EA):                       # CODE / DATA
            n = u(o) * 4
            o += 4
            hunks.append(dict(index=idx, type=HUNK_NAMES[htype], size=n,
                              mem=sizes[idx][1], data=data[o:o + n]))
            o += n
        elif htype == 0x3EC:                                # RELOC32
            while True:
                cnt = u(o)
                o += 4
                if cnt == 0:
                    break
                o += 4 + cnt * 4
            continue
        elif htype in (0x3F0, 0x3F1):                       # SYMBOL / DEBUG
            n = u(o)
            o += 4 + n * 4
            continue
        elif htype == 0x3F2:                                # HUNK_END
            idx += 1
            continue
        else:
            break
    return hunks


# --------------------------------------------------------------------------
# Grafik: plane-sequentielles Amiga-Format -> Indexbild
# --------------------------------------------------------------------------

def planar_to_indices(data, width, planes, height=None, layout="line"):
    """Amiga-Planar -> Farbindizes.

    layout="line" (der tatsächlich benutzte Fall): zeilenverschachtelt.  Pro
    Bildzeile stehen die Plane-Zeilen direkt hintereinander:

        Zeile 0: Plane0 Plane1 Plane2 Plane3 Plane4
        Zeile 1: Plane0 Plane1 ...

    layout="plane": Plane 0 komplett, dann Plane 1 usw. (IFF-ACBM-Stil).

    Amberworld beschreibt das Format als ACBM-ähnlich, das ist aber falsch:
    der Vergleich mit der Referenz in `specs/picbinary.txt` (Portraits.amb,
    Eintrag 1) ergibt bei "line" exakte Übereinstimmung, bei "plane"
    168 von 170 Abweichungen.

    Beides ist NICHT das Atari-Layout, das die Planes wortweise verzahnt.
    """
    stride = width // 8
    if height is None:
        height = len(data) // (stride * planes)
    idx = [0] * (width * height)
    for p in range(planes):
        bit = 1 << p
        for y in range(height):
            if layout == "line":
                row = y * stride * planes + p * stride
            else:
                row = p * stride * height + y * stride
            o = y * width
            for xb in range(stride):
                b = data[row + xb]
                if not b:
                    continue
                ox = o + xb * 8
                for k in range(8):
                    if b & (0x80 >> k):
                        idx[ox + k] |= bit
    return idx, height


def parse_palette(data):
    """32 Farben à 16 Bit im Format $0RGB -> Liste von (r,g,b) 8 Bit."""
    n = len(data) // 2
    out = []
    for i in range(n):
        w = struct.unpack(">H", data[i * 2:i * 2 + 2])[0]
        r, g, b = (w >> 8) & 0xF, (w >> 4) & 0xF, w & 0xF
        out.append((r * 17, g * 17, b * 17))
    return out


def save_png(path, idx, width, height, palette):
    from PIL import Image
    img = Image.new("P", (width, height))
    flat = []
    for c in palette[:256]:
        flat += list(c)
    flat += [0] * (768 - len(flat))
    img.putpalette(flat)
    img.putdata(idx)
    img.save(path)


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------

def cmd_info(a):
    for path in a.files:
        if os.path.isdir(path):
            continue
        data = open(path, "rb").read()
        kind = identify(data)
        line = f"{os.path.basename(path):24} {len(data):>8}  {kind:6}"
        try:
            k, entries = unpack(data)
            total = sum(len(e) for e in entries)
            empty = sum(1 for e in entries if not e)
            line += (f"  {len(entries):>4} Eintr.  {total:>9} entpackt"
                     + (f"  ({empty} leer)" if empty else ""))
        except Exception as e:
            line += f"  FEHLER: {e}"
        print(line)


def cmd_extract(a):
    data = open(a.file, "rb").read()
    kind, entries = unpack(data)
    os.makedirs(a.outdir, exist_ok=True)
    base = os.path.basename(a.file).replace(".amb", "")
    n = 0
    for i, e in enumerate(entries):
        if not e:
            continue
        p = os.path.join(a.outdir, f"{base}_{i + 1:03d}.bin")
        open(p, "wb").write(e)
        n += 1
    print(f"{a.file}: {kind}, {n} Einträge nach {a.outdir}")


def cmd_hunks(a):
    data = open(a.file, "rb").read()
    hunks = read_hunks(data)
    print(f"{a.file}: {len(hunks)} Hunks")
    for h in hunks:
        print(f"  {h['index']:2}  {h['type']:4}  {h['size']:>8} Byte  "
              f"{MEM_NAMES.get(h['mem'], '?')}")
    if a.outdir:
        os.makedirs(a.outdir, exist_ok=True)
        base = os.path.basename(a.file)
        for h in hunks:
            if h["data"]:
                p = os.path.join(a.outdir,
                                 f"{base}_hunk{h['index']:02d}_{h['type']}.bin")
                open(p, "wb").write(h["data"])
        print(f"  -> {a.outdir}")


def cmd_palettes(a):
    data = open(a.file, "rb").read()
    kind, entries = unpack(data)
    pals = [parse_palette(e) for e in entries if e]
    print(f"{len(pals)} Paletten à {len(pals[0])} Farben")
    if a.json:
        json.dump([[list(c) for c in p] for p in pals], open(a.json, "w"))
        print(f"  -> {a.json}")
    if a.png:
        from PIL import Image
        cell = 16
        img = Image.new("RGB", (32 * cell, len(pals) * cell))
        for y, p in enumerate(pals):
            for x, c in enumerate(p):
                for dy in range(cell):
                    for dx in range(cell):
                        img.putpixel((x * cell + dx, y * cell + dy), c)
        img.save(a.png)
        print(f"  -> {a.png}")


def cmd_gfx(a):
    data = open(a.file, "rb").read()
    kind, entries = unpack(data)
    pal_kind, pal_entries = unpack(open(a.palette_file, "rb").read())
    palette = parse_palette(pal_entries[a.palette - 1])
    os.makedirs(a.outdir, exist_ok=True)
    base = os.path.basename(a.file).replace(".amb", "")
    stride = a.width // 8
    made = 0
    for i, e in enumerate(entries):
        if not e:
            continue
        unit = stride * a.planes
        if a.height:
            frames = len(e) // (unit * a.height)
            h = a.height
        else:
            frames, h = 1, len(e) // unit
        if h == 0:
            continue
        for f in range(frames):
            chunk = e[f * unit * h:(f + 1) * unit * h]
            idx, hh = planar_to_indices(chunk, a.width, a.planes, h)
            name = f"{base}_{i + 1:03d}" + (f"_{f:02d}" if frames > 1 else "")
            save_png(os.path.join(a.outdir, name + ".png"), idx, a.width, hh,
                     palette)
            made += 1
    print(f"{a.file}: {made} Bilder ({a.width}px, {a.planes} Planes) "
          f"nach {a.outdir}")


def main():
    p = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    i = sub.add_parser("info", help="Format und Inhalt anzeigen")
    i.add_argument("files", nargs="+")
    i.set_defaults(func=cmd_info)

    e = sub.add_parser("extract", help="Container entpacken")
    e.add_argument("file")
    e.add_argument("outdir")
    e.set_defaults(func=cmd_extract)

    h = sub.add_parser("hunks", help="Amiga-Hunk-Executable zerlegen")
    h.add_argument("file")
    h.add_argument("outdir", nargs="?")
    h.set_defaults(func=cmd_hunks)

    pa = sub.add_parser("palettes", help="Palettes.amb auslesen")
    pa.add_argument("file")
    pa.add_argument("--json")
    pa.add_argument("--png")
    pa.set_defaults(func=cmd_palettes)

    g = sub.add_parser("gfx", help="Planar-Grafik nach PNG")
    g.add_argument("file")
    g.add_argument("outdir")
    g.add_argument("--width", type=int, required=True)
    g.add_argument("--planes", type=int, required=True)
    g.add_argument("--height", type=int, help="feste Höhe = mehrere Frames")
    g.add_argument("--palette-file", required=True)
    g.add_argument("--palette", type=int, default=1, help="Palettennummer")
    g.set_defaults(func=cmd_gfx)

    a = p.parse_args()
    sys.exit(a.func(a) or 0)


if __name__ == "__main__":
    main()

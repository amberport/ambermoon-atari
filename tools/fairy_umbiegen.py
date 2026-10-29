#!/usr/bin/env python3
"""
fairy_umbiegen.py -- K1: die Amiga-Hardwareadressen in FAIRY.S umbiegen.

Thalions FAIRY.S schreibt unmittelbar in die Amiga-Chips ($DFFxxx).  Die
Datei bleibt unverändert (Leitziel 1).  Geändert wird die Übersetzung:
Nach dem Binden sucht dieses Werkzeug im Bereich Fairy_anfang..Fairy_ende von
FANTASY.TOS genau die zehn bekannten Operanden.  Es setzt jeden auf
Amiga_register + Registerversatz und trägt die Stelle in die
TOS-Verschiebetabelle ein.  Beschluss des Nutzers 2026-09-29, docs/11 7.2.

Abbruch, wenn eine Stelle fehlt, eine dazukommt oder der Befehl davor nicht
der erwartete ist.

Aufruf: fairy_umbiegen.py <FANTASY.TOS> <Linkkarte>
"""

import re
import struct
import sys

# (Befehlskopf vor dem Adressfeld, Register): in der Reihenfolge von FAIRY.S
ERWARTET = [
    (bytes.fromhex("4df9"), 0x000, "level3: lea $dff000,a6"),
    (bytes.fromhex("48f900ff"), 0x180, "level3: movem.l d0-d7,$dff180"),
    (bytes.fromhex("48f900ff"), 0x1A0, "level3: movem.l d0-d7,$dff1a0"),
    (bytes.fromhex("43f9"), 0x120, "level3: lea $dff120,a1"),
    (bytes.fromhex("33fc0020"), 0x09C, "level3: move #%100000,$dff09c"),
    (bytes.fromhex("41f9"), 0x120, "skip_level3: lea $dff120,a0"),
    (bytes.fromhex("33fc0020"), 0x09C, "skip_level3: move #%100000,$dff09c"),
    (bytes.fromhex("4df9"), 0x000, "make_magic: lea $dff000,a6"),
    (bytes.fromhex("4df9"), 0x000, "blit_star: lea $dff000,a6"),
    (bytes.fromhex("4df9"), 0x000, "blit_star2: lea $dff000,a6"),
]


def fehler(text):
    sys.exit("fairy_umbiegen.py: " + text)


def karte_lesen(pfad, namen):
    """Adressen aus der vlink-Karte (-M): Zeilen '0x... name'."""
    adr = {}
    for z in open(pfad, encoding="latin1"):
        m = re.match(r"\s*0x([0-9a-fA-F]+)\s+([^\s:]+):? ", z)
        if m and m.group(2) in namen:
            adr[m.group(2)] = int(m.group(1), 16)
    fehlend = [n for n in namen if n not in adr]
    if fehlend:
        fehler("nicht in der Karte: " + " ".join(fehlend))
    return adr


def fixups_lesen(d, start):
    erster = struct.unpack_from(">I", d, start)[0]
    stellen = []
    if erster == 0:
        return stellen, start + 4
    pos = erster
    stellen.append(pos)
    i = start + 4
    while True:
        b = d[i]
        i += 1
        if b == 0:
            break
        if b == 1:
            pos += 254
            continue
        pos += b
        stellen.append(pos)
    return stellen, i


def fixups_schreiben(stellen):
    stellen = sorted(stellen)
    if not stellen:
        return struct.pack(">I", 0)
    out = bytearray(struct.pack(">I", stellen[0]))
    for a, b in zip(stellen, stellen[1:]):
        delta = b - a
        if delta <= 0 or delta & 1:
            fehler(f"Verschiebestellen {a:#x}, {b:#x} ungueltig")
        while delta > 254:
            out.append(1)
            delta -= 254
        out.append(delta)
    out.append(0)
    return bytes(out)


def main():
    tos, karte = sys.argv[1], sys.argv[2]
    d = bytearray(open(tos, "rb").read())
    if d[:2] != b"\x60\x1a":
        fehler("kein TOS-Programm")
    tsize, dsize, bsize, ssize = struct.unpack_from(">IIII", d, 2)
    kopf = 0x1C
    adr = karte_lesen(karte, ["Fairy_anfang", "Fairy_ende", "Amiga_register"])
    von, bis = adr["Fairy_anfang"], adr["Fairy_ende"]
    if not (0 <= von < bis <= tsize):
        fehler("Fairy_anfang/Fairy_ende liegen nicht im Textabschnitt")

    # Jedes gerade Langwort $00DFFxxx im Bereich von FAIRY.S
    funde = []
    for o in range(von, bis - 3, 2):
        w = struct.unpack_from(">I", d, kopf + o)[0]
        if w & 0xFFFFFE00 == 0x00DFF000:
            funde.append((o, w & 0x1FF))
    if len(funde) != len(ERWARTET):
        fehler(f"{len(funde)} Hardwareadressen statt {len(ERWARTET)}: "
               + " ".join(f"${o:x}=$DFF{r:03X}" for o, r in funde))

    stellen, fix_ende = fixups_lesen(d, kopf + tsize + dsize + ssize)
    neu = set(stellen)
    for (o, reg), (kopfbytes, erw_reg, text) in zip(funde, ERWARTET):
        if reg != erw_reg or bytes(d[kopf + o - len(kopfbytes):kopf + o]) != kopfbytes:
            fehler(f"${o:x}: erwartet {text}, gefunden Register ${reg:03X}")
        if o in neu:
            fehler(f"${o:x}: steht schon in der Verschiebetabelle")
        struct.pack_into(">I", d, kopf + o, adr["Amiga_register"] + reg)
        neu.add(o)
    rest = d[fix_ende:]
    d = d[:kopf + tsize + dsize + ssize] + fixups_schreiben(neu) + rest
    open(tos, "wb").write(d)
    print(f"  K1: {len(funde)} Amiga-Adressen in FAIRY.S auf Amiga_register "
          f"(${adr['Amiga_register']:x}) umgebogen")


if __name__ == "__main__":
    main()

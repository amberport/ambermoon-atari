#!/usr/bin/env python3
"""
musik_k1.py -- the hardware operands of Thalion's music player, at build time.

    python3 tools/musik_k1.py intro     Intro_music
    python3 tools/musik_k1.py extro     Extro_music

Intro and extro load their music file at run time (goal 2, docs/11 6).  It
is raw code: Thalion's Sonic Arranger player ($1983 bytes, PC-relative) with
the song behind it.  The player addresses the hardware through 27 absolute
operands, at the same places in both files:

    $DFF000 x1, $DFF007 x2, $DFF096 x4, $DFF0A0-$DFF0D0 x13   Paula, VHPOSR
    $BFD000 x3 (CIA-B timer), $BFE001 x4 (CIA-A, filter)

K1 at run time (amiga/AMIGA_MUSIK.S) bends them onto the player's shadow
block and a CIA dummy.  This tool writes the map for it, build/<name>_musik.i:
the file length and each operand's offset with its original value.  The run
time checks both before it patches anything; a different file stays silent.
The count is fixed: if it differs, it is another version, and the build
stops.

Only this tool is in the repository, not the music.
"""

import collections
import os
import struct
import sys
import paths

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(WURZEL, "build")
AMBERFILES = paths.amberfiles()

DATEIEN = {"intro": "Intro_music", "extro": "Extro_music"}
SPIELER = 0x1983            # length of the player in front of the song
ERWARTET = {0xDFF000: 1, 0xDFF007: 2, 0xDFF096: 4, 0xDFF0A0: 4,
            0xDFF0B0: 3, 0xDFF0C0: 3, 0xDFF0D0: 3, 0xBFD000: 3, 0xBFE001: 4}


def stellen(d):
    """Even offsets in the player whose long is a hardware address."""
    s = []
    for i in range(0, SPIELER - 3, 2):
        v = struct.unpack_from(">I", d, i)[0]
        if 0xDFF000 <= v < 0xDFF200 or 0xBFD000 <= v < 0xBFF000:
            s.append((i, v))
    return s


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in DATEIEN:
        sys.exit("usage: musik_k1.py " + "|".join(DATEIEN))
    name = sys.argv[1]
    datei = DATEIEN[name]
    d = open(os.path.join(AMBERFILES, datei), "rb").read()
    s = stellen(d)
    zahl = dict(collections.Counter(v for _, v in s))
    if zahl != ERWARTET:
        sys.exit(f"musik_k1 {name}: {datei}: hardware operands {zahl}, "
                 f"expected {ERWARTET}")
    os.makedirs(BUILD, exist_ok=True)
    with open(os.path.join(BUILD, f"{name}_musik.i"), "w") as f:
        f.write(f"; build/{name}_musik.i -- written by tools/musik_k1.py from\n"
                f"; {datei}.  Do not edit, not for the repository.\n\n"
                f"MUSIK_LAENGE\tequ\t{len(d)}\n"
                "Musik_k1:\n")
        for i, v in s:
            f.write(f"\tdc.w\t${i:04x}\n\tdc.l\t${v:08x}\n")
        f.write("\tdc.w\t-1\n")
    print(f"  {datei}: {len(d)} bytes, K1 at {len(s)} places "
          f"-> build/{name}_musik.i")


if __name__ == "__main__":
    main()

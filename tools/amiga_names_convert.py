#!/usr/bin/env python3
"""amiga_names_convert.py -- developer tool: our sources name places of
Thalion's intro and extro by their 1.20 offset (tools/amiga_places.py).

    Intro_h5+$12206   ->  Intro_h5_12206
    Extro_h1+$EBC     ->  Extro_h1_EBC
    Intro_h5+8        ->  Intro_h5_8         (decimal offsets too)
    Extro_h6+$2E90+51200 -> Extro_h6_2E90+51200  (only the first term)

and the few constants that held such an offset become the moved name
(ZM_BASIS equ Intro_h5_11CF0, uses Intro_h5+ZM_BASIS -> ZM_BASIS).

The build then writes each name as an equ for the version it reads
(1.20: the same offset).  Not part of the build.  Run it once after a merge
brings a source with the old form back: it changes nothing that is already
converted, so it may run any number of times.  A bare hunk label
(jsr Intro_h0, cmp.l #Intro_h4+...) stays: those are hunk bounds.

Usage: python3 tools/amiga_names_convert.py [--check]
       --check: change nothing, list what would change, exit 1 if any
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FOLDERS = ["intro", "extro", "intro_st", "extro_st", "amiga"]

PLACE = re.compile(r"\b((?:Intro|Extro)_h)(\d+)\+(\$[0-9A-Fa-f]+|\d+)\b")

# Constants that held an offset into a hunk: (file, definition before,
# definition after); every use <hunk label>+<name> becomes <name>.
CONSTANTS = [
    ("intro/INTRO_ZOOM.S", r"ZM_BASIS\tequ\t\$11CF0", "ZM_BASIS\tequ\tIntro_h5_11CF0"),
    ("intro/INTRO_ZOOM.S", r"ZM_SCHIRM\tequ\t\$18", "ZM_SCHIRM\tequ\tIntro_h5_18"),
    ("intro_st/ZOOM_ST.S", r"ZM_BASE\t\tequ\t\$11CF0", "ZM_BASE\t\tequ\tIntro_h5_11CF0"),
    ("intro_st/ZOOM_ST.S", r"ZM_SCREEN\tequ\t\$18", "ZM_SCREEN\tequ\tIntro_h5_18"),
    ("intro_st/INTRO_ST.S", r"THALION_VBL\tequ\t\$2522", "THALION_VBL\tequ\tIntro_h0_2522"),
    ("extro_st/extro_st_defs.i", r"H5_COUNT\tequ\t\$04", "H5_COUNT\tequ\tExtro_h5_4"),
    ("extro_st/extro_st_defs.i", r"H5_FAST\t\tequ\t\$3E", "H5_FAST\t\tequ\tExtro_h5_3E"),
]
NAMES = "|".join(sorted({re.match(r"(\w+)", k[1]).group(1) for k in CONSTANTS}))
USE = re.compile(r"\b(?:Intro|Extro)_h\d+\+(%s)\b" % NAMES)


def place_name(m):
    number = m.group(3)
    value = int(number[1:], 16) if number.startswith("$") else int(number)
    return "%s%s_%X" % (m.group(1), m.group(2), value)


def convert(path, text):
    rel = os.path.relpath(path, ROOT)
    for file, before_text, after_text in CONSTANTS:
        if file == rel:
            text = re.sub(before_text, after_text, text)
    text = USE.sub(lambda m: m.group(1), text)
    return PLACE.sub(place_name, text)


def main():
    check = "--check" in sys.argv[1:]
    changed = []
    for folder in FOLDERS:
        for path in sorted(glob.glob(os.path.join(ROOT, folder, "*.[sSi]"))):
            with open(path, encoding="latin1", newline="") as f:
                old = f.read()
            new = convert(path, old)
            if new != old:
                changed.append(os.path.relpath(path, ROOT))
                if not check:
                    with open(path, "w", encoding="latin1", newline="") as f:
                        f.write(new)
    for g in changed:
        print(("would change " if check else "changed ") + g)
    if not changed:
        print("nothing to change")
    return 1 if check and changed else 0


if __name__ == "__main__":
    sys.exit(main())

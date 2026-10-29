#!/usr/bin/env python3
"""intro_auszug.py -- was die Bibliothek aus Ambermoon_intro braucht, beim Bau.

DEVIATION (goals 1 and 2), docs/17-deviations.md D4: the texts of our own
start menu, taken from Ambermoon_intro at build time.

Das Startmenue (WEITERSPIELEN, NEUE QUEST STARTEN, INTRO, QUIT) steht im
Original nicht in AM2_CPU, sondern im eigenen Programm Ambermoon_intro.  Sein
Quelltext ist nicht freigegeben.  Die Texte holt dieses Werkzeug beim Bau
heraus (wie am2cpu_auszug.py, Nutzer 2026-09-27: Amiga-Programme werden zur
Laufzeit nie gelesen) und schreibt build/intro_daten.i; engine.s bindet es
ein, HULL/STARTMENUE.S zeichnet daraus.

Aufbau in 1.20 (Hunk 1 ab $297): ein Byte Anzahl (4), dann je Eintrag ein
Byte x, ein Byte y und der Text mit Endnull.  x und y sind die Lage in
Thalions Menue (320x256, grosse Zierschrift); wir uebernehmen y, x rechnet
die Bibliothek fuer unseren Zeichensatz neu.

Aufruf:  intro_auszug.py [--amberfiles DIR] [--out build/intro_daten.i]
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import read_hunks                          # noqa: E402
import paths  # noqa: E402

MENUE_HUNK, MENUE_ANFANG = 1, 0x297
MENUE_ERWARTET = ["WEITERSPIELEN", "NEUE QUEST STARTEN", "INTRO", "QUIT"]


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--amberfiles", default=paths.amberfiles())
    p.add_argument("--out", default="build/intro_daten.i")
    a = p.parse_args()

    hunks = {h["index"]: h["data"] for h in read_hunks(
        open(os.path.join(a.amberfiles, "Ambermoon_intro"), "rb").read())}
    d = hunks[MENUE_HUNK]
    o = MENUE_ANFANG
    anzahl = d[o]
    o += 1
    eintraege = []
    for _ in range(anzahl):
        x, y = d[o], d[o + 1]
        ende = d.index(b"\0", o + 2)
        eintraege.append((x, y, d[o + 2:ende].decode("latin-1")))
        o = ende + 1
    if [t for _, _, t in eintraege] != MENUE_ERWARTET:
        raise SystemExit("intro_auszug: Menue in Ambermoon_intro passt nicht: %r"
                         % eintraege)

    z = ["; build/intro_daten.i -- erzeugt von tools/intro_auszug.py aus",
         "; Ambermoon_intro.  Nicht von Hand aendern, nicht ins Repository.",
         "", "\tSECTION\tFast_DATA,data", "\teven",
         "; Startmenue: Anzahl, dann je Eintrag y (wie im Original) und Text.",
         "Menue_anzahl:\tdc.w\t%d" % anzahl]
    z.append("Menue_y:")
    for x, y, t in eintraege:
        z.append("\tdc.w\t%d\t\t; x im Original %d" % (y, x))
    z.append("Menue_texte:")
    for i, (_, _, t) in enumerate(eintraege):
        z.append("\tdc.l\tMenue_text_%d" % i)
    for i, (_, _, t) in enumerate(eintraege):
        z.append('Menue_text_%d:\tdc.b\t"%s",0' % (i, t))
    z += ["\teven", ""]

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as fh:
        fh.write("\n".join(z))
    print("  Ambermoon_intro: Startmenue, %d Eintraege -> %s" % (anzahl, a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Vollprobe: alle Dateien Thalions zusammen uebersetzen und zaehlen, was fehlt.

Was dann fehlt, ist die **ganze** Bibliothek, die Thalion nie veroeffentlicht
hat (AM2_CPU), samt den Datendateien, aus denen Texte und Grafik kamen.  Das
ist die Ziellinie von Leitziel 1: sind diese Namen echt da, kann jede
Thalion-Datei herein.

Die Probe baut zwei Einheiten wie engine/spiel.s (Thalion hat Bibliothek und
Spiel getrennt uebersetzt; Number und Control_list_ptr stehen doppelt):

    bibliothek  vorspann.i + GAME_OFF.S + HULL/*.S
    spiel       vorspann.i + GAME_OFF.S + alle uebrigen *.S, mit "opt t-"
                (ACTIONS.S:128, Erkenntnis 189)

Ausgelassen wird FAIRY.S: sie greift als einzige nennenswert auf die
Amiga-Hardware zu und gehoert nicht zum Spiel.

Aus den Listings kommt, was beide Einheiten zusammen brauchen und keine
definiert.  Jeder dieser Namen wird gegen unseren Bau gehalten (die Listings
von tools/einheiten_verbinden.py in build/):

    echt         bei uns definiert, nicht in einer *_STUBS.S
    Platzhalter  in einer *_STUBS.S
    fehlt        noch gar nicht da

Schreibt build/vollprobe.txt und eine Zeile auf die Konsole.  Uebersetzt die
Probe nicht, steht ACHTUNG da: dann passt vorspann.i nicht mehr zu Thalions
Quelltext -- das trifft jede Datei, die noch hereinkommt.

Rueckgabe immer 0 (Bericht, wie die 68000-Gegenprobe).
"""
import glob
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from einheiten_verbinden import symbole  # noqa: E402
import paths  # noqa: E402

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URCODE = paths.urcode()
BUILD = os.path.join(WURZEL, "build")
AUSGELASSEN = {"GAME_OFF.S", "FAIRY.S"}
DOPPELT_ERLAUBT = {"Number", "Control_list_ptr"}


def thalions_dateien():
    alle = []
    for p in glob.glob(os.path.join(URCODE, "**", "*"), recursive=True):
        if os.path.isfile(p) and p.upper().endswith(".S"):
            rel = os.path.relpath(p, URCODE)
            if os.path.basename(rel).upper() not in AUSGELASSEN:
                alle.append(rel)
    alle.sort()
    bib = [d for d in alle if d.upper().startswith("HULL" + os.sep)]
    spiel = [d for d in alle if d not in bib]
    return bib, spiel


def probe_schreiben(name, dateien, opt_t):
    zeilen = ["; erzeugt von tools/vollprobe.py -- nicht von Hand aendern",
              '\tINCLUDE\t"vorspann.i"', "\tSECTION\tProgram,code",
              '\tINCLUDE\t"GAME_OFF.S"']
    if opt_t:
        zeilen.append("\topt\tt-")
    for d in dateien:
        zeilen.append('\tINCLUDE\t"%s"' % d)
        zeilen.append("\tSECTION\tProgram,code")
    pfad = os.path.join(BUILD, "vollprobe_%s.s" % name)
    with open(pfad, "w") as f:
        f.write("\n".join(zeilen) + "\n")
    return pfad


def uebersetzen(quelle, name):
    lst = os.path.join(BUILD, "vollprobe_%s.lst" % name)
    cmd = ["vasmm68k_mot", "-m68030", "-Fvobj", "-esc", "-align", "-quiet",
           "-I" + URCODE, "-I" + os.path.join(WURZEL, "tools", "originalcode"),
           "-L", lst, "-Lni", "-o", os.devnull, quelle]
    r = subprocess.run(cmd, capture_output=True, text=True, errors="replace")
    # Nur Fehler und Warnung 2028 (Erkenntnis 185).  Die uebrigen Warnungen
    # hat der Normalbau ebenso (NUMERIC.S:339, "not referenced").
    meldungen = [z for z in (r.stdout + r.stderr).splitlines()
                 if re.match(r"^(fatal )?error |^warning 2028", z)]
    return r.returncode, meldungen, lst


def stub_namen():
    namen = set()
    for f in glob.glob(os.path.join(WURZEL, "engine", "src", "**", "*_STUBS.S"),
                       recursive=True):
        for z in open(f, encoding="latin-1"):
            m = re.match(r"^([A-Za-z_]\w*):", z)
            if m:
                namen.add(m.group(1))
    return namen


def main():
    if not os.path.isdir(URCODE):
        print("  Vollprobe uebersprungen -- AMBER_URCODE fehlt")
        return 0
    os.makedirs(BUILD, exist_ok=True)
    bib, spiel = thalions_dateien()
    tab = {}
    for name, dateien, opt_t in (("bibliothek", bib, False), ("spiel", spiel, True)):
        rc, meldungen, lst = uebersetzen(probe_schreiben(name, dateien, opt_t), name)
        if rc or meldungen:
            print("  ACHTUNG: Vollprobe %s uebersetzt nicht sauber (vorspann.i?):" % name)
            for z in meldungen[:10]:
                print("    " + z)
            if rc:
                return 0
        tab[name] = symbole(lst)

    (mb, kb, eb), (ms, ks, es) = tab["bibliothek"], tab["spiel"]
    doppelt = (mb & ms) - DOPPELT_ERLAUBT
    fehlt_ganz = sorted((eb | es) - (mb | kb | ms | ks))

    unsere = set()
    for n in ("bibliothek", "spiel"):
        lst = os.path.join(BUILD, "%s.lst" % n)
        if os.path.isfile(lst):
            m, k, _ = symbole(lst)
            unsere |= m | k
    stubs = stub_namen()
    echt = [n for n in fehlt_ganz if n in unsere and n not in stubs]
    platz = [n for n in fehlt_ganz if n in stubs]
    offen = [n for n in fehlt_ganz if n not in unsere]

    aus = ["Vollprobe, erzeugt von tools/vollprobe.py",
           "%d Thalion-Dateien (Bibliothek %d, Spiel %d), ohne %s"
           % (len(bib) + len(spiel), len(bib), len(spiel),
              ", ".join(sorted(AUSGELASSEN))),
           "Namen, die Thalions Quelltext braucht und nicht definiert: %d"
           % len(fehlt_ganz), ""]
    for titel, liste in (("fehlt", offen), ("Platzhalter", platz), ("echt", echt)):
        aus.append("== %s: %d" % (titel, len(liste)))
        aus += ["  " + n for n in liste]
        aus.append("")
    if doppelt:
        aus.append("== doppelt in beiden Einheiten (unerwartet): " + " ".join(sorted(doppelt)))
    with open(os.path.join(BUILD, "vollprobe.txt"), "w") as f:
        f.write("\n".join(aus) + "\n")

    print("  Vollprobe: %d Thalion-Dateien uebersetzen zusammen; Thalions "
          "Bibliothek braucht %d Namen -- echt %d, Platzhalter %d, fehlt %d "
          "-> build/vollprobe.txt"
          % (len(bib) + len(spiel), len(fehlt_ganz), len(echt), len(platz), len(offen)))
    if doppelt:
        print("  ACHTUNG: Vollprobe doppelt: " + " ".join(sorted(doppelt)))
    return 0


if __name__ == "__main__":
    sys.exit(main())

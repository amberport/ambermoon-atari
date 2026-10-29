#!/usr/bin/env python3
"""Platzhalter im falschen Abschnitt finden.

Unsere *_STUBS.S haben einen Routinenblock, in dem viele Marken auf ein
einziges ``rts`` fallen::

    Find_small_text:
    Number:
    Push_Scroll_bar:
        rts

Alle zeigen auf dieselbe Adresse.  Steht dort ein Symbol, das das Original
nicht *ruft*, sondern mit ``lea`` *adressiert* und beschreibt, dann
ueberschreibt der erste Schreibzugriff dieses ``rts`` -- und der naechste
Aufruf irgendeines anderen Platzhalters fuehrt die geschriebenen Bytes als
Befehle aus.

Genau das war der Inventar-Freeze vom 2026-09-19 (Erkenntnis 157): ``Number``
ist ein Zahlentext-Puffer, stand aber im Routinenblock; der erste Aufruf von
``Display_small_member_info`` legte drei ASCII-Ziffern auf das ``rts``, der
zweite sprang hinein.  Elf weitere Faelle steckten in DISPLAY_STUBS.S und
waren nur noch nicht dran.

Die Probe ist mechanisch und braucht kein Urteil:

    kommt "lea <Name>" im Originalquelltext vor
    und kein "jsr/bsr <Name>"          -> es sind Daten, kein Sprungziel

Kommt beides vor, ist es eine Routine, deren Adresse irgendwo als Vektor
abgelegt wird -- harmlos.

Rueckgabe 1, wenn etwas gefunden wurde.
"""
import os
import re
import sys
import paths

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URCODE = paths.urcode()
# AM2_CPU_STUBS.S replaced all former *_STUBS.S.  A file named here that is
# missing stops the check: otherwise it passes without looking at anything.
STUBS = ["engine/src/HULL/AM2_CPU_STUBS.S"]

MARKE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):\s*$")
SECTION = re.compile(r"^\s+SECTION\s+\w+\s*,\s*(\w+)", re.IGNORECASE)


def routinenmarken(pfad):
    """The labels in the code sections of the file: the routine block."""
    namen, drin = [], False
    with open(pfad, encoding="latin-1") as f:
        for zeile in f:
            s = SECTION.match(zeile)
            if s:
                drin = s.group(1).lower() == "code"
                continue
            if not drin:
                continue
            m = MARKE.match(zeile)
            if m:
                namen.append(m.group(1))
    return namen


def originalquellen():
    texte = []
    for wurzel, _, dateien in os.walk(URCODE):
        for d in dateien:
            if d.endswith(".S"):
                with open(os.path.join(wurzel, d), encoding="latin-1") as f:
                    texte.append(f.read())
    return "\n".join(texte)


def main():
    if not os.path.isdir(URCODE):
        print("  Platzhalterprobe uebersprungen -- AMBER_URCODE fehlt")
        return 0
    quelle = originalquellen()
    funde = []
    for rel in STUBS:
        pfad = os.path.join(WURZEL, rel)
        if not os.path.exists(pfad):
            print("  ERROR: %s is missing; update STUBS in %s"
                  % (rel, os.path.relpath(__file__, WURZEL)))
            return 1
        for name in routinenmarken(pfad):
            # "Unser_"-Vorsatz ist unsere Umbenennung, im Original steht der
            # nackte Name.
            orig = name[len("Unser_"):] if name.startswith("Unser_") else name
            adressiert = re.search(r"lea(\.l)?\s+%s\s*,\s*a[0-7]" % re.escape(orig), quelle)
            gerufen = re.search(r"\b(jsr|bsr)(\.[bwsl])?\s+%s\b" % re.escape(orig), quelle)
            if adressiert and not gerufen:
                funde.append((rel, name))
    if funde:
        print("  FEHLER: Platzhalter im Routinenblock, die Daten sind:")
        for rel, name in funde:
            print("     %s  %s" % (rel, name))
        print("  Das Original adressiert sie mit lea und ruft sie nie.  Im")
        print("  Routinenblock ueberschreibt der erste Schreibzugriff das")
        print("  gemeinsame rts -- siehe Erkenntnis 157.  Nach Fast_BSS damit.")
        return 1
    print("  Kein Platzhalter im falschen Abschnitt.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

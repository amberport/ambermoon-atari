#!/usr/bin/env python3
"""Ausgabe von a56 in ein Abbild fuer Dsp_ExecBoot umsetzen.

a56 schreibt je Wort eine Zeile "P aaaa wwwwww" (Speicher, Adresse, Wort,
hexadezimal), dazu "I"-Zeilen mit den Marken.  Dsp_ExecBoot laedt den
P-Speicher ab P:0 und hoechstens 512 Worte, je Wort drei Bytes, hoechstes
zuerst.  Luecken werden mit 0 gefuellt.

    python3 tools/dsp_lod.py build/x.lod build/x.dsp

Bricht ab bei X- oder Y-Worten (die laedt der Urlader nicht), bei einer
Adresse ab 512 und bei einem doppelt belegten Wort.
"""
import sys

GRENZE = 512


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    worte = {}
    for nr, zeile in enumerate(open(sys.argv[1]), 1):
        teile = zeile.split()
        if not teile or teile[0] == 'I':
            continue
        if len(teile) != 3 or teile[0] not in ('P', 'X', 'Y'):
            sys.exit('%s:%d: unbekannte Zeile: %s' % (sys.argv[1], nr, zeile.strip()))
        if teile[0] != 'P':
            sys.exit('%s:%d: %s-Speicher laedt der Urlader nicht' % (sys.argv[1], nr, teile[0]))
        adr, wort = int(teile[1], 16), int(teile[2], 16)
        if adr >= GRENZE:
            sys.exit('%s:%d: P:%04X liegt hinter %d Worten' % (sys.argv[1], nr, adr, GRENZE))
        if adr in worte:
            sys.exit('%s:%d: P:%04X doppelt belegt' % (sys.argv[1], nr, adr))
        worte[adr] = wort
    if not worte:
        sys.exit('%s: keine Worte' % sys.argv[1])
    laenge = max(worte) + 1
    abbild = bytearray()
    for adr in range(laenge):
        abbild += worte.get(adr, 0).to_bytes(3, 'big')
    open(sys.argv[2], 'wb').write(abbild)
    print('  %s: %d Worte P-Speicher' % (sys.argv[2], laenge))


if __name__ == '__main__':
    main()

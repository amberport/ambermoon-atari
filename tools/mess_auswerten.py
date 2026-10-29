#!/usr/bin/env python3
"""
mess_auswerten.py -- die Messdatei einer Amiga-Messfassung auswerten
(Schalter AMIGA_MESSEN, amiga/AMIGA_RAHMEN.S; docs/11 7.6).

Die Datei (<Programm>.MES, etwa INTROMES.MES, FEEDIAG.MES) zählt, wo Timer A das Programm angetroffen
hat: je 64 Byte ab `start` ein Fach, dazu je Sekunde die drei Arten Blits,
Anzeige, sonst.  Die Linkkarte der Messfassung (build/INTROMES.map) nennt
die Routinen; Thalions Programm hat dort nur einen Namen je Hunk, darum
erscheint es als Intro_h0+Versatz (der Versatz passt zu
`am2cpu_lesen.py`-artigen Disassemblierungen des Hunks).

Mit BLIT_STATISTIK steht hinter dem Verlauf die Tabelle der Blit-Arten
(Bs_zaehlen in amiga/AMIGA_MESSEN.S); sie wird nach Proben geordnet gezeigt.
Zuletzt steht "VBLS" mit der Zahl der VBLs: die echte Laufzeit, daraus der
Anteil, in dem Timer A nicht durchkam (HOG-Blits des Falcon-Blitters).
Dahinter "H200" mit den Takten von _hz_200 (Uhr des TOS, 200 je Sekunde):
die Laufzeit unabhaengig vom VBL, daraus die Bildfrequenz (50 oder 60 Hz).
Dahinter beim Fantasy-Intro "BILD": je Sekunde Bilder, knapp, zu spaet und
die Summe von vindex (Bild_messen in fantasy/FEE_SUP.S).

Aufruf: mess_auswerten.py <Datei.MES> <Linkkarte.map> [--verlauf]
"""

import re
import struct
import sys


def karte_lesen(pfad):
    """Codemarken der Karte: [(Adresse, Name)], aufsteigend."""
    text = open(pfad, encoding="latin-1").read()
    teil = text.split("Symbols of .text:")[1].split("Symbols of")[0]
    marken = []
    for m in re.finditer(r"0x([0-9a-f]+) ([A-Za-z_][\w]*): \w+ reloc", teil):
        name = m.group(2)
        if name.startswith("."):
            continue
        marken.append((int(m.group(1), 16), name))
    marken.sort()
    return marken


def name_von(marken, adresse):
    vorher = None
    for a, n in marken:
        if a > adresse:
            break
        vorher = (a, n)
    if vorher is None:
        return f"${adresse:x}"
    return f"{vorher[1]}+${adresse - vorher[0]:x}"


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    daten = open(sys.argv[1], "rb").read()
    marken = karte_lesen(sys.argv[2])
    kennung, takt, fach, faecher, sekunden = struct.unpack_from(">4sHHHH", daten, 0)
    if kennung != b"AMES":
        sys.exit("keine Messdatei (Kennung AMES fehlt)")
    blits, anzeige, sonst, fremd = struct.unpack_from(">LLLL", daten, 12)
    bl_anzahl, bl_schnell, bl_fremd, k2_fremd = struct.unpack_from(">HHHH", daten, 28)
    werte = struct.unpack_from(f">{faecher}L", daten, 36)
    verlauf_ab = 36 + 4 * faecher
    verlauf = [struct.unpack_from(">HHH", daten, verlauf_ab + 6 * i) for i in range(sekunden)]

    gesamt = blits + anzeige + sonst
    print(f"Proben: {gesamt} ({gesamt / takt:.0f} s bei {takt}/s), außerhalb des Programms: {fremd}")
    for name, n in (("Blits", blits), ("Anzeige", anzeige), ("Thalion/sonst", sonst)):
        print(f"  {name:14s} {n:8d}  {100 * n / max(gesamt, 1):5.1f} %")
    print(f"Amiga-Blits: {bl_anzahl} (Zähler läuft bei 65536 über), schnell: {bl_schnell}, "
          f"nicht unterstützt: {bl_fremd}, K2 fremd: {k2_fremd}")

    # Fächer zu Routinen zusammenfassen
    je_routine = {}
    for i, n in enumerate(werte):
        if not n:
            continue
        name = name_von(marken, i * fach).split("+")[0]
        je_routine[name] = je_routine.get(name, 0) + n
    print("\nNach Routinen (Marke der Karte):")
    for name, n in sorted(je_routine.items(), key=lambda x: -x[1])[:20]:
        print(f"  {name:24s} {n:8d}  {100 * n / max(gesamt, 1):5.1f} %")
    print("\nVollste Fächer:")
    for i in sorted(range(faecher), key=lambda i: -werte[i])[:20]:
        if not werte[i]:
            break
        print(f"  ${i * fach:05x}  {name_von(marken, i * fach):28s} {werte[i]:8d}  "
              f"{100 * werte[i] / max(gesamt, 1):5.1f} %")

    block_ab = verlauf_ab + 6 * sekunden
    if daten[block_ab:block_ab + 4] == b"BSTA":
        eintraege = struct.unpack_from(">H", daten, block_ab + 4)[0]
        statistik(daten, block_ab, gesamt, blits)
        block_ab += 8 + 16 * eintraege
    bilder = None
    if daten[block_ab:block_ab + 4] == b"VBLS":
        vbls = struct.unpack_from(">L", daten, block_ab + 4)[0]
        block_ab += 8
        takte = None
        if daten[block_ab:block_ab + 4] == b"H200":
            takte = struct.unpack_from(">L", daten, block_ab + 4)[0]
            block_ab += 8
        if daten[block_ab:block_ab + 4] == b"BILD":
            n = struct.unpack_from(">H", daten, block_ab + 4)[0]
            bilder = [struct.unpack_from(">HHHH", daten, block_ab + 8 + 8 * i)
                      for i in range(min(n, sekunden))]
        if takte:
            laufzeit = takte / 200
            print(f"\nEchte Laufzeit (Uhr des TOS): {takte} Takte = {laufzeit:.1f} s; "
                  f"{vbls} VBLs, also {vbls / laufzeit:.1f} Hz Bildfrequenz.")
        else:
            laufzeit = vbls / 50
            print(f"\nEchte Laufzeit: {vbls} VBLs = {laufzeit:.1f} s bei 50 Hz (bei 60 Hz: "
                  f"{vbls / 60:.1f} s).  Ohne H200-Block ist die Bildfrequenz unbekannt.")
        erwartet = laufzeit * takt
        print(f"Erwartet {erwartet:.0f} Proben, da {gesamt}: "
              f"{100 * (1 - gesamt / max(erwartet, 1)):.1f} % fehlen, so lange war Timer A "
              f"aufgehalten (HOG-Blits halten die CPU an).  Eine Messsekunde ist dann "
              f"entsprechend laenger als eine echte.")

    if bilder:
        n = sum(z[0] for z in bilder)
        print(f"\nBilder (Fantasy-Intro, Takt 3 VBL): {n}, knapp {sum(z[1] for z in bilder)}, "
              f"zu spaet {sum(z[2] for z in bilder)}")

    if "--verlauf" in sys.argv:
        print("\nVerlauf je Sekunde (Blits / Anzeige / sonst, in Prozent):")
        if bilder:
            print("  (dahinter Bilder, knapp, zu spaet, mittleres vindex beim Fertigwerden)")
        for s, (b, a, r) in enumerate(verlauf):
            summe = max(b + a + r, 1)
            zeile = f"  {s:4d} s  {100 * b / summe:5.1f} {100 * a / summe:5.1f} {100 * r / summe:5.1f}"
            if bilder and s < len(bilder):
                bi, kn, sp, vi = bilder[s]
                zeile += f"   {bi:3d} {kn:3d} {sp:3d}  {vi / max(bi, 1):4.2f}"
            print(zeile)


def art_text(art):
    """Art aus Bs_zaehlen: BLTCON0 Bits 0-11, 12 DESC, 13 Linie/Fuellen,
    14 ASH > 0, 15 C = D."""
    kanaele = "".join(k for b, k in ((11, "A"), (10, "B"), (9, "C"), (8, "D")) if art >> b & 1)
    merkmale = [f"${art & 0xFF:02X}", kanaele or "-"]
    if art >> 12 & 1:
        merkmale.append("ab")
    if art >> 13 & 1:
        merkmale.append("Linie/Fuellen")
    if art >> 14 & 1:
        merkmale.append("ASH")
    if art >> 15 & 1:
        merkmale.append("C=D")
    return " ".join(merkmale)


def statistik(daten, ab, gesamt, blits):
    eintraege, ueberlauf = struct.unpack_from(">HH", daten, ab + 4)
    zeilen = [struct.unpack_from(">HHLLL", daten, ab + 8 + 16 * i) for i in range(eintraege)]
    print(f"\nBlit-Arten ({eintraege}, Ueberlauf {ueberlauf}), nach Proben:")
    print(f"  {'Minterm Kanaele Merkmale':32s} {'Blits':>8s} {'Worte':>10s} {'W/Blit':>7s} "
          f"{'breit':>5s} {'Proben':>7s} {'ges.':>6s} {'Blits':>6s}")
    for art, breit, anzahl, worte, proben in sorted(zeilen, key=lambda z: -z[4]):
        print(f"  {art_text(art):32s} {anzahl:8d} {worte:10d} {worte / max(anzahl, 1):7.1f} "
              f"{breit:5d} {proben:7d} {100 * proben / max(gesamt, 1):5.1f}% "
              f"{100 * proben / max(blits, 1):5.1f}%")


if __name__ == "__main__":
    main()

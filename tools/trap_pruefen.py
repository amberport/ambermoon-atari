#!/usr/bin/env python3
"""Unser Code ruft TOS nur ueber die Makros Gemdos, Bios, Xbios (Erkenntnis 270).

GEMDOS (trap #1), BIOS (#13) und XBIOS (#14) duerfen d0-d2/a0-a2 zerstoeren.
Ein nackter Trap in engine/src bricht den Bau ab; erlaubt ist er nur in den
Makros selbst (FALCON_OFF.S).  Thalions Dateien liegen nicht in engine/src
und werden nicht geprueft.
"""
import glob, os, re, sys

WURZEL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "engine", "src")
MUSTER = re.compile(r"^\s*(?:[\w.]+:)?\s*trap\s+#(1|13|14)\b", re.I)

funde = []
for pfad in sorted(glob.glob(os.path.join(WURZEL, "**", "*"), recursive=True)):
    if not os.path.isfile(pfad) or not pfad.upper().endswith((".S", ".I")):
        continue
    name = os.path.relpath(pfad, WURZEL)
    im_makro = False
    for nr, zeile in enumerate(open(pfad, encoding="latin-1"), 1):
        code = zeile.split(";")[0]
        if re.search(r"\bMACRO\b", code):
            im_makro = True
        elif re.search(r"\bENDM\b", code):
            im_makro = False
        elif MUSTER.match(code) and not (im_makro and name == "FALCON_OFF.S"):
            funde.append(f"  {name}:{nr}: {zeile.strip()}")

if funde:
    print("Nackter TOS-Aufruf -- Gemdos/Bios/Xbios benutzen (FALCON_OFF.S, Erkenntnis 270):")
    print("\n".join(funde))
    sys.exit(1)
print("  TOS-Aufrufe: alle ueber Gemdos/Bios/Xbios.")

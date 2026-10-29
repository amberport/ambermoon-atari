#!/usr/bin/env python3
"""
spielstand_setzen.py -- einen Spielstand auf eine andere Karte setzen (Test).

Für Tests, die eine Stelle weiter hinten im Spiel brauchen (T3: Kartenwechsel
3D -> 3D; E3: Himmel in einer 3D-Stadt).  Thalions `Save.00` bis `Save.10`
sind alle "Neues Spiel" (Karte 258), also wird ein vorhandener Spielstand
kopiert und nur Karte, Lage und Blickrichtung geändert.

**Nur zum Testen.**  Das ist ein Sprung ohne die Ereignisse dazwischen:
Quests, Türen und Gruppe bleiben, wie sie im Quellstand waren.  Am Spielcode
ändert sich nichts; geändert werden nur Kopien der Spielstanddateien.

Aufbau (Thalions MAIN.S ab `Party_data:`, Erkenntnis 251):

    Party_data.sav   "JH", Schlüsselwort, dann JH-verschlüsselt (ambtool.py)
      +10  w  Map_nr
      +12  w  Map_Xcoord        ab 1
      +14  w  Map_Ycoord        ab 1
      +16  w  View_direction    0 Norden, 1 Osten, 2 Süden, 3 Westen
      +60  w  Travel_mode       0 = zu Fuß
    Saves            w  letzter Platz, dann 10 Namen zu je 39 Byte (Thalion
                     wählt einen Platz nur, wenn sein Name nicht leer ist)

Aufruf:

    python3 tools/spielstand_setzen.py --ziel ORDNER --platz 9 \\
        --karte 260 --x 28 --y 8 --richtung 0 --name "T3 HOEHLE" \\
        [--quelle ORDNER] [--saves DATEI]

--quelle  Ordner mit den fünf Spielstanddateien (Amiga- oder Atari-Namen);
          Vorgabe $AMBER_DATEN/Amberfiles/Save.00
--ziel    hier entsteht SAVE.nn mit Atari-Namen (as in ATARI/AMBFILES)
--saves   eine Kopie von SAVES: Name des Platzes und letzter Platz werden
          gesetzt (WEITERSPIELEN lädt ihn dann).  Ohne: SAVES bleibt, wie es
          ist, und der Platz braucht auf dem Atari schon einen Namen.

Spielstände kommen nie ins Repository (.gitignore).
"""

import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ambtool  # noqa: E402
import ambmap   # noqa: E402
import paths  # noqa: E402

# Amiga name -> Atari name, as in build_common.sh
DATEIEN = [("Party_data.sav", "PARTYDAT.SAV"),
           ("Party_char.amb", "PARTYCHR.AMB"),
           ("Chest_data.amb", "CHESTDAT.AMB"),
           ("Merchant_data.amb", "MERCHANT.AMB"),
           ("Automap.amb", "AUTOMAP.AMB")]

MAP_NR, MAP_X, MAP_Y, RICHTUNG, TRAVEL_MODE = 10, 12, 14, 16, 60
NAME_LAENGE = 38            # Save_name_length (GAME_OFF.S)
PLAETZE = 10
RICHTUNGEN = "NOSW"

KARTENDATEIEN = ("1Map_data.amb", "2Map_data.amb", "3Map_data.amb")


def daten_ordner():
    return paths.amberfiles()


def karte_laden(nr):
    """Die Karte nr; der Eintrag im Behälter ist die Kartennummer selbst."""
    for f in KARTENDATEIEN:
        _, eintraege = ambtool.unpack(open(os.path.join(daten_ordner(), f),
                                           "rb").read())
        if nr <= len(eintraege) and eintraege[nr - 1] and \
                len(eintraege[nr - 1]) >= ambmap.TILE_OFFSET:
            return ambmap.parse_map(eintraege[nr - 1])
    sys.exit(f"Karte {nr} gibt es nicht")


def quelldatei(ordner, amiga, atari):
    for n in (atari, amiga):
        p = os.path.join(ordner, n)
        if os.path.isfile(p):
            return p
    sys.exit(f"{amiga} / {atari} fehlt in {ordner}")


def jh_auf(roh):
    if roh[:2] != b"JH":
        sys.exit("Party_data.sav ist nicht JH-verschlüsselt")
    w0, w1 = struct.unpack(">HH", roh[:4])
    return roh[:4], bytearray(ambtool.jh_decrypt(roh[4:], w0 ^ w1))


def jh_zu(kopf, daten):
    w0, w1 = struct.unpack(">HH", kopf)
    return kopf + ambtool.jh_decrypt(bytes(daten), w0 ^ w1)   # XOR: symmetrisch


def main():
    a = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    a.add_argument("--quelle", default=None)
    a.add_argument("--ziel", required=True)
    a.add_argument("--platz", type=int, required=True)
    a.add_argument("--karte", type=int, required=True)
    a.add_argument("--x", type=int, required=True)
    a.add_argument("--y", type=int, required=True)
    a.add_argument("--richtung", type=int, default=0, choices=range(4))
    a.add_argument("--name", default=None)
    a.add_argument("--saves", default=None)
    o = a.parse_args()

    if not 1 <= o.platz <= PLAETZE:
        sys.exit("--platz 1..10 (0 ist die Vorlage \"Neues Spiel\")")
    quelle = o.quelle or os.path.join(daten_ordner(), "Save.00")

    m = karte_laden(o.karte)
    art = {1: "3D", 2: "2D"}.get(m["type"], "?")
    if not (1 <= o.x <= m["width"] and 1 <= o.y <= m["height"]):
        sys.exit(f"({o.x},{o.y}) liegt nicht in Karte {o.karte} "
                 f"({m['width']}x{m['height']})")
    kachel = (o.y - 1) * m["width"] + (o.x - 1)
    if m["type"] == 1 and m["wall"][kachel]:
        print(f"Warnung: auf ({o.x},{o.y}) steht Wand/Objekt "
              f"{m['wall'][kachel]}", file=sys.stderr)

    ziel = os.path.join(o.ziel, "SAVE.%02d" % o.platz)
    os.makedirs(ziel, exist_ok=True)
    for amiga, atari in DATEIEN:
        roh = open(quelldatei(quelle, amiga, atari), "rb").read()
        if atari == "PARTYDAT.SAV":
            kopf, d = jh_auf(roh)
            alt = struct.unpack(">4H", d[MAP_NR:MAP_NR + 8])
            struct.pack_into(">4H", d, MAP_NR, o.karte, o.x, o.y, o.richtung)
            if struct.unpack(">H", d[TRAVEL_MODE:TRAVEL_MODE + 2])[0]:
                print("Warnung: Travel_mode ist nicht 0 (zu Fuß)",
                      file=sys.stderr)
            roh = jh_zu(kopf, d)
        open(os.path.join(ziel, atari), "wb").write(roh)

    if o.saves:
        s = bytearray(open(o.saves, "rb").read())
        if len(s) != 2 + PLAETZE * (NAME_LAENGE + 1):
            sys.exit(f"{o.saves}: unerwartete Länge {len(s)}")
        name = (o.name or "TEST").encode("ascii")[:NAME_LAENGE]
        p = 2 + (o.platz - 1) * (NAME_LAENGE + 1)
        s[p:p + NAME_LAENGE + 1] = name.ljust(NAME_LAENGE + 1, b"\0")
        struct.pack_into(">H", s, 0, o.platz)
        open(o.saves, "wb").write(s)

    print(f"{ziel}: Karte {alt[0]} ({alt[1]},{alt[2]}) -> Karte {o.karte} "
          f"({art}, {m['width']}x{m['height']}) ({o.x},{o.y}) Blick "
          f"{RICHTUNGEN[o.richtung]}" +
          (f"; {o.saves}: Platz {o.platz} \"{o.name or 'TEST'}\", zuletzt"
           if o.saves else ""))


if __name__ == "__main__":
    main()

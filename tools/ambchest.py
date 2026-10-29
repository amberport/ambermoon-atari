#!/usr/bin/env python3
"""
ambchest.py -- Truhen, Gegenstaende und ihre Symbole.

Die Aufteilung folgt dem Original: Chest_data.amb liegt im Verzeichnis des
Spielstands, weil sich sein Inhalt aendert, sobald jemand eine Truhe leert.
Objects.amb und Object_icons gehoeren zu den festen Spieldaten.

Alle Offsets stammen aus GAME_OFF.S des freigegebenen Thalion-Quelltexts,
Abschnitte "offsets for the chest data", "offsets for the object packets"
und "offsets for the object data".
"""

import struct

# --- Objektpaket, 6 Byte -----------------------------------------------
# Quantity, Charges, Enchantment_normal, Item_bits_DYNAMIC, Object_index.w
OBJECT_PACKET_SIZE = 6

# --- Truhendaten -------------------------------------------------------
# 24 Objektpakete, dann Gold und Nahrung als Wort.  Macht 148 Byte, und
# genau diese Groesse haben alle 185 belegten Eintraege von Chest_data.amb.
ITEMS_PER_CHEST = 24
CHEST_GOLD = ITEMS_PER_CHEST * OBJECT_PACKET_SIZE      # 144
CHEST_FOOD = CHEST_GOLD + 2                            # 146
CHEST_DATA_SIZE = CHEST_FOOD + 2                       # 148

# --- Gegenstandsdaten --------------------------------------------------
ITEM_DATA_SIZE = 60
ITEM_PIC = 0            # Nummer des Symbols in Object_icons, ab 0
ITEM_TYPE = 1
ITEM_BITS_STATIC = 32     # rsreset in GAME_OFF.S: 32 Byte stehen davor
ITEM_PRICE = 36         # Wort
ITEM_WEIGHT = 38        # Wort
ITEM_NAME = 40          # 19 Byte, mit 0 abgeschlossen
ITEM_NAME_LEN = 19

# Objects.amb beginnt mit einem Wort, das die Zahl der Gegenstaende nennt.
# Bei der deutschen Fassung 1.20 steht dort 0x0192 = 402, und 2 + 402*60
# ergibt exakt die Dateigroesse von 24122 Byte.  Der Quelltext greift mit
# "lea.l Object_data+4,a0" zu; im Speicher liegen vor der Tabelle also noch
# zwei weitere Byte, die die Datei selbst nicht hat.
OBJECT_HEADER = 2

# --- Symbole -----------------------------------------------------------
ICON_W = ICON_H = 16
ICON_PLANES = 5
ICON_SIZE = ICON_W // 8 * ICON_PLANES * ICON_H         # 160
# 30080 Byte / 160 = 188 Symbole, ohne Rest.

# --- 80x80-Bilder ------------------------------------------------------
# Alle 22 Eintraege von Pics_80x80.amb sind 4000 Byte gross, was bei 80x80
# genau fuenf Bitebenen ergibt.
PIC_W = PIC_H = 80
PIC_PLANES = 5
PIC_SIZE = PIC_W // 8 * PIC_PLANES * PIC_H             # 4000

# Nummern aus dem Abschnitt "These are the 80 x 80 pictures".  Gezaehlt wird
# ab 1, der erste Platz der Liste ist unbenutzt.
CLOSED_CHEST_PIC = 1
EMPTY_CHEST_PIC = 3
OPENED_CHEST_PIC = 11
TRASHPILE_PIC = 15

CHEST_PICS = (CLOSED_CHEST_PIC, EMPTY_CHEST_PIC,
              OPENED_CHEST_PIC, TRASHPILE_PIC)

# Chest_layout aus dem Abschnitt "These are the layouts": der vierte Platz,
# gezaehlt ab 0, also Layout 3 in Layouts.amb.
CHEST_LAYOUT = 3


def parse_chest(data):
    """Ein Eintrag aus Chest_data.amb -> dict.

    Leere Plaetze haben Object_index 0 und werden uebergangen; das Original
    prueft in OpenedChest_ModInit genauso, ob ueberhaupt etwas drin ist.
    """
    if len(data) < CHEST_DATA_SIZE:
        raise ValueError("Truhendaten zu kurz: %d Byte" % len(data))
    objekte = []
    for i in range(ITEMS_PER_CHEST):
        o = i * OBJECT_PACKET_SIZE
        anz, lad, ver, bits, idx = struct.unpack(">BBBBH", data[o:o + 6])
        if idx:
            objekte.append(dict(slot=i, index=idx, count=anz, charges=lad,
                                enchantment=ver, bits=bits))
    gold, nahrung = struct.unpack(">HH", data[CHEST_GOLD:CHEST_DATA_SIZE])
    return dict(objects=objekte, gold=gold, food=nahrung,
                empty=not objekte and not gold and not nahrung)


def parse_objects(data):
    """Objects.amb -> Liste von dicts, Listenplatz 0 ist Gegenstand 1.

    Die Namen bleiben rohe Bytes.  Sie sind in der Kodierung des Spiels
    geschrieben, die der Zeichensatz mit seiner eigenen Tabelle aufloest --
    0x8E ist Ae, 0x99 Oe, 0x9A Ue, 0x9E ss.  Wer sie hier nach Unicode
    wandelt, muss sie fuer die Anzeige zurueckwandeln.
    """
    n = struct.unpack(">H", data[:OBJECT_HEADER])[0]
    erwartet = OBJECT_HEADER + n * ITEM_DATA_SIZE
    if erwartet != len(data):
        raise ValueError("Objects.amb: Kopf nennt %d Gegenstaende, das waeren "
                         "%d Byte, die Datei hat %d" % (n, erwartet, len(data)))
    out = []
    for i in range(n):
        o = OBJECT_HEADER + i * ITEM_DATA_SIZE
        p = data[o:o + ITEM_DATA_SIZE]
        preis, gewicht = struct.unpack(">HH", p[ITEM_PRICE:ITEM_PRICE + 4])
        out.append(dict(
            index=i + 1,
            pic=p[ITEM_PIC],
            type=p[ITEM_TYPE],
            bits=p[ITEM_BITS_STATIC],
            price=preis,
            weight=gewicht,
            name=p[ITEM_NAME:ITEM_NAME + ITEM_NAME_LEN].split(b"\0")[0],
        ))
    return out


def chest_events(m):
    """Die Truhenereignisse einer Karte -> Liste von dicts.

    Ereignistyp 3 ist Item_found.  Die Bedeutung der Bytes steht in
    EVENTS.S; b4 ist die Nummer, die zugleich das Bit im Chest-Bitfeld und
    den Eintrag in Chest_data.amb waehlt.
    """
    out = []
    for ev in (m.get("events") or []):
        if ev["type"] != 3:
            continue
        d = ev["data"]                 # Event_b1 bis Event_b9
        out.append(dict(
            event=ev["index"],
            locked=d[0],               # Schloss in Prozent
            hidden=d[1],               # braucht eine Suchen-Probe
            number=d[3],               # Event_b4
            pile=bool(d[4] & 1),       # Haufen statt Truhe
            keep=bool(d[4] & 2),       # Inhalt nicht zurueckschreiben
            trap=struct.unpack(">H", d[7:9])[0],   # Event_w8, FFFF = keine
        ))
    return out


def chest_entry(nummern, truhen):
    """Die Truhen einer Karte fuer die Szenendatei packen.

    Aufbau, wortorientiert wie alles andere in der Szenendatei:

        +0   Anzahl
        +2   je Truhe: Nummer.w, dann 148 Byte Truhendaten

    Der Versatz um eins ist die Stelle, an der man sich verrechnet:
    Load_subfile im Original holt Eintrag b4+1, und die Eintraege zaehlen
    ab 1.  In einer Liste ab 0 ist das schlicht Index b4 -- das "; !!!"
    hinter dem "addq.w #1,d0" im Quelltext warnt genau davor.
    """
    teile = [struct.pack(">H", len(nummern))]
    for nr in nummern:
        if nr >= len(truhen) or len(truhen[nr]) < CHEST_DATA_SIZE:
            raise ValueError("Truhe %d fehlt in Chest_data.amb" % nr)
        teile.append(struct.pack(">H", nr))
        teile.append(truhen[nr][:CHEST_DATA_SIZE])
    return b"".join(teile)


def object_names_entry(objekte):
    """Die Namen aller Gegenstaende als feste Saetze zu 19 Byte.

    Feste Laenge statt Zeigertabelle: das Nachschlagen ist dann eine
    Multiplikation, und 402 mal 19 Byte sind keine 8 KB.
    """
    teile = [struct.pack(">2H", len(objekte), ITEM_NAME_LEN)]
    for o in objekte:
        nm = o["name"][:ITEM_NAME_LEN]
        teile.append(nm + b"\0" * (ITEM_NAME_LEN - len(nm)))
    return b"".join(teile)


def object_table_entry(objekte):
    """Was die Engine je Gegenstand braucht, ohne die Kampfwerte: Symbol,
    Art, Merker, Preis, Gewicht.  Acht Byte je Eintrag."""
    teile = [struct.pack(">H", len(objekte))]
    for o in objekte:
        teile.append(struct.pack(">BBBBHH", o["pic"], o["type"], o["bits"],
                                 0, o["price"], o["weight"]))
    return b"".join(teile)


# ---------------------------------------------------------------------------
# Gegenprobe gegen Thalions GAME_OFF.S
#
# Die Versaetze oben sind aus dem rsreset "These are the offsets for the
# object data" abgeschrieben, und genau dabei ist ein Fehler entstanden:
# ITEM_BITS_STATIC stand auf 33 statt auf 32, also auf
# Item_bits_DYNAMIC_init.  Aufgefallen ist er nur, weil danach kein einziger
# von 402 Gegenstaenden mehr stapelbar war (Erkenntnis 116).
#
# Die Engine prueft ihre Konstanten seit dem Umstieg auf vlink zur
# Uebersetzungszeit gegen Thalions Datei.  Hier geht das genauso: den
# rsreset lesen und nachrechnen.  Wo der Quelltext liegt, sagt AMBER_URCODE.
# Fehlt er, wird die Probe uebersprungen -- sie ist eine Zugabe, keine
# Voraussetzung.
# ---------------------------------------------------------------------------

def _thalion_offsets(pfad=None):
    """Den Objekt-rsreset aus Thalions GAME_OFF.S lesen -> {Name: Versatz}."""
    import os
    import re
    import paths
    if pfad is None:
        pfad = paths.urcode()
    datei = os.path.join(pfad, "GAME_OFF.S")
    if not os.path.isfile(datei):
        return None
    text = open(datei, encoding="latin1").read()
    anfang = text.index("; These are the offsets for the object data")
    block = text[anfang:text.index("Item_data_size:", anfang) + 40]
    aus, versatz = {}, 0
    breite = {"b": 1, "w": 2, "l": 4}
    for m in re.finditer(r"^(\w*):?\s*rs\.([bwl])\s+(\d+)", block, re.M):
        name, art, anzahl = m.group(1), m.group(2), int(m.group(3))
        if name:
            aus[name] = versatz
        versatz += anzahl * breite[art]
    return aus


def pruefe_gegen_original(pfad=None):
    """Vergleicht unsere ITEM_*-Versaetze mit Thalions rsreset.

    Gibt die Liste der Abweichungen zurueck; leer heisst: alles stimmt.
    None heisst: Thalions Quelltext war nicht auffindbar.
    """
    thalion = _thalion_offsets(pfad)
    if thalion is None:
        return None
    paare = [("ITEM_PIC", ITEM_PIC, "Item_pic"),
             ("ITEM_TYPE", ITEM_TYPE, "Item_type"),
             ("ITEM_BITS_STATIC", ITEM_BITS_STATIC, "Item_bits_STATIC"),
             ("ITEM_PRICE", ITEM_PRICE, "Price"),
             ("ITEM_WEIGHT", ITEM_WEIGHT, "Weight"),
             ("ITEM_NAME", ITEM_NAME, "Item_name")]
    schlecht = []
    for name, wert, thname in paare:
        soll = thalion.get(thname)
        if soll is None:
            schlecht.append("%s: %s steht nicht in Thalions rsreset"
                            % (name, thname))
        elif soll != wert:
            schlecht.append("%s ist %d, Thalions %s liegt auf %d"
                            % (name, wert, thname, soll))
    return schlecht


if __name__ == "__main__":
    ergebnis = pruefe_gegen_original()
    if ergebnis is None:
        print("Thalions Quelltext nicht gefunden -- Probe uebersprungen.")
    elif ergebnis:
        for zeile in ergebnis:
            print("  ABWEICHUNG: " + zeile)
        raise SystemExit(1)
    else:
        print("Alle ITEM_*-Versaetze stimmen mit Thalions GAME_OFF.S ueberein.")

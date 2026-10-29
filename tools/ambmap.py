#!/usr/bin/env python3
"""
ambmap.py -- Kartenstruktur von Ambermoon (XMap_data.amb).

2D- und 3D-Karten teilen sich das Dateiformat und unterscheiden sich nur in
der Groesse der Kacheldaten: 4 Byte je Kachel in 2D, 2 Byte in 3D.

Aufbau
======
    0x0000  w   Flags
    0x0002  b   Typ (1 = 3D, 2 = 2D; 0 waere das alte 2D-Format, unbenutzt)
    0x0003  b   Musiknummer
    0x0004  b   Breite in Kacheln
    0x0005  b   Hoehe in Kacheln
    0x0006  b   Tileset (2D) bzw. Labdata-Index (3D)
    0x0007  b   NPC-Grafiksatz
    0x0008  b   Labyrinth-Hintergrund (3D) bzw. Reisegrafik (2D)
    0x0009  b   Palette
    0x000A  b   Welt (0 Lyramion, 1 Waldmond, 2 Wuestenmond)
    0x000B  b   Fuellbyte
    0x000C  32 x 10 Byte  Charakterverweise
    0x014C  Kacheldaten
            w   Anzahl Ereignisketten
            w[] Index des jeweils ersten Ereignisses
            w   Anzahl Ereignisse
            12 Byte je Ereignis
            Charakterpositionen
            w   Anzahl Zielpunkte, danach 20 Byte je Punkt

Kachelkodierung 2D
==================
Vier Byte je Kachel:

    unterlage = b0                  8 Bit
    ereignis  = b1                  Nummer der Ereigniskette
    ueberlage = (b2 << 8) | b3     16 Bit

Belegt am Amiga-Bildschirm eines FS-UAE-Speicherauszugs: an drei
benachbarten Stellen laufen b3 = 146, 147, 148 und die tatsaechlich
angezeigten Grafiken 371, 372, 373 -- konstante Differenz.  Aufgeloest ueber
Icon_data ergibt (b2<<8)|b3 die Definitionen 402, 403, 404, und die zeigen
exakt auf jene Grafiken.

Gegenprobe an allen 271 zweidimensionalen Karten:
  * von 589173 Ueberlage-Werten liegt genau einer ueber den 2500
    Definitionen -- an der letzten Kachel von Karte 167, also Randmuell.
  * das Maximum von b1 ueberschreitet auf keiner einzigen Karte die Anzahl
    ihrer Ereignisketten.

**Frueherer Irrtum:** Pyrdacors Dokumentation beschreibt zwei 12-Bit-Indizes,
deren obere Bits sich Byte 1 teilen, und Byte 3 als Ereignisfeld.  Damit
gerendert sieht eine Karte ueberzeugend aus, weil die haeufigste Bodenkachel
(49) unter beiden Lesarten stimmt -- nur 48 von 81 Kacheln des Ausschnitts
waren pixelgenau richtig.  Ein Bild, das plausibel aussieht, ist kein Beleg.

Index 0 bedeutet "keine Kachel".  Alle anderen Indizes sind 1-basiert.

Abweichung von der Originaldokumentation
========================================
`MAP_FILE.TXT` (Thalion, Stand 1993) beschreibt die Kacheldaten als drei
getrennte Schichten und fuehrt nach den Ereignisketten ein Byte-Feld
("Event save number") auf.  Beides trifft auf die ausgelieferten Daten nicht
zu: die Kacheln sind verschachtelt, und mit dem Byte-Feld ergeben sich
unsinnige Ereigniszahlen (270 statt 18).  Ohne es liegen alle Ereignistypen
im gueltigen Bereich 1..23 und alle Verkettungen im Feld.
"""

import struct

TYPE_3D = 1
TYPE_2D = 2

TILE_OFFSET = 0x14C
CHAR_COUNT = 32
CHAR_SIZE = 10

WORLDS = {0: "Lyramion", 1: "Waldmond", 2: "Wuestenmond"}

FLAGS = {
    0: "Innen", 1: "Aussen", 2: "Verlies", 3: "Automap", 4: "Rasten",
    5: "Wildnis", 6: "Stadt", 7: "Dungeon", 8: "Reisen", 9: "U-Boot",
    10: "Weltoberflaeche", 11: "Zauber erlaubt", 12: "Keine Reisemusik",
    13: "Kein Markieren", 14: "Kein Adler/Besen", 15: "Kachelquelle",
}

EVENT_TYPES = {
    1: "Kartenwechsel", 2: "Tuer", 3: "Truhe", 4: "Textfenster",
    5: "Dreher", 6: "Schaden/Falle", 7: "Segen entfernen", 8: "Raetselmaul",
    9: "Belohnung", 10: "Kachel aendern", 11: "Kampf", 12: "Ort betreten",
    13: "Bedingung", 14: "Aktion", 15: "Wuerfelwurf", 16: "Gespraech",
    17: "Text ausgeben", 18: "Erzeugen", 19: "Ja/Nein-Frage",
    20: "Musikwechsel", 21: "Ende", 22: "Fahrzeug", 23: "Interaktion",
}

CHAR_KINDS = {0: "Gruppe", 1: "NSC", 2: "Monster", 3: "Objekt"}


def flag_names(flags):
    return [FLAGS[b] for b in range(16) if flags & (1 << b) and b in FLAGS]


def parse_characters(data):
    out = []
    for i in range(CHAR_COUNT):
        o = i * CHAR_SIZE
        index, travel, tf, event = data[o:o + 4]
        gfx = struct.unpack(">H", data[o + 4:o + 6])[0]
        tile_flags = struct.unpack(">I", data[o + 6:o + 10])[0]
        if index == 0:
            continue
        out.append(dict(slot=i, index=index, travel=travel,
                        kind=CHAR_KINDS[tf & 3], flags=tf >> 2,
                        event=event, gfx=gfx, tile_flags=tile_flags))
    return out


def parse_events(data, o):
    """Ereignisketten und Ereignisse ab Offset o.  Gibt (dict, neuer Offset)."""
    if o + 2 > len(data):
        return dict(chains=[], events=[]), o
    n = struct.unpack(">H", data[o:o + 2])[0]
    o += 2
    if o + 2 * n > len(data):          # beschaedigte oder gekuerzte Karte
        return dict(chains=[], events=[]), len(data)
    chains = list(struct.unpack(f">{n}H", data[o:o + 2 * n])) if n else []
    o += 2 * n
    if o + 2 > len(data):
        return dict(chains=chains, events=[]), o
    m = struct.unpack(">H", data[o:o + 2])[0]
    o += 2
    events = []
    for i in range(m):
        e = data[o:o + 12]
        if len(e) < 12:
            break
        events.append(dict(index=i, type=e[0],
                           name=EVENT_TYPES.get(e[0], "?"),
                           data=e[1:10],
                           next=struct.unpack(">H", e[10:12])[0]))
        o += 12
    return dict(chains=chains, events=events), o


def parse_map(data):
    (flags, typ, music, w, h, tileset, npc_gfx,
     lab_bg, palette, world, _pad) = struct.unpack(">HBBBBBBBBBB", data[:12])

    m = dict(flags=flags, flag_names=flag_names(flags), type=typ,
             music=music, width=w, height=h, tileset=tileset,
             npc_gfx=npc_gfx, lab_background=lab_bg,
             # Bei 2D-Karten waehlt dasselbe Byte den Figurensatz aus
             # Party_gfx.amb -- Innenkarten nutzen 0, die Weltkarte 1.
             travel_gfx=lab_bg, palette=palette,
             world=world, world_name=WORLDS.get(world, "?"),
             characters=parse_characters(data[0x0C:0x0C + 320]))

    n = w * h
    bpt = 2 if typ == TYPE_3D else 4
    blk = data[TILE_OFFSET:TILE_OFFSET + bpt * n]
    if len(blk) < bpt * n:
        raise ValueError("Kacheldaten unvollstaendig: %d < %d"
                         % (len(blk), bpt * n))

    if typ == TYPE_3D:
        m["wall"] = list(blk[0::2])
        m["event"] = list(blk[1::2])
        m["underlay"] = m["overlay"] = None
    else:
        b2 = blk[2::4]
        b3 = blk[3::4]
        m["underlay"] = list(blk[0::4])
        m["event"] = list(blk[1::4])
        m["overlay"] = [(b2[i] << 8) | b3[i] for i in range(n)]
        m["wall"] = None

    ev, o = parse_events(data, TILE_OFFSET + bpt * n)
    m.update(ev)
    m["tail"] = len(data) - o

    # Hinter den Ereignissen liegen die Wege der Charaktere: je 288
    # Positionen zu zwei Byte, eine fuer jeden Fuenfminutenabschnitt des
    # Tages.  Nicht jeder Charakter hat einen -- wer keinen hat, steht fest.
    # Die Koordinaten zaehlen ab eins, wie die der Gruppe im Spielstand.
    schritte = 288
    m["paths"] = [data[o + i * schritte * 2:o + (i + 1) * schritte * 2]
                  for i in range((len(data) - o) // (schritte * 2))]
    return m


def load_maps(container_entries):
    """Liste von Containereintraegen -> {Kartennummer: dict}.  Leere Eintraege
    werden uebersprungen."""
    out = {}
    for i, e in enumerate(container_entries):
        if not e or len(e) < TILE_OFFSET:
            continue
        try:
            out[i + 1] = parse_map(e)
        except (ValueError, struct.error):
            continue
    return out


def pack_for_atari(m):
    """Kachelddaten in eine wortorientierte Form fuer den Atari.

        w  Breite, Hoehe, Tileset, Palette, Musik, Welt, Typ, Flags
        w[n]  Unterlage
        w[n]  Ueberlage
        b[n]  Ereignis  (auf gerade Laenge aufgefuellt)

    Der 68000 liest damit Kachelindizes als Wort, ohne Halbbytes
    auseinanderzunehmen -- die Bitfummelei passiert einmal hier statt bei
    jedem Bildaufbau.
    """
    n = m["width"] * m["height"]
    out = bytearray()
    out += struct.pack(">8H", m["width"], m["height"], m["tileset"],
                       m["palette"], m["music"], m["world"], m["type"],
                       m["flags"])
    if m["type"] == TYPE_3D:
        out += struct.pack(f">{n}H", *m["wall"])
        out += b"\0" * (2 * n)
    else:
        out += struct.pack(f">{n}H", *m["underlay"])
        out += struct.pack(f">{n}H", *m["overlay"])
    out += bytes(m["event"])
    out += b"\0" * (len(out) % 2)

    # Ereignisketten und Ereignisse unveraendert anhaengen -- das Format des
    # Originals ist bereits wortorientiert und big-endian, es muss nichts
    # umgerechnet werden.
    #     w      Anzahl Ketten
    #     w[]    Nummer des ersten Ereignisses je Kette
    #     w      Anzahl Ereignisse
    #     12 Byte je Ereignis
    out += struct.pack(">H", len(m["chains"]))
    for c in m["chains"]:
        out += struct.pack(">H", c)
    out += struct.pack(">H", len(m["events"]))
    for e in m["events"]:
        out += bytes([e["type"]]) + bytes(e["data"]) + struct.pack(">H", e["next"])
    return bytes(out)


# --------------------------------------------------------------------------
# Tileset-Definitionen (Icon_data.amb)
# --------------------------------------------------------------------------

def parse_tileset(data):
    """Icon_data-Eintrag -> Liste von Kacheldefinitionen.

        w        Anzahl (immer 2500)
        je 8 Byte:
            l    Flags (Begehbarkeit, Kollisionsklassen, Erscheinung)
            w    Grafikindex im zugehoerigen XIcon_gfx-Satz (1-basiert)
            b    Anzahl Animationsbilder
            b    unbekannt

    **Wichtig:** Karten verweisen auf diese Definitionen, nicht auf die
    Grafiken.  Nur 219 der 2500 Eintraege sind deckungsgleich -- wer die
    Indirektion ueberspringt, bekommt ein Bild, das ueberwiegend stimmt und
    an genau den interessanten Stellen falsch ist.

    Definitionen mit `frames == 0` sind unbenutzte Fuellplaetze; sie zeigen
    alle auf die letzte Grafik und werden nicht gezeichnet.
    """
    n = struct.unpack(">H", data[:2])[0]
    out = []
    for i in range(n):
        o = 2 + i * 8
        flags = struct.unpack(">I", data[o:o + 4])[0]
        gfx = struct.unpack(">H", data[o + 4:o + 6])[0]
        out.append(dict(index=i + 1, flags=flags, gfx=gfx,
                        frames=data[o + 6], unknown=data[o + 7]))
    return out


def resolve(tileset_defs, index):
    """Kachelverweis -> (Grafikindex, Anzahl Bilder) oder (0, 0) fuer leer."""
    if index <= 0 or index > len(tileset_defs):
        return 0, 0
    d = tileset_defs[index - 1]
    if d["frames"] == 0:
        return 0, 0
    return d["gfx"], d["frames"]


def pack_tileset_defs(defs):
    """Kacheldefinitionen fuer den Atari.

        w   Anzahl
        je Eintrag 8 Byte:
            l   Flags (Begehbarkeit, Kollisionsklassen)
            w   Grafikindex, 1-basiert; 0 = leer
            b   Anzahl Animationsbilder
            b   Fuellbyte

    Animationsbilder liegen im Tileset fortlaufend hinter dem Grundbild.  Die
    Engine zeichnet also `gfx + (takt % frames) - 1`; es muss nichts
    dupliziert werden.

    Geprueft ueber alle acht Tilesets: 176 animierte Definitionen, keine
    ueberschreitet die Tilesetgrenze, und keines ihrer Folgebilder wird von
    einer anderen Definition als Einzelkachel beansprucht.
    """
    out = bytearray()
    out += struct.pack(">H", len(defs))
    for d in defs:
        gfx = d["gfx"] if d["frames"] else 0
        out += struct.pack(">IHBB", d["flags"], gfx, d["frames"], 0)
    return bytes(out)


TILESET_FILES = ("1Icon_gfx.amb", "2Icon_gfx.amb", "3Icon_gfx.amb")


def find_tileset_gfx(entries_by_file, number):
    """{Dateiname: Containereintraege} + Tilesetnummer -> (Datei, Rohdaten).

    Tileset k liegt in einer der drei Dateien jeweils an Eintrag k; belegt ist
    es genau einmal.  Welche Datei es ist, steht nirgends -- man sieht es nur
    daran, welcher Eintrag nicht leer ist.
    """
    hits = [(fn, e[number - 1]) for fn, e in entries_by_file.items()
            if len(e) >= number and e[number - 1]]
    if not hits:
        raise ValueError("Tileset %d in keiner Datei belegt" % number)
    if len(hits) > 1:
        raise ValueError("Tileset %d mehrfach belegt: %s"
                         % (number, [f for f, _ in hits]))
    return hits[0]


# --------------------------------------------------------------------------
# Reisegrafiken (Travel_gfx.amb)
# --------------------------------------------------------------------------

TRAVEL_NAMES = ["zu Fuss", "Pferd", "Floss", "Schiff", "Magische Scheibe",
                "Adler", "Fliegen", "Schwimmen", "Wuestenschiff", "Besen",
                "Sandwurm"]


def parse_travel_gfx(data, planes=5, directions=4):
    """Ein Eintrag aus Travel_gfx.amb -> Liste von Bildern je Blickrichtung.

    Jedes Bild traegt einen eigenen Kopf:

        w  Breite in Bloecken zu 16 Pixeln
        w  Hoehe in Zeilen
        w  Versatz in X
        w  Versatz in Y
        dann Breite * Hoehe * 2 * planes Byte Bilddaten

    Der Originalcode ueberspringt Bilder genau so (`2D_MAP.S`,
    Display_2D_party): Breite mal Hoehe mal Screen_depth mal zwei, plus vier
    Byte Kopf.  Die Rechnung geht auf -- Eintrag 1 hat 672 Byte, das sind
    vier Bilder zu je 168.
    """
    out = []
    o = 0
    for _ in range(directions):
        if o + 8 > len(data):
            break
        w, h, ox, oy = struct.unpack(">4h", data[o:o + 8])
        o += 8
        size = w * h * 2 * planes
        out.append(dict(blocks=w, width=w * 16, height=h,
                        offset_x=ox, offset_y=oy,
                        data=data[o:o + size]))
        o += size
    return out

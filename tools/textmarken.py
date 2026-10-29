#!/usr/bin/env python3
"""textmarken.py -- Thalions Textnamen als Marken in Text.amb, beim Bau.

DEVIATION (goal 2), docs/17-deviations.md D5: the positions of the
library's texts inside Text.amb are fixed at build time.

Im Original stehen die Texte der Bibliothek in AM2_CPU: Rassen-, Klassen-
und Zaubernamen, die Vorlagen der Charakterseite ("ALTER:012"), die
Ueberschriften.  Die deutsche Fassung 1.20 traegt sie in ``Text.amb``
(JH-Huelle, LOB).  Thalions Code spricht sie ueber feste Marken an:

    lea.l Race_names,a0 / jsr Find_small_text        ; INVENTOR.S
    lea.l Age_nr,a0 / jsr DecL_convert                ; schreibt in Age_txt
    lea.l Age_txt,a0 / jsr Put_text_line

Die Bibliothek laedt die Datei zur Laufzeit ganz nach ``Textdaten``
(``Lade_texte``, HULL/WORDS_SUP.S; Leitziel 2).  **Wo** darin jeder Name
liegt, steht hier fest, beim Bau: ``Age_nr`` - ``Age_txt`` haengt von der
Sprache ab ("ALTER:012" gegenueber "AGE:012"), Thalion rechnet aber mit
zwei festen Marken.  Eine andere Fassung heisst neu bauen, wie beim
AM2_CPU-Auszug.

**Aufbau von Text.amb 1.20** (ausgepackt 18.526 Byte, nachgerechnet
2026-09-28):

1. ``$0000`` Einzeltexte: Wort Langworte der Texte, Wort Anzahl (46),
   ebenso viele Versatzworte, dann die Texte, je mit Endnull.  Weltnamen,
   Disketten- und Fehlermeldungen, Bausteine fuer Meldungen.
2. ``$05D8`` ``Prompts``: Wort Anzahl, Laengenworte, Texte -- das Format
   von ``Find_large_text`` (Erkenntnis 179).
3. Namenslisten: je ``[Wort n][n Langworte]``, darin Texte mit Endnull --
   das Format von ``Find_small_text``.  Vierzehn Stueck, Reihenfolge
   ``LISTEN``.
4. Einzeltexte: Wort Anzahl Tabellenworte, dann die Tabelle: je Text ein
   Laengenwort, davor fuer jede ``*_nr``-Marke im Text ein Wort
   ``$FFxx`` (xx = Versatz im Text).  Dann die Texte.  Reihenfolge
   ``EINZEL``.
5. Die zwei Versionszeilen, davor zwei Byte (unbekannt), dahinter Nullen.

Die Namen ordnet diese Datei zu, nach Inhalt und Aufrufstellen in
Thalions Quelltext.  Das Werkzeug prueft den Aufbau und bricht ab, wenn er
nicht aufgeht.

Ausgabe ``build/textmarken.i``: ein BSS-Block ``Textdaten`` in
Dateigroesse, Thalions Namen als echte Marken an ihren Versaetzen, dazu
``TEXT_LAENGE``.  Keine Spieldaten, nur Versaetze -- trotzdem nicht ins
Repository (``build/``).

Aufruf:  textmarken.py [--amberfiles DIR] [--out build/textmarken.i]
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import unpack                               # noqa: E402
from am2cpu_auszug import MELDUNG_EINZEL, MELDUNG_TABELLE  # noqa: E402
import paths  # noqa: E402

PROMPT_OFF = 0x05D8

# Teil 1: Einzeltexte nach Nummer.  Jeder bekommt die Marke Textamb_<n>;
# darauf zeigen die Meldungslisten (Recup1_text ...), die am2cpu_auszug.py
# aus AM2_CPU aufbaut.  Einzeltexte, die Thalion selbst als Text anspricht
# ("move.l #Divide_start_text,(a2)+"), bekommen dazu ihren Namen; die
# Zuordnung steht dort (MELDUNG_EINZEL) und ist an AM2_CPU gegengeprueft.
BAUSTEINE = {0: "Weltname_1", 1: "Weltname_2", 2: "Weltname_3"}
BAUSTEINE.update({nr: name for name, nr, _, _ in MELDUNG_EINZEL})
TEIL1_ANZAHL = 46

# Teil 3, in Dateireihenfolge.
LISTEN = [
    "Automap_icon_names",       # Raetselmund, Teleporter ... (AUTOMAPP.S)
    "Option_names",             # Musik, Schneller Kampfmodus ... (ACTIONS.S)
    "Song_names",               # (MAGIC.S)
    "Spell_class_names",        # Heilung, Alchemie ... (INVENTOR.S)
    "Spell_names",              # 7 x 30 (MAGIC.S, INVENTOR.S)
    "Language_names",           # (INVENTOR.S, Schleife ueber Endnullen)
    "Class_names",
    "Race_names",
    "Skill_names",
    "Attribute_names",
    "Short_skill_names",        # ATT PAR ...
    "Short_attr_names",         # STAe INT ...
    "Item_type_names",          # Find_small_text mit Typ-1
    "Condition_names",
]

# Teil 4, in Dateireihenfolge: (Textname oder None, [Namen der $FF-Marken
# in Dateireihenfolge]).  Die Versaetze stehen in der Datei; wo Thalion
# selbst einen festen Versatz nimmt (LP_txt +5/+9, Goldfood_txt +2/+10,
# ProtDam_txt +1, SLP_txt +4, TP_txt +3), passt die Vorlage dazu.
EINZEL = [
    ("APR_txt", []),            # "APR:  " (COMBAT_M.S)
    ("He_txt", []),             # MAIN.S Insert_sex1/2
    ("She_txt", []),
    ("His_txt", []),
    ("Hers_txt", []),
    ("Skills_txt", []),         # Ueberschriften der Charakterseite
    ("Attrs_txt", []),
    ("Language_txt", []),
    ("Conditions_txt", []),
    ("Male_txt", []),
    ("Female_txt", []),
    ("Both_txt", []),
    ("Compass_txt", []),        # DISPLAY.S, MAGIC.S
    ("Age_txt", ["Age_nr"]),    # "ALTER:012"
    ("Skill_txt", []),          # "01%/01%", Thalion schreibt bei 0 und 4
    ("Attr_txt", []),           # "012/012"
    ("EP_txt", []),             # "EP" (MAIN.S Make_levels)
    ("Experience_txt", ["Experience_nr"]),
    ("LP_txt", []),
    ("PP_txt", []),
    ("SLP_txt", []),
    ("TP_txt", []),
    ("Goldfood_txt", []),       # "G:01234 R:0123"
    ("ProtDam_txt", []),        # ": 012"
    ("Gold_txt", []),           # DISPLAY.S
    ("Food_txt", []),
    ("Classes_txt", []),        # Gegenstandsansicht (INVENTOR.S)
    ("Sex_txt", []),
    ("Weight2_txt", ["Weight2_nr"]),
    ("Hands_txt", ["Hands_nr"]),
    ("Fingers_txt", ["Fingers_nr"]),
    ("Damage_txt", ["Damage_nr"]),
    ("Protection_txt", ["Protection_nr"]),
    ("LP_max_txt", ["LP_max_nr"]),
    ("PP_max_txt", ["PP_max_nr"]),
    ("MBW_txt", ["MBW_nr"]),    # " M-B-W: 01"
    ("MBA_txt", ["MBA_nr"]),    # " M-B-R: 01"
    ("Attr2_txt", []),
    ("Skill2_txt", []),
    ("Cursed_txt", []),
    ("Weight_txt", []),         # INVENTOR.S, Inventarseite
    # "012KG/012KG": Thalion druckt ab Weight_nr1, also liegt es bei 0;
    # die Datei nennt erst 6, dann 0.
    (None, ["Weight_nr2", "Weight_nr1"]),
    ("Legend_txt", []),         # AUTOMAPP.S
    ("YAH_text", []),           # "STANDORT"
    ("On_txt", []),             # ACTIONS.S, Optionen
    ("Off_txt", []),
    ("MonKnow_line", []),       # "------- DATEN --------", plausibel
    ("Chared_headline", []),    # "Waehlen Sie einen Charakter:", plausibel
    ("Inventory_headline", []),
]

VERSION = ["Version_string1", "Version_string2"]   # ACTIONS.S


def fehler(text):
    sys.exit("textmarken.py: " + text)


def wort(d, o):
    return struct.unpack(">H", d[o:o + 2])[0]


def zerlegen(d):
    """-> {Versatz: [Namen]}, Laenge.  Bricht ab, wenn der Aufbau nicht aufgeht."""
    marken = {}

    def setze(o, name):
        marken.setdefault(o, []).append(name)

    # Teil 1
    langworte, anzahl = wort(d, 0), wort(d, 2)
    basis = 4 + 2 * anzahl
    if basis + 4 * langworte != PROMPT_OFF:
        fehler("Teil 1 endet bei $%X, nicht bei $%X" %
               (basis + 4 * langworte, PROMPT_OFF))
    if anzahl != TEIL1_ANZAHL or anzahl != MELDUNG_TABELLE[2]:
        fehler("Teil 1: %d Einzeltexte, erwartet %d" % (anzahl, TEIL1_ANZAHL))
    versaetze = [wort(d, 4 + 2 * i) for i in range(anzahl)]
    for nr in range(anzahl):
        setze(basis + versaetze[nr], "Textamb_%d" % nr)
    for nr, name in BAUSTEINE.items():
        setze(basis + versaetze[nr], name)

    # Teil 2
    anzahl = wort(d, PROMPT_OFF)
    o = PROMPT_OFF + 2 + 2 * anzahl
    o += sum(wort(d, PROMPT_OFF + 2 + 2 * i) for i in range(anzahl))
    setze(PROMPT_OFF, "Prompts")

    # Teil 3
    for name in LISTEN:
        n = wort(d, o)
        daten = d[o + 2:o + 2 + 4 * n]
        if n == 0 or len(daten) != 4 * n or daten[-1] != 0:
            fehler("Liste %s bei $%X geht nicht auf" % (name, o))
        setze(o + 2, name)
        if name == "Spell_class_names":
            # Magic_txt: der achte Text der Liste.  So setzt es die
            # Startroutine von AM2_CPU (Hunk 8 $168, sieben Texte
            # ueberspringen; am2cpu_auszug.py prueft sie gegen).  In 1.20
            # (deutsch) ist das das Fuellbyte hinter "Funktion": ein leerer
            # Text, und so zeigt es auch das Original.
            m = o + 2
            for _ in range(7):
                m = d.index(b"\0", m) + 1
            if m >= o + 2 + 4 * n:
                fehler("Magic_txt liegt nicht in Spell_class_names")
            setze(m, "Magic_txt")
        o += 2 + 4 * n

    # Teil 4
    n = wort(d, o)
    tabelle = [wort(d, o + 2 + 2 * i) for i in range(n)]
    o += 2 + 2 * n
    eintraege, nr = [], []
    for w in tabelle:
        if w >= 0xFF00:
            nr.append(w & 0xFF)
        else:
            eintraege.append((w, nr))
            nr = []
    if nr or len(eintraege) != len(EINZEL):
        fehler("Teil 4: %d Texte, erwartet %d" % (len(eintraege), len(EINZEL)))
    for (laenge, stellen), (name, nr_namen) in zip(eintraege, EINZEL):
        text = d[o:o + laenge]
        if laenge == 0 or text[-1] != 0 or 0 in text[:-1]:
            fehler("Text %s bei $%X: Laenge %d passt nicht" % (name, o, laenge))
        if len(stellen) != len(nr_namen):
            fehler("Text %s: %d Nummernfelder, erwartet %d" %
                   (name, len(stellen), len(nr_namen)))
        if name:
            setze(o, name)
        for stelle, nr_name in zip(stellen, nr_namen):
            if stelle >= laenge - 1:
                fehler("%s liegt hinter dem Text" % nr_name)
            setze(o + stelle, nr_name)
        o += laenge

    # Teil 5: zwei Byte, zwei Texte, Rest Nullen
    o += 2
    for name in VERSION:
        ende = d.find(b"\0", o)
        if ende < 0 or ende == o:
            fehler("Versionszeile %s fehlt" % name)
        setze(o, name)
        o = ende + 1
    if any(d[o:]):
        fehler("hinter den Versionszeilen stehen noch Daten ($%X)" % o)
    return marken, len(d)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--amberfiles", default=paths.amberfiles())
    p.add_argument("--out", default="build/textmarken.i")
    a = p.parse_args()

    art, teile = unpack(open(os.path.join(a.amberfiles, "Text.amb"), "rb").read())
    if len(teile) != 1:
        fehler("Text.amb: %d Teile, erwartet einer (%s)" % (len(teile), art))
    d = bytes(teile[0])
    marken, laenge = zerlegen(d)

    z = ["; build/textmarken.i -- erzeugt von tools/textmarken.py aus Text.amb.",
         "; Nicht von Hand aendern.  Lade_texte (HULL/WORDS_SUP.S) fuellt den Block",
         "; zur Laufzeit; hier stehen nur die Versaetze.",
         "",
         "TEXT_LAENGE\tequ\t%d" % laenge,
         "",
         "\tSECTION\tFast_BSS,bss",
         "\teven",
         "Textdaten:"]
    zuletzt = 0
    for o in sorted(marken):
        if o > zuletzt:
            z.append("\tds.b\t%d" % (o - zuletzt))
        for name in marken[o]:
            z.append("%s:\t\t\t; $%04X" % (name, o))
        zuletzt = o
    z.append("\tds.b\t%d" % (laenge - zuletzt))
    z.append("\teven")
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    open(a.out, "w").write("\n".join(z) + "\n")
    print("  Text.amb: %d Byte, %d Marken -> %s" %
          (laenge, sum(len(v) for v in marken.values()), a.out))


if __name__ == "__main__":
    main()

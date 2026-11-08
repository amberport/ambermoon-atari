#!/usr/bin/env python3
"""text_labels.py -- Thalion's text names as labels in Text.amb, at build time.

DEVIATION (goal 2), docs/17-deviations.md D5: the positions of the
library's texts inside Text.amb are fixed at build time.

In the original the library's texts are in AM2_CPU: race, class and spell
names, the templates of the character page ("AGE:012"), the headlines.  The
German version 1.20 keeps them in ``Text.amb`` (JH wrapper, LOB).  Thalion's
code addresses them through fixed labels:

    lea.l Race_names,a0 / jsr Find_small_text        ; INVENTOR.S
    lea.l Age_nr,a0 / jsr DecL_convert                ; writes into Age_txt
    lea.l Age_txt,a0 / jsr Put_text_line

The library loads the whole file into ``Textdaten`` at run time
(``Lade_texte``, HULL/WORDS_SUP.S; goal 2).  **Where** each name lies in it
is fixed here, at build time: ``Age_nr`` - ``Age_txt`` depends on the language
("ALTER:012" against "AGE:012"), but Thalion computes with two fixed labels.
Another version means building again, as with the AM2_CPU extract.

**Layout of Text.amb 1.20** (18,526 bytes unpacked, worked out 2026-09-28):

1. ``$0000`` single texts: word longwords of the texts, word count (46), as
   many offset words, then the texts, each with its end zero.  World names,
   disk and error messages, building blocks of messages.
2. ``$05D8`` ``Prompts``: word count, length words, texts -- the format of
   ``Find_large_text`` (finding 179).
3. Name lists: each ``[word n][n longwords]``, in it texts with end zeros --
   the format of ``Find_small_text``.  Fourteen of them, order ``LISTS``.
4. Single texts: word count of table words, then the table: per text a
   length word, before it for each ``*_nr`` label in the text a word ``$FFxx``
   (xx = offset in the text).  Then the texts.  Order ``SINGLES``.
5. The two version lines, two bytes (unknown) before them, zeros after them.

This file assigns the names, by content and by the call sites in Thalion's
source.  The tool checks the layout and stops if it does not work out.

Output ``build/textmarken.i``: a BSS block ``Textdaten`` of the file's size,
Thalion's names as real labels at their offsets, and ``TEXT_LAENGE``.  No game
data, only offsets -- still not for the repository (``build/``).

Usage:  text_labels.py [--amberfiles DIR] [--out build/textmarken.i]
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import unpack                               # noqa: E402
from am2cpu_extract import MESSAGE_SINGLES, MESSAGE_TABLE  # noqa: E402
import paths  # noqa: E402

PROMPT_OFF = 0x05D8

# Part 1: single texts by number.  Each gets the label Textamb_<n>; the message
# lists (Recup1_text ...) that am2cpu_extract.py builds from AM2_CPU point at
# them.  Single texts Thalion addresses as texts itself ("move.l
# #Divide_start_text,(a2)+") get their name as well; the assignment is there
# (MESSAGE_SINGLES), checked against AM2_CPU.
NAMED_TEXTS = {0: "Weltname_1", 1: "Weltname_2", 2: "Weltname_3"}
NAMED_TEXTS.update({nr: name for name, nr, _, _ in MESSAGE_SINGLES})
PART1_COUNT = 46

# Part 3, in file order.
LISTS = [
    "Automap_icon_names",       # riddlemouth, teleporter ... (AUTOMAPP.S)
    "Option_names",             # music, fast combat mode ... (ACTIONS.S)
    "Song_names",               # (MAGIC.S)
    "Spell_class_names",        # healing, alchemy ... (INVENTOR.S)
    "Spell_names",              # 7 x 30 (MAGIC.S, INVENTOR.S)
    "Language_names",           # (INVENTOR.S, loop over end zeros)
    "Class_names",
    "Race_names",
    "Skill_names",
    "Attribute_names",
    "Short_skill_names",        # ATT PAR ...
    "Short_attr_names",         # STAe INT ...
    "Item_type_names",          # Find_small_text with type-1
    "Condition_names",
]

# Part 4, in file order: (text name or None, [names of the $FF labels in file
# order]).  The offsets are in the file; where Thalion itself takes a fixed
# offset (LP_txt +5/+9, Goldfood_txt +2/+10, ProtDam_txt +1, SLP_txt +4, TP_txt
# +3), the template fits it.
SINGLES = [
    ("APR_txt", []),            # "APR:  " (COMBAT_M.S)
    ("He_txt", []),             # MAIN.S Insert_sex1/2
    ("She_txt", []),
    ("His_txt", []),
    ("Hers_txt", []),
    ("Skills_txt", []),         # headlines of the character page
    ("Attrs_txt", []),
    ("Language_txt", []),
    ("Conditions_txt", []),
    ("Male_txt", []),
    ("Female_txt", []),
    ("Both_txt", []),
    ("Compass_txt", []),        # DISPLAY.S, MAGIC.S
    ("Age_txt", ["Age_nr"]),    # "ALTER:012"
    ("Skill_txt", []),          # "01%/01%", Thalion writes at 0 and 4
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
    ("Classes_txt", []),        # item view (INVENTOR.S)
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
    ("Weight_txt", []),         # INVENTOR.S, inventory page
    # "012KG/012KG": Thalion prints from Weight_nr1, so it lies at 0; the file
    # names 6 first, then 0.
    (None, ["Weight_nr2", "Weight_nr1"]),
    ("Legend_txt", []),         # AUTOMAPP.S
    ("YAH_text", []),           # "STANDORT"
    ("On_txt", []),             # ACTIONS.S, options
    ("Off_txt", []),
    ("MonKnow_line", []),       # "------- DATEN --------", plausible
    ("Chared_headline", []),    # "Waehlen Sie einen Charakter:", plausible
    ("Inventory_headline", []),
]

VERSION = ["Version_string1", "Version_string2"]   # ACTIONS.S


def error(text):
    sys.exit("text_labels.py: " + text)


def word(d, o):
    return struct.unpack(">H", d[o:o + 2])[0]


def parse_text_amb(d):
    """-> {offset: [names]}, length.  Stops if the layout does not work out."""
    labels = {}

    def put(o, name):
        labels.setdefault(o, []).append(name)

    # Part 1
    longwords, count = word(d, 0), word(d, 2)
    base = 4 + 2 * count
    # the end of part 1 comes from the file (1.20 German: $5D8)
    PROMPT_OFF = base + 4 * longwords
    if count != PART1_COUNT or count != MESSAGE_TABLE[2]:
        error("part 1: %d single texts, expected %d" % (count, PART1_COUNT))
    offsets = [word(d, 4 + 2 * i) for i in range(count)]
    for nr in range(count):
        put(base + offsets[nr], "Textamb_%d" % nr)
    for nr, name in NAMED_TEXTS.items():
        put(base + offsets[nr], name)

    # Part 2
    count = word(d, PROMPT_OFF)
    o = PROMPT_OFF + 2 + 2 * count
    o += sum(word(d, PROMPT_OFF + 2 + 2 * i) for i in range(count))
    put(PROMPT_OFF, "Prompts")
    # part 3 starts on a word boundary (1.21 en/fr/pl/cz: the
    # prompts end on an odd offset, one fill byte follows)
    # Rule found in all six files (1.20 de, 1.21 de/en/fr/pl/cz): the count
    # word of the first list lies at 2 mod 4, so its texts start on a
    # longword; zero bytes fill the gap.
    while (o + 2) % 4:
        if d[o]:
            error("fill byte behind the prompts at $%X is not zero" % o)
        o += 1

    # Part 3
    for name in LISTS:
        n = word(d, o)
        data = d[o + 2:o + 2 + 4 * n]
        if n == 0 or len(data) != 4 * n or data[-1] != 0:
            error("list %s at $%X does not work out" % (name, o))
        put(o + 2, name)
        if name == "Spell_class_names":
            # Magic_txt: the eighth text of the list.  That is how AM2_CPU's
            # start routine sets it (hunk 8 $168, skip seven texts;
            # am2cpu_extract.py checks it).  In 1.20 (German) that is the fill
            # byte behind "Funktion": an empty text, and the original shows it
            # so too.
            m = o + 2
            for _ in range(7):
                m = d.index(b"\0", m) + 1
            if m >= o + 2 + 4 * n:
                # 1.21 fr has no empty eighth text; AM2_CPU's
                # start routine (hunk 8 $168, the same in 1.21) points behind
                # the list then.  We do the same and say so.
                print("  text_labels.py: NOTE Magic_txt lies behind "
                      "Spell_class_names ($%X), as in AM2_CPU" % m)
            put(m, "Magic_txt")
        o += 2 + 4 * n

    # Part 4
    n = word(d, o)
    table = [word(d, o + 2 + 2 * i) for i in range(n)]
    o += 2 + 2 * n
    entries, nr = [], []
    for w in table:
        if w >= 0xFF00:
            nr.append(w & 0xFF)
        else:
            entries.append((w, nr))
            nr = []
    if nr or len(entries) != len(SINGLES):
        error("part 4: %d texts, expected %d" % (len(entries), len(SINGLES)))
    for (length, places), (name, nr_names) in zip(entries, SINGLES):
        text = d[o:o + length]
        if length == 0 or text[-1] != 0 or 0 in text[:-1]:
            error("text %s at $%X: length %d does not fit" % (name, o, length))
        if len(places) != len(nr_names):
            error("text %s: %d number fields, expected %d" %
                  (name, len(places), len(nr_names)))
        if name:
            put(o, name)
        for place, nr_name in zip(places, nr_names):
            if place >= length - 1:
                error("%s lies behind the text" % nr_name)
            put(o + place, nr_name)
        o += length

    # Part 5: two bytes, two texts, the rest zeros
    o += 2
    for name in VERSION:
        end = d.find(b"\0", o)
        if end < 0 or end == o:
            error("version line %s is missing" % name)
        put(o, name)
        o = end + 1
    if any(d[o:]):
        error("there is more data behind the version lines ($%X)" % o)
    return labels, len(d)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--amberfiles", default=paths.amberfiles())
    p.add_argument("--out", default="build/textmarken.i")
    a = p.parse_args()

    kind, parts = unpack(open(os.path.join(a.amberfiles, "Text.amb"), "rb").read())
    if len(parts) != 1:
        error("Text.amb: %d parts, expected one (%s)" % (len(parts), kind))
    d = bytes(parts[0])
    labels, length = parse_text_amb(d)

    z = ["; build/textmarken.i -- written by tools/text_labels.py from Text.amb.",
         "; Do not edit.  Lade_texte (HULL/WORDS_SUP.S) fills the block at run",
         "; time; only the offsets are here.",
         "",
         "TEXT_LAENGE\tequ\t%d" % length,
         "",
         "\tSECTION\tFast_BSS,bss",
         "\teven",
         "Textdaten:"]
    last = 0
    for o in sorted(labels):
        if o > last:
            z.append("\tds.b\t%d" % (o - last))
        for name in labels[o]:
            z.append("%s:\t\t\t; $%04X" % (name, o))
        last = o
    z.append("\tds.b\t%d" % (length - last))
    z.append("\teven")
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    open(a.out, "w").write("\n".join(z) + "\n")
    print("  Text.amb: %d bytes, %d labels -> %s" %
          (length, sum(len(v) for v in labels.values()), a.out))


if __name__ == "__main__":
    main()

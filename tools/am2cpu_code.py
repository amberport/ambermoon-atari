#!/usr/bin/env python3
"""am2cpu_code.py -- Thalions Routinen der Bibliothek, beim Bau aus AM2_CPU.

DEVIATION (goals 1 and 2), docs/17-deviations.md D2: Thalion's library
routines taken from AM2_CPU at build time.

**Entscheidung (Nutzer, 2026-09-28).**  Die CPU-Fassungen der 3D-Rasterer
sind reiner Speichercode: Sie lesen Grafik, schreiben in Thalions
Zwischenpuffer und fassen keine Amiga-Hardware an.  Statt sie nach dem
Vertrag nachzuschreiben, nehmen wir Thalions uebersetzten Code, genau wie die
Daten in am2cpu_auszug.py: **beim Bau herausgezogen, nie im Repository, nie
zur Laufzeit gelesen.**  Warum, und wie man zurueckgeht, steht in
docs/02-3D-Renderpfad.md, Teil A7.

Was herauskommt (build/am2cpu_code.i):

- je Stueck die Maschinenbefehle als ``dc.w``, dahinter als Kommentar der
  Befehl, wie objdump ihn liest;
- jede verschobene Adresse (Relokation) als ``dc.l Name``: Thalions Variablen
  unter Thalions Namen, Sprungziele in einem Stueck unter einer Marke dort,
  die internen Variablen der Bibliothek in einem BSS-Block **mit derselben
  Anordnung wie im Original**, weil der Code mehrere davon in einem Zug
  liest (``movem.w`` ueber sechs Worte, ``tst.l`` ueber vier Merkerbytes);
- der Einsprung unter Thalions Namen, bei den 3D-Routinen die CPU-Fassung
  hinter ``tst.b Blitter_or_CPU``.  Die Weiche in Hunk 11 uebernehmen wir
  nicht; Blitter_or_CPU steht bei uns fest auf $FF (D3_SUP.S).

**Pruefungen, jede bricht den Bau ab:**

1. Jede Relokation hat einen Namen oder eine Marke.
2. Kein Sprung und kein PC-relativer Zugriff verlaesst sein Stueck.
   Ausnahme: Wortspruenge nach AUSGAENGE (bei uns eine eigene Marke) und
   das Ende eines Stuecks in FORTSETZUNGEN (dort beginnt im Original der
   Blitter, bei uns geht es mit ``jmp`` in unserer Routine weiter).
3. Keine absolute Adresse ohne Relokation (Amiga-Hardware wie $DFF000).
4. 68000: objdump liest jeden Befehl als 68000 und als 68030 gleich, und
   kein Index ist skaliert.  Die 68000-Gegenprobe von build_falcon.sh sieht in
   ``dc.w`` nichts; diese hier ersetzt sie fuer die Stuecke.  Ausnahme sind
   die Stuecke in CPU_020: Thalion ruft sie nur bei CPU_68020_plus, dort
   duerfen die Befehle aus ERLAUBT_020 stehen, sonst nichts.
5. Jedes Stueck endet mit rts/rte/jmp/bra, faellt also nicht heraus, und
   jede Tabelle beginnt auf einer Befehlsgrenze.

Aufruf:  am2cpu_code.py [--datei .../AM2_CPU] [--out build/am2cpu_code.i]
"""
import argparse
import os
import re
import struct
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from am2cpu_lesen import NAMEN, amberfiles, lies_hunks, objdump   # noqa: E402

# (Einsprung, Hunk, von, bis, Tabellen [(von, bis)], Beleg).  Einsprung None:
# das Stueck wird nur ueber Relokationen erreicht.
STUECKE = [
    # DISPLAY.S und 3D_MAP.S Set_D3_light_level: eine Farbe $0RGB (d0) je
    # Komponente um eine Stufe auf d1 zu.  Kein Blitter, keine Weiche.
    ("Fade_colour", 0, 0x23332, 0x2338A, [],
     "am Aufruf in Set_D3_light_level (moveq #14,d7 / sub.w d0,d7)"),
    # 3D_MAP.S Draw_horizon: 20 Zeilen zu 72 Byte, Quelle mit 144 Byte
    # Zeilenabstand.  Ziel von 11:$0000 bei Blitter_or_CPU <> 0.
    ("Insert_horizon", 0, 0x29A42, 0x29A6C, [],
     "CPU-Fassung hinter 11:$0000 (einziger jsr aus Draw_horizon)"),
    # 3D_MAP.S Draw_faces: eine Wand.  Nahebene, Projektion, Kantenliste,
    # Spalten.  Am Ende eine Tabelle der Spaltenmasken (8 Langworte).
    ("put_dpoly", 0, 0x29A6E, 0x2A036, [(0x29E52, 0x29E72)],
     "CPU-Fassung hinter 11:$0886 (jsr aus Draw_faces)"),
    # Kantenliste fuellen: put_dpoly springt bei Blitter_or_CPU <> 0 mit jmp
    # nach $019E (Schleife), sonst mit jsr nach $01B4 (ausgerollt).  Beide
    # sind reiner Speichercode; die ausgerollte kommt mit, damit jede
    # Relokation ein Ziel hat.
    (None, 11, 0x019E, 0x0886, [],
     "Ziel von jmp/jsr am Ende der Kantenroutine in put_dpoly"),
    # 3D_MAP.S make_3dzoom2: ein Objekt, verkleinert oder vergroessert.  Am
    # Ende die Randmasken links (5 Langworte) und rechts (ab +$20).
    ("draw_zoomshape", 0, 0x2A036, 0x2A70A, [(0x2A6CA, 0x2A70A)],
     "CPU-Fassung hinter 11:$3978 (jsr aus make_3dzoom2)"),
    # 3D_MAP.S M3_DisUpd: texturierter Boden und Decke in den 3D-Puffer,
    # nur bei Floor_ceiling_status <> 0, also nur bei CPU_68020_plus.
    # Draw_ceiling setzt seine Werte und springt in Draw_floor hinein;
    # darum ein Stueck mit zwei Einspruengen (EINSPRUENGE).  Kein Blitter,
    # keine Weiche.  68020-Code (CPU_020).
    ("Draw_ceiling", 0, 0x2A70A, 0x2AA0E, [],
     "jsr Draw_ceiling / jsr Draw_floor in M3_DisUpd"),
    # COMBAT.S Load_monster_graphics u. a.: ein Monsterbild ueber die
    # Tabelle Amiga_recol umfaerben, in Thalions fuenf Ebenen.  Mit den
    # Hilfsroutinen fuer ein und zwei Worte ($21BE8, $21C6E).  Reiner
    # Speichercode, keine Weiche.
    ("Recolour_block", 0, 0x21B6C, 0x21CF4, [],
     "jsr Recolour_block in COMBAT.S (a0 Bild, a1 Amiga_recol, d6/d7)"),
    # COMOBS.S: ein Kampfobjekt gezoomt und/oder gespiegelt.  Nur Thalions
    # Einsprung und Vorspann (Merker, Lage, Beschneiden gegen die CA,
    # jsr Zoom_tabellen); ab $2BE42 folgt der Blitter, dort geht es in
    # unserer Routine weiter (FORTSETZUNGEN, COMBAT_SUP.S).  Eine CPU-Fassung
    # gibt es nicht.
    ("Draw_zoom_shape", 0, 0x2BD2A, 0x2BE42, [],
     "jsr Draw_zoom_shape in COMOBS.S (d2 < 0, Groesse oder Spiegelung)"),
    # Die Schritttabellen des Zooms: je Zielzeile ($EBDC) und Zielspalte
    # ($E95C) der Schritt in der Quelle, dazu die ersten Quellzeile/-spalte
    # nach dem Beschneiden.  Reiner Speichercode.
    ("Zoom_tabellen", 0, 0x2C534, 0x2C636, [],
     "jsr 0:$2C534 am Ende des Vorspanns von Draw_zoom_shape"),
    # Dasselbe als Silhouette in einer Farbe (d2).  Der Vorspann endet vor
    # dem Blitter; die Tabellen rechnet Thalion erst dahinter aus, bei uns
    # also Zoom_silhouette_zeichnen.
    ("Draw_zoom_silhouette", 0, 0x2C636, 0x2C74E, [],
     "jsr Draw_zoom_silhouette in COMOBS.S (d2 >= 0)"),
    # The LOB unpacker: the loop of Thalion's Decompress (0:$26124), behind
    # its type check (cmpi.b #6).  Decompress first moves the packed data to
    # the end of the buffer; that part is not taken (ours is FILES_SUP.S).
    # Bit-flagged LZ, a0 = packed stream, a1 = destination, d0 = end of the
    # destination; the end is checked after each literal and each back
    # reference.  Pure memory code.  Our LOB_decompress calls it.
    ("Lob_core", 0, 0x261E4, 0x2621E, [],
     "loop of Decompress 0:$26124 (jsr from 0:$257C8 after the LOB check)"),
    # Der Musikspieler (Sonic Arranger), docs/13 Abschnitt 4.  Vorn die
    # Sprungtabelle.  Thalions XREF Music_routine in VARIOUS.S (Makro music:
    # +0/+12/+16) ist seit 2026-10-10 unsere Weiche in MUSIK_YM.S, die zu
    # Sa_spieler oder zum YM-Spieler fuehrt; der VBL ruft Sa_spieler+24.
    # Die Hardware biegt UMBIEGEN auf unseren Schattenblock (MUSIK_SUP.S).
    # Tabellen: Variablen hinter der Sprungtabelle, zwei Interrupt-Saetze
    # mit Namen, zwei Sprungversatz-Tabellen (Effektbefehle, Synth-Effekte).
    ("Sa_spieler", 0, 0x2AA0E, 0x2BD2A,
     [(0x2AA2A, 0x2AA44), (0x2AB52, 0x2AB86), (0x2AD72, 0x2AD9C),
      (0x2B06E, 0x2B08E), (0x2B6B8, 0x2B6DC)],
     "jsr 0:$2AA0E/$2AA1A/$2AA1E in Set_music und Remove_music, 0:$2AA26 im VBL"),
]

# Weitere Einspruenge mitten in einem Stueck: (Hunk, Versatz) -> Name.
EINSPRUENGE = {
    (0, 0x2A774): "Draw_floor",
}

# Wortspruenge aus einem Stueck heraus, die bei uns an einer eigenen Marke
# landen: (Hunk, Ziel) -> Name.  Die Befehlsbytes bleiben Thalions; nur der
# Abstand wird als ``dc.w Name-*`` geschrieben, so rechnet vasm ihn neu aus.
# Kurze Spruenge (.s) koennen das nicht und brechen weiter ab.
AUSGAENGE = {
    (0, 0x2C288): "Zoom_aus",       # rts des Blitterteils von Draw_zoom_shape
    (0, 0x2CB36): "Zoom_aus",       # rts des Blitterteils von Draw_zoom_silhouette
}

# Stuecke, die an ihrem Ende nicht zurueckkehren, sondern in den
# Blitterteil laufen.  Dort geht es bei uns weiter: (Hunk, bis) -> Name,
# geschrieben als ``jmp Name`` hinter dem Stueck.
FORTSETZUNGEN = {
    (0, 0x2BE42): "Zoom_zeichnen",
    (0, 0x2C74E): "Zoom_silhouette_zeichnen",
}

# Stuecke mit 68020-Befehlen, (Hunk, von) -> Beleg, dass Thalion sie nur
# auf dem 68020 ruft.  Unser Schalter dafuer ist D3_CPU (D3_SUP.S); beim
# 68000-Weg bleibt der Code liegen, ohne je zu laufen.
CPU_020 = {
    (0, 0x2A70A): "3D_MAP.S: Floor_ceiling_potential = 0 ohne CPU_68020_plus,"
                  " also kein Load_floor und kein Draw_floor/Draw_ceiling",
}
# Was ein 020-Stueck ueber den 68000 hinaus darf: 32-Bit-Division und
# -Multiplikation.  Alles andere bricht weiter ab.
ERLAUBT_020 = re.compile(r"(div[su]l?l|mul[su]l)\b")

# Die internen Variablen der Bibliothek, die die Stuecke benutzen, liegen in
# Hunk 9 lueckenlos von $E278 (draw_zoomshape: Lage, Groessen, Randversaetze)
# ueber die Schritttabellen ($E29C Spalten, $E51C Zeilen), die Zeiger der
# Zoomschirme, die Boden-/Deckenwerte, dpoly_koos3d ($E6CC), die
# projizierten Punkte ($E6D8) und die Kantenliste ($E6E8, 144 Langworte)
# bis zu den vier Merkerbytes $E934..$E937, die put_dpoly mit tst.l liest.
#
# Dazu Hunk 2 (Longword_BSS) hinter Thalions wall_list0: Floor_source_gfx,
# die Eckvektoren ($BC4, 8 Langworte), die Zeilentabelle ($BE4, 144 Zeilen
# zu 16 Byte) und die Texelzeile ($14E4, 144 Byte) von Draw_floor.  Der
# Block reicht bis zum Ende des Hunks.
#
# Dahinter (bis $ED6C) die des Kampfzooms: Merker, Lage und Groessen
# ($E938..$E95B), die Spaltenschritte ($E95C, 320 Worte) und die
# Zeilenschritte ($EBDC, 200 Worte).  Zuletzt Zoomscreen1_ptr ($ED6C) und
# Zoomscreen2_ptr ($ED70): Thalions COMOBS.S schreibt sie, lesen tut sie
# nur der Blitterteil, den bei uns COMBAT_SUP.S ersetzt.
BSS_BLOECKE = [(9, 0xE278, 0xED74), (2, 0x0BC0, 0x1574)]

# Vorbelegte Daten, die nur ein Stueck benutzt, als Block mit Inhalt und
# Originalanordnung: (Hunk, von, bis).  Der Musikspieler hat seine Tabellen
# (Perioden ab $35E0) und Variablen (vier Kanalsaetze zu 206 Byte ab $37BE,
# Stille $3AF6, Zeiger ab $3AFE) am Ende von Hunk 3; niemand sonst zeigt
# dorthin (nachgerechnet 2026-10-01).
DATEN_BLOECKE = [(3, 0x35E0, 0x3D64)]

# Absolute Operanden ohne Relokation, die auf uns umgebogen werden, wie K1
# bei FAIRY.S (docs/13): Stueck -> [(von, bis, Symbol)].  Ein Wert v in
# [von, bis) wird zu ``Symbol+(v-von)``.  Alles andere bleibt ein Abbruch.
UMBIEGEN = {
    "Sa_spieler": [
        (0xDFF000, 0xDFF200, "Paula_schatten"),     # Custom-Chips
        (0xBFD000, 0xBFE000, "Cia_b_attrappe"),     # CIA-B (Tempo-Timer)
        (0xBFE001, 0xBFE002, "Cia_a_filter"),       # CIA-A PRA, Filterbit
        (0x000004, 0x000008, "Musik_exec_zeiger"),  # ExecBase (nur +4/+8/+20)
    ],
}

AUSGABE_KOPF = """\
; build/am2cpu_code.i -- erzeugt von tools/am2cpu_code.py aus AM2_CPU.
; Thalions uebersetzter Code der Bibliothek, beim Bau herausgezogen.
; Nicht von Hand aendern, nicht ins Repository (Thalions Code, Spieldaten).
; Warum und wie zurueck: docs/02-3D-Renderpfad.md, Teil A7.
"""


def marke(h, v):
    return "Am2cpu_%d_%05X" % (h, v)


def dis(daten, von, bis, arch):
    """-> Liste (Adresse, Laenge, Text) fuer daten[von:bis]."""
    with tempfile.NamedTemporaryFile(suffix=".bin") as f:
        f.write(daten)
        f.flush()
        aus = subprocess.run(
            [objdump(), "-D", "-b", "binary", "-m", arch,
             "--start-address=0x%x" % von, "--stop-address=0x%x" % bis, f.name],
            capture_output=True, text=True, check=True).stdout
    zeilen = []
    for z in aus.splitlines():
        m2 = re.match(r"^\s*([0-9a-f]+):\t((?:[0-9a-f]{4} ?)+)\s*$", z)
        if m2:
            zeilen[-1][1] += len(m2.group(2).split()) * 2
            continue
        m = re.match(r"^\s*([0-9a-f]+):\t((?:[0-9a-f]{4} ?)+)\s*\t(.*)$", z)
        if m:
            zeilen.append([int(m.group(1), 16), len(m.group(2).split()) * 2,
                           m.group(3).strip()])
    return zeilen


class Fehler(Exception):
    pass


def bytes_zeilen(daten, h, von, bis, marken, art, name_von, erste=True):
    """Bytes von..bis als dc.w/dc.b, mit einer Marke vor jedem Versatz aus
    marken.  vasm laeuft mit -align und legte ein dc.w auf einer ungeraden
    Adresse gerade; darum dc.w nur ab gerader Adresse und gerader Laenge."""
    z, x = [], von
    while x < bis:
        if (h, x) in marken and (erste or x != von):
            z.append(name_von(h, x) + ":")
        ende = min((x + 16) & ~15, bis)
        for y in range(x + 1, ende):
            if (h, y) in marken:
                ende = y
                break
        if x % 2 == 0 and (ende - x) % 2 == 0:
            werte = ",".join("$%04X" % struct.unpack(">H", daten[y:y + 2])
                             for y in range(x, ende, 2))
            z.append("\tdc.w\t%s\t; %s $%05X" % (werte, art, x))
        else:
            werte = ",".join("$%02X" % daten[y] for y in range(x, ende))
            z.append("\tdc.b\t%s\t; %s $%05X" % (werte, art, x))
        x = ende
    return z


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--datei", default=os.path.join(amberfiles(), "AM2_CPU"))
    p.add_argument("--out", default="build/am2cpu_code.i")
    a = p.parse_args()
    hunks = lies_hunks(a.datei)

    def im_stueck(h, v):
        for s in STUECKE:
            if s[1] == h and s[2] <= v < s[3]:
                return s
        return None

    # ---- 1. Befehle lesen und pruefen ----
    anzahl_020 = [0]
    befehle = {}                 # (Hunk, von) -> [(Adresse, Laenge, Text)]
    grenzen = set()              # (Hunk, Adresse) aller Befehle und Tabellen
    for name, h, von, bis, tabellen, _ in STUECKE:
        daten = hunks[h]["daten"]
        teile, o = [], von
        for tv, tb in sorted(tabellen):
            teile.append((o, tv, "code"))
            teile.append((tv, tb, "tab"))
            o = tb
        if o < bis:
            teile.append((o, bis, "code"))
        liste = []
        for tv, tb, art in teile:
            if art == "tab":
                for x in range(tv, tb):
                    grenzen.add((h, x))
                liste.append((tv, tb - tv, None))
                continue
            z30 = dis(daten, tv, tb, "m68k:68030")
            z00 = dis(daten, tv, tb, "m68k:68000")
            wo = "%s %d:$%05X" % (name or "Stueck", h, tv)
            if (h, von) in CPU_020:
                # Die erlaubten 020-Befehle fuer die Gegenprobe durch NOPs
                # gleicher Laenge ersetzen; der Rest muss wie ueberall als
                # 68000 und 68030 gleich lauten.
                probe = bytearray(daten)
                for adr, n, text in z30:
                    if ERLAUBT_020.match(text):
                        probe[adr:adr + n] = b"\x4e\x71" * (n // 2)
                        anzahl_020[0] += 1
                p30 = dis(bytes(probe), tv, tb, "m68k:68030")
                p00 = dis(bytes(probe), tv, tb, "m68k:68000")
            else:
                p30, p00 = z30, z00
            if [z[:3] for z in p30] != [z[:3] for z in p00]:
                for x, y in zip(p30, p00):
                    if x != y:
                        raise Fehler("%s: kein 68000-Befehl bei $%05X: %s (68000: %s)"
                                     % (wo, x[0], x[2], y[2]))
                raise Fehler("%s: 68000 und 68030 lesen verschieden" % wo)
            if not z30 or z30[-1][0] + z30[-1][1] != tb:
                raise Fehler("%s: letzter Befehl ragt ueber $%05X" % (wo, tb))
            if (h, tb) in FORTSETZUNGEN and tb == bis:
                pass
            elif not re.match(r"(rts|rte|jmp|bra[sw]?)\b", z30[-1][2]):
                raise Fehler("%s: endet nicht mit rts/rte/jmp/bra: %s"
                             % (wo, z30[-1][2]))
            for adr, n, text in z30:
                grenzen.add((h, adr))
                liste.append((adr, n, text))
        befehle[(h, von)] = liste

    # ---- 2. Relokationen aufloesen ----
    reloc_ziel = {}              # (Hunk, Adresse) -> Symboltext
    marken = set()               # (Hunk, Versatz) mit interner Marke
    bss = {}                     # (Hunk, Versatz) -> Name

    def im_bss(h, v):
        return any(h == bh and bv <= v < bb for bh, bv, bb in BSS_BLOECKE)

    def im_daten(h, v):
        return any(h == bh and bv <= v < bb for bh, bv, bb in DATEN_BLOECKE)
    daten_marken = {}            # (Hunk, Versatz) -> Name
    for (h, v), n in NAMEN.items():
        if im_bss(h, v):
            bss[(h, v)] = n
    extern = set()
    for name, h, von, bis, tabellen, _ in STUECKE:
        daten, reloc = hunks[h]["daten"], hunks[h]["reloc"]
        for o in sorted(r for r in reloc if von <= r < bis):
            zh = reloc[o]
            zv = struct.unpack(">I", daten[o:o + 4])[0]
            wo = "%s %d:$%05X" % (name or "Stueck", h, o)
            if im_stueck(zh, zv):
                if (zh, zv) not in grenzen:
                    raise Fehler("%s: Ziel %d:$%05X liegt mitten in einem Befehl"
                                 % (wo, zh, zv))
                ziel = marke(zh, zv)
                marken.add((zh, zv))
            elif im_bss(zh, zv):
                ziel = bss.setdefault((zh, zv), marke(zh, zv))
            elif im_daten(zh, zv):
                ziel = daten_marken.setdefault((zh, zv), marke(zh, zv))
            elif (zh, zv) in NAMEN and hunks[zh]["typ"] != "CODE":
                ziel = NAMEN[(zh, zv)]
                extern.add(ziel)
            else:
                raise Fehler("%s: Relokation nach %d:$%05X hat keinen Namen "
                             "(NAMEN in am2cpu_lesen.py oder BSS_BLOCK)"
                             % (wo, zh, zv))
            if any(tv <= o < tb for tv, tb in tabellen):
                raise Fehler("%s: Relokation in einer Tabelle" % wo)
            reloc_ziel[(h, o)] = ziel

    # ---- 3. Spruenge, PC-relative Ziele, absolute Adressen ----
    def daten_h(h):
        return hunks[h]["daten"]
    ausgang_bei = {}             # (Hunk, Befehl) -> Name der Marke
    umgebogen = []               # (Adresse, Befehl, Ziel) aus UMBIEGEN
    sprung = re.compile(r"(b[a-z]{1,2}[sw]?|db[a-z]{1,2}\s+%d\d,|bsr[sw]?)\s*0x([0-9a-f]+)$")
    for name, h, von, bis, _, _ in STUECKE:
        for adr, n, text in befehle[(h, von)]:
            if text is None:
                continue
            wo = "%s %d:$%05X %s" % (name or "Stueck", h, adr, text)
            if re.search(r":[wl]:[248]\)|\)@|%z", text):
                raise Fehler("%s: Adressierungsart erst ab 68020" % wo)
            if re.match(r"\.(short|long|byte)\b", text):
                raise Fehler("%s: kein Befehl (Tabelle nicht angegeben?)" % wo)
            m = sprung.match(text)
            ziele = [int(t, 16) for t in re.findall(r"%pc@\(0x([0-9a-f]+)", text)]
            if m:
                ziele.append(int(m.group(2), 16))
            if m and (h, int(m.group(2), 16)) in AUSGAENGE:
                if n != 4 or daten_h(h)[adr + 1] != 0 or not re.match(
                        r"(b[a-z]{2}w|braw)\b", text):
                    raise Fehler("%s: Ausgang nur als Wortsprung" % wo)
                ausgang_bei[(h, adr)] = AUSGAENGE[(h, int(m.group(2), 16))]
                ziele.remove(int(m.group(2), 16))
            for t in ziele:
                if not (von <= t < bis) or (h, t) not in grenzen:
                    raise Fehler("%s: Ziel $%05X ausserhalb des Stuecks" % (wo, t))
            if not m:
                # Jede absolute Adresse braucht eine Relokation an ihrer
                # Stelle oder einen Eintrag in UMBIEGEN.  Auch als Ziel
                # hinter dem Komma ("move.w #15,$DFF096"); bis 2026-10-01
                # uebersah die Suche diese Form.
                rest = re.sub(r"%pc@\([^)]*\)", "", text)
                absolut = re.findall(r"(?<![#\w(])0x([0-9a-f]+)", rest)
                for wert in (int(t, 16) for t in absolut):
                    if any((h, x) in reloc_ziel and struct.unpack(
                            ">I", daten_h(h)[x:x + 4])[0] == wert
                            for x in range(adr + 2, adr + n - 3, 2)):
                        continue
                    ziel = next(("%s+$%X" % (sym, wert - uv) if wert > uv else sym
                                 for uv, ub, sym in UMBIEGEN.get(name, [])
                                 if uv <= wert < ub), None)
                    stellen = [x for x in range(adr + 2, adr + n - 3, 2)
                               if struct.unpack(">I", daten_h(h)[x:x + 4])[0] == wert]
                    if ziel is None or len(stellen) != 1:
                        raise Fehler("%s: absolute Adresse ohne Relokation" % wo)
                    reloc_ziel[(h, stellen[0])] = ziel
                    umgebogen.append((adr, text, ziel))

    # ---- 4. Ausgabe ----
    z = [AUSGABE_KOPF, "\tSECTION\tProgram,code", "\teven"]
    bytes_ges = 0
    for name, h, von, bis, _, beleg in STUECKE:
        daten = hunks[h]["daten"]
        z += ["", "; " + "-" * 70,
              "; %s -- AM2_CPU %d:$%05X..$%05X, %d Byte" % (
                  name or "(ohne Einsprung)", h, von, bis, bis - von),
              "; Beleg: " + beleg, "; " + "-" * 70]
        if name:
            z.append(name + ":")
        bytes_ges += bis - von
        for (eh, ev), en in EINSPRUENGE.items():
            if eh == h and von < ev < bis and (eh, ev) not in grenzen:
                raise Fehler("Einsprung %s %d:$%05X liegt mitten in einem Befehl"
                             % (en, eh, ev))
        for adr, n, text in befehle[(h, von)]:
            if (h, adr) in EINSPRUENGE:
                z.append(EINSPRUENGE[(h, adr)] + ":")
            if (h, adr) in marken:
                z.append(marke(h, adr) + ":")
            if text is None:                    # Tabelle
                z += bytes_zeilen(daten, h, adr, adr + n, marken, "Tabelle",
                                  lambda hh, v: marke(hh, v), erste=False)
                continue
            if (h, adr) in ausgang_bei:
                z.append("\tdc.w\t$%04X\t; %05X  %s -> %s" % (
                    struct.unpack(">H", daten[adr:adr + 2])[0], adr, text,
                    ausgang_bei[(h, adr)]))
                z.append("\tdc.w\t%s-*" % ausgang_bei[(h, adr)])
                continue
            teile, x = [], adr
            while x < adr + n:
                if (h, x) in reloc_ziel:
                    teile.append(("l", reloc_ziel[(h, x)]))
                    x += 4
                else:
                    teile.append(("w", "$%04X" % struct.unpack(">H", daten[x:x + 2])))
                    x += 2
            erste = True
            gruppe = []
            for art, wert in teile + [(None, None)]:
                if gruppe and art != gruppe[0][0]:
                    zeile = "\tdc.%s\t%s" % (gruppe[0][0], ",".join(g[1] for g in gruppe))
                    if erste:
                        zeile += "\t; %05X  %s" % (adr, text)
                        erste = False
                    z.append(zeile)
                    gruppe = []
                if art:
                    gruppe.append((art, wert))

        if (h, bis) in FORTSETZUNGEN:
            z.append("\tjmp\t%s\t; ab $%05X Blitter, bei uns: %s"
                     % (FORTSETZUNGEN[(h, bis)], bis, FORTSETZUNGEN[(h, bis)]))

    for bh, bv, bb in DATEN_BLOECKE:
        z += ["", "; " + "-" * 70,
              "; Vorbelegte Daten der Bibliothek, AM2_CPU %d:$%05X..$%05X, Inhalt und"
              % (bh, bv, bb), "; Anordnung wie im Original.", "; " + "-" * 70,
              "\tSECTION\tFast_DATA,data", "\tcnop\t0,4"]
        if any(hunks[bh]["reloc"].get(o) is not None for o in range(bv, bb)):
            raise Fehler("Datenblock %d:$%05X enthaelt Relokationen" % (bh, bv))
        z += bytes_zeilen(hunks[bh]["daten"], bh, bv, bb,
                          {k for k in daten_marken if k[0] == bh}, "Daten",
                          lambda hh, v: daten_marken[(hh, v)])
        z.append("\teven")
    for bh, bv, bb in BSS_BLOECKE:
        z += ["", "; " + "-" * 70,
              "; Interne Variablen der Bibliothek, AM2_CPU %d:$%05X..$%05X, Anordnung"
              % (bh, bv, bb), "; wie im Original.  Namen ohne Am2cpu_ sind Thalions.",
              "; " + "-" * 70, "\tSECTION\tFast_BSS,bss", "\tcnop\t0,4"]
        if (bh, bv) not in bss:
            bss[(bh, bv)] = marke(bh, bv)
        offs = sorted(v for h, v in bss if h == bh and bv <= v < bb)
        for i, v in enumerate(offs):
            naechst = offs[i + 1] if i + 1 < len(offs) else bb
            z.append("%s:\tds.b\t%d\t; %d:$%05X" % (bss[(bh, v)], naechst - v, bh, v))
        z.append("\teven")
    z += ["", "\tSECTION\tProgram,code", ""]

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        f.write("\n".join(z))
    print("  AM2_CPU-Code: %d Stuecke, %d Byte, %d Relokationen, %d BSS-Namen"
          " -> %s" % (len(STUECKE), bytes_ges, len(reloc_ziel), len(bss), a.out))
    print("    Thalions Namen: " + " ".join(sorted(extern)))
    print("    68020-Befehle in CPU_020-Stuecken: %d" % anzahl_020[0])
    print("    umgebogen (UMBIEGEN): %d Operanden" % len(umgebogen))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Fehler as e:
        sys.exit("am2cpu_code: ABBRUCH: %s" % e)

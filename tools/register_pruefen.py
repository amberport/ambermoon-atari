#!/usr/bin/env python3
"""
register_pruefen.py -- welche Routine beschreibt ein Register, das sie nicht
gesichert hat?

Warum
=====
Diese Fehlerklasse hat das Projekt mehrfach Zeit gekostet, und sie ist von
aussen kaum zu erkennen: Der Aufrufer verliert einen Wert, den er fuer
sicher hielt, und der Schaden zeigt sich irgendwo anders.

Zwei Beispiele aus einem einzigen Hardwaretest:

  * `Update_mouse` sicherte d0-d3 und beschrieb d4.  `Feedback` benutzt d4
    als Zaehler seiner Warteschleife und ruft `Update_mouse` darin -- `dbf`
    zaehlte danach von einem zufaelligen Wert herunter.  Bei $FF00 sind das
    rund achtzehn Minuten bei 60 Hz.  Auf dem Geraet sah das so aus, als
    haenge das Programm.

  * `Resolve_tile` sicherte a3 nicht.  `Display_2D_person` ruft es, und der
    Aufrufer darueber fuehrt in a3 den Zeiger auf den Charaktereintrag.
    Nach dem ersten gezeichneten Charakter lief die Schleife durch fremden
    Speicher.

Beides faellt weder beim Uebersetzen auf noch im Emulator, solange man nicht
genau die betroffene Stelle bedient.

Was es findet und was nicht
===========================
Gemeldet wird jedes Register, das als Ziel eines Befehls auftaucht und nicht
in der `movem`-Liste am Anfang der Routine steht.  **Rueckgabewerte sehen
genauso aus** -- eine Routine, die ihr Ergebnis in d0 liefert, steht
zwangslaeufig in der Liste.  Die Ausgabe ist also kein Fehlerbericht,
sondern eine Liste zum Durchsehen; bekannte Rueckgaben stehen in AUSNAHMEN
und werden uebergangen.

**Routinen ohne `movem` am Anfang kann das Werkzeug nicht pruefen** -- es
weiss dann nicht, was gesichert sein sollte.  Sie werden am Ende aufgezaehlt,
damit sie wenigstens sichtbar sind.  Genau eine solche Routine hat einen
Fehler gekostet: `Get_entry` benutzt d2 und sichert nichts, und ein Aufrufer
hielt dort seinen Wert (Erkenntnis 67).

Register, die nur indirekt geschrieben werden, findet es ebenfalls nicht.

    python3 tools/register_pruefen.py
"""
import glob
import os
import re
import sys

# Routine -> Register, die dort absichtlich als Ergebnis herauskommen.
AUSNAHMEN = {
    "Teildatei_waehlen": {"d1"},  # Dateinummer des Behaelters (Erkenntnis 197)
    "Baum_heil":        {"d0"},   # 1 = Objektbaum durchlaufbar, 0 = nicht
    "Find_chain":       {"d0"},
    "Event_bit_nr":     {"d0"},
    "Gegenprobe_karte": {"d0"},   # 0 = Originalkarte stimmt, -1 nicht
    "Packkopf_aufloesen": {"d6"}, # Handle der ausgepackten Daten (Load_subfile)
    "Eintrag_holen":    {"d0"},   # Container-Teil von Load_subfile: das Handle
    "Ereignisbild_aufweiten": {"d0"},  # Handle des aufgeweiteten Bildes
    # Bruecke zu Thalions Feedback: d0 = 0 ausfuehren, -1 verworfen
    # (Erkenntnis 167).  Beide Namen, weil das Werkzeug nach dem ersten
    # Einsprung mit movem geht und der zweite ihn mitbenutzt.
    "Taste_rueckmelden_maus":  {"d0"},
    "Taste_rueckmelden_taste": {"d0"},
    "Access_bit_array": {"d0"},
    # a3 ist bei Resolve_tile die Rueckgabe, nicht Schmierpapier: die
    # Adresse der Kachel, die Put_masked_block dort erwartet.  Das einmal
    # uebersehen und "behoben" zu haben, hat die ganze Karte zerstoert
    # (Erkenntnis 60).
    "Resolve_tile":     {"d0", "a3"},
    # ST-Bau (ST_LIB.S, ST.S): Rueckgaben
    "St_cookie":        {"d0"},   # Wert des Cookies
    "St_eintrag":       {"a0"},   # der Eintrag
    "St_kachel":        {"a3"},   # das umgesetzte Symbol (P3)
    "St_abschrift_zeiger": {"d0"},  # Adresse: Abschrift oder MEM_ADR (E12)
    "Tile_frames":      {"d0"},
    # Beschneiden gegen die CA: Zeile, Hoehe und Quelle kommen beschnitten
    # zurueck (LIBRARY.S, wie in AM2_CPU die Blockroutinen selbst).
    "Block_beschneiden": {"a0", "d1", "d7"},
    "Load_map":         {"d0"},
    "Load_chest":       {"d0"},
    "Load_objects":     {"d0"},	# Rueckgabe: 0 geladen / -1 Fehler
    "Map_click_dir":    {"d0"},
    "Char_removed":     {"d0"},
    "Check_event_save_status": {"d0"},  # 0/1 aus sne nach Thalions Access_bit_array
    "Load_party_data":  {"d0"},	# Rueckgabe: 0 geladen / -1 Fehler
    "Fleck_adresse":    {"a1"},
    "Tile_flags":       {"d0"},
    # R_range (RASTER.S): Verlaufsfarbe und Platz einer Zeile; Zahl der
    # Plaetze, die Set_fade danach blendet.
    "Zeilenersatz":     {"d0", "d1"},
    "Bereiche_sammeln": {"d0"},
    "Platz_rueck":      {"d4"},   # Get_pixel: Platz -> Bank + Verlaufsfarbe (R_range); ST: Register -> Farbe
    "Text_mitte":       {"d0"},
    "Text_breite":      {"d0"},
    "Party_satz":       {"a3"},
    "Item_bits_hole":   {"d1"},	# Rueckgabe: Item_bits_STATIC
    "Allocate_memory":  {"d0"},	# Rueckgabe: Handle
    "Speicher_holen":   {"d0"},	# Rueckgabe: Handle (MEMORY.S, 267)
    "Allocate_CHIP":    {"d0"},	# dasselbe unter Thalions zweitem Namen
    "Create_fake_handle": {"d0"},	# Rueckgabe: vorgetaeuschtes Handle
    "Get_pixel":        {"d4"},	# Rueckgabe: Farbe des Punktes
    "Farbbank":         {"d0"},	# Rueckgabe: Bankversatz der Bildzeile
    "Farbbank_spanne":  {"d0", "d1"},	# Rueckgabe: Bank und Grenzzeile
    "Rasterbank_spanne": {"d0", "d1"},	# Rueckgabe: Bank und Grenzzeile
    "Kachel_holen":     {"a3"},	# Rueckgabe: Eintrag im Kachelspeicher
    "Quelle_aufweiten": {"a0"},	# Rueckgabe: Zwischenpuffer oder 0
    # Not a return value: Draw_box saves all registers before it calls the
    # fill (FALCON_LIB.S); the movem the tool sees is the per-block save
    # inside the loop, not a prologue.
    "Box_fuellen":      {"a0", "a2", "d0", "d1", "d4", "d5", "d7"},
    "Read_key":         {"d0"},	# Rueckgabe: Tastencode
    "Keymap_zeichen":   {"d0"},	# Rueckgabe: Kennung mit Zeichen in Bit 0-7 (260)
    "Load_subfile":     {"d0"},	# Rueckgabe: Speicher-Handle (Thalions .b)
    "Load_file":        {"d0"},	# Rueckgabe: Speicher-Handle
    "Datei_lesen":      {"d0", "d1"},	# Rueckgabe: Handle und Laenge
    "Eintrag_lage":     {"d0", "d1"},	# Rueckgabe: Versatz und Laenge
    # Load_subfile reads only its entry (FILES_SUP.S, 2026-10-21)
    "Eintrag_lesen":    {"d0", "d2", "d3", "d5", "d7"},  # handle, id, count, length, entry
    "Eintrag_suchen":   {"d0", "d2", "d3", "d4", "d5", "d7"},  # status, id, count, offset, length, entry
    "Behaelter_oeffnen": {"d0", "a2"},  # file handle and name
    "Offen_lesen":      {"d0"},   # 0 or the read error
    "Eintrag_aus_datei": {"d0"},  # handle of the entry
    "Datei_sichern":    {"d0"},	# Rueckgabe: 0 gut / -1 Fehler
    "Amiga_nach_videl": {"d0"},	# Rueckgabe: VIDEL-Registerwert
    "Claim_pointer_d6": {"a0"},	# Rueckgabe: Zeiger zum Handle in d6
    "Datei_name":       {"a0"},	# Rueckgabe: Zeiger auf den Dateinamen
    "Mem_eintrag":      {"a0"},	# Rueckgabe: Tabelleneintrag
    "Aktuelle_CIL":     {"a0"},	# Rueckgabe: die CIL des Feldes
    "Inv_slot_at":      {"d0"},
    "Inv_suche":        {"d2"},
    "Inv_pkt_addr":     {"a0"},
    "Chest_slot_at":    {"d0"},
    "Chest_pkt_addr":   {"a0"},
    "Portrait_at":      {"d0"},
}

SPRUNG = ("b", "db", "j", "rt", "cmp", "tst", "btst", "pea", "movem", "trap")


def maske(text):
    """movem-Liste wie d0-d3/a0-a2 zu einer Menge von Registernamen."""
    aus = set()
    for teil in text.split("/"):
        teil = teil.strip()
        m = re.fullmatch(r"([ad])(\d)-([ad])(\d)", teil)
        if m and m.group(1) == m.group(3):
            for i in range(int(m.group(2)), int(m.group(4)) + 1):
                aus.add(m.group(1) + str(i))
        elif re.fullmatch(r"[ad]\d", teil):
            aus.add(teil)
    return aus


def routinen(pfad):
    """Jede Routine mit Namen, gesicherten und beschriebenen Registern."""
    zeilen = open(pfad, encoding="utf-8").read().split("\n")
    i = 0
    while i < len(zeilen):
        m = re.match(r"^([A-Za-z_]\w*):", zeilen[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        # Das Ende der Routine ist die naechste *grosse* globale Marke.  Im
        # Projekt heissen Routinen wie im Original mit grossem Anfangs-
        # buchstaben, Sprungziele innerhalb einer Routine klein -- ss_out,
        # db_row, fb_los.  Wer nur auf den Kommentarblock "; ***" achtet,
        # zaehlt Code der Folgeroutine mit und meldet Fehler, die es nicht
        # gibt.
        j = i + 1
        rumpf = []
        while j < len(zeilen):
            nm = re.match(r"^([A-Z]\w*):", zeilen[j])
            if nm:
                break
            rumpf.append(zeilen[j])
            j += 1
        sm = re.search(r"movem\.l\s+([^,]+),-\(sp\)", "\n".join(rumpf))
        if sm:
            schreibt = set()
            for z in rumpf:
                z = z.split(";")[0]
                mm = re.match(r"^\S*\s+(\S+)\s+(.+)$", z)
                if not mm:
                    continue
                op, ops = mm.group(1), mm.group(2)
                if op.startswith(SPRUNG):
                    continue
                ziel = ops.split(",")[-1].strip()
                if re.fullmatch(r"[ad]\d", ziel):
                    schreibt.add(ziel)
            yield name, maske(sm.group(1)), schreibt
        i = j


def ohne_sicherung(pfad):
    """Routinen ohne movem am Anfang -- sie lassen sich nicht pruefen."""
    zeilen = open(pfad, encoding="utf-8").read().split("\n")
    aus, i = [], 0
    while i < len(zeilen):
        m = re.match(r"^([A-Z]\w*):", zeilen[i])
        if not m:
            i += 1
            continue
        name, j, rumpf = m.group(1), i + 1, []
        while j < len(zeilen) and not re.match(r"^([A-Z]\w*):", zeilen[j]):
            rumpf.append(zeilen[j])
            j += 1
        txt = "\n".join(rumpf)
        if txt.strip() and not re.search(r"movem\.l\s+[^,]+,-\(sp\)", txt):
            if re.search(r"^\s*(move|add|sub|lea|and|or|lsl|lsr|mulu|divu)", txt, re.M):
                aus.append(name)
        i = j
    return aus


def main():
    wurzel = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    treffer = 0
    ungeprueft = []
    for pfad in sorted(glob.glob(os.path.join(wurzel, "engine", "src", "**", "*.S"),
                                 recursive=True)):
        kurz = os.path.relpath(pfad, os.path.join(wurzel, "engine", "src"))
        ungeprueft += [(kurz, n) for n in ohne_sicherung(pfad)]
        for name, gesichert, schreibt in routinen(pfad):
            fehlt = schreibt - gesichert - AUSNAHMEN.get(name, set())
            if fehlt:
                print("  %-20s %-24s beschreibt ungesichert: %s"
                      % (kurz, name, " ".join(sorted(fehlt))))
                treffer += 1
    if treffer:
        print("\n%d Stelle(n) zum Durchsehen." % treffer)
        print("Ist es ein Rueckgabewert, gehoert die Routine in AUSNAHMEN.")
        return 1
    print("  Keine Routine beschreibt ein ungesichertes Register.")
    if ungeprueft:
        print("  Ungeprueft, weil ohne movem am Anfang -- was sie beschreiben,"
              " muss der Aufrufer wissen:")
        for kurz, n in ungeprueft:
            print("     %s %s" % (kurz, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())

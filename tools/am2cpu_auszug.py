#!/usr/bin/env python3
"""am2cpu_auszug.py -- die Daten der nicht freigegebenen Bibliothek, beim Bau.

DEVIATION (goals 1 and 2), docs/17-deviations.md D2: library data taken
from AM2_CPU at build time.

Thalions Code spricht Daten an, die in keinem freigegebenen Quelltext und in
keiner Spieldatei stehen, nur im Amiga-Programm AM2_CPU: die Hauptpalette,
Fensterkacheln, Statusleiste, Tastenrahmen, Zeichensatz ...  Auf dem Amiga
liegen sie dort an festen Adressen, und Thalions Code greift mit
``lea.l Name,a0`` darauf zu.

**AM2_CPU wird zur Laufzeit nie gelesen** (Nutzer, 2026-09-27): es ist ein
Amiga-Executable, keine Spieldatei.  Dieses Werkzeug holt die Stuecke beim
Bau heraus und schreibt sie als Assemblerdatei nach build/am2cpu_daten.i;
engine.s bindet sie ein.  Damit stehen die Namen an festen Adressen wie im
Original, und nichts davon liegt im Repository.

The first places are the ones the old converter falcon_gfx.py (now in
tools/archiv/) had used and proven (findings 118, 64, 184).  Newer ones are
proven through Thalion's assembled code (CODEBELEGE, VERWEISE): at build
time the tool checks that the place there points at exactly this piece.
Since 2026-09-28 nothing comes from memory dumps any more, not the mouse
pointer and Ouch either.

Aufruf:  am2cpu_auszug.py [--amberfiles DIR] [--out build/am2cpu_daten.i]
"""
import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import read_hunks                          # noqa: E402
import paths  # noqa: E402

# The interface palette as read from the Copper list of an Amiga memory
# dump (finding 64), (R, G, B) with 4 bits each; the check below holds
# Main_pal in hunk 4 against it.  It came from falcon_gfx.py, which went to
# tools/archiv/ on 2026-10-29.
STATUS_PALETTE = [
    (0x0, 0x0, 0x0), (0xE, 0xD, 0xC), (0xF, 0xF, 0xE), (0xB, 0xB, 0xC),
    (0x8, 0x9, 0xA), (0x5, 0x7, 0x8), (0x2, 0x5, 0x6), (0x0, 0x3, 0x4),
    (0xF, 0xC, 0x9), (0xE, 0xA, 0x7), (0xC, 0x8, 0x5), (0xA, 0x6, 0x3),
    (0x8, 0x4, 0x2), (0x5, 0x2, 0x1), (0xB, 0x8, 0x0), (0xD, 0xA, 0x0),
    (0xF, 0xC, 0x0), (0xF, 0x9, 0x0), (0xC, 0x6, 0x0), (0x8, 0x1, 0x2),
    (0xC, 0x4, 0x3), (0xE, 0x6, 0x3), (0xA, 0xA, 0x4), (0x5, 0x7, 0x3),
    (0x2, 0x5, 0x4), (0x5, 0x0, 0x9), (0x2, 0x2, 0x2), (0x4, 0x4, 0x3),
    (0x6, 0x6, 0x5), (0x8, 0x8, 0x7), (0xA, 0xA, 0x9), (0xC, 0xC, 0xB),
]

# (Name, Hunk, Versatz, Laenge, Beleg)
STUECKE = [
    # Die Palette der Bedienoberflaeche, 32 Amiga-Farbworte.  Wort fuer Wort
    # STATUS_PALETTE above, am Truhen-Speicherauszug belegt
    # (Erkenntnis 64).  Datei 0x43688.
    ("Main_pal", 4, 0x5B18, 64, "Hunk 4, Hauptpalette"),
    # Acht Fensterkacheln 16x16, drei Ebenen (Put_window_part, Erk. 118).
    ("Window_icons", 3, 0x00C0, 8 * 96, "Hunk 3, Fensterrahmen"),
    # Statusleiste (Display_status_block): links, Mitte, rechts 16x36, der
    # Riegel 32x1, alle drei Ebenen, lueckenlos hintereinander.
    ("Status_L", 3, 0x19D8, 216, "Hunk 3, Statusleiste links"),
    ("Status_M", 3, 0x19D8 + 216, 216, "Hunk 3, Statusleiste Mitte"),
    ("Status_R", 3, 0x19D8 + 432, 216, "Hunk 3, Statusleiste rechts"),
    ("Status_TB", 3, 0x19D8 + 648, 12, "Hunk 3, Riegel ueber/unter dem Portrait"),
    # Der leere Portraitplatz, 32x34, drei Ebenen.
    ("Empty_portrait", 3, 0x2DA8, 4 * 3 * 34, "Hunk 3, leerer Platz"),
    # Tastenrahmen 32x17, drei Ebenen, gedrueckt direkt dahinter.
    ("Button_up", 3, 0x2860, 204, "Hunk 3, Tastenrahmen"),
    ("Button_down", 3, 0x2860 + 204, 204, "Hunk 3, Tastenrahmen gedrueckt"),
    # Welche Palette zu welchem Ereignisbild gehoert (ShowPicTxt_ModInit).
    # Acht Byte, das neunte (0) liest das Original fuer das neunte Bild mit
    # (Erkenntnis 184).
    ("Event_pix_palette_table", 4, 0x770A, 9, "Hunk 4, Ereignisbild-Paletten"),
    # Die drei Welten (Init_world, MAP/MAP.S), je sieben Worte: Welt- und
    # Kartengroesse, erste Kartennummer, Morgen- und Abenddaemmerung.  Das
    # Muster (.., .., 50, 50, 1, ..) kommt in AM2_CPU genau einmal vor.
    ("World_data", 4, 0x75FE, 3 * 14, "Hunk 4, Weltdaten"),
    # Sinus fuer die 3D-Ansicht: 1024 Worte (slang), sin * 2^14; Thalion
    # liest den Kosinus bei +256 und maskiert mit slang*2-1 auf den
    # Byteversatz.  Gefunden an Get_draw_size (lea Sinus_table,a0 ist dort
    # der erste Befehl, AM2_CPU 0:$10CCE); die naechste Tabelle beginnt genau
    # 2048 Byte weiter (docs/02 A5, Erkenntnis 195).
    ("Sinus_table", 4, 0x65C4, 2048, "Hunk 4, Sinustabelle"),
    # Groesse je Rasse in cm, ein Wort je Rasse (Max_races = 15), gelesen
    # von Calculate_camera_height (3D_MAP.S; AM2_CPU 0:$12094).
    ("Race_heights", 4, 0x76A8, 2 * 15, "Hunk 4, Rassengroessen"),
    # Die Portraitnummern des Charaktereditors (CHARACTE.S Chared_ModInit:
    # lea Chared_portraits,a1 / moveq #Portraits_per_sex*2-1,d7), je vier
    # maennlich, dann weiblich: 2, 25, 7, 23, 31, 38, 44, 51.  **Race_heights
    # hat in AM2_CPU nur neun Worte**; Thalion liest fuer Rasse 9-14 in diese
    # Tabelle hinein, darum ueberlappen die beiden (wie Erkenntnis 184).
    ("Chared_portraits", 4, 0x76BA, 2 * 8, "Hunk 4, Portraits des Charaktereditors"),
    # Zauberdaten (GAME_OFF.S: Spell_area_bits ... Spell_data_size = 5), je
    # Zauberklasse Max_spells = 30 Saetze, sieben Klassen.
    ("Spell_data", 4, 0x61AA, 7 * 30 * 5, "Hunk 4, Zauberdaten"),
    # Sechs Symbole der laufenden Zauber 16x16, drei Ebenen, Abstand 96
    # (Display_spells).  Liegen direkt hinter Status_TB.
    ("Spell_icons", 3, 0x1C6C, 6 * 96, "Hunk 3, Zaubersymbole"),
    # Elf Bilder "Poof" 16x16, drei Ebenen (Dissolve_HDOB in EVENTS.S:
    # Breite 1, Hoehe 16, Tiefe 3; Animate_HDOB mit d0 = 11).  Liegen direkt
    # hinter Empty_portrait.
    ("Dissolve", 3, 0x2F40, 11 * 96, "Hunk 3, Aufloesen"),
    # Sprechblase "OUCH!" 32x23, drei Ebenen (Display_2D_map: Put_masked_block
    # mit d4=24, d5=3, d6=2, d7=23).
    ("Ouch", 3, 0x166C, 4 * 3 * 23, "Hunk 3, Sprechblase"),
    # Kleine 2D-Tabellen, lueckenlos vor World_data ($75FE).  Je Reiseart
    # ein Byte (GAME_OFF.S: On_foot ... Sandskimmer, Max_travelmodes = 11).
    ("Level_start_EPs", 4, 0x75C6, 2 * 11, "Hunk 4, Start-EP je Klasse (Max_classes)"),
    ("World_move_delay", 4, 0x75DC, 11, "Hunk 4, Schrittpause je Reiseart"),
    ("Travel_speed", 4, 0x75E7, 11, "Hunk 4, Zeitraffer je Reiseart"),
    ("Travel_music", 4, 0x75F2, 11, "Hunk 4, Musik je Reiseart"),
    # Breite, Hoehe je Standbild (Display_2D_transport).  Fuenf Paare; ihre
    # Summe in fuenf Ebenen ist genau die entpackte Laenge von Stationary
    # (3480 Byte).
    ("Stationary_dimensions", 4, 0x7712, 5 * 4, "Hunk 4, Standbildmasse"),
    # Je Zustand ein Gegenstandsindex (PLACES.S, 16 Zustaende).
    ("Condition_object_index_table", 4, 0x7726, 16, "Hunk 4, Zustand -> Gegenstand"),
    # Kleine Schreibpuffer der Gegenstandsansicht (INVENTOR.S ItemView2):
    # " 01" (SDecL_convert schreibt hinein) und "(01)" (DecR_convert ab +1,
    # dann ")" an +3).
    ("Attrskill_nr", 4, 0x070E, 4, "Hunk 4, Bonuszahl"),
    ("Charges_txt", 4, 0x0712, 5, "Hunk 4, Ladungen"),
    # Kampf (COMBAT.S Combat_ModInit): je Kampfhintergrund vier Byte,
    # Bildnummer und drei Paletten (Tag, Daemmerung, Nacht), 16 Eintraege.
    # Die 3D-Tabelle folgt lueckenlos, dahinter Race_heights.
    ("Combat_bg_2D_table", 4, 0x7628, 16 * 4, "Hunk 4, Kampfhintergruende 2D"),
    ("Combat_bg_3D_table", 4, 0x7668, 16 * 4, "Hunk 4, Kampfhintergruende 3D"),
    # Palette der Taktikflaeche unter dem Kampfbild (MODULES.S Combat_RL),
    # 32 Amiga-Farbworte; Set_layout_colours kopiert die letzten sechs.
    ("Tactic_pal", 4, 0x5B98, 64, "Hunk 4, Taktikpalette"),
    # Schaden der Zerstoerungszauber (COMBAT_M.S Do_destruction_damage):
    # je Zauber ab Nummer 15 Mindest- und Hoechstwert als Worte.  Endet
    # lueckenlos vor Event_pix_palette_table ($770A).
    ("Destruction_table", 4, 0x76CA, 16 * 4, "Hunk 4, Zerstoerungsschaden"),
    # Rotes Kreuz ueber einem Feld der Taktikflaeche (TACTIC.S:
    # Put_masked_silhouette mit d5 = 1, d6 = 1, d7 = Tactic_cell_height = 13).
    ("Red_cross", 3, 0x35A4, 13 * 2, "Hunk 3, rotes Kreuz"),
    # Der Mausbereich "ganzes Bild" (X1, X2, Y1, Y2), den Init_module
    # auflegt, wenn ein Modul keinen eigenen mitbringt: 0,319,0,199.
    ("Default_MA", 4, 0x491A, 4 * 2, "Hunk 4, Mausbereich Vollbild"),
    # **2D-Grafik** (Erkenntnis 256).  Jede Stelle ueber Thalions "lea Name"
    # gefunden (CODEBELEGE unten); die Laenge ist das Mass, das Thalions
    # Aufruf uebergibt (Breite in Worten x Hoehe x Ebenen x 2), und sie fuellt
    # jeweils genau die Luecke bis zum naechsten Stueck in Hunk 3.
    ("Cross_hatch", 3, 0x00A0, 2 * 16 * 1, "Hunk 3, Schraffur 16x16, 1 Ebene (Options_ModInit)"),
    ("Status_icons", 3, 0x03C0, 23 * 160, "Hunk 3, 23 Zustandssymbole 16x16, 5 Ebenen (Icon_size)"),
    ("Giant_eagle_shape", 3, 0x1220, 4 * 29 * 5, "Hunk 3, Adler 32x29, 5 Ebenen (Giant_eagle_HDOB)"),
    ("Damage_star", 3, 0x1464, 4 * 26 * 5, "Hunk 3, Schadensstern 32x26, 5 Ebenen"),
    ("Magic_stars", 3, 0x1780, 4 * 9 * 5 * 2, "Hunk 3, vier Funken 16x9, 5 Ebenen"),
    ("Magic8_stars", 3, 0x18E8, 4 * 10 * 3 * 2, "Hunk 3, vier Sterne 16x10, 3 Ebenen (Minikarte)"),
    ("Windchain", 3, 0x1EAC, 4 * 15 * 3, "Hunk 3, Windkette 32x15, 3 Ebenen"),
    ("Eye_off", 3, 0x1F60, 4 * 32 * 3, "Hunk 3, Auge zu 32x32, 3 Ebenen"),
    ("Eye_on", 3, 0x20E0, 4 * 32 * 3, "Hunk 3, Auge offen 32x32, 3 Ebenen"),
    ("Daynight_icons", 3, 0x2260, 4 * 32 * 12, "Hunk 3, vier Tageszeiten 32x32, 3 Ebenen"),
    ("Chequered", 3, 0x29F8, 4 * 11 * 1, "Hunk 3, Schraffur gesperrter Tasten 32x11, 1 Ebene"),
    ("Compass", 3, 0x2A24, 4 * 32 * 3, "Hunk 3, Kompass 32x32, 3 Ebenen"),
    ("Swordshield", 3, 0x2BA4, 2 * 9 * 3 * 2, "Hunk 3, Schwert und Schild 16x9, 3 Ebenen"),
    ("Death_mask", 3, 0x2C10, 4 * 34 * 3, "Hunk 3, Totenmaske 32x34, 3 Ebenen"),
    ("Ankh_symbol", 3, 0x3360, 4 * 29 * 5, "Hunk 3, Ankh 32x29, 5 Ebenen (Heiler)"),
    ("Broken", 3, 0x35BE, 2 * 16 * 1, "Hunk 3, Aufdruck kaputt 16x16, 1 Ebene"),
    # Die Farben der Automap-Haelfte, direkt hinter Main_pal (VERWEISE).
    ("Automap_pal", 4, 0x5B58, 64, "Hunk 4, Automap-Palette"),
    # 3D-Staedte (3D_MAP.S Set_C3_light_level): je Welt drei Himmelsverlaeufe
    # zu C3_horizon = 72 Farbworten (mulu.w #C3_horizon*6), dahinter
    # lueckenlos je Welt zwei Saetze zu Pal_size = 32 Byte (mulu.w
    # #2*Pal_size, lea Pal_size(a0); Dim_colours mit d7 = Pal_size/2).
    # Drei Welten; hinter Tactic_pal, endet vor Spell_data ($61AA).
    ("Sky_ranges", 4, 0x5BD8, 3 * 72 * 6, "Hunk 4, Himmelsverlaeufe 3D-Staedte"),
    ("C3_palettes", 4, 0x60E8, 3 * 2 * 32, "Hunk 4, Paletten 3D-Staedte"),
    # Der Ladefehlerschirm der Bibliothek (0:$2637C, Erkenntnis 268): die
    # Ueberschrift und die Namen der 45 Dateiarten (Memory block ... Object
    # graphics), je 22 Byte mit Endnull.  Das Original nimmt sie ueber die
    # Zeigertabelle 4:$4934 (0:$263AA "lea ...,a2 / lsl.w #2,d0"), deren 45
    # Zeiger in Schritten zu 22 auf genau diese Saetze zeigen; wir rechnen
    # mit Nummer * 22.
    ("Datei_arten", 4, 0x49E8, 45 * 22, "Hunk 4, Namen der Dateiarten"),
    ("Ladefehler_text", 4, 0x4DC6, 26, "Hunk 4, FILE COULDN'T BE LOADED :"),
]

# Die Mauszeiger, Hunk 4 $5028-$5B17: 28 Saetze zu 100 Byte, je Hotspot
# (x, y als Worte) und ein Bild 16x16 in drei Ebenen, zeilenweise (je Zeile
# drei Worte).  Farbe = 24 + Bildwert, 0 ist durchsichtig.  Die 13 Bilder
# aus den frueheren Amiga-Speicherauszuegen stimmen Punkt fuer Punkt damit
# ueberein (2026-09-28).  Namen wie in Thalions Quelltext; None = nur die
# Bibliothek benutzt den Satz (Dateizugriff, Speicher).
ZEIGER_HUNK, ZEIGER_ANFANG, ZEIGER_SATZ = 4, 0x5028, 100
ZEIGER = [
    "Default_Mptr",
    "Up_2D_Mptr", "Down_2D_Mptr", "Left_2D_Mptr", "Right_2D_Mptr",
    "Upleft_2D_Mptr", "Upright_2D_Mptr", "Downleft_2D_Mptr", "Downright_2D_Mptr",
    "Forward_3D_Mptr", "Back_3D_Mptr", "Left_3D_Mptr", "Right_3D_Mptr",
    "Turnleft_3D_Mptr", "Turnright_3D_Mptr", "Turn180_left_Mptr", "Turn180_right_Mptr",
    "Zzz_Mptr", "Eye_Mptr", "Mouth_Mptr", None, "Gold_Mptr", "Food_Mptr",
    "Pick_Mptr", "Hand_Mptr", "EyeMouth_Mptr", "Click_Mptr", None,
]

# Mousetab_2D und Mousetab_3D (MAP/MAP.S), 18 Langworte in Hunk 4.
MOUSETAB = (0x3C44, ["Upleft_2D_Mptr", "Up_2D_Mptr", "Upright_2D_Mptr",
                     "Left_2D_Mptr", "Zzz_Mptr", "Right_2D_Mptr",
                     "Downleft_2D_Mptr", "Down_2D_Mptr", "Downright_2D_Mptr",
                     "Turnleft_3D_Mptr", "Forward_3D_Mptr", "Turnright_3D_Mptr",
                     "Left_3D_Mptr", "Zzz_Mptr", "Right_3D_Mptr",
                     "Turn180_left_Mptr", "Back_3D_Mptr", "Turn180_right_Mptr"])

# Weitere Stellen, an denen Thalions uebersetzter Code auf einen Zeiger oder
# auf Ouch zeigt: (Hunk, Versatz des Langworts, Name, Stelle im Quelltext).
# Vor dem Verschieben steht dort der Versatz im Zielhunk.
VERWEISE = [
    (0, 0xD624, "Default_Mptr", "MAP.S Reset_map_mouse: lea Default_Mptr,a0"),
    (4, 0x1B08, "Click_Mptr", "MODULES.S Wait_4_user_Mod"),
    (4, 0x258C, "Pick_Mptr", "MODULES.S Move_item_Mod"),
    (4, 0x2A0E, "Pick_Mptr", "MODULES.S Move_LAY3_item_Mod"),
    (4, 0x26EA, "EyeMouth_Mptr", "MODULES.S, Moduldeskriptor mit Made_area"),
    (0, 0x6F22, "EyeMouth_Mptr", "ACTIONS.S: lea EyeMouth_Mptr,a0"),
    (0, 0x6F30, "Mouth_Mptr", "ACTIONS.S .Mouth: lea Mouth_Mptr,a0"),
    (4, 0x2748, "Eye_Mptr", "MODULES.S Eye-Modul"),
    (4, 0x277E, "Hand_Mptr", "MODULES.S 2D Hand action"),
    (4, 0x27B4, "Mouth_Mptr", "MODULES.S 2D Mouth action"),
    (0, 0x495E, "Gold_Mptr", "INVENTOR.S: move.l #Gold_Mptr,Mouse_ptr(a0)"),
    (0, 0x4A6C, "Food_Mptr", "INVENTOR.S: move.l #Food_Mptr,Mouse_ptr(a0)"),
    (0, 0xBEA0, "Zzz_Mptr", "MINIMAP.S: Push Mptr,Zzz_Mptr"),
    (0, 0xDCBA, "Ouch", "2D_MAP.S Display_2D_map: lea Ouch,a0"),
    (0, 0x04A2, "Travel_speed", "MAIN.S: lea Travel_speed,a0 / move.b 0(a0,d0.w),d0"),
    (0, 0xCDFE, "World_move_delay", "MAP.S: lea World_move_delay,a0 ... beq.s"),
    (0, 0xD734, "Travel_music", "MAP.S: lea Travel_music,a0 ... bne.s"),
    (0, 0x15C8, "Level_start_EPs", "MAIN.S Check_member_levels: lea Level_start_EPs,a1"),
    (0, 0xE03C, "Stationary_dimensions", "2D_MAP.S Display_2D_transport"),
    (0, 0x16594, "Condition_object_index_table", "PLACES.S: lea ...,a1 / moveq #0,d1"),
    # MODULES.S Automap_Mod, .RL: "R_palette Middle_Y+1,Automap_pal".  Der
    # Satz traegt dieselben Tasten und dasselbe Feld 216,303,45,188 wie
    # Thalions Quelltext.
    (4, 0x346C, "Automap_pal", "MODULES.S Automap_Mod .RL"),
]

# **Meldungen** (Stufe 1b).  In 1.20 stehen die Texte in Text.amb, Teil 1
# (46 Einzeltexte, tools/textmarken.py).  Die Bibliothek traegt beim Start
# einen Zeiger auf jeden in einen festen Platz ein; wohin, sagt eine Tabelle
# in Hunk 6 ab $00: 46 Langworte, Text n -> Platz.  Die Plaetze 3-45 liegen
# in Hunk 4, und fast alle in **Textlisten**: Folgen von Zeigern, Ende null,
# deren Luecken Thalions Code fuellt (Print_member_text setzt den Namen an
# 0, "move.l #Number,8(a0)" ...).  Die Listen stehen in der Datei als
# Nullen, ihre Grenzen ergeben sich aus den Anfaengen.
#
# Wir legen die Listen beim Bau an, mit "dc.l Textamb_n" -- den Marken,
# die textmarken.py auf die Texte in Textdaten setzt.  Die Texte selbst
# liest Lade_texte zur Laufzeit (Leitziel 2).
MELDUNG_TABELLE = (6, 0x00, 46)
# (Name, Anfang in Hunk 4, Stellen in Hunk 0, an denen ein lea/move.l darauf
# zeigt, Thalions Aufrufstelle).  Aufsteigend; jede Liste endet vor der
# naechsten, die letzte vor MELDUNG_ENDE.
MELDUNG_LISTEN = [
    ("Known_error_text", 0x7D0E, [0x29212], "HULL/CONTROLS.S Disk_error_handler"),
    ("Disk_request_text", 0x7D26, [0x292B2], "HULL/CONTROLS.S Disk_requester .No"),
    ("Save_disk_request_text", 0x7D36, [0x292AA], "HULL/CONTROLS.S Disk_requester"),
    None,                                   # $7D3E: Ersatztext von AM2_CPU
    ("No_recup_text", 0x7F94, [0x7AD4], "ACTIONS.S: lea No_recup_text,a0"),
    ("Recup1_text", 0x7FA0, [0x7E1E], "ACTIONS.S: move.l #Number,8(a0)"),
    ("Recup2_text", 0x7FB4, [0x7E46], "ACTIONS.S: move.l #Number,8(a0)"),
    ("Aging_text", 0x7FD0, [0x7A40], "ACTIONS.S: Print_member_text"),
    ("Ageddeath_text", 0x7FDC, [0x7A68, 0x125C8], "ACTIONS.S, TIME.S"),
    ("BuySell_req_text", 0x7FE8, [0x17A6A], "PLACES.S BuySell_req: Prompt an 0"),
    ("Food_price_text", 0x7FF8, [0x176FC], "PLACES.S Print_food_price: Number an 4"),
    ("Make_level_text", 0x8008, [0x174C], "MAIN.S Make_levels: lea ...,a3"),
    ("Attack_text", 0x801C, [0x1A282], "COMBAT.S Print_attacking .Normal: clr.l 24(a1)"),
    ("Attack2_text", 0x8038, [0x1A268], "COMBAT.S Print_attacking: clr.l 16(a1)"),
    ("Broken_text", 0x804C, [0x4EBA, 0x1A384], "INVENTOR.S, COMBAT.S: lea ...,a2"),
    ("Hit_text", 0x8060, [0x1A2C4], "COMBAT.S Print_hitting: Number an 8"),
    ("EP_divide_text", 0x8074, [0x1B97A, 0x1BABE], "COMBAT/APRES.S: Number an 4"),
    ("Magic_action_text", 0x8084, [0x1DB1E], "COMBAT_M.S Print_magic_action"),
    ("Magic_object_text", 0x8098, [0x1DC0A], "COMBAT_M.S Print_magic_obj_action"),
    ("Wrong_answer_text", 0x80B4, [0x147E6, 0x147F4], "EVENTS.S Raetselmund: lea ...,a1"),
]
MELDUNG_ENDE = 0x80C0
# Einzeltexte, die Thalions freigegebener Quelltext als Text anspricht
# ("move.l #Divide_start_text,(a2)+"); 1.20 liest dort den Platz
# ("move.l $7F88,(a2)+").  Bei uns sind es Marken in Textdaten, gesetzt von
# textmarken.py: (Name, Text, Stellen in Hunk 0, Aufrufstelle).
MELDUNG_EINZEL = [
    ("Text_error_text", 9, [0x28DBE], "HULL/CONTROLS.S Find_large_text"),
    ("Out_of_memory_text", 11, [0x18BFE], "DIAGNOST.S Out_of_memory"),
    ("Divide_start_text", 12, [0x1A90], "MAIN.S Check_for_vital_items"),
    ("Divide_inter_text", 13, [0x1AC6], "MAIN.S Check_for_vital_items"),
    ("Divide_end_text", 14, [0x1ACE], "MAIN.S Check_for_vital_items"),
    ("That_text", 45, [0x147EC], "EVENTS.S Raetselmund: move.l #That_text,(a1)"),
]
# Magic_txt ("MAGIE") setzt die Startroutine in Hunk 8 ($168): sie ueberspringt
# in Spell_class_names sieben Texte und legt den achten nach $8100.  Die
# Marke setzt textmarken.py; hier wird nur die Routine gegengeprueft.
MAGIC_TXT_CODE = (8, 0x168, bytes.fromhex(
    "2479000080d470004a1a66fc52000c00000663f423ca00008100"))
MAGIC_TXT_STELLE = 0x5AC8        # INVENTOR.S ItemView2: "lea Magic_txt,a0"


def meldungen(hunks):
    """Die Textlisten als Assemblerzeilen; bricht ab, wenn etwas nicht passt."""
    h, o, n = MELDUNG_TABELLE
    platz = struct.unpack(">%dI" % n, hunks[h][o:o + 4 * n])
    text_von = {p: i for i, p in enumerate(platz) if i >= 3}
    if len(text_von) != n - 3 or not all(0x7D00 <= p <= MELDUNG_ENDE for p in text_von):
        raise SystemExit("am2cpu_auszug: Meldungstabelle in Hunk 6 passt nicht")
    for hn, stelle, erwartet in [(0, s, a) for name, a, st, _ in
                                 [m for m in MELDUNG_LISTEN if m] for s in st] + \
            [(0, s, platz[t]) for _, t, st, _ in MELDUNG_EINZEL for s in st] + \
            [(0, MAGIC_TXT_STELLE, 0x8100)]:
        if struct.unpack(">I", hunks[hn][stelle:stelle + 4])[0] != erwartet:
            raise SystemExit("am2cpu_auszug: Meldung -- 0:$%X zeigt nicht auf $%X"
                             % (stelle, erwartet))
    h, o, code = MAGIC_TXT_CODE
    if hunks[h][o:o + len(code)] != code:
        raise SystemExit("am2cpu_auszug: Magic_txt -- Startroutine in Hunk 8 passt nicht")
    z = ["", "; Meldungen -- Textlisten aus Hunk 4 ($%X-$%X), Plaetze nach der"
         % (MELDUNG_LISTEN[0][1], MELDUNG_ENDE),
         "; Tabelle in Hunk 6; Textamb_n sind die Einzeltexte in Textdaten."]
    einzel = {platz[t] for _, t, _, _ in MELDUNG_EINZEL}
    for k, m in enumerate(MELDUNG_LISTEN):
        if not m:
            continue
        name, anfang, _, wo = m
        ende = MELDUNG_ENDE
        for f in MELDUNG_LISTEN[k + 1:]:
            ende = f[1] if f else 0x7D3E
            break
        eintraege = []
        for p in range(anfang, ende, 4):
            if p in einzel:
                raise SystemExit("am2cpu_auszug: Einzeltext $%X in Liste %s" % (p, name))
            eintraege.append("Textamb_%d" % text_von[p] if p in text_von else "0")
        if eintraege[-1] != "0":
            raise SystemExit("am2cpu_auszug: Liste %s endet nicht mit null" % name)
        z += ["%s:			; $%X, %s" % (name, anfang, wo),
              "	dc.l	" + ",".join(eintraege)]
    return z


# Wo Thalions uebersetzter Code auf ein Stueck zeigt: (Name, Versatz des
# lea in Hunk 0, Befehlswort, Aufrufstelle[, Versatz im Stueck]).  Die
# Adresse im Befehl ist vor dem Verschieben der Versatz im Zielhunk.
# Gefunden mit am2cpu_lesen.py ueber die Befehlsfolge aus Thalions
# Quelltext (2026-09-28).
CODEBELEGE = [
    ("Attrskill_nr", 0x5A16, 0x41F9,
     "INVENTOR.S ItemView2_DisInit: lea Attrskill_nr,a0 vor SDecL_convert"),
    ("Charges_txt", 0x5B54, 0x41F9,
     "INVENTOR.S ItemView2_DisInit: lea Charges_txt,a0 vor Put_text_line"),
    ("Spell_data", 0x440A, 0x47F9,
     "INVENTOR.S Use_item: lea Spell_data,a3 vor mulu.w #Max_spells"),
    ("Spell_icons", 0x2526, 0x47F9,
     "DISPLAY.S Display_spells: lea Spell_icons,a3 / move.w #208,d0"),
    ("Dissolve", 0x69B6, 0x41F9,
     "moveq #11,d0 / moveq #3,d1 / lea Dissolve,a0 (fuenf Stellen)"),
    ("Combat_bg_2D_table", 0x18DCE, 0x41F9,
     "COMBAT.S Combat_ModInit: lea ...2D...,a0 / bra.s / lea ...3D...,a0"),
    ("Combat_bg_3D_table", 0x18DD6, 0x41F9,
     "COMBAT.S Combat_ModInit: .3D: lea ...,a0 / lsl.w #2,d0"),
    ("Tactic_pal", 0x1B812, 0x41F9,
     "COMBAT.S Set_layout_colours: lea Tactic_pal+26*2,a0 / moveq #6-1,d7",
     26 * 2),
    ("Destruction_table", 0x20190, 0x45F9,
     "COMBAT_M.S Do_destruction_damage: lea ...,a2 / sub.w #15,d0"),
    ("Red_cross", 0x1CB86, 0x41F9,
     "TACTIC.S: moveq #Tactic_cell_height,d7 / lea Red_cross,a0"),
    ("Chared_portraits", 0xC4AA, 0x43F9,
     "CHARACTE.S Chared_ModInit: move.w #2,Ink_colour / lea Chared_portraits,a1"),
    ("Default_MA", 0x278EE, 0x41F9,
     "HULL/MODULE_C.S Init_module: move.l MA_ptr(a1),d0 / bne / lea Default_MA,a0"),
    # 2D-Grafik: jede Stelle, an der Thalions Quelltext "lea Name" sagt.
    # Gefunden, indem die Befehle um das lea in unserem Bau in Hunk 0
    # gesucht wurden (Erkenntnis 256).
    ("Cross_hatch", 0x7EAE, 0x41F9, "ACTIONS.S Options_ModInit"),
    ("Status_icons", 0x225C, 0x41F9, "DISPLAY.S: lea Status_icons,a0 / Put_masked_icon"),
    ("Status_icons", 0x3C98, 0x41F9, "INVENTOR.S Display_Inv1_member_info"),
    ("Status_icons", 0x3CB4, 0x49F9, "INVENTOR.S: lea Status_icons,a4"),
    ("Giant_eagle_shape", 0xBD50, 0x41F9, "MAGIC.S: Create_fake_handle"),
    ("Giant_eagle_shape", 0x6DDE, 0x41F9, "ACTIONS.S Show_eagle_flying_away"),
    ("Damage_star", 0x234E, 0x41F9, "DISPLAY.S Display_damage"),
    ("Magic_stars", 0x23D6, 0x45F9, "DISPLAY.S: lea Magic_stars,a2"),
    ("Magic_stars", 0x3268, 0x43F9, "DISPLAY.S: lea Magic_stars,a1"),
    ("Magic8_stars", 0xC15C, 0x41F9, "MINIMAP.S Minimap_DisUpd"),
    ("Windchain", 0x2642, 0x41F9, "DISPLAY.S Display_special_items"),
    ("Eye_off", 0x2926, 0x41F9, "DISPLAY.S: lea Eye_off,a0"),
    ("Eye_on", 0x292E, 0x41F9, "DISPLAY.S .Seen: lea Eye_on,a0"),
    ("Daynight_icons", 0x2686, 0x41F9, "DISPLAY.S .Draw2"),
    ("Chequered", 0x280F0, 0x49F9, "CONTROLS.S Display_control_icons"),
    ("Chequered", 0x2828A, 0x49F9, "CONTROLS.S Update_control_icons"),
    ("Compass", 0x2716, 0x41F9, "DISPLAY.S .Draw3a"),
    ("Compass", 0xB774, 0x41F9, "MAGIC.S MagicCompass_ModInit"),
    ("Swordshield", 0x3FCE, 0x41F9, "INVENTOR.S: lea Swordshield,a0"),
    ("Swordshield", 0x1E7E8, 0x41F9, "COMBAT_M.S MonKnow_ModInit"),
    ("Death_mask", 0xE6C, 0x41F9, "MAIN.S Show_death"),
    ("Death_mask", 0x1FD2, 0x41F9, "DISPLAY.S Display_portrait"),
    ("Ankh_symbol", 0x16888, 0x41F9, "PLACES.S Display_Ankh"),
    ("Broken", 0x2E2E, 0x41F9, "DISPLAY.S Display_object"),
    ("Broken", 0x2F3A, 0x41F9, "DISPLAY.S Display_body_object"),
    ("Broken", 0x6768, 0x41F9, "DISPLAY.S Create_object_graphics"),
    ("Sky_ranges", 0x11F22, 0x41F9,
     "3D_MAP.S Set_C3_light_level: lea Sky_ranges,a0 / mulu.w #C3_horizon*6"),
    ("C3_palettes", 0x11F5C, 0x41F9,
     "3D_MAP.S Set_C3_light_level: lea C3_palettes,a0 / mulu.w #2*Pal_size"),
    ("Ladefehler_text", 0x26392, 0x43F9,
     "Bibliothek, Ladefehlerschirm: jsr Init_diagnostic_screen / lea ...,a1"),
]

# Gegenprobe der Weltdaten: Lyramion 16x16, Waldmond 6x6, Morag 4x4 Karten
# zu 50x50, erste Karten 1, 300, 513.
WELTEN = (16, 16, 50, 50, 1, 6, 18, 6, 6, 50, 50, 300, 6, 18,
          4, 4, 50, 50, 513, 6, 18)

# Zeichensatz, Hunk 13 (falcon_gfx.py, "Zeichensatz"): Umsetzungstabelle
# und 94 Zeichen zu fuenf Byte.  Kopf wie der Karteneintrag 8, den
# Put_text_line (HULL/WORDS_SUP.S) ueber p_font liest.
FONT_HUNK, FONT_TAB, FONT_BASE = 13, 0x0000, 0x01C0
FONT_CHARS, FONT_BYTES, FONT_ADVANCE, FONT_LINE = 94, 5, 6, 7
# The rune table, for ~RUN1~ (AM2_CPU 0:$23BDE: "tst.b Rune_flag", then
# lea 13:$E0 instead of 13:$0, indexed with the character minus 32).  The
# runes are glyphs $40-$5D of the same font.  Two entries (characters $C0,
# $C1) point to glyph $7B, behind the end of hunk 13; they become "no
# character", and the build checks that there are no others.
RUNE_TAB, RUNE_LEN, RUNE_AUSSERHALB = 0x00E0, 224, (0xA0, 0xA1)


def zeilen_db(daten, breite=16):
    aus = []
    for i in range(0, len(daten), breite):
        aus.append("\tdc.b\t" + ",".join("$%02X" % b for b in daten[i:i + breite]))
    return aus


def zeilen_dw(worte, breite=8):
    aus = []
    for i in range(0, len(worte), breite):
        aus.append("\tdc.w\t" + ",".join("$%04X" % w for w in worte[i:i + breite]))
    return aus


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--amberfiles", default=paths.amberfiles())
    p.add_argument("--out", default="build/am2cpu_daten.i")
    a = p.parse_args()

    hunks = {h["index"]: h["data"] for h in read_hunks(
        open(os.path.join(a.amberfiles, "AM2_CPU"), "rb").read())}

    z = ["; build/am2cpu_daten.i -- erzeugt von tools/am2cpu_auszug.py aus AM2_CPU.",
         "; Nicht von Hand aendern, nicht ins Repository (Spieldaten).",
         "", "\tSECTION\tFast_DATA,data", "\teven"]

    # Gegenprobe: die Hauptpalette muss STATUS_PALETTE sein.
    erwartet = b"".join(bytes([r, (g << 4) | b]) for r, g, b in STATUS_PALETTE)
    if hunks[4][0x5B18:0x5B18 + 64] != erwartet:
        raise SystemExit("am2cpu_auszug: Main_pal in Hunk 4 passt nicht zu STATUS_PALETTE")

    if struct.unpack(">21H", hunks[4][0x75FE:0x75FE + 42]) != WELTEN:
        raise SystemExit("am2cpu_auszug: World_data in Hunk 4 passt nicht")

    # Gegenprobe: sin 0 = 0, sin 90 Grad = 2^14, sin 270 Grad = -2^14.
    sinus = struct.unpack(">1024h", hunks[4][0x65C4:0x65C4 + 2048])
    if (sinus[0], sinus[256], sinus[768]) != (0, 16384, -16384):
        raise SystemExit("am2cpu_auszug: Sinus_table in Hunk 4 passt nicht")
    lage = {name: off for name, _, off, _, _ in STUECKE}
    for name, stelle, befehl, wo, *plus in CODEBELEGE:
        ziel = lage[name] + (plus[0] if plus else 0)
        if struct.unpack(">HI", hunks[0][stelle:stelle + 6]) != (befehl, ziel):
            raise SystemExit("am2cpu_auszug: %s -- %s zeigt nicht auf $%X"
                             % (name, wo, ziel))
    for i, name in enumerate(ZEIGER):
        if name:
            lage[name] = ZEIGER_ANFANG + i * ZEIGER_SATZ
    stelle, namen = MOUSETAB
    ist = struct.unpack(">18I", hunks[4][stelle:stelle + 72])
    if list(ist) != [lage[n] for n in namen]:
        raise SystemExit("am2cpu_auszug: Mousetab_2D/3D passt nicht zu den Zeigern")
    for hunk, stelle, name, wo in VERWEISE:
        if struct.unpack(">I", hunks[hunk][stelle:stelle + 4])[0] != lage[name]:
            raise SystemExit("am2cpu_auszug: %s -- %s zeigt nicht auf $%X"
                             % (name, wo, lage[name]))

    # Kein Stueck darf in ein anderes ragen: die Laengen kommen aus Thalions
    # Aufrufen, die Anfaenge aus AM2_CPU -- beides zusammen muss aufgehen.
    # Ausnahme: das neunte Byte der Ereignisbild-Tabelle, das das Original
    # mitliest, ist das erste der Standbildmasse (Erkenntnis 184).
    # Ebenso Race_heights, das Thalion mit Max_races = 15 in
    # Chared_portraits hinein liest.
    erlaubt = {("Event_pix_palette_table", "Stationary_dimensions"),
               ("Race_heights", "Chared_portraits")}
    reihe = sorted((hunk, off, off + n, name) for name, hunk, off, n, _ in STUECKE)
    for (h1, _, e1, n1), (h2, a2, _, n2) in zip(reihe, reihe[1:]):
        if h1 == h2 and e1 > a2 and (n1, n2) not in erlaubt:
            raise SystemExit("am2cpu_auszug: %s ragt in %s (Hunk %d $%X > $%X)"
                             % (n1, n2, h1, e1, a2))

    for name, hunk, off, n, beleg in STUECKE:
        d = hunks[hunk][off:off + n]
        if len(d) != n:
            raise SystemExit("am2cpu_auszug: %s unvollstaendig" % name)
        z += ["", "; %s -- %s ab $%X, %d Byte" % (name, beleg, off, n), name + ":"]
        z += zeilen_db(d)
        z.append("\teven")

    z += meldungen(hunks)

    # Zeichensatz
    f = hunks[FONT_HUNK]
    ftab = f[FONT_TAB:FONT_TAB + 256]
    fgly = f[FONT_BASE:FONT_BASE + FONT_CHARS * FONT_BYTES]
    for zeichen, nummer in (("A", 0), ("H", 7), ("N", 13), ("O", 14), ("0", 48)):
        if ftab[ord(zeichen) - 32] != nummer:
            raise SystemExit("am2cpu_auszug: Zeichensatz %r zeigt auf %d statt %d"
                             % (zeichen, ftab[ord(zeichen) - 32], nummer))
    z += ["", "; Zeichensatz -- Hunk 13: Kopf (Zeichen, Byte je Zeichen, Vorschub,",
          "; Zeile), Umsetzungstabelle, Muster.  Liest Put_text_line ueber p_font.",
          "Zeichensatz:"]
    z += zeilen_dw([FONT_CHARS, FONT_BYTES, FONT_ADVANCE, FONT_LINE])
    z += zeilen_db(ftab + fgly)
    z.append("\teven")
    rtab = bytearray(f[RUNE_TAB:RUNE_TAB + RUNE_LEN])
    if rtab[ord("A") - 32] != 0x40 or rtab[ord("0") - 32] != ftab[ord("0") - 32]:
        raise SystemExit("am2cpu_auszug: Runentabelle bei 13:$%X passt nicht" % RUNE_TAB)
    for i, v in enumerate(rtab):
        if v != 0xFF and v >= FONT_CHARS:
            if i not in RUNE_AUSSERHALB:
                raise SystemExit("am2cpu_auszug: Runentabelle %d zeigt auf %d, "
                                 "hinter den Zeichensatz" % (i, v))
            rtab[i] = 0xFF
    z += ["", "; Runentabelle -- Hunk 13 ab $%X, %d Byte, wie die Umsetzungstabelle"
          % (RUNE_TAB, RUNE_LEN),
          "; des Zeichensatzes; Put_text_line nimmt sie bei Rune_flag (~RUN1~).",
          "Runentabelle:"]
    z += zeilen_db(bytes(rtab))
    z.append("\teven")

    # Mauszeiger: Thalions Saetze, die Bibliothek weitet beim Setzen auf
    # (Set_mouse_ptr, HULL/AREAS.S).
    z += ["", "; Mauszeiger -- Hunk 4 ab $%X, %d Saetze zu %d Byte: Hotspot x, y,"
          % (ZEIGER_ANFANG, len(ZEIGER), ZEIGER_SATZ),
          "; dann 16 Zeilen zu drei Ebenenworten."]
    for i, name in enumerate(ZEIGER):
        off = ZEIGER_ANFANG + i * ZEIGER_SATZ
        z.append((name + ":") if name else "; $%X: nur die Bibliothek" % off)
        z += zeilen_db(hunks[ZEIGER_HUNK][off:off + ZEIGER_SATZ])
    z += ["\teven", ""]

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as fh:
        fh.write("\n".join(z))
    print("  AM2_CPU-Daten: %d Stuecke, Zeichensatz, %d Mauszeiger -> %s"
          % (len(STUECKE), len(ZEIGER), a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

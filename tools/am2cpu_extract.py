#!/usr/bin/env python3
"""am2cpu_extract.py -- the data of the unreleased library, at build time.

DEVIATION (goals 1 and 2), docs/17-deviations.md D2: library data taken
from AM2_CPU at build time.

Thalion's code addresses data that is in no released source and no game file,
only in the Amiga program AM2_CPU: the main palette, window tiles, status bar,
button frames, font ...  On the Amiga they lie there at fixed addresses, and
Thalion's code reaches them with ``lea.l Name,a0``.

**AM2_CPU is never read at run time** (user, 2026-09-27): it is an Amiga
executable, not a game file.  This tool takes the pieces out at build time and
writes them as an assembler file to build/am2cpu_daten.i, which engine.s
includes.  So the names stand at fixed addresses as in the original, and none
of it is in the repository.

The first places are the ones the old converter falcon_gfx.py (now in
tools/archiv/) had used and proven (findings 118, 64, 184).  Newer ones are
proven through Thalion's assembled code (CODE_PROOFS, REFERENCES): at build
time the tool checks that the place there points at exactly this piece.
Since 2026-09-28 nothing comes from memory dumps any more, not the mouse
pointer and Ouch either.

Usage:  am2cpu_extract.py [--amberfiles DIR] [--out build/am2cpu_daten.i]
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

# (name, hunk, offset, length, proof)
PIECES = [
    # The interface palette, 32 Amiga colour words.  Word for word
    # STATUS_PALETTE above, proven at the chest memory dump (finding 64).
    # File offset 0x43688.
    ("Main_pal", 4, 0x5B18, 64, "hunk 4, main palette"),
    # Eight window tiles 16x16, three planes (Put_window_part, finding 118).
    ("Window_icons", 3, 0x00C0, 8 * 96, "hunk 3, window frame"),
    # Status bar (Display_status_block): left, middle, right 16x36, the bar
    # 32x1, all three planes, one right after the other.
    ("Status_L", 3, 0x19D8, 216, "hunk 3, status bar left"),
    ("Status_M", 3, 0x19D8 + 216, 216, "hunk 3, status bar middle"),
    ("Status_R", 3, 0x19D8 + 432, 216, "hunk 3, status bar right"),
    ("Status_TB", 3, 0x19D8 + 648, 12, "hunk 3, bar above/below the portrait"),
    # The empty portrait place, 32x34, three planes.
    ("Empty_portrait", 3, 0x2DA8, 4 * 3 * 34, "hunk 3, empty place"),
    # Button frame 32x17, three planes, pressed right behind it.
    ("Button_up", 3, 0x2860, 204, "hunk 3, button frame"),
    ("Button_down", 3, 0x2860 + 204, 204, "hunk 3, button frame pressed"),
    # Which palette belongs to which event picture (ShowPicTxt_ModInit).
    # Eight bytes; the original also reads the ninth (0) for the ninth picture
    # (finding 184).
    ("Event_pix_palette_table", 4, 0x770A, 9, "hunk 4, event picture palettes"),
    # The three worlds (Init_world, MAP/MAP.S), seven words each: world and
    # map size, first map number, dawn and dusk.  The pattern
    # (.., .., 50, 50, 1, ..) occurs exactly once in AM2_CPU.
    ("World_data", 4, 0x75FE, 3 * 14, "hunk 4, world data"),
    # Sine for the 3D view: 1024 words (slang), sin * 2^14; Thalion reads the
    # cosine at +256 and masks with slang*2-1 to the byte offset.  Found at
    # Get_draw_size (lea Sinus_table,a0 is the first instruction there,
    # AM2_CPU 0:$10CCE); the next table starts exactly 2048 bytes on (docs/02
    # A5, finding 195).
    ("Sinus_table", 4, 0x65C4, 2048, "hunk 4, sine table"),
    # Height per race in cm, one word per race (Max_races = 15), read by
    # Calculate_camera_height (3D_MAP.S; AM2_CPU 0:$12094).
    ("Race_heights", 4, 0x76A8, 2 * 15, "hunk 4, race heights"),
    # The portrait numbers of the character editor (CHARACTE.S Chared_ModInit:
    # lea Chared_portraits,a1 / moveq #Portraits_per_sex*2-1,d7), four male,
    # then four female: 2, 25, 7, 23, 31, 38, 44, 51.  **Race_heights has only
    # nine words in AM2_CPU**; for races 9-14 Thalion reads into this table,
    # so the two overlap (like finding 184).
    ("Chared_portraits", 4, 0x76BA, 2 * 8, "hunk 4, portraits of the character editor"),
    # Spell data (GAME_OFF.S: Spell_area_bits ... Spell_data_size = 5), per
    # spell class Max_spells = 30 records, seven classes.
    ("Spell_data", 4, 0x61AA, 7 * 30 * 5, "hunk 4, spell data"),
    # Six symbols of the running spells 16x16, three planes, distance 96
    # (Display_spells).  Right behind Status_TB.
    ("Spell_icons", 3, 0x1C6C, 6 * 96, "hunk 3, spell symbols"),
    # Eleven "poof" pictures 16x16, three planes (Dissolve_HDOB in EVENTS.S:
    # width 1, height 16, depth 3; Animate_HDOB with d0 = 11).  Right behind
    # Empty_portrait.
    ("Dissolve", 3, 0x2F40, 11 * 96, "hunk 3, dissolve"),
    # Speech bubble "OUCH!" 32x23, three planes (Display_2D_map: Put_masked_block
    # with d4=24, d5=3, d6=2, d7=23).
    ("Ouch", 3, 0x166C, 4 * 3 * 23, "hunk 3, speech bubble"),
    # Small 2D tables, right before World_data ($75FE).  One byte per travel
    # mode (GAME_OFF.S: On_foot ... Sandskimmer, Max_travelmodes = 11).
    ("Level_start_EPs", 4, 0x75C6, 2 * 11, "hunk 4, start EP per class (Max_classes)"),
    ("World_move_delay", 4, 0x75DC, 11, "hunk 4, step pause per travel mode"),
    ("Travel_speed", 4, 0x75E7, 11, "hunk 4, time lapse per travel mode"),
    ("Travel_music", 4, 0x75F2, 11, "hunk 4, music per travel mode"),
    # Width, height per stationary picture (Display_2D_transport).  Five pairs;
    # their sum in five planes is exactly the unpacked length of Stationary
    # (3480 bytes).
    ("Stationary_dimensions", 4, 0x7712, 5 * 4, "hunk 4, stationary picture sizes"),
    # One item index per condition (PLACES.S, 16 conditions).
    ("Condition_object_index_table", 4, 0x7726, 16, "hunk 4, condition -> item"),
    # Small write buffers of the item view (INVENTOR.S ItemView2): " 01"
    # (SDecL_convert writes into it) and "(01)" (DecR_convert from +1, then
    # ")" at +3).
    ("Attrskill_nr", 4, 0x070E, 4, "hunk 4, bonus number"),
    ("Charges_txt", 4, 0x0712, 5, "hunk 4, charges"),
    # Combat (COMBAT.S Combat_ModInit): four bytes per combat background,
    # picture number and three palettes (day, dusk, night), 16 entries.  The
    # 3D table follows right behind, then Race_heights.
    ("Combat_bg_2D_table", 4, 0x7628, 16 * 4, "hunk 4, combat backgrounds 2D"),
    ("Combat_bg_3D_table", 4, 0x7668, 16 * 4, "hunk 4, combat backgrounds 3D"),
    # Palette of the tactic field below the combat picture (MODULES.S
    # Combat_RL), 32 Amiga colour words; Set_layout_colours copies the last six.
    ("Tactic_pal", 4, 0x5B98, 64, "hunk 4, tactic palette"),
    # Damage of the destruction spells (COMBAT_M.S Do_destruction_damage): per
    # spell from number 15 minimum and maximum as words.  Ends right before
    # Event_pix_palette_table ($770A).
    ("Destruction_table", 4, 0x76CA, 16 * 4, "hunk 4, destruction damage"),
    # Red cross over a cell of the tactic field (TACTIC.S:
    # Put_masked_silhouette with d5 = 1, d6 = 1, d7 = Tactic_cell_height = 13).
    ("Red_cross", 3, 0x35A4, 13 * 2, "hunk 3, red cross"),
    # The mouse area "whole picture" (X1, X2, Y1, Y2) that Init_module puts up
    # when a module brings none of its own: 0,319,0,199.
    ("Default_MA", 4, 0x491A, 4 * 2, "hunk 4, mouse area full picture"),
    # **2D graphics** (finding 256).  Every place found through Thalion's
    # "lea Name" (CODE_PROOFS below); the length is the size Thalion's call
    # passes (width in words x height x planes x 2), and each fills exactly
    # the gap to the next piece in hunk 3.
    ("Cross_hatch", 3, 0x00A0, 2 * 16 * 1, "hunk 3, hatching 16x16, 1 plane (Options_ModInit)"),
    ("Status_icons", 3, 0x03C0, 23 * 160, "hunk 3, 23 condition symbols 16x16, 5 planes (Icon_size)"),
    ("Giant_eagle_shape", 3, 0x1220, 4 * 29 * 5, "hunk 3, eagle 32x29, 5 planes (Giant_eagle_HDOB)"),
    ("Damage_star", 3, 0x1464, 4 * 26 * 5, "hunk 3, damage star 32x26, 5 planes"),
    ("Magic_stars", 3, 0x1780, 4 * 9 * 5 * 2, "hunk 3, four sparks 16x9, 5 planes"),
    ("Magic8_stars", 3, 0x18E8, 4 * 10 * 3 * 2, "hunk 3, four stars 16x10, 3 planes (minimap)"),
    ("Windchain", 3, 0x1EAC, 4 * 15 * 3, "hunk 3, wind chain 32x15, 3 planes"),
    ("Eye_off", 3, 0x1F60, 4 * 32 * 3, "hunk 3, eye closed 32x32, 3 planes"),
    ("Eye_on", 3, 0x20E0, 4 * 32 * 3, "hunk 3, eye open 32x32, 3 planes"),
    ("Daynight_icons", 3, 0x2260, 4 * 32 * 12, "hunk 3, four times of day 32x32, 3 planes"),
    ("Chequered", 3, 0x29F8, 4 * 11 * 1, "hunk 3, hatching of disabled buttons 32x11, 1 plane"),
    ("Compass", 3, 0x2A24, 4 * 32 * 3, "hunk 3, compass 32x32, 3 planes"),
    ("Swordshield", 3, 0x2BA4, 2 * 9 * 3 * 2, "hunk 3, sword and shield 16x9, 3 planes"),
    ("Death_mask", 3, 0x2C10, 4 * 34 * 3, "hunk 3, death mask 32x34, 3 planes"),
    ("Ankh_symbol", 3, 0x3360, 4 * 29 * 5, "hunk 3, ankh 32x29, 5 planes (healer)"),
    ("Broken", 3, 0x35BE, 2 * 16 * 1, "hunk 3, overlay broken 16x16, 1 plane"),
    # The colours of the automap half, right behind Main_pal (REFERENCES).
    ("Automap_pal", 4, 0x5B58, 64, "hunk 4, automap palette"),
    # 3D cities (3D_MAP.S Set_C3_light_level): per world three sky gradients of
    # C3_horizon = 72 colour words (mulu.w #C3_horizon*6), right behind them
    # per world two sets of Pal_size = 32 bytes (mulu.w #2*Pal_size, lea
    # Pal_size(a0); Dim_colours with d7 = Pal_size/2).  Three worlds; behind
    # Tactic_pal, ends before Spell_data ($61AA).
    ("Sky_ranges", 4, 0x5BD8, 3 * 72 * 6, "hunk 4, sky gradients of 3D cities"),
    ("C3_palettes", 4, 0x60E8, 3 * 2 * 32, "hunk 4, palettes of 3D cities"),
    # The library's load error screen (0:$2637C, finding 268): the headline and
    # the names of the 45 file kinds (Memory block ... Object graphics), 22
    # bytes each with end zero.  The original takes them through the pointer
    # table 4:$4934 (0:$263AA "lea ...,a2 / lsl.w #2,d0"), whose 45 pointers
    # point at exactly these records in steps of 22; we compute number * 22.
    ("Datei_arten", 4, 0x49E8, 45 * 22, "hunk 4, names of the file kinds"),
    ("Ladefehler_text", 4, 0x4DC6, 26, "hunk 4, FILE COULDN'T BE LOADED :"),
]

# The mouse pointers, hunk 4 $5028-$5B17: 28 records of 100 bytes, each a
# hotspot (x, y as words) and a picture 16x16 in three planes, line by line
# (three words per line).  Colour = 24 + picture value, 0 is transparent.  The
# 13 pictures from the earlier Amiga memory dumps match point for point
# (2026-09-28).  Names as in Thalion's source; None = only the library uses
# the record (file access, memory).
POINTER_HUNK, POINTER_START, POINTER_RECORD = 4, 0x5028, 100
POINTERS = [
    "Default_Mptr",
    "Up_2D_Mptr", "Down_2D_Mptr", "Left_2D_Mptr", "Right_2D_Mptr",
    "Upleft_2D_Mptr", "Upright_2D_Mptr", "Downleft_2D_Mptr", "Downright_2D_Mptr",
    "Forward_3D_Mptr", "Back_3D_Mptr", "Left_3D_Mptr", "Right_3D_Mptr",
    "Turnleft_3D_Mptr", "Turnright_3D_Mptr", "Turn180_left_Mptr", "Turn180_right_Mptr",
    "Zzz_Mptr", "Eye_Mptr", "Mouth_Mptr", None, "Gold_Mptr", "Food_Mptr",
    "Pick_Mptr", "Hand_Mptr", "EyeMouth_Mptr", "Click_Mptr", None,
]

# Mousetab_2D and Mousetab_3D (MAP/MAP.S), 18 longwords in hunk 4.
MOUSETAB = (0x3C44, ["Upleft_2D_Mptr", "Up_2D_Mptr", "Upright_2D_Mptr",
                     "Left_2D_Mptr", "Zzz_Mptr", "Right_2D_Mptr",
                     "Downleft_2D_Mptr", "Down_2D_Mptr", "Downright_2D_Mptr",
                     "Turnleft_3D_Mptr", "Forward_3D_Mptr", "Turnright_3D_Mptr",
                     "Left_3D_Mptr", "Zzz_Mptr", "Right_3D_Mptr",
                     "Turn180_left_Mptr", "Back_3D_Mptr", "Turn180_right_Mptr"])

# More places where Thalion's assembled code points at a pointer or at Ouch:
# (hunk, offset of the longword, name, place in the source).  Before relocation
# the offset in the target hunk stands there.
REFERENCES = [
    (0, 0xD624, "Default_Mptr", "MAP.S Reset_map_mouse: lea Default_Mptr,a0"),
    (4, 0x1B08, "Click_Mptr", "MODULES.S Wait_4_user_Mod"),
    (4, 0x258C, "Pick_Mptr", "MODULES.S Move_item_Mod"),
    (4, 0x2A0E, "Pick_Mptr", "MODULES.S Move_LAY3_item_Mod"),
    (4, 0x26EA, "EyeMouth_Mptr", "MODULES.S, module descriptor with Made_area"),
    (0, 0x6F22, "EyeMouth_Mptr", "ACTIONS.S: lea EyeMouth_Mptr,a0"),
    (0, 0x6F30, "Mouth_Mptr", "ACTIONS.S .Mouth: lea Mouth_Mptr,a0"),
    (4, 0x2748, "Eye_Mptr", "MODULES.S eye module"),
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
    # MODULES.S Automap_Mod, .RL: "R_palette Middle_Y+1,Automap_pal".  The
    # record carries the same buttons and the same area 216,303,45,188 as
    # Thalion's source.
    (4, 0x346C, "Automap_pal", "MODULES.S Automap_Mod .RL"),
]

# **Messages** (stage 1b).  In 1.20 the texts are in Text.amb, part 1 (46 single
# texts, tools/text_labels.py).  At the start the library enters a pointer to
# each into a fixed place; a table in hunk 6 from $00 says where: 46 longwords,
# text n -> place.  Places 3-45 lie in hunk 4, and nearly all in **text lists**:
# sequences of pointers, end null, whose gaps Thalion's code fills
# (Print_member_text puts the name at 0, "move.l #Number,8(a0)" ...).  The lists
# stand in the file as zeros; their limits follow from their starts.
#
# We lay the lists out at build time, with "dc.l Textamb_n" -- the labels that
# text_labels.py sets on the texts in Textdaten.  Lade_texte reads the texts
# themselves at run time (goal 2).
MESSAGE_TABLE = (6, 0x00, 46)
# (name, start in hunk 4, places in hunk 0 where a lea/move.l points at it,
# Thalion's call site).  Ascending; each list ends before the next one, the
# last one before MESSAGE_END.
MESSAGE_LISTS = [
    ("Known_error_text", 0x7D0E, [0x29212], "HULL/CONTROLS.S Disk_error_handler"),
    ("Disk_request_text", 0x7D26, [0x292B2], "HULL/CONTROLS.S Disk_requester .No"),
    ("Save_disk_request_text", 0x7D36, [0x292AA], "HULL/CONTROLS.S Disk_requester"),
    None,                                   # $7D3E: AM2_CPU's substitute text
    ("No_recup_text", 0x7F94, [0x7AD4], "ACTIONS.S: lea No_recup_text,a0"),
    ("Recup1_text", 0x7FA0, [0x7E1E], "ACTIONS.S: move.l #Number,8(a0)"),
    ("Recup2_text", 0x7FB4, [0x7E46], "ACTIONS.S: move.l #Number,8(a0)"),
    ("Aging_text", 0x7FD0, [0x7A40], "ACTIONS.S: Print_member_text"),
    ("Ageddeath_text", 0x7FDC, [0x7A68, 0x125C8], "ACTIONS.S, TIME.S"),
    ("BuySell_req_text", 0x7FE8, [0x17A6A], "PLACES.S BuySell_req: prompt at 0"),
    ("Food_price_text", 0x7FF8, [0x176FC], "PLACES.S Print_food_price: Number at 4"),
    ("Make_level_text", 0x8008, [0x174C], "MAIN.S Make_levels: lea ...,a3"),
    ("Attack_text", 0x801C, [0x1A282], "COMBAT.S Print_attacking .Normal: clr.l 24(a1)"),
    ("Attack2_text", 0x8038, [0x1A268], "COMBAT.S Print_attacking: clr.l 16(a1)"),
    ("Broken_text", 0x804C, [0x4EBA, 0x1A384], "INVENTOR.S, COMBAT.S: lea ...,a2"),
    ("Hit_text", 0x8060, [0x1A2C4], "COMBAT.S Print_hitting: Number at 8"),
    ("EP_divide_text", 0x8074, [0x1B97A, 0x1BABE], "COMBAT/APRES.S: Number at 4"),
    ("Magic_action_text", 0x8084, [0x1DB1E], "COMBAT_M.S Print_magic_action"),
    ("Magic_object_text", 0x8098, [0x1DC0A], "COMBAT_M.S Print_magic_obj_action"),
    ("Wrong_answer_text", 0x80B4, [0x147E6, 0x147F4], "EVENTS.S riddlemouth: lea ...,a1"),
]
MESSAGE_END = 0x80C0
# Single texts that Thalion's released source addresses as texts
# ("move.l #Divide_start_text,(a2)+"); 1.20 reads the place there
# ("move.l $7F88,(a2)+").  With us they are labels in Textdaten, set by
# text_labels.py: (name, text, places in hunk 0, call site).
MESSAGE_SINGLES = [
    ("Text_error_text", 9, [0x28DBE], "HULL/CONTROLS.S Find_large_text"),
    ("Out_of_memory_text", 11, [0x18BFE], "DIAGNOST.S Out_of_memory"),
    ("Divide_start_text", 12, [0x1A90], "MAIN.S Check_for_vital_items"),
    ("Divide_inter_text", 13, [0x1AC6], "MAIN.S Check_for_vital_items"),
    ("Divide_end_text", 14, [0x1ACE], "MAIN.S Check_for_vital_items"),
    ("That_text", 45, [0x147EC], "EVENTS.S riddlemouth: move.l #That_text,(a1)"),
]
# Magic_txt ("MAGIE") is set by the start routine in hunk 8 ($168): it skips
# seven texts in Spell_class_names and puts the eighth at $8100.  text_labels.py
# sets the label; here only the routine is checked.
MAGIC_TXT_CODE = (8, 0x168, bytes.fromhex(
    "2479000080d470004a1a66fc52000c00000663f423ca00008100"))
MAGIC_TXT_PLACE = 0x5AC8        # INVENTOR.S ItemView2: "lea Magic_txt,a0"
VIRTUAL = None                  # set in main(): version of a Thalion 1.0x AM2_CPU


def messages(hunks):
    """The text lists as assembler lines; stops if something does not fit."""
    h, o, n = MESSAGE_TABLE
    place = struct.unpack(">%dI" % n, hunks[h][o:o + 4 * n])
    text_of = {p: i for i, p in enumerate(place) if i >= 3}
    if len(text_of) != n - 3 or not all(0x7D00 <= p <= MESSAGE_END for p in text_of):
        raise SystemExit("am2cpu_extract: message table in hunk 6 does not fit")
    for hn, st, expected in [(0, s, a) for name, a, sts, _ in
                             [m for m in MESSAGE_LISTS if m] for s in sts] + \
            [(0, s, place[t]) for _, t, sts, _ in MESSAGE_SINGLES for s in sts] + \
            [(0, MAGIC_TXT_PLACE, 0x8100)]:
        if struct.unpack(">I", hunks[hn][st:st + 4])[0] != expected:
            raise SystemExit("am2cpu_extract: message -- 0:$%X does not point at $%X"
                             % (st, expected))
    h, o, code = MAGIC_TXT_CODE
    # Hunk 8 is 1.2x's own start code; Thalion's 1.0x has none (am2cpu_old.py).
    if not VIRTUAL and hunks[h][o:o + len(code)] != code:
        raise SystemExit("am2cpu_extract: Magic_txt -- start routine in hunk 8 does not fit")
    z = ["", "; Messages -- text lists from hunk 4 ($%X-$%X), places after the"
         % (MESSAGE_LISTS[0][1], MESSAGE_END),
         "; table in hunk 6; Textamb_n are the single texts in Textdaten."]
    singles = {place[t] for _, t, _, _ in MESSAGE_SINGLES}
    for k, m in enumerate(MESSAGE_LISTS):
        if not m:
            continue
        name, start, _, where = m
        end = MESSAGE_END
        for f in MESSAGE_LISTS[k + 1:]:
            end = f[1] if f else 0x7D3E
            break
        entries = []
        for p in range(start, end, 4):
            if p in singles:
                raise SystemExit("am2cpu_extract: single text $%X in list %s" % (p, name))
            entries.append("Textamb_%d" % text_of[p] if p in text_of else "0")
        if entries[-1] != "0":
            raise SystemExit("am2cpu_extract: list %s does not end with null" % name)
        z += ["%s:			; $%X, %s" % (name, start, where),
              "	dc.l	" + ",".join(entries)]
    return z


# Where Thalion's assembled code points at a piece: (name, offset of the lea in
# hunk 0, instruction word, call site[, offset in the piece]).  Before
# relocation the address in the instruction is the offset in the target hunk.
# Found with am2cpu_read.py through the instruction sequence from Thalion's
# source (2026-09-28).
CODE_PROOFS = [
    ("Attrskill_nr", 0x5A16, 0x41F9,
     "INVENTOR.S ItemView2_DisInit: lea Attrskill_nr,a0 before SDecL_convert"),
    ("Charges_txt", 0x5B54, 0x41F9,
     "INVENTOR.S ItemView2_DisInit: lea Charges_txt,a0 before Put_text_line"),
    ("Spell_data", 0x440A, 0x47F9,
     "INVENTOR.S Use_item: lea Spell_data,a3 before mulu.w #Max_spells"),
    ("Spell_icons", 0x2526, 0x47F9,
     "DISPLAY.S Display_spells: lea Spell_icons,a3 / move.w #208,d0"),
    ("Dissolve", 0x69B6, 0x41F9,
     "moveq #11,d0 / moveq #3,d1 / lea Dissolve,a0 (five places)"),
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
    # 2D graphics: every place where Thalion's source says "lea Name".  Found by
    # searching the instructions around the lea of our build in hunk 0
    # (finding 256).
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
     "library, load error screen: jsr Init_diagnostic_screen / lea ...,a1"),
]

# Check of the world data: Lyramion 16x16, Forest Moon 6x6, Morag 4x4 maps of
# 50x50, first maps 1, 300, 513.
WORLDS = (16, 16, 50, 50, 1, 6, 18, 6, 6, 50, 50, 300, 6, 18,
          4, 4, 50, 50, 513, 6, 18)

# Font, hunk 13 (falcon_gfx.py, "Zeichensatz"): translation table and 94
# characters of five bytes.  Header like map entry 8, which Put_text_line
# (HULL/WORDS_SUP.S) reads through p_font.
FONT_HUNK, FONT_TAB, FONT_BASE = 13, 0x0000, 0x01C0
FONT_CHARS, FONT_BYTES, FONT_ADVANCE, FONT_LINE = 94, 5, 6, 7
# The rune table, for ~RUN1~ (AM2_CPU 0:$23BDE: "tst.b Rune_flag", then
# lea 13:$E0 instead of 13:$0, indexed with the character minus 32).  The
# runes are glyphs $40-$5D of the same font.  Two entries (characters $C0,
# $C1) point to glyph $7B, behind the end of hunk 13; they become "no
# character", and the build checks that there are no others.
RUNE_TAB, RUNE_LEN, RUNE_OUTSIDE = 0x00E0, 224, (0xA0, 0xA1)


def lines_db(data, width=16):
    out = []
    for i in range(0, len(data), width):
        out.append("\tdc.b\t" + ",".join("$%02X" % b for b in data[i:i + width]))
    return out


def lines_dw(words, width=8):
    out = []
    for i in range(0, len(words), width):
        out.append("\tdc.w\t" + ",".join("$%04X" % w for w in words[i:i + width]))
    return out


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--amberfiles", default=paths.amberfiles())
    p.add_argument("--out", default="build/am2cpu_daten.i")
    a = p.parse_args()

    # Thalion's 1.0x is read as a virtual 1.21 (am2cpu_old.py); then the
    # 1.20 places in hunk 0 are moved to this AM2_CPU (am2cpu_places.py).
    import am2cpu_old, am2cpu_places
    cpu_hunks = am2cpu_old.read_am2cpu(os.path.join(a.amberfiles, "AM2_CPU"),
                            lambda t: print("    " + t))
    hunks = dict(enumerate(h["data"] for h in cpu_hunks))
    global VIRTUAL
    VIRTUAL = cpu_hunks[0].get("virtual")
    for line in am2cpu_places.adapt_extract(sys.modules[__name__], cpu_hunks):
        print("    places: " + line)

    z = ["; build/am2cpu_daten.i -- written by tools/am2cpu_extract.py from AM2_CPU.",
         "; Do not edit, not for the repository (game data).",
         "", "\tSECTION\tFast_DATA,data", "\teven"]

    # Check: the main palette must be STATUS_PALETTE.
    expected = b"".join(bytes([r, (g << 4) | b]) for r, g, b in STATUS_PALETTE)
    if hunks[4][0x5B18:0x5B18 + 64] != expected:
        raise SystemExit("am2cpu_extract: Main_pal in hunk 4 does not fit STATUS_PALETTE")

    if struct.unpack(">21H", hunks[4][0x75FE:0x75FE + 42]) != WORLDS:
        raise SystemExit("am2cpu_extract: World_data in hunk 4 does not fit")

    # Check: sin 0 = 0, sin 90 degrees = 2^14, sin 270 degrees = -2^14.
    sine = struct.unpack(">1024h", hunks[4][0x65C4:0x65C4 + 2048])
    if (sine[0], sine[256], sine[768]) != (0, 16384, -16384):
        raise SystemExit("am2cpu_extract: Sinus_table in hunk 4 does not fit")
    places = {name: off for name, _, off, _, _ in PIECES}
    for name, st, instr, where, *plus in CODE_PROOFS:
        target = places[name] + (plus[0] if plus else 0)
        if struct.unpack(">HI", hunks[0][st:st + 6]) != (instr, target):
            raise SystemExit("am2cpu_extract: %s -- %s does not point at $%X"
                             % (name, where, target))
    for i, name in enumerate(POINTERS):
        if name:
            places[name] = POINTER_START + i * POINTER_RECORD
    st, names = MOUSETAB
    found = struct.unpack(">18I", hunks[4][st:st + 72])
    if list(found) != [places[n] for n in names]:
        raise SystemExit("am2cpu_extract: Mousetab_2D/3D does not fit the pointers")
    for hunk, st, name, where in REFERENCES:
        if struct.unpack(">I", hunks[hunk][st:st + 4])[0] != places[name]:
            raise SystemExit("am2cpu_extract: %s -- %s does not point at $%X"
                             % (name, where, places[name]))

    # No piece may reach into another: the lengths come from Thalion's calls,
    # the starts from AM2_CPU -- both together must work out.  Exception: the
    # ninth byte of the event picture table, which the original also reads, is
    # the first of the stationary picture sizes (finding 184).  Likewise
    # Race_heights, which Thalion reads into Chared_portraits with Max_races = 15.
    allowed = {("Event_pix_palette_table", "Stationary_dimensions"),
               ("Race_heights", "Chared_portraits")}
    row = sorted((hunk, off, off + n, name) for name, hunk, off, n, _ in PIECES)
    for (h1, _, e1, n1), (h2, a2, _, n2) in zip(row, row[1:]):
        if h1 == h2 and e1 > a2 and (n1, n2) not in allowed:
            raise SystemExit("am2cpu_extract: %s reaches into %s (hunk %d $%X > $%X)"
                             % (n1, n2, h1, e1, a2))

    for name, hunk, off, n, proof in PIECES:
        d = hunks[hunk][off:off + n]
        if len(d) != n:
            raise SystemExit("am2cpu_extract: %s incomplete" % name)
        z += ["", "; %s -- %s from $%X, %d bytes" % (name, proof, off, n), name + ":"]
        z += lines_db(d)
        z.append("\teven")

    z += messages(hunks)

    # Font
    f = hunks[FONT_HUNK]
    ftab = f[FONT_TAB:FONT_TAB + 256]
    fgly = f[FONT_BASE:FONT_BASE + FONT_CHARS * FONT_BYTES]
    for char, number in (("A", 0), ("H", 7), ("N", 13), ("O", 14), ("0", 48)):
        if ftab[ord(char) - 32] != number:
            raise SystemExit("am2cpu_extract: font %r points at %d instead of %d"
                             % (char, ftab[ord(char) - 32], number))
    z += ["", "; Font -- hunk 13: header (characters, bytes per character, advance,",
          "; line), translation table, patterns.  Put_text_line reads it through p_font.",
          "Zeichensatz:"]
    z += lines_dw([FONT_CHARS, FONT_BYTES, FONT_ADVANCE, FONT_LINE])
    z += lines_db(ftab + fgly)
    z.append("\teven")
    rtab = bytearray(f[RUNE_TAB:RUNE_TAB + RUNE_LEN])
    if rtab[ord("A") - 32] != 0x40 or rtab[ord("0") - 32] != ftab[ord("0") - 32]:
        raise SystemExit("am2cpu_extract: rune table at 13:$%X does not fit" % RUNE_TAB)
    for i, v in enumerate(rtab):
        if v != 0xFF and v >= FONT_CHARS:
            if i not in RUNE_OUTSIDE:
                raise SystemExit("am2cpu_extract: rune table %d points at %d, "
                                 "behind the font" % (i, v))
            rtab[i] = 0xFF
    z += ["", "; Rune table -- hunk 13 from $%X, %d bytes, like the font's translation"
          % (RUNE_TAB, RUNE_LEN),
          "; table; Put_text_line takes it with Rune_flag (~RUN1~).",
          "Runentabelle:"]
    z += lines_db(bytes(rtab))
    z.append("\teven")

    # Mouse pointers: Thalion's records, the library widens them when setting
    # them (Set_mouse_ptr, HULL/AREAS.S).
    z += ["", "; Mouse pointers -- hunk 4 from $%X, %d records of %d bytes: hotspot x, y,"
          % (POINTER_START, len(POINTERS), POINTER_RECORD),
          "; then 16 lines of three plane words."]
    for i, name in enumerate(POINTERS):
        off = POINTER_START + i * POINTER_RECORD
        z.append((name + ":") if name else "; $%X: library only" % off)
        z += lines_db(hunks[POINTER_HUNK][off:off + POINTER_RECORD])
    z += ["\teven", ""]

    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as fh:
        fh.write("\n".join(z))
    print("  AM2_CPU data: %d pieces, font, %d mouse pointers -> %s"
          % (len(PIECES), len(POINTERS), a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

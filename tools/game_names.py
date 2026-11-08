#!/usr/bin/env python3
"""game_names.py -- the one table: Amiga name of a game file -> 8.3 name.

Many Amberfiles have longer names than a FAT file system holds.  Readers:
deliver_data in tools/build_common.sh, tools/install.py and
tools/set_save_game.py.  The other side is the name table in
engine/src/HULL/FILES_SUP.S (dn_tabelle) and SPIELSTAND.S (sp_tabelle):
whoever changes something here must change it there too.

Usage: game_names.py files|saves    one "Amiga 8.3" pair per line
"""
import sys

# in AMBFILES.  Saves unchanged as in the original (user, 2026-09-30): last
# save game 0, so Thalion's Init_program puts up the character editor for a
# new game (Chared_Mod, finding 261).
GAME_FILES = (
    ("Layouts.amb", "LAYOUTS.AMB"),
    ("Dict.amb", "DICT.AMB"),
    ("Automap_graphics", "AUTOMAPG.DAT"),
    ("Object_icons", "OBJICONS.DAT"),
    ("Button_graphics", "BUTTONGF.DAT"),
    ("Text.amb", "TEXT.AMB"),
    ("Objects.amb", "OBJECTS.AMB"),
    ("1Map_data.amb", "MAPDATA1.AMB"),
    ("2Map_data.amb", "MAPDATA2.AMB"),
    ("3Map_data.amb", "MAPDATA3.AMB"),
    ("1Map_texts.amb", "MAPTEXT1.AMB"),
    ("2Map_texts.amb", "MAPTEXT2.AMB"),
    ("3Map_texts.amb", "MAPTEXT3.AMB"),
    ("Icon_data.amb", "ICONDATA.AMB"),
    ("Pics_80x80.amb", "PICS80.AMB"),
    ("Event_pix.amb", "EVENTPIX.AMB"),
    ("Palettes.amb", "PALETTES.AMB"),
    ("Music.amb", "MUSIC.AMB"),
    ("NPC_char.amb", "NPCCHAR.AMB"),
    ("Monster_char.amb", "MONSTCHR.AMB"),
    ("Portraits.amb", "PORTRAIT.AMB"),
    ("1Icon_gfx.amb", "ICONGFX1.AMB"),
    ("2Icon_gfx.amb", "ICONGFX2.AMB"),
    ("3Icon_gfx.amb", "ICONGFX3.AMB"),
    ("Travel_gfx.amb", "TRAVELGF.AMB"),
    ("NPC_gfx.amb", "NPCGFX.AMB"),
    ("Object_texts.amb", "OBJTEXTS.AMB"),
    ("Party_texts.amb", "PARTYTXT.AMB"),
    ("NPC_texts.amb", "NPCTEXT.AMB"),
    ("Place_data", "PLACEDAT.DAT"),
    ("Stationary", "STATIONR.DAT"),
    ("Party_gfx.amb", "PARTYGFX.AMB"),
    ("2Lab_data.amb", "LABDATA2.AMB"),
    ("3Lab_data.amb", "LABDATA3.AMB"),
    ("2Wall3D.amb", "WALL3D2.AMB"),
    ("3Wall3D.amb", "WALL3D3.AMB"),
    ("2Object3D.amb", "OBJ3D2.AMB"),
    ("3Object3D.amb", "OBJ3D3.AMB"),
    ("2Overlay3D.amb", "OVL3D2.AMB"),
    ("3Overlay3D.amb", "OVL3D3.AMB"),
    ("Lab_background.amb", "LABBACK.AMB"),
    ("Floors.amb", "FLOORS.AMB"),
    ("Monster_groups.amb", "MONSTGRP.AMB"),
    ("Combat_background.amb", "COMBATBG.AMB"),
    ("Monster_gfx.amb", "MONSTGFX.AMB"),
    ("Combat_graphics", "COMBATGF.DAT"),
    ("Riddlemouth_graphics", "RIDDLEGF.DAT"),
    ("Keymap", "KEYMAP"),
    ("Intro_music", "INTROMUS.DAT"),
    ("Extro_music", "EXTROMUS.DAT"),
    ("Saves", "SAVES"),
)
# Save games as in the original (AM2_CPU 1.20, finding 251): in Save.00 to
# Save.10, which become SAVE.00 (the template "new game") to SAVE.10 (the
# slots); those of Save.00 once more in AMBFILES as the working files.
SAVE_FILES = (
    ("Party_data.sav", "PARTYDAT.SAV"),
    ("Chest_data.amb", "CHESTDAT.AMB"),
    ("Party_char.amb", "PARTYCHR.AMB"),
    ("Merchant_data.amb", "MERCHANT.AMB"),
    ("Automap.amb", "AUTOMAP.AMB"),
)
SAVE_SLOTS = 11


def main():
    tables = {"files": GAME_FILES, "saves": SAVE_FILES}
    if len(sys.argv) != 2 or sys.argv[1] not in tables:
        sys.exit(__doc__.split("Usage: ")[1].strip())
    for amiga, atari in tables[sys.argv[1]]:
        print(amiga, atari)


if __name__ == "__main__":
    main()

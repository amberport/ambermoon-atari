#!/usr/bin/env python3
"""
set_save_game.py -- move a copy of a save game to another map (for tests).

For tests that need a place further on in the game (T3: map change 3D -> 3D;
E3: sky in a 3D town).  Thalion's `Save.00` to `Save.10` are all "new game"
(map 258), so an existing save game is copied, and only map, place and view
direction change.

**For testing only.**  It is a jump without the events in between: quests,
doors and party stay as they were in the source.  Nothing in the game's code
changes; only copies of the save game files do.

Layout (Thalion's MAIN.S from `Party_data:`, finding 251):

    Party_data.sav   plain in Thalion's Save.nn; a save game the game wrote
                     has "JH", a key word, then the same data JH-encrypted
                     (ambtool.py).  Load_file reads both, so a copy stays in
                     the form its source has.
      +10  w  Map_nr
      +12  w  Map_Xcoord        from 1
      +14  w  Map_Ycoord        from 1
      +16  w  View_direction    0 north, 1 east, 2 south, 3 west
      +60  w  Travel_mode       0 = on foot
    Saves            w  last slot, then 10 names of 39 bytes each (Thalion
                     offers a slot only if its name is not empty)

Usage:

    python3 tools/set_save_game.py --target DIR --slot 9 \\
        --map 260 --x 28 --y 8 --direction 0 --name "T3 CAVE" \\
        [--source DIR] [--saves FILE]

--source  folder with the five save game files (Amiga or Atari names);
          default Amberfiles/Save.00 of $AMBER_DATEN.  Thalion's disks 1.01
          and 1.07 have no Save.00: name ATARI/AMBFILES/SAVE.00 of a build.
--target  SAVE.nn is made here, with Atari names (as in ATARI/AMBFILES)
--saves   a copy of SAVES: the slot's name and the last slot are set (CONTINUE
          loads it then).  Without it SAVES stays as it is, and the slot needs
          a name on the Atari already.

Save games never go into the repository (.gitignore).
"""

import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ambtool  # noqa: E402
import ambmap   # noqa: E402
import game_names  # noqa: E402
import paths  # noqa: E402

MAP_NR, TRAVEL_MODE = 10, 60
NAME_LENGTH = 38            # Save_name_length (GAME_OFF.S)
SLOTS = 10
DIRECTIONS = "NESW"

MAP_FILES = ("1Map_data.amb", "2Map_data.amb", "3Map_data.amb")


def load_map(nr):
    """Map nr; its entry in the container is the map number itself."""
    for f in MAP_FILES:
        _, entries = ambtool.unpack(open(os.path.join(paths.amberfiles(), f),
                                         "rb").read())
        if nr <= len(entries) and entries[nr - 1] and \
                len(entries[nr - 1]) >= ambmap.TILE_OFFSET:
            return ambmap.parse_map(entries[nr - 1])
    sys.exit(f"there is no map {nr}")


def source_file(folder, amiga, atari):
    for n in (atari, amiga):
        p = os.path.join(folder, n)
        if os.path.isfile(p):
            return p
    sys.exit(f"{amiga} / {atari} is missing in {folder}")


def open_party(raw):
    """Party_data.sav -> (head, plain data); head is empty for a plain file."""
    kind = ambtool.identify(raw)
    if kind == "RAW":
        return b"", bytearray(raw)
    if kind != "JH":
        sys.exit(f"Party_data.sav: unexpected format {kind}")
    w0, w1 = struct.unpack(">HH", raw[:4])
    return raw[:4], bytearray(ambtool.jh_decrypt(raw[4:], w0 ^ w1))


def close_party(head, data):
    if not head:
        return bytes(data)
    w0, w1 = struct.unpack(">HH", head)
    return head + ambtool.jh_decrypt(bytes(data), w0 ^ w1)   # XOR: symmetric


def main():
    a = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    a.add_argument("--source", default=None)
    a.add_argument("--target", required=True)
    a.add_argument("--slot", type=int, required=True)
    a.add_argument("--map", type=int, required=True)
    a.add_argument("--x", type=int, required=True)
    a.add_argument("--y", type=int, required=True)
    a.add_argument("--direction", type=int, default=0, choices=range(4))
    a.add_argument("--name", default=None)
    a.add_argument("--saves", default=None)
    o = a.parse_args()

    if not 1 <= o.slot <= SLOTS:
        sys.exit("--slot 1..10 (0 is the template \"new game\")")
    source = o.source or os.path.join(paths.amberfiles(), "Save.00")

    m = load_map(o.map)
    kind = {1: "3D", 2: "2D"}.get(m["type"], "?")
    if not (1 <= o.x <= m["width"] and 1 <= o.y <= m["height"]):
        sys.exit(f"({o.x},{o.y}) is outside map {o.map} "
                 f"({m['width']}x{m['height']})")
    tile = (o.y - 1) * m["width"] + (o.x - 1)
    if m["type"] == 1 and m["wall"][tile]:
        print(f"Warning: wall or object {m['wall'][tile]} stands on "
              f"({o.x},{o.y})", file=sys.stderr)

    files = [(atari, source_file(source, amiga, atari))
             for amiga, atari in game_names.SAVE_FILES]
    target = os.path.join(o.target, "SAVE.%02d" % o.slot)
    os.makedirs(target, exist_ok=True)
    for atari, path in files:
        raw = open(path, "rb").read()
        if atari == "PARTYDAT.SAV":
            head, d = open_party(raw)
            old = struct.unpack(">4H", d[MAP_NR:MAP_NR + 8])
            struct.pack_into(">4H", d, MAP_NR, o.map, o.x, o.y, o.direction)
            if struct.unpack(">H", d[TRAVEL_MODE:TRAVEL_MODE + 2])[0]:
                print("Warning: Travel_mode is not 0 (on foot)",
                      file=sys.stderr)
            raw = close_party(head, d)
        open(os.path.join(target, atari), "wb").write(raw)

    if o.saves:
        s = bytearray(open(o.saves, "rb").read())
        if len(s) != 2 + SLOTS * (NAME_LENGTH + 1):
            sys.exit(f"{o.saves}: unexpected length {len(s)}")
        name = (o.name or "TEST").encode("ascii")[:NAME_LENGTH]
        p = 2 + (o.slot - 1) * (NAME_LENGTH + 1)
        s[p:p + NAME_LENGTH + 1] = name.ljust(NAME_LENGTH + 1, b"\0")
        struct.pack_into(">H", s, 0, o.slot)
        open(o.saves, "wb").write(s)

    print(f"{target}: map {old[0]} ({old[1]},{old[2]}) -> map {o.map} "
          f"({kind}, {m['width']}x{m['height']}) ({o.x},{o.y}) facing "
          f"{DIRECTIONS[o.direction]}" +
          (f"; {o.saves}: slot {o.slot} \"{o.name or 'TEST'}\", last"
           if o.saves else ""))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""am2cpu_read.py -- read Thalion's unreleased library.

DEVIATION (goals 1 and 2), docs/17-deviations.md D2: NAMES and STUECKE in
am2cpu_code.py say where the pieces it takes lie in AM2_CPU.

AM2_CPU is an Amiga hunk executable: Thalion's assembled game together with
the library, whose source was never released.  Where a contract cannot be
seen at the call sites (registers, variables, pixel format), it is in here.
This tool only reads: it splits the file into hunks with their relocations,
disassembles a routine and writes at every relocated address where it points
(hunk, offset, known name).

**What for.**  The results are *contracts*: what a routine reads, writes and
returns.  What depends on the screen, the blitter or the operating system we
write ourselves from that, for Falcon and ST.  Pure memory code is taken by
am2cpu_code.py at build time (user, 2026-09-28; docs/02 A7), which uses NAMES
below for its relocations.  The findings are in docs/02-3D-Renderpfad.md and
docs/04.

AM2_CPU stays where it is (AMBER_DATEN); this tool stores nothing.

**Disassembler.**  GNU objdump with m68k support.  It looks for
``$AMBER_OBJDUMP``, then four known names in PATH, then any other
``m68k-*-objdump`` in PATH, then the copies in the VS Code extensions
(atari-st-dev, amiga-debug).  On Debian and Ubuntu it is the package
binutils-m68k-linux-gnu, on macOS Homebrew's m68k-elf-binutils.

Usage:

    am2cpu_read.py hunks                     list of hunks
    am2cpu_read.py dis put_dpoly             routine by name (NAMES below)
    am2cpu_read.py dis 11:886 --to 11:a00    by hunk:offset (hex)
    am2cpu_read.py dis 0:21b06 -n 40         the first 40 instructions
    am2cpu_read.py who 11:886                who jumps there (jsr/jmp)
    am2cpu_read.py find 024000ffe548         byte sequence (hex) in all hunks
    am2cpu_read.py data 4:75fe -l 64         data bytes as a hex dump

Without ``--to``/``-n``, ``dis`` ends at the first rts/rte/jmp that no branch
inside the routine jumps over (an approximation).
"""
import argparse
import glob
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import paths

# Known addresses: (hunk, offset) -> name.  Each entry has its proof: found
# through a call site in Thalion's assembled code whose source we have.  Add
# to it when a name is proven.
NAMES = {
    # 3D_MAP.S Draw_faces: "jsr Get_wall_address / jsr put_dpoly".
    # Get_wall_address found by the pattern and.w #$ff,d0 / lsl.w #2,d0 /
    # move.l 0(a0,d0.w),a0 / rts; the jsr after it is put_dpoly.
    (0, 0x1175E): "Get_wall_address",
    (11, 0x0886): "put_dpoly",
    # 3D_MAP.S make_3dzoom2: the only jsr there.
    (11, 0x3978): "draw_zoomshape",
    # 3D_MAP.S M3_DisUpd, the call sequence from hunk 0 $101FC (pattern of the
    # Show call: moveq #9,d6 / move.w #144,d7 / move.l MOVEP_ptr,a0).
    (0, 0x24B30): "Claim_pointer",
    (0, 0x24B6E): "Free_pointer",
    (0, 0x12040): "Calculate_camera_height",
    (0, 0x2A774): "Draw_floor",
    (0, 0x2A70A): "Draw_ceiling",
    (0, 0x120C4): "Draw_horizon",
    (0, 0x10B18): "Draw_dungeon",
    (0, 0x21B06): "Show_MOVEP_screen",
    (0, 0x21592): "Clear_1plane_block",
    # Music (docs/13): Thalion's XREF in VARIOUS.S, the player's jump table;
    # Set_music jumps to +0/+12/+16, the VBL to +24.
    (0, 0x2AA0E): "Sa_spieler",       # Thalion's Music_routine (docs/13)
    (0, 0x26872): "Set_music",
    (0, 0x12132): "Draw_stars",
    # 3D_MAP.S Draw_horizon: the only jsr to it (hunk 0 $12116).
    (11, 0x0000): "Insert_horizon",
    # CPU versions: every 3D routine tests Blitter_or_CPU first and jumps
    # here on $FF (docs/02 A3).
    (0, 0x29A6E): "put_dpoly_CPU",
    (0, 0x2A036): "draw_zoomshape_CPU",
    (0, 0x29A42): "Insert_horizon_CPU",
    # 3D_MAP.S Load_3D_map_data, the sequence around "jsr Init_zoom_table"
    # (0:$0FC48) and around the overlays (0:$0F900..).
    (0, 0x10ACE): "Init_zoom_table",
    (0, 0x23DCE): "Reallocate_memory",
    (0, 0x24050): "File_allocate",
    (0, 0x23D52): "Invalidate_memory",
    (0, 0x24020): "Allocate_CHIP",
    (0, 0x24030): "Allocate_FAST",
    (0, 0x24000): "Clear_memory",
    (0, 0x23F82): "Free_memory",
    (0, 0x250C8): "Load_subfile",
    (0, 0x25162): "Load_unique_subfile",
    (0, 0x25208): "Load_batch_of_subfiles",
    (0, 0x25354): "Load_batch_of_unique_subfiles",
    (0, 0x118E6): "Put_unmasked_MOVEP_block",
    (0, 0x11916): "Put_masked_MOVEP_block",
    # Load_subfile -> $24FFA -> file name: picks 1/2/3 by Map_nr.
    (0, 0x29846): "Dateiname_bilden",
    # 3D_MAP.S Set_D3_light_level (pattern moveq #14,d7 / sub.w d0,d7 /
    # moveq #15,d6), the only jsr in the loop.
    (0, 0x23332): "Fade_colour",
    # Decompress: four jsr, one of them from the game code (0:$01C6A; DISPLAY.S
    # has one jsr Decompress), three from the file loader behind the check
    # cmpi.l #$014C4F42 (1, "LOB").  Lob_core is its loop (am2cpu_code.py).
    (0, 0x26124): "Decompress",
    (0, 0x261E4): "Lob_core",
    # 3D_MAP.S Left90_3D and others: "dbra d7,.Loop / jsr Copy_screen /
    # move.l (sp)+,d7 / rts", four times the same target.
    (0, 0x21456): "Copy_screen",
    # Double buffer (finding 200).  Update_screen and Switch_screens told apart
    # by their number of callers (189 against 158 jsr in Thalion's source, 39
    # against 37); Update_screen calls Copy_screen, Switch_screens does not.
    (0, 0x21344): "Init_screens",
    (0, 0x2137A): "Update_screen",
    (0, 0x213C4): "Switch_screens",
    # Blitter A -> D from the visible to the back screen, clipped against
    # CA_Sp; the only caller is COMOBS.S Draw_combat_screen.
    (0, 0x215F0): "Duplicate_block",
    (0, 0x27B22): "ScrQ_handler",
    (0, 0x27F50): "HDOBs_zeichnen",
    (0, 0x28050): "HDOBs_loeschen",
    # Box and text, both clipped against CA_Sp (finding 259).
    # Draw_box: 82 callers against 84 jsr Draw_box in the source.
    # Print_centered_string: the byte sequence from HULL/WORDS.S (movem.l
    # d0/d2/d6, move.w d0,d6, jsr Strlen), found once; it calls Put_text_line
    # (114 callers against 115 jsr Put_text_line in the source).
    (0, 0x21E64): "Draw_box",
    (0, 0x26E90): "Print_centered_string",
    (0, 0x239A8): "Put_text_line",
    # Variables.  Proven at M3_DisUpd (0:$101A6..), Draw_dungeon and the
    # operands of put_dpoly/draw_zoomshape.
    (9, 0x36D4): "MOVEP_ptr",
    (9, 0x36D8): "MPB_ptr",
    (9, 0x3702): "Map_nr",
    (9, 0x9CC0): "CPU_68020_plus",
    (9, 0x9CEA): "Schirm_merker",
    # COMBAT_M.S "move.w d0,Vertical_screen_offset" = 0:$20908; the Copper
    # moves DIWSTRT/DIWSTOP by it (0:$21280).
    (9, 0x9CEC): "Vertical_screen_offset",
    (9, 0x9CF0): "Schirm_vorn",  # our name (LIBRARY.S, B1a)
    # Off_screen/Work_screen: CONTROLS.S "move.l Off_screen,Work_screen ; Reset".
    (9, 0x9CF4): "Off_screen",
    (9, 0x9CF8): "Work_screen",
    (9, 0xED6C): "Zoomscreen1_ptr", (9, 0xED70): "Zoomscreen2_ptr",
    # The stack pointer of the clip areas: "move.l (CA_Sp),a0 / move.l (a0),a0"
    # and then X1,X2,Y1,Y2 as in Thalion's EFFECTS.S ("move.l CA_Sp,a0 ; Get
    # CA"), in all block routines from 0:$2161C and before the zooms.
    (9, 0x9D02): "CA_Sp",
    (6, 0x00C0): "Blitter_or_CPU",
    (9, 0xE6AC): "zoom_screen",
    (9, 0xE6B0): "zoom_screen2",
    (9, 0xE6B6): "Floor_X",
    (9, 0xE6BA): "Floor_Z",
    (9, 0xE6C8): "cls_top",
    (9, 0xE6CA): "cls_bottom",
    (9, 0xE6CC): "dpoly_koos3d",
    (9, 0x0EEE): "seethru_flag",
    (9, 0x0EF0): "scry",
    (9, 0x0EF2): "cx1",
    (9, 0x0EF4): "cy1",
    (9, 0x0EF6): "cx2",
    (9, 0x0EF8): "cy2",
    (4, 0x3D10): "scrx",
    (4, 0x65C4): "Sinus_table",
    (4, 0x76A8): "Race_heights",
    (2, 0x0000): "zoom_ptrbuff",
    (2, 0x0500): "Wall_ptrs",
    # Hunk 2 is Longword_BSS: Thalion's MAIN.S ends with wall_list0 at $BC0
    # (320+32+400 longwords), the library comes after it.  3D_MAP.S sets
    # Floor_source_gfx (M3_DisUpd, "Get Floor_buffer_handle,Floor_source_gfx")
    # but defines it nowhere: it is a name of the library.
    (2, 0x0BC0): "Floor_source_gfx",
    # 3D_MAP.S M3_DisUpd "move.w Y_angle,d0 / neg.w d0" (0:$101BC) and
    # Calculate_camera_height "move.w d2,head_height" (0:$120B8).
    (9, 0x1B6A): "Y_angle",
    (9, 0x1B94): "head_height",
}

HUNK_MAGIC = b"\x00\x00\x03\xf3"
END = re.compile(r"^\s*(rts|rte|jmp)\b")


def amberfiles():
    return paths.amberfiles()


def load_hunks(path):
    """-> list of dict(type, size, data, reloc={offset: target hunk})."""
    d = open(path, "rb").read()
    if d[:4] != HUNK_MAGIC:
        sys.exit("%s: not an Amiga hunk executable" % path)
    u = lambda o: struct.unpack(">I", d[o:o + 4])[0]
    o = 4
    while u(o) != 0:
        o += 4 * (u(o) + 1)
    o += 4
    count, first, last = u(o), u(o + 4), u(o + 8)
    o += 12 + 4 * count
    hunks = []
    while o < len(d) and len(hunks) <= last - first:
        t = u(o) & 0x3FFFFFFF
        o += 4
        if t == 0x3EB:                                   # BSS
            hunks.append(dict(type="BSS", size=u(o) * 4, data=b"", reloc={}))
            o += 4
        elif t in (0x3E9, 0x3EA):                        # CODE, DATA
            n = u(o) * 4
            o += 4
            hunks.append(dict(type="CODE" if t == 0x3E9 else "DATA", size=n,
                              data=d[o:o + n], reloc={}))
            o += n
        elif t == 0x3EC:                                 # RELOC32
            while True:
                c = u(o)
                o += 4
                if c == 0:
                    break
                target = u(o)
                o += 4
                for _ in range(c):
                    hunks[-1]["reloc"][u(o)] = target
                    o += 4
        elif t in (0x3F0, 0x3F1):                        # SYMBOL, DEBUG
            o += 4 + u(o) * 4
        elif t == 0x3F2:                                 # END
            pass
        else:
            sys.exit("unknown hunk type $%X at $%X" % (t, o - 4))
    return hunks


OBJDUMP_MISSING = """no m68k objdump found.  It comes with GNU binutils for m68k:
  Debian, Ubuntu:  sudo apt install binutils-m68k-linux-gnu
  macOS:           brew install m68k-elf-binutils   (Homebrew)
  other systems:   a package of binutils for m68k, often of the same name;
                   any m68k-*-objdump in PATH will do
or set AMBER_OBJDUMP to its path (environment or build.cfg)."""


def objdump():
    candidates = [paths.value("AMBER_OBJDUMP")]
    for n in ("m68k-atari-mintelf-objdump", "m68k-atari-mint-objdump",
              "m68k-amiga-elf-objdump", "m68k-linux-gnu-objdump"):
        candidates.append(shutil.which(n))
    # any other target, e.g. m68k-elf-objdump
    for d in os.environ.get("PATH", "").split(os.pathsep):
        candidates += sorted(glob.glob(os.path.join(d, "m68k-*-objdump")))
    # The VS Code extension keeps its tools per platform; on macOS under
    # darwin.  Windows builds through WSL, which is linux.
    platform = "darwin" if sys.platform == "darwin" else "linux"
    candidates += sorted(glob.glob(os.path.expanduser(
        "~/.vscode/extensions/*/sdk/%s/opt/cross-mint/bin/m68k-*-objdump"
        % platform)))
    candidates += sorted(glob.glob(os.path.expanduser(
        "~/.vscode/extensions/*/bin/%s/opt/bin/m68k-*-objdump" % platform)))
    for c in candidates:
        if c and os.access(c, os.X_OK):
            return c
    sys.exit(OBJDUMP_MISSING)


def place(text):
    """'11:886' -> (11, 0x886); a name from NAMES works too."""
    for k, v in NAMES.items():
        if v == text:
            return k
    m = re.fullmatch(r"(\d+):(?:\$|0x)?([0-9a-fA-F]+)", text)
    if not m:
        sys.exit("a place is hunk:offset (hex) or a known name: %s" % text)
    return int(m.group(1)), int(m.group(2), 16)


def name_of(h, v):
    n = NAMES.get((h, v))
    return "%d:$%05X%s" % (h, v, " " + n if n else "")


def disassemble(hunks, h, start, to, count):
    data = hunks[h]["data"]
    reloc = hunks[h]["reloc"]
    end = to if to is not None else min(len(data), start + 0x4000)
    with tempfile.NamedTemporaryFile(suffix=".bin") as f:
        f.write(data)
        f.flush()
        dump = subprocess.run(
            [objdump(), "-D", "-b", "binary", "-m", "m68k:68030",
             "--start-address=0x%x" % start, "--stop-address=0x%x" % end, f.name],
            capture_output=True, text=True, check=True).stdout
    lines = []
    for z in dump.splitlines():
        m2 = re.match(r"^\s*([0-9a-f]+):\t((?:[0-9a-f]{4} ?)+)\s*$", z)
        if m2:                         # continuation line of a long instruction
            if lines:
                lines[-1][1] += len(m2.group(2).split()) * 2
            continue
        m = re.match(r"^\s*([0-9a-f]+):\t((?:[0-9a-f]{4} ?)+)\s*\t(.*)$", z)
        if not m:
            continue
        addr = int(m.group(1), 16)
        lines.append([addr, len(m.group(2).split()) * 2, m.group(3)])
    # branch targets of the instructions read so far, for the end criterion
    branch = re.compile(r"\s*(b[a-z]{1,2}[sw]?|db[a-z]{1,2})\s")
    furthest = 0
    output = []
    for i, (addr, n, instr) in enumerate(lines):
        notes = []
        for o in range(addr + 2, addr + n, 2):
            if o in reloc:
                target = struct.unpack(">I", data[o:o + 4])[0]
                notes.append("-> " + name_of(reloc[o], target))
        # name branch targets in the same hunk (only without a relocation:
        # otherwise the number is an offset in another hunk)
        if not notes and re.match(r"\s*(b|db|jsr|jmp)", instr):
            for t in re.findall(r"\b0x([0-9a-f]+)\b", instr):
                if (h, int(t, 16)) in NAMES:
                    notes.append(NAMES[(h, int(t, 16))])
        label = NAMES.get((h, addr))
        if label:
            output.append("%s:" % label)
        output.append("  %05x  %-40s%s" % (addr, instr,
                      ("; " + ", ".join(notes)) if notes else ""))
        if count and len([a for a in output if a.startswith("  ")]) >= count:
            break
        if branch.match(instr):
            for t in re.findall(r"\b0x([0-9a-f]+)\b", instr):
                furthest = max(furthest, int(t, 16))
        if to is None and not count and END.match(instr) \
                and furthest <= addr:
            break
    return output


def who(hunks, h, v):
    hits = []
    for j, hk in enumerate(hunks):
        d = hk["data"]
        for o, target in hk["reloc"].items():
            if target == h and struct.unpack(">I", d[o:o + 4])[0] == v \
                    and d[o - 2:o] in (b"\x4e\xb9", b"\x4e\xf9"):
                hits.append("%s %s" % ("jsr" if d[o - 1] == 0xB9 else "jmp",
                                       name_of(j, o - 2)))
    return hits


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("command", choices=("hunks", "dis", "who", "find", "data"))
    p.add_argument("place", nargs="?")
    p.add_argument("--to")
    p.add_argument("-n", type=int, default=0, help="at most n instructions")
    p.add_argument("-l", type=lambda s: int(s, 0), default=64, help="bytes (data)")
    p.add_argument("--file", default=os.path.join(amberfiles(), "AM2_CPU"))
    a = p.parse_args()
    hunks = load_hunks(a.file)

    if a.command == "hunks":
        for i, hk in enumerate(hunks):
            print("%2d  %-4s %7d bytes  %5d relocations" % (
                i, hk["type"], hk["size"], len(hk["reloc"])))
    elif a.command == "dis":
        h, v = place(a.place)
        to = place(a.to)[1] if a.to else None
        print("\n".join(disassemble(hunks, h, v, to, a.n)))
    elif a.command == "who":
        h, v = place(a.place)
        print("\n".join(who(hunks, h, v)) or "nobody (by jsr/jmp abs.l)")
    elif a.command == "find":
        pattern = bytes.fromhex(a.place)
        for i, hk in enumerate(hunks):
            o = hk["data"].find(pattern)
            while o >= 0:
                print(name_of(i, o))
                o = hk["data"].find(pattern, o + 1)
    elif a.command == "data":
        h, v = place(a.place)
        d = hunks[h]["data"][v:v + a.l]
        for i in range(0, len(d), 16):
            print("%d:$%05X  %s" % (h, v + i, d[i:i + 16].hex(" ")))


if __name__ == "__main__":
    main()

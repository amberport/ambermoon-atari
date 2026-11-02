# 9. Build and checks

## The builds

| Script | Builds | Needs |
|---|---|---|
| `tools/build_all.sh` | both, one after the other: the one build | everything below |
| `tools/build_falcon.sh` | the Falcon programs | `a56` only if the mixer changed: without it the build takes the assembled `musik/musik_dsp.dsp` |
| `tools/build_st.sh` | the ST programs, on its own | no `a56`: under `ZIEL_ST` the mixer drops out |

Each takes the game files on the command line (`sh tools/build_all.sh
FILE`), which wins over `AMBER_DATEN`. `TESTBUILDS=1` adds the test builds
(below).

Both deliver into **one folder, `ATARI/`**, laid out like `Amberfiles/` on
the Amiga (finding 262): the loaders on top, everything else in
`ATARI/AMBFILES/`. Game files and save games are the same for both
machines, so one folder plays on either, and a save game from one continues
on the other. The program names are unique per machine:

| | Falcon | ST |
|---|---|---|
| loader (top) | `AMBER.TOS`, one for both (cookie `_MCH`) | the same |
| engine | `ENGINE.TOS` | `ENGINEST.TOS` |
| fantasy intro | `FANTASY.TOS` | `FANTSYST.TOS` |
| intro, extro | `INTRO.TOS`, `EXTRO.TOS` | `INTROST.TOS`, `EXTROST.TOS` |

`AMBER.TOS` skips a missing program silently. Only the ST build delivers
`STPAL.DAT`, the precomputed ST palettes (`tools/st_palettes.py build`; deviation D1 in
`docs/17-deviations.md`).

**What a build removes.** Before delivering, each build empties
`ATARI/` and `ATARI/AMBFILES/` except `*.INF` (desktop and music settings
belong to the user) and the files the other build delivered last time
(`build/delivered_falcon.txt`, `build/delivered_st.txt`). A Falcon build
alone thus leaves the ST programs of the last ST build in place and says
so at the end.

**Output: one line per step** (user, 2026-10-29). `build_common.sh` gives
the scripts `step NAME` (closes the step before with a tick and its
seconds, opens the next), `note TEXT` (the short note on the step's line)
and `warn TEXT` (shown with `!` under the step and counted in the closing
line). The script that starts first sends its own output and that of every
build it calls into `build/build.log`; only the step lines reach the
terminal, and `VERBOSE=1` shows everything. A step ends badly only by an
exit: the trap on `EXIT` then marks it `✗ FAILED` and shows the last 25
lines of the log, where a path check's "MISSING" line also appears. The
closing line gives the time, the number of warnings, the YM state and the
diagnostic switches; the last line names the build.

The shared part is `tools/build_common.sh` (sourced, not run). **While it
is sourced**, before the first step, it settles what the steps read:

- `ambermoon_gamedata/bin/` and `ambermoon_gamedata/vbcc/bin/` go in front
  of the `PATH`, and it is exported, so every script finds the same tools.
- A name on the command line is checked first, so that a wrong one stops
  before anything is downloaded.
- `tools/fetch_source.py` fetches Thalion's source, only if it is missing
  and its path is the default.
- `tools/game_files.py` finds the game files in what names them, a folder,
  a zip or disk images, and unpacks zips and disks into `build/game_files/`
  (`adf_read.py`; DMS through `xdms`, IPF through `ipf_to_adf.py`).
- `tools/fetch_vbcc.py` fetches vasm and vlink, only if one is missing,
  into `ambermoon_gamedata/bin/` (Linux x86-64).
- `tools/thalion_prepare.py` writes **`build/thalion/Amberfiles`** for
  Thalion's disks (below); from there on `AMBER_DATEN` points at that
  folder. For 1.2x it does nothing.

`AMBER_DOWNLOAD=NO` forbids both downloads. The steps:

1. **Sources and switches** (`prepare`): shows where Thalion's source, the
   game files, the `objdump`, vasm, vlink and the YM SNDH file come from;
   stops if a required one is missing. `a56` is shown, for the Falcon, and
   its absence is no stop. A vasm other than 1.9a, or `VASM_EXTRA` set,
   warns; without the YM SNDH there is a hint. `build_name.py` writes the
   build's name.
2. **Library data from `AM2_CPU`:** `am2cpu_auszug.py` →
   `build/am2cpu_daten.i`; `textmarken.py` → `build/textmarken.i`;
   `am2cpu_code.py` → `build/am2cpu_code.i` (needs an m68k `objdump`);
   `intro_auszug.py` → `build/intro_daten.i`.
3. **Constants against Thalion's source** (`ambchest.py`).
4. **YM music from the SNDH**, only with the YM SNDH file: `ym_auszug.py
   --sndh` → `build/MUSIK_YM.BIN`.
5. **Delivery** (`deliver_data`, in each machine's step "Game files and
   delivery"): game files renamed to 8.3, save game folders from
   `Save.nn/`, the YM music, `BUILD.TXT`; `*.INF` left alone.

Under `build_all.sh` steps 1–4 and the source checks run once.

## Which version of the game

`AMBER_DATEN` may hold 1.01 German, 1.07 English, 1.20 German or 1.21
German, English or French; the build needs no switch. Polish and Czech
1.21 build the engine and the fantasy intro and stop at the intro, because
their `Ambermoon_intro` is a different program. All places in our tables
and sources are those of **German 1.20**. Three layers carry them to the
other versions, each proved against the file it reads; a version the
tables do not know stops the build, with a message naming the tool that
makes the table.

**`AM2_CPU`.** `am2cpu_places.py` finds the places of 1.20 in a 1.2x
`AM2_CPU`, from anchors the tools already know, with no bytes of Thalion's
code in the repository; for 1.20 every shift is 0. `am2cpu_old.py` lays
Thalion's 1.0x `AM2_CPU` (6 hunks, imploded) out as a virtual 1.21 file (14
hunks), by the ranges in `am2cpu_old_maps.py`, numbers only. `am2cpu_code.py`
checks that every piece it takes comes from Thalion's file, not from a gap
of the virtual image.

**The files 1.0x lacks.** Thalion's disks keep the texts, the item table
and the button graphics inside `AM2_CPU`. `thalion_prepare.py` makes
`Text.amb` in the 1.20 layout, `Objects.amb` and `Button_graphics` from it,
copies `Dict.amb` and `Monster_char.amb` under the 1.2x names, writes
`Saves` (392 zero bytes) and `Save.00`–`Save.10` (copies of `Initial/`), all
into `build/thalion/Amberfiles`. The engine reads them as for 1.2x
(deviation D7, `docs/17-deviations.md`).

**Intro, extro, fantasy intro.** `amiga_places.py` and its map: chapter 10.

The engine stays Thalion's 1.20 source on the older data. Where Thalion
changed a format between 1.01 and 1.20, only a test shows it.

**A new version of the data:** `am2cpu_old_generate.py` (only for an
imploded 1.0x `AM2_CPU`) and `amiga_places_generate.py` write the tables;
both take the 1.20 or 1.21 `Amberfiles` as the reference and are not part
of the build.

**The build's name.** `build_name.py` makes it from the file `VERSION`, the
git commit (`+` for changed files, none without git) and the two version
lines of `Text.amb`:

```
Ambermoon Atari 0.8 (65202f9) for Ambermoon v1.07 26-3-1994 / English
```

It appears in the build's overview and last line, in
`ATARI/AMBFILES/BUILD.TXT`, and as the first lines `ENGINE.TOS` shows at
the start, above the load address.

**The check at the start.** `Check_game_files` (`MAIN.S`, after
`D3_einrichten`, before the screen opens) compares Thalion's
`Version_string1/2` in the loaded `Text.amb` with those the build was made
for (`build/build_name.i`). If they differ, or `Lade_texte` took nothing,
the engine says on the text screen what it was built for and what it found
(`Find_version` in `WORDS_SUP.S` reads that from any `Text.amb`), waits for
a key and goes back to the desktop.

## Inside a build

**A new piece from `AM2_CPU`** (step 2). Data goes into the table
`STUECKE` of `am2cpu_auszug.py` (name, hunk, offset, length, evidence),
Thalion's routines into `STUECKE` of `am2cpu_code.py` (entry name, hunk,
from, to, embedded tables, evidence). A name a routine refers to goes
into `NAMEN` in `am2cpu_lesen.py`, whose disassembler `am2cpu_code.py`
uses. `am2cpu_code.py` stops on
a relocation without a name, a jump out of the piece, a hardware address
or an instruction the 68000 lacks. A piece Thalion calls only on a
68020 (`Draw_floor`/`Draw_ceiling`) goes into `CPU_020` with the evidence,
and may use what `ERLAUBT_020` allows: 32-bit division and multiplication,
nothing else (finding 198). To read a contract in `AM2_CPU` before that:
`am2cpu_lesen.py dis <Name>`, or a place as hunk:offset (`dis 0:C4A2 -n
8`, `daten 4:76A8 -l 40`, `wer 4:76BA`).

**The engine** (`tools/build_engine.sh`, called by both builds):
`tools/musik_dsp.sh` assembles the DSP mixer with `a56` and requires the
result to equal `musik/musik_dsp.dsp`, or without `a56` takes that file
(Falcon only; a changed mixer means `cp build/musik_dsp.dsp
musik/musik_dsp.dsp`, committed with the source); `einheiten_verbinden.py`
writes the export lists;
`vasmm68k_mot -m68030 -Fvobj -esc -align` assembles both units, `spiel.s`
a second time without `opt t-` to check the one expected message (`-esc`
turns C escapes in strings on, so a path in a string is written
`"AMBFILES\\"`); `vlink
-b ataritos` links and writes the relocation table, without which
Thalion's `dc.l <label>` would not run. The ST build sets `VASM_CPU=68000`
and `-DZIEL_ST=1`.

**The Falcon build** then adds a 68000 cross-check of both units, the
fantasy intro, intro and extro, the loader, the checks (below) and the
appendices of this documentation into `build/doku/`. **Test builds, only
with `TESTBUILDS=1`:** `FEEMESS`, `FEECHECK`, `INTROMES`, `INTROPRF`,
`INTRDIAG`, `EXTRDIAG`, `EXTROPRF` (chapter 10) and `FREQ.TOS`, the one tool
only they need; a player has no use for them. **The ST build** adds the ST palettes
(`STPAL.DAT`; with Pillow also the check page
`build/palette_editor/index.html`, without it one warning and no page, the
game files the same), the ST fantasy intro (`FANTSYST.TOS`), the ST intro
(`INTROST.TOS`), the ST extro (`EXTROST.TOS`), its loader and, when it runs alone, the
source checks.

**Expected warnings, in every engine build:** vasm 22 in Thalion's
`HULL/NUMERIC.S` line 339 (`dc.l 10000000000`), vasm 58 four times in
Thalion's files (auto-aligned, because of `-align`), vlink 62 (`start` not
referenced). `engine_warnings` in `build_common.sh` counts them (1, 4, 1)
and does not show them; a changed count is a warning, and so is any other
message, shown under the step "Engine". Any of them is a finding. **vasm warning 2028** ("signed
operand as unsigned") stops the build: once it turned `moveq
#Pal_size-1` into `moveq #-1`, and a `dbra` copied 128 KB (finding 185).

**vasm 1.9a, not 2.0f:** 2.0f reports warning 40 for Thalion's label
`Touch:` and warning 53 for our macros `rseven` and `LOCAL`
(`vorspann.i`), and the cross-check of `opt t-` wants exactly one message,
so the engine step stops.

**Why `-align`:** Thalion's assembler aligned `dc.w`/`dc.l` and
`rs.w`/`rs.l` on its own; without the switch `Search_layer` read a pointer
one byte off (finding 255). A new warning 58 in our code means a missing
`even`.

## The checks

What each check says and what it does not: `docs/16-Pruefwerkzeuge.md`.

| Tool | Guarantees |
|---|---|
| 68000 cross-check | no 68020+ instruction in the shared library |
| `am2cpu_code.py` | every extracted piece: named relocations only, no jump out, no hardware address, 68000 instructions (except the 68020-only floor/ceiling) |
| `einheiten_verbinden.py` | no name in both units, none missing |
| `trap_pruefen.py` | our code calls TOS only through `Gemdos`/`Bios`/`Xbios` (finding 270) |
| `register_pruefen.py` | no routine of ours destroys a register it does not declare; return values listed in `AUSNAHMEN`. It does not see macros |
| `vars_pruefen.py` | no two `a5` variables in `FALCON_OFF.S` overlap |
| `platzhalter_pruefen.py` | no placeholder addressed with `lea` in a code section |
| `amiga_names_convert.py --check` | no place of Thalion's intro or extro left in the old form `<label><hunk>+$hex`, which would keep the 1.20 offset in every other version without an error (chapter 10) |
| `platzhalter_karte.py`, `vollprobe.py` | which call paths still lead to a placeholder; the complete list of names Thalion never released |

## Diagnostic switches

`VASM_EXTRA="-D<switch>=1" sh tools/build_all.sh` (or `build_falcon.sh`, `build_st.sh`)

| Switch | Effect |
|---|---|
| `ZEIGERTAKT` | a bar at the top left shows the VBLs per frame |
| `ENDETEST=n` | an end without its own return value counts as ending *n* |
| `SPEICHERTEST=n` | the *n*th memory request after `Init_program` fails once |
| `LADEFEHLERTEST` | the first `Load_subfile` in the game fails |
| `ABSTURZTEST` | bombs about five seconds in, to test the emergency exit |
| `ENTPACKPRUEF`, `RASTERPRUEF` | self-tests of unpacking and raster list |

A diagnostic build overwrites `ATARI/` like a normal one: set it aside,
build normally, then copy it back under a name of its own.

## Symbol map

```
cd engine && vlink -b ataritos -s -N Program .text -N Fast_DATA .data \
  -N Fast_BSS .bss -N Longword_BSS .bss -N Chip_BSS .bss \
  -M -o /tmp/x.TOS engine.o spiel.o > karte.map
```

Exactly the call of `build_engine.sh`; `/tmp/x.TOS` must equal
`ATARI/AMBFILES/ENGINE.TOS`. After a crash: PC minus the load address
that `ENGINE.TOS` shows at start is the offset in this map (chapter 3).

## Emulator and hardware

- `sh tools/hatari/teste.sh [-m rgb|vga]` runs the delivered build in
  Hatari.
  Hatari is good for logic and ratios; it does not show palette changes
  inside a Falcon frame, and TOS there spares registers that TOS 4.04
  destroys. Real hardware decides.
- `tools/testpaket.py` collects the builds for a hardware test from all
  working trees and uploads them to the Falcon (uIPtool) or copies them to
  an SD card.
- Real hardware and the emulator measure speed differently: Hatari rounds
  to whole VBLs and is good only for ratios.
- **Every Hatari run for timing uses the accuracy switches** (user,
  2026-10-24): `--cpu-exact on --compatible on`, on the Falcon also
  `--data-cache on`; `teste.sh` sets them explicitly instead of relying
  on `~/.config/hatari/hatari.cfg` (which has them on today).
  `--fast-forward on` is harmless for measurements: it only changes the
  speed on the host, not the cycles per VBL; no vsync switch changes the
  emulated machine. Even so, Hatari was 1.7x (2D) to 2.2x (3D) too fast
  against the Falcon, about 4x for the 3D floor (62 instead of 15 cycles
  per pixel on the hardware), because it hardly models the bus wait
  states (2026-10-21, Falcon Tempo).

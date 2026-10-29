# 9. Build and checks

## The builds

| Script | Builds | Needs |
|---|---|---|
| `tools/build_all.sh` | both, one after the other: the one build | everything below |
| `tools/build_falcon.sh` | the Falcon programs | `a56` for the DSP mixer |
| `tools/build_st.sh` | the ST programs, on its own | no `a56`: under `ZIEL_ST` the mixer drops out |

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

There are no ST versions of the intros yet; `AMBER.TOS` skips a missing
program silently, and the engine shows its own start menu. `BOMBEN.TOS`
(68000) is the same for both. Only the ST build delivers `STPAL.DAT`, the
precomputed ST palettes (`tools/st_palettes.py build`; deviation D1 in
`docs/17-deviations.md`).

**What a build removes.** Before delivering, each build empties
`ATARI/` and `ATARI/AMBFILES/` except `*.INF` (desktop and music settings
belong to the user) and the files the other build delivered last time
(`build/delivered_falcon.txt`, `build/delivered_st.txt`). A Falcon build
alone thus leaves the ST programs of the last ST build in place and says
so at the end.

The shared part is `tools/build_common.sh` (sourced, not run):

1. **Sources and switches** (`prepare`): shows where Thalion's source, the
   game files and the YM SNDH file come from; stops if a required one is
   missing; `a56` only for the Falcon.
2. **Library data from `AM2_CPU`:** `am2cpu_auszug.py` →
   `build/am2cpu_daten.i`; `textmarken.py` → `build/textmarken.i`;
   `am2cpu_code.py` → `build/am2cpu_code.i` (needs an m68k `objdump`);
   `intro_auszug.py` → `build/intro_daten.i`; `ym_auszug.py` →
   `build/MUSIK_YM.BIN` with the YM SNDH file (`--sndh`).
3. **Constants against Thalion's source** (`ambchest.py`).
4. **Delivery** (`deliver_data`): game files renamed to 8.3, save game
   folders from `Save.nn/`, the YM music; `*.INF` left alone.

Under `build_all.sh` steps 1–3 and the source checks run once.

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
`tools/musik_dsp.sh` assembles the DSP mixer with `a56`
(Falcon only); `einheiten_verbinden.py` writes the export lists;
`vasmm68k_mot -m68030 -Fvobj -esc -align` assembles both units, `spiel.s`
a second time without `opt t-` to check the one expected message (`-esc`
turns C escapes in strings on, so a path in a string is written
`"AMBFILES\\"`); `vlink
-b ataritos` links and writes the relocation table, without which
Thalion's `dc.l <label>` would not run. The ST build sets `VASM_CPU=68000`
and `-DZIEL_ST=1`.

**The Falcon build** then adds a 68000 cross-check of both units, the
fantasy intro, intro and extro with their diagnostic versions, the loader,
`FREQ.TOS`, `BOMBEN.TOS`, the checks (below) and the appendices of this
documentation into `build/doku/`. **The ST build** adds its loader,
`BOMBEN.TOS` and the source checks.

**Expected warnings, in every build:** vasm 22 in Thalion's
`HULL/NUMERIC.S` line 339 (`dc.l 10000000000`), vasm 58 four times in
Thalion's files (auto-aligned, because of `-align`), vlink 62 (`start` not
referenced). Any other is a finding. **vasm warning 2028** ("signed
operand as unsigned") stops the build: once it turned `moveq
#Pal_size-1` into `moveq #-1`, and a `dbra` copied 128 KB (finding 185).

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

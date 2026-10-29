# 4. The interface

## A name is a contract

Thalion's code says `jsr Put_unmasked_block` or reads `Mouse_X`. The
linker only checks *that* the name exists. Whoever defines it takes on
its whole contract:

- input and output registers, and which registers survive;
- the section: data or code. A data name that Thalion addresses with
  `lea` must not lie among routines, or a write through it overwrites an
  `rts` (finding 157);
- structure length, step width, the behaviour of a macro. `Get` and
  `Free` must not change `d0` and must stay short, because Thalion
  branches over them with `bxx.s` (findings 164, 186).

The same holds the other way round: when our code calls a name that
moves from our side to Thalion's, our call has to meet Thalion's contract
(findings 167, 170, 171).

**Where to find a contract:**

1. **At the call sites.** What Thalion's code sets before the call and
   reads after it. Usually that is enough.
2. **In `AM2_CPU`**, when the call sites leave it open:
   `tools/am2cpu_lesen.py dis <Name>` disassembles Thalion's library
   routine. Places are given as *hunk:offset* (`dis 0:C4A2 -n 8`). What
   counts is the CPU version behind `tst.b Blitter_or_CPU`.

Contracts that surprised us, each with its finding: `Draw_box` takes two
corners, not position and size; `Put_text_line` returns `a0` behind the
terminating zero (173); `a5` is not reserved, so every library entry
loads `lea vars,a5` itself (177); Thalion's rasterisers save no
registers, not even `a5`/`a6`; `Default_MA` is a data record in the
original, not a routine.

## What Thalion hands to the library

| Thalion | Meaning | Ours |
|---|---|---|
| `Screen_depth` = 5 | depth of Thalion's **data** | stays 5. Our screen depth is `PLANES` / `Schirm_ebenen` = 8 (finding 191) |
| `d5` | planes of the source, 1–5; 8 means our own screen format | decides how the source is widened (chapter 6) |
| `d4` | colour offset for the planes from `d5` up | part of the colour |
| `Work_screen` | where to draw | one of our two screens |
| `Raster_list_ptr` of a module | palettes per screen area | colour banks (chapter 6) |
| `Icon_size` = 160 | distance between icons in **Thalion's data** | not the size on our screen (176) |

## Two translation units

As at Thalion: `engine/engine.s` (the library: Thalion's `HULL/`, our
layer, the pieces of `AM2_CPU`) and `engine/spiel.s` (the game: all other
files of Thalion except `FAIRY.S`). It has to be two, because Thalion
defines `Number` and `Control_list_ptr` twice, privately in `HULL` files
(finding 181).

- `tools/einheiten_verbinden.py` writes the export lists
  (`build/xdef_*.i`). It stops the build if a name is defined in both
  units or in neither.
- Across the units only `jsr`, never `bsr`.
- vasm does not compute with a name from the other unit (`#Name/2-1`).

`engine/engine.s` only includes. The path tells the kind:
`INCLUDE "HULL/FADE.S"` is Thalion's file, found through `-I
$AMBER_URCODE`; `INCLUDE "src/HULL/FADE_SUP.S"` is ours. The order
matters (`start` must come first), and after each of Thalion's files
stands `SECTION Program,code`, because Thalion's files end in BSS.
`engine.s` is also one of the two places in main's files that ask for
the machine (`IFD ZIEL_ST`): it includes `FALCON_LIB.S` and `FALCON.S`,
or `ST.S` and `ST_LIB.S`. The other place is the switch block of
`vorspann.i` (below); chapter 5 has the split.

## `vorspann.i`: Thalion's include file, rebuilt

`tools/originalcode/vorspann.i` replaces the include file Thalion did not
release. It holds:

- **constants and structure offsets** that Thalion's code uses but
  `GAME_OFF.S` does not define;
- **macros**: `Get` and `Free` (memory handles), `Push` and `Pop`
  (`Push Module,Name` becomes `lea Name,a0 / jsr Push_Module`), `LOCAL`
  and `rseven` (Devpac features vasm lacks), `R_palette`, `R_range`,
  `R_end` (raster lists), `music` (entry into the music player's jump
  table), `waitblit`;
- **our extensions**: file number 45 for `Button_graphics`, and the
  **switch block** per machine (`IFD ZIEL_ST`): `Schirm_ebenen` (8 on the
  Falcon, 4 on the ST), `SCHIRM_RAND`, `MACHINE_NAME` and the memory hooks
  `MEM_ADDRESS`, `MEM_FREE_HOOK`, `MEM_KILL_HOOK` (chapter 5).
  `Screen_depth` stays 5 on both.

A constant there means what Thalion meant, not what the Falcon has:
`Pal_size` is 32 (finding 185).

Appendix B lists all of it with the number of Thalion's uses.

## Our variables: `FALCON_OFF.S`

`engine/src/FALCON_OFF.S` holds our constants and the variable block that
our routines address relative to `a5` (`p_*`, `v_*`). It is not Thalion's
`GAME_OFF.S`; `engine.s` includes both. Variables that Thalion's code
reads are absolute labels with Thalion's names (`Mouse_X`,
`Button_state`, `VBL_counter`), defined where they belong in our layer.

## Writing a routine of the library

- Read the call sites first, then `AM2_CPU` if needed.
- Save every register the contract does not name as output.
  `tools/register_pruefen.py` checks this in every build; real return
  values go into its `AUSNAHMEN`.
- Call TOS only through the macros `Gemdos`, `Bios`, `Xbios`
  (`FALCON_OFF.S`). TOS 4.04 destroys `d0`–`d2`/`a0`–`a2`; Hatari and
  EmuTOS often do not, so the emulator hides the bug (finding 270).
- Begin the header comment with **`; Name -- one sentence.`**; that
  sentence becomes the description in appendix B.
- Data that Thalion addresses goes into a data or BSS section
  (`tools/platzhalter_pruefen.py`).

# Deviations from the two goals

The two goals (CLAUDE.md) are: **(1)** take Thalion's source unchanged and
build only the library layer; **(2)** read the original game files at run
time instead of converting them in advance. Where the project departs from
them, the user has decided so. This file lists every such place: **what**
happens, **why**, **where** it is in the code, and how to go back.

**How to find them in the code.** Every place is marked with a comment
`DEVIATION (goal N), docs/17-deviations.md Dn`, or `DEVIATION (goals 1
and 2), ...` where both are touched:

```
grep -rn "DEVIATION (goal" engine tools lader intro extro fantasy amiga musik fantasy_st intro_st extro_st
```

A deviation without the marker is a gap in this list; please add both.
Places owned by another session get their marker from that session
(CLAUDE.md, file owners); until then the table says "open". The
markers of D2, D4 and D5 in the 2D session's files stand on `main`
(2026-10-17); in a branch without them the grep does not find them.

## Overview

| Nr | Goal | What | Machine | Decided | Marker |
|---|---|---|---|---|---|
| D1 | 2 | ST palettes reduced at build time, `STPAL.DAT` loaded once at start | ST/STE | user, 2026-10-17 | `ST_LIB.S`, `tools/build_st.sh`, `tools/st_palettes.py` |
| D2 | 1, 2 | Library data, pure memory routines and the music player (operands bent onto shadow registers) of `AM2_CPU` taken at build time; `AM2_CPU` is never read at run time | both | user, 2026-09-27/28 | `tools/am2cpu_extract.py`, `am2cpu_code.py`, `am2cpu_read.py`, `engine/engine.s`; open: 3D and music session |
| D3 | 1, 2 | Intro, extro, fantasy intro: Thalion's programs taken apart at build time and bent (K1, K2), own routines at the bottlenecks (K3, `Fee_ablauf`); the ST builds all three itself (below) | both | user, 2026-09-29 and 2026-10-04; ST 2026-10-22/24/29; Falcon fantasy intro 2026-10-30 | Falcon: `fantasy/FEE_SUP.S`, `fantasy/STARS_FALCON.S` (fantasy intro), the rest open (Falcon Tempo); ST: `fantasy_st/`, `intro_st/`, `extro_st/`, `tools/fantasy_st_data.py`, `tools/intro_st_program.py`, `tools/extro_st_program.py`, `tools/extro_st_data.py` |
| D4 | 1, 2 | Our own start menu for `ENGINE.TOS` started alone; its four texts from `Ambermoon_intro` at build time | both | user, 2026-09-28 ("plain, for now") | `tools/intro_auszug.py`, `HULL/STARTMENUE.S` |
| D5 | 2 | Positions of the library's texts inside `Text.amb` fixed at build time | both | finding 250 | `tools/text_labels.py`, `HULL/WORDS_SUP.S` |
| D6 | 1, 2 | YM music from Big Alec's SNDH file (`big_alec/ambermon.snd`, until 2026-10-27 the "Ambermoon Music Demo" disk), extracted at build time; Big Alec's player instead of Thalion's | ST, Falcon with `YM` | user, 2026-09-29 (docs/11 7.1) | open (music session) |
| D7 | 2 | Game versions 1.01 and 1.07: `Text.amb`, `Objects.amb`, `Button_graphics` made from `AM2_CPU` at build time | both | user, 2026-11-02 | `tools/thalion_prepare.py` |
| D8 | 1 | Our column loop for opaque 3D walls instead of Thalion's inner loop in `put_dpoly`; same picture, point for point | both | user, 2026-11-02 | `HULL/D3_WALLS.S`, `tools/am2cpu_code.py` (`EINGRIFFE`), `engine/engine.s` |
| D9 | 1 | Texel loop of floor and ceiling (Falcon Tempo, E16); the number is kept for it, the text follows from Falcon Tempo after T74 | Falcon | open (Falcon Tempo) | open (Falcon Tempo: `HULL/D3_FLOOR.S`) |
| D10 | 1 | Coarse walls while the view moves: opaque walls in pairs of columns from one texel; standing still, Thalion's picture; a switch, off by default. For it, the first instruction of Thalion's `Draw_dungeon` is turned into a jump to our `D3_frame` at run time | both | user, 2026-11-04 | `HULL/D3_WALLS.S`, `engine/engine.s` |
| D11 | 1 | `Timer` capped at $1000 in the VBL, so that Thalion's word compare in `Make_2D_move` cannot go negative: the 2D map no longer stops taking moves after 9–11 minutes of standing still (a bug of the Amiga original) | both | user, 2026-11-06 | `HULL/LIBRARY.S` (`Bibliothek_vbl`) |
| D12 | 1 | Our loop for the horizontal scaling of an enlarged 3D object instead of Thalion's in `draw_zoomshape`; same picture, point for point | both | user, 2026-11-07 | `HULL/D3_WALLS.S`, `tools/am2cpu_code.py` (`EINGRIFFE`, `EINSPRUENGE`) |
| D13 | 1 | Our rotation of the 3D point grid and our sort of the faces instead of Thalion's `rotate_y` and `Quicksort` (`3D_MAP.S`); the first six bytes of each are turned into a jump at run time; same results, bit for bit | both | user, 2026-11-07 | `HULL/D3_WALLS.S` |

Not deviations, for completeness: the 8.3 names of the game files (the
contents stay as they are), the save-game folders `SAVE.nn` (copies of the
original save games). `INTROMUS.DAT`/`EXTROMUS.DAT` stay unchanged on
disk, but the 27 operands bent in Thalion's player at run time belong to
D3 (K1).

D2 to D6 are summarised here from the documents named; the owner sessions
should check the wording when they set their marker.

## D1: precomputed ST palettes (goal 2)

**What.** The ST has 16 colour registers; Thalion's palettes have 32
colours. `ST_LIB.S` reduces every palette to 15 groups plus colour 0 and
keeps a table colour → register (docs/12). Until now it computed this at
run time, in `St_bauen`, for every palette it had not seen. Now the build
does the same computation for every palette the game puts into a raster
list and writes the result into `ATARI/AMBFILES/STPAL.DAT`
(`tools/st_palettes.py build`, called by `tools/build_st.sh`):

- `Palettes.amb` 1–49 (maps, event pictures),
- `Main_pal`, `Tactic_pal`, `Automap_pal` (from `AM2_CPU`, like D2),
- the combat palettes: `Palettes.amb` *N* with colours 26–31 from
  `Tactic_pal`, as Thalion's `Set_layout_colours` makes them; *N* from
  `Combat_bg_2D_table`/`Combat_bg_3D_table`.

65 distinct palettes, 11,448 bytes. Per palette the file holds the key
(the palette as Thalion has it), the table, and the 15 register values
twice: for the STE (4 bits per channel) and for the plain ST (3 bits). The
engine loads the file once when the screen opens (`St_load_palettes`) and
looks a palette up there before it would compute one (`St_from_file`).

**Weighted by the pictures** (user, 2026-10-17). At build time the tool
knows where each palette is used, which `St_bauen` at run time does not:
it counts how many points of each colour the game shows with it (the tiles
of every 2D map as often as they lie on the map, the event pictures, the
combat backgrounds) and groups the colours 1–25 by that weight; the
register values are weighted means. Every colour counts at least 1 % of
the points (`FLOOR`, `--floor`), so rare bright colours keep a say. The
UI ramp 26–31 is grouped as before. Why: unweighted, every colour counted
the same, whether it covers 37 % of the picture or 0.02 %. On Lyramion
(`Palettes.amb` 1, maps 1–256) the dark sea blue landed in a register of
the UI ramp and turned grey, and four greens shared one register: the
world map looked dull and grey. Weighted, the mean deviation per point
falls there from 1.55 to 0.85 steps; of the 37 weighted palettes it falls
in 33, stays in 1 and rises slightly in 3. The price: a rare accent can
lose its register (the orange fire in Grandfather's house, `Palettes.amb`
7, went brown).

**The method per palette** (user, 2026-10-29: "more was right with the
old one; the worlds are the exception"). Every palette is grouped
unweighted, exactly as `St_bauen` does at run time, unless
`tools/st_palettes.txt` names another method for it
(`<palette> method weighted N`, N = the floor in per cent). Weighted are
the three worlds: `Palettes.amb` 1 (Lyramion), 2 (forest moon) and 3
(Morag), at 1 %. The fire in Grandfather's house is red again (E80 and A20
in registers of their own). The palette editor
(`tools/palette_editor/palette_sheet.py`, since 2026-10-30 instead of the
sheet of `st_palettes.py`) shows every palette whose pictures are counted
under each method, with a button to choose it, and writes the method
lines for the file (`build/palette_editor/index.html`). T99 passed. The
user's choice of 2026-10-30 adds 21 palettes: weighted 1 for `pal` 19,
21, 22, 24, 25, 26, 34, 35, 40 and `combat` 29; weighted 3 for `pal` 10,
17, 18, 20, 27, 33, 37 and `combat` 28, 39, 42, 49.

**What is counted since 2026-11-06** (user: "for the 3D worlds and the
tactic screen there are no pictures"). Besides 2D map tiles, event pictures
and combat backgrounds the tool now counts the 3D maps and the tactic field,
so these palettes can take a weighted method too:
- a 3D map counts as many points as a 2D map of its size (256 per square),
  shared out like the 3D view: walls half, objects a tenth (an estimate;
  the view changes with every step), the rest sky above the horizon line
  (`D3_horizon`/`C3_horizon`, the horizon picture in it) and floor below,
  as the ST draws them (no textured floor or ceiling). Each wall (with its
  overlays put in, as `Load_3D_map_data` does) and each object counts by
  how often it stands on the map.
- `Tactic_pal`: the combat layout from line 133 down and each of the 35
  tactical icons once.

This changes no palette without a method line: `STPAL.DAT` stayed byte for
byte the same (1.07, 11,448 bytes). The user's choice of 2026-11-06 with
these pictures: weighted 1 for `pal` 4, 6, 11–16, 23 and `combat` 30, 31,
36, 41, 43–48, weighted 3 for `pal` 7; `pal` 17, 18, 20, 27 and `combat`
28 from weighted 3 to weighted 1 (T104 passed). `tactic` stays unweighted. `Main_pal` and `Automap_pal` still have
nothing counted. Reading the 3D files the tool met entries `ambtool.py`
gives back still encrypted (finding 249, docs/05c).

**Why.** Speed and look. `St_bauen` costs about one second on 8 MHz for
every new palette: at every map change, every combat, every event picture.
And the result could not be corrected by hand: some palettes look wrong on
the ST (world map too colourless, docs/05; the too bright tactic field
was a library error, finding 400 in docs/05c). The
file can carry corrections, kept apart for the ST and the STE.

**What stays at run time.** Thalion's colours still come from the original
files: `Palettes.amb` is loaded by Thalion's code as before, and the file
is only the key to find the entry; the registers are computed from the
colours as they stand (fades, light levels). A palette that is not in the
file -- a fade in between, Thalion's combat flashes, another game version
-- is computed by `St_bauen` as before. Without `STPAL.DAT` the game runs
as before, only with the pauses.

**What the repository holds.** Only our corrections:
`tools/st_palettes.txt` (colour into another register, register values by
hand, per palette and machine). Everything that contains Thalion's colours
is computed at build time and stays out of the repository: the file
itself, the listing `build/st_palettes/listing.txt` and the review sheet
`build/st_palettes/index.html` (`tools/st_palettes.py sheet`: per palette
Thalion's colours, the table, the STE and ST registers, and a picture from
the game three times, Thalion / STE / ST).

**Fades and light levels.** A value from the file holds for the full
palette. While Thalion fades, `st_regs_bauen` scales it per channel by how
much the colours of its group have faded (`srp_hand`), so the fade still
ends in black and a hand-set value fades with it. Only the palette
exactly as it stands is looked up: a 3D map entered in the dark (Thalion
dims colours 0–15 only) is computed by `St_bauen` as before, because the
groups of the bright palette would put dimmed and undimmed colours into
one register.

**Where.**
- `engine/src/HULL/ST_LIB.S`: `St_load_palettes`, `St_from_file`,
  `srp_hand`, entry fields `SE_HAND`, `SE_HWERT`, `SE_HSUMME`.
- `engine/src/HULL/ST.S`: `Open_screen` calls `St_load_palettes`.
- `tools/st_palettes.py`, `tools/st_palettes.txt`, `tools/build_st.sh`;
  the choice on the page of `tools/palette_editor/palette_sheet.py`.

**Going back.** Remove the `STPAL.DAT` line from `tools/build_st.sh` (and
the file from the Atari): the engine falls back to `St_bauen` for every
palette. Corrections in `tools/st_palettes.txt` are then lost.

## D2: AM2_CPU at build time (goals 1 and 2)

**What.** `AM2_CPU` is Thalion's library, not released as source. The
build extracts its data (`Main_pal`, `Tactic_pal`, `Automap_pal`, window
icons, `Status_*`, `Button_up`/`Button_down`, `World_data`, font, mouse
pointers, tables; `tools/am2cpu_extract.py` → `build/am2cpu_daten.i`) and
its pure memory routines into the program: the 3D rasteriser
(`put_dpoly` with the edge list, `draw_zoomshape`, `Insert_horizon`)
including `Draw_floor`/`Draw_ceiling` (pieces in `CPU_020`, which may
contain the instructions in `ERLAUBT_020`, because Thalion calls them only
with `CPU_68020_plus`, so never on the 68000; finding 198), the front part of the combat
zoom (`Draw_zoom_shape`/`Draw_zoom_silhouette` up to our blitter
replacement in `COMBAT_SUP.S`, and the zoom tables), `Recolour_block`,
`Fade_colour` and `Lob_core` (the loop of Thalion's `Decompress`, called
by our `LOB_decompress`; finding 274); `tools/am2cpu_code.py` → `build/am2cpu_code.i`, with
Thalion's internal variables as a BSS block in the original layout. At
run time `AM2_CPU` is never read.

Also Thalion's Sonic Arranger player (`Music_routine` in `AM2_CPU`,
0:$2AA0E–$2BD2A, here `Sa_spieler`; docs/13). Unlike the rasteriser it
touches hardware: `am2cpu_code.py` bends its operands at build time onto
our shadow registers (`Paula_schatten`, the CIA dummies,
`Musik_exec_zeiger`; `UMBIEGEN`), and the mixer turns the shadow into
sound. The name `Music_routine` is our switch in `MUSIK_YM.S`, to
`Sa_spieler` or the YM player.

The build checks every piece and stops at a relocation without a name, a
jump out of the piece, a hardware address or an instruction the 68000
does not know (`tools/am2cpu_code.py`; a hardware address passes only
as an entry in `UMBIEGEN`). Where the pieces lie is in
`tools/am2cpu_read.py` (`STUECKE`, `NAMEN`). Another game version means
building again.

**Why.** Library data that Thalion's code expects at fixed names; code
that only works in memory is Thalion's own and better than a rewrite. The
user ruled that this is not a copy (CLAUDE.md, goal 1).

**Where.** `tools/am2cpu_extract.py`, `tools/am2cpu_code.py`,
`tools/am2cpu_read.py`, the INCLUDE lines in `engine/engine.s`.

**Going back.** docs/02 A7; CLAUDE.md "Daten".

### AM2_CPU and the two goals (user, 2026-11-07)

"grundsätzlich: am2_cpu liegt nicht streng in leitziel 1 und 2. [...] Also
Daten vorbereiten. [...] lieber engine tos wie auch in am2_cpu" (user,
2026-11-07). So what comes from `AM2_CPU` may be replaced or prepared at
build time for speed, and data prepared from it go into `ENGINE.TOS` /
`ENGINEST.TOS`, as the extracts of D2 do, not into a file of their own.
Each such place still gets its Dn here and its marker, so that it stays
known what is ours and what would be Thalion's.

Data from the game files (walls, objects, overlays: `*Wall3D.amb`,
`*Object3D.amb`, `*Overlay3D.amb`) are not `AM2_CPU`. They are loaded per
map, and Thalion's `3D_MAP.S` paints the overlays onto the walls after
loading (`Put_unmasked_MOVEP_block`, `Put_masked_MOVEP_block`, Thalion's
source), so a wall's final picture exists only at run time. Goal 2 holds
for them.

**What of `AM2_CPU` is ours, what is Thalion's** (state 2026-11-07):

| Piece of `AM2_CPU` | Thalion's, unchanged | ours | Dn | way back |
|---|---|---|---|---|
| `put_dpoly` | near plane, projection, edge list, clipping in x, the loop of see-through walls | the column loop of opaque walls; coarse walls while moving (switch, off) | D8, D10 | `-DWALLS_THALION=1`; `COARSE_WALLS=NO` |
| `draw_zoomshape` | clipping, step tables, shrunk objects, mask, copy into the 3D buffer | the horizontal scaling of enlarged objects | D12 | `-DZOOM_THALION=1` |
| `Draw_floor`, `Draw_ceiling` | Falcon: open (Falcon Tempo) | Falcon: the texel loop (open) | D9 | open |
| `Draw_zoom_shape`, `Draw_zoom_silhouette` (combat) | head and zoom tables | the blitter part (`COMBAT_SUP.S`, hardware layer, no deviation) | – | – |
| `Sa_spieler` (music) | the player | operands bent onto shadow registers (D2) | D2 | – |
| `Insert_horizon`, `Recolour_block`, `Fade_colour`, `Lob_core`, the library data | all | – | D2 | – |

Not `AM2_CPU` but Thalion's source (`3D_MAP.S`), bound at run time:
the head of `Draw_dungeon` (D10), `rotate_y` and `Quicksort` (D13).

## D3: intro, extro, fantasy intro (goals 1 and 2)

**What.** The three non-interactive programs are Amiga programs; two have
no source. They run on an emulation of the Amiga hardware they touch
(docs/developer/10-amiga-layer.md), and Thalion's code in them is taken
over at build time and bent:

- *Build time* (goal 2, decision of 2026-09-29, docs/11 7.1):
  `Ambermoon_intro` and `Ambermoon_extro` are split into hunks
  (`tools/amiga_programm.py`, the extro unpacked first by
  `tools/imploder_exe.py`); `FAIRY.S` is assembled unchanged, the rest of
  `Fantasy_intro` (graphics, variables, hunk-1 code) is extracted by
  `tools/fantasy_auszug.py`. None of the three files is read at run time.
- *K1*: hardware operands (`$DFFxxx`, `$BFE001`, ExecBase) are bent onto
  our shadow block: in `FAIRY.S` after linking (`tools/fairy_umbiegen.py`,
  ten operands), in intro and extro at build time (`amiga_programm.py`),
  and in Thalion's music player at run time (`amiga/AMIGA_MUSIK.S`, 27
  operands, checked against `tools/musik_k1.py`).
- *K2*: every write to BLTSIZE becomes `trap #8`; the blit runs in
  software (`amiga/AMIGA_BLIT.S`).
- *K3* (decision of 2026-10-04): at a bottleneck one of Thalion's
  instructions becomes `jmp` into our routine. On the Falcon (main
  f9f3b8f) 29 places in the intro (zoom, picture switch, logo, clouds,
  menu, the writers of the target screens) and 3 in the extro (the copy
  into both screens, the picture switch twice); `amiga_programm.py`
  holds them in its table and prints the count ("K3 an 29", "K3 an 3").
  The full table is in docs/developer/10. The ST builds have their own
  (below).
- *Rewritten*: Thalion's main sequence of the fantasy intro (hunk 1
  $110-$2B0, tied to copper, CIA and DMA) is `Fee_ablauf` in
  `fantasy/FEE_SUP.S`, in Thalion's order and with Thalion's values.
- *Atari format*: the extro's two screens lie in Falcon format and are
  shown directly (`amiga/AMIGA_ZIEL.S`); the fantasy intro draws into
  Falcon screens on the ST's model (below).

Allowed by the decision: an own logo build-up in the fantasy intro
(built on the ST, below), precomputed graphics (built on the ST for the
fantasy intro, below).

**Why.** Pure playback without input: it has to run smoothly, and the
programs touch the hardware directly, so there is no library to replace.
Thalion's sequence, texts, colours and timing stay; the start menu stays
Thalion's code. For the game goal 1 is unchanged.

**Going back.** Delete a K3 entry in `PROGRAMME`
(`tools/amiga_programm.py`) and its routine: Thalion's code runs there
again (slower; the white frame before the zoom returns). For the zoom
alone the switch `ZOOM_THALION` exists. K1/K2 and the build-time
extraction have no way back without giving up the programs.

**Where.** docs/11 (sections 3-7), docs/developer/10-amiga-layer.md; the
files named above.

### D3 on the Falcon: the fantasy intro

*State 2026-10-30 (Falcon Tempo, step 3, test T71; Hatari: `FEECHECK` 497
of 497 frames equal).* The Falcon's fantasy intro has the ST's cut (below,
"Fantasy intro"); docs/11 7.3 has the details.

- **Rewritten:** Thalion's main sequence is `Fee_ablauf`
  (`fantasy/FEE_SUP.S`), in Thalion's order and with Thalion's values.
- **Hooks:** Thalion's `make_funkel` plots through `plot_jmptab`, which
  points to `Plot_falcon0..31`; `Blitter_warten` does Thalion's two blit
  kinds (`$CA` star, `$E2` logo column) in Falcon format.
- **Own routines:** `Magic_falcon` and `Dust_falcon`
  (`fantasy/STARS_FALCON.S`) instead of Thalion's `make_magic` and
  `make_funkel2`, with Thalion's logic, buffers, tables and random numbers,
  as the ST's `Magic_st`/`Dust_st`; the stars through compiled routines.
- **Precomputed graphics:** background, fairy, logo and stars from
  `tools/fantasy_st_data.py --falcon` (8 planes, the Amiga colours, no
  reduction); nothing is converted at run time, no Amiga screen is shown.
- **The fairy:** from 16 preshifts made at start, put in every VBL with a
  save-under (50 Hz, as the Amiga's sprites; E30).
- **Colours:** no copper split needed; plane 5 is the bank, in the data
  (0 above row 134, 1 from there).

**What looks different:** nothing intended; `FEECHECK` compares Thalion's
`make_magic`/`make_funkel2` with ours frame by frame.

**Going back (Falcon):** call Thalion's `make_funkel2` and `make_magic`
again in `Fee_ablauf` instead of `Dust_falcon`/`Magic_falcon`, then
`Blitter_warten` once for the last blit (as `Check_stars` does);
`Blitter_warten` draws their blits, slower.
The Falcon format and the drawing hooks have no way back short of the
general Amiga layer (docs/11 7.4-7.8, F1-F4).

### D3 on the ST: what is changed, and what looks different

*State 2026-10-27: the fantasy intro passed T94 on the STE; the intro
passed T96a, and the intro without live conversion (every scene a target
screen) is built for T97. The extro is built for T100 (2026-10-30).* The
ST builds the three programs itself, each in its own files, independent
of the Falcon's `fantasy/`, `intro/`, `extro/` and `amiga/`; only the
emergency exit `amiga/AMIGA_NOTAUS.S` is shared, unchanged. Details and
measurements: docs/05c-ST.md ("ST fairy intro, plan", "ST intro", "ST
extro").

**Taken unchanged.** Thalion's `FAIRY.S` (flight path, fairy animation in
`level3`, sparks, the stars' logic, random numbers, the 3-VBL frame);
Thalion's hunk-1 fades and tables of `Fantasy_intro`
(`tools/fantasy_auszug.py`, as on the Falcon). All seven hunks of
`Ambermoon_intro`, with K1 and K2 exactly as on the Falcon
(`tools/intro_st_program.py` calls the functions of
`tools/amiga_programm.py`): every scene, text, timing and the start menu
are Thalion's code. All six hunks of `Ambermoon_extro`, with K1 and K2 as
on the Falcon (`tools/extro_st_program.py`): the flow, the texts and their
writers, the fades, the brightened text plane (`$2B2E`), the timing.

**Replaced: our code instead of Thalion's (or instead of Amiga hardware).**

| Program | On the Amiga (Thalion) | On the ST (ours) | Same result? | Where |
|---|---|---|---|---|
| fantasy | main flow, hunk 1 $110-$2B0 (copper, CIA, DMA) | `Fairy_flow`, Thalion's order and values | as on the Falcon | `fantasy_st/FANTASY_ST.S` |
| fantasy | `make_magic`: logo column and up to 165 stars a frame through the blitter | `Magic_st` (E41): same logic, buffers, tables, random; draws straight into the ST screen | yes: `CHECK_STARS` 350 of 350 frames equal | `fantasy_st/STARS_ST.S` |
| fantasy | `make_funkel2`: dust | `Dust_st` (E41) | yes, same check | `fantasy_st/STARS_ST.S` |
| fantasy | 32 plot routines `.plot00`-`.plot31` (through `plot_jmptab`) | `Plot_st0..15`, one per ST register; `plot_jmptab` points to them | same places; the colour through the band's map | `fantasy_st/FANTASY_ST.S` |
| fantasy | blits of `blit_star`, `blit_star2` (until `waitblit`) | `Blitter_wait`: the star as compiled code for image and shift | same pixels | `fantasy_st/FANTASY_ST.S` |
| fantasy | the fairy: 8 attached hardware sprites | `Fairy_draw`: drawn into the screen from 16 preshifts made at program start | same frame and place, see below for the rate | `fantasy_st/FANTASY_ST.S` |
| fantasy | background restore by blit ($BC0) | `Lower_restore` (copy with `movem`) | yes | `fantasy_st/FANTASY_ST.S` |
| fantasy | copper: seven colours at row 134 | Timer B `Tb_split` | yes | `fantasy_st/FANTASY_ST.S` |
| intro | the zoom from $1C98 on (blitter: a blit per row and per column) | `Zoom_st` (K3), the Falcon's method (fold through a spread table, put, a row with the same source row only put); Thalion's clipping and step tables stay | yes: `CHECK_ZOOM` 98 of 98 zooms equal, into target screens `CHECK_TARGET` 0 differences | `intro_st/ZOOM_ST.S` |
| intro | end of Thalion's VBL ($2824) | `Vbl_end_hook` (K3): our display update, then Thalion's instruction | nothing of Thalion's is left out | `intro_st/INTRO_ST.S` |
| intro | the blitter | `Amiga_blit` in software, fast paths for clear, copy, $CA | yes: `CHECK_BLIT` 579 of 579 up to Twinlake (clouds not checked yet) | `intro_st/BLIT_ST.S` |
| intro | copper list, bitplane DMA, sprites | `Display_update`: reads the copper list and registers, converts the picture into ST format, draws the pointer | see below | `intro_st/SHOW_ST.S` |
| intro | the four-plane scenes (space, Twinlake, meteors): Thalion's two Amiga screens, written by the blitter and by Thalion's CPU code | target screens in ST format, shown directly (the Falcon's method, docs/11 7.8): the same K3 places as the Falcon ($4F4, $AD4 table; $294E, $1A42, $776, $B40, $169C, $12C0 our writers; $7BA, $994/$A36 Thalion's CPU code between fetch and bring; $6EE a reader; $24BE the base at once); blits redirected into the target | yes: `CHECK_TARGET` 0 differences through space, Twinlake and meteors (each writer against Thalion's way; the VBL compares the rows against unknown writers) | `intro_st/TARGET_ST.S`, `intro_st/INTRO_ST.S` |
| intro | the logo phase, the clouds and the menu (E30, docs/11 7.8b): Thalion's screens with five planes (logo, menu) or four (clouds), written by the blitter and Thalion's CPU code | target screens too, the Falcon's K3 places and names: $1E0, $D00, $FB2 table; $21E, $137E, $2646 (the stars in Thalion's VBL), $310, $DA2, $1270 our writers; $14E6 a scratch screen for Thalion's logo stages; $D74, $1030 Thalion's CPU code, then bring; $3C0, $AD4, $D00, $F4E the picture held while Thalion changes the screens' format. Plane 4 is not in the ST target: the logo's stars only in the target, with a list per screen; the menu's text laid over planes 0-3 | see the colours below | `intro_st/INTRO_ST.S`, `intro_st/TARGET_ST.S`, `intro_st/SHOW_ST.S` |
| intro | the four cloud blits a frame ($4E2A, $CA, from $E3A to $EB2) | `Clouds_draw` (K3 at $E3A, the Falcon's method of 2026-10-29): both clouds shifted once at program start into all 16 positions, in ST format, masked; put with the CPU (a group covered whole written, a free one skipped); `Clouds_column` copies whole groups from the menu picture converted once into ST format (`Menu_st`) | the same pixels in the rows the ST shows (Hatari against the old build; T99 passed); Thalion's rows 248-255 get no cloud, they are never shown | `intro_st/CLOUDS_ST.S`, `intro_st/INTRO_ST.S` |
| extro | the scroll text: five blits D = C ? B : A ($D8) a step, one per plane, then a blit moving the mask up a row ($450-$524) | `Text_scroll` (K3 at $450): screen = A xor (X and mask) for all four planes at once, A and X from the build; a line without text skipped unless it had text when that screen was drawn last; the mask in a ring, moved by a pointer (`Text_begin` $420, `Text_row` $534) | the same mask and choice per pixel; the colours as below | `extro_st/TEXT_ST.S` |
| extro | copper list, bitplane DMA; Thalion's two screens | three ST screens in turn; `Extro_after_copy` ($2EC) puts the picture in ST format into all, `Extro_switch_1/2` ($1E8, $596) set the base (the Falcon's places) | yes | `extro_st/EXTRO_ST.S` |
| extro | two VBL waits after each step ($43A-$449: `bsr $F54`, the closing text once) | `Step_wait` (K3 at $43A): wait until `STEP_VBL` VBL (the closing text one less) have passed since the last step, then Thalion's pause check | a fixed pace of 4 VBL a step (3), near the Amiga's work plus waits; chosen by the user against 3 | `extro_st/TEXT_ST.S` |
| fantasy, intro | lower border closed at line 200 of an ST | opened by Timer B (`Tb_border`, T93) | more lines visible | both layers |

**Precomputed (goal 2).** Fantasy intro, at build time
(`tools/fantasy_st_data.py`, from what `fantasy_auszug.py` extracted):
background, fairy and logo in ST format, the stars as compiled code, the
colour maps; the fairy's 16 preshifts at program start (1.15 MB from
`Malloc`). Intro: nothing at build time yet; the zoom converts its source
pictures once at run time (`Zoom_store`); the clouds are shifted at
program start (`Clouds_prepare`, 2 x 192 KB), the menu picture is
converted once per clouds scene (`Menu_st`, 39 KB). Extro, at build time
(`tools/extro_st_data.py`): per picture A and X = A xor B in ST format and
the 16 representatives (320 KB in `EXTROST.TOS`).

**What looks or behaves different from the Amiga.**

*Fantasy intro:*
- **16 colours a band instead of 32.** Two bands of 16 ST registers,
  split where Thalion's copper splits (Amiga row 134). Each register shows
  the fade of its representative Amiga colour (V3), so Thalion's fades
  work. Pixels in another colour than on the Amiga: fairy 7.6 %, logo
  9.7 %, stars 10.1 %, dust 5.6 %, background below row 134 5.3 %, above
  1.3 %. Visible: the tip of the Thalion "V" below row 134 is lighter
  (`$88E` becomes `$7CD`).
- **Picture position.** ST line 0 is Amiga row 22, so rows 0-21 are not
  shown; with the opened border the monitor shows about rows 22-252.
- **The fairy moves at 16.7 Hz, not 50 Hz.** On the Amiga the sprites
  follow every VBL; here she is drawn once a frame with the rest (open
  point in docs/05c).
- **About 0.5 s longer** before the flight (the preshift); the whole run
  1746 VBL instead of 1706.
- Plain ST: three bits a colour channel instead of four.

*Intro:*
- **16 colours.** Four-plane pictures as on the Amiga (register n =
  colour n). Five-plane pictures (logo, PRESENTS, menu): plane 4 goes into
  one register, in one colour. Logo phase: the stars (colour 16, white)
  only where planes 0-3 are 0, as on the Amiga; in register 1 while
  THALION shows (its colour 1, `$EED`, is on 8 pixels of the logo, which
  then show white), in register 13 while AMBERMOON shows (the logo leaves
  13 and 14 unused: nothing changes). Menu: the text in register 1, colour
  31 (white, as on the Amiga), everywhere; the highlight (colour 30, which
  Thalion cycles red to gold) is not shown yet, and register 1 (near
  white) loses its own colour there.
- **Picture position.** ST line 0 is raster line $2C, the Amiga's usual
  start; with the opened border lines down to about 230 show, so the
  lowest rows of the 256-row pictures (Lyramion, clouds, menu) are cut.
- **Copper colour changes** only where one falls on ST line 200 (the
  credits under the space scene); others are not shown.
- **Mouse pointer:** sprites 0 and 1 attached, as on the Amiga, but each
  pixel value v in the register whose shown colour is nearest to Amiga
  colour 16+v (no register is free in the menu): the sword's six shades
  (`222`-`ccb`) come out a little off (finding 248).
- **Target screens:** every scene is one (E30); the VBL converts
  nothing (`Converted` counts the fallback). The pointer (menu) is drawn
  into the target shown. Where Thalion changes the format of its screens
  (logo -> space, space -> meteors, any scene -> clouds, clouds -> menu)
  the picture shown is held until the next scene's table shows; the
  Amiga shows Thalion's copy meanwhile, made from the same picture.
  On a plain ST Twinlake's window shake cannot move the base by a line
  (no low base byte), so there the VBL converts during the shake.
  At the scene starts the VBL is held off for a few frames while the
  rows are brought into the target (`Screens_switch`).
- **No music:** no YM version of the intro music is known; Thalion's
  player is replaced by a table of `rts` (`Music_silent`).
- **Speed:** Twinlake runs at Thalion's pace (4 VBL a picture); the
  space scene mostly at 2 VBL a picture (4.0 on average, up to 9 in
  the big zooms), the meteors 6.6 on average; the
  clouds were slow (about 13.5 VBL a picture instead of 2, T97) and are
  drawn by our code since 2026-10-29 (T99 passed: fast and smooth).
  Numbers in docs/05c.
- **No drawing into the picture still shown** (`Target_free`,
  `TARGET_ST.S`, the Falcon's `Ziel_frei`): a new base takes effect at the
  next frame; when a frame of ours lasts longer than Thalion's wait, a
  blit, `Clouds_column` or `Clouds_draw` into that target waits for the
  VBL first. On the Amiga Thalion's frames never last that long.

*Extro:*
- **16 colours a picture instead of 32.** 16 representative Amiga
  colours per picture (the fairy's way, V3), chosen for the picture and
  its text colours alike; each register shows the fade of its
  representative, so Thalion's fades work. Small accents can lose their
  hue (the red cloak in the second picture turns brown). The text colour of a pixel
  is the register nearest to Thalion's brightened colour, and never the
  pixel's own register where Thalion's differs, so the text cannot vanish.
- **Picture position.** Rows 28-227 of 256 (S1, centred); the lower
  border stays closed.
- **No music:** no YM version of the extro music is known
  (`Music_silent`).
- **Speed:** the mixing takes about 1.1 VBL a step on the 8 MHz STE
  (Hatari) and varies with the text; `Step_wait` (K3 at $43A) waits for
  a fixed 4 VBL since the last step (the closing text 3) instead of
  Thalion's 2 VBL (1) after it. On the Amiga the blits add an estimated
  1.6-2.5 VBL, so 3 or 4 there; 2 was too fast to read, and of 3 and 4
  the user chose 4 (2026-10-30). The way back: Thalion's waits at $43A, then the pace
  varies with the mixing time.

**Going back (ST).** Extro: delete an entry in `HOOKS`
(`tools/extro_st_program.py`) and its routine; without `Text_scroll` the
K2 trap does no blit, so the text stays empty. Intro: delete an entry in `HOOKS`
(`tools/intro_st_program.py`) and its routine, and Thalion's code runs
there again (without `Zoom_st` the intro does not get past the logo).
Fantasy intro: call Thalion's `make_magic` and `make_funkel2` again in
`Fairy_flow` (`Blitter_wait` still draws their blits; the logo phase then
takes 5 VBL a frame instead of 3). The ST format and the drawing hooks
have no way back short of the Falcon's general Amiga layer, which is too
slow on the ST.

**Markers.** `DEVIATION (goals 1 and 2), docs/17-deviations.md D3` in the
files of the table (on the Falcon `fantasy/FEE_SUP.S` and
`fantasy/STARS_FALCON.S`) and in `tools/fantasy_st_data.py`,
`tools/intro_st_program.py`.

## D4: start menu (goals 1 and 2)

**What.** `HULL/STARTMENUE.S` is a menu of our own instead of Thalion's
menu in `Ambermoon_intro`, whose source is missing (goal 1): our font, a
black background, the x positions computed anew for our font. From
Thalion come only the four texts and their y positions;
`tools/intro_auszug.py` takes them from `Ambermoon_intro` at build time
(`build/intro_daten.i`, goal 2) and checks that the four expected texts
stand at hunk 1 $297.

It runs only when `ENGINE.TOS` is started alone with an empty command
line. Through the loader `AMBER.TOS`, Thalion's menu in the intro runs. In
both cases the choice goes through Thalion's `Intro_menu_choice`.

**Decided.** User, 2026-09-28: "plain, for now" (head of
`STARTMENUE.S`); the inventory of docs/11 (2026-09-29) refers to it.

**Where.** `tools/intro_auszug.py`, the head of `HULL/STARTMENUE.S`.

## D5: positions in Text.amb (goal 2)

**What.** In the German 1.20, `Text.amb` holds texts that the original
keeps in `AM2_CPU`. The file is read whole at run time (`Lade_texte` in
`HULL/WORDS_SUP.S`); only where `Race_names`, `Age_txt` and the like lie
inside it is fixed at build time (`tools/text_labels.py` →
`build/textmarken.i`, finding 250). `text_labels.py` checks the structure
of the file and stops when it does not add up; another language or
version means building again, as with the `AM2_CPU` extract. At run time
`Lade_texte` checks only the unpacked length (`TEXT_LAENGE`); if it
differs, `Textdaten` stays zero and every name is an empty text.

**Where.** `tools/text_labels.py`, `Lade_texte` in `HULL/WORDS_SUP.S`.

## D6: YM music (goals 1 and 2)

**What.** Big Alec's YM version of the music is not one of Thalion's game
files, and with it Big Alec's player runs instead of Thalion's: what
sounds is Big Alec's arrangement, not Thalion's data from `Music.amb`.
`tools/ym_extract.py` takes it at build time from the SNDH archive's
`big_alec/ambermon.snd` (`AMBER_YMSNDH` through `tools/paths.py`, by default `ambermon.snd` in
`ambermoon_gamedata/` next to the repository; until 2026-10-27
from the MSA image of the "Ambermoon Music Demo"). The block (Big Alec's
player and 18 songs, 241 630 bytes) is taken from the SNDH file with one
change: the 36 bytes that drive the player by Timer B are bound back to
Timer D, as on the demo disk, because Timer B is the ST's raster; every
place is checked, and the result is the tested demo block's first
241 630 bytes (SHA-256). At run time the game
loads `MUSIK_YM.BIN` and `MUSIK_YM.INF` (`ym_install` in `MUSIK_YM.S`);
`MUSIK_YM.INF` maps 14 of Thalion's 32 songs to YM songs, the others stay
silent (docs/13 3.2). Neither the SNDH file nor the block goes into the
repository or the delivery.

**Decided.** User, 2026-09-29 (docs/11 7.1: the YM songs may come along
but are not delivered). E4 (2026-10-10) only says that the STE plays the
YM like the ST.

**Where.** `tools/ym_extract.py`, `engine/src/HULL/MUSIK_YM.S`
(`ym_install`), `tools/musik_ym.inf`; the call in the build scripts.

**Going back.** Without the SNDH file the build goes on and the YM stays
silent; the Falcon then plays Thalion's songs from `Music.amb` through the
mixer (DSP or CPU), the ST has no music.

## D7: text, items and buttons of Thalion's disks (goal 2)

**What.** Thalion's 1.01 and 1.07 keep the texts, the item table and the
button graphics inside `AM2_CPU`; 1.2x has them as `Text.amb`, `Objects.amb`,
`Button_graphics`. For 1.0x the build makes these three files from `AM2_CPU`
(and copies `Dict.amb`, `Monster_char.amb` and the save games from `Initial/`
under the 1.2x names) and delivers them; the engine reads them as for 1.2x.

**Why.** One engine for all versions, no second way of loading.

**Decided.** User, 2026-11-02: "das leitziel bezog sich vor allem auf die
verfügbaren sourcen, die es bei am2_cpu nicht gibt".

**Where.** `tools/thalion_prepare.py`, `tools/build_common.sh`.

**Going back.** Read them from `AM2_CPU` at run time; the places are those of
`tools/am2cpu_old.py`.

## D8: the column loop of opaque walls (goal 1)

**What.** Thalion's `put_dpoly` from `AM2_CPU` keeps its near plane,
projection, edge list and clipping in x. At its `tst.w seethru_flag` the build
writes `jmp Wall_columns` (same length, `EINGRIFFE` in `tools/am2cpu_code.py`,
which stops if another instruction is there). `Wall_columns` draws opaque
walls: the columns sharing a longword of the buffer are gathered in a column of
our own, and each row is written once, where Thalion does two read-modify-writes
per point. Since 2026-11-08 two neighbouring columns go through the gather loop
together and write that column once a row for both (docs/05c (A)). See-through
walls go on in Thalion's loop. `3D_MAP.S` is untouched.
The same code runs on Falcon and ST, with no machine switch.

**Why.** The wall loop is the largest item of a 3D frame on the ST, 107 cycles a
point (docs/05c, 3D profile). One code base for both machines was the user's
condition.

**Decided.** User, 2026-11-02: "los, dinge, die sinnvoll sind und eine Codebasis
erlauben, bitte auch für falcon 3d umsetzen und dich mit falcon tempo abstimmen.
damit wartbarkeit beider versionen einfacher bleibt". Before it, on goal 1: "das
leitziel bezog sich vor allem auf die verfügbaren sourcen, die es bei am2_cpu
nicht gibt". Thalion's loop is library code without source.

**Same picture.** `VASM_EXTRA="-DWALLCHECK=1"` draws every wall both ways and
compares the buffer with a row of margin on either side, then runs
`WALLCHECK_RANDOM` invented walls through the whole of `put_dpoly`. The counters
are `wchk_walls` and `wchk_bad`. Results in docs/05c, section "Wall loop".

**Tested.** T102 (a)-(c) passed on the STE and the Falcon (user, 2026-11-05: "sieht
alles gleich aus, ggf. ein vbl besser. bei beiden systemen").

**Where.** `engine/src/HULL/D3_WALLS.S`, the table `EINGRIFFE` in
`tools/am2cpu_code.py` (with its adaptation in `tools/am2cpu_places.py`), the
include in `engine/engine.s`.

**Going back.** `VASM_EXTRA="-DWALLS_THALION=1"` takes Thalion's loop in one
build; it stays in the program for that. For good: delete `EINGRIFFE` and the two
`put_dpoly_*` entries in `tools/am2cpu_code.py`, and the file and its include.

## D10: coarse walls while the view moves (goal 1)

**What.** While the player turns, walks or the camera height changes,
`Wall_columns` (D8) draws opaque walls in pairs of columns: columns 2k and
2k+1 of the 3D buffer, when both belong to the wall, both get the texel of
the left one, and the right one is skipped (no texel, no steps). Its rows are
those of the left one, so an edge steps in two points. A column at the end of
a wall without its partner stays single. See-through walls, objects, floor and
sky stay as they are. In the first frame in which the view no longer changes,
the picture is Thalion's again, point for point (D8).

To know that a new frame begins, `D3_frame` has to run once a frame, before the
walls. `wc_bind` makes that so at run time, the first time a wall is drawn:
the first instruction of Thalion's `Draw_dungeon` (`clr.w dface_anz`, 6 bytes)
becomes `jmp D3_frame`, and `D3_frame` does that `clr` itself and goes on behind
it. It checks the instruction first; if it is not what Thalion's source says,
nothing changes and the walls stay full (`wc_hooked` stays 0). Thalion's file
`3D_MAP.S` stays unchanged; the change is in memory only. (The call in
`M3_DisUpd` cannot be bent: vasm made it a `bsr.w`, and `D3_frame` lies out of
its reach.)

**Why.** Walls are about half of a 3D frame on the ST; with D8 the same
picture costs 87-95 cycles a point, and there is not much more in it
(docs/05c). Pairs cost about a third less in the wall loop. Measured in Hatari
(STE, 8 MHz), the same standing frames once full and once coarse
(`COARSE_ALWAYS`, a measuring switch): Keller 10.75 → 9.71 VBL a frame,
Spannenberg 10.99 → 9.09.

**Decided.** User, 2026-11-04, on the proposal to draw walls in double
width only while moving, as a switch: "2 als schalter"; on a renderer of our
own: "3 ja, jedoch abweichungen in docs vermerken". After T102 (d), 2026-11-05
(typed in the Falcon Tempo session, relayed): "T102CR funktioniert. ich würde das feature drin lassen. aber per default ausschalten und dann in amber.in als schalter einbauen". So it stays, off by default,
switched in `AMBER.INF`.

**The switch.** The byte `Coarse_walls` in `D3_WALLS.S`: 0 off (the default,
Thalion's picture always), `$FF` on. `VASM_EXTRA="-DCOARSE_WALLS=1"` builds it
on. The key `COARSE_WALLS=YES` in `AMBER.INF` is a wish to main (docs/05c). With the switch
off, `wc_bind` changes nothing in Thalion's code. The first frame of a 3D map (the one
Thalion's `M3_DisInit` draws, with `NPCs_off` set) is always full, even if the
view differs from the map before (finding of the user, 2026-11-06; T103 passed the same day).

**Checked.** `VASM_EXTRA="-DWALLCHECK=1 -DWALLCHECK_COARSE=1"` draws every
wall Thalion's way and coarse, and asks: is every point but the right columns
of pairs Thalion's (`wchk_bad`), and in every row where a pair changed, is the
right point the left one (`wchk_pairbad`)? Results in docs/05c. On the
hardware: T102 (d) passed (user, 2026-11-05).

**Where.** `engine/src/HULL/D3_WALLS.S`: `wall_coarse` and what follows it,
`D3_frame`, `wc_bind`; the include in `engine/engine.s`.

**Going back.** Switch off: no coarse frame, no change in memory. For good:
delete `wall_coarse` up to `wc_pairs_left`, `D3_frame`, `wc_bind`, the branch
to `wall_coarse` and the call of `wc_bind` in `Wall_columns`, and the `\4` of
`WC_COLUMN`.

## D11: Timer capped, against a bug of the original (goal 1)

**What.** `Bibliothek_vbl` caps Thalion's long `Timer` at `TIMER_CAP`
($1000) right after `VblQ_handler`. Nothing else changes: below the cap the
counter runs as before, and no register is touched.

**Why.** Thalion's `Make_2D_move` (`MAP/2D_MAP.S`) asks whether a step is
due with a word compare of a long counter:

```
move.l  Timer,d2
move.w  #M2_movement_speed,d3   ; 8
sub.w   Time_warp,d3
cmp.w   d3,d2
bmi.s   .Exit
```

On the 2D map the VBL queue (`Map2D_VblQ`, `Time_2D`) counts `Timer` up in
every frame, and only a step clears it (`clr.l Timer`, line 851). After
32768 frames of standing still the low word is negative, `bmi` is taken
every time, and no move is accepted: no left click on the map, no arrow
icon, no cursor key. The mouse, the animations and the other clicks go on.
It lasts until the low word wraps again, another 32768 frames. At VGA
(60 Hz) it begins after 9:06 minutes, at RGB (50 Hz) after 10:55. Reported
by the user on the Falcon, 2026-11-06.

It is Thalion's bug, not ours: `AM2_CPU` 1.07 en has the same `cmp.w` at
0:$E2BC, and its VBL calls the queue in every frame (0:$2127A); the 1.2x
source has it too. Finding 275.

**Why $1000.** Any value from `M2_movement_speed` (8) up acts the same in
2D. 3D clears `Timer` in every frame (`M3_DisUpd`, line 639) and clips it at
`Max_3D_VBLs` (13) itself. No other code reads `Timer`. $1000 keeps the
compare positive and is far above both.

**Decided.** User, 2026-11-06, on the proposal to cap `Timer` in the
library: "bitte umsetzen".

**Checked.** Passed on the Falcon (user, 2026-11-06: "test bestanden"):
standing still on a 2D map for more than 11 minutes, then walking with the
mouse, an arrow icon and the cursor keys.

**Where.** `engine/src/HULL/LIBRARY.S`: `TIMER_CAP` and the four lines
behind `jsr VblQ_handler` in `Bibliothek_vbl`.

**Going back.** Delete those four lines and `TIMER_CAP`; then the 2D map
stops again after 9–11 minutes of standing still, as on the Amiga.

## D12: the horizontal scaling of enlarged 3D objects (goal 1)

**What.** Thalion's `draw_zoomshape` from `AM2_CPU` draws an object of the 3D
view. When the object is taller on the screen than in its graphic, it first
scales each source row across into `zoom_screen`, then makes a mask and copies
the rows down into the 3D buffer. For the first step only, the build writes
`jmp Zoom_columns` over its first instruction (`move.w <source height>,d5`, the
same length; `EINGRIFFE` in `tools/am2cpu_code.py`, which stops if another
instruction is there). `Zoom_columns` comes back behind Thalion's call of the
step (`draw_zoomshape_hdone`), and Thalion makes the mask and copies.
Clipping, the step tables, shrunk objects, the mask and the copy stay
Thalion's. The same code runs on Falcon and ST, with no machine switch.

`Zoom_columns` cuts the columns of each longword into segments: neighbouring
columns that take the same source point (enlarged) or the next one (about
1:1). Per row a segment costs one or two fetches, shifts and masks and one
write, where Thalion does two read-modify-writes per point. Bits of a longword
outside the object's columns become 0 where Thalion leaves what was there; the
mask and the copy never take them (Thalion's edge masks).

**Why.** With an object close by this step was the largest item of a 3D frame
on the ST: 0.5 M cycles at 99 a point (docs/05c, "Objects in 3D"). Objects
close by are about 1:1 across: Grandfather's cellar, a pillar one square ahead,
63 columns from 63 source columns. Hatari STE, standing, VBL per frame:

| Scene (docs/05c) | Thalion | D12 | the step itself |
|---|---|---|---|
| A, a pillar close by | 15.15 | 12.20 | 499 k → 54 k |
| B, a pillar close by | 14.08 | 11.11 | 493 k → 54 k |
| C, a pillar close by | 14.29 | 11.11 | 502 k → 54 k |
| the well | 10.99 | 10.10 | 208 k → 106 k |
| objects at middle distance | 11.76 | 11.11 | 69 k → 21 k |

**Decided.** User, 2026-11-07, after the profile: "ja, los mit dem Umbau".
Like D8, on goal 1 and `AM2_CPU` (user, 2026-11-02): "das leitziel bezog sich
vor allem auf die verfügbaren sourcen, die es bei am2_cpu nicht gibt".

**Same picture.** `VASM_EXTRA="-DZOOMCHECK=1"` runs both for every enlarged
object: Thalion's step into `zoom_screen`, kept; ours over a pattern; then the
object's points compared (its columns, its source rows; what the mask and the
copy take). Before the first object `ZOOMCHECK_RANDOM` (5000) invented objects
go through Thalion's whole `draw_zoomshape`: source width 16-128, height
4-120, taller on the screen by 1-256 rows, width 1-256, random place, mask
on or off, random clip window. Counters `zchk_objects`, `zchk_bad`, the first
difference in `zchk_first`. Results in docs/05c, section "Objects in 3D".

**Tested.** T106 passed (user, 2026-11-07: "T106 funktioniert"; machines not
named): `T106ST.TOS` and `T106F.TOS`, release builds of 2fdf451.

**Where.** `engine/src/HULL/D3_WALLS.S` (`Zoom_columns`, `zoom_ours`,
`Zoom_check`), the tables `EINGRIFFE` and `EINSPRUENGE` in
`tools/am2cpu_code.py` (`draw_zoomshape_hscale`, `draw_zoomshape_hdone`).

**Going back.** `VASM_EXTRA="-DZOOM_THALION=1"` takes Thalion's step in one
build; it stays in the program for that. For good: delete the `EINGRIFFE`
entry for `Zoom_columns`, the two `draw_zoomshape_*` entries in `EINSPRUENGE`
and the part "Enlarged objects" of `D3_WALLS.S`.

## D13: rotation of the point grid and sort of the faces (goal 1)

**What.** Two routines of Thalion's source file `3D_MAP.S`, which is goal 1
proper (not `AM2_CPU`), run as ours:

- `rotate_y`, called once a frame by `Rotate_points`, turns the point grid of
  the view (up to 16 × 16 points, `patt_size` apart) by `Y_angle`, with four
  `muls` per point. Our `Rotate_grid` takes the products of the first point
  as Thalion does and then adds per point and per row: the products of
  neighbouring grid points differ by `patt_size` × sin or cos, the sums are
  exact integers, so after Thalion's `asl.l #2` and `swap` every word is
  Thalion's. The offsets (`xoffset`, `zoffset`, cleared by `Rotate_points`)
  go into the high word, the same word arithmetic.
- `Quicksort`, called once a frame by `Draw_dungeon`, sorts `wall_list0`
  (faces and objects by depth). Thalion's limit for the quicksort part is the
  whole list ("immer bubblesort"), so it always sorts by insertion:
  ascending by the signed long in front of each 8-byte entry, stable. The
  list comes mostly in falling order, the slow case. Our `Sort_faces` is a
  merge sort, stable as well, so the order is the same, equal keys included.

Thalion's file stays unchanged. `Geo_bind` turns the first six bytes of
`rotate_y` and of `Quicksort` into `jmp` to ours, at run time, the first time
a wall is drawn (from `Draw_faces`, so the change counts from the next
frame); only if the bytes are what Thalion's source assembles to there, else
Thalion's routines stay (`geo_hooked`: bit 0 rotation, bit 1 sort). Each of
ours does the six bytes it covers itself where it hands back to Thalion's:
another caller (a0 ≠ a1, a count that is not the grid; entries not 8 bytes
or more than 200) gets Thalion's routine. The same code runs on Falcon and
ST, with no machine switch.

**Why.** Speed in 3D on the ST, the next step after D12 (docs/05c, "Speed in
3D, step 0"). Hatari STE, standing, cycles per frame:

| | Thalion | D13 |
|---|---|---|
| sort (`qsb_*` / `sf_*`), about 48 entries, about 630 shifts | 75 k | 37 k |
| rotation of the grid | 30 k | 9 k |
| scene A, VBL per frame | 12.20 | 11.90 |
| scene B, VBL per frame | 11.11 | 10.87 |
| scene D, VBL per frame | 9.62 | 9.62 (Hatari counts whole VBL) |

**Decided.** User, 2026-11-07: "wir gehen mal alles an. abweichung von
leitziel 1 ist hier ok", then "ja, beide Rechner" and "ja, los mit 2a + 2b".

**Same results.** `VASM_EXTRA="-DGEOMCHECK=1"` runs both for every call:
Thalion's on a copy of the input, kept; ours; then the output compared,
every word of the grid, every byte of the list. Before the first call
`GEOMCHECK_ROT` (2000) invented grids (1-16 × 1-16 points, any place within
±8192, any angle word, offsets now and then) and `GEOMCHECK_SORT` (300)
invented lists (2-200 entries; keys with many equal ones, any signed long,
falling with bumps, rising in small steps; the second long is the entry's
number, so a change in the order of equal keys shows). Counters
`geo_rot_calls`, `geo_rot_fast`, `geo_rot_bad`, `geo_sort_calls`,
`geo_sort_bad`, the first difference in `geo_first`. Results in docs/05c.

**Tested.** T107 passed (user, 2026-11-07: "t107 sieht gut aus"), release
builds of 5f3da3e on the STE and the Falcon, 1.07 en.

**Where.** `engine/src/HULL/D3_WALLS.S`, the part "The geometry of a 3D frame"
(`Geo_bind`, `Rotate_grid`, `Sort_faces`, `Rotate_check`, `Sort_check`) and
the call of `Geo_bind` at the head of `Wall_columns`.

**Going back.** `VASM_EXTRA="-DGEOM_THALION=1"` binds nothing, Thalion's two
routines run. For good: delete the call at the head of `Wall_columns` and the
part "The geometry of a 3D frame" of `D3_WALLS.S`.

**Open.** Like `wc_bind` (D10), `Geo_bind` writes code without flushing the
instruction cache. Thalion's two routines ran earlier in the same frame, and
by their next call a 68030 has long dropped them from its 256 bytes; on a
68060 (CT60) the cache is 8 KB. Part of the cache point deferred until the whole CT60 adaptation
(docs/05c).

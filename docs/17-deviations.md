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
grep -rn "DEVIATION (goal" engine tools lader intro extro fantasy amiga musik fantasy_st intro_st
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
| D2 | 1, 2 | Library data, pure memory routines and the music player (operands bent onto shadow registers) of `AM2_CPU` taken at build time; `AM2_CPU` is never read at run time | both | user, 2026-09-27/28 | `tools/am2cpu_auszug.py`, `am2cpu_code.py`, `am2cpu_lesen.py`, `engine/engine.s`; open: 3D and music session |
| D3 | 1, 2 | Intro, extro, fantasy intro: Thalion's programs taken apart at build time and bent (K1, K2), own routines at the bottlenecks (K3, `Fee_ablauf`); the ST builds both intros itself (below) | both | user, 2026-09-29 and 2026-10-04; ST 2026-10-22/24 | Falcon: open (Falcon Tempo); ST: `fantasy_st/`, `intro_st/`, `tools/fantasy_st_data.py`, `tools/intro_st_program.py` |
| D4 | 1, 2 | Our own start menu for `ENGINE.TOS` started alone; its four texts from `Ambermoon_intro` at build time | both | user, 2026-09-28 ("plain, for now") | `tools/intro_auszug.py`, `HULL/STARTMENUE.S` |
| D5 | 2 | Positions of the library's texts inside `Text.amb` fixed at build time | both | finding 250 | `tools/textmarken.py`, `HULL/WORDS_SUP.S` |
| D6 | 1, 2 | YM music from Big Alec's SNDH file (`big_alec/ambermon.snd`, until 2026-10-27 the "Ambermoon Music Demo" disk), extracted at build time; Big Alec's player instead of Thalion's | ST, Falcon with `YM` | user, 2026-09-29 (docs/11 7.1) | open (music session) |

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
in registers of their own). The review sheet (`st_palettes.py sheet`)
shows every palette whose pictures are counted under each method, with a
button to choose it, and writes the method lines for the file; every ST
build writes it (`build/st_palettes/index.html`). T99 passed.

**Why.** Speed and look. `St_bauen` costs about one second on 8 MHz for
every new palette: at every map change, every combat, every event picture.
And the result could not be corrected by hand: some palettes look wrong on
the ST (tactic field too bright, world map too colourless, docs/05). The
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
- `tools/st_palettes.py`, `tools/st_palettes.txt`, `tools/build_st.sh`.

**Going back.** Remove the `STPAL.DAT` line from `tools/build_st.sh` (and
the file from the Atari): the engine falls back to `St_bauen` for every
palette. Corrections in `tools/st_palettes.txt` are then lost.

## D2: AM2_CPU at build time (goals 1 and 2)

**What.** `AM2_CPU` is Thalion's library, not released as source. The
build extracts its data (`Main_pal`, `Tactic_pal`, `Automap_pal`, window
icons, `Status_*`, `Button_up`/`Button_down`, `World_data`, font, mouse
pointers, tables; `tools/am2cpu_auszug.py` → `build/am2cpu_daten.i`) and
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
`tools/am2cpu_lesen.py` (`STUECKE`, `NAMEN`). Another game version means
building again.

**Why.** Library data that Thalion's code expects at fixed names; code
that only works in memory is Thalion's own and better than a rewrite. The
user ruled that this is not a copy (CLAUDE.md, goal 1).

**Where.** `tools/am2cpu_auszug.py`, `tools/am2cpu_code.py`,
`tools/am2cpu_lesen.py`, the INCLUDE lines in `engine/engine.s`.

**Going back.** docs/02 A7; CLAUDE.md "Daten".

## D3: intro, extro, fantasy intro (goals 1 and 2)

**What.** The three non-interactive programs are Amiga programs; two have
no source. They run on an emulation of the Amiga hardware they touch
(docs/entwickler/10-amiga-layer.md), and Thalion's code in them is taken
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
  instructions becomes `jmp` into our routine. Today seven places: the
  intro's zoom (`intro/INTRO_ZOOM.S`), the picture switch, clearing before
  the zoom and the end of Thalion's VBL (`intro/INTRO_SUP.S`); the copy
  into both screens and the picture switch twice (`extro/EXTRO_SUP.S`).
  Table in docs/entwickler/10.
- *Rewritten*: Thalion's main sequence of the fantasy intro (hunk 1
  $110-$2B0, tied to copper, CIA and DMA) is `Fee_ablauf` in
  `fantasy/FEE_SUP.S`, in Thalion's order and with Thalion's values.
- *Atari format*: the extro's two screens lie in Falcon format and are
  shown directly (`amiga/AMIGA_ZIEL.S`).

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

**Where.** docs/11 (sections 3-7), docs/entwickler/10-amiga-layer.md; the
files named above.

### D3 on the ST: what is changed, and what looks different

*State 2026-10-27: the fantasy intro passed T94 on the STE; the intro
passed T96a, and the intro without live conversion (every scene a target
screen) is built for T97.* The ST builds both programs itself, in its own
files, independent of the Falcon's `fantasy/`, `intro/` and `amiga/`; only
the emergency exit `amiga/AMIGA_NOTAUS.S` is shared, unchanged. Details
and measurements: docs/05c-ST.md ("ST fairy intro, plan", "ST intro").

**Taken unchanged.** Thalion's `FAIRY.S` (flight path, fairy animation in
`level3`, sparks, the stars' logic, random numbers, the 3-VBL frame);
Thalion's hunk-1 fades and tables of `Fantasy_intro`
(`tools/fantasy_auszug.py`, as on the Falcon). All seven hunks of
`Ambermoon_intro`, with K1 and K2 exactly as on the Falcon
(`tools/intro_st_program.py` calls the functions of
`tools/amiga_programm.py`): every scene, text, timing and the start menu
are Thalion's code.

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
| both | lower border closed at line 200 of an ST | opened by Timer B (`Tb_border`, T93) | more lines visible | both layers |

**Precomputed (goal 2).** Fantasy intro, at build time
(`tools/fantasy_st_data.py`, from what `fantasy_auszug.py` extracted):
background, fairy and logo in ST format, the stars as compiled code, the
colour maps; the fairy's 16 preshifts at program start (1.15 MB from
`Malloc`). Intro: nothing at build time yet; the zoom converts its source
pictures once at run time (`Zoom_store`); the clouds are shifted at
program start (`Clouds_prepare`, 2 x 192 KB), the menu picture is
converted once per clouds scene (`Menu_st`, 39 KB).

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

**Going back (ST).** Intro: delete an entry in `HOOKS`
(`tools/intro_st_program.py`) and its routine, and Thalion's code runs
there again (without `Zoom_st` the intro does not get past the logo).
Fantasy intro: call Thalion's `make_magic` and `make_funkel2` again in
`Fairy_flow` (`Blitter_wait` still draws their blits; the logo phase then
takes 5 VBL a frame instead of 3). The ST format and the drawing hooks
have no way back short of the Falcon's general Amiga layer, which is too
slow on the ST.

**Markers.** `DEVIATION (goals 1 and 2), docs/17-deviations.md D3` in the
files of the table and in `tools/fantasy_st_data.py`,
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
inside it is fixed at build time (`tools/textmarken.py` →
`build/textmarken.i`, finding 250). `textmarken.py` checks the structure
of the file and stops when it does not add up; another language or
version means building again, as with the `AM2_CPU` extract. At run time
`Lade_texte` checks only the unpacked length (`TEXT_LAENGE`); if it
differs, `Textdaten` stays zero and every name is an empty text.

**Where.** `tools/textmarken.py`, `Lade_texte` in `HULL/WORDS_SUP.S`.

## D6: YM music (goals 1 and 2)

**What.** Big Alec's YM version of the music is not one of Thalion's game
files, and with it Big Alec's player runs instead of Thalion's: what
sounds is Big Alec's arrangement, not Thalion's data from `Music.amb`.
`tools/ym_auszug.py` takes it at build time from the SNDH archive's
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

**Where.** `tools/ym_auszug.py`, `engine/src/HULL/MUSIK_YM.S`
(`ym_install`), `tools/musik_ym.inf`; the call in the build scripts.

**Going back.** Without the SNDH file the build goes on and the YM stays
silent; the Falcon then plays Thalion's songs from `Music.amb` through the
mixer (DSP or CPU), the ST has no music.

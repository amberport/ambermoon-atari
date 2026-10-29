# 5. Our layer, file by file

All of it is in `engine/`, except `vorspann.i` (chapter 4). Unless a line
says otherwise, a file is part of both builds. The routines each file
offers to Thalion's code are listed in appendix B.

## The frame

| File | What it does |
|---|---|
| `engine/engine.s` | the library unit: includes Thalion's `HULL/` files, our files and the generated `build/*.i` in a fixed order; the two screens and a few absolute variables |
| `engine/spiel.s` | the game unit: includes Thalion's game files; `ACTIONS.S` inside `opt t-` (appendix A) |
| `src/MAIN.S` | `start`, `Restart_game`, `Main_loop`, `Exit_program`, `Notausgang` (chapter 3). Not Thalion's `MAIN.S`, which is in the game unit |
| `src/FALCON_OFF.S` | our constants, the `a5` variable block, the `Gemdos`/`Bios`/`Xbios` macros, a cross-check against Thalion's symbols at its end |
| `shared/SETTINGS.S` | the reader of `AMBER.INF`, one module for the game, the intros and the loader: no `SECTION` of its own, pure 68000, GEMDOS only. `Settings_read` fills `Settings_music` and `Settings_plain_st`, `Settings_text` writes the line shown at start. A new setting is one entry in `set_table` and one result byte. `engine.s` includes it after `MAIN.S`; `Einstellungen_lesen` reads the file once, before `Open_screen` and `Musik_install` |

## Drawing, screens, mouse

| File | What it does |
|---|---|
| `HULL/LIBRARY.S` | the core, with Thalion's names and contracts and the part both machines share. The block routines (`Put_unmasked_block`, `Put_masked_block`/`2`/`8`, `Put_masked_icon`, `Put_masked_silhouette`, `Get_block`), `Draw_box` and lines, the double buffer (`Update_screen`, `Switch_screens`, `Copy_screen`, `Duplicate_block`), the mouse pointer drawn into the picture, the colour-bank routines (`Farbbank`, `Farbbank_spanne`), `Bibliothek_vbl`, mouse interrupt and `Maus_vbl`. The machine parts are in `FALCON_LIB.S` and `ST_LIB.S` |
| `HULL/FALCON_LIB.S` | Falcon build only, owner Falcon Tempo: what knows colour banks and eight planes. `Pub_zeilen` (Thalion's format into eight planes, bank per span, the whole-tile path), `Box_fuellen`, `Quelle_aufweiten`, `Zeilenfarbe` (the colour of a pixel in a given line), `Get_block_orig` (saving in Thalion's format), `Masked_icon` (`Put_masked_icon`), the tile cache `Kachel_holen` (456 KB), the R_range afterwork `Bloecke_nacharbeiten`, `Zeichen_nacharbeiten`, `Pointer_convert`, the palettes into the colour banks (`Platz_setzen`, `Bank0_setzen`, `Bank_setzen`, `Palette_anfang`), the colours of `Drugged_FX` (`Drogen_setzen`, `Drogen_farben`), and the empty hooks `Unmasked_icon`, `Pm2_schnell`, `Zeiger_bild`. Each is called from its routine in a shared file; `ST_LIB.S` has the same names (table below) |
| `HULL/RASTER.S` | the raster list, our copper: it translates Thalion's raster list once (`Raster_liste_setzen`), so the VBL only writes registers (which bank applies in which line is `Farbbank`/`Farbbank_spanne` in `LIBRARY.S`), the gradient slots for `R_range` (`Bereich_tabelle`, `Zeilenersatz`, `Bereich_nacharbeiten`, `Bereich_rueck`), `Amiga_nach_videl`, the VBL hook `Raster_vbl`. Also holds an unused Timer B variant for the Falcon (`RASTER_ZEIT`, see `FALCON_OFF.S`) |
| `HULL/FADE_SUP.S` | below Thalion's `HULL/FADE.S`: `Set_fade` (set or fade the palettes of a line range), `Wait_4_fade`, `My_vsync`, the table place → bank `Platzbank`, `Vid_stufe` (Amiga 4-bit to Videl 6-bit); the palette itself goes to the machine part (`Platz_setzen`) |
| `HULL/FALCON.S` | the Falcon hardware: supervisor mode, `Open_screen` (Videl mode inherited from the desktop, except that on RGB it always sets `MD_PAL`, because Thalion counts VBLs for 50 Hz and a 60 Hz desktop ran the game a fifth too fast; VGA keeps its mode; own screen memory, old palette saved), `Close_screen` |
| `HULL/AREAS.S` | the three area stacks Thalion uses: print area (`PA`), mouse area (`MA`), mouse pointer (`Mptr`); `Push_*`, `Pop_*`, `Change_Mptr` |
| `HULL/EFFECTS_SUP.S` | below Thalion's `HULL/EFFECTS.S`: `Get_pixel`, the scratch buffer, the clip-area stack (`Push_CA`, `Pop_CA`) |
| `HULL/CONTROLS_SUP.S` | the button graphics for Thalion's `HULL/CONTROLS.S`, loaded from the game file `Button_graphics` |

### The shared part and the machine parts

`LIBRARY.S` holds Thalion's names, their contracts and the part both
machines share; "shared" code works through the constants `PLANES`,
`TROW`, `SCRROW`. Where a machine differs, `LIBRARY.S` calls a routine
with a neutral name that both machine parts define: `FALCON_LIB.S`
(colour banks, eight planes) and `ST_LIB.S` (the colour table, four
planes). `engine.s` includes one of them: `FALCON_LIB.S` right behind
`LIBRARY.S`, so the two reach each other with `bsr`; `ST_LIB.S` further
down. What only one machine has gets an empty twin on the other.

In main's files `ZIEL_ST` is asked in two places only: the switch block
of `vorspann.i` (`Schirm_ebenen`, `SCHIRM_RAND`, `MACHINE_NAME`, the
memory hooks) and the two include places of `engine.s`. The files of
Falcon Tempo (`RASTER.S`, `D3_SUP.S`, `COMBAT_SUP.S`, `MUSIK_SUP.S`)
still branch with `IFD ZIEL_ST` themselves.

| Called from `LIBRARY.S` (or another shared file) | Falcon (`FALCON_LIB.S`) | ST (`ST_LIB.S`) |
|---|---|---|
| `Pub_zeilen`: the lines of `Put_unmasked_block` for a source in Thalion's format; clipping, side clamp, addresses and `pub_schlicht` (source in screen format) stay shared | eight planes, bank per span, the whole-tile path through `Kachel_holen` (456 KB) | through the colour table; the ST's own tile cache `St_kachel` |
| `Unmasked_icon`, a fast path at the start of `Put_unmasked_icon` | empty: back to `pui_allgemein` | the ST's fast path |
| `Pm2_schnell`, a fast path in `Put_masked_block2` | empty (C set: go on) | one block on a block border |
| `Quelle_aufweiten`, the source of a masked graphic into a buffer (`Put_masked_block`/`2`) | the colour per line, bank across a border | through the colour table |
| `Masked_icon`: all of `Put_masked_icon` | tile path and line path | the ST's version |
| `Get_block_orig`: `Get_block` into Thalion's format (into screen format stays shared) | the lower `d5` planes | the way back through the table |
| `Box_fuellen`: the fill of `Draw_box`, `Draw_hline`, `Draw_vline`, `Plot_pixel` (corners, clamping, address stay shared) | bank per span | through the colour table |
| `Zeilenfarbe`: one colour of Thalion's in a given line, for `Put_char`, `Put_masked_silhouette` and the rest | bank of the line | register from the table |
| `Bloecke_nacharbeiten`, `Zeichen_nacharbeiten`; `Bereich_nacharbeiten`, `Bereich_rueck`, `Bereiche_sammeln`, `Bereiche_schritt` (in `RASTER.S`) | the R_range gradient slots | empty; `Bereiche_sammeln` gives `d0` = 0 |
| `Platz_rueck` (in `RASTER.S`), for `Get_pixel` | slot back to Thalion's colour | the ST's way back |
| `Drogen_setzen`, `Drogen_farben`, from `Bibliothek_vbl` | the colours of Thalion's `Drugged_FX`, written in the top border (tested on the hardware 2026-10-23) | empty |
| `Zeiger_bild`, in `Zeiger_in_puffer` (also in the VBL) | empty | per line the pointer image of its range, made in advance by `St_zeiger_bilder` |
| `Pointer_convert`, in `Set_mouse_ptr` (`AREAS.S`) | the pointer to eight planes | the ST's conversion |
| `Platz_setzen`, `Bank0_setzen`, `Palette_anfang`, from `Set_fade` | one palette into its bank (`Bank_setzen`: Amiga colour words to Videl values) | the palette into `Bank_ist`, the registers computed from there |

Also shared, with a small machine switch:

- `Farbbank`, `Farbbank_spanne`, `Rasterbank`, `Rasterbank_spanne`,
  `Zeichenliste` stay in `LIBRARY.S`: both builds call them (pointer,
  `Zeigertakt_balken`, `D3_SUP.S`, `COMBAT_SUP.S`). On the ST the bank
  reaches no plane, because `PLANES` < `Data_depth`.
- `Basis_setzen` writes the low video base byte only with `Feinbasis`, a
  byte in `LIBRARY.S`: set for the Falcon, set or cleared by `ST.S` in
  `Open_screen` (cleared on a plain ST).
- `MEMORY.S`: the ST's recoloured copies of the 3D graphics (user, 2026-10-10) hang on
  three macros from `vorspann.i`, `MEM_ADDRESS` in `Claim_pointer`,
  `MEM_FREE_HOOK` in `Free_memory` and `Invalidate_memory`,
  `MEM_KILL_HOOK` in `Kill_unclaimed_memory`. On the Falcon they are
  empty (`MEM_ADDRESS` is a plain `move.l MEM_ADR(a0),d0`), so
  `Claim_pointer` pays nothing.
- `Data_change_count` (`MEMORY.S`) counts on both machines in
  `Allocate_memory`, `Eintrag_lesen`, `Datei_lesen` and `Decompress`; only
  the ST's tile cache reads it.
- `Vid_stufe` stays in `FADE_SUP.S`, because `RASTER.S` assembles
  `Amiga_nach_videl` on both machines.
- `ST_LIB.S` uses some `LIBRARY.S` data: `bl_links`, `bl_rechts`,
  `bl_anzahl` (clipping) and `pmo_puffer`/`PMO_MAX`.

The split came in three cuts (2026-10-21 to 10-24), each proven by
comparing every routine's instructions before and after, and each tested
on the Falcon and the STE.

## Memory, files, save games

| File | What it does |
|---|---|
| `HULL/MEMORY.S` | the memory manager with Thalion's handles: `Allocate_*`, `Claim_pointer`, `Free_pointer`, `Free_memory`, `Kill_memory`, claim counters as in the original (they drive Thalion's `Out_of_memory`) |
| `HULL/FILES_SUP.S` | Leitziel 2: `Load_subfile`, `Load_file`, `Load_batch_of_subfiles`, `Save_subfile`; the name table (Thalion's file number → 8.3 name in `AMBFILES\`), container headers, `JH_decrypt` (calls Thalion's `Crypt_block`), `Decompress` (LOB; `LOB_decompress` calls `Lob_core` from `AM2_CPU`) |
| `HULL/SPIELSTAND.S` | `Get_saved_game`, `Put_saved_game`, `Save_file`, `Save_encrypted_file`, contracts read in `AM2_CPU` (finding 251) |
| `HULL/INVENTOR_SUP.S` | `Object_data`, Thalion's item table, loaded from `Objects.amb` at start |
| `HULL/WORDS_SUP.S` | below Thalion's `HULL/WORDS.S`: `Put_text_line`; `Lade_texte` loads `Text.amb`, whose library texts Thalion's code reaches through fixed labels (`build/textmarken.i`) |

## Input

| File | What it does |
|---|---|
| `HULL/VARIOUS_SUP.S` | below Thalion's `HULL/VARIOUS.S`: `Read_key` builds Thalion's Amiga key code from the Atari scan code (rawkey from the key's position, qualifiers from `Kbshift`, the character from Thalion's `Keymap` file as `MapRawKey` would), `Read_Mev` (mouse event queue), `Copy_memory` and a few tables |

## 3D and combat

| File | What it does |
|---|---|
| `HULL/D3_SUP.S` | below Thalion's `MAP/3D_MAP.S`: `Show_MOVEP_screen` (3D buffer to screen, with gradients), `Clear_1plane_block`, `D3_einrichten` (CPU check, `CPU_68020_plus`, caches on the 68030), `Cache030_zurueck` (chapter 7) |
| `HULL/COMBAT_SUP.S` | the combat zoom: the blitter part of Thalion's `Draw_zoom_shape` and `Draw_zoom_silhouette` as CPU code; Thalion's preamble comes from `AM2_CPU` |

## Music

| File | What it does |
|---|---|
| `HULL/MUSIK_SUP.S` | the hardware below Thalion's Sonic Arranger player (from `AM2_CPU`): shadow Paula and CIA registers, the choice `MUSIC=` from `AMBER.INF` (`Musik_inf_lesen`; `Einstellungen_lesen` in `MAIN.S` reads the file through `shared/SETTINGS.S`), the parameter block for the mixer, `Musik_install`/`Musik_remove`/`Musik_vbl` |
| `musik/MISCHER.S` | the mixer, a module shared with intro and extro: the Paula emulated on the CPU (DMA sound) or the host side of the DSP mixer; `Mischer_remove` leaves the sound as it found it |
| `musik/MUSIK_DSP.A56` | the Paula mixer on the DSP56001, assembled with `a56` (`tools/musik_dsp.sh`), loaded with `Dsp_ExecBoot` |
| `HULL/MUSIK_YM.S` | `Music_routine`: the switch in front of the player; with `YM` it plays Big Alec's arrangement (`MUSIK_YM.BIN`, `MUSIK_YM.INF`) instead |

## ST only (`-DZIEL_ST=1`)

| File | What it does |
|---|---|
| `HULL/ST.S` | the ST/STE hardware with the same names as `FALCON.S`: low resolution, cookies `_MCH` and `_VDO`, STE fine video base |
| `HULL/ST_LIB.S` | 32 colours on 16 registers: per palette a table colour → register (k-means, Thalion's grey UI ramp protected), drawing through the table, Timer B at the area borders, the way back for `Get_block`, the tile cache of the ST; the 3D buffer on four planes; recoloured copies of the 3D blocks (user, 2026-10-10), hooked into `MEMORY.S` |

## Small and diagnostic

| File | What it does |
|---|---|
| `HULL/STARTMENUE.S` | the start menu (continue, new quest, intro, quit) when `ENGINE.TOS` runs without the loader; texts from `Ambermoon_intro` at build time |
| `HULL/DIAGNOSE_SUP.S` | the library's diagnostic screen (`Init_diagnostic_screen`, `DI_Print`, `DI_CR` …) and `Diagnostics_list1`, as in `AM2_CPU` (finding 267) |
| `HULL/AM2_CPU_STUBS.S` | placeholders for names not built yet; today none (the last, `Rune_flag`, is real since 2026-10-17, `WORDS_SUP.S`) |

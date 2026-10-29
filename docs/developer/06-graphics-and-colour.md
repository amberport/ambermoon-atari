# 6. Graphics and colour

## Thalion's data and our screen

| | Thalion's data | Our Falcon screen |
|---|---|---|
| Layout | Amiga bitplanes, line-interleaved: per line all words of plane 0, then plane 1 … | Atari format, word-interleaved: 16 pixels = 8 words in a row |
| Depth | 1 to 5 planes, colours 0–31 | 8 planes, 256 colour registers |
| Tiles | 16×16, `Icon_size` = 160 bytes | widened on demand, cached |
| Palette | 32 Amiga colour words `$0RGB` per palette, several per frame through the copper | 8 banks of 32 Videl registers |

The Videl knows 1, 2, 4 or 8 planes, not 5, so the screen has 8.
320×200, the mode bits inherited from the desktop: the program runs on RGB
and VGA monitors. One exception: on RGB `Open_screen` always sets
`MD_PAL` (50 Hz), because Thalion counts VBLs for 50 Hz (`Realtime`,
`VBLs_per_step`, `Delay`); VGA keeps its mode (tested on the Falcon 2026-10-27).

## Widened while drawing

**Thalion's data stays in memory as it is; the library widens it while
drawing.** One rule holds for every drawing routine (`Zeilenfarbe`):

```
colour = bank of the line + (bits of d4 from plane d5 up) + source value
         0 stays 0
```

- The planes below `d5` come from the source.
- Every higher plane is the mask "source value ≠ 0" where its bit is set
  in `d4`, otherwise zero. Example: Thalion's layouts have 3 planes and
  come with `d4` = 24; they land on colours 24–31.
- Planes 5–7 carry the bank, which replaces the copper (below).
- `d5` = 8 means the source is already in our screen format.

**Why while drawing:** Thalion's code computes with its data. It saves
backgrounds with `Get_block` (`d5` = 5) and puts them back later. That
round trip is lossless only if every routine keeps the rule: the bank is
dropped on saving and comes back from the line on restoring (finding
191). A graphic widened in advance would break it.

**Speed** (finding 271). Thalion redraws the 2D map in every frame,
about 200 tiles. `Kachel_holen` widens each tile once and afterwards
only copies. An entry is valid only for identical source contents,
because Thalion keeps restoring backgrounds at the same address.
`Farbbank_spanne` returns the bank together with the line from which it
may change, so a routine asks again only at that border.

**Double buffer as at Thalion.** `Schirm_vorn` is shown, `Off_screen` is
behind, `Work_screen` is where Thalion draws. `Switch_screens` draws
Thalion's HDOBs (free-floating objects) into the back screen, swaps, waits
for the frame and removes the HDOBs again.

**The mouse pointer** is a hardware sprite on the Amiga. Here it is part
of the picture: drawn into the back screen before every swap, and in every
VBL moved within the shown screen (save background, draw, restore;
finding 269). It takes the bank of its line (266).

**Clipping:** the block routines clip against the topmost clip area, as
the original does (`Block_beschneiden`, finding 254); `Put_unmasked_icon`
does not.

## Palettes: from the copper to colour banks

**The original.** Every module names a **raster list**: which palette
applies from which screen line, and where a colour runs through a
gradient. The map, for instance, has the interface palette `Main_pal` at
the top, a gradient of colour 25 behind the portraits in lines 1–35, and
the map palette `Current_pal` from line `Middle_Y`+1. The Amiga's copper
switches them in the middle of the frame: two palettes of 32 plus a
gradient on one screen.

**The Falcon: in space instead of in time.** Instead of rewriting the
registers in the middle of the frame (a Timer B interrupt, "in time"),
every palette of the raster list gets a bank of its own, and every pixel
carries the bank of its line ("in space"). No interrupt is needed.

```
raster list of the top module          colour registers     screen lines
1st R_palette (Main_pal)          →    bank 2 (64–95)   ←   0 … Middle_Y
2nd R_palette (Current_pal)       →    bank 0 (0–31)    ←   Middle_Y+1 …
3rd R_palette (combat: Tactic)    →    bank 1 (32–63)
R_range gradients                 →    banks 3–7 (96–255), one slot per line
colour 0                          →    register 0, in every line
```

- **The bank depends on the place of the palette in the list**
  (`Platzbank`, finding 264), never on what a bank holds at the moment.
  Otherwise a pixel would change colour when a fade loads the bank anew.
- If the top module has no raster list, the one below applies: on the
  Amiga the copper list would simply stay.
- **Fading:** Thalion's `HULL/FADE.S` calls `Set_fade` with a range of
  lines. Our `Set_fade` sets or fades every place whose palette starts in
  that range, gradient slots included. The copper fades along the frame;
  we fade in place, so `Wait_4_fade` has nothing to wait for. The light
  level in 3D is computed by Thalion's `Fade_colour` from `AM2_CPU`.

## The palettes and who uses them

**Raster lists.** They are data in Thalion's `MODULES.S`; each module
descriptor points to one (`Raster_list_ptr`), or to none, and then the
list of the module below applies. `R_palette <line>,<palette>` holds a
*pointer* to the palette, so the library reads the colours when it fades,
not when the module is pushed (finding 192). `Combat_RL` spells its
second entry out by hand (`Combat_pal_ptr: dc.l Combat_pal`) so that
`COMBAT.S` can swap that pointer. `Middle_Y` is 36: the second palette
starts at line 37.

| Raster list | Line 0 → bank 2 | Line 37 → bank 0 | Third place → bank 1 | Gradients | Modules |
|---|---|---|---|---|---|
| `Main_RL` | `Main_pal` | `Main_pal` | – | colour 25, lines 1–35 | camp, shops, trainers, chests, doors, riddle mouth, battle order, after combat; the default module |
| `Inv_RL` | `Main_pal` | `Main_pal` | – | colour 25, lines 1–35 and from line 49 | `Inv1_Mod`, `Inv2_Mod` |
| `Dialogue_RL` | `Main_pal` | `Main_pal` | – | colour 25, lines 1–35 and from line 43 | `Dialogue_Mod`, `Dialogue2_Mod` |
| `Map_RL` | `Main_pal` | `Current_pal` | – | colour 25, lines 1–35 | 2D maps (`C2Map`, `W2Map`), 3D dungeons (`D3Map`) |
| `C3_RL` | `Main_pal` | `Current_pal` | – | colour 25; colour 9 (sky) from line 49 (`Map3D_Y`) with `Current_sky` | 3D cities (`C3Map_Mod`) |
| `Combat_RL` | `Main_pal` | `Combat_pal` (through `Combat_pal_ptr`) | `Tactic_pal` from line 133 | colour 25, lines 1–35 | `Combat_Mod`, `CombatDisplay_Mod` |
| `Automap_Mod` `.RL` | `Main_pal` | `Automap_pal` | – | colour 25, lines 1–35 | automap |
| `Chared_Mod` `.RL` | `Main_pal` | – | – | colour 25 from line 62 (`Chared_Y`+13) | character editor |
| `ShowPicTxt_RL` | `Main_pal` | `Batch` | – | colour 25, lines 1–35 | event pictures, game over |

The bank follows the **place** in the list, not the palette (finding
264): `Main_pal` in the first place always lands in bank 2, whatever
palette stands in the second place lands in bank 0.

**Where the colours come from.** Every palette is 32 Amiga colour words
(`Pal_size` = 32, also for the Falcon).

| Palette | Defined | Filled from | When |
|---|---|---|---|
| `Main_pal` | `AM2_CPU` hunk 4 `$5B18`, extracted at build time (`build/am2cpu_daten.i`) | fixed | – |
| `Automap_pal` | `AM2_CPU` hunk 4 `$5B58` | fixed | – |
| `Tactic_pal` | `AM2_CPU` hunk 4 `$5B98` | fixed | – |
| `Current_pal` | Thalion's buffer (`MAIN.S`) | `Palettes.amb`, entry `Colourpal_filenr` of the map (`MAP.S`) | on entering a map |
| | | in 3D dungeons: a copy in `Backup_pal`, `Current_pal` = the copy faded to the light level (`3D_MAP.S`, Thalion's `Fade_colour` from `AM2_CPU`) | when the light changes |
| `Combat_pal` | Thalion's buffer (`MAIN.S`) | `Palettes.amb`, entry `Combat_palette_nr` (`COMBAT.S`); colours 26–31 from `Tactic_pal`; turned white and back for spell flashes (`COMBAT_M.S`) | combat |
| `Batch` | Thalion's scratch buffer | `Palettes.amb`, entry from `Event_pix_palette_table` (`EVENTS.S`) | event pictures |
| `Portrait_range` | Thalion's table (`DISPLAY.S`) | fixed: one colour word per line | – |
| `Current_sky` | Thalion's buffer (`MAIN.S`) | `Sky_ranges` (`AM2_CPU` hunk 4 `$5BD8`, three worlds), for the light level (`3D_MAP.S`) | 3D cities |

Thalion's code changes these buffers itself and then calls
`Reset_current_RL` or one of the fades; the library does not copy them,
it reads them through the raster list. Appendix C lists every piece taken
from `AM2_CPU` with its place.

Fantasy intro, intro and extro have their own palette path (copper list
→ two banks), described in chapter 10.

## Gradients (`R_range`)

A gradient gives one colour (25 behind the portraits, 9 for the 3D sky)
a different value in every line. On the Falcon every line of a gradient
gets a **slot**: a colour register of its own in banks 3–7.

- **Slots.** Slot *k* is colour 96 + (*k*/15)·32 + 1 + *k* mod 15, plus 16
  for the second kind. One kind has plane 4 = 0, the other plane 4 = 1,
  75 slots each. In the 3D window only the first kind is used, because
  plane 4 is cleared there in every frame (`Clear_1plane_block`, the
  stars).
  `Bereich_tabelle` (`RASTER.S`) assigns them per raster list into
  `Zb_tab`: per line the gradient colour and the slot.
- **After the gradient** the colour keeps its last value until the next
  palette, as on the copper: colour 25 in line 36 is black.
- **Drawing (2D).** The routines draw bank + colour as usual. Afterwards
  `Bereich_nacharbeiten` replaces, inside the drawn rectangle and only in
  gradient lines, bank + gradient colour by the slot of the line (a mask
  over the 8 planes per block and line). The tile cache stays valid,
  because it holds the picture before this step.
- **Drawing (3D).** `Show_MOVEP_screen` asks `Zeilenersatz` per line and
  writes the slot directly (chapter 7).
- **Reading back.** `Get_block` turns slots back into bank + gradient
  colour (`Bereich_rueck`), and so does `Get_pixel` (`Platz_rueck`), so
  that Thalion's code sees its own colour numbers.

## Amiga colours on the Videl

An Amiga colour word is `$0RGB`, 4 bits per channel. The Videl has 6
bits per channel. The library spreads 0–15 linearly over 0–63,
`min(63, round(n·63/15))`, stored in the upper six bits of a byte
(`Vid_stufe`: 0, 16, 32, 52 … 252). `Bank_setzen` writes 32 of them
through XBIOS `VsetRGB` (`$00RRGGBB`). The hardware registers at
`$FFFF9800` hold `$RRGG00BB` instead (measured, see `RASTER.S`);
`Amiga_nach_videl` converts for direct writes.

Hatari does not show palette changes inside a Falcon frame (finding
150). For colours only the hardware is evidence.

## The ST: 32 colours on 16 registers

The ST has 16 colour registers and no banks. **The picture data stays;
the palette is reduced** (`ST_LIB.S`, `docs/12-ST-Port.md`):

1. Per place of the raster list the library computes 16 replacement
   colours and a table colour number → register: k-means over the 31
   colours, Thalion's grey interface ramp (26–31) kept apart, register 0
   for colour 0 alone, so 0 stays transparent.
2. Where the Falcon adds the bank, the ST looks up the table: register →
   4 planes.
3. **Timer B** reloads the 16 registers of the next area at every border
   (`St_raster_int`), once per border and frame. Here it is "in time"
   after all; with 16 colours there is no other way.
4. Back through `Get_block` goes through a representative: register *r*
   becomes a colour whose table entry is *r* again.
5. Gradients stay flat (decision of 2026-10-02).
6. The tables come precomputed: the ST build reduces every palette of the
   game the same way and writes `STPAL.DAT`, which the engine loads once
   at start (`St_load_palettes`, `St_from_file`); hand corrections per
   machine are in `tools/st_palettes.txt`. Only a palette not in the file
   is computed at run time (`St_bauen`, about a second on 8 MHz). This is
   deviation D1 from goal 2 (`docs/17-deviations.md`).

Colour words: the ST has 3 bits per channel, the STE 4, with the lowest
bit stored as bit 3 of each nibble (`st_ste_wort`). The program detects
the STE by the cookie `_MCH`.

# 2. The copper becomes colour banks

## The problem

Look at the 2D map screen of Ambermoon. The top strip with the party's
portraits uses Thalion's grey interface palette, `Main_pal`. The map
below uses the palette of the current map, `Current_pal`. Behind the
portraits, colour 25 runs through a gradient: a different shade in every
line. That is two palettes of 32 colours and a gradient on one screen,
although the Amiga shows only 32 colours at a time.

The Amiga does it with the **copper**, a small coprocessor that follows
the picture beam and rewrites colour registers at chosen lines. The
palette changes *in time*: line 36 still shows `Main_pal`, line 37
already `Current_pal`.

Thalion's code describes this per screen in a **raster list**. Every
module (map, inventory, combat, dialogue …) names one:

```
Map_RL:  R_palette 0,Main_pal              from line 0: the interface palette
         R_range   1,25,35,Portrait_range  colour 25, lines 1–35: one value per line
         R_palette Middle_Y+1,Current_pal  from line 37: the map palette
         R_end
```

The Falcon has no copper. It has 256 colour registers instead of 32.

## The idea

There are two ways to show several palettes on one Atari screen:

- **In time**, like the copper: an interrupt (the MFP's Timer B, which
  can count screen lines) fires at each border and rewrites the
  registers. Then 32 registers are enough, and Thalion's colour numbers
  mean what they say.
- **In space**: every palette gets registers of its own, and every pixel
  says which ones it uses. No interrupt is needed, but the pixel needs
  more bits.

The Falcon uses **space**. Its 256 registers are eight **banks** of 32.
Each palette of the raster list gets a bank, and planes 5–7 of every
pixel hold its bank number (chapter 1). The picture never changes its
registers in the middle; the Videl just shows 256 colours.

```
raster list of the top module          colour registers        screen lines
1st R_palette (Main_pal)          →    bank 2 (64–95)     ←    0 … 36
2nd R_palette (Current_pal)       →    bank 0 (0–31)      ←    37 …
3rd R_palette (combat: Tactic)    →    bank 1 (32–63)
R_range gradients                 →    banks 3–7 (96–255), one register per line
```

The way in time exists too (`engine/src/HULL/RASTER.S`, `RASTER_ZEIT`).
Timer B does count screen lines on the Falcon (measured on the hardware
with a test program of its own, finding 154), but the first
interrupt came at line 81 instead of 100, with a spread up to line 131
that was never explained, and two other routines rewrote the registers
behind its back (finding 155). The banks work without any of that, so
the Falcon stays with them (user, 2026-09-30; `RASTER_VERFAHREN` =
`RASTER_RAUM` in `engine/src/FALCON_OFF.S`). The ST has only 16
registers and no room for banks; it has to go in time (planned chapter).

### The bank belongs to the place, not to the palette

Which palette lands in which bank? The answer is: **its place in the
raster list**. The first `R_palette` always goes to bank 2, the second to
bank 0, the third to bank 1 (`Platzbank`).

An earlier version looked at what a bank held at the moment. Then a
pixel could change colour after it was drawn: a fade put `Main_pal` into
bank 0, the next module drew the portrait strip into bank 0, the next
fade loaded the map palette into bank 0, and the portraits took on the
map's colours (finding 264, from a savestate of the user). Since the bank
follows only the line and the place, a pixel keeps its meaning however
the banks are refilled.

### Which raster list applies

The library asks the module stack, the same way the Amiga's copper list
simply stayed where it was:

- the raster list of the **top module**;
- if that module has none (a requester, the target choice in combat), the
  one of the module below, and so on;
- when something draws straight into the **visible** screen (the
  diagnostic screen after "out of memory"), the list that was set last,
  because on the Amiga that is the copper list that is running;
- when something draws into a scratch screen (item graphics being
  composed), bank 0: whatever is drawn there is picked up again with five
  planes, and a bank would be dropped anyway.

### Fades

Thalion's `HULL/FADE.S` asks the library to fade a range of lines in or
out. On the Amiga the copper does it alongside the game; the call returns
at once, and `Wait_4_fade` waits for the copper. Our `Set_fade` fades
in place: every place of the raster list whose palette starts inside the
range is faded in 15 steps, one per frame, about a third of a second as
in the original, and only then returns. `Wait_4_fade` has nothing left to
wait for. To Thalion's code, which calls one and then the other, the two
worlds look the same.

### Gradients

A gradient (`R_range`) gives one colour a different value in every line:
colour 25 behind the portraits, colour 9 for the sky in 3D cities. With
banks, every line of a gradient needs a register of its own. Banks 3–7
provide them as **slots**, one per line.

Drawing then takes two steps. The routine draws as usual, bank + colour.
Afterwards `Bereich_nacharbeiten` looks only at gradient lines inside the
drawn rectangle and replaces bank + gradient colour by the slot of that
line. When Thalion's code reads the screen back (`Get_block`,
`Get_pixel`), slots turn back into bank + colour 25, so Thalion sees its
own numbers. The tile cache from chapter 1 stays valid, because it holds
the picture before this step.

### Colour values

An Amiga colour word is `$0RGB`, four bits per channel, 0–15. The Videl
has six bits per channel, 0–63. The library spreads the 16 steps evenly
(`Vid_stufe`: 0, 16, 32, 52 … 252 as the upper six bits of a byte) and
writes a bank of 32 through XBIOS `VsetRGB`.

## In the code

| Routine | File | What it does |
|---|---|---|
| `Farbbank`, `Farbbank_spanne` | `engine/src/HULL/LIBRARY.S` | the bank of a screen line; `_spanne` also says up to which line it holds, and remembers the answer for the usual case (drawing into the back screen, top module with its own list) |
| `Zeichenliste` | `LIBRARY.S` | which raster list applies to a drawing: top module, module below, last set list, or none |
| `Rasterbank`, `Rasterbank_spanne` | `LIBRARY.S` | the same for the mouse pointer, which always stands in the shown picture |
| `Platzbank` | `engine/src/HULL/FADE_SUP.S` | the table place → bank: 64, 0, 32 |
| `Set_fade`, `Wait_4_fade` | `FADE_SUP.S` | below Thalion's `HULL/FADE.S`: set or fade the places of a line range |
| `Platz_setzen`, `Bank_setzen` | `engine/src/HULL/FALCON_LIB.S` | one palette into its bank; Amiga colour words to Videl values |
| `Bereich_tabelle`, `Zeilenersatz` | `engine/src/HULL/RASTER.S` | gradient slots per raster list; the slot of one line |
| `Bereich_nacharbeiten`, `Bereich_rueck` | `RASTER.S` | slots into a drawn rectangle; slots back to Thalion's colour |

Findings: 150 (Hatari does not show palette changes inside a Falcon
frame, so for colour effects only the hardware is evidence), 154 and 155
(Timer B on the Falcon), 192 (the library reads palettes through the
raster list's pointers, it keeps no copies), 264 (bank by place), 266
(the pointer takes the bank of its line). Developer reference, with the
table of every raster list of the game and where each palette comes
from: [chapter 6 of the developer
documentation](../developer/06-graphics-and-colour.md).

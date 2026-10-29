# How the Atari layer works

Ambermoon on the Falcon and the ST runs **Thalion's own source code,
unchanged**. Thalion never released one part of it: the library
underneath, which on the Amiga talks to the hardware. It shipped only as
the compiled file `AM2_CPU`. This project writes that library again, for
the Atari. The game above it does not know it is not on an Amiga.

This guide explains that library one problem at a time. You can read it
without knowing 68000 assembler. Start with chapter 0, the big
picture; the chapters after it each take one problem and have three
parts:

- **The problem.** What the Amiga does that the Atari cannot, and why
  that matters to Thalion's code.
- **The idea.** How the library solves it, and which other ways were
  possible and why they were not taken.
- **In the code.** For developers: the routines, their files, and the
  findings in `docs/04-Erkenntnisse.md` (German) that led there. The
  full reference is the developer documentation in
  [`docs/developer/`](../developer/README.md).

The guide describes the current state. Where it names a routine, the
name is the one in the source; many of our names are German (a short
glossary is at the end of this page).

## Chapters

| | Chapter | The problem in one line |
|---|---|---|
| 0 | [The big picture](00-big-picture.md) | what Thalion released and what not, where the hardware begins, and the four ways we fill the gap |
| 1 | [Five planes on a machine that has eight](01-five-planes.md) | the Amiga draws in 32 colours with five bitplanes; the Falcon knows 1, 2, 4 or 8 |
| 2 | [The copper becomes colour banks](02-colour-banks.md) | the Amiga changes the palette in the middle of the picture; the Falcon would need an interrupt for that |
| 3 | [Files unpacked while playing](03-files-at-run-time.md) | Thalion's game files are packed, encrypted containers, and only the unreleased library knew how to open them |

Planned, in this order:

- **Music**: the Amiga's sound chip Paula, emulated on the Falcon's DSP,
  and Big Alec's YM version for the ST.
- **32 colours on 16 registers**: the ST.
- **Intro and extro without source**: Thalion's Amiga programs on an
  emulated Amiga, with a blitter in software.

## The two machines in one table

| | Amiga (the original) | Falcon030 | ST/STE |
|---|---|---|---|
| Processor | 68000, 7 MHz | 68030, 16 MHz | 68000, 8 MHz |
| Screen | 320×200, 5 bitplanes, 32 colours | 320×200, 8 planes, 256 colours | 320×200, 4 planes, 16 colours |
| Palette changes in the picture | the copper, for free | colour banks (chapter 2) | an interrupt per border |
| Graphics help | blitter | none used | blitter on STE and Mega STE |
| Sound | Paula, four sample channels | DSP56001 and DMA sound | YM2149 |

## Glossary of our names

| Word | Meaning |
|---|---|
| *Bank*, *Farbbank* | colour bank: a group of 32 of the Falcon's 256 colour registers |
| *Ebene* | plane (bitplane) |
| *Farbe* | colour |
| *Kachel*, *Kachelspeicher* | tile, tile cache |
| *Platz* | place, slot (of a palette in a raster list, of a gradient line in a bank) |
| *Quelle* | source (the graphic being drawn) |
| *Schirm* | screen |
| *Spanne* | span: the lines over which something holds |
| *Zeile* | line (of the screen) |
| *aufweiten* | to widen (five planes to eight) |
| *nacharbeiten* | to rework afterwards |

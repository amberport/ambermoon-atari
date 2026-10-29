# 1. Five planes on a machine that has eight

## The problem

Both the Amiga and the Atari store a picture in **bitplanes**. A plane
holds one bit per pixel. With five planes every pixel has five bits, a
number from 0 to 31, and that number picks one of 32 colours from the
palette:

```
pixel x:     plane 0   plane 1   plane 2   plane 3   plane 4
             1         1         0         1         1          = 1+2+8+16 = colour 27
```

Ambermoon on the Amiga uses five planes, 32 colours. Thalion's graphics
are stored that way in the game files, and Thalion's code computes with
them that way.

The Falcon's video chip, the Videl, shows 1, 2, 4 or 8 planes. **Five
is not among them.** So our screen has eight planes and 256 colours.

The two machines also lay the planes out differently in memory:

```
Amiga, line-interleaved                Atari, word-interleaved
(Thalion's data)                       (our screen)

line 0: plane 0  [w][w][w]...          line 0: [p0 p1 p2 p3 p4 p5 p6 p7][p0 p1 ...]...
        plane 1  [w][w][w]...                   └──── 16 pixels ────┘
        plane 2  [w][w][w]...
        plane 3  [w][w][w]...          w = one 16-bit word = 16 pixels of one plane
        plane 4  [w][w][w]...
line 1: plane 0  ...
```

On the Amiga each line holds all words of plane 0, then all words of
plane 1, and so on. On the Atari the eight words of one group of 16
pixels stand side by side.

## The idea

**Thalion's graphics stay in memory exactly as they are: five planes,
Amiga layout. The library widens them to eight planes at the moment it
draws them.**

The obvious alternative was to convert every graphic in advance, once,
to the Atari format. It was not taken, for two reasons:

1. It would break goal 2 of the project, to read the original game files
   as they are.
2. It would break Thalion's code. Thalion does not only draw graphics, it
   also *saves* parts of the screen and puts them back later (behind a
   window, under a menu). It saves them with five planes, because that is
   what the Amiga has. If the screen held something that five planes
   cannot express, that something would be lost on the way back.

So the rule is: whatever Thalion's code sees is five planes deep.
`Screen_depth`, the constant Thalion's code reads, stays 5. Only the
library knows that the screen has eight.

### What the three extra planes carry

Planes 0–4 carry Thalion's colour number, 0 to 31. Planes 5–7 carry the
**colour bank**: which of eight groups of 32 colour registers this pixel
uses. That is how the Falcon shows several palettes at once; chapter 2
explains it. For this chapter it is enough that the bank depends only on
the screen line.

### The drawing rule

Thalion's code calls a drawing routine with two parameters that already
existed on the Amiga:

- `d5`, the number of planes in the source graphic (1 to 5);
- `d4`, a colour offset for the planes the source does not have.

A graphic with three planes knows colours 0–7. Thalion's interface
layouts are such graphics, drawn with `d4` = 24: they land on colours
24–31 of the palette. Every routine of our library applies one rule:

```
colour of the pixel = bank of the line + bits of d4 from plane d5 up + source value
                      but a source value of 0 stays 0
```

In planes this means, per line:

- planes below `d5` are copied from the source;
- every plane from `d5` up is set where the pixel is *not* colour 0 and
  the target colour has that plane's bit, otherwise it is cleared.

**Why 0 stays 0.** Colour 0 is transparent on the Amiga, and the offset
applies only to visible pixels. This was measured, not assumed: in a
memory dump of the Amiga version, layout value 3 appears as colour 27, 7
as 31, 5 as 29, but 0 stays 0 (the comment in `Pub_zeilen` records
it).

### The round trip

The rule makes saving and restoring lossless:

```
draw:     source value 27, line 50 (bank 0)   →  screen: 27 + bank 0
save:     Get_block with d5 = 5               →  keeps the lower 5 planes: 27, drops the bank
restore:  Put_unmasked_block, line 50         →  27 + bank of line 50 again
```

The bank is dropped on saving and comes back from the line on
restoring. It works only if **every** routine keeps the rule. When one
did not, a background saved with five planes came back in another colour
(finding 191).

### Speed: the tile cache

Widening costs time. Thalion's 2D map is made of 16×16 tiles, and
Thalion redraws the whole map in every frame, about 200 tiles, even when
the party stands still. On the Amiga that is cheap: the blitter copies.
On the Falcon every tile would be widened anew in every frame.

So the library keeps a **tile cache** (`Kachelspeicher`, 1024 entries,
456 KB): each tile is widened once and afterwards only copied. This is
allowed, because it is our layer converting at run time; Thalion's code
and data stay untouched.

The difficult part is knowing when an entry is still valid. A tile is
found by its address, its colour and its number of planes, but **valid
only if the source bytes are still the same**. Each entry keeps a copy of
its source and compares all of it. A checksum or a load counter was not
enough: Thalion's code keeps saving backgrounds at the same address with
`Get_block`, and writes memory without calling the library at all
(finding 271). The comparison costs about as much as the copy; widening
cost many times more.

A second saving: the bank changes only at two or three lines of the
screen. `Farbbank_spanne` returns the bank together with the line up to
which it holds, so a drawing routine asks again only at that border.

## In the code

| Routine | File | What it does |
|---|---|---|
| `Put_unmasked_block`, `Put_masked_block`, `Put_masked_icon` … | `engine/src/HULL/LIBRARY.S` | Thalion's names and contracts: clipping, addresses, then the machine part |
| `Pub_zeilen` | `engine/src/HULL/FALCON_LIB.S` | the lines of `Put_unmasked_block` for a source in Thalion's format: mask "not colour 0" per line, plane by plane into the target; a whole tile goes through the cache |
| `Quelle_aufweiten` | `FALCON_LIB.S` | widens a masked graphic into a buffer, the colour per line (a graphic across a bank border gets the right bank above and below) |
| `Masked_icon` | `FALCON_LIB.S` | `Put_masked_icon` on the Falcon, with the tile path |
| `Kachel_holen` | `FALCON_LIB.S` | the tile cache: find, compare, widen once |
| `Zeilenfarbe` | `LIBRARY.S` (contract), `FALCON_LIB.S` | one colour of Thalion's into the bank of a line: for lines, boxes, characters, silhouettes |
| `Get_block_orig` | `FALCON_LIB.S` | `Get_block` into Thalion's format: the lower `d5` planes only |
| `Farbbank`, `Farbbank_spanne` | `LIBRARY.S` | the bank of a line, and up to where it holds (chapter 2) |

The parameter `d5` = 8 means "the source is already in our screen
format"; then nothing is widened (`SCHIRM_FORMAT` in `FALCON_OFF.S`).

Findings: 191 (`Screen_depth` means Thalion's data), 176 (`Icon_size` is
the distance in Thalion's data, not on our screen), 271 (tile cache and
the bank span). Developer reference: [chapter 6 of the developer
documentation](../developer/06-graphics-and-colour.md).

**On the ST** the screen has four planes, not eight, and the problem
turns round: 32 colours must fit into 16. That is a chapter of its own
(planned).

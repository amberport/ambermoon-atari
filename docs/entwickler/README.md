# Developer documentation

Ambermoon for the Atari Falcon030 and ST/STE: a port of Thalion's Amiga
role-playing game (1993) that assembles **Thalion's own source code,
unchanged**, on top of a library layer we wrote, and reads **the original
game files at run time**. No emulator, no remake.

This folder is meant for reading in: how the project is built, where its
entry points and interfaces are, and how the Amiga's hardware model is
mapped onto the Falcon and the ST. It describes the current state only.
How we got there, with evidence, is in the working documents one level up
(`docs/04-Erkenntnisse.md`, in German); this text points there where it
helps.

![Architecture](architecture.svg)

## Chapters

| | Chapter | Read it for |
|---|---|---|
| 1 | [Getting started](01-getting-started.md) | what you need, how to build, where things are |
| 2 | [Architecture](02-architecture.md) | the layers, the two goals, the two targets |
| 3 | [Entry points and flow](03-entry-points.md) | `start`, the main loop, the VBL, the program chain, the emergency exit |
| 4 | [The interface](04-interface.md) | names as contracts, two translation units, `vorspann.i` |
| 5 | [Our layer, file by file](05-our-layer.md) | what each of our source files does |
| 6 | [Graphics and colour](06-graphics-and-colour.md) | planes, colour banks, gradients, Amiga colours on the Videl, the ST's 16 registers |
| 7 | [3D](07-3d.md) | Thalion's rasterisers, the 3D buffer, the sky |
| 8 | [Files, music, intro and extro](08-files-music-amiga.md) | run-time unpacking, save games, the three music paths |
| 9 | [Build and checks](09-build-and-checks.md) | what `build_all.sh`, `build_falcon.sh` and `build_st.sh` do, what each check guarantees |
| 10 | [The Amiga layer](10-amiga-layer.md) | fantasy intro, intro, extro: Thalion's binaries on an emulated Amiga, K1/K2/K3, display, colours, blitter, music |
| 11 | [Tools](11-tools.md) | every tool in `tools/`: what for, how to call it, what it needs |

## Appendices (generated)

| | Appendix | |
|---|---|---|
| A | [Thalion's source files](appendix-a-source-files.md) | which unit includes which file, our companion files |
| B | [Symbols](appendix-b-symbols.md) | every name Thalion's code uses but never released, and where we define it |
| C | [What the build takes from AM2_CPU](appendix-c-am2cpu.md) | data and code pieces with their location |

The appendices are written by `tools/doku_listen.py`. Every build writes
them to `build/doku/`; `python3 tools/doku_listen.py --docs` writes them
here. Do that on `main` only, before committing the documentation.

## Conventions

- **Thalion** is the studio; "Thalion's code" means the released source,
  never ours.
- Our identifiers and many comments are German (*Zeile* line, *Farbe*
  colour, *Bank* bank, *Platz* slot, *Schirm* screen, *Ebene* plane). New
  text is English; German paragraphs are translated as they change.
- File references are relative to the repository root. Thalion's files are
  named as in their source tree (`HULL/FADE.S`, `MAP/3D_MAP.S`); ours carry
  their path (`engine/src/HULL/FADE_SUP.S`).
- Numbers like *finding 271* refer to `docs/04-Erkenntnisse.md`.

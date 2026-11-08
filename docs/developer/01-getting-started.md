# 1. Getting started

## What you need

**Thalion's material, not in this repository:**

| What | Where it comes from | Key (default below `ambermoon_gamedata/` next to the repository) |
|---|---|---|
| Thalion's released 68000 source, its `src/` folder with `GAME_OFF.S`, `HULL/`, `MAP/` … | [jhorneman/ambermoon](https://github.com/jhorneman/ambermoon); if it is missing at its default place, the build fetches it (`tools/fetch_source.py`) | `AMBER_URCODE` (`ambermoon-main-asm/src`) |
| The game files of one version: 1.01 German, 1.07 English, 1.20 German, 1.21 German, English or French. A folder, a zip or disk images (ADF, IPF, DMS) | your own copy of the game | `AMBER_DATEN`, for a folder the one *above* `Amberfiles/` (`ambermoon_german_1.20_extracted`), or on the command line; unset and missing, the one set in `ambermoon_gamedata/` |
| Optional: Big Alec's YM arrangement as an SNDH file (released by PHF/Nokturnal in 2019 as the *Ambermoon Music Demo*, linked into one file by Grazey) | `big_alec/ambermon.snd` from the SNDH archive | `AMBER_YMSNDH` (`ambermon.snd`); if it is set and the file is missing, the build stops |
| Optional: a TOS image for Hatari | your own | `AMBER_TOS` (`TOS404.IMG`) |

Every tool asks `tools/paths.py` for these paths, key by key: first the
environment variable of that name, then the file `build.cfg` (the first
one found from the repository root upwards, so the worktrees use the main
checkout's; it holds personal paths and is never committed, template
`build.cfg.example`), then the default folder. `python3 tools/paths.py`
shows what it finds and where from; the first step of every build,
"Sources and switches", checks the same, with the details in
`build/build.log`. `AMBER_OBJDUMP` works the same way and has no
default (below). `AMBER_DOWNLOAD=NO` forbids the build every download.

The build finds out by itself which version it has. Our code is written
against 1.20; for the others the build moves each place it needs and
makes the files Thalion's older disks lack (chapters 9 and 10). A build
fits the game files it was built from: the engine checks that at start.

The rights to Thalion's games are unclear; the source is published for
study. That is why nothing of Thalion's ever goes into this repository,
neither source nor game data nor anything extracted from them.

**Tools:** `vasmm68k_mot` 1.9a and `vlink` 0.17a (Volker Barthelmann,
Frank Wille; vasm 2.0f does not build this project), on Linux x86-64
fetched by the build when they are missing (`tools/fetch_vbcc.py`), an
m68k `objdump` (`AMBER_OBJDUMP`, `PATH`, or the VS Code extension
`atari-st-dev`), Python 3, a POSIX shell. `a56` (the DSP56001 assembler;
Debian/Ubuntu package `a56`) only to change the music mixer: without it
the build takes the assembled `musik/musik_dsp.dsp`. `node` only for the
ST build's check of the palette editor's page; without it the build warns
once. Hatari for emulator runs.

**Hardware it runs on:** a Falcon030 (tested with 14 MB, TOS 4.04, RGB and
VGA; a CT60 in 68030 mode). On a CT60 with its own processor (first test
by the user, release 0.8.5) the game runs, 3D about as fast as on the
68030; TT-RAM (Alt-RAM) is not used yet. The ST build targets an STE with
8 MHz and 4 MB (user, 2026-10-21); it uses the blitter where there is one
and keeps the CPU path for a plain ST. It also runs on a Mega STE, but
nothing is laid out for it; 16 MHz and the cache are switched on by hand,
not by the program. At 16 MHz the intro and the fantasy intro switch to
8 MHz for now (test T111 open; to be looked at again). Minimum memory and
other TOS versions are not measured yet.

## Build

```
sh tools/build_all.sh          both machines
sh tools/build_all.sh FILE     the same, from these game files
sh tools/build_falcon.sh       the Falcon only
sh tools/build_st.sh           the ST only
TESTBUILDS=1 sh tools/build_all.sh   also the test builds (chapter 9)
```

The short way, with the versions and how far each is tested, is the
[Quickstart in the README](../../README.md#quickstart). What the build
looks for and where, the tools, and the way on macOS and Windows:
[building it yourself](building.md).

`build_all.sh` is the one build. It shows one line per step and writes
everything else into `build/build.log` (`VERBOSE=1` shows all); its first
step, "Sources and switches", stops it if a required source is missing.
Its last line names the build: our version (the file `VERSION`), the
commit, and the game files it was built for. Both machines' builds write
into one folder:

```
ATARI/AMBER.TOS           the loader for both: start this on Falcon or ST/STE
ATARI/AMBFILES/           ENGINE.TOS, FANTASY.TOS, INTRO.TOS, EXTRO.TOS
                          (Falcon), ENGINEST.TOS, FANTSYST.TOS, INTROST.TOS,
                          EXTROST.TOS (ST), Thalion's game files
                          under 8.3 names, save games, BUILD.TXT (the build's
                          name), MUSIK_YM.BIN (with AMBER_YMSNDH)
build/                    everything intermediate, never versioned
```

Copy `ATARI/` to the Atari and start the loader of the machine. Game files
and save games are shared, so the same folder plays on both. Every program
also runs alone, for instance `AMBFILES\ENGINE.TOS` without intro.

**A build overwrites** `ATARI/` and `ATARI/AMBFILES/` except `*.INF` and
the programs of the other machine, including the save games: copy yours
away first.

Partial builds for quick work on one part (they do not deliver to
`ATARI/`): `sh tools/fantasy_bauen.sh`, `sh tools/amiga_bauen.sh
intro|extro`. A diagnostic switch goes in through `VASM_EXTRA`, for
example `VASM_EXTRA="-DZEIGERTAKT=1" sh tools/build_falcon.sh`; chapter 9
lists them.

## Run-time switches

| File in `AMBFILES\` | Effect |
|---|---|
| `AMBER.INF` | the one settings file (`shared/SETTINGS.S`): `MUSIC=OFF`, `DSP` (default, also without the file), `CPU`, `YM`; on the ST only `OFF` counts. `PLAIN_ST=YES` (ST build only): an STE or Mega STE behaves like a plain ST. `COARSE_WALLS=YES` (both machines): opaque 3D walls are drawn in pairs of columns while the view moves, sharp again when it stands (docs/17 D10); `NO` turns it off; no line keeps the built-in value, off unless built with `-DCOARSE_WALLS=1` |
| `MUSIK_YM.INF` | which of Thalion's song numbers plays which YM song; delivered as a template when none is there |

## Where things are

```
engine/       the engine: engine.s and spiel.s (the two units), src/ (our layer)
lader/        the loader AMBER.TOS
fantasy/      the fantasy intro: our layer under Thalion's FAIRY.S
intro/ extro/ start code and hand-over for Thalion's intro and extro binaries
amiga/        the Amiga layer for intro and extro: OS calls, copper, software blitter
fantasy_st/ intro_st/ extro_st/   the same three programs for the ST
tools/        build, extraction from AM2_CPU, checks (Python, sh)
tools/originalcode/vorspann.i   replaces Thalion's unreleased include file
docs/         working documents (German) and this folder
```

## Where to start reading

Chapter 2 for the big picture, then chapter 4 (the interface) before
touching any of our routines. `docs/04-Erkenntnisse.md` (German) holds
the numbered findings this documentation cites, each with its evidence;
at its front, the rules in short and the groups of traps that came back
more than once. `docs/16-Pruefwerkzeuge.md` says what each check proves
and what it does not.

# 1. Getting started

## What you need

**Thalion's material, not in this repository:**

| What | Where it comes from | Key (default below `ambermoon_gamedata/` next to the repository) |
|---|---|---|
| Thalion's released 68000 source, its `src/` folder with `GAME_OFF.S`, `HULL/`, `MAP/` … | [jhorneman/ambermoon](https://github.com/jhorneman/ambermoon) | `AMBER_URCODE` (`ambermoon-main-asm/src`) |
| The game files, German version 1.20, unpacked so that `Amberfiles/` is a folder | your own copy of the game | `AMBER_DATEN`, the folder *above* `Amberfiles/` (`ambermoon_german_1.20_extracted`) |
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
default (below).

The rights to Thalion's games are unclear; the source is published for
study. That is why nothing of Thalion's ever goes into this repository,
neither source nor game data nor anything extracted from them.

**Tools:** `vasmm68k_mot` and `vlink` (Volker Barthelmann), `a56` (the
DSP56001 assembler; Debian/Ubuntu package `a56`), an m68k `objdump`
(`AMBER_OBJDUMP`, `PATH`, or the VS Code extension `atari-st-dev`),
Python 3, a POSIX shell. Hatari for emulator runs.

**Hardware it runs on:** a Falcon030 (tested with 14 MB, TOS 4.04, RGB and
VGA; a CT60 in 68030 mode). The ST build targets an STE with 8 MHz and
4 MB (user, 2026-10-21); it uses the blitter where there is one and keeps
the CPU path for a plain ST. It also runs on a Mega STE, but nothing is
laid out for it; 16 MHz and the cache are switched on by hand, not by the
program. Minimum memory and other TOS versions are not measured yet.

## Build

```
sh tools/build_all.sh          both machines
sh tools/build_falcon.sh       the Falcon only (needs a56)
sh tools/build_st.sh           the ST only (no a56)
```

Step by step for Linux, macOS and Windows, with where each tool comes
from: [building it yourself](building.md).

`build_all.sh` is the one build. It shows one line per step and writes
everything else into `build/build.log` (`VERBOSE=1` shows all); its first
step, "Sources and switches", stops it if a required source is missing.
Both machines' builds write into one folder:

```
ATARI/AMBER.TOS           the loader for both: start this on Falcon or ST/STE
ATARI/BOMBEN.TOS          crash report tool (not part of the game)
ATARI/AMBFILES/           ENGINE.TOS, FANTASY.TOS, INTRO.TOS, EXTRO.TOS
                          (Falcon), ENGINEST.TOS (ST), Thalion's game files
                          under 8.3 names, save games, MUSIK_YM.BIN (with
                          AMBER_YMSNDH)
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
| `AMBER.INF` | the one settings file (`shared/SETTINGS.S`): `MUSIC=OFF`, `DSP` (default, also without the file), `CPU`, `YM`; on the ST only `OFF` counts. `PLAIN_ST=YES` (ST build only): an STE or Mega STE behaves like a plain ST |
| `MUSIK_YM.INF` | which of Thalion's song numbers plays which YM song; delivered as a template when none is there |

## Where things are

```
engine/       the engine: engine.s and spiel.s (the two units), src/ (our layer)
lader/        the loader AMBER.TOS
fantasy/      the fantasy intro: our layer under Thalion's FAIRY.S
intro/ extro/ start code and hand-over for Thalion's intro and extro binaries
amiga/        the Amiga layer for intro and extro: OS calls, copper, software blitter
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

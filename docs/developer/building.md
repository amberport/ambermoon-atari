# Building it yourself

> **Draft** (Docs, 2026-10-29). Written for visitors of the published
> repository. Only the Linux way has been run so far, on the
> maintainer's machine; the macOS and Windows parts are worked out from
> the build scripts and are not tested. The open points are at the end.

This repository holds the Atari side of the port only: our library, the
build scripts and the tools. Thalion's source and the game are not in it
and never will be. You bring both yourself; the build reads them where
they lie, takes what it needs and writes a folder `ATARI/` that you copy
to a Falcon030 or an ST/STE.

## What you need

### From outside the repository

| What | Where from | Key |
|---|---|---|
| Thalion's released source: the folder that holds `GAME_OFF.S`, `HULL/`, `MAP/` … | [jhorneman/ambermoon](https://github.com/jhorneman/ambermoon) | `AMBER_URCODE` |
| Ambermoon, **German version 1.20**, unpacked, so that `Amberfiles/` is an ordinary folder with `AM2_CPU` in it | your own copy of the game | `AMBER_DATEN`: the folder *above* `Amberfiles/` |
| Optional: Big Alec's YM music, `big_alec/ambermon.snd` | the [SNDH archive](https://sndh.atari.org) | `AMBER_YMSNDH`: the file itself |
| Optional: a TOS image, for the emulator Hatari | your own | `AMBER_TOS` |

### Telling the build where they are

The build looks for each of these by its key, in this order:

1. an **environment variable** of that name, for one build:
   `AMBER_DATEN=/somewhere sh tools/build_all.sh`;
2. the file **`build.cfg`** in the repository root (or a folder above
   it), one `KEY=PATH` per line. Copy `build.cfg.example` to `build.cfg`
   and fill in what differs; `~` and paths relative to the file work.
   The file holds your own paths and is never committed;
3. the **default**: a folder `ambermoon_gamedata/` next to the
   repository, with the names `ambermoon_german_1.20_extracted/`,
   `ambermoon-main-asm/src/`, `ambermon.snd` and `TOS404.IMG` in it.

The easiest way is the third: put your copies there under those names,
and nothing needs to be set:

```
somewhere/
  ambermoon/                          this repository
  ambermoon_gamedata/
    ambermoon_german_1.20_extracted/  with Amberfiles/ inside
    ambermoon-main-asm/src/           Thalion's source, with GAME_OFF.S
    ambermon.snd                      optional
```

`python3 tools/paths.py` shows what it finds, and from where.

Why only German 1.20: the build takes the library's data and some of its
routines out of `AM2_CPU` by fixed offsets (chapter 9), and those were
read in that version. The extract checks each place against Thalion's
code around it, so another version or language makes the build stop with
a message instead of building something wrong.

Without the YM file the build goes on; the ST version is then silent,
the Falcon plays the original music anyway. If you name `AMBER_YMSNDH`
(variable or `build.cfg`) and the file is not there, the build stops,
because that is more likely a typo.

### Tools

| Tool | What for | Tested with |
|---|---|---|
| `vasmm68k_mot` (vasm, Motorola syntax) and `vlink`, by Volker Barthelmann and Frank Wille | assembling and linking every program | vasm 1.9a, vlink 0.17a |
| `a56`, the DSP56001 assembler | the Falcon's music mixer on the DSP; the ST build does not need it | Ubuntu package `a56` |
| an m68k `objdump` (GNU binutils) | `tools/am2cpu_code.py` disassembles Thalion's routines in `AM2_CPU` with it | `m68k-atari-mintelf-objdump` |
| Python 3, standard library only | all extracts and checks | 3.14; the code needs 3.9 or newer |
| a POSIX shell (`sh`) and the usual command-line tools | the build scripts | `dash`, `bash` |

The m68k `objdump` is looked for in this order: the variable
`AMBER_OBJDUMP` (variable or `build.cfg`); `m68k-atari-mintelf-objdump`,
`m68k-atari-mint-objdump`, `m68k-amiga-elf-objdump`,
`m68k-linux-gnu-objdump` in the `PATH`; the binary inside the VS Code
extension *atari-st-dev*, for Linux or macOS. Any other name works
through `AMBER_OBJDUMP`.

## Linux

The example is Ubuntu; other distributions need the same tools under
their own package names.

1. **Packages:**

   ```bash
   sudo apt install python3 a56 binutils-m68k-linux-gnu build-essential git
   ```

   `binutils-m68k-linux-gnu` brings `m68k-linux-gnu-objdump`;
   `build-essential` is for compiling vasm and vlink.

   *Check:* `a56` alone prints a line `usage: a56 …`;
   `m68k-linux-gnu-objdump --version` names its version.

2. **vasm and vlink** from their sources
   ([vasm](http://sun.hasenbraten.de/vasm/),
   [vlink](http://sun.hasenbraten.de/vlink/)). Unpack each, then:

   ```bash
   make CPU=m68k SYNTAX=mot
   ```

   in the vasm folder (it builds `vasmm68k_mot`) and

   ```bash
   make
   ```

   in the vlink folder. Put both binaries into a folder in your `PATH`,
   for instance `~/.local/bin`.

   *Check:* `vlink` alone prints `vlink V0.17a …` or newer;
   `vasmm68k_mot` alone complains that there is no input file and then
   names its version, `vasm 1.9a …` or newer.

3. **The repository and the paths:**

   ```bash
   git clone <repository URL> ambermoon && cd ambermoon
   ```

   Then either lay out `ambermoon_gamedata/` next to it as shown above,
   or

   ```bash
   cp build.cfg.example build.cfg
   ```

   and set `AMBER_DATEN`, `AMBER_URCODE` and, if you have it,
   `AMBER_YMSNDH` there (remove the `#` in front of each line you use).

   *Check:*

   ```bash
   python3 tools/paths.py
   ```

   shows each key with `found` or `missing`, and where the path came
   from. `AMBER_DATEN` and `AMBER_URCODE` must say `found`.

4. **Build:**

   ```bash
   sh tools/build_all.sh
   ```

   The build shows one line per step: its name, a tick, the seconds and
   a short note. Everything else goes into `build/build.log`;
   `VERBOSE=1 sh tools/build_all.sh` shows all of it on the terminal.
   The first step, "Sources and switches", checks what the build takes
   from where. If something required is missing, the build stops right
   there (see "When the build stops" below).

   *Check:* the closing line says `Done in m:ss. No warnings.`,
   `ATARI/AMBER.TOS` exists, and `ATARI/AMBFILES/` holds `ENGINE.TOS`
   and `ENGINEST.TOS`.

## macOS

> Not tested.

No two paths in the repository differ only in case, so it clones onto
an ordinary macOS volume.

1. **Compiler and Python:** the Xcode command-line tools,

   ```bash
   xcode-select --install
   ```

   bring `make`, a C compiler, `git` and `python3`.

2. **vasm and vlink** from source, exactly as under Linux, step 2.

3. **objdump.** The simplest is the VS Code extension *atari-st-dev*:
   it ships a macOS binary (`sdk/darwin/opt/cross-mint/bin/`), and the
   build finds it there by itself. GNU binutils built for an m68k target
   work too; if their `objdump` has none of the names above, set
   `AMBER_OBJDUMP` in `build.cfg`.

   *Check:* `python3 tools/paths.py` lists `AMBER_OBJDUMP` as "not set,
   searched"; the build names the `objdump` it found under "Sources and
   switches".

4. **a56.** There is no ready package we know of. Its C source is small
   and public (for instance the source of the Ubuntu package `a56`);
   compile it and put `a56` into your `PATH`. Without it, build the ST
   only: `sh tools/build_st.sh`.

5. Paths and build as under Linux, steps 3 and 4.

## Windows

> Not tested. The way that should work is WSL, the Linux inside Windows.

The build is a set of shell scripts, so build inside WSL rather than in
Windows itself:

1. Install WSL with Ubuntu (in an administrator PowerShell):

   ```bash
   wsl --install -d Ubuntu
   ```

2. Open the Ubuntu terminal and follow **Linux**, steps 1 to 4.
   **Clone into your WSL home folder** (`~/…`), not under `/mnt/c/…`:
   there a Windows git cannot turn the line ends of the shell scripts
   into CR LF, and the build reads its files much faster.

3. Thalion's source and the game files may stay on the Windows side;
   point `build.cfg` at them through `/mnt/c/…`, for instance
   `AMBER_DATEN=/mnt/c/Games/ambermoon_german_1.20`. Or copy them into
   `ambermoon_gamedata/` next to the repository in WSL, which also reads
   faster.

4. The result is in `ATARI/` inside WSL. In the Windows Explorer it is
   under `\\wsl$\Ubuntu\home\<user>\ambermoon\ATARI`; copy it from there
   to the card or disk for the Atari.

Building natively under Windows (Git Bash, MSYS2) has not been tried and
is not planned.

## What comes out

```
ATARI/AMBER.TOS           the loader: start this, on the Falcon or the ST
ATARI/AMBFILES/           the programs of both machines, the game files
                          under 8.3 names, the save games, AMBER.INF
build/                    everything intermediate; never part of the repository
```

Copy the whole `ATARI/` folder to the Atari and start `AMBER.TOS`. It
reads which machine it runs on and starts the right programs. A fresh
folder starts a new game with the character editor, as on the Amiga.
Settings, such as `MUSIC=OFF`, go into `ATARI/AMBFILES/AMBER.INF`
(chapter 1).

`sh tools/build_falcon.sh` or `sh tools/build_st.sh` builds one machine
only; both write into the same `ATARI/`.

**A build empties `ATARI/`** apart from `*.INF` and the other machine's
programs, and that includes the save games. If you play from this folder,
copy your save games away before you build again.

## When the build stops

The step that failed is marked `✗ FAILED`, and below it come the last
25 lines of `build/build.log`; the whole log is still there afterwards.

- **"MISSING" under "Sources and switches"**: a path is wrong. The line
  among the last lines of the log shows what the build looked for and
  where the path came from (the variable, `build.cfg` or the default);
  fix it there.
- **`build.cfg line n: expected one of …`**: a line in `build.cfg` has a
  key the build does not know, or no `=`.
- **The extract from `AM2_CPU` stops**: the game files are not the German
  1.20, or `AM2_CPU` is not the one from that version.
- **Warnings**: each engine build has a few expected ones, vasm 22 once,
  vasm 58 four times, vlink 62 once, all in Thalion's files (chapter 9).
  The build counts them and does not show them. Any other warning, or a
  changed count, appears with a `!` under its step and in the closing
  line, and is worth a report. vasm warning 2028 stops the build on
  purpose.

## Open points of this draft

Not for publication; to settle before.

1. **a56 on macOS:** where to get it, tried by someone with a Mac.
2. **Python:** 3.9 is read from the code, not tried.
3. **Which game files exactly:** how a visitor gets from the disks or the
   hard-disk install to an unpacked `Amberfiles/`, and which release
   counts as "German 1.20".

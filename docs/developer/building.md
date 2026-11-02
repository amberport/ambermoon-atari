# Building it yourself

> **Draft** (Docs, 2026-11-02). Written for visitors of the published
> repository. Only the Linux way has been run so far; the macOS and
> Windows parts are worked out from the build scripts and are not tested.
> The open points are at the end.

This repository holds the Atari side of the port only: our library, the
build scripts and the tools. Thalion's source and the game are not in it
and never will be. The build reads them where they lie, takes what it
needs and writes a folder `ATARI/` that you copy to a Falcon030 or an
ST/STE.

**The short way is the [Quickstart in the README](../../README.md#quickstart):**
put the game files into `ambermoon_gamedata/` next to the repository and
run `sh tools/build_all.sh`. On Linux x86-64 the build fetches what else
it needs. It is also where the versions of the game are listed with how
far each is tested. This page is for everything else: what the build
looks for and where, the tools, other systems, and what to do when it
stops.

## What the build needs

### From outside the repository

| What | Where from | Key |
|---|---|---|
| The game files of one version | your own copy of the game | named on the command line, or `AMBER_DATEN` |
| Thalion's released source: the folder that holds `GAME_OFF.S`, `HULL/`, `MAP/` … | fetched by the build, or your clone of [jhorneman/ambermoon](https://github.com/jhorneman/ambermoon) | `AMBER_URCODE` |
| Optional: Big Alec's YM music, `big_alec/ambermon.snd` | by hand from the [SNDH archive](https://sndh.atari.org/?ID=5364); the build does not download it | `AMBER_YMSNDH`: the file itself |
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

The game files also have a shorter way: `sh tools/build_all.sh FILE`
names them for this build and wins over `AMBER_DATEN`. `FILE` is relative
to where you call the build, else to `ambermoon_gamedata/`.

`python3 tools/paths.py` shows what it finds, and from where.

### The game files

**Versions.** The build reads 1.01 German, 1.07 English, 1.20 German and
1.21 German, English and French, and finds out by itself which one it
has. No switch is needed. Polish and Czech 1.21 stop at the intro: their
intro is a different program.

**Forms.** Whatever names the game files (`FILE` or `AMBER_DATEN`) may be:

- the folder *above* `Amberfiles/`, the `Amberfiles` folder itself, or a
  folder with one of these somewhere below it;
- disk images: a folder with the ADF, DMS or IPF files of one version, or
  one of those files (then its folder counts). DMS needs the program `xdms`;
- a zip holding any of these, as downloaded.

Zips and disks are unpacked once per content into `build/game_files/`;
nothing is ever written next to your files. If nothing names the game
files and the default folder is missing, the build searches
`ambermoon_gamedata/` for one set. With several sets it stops and lists
them; name one.

**A build fits the game files it was built from.** The engine compares
the version lines of the `Text.amb` it loads with those it was built for.
If they differ, it says on the text screen what it was built for and what
it found, waits for a key and goes back to the desktop.

Without the YM file the build goes on; the YM stays silent, and the ST
has no music. If you name `AMBER_YMSNDH` (variable or `build.cfg`) and
the file is not there, the build stops, because that is more likely a
typo.

### Thalion's source

If `AMBER_URCODE` is not set and the source is not at its default place,
the build takes, in this order:

1. a clone in `ambermoon_gamedata/` (a folder that holds `src/GAME_OFF.S`);
2. a zip of it there (GitHub's "Download ZIP", or the archive the build
   keeps from a download);
3. the tested commit from GitHub, kept as a zip in `ambermoon_gamedata/`,
   through `git` if the archive cannot be downloaded.

The files are checked against a SHA-256 of the tested state. A download
that differs stops the build; a clone or zip that differs is a warning,
since a newer state may build as well. The source is only read, and it
never goes into this repository. A path you set yourself is taken as it
is, and is neither fetched nor checked.

**`AMBER_DOWNLOAD=NO`** (variable or `build.cfg`) forbids every download:
Thalion's source and vasm and vlink.

### Tools

| Tool | What for | Where from |
|---|---|---|
| `vasmm68k_mot` (vasm, Motorola syntax) 1.9a and `vlink` 0.17a, by Volker Barthelmann and Frank Wille | assembling and linking every program | fetched on Linux x86-64; elsewhere [from their sources](#vasm-and-vlink-from-their-sources) |
| an m68k `objdump` (GNU binutils) | `tools/am2cpu_code.py` disassembles Thalion's routines in `AM2_CPU` with it | required, see below |
| Python 3, standard library only | all extracts and checks | required; tested with 3.14, the code needs 3.9 or newer |
| a POSIX shell (`sh`) and the usual command-line tools | the build scripts | `dash`, `bash` |
| optional: `xdms` | game files as DMS images | Ubuntu package `xdms` |
| optional: `a56`, the DSP56001 assembler | only if you change the Falcon's music mixer | Ubuntu package `a56` |
| optional: Pillow, the Python imaging library | only the palette check page `build/palette_editor/index.html`. Without it the ST build gives one warning and leaves the page out; the game files are the same | Ubuntu package `python3-pil` |

**vasm 2.0f does not build this project.** It reports warning 40 for
Thalion's label `Touch:` and warning 53 for our macros `rseven` and
`LOCAL`, and the cross-check of `opt t-` in `build_engine.sh` wants exactly
one message. A vasm other than
1.9a gives a warning at the first step.

**Where the tools are looked for:** `ambermoon_gamedata/bin/`, then
`ambermoon_gamedata/vbcc/bin/` (the [vbcc package](http://www.ibaug.de/vbcc/vbcc_linux_x64.tar.gz)
unpacked there), then the `PATH`. The first step, "Sources and switches",
shows each tool with where it came from.

**vasm or vlink found nowhere:** on Linux x86-64 the build takes the two
programs out of the vbcc package, a copy lying in `ambermoon_gamedata/` or
a download of about 32 MB. They are checked against their SHA-256; a
difference stops the build. Only the two programs are kept, in
`ambermoon_gamedata/bin/`.

**`a56`:** the assembled mixer lies in the repository as
`musik/musik_dsp.dsp`, our own code. Without `a56` the build takes it. With
`a56` the build assembles `musik/MUSIK_DSP.A56` and the result must equal
that file, or it stops. The ST build does not use the DSP at all.

The m68k `objdump` is looked for in this order: the variable
`AMBER_OBJDUMP` (variable or `build.cfg`); `m68k-atari-mintelf-objdump`,
`m68k-atari-mint-objdump`, `m68k-amiga-elf-objdump`,
`m68k-linux-gnu-objdump` in the `PATH`; the binary inside the VS Code
extension *atari-st-dev*, for Linux or macOS. Any other name works
through `AMBER_OBJDUMP`.

### vasm and vlink from their sources

Needed on any system but Linux x86-64. Take the tested versions, not the
newest:
[vasm 1.9a](http://phoenix.owl.de/tags/vasm1_9a.tar.gz) and
[vlink 0.17a](http://phoenix.owl.de/tags/vlink0_17a.tar.gz). Unpack each,
then:

```bash
make CPU=m68k SYNTAX=mot
```

in the vasm folder (it builds `vasmm68k_mot`) and

```bash
make
```

in the vlink folder. Put both binaries into `ambermoon_gamedata/bin/` or
into a folder in your `PATH`.

*Check:* `vlink` alone prints `vlink V0.17a …`; `vasmm68k_mot` alone
complains that there is no input file and then names its version,
`vasm 1.9a …`.

## Linux

The example is Ubuntu; other distributions need the same tools under
their own package names.

1. **Packages:**

   ```bash
   sudo apt install python3 binutils-m68k-linux-gnu
   ```

   `binutils-m68k-linux-gnu` brings `m68k-linux-gnu-objdump`. Add `xdms`
   for DMS images, `a56` if you will change the mixer, `python3-pil` for
   the palette check page, and `build-essential` if you are not on x86-64
   and have to compile vasm and vlink.

   *Check:* `m68k-linux-gnu-objdump --version` names its version.

2. **The repository and the game files:**

   ```bash
   git clone <repository URL> ambermoon-atari && cd ambermoon-atari
   ```

   Put the game files into `ambermoon_gamedata/` next to it:

   ```
   somewhere/
     ambermoon-atari/                    this repository
     ambermoon_gamedata/
       ambermoone.zip                    the game files, in any form above
       ambermon.snd                      optional, Big Alec's YM music
   ```

   Thalion's source, vasm and vlink land there too. To keep things
   elsewhere,

   ```bash
   cp build.cfg.example build.cfg
   ```

   and set the keys there (remove the `#` in front of each line you use).

   *Check:*

   ```bash
   python3 tools/paths.py
   ```

   shows each key with `found` or `missing`, and where the path came from.
   `missing` is not an error for what the build can find or fetch itself.

3. **Build:**

   ```bash
   sh tools/build_all.sh
   ```

   The build shows one line per step: its name, a tick, the seconds and
   a short note. Everything else goes into `build/build.log`;
   `VERBOSE=1 sh tools/build_all.sh` shows all of it on the terminal.
   The first step, "Sources and switches", checks what the build takes
   from where. If something required is missing, the build stops right
   there (see "When the build stops" below).

   *Check:* the closing lines say `Done in m:ss. No warnings.` (without
   Pillow, its one warning) and `Built: Ambermoon Atari …` with the version
   of your game files,
   `ATARI/AMBER.TOS` exists, and `ATARI/AMBFILES/` holds `ENGINE.TOS` and
   `ENGINEST.TOS`.

## macOS

> Not tested.

No two paths in the repository differ only in case, so it clones onto
an ordinary macOS volume.

1. **Compiler and Python:** the Xcode command-line tools,

   ```bash
   xcode-select --install
   ```

   bring `make`, a C compiler, `git` and `python3`.

2. **vasm and vlink** [from their sources](#vasm-and-vlink-from-their-sources).
   The vbcc package the build fetches on Linux is for Linux x86-64 only.

3. **objdump.** The simplest is the VS Code extension *atari-st-dev*:
   it ships a macOS binary (`sdk/darwin/opt/cross-mint/bin/`), and the
   build finds it there by itself. GNU binutils built for an m68k target
   work too; if their `objdump` has none of the names above, set
   `AMBER_OBJDUMP` in `build.cfg`.

   *Check:* `python3 tools/paths.py` lists `AMBER_OBJDUMP` as "not set,
   searched"; the build names the `objdump` it found under "Sources and
   switches".

4. Repository, game files and build as under Linux, steps 2 and 3. Without
   `xdms`, use the game files as a zip of ADF or IPF images, or as a folder.

## Windows

> Not tested. The way that should work is WSL, the Linux inside Windows.

The build is a set of shell scripts, so build inside WSL rather than in
Windows itself:

1. Install WSL with Ubuntu (in an administrator PowerShell):

   ```bash
   wsl --install -d Ubuntu
   ```

2. Open the Ubuntu terminal and follow **Linux**, steps 1 to 3.
   **Clone into your WSL home folder** (`~/…`), not under `/mnt/c/…`:
   there a Windows git cannot turn the line ends of the shell scripts
   into CR LF, and the build reads its files much faster.

3. The game files may stay on the Windows side; name them through
   `/mnt/c/…`, for instance
   `sh tools/build_all.sh /mnt/c/Games/ambermoone.zip`. Or copy them into
   `ambermoon_gamedata/` next to the repository in WSL.

4. The result is in `ATARI/` inside WSL. In the Windows Explorer it is
   under `\\wsl$\Ubuntu\home\<user>\ambermoon-atari\ATARI`; copy it from
   there to the card or disk for the Atari.

Building natively under Windows (Git Bash, MSYS2) has not been tried and
is not planned.

## What comes out

```
ATARI/AMBER.TOS           the loader: start this, on the Falcon or the ST
ATARI/AMBFILES/           the programs of both machines, the game files
                          under 8.3 names, the save games, AMBER.INF,
                          BUILD.TXT (the build's name)
build/                    everything intermediate; never part of the repository
```

Copy the whole `ATARI/` folder to the Atari and start `AMBER.TOS`. It
reads which machine it runs on and starts the right programs. A fresh
folder starts a new game with the character editor, as on the Amiga.
Settings, such as `MUSIC=OFF`, go into `ATARI/AMBFILES/AMBER.INF`
(chapter 1).

`sh tools/build_falcon.sh` or `sh tools/build_st.sh` builds one machine
only; both write into the same `ATARI/`, and both take the game files on
the command line too. `TESTBUILDS=1 sh tools/build_all.sh` also builds
the test versions of the intros and the extro (chapter 9).

**A build empties `ATARI/`** apart from `*.INF` and the other machine's
programs, and that includes the save games. If you play from this folder,
copy your save games away before you build again.

## When the build stops

The step that failed is marked `✗ FAILED`, and below it come the last
25 lines of `build/build.log`; the whole log is still there afterwards.

- **"MISSING" or "NOT FOUND" under "Sources and switches"**: a path is
  wrong, or a download failed. The lines just above or among the last
  lines of the log show what the build looked for and where the path came
  from (the variable, `build.cfg`, the command line or the default); fix
  it there.
- **Several sets of game files**: the build lists them. Name one:
  `sh tools/build_all.sh FILE`.
- **`build.cfg line n: expected one of …`**: a line in `build.cfg` has a
  key the build does not know, or no `=`.
- **A version the tables do not know**: the extract from `AM2_CPU` or
  the intro's table stops the build, and the message names the tool that
  makes the table. This is what Polish and Czech 1.21 do at the intro.
- **The step "Engine" stops with a second message from `opt t-`**: probably
  a vasm other than 1.9a. The first step has warned about it.
- **`musik/musik_dsp.dsp is not what a56 makes`**: you changed the mixer.
  `cp build/musik_dsp.dsp musik/musik_dsp.dsp`, and commit it with the
  source.
- **Warnings**: each engine build has a few expected ones, vasm 22 once,
  vasm 58 four times, vlink 62 once, all in Thalion's files (chapter 9).
  The build counts them and does not show them. Any other warning, or a
  changed count, appears with a `!` under its step and in the closing
  line, and is worth a report. vasm warning 2028 stops the build on
  purpose.

## Open points of this draft

Not for publication; to settle before.

1. **macOS and Windows:** neither has been tried; vasm and vlink from their
   sources were not compiled for this page, only their archives checked.
2. **Python:** 3.9 is read from the code, not tried.
3. **The `apt` line:** the one in step 1, the same as the README's, was
   not run on a fresh system. The build itself was run from a folder
   without `.git`, without `a56`, vasm and vlink in the `PATH`, with its
   `objdump` from the VS Code extension.

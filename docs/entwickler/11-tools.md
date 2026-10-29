# 11. Tools

Everything in `tools/` runs on the host, not on the Atari, except the
small Atari programs in their own folders (`tools/bomben/`,
`tools/st_rand/`). The
Python tools need Python 3.9 or newer and the standard library only;
`PIL` is loaded only where a tool writes a picture. Most of them are
German inside, comments and messages; their header says what they are
for.

The tools fall into six groups:

1. **Paths and build**: where the outside material lies, and the build
   scripts.
2. **Build-time extracts**: what the build takes out of Thalion's files,
   so that nothing of Thalion's has to go into the repository.
3. **Reading the game data on the host**: the formats, for looking and
   for checking.
4. **Checks**: what runs after every build and what you call by hand.
5. **Testing, hardware and measuring**: the emulator, the test package,
   crash reports, save games, measuring versions.
6. **The ST's own tools**: palettes and the ST intros.

Chapter 9 says what the build does step by step and what each check
guarantees; `docs/16-Pruefwerkzeuge.md` (German) says where each check's
statement ends. This chapter is the index: what each tool is for, how
to call it, what it needs. Tools of earlier phases of the project,
which the build no longer runs, are archived and not described here.

**Outside material.** Most tools read Thalion's source (`AMBER_URCODE`)
or the game files (`AMBER_DATEN`). They ask `tools/paths.py` for both
(chapter 1). Whatever a tool writes from them goes to `build/` or to a
folder you name, never into the repository.

## 1. Paths and build

| Tool | What for | Call |
|---|---|---|
| `paths.py` | where Thalion's source, the game files, the YM file, the TOS image and `objdump` lie: environment variable, then `build.cfg`, then `ambermoon_gamedata/` next to the repository. Every other tool imports it | `python3 tools/paths.py` shows each key, `found`/`missing` and where from; `--sh` gives shell assignments |
| `build_all.sh` | the one build, both machines into `ATARI/` | `sh tools/build_all.sh` |
| `build_falcon.sh`, `build_st.sh` | one machine each | `sh tools/build_falcon.sh` (needs `a56`), `sh tools/build_st.sh` |
| `build_common.sh` | the shared part: sources, extracts, delivery, source checks. Sourced by the two, not run | — |
| `build_engine.sh` | the engine from its two units: export lists, vasm, vlink | `sh tools/build_engine.sh ZIEL.TOS [OBJEKTORDNER]`; called by the builds |
| `musik_dsp.sh`, `dsp_lod.py` | the DSP mixer `musik/MUSIK_DSP.A56` with `a56`, and its output turned into the image `Dsp_ExecBoot` loads (at most 512 words, P memory only) | called by `build_engine.sh` and `amiga_bauen.sh` |
| `fantasy_bauen.sh` | the fantasy intro alone, into `build/` | `sh tools/fantasy_bauen.sh` |
| `amiga_bauen.sh` | intro or extro alone, into `build/` | `sh tools/amiga_bauen.sh intro\|extro` |
| `einheiten_verbinden.py` | the export lists between `engine.s` and `spiel.s`; stops on a name in both units or in neither (finding 181) | called by `build_engine.sh` |
| `doku_listen.py` | appendices A–C of this documentation | every Falcon build writes them to `build/doku/`; `--docs` writes them here, on `main` only |
| `originalcode/vorspann.i` | not a tool but the stand-in for Thalion's unreleased include file (chapter 4) | included by the build |

The partial builds write to `build/` only; only `build_falcon.sh` and
`build_st.sh` deliver to `ATARI/`.

## 2. Build-time extracts

Thalion's source does not contain the library, its data, the intro and
extro programs or the music player; they exist only as translated Amiga
programs in the game files. These tools take out what the build needs,
each piece at a place they check, and write it to `build/`. None of it
is read at run time, and none of it is committed. If a check fails, the
tool stops the build: another version or language of the game would
otherwise build into something wrong. Each deviation from the two goals
behind them is in `docs/17-deviations.md`.

| Tool | Takes | From | Writes |
|---|---|---|---|
| `am2cpu_auszug.py` | the library's data: main palette, window tiles, status bar, font … (table `STUECKE`) | `AM2_CPU` | `build/am2cpu_daten.i` |
| `am2cpu_code.py` | Thalion's pure memory routines: the 3D rasterisers, `Fade_colour`, `Lob_core` …, disassembled with `objdump` and checked (named relocations only, no jump out, no hardware address, 68000 only) | `AM2_CPU` | `build/am2cpu_code.i` |
| `am2cpu_lesen.py` | the reader under both: hunks, relocations, disassembly, the names (`NAMEN`); also by hand, group 3 | `AM2_CPU` | — |
| `textmarken.py` | where each of the library's texts lies in `Text.amb` (D5) | `Text.amb`, German 1.20 | `build/textmarken.i` |
| `intro_auszug.py` | the texts of the start menu (D4) | `Ambermoon_intro` | `build/intro_daten.i` |
| `ym_auszug.py` | Big Alec's YM player and pieces, Timer B bound back to Timer D, checked by SHA-256 against the block tested on the hardware | `ambermon.snd` (`AMBER_YMSNDH`) | `build/MUSIK_YM.BIN` |
| `amiga_programm.py` | intro and extro: hunks, K1 (hardware operands), K2 (`BLTSIZE` → trap), K3 (our hooks); every place is in `PROGRAMME` | `Ambermoon_intro`, `Ambermoon_extro` | `build/<name>_hunks.i` |
| `musik_k1.py` | K1 for the music player that intro and extro load at run time: its 27 hardware operands | `Intro_music`, `Extro_music` | a table for the intro and extro build |
| `fantasy_auszug.py` | the fantasy intro's graphics, data and constants, checked against Thalion's `FAIRY.S` | `Fantasy_intro` | `build/fantasy_*.bin`, `build/fantasy_*.i` |
| `fairy_umbiegen.py` | K1 after linking: the ten `$DFFxxx` operands of `FAIRY.S` in `FANTASY.TOS`, put on `Amiga_register` and into the relocation table | the linked program | `FANTASY.TOS` in place |
| `imploder_exe.py`, `imploder.py` | the Imploder unpacker: whole programs (`Fantasy_intro`, `Ambermoon_extro`) and `IMP!` data blocks, carried over instruction by instruction from Thalion's intro | — | used by the tools above |
| `ambchest.py` | not an extract: checks our item offsets against the `rsreset` in Thalion's `GAME_OFF.S` | Thalion's source | — |

Chapter 9 says how to add a new piece from `AM2_CPU`; appendix C lists
all of them with their places. Chapter 10 explains K1, K2 and K3.

## 3. Reading the game data on the host

| Tool | What for | Call |
|---|---|---|
| `ambtool.py` | the containers (`AMNC`, `AMNP`, `AMPC`, `AMBR`), JH, LOB, Amiga hunks, palettes, planar graphics. The reference the Atari code was checked against over all game data (guide chapter 3); most other tools import it | `python3 tools/ambtool.py info FILE …`, `extract FILE DIR`, `hunks FILE [DIR]`, `palettes FILE [--json F] [--png F]`, `gfx FILE DIR --width W --planes N --palette-file Palettes.amb [--palette n] [--height H]` |
| `am2cpu_lesen.py` | read a contract in `AM2_CPU` when the call sites do not show it (finding 194) | `hunks`; `dis NAME`; `dis 0:C4A2 -n 8`; `dis 0:20000 --bis 0:2E000`; `wer 4:76BA` (who jumps there); `suche HEXBYTES`; `daten 4:76A8 -l 40` |
| `ambmap.py` | the map format (`nMap_data.amb`): header, tiles, events; a module, imported by others | — |
| `ambchest.py` | chests, items and their icons; a module, and the offset check of group 2 | `python3 tools/ambchest.py` runs the check |
| `sa_auszug.py` | Thalion's 32 songs from `Music.amb` as Sonic Arranger files, to listen to on the PC (UADE, for instance); not for the build | `python3 tools/sa_auszug.py [--amberfiles DIR] [--out build/sa] [--roh]` |
| `ussref.py` | Amiga memory dumps (FS-UAE/WinUAE `.uss`) as an independent reference: the picture from the copper list, the colours, which map is loaded (docs/16) | a module; `find_sprites` and the readers are called from scripts |

Start with `am2cpu_lesen.py dis` close to the place you want: from `0:0`
the disassembly loses its step. A name you add goes into `NAMEN`.

## 4. Checks

The four source checks read only our code. `build_common.sh` runs them
after every build; each also runs on its own, without a build:

| Tool | Finds |
|---|---|
| `trap_pruefen.py` | a bare `trap #1/#13/#14` in `engine/src` outside the `Gemdos`/`Bios`/`Xbios` macros; TOS destroys d0–d2/a0–a2 (finding 270) |
| `register_pruefen.py` | a routine of ours that writes a register it did not save; return values are listed in `AUSNAHMEN`; it does not see macros |
| `vars_pruefen.py` | two `a5` variables in `FALCON_OFF.S` on the same place |
| `platzhalter_pruefen.py` | a placeholder in the code block of a `*_STUBS.S` that Thalion addresses with `lea` |

Two more need the XDEF lists of a Falcon build in `build/` and write
their report there:

| Tool | Says | Writes |
|---|---|---|
| `platzhalter_karte.py` | which call paths of Thalion's code still lead to a placeholder (none today) | `build/platzhalter.txt` |
| `vollprobe.py` | all of Thalion's files assembled together: which names are still missing, the full list of what Thalion never released | `build/vollprobe.txt` |

All are called as `python3 tools/<name>.py` from the repository root.

## 5. Testing, hardware and measuring

| Tool | What for | Call |
|---|---|---|
| `hatari/teste.sh` | runs the delivered build in Hatari without a window and takes screenshots; good for "does it crash" and "is the picture right", not for timing on the Falcon or for the mouse (`hatari/LIESMICH.txt`) | `sh tools/hatari/teste.sh [-m rgb\|vga] [-v 800,2000] [-p PROGRAM]`; needs `AMBER_TOS` |
| `testpaket.py` | the test package: collects the test builds of all working trees, by their tables `tools/testpaket_<branch>.tab`, into one folder `ATARI/` with one `TESTS.TXT` | `zeigen`; `ordner [PATH]`; `karte TARGET [--echt]`; `falcon [--echt] [--pruefen]` (over uIPtool). Acts only with `--echt`; save games and `*.INF` are never touched |
| `bomben/bomben.s` → `ATARI/BOMBEN.TOS` | after a crash on the Atari: shows and writes to `BOMBEN.TXT` what TOS saved at `$380` (PC, access address, registers, the exception frame); PC minus the load address that `ENGINE.TOS` shows is the offset in the symbol map (chapter 9) | built and delivered by both builds; start it from the desktop after the bombs |
| `spielstand_setzen.py` | moves a copy of a save game to another map, place and direction, to start a test there; with `--saves` also a copy of `SAVES`, so "continue" loads it | `python3 tools/spielstand_setzen.py --ziel DIR --platz 9 --karte 260 --x 28 --y 8 --richtung 0 --name "NAME" [--quelle DIR] [--saves FILE]` |
| `musik_messbau.sh` | three measuring versions of the engine, without music, mixer on the CPU, mixer on the DSP; each writes frames, VBLs and the time in `Musik_vbl` to `MESS_OHN.TXT`, `MESS_CPU.TXT`, `MESS_DSP.TXT` | `sh tools/build_falcon.sh && sh tools/musik_messbau.sh` |
| `mess_auswerten.py` | reads the file of an intro or fantasy intro measuring version (`*.MES`: where Timer A found the program, per second blits, display and the rest) with its link map | `python3 tools/mess_auswerten.py FILE.MES build/NAME.map [--verlauf]` |

The diagnostic switches (`VASM_EXTRA="-D…"`, chapter 9) are the other
half of this group: they build a version that measures or provokes one
thing.

A save game the user plays from `ATARI/AMBFILES/` is gone after the next
build; copy it away first.

## 6. The ST's own tools

These belong to the ST work and are described in `docs/12-ST-Port.md`;
here only what they are for.

| Tool | What for |
|---|---|
| `st_palettes.py` | the ST palettes: Thalion's 32 colours on 16 registers, recomputed like `St_bauen` in `ST_LIB.S`. `build` writes `STPAL.DAT` with the hand corrections from `st_palettes.txt` (deviation D1; called by `build_st.sh`); `sheet` writes a review page `build/st_palettes/index.html`; `ramp`, `screen`, `measure` compare with and without the ramp protection |
| `st_palettes.txt` | the hand corrections, read by `st_palettes.py build` |
| `farbreduktion.py` | the first study of 32 to 16 colours (`messen`, `bild`); `st_palettes.py` still imports it |
| `fantasy_st_build.sh`, `fantasy_st_data.py` | the ST fantasy intro `FANTSYST.TOS`: Thalion's unchanged `FAIRY.S`, graphics in ST format; called by `build_st.sh` |
| `intro_st_build.sh`, `intro_st_program.py` | the ST intro `INTROST.TOS` with its own K3 hooks; on its own for now, not delivered |
| `st_shot.py` | `SHOTnn.RAW` of the ST intro's test build (key S) as a PNG |
| `st_rand/` | probe programs for the lower border on the ST, at three delays |

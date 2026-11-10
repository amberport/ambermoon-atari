# Release notes

## 0.8.5

### Faster 3D on both machines

To speed up 3D, some of Thalion's 3D code is now replaced by our own. What changed, how much it gains and how to switch each part back to Thalion's code at build time is in [docs/17-deviations.md](docs/17-deviations.md).

Optional: `COARSE_WALLS=YES` in `AMBER.INF` draws the walls coarser while the view moves and sharp again when it stands. Off by default.

### ST colours

- Combat: the tactic field is brown and no longer too bright.
- Most map and combat palettes are reduced by how much of each colour the game shows, so large areas keep their colour.
- Lyramion: the sea is blue instead of grey, and the greens are easier to tell apart.
- Entering a town at night no longer gives wrong colours at dawn.
- YM music: Grandfather's house stays silent, as the piece played there has no YM version. `AMBFILES\MUSIK_YM.INF` says which YM piece plays where and can be changed.
- A palette editor page for corrections of your own: the ST build writes it to `build/palette_editor/index.html`.

### Fixes and machines

- 2D maps: after about ten minutes of standing still the party could not move any more. This bug is in the original; the port now works around it.
- Mega STE at 16 MHz: the intro and the fantasy intro crashed. For now they switch to 8 MHz and set the clock back at the end; the game runs at the clock you set. Not tested on the hardware yet, and to be looked at again later.
- Falcon with a CT60: first test. The game runs, but 3D is about as fast as on the 68030. TT-RAM (Alt-RAM) is not used yet.

### Building and installing

- Prebuilt binaries, one package per game version. To install them, run the Python tool `install.py` from the package on a PC: it copies your own game files (a zip or disk images) next to the programs and adds the YM music if you have it. On an update it also takes over your save games. It needs only Python 3.
- Pillow is no longer needed. node is needed only for a check of the palette editor; without it the build warns.
- `objdump` is found under more names, with hints for macOS.

## 0.8

### More versions of the game

The port used to build only from the German 1.20. It now also builds from these versions:

| version | from |
|---|---|
| 1.01 German, 1.07 English | Thalion's disks |
| 1.21 German, English, French | Pyrdacor |

- All of them were tested in Hatari, and several on a real Falcon and ST, saving and loading included. The complete game has not been played through on any of them.
- 1.21 Polish and Czech do not work yet: their intro is a different program.
- A build fits only the game files it was built from. If the two do not match, the game says so at the start and names both versions.
- The start line and `AMBFILES\BUILD.TXT` name the build and its game files. Please quote that line in bug reports.

### A simpler build

- **Game files in any common form:** a zip as downloaded, disk images (ADF, IPF, or DMS with `xdms`) or a folder. With several versions at hand, name one: `sh tools/build_all.sh ambermoone.zip`.
- **Less to fetch by hand:** the build downloads Thalion's source code once. On Linux x86-64 it also downloads `vasm` and `vlink` if they are missing. Everything downloaded is checked against a checksum.
- **`a56` is optional:** the assembled music mixer for the Falcon is now in the repository.
- **A tidier `ATARI/` folder:** it holds only what a player needs. The measuring and test programs are built only with `TESTBUILDS=1`.

Still needed: Python 3 and an m68k `objdump`. `vasm` 2.0f does not build the project yet, so use 1.9a. Linux is tested; macOS and Windows/WSL are not.

The steps are in the [Quickstart](README.md#quickstart).

# Release notes

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

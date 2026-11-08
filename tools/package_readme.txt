Ambermoon for the Atari Falcon030 and ST/STE
@BUILD@
Programs for: @GAME@

An unofficial fan project. It is not affiliated with Thalion or with the
current rights holders. Source and documentation:
https://github.com/amberport/ambermoon-atari

This package holds the programs only, not the game. You need your own copy of
the Amiga game files, of exactly the version named above. A small tool on your
PC puts them into place.


WHAT YOU NEED

- An Atari Falcon030, or an ST/STE with 4 MB, and a hard disk.
- A PC with Python 3 (https://www.python.org).
- The game files, in any of these forms: the zip as downloaded, the disk images
  (ADF, IPF or DMS), or the folder Amberfiles.


INSTALLING

1. Unpack this zip on the PC.

2. In a terminal, in the unpacked folder, name your game files:

       python3 install.py PATH_TO_YOUR_GAME_FILES

   On Windows the command is usually "py" instead of "python3". The tool checks
   the files and their version first and copies them into ATARI\AMBFILES under
   the short names the programs ask for. Your copy stays as it is.

3. Copy the folder ATARI to the Atari's hard disk.

4. Start ATARI\AMBER.TOS. The one folder serves both the Falcon and the ST.


MUSIC

The Falcon plays the game's own music. The ST plays Big Alec's YM version, which
is not in this package either. Without it the ST stays silent. Download the file
of the entry "Big Alec: Ambermoon" (ambermon.snd or Ambermoon.sndh) from

    https://sndh.atari.org/?ID=5364

and put it beside install.py before you run the tool; it finds the file there.
It can also come later, on its own:

    python3 install.py --ym "Ambermoon.sndh"

Settings, such as MUSIC=YM on the Falcon, are in ATARI\AMBFILES\AMBER.INF.


UPDATING

Your save games are in ATARI\AMBFILES. For a new release, copy the folder ATARI
from the Atari back to the PC, unpack the new package into a new folder and
name the old ATARI folder too:

    python3 install.py PATH_TO_YOUR_GAME_FILES --saves PATH_TO_THE_OLD_ATARI

The tool takes your save games and settings (AMBER.INF, the YM music) from
there. Then replace the folder ATARI on the Atari with the new one.

If the tool finds save games it would replace, it asks first. On yes it copies
them to a folder saves-DATE-TIME beside ATARI before it replaces them.


PROBLEMS

Known limitations are listed in the README of the repository above. To report a
bug, open an issue there and name your machine, TOS, monitor, and the first line
of ATARI\AMBFILES\BUILD.TXT.


WHOSE WORK THIS IS

These programs are not only my work. They contain Thalion's code, assembled from
Thalion's source, and parts of Thalion's Amiga programs, including graphics; the
versions 1.20 and 1.21 also carry Pyrdacor's work on them. I offer them so that
people who cannot build the port themselves can play it on their Ataris.

It is unknown who holds the rights to the games published by Thalion Software.
If you can make a credible claim to these rights and do not want these programs
offered, open an issue in the repository above and I will take them down.

No rights are claimed, explicitly or implicitly, except the moral rights of the
developers of Ambermoon, and of the authors of this port, to be identified as
such. This is not a license, and no rights are granted.

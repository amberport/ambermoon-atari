#!/usr/bin/env python3
"""install.py -- put your own game files next to the ready-built programs.

A release package holds the programs of one game version, never the game
files.  This tool copies them from your copy into ATARI/AMBFILES/, under the
8.3 names the programs ask for.  Your copy stays as it is.  Run it on the PC,
before anything goes onto the Atari's disk: many Amiga names do not fit a FAT
file system.

    python3 install.py GAME_FILES [--ym ambermon.snd] [--saves OLD_ATARI]

GAME_FILES is what you have: the Amiga folder Amberfiles, a folder above it, a
zip as downloaded, or the disk images (a folder with the ADF, DMS or IPF
files, or one of them).

--ym takes Big Alec's YM music, which the package does not hold either (the
file big_alec/ambermon.snd of the SNDH archive, README.TXT).  Without it the ST
has no music.  It can come later, on its own: install.py --ym ambermon.snd
Without --ym the tool looks for it itself: any *.snd or *.sndh beside
install.py, in the current folder and beside the game files, whose SNDH header
names Ambermoon.

--saves takes the save games and settings (AMBER.INF, MUSIK_YM.BIN) of an
older installation, for a new release: unpack the new package, run install.py
with the same game files and --saves naming the old ATARI folder.

Then copy the folder ATARI/ to the Atari and start AMBER.TOS.

Checks first, copies afterwards:
- the files are all there;
- their version is the one the programs were built for (AMBFILES/BUILD.TXT,
  the same comparison ENGINE.TOS makes at the start);
- save games and settings in the target that would change: it asks, and on
  yes copies them to a folder saves-DATE-TIME beside ATARI/ first.  Without a
  terminal it stops; --force replaces them without the question, after the
  same copy.  Programs and game files are replaced without a question: every
  version has the same names.

Thalion's disks (1.01, 1.07) lack files of 1.2x; tools/thalion_prepare.py
makes them in a temporary folder, as in the build (DEVIATION (goal 2),
docs/17-deviations.md D7).

Usage: install.py [GAME_FILES] [--ym FILE] [--saves OLD_ATARI]
                  [--target ATARI/AMBFILES] [--force]
"""
import argparse
import contextlib
import filecmp
import io
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
# in a package the tools lie in tools/ below this file, in the repository
# beside it
TOOLS = os.path.join(HERE, "tools")
if not os.path.isdir(TOOLS):
    TOOLS = HERE
sys.path.insert(0, TOOLS)

import game_files                                  # noqa: E402
import game_names                                  # noqa: E402
from build_name import game_files_version          # noqa: E402


class Error(SystemExit):
    def __init__(self, text):
        super().__init__("ERROR: " + text)


def find_amberfiles(path, temp):
    """The Amberfiles folder in what the user names; zips and disk images are
    read into temp."""
    # any name will do; game_files.py would make a link for it, which Windows
    # may refuse
    if os.path.isfile(os.path.join(path, "AM2_CPU")):
        return path
    try:
        above, _ = game_files.resolve(os.path.abspath(path), os.path.join(temp, "read"))
    except (game_files.Error, OSError) as e:
        raise Error(str(e))
    return os.path.join(above, "Amberfiles")


def prepare_old(amberfiles, temp):
    """Thalion's 1.0x laid out as 1.2x; for 1.2x the folder itself."""
    r = subprocess.run([sys.executable, os.path.join(TOOLS, "thalion_prepare.py"),
                        "--amberfiles", amberfiles, "--out", os.path.join(temp, "laid_out")],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode:
        raise Error("the files of %s could not be laid out:\n%s"
                    % (amberfiles, r.stderr.decode("latin1")))
    made = r.stdout.decode().strip()
    return os.path.join(made, "Amberfiles") if made else amberfiles


def plan(amberfiles, target):
    """Every copy as (source, target); stops if a source is missing."""
    copies = [(os.path.join(amberfiles, a), os.path.join(target, b))
              for a, b in game_names.GAME_FILES]
    for slot in range(game_names.SAVE_SLOTS):
        for a, b in game_names.SAVE_FILES:
            copies.append((os.path.join(amberfiles, "Save.%02d" % slot, a),
                           os.path.join(target, "SAVE.%02d" % slot, b)))
    for a, b in game_names.SAVE_FILES:
        copies.append((os.path.join(amberfiles, "Save.00", a),
                       os.path.join(target, b)))
    missing = [q for q, _ in copies if not os.path.isfile(q)]
    if missing:
        raise Error("files missing: %d, the first is %s" % (len(missing), missing[0]))
    return copies


def built_for(target):
    """The game files named in BUILD.TXT, or None."""
    try:
        with open(os.path.join(target, "BUILD.TXT"), encoding="latin1") as f:
            for line in f:
                if line.startswith("for the game files "):
                    return line[len("for the game files "):].strip()
    except OSError:
        pass
    return None


def check_version(amberfiles, target):
    """As tools/build_name.py writes it into BUILD.TXT."""
    built = built_for(target)
    if built is None:
        raise Error("BUILD.TXT does not name the game files")
    with contextlib.redirect_stderr(io.StringIO()):     # its notes
        lines = game_files_version(amberfiles)
    found = " ".join(bytes(c for c in v if c >= 32).decode("latin1") for v in lines)
    if found != built:
        raise Error("these programs are for\n  %s\nbut your game files are\n  %s\n"
                    "Take the package of your version.  If there is none, try the same\n"
                    "language in another version, or build from the source (README.TXT)."
                    % (built, found))
    return found


def kept_names():
    """What belongs to the player, not to the package, below AMBFILES: the
    save games and the settings."""
    names = ["SAVES", "AMBER.INF", "MUSIK_YM.BIN"] + [b for _, b in game_names.SAVE_FILES]
    for slot in range(game_names.SAVE_SLOTS):
        names += [os.path.join("SAVE.%02d" % slot, b) for _, b in game_names.SAVE_FILES]
    return names


def ask(question):
    """True on y/yes/j/ja; False on anything else and without a terminal."""
    if not sys.stdin.isatty():
        return False
    try:
        answer = input(question + " [y/N] ")
    except EOFError:
        return False
    return answer.strip().lower() in ("y", "yes", "j", "ja")


def old_saves(path, copies, target, force):
    """--saves: the copies, with the player's files from the old AMBFILES in
    place of the fresh ones."""
    for old in (path, os.path.join(path, "AMBFILES"), os.path.join(path, "ATARI", "AMBFILES")):
        if os.path.isfile(os.path.join(old, "SAVES")):
            break
    else:
        raise Error("no save games in %s: name the old ATARI folder" % path)
    if os.path.samefile(old, target):
        raise Error("%s is this installation itself; name the old one" % path)
    was, now = built_for(old), built_for(target)
    text = ("the save games in %s are from\n  %s\nbut these programs are for\n  %s"
            % (old, was or "an unknown version", now))
    if was != now and not force and not ask(text[0].upper() + text[1:] + "\nTake them anyway?"):
        raise Error("nothing changed: %s\nTo take them anyway, add --force." % text)
    names = [n for n in kept_names() if os.path.isfile(os.path.join(old, n))]
    replaced = {os.path.join(target, n) for n in names}
    copies = [(q, z) for q, z in copies if z not in replaced]
    copies += [(os.path.join(old, n), os.path.join(target, n)) for n in names]
    inf = os.path.join(old, "MUSIK_YM.INF")
    if os.path.isfile(inf) and not filecmp.cmp(inf, os.path.join(target, "MUSIK_YM.INF"),
                                               shallow=False):
        print("Note: the old MUSIK_YM.INF differs from the new one; the new one stays.\n"
              "If you changed the old one yourself, copy it over by hand.")
    return copies


def replaced_kept(copies, target):
    """The player's files in the target that the copies would change.  Before
    the first installation there are none: AMBER.INF is then the package's."""
    if not os.path.isfile(os.path.join(target, "SAVES")):
        return []
    kept = {os.path.join(target, n) for n in kept_names()}
    return [z for q, z in copies
            if z in kept and os.path.isfile(z) and not filecmp.cmp(q, z, shallow=False)]


def back_up(files, target):
    """Copies files to a new folder saves-DATE-TIME beside ATARI/; -> folder."""
    above = os.path.dirname(os.path.dirname(os.path.abspath(target)))
    name = time.strftime("saves-%Y-%m-%d-%H%M")
    folder, n = os.path.join(above, name), 1
    while os.path.exists(folder):
        n += 1
        folder = os.path.join(above, "%s-%d" % (name, n))
    for z in files:
        to = os.path.join(folder, os.path.relpath(z, target))
        os.makedirs(os.path.dirname(to), exist_ok=True)
        shutil.copy2(z, to)
    return folder


def find_ym(game_files):
    """-> (Big Alec's SNDH or None, packed SNDH files seen, folders searched)."""
    folders = []
    for d in (HERE, os.getcwd(), game_files):
        if d and os.path.isfile(d):
            d = os.path.dirname(d)
        d = os.path.abspath(d) if d else None
        if d and os.path.isdir(d) and d not in folders:
            folders.append(d)
    packed = []
    for d in folders:
        for n in sorted(os.listdir(d)):
            f = os.path.join(d, n)
            if os.path.splitext(n)[1].lower() not in (".snd", ".sndh") or not os.path.isfile(f):
                continue
            with open(f, "rb") as h:
                head = h.read(256)
            if head[:4] == b"ICE!":
                packed.append(f)
            elif head[12:16] == b"SNDH" and b"TITLAmbermoon" in head:
                return f, packed, folders
    return None, packed, folders


def extract_ym(sndh, temp):
    """Big Alec's block from the SNDH; tools/ym_extract.py checks every place."""
    if not os.path.isfile(sndh):
        raise Error("%s: no such file" % sndh)
    out = os.path.join(temp, "ym")
    r = subprocess.run([sys.executable, os.path.join(TOOLS, "ym_extract.py"),
                        "--sndh", sndh, "--out", out],
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode:
        raise Error("%s: %s" % (sndh, r.stderr.decode("latin1").strip()))
    return os.path.join(out, "AMBERYM.BIN")


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("game_files", nargs="?", help="Amberfiles folder, zip or disk images")
    p.add_argument("--ym", help="ambermon.snd, Big Alec's YM music")
    p.add_argument("--saves", help="the old ATARI folder, to keep its save games")
    p.add_argument("--target", default=os.path.join(HERE, "ATARI", "AMBFILES"))
    p.add_argument("--force", action="store_true",
                   help="replace save games without asking (they are copied first)")
    a = p.parse_args()

    if not a.game_files and not a.ym and not a.saves:
        p.error("name your game files, the YM music, the old save games, or some of them")
    if not os.path.isfile(os.path.join(a.target, "BUILD.TXT")):
        raise Error("no programs in %s: run this from the unpacked package" % a.target)
    if not a.game_files and a.saves and not os.path.isfile(os.path.join(a.target, "SAVES")):
        raise Error("no game files in %s yet: name them too" % a.target)
    with tempfile.TemporaryDirectory() as temp:
        sndh, packed, searched = a.ym, [], []
        if not sndh and not os.path.exists(os.path.join(a.target, "MUSIK_YM.BIN")):
            sndh, packed, searched = find_ym(a.game_files)
        ym = extract_ym(sndh, temp) if sndh else None
        copies = []
        if a.game_files:
            source = prepare_old(find_amberfiles(a.game_files, temp), temp)
            version = check_version(source, a.target)
            copies = plan(source, a.target)
        games = len(copies)
        if a.saves:
            copies = old_saves(a.saves, copies, a.target, a.force)
        if ym:
            copies.append((ym, os.path.join(a.target, "MUSIK_YM.BIN")))
        changed = replaced_kept(copies, a.target)
        if changed:
            files = "%d file%s" % (len(changed), "s" * (len(changed) > 1))
            question = ("%s holds save games or settings that would be replaced "
                        "(%s).\nThey are copied beside the folder ATARI first.\n"
                        "Replace them?" % (a.target, files))
            if not a.force and not ask(question):
                raise Error("nothing changed: %s of save games or settings in %s would be "
                            "replaced.\nTo replace them without the question, add --force "
                            "(they are copied first)." % (files, a.target))
            folder = back_up(changed, a.target)
        for q, z in copies:
            os.makedirs(os.path.dirname(z), exist_ok=True)
            shutil.copyfile(q, z)
    if games:
        print("%d files copied for %s." % (games, version))
    if a.saves:
        print("Save games and settings taken from %s." % a.saves)
    if changed:
        print("The ones replaced are in %s." % folder)
    if ym:
        print("YM music from %s." % sndh)
    elif not os.path.exists(os.path.join(a.target, "MUSIK_YM.BIN")):
        for f in packed:
            print("%s is packed (ICE); this tool does not read packed files." % f)
        print("No YM music, so the ST stays silent.  No ambermon.snd found in\n  %s\n"
              "README.TXT says where to get it; put it beside install.py and run "
              "this again." % "\n  ".join(searched))
    print("Now copy the folder ATARI to the Atari and start AMBER.TOS.")


if __name__ == "__main__":
    main()

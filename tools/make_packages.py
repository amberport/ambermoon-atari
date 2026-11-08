#!/usr/bin/env python3
"""make_packages.py -- the release packages: the programs, without the game.

One zip per game version, from a clean clone of one commit, so BUILD.TXT names
that commit.  A package holds README.TXT (tools/package_readme.txt), install.py,
what install.py needs of tools/, and of ATARI/ only the files named in PROGRAMS.
Game files and the YM music (MUSIK_YM.BIN) stay out; the player brings them
(docs/14 F).

The build runs without TESTBUILDS, diagnostic switches and the YM SNDH.  Each
zip is then unpacked and installed from the same game files as a player would.
It stops if
- the commit in BUILD.TXT carries a "+": the build changed a tracked file;
- the installed folder is not, byte for byte, the folder the build delivered:
  a new file of the build ends here until it is named in PROGRAMS or in
  tools/game_names.py;
- a program file equals a game file.

The packages never go into the repository, and publishing is a step of its own.

Usage: make_packages.py GAME_FILES... [--repo DIR] [--ref REF] [--out DIR]
       GAME_FILES   as for tools/build_all.sh, one package each
       --repo       the repository to clone, default this one
       --ref        the commit, default HEAD
       --out        default ambermoon_gamedata/packages
"""
import argparse
import datetime
import hashlib
import os
import re
import subprocess
import sys
import tempfile
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import paths                                       # noqa: E402

PROGRAMS = (
    "AMBER.TOS",
    "AMBFILES/ENGINE.TOS", "AMBFILES/ENGINEST.TOS",
    "AMBFILES/FANTASY.TOS", "AMBFILES/FANTSYST.TOS",
    "AMBFILES/INTRO.TOS", "AMBFILES/INTROST.TOS",
    "AMBFILES/EXTRO.TOS", "AMBFILES/EXTROST.TOS",
    "AMBFILES/STPAL.DAT", "AMBFILES/MUSIK_YM.INF",
    "AMBFILES/AMBER.INF", "AMBFILES/BUILD.TXT",
)
# what install.py imports and calls, directly or not
TOOLS = (
    "adf_read.py", "am2cpu_extract.py", "am2cpu_old.py", "am2cpu_old_maps.py",
    "am2cpu_places.py", "am2cpu_read.py", "ambtool.py", "build_name.py",
    "dms_to_adf.py", "game_files.py", "game_names.py", "imploder_exe.py",
    "ipf_to_adf.py", "paths.py", "text_labels.py", "thalion_prepare.py",
    "ym_extract.py",
)
LANGUAGES = {"Deutsch": "de", "English": "en", "French": "fr"}


class Error(SystemExit):
    def __init__(self, text):
        super().__init__("ERROR: " + text)


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo] + list(args),
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode:
        raise Error("git %s: %s" % (" ".join(args), r.stderr.decode().strip()))
    return r.stdout.decode().strip()


def build_env():
    """Only what the clone cannot find itself: there is no build.cfg and no
    ambermoon_gamedata/ next to it, so no YM SNDH either."""
    env = {k: v for k, v in os.environ.items()
           if not k.startswith("AMBER_")
           and k not in ("TESTBUILDS", "VASM_EXTRA", "VERBOSE")}
    env["AMBER_DOWNLOAD"] = "NO"
    env["AMBER_URCODE"] = paths.urcode()
    if paths.value("AMBER_OBJDUMP"):
        env["AMBER_OBJDUMP"] = paths.value("AMBER_OBJDUMP")
    env["PATH"] = os.pathsep.join(os.path.join(paths.gamedata(), d)
                                  for d in ("vbcc/bin", "bin")) + os.pathsep + env["PATH"]
    return env


def build(clone, game, log):
    git(clone, "clean", "-fdxq")
    with open(log, "wb") as f:
        r = subprocess.run(["sh", "tools/build_all.sh", game], cwd=clone, env=build_env(),
                           stdout=f, stderr=subprocess.STDOUT)
    if r.returncode:
        with open(log, encoding="latin1") as f:
            raise Error("the build of %s failed:\n%s" % (game, "".join(f.readlines()[-25:])))


def build_lines(atari):
    """The build's name and the game files it is for, from BUILD.TXT."""
    with open(os.path.join(atari, "AMBFILES", "BUILD.TXT"), encoding="latin1") as f:
        lines = [line.strip() for line in f]
    game = [line[len("for the game files "):] for line in lines
            if line.startswith("for the game files ")]
    if not game:
        raise Error("BUILD.TXT does not name the game files")
    if "+" in lines[0]:
        raise Error("the build changed a tracked file: %s" % lines[0])
    return lines[0], game[0]


def package_name(built, game):
    version = re.match(r"Ambermoon Atari (\S+) ", built)
    found = re.match(r"Ambermoon v(\d+\.\d+) .*/ (\w+)$", game)
    if not version or not found or found.group(2) not in LANGUAGES:
        raise Error("no package name from %r and %r" % (built, game))
    return "ambermoon-atari-%s-for-%s-%s" % (version.group(1), found.group(1),
                                             LANGUAGES[found.group(2)])


def readme(clone, built, game):
    with open(os.path.join(clone, "tools", "package_readme.txt"), encoding="ascii") as f:
        text = f.read()
    text = text.replace("@BUILD@", built).replace("@GAME@", game)
    return text.replace("\n", "\r\n").encode("ascii")


def write_zip(path, clone, name, built, game, stamp):
    entries = [("README.TXT", readme(clone, built, game))]
    sources = [("install.py", os.path.join("tools", "install.py"))]
    sources += [("tools/" + t, os.path.join("tools", t)) for t in TOOLS]
    sources += [("ATARI/" + p, os.path.join("ATARI", p)) for p in PROGRAMS]
    for inside, source in sources:
        with open(os.path.join(clone, source), "rb") as f:
            entries.append((inside, f.read()))
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for inside, data in entries:
            info = zipfile.ZipInfo(name + "/" + inside, stamp)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)


def tree(folder):
    """Every file below folder: path with / -> SHA-256."""
    sums = {}
    for d, _, files in os.walk(folder):
        for f in files:
            p = os.path.join(d, f)
            with open(p, "rb") as h:
                sums[os.path.relpath(p, folder).replace(os.sep, "/")] = \
                    hashlib.sha256(h.read()).hexdigest()
    return sums


def verify(path, name, game, built_atari):
    """As a player would; the tools run from the unpacked package alone."""
    with tempfile.TemporaryDirectory() as temp:
        with zipfile.ZipFile(path) as z:
            z.extractall(temp)
        package = os.path.join(temp, name)
        r = subprocess.run([sys.executable, "install.py", game], cwd=package,
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if r.returncode:
            raise Error("install.py from %s failed:\n%s" % (path, r.stdout.decode("latin1")))
        installed = tree(os.path.join(package, "ATARI"))
    built = tree(built_atari)
    wrong = sorted(k for k in set(installed) | set(built)
                   if installed.get(k) != built.get(k))
    if wrong:
        raise Error("%s: %d files differ from the build, the first is %s"
                    % (path, len(wrong), wrong[0]))
    programs = {built[p] for p in PROGRAMS}
    same = sorted(k for k in built if k not in PROGRAMS and built[k] in programs)
    if same:
        raise Error("%s: a program equals the game file %s" % (path, same[0]))
    return len(installed)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("game_files", nargs="+")
    p.add_argument("--repo", default=ROOT)
    p.add_argument("--ref", default="HEAD")
    p.add_argument("--out", default=os.path.join(paths.gamedata(), "packages"))
    a = p.parse_args()

    repo, out = os.path.abspath(a.repo), os.path.abspath(a.out)
    if os.path.commonpath([repo, out]) == repo:
        raise Error("%s lies in the repository; packages never go there" % out)
    games = []
    for g in a.game_files:
        for candidate in (g, os.path.join(paths.gamedata(), g)):
            if os.path.exists(candidate):
                games.append(os.path.abspath(candidate))
                break
        else:
            raise Error("game files not found: %s" % g)
    commit = git(repo, "rev-parse", a.ref + "^{commit}")
    if git(repo, "status", "--porcelain", "--untracked-files=no"):
        print("Note: %s has changes that are not committed; they are not in the "
              "packages." % repo)
    stamp = datetime.datetime.strptime(
        git(repo, "log", "-1", "--format=%cd", "--date=format:%Y-%m-%d %H:%M:%S", commit),
        "%Y-%m-%d %H:%M:%S").timetuple()[:6]

    os.makedirs(out, exist_ok=True)
    with tempfile.TemporaryDirectory() as temp:
        clone = os.path.join(temp, "clone")
        subprocess.run(["git", "clone", "-q", "--no-hardlinks", repo, clone], check=True)
        git(clone, "checkout", "-q", "--detach", commit)
        for g in games:
            print("%s: building" % os.path.basename(g), flush=True)
            build(clone, g, os.path.join(temp, "build.log"))
            atari = os.path.join(clone, "ATARI")
            built, game = build_lines(atari)
            name = package_name(built, game)
            path = os.path.join(out, name + ".zip")
            write_zip(path, clone, name, built, game, stamp)
            count = verify(path, name, g, atari)
            print("%s: %d KB, %d files once installed, same as the build (%s)"
                  % (os.path.basename(path), os.path.getsize(path) // 1024, count, built),
                  flush=True)


if __name__ == "__main__":
    main()

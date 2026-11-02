#!/usr/bin/env python3
"""fetch_source.py -- fetch Thalion's source for the build, when it is missing.

Called by tools/build_common.sh only when the source is missing *and* its
path is the default (nothing set in the environment or build.cfg).  It then
comes, in this order, from

1. a folder in ambermoon_gamedata/ that holds src/GAME_OFF.S (a git clone);
2. a zip in ambermoon_gamedata/ that holds it (GitHub's "Download ZIP",
   ambermoon-main.zip, or the archive this tool keeps from a download);
3. a download of the tested commit from GitHub, kept as
   ambermoon_gamedata/ambermoon-<commit>.zip for the next time; if the
   archive cannot be downloaded and git is there, git fetches that commit.

So a build without network works as soon as one of 1 or 2 is there.  The
files of src/ are checked against the tested state (a SHA-256 over every
file): for a download a difference stops, for 1 and 2 it is a warning (a
newer state of the repository may build as well).  Thalion's source is
never put into this repository.

AMBER_DOWNLOAD=NO (variable or build.cfg) forbids the download.

Output (stdout): line 1 the path to use, line 2 where it came from.
Exit 1: nothing found (message on stderr).

Usage: fetch_source.py --target PATH --gamedata DIR [--download yes|no]
"""
import argparse
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
import zipfile

# Thalion's source as released by Jurie Horneman; the commit the port is
# built and tested with.
URCODE_REPO = "https://github.com/jhorneman/ambermoon"
URCODE_COMMIT = "52e36804e1f211330d884a79ecc5559138c4974d"
URCODE_URL = "%s/archive/%s.zip" % (URCODE_REPO, URCODE_COMMIT)
# SHA-256 over src/: per file (sorted by path below src/) the path, a zero
# byte and the file's SHA-256 (41 files).
URCODE_SHA = "07a5f1c51edb1cbfcc55929508404344310dda1b5def459bc948aea953836452"

MAX_SIZE = 64 << 20


class Error(Exception):
    pass


def src_hash(files):
    """files: {path below src/: bytes} -> hex digest as URCODE_SHA."""
    h = hashlib.sha256()
    # .DS_Store: macOS leaves it in a clone; it is not part of the source
    for p in sorted((f for f in files if not f.endswith(".DS_Store")),
                    key=lambda s: s.encode("utf-8")):
        h.update(p.encode("utf-8") + b"\0" + hashlib.sha256(files[p]).digest())
    return h.hexdigest()


def read_folder(src):
    result = {}
    for root, _, files in os.walk(src):
        for n in files:
            p = os.path.join(root, n)
            result[os.path.relpath(p, src).replace(os.sep, "/")] = open(p, "rb").read()
    return result


def zip_src(path):
    """-> {path below src/: bytes} of the zip's <top>/src/, or None."""
    try:
        z = zipfile.ZipFile(path)
    except (zipfile.BadZipFile, OSError):
        return None
    with z:
        top = None
        for n in z.namelist():
            parts = n.split("/")
            if len(parts) == 3 and parts[1:] == ["src", "GAME_OFF.S"]:
                top = parts[0] + "/src/"
            elif parts == ["src", "GAME_OFF.S"]:
                top = "src/"
        if top is None:
            return None
        result = {}
        for i in z.infolist():
            if i.is_dir() or not i.filename.startswith(top):
                continue
            rel = i.filename[len(top):]
            parts = rel.split("/")
            if i.filename.startswith("/") or ".." in parts or "" in parts:
                raise Error("%s: the entry %r leaves the folder" % (path, i.filename))
            if i.file_size > MAX_SIZE:
                raise Error("%s: %s is too large" % (path, i.filename))
            result[rel] = z.read(i)
        return result


def write_folder(files, target):
    """Write {rel: bytes} as the folder target (src), through a temporary name."""
    tmp = target + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    for rel, content in files.items():
        p = os.path.join(tmp, *rel.split("/"))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(content)
    if os.path.exists(target):
        raise Error("%s exists already but holds no GAME_OFF.S: move it away first" % target)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    os.rename(tmp, target)


def download_file(url, target, max_size=MAX_SIZE):
    tmp = target + ".part"
    try:
        with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
            n = 0
            for piece in iter(lambda: r.read(1 << 16), b""):
                n += len(piece)
                if n > max_size:
                    raise Error("%s: more than %d MB" % (url, max_size >> 20))
                f.write(piece)
    except (OSError, ValueError) as e:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise Error("download of %s failed: %s" % (url, e))
    os.rename(tmp, target)


def git_fetch(target_zip):
    """The tested commit through git, written as the same zip layout."""
    if not shutil.which("git"):
        raise Error("no git either")
    with tempfile.TemporaryDirectory() as tmp:
        for cmd in (["git", "init", "-q", tmp],
                       ["git", "-C", tmp, "fetch", "-q", "--depth", "1",
                        URCODE_REPO + ".git", URCODE_COMMIT],
                       ["git", "-C", tmp, "archive", "--format=zip",
                        "--prefix=ambermoon-%s/" % URCODE_COMMIT, "-o", target_zip + ".part",
                        URCODE_COMMIT]):
            r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            if r.returncode:
                raise Error("%s: %s" % (" ".join(cmd[:4]), r.stdout.decode("latin1").strip()))
    os.rename(target_zip + ".part", target_zip)


def check_source(files, origin, strict):
    h = src_hash(files)
    if h == URCODE_SHA:
        return "tested state"
    text = "%s: Thalion's source differs from the tested state (commit %s)" % (
        origin, URCODE_COMMIT[:7])
    if strict:
        raise Error(text)
    print("WARNING: " + text, file=sys.stderr)
    return "NOT the tested state"


def urcode(target, gamedata, download):
    # 1. a git clone (or an unpacked zip) in ambermoon_gamedata/
    if os.path.isdir(gamedata):
        for n in sorted(os.listdir(gamedata)):
            src = os.path.join(gamedata, n, "src")
            if os.path.isfile(os.path.join(src, "GAME_OFF.S")) and \
                    os.path.normpath(src) != os.path.normpath(target):
                return src, "%s, %s" % (os.path.join(n, "src"),
                                        check_source(read_folder(src), src, False))
    # 2. a zip in ambermoon_gamedata/
    if os.path.isdir(gamedata):
        for n in sorted(os.listdir(gamedata)):
            p = os.path.join(gamedata, n)
            if n.lower().endswith(".zip") and os.path.isfile(p):
                files = zip_src(p)
                if files:
                    state = check_source(files, p, False)
                    write_folder(files, target)
                    return target, "unpacked from %s, %s" % (n, state)
    # 3. the download
    if not download:
        raise Error("Thalion's source is missing and AMBER_DOWNLOAD=NO forbids the download.\n"
                     "Put it into %s: a clone of %s, or its zip" % (gamedata, URCODE_REPO))
    os.makedirs(gamedata, exist_ok=True)
    archive = os.path.join(gamedata, "ambermoon-%s.zip" % URCODE_COMMIT[:7])
    print("downloading %s" % URCODE_URL, file=sys.stderr)
    note = "downloaded from GitHub"
    try:
        download_file(URCODE_URL, archive)
    except Error as e:
        print("%s; trying git" % e, file=sys.stderr)
        try:
            git_fetch(archive)
        except Error as e2:
            raise Error("%s; git: %s.\nWithout network: put a clone of %s or its zip "
                         "into %s" % (e, e2, URCODE_REPO, gamedata))
        note = "fetched from GitHub with git"
    files = zip_src(archive)
    if not files:
        raise Error("%s holds no src/GAME_OFF.S" % archive)
    check_source(files, URCODE_URL, True)
    write_folder(files, target)
    return target, "%s (commit %s, kept as %s)" % (
        note, URCODE_COMMIT[:7], os.path.basename(archive))


def main():
    a = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    a.add_argument("--target", required=True)
    a.add_argument("--gamedata", required=True)
    a.add_argument("--download", default="yes")
    a = a.parse_args()
    download = a.download.strip().lower() not in ("no", "0", "off", "false")
    try:
        path, text = urcode(a.target, a.gamedata, download)
    except (Error, OSError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    print(path)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())

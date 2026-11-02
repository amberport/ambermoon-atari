#!/usr/bin/env python3
"""game_files.py -- find the game files in what AMBER_DATEN names.

The build reads the game files from a folder Amberfiles/ (AMBER_DATEN is
the directory above it).  To make building easy, AMBER_DATEN may also be:

- the Amberfiles folder itself (with AM2_CPU in it);
- a folder that holds one of these somewhere below it;
- the disk images: a folder with the ADF, DMS or IPF files of one version,
  or one of those files (then its folder counts);
- a zip file holding any of the above, as downloaded (from the Thalion
  Webshrine: Thalion's 1.07 is a zip of DMS files, 1.01 of IPF files;
  Pyrdacor's 1.2x come as ADF).

If AMBER_DATEN is not set and its default folder is missing, the folder
ambermoon_gamedata/ is searched for exactly one such thing.

Nothing is ever written next to the user's files: zips are unpacked and
disks read into build/game_files/, once per content (the folder name holds a
hash of the input; a second build reuses it).  Disk images are read by
tools/adf_read.py; DMS needs the program xdms (Linux: apt install xdms), IPF
goes through tools/ipf_to_adf.py and must give every sector.
The files of all disks go into one Amberfiles/, as Thalion's installer
puts them: everything on top of each disk and its folders Initial/,
Save.xx/, except the Workbench folders (C, Devs, L, S, ...) and icons
(*.info).  A file that two disks hold with different contents stops it.

Output (stdout): line 1 the directory above Amberfiles/, line 2 what was
found, for the build's overview.  Errors go to stderr, exit 1.

Usage: game_files.py --data PATH --source SOURCE --gamedata DIR [--out build/game_files]
       SOURCE is where PATH came from (paths.py: "default" or a name)
"""
import argparse
import glob
import hashlib
import os
import shutil
import stat
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import adf_read                         # noqa: E402
import ipf_to_adf                       # noqa: E402

IMAGES = (".adf", ".dms", ".ipf")
# Workbench folders on Thalion's and Pyrdacor's disk A, not game files
SYSTEM = {"c", "devs", "l", "s", "libs", "system", "fonts", "prefs", "utilities",
          "expansion", "storage", "tools", "trashcan", "locale", "classes", "rexx"}
ZIP_MAX = 512 << 20               # unpacked bytes
ZIP_FILES = 5000
DEPTH = 4


class Error(Exception):
    pass


def hash_of(file_paths):
    h = hashlib.sha1()
    for p in sorted(file_paths):
        h.update(os.path.basename(p).encode("utf-8", "replace") + b"\0")
        with open(p, "rb") as f:
            for piece in iter(lambda: f.read(1 << 20), b""):
                h.update(piece)
    return h.hexdigest()[:12]


def images_in(folder):
    return [os.path.join(folder, n) for n in sorted(os.listdir(folder))
            if n.lower().endswith(IMAGES) and os.path.isfile(os.path.join(folder, n))]


def kind_of(folder):
    """What a folder is: "daten" (has Amberfiles/AM2_CPU), "amberfiles"
    (has AM2_CPU), "disks" (has disk images) or None."""
    if os.path.isfile(os.path.join(folder, "Amberfiles", "AM2_CPU")):
        return "daten"
    if os.path.isfile(os.path.join(folder, "AM2_CPU")):
        return "amberfiles"
    return "disks" if images_in(folder) else None


def search_folder(folder, depth=DEPTH):
    """-> [(kind, folder)] below folder; a folder that is one is not entered."""
    kind = kind_of(folder)
    if kind:
        return [(kind, folder)]
    if depth == 0:
        return []
    result = []
    for n in sorted(os.listdir(folder)):
        p = os.path.join(folder, n)
        if os.path.isdir(p) and not os.path.islink(p) and n != "__MACOSX":
            result += search_folder(p, depth - 1)
    return result


def unpack_zip(path, out):
    target = os.path.join(out, "zip_" + hash_of([path]))
    done = os.path.join(target, ".done")
    if os.path.isfile(done):
        return target
    shutil.rmtree(target, ignore_errors=True)
    try:
        z = zipfile.ZipFile(path)
    except zipfile.BadZipFile as e:
        raise Error("%s: not a zip file (%s)" % (path, e))
    with z:
        infos = z.infolist()
        if len(infos) > ZIP_FILES or sum(i.file_size for i in infos) > ZIP_MAX:
            raise Error("%s: too large for game files" % path)
        tmp = target + ".tmp"
        shutil.rmtree(tmp, ignore_errors=True)
        os.makedirs(tmp)
        for i in infos:
            name = i.filename.replace("\\", "/")
            parts = [t for t in name.split("/") if t not in ("", ".")]
            if name.startswith("/") or ".." in parts or not parts or ":" in parts[0]:
                raise Error("%s: the entry %r leaves the folder" % (path, i.filename))
            if i.is_dir() or stat.S_ISLNK(i.external_attr >> 16):
                continue
            dest = os.path.join(tmp, *parts)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with z.open(i) as q, open(dest, "wb") as f:
                shutil.copyfileobj(q, f)
    os.rename(tmp, target)
    open(done, "w").write(path + "\n")
    return target


def zip_is_game(path):
    """A zip in ambermoon_gamedata/ that looks like game files."""
    try:
        with zipfile.ZipFile(path) as z:
            for n in z.namelist():
                b = n.rstrip("/").split("/")[-1]
                if b == "AM2_CPU" or b.lower().endswith(IMAGES):
                    return True
    except (zipfile.BadZipFile, OSError):
        return False
    return False


def adf_of(image, target):
    """-> path of an ADF for this image (DMS through xdms, IPF through
    tools/ipf_to_adf.py)."""
    if image.lower().endswith(".adf"):
        return image
    adf = os.path.join(target, os.path.splitext(os.path.basename(image))[0] + ".adf")
    if image.lower().endswith(".ipf"):
        n, bad = ipf_to_adf.convert(image, adf)
        if n != 1760 or bad:
            raise Error("%s: %d of 1760 sectors read, %d bad; not a standard AmigaDOS "
                        "disk" % (image, n, len(bad)))
        return adf
    if not shutil.which("xdms"):
        raise Error("%s is a DMS image: the build needs the program xdms to read it "
                     "(Linux: sudo apt install xdms), or give the ADF files" % image)
    r = subprocess.run(["xdms", "-q", "u", image, "+" + adf],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if r.returncode or not os.path.isfile(adf):
        raise Error("xdms could not unpack %s: %s" % (image, r.stdout.decode("latin1").strip()))
    return adf


def read_disks(folder, out):
    images = images_in(folder)
    target = os.path.join(out, "disks_" + hash_of(images))
    done = os.path.join(target, ".done")
    if os.path.isfile(done):
        return target, open(done).read().strip()
    shutil.rmtree(target, ignore_errors=True)
    tmp = target + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(os.path.join(tmp, "adf"))
    amber = os.path.join(tmp, "Amberfiles")
    os.makedirs(amber)
    origin = {}
    for image in images:
        adf = adf_of(image, os.path.join(tmp, "adf"))
        try:
            files = adf_read.read(adf)
            disk = adf_read.disk_name(adf)
        except adf_read.AdfError as e:
            raise Error(str(e))
        for name, content in sorted(files.items()):
            parts = name.rstrip("/").split("/")
            if parts[0].lower() in SYSTEM or parts[-1].lower().endswith(".info"):
                continue
            if any(t in ("", ".", "..") for t in parts):
                raise Error("%s: the name %r is not usable" % (image, name))
            p = os.path.join(amber, *parts)
            if content is None:
                os.makedirs(p, exist_ok=True)
                continue
            if name in origin:
                if open(p, "rb").read() != content:
                    raise Error("%s is on %s and on %s with different contents"
                                 % (name, origin[name], disk))
                continue
            os.makedirs(os.path.dirname(p), exist_ok=True)
            open(p, "wb").write(content)
            origin[name] = disk
    shutil.rmtree(os.path.join(tmp, "adf"))
    if not os.path.isfile(os.path.join(amber, "AM2_CPU")):
        raise Error("the disk images in %s hold no AM2_CPU: not Ambermoon's disks, "
                     "or not all of them" % folder)
    kinds = sorted({os.path.splitext(b)[1][1:].upper() for b in images})
    text = "%d disk images (%s)" % (len(images), ", ".join(kinds))
    os.rename(tmp, target)
    open(done, "w").write(text + "\n")
    return target, text


def amberfiles_wrapper(folder, out):
    """A folder named other than Amberfiles: a directory above it with a link."""
    if os.path.basename(os.path.normpath(folder)) == "Amberfiles":
        return os.path.dirname(os.path.normpath(folder))
    target = os.path.join(out, "link_" + hashlib.sha1(
        os.path.realpath(folder).encode()).hexdigest()[:12])
    os.makedirs(target, exist_ok=True)
    link = os.path.join(target, "Amberfiles")
    if os.path.islink(link) and os.readlink(link) != os.path.realpath(folder):
        os.remove(link)
    if not os.path.lexists(link):
        os.symlink(os.path.realpath(folder), link)
    return target


def resolve(path, out, origin=None):
    """-> (directory above Amberfiles/, what it was)."""
    name = origin or os.path.basename(os.path.normpath(path))
    if os.path.isfile(path):
        if path.lower().endswith(".zip"):
            d, text = resolve(unpack_zip(path, out), out, name)
            return d, text
        if path.lower().endswith(IMAGES):
            return resolve(os.path.dirname(os.path.abspath(path)), out, origin)
        raise Error("%s: neither a folder, a zip nor a disk image" % path)
    if not os.path.isdir(path):
        raise Error("%s does not exist" % path)
    found = search_folder(path)
    if not found:
        raise Error("%s holds no game files: no Amberfiles/ with AM2_CPU, "
                     "no ADF, DMS or IPF images" % path)
    if len(found) > 1:
        raise Error("%s holds more than one set of game files:\n  %s\nName one of them: "
                     "sh tools/build_all.sh PATH (or AMBER_DATEN, variable or build.cfg)"
                     % (path, "\n  ".join(f for _, f in found)))
    kind, folder = found[0]
    if kind == "daten":
        return folder, "%s, folder %s" % (name, os.path.relpath(folder, path)) \
            if origin else "folder %s" % folder
    if kind == "amberfiles":
        return amberfiles_wrapper(folder, out), "%s, Amberfiles folder" % name
    d, text = read_disks(folder, out)
    return d, "%s: %s" % (name, text)


def in_gamedata(gamedata):
    """Default missing: exactly one set of game files in ambermoon_gamedata/."""
    if not os.path.isdir(gamedata):
        return None
    candidates = []
    for n in sorted(os.listdir(gamedata)):
        p = os.path.join(gamedata, n)
        if os.path.isdir(p):
            if search_folder(p, DEPTH - 1):
                candidates.append(p)
        elif n.lower().endswith(".zip") and zip_is_game(p):
            candidates.append(p)
        elif n.lower().endswith(IMAGES) and gamedata not in candidates:
            candidates.append(gamedata)
    if len(candidates) > 1:
        raise Error("%s holds more than one set of game files:\n  %s\nName the one to build "
                     "from: sh tools/build_all.sh NAME (or AMBER_DATEN, variable or build.cfg)"
                     % (gamedata, "\n  ".join(candidates)))
    return candidates[0] if candidates else None


def main():
    a = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    a.add_argument("--data", required=True)
    a.add_argument("--source", required=True)
    a.add_argument("--gamedata", required=True)
    a.add_argument("--out", default="build/game_files")
    a = a.parse_args()
    try:
        # the usual case first, unchanged: a folder with Amberfiles/AM2_CPU
        if os.path.isfile(os.path.join(a.data, "Amberfiles", "AM2_CPU")):
            print(a.data)
            print("folder")
            return 0
        path = a.data
        if not os.path.exists(path) and a.source == "default":
            path = in_gamedata(a.gamedata)
            if path is None:
                raise Error("no game files: %s holds none.  Put a zip, disk images or a "
                             "folder there, or name them: sh tools/build_all.sh PATH" % a.gamedata)
        os.makedirs(a.out, exist_ok=True)
        d, text = resolve(os.path.abspath(path), os.path.abspath(a.out))
    except (Error, OSError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    print(d)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())

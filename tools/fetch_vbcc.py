#!/usr/bin/env python3
"""fetch_vbcc.py -- fetch vasm and vlink for the build, when they are missing.

Called by tools/build_common.sh only when vasmm68k_mot or vlink is found
neither in ambermoon_gamedata/ nor in PATH.  Both come out of the vbcc
package for Linux x86-64, the one the builds are tested with (vasm 1.9a,
vlink 0.17a): a package already lying in ambermoon_gamedata/ or a download of
about 32 MB.  The two programs are checked against their SHA-256, a difference
stops.  Only they are kept, as ambermoon_gamedata/bin/; a downloaded package
is removed again, one the user put there stays.

Other systems: build vasm and vlink from their sources
(docs/developer/building.md).

AMBER_DOWNLOAD=NO (variable or build.cfg) forbids the download.

Usage: fetch_vbcc.py --gamedata DIR [--download yes|no]
"""
import argparse
import hashlib
import os
import platform
import sys
import tarfile

from fetch_source import Error, download_file

PACKAGE = "vbcc_linux_x64.tar.gz"
URL = "http://www.ibaug.de/vbcc/" + PACKAGE
PROGRAMS = {
    "vasmm68k_mot": "d7dc7ed46590958c69a3105f2f0eda7872eb3865767f8da92f6b1846aa15603b",
    "vlink": "2d325c06fa0d16b2a9964563649917569d47f868ba4796338b1f9648303e014e",
}
MAX_SIZE = 64 << 20


def unpack_programs(package, target):
    """The two programs of bin/ into target, each only if it is the tested one."""
    found = {}
    with tarfile.open(package, "r:*") as t:
        for m in t:
            parts = m.name.split("/")
            if m.isfile() and parts[-1] in PROGRAMS and parts[-2:-1] == ["bin"]:
                with t.extractfile(m) as f:
                    found[parts[-1]] = f.read()
    for name, sha in PROGRAMS.items():
        if name not in found:
            raise Error("%s holds no bin/%s" % (package, name))
        if hashlib.sha256(found[name]).hexdigest() != sha:
            raise Error("%s: bin/%s is not the tested program (SHA-256 differs)" % (package, name))
    os.makedirs(target, exist_ok=True)
    for name, content in found.items():
        p = os.path.join(target, name)
        with open(p + ".tmp", "wb") as f:
            f.write(content)
        os.chmod(p + ".tmp", 0o755)
        os.rename(p + ".tmp", p)


def fetch(gamedata, download):
    if (platform.system(), platform.machine()) != ("Linux", "x86_64"):
        raise Error("the vbcc package is for Linux x86-64; on this system build vasm "
                    "and vlink from their sources (docs/developer/building.md)")
    package = os.path.join(gamedata, PACKAGE)
    fetched = not os.path.isfile(package)
    if fetched:
        if not download:
            raise Error("vasm and vlink are missing and AMBER_DOWNLOAD=NO forbids the "
                        "download.\nPut %s from %s into %s" % (PACKAGE, URL, gamedata))
        os.makedirs(gamedata, exist_ok=True)
        print("downloading %s" % URL, file=sys.stderr)
        download_file(URL, package, MAX_SIZE)
    try:
        unpack_programs(package, os.path.join(gamedata, "bin"))
    finally:
        if fetched and os.path.exists(package):
            os.remove(package)


def main():
    a = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    a.add_argument("--gamedata", required=True)
    a.add_argument("--download", default="yes")
    a = a.parse_args()
    download = a.download.strip().lower() not in ("no", "0", "off", "false")
    try:
        fetch(a.gamedata, download)
    except (Error, OSError, tarfile.TarError) as e:
        print("ERROR: %s" % e, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

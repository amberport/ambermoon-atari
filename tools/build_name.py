#!/usr/bin/env python3
"""build_name.py -- the build's name: our version, the commit, and the
version of the game files it was built for.

    Ambermoon Atari 0.8 (65202f9) for Ambermoon v1.07 26-3-1994 / English

- Our version is the file VERSION in the repository root.
- The commit is git's short hash; "+" behind it when tracked files are
  changed.  Without git (a downloaded zip of the repository) it is left out.
- The game files' version is the two version lines at the end of Text.amb
  (Thalion's Version_string1 and Version_string2, which the game shows in
  its options); for Thalion's 1.01 and 1.07 the Text.amb the build made
  from AM2_CPU (tools/thalion_prepare.py) carries them as well.

Writes:
- build/build_name.i for the engine: the start screen's lines
  (Build_line, two lines, so they fit the ST's 40 columns), the two
  version lines it was built for (Build_version1, Build_version2), which
  MAIN.S compares with the Text.amb it loads, and the same without
  control bytes for its message (Build_display);
- build/BUILD.TXT, delivered to ATARI/AMBFILES/: the same in plain text;
- stdout: the line.

Usage: build_name.py [--amberfiles DIR] [--out build]
"""
import argparse
import contextlib
import datetime
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import unpack                     # noqa: E402
import paths                                   # noqa: E402
import textmarken                              # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def our_version():
    v = open(os.path.join(ROOT, "VERSION")).read().strip()
    if not v or any(c.isspace() for c in v):
        sys.exit("ERROR: VERSION holds %r, expected one word such as 0.8" % v)
    return v


def commit():
    try:
        h = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short=7", "HEAD"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if h.returncode:
            return None
        s = subprocess.run(["git", "-C", ROOT, "status", "--porcelain",
                            "--untracked-files=no"],
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    except OSError:
        return None
    return h.stdout.decode().strip() + ("+" if s.stdout.strip() else "")


def game_files_version(amberfiles):
    kind, parts = unpack(open(os.path.join(amberfiles, "Text.amb"), "rb").read())
    d = bytes(parts[0])
    with contextlib.redirect_stdout(sys.stderr):     # its notes
        labels, _ = textmarken.zerlegen(d)
    lines = []
    for name in textmarken.VERSION:
        o = next(o for o, n in labels.items() if name in n)
        lines.append(d[o:d.index(b"\0", o)])
    return lines


def dc_b(b):
    """Bytes as dc.b, printable ones in quotes (vasm runs with -esc)."""
    parts, text = [], ""
    for c in b:
        if 32 <= c < 127 and chr(c) not in '"\\':
            text += chr(c)
            continue
        if text:
            parts.append('"%s"' % text)
            text = ""
        parts.append("%d" % c)
    if text:
        parts.append('"%s"' % text)
    return "\tdc.b\t%s,0" % ",".join(parts)


def main():
    a = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    a.add_argument("--amberfiles", default=paths.amberfiles())
    a.add_argument("--out", default="build")
    a = a.parse_args()
    v1, v2 = game_files_version(a.amberfiles)
    c = commit()
    ours = "Ambermoon Atari %s%s" % (our_version(), " (%s)" % c if c else "")
    # a control byte may lead the first line (1.21: 5 or 6): not shown
    data = " ".join(bytes(c for c in v if c >= 32).decode("latin1") for v in (v1, v2))
    line = "%s for %s" % (ours, data)
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "build_name.i"), "w") as f:
        f.write("; build/build_name.i -- written by tools/build_name.py.  Do not edit.\n"
                "; The build's name and the version of the game files it was built\n"
                "; for (the two version lines of Text.amb).  MAIN.S shows the line at\n"
                "; the start and compares the version lines with the loaded Text.amb.\n\n"
                "\tSECTION\tFast_DATA,data\n"
                "Build_line:\n%s\n"
                "Build_version1:\n%s\n"
                "Build_version2:\n%s\n"
                "Build_display:\n%s\n"
                "\teven\n" % (dc_b(("%s\r\nfor %s\r\n" % (ours, data)).encode("latin1")),
                              dc_b(v1), dc_b(v2), dc_b(data.encode("latin1"))))
    with open(os.path.join(a.out, "BUILD.TXT"), "w", newline="\r\n") as f:
        f.write("%s\nbuilt %s\nfor the game files %s\n"
                % (ours, datetime.date.today().isoformat(), data))
    print(line)


if __name__ == "__main__":
    main()

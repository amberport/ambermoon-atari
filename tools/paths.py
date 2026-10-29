#!/usr/bin/env python3
"""paths.py -- where the build finds what lies outside the repository.

Thalion's source, the game files, Big Alec's YM music, the TOS image for
Hatari and the m68k objdump never go into the repository; every tool asks
this module for them.  So does tools/testpaket.py for the network address
of the test Falcon, which is personal too.  Each value is looked up in this order:

1. the environment variable (for one build: ``AMBER_DATEN=... sh ...``);
2. the file ``build.cfg``: the first one found from the repository root
   upwards, so a worktree under ``.claude/worktrees/`` finds the one of the
   main checkout.  One ``KEY=VALUE`` per line, ``#`` starts a comment, ``~``
   is allowed, a relative path is relative to the file.  It holds personal
   paths and never goes into the repository (``.gitignore``); the template
   is ``build.cfg.example``;
3. the default: a folder ``ambermoon_gamedata/`` next to the repository,
   searched upwards the same way.

Keys and defaults:

    AMBER_DATEN    the directory above Amberfiles/
                   ambermoon_gamedata/ambermoon_german_1.20_extracted
    AMBER_URCODE   Thalion's source (the folder with GAME_OFF.S)
                   ambermoon_gamedata/ambermoon-main-asm/src
    AMBER_YMSNDH   big_alec/ambermon.snd from the SNDH archive (optional)
                   ambermoon_gamedata/ambermon.snd
    AMBER_TOS      TOS image for Hatari (tools/hatari/teste.sh)
                   ambermoon_gamedata/TOS404.IMG
    AMBER_OBJDUMP  m68k objdump; no default, am2cpu_lesen.objdump() searches
    AMBER_FALCON   the test Falcon's address for uIPtool (testpaket.py
                   falcon); no default, an address, not a path

In Python: ``import paths`` (the tools run from tools/), then
``paths.value(KEY)``, ``paths.source(KEY)``, ``paths.amberfiles()``,
``paths.urcode()``.  In the shell: ``eval "$(python3 tools/paths.py --sh)"``
sets DATEN, URCODE, YMSNDH, TOS, OBJDUMP, FALCON_IP and with _SOURCE behind each name
where it came from (the variable's name, build.cfg or default).

Usage:  paths.py            show the values and where they come from
        paths.py --sh       the same as shell assignments
"""
import os
import shlex
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CFG = "build.cfg"
FOLDER = "ambermoon_gamedata"

# key -> (shell name, default below FOLDER or None)
KEYS = {
    "AMBER_DATEN": ("DATEN", "ambermoon_german_1.20_extracted"),
    "AMBER_URCODE": ("URCODE", "ambermoon-main-asm/src"),
    "AMBER_YMSNDH": ("YMSNDH", "ambermon.snd"),
    "AMBER_TOS": ("TOS", "TOS404.IMG"),
    "AMBER_OBJDUMP": ("OBJDUMP", None),
    "AMBER_FALCON": ("FALCON_IP", None),
}
# values that are not paths: taken from build.cfg as they stand
NOT_PATHS = {"AMBER_FALCON"}


def _upwards():
    d = ROOT
    while True:
        yield d
        parent = os.path.dirname(d)
        if parent == d:
            return
        d = parent


def _find_cfg():
    for d in _upwards():
        f = os.path.join(d, CFG)
        if os.path.isfile(f):
            return f
    return None


def _find_folder():
    # next to the repository: the folder beside ROOT or beside an ancestor
    for d in _upwards():
        f = os.path.join(os.path.dirname(d), FOLDER)
        if d != os.path.dirname(d) and os.path.isdir(f):
            return f
    return os.path.join(os.path.dirname(ROOT), FOLDER)   # for the message


def _read_cfg():
    f = _find_cfg()
    if f is None:
        return None, {}
    values = {}
    with open(f, encoding="utf-8") as h:
        for n, line in enumerate(h, 1):
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            key, eq, val = line.partition("=")
            key, val = key.strip(), val.strip().strip('"').strip("'")
            if not eq or key not in KEYS:
                sys.exit("%s line %d: expected one of %s=PATH" %
                         (f, n, ", ".join(KEYS)))
            if val and key in NOT_PATHS:
                values[key] = val
            elif val:
                val = os.path.expanduser(val)
                values[key] = os.path.normpath(
                    os.path.join(os.path.dirname(f), val))
    return f, values


_CFG_FILE, _CFG = _read_cfg()


def lookup(key):
    """(value, source): source is the variable's name, the build.cfg path
    or "default"; value is "" when there is none (AMBER_OBJDUMP)."""
    if os.environ.get(key):
        return os.path.expanduser(os.environ[key]), key
    if key in _CFG:
        return _CFG[key], _CFG_FILE
    sub = KEYS[key][1]
    if sub is None:
        return "", "default"
    return os.path.join(_find_folder(), sub), "default"


def value(key):
    return lookup(key)[0]


def source(key):
    s = lookup(key)[1]
    return CFG if s == _CFG_FILE else s


def urcode():
    return value("AMBER_URCODE")


def amberfiles():
    return os.path.join(value("AMBER_DATEN"), "Amberfiles")


def main():
    if sys.argv[1:] == ["--sh"]:
        for key, (name, _) in KEYS.items():
            v, s = lookup(key)
            print("%s=%s" % (name, shlex.quote(v)))
            print("%s_SOURCE=%s" % (name, shlex.quote(source(key))))
        return
    if sys.argv[1:]:
        sys.exit(__doc__.split("Usage:")[1])
    print("build.cfg: %s" % (_CFG_FILE or "none"))
    for key in KEYS:
        v, s = lookup(key)
        if not v:
            print("  %-14s %-8s %-10s %s" % (key, "not set", "", "searched"))
            continue
        if key in NOT_PATHS:
            there = "set"
        else:
            there = "found" if os.path.exists(v) else "missing"
        print("  %-14s %-8s %-10s %s" % (key, there, source(key), v))


if __name__ == "__main__":
    main()

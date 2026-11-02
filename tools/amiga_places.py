#!/usr/bin/env python3
"""amiga_places.py -- the 1.20 places of Thalion's intro and extro in another
version of the program (Thalion's disks 1.01 and 1.07, Pyrdacor's 1.21).

The tables of tools/amiga_programm.py (K1 ExecBase, K2, K3), of the ST
tools (extro_st_program.py, intro_st_program.py) and the names in our
sources (intro/, extro/, intro_st/, extro_st/) give places of the German
1.20.  Other versions have the same code with insertions and deletions
(English 1.07/1.21 extro: a joystick check; 1.01: shorter starts).  This
module moves each place with the map that tools/amiga_places_generate.py
made (tools/amiga_places_maps.py, numbers only), and proves it on the file:

- a K3 site's six bytes must be the 1.20 bytes, except branch displacements
  and relocated longwords whose targets the map moves alike;
- a name in our sources must lie in a mapped range;
- the counts of K1 and relocations are the version's, from the map.

A file the map does not know is taken as 1.20 when its hunk sizes are those
of 1.20; amiga_programm.py then checks it as before.  Anything else stops.

Names: our sources write a place of Thalion's program as <label>_<hex>,
the 1.20 offset (Extro_h1_EBC for Extro_h1+$EBC).  write_names() puts
an equ for each such name it finds in the sources into the hunks file.

    for_version(name, d, hunks, p)  -> p for this file (places moved), with
                                   p["places"] the Lage
    write_names(f, p)       -> equ lines for the names in our sources
"""
import glob
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Our sources that name places of Thalion's intro and extro.
SOURCE_DIRS = ["intro", "extro", "intro_st", "extro_st", "amiga"]


class PlacesError(Exception):
    pass


# Thalion's English extro (1.07, the same in 1.21) has, behind bsr $EBC at
# 1.20 $596, a check of the joystick fire button: btst #7,$BFE001 and
# beq.s to the rts, 10 bytes; then tst.w $3E as in German.  Our CIA-A
# (amiga/AMIGA_RAHMEN.S, Amiga_maus) only ever clears bit 6, bit 7 stays 1,
# so the branch is never taken: the K3 hook (bsr $EBC, our display, tst.w
# $3E) may skip it.  Checked byte for byte.  (program, 1.20 site) ->
# (bytes behind the first instruction, length of that instruction).
INSERTIONS = {
    ("extro", 0x0596): ("0839000700bfe0016716", 4),
}


class Places:
    """Places of one program file: 1.20 (hunk, offset) -> this file."""

    def __init__(self, name, place_map=None):
        self.name = name
        self.place_map = place_map          # None: 1.20 itself
        self.version = place_map["version"] if place_map else "1.20"

    def _range(self, h, o, n=1):
        if self.place_map is None:
            return o, "="
        for a, b, l, kind in self.place_map["hunks"].get(h, ()):
            if a <= o and o + n <= a + l:
                return b + o - a, kind
        return None, None

    def place(self, h, o, why=""):
        """1.20 offset o in hunk h -> offset in this file, or stop."""
        new, kind = self._range(h, o)
        if new is None:
            raise PlacesError("%s %s: 1.20 place %d:$%X has no place in this version%s"
                             % (self.name, self.version, h, o, why and " (%s)" % why))
        return new

    def piece_range(self, h, begin, stop, why=""):
        """1.20 range [von, bis) -> (von, bis) here; it must stay one piece."""
        a, b = self.place(h, begin, why), self.place(h, stop - 1, why) + 1
        if b - a != stop - begin:
            raise PlacesError("%s %s: 1.20 range %d:$%X-$%X is not one piece here%s"
                             % (self.name, self.version, h, begin, stop, why and " (%s)" % why))
        return a, b

    def k3_bytes(self, h, o, old, code):
        """The six bytes of a K3 site in this file, proved against the 1.20
        bytes old (hex) -> (new offset, new bytes hex).  First as one piece
        of the 1.20 code; else as the known insertion of INSERTIONS."""
        if self.place_map is None:
            return o, old
        ref = bytes.fromhex(old)
        new = self.place(h, o, "K3 site")
        error = None
        for i in range(len(ref)):
            p, kind = self._range(h, o + i)
            if p is None:
                error = "byte %d has no place" % i
            elif p != new + i:
                error = "not one piece"
            elif kind == "=" and code[p] != ref[i]:
                error = "byte %d differs" % i
            if error:
                break
        if error is None:
            return new, code[new:new + len(ref)].hex()
        insertion = INSERTIONS.get((self.name, o))
        if insertion:
            between, first = insertion
            z = bytes.fromhex(between)
            # the first instruction mapped (a branch: its displacement moves)
            header = all(self._range(h, o + i)[0] == new + i for i in range(first))
            if header and code[new:new + 2] == ref[:2] and \
                    code[new + first:new + first + len(z)] == z and \
                    code[new + first + len(z):new + len(ref) + len(z)] == ref[first:] and \
                    self._range(h, o + first)[0] == new + first + len(z):
                return new, code[new:new + len(ref)].hex()
            error += "; not the known insertion either"
        raise PlacesError("%s %s: K3 site $%X: %s" % (self.name, self.version, o, error))


def _maps():
    try:
        import amiga_places_maps as K
    except ImportError:
        return {}
    return K.MAPS


# Programs without K1/K2 tables (their source is Thalion's FAIRY.S, the
# tool fantasy_auszug.py), described here for the map: 1.20 hunk sizes.
OTHER_PROGRAMS = {
    "fantasy": dict(datei="Fantasy_intro", gepackt=True, exec=[],
                    hunks={1: ("CODE", 4584), 2: ("BIN", 121356), 3: ("BSS", 8740),
                           4: ("BIN", 103200)}),
}


def places_of(name, d, hunks, p):
    """-> Lage of this program file; a file the map does not know must have
    the hunk sizes of 1.20."""
    place_map = _maps().get(name, {}).get(hashlib.sha1(d).hexdigest())
    if place_map is not None:
        return Places(name, place_map)
    sizes = {n: h["groesse"] for n, h in hunks.items()}
    expected = {n: g for n, (_, g) in p["hunks"].items()}
    free = p.get("sprache", set())
    if any(sizes.get(n) != g for n, g in expected.items() if n not in free):
        raise PlacesError("%s: neither 1.20 nor a version in tools/amiga_places_maps.py "
                         "(sizes %s); tools/amiga_places_generate.py makes the map"
                         % (p["datei"], sizes))
    return Places(name)


def for_version(name, d, hunks, p):
    """-> p for this program file: places, sizes and counts of its version."""
    pl = places_of(name, d, hunks, p)
    place_map = pl.place_map
    if place_map is None:
        q = dict(p)
        q["places"] = pl
        return q
    code_n = next(n for n, (a, _) in p["hunks"].items() if a == "CODE")
    code = hunks[code_n]["daten"]
    q = dict(p)
    q["places"] = pl
    q["hunks"] = {n: (a, hunks[n]["groesse"]) for n, (a, _) in p["hunks"].items()}
    q["relok"], q["dff"], q["bfe"] = (place_map["counts"][k] for k in ("relok", "dff", "bfe"))
    q["exec"] = list(place_map["exec"])
    q["k2"] = {pl.place(code_n, o, "K2"): w for o, w in p["k2"].items()}
    k3 = {}
    for o, (old, label) in p.get("k3", {}).items():
        new, b = pl.k3_bytes(code_n, o, old, code)
        k3[new] = (b, label)
    q["k3"] = k3
    return q


NAME = r"\b(%s)(\d+)_([0-9A-F]+)\b"


def names(label):
    """-> sorted set of (hunk, 1.20 offset) our sources name for label."""
    result = set()
    for folder in SOURCE_DIRS:
        for f in glob.glob(os.path.join(ROOT, folder, "*.[sSi]")):
            for m in re.finditer(NAME % re.escape(label), open(f, errors="replace").read()):
                result.add((int(m.group(2)), int(m.group(3), 16)))
    return sorted(result)


def write_names(f, p):
    """equ for every <label><hunk>_<hex> in our sources, moved to this file."""
    label, places = p["marke"], p["places"]
    items = names(label)
    f.write("\n; Places of Thalion's program our sources name (1.20 offset in the\n"
            "; name), here in %s (tools/amiga_places.py)\n" % places.version)
    for h, o in items:
        f.write("%s%d_%X\tequ\t%s%d+$%X\n" % (label, h, o, label, h, places.place(h, o, "named")))
    return len(items)

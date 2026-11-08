#!/usr/bin/env python3
"""amiga_places_generate.py -- developer tool: the place maps of Thalion's
intro and extro, written to tools/amiga_places_maps.py.

Not part of the build.  Needs the German 1.20 Amberfiles (or 1.21: its
intro and extro are 1.20's, they pass every check of amiga_programm.py)
and the Amberfiles of the other versions.  The output holds only numbers:
per program file (by its SHA-1) the ranges of each hunk, where they lie in
that file, the ExecBase sites and the counts of K1 and relocations.

How the places are found
========================
- code hunk: the two hunks are aligned as sequences of words, a relocated
  longword counting as one token with its target hunk.  Equal words give
  "=" ranges.  In a replaced run of the same length, a branch displacement
  (Bcc.w, bsr.w, bra.w, DBcc) whose target the "=" ranges move to the
  other target gives a "b" range (also as the first word of a run of
  another length: code inserted behind a bsr), a relocated longword whose target moves
  alike an "r" range.
- BSS hunks: from the relocation pairs (1.20 value, new value) in "=" and
  "r" places; each shift reaches up to the next (as am2cpu_old_generate.py).
- data hunks: equal ones as a whole, others aligned byte by byte.
Every relocation pair is then checked against the finished map.

Usage: amiga_places_generate.py REF_AMBERFILES OTHER_AMBERFILES [...]
       [--out tools/amiga_places_maps.py]
"""
import argparse
import difflib
import hashlib
import os
import struct
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import amiga_programm as ap                  # noqa: E402
from am2cpu_old_generate import bss_ranges, align_data  # noqa: E402
import am2cpu_old                            # noqa: E402
from am2cpu_read import load_hunks          # noqa: E402


class Error(Exception):
    pass


def read_program_file(p, folder):
    d = open(os.path.join(folder, p["datei"]), "rb").read()
    return d, ap.read_program(d, p)


def tokens(h):
    d, rel = h["daten"], h["rel"]
    t, pos = [], []
    o = 0
    while o + 1 < len(d):
        pos.append(o)
        if o in rel:
            t.append(("R", rel[o]))
            o += 4
        else:
            t.append(d[o] << 8 | d[o + 1])
            o += 2
    pos.append(o)
    return t, pos


def is_branch(w):
    """Bcc.w/bsr.w/bra.w (displacement 0 in the opcode) or DBcc."""
    return (w & 0xF0FF) == 0x6000 or (w & 0xF0F8) == 0x50C8


def code_place_map(ref, old):
    tr, pr = tokens(ref)
    ta, pa = tokens(old)
    sm = difflib.SequenceMatcher(None, tr, ta, autojunk=False)
    equal, branches, reloc = [], [], []
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        if op == "equal" or op == "replace":
            # a replaced run of another length: only its first word can be
            # a branch displacement (code inserted right behind a bsr)
            length = i2 - i1 if op == "equal" or i2 - i1 == j2 - j1 else 1
            for k in range(length):
                a, b = tr[i1 + k], ta[j1 + k]
                oa, ob = pr[i1 + k], pa[j1 + k]
                if isinstance(a, tuple) or isinstance(b, tuple):
                    if a == b:
                        reloc.append((oa, ob, a[1]))
                elif a == b:
                    equal.append((oa, ob))
                elif i1 + k and j1 + k and tr[i1 + k - 1] == ta[j1 + k - 1] and \
                        not isinstance(tr[i1 + k - 1], tuple) and is_branch(tr[i1 + k - 1]):
                    branches.append((oa, ob, a, b))
    ranges = []
    for oa, ob in equal:
        if ranges and ranges[-1][0] + ranges[-1][2] == oa and \
                ranges[-1][1] + ranges[-1][2] == ob:
            ranges[-1][2] += 2
        else:
            ranges.append([oa, ob, 2, "="])

    def mapped(o):
        for a, b, l, _ in ranges:
            if a <= o < a + l:
                return b + o - a
        return None
    for oa, ob, a, b in branches:
        target_a = oa + struct.unpack(">h", struct.pack(">H", a))[0]
        target_b = ob + struct.unpack(">h", struct.pack(">H", b))[0]
        if mapped(target_a) == target_b:
            ranges.append([oa, ob, 2, "b"])
    return ranges, reloc


def value(h, o):
    return struct.unpack(">I", h["daten"][o:o + 4])[0]


def place_map(p, ref, old):
    """-> {hunk: [(1.20 off, new off, length, kind)]}"""
    code_n = next(n for n, (a, _) in p["hunks"].items() if a == "CODE")
    k = {}
    ranges, reloc = code_place_map(ref[code_n], old[code_n])
    pairs = [(z, value(ref[code_n], oa), value(old[code_n], ob), oa, ob)
             for oa, ob, z in reloc]
    for n, (kind, _) in p["hunks"].items():
        if n == code_n:
            continue
        if ref[n]["daten"] == old[n]["daten"] and ref[n]["groesse"] == old[n]["groesse"]:
            k[n] = [(0, 0, ref[n]["groesse"], "=")]
        elif kind == "BSS":
            k[n] = [(a, b, l, "=") for a, b, l, _ in bss_ranges(
                [(rv, n, av) for z, rv, av, _, _ in pairs if z == n], ref[n]["groesse"])]
        else:
            k[n] = [(a, b, l, "=") for a, b, l in align_data(
                ref[n]["daten"], old[n]["daten"], ref[n]["rel"], old[n]["rel"])]
    k[code_n] = [tuple(b) for b in ranges]

    def mapped(h, o):
        for a, b, l, _ in k.get(h, ()):
            if a <= o < a + l or (o == a + l and h != code_n):
                return b + o - a
        return None
    # relocations: those whose target moves alike become "r" places; a
    # pair inside an "=" place that does not fit is an error
    off_count = 0
    for z, rv, av, oa, ob in pairs:
        if mapped(z, rv) == av:
            k[code_n].append((oa, ob, 4, "r"))
        else:
            off_count += 1
    k[code_n].sort()
    return k, off_count


def counts(p, h):
    code_n = next(n for n, (a, _) in p["hunks"].items() if a == "CODE")
    code, rel = h[code_n]["daten"], h[code_n]["rel"]
    claimed = set()
    for r in rel:
        claimed.update(range(r, r + 4))
    dff = bfe = 0
    for o in range(0, len(code) - 3, 2):
        if o in claimed:
            continue
        w = struct.unpack_from(">I", code, o)[0]
        dff += 0x00DFF000 <= w <= 0x00DFF1FF
        bfe += w == 0x00BFE001
    return dict(relok=sum(len(x["rel"]) for x in h.values()), dff=dff, bfe=bfe)


def version(folder):
    path = os.path.join(folder, "AM2_CPU")
    old = am2cpu_old.read_old(path, check=True)
    if old:
        return old[1]
    v = am2cpu_old.version(load_hunks(path))
    if v:
        return v
    # Pyrdacor's 1.21: the version lines of Text.amb
    import build_name
    return " ".join(bytes(c for c in z if c >= 32).decode("latin1")
                    for z in build_name.game_files_version(folder))


def same_layout(p, ref, old):
    """-> None when old is to be mapped, else why it is left out: a file
    with other hunks is another program (Pyrdacor's Polish and Czech intro
    and extro)."""
    kind = {"CODE": "CODE", "DC": "DATA", "BIN": "DATA", "BSS": "BSS"}
    if set(old) != set(p["hunks"]) or any(
            old[n]["art"] not in (None, kind[k]) for n, (k, _) in p["hunks"].items()):
        return "another program (hunks %s)" % sorted(old)
    return None


def main():
    pa = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    pa.add_argument("ref")
    pa.add_argument("others", nargs="+")
    pa.add_argument("--out", default=os.path.join(os.path.dirname(
        os.path.abspath(__file__)), "amiga_places_maps.py"))
    a = pa.parse_args()
    z = ['"""amiga_places_maps.py -- generated by tools/amiga_places_generate.py.',
         "",
         "Places of Thalion's intro and extro in other versions against 1.20: per",
         "program, per file SHA-1, per hunk (1.20 offset, offset, length, kind),",
         "kind '=' equal bytes, 'b' a branch displacement, 'r' a relocated",
         "longword; the ExecBase sites and the counts of K1 and relocations.",
         "Numbers only, no game data.  Do not edit by hand.",
         '"""', "", "MAPS = {"]
    import amiga_places
    for name, p in dict(ap.PROGRAMME, **amiga_places.OTHER_PROGRAMS).items():
        z.append("    %r: {" % name)
        d_ref, ref = read_program_file(p, a.ref)
        code_n = next(n for n, (k, _) in p["hunks"].items() if k == "CODE")
        seen = {hashlib.sha1(d_ref).hexdigest()}
        for folder in a.others:
            d = open(os.path.join(folder, p["datei"]), "rb").read()
            fp = hashlib.sha1(d).hexdigest()
            if fp in seen:
                continue
            seen.add(fp)
            ver = version(folder)
            try:
                old = ap.read_program(d, p)
                note = same_layout(p, ref, old)
            except Exception as e:      # imploder_exe, struct: not read
                note = "not read (%s)" % (e.__class__.__name__)
            if note:
                print("%s %s: left out, %s" % (name, ver, note))
                continue
            k, off_count = place_map(p, ref, old)
            exec_ = []
            for o in p["exec"]:
                for x, y, l, kind in k[code_n]:
                    if kind == "=" and x <= o - 2 and o + 4 <= x + l:
                        exec_.append(y + o - x)
            z.append("        %r: {" % fp)
            z.append("            'version': %r," % ver)
            z.append("            'counts': %r," % counts(p, old))
            z.append("            'exec': [%s]," % ", ".join("0x%04X" % o for o in exec_))
            z.append("            'hunks': {")
            for n in sorted(k):
                z.append("                %d: [" % n)
                for b in k[n]:
                    z.append("                    (0x%05X, 0x%05X, 0x%05X, %r)," % b)
                z.append("                ],")
            z.append("            },")
            z.append("        },")
            coverage = sum(l for _, _, l, _ in k[code_n])
            print("%s %s: code %d/%d bytes placed, %d relocation pairs off, exec %d of %d"
                  % (name, ver, coverage, ref[code_n]["groesse"], off_count,
                     len(exec_), len(p["exec"])))
        z.append("    },")
    z.append("}")
    open(a.out, "w").write("\n".join(z) + "\n")
    print("-> " + a.out)


if __name__ == "__main__":
    main()

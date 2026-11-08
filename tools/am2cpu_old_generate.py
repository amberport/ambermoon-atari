#!/usr/bin/env python3
"""am2cpu_old_generate.py -- developer tool: the place tables for Thalion's
AM2_CPU 1.0x, written to tools/am2cpu_old_maps.py.

Not part of the build.  Needs a 1.21 AM2_CPU (any language; its code is the
same in all) and the old one.  The output holds only numbers: for each hunk
of 1.21 the ranges and where they lie in the old file.  No game data.

How the places are found
========================
- hunk 0 (code): the two code hunks are aligned as sequences of words, a
  relocated longword counting as one token.  Equal runs give the ranges.
- relocations inside equal runs pair a 1.21 target (hunk, value) with an
  old one.  For BSS hunks, which have no content, these pairs are the
  ranges.
- data hunks (3, 4, 5, 13): aligned by content, byte by byte.

Usage: am2cpu_old_generate.py AM2_CPU_1.21 OLD_AM2_CPU [OLD_AM2_CPU ...]
       [--out tools/am2cpu_old_maps.py]
"""
import argparse
import difflib
import os
import pickle
import struct
import sys
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from am2cpu_read import load_hunks          # noqa: E402
import am2cpu_old                            # noqa: E402

MIN_CODE = 8        # bytes; shorter equal runs in the code are not trusted
MIN_DATA = 16      # bytes; likewise in data hunks


CACHE = None        # --cache: directory for SequenceMatcher results


class _Result:
    def __init__(self, blocks, ops):
        self.blocks, self.ops = blocks, ops

    def get_matching_blocks(self):
        return self.blocks

    def get_opcodes(self):
        return self.ops


def _matcher(a, b):
    """difflib.SequenceMatcher, its results kept in CACHE (minutes each)."""
    import hashlib
    key_hash = hashlib.sha1(repr((a, b)).encode()).hexdigest()
    path = CACHE and os.path.join(CACHE, "sm_" + key_hash + ".pkl")
    if path and os.path.exists(path):
        return pickle.load(open(path, "rb"))
    sm = difflib.SequenceMatcher(None, a, b, autojunk=False)
    e = _Result(sm.get_matching_blocks(), sm.get_opcodes())
    if path:
        pickle.dump(e, open(path, "wb"))
    return e


def tokens(h):
    d, rel = h["data"], h["reloc"]
    t, pos = [], []
    o = 0
    while o + 1 < len(d):
        pos.append(o)
        if o in rel:
            t.append(-1)
            o += 4
        else:
            t.append(d[o] << 8 | d[o + 1])
            o += 2
    pos.append(o)
    return t, pos


def align_code(new, old):
    """-> (ranges [(new off, old off, bytes)], reloc pairs)."""
    tn, pn = tokens(new)
    ta, pa = tokens(old)
    sm = _matcher(tn, ta)
    ranges, pairs = [], []
    # Ranges: equal runs, and replaced runs of the same length -- Thalion's
    # own code (with its own relocations) where 1.2x
    # changed it in place (e.g. "move.l #Text,(a2)+" against 1.2x's
    # "move.l Place,(a2)+"; put_dpoly's inline loop against 1.2x's jumps).
    for op, i1, i2, j1, j2 in sm.get_opcodes():
        length = pn[i2] - pn[i1]
        if length != pa[j2] - pa[j1]:
            continue
        joined = ranges and ranges[-1][0] + ranges[-1][2] == pn[i1] and \
            ranges[-1][1] + ranges[-1][2] == pa[j1]
        # a short equal run counts only right behind an accepted range
        if op == "equal" and (length >= MIN_CODE or joined) or op == "replace":
            if joined:
                ranges[-1] = (ranges[-1][0], ranges[-1][1], ranges[-1][2] + length)
            else:
                ranges.append((pn[i1], pa[j1], length))
    for b in sm.get_matching_blocks():
        if not b.size:
            continue
        for k in range(b.size):
            if tn[b.a + k] == -1:
                on, oa = pn[b.a + k], pa[b.b + k]
                pairs.append((new["reloc"][on],
                              struct.unpack(">I", new["data"][on:on + 4])[0],
                              old["reloc"][oa],
                              struct.unpack(">I", old["data"][oa:oa + 4])[0]))
    return ranges, pairs


def align_data(new, old, rel_new, rel_old):
    """Byte alignment; relocated longwords are compared as 'some pointer'."""
    def mask(d, rel):
        m = list(d)
        for o in rel:
            for k in range(4):
                if o + k < len(m):
                    m[o + k] = -1
        return m
    sm = _matcher(mask(new, rel_new), mask(old, rel_old))
    return [(b.a, b.b, b.size) for b in sm.get_matching_blocks() if b.size >= MIN_DATA]


def bss_ranges(pairs, new_size):
    """Pairs (new value, old hunk, old value) -> ranges.  Each run of one
    shift reaches up to the next run, so every BSS offset has a place."""
    m = defaultdict(Counter)
    for nv, oh, ov in pairs:
        m[nv][(oh, ov - nv)] += 1
    runs = []
    for nv in sorted(m):
        (oh, d), _ = m[nv].most_common(1)[0]
        if runs and runs[-1][2:] == [oh, d]:
            continue
        runs.append([nv, None, oh, d])
    result = []
    for i, (a, _, oh, d) in enumerate(runs):
        start = 0 if i == 0 else a
        end = runs[i + 1][0] if i + 1 < len(runs) else new_size
        if start + d < 0:
            start = -d
        result.append((start, start + d, end - start, oh))
    return result


def place_map(new, old):
    """-> {new hunk: [(new off, old off, length, old hunk)]}"""
    k = defaultdict(list)
    ranges, pairs = align_code(new[0], old[0])
    k[0] = [(n, o, l, 0) for n, o, l in ranges]
    # which old hunk each new hunk went to (by the reloc pairs)
    target = defaultdict(Counter)
    for nh, nv, oh, ov in pairs:
        target[nh][oh] += 1
    hunk_to = {nh: c.most_common(1)[0][0] for nh, c in target.items()}
    for nh in sorted(hunk_to):
        # 11: 1.2x's own CPU/blitter code; 6: its pointer table for the
        # texts of Text.amb.  Neither exists in the old file.
        if nh in (0, 6, 11):
            continue
        oh = hunk_to[nh]
        if new[nh]["type"] == "BSS" and nh != 5:
            k[nh] = [(a, b, l, oh) for a, b, l, oh in
                     bss_ranges([(nv, h2, ov) for h, nv, h2, ov in pairs
                                   if h == nh and h2 == oh], new[nh]["size"])]
        elif new[nh]["type"] != "BSS":
            k[nh] = [(a, b, l, oh) for a, b, l in align_data(
                new[nh]["data"], old[oh]["data"], new[nh]["reloc"], old[oh]["reloc"])]
    # Labels: each old target the code names, with its 1.21 counterpart.
    # They take precedence over the ranges: where a table starts in the
    # old file can differ from where its content matches (a header word
    # more or less), and the code's pointer is what counts.
    m = defaultdict(Counter)
    for nh, nv, oh, ov in pairs:
        if nh != 11:
            m[(oh, ov)][(nh, nv)] += 1
    labels = sorted((oh, ov) + c.most_common(1)[0][0] for (oh, ov), c in m.items()
                    if c.most_common(1)[0][1] * 2 > sum(c.values()))
    return dict(k), hunk_to, labels


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("new")
    p.add_argument("old", nargs="+")
    p.add_argument("--out", default=os.path.join(os.path.dirname(
        os.path.abspath(__file__)), "am2cpu_old_maps.py"))
    p.add_argument("--cache", help="directory for the alignment results")
    a = p.parse_args()
    new = load_hunks(a.new)
    global CACHE
    CACHE = a.cache
    sizes = [h["size"] for h in new]
    z = ['"""am2cpu_old_maps.py -- generated by tools/am2cpu_old_generate.py.',
         "",
         "Places of Thalion's AM2_CPU 1.0x against 1.21: per version, per 1.21",
         "hunk, ranges (1.21 offset, old offset, length, old hunk), and the labels",
         "(old hunk, old offset, 1.21 hunk, 1.21 offset) the code names.  Numbers",
         "only, no game data.  Do not edit by hand.",
         '"""',
         "",
         "HUNKS_121 = %r" % sizes,
         "TYPES_121 = %r" % [h["type"] for h in new],
         "",
         "MAPS = {"]
    for path in a.old:
        old, ver = am2cpu_old.read_old(path)
        k, hunk_to, labels = place_map(new, old)
        z.append("    %r: {" % (ver,))
        z.append("        'old_sizes': %r," % [h["size"] for h in old])
        z.append("        'hunk_of': %r," % dict(sorted(hunk_to.items())))
        for nh in sorted(k):
            z.append("        %d: [" % nh)
            for b in k[nh]:
                z.append("            (0x%05X, 0x%05X, 0x%05X, %d)," % b)
            z.append("        ],")
        z.append("        'labels': [")
        for m in labels:
            z.append("            (%d, 0x%05X, %d, 0x%05X)," % m)
        z.append("        ],")
        z.append("    },")
        coverage = {nh: sum(b[2] for b in k[nh]) for nh in k}
        print("%s: %s" % (ver, ", ".join("%d:%d/%d" % (nh, coverage[nh], sizes[nh])
                                         for nh in sorted(k))))
    z.append("}")
    open(a.out, "w").write("\n".join(z) + "\n")
    print("-> " + a.out)


if __name__ == "__main__":
    main()

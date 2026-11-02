#!/usr/bin/env python3
"""am2cpu_old.py -- Thalion's AM2_CPU 1.0x as a virtual 1.21 AM2_CPU.

Thalion's disks (1.01 German, 1.07 English) carry AM2_CPU imploded, with
six hunks: code, three BSS/data hunks, one data hunk holding all tables and
texts, one BSS.  1.2x (Pyrdacor, rebuilt from the source) has fourteen.
The code is nearly the same; the places are not.

This module unpacks the old file and lays it out as 1.21: every range that
tools/am2cpu_old_maps.py names is copied to its 1.21 place, and every
relocation in it is moved to the 1.21 hunk and offset of its target.  What
has no place in the old file (1.2x's own code in hunks 8, 11, 12, the
pointer table in hunk 6) stays zero.  The build tools then read the
virtual file as they read 1.21 (am2cpu_places.py moves the 1.20 places), and
their checks prove the result: a wrong range breaks a check.

Relocations whose target has no 1.21 place keep their old value and get
the target hunk UNKNOWN; a tool that meets one in a piece stops.

    read_am2cpu(path) -> hunks as am2cpu_lesen.lies_hunks, virtual for 1.0x
    is_old(path)      -> True for an imploded (Thalion 1.0x) AM2_CPU
    read_old(path)    -> (old hunks, version), unpacked, 0-based
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import read_hunks                     # noqa: E402
from imploder_exe import entpacke, ExeImploderError  # noqa: E402

UNKNOWN = 99
VERSION = re.compile(rb"Ambermoon v(\d\.\d\d)\x00+(\d+-\d+-\d{4}) / (\w+)")


# The 46 places of part 1 of Text.amb (1.20/1.21 hunk 6, the same in both):
# 1.2x fills them at start with pointers to the texts.  0-2 lie in hunk 6
# (World_map_names), the others in hunk 4.  The virtual hunk 6 carries this
# table, as am2cpu_auszug.py reads it there.  Numbers only.
TEXT_PLACES = [
    (6, 0x104), (6, 0x108), (6, 0x10C),
    0x7D0E, 0x7D16, 0x7D1E, 0x7D26, 0x7D2E, 0x7D36, 0x7D5E, 0x7D62, 0x7D66,
    0x7F88, 0x7F8C, 0x7F90, 0x7F98, 0x7FA4, 0x7FAC, 0x7FB8, 0x7FC0, 0x7FC8,
    0x7FD4, 0x7FE0, 0x7FF0, 0x7FF8, 0x8000, 0x800C, 0x8014, 0x8020, 0x8028,
    0x8030, 0x803C, 0x8044, 0x8050, 0x8058, 0x8064, 0x806C, 0x8074, 0x807C,
    0x8088, 0x8090, 0x809C, 0x80A4, 0x80AC, 0x80B8, 0x80C0,
]


class OldError(Exception):
    pass


def version(hunks):
    """-> 'v1.07 26-3-1994 English' from the version lines, or None."""
    for h in hunks:
        m = VERSION.search(h["daten"])
        if m:
            return "v%s %s %s" % tuple(x.decode("latin1") for x in m.groups())
    return None


def is_old(path):
    return read_old(path, check=True) is not None


def read_old(path, check=False):
    raw = read_hunks(open(path, "rb").read())
    try:
        content, relocs = entpacke(raw)
    except (ExeImploderError, IndexError, KeyError, ValueError, StopIteration):
        if check:
            return None
        raise OldError("%s: not an imploded AM2_CPU" % path)
    hunks = []
    for i in sorted(content):
        hunks.append({"typ": "?", "groesse": len(content[i]), "daten": content[i],
                      "reloc": {o: after - 1 for o, after in relocs[i]}})
    return hunks, version(hunks)


def _reverse_map(place_map):
    """-> {old hunk: [(old off, new off, length, new hunk)]}, sorted."""
    r = {}
    for nh, ranges in place_map.items():
        if not isinstance(nh, int):
            continue
        for n, o, l, oh in ranges:
            r.setdefault(oh, []).append((o, n, l, nh))
    for oh in r:
        r[oh].sort()
    return r


def _to_new(reverse, oh, ov, labels):
    """Old target -> (new hunk, new value) or None.  A label the code names
    first; then the range holding it; a value just behind a range (an end
    label) belongs to that range."""
    if (oh, ov) in labels:
        return labels[(oh, ov)]
    hits = None
    for o, n, l, nh in reverse.get(oh, []):
        if o <= ov < o + l:
            return nh, n + ov - o
        if ov == o + l:
            hits = (nh, n + l)
    return hits


SHORT_MAX = 16


def _short_places(data, nh, place_map, old):
    """Short data the code names, but too short for the content alignment
    (Attrskill_nr " 01", Charges_txt "(01)" in hunk 4): copied from each
    such label up to the next label or range, at most SHORT_MAX
    bytes.  Only where no range lies."""
    ranges = sorted((n, n + l) for n, o, l, oh in place_map.get(nh, []))
    labels = sorted((nv, oh, ov) for oh, ov, h, nv in place_map.get("labels", []) if h == nh)
    for i, (nv, oh, ov) in enumerate(labels):
        if any(a <= nv < b for a, b in ranges):
            continue
        end = min([a for a, b in ranges if a > nv] +
                   [m[0] for m in labels[i + 1:] if m[0] > nv] + [nv + SHORT_MAX])
        source = old[oh]["daten"][ov:ov + end - nv]
        if any(ov <= p < ov + len(source) for p in old[oh]["reloc"]):
            continue                      # pointers: not short data
        data[nv:nv + len(source)] = source


def virtual(old, place_map, sizes, types):
    reverse = _reverse_map(place_map)
    labels = {(oh, ov): (nh, nv) for oh, ov, nh, nv in place_map.get("labels", [])}
    hunks = []
    unresolved = 0
    for nh, size in enumerate(sizes):
        data = bytearray(size)
        reloc = {}
        for n, o, l, oh in place_map.get(nh, []):
            source = old[oh]
            data[n:n + l] = source["daten"][o:o + l]
            for p, th in source["reloc"].items():
                if not o <= p < o + l:
                    continue
                if p + 4 > o + l:
                    raise OldError("relocation at old %d:$%X crosses a range end" % (oh, p))
                np_ = n + p - o
                tv = int.from_bytes(source["daten"][p:p + 4], "big")
                target = _to_new(reverse, th, tv, labels)
                if target is None:
                    reloc[np_] = UNKNOWN
                    unresolved += 1
                else:
                    reloc[np_] = target[0]
                    data[np_:np_ + 4] = target[1].to_bytes(4, "big")
        if types[nh] == "DATA":
            _short_places(data, nh, place_map, old)
        if nh == 6:
            for i, place in enumerate(TEXT_PLACES):
                h, v = place if isinstance(place, tuple) else (4, place)
                data[4 * i:4 * i + 4] = v.to_bytes(4, "big")
                reloc[4 * i] = h
        hunks.append({"typ": types[nh], "groesse": size,
                      "daten": bytes(data) if types[nh] != "BSS" else b"",
                      "reloc": reloc})
    return hunks, unresolved


def gaps(hunks, h, begin, stop):
    """Parts of [von, bis) in hunk h that no range filled (virtual image)."""
    result, o = [], begin
    for a, b in sorted(hunks[0]["ranges"].get(h, [])):
        if b <= o or a >= stop:
            continue
        if a > o:
            result.append((o, a))
        o = max(o, b)
    if o < stop:
        result.append((o, stop))
    return result


def read_am2cpu(path, message=None):
    """AM2_CPU as hunks.  1.2x as it is; 1.0x virtual, laid out as 1.21."""
    from am2cpu_lesen import lies_hunks
    old_read = read_old(path, check=True)
    if old_read is None:
        return lies_hunks(path)
    old, ver = old_read
    import am2cpu_old_maps as K
    if ver not in K.MAPS:
        raise OldError("AM2_CPU %s: no place table for this version (known: %s)"
                        % (ver, ", ".join(sorted(K.MAPS))))
    place_map = K.MAPS[ver]
    if [h["groesse"] for h in old] != place_map["old_sizes"]:
        raise OldError("AM2_CPU %s: hunk sizes differ from the table" % ver)
    hunks, unresolved = virtual(old, place_map, K.HUNKS_121, K.TYPES_121)
    hunks[0]["virtual"] = ver
    hunks[0]["ranges"] = {nh: [(n, n + l) for n, o, l, oh in b]
                            for nh, b in place_map.items() if isinstance(nh, int)}
    if message:
        message("Thalion AM2_CPU %s, laid out as 1.21 (%d relocations without a place)"
                % (ver, unresolved))
    return hunks


if __name__ == "__main__":
    for path in sys.argv[1:]:
        h = read_am2cpu(path, print)
        print(path, [(x["typ"], x["groesse"], len(x["reloc"])) for x in h])

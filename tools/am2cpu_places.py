#!/usr/bin/env python3
"""am2cpu_places.py -- where the 1.20 places of AM2_CPU lie in another version.

Since 2026-11-01.  Untested on 1.20 itself (the shift there must come out
as zero); checked on 1.21 de/en/fr/pl/cz and on Thalion's 1.01/1.07 laid
out as 1.21 (am2cpu_old.py).

The tables in am2cpu_auszug.py and am2cpu_code.py give places as they are
in AM2_CPU of the German version 1.20.  Pyrdacor's 1.21 (all languages, one
AM2_CPU) keeps the data hunks as they are, but code in hunk 0 has moved
(fixes inserted, 1.20: 183100 bytes, 1.21: 183352).

This module finds the shift of hunk 0 without any bytes of Thalion's code
in the repository: only from the places the tools already know.

1. **Anchors.**  Every place in hunk 0 where the tools expect a known
   operand (a lea/move to a data piece, a pointer to a message list, a
   pointer to a mouse pointer record) is searched in the given AM2_CPU:
   same instruction word, same operand, a relocation at the operand.  The
   target lies in a data hunk whose layout has not moved; the check of that
   stays in am2cpu_auszug.py.
2. **Shift map.**  Each anchor gives one or more possible shifts.  The
   choice with the smallest total change along hunk 0 wins (dynamic
   programming); shifts are piecewise constant.
3. **Code pieces.**  A piece of am2cpu_code.py takes the shift of its
   region.  Where its region lies between two anchors with different
   shifts, each candidate is tried: every relocation inside the moved piece
   must name a known target (NAMEN, the BSS and data blocks) or a place in
   another moved piece.  Exactly one candidate must pass.

For 1.20 every shift is 0, and everything stays as before.
"""
import struct
import sys

HUNK0_LENGTH_120 = 183100   # docs/archive/08: hunk 0 of AM2_CPU 1.20
WINDOW = 0x1000             # largest shift searched, either way


class PlacesError(Exception):
    pass


def _reloc_value(hunk, o):
    if o not in hunk["reloc"]:
        return None
    return struct.unpack(">I", hunk["daten"][o:o + 4])[0]


def anchors_120(A, h6):
    """-> list of (1.20 offset of the operand, instruction word or None,
    operand value, what).  A = module am2cpu_auszug, h6 = hunk 6 data."""
    places = {n: off for n, _, off, _, _ in A.STUECKE}
    for i, n in enumerate(A.ZEIGER):
        if n:
            places[n] = A.ZEIGER_ANFANG + i * A.ZEIGER_SATZ
    result = []
    for name, st, instr, where, *plus in A.CODEBELEGE:
        result.append((st + 2, instr, places[name] + (plus[0] if plus else 0), name))
    for m in A.MELDUNG_LISTEN:
        if m:
            for st in m[2]:
                result.append((st, None, m[1], m[0]))
    h, o, n = A.MELDUNG_TABELLE
    place = struct.unpack(">%dI" % n, h6[o:o + 4 * n])
    for name, t, sts, _ in A.MELDUNG_EINZEL:
        for st in sts:
            result.append((st, None, place[t], name))
    result.append((A.MAGIC_TXT_STELLE, None, 0x8100, "Magic_txt"))
    for hunk, st, name, where in A.VERWEISE:
        if hunk == 0:
            result.append((st, None, places[name], name))
    return sorted(result)


def candidates(h0, anchors):
    """-> list of (offset 1.20, [shifts], what)."""
    d = h0["daten"]
    result = []
    for st, instr, value, what in anchors:
        ks = []
        for delta in range(-WINDOW, WINDOW + 1, 2):
            o = st + delta
            if o < 2 or o + 4 > len(d):
                continue
            if _reloc_value(h0, o) != value:
                continue
            if instr is not None and struct.unpack(">H", d[o - 2:o])[0] != instr:
                continue
            ks.append(delta)
        result.append((st, ks, what))
    return result


def place_map(h0, anchors):
    """-> sorted list of (offset 1.20, shift), one per anchor that was found,
    plus the end of the hunk.  Anchors without a hit are reported."""
    ks = candidates(h0, anchors)
    missing = [(st, what) for st, k, what in ks if not k]
    ks = [(st, k, what) for st, k, what in ks if k]
    end = len(h0["daten"]) - HUNK0_LENGTH_120
    ks.append((HUNK0_LENGTH_120, [end], "end of hunk 0"))
    # dynamic programming: smallest total change, ties to the smaller shift
    costs = [{d: (abs(d), None) for d in ks[0][1]}]
    for i in range(1, len(ks)):
        z = {}
        for d in ks[i][1]:
            best = None
            for dv, (c, _) in costs[-1].items():
                cc = c + abs(d - dv) * 1000 + abs(d)
                if best is None or cc < best[0]:
                    best = (cc, dv)
            z[d] = best
        costs.append(z)
    d = min(costs[-1], key=lambda x: costs[-1][x][0])
    choice = []
    for i in range(len(ks) - 1, -1, -1):
        choice.append((ks[i][0], d, ks[i][2], len(ks[i][1])))
        d = costs[i][d][1]
    choice.reverse()
    return choice, missing


def shifts_at(choice, o):
    """-> set of possible shifts for 1.20 offset o of hunk 0."""
    before = [w for w in choice if w[0] <= o]
    after = [w for w in choice if w[0] > o]
    if not before:
        return {after[0][1]}
    if not after:
        return {before[-1][1]}
    return {before[-1][1], after[0][1]}


def sections(choice):
    """-> list of (from, to, shift): ranges of 1.20 offsets with one shift
    proved by anchors at both ends."""
    result = []
    for w in choice:
        if result and result[-1][2] == w[1]:
            result[-1][1] = w[0]
        else:
            result.append([w[0], w[0], w[1]])
    return [tuple(a) for a in result]


def _fits(hunks, C, h, begin, stop, tables, d, all_pieces, s9):
    """Every relocation in the moved piece names a known target; targets
    in hunk 9 are taken back by s9.  -> (ok, why, hits on NAMEN)."""
    hk = hunks[h]
    bss = lambda zh, zv: any(zh == bh and bv <= zv < bb for bh, bv, bb in C.BSS_BLOECKE)
    in_data = lambda zh, zv: any(zh == bh and bv <= zv < bb for bh, bv, bb in C.DATEN_BLOECKE)
    n = hits = 0
    for o in sorted(r for r in hk["reloc"] if begin + d <= r < stop + d):
        if any(tv + d <= o < tb + d for tv, tb in tables):
            return False, "relocation in a table", 0
        zh = hk["reloc"][o]
        zv = struct.unpack(">I", hk["daten"][o:o + 4])[0]
        n += 1
        if zh in (0, 11):
            if not any(sh == zh and sv + sd <= zv < sb + sd
                       for sh, sv, sb, sds in all_pieces for sd in sds):
                return False, "target %d:$%05X outside the pieces" % (zh, zv), 0
            continue
        if zh == 9:
            zv -= s9
        if (zh, zv) in C.NAMEN:
            hits += 1
        elif not (bss(zh, zv) or in_data(zh, zv)):
            return False, "target %d:$%05X has no name" % (zh, zv), 0
    return True, "%d relocations" % n, hits


S9_WINDOW = 0x40
_instructions_cache = {}


def _instructions_fit(hunks, C, h, begin, stop, tables, d):
    """The moved piece reads as instructions from its first to its last
    byte, the last one returns (rts/rte/jmp/bra) or continues in
    FORTSETZUNGEN, and every branch stays inside.  The same tests as
    am2cpu_code.py, step 1 and 3, in short."""
    import re
    key = (h, begin, stop, d)
    if key in _instructions_cache:
        return _instructions_cache[key]
    data = hunks[h]["daten"]
    parts, o = [], begin + d
    for tv, tb in sorted(tables):
        parts.append((o, tv + d))
        o = tb + d
    parts.append((o, stop + d))
    ok = True
    for tv, tb in parts:
        if tv >= tb:
            continue
        z = C.dis(data, tv, tb, "m68k:68000")
        if not z or z[0][0] != tv or z[-1][0] + z[-1][1] != tb:
            ok = False
            break
        if any(re.match(r"\.(short|long|byte)\b", t) for _, _, t in z):
            ok = False
            break
        last_line = z[-1][2]
        if not ((h, stop) in C.FORTSETZUNGEN and tb == stop + d) and \
                not re.match(r"(rts|rte|jmp|bra[sw]?)\b", last_line):
            ok = False
            break
        for _, _, t in z:
            m = re.match(r"(b[a-z]{1,2}[sw]?|db[a-z]{1,2}\s+%d\d,|bsr[sw]?)\s*0x([0-9a-f]+)$", t)
            if m and not (begin + d <= int(m.group(2), 16) < stop + d) and \
                    (h, int(m.group(2), 16) - d) not in C.AUSGAENGE:
                ok = False
                break
        if not ok:
            break
    _instructions_cache[key] = ok
    return ok


def adapt_pieces(C, A, hunks):
    """Moves the 1.20 places in module C (am2cpu_code) to the given
    AM2_CPU: hunk 0 by the anchor map, hunk 9 (the library's variables) by
    one shift s9 found from the pieces themselves.  -> report lines."""
    anchors = anchors_120(A, hunks[6]["daten"])
    choice, missing = place_map(hunks[0], anchors)
    if missing:
        raise PlacesError("anchors not found: %s" % ", ".join(w for _, w in missing))
    report = ["hunk 0: %d anchors; %s" % (len(choice) - 1, ", ".join(
        "$%05X..$%05X %+X" % a for a in sections(choice)))]
    cands = []
    for name, h, begin, stop, tab, evidence in C.STUECKE:
        ds = shifts_at(choice, begin) | shifts_at(choice, stop - 1) if h == 0 else {0}
        ds = set(range(min(ds), max(ds) + 2, 2))
        cands.append((h, begin, stop, sorted(ds)))
    solutions = []
    for s9 in range(-S9_WINDOW, S9_WINDOW + 2, 2):
        chosen, hits, all_good = [], 0, True
        for (name, h, begin, stop, tab, evidence), (_, _, _, ds) in zip(C.STUECKE, cands):
            good = [(d,) + _fits(hunks, C, h, begin, stop, tab, d, cands, s9)[1:]
                   for d in ds if _fits(hunks, C, h, begin, stop, tab, d, cands, s9)[0]]
            if len(good) > 1:
                good = [g[:1] + (g[1] + ", instructions fit",) + g[2:] for g in good
                       if _instructions_fit(hunks, C, h, begin, stop, tab, g[0])]
            if len(good) != 1:
                all_good = False
                break
            chosen.append(good[0])
            hits += good[0][2]
        if all_good:
            solutions.append((hits, s9, chosen))
    if not solutions:
        raise PlacesError("no shift of hunk 9 lets every piece fit")
    solutions.sort(reverse=True)
    if len(solutions) > 1 and solutions[0][0] == solutions[1][0]:
        raise PlacesError("hunk 9: shifts %+X and %+X fit equally well"
                         % (solutions[0][1], solutions[1][1]))
    hits, s9, chosen = solutions[0]
    report.append("hunk 9: shift %+X (%d hits on NAMEN; next best: %s)" % (
        s9, hits, ", ".join("%+X:%d" % (l[1], l[0]) for l in solutions[1:4]) or "none"))
    new, shift = [], {}
    for (name, h, begin, stop, tab, evidence), (_, _, _, ds), (d, why, _) in zip(
            C.STUECKE, cands, chosen):
        shift[(h, begin, stop)] = d
        new.append((name, h, begin + d, stop + d, [(a + d, b + d) for a, b in tab], evidence))
        report.append("%-22s %d:$%05X %+X (%s; tried %s)" % (
            name or "(piece)", h, begin, d, why, ",".join("%+X" % x for x in ds)))

    def shift_at(h, v, include_end=False):
        for (sh, sv, sb), d in shift.items():
            if sh == h and (sv <= v < sb or (include_end and v == sb)):
                return d
        ds = shifts_at(choice, v) if h == 0 else {0}
        if len(ds) != 1:
            raise PlacesError("%d:$%05X lies between two shifts" % (h, v))
        return ds.pop()
    C.STUECKE[:] = new
    for tab, end in ((C.EINSPRUENGE, False), (C.FORTSETZUNGEN, True),
                      (C.CPU_020, False), (C.AUSGAENGE, False)):
        old = dict(tab)
        tab.clear()
        for (h, v), x in old.items():
            tab[(h, v + shift_at(h, v, end))] = x
    if s9:
        old = dict(C.NAMEN)
        C.NAMEN.clear()
        for (h, v), x in old.items():
            C.NAMEN[(h, v + s9 if h == 9 else v)] = x
        C.BSS_BLOECKE[:] = [(h, a + s9, b + s9) if h == 9 else (h, a, b)
                            for h, a, b in C.BSS_BLOECKE]
        C.NAME_SHIFT[9] = s9       # Am2cpu_9_* names stay 1.20 offsets
    return report


def adapt_extract(A, hunks):
    """Moves the hunk 0 places in module A (am2cpu_auszug) to the given
    AM2_CPU; they are the anchors themselves.  -> report lines."""
    anchors = anchors_120(A, hunks[6]["daten"])
    choice, missing = place_map(hunks[0], anchors)
    if missing:
        raise PlacesError("anchors not found: %s" % ", ".join(w for _, w in missing))
    d = {st: s for st, s, _, _ in choice}
    A.CODEBELEGE[:] = [(n, st + d[st + 2], b, w, *p) for n, st, b, w, *p in A.CODEBELEGE]
    A.MELDUNG_LISTEN[:] = [m and (m[0], m[1], [s + d[s] for s in m[2]], m[3])
                           for m in A.MELDUNG_LISTEN]
    A.MELDUNG_EINZEL[:] = [(n, t, [s + d[s] for s in st], w) for n, t, st, w in A.MELDUNG_EINZEL]
    A.MAGIC_TXT_STELLE += d[A.MAGIC_TXT_STELLE]
    A.VERWEISE[:] = [(h, st + d[st] if h == 0 else st, n, w) for h, st, n, w in A.VERWEISE]
    return ["hunk 0: %d anchors; %s" % (len(choice) - 1, ", ".join(
        "$%05X..$%05X %+X" % a for a in sections(choice)))]


def _h0(hunks):
    return hunks[0]

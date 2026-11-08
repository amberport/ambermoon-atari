#!/usr/bin/env python3
"""compare.py -- how Big Alec turned Thalion's four Paula voices into three YM channels.

For every pair of tools/musik_ym.inf, both players run tick by tick
(sa_log.py, ym_log.py) and the notes are compared frame by frame:

- **Amiga:** a voice sounds when volume and period are set.  A synth
  sound's pitch is exact (Paula clock / period / buffer length, times the
  cycles of the wave in the buffer).  A
  sample's is not known; its note is counted as if period 428 were C-4,
  and the comparison finds the true offset per sample.
- **YM:** a channel sounds with its tone (mixer bit clear) or as buzzer
  (envelope volume, tone off, a repeating shape: saw 2 MHz/256/EP,
  triangle /512).  Noise and SID timers (a timer handler that writes the
  channel's volume) are counted.
- **Lag:** the shift in frames with the most notes in common, per window
  of 20 s, so a different tempo would show as a drift.
- **Voices:** for each YM channel the Amiga voice whose notes it plays
  most often (same pitch class), with the octave between them; for each
  sample the semitone offset that matched most often on one YM channel.
  The octave of a sample voice is relative to that offset.

The report goes to --out/compare.txt (default build/sa_to_ym), with a line
per pair on stdout.

Usage:  VENV/bin/python tools/sa_to_ym/compare.py [--out DIR] [--seconds N]
            [--only THALION ...]
"""
import argparse
import collections
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.dirname(HERE)]
import paths                         # noqa: E402
import sa_log                        # noqa: E402
import ym_log                        # noqa: E402
from pairs import pairs              # noqa: E402

YM_CLOCK = 2_000_000


def midi(f):
    return 12 * math.log2(f / 440) + 69 if f > 0 else None


def amiga_notes(song, ticks):
    """-> per tick, per voice: None or (note, instrument, restarted).  The
    instrument is the one of the last restart (sa_log.py)."""
    out = []
    inst = [(None, 0)] * 4
    for _ in range(ticks):
        row = []
        for v, (per, vol, lc, length, trig) in enumerate(song.tick()):
            if trig:
                inst[v] = song.where(lc)
            kind, n = inst[v]
            if not vol or not per or kind is None:
                row.append(None)
            elif kind == "B":
                if length < 2 or song.where(lc)[0] != "B":
                    row.append(None)
                else:
                    row.append((midi(song.frequency(per, lc, length)),
                                "synth", trig))
            else:
                row.append((midi(sa_log.PAULA_CLOCK / per)
                            - midi(sa_log.PAULA_CLOCK / 428) + 60,
                            "sample %d" % n, trig))
        out.append(row)
    return out


def ym_notes(sndh, frames):
    """-> per frame, per channel: None or (note, how), how in tone, buzz,
    noise; + per channel counts of noise, envelope, SID frames."""
    out = []
    use = [collections.Counter() for _ in range(3)]
    for _ in range(frames):
        sndh.frame()
        r, rates, touched = sndh.frames[-1]
        row = []
        for ch in range(3):
            v = r[8 + ch]
            tone_on = not r[7] >> ch & 1
            noise_on = not r[7] >> (ch + 3) & 1
            env = bool(v & 0x10)
            sid = any(8 + ch in regs for regs in touched.values())
            if not env and not v & 0x0F and not sid:
                row.append(None)
                continue
            use[ch]["sounding"] += 1
            use[ch]["noise"] += noise_on
            use[ch]["envelope"] += env
            use[ch]["sid"] += sid
            tp = r[2 * ch] | (r[2 * ch + 1] & 0x0F) << 8
            ep = r[11] | r[12] << 8
            if tone_on and tp:
                row.append((midi(YM_CLOCK / 16 / tp), "tone"))
                use[ch]["tone"] += 1
            elif env and ep and r[13] in (8, 10, 12, 14):
                div = 256 if r[13] in (8, 12) else 512
                row.append((midi(YM_CLOCK / div / ep), "buzz"))
                use[ch]["buzz"] += 1
            elif noise_on:
                row.append((None, "noise"))
            else:
                row.append(None)
        out.append(row)
    return out, use


def common(am, ym, lag, lo=0, hi=None):
    """Notes in common (same pitch class, synth voices only) at this lag."""
    hits = 0
    hi = len(ym) if hi is None else hi
    for f in range(max(lo, -lag, 0), min(hi, len(am) - lag)):
        a = {round(x[0]) % 12 for x in am[f + lag]
             if x and x[1] == "synth"}
        hits += sum(1 for y in ym[f] if y and y[0] is not None
                    and round(y[0]) % 12 in a)
    return hits


def best_lag(am, ym, lo=0, hi=None, span=60):
    return max(range(-span, span + 1), key=lambda g: common(am, ym, g, lo, hi))


def voices(am, ym, lag):
    """-> per YM channel [(Amiga voice, share, octave shift, frames)],
    and per sample Counter of semitone offsets.  Two passes: the first
    finds each sample's offset (per YM channel, the best one counts), the
    second counts synth and sample voices alike."""
    def frames():
        for f in range(len(ym)):
            if 0 <= f + lag < len(am):
                for c, y in enumerate(ym[f]):
                    if y and y[0] is not None:
                        for v, a in enumerate(am[f + lag]):
                            if a:
                                yield c, v, y[0] - a[0], a[1]

    per_channel = collections.defaultdict(collections.Counter)
    for c, v, d, inst in frames():
        if inst != "synth":
            per_channel[inst, c][round(d)] += 1
    tune, offset = collections.defaultdict(collections.Counter), {}
    for (inst, c), cnt in per_channel.items():
        top = cnt.most_common(1)[0]
        if inst not in offset or top[1] > tune[inst][offset[inst]]:
            offset[inst] = top[0]
            tune[inst] = cnt
    pair = [[collections.Counter() for _ in range(4)] for _ in range(3)]
    both = [[0] * 4 for _ in range(3)]
    for c, v, d, inst in frames():
        both[c][v] += 1
        d -= offset.get(inst, 0)
        if abs(d - round(d)) < 0.3 and round(d) % 12 == 0:
            pair[c][v][round(d) // 12] += 1
    out = []
    for c in range(3):
        rows = []
        for v in range(4):
            hit = sum(pair[c][v].values())
            if both[c][v]:
                octave = pair[c][v].most_common(1)[0][0] if hit else None
                rows.append((v, hit / both[c][v], octave, both[c][v]))
        rows.sort(key=lambda r: -r[1])
        out.append(rows)
    return out, tune


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--out", default="build/sa_to_ym")
    p.add_argument("--seconds", type=int, default=180)
    p.add_argument("--only", type=int, nargs="*")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    frms = ym_log.sndh_header(open(paths.value("AMBER_YMSNDH"), "rb").read())[
        "FRMS"]
    rep = []
    for t, y, title, active in pairs():
        if a.only and t not in a.only:
            continue
        frames = min(frms[y - 1], a.seconds * 50)
        am = amiga_notes(sa_log.Song(t), frames + 120)
        ym, use = ym_notes(ym_log.Sndh(y), frames)
        windows = [(lo, min(lo + 1000, frames)) for lo in range(0, frames, 1000)]
        lags = [best_lag(am, ym, lo, hi) for lo, hi in windows]
        lag = collections.Counter(lags).most_common(1)[0][0]
        vo, tune = voices(am, ym, lag)
        rep.append("Thalion %d <- YM %d%s  %s  (%d frames)" % (
            t, y, "" if active else " (part 2)", title, frames))
        rep.append("  lag per 20 s: %s" % " ".join("%+d" % g for g in lags))
        for c in range(3):
            u = use[c]
            n = u["sounding"] or 1
            best = ", ".join("voice %d %.0f%%%s" % (
                v, 100 * share,
                "" if octave is None else " oct %+d" % octave)
                for v, share, octave, cnt in vo[c][:2] if share >= 0.05)
            rep.append("  YM %s: sounds %3.0f%%  tone %3.0f%%  buzz %3.0f%%  "
                       "noise %3.0f%%  env %3.0f%%  SID %3.0f%%  <- %s" % (
                           "ABC"[c], 100 * u["sounding"] / frames,
                           100 * u["tone"] / n, 100 * u["buzz"] / n,
                           100 * u["noise"] / n, 100 * u["envelope"] / n,
                           100 * u["sid"] / n, best or "-"))
        for inst in sorted(tune):
            top = tune[inst].most_common(1)[0]
            total = sum(tune[inst].values())
            rep.append("  %-10s offset %+3d semitones (%.0f%% of %d)" % (
                inst, top[0], 100 * top[1] / total, total))
        rep.append("")
        print("\n".join(rep[-(6 + len(tune)):]), flush=True)
    open(os.path.join(a.out, "compare.txt"), "w").write("\n".join(rep))


if __name__ == "__main__":
    main()

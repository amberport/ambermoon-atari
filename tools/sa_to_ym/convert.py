#!/usr/bin/env python3
"""convert.py -- Thalion's Sonic Arranger songs to YM2149 frames, after Big Alec's recipe.

Thalion's player runs as in sa_log.py; every tick (50 Hz) gives four Paula
voices, and every YM frame takes three of them.  The recipe is what
compare.py found in Big Alec's versions:

- **Channel A, the bass:** the most recently struck voice below BASS_HZ
  plays as buzzer (envelope as wave, tone off): triangle, 2 MHz/512/EP.
  The envelope starts again with each new note.  The buzzer has no
  volume of its own, so it stops when the Amiga voice falls below
  BUZZ_MIN.  Other low voices are left out, as Big Alec does when two
  voices take turns with the bass.  No bass: A plays like B and C.
- **Channels B and C, melody and chords:** the two loudest of the other
  voices, a newly struck note first; a voice keeps its channel while it
  sounds.  Tone at the voice's pitch; the volume follows the Amiga's
  (0-64 to 0-15, 3 dB per step, 64 = VOL_TOP).
- **SID:** on B and C below SID_MAX_HZ, an MFP timer at twice the tone
  frequency switches the channel's volume on and off (Big Alec's sound;
  on the ST Timer A and D, since the game keeps Timer B for the raster).
- **Left out:** the fourth voice when four sound, and drums: a sample's
  pitch is taken as if period 428 were C-4, which is right only by chance.

A frame is 16 register values (13 = 0xFF: the envelope is not restarted)
and {channel: SID rate in Hz}.  ``to_log`` turns frames into the write log
ym_synth.py renders, with the SID switches at the timer's times.

For each song it writes into --out (default build/sa_to_ym):

    NN_ours.wav        the conversion, as loud as the Amiga (or as loud
                       as it goes without clipping)
    NN_amiga_ours.wav  Amiga left, conversion right

The Amiga side is NN_YY_amiga.wav from pairs.py when there is one, else
UADE writes NN_amiga.wav.  Length: Big Alec's piece when there is one,
else --seconds.  The page index.html gets a row per song (pairs.page).

Usage:  VENV/bin/python tools/sa_to_ym/convert.py SONG... [--out DIR]
            [--seconds N] [--no-sid]
"""
import argparse
import collections
import glob
import math
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.dirname(HERE)]
import paths                         # noqa: E402
import pairs                         # noqa: E402
import sa_log                        # noqa: E402
import ym_log                        # noqa: E402
import ym_synth                      # noqa: E402

YM_CLOCK = 2_000_000
FRAME = YM_CLOCK // 50
BASS_HZ = 200
BUZZ_MIN = 16
VOL_TOP = 12
SID_MAX_HZ = 700
SHAPE = 0x0E                         # triangle, repeating
RATE = 44100

Note = collections.namedtuple("Note", "voice hz vol since kind")


def amiga(song, ticks):
    """-> per tick the sounding voices as [Note].  since: ticks since the
    voice was struck; kind: "synth" or "sample N"."""
    out = []
    inst = [(None, 0)] * 4
    since = [0] * 4
    for _ in range(ticks):
        row = []
        for v, (per, vol, lc, length, trig) in enumerate(song.tick()):
            if trig:
                inst[v] = song.where(lc)
                since[v] = 0
            else:
                since[v] += 1
            kind, n = inst[v]
            if not vol or not per or kind is None:
                continue
            if kind == "B":
                if length < 2 or song.where(lc)[0] != "B":
                    continue
                row.append(Note(v, song.frequency(per, lc, length), vol,
                                since[v], "synth"))
            else:
                row.append(Note(v, 261.63 * 428 / per, vol, since[v],
                                "sample %d" % n))
        out.append(row)
    return out


def ym_volume(vol):
    """Amiga 1-64 -> YM 0-15, 3 dB per step."""
    return max(0, min(15, round(VOL_TOP + 20 * math.log10(vol / 64) / 3)))


def allocate(ticks):
    """-> per tick [Note or None] * 3 for A, B, C (see the module text)."""
    out = []
    held = [None] * 3                       # voice per channel
    for notes in ticks:
        by_voice = {n.voice: n for n in notes}
        bass = [n for n in notes if n.hz < BASS_HZ]
        chan = [None] * 3
        if bass:
            chan[0] = min(bass, key=lambda n: (n.since, n.hz))
            rest = [n for n in notes if n.hz >= BASS_HZ]
            free = [1, 2]
        else:
            rest = list(notes)
            free = [0, 1, 2]

        def score(n):
            return ym_volume(n.vol) + (4 if n.since < 2 else 0)
        rest.sort(key=score, reverse=True)
        rest = rest[:len(free)]
        for c in free:                      # a voice keeps its channel
            if held[c] in by_voice and by_voice[held[c]] in rest:
                chan[c] = by_voice[held[c]]
                rest.remove(chan[c])
        for c in free:
            if chan[c] is None and rest:
                chan[c] = rest.pop(0)
        held = [n.voice if n else None for n in chan]
        out.append(chan)
    return out


def timer_hz(hz):
    """The MFP delay-mode rate nearest to hz."""
    best = None
    for pre in ym_log.PRESCALE[1:]:
        data = max(1, min(256, round(ym_log.MFP_CLOCK / (pre * hz))))
        rate = ym_log.MFP_CLOCK / (pre * data)
        if best is None or abs(rate - hz) < abs(best - hz):
            best = rate
    return best


def frames(alloc, sid=True):
    """-> [(16 registers, {channel: SID Hz})] per tick."""
    out = []
    last = [None] * 3                       # (voice, since) of the buzzer
    for chan in alloc:
        r = [0] * 16
        r[7] = 0x3F
        r[13] = 0xFF
        rates = {}
        for c, n in enumerate(chan):
            if n is None:
                continue
            if c == 0 and n.hz < BASS_HZ:
                if n.vol < BUZZ_MIN:
                    continue
                ep = max(1, min(0xFFFF, round(YM_CLOCK / 512 / n.hz)))
                r[11], r[12] = ep & 0xFF, ep >> 8
                r[8] = 0x10
                if last[0] != n.voice or n.since == 0:
                    r[13] = SHAPE
                last[0] = n.voice
                continue
            tp = max(1, min(0xFFF, round(YM_CLOCK / 16 / n.hz)))
            r[2 * c], r[2 * c + 1] = tp & 0xFF, tp >> 8
            r[7] &= ~(1 << c)
            r[8 + c] = ym_volume(n.vol)
            if sid and c and n.hz <= SID_MAX_HZ and r[8 + c]:
                rates[c] = timer_hz(2 * YM_CLOCK / 16 / tp)
        if chan[0] is None or chan[0].hz >= BASS_HZ:
            last[0] = None
        out.append((r, rates))
    return out


def to_log(frames):
    """-> (write log for ym_synth.render, length in YM clocks).  A SID
    timer keeps its phase while its channel stays SID."""
    log, prev = [], [None] * 16
    phase = {}                              # channel -> YM clocks to next switch
    for f, (r, rates) in enumerate(frames):
        t0 = f * FRAME
        for reg, v in enumerate(r):
            if reg == 13:
                if v != 0xFF:
                    log.append((t0, 13, v))
            elif v != prev[reg]:
                log.append((t0, reg, v))
                prev[reg] = v
        for c in list(phase):
            if c not in rates:
                del phase[c]
        for c, hz in rates.items():
            step = YM_CLOCK / hz
            t = phase.get(c, step)
            on = True
            while t < FRAME:
                on = not on
                log.append((t0 + int(t), 8 + c, r[8 + c] if on else 0))
                t += step
            phase[c] = t - FRAME
            prev[8 + c] = None
    log.sort(key=lambda w: w[0])
    return log, len(frames) * FRAME


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("songs", type=int, nargs="+")
    p.add_argument("--out", default="build/sa_to_ym")
    p.add_argument("--seconds", type=int, default=120)
    p.add_argument("--no-sid", action="store_true")
    a = p.parse_args()
    sa_dir = os.path.join(a.out, "sa")
    if not glob.glob(os.path.join(sa_dir, "*.sa")):
        os.makedirs(sa_dir, exist_ok=True)
        subprocess.run([sys.executable, "-I",
                        os.path.join(pairs.TOOLS, "sa_auszug.py"),
                        "--out", sa_dir], check=True, stdout=subprocess.DEVNULL)
    frms = ym_log.sndh_header(open(paths.value("AMBER_YMSNDH"), "rb").read())[
        "FRMS"]
    big_alec = {t: y for t, y, _, active in pairs.pairs() if active}
    for t in a.songs:
        if t in big_alec:
            ticks = min(frms[big_alec[t] - 1], 180 * 50)
            amiga_wav = os.path.join(a.out, "%02d_%02d_amiga.wav" % (
                t, big_alec[t]))
        else:
            ticks = a.seconds * 50
            amiga_wav = os.path.join(a.out, "%02d_amiga.wav" % t)
        secs = ticks / 50
        if not os.path.exists(amiga_wav):
            sa = glob.glob(os.path.join(sa_dir, "%02d_*.sa" % t))[0]
            subprocess.run(["uade123", "-1", "-t", str(int(secs + 1)),
                            "-f", amiga_wav, sa], check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        notes = amiga(sa_log.Song(t), ticks)
        alloc = allocate(notes)
        fr = frames(alloc, not a.no_sid)
        log, clocks = to_log(fr)
        pcm = ym_synth.render(log, clocks, RATE)
        n = int(secs * RATE)
        left = pairs.read_wav(amiga_wav)[:n]
        right = list(struct.unpack("<%dh" % (len(pcm) // 2), pcm))
        m = sum(right) / len(right)
        peak = max(abs(v - m) for v in right) or 1
        right = pairs.louder(right, min(pairs.rms(left) / pairs.rms(right),
                                        32000 / peak))
        ym_synth.save_wav(os.path.join(a.out, "%02d_ours.wav" % t),
                          struct.pack("<%dh" % len(right), *right), RATE)
        pairs.both(left, right, os.path.join(a.out, "%02d_amiga_ours.wav" % t))
        kinds = collections.Counter(n.kind.split()[0] for row in notes
                                    for n in row)
        four = sum(1 for row in notes if len(row) > 3)
        buzz = sum(1 for r, _ in fr if r[8] == 0x10)
        sid = sum(1 for _, s in fr if s)
        print("%2d  %.0f s  voices: %s  four at once %d%%  buzzer %d%%  "
              "SID %d%%" % (t, secs, dict(kinds), 100 * four // ticks,
                            100 * buzz // ticks, 100 * sid // ticks),
              flush=True)
    pairs.page(a.out)
    print("page:", os.path.abspath(os.path.join(a.out, "index.html")))


if __name__ == "__main__":
    main()

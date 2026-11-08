#!/usr/bin/env python3
"""pairs.py -- Thalion's songs next to Big Alec's YM versions, to listen and compare.

For every pair of tools/musik_ym.inf (the active lines and the commented
second parts) it writes into --out (default build/sa_to_ym, never into the
repository: Thalion's and Big Alec's music):

    NN_YY_amiga.wav  Thalion's song NN, played by UADE from build/sa_to_ym/sa
                     (tools/sa_auszug.py writes the .sa files)
    NN_YY_ym.wav     Big Alec's piece YY, from the SNDH (ym_log.py, ym_synth.py)
    NN_YY_both.wav   Amiga left, YM right, at the same time
    index.html       a page with the players per song (page), also for
                     convert.py's files

Both last as long as the YM piece (FRMS of the SNDH), at most --seconds;
the YM is scaled to the loudness (RMS) of the Amiga.

Usage:  VENV/bin/python tools/sa_to_ym/pairs.py [--out DIR] [--seconds N]
            [--only THALION ...]
        VENV: a Python with unicorn (m68k.py)
"""
import argparse
import glob
import html
import os
import re
import struct
import subprocess
import sys
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.dirname(HERE)
sys.path[:0] = [HERE, TOOLS]
import paths                         # noqa: E402
import ym_log                        # noqa: E402
import ym_synth                      # noqa: E402

RATE = 44100


def pairs():
    """-> [(thalion, ym, title, active)] from tools/musik_ym.inf."""
    out = []
    for line in open(os.path.join(TOOLS, "musik_ym.inf"), encoding="latin-1"):
        m = re.match(r"^(;?)\s*(\d+)\s+(\d+)\s*;\s*(.*?)\s{2,}", line)
        if m:
            out.append((int(m.group(2)), int(m.group(3)), m.group(4),
                        not m.group(1)))
    return out


def read_wav(path):
    """-> mono samples (list of int), the channels averaged."""
    with wave.open(path) as w:
        ch, n = w.getnchannels(), w.getnframes()
        d = struct.unpack("<%dh" % (n * ch), w.readframes(n))
    if ch == 1:
        return list(d)
    return [(d[i] + d[i + 1]) // 2 for i in range(0, len(d), 2)]


def rms(x):
    m = sum(x) / len(x)
    return (sum((v - m) ** 2 for v in x) / len(x)) ** 0.5 or 1.0


def louder(x, factor):
    """Scale and remove the DC offset, clipped to 16 bits."""
    m = sum(x) / len(x)
    return [max(-32768, min(32767, int((v - m) * factor))) for v in x]


def both(left, right, path):
    n = max(len(left), len(right))
    left = left + [0] * (n - len(left))
    right = right + [0] * (n - len(right))
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<hh", a, b)
                               for a, b in zip(left, right)))


def titles(out):
    """-> {Thalion's number: title} from the .sa files tools/sa_auszug.py wrote."""
    t = {}
    for f in glob.glob(os.path.join(out, "sa", "*.sa")):
        n, _, name = os.path.basename(f)[:-3].partition("_")
        t[int(n)] = name.replace("_", " ")
    return t


def page(out):
    """index.html: a row per song with the files that are there (pairs.py
    writes NN_YY_*, convert.py NN_ours and NN_amiga_ours)."""
    names = titles(out)
    rows = [(t, y, active) for t, y, _, active in pairs()]
    paired = {t for t, y, active in rows}
    rows += [(int(os.path.basename(f)[:2]), None, True)
             for f in sorted(glob.glob(os.path.join(out, "[0-9][0-9]_ours.wav")))
             if int(os.path.basename(f)[:2]) not in paired]
    rows.sort(key=lambda r: (r[0], not r[2]))
    h = ['<!doctype html><meta charset="utf-8"><title>SA and YM</title>',
         "<style>body{font:15px sans-serif;margin:16px;background:#fff;"
         "color:#111}td,th{padding:4px 8px;text-align:left;"
         "vertical-align:middle}audio{width:220px}"
         "@media (prefers-color-scheme:dark){body{background:#181818;"
         "color:#eee}}</style>",
         "<h1>Thalion's songs, Big Alec's YM versions, our conversion</h1>",
         "<p>Amiga: UADE from Music.amb. Big Alec: his SNDH in a 68000 "
         "emulation. Ours: tools/sa_to_ym/convert.py. Both YM sides play "
         "on our YM2149 model. The pairs: Amiga left, YM right.</p>",
         "<table><tr><th>Thalion</th><th>Title</th><th>Amiga</th>"
         "<th>Big Alec</th><th>Ours</th><th>Amiga | Big Alec</th>"
         "<th>Amiga | Ours</th></tr>"]
    for t, y, active in rows:
        stem = "%02d_%02d" % (t, y) if y else "%02d" % t
        files = [stem + "_amiga.wav", stem + "_ym.wav", "%02d_ours.wav" % t,
                 stem + "_both.wav", "%02d_amiga_ours.wav" % t]
        if not active:          # a second part: ours belongs to the first
            files[2] = files[4] = None
        h.append("<tr><td>%d%s</td><td>%s</td>" % (
            t, "" if y is None else " / YM %d%s" % (
                y, "" if active else " (part 2)"),
            html.escape(names.get(t, ""))))
        for f in files:
            if f and os.path.exists(os.path.join(out, f)):
                h.append('<td><audio controls preload="none" src="%s">'
                         "</audio></td>" % f)
            else:
                h.append("<td></td>")
        h.append("</tr>")
    h.append("</table>")
    open(os.path.join(out, "index.html"), "w").write("\n".join(h))


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--out", default="build/sa_to_ym")
    p.add_argument("--seconds", type=int, default=180)
    p.add_argument("--only", type=int, nargs="*")
    a = p.parse_args()
    sa_dir = os.path.join(a.out, "sa")
    os.makedirs(sa_dir, exist_ok=True)
    subprocess.run([sys.executable, "-I", os.path.join(TOOLS, "sa_auszug.py"),
                    "--out", sa_dir], check=True, stdout=subprocess.DEVNULL)
    frms = ym_log.sndh_header(open(paths.value("AMBER_YMSNDH"), "rb").read())[
        "FRMS"]
    for t, y, title, active in pairs():
        if a.only and t not in a.only:
            continue
        stem = "%02d_%02d" % (t, y)
        frames = min(frms[y - 1], a.seconds * 50)
        secs = frames / 50
        print("%2d <- YM %2d  %s  %.0f s" % (t, y, title, secs), flush=True)
        sa = glob.glob(os.path.join(sa_dir, "%02d_*.sa" % t))[0]
        amiga = os.path.join(a.out, stem + "_amiga.wav")
        subprocess.run(["uade123", "-1", "-t", str(int(secs + 1)),
                        "-f", amiga, sa], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        s = ym_log.Sndh(y)
        for _ in range(frames):
            s.frame()
        pcm = ym_synth.render(s.log, s.now, RATE)
        n = int(secs * RATE)
        left = read_wav(amiga)[:n]
        right = list(struct.unpack("<%dh" % (len(pcm) // 2), pcm))
        right = louder(right, rms(left) / rms(right))   # as loud as the Amiga
        ym_synth.save_wav(os.path.join(a.out, stem + "_ym.wav"),
                          struct.pack("<%dh" % len(right), *right), RATE)
        both(left, right, os.path.join(a.out, stem + "_both.wav"))
    page(a.out)
    print("page:", os.path.abspath(os.path.join(a.out, "index.html")))


if __name__ == "__main__":
    main()

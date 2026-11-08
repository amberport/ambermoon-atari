"""sa_log.py -- what Thalion's Sonic Arranger player writes to Paula, tick by tick.

The player is the one in AM2_CPU (hunk 0 $2AA0E, docs/13 section 4), run on
the host in m68k.Machine with all hunks loaded and relocated.  The way is
Thalion's Set_music: +0 with a0 = the unpacked entry of Music.amb, +12 with
d0 = the part, then +24 once per tick (the VBL, 50 Hz).

A tick's record per channel: period, volume, sample start (LC), length in
words (LEN), and whether DMACON restarted the channel in that tick.  LC is
an address in the host machine; ``Song.where`` names it (a sample of the
song, or the player's buffer for a synth sound).

What a channel plays is what LC and LEN said in the tick DMACON restarted
it: the tick after, the player already sets them to the loop, which Paula
takes only at the end of the sample; a sample without a loop goes on to
the player's silent buffer (length 1).
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.dirname(HERE)]
import paths                          # noqa: E402
from am2cpu_read import load_hunks    # noqa: E402
from ambtool import unpack            # noqa: E402
from m68k import Machine, bytes_of    # noqa: E402

PLAYER = 0x2AA0E                      # hunk 0
HUNK_BASE = 0x100000
SONG_BASE = 0x400000
CUSTOM, CIA = 0xDFF000, 0xBF0000
DMACON = 0x96
PAULA_CLOCK = 3546895                 # PAL


class Song:
    def __init__(self, number, part=0, amberfiles=None):
        amberfiles = amberfiles or paths.amberfiles()
        self.m = m = Machine()
        self.regs = bytearray(0x200)
        self.trig = [False] * 4
        self.off = [False] * 4
        self.random = 0x1234
        m.io(CUSTOM, 0x1000, self._read, self._write)
        m.uc.mem_map(CIA, 0x10000)

        hunks = load_hunks(os.path.join(amberfiles, "AM2_CPU"))
        base, o = [], HUNK_BASE
        for h in hunks:
            base.append(o)
            o = (o + h["size"] + 15) & ~15
        if o > SONG_BASE:
            sys.exit("AM2_CPU does not fit below $%X" % SONG_BASE)
        for h, b in zip(hunks, base):
            d = bytearray(h["data"].ljust(h["size"], b"\0"))
            for off, target in h["reloc"].items():
                v = struct.unpack_from(">I", d, off)[0] + base[target]
                struct.pack_into(">I", d, off, v)
            m.write(b, d)
        self.player = base[0] + PLAYER

        _, entries = unpack(open(os.path.join(amberfiles, "Music.amb"),
                                 "rb").read())
        self.data = entries[number - 1]
        m.write(SONG_BASE, self.data)
        self._samples()
        m.call(self.player + 0, a={0: SONG_BASE})
        m.call(self.player + 12, d={0: part})
        self.trig = [False] * 4

    def _samples(self):
        """Where each sample of the song lies: [(start, end)] as addresses."""
        o = struct.unpack(">8I", self.data[:32])[7]
        n = struct.unpack(">I", self.data[o:o + 4])[0]
        sizes = struct.unpack(">%dI" % n, self.data[o + 4:o + 4 + 4 * n])
        a = SONG_BASE + o + 4 + 4 * n
        self.samples = []
        for s in sizes:
            self.samples.append((a, a + s))
            a += s

    def where(self, lc):
        """-> ("S", n) sample n of the song, ("B", addr) elsewhere (synth
        buffer), (None, 0) when LC holds the junk of $2B38E."""
        for n, (a, e) in enumerate(self.samples):
            if a <= lc < e:
                return "S", n
        if HUNK_BASE <= lc < SONG_BASE:
            return "B", lc
        return None, 0

    def _read(self, off, size):
        if off in (4, 6):                 # VPOSR/VHPOSR: noise source
            self.random = (self.random * 1103515245 + 12345) & 0x7FFFFFFF
            return self.random >> 8
        v = 0
        for i in range(size):
            v = v << 8 | (self.regs[off + i] if off + i < 0x200 else 0)
        return v

    def _write(self, off, size, value):
        for o, b in bytes_of(off, size, value):
            if o < 0x200:
                self.regs[o] = b
        if off == DMACON and size >= 2:
            w = value >> 8 * (size - 2) & 0xFFFF
            for ch in range(4):
                if w & 1 << ch:
                    if w & 0x8000:
                        self.trig[ch] = True
                    else:
                        self.off[ch] = True

    def channel(self, ch):
        r = 0xA0 + 16 * ch
        lc, length, per, vol = struct.unpack_from(">IHHH", self.regs, r)
        return lc, length, per, vol

    def tick(self):
        """One tick -> [(period, volume, lc, len, restarted)] per channel."""
        self.trig = [False] * 4
        self.off = [False] * 4
        self.m.call(self.player + 24)
        out = []
        for ch in range(4):
            lc, length, per, vol = self.channel(ch)
            out.append((per, min(vol, 64), lc, length, self.trig[ch]))
        return out

    def wave(self, lc, length):
        return self.m.read(lc, 2 * length)

    def frequency(self, per, lc, length):
        """Hz of a looping synth buffer of length words played at period
        per.  A buffer may hold several cycles of its wave (Compact disc:
        eight in 64 bytes), so the shortest period that repeats counts."""
        if not per or not length:
            return 0.0
        return PAULA_CLOCK * cycles(self.wave(lc, length)) / (per * 2 * length)


def cycles(wave):
    """How many times the shortest repeating part fits into the buffer
    (within 1/16 of the wave's range)."""
    n = len(wave)
    v = [b - 256 if b > 127 else b for b in wave]
    tolerance = max(2, (max(v) - min(v)) // 16)
    for p in range(1, n):
        if n % p == 0 and all(abs(v[i] - v[(i + p) % n]) <= tolerance
                              for i in range(n)):
            return n // p
    return 1


if __name__ == "__main__":
    s = Song(int(sys.argv[1]))
    for t in range(int(sys.argv[2]) if len(sys.argv) > 2 else 20):
        row = s.tick()
        print("%4d " % t + " | ".join(
            "%s%4d %2d %s%-5s %4d" % ("*" if c[4] else " ", c[0], c[1],
                                       *map(str, s.where(c[2])), c[3])
            for c in row))

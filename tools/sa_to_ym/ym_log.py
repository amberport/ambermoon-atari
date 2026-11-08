"""ym_log.py -- what an SNDH player writes to the YM2149, with the time.

Big Alec's ambermon.snd (AMBER_YMSNDH) runs in m68k.Machine: SNDH +0 init
(d0 = piece 1-18), +8 play once per frame (the header says TC50), and the
MFP timers its init programs (FLAG ~aby: Timer A and B).  The timers are
modelled only as far as a player needs them: delay mode with the MFP
prescalers, event count on Timer B as the 15625 Hz line rate, an interrupt
when IER and IMR allow it.  A handler runs whole at the time its timer
fires; the play routine at the start of its frame.

Every YM write is logged as (time in YM clocks at 2 MHz, register, value).
The 68000 runs without 24-bit addressing, so the I/O pages are mapped twice:
$FF8800 and $FFFF8800 (short addressing), $FFFA00 and $FFFFFA00.
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path[:0] = [HERE, os.path.dirname(HERE)]
import paths                          # noqa: E402
from m68k import Machine, bytes_of    # noqa: E402

YM_CLOCK = 2_000_000
MFP_CLOCK = 2_457_600
FRAME = YM_CLOCK // 50
LINE_RATE = 15625
LOAD = 0x10000
PRESCALE = [0, 4, 10, 16, 50, 64, 100, 200]
# timer: (control register, its bits, data register, vector, IER/IMR
# register, bit)
TIMERS = {
    "A": (0x19, 0, 0x1F, 0x134, 0x07, 5),
    "B": (0x1B, 0, 0x21, 0x120, 0x07, 0),
    "C": (0x1D, 4, 0x23, 0x114, 0x09, 5),
    "D": (0x1D, 0, 0x25, 0x110, 0x09, 4),
}


def sndh_header(data):
    """-> dict of the SNDH tags we use (TITL, ##, TC/TA, FRMS)."""
    tags = {}
    o = data.index(b"SNDH") + 4
    while o < 0x200 and data[o:o + 4] != b"HDNS":
        if data[o:o + 2] == b"##":
            tags["##"] = int(data[o + 2:o + 4])
            o += 4
        elif data[o:o + 4] == b"FRMS":
            n = tags.get("##", 1)
            tags["FRMS"] = struct.unpack(">%dI" % n, data[o + 4:o + 4 + 4 * n])
            o += 4 + 4 * n
        elif data[o:o + 2] in (b"TA", b"TB", b"TC", b"TD"):
            e = data.index(b"\0", o)
            tags["timer"] = data[o:e].decode()
            o = e + 1
        else:
            e = data.index(b"\0", o)
            tags[data[o:o + 4].decode("latin-1")] = data[o + 4:e].decode(
                "latin-1")
            o = e + 1
        while o < len(data) and data[o] == 0:
            o += 1
    return tags


class Sndh:
    def __init__(self, piece, path=None):
        path = path or paths.value("AMBER_YMSNDH")
        self.data = open(path, "rb").read()
        self.tags = sndh_header(self.data)
        self.m = m = Machine()
        self.select = 0
        self.ym = bytearray(16)
        self.mfp = bytearray(0x40)
        self.count = {}               # timer -> clocks left (MFP clocks)
        self.now = 0                  # YM clocks
        self.log = []
        self.frames = []              # per frame: see frame()
        self.source = None            # timer whose handler runs, or None
        self.touched = {}
        for base in (0xFF8000, 0xFFFF8000):
            m.io(base, 0x1000, self._st_read, self._st_write)
        for base in (0xFFF000, 0xFFFFF000):
            m.io(base, 0x1000, self._mfp_read, self._mfp_write)
        m.write(LOAD, self.data)
        m.call(LOAD + 0, d={0: piece})

    # ---- YM at $FF8800 (select) / $FF8802 (data), mirrored every 4 bytes
    def _st_read(self, off, size):
        v = 0
        for o in range(off, off + size):
            b = 0xFF
            if 0x800 <= o < 0x900 and o & 3 == 0:
                b = self.ym[self.select] if self.select < 16 else 0xFF
            v = v << 8 | b
        return v

    def _st_write(self, off, size, value):
        for o, b in bytes_of(off, size, value):
            if not 0x800 <= o < 0x900 or o & 1:
                continue
            if o & 2 == 0:
                self.select = b & 0x0F if b < 16 else 16
            elif self.select < 16:
                self.ym[self.select] = b
                self.log.append((self.now, self.select, b))
                if self.source:
                    self.touched.setdefault(self.source, set()).add(
                        self.select)

    # ---- MFP at $FFFA00: odd bytes only
    def _mfp_read(self, off, size):
        v = 0
        for o in range(off, off + size):
            r = o - 0xA00
            v = v << 8 | (self.mfp[r] if 0 <= r < 0x40 else 0xFF)
        return v

    def _mfp_write(self, off, size, value):
        for o, b in bytes_of(off, size, value):
            r = o - 0xA00
            if 0 <= r < 0x40:
                self.mfp[r] = b

    def _mode(self, t):
        cr, shift = TIMERS[t][:2]
        return self.mfp[cr] >> shift & (0x0F if t in "AB" else 0x07)

    def _period(self, t):
        """MFP clocks between two interrupts of timer t, 0 when stopped."""
        cr, shift, dr = TIMERS[t][:3]
        mode = self._mode(t)
        data = self.mfp[dr] or 256
        if t in "AB" and mode == 8:
            return MFP_CLOCK * data // LINE_RATE if t == "B" else 0
        if 1 <= mode & 7 <= 7 and not mode & 8:
            return PRESCALE[mode & 7] * data
        return 0

    def _enabled(self, t):
        reg, bit = TIMERS[t][4:6]
        return self.mfp[reg] >> bit & self.mfp[reg + 0x0C] >> bit & 1

    def frame(self):
        """Play one frame: the play routine, then the timers until the
        next frame.  Appends to self.frames (registers after the play
        routine, {timer: Hz} of the running timers with an interrupt,
        {timer: registers its handler wrote in this frame})."""
        start = self.now
        self.m.call(LOAD + 8)
        self.touched = {}
        rates = {t: MFP_CLOCK / self._period(t) for t in "ABD"
                 if self._period(t) and self._enabled(t)}
        self.frames.append((bytes(self.ym), rates, self.touched))
        end = start + FRAME
        while True:
            # Next timer event, in MFP clocks from now.
            nxt, who = None, None
            for t in "ABD":
                p = self._period(t)
                if not p:
                    self.count.pop(t, None)
                    continue
                c = self.count.setdefault(t, p)
                if nxt is None or c < nxt:
                    nxt, who = c, t
            if nxt is None:
                break
            at = self.now + nxt * YM_CLOCK // MFP_CLOCK
            if at >= end:
                step = (end - self.now) * MFP_CLOCK // YM_CLOCK
                for t in self.count:
                    self.count[t] -= step
                break
            for t in self.count:
                self.count[t] -= nxt
            self.now = at
            self.count[who] = self._period(who)
            if self._enabled(who):
                self.source = who
                self.m.call(self.m.long(TIMERS[who][3]), frame=True)
                self.source = None
        self.now = end


if __name__ == "__main__":
    s = Sndh(int(sys.argv[1]))
    print(s.tags)
    for f in range(int(sys.argv[2]) if len(sys.argv) > 2 else 5):
        n = len(s.log)
        s.frame()
        print(f, " ".join("%d:%02X" % (r, v) for _, r, v in s.log[n:]))

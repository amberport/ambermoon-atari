#!/usr/bin/env python3
"""Convert a DMS disk image (Disk Masher) to an ADF.

    python3 tools/dms_to_adf.py IN.dms OUT.adf

Reads the methods NONE, SIMPLE (run-length) and HEAVY 1 and 2 (LZ with
Huffman codes, then run-length if the track says so); Thalion's 1.07 uses
only HEAVY 2.  QUICK, MEDIUM, DEEP and encrypted images stop with
Unsupported, and tools/game_files.py then asks xdms.  Every header and track
is checked against its CRC, every unpacked track against its checksum.
Written from the DMS track layout; no code of xdms.

Proved: the nine disks of Thalion's English 1.07 give the same ADF as
xdms 1.3.2, byte for byte (2026-11-04).
"""
import bisect, struct, sys

TRACK = 11 * 2 * 512          # one cylinder, both sides
TRACKS = 80
LONG = 1023                   # table entry: the code is longer than 16 bits


class Error(Exception):
    pass


class Unsupported(Error):
    pass


def _crc_table():
    t = []
    for n in range(256):
        c = n
        for _ in range(8):
            c = (c >> 1) ^ 0xA001 if c & 1 else c >> 1
        t.append(c)
    return t

CRC = _crc_table()

def crc16(data):
    """CRC-16 as DMS uses it (polynomial $A001 reflected, start 0)."""
    c = 0
    for b in data:
        c = CRC[(c ^ b) & 0xFF] ^ (c >> 8)
    return c


def unpack_rle(src, size):
    """$90 n b: n times b; $90 $FF b hi lo: hi*256+lo times b; $90 0: $90."""
    out = bytearray()
    i = 0
    while len(out) < size:
        k = src.find(0x90, i)
        if k < 0 or k >= len(src) - 1:
            out += src[i:]
            break
        out += src[i:k]
        n = src[k + 1]
        if n == 0:
            out.append(0x90)
            i = k + 2
        elif n == 0xFF:
            out += bytes([src[k + 2]]) * ((src[k + 3] << 8) | src[k + 4])
            i = k + 5
        else:
            out += bytes([src[k + 2]]) * n
            i = k + 3
    if len(out) != size:
        raise Error("run-length data gives %d bytes, not %d" % (len(out), size))
    return out


class Heavy:
    """The HEAVY decoder.  Code tables, the last distance and the window
    carry over from track to track until a track asks for a reset."""

    def __init__(self):
        self.reset()
        self.ctab = self.ptab = None
        self.clong = []
        self.last = 0

    def reset(self):
        # the window as one buffer: 8 KB of zeros, then everything unpacked
        self.hist = bytearray(8192)

    @staticmethod
    def table(lengths):
        """-> (tab, long): tab is a list of 65536, entry = symbol << 5 | code
        length, for the next 16 bits of input.  Codes are canonical: shorter
        first, then by symbol.  A code longer than 16 bits has the entry
        LONG << 5 in its 16-bit slot; long is then a sorted list of (first
        32-bit value, length, symbol) for those."""
        tab = [0] * 65536
        long = []
        pos = 0                                   # 32-bit space
        for n in range(1, 32):
            for sym, L in enumerate(lengths):
                if L != n:
                    continue
                if n <= 16:
                    step = 1 << (16 - n)
                    tab[pos >> 16:(pos >> 16) + step] = [sym << 5 | n] * step
                else:
                    tab[pos >> 16] = LONG << 5
                    long.append((pos, n, sym))
                pos += 1 << (32 - n)
        if pos != 1 << 32:
            raise Error("the Huffman code lengths do not make a full code")
        return tab, long

    def unpack(self, src, size, heavy2, new_tables):
        np = 15 if heavy2 else 14
        d = bytes(src) + bytes(8)
        pos = 0                                   # in bits, highest bit first

        def bits(n):
            nonlocal pos
            q = pos >> 3
            v = ((d[q] << 16 | d[q + 1] << 8 | d[q + 2]) >> (24 - n - (pos & 7))) & ((1 << n) - 1)
            pos += n
            return v

        def lengths(count_bits, len_bits, total):
            n = bits(count_bits)
            if n == 0:
                return [bits(count_bits) << 5] * 65536, []   # one symbol, no bits
            if n > total:
                raise Error("%d Huffman codes, at most %d" % (n, total))
            return self.table([bits(len_bits) for _ in range(n)] + [0] * (total - n))

        if new_tables:
            self.ctab, self.clong = lengths(9, 5, 510)
            self.ptab, _ = lengths(5, 4, np)      # 4-bit lengths: never long
        elif self.ctab is None:
            raise Error("a track without Huffman tables comes first")
        ctab, ptab, hist, last = self.ctab, self.ptab, self.hist, self.last
        starts = [f for f, _, _ in self.clong]
        end = len(hist) + size
        while len(hist) < end:
            q = pos >> 3
            e = ctab[((d[q] << 16 | d[q + 1] << 8 | d[q + 2]) >> (8 - (pos & 7))) & 0xFFFF]
            pos += e & 31
            c = e >> 5
            if c < 256:
                hist.append(c)
                continue
            if c == LONG:
                q = pos >> 3
                v = (int.from_bytes(d[q:q + 5], "big") >> (8 - (pos & 7))) & 0xFFFFFFFF
                _, n, c = self.clong[bisect.bisect_right(starts, v) - 1]
                pos += n
                if c < 256:
                    hist.append(c)
                    continue
            q = pos >> 3
            e = ptab[((d[q] << 16 | d[q + 1] << 8 | d[q + 2]) >> (8 - (pos & 7))) & 0xFFFF]
            pos += e & 31
            j = e >> 5
            if j != np - 1:                       # np-1: the last distance again
                if j > 1:
                    j = bits(j - 1) | (1 << (j - 1))
                last = j
            n = c - 253
            s = len(hist) - last - 1
            if s < 0:
                raise Error("a distance before the start of the window")
            if last + 1 >= n:
                hist += hist[s:s + n]
            else:
                piece = hist[s:]
                hist += (piece * (n // len(piece) + 1))[:n]
        self.last = last
        if pos > len(src) * 8:
            raise Error("the packed track ends too early")
        return hist[end - size:end]


def convert(src, dst):
    """Write the ADF; -> number of tracks."""
    d = open(src, "rb").read()
    if d[:4] != b"DMS!" or len(d) < 56:
        raise Error("%s: not a DMS image" % src)
    if crc16(d[4:54]) != struct.unpack(">H", d[54:56])[0]:
        raise Error("%s: the header's CRC is wrong" % src)
    if struct.unpack(">H", d[10:12])[0] & 2:
        raise Unsupported("%s is encrypted" % src)
    adf = bytearray(TRACK * TRACKS)
    seen = set()
    heavy = Heavy()
    p = 56
    while p + 20 <= len(d):
        h = d[p:p + 20]
        if h[:2] != b"TR":
            break
        if crc16(h[:18]) != struct.unpack(">H", h[18:20])[0]:
            raise Error("%s: track header at %d: CRC wrong" % (src, p))
        number, _, pklen1, pklen2, unpklen, flags, mode, usum, dcrc = \
            struct.unpack(">HHHHHBBHH", h[2:18])
        data = d[p + 20:p + 20 + pklen1]
        p += 20 + pklen1
        if len(data) != pklen1 or crc16(data) != dcrc:
            raise Error("%s: track %d: data CRC wrong" % (src, number))
        if number >= TRACKS or unpklen <= 2048:
            continue                              # banner, FILE_ID.DIZ
        if mode == 0:
            out = data[:unpklen]
        elif mode == 1:
            out = unpack_rle(data, unpklen)
        elif mode in (5, 6):
            out = heavy.unpack(data, pklen2, mode == 6, flags & 2)
            if flags & 4:
                out = unpack_rle(out, unpklen)
        else:
            raise Unsupported("%s: track %d: method %d is not read here" % (src, number, mode))
        if not flags & 1:
            heavy.reset()
        if len(out) != unpklen or sum(out) & 0xFFFF != usum:
            raise Error("%s: track %d: checksum wrong after unpacking" % (src, number))
        if unpklen != TRACK:
            raise Unsupported("%s: track %d has %d bytes, not %d" % (src, number, unpklen, TRACK))
        adf[number * TRACK:(number + 1) * TRACK] = out
        seen.add(number)
    if len(seen) != TRACKS:
        raise Error("%s: %d of %d tracks" % (src, len(seen), TRACKS))
    open(dst, "wb").write(adf)
    return len(seen)


if __name__ == "__main__":
    try:
        print("%s: %d tracks" % (sys.argv[1], convert(sys.argv[1], sys.argv[2])))
    except Error as e:
        sys.exit("dms_to_adf: %s" % e)

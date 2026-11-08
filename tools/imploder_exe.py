#!/usr/bin/env python3
"""
imploder_exe.py -- unpacker for Imploder-packed Amiga programs.

For `Fantasy_intro` and `Ambermoon_extro`.  This is another variant than the
data blocks with the `IMP!` signature (see `imploder.py`): the core is the
same, but around it lies a loader that builds a whole program.

Layout of the file (hunks, Fantasy_intro / Ambermoon_extro)
===========================================================

    0          CODE  120 bytes  start piece
    1 .. n     BSS              the hunks of the actual program (n = 4 / 6)
    n+1        CODE  512 bytes  unpacker
    n+2        DATA             packed stream
    n+3        BSS              ring buffer (18692 / 18628 bytes)

The start piece calls the unpacker, puts hunk 1 on the stack as the return
address and frees unpacker, stream and ring: **the program starts at the
beginning of hunk 1.**

Two levels
==========
1. **The core** ($84-$1F8) unpacks one ring full per call, backwards from the
   end of the ring.  It reads the stream backwards from `adda.l #n,a1` ($06).
   **The ring stays between calls**: a back reference beyond the end of the
   ring reads bytes of the previous block.  The first version of this tool made
   a new empty buffer every time; the code still came out right, the graphics
   in hunk 2 did not (20000 bytes differed).
2. **The command stream** ($00-$6A) reads the ring longword by longword from
   the end:

       bit 31 set         next target hunk (after the last one: done)
       bit 30 set         relocations: per group count, target hunk - 1,
                          then count distances (summed up); group 0 = end
       0                  nothing
       otherwise          that many longwords of data from the hunk's start

   What a target hunk does not get as data stays 0 (Amiga: MEMF_CLEAR).

Self check
==========
Three conditions must hold together: the read pointer is at the start of the
stream (`a0` = 0), the pass counter from $1EA is at zero, and the command
stream has finished all target hunks.  All of it holds for `Fantasy_intro` and
`Ambermoon_extro`.  In `Fantasy_intro` hunk 1 then holds Thalion's `FAIRY.S`
(`mani_tab`, `puls_tab`, `plot00`...).

Usage
=====
    python3 tools/imploder_exe.py <file> <target folder>

writes `hunkNN.bin` and `relocs.txt` (hunk, offset, target hunk).
"""

import os
import struct
import sys


class ExeImploderError(Exception):
    pass


def _w(x):
    return x & 0xFFFF


def _s(x):
    x &= 0xFFFF
    return x - 0x10000 if x & 0x8000 else x


class Core:
    """The unpacker, instruction by instruction after the 512-byte code hunk."""

    def __init__(self, stream, code):
        self.stream = stream
        self.code = code
        self.a0 = struct.unpack_from(">I", code, 0x08)[0]      # adda.l #n,a1
        self.size = struct.unpack_from(">H", code, 0x18)[0]    # move.w #n,d4
        self.ring = bytearray(self.size)
        # state at $1E6: d2.w, d1.b, d0.b, counter.l
        self.d2 = struct.unpack_from(">H", code, 0x1E6)[0]
        self.d1 = code[0x1E8]
        self.d0 = code[0x1E9]
        self.counter = struct.unpack_from(">I", code, 0x1EA)[0]
        self.a5 = 0
        self.done = False

    def _word(self, addr):
        return _s(struct.unpack_from(">H", self.code, addr)[0])

    def _byte(self):
        self.a0 -= 1
        if self.a0 < 0:
            raise ExeImploderError("read pointer before the start of the stream")
        return self.stream[self.a0]

    def _bit(self):
        # add.b d1,d1 / bne.s / move.b -(a0),d1 / addx.b d1,d1
        old = self.d1
        self.d1 = (old << 1) & 0xFF
        c = old >> 7
        if self.d1 == 0:
            n = self._byte()
            self.d1 = ((n << 1) | c) & 0xFF
            c = n >> 7
        return c

    def fill(self):
        """One call from $84: fills the ring from the end."""
        if self.done:
            raise ExeImploderError("command stream reads past the end")
        end = self.size
        a3 = end
        d5 = self.size
        d2, d0, a5 = self.d2, self.d0, self.a5
        ring = self.ring
        copying = d0 != 0                        # tst.b d0 / bne $1D8
        check = False
        while True:
            if not copying:
                while _w(d2):                    # $9C: direct bytes
                    d5 = _w(d5 - 1)
                    if d5 & 0x8000:
                        self.d2, self.d0, self.a5 = d2, d0, a5
                        return
                    a3 -= 1
                    ring[a3] = self._byte()
                    d2 = _w(d2 - 1)
                self.counter = (self.counter - 1) & 0xFFFFFFFF
                if self.counter == 0:            # $AC
                    self.done = True
                    self.d2, self.d0, self.a5 = d2, d0, a5
                    return
                # length ($B2-$114)
                if not self._bit():
                    d0, d7 = 2, 0
                elif not self._bit():
                    d0, d7 = 3, 1
                elif not self._bit():
                    d0, d7 = 4, 2
                elif not self._bit():
                    d0, d7 = 5, 3
                elif not self._bit():
                    for _ in range(3):
                        d0 = ((d0 << 1) | self._bit()) & 0xFF
                    d0 = (d0 + 6) & 0xFF
                    d7 = 3
                else:
                    d0, d7 = self._byte(), 3
                d3 = d7
                # number of the following direct bytes ($118-$162)
                if not self._bit():
                    d2 = _w((d2 << 1) | self._bit())
                else:
                    if not self._bit():
                        d6 = 2
                    else:
                        d6 = self.code[0x136 + d7]
                        d7 += 4
                    n = self.code[0x13A + d7]
                    while True:                  # subq.b/bne: 0 means 256
                        d2 = _w((d2 << 1) | self._bit())
                        n = (n - 1) & 0xFF
                        if n == 0:
                            break
                    d2 = _w(d2 + d6)
                # distance ($164-$1D0)
                d6, a5, d7 = 0, 0, d3
                if self._bit():
                    d3 += d3
                    if self._bit():
                        a5, d7 = self._word(0x190 + d3), d7 + 8
                    else:
                        a5, d7 = self._word(0x188 + d3), d7 + 4
                d7 = self.code[0x198 + d7]
                loop = True
                if d7 & 0x80:                    # a whole byte, then the other bits
                    d6 = self._byte()
                    d7 &= 0x0F
                    loop = d7 != 0
                if loop:
                    while True:
                        d6 = _w((d6 << 1) | self._bit())
                        d7 = (d7 - 1) & 0xFF
                        if d7 == 0:
                            break
                d6 = _w(d6 + 1)
                a5 += _s(d6) + a3                # adda.w / adda.l
                if a5 > end:                     # cmpa.l a2,a5 / bls: ring
                    a5 -= self.size
                copying = check = True
            if check and a5 == 0:                # $1D2: start -> end
                a5 = end
            d5 = _w(d5 - 1)                      # $1D8
            if d5 & 0x8000:
                self.d2, self.d0, self.a5 = d2, d0, a5
                return
            a5 -= 1
            a3 -= 1
            ring[a3] = ring[a5]
            d0 = (d0 - 1) & 0xFF
            copying = check = d0 != 0


def unpack_program(hunks):
    """hunks: list from ambtool.read_hunks().

    Returns (content, relocs): content = {hunk: bytes in full size},
    relocs = {hunk: [(offset, target hunk), ...]}.  The program starts at the
    beginning of hunk 1."""
    code_i = next(h["index"] for h in hunks
                  if h["type"] == "CODE" and h["size"] == 512)
    code = hunks[code_i]["data"]
    stream = hunks[code_i + 1]["data"]
    if hunks[code_i + 1]["type"] != "DATA":
        raise ExeImploderError("no DATA hunk behind the unpacker")
    core = Core(stream, code)
    if hunks[code_i + 2]["size"] != core.size:
        raise ExeImploderError("ring size does not fit the hunk behind it")
    count = struct.unpack_from(">H", code, 0x2A)[0]        # cmpi.w #n,d5
    targets = list(range(1, count + 1))
    size = {h["index"]: h["size"] for h in hunks}
    content = {i: bytearray(size[i]) for i in targets}
    relocs = {i: [] for i in targets}

    read_pointer = [0]                                     # a2, 0 = empty

    def byte():
        if read_pointer[0] == 0:
            core.fill()
            read_pointer[0] = core.size
        read_pointer[0] -= 1
        return core.ring[read_pointer[0]]

    def long():
        return int.from_bytes(bytes(byte() for _ in range(4)), "big")

    nr = 0
    while True:
        v = long()
        if v & 0x80000000:
            nr += 1
            if nr == count:
                break
            continue
        hunk = targets[nr]
        if v & 0x40000000:
            while True:
                n = long()
                if n == 0:
                    break
                target = long() + 1
                offset = 0
                for _ in range(n):
                    offset = (offset + long()) & 0xFFFFFFFF
                    relocs[hunk].append((offset, target))
            continue
        if v == 0:
            continue
        if 4 * v > len(content[hunk]):
            raise ExeImploderError(f"hunk {hunk}: {4 * v} bytes of data, "
                                   f"room for {len(content[hunk])}")
        for j in range(4 * v):
            content[hunk][j] = byte()

    if core.a0 != 0:
        raise ExeImploderError(f"self check: {core.a0} bytes of the stream left")
    if core.counter != 0 or not core.done:
        raise ExeImploderError(f"self check: pass counter at {core.counter}")
    return {i: bytes(b) for i, b in content.items()}, relocs


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from ambtool import read_hunks
    if len(sys.argv) != 3:
        sys.exit("usage: imploder_exe.py <file> <target folder>")
    path, folder = sys.argv[1], sys.argv[2]
    content, relocs = unpack_program(read_hunks(open(path, "rb").read()))
    os.makedirs(folder, exist_ok=True)
    for i, blob in content.items():
        open(os.path.join(folder, f"hunk{i:02d}.bin"), "wb").write(blob)
        print(f"hunk {i}: {len(blob)} bytes, {len(relocs[i])} relocations")
    with open(os.path.join(folder, "relocs.txt"), "w") as f:
        for i in content:
            for offset, target in relocs[i]:
                f.write(f"{i} {offset:06x} {target}\n")

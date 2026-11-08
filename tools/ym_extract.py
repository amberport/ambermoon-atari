#!/usr/bin/env python3
"""ym_extract.py -- Big Alec's YM version of the Ambermoon music, from the SNDH.

For the ST the pieces exist as a YM2149 version: Gunnar Gaubatz (Big Alec)
wrote them for the ST version that never came out; PHF/Nokturnal released
them in 2019 as the "Ambermoon Music Demo", and Grazey linked player and
pieces into one file, which the SNDH archive carries as
``big_alec/ambermon.snd`` (docs/13).  The user fetches that file; it is
never supplied with the port and never goes into the repository, nor does
anything this tool writes.

The way (worked out 2026-10-27 against the block of the demo disk, which
the build took until then):

1. SNDH header: ``SNDH``, ``TITLAmbermoon``, ``##18``; the payload starts
   at $D6 (``PAYLOAD``) with the jump table of Grazey's block and its
   text.  Jump table: +0 start (d0 = piece 1-18), +4 once per frame,
   +8 stop.  Only PC-relative, so it runs at any address.  The SNDH header
   jumps to the same three entries, in SNDH order (init, exit, play).
2. The SNDH version drives the player with MFP Timer A and **Timer B**; the
   demo used Timer A and **D**.  Timer B is ours on the ST (raster), so
   ``BIND_BACK`` binds the 36 bytes back to Timer D: vector $120 -> $110,
   TBCR/TBDR -> TCDCR/TDDR, bit 0 of IERA/IMRA/ISRA -> bit 4 of
   IERB/IMRB/ISRB.  Every byte is checked against its expected old value.
3. The result must hash to ``SHA256``, the first 241630 bytes of the block
   the build took from the demo disk and that was tested on hardware
   (T10 and later).  The demo block was 2714 bytes longer: the SNDH ends
   piece 18 early, the untitled one that tools/musik_ym.inf does not play.

Every place is checked; if one does not match, the tool stops.

Output (``--out``, default ``build/ym``):
    AMBERYM.BIN     player and pieces, one block
    PIECEnn.BIN    with ``--pieces``: only the data of each piece

Usage:  ym_extract.py [--sndh FILE] [--out DIR] [--pieces]
        default for --sndh: AMBER_YMSNDH (tools/paths.py)
"""
import argparse
import hashlib
import os
import struct
import sys

import paths

PAYLOAD = 0xD6                     # Grazey's block in the SNDH file
JUMP_TABLE = bytes.fromhex("6000000a600001f060000022")
SIGNATURE = b"Ambermoon Music, linked into one file by Grazey"
POINTERS, BASE, PIECES = 0x210A, 0x2152, 18   # piece pointers, block relative
SHA256 = "dcd14fbfe650903e4c31995841cc9e96d1f29167d87e954edebad34b7200bdb0"
LENGTH = 241630

# Timer B (SNDH) back to Timer D (demo): block offset, SNDH byte, our byte.
BIND_BACK = (
    [(o, 0x20, 0x10) for o in (0xB7, 0x183, 0x1AF,           # vector $120
                               0xA45, 0xA5D, 0xA75, 0xA8D)]  # -> $110
    + [(o, 0x1B, 0x1D) for o in (0xD7, 0x1CF, 0x281, 0x61D,  # TBCR $FA1B
                                 0x63D, 0x675, 0x67D, 0x75B,  # -> TCDCR $FA1D
                                 0x77B, 0x7B3, 0x7BB)]
    + [(o, 0x21, 0x25) for o in (0xDF, 0x1D7, 0x66B, 0x671,  # TBDR $FA21
                                 0x7A9, 0x7AF)]               # -> TDDR $FA25
    + [(o, 0x00, 0x04) for o in (0xF3, 0xFF, 0xA49, 0xA61,   # bit 0 -> bit 4
                                 0xA79, 0xA91)]
    + [(0xF5, 0x07, 0x09), (0x101, 0x13, 0x15)]              # IERA, IMRA
    + [(o, 0x0F, 0x11) for o in (0xA4B, 0xA63, 0xA7B, 0xA93)]  # ISRA -> ISRB
)

# Titles by YM piece, as the demo's selection list wrote them (read from
# its bitmap); piece 18 has none.
TITLES = [
    "HE IS SAILING", "COMPACT DISK", "DON'T LOOK BACH", "DOWNTOWN",
    "LA CRYPTA STRANGIATO", "WHOLE LOTTA DOVE", "CAPITAL",
    "VOICE OF THE BAGPIPE", "NOBODY'S VAULT BUT ME", "HORSE IS NO DISGRACE",
    "RIVERSIDE TRAVELLING BLUES", "PLODDING ALONG", "MELLOW CAMEL FUNK",
    "SAPHIRE FIREBALLS OF PURE LOVE", "SAPHIRE FIREBALLS OF PURE LOVE PT2",
    "LA CRYPTA STRANGIATO PT2", "MELLOW CAMEL FUNK PT2", "(untitled)",
]


def error(text):
    sys.exit("ym_extract: " + text)


def read_block(s):
    if s[12:16] != b"SNDH":
        error("not an SNDH file (or a packed one: unpack it first)")
    head = s[16:PAYLOAD]
    for mark in (b"TITLAmbermoon\0", b"##18\0"):
        if mark not in head:
            error("SNDH header lacks %r" % mark)
    b = bytearray(s[PAYLOAD:])
    if b[:12] != JUMP_TABLE:
        error("no jump table at $%X" % PAYLOAD)
    if b.find(SIGNATURE, 0, 0x100) < 0:
        error("text of Grazey's block missing")
    for o, old, new in BIND_BACK:
        if b[o] != old:
            error("$%X: $%02X, expected $%02X (Timer B)" % (o, b[o], old))
        b[o] = new
    if len(b) != LENGTH or hashlib.sha256(b).hexdigest() != SHA256:
        error("result (%d bytes) is not the tested block" % len(b))
    return bytes(b)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--sndh", default=paths.value("AMBER_YMSNDH"))
    p.add_argument("--out", default="build/ym")
    p.add_argument("--pieces", action="store_true")
    a = p.parse_args()
    if not a.sndh:
        error("no SNDH file (--sndh or AMBER_YMSNDH)")

    b = read_block(open(a.sndh, "rb").read())
    offsets = struct.unpack(">%dL" % PIECES, b[POINTERS:POINTERS + 4 * PIECES])
    starts = [BASE + v for v in offsets] + [len(b)]

    os.makedirs(a.out, exist_ok=True)
    open(os.path.join(a.out, "AMBERYM.BIN"), "wb").write(b)
    if a.pieces:
        for n in range(PIECES):
            open(os.path.join(a.out, "PIECE%02d.BIN" % (n + 1)), "wb").write(
                b[starts[n]:starts[n + 1]])

    print("AMBERYM.BIN: %d bytes (player %d, %d pieces, %d bytes bound "
          "back to Timer D)" % (len(b), BASE, PIECES, len(BIND_BACK)))
    for n in range(PIECES):
        print("  piece %2d  %6d bytes  %s"
              % (n + 1, starts[n + 1] - starts[n], TITLES[n]))


if __name__ == "__main__":
    main()

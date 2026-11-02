#!/usr/bin/env python3
"""Convert an IPF disk image (CAPS format) to an ADF.

    python3 tools/ipf_to_adf.py IN.ipf OUT.adf

Reads only AmigaDOS standard tracks, cylinders 0-79, two sides, eleven
sectors of 512 bytes. Every sector is checked against its data checksum,
its format byte and its track number; a sector that fails is reported
and left as zeros in the ADF. Copy-protected or non-standard tracks are
not decoded. Written from the IPF record layout; no code of the CAPS
library.

Proved: the nine disks of Thalion's German 1.01 give 1760/1760 sectors
each, none bad (2026-11-01). tools/game_files.py calls it for IPF images.
"""
import struct, sys

SPREAD = [sum(((b >> i) & 1) << (2 * i) for i in range(8)) for b in range(256)]

def spread16(v):
    return SPREAD[v & 0xFF] | (SPREAD[v >> 8] << 16)

def join(odd, even):
    """odd/even: bytes of equal length, 2 bytes per longword -> longs as bytes."""
    out = bytearray()
    for k in range(0, len(odd), 2):
        hi = (odd[k] << 8) | odd[k + 1]
        lo = (even[k] << 8) | even[k + 1]
        out += struct.pack('>I', (spread16(hi) << 1) | spread16(lo))
    return bytes(out)

def records(d):
    o = 0
    while o < len(d):
        t = d[o:o + 4]
        L = struct.unpack('>I', d[o + 4:o + 8])[0]
        if t == b'DATA':
            dl = struct.unpack('>I', d[o + 12:o + 16])[0]
            key = struct.unpack('>I', d[o + 24:o + 28])[0]
            yield t, d[o:o + L], d[o + L:o + L + dl], key
            o += L + dl
        else:
            yield t, d[o:o + L], None, None
            o += L

def elements(x, off):
    while True:
        h = x[off]; off += 1
        typ, n = h & 0x1F, h >> 5
        if typ == 0:
            return
        size = int.from_bytes(x[off:off + n], 'big'); off += n
        yield typ, x[off:off + size]
        off += size

def convert(src, dst):
    """-> (sectors read, bad sectors); writes the ADF either way."""
    d = open(src, 'rb').read()
    imge = {}
    adf = bytearray(80 * 2 * 11 * 512)
    seen = set(); bad = []
    for t, rec, extra, key in records(d):
        if t == b'IMGE':
            f = struct.unpack('>17I', rec[12:12 + 68])
            imge[f[13]] = f      # dataKey
        elif t == b'DATA' and extra:
            f = imge[key]
            cyl, side, nblk = f[0], f[1], f[10]
            if cyl >= 80:
                continue
            for b in range(nblk):
                bd = struct.unpack('>8I', extra[b * 32:b * 32 + 32])
                for typ, data in elements(extra, bd[7]):
                    if typ != 2 or len(data) != 540:
                        continue
                    info = join(data[0:2], data[2:4])
                    fmt, trk, sec, _ = info
                    body = join(data[28:284], data[284:540])
                    hdr = join(data[4:12], data[12:20])  # label, unused
                    dchk = struct.unpack('>I', join(data[24:26], data[26:28]))[0]
                    # data checksum: XOR of the MFM longs, masked 0x55555555
                    x = 0
                    for k in range(0, 256, 2):
                        x ^= spread16((data[28 + k] << 8) | data[29 + k])
                        x ^= spread16((data[284 + k] << 8) | data[285 + k])
                    if x != dchk or fmt != 0xFF or trk != cyl * 2 + side or sec > 10:
                        bad.append((cyl, side, b, fmt, trk, sec, hex(x), hex(dchk)))
                        continue
                    i = (trk * 11 + sec) * 512
                    adf[i:i + 512] = body
                    seen.add((trk, sec))
    open(dst, 'wb').write(adf)
    return len(seen), bad

if __name__ == '__main__':
    n, bad = convert(sys.argv[1], sys.argv[2])
    print(f'{sys.argv[1]}: {n}/1760 sectors, {len(bad)} bad', bad[:5])

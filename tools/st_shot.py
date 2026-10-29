#!/usr/bin/env python3
"""
st_shot.py -- SHOTnn.RAW of the ST intro's S key as a PNG

The test build with SCREEN_DUMP (intro_st/DUMP_ST.S) writes, per press of
S, the picture the ST showed in that frame: a header and all ST_LINES lines
of low resolution (160 bytes a line, four planes word-interleaved).  Lines
0-199 get the colours of the header, from line 200 on the colour changes
Tb_border made there (Split_colours), as on the screen.

    python3 tools/st_shot.py SHOT01.RAW [...]    # -> SHOT01.png, header on stdout

The header goes to stdout: the base of the picture, the base for the next
frame, the border counters, and whether a target screen was shown directly.
A right dump of a wrong picture points at the display, not at the memory
(docs/05c-ST.md, finding 245).
"""
import struct
import sys

from PIL import Image

HEADER = 80
LINE = 160


def st_level(v, ste):
    """One ST channel value (4 bits of the register) -> 0..255."""
    if ste:
        level = ((v & 7) << 1) | ((v >> 3) & 1)
        return level * 17
    return (v & 7) * 255 // 7


def rgb(word, ste):
    return (st_level(word >> 8, ste), st_level(word >> 4, ste),
            st_level(word, ste))


def convert(path):
    data = open(path, 'rb').read()
    (magic, vbl, base, next_base, late, missed) = struct.unpack_from(
        '>4sLLLLL', data, 0)
    if magic != b'AMSD':
        sys.exit(f'{path}: not a dump of the ST intro')
    palette = list(struct.unpack_from('>16H', data, 24))
    splits = struct.unpack_from('>H', data, 56)[0]
    split = struct.unpack_from('>8H', data, 58)
    ste, direct = data[74], data[75]
    lines = struct.unpack_from('>H', data, 76)[0]
    screen = data[HEADER:HEADER + lines * LINE]

    print(f'{path}: VBL {vbl}, base ${base:06X}, next ${next_base:06X}, '
          f'border late {late}, missed {missed}, '
          f'{"target screen" if direct else "converted"}, '
          f'{"STE" if ste else "ST"}, {lines} lines')
    lower = palette[:]
    for n in range(min(splits, 4)):
        register, value = split[2 * n], split[2 * n + 1]
        lower[register // 2] = value
        print(f'  line 200: colour {register // 2} = ${value:03X}')

    image = Image.new('RGB', (320, lines))
    pixels = image.load()
    for y in range(lines):
        colours = [rgb(w, ste) for w in (palette if y < 200 else lower)]
        row = screen[y * LINE:(y + 1) * LINE]
        for group in range(20):
            planes = struct.unpack_from('>4H', row, group * 8)
            for bit in range(16):
                mask = 0x8000 >> bit
                index = sum(1 << p for p in range(4) if planes[p] & mask)
                pixels[group * 16 + bit, y] = colours[index]
    out = path.rsplit('.', 1)[0] + '.png'
    image.save(out)
    print(f'  -> {out}')


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for name in sys.argv[1:]:
        convert(name)

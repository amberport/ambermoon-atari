#!/usr/bin/env python3
"""
st_palettes.py -- the ST colours: Thalion's 32 colours on 16 registers

For the palette file each palette is grouped by one of two **methods**
(D1), chosen per palette in tools/st_palettes.txt (`<palette> method ...`):

  unweighted    St_bauen as at run time; the default (user, 2026-10-29:
                more was right with it, the fire in Grandfather's house
                stays red)
  weighted N    by how many points of each colour the game shows with the
                palette (2D map tiles, 3D walls, objects, horizon, sky and
                floor, event pictures, combat backgrounds, the tactic
                field; every colour at least N % of them), which St_bauen
                at run time cannot know; better for the worlds (Lyramion:
                sea blue instead of grey, the greens apart), so the worlds
                take it.  Only main and automap have nothing counted.

Either method can add ` oklab` (user, 2026-11-08): the distance between two
colours is then measured in OKLab with hue and saturation counting double,
instead of plain RGB, so that colours of the same lightness but another hue
(dark brown wood, dark green meadow) stay apart.  The register values are
still the RGB means of their colours.  Build time only; St_bauen at run time
measures in RGB.

Two more lines (user, 2026-11-08) steer the grouping of one palette:

  own C C ...   these colours (1..25) form a register of their own, no
                other colour joins it (e.g. the dark brown of the bridge in
                Lyramion, which the methods put with the green of the
                meadow); a colour of the same value goes with them; several
                lines, several registers
  ramp N        the UI ramp 26..31 gets at most N registers (1..5, default
                5); the registers it gives up go to the map colours.  The
                ST takes the ramp mask from the file's table (st_rmaske), so
                ST_LIB.S needs no change

The palette editor recomputes all of this in the browser
(tools/palette_editor/st_group.js); its build compares that with this tool
for every palette and method.

Unweighted:

Recomputes St_bauen from engine/src/HULL/ST_LIB.S (32 colours on 15
registers plus colour 0, integer arithmetic like the 68000, with the
**ramp protection**: Thalion's UI ramp, colours 26..31 of every palette, gets
at most five registers of its own and is grouped only with itself; a map
colour may share a ramp register but does not count in its value).  In
Hatari on a plain ST the tables and masks matched this recomputation
exactly (docs/12).

    st_palettes.py build [-o build/STPAL.DAT]
        The palette file of the ST build -- DEVIATION (goal 2),
        docs/17-deviations.md D1: every
        palette the game puts into a raster list -- Palettes.amb, Main_pal,
        Tactic_pal, Automap_pal and the combat palettes -- reduced like
        St_bauen, with the hand corrections from tools/st_palettes.txt
        applied, an STE and an ST column each.  Also writes the listing
        build/st_palettes/listing.txt.  Called by tools/build_st.sh.
    st_palettes.py sheet [NAME ...]
        Only a pointer: the review sheet, where the method per palette is
        chosen, is the palette editor tools/palette_editor/palette_sheet.py
        (Docs, 2026-10-30; page build/palette_editor/index.html).  It
        imports this tool for the methods, the pictures and the file
        format.
    st_palettes.py ramp [-k 5] [-s 1] [-o FILE]
        Chart: colours 24..31 per palette, Thalion / without / with ramp
        protection
    st_palettes.py screen PAL [PAL ...] [-k 5] [-s 1] [--layout N] [-o FILE]
        Screen mock-up per palette (0 = Main_pal), three columns Thalion /
        without / with ramp protection
    st_palettes.py measure [-k 5] [-s 1]
        Deviation on all 2D maps, without against with ramp protection

**What goes where.**  The corrections file in the repository holds only our
own values: which Thalion colour goes into which register, and register
values chosen by hand.  Everything that contains Thalion's colours -- the
palette file and the listing -- is computed at build time from the
original files and stays in build/ (not versioned): the default register
values are averages of Thalion's colours, and a group of one colour is
Thalion's colour itself.  Needs Pillow for the pictures only.

**Since 2026-11-06** the tool also reads the 3D files (2/3Lab_data,
2/3Wall3D, 2/3Object3D, 2/3Overlay3D, Lab_background; class D3) and the
tactical icons of Combat_graphics, for the weighting and for the pictures
of the palette editor.  This changes no palette that has no method line:
STPAL.DAT stays as it was until a 3D palette or tactic gets one.
"""
import argparse
import collections
import html
import math
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ambmap                                           # noqa: E402
import ambtool                                          # noqa: E402
import farbreduktion                                    # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CORRECTIONS = os.path.join(ROOT, "tools", "st_palettes.txt")
AM2CPU_DATA = os.path.join(ROOT, "build", "am2cpu_daten.i")
OUT_DIR = "build/st_palettes"

RAMP = range(26, 32)            # what Show_layout uses of 24..31
RAMP_REGS = 5                   # ST_RAMPE_REG in ST_LIB.S
PENALTY = 1                     # map colour -> ramp register: distance x2
FLOOR = 0.01                    # "weighted" without a number: every colour at least 1 %
DEFAULT_METHOD = "unweighted"   # without a method line (user, 2026-10-29)
SHEET_METHODS = ("unweighted", "unweighted oklab", "weighted 1", "weighted 1 oklab",
                 "weighted 3")  # offered by the sheet
OKLAB_CHROMA = 2                # oklab: a and b count this many times as much as L
MAGIC = b"STP1"
ENTRY_SIZE = 176                # STP_GROESSE in ST_LIB.S
MAX_ENTRIES = 112               # STP_MAX in ST_LIB.S
LAYOUT_2D, LAYOUT_3D, LAYOUT_INV = 1, 5, 2   # Layouts.amb (.Layout_info in DISPLAY.S)
MIDDLE_Y = 36
MAP2D_X, MAP2D_Y = 16, 49       # GAME_OFF.S
PAL_2D = (1, 2, 3, 7, 8, 9, 10)
PAL_3D = (4, 5, 6, 11, 12, 13, 14, 15, 16)
# The 2D map a palette shows as its reference picture, where the automatic
# choice (the map with the most colours) misses what matters: palette ->
# (map, tile column, tile row of the cut's top left corner, place).
# Pal 7: the kitchen of Grandfather's house, its fire (user, 2026-11-06).
MAP_REFERENCE = {7: (258, 6, 0, "the kitchen of Grandfather's house")}
# 3D (GAME_OFF.S, MAP/3D_MAP.S)
LAYOUT_COMBAT = 4                       # Combat_layout
MAP3D_X, MAP3D_Y, VIEW3D = 32, 49, 144  # Map3D_X, Map3D_Y; the 3D buffer is 144 x 144
SCRY = {False: 144 // 3, True: 144 // 2}   # D3_horizon (dungeon), C3_horizon (city)
HORIZON_HEIGHT = 20                     # Horizon_height; Lab_background is 144 x 20, 4 planes
WALL_W, WALL_H = 128, 80                # Wall_width, Wall_size = 80*8*2*planes
FIRST_WALL = 101                        # map byte: 1..100 object group, from 101 wall
CITY_BIT = 6                            # City_bit of Map_special
# The 3D view, as the weighting counts it (an estimate, the 3D view itself
# changes with every step): walls cover half of it, objects a tenth, the
# rest is sky above the horizon line and floor below; the ST draws no
# textured floor or ceiling (68000).
VIEW_WALLS, VIEW_OBJECTS = 0.5, 0.1
# Tactic field (COMBAT/TACTIC.S, GAME_OFF.S): Tactic_pal from line 133 down
# (Combat_RL), the icons 16 x 14, 5 planes, at Tactic_X + 16*column,
# Tactic_Y - 1 + Tactic_cell_height*row, 6 x 5 cells.
TACTIC_LINE = 133
TACTIC_X, TACTIC_Y, TACTIC_CELL = 96, 133, 13
TACTIC_ICON = 14 * 2 * 5                # 14 lines, one word per plane, 5 planes
# Tactical_GFX in Combat_graphics: the rsgfx list before it in GAME_OFF.S
# (width/16 * Screen_depth * 2 * height * frames) plus Fighting_FXGFX
TACTICAL_GFX = sum(w // 16 * 5 * 2 * h * n for w, h, n in (
    (16, 16, 8), (16, 32, 8), (16, 16, 6), (32, 32, 24), (32, 32, 12), (32, 64, 4),
    (32, 32, 4), (16, 16, 5), (16, 16, 5), (32, 64, 1), (16, 1, 1), (16, 19, 1),
    (16, 19, 1), (16, 20, 1), (16, 20, 1), (16, 16, 1), (16, 15, 1), (16, 16, 1),
    (32, 16, 1), (64, 32, 1), (64, 32, 1), (16, 16, 1), (16, 16, 1), (32, 32, 1),
    (16, 16, 11), (48, 59, 14), (32, 32, 4), (16, 32, 2), (16, 43, 3), (32, 32, 4),
    (16, 13, 4))) + 2 * 6 * 36


# ---------------------------------------------------------------- St_bauen

def quarter(w):
    return (((w >> 8) & 15) * 4, ((w >> 4) & 15) * 4, (w & 15) * 4)


def srgb_linear(c):
    c /= 15
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def oklab(w):
    """$0RGB -> OKLab (Björn Ottosson's matrices), L times 100, a and b times
    100 * OKLAB_CHROMA, so that a difference in hue or saturation counts
    more than one in lightness."""
    r, g, b = (srgb_linear((w >> s) & 15) for s in (8, 4, 0))
    l = (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b) ** (1 / 3)
    m = (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b) ** (1 / 3)
    s = (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b) ** (1 / 3)
    k = 100 * OKLAB_CHROMA
    return (100 * (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s),
            k * (1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s),
            k * (0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s))


# The point of a colour in the space a method groups in: "rgb" like
# St_bauen (integers, quarter steps), "oklab" (floats, build time only).
SPACES = {"rgb": quarter, "oklab": oklab}


def py_sum(xs):
    """sum() as CPython computes it since 3.12, written out: integers
    exactly until the first float, then floats with Neumaier's compensation.
    Many weighted means lie exactly on a half step, where a plain sum falls
    the other way than this (four palettes of STPAL.DAT would change); written
    out, the result does not hang on the Python version, and st_group.js
    follows it step by step."""
    it = iter(xs)
    total = 0
    for x in it:
        if isinstance(x, float):
            hi, lo = total + x, 0.0
            break
        total += x
    else:
        return total
    for x in it:
        x = float(x)
        t = hi + x
        if abs(hi) >= abs(x):
            lo += (hi - t) + x
        else:
            lo += (x - t) + hi
        hi = t
    return hi + lo if lo and math.isfinite(lo) else hi


def distance(w, m, space="rgb"):
    return py_sum((a - b) ** 2 for a, b in zip(SPACES[space](w), m))


def nearest(w, centres, nfixed=0, penalty=0, space="rgb"):
    """(distance, number) of the nearest centre; on a tie the first.  To
    the first nfixed centres the distance counts 2**penalty times."""
    best = None
    for j, m in enumerate(centres):
        d = distance(w, m, space) * (1 << (penalty if j < nfixed else 0))
        if best is None or d < best[0]:
            best = (d, j)
    return best


def kmeans(points, n, fixed=(), penalty=0, space="rgb"):
    """Centres like St_bauen: farthest point, then eight rounds.  fixed are
    centres that stand already and do not move; they count when searching
    the farthest point and when assigning.  space: see SPACES (rgb rounds
    the means like the 68000)."""
    point = SPACES[space]
    fixed = list(fixed)
    if len(points) <= n:
        return fixed + [point(w) for w in points]
    centres = fixed[:]
    if not centres:
        centres.append(point(points[0]))
    while len(centres) < len(fixed) + n:
        bd, bp = -1, 0
        for w in points:
            d, _ = nearest(w, centres, len(fixed), penalty, space)
            if d > bd:
                bd, bp = d, w
        centres.append(point(bp))
    for _ in range(8):
        total = [[0, 0, 0, 0] for _ in centres]
        for w in points:
            _, j = nearest(w, centres, len(fixed), penalty, space)
            p = point(w)
            for k in range(3):
                total[j][k] += p[k]
            total[j][3] += 1
        for j in range(len(fixed), len(centres)):
            a = total[j][3]
            if a and space == "rgb":
                centres[j] = tuple((total[j][k] + a // 2) // a for k in range(3))
            elif a:
                centres[j] = tuple(total[j][k] / a for k in range(3))
    return centres


def wkmeans(points, weights, n, fixed=(), penalty=0, space="rgb"):
    """kmeans weighted by how much of the picture each colour covers
    (build time only, D1): the farthest point counts its distance times its
    weight, the centres are weighted means, twenty rounds."""
    point = SPACES[space]
    fixed = list(fixed)
    if len(points) <= n:
        return fixed + [point(w) for w in points]
    centres = fixed[:] or [point(max(points, key=lambda w: weights[w]))]
    while len(centres) < len(fixed) + n:
        bp = max(points, key=lambda w: nearest(w, centres, len(fixed), penalty,
                                                space)[0] * weights[w])
        centres.append(point(bp))
    for _ in range(20):
        total = [[0, 0, 0, 0] for _ in centres]
        for w in points:
            _, j = nearest(w, centres, len(fixed), penalty, space)
            p = point(w)
            for k in range(3):
                total[j][k] += p[k] * weights[w]
            total[j][3] += weights[w]
        for j in range(len(fixed), len(centres)):
            a = total[j][3]
            if a and space == "rgb":
                centres[j] = tuple(round(total[j][k] / a) for k in range(3))
            elif a:
                centres[j] = tuple(total[j][k] / a for k in range(3))
    return centres


def floored(counts, floor=FLOOR):
    """Weights per colour number 1..31 from pixel counts: every colour at
    least floor of all pixels, so rare bright accents keep a say.  None
    without counts."""
    total = py_sum(counts.get(i, 0) for i in range(1, 32))
    if not total:
        return None
    return {i: max(counts.get(i, 0), floor * total) for i in range(32)}


def rounded(centres):
    return [tuple(min(15, (c + 2) // 4) * 4 for c in m) for m in centres]


def registers(pal, tab, counts=lambda i, r: True, weights=None):
    """Register values like st_regs_bauen: the mean of the colours of each
    register.  With weights (colour number -> weight) the weighted mean,
    rounded half up."""
    regs = [pal[0] & 0xFFF]
    for r in range(1, 16):
        g = [i for i in range(1, 32) if tab[i] == r and counts(i, r)]
        if not g:
            regs.append(0)
            continue
        v = 0
        if weights is None:
            a = len(g)
            for s in (8, 4, 0):
                v = (v << 4) | ((sum((pal[i] >> s) & 15 for i in g) + a // 2) // a)
        else:
            a = py_sum(weights[i] for i in g)
            for s in (8, 4, 0):
                c = py_sum(((pal[i] >> s) & 15) * weights[i] for i in g) / a
                v = (v << 4) | min(15, int(c + 0.5))
        regs.append(v)
    return regs


def ramp_registers(pal, tab, weights=None):
    """Like registers, with SE_RMASKE: into a ramp register only ramp
    colours count."""
    mask = {tab[i] for i in RAMP}
    return registers(pal, tab, lambda i, r: r not in mask or i in RAMP, weights)


def unique(pal, numbers, without=()):
    out = []
    for i in numbers:
        w = pal[i] & 0xFFF
        if w not in out and w not in without:
            out.append(w)
    return out


def st_plain(pal):
    """St_bauen and st_regs_bauen before the ramp protection (until
    2026-10-04)."""
    centres = rounded(kmeans(unique(pal, range(1, 32)), 15))
    tab = [0] + [(nearest(pal[i] & 0xFFF, centres)[1] + 1) if centres else 1
                 for i in range(1, 32)]
    return tab, registers(pal, tab)


def st_ramp(pal, k=RAMP_REGS, penalty=PENALTY, weights=None, space="rgb", own=()):
    """Ramp protection: 26..31 in at most k registers of their own, only
    among themselves.  A map colour may share a ramp register; the distance
    there counts 2**penalty times, else the ramp takes the register from
    colourful colours (mushrooms grey).

    weights (colour number -> weight, see floored): the colours 1..25 are
    grouped by how much of the picture they cover, and the register values
    are weighted means.  Build time only (D1); St_bauen at run time does not
    know the pictures and stays unweighted.

    space (see SPACES): "oklab" groups by OKLab distance; its centres are
    not rounded to register steps, which only St_bauen's RGB needs.

    own: groups of colour numbers 1..25 (the file's own lines), each a
    register of its own after the ramp registers, which no other colour
    joins; a colour 1..25 of the same value goes with its group.  The other
    colours share what is left.  Too many registers: ValueError (own_error)."""
    keep = rounded if space == "rgb" else list
    ramp = unique(pal, RAMP)
    rm = keep(kmeans(ramp, min(k, len(ramp)), space=space))
    group_of = {}                       # value -> number of its own group
    for g, cs in enumerate(own):
        for c in cs:
            group_of[pal[c] & 0xFFF] = g
    rest = unique(pal, range(1, 26), without=ramp + list(group_of))
    n = 15 - len(rm) - len(own)
    if n < 0 or (rest and n < 1):
        raise ValueError("%d ramp registers and %d own groups leave no register for "
                         "the other colours" % (len(rm), len(own)))
    if weights is None:
        centres = keep(kmeans(rest, n, fixed=rm, penalty=penalty, space=space))
    else:
        wv = collections.Counter()
        for i in range(1, 26):
            wv[pal[i] & 0xFFF] += weights[i]
        centres = keep(wkmeans(rest, wv, n, fixed=rm, penalty=penalty, space=space))
    tab = [0]
    for i in range(1, 32):
        w = pal[i] & 0xFFF
        if i < RAMP[0] and w in group_of:
            tab.append(len(rm) + group_of[w] + 1)
        elif w in ramp:
            tab.append(nearest(w, rm, space=space)[1] + 1)
        else:
            j = nearest(w, centres, len(rm), penalty, space)[1]
            tab.append(j + 1 if j < len(rm) else j + 1 + len(own))
    return tab, ramp_registers(pal, tab, weights)


# ---------------------------------------------------------------- the palettes of the game

def am2cpu_bytes(label):
    """The bytes of a label in build/am2cpu_daten.i (the build extracts
    them from AM2_CPU)."""
    try:
        text = open(AM2CPU_DATA).read()
    except OSError:
        raise SystemExit("st_palettes: %s missing -- run the build first "
                         "(tools/am2cpu_extract.py)" % AM2CPU_DATA)
    part = text.split("\n%s:" % label)[1].split("even")[0]
    return [int(x, 16) for x in re.findall(r"\$([0-9A-Fa-f]{2})", part)]


def am2cpu_palette(label):
    b = am2cpu_bytes(label)
    return tuple((b[i] << 8) | b[i + 1] for i in range(0, 64, 2))


class Game:
    """Every palette the game puts into a raster list, and where each is
    used.  Sources (docs/12, ST palette file):
      pal N      Palettes.amb N: maps (Load_map_palette -> Current_pal),
                 event pictures (Event_pix_palette_table -> Batch)
      combat N   Palettes.amb N with 26..31 from Tactic_pal (COMBAT.S
                 Combat_pal, Set_layout_colours); N from Combat_bg_2D/3D_table
      main, tactic, automap   Main_pal, Tactic_pal, Automap_pal (AM2_CPU)"""

    def __init__(self, maps=True):
        self.d = farbreduktion.Daten() if maps else None
        pals = (self.d.paletten if self.d else
                [struct.unpack(">32H", p[:64]) for p in farbreduktion.lade("Palettes.amb")])
        self.palettes = pals
        self.main = am2cpu_palette("Main_pal")
        self.tactic = am2cpu_palette("Tactic_pal")
        self.automap = am2cpu_palette("Automap_pal")
        self.events = am2cpu_bytes("Event_pix_palette_table")
        self.combat_bg = {}             # palette number -> background
        for label in ("Combat_bg_2D_table", "Combat_bg_3D_table"):
            b = am2cpu_bytes(label)
            for i in range(0, len(b), 4):
                for n in b[i + 1:i + 4]:
                    self.combat_bg.setdefault(n, b[i])
        self.usage = collections.defaultdict(list)
        if self.d:
            for nr, m in sorted(self.d.karten.items()):
                kind = "2D" if m["type"] == ambmap.TYPE_2D else "3D"
                self.usage["pal %d" % m["palette"]].append("%s map %d" % (kind, nr))
        for i, n in enumerate(self.events):
            if n:
                self.usage["pal %d" % n].append("event picture %d" % (i + 1))
        for n, bg in sorted(self.combat_bg.items()):
            self.usage["combat %d" % n].append("combat background %d" % bg)
        self.pixels = collections.defaultdict(collections.Counter)   # name -> colour counts
        self.map_pixels = {}                                          # 2D map -> colour counts
        if self.d:
            self.count_pixels()
        self.usage["main"].append("top of every screen, inventory and other full screens")
        self.usage["tactic"].append("combat: tactic field below the combat picture")
        self.usage["automap"].append("automap")

    def count_pixels(self):
        """How many points of each colour the game shows with a palette, for
        the weighting (st_ramp): the tiles of every 2D map (underlay and
        overlay, each tile as often as it lies on the map), the 3D maps
        (view3d_counts), the event pictures, the combat backgrounds, the
        tactic field (tactic_counts).  main and automap stay unweighted."""
        d, tile_hist = self.d, {}
        self.d3 = D3(d)
        for nr, m in sorted(d.karten.items()):
            if m["type"] != ambmap.TYPE_2D:
                h = self.d3.view_counts(nr, m)
                self.map_pixels[nr] = h
                self.pixels["pal %d" % m["palette"]].update(h)
                continue
            ts = m["tileset"]
            if ts not in tile_hist:
                tile_hist[ts] = (ambmap.parse_tileset(d.icondata[ts - 1]), d.kacheln(ts), {})
            defs, tiles, th = tile_hist[ts]
            h = collections.Counter()
            for i in range(m["width"] * m["height"]):
                for layer, clear in ((m["underlay"][i], False), (m["overlay"][i], True)):
                    g, _ = ambmap.resolve(defs, layer)
                    if not g or g > len(tiles):
                        continue
                    if g not in th:
                        th[g] = collections.Counter(tiles[g - 1])
                    for c, k in th[g].items():
                        if not (clear and c == 0):
                            h[c] += k
            self.map_pixels[nr] = h
            self.pixels["pal %d" % m["palette"]].update(h)
        for i, n in enumerate(self.events):
            if n:
                self.pixels["pal %d" % n].update(planar_picture("Event_pix.amb", i + 1, 92))
        for n, bg in self.combat_bg.items():
            self.pixels["combat %d" % n].update(planar_picture("Combat_background.amb", bg, 95))
        self.pixels["tactic"].update(tactic_counts(d))

    def palette(self, name):
        kind, _, n = name.partition(" ")
        if kind == "main":
            return self.main
        if kind == "tactic":
            return self.tactic
        if kind == "automap":
            return self.automap
        n = int(n)
        if kind == "pal":
            return self.palettes[n - 1]
        if kind == "combat":
            p = list(self.palettes[n - 1])
            p[26:32] = self.tactic[26:32]
            return tuple(p)
        raise KeyError(name)

    def names(self):
        out = ["main", "tactic", "automap"]
        out += ["pal %d" % n for n in range(1, len(self.palettes) + 1)]
        out += ["combat %d" % n for n in sorted(self.combat_bg)]
        return out


# ---------------------------------------------------------------- corrections

class Corrections:
    """tools/st_palettes.txt: per palette name, colour -> register moves and
    register values by hand.  Format and meaning are described in the file."""

    def __init__(self, path=CORRECTIONS):
        self.colours = collections.defaultdict(dict)    # name -> {colour: reg}
        self.ste = collections.defaultdict(dict)        # name -> {reg: $0RGB}
        self.st = collections.defaultdict(dict)         # name -> {reg: $0RGB, 0..7}
        self.methods = {}                               # name -> "unweighted" | "weighted N"
        self.notes = {}                                 # name -> comment of its method line
        self.own = collections.defaultdict(list)        # name -> [(colour, ...)]
        self.ramp = {}                                  # name -> registers of the ramp
        self.lines = []                                 # the file without method, own, ramp
        self.path = path
        if not os.path.exists(path):
            return
        for nr, line in enumerate(open(path), 1):
            t = line.split("#")[0].split()
            if not t:
                self.lines.append(line)
                continue
            where = "%s:%d" % (os.path.basename(path), nr)
            try:
                if t[0] in ("pal", "combat"):
                    name, rest = "%s %d" % (t[0], int(t[1])), t[2:]
                else:
                    name, rest = t[0], t[1:]
                if rest and rest[0] == "method":
                    self.methods[name] = method_key(rest[1:])
                    if "#" in line:
                        self.notes[name] = line.split("#", 1)[1].strip()
                    continue
                if rest and rest[0] == "own":
                    cs = tuple(int(c) for c in rest[1:])
                    taken = {c for g in self.own[name] for c in g}
                    if not cs or len(set(cs)) < len(cs) or taken & set(cs) or \
                            not all(1 <= c < RAMP[0] for c in cs):
                        raise ValueError
                    self.own[name].append(cs)
                    continue
                if rest and rest[0] == "ramp":
                    n = int(rest[1])
                    if len(rest) != 2 or name in self.ramp or not 1 <= n <= RAMP_REGS:
                        raise ValueError
                    self.ramp[name] = n
                    continue
                self.lines.append(line)
                kind, a, b = rest
                if kind == "colour":
                    c, r = int(a), int(b)
                    if not (1 <= c <= 31 and 1 <= r <= 15):
                        raise ValueError
                    self.colours[name][c] = r
                elif kind in ("ste", "st"):
                    r = int(a)
                    v = int(b, 16)
                    if not (1 <= r <= 15 and len(b) == 3 and 0 <= v <= 0xFFF):
                        raise ValueError
                    if kind == "st" and any(((v >> s) & 15) > 7 for s in (8, 4, 0)):
                        raise ValueError
                    getattr(self, kind)[name][r] = v
                else:
                    raise ValueError
            except (ValueError, IndexError):
                raise SystemExit("st_palettes: %s: cannot read %r" % (where, line.strip()))

    def names(self):
        return (set(self.colours) | set(self.ste) | set(self.st) | set(self.methods)
                | {n for n, g in self.own.items() if g} | set(self.ramp))


def method_key(words):
    """["unweighted"] or ["weighted"] or ["weighted", "N"], each optionally
    followed by "oklab" -> the method as the file and the sheet name it:
    "unweighted" or "weighted N" (N % floor, 1 without a number), plus
    " oklab"."""
    suffix = ""
    if words and words[-1] == "oklab":
        words, suffix = words[:-1], " oklab"
    if words == ["unweighted"]:
        return "unweighted" + suffix
    if words and words[0] == "weighted" and len(words) <= 2:
        n = int(words[1]) if len(words) == 2 else round(FLOOR * 100)
        if 1 <= n <= 20:
            return "weighted %d" % n + suffix
    raise ValueError


def method_floor(method):
    """The floor of a method, None = unweighted."""
    w = method.split()
    return None if w[0] == "unweighted" else int(w[1]) / 100


def method_space(method):
    """The space a method groups in (SPACES)."""
    return "oklab" if method.endswith(" oklab") else "rgb"


def st_from_ste(v):
    """What the plain ST shows of an STE value: the upper three bits of each
    channel (st_ste_wort)."""
    return ((v >> 1) & 0x777)


def st_to_four_bits(v):
    """ST levels 0..7 per channel -> the 0..15 scale of the palette file, so
    that the ST shows exactly these levels: c = round(v * 15 / 7), c >> 1 = v."""
    return sum(((((v >> s) & 7) * 15 + 3) // 7) << s for s in (8, 4, 0))


class Entry:
    def __init__(self, names, pal, corr, counts=None, method=DEFAULT_METHOD):
        self.names = names
        self.pal = pal
        self.counts = counts or collections.Counter()
        self.method = method
        floor = method_floor(method)
        self.weights = floored(self.counts, floor) if floor is not None else None
        self.own = [g for n in names for g in corr.own.get(n, [])]
        self.ramp = next((corr.ramp[n] for n in names if n in corr.ramp), RAMP_REGS)
        values = [pal[c] & 0xFFF for g in self.own for c in g]
        if len(set(values)) < len(values):
            raise SystemExit("st_palettes: %s: two own groups hold the same colour value"
                             % names[0])
        try:
            tab, _ = st_ramp(pal, k=self.ramp, weights=self.weights,
                             space=method_space(method), own=self.own)
        except ValueError as err:
            raise SystemExit("st_palettes: %s: %s" % (names[0], err))
        self.tab = list(tab)
        self.auto_tab = list(tab)
        self.hand_colours, self.hand_ste, self.hand_st = {}, {}, {}
        for n in names:
            self.hand_colours.update(corr.colours.get(n, {}))
            self.hand_ste.update(corr.ste.get(n, {}))
            self.hand_st.update(corr.st.get(n, {}))
        for c, r in self.hand_colours.items():
            self.tab[c] = r
        self.mean = ramp_registers(pal, self.tab, self.weights)
        self.ste = list(self.mean)
        for r, v in self.hand_ste.items():
            self.ste[r] = v
        self.st = [st_from_ste(v) for v in self.ste]
        for r, v in self.hand_st.items():
            self.st[r] = v
        self.rep = [0]
        for r in range(1, 16):
            self.rep.append(next((i for i in range(1, 32) if self.tab[i] == r), 1))

    def pack(self):
        b = struct.pack(">32H", *self.pal)
        b += bytes(self.tab) + bytes(self.rep)
        b += struct.pack(">16H", *self.ste)
        b += struct.pack(">16H", *(st_to_four_bits(v) for v in self.st))
        assert len(b) == ENTRY_SIZE
        return b


def entries(game, corr, method=None):
    """One entry per distinct palette content, in the order of names(); a
    palette with the same content as an earlier one only adds its name, and
    its pixels to the weighting.  The method from the corrections file, else
    DEFAULT_METHOD; method, if given, for every entry (the sheet)."""
    unknown = corr.names() - set(game.names())
    if unknown:
        raise SystemExit("st_palettes: %s names palettes the game does not have: %s"
                         % (os.path.basename(corr.path), ", ".join(sorted(unknown))))
    by_content = collections.OrderedDict()
    for n in game.names():
        by_content.setdefault(game.palette(n), []).append(n)
    out = []
    for pal, names in by_content.items():
        counts = collections.Counter()
        for n in names:
            counts.update(game.pixels.get(n, {}))
        chosen = {corr.methods[n] for n in names if n in corr.methods}
        if len(chosen) > 1:
            raise SystemExit("st_palettes: %s are the same palette with different methods"
                             % " and ".join(n for n in names if n in corr.methods))
        out.append(Entry(names, pal, corr, counts,
                         method or (chosen.pop() if chosen else DEFAULT_METHOD)))
    for e in out:
        moved = [n for n in e.names if n in corr.names()]
        if len(moved) > 1:
            raise SystemExit("st_palettes: %s are the same palette; correct it under "
                             "one name only" % " and ".join(moved))
    return out


# ---------------------------------------------------------------- build

def cmd_build(a):
    game = Game(maps=True)
    corr = Corrections()
    es = entries(game, corr)
    if len(es) > MAX_ENTRIES:
        raise SystemExit("st_palettes: %d palettes, ST_LIB.S holds STP_MAX = %d"
                         % (len(es), MAX_ENTRIES))
    data = MAGIC + struct.pack(">HH", len(es), ENTRY_SIZE) + b"".join(e.pack() for e in es)
    os.makedirs(os.path.dirname(a.o) or ".", exist_ok=True)
    with open(a.o, "wb") as f:
        f.write(data)
    os.makedirs(OUT_DIR, exist_ok=True)
    listing = os.path.join(OUT_DIR, "listing.txt")
    with open(listing, "w") as f:
        f.write(listing_text(game, es))
    hand = sum(1 for e in es if e.hand_colours or e.hand_ste or e.hand_st)
    weighted = ", ".join("%s (%s)" % (e.names[0], e.method) for e in es if e.weights)
    steered = sum(1 for e in es if e.own or e.ramp != RAMP_REGS)
    print("  %s: %d palettes, weighted by pixels: %s; %d bytes, "
          "%d with hand corrections, %d with own or ramp lines; listing %s"
          % (a.o, len(es), weighted or "none", len(data), hand, steered, listing))


def hex3(v):
    return "%03X" % v


def listing_text(game, es):
    out = ["ST palettes, as the build put them into STPAL.DAT (st_palettes.py).",
           "Contains Thalion's colours: build/ only, never into the repository.",
           "* = by hand (tools/st_palettes.txt)", ""]
    for e in es:
        out.append("=== " + " = ".join(e.names))
        for n in e.names:
            for u in game.usage.get(n, []):
                out.append("    used: " + u)
        total = sum(e.counts.get(i, 0) for i in range(1, 32))
        out.append("    grouping: %s%s" % ("weighted by %d points, floor %d %%"
                                           % (total, method_floor(e.method) * 100) if e.weights
                                           else "unweighted",
                                           ", OKLab distance" if method_space(e.method) == "oklab"
                                           else ""))
        if e.ramp != RAMP_REGS or e.own:
            out.append("    ramp: at most %d registers; own groups: %s" % (
                e.ramp, "; ".join(" ".join(map(str, g)) for g in e.own) or "none"))
        out.append("    colour  Thalion  register  pixels")
        for i in range(32):
            share = ("%6.2f%%" % (100 * e.counts.get(i, 0) / total)) if total else ""
            out.append("    %6d  %s      %2d%s  %s" % (i, hex3(e.pal[i] & 0xFFF), e.tab[i],
                                                      "*" if i in e.hand_colours else " ", share))
        out.append("    register  colours                          STE    ST   mean")
        for r in range(16):
            cs = " ".join(str(i) for i in range(32) if e.tab[i] == r) or "-"
            out.append("    %8d  %-32s %s%s %s%s %s" % (
                r, cs, hex3(e.ste[r]), "*" if r in e.hand_ste else " ",
                hex3(e.st[r]), "*" if r in e.hand_st else " ", hex3(e.mean[r])))
        out.append("")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------- pictures

def rgb_amiga(w):
    return tuple(((w >> s) & 15) * 17 for s in (8, 4, 0))


def rgb_st(v):
    return tuple(round(((v >> s) & 7) * 255 / 7) for s in (8, 4, 0))


def layout_picture(d, nr):
    """Layout nr from Layouts.amb as colour numbers, 320 x 200 (the top
    MIDDLE_Y+1 lines stay 0)."""
    raw, _ = ambtool.lob_unpack(d.layouts[nr - 1])
    pic = [0] * (320 * 200)
    for y in range(199 - MIDDLE_Y):
        for x in range(320):
            v = 0
            for p in range(3):
                if raw[y * 120 + p * 40 + x // 8] >> (7 - x % 8) & 1:
                    v |= 1 << p
            pic[(MIDDLE_Y + 1 + y) * 320 + x] = v + 24 if v else 0
    return pic


def map_cut(d, m, w=176, h=144, at=None):
    """w x h points of a 2D map, rendering only those tiles: the middle, or
    from tile (column, row) at."""
    defs = ambmap.parse_tileset(d.icondata[m["tileset"] - 1])
    tiles = d.kacheln(m["tileset"])
    mw, mh = m["width"] * 16, m["height"] * 16
    x0, y0 = (at[0] * 16, at[1] * 16) if at else (mw // 2 - w // 2, mh // 2 - h // 2)
    x0 = max(0, min(mw - w, x0))
    y0 = max(0, min(mh - h, y0))
    pic = [0] * (w * h)
    for ty in range(y0 // 16, min(m["height"], (y0 + h + 15) // 16)):
        for tx in range(x0 // 16, min(m["width"], (x0 + w + 15) // 16)):
            i = ty * m["width"] + tx
            for layer, clear in ((m["underlay"][i], False), (m["overlay"][i], True)):
                g, _ = ambmap.resolve(defs, layer)
                if not g or g > len(tiles):
                    continue
                k = tiles[g - 1]
                for y in range(16):
                    py = ty * 16 + y - y0
                    if not 0 <= py < h:
                        continue
                    for x in range(16):
                        px = tx * 16 + x - x0
                        c = k[y * 16 + x]
                        if 0 <= px < w and not (clear and c == 0):
                            pic[py * w + px] = c
    return pic


_loaded = {}


def planar_picture(file, nr, height):
    raw = loaded(file)[nr - 1]
    return ambtool.planar_to_indices(raw, 320, 5, height)[0]


def loaded(file):
    """The entries of a game file, as farbreduktion.lade gives them, once
    per file (ambtool.py decrypts the unpacked entries of an AMNP container
    since main d0e8144, finding 249)."""
    if file not in _loaded:
        _loaded[file] = list(farbreduktion.lade(file))
    return _loaded[file]


def layouts(d):
    if not getattr(d, "layouts", None):
        d.layouts = loaded("Layouts.amb")
    return d.layouts


# ---------------------------------------------------------------- 3D

_BITS = [[[(b >> (7 - k) & 1) << p for k in range(8)] for b in range(256)] for p in range(4)]


def movep_picture(data, w, h):
    """Wall3D/Object3D/Overlay3D -> colour numbers 0..15: the format of the
    3D buffer (MOVEP), every 8 points of a line take 4 bytes, one per plane;
    a line is (w+7)//8 such groups."""
    groups = (w + 7) // 8
    out = []
    t0, t1, t2, t3 = _BITS
    for y in range(h):
        line = []
        for g in range(groups):
            o = (y * groups + g) * 4
            line.extend(a | b | c | e for a, b, c, e in zip(
                t0[data[o]], t1[data[o + 1]], t2[data[o + 2]], t3[data[o + 3]]))
        out.extend(line[:w])
    return out


def lab_data(raw):
    """One entry of 2/3Lab_data.amb (GAME_OFF.S, the LAByrinth offsets)."""
    sky, floor = raw[4], raw[5]

    def count(o):
        return struct.unpack_from(">H", raw, o)[0], o + 2

    n, o = count(8)
    groups = []
    for _ in range(n):
        # Object_automapper_icon, then Objects_per_group x (X, Y, Z, Object_nr)
        groups.append([struct.unpack_from(">4H", raw, o + 2 + 8 * k)[3] for k in range(8)])
        o += 2 + 8 * 8
    n, o = count(o)
    objects = []
    for _ in range(n):
        _, gfx, frames, _, w, h, _, _ = struct.unpack_from(">IHBBBBHH", raw, o)
        objects.append((gfx, frames, w, h))
        o += 14
    walls = []
    n, o = count(o)
    for _ in range(n):
        gfx, nov = raw[o + 4], raw[o + 7]
        o += 8
        walls.append((gfx, [tuple(raw[o + 6 * j:o + 6 * j + 6]) for j in range(nov)]))
        o += 6 * nov
    return {"sky": sky, "floor": floor, "groups": groups, "objects": objects, "walls": walls}


def part3d(nr):
    """Which container of the 3D files a map reads (Teildatei_waehlen in
    FILES_SUP.S, after AM2_CPU): 2 below map 300 and from 400, else 3."""
    return 3 if 300 <= nr < 400 else 2


class D3:
    """The 3D textures of the maps: walls with their overlays, objects (first
    frame), horizon, sky and floor colour.  Colour numbers 0..15 of the map
    palette (the 3D buffer has four planes)."""

    def __init__(self, d):
        self.d = d
        self._walls, self._objects = {}, {}

    def lab(self, m):
        return lab_data(loaded("2Lab_data.amb")[m["tileset"] - 1])

    def wall(self, part, wall):
        """A wall as Load_3D_map_data builds it: the graphics, then each
        overlay put in (x on 8 points, Put_(un)masked_MOVEP_block)."""
        gfx, overlays = wall
        key = (part, gfx, tuple(overlays))
        if key not in self._walls:
            pic = movep_picture(loaded("%dWall3D.amb" % part)[gfx - 1], WALL_W, WALL_H)
            for mask, g, x, y, w, h in overlays:
                x, w = x & ~7, w & ~7
                ov = movep_picture(loaded("%dOverlay3D.amb" % part)[g - 1], w, h)
                for yy in range(h):
                    for xx in range(w):
                        c = ov[yy * w + xx]
                        if (c or not mask) and x + xx < WALL_W and y + yy < WALL_H:
                            pic[(y + yy) * WALL_W + x + xx] = c
            self._walls[key] = pic
        return self._walls[key]

    def object(self, part, obj):
        """(colour numbers, width, height) of the first frame; 0 is clear."""
        gfx, _, w, h = obj
        key = (part, gfx, w, h)
        if key not in self._objects:
            raw = loaded("%dObject3D.amb" % part)[gfx - 1]
            # an entry can be empty in the container the map reads (1.07: map
            # 355, part 3, object 168 is only in part 2); then it is left out
            ok = len(raw) >= (w + 7) // 8 * 4 * h
            self._objects[key] = (movep_picture(raw, w, h) if ok else [], w, h)
        return self._objects[key]

    def horizon(self, m):
        if not m["lab_background"]:
            return None
        raw = loaded("Lab_background.amb")[m["lab_background"] - 1]
        return ambtool.planar_to_indices(raw, VIEW3D, 4, HORIZON_HEIGHT)[0]

    def contents(self, nr, m):
        """lab, part, Counter wall index -> squares, Counter object -> count."""
        lab, part = self.lab(m), part3d(nr)
        walls, objects = collections.Counter(), collections.Counter()
        for b in m["wall"]:
            if b >= FIRST_WALL:
                if b - FIRST_WALL < len(lab["walls"]):
                    walls[b - FIRST_WALL] += 1
            elif 0 < b <= len(lab["groups"]):
                for k in lab["groups"][b - 1]:
                    if 0 < k <= len(lab["objects"]):
                        objects[k - 1] += 1
        return lab, part, walls, objects

    def view_counts(self, nr, m):
        """Colour counts of a 3D map for the weighting: as many points as a
        2D map of that size (256 per square), shared out like the 3D view
        (VIEW_WALLS, VIEW_OBJECTS; sky above the horizon line SCRY, the
        horizon in it, floor below), each wall and object by how often it
        stands on the map."""
        lab, part, walls, objects = self.contents(nr, m)
        budget = m["width"] * m["height"] * 256
        sw = VIEW_WALLS if walls else 0
        so = VIEW_OBJECTS if objects else 0
        back = (1 - sw - so) * budget
        scry = SCRY[bool(m["flags"] >> CITY_BIT & 1)]
        h = collections.Counter()
        sky = back * scry / VIEW3D
        hor = self.horizon(m)
        if hor:
            part_h = sky * HORIZON_HEIGHT / scry
            sky -= part_h
            for c, k in collections.Counter(hor).items():
                h[c or lab["sky"]] += part_h * k / len(hor)
        h[lab["sky"]] += sky
        h[lab["floor"]] += back - back * scry / VIEW3D
        for share, items, pic in (
                (sw, walls, lambda i: self.wall(part, lab["walls"][i])),
                (so, objects, lambda i: [c for c in self.object(part, lab["objects"][i])[0] if c])):
            total = sum(items.values())
            for i, k in items.items():
                p = pic(i)
                if p:
                    for c, n in collections.Counter(p).items():
                        h[c] += share * budget * k / total * n / len(p)
        return h

    def view_picture(self, nr, m):
        """A mock-up of the 3D view, 144 x 144: sky, horizon and floor as
        Thalion clears and draws them, the wall that stands most often on the
        map straight ahead.  Not Thalion's 3D view (no perspective)."""
        lab, part, walls, _ = self.contents(nr, m)
        scry = SCRY[bool(m["flags"] >> CITY_BIT & 1)]
        pic = [lab["sky"]] * (VIEW3D * scry) + [lab["floor"]] * (VIEW3D * (VIEW3D - scry))
        hor = self.horizon(m)
        if hor:
            o = (scry - HORIZON_HEIGHT) * VIEW3D
            for i, c in enumerate(hor):
                if c:
                    pic[o + i] = c
        if walls:
            w = self.wall(part, lab["walls"][walls.most_common(1)[0][0]])
            x0, y0 = (VIEW3D - WALL_W) // 2, max(0, scry - WALL_H // 2)
            for y in range(min(WALL_H, VIEW3D - y0)):
                pic[(y0 + y) * VIEW3D + x0:(y0 + y) * VIEW3D + x0 + WALL_W] = w[y * WALL_W:(y + 1) * WALL_W]
        return pic

    def sheet(self, maps, width=8 * (WALL_W + 4) - 4, gap=4):
        """All walls (with overlays), objects and horizons of these 3D maps,
        each once, packed in rows: (colour numbers, width, height, legend)."""
        items, seen = [], set()
        for kind in ("wall", "object", "horizon"):
            for nr, m in maps:
                lab, part, walls, objects = self.contents(nr, m)
                if kind == "wall":
                    for i in sorted(walls):
                        p = self.wall(part, lab["walls"][i])
                        if tuple(p) not in seen:
                            seen.add(tuple(p))
                            items.append((p, WALL_W, WALL_H))
                elif kind == "object":
                    for i in sorted(objects):
                        p, w, h = self.object(part, lab["objects"][i])
                        if p and tuple(p) not in seen:
                            seen.add(tuple(p))
                            items.append((p, w, h))
                else:
                    p = self.horizon(m)
                    if p and tuple(p) not in seen:
                        seen.add(tuple(p))
                        items.append((p, VIEW3D, HORIZON_HEIGHT))
        swatches = sorted({(self.lab(m)["sky"], self.lab(m)["floor"]) for _, m in maps})
        places, x, y, row = [], 0, 0, 0
        for p, w, h in items:
            if x and x + w > width:
                x, y, row = 0, y + row + gap, 0
            places.append((x, y))
            x, row = x + w + gap, max(row, h)
        sw_y = y + row + gap
        height = sw_y + 24
        out = [0] * (width * height)
        for (p, w, h), (x0, y0) in zip(items, places):
            for yy in range(h):
                out[(y0 + yy) * width + x0:(y0 + yy) * width + x0 + w] = p[yy * w:(yy + 1) * w]
        for j, (s, f) in enumerate(swatches):
            for k, c in enumerate((s, f)):
                x0 = j * 56 + k * 24
                if x0 + 20 <= width:
                    for yy in range(20):
                        out[(sw_y + yy) * width + x0:(sw_y + yy) * width + x0 + 20] = [c] * 20
        legend = ("%d walls with their overlays, %d objects (first frame), %d horizons; "
                  "bottom row: sky and floor colour per lab"
                  % (sum(1 for _, w, h in items if (w, h) == (WALL_W, WALL_H)),
                     sum(1 for _, w, h in items if (w, h) not in ((WALL_W, WALL_H), (VIEW3D, HORIZON_HEIGHT))),
                     sum(1 for _, w, h in items if (w, h) == (VIEW3D, HORIZON_HEIGHT))))
        return out, width, height, legend


# ---------------------------------------------------------------- tactic field

def tactic_icons():
    """The tactical icons from Combat_graphics, 16 x 14 colour numbers each."""
    raw = loaded("Combat_graphics")[0][TACTICAL_GFX:]
    return [ambtool.planar_to_indices(raw[i:i + TACTIC_ICON], 16, 5, 14)[0]
            for i in range(0, len(raw) - TACTIC_ICON + 1, TACTIC_ICON)]


def tactic_picture(d):
    """The combat layout from line TACTIC_LINE down (where Tactic_pal
    holds), its tactic field filled with the icons in their order: 320 x
    (200 - TACTIC_LINE)."""
    layouts(d)
    lay = layout_picture(d, LAYOUT_COMBAT)
    h = 200 - TACTIC_LINE
    pic = lay[TACTIC_LINE * 320:]
    for n, icon in enumerate(tactic_icons()[:30]):
        x0 = TACTIC_X + 16 * (n % 6)
        y0 = TACTIC_Y + TACTIC_CELL * (n // 6) - TACTIC_LINE
        for y in range(14):
            for x in range(16):
                c = icon[y * 16 + x]
                if c and y0 + y < h:
                    pic[(y0 + y) * 320 + x0 + x] = c
    return pic, 320, h


def tactic_counts(d):
    """Weighting of Tactic_pal: the layout from line TACTIC_LINE down, and
    every tactical icon once (which ones a combat shows depends on the
    party and the monsters)."""
    layouts(d)
    h = collections.Counter(layout_picture(d, LAYOUT_COMBAT)[TACTIC_LINE * 320:])
    for icon in tactic_icons():
        h.update(c for c in icon if c)
    return h


def examples(game, d, e):
    """(caption, colour numbers, width, height) pictures for an entry."""
    out = []
    for n in e.names:
        kind, _, num = n.partition(" ")
        if kind == "pal":
            num = int(num)
            maps2d = [(nr, m) for nr, m in sorted(d.karten.items())
                      if m["palette"] == num and m["type"] == ambmap.TYPE_2D]
            maps3d = [nr for nr, m in sorted(d.karten.items())
                      if m["palette"] == num and m["type"] != ambmap.TYPE_2D]
            if maps2d:
                ref = MAP_REFERENCE.get(num)
                if ref:
                    nr, at, place = ref[0], ref[1:3], ": " + ref[3]
                    m = d.karten[nr]
                else:
                    # the map with the most colours that cover something (not
                    # the first: map 1 of Lyramion is open sea)
                    nr, m = max(maps2d, key=lambda t: (sum(
                        1 for k in game.map_pixels.get(t[0], {}).values() if k > 200), -t[0]))
                    at, place = None, ""
                pic = layout_picture(d, LAYOUT_2D)
                cut = map_cut(d, m, at=at)
                for y in range(144):
                    for x in range(176):
                        pic[(MAP2D_Y + y) * 320 + MAP2D_X + x] = cut[y * 176 + x]
                out.append(("2D map %d in the layout%s" % (nr, place), pic, 320, 200))
            if maps3d:
                # the 3D map with the most squares of wall
                nr = max(maps3d, key=lambda n: (sum(1 for b in d.karten[n]["wall"]
                                                    if b >= FIRST_WALL), -n))
                pic = layout_picture(d, LAYOUT_3D)
                view = game.d3.view_picture(nr, d.karten[nr])
                for y in range(VIEW3D):
                    pic[(MAP3D_Y + y) * 320 + MAP3D_X:(MAP3D_Y + y) * 320 + MAP3D_X + VIEW3D] = \
                        view[y * VIEW3D:(y + 1) * VIEW3D]
                out.append(("3D map %d, mock-up: sky, horizon, floor and its most common "
                            "wall, without perspective; all textures in the sheet below" % nr,
                            pic, 320, 200))
            for i, p in enumerate(game.events):
                if p == num:
                    out.append(("event picture %d" % (i + 1),
                                planar_picture("Event_pix.amb", i + 1, 92), 320, 92))
        elif kind == "combat":
            bg = game.combat_bg[int(num)]
            out.append(("combat background %d" % bg,
                        planar_picture("Combat_background.amb", bg, 95), 320, 95))
        elif kind == "main":
            out.append(("inventory layout", layout_picture(d, LAYOUT_INV), 320, 200))
        elif kind == "tactic":
            pic, w, h = tactic_picture(d)
            out.append(("combat layout from line %d, tactic field with the first 30 of "
                        "the %d tactical icons" % (TACTIC_LINE, len(tactic_icons())), pic, w, h))
    return out


def save_png(pic, w, h, colours, path):
    from PIL import Image
    im = Image.frombytes("P", (w, h), bytes(pic))
    flat = []
    for c in colours:
        flat.extend(c)
    im.putpalette(flat + [0] * (768 - len(flat)))
    im.convert("RGB").resize((w * 2, h * 2), Image.NEAREST).save(path)


def slug(names):
    return names[0].replace(" ", "_")


def colours_of(e):
    """Thalion's, the STE's and the ST's colour per colour number."""
    return ([rgb_amiga(w) for w in e.pal],
            [rgb_amiga(e.ste[e.tab[i]]) for i in range(32)],
            [rgb_st(e.st[e.tab[i]]) for i in range(32)])


def strip(title, cs):
    return "<tr><th>%s</th>%s</tr>" % (html.escape(title), "".join(
        "<td style='background:#%02x%02x%02x'></td>" % c for c in cs))


def cmd_sheet(a):
    raise SystemExit("st_palettes: the review sheet is now the palette editor:\n"
                     "  python3 tools/palette_editor/palette_sheet.py %s\n"
                     "  -> build/palette_editor/index.html"
                     % " ".join('"%s"' % n for n in a.names))


# ---------------------------------------------------------------- older views

def versions(pal, k, penalty):
    t1, r1 = st_plain(pal)
    t2, r2 = st_ramp(pal, k, penalty)
    return (("Thalion (Amiga/Falcon)", [rgb_amiga(w) for w in pal]),
            ("ST without ramp protection", [rgb_amiga(r1[t1[i]]) for i in range(32)]),
            ("ST with ramp protection, k=%d s=%d" % (k, penalty),
             [rgb_amiga(r2[t2[i]]) for i in range(32)]))


def palette_nr(game, n):
    """Number in Palettes.amb, 0 = Main_pal (inventory, bar at the top)."""
    return game.main if n == 0 else game.palettes[n - 1]


def cmd_ramp(a, game):
    from PIL import Image, ImageDraw
    rows = [(0, "Main")] + [(n, "2D") for n in PAL_2D] + [(n, "3D") for n in PAL_3D]
    S, X0, G = 22, 80, 16
    w = X0 + 3 * 8 * S + 2 * G + 8
    h = 30 + len(rows) * (S + 4)
    im = Image.new("RGB", (w, h), (40, 40, 40))
    dr = ImageDraw.Draw(im)
    for r, (n, kind) in enumerate(rows):
        y = 30 + r * (S + 4)
        dr.text((6, y + 5), "Pal %2d %s" % (n, kind), fill=(230, 230, 230))
        for s, (title, colours) in enumerate(versions(palette_nr(game, n), a.k, a.s)):
            x0 = X0 + s * (8 * S + G)
            if r == 0:
                dr.text((x0, 8), title, fill=(230, 230, 230))
            for j, i in enumerate(range(24, 32)):
                dr.rectangle([x0 + j * S, y, x0 + j * S + S - 2, y + S - 1], fill=colours[i])
    store(im.resize((w * 2, h * 2), Image.NEAREST), a.o or "ramp_k%d_s%d.png" % (a.k, a.s))


def cmd_screen(a, game):
    from PIL import Image, ImageDraw
    d = game.d
    boards = []
    for n in a.pal:
        nr = m = None
        if n in PAL_2D and not a.layout:
            nr, m = next(((nr, m) for nr, m in d.karten_2d(hoechstens=120 * 120)
                          if m["palette"] == n), (None, None))
        pic = layout_picture(d, a.layout or (LAYOUT_2D if n in PAL_2D else LAYOUT_3D))
        if m:
            cut = map_cut(d, m)
            for y in range(144):
                for x in range(176):
                    pic[(MAP2D_Y + y) * 320 + MAP2D_X + x] = cut[y * 176 + x]
        boards.append((n, nr, pic))
    G = 8
    HB = 199 - MIDDLE_Y
    w, h = 3 * 320 + 2 * G, len(boards) * (HB + 14 + G)
    im = Image.new("RGB", (w, h), (40, 40, 40))
    dr = ImageDraw.Draw(im)
    for t, (n, nr, pic) in enumerate(boards):
        y0 = t * (HB + 14 + G)
        for s, (title, colours) in enumerate(versions(palette_nr(game, n), a.k, a.s)):
            x0 = s * (320 + G)
            dr.text((x0 + 2, y0), "Pal %d%s: %s" % (
                n, (", map %d" % nr) if nr else "", title), fill=(230, 230, 230))
            for y in range(MIDDLE_Y + 1, 200):
                for x in range(320):
                    im.putpixel((x0 + x, y0 + 14 + y - MIDDLE_Y - 1), colours[pic[y * 320 + x]])
    store(im.resize((w * 2, h * 2), Image.NEAREST),
          a.o or "screen_%s_k%d_s%d.png" % ("_".join(map(str, a.pal)), a.k, a.s))


def store(im, name):
    path = name if os.path.dirname(name) else os.path.join(OUT_DIR, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im.save(path)
    print(path)


def cmd_measure(a, game):
    def measure(pal, hf, tab, regs):
        g = sum(hf.values())
        strong = total = 0
        for i, n in hf.items():
            dd = math.sqrt(sum((x - y) ** 2 for x, y in
                               zip(farbreduktion.rgb(pal[i]), farbreduktion.rgb(regs[tab[i]]))))
            total += dd * n
            if dd >= 2:
                strong += n
        return 100.0 * strong / g, total / g
    per = collections.defaultdict(list)
    d = game.d
    for nr, m in d.karten_2d():
        pic, _, _ = d.render(m)
        pal = d.paletten[m["palette"] - 1]
        hf = collections.Counter(pic)
        per[m["palette"]].append((measure(pal, hf, *st_plain(pal)),
                                  measure(pal, hf, *st_ramp(pal, a.k, a.s))))
    print("Palette maps   without: >=2 levels  mean   ramp protection k=%d s=%d: >=2 levels  mean"
          % (a.k, a.s))
    for p in sorted(per):
        e = per[p]
        mw = lambda f: sum(f(x) for x in e) / len(e)            # noqa: E731
        print("%5d %6d          %5.1f %%   %5.2f                     %5.1f %%   %5.2f"
              % (p, len(e), mw(lambda x: x[0][0]), mw(lambda x: x[0][1]),
                 mw(lambda x: x[1][0]), mw(lambda x: x[1][1])))


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    u = p.add_subparsers(dest="command", required=True)
    q = u.add_parser("build")
    q.add_argument("-o", default="build/STPAL.DAT")
    q = u.add_parser("sheet")
    q.add_argument("names", nargs="*", help='e.g. "pal 12" "combat 39" main')
    for name in ("ramp", "screen", "measure"):
        q = u.add_parser(name)
        q.add_argument("-k", type=int, default=RAMP_REGS,
                       help="registers for the ramp (ST_RAMPE_REG)")
        q.add_argument("-s", type=int, default=PENALTY,
                       help="penalty: distance map colour -> ramp register times 2**s")
        if name == "screen":
            q.add_argument("pal", type=int, nargs="+", help="0 = Main_pal")
            q.add_argument("--layout", type=int, default=0,
                           help="entry in Layouts.amb (2 = inventory)")
        if name != "measure":
            q.add_argument("-o", default=None)
    a = p.parse_args()
    if a.command == "build":
        cmd_build(a)
    elif a.command == "sheet":
        cmd_sheet(a)
    else:
        game = Game(maps=True)
        game.d.layouts = farbreduktion.lade("Layouts.amb")
        {"ramp": cmd_ramp, "screen": cmd_screen, "measure": cmd_measure}[a.command](a, game)


if __name__ == "__main__":
    main()

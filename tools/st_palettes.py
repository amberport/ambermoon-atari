#!/usr/bin/env python3
"""
st_palettes.py -- the ST colours: Thalion's 32 colours on 16 registers

For the palette file each palette is grouped by one of two **methods**
(D1), chosen per palette in tools/st_palettes.txt (`<palette> method ...`):

  unweighted    St_bauen as at run time; the default (user, 2026-10-29:
                more was right with it, the fire in Grandfather's house
                stays red)
  weighted N    by how many points of each colour the game shows with the
                palette (2D map tiles, event pictures, combat backgrounds;
                every colour at least N % of them), which St_bauen at run
                time cannot know; better for the worlds (Lyramion: sea blue
                instead of grey, the greens apart), so the worlds take it

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
        build/st_palettes/listing.txt and the review sheet (see sheet; not
        with --no-sheet), so every ST build comes with it.  Called by
        tools/build_st.sh.
    st_palettes.py sheet [NAME ...]
        Review sheet build/st_palettes/index.html: per palette Thalion's
        colours, the table, the STE and the ST registers, and a picture from
        the game: Thalion (Amiga/Falcon), then STE and ST for every method,
        each with a button to choose it; the page writes the method lines
        for tools/st_palettes.txt.  NAME as in the corrections file
        ("pal 12", "combat 39", "main"); none = all.
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
palette file, the listing, the sheet -- is computed at build time from the
original files and stays in build/ (not versioned): the default register
values are averages of Thalion's colours, and a group of one colour is
Thalion's colour itself.  Needs Pillow for the pictures only.
"""
import argparse
import collections
import html
import json
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
SHEET_METHODS = ("unweighted", "weighted 1", "weighted 3")   # offered by the sheet
MAGIC = b"STP1"
ENTRY_SIZE = 176                # STP_GROESSE in ST_LIB.S
MAX_ENTRIES = 112               # STP_MAX in ST_LIB.S
LAYOUT_2D, LAYOUT_3D, LAYOUT_INV = 1, 5, 2   # Layouts.amb (.Layout_info in DISPLAY.S)
MIDDLE_Y = 36
MAP2D_X, MAP2D_Y = 16, 49       # GAME_OFF.S
PAL_2D = (1, 2, 3, 7, 8, 9, 10)
PAL_3D = (4, 5, 6, 11, 12, 13, 14, 15, 16)


# ---------------------------------------------------------------- St_bauen

def quarter(w):
    return (((w >> 8) & 15) * 4, ((w >> 4) & 15) * 4, (w & 15) * 4)


def distance(w, m):
    return sum((a - b) ** 2 for a, b in zip(quarter(w), m))


def nearest(w, centres, nfixed=0, penalty=0):
    """(distance, number) of the nearest centre; on a tie the first.  To
    the first nfixed centres the distance counts 2**penalty times."""
    best = None
    for j, m in enumerate(centres):
        d = distance(w, m) << (penalty if j < nfixed else 0)
        if best is None or d < best[0]:
            best = (d, j)
    return best


def kmeans(points, n, fixed=(), penalty=0):
    """Centres like St_bauen: farthest point, then eight rounds.  fixed are
    centres that stand already and do not move; they count when searching
    the farthest point and when assigning."""
    fixed = list(fixed)
    if len(points) <= n:
        return fixed + [quarter(w) for w in points]
    centres = fixed[:]
    if not centres:
        centres.append(quarter(points[0]))
    while len(centres) < len(fixed) + n:
        bd, bp = -1, 0
        for w in points:
            d, _ = nearest(w, centres, len(fixed), penalty)
            if d > bd:
                bd, bp = d, w
        centres.append(quarter(bp))
    for _ in range(8):
        total = [[0, 0, 0, 0] for _ in centres]
        for w in points:
            _, j = nearest(w, centres, len(fixed), penalty)
            p = quarter(w)
            for k in range(3):
                total[j][k] += p[k]
            total[j][3] += 1
        for j in range(len(fixed), len(centres)):
            a = total[j][3]
            if a:
                centres[j] = tuple((total[j][k] + a // 2) // a for k in range(3))
    return centres


def wkmeans(points, weights, n, fixed=(), penalty=0):
    """kmeans weighted by how much of the picture each colour covers
    (build time only, D1): the farthest point counts its distance times its
    weight, the centres are weighted means, twenty rounds."""
    fixed = list(fixed)
    if len(points) <= n:
        return fixed + [quarter(w) for w in points]
    centres = fixed[:] or [quarter(max(points, key=lambda w: weights[w]))]
    while len(centres) < len(fixed) + n:
        bp = max(points, key=lambda w: nearest(w, centres, len(fixed), penalty)[0] * weights[w])
        centres.append(quarter(bp))
    for _ in range(20):
        total = [[0, 0, 0, 0] for _ in centres]
        for w in points:
            _, j = nearest(w, centres, len(fixed), penalty)
            p = quarter(w)
            for k in range(3):
                total[j][k] += p[k] * weights[w]
            total[j][3] += weights[w]
        for j in range(len(fixed), len(centres)):
            a = total[j][3]
            if a:
                centres[j] = tuple(round(total[j][k] / a) for k in range(3))
    return centres


def floored(counts, floor=FLOOR):
    """Weights per colour number 1..31 from pixel counts: every colour at
    least floor of all pixels, so rare bright accents keep a say.  None
    without counts."""
    total = sum(counts.get(i, 0) for i in range(1, 32))
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
            a = sum(weights[i] for i in g)
            for s in (8, 4, 0):
                c = sum(((pal[i] >> s) & 15) * weights[i] for i in g) / a
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


def st_ramp(pal, k=RAMP_REGS, penalty=PENALTY, weights=None):
    """Ramp protection: 26..31 in at most k registers of their own, only
    among themselves.  A map colour may share a ramp register; the distance
    there counts 2**penalty times, else the ramp takes the register from
    colourful colours (mushrooms grey).

    weights (colour number -> weight, see floored): the colours 1..25 are
    grouped by how much of the picture they cover, and the register values
    are weighted means.  Build time only (D1); St_bauen at run time does not
    know the pictures and stays unweighted."""
    ramp = unique(pal, RAMP)
    rm = rounded(kmeans(ramp, min(k, len(ramp))))
    rest = unique(pal, range(1, 26), without=ramp)
    if weights is None:
        centres = rounded(kmeans(rest, 15 - len(rm), fixed=rm, penalty=penalty))
    else:
        wv = collections.Counter()
        for i in range(1, 26):
            wv[pal[i] & 0xFFF] += weights[i]
        centres = rounded(wkmeans(rest, wv, 15 - len(rm), fixed=rm, penalty=penalty))
    tab = [0]
    for i in range(1, 32):
        w = pal[i] & 0xFFF
        if w in ramp:
            tab.append(nearest(w, rm)[1] + 1)
        else:
            tab.append(nearest(w, centres, len(rm), penalty)[1] + 1)
    return tab, ramp_registers(pal, tab, weights)


# ---------------------------------------------------------------- the palettes of the game

def am2cpu_bytes(label):
    """The bytes of a label in build/am2cpu_daten.i (the build extracts
    them from AM2_CPU)."""
    try:
        text = open(AM2CPU_DATA).read()
    except OSError:
        raise SystemExit("st_palettes: %s missing -- run the build first "
                         "(tools/am2cpu_auszug.py)" % AM2CPU_DATA)
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
        overlay, each tile as often as it lies on the map), the event
        pictures, the combat backgrounds.  The rest -- 3D maps, main,
        tactic, automap -- stays unweighted."""
        d, tile_hist = self.d, {}
        for nr, m in sorted(d.karten.items()):
            if m["type"] != ambmap.TYPE_2D:
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
        self.lines = []                                 # the file without its method lines
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
        return set(self.colours) | set(self.ste) | set(self.st) | set(self.methods)


def method_key(words):
    """["unweighted"] or ["weighted"] or ["weighted", "N"] -> the method as
    the file and the sheet name it: "unweighted" or "weighted N" (N % floor,
    1 without a number)."""
    if words == ["unweighted"]:
        return "unweighted"
    if words and words[0] == "weighted" and len(words) <= 2:
        n = int(words[1]) if len(words) == 2 else round(FLOOR * 100)
        if 1 <= n <= 20:
            return "weighted %d" % n
    raise ValueError


def method_floor(method):
    """The floor of a method, None = unweighted."""
    return None if method == "unweighted" else int(method.split()[1]) / 100


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
        tab, _ = st_ramp(pal, weights=self.weights)
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
    print("  %s: %d palettes, weighted by pixels: %s; %d bytes, "
          "%d with hand corrections; listing %s"
          % (a.o, len(es), weighted or "none", len(data), hand, listing))
    if not a.no_sheet:
        print("  review sheet, to choose the method per palette: %s"
              % write_sheet(game, corr))


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
        out.append("    grouping: %s" % ("weighted by %d points, floor %d %%"
                                         % (total, method_floor(e.method) * 100) if e.weights
                                         else "unweighted"))
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


def map_cut(d, m, w=176, h=144):
    """The middle of a 2D map, w x h points, rendering only those tiles."""
    defs = ambmap.parse_tileset(d.icondata[m["tileset"] - 1])
    tiles = d.kacheln(m["tileset"])
    mw, mh = m["width"] * 16, m["height"] * 16
    x0 = max(0, min(mw - w, mw // 2 - w // 2))
    y0 = max(0, min(mh - h, mh // 2 - h // 2))
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
    if file not in _loaded:
        _loaded[file] = farbreduktion.lade(file)
    raw = _loaded[file][nr - 1]
    return ambtool.planar_to_indices(raw, 320, 5, height)[0]


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
                # the map with the most colours that cover something (not
                # the first: map 1 of Lyramion is open sea)
                nr, m = max(maps2d, key=lambda t: (sum(
                    1 for k in game.map_pixels.get(t[0], {}).values() if k > 200), -t[0]))
                pic = layout_picture(d, LAYOUT_2D)
                cut = map_cut(d, m)
                for y in range(144):
                    for x in range(176):
                        pic[(MAP2D_Y + y) * 320 + MAP2D_X + x] = cut[y * 176 + x]
                out.append(("2D map %d in the layout" % nr, pic, 320, 200))
            if maps3d:
                out.append(("3D map %d: layout only (the 3D view needs a savestate "
                            "picture)" % maps3d[0], layout_picture(d, LAYOUT_3D), 320, 200))
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
    game = Game(maps=True)
    print(write_sheet(game, Corrections(), a.names))


def write_sheet(game, corr, names=()):
    """The review sheet build/st_palettes/index.html, for the palettes
    names (none = all); returns its path."""
    d = game.d
    d.layouts = farbreduktion.lade("Layouts.amb")
    es = entries(game, corr)
    variants = {m: entries(game, corr, m) for m in SHEET_METHODS}
    picked = list(range(len(es)))
    if names:
        want = set(names)
        picked = [k for k in picked if want & set(es[k].names)]
        if not picked:
            raise SystemExit("st_palettes: no palette called %s" % ", ".join(names))
    os.makedirs(OUT_DIR, exist_ok=True)
    parts, choices = [], []
    for k in picked:
        e = es[k]
        sl = slug(e.names)
        # a method can be chosen where the game's pictures were counted
        methods = SHEET_METHODS if sum(e.counts.values()) else ()
        name = next((n for n in e.names if n in corr.methods), e.names[0])
        if methods:
            choices.append({"slug": sl, "name": name, "method": e.method,
                            "note": corr.notes.get(name, "")})
        thalion, ste, st = colours_of(e)
        rows = ["<h2 id='%s'>%s</h2>" % (sl, html.escape(" = ".join(e.names)))]
        uses = [u for n in e.names for u in game.usage.get(n, [])]
        rows.append("<p class=use>method in tools/st_palettes.txt: <b>%s</b>%s</p>" % (
            e.method, "" if methods else " (no pictures counted: only unweighted)"))
        if uses:
            rows.append("<p class=use>%s</p>" % html.escape("; ".join(uses[:12]) +
                                                           (" ..." if len(uses) > 12 else "")))
        rows.append("<table class=pal><tr><th>colour</th>%s</tr>" %
                    "".join("<td>%d</td>" % i for i in range(32)))
        rows.append(strip("Thalion", thalion))
        for m in methods or (e.method,):
            v = variants[m][k] if methods else e
            _, vste, vst = colours_of(v)
            rows.append(strip("STE %s" % m, vste))
            rows.append(strip("ST %s" % m, vst))
        rows.append("<tr><th>register (%s)</th>%s</tr></table>" % (e.method, "".join(
            "<td%s>%d</td>" % (" class=hand" if i in e.hand_colours else "", e.tab[i])
            for i in range(32))))
        rows.append("<table class=reg><tr><th>register (%s)</th>%s</tr>" %
                    (e.method, "".join("<td>%d</td>" % r for r in range(1, 16))))
        rows.append("<tr><th>STE</th>%s</tr>" % "".join(
            "<td%s>%s</td>" % (" class=hand" if r in e.hand_ste else "", hex3(e.ste[r]))
            for r in range(1, 16)))
        rows.append("<tr><th>ST</th>%s</tr></table>" % "".join(
            "<td%s>%s</td>" % (" class=hand" if r in e.hand_st else "", hex3(e.st[r]))
            for r in range(1, 16)))
        for j, (caption, pic, w, h) in enumerate(examples(game, d, e)):
            name0 = "%s_%d_Thalion.png" % (sl, j)
            save_png(pic, w, h, thalion, os.path.join(OUT_DIR, name0))
            cols = ["<figure class=col><figcaption>Thalion (Amiga/Falcon)</figcaption>"
                    "<img src='%s'></figure>" % name0]
            for m in methods or (e.method,):
                v = variants[m][k] if methods else e
                _, vste, vst = colours_of(v)
                imgs = []
                for title, cs in (("STE", vste), ("ST", vst)):
                    fn = "%s_%d_%s_%s.png" % (sl, j, m.replace(" ", ""), title)
                    save_png(pic, w, h, cs, os.path.join(OUT_DIR, fn))
                    imgs.append("<img src='%s' title='%s'>" % (fn, title))
                if methods:
                    head = ("<label><input type=radio name='%s' value='%s'%s> %s</label>"
                            % (sl, m, " checked" if m == e.method else "", m))
                else:
                    head = m
                cols.append("<figure class='col m' data-slug='%s' data-method='%s'>"
                            "<figcaption>%s <span>STE above, ST below</span></figcaption>%s"
                            "</figure>" % (sl, m, head, "".join(imgs)))
            rows.append("<p>%s</p><div class=pics>%s</div>" % (html.escape(caption), "".join(cols)))
        parts.append("<section>%s</section>" % "\n".join(rows))
    index = "".join("<a href='#%s'>%s</a> " % (slug(es[k].names), html.escape(es[k].names[0]))
                    for k in picked)
    data = json.dumps({"default": DEFAULT_METHOD, "choices": choices,
                       "lines": "".join(corr.lines)})
    page = SHEET.replace("@INDEX@", index).replace("@PARTS@", "\n".join(parts)) \
                .replace("@DATA@", data.replace("</", "<\\/"))
    path = os.path.join(OUT_DIR, "index.html")
    with open(path, "w") as f:
        f.write(page)
    return path


SHEET = """<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>ST palettes</title><style>
body{font:14px sans-serif;background:#222;color:#ddd;margin:16px;padding-bottom:220px}
a{color:#9cf;margin-right:6px}
table{border-collapse:collapse;margin:6px 0}
td,th{border:1px solid #444;padding:2px 4px;font:12px monospace;text-align:center}
th{text-align:left;white-space:nowrap}
table.pal td{width:18px;height:18px}
.hand{background:#753 !important}
.use{color:#aaa}
.pics{display:flex;gap:8px;flex-wrap:wrap;align-items:flex-start}
figure{margin:0}figcaption{font-size:13px;margin-bottom:3px}
figcaption span{color:#888;font-size:11px}
.col{padding:4px;border:2px solid transparent;border-radius:4px}
.col.on{border-color:#6c6;background:#2c3a2c}
img{display:block;image-rendering:pixelated;width:320px;max-width:100%;margin-bottom:3px}
label{cursor:pointer;font-weight:bold}
section{border-top:1px solid #555;margin-top:16px}
#out{position:fixed;left:0;right:0;bottom:0;background:#333;border-top:2px solid #6c6;
 padding:8px 16px;display:flex;gap:12px;align-items:flex-start}
#out textarea{flex:1;height:150px;font:12px monospace;background:#111;color:#dfd;border:1px solid #555}
#out div{display:flex;flex-direction:column;gap:6px;width:220px}
button{font:13px sans-serif;padding:4px 8px}
</style></head><body>
<h1>ST palettes</h1>
<p>Built from the original files by tools/st_palettes.py sheet.  Contains
Thalion's graphics and colours: stays in build/, never into the repository
or a published page.  Brown = set by hand in tools/st_palettes.txt.</p>
<p>Choose a method per palette (only palettes whose pictures the build
counts can be weighted).  The box at the bottom holds the method lines that
differ from the default; "Download" gives the whole tools/st_palettes.txt
with them.  Then build again (tools/build_st.sh).</p>
<p>@INDEX@</p>
@PARTS@
<div id=out><textarea id=lines readonly></textarea><div>
<span id=count></span>
<button id=copy>Copy method lines</button>
<button id=save>Download st_palettes.txt</button></div></div>
<script>
const D = @DATA@;
function chosen(c) {
  const r = document.querySelector("input[name='" + c.slug + "']:checked");
  return r ? r.value : c.method;
}
function methodLines() {
  return D.choices.filter(c => chosen(c) !== D.default)
                  .map(c => (c.name + " method " + chosen(c) + "      ").slice(0, 29) +
                            (c.note ? "# " + c.note : "")).map(l => l.trimEnd());
}
function update() {
  for (const f of document.querySelectorAll(".col.m"))
    f.classList.toggle("on", chosen({slug: f.dataset.slug, method: ""}) === f.dataset.method);
  const l = methodLines();
  document.getElementById("lines").value = l.join("\\n");
  const changed = D.choices.filter(c => chosen(c) !== c.method).length;
  document.getElementById("count").textContent = l.length + " method lines (default " +
    D.default + "), " + changed + " changed against the file";
}
function wholeFile() {
  let t = D.lines.replace(/\\n*$/, "\\n");
  const l = methodLines();
  if (l.length && !/^# Methods/m.test(t))
    t += "\\n# Methods (default " + D.default + "), chosen in st_palettes.py sheet\\n";
  if (l.length) t += l.join("\\n") + "\\n";
  return t;
}
document.addEventListener("change", update);
document.getElementById("copy").onclick = () => {
  const t = document.getElementById("lines");
  t.select();
  navigator.clipboard ? navigator.clipboard.writeText(t.value) : document.execCommand("copy");
};
document.getElementById("save").onclick = () => {
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([wholeFile()], {type: "text/plain"}));
  a.download = "st_palettes.txt";
  a.click();
};
update();
</script>
</body></html>
"""


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
    q.add_argument("--no-sheet", action="store_true",
                   help="without the review sheet (it takes a few seconds)")
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

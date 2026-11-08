#!/usr/bin/env python3
"""
palette_sheet.py -- the palette editor: how each ST palette is grouped

Writes a page build/palette_editor/index.html.  For every palette of the
game it shows Thalion's colours and the STE and ST result next to pictures
from the game, and lets the user steer the grouping (user, 2026-11-08):

  method        how the colours are grouped (below); the default without a
                method line is unweighted
  UI registers  how many registers Thalion's UI ramp 26..31 may take, 5 to
                1; what it gives up goes to the map colours ("ramp N" line)
  own register  colours 1..25 marked by click form a register of their own,
                which no other colour joins ("own C C ..." line; e.g. the
                dark brown of the bridge in Lyramion, which the methods put
                with the green of the meadow)

The rest is grouped by the method.  The page computes all of it itself
(st_group.js, inlined), so every click shows the result at once: the colour
strips, the registers, the pictures, the whole world of a 2D palette, every
3D texture of a 3D palette.  It writes the lines of tools/st_palettes.txt
(ST's file, format in its head) and offers the whole file to download.

**The page computes what the build will put into STPAL.DAT**: before it is
written, this tool runs st_group.js through node for every palette, with
every method, with the file's lines and with made-up own and ramp lines, and
stops on the first table that differs from tools/st_palettes.py.  Without
node it says so and goes on.

The methods (tools/st_palettes.py):

  unweighted    St_bauen as at run time: all 32 colours count the same
  weighted N    by how many points of each colour the game shows with the
                palette, every colour at least N %; good for the worlds
                (Lyramion: sea blue instead of grey)
  ... oklab     either of them with the colour distance measured in OKLab,
                hue and saturation counting double (user, 2026-11-08)

The pictures go as colour numbers, zlib-packed, into one <slug>_view.js per
palette beside the page.  The page starts from the file the build read
(default tools/st_palettes.txt of this checkout; --file another);
"Open st_palettes.txt" on the page reads a newer one, hand corrections
included, without a new build.

The page contains Thalion's graphics and colours: it stays in build/, never
into the repository or a published page.

Usage:  palette_sheet.py [NAME ...] [--file FILE] [-o DIR]
        NAME as in st_palettes.txt ("pal 12", "combat 39", "main"); none = all
"""
import argparse
import base64
import collections
import datetime
import html
import json
import math
import os
import shutil
import subprocess
import sys
import types
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import ambmap                                           # noqa: E402
import farbreduktion                                    # noqa: E402
import st_palettes as stp                               # noqa: E402

OUT_DIR = "build/palette_editor"
ST_GROUP = os.path.join(HERE, "st_group.js")

# What each method does, in the legend and as the tooltip of its button.
ABOUT = {
    "unweighted": "St_bauen as the ST computes it at run time: all 32 colours "
                  "count the same, so rare accents keep a register of their "
                  "own (the fire in Grandfather's house stays red).",
    "weighted": "Grouped by how many points of each colour the game shows "
                "with this palette (2D maps, 3D walls, objects, sky and floor, "
                "event pictures, combat backgrounds, the tactic field); large "
                "areas get the closer colours (Lyramion: "
                "sea blue instead of grey, the greens apart).  Every colour "
                "counts as at least %d %% of the points; the higher this "
                "floor, the more rare colours (lights, edges) keep their own "
                "register, the closer to unweighted.",
}
ABOUT_OKLAB = ("  OKLab: the distance between two colours is measured in OKLab, "
               "where a difference in hue or saturation counts twice as much as "
               "one in lightness, instead of in plain RGB: colours of the same "
               "lightness but another hue (dark brown wood, dark green meadow) "
               "stay apart.  The register values are still the means of their "
               "colours.  Only in STPAL.DAT; St_bauen on the ST (palettes not in "
               "the file, dark 3D light levels) measures in RGB.")


def about(m):
    w = m.split()
    text = ABOUT[w[0]] if w[0] == "unweighted" else ABOUT["weighted"] % int(w[1])
    return text + (ABOUT_OKLAB if w[-1] == "oklab" else "")


def offered(corr):
    """The sheet's methods, and any other the file names (e.g. weighted 5),
    so that a palette always shows the method it has."""
    extra = sorted(set(corr.methods.values()) - set(stp.SHEET_METHODS),
                   key=lambda m: stp.method_floor(m) or 0)
    return tuple(stp.SHEET_METHODS) + tuple(extra)


WORLD_BIT = 10                  # World_map_bit of Map_special (GAME_OFF.S)
DETAIL = (40, 25)               # tiles of the full-size cut of a world


def packed(data):
    """bytes -> base64 of their zlib stream (the page inflates it with
    DecompressionStream)."""
    return base64.b64encode(zlib.compress(bytes(data), 9)).decode("ascii")


def world_maps(d, num):
    """The 2D maps of palette num that are world map squares, with their
    place: (columns, rows, map width, map height, [(nr, m, column, row)]),
    or None.  The squares are numbered row by row (Lyramion: maps 1..256,
    16 per row)."""
    ms = [(nr, m) for nr, m in sorted(d.karten.items())
          if m["palette"] == num and m["type"] == ambmap.TYPE_2D
          and m["flags"] >> WORLD_BIT & 1]
    if len(ms) < 2:
        return None
    mw, mh = ms[0][1]["width"], ms[0][1]["height"]
    lo, hi = ms[0][0], ms[-1][0]
    cols = math.isqrt(hi - lo + 1)
    if cols * cols < hi - lo + 1:
        cols += 1
    rows = (hi - lo) // cols + 1
    return cols, rows, mw, mh, [(nr, m, (nr - lo) % cols, (nr - lo) // cols)
                                for nr, m in ms if (m["width"], m["height"]) == (mw, mh)]


def world_data(d, world):
    """The whole world for the page: the tiles it uses (16 x 16 colour
    numbers each, id 0 = none), underlay and overlay ids per square
    (big-endian words), and an overview of 2 x 2 points per square (the
    most frequent colour of each 8 x 8 quarter of the square as drawn)."""
    cols, rows, mw, mh, maps = world
    W, H = cols * mw, rows * mh
    ids, tiles = {}, [bytes(256)]
    under, over = bytearray(W * H * 2), bytearray(W * H * 2)
    overview = bytearray(W * 2 * H * 2)
    quarters = {}
    for nr, m, cx, cy in maps:
        ts = m["tileset"]
        defs = ambmap.parse_tileset(d.icondata[ts - 1])
        gfx = d.kacheln(ts)
        for i in range(mw * mh):
            pair = []
            for layer in (m["underlay"][i], m["overlay"][i]):
                g, _ = ambmap.resolve(defs, layer)
                if not g or g > len(gfx):
                    pair.append(0)
                    continue
                if (ts, g) not in ids:
                    ids[(ts, g)] = len(tiles)
                    tiles.append(bytes(gfx[g - 1]))
                pair.append(ids[(ts, g)])
            x, y = cx * mw + i % mw, cy * mh + i // mw
            o = (y * W + x) * 2
            under[o:o + 2] = pair[0].to_bytes(2, "big")
            over[o:o + 2] = pair[1].to_bytes(2, "big")
            key = tuple(pair)
            if key not in quarters:
                pix = bytearray(tiles[pair[0]])
                for j, c in enumerate(tiles[pair[1]] if pair[1] else ()):
                    if c:
                        pix[j] = c
                quarters[key] = [collections.Counter(
                    pix[(qy * 8 + yy) * 16 + qx * 8 + xx]
                    for yy in range(8) for xx in range(8)).most_common(1)[0][0]
                    for qy in (0, 1) for qx in (0, 1)]
            q = quarters[key]
            o = (2 * y) * 2 * W + 2 * x
            overview[o], overview[o + 1] = q[0], q[1]
            overview[o + 2 * W], overview[o + 2 * W + 1] = q[2], q[3]
    return {"kind": "world", "w": W, "h": H, "mw": mw, "mh": mh, "cols": cols,
            "maps": [[nr, cx, cy] for nr, _, cx, cy in maps],
            "detail": list(DETAIL), "tiles": packed(b"".join(tiles)),
            "under": packed(under), "over": packed(over), "overview": packed(overview)}


def viewers(game, d, e):
    """The large pictures: the whole world of a 2D palette, the 3D textures
    of a 3D palette.  [(caption, block)]"""
    blocks = []
    for n in e.names:
        kind, _, num = n.partition(" ")
        if kind != "pal":
            continue
        num = int(num)
        world = world_maps(d, num)
        if world:
            cols, rows, mw, mh, maps = world
            blocks.append(("the whole world: %d x %d maps of %d x %d squares "
                           "(maps %d-%d); overview 2 points per square, click it for the "
                           "cut at full size" % (cols, rows, mw, mh, maps[0][0], maps[-1][0]),
                           world_data(d, world)))
        maps3d = [(nr, m) for nr, m in sorted(d.karten.items())
                  if m["palette"] == num and m["type"] != ambmap.TYPE_2D]
        if maps3d:
            pic, w, h, legend = game.d3.sheet(maps3d)
            blocks.append(("3D textures of its %d maps: %s" % (len(maps3d), legend),
                           {"kind": "pixels", "w": w, "h": h, "pixels": packed(pic)}))
    return blocks


def palette_data(e):
    """What st_group.js needs of an entry: Thalion's colours, their OKLab
    points (computed here, so that no pow() of two languages has to agree),
    the counted points and which of them Python holds as floats (py_sum)."""
    counts = [e.counts.get(i, 0) for i in range(32)]
    return {"pal": list(e.pal), "ok": [list(stp.oklab(w & 0xFFF)) for w in e.pal],
            "counts": counts, "countsFloat": [isinstance(c, float) for c in counts]}


# ---------------------------------------------------------------- the check against st_palettes.py

RUNNER = r"""
const STG = require(process.argv[1]);
let s = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", d => { s += d; });
process.stdin.on("end", () => {
  const q = JSON.parse(s);
  const res = q.cases.map(k => {
    const r = STG.compute(q.palettes[k.p], k.c);
    return r.error ? {error: r.error} : {tab: r.tab, ste: r.ste, st: r.st};
  });
  process.stdout.write(JSON.stringify({res, file: STG.readFile(q.file)}));
});
"""


def made_up(e):
    """Own and ramp lines no file has, to try the paths the file does not
    take: (own groups, ramp, hand colours, hand ste, hand st)."""
    ramp_values = {e.pal[i] & 0xFFF for i in stp.RAMP}
    free, seen = [], set()
    for i in range(1, stp.RAMP[0]):
        w = e.pal[i] & 0xFFF
        if w not in seen and w not in ramp_values:
            seen.add(w)
            free.append(i)
    out = []
    if len(free) >= 2:
        out.append(([free[:2]], 3, {free[0]: 3}, {2: 0xA84}, {3: 0x333}))
    if len(free) >= 6:
        out.append(([free[2:3], free[3:6]], 2, {}, {}, {}))
        out.append(([free[k:k + 1] for k in range(len(free))][:11], 5, {}, {}, {}))
    out.append(([], 1, {}, {}, {}))
    return out


def python_result(e, method, own, ramp, colours, ste, st):
    """st_palettes.py's Entry for these lines: (tab, ste, st) or an error."""
    n = e.names[0]
    corr = types.SimpleNamespace(colours={n: colours}, ste={n: ste}, st={n: st},
                                 own={n: [tuple(g) for g in own]}, ramp={n: ramp})
    try:
        x = stp.Entry(e.names, e.pal, corr, e.counts, method)
    except SystemExit as err:
        return {"error": str(err)}
    return {"tab": x.tab, "ste": x.ste, "st": x.st}


def check_js(corr, es, methods):
    """Runs st_group.js through node for every entry and method, with the
    file's lines and made-up ones, and the file through its reader; stops
    on the first difference.  Returns a line for the page."""
    node = shutil.which("node")
    if not node:
        print("palette_sheet: no node: the page's grouping (st_group.js) was not "
              "compared with st_palettes.py")
        return "not compared with st_palettes.py (no node at build time)"
    palettes, cases, expected = [], [], []
    for k, e in enumerate(es):
        palettes.append(palette_data(e))
        lines = [(e.own, e.ramp, e.hand_colours, e.hand_ste, e.hand_st)] + made_up(e)
        for m in methods:
            for own, ramp, colours, ste, st in lines:
                cases.append({"p": k, "c": {
                    "method": m, "own": [list(g) for g in own], "ramp": ramp,
                    "hand": {"colours": colours, "ste": ste, "st": st}}})
                expected.append(python_result(e, m, own, ramp, colours, ste, st))
    text = open(corr.path).read() if os.path.exists(corr.path) else ""
    query = json.dumps({"palettes": palettes, "cases": cases, "file": text})
    run = subprocess.run([node, "-e", RUNNER, ST_GROUP], input=query, capture_output=True,
                         text=True)
    if run.returncode:
        raise SystemExit("palette_sheet: node stopped on st_group.js:\n" + run.stderr)
    got = json.loads(run.stdout)
    bad = []
    for case, py, js in zip(cases, expected, got["res"]):
        if ("error" in py) != ("error" in js) or ("error" not in py and py != js):
            bad.append("%s, %s: st_palettes.py %s, st_group.js %s" % (
                es[case["p"]].names[0], json.dumps(case["c"]), py, js))
    bad += file_differences(corr, got["file"])
    if bad:
        raise SystemExit("palette_sheet: st_group.js differs from st_palettes.py "
                         "(%d of %d):\n  %s" % (len(bad), len(cases), "\n  ".join(bad[:10])))
    print("  palette editor: st_group.js equals st_palettes.py in %d cases "
          "(%d palettes, %d methods)" % (len(cases), len(es), len(methods)))
    return "checked at build time: equals st_palettes.py in %d cases" % len(cases)


def file_differences(corr, js):
    """What st_group.js read of the file, against Corrections."""
    out = []
    if js["bad"]:
        out.append("st_group.js cannot read line %s" % js["bad"])
    if js["keep"] != "".join(corr.lines):
        out.append("st_group.js keeps other lines than Corrections")
    for n in sorted(corr.names() | set(js["names"])):
        j = js["names"].get(n, {"own": [], "hand": {"colours": {}, "ste": {}, "st": {}}})
        mine = (corr.methods.get(n), [list(g) for g in corr.own.get(n, [])], corr.ramp.get(n),
                corr.colours.get(n, {}), corr.ste.get(n, {}), corr.st.get(n, {}))
        theirs = (j.get("method"), j["own"], j.get("ramp"),
                  *({int(a): b for a, b in j["hand"][k].items()} for k in ("colours", "ste", "st")))
        if mine != theirs:
            out.append("%s: Corrections %s, st_group.js %s" % (n, mine, theirs))
    return out


# ---------------------------------------------------------------- the page

def write_page(game, corr, names=(), out=OUT_DIR):
    d = game.d
    d.layouts = farbreduktion.lade("Layouts.amb")
    es = stp.entries(game, corr)
    methods = offered(corr)
    checked = check_js(corr, es, methods)
    picked = list(range(len(es)))
    if names:
        want = set(names)
        picked = [k for k in picked if want & set(es[k].names)]
        if not picked:
            raise SystemExit("palette_sheet: no palette called %s" % ", ".join(names))
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):           # the PNGs of the page before 2026-11-08
        if f.endswith(".png") or f.endswith("_view.js"):
            os.remove(os.path.join(out, f))
    scripts, palettes = [], []
    for k in picked:
        e = es[k]
        sl = stp.slug(e.names)
        uses = [u for n in e.names for u in game.usage.get(n, [])]
        block = palette_data(e)
        block.update({
            "names": e.names,
            "usage": "; ".join(uses[:12]) + (" ..." if len(uses) > 12 else ""),
            "counted": bool(sum(e.counts.values())),
            "examples": [{"caption": c, "w": w, "h": h, "px": packed(pic)}
                         for c, pic, w, h in stp.examples(game, d, e)],
            "viewers": [dict(b, caption=c) for c, b in viewers(game, d, e)]})
        fn = "%s_view.js" % sl
        with open(os.path.join(out, fn), "w") as f:
            f.write("PV.add(%s, %s);\n" % (json.dumps(sl), json.dumps(block)))
        scripts.append("<script src='%s'></script>" % fn)
        palettes.append(sl)
    legend = "".join("<dt>%s%s</dt><dd>%s</dd>" % (
        m, " <em class=def>default</em>" if m == stp.DEFAULT_METHOD else "", about(m))
        for m in methods)
    when = datetime.datetime.fromtimestamp(os.path.getmtime(corr.path)) \
        if os.path.exists(corr.path) else None
    data = json.dumps({
        "default": stp.DEFAULT_METHOD, "methods": list(methods),
        "about": {m: about(m) for m in methods}, "palettes": palettes,
        "text": open(corr.path).read() if when else "",
        "file": os.path.relpath(corr.path), "checked": checked,
        "when": when.strftime("%Y-%m-%d %H:%M") if when else "missing"})
    page = PAGE.replace("@LEGEND@", legend).replace("@SCRIPTS@", "\n".join(scripts)) \
               .replace("@STG@", open(ST_GROUP).read()) \
               .replace("@DATA@", data.replace("</", "<\\/"))
    path = os.path.join(out, "index.html")
    with open(path, "w") as f:
        f.write(page)
    return path


PAGE = r"""<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Palette editor</title><style>
body{font:14px sans-serif;background:#222;color:#ddd;margin:16px;padding-bottom:240px}
a{color:#9cf;margin-right:6px}
table{border-collapse:collapse;margin:6px 0}
td,th{border:1px solid #444;padding:2px 4px;font:12px monospace;text-align:center}
th{text-align:left;white-space:nowrap}
table.pal td{width:20px;height:20px;padding:0}
table.pal tr.thal td.pick{cursor:pointer}
table.pal tr.thal td{position:relative;font:bold 11px sans-serif;color:#fff;
 text-shadow:0 0 2px #000,0 0 2px #000}
table.pal td.sel{outline:3px solid #fff;outline-offset:-3px}
table.pal td.ui{opacity:.75}
.hand{background:#753 !important}
.own{background:#356 !important}
.uireg{background:#444 !important}
.use{color:#aaa}
.err{color:#f96}
dl{margin:6px 0 12px}dt{font-weight:bold;margin-top:6px}dd{margin:2px 0 0 20px;color:#bbb}
em{font-style:normal;font-size:11px;padding:0 4px;border-radius:3px;margin-left:4px}
em.def{background:#346;color:#cdf}
em.inf{background:#552;color:#ffc}
.ctl{display:flex;gap:6px 16px;flex-wrap:wrap;align-items:center;margin:6px 0;
 padding:6px;background:#2a2a2a;border-radius:4px}
.ctl label{cursor:pointer;white-space:nowrap}
.ctl .grp{display:inline-block;background:#356;border-radius:3px;padding:1px 6px;margin-right:4px}
.ctl .grp button{padding:0 4px;margin-left:4px;font-size:11px}
.pics{display:flex;gap:8px;flex-wrap:wrap;align-items:flex-start}
figure{margin:0}figcaption{font-size:13px;margin-bottom:3px}
canvas.pic{display:block;image-rendering:pixelated;width:320px;max-width:100%}
section{border-top:1px solid #555;margin-top:16px}
details{margin:4px 0}summary{cursor:pointer;color:#aaa}
#state{padding:6px 8px;background:#2a2a2a;border-left:3px solid #6c6}
#state.warn{border-left-color:#c84}
#out{position:fixed;left:0;right:0;bottom:0;background:#333;border-top:2px solid #6c6;
 padding:8px 16px;display:flex;gap:12px;align-items:flex-start;flex-wrap:wrap}
#out textarea{flex:1;min-width:200px;height:160px;font:12px monospace;background:#111;
 color:#dfd;border:1px solid #555}
#out div{display:flex;flex-direction:column;gap:6px;width:230px}
button{font:13px sans-serif;padding:4px 8px}
.vbar{display:flex;gap:4px;flex-wrap:wrap;margin:4px 0}
.vbar button{font-size:12px;padding:2px 6px}
.vbar button.on{background:#6c6;color:#000}
.vbox{overflow:auto;max-width:100%;max-height:70vh;border:1px solid #444}
.vbox canvas{display:block;image-rendering:pixelated;cursor:crosshair}
canvas.detail{display:block;image-rendering:pixelated;width:1280px;max-width:100%;margin-top:4px}
</style>
<script>const PV = {d: {}, add(id, v) { this.d[id] = v; }};</script>
@SCRIPTS@
</head><body>
<h1>Palette editor</h1>
<p>How each palette of the ST is grouped from Thalion's 32 colours onto 16
registers.  Built from the original files by
tools/palette_editor/palette_sheet.py; contains Thalion's graphics and
colours, so it stays in build/, never into the repository or a published
page.</p>
<p>Per palette: choose the <b>method</b>; choose how many <b>UI
registers</b> Thalion's window and text colours 26..31 may take (fewer
leave more for the map); click colours 1..25 in the Thalion row and make
them an <b>own register</b>, which no other colour joins (colours of the same
value go along).  The rest is grouped by the method.  Every change is
computed at once by the page, the same way the build computes STPAL.DAT
(<span id=checked></span>); the pictures, the whole world and the 3D
textures show it, their buttons switch between Thalion, STE and ST.  In a
world, click the overview for the cut at full size.  Brown cells are set by
hand in st_palettes.txt (colour, ste, st lines); hand colour lines name
register numbers, which own and UI registers shift.</p>
<dl>@LEGEND@</dl>
<p>Each palette starts as <b>in the file</b>; without lines it has the
<b>default</b>.  The box at the bottom holds the method, ramp and own lines
that differ from the default; "Download" gives the whole st_palettes.txt
with them.  Put it into tools/st_palettes.txt and build again
(tools/build_st.sh).</p>
<p id=state></p>
<p id=index></p>
<div id=parts></div>
<div id=out><textarea id=lines readonly></textarea><div>
<span id=count></span>
<button id=open>Open st_palettes.txt</button>
<input id=pick type=file accept=".txt,text/plain" hidden>
<button id=asfile>As in the file</button>
<button id=todefault>All to default</button>
<button id=copy>Copy lines</button>
<button id=save>Download st_palettes.txt</button></div></div>
<script>
@STG@
</script>
<script>
"use strict";
const D = @DATA@;
const RAMP0 = STG.RAMP0, RAMP_REGS = STG.RAMP_REGS;
const S = {};                    // slug -> state of its palette
let fileName = D.file, fileWhen = D.when, keepText = "", others = [], methods = D.methods.slice();

const el = (tag, attrs, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {}))
    if (k === "class") e.className = v; else if (k.startsWith("on")) e[k] = v; else e.setAttribute(k, v);
  for (const k of kids) e.append(k);
  return e;
};
const amiga = w => [((w >> 8) & 15) * 17, ((w >> 4) & 15) * 17, (w & 15) * 17];
const stRgb = v => [8, 4, 0].map(s => Math.round(((v >> s) & 7) * 255 / 7));
const css = c => "rgb(" + c.join(",") + ")";
const hex3 = v => v.toString(16).toUpperCase().padStart(3, "0");
const sameLines = (a, b) => a.method === b.method && a.ramp === b.ramp &&
  JSON.stringify(a.own) === JSON.stringify(b.own);
const copyLines = l => ({method: l.method, ramp: l.ramp, own: l.own.map(g => g.slice())});

// The lines of the file for one palette, as st_palettes.py's Entry takes
// them: the method of the first name that has one, the own lines of all
// names, the ramp of the first, the hand corrections of all.
function fromFile(P, f) {
  let name = null, method = null, ramp = null;
  const own = [], notes = {method: "", ramp: "", own: {}}, hand = {colours: {}, ste: {}, st: {}};
  for (const n of P.names) {
    const e = f.names[n];
    if (!e) continue;
    name = name || n;
    if (method === null && e.method) { method = e.method; notes.method = e.note; }
    if (ramp === null && e.ramp) { ramp = e.ramp; notes.ramp = e.rampNote; }
    e.own.forEach((g, k) => { own.push(g.slice()); notes.own[g.join(" ")] = e.ownNotes[k]; });
    for (const k of ["colours", "ste", "st"]) Object.assign(hand[k], e.hand[k]);
  }
  return {name: name || P.names[0], notes, hand,
          lines: {method: method || D.default, ramp: ramp || RAMP_REGS, own}};
}
function compute(slug, lines) {
  const s = S[slug];
  return STG.compute(PV.d[slug], {method: lines.method, own: lines.own, ramp: lines.ramp, hand: s.hand});
}
function methodsFor(slug) {
  const P = PV.d[slug], ms = methods.filter(m => P.counted || STG.methodFloor(m) === null);
  if (!ms.includes(S[slug].cur.method)) ms.push(S[slug].cur.method);
  return ms;
}
function lineText(head, note) {
  return (head.padEnd(28) + " " + (note ? "# " + note : "")).trimEnd();
}
function linesOf(name, l, notes) {
  const out = [];
  if (l.method !== D.default) out.push(lineText(name + " method " + l.method, notes.method));
  if (l.ramp !== RAMP_REGS) out.push(lineText(name + " ramp " + l.ramp, notes.ramp));
  for (const g of l.own) out.push(lineText(name + " own " + g.join(" "), notes.own[g.join(" ")]));
  return out;
}
function allLines() {
  const out = [];
  for (const slug of D.palettes) out.push(...linesOf(S[slug].name, S[slug].cur, S[slug].notes));
  return out.concat(others);
}

// ---- one palette
function build(slug) {
  const P = PV.d[slug], s = S[slug];
  const sec = el("section", {id: slug});
  sec.append(el("h2", {}, P.names.join(" = ")));
  if (P.usage) sec.append(el("p", {class: "use"}, P.usage));
  const info = el("p", {class: "use"});
  const ctl = el("div", {class: "ctl"});
  const err = el("p", {class: "err"});
  // the colour table
  const tab = el("table", {class: "pal"});
  const head = el("tr", {}, el("th", {}, "colour"));
  for (let i = 0; i < 32; i++) head.append(el("td", {}, String(i)));
  const rows = {};
  for (const [key, title] of [["thal", "Thalion (click 1..25)"], ["ste", "STE"], ["st", "ST"], ["reg", "register"]]) {
    rows[key] = el("tr", {class: key}, el("th", {}, title));
    for (let i = 0; i < 32; i++) rows[key].append(el("td"));
    tab.append(rows[key]);
  }
  tab.prepend(head);
  for (let i = 1; i < RAMP0; i++) {
    const td = rows.thal.children[i + 1];
    td.classList.add("pick");
    td.title = "colour " + i + ": click to mark";
    td.onclick = () => {
      const w = P.pal[i] & 0xFFF, on = !s.sel.has(i);
      for (let j = 1; j < RAMP0; j++) if ((P.pal[j] & 0xFFF) === w) on ? s.sel.add(j) : s.sel.delete(j);
      refresh(slug, false);
    };
  }
  for (let i = RAMP0; i < 32; i++) {
    rows.thal.children[i + 1].classList.add("ui");
    rows.thal.children[i + 1].title = "colour " + i + ": Thalion's UI ramp";
  }
  const reg = el("table", {class: "reg"});
  const rh = el("tr", {}, el("th", {}, "register"));
  const rste = el("tr", {}, el("th", {}, "STE")), rst = el("tr", {}, el("th", {}, "ST"));
  for (let r = 1; r < 16; r++) { rh.append(el("td", {}, String(r))); rste.append(el("td")); rst.append(el("td")); }
  reg.append(rh, rste, rst);
  const cmp = el("table", {class: "pal"});
  const det = el("details", {}, el("summary", {}, "all methods with these UI and own registers"), cmp);
  sec.append(info, ctl, err, tab, reg, det);
  // pictures, painted when the section comes into view
  const pics = [];
  for (const ex of P.examples) {
    const cs = ["Thalion", "STE", "ST"].map(() => el("canvas", {class: "pic"}));
    sec.append(el("p", {}, ex.caption),
               el("div", {class: "pics"}, ...["Thalion (Amiga/Falcon)", "STE", "ST"].map(
                 (t, k) => el("figure", {}, el("figcaption", {}, t), cs[k]))));
    pics.push({ex, cs, px: null});
  }
  const views = [];
  for (const v of P.viewers) {
    const box = el("div", {class: "viewer"});
    sec.append(el("p", {}, v.caption), box);
    views.push({v, box, draw: null});
  }
  s.dom = {sec, info, ctl, err, rows, rste, rst, cmp, pics, views};
  new IntersectionObserver((ents, obs) => {
    if (!ents.some(x => x.isIntersecting)) return;
    obs.disconnect();
    load(slug).catch(x => { err.textContent = "This browser cannot show the pictures: " + x; });
  }, {rootMargin: "800px"}).observe(sec);
  return sec;
}

function controls(slug) {
  const s = S[slug], d = s.dom, P = PV.d[slug];
  d.ctl.textContent = "";
  const mbox = el("span", {}, "method: ");
  for (const m of methodsFor(slug)) {
    const r = el("input", {type: "radio", name: "m_" + slug, value: m});
    r.checked = m === s.cur.method;
    r.onchange = () => change(slug, l => { l.method = m; });
    const lab = el("label", {title: D.about[m] || ""}, r, " " + m);
    if (m === D.default) lab.append(el("em", {class: "def"}, "default"));
    if (m === s.file.method) lab.append(el("em", {class: "inf"}, "in file"));
    mbox.append(lab, " ");
  }
  const sel = el("select", {});
  for (let n = RAMP_REGS; n >= 1; n--) {
    const o = el("option", {value: n}, String(n) + (n === RAMP_REGS ? " (default)" : ""));
    o.selected = n === s.cur.ramp;
    sel.append(o);
  }
  sel.onchange = () => change(slug, l => { l.ramp = Number(sel.value); });
  const groups = el("span", {});
  s.cur.own.forEach((g, k) => groups.append(el("span", {class: "grp"},
    String.fromCharCode(65 + k) + ": " + g.join(" "),
    el("button", {title: "dissolve this own register",
                  onclick: () => change(slug, l => { l.own.splice(k, 1); })}, "×"))));
  const make = el("button", {onclick: () => {
    const cs = [...s.sel].sort((a, b) => a - b);
    if (!cs.length) return;
    change(slug, l => {
      l.own = l.own.map(g => g.filter(c => !s.sel.has(c))).filter(g => g.length);
      l.own.push(cs);
    }, () => s.sel.clear());
  }}, "own register from the marked colours");
  make.disabled = !s.sel.size;
  const clear = el("button", {onclick: () => { s.sel.clear(); refresh(slug, false); }}, "unmark");
  clear.disabled = !s.sel.size;
  d.ctl.append(mbox, el("label", {}, "UI registers: ", sel), make, clear,
               el("span", {}, "own registers: "), groups.childNodes.length ? groups : "none");
}

// a change of the lines: refused (and said why) if it leaves no register
function change(slug, edit, after) {
  const s = S[slug], l = copyLines(s.cur);
  edit(l);
  const r = compute(slug, l);
  if (r.error) {
    s.dom.err.textContent = "Not taken: " + r.error + ".";
    refresh(slug, false);
    return;
  }
  s.cur = l;
  s.dom.err.textContent = "";
  if (after) after();
  refresh(slug, true);
  update();
}

function coloursOf(slug, r) {
  const P = PV.d[slug];
  const out = {Thalion: P.pal.map(amiga)};
  if (r && !r.error) {
    out.STE = r.tab.map(t => amiga(r.ste[t]));
    out.ST = r.tab.map(t => stRgb(r.st[t]));
  } else out.STE = out.ST = out.Thalion.map(() => [0, 0, 0]);
  return out;
}

function refresh(slug, pictures) {
  const s = S[slug], d = s.dom, P = PV.d[slug];
  const r = compute(slug, s.cur);
  s.result = r;
  controls(slug);
  if (r.error) d.err.textContent = "These lines cannot be built: " + r.error + ".";
  const cs = coloursOf(slug, r);
  const ownOf = {};
  s.cur.own.forEach((g, k) => g.forEach(c => { ownOf[c] = k; }));
  const nui = r.error ? 0 : new Set(r.tab.slice(RAMP0)).size;
  const ownRegs = new Set(r.error ? [] : s.cur.own.map((g, k) => nui + k + 1));
  for (let i = 0; i < 32; i++) {
    const t = d.rows.thal.children[i + 1];
    t.style.background = css(cs.Thalion[i]);
    t.classList.toggle("sel", s.sel.has(i));
    const w = P.pal[i] & 0xFFF;
    const k = Object.keys(ownOf).find(c => (P.pal[c] & 0xFFF) === w && i < RAMP0);
    t.textContent = k !== undefined ? String.fromCharCode(65 + ownOf[k]) : "";
    t.title = "colour " + i + " $" + hex3(w) + (i >= RAMP0 ? ": Thalion's UI ramp" : ": click to mark");
    d.rows.ste.children[i + 1].style.background = css(cs.STE[i]);
    d.rows.st.children[i + 1].style.background = css(cs.ST[i]);
    const g = d.rows.reg.children[i + 1];
    g.textContent = r.error ? "" : String(r.tab[i]);
    g.className = (s.hand.colours[i] !== undefined ? "hand" : "") + (ownRegs.has(r.tab && r.tab[i]) ? " own" : "");
  }
  for (let reg = 1; reg < 16; reg++) {
    const a = d.rste.children[reg], b = d.rst.children[reg];
    a.textContent = r.error ? "" : hex3(r.ste[reg]);
    b.textContent = r.error ? "" : hex3(r.st[reg]);
    const kind = r.error ? "" : reg <= nui ? "uireg" : ownRegs.has(reg) ? "own" : "";
    a.className = (s.hand.ste[reg] !== undefined ? "hand " : "") + kind;
    b.className = (s.hand.st[reg] !== undefined ? "hand " : "") + kind;
  }
  d.info.textContent = r.error ? "" :
    (r.weighted ? "weighted by the counted points" : "unweighted") + "; registers: " + nui +
    " UI, " + s.cur.own.length + " own, " + (new Set(r.tab.slice(1)).size - nui - s.cur.own.length) +
    " by the method" + (sameLines(s.cur, s.file) ? "; as in the file" : "; changed against the file");
  // all methods
  d.cmp.textContent = "";
  for (const m of methodsFor(slug)) {
    const x = compute(slug, {method: m, ramp: s.cur.ramp, own: s.cur.own});
    const c = coloursOf(slug, x);
    for (const k of ["STE", "ST"]) {
      const tr = el("tr", {}, el("th", {}, k + " " + m + (m === s.cur.method ? " (chosen)" : "")));
      for (let i = 0; i < 32; i++) {
        const td = el("td");
        td.style.background = css(c[k][i]);
        tr.append(td);
      }
      if (x.error) tr.append(el("td", {class: "err"}, x.error));
      d.cmp.append(tr);
    }
  }
  if (pictures) paintAll(slug);
}

// ---- pictures
async function inflate(b64) {
  const bin = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
  const st = new Blob([bin]).stream().pipeThrough(new DecompressionStream("deflate"));
  return new Uint8Array(await new Response(st).arrayBuffer());
}
function paint(cv, idx, w, h, rgb) {
  cv.width = w; cv.height = h;
  const ctx = cv.getContext("2d"), im = ctx.createImageData(w, h), p = im.data;
  for (let i = 0, j = 0; i < w * h; i++, j += 4) {
    const c = rgb[idx[i] & 31];
    p[j] = c[0]; p[j + 1] = c[1]; p[j + 2] = c[2]; p[j + 3] = 255;
  }
  ctx.putImageData(im, 0, 0);
}
async function load(slug) {
  const d = S[slug].dom;
  for (const p of d.pics) p.px = await inflate(p.ex.px);
  for (const v of d.views) v.draw = await viewer(slug, v);
  S[slug].loaded = true;
  paintAll(slug);
}
function paintAll(slug) {
  const s = S[slug];
  if (!s.loaded) return;
  const cs = coloursOf(slug, s.result);
  for (const p of s.dom.pics)
    ["Thalion", "STE", "ST"].forEach((k, j) => paint(p.cs[j], p.px, p.ex.w, p.ex.h, cs[k]));
  for (const v of s.dom.views) v.draw(cs);
}
async function viewer(slug, view) {
  const v = view.v, el0 = view.box;
  const bar = el("div", {class: "vbar"});
  let current = "ST", last = null, draw;
  for (const name of ["Thalion", "STE", "ST"]) {
    const b = el("button", {onclick: () => { current = name; draw(last); }}, name);
    b.dataset.name = name;
    bar.append(b);
  }
  const box = el("div", {class: "vbox"});
  el0.append(bar, box);
  const mark = () => { for (const b of bar.children) b.classList.toggle("on", b.dataset.name === current); };
  if (v.kind === "pixels") {
    const px = await inflate(v.pixels);
    const cv = el("canvas");
    box.append(cv);
    draw = cs => { last = cs; mark(); paint(cv, px, v.w, v.h, cs[current]); };
    return draw;
  }
  const [tiles, under, over, ov] = await Promise.all([v.tiles, v.under, v.over, v.overview].map(inflate));
  const du = new DataView(under.buffer), dov = new DataView(over.buffer);
  const W = v.w, H = v.h, DW = v.detail[0], DH = v.detail[1];
  const cut = new Uint8Array(DW * 16 * DH * 16);
  let cx = W >> 1, cy = H >> 1;
  const ovc = el("canvas", {title: "click: the cut at full size"});
  box.append(ovc);
  const info = el("p", {class: "use"}), det = el("canvas", {class: "detail"});
  el0.append(info, det);
  draw = cs => {
    last = cs;
    mark();
    const rgb = cs[current];
    const X = Math.max(0, Math.min(W - DW, cx - (DW >> 1)));
    const Y = Math.max(0, Math.min(H - DH, cy - (DH >> 1)));
    paint(ovc, ov, 2 * W, 2 * H, rgb);
    const ctx = ovc.getContext("2d");
    ctx.strokeStyle = "#fff"; ctx.lineWidth = 2;
    ctx.strokeRect(2 * X, 2 * Y, 2 * DW, 2 * DH);
    for (let ty = 0; ty < DH; ty++)
      for (let tx = 0; tx < DW; tx++) {
        const o = ((Y + ty) * W + X + tx) * 2, u = du.getUint16(o), a = dov.getUint16(o);
        for (let y = 0; y < 16; y++)
          for (let x = 0; x < 16; x++) {
            let c = tiles[u * 256 + y * 16 + x];
            if (a) { const dd = tiles[a * 256 + y * 16 + x]; if (dd) c = dd; }
            cut[(ty * 16 + y) * DW * 16 + tx * 16 + x] = c;
          }
      }
    paint(det, cut, DW * 16, DH * 16, rgb);
    const mx = Math.floor((X + (DW >> 1)) / v.mw), my = Math.floor((Y + (DH >> 1)) / v.mh);
    const m = v.maps.find(t => t[1] === mx && t[2] === my);
    info.textContent = "cut at full size: squares " + X + "-" + (X + DW - 1) + " x " + Y +
      "-" + (Y + DH - 1) + (m ? ", around map " + m[0] : "") + "; " + current;
  };
  ovc.onclick = ev => {
    const r = ovc.getBoundingClientRect();
    cx = Math.floor((ev.clientX - r.left) * W / r.width);
    cy = Math.floor((ev.clientY - r.top) * H / r.height);
    draw(last);
  };
  return draw;
}

// ---- the file
function applyFile(name, when, text) {
  const f = STG.readFile(text);
  keepText = f.keep;
  const known = new Set();
  for (const slug of D.palettes) {
    const P = PV.d[slug], x = fromFile(P, f);
    P.names.forEach(n => known.add(n));
    S[slug] = Object.assign(S[slug] || {sel: new Set()},
                            {name: x.name, notes: x.notes, hand: x.hand, file: x.lines, cur: copyLines(x.lines)});
    if (!methods.includes(x.lines.method)) methods.push(x.lines.method);
  }
  others = [];
  for (const [n, e] of Object.entries(f.names))
    if (!known.has(n))
      others.push(...linesOf(n, {method: e.method || D.default, ramp: e.ramp || RAMP_REGS, own: e.own},
                             {method: e.note, ramp: e.rampNote,
                              own: Object.fromEntries(e.own.map((g, k) => [g.join(" "), e.ownNotes[k]]))}));
  fileName = name; fileWhen = when;
  const warn = [];
  if (others.length)
    warn.push("Lines for palettes not on this page, kept as they are: " +
              others.map(l => l.split(/ (method|ramp|own) /)[0]).join(", ") + ".");
  if (f.bad.length) warn.push("Unreadable lines, kept as they are: line " + f.bad.join(", ") + ".");
  const st = document.getElementById("state");
  st.className = warn.length ? "warn" : "";
  st.textContent = "File: " + fileName + " (" + fileWhen + ")." + (warn.length ? " " + warn.join(" ") : "");
}
function update() {
  const l = allLines();
  document.getElementById("lines").value = l.join("\n");
  const changed = D.palettes.filter(slug => !sameLines(S[slug].cur, S[slug].file)).length;
  document.getElementById("count").textContent = l.length + " lines (method, ramp, own), " +
    changed + " palettes changed against the file";
}
function refreshAll() { for (const slug of D.palettes) if (S[slug].dom) refresh(slug, true); update(); }
function wholeFile() {
  let t = keepText.replace(/\n*$/, "\n");
  const l = allLines();
  if (l.length && !/^# Methods/m.test(t))
    t += "\n# Methods (default " + D.default + "), UI and own registers, chosen in the palette editor\n";
  if (l.length) t += l.join("\n") + "\n";
  return t;
}
document.getElementById("open").onclick = () => document.getElementById("pick").click();
document.getElementById("pick").onchange = e => {
  const file = e.target.files[0];
  if (!file) return;
  const when = new Date(file.lastModified), pad = n => String(n).padStart(2, "0");
  const stamp = when.getFullYear() + "-" + pad(when.getMonth() + 1) + "-" + pad(when.getDate()) +
                " " + pad(when.getHours()) + ":" + pad(when.getMinutes());
  file.text().then(t => { applyFile(file.name + ", opened", stamp, t); refreshAll(); });
  e.target.value = "";
};
document.getElementById("asfile").onclick = () => {
  for (const slug of D.palettes) { S[slug].cur = copyLines(S[slug].file); S[slug].sel.clear(); }
  refreshAll();
};
document.getElementById("todefault").onclick = () => {
  for (const slug of D.palettes) { S[slug].cur = {method: D.default, ramp: RAMP_REGS, own: []}; S[slug].sel.clear(); }
  refreshAll();
};
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
document.getElementById("checked").textContent = D.checked;
applyFile(D.file, D.when, D.text);
const parts = document.getElementById("parts"), index = document.getElementById("index");
for (const slug of D.palettes) {
  index.append(el("a", {href: "#" + slug}, PV.d[slug].names[0]), " ");
  parts.append(build(slug));
  refresh(slug, false);
}
update();
</script>
</body></html>
"""


def main():
    p = argparse.ArgumentParser(description=__doc__.strip().split("\n")[0])
    p.add_argument("names", nargs="*", help='e.g. "pal 12" "combat 39" main')
    p.add_argument("--file", default=stp.CORRECTIONS,
                   help="the st_palettes.txt to start from (default: this checkout's)")
    p.add_argument("-o", default=OUT_DIR, help="output folder (default %(default)s)")
    a = p.parse_args()
    if not os.path.exists(a.file):
        raise SystemExit("palette_sheet: %s does not exist" % a.file)
    game = stp.Game(maps=True)
    print(write_page(game, stp.Corrections(a.file), a.names, a.o))


if __name__ == "__main__":
    main()

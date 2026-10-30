#!/usr/bin/env python3
"""
palette_sheet.py -- the palette editor: choose the ST method per palette

Writes a page build/palette_editor/index.html.  For every palette of the
game it shows Thalion's colours, then the STE and the ST result of each
method next to pictures from the game, with a button per method.  The page
writes the method lines of tools/st_palettes.txt (ST's file, format in its
head) and offers the whole file to download.

The methods (computed by tools/st_palettes.py, which this tool imports for
everything it shows):

  unweighted    St_bauen as at run time: all 32 colours count the same;
                the default, without a method line
  weighted N    by how many points of each colour the game shows with the
                palette, every colour at least N %; good for the worlds
                (Lyramion: sea blue instead of grey)

The page starts from the file the build read (default tools/st_palettes.txt
of this checkout; --file another).  "Open st_palettes.txt" on the page reads
a newer one and sets the buttons from it, without a new build.  The pictures
always show the hand corrections of the file the build read; the page says
when an opened file has others.

The page contains Thalion's graphics and colours: it stays in build/, never
into the repository or a published page.  Needs Pillow.

Usage:  palette_sheet.py [NAME ...] [--file FILE] [-o DIR]
        NAME as in st_palettes.txt ("pal 12", "combat 39", "main"); none = all
"""
import argparse
import datetime
import html
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import farbreduktion                                    # noqa: E402
import st_palettes as stp                               # noqa: E402

OUT_DIR = "build/palette_editor"

# What each method does, in the legend and as the tooltip of its button.
ABOUT = {
    "unweighted": "St_bauen as the ST computes it at run time: all 32 colours "
                  "count the same, so rare accents keep a register of their "
                  "own (the fire in Grandfather's house stays red).",
    "weighted": "Grouped by how many points of each colour the game shows "
                "with this palette (2D maps, event pictures, combat "
                "backgrounds); large areas get the closer colours (Lyramion: "
                "sea blue instead of grey, the greens apart).  Every colour "
                "counts as at least %d %% of the points; the higher this "
                "floor, the more rare colours (lights, edges) keep their own "
                "register, the closer to unweighted.",
}
SHORT = {"unweighted": "all colours equal",
         "weighted": "by area, every colour at least %d %%"}


def about(m):
    if m == "unweighted":
        return ABOUT[m]
    return ABOUT["weighted"] % int(m.split()[1])


def short(m):
    if m == "unweighted":
        return SHORT[m]
    return SHORT["weighted"] % int(m.split()[1])


def offered(corr):
    """The sheet's methods, and any other the file names (e.g. weighted 5),
    so that a palette always shows the method it has."""
    extra = sorted(set(corr.methods.values()) - set(stp.SHEET_METHODS),
                   key=lambda m: stp.method_floor(m) or 0)
    return tuple(stp.SHEET_METHODS) + tuple(extra)


def write_page(game, corr, names=(), out=OUT_DIR):
    d = game.d
    d.layouts = farbreduktion.lade("Layouts.amb")
    es = stp.entries(game, corr)
    methods_all = offered(corr)
    variants = {m: stp.entries(game, corr, m) for m in methods_all}
    picked = list(range(len(es)))
    if names:
        want = set(names)
        picked = [k for k in picked if want & set(es[k].names)]
        if not picked:
            raise SystemExit("palette_sheet: no palette called %s" % ", ".join(names))
    os.makedirs(out, exist_ok=True)
    parts, choices = [], []
    for k in picked:
        e = es[k]
        sl = stp.slug(e.names)
        # a method can be chosen where the game's pictures were counted
        methods = methods_all if sum(e.counts.values()) else ()
        name = next((n for n in e.names if n in corr.methods), e.names[0])
        if methods:
            choices.append({"slug": sl, "name": name, "names": e.names,
                            "method": e.method, "note": corr.notes.get(name, "")})
        thalion, _, _ = stp.colours_of(e)
        rows = ["<h2 id='%s'>%s</h2>" % (sl, html.escape(" = ".join(e.names)))]
        if methods:
            rows.append("<p class=use>in the file: <b id='file_%s'>%s</b> &middot; "
                        "default: <b>%s</b></p>" % (sl, e.method, stp.DEFAULT_METHOD))
        else:
            rows.append("<p class=use>no pictures counted, so only %s</p>" % e.method)
        uses = [u for n in e.names for u in game.usage.get(n, [])]
        if uses:
            rows.append("<p class=use>%s</p>" % html.escape(
                "; ".join(uses[:12]) + (" ..." if len(uses) > 12 else "")))
        rows.append("<table class=pal><tr><th>colour</th>%s</tr>" %
                    "".join("<td>%d</td>" % i for i in range(32)))
        rows.append(stp.strip("Thalion", thalion))
        for m in methods or (e.method,):
            v = variants[m][k] if methods else e
            _, vste, vst = stp.colours_of(v)
            rows.append(stp.strip("STE %s" % m, vste))
            rows.append(stp.strip("ST %s" % m, vst))
        rows.append("<tr><th>register (%s)</th>%s</tr></table>" % (e.method, "".join(
            "<td%s>%d</td>" % (" class=hand" if i in e.hand_colours else "", e.tab[i])
            for i in range(32))))
        rows.append("<table class=reg><tr><th>register (%s)</th>%s</tr>" %
                    (e.method, "".join("<td>%d</td>" % r for r in range(1, 16))))
        rows.append("<tr><th>STE</th>%s</tr>" % "".join(
            "<td%s>%s</td>" % (" class=hand" if r in e.hand_ste else "", stp.hex3(e.ste[r]))
            for r in range(1, 16)))
        rows.append("<tr><th>ST</th>%s</tr></table>" % "".join(
            "<td%s>%s</td>" % (" class=hand" if r in e.hand_st else "", stp.hex3(e.st[r]))
            for r in range(1, 16)))
        for j, (caption, pic, w, h) in enumerate(stp.examples(game, d, e)):
            name0 = "%s_%d_Thalion.png" % (sl, j)
            stp.save_png(pic, w, h, thalion, os.path.join(out, name0))
            cols = ["<figure class=col><figcaption>Thalion (Amiga/Falcon)</figcaption>"
                    "<img src='%s'></figure>" % name0]
            for m in methods or (e.method,):
                v = variants[m][k] if methods else e
                _, vste, vst = stp.colours_of(v)
                imgs = []
                for title, cs in (("STE", vste), ("ST", vst)):
                    fn = "%s_%d_%s_%s.png" % (sl, j, m.replace(" ", ""), title)
                    stp.save_png(pic, w, h, cs, os.path.join(out, fn))
                    imgs.append("<img src='%s' title='%s'>" % (fn, title))
                badge = " <em class=def>default</em>" if m == stp.DEFAULT_METHOD else ""
                if methods:
                    head = ("<label title='%s'><input type=radio name='%s' value='%s'%s> "
                            "%s</label>%s <em class=inf data-slug='%s' data-method='%s'>"
                            "in file</em>"
                            % (html.escape(about(m), quote=True), sl, m,
                               " checked" if m == e.method else "", m, badge, sl, m))
                else:
                    head = m + badge
                cols.append("<figure class='col m' data-slug='%s' data-method='%s'>"
                            "<figcaption>%s <span>STE above, ST below</span>"
                            "<br><small>%s</small></figcaption>%s</figure>"
                            % (sl, m, head, short(m), "".join(imgs)))
            rows.append("<p>%s</p><div class=pics>%s</div>"
                        % (html.escape(caption), "".join(cols)))
        parts.append("<section>%s</section>" % "\n".join(rows))
    index = "".join("<a href='#%s'>%s</a> " % (stp.slug(es[k].names),
                                                html.escape(es[k].names[0]))
                    for k in picked)
    legend = "".join("<dt>%s%s</dt><dd>%s</dd>" % (
        m, " <em class=def>default</em>" if m == stp.DEFAULT_METHOD else "", about(m))
        for m in methods_all)
    when = datetime.datetime.fromtimestamp(os.path.getmtime(corr.path)) \
        if os.path.exists(corr.path) else None
    data = json.dumps({
        "default": stp.DEFAULT_METHOD, "methods": list(methods_all),
        "choices": choices, "lines": "".join(corr.lines),
        "file": os.path.relpath(corr.path),
        "when": when.strftime("%Y-%m-%d %H:%M") if when else "missing"})
    page = PAGE.replace("@LEGEND@", legend).replace("@INDEX@", index) \
               .replace("@PARTS@", "\n".join(parts)) \
               .replace("@DATA@", data.replace("</", "<\\/"))
    path = os.path.join(out, "index.html")
    with open(path, "w") as f:
        f.write(page)
    return path


PAGE = """<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1">
<title>Palette editor</title><style>
body{font:14px sans-serif;background:#222;color:#ddd;margin:16px;padding-bottom:240px}
a{color:#9cf;margin-right:6px}
table{border-collapse:collapse;margin:6px 0}
td,th{border:1px solid #444;padding:2px 4px;font:12px monospace;text-align:center}
th{text-align:left;white-space:nowrap}
table.pal td{width:18px;height:18px}
.hand{background:#753 !important}
.use{color:#aaa}
dl{margin:6px 0 12px}dt{font-weight:bold;margin-top:6px}dd{margin:2px 0 0 20px;color:#bbb}
em{font-style:normal;font-size:11px;padding:0 4px;border-radius:3px;margin-left:4px}
em.def{background:#346;color:#cdf}
em.inf{background:#552;color:#ffc;display:none}
em.inf.on{display:inline}
.pics{display:flex;gap:8px;flex-wrap:wrap;align-items:flex-start}
figure{margin:0}figcaption{font-size:13px;margin-bottom:3px}
figcaption span{color:#888;font-size:11px}
figcaption small{color:#999;font-size:11px}
.col{padding:4px;border:2px solid transparent;border-radius:4px}
.col.on{border-color:#6c6;background:#2c3a2c}
img{display:block;image-rendering:pixelated;width:320px;max-width:100%;margin-bottom:3px}
label{cursor:pointer;font-weight:bold}
section{border-top:1px solid #555;margin-top:16px}
#state{padding:6px 8px;background:#2a2a2a;border-left:3px solid #6c6}
#state.warn{border-left-color:#c84}
#out{position:fixed;left:0;right:0;bottom:0;background:#333;border-top:2px solid #6c6;
 padding:8px 16px;display:flex;gap:12px;align-items:flex-start;flex-wrap:wrap}
#out textarea{flex:1;min-width:200px;height:160px;font:12px monospace;background:#111;
 color:#dfd;border:1px solid #555}
#out div{display:flex;flex-direction:column;gap:6px;width:230px}
button{font:13px sans-serif;padding:4px 8px}
</style></head><body>
<h1>Palette editor</h1>
<p>Choose how each palette of the ST is grouped from Thalion's 32 colours
onto 16 registers.  Built from the original files by
tools/palette_editor/palette_sheet.py; contains Thalion's graphics and
colours, so it stays in build/, never into the repository or a published
page.  Brown cells are set by hand in st_palettes.txt.</p>
<dl>@LEGEND@</dl>
<p>Each palette shows its method <b>in the file</b> preselected; a palette
without a method line has the <b>default</b>.  Only palettes whose pictures
the build counts can be weighted.  The box at the bottom holds the method
lines that differ from the default; "Download" gives the whole
st_palettes.txt with them.  Put it into tools/st_palettes.txt and build
again (tools/build_st.sh).</p>
<p id=state></p>
<p>@INDEX@</p>
@PARTS@
<div id=out><textarea id=lines readonly></textarea><div>
<span id=count></span>
<button id=open>Open st_palettes.txt</button>
<input id=pick type=file accept=".txt,text/plain" hidden>
<button id=asfile>As in the file</button>
<button id=todefault>All to default</button>
<button id=copy>Copy method lines</button>
<button id=save>Download st_palettes.txt</button></div></div>
<script>
const D = @DATA@;
const builtLines = D.lines;
let fileName = D.file, fileWhen = D.when, others = [];

function chosen(c) {
  const r = document.querySelector("input[name='" + c.slug + "']:checked");
  return r ? r.value : c.method;
}
function setRadios(get) {
  for (const c of D.choices)
    for (const r of document.querySelectorAll("input[name='" + c.slug + "']"))
      r.checked = r.value === get(c);
}
function methodLine(name, m, note) {
  return ((name + " method " + m).padEnd(28) + " " + (note ? "# " + note : "")).trimEnd();
}
function methodLines() {
  return D.choices.filter(c => chosen(c) !== D.default)
                  .map(c => methodLine(c.name, chosen(c), c.note)).concat(others);
}
function update() {
  for (const f of document.querySelectorAll(".col.m"))
    f.classList.toggle("on", chosen({slug: f.dataset.slug, method: ""}) === f.dataset.method);
  for (const b of document.querySelectorAll("em.inf")) {
    const c = D.choices.find(c => c.slug === b.dataset.slug);
    b.classList.toggle("on", !!c && c.method === b.dataset.method);
  }
  const l = methodLines();
  document.getElementById("lines").value = l.join("\\n");
  const changed = D.choices.filter(c => chosen(c) !== c.method).length;
  document.getElementById("count").textContent = l.length + " method lines (default " +
    D.default + "), " + changed + " changed against the file";
}
function showState(warn) {
  const s = document.getElementById("state");
  s.className = warn ? "warn" : "";
  s.textContent = "File: " + fileName + " (" + fileWhen + ")." + (warn ? " " + warn : "");
}
// The method key as st_palettes.py's method_key: "unweighted" or "weighted N".
function methodKey(w) {
  if (w.length === 1 && w[0] === "unweighted") return "unweighted";
  if (w.length >= 1 && w.length <= 2 && w[0] === "weighted") {
    const n = w.length === 2 ? Number(w[1]) : 1;
    if (Number.isInteger(n) && n >= 1 && n <= 20) return "weighted " + n;
  }
  return null;
}
// Reads a st_palettes.txt like st_palettes.py's Corrections: the method lines
// set the buttons, everything else is kept for the download.
function readFile(text) {
  const keep = [], methods = {}, notes = {}, bad = [];
  text.replace(/\\r\\n/g, "\\n").split(/^/m).forEach((line, i) => {
    const t = line.split("#")[0].trim().split(/\\s+/).filter(Boolean);
    let name = null, rest = t;
    if (t.length && (t[0] === "pal" || t[0] === "combat")) {
      name = t[0] + " " + parseInt(t[1], 10); rest = t.slice(2);
    } else if (t.length) { name = t[0]; rest = t.slice(1); }
    if (!rest.length || rest[0] !== "method") { keep.push(line); return; }
    const m = methodKey(rest.slice(1));
    if (!m) { bad.push(i + 1); keep.push(line); return; }
    methods[name] = m;
    if (line.includes("#")) notes[name] = line.split("#").slice(1).join("#").trim();
  });
  return {keep: keep.join(""), methods, notes, bad};
}
function applyFile(name, when, text) {
  const f = readFile(text);
  const known = new Set();
  for (const c of D.choices) {
    const n = c.names.find(n => n in f.methods);
    c.name = n || c.name;
    c.method = n ? f.methods[n] : D.default;
    c.note = n ? (f.notes[n] || "") : "";
    c.names.forEach(n => known.add(n));
  }
  others = Object.keys(f.methods).filter(n => !known.has(n))
                 .map(n => methodLine(n, f.methods[n], f.notes[n]));
  setRadios(c => c.method);
  D.lines = f.keep;
  fileName = name; fileWhen = when;
  const warn = [];
  if (f.keep !== builtLines)
    warn.push("Its hand corrections differ from the file the build read: the " +
              "pictures and tables do not show them, build again to see them.");
  const odd = D.choices.filter(c => !D.methods.includes(c.method)).map(c => c.name);
  if (odd.length)
    warn.push("Methods this page has no pictures for: " + odd.join(", ") + ".");
  if (others.length)
    warn.push("Method lines for palettes without counted pictures, kept as they are: " +
              others.map(l => l.split(" method")[0]).join(", ") + ".");
  if (f.bad.length)
    warn.push("Unreadable method lines, kept as they are: line " + f.bad.join(", ") + ".");
  showState(warn.join(" "));
  update();
}
document.addEventListener("change", e => { if (e.target.type === "radio") update(); });
document.getElementById("open").onclick = () => document.getElementById("pick").click();
document.getElementById("pick").onchange = e => {
  const file = e.target.files[0];
  if (!file) return;
  const when = new Date(file.lastModified);
  const pad = n => String(n).padStart(2, "0");
  const stamp = when.getFullYear() + "-" + pad(when.getMonth() + 1) + "-" +
                pad(when.getDate()) + " " + pad(when.getHours()) + ":" + pad(when.getMinutes());
  file.text().then(t => applyFile(file.name + ", opened", stamp, t));
  e.target.value = "";
};
document.getElementById("asfile").onclick = () => { setRadios(c => c.method); update(); };
document.getElementById("todefault").onclick = () => { setRadios(c => D.default); update(); };
function wholeFile() {
  let t = D.lines.replace(/\\n*$/, "\\n");
  const l = methodLines();
  if (l.length && !/^# Methods/m.test(t))
    t += "\\n# Methods (default " + D.default + "), chosen in the palette editor\\n";
  if (l.length) t += l.join("\\n") + "\\n";
  return t;
}
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
showState("");
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

// st_group.js -- the ST grouping of tools/st_palettes.py in the browser
//
// The palette editor (palette_sheet.py) inlines this file into its page, so
// that a click recomputes a palette at once; palette_sheet.py also runs it
// through node against st_palettes.py for every palette and method and stops
// on the first difference (check_js).  So whoever changes the grouping in
// st_palettes.py changes it here the same way, step by step: the same order
// of sums, the same ties (the first wins), Python's round() (half to even),
// integer arithmetic where Python has it, and py_sum (CPython's sum():
// integers exactly until the first float, then compensated), for which a
// value has to say whether Python holds it as a float (p.countsFloat).  The
// OKLab points come from st_palettes.py (p.ok), so no pow() of two
// languages has to agree.
//
// Also reads tools/st_palettes.txt like st_palettes.py's Corrections.
"use strict";
const STG = (() => {
  const RAMP0 = 26, RAMP_REGS = 5, PENALTY = 1, DEFAULT_METHOD = "unweighted";

  const quarter = w => [((w >> 8) & 15) * 4, ((w >> 4) & 15) * 4, (w & 15) * 4];
  // Python's round(): half to even
  function pyRound(x) {
    const f = Math.floor(x), d = x - f;
    if (d > 0.5) return f + 1;
    if (d < 0.5) return f;
    return f % 2 === 0 ? f : f + 1;
  }
  const floorDiv = (a, b) => Math.floor(a / b);
  // py_sum of st_palettes.py; items [[value, is a Python float]]
  function pySum(items) {
    let total = 0, k = 0;
    for (; k < items.length && !items[k][1]; k++) total += items[k][0];
    if (k === items.length) return total;
    let hi = total + items[k][0], lo = 0;
    for (k++; k < items.length; k++) {
      const x = items[k][0], t = hi + x;
      if (Math.abs(hi) >= Math.abs(x)) lo += (hi - t) + x;
      else lo += (x - t) + hi;
      hi = t;
    }
    return lo && isFinite(lo) ? hi + lo : hi;
  }

  // p.point(w): the point of a colour value in the method's space
  function distance(p, w, m) {
    const a = p.point(w);
    if (p.rgb) return (a[0] - m[0]) ** 2 + (a[1] - m[1]) ** 2 + (a[2] - m[2]) ** 2;
    return pySum([0, 1, 2].map(k => [(a[k] - m[k]) ** 2, true]));
  }
  function nearest(p, w, centres, nfixed, penalty) {
    let bd = null, bj = 0;
    for (let j = 0; j < centres.length; j++) {
      const d = distance(p, w, centres[j]) * (1 << (j < nfixed ? penalty : 0));
      if (bd === null || d < bd) { bd = d; bj = j; }
    }
    return [bd, bj];
  }
  function kmeans(p, points, n, fixed, penalty) {
    fixed = fixed.slice();
    if (points.length <= n) return fixed.concat(points.map(w => p.point(w)));
    const centres = fixed.slice();
    if (!centres.length) centres.push(p.point(points[0]));
    while (centres.length < fixed.length + n) {
      let bd = -1, bp = 0;
      for (const w of points) {
        const d = nearest(p, w, centres, fixed.length, penalty)[0];
        if (d > bd) { bd = d; bp = w; }
      }
      centres.push(p.point(bp));
    }
    for (let round = 0; round < 8; round++) {
      const total = centres.map(() => [0, 0, 0, 0]);
      for (const w of points) {
        const j = nearest(p, w, centres, fixed.length, penalty)[1], q = p.point(w);
        for (let k = 0; k < 3; k++) total[j][k] += q[k];
        total[j][3] += 1;
      }
      for (let j = fixed.length; j < centres.length; j++) {
        const a = total[j][3];
        if (a && p.rgb) centres[j] = [0, 1, 2].map(k => floorDiv(total[j][k] + floorDiv(a, 2), a));
        else if (a) centres[j] = [0, 1, 2].map(k => total[j][k] / a);
      }
    }
    return centres;
  }
  function wkmeans(p, points, weights, n, fixed, penalty) {
    fixed = fixed.slice();
    if (points.length <= n) return fixed.concat(points.map(w => p.point(w)));
    const first = arr => {           // max(points, key=...): the first maximum
      let best = null, bw = 0;
      for (const w of points) { const v = arr(w); if (best === null || v > best) { best = v; bw = w; } }
      return bw;
    };
    const centres = fixed.length ? fixed.slice() : [p.point(first(w => weights.get(w)))];
    while (centres.length < fixed.length + n)
      centres.push(p.point(first(w => nearest(p, w, centres, fixed.length, penalty)[0] * weights.get(w))));
    for (let round = 0; round < 20; round++) {
      const total = centres.map(() => [0, 0, 0, 0]);
      for (const w of points) {
        const j = nearest(p, w, centres, fixed.length, penalty)[1], q = p.point(w);
        for (let k = 0; k < 3; k++) total[j][k] += q[k] * weights.get(w);
        total[j][3] += weights.get(w);
      }
      for (let j = fixed.length; j < centres.length; j++) {
        const a = total[j][3];
        if (a && p.rgb) centres[j] = [0, 1, 2].map(k => pyRound(total[j][k] / a));
        else if (a) centres[j] = [0, 1, 2].map(k => total[j][k] / a);
      }
    }
    return centres;
  }
  const rounded = cs => cs.map(m => m.map(c => Math.min(15, floorDiv(c + 2, 4)) * 4));

  // {w: weight per colour, f: is it a Python float} or null
  function floored(counts, isFloat, floor) {
    const items = [];
    for (let i = 1; i < 32; i++) items.push([counts[i] || 0, !!isFloat[i]]);
    const total = pySum(items);
    if (!total) return null;
    const w = [], f = [];
    for (let i = 0; i < 32; i++) {
      const c = counts[i] || 0, m = floor * total;
      if (m > c) { w.push(m); f.push(true); } else { w.push(c); f.push(!!isFloat[i]); }
    }
    return {w, f};
  }
  function registers(pal, tab, counts, weights) {
    const regs = [pal[0] & 0xFFF];
    for (let r = 1; r < 16; r++) {
      const g = [];
      for (let i = 1; i < 32; i++) if (tab[i] === r && counts(i, r)) g.push(i);
      if (!g.length) { regs.push(0); continue; }
      let v = 0;
      for (const s of [8, 4, 0]) {
        if (weights === null) {
          const a = g.length;
          let t = 0;
          for (const i of g) t += (pal[i] >> s) & 15;
          v = (v << 4) | floorDiv(t + floorDiv(a, 2), a);
        } else {
          const a = pySum(g.map(i => [weights.w[i], weights.f[i]]));
          const t = pySum(g.map(i => [((pal[i] >> s) & 15) * weights.w[i], weights.f[i]]));
          v = (v << 4) | Math.min(15, Math.floor(t / a + 0.5));
        }
      }
      regs.push(v);
    }
    return regs;
  }
  function rampRegisters(pal, tab, weights) {
    const mask = new Set();
    for (let i = RAMP0; i < 32; i++) mask.add(tab[i]);
    return registers(pal, tab, (i, r) => !mask.has(r) || i >= RAMP0, weights);
  }
  function unique(pal, from, to, without) {
    const out = [];
    for (let i = from; i < to; i++) {
      const w = pal[i] & 0xFFF;
      if (!out.includes(w) && !without.includes(w)) out.push(w);
    }
    return out;
  }

  // st_ramp of st_palettes.py; p = {pal, ok}, returns {tab} or {error}
  function stRamp(p, k, weights, space, own) {
    const pal = p.pal, ok = new Map();
    for (let i = 0; i < 32; i++) ok.set(pal[i] & 0xFFF, p.ok[i]);
    const sp = space === "rgb" ? {rgb: true, point: quarter} : {rgb: false, point: w => ok.get(w)};
    const keep = sp.rgb ? rounded : cs => cs;
    const ramp = unique(pal, RAMP0, 32, []);
    const rm = keep(kmeans(sp, ramp, Math.min(k, ramp.length), [], 0));
    const groupOf = new Map();
    own.forEach((cs, g) => cs.forEach(c => groupOf.set(pal[c] & 0xFFF, g)));
    const rest = unique(pal, 1, RAMP0, ramp.concat([...groupOf.keys()]));
    const n = 15 - rm.length - own.length;
    if (n < 0 || (rest.length && n < 1))
      return {error: rm.length + " ramp registers and " + own.length +
                     " own groups leave no register for the other colours"};
    let centres;
    if (weights === null) centres = keep(kmeans(sp, rest, n, rm, PENALTY));
    else {
      const wv = new Map();
      for (let i = 1; i < RAMP0; i++) {
        const w = pal[i] & 0xFFF;
        wv.set(w, (wv.get(w) || 0) + weights.w[i]);
      }
      centres = keep(wkmeans(sp, rest, wv, n, rm, PENALTY));
    }
    const tab = [0];
    for (let i = 1; i < 32; i++) {
      const w = pal[i] & 0xFFF;
      if (i < RAMP0 && groupOf.has(w)) tab.push(rm.length + groupOf.get(w) + 1);
      else if (ramp.includes(w)) tab.push(nearest(sp, w, rm, 0, 0)[1] + 1);
      else {
        const j = nearest(sp, w, centres, rm.length, PENALTY)[1];
        tab.push(j < rm.length ? j + 1 : j + 1 + own.length);
      }
    }
    return {tab};
  }

  function methodKey(w) {
    let suffix = "";
    if (w.length && w[w.length - 1] === "oklab") { w = w.slice(0, -1); suffix = " oklab"; }
    if (w.length === 1 && w[0] === "unweighted") return "unweighted" + suffix;
    if (w.length >= 1 && w.length <= 2 && w[0] === "weighted") {
      const n = w.length === 2 ? Number(w[1]) : 1;
      if (/^\d+$/.test(w.length === 2 ? w[1] : "1") && n >= 1 && n <= 20)
        return "weighted " + n + suffix;
    }
    return null;
  }
  const methodFloor = m => m.split(" ")[0] === "unweighted" ? null : Number(m.split(" ")[1]) / 100;
  const methodSpace = m => m.endsWith(" oklab") ? "oklab" : "rgb";
  const stFromSte = v => (v >> 1) & 0x777;

  // Entry of st_palettes.py.  p = {pal, ok, counts|null, countsFloat}; c = {method, own,
  // ramp, hand: {colours: {c: r}, ste: {r: v}, st: {r: v}}}
  function compute(p, c) {
    const floor = methodFloor(c.method);
    const weights = floor !== null && p.counts ? floored(p.counts, p.countsFloat, floor) : null;
    const values = [];
    c.own.forEach(g => g.forEach(i => values.push(p.pal[i] & 0xFFF)));
    if (new Set(values).size < values.length)
      return {error: "two own groups hold the same colour value"};
    const r = stRamp(p, c.ramp, weights, methodSpace(c.method), c.own);
    if (r.error) return r;
    const tab = r.tab.slice(), auto = r.tab;
    const hand = c.hand || {colours: {}, ste: {}, st: {}};
    for (const [i, reg] of Object.entries(hand.colours)) tab[i] = reg;
    const mean = rampRegisters(p.pal, tab, weights);
    const ste = mean.slice();
    for (const [reg, v] of Object.entries(hand.ste)) ste[reg] = v;
    const st = ste.map(stFromSte);
    for (const [reg, v] of Object.entries(hand.st)) st[reg] = v;
    const rep = [0];
    for (let reg = 1; reg < 16; reg++) {
      let f = 1;
      for (let i = 1; i < 32; i++) if (tab[i] === reg) { f = i; break; }
      rep.push(f);
    }
    return {tab, auto, mean, ste, st, rep, weighted: weights !== null};
  }

  // Corrections of st_palettes.py: {names: {name: {method, note, own: [[c..]],
  // ownNotes, ramp, rampNote, hand}}, keep: the file without method, own and
  // ramp lines, bad: [line numbers]}
  function readFile(text) {
    const names = {}, keep = [], bad = [];
    const of = n => names[n] || (names[n] = {own: [], ownNotes: [], hand: {colours: {}, ste: {}, st: {}}});
    const isInt = s => /^-?\d+$/.test(s);
    text.replace(/\r\n/g, "\n").split(/^/m).forEach((line, nr) => {
      const t = line.split("#")[0].trim().split(/\s+/).filter(Boolean);
      const note = line.includes("#") ? line.split("#").slice(1).join("#").trim() : "";
      if (!t.length) { keep.push(line); return; }
      let name, rest;
      if (t[0] === "pal" || t[0] === "combat") {
        if (!isInt(t[1] || "")) { bad.push(nr + 1); keep.push(line); return; }
        name = t[0] + " " + parseInt(t[1], 10); rest = t.slice(2);
      } else { name = t[0]; rest = t.slice(1); }
      const e = of(name);
      if (rest[0] === "method") {
        const m = methodKey(rest.slice(1));
        if (!m) { bad.push(nr + 1); keep.push(line); return; }
        e.method = m; e.note = note;
        return;
      }
      if (rest[0] === "own") {
        const cs = rest.slice(1);
        const taken = new Set(e.own.flat());
        const nums = cs.map(Number);
        if (!cs.length || !cs.every(isInt) || new Set(nums).size < nums.length ||
            nums.some(c => taken.has(c) || c < 1 || c >= RAMP0)) {
          bad.push(nr + 1); keep.push(line); return;
        }
        e.own.push(nums); e.ownNotes.push(note);
        return;
      }
      if (rest[0] === "ramp") {
        const n = Number(rest[1]);
        if (rest.length !== 2 || !isInt(rest[1]) || "ramp" in e || n < 1 || n > RAMP_REGS) {
          bad.push(nr + 1); keep.push(line); return;
        }
        e.ramp = n; e.rampNote = note;
        return;
      }
      keep.push(line);
      if (rest.length !== 3) { bad.push(nr + 1); return; }
      const [kind, a, b] = rest;
      if (kind === "colour" && isInt(a) && isInt(b) && +a >= 1 && +a <= 31 && +b >= 1 && +b <= 15)
        e.hand.colours[+a] = +b;
      else if ((kind === "ste" || kind === "st") && isInt(a) && +a >= 1 && +a <= 15 &&
               /^[0-9A-Fa-f]{3}$/.test(b) &&
               (kind === "ste" || [8, 4, 0].every(s => ((parseInt(b, 16) >> s) & 15) <= 7)))
        e.hand[kind][+a] = parseInt(b, 16);
      else bad.push(nr + 1);
    });
    return {names, keep: keep.join(""), bad};
  }

  return {compute, readFile, methodKey, methodFloor, RAMP0, RAMP_REGS, DEFAULT_METHOD, pyRound};
})();
if (typeof module !== "undefined") module.exports = STG;

#!/usr/bin/env python3
"""
farbreduktion.py -- 32 Farben auf 16: wie viel kostet es auf dem ST?

Vorstudie zur ST-Bildschicht (docs/12-ST-Port.md).  Die Bilddaten
bleiben unangetastet; reduziert wird nur die Palette: 16 Ersatzfarben und
eine Tabelle Nummer 0..31 -> Register 0..15.  Das Werkzeug rendert alle
2D-Karten mit ihrer Palette und misst, wie weit die Punkte danach von der
Originalfarbe liegen.

    farbreduktion.py messen [--art palette|wurzel|haeufig]
        je 2D-Karte: Abweichung STE (4 Bit je Kanal) und ST (3 Bit)
    farbreduktion.py bild [--art ...] [-o DATEI]
        Vergleichsbild: drei Kartenausschnitte, je 32 / STE 16 / ST 16

Arten der Reduktion
    palette   nur die 32 Palettenfarben, alle gleich gewichtet.  Braucht
              zur Laufzeit nichts ausser der Palette.
    wurzel    Gewicht = Wurzel der Punkthaeufigkeit auf der Karte.
    haeufig   Gewicht = Punkthaeufigkeit, Start mit den 16 haeufigsten.
              Seltene Akzente (Feuer, Kristalle) gehen dabei verloren.

Die Bilder sind aus Spielgrafik gerechnet und gehoeren nicht ins
Repository; Vorgabe ist build/farbreduktion/ (von git ausgenommen).
"""
import argparse
import collections
import math
import os
import statistics
import struct
import sys
import zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ambmap                                           # noqa: E402
from ambtool import planar_to_indices, unpack           # noqa: E402
import paths  # noqa: E402

AMBERFILES = paths.amberfiles()

# Ausschnitte fuer das Vergleichsbild: Karte, x, y (Punkte)
AUSSCHNITTE = ((525, 240, 300), (286, 160, 100), (455, 0, 20))


def lade(name):
    with open(os.path.join(AMBERFILES, name), "rb") as f:
        return unpack(f.read())[1]


def rgb(w):
    return ((w >> 8) & 15, (w >> 4) & 15, w & 15)


def abstand2(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


class Daten:
    def __init__(self):
        self.paletten = [struct.unpack(">32H", d[:64])
                         for d in lade("Palettes.amb")]
        self.icondata = lade("Icon_data.amb")
        self.gfx = {f: lade(f) for f in ambmap.TILESET_FILES}
        self.karten = {}
        for f in ("1Map_data.amb", "2Map_data.amb", "3Map_data.amb"):
            self.karten.update(ambmap.load_maps(lade(f)))
        self._kacheln = {}

    def kacheln(self, satz):
        if satz not in self._kacheln:
            _, roh = ambmap.find_tileset_gfx(self.gfx, satz)
            self._kacheln[satz] = [
                planar_to_indices(roh[i * 160:(i + 1) * 160], 16, 5)[0]
                for i in range(len(roh) // 160)]
        return self._kacheln[satz]

    def render(self, m):
        """Ganze 2D-Karte -> Farbnummern; Ueberlage mit 0 durchsichtig."""
        defs = ambmap.parse_tileset(self.icondata[m["tileset"] - 1])
        kacheln = self.kacheln(m["tileset"])
        w, h = m["width"] * 16, m["height"] * 16
        bild = [0] * (w * h)
        for ty in range(m["height"]):
            for tx in range(m["width"]):
                i = ty * m["width"] + tx
                for lage, durchsichtig in ((m["underlay"][i], False),
                                           (m["overlay"][i], True)):
                    g, _ = ambmap.resolve(defs, lage)
                    if not g or g > len(kacheln):
                        continue
                    k = kacheln[g - 1]
                    for y in range(16):
                        z = (ty * 16 + y) * w + tx * 16
                        for x in range(16):
                            c = k[y * 16 + x]
                            if durchsichtig and c == 0:
                                continue
                            bild[z + x] = c
        return bild, w, h

    def karten_2d(self, hoechstens=80 * 80):
        for nr, m in sorted(self.karten.items()):
            if m["type"] == ambmap.TYPE_2D and m["width"] * m["height"] <= hoechstens:
                yield nr, m


def reduziere(palette, haeufigkeit, art, stufen):
    """32 Farben -> (16 Ersatzfarben, Tabelle[32]).

    Weitester-Punkt-Start (ausser bei 'haeufig'), dann gewichtetes k-means,
    zuletzt auf das Raster der Hardware gerundet (stufen = 15 STE, 7 ST).
    """
    if art == "palette":
        gewicht = {i: 1 for i in range(32)}
    elif art == "wurzel":
        gewicht = {i: math.sqrt(n) for i, n in haeufigkeit.items()}
    else:
        gewicht = dict(haeufigkeit)
    punkte = [(rgb(palette[i]), gewicht[i]) for i in range(32)
              if gewicht.get(i, 0) > 0]
    if len(punkte) <= 16:
        mitten = [p for p, _ in punkte]
    else:
        if art == "haeufig":
            mitten = [p for p, _ in sorted(punkte, key=lambda q: -q[1])[:16]]
        else:
            mitten = [max(punkte, key=lambda q: q[1])[0]]
            while len(mitten) < 16:
                mitten.append(max(punkte, key=lambda q: min(
                    abstand2(q[0], c) for c in mitten))[0])
        for _ in range(30):
            gruppen = collections.defaultdict(list)
            for p, g in punkte:
                j = min(range(16), key=lambda j: abstand2(p, mitten[j]))
                gruppen[j].append((p, g))
            for j, grp in gruppen.items():
                s = sum(g for _, g in grp)
                mitten[j] = tuple(sum(p[k] * g for p, g in grp) / s
                                  for k in range(3))
    mitten = [tuple(round(v / 15 * stufen) * 15 / stufen for v in c)
              for c in mitten]
    tabelle = [min(range(len(mitten)),
                   key=lambda j: abstand2(rgb(palette[i]), mitten[j]))
               for i in range(32)]
    return mitten, tabelle


def fehler(palette, haeufigkeit, mitten, tabelle):
    """(Anteil der Punkte mit >= 2 Stufen Abweichung in %,
        schlimmste Abweichung einer Farbe mit >= 0,1 % Anteil)"""
    gesamt = sum(haeufigkeit.values())
    stark = 0
    akzent = 0.0
    for i, n in haeufigkeit.items():
        d = math.sqrt(abstand2(rgb(palette[i]), mitten[tabelle[i]]))
        if d >= 2.0:
            stark += n
        if n / gesamt >= 0.001:
            akzent = max(akzent, d)
    return 100.0 * stark / gesamt, akzent


def cmd_messen(a):
    d = Daten()
    ergebnis = {15: [], 7: []}
    print("Karte Satz Pal  Groesse   Farben  STE >=2 St. Akzent   ST >=2 St. Akzent")
    for nr, m in d.karten_2d():
        bild, w, h = d.render(m)
        pal = d.paletten[m["palette"] - 1]
        hf = collections.Counter(bild)
        zeile = []
        for stufen in (15, 7):
            anteil, akzent = fehler(pal, hf, *reduziere(pal, hf, a.art, stufen))
            ergebnis[stufen].append((anteil, akzent))
            zeile += [anteil, akzent]
        print("%4d %3d %4d  %4dx%-4d  %2d    %5.1f%%  %4.1f     %5.1f%%  %4.1f"
              % (nr, m["tileset"], m["palette"], w, h, len(hf), *zeile))
    for stufen, name in ((15, "STE"), (7, "ST")):
        e = ergebnis[stufen]
        print("%s: %d Karten; Punkte >= 2 Stufen: Median %.1f %%, Max %.1f %%, "
              "unter 1 %%: %d; schlimmste Akzentfarbe: Median %.1f, Max %.1f Stufen"
              % (name, len(e), statistics.median(x for x, _ in e),
                 max(x for x, _ in e), sum(1 for x, _ in e if x < 1),
                 statistics.median(y for _, y in e), max(y for _, y in e)))


def schreibe_png(pfad, punkte, w, h):
    roh = b"".join(b"\0" + bytes(v for p in punkte[y * w:(y + 1) * w] for v in p)
                   for y in range(h))

    def block(t, inhalt):
        return (struct.pack(">I", len(inhalt)) + t + inhalt
                + struct.pack(">I", zlib.crc32(t + inhalt) & 0xFFFFFFFF))
    with open(pfad, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + block(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + block(b"IDAT", zlib.compress(roh, 9)) + block(b"IEND", b""))


def cmd_bild(a):
    d = Daten()
    tafeln = []
    for nr, x0, y0 in AUSSCHNITTE:
        m = d.karten[nr]
        bild, w, h = d.render(m)
        pal = d.paletten[m["palette"] - 1]
        hf = collections.Counter(bild)
        bw, bh = min(320, w), min(200, h)
        aus = [bild[(y0 + y) * w + x0 + x] for y in range(bh) for x in range(bw)]
        spalten = [[tuple(v * 17 for v in rgb(pal[i])) for i in range(32)]]
        for stufen in (15, 7):
            mitten, tabelle = reduziere(pal, hf, a.art, stufen)
            spalten.append([tuple(int(v * 17) for v in mitten[tabelle[i]])
                            for i in range(32)])
        tafeln.append((aus, bw, bh, spalten))
    gw = 3 * 320 + 2 * 8
    gh = sum(t[2] for t in tafeln) + 8 * (len(tafeln) - 1)
    punkte = [(40, 40, 40)] * (gw * gh)
    y = 0
    for aus, bw, bh, spalten in tafeln:
        for s, farben in enumerate(spalten):
            for yy in range(bh):
                for xx in range(bw):
                    punkte[(y + yy) * gw + s * 328 + xx] = farben[aus[yy * bw + xx]]
        y += bh + 8
    os.makedirs(os.path.dirname(a.o) or ".", exist_ok=True)
    schreibe_png(a.o, punkte, gw, gh)
    print(a.o)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    u = p.add_subparsers(dest="befehl", required=True)
    for name in ("messen", "bild"):
        q = u.add_parser(name)
        q.add_argument("--art", choices=("palette", "wurzel", "haeufig"),
                       default="palette")
        if name == "bild":
            q.add_argument("-o", default=None)
    a = p.parse_args()
    if a.befehl == "bild":
        if a.o is None:
            a.o = "build/farbreduktion/vergleich_%s.png" % a.art
        cmd_bild(a)
    else:
        cmd_messen(a)


if __name__ == "__main__":
    main()

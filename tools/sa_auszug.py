#!/usr/bin/env python3
"""sa_auszug.py -- Thalions 32 Musikstuecke aus Music.amb als Sonic-Arranger-Dateien.

Zum Anhoeren am PC (etwa mit UADE), nicht fuer den Bau.  Die Ausgabe
liegt unter ``build/sa`` und kommt nie ins Repository (Spieldaten).

**Weg:**

1. ``Music.amb`` (AMNP, 32 Eintraege, LOB) mit ``ambtool.unpack``.
2. Jeder Eintrag ist eine *gepackte* Sonic-Arranger-Datei (docs/13 4): 8
   Langworte Versaetze (Lieder, Stimmen, Noten, Instrumente, Wellen,
   ADSR, AMF, Samples), Wort $2144/$2154, Wort $FFFF, Langwort 0, ab $28
   die Abschnitte mit fester Satzlaenge (12, 4, 4, 152, 128, 128, 128),
   dann die Samples (Anzahl, Groessen in Byte, Daten), dann "deadbeef",
   Langwort 0 und der Autor (Zeichen bitweise verneint, Endnull).
3. Daraus wird das Editorformat ``SOARV1.0`` mit den Bloecken STBL, OVTB,
   NTBL, INST, SD8B, SYWT, SYAR, SYAF, EDAT.  Den Aufbau beider Formate
   beschreibt Pyrdacors Bibliothek (github.com/Pyrdacor/SonicArranger,
   ``Docs/PackedFileFormat.md``, ``SonicArrangerFile.cs``,
   ``SampleTable.cs``); dieses Werkzeug schreibt so, wie deren ``Save``
   es tut.  Die Instrumentsaetze gehen Byte fuer Byte hinueber.

Die Titel kommen aus ``Text.amb`` (``Song_names``, ueber
``textmarken.zerlegen``), die Nummer ist Thalions (docs/13 3).  Jede
Annahme wird geprueft; passt eine nicht, bricht das Werkzeug ab.

Aufruf:  sa_auszug.py [--amberfiles DIR] [--out build/sa] [--roh]
         --roh schreibt zusaetzlich die gepackten Eintraege (NN_*.bin)
"""
import argparse
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import unpack          # noqa: E402
from textmarken import zerlegen     # noqa: E402
import paths  # noqa: E402

ANZAHL = 32
SATZ = [12, 4, 4, 152, 128, 128, 128]      # Lieder .. AMF
ENDE = b"deadbeef"


def fehler(text):
    sys.exit("sa_auszug.py: " + text)


def titel_lesen(amberfiles):
    art, teile = unpack(open(os.path.join(amberfiles, "Text.amb"), "rb").read())
    d = bytes(teile[0])
    marken, _ = zerlegen(d)
    o = [v for v, namen in marken.items() if "Song_names" in namen]
    if len(o) != 1:
        fehler("Song_names in Text.amb nicht gefunden")
    o = o[0]
    if struct.unpack(">H", d[o - 2:o])[0] * 4 < ANZAHL:
        fehler("Song_names: Liste zu kurz")
    titel = []
    for _ in range(ANZAHL):
        e = d.index(b"\0", o)
        titel.append(d[o:e].decode("latin-1"))
        o = e + 1
    return titel


def dateiname(nr, titel):
    t = titel.replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
    t = re.sub(r"[^A-Za-z0-9]+", "_", t).strip("_")
    return "%02d_%s" % (nr, t or "ohne_Titel")


def zerlege_gepackt(nr, x):
    """-> dict mit den Abschnitten; prueft den Aufbau."""
    v = list(struct.unpack(">8I", x[:32]))
    w1, w2, l0 = struct.unpack(">HHI", x[32:40])
    if v[0] != 0x28 or w2 != 0xFFFF or l0 != 0:
        fehler("Stueck %d: Kopf passt nicht (%x %04x %x)" % (nr, v[0], w2, l0))
    if v != sorted(v) or v[7] > len(x):
        fehler("Stueck %d: Versaetze nicht aufsteigend" % nr)
    teile = []
    for i, satz in enumerate(SATZ):
        groesse = v[i + 1] - v[i]
        if groesse % satz:
            fehler("Stueck %d: Abschnitt %d (%d Byte) nicht durch %d teilbar"
                   % (nr, i, groesse, satz))
        teile.append(x[v[i]:v[i + 1]])
    if len(teile[1]) % 16:
        fehler("Stueck %d: Stimmen nicht in Vierergruppen" % nr)
    o = v[7]
    n = struct.unpack(">I", x[o:o + 4])[0]
    groessen = struct.unpack(">%dI" % n, x[o + 4:o + 4 + 4 * n])
    o += 4 + 4 * n
    samples = []
    for g in groessen:
        samples.append(x[o:o + g])
        o += g
    if x[o:o + 8] != ENDE or x[o + 8:o + 12] != b"\0\0\0\0":
        fehler("Stueck %d: hinter den Samples kein deadbeef ($%X)" % (nr, o))
    o += 12
    e = x.index(b"\0", o)
    autor = bytes(~b & 0xFF for b in x[o:e] if b & 0x80).decode("ascii", "replace")
    if any(x[e:]):
        fehler("Stueck %d: hinter dem Autor stehen noch Daten" % nr)
    return teile, samples, autor


def soar(teile, samples):
    lieder, stimmen, noten, inst, wellen, adsr, amf = teile
    b = bytearray(b"SOARV1.0")

    def block(tag, anzahl, daten):
        b.extend(tag + struct.pack(">I", anzahl) + daten)

    block(b"STBL", len(lieder) // 12, lieder)
    block(b"OVTB", len(stimmen) // 16, stimmen)      # Anzahl = Muster (je 4 Stimmen)
    block(b"NTBL", len(noten) // 4, noten)
    block(b"INST", len(inst) // 152, inst)
    # SD8B: Anzahl, Laengen (Worte), Wiederholung, Namen (30), Groessen, Daten
    n = len(samples)
    namen = []
    for s in range(n):
        name = b"--blank--"
        for i in range(0, len(inst), 152):
            synth, nummer = struct.unpack(">HH", inst[i:i + 4])
            if synth == 0 and nummer == s:
                name = inst[i + 122:i + 152].split(b"\0")[0]
                break
        namen.append(name[:30].ljust(30, b"\0"))
    sd = b"".join(struct.pack(">I", len(s) // 2) for s in samples)
    sd += struct.pack(">I", 1) * n
    sd += b"".join(namen)
    sd += b"".join(struct.pack(">I", len(s)) for s in samples)
    sd += b"".join(samples)
    block(b"SD8B", n, sd)
    block(b"SYWT", len(wellen) // 128, wellen)
    block(b"SYAR", len(adsr) // 128, adsr)
    block(b"SYAF", len(amf) // 128, amf)
    b.extend(b"EDAT" + b"V1.1" + bytes([1, 1, 1, 1]) + bytes(12))
    return bytes(b)


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--amberfiles", default=paths.amberfiles())
    p.add_argument("--out", default="build/sa")
    p.add_argument("--roh", action="store_true")
    a = p.parse_args()

    art, eintraege = unpack(open(os.path.join(a.amberfiles, "Music.amb"), "rb").read())
    if art != "AMNP" or len(eintraege) != ANZAHL:
        fehler("Music.amb: %s mit %d Eintraegen, erwartet AMNP mit %d"
               % (art, len(eintraege), ANZAHL))
    titel = titel_lesen(a.amberfiles)
    os.makedirs(a.out, exist_ok=True)
    for nr, (x, t) in enumerate(zip(eintraege, titel), 1):
        x = bytes(x)
        teile, samples, autor = zerlege_gepackt(nr, x)
        name = dateiname(nr, t)
        daten = soar(teile, samples)
        open(os.path.join(a.out, name + ".sa"), "wb").write(daten)
        if a.roh:
            open(os.path.join(a.out, name + ".bin"), "wb").write(x)
        print("  %2d  %-34s %d Lied(er) %d Samples %6d Byte"
              % (nr, t, len(teile[0]) // 12, len(samples), len(daten)))
    print("  -> %s" % a.out)


if __name__ == "__main__":
    main()

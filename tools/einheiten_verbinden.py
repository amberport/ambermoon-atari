#!/usr/bin/env python3
"""Zwei Uebersetzungseinheiten verbinden: die XDEF-Listen erzeugen und pruefen.

Thalion hat Bibliothek und Spiel getrennt uebersetzt (engine/spiel.s erklaert
das).  Wir bauen deshalb zwei Einheiten:

    bibliothek  engine/engine.s   Thalions HULL/, unsere Schicht, der Nachbau
    spiel       engine/spiel.s    Thalions Spieldateien (MAIN.S, ...)

Was eine Einheit von der anderen braucht, muss die andere exportieren.  Das
Werkzeug uebersetzt jede Einheit einmal mit Listing (ohne Objektdatei), liest
aus der Symboltabelle, was sie definiert und was ihr fehlt, und schreibt
build/xdef_<einheit>.i mit genau den Namen, die die andere braucht.

**Pruefungen**, jede bricht ab (Rueckgabewert 1):

- *doppelt*: eine Marke, die in beiden Einheiten definiert ist.  Sonst gaebe
  es still zwei Variablen gleichen Namens, und Thalions Code schriebe in eine
  andere, als unser Code liest.  Ausgenommen ist nur DOPPELT_ERLAUBT.
- *fehlt*: ein Name, den eine Einheit braucht und keine definiert.  vlink
  meldete das auch, aber hier steht, welche Einheit ihn braucht.

Aufruf aus dem Repository-Wurzelverzeichnis:

    python3 tools/einheiten_verbinden.py [--cpu 68030] [--extra "-DZEIGERTAKT=1"]

VASM_EXTRA aus der Umgebung wird uebernommen, wenn --extra fehlt.
"""
import argparse
import os
import re
import subprocess
import sys
import paths

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

EINHEITEN = [("bibliothek", "engine.s"), ("spiel", "spiel.s")]

# Namen, die in Thalions Quelltext selbst doppelt stehen: je eine private
# Fassung in einer HULL-Datei (nicht per XDEF exportiert) und in MAIN.S.
DOPPELT_ERLAUBT = {
    "Number": "MAIN.S und HULL/MODULE_C.S, dort nicht exportiert",
    "Control_list_ptr": "MAIN.S und HULL/CONTROLS.S, dort nicht exportiert",
}

ZEILE = re.compile(r"^(\S+)\s+(external|[0-9A-Fa-f]+:[0-9A-Fa-f]+|E:[0-9A-Fa-f]+)")


def symbole(listing):
    """Listing -> (Marken, Konstanten, extern) als Mengen."""
    marken, konst, extern = set(), set(), set()
    drin = False
    for zeile in open(listing, encoding="latin1"):
        if zeile.startswith("Symbols by name:"):
            drin = True
            continue
        if drin:
            if not zeile.strip():
                break
            m = ZEILE.match(zeile)
            if not m:
                continue
            name, art = m.group(1), m.group(2)
            if art == "external":
                extern.add(name)
            elif art.startswith("E:"):
                konst.add(name)
            else:
                marken.add(name)
    if not drin:
        raise SystemExit("%s: keine Symboltabelle im Listing" % listing)
    return marken, konst, extern


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cpu", default="68030")
    ap.add_argument("--extra", default=None,
                    help="Uebersetzungsschalter wie VASM_EXTRA")
    a = ap.parse_args()
    extra = a.extra if a.extra is not None else os.environ.get("VASM_EXTRA", "")

    urcode = paths.urcode()
    build = os.path.join(WURZEL, "build")
    engine = os.path.join(WURZEL, "engine")
    os.makedirs(build, exist_ok=True)

    # Durchgang 1: leere XDEF-Listen.  Eine alte Liste koennte einen Namen
    # exportieren, den es nicht mehr gibt, und die Uebersetzung stoeren.
    for name, _ in EINHEITEN:
        open(os.path.join(build, "xdef_%s.i" % name), "w").close()

    tab = {}
    for name, quelle in EINHEITEN:
        lst = os.path.join(build, "%s.lst" % name)
        cmd = ["vasmm68k_mot", "-m" + a.cpu, "-Fvobj", "-esc", "-align", "-quiet",
               "-I" + urcode, "-I../tools/originalcode", "-I" + build]
        cmd += extra.split()
        cmd += ["-L", lst, "-Lni", "-o", os.devnull, quelle]
        r = subprocess.run(cmd, cwd=engine, capture_output=True, text=True,
                           errors="replace")
        if r.returncode:
            sys.stderr.write(r.stdout + r.stderr)
            raise SystemExit("Einheit %s uebersetzt nicht" % name)
        tab[name] = symbole(lst)

    fehler = 0
    (na, (ma, ka, ea)), (nb, (mb, kb, eb)) = list(tab.items())

    doppelt = sorted((ma & mb) - set(DOPPELT_ERLAUBT))
    if doppelt:
        fehler += 1
        print("  DOPPELT in %s und %s (%d):" % (na, nb, len(doppelt)))
        for n in doppelt:
            print("    " + n)

    for (nx, (mx, kx, ex)), (ny, (my, ky, ey)) in (
            ((na, tab[na]), (nb, tab[nb])), ((nb, tab[nb]), (na, tab[na]))):
        # Was y braucht und x definiert, exportiert x.
        export = sorted(ey & (mx | kx))
        with open(os.path.join(build, "xdef_%s.i" % nx), "w") as f:
            f.write("; erzeugt von tools/einheiten_verbinden.py -- "
                    "nicht von Hand aendern\n")
            f.write("; was die Einheit %s aus %s braucht\n" % (ny, nx))
            for n in export:
                f.write("\txdef\t%s\n" % n)
        fehlt = sorted(ey - mx - kx)
        if fehlt:
            fehler += 1
            print("  FEHLT: %s braucht %d Namen, die nirgends stehen:"
                  % (ny, len(fehlt)))
            print("    " + " ".join(fehlt))
        print("  %s exportiert %d Namen an %s" % (nx, len(export), ny))

    erlaubt = sorted((ma & mb) & set(DOPPELT_ERLAUBT))
    for n in erlaubt:
        print("  doppelt, wie bei Thalion: %s (%s)" % (n, DOPPELT_ERLAUBT[n]))
    return 1 if fehler else 0


if __name__ == "__main__":
    sys.exit(main())

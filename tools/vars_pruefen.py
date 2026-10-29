#!/usr/bin/env python3
"""
vars_pruefen.py -- liegen zwei Variablen auf demselben Platz?

Warum
=====
Die Variablen der Engine sind Versaetze auf `a5`, von Hand vergeben:

    v_step  = 256
    p_tos   = 258
    p_scrr  = 262

Wer eine neue anhaengt, muss wissen, wo die letzte aufhoert -- und die Liste
ist nach Themen geordnet, nicht nach Zahlen.  Genau daran ist es
schiefgegangen: `v_sit` bekam 258 und lag damit auf `p_tos`, der Adresse des
TOS-Bildschirms.  Beim Beenden schaltet die Engine dorthin zurueck; sie
schaltete stattdessen auf den Wert der Sitzhaltung.

**Der Fehler zeigt sich nicht dort, wo er entsteht.** Auf dem Bildschirm sah
es nach einem kaputten Desktop nach dem Programmende aus, und die
Sitzhaltung selbst funktionierte.

Was geprueft wird
=================
Jede Zuweisung der Form `name = zahl` in FALCON_OFF.S (unsere Datei,
nicht Thalions GAME_OFF.S) wird als Variable
gelesen, ihre Groesse aus dem Namensvorsatz geschaetzt:

    p_...   4 Byte (Zeiger)
    sonst   2 Byte (Wort), sofern nicht unten anders eingetragen

Ueberlappen sich zwei Bereiche, wird das gemeldet.  Ausserdem, ob alles in
`vars_size` passt.

Was es nicht kann
=================
Die Groessen sind geschaetzt.  Wer ein Langwort in einer Variablen ohne
`p_`-Vorsatz fuehrt, traegt sie in GROESSEN ein -- sonst bleibt eine
Ueberlappung unentdeckt.  Konstanten, die keine Variablen sind, stehen in
KEINE_VARIABLE.

    python3 tools/vars_pruefen.py
"""
import os
import re
import sys

# Variablen, die groesser sind als ihr Vorsatz vermuten laesst.
GROESSEN = {
    "oldssp": 4,
    "oldmvec": 4,
}

# Zeilen der Form "name = zahl", die keine a5-Variable beschreiben.
KEINE_VARIABLE = re.compile(
    r"^(vars_size|SCRW|SCRH|PLANES|SCRROW|SCRSZ|TILE|TROW|TSZ|COLS|ROWS"
    r"|CENTREX|CENTREY|WINX|WINY|MODEMASK|FILEMAX|AMFA_HDR|AMFA_ENT"
    r"|MPTR_W|MPTR_H|MPTR_SIZE|PAD_SIZE|SIT_MASK|DIRS|MB_LEFT|MB_RIGHT"
    r"|F_[A-Z]+|CH_[A-Z]+|MAX_[A-Z]+|PD_[A-Z]+|BA_[A-Z]+|UI_[A-Z]+"
    r"|DEFAULT_[A-Z]+|WINDOW_[A-Z]+|PROCBUF|FONT_[A-Z]+|[A-Z][A-Z0-9_]*)$")


def variablen(pfad):
    """Nur der a5-Block: er beginnt hinter `vars_size` und endet am naechsten
    Ueberschriftenblock.  Davor stehen die TOS-Aufrufnummern, die zufaellig
    dieselbe Schreibweise haben -- Cconin = 1, Physbase = 2 -- und ohne
    diese Eingrenzung als ueberlappende Variablen gemeldet wuerden."""
    aus = []
    drin = False
    for zeile in open(pfad, encoding="utf-8"):
        if re.match(r"^vars_size\s*=", zeile):
            drin = True
            continue
        if not drin:
            continue
        if re.match(r"^; \*\*\*", zeile):
            break
        zeile = zeile.split(";")[0]
        m = re.match(r"^([A-Za-z_]\w*)\s*=\s*(\d+)\s*$", zeile)
        if not m:
            continue
        name, wert = m.group(1), int(m.group(2))
        # **Das Ausschlussmuster wurde hier nie gefragt.**  Es stand seit
        # jeher oben, aber die Schleife lief daran vorbei; auffallen konnte
        # das nicht, solange keine Konstante zwischen den Variablen stand.
        # Mit BTN_H, CI_H und PROMPT_QUIT standen dort drei, und der
        # Pruefer meldete sie als ueberlappende Variablen.
        if KEINE_VARIABLE.match(name):
            continue
        groesse = GROESSEN.get(name, 4 if name.startswith("p_") else 2)
        aus.append((wert, groesse, name))
    return sorted(aus)


def main():
    wurzel = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    pfad = os.path.join(wurzel, "engine", "src", "FALCON_OFF.S")
    vs = variablen(pfad)
    if not vs:
        print("  Keine Variablen gefunden -- Muster geprueft?")
        return 1

    treffer = 0
    for i in range(len(vs) - 1):
        a, ga, na = vs[i]
        b, gb, nb = vs[i + 1]
        if a + ga > b:
            print("  %-10s %3d..%-3d ueberlappt %-10s %3d..%d"
                  % (na, a, a + ga - 1, nb, b, b + gb - 1))
            treffer += 1

    m = re.search(r"^vars_size\s*=\s*(\d+)", open(pfad, encoding="utf-8").read(),
                  re.M)
    if m:
        ende = vs[-1][0] + vs[-1][1]
        if ende > int(m.group(1)):
            print("  %s endet bei %d, vars_size ist nur %s"
                  % (vs[-1][2], ende, m.group(1)))
            treffer += 1

    if treffer:
        print("\n%d Ueberlappung(en).  Freier Platz beginnt bei %d."
              % (treffer, vs[-1][0] + vs[-1][1]))
        return 1
    print("  Keine Ueberlappung.  %d Variablen, hoechster Platz %d von %s."
          % (len(vs), vs[-1][0] + vs[-1][1] - 1, m.group(1) if m else "?"))
    return 0


if __name__ == "__main__":
    sys.exit(main())

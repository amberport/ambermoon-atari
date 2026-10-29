#!/usr/bin/env python3
"""Platzhalter-Karte: was ist Platzhalter, woher kommt das Echte, wer ruft es.

Statt im Hardwaretest zu entdecken "Knopf geht nicht -- war das ein
Platzhalter?", soll *vorher* feststehen, welche Wege auf einen Platzhalter
fuehren.  Was dann trotzdem nicht geht und nicht auf der Liste steht, ist ein
echter Fehler.

Das Werkzeug liest die Dateien, die engine/engine.s und engine/spiel.s
einbinden (den INCLUDE-Zeilen nach, ohne Bedingungen auszuwerten), und baut
daraus einen Verweisgraphen: jede globale Marke ist ein Knoten, jeder Name
in ihrem Rumpf eine Kante (jsr, bsr, jmp, lea, dc.l ... -- also auch
Moduldeskriptoren und Sprungtabellen), dazu das Durchfallen in die naechste
Marke.  Die Makros aus vorspann.i werden eine Stufe tief eingesetzt
("Push Module,Eye_Mod" -> Push_Module und Eye_Mod).

**Was als Platzhalter gilt**

- jede Marke in einer *_STUBS.S, die Thalions Code anspricht oder die in
  Thalions Quelltext definiert ist (sonst ist es eine Hilfsmarke von uns,
  etwa Platzhaltermodul_ab),
- eine Marke in unseren uebrigen Dateien, deren Rumpf nur ``rts`` ist und die
  Thalions Code anspricht ("verdeckt", etwa Exit_map).

**Woher das Echte kommt** (Sorte)

- A: in Thalions Quelltext definiert, die Datei ist nur noch nicht
  eingebunden -> faellt mit der Datei.
- B: nicht im Quelltext, eine Routine oder ein Mauszeiger -> Thalions nicht
  freigegebene Bibliothek (AM2_CPU), also unsere Bibliotheksschicht.
- C: nicht im Quelltext, Daten (Texte, Grafik, Tabellen) -> bei Thalion
  eigene Dateien, bei uns Ladebruecken (Leitziel 2).
Die Trennung B/C ist eine Naeherung ueber die Art des Platzhalters.

**Gefaehrlich** heisst: der Platzhalter antwortet still falsch.

- ein Routinen-Platzhalter, nach dessen Aufruf Thalion die Flags auswertet
  (Bcc, Scc) oder ein Register prueft (tst/cmp) -> "Rueckgabe";
  liest der naechste Befehl nur ein Register als Quelle -> "Register?"
  (kann auch ein bewahrtes Argument sein, von Hand pruefen);
  ein ``jmp`` darauf gibt die Antwort an den Aufrufer des Aufrufers weiter
  -> "Endsprung",
- ein Nullmodul (``ds.b Module_data_size``): legt die Eingabe lahm.
Datensaetze aus Nullen verhalten sich wie "nichts da" (Erkenntnis 187); sie
stehen mit ihren Lesern in der Liste, gelten aber nicht als gefaehrlich.

**Schreiber fehlt** -- was die Platzhalter-Liste nicht sieht: eine Variable
Thalions, die der eingebundene Code *liest*, die aber nur eine noch nicht
eingebundene Datei *beschreibt*.  Der Name ist da (meist in MAIN.S), Bau und
Linker sind zufrieden, der Wert bleibt null.  So fand Find_event auf der
Weltkarte kein Ereignis: Submap_width und Quad_map setzt nur MAP/2D_WILD.S.
Geschrieben heisst: der Name steht im Ziel eines Befehls (move ...,Name;
clr Name; st Name; addq #1,Name ...).  Wer ueber einen Zeiger schreibt
(lea Name,a0 / move d0,Feld(a0)), zaehlt nicht -- die Liste ist darum eine
Obermenge; "lea im Bau" steht dabei, wo das vorkommt.

**Aufrufe**

    python3 tools/platzhalter_karte.py            Liste nach build/platzhalter.txt,
                                                   Zusammenfassung auf stdout
    python3 tools/platzhalter_karte.py --von Event_handler
                                                   welche Platzhalter von dort
                                                   erreichbar sind, mit Weg
    python3 tools/platzhalter_karte.py --von Event_handler --ohne Door,Riddlemouth
                                                   Knoten abschneiden
    python3 tools/platzhalter_karte.py --wer Update_light_status
                                                   Eintrag eines Platzhalters
    python3 tools/platzhalter_karte.py --schreiber
                                                   Variablen ohne Schreiber im Bau

Die Reichweite ist eine **Obermenge**: jede Tabelle zaehlt ganz, auch
Zweige, die der Spielzustand nie nimmt.  Der Weg zeigt, warum ein
Platzhalter erreichbar ist; ob der Zweig genommen wird, entscheidet man dort.

Rueckgabe immer 0 (nur Bericht), ausser bei Aufruffehlern.
"""
import argparse
import collections
import os
import re
import sys
import paths

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
URCODE = paths.urcode()
ENGINE = os.path.join(WURZEL, "engine")
VORSPANN = os.path.join(WURZEL, "tools", "originalcode", "vorspann.i")
EINHEITEN = [("bibliothek", "engine.s"), ("spiel", "spiel.s")]

NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
REGISTER = re.compile(r"^(d[0-7]|a[0-7]|sp|pc|ccr|sr|usp)$", re.I)
BEDINGUNGEN = ("hi", "ls", "cc", "hs", "cs", "lo", "ne", "eq", "vc", "vs",
               "pl", "mi", "ge", "lt", "gt", "le")
ENDE = {"rts", "rte", "rtr", "jmp", "bra"}

# Leere Routinen in unserer Bibliotheksschicht, die *endgueltig* leer sind:
# die richtige Uebersetzung, kein Platzhalter.  Begruendung steht am Ort.
ENDGUELTIG_LEER = {
    "Close_current_file": "HULL/LIBRARY.S: unsere Dateien sind beim Fehler schon zu (Erkenntnis 268)",
    "Wait_4_fade": "HULL/FADE_SUP.S: Set_fade ist fertig, wenn es zurueckkehrt",
    "Invalidate_memory": "HULL/MEMORY.S: nichts wird wiederverwendet (Erkenntnis 196)",
}


def ohne_groesse(mnem):
    return mnem.lower().split(".")[0]


def ist_bcc(m):
    m = ohne_groesse(m)
    return (m.startswith("b") and m[1:] in BEDINGUNGEN) or \
           (m.startswith("s") and m[1:] in BEDINGUNGEN)


def operand_namen(op):
    """Namen im Operandenfeld, ohne Zeichenketten und Register."""
    op = re.sub(r'"[^"]*"|\'[^\']*\'', " ", op)
    op = re.sub(r"\$[0-9A-Fa-f]+|%[01]+", " ", op)
    return [n for n in NAME.findall(op)
            if not REGISTER.match(n) and n.lower() not in ("b", "w", "l", "s")]


def zerlege(zeile):
    """Zeile -> (Marke, Befehl, Operand).  Motorola-Syntax wie bei vasm."""
    z = zeile.rstrip("\r\n")
    if not z.strip() or z[0] in ";*":
        return None, None, None
    marke = None
    rest = z
    if not z[0].isspace():
        m = re.match(r"([A-Za-z_.][A-Za-z0-9_.\\@]*):?", z)
        if not m:
            return None, None, None
        marke, rest = m.group(1), z[m.end():]
    rest = rest.lstrip()
    m = re.match(r"([A-Za-z_.][A-Za-z0-9_.]*):(?=\s|$)", rest)
    if m and marke is None:                     # eingerueckte Marke mit Doppelpunkt
        marke, rest = m.group(1), rest[m.end():].lstrip()
    if not rest or rest[0] == ";":
        return marke, None, None
    teile = rest.split(None, 1)
    befehl = teile[0]
    op = ""
    if len(teile) > 1:
        # Operand endet am ersten Leerraum ausserhalb von Anfuehrungszeichen.
        s, q = teile[1], None
        for i, c in enumerate(s):
            if q:
                if c == q:
                    q = None
            elif c in "\"'":
                q = c
            elif c in " \t;":
                s = s[:i]
                break
        op = s
    if befehl == "=":
        befehl = "equ"
    return marke, befehl, op


# ---------------------------------------------------------------------------
# Dateien und Makros
# ---------------------------------------------------------------------------

def aufloesen(name):
    for basis, art in ((ENGINE, "unser"), (URCODE, "thalion"),
                       (os.path.dirname(VORSPANN), "unser"),
                       (os.path.join(WURZEL, "build"), "erzeugt")):
        p = os.path.join(basis, name)
        if os.path.isfile(p):
            return p, art
    return None, None


def eingebunden():
    """[(Pfad, Art, Einheit)] in Einbindereihenfolge."""
    liste, gesehen = [], set()

    def lies(pfad, art, einheit):
        if pfad in gesehen:
            return
        gesehen.add(pfad)
        liste.append((pfad, art, einheit))
        for zeile in open(pfad, encoding="latin-1"):
            m = re.match(r'\s+INCLUDE\s+"([^"]+)"', zeile, re.I)
            if m:
                p, a = aufloesen(m.group(1))
                if p and a != "erzeugt":
                    lies(p, a, einheit)

    for einheit, datei in EINHEITEN:
        lies(os.path.join(ENGINE, datei), "unser", einheit)
    return liste


def makros():
    """Name -> Rumpfzeilen (nur vorspann.i)."""
    tab, name, rumpf = {}, None, []
    for zeile in open(VORSPANN, encoding="latin-1"):
        m = re.match(r"^(\w+)\s+MACRO\b", zeile, re.I)
        if m:
            name, rumpf = m.group(1), []
            continue
        if name and re.match(r"^\s+ENDM\b", zeile, re.I):
            tab[name.lower()] = rumpf
            name = None
            continue
        if name:
            rumpf.append(zeile)
    return tab


def makro_namen(rumpf, op):
    args = [a.strip() for a in op.split(",")] if op else []
    namen = []
    for zeile in rumpf:
        for i, a in enumerate(args, 1):
            zeile = zeile.replace("\\%d" % i, a)
        _, b, o = zerlege(zeile)
        if b and ohne_groesse(b) not in ("ifnc", "ifc", "endc"):
            namen += operand_namen(o or "")
    return namen


# ---------------------------------------------------------------------------
# Graph
# ---------------------------------------------------------------------------

class Knoten:
    __slots__ = ("name", "pfad", "zeile", "art", "abschnitt", "befehle",
                 "kanten", "weiter", "equ")

    def __init__(self, name, pfad, zeile, art, abschnitt):
        self.name, self.pfad, self.zeile = name, pfad, zeile
        self.art, self.abschnitt = art, abschnitt
        self.befehle = []          # (Zeile, Befehl, Operand)
        self.kanten = []           # (Name, Zeile, Befehl)
        self.weiter = None         # Durchfallen in die naechste Marke
        self.equ = False


def graph_bauen(dateien, mak):
    knoten = {}
    for pfad, art, _ in dateien:
        if pfad == VORSPANN:
            continue
        abschnitt, aktuell, vorher = "code", None, None
        for nr, zeile in enumerate(open(pfad, encoding="latin-1"), 1):
            marke, befehl, op = zerlege(zeile)
            b = ohne_groesse(befehl) if befehl else None
            if b == "section":
                t = (op or "").split(",")
                abschnitt = t[1].lower() if len(t) > 1 else "code"
                continue
            if marke and not marke.startswith(".") and "\\" not in marke:
                if b in ("equ", "set"):
                    k = Knoten(marke, pfad, nr, art, "equ")
                    k.equ = True
                    knoten.setdefault(marke, k)
                    continue
                neu = Knoten(marke, pfad, nr, art, abschnitt)
                # Durchfallen: eine Marke ohne Rumpf ist ein Alias der
                # naechsten; eine Routine ohne Abschluss laeuft in die
                # naechste weiter.  Daten fallen nicht durch.
                if aktuell is not None:
                    letzte = aktuell.befehle[-1][1] if aktuell.befehle else None
                    if letzte is None or ohne_groesse(letzte) not in \
                            ENDE | {"dc", "ds", "dcb"}:
                        aktuell.weiter = marke
                if marke not in knoten or knoten[marke].equ:
                    knoten[marke] = neu
                aktuell = neu
            if not befehl or aktuell is None:
                continue
            if b in ("include", "incbin", "xdef", "xref", "opt", "even",
                     "cnop", "if", "ifd", "ifnd", "ifc", "ifnc", "else",
                     "endc", "endif", "list", "nolist", "macro", "endm"):
                continue
            aktuell.befehle.append((nr, befehl, op or ""))
            namen = operand_namen(op or "")
            if b in mak:
                namen += makro_namen(mak[b], op or "")
            for n in namen:
                aktuell.kanten.append((n, nr, befehl))
    return knoten


# ---------------------------------------------------------------------------
# Platzhalter
# ---------------------------------------------------------------------------

def thalions_definitionen():
    """Name -> Datei (relativ zu URCODE) fuer alle globalen Marken und EQUs."""
    tab = {}
    for wurzel, _, dateien in os.walk(URCODE):
        for d in sorted(dateien):
            if not d.upper().endswith(".S"):
                continue
            p = os.path.join(wurzel, d)
            rel = os.path.relpath(p, URCODE)
            for zeile in open(p, encoding="latin-1"):
                marke, _, _ = zerlege(zeile)
                if marke and not marke.startswith(".") and "\\" not in marke:
                    tab.setdefault(marke, rel)
    return tab


def rumpf(knoten, name):
    """Die Befehle, die an dieser Marke ausgefuehrt werden (Aliase folgen)."""
    k = knoten[name]
    gesehen = set()
    while not k.befehle and k.weiter and k.weiter not in gesehen:
        gesehen.add(k.name)
        k = knoten[k.weiter]
    return k.befehle


def platzhalter_art(knoten, name):
    b = rumpf(knoten, name)
    k = knoten[name]
    if k.equ:
        return "Konstante"
    if not b:
        return "Daten"
    befehl, op = ohne_groesse(b[0][1]), b[0][2]
    if befehl == "rts":
        return "Routine"
    if befehl in ("jmp", "bra"):
        return "Routine (Sprung nach %s)" % op
    if befehl == "ds" and "Module_data_size" in op:
        return "Nullmodul"
    if befehl == "dc" and op.startswith("Local_mod"):
        return "Modul (nimmt sich herunter)"
    return "Daten"


def sorte(name, art, herkunft):
    if herkunft:
        return "A", herkunft
    if art.startswith("Routine") or name.endswith("_Mptr") or art == "Konstante":
        return "B", "Bibliothek (AM2_CPU)"
    low = name.lower()
    if "txt" in low or "text" in low or "names" in low or "string" in low:
        return "C", "Texte"
    return "C", "Daten"


def verweise(knoten):
    """Name -> [(Knoten, Zeile, Befehl)]: wer spricht den Namen an."""
    tab = collections.defaultdict(list)
    for k in knoten.values():
        for n, nr, befehl in k.kanten:
            tab[n].append((k, nr, befehl))
    return tab


def naechster_befehl(pfad, nr):
    for i, zeile in enumerate(open(pfad, encoding="latin-1"), 1):
        if i <= nr:
            continue
        _, befehl, op = zerlege(zeile)
        if befehl:
            return befehl, op or ""
    return None, ""


def vorher_geschrieben(k, nr, reg, tiefe=6):
    """Schreibt einer der letzten Befehle vor dem Aufruf in reg?  Dann prueft
    Thalion danach eher einen eigenen Wert als eine Antwort."""
    vorher = [b for b in k.befehle if b[0] < nr][-tiefe:]
    for _, befehl, op in vorher:
        ziel = op.split(",")[-1].strip().lower() if op else ""
        if ziel == reg.lower() and ohne_groesse(befehl) not in ("tst", "cmp",
                                                               "cmpa", "cmpi",
                                                               "btst"):
            return True
    return False


def rueckgabe_pruefen(name, stellen):
    """Aufrufstellen, an denen Thalion eine Antwort des Platzhalters liest."""
    befunde = []
    for k, nr, befehl in stellen:
        b = ohne_groesse(befehl)
        if b == "jmp":
            befunde.append(("Endsprung", k, nr, "jmp"))
            continue
        if b not in ("jsr", "bsr"):
            continue
        nb, nop = naechster_befehl(k.pfad, nr)
        if not nb:
            continue
        m = ohne_groesse(nb)
        text = "%s %s" % (nb, nop)
        if ist_bcc(nb):
            befunde.append(("Rueckgabe", k, nr, text))
        elif m in ("tst", "cmp", "cmpa", "cmpi") and \
                REGISTER.match(nop.split(",")[-1].strip()):
            reg = nop.split(",")[-1].strip()
            if vorher_geschrieben(k, nr, reg):
                befunde.append(("Register?", k, nr, text + "  (%s vorher geladen)" % reg))
            else:
                befunde.append(("Rueckgabe", k, nr, text))
        elif not m.startswith("db") and nop and REGISTER.match(nop.split(",")[0].strip()) and \
                nop.split(",")[0].strip().lower() not in ("sp", "a7"):
            befunde.append(("Register?", k, nr, text))
    return befunde


def platzhalter_finden(dateien, knoten, thalion):
    ver = verweise(knoten)
    eingebunden_rel = {os.path.relpath(p, URCODE) for p, a, _ in dateien
                       if a == "thalion"}
    tab = {}
    for name, k in knoten.items():
        stub = os.path.basename(k.pfad).upper().endswith("_STUBS.S")
        stellen = ver.get(name, [])
        von_thalion = [s for s in stellen if s[0].art == "thalion"]
        herkunft = thalion.get(name)
        if herkunft in eingebunden_rel:
            continue                    # das Echte ist da
        if stub:
            if not von_thalion and not herkunft:
                continue                # Hilfsmarke von uns
            art = platzhalter_art(knoten, name)
        elif k.art == "unser" and von_thalion and not k.equ:
            b = rumpf(knoten, name)
            if not (len(b) == 1 and ohne_groesse(b[0][1]) == "rts"):
                continue
            if name in ENDGUELTIG_LEER:
                continue
            art = "Routine (verdeckt, in %s)" % os.path.relpath(k.pfad, ENGINE)
        else:
            continue
        s, woher = sorte(name, art, herkunft)
        befunde = rueckgabe_pruefen(name, von_thalion) \
            if art.startswith("Routine") else []
        if art == "Nullmodul" and von_thalion:
            befunde.append(("Nullmodul", von_thalion[0][0], von_thalion[0][1],
                            "legt die Eingabe lahm"))
        tab[name] = dict(art=art, sorte=s, woher=woher, stellen=stellen,
                         von_thalion=von_thalion, befunde=befunde, knoten=k)
    return tab


# ---------------------------------------------------------------------------
# Schreiber fehlt
# ---------------------------------------------------------------------------

# Befehle, deren letzter Operand beschrieben wird, und solche mit nur einem
# Operanden, den sie beschreiben.
ZIEL_LETZTER = {"move", "movea", "movem", "moveq", "add", "adda", "addq", "addi",
                "addx", "sub", "suba", "subq", "subi", "subx", "and", "andi",
                "or", "ori", "eor", "eori", "lsl", "lsr", "asl", "asr", "rol",
                "ror", "roxl", "roxr", "bset", "bclr", "bchg", "exg", "mulu",
                "muls", "divu", "divs", "abcd", "sbcd"}
ZIEL_EINZIG = {"clr", "st", "sf", "neg", "negx", "not", "tas", "nbcd"} | \
    {"s" + b for b in BEDINGUNGEN}


def geschrieben(befehl, op):
    """Die Namen, die dieser Befehl unmittelbar beschreibt."""
    b = ohne_groesse(befehl)
    if not op:
        return []
    teile = [t for t in re.split(r",(?![^(]*\))", op)]
    if b in ZIEL_EINZIG or (b in ("lsl", "lsr", "asl", "asr", "rol", "ror",
                                  "roxl", "roxr") and len(teile) == 1):
        ziel = teile[0]
    elif b in ZIEL_LETZTER and len(teile) >= 2:
        ziel = teile[-1]
    else:
        return []
    # Nur der Name selbst, nicht Feld(a0) oder (Name,d0) als Index.
    ziel = ziel.strip()
    m = re.match(r"^([A-Za-z_]\w*)(\+\d+)?(\.[wl])?$", ziel)
    return [m.group(1)] if m else []


def schreiber_pruefen(dateien, knoten):
    """[(Name, Leser im Bau, lea im Bau, {Datei: Zeilen} ausserhalb)]"""
    im_bau = {p for p, _, _ in dateien}
    variablen = {n for n, k in knoten.items()
                 if k.art == "thalion" and k.abschnitt in ("bss", "data")
                 and not k.equ}
    lesen = collections.defaultdict(set)      # Name -> Routinen im Bau
    lea = collections.defaultdict(set)
    schreiben_bau = set()
    schreiben_aussen = collections.defaultdict(lambda: collections.defaultdict(list))

    thalion_dateien = []
    for wurzel, _, ds in os.walk(URCODE):
        for d in sorted(ds):
            if d.upper().endswith(".S"):
                thalion_dateien.append(os.path.join(wurzel, d))
    unsere = [p for p, a, _ in dateien if a == "unser" and p != VORSPANN]

    for pfad in thalion_dateien + unsere:
        drin = pfad in im_bau
        routine = None
        for nr, zeile in enumerate(open(pfad, encoding="latin-1"), 1):
            marke, befehl, op = zerlege(zeile)
            if marke and not marke.startswith("."):
                routine = marke
            if not befehl:
                continue
            ziele = [n for n in geschrieben(befehl, op) if n in variablen]
            for n in ziele:
                if drin:
                    schreiben_bau.add(n)
                else:
                    schreiben_aussen[n][os.path.relpath(pfad, URCODE)].append(nr)
            if not drin:
                continue
            for n in operand_namen(op or ""):
                if n in variablen and n not in ziele:
                    lesen[n].add(routine or "?")
                    if ohne_groesse(befehl) in ("lea", "pea"):
                        lea[n].add(routine or "?")
    befund = []
    for n in sorted(variablen):
        if lesen.get(n) and n not in schreiben_bau and n in schreiben_aussen:
            befund.append((n, sorted(lesen[n]), sorted(lea.get(n, ())),
                           schreiben_aussen[n]))
    return befund


def schreiber_text(befund):
    aus = []
    for n, leser, lea_bau, aussen in befund:
        wo = ", ".join("%s (%d)" % (d, len(z)) for d, z in sorted(aussen.items()))
        aus.append("%s  -- geschrieben nur in: %s" % (n, wo))
        aus.append("    gelesen im Bau von: " + ", ".join(leser[:8]) +
                   (" ..." if len(leser) > 8 else ""))
        if lea_bau:
            aus.append("    lea im Bau (schreibt vielleicht ueber Zeiger): " +
                       ", ".join(lea_bau[:8]))
    return aus


# ---------------------------------------------------------------------------
# Ausgabe
# ---------------------------------------------------------------------------

def ort(k, nr=None):
    if k.art == "thalion":
        p = os.path.relpath(k.pfad, URCODE)
    else:
        p = os.path.relpath(k.pfad, ENGINE)
    return "%s:%d" % (p, nr or k.zeile)


def gefaehrlich(p):
    return [b for b in p["befunde"] if b[0] in ("Rueckgabe", "Endsprung",
                                                  "Nullmodul")]


def eintrag(name, p, aus):
    aus.append("%s  [%s %s]  %s  -- %s" % (name, p["sorte"], p["woher"],
                                           p["art"], ort(p["knoten"])))
    aufrufer = sorted({s[0].name for s in p["von_thalion"]})
    if aufrufer:
        aus.append("    angesprochen von (Thalion): " + ", ".join(aufrufer))
    unsere = sorted({s[0].name for s in p["stellen"] if s[0].art != "thalion"})
    if unsere:
        aus.append("    angesprochen von (unser):   " + ", ".join(unsere))
    for art, k, nr, text in p["befunde"]:
        aus.append("    ! %-10s %s in %s: %s" % (art, ort(k, nr), k.name, text))


def liste_schreiben(tab, ziel, befund=()):
    aus = ["Platzhalter-Karte, erzeugt von tools/platzhalter_karte.py",
           "Sorte A: Thalions Datei fehlt noch | B: Bibliothek (AM2_CPU) | "
           "C: Daten aus eigenen Dateien", ""]
    for s in "ABC":
        namen = sorted(n for n, p in tab.items() if p["sorte"] == s)
        aus.append("=" * 72)
        aus.append("Sorte %s: %d" % (s, len(namen)))
        aus.append("=" * 72)
        if s == "A":
            nach = collections.Counter(tab[n]["woher"] for n in namen)
            for datei, zahl in nach.most_common():
                aus.append("  %3d  %s" % (zahl, datei))
            aus.append("")
        for n in sorted(namen, key=lambda n: (tab[n]["woher"], n)):
            eintrag(n, tab[n], aus)
        aus.append("")
    aus.append("=" * 72)
    aus.append("Schreiber fehlt: %d (Variable gelesen, nur ausserhalb des Baus "
               "geschrieben)" % len(befund))
    aus.append("=" * 72)
    aus += schreiber_text(befund)
    with open(ziel, "w") as f:
        f.write("\n".join(aus) + "\n")


def zusammenfassung(tab):
    z = collections.Counter(p["sorte"] for p in tab.values())
    gef = [n for n, p in tab.items() if gefaehrlich(p)]
    print("  Platzhalter: %d (A %d Thalion-Datei fehlt, B %d Bibliothek, "
          "C %d Daten), gefaehrlich %d -> build/platzhalter.txt"
          % (len(tab), z["A"], z["B"], z["C"], len(gef)))
    nach = collections.Counter(p["woher"] for p in tab.values()
                               if p["sorte"] == "A")
    print("    groesste Brocken: " + ", ".join(
        "%s %d" % (d, n) for d, n in nach.most_common(5)))


def reichweite(knoten, tab, starts, ohne):
    vorg = {s: None for s in starts}
    schlange = collections.deque(starts)
    while schlange:
        n = schlange.popleft()
        if n in tab and n not in starts:
            continue                    # Platzhalter sind Blaetter
        k = knoten.get(n)
        if k is None:
            continue
        nachbarn = [e[0] for e in k.kanten]
        if k.weiter:
            nachbarn.append(k.weiter)
        for m in nachbarn:
            if m in vorg or m in ohne or m not in knoten:
                continue
            vorg[m] = n
            schlange.append(m)
    gefunden = []
    for n in tab:
        if n in vorg:
            weg, x = [], n
            while x is not None:
                weg.append(x)
                x = vorg[x]
            gefunden.append((n, list(reversed(weg))))
    return gefunden, len(vorg)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--von", help="Startmarken, mit Komma getrennt")
    ap.add_argument("--ohne", default="", help="Marken, die nicht betreten werden")
    ap.add_argument("--wer", help="Eintrag eines Platzhalters zeigen")
    ap.add_argument("--schreiber", action="store_true",
                    help="Variablen, die im Bau niemand schreibt")
    ap.add_argument("--liste", default=os.path.join(WURZEL, "build", "platzhalter.txt"))
    a = ap.parse_args()

    if not os.path.isdir(URCODE):
        print("  Platzhalter-Karte uebersprungen -- AMBER_URCODE fehlt")
        return 0
    dateien = eingebunden()
    knoten = graph_bauen(dateien, makros())
    tab = platzhalter_finden(dateien, knoten, thalions_definitionen())

    if a.wer:
        if a.wer not in tab:
            print("%s ist kein Platzhalter" % a.wer)
            return 2
        aus = []
        eintrag(a.wer, tab[a.wer], aus)
        print("\n".join(aus))
        return 0

    if a.von:
        starts = [s.strip() for s in a.von.split(",") if s.strip()]
        fehlt = [s for s in starts if s not in knoten]
        if fehlt:
            print("unbekannte Startmarke: " + ", ".join(fehlt))
            return 2
        ohne = {s.strip() for s in a.ohne.split(",") if s.strip()}
        gefunden, zahl = reichweite(knoten, tab, starts, ohne)
        print("Von %s erreichbar: %d Marken, davon %d Platzhalter "
              "(Obermenge, siehe --help)" % (", ".join(starts), zahl, len(gefunden)))
        for n, weg in sorted(gefunden, key=lambda g: (not gefaehrlich(tab[g[0]]),
                                                       tab[g[0]]["sorte"], g[0])):
            p = tab[n]
            warn = "!" if gefaehrlich(p) else " "
            print("%s %-24s %s %-18s %s" % (warn, n, p["sorte"], p["art"][:18],
                                            " > ".join(weg)))
        return 0

    befund = schreiber_pruefen(dateien, knoten)
    if a.schreiber:
        print("\n".join(schreiber_text(befund)))
        return 0
    os.makedirs(os.path.dirname(a.liste), exist_ok=True)
    liste_schreiben(tab, a.liste, befund)
    zusammenfassung(tab)
    print("    Schreiber fehlt: %d Variablen, die der Bau liest und nur eine "
          "fehlende Datei schreibt" % len(befund))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""
fantasy_auszug.py -- das Fantasy-Intro aus `Fantasy_intro`, beim Bau.

Wie bei AM2_CPU (Nutzer, 2026-09-27/29): Das Programm wird **nie zur Laufzeit**
gelesen.  Der Bau entpackt es (`imploder_exe.py`) und schreibt nach `build/`:

    fantasy_grafik.bin  Hunk 2 (Grafik, Paletten, Flugbahn), unverändert
    fantasy_daten.i     Namen in Hunk 2, Hunk 3 als BSS in Originalanordnung,
                        Thalions reiner Speichercode und Tabellen aus Hunk 1
    fantasy_werte.i     die Konstanten, die FAIRY.S benutzt, aber nicht
                        definiert (planes, bpscanl, star_anz ...)

Im Repository liegt nur dieses Werkzeug (docs/11-Intro-Extro.md).

Wie die Namen gefunden werden
=============================
Thalions `FAIRY.S` ist der Quelltext eines Teils von Hunk 1 (docs/11, 3.2).
Das Werkzeug übersetzt die **unveränderte** Datei mit vasm und setzt jeden
Namen, den sie nicht selbst definiert, auf einen eigenen Probewert.  An jeder
Relokation im Binärcode steht dann im Probecode „Probewert + Zusatz“: daraus
folgen Name und Adresse.  Gleichzeitig wird Byte für Byte verglichen.  Weicht
etwas ab, stimmt eine Konstante nicht oder die Datei passt nicht zum
Programm, und der Bau bricht ab.  Geduldet werden nur zwei Dinge: die 21
Befehle, die Thalions Assembler als ADDI/SUBI/ANDI/ORI kodiert hat und vasm
als ADD/SUB/AND/OR #n,Dn (gleiche Wirkung, gleiche Flags), und die vier
Sprünge von `level3` nach `new_funkel`, deren Weite anders ist, weil Thalions
Programm die Stücke anders anordnet (das Ziel wird geprüft).
"""

import os
import struct
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import read_hunks          # noqa: E402
from imploder_exe import entpacke       # noqa: E402
import paths  # noqa: E402

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(WURZEL, "build")
URCODE = paths.urcode()
AMBERFILES = paths.amberfiles()


class Fehler(Exception):
    pass


# ---------------------------------------------------------------------------
# Konstanten, die FAIRY.S benutzt und nicht definiert.  Belegt durch den
# Bytevergleich unten: jede steckt in einem Befehl, der sonst abwiche.
# ---------------------------------------------------------------------------
WERTE = [
    ("planes", 5, "move.w #83*planes*64+1,$58(a6) in make_magic"),
    ("bpscanl", 200, "mulu #bpscanl,d1 in blit_star, plot_5p ..."),
    ("star_anz", 400, "move #star_anz-1,d6 in make_magic"),
    ("funkel_anz", 96, "move #funkel_anz-1,d7 in new_funkel"),
    ("funkel_size", 10, "add.w #funkel_size,a0 in new_funkel"),
    ("funkel_anz2", 512, "move #funkel_anz2,d6 in make_funkel"),
    ("funkel_size2", 10, "lea funkel_size2(a3),a3 in make_funkel2"),
]

# Namen, die FAIRY.S benutzt und nicht definiert.  Ihre Adressen liefert der
# Vergleich.
FREMDE_NAMEN = [
    "vindex", "palette0", "vbl_flag", "magic_doit", "elfe_kptr", "leave_flag",
    "magic_offs", "posx", "posy", "elfe", "elfe_ani", "elfe_anidelay",
    "elfe_fcount", "elfe_fdelay", "magic_offstab", "megaf_x", "megaf_y",
    "magic_x", "sprite_00", "background", "flogo", "magic_buffer",
    "overfunkel", "plot_buffer", "plot_buffer2", "workbase", "stars",
]

# Die Stücke von FAIRY.S im Binärcode: (erste Marke in FAIRY.S, Marke dahinter,
# Anfang in Hunk 1).  Thalions Programm hat sie anders angeordnet als die
# freigegebene Datei.
FAIRY_STUECKE = [
    ("level3", "make_magic", 0xD88),
    ("make_magic", "fairy_ende", 0x316),
]

# Unsere Namen für Stellen, die FAIRY.S nicht benennt (Thalions Namen sind dort
# unbekannt).  (Hunk, Versatz): Name
UNSERE_NAMEN = {
    (2, 0x0000): "Palette_unten_quelle",   # eingeblendet nach Palette_unten
    (2, 0x0040): "Palette_oben_quelle",    # eingeblendet nach palette0
    (2, 0x1CE22): "Flugbahn",              # elfe_kptr am Anfang ($1C6)
    (3, 0x0000): "Anfangsfarben",          # nach $DFF180/$1A0 in $D5E
    (3, 0x0060): "Palette_unten",          # Copperliste ab Zeile 134 ($CD6)
    (3, 0x00F0): "Schirm_arbeit",          # Schirme_tauschen ($C0A)
    (3, 0x00F4): "Schirm_zeigen",          # Schirme_tauschen, Copperliste
    (1, 0x0D12): "Farbwechsel_register",   # Copperliste ($CD0)
}

# Reiner Speichercode und Tabellen aus Hunk 1: (Name, von, bis, Beleg).
# Namen unsere, die Routinen Thalions.
HUNK1_STUECKE = [
    ("Schirme_tauschen", "code", 0x0C0A, 0x0C2C,
     "bsr $C0A in der Hauptschleife ($226).  Veraendert d0."),
    ("Farben_einblenden", "code", 0x10D0, 0x1118,
     "a0 Sollfarben, a1 Istfarben, d7 Anzahl: ein Schritt je Aufruf ($1E8).\n"
     "; Veraendert d0-d5/d7/a0/a1."),
    ("Farben_ausblenden", "code", 0x1118, 0x1148,
     "a0 Farben, d7 Anzahl: ein Schritt nach Schwarz je Aufruf ($29C).\n"
     "; Veraendert d0-d3/d7/a0."),
    ("Farbwechsel_register", "daten", 0x0D12, 0x0D22,
     "Farbversaetze, die die Copperliste ab Zeile 134 aus Palette_unten\n"
     "; neu laedt ($CD0); Ende $FFFF"),
    ("magic_offstab", "daten", 0x1188, 0x11D4,
     "lea magic_offstab,a5 in level3; 19 Punkte"),
]

# Hunk 3 ist BSS; Größe aus dem Programmkopf.
HUNK3_GROESSE = 8740

# Probewerte: jeder fremde Name bekommt einen eigenen Bereich.
PROBE_BASIS = 0x10000000
PROBE_SCHRITT = 0x00100000


def vasm():
    return os.environ.get("VASM", "vasmm68k_mot")


def probe_uebersetzen():
    """FAIRY.S unverändert übersetzen, fremde Namen als Probewerte."""
    os.makedirs(BUILD, exist_ok=True)
    quelle = os.path.join(BUILD, "fairy_probe.s")
    ziel = os.path.join(BUILD, "fairy_probe.bin")
    with open(quelle, "w") as f:
        f.write("; erzeugt von tools/fantasy_auszug.py -- nur zum Vergleich\n")
        for name, wert, _ in WERTE:
            f.write(f"{name}\t= {wert}\n")
        # waitblit wie auf dem Amiga, damit die Längen stimmen
        f.write("waitblit\tmacro\n.\\@:\tbtst\t#14,$dff002\n\tbne.s\t.\\@\n\tendm\n")
        for i, name in enumerate(FREMDE_NAMEN):
            f.write(f"{name}\t= ${PROBE_BASIS + i * PROBE_SCHRITT:08x}\n")
        f.write("\tinclude\t\"FAIRY.S\"\n")
        f.write("fairy_ende:\n")
        marken = sorted({m for a, b, _ in FAIRY_STUECKE for m in (a, b)})
        for m in marken:
            f.write(f"\tdc.l\t{m}\n")
    r = subprocess.run([vasm(), "-Fbin", "-m68000", "-no-opt", "-quiet",
                        "-I" + URCODE, "-o", ziel, quelle],
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise Fehler("FAIRY.S geht nicht durch vasm:\n" + r.stdout + r.stderr)
    daten = open(ziel, "rb").read()
    n = len(marken)
    adr = struct.unpack(f">{n}I", daten[-4 * n:])
    return daten[:-4 * n], dict(zip(marken, adr))


def gleiche_wirkung(p, b):
    """ADD/SUB/AND/OR #n,Dn (vasm) gegen ADDI/SUBI/ANDI/ORI #n,Dn (Thalion)."""
    lang = {0xD000: 0x0600, 0x9000: 0x0400, 0xC000: 0x0200, 0x8000: 0x0000}
    if p & 0x003F != 0x003C:            # Quelle #n
        return False
    op = p & 0xF000
    if op not in lang:
        return False
    reg = (p >> 9) & 7
    groesse = (p >> 6) & 3
    if groesse == 3:
        return False
    return b == lang[op] | (groesse << 6) | reg


def vergleichen(probe, marken, h1, rel1):
    """Stücke vergleichen; gibt {Name: (Hunk, Versatz)} zurück."""
    adressen = {}
    geduldet = 0
    for anf, ende, bin_anf in FAIRY_STUECKE:
        p_von, p_bis = marken[anf], marken[ende]
        i = 0
        while i < p_bis - p_von:
            bo = bin_anf + i
            po = p_von + i
            if bo in rel1:
                zielhunk, ziel = rel1[bo]
                pw = struct.unpack_from(">I", probe, po)[0]
                if pw >= PROBE_BASIS:
                    k = (pw - PROBE_BASIS + PROBE_SCHRITT // 2) // PROBE_SCHRITT
                    name = FREMDE_NAMEN[k]
                    zusatz = pw - (PROBE_BASIS + k * PROBE_SCHRITT)
                    wo = (zielhunk, ziel - zusatz)
                    if adressen.setdefault(name, wo) != wo:
                        raise Fehler(f"{name}: zwei Adressen {adressen[name]} und {wo}")
                else:
                    # Marke in FAIRY.S selbst: muss im selben Stück landen
                    ok = False
                    for a2, e2, b2 in FAIRY_STUECKE:
                        if marken[a2] <= pw < marken[e2]:
                            ok = zielhunk == 1 and ziel == b2 + pw - marken[a2]
                    if not ok:
                        raise Fehler(f"Hunk 1 ${bo:x}: interne Marke ${pw:x} zeigt "
                                     f"nach H{zielhunk}:${ziel:x}")
                i += 4
                continue
            if probe[po] != h1[bo]:
                # Bcc/BSR mit 16-Bit-Weite über die Stückgrenze: das Ziel
                # muss dasselbe sein, die Weite ist es nicht.
                if i % 2 == 0 and i >= 2:
                    op_p = struct.unpack_from(">H", probe, po - 2)[0]
                    op_b = struct.unpack_from(">H", h1, bo - 2)[0]
                    if op_p == op_b and op_p & 0xF0FF == 0x6000:
                        ziel_p = po + struct.unpack_from(">h", probe, po)[0]
                        ziel_b = bo + struct.unpack_from(">h", h1, bo)[0]
                        erwartet = None
                        for a2, e2, b2 in FAIRY_STUECKE:
                            if marken[a2] <= ziel_p < marken[e2]:
                                erwartet = b2 + ziel_p - marken[a2]
                        if erwartet != ziel_b:
                            raise Fehler(f"Hunk 1 ${bo - 2:x}: Sprung nach ${ziel_b:x}, "
                                         f"FAIRY.S erwartet {erwartet}")
                        i += 2
                        continue
                if i % 2 == 0 and gleiche_wirkung(
                        struct.unpack_from(">H", probe, po)[0],
                        struct.unpack_from(">H", h1, bo)[0]):
                    geduldet += 1
                    i += 2
                    continue
                raise Fehler(f"FAIRY.S weicht ab: Hunk 1 ${bo:x} "
                             f"(Probe ${po:x}): {h1[bo]:02x} statt {probe[po]:02x}")
            i += 1
    fehlend = [n for n in FREMDE_NAMEN if n not in adressen]
    if fehlend:
        raise Fehler("ohne Adresse: " + " ".join(fehlend))
    return adressen, geduldet


def namen_sammeln(adressen):
    namen = {}
    for name, wo in adressen.items():
        namen.setdefault(wo, name)
    for wo, name in UNSERE_NAMEN.items():
        if wo in namen and namen[wo] != name:
            raise Fehler(f"{wo}: {name} und {namen[wo]}")
        namen.setdefault(wo, name)
    return namen


def dc_ausgabe(f, h1, rel1, von, bis, namen, lokale):
    """Hunk-1-Stück als dc.w; Relokationen als dc.l Name+Zusatz."""
    i = von
    worte = []

    def raus():
        if worte:
            f.write("\tdc.w\t" + ",".join(f"${w:04x}" for w in worte) + "\n")
            worte.clear()
    while i < bis:
        if i in rel1:
            raus()
            zielhunk, ziel = rel1[i]
            if zielhunk == 1 and von <= ziel < bis:
                f.write(f"\tdc.l\t{lokale}+${ziel - von:x}\n")
            else:
                name, zusatz = name_zu(zielhunk, ziel, namen)
                f.write(f"\tdc.l\t{name}{'+' if zusatz >= 0 else '-'}${abs(zusatz):x}\n"
                        if zusatz else f"\tdc.l\t{name}\n")
            i += 4
            continue
        worte.append(struct.unpack_from(">H", h1, i)[0])
        if len(worte) == 8:
            raus()
        i += 2
    raus()


def name_zu(hunk, ziel, namen):
    if (hunk, ziel) in namen:
        return namen[(hunk, ziel)], 0
    # nächster Name darunter im selben Hunk
    kand = [(o, n) for (h, o), n in namen.items() if h == hunk and o <= ziel]
    if not kand:
        raise Fehler(f"Relokation nach H{hunk}:${ziel:x} ohne Namen")
    o, n = max(kand)
    return n, ziel - o


def main():
    datei = os.path.join(AMBERFILES, "Fantasy_intro")
    hunks = read_hunks(open(datei, "rb").read())
    inhalt, relok = entpacke(hunks)
    h1 = inhalt[1]
    rel1 = {o: (n, struct.unpack_from(">I", h1, o)[0]) for o, n in relok[1]}
    if relok[2] or relok[3] or relok[4]:
        raise Fehler("Relokationen ausserhalb von Hunk 1 -- unerwartet")

    probe, marken = probe_uebersetzen()
    adressen, geduldet = vergleichen(probe, marken, h1, rel1)
    namen = namen_sammeln(adressen)

    # Jede Relokation in den übernommenen Hunk-1-Stücken braucht einen Namen
    for name, _, von, bis, _ in HUNK1_STUECKE:
        for o in range(von, bis):
            if o in rel1:
                zh, z = rel1[o]
                if not (zh == 1 and von <= z < bis):
                    name_zu(zh, z, namen)

    open(os.path.join(BUILD, "fantasy_grafik.bin"), "wb").write(inhalt[2])

    with open(os.path.join(BUILD, "fantasy_werte.i"), "w") as f:
        f.write("; erzeugt von tools/fantasy_auszug.py -- nicht bearbeiten\n")
        f.write("; Konstanten, die FAIRY.S benutzt und nicht definiert.\n")
        for name, wert, beleg in WERTE:
            f.write(f"{name}\t= {wert}\t\t; {beleg}\n")

    with open(os.path.join(BUILD, "fantasy_daten.i"), "w") as f:
        f.write("; erzeugt von tools/fantasy_auszug.py -- nicht bearbeiten\n")
        f.write("; Quelle: Fantasy_intro (Thalion), beim Bau entpackt.\n\n")
        f.write("\tSECTION\tFee_daten,data\n")
        f.write("; Hunk 2: Grafik, Paletten, Flugbahn\n")
        f.write("Fantasy_grafik:\n\tincbin\t\"fantasy_grafik.bin\"\n\teven\n")
        for (h, o), n in sorted(namen.items()):
            if h == 2:
                f.write(f"{n}\tequ\tFantasy_grafik+${o:x}\n")
        for art, abschnitt in (("daten", "Fee_daten,data"), ("code", "Fee_code,code")):
            f.write(f"\n\tSECTION\t{abschnitt}\n")
            f.write(f"; Hunk 1: Thalions {'Tabellen' if art == 'daten' else 'reiner Speichercode'}\n")
            for name, a, von, bis, beleg in HUNK1_STUECKE:
                if a != art:
                    continue
                f.write(f"\n; {beleg}\n{name}:\n")
                dc_ausgabe(f, h1, rel1, von, bis, namen, name)
        f.write("\n\tSECTION\tFee_bss,bss\n")
        f.write("; Hunk 3: Thalions Variablen, in Originalanordnung\n")
        f.write("Fantasy_variablen:\n")
        pos = 0
        for (h, o), n in sorted(namen.items()):
            if h != 3:
                continue
            if o > pos:
                f.write(f"\tds.b\t{o - pos}\n")
                pos = o
            f.write(f"{n}:\n")
        f.write(f"\tds.b\t{HUNK3_GROESSE - pos}\n")

    print(f"  FAIRY.S gegen Fantasy_intro: gleich, {geduldet} Befehle in "
          f"Thalions Kurzform (ADDI/SUBI/ANDI/ORI)")
    for n in FREMDE_NAMEN:
        h, o = adressen[n]
        print(f"    {n:14s} H{h}:${o:x}")


if __name__ == "__main__":
    try:
        main()
    except Fehler as e:
        sys.exit(f"fantasy_auszug.py: {e}")

#!/usr/bin/env python3
"""
amiga_programm.py -- Thalions Programme ohne Quelltext, beim Bau.

    python3 tools/amiga_programm.py intro     Ambermoon_intro
    python3 tools/amiga_programm.py extro     Ambermoon_extro (Imploder)

Zu diesen Programmen gibt es keinen Quelltext.  Nach Leitziel 1 ist dann der
Binaercode selbst Thalions Code (docs/11-Intro-Extro.md, 4.5 und 5.6): Er
wird beim Bau unveraendert uebernommen, wie Thalions Rasterer aus AM2_CPU,
und zur Laufzeit nie gelesen.  Das Werkzeug schreibt nach `build/`:

    <name>_hN.bin    Datenhunks ohne Relokationen
    <name>_hunks.i   der Codehunk und die Datenhunks mit Relokationen als
                     dc.w, jede Relokation als dc.l <Marke>N+Versatz; die
                     anderen Datenhunks als incbin, die BSS-Hunks als ds.b.
                     Marken wie die Hunk-Nummern (Intro_h0 ..., Extro_h1 ...).

K1 (wie beim Fantasy-Intro, docs/11 7.2): Operanden, die auf die Hardware
zeigen, werden auf unsere Schicht gebogen, sonst nichts:

    $00DFF000-$00DFF1FF   -> Amiga_register+Versatz (Schattenblock)
    $00BFE001             -> Amiga_cia_a (CIA-A, Port A: linke Maustaste)
    $00000004             -> Exec_zeiger (ExecBase; nur die Stellen
                             movea.l $4,An, die der Rahmen braucht)

Thalion spricht die Hardware meist ueber `lea $DFF000,a6` an; mit der
gebogenen Basis landen auch alle a6-Zugriffe im Schattenblock.  Die Zahl
der Stellen ist je Programm festgeschrieben (Kartierung): Weicht sie ab, ist
es eine andere Fassung, und der Bau bricht ab.

K2 (Nutzer, 2026-09-30): Thalion startet einen Blit, indem er BLTSIZE
schreibt.  Im Schattenblock ist das nur eine Speicherstelle; also wird an
diesen Stellen das erste Wort des Befehls durch `trap #8` ersetzt.  Der
Trap (amiga/AMIGA_RAHMEN.S, K2_trap) findet die Stelle in K2_tabelle, holt
den Wert wie der Originalbefehl, schreibt ihn, blittet und springt hinter
den Befehl.  Drei Formen kommen vor:

    move.w #imm,$58(a6)   $3D7C   6 Byte
    move.w Dn,$58(a6)     $3D4n   4 Byte
    move.w Dn,(a5)        $3A8n   2 Byte (a5 = lea $58(a6), davor)

Keiner dieser Befehle setzt Bedingungen, die der naechste Befehl liest
(nachgesehen): Dass rte die alten Bedingungen zurueckholt, schadet nicht.

K3 (Nutzer, 2026-10-04: in den Vorspaennen darf Leitziel 1 an Engstellen
weichen, docs/11): An einer Engstelle springt Thalions Programm in unsere
Routine.  Der Befehl dort (6 Byte) wird `jmp <Marke>`; eine Relokation in
seinem Operanden faellt dabei weg.  Die Originalbytes stehen in der Tabelle;
weichen sie ab, bricht der Bau ab.  Unsere Routine fuehrt den ersetzten
Befehl selbst aus, wenn sie in Thalions Weg zurueckspringt.

Im Repository liegt nur dieses Werkzeug.
"""

import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ambtool import read_hunks          # noqa: E402
from imploder_exe import entpacke       # noqa: E402
import paths  # noqa: E402

WURZEL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(WURZEL, "build")
AMBERFILES = paths.amberfiles()

K2_TRAP = 0x4E48            # trap #8
K3_JMP = 0x4EF9             # jmp abs.l

# Je Programm der Aufbau der Fassung 1.20 und die Stellen fuer K1 und K2.
#   hunks   Hunk -> (Art, Groesse); Art CODE, DC (Daten mit Relokationen),
#           BIN (Daten ohne), BSS
#   exec    Versatz des Langworts $4 in movea.l $4,An
#   k2      Versatz des Befehls, der BLTSIZE schreibt -> erstes Wort
#   k3      Versatz des Befehls -> (seine 6 Byte im Original, Marke)
PROGRAMME = {
    "intro": dict(
        datei="Ambermoon_intro", gepackt=False, marke="Intro_h",
        abschnitt="Intro", docs="4",
        hunks={0: ("CODE", 20668), 1: ("DC", 1372), 2: ("BIN", 97904),
               3: ("BIN", 261208), 4: ("BIN", 132640), 5: ("BSS", 74288),
               6: ("BSS", 148844)},
        relok=648,
        dff=39,             # 15 x lea $DFF000,a6 und 24 absolute Operanden
        bfe=7,
        exec=[0x18, 0x3A, 0xD8, 0x108],
        k2={
            0x08EA: 0x3D7C, 0x12BA: 0x3D42, 0x1306: 0x3D7C, 0x1444: 0x3D47,
            0x14D8: 0x3D47, 0x1D50: 0x3A86, 0x1E8A: 0x3D45, 0x1F26: 0x3D45,
            0x1FC6: 0x3D45, 0x204A: 0x3D45, 0x21FA: 0x3A86, 0x2224: 0x3A86,
            0x22A4: 0x3D43, 0x22D0: 0x3D43, 0x2306: 0x3D43, 0x296C: 0x3D7C,
            0x2AC6: 0x3D43, 0x4F2A: 0x3D43,
        },
        # Zoom ($1BAE): nach Beschnitt und Schritttabellen (bsr $2314) in
        # unsere Routine (intro/INTRO_ZOOM.S); ersetzt wird
        # move.w Intro_h5+$11CF8,d0
        # New copper list ($2452, end): show it from the next frame on, not
        # only in the VBL (T11; intro/INTRO_SUP.S).  Replaced is
        # move.l d0,Intro_h5+8; Intro_umschalten also does the following
        # move.l d0,$DFF080 (a K1 site) and returns for Thalion's rts.
        # Clearing before the zoom loop ($137E, whole routine): also plane 4
        # of the hidden screen, which Thalion's VBL clears before the Amiga
        # shows it (white frame, intro/INTRO_SUP.S).  Replaced is
        # movea.l Intro_h5+$1C,a0.
        # End of Thalion's VBL ($2824, all paths meet there): our display
        # after Thalion's work (intro/INTRO_SUP.S, Thalion_vbl_ende).
        # Replaced is tst.w Intro_h5+$12148.
        # The intro without live conversion (E30, docs/11 7.8a;
        # intro/INTRO_SUP.S): the logo phase ($1E0 table, $21E clear,
        # $14E6 a scratch screen for the stages, $2646 the stars in
        # Thalion's VBL, $310 PRESENTS, $3C0 hold), the clouds ($D00 hold
        # and table, $D74/$DA2 the screens filled, $1270 the column copy)
        # and the menu ($F4E hold, $FB2 the hold ends: the menu is
        # converted again, user 2026-10-29, T70).
        # Our clouds ($E3A, the four cloud blits up to $EB2; intro/
        # INTRO_CLOUDS.S): shifted once in the target format, put with the
        # CPU (user, 2026-10-29).
        # The 4-plane scenes in the target format (docs/11 7.8, T63;
        # intro/INTRO_SUP.S): the table at $4F4 and $AD4; our
        # target writers instead of Thalion's CPU at $294E, $1A42, $776,
        # $B40, $169C, $12C0; Thalion's code between fetch and bring at
        # $7BA, $994/$A36; a reader at $6EE.  The covered instructions are
        # named there.
        k3={0x1C98: ("303900011cf8", "Zoom_eigen"),
            0x24BE: ("23c000000008", "Intro_umschalten"),
            0x137E: ("20790000001c", "Zoom_loeschen"),
            0x2824: ("4a7900012148", "Thalion_vbl_ende"),
            0x04F4: ("34827e146100", "Raum_anfang"),
            0x0AD4: ("303c00c87204", "Meteor_anfang"),
            0x0D00: ("303c01007204", "Clouds_begin"),
            0x294E: ("2d7900000018", "Raum_loeschen"),
            0x1A42: ("227900000018", "Sterne_setzen"),
            0x0776: ("227900000018", "Stadt_raum"),
            0x0B40: ("227900000018", "Stadt_meteor"),
            0x07BA: ("6100231e6100", "Stadt_text"),
            0x06EE: ("61000eb632fc", "Bild_holen"),
            0x0994: ("207900012206", "Twinlake_vorher"),
            0x0A36: ("61000c266100", "Twinlake_nachher"),
            0x169C: ("207900012206", "Anim_eor"),
            0x12C0: ("207900000020", "Kopie_vorn_hinten"),
            0x01E0: ("068000000370", "Logo_begin"),
            0x021E: ("20790000001c", "Logo_clear"),
            0x14E6: ("610014582279", "Logo_stages"),
            0x2646: ("2f3900000018", "Logo_stars"),
            0x0310: ("700922d851c8", "Presents_row"),
            0x03C0: ("207900000020", "Logo_end"),
            0x0D74: ("207900012206", "Clouds_background"),
            0x0DA2: ("22790000001c", "Clouds_fill"),
            0x1270: ("207900012206", "Clouds_column"),
            0x0E3A: ("41f90001bf88", "Clouds_draw"),
            0x0F4E: ("203c0000c8c0", "Menu_hold"),
            0x0FB2: ("207900000020", "Menu_begin")}),
    # Imploder: das Programm beginnt mit Hunk 1 (docs/11, 2 und 5.1)
    "extro": dict(
        datei="Ambermoon_extro", gepackt=True, marke="Extro_h",
        abschnitt="Extro", docs="5",
        hunks={1: ("CODE", 12336), 2: ("DC", 9528), 3: ("BIN", 140020),
               4: ("DC", 4), 5: ("BSS", 192), 6: ("BSS", 216720)},
        relok=160,
        dff=24,             # 4 x lea $DFF000,a6 und 20 absolute Operanden
        bfe=4,
        exec=[0x12, 0x34, 0xD2, 0xFC],
        k2={0x04AA: 0x3D7C, 0x04FC: 0x3D7C},
        # Hintergrund in beide Schirme kopiert ($2CA): ins Zielformat
        # bringen (extro/EXTRO_SUP.S).  Ersetzt werden move.l (sp),a4;
        # addq.l #2,a4 und das erste Wort von bsr $5B2.
        # Neue Copperliste ($EBC): die Bildbasis gleich setzen, nicht erst
        # im VBL (T11; extro/EXTRO_SUP.S).  Ersetzt werden bsr $EBC und das
        # erste Wort des folgenden Befehls.
        k3={0x02EC: ("2857548c6100", "Extro_nach_kopie"),
            0x01E8: ("61000cd26100", "Extro_umschalten_1"),
            0x0596: ("610009244a79", "Extro_umschalten_2")}),
}


class Fehler(Exception):
    pass


def hunks_lesen(d):
    """Hunks eines ungepackten Programms: {Nummer: dict(art, groesse, daten,
    rel)}, rel = {Versatz: Zielhunk}."""
    u = lambda o: struct.unpack_from(">I", d, o)[0]
    if u(0) != 0x3F3:
        raise Fehler("kein Amiga-Programm")
    o = 4
    while u(o):
        o += 4 * (u(o) + 1)
    o += 4
    anzahl, erster, letzter = u(o), u(o + 4), u(o + 8)
    o += 12 + 4 * anzahl
    hunks = []
    while o < len(d) and len(hunks) <= letzter - erster:
        art = u(o) & 0x3FFFFFFF
        o += 4
        if art == 0x3EB:
            hunks.append(dict(art="BSS", groesse=u(o) * 4, daten=b"", rel={}))
            o += 4
        elif art in (0x3E9, 0x3EA):
            n = u(o) * 4
            o += 4
            hunks.append(dict(art="CODE" if art == 0x3E9 else "DATA",
                              groesse=n, daten=d[o:o + n], rel={}))
            o += n
        elif art == 0x3EC:
            while True:
                n = u(o)
                o += 4
                if n == 0:
                    break
                ziel = u(o)
                o += 4
                for _ in range(n):
                    hunks[-1]["rel"][u(o)] = ziel
                    o += 4
        elif art == 0x3F2:
            continue
        else:
            raise Fehler(f"unbekannter Hunk-Typ ${art:x}")
    return dict(enumerate(hunks))


def gepackt_lesen(d):
    """Hunks eines Imploder-Programms, entpackt (imploder_exe.py).  Die Art
    kennt der Kopf dort nicht; sie kommt aus der Tabelle."""
    inhalt, relok = entpacke(read_hunks(d))
    return {n: dict(art=None, groesse=len(inhalt[n]), daten=bytes(inhalt[n]),
                    rel={o: z for o, z in relok[n]})
            for n in inhalt}


def aufbau_pruefen(p, hunks):
    ist = {n: h["groesse"] for n, h in hunks.items()}
    soll = {n: g for n, (_, g) in p["hunks"].items()}
    if ist != soll:
        raise Fehler(f"anderer Aufbau als 1.20: {ist}")
    for n, (art, _) in p["hunks"].items():
        h = hunks[n]
        if not p["gepackt"]:
            erwartet = {"CODE": "CODE", "DC": "DATA", "BIN": "DATA", "BSS": "BSS"}[art]
            if h["art"] != erwartet:
                raise Fehler(f"Hunk {n} ist {h['art']}, erwartet {erwartet}")
        if art in ("BIN", "BSS") and h["rel"]:
            raise Fehler(f"Hunk {n} hat Relokationen -- unerwartet")
        if art == "BSS" and any(h["daten"]):
            raise Fehler(f"Hunk {n} sollte leer sein")
        for o in h["rel"]:
            if o % 2:
                raise Fehler("ungerade Relokation")
    anzahl = sum(len(h["rel"]) for h in hunks.values())
    if anzahl != p["relok"]:
        raise Fehler(f"{anzahl} Relokationen, erwartet {p['relok']}")
    return anzahl


def k1_stellen(p, code, rel):
    """Versatz -> Ausdruck fuer jedes Hardware-Langwort im Codehunk."""
    belegt = set()
    for r in rel:
        belegt.update(range(r, r + 4))
    stellen = {}
    dff = bfe = 0
    for o in range(0, len(code) - 3, 2):
        if o in belegt:
            continue
        w = struct.unpack_from(">I", code, o)[0]
        if 0x00DFF000 <= w <= 0x00DFF1FF:
            stellen[o] = f"Amiga_register+${w - 0x00DFF000:03x}"
            dff += 1
        elif w == 0x00BFE001:
            stellen[o] = "Amiga_cia_a"
            bfe += 1
    for o in p["exec"]:
        befehl = struct.unpack_from(">H", code, o - 2)[0]
        wert = struct.unpack_from(">I", code, o)[0]
        if befehl & 0xF1FF != 0x2079 or wert != 4:
            raise Fehler(f"bei ${o - 2:x} steht kein movea.l $4,An")
        stellen[o] = "Exec_zeiger"
    if dff != p["dff"] or bfe != p["bfe"]:
        raise Fehler(f"K1: {dff} x $DFFxxx (erwartet {p['dff']}), "
                     f"{bfe} x $BFE001 (erwartet {p['bfe']})")
    # Keine K1-Stelle darf eine andere oder eine Relokation ueberlappen
    offen = sorted(stellen)
    for a, b in zip(offen, offen[1:]):
        if b < a + 4:
            raise Fehler(f"K1-Stellen ${a:x} und ${b:x} ueberlappen")
    return stellen


def k2_ersetzen(p, code, rel, k1):
    """Das erste Wort jedes BLTSIZE-Schreibbefehls -> trap #8."""
    code = bytearray(code)
    belegt = set()
    for o in list(rel) + list(k1):
        belegt.update(range(o, o + 4))
    for o, erwartet in p["k2"].items():
        wort = struct.unpack_from(">H", code, o)[0]
        if wort != erwartet:
            raise Fehler(f"K2: bei ${o:x} steht ${wort:04x}, erwartet ${erwartet:04x}")
        if erwartet & 0xFFF8 == 0x3D40 or erwartet == 0x3D7C:
            ziel = struct.unpack_from(">H", code, o + (4 if erwartet == 0x3D7C else 2))[0]
            if ziel != 0x58:
                raise Fehler(f"K2: bei ${o:x} kein Schreiben nach $58(a6)")
        if o in belegt or o + 1 in belegt:
            raise Fehler(f"K2: ${o:x} ueberlappt Relokation oder K1")
        struct.pack_into(">H", code, o, K2_TRAP)
    return bytes(code)


def k3_einsetzen(p, code, rel, k1):
    """Jeder K3-Befehl -> jmp <Marke>.  Gibt Code, Relokationen und K1-Stellen
    neu zurueck; die Marke steht wie eine K1-Stelle als dc.l im Operanden."""
    code = bytearray(code)
    rel = dict(rel)
    k1 = dict(k1)
    for o, (alt, marke) in p.get("k3", {}).items():
        if code[o:o + 6].hex() != alt:
            raise Fehler(f"K3: bei ${o:x} steht {code[o:o + 6].hex()}, erwartet {alt}")
        for k in list(k1) + list(p["k2"]):
            if o - 3 <= k < o + 6:
                raise Fehler(f"K3: ${o:x} ueberlappt K1 oder K2 bei ${k:x}")
        for r in list(rel):
            if o - 3 <= r < o + 6:
                if r != o + 2:
                    raise Fehler(f"K3: ${o:x} ueberlappt die Relokation bei ${r:x}")
                del rel[r]
        struct.pack_into(">H", code, o, K3_JMP)
        k1[o + 2] = marke
    return bytes(code), rel, k1


def dc_ausgabe(f, marke, daten, rel, k1):
    """Ein Hunk als dc.w; Relokationen und K1-Stellen als dc.l."""
    worte = []

    def raus():
        if worte:
            f.write("\tdc.w\t" + ",".join(f"${w:04x}" for w in worte) + "\n")
            worte.clear()
    i = 0
    while i < len(daten):
        if i in rel:
            raus()
            ziel = struct.unpack_from(">I", daten, i)[0]
            f.write(f"\tdc.l\t{marke}{rel[i]}+${ziel:x}\n")
            i += 4
        elif i in k1:
            raus()
            f.write(f"\tdc.l\t{k1[i]}\t; K1 ${i:x}\n")
            i += 4
        else:
            worte.append(struct.unpack_from(">H", daten, i)[0])
            if len(worte) == 8:
                raus()
            i += 2
    raus()


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in PROGRAMME:
        sys.exit("Aufruf: amiga_programm.py " + "|".join(PROGRAMME))
    name = sys.argv[1]
    p = PROGRAMME[name]
    marke, ab = p["marke"], p["abschnitt"]
    art = {n: a for n, (a, _) in p["hunks"].items()}
    code_n = next(n for n, a in art.items() if a == "CODE")
    try:
        d = open(os.path.join(AMBERFILES, p["datei"]), "rb").read()
        hunks = gepackt_lesen(d) if p["gepackt"] else hunks_lesen(d)
        anzahl = aufbau_pruefen(p, hunks)
        k1 = k1_stellen(p, hunks[code_n]["daten"], hunks[code_n]["rel"])
        code = k2_ersetzen(p, hunks[code_n]["daten"], hunks[code_n]["rel"], k1)
        code, code_rel, k1 = k3_einsetzen(p, code, hunks[code_n]["rel"], k1)
    except Fehler as e:
        print(f"amiga_programm {name}: {p['datei']}: {e}", file=sys.stderr)
        sys.exit(1)

    os.makedirs(BUILD, exist_ok=True)
    for n in sorted(art):
        if art[n] == "BIN":
            open(os.path.join(BUILD, f"{name}_h{n}.bin"), "wb").write(hunks[n]["daten"])
    with open(os.path.join(BUILD, f"{name}_hunks.i"), "w") as f:
        f.write(f"; build/{name}_hunks.i -- erzeugt von tools/amiga_programm.py aus\n"
                f"; {p['datei']}.  Thalions Programm; nicht von Hand aendern,\n"
                "; nicht ins Repository.\n\n")
        f.write(f"\tSECTION\t{ab}_code,code\n\tcnop\t0,4\n{marke}{code_n}:\n")
        dc_ausgabe(f, marke, code, code_rel, k1)
        f.write(f"\n\tSECTION\t{ab}_daten,data\n")
        f.write("; K2: Ruecksprung hinter dem trap, erstes Wort des Befehls\n"
                "K2_tabelle:\n")
        for o in sorted(p["k2"]):
            f.write(f"\tdc.l\t{marke}{code_n}+${o + 2:x}\n\tdc.w\t${p['k2'][o]:04x}\n")
        f.write("\tdc.l\t0\n")
        for n in sorted(art):
            if art[n] == "DC":
                f.write(f"\tcnop\t0,4\n{marke}{n}:\n")
                dc_ausgabe(f, marke, hunks[n]["daten"], hunks[n]["rel"], {})
        for n in sorted(art):
            if art[n] == "BIN":
                f.write(f"\tcnop\t0,4\n{marke}{n}:\n\tincbin\t\"{name}_h{n}.bin\"\n")
        f.write(f"\n\tSECTION\t{ab}_bss,bss\n")
        for n in sorted(art):
            if art[n] == "BSS":
                f.write(f"\tcnop\t0,4\n{marke}{n}:\n\tds.b\t{hunks[n]['groesse']}\n")
    print(f"  {p['datei']}: {anzahl} Relokationen, K1 an {len(k1)} Stellen "
          f"({p['dff']} $DFFxxx, {p['bfe']} $BFE001, {len(p['exec'])} ExecBase), "
          f"K2 an {len(p['k2'])} Stellen, K3 an {len(p.get('k3', {}))} "
          f"-> build/{name}_hunks.i")


if __name__ == "__main__":
    main()

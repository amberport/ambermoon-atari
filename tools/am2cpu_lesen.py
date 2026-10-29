#!/usr/bin/env python3
"""am2cpu_lesen.py -- Thalions nicht freigegebene Bibliothek lesen.

DEVIATION (goals 1 and 2), docs/17-deviations.md D2: STUECKE and NAMEN say
where the pieces that am2cpu_code.py takes lie in AM2_CPU.

AM2_CPU ist ein Amiga-Hunk-Executable: Thalions uebersetztes Spiel samt der
Bibliothek, deren Quelltext nie freigegeben wurde.  Wo ein Vertrag an den
Aufrufstellen nicht zu erkennen ist (Register, Variablen, Pixelformat), steht
er hier.  Das Werkzeug liest ihn nur: es zerlegt die Datei in Hunks samt
Relokationen, disassembliert eine Routine und schreibt an jede verschobene
Adresse, wohin sie zeigt (Hunk, Versatz, bekannter Name).

**Wozu.**  Die Ergebnisse sind *Vertraege*: was eine Routine liest,
schreibt und zurueckgibt.  Was an Schirm, Blitter oder Betriebssystem
haengt, schreiben wir danach fuer Falcon und ST selbst.  Reinen
Speichercode uebernimmt am2cpu_code.py beim Bau (Nutzer, 2026-09-28;
docs/02 A7); es benutzt NAMEN unten fuer seine Relokationen.  Die Befunde
stehen in docs/02-3D-Renderpfad.md bzw. docs/04.

AM2_CPU bleibt, wo es ist (AMBER_DATEN); dieses Werkzeug legt nichts ab.

**Disassembler.**  GNU objdump mit m68k-Unterstuetzung.  Gesucht wird
``$AMBER_OBJDUMP``, dann ``m68k-*-objdump`` im PATH, dann die Kopien in den
VS-Code-Erweiterungen (atari-st-dev, amiga-debug).

Aufrufe:

    am2cpu_lesen.py hunks                     Hunkliste
    am2cpu_lesen.py dis put_dpoly             Routine nach Name (NAMEN unten)
    am2cpu_lesen.py dis 11:886 --bis 11:a00   nach Hunk:Versatz (hex)
    am2cpu_lesen.py dis 0:21b06 -n 40         die ersten 40 Befehle
    am2cpu_lesen.py wer 11:886                wer springt dorthin (jsr/jmp)
    am2cpu_lesen.py suche 024000ffe548        Bytefolge (hex) in allen Hunks
    am2cpu_lesen.py daten 4:75fe -l 64        Datenbytes als Hexauszug

Ohne ``--bis``/``-n`` endet ``dis`` am ersten rts/rte/jmp, das nicht von
einem Sprung innerhalb der Routine uebersprungen wird (Naeherung).
"""
import argparse
import glob
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import paths

# Bekannte Adressen: (Hunk, Versatz) -> Name.  Jeder Eintrag mit Beleg:
# gefunden ueber eine Aufrufstelle in Thalions uebersetztem Code, deren
# Quelltext wir haben.  Ergaenzen, wenn ein Name belegt ist.
NAMEN = {
    # 3D_MAP.S Draw_faces: "jsr Get_wall_address / jsr put_dpoly".
    # Get_wall_address am Muster and.w #$ff,d0 / lsl.w #2,d0 /
    # move.l 0(a0,d0.w),a0 / rts gefunden, der folgende jsr ist put_dpoly.
    (0, 0x1175E): "Get_wall_address",
    (11, 0x0886): "put_dpoly",
    # 3D_MAP.S make_3dzoom2: einziger jsr dort.
    (11, 0x3978): "draw_zoomshape",
    # 3D_MAP.S M3_DisUpd, Aufruffolge ab Hunk 0 $101FC (Muster des Show-
    # Aufrufs: moveq #9,d6 / move.w #144,d7 / move.l MOVEP_ptr,a0).
    (0, 0x24B30): "Claim_pointer",
    (0, 0x24B6E): "Free_pointer",
    (0, 0x12040): "Calculate_camera_height",
    (0, 0x2A774): "Draw_floor",
    (0, 0x2A70A): "Draw_ceiling",
    (0, 0x120C4): "Draw_horizon",
    (0, 0x10B18): "Draw_dungeon",
    (0, 0x21B06): "Show_MOVEP_screen",
    (0, 0x21592): "Clear_1plane_block",
    # Musik (docs/13): Thalions XREF in VARIOUS.S, Sprungtabelle des Spielers;
    # Set_music springt nach +0/+12/+16, der VBL nach +24.
    (0, 0x2AA0E): "Sa_spieler",       # Thalions Music_routine (docs/13)
    (0, 0x26872): "Set_music",
    (0, 0x12132): "Draw_stars",
    # 3D_MAP.S Draw_horizon: einziger jsr dorthin (Hunk 0 $12116).
    (11, 0x0000): "Insert_horizon",
    # CPU-Fassungen: jede 3D-Routine prueft zuerst Blitter_or_CPU und
    # springt bei $FF hierher (docs/02 A3).
    (0, 0x29A6E): "put_dpoly_CPU",
    (0, 0x2A036): "draw_zoomshape_CPU",
    (0, 0x29A42): "Insert_horizon_CPU",
    # 3D_MAP.S Load_3D_map_data, Folge um "jsr Init_zoom_table" (0:$0FC48)
    # und um die Overlays (0:$0F900..).
    (0, 0x10ACE): "Init_zoom_table",
    (0, 0x23DCE): "Reallocate_memory",
    (0, 0x24050): "File_allocate",
    (0, 0x23D52): "Invalidate_memory",
    (0, 0x24020): "Allocate_CHIP",
    (0, 0x24030): "Allocate_FAST",
    (0, 0x24000): "Clear_memory",
    (0, 0x23F82): "Free_memory",
    (0, 0x250C8): "Load_subfile",
    (0, 0x25162): "Load_unique_subfile",
    (0, 0x25208): "Load_batch_of_subfiles",
    (0, 0x25354): "Load_batch_of_unique_subfiles",
    (0, 0x118E6): "Put_unmasked_MOVEP_block",
    (0, 0x11916): "Put_masked_MOVEP_block",
    # Load_subfile -> $24FFA -> Dateiname: waehlt 1/2/3 nach Map_nr.
    (0, 0x29846): "Dateiname_bilden",
    # 3D_MAP.S Set_D3_light_level (Muster moveq #14,d7 / sub.w d0,d7 /
    # moveq #15,d6), einziger jsr in der Schleife.
    (0, 0x23332): "Fade_colour",
    # Decompress: four jsr, one of them from the game code (0:$01C6A; DISPLAY.S
    # has one jsr Decompress), three from the file loader behind the check
    # cmpi.l #$014C4F42 (1, "LOB").  Lob_core is its loop (am2cpu_code.py).
    (0, 0x26124): "Decompress",
    (0, 0x261E4): "Lob_core",
    # 3D_MAP.S Left90_3D u. a.: "dbra d7,.Loop / jsr Copy_screen /
    # move.l (sp)+,d7 / rts", viermal dasselbe Ziel.
    (0, 0x21456): "Copy_screen",
    # Doppelpuffer (Erkenntnis 200).  Update_screen und Switch_screens nach
    # Aufrufzahl zugeordnet (189 zu 158 jsr in Thalions Quelltext, 39 zu 37);
    # Update_screen ruft Copy_screen, Switch_screens nicht.
    (0, 0x21344): "Init_screens",
    (0, 0x2137A): "Update_screen",
    (0, 0x213C4): "Switch_screens",
    # Blitter A -> D vom sichtbaren in den hinteren Schirm, beschnitten gegen
    # CA_Sp; einziger Aufrufer COMOBS.S Draw_combat_screen.
    (0, 0x215F0): "Duplicate_block",
    (0, 0x27B22): "ScrQ_handler",
    (0, 0x27F50): "HDOBs_zeichnen",
    (0, 0x28050): "HDOBs_loeschen",
    # Kasten und Text, beide beschnitten gegen CA_Sp (Erkenntnis 259).
    # Draw_box: 82 Aufrufer gegen 84 jsr Draw_box im Quelltext.
    # Print_centered_string: Bytefolge aus HULL/WORDS.S (movem.l d0/d2/d6,
    # move.w d0,d6, jsr Strlen), einzige Fundstelle; ruft Put_text_line
    # (114 Aufrufer gegen 115 jsr Put_text_line im Quelltext).
    (0, 0x21E64): "Draw_box",
    (0, 0x26E90): "Print_centered_string",
    (0, 0x239A8): "Put_text_line",
    # Variablen.  Belegt an M3_DisUpd (0:$101A6..), Draw_dungeon, den
    # Operanden von put_dpoly/draw_zoomshape.
    (9, 0x36D4): "MOVEP_ptr",
    (9, 0x36D8): "MPB_ptr",
    (9, 0x3702): "Map_nr",
    (9, 0x9CC0): "CPU_68020_plus",
    (9, 0x9CEA): "Schirm_merker",
    # COMBAT_M.S "move.w d0,Vertical_screen_offset" = 0:$20908; der
    # Copper verschiebt damit DIWSTRT/DIWSTOP (0:$21280).
    (9, 0x9CEC): "Vertical_screen_offset",
    (9, 0x9CF0): "Schirm_vorn",  # Name von uns (LIBRARY.S, B1a)
    # Off_screen/Work_screen: CONTROLS.S "move.l Off_screen,Work_screen ; Reset".
    (9, 0x9CF4): "Off_screen",
    (9, 0x9CF8): "Work_screen",
    (9, 0xED6C): "Zoomscreen1_ptr", (9, 0xED70): "Zoomscreen2_ptr",
    # Der Stapelzeiger der Clip-Areas: "move.l (CA_Sp),a0 / move.l (a0),a0"
    # und dann X1,X2,Y1,Y2 wie Thalions EFFECTS.S ("move.l CA_Sp,a0 ; Get
    # CA"), in allen Blockroutinen ab 0:$2161C und im Vorspann der Zooms.
    (9, 0x9D02): "CA_Sp",
    (6, 0x00C0): "Blitter_or_CPU",
    (9, 0xE6AC): "zoom_screen",
    (9, 0xE6B0): "zoom_screen2",
    (9, 0xE6B6): "Floor_X",
    (9, 0xE6BA): "Floor_Z",
    (9, 0xE6C8): "cls_top",
    (9, 0xE6CA): "cls_bottom",
    (9, 0xE6CC): "dpoly_koos3d",
    (9, 0x0EEE): "seethru_flag",
    (9, 0x0EF0): "scry",
    (9, 0x0EF2): "cx1",
    (9, 0x0EF4): "cy1",
    (9, 0x0EF6): "cx2",
    (9, 0x0EF8): "cy2",
    (4, 0x3D10): "scrx",
    (4, 0x65C4): "Sinus_table",
    (4, 0x76A8): "Race_heights",
    (2, 0x0000): "zoom_ptrbuff",
    (2, 0x0500): "Wall_ptrs",
    # Hunk 2 ist Longword_BSS: Thalions MAIN.S endet mit wall_list0 bei
    # $BC0 (320+32+400 Langworte), dahinter die Bibliothek.  Floor_source_gfx
    # setzt 3D_MAP.S (M3_DisUpd, "Get Floor_buffer_handle,Floor_source_gfx"),
    # definiert es aber nirgends: es ist ein Name der Bibliothek.
    (2, 0x0BC0): "Floor_source_gfx",
    # 3D_MAP.S M3_DisUpd "move.w Y_angle,d0 / neg.w d0" (0:$101BC) und
    # Calculate_camera_height "move.w d2,head_height" (0:$120B8).
    (9, 0x1B6A): "Y_angle",
    (9, 0x1B94): "head_height",
}

HUNK_MAGIC = b"\x00\x00\x03\xf3"
ENDE = re.compile(r"^\s*(rts|rte|jmp)\b")


def amberfiles():
    return paths.amberfiles()


def lies_hunks(pfad):
    """-> Liste von dict(typ, daten, reloc={versatz: zielhunk})."""
    d = open(pfad, "rb").read()
    if d[:4] != HUNK_MAGIC:
        sys.exit("%s: kein Amiga-Hunk-Executable" % pfad)
    u = lambda o: struct.unpack(">I", d[o:o + 4])[0]
    o = 4
    while u(o) != 0:
        o += 4 * (u(o) + 1)
    o += 4
    anzahl, erster, letzter = u(o), u(o + 4), u(o + 8)
    o += 12 + 4 * anzahl
    hunks = []
    while o < len(d) and len(hunks) <= letzter - erster:
        t = u(o) & 0x3FFFFFFF
        o += 4
        if t == 0x3EB:                                   # BSS
            hunks.append(dict(typ="BSS", groesse=u(o) * 4, daten=b"", reloc={}))
            o += 4
        elif t in (0x3E9, 0x3EA):                        # CODE, DATA
            n = u(o) * 4
            o += 4
            hunks.append(dict(typ="CODE" if t == 0x3E9 else "DATA", groesse=n,
                              daten=d[o:o + n], reloc={}))
            o += n
        elif t == 0x3EC:                                 # RELOC32
            while True:
                c = u(o)
                o += 4
                if c == 0:
                    break
                ziel = u(o)
                o += 4
                for _ in range(c):
                    hunks[-1]["reloc"][u(o)] = ziel
                    o += 4
        elif t in (0x3F0, 0x3F1):                        # SYMBOL, DEBUG
            o += 4 + u(o) * 4
        elif t == 0x3F2:                                 # END
            pass
        else:
            sys.exit("unbekannter Hunktyp $%X bei $%X" % (t, o - 4))
    return hunks


def objdump():
    kandidaten = [paths.value("AMBER_OBJDUMP")]
    for n in ("m68k-atari-mintelf-objdump", "m68k-atari-mint-objdump",
              "m68k-amiga-elf-objdump", "m68k-linux-gnu-objdump"):
        kandidaten.append(shutil.which(n))
    # The VS Code extension keeps its tools per platform; on macOS under
    # darwin.  Windows builds through WSL, which is linux.
    plattform = "darwin" if sys.platform == "darwin" else "linux"
    kandidaten += sorted(glob.glob(os.path.expanduser(
        "~/.vscode/extensions/*/sdk/%s/opt/cross-mint/bin/m68k-*-objdump"
        % plattform)))
    kandidaten += sorted(glob.glob(os.path.expanduser(
        "~/.vscode/extensions/*/bin/%s/opt/bin/m68k-*-objdump" % plattform)))
    for k in kandidaten:
        if k and os.access(k, os.X_OK):
            return k
    sys.exit("kein m68k-objdump gefunden (AMBER_OBJDUMP setzen)")


def ort(text):
    """'11:886' -> (11, 0x886); ein Name aus NAMEN geht auch."""
    for k, v in NAMEN.items():
        if v == text:
            return k
    m = re.fullmatch(r"(\d+):(?:\$|0x)?([0-9a-fA-F]+)", text)
    if not m:
        sys.exit("Ort als Hunk:Versatz (hex) oder bekannter Name: %s" % text)
    return int(m.group(1)), int(m.group(2), 16)


def name_von(h, v):
    n = NAMEN.get((h, v))
    return "%d:$%05X%s" % (h, v, " " + n if n else "")


def disassemblieren(hunks, h, von, bis, anzahl):
    daten = hunks[h]["daten"]
    reloc = hunks[h]["reloc"]
    ende = bis if bis is not None else min(len(daten), von + 0x4000)
    with tempfile.NamedTemporaryFile(suffix=".bin") as f:
        f.write(daten)
        f.flush()
        aus = subprocess.run(
            [objdump(), "-D", "-b", "binary", "-m", "m68k:68030",
             "--start-address=0x%x" % von, "--stop-address=0x%x" % ende, f.name],
            capture_output=True, text=True, check=True).stdout
    zeilen = []
    for z in aus.splitlines():
        m2 = re.match(r"^\s*([0-9a-f]+):\t((?:[0-9a-f]{4} ?)+)\s*$", z)
        if m2:                         # Fortsetzungszeile langer Befehle
            if zeilen:
                zeilen[-1][1] += len(m2.group(2).split()) * 2
            continue
        m = re.match(r"^\s*([0-9a-f]+):\t((?:[0-9a-f]{4} ?)+)\s*\t(.*)$", z)
        if not m:
            continue
        adr = int(m.group(1), 16)
        zeilen.append([adr, len(m.group(2).split()) * 2, m.group(3)])
    # Sprungziele der bisher gelesenen Befehle, fuer das Ende-Kriterium
    sprung = re.compile(r"\s*(b[a-z]{1,2}[sw]?|db[a-z]{1,2})\s")
    weitestes = 0
    ausgabe = []
    for i, (adr, n, befehl) in enumerate(zeilen):
        notiz = []
        for o in range(adr + 2, adr + n, 2):
            if o in reloc:
                ziel = struct.unpack(">I", daten[o:o + 4])[0]
                notiz.append("-> " + name_von(reloc[o], ziel))
        # Sprungziele im selben Hunk benennen (nur ohne Relokation:
        # sonst ist die Zahl ein Versatz in einem anderen Hunk)
        if not notiz and re.match(r"\s*(b|db|jsr|jmp)", befehl):
            for t in re.findall(r"\b0x([0-9a-f]+)\b", befehl):
                if (h, int(t, 16)) in NAMEN:
                    notiz.append(NAMEN[(h, int(t, 16))])
        marke = NAMEN.get((h, adr))
        if marke:
            ausgabe.append("%s:" % marke)
        ausgabe.append("  %05x  %-40s%s" % (adr, befehl,
                       ("; " + ", ".join(notiz)) if notiz else ""))
        if anzahl and len([a for a in ausgabe if a.startswith("  ")]) >= anzahl:
            break
        if sprung.match(befehl):
            for t in re.findall(r"\b0x([0-9a-f]+)\b", befehl):
                weitestes = max(weitestes, int(t, 16))
        if bis is None and not anzahl and ENDE.match(befehl) \
                and weitestes <= adr:
            break
    return ausgabe


def wer(hunks, h, v):
    treffer = []
    for j, hk in enumerate(hunks):
        d = hk["daten"]
        for o, ziel in hk["reloc"].items():
            if ziel == h and struct.unpack(">I", d[o:o + 4])[0] == v \
                    and d[o - 2:o] in (b"\x4e\xb9", b"\x4e\xf9"):
                treffer.append("%s %s" % ("jsr" if d[o - 1] == 0xB9 else "jmp",
                                          name_von(j, o - 2)))
    return treffer


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("befehl", choices=("hunks", "dis", "wer", "suche", "daten"))
    p.add_argument("ort", nargs="?")
    p.add_argument("--bis")
    p.add_argument("-n", type=int, default=0, help="hoechstens n Befehle")
    p.add_argument("-l", type=lambda s: int(s, 0), default=64, help="Bytes (daten)")
    p.add_argument("--datei", default=os.path.join(amberfiles(), "AM2_CPU"))
    a = p.parse_args()
    hunks = lies_hunks(a.datei)

    if a.befehl == "hunks":
        for i, hk in enumerate(hunks):
            print("%2d  %-4s %7d Byte  %5d Relokationen" % (
                i, hk["typ"], hk["groesse"], len(hk["reloc"])))
    elif a.befehl == "dis":
        h, v = ort(a.ort)
        bis = ort(a.bis)[1] if a.bis else None
        print("\n".join(disassemblieren(hunks, h, v, bis, a.n)))
    elif a.befehl == "wer":
        h, v = ort(a.ort)
        print("\n".join(wer(hunks, h, v)) or "niemand (per jsr/jmp abs.l)")
    elif a.befehl == "suche":
        muster = bytes.fromhex(a.ort)
        for i, hk in enumerate(hunks):
            o = hk["daten"].find(muster)
            while o >= 0:
                print(name_von(i, o))
                o = hk["daten"].find(muster, o + 1)
    elif a.befehl == "daten":
        h, v = ort(a.ort)
        d = hunks[h]["daten"][v:v + a.l]
        for i in range(0, len(d), 16):
            print("%d:$%05X  %s" % (h, v + i, d[i:i + 16].hex(" ")))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Thalion's extro (Ambermoon_extro) for the ST build: build/st_extro/.

The ST extro has its own layer (extro_st/, docs/05c-ST.md "ST extro"), so
it has its own K3 hooks.  K1 and K2 are the same as on the Falcon; this
tool only uses the functions of tools/amiga_programm.py (unpacking, reading
the hunks, K1, K2, K3, the dc output) and does not change that file.

    K1  $DFFxxx -> Amiga_register+x, $BFE001 -> Amiga_cia_a, the four
        reads of ExecBase -> Exec_zeiger
    K2  each write to BLTSIZE -> trap #8; both sites lie in the part
        Text_scroll replaces, so the trap only counts (K2_trap)
    K3  HOOKS below: Thalion's instruction (6 bytes) -> jmp <label>; the
        original bytes are checked, a different file stops the build

DEVIATION (goals 1 and 2), docs/17-deviations.md D3: the K3 hooks.

Writes build/st_extro/extro_hunks.i and the data hunk as .bin next to it.
Extracted hunks never go into the repository.  The German names
(ap.gepackt_lesen, p["marke"], "daten" ...) are those of amiga_programm.py
and stay as they are.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import amiga_programm as ap             # noqa: E402

OUT = os.path.join(ap.BUILD, "st_extro")

# The K3 hooks of the ST extro: offset in hunk 1 -> (the 6 original bytes,
# our label).  Each label does the replaced instructions itself.  The first
# three are the Falcon's places (extro/EXTRO_SUP.S).
HOOKS = {
    # Thalion has copied the background into both screens ($2CA): the
    # picture in ST format into both ST screens.  Replaced are
    # move.l (sp),a4; addq.l #2,a4 and the first word of bsr $5B2.
    0x02EC: ("2857548c6100", "Extro_after_copy"),
    # New copper list ($EBC): the ST base at once.  Replaced are bsr $EBC
    # and the first word of the next instruction.
    0x01E8: ("61000cd26100", "Extro_switch_1"),
    0x0596: ("610009244a79", "Extro_switch_2"),
    # The scroll text (extro_st/TEXT_ST.S): the mask in a ring.  $420 the
    # mask cleared at the start of a text (lea Extro_h6+$320,a1), $534 the
    # writer's first row (lea Extro_h6+$2B20,a1), $450 the five picture
    # blits, the mask blit and the clear of its last row ($450-$524) by
    # our mixing (lea Extro_h6+$320,a0).
    0x0420: ("43f900000320", "Text_begin"),
    0x0534: ("43f900002b20", "Text_row"),
    0x0450: ("41f900000320", "Text_scroll"),
    # Thalion's wait for one or two VBL after each step ($43A-$449: bsr
    # $F54, tst.w $3E, bne, bsr $F54): wait for 2 VBL (1) since the last
    # step instead, so a step longer than a VBL keeps Thalion's timing.
    # Replaced are bsr $F54 and the first word of tst.w $3E.
    0x043A: ("61000b184a79", "Step_wait"),
}


def main():
    p = dict(ap.PROGRAMME["extro"])
    p["k3"] = HOOKS
    prefix = p["marke"]
    kind = {n: a for n, (a, _) in p["hunks"].items()}
    code_n = next(n for n, a in kind.items() if a == "CODE")
    try:
        d = open(os.path.join(ap.AMBERFILES, p["datei"]), "rb").read()
        hunks = ap.gepackt_lesen(d)
        count = ap.aufbau_pruefen(p, hunks)
        k1 = ap.k1_stellen(p, hunks[code_n]["daten"], hunks[code_n]["rel"])
        code = ap.k2_ersetzen(p, hunks[code_n]["daten"], hunks[code_n]["rel"], k1)
        code, code_rel, k1 = ap.k3_einsetzen(p, code, hunks[code_n]["rel"], k1)
    except ap.Fehler as e:
        sys.exit(f"extro_st_program: {p['datei']}: {e}")

    os.makedirs(OUT, exist_ok=True)
    for n in sorted(kind):
        if kind[n] == "BIN":
            with open(os.path.join(OUT, f"extro_h{n}.bin"), "wb") as f:
                f.write(hunks[n]["daten"])
    with open(os.path.join(OUT, "extro_hunks.i"), "w") as f:
        f.write("; build/st_extro/extro_hunks.i -- written by "
                "tools/extro_st_program.py from\n"
                f"; {p['datei']}.  Thalion's program; do not edit, "
                "not for the repository.\n\n")
        f.write(f"\tSECTION\tExtro_code,code\n\tcnop\t0,4\n{prefix}{code_n}:\n")
        ap.dc_ausgabe(f, prefix, code, code_rel, k1)
        f.write("\n\tSECTION\tExtro_data,data\n")
        f.write("; K2: return address behind the trap, first word of the "
                "instruction\nK2_tabelle:\n")
        for o in sorted(p["k2"]):
            f.write(f"\tdc.l\t{prefix}{code_n}+${o + 2:x}\n\tdc.w\t${p['k2'][o]:04x}\n")
        f.write("\tdc.l\t0\n")
        for n in sorted(kind):
            if kind[n] == "DC":
                f.write(f"\tcnop\t0,4\n{prefix}{n}:\n")
                ap.dc_ausgabe(f, prefix, hunks[n]["daten"], hunks[n]["rel"], {})
        for n in sorted(kind):
            if kind[n] == "BIN":
                f.write(f"\tcnop\t0,4\n{prefix}{n}:\n\tincbin\t\"extro_h{n}.bin\"\n")
        f.write("\n\tSECTION\tExtro_bss,bss\n")
        for n in sorted(kind):
            if kind[n] == "BSS":
                f.write(f"\tcnop\t0,4\n{prefix}{n}:\n\tds.b\t{hunks[n]['groesse']}\n")
    print(f"  {p['datei']}: {count} relocations, K1 at {len(k1)} places, "
          f"K2 at {len(p['k2'])}, K3 at {len(HOOKS)} -> build/st_extro/extro_hunks.i")


if __name__ == "__main__":
    main()

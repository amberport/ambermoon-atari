#!/usr/bin/env python3
"""Thalion's intro (Ambermoon_intro) for the ST build: build/st_intro/.

The ST intro has its own layer (intro_st/, docs/05c-ST.md "ST intro"), so
it has its own K3 hooks.  K1 and K2 are the same as on the Falcon; this
tool only uses the functions of tools/amiga_programm.py (reading the
hunks, K1, K2, K3, the dc output) and does not change that file.

    K1  $DFFxxx -> Amiga_register+x, $BFE001 -> Amiga_cia_a, the four
        reads of ExecBase -> Exec_zeiger
    K2  each write to BLTSIZE -> trap #8 (K2_trap, intro_st/INTRO_ST.S)
    K3  HOOKS below: Thalion's instruction (6 bytes) -> jmp <label>; the
        original bytes are checked, a different file stops the build

DEVIATION (goals 1 and 2), docs/17-deviations.md D3: the K3 hooks.

Writes build/st_intro/intro_hunks.i and the data hunks as .bin next to
it.  Extracted hunks never go into the repository.  The German names
(ap.hunks_lesen, p["marke"], "daten" ...) are those of amiga_programm.py
and stay as they are.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import amiga_programm as ap             # noqa: E402

OUT = os.path.join(ap.BUILD, "st_intro")

# The K3 hooks of the ST intro: offset in hunk 0 -> (the 6 original bytes,
# our label).  Each label does the replaced instruction itself.
HOOKS = {
    # Zoom ($1BAE): after clipping and step tables (bsr $2314) into our
    # zoom (intro_st/ZOOM_ST.S).  Replaced is move.w Intro_h5+$11CF8,d0.
    0x1C98: ("303900011cf8", "Zoom_st"),
    # End of Thalion's VBL ($2522), where all paths meet: our display after
    # Thalion's work, in the same frame (INTRO_ST.S, Vbl_end_hook).
    # Replaced is tst.w Intro_h5+$12148.
    0x2824: ("4a7900012148", "Vbl_end_hook"),
    # End of $2452 (new copper list): the base at once where the list shows
    # a target screen (INTRO_ST.S, Intro_switch; the Falcon's $24BE).
    0x24BE: ("23c000000008", "Intro_switch"),
    # The four-plane scenes in the target format (intro_st/TARGET_ST.S,
    # INTRO_ST.S; the same places as the Falcon's, docs/11 7.8): the table
    # at $4F4 and $AD4; our target writers instead of Thalion's CPU at
    # $294E, $1A42, $776, $B40, $169C, $12C0; Thalion's code between fetch
    # and bring at $7BA, $994/$A36; a reader at $6EE.  The covered
    # instructions are named there.
    0x04F4: ("34827e146100", "Space_begin"),
    0x0AD4: ("303c00c87204", "Meteor_begin"),
    0x294E: ("2d7900000018", "Space_clear"),
    0x1A42: ("227900000018", "Stars_set"),
    0x0776: ("227900000018", "City_space"),
    0x0B40: ("227900000018", "City_meteor"),
    0x07BA: ("6100231e6100", "City_text"),
    0x06EE: ("61000eb632fc", "Picture_fetch"),
    0x0994: ("207900012206", "Twinlake_before"),
    0x0A36: ("61000c266100", "Twinlake_after"),
    0x169C: ("207900012206", "Anim_eor"),
    0x12C0: ("207900000020", "Copy_shown_hidden"),
    # The intro without live conversion (E30; docs/11 7.8b, docs/05c-ST.md;
    # the Falcon's places and names): the logo phase ($1E0 table, $21E
    # clear, $137E the zoom's clear, $14E6 a scratch screen for the stages,
    # $2646 the stars in Thalion's VBL, $310 PRESENTS, $3C0 hold), the
    # clouds ($D00 hold and table, $D74/$DA2 the screens filled, $1270 the
    # column copy) and the menu ($F4E hold, $FB2 table, $1030 the entries).
    # Our clouds ($E3A, the four cloud blits up to $EB2; intro_st/
    # CLOUDS_ST.S): shifted once in ST format, put with the CPU (user,
    # 2026-10-29, the Falcon's way).
    0x01E0: ("068000000370", "Logo_begin"),
    0x021E: ("20790000001c", "Logo_clear"),
    0x137E: ("20790000001c", "Zoom_clear"),
    0x14E6: ("610014582279", "Logo_stages"),
    0x2646: ("2f3900000018", "Logo_stars"),
    0x0310: ("700922d851c8", "Presents_row"),
    0x03C0: ("207900000020", "Logo_end"),
    0x0D00: ("303c01007204", "Clouds_begin"),
    0x0D74: ("207900012206", "Clouds_background"),
    0x0DA2: ("22790000001c", "Clouds_fill"),
    0x1270: ("207900012206", "Clouds_column"),
    0x0E3A: ("41f90001bf88", "Clouds_draw"),
    0x0F4E: ("203c0000c8c0", "Menu_hold"),
    0x0FB2: ("207900000020", "Menu_begin"),
    0x1030: ("49f900000180", "Menu_texts"),
}


def main():
    p = dict(ap.PROGRAMME["intro"])
    p["k3"] = HOOKS
    prefix = p["marke"]
    kind = {n: a for n, (a, _) in p["hunks"].items()}
    try:
        d = open(os.path.join(ap.AMBERFILES, p["datei"]), "rb").read()
        hunks = ap.hunks_lesen(d)
        count = ap.aufbau_pruefen(p, hunks)
        k1 = ap.k1_stellen(p, hunks[0]["daten"], hunks[0]["rel"])
        code = ap.k2_ersetzen(p, hunks[0]["daten"], hunks[0]["rel"], k1)
        code, code_rel, k1 = ap.k3_einsetzen(p, code, hunks[0]["rel"], k1)
    except ap.Fehler as e:
        sys.exit(f"intro_st_program: {p['datei']}: {e}")

    os.makedirs(OUT, exist_ok=True)
    for n in sorted(kind):
        if kind[n] == "BIN":
            with open(os.path.join(OUT, f"intro_h{n}.bin"), "wb") as f:
                f.write(hunks[n]["daten"])
    with open(os.path.join(OUT, "intro_hunks.i"), "w") as f:
        f.write("; build/st_intro/intro_hunks.i -- written by "
                "tools/intro_st_program.py from\n"
                f"; {p['datei']}.  Thalion's program; do not edit, "
                "not for the repository.\n\n")
        f.write(f"\tSECTION\tIntro_code,code\n\tcnop\t0,4\n{prefix}0:\n")
        ap.dc_ausgabe(f, prefix, code, code_rel, k1)
        f.write("\n\tSECTION\tIntro_data,data\n")
        f.write("; K2: return address behind the trap, first word of the "
                "instruction\nK2_tabelle:\n")
        for o in sorted(p["k2"]):
            f.write(f"\tdc.l\t{prefix}0+${o + 2:x}\n\tdc.w\t${p['k2'][o]:04x}\n")
        f.write("\tdc.l\t0\n")
        for n in sorted(kind):
            if kind[n] == "DC":
                f.write(f"\tcnop\t0,4\n{prefix}{n}:\n")
                ap.dc_ausgabe(f, prefix, hunks[n]["daten"], hunks[n]["rel"], {})
        for n in sorted(kind):
            if kind[n] == "BIN":
                f.write(f"\tcnop\t0,4\n{prefix}{n}:\n\tincbin\t\"intro_h{n}.bin\"\n")
        f.write("\n\tSECTION\tIntro_bss,bss\n")
        for n in sorted(kind):
            if kind[n] == "BSS":
                f.write(f"\tcnop\t0,4\n{prefix}{n}:\n\tds.b\t{hunks[n]['groesse']}\n")
    print(f"  {p['datei']}: {count} relocations, K1 at {len(k1)} places, "
          f"K2 at {len(p['k2'])}, K3 at {len(HOOKS)} -> build/st_intro/intro_hunks.i")


if __name__ == "__main__":
    main()

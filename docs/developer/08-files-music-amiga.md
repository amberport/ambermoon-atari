# 8. Files, music, intro and extro

## Game files at run time

Thalion's game files lie in `AMBFILES\` as they ship, only renamed to
8.3 by the build (the name table in `FILES_SUP.S` is the other side of
that renaming; both change together). Nothing is converted in advance.

```
jsr Load_subfile         d1 = Thalion's file number, d0 = entry
  Teildatei_waehlen      1Map_data / 2Map_data / 3Map_data … by map number
  name table             8.3 name, "AMBFILES\" in front if the folder exists
  Eintrag_lesen          head and length table, Fseek, only the entry
  JH_decrypt             Jurie Horneman's XOR stream: Thalion's Crypt_block
  Decompress             LOB, in place: Lob_core (AM2_CPU) unpacks
```

The formats are reverse-engineered in `tools/ambtool.py`. The chain in
`FILES_SUP.S` is ours; the two inner loops are Thalion's: `Crypt_block`
from `HULL/VARIOUS.S` and `Lob_core`, the loop of Thalion's `Decompress`,
taken from `AM2_CPU` at build time (finding 274). Both were checked
against `ambtool.py` over the whole game data. Pyrdacor's format descriptions were the starting point
(`docs/01-Datenfluss-und-Formate.md`).

**Memory** works with Thalion's **handles**, not pointers: `Allocate_*`
returns a handle, `Claim_pointer` an address, `Free_pointer` lets go.
Nothing moves in our memory, but the handles stay, because more than a
hundred call sites use them, and the claim counters behave as in the
original: Thalion's `Out_of_memory` lives on them.

**Save games** as in the original: working files in `AMBFILES\`,
`SAVE.00` is "new game", `SAVE.01`–`SAVE.10` are JH-encrypted, `SAVES`
holds the names and the last save game. Whether the game continues or
starts a new quest is decided by Thalion's `Init_program` from
`Intro_menu_choice`, which the loader or our start menu sets.

The build delivers `Saves` **unchanged** (user, 2026-09-30). Its last save
game is 0, so Thalion's `Init_program` puts up the character editor
(`Chared_Mod`) for a new game, as on the Amiga (finding 261). To start a
test at a later place, `tools/spielstand_setzen.py` moves a copy of a
save game to another map, and with `--saves` it writes a copy of `SAVES`
whose last save game is that one, so "continue" loads it. It changes only
copies of the save game files, never the game code.

File names in our strings are written with a double backslash,
`"AMBFILES\\"`, `"SAVE.00\\PARTYCHR.AMB"`: the build assembles with
`-esc` (chapter 9), so `\\` becomes one backslash and a single one would
start an escape.

The library's texts (messages, names, templates) are in `Text.amb`.
`Lade_texte` loads it at start; where each text lies in it is computed
at build time (`tools/textmarken.py`, `build/textmarken.i`).

## Music: three ways to the speaker

```
Thalion's Set_music (HULL/VARIOUS.S)
  → macro music → Music_routine (MUSIK_YM.S, our switch)
      ├ Sa_spieler: Thalion's Sonic Arranger player from AM2_CPU
      │   writes "Paula" and "CIA", rebound at build time to
      │   Paula_schatten / Cia_b_attrappe (shadow registers in memory)
      │   Musik_vbl → Mischer_vbl (musik/MISCHER.S): the player's tick
      │   once per 1/50 s, then the mixer reads Paula_schatten:
      │     DSP  MUSIK_DSP.A56, samples of the song inside the DSP,
      │          output over SSI → matrix → DAC
      │     CPU  DMA sound (Setbuffer/Buffoper)
      │     16 bit stereo, 12 292 Hz; the sound sets the pace, not the VBL
      └ YM: Big Alec's arrangement from the SNDH file (MUSIK_YM.BIN),
            Thalion's song number → YM song via MUSIK_YM.INF,
            MFP Timer A and D; Timer B stays free for the ST's raster
```

The mixer is a module, `musik/MISCHER.S` (with `mischer_daten.i`,
`mischer_bss.i`, `mischer_chip.i`), shared by the game, the intro and the
extro. The caller hands it a parameter block: the shadow block, the tick
routine, the "music on" byte and the choice; four more fields let the DSP
keep the samples of Thalion's player in AM2_CPU. `MUSIK_SUP.S` fills the
block for the game. `Mischer_remove` stops the DSP and writes back the
sound registers saved at start, so the desktop clicks again afterwards.

`MUSIC=` in `AMBFILES\AMBER.INF` (`shared/SETTINGS.S`, read once by
`MAIN.S`) chooses at start: `OFF`, `DSP` (default), `CPU`, `YM`. The ST
always plays YM; there only `OFF` counts. The YM block (player and
pieces) comes at build time from the SNDH archive's
`big_alec/ambermon.snd` (`tools/ym_auszug.py --sndh`, `AMBER_YMSNDH`).
The SNDH version drives the player with MFP Timer A and B, but Timer B
is the ST's raster, so the tool binds its 36 bytes back to Timer D, as in
the Music Demo, checking each against its expected value. The result must
match by SHA-256 the first 241 630 bytes of the demo block that was
tested on the hardware; only piece 18, which `MUSIK_YM.INF` does not
play, ends earlier. Without the file the YM stays silent. 14 of Thalion's 32 songs
have a YM version. Details, contracts and measurements:
`docs/13-Musik.md`.

## Fantasy intro, intro, extro

These three are Amiga programs, two of them without source. They do not
run on our library but on an emulation of the Amiga hardware they touch:
hunks taken over at build time, hardware operands rebound (K1), blitter
starts turned into a trap (K2), and at a few bottlenecks our own routines
(K3). Intro and extro get their music from the same mixer module as the
game. All of it is in [chapter 10](10-amiga-layer.md).

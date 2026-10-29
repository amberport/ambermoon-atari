# 10. The Amiga layer: fantasy intro, intro, extro

The game reaches the hardware only through Thalion's library (chapter 2),
so rebuilding the library is enough. The three programs around the game
are different. They are Amiga programs that write to the custom chips
directly, and two of them exist only as binaries. For them we do not
rebuild a library. **We emulate the part of the Amiga they touch**, and
let Thalion's code run on top of it.

This chapter describes that layer as it stands. The working document with
the reasoning, the measurements and the history is `docs/11-Intro-Extro.md`
(German); section numbers like *11 §7.8* point there.

## The programs

| | Fantasy intro | Intro | Extro |
|---|---|---|---|
| Thalion's file | `Fantasy_intro` (Imploder) | `Ambermoon_intro` | `Ambermoon_extro` (Imploder) |
| Source | **`FAIRY.S`**, part of the program | none | none |
| Ours | `FANTASY.TOS` | `INTRO.TOS` | `EXTRO.TOS` |
| Unit | `fantasy/fantasy.s` | `intro/intro.s` | `extro/extro.s` |
| Layer below | `fantasy/FEE_SUP.S` (own) | `amiga/AMIGA_RAHMEN.S` | `amiga/AMIGA_RAHMEN.S` |
| Hands back | nothing | menu choice 0/1/3 | 0 |
| Music | none (Thalion's has none) | `INTROMUS.DAT` | `EXTROMUS.DAT` |

The loader `AMBER.TOS` (`lader/lader.s`, plain 68000) starts them in
Thalion's order and passes a single digit on the command line; chapter 3
has the table. Each program also runs alone.

Shared by all three: `amiga/AMIGA_BLIT.S` (the Amiga blitter in software),
`amiga/AMIGA_NOTAUS.S` (emergency exit) and `amiga/AMIGA_MESSEN.S`
(measurement builds). Intro and extro also share `AMIGA_RAHMEN.S`,
`AMIGA_ZIEL.S`, `AMIGA_MUSIK.S` and `amiga_vorspann.i`. Per program only
`start`, the hand-over record `Uebergabe` and the K3 routines (below)
remain: `intro/INTRO_SUP.S`, `extro/EXTRO_SUP.S`.

## The exception to goal 1

These three programs only play; there is no interaction except the
intro's start menu. For them the user allowed (2026-10-04) our own
routines in place of Thalion's at bottlenecks, graphics in Atari format
and precomputation. **Sequence, texts, colours and timing stay
Thalion's**, and so does the start menu. The game has no such exception.

In practice that means three kinds of code in these programs:

| Kind | What | Example |
|---|---|---|
| Thalion's, unchanged | the binary or the source, assembled or taken over at build time | `FAIRY.S`; hunks 0–6 of `Ambermoon_intro` |
| Thalion's, rebound | the same bytes, with hardware operands bent onto our memory (K1) or a blitter start turned into a trap (K2) | `move.w #imm,$58(a6)` → `trap #8` |
| Ours, in Thalion's place | a jump out of Thalion's code into ours (K3), or a routine rewritten after Thalion's | the intro's zoom (`INTRO_ZOOM.S`); `Fee_ablauf` |

## How Thalion's code gets into the build

### With source: `FAIRY.S`

`fantasy/fantasy.s` includes `fee_vorspann.i`, `build/fantasy_werte.i`,
our `FEE_SUP.S`, Thalion's unchanged `FAIRY.S` and
`build/fantasy_daten.i` (`tools/fantasy_bauen.sh`).

1. `tools/fantasy_auszug.py` unpacks `Fantasy_intro`, assembles `FAIRY.S`
   and compares it with the binary (equal apart from 21 short-form
   instructions and 4 branch widths, *11 §3.2*). From the relocations it
   learns where the 27 names `FAIRY.S` uses but does not define lie
   (graphics in hunk 2, variables in hunk 3) and writes them out with
   the constants. Hunk 2 goes in as `incbin`. Thalion's fade, screen swap
   and tables from hunk 1 come along as code.
2. After linking, `tools/fairy_umbiegen.py` finds exactly the ten
   `$DFFxxx` operands in `FAIRY.S` and bends them onto `Amiga_register`
   (K1). Any other count stops the build.
3. Thalion's main sequence (hunk 1 `$110`–`$2B0`) is not part of
   `FAIRY.S` and hangs on copper, CIA and DMA. `Fee_ablauf` (`FEE_SUP.S`)
   is a rewrite of it, in Thalion's order and with Thalion's values; the
   hunk offsets stand in its comments.

### Without source: `tools/amiga_programm.py`

`python3 tools/amiga_programm.py intro|extro` reads the file from
`Amberfiles/` (the extro is unpacked first by `tools/imploder_exe.py`),
splits it into hunks and writes:

- `build/<name>_hunks.i`: the code hunk and the data hunks with
  relocations as `dc.w`, every relocation as `dc.l <Label>N+offset`; the
  BSS hunks as `ds.b`. The labels are `Intro_h0` … `Intro_h6`,
  `Extro_h1` … `Extro_h6` (the extro starts at hunk 1, as the Imploder
  numbers them). Our code addresses Thalion's variables as
  `Intro_h5+$12148`, with the offsets from *11 §4* and *§5*.
- `build/<name>_hN.bin`: data hunks without relocations, for `incbin`.
- `K2_tabelle`: the blitter starts (below).

The table `PROGRAMME` in the tool holds, per program, the hunk layout,
the number of relocations and every rebound place. If any of them
differs, it is another version of the file, and the build stops. Hunks
and disassemblies never enter the repository.

The three kinds of rebinding:

| | What is replaced | By | Count (intro / extro) |
|---|---|---|---|
| **K1** | operands `$DFF000`–`$DFF1FF`, `$BFE001`, and the four `movea.l $4,An` that read ExecBase | `Amiga_register`+offset, `Amiga_cia_a`, `Exec_zeiger` | 39+7+4 / 24+4+4 |
| **K2** | the first word of each instruction that writes BLTSIZE | `trap #8` | 18 / 2 |
| **K3** | one 6-byte instruction at a bottleneck | `jmp <our routine>` | 17 / 3 |

Thalion mostly addresses the chips through `lea $DFF000,a6`. With the
base of that `lea` bent, every `xx(a6)` access lands in our block too, so
K1 needs only the operands, not the 224 `a6` accesses.

K3 checks the six original bytes and refuses to cover a K1, K2 or
relocation site. Our routine performs the covered instruction itself
before it returns into Thalion's path. The K3 sites today:

| Program | Place | Routine | Why |
|---|---|---|---|
| intro | `$1C98` | `Zoom_eigen` (`INTRO_ZOOM.S`) | Thalion zooms with one blit per target column; ours writes each target word once |
| intro | `$24BE` | `Intro_umschalten` | a new copper list takes effect from the next frame (switch timing, below) |
| intro | `$137E` | `Zoom_loeschen` | also clears plane 4 of the hidden screen (white frame before the zoom) |
| intro | `$2824` | `Thalion_vbl_ende` | our display after Thalion's VBL work, before its `rte` |
| intro | `$4F4`, `$AD4`, `$D00` | `Raum_anfang`, `Meteor_anfang`, `Szene_ende` | the table of screens in the target format per scene |
| intro | `$294E`, `$1A42`, `$776`, `$B40`, `$169C`, `$12C0` | `Raum_loeschen`, `Sterne_setzen`, `Stadt_raum`, `Stadt_meteor`, `Anim_eor`, `Kopie_vorn_hinten` | Thalion's CPU writing every frame: ours writes the target |
| intro | `$7BA`, `$994`/`$A36`, `$6EE` | `Stadt_text`, `Twinlake_vorher/nachher`, `Bild_holen` | Thalion's CPU once per scene, between fetch and bring; a reader after fetching |
| extro | `$2EC` | `Extro_nach_kopie` | after Thalion's CPU copy into both screens: bring them into the target format |
| extro | `$1E8`, `$596` | `Extro_umschalten_1/2` | switch timing, as in the intro |

## The Amiga as a block of memory

The programs see an Amiga made of memory:

| Amiga | Ours | Fed by |
|---|---|---|
| custom chips `$DFF000` | `Amiga_register`, a shadow block; offsets `AR_*` in `amiga_vorspann.i` | Thalion's writes land here; we read them in the VBL |
| CIA-A port A (`$BFE001`) | `Amiga_cia_a`, bit 6 = left button | `Amiga_maus` |
| ExecBase (`$4`) | `Exec_zeiger` → `Exec_basis`, `Gfx_basis` | `Bibliothek_anlegen` |
| VBR | 0 (`AttnFlags` = 0: no 68010+, Thalion takes VBR 0) | – |
| level-3 vector `$6C` | Thalion's VBL, where Thalion puts it | our VBL at `$70` jumps there |
| `trap #0` (`$80`) | Thalion's main program in supervisor mode | Thalion sets it |
| `trap #8` (`$A0`) | `K2_trap` | `Amiga_einrichten` |

**The operating system.** Thalion's frame calls exactly five library
functions: `OpenLibrary`, `CloseLibrary`, `Supervisor`, `LoadView`,
`WaitTOF`. `Bibliothek_anlegen` builds a jump table below each base, as
on the Amiga. Every other entry points to `Bib_fehlt`, which notes the
offset; `Fehlende_melden` reports it after the end. No `dos.library`:
the programs read no files (music aside, which we load ourselves).

**The mouse.** `Amiga_maus` hangs in the IKBD mouse vector and turns
each packet into what Thalion reads: the left button in `Amiga_cia_a`
bit 6, the right in `POTGOR` bit 10 (0 = pressed), the movement added
to the counters in `JOY0DAT`.

## One frame

```
VBL ($70) -> Amiga_vbl                      amiga/AMIGA_RAHMEN.S
  _frclock + 1, Vbl_zaehler + 1             TOS waits on _frclock, even after bombs
  Farben_schreiben                          last VBL's colours, only the changed ones
  Anzeige_vbl                               unless THALION_VBL: then at the end of Thalion's VBL
    Zeiger_weg                              background under the last pointer back
    Liste_lesen                             copper list + BPLCON0/BPL1MOD/DIW -> Zustand
    Anzeige_nachfuehren                     changed: convert all, switch; else roll up to 32 lines
                                            behind the beam (Roll_strahl)
    Ebene4_nachfuehren                      intro: plane 4 (stars) every VBL
    Zeiger_zeichnen                         sprites 0/1 as the mouse pointer
    Farben_rechnen                          32 colours -> bank 0, copper colours -> bank 1,
                                            into Farben_neu
  Mischer_vbl                               music: fill the sound buffer (musik/MISCHER.S);
                                            with THALION_VBL also at the end of Thalion's VBL
  jump to ($6C)                             Thalion's level-3 VBL, ends in rte
```

The display comes before the mixer so that it starts right after the
picture; behind the mixer it mostly started inside the picture (measured on the Falcon 2026-10-17). The
mixer keeps three pieces of sound ahead and does not mind the later call.

`Amiga_vbl` replaces the TOS VBL entirely, so it counts `_frclock`
itself: TOS waits on it after bombs, and the emergency exit hung
(found 2026-10-10, *11 §8*, item 7).

The intro defines `THALION_VBL`: while Thalion's handler is installed,
`Amiga_vbl` only jumps there, and `Thalion_vbl_ende` (K3 at the common
end of that handler) calls `Anzeige_vbl` after Thalion's work. Stars,
colours and pointer then appear in the frame Thalion wrote them for.

The fantasy intro has its own VBL (`Fee_vbl`, `FEE_SUP.S`) with the same
duties: picture base, colours, the fairy's sprites, then Thalion's
`level3` from `FAIRY.S`.

## The picture

### From copper list to Falcon screen

On the Amiga, Thalion's copper list names the plane pointers and,
optionally, a wait for a raster line followed by colour changes;
`BPLCON0`, `BPL1MOD` and `DIWSTRT`/`DIWSTOP` name planes, line length and
window. `Liste_lesen` reads exactly that into `Zustand` (`Z_EBENEN`,
`Z_ABSTAND`, `Z_VSTART`/`Z_VSTOP`, `Z_TEILUNG`, `Z_ZEIGER`, and in
`Z_LISTE` the planes the list has pointers for) and the colour changes
into `Teil_farben` (at most 8).

Thalion sometimes writes a list for a new plane count first and
`BPLCON0`/`BPL1MOD` only after the next VBL (the intro's menu, `$FA0` and
`$FAE`); on the Amiga the registers are in place before the list is
shown. So `Anzeige_nachfuehren` lets such a list wait (`Z_LISTE` differs
from `Z_EBENEN` and from the last list's count) and keeps the shown
picture, at most `LISTE_WARTEN` times (tested on the Falcon 2026-10-23, *11 §7.8*).

Thalion's screens are Amiga format: up to five planes, line-interleaved.
The Falcon shows 8 planes, word-interleaved (chapter 6). Two Falcon
screens (`Falcon_vorn` shown, `Falcon_hinten` hidden) take the converted
picture:

- **Changed state** (another screen, window or plane count):
  `Ganz_umsetzen` converts the whole picture into the hidden Falcon
  screen, then the two swap (`Basis_setzen`).
- **Same state:** `Bereich_umsetzen` follows up `ROLLZEILEN` (32) lines
  per VBL on the shown screen, for code that draws into the shown screen
  (the start menu, the intro's stars). `Roll_strahl` first reads the
  Videl's video counter and lets through only lines the beam has already
  passed in this frame, or a band at least `ROLL_VORLAUF` (64) lines
  ahead of it; otherwise the band waits for the next VBL. Writing where
  the Videl reads gave garbage lines in the picture (measured on the Falcon 2026-10-17: 27 % of the
  rolls).
- `Lage_rechnen` places the Amiga window: picture line *r* stands on
  raster line `VSTART`+*r* on the Amiga, on Falcon line
  `VSTART`−`$2C`+*r*−`Anzeige_erste` here. Lines outside the window are
  black.
- The conversion runs on the Falcon blitter, one blit per plane, in HOG
  mode (`Ebene_blit`, `Blit_starten`).

**Lines.** On RGB the layer always sets PAL (Thalion counts VBLs for
50 Hz) and stretches the Videl from 200 to 256 lines (`Videl_256`) where
the timing allows; on VGA it is 240 lines at 60 Hz. The intro is aligned
at the top (`Anzeige_erste` 0); the extro (`ANZEIGE_MITTIG`) cuts its 256
lines evenly at top and bottom.

### Screens in the target format (`AMIGA_ZIEL.S`, *11 §7.8*)

Converting every frame is the main cost. A program can therefore name
Thalion screens that the Videl shows directly: `Schirm_tabelle` with the
macro `SCHIRM` (address, lines, planes). The extro names its two screens
for the whole run (`Extro_h6+$2E90`, 256 lines, 5 planes). The intro
changes the table per scene with `Schirme_wechseln` (a0 = table or 0):
its 4-plane scenes from `$4F4` to `$D00`, 236 lines, the meteor scene
200 (tested on the Falcon 2026-10-25); logo, clouds and menu stay converted.

- `Schirme_anlegen` creates a **target screen** in Falcon format for
  each, with `ZIEL_RAND_ZEILEN` black lines above and below it, and clears it whole.
  The target screen is authoritative. Thalion's Amiga screen stays as a
  **staging buffer**, each line with a "valid" flag.
- `Schirme_wechseln` fetches the old table's screens whole into their
  buffers first, then sets up the new table; the next VBL judges the
  display anew.
- `Anzeige_direkt`: if the copper list shows such a screen, the Videl
  points straight at the target screen; only the bank plane is redrawn
  when the split moves. The window must lie in the screen; above it the
  black margin shows, and below it either the display ends or the screen
  does (the lines below `SCH_ZEILEN` stay black).
- **Blits** are redirected in `Amiga_blit` → `Bl_umlenken`. If only D
  lies in the screen and there is a direct path (today `Bl_ziel_d8`, the
  extro's scroll text), the blit writes the target screen and the staging
  lines become invalid. Otherwise the touched lines are fetched into the
  staging buffer, Thalion's blit runs there unchanged, and the D lines
  are brought back to the target.
- **CPU writes** cannot be redirected. At the places we know (K3), the
  layer brings the lines over afterwards (`Alle_bringen`), or fetches
  them before and brings them after (`Schirm_vorher`, `Schirm_nachher`).
  Where Thalion writes every frame, the intro has its own routine that
  writes the target and marks the buffer lines invalid
  (`Zeilen_ungueltig`; clearing: `Ziel_loeschen`). The list is in
  `intro/INTRO_SUP.S` and *11 §7.8*.
- The format is three values in `amiga_vorspann.i`: `ZIEL_EBENEN`,
  `ZIEL_ZEILE`, `ZIEL_WORT` (Falcon 8, 320, 16). The ST would be 4, 160,
  8; the code computes only with these.

### When a new picture takes effect

Measured on the Falcon (2026-10-09, *11 §7.8*): the Videl latches the picture
base before our VBL runs. A base written in the VBL therefore takes
effect one frame later than on the Amiga, where Thalion sets the copper
list during the frame. Thalion would then draw into the screen that is
still shown. The fix: write the base as soon as Thalion switches, not in
the VBL.

| Program | Where | How |
|---|---|---|
| fantasy intro | `Anzeige_setzen` (Thalion's `$C98`, rewritten) | draws the fairy into the new screen, then writes the base |
| intro | K3 `Intro_umschalten` → `Anzeige_umschalten` | converts a changed picture at once, writes the base |
| extro | K3 `Extro_umschalten_1/2` → `Anzeige_sofort` | sets the base of a target screen at once |

## Colours

The Amiga programs have 32 colours per screen area, and the copper can
change some in the middle of the frame. On the Falcon this becomes
**two colour banks, chosen by plane 5** of each pixel, the same idea as
the game's banks (chapter 6) on a smaller scale:

```
Falcon plane 5 = 0  ->  registers  0-31   bank 0: the 32 colours Thalion wrote to $DFF180
Falcon plane 5 = 1  ->  registers 32-63   bank 1: the same, with the copper's changes
planes 6, 7 = 0
```

- `Farben_rechnen` fills bank 0 from `Amiga_register+AR_COLOR00` and copies
  it to bank 1, then overwrites the registers from `Teil_farben` there,
  all in `Farben_neu`. `Farben_schreiben`, the first thing in the next
  `Amiga_vbl`, writes into the Videl only what differs from `Farben_alt`:
  writing the palette while the picture runs made garbage stripes (tested on the Falcon 2026-10-23,
  *11 §7.8*). So the colours follow Thalion one frame later, as a new
  picture base does.
- The bank plane is set from `Z_TEILUNG`, the raster line the copper
  list waits for (`Bank_setzen`). Without a wait there is only bank 0.
- The fantasy intro is the fixed case: its copper list reloads colours
  20, 21, 22, 29, 30, 31 at raster line `$AE`, picture line 134
  (`WECHSELZEILE`). Planes 5–7 of its Falcon screens are set once and
  never converted (*11 §3.3*).
- Colour words: `Amiga_nach_videl` spreads 4 bits per channel to the
  Videl's 6 through `Vier_nach_acht` and writes the hardware layout
  `$RRGG00BB` directly (chapter 6, "Amiga colours on the Videl").
- Sprite colours 16–31 come from the same registers. Because the copper
  change also reaches sprites, the fairy and the pointer take the bank
  of their line too.

## The blitter

**K2.** Writing BLTSIZE into the shadow block starts nothing. So the
build puts `trap #8` there, and `K2_trap` looks up the trap's return
address in `K2_tabelle`. It takes the value the original instruction
would have written (`#imm`, `Dn` through `$58(a6)` or `(a5)`), stores it,
runs the blit with `Amiga_blit` and continues behind the original
instruction. When Thalion then polls `DMACONR`, the blitter is always
free. None of the replaced instructions sets flags the next one reads.

`FAIRY.S` has no BLTSIZE to catch; there the macro `waitblit` is the
hook (`fee_vorspann.i` → `Blitter_warten`), which runs the blit last set
up.

**`Amiga_blit`** (`AMIGA_BLIT.S`) emulates the Amiga blitter on the CPU:
first/last word masks, shifts with the previous word carried over line
ends, fixed values without `USEx`, ascending and descending mode, every
minterm; afterwards the channel pointers stand behind the blit, as on the
Amiga (the intro relies on it). Line and fill mode are counted in
`Bl_fremd`, not executed; none of the programs uses them.

`Amiga_blit_genau` is the exact reference. In front of it, `Amiga_blit`
looks for a pattern with a tight loop:

| Path | Pattern | Who |
|---|---|---|
| `Bl_schnell_spalte` | one word column, `$CA` or `$E2`, up or down | intro, Thalion's zoom |
| `Bl_schnell_stern` | `$CA`, two words, `ASH` = `BSH` | fantasy intro, stars |
| `Bl_schnell_ca` | `$CA`, A?B:C, C = D | fantasy intro, the logo |
| `Bl_schnell_d8` / `Bl_ziel_d8` | `$D8`, C?B:A, unshifted | extro, scroll text |
| `Bl_schnell_fc`, `_fe` | OR of two or three sources, shifted | intro, space scene |
| `Bl_schnell_f0`, `_00` | copy, clear | all |

`BLIT_PRUEF` runs every fast blit through the exact path as well and
counts differences (`Bl_abweichung`); with it the fast paths are
checked, not trusted.

The **Falcon blitter** (the STE blitter) is used only by our layer: for
converting screens and for stamping sprites, always in HOG mode. The VBL
uses it too; it waits until the blitter is free and restores its
registers afterwards.

## Sprites

The Amiga shows the mouse pointer and the fairy as hardware sprites. We
draw them into the picture:

- **Pointer** (intro menu): `Zeiger_zeichnen` reads, like sprite DMA,
  the pointers `SPR0PT`/`SPR1PT` and each sprite's control words, checks
  `SPREN` in the last `DMACON` write, and draws sprite 0 (and 1 when
  attached: colours 16–31) into the shown Falcon screen, planes 0–4;
  plane 5 keeps the bank. `Zeiger_weg` puts the background back before
  the next conversion. Never into a target screen: that is Thalion's
  drawing surface.
- **Fairy** (`Fee_sprites`, `FEE_SUP.S`): eight sprites, attached in
  pairs, merged into runs; per run the CPU builds mask and four planes,
  the blitter stamps them in (nine blits). Nothing is saved under the
  fairy; the next conversion of that rectangle restores it. The sprites
  lag one frame behind `level3`, so that Thalion's `rte` stays untouched.

## Music (`AMIGA_MUSIK.S`)

On the Amiga the loader hands each program a pointer to the music player
in `Uebergabe+0`. Thalion calls it at `+0` (init), `+12` (start, `d0` =
part), `+16` (stop) and from its VBL at `+24` (the beat).

1. `Musik_laden` (before `Super`) reads `INTROMUS.DAT` / `EXTROMUS.DAT`
   from `AMBFILES\`, else next to the program. These are Thalion's
   `Intro_music` / `Extro_music`, renamed to 8.3 by the build; they are
   read at run time (goal 2).
2. Length and the 27 hardware operands must match
   `build/<name>_musik.i`, written by `tools/musik_k1.py` from the game
   data. Only then the operands are bent (Paula onto `Musik_schatten`,
   the CIAs onto a dummy) and `Uebergabe+0` points to `Musik_tabelle`;
   otherwise it stays `Musik_stumm`, a table of `rts`.
3. `Musik_mischen` starts the music session's mixer (`musik/MISCHER.S`,
   chapter 8) with a parameter block: the shadow block, the beat
   (`+24` of the player) and Thalion's "music on" word (intro
   `Intro_h5+$12148`, extro `Extro_h5+$38`). The mixer calls the beat
   once per 1/50 s of sound, so `+24` in our table is empty.
4. `MUSIC=` in `AMBER.INF` (`shared/SETTINGS.S`, `AMBFILES\` first):
   `OFF` silent, `CPU` the processor mixes, everything else the DSP.

## Leaving, also after a crash (`AMIGA_NOTAUS.S`)

All three programs replace vectors (VBL, mouse, traps) and the video
mode. If they end any other way than through their own removal
(`Amiga_abraeumen`, `Fee_abraeumen`), those would point into freed
memory.

- `Notausgang_einhaengen`, right after `Super`, hangs into `etv_term`
  (`$408`), which TOS calls in every `Pterm`, and in front of the crash
  vectors 2–8. EmuTOS shows a text after a crash and waits for a key
  before `Pterm`; until then our VBL and mode would keep running.
- The handler masks interrupts, gives the VBL its old vector, drops to
  level 3 and runs the program's removal (`NOTAUS_ABRAEUMEN`). Each step
  has a flag (`Ab_modus`, `Ab_maus`, `Ab_vbl`, `Ab_absturz`), so a second
  call after a regular end does nothing. No GEMDOS inside: `Pterm` is
  still in GEMDOS.
- After a crash it jumps on into the TOS handler with registers and frame
  unchanged; TOS 4.04 draws the bombs on the desktop, and `BOMBEN.TOS`
  reads `$380` as for the engine (chapter 3).

## Diagnostic builds

`build_falcon.sh` builds them next to the delivered programs into
`ATARI/AMBFILES/` (for now; they are to move behind a switch).

| Switch | Effect | Builds |
|---|---|---|
| `AMIGA_MESSEN` | Timer A samples the PC about 1000 times a second; per 64 bytes of program, blits vs. display vs. rest, per second | `INTROMES`, `INTROPRF`, `EXTROPRF`, the `*DIAG` builds |
| `STRAHL` | where the Videl reads when we write into a screen or enter the VBL (`amiga_strahl.i`, `Tk_vbl`) | `INTRDIAG`, `EXTRDIAG`, `FEEDIAG` |
| `MESS_ENDE=n` | end after *n* seconds, for hardware runs | the `*DIAG` builds |
| `BLIT_PRUEF` | fast blits against the exact path | `INTROPRF`, `EXTROPRF`, `FEEPRUEF` |
| `ZOOM_PRUEF` | our zoom against Thalion's | with `AMIGA_MESSEN` |
| `FEE_CPU`, `FEE_MESSEN` | fantasy intro: convert with the CPU; count late frames | `FEEMESSC`, `FEEMESSB` |
| `ABSTURZTEST` | an `illegal` after 250 VBL, to test the emergency exit | `FEEABST`, `INTRABST`, `EXTRABST` (built separately) |

`FREQ.TOS` (`lader/freq.s`) measures the machine's frame rate: Thalion's
timing is in VBLs.

## The ST

None of the three programs runs on the ST yet; each checks for a Falcon
(`Falcon_pruefen`, cookie `_MCH`) and stops otherwise. The plan is
decided (*11 §7.10*, S1–S5): 200 lines, colour reduction by the `wurzel`
method at build time, register 0 reserved for colour 0, the intro first
(four of its six scenes have four planes and fit the ST format plane by
plane through the target-format machinery), then the extro, then the
fantasy intro. On the ST there is no music in intro and extro: no YM
version of those songs is known.

## Files

| File | What it does |
|---|---|
| `lader/lader.s` | `AMBER.TOS`: the program chain |
| `lader/freq.s` | `FREQ.TOS`: frame rate |
| `fantasy/fantasy.s`, `fee_vorspann.i` | fantasy intro unit; `waitblit` → `Blitter_warten`, register offsets |
| `fantasy/FEE_SUP.S` | the layer under `FAIRY.S`: start, `Fee_ablauf`, `Fee_vbl`, conversion, sprites, mouse |
| `intro/intro.s`, `extro/extro.s` | units: vorspann, `*_SUP.S`, then `build/<name>_hunks.i` |
| `intro/INTRO_SUP.S`, `extro/EXTRO_SUP.S` | `start`, `Uebergabe`, `Schirm_tabelle`, the K3 routines |
| `intro/INTRO_ZOOM.S` | our zoom (K3 `$1C98`) |
| `amiga/AMIGA_RAHMEN.S` | intro and extro: OS emulation, vectors, VBL, display, colours, pointer, mouse, `K2_trap` |
| `amiga/AMIGA_ZIEL.S` | screens in the target format |
| `amiga/AMIGA_BLIT.S` | `Amiga_blit`: the Amiga blitter on the CPU |
| `amiga/AMIGA_MUSIK.S` | loading and binding Thalion's music player |
| `amiga/AMIGA_NOTAUS.S` | emergency exit |
| `amiga/AMIGA_MESSEN.S`, `amiga_strahl.i` | measurement builds |
| `amiga/amiga_vorspann.i` | constants: TOS, Videl, blitter, `AR_*`, screen format, `SCHIRM` |
| `tools/amiga_programm.py` | hunks, K1, K2, K3 for intro and extro |
| `tools/fantasy_auszug.py`, `fairy_umbiegen.py` | the fantasy intro's extraction and K1 |
| `tools/imploder_exe.py` | Imploder unpacker |
| `tools/musik_k1.py` | the music files' hardware operands |
| `tools/fantasy_bauen.sh`, `amiga_bauen.sh` | single builds into `build/` |

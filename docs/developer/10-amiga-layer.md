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
| Layer below | `fantasy/FEE_SUP.S`, `STARS_FALCON.S` (own) | `amiga/AMIGA_RAHMEN.S` | `amiga/AMIGA_RAHMEN.S` |
| Hands back | nothing | menu choice 0/1/3 | 0 |
| Music | none (Thalion's has none) | `INTROMUS.DAT` | `EXTROMUS.DAT` |
| On the ST | `FANTSYST.TOS`, `fantasy_st/` | `INTROST.TOS`, `intro_st/` | `EXTROST.TOS`, `extro_st/` |

The loader `AMBER.TOS` (`lader/lader.s`, plain 68000) starts them in
Thalion's order and passes a single digit on the command line; chapter 3
has the table. Each program also runs alone.

Intro and extro share the Amiga layer in `amiga/`: `AMIGA_RAHMEN.S`,
`AMIGA_ZIEL.S`, `AMIGA_BLIT.S` (the Amiga blitter in software),
`AMIGA_MUSIK.S`, `AMIGA_MESSEN.S` (measurement builds) and
`amiga_vorspann.i`. Per program only `start`, the hand-over record
`Uebergabe` and the K3 routines (below) remain: `intro/INTRO_SUP.S` with
`INTRO_ZOOM.S` and `INTRO_CLOUDS.S`, `extro/EXTRO_SUP.S`. The fantasy
intro has its own layer and takes from `amiga/` only the emergency exit
`AMIGA_NOTAUS.S`. The ST builds its three programs in their own folders
(below, "The ST").

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
| Ours, in Thalion's place | a jump out of Thalion's code into ours (K3), a hook Thalion's code calls, or a routine rewritten after Thalion's | the intro's zoom (`INTRO_ZOOM.S`) and clouds (`INTRO_CLOUDS.S`); `Fee_ablauf`, `Magic_falcon` |

## How Thalion's code gets into the build

### With source: `FAIRY.S`

`fantasy/fantasy.s` includes `fee_vorspann.i`, `build/fantasy_werte.i`,
our `FEE_SUP.S` and `STARS_FALCON.S`, Thalion's unchanged `FAIRY.S`,
`build/fantasy_daten.i` and the graphics in Falcon format from
`build/falcon_fantasy/` (`tools/fantasy_bauen.sh`). It stops the build
if the graphics have another row count, line length, bank row or fairy
frame size than `FAIRY.S` and our layer expect.

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
4. `tools/fantasy_st_data.py --falcon`, the ST's tool with a Falcon
   switch, writes background, fairy and logo in Falcon format (8 planes,
   the Amiga colours, nothing reduced) and the stars as compiled code
   per image and shift (decision E30: the same method on both machines,
   *11 §7.8a*). Nothing of the fantasy intro is converted at run time.

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
| **K3** | one 6-byte instruction at a bottleneck | `jmp <our routine>` | 29 / 3 |

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
| intro | `$1E0`, `$4F4`, `$AD4`, `$D00` | `Logo_begin`, `Raum_anfang`, `Meteor_anfang`, `Clouds_begin` | the table of screens in the target format per scene |
| intro | `$3C0`, `$F4E`, `$FB2` | `Logo_end`, `Menu_hold`, `Menu_begin` | Thalion changes the screens' format: the picture is held (`Display_hold`), at `$FB2` the converted menu begins (`Display_release`) |
| intro | `$294E`, `$1A42`, `$776`, `$B40`, `$169C`, `$12C0` | `Raum_loeschen`, `Sterne_setzen`, `Stadt_raum`, `Stadt_meteor`, `Anim_eor`, `Kopie_vorn_hinten` | Thalion's CPU writing every frame: ours writes the target |
| intro | `$21E`, `$2646`, `$310`, `$DA2`, `$1270` | `Logo_clear`, `Logo_stars`, `Presents_row`, `Clouds_fill`, `Clouds_column` | the same in the logo phase and the cloud scene: clearing, the stars in Thalion's VBL, the PRESENTS wipe, the fill, two columns of the menu picture |
| intro | `$E3A` | `Clouds_draw` (`INTRO_CLOUDS.S`) | Thalion's four cloud blits a frame took most of a frame in software; ours puts preshifted clouds straight into the target |
| intro | `$14E6` | `Logo_stages` | Thalion computes the logo's zoom stages in the hidden screen as 4 planes; ours hands it a scratch screen (`Logo_scratch`), so the hidden screen stays a 5-plane target |
| intro | `$7BA`, `$994`/`$A36`, `$6EE`, `$D74` | `Stadt_text`, `Twinlake_vorher/nachher`, `Bild_holen`, `Clouds_background` | Thalion's CPU once per scene, between fetch and bring; a reader after fetching |
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
    Anzeige_nachfuehren                     a target screen: point the Videl at it; else
                                            changed: convert all, switch; else roll up to 32
                                            lines behind the beam (Roll_strahl)
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

The fantasy intro has its own VBL (`Fee_vbl`, `FEE_SUP.S`): picture
base, colours, the fairy (`Fairy_put`), then Thalion's `level3` from
`FAIRY.S`.

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
The Falcon shows 8 planes, word-interleaved (chapter 6). Where a screen
is not in the target format (next section), two Falcon screens
(`Falcon_vorn` shown, `Falcon_hinten` hidden) take the converted picture.
Today that is only the intro's start menu (and a fallback the
measurement build counts, expected 0):

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
  mode, in pieces (`Ebene_blit`, `Blit_starten`; "The blitter", below).

**Lines.** On RGB the layer always sets PAL (Thalion counts VBLs for
50 Hz) and stretches the Videl from 200 to 256 lines (`Videl_256`) where
the timing allows; on VGA it is 240 lines at 60 Hz. The intro is aligned
at the top (`Anzeige_erste` 0); the extro (`ANZEIGE_MITTIG`) cuts its 256
lines evenly at top and bottom.

### Screens in the target format (`AMIGA_ZIEL.S`, *11 §7.8*, *§7.8b*)

Converting every frame is the main cost. A program can therefore name
Thalion screens that the Videl shows directly: `Schirm_tabelle` with the
macro `SCHIRM` (address, lines, planes). The extro names its two screens
for the whole run (`Extro_h6+$2E90`, 256 lines, 5 planes). The intro
changes the table per scene with `Schirme_wechseln` (a0 = table or 0):

| Scene | Thalion's screens | Table from |
|---|---|---|
| logo phase, `$190`–`$3C0` | 320 × 200 × 5 | `$1E0` (`Logo_begin`, `Screens_logo`) |
| space, Twinlake, city, `$4F4`–`$D00` | 320 × 236 × 4 | `$4F4` (`Raum_anfang`) |
| meteors | the same, 200 lines | `$AD4` (`Meteor_anfang`) |
| LYRAMION and the clouds, `$D00`–`$F4E` | 320 × 256 × 4 | `$D00` (`Clouds_begin`, `Screens_clouds`) |
| start menu, from `$F4E` | 320 × 256 × 5 | none: converted (T70) |

The menu stays converted (user, 2026-10-29): in a target Thalion's menu
wrote into the picture shown, and the pointer had to go before every
blit of the highlight; it hung and jumped (T67–T69). Converted, Thalion
writes only its own screens. Under `AMIGA_MESSEN` the measurement counts
what the VBL still converts (`Anz_umgesetzt`, `Anz_gerollt`); outside the
menu it is 0.

- `Schirme_anlegen` creates a **target screen** in Falcon format for
  each, with `ZIEL_RAND_ZEILEN` black lines above and below it, and clears it whole.
  The target screen is authoritative. Thalion's Amiga screen stays as a
  **staging buffer**, each line with a "valid" flag.
- `Schirme_wechseln` fetches the old table's screens whole into their
  buffers first, then sets up the new table; the next VBL judges the
  display anew.
- **The picture is held** where Thalion changes the format of its
  screens with the CPU before the next table comes: logo → space
  (`$3C0`–`$4F4`, 5 → 4 planes), any scene → clouds (`$D00`), clouds →
  menu (`$F4E`–`$FB2`, 4 → 5 planes), and at the meteor scene (`$AD4`),
  whose table comes before Thalion writes the 200-line window.
  `Display_hold` (`AMIGA_RAHMEN.S`) copies the picture shown into the
  hidden Falcon screen, shows it from there and removes the table;
  until a copper list can be shown directly again, nothing is converted.
  At `$FB2` `Display_release` lets the VBL convert the menu.
- `Anzeige_direkt`: if the copper list shows such a screen, the Videl
  points straight at the target screen; only the bank plane is redrawn
  when the split moves. The window must lie in the screen; above it the
  black margin shows, and below it either the display ends or the screen
  does (the lines below `SCH_ZEILEN` stay black).
- **Blits** are redirected in `Amiga_blit` → `Bl_umlenken`. If only D
  lies in the screen (or C = D) and there is a direct path
  (`Bl_ziel_waehlen`), the blit writes the target screen and the staging
  lines become invalid: `Bl_ziel_d8` (`$D8`, the extro's scroll text),
  `Bl_ziel_ca` (`$CA` with C = D), `Bl_ziel_f0` (copy, the logo stages),
  `Bl_ziel_allg` (any other minterm with C = D or without C, the menu
  picture's text). A channel touches a screen by its whole range, not by
  its start; when a blit's first word only gives D = C
  (`Bl_erstes_wort`), the path starts with the second. Otherwise the
  touched lines are fetched into the staging buffer, Thalion's blit runs
  there unchanged, and the D lines are brought back to the target.
- **CPU writes** cannot be redirected. At the places we know (K3), the
  layer brings the lines over afterwards (`Alle_bringen`), or fetches
  them before and brings them after (`Schirm_vorher`, `Schirm_nachher`).
  Where Thalion writes every frame, the intro has its own routine that
  writes the target and marks the buffer lines invalid
  (`Zeilen_ungueltig`; clearing: `Ziel_loeschen`). Every writer marks
  the lines invalid **before** it writes the target, not after. The list
  is in `intro/INTRO_SUP.S` and *11 §7.8*, *§7.8b*.
- **The clouds** before the menu (`INTRO_CLOUDS.S`, K3 at `$E3A`):
  Thalion draws four clouds a frame with `$CA` blits (`$4E2A`), cheap on
  the Amiga, most of a frame through our software blitter (T66).
  `Clouds_prepare` shifts both clouds once at the start into all 16
  positions, in the target's format (per 16-pixel group the inverted
  mask and planes 0–3, the cloud already masked; 2 × 192 KB).
  `Clouds_draw` then writes them with the CPU straight into the target:
  a group the mask covers whole is written, a free one skipped, only the
  rest reads the target. Pixel for pixel Thalion's result, clipped at
  both edges; planes 4–7 stay. The two columns of the menu picture that
  Thalion's loop draws per frame go in with the Falcon blitter
  (`Clouds_column`, `INTRO_SUP.S`).
- **The logo's stars.** Thalion's VBL clears plane 4 of the shown screen
  and sets 150 stars. `Logo_stars` (K3 at `$2646`) walks Thalion's tracks
  the same way and sets them into plane 4 of the shown target, clearing
  only the words it set there last time.
- **Not into the picture still shown** (`Ziel_frei`). A new base
  (`Basis_setzen`) takes over at the next VBL; until then the Videl shows
  `Basis_vorher` (`Basis_wartet`, cleared in `Amiga_vbl`). Thalion's cloud
  loop waits only until 2 VBL have passed since the frame began, so a
  frame that took longer went on into the screen still shown: frame
  *n*+2 over *n* before *n*+1 came, the white flicker of T66. Before a
  direct write into a target, `Ziel_frei` waits for that VBL if the
  Videl still shows it: in `Bl_umlenken` (D's screen), `Clouds_column`
  and `Clouds_draw`. Not in the switch itself: Thalion waits for the next
  VBL right after a new copper list in seven places (`$288A`), and a wait
  there would halve those scenes' frame rate. Inside the VBL or with it
  held off, `Ziel_frei` returns at once.
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
| fantasy intro | `Anzeige_setzen` (in `Fee_ablauf`, after Thalion's and our screen swap) | drops the fairy's save-under on the old screen, draws the fairy into the new one, then writes the base |
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
- The fantasy intro is the fixed case: its copper list reloads six
  colours at raster line `$AE`, picture line 134 (`WECHSELZEILE`;
  bank 1 takes them from `Palette_unten`). Plane 5 of its Falcon screens comes with
  the background from the build (0 above line 134, 1 from there), planes
  6 and 7 are 0, and nothing writes them.
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
hook (`fee_vorspann.i` → `Blitter_warten`). It does Thalion's two blit
kinds itself, in Falcon format: the `$CA` star and the `$E2` logo column.
Since `Magic_falcon` and `Dust_falcon` replace the routines that blit,
only the check build `FEECHECK` still reaches it.

**`Amiga_blit`** (`AMIGA_BLIT.S`) emulates the Amiga blitter on the CPU:
first/last word masks, shifts with the previous word carried over line
ends, fixed values without `USEx`, ascending and descending mode, every
minterm; afterwards the channel pointers stand behind the blit, as on the
Amiga (the intro relies on it). Line and fill mode are counted in
`Bl_fremd`, not executed; none of the programs uses them.

`Amiga_blit_genau` is the exact reference. In front of it, `Amiga_blit`
looks for a pattern with a tight loop:

| Path | Pattern | Written for |
|---|---|---|
| `Bl_schnell_spalte` | one word column, `$CA` or `$E2`, up or down | Thalion's zoom in the intro |
| `Bl_schnell_stern` | `$CA`, two words, `ASH` = `BSH` | the fantasy intro's stars (before E30) |
| `Bl_schnell_ca` | `$CA`, A?B:C, C = D | the fantasy intro's logo (before E30) |
| `Bl_schnell_d8` | `$D8`, C?B:A, unshifted | the extro's scroll text |
| `Bl_schnell_fc`, `_fe` | OR of two or three sources, shifted | the intro's space scene |
| `Bl_schnell_f0`, `_00` | copy, clear | all |
| `Bl_ziel_d8`, `_ca`, `_f0`, `_allg` | the same into a target screen (above) | extro text; intro logo stages, clouds, menu text |

**What runs today.** The path is chosen by the registers, not by the
program. Counted in Hatari (Falcon Tempo, 2026-10-30, `INTRO.TOS` alone
from the desktop to the menu, no click): of 3025 blits 3008 went into a
target (`Bl_ziel_ca` 2584, `Bl_ziel_f0` 412, `Bl_ziel_allg` 12), 15 to
`Amiga_blit_genau`, 2 to `Bl_schnell_00`. None of the other fast paths
was reached; Thalion's `$CA` blit at hunk 0 `$14D0`, for instance, now
goes to `Bl_ziel_ca`. The extro was not counted (read from the code: no
`$CA` blit). Whether the unreached paths go is open (`docs/05b`, open
points).

`BLIT_PRUEF` runs every fast blit through the exact path as well and
counts differences (`Bl_abweichung`); with it the fast paths are
checked, not trusted.

The **Falcon blitter** (the STE blitter) is used only by our layer: for
converting screens, for fetching and bringing target lines and for the
intro's `Clouds_column`, in HOG mode. The VBL uses it too; it waits until
the blitter is free and restores its registers afterwards.

**HOG blits in pieces** (T68). While the blitter holds the bus in HOG
mode the CPU takes no interrupt, the keyboard ACIA's neither. The IKBD
sends a byte every 1.3 ms, and a blit over a whole plane takes longer;
after one lost byte TOS reads the mouse packets shifted, the pointer
jumps, and a menu entry was chosen without a click (T67). `Blit_starten`
(`AMIGA_RAHMEN.S`) therefore runs a blit in pieces of about
`BLIT_STUECK` (512) words, whole lines each; the blitter carries its
addresses on, and between two pieces the CPU takes what is pending.
"HOG mode" holds per piece.

## Sprites

The Amiga shows the mouse pointer and the fairy as hardware sprites. We
draw them into the picture:

- **Pointer** (intro menu): `Zeiger_zeichnen` reads, like sprite DMA,
  the pointers `SPR0PT`/`SPR1PT` and each sprite's control words, checks
  `SPREN` in the last `DMACON` write, and draws sprite 0 (and 1 when
  attached: colours 16–31) into the picture shown (`Basis_jetzt`),
  planes 0–4; plane 5 keeps the bank. In a scene with a table that is
  the target screen shown, so before anyone writes or reads a target the
  pointer goes (`Zeiger_weg`: in `Bl_umlenken` with the VBL held off, in
  `Schirme_wechseln`, in `Display_hold`); the next VBL draws it again.
- **Fairy** (`Fairy_put`, `FEE_SUP.S`; E30: at 50 Hz, as the Amiga's
  sprites): in every VBL on the shown screen. It puts back what it
  covered last time (planes 0–4, `Fee_rettung`), saves the new place and
  draws the fairy there: frame and place from the sprite pointers and
  control words `level3` wrote, the frame from 16 preshifts made at the
  start during the fade-in (`Fairy_shift_*`, 1.1 MB from `Mxalloc`;
  without it no fairy). Planes 0–3 take the sprite value, plane 4 the
  mask (colours 16–31); plane 5 stays the line's bank, as the copper
  changes the sprite colours too. One frame late: drawn is what `level3`
  set in the previous VBL, so Thalion's `rte` stays untouched.

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
  unchanged; TOS 4.04 draws the bombs on the desktop.

## Diagnostic builds

`build_falcon.sh` builds them next to the delivered programs into
`ATARI/AMBFILES/` (for now; they are to move behind a switch).

| Switch | Effect | Builds |
|---|---|---|
| `AMIGA_MESSEN` | Timer A samples the PC about 1000 times a second; per 64 bytes of program, blits vs. display vs. rest, per second | `INTROMES`, `INTROPRF`, `EXTROPRF`, the `*DIAG` builds |
| `STRAHL` | where the Videl reads when we write into a screen or enter the VBL (`amiga_strahl.i`, `Tk_vbl`) | `INTRDIAG`, `EXTRDIAG` |
| `MESS_ENDE=n` | end after *n* seconds, for hardware runs | the `*DIAG` builds |
| `BLIT_PRUEF` | fast blits against the exact path | `INTROPRF`, `EXTROPRF` |
| `ZOOM_PRUEF` | our zoom against Thalion's | with `AMIGA_MESSEN` |
| `FEE_MESSEN` | fantasy intro: count the frames done just in time (after the 2nd VBL) or late (after the 3rd); Thalion's loop takes 3 VBL a frame | `FEEMESS`, writes `FEEMESS.TXT` |
| `CHECK_STARS`, `CHECK_DEFER` | fantasy intro: Thalion's `make_funkel2` and `make_magic` and ours every frame from the same state; counts the frames whose state or lower band differ | `FEECHECK`, writes `FEECHECK.TXT` |
| `ABSTURZTEST` | an `illegal` after 250 VBL, to test the emergency exit | `FEEABST`, `INTRABST`, `EXTRABST` (built separately) |

`FREQ.TOS` (`lader/freq.s`) measures the machine's frame rate: Thalion's
timing is in VBLs.

## The ST

The ST builds the three programs itself, each in its own folder and from
its own tools, on the Falcon's model and independent of `fantasy/`,
`intro/`, `extro/` and `amiga/`; only the emergency exit
`amiga/AMIGA_NOTAUS.S` is shared, unchanged. The Falcon programs check
for a Falcon (`Falcon_pruefen`, cookie `_MCH`) and stop otherwise; the
loader starts the ST's names on an ST (chapter 3).

| | Fantasy intro | Intro | Extro |
|---|---|---|---|
| Ours | `FANTSYST.TOS` | `INTROST.TOS` | `EXTROST.TOS` |
| Folder | `fantasy_st/` | `intro_st/` | `extro_st/` |
| Built by | `tools/fantasy_st_build.sh`, `fantasy_st_data.py` | `tools/intro_st_build.sh`, `intro_st_program.py` | `tools/extro_st_build.sh`, `extro_st_program.py`, `extro_st_data.py` |
| Thalion's code | `FAIRY.S` unchanged | all seven hunks, K1 and K2 as on the Falcon, its own K3 | all six hunks, K1 and K2 as on the Falcon, its own K3 |

Decision E30 (*11 §7.8a*): per program both machines do the same things
the same way, so that a reader of one understands the other. The
fantasy intro has the same cut on both (graphics in the machine's
format at build time, hooks at `plot_jmptab` and the blit wait, own
`make_magic`/`make_funkel2`); in the intro the scenes are target
screens, with the same K3 places and names where they exist (the
Falcon converts its start menu again since T70, the ST keeps it as a
target). Inner loops and what the hardware forces may differ: on the ST
16 colours instead of 32, Timer B where the Falcon has colour banks, the
CPU where the Falcon has a blitter. No music in intro and extro on the ST: no YM
version of those songs is known.

What the ST changes and what looks different from the Amiga is listed in
`docs/17-deviations.md` D3, the state and the measurements in
`docs/05c-ST.md` ("ST fairy intro", "ST intro", "ST extro").

## Files

| File | What it does |
|---|---|
| `lader/lader.s` | `AMBER.TOS`: the program chain |
| `lader/freq.s` | `FREQ.TOS`: frame rate |
| `fantasy/fantasy.s`, `fee_vorspann.i` | fantasy intro unit; `waitblit` → `Blitter_warten`, register offsets |
| `fantasy/FEE_SUP.S` | the layer under `FAIRY.S`: start, `Fee_ablauf`, `Fee_vbl`, display, the fairy (`Fairy_put`), the plot hook, `Blitter_warten`, mouse |
| `fantasy/STARS_FALCON.S` | `Magic_falcon`, `Dust_falcon` for Thalion's `make_magic`, `make_funkel2`; the check `CHECK_STARS` |
| `intro/intro.s`, `extro/extro.s` | units: vorspann, `*_SUP.S`, then `build/<name>_hunks.i` |
| `intro/INTRO_SUP.S`, `extro/EXTRO_SUP.S` | `start`, `Uebergabe`, `Schirm_tabelle`, the K3 routines |
| `intro/INTRO_ZOOM.S` | our zoom (K3 `$1C98`) |
| `intro/INTRO_CLOUDS.S` | our clouds (K3 `$E3A`): `Clouds_prepare`, `Clouds_draw` |
| `amiga/AMIGA_RAHMEN.S` | intro and extro: OS emulation, vectors, VBL, display, colours, pointer, mouse, `K2_trap` |
| `amiga/AMIGA_ZIEL.S` | screens in the target format, `Bl_umlenken`, `Ziel_frei` |
| `amiga/AMIGA_BLIT.S` | `Amiga_blit`: the Amiga blitter on the CPU |
| `amiga/AMIGA_MUSIK.S` | loading and binding Thalion's music player |
| `amiga/AMIGA_NOTAUS.S` | emergency exit |
| `amiga/AMIGA_MESSEN.S`, `amiga_strahl.i` | measurement builds |
| `amiga/amiga_vorspann.i` | constants: TOS, Videl, blitter, `AR_*`, screen format, `SCHIRM` |
| `tools/amiga_programm.py` | hunks, K1, K2, K3 for intro and extro |
| `tools/fantasy_auszug.py`, `fairy_umbiegen.py` | the fantasy intro's extraction and K1 |
| `tools/fantasy_st_data.py --falcon` | the fantasy intro's graphics in Falcon format (the ST's tool) |
| `tools/imploder_exe.py` | Imploder unpacker |
| `tools/musik_k1.py` | the music files' hardware operands |
| `tools/fantasy_bauen.sh`, `amiga_bauen.sh` | single builds into `build/`; `fantasy_bauen.sh` also builds `FEEMESS.TOS` and `FEECHECK.TOS` |

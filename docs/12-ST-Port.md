# ST-Portierung: Stand, Plan und die Farbreduktion 32 auf 16

*Bis 2026-09-30 `docs/11-ST-Farbreduktion.md`; umbenannt, weil die
Intro-Session `docs/11-Intro-Extro.md` führt. Die Messwerte stammen aus
`tools/farbreduktion.py`. Die Laufzeitkosten sind **Schätzungen** aus
Taktzahlen des 68000, nicht gemessen.*

## State: ST mode on the STE, blitter detection (2026-10-21, Hatari; hardware T91 passed 2026-10-23)

The user has no plain ST, only an STE and the club's Mega STE (E40).
`PLAIN_ST=YES` in `ATARI/AMBFILES/AMBER.INF` (E17, main's reader
`shared/SETTINGS.S`; until 2026-10-23 the file `ST.INF` with `ST`) makes
`ENGINEST.TOS` behave like a plain ST: `Open_screen` (`ST.S`) clears
`Feinbasis` (three bits per channel, the ST register values from
`STPAL.DAT`; no low video base byte, so no screen shake) and
`St_blitter`. `NO`, no key or no file: the machine as detected. Until
the cut (E17 step 3) `ST.S` reads the file itself (`St_settings`, marked
as a bridge); afterwards `MAIN.S` reads it once before `Open_screen`.
The build leaves `*.INF` in place. The 8 MHz STE runs as fast as the ST
(same bus and shifter timing), so the speed needs no imitation. Not
covered: the older TOS (1.0x) and the memory of a real ST.

`St_blitter` comes from XBIOS `Blitmode(-1)` (bit 1), called from TOS
1.02 on (`os_version` in `_sysbase`); no code uses it yet (docs/05c,
2D plan step 4: the CPU path is improved first).

Hatari (STE, EmuTOS 1.4, 2026-10-21, then still `ST.INF`): without the file `Feinbasis`
and `St_blitter` set, the 2D map shows 16 levels per channel; with it
both clear and `St_nur_st` set, 8 levels, picture otherwise the same.
Again with `AMBER.INF` (2026-10-23): no file, `PLAIN_ST=NO` (with
`MUSIC=YM`, CR LF) as before; `PLAIN_ST=YES` and `plain_st = yes ;
comment` both clear and `St_nur_st` set; the start menu comes up.

## State: precomputed palettes, STPAL.DAT (2026-10-17, built, untested on hardware)

User, 2026-10-17: put all ST palettes into a file of their own for visual
fine tuning, separately for ST and STE, loaded once at start; goal 2 is
relaxed for it, and the deviation is documented
(**docs/17-deviations.md D1**, with what, why, where and the way back).

- `tools/st_palettes.py build` (called by `tools/build_st.sh`) reduces
  every palette the game puts into a raster list like `St_bauen` and
  writes `ATARI/AMBFILES/STPAL.DAT`: `Palettes.amb` 1-49, `Main_pal`,
  `Tactic_pal`, `Automap_pal` and the combat palettes (`Palettes.amb` *N*
  with 26-31 from `Tactic_pal`); 65 distinct, 11,448 bytes. Per palette:
  key, table, representatives, 15 register values for the STE and 15 for
  the plain ST.
- Weighted by the pictures (user, 2026-10-17, D1): the colours 1-25 are
  grouped by how many points the game shows of each (2D map tiles, event
  pictures, combat backgrounds), every colour at least 1 %; register
  values are weighted means. Lyramion: sea blue instead of grey, the
  greens apart (mean deviation 1.55 -> 0.85 steps). Compared on
  Grandfather's house (pal 7) and a Lyramion forest: 1 % is the best of
  1/2/3/5 % for the large areas; from 2 % the house floor turns brown. The
  orange accents of the house are lost at 1 %. 3D-only palettes and
  `Main_pal`/`Tactic_pal`/`Automap_pal` stay unweighted.
- Method per palette (user, 2026-10-29): unweighted is the default again
  (as `St_bauen`, the fire in the house red); only the worlds, pal 1-3,
  are weighted at 1 %. A line `<palette> method weighted N` or
  `... method unweighted` in `tools/st_palettes.txt` chooses; the review
  sheet shows each palette under each method with a button and writes
  the lines (a whole `st_palettes.txt` to download).
- Hand corrections: `tools/st_palettes.txt` (colour into another
  register; register value per machine). The repository holds only these;
  the defaults are averages of Thalion's colours and stay in `build/`.
- To look at and choose: every ST build (and `python3 tools/st_palettes.py sheet`) writes
  `build/st_palettes/index.html` (per palette Thalion's colours, table,
  STE and ST registers, a picture from the game: 2D map in the layout,
  event picture, combat background, 3D maps only the layout; Thalion, then
  STE and ST under each method, unweighted, weighted 1 % and 3 %).
  `build/st_palettes/listing.txt` in numbers. Both contain Thalion's
  graphics: not for the repository, not for publishing.
- Run time (`ST_LIB.S`): `St_load_palettes` from `Open_screen`;
  `St_from_file` before `St_bauen` fills an entry from the file, for the
  palette exactly as it is. `srp_hand` scales the file values with the
  faded colours of the group, so fades and light levels stay right. A 3D
  map entered in the dark is not looked up through `Backup_pal`: the
  groups of the bright palette put dimmed and undimmed colours into one
  register (Hatari, Grandfather's cellar: brown floor instead of black);
  `St_bauen` groups the dimmed palette, as before. Without the
  file, or for a palette not in it, `St_bauen` as before.
- **Proof so far (Hatari, STE with EmuTOS, 2026-10-17):** the file is
  loaded whole (65 entries). With the save games "Anfang" (Grandfather's
  house, 2D) and "Keller" (3D, dark) the picture at VBL 3000 is the same
  with and without `STPAL.DAT`: in the cellar identical to the pixel, in
  the house only the animation phase differs. With the file `St_bauen`
  ran only for the all-black palette at the start of the fade-in (and in
  the cellar for the dimmed palette); without it, also for `Main_pal` and
  the map palette. On the way two register faults turned up and were
  fixed: `stb_ebenen` changes `a4` (`St_from_file` then read zeros as
  register values), and `srp_hand` changed `d4`, the place counter of
  `st_regs_bauen` (bus error). Not on the hardware yet (T25); the pause
  saved is not measured.

## State: separate builds, one folder for both (2026-10-15, built, untested on hardware)

User, 2026-10-15: the Falcon builds on its own with the DSP, the ST on its
own without, and both machines play from the same game files.

- `tools/build_falcon.sh` and `tools/build_st.sh` each build one machine;
  `tools/build_all.sh` runs both (it replaces `baue_alles.sh`, which also
  called `baue_st.sh`). Shared part: `tools/build_common.sh`.
- `build_st.sh` needs no Falcon build and no `a56`: `tools/build_engine.sh`
  (formerly `engine_uebersetzen.sh`) skips `musik_dsp.sh` under `ZIEL_ST`,
  where `MUSIK_SUP.S` leaves the mixer out anyway. Proven with an `a56`
  that stops when called: not called.
- **One folder `ATARI/`** instead of `FALCON/` and `ST/`, with one
  `AMBFILES/`: game files and save games are shared, the program names
  unique per machine: `ENGINE.TOS`/`ENGINEST.TOS`, and reserved
  `FANTSYST.TOS`, `INTROST.TOS`, `EXTROST.TOS`. Since 2026-10-21 there is
  one loader `AMBER.TOS` for both (main, test T30): it reads the cookie
  `_MCH` and takes the Falcon names at 3, else the ST names. Until then
  the loader was built twice, `AMBERST.TOS` for the ST; starting the Falcon
  loader on the Mega STE ended in a hanging `INTRO.TOS` and bombs. The
  Falcon intros do not run on the ST; the loader skips the missing ST
  intros silently.
- Each build removes only what is neither `*.INF` nor delivered by the
  other build last time (`build/delivered_*.txt`).
- `AMBER.INF` is shared (E17; until 2026-10-24 `MUSIK.INF`): the ST
  reads only `MUSIC=OFF` from the `MUSIC` line (otherwise YM), so `OFF`
  silences both machines.
- **Proof (build only):** `ENGINE.TOS`, `AMBER.TOS`, the intros and all
  game files byte-identical to the old `baue_alles.sh` at 2ed5496;
  `ENGINEST.TOS` byte-identical to the old `ST/AMBFILES/ENGINE.TOS`
  (240417 bytes). `AMBERST.TOS` differed only in the names. **Open:**
  hardware test with one `ATARI/` folder on Falcon and Mega STE, save game
  from one continued on the other.

## Stand: E12 eingebaut, Weg B (2026-10-10, Hatari vom Nutzer)

- **Erkenntnis 242: Der 3D-Puffer kann Register tragen, wenn seine
  Quellen sie tragen.** Thalion kopiert Wände, Objekte, Horizont und die
  Füllfarben unverändert in den Puffer (Leseprüfung unten). Die Bibliothek
  legt darum von diesen Blöcken eine Abschrift in Registernummern an
  (`St_abschrift_*` in `ST_LIB.S`) und gibt sie während eines 3D-Bilds über
  `Claim_pointer` heraus; Thalions Blöcke bleiben unverändert.
  `Show_MOVEP_screen` kopiert dann nur noch, wie beim Falcon
  (`St_abschrift_zeigen`).
  - *A frame starts* with the `Claim_pointer` on `MOVEP_handle`, if the
    block also has the size of Thalion's MOVEP buffer: Thalion claims it
    first in every 3D frame and never otherwise, but between two 3D maps
    the variable still names a freed handle number that may already belong
    to another block (finding 243, docs/05c). There the copies are checked
    and allocated. **Colouring is lazy** (2026-10-22): a copy is coloured
    from Thalion's block when its handle is first claimed in a frame with
    the current set; a new set (another entry or `ST_GEN`) makes all of them
    uncoloured again. A light level does not change the set (`st_blende`).
    Thalion claims all wall pointers in every frame (`Wall_ptrs`,
    `3D_MAP.S`), so the first picture of a map still colours almost
    everything; only objects and the horizon wait until they are seen.
  - `Sky_colour` und `Floor_colour` stehen für die Dauer des Bilds in
    Registern, danach wieder wie bei Thalion. Das ist der einzige Eingriff
    in Thalions Speicher.
  - The copies live in a block of their own (`Malloc`), not in the handle
    table (199 places). `Free_memory` or `Invalidate_memory` on one of their
    handles drops all of them, but the block is **parked** (2026-10-22): up
    to two maps keep their coloured copies, each entry keyed by the length,
    two checksums of Thalion's block (sum, and rotated xor) and the set
    (`ST_TAB` 0..15). A copy is first looked for there, so town → house →
    town colours the town once. Parks go, oldest first, when less than
    512 KB stays free, when the copies of a new map find no memory, and in
    `Kill_unclaimed_memory` (`Out_of_memory`) all of them. The hooks in
    `MEMORY.S` are under `IFD ZIEL_ST`.
  - Der alte Weg (`St_movep_schirm`) bleibt, wenn kein Speicher da ist, die
    144 Zeilen nicht einen Satz haben oder `Draw_floor`/`Draw_ceiling`
    malen (`Floor_ceiling_status`, nur der ST-Bau auf einem Falcon).
- **Test:** Der Nutzer hat `E12ENG.TOS` in Hatari (STE) gespielt: läuft
  gut. **Nicht gemessen:** VBL je Bild, Speicherbedarf der Abschriften,
  Dauer des Umfärbens beim ersten Bild einer Karte (jeder Block wird ganz
  umgefärbt; auf 8 MHz eher einige Sekunden als die 0,5–1 s unten).
  Hardware: T19.

## Stand: E12, Leseprüfung des 3D-Puffers (2026-10-10, nur gelesen)

**Frage (docs/05, E12):** Lässt sich die Umsetzung Farbe → Register
(`St_movep_schirm`, 1,27 Mio. Takte je Bild) einsparen, indem die Quellen
schon Registernummern tragen? Dafür muss jede Farbnummer im 3D-Puffer
(`MOVEP_ptr`) aus Daten stammen, die man vorher umfärben kann. Gelesen
in Thalions `3D_MAP.S` und im Bau aus `AM2_CPU` (`build/am2cpu_code.i`);
kein Lauf, kein Hatari.

**Wer in den Puffer schreibt** (nur `3D_MAP.S`; `MOVEP_ptr` und
`Show_MOVEP_screen` kommen sonst nirgends vor):

| Quelle | Ort | Farbnummer | umfärbbar |
|---|---|---|---|
| Wände | `put_dpoly` aus `Wall_ptrs` (← `Wall_handles`, `Wall_3D_FAST_file`) | Texel unverändert: Langwort lesen, schieben, mit dem Punktbit aller vier Ebenen maskieren, odern. Durchsichtig = alle vier Bits null (`seethru_flag`) | ja, Block je Wandhandle |
| Overlays auf Wänden | `Put_(un)masked_MOVEP_block` in `Load_3D_map_data`, beim Laden in den Wandblock | wie oben, Maske = ODER der vier Ebenen | ja, sie stecken danach im Wandblock |
| Objekte | `draw_zoomshape` (über `make_3dzoom2`, d2 = −1) aus `Object_handles` (`Object_3D_FAST_file`) | Texel unverändert, Maske aus dem ODER der Ebenen; **überflogen**, nicht Befehl für Befehl gelesen | ja, Block je Objekthandle |
| Horizont | `Insert_horizon` aus `Horizon_preshift_handle` | beim Laden aus `Lab_background_file` vorgeschoben (16 Lagen, 20 Zeilen, 46 KB), dann unverändert kopiert; die Ursprungsdatei gibt Thalion gleich wieder frei | ja, aber nur einmal: das Original ist weg |
| Himmel, Boden (Füllung) | `Sky_colour`, `Floor_colour`: Thalions Variablen, in `M3_ModInit` aus `Sky_colour_nr`/`Floor_colour_nr` der Labordaten gebildet | eine feste Nummer je Karte | ja, aus den Labordaten neu zu bilden |
| Böden, Decken mit Textur | `Draw_floor`/`Draw_ceiling`, nur bei `CPU_68020_plus` | aus eigenen Puffern | auf dem ST nie; **der ST-Bau auf einem Falcon** nähme den Weg (siehe unten) |
| Sterne | `Draw_stars`: `Get_pixel`/`Plot_pixel` auf dem Schirm, Ebene 4 | nicht im Puffer | entfällt |
| Finsternis | `Draw_box` auf dem Schirm | nicht im Puffer | entfällt |

Keine dieser Stellen rechnet mit der Farbnummer: kein Versatz, keine
Lichttabelle, keine Schattierung nach Entfernung. **Bewiesen** für
`put_dpoly`, `Insert_horizon`, die beiden Overlayroutinen und die
Füllungen; für `draw_zoomshape` nur aus dem Befehlsgemisch geschlossen.
Das Licht ist auf dem ST eine Blende der Register, die Tabelle bleibt
(`st_blende`, Abschnitt „Lichtstufe“).

**Was dafür spricht:**
- Der ganze 3D-Ausschnitt (Zeilen 49–192) liegt in einem Platz der
  Rasterliste: `Map_RL` und `C3_RL` setzen `Current_pal` ab Zeile 37,
  `R_range` bleibt auf dem ST flach. Eine Tabelle gilt also für alle 144
  Zeilen.
- Durchsichtig bleibt durchsichtig: Register 0 gehört der Farbe 0 allein
  (`ST_LIB.S`), und alle Masken oben sind „alle vier Bits null“.
- Die Blöcke liest nur `3D_MAP.S`. Kein anderer Teil Thalions holt Wände,
  Objekte oder Horizont.
- Unser Speicherverwalter hat keinen Dateizwischenspeicher
  (`MEMORY.S`): Jede Karte lädt frisch, `Free_memory` gibt sofort zurück.
  Ein umgefärbter Block überlebt die Karte also nicht.

**Was dagegen steht oder zu entscheiden ist:**
1. **Die Tabelle einer Karte kann wechseln.** `ST_GEN` ändert sich, wenn
   der Eintrag der Palette aus dem Zwischenspeicher fällt (acht Einträge;
   ein Kampf bringt mehrere Paletten) und neu gebaut wird, dann aus der
   gerade geblendeten Palette. Umfärben ist verlustbehaftet (31 Farben auf
   15 Register): Ohne das Original lässt sich nicht neu färben. Es braucht
   also eine **Abschrift** je Block, entweder als Original (Thalions Block
   wird umgefärbt) oder als umgefärbte Fassung (Thalions Block bleibt). Bei
   der zweiten müsste `Claim_pointer` für diese Handles unsere Fassung
   liefern, weil `3D_MAP.S` die Zeiger in jedem Bild neu holt. Bei der
   ersten ändert sich Thalions Speicher, nicht seine Dateien und nicht sein
   Code. Speicher: bis 32 Wände (128 Punkte breit), Objekte je Karte
   verschieden, Horizont 46 KB; die Summe ist nicht gemessen, geschätzt
   100–250 KB zusätzlich.
2. **Wann umfärben?** Thalion ruft nach dem Laden keine Bibliotheksroutine,
   die sicher „Karte fertig, Palette steht“ heißt. Der Weg ohne Eingriff:
   im ersten `Show_MOVEP_screen` nach einem Kartenwechsel oder Tabellenwechsel.
   Dieses eine Bild geht noch den alten Weg, danach wird umgefärbt (Kosten
   einmal je Karte, geschätzt 0,5–1 s auf 8 MHz). Einen Kartenwechsel
   erkennt man nicht sicher an Handle und Adresse (TOS gibt dieselbe
   Adresse wieder heraus); nötig ist ein Zähler in `Load_subfile` oder
   `Free_memory`, also in `FILES_SUP.S` oder `MEMORY.S` (Absprache mit der
   2D-Sitzung).
3. **Der Puffer gilt nur für die Tabelle, mit der gefärbt wurde.** Zeigt
   ein anderes Modul darüber eine andere Rasterliste, während 3D zeichnet,
   oder ist ein Bild noch mit den alten Nummern gerastert, braucht es den
   alten Weg. Dafür bleibt `St_movep_schirm`, mit einer Tabelle Register →
   Register.
4. **Der ST-Bau auf einem Falcon** setzt nach dem Cookie `CPU_68020_plus`,
   und dann malen `Draw_floor`/`Draw_ceiling` ungefärbte Nummern. Entweder
   im ST-Bau den 68000-Weg festlegen (`D3_CPU` = 0) oder deren Puffer
   mitfärben. Gehört zu „später, bei Falcon-Arbeiten“.

**Gewinn, geschätzt aus der Messung vom 2026-10-04:** Die Umsetzung
(1,27 Mio. Takte) wird ein reines Kopieren mit `movep` wie beim Falcon,
rund 0,12 Mio. Das spart gut 1,1 Mio. Takte, etwa 7 VBL auf 8 MHz: von
rund 21 auf rund 14 VBL je Bild. Die Angabe „15 von 21 VBL“ in docs/05 ist
damit zu hoch, wenn sie die Ersparnis meint; als Ergebnis (rund 14–15 VBL)
passt sie. Die „Tabelle über zwei Ebenen“ (−0,2 bis −0,3 Mio.) entfällt
mit E12, sie beschleunigt die Umsetzung, die E12 abschafft. Danach führt
Thalions `put_dpoly` (1,42 Mio.).

**Entscheidung (Nutzer, 2026-10-10): Weg B.** Thalions Blöcke bleiben
unverändert; die Bibliothek legt eine umgefärbte Abschrift an und gibt sie
`3D_MAP.S` statt des Originals.

## Stand: Hardwaretest Mega STE (2026-10-07, vom Nutzer)

Erster Lauf auf echter ST-Hardware, gemeldet am 2026-10-09. Bau: `ST/` des
Worktrees `st` vom 2026-10-04 17:00, Stand 5b2cece (3D-Puffer über zwei
Tabellen, Lichtstufe als Blende). Prüfliste T4 aus docs/05.

| Punkt | 8 MHz ohne Cache | 16 MHz mit Cache |
|---|---|---|
| (a) 2D-Karte: Farben, keine Streifen an Bereichsgrenzen | in Ordnung | in Ordnung |
| (b) Inventar: Rahmengrau grau | in Ordnung | in Ordnung |
| (c) Ereignisbild: Palette | in Ordnung | in Ordnung |
| (d) 3D im Keller: Bild, kein Absturz | in Ordnung | in Ordnung, schneller |
| (e) Lichtwechsel in 3D | nicht getestet (in Hatari in Ordnung) | nicht getestet |
| (f) Beenden | in Ordnung | in Ordnung |

Damit sind Timer B je Bereichsgrenze (S2), der Rampenschutz für das
UI-Grau, das Ereignisbild (241) und der 3D-Puffer über `movep` auf der
Hardware bestätigt. Gemessen hat der Nutzer das Tempo nicht; 16 MHz mit
Cache schaltet er selbst ein (E13: wir legen auf 8 MHz aus).

**Nach dem Einmischen von main (68bd67f) offen:** Thalions Musik kam mit
main in den ST-Bau. Unter EmuTOS (Hatari, STE, 4 MB) nimmt `Locksnd` an,
und ohne `MUSIK.INF` mischt der Prozessor den Falcon-Ton (`mk_bereit`
gesetzt, `md_dsp` 0). Bild und Weg in den Keller sind mit und ohne Musik
gleich, das Tempo ist ungemessen. Auf dem ST soll die Musik still bleiben,
bis der YM-Spieler kommt (docs/05 E4).

**Behoben in main (b8ea229, Musik-Sitzung):** `Musik_install` liest den
Cookie `_SND` und spielt nur mit 16-Bit-Ton und Matrix (Bits 2 und 4), den
DSP-Weg nur mit Bit 3. Das hängt am Rechner, nicht an der Fassung; die
Antwort von TOS 2.06 auf `Locksnd` spielt keine Rolle mehr. Hatari, STE,
ohne `MUSIK.INF`: `mk_bereit` 0, der Keller kommt wie vorher. Auf dem Mega
STE: Test T15.

**Off at assembly since main 02ba79f (session Musik):** under `ZIEL_ST`
the Falcon mixers, the DSP code and the ring are left out (44 KB less);
the music entry points lead to the YM player (docs/13 6a), and of the
`MUSIC` line in `AMBER.INF` only `OFF` counts. The `_SND` check stays for
the Falcon.

## Stand: Kampfzoom im ST-Bau (2026-10-10, nach dem Einmischen von `3d`)

`3d` hat den Kampfzoom (`COMBAT_SUP.S`) auf Gruppen zu 16 Punkten
umgestellt (Erkenntnis 202): die Ebenen 0..4 gehen direkt aus Thalions
Quelle in Register, die Ebenen 5..7 aus der Bank. Auf dem ST geht das so
nicht, die Farbe läuft über die Tabelle der Zeile. Der ST-Weg: je Zeile
der Satz aus `St_zeilensatz_schnell` (einmal vorher
`St_zeilen_pruefen`), je Punkt die Farbnummer aus den fünf Ebenen,
`ST_TAB` gibt das Register, dessen vier Bits gehen in vier Ebenenwörter,
die Maske in ein fünftes; geschrieben wird je Gruppe wie beim Falcon
(`zst_schreiben`). Die Silhouette nimmt `zs_schreiben` des Falcon, mit
dem Register ihrer Farbe. Tempo ungemessen.

Vom Nutzer in Hatari geprüft (2026-10-10, STE, 4 MB, 8 MHz, `T15ENG.TOS`):
keine Grafikfehler, Farben im Kampfbild in Ordnung, der Zeiger flüssiger.
Das Taktikfeld ist sehr hell; das kommt mit den Spezialpaletten
(zurückgestellt). Danach T15 (a) und (c) vom Nutzer getestet
(2026-10-10): Dungeons, Kämpfe, Stadt, Gasthaus, Landkarte in Ordnung.
Offen nur T15 (b), der Absturztest.

**Nebenbefund, ST-Bau auf dem Falcon:** Ein Savestate vom Mac (Hatari
2.6.1, Cookies `_MCH` 3, `_CPU` 30) zeigt Portrait und Kampfbild mit
falschen Farben, der Zeiger ruckelt; im Savestate lief der alte Bau
5b2cece, mit `T15ENG.TOS` sah es gleich aus. Vermutlich Hataris Grenze
(Erkenntnis 150: im Falcon-Bild kein Palettenwechsel, der ST-Bau wechselt
je Bereich); auf einem echten Falcon ungeprüft. Für später gemerkt
(docs/05, Nutzer).

## Stand: Notausgang im ST-Bau (2026-10-09, Hatari; Mega STE offen, T15)

Mit main kam der Notausgang über `etv_term` (`MAIN.S`, Erkenntnis 272): er
ruft bei jedem Programmende `Musik_remove`, `Raster_remove`,
`Mouse_remove` und `Close_screen`, also nach `Exit_program` ein zweites
Mal. `Raster_remove` und `Mouse_remove` sind gemeinsamer Code mit Merker.
`Close_screen` in `ST.S` bekommt dieselbe Wache wie in `FALCON.S`: nur nach
`Open_screen` und nur einmal (`Schirm_offen`), im Notausgang
(`Im_notausgang`) kein `Mfree` und keine Cursorfolge. Ohne die Wache gäbe
das Beenden den Schirmspeicher zweimal frei.

Hatari, STE, EmuTOS 1.4, Bau mit `-DABSTURZTEST=1`: WEITERSPIELEN, Bomben
(EmuTOS zeigt seinen Fehlerschirm), danach der Desktop mit Farben und Maus;
`Im_notausgang` gesetzt, `Schirm_offen` 0. Normales Beenden ist in Hatari
nicht nachgestellt (nur mit der Maus).

## Stand: Lichtstufe in 3D als Blende (2026-10-04, Hatari, einfacher ST; vom Nutzer im Dungeon getestet)

**Befund des Nutzers (Hatari):** Wird es in 3D langsam Nacht, also beim
Wechsel in eine neue Stufe der Dämmerung, ist das Bild rund 1 s lang in
falschen Farben.

**Ursache (Thalions `3D_MAP.S`, bewiesen):** `Set_D3_light_level`
(Dungeon) und `Set_C3_light_level` (Stadt) blenden die Farben 0–15 an Ort
und Stelle nach `Current_pal` und rufen `Reset_current_RL`. Unser
Zwischenspeicher findet Einträge über den Inhalt der Palette. Jede
Lichtstufe war für ihn eine neue Palette: `St_bauen` (rund 1 s) rechnete
neue Gruppen, und bis das Bild neu stand, passten Register und gezeichnete
Punkte nicht zusammen.

**Abhilfe (`st_blende`, `ST_LIB.S`; vom Nutzer freigegeben):** Eine
Lichtstufe wird behandelt wie eine Blende (Abschnitt „Blenden“ unten): Die
Tabelle bleibt, die Register rechnet `st_regs_bauen` aus `Bank_ist`, also
aus den geblendeten Farben. Als Lichtstufe gilt eine neue Palette, wenn sie
`Current_pal` ist, auf derselben Karte (`Map_nr`; `Load_map` füllt
`Current_pal` neu) und die Farben 16–31 gleich bleiben. Der Eintrag merkt
sich dazu Quelle und Karte (`SE_QUELLE`, `SE_KARTE`) und übernimmt die
neuen Farben als Schlüssel. `ST_GEN` bleibt, Merkliste und Kacheln gelten
weiter.

**Hatari, „Keller“ des Nutzers:** Der Keller ist dunkel, das Licht kommt
vom Lichtzauber (Stufe 13). Die Zauberdauer per Speicherschreiben auf 0
gesetzt, den Echtzeitzähler (`Frame`) dreimal vorgestellt: Licht 13 → 10.
Alter Bau: `st_gen` 3 → 6, ein Neubau je Stufe, und Zwischenbilder in
Orange und Cyan, also der Befund des Nutzers. Neuer Bau: `st_gen` bleibt 3,
das Bild dunkelt ohne Ausreißer ab. **Test des Nutzers (2026-10-04,
Hatari, Dungeon):** „passt“. Eine Stadt bei Dämmerung (C3) ist nicht
geprüft, sie geht denselben Weg.

**Bekannte Grenze:** Die Gruppen stammen aus der ersten Lichtstufe, die
auf einer Karte gesehen wird. Wird ein Spielstand bei Nacht geladen, gelten
die Gruppen der dunklen Palette auch, wenn es hell wird. Besser wäre ein
Bau aus der hellen Palette (`Backup_pal` und die Farben 16–31). Das ist
nicht umgesetzt.

## Stand: 3D-Tempo, Umsetzung des 3D-Puffers (2026-10-04, Hatari, einfacher ST)

**Befund des Nutzers:** In Hatari ist der 2D-Teil schnell, der 3D-Teil
kaum spielbar (auf dem Amiga ruckelt er auch, ist aber spielbar).

**Messung:** Hatari, einfacher ST, 8 MHz, 4 MB, EmuTOS 1.4, Spielstand
„Keller“ des Nutzers, 500 VBL lang „rechts drehen“ gehalten (Pfeil oben
rechts, ST-Punkt 288,152), Profiler. **15 Bilder in 500 VBL, also rund
33 VBL je Bild (gut 1,5 Bilder in der Sekunde).** Zum Vergleich 2D: 11,6
VBL je Bild. Ein Bild kostet rund 5,0 Mio. Takte (0,63 s):

| Stelle | je Bild | Anteil | Wessen Code |
|---|---|---|---|
| `Show_MOVEP_screen` (3D-Puffer auf den Schirm, ST-Zweig) | 3,0 Mio. | 60 % | unser (`D3_SUP.S`, `St_block_direkt`/`st_acht` in `ST_LIB.S`) |
| davon `st_acht` (Punkt für Punkt durch die Tabelle) | 2,2 Mio. | 43 % | unser |
| `Draw_dungeon` | 1,8 Mio. | 36 % | Thalions |
| davon `put_dpoly` (Wände) | 1,15 Mio. | 23 % | Thalions (AM2_CPU, CPU-Fassung) |
| davon `draw_zoomshape` (Gegenstände, Figuren) | 0,35 Mio. | 7 % | Thalions |
| Mauszeiger im VBL (Knopf gehalten) | 0,27 Mio. | 5 % | unser |

Der 3D-Puffer trägt nur die Ebenen 0–3, also Thalions Farben 0–15. Die
Umsetzung schiebt jeden Punkt einzeln durch die Tabelle (rund 135 Takte je
Punkt, 20.736 Punkte je Bild). Auf dem Amiga kostet dieser Schritt nichts.
Thalions Rasterer läuft auf dem ST als CPU-Fassung; ein A500 nahm dort den
Blitter (docs/02, A3/A7).

**Test des Nutzers (2026-10-04, Hatari):** „etwas schneller und
spielbarer und sieht gut aus“, Tag/Nacht gut. Offen: Bei einem
Palettenwechsel ist das Bild rund 1 s falsch (Vermutung des Nutzers: solange
neu gerechnet wird); behoben im Abschnitt „Lichtstufe in 3D als Blende“.

**H1, die Umsetzung neu (`St_movep_schirm`, `ST_LIB.S`; vom Nutzer
freigegeben, in Hatari gemessen, auf Hardware ungetestet):** Je acht Punkte
zwei Schritte über Tabellen statt Punkt für Punkt. `st_mv_s` (fest, 4 KB)
verteilt die vier Ebenenbytes auf acht Nibbles, also acht Farben n;
`st_mv_t` (4 KB, je Satz und Bau neu, rund 50.000 Takte) setzt je Byte
zwei Punkte auf die Schirmebenen um, schon in der Lage für `movep.l`.
`Show_MOVEP_screen` (`D3_SUP.S`) ruft auf dem ST nur noch diese Routine.
Die reine Ebenenlogik (Wortbefehle je Ebene) wäre auf dem 68000 nicht
schneller gewesen: Es fehlen Register, und `eor` nimmt keinen Speicher als
Quelle.

| | vorher | nachher |
|---|---|---|
| Umsetzung je Bild | 3,04 Mio. Takte (147 je Punkt) | 1,27 Mio. Takte (61 je Punkt) |
| ein Bild (ohne Wartezeit) | rund 34 VBL | rund 21 VBL |

Gemessen mit derselben Kette für beide Bauten (500 VBL „rechts drehen“
gehalten). Darin hängt Thalions `Wait_4_unclick` gut 2,5 s, weil der
Knopf nie losgelassen wird; diese Zeit ist oben herausgerechnet.
**Bildvergleich:** drei verschiedene Ansichten (Start, nach einer und nach
zwei Drehungen) punktgleich mit dem alten Bau, je dort, wo beide Bauten
denselben Winkel erreicht hatten.

Danach (je Bild): Thalions `put_dpoly` 1,42 Mio., unsere Umsetzung
1,27 Mio., `draw_zoomshape` und der Rest von `Draw_dungeon` 0,4 Mio.
Nächster Hebel bei uns: eine Tabelle über zwei Ebenen auf einmal
(256 KB, einmal gebaut), geschätzt 0,2–0,3 Mio. weniger.

## Stand: Rampenschutz für das UI-Grau (2026-10-04, Hatari; auf Hardware ungetestet)

**Test des Nutzers (2026-10-04, Hatari):** „rampenschutz passt“. Die
Weltkarte wirkt dagegen recht farblos (später; vermutlich, weil ihr nur
noch 10 freie Register bleiben). Ein echter ST/STE steht aus.

**Befund des Nutzers:** Das Grau der Oberfläche glitt auf dem ST ins
Sumpf- oder Moosgrüne ab; im Inventar und am Truhenbildschirm gab es
grünliches Grau und ein dumpfes, tristes Braun als Platzhalter. Auf dem
Falcon tönt das UI je Ort auch, aber dezent.

**Ursache:** Thalion zeichnet Rahmen, Fenster und Schrift mit den Farben
24–31 der jeweiligen Palette (`Show_layout` mit Farbversatz 24 und drei
Ebenen; benutzt sind 26–31, `Window_colour` 28, Schrift 31). Thalions
Paletten tönen diese Rampe absichtlich (Städte bräunlich, 3D teils neutral,
teils bläulich). k-means fasste aber Rampenstufen mit Kartenfarben
zusammen: im Inventar (`Main_pal`, Rampe `222 443 665 887 aa9 ccb`) wurden
`222`/`443` zu `432` (Braun) und `665` zu `674` (Grünlich), in den Städten
die dunklen Stufen olivgrün. Ein **festes Grau für alle Paletten** geht
nicht: dieselben Nummern malen auch die Karte, in den Städten (Paletten
7–10) 20–40 % aller Punkte.

**Abhilfe in `St_bauen` (`ST_LIB.S`):**
1. Die Rampe (26–31, ohne doppelte) wird nur unter sich gruppiert, in
   höchstens `ST_RAMPE_REG` = 5 Register. Diese Mitten stehen danach fest.
2. Die übrigen Farben 1–25 (ohne die Werte der Rampe) kommen auf die freien
   Register. Eine Kartenfarbe darf ein Rampenregister mitbenutzen, der
   Abstand dorthin zählt aber doppelt (`stb_naechste`); sonst nähme die
   Rampe bunten Farben ihr Register (im Wald wurden Pilze grau).
3. Eine Farbe der Rampe geht in der Tabelle nur zu einer Mitte der Rampe.
4. In den Wert eines Rampenregisters rechnen nur Farben der Rampe
   (`SE_RMASKE`, `b0st_summieren`), auch beim Blenden.

Chosen from pictures of `tools/st_palettes.py` (formerly
`st_paletten.py`; `ramp`, `screen`, `measure`; pictures in
`build/st_palettes/`), compared with 4 and 6 registers and without
weighting. The mean deviation on the 2D maps stays about the same (world
1.74 → 1.43 levels, towns 1.5 → 1.4; forest palette 2 0.99 → 1.34); only
the forest is visibly dearer: mushrooms lose some brown and red. Since
2026-10-17 that can be corrected by hand (`tools/st_palettes.txt`).

**Checked in Hatari, plain ST:** the tables and masks in the cache
(`Main_pal` and the palette of the cellar) match the recomputation in
`tools/st_palettes.py` **exactly**. The inventory shows Thalion's warm grey
instead of green and brown (screenshot). Chest and towns not looked at in
the emulator, only recomputed.

## Stand: zwei Fehler vom Falcon-Test (2026-10-04, auf dem Falcon getestet)

**Test des Nutzers auf dem Falcon (2026-10-04, ST-Fassung):** Beenden führt
zurück ins richtige Desktop; das Startereignis hat die richtigen Farben;
durch das Ereignis bis auf die Karte ohne Hänger.

- **Erkenntnis 241: eine Palette, die erst nach dem Zeichnen kommt.**
  Thalions Ereignisbild (`ShowPicTxt_Mod`, auch `GameOver_Mod`) zeigt den
  unteren Teil mit der Palette in `Batch` (`R_palette Middle_Y+1,Batch ;
  !!!`), zeichnet Layout, Kästen und Bild aber, bevor die Palette dorthin
  kopiert wird (`EVENTS.S`, `ShowPicTxt_ModInit`). Amiga und Falcon
  schreiben Farbnummern, der ST Register nach der Tabelle der gerade
  geltenden Palette: das Startereignis kam gelb und blau (Savestate des
  Nutzers). Umrechnen geht nicht, die Tabelle legt mehrere Nummern auf ein
  Register. **Abhilfe in `ST_LIB.S` (`St_nr_*`):** Solange ein Platz `Batch`
  trägt und sich deren Inhalt nicht geändert hat, schreiben `Pub_zeilen`
  und `Box_fuellen` mit (Quelle als Abschrift, Puffer 48 KB). Ändert sich
  der Inhalt, zeichnet `St_stand` alles noch einmal, in beide Schirme.
  Hatari, einfacher ST: der alte Bau zeigt das Bild gelb und blau, der neue
  richtig. Maskiertes wird nicht mitgeschrieben (angenommen: kommt dort vor
  dem Füllen nicht vor).
- **Beenden auf dem Falcon:** `Setscreen` mit Auflösung 0 stellte auch das
  VDI auf 320×200; `Close_screen` nahm nur den Modus mit `VsetMode` zurück.
  Das Desktop kam zweimal verkleinert oben, unten weiß. Jetzt schaltet
  `ST.S` auf dem Falcon mit `VsetMode` (STMODES, vier Ebenen, VGA/PAL
  geerbt), wie `FALCON.S`. In Hatari (TOS 4.04, Desktop 640×400 zwei
  Farben) zeigte schon der alte Bau den Fehler nicht; belegt hat es erst
  der Test auf dem Falcon.

## Stand: P5, Tempo auf dem ST (2026-10-03, Hatari; Falcon getestet, STE offen)

**Test des Nutzers auf dem Falcon (2026-10-03, ST-Fassung):** Laufen auf der
Karte spürbar flüssiger; Fenster, Kästen und Inventar mit richtigen Kanten
und Farben (`Box_fuellen`); Kartenwechsel Haus ↔ draußen ohne falsche
oder alte Kacheln (Ladestand). Der Test auf dem STE folgt.

Messung in Hatari, **einfacher ST, 8 MHz, 4 MB**, EmuTOS 1.4, Spielstand
„Anfang“, 500 VBL Laufen hoch und runter in Großvaters Haus (Profiler,
Bilder = Aufrufe von `Schirmwechsel`). Vorher 33 Bilder (ein Bild je
15 VBL, gut 3 Bilder in der Sekunde), nachher **43 Bilder (11,6 VBL je
Bild), rund 30 % mehr**. Die Arbeit je Bild (Profilertakte, nur zum
Vergleich) fiel von 1139k auf 867k:

| Stelle | vorher | nachher | Änderung |
|---|---|---|---|
| `St_kachel` | 130k | 72k | Ladestand statt Prüfsumme (s. u.), dazu die Maske je Zeile |
| `Draw_box` | 91k | 51k | `Box_fuellen`: Randmasken einmal, Ebenenworte nur bei neuem Register, volle Blöcke mit zwei Langworten |
| `St_zeilen_pruefen` | 85k | 46k | Vorstempel (`VBL_counter`, `Module_Sp`, `Work_screen`, `Off_screen`, `Letzte_RL`) vor dem Lauf durch die Liste |
| `Pub_zeilen` | 159k | 115k | erste gegen letzte Zeile statt 16 Vergleiche; Kopie ausgerollt |
| `Masked_icon` | 156k | 127k | Maske fertig aus dem Kachelspeicher; leere Zeilen fallen weg, volle werden kopiert, sonst Langworte |

**The load counter** (`Data_change_count` in `MEMORY.S`, the ST's
`St_ladestand` until main's library split phase 3, 2026-10-25) replaces
the checksum in `St_kachel`: it counts on everything that brings graphics
into memory, and a slot in the tile cache holds only with the count it was
built under. Counted in `Speicher_holen` (`MEMORY.S`), `Eintrag_lesen`,
`Datei_lesen` and `Decompress` (`FILES_SUP.S`), on both machines since
phase 3, and in the ST's `Get_block_orig` (`ST_LIB.S`). On the map none of
them came up in 500 VBL. **Assumption:** Thalion does not rewrite tile
graphics without loading or new memory. If it does, the ST shows a stale
tile; then a counting place is missing (finding 271 says this for the
Falcon).

`Draw_box` springt nach dem Beschneiden nach `Box_fuellen` (eine
Zeile `IFD ZIEL_ST` in `LIBRARY.S`, statt der bisherigen je Zeile).
Absprache: der Nutzer hat alle fünf Punkte freigegeben (2026-10-03); die
2D-Sitzung ist über die Stellen in ihren Dateien zu unterrichten.

Bildvergleich in Hatari: Inventar pixelgleich; auf der Karte weichen nur
Animationsphasen ab (Dampf, Feuer, Kerze), weil mehr Bilder in dieselben
VBL fallen.

Was danach am meisten kostet (je Bild): `Masked_icon` 127k,
`Pub_zeilen` 115k, `St_kachel` 72k, Thalions `Put_unmasked_block`-
und `Put_masked_block2`-Wege (`Maskiert_setzen`) je etwa 65k,
`Box_fuellen` 46k, `St_zeilen_pruefen` 46k, `Get_icon_frame_address` 41k.

## Stand: S2, Paletten je Bildbereich (2026-10-02, Hatari, auf Hardware ungetestet)

Nach dem Hardwaretest von S1 (Nutzer, 2026-10-02: „Farben scheinen
grundsätzlich ok“, es fehlt Timer B) bekommt jeder Bildbereich seine eigenen
16 Register. Die Verläufe (`R_range`: Portraithintergrund, 3D-Himmel) bleiben
vorerst flach (Nutzer: „erstmal ignorieren, nur die Paletten für die groben
Bildschirmbereiche“).

- **Ein Satz je Platz der Rasterliste** (`St_stand`): jede `R_palette` ist
  ein Platz mit Startzeile, Palette und Platz in `Bank_ist`; der erste gilt
  ab Zeile 0. Je Palette 15 Gruppen aus ihren eigenen 31 Farben (S1 teilte
  sie mit Main_pal). Zwischenspeicher acht Einträge, gefunden über den
  Inhalt; was ein Platz gerade trägt, wird nicht verdrängt.
- **Die Tabelle folgt weiter der Palette der Liste** (Erkenntnis 240), die
  Register kommen aus `Bank_ist` (`st_regs_bauen`).
- **Timer B: ein Interrupt je Grenze, nicht je Zeile** (Nutzer). Im VBL
  kommen die Register des ersten Bereichs in die Hardware, und Timer B
  zählt im Ereigniszählmodus bis zur ersten Grenze; der Interrupt stellt
  den Zähler auf die nächste (anhalten, `TBDR` schreiben, starten).
  Grenzen, hinter denen dieselben Werte stehen, fallen weg:

  | Liste | Grenzen | Interrupts je Bild |
  |---|---|---|
  | Karte 2D/3D, Automap, Bild mit Text | Zeile 37 | 1 |
  | Kampf | Zeilen 37 und 133 | 2 |
  | Inventar, Dialog, Charaktereditor | keine (nur Main_pal) | 0 |

- **Eine Zeile Vorlauf.** 16 Register samt Interrupt kosten rund 300
  Takte, der Rand zwischen zwei Zeilen ist rund 190 lang. Timer B löst
  darum eine Zeile früher aus; der Interrupt lädt die Werte in Register,
  zählt eine Zeile ab (Bit 0 in IPRA) und schreibt dann mit einem `movem`.
  Kosten gut 500 Takte je Grenze (unter 1 % eines Bildes).
- **Der Mauszeiger** nimmt je Zeile den Satz ihres Bereichs, wie das
  Sprite auf dem Amiga (Erkenntnis 266): `Zeiger_bild`, gerufen am
  Anfang von `Zeiger_in_puffer` (eine Zeile `IFD ZIEL_ST` in `LIBRARY.S`).
  Seit main den Zeiger im VBL führt (269) rechnet es dort nichts mehr:
  `St_zeiger_bilder` baut das Bild einmal je Platz im Hauptprogramm (neue
  Plätze in `St_stand`, neuer Zeiger in `Pointer_convert`, bis Phase 3 `St_zeiger_wandeln`), unter
  `zeiger_sperre`; `st_zplatz` sagt je Bildzeile den Platz. Der VBL kopiert
  nur sechzehn Zeilen zu acht Byte.
- **Nach dem Einmischen von main bis 4b57a78** (TOS nur über
  `Gemdos`/`Xbios`, 270; Bank je Spanne, 271): in `Draw_box` holt der ST
  das Register weiter je Zeile über `Zeilenfarbe`, statt die Bank zur
  Farbe zu odern.
- **Palettenprüfung einmal je Bild** statt bei jedem Zeichnen: der kurze
  Stempel (Liste, `Letzte_RL`, Hilfsschirm, `VBL_counter`); den Inhalt
  vergleicht `St_stand` nur, wenn er sich ändert. `Platz_setzen` erzwingt
  den ganzen Weg. P2/P3 sind jetzt an den Bau des Satzes gebunden
  (`ST_GEN`), nicht an einen gemeinsamen Zähler: eine neue Palette lässt die
  Kacheln der anderen stehen.
- **Am Falcon an VGA** (ST-Fassung als Prüfstand) zählt Timer B vermutlich
  jede Zeile doppelt; `St_zfaktor` (ST.S, `VgetMonitor`) verdoppelt die
  Zähler. **Angenommen, nicht gemessen.**

**Geprüft in Hatari STE** mit dem Spielstand „Anfang“: Karte (Leiste mit
Main_pal, Karte mit ihrer Palette, die Grenze sauber auf Zeile 37),
Inventar (keine Grenze), Zeiger über Leiste und Karte. Tempo: in 200 VBL
auf der Karte 30.800 statt 24.640 Kachelprüfungen, also rund 25 % mehr
Bilder als P4. **Offen für die Hardware:** ob die Grenze auf dem Gerät
ohne Flackern liegt, auch bei Mausbewegung (der Tastatur-Interrupt läuft
auf derselben Stufe); Kampf; Wechsel Haus ↔ draußen.

**Hardware, 2026-10-03 (Falcon, TOS 4.04, RGB; die ST-Fassung als
Prüfstand):** der S2-Bau vor dem Einmischen gab zwei Bomben (Busfehler).
Mit main eingemischt (TOS nur über `Gemdos`/`Xbios`, 270) und dem Zeiger
VBL-fest: keine Bomben mehr; die Grenze liegt ruhig, auch bei
Mausbewegung; im Kampf stimmen oben und Mitte, das Taktikfeld wirkt
falsch gefärbt (vielleicht nur die Reduktion: `Tactic_pal` hat 31 sehr
verschiedene Farben auf 15 Register; offen, Vergleichsbild Falcon gegen
ST nötig). Laufen fühlt sich langsamer an als die Falcon-Fassung mit acht
Ebenen (auf demselben Falcon; sagt über einen ST wenig). Offen: Haus ↔
draußen, VGA, ein echter ST.

**Hatari, einfacher ST, 4 MB, EmuTOS 1.4:** Startmenü, Karte (Grenze auf
Zeile 37), Zeiger auf der Grenze, Inventar ohne Ausnahme; ohne unteres
Byte der Videobasis kein Busfehler.

## Stand: S1 auf Branch `st` (2026-09-30, ungetestet)

Der ST-Port hat einen eigenen Branch `st` (Nutzer: „bitte eigener
branch“). Er mischt main ein wie `3d`. Vorgabe des Nutzers: **erst
funktional**, Tempo danach, dafür darf später von Leitziel 1 abgewichen
werden.

**Bau.** `tools/baue_alles.sh` baut beide Programme: wie bisher
`FALCON/ENGINE.TOS`, danach `tools/baue_st.sh` mit `VASM_CPU=68000` und
`-DZIEL_ST=1` nach `ST/ENGINE.TOS`, daneben dieselben Spieldateien. Der
Falcon-Bau ist dabei **byteidentisch** zu dem ohne ST-Teil (verglichen mit
`3d`).

**Was der Schalter umlegt:**

| Stelle | Falcon | ST (`ZIEL_ST`) |
|---|---|---|
| `vorspann.i` `Schirm_ebenen` | 8 | 4 (160 Byte je Zeile) |
| `FALCON_OFF.S` `SCHIRM_RAND` | 4 | 8: die Schirme liegen auf 256er-Grenzen |
| Hardware | `FALCON.S` | `ST.S`: Cookies `_MCH`/`_VDO`, ST niedrig über `Setscreen`, 16 Register |
| Farben | Farbbank in den Ebenen 5..7 | `ST_LIB.S`: Tabelle Farbe → Register |
| `Zeilenfarbe`, `Quelle_aufweiten`, `Get_block` (d5 < 8), `Put_masked_icon` | Falcon-Fassung | Sprung nach `ST_LIB.S` |
| `Put_unmasked_block` | Bankebenen | `Pub_zeilen` |
| `Bank0_setzen`, `Palette_anfang` | `FADE_SUP.S` (VIDEL) | `ST_LIB.S` (`$FF8240`) |
| `Set_mouse_ptr` (AREAS.S), `Get_pixel`, Kampf-Zoom, 3D-Schirm | Bank | Tabelle |
| `Basis_setzen` | unteres Byte, Schütteln | nur mit `Feinbasis` (STE, Falcon) |

Dazu ohne Schalter: `SCHIRM_FORMAT` (= 8) statt `PLANES` als Kennung „Quelle
schon im Schirmformat“ in `d5` (beim ST wäre `PLANES` = 4 von Thalions
`d5` = 4 nicht zu unterscheiden), und zwei Kopierschleifen über `TROW`
statt fest 16 Byte (`Duplicate_block`, `Zeiger_aus_rechteck`).

**Die Farben in S1** (`ST_LIB.S`):
- Ein Registersatz für das ganze Bild, **ohne Timer B**. Die Farben von
  Bank 0 (Karte) und Main_pal (Leiste) werden **gemeinsam** in 15 Gruppen
  geteilt (weitester Punkt, dann acht Runden k-means, gerundet auf die
  16 Stufen des STE). Register 0 gehört der Farbe 0 allein, so bleibt 0
  durchsichtig.
- Je Zeile nimmt der Zeichner die Tabelle der Karte oder die von
  Main_pal, wie `Farbbank` beim Falcon die Bank wählt.
- Gefunden wird eine Tabelle über den **Inhalt** der Palette (vier
  Einträge Zwischenspeicher). Neue Palette: rund 0,2 s auf dem ST.
- Beim Blenden bleibt die Tabelle, die Register bekommen das Mittel der
  geblendeten Farben ihrer Gruppe.
- Zurück (`Get_block`, `Get_pixel`) über einen Stellvertreter: je Register
  eine Farbe, deren Tabelleneintrag wieder dieses Register ist.
- **Erkenntnis 240: die Tabelle gehört zur Soll-Palette, nicht zur, die
  gerade steht.** Beim ST legt schon das Zeichnen das Register fest, beim
  Falcon erst die Hardware beim Anzeigen. Thalion baut Schirme im Dunkeln
  auf und blendet danach ein (`Chared_DisInit` → `Open_window` bei
  schwarzer Bank 0). Mit der Tabelle von Schwarz fiel jede Farbe des
  Fensterrahmens auf Register 1: ein flacher „Pergament“-Rahmen, der
  Bestätigungsdialog danach war richtig (Savestates des Nutzers,
  2026-10-01). Jetzt nennt `st_soll` die Palette (Stand nach Erkenntnis
  264, siehe unten).
- **Nach Erkenntnis 264 (main, Platzbank; eingemischt 2026-10-01):** Jede
  R_palette hat ihren Platz in der Rasterliste, `Bank_ist` hält je Platz,
  was zuletzt gesetzt wurde. Ein Modul ohne Liste erbt die des Moduls
  darunter (`st_rl`, wie `Farbbank`). Der ST hat eigene `Platz_setzen`,
  `Bank0_setzen` (= zweiter Platz) und `Palette_anfang`. `st_soll`: die
  **erste** Palette der geltenden Liste außer Main_pal (beim Falcon Bank 0:
  Karte, Bild, im Kampf `Combat_pal`), sonst Main_pal; ohne Liste die von
  `Letzte_RL`, sonst der zweite Platz in `Bank_ist`. Die Register rechnet
  `st_register` aus `Bank_ist`: Soll-Seite über SE_B, der Platz von
  Main_pal über SE_M, beide so, wie Set_fade sie gerade geblendet hat.
  Ein dritter Platz (`Tactic_pal`) nimmt in S1 den Satz der Soll-Palette.
  Karte und Charaktereditor in Hatari punktgleich mit dem Stand davor.

**Tempo, erste Stufe (2026-10-01, ungetestet auf Hardware):**
- P1: `st_zsatz`, je Bildzeile ein Zeiger auf ihren Satz. `St_zeilen_pruefen`
  rechnet die Tabelle nur neu, wenn sich Soll-Palette, `st_gen`, Modul,
  Rasterliste oder Zeichenziel ändern. Die Zeichenschleifen prüfen einmal
  und holen dann je Zeile mit `St_zeilensatz_schnell`.
- P2: Merkliste in `St_block` (4096 Plätze, 128 KB): fünf Quellworte und
  Tabelle ergeben vier Schirmworte. 3D nimmt `St_block_direkt`.
- Gemessen in Hatari (STE, EmuTOS 1.4) über Charaktereditor bis Ereignisbild,
  beim ersten Zeichnen: Wandlung vorher 14,2 Mio. Takte, nachher 8,7 Mio. bei
  mehr Fortschritt im selben Zeitfenster; Trefferquote beim ersten Zeichnen
  etwa die Hälfte. Auf der Karte, wo dieselben Kacheln jedes Bild kommen,
  sollte sie höher liegen; gemessen ist das noch nicht.
- Offen: `St_bauen` kostet 0,7–1 s je neuer Palette (3 `muls` je Abstand,
  acht Runden k-means). Hebel: Quadrattabelle statt `muls`.

**Tempo auf der Karte, P3 (2026-10-01, Hatari, ungetestet auf Hardware):**
- Gemessen mit dem Spielstand „Anfang“ des Nutzers (Platz 1, Großvaters
  Haus, hinter dem Startereignis), Hatari STE 8 MHz, EmuTOS 1.4, 4 MB.
- Vorher (P1+P2): Thalion zeichnet die 2D-Karte in jedem Bild ganz neu, auch
  im Stehen. Ein Bild kostete rund 28 VBL, ein Schritt rund 30 VBL. Die CPU
  wartete nie; rund 85 % lagen in unserer Umsetzung (`St_zeile_amiga`,
  `St_block`), obwohl die Merkliste zu 93 % traf: rund 1.800 Takte je
  16-Punkte-Zeile, rund 160 Symbole je Bild.
- P3: `St_kachel` setzt ein Symbol (ein Block, sechzehn Zeilen) einmal um
  und hält es im Kachelspeicher (2048 Plätze zu 160 Byte, 320 KB). Schlüssel:
  Quelladresse, Tabelle, `st_gen`, Versatz, Ebenen, Prüfsumme der Quelle.
  `Put_unmasked_icon` (über `Pub_zeilen`, wenn alle sechzehn Zeilen
  denselben Satz haben) und `Put_masked_icon` kopieren danach nur noch.
- Nachher: ein Bild rund 10 VBL, ein Schritt rund 10–15 VBL. Die Bilder
  sind punktgleich mit vorher (Karte nach dem Laden und nach dem Laufen).
- Was jetzt zählt (stehend): `St_eintrag`/`St_gleich`/`St_zeilen_pruefen`
  zusammen rund 30 %. Jedes Symbol vergleicht die Soll-Palette (32 Worte)
  aufs Neue. Dann `Masked_icon` 12 %, `Pub_zeilen` 10 %, `St_kachel`
  9 %, `Draw_box` 8 % (LIBRARY.S, 2D-Sitzung).
- P4 (Prüfung billiger, exakt wie vorher): `st_soll` merkt sein Ergebnis
  je Rasterliste und `Letzte_RL` (Thalions Listen sind feste Daten,
  `MODULES.S`), `St_gleich` ohne Schleife, `St_zeilen_pruefen` nimmt die
  Liste von `st_soll`. Gewinn nur rund 5 % (20 statt 19 Bilder in 200 VBL).
  Der Inhaltsvergleich der Palette (32 Worte je Symbol) bleibt, denn
  Thalion kopiert Paletten ohne Bibliotheksaufruf (Erkenntnis 240).
- Stand danach (stehend, je Bild rund 10 VBL): `Masked_icon` 12 %,
  `Pub_zeilen` 10 %, Prüfung (`St_eintrag`, `St_gleich`,
  `St_zeilen_pruefen`) 28 %, `St_kachel` 9 %, `Draw_box` 8 %,
  `Anzeige_setzen` 7 % (Warten auf den Bildwechsel, wie im Original).
- **Vorgemerkt:** Die Prüfsumme (erstes Langwort jeder zweiten Zeile) fängt
  einen neuen Kachelsatz an alter Adresse nur fast sicher. Sauberer: ein
  Zähler beim Laden in `FILES_SUP.S` (2D-Sitzung), den `St_kachel` mit in
  den Schlüssel nimmt. Erst absprechen.
- **Vorgemerkt (Nutzer, 2026-10-01):** Reicht die Laufzeit nicht, wäre ein
  Vorab-Cache denkbar: ein eigenes TOS-Programm, das die Kachelsätze einmal
  für den ST umsetzt und ablegt; das Spiel liest sie dann nur. Berührt
  Leitziel 2, erst nach Freigabe.

**Bekannte Grenzen von S1:**
- Oben und unten teilen sich 16 Register, die Farben sind also gröber als
  nötig. *Erledigt mit S2 (oben).*
- 3D: die Sterne (Ebene 4) gibt es nicht.
- Bildschütteln nur auf STE und Falcon (unteres Byte der Videobasis).
- Langsam: jeder Punkt wird einzeln nachgeschlagen (rund 90 Takte).
- `Mxalloc` gibt es erst ab TOS 2; ein ST mit TOS 1.x bekommt keinen
  Speicher. Für den Test auf dem Falcon egal, für den echten ST offen.
- Adressfehler, die nur der 68000 kennt (ungerade Wortzugriffe), zeigt
  der Falcon nicht.

**Erkenntnisnummern** des ST-Zweigs: 240 bis 249 (main zählt ab 255, 3d
unter 240), abgesprochen mit der 2D-Session.

**Test:** `ST/ENGINE.TOS` auf dem Falcon starten. Es schaltet selbst auf
ST niedrig, an RGB und VGA. Beim Beenden kommen Modus und Farben zurück.

## Ausgangslage

- Der ST hat 16 Farbregister (ST 3 Bit je Kanal, STE 4 Bit), Thalions
  Grafik hat 5 Ebenen, also 32 Farben je Palette.
- Alle 49 Paletten in `Palettes.amb` sind voll: 26 bis 32 verschiedene
  Farbwerte, gemeinsam ist nur Farbe 0. Einen Teil, den alle teilen, gibt
  es nicht.
- Die Grafik nutzt die 32 Farben auch: Kachelsätze, Portraits und die
  meisten Kampfhintergründe belegen 22 bis 32 Nummern.
- Der Amiga zeigt mehrere 32er-Paletten übereinander (Copper). Thalions
  Module beschreiben das hardwarefrei in der `Raster_list` (`RL_PAL` ab
  einer Bildzeile, `RL_RANGE` für Verläufe).

## Die Idee: nur die Palette wird reduziert

Die Bilddaten enthalten keine Farben, nur **Farbnummern** 0 bis 31. Welche
Farbe eine Nummer bekommt, sagt die Palette. Die Reduktion arbeitet deshalb
nur auf der Palette. Je Palette bildet die Bibliothek zur Laufzeit:

    16 Ersatzfarben   -> in die 16 Farbregister des ST
    Tabelle[32]       Nummer 0..31 -> Register 0..15

Beispiel, vereinfacht: Fünf fast gleiche Sandtöne (Nummer 5 bis 9) teilen
sich zwei Register. Das Flammenrot (12) liegt weit weg von allem und behält
ein eigenes.

    Tabelle:  5->3  6->3  7->4  8->4  9->4  ...  12->9  ...

**Beim Zeichnen** liest die Bibliothek die 5 Ebenen aus Thalions Daten wie
heute und erhält die Nummer n. Das geschieht an derselben Stelle wie heute
(`Farbbank`/`Zeilenfarbe`), nur mit einer anderen Rechnung:

    Falcon heute:  Nummer n + Farbbank   ->  8 Ebenen schreiben
    ST:            Tabelle[n]            ->  4 Ebenen schreiben

Thalions Code merkt davon nichts, für ihn bleibt `Screen_depth` = 5. Die
Dateien bleiben, wie sie sind (Leitziel 2).

### Wie die 16 Ersatzfarben entstehen (Art „palette“)

Die 32 Palettenfarben gelten als Punkte im Farbraum (R, G, B).

1. **Weit verteilt anfangen.** Die erste Farbe wird gewählt, danach immer
   die, die von allen gewählten am weitesten weg liegt, bis es 16 sind. So
   bekommen auffällige Einzelfarben sicher ein Register.
2. **Nachschärfen (k-means).** Jede der 32 Farben kommt zur nächsten der 16,
   und jede der 16 wird zum Mittelwert ihrer Gruppe. Das wird einige Male
   wiederholt.
3. **Runden** auf die Hardware: STE 16 Stufen je Kanal, ST 8.
4. **Tabelle:** Jede Nummer zeigt auf ihre nächste Ersatzfarbe.

Seit 2026-10-04 mit **Rampenschutz**: Thalions UI-Rampe (Farben 26–31)
wird für sich gruppiert und behält eigene Register (Abschnitt oben).

### Wann

- **Neue Palette** (`RL_PAL` in der `Raster_list`, `Set_fade`): Die
  Bibliothek rechnet Ersatzfarben und Tabelle und merkt sie sich je Palette.
- **Mehrere Paletten übereinander** (Karte und Oberfläche): Jeder Streifen
  bekommt seine eigenen 16 Farben. Timer B lädt sie an der Streifengrenze,
  als Ersatz für den Copper. **Ohne Timer B geht es nicht**, denn eine
  16er-Palette für den ganzen Schirm müsste mehrere 32er-Paletten tragen.
- **Blenden** (Tag/Nacht, Ein-/Ausblenden, Lichtstufe in 3D): Die Tabelle
  bleibt. Nur die 16 Ersatzfarben werden neu gebildet, als Mittelwert ihrer
  Gruppe aus den geblendeten Farben.
- **Farbe 0** bleibt Register 0. Ob ein Punkt durchsichtig ist, entscheidet
  die Nummer im Original, also vor der Tabelle.

## Messung an allen 2D-Karten

`tools/farbreduktion.py messen --art <art>`: Die Werte stammen aus 357
2D-Karten, jede ganz gerendert (Unterlage und Überlage) mit ihrer Palette.
Die Abweichung wird in Stufen von 0 bis 15 je Kanal gemessen, als Abstand
im Farbraum.

- **Punkte ≥ 2 Stufen:** Anteil der Punkte, deren Farbe sich um mindestens
  2 Stufen verschiebt.
- **Akzentfarbe:** die schlimmste Abweichung einer Farbe, die mindestens
  0,1 % der Karte bedeckt. Sie zeigt, ob seltene Farben untergehen.

| Art | Gewicht | STE: Punkte ≥ 2 St. (Median / Max) | STE: Akzent (Median / Max) | ST: Punkte ≥ 2 St. (Median / Max) | ST: Akzent (Median / Max) |
|---|---|---|---|---|---|
| `palette` | nur Palette | 1,0 % / 49,1 % | 2,2 / 4,1 | 16,0 % / 66,5 % | 2,7 / 3,5 |
| `wurzel` | √ Häufigkeit | 1,2 % / 38,4 % | 2,2 / 4,1 | 7,9 % / 40,7 % | 2,5 / 4,8 |
| `haeufig` | Häufigkeit | 0,7 % / 15,0 % | **3,2 / 10,2** | 0,7 % / 14,7 % | **2,8 / 11,6** |

Lesart:
- **`haeufig`** trifft die großen Flächen am besten, verliert aber die
  Akzente. Feuer, Kristalle und rote Flammen werden grau oder braun (bis
  10 Stufen daneben).
- **`palette`** und **`wurzel`** halten alle Akzente, keiner liegt mehr als
  etwa 4 Stufen daneben. Einzelne Karten verlieren Feinheiten in Verläufen,
  etwa Sandwellen oder das Grün im Gras.
- Auf dem ST enthält die Abweichung auch das Runden auf 3 Bit: Das hätte
  auch eine Palette mit nur 16 Farben. Die Wüste wird dort grünstichig.

### Vergleichsbilder (Entwurf)

Je Zeile eine Karte: links das Original mit 32 Farben, in der Mitte STE mit
16 Farben, rechts ST mit 16 Farben. Die Karten sind 525 (Wüste mit
Kristallburg), 286 (Hof mit Teich) und 455 (Kerker mit Feuer).

**Art `palette`**: nur aus der Palette gerechnet, das Verfahren oben.

*(Picture `bilder/st16_palette.png`, see below.)*

**Art `wurzel`**: Häufigkeit gedämpft. Das Gras bleibt grüner.

*(Picture `bilder/st16_wurzel.png`, see below.)*

**Art `haeufig`**: Gegenbeispiel. Feuer und Kristalle gehen verloren.

*(Picture `bilder/st16_haeufig.png`, see below.)*

The pictures are computed from game graphics. They lie as examples in
`docs/bilder/` of the working repository (user, 2026-09-30), but not in
the published one, because they show Thalion's graphics in full
(2026-10-29). To make them anew: `tools/farbreduktion.py bild --art
<art>`, which writes to `build/farbreduktion/`.

**Nicht geprüft:** Oberfläche (`Main_pal`), Portraits, Kampfbilder,
80×80-Bilder und 3D. Gerechnet ist je ganzer Karte, nicht je sichtbarem Bild,
und ohne Dithering.

## Was es zur Laufzeit kostet

Ein Bild bei 50 Hz hat auf dem ST (8 MHz) rund 160.000 Takte.

### Paletten rechnen: vernachlässigbar

| Was | Wann | Aufwand |
|---|---|---|
| Ersatzfarben und Tabelle bilden | einmal je neuer Palette, dann gemerkt | ~1 Mio. Takte ≈ 0,13 s (gemessen, s. u.) |
| Ersatzfarben beim Blenden | je Bild während der Blende | ~32 Additionen |
| Timer B an den Streifengrenzen | je Bild | 16 Register je Grenze, einige hundert Takte |

**Measured** (2026-10-04, Hatari, plain ST, 8 MHz, build P5): from the
click on WEITERSPIELEN until grandfather's house stands (VBL 710–2300,
253 M cycles) exactly one palette is built, for about 1.0 M cycles (0.4 %,
about 0.13 s). The rest of the loading was `LOB_decompress` (26 M),
`JH_decrypt` (10 M) and the first drawing; since main bcf16d9 (T33,
finding 274) both run Thalion's inner loops (`Crypt_block`, `Lob_core`)
and cost about half (docs/05, map-change speed). The comparison with the
per-frame cache (`St_gleich`) costs 1.3 M over 2527 calls. **Computing
palettes in advance would save at most a little over a tenth of a second
per map change**, not worth it for speed. Hand-picked palettes remain a
question of looks (user, 2026-10-04: browner in the dungeon, because
without floor and ceiling texture it looks very dark on the ST; tactical
field).

Speicher: 64 Byte je Palette (16 Farben und 32 Tabelleneinträge), für alle
Paletten rund 3 KB.

### Zeichnen: hier liegt der Aufwand

Ohne Tabelle könnte man wortweise kopieren (16 Punkte auf einmal). Mit der
Tabelle muss jeder Punkt zerlegt werden: 5 Bits lesen, nachschlagen, 4 Bits
verteilen. Der Nachschlag selbst kostet wenig, etwa 14 Takte. Teuer sind
das Zerlegen und das Zusammensetzen.

| | Takte je Punkt | eine Kachel 16×16 |
|---|---|---|
| wortweise (natives ST-Format) | ~5–10 | ~1.500–2.500 |
| Punkt für Punkt durch die Tabelle | ~50–100 | ~13.000–26.000 |

- **2D-Kartenfenster** (176×144, etwa 150 Kacheln aus Unter- und
  Überlage): Punkt für Punkt 2–4 Mio. Takte, also 0,25–0,5 s je Bild.
  Nativ wären es gut 2 Bilder. **So nicht tragbar.**
- **Oberfläche, Portraits, Fenster:** Sie werden selten gezeichnet, dort ist
  der Aufwand egal.
- **Kampfzoom:** arbeitet schon Punkt für Punkt (`COMBAT_SUP.S`). Die
  Tabelle kostet dort nur einige Prozent mehr.
- **3D:** Die Wände haben ohnehin 16 Farben. Bleiben im 3D-Streifen die
  Nummern 0–15 unverändert, zeichnet der Rasterer ohne Tabelle.

### Ausweg für die Kacheln: einmal wandeln statt jedes Bild

Jede Kachel wird beim ersten Gebrauch mit der Tabelle ins ST-Format
gewandelt: 4 Ebenen, 128 statt 160 Byte. Das geht an Ort und Stelle, ohne
zusätzlichen Speicher. Danach wird sie nur noch wortweise kopiert.

- Kosten: etwa 20.000 Takte je Kachel, einmal. Eine Karte nutzt 100–300
  verschiedene Kacheln, zusammen 0,3–0,6 s, über das Laufen verteilt.
- Die Dateien bleiben unberührt, gewandelt wird die Kopie im Speicher.
- **Steht gegen CLAUDE.md** („Eine Grafik, die wir vorab aufweiten, ist ein
  Umweg“). Für den ST wäre es eine begründete Ausnahme, und nur, wenn die
  Messung zeigt, dass es nicht anders geht. **Entscheidung beim Nutzer.**
- Alternative auf STE und Mega STE: den Blitter nutzen.

## Zielrechner und Palettenweg

*Nachtrag 2026-09-30.* Es gibt zwei Fassungen: eine für den Falcon und eine
für den ST. Wo die ST-Fassung beim Tempo Abstriche macht, zeigt erst die
Messung (Phase 2). Nach dem Zielrechner richtet sich auch, wie die Paletten
behandelt werden.

**Timer B auf dem Falcon.** Der Falcon hat denselben MFP 68901 wie der ST.
Timer B zählt im Ereigniszählmodus die Bildzeilen, auch im 8-Bit-Modus.
**Gemessen**: `tools/rastertest/timerb.s` im Modus `BPS8+COL40` am
RGB-Monitor (Erkenntnis 154). Im ST-Low-Modus des Falcon läuft er wie
beim ST; das ist nicht selbst gemessen.

| | Falcon 8 Bit | Falcon ST-Low | STE / ST |
|---|---|---|---|
| Timer B | ja, gemessen | ja, nicht selbst gemessen | ja |
| Farbregister | `$FF9800`, 256 Langworte, 6 Bit je Kanal | `$FF8240`, 16 Worte, 4 Bit | `$FF8240`, 4 bzw. 3 Bit |
| Farben je Zeile ohne Interrupt | 256 = 8 Bänke zu 32 | 16 | 16 |

**Was auf dem Falcon offen ist**
- *VGA:* 200 Zeilen erscheinen dort verdoppelt. **Angenommen, nicht
  gemessen:** Timer B zählt dann 400 Zeilen je Bild, und der Zeilenzähler
  braucht einen Faktor 2 (erkennbar am Monitorbit in `oldmode`). Probe:
  `TIMERB.TOS` an VGA, „Feuern je Bild“ 4 statt 2.
- *Zittern:* gemessen Zeile 81 statt 100, Spanne 81 bis 131. Ob die Kante
  fest liegt oder springt, ist nicht getrennt (154).
- *Absturz:* `FARBKANT.TOS` endet mit einer Exception, der Grund ist offen
  (156). Die Zahl der Bomben würde ihn eingrenzen.

**Palettenweg je Fassung**

| Fassung | Rasterlisten (`RL_PAL`) | Farbverläufe (`RL_RANGE`, Himmel E4) | Reduktion |
|---|---|---|---|
| Falcon | Farbbänke, kein Interrupt (heute) | eigene Farbeinträge je Zeile, kein Interrupt (Idee) | keine, alle 32 Farben |
| STE | Timer B | Timer B | 32 → 16, 4 Bit |
| ST | Timer B | Timer B, ggf. vereinfacht | 32 → 16, 3 Bit |

**Der Falcon kommt ohne Timer B aus** (Vorschlag des Nutzers, 2026-09-30).
Für die Verläufe ist das eine **Idee, nicht geprüft**: Der Copper ändert je
Zeile das Register einer Farbe n. Unsere Bibliothek schreibt jedes Pixel
selbst, also kann `Zeilenfarbe` im Bereich eines `RL_RANGE` die Farbe n je
Zeile auf einen eigenen Eintrag lenken, den sie einmal mit dem Verlauf
füllt. Platz ist da: belegt sind Bank 0 und Bank 2; ein Himmel von rund 70
Zeilen oder zwei Porträtverläufe zu 35 Zeilen passen in die freien Bänke.
Zu prüfen: ob alle Pixel eines Verlaufs durch unsere Routinen laufen (beim
3D-Himmel durch die Umsetzung vom 3D-Puffer auf den Schirm).

Damit bleiben `RASTER.S` und alle Fragen zu Timer B bei der ST-Fassung.

**Den ST-Bau auf dem Falcon prüfen.** Im ST-Low-Modus sollte die ST-Fassung
auf dem Falcon laufen: Farben und Raster lassen sich dort auf echter
Hardware prüfen. **Das Tempo nicht:** Auch mit 8 MHz ist ein 68030 mit
Cache kein 68000. Das Tempo messen ein echter ST/STE oder Hatari im
ST-Modus (zyklengenau).

## Fassungen und Trennung

*Vorschlag, 2026-09-30; umgesetzt in S1 (oben), mit zwei Abweichungen:
der Schalter heißt `ZIEL_ST`, und statt einer einzigen Naht in
`LIBRARY.S` springen fünf Routinen an ihrem Anfang nach `ST_LIB.S`
(je ein `IFD ZIEL_ST`). Die Falcon-Fassung bleibt dabei, wo sie ist.*

**Zwei Programme:** FALCON (68030, 8 Ebenen, Farbbänke) und ST (68000,
4 Ebenen, Timer B).
- Falcon gegen ST ist ein Unterschied im Aufbau: `PLANES` steckt beim
  Übersetzen in jeder Adressrechnung.
- ST gegen STE ist klein. Die ST-Fassung erkennt den STE beim Start am
  Cookie `_MCH` und schaltet um: Farben mit 4 statt 3 Bit (nur in der
  Rechnung beim Palettenwechsel), Blitter, feines Bildschütteln, DMA-Ton.
  Vorbild ist `D3_CPU`: selbst erkennen statt eines eigenen `ENG020.TOS`.
- Ein drittes Programm lohnt erst, wenn der STE-Weg viel eigenen Code
  braucht (etwa Zeichnen über den Blitter). Das zeigt die Messung
  (Phase 2).

**Ein Quellbaum, kein Fork**, damit die Falcon-Fixes mitkommen:
1. Ein Bauschalter, etwa `ZIEL=FALCON|ST`. Thalions Code und der gemeinsame
   Teil der Bibliothek sind gleich. Je Ziel eigene Dateien: `FALCON.S` /
   `ST.S` (Videl oder Shifter, Paletten, Schirm), `FALCON_OFF.S` /
   `ST_OFF.S`, `RASTER.S` nur für den ST.
2. Eine Nahtstelle statt verstreuter `IFD`: Wo `LIBRARY.S` heute die
   Bankfarbe rechnet (`Farbbank`/`Zeilenfarbe`), ruft sie eine Zielroutine
   (Falcon: Bank + n, ST: `Tabelle[n]`). Das ist der einzige Eingriff in
   `LIBRARY.S`, als kleiner Commit auf main, abgesprochen mit der
   2D-Session, der `LIBRARY.S` gehört.
3. `baue_alles.sh` baut immer beide Ziele (since 2026-10-15
   `build_all.sh`; `build_falcon.sh` and `build_st.sh` build one each). Bricht ein Falcon-Fix die
   ST-Fassung, merkt es sofort, wer ihn macht. Die heutige
   68000-Gegenprobe ist der Anfang davon.
4. Eine eigene Session mit Branch `st`, die main regelmäßig einmischt wie
   3d. Sie besitzt `ST.S`, `ST_OFF.S`, `RASTER.S` und die ST-Hälfte des
   Baus; an gemeinsame Dateien geht sie nur über die Naht und nur
   abgesprochen.

**Zeitpunkt:** Die ST-Session erst, wenn die Falcon-Fassung weitgehend
steht, sonst wird jede Umstellung der Bibliothek zweimal nachgezogen. Naht
und Bau für beide Ziele (Punkte 2 und 3) können früher kommen. Entscheidung
beim Nutzer.

## Grober Plan

**Phase 0, Voraussetzungen**
1. Doppelpuffer B1a (2D-Session, Erkenntnis 200). Auf dem ST Pflicht: 32000
   Byte je Bild zu kopieren dauert länger als ein Bild.
2. Ein Timer-B-Raster, das Thalions `Raster_list` abarbeitet (Copper-Ersatz).
   Timer B zählt die Bildzeilen (154); vorher muss aber der Absturz von
   `FARBKANT.TOS` geklärt sein (156, docs/05). Der Falcon braucht ihn nicht,
   siehe „Zielrechner und Palettenweg“.

**Phase 1, ST-Bildschicht als Bauschalter**
1. `Schirm_ebenen` = 4, 160 Byte je Zeile, 32000 Byte. Die Ebenen liegen
   wortweise verschränkt wie beim Falcon, die Zeichenroutinen laufen schon
   über `PLANES`.
2. Die Farbübersetzung an der Stelle von `Farbbank`, Art `palette`.
3. **Zuerst auf dem Falcon testen:** Er kann den ST-Modus mit 16 Farben und
   Timer B. So prüfen wir die Farben ohne die Tempofrage.

**Phase 2, Tempo auf dem 68000 (E5)**
1. Messen in Hatari im ST-Modus (zyklengenau, nur nach Freigabe):
   Kartenfenster, 3D ohne Böden, Kampfzoom.
2. Hebel: Kacheln beim ersten Gebrauch wandeln (Entscheidung oben),
   STE-Blitter, Rasterer-Stücke selbst schreiben (docs/02 A7).

**Phase 3, der Rest**
- Speicherbedarf gegen 1 MB messen.
- Bildschütteln: Der ST setzt die Bildadresse nur in 256-Byte-Schritten.
  Auf dem STE geht es fein, auf dem ST kopieren oder weglassen.
- Sound: Amiga-Musik auf YM2149 oder STE-DMA, ein eigenes Thema (Beschlüsse
  der Intro-Session).
- 3D: 16 Farben und der 68000-Weg sind da, die Weiche ist auf einem echten
  ST noch ungeprüft.

## Offene Entscheidungen

1. Art der Reduktion: `palette` (keine Zusatzdaten) oder `wurzel` (besser
   im Gras, braucht Häufigkeiten beim Laden oder als Tabelle vom Bau).
2. Kacheln beim ersten Gebrauch wandeln, ja oder nein (nach der Messung).
3. Ob Dithering für einzelne Bilder (80×80, Portraits) lohnt.
4. Zielrechner: ST mit 1 MB, STE oder Mega STE (Blitter). Vorschlag: ein
   ST-Programm, das den STE selbst erkennt (siehe „Fassungen und Trennung“).
5. Wann die ST-Session beginnt, und ob Naht und Bau für beide Ziele vorher
   kommen.

# 13 – Musik

Stand 2026-10-10, Zweig `musik`; begonnen als Bestandsaufnahme vor der Umsetzung. Was
bewiesen ist und was angenommen, steht jeweils dabei.

## 1. Beschlüsse

- Die Musik ist ein eigenes Paket und wird zum Schluss eingebunden (Nutzer,
  2026-09-29). Seit 2026-10-01 hat sie eine eigene Sitzung.
- **Falcon:** Wenn wir wissen, wie der Spieler arbeiten muss, darf es für
  das Tempo ein angepasster Spieler sein (Nutzer, 2026-10-01). Gemischt
  wird auf dem DSP.
- **ST:** Big Alecs YM-Fassung (Abschnitt 6). Die Stücke dürfen mit, werden
  aber nicht mitgeliefert. Liegen sie neben dem Programm, werden sie
  gespielt, sonst bleibt es still (docs/11-Intro-Extro 7.1, Zweig `intro`).
- Musikdaten kommen nie ins Repository, weder Thalions noch die der Demo.

## 2. Thalions Weg im Spiel

Alles bis `Set_music` ist Thalions Quelltext und läuft schon.

| Wer | Was |
|---|---|
| `MAP/MAP.S` `Set_map_music` | Zuerst `Travel_music[Travel_mode]` (wenn `Show_trans`), sonst `Current_map_music`, sonst `Map_music` aus dem Kartenkopf (Byte 3) |
| `MAP/2D_MAP.S`, `COMBAT/APRES.S`, `MAIN.S` | `Set_map_music` beim Betreten, nach dem Kampf, nach dem Laden |
| `MAP/2D_CITY.S`, `MAP/2D_WILD.S` | `Set_music` mit 0: Musik aus |
| `ACTIONS.S` | Lager: `Camp_music` (21), danach `Set_map_music`; Schalter „Musik“ in den Optionen (`Music_flag_bit`) |
| `MAIN.S` | `Fanfare_music` (23), `Game_over_music` (32), `Music_on`/`Music_off`; `Init_program` setzt `Music_flag` aus `Internal_flags` |
| `EVENTS.S` `Sound` | Ereignis „Musik“: Stück setzen oder mit -1 zur Kartenmusik zurück |
| `MAGIC.S` `Magic_music` | Zauber mit Liederwahl: Fenster mit `Song_names`, `Set_music` mit dem gewählten Stück |
| `COMBAT/COMBAT.S` | Kampfbeginn: `Combat_music` (11) |

**`Set_music` (`HULL/VARIOUS.S`)**, `d0` = Stück (0 aus, -1 wieder an),
`d1` = Teilstück. Es lädt `Load_subfile(d0, Music_file)`, also Nummer 25
= `Music.amb`, und ruft den Spieler über das Makro `music`. Drei Variablen
halten fest, welches Stück gewählt, geladen und gespielt ist.
`Relocate_music` hält die Musik an, wenn die Speicherverwaltung den Block
verschiebt, und startet sie danach neu.

**Im Original läuft der Spieler aus dem VBL:** Die VBL-Routine von AM2_CPU
(0:`$21270`) ruft `+24` der Sprungtabelle, wenn `Music_flag` gesetzt ist.
Bei uns ruft `Bibliothek_vbl` (`LIBRARY.S`) in jedem Bild `Musik_vbl`
(`MUSIK_SUP.S`), und das ruft den Takt einmal je 1/50 s Ton (Abschnitt
4b). So stimmt das Tempo auch an VGA mit 60 Hz.

## 3. Die Stücke und ihre Zuordnung

Das Arbeitsblatt für Anhören und Zuordnen (Nutzer, 2026-10-10): Thalions
32 Stücke, Big Alecs 18 YM-Stücke, wie man sie hört und wie man die
Zuordnung ändert. Die Spalte „Notiz“ ist für Höreindrücke.

### 3.1 Thalions 32 Stücke

Namen aus `Text.amb` (`Song_names`, Marke `$386C`, Liste für
`Find_small_text`), Nummer = Listenplatz (`Music_selected` rechnet
`Song_names[d0-1]`). Bestätigt durch `Travel_music`: Die Reisearten treffen
die passenden Namen (Pferd 8, Schiff 6, Scheibe 15, Adler 7, Huhn 25,
Besen 20, Sandgleiter 22). Kartenzahl aus Byte 3 der Kartenköpfe (1.20,
Karten 1–256 aus `1Map_data`, 257–299 aus `2Map_data`, 300–399 aus
`3Map_data`). Keine Musik (0) haben die Weltkarte (1–256) und die
Karten 300–335 außer 309.

Datei = `build/sa/NN_<Name>.sa` (3.3). „Teile“ = Teilstücke (`d1` von
`Set_music`), „Smp“ = Samples; ohne Samples ist das Stück reine Synthese.
„YM“ = das YM-Stück, das die Vorlage `tools/musik_ym.inf` zuordnet (3.2).

| Nr | Name (Text.amb) | Teile | Smp | Verwendung | YM | Notiz |
|---:|---|---:|---:|---|---:|---|
| 1 | Who said "Hi Ho" ? | 1 | 4 | 1 Karte (336) | – | |
| 2 | Mellow camel funk | 1 | 2 | 2 Karten; Sandkriecher | 13 | |
| 3 | Close to the hedge | 1 | 3 | 3 Karten | – | |
| 4 | Voice of the bagpipe | 1 | 4 | 2 Karten (3D) | 8 | |
| 5 | Downtown | 1 | 4 | 2 Karten (3D) | 4 | |
| 6 | SHIP | 1 | 0 | 1 Karte; Schiff | 1? | |
| 7 | Whole lotta dove | 1 | 2 | Adler | 6 | |
| 8 | Horse is no disgrace | 1 | 1 | 1 Karte; Pferd | 10 | |
| 9 | Don't look Bach | 1 | 2 | 1 Karte | 3 | |
| 10 | Rough waterfront tavern | 1 | 1 | 2 Karten | – | |
| 11 | Sapphire fireballs of pure love | 1 | 5 | 3 Karten; `Combat_music` | 14 | |
| 12 | The Aum remains the same | 1 | 2 | 4 Karten | – | |
| 13 | CAPITAL | 1 | 2 | 1 Karte | 7 | |
| 14 | Plodding along | 1 | 2 | 4 Karten; zu Fuß, Schwimmen | 12 | |
| 15 | Compact disc | 1 | 0 | Zauberscheibe | 2 | |
| 16 | Riverside travelling blues | 1 | 3 | 5 Karten (3D); Floß | 11 | |
| 17 | Nobody's vault but mine | 1 | 2 | 5 Karten (3D) | 9 | |
| 18 | La Crypta Strangiato | 1 | 2 | 11 Karten | 5 | |
| 19 | Misty dungeon hop | 1 | 5 | 6 Karten (3D) | – | |
| 20 | Burn baby burn! | 1 | 4 | Hexenbesen | – | |
| 21 | Bar brawlin' | 1 | 1 | `Camp_music` | – | |
| 22 | Psychedelic dune groove | 1 | 3 | Sandgleiter | – | |
| 23 | Stairway to level 50 | 1 | 1 | `Fanfare_music` | – | |
| 24 | That hunch is back | 1 | 3 | 5 Karten (3D) | – | |
| 25 | Chicken soup | 1 | 0 | 1 Karte; Superhuhn | – | |
| 26 | Dragon chase in creepy dungeon | 2 | 3 | 12 Karten | – | |
| 27 | His master's voice | 2 | 1 | – | – | |
| 28 | No name | 1 | 0 | 3 Karten | – | |
| 29 | Oh no not another magical event | 2 | 0 | – | – | |
| 30 | The Uh-oh song | 1 | 0 | – | – | |
| 31 | Owner of a lonely sword | 1 | 0 | 3 Karten | – | |
| 32 | GAME OVER | 1 | 2 | `Game_over_music` | – | |

„–“ bei der Verwendung heißt: nicht über Kartenkopf, Reiseart oder EQU.
Stücke, die nur über Ereignisse (`Sound`) oder den Zauber laufen, sind noch
nicht gezählt. Teile und Samples zählt `tools/sa_auszug.py` (3.3).

### 3.2 Big Alecs 18 YM-Stücke

Nummer = die in `MUSIK_YM.INF` (Stückzeiger im Block, Abschnitt 6), nicht
der Platz im Menü der Demo: das Menü ist alphabetisch. Titel abgelesen aus
der Titelbitmap der Demo (6), Byte = Länge im Block. „Für“ = Thalions
Nummer nach der Vorlage; in Klammern auskommentiert.

| YM | Titel (Demo) | Menüplatz | Byte | Für | Notiz |
|---:|---|---:|---:|---:|---|
| 1 | HE IS SAILING | 5 | 13206 | 6? | |
| 2 | COMPACT DISK | 2 | 15510 | 15 | |
| 3 | DON'T LOOK BACH | 3 | 13206 | 9 | |
| 4 | DOWNTOWN | 4 | 15510 | 5 | |
| 5 | LA CRYPTA STRANGIATO | 7 | 11670 | 18 | |
| 6 | WHOLE LOTTA DOVE | 17 | 11670 | 7 | |
| 7 | CAPITAL | 1 | 10902 | 13 | |
| 8 | VOICE OF THE BAGPIPE | 16 | 13206 | 4 | |
| 9 | NOBODY'S VAULT BUT ME | 11 | 10134 | 17 | |
| 10 | HORSE IS NO DISGRACE | 6 | 13206 | 8 | |
| 11 | RIVERSIDE TRAVELLING BLUES | 13 | 14742 | 16 | |
| 12 | PLODDING ALONG | 12 | 12438 | 14 | |
| 13 | MELLOW CAMEL FUNK | 9 | 15510 | 2 | |
| 14 | SAPHIRE FIREBALLS OF PURE LOVE | 14 | 13206 | 11 | |
| 15 | SAPHIRE FIREBALLS OF PURE LOVE PT2 | 15 | 11670 | (11) | |
| 16 | LA CRYPTA STRANGIATO PT2 | 8 | 10902 | (18) | |
| 17 | MELLOW CAMEL FUNK PT2 | 10 | 10134 | (2) | |
| 18 | (ohne Titel, nicht im Menü) | – | 18992 | ? | |

Damit haben 14 der 32 Stücke eine YM-Fassung; die übrigen 18 bleiben mit
dem YM still (7.2).

### 3.3 Anhören

- **Thalions Stücke am PC:** `tools/sa_auszug.py` zieht sie aus
  `Music.amb` als Sonic-Arranger-Dateien nach `build/sa/NN_<Name>.sa`
  (Musikdaten, nie ins Repository). Abspielen mit UADE (3.05, in
  `~/.local`):

  ```
  uade123 build/sa/*.sa
  ```

  Tasten: Eingabe oder `>` nächstes Stück, `<` voriges, `b`/`z` nächstes
  und voriges Teilstück (26, 27, 29), Leertaste Pause, Pfeil rechts/links
  10 s vor/zurück, `q` Ende. Einzeln: `uade123 build/sa/18_*.sa`.
- **YM-Stücke 1–17:** die Demodisk
  (`ambermoon_gamedata/AMBERMOO.MSA`) in Hatari oder am
  ST, im Menü den Platz aus 3.2 wählen.
- **YM-Stück 18:** nur im Spiel. In `MUSIK_YM.INF` ein Stück, das man
  leicht erreicht, darauf legen (etwa `14 18`: zu Fuß), dann hören.

### 3.4 Zuordnung ändern

`MUSIK_YM.INF` lies next to the game files, since 2026-10-15 one for both
machines: `ATARI/AMBFILES/MUSIK_YM.INF`. The build delivers the template
`tools/musik_ym.inf` only when there is none; a changed one stays. It also
assembles the template into `MUSIK_YM.S` (`ym_inf_vorgabe`, 2026-10-21):
without the file that applies, so a folder copied without `*.INF` (the
test package) plays music too. The game reads the file at start, so
restart after a change. On the Falcon it counts only with `YM` in
`MUSIC=` in `AMBER.INF` (4d).

Je Zeile „Thalions Nummer YM-Stück“, `;` bis Zeilenende ist Kommentar.
Nicht genannte Nummern bleiben still, gilt eine Nummer zweimal, zählt die
letzte Zeile. Beispiel: `21 13` spielt im Lager „Mellow camel funk“.
Steht die Zuordnung fest, kommt sie in die Vorlage `tools/musik_ym.inf`
und in die Spalten „YM“ und „Für“ oben.

### 3.5 Offen

- Ist „He is sailing“ (YM 1) wirklich SHIP (6)? Nur nach dem Namen
  vermutet.
- Was ist YM 18? Kein Titel, das Ende im Block ist geschätzt (letztes Byte
  ungleich null vor dem SNDH der Demo).
- Die drei PT2-Stücke: Thalions 2, 11 und 18 haben in `Music.amb` nur ein
  Teilstück. Statt des ersten Teils, gar nicht, oder für ein anderes
  Stück?
- Die 18 Stücke ohne YM-Fassung: still lassen (so entschieden, 7.2) oder
  ein ähnliches YM-Stück leihen, etwa für Lager (21), Fanfare (23) und
  Game Over (32)?

## 4. `Music.amb` und Thalions Spieler

**`Music.amb`:** AMNP-Container, 32 Einträge, LOB-gepackt, 2–48 KB. Jeder
Eintrag besteht nur aus Daten, vorn 8 Langworte mit Versätzen relativ zum
Anfang. Der erste Bereich ist die Liste der Teilstücke, je 12 Byte. Die
Nummern 26, 27 und 29 haben 2 Teilstücke, alle anderen eins. Das Format
ist das von Sonic Arranger (Kennung „musicirq“, Takt `709379/Tempo`,
Komponist Matthias Steinwachs). Das ist erschlossen, nicht belegt.

**Spieler:** AM2_CPU Hunk 0 `$2AA0E`–`$2BD28` (4,9 KB; ab `$2BD2A`
folgt Blitter-Code der Bibliothek, gerufen von 0:`$1C1B6`), Variablen in
Hunk 3 ab `$37BE`. Sprungtabelle:

| Eintrag | Ziel | Wer ruft | Aufgabe |
|---|---|---|---|
| +0 | `$2AA44` | `Set_music` (`music Music_init`), `a0` = Stück | Versätze in Zeiger umrechnen |
| +4 | `$2AB86` | niemand (abs.) | Interrupt über `ciab.resource` anmelden |
| +8 | `$2AC20` | niemand (abs.) | abmelden |
| +12 | `$2ACCA` | `Set_music` (`music Music_start`), `d0` = Teilstück | starten |
| +16 | `$2AD0E` | `Remove_music`, `Relocate_music` (`music Music_stop`) | anhalten |
| +20 | `$2BC8E` | niemand (abs.) | einen Ton auf Kanal `d1` sofort anschlagen (Klangeffekt), mit `Disable`/`Enable` und sofortigem `DMACON` |
| +24 | `$2ADD6` | VBL (0:`$21278`) | der Takt selbst, einmal je Bild, ohne Betriebssystem. (Über `Cause` (-180) ruft ihn nur der CIA-Interrupt 0:`$2AD98`, den +4 anmeldet; das Spiel tut das nie.) |

**Hardware im Spieler, ausgezählt** (2026-10-01, `am2cpu_lesen.py dis`).
Die Kanäle spricht der Spieler über `a3` an: `lea $DFF0A0/B0/C0/D0,a3` an
drei Stellen je vier (`$2ADE8`, `$2AF7A`, `$2B3BA`) und einmal gerechnet
(`$2BCF0`). Darüber schreibt er:

| Register | Stellen | Wann |
|---|---|---|
| `AUDxLC` | `$2AD4E`, `$2AD6A` | Tick danach: Schleifenanfang (Kanäle mit Merker in `$3D28`) |
| | `$2B280`, `$2B2CA` | Anschlag: Sample bzw. Wellenpuffer des Synthklangs im Kanalsatz |
| | `$2B38E`, `$2B424` | Stille (`$3AF6`); `$2B38E` schreibt nur ein **Wort** (`move.w a0,(a3)`) |
| `AUDxLEN` | `$2AD50`, `$2AD6C`, `$2B228`, `$2B29C`, `$2B2D0`, `$2B390`, `$2B418` | wie LC; beim Anschlag erst 1 |
| `AUDxPER` | `$2B22E` (114 beim Anschlag), `$2B5BE` | Anschlag, Effekte je Tick |
| `AUDxVOL` | `$2B384`, `$2B414`, `$2B5E6`, `$2B626` | Stille, Effekte je Tick |
| `DMACON` | `$2B222` | Anschlag: Kanal aus |
| | `$2AE68` | Ende des Ticks: alle angeschlagenen Kanäle an (`$3D62`) |
| | `$2AAE4`, `$2AC54`, `$2BD14` | Grundstellung, IRQ ab, +20 |
| `ADKCON`, `INTENA`, `INTREQ` | `$2AAEA`–`$2AAF6` | Grundstellung (über `a0` = `$DFF000`) |
| `VHPOSR` (lesen) | `$2BB88`, `$2BBB0` | Zufallsquelle für Rauscheffekte im Synthklang, **kein** DMA-Warten |

Dazu außerhalb der Paula:
- CIA-B Timer A für das Tempo (`$2AC60`–`$2ACA8`, `$BFD000` +
  `$600`/`$700`/`$E00`). `$2AADE` setzt ihn bei jedem Start, auch wenn
  niemand den Interrupt anmeldet.
- CIA-A `$BFE001` Bit 1, Tiefpassfilter: `$2ACCA`, `$2AD0E`, `$2B176`,
  `$2B180` (auch als Effektbefehl).
- exec (`OpenResource`, `AddICRVector`, `RemICRVector`, `Disable`,
  `Enable`, `Cause`) nur in +4, +8 und +20. Der Weg des Spiels (+0, +12,
  +16, +24) braucht das Betriebssystem nicht.

**Was das für eine Nachbildung heißt.** Alle Paula-Schreibzugriffe fallen
in den Tick (+24) oder in Start und Stop, und ihre Reihenfolge ist fest.
Beim Anschlag: `DMACON` aus, LC und LEN aufs Sample, am Ende des Ticks
`DMACON` an. Im Tick danach LC und LEN auf die Schleife; die Paula
übernimmt sie erst, wenn das Sample durch ist. Ein Schattenblock, den der
Mischer **nach jedem Tick** liest, sieht also alles, was er braucht:
`DMACON` mit gesetztem Bit 15 startet die Kanäle aus LC/LEN neu, und LC/LEN
ohne Neustart gelten ab dem nächsten Durchlauf. Der Mischer muss nur
`DMACON` nach dem Lesen löschen. Verloren geht höchstens das „aus“ eines
Kanals, der im selben Tick nicht wieder angeschlagen wird. Der ist dann
aber stumm (Lautstärke 0, Stille-Puffer).

**Stop (+16) schaltet die Kanäle nicht ab.** Er setzt nur je Kanal den
Stumm-Merker (`$2ACAA`). Das `DMACON` davor schreibt Thalions `Set_music`
(`move.w #$000F,Custom+dmacon`, `HULL/VARIOUS.S`). Also muss auch `Custom`
aus `vorspann.i` auf denselben Schattenblock zeigen. Das erledigt zugleich
Befund 3 in Abschnitt 5.

Zwei Dinge muss der Mischer abfangen:
- Nach `$2B38E` steht in LC eine Unsinnsadresse. Die Lautstärke ist dort
  0, der Mischer darf die Adresse trotzdem nicht lesen.
- Synthklänge spielen aus einem 128-Byte-Puffer im Kanalsatz, den der
  Spieler jeden Tick umschreibt. Der Mischer liest also nicht aus einer
  vorab gewandelten Kopie, sondern aus dem Speicher.

**`Intro_music`, `Extro_music`:** eigenständig, mit einer Kopie des
Spielers und einer eigenen Sprungtabelle am Dateianfang (`4EFA` × 7). Das
gehört dem Zweig `intro`, braucht aber dieselbe Paula-Nachbildung.

## 4b. Der Mischer auf dem Prozessor (Schritt 4b, Stand 2026-10-02)

Zwischenstufe vor dem DSP, damit etwas zu hören ist und Thalions Spieler
sich prüfen lässt. Alles in `MUSIK_SUP.S`, 68000-Code.

- **Ausgabe:** DMA-Ton des Falcon über XBIOS (`Locksnd`, `Sndstatus`,
  `Setmode` 16 Bit Stereo, `Devconnect` DMA-Wiedergabe → DAC, 25,175 MHz,
  Vorteiler 7 = 12 292 Hz, `Setbuffer`, `Buffoper` mit Wiederholen).
  `Musik_install` hinter `Raster_install`, `Musik_remove` in
  `Exit_program` und `Speicher_voll` (`MAIN.S`, mit der 2D-Sitzung
  abgesprochen).
- **Ring:** 8 Stücke zu 246 Werten (1/50 s) im ST-RAM. `Musik_vbl` liest
  den DMA-Zähler (`$FF8909`–`$FF890D`) und hält 3 Stücke Vorsprung. Ist
  die Wiedergabe vorbeigezogen, setzt es ein Stück hinter ihr neu an.
- **Takt:** je Stück einmal `+24`, nur bei gesetztem `Music_flag`. Der Ton
  gibt das Tempo vor, nicht der VBL.
- **Paula:** je Kanal Zeiger, Länge, Stelle (16.16). `DMACON` mit Bit 15
  startet neu, ohne schaltet ab, ausgewertet vor und nach dem Takt. Ist
  ein Block durch, lädt der Kanal LC/LEN neu aus dem Schatten.
  Schrittweite = 3 546 895 / Periode / 12 292, Periode mindestens 113.
  Lautstärke über eine Tabelle (65 × 256 Worte), Kanal 0+3 links, 1+2
  rechts, halbe Aussteuerung.
- **Schutz:** Ein Block, der nicht ganz unter `phystop` (oder im TT-RAM
  unter `ramtop`) liegt, wird nicht gelesen; der Kanal spielt Stille, bis
  er neu lädt (0:`$2B38E`).
- **Nicht nachgebildet:** das Tiefpassfilter (`Cia_a_filter`), die
  Modulation über `ADKCON`.

**Auf dem Falcon getestet (Nutzer, 2026-10-03):** Musik in Haus, Keller
und auf der Landkarte, ohne Aussetzer, Klang in Ordnung (nicht mit dem
Amiga verglichen). Das Spiel läuft spürbar langsamer; das war zu erwarten,
der Mischer kostet nach Schätzung 15–17 % je VBL (nicht gemessen). Deshalb
Schritt 4c: der Mischer auf den DSP.

Ein Mitschnitt in Hatari gelang nicht: die AVI-Datei bekam nur eine halbe
Sekunde stillen Ton, mit und ohne Schnellvorlauf. Vermutlich holt Hatari den
Ton für die AVI-Datei aus der SDL-Tonausgabe, und die war ohne Lautsprecher
eine Attrappe (`SDL_AUDIODRIVER=dummy`); nicht nachgewiesen.

## 4c. Der Mischer auf dem DSP (Schritt 4c, Stand 2026-10-04)

`MUSIK_DSP.A56` (DSP56001) und `md_*` in `MUSIK_SUP.S`. Der Mischer aus 4b
bleibt als Rückfall: Ist der DSP belegt (`Dsp_Lock`), oder ist der Bau mit
`VASM_EXTRA="-DMUSIK_CPU=1"` übersetzt, mischt wieder der Prozessor.

- **Bau:** `a56` (Ubuntu-Paket `a56`) übersetzt in `build_engine.sh` (Falcon only; the ST build skips it),
  `tools/dsp_lod.py` macht daraus das Abbild für `Dsp_ExecBoot` (nur
  P-Speicher, höchstens 512 Worte; jetzt 298), `MUSIK_SUP.S` holt es mit
  `incbin`. Ohne `a56` bricht der Bau ab.
- **Ausgabeweg:** `Dsp_ExecBoot`, `Dsptristate(an, an)`, `Devconnect` von
  DSP-Senden auf den DAC, 12 292 Hz. Die SSI sendet im Netzwerkbetrieb zwei
  16-Bit-Worte je Rahmen aus einem Ring in Y (schnelle Unterbrechung).
  Vorab geprüft mit `tools/dspton/` (`DSPTON.TOS`, Sinus 439 Hz): auf dem
  Falcon sauber (Nutzer, 2026-10-03).
- **Arbeitsteilung:** Der Prozessor ruft weiter Thalions Takt und wertet
  DMACON aus, und er folgt jedem Kanal durch Blöcke und Schleifen wie in 4b
  (`mk_holen`). Dem DSP schickt er je Stück und Kanal Schritt, Stelle,
  Lautstärke und genau die Sample-Bytes, die der Kanal liest, drei je
  Host-Wort (`move.l` nach `$FFFFA204`). Tonhöhe, Lautstärke und Summe
  rechnet der DSP, wie 4b: ohne Glättung, Kanal 0+3 links, 1+2 rechts,
  gleiche Aussteuerung.
- **Takt:** Der DSP hält 3 Stücke vor der Wiedergabe. Braucht er eines,
  setzt er HF2; nach jedem Stück antwortet er, ob gleich noch eines kommen
  soll. `Musik_vbl` schickt höchstens 4 je VBL. Den Takt gibt also weiter
  der Ton vor.
- **Kein Hängen:** Jedes Warten auf den Host-Port hat eine Grenze (etwa
  65 536 Versuche). Ist sie erreicht, gilt der DSP als tot (`md_tot`), die
  Musik schweigt, das Spiel läuft weiter.
- **Rechenzeit, gemessen in Hatari (2026-10-04):** Der DSP-Weg spart
  nichts. Profil über 500 VBL an VGA, Spielstände des Nutzers, Stand mit
  Erkenntnis 271 (86ab7f8):

  | | ohne Musik | Prozessor (4b) | DSP (4c) |
  |---|---|---|---|
  | Bilder 2D-Karte (Großvaters Haus) | 166 | 166 | 166 |
  | Bilder 3D (Großvaters Keller) | 125 | 107 | 108 |
  | Musik je VBL, davon Thalions Takt | — | 7,9 %, 2,1 % | 7,8 %, 2,2 % |

  Der Prozessor-Mischer kostet nur etwa 18 Takte je Wert (die Schätzung
  15–17 % war falsch). Den DSP zu füttern kostet ebenso viel: rund 900
  Sample-Bytes je Stück einzeln zusammensuchen, bei kurzen Schleifen
  (Synthie-Wellen) etwa 19 Blockwechsel je Stück, und jedes Wort am Port
  abwarten. Hatari bildet den Engpass am ST-RAM vermutlich nicht voll nach;
  auf dem Falcon fühlt es sich gleich an (Nutzer). Ausweg: die Samples
  einmal je Stück in den DSP laden, dann gehen je Stück nur noch Kopfwerte
  über den Port (Abschnitt 7).

### Messfassungen (Schalter `MUSIKMESS`, `MUSIK_AUS`, `MUSIK_CPU`)

`sh tools/build_falcon.sh && sh tools/musik_messbau.sh` legt drei Fassungen
neben `ENGINE.TOS` in `ATARI/AMBFILES/`: `MESS_OHN.TOS` (ohne Musik, der Ton
wird nicht eingeschaltet), `MESS_CPU.TOS` (Mischer auf dem Prozessor),
`MESS_DSP.TOS` (Mischer auf dem DSP). Alle messen gleich (`mm_*` in
`MUSIK_SUP.S`): je 10 s die Bilder (Wechsel von `Schirm_vorn`), die VBL und
die Zeit in `Musik_vbl`, gemessen mit `_hz_200` und dem Zähler von MFP-Timer
C (26 µs). Beim Beenden schreibt die Fassung `MESS_OHN.TXT`,
`MESS_CPU.TXT` oder `MESS_DSP.TXT` in ihren Ordner, mit dem Mischer, der
wirklich lief. Der Zeilenzähler des Videl taugte als Uhr nicht: in Hatari
zeigte er ein Viertel der Zeit, die der Profiler maß. Mit Timer C stimmen
Messfassung und Profiler überein (Hatari, 2D-Karte: 0,0 / 8,2 / 7,8 %).

**Erste Messung auf dem Falcon (Nutzer, 2026-10-04, 59,6 Hz):** je
Fassung etwa 60–80 s, Strecken nicht gleich, darum die Bildzahlen nur grob
vergleichbar. Musik in `Musik_vbl` (ohne die erste Zeile, Start):

| | Musik % (je 10 s) | beste 10 s (2D) Bilder/s |
|---|---|---|
| ohne | 0,1 | 23,6 |
| Prozessor | 18,4 – 24,3 | 18,1 |
| DSP | 12,5 – 20,9 | 20,5 |

Auf dem Falcon kostet die Musik also zwei- bis dreimal so viel wie in
Hatari (dort 8 %). Der DSP-Weg spart rund ein Viertel, mehr nicht.

## 4d. Choosing the music at run time: `MUSIC=` in `AMBER.INF` (E17)

So that the game can be compared with and without music without a new
build (user, 2026-10-08), the music is chosen at start from a settings
file beside the game files. Since E17 (user, 2026-10-22) that is the
line `MUSIC=` in `AMBER.INF`, read by main's shared reader
`shared/SETTINGS.S` (`Settings_read`, result `Settings_music`); until
then it was `MUSIK.INF` with its first three letters. **A hard cut, no
fallback:** from the cut on (docs/05 E17 step 3) no program reads
`MUSIK.INF` any more. Case does not matter:

| `MUSIC=` | Effect |
|---|---|
| `OFF` | `Musik_install` sets up nothing: no DMA sound, no DSP, no tick (like `MESS_OHN`) |
| `DSP` | the mixer on the DSP (4c); if it is taken, the processor. **Default**, also without the file or without `MUSIC=` |
| `CPU` | the mixer on the processor (4b) |
| `YM` | Big Alec's YM version (section 6a). The default in the ST build; there only `OFF` counts |

The intro and the extro read the same line (`Musik_mischen`,
`AMIGA_MUSIK.S`: `AMBFILES\AMBER.INF` first, then beside the program);
there `YM` means the DSP. In the game `MAIN.S` reads the file once after
`Ordner_suchen` from the cut on, and `Musik_inf_lesen` only takes
`Settings_music`; until the cut `MUSIK_SUP.S` includes the reader itself
and calls it (`SETTINGS_HIER`, it drops out once `MAIN.S` has it).

The build empties `ATARI/AMBFILES` except `*.INF`, so the choice stays.
The file is shared by both machines (one `ATARI/` folder, docs/12): an
`OFF` written for the Falcon also silences the ST. Die Bauschalter gehen vor: `MUSIK_AUS` liest die Datei gar nicht,
`MUSIK_CPU` mischt immer auf dem Prozessor. Thalions eigene Option „Musik
aus“ stellt nur den Takt ab; gemischt wird dann weiter, aber Stille.

Geprüft: im Programm disassembliert; in Hatari (Keller, `DSP`) sind Wahl,
`md_dsp`, `mk_bereit` und `Music_flag` gesetzt, der Ring in Y füllt sich mit
wechselnden Werten und `r7` läuft weiter. Vom Nutzer getestet, zuerst in
Hatari mit Ton (2026-10-08: „klappt alles“).

## 4e. Samples im DSP (Stand 2026-10-09)

Nach der Messung in 4c lag die Last beim Füttern des DSP, nicht beim
Mischen. Seit 4e liegen die Samples eines Stücks im DSP, und je Stück Ton
gehen nur noch Kopfwerte über den Port.

- **Belegt vorab (Analyse, 2026-10-08):** Der Spieler liest den
  Sample-Bereich eines Stücks nur (0:`$2B25E`: `AUDxLC` zeigt hinein).
  Synthie-Wellen kopiert er aus dem Stück in den Puffer am Anfang seines
  Kanalsatzes (0:`$2B2AE`, vier Sätze zu `$CE` Byte ab 3:`$37BE`, höchstens
  128 Byte), und nur diesen Puffer ändern die Effekte. Die Paula liest also
  aus genau drei Sorten Speicher: Sample-Bereich, die vier Synthpuffer,
  Stille (3:`$3AF6` oder `mk_stille`).
- **Größe:** Der größte Sample-Bereich hat Stück 19 mit 42 640 Byte (14 214
  DSP-Worte). Ganz ohne Samples, nur Synthie, sind 6, 15, 25, 28–31.
- **Speicherplan (Annahme: X und Y je 16 K, getrennt):** Y wie in 4c (Ring
  für die SSI, Rohdaten, Kanalpuffer). In X: `$200` Stille (2 Worte),
  `$202` vier Synthpuffer zu 46 Worten, ab `$300` die Samples, drei Byte je
  Wort (Platz für 47 872 Byte). Das Programm hat 451 von 512 Worten.
- **Stückwechsel (`md_proben`):** In jedem VBL, vor dem ersten Stück Ton,
  vergleicht der Prozessor `Playing_music` und den Zeiger 3:`$3AFE` mit dem
  zuletzt geladenen Paar. Ist es neu, prüft er den Stückkopf (erster
  Versatz `$28`, in allen 32 Stücken), liest aus dem letzten Bereich N und
  die N Längen und schickt die Samples am Stück (Anfangswort `$10`, dann W,
  dann W Worte). Passt es nicht, bleibt der alte Weg für alle Kanäle.
- **Je Stück Ton:** `md_planen` legt für jeden Kanal fest, wo er liest.
  `md_ort` bildet die Adresse ab: im Sample-Bereich auf `$300`·3 + Abstand,
  in einem Synthpuffer auf dessen Platz, Stille auf `$200`. Liegen der
  aktuelle und der nächste Block (die Schleife) im DSP, gehen fünf Werte
  hin (Art 1: Anzahl, Adresse, Rest, nächste Adresse, nächste Länge), der
  DSP sammelt die Bytes selbst aus X (`sammeln`, Byte über `mpy` mit 1/3).
  Sonst gehen die Bytes wie in 4c (Art 2). Geänderte Synthpuffer schickt
  `md_synth` vorher, erkannt am Vergleich mit einer Abschrift (`cmpm.l`).
- **Protokoll:** Anfangswort Bit 4 = Samples laden (keine Antwort), sonst
  Bit 0–3 = welche Synthpuffer folgen (je 43 Worte). Dann je Kanal Schritt,
  Bruch, Stelle, Lautstärke, Art und die Werte der Art. Antwort wie 4c.
- **Spielstand laden** (Erkenntnis 273, `main`): `Restart_game` ruft vorher
  `Set_music(0)`. Damit schaltet DMACON alle Kanäle ab, bevor ein Byte
  gelesen wird, und `Remove_music` löscht `Playing_music`; das nächste
  Stück lädt seine Samples vor dem ersten Takt neu. Aus dem Code gelesen,
  noch nicht im Lauf belegt.
- **Getestet (T8, Nutzer, 2026-10-09, Falcon):** „läuft sauber, mehrere
  Stücke“. Nicht ausdrücklich geprüft: reine Synthie-Stücke und Spielstand
  laden (der Testbau hatte 273 noch nicht; T14 hat es inzwischen mit
  Samples im DSP bestanden).
- **Gemessen (Nutzer, 2026-10-10, Falcon, 59,6 Hz, Bau b8ea229):** je
  Fassung 80–100 s, Strecken nicht gleich, die Bildzahlen darum nur grob
  vergleichbar. Ohne die erste Zeile (Start):

  | | Musik % (je 10 s) | davon Thalions Takt % |
  |---|---|---|
  | ohne | 0,1 | 0,0 |
  | Prozessor | 16,4 – 32,8, meist 20–24 | 1,5 – 2,5 |
  | DSP mit Samples | 7,7 – 11,4, meist 10–11 | 1,5 – 2,3 |

  Gegen 4c (DSP 12,5 – 20,9 %) halbiert sich die Last ungefähr. Thalions
  Takt kostet auf dem Falcon so viel wie in Hatari (2,1 %). Der Rest, rund
  8 %, ist unsere Seite: `mk_holen` je Kanal, `md_planen`, der Vergleich
  der Synthpuffer und der Host-Port. Welcher Teil wie viel kostet, ist
  nicht gemessen. Für E14 reicht das: Die Musik kostet auf dem Falcon
  rund ein Zehntel.

## 4f. The mixer as a module (E14, 2026-10-12)

The mixer (4b, 4c, 4e) left `MUSIK_SUP.S` and is now `musik/MISCHER.S`,
for the game, the intro and the extro. No SECTION in it: the includer
places `MISCHER.S` in code, `mischer_daten.i` in data, `mischer_bss.i` in
bss and `mischer_chip.i` (the DMA ring) where memory is ST-RAM.
`mischer_daten.i` pulls in `build/musik_dsp.dsp`, which
`tools/musik_dsp.sh` makes from `musik/MUSIK_DSP.A56`; the game's build
calls it from `build_engine.sh` (Falcon only), the intro's from `amiga_bauen.sh`.

**Entry points**, supervisor, all registers kept except d0 where stated:

| Name | What |
|---|---|
| `Mischer_install` | a0 = parameter block (below), copied. Silent with wahl 0, without 16-bit sound or matrix in `_SND`, or when `Locksnd` fails |
| `Mischer_vbl` | every VBL: mixes ahead, calls the tick once per 1/50 s of sound |
| `Mischer_remove` | only XBIOS, so safe from `etv_term`; harmless without install |
| `Mischer_stand` | d0 = 0 silent, 1 CPU, 2 DSP, 3 DSP dead |
| `Mischer_snd` | d0 = cookie `_SND` (0 without) |

**Parameter block** (`MS_*` in `MISCHER.S`):

| Offset | | Game (`mu_satz`, `MUSIK_SUP.S`) |
|---|---|---|
| 0 | shadow block, custom-register layout | `Paula_schatten` |
| 4 | tick routine, keeps all registers | `mu_takt` → `Sa_spieler+24` |
| 8 | byte "music on", tick only if not 0; 0 = always | `Music_flag` |
| 12 | word: number of the playing song (4e) | `Playing_music` |
| 16 | long: pointer to its first area (4e) | `Am2cpu_3_03AFE` |
| 20 | first of the four channel records, $CE apart (4e) | `Am2cpu_3_037BE` |
| 24 | the player's silence (4e) | `Am2cpu_3_03AF6` |
| 28 | word: 0 silent, 1 DSP (else CPU), 2 CPU | from `MUSIC=` in `AMBER.INF` |

The four 4e fields describe the player in AM2_CPU. The intro has a
different build of the player (entry points elsewhere, $1983 bytes
instead of $131A; intro session, 2026-10-12), so it passes 0 there: the
processor then sends each channel's bytes to the DSP (4c), which costs
host-port time and nothing else.

**What stays in `MUSIK_SUP.S`:** the choice from `AMBER.INF`, the YM switch, the shadow
blocks, the parameter block, the measuring version. `Musik_install`
takes `MUSIC=` (`Musik_inf_lesen`), then calls `ym_install` or `Mischer_install`;
`Musik_vbl` goes to `ym_vbl` or `Mischer_vbl`; `Musik_remove` calls both
removes.

**Leaving the sound as found (5.7).** `Mischer_install` saves the sound
registers before `Sndstatus(1)`: $FF8920 (tracks, mode), $FF8930/32
(matrix), $FF8934/35 (clock dividers), $FF8936 (record tracks), $FF8937
(`ADDERIN`), $FF8938 (`ADCINPUT`), $FF8939 (gain), $FF893A (attenuation).
XBIOS cannot report the matrix, hence the registers; the map is from the
documentation, not measured. `Mischer_remove` then:
- DSP way: `Dsptristate(0,0)`, `Dsp_ExecBoot` with one word, `jmp 0`
  (resets the DSP, so the SSI stops; the mixer no longer runs on),
  `Dsp_Unlock`. No `Sndstatus(1)` any more.
- CPU way: `Buffoper(0)`.
- both: write the saved registers back, `Unlocksnd`.

Test: T22 (docs/05).

## 5. Befunde und ihr Stand

1. ~~Das Makro `music` rief `Set_music` rekursiv auf.~~ Seit Schritt 2a
   springt es wie in AM2_CPU in die Sprungtabelle (`jsr
   Music_routine+4*Befehl`, `Music_init` 0, `Music_start` 3, `Music_stop`
   4).
2. `Block_subfile_nr` ist bei uns 10, AM2_CPU liest `22(a3)`. **Folgenlos:**
   Unser `MEMORY.S` verschiebt keine Blöcke und ruft `Relocate_music` nie
   (2D-Sitzung, 2026-10-01). Ein echtes Feld gehörte in `MEMORY.S`.
3. ~~`Custom+dmacon` schrieb nach `$DFF096`.~~ `Custom` steht seit Schritt
   2a in `MUSIK_SUP.S` und zeigt auf `Paula_schatten`. Im Programm geprüft:
   beide Stellen schreiben nach `Paula_schatten+$96`.
4. ~~`Music_routine` war ein `rts`.~~ Seit Schritt 1 ist es Thalions
   Spieler.
5. **Neu (Tempo):** `Load_subfile` holt `MUSIC.AMB` (536 KB) als ganzen
   Container in den Ein-Platz-Cache von `FILES_SUP.S`. Jeder Musikwechsel
   lädt die Datei also neu und wirft dabei den Container der Karte aus dem
   Cache, und umgekehrt. Erst einmal nur festgehalten: Funktion vor Tempo.
   Abhilfe wäre, nur den Eintrag zu lesen (Fseek) oder einen zweiten
   Cache-Platz einzurichten; beides gehört der 2D-Sitzung.
6. **Neu (Speicher):** Die Speicheranforderung in AM2_CPU (0:`$24574`)
   hat einen Ausweg, den unsere Schicht nicht hat. Fehlt Chip-Speicher und
   ist `Music_flag` gesetzt, dann ruft sie Thalions Musik-aus (0:`$1A02`:
   Bit in `Internal_flags`, `Music_flag` löschen), zeigt den
   Chip-Memory-Hinweis (0:`$263F6`, Text 4:`$7D62`) und versucht es noch
   einmal. Seit Erkenntnis 267 (`main` 69f1643) springt unsere
   Anforderung ohne Speicher in Thalions `Out_of_memory`; ein Ausweg ginge
   über `Speicher_anfordern` (`MEMORY.S`). Nötig erst, wenn der Mischer
   knappen Speicher braucht (ST); der Hinweisschirm gehört dieser Sitzung.

7. **New (Falcon, T10 (a), user 2026-10-12). Fix built with E14 (4f),
   test T22; the plan below became 4f.** YM on the Falcon plays, song changes work (training house, 3D
   city). Two side effects of the other two paths:
   - After a game with `CPU` or `DSP` the desktop has no key click.
   - A game with `YM` after one with `CPU` plays; after one with `DSP` it
     stays silent.

   From the code (`Musik_remove`, `MUSIK_SUP.S`), nothing measured:
   - The CPU path ends with `Buffoper(0)` and `Unlocksnd`, without
     `Sndstatus(1)`. `ADDERIN` stays on the matrix (set in
     `Musik_install`), so the PSG no longer reaches the speaker: no key
     click. That is proven by the code, not by a test. The next YM start
     sets `ADCINPUT`/`ADDERIN` again (`ym_falcon_psg`), so YM plays.
   - The DSP path ends with `Sndstatus(1)`, `Dsptristate(0,0)` and
     `Dsp_Unlock`. The mixer program keeps running in the DSP (SSI in
     network mode, TE/TIE on), only cut off from the matrix. Why the next
     YM start, which sets the same two `Soundcmd`s, stays silent is not
     known. Suspects: the running DSP program, or a setting that
     `Sndstatus(1)` leaves and `ym_falcon_psg` does not restore.

   Plan (2D session's proposal, to be confirmed):
   1. On exit, stop the DSP: a halt command over the host port that clears
      the SSI (CRB = 0), or an empty program via `Dsp_ExecBoot`.
   2. At the end of `Musik_remove`, on both paths, `Soundcmd(ADCINPUT,
      PSG)` and `Soundcmd(ADDERIN, ADC)`: the desktop clicks again.
   3. Test, bundled with the rest of T10: a game with `DSP`, then one with
      `YM`; after each, check the key click on the desktop.
   4. Possible probe without a build: a game with `DSP`, then another
      program that loads the DSP, then a game with `YM`. If YM plays
      then, the leftover mixer program was the cause.

## 6. Die YM-Fassung (Big Alec)

**Origin:** the SNDH archive's `big_alec/ambermon.snd` (since
2026-10-27, main a52e6ce, T37 passed). Released first as the disk
"Ambermoon Music Demo" by PHF/Nokturnal (Sommarhack, July 2019); Grazey
linked player and pieces into the one file the archive carries. Music by
Big Alec/Delta Force, written with his tracker "Triplex", converted from
Steinwachs' Sonic Arranger pieces according to the demo's text. Code
Grazey/PHF and GGN/KUA.

**Extract:** `tools/ym_auszug.py`, the file comes through `AMBER_YMSNDH`
or `--sndh`.
- The block starts at $D6 of the SNDH file. The SNDH version drives the
  player with MFP Timer A and Timer B; the tool binds the 36 bytes of
  Timer B back to Timer D (table `ZURUECK`, every byte checked against
  its old value), because Timer B is the ST's raster.
- The result is checked by SHA-256: the first 241 630 bytes of the block
  the build took from the demo disk until 2026-10-27 (tested on
  hardware, T10 and later). Pieces 1-17 are the same; piece 18
  (untitled, not in `musik_ym.inf`) ends 2714 bytes earlier.
- Until 2026-10-27 the tool read the demo disk's MSA image
  (`AMBER_YMDISK`, `--msa`; `AUTO\AMBER.PRG` packed with UPX 3.09, the
  block unpacked at `$D1D0`-`$48C48`, 244 344 bytes). That way is gone
  (hard cut).

**Block** (241 630 bytes), player and 18 pieces:
- Sprungtabelle: `+0` Start (`d0` = Stück 1–18), `+4` einmal je Bild,
  `+8` Stop.
- Nur PC-relativ adressiert: der Block läuft an jeder Adresse.
- Benutzt MFP Timer A und D. Eingebetteter Text: „so Rasters can be
  used“. Timer B bleibt also für den ST-Raster frei.
- Stückzeiger bei `$F2DA` (relativ zu `$F322`). Alle 18 Stücke haben
  denselben 20-Byte-Kopf.
- Dahinter die Menümusik der Demo, ein SNDH „Amberstar“ von Mad Max.
  Nicht Ambermoon, wird nicht übernommen.

**Titel:** Die Auswahlliste der Demo liegt als Bitmap im Programm (`$89E8`,
je Platz 1040 Byte = 10 Zeilen × 208 Pixel, 4 Ebenen). `--titelbild`
schreibt sie als PNG. Welcher Platz welches Stück startet, steht bei
`$35E6`. Der Wählercode nimmt für den Balken (`× 1040`) und für den Start
(`× 2`) dasselbe `d0`.

Die 18 Stücke mit Titel, Menüplatz, Länge und Zuordnung stehen in 3.2,
die offenen Fragen in 3.5. Die Grenzen der Stücke folgen aus der
Zeigertabelle.

## 6a. Der YM-Spieler im Spiel (Stand 2026-10-10)

`engine/src/HULL/MUSIK_YM.S`, eingebunden am Ende von `MUSIK_SUP.S`, in
beiden Bauten.

**Die Weiche.** Thalions `Set_music` und `Remove_music` rufen über das
Makro `music` `Music_routine+0/+12/+16`. `Music_routine` ist jetzt unsere
Sprungtabelle (sieben `bra.w`, je 4 Byte, im Programmabschnitt); Thalions
Spieler aus AM2_CPU heißt `Sa_spieler` (`am2cpu_code.py`, `am2cpu_lesen.py`).
Ohne YM geht jeder Einsprung unverändert dorthin; `mk_takt` ruft
`Sa_spieler+24` direkt. Mit YM nimmt `mw_start` die Nummer aus Thalions
`Playing_music` (Set_music setzt sie vor `Music_start`), schlägt sie in
`MUSIK_YM.INF` nach und startet das YM-Stück; `mw_init` tut nichts,
`mw_stop` hält an. Das Teilstück in `d0` zählt für den YM nicht.

**Der Vertrag des Blocks** (gelesen im entpackten Block, 2026-10-10):
- `+0` Start, `d0` = Stück 1–18. Rettet die Vektoren von Timer A (`$134`)
  und D (`$110`) und neun MFP-Register (IERA, IERB, IMRA, IMRB, VR, TACR,
  TCDCR, TADR, TDDR) in sich selbst, hängt eigene Interruptroutinen ein
  und setzt VR auf Software-EOI.
- `+4` einmal je 1/50 s; tut nichts, solange kein Stück läuft.
- `+8` Stop: schreibt Gerettetes zurück, **ohne zu prüfen, ob gestartet
  war**, und schaltet den YM stumm (Register 7 = `$FF`, 8–10 = 0).
- Alle drei zerstören Register und brauchen den Supervisor. Die
  Interruptroutinen selbst benutzen kein Register: Sie schreiben mit einem
  `move.l` Registernummer und Wert nach `$FF8800`, ändern ihren eigenen
  Wert und den Vektor und quittieren im ISR.

Daraus folgt:
- Nie `+8` ohne vorheriges `+0`: Die Rettung wäre noch null, und `+8`
  schaltete Tastatur und Timer C ab. Nie zweimal `+0` ohne `+8`
  dazwischen: Dann rettete `+0` seine eigenen Vektoren als die alten.
  `ym_laeuft` hält beides fest.
- `+8` schreibt IERA/IMRA und IERB/IMRB als Ganzes zurück. `ym_stop`
  übernimmt davon nur die Bits von Timer A und D, damit Timer B (der
  ST-Raster) bleibt, wie er vor dem Stop war.
- **`+4` hält Timer C an** (Befund im ersten Hatari-Test, Nutzer
  2026-10-10: nur ein stehender Pfeifton, je Stück anders hoch). Es stellt
  Timer D, indem es `TCDCR` ganz überschreibt (`move.b d1,$FFFFFA1D`,
  `d1` = 0–6, im Block bei `$67A` und `$7B8`), und löscht damit die Bits
  4–6, die Timer C steuern. Damit stand `_hz_200`, mit ihm unser Takt, und
  Timer A/D hielten die letzte Note. Die Demo merkt das nicht, sie ruft
  `+4` aus ihrem VBL. `ym_takt` setzt Timer C nach jedem `+4` zurück.
  Angenommen: Der kurze Halt verschiebt den Takt unhörbar, und das
  Neuschreiben mit demselben Teiler stört Timer D nicht.
- Die Interruptroutinen wählen das YM-Register, ohne das gewählte zu
  retten. Wer den YM in zwei Schritten anspricht (wählen, dann schreiben),
  kann dazwischen umgelenkt werden: TOS beim Tastenklick, bei der Glocke
  und beim Diskettenzugriff (Laufwerkswahl über Port A). Klick und Glocke
  schaltet `ym_install` in `conterm` (`$484`) ab, `ym_remove` stellt sie
  zurück. **Offen:** Laden von Diskette, während Musik läuft, ist nicht
  geprüft; von Festplatte betrifft es nicht.

**Takt:** `ym_vbl` aus `Musik_vbl`, gezählt über `_hz_200`: je vier
Schritte einmal `+4`, höchstens zwei je Bild; lag das Spiel länger fest
(Laden), geht es ohne Nachholen weiter. Damit bleibt es bei 50 Hz, ob der
Schirm mit 50, 60 oder 71 Hz läuft. Ist Thalions `Music_flag` aus, hält es
an.

**Offen, neu durchdenken (Nutzer 2026-10-10): einfacher, ohne Timer C?**
Der Nutzer möchte die Architektur einfacher halten. Die Frage ist, ob wir
es wie die Demo machen: Timer C bleibt aus, solange der YM spielt, und
`+4` hängt nur am VBL, ohne `_hz_200` und ohne `ym_takt`. Die Demo kommt
damit aus, weil sie Tastatur (`$118`, `$FFFC02`) und VBL (`$70`) selbst
bedient und `_hz_200` nie liest.
- *Dafür:* Timer C (200 Hz, dazu TOS mit `etv_timer` 50-mal je Sekunde)
  kostet vermutlich deutlich mehr als die rechnerisch geschätzten 1 %:
  ein Interrupt bei vollem Bus und ausgelasteter CPU. Auf dem ST liegen
  alle MFP-Interrupte auf derselben Stufe; Timer C kann also den Timer-B-
  Raster verzögern. Auf dem Falcon stört er die Caches. Beides angenommen,
  nicht gemessen.
- *Dagegen, und was dann zu lösen wäre:* Die Tastenwiederholung kommt von
  TOS aus Timer C (wir lesen über `Bconin`); laut Nutzer braucht das Spiel
  sie aber nicht (2026-10-10). Die Disketten- und
  Festplattentreiber messen ihre Zeitgrenzen mit `_hz_200`, Timer C
  bräuchte also beim Laden Strom. Die Bildrate ist nicht überall 50 Hz
  (Falcon in T9 59,6 Hz, ST mit 60 Hz); dann bräuchte der VBL-Takt einen
  Zähler über die einmal gemessene Bildrate.
- Entscheidet der Nutzer nach T10. Hängt die Entscheidung an den Kosten,
  lohnt eine Messung mit und ohne Timer C (ST, Hatari-Profiler).

**Laden:** `ym_install` (aus `Musik_install`, Supervisor) lädt
`MUSIK_YM.BIN` mit `Malloc`, vor Thalions Speicherverwaltung, und
vergleicht die ersten 12 Byte mit der Sprungtabelle. Fehlt die Datei oder
passt sie nicht, bleibt `ym_bereit` aus, und die Weiche führt zu Thalions
Spieler wie bisher (auf dem ST: still). Der Block bleibt bis `Pterm`;
`ym_remove` (auch im Notausgang) ruft kein GEMDOS.

**Falcon:** `ym_falcon_psg` legt den YM über den ADC-Eingang in den
Ausgang (`Soundcmd` ADCINPUT = PSG, ADDERIN = ADC), nur mit 16-Bit-Ton im
Cookie `_SND`. Angenommen, nicht belegt: dass das nach einem Programm, das
die Matrix umgestellt hat, nötig und genug ist. Der DMA-Ton bleibt mit
`YM` unberührt (kein `Locksnd`).

**Zuordnung: `MUSIK_YM.INF`** neben den Spieldateien, Klartext, je Zeile
„Thalions Nummer YM-Stück“, `;` bis Zeilenende ist Kommentar. Nicht
genannte Nummern bleiben still (entschieden 2026-10-08, 7.2). Gilt eine
Nummer zweimal, zählt die letzte Zeile. Vorlage: `tools/musik_ym.inf`
mit den 14 Zuordnungen aus 3.2; PT2 und Stück 18 stehen auskommentiert
darin. The build puts it into `ATARI/AMBFILES` (`build_common.sh`, for both
machines) only when there is none; a changed one stays. Without the file
the template built into `MUSIK_YM.S` applies (3.4); before 2026-10-21 the
YM was silent then, and the test package, which leaves `*.INF` out, played
no music on the ST.

**Build:** when the build finds the SNDH file, it writes the block with
`ym_auszug.py` as `MUSIK_YM.BIN` into `ATARI/AMBFILES` (241 630 bytes),
the same file for Falcon and ST. It looks in `AMBER_YMSNDH` through
`tools/paths.py` (variable, `build.cfg`, else `ambermon.snd` in
`ambermoon_gamedata/` next to the repository). Without the
default, `MUSIK_YM.BIN` is missing and the build goes on; if
`AMBER_YMSNDH` is set and the file is missing, it stops. The overview
"Sources and switches" at the start and "Done" at the end say whether
the YM music is on.

**Geprüft:** Falcon- und ST-Bau übersetzen, 68000-Gegenprobe,
Register-, Trap-, Variablen- und Platzhalterprüfung ohne Befund. Im
ST-Bau setzt vasm einen Sprung mehr lang (Warnung 2047, `AREAS.S`:248;
die drei in `MAIN.S` gab es vorher schon; main hat alle vier inzwischen
auf `jsr` gestellt). Gehört in Hatari STE (Nutzer, 2026-10-10, nach der
Timer-C-Behebung): Musik auf der Landkarte, im Haus und im Keller,
Stückwechsel dazwischen, gehaltene Taste wiederholt (Timer C läuft).
Offen: Kampf, Beenden (Desktop still, Tastenklick), Falcon und Mega STE
auf Hardware, Zuordnung (T10).

## 7. Offene Entscheidungen

1. **Falcon-Spieler:**
   - (a) Thalions Spieler aus AM2_CPU beim Bau übernehmen (`$2AA0E`–`$2BD28`
     samt Variablen in Hunk 3). Die Operanden `$DFFxxx`, `$BFDxxx`, `$BFE001`
     biegt der Bau auf einen Schattenblock, wie K1 bei `FAIRY.S`. **Kein
     `trap` nötig** (Abschnitt 4).
   - (b) Einen eigenen Sonic-Arranger-Spieler schreiben, der die Ereignisse
     direkt an den Mischer gibt (erlaubt, 2026-10-01).

   Empfehlung: (a). Der Spieler selbst ist billig: einmal je Bild, vier
   Kanäle, 128-Byte-Puffer. Die Last liegt im Mischen, und das ist in
   beiden Fällen unser Code auf dem DSP. (b) spart kaum Zeit und wäre ein
   Nachbau. Dieselbe Nachbildung trägt auch `Intro_music` und
   `Extro_music`.
2. **ST:** YM song ↔ Thalion's number through `MUSIK_YM.INF` (3.2, 3.4).
   **Decided (user, 2026-10-08):** songs without a YM version stay
   silent, also on the Falcon with `MUSIC=YM` in `AMBER.INF` (no fallback
   to Thalion's version through the DSP), so the Falcon then sounds like
   the ST.
3. **STE:** DMA-Ton mit Paula-Nachbildung oder YM wie der ST.
   **Im ST-Bau (`ZIEL_ST`, 2026-10-10)** fallen beide Mischer weg;
   `Musik_install`, `Musik_remove` und `Musik_vbl` führen zum YM-Spieler
   (6a). Das spart 44 932 Byte (Text, Daten, BSS; ST-Bau aus `st`
   mit dieser `MUSIK_SUP.S`). Der Falcon-Bau bleibt byte-gleich. Vorher
   hielt nur der Cookie `_SND` den ST still.
4. ~~**Falcon, Samples im DSP**~~ (nach der Messung in 4c): umgesetzt in
   4e. Beide Fragen sind beantwortet: Die Samples passen (höchstens 42 640
   Byte), und der Spieler schreibt nur in seine Kanalsätze.
5. **PAL (Nutzer, 2026-10-03):** am RGB-Monitor 50 Hz. Für die Musik ändert
   sich nichts: den Takt gibt der Ton vor, nicht der VBL. An PAL fällt
   genau ein Stück je VBL an, und je VBL stehen 20 % mehr Takte zur
   Verfügung. Umzustellen ist die Anzeige der Engine (2D-Sitzung).

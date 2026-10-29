# Fantasy-Intro, Intro, Extro

Bestandsaufnahme vom 2026-09-29 (Zweig `intro`). Hier steht, was die drei
Vorspann- und Abspannprogramme enthalten und wie sie zum Spiel stehen,
dazu ein Vorschlag, wie sie nach den Leitzielen auf den Atari kommen.
**Bewiesen** heißt: am Binärcode oder an Thalions Quelltext nachgeprüft.
**Angenommen** ist ausdrücklich so markiert.

## 1. Die Programme und ihre Übergaben

| Programm | Quelltext | Datei | Aufbau |
|---|---|---|---|
| Fantasy-Intro (Fee, Thalion-Logo) | **`FAIRY.S`**, 858 Zeilen, ein Teil davon | `Fantasy_intro`, 48 KB, Imploder | 4 Zielhunks, Code 4584 Byte |
| Intro (Geschichte, **Startmenü**) | keiner | `Ambermoon_intro`, 516 KB, ungepackt | Code 20668 Byte, 4 Datenhunks, 2 BSS |
| Extro (drei Enden) | keiner | `Ambermoon_extro`, 132 KB, Imploder | 6 Zielhunks, Code 12336 Byte |
| Musik | keiner | `Intro_music`, `Extro_music` | Abspieler + Stück für Paula (Sprungtabelle am Anfang) |

**Übergaben (bewiesen, soweit im Code sichtbar):**

- Intro und Extro lesen beim Start einen Satz über `a0`. Beim Intro
  (kartiert 2026-09-30, 4.2) ist das erste Langwort **ein Zeiger auf den
  Musikspieler**, den Thalion mit `jsr (a0)`, `jsr 12(a0)` … aufruft, keine
  Kennung; dazu ein Merkerbyte bei `4(a0)`. Das Intro gibt am Ende die
  Menüwahl in `d0` zurück (`move.w <Var>,d0 / rts`, Hunk 0 $E4).
- Die Kennung `$00ABACAB` gehört zur **anderen** Seite: Sie steht in dem
  Satz, den das Spiel beim Start in `a0` bekommt, gefolgt vom Wort
  `Intro_menu_choice` und einem Byte (docs/04, Erkenntnis 251). Der Lader des
  Amiga reicht also die Wahl des Intros in einem neuen Satz an das Spiel.
- Das Spiel endet in Thalions `End_seq` (`EVENTS.S`) mit `Return_value` =
  `GAME_COMPLETED`, `GAME_COMPLETED2` oder `GAME_COMPLETED3`, je nachdem ob
  Valdyn in der Gruppe ist und ob er „das Ding“ hat. Ambermoon.net nennt
  die drei Enden des Extros genau so (`OutroOption`).
- **Thalions Lader** ist das Programm `Ambermoon` im Hauptverzeichnis der
  Spieldaten (Imploder, 5392 Byte; gelesen 2026-09-30, entpackt nur im
  Scratchpad). Belegt ab Hunk 1:$1AE:
  1. `Saves` laden, `tst.w (a0)` / `sne Merker`: **Der Merker ist gesetzt,
     wenn der zuletzt gespeicherte Platz nicht 0 ist**, ohne Namensprüfung.
     Fehlt `Saves`, endet der Lader.
  2. `Fantasy_intro` starten. Es liest keinen Satz; die linke Maustaste kürzt
     dort ohne Bedingung ab (Hunk 0 $212, $254).
  3. `Intro_music` laden, `Ambermoon_intro` mit `a0` → {Musik, Merkerbyte}
     starten. Wahl 3 → Ende.
  4. Sonst `a0` → {`$00ABACAB`, Wahl als Wort, ein Byte} und `AM2_*` starten.
  5. Rückgabe des Spiels: 0 oder -1 → Ende; zwischen -1 und -5000 eine
     Fehlermeldung; **≤ -5000: Ende n = -d0-5000** → `Extro_music` laden,
     `Ambermoon_extro` mit {Musik, n} starten, danach „Would you like to see
     the ending again?“ als Schleife.

**Der Lader `AMBER.TOS`** (`lader/lader.s`, erster Stand getestet 2026-09-30;
Stufe I4 Test bestanden, Nutzer 2026-09-30) macht es wie Thalions Lader:

| Schritt | Befehlszeile | Ergebnis |
|---|---|---|
| `SAVES` lesen | | Merker = erstes Wort ≠ 0; fehlt `SAVES`: 0 (Thalion endet dort) |
| `FANTASY.TOS` | leer | wird nicht ausgewertet |
| `INTRO.TOS` | `1` mit Merker, sonst `0` | Menüwahl 0, 1 oder 3 |
| `ENGINE.TOS` | `0` (WEITERSPIELEN, nur mit Merker) oder `1` (NEUE QUEST) | bei QUIT gar nicht gestartet |
| `EXTRO.TOS` | `0`–`2` = -Rückgabe-5000 | nur wenn `ENGINE.TOS` mit -5000 bis -5002 endet; danach „Das Ende noch einmal sehen? (J/N)“ |

**Ablage wie `Amberfiles/` beim Amiga** (Erkenntnis 262, Test bestanden 2026-10-01): On top, in
`ATARI/` (until 2026-10-15 `FALCON/`), lie only the loader `AMBER.TOS`
(since 2026-10-21 one for both machines: the cookie `_MCH` decides; on the
ST it starts `FANTSYST.TOS`, `INTROST.TOS`, `ENGINEST.TOS`, `EXTROST.TOS`)
and the desktop files, everything else in
`ATARI/AMBFILES/`, also `FANTASY.TOS`, `FEEMESSB/C.TOS` and `INTRO.TOS`. Der Lader sucht jede Datei zuerst als `AMBFILES\Name`, dann
als bloßen Namen (flache Ablage); das Arbeitsverzeichnis bleibt seines, von
dort findet `ENGINE.TOS` den Ordner. Fantasy-Intro und Intro lesen zur
Laufzeit keine Dateien.

Die Befehlszeile ist ein Längenbyte 1, eine ASCII-Ziffer und eine Endnull.
Fehlt `INTRO.TOS`, gibt es einen Ladefehler oder eine unbekannte Wahl,
startet `ENGINE.TOS` mit leerer Befehlszeile und zeigt sein eigenes
Startmenü. Jedes Programm läuft auch allein; fehlt eines (-33, -34), geht
es still weiter, jeder andere Ladefehler wird gemeldet. Nur 68000-Befehle.
**Abgesprochen mit der 2D-Session (2026-09-30):** `ENGINE.TOS` setzt aus der
Ziffer Thalions `Intro_menu_choice` und überspringt sein Ersatzmenü; bei 1
legt Thalions `Init_program` den Charaktereditor auf. `SAVES` wird dann
unverändert aus Thalions Daten ausgeliefert (letzter Platz 0), damit gilt
Thalions Regel wörtlich (main 3423cfd, hier eingemischt).

**Das Startmenü steht in `Ambermoon_intro`**, nicht in AM2_CPU. Die
2D-Session hat ein schlichtes Menü in der Bibliothek gebaut
(`HULL/STARTMENUE.S`, Texte beim Bau aus Hunk 1 ab $297 über
`tools/intro_auszug.py`). Es bleibt die Zwischenlösung, bis das Intro läuft
(Absprache 2026-09-29).

## 2. Der Imploder-Entpacker (`tools/imploder_exe.py`)

`Fantasy_intro` und `Ambermoon_extro` sind mit dem Imploder gepackt. Die
alte Fassung des Werkzeugs lieferte falsche Grafik; deshalb kamen die
Bilder der ersten Intro-Übertragung aus einem UAE-Speicherauszug. Behoben,
**bewiesen durch die Selbstprüfung** (der Strom ist genau aufgebraucht,
der Zähler steht auf null, und alle Zielhunks sind abgeschlossen):

- **Der Ring bleibt stehen.** Der Kern ($84–$1F8 im 512-Byte-Codehunk)
  füllt je Aufruf einen Ringpuffer (18692 bzw. 18628 Byte). Ein
  Rückverweis über das Ringende liest den **vorigen** Block. Die alte
  Fassung legte jedes Mal einen leeren Puffer an: Der Code kam richtig
  heraus, in der Grafik waren 20000 Byte falsch.
- **Der entpackte Strom ist ein Befehlsstrom** ($00–$6A): Langwort mit
  Bit 31 = nächster Zielhunk, Bit 30 = Relokationsgruppen, sonst die Zahl der
  Datenlangworte. Die alte Fassung schrieb den Strom roh in die Hunks 7 und 2.
- Das Startstück (Hunk 0) springt danach an den **Anfang von Hunk 1**.

`python3 tools/imploder_exe.py <Datei> <Ziel>` legt die Hunks und
`relok.txt` ab. Beide Dateien gehen durch, der Kern ist derselbe, die
Parameter liest das Werkzeug aus dem Code.

## 3. Fantasy-Intro

### 3.1 Aufbau (bewiesen)

| Hunk | Inhalt |
|---|---|
| 1 (Code, 4584 Byte) | das ganze Programm, darin `FAIRY.S` |
| 2 (Chip, 121356 Byte) | Grafik und Tabellen, siehe unten |
| 3 (8740 Byte, BSS) | Variablen: `palette0` $20, zweite Palette $60, `vindex` $A0, `magic_buffer` $102 (400 × 6), `plot_buffer` $A62 (96 × 10), `plot_buffer2` $E22 (512 × 10) … |
| 4 (Chip, 103200 Byte, BSS) | zwei Schirme zu 51200 Byte (320 × 256, 5 Ebenen) und zwei Copperlisten |

Grafik in Hunk 2, festgemacht an den Verweisen aus Hunk 1:

| Versatz | Name in FAIRY.S | Inhalt |
|---|---|---|
| $0000 | — | Palette der unteren Bildhälfte (32 Farben) |
| $0040 | (`palette0`) | Palette, eingeblendet nach Hunk 3 $20 |
| $0080 | `stars` | Sternbilder (`lea stars-100,a0`) |
| $01AC | `elfe` | Fee: 23 Bilder × 8 Sprites × 73 Langworte |
| $D38C | `background` | Hintergrund 320 × 256 × 5, auf beide Schirme kopiert |
| $13C3C | — | Blitquelle im Rahmen ($BC0) |
| $19B8C | `overfunkel` | Funkelbilder |
| $1A3FC | `flogo` | Schriftzug „Fantasy“ |
| $1CE22 | — | Flugbahn der Fee: Wortpaare x, y, Marke 12345 |
| $1DA06 | `sprite_00` | leeres Sprite |

`magic_offstab` (19 Punkte des Zauberstabs) liegt in **Hunk 1 bei $1188**.
Die alte Übertragung hatte sie aus Ambermoon.net abgeschrieben.

### 3.2 `FAIRY.S` ist Thalions Quelltext dieses Programms (bewiesen)

vasm übersetzt die **unveränderte** `FAIRY.S` zu 2892 Byte. Im
Binärcode stehen sie in zwei Stücken: `level3`…`vsync` bei
$D88–$102A und `make_magic`…`plot31` bei $316–$BC0.
Verglichen wurde mit ausgeblendeten Relokationsfeldern. Das Ergebnis ist
**bytegleich bis auf 21 Befehle und 4 Sprünge**:

- Thalions Assembler kodierte `add/sub/and/or #n,Dn` als
  `addi/subi/andi/ori`, vasm nimmt die kurze Form. Wirkung und Flags sind
  gleich. `-devpac` ändert daran nichts.
- Die vier `bsr new_funkel` in `level3` springen über die Stückgrenze. Weil
  Thalions Programm die Stücke anders anordnet, ist die Weite eine andere;
  das Ziel ist dasselbe.

`FAIRY.S` definiert die Namen aus Hunk 2 und Hunk 3, die Konstanten
(`planes` = 5, `bpscanl` = 200, `star_anz` = 400, `funkel_anz` = 96 …) und
das Makro `waitblit` nicht. Die Werte stehen im Binärcode.
`tools/fantasy_auszug.py` wiederholt diesen Vergleich bei jedem Bau und
gewinnt daraus die Adressen der 27 fremden Namen. Dazu setzt es jeden Namen
auf einen Probewert und liest an den Relokationen ab, wohin Thalions Code
zeigt.

**Was nur im Binärcode steht** (rund 1700 Byte):

| Bereich | Inhalt | Art |
|---|---|---|
| $000–$10E | Start: Betriebssystem abschalten, Rückkehr | Amiga-OS |
| $110–$2B0 | Hauptablauf: Einblenden, Warten, Schleife mit 16,7 Bildern/s (`vindex` ≥ 2, dann noch `vsync`: drei VBL je Bild), Maustaste, Ausblenden | gemischt |
| $2B0–$314 | Ende, Interrupts zurück | Hardware |
| $BC0–$C08 | ein Blit des Rahmens | Blitter |
| $C0A–$C96 | Schirme tauschen, Schirme einrichten | Speicher |
| $C98–$D10 | **Copperliste** mit dem Palettenwechsel | Copper |
| $D22–$D82 | Hardware einrichten | Hardware |
| $102A–$106C | Bildfenster (DIW/DDF/BPLCON) | Hardware |
| $106E–$10CE | Joystick und Maustaste lesen | Hardware |
| $10D0–$1146 | Farben ein- und ausblenden (12 Bit, je Schritt ±1) | Speicher |
| $1148–$1186 | Maskentabellen | Daten |
| $1188–$11D3 | `magic_offstab` | Daten |
| $11D4–$11E6 | Schirm füllen | Speicher |

### 3.3 Der Palettenwechsel im Bild (bewiesen)

Die Copperliste (Aufbau bei $C98) wartet auf die Rasterzeile $AE und lädt
dort sechs Farbregister neu: **20, 21, 22, 29, 30, 31**, aus der zweiten
Palette (Hunk 3 $60, eingeblendet aus Hunk 2 $0). Der Schirm beginnt bei
Zeile $28 (`add #$28,d1` in `level3`), der Wechsel liegt also bei **Bildzeile
134**. Genau ab dort lässt `new_funkel` die Funken zu (`cmp #134,d1`).
Oben und unten sind demnach je 32 Farben. Auf dem Falcon sind das zwei
Farbbänke, die Bank ergibt sich aus der Bildzeile, wie im Spiel
(`RASTER_RAUM`).

### 3.4 Wo `FAIRY.S` selbst die Hardware anfasst

`FAIRY.S` ist die einzige Datei Thalions, die unmittelbar auf die Hardware
zugreift. Bei `level3` ist das so, weil die Routine ein Interrupt ist.
Alle Stellen:

1. `level3`: Palette nach `$DFF180`/`$DFF1A0` (32 Farben je Bild),
   Spritezeiger nach `$DFF120` (8 Sprites, „attached“, 16 Farben aus 16–31),
   Interrupt quittieren (`$DFF09C`).
2. `skip_level3`: Spritezeiger auf `sprite_00`.
3. `make_magic`, `blit_star`, `blit_star2`: der Blitter über `a6` =
   `$DFF000` und `waitblit`. Es gibt zwei Arten: Minterm `$E2` (Spalte des
   Schriftzugs mit Maske `mbl_masks`) und `$CA` (Stern mit Maske,
   verschoben).
4. Das Bildformat ist fest eingebaut. Die Plotroutinen `plot00`…`plot31`
   schreiben mit festen Abständen 40, 80, 120, 160: fünf Ebenen,
   zeilenverschachtelt, 200 Byte je Zeile. Das ist Amiga-Format, der Falcon
   kann es nicht anzeigen.

## 4. Intro (`Ambermoon_intro`)

Ungepackt, 648 Relokationen, keine Symbole, **kein Quelltext**. Kartiert
am 2026-09-30 aus dem Binärcode (alles hier ist **am Code nachgeprüft**,
wo nicht „angenommen“ dasteht). Versätze sind Hunk:Versatz.

### 4.1 Hunks

Die Namen der Bilder sind teils nach Ambermoon.net **angenommen**; die
Versätze, Größen und Verwendungen sind am Code nachgeprüft.

| Hunk | Art | Größe | Inhalt |
|---|---|---|---|
| 0 | Code | 20668 | Programm $0–$2C04; großer Zeichensatz (Breiten $2C06, Zeichen $2C52, 88 Byte = 22 Zeilen × 32 Bit); Ausgabe mit kleinem Zeichensatz $466C–$4754 (Breiten $4756, Zeichen $47A2, 22 Byte = 11 Zeilen × 16 Bit); maskierter Blit $4E2A; Imploder-Entpacker im Speicher $4F5C (Kennung `IMP!`) |
| 1 | Daten | 1372 | Paletten ($80, $C0, $E0, $100, $120, $140, $160, $180, $1C0, $1E0), Farbfolge $200, Texte: „GEMSTONE“, „ILLIEN“, „SNAKESIGN“ ($242–$25A), „PRESENTS“ $265, „TWINLAKE“ $26E, „LYRAMION“ $277, „70 Jahre“/„danach…“ $280/$28B, **Startmenü $297**, Textliste ab $2CC (Abspann, Geschichte, mit Steuerbytes), Tabellen ab $4FE (Planeten der Raumszene) |
| 2 | Daten | 97904 | $0 und $1954: Imploder-gepackte Bilder (Twinlake, Menühintergrund; angenommen nach Ambermoon.net); $8E6E drei Stadtbilder zu 2560 Byte |
| 3 | Daten | 261208 | Animationsdaten (Twinlake), gelesen ab $0 über $1165E |
| 4 | **Chip** | 132640 | Grafik: Logo $0, $1480, Planeten ab $42B8 (je 2048), $D2B8 Meteor, $E338 Animation (je 1880), $1BF88/$1E288 Menügrafik, $20588 **Mauszeiger** (zwei Sprites), $20618 leeres Sprite |
| 5 | BSS | 74288 | Variablen; $0 Musikspieler, $4 VBL-Zähler, $8/$C zwei Copperlisten, $18/$1C/$20 Schirmzeiger, $28 Ebenenzahl, $3B0 Sternfeld, $12172 **Menüwahl**, $12182 schwarze Palette, $121C6/$121E6 die 32 Farben, die der VBL setzt |
| 6 | **Chip** | 148844 | Schirme und Copperlisten, ab $C0 |

### 4.2 Rahmen und Übergabe

- **Start ($0):** Satz aus `a0` übernehmen: Langwort → 5:$0 (Musikspieler),
  Byte `4(a0)` → 5:$12212 und 5:$12213. Über ExecBase AttnFlags prüfen, ob
  ein 68010+ da ist, dann im Supervisor den VBR holen (`movec vbr,a0`,
  $114). `graphics.library` öffnen, ActiView und copinit merken,
  `LoadView(0)`, dreimal `WaitTOF`, DMACON und INTENA merken, Level-3-Vektor
  merken und **`trap #0` auf $12C umbiegen**: Das ganze Intro läuft im
  Supervisor. Kein `dos.library`, **keine Dateien**: Alles steht in den
  Hunks.
- **Ende ($1152):** Musik anhalten (`jsr 16(a0)`), Interrupts und DMA
  zurück, `LoadView(ActiView)`, COP1LC = copinit, `CloseLibrary`, dann
  `moveq #0,d0 / move.w 5:$12172,d0 / rts` ($E2).
- **Merkerbyte `4(a0)` ≠ 0:** Das Intro wird übersprungen ($252 → $C90),
  und das Menü bietet WEITERSPIELEN an; bei 0 fehlt dieser Eintrag, und
  Zeile 0 ist nicht wählbar. Thalions Lader setzt es, wenn `Saves` einen
  zuletzt gespeicherten Platz nennt (Abschnitt 1, belegt).
- **Menüwahl** (5:$12172): 0 WEITERSPIELEN, 1 NEUE QUEST STARTEN, 2 INTRO,
  3 QUIT. **INTRO (2) springt nach $12C zurück**, das Programm endet dann
  nicht; zurück kommen nur 0, 1 und 3.
- **Musikspieler** (Sprungtabelle, Aufrufe nur so gesehen): `+0` Anfang
  ($250), `+12` Stück `d0` (0 im Vorspann, 1 im Menü), `+16` Ende, `+24`
  je VBL, solange 5:$12148 gesetzt ist.

### 4.3 Ablauf

| Code | Szene |
|---|---|
| $12C–$2C2 | Grundstellung, Schirm 320 × 200 × 5 (`$289A` mit `d0` = Zeilen, `d1` = Ebenen), Musik an, Logo (4:$0) einblenden |
| $2C2–$3B0 | „PRESENTS“ mit großem Zeichensatz, zweites Bild (4:$1480), Blenden |
| $3B0–$926 | **Raumszene**, eine Schleife ab $568: Schirm 320 × 236 × 4, Sternfeld (150 Sterne, Zufall $1B20), Planeten perspektivisch (`divs` durch z = 5:$1212C, von −7000 bis 22248), **Bilder spaltenweise mit dem Blitter gezoomt** ($1BAE…$2360); nach der Zeittafel $11C8 die Stadtbilder aus 2:$8E6E mit „GEMSTONE“, „ILLIEN“, „SNAKESIGN“; dazu die Textliste ab 1:$2CC (Abspann, dann „20 Jahre nach den Ereignissen …“) mit kleinem Zeichensatz, gesteuert über Steuerbytes ($812–$910) |
| $926–$B24 | **Twinlake**: Bild aus 2:$0 entpacken, „TWINLAKE“, Animation aus Hunk 3 ($165E, $12C0), Bildfenster wandert (DIWSTRT/DIWSTOP aus einer Tabelle) |
| $B24–$C90 | Meteor über Lyramion, „LYRAMION“, „70 Jahre danach …“ |
| $C90–$1150 | **Startmenü**: Musik Stück 1, Schirm 320 × 256 × 5 (6:$C8C0), Menühintergrund aus 2:$1954 entpacken, Menügrafik ($4E2A), Einträge mit großem Zeichensatz bei y = 66 + 30·n, Hervorheben mit Farbe 30/31 ($121C), Mauszeiger, Wahl mit linker Maustaste |

`$1250` wartet `d7` VBLs und **bricht bei linker Maustaste ab** (dann `bne
$C90`, ins Menü); die rechte Maustaste lässt die Raumszene viermal so schnell
laufen ($2800).

### 4.4 Hardware

Anders als `FAIRY.S` spricht das Intro die Hardware meist über **`lea
$DFF000,a6`** und Versätze an (15 Stellen, 224 Zugriffe über `a6`, darunter
auch die 8 Betriebssystemaufrufe), dazu 24 absolute `$DFFxxx`-Operanden und
7 × `$BFE001` (CIA-A, linke Maustaste). **K1 greift trotzdem:** Wird die
Basis im `lea` auf den Schattenblock gebogen, landen alle `a6`-Zugriffe
dort.

| Was | Wo | Bei uns |
|---|---|---|
| VBL (Level 3, $2522) | zählt 5:$4, setzt die 32 Farben aus 5:$121C6, liest die Maus (JOY0DAT) und stellt die Zeigersprites, ruft die Musik | wie `Fee_vbl`: unser VBL ruft Thalions Routine |
| Copperliste ($2452) | zwei Listen im Wechsel: Ebenenzeiger, wahlweise ein Warten auf Zeile $F4 mit einer Farbe (COLOR01), COP1LC | Bildbasis und Farbbank aus der Liste lesen, wie beim Fantasy-Intro |
| Bildfenster ($289A, $8B8–$ACA) | DIWSTRT/STOP, DDF, BPLCON0 (Ebenen), Modulo; in Twinlake wandert DIW | Höhe und Ebenenzahl je Szene; wanderndes Fenster = Ausschnitt |
| Blitter | Kopieren `$09F0`, Löschen, maskiert `$0FCA`, Zeichensatz `$0BFA`/`$0B0A`, **Zoom spaltenweise mit `$0FCA`/`$0BE2`, auch absteigend (BLTCON1 = 2)** | `Amiga_blit` aus dem Fantasy-Intro, **um den Absteigemodus erweitern**; Linienmodus nicht gesehen |
| Sprites | nur der Mauszeiger im Menü (zwei Sprites) | wie die Fee, als Maske und Bild |
| Maus | JOY0DAT (5:$1216C ff.), linke Taste CIA-A, rechte POTGOR | Mausvektor wie beim Fantasy-Intro |

**Schirme:** Alle Formate sind wie bei `FAIRY.S` zeilenverschachtelt:
320 × 200 × 5 (200 Byte je Zeile), 320 × 236 × 4 (160) und 320 × 256 × 5.
Umsetzen wie beim Fantasy-Intro, mit Ebenenzahl und Höhe je Szene.

### 4.5 Was das für die Umsetzung heißt

- Es gibt keinen Quelltext. Nach Leitziel 1 ist der **Binärcode selbst
  Thalions Code**: Hunks 0–4 beim Bau übernehmen (wie Thalions Rasterer aus
  AM2_CPU), die 648 Relokationen beim Bau auflösen und die
  Hardwareoperanden auf den Schattenblock biegen (K1).
- Auch der **Rahmen** ($0–$12C, $1152–$1250: Betriebssystem, VBR,
  `trap #0`) bleibt Thalions Code. Er bekommt eine kleine Nachbildung von
  exec und graphics, genau die fünf Aufrufe, die er macht; K1 biegt die
  vier Lesestellen von ExecBase (`movea.l $4,An`) auf `Exec_zeiger`.
- Die Musikschnittstelle ist eine Sprungtabelle. Bis die Musik kommt,
  zeigt 5:$0 auf eine Tabelle stummer Routinen.
- Die Menüwahl geht über den Lader zum Spiel, als Befehlszeile
  (Abschnitt 1, abgesprochen mit der 2D-Session). `INTRO.TOS` liest den
  Merker aus seiner Befehlszeile (`1`) ins Merkerbyte und gibt die Wahl
  mit `Pterm` zurück.

### 4.6 Stufen

| Stufe | Inhalt | Stand |
|---|---|---|
| I1 | Auszug beim Bau (`tools/intro_programm.py`, seit E1 `amiga_programm.py`; K1 an 50 Stellen), Nachbildung von exec/graphics, VBL-Brücke, Anzeige aus Copperliste und Registern, Farben mit Farbwechsel, Maus auf CIA/POTGOR/JOY0DAT | Test bestanden (Nutzer, 2026-09-30): läuft durch, an vielen Stellen sehr langsam |
| I2 | Thalions Blits über K2 (unten); `Amiga_blit` gemeinsam in `amiga/`, mit Absteigemodus, Zeigern danach und weiteren Mintermen | Test bestanden (Nutzer, 2026-09-30), Tempo wie I1 |
| I3 | Menü: Zeigersprites. Thalions VBL ($2522) schreibt Lage und SPR0PT/SPR1PT, DMACON $8020 schaltet ein ($10C4). `Zeiger_zeichnen` liest Kopfwörter und DMACON wie die Hardware und zeichnet Sprite 0 und 1 (verbunden: Farben 16–31) mit der CPU in den gezeigten Schirm, Ebenen 0–4, die Bankebene bleibt; `Zeiger_weg` schreibt den Hintergrund vor dem Umsetzen zurück. Ein Bild Verzug | Test bestanden (Nutzer, 2026-10-01) |
| I4 | Lader: `SAVES` → Merker, `FANTASY` → `INTRO` → `ENGINE`, Merker und Wahl als Befehlszeile (Abschnitt 1) | Test bestanden (Nutzer, 2026-09-30): ohne Spielstand das Intro, mit Spielstand gleich das Menü; NEUE QUEST ruft den Charaktereditor, WEITERSPIELEN lädt den letzten Stand. Die Spielseite ist von der 2D-Session (main 3423cfd) |
| später | Tempo, wie F4 | offen |

**Finding (user, 2026-09-30): white full picture before the zoom.** Just
before the smallest stage appears, the picture stood large and white for
one or two frames. Cause found and fixed on 2026-10-15 (7.8, T23): the
precomputed full-size stage ($14E6) stays in plane 4 of the hidden screen;
Thalion's VBL clears it before the Amiga shows that screen, we converted it
earlier.

**I1 im Einzelnen** (`intro/INTRO_SUP.S`, seit E1 zum größten Teil `amiga/AMIGA_RAHMEN.S`):

- `start` ruft Thalions Programm wie der Amiga-Lader: `a0` = Satz aus
  Zeiger auf `Musik_stumm` (an jeder Stelle ein `rts`) und Merkerbyte 0;
  die Wahl aus `d0` wird Rückgabewert des Programms (`Pterm`).
- Thalion findet AttnFlags 0 und nimmt VBR 0: Sein VBL landet in `$6C`,
  sein Hauptprogramm in `$80` (`trap #0`). Unser VBL (`$70`) springt nach
  `$6C`; bis Thalion ihn einträgt, steht dort ein bloßes `rte`.
- **Anzeige:** Der VBL liest COP1LC (Ebenenzeiger, Warten auf eine
  Bildzeile, Farben danach), BPLCON0, BPL1MOD, DIWSTRT/DIWSTOP. Ändert sich
  etwas, setzt er das ganze Bild auf den verdeckten Falcon-Schirm um und
  schaltet um; sonst führt er je VBL 32 Zeilen auf dem gezeigten nach, für
  Zeichnen auf dem gezeigten Schirm (Menü). Ebene 5 ist die Farbbank ab dem
  Farbwechsel der Copperliste. Oben bündig: auf 200 Zeilen (ohne
  256-Zeilen-Kniff) fehlt der untere Rand der Raumszene.
- Das waagerechte Fenster (DIW in Twinlake) wird noch nicht beachtet.

**K2 (Nutzer, 2026-09-30).** Thalion startet Blits durch Schreiben von
BLTSIZE (18 Stellen) und wartet durch Abfragen von DMACONR (30 Stellen).
Beim Fantasy-Intro war das Makro `waitblit` im Quelltext der Haken; hier gibt
es keinen Aufruf, an dem wir hängen könnten. Beschluss: Beim Bau wird an den
18 Stellen das erste Wort des Befehls durch `trap #8` ersetzt
(`tools/amiga_programm.py`); `K2_trap` holt den Wert wie der Originalbefehl
(`#imm`, `Dn` über `$58(a6)` oder `(a5)`), schreibt BLTSIZE, führt den Blit
mit `Amiga_blit` aus und springt hinter den Befehl. Keiner der 18 Befehle
setzt Bedingungen, die der nächste liest. Geprüft ist am gebauten Programm:
Hunk 0 weicht vom Original nur an Relokationen, K1 und K2 ab. „Ggf. später
3“ (Nutzer): Für das Tempo können bei Intro und Extro Thalions Blitroutinen
nachgeschrieben werden, abweichend von Leitziel 1; das wird entschieden,
wenn alles funktional läuft.

**`Amiga_blit` gemeinsam** (`amiga/AMIGA_BLIT.S`, `amiga_blit_bss.i`). Das
Verschieben aus `FEE_SUP.S` war neutral: `FANTASY.TOS` und beide
Messfassungen blieben bytegleich. Danach erweitert: absteigender Modus
(Zeiger rückwärts, Modulos abgezogen, Verschiebung nach links), die Zeiger
der benutzten Kanäle stehen nach dem Blit hinter ihm (das Intro setzt
BLTDPT einmal und blittet spaltenweise weiter), direkt ausgeführt werden die
Minterme `$CA`, `$E2`, `$F0`, `$FA`, `$0A`, `$00`.

## 5. Extro (`Ambermoon_extro`)

Kartiert 2026-09-30 (E0), gelesen im entpackten Programm (nur Scratchpad).
Hunk-Nummern wie beim Imploder-Werkzeug: das Programm beginnt mit Hunk 1.
**Derselbe Rahmen wie das Intro**, dieselbe Bibliothek, dieselben Kniffe.

### 5.1 Hunks (bewiesen)

| Hunk | Art | Größe | Relokationen nach | Inhalt |
|---|---|---|---|---|
| 1 | Code | 12336 | 1 (10), 2 (8), 4 (1), 5 (101), 6 (12) | Programm, Zeichensatz, Schreibroutinen |
| 2 | Daten | 9528 | 2 (14), 3 (14) | Paletten ($0), die drei Ablauflisten ($40, $6C, $98), Schlusstext ($BC), Texte |
| 3 | Daten | 140020 | — | Bilder |
| 4 | Chip | 4 | — | leere Copperliste (während des Aufbaus) |
| 5 | BSS | 192 | — | Variablen: $3A Musikspieler, $2C Ende, $38 Musik im VBL, $4 VBL-Zähler, $10/$14/$18 Schirme |
| 6 | Chip-BSS | 216720 | — | Copperlisten $0 und $190, Textmaske $320, Schirme $2E90 und +51200 (320 × 256 × 5), Textebene $1BE90, Hintergrund $28690 |

160 Relokationen.

### 5.2 Rahmen und Übergabe (bewiesen)

- **Start ($0):** Wie das Intro: den Satz aus `a0` übernehmen, **Langwort →
  Musikspieler** (5:$3A), **Byte `4(a0)` → Ende** (5:$2C, 0–2). AttnFlags,
  `graphics.library`, `LoadView(0)`, dreimal `WaitTOF`, DMACON/INTENA
  merken, `Supervisor` holt den VBR, **`trap #0` auf $120**, dort läuft
  alles im Supervisor. Kein `dos.library`, keine Dateien.
- **Bibliothek:** genau die fünf Aufrufe des Intros (OpenLibrary,
  CloseLibrary, Supervisor, LoadView ×2, WaitTOF ×3).
- **Ende ($322–$3C6):** Schlusstext, Klick, ausblenden, `jsr 16(a0)`
  (Musik aus), Interrupts, DMA, View zurück, `rte`; danach
  `CloseLibrary` und **`d0` = 0**.
- **Musik:** `+0` Anfang, `+12` Stück 0, `+16` Ende, `+24` je VBL
  (solange 5:$38 gesetzt ist) — dieselbe Sprungtabelle wie beim Intro.

### 5.3 Ablauf (bewiesen)

Das Ende n wählt eine Liste in Hunk 2 ($244: $40, $6C, $98). Jeder Eintrag
ist ein Langwort-Paar {Textskript, Bild}; 0 beendet die Liste. Je Eintrag:

1. Ausblenden; das Bild (Breite, Höhe, Palette, Daten) mittig in den
   Hintergrund 6:$28690 kopieren, von dort in beide Schirme; einblenden.
2. **Rolltext** ($420–$5B0): je Bild zwei Blits und eine Textzeile.
   - Blit 1 ($4AA, fünfmal, je Ebene 256 × 20 Worte): D = C ? B : A
     (Minterm $D8) — die Textmaske C wählt zwischen Textebene B und
     Hintergrund A.
   - Blit 2 ($4FC, 277 × 20 Worte): die Textmaske eine Zeile hoch.
   - Neue Zeilen schreibt die CPU ($FEE, $6E2) nach 6:$2B20.
   - Schirme tauschen, Copperliste neu ($EBC).
3. Ende des Textes: warten auf die linke Taste, nächster Eintrag.

Die **rechte Taste** hält an und lässt wieder laufen (in der
VBL-Warteroutine $F54, POTGOR Bit 10). Die linke kürzt ab, wenn der Text
steht.

### 5.4 Hardware (bewiesen)

- **K1:** 24 Operanden `$DFFxxx` (davon 4× `lea $DFF000,a6` als Basis),
  4× `$BFE001`, 4 Lesestellen von ExecBase (`movea.l $4,An`).
- **K2:** nur **2** BLTSIZE-Schreibstellen ($4AA, $4FC), beide
  `move.w #imm,$58(a6)`, dieselbe Form wie im Intro.
- **Anzeige:** Copperliste ($EBC) wie im Intro: Warten auf Zeile $20,
  fünf Ebenenzeiger, BPLCON1, Ende; **keine Farbwechsel**. Die Farben
  schreibt die CPU nach $DFF180 ($3C8). DIW mit **256 Zeilen** ($F8E).
- Sprites benutzt das Extro nicht.
- **Tempo:** je Bild rund 31000 Worte Blit über vier Kanäle, mit
  `Amiga_blit` in der CPU wird der Rolltext langsam laufen.

### 5.5 Übergabe vom Spiel (bewiesen)

Thalions `End_seq` (EVENTS.S) steht in AM2_CPU 1.20 bei 0:$12D0E und
setzt `Return_value` auf **-5002** (Valdyn nicht in der Gruppe,
`GAME_COMPLETED3`), **-5001** (Valdyn mit „dem Ding“, `GAME_COMPLETED2`)
oder **-5000** (`GAME_COMPLETED`), dann `jmp Exit_program`. Thalions Lader
rechnet n = -d0-5000: GAME_COMPLETED → Liste 0, 2 → 1, 3 → 2. Die Werte in
`tools/originalcode/vorspann.i` (-204…-206, „angenommen“) sind damit
überholt; das gehört der 2D-Session.

### 5.6 Umsetzung

**E1, Test bestanden (Nutzer, 2026-10-01)** (Nutzer: „ja“, 2026-09-30):

- **Ein Werkzeug für beide:** `tools/amiga_programm.py intro|extro` (vorher
  `intro_programm.py`) hat je Programm eine Tabelle: Hunks und ihre Art,
  Relokationen, K1-Zahlen, ExecBase-Stellen, K2-Stellen. Das Extro kommt
  gepackt und geht durch `imploder_exe.py`. `tools/amiga_bauen.sh
  intro|extro` übersetzt und bindet (vorher `intro_bauen.sh`).
- **Eine Schicht für beide:** `amiga/AMIGA_RAHMEN.S` (exec/graphics, VBL,
  Anzeige, Farben, Maus, Zeiger, K2), `amiga_rahmen_daten.i`,
  `amiga_rahmen_bss.i`, `amiga_vorspann.i`. Je Programm bleiben `start`
  und der Satz `Uebergabe` (`intro/INTRO_SUP.S`, `extro/EXTRO_SUP.S`).
  Neu: `ANZEIGE_MITTIG` (Extro) schneidet 256 Zeilen auf 200 oder 240
  oben und unten gleich ab.
- **Minterm $D8** (C ? B : A, der Rolltext) steht in der schnellen Tabelle
  von `Amiga_blit`.
- `EXTRO.TOS` liest das Ende aus der Befehlszeile (eine Ziffer 0–2), sonst
  Ende 0. Ausgeliefert nach `ATARI/AMBFILES/`.

**Bewiesen:**
- Das Verschieben der Schicht und des Werkzeugs ist neutral: `INTRO.TOS`
  ist bytegleich mit dem Stand davor, wenn man nur Minterm $D8 weglässt
  (die Texte „Das Intro braucht …“ wurden vorher allgemein gefasst).
- In `INTRO.TOS` und `EXTRO.TOS` weicht Thalions Programm vom Original nur
  an Relokationen, K1 und K2 ab; alle traps sitzen (Extro: Hunk 1 473 Byte,
  Hunk 2 59 Byte, Hunks 3 und 4 gleich).

**E2, Test bestanden 2026-10-01** (Nutzer: „ja zu e2“; Test: „Ende1
funktioniert mit amber.tos“, mit der Prüffassung `ENDETEST=1` der 2D-Session,
die beim Beenden -5001 zurückgibt): Liegt das
untere Wort der Rückgabe von `ENGINE.TOS` zwischen -5002 und -5000, startet
der Lader `EXTRO.TOS` mit n = -Wert-5000 als Befehlszeile und fragt danach
wie Thalions Lader, ob das Ende noch einmal laufen soll (J wiederholt).
Verglichen wird nur das Wort, weil `Pterm` ein Wort zurückgibt. Als
Ladefehler meldet der Lader nur noch -1 bis -127; tiefer ist es der Wert
des Programms. Die Spielseite ist von der 2D-Session: `Exit_program` endet
mit `Pterm(Return_value)` (Erkenntnis 263; GAME_COMPLETED -5000/-5001/-5002).
Ein echtes Spielende ist noch nicht durchgespielt. Thalions Lader
zeigt für andere negative Werte einen Fehlertext; das ist hier noch nicht
nachgebaut.

## 6. Musik

`Intro_music` und `Extro_music` sind Abspieler und Stück für den
Amiga-Tonbaustein (Paula). Für den ST gibt es die Stücke als YM2149-Fassung.
Gunnar Gaubatz (Big Alec) hat sie für die abgebrochene ST-Fassung
umgesetzt, PHF/Nokturnal hat sie 2019 auf der Sommarhack als „Ambermoon
Music Demo“ veröffentlicht ([demozoo 205750](https://demozoo.org/productions/205750),
[pouet 81770](https://www.pouet.net/prod.php?which=81770)).
Laut den Angaben dazu sind es etwa ein Dutzend Stücke. Welche das sind,
welches Format sie haben und unter welchen Bedingungen man sie verwenden
darf, ist offen. Die Musik ist ein eigenes Paket; eingebunden wird sie
zum Schluss (Nutzer).

**Die beiden Dateien (gelesen 2026-10-08, nur Scratchpad):** Rohcode ohne
Hunks, vorn sieben `bra` (`4EFA`), Ziele in beiden gleich ($2C, $702,
$786, $822, $858, $18F0, $908). Die ersten $1983 Byte, also der Spieler,
sind in beiden Dateien gleich; dahinter folgt das Stück (`Intro_music`
87 570 Byte, `Extro_music` 128 356). Der Spieler ist bis auf **27
Hardwareoperanden** PC-relativ; die liegen in beiden an denselben Stellen
(`$DFF000`, `$DFF096` ×4, Kanalbasen `$DFF0A0`…`$DFF0D0` ×13, `$DFF007` ×2 als
Zufall, `$BFD000` ×3, `$BFE001` ×4 Filter). Das Fantasy-Intro hat keine
Musik (`FAIRY.S` spricht die Paula nicht an).

**Stand der Musik-Sitzung (Nachricht 2026-10-08):** `musik` ist in
`main` eingemischt (e0c51e2); der Bau braucht dann `a56`, `MUSIK.INF`
wählt AUS/DSP/CPU für `ENGINE.TOS`. Reihenfolge laut Nutzer: erst die
Samples im DSP, dann der YM-Spieler für ST und Falcon. Erst danach wird die
Paula-Nachbildung als Include für `amiga/` herausgelöst; eine Zusage dazu
gibt es noch nicht. Bis dahin bleiben Intro und Extro stumm.

**Nachtrag 2026-10-09 (Musik-Sitzung, zu E14 in docs/05):** Der Mischer als
gemeinsames Modul ist technisch zugesagt; ob und wann, entscheidet der
Nutzer mit E14, bei der Musik-Sitzung nach T8/T9 und dem YM-Spieler.
- Der Kern ist schon allgemein: Er liest die Paula-Register aus einem
  Schattenblock (bei uns die `AR_`-Felder in `Amiga_register`) und mischt
  auf dem DSP oder mit dem Prozessor.
- Geplanter Schnitt: Einsprünge Install, Remove und Takt mit einem Zeiger
  auf den Schattenblock. Takt und Aufruf des Spielers bleiben beim
  Aufrufer, hier also in `Amiga_vbl`.
- An das Spiel gebunden sind nur der Takt, `MUSIK.INF` und die Erkennung
  des Stückwechsels. Die Erkennung braucht erst „Samples im DSP“ (T8); den
  Stückkopf von `Intro_music`/`Extro_music` klären wir dafür später.
- Kosten wie im Spiel, Falcon heute 12–24 % Prozessor.
- **Keine eigene Kopie von `MUSIK_SUP.S`**, sonst laufen zwei Mischer
  auseinander.

**Beschluss 2026-10-10 (Nutzer):** Die Musik in Intro und Extro wartet,
bis T10 (YM-Spieler) durch ist und die Musik-Sitzung den Mischer
herausgelöst hat. Vereinbart ist schon: Thalions Spieler bekommt über K1
einen eigenen Schattenblock von $200 Byte, das Intro bleibt bei
`Amiga_register`.

**Built 2026-10-15 (E14, test T23).** The music session's mixer
(`musik/MISCHER.S`, docs/13 4f) plays Thalion's player in intro and extro.
- *Loading at run time* (`amiga/AMIGA_MUSIK.S`, `Musik_laden`, before
  `Super`): `INTROMUS.DAT`/`EXTROMUS.DAT` from `AMBFILES\`, else next to the
  program. Length and all 27 operands must match `build/<name>_musik.i`
  (written by `tools/musik_k1.py` from the game data at build time); only
  then are they bent (Paula to `Musik_schatten`, CIA to a dummy) and
  `Uebergabe+0` points to `Musik_tabelle`. Otherwise it stays
  `Musik_stumm`.
- *Jump table*: +0 init, +12 start, +16 stop go to Thalion's player; +24,
  the beat, is empty, because the mixer calls the beat once per 1/50 s of
  sound (`MS_TAKT` = player +24).
- *Mixer*: `Musik_mischen` after `Amiga_einrichten` builds the parameter
  block (shadow, beat, Thalion's word "music on": intro `Intro_h5+$12148`,
  extro `Extro_h5+$38`, Thalion writes -1/0; the 4e fields are 0, the
  player is another build than in AM2_CPU). `MUSIC=` in `AMBER.INF` (E17,
  since 2026-10-23; before `MUSIK.INF`): `OFF` silent, `CPU` processor,
  anything else (`DSP`, `YM`, no file) the DSP (user, 2026-10-12). `Mischer_vbl` first in `Amiga_vbl`, `Mischer_remove` in
  `Amiga_abraeumen` (also the emergency exit). The DMA ring lies in the
  program's BSS: the header has no flags, so it loads into ST-RAM.
- *Hatari, intro (2026-10-15)*: one beat per VBL in all phases, DSP alive
  at VBL 3000, the mixer costs about 5 % of a VBL.

## 7. Beschlüsse und Umsetzung

### 7.1 Daten beim Bau, nicht zur Laufzeit (Nutzer, 2026-09-29)

Intro, Extro und Fantasy-Intro sind Programme wie `AM2_CPU`, keine
Spieldateien. Sie werden behandelt wie `AM2_CPU`: Daten **und** reiner
Speichercode kommen beim Bau heraus, im Repository liegt nur das Werkzeug.
Zur Laufzeit wird keins der drei Programme gelesen.

**Musik (Nutzer):** Die YM-Stücke dürfen mit. Sie werden nicht
mitgeliefert: Liegen sie neben dem Programm, werden sie gespielt, sonst
bleibt es still.

### 7.2 K1: die Hardwareadressen von `FAIRY.S` (Nutzer, 2026-09-29)

`FAIRY.S` bleibt unverändert. `tools/fairy_umbiegen.py` sucht nach dem
Binden im Bereich `Fairy_anfang`…`Fairy_ende` genau die zehn Operanden
`$DFFxxx`. Es setzt jeden auf `Amiga_register` + Registerversatz und
ergänzt die TOS-Verschiebetabelle. Fehlt eine Stelle, kommt eine hinzu oder
steht davor ein anderer Befehl, bricht es ab. Die Quelle bleibt also, wie
sie ist; geändert wird nur die Übersetzung, wie mit `opt t-` bei
`ACTIONS.S`. Verworfen wurden K2 (die MMU, nur auf dem Falcon möglich) und
K3 (den Busfehler abfangen).

### 7.3 Aufbau

| Datei | Sorte | Inhalt |
|---|---|---|
| `fantasy/fantasy.s` | unsere | bindet nur ein |
| `FAIRY.S` | Thalions | unverändert, aus `$AMBER_URCODE` |
| `fantasy/fee_vorspann.i` | unsere | `waitblit` → `jsr Blitter_warten`, Registerversätze, Maße |
| `fantasy/FEE_SUP.S` | unsere | Amiga-Schicht: Start und Ende, Hauptablauf nach Hunk 1 $110–$2B0, VBL, Anzeige, Maus, Blitter, Sprites |
| `build/fantasy_werte.i` | Bau | Konstanten für `FAIRY.S`, gegen den Binärcode geprüft |
| `build/fantasy_daten.i` | Bau | Hunk 2 (`incbin`) mit Namen, Hunk 3 als BSS in Originalanordnung, Thalions Blenden, Schirmtausch und Tabellen aus Hunk 1 |

Bauen: `tools/fantasy_bauen.sh`, von `build_falcon.sh` gerufen, erzeugt
`ATARI/AMBFILES/FANTASY.TOS` und zwei Messfassungen: `FEEMESSB.TOS` (Blitter) und
`FEEMESSC.TOS` (Zeilen mit der CPU, Schalter `FEE_CPU`). Beide zählen
(`FEE_MESSEN`) die Bilder, die knapp (erst nach dem 2. VBL) oder zu spät
(erst nach dem 3. VBL) fertig wurden, dazu die Amiga-Blits, und schreiben
das Ergebnis nach dem Ende auf den Desktop. Thalions Schleife braucht drei
VBL je Bild; knapp kostet also noch nichts.

**Die Schicht:**

- **Anzeige:** Jeder Amiga-Puffer hat einen Falcon-Zwilling. Umgesetzt
  werden die Ebenen 0–4 aus den fünf Amiga-Zeilen. Ebene 5 ist die Bank:
  0 bis Zeile 133, 1 ab Zeile 134. Die Ebenen 5–7 stehen fest. Je Bild
  werden die Zeilen 134–255 umgesetzt, denn nur die stellt Thalions Rahmen
  jedes Mal aus dem Hintergrund her.
- **Zeilen (Nutzer):** RGB. Der Videl wird von 200 auf 256 Zeilen gezogen
  (VDB/VDE ±28 Zeilen, VBE/VBB mit), wenn die Grenzen es erlauben. Sonst
  gibt es 200 Zeilen ab Amiga-Zeile 28, an VGA 240 ab Zeile 8. Ob der Videl
  mitgeht, ist **ungeprüft**; das zeigt der Test auf RGB.
- **VBL:** Bildbasis und Farben setzen, dann in Thalions `level3` springen.
  Der Ausnahmerahmen des Falcon-VBL liegt dabei schon richtig auf dem
  Stapel, Thalions `rte` kehrt also richtig zurück. Bank 0 bekommt die
  32 Farben, die `level3` schrieb. Bank 1 bekommt dieselben, sechs davon aus
  `Palette_unten`, wie es die Copperliste tut.
- **Maus:** Mausvektor (`Kbdvbase`), linke Taste, wie Thalions
  `btst #6,$bfe001`.
- **Blitter** (F2, der ST(E)-Blitter des Falcon): `Ebenen_umsetzen` setzt
  ein Rechteck mit fünf Blits um, einen je Ebene (Quelle Schritt 2, Ziel
  Schritt 16). Der Bus bleibt geteilt, damit die Tastatur keine Bytes
  verliert. Der VBL blittet auch: Er wartet, bis der Blitter frei ist, und
  stellt dessen Register danach wieder her.
- **Sprites** (F2): Im VBL werden die acht Spritezeiger gelesen, die
  `level3` nach `$DFF120` schrieb, dazu die Steuerwörter am Anfang jedes
  Sprites, so wie die Sprite-DMA es tut. Angehängte Paare ergeben die
  Farben 16–31. Nebeneinanderliegende Paare fasst die Schicht zu einem Lauf
  zusammen; die Fee ist einer. Je Lauf legt die CPU die Maske und vier
  Ebenen mit einem Nullwort je Zeile ab. Dann stanzt der Blitter die
  Ebenen 0–3 aus und odert sie ein, Ebene 4 bekommt die Maske (neun Blits).
  Ebene 5 trägt schon die Bank der Zeile, denn die Copperliste wechselt
  auch Spritefarben. Links und rechts schneiden FXSR und die Endmasken zu,
  oben und unten der Zeilenausschnitt.
  - Unter der Fee wird nichts gesichert: Beim nächsten Mal setzt die
    Schicht das Rechteck aus dem Amiga-Zwilling neu um.
  - **Ein Bild Versatz:** Gezeichnet wird, was `level3` im *vorigen* VBL
    eintrug. So bleibt Thalions `rte` unberührt.
  - Nullpunkt wie bei Thalion: `$80` waagerecht, `$28` senkrecht
    („screen_start“). Ob die Hardware waagerecht um einen Punkt versetzt,
    ist nicht geprüft.
  - Die Flugbahn reicht waagerecht von −64 bis 324 und senkrecht bis 265
    (Unterkante): Die Fee fliegt links herein und rechts hinaus.

### 7.4 Stufen

| Stufe | Inhalt | Stand |
|---|---|---|
| F1 | Auszug, K1, Rahmen, Anzeige, Blenden, Maus | läuft (Nutzer, 2026-09-29), funktional in Ordnung; Tempo, Bildhöhe und Palettenwechsel auf Hardware offen |
| F2 | Blitter-Schicht; Zeilen mit dem Blitter umsetzen; Sprites: die Fee | Fee in Hatari sauber (Nutzer, 2026-09-29); Hardware offen. Hatari: beide Fassungen halten den Takt, die Blitterfassung mit weniger Reserve (199 von 443 Bildern über zwei VBL, CPU 2) |
| F3 | Thalions Blits: Schriftzug im Sternenschweif, Sterne im Flugstaub (`Amiga_blit`, CPU) | in Hatari „sehr schön“, Schriftzug und Sternenstaub klar (Nutzer, 2026-09-29); Hardware offen. Hatari: rund 10 650 Amiga-Blits, 0 nicht unterstützt; 63–65 Bilder zu spät (F2: 2), höchstes vindex 11, in beiden Fassungen gleich, also Kosten der Blits in der CPU (F4) |
| F4 | Tempo: zuerst ein schneller Weg in `Amiga_blit` für die Sterne (`$CA`), geprüft gegen den genauen (7.6); der Atari-Blitter erst, wenn das nicht reicht | T2 gebaut 2026-10-01, ungetestet |

In F1 läuft Thalions ganzer Ablauf: Einblenden, Flugbahn, Flugstaub,
Ausblenden bei Maustaste oder am Ende der Bahn. F2 bringt die Fee, F3
Thalions Blits.

**Thalions Blits** (F3). `FAIRY.S` blittet dreimal:

| Stelle | Was | Minterm | Ziel |
|---|---|---|---|
| `make_magic` | je Bild eine 4-Punkte-Spalte des Schriftzugs (`flogo`) | `$E2`: B ? A : C, B fest (BLTBDAT) | `background`, Zeilen 146–228 |
| `blit_star` | das Funkeln im Sternenschweif (`overfunkel`), verschoben | `$CA`: A ? B : C | `workbase` |
| `blit_star2` | Sterne im Flugstaub (`stars`), A = B, also ein Odern | `$CA` | `workbase` |

`Blitter_warten` (Thalions `waitblit`) führt den Blit aus, den `FAIRY.S`
zuletzt eingetragen hat. BLTSIZE ist bei uns nur eine Speicherstelle; der
Blit läuft beim nächsten `waitblit`, den letzten eines Bildes stößt
`Fee_ablauf` an. `Amiga_blit` bildet den Amiga-Blitter in der CPU nach:
aufsteigender Modus, Erst- und Letztwortmaske, Verschiebung mit dem
vorigen Wort (auch über das Zeilenende), feste Werte ohne USEx, jeder
Minterm, `$CA` und `$E2` direkt. Linien-, Absteige- und Füllmodus zählt es
als nicht unterstützt (`FEE_MESSEN` zeigt die Zahl). Es ist genau, aber
langsam; es bleibt die Referenz für den schnellen Weg über den
Atari-Blitter (F4).

**Blitter-Annahmen** (aus der Hatari-Quelle, nicht auf Hardware geprüft):
Bei einer Zeile aus einem Wort gilt Endmaske 1. Die Quelladresse wächst je
Lesezugriff, auch beim FXSR-Lesen. Nicht-HOG teilt den Bus von selbst.

### 7.5 Offen

- **ST:** Er hat 16 Farben, das Fantasy-Intro braucht zweimal 32. Das kommt
  später. Den unteren Rand öffnet dort der bekannte Trick mit einem
  Interrupt je Bild.
- **VGA mit 60 Hz:** Thalion zählt VBLs, an VGA liefe alles um ein Fünftel
  schneller. Dort gibt es kein 50 Hz; denkbar ist, Thalion nur 5 von 6 VBLs
  zu geben (ruckelt leicht). Am RGB-Monitor stellen wir seit 2026-10-03 PAL
  fest ein (7.6).

### 7.6 Tempo (Fantasy-Intro, Intro, Extro)

Befund (Nutzer, 2026-10-01): Fantasy-Intro und Intro sind langsam. Beim
Fantasy-Intro nur, solange der Schriftzug mit Feenstaub entsteht; die Fee
allein mit Flugstaub läuft schnell. Vorgehen (Nutzer: „Los“): erst unsere
Schicht schneller machen, Leitziel 1 bleibt; Thalions Blitroutinen
nachzuschreiben entscheidet der Nutzer erst, wenn das nicht reicht.

**Ursache beim Fantasy-Intro, erste Annahme** (aus `FAIRY.S` gelesen,
Mengen geschätzt; **die Messung unten zeigt: nur zum Teil richtig**, der
größere Posten ist das Umsetzen der Zeilen):
`make_magic` legt je Bild bis zu 24 Funkelsterne an (`magic_buffer`, 400
Plätze), jeder lebt 4–16 Bilder, und jeder lebende ist je Bild ein Blit
`blit_star`: Minterm `$CA`, 9 Zeilen × 5 Ebenen × 2 Worte, verschoben. Bei
150–200 Sternen sind das über 15 000 Worte je Bild durch `Amiga_blit`, das
je Wort rund 20 Befehle und einen Unterprogrammaufruf braucht. Thalions
Takt sind drei VBL je Bild (rund 960 000 Takte am 030). Die Fee allein
blittet kaum (`blit_star2` nur für jeden achten Flugstaubpunkt). Passt zu
F3 in Hatari: 63–65 Bilder zu spät mit Thalions Blits, 2 ohne, in beiden
Umsetz-Fassungen gleich.

**T2: schneller Weg in `Amiga_blit`** (gebaut 2026-10-01; im Emulator
genau, Ergebnis unten; Hardware offen):
Minterm `$CA`, aufsteigend, alle vier Kanäle, C und D dieselbe Stelle mit
demselben Modulo → `Bl_schnell_ca`. Enge Schleife in Registern, ohne
Aufruf je Wort; ist das verschobene A-Wort 0, bleibt D = C stehen und wird
weder gelesen noch geschrieben. Alles andere läuft wie bisher über
`Amiga_blit_genau` (die Referenz, unverändert). Das gilt auch für Intro und
Extro, wo Thalion so blittet.
- `FEEPRUEF.TOS` / `INTROPRF.TOS` (Schalter `BLIT_PRUEF`): Jeder schnelle
  Blit läuft zuerst genau, Ergebnis und Register werden gemerkt, alles
  zurückgesetzt, dann schnell und verglichen; gezählt wird jede Abweichung
  (D-Bereich bis 8 KB, sonst „ungeprüft“). Langsam, nur der Beleg.
- `FEEMESSB.TOS` zeigt jetzt auch die Zahl der schnellen Blits.

**T1: Messfassungen für Intro und Extro** (`INTROMES.TOS`, `EXTROMES.TOS`,
Schalter `AMIGA_MESSEN`): MFP Timer A stößt 1010-mal je Sekunde an, auf
Stufe 6, also auch mitten in unserem VBL (Stufe 4). Das ist nötig, weil
`Anzeige_nachfuehren` beim Schirmtausch das ganze Bild im VBL umsetzt und
eine Messung über den VBL diese Zeit nicht sähe. Gezählt wird der PC: je 64
Byte Programm ein Fach, dazu je Sekunde drei Arten (Blits, Anzeige,
Thalion/sonst). Am Ende stehen Summen und die sechs vollsten Fächer auf dem
Desktop, und die Datei landet im Arbeitsverzeichnis, benannt nach dem
Programm (`INTROMES.MES`, `FEEDIAG.MES`; den Namen schreibt der Bau nach
`build/mess_name.i`), die Bildschirmseiten daneben als `.TXT`. `tools/mess_auswerten.py <Datei> build/INTROMES.map
[--verlauf]` ordnet die Fächer den Routinen zu. Die Messung steht in
`amiga/AMIGA_MESSEN.S` und gilt auch fürs Fantasy-Intro
(`VASM_EXTRA="-DAMIGA_MESSEN" sh tools/fantasy_bauen.sh` → `FEEMESSB`
schreibt `FEEMESSB.MES`; zweiter Bereich dort: Thalions `FAIRY.S`).
Diagnoseschalter: `BLIT_NUR_GENAU` (ohne schnelle Wege, für vorher/nachher),
`MESS_ENDE=n` (die Messfassung beendet sich nach n Sekunden selbst; für den
Emulator, denn Thalions Menü endet nur auf einen Mausklick),
`BLIT_STATISTIK` (zu `AMIGA_MESSEN`: Blits nach Art, siehe unten).

**Messung im Emulator, 2026-10-02** (Nutzer: „kannst du das bitte alles
ausführen und messen?“). Hatari 2.6.1, Falcon 16 MHz, RGB,
`--cpu-exact --data-cache --compatible`. **Das Zeitverhalten ist ein
Emulatorbefund** (LIESMICH der Hatari-Werkzeuge): Verhältnisse und
vorher/nachher taugen, absolute Zahlen gelten erst auf der Hardware.

- **Der schnelle Weg ist genau:** `FEEPRUEF` 10 578 schnelle Blits, 0
  Abweichungen, 0 ungeprüft; `INTROPHT` (Intro mit `BLIT_PRUEF`) rund
  19 000 schnelle Blits, 0 Abweichungen, 5615 zu groß für den Prüfpuffer.
- **Fantasy-Intro:** Die Schriftzugphase dauert ohne schnellen Weg rund 8 s,
  mit rund 6 s; nach Thalions Takt (rund 70 Bilder zu drei VBL) wären es
  rund 4 s. Zu späte Bilder 60 → 54, längstes Bild 6 → 4 VBL. Blits in der
  Phase 37 % → 25 %. **Größter Posten ist aber das Umsetzen:** In jedem Bild
  setzt der Falcon-Blitter die 122 unteren Zeilen um (`Zeilen_umsetzen` →
  `Blit_starten`, rund 40 % aller Proben), dazu kopiert `Unten_herstellen`
  den Hintergrund (rund 9 %). In der Feenphase bleibt danach rund ein
  Viertel Warten (`vsync`); die Sterne passen nicht mehr hinein.
- **Intro:** Bis ins Menü rund 175 s. Davor je nach Szene 40–70 % Blits,
  fast alle auf dem genauen Weg (andere Minterme, absteigend); der
  `$CA`-Weg spart nur rund 6 s (178 → 172 s). „Anzeige“ (Falcon-Blitter
  beim Umsetzen) 15–50 %. Im Menü 19 % für das Nachführen von 32 Zeilen je
  VBL, der Rest Thalions Warteschleife (Hunk 0 $288A).
- **Extro:** Rolltext rund 120 s, dabei 54 % Blits (genauer Weg, Minterm
  `$D8`), 35 % Anzeige, der Rest Thalion; danach wartet es.

**Zweite Runde, 2026-10-02** (Nutzer: „ja, geht los“ zu: nur Geändertes
umsetzen, Blit-Statistik). Wieder Emulatorbefunde.

- **Nur Geändertes umsetzen, durchgerechnet:** Ein Schatten je Zwilling,
  mit dem jedes Bild verglichen wird, liest so viele Worte, wie das
  Umsetzen liest und schreibt; der Bus ist der Engpass, gewonnen wäre
  nichts. Billig würde es erst, wenn bekannt ist, *wo* sich etwas
  geändert hat: `Unten_herstellen` kann beim Kopieren vergleichen (gleich
  teuer wie Kopieren), die Blits kennen ihr D-Rechteck, die Punkte von
  `make_funkel`/`make_funkel2` aber zeichnet Thalions Code mit der CPU,
  ihre Lage stünde nur in `plot_buffer`/`plot_buffer2`. Das hieße, Thalions
  Puffer auszulegen; zurückgestellt, Entscheidung des Nutzers.
- **Blitter neu anstoßen statt warten** (`bset #7` auf BUSY in der
  Warteschleife, aus Ataris Blitter-Doku): `FEERST` blieb in Hatari hängen
  (kein Ende in 9000 VBL). Hatari setzt bei jedem Anstoßen die Anlaufzeit
  des Blitters neu; die enge Schleife lässt ihn so nie arbeiten. Ob die
  Hardware das auch tut, ist offen. Zurückgenommen.
- **CPU gegen Blitter beim Umsetzen** (`FEEMESSC` gegen `FEEMESSB`, beide
  mit schnellem `$CA`-Weg): zu späte Bilder 18 statt 54, knappe 36 statt
  48, längstes Bild 3 statt 4 VBL. Profil (`AMIGA_MESSEN` mit `FEE_CPU`):
  `Zeilen_umsetzen` mit der CPU 10 % gegen rund 20 % Blitterwarten für
  dieselben Zeilen; die übrigen 21 % in `Blit_starten` sind die Fee im VBL
  (`Alte_fee_loeschen`, `Lauf_zeichnen`). Warten (`vsync` und `.takt`)
  44 % statt 35 %. **In Hatari ist die CPU beim Umsetzen also doppelt so
  schnell wie der nicht-HOG-Blitter.** Ob das auf dem Falcon auch so ist,
  zeigt nur der Vergleich `FEEMESSB.TOS` gegen `FEEMESSC.TOS` dort.
- **Blit-Statistik** (Schalter `BLIT_STATISTIK` zu `AMIGA_MESSEN`):
  `Bs_zaehlen` zählt jeden Blit nach Art (Minterm, Kanäle, absteigend,
  ASH > 0, C = D), mit Anzahl, Worten, größter Breite, und Mess_timer
  rechnet jede Blit-Probe der Art des laufenden Blits zu. Die Tabelle steht
  in der `.MES`-Datei hinter dem Verlauf, `mess_auswerten.py` zeigt sie.
  Anteile an der Blitzeit:
  - Intro: `$CA` absteigend mit Verschiebung 22 %, `$F0` (A → D, Kopie)
    18 %, `$E2` absteigend 16 %, `$00` (Löschen, 8000 Worte je Blit) 15 %,
    `$CA` aufsteigend mit Verschiebung 9 % (schon schnell), `$E2`
    aufsteigend 7 %, `$FC` und `$FE` je 4 %. `$E2` und das absteigende
    `$CA` sind eine Wortspalte breit (die Zoom-Spalten).
  - Extro: `$D8` (ABCD, ohne Verschiebung, aufsteigend, C ≠ D, 5120 Worte
    je Blit) 87 %, `$F0` 13 %. Nur zwei Arten.
  - Der Zähler `Bl_anzahl` läuft bei 65 536 über; die Tabelle zählt in
    Langworten.

**Beschluss (Nutzer, 2026-10-02): erst die Schicht, dann messen, dann
gegebenenfalls umschreiben.** Gefragt war, ob Fantasy-Intro, Intro und
Extro für das Tempo umgeschrieben werden müssen (Leitziel 1 fiele dann für
diese drei). Abgewogen:
- *Umschreiben* zeichnete direkt im Falcon-Format: kein nachgebildeter
  Blitter, kein Umsetzen, der größte Gewinn. Aber Leitziel 1 fiele; für
  Intro und Extro gibt es keinen Quelltext, und Disassemblierungen oder
  Abschriften dürfen nicht ins Repository. Sauber ginge es nur wie K1/K2:
  ein Bauwerkzeug ersetzt in den ausgezogenen Hunks gezielt einzelne heiße
  Routinen durch unseren Falcon-Code. Jede ersetzte Routine kann vom
  Original abweichen, und die Prüffassung greift dort nicht mehr.
- *Die Schicht schneller machen* bleibt exakt (Prüffassung) und lässt
  Thalions Code unberührt, nimmt aber das Umsetzen ins Falcon-Format nicht
  weg.
- Der ST (68000, 8 MHz, rund ein Viertel des Falcon) wird mit der
  Nachbildung wohl nicht auskommen; dort ist das Umschreiben eine eigene
  Frage.

Vorgehen (Nutzer: „Wir gehen 1 und 2 an“):
1. Auf dem Falcon die exakten Schritte in der Schicht: schnelle Wege für
   `$00`, `$F0`, `$D8` und die Zoom-Spalten (`$CA`/`$E2`, eine Wortspalte,
   auf- und absteigend), und Umsetzen mit der CPU, wenn der Test von
   `FEEMESSB.TOS` gegen `FEEMESSC.TOS` auf dem Falcon das bestätigt.
2. Auf der Hardware messen.
3. Erst wo es dann nicht reicht: gezielt die heiße Routine ersetzen (beim
   Bau, wie K2), nicht das ganze Programm. Das beschließt der Nutzer.
4. ST: eigene Entscheidung, voraussichtlich mit Umschreiben.

**Die schnellen Wege** (`amiga/AMIGA_BLIT.S`, `Amiga_blit` wählt nach den
Registern; Linien- und Füllmodus laufen immer genau):

| Weg | Muster | je Wort |
|---|---|---|
| `Bl_schnell_spalte` | Breite 1, `$CA`/`$E2`, auf- und absteigend, verschoben, B auch fest | Rohr wie genau, Minterm eingesetzt, kein Aufruf |
| `Bl_schnell_ca` | `$CA` aufsteigend, ABCD, C = D | wie bisher (T2) |
| `Bl_schnell_d8` | `$D8` aufsteigend, ABCD, unverschoben | `D = A ^ ((A ^ B) & C)`, 5 Befehle |
| `Bl_schnell_f0` | `$F0` aufsteigend, A und D, A unverschoben | `move.w (a0)+,(a3)+`, Masken am Rand |
| `Bl_schnell_00` | `$00` aufsteigend, nur D | `move.l` je zwei Worte |
| `Bl_schnell_fc`, `Bl_schnell_fe` | `$FC` (ABD), `$FE` (ABCD, C = D), aufsteigend, verschoben | Rohr wie `Bl_schnell_ca`, `or` (2026-10-03) |

Die Prüffassung (`BLIT_PRUEF`) prüft jetzt jeden Weg (`Pr_weg`). Der
geprüfte Bereich ist alles, was D überstreicht, auch absteigend und mit
negativem Modulo (die Zoom-Spalten laufen absteigend mit DMOD −42, also
nach oben). Der Puffer fasst 128 KB, denn das Extro blittet `$D8` über
verschränkte Ebenen. Ein ungeprüfter Blit zeigt BLTCON0/1, BLTSIZE und
DMOD des letzten auf dem Desktop. `EXTROPRF.TOS` wird jetzt mit
ausgeliefert.

**Ergebnis im Emulator** (je 200 s, Hatari wie oben):
- Genau: `FEEPRUEF` 10 832 Blits, `INTROPRF` 28 239, `EXTROPRF` 2202, alle
  geprüft, **0 Abweichungen**. Im Fantasy-Intro läuft jetzt jeder Blit
  schnell (`make_magic` ist eine `$E2`-Spalte).
- Intro bis ins Menü: **171 s → 153 s**. Je Szene noch 20–50 % Blits.
  Danach `Blit_starten` (Umsetzen, 30 % der 200 s), `Bl_schnell_spalte`
  11 %; `$FC`/`$FE` laufen noch genau (15 % der Blitzeit).
- Extro, Rolltext: **123 s → 89 s**. Darin 43 % Blits (`Bl_schnell_d8`),
  43 % Umsetzen, 14 % Thalion.
- Fantasy-Intro: kaum Unterschied, dort waren die Blits schon klein. Die
  Zählung „knapp/zu spät“ schwankt zwischen zwei Läufen stark (CPU-Fassung
  18/36 gegen 49/9, in der Summe gleich), weil viele Bilder genau an der
  Grenze zwischen 2 und 3 VBL liegen; sie taugt nur grob.

Was jetzt noch am meisten kostet, ist überall das Umsetzen mit dem
Falcon-Blitter; das klärt der Hardwaretest `FEEMESSB` gegen `FEEMESSC`.

**Erster Lauf auf echter Hardware (Nutzer, 2026-10-02).** Falcon mit 14 MB,
CT60 abgeschaltet (030-Modus), RGB, gestartet über `AMBER.TOS`. Vorher
liefen Fantasy-Intro, Intro und Extro nur in Hatari.
- Fantasy-Intro: Die Fee flackerte und war grünlich falsch, nur ihre Umrisse
  stimmten. Der Schriftzug kam nicht, der Klick wirkte nicht, die Fee
  bewegte sich weiter.
- `FEEDIAG` (Profil, endet nach 60 s von selbst): ab Sekunde 2 unter 1 %
  für `FAIRY.S`, 85 % in der Warteschleife auf den Falcon-Blitter
  (`Blit_starten`/`Blitter_sichern`). **Bewiesen:** Der VBL mit der Fee
  dauerte länger als ein Bild, Thalions Ablauf kam nicht mehr dran.
- Ursache (abgeleitet, nicht gemessen): Mit geteiltem Bus wechseln Blitter
  und CPU je 64 Buszyklen. Die 030-Warteschleife läuft aus dem Cache und
  braucht kaum Bus, ihre 64 Zyklen dauern lange. Hatari bildet das anders
  ab, dort war die CPU nur etwa doppelt so schnell wie der Blitter.
- **HOG** (`FEEDIAGH`): Das Fantasy-Intro lief fehlerfrei, die Fee stimmte,
  das Programm endete regulär.
- Ataris Neustart in der Warteschleife (`bset #7`, im Blitter-Handbuch mit
  `tas`; `FEEDIAGR`): Erst war die Fee halb und falsch, dann sprang das
  ganze Bild mit versetzten Farben, und das Programm hing ohne Messdatei.
  Ursache unbekannt; verworfen.
- Seitdem setzt `Blit_starten` im Fantasy-Intro immer HOG. Ein HOG-Blit
  hält die CPU an; Timer A kommt dann nicht durch, und dort fehlen Proben.
  Darum zählt die Messung jetzt auch die VBLs (Block `VBLS`), und
  `mess_auswerten.py` rechnet die fehlende Zeit aus.
- STE und Falcon: gleiche Register und Fähigkeiten. Der Falcon-Blitter
  läuft mit 16 MHz, leistet aber etwa so viel wie einer mit 12 MHz, weil
  der Videl im sichtbaren Bild Bus nimmt. Beim Kopieren ist er laut Forum
  3–4 × langsamer als die CPU. Einen Blit-Interrupt hat er nicht (die
  Leitung gehört dem DSP). Der 030-Datencache gilt auch für das ST-RAM:
  Liest die CPU, was der Blitter schrieb, braucht es ein Leeren des Caches.
  Darum wird Blitter oder CPU je Rechner gewählt, als Schalter.
- Nächster Vergleich: `FEEDIAG` (alles Blitter, HOG) gegen `FEEDIAGC`
  (Umsetzen mit der CPU, Fee mit dem Blitter, HOG). Danach dasselbe für die
  Anzeige von Intro und Extro (`AMIGA_RAHMEN.S`, Blitter ohne HOG; die
  ruckelnden Sterne im Intro).

**Logo-Aufbau mit Sternschweif (Nutzer, 2026-10-02: auf dem Falcon sichtbar
langsam).** Hatari, `FEEDIAG` mit `BLIT_STATISTIK`: Außerhalb des Aufbaus
hält das Fantasy-Intro Thalions Takt (3 VBL, 17 Bilder je Sekunde), im
Aufbau (Sekunde 12–16, je Bild eine `$E2`-Spalte, 52 Bilder) 12–13 Bilder,
fast alle zu spät (vindex 3). 91 % der Amiga-Blitzeit sind Thalions Sterne
(`blit_star`/`blit_star2`: `$CA`, 2 Worte, ALWM 0, ASH = BSH), rund 190 je
Bild. Dafür gibt es jetzt `Bl_schnell_stern` (ein Langwort je Zeile, von
`BLIT_PRUEF` gegen den genauen Weg belegt: 10 653 Blits, 0 abweichend).
**Gewinn klein:** Die Sternzeit sank nur um etwa 12 % (Hatari, 1032 → 907
Proben), denn auch der alte Weg war schon vom Speicher gebremst (rund 2 µs
je Zeile). Die Bilder im Aufbau blieben bei 12–13 je Sekunde: Ein Bild
braucht dort etwas mehr als 3 VBL und wartet dann bis zum vierten.
Messdateien heißen seither nach dem Programm (`FEEDIAG.MES`, `.TXT`).

Auf dem Falcon (Nutzer, `FEEDIAG` mit `Bl_schnell_stern`): Im Aufbau 8–9
VBL je Bild statt 3, etwa 9 Messsekunden lang (Hatari 4,5). Die Sterne sind
dort ein Drittel der Zeit; die festen Kosten je Bild (Falcon-Blitter beim
Umsetzen, `Unten_herstellen`, `Lauf_zeichnen`) füllen schon außerhalb den
Takt knapp. Der Nutzer nimmt das Tempo vorerst hin („zur Not geht es“).
Dazu zwei Befunde:
- **Grafikmüll** oben, 1–2 Bilder lang: Thalions große Sterne ragen bis 8
  Zeilen unter den Schirm. Im Original liegen die beiden Schirme wie bei uns
  hintereinander (Hunk 4: `$320` + 2 × 51 200 Byte, der Hunk endet dort);
  vom ersten Schirm läuft es also auch auf dem Amiga in den zweiten. Vom
  zweiten lief es dort hinter den Hunk, bei uns in den Falcon-Schirm. Darum
  `Amiga_ueberlauf` (10 Zeilen) hinter `Amiga_schirme`.
- **Bildfrequenz unbekannt**: Die Datei passte zu 60 Hz ebenso wie zu 50 Hz
  mit 18 % ausgefallenen Proben. Seither schreibt die Messung den Block
  `H200` (Takte von `_hz_200`), und `mess_auswerten.py` rechnet daraus
  Laufzeit und Frequenz; `FREQ.TOS` (`lader/freq.s`) misst sie allein.

Auf dem Falcon (Nutzer, 2026-10-03, `FEEDIAG.TXT`, `INTRDIAG.TXT`): **60
Hz.** FEEDIAG 1588 VBLs in 5331 Takten (59,6 Hz), INTRDIAG 3810 in 12793
(59,6 Hz). Timer A verliert gegen die 200-Hz-Uhr nur 2,3 % bzw. 6 %, die Uhr
selbst also kaum etwas: Der Wert ist echt. Der Desktop stand auf NTSC, und
wir erbten das. Thalion zählt für 50 Hz, alles lief ein Fünftel zu schnell,
und die Latte „3 VBL je Bild“ lag bei 50 statt 60 ms. Gemessen in echter
Zeit braucht das Fantasy-Intro im Schnitt 73 ms je Bild (366 Bilder in 26,7
s), gut ein Fünftel über Thalions 60 ms. **Beschluss (Nutzer): PAL.**
`Fee_einrichten` und `Amiga_einrichten` setzen am RGB-Monitor und Fernseher
immer `VM_PAL` und damit auch die 256 Zeilen (`Videl_256`), die bis dahin
auf der Hardware nie liefen; VGA bleibt bei 60 Hz.

Weitere Befunde derselben Läufe: Der Grafikmüll oben ist mit dem Puffer
seltener, aber nicht weg. Im Intro sind die Zooms von Planeten und Meteor
sehr langsam; Blits 56 % (Hatari 44 %), `Bl_schnell_spalte` 19 %, die
Warteschleife des Falcon-Blitters (Umsetzen) 15 %, `Minterm_allgemein` 10 %,
Thalions Intro 10 %. (Die Blitzahl der Textausgabe läuft bei 65 536 über
und taugt nicht zum Vergleich mit Hatari.)

**Zoom schneller (2026-10-03, Hatari, `INTRSTAT` = `INTRDIAG` mit
`BLIT_STATISTIK`):** Thalions Intro wartet in Hatari 28 % der Zeit auf den
VBL (`Intro_h0+$288A` und `+$1250`, Warteschleifen). Teuer waren `$FC`
(D = A | B) und `$FE` (D = A | B | C) mit zehn Worten Breite, je 3100 Blits:
12 % der Proben über den genauen Weg und `Minterm_allgemein`. Dafür
`Bl_schnell_fc` und `Bl_schnell_fe` (mit Verschiebung, wie
`Bl_schnell_ca`). Dazu `Bl_schnell_spalte` mit C = D: Zeilenzähler im
oberen Wort von `d5`, Modulo in `a6`, kein Speicherzugriff mehr je Zeile
außer A, B, C, D. Ergebnis in denselben 60 Messsekunden: `$FC`/`$FE` 1,6 %
statt 12 %, ein Fünftel mehr Blits (106 734 statt 89 717), die Spalten je
Blit 7 % schneller, das Warten auf den VBL 31 % statt 28 %. Nur noch die 169
Blits `$CA` ohne A laufen genau. Prüffassung (`BLIT_PRUEF`, 120 s): 0
Abweichungen, 0 ungeprüft. Verbleibend: Spalten 19 %, Umsetzen mit dem
Falcon-Blitter 10,5 %, `Bereich_umsetzen` 4,5 %, Kopien `$F0` 6,7 %.

**Beschluss (Nutzer, 2026-10-04): In den Vorspännen darf Leitziel 1 an
Engstellen weichen.** Fantasy-Intro, Intro und Extro sind reines Abspielen
ohne Eingabe. Dort dürfen eigene Routinen Thalions Engstellen ersetzen
(Zooms, Logo-Aufbau), Grafik darf im Falcon/ST-Format liegen, wo nötig
vorberechnet. Für den ST muss das ohnehin sein. Begründung des Nutzers:
Leitziel 1 soll beim *Spiel* Logik, Layout und Grafik vollständig
wiederverwenden, damit wir keine eigenen Fehler hineinbringen und das
Spielgefühl dem Amiga gleicht. Bei den unveränderlichen Vor- und Abspännen
zählt, dass sie flüssig laufen. Grenzen: Thalions Ablauf, Texte, Farben und
Takt bleiben der Rahmen, ersetzt wird nur, was bremst. Das Startmenü im
Intro ist Eingabe und bleibt Thalions. Leitziel 2 gilt weiter, und für das
Spiel gilt Leitziel 1 unverändert. Den anderen Sitzungen mitgeteilt.

**K3 und unser Zoom (2026-10-04, `intro/INTRO_ZOOM.S`).** Thalions Zoom
(Hunk 0, `$1BAE`; Aufrufer `$64C` Planeten, `$BD8` Meteor, `$1536` die
beiden Logos, die Thalion beim Start in 65 und 33 Stufen vorberechnet)
beschneidet, rechnet die Schritttabellen (`$2314`) und blittet dann: Weg A
(Zielhöhe < Quellhöhe) je Zielzeile einen Blit in einen Zwischenpuffer,
dann je Zielspalte einen Blit, ein Wort breit über Höhe × 4 Ebenen, der ein
Bit setzt (`$CA` mit Maske aus A, `$E2` ohne, auf- oder absteigend); Weg B
(`$2060`) erst die Spalten, dann die Zeilen. Jedes Zielwort wird so bis zu
16-mal gelesen und geschrieben.
- **K3** (`tools/amiga_programm.py`): Der Bau ersetzt den Befehl an `$1C98`
  (`move.w Intro_h5+$11CF8,d0`, nach Beschnitt und Tabellen) durch `jmp
  Zoom_eigen`; die Originalbytes stehen in der Tabelle, sonst Abbruch.
  `Zoom_thalion` führt den ersetzten Befehl aus und springt nach `$1C9E`.
- **Unser Weg** liest Thalions Variablen und Tabellen und schreibt in
  Thalions Schirm, jedes Wort einmal: Quellbild als Farbnummern (einmal je
  Bild, es bleibt in `Zm_lager`, denn die Bilder liegen fest in den
  Datenhunks 2–4), je Zielzeile 16 Punkte über die Spaltenkarte zu vier
  Ebenenworten und Maske falten (`movep`), mit Maske einsetzen; dieselbe
  Quellzeile wird nicht neu gefaltet. 68000-tauglich.
- **Belegt** (Hatari, `ZOOM_PRUEF`: jeder Zoom erst Thalions Weg über
  `Amiga_blit`, dann unserer, die Zeilen verglichen): 180 s, 3684 Zooms,
  davon 108 über Weg B, **0 Abweichungen**. Gegenprobe mit absichtlich
  falscher Farbe 7: 827 abweichend, ab dem ersten Aufruf.
- **Tempo** (Hatari, 60 s, `INTROMES` gegen `ZOOM_THALION`): Blits 36,7 %
  → 4,9 %; unser Zoom 19 % statt rund 33 % für Thalions Weg. In der langen
  Planetenszene stiegen die Blits bisher von 21 auf 73 %, und der Anteil
  der Anzeige fiel von 27 auf 14 % (halb so viele Bilder). Jetzt bleiben
  die Blits bei 6 % und die Anzeige bei 27 %, gleichmäßig über die Szene.
  Das Vorberechnen der Logos beim Start kostete rund 2 s Blits, jetzt kaum
  messbar. Thalions Warten auf den VBL ($288A) 28,6 % statt 20,5 %.
- Erste Fassung ohne Lager: Das Wandeln je Zielzeile kostete 25 %, denn
  kleine Planeten wandelten je Zeile 64 Quellpunkte für wenige Zielpunkte.
  Unterm Strich so teuer wie Thalions Weg.
- Schalter: `ZOOM_THALION` (immer Thalions Weg, für den Vergleich),
  `ZOOM_PRUEF` (mit `AMIGA_MESSEN`; in `INTROPRF.TOS`).

**Streifen belegt (Falcon, 2026-10-04, `INTRDIAG`, 60 s, 3612 Bilder).**
Der Nutzer: Das Intro läuft flüssig, aber Streifen oben und unten, im Menü
am Ende des ersten Drittels, stärker bei Mausbewegung. Die Strahlzähler:

| Schreiben | Mal | Strahl im Bereich | danach im Bild |
|---|---|---|---|
| ganzes Bild auf den „verdeckten“ Schirm | 1145 | 572 | 50 |
| 32 Rollzeilen auf den gezeigten Schirm | 2464 | 679 | 992 |
| unser VBL insgesamt | 3612 | 2361 | 2361 |

Mindestens 522-mal las der Videl schon vor dem Umsetzen im Zielschirm: Der
„verdeckte“ Schirm war noch zu sehen. Die Rollzeilen treffen den Strahl in
gut einem Viertel der Fälle; in 65 % der Bilder läuft unser VBL noch, wenn
das Bild schon gezeigt wird. Ungeklärt ist, warum: entweder kommt der VBL
vor dem Ende der 28 angehängten Zeilen, oder die neue Bildbasis greift ein
Bild später als angenommen. Die Bestandsaufnahme unten erklärt zwei
Beobachtungen ohne weitere Annahme: Thalions VBL zeichnet in der Logoszene
die Sterne in Ebene 4 des *gezeigten* Schirms (weiße Streifen bei
Sternen), und das Menü zeichnet Einträge und Hervorhebung in den gezeigten
Schirm (Mausbewegung → neue Hervorhebung → mehr Rollzeilen mit
Zwischenständen). Messfächer: Das Fach `Intro_h0+$121C/$125C`, früher als
Sterncode gedeutet, ist Thalions Warteschleife `$1250`; auf dem Falcon
wartet Thalion zusammen mit `$288A` rund 30 % der Zeit.

**Sterne: weich im Zoom, ruckelnd danach (Nutzer, Falcon, 2026-10-04,
schon früher gemeldet).** Während „AMBERMOON“ und „THALION“ herangezoomt
werden, laufen die Sterne butterweich. Sobald „PRESENTS“ kommt oder der
Zoom fertig ist, ruckeln sie wieder stark. *Annahme, nicht gemessen:* Im
Zoom wechselt Thalion jedes Bild die Schirme, also setzt `Ganz_umsetzen`
das ganze Bild auf einmal um. Danach steht das Bild, und nur Thalions VBL
setzt die Sterne in den gezeigten Schirm; die erreichen den Falcon dann nur
über die Rollzeilen, 32 je VBL, also jede Zeile nur jedes achte Bild. Das
fiele mit einem Schirmformat ohne Umsetzen (7.7) weg.

### 7.7 Bestandsaufnahme: wer schreibt in die Schirme (2026-10-04)

Für die Frage, ob Thalions Schirme im Falcon- bzw. ST-Format liegen
können, sodass das Umsetzen entfällt. Gelesen in den Disassemblierungen
(nur Scratchpad) und in `FAIRY.S`. „Jedes Bild“ heißt: läuft in der
Schleife einer Szene; sonst einmal je Szene.

**Intro.** Schirme in Hunk 6, Zeiger 5:$1C (verdeckt), 5:$20 (gezeigt),
5:$18 (Ziel des Zeichnens, meist = $1C). Formate je Szene:

| Szene | Format | Ebenen |
|---|---|---|
| Logo, „PRESENTS“ | 320 × 200, 200 Byte je Zeile | 5 (Sterne in Ebene 4) |
| Raumszene, Twinlake, Meteor | 320 × 236 bzw. 200, 160 Byte je Zeile | 4 |
| Menü | 320 × 256, 200 Byte je Zeile | 5 |

*Blits:* Alle 18 K2-Stellen schreiben in einen Schirm (Text `$8EA`,
`$2AC6`; Menügrafik `$12BA`, `$4F2A`; Kopie gezeigt → verdeckt `$1306`;
Logostufen `$1444`; Animation `$14D8`; Löschen `$296C`; Zoom `$1D50`…
`$2306`, jetzt meist unser Zoom). Sie laufen alle durch `Amiga_blit`.

*CPU, jedes Bild:*

| Stelle | Was | Szene |
|---|---|---|
| `$29B2` + `$1AF2` in Thalions VBL (`$2646`) | Ebene 4 löschen, 150 Sterne mit `bset` setzen, **im gezeigten Schirm** | Logo |
| `$2940` | Schirm löschen: obere Hälfte Blit, untere `movem` | Raum, Meteor |
| `$1A42` | Sternbild: Wortliste in Ebene 0 | Raum |
| `$165E`/`$16A2` | Animation: Lauflängen entpacken, dann EOR in Ebene 0–3 | Twinlake |
| `$B40` | Stadtbild 128 Zeilen kopieren | Meteor |

*CPU, einmal je Szene:* Löschen und Kopieren ganzer Schirme (`$21E`,
`$3C0`, `$43C`, `$4AE`, `$9AE`/`$9DE`, `$D8C`, `$DB4`, `$FB2`, `$137E`),
Umbau 5 → 4 Ebenen (`$3D6`) und 4 → 5 (`$F6C`), Stadtbild (`$776`),
Text mit dem großen Zeichensatz (`$2ADA`/`$2B9A`, ODER in eine Ebene: in
den Schirm von `$7BA`, `$A04`, `$A20`, `$1024`, in den Textpuffer von
`$2E6`, `$2A24`), Textwischer zeilenweise in den **gezeigten** Schirm
(`$302`, 22 Zeilen, je zwei VBL). Das Menü zeichnet in den gezeigten
Schirm (`$FDC`: 5:$18 = 5:$20), auch die Hervorhebung (`$121C` → `$29F4`,
Blit).

*CPU liest aus dem Schirm* (Amiga-Format vorausgesetzt): `$4BC` baut die
Sternbildliste aus Ebene 0, `$1560` holt die gezoomten Logostufen zurück,
`$15A6` holt ein Bild als Maske und Ebenen zurück (Raumszene, `$6EE`).

**Extro.** Schirme 6:$2E90 und +51200 (320 × 256 × 5, 200 Byte je Zeile),
Zeiger 5:$10/$14/$18. Jedes Bild schreibt nur der Blit `$4AA` (fünfmal,
D = C ? B : A) den ganzen Schirm; Quellen sind Puffer (Hintergrund
6:$28690, Textebene 6:$1BE90, Maske 6:$320). Die CPU schreibt nur
einmal je Bild der Abfolge: Hintergrund in beide Schirme (`$2CA`), untere
Hälfte löschen (`$3F2`). `$2B2E` rechnet die Textebene aus dem
Hintergrund (Farben je Punkt), das sind Puffer, kein Schirm.
*Berichtigt 2026-10-08:* `$3F2` (und `$3C8` davor) ruft niemand, weder
`bsr`/`jsr` noch ein Zeiger in den Datenhunks; toter Code. Es bleibt
`$2CA`, im Ablauf ab `$250` je Bild der Abfolge.

**Fantasy-Intro** (`FAIRY.S`, 3.1/3.4). Zwei Schirme in Hunk 4 (320 × 256
× 5, 200 Byte je Zeile). Jedes Bild: Blits `make_magic` (Schriftzug),
`blit_star`/`blit_star2` (Sterne mit Maske); CPU `plot_5p`/`plot_5p2` und
`plot00`…`plot31` (Funken, feste Abstände 40/80/120/160). Dazu im
Binärteil Hintergrund in beide Schirme, Schirm füllen (`$11D4`), ein Blit
des Rahmens (`$BC0`). Die Fee zeichnen wir schon selbst.

**Folgerungen.**
- Blits lassen sich an einer Stelle umlenken: `Amiga_blit` erkennt eine
  Adresse im Schirm und rechnet je Zeile Bildzeile, Ebene und Wort ins
  Falcon-Format um (Wortschritt 16 statt 2). Das gilt für alle drei
  Programme.
- Die CPU-Stellen nicht. Im Intro sind es fünf je Bild, rund fünfzehn je
  Szene und drei lesende; jede bräuchte einen K3-Eingriff. Das Extro
  braucht zwei, das Fantasy-Intro die Plotroutinen und zwei im Binärteil.
- Das Menü zeichnet mit der CPU (Zeichensatz) in den Schirm. Ein Format
  im Schirm berührt dort also Thalions Menücode; der Beschluss vom
  2026-10-04 lässt das Menü bei Thalion.
- ST: Die bewegten Intro-Szenen (Raum, Twinlake, Meteor) haben vier
  Ebenen, also 16 Farben, und passen ebenenweise auf das ST-Format. Die
  Szenen mit fünf Ebenen (Logo, Menü, Extro, Fantasy-Intro) nicht: Eine
  Farbreduktion braucht den ganzen Punkt, Thalion schreibt aber
  ebenenweise. Dort braucht der ST eigene, vorberechnete Daten.

### 7.8 Schirme im Zielformat (Nutzer, OK 2026-10-08)

Ziel: Thalions Blits schreiben gleich in Schirme, die der Videl ohne
Umsetzen zeigt (7.7). Das spart das Umsetzen und nimmt die Streifen
(Schreiben in gezeigte Zeilen) an der Wurzel weg. Schritte: 1 Timing
messen, 2 Schirmtabelle, 3 Blits umlenken, 4 Extro zuerst; danach
Fantasy-Intro und Intro.

**Das Format** nennen drei Werte in `amiga_vorspann.i`: `ZIEL_EBENEN`,
`ZIEL_ZEILE` (Bytes je Bildzeile), `ZIEL_WORT` (von einem 16-Punkte-Wort
zum nächsten). Falcon 8, 320, 16; der ST bekäme 4, 160, 8. Der Code rechnet
nur mit diesen Werten.

**1. Timing (`INTRDIAG.TOS`, gebaut, ungetestet).** Beim Eintritt in
unseren VBL liest `Tk_vbl` den Videozähler und ordnet ihn ein: im zuletzt
gesetzten Schirm („neu“) oder im davor gesetzten („alt“), in Fächern zu 16
Zeilen, „Anfang“, „Ende“ (genau hinter der letzten Zeile), „dahinter“. Das
getrennt danach, ob der VBL davor umgeschaltet hat. Steht der Zähler nach
einem Umschalten auf „neu Ende“, kommt der VBL nach der Anzeige und die
neue Basis greift im nächsten Bild; „alt“ hieße ein Bild später. Damit die
Fächer eindeutig sind, liegen in den Diagnosebauten 32 Zeilen Lücke
zwischen den Schirmen (`FALCON_LUECKE`). Ausgabe in `INTRDIAG.TXT`, dazu
die ersten acht Zählerstände nach einem Umschalten.

**2. Schirmtabelle.** Das Programm nennt in `Schirm_tabelle` Thalions
Schirme, die direkt gezeigt werden (Makro `SCHIRM`: Adresse, Zeilen,
Ebenen). `Schirme_anlegen` (`amiga/AMIGA_ZIEL.S`) legt zu jedem einen
Zielschirm an. **Massgeblich ist der Zielschirm.** Thalions Amiga-Schirm
bleibt als Zwischenspeicher, je Zeile mit einem Merker „gilt“. Der VBL
zeigt den Zielschirm direkt (`Anzeige_direkt`), wenn die Copperliste ihn
ganz zeigt: alle Ebenen im Abstand 40, Ebenen und Zeilenlänge wie in der
Tabelle, und das Fenster füllt die Anzeige. Die Bankebene 5 zieht er dort
nach, wenn sich die Teilung ändert. Sonst setzt er um wie bisher und holt
vorher ungültige Zeilen in den Zwischenspeicher. Den Mauszeiger zeichnet er
nicht in einen direkten Schirm, denn der ist Thalions Zeichenfläche.

**3. Blits umlenken.** `Amiga_blit` fragt zuerst, ob ein benutzter Kanal
in einem Schirm der Tabelle liegt (ohne Tabelle kostet das einen Vergleich).
Dann:
- *direkt ins Ziel*, wenn nur D im Schirm liegt und es einen Weg gibt:
  aufsteigend, jede Zeile bleibt in einer Ebene einer Amiga-Zeile, der
  Schritt sind ganze Zeilen. Bisher `Bl_ziel_d8` (Minterm `$D8`, Extro),
  derselbe Code wie `Bl_schnell_d8`, nur mit dem Wortschritt als
  Makrowert. Die Zeilen im Zwischenspeicher gelten danach nicht mehr.
- *über den Zwischenspeicher* in allen anderen Fällen: die berührten
  Zeilen holen (nur ungültige), Thalions Blit unverändert dort, die Zeilen
  von D ins Ziel bringen. Das ist immer richtig, aber teuer, wenn es oft
  vorkommt; die Messung zählt es.
- Holen und Bringen macht der Falcon-Blitter je Ebene. Außerhalb des VBL
  sperrt es dabei den VBL (Stufe 4), der den Blitter auch benutzt.
- Prüfung: In `EXTROPRF.TOS` läuft jeder Blit direkt ins Ziel auch über
  den Zwischenspeicher; Ergebnis im Ziel und Register werden verglichen
  (`Bl_ziel_pruefen`, Abweichungen in derselben Zahl wie bei
  `BLIT_PRUEF`).

**4. Extro (gebaut, ungetestet).** Schirme `6:$2E90` und `6:$F690`,
256 Zeilen, 5 Ebenen. Thalion zeichnet je Bild fünfmal `$4AA` (`$D8`,
nur D im Schirm) und schaltet über die Copperliste um (`$EBC`, dann auf den
VBL warten). Die einzige CPU-Stelle ist `$2CA` (Hintergrund in beide
Schirme). K3 an `$2EC` (`Extro_nach_kopie`): Thalions Kopie läuft
unverändert in den Zwischenspeicher, danach bringt `Alle_bringen` beide
Schirme ins Ziel; dann die drei überdeckten Befehle. Thalions Code bleibt so
an allen Stellen, wo er schreibt; ersetzt ist nur, wohin.

**Hardwaretests T5 und T12 (Falcon, Nutzer, 2026-10-09).**
- *T5 Fantasy-Intro:* 50 Hz und 256 Zeilen bestätigt. `FEEMESSB`
  (Blitter) gegen `FEEMESSC` (CPU), je ein Lauf: knapp 104 gegen 200, zu
  spät 59 gegen 60, längstes Bild vindex 6, Blits 10 689 gegen 10 776. Der
  Blitter mit HOG ist auf dem Falcon nicht langsamer als die CPU (in
  Hatari war die CPU doppelt so schnell); das Umsetzen bleibt beim
  Blitter. `FEEMESSB/C` schreiben keine Dateien, sie zeigen die Zahlen am
  Ende auf dem Desktop. Dünne Linien oben, sporadisch, nur mit dem Blitter
  (`FANTASY`, `FEEMESSB`). Drei Vermutungen, keine belegt: (1) die Sterne
  laufen in die oberen Zeilen des zweiten Amiga-Schirms, seit PAL sichtbar
  (`Anzeige_erste` 0); (2) wir setzen in den gezeigten Schirm um (die Frage
  von T11); (3) ein HOG-Blit hält den VBL bis zu einer Ebene lang auf
  (laut Blitter-Handbuch wartet die CPU samt Interrupts bis zum Ende), und
  der VBL zeichnet die Fee dann in schon gezeigte Zeilen. Das Einrichten
  des Blitters stimmt mit dem Handbuch (Atari-Wiki, „Blitter manual“).
  `FEEDIAG` (Falcon, 2026-10-09; ausgewertet mit der Karte eines
  Nachbaus, der der gelaufenen Datei bytegleich ist): 50,1 Hz (1800 VBL in
  7192 Takten der TOS-Uhr), 36 s, 490 Bilder, außerhalb des Logo-Aufbaus
  18 Bilder je Sekunde (Thalions Takt), im Logo-Aufbau (Sekunde 12–19)
  6–9; Timer A fehlen 5,1 % (HOG). Strahl:
  | Schreiben | Mal | Strahl im Bereich | danach im Bild dieses Schirms |
  |---|---|---|---|
  | unser VBL (ganzes Bild) | 1800 | 951 | 951 |
  | Fee: altes Rechteck zurück (gezeigter Schirm) | 1306 | 0 | 291 |
  | Fee: neu zeichnen (gezeigter Schirm) | 1800 | 0 | 1364 |
  | Umsetzen ab `WECHSELZEILE` (verdeckter Schirm) | 490 | 9 | 80 |

  Die Fee kreuzte der Strahl nie. In 80 von 490 Bildern zeigte der Videl
  nach dem Umsetzen noch den „verdeckten“ Schirm, 9-mal lief der Strahl
  durch die umgesetzten Zeilen; das ist echt, betrifft aber nur Zeilen ab
  `WECHSELZEILE` (134). **Die Linien liegen woanders** (Nutzer): im
  Fantasy-Intro in den obersten knapp 10 Zeilen, im Intro oben und unten je
  etwa 10. In die obersten Zeilen schreiben wir nach dem Start nicht mehr:
  Umgesetzt wird ab Zeile 134, und die Fee fliegt nur zwischen y 138 und
  194 (Thalions Flugbahn, 759 Punkte). Vermutungen 1 bis 3 erklären die
  Linien damit nicht. Neue Vermutung 4, nicht belegt: Unser VBL kommt zu
  spät (ein HOG-Blit des Hauptablaufs hält ihn auf; in 951 von 1800 Fällen
  lief er noch, als das Bild schon begann) und greift dann auf Palette und
  Bus zu, während der Videl die ersten Zeilen holt. Das passt zu „nur mit
  dem Blitter“ und zu Zeilen am Bildanfang, im Intro auch am Bildende,
  falls der VBL dort schon vor der letzten Zeile kommt. Wo der Strahl beim
  Eintritt in den VBL steht, misst T11 (`Tk_vbl`).
- *T12 Extro:* `T12EXTR` läuft durch; der Rolltext ruckelt leicht,
  unabhängig von der Textmenge (Takt oder Last). Das ganze Extro ist für
  eine Messung zu lang: `EXTROMES` ersetzt durch `EXTRDIAG` (wie
  `INTRDIAG`: `MESS_ENDE=60`, `STRAHL`). `EXTROPRF` ist fast ein Standbild
  (eine Zeile in 3 s) und endet jetzt nach 120 Messsekunden. Linien oben
  nur in `EXTROPRF`, nicht in `T12EXTR` (Nutzer). Bisher also überall dort,
  wo der Falcon-Blitter in Schirme schreibt (Fantasy-Intro mit Blitter,
  Intro, `EXTROPRF` beim Holen und Bringen), und nirgends, wo nur die CPU
  schreibt (`FEEMESSC`, das Extro im Zielformat). Das stützt Vermutung 2
  oder 3, belegt keine.

**T11, Videl-Takt (Falcon, Nutzer, 2026-10-09, `INTRDIAG.TXT`).** 60 s,
3614 VBL in 14 442 Takten der TOS-Uhr: 50 Hz. Strahl beim Eintritt in
unseren VBL (`Tk_vbl`):
- ohne Umschalten im VBL davor: 2467-mal knapp hinter dem Ende des
  gezeigten Schirms (Videozähler = Ende + 2 Byte). Der VBL kommt also
  pünktlich nach der letzten Zeile.
- nach einem Umschalten im VBL davor: **1147 von 1147** Mal hinter dem Ende
  des *alten* Schirms (Beispiele: Videozähler 10 238 Byte vor bzw. 174 082
  hinter dem neuen Schirm, beides Ende des alten + 2).

**Belegt: Eine Bildbasis, die unser VBL schreibt, gilt erst ein Bild
später.** Der Videl übernimmt die Basis schon vor oder mit dem VBL; was der
VBL schreibt, greift erst beim nächsten. Das Bild nach dem Umschalten zeigt
noch den alten Schirm, in den Thalion dann schon zeichnet. Auf dem Amiga
gilt die neue Copperliste ab dem nächsten Bild, weil Thalion sie während
des Bildes setzt; wir lesen sie erst im VBL und setzen die Basis dann ein
Bild zu spät. Das erklärt das Schreiben in gezeigte Zeilen (7.6, `STRAHL`)
und im Fantasy-Intro die 80 Bilder, in denen in den gezeigten Schirm
umgesetzt wird; ob auch die Linien oben (T5), ist offen. Weitere Zahlen:
Rollzeilen auf den gezeigten Schirm 2464-mal, Strahl 215-mal darin; der VBL
der Schicht läuft in 2361 von 3614 Fällen bis ins Bild.

**Abhilfe (Nutzer, OK 2026-10-10; gebaut, auf Hardware ungetestet, Test
T17).** Die Basis wird geschrieben, sobald umgeschaltet wird, nicht erst im
VBL; der Videl übernimmt sie dann zum nächsten Bild wie der Amiga die
Copperliste.
- Fantasy-Intro: `Anzeige_setzen` (unser Code, Thalions `$C98`) schreibt
  die Basis selbst; `Fee_vbl` schreibt sie noch einmal, mit demselben Wert.
- Extro: K3 an Thalions zwei Aufrufen von `$EBC` (neue Copperliste):
  `$1E8` → `Extro_umschalten_1`, `$596` → `Extro_umschalten_2`
  (`extro/EXTRO_SUP.S`). Beide rufen `$EBC`, dann `Anzeige_sofort`
  (`AMIGA_RAHMEN.S`), dann den Befehl, dessen erstes Wort der `jmp`
  überdeckt. `Anzeige_sofort` liest die Liste wie der VBL; zeigt sie einen
  Schirm im Zielformat ganz (`Anzeige_direkt`), gilt die Basis jetzt, und
  der VBL findet den Zustand schon vor. Sonst bleibt es beim VBL.
- Intro (2026-10-15, T23): K3 at the end of Thalion's `$2452` (`$24BE`,
  14 callers) goes to `Intro_umschalten`: it does the covered stores and
  calls `Anzeige_umschalten` (`AMIGA_RAHMEN.S`), which converts a changed
  picture at once and writes the base, so it holds from the next frame.
- Rest-Risiko, nicht gemessen: Fällt das Schreiben in die wenigen Zeilen
  zwischen der Übernahme durch den Videl und unserem VBL, gilt die Basis
  wie bisher ein Bild später.
- **Fee flackert in Hatari (Nutzer, 2026-10-10; Hatari-Probe, belegt).**
  `FANTASY.TOS` (mit Abhilfe) und `FEEMESSB.TOS` (08.10., ohne), je zwölf
  Einzelbilder ab VBL 1100, Falcon, TOS 4.04: Mit Abhilfe fehlt die Fee
  genau im ersten Bild nach jedem Schirmwechsel (4 von 12), ohne Abhilfe
  in keinem. Erklärung (abgeleitet): Hatari malt ein Falcon-Bild auf
  einmal mit der Basis, die zum VBL steht (vgl. 150). Das ist jetzt schon
  der neue Schirm, und in dem hat das Umsetzen die Fee überschrieben;
  `Fee_vbl` zeichnet sie erst danach. Der Falcon holt die Zeilen
  fortlaufend, die Fee liegt ab Zeile 138, und `FEEDIAG` sah den Strahl
  nie in der Fee: Dort sollte sie stehen bleiben. Entscheidet T17. Flackert
  sie auch auf dem Falcon, zeichnet `Anzeige_setzen` die Fee vor dem
  Schreiben der Basis in den neuen Schirm.
- **Fairy drawn before the base (2026-10-15, T23).** `Anzeige_setzen`
  (`FEE_SUP.S`) now draws the fairy into the new screen before it writes
  the base (interrupts off, `Fee_vbl` uses the same sprite state). Hatari:
  the fairy stands in 12 of 12 frames from VBL 1100.
- **White frame before the zoom (finding 2026-09-30; cause found and fixed
  2026-10-15, T23).** Thalion precomputes the zoom stages into the hidden
  screen (`$14E6`); the full-size stage stays in its plane 4. Before the
  zoom loop `$137E` clears only planes 0-3 of both screens. On the Amiga
  that does not show: Thalion's VBL clears plane 4 of the shown screen
  (`$29B2`) and draws the stars (`$1AF2`) in the blanking, before the beam
  reaches the picture. We converted the screen earlier (at the switch and
  before Thalion's VBL), so the rest showed for one frame, white (colour
  16). Hatari, register dump at VBL 973/974: copper list switched to the
  second screen for the first time, BPLCON0 $5200. Fixes:
  - `Zoom_loeschen` (`INTRO_SUP.S`, K3 at `$137E`, the whole routine): as
    Thalion, plus plane 4 of the hidden screen to 0, then the shown screen
    converted whole (`Anzeige_umschalten`). Without the last step the old
    logo stood two frames in the new colours, because Thalion clears the
    shown screen too and we follow up only `ROLLZEILEN` lines per VBL.
  - `Thalion_vbl_ende` (`INTRO_SUP.S`, K3 at `$2824`, the common end of
    Thalion's VBL `$2522`): Thalion's end, with `Anzeige_vbl` before the
    `rte`. `Amiga_vbl` only jumps to Thalion's VBL while it is installed
    (`THALION_VBL`). Stars, colours and pointer now show in the frame
    Thalion wrote them for.
- **Stars stutter without a zoom (user 2026-10-15; Hatari, proven).**
  Without a switch we followed up 32 lines per VBL; each star moved once
  in 7 frames, in bands. `Ebene4_nachfuehren` (`AMIGA_RAHMEN.S`, only with
  `EBENE4_MERKER`, intro: `Intro_h5+$2A`, Thalion's "stars on") blits plane
  4 of the shown picture into Falcon plane 4 every VBL. Hatari: stars
  change in every frame, about 10 % of a VBL more blitter time; frames per
  zoom stage unchanged (2-3 VBL). Open, only hardware shows it: our display
  now runs later in the VBL; if it ends after the upper border, the top
  lines are one frame old.
- **Garbage lines in the picture, three slow spots (user, Falcon, T23,
  2026-10-17).** T23 passed for the fairy, the extro music, the key click,
  the intro music and the smooth stars. Open: garbage lines, also in the
  middle of the picture, and three slow spots (user): the zoom onto the 3D
  Lyramion; the 2D animation of the meteor impact, slow while the meteor
  BOB is large (it flies diagonally through the pictures, and in the
  middle the picture beneath changes from the whole city to the destroyed
  one); the clouds that part to the left and right before the menu.
- **T27 (user, Falcon, 2026-10-17).** (a) `T27INTR.TOS`, without
  `Ebene4_nachfuehren` (switch `OHNE_STERNE`): the garbage lines stay, so
  the stars are not the (only) cause. (b) `T27DIAG.TXT` (`AMIGA_MESSEN`,
  `STRAHL`, the whole intro to the menu, 146 measured seconds):

  | Write | Times | Beam in the lines meanwhile |
  |---|---|---|
  | whole picture into the hidden screen | 1511 | 2 |
  | 32 roll lines into the shown screen | 8691 | 2313 (27 %) |

  Proven: the conversion at the switch (`Anzeige_umschalten`, new in T23)
  is clean; the roll lines write where the Videl reads in a quarter of
  the frames. Our VBL now mostly starts when the picture is already
  running: without a switch before, the beam stood in lines 0-64 of the
  shown screen at the entry about 4100 times, behind the picture only
  about 2900 times; in T11 (before the music) it came after the picture
  every time. Assumption, well supported: the music runs first in
  `Amiga_vbl` (`Mischer_vbl`), about 14 % of the time, a good part of it
  waiting for the DSP host port (`md_senden`), and pushes the display
  into the picture. Time per second: only seconds 117-140 (the clouds
  before the menu) are saturated, 75-80 % in Thalion's blits (over the
  whole run the fast path `$CA` leads; which blits the clouds use was not
  counted), Thalion's wait loops (`$1250`, `$288A`) almost
  gone; elsewhere Thalion still waits 40-75 % of the time. The two other
  slow spots do not show as a full load. 8711 VBLs in 154 s of the TOS
  clock give 56 Hz instead of 50: the clock probably lost ticks while the
  Falcon blitter held the bus, so the seconds are approximate.
- **Rolling behind the beam (user, OK 2026-10-17; built, test T28).**
  `Roll_strahl` (`AMIGA_RAHMEN.S`) reads the video counter before every
  roll and lets through only lines the beam has passed in this frame, or
  a band at least `ROLL_VORLAUF` (64) lines ahead; a band in between waits
  for the next VBL, a band the beam is inside shrinks to the part behind
  it. Is the beam not in the shown screen, it counts as at line 0. The
  64 lines are an estimate, not measured. Expected cost: the top lines
  are followed up more slowly when the VBL starts late. `T28DIAG.TOS`
  measures as T27; the roll hits should drop to about 0, the number of
  rolls shows how often a band waited. Also for the music session: the
  wait for the DSP in the VBL (docs/13).
- **Display before the music (user, OK 2026-10-18; built, test T29).**
  `Amiga_vbl` now calls `Anzeige_vbl` first and `Mischer_vbl` after it;
  while Thalion's VBL is installed, `Thalion_vbl_ende` does the same after
  Thalion's work. The music session: the mixer keeps three pieces ahead
  and does not mind a later call. T29 is T28 plus this, so T28 alone
  shows what `Roll_strahl` does.
- **Samples into the DSP (way 1, docs/13 4e): does not fit (2026-10-18,
  read from the files).** The music session asked for the four 4e fields
  for intro and extro. Thalion's players in `INTROMUS.DAT` and
  `EXTROMUS.DAT` are built as the game's: the song at file `$197C` (first
  offset `$28`, 8 offsets, the last one to N, N lengths, the samples), the
  pointer to its first area at `$3FC` (game 3:`$3AFE`), four channel
  records of `$CE` from `$BC` (game 3:`$37BE`), the synth wave copied to
  the start of the record (`$D78`), the silence at `$3F4` (game
  3:`$3AF6`). Both players use the same offsets. But the samples are too
  large for the DSP's 46 848 bytes (`$3D00` words of three bytes; a
  comment in `MISCHER.S` says 47 872): intro 7 samples, 64 426 bytes;
  extro 13 samples, 102 992 bytes. With the four fields the mixer would stay on
  way 2 (`md_proben` checks the size). Handed to the music session, whose
  mixer it is.
- **Partial way 1 (user, OK 2026-10-18; built into T29).** The music
  session allows two of the four fields: `MS_SAETZE` = `Musik_daten+$BC`
  and `MS_STILLE` = `Musik_daten+$3F4`, with `MS_STUECK` and `MS_LIED`
  left 0. Synth and silent channels then go way 1, sample channels stay on
  way 2. `Musik_mischen` (`AMIGA_MUSIK.S`) sets them in our block before
  `Mischer_install`, as in the game. That is before Thalion's init, and it
  may be (music session, from the code): the mixer only compares addresses
  with them and reads a record only after a channel played from it, and
  `Musik_daten` is loaded by then. What it saves is not measured: `T29DIAG` shows it in the
  mixer's lines. A larger sample area in the DSP (reloading only the
  samples being played) is the music session's matter and waits for this
  measurement.
- **T28 and T29 failed (user, Falcon, 2026-10-21).** Garbage lines in
  both, also in `T29INTR`; only during animations (the zooms, the
  animation in Twinlake, the meteor flying diagonally): something like a
  late, shifted picture line, but garbage, that moves along; with much
  going on two, in the upper and the lower third. `T29DIAG`: the menu
  never appeared (the user then clicked INTRO blind and stopped). `T28`:
  the menu highlight reacts unreliably, under the mouse it stays white.
  The measurements (`T28DIAG`, `T29DIAG`, to the menu):

  | | T27 | T28 | T29 |
  |---|---|---|---|
  | 32 roll lines into the shown screen | 8691 | 2215 | 191 |
  | of them with the beam in the lines | 2313 | 0 | 0 |
  | whole picture into the hidden screen, beam in it | 2 of 1511 | 0 | 0 of 1779 |
  | our VBL starts behind the picture (no switch before) | about 2900 | not counted here | 5841 |

  - *Menu and highlight, cause found in the code, the figures support it:*
    `Roll_strahl` counted a beam outside the picture of `Falcon_vorn` as
    line 0 and refused the top band, and `Anzeige_nachfuehren` retried the
    refused band every VBL without moving on. With the display before the
    music (T29) our VBL almost always comes in the blank, so the roll
    stood at the top for good, and what Thalion draws into the shown
    screen (the menu) never reached the Falcon. In T28 the VBL often came
    with the beam in the first 64 lines; the roll moved now and then.
  - *Garbage lines, cause open:* none of our measured writes meets the
    beam any more, so they are neither the roll lines nor the conversion
    at the switch. Unmeasured writes into the shown screen are plane 4 of
    the stars (`Ebene4_nachfuehren`) and the pointer. Thalion's Twinlake
    loop (`$A6C`: wait 4 VBLs, delta frame into the hidden screen `$165E`,
    swap `$240E`, new list `$2452`, copy shown → hidden `$12C0`) touches
    only the hidden screen after the switch, read from the disassembly.
    After 1600 of 1779 switches our next VBL found the beam still in the
    old screen. Derived, not measured: the conversion at the switch (main
    flow, VBL held off) mostly ends after the frame start, so the new base
    shows one frame late (the T11 lag, back in the intro).
  - Mixer share (sum of its routines): T28 14.6 %, T29 11.1 %;
    `md_senden` is gone from the top. Rough, 64-byte bins, unequal runs.
- **T60: the roll no longer stalls (user, OK 2026-10-21; built).**
  `Roll_strahl` lets a band through when the beam is not in the picture
  of `Falcon_vorn`: behind it the blank is still ahead (RGB 50 Hz 72
  lines, more than `ROLL_VORLAUF`; VGA only about 22, a risk there), and
  in the other screen `Falcon_vorn` shows only from the next frame. A
  refused band is skipped; it comes again next round. `T60DIAG` adds two
  lines: skipped bands, and plane 4 of the stars written into the shown
  screen (`St_eb4`, beam in the lines meanwhile).
  `T60TEIL.TOS` (switch `BLIT_TEILEN`, user, OK 2026-10-21) tests an
  assumption about the garbage lines: our HOG blits of the conversion at
  the switch, now in the main flow and so during the picture, might keep
  the Videl from its data. `Blit_starten` then runs without HOG and
  restarts the blitter with `bset` (the ST way). Lines gone: the bus is the
  cause; lines still there: it is not.
- **T60 on the Falcon (user, 2026-10-22).** `T60INTR`: the menu is
  visible and its entry pulses under the mouse; the stall is gone.
  `T60TEIL`: the garbage lines stay, so HOG is not their cause, and HOG
  stays. What the user sees now: one stripe always near the top; with
  movement it goes down, or it stays and a second one comes; with large
  moving areas it jumps more. "Like the end of a time measurement with
  palette colours", where the coloured part of the frame is set back to
  black. `T60EXTR`, `T60DIAG`: no report yet.
- **T61FARB: the palette written only where it changed (user, OK
  2026-10-22; built).** Assumption, not proven: `Farben_setzen` writes all
  64 Videl colours every VBL, as the last step of our display, whether a
  colour changed or not; so it writes at the moment our work ends, and our
  VBL mostly comes behind the picture (T29DIAG), so that moment lies in the
  top lines, lower when the conversion in the main flow holds the VBL off.
  That fits the picture above, if writing the Videl palette during the
  display shows garbage on the Falcon, which only the hardware tells.
  Switch `FARBEN_NUR_NEU`: the colours go into `Farben_neu` first, and into
  the Videl only the entries that differ from `Farben_alt`. Stripe gone in
  still scenes: the palette is the cause, and the switch becomes the rule.
  Stripe unchanged: next suspect is `Basis_setzen`, the picture base
  written during the display.
- **T61FARB and T60DIAG on the Falcon (user, 2026-10-23).**
  - `T61FARB`: the stripes are now very rare: in every palette fade (to
    black and back), and a few single pixel groups in the zoom of the sun
    and the earth. So writing the Videl palette while the picture runs is
    the cause of the stripes (proven by A/B against `T60INTR`); the fades
    still write during the picture, because the colours really change.
  - `T60DIAG` (8654 VBL): our display (`Anzeige_vbl`) ends with the beam
    in the picture 6931 times, so the palette came there in 80 % of the
    frames. Rolls 8279 (T29: 191), the stall is gone; skipped bands 355;
    full conversions 1507, beam hits 0. But **roll hits 412** (5 %), where
    0 was expected: bands the new rule let through while the beam was
    behind the picture or in the other screen, and which the beam then
    reached at the next frame start. Plane 4 of the stars 924 times, beam
    in its lines 824 times (by design: the whole window every VBL).
  - Candidates for the pixel groups in the zoom: the roll hits, or plane 4
    of the stars ahead of the other planes (it is fresh, the roll lags).

- **T62: the palette at the start of the VBL, the roll with the vertical
  counter (2026-10-23, T62 passed).** `Farben_rechnen` (end of
  `Anzeige_vbl`) puts the 64 colours into `Farben_neu`; `Farben_schreiben`,
  the first thing in `Amiga_vbl`, writes only the changed entries into the
  Videl. The colours follow Thalion one frame later, as a new picture base
  does. `Roll_strahl`: is the beam not in the picture of `Falcon_vorn`,
  `Strahl_vorlauf` takes its distance to the top of that picture from VFC
  (`$FFFF82A0`), VFT and VDB as a line above the picture, and the T28 rule
  holds (band at least `ROLL_VORLAUF` lines ahead). *Assumed:* VFC counts
  half-lines like VFT. `T62DIAG` records VFC at our VBL (per 32
  half-lines) with VFT, VDB and VDE, counts palette writes with the beam in
  the picture (by VFC and by the video counter) and bands refused before
  the picture.
  *On the Falcon (user, 2026-10-23, `T62INTR`):* the garbage lines are
  gone; `T62EXTR` runs through; E17 works (`MUSIC=OFF`, `MUSIC=CPU`, no
  file). `T62DIAG` was waived. Left: a few single pixels in the zoom of sun and earth, always
  while the text at the bottom fades. Open, for later (user); the target
  format for the intro (below) may take it away with the roll.
- **White frame before the menu (user, 2026-10-23; in T60, T61 and
  probably earlier; fixed in T62).** Just before the menu fades in, one frame nearly
  full of white garbage, every time. *Cause, read in Thalion's code (hunk
  0), confirmed by the fix:* at `$F94`–`$FAE` Thalion switches from
  the four-plane screen to the five-plane menu screen in this order:
  `$240E` swaps the screens, `$28` = 5, `$2452` writes the copper list
  with five plane pointers at 200 bytes per line and sets COP1LC, `$288A`
  waits for the VBL, and only then `$289A` writes BPLCON0 (5 planes) and
  BPL1MOD (160). On the Amiga the new list takes effect at that VBL, and
  `$289A` runs right after it, still in the blank: no wrong frame. Here
  the K3 at `$24BE` (`Anzeige_umschalten`) converts the new list at once,
  with the old BPLCON0 and BPL1MOD (4 planes, 160 bytes per line), and
  shows it from the next frame; the VBL after `$289A` sees the change and
  converts again. In between one frame of the menu screen read with the
  wrong line length. The same order is at `$406`/`$42A` and `$CD8`/`$D0C`,
  but there the list keeps its plane count and only the registers change.
  *Fix in T62 (user, 2026-10-23; on the Falcon the white frame is gone):* `Liste_lesen` counts the
  planes the list has pointers for (`Z_LISTE`). `Anzeige_nachfuehren`
  keeps the shown picture while that count differs from BPLCON0 and from
  the last list's count, at most `LISTE_WARTEN` (3) times; expected are
  two (the K3, the VBL in `$288A`). Then it converts as before. `T62DIAG`
  counts the waits.
- **T63: the 4-plane scenes in the target format (user, OK 2026-10-23;
  built 2026-10-24; T63 passed, user 2026-10-25).** On the Falcon the
  intro runs to the menu as before; one finding: when the star field
  stops, it changes once more during the rest (docs/05b, likely the cap
  `STERNE_MAX`, see T64). Steps 1 and 2 of the plan for the
  intro. Thalion's screens there are `6:$C0` and `6:$C0+37760`, 4 planes,
  160 bytes a line (`$42E`).
  - *A table per scene* (`Schirme_wechseln`, `AMIGA_ZIEL.S`): the screens
    of the old table are fetched whole, the new one goes into
    `Schirm_tabelle`, `Schirme_anlegen` brings it into the target; the
    display is judged anew at the next VBL. K3 at `$4F4` (after the star
    list, `Schirme_raum`, 236 lines), `$AD4` (`Schirme_meteor`, 200
    lines: the meteor scene shows only 200, and Raum's text below must
    not show) and `$D00` (no table; every way to the clouds and the menu
    passes there, also the click). Logo, clouds and menu stay converted.
  - *Black margins* (`ZIEL_RAND_ZEILEN`, 16 lines above and below each
    target screen, and the lines below `SCH_ZEILEN`, all kept 0 and
    cleared by `Schirme_anlegen`): `Anzeige_direkt` now also shows a
    window that is shorter than the display (236 or 200 lines) or moved
    off its top (Twinlake shakes the window up to 8 lines down and 3 up,
    table `$11D8`). The
    rule: the window lies in the screen, and below it either the display
    ends or the screen does; display line 0 is target line r0 - f0. The
    bank plane covers the margins too.
  - *Writing, read in hunk 0:* every frame `$2940` clear (lines 0-199),
    `$1A42` star picture, `$1BAE` zoom (ours), `$776`/`$B40` city picture
    (128 lines at line 36, word 5), `$165E`/`$169C` Twinlake's animation
    (byte EOR, lines 7-183), `$12C0` copy shown -> hidden (same area).
    Our routines write the target and mark the buffer lines invalid
    (`Zeilen_ungueltig`; clearing is one Falcon blit, `Ziel_loeschen`).
    Once per scene Thalion's code runs between `Schirm_vorher` (fetch)
    and `Schirm_nachher` (bring): the city text `$7BA`, Twinlake's
    picture `$994`-`$A36` (both screens, `Alle_*`). The reader `$15A6`
    (a piece back as mask, `$6EE`) fetches first. Thalion's blits (text
    at the bottom `$8EA`, the two BOBs `$1464`/`$1472` at the end of the
    space scene) go through the buffer by themselves (`Bl_umlenken`).
  - Not measured: how much time it saves, and how often the BOBs fetch
    and bring their 48 lines.

### 7.8a The same method on both machines (E30, user 2026-10-25)

Per program, Falcon and ST do the same things the same way, so that a
reader of one understands the other; neither takes Thalion's way with
live conversion where the other has its own scene. The picture in the
machine's format is authoritative, an Amiga screen is at most a buffer;
live conversion stays only where neither machine has its own scene yet.
Thalion's flow, timing and colours stay (intro exception of goal 1).
Inner loops and what the hardware forces (Falcon blitter or ST CPU for
fetch and bring, the STE's low base byte) may differ.

| Program | Falcon | ST | State |
|---|---|---|---|
| Intro | every scene in the target format, nothing converted live (7.8, T63; 7.8b, T66): own zoom, own stars in the logo phase, the clouds and the menu's text by blits straight into the target, the picture held at the three format changes | the same plan (docs/05c "The intro without live conversion"), the same hooks and names where they exist (docs/05c "Target screens"); the ST builds it after the Falcon | same plan; the ST follows |
| Fantasy intro | Thalion draws into Amiga buffers, we convert every frame (`Zeilen_umsetzen`) and stamp the fairy in the VBL | no Amiga screen (`workbase` a dummy), graphics in ST format at build, fairy preshifted at start, hooks at `plot_jmptab` and `Blitter_wait`, own `make_magic`/`make_funkel2` (E41, `fantasy_st/`) | **differs**: the Falcon follows `fantasy_st/` (plan before building) |
| Extro | target format, 5 planes, 256 lines | none yet | the ST takes the Falcon's method when it builds one |

Both take Thalion's data from `Amberfiles/` at build time (7.1).

### 7.8b The intro without live conversion (E30, 2026-10-25, test T66)

The ST's inventory (docs/05c, "The intro without live conversion") named
the three scenes 7.8 left converted: the logo phase, LYRAMION with the
clouds, the menu. Now each has its table (`intro/INTRO_SUP.S`), and the
VBL converts nothing in the whole intro; under `AMIGA_MESSEN` the
measurement counts the fallback ("Converted (fallback): pictures, bands",
`Anz_umgesetzt`, `Anz_gerollt`), expected 0.

| Scene | Thalion's screens | Our table | Writers into the target |
|---|---|---|---|
| Logo phase, $190-$3C0 | 6:$C0, +40000; 320 x 200 x 5 | `Screens_logo` from `$1E0` (`Logo_begin`, before the first copper list) | clear `$21E` (`Logo_clear`); stage blits `$13D0` ($F0 way); zoom loop clear `$137E` (`Zoom_loeschen`, planes 0-3); stars in Thalion's VBL `$2646` (`Logo_stars`, plane 4 of the shown target); PRESENTS wipe `$310` (`Presents_row`) |
| LYRAMION, clouds, $D00-$F4E | 6:$C0, +40960; 320 x 256 x 4 | `Screens_clouds` from `$D00` (`Clouds_begin`) | fill `$DA2` (`Clouds_fill`); after a click the picture `$D74` (`Clouds_background`); columns of the menu picture `$1270` (`Clouds_column`, Falcon blitter); clouds `$4E2A` ($CA way); text `$29F4` (any minterm) |
| Menu, from $F4E | 6:$C8C0, 6:$C0; 320 x 256 x 5 | `Screens_menu` from `$FB2` (`Menu_begin`) | entries `$FE6-$102C` (CPU, brought at `$1030`, `Menu_texts`); highlight `$29F4` (blits) |

**Thalion's scratch screen.** Before each logo zoom Thalion computes the
stages ($14E6): it clears the hidden screen as 4 planes of 160 bytes,
zooms the logo into it and reads it back ($1560). `Logo_stages` hands it
a scratch screen of its own (`Logo_scratch`), so the hidden screen stays
a 5-plane target.

**The stars of the logo phase.** Thalion's VBL clears plane 4 of the shown
screen and sets 150 stars ($29B2, $1AF2). `Logo_stars` walks Thalion's
tracks the same way (Thalion's pointers at 5:$2C advance as there) and sets
the stars into plane 4 of the shown target; it clears only the words it
set on that screen last time. `Ebene4_nachfuehren`, which copied plane 4
every VBL (T25), is gone, and with it `OHNE_STERNE`.

**Format changes: the picture is held.** Three times Thalion changes the
screens' format with the CPU, and the next scene's table comes only
later: logo -> space ($3C0-$4F4: copy, 5 -> 4 planes, the star list from
plane 0), any scene -> clouds ($D00), clouds -> menu ($F4E-$FB2: 4 -> 5
planes, copy). `Display_hold` (`AMIGA_RAHMEN.S`) copies the picture shown
into the hidden Falcon screen, shows it from there and removes the table
(Thalion's buffers hold everything again); until a copper list can be
shown directly, nothing is converted. In the logo -> space change the
stars live only in the target, so `Logo_end` first fetches all lines of
the shown screen. The fourth hold is at the meteor scene ($AD4,
`Meteor_anfang`): its table (200 lines) comes before Thalion writes the
200-line window in $289A; a VBL between them saw the old 236-line window
against the new table and converted one picture and one band (Hatari
pre-check, 2026-10-27). With the hold the fallback count is 0.

**Blits straight into the target** (`Bl_ziel_waehlen`, `AMIGA_ZIEL.S`):
besides `$D8` (extro) now `$CA` with C = D (`Bl_ziel_ca`, the clouds),
`$F0` (`Bl_ziel_f0`, the logo stages) and any other minterm with C = D or
without C (`Bl_ziel_allg`, the text: `$FA`, `$0A`). A channel touches the
screens by its whole range now, not by its start: Thalion's clouds start
a word left of the line, at line 0 before the screen or in the screen
before. When that first word only gives D = C (`$CA`, AFWM < 1 << ASH,
`Bl_erstes_wort`), the way starts with the second word.

**The mouse pointer** is drawn into the picture shown (`Basis_jetzt`),
in the menu the target. Before anyone writes or reads a target the
pointer goes (`Bl_umlenken` with the VBL held off, `Schirme_wechseln`,
`Display_hold`); the VBL draws it again.

### 7.9 Notausgang (Nutzer, OK 2026-10-09)

Nach dem Muster der Engine (`MAIN.S`, Erkenntnis 272, T1):
`amiga/AMIGA_NOTAUS.S` hängt in `start` (Fantasy-Intro, Intro, Extro)
gleich nach `Super` `etv_term` ($408) auf `Notausgang`. TOS ruft den
Vektor in `Pterm`, auch nach Bomben. Der Notausgang sperrt die Interrupts,
gibt dem VBL seinen alten Vektor zurück (gegen einen Absturz im eigenen
VBL), geht auf Stufe 3, ruft den Abbau des Programms
(`NOTAUS_ABRAEUMEN`: `Amiga_abraeumen`, im Fantasy-Intro `Fee_notabbau`),
schreibt den alten Vektor zurück und springt hinein.
- Der Abbau ist wiederholbar: Merker `Ab_modus`, `Ab_maus`, `Ab_vbl`
  (`amiga_notaus_bss.i`), gesetzt beim Einrichten, gelöscht beim
  Zurückstellen; `Mess_stoppen` ebenso (`Mess_laeuft`). Nach einem
  geordneten Ende ruft `Pterm` den Notausgang, und er tut nichts mehr.
- Im Notausgang kein GEMDOS (`Im_notausgang`): der Textcursor bleibt aus,
  keine Messdatei. XBIOS (`Setscreen`, `Vsync`, `VsetMode`) bleibt; das ist
  auf dem Falcon nur mittelbar belegt (T1 der Engine).
- Prüfschalter `ABSTURZTEST`: nach 250 VBL ein `illegal` aus dem
  Hauptablauf (Intro, Extro: in `K2_trap`, nur auf Stufe 3 oder darunter;
  Fantasy-Intro: in der Bildschleife). Fassungen `FEEABST.TOS`,
  `INTRABST.TOS`, `EXTRABST.TOS`, einzeln gebaut, nicht in
  `build_falcon.sh` (Aufruf: `sh tools/amiga_bauen.sh intro INTRABST
  "-DABSTURZTEST=1"`, beim Fantasy-Intro der Aufruf aus
  `fantasy_bauen.sh` mit `-DABSTURZTEST=1`). Erwartet: vier Bomben, dann
  der Desktop mit Modus, Farben und Maus.
- **Abbau schon im Absturz** (2026-10-10, nach T16 unter EmuTOS):
  EmuTOS zeigt nach einem Absturz einen Text und wartet auf eine Taste,
  bevor es `Pterm` ruft. Bis dahin liefen unser VBL, unser Modus und unsere
  Farben weiter (Text in Lila, Animation lief, keine Reaktion).
  `Notausgang_einhaengen` hängt sich darum auch vor die Absturzvektoren
  2–8 (`VEK_ABSTURZ`, `ABSTURZ_VEKTOREN`; Line-A/F bleiben bei TOS). Der
  Halter (`Absturz`) baut ab wie der Notausgang (`Notabbau`), gibt die
  Vektoren zurück und springt mit unveränderten Registern, Stufe und
  Ausnahmerahmen in den Halter von TOS. TOS 4.04 malt die Bomben dann auf
  den Desktop, `$380` bekommt seine Angaben wie bisher (`BOMBEN.TOS`).
  Merker `Ab_absturz`; nach einem geordneten Ende gibt der Notausgang die
  Vektoren zurück.
- Nicht abgedeckt: ein Absturz bei gesperrten Interrupts, der nie bis
  `Pterm` kommt.

### 7.10 ST-Bestandsaufnahme je Szene (2026-10-10, S1–S5 beschlossen)

Auftrag des Nutzers (Inventur 2026-10-09): je Szene Ebenen, Farben, was die
Farbreduktion schafft, was vorberechnet werden muss; die ST-Sitzung liest
gegen (gegengelesen 2026-10-10, ihre Korrekturen sind eingearbeitet). Gemessen mit `reduziere`/`fehler` aus `tools/farbreduktion.py`
(docs/12) an den Bildern aus den Hunks (Skript und Vergleichsbilder nur im
Scratchpad). Was nicht gemessen ist, steht als Schätzung oder Annahme da.

**Rahmen auf dem ST** (docs/12, Entscheidungen E4, E5, E13):
- 320 × 200, 4 Ebenen wortweise verschränkt (`ZIEL_EBENEN` 4, `ZIEL_ZEILE`
  160, `ZIEL_WORT` 8), 16 Farbregister (ST 3 Bit je Kanal, STE 4 Bit).
  Thalions Szenen haben 200, 236 oder 256 Zeilen.
- 68000 mit 8 MHz, 160 000 Takte je VBL. Ausgelegt wird auf den einfachen
  ST **ohne** Blitter (E13); Mega ST, STE und Mega STE haben einen, 16 MHz
  und Cache sind Bonus. Der Atari-Blitter kennt Quelle, Ziel und
  Halbtonmuster mit 16 Verknüpfungen von S und D (Amiga: drei Quellen);
  D = C ? B : A braucht also zwei Durchgänge.
- Farbwechsel im Bild nur über Timer B (Copper-Ersatz). Den gibt es bisher
  nur in der Bibliothek von `ENGINE.TOS` (`RASTER.S` der 2D-Sitzung,
  ST-Teil `St_raster_vbl`/`St_raster_int` in `ST_LIB.S`); in `INTRO.TOS`,
  `EXTRO.TOS` und `FANTASY.TOS` ist er nicht gebunden. Wer ihn braucht,
  baut ihn in die Amiga-Schicht (`AMIGA_RAHMEN.S`, Vorlage
  `St_raster_int` samt Zeilenversatz). Jede Szene mit **einer** Palette
  spart das.
- Für Vor- und Abspann erlaubt (Nutzer, 2026-10-04): eigene Routinen an den
  Engstellen, Grafik im ST-Format, Vorberechnung. Ablauf, Texte, Farben und
  Takt bleiben Thalions, das Startmenü bleibt Thalions Code.
- Musik: Für Intro und Extro ist keine YM-Fassung bekannt (6), auf dem ST
  also stumm.

**Grundsatz aus 7.7:** Eine Szene mit **4 Ebenen** passt ebenenweise auf
den ST: `Amiga_blit` kann mit dem Zielformat (7.8) gleich ins ST-Format
schreiben, Thalions Code bleibt. Eine Szene mit **5 Ebenen** nicht: Die
Reduktion 32 → 16 braucht den ganzen Punkt, Thalion schreibt ebenenweise.
Dort braucht der ST eine Umsetzung über die Tabelle (`Tabelle[n]`, docs/12)
oder eigene Routinen und vorberechnete Daten.

**Messung: Farben je Bild und Reduktion auf 16** (Anteil der Punkte, die
sich um 2 Stufen oder mehr verschieben, und die schlimmste Akzentfarbe;
Art `palette` / `wurzel` wie in docs/12):

| Bild | Format | benutzte Farben | STE `palette` | STE `wurzel` | ST `palette` | ST `wurzel` |
|---|---|---|---|---|---|---|
| Extro 0 | 160 × 128 × 5 | 32 | 31,6 % / 2,2 | 24,2 % / 3,0 | 37,6 % / 3,0 | 30,5 % / 3,7 |
| Extro 1 | 272 × 189 × 5 | 32 | 24,2 % / 2,4 | 16,7 % / 3,2 | 52,8 % / 3,4 | 47,5 % / 3,2 |
| Extro 2 | 208 × 175 × 5 | 32 | 21,3 % / 3,2 | 14,9 % / 3,0 | 50,6 % / 3,4 | 12,6 % / 3,0 |
| Extro 3 | 176 × 189 × 5 | 32 | 10,8 % / 2,2 | 16,7 % / 3,0 | 36,6 % / 2,9 | 26,5 % / 3,1 |
| Extro 4 (Schluss) | 320 × 256 × 5 | 26 | 0,0 % / 1,7 | 0,0 % / 1,7 | 1,9 % / 2,0 | 1,9 % / 2,0 |
| Fantasy, Hintergrund oben (0–133) | 320 × 134 × 5 | 20 | 14,8 % / 3,0 | 0,0 % / 1,7 | 23,2 % / 3,7 | 7,1 % / 2,5 |
| Fantasy, Hintergrund unten (134–255) | 320 × 122 × 5 | 13 | 72,5 % / 2,4 | 0,0 % / 0,0 | 72,7 % / 2,7 | 0,0 % / 1,6 |
| Fantasy, Hintergrund ganz, **eine** Palette | 320 × 256 × 5 | 20 | 9,3 % / 3,0 | 0,0 % / 1,7 | 16,3 % / 3,2 | 6,6 % / 2,5 |
| Intro, Menühintergrund (2:$1954, Pal. 1:$180) | 320 × 256 × **4** | 15 | 0 | 0 | 0,0 % / 1,8 | 0,0 % / 1,5 |
| Intro, Twinlake (2:$0, Pal. 1:$120) | 320 × 180 × **4** | 16 | 0 | 0 | 0,0 % / 1,2 | 0,0 % / 1,2 |

Lesart:
- Die **Extro-Bilder** nutzen alle 32 Farben. Auf dem STE bleiben die
  Akzente erhalten (höchstens gut 3 Stufen daneben), 15–25 % der Punkte
  verschieben sich sichtbar (`wurzel`). Auf dem ST kommt das Runden auf
  3 Bit dazu: bis knapp die Hälfte der Punkte, das Bild wird gelb- bzw.
  olivstichig. Das ist so schlecht wie bei den Karten in docs/12, nicht
  schlechter.
- Der **Fantasy-Hintergrund** nutzt nur 20 Farben, und oben und unten
  zusammen auch nur diese 20: Die sechs Farben, die die Copperliste ab
  Zeile 134 tauscht (20, 21, 22, 29, 30, 31), braucht der Hintergrund unten
  nicht, nur Fee, Funken und Sterne. Mit `wurzel` reicht **eine**
  16er-Palette für den Hintergrund (STE 0 %). Nicht gemessen sind die
  bewegten Teile: Fee (16 Farben, 16–31), Funken (`plot00`…`plot31`, alle
  32), Sterne und Schriftzug. Sie teilen sich die 16 Register mit dem
  Hintergrund. Weil Timer B in der Amiga-Schicht fehlt (oben), ist die
  eine Palette ein echter Gewinn.
- **Menü und Twinlake** haben schon 16 Farben. Auf dem ST bleibt nur das
  Runden auf 3 Bit (Wolken werden grünstichig, wie in docs/12).

**Je Szene**

| Szene | Amiga | Je Bild | ST: Farben | ST: Weg | Vorberechnen |
|---|---|---|---|---|---|
| Fantasy-Intro | 320 × 256 × 5, zwei Paletten (Wechsel Zeile 134), 3 VBL je Bild | Schriftzug (Blit `$E2`), Sterne (Blit `$CA` mit Maske), Funken (CPU, Amiga-Format fest eingebaut), Fee (8 Sprites, CPU bei uns) | 16 aus Hintergrund + Fee + Funken; eine Palette ohne Timer B möglich (Hintergrund gemessen) | 5 Ebenen: eigene Routinen im ST-Format für Funken, Sterne, Schriftzug, Fee; Thalions Ablauf (`FAIRY.S`) bleibt | Hintergrund, Schriftzug, Sternbilder, Fee im ST-Format mit Tabelle, beim Bau |
| Intro: Logo, „PRESENTS“ | 320 × 200 × 5: Logo 4 Ebenen, Sterne in Ebene 4 | 150 Sterne (CPU, `bset`), Zoom (unser `INTRO_ZOOM.S`) | Logo 16 + Sternfarbe: Logo auf 15 reduzieren | Logo und Zoom 4 Ebenen: Zielformat; Sterne eigene Routine | nein (höchstens die Zoomquelle) |
| Intro: Raumszene | 320 × 236 × **4**; die Copperliste kann ab Zeile $F4 Farbe 1 tauschen (4.4) | Schirm löschen, Sternfeld, Planeten-Zoom, Stadtbilder, Text | 16, nur Runden | Zielformat; Zoom eigene Routine; 236 → 200 Zeilen | nein |
| Intro: Twinlake | 320 × 180 × **4**, Fenster wandert waagerecht (DIW) | Animation: Lauflängen, EOR in Ebene 0–3 (CPU, Amiga-Format) | 16, nur Runden | Zielformat für Blits; EOR-Routine für ST-Schritte (K3) oder Animation vorab wandeln; Fenster als Rand löschen | evtl. Animation (Hunk 3, 261 KB) |
| Intro: Meteor | 320 × 236 bzw. 200 × **4** (7.7) | Stadtbild 128 Zeilen kopieren (CPU) | 16, nur Runden | Zielformat; Kopie über K3 | nein |
| Intro: Startmenü | 320 × 256 × 5: Hintergrund 4 Ebenen, Text Ebene 4 (Farben 16–31 weiß), Hervorheben 30/31 | Menü zeichnet mit der CPU in den gezeigten Schirm (Thalions Code, bleibt) | 15 + Weiß + Hervorhebung: Hintergrund auf 14 reduzieren | Umsetzen wie vor dem Zielformat (Amiga-Schirm → ST über die Tabelle), selten, Tempo egal; passt in 200 Zeilen | nein |
| Extro | 320 × 256 × 5, Bilder mit eigener Palette (32 Farben), Textfarben = aufgehellte Bildfarben (`$2B2E`) | 5 Blits D = C ? B : A über den ganzen Schirm, Maske eine Zeile hoch | 16 je Bild (gemessen oben); Textfarben aus denselben 16 neu wählen | eigene Routine: Text über Hintergrund im ST-Format; 256 → 200 Zeilen mittig (`ANZEIGE_MITTIG`) | je Bild beim Bau: Bild A im ST-Format mit Tabelle und das aufgehellte Bild B auf dieselben 16 Register |

**Tempo (Schätzung, nicht gemessen).** Der 68000 mit 8 MHz ist für diese
Arbeit grob drei- bis viermal langsamer als der Falcon. Der Falcon schafft
heute im Fantasy-Intro Thalions Takt (18 Bilder je Sekunde außerhalb des
Logo-Aufbaus), das Intro erst mit eigenem Zoom.
- Extro: Text über Hintergrund mit der CPU. Je 16 Punkte die Maske bilden,
  je Ebene A AND NOT Maske, B AND Maske, odern, schreiben: rund 36 Takte je
  Ebene, etwa 170 je Gruppe (ST-Sitzung). 4000 Gruppen über den ganzen
  Schirm geben 0,6–0,7 Mio. Takte, **eher 4 als 3 VBL je Bild**. Der
  entscheidende Hebel: nur die Zeilen mit Text mischen. Liegt ein Bild
  ohne Text zum Zurücklegen bereit, reicht beim Weiterrollen das Neumischen
  der Textzeilen.
- Fantasy-Intro, Fee: ohne Hardwaresprites braucht der ST vorgeschobene
  Masken in 16 Lagen (Speicher statt Schieben je Bild).
- Fantasy-Intro und Intro: ohne eigene Routinen im ST-Format deutlich unter
  Thalions Takt. Wie weit, misst erst Hatari im ST-Modus (E11: vorher
  fragen).

**Speicher:** Vorberechnetes im ST-Format ist kleiner als das Original
(4 statt 5 Ebenen, 200 statt 256 Zeilen): Fantasy-Hintergrund 32 000 Byte,
Extro-Bilder rund 100 KB, Twinlake-Animation höchstens so groß wie Hunk 3.
Bei 4 MB (Vorgabe für den ST) kein Engpass.

**Beschluss (Nutzer, 2026-10-10): S1 bis S5 angenommen.**
- **S1, Zeilen:** 256 → 200. Fantasy-Intro und Extro mittig beschneiden
  (Extro wie heute an VGA); Menü und Intro oben bündig (passen). Die Fee
  fliegt zwischen y 138 und 194, bleibt also sichtbar.
- **S2, Reduktion:** Art `wurzel` für die Bilder mit 32 Farben, gerechnet
  beim Bau. **Register 0 nur für Farbe 0**, keine andere Farbe darauf
  (wie `ST_LIB.S`): Masken aus dem ODER der Ebenen (Fee, Sterne, Blits mit
  Maske) bleiben nur so richtig. Blenden wie in docs/12: Die Tabelle
  bleibt, jedes Register bekommt das Mittel der geblendeten Farben seiner
  Gruppe (`st_blende`); die Tabelle gehört zur Soll-Palette (Erkenntnis
  240). Ein Überblenden von Bild A nach Bild B mit je eigener Tabelle geht
  darum nicht direkt, nur über Schwarz. Das Extro blendet ohnehin über
  Schwarz (5.3), passt also. Auf dem einfachen ST haben Blenden nur
  8 Stufen; ein Satz STE-Werte dient beiden (der ST lässt Bit 3 fallen).
- **S3, Vorberechnen beim Bau** (`tools/amiga_programm.py`, in `build/`,
  nie ins Repository): Fantasy-Hintergrund, Schriftzug, Sternbilder, Fee;
  Extro-Bilder samt aufgehelltem Bild B. Nicht vorberechnet werden die
  Szenen mit 4 Ebenen.
- **S4, Reihenfolge:** zuerst Intro (vier von sechs Szenen mit 4 Ebenen,
  dort trägt das Zielformat), dann Extro (eine eigene Routine), dann
  Fantasy-Intro (die meisten eigenen Routinen).
- **S5, Messen vor dem Bauen:** je Programm ein erster ST-Bau ohne
  Tempoarbeit, dann Hatari im ST-Modus (nach Rückfrage, E11) oder der
  Mega STE des Nutzers.

## 8. Nächste Schritte

1. F1/F2 auf dem Falcon (RGB): mit HOG fehlerfrei (7.6, 2026-10-02).
   Logo-Aufbau langsam (8–9 VBL je Bild), vorerst hingenommen. Der Falcon
   lief mit 60 Hz, seit 2026-10-03 stellen wir PAL ein (Test, auch der 256
   Zeilen). Offen: Grafikmüll oben, seltener als vor dem Puffer. `AMIGA_RAHMEN.S` blittet seit 2026-10-02 ebenfalls mit
   HOG (Intro, Extro); `INTRDIAG.TOS` misst das Intro auf dem Falcon
   (endet nach 60 s, zurück zum Desktop). Zu prüfen: der Mauszeiger im
   Intromenü (`Zeiger_zeichnen` liest den Falcon-Schirm, 030-Datencache).
2. Tempo (7.6, Beschluss 2026-10-02): auf dem Falcon `FEEMESSB.TOS`
   gegen `FEEMESSC.TOS`; `FEEPRUEF.TOS`, `INTROPRF.TOS`, `EXTROPRF.TOS`
   auf Abweichungen; `FANTASY.TOS`, `INTRO.TOS`, `EXTRO.TOS` ansehen,
   `INTROMES.TOS`/`EXTROMES.TOS` messen. Danach: Umsetzen mit der CPU,
   falls bestätigt; `$FC`/`$FE`; `$D8` und `$F0` in Langworten.
3. Intro: I1–I4 getestet. Unser Zoom (K3, 7.6, 2026-10-04) im Emulator
   belegt, auf dem Falcon flüssig (2026-10-04). Die Streifen kommen vom
   Schreiben in gezeigte Zeilen (`STRAHL`, 7.6); die Bestandsaufnahme für
   ein Schirmformat ohne Umsetzen steht in 7.7, die Entscheidung steht
   aus. Offen: Musik, der weiße Blitz vor dem Zoom.
4. Extro: kartiert (E0), `EXTRO.TOS` getestet (E1); E2 getestet mit
   der Prüffassung `ENDETEST=1`. Schirme im Zielformat gebaut (7.8),
   auf dem Falcon getestet (T12, 2026-10-09): läuft durch, leichtes
   Ruckeln. Offen: Takt oder Last (`EXTRDIAG`), Musik.
5. Musik: die YM-Stücke prüfen, zum Schluss einbinden (nur wenn sie
   daneben liegen).
6. `main` eingemischt (2026-10-08, Vorspulen auf c1fdf4b): CLAUDE.md
   von `main`, `a56` vorhanden; docs/15 Abschnitte 9 und 11 korrigiert
   (Rollen, K3, `AMIGA_RAHMEN` nur Intro und Extro), wie mit der
   2D-Sitzung abgesprochen. Auf `main` übersetzt `einheiten_verbinden.py`
   die Bibliothek vor dem `a56`-Schritt; in einem leeren `build/` fehlte
   dann `musik_dsp.dsp`. Von der Musik-Sitzung behoben (`main` d4e4144),
   ebenfalls eingemischt.
7. Notausgang (7.9): gebaut; Test T16 (`FEEABST`, `INTRABST`,
   `EXTRABST` auf dem Falcon, 2026-10-09/10) **fehlgeschlagen**: Alle
   drei bleiben nach den Bomben stehen, nur ein Reset hilft. `FEEABST`
   zeigt die Bomben als schwarzen Kasten in unserem Schirm, der `illegal`
   kam also an. Die Engine (`T01ABST`) kehrt zurück. Den CACR ändern die
   drei Programme nicht, `Cache030_zurueck` kommt als Ursache nicht in
   Frage.
   **Ursache (Hatari, 2026-10-10, `FEEABST`):** TOS wartet nach den
   Bomben, noch vor `etv_term`, in einer Schleife auf `_frclock` (`$466`,
   ROM `$E00D60`). Unsere VBLs ersetzen `$70` ganz, der VBL von TOS lief
   nicht mehr, `_frclock` stand. Die Engine hängt sich in die
   VBL-Warteschlange und hat das Problem nicht. **Behoben:** `Fee_vbl` und
   `Amiga_vbl` zählen `_frclock` selbst (`FRCLOCK`). In Hatari kehren
   danach `FEEABST`, `INTRABST` und `EXTRABST` zum Desktop zurück (`$70`
   und `$408` wieder bei TOS). Test T16 auf dem Falcon steht aus.
   **Unter EmuTOS** (Hatari des Nutzers, 2026-10-10) hingen alle drei
   weiter: EmuTOS wartet vor `Pterm` auf eine Taste. Behoben mit dem Abbau
   schon im Absturz (7.9).

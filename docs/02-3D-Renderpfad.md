# Ambermoons 3D-Ansicht: Schnittstelle zur Bibliothek und Renderpfad

**Teil A** (Stand 2026-09-28) hält fest, was die nicht freigegebene
Bibliothek für den 3D-Teil tut, gelesen in `AM2_CPU` mit
`tools/am2cpu_lesen.py` (Erkenntnis 194). Das sind **Verträge**. Die reinen
Speicherroutinen (Rasterer) nehmen wir seit 2026-09-28 als Thalions
übersetzten Code, beim Bau herausgezogen (A7); was am Schirm hängt, schreiben
wir für Falcon und ST selbst (`src/HULL/D3_SUP.S`).
**Teil B** ist die Aufwandsrechnung aus der Nachbauzeit; ihre Messungen
gelten weiter, ihre Annahmen über das Pufferformat nicht mehr.

Adressen in der Form `Hunk:Versatz` beziehen sich auf `AM2_CPU` der
deutschen Fassung 1.20.

# Teil A: Die Schnittstelle

## A1. Die Aufteilung

Thalions `MAP/3D_MAP.S` ist eingebunden (Stufe (c)) und rechnet alles, was
keine Hardware braucht: Sichtfeld (`Get_draw_size`), Drehung
(`Rotate_points`), Figuren (`Insert_NPCs`), Flächen (`Get_faces`),
Tiefensortierung (`Quicksort`), waagerechtes Clipping (`Draw_faces`
Durchgang 1), Projektion der Objekte (`make_3dzoom0`), Licht, Kollision,
Bewegung. Die Bibliothek **rastert** nur, in einen Zwischenpuffer von
144×144 Pixeln, und bringt ihn auf den Schirm.

Ablauf eines Bildes (`M3_DisUpd`):

```
Claim_pointer         MOVEP_ptr, zoom_screen(2), Wall_ptrs, Labdata_ptr
[Draw_floor]          nur mit CPU_68020_plus, setzt cls_top/cls_bottom
[Draw_ceiling]
Himmel und Boden      Thalion füllt die übrigen Zeilen selbst (Sky_colour,
                      Floor_colour, je 9 Langworte = 72 Byte je Zeile)
[Draw_horizon]        -> Insert_horizon
Draw_dungeon          -> put_dpoly je Wand, draw_zoomshape je Objekt
Show_MOVEP_screen     Puffer auf den Schirm, Ebenen 0-3
Clear_1plane_block    Ebene 4 im Himmelsstreifen löschen
Draw_stars            Get_pixel / Plot_pixel, nur in 3D-Städten
```

## A2. Das Pufferformat legt Thalion fest, nicht die Bibliothek

Der Puffer (`MOVEP_handle`, `MOVEP_ptr`) ist 144 Zeilen zu **72 Byte**:
**je 8 Pixel 4 Byte, ein Byte je Ebene** (Ebene 0 zuerst), also 16
Farben. Thalion nennt es MOVEP-Format, weil `movep.l` genau diese vier Byte
auf die Ebenen eines Atari-Schirms verteilt.

Thalions Code schreibt selbst in diesem Format, darum steht es fest:

- Himmel und Boden: `Sky_colour`/`Floor_colour` sind Langworte mit $00/$FF
  je Ebene (`M3_ModInit`).
- `Load_3D_map_data` schiebt den Horizont mit `movep.l` in dieses Format
  vor (16 Verschiebungen, je Zeile 144 Byte: 72 und dieselben 72 noch
  einmal, zum Umlaufen).
- `Put_unmasked_MOVEP_block`/`Put_masked_MOVEP_block` malen die Overlays
  in die Wände.

Auch die Grafik in den Spieldateien liegt so: `Wall3D` (128×80, 64 Byte je
Zeile, 5120 Byte), `Object3D` (Breite/2 Byte je Zeile), `Overlay3D`.

**Die Ebene 4 fasst der 3D-Teil nicht an.** 3D-Wände haben 16 Farben;
`Set_D3_light_level` blendet nur `Current_pal` 0–15.

## A3. Zwei Weichen, die Thalion schon eingebaut hat

| Name | Ort | Wert im Original | Wirkung |
|---|---|---|---|
| `Blitter_or_CPU` | 6:`$C0` | `$FF` (Datenhunk) | ≠ 0: jede 3D-Routine nimmt die CPU-Fassung; `Load_3D_map_data` lädt `Wall_3D_FAST_file`/`Object_3D_FAST_file` und fordert Fast-RAM an |
| `CPU_68020_plus` | 9:`$9CC0` | zur Laufzeit ermittelt | 0: **keine** texturierten Böden und Decken (`Floor_ceiling_potential` = 0), nur Farbflächen |

**Für uns:** `Blitter_or_CPU` = `$FF` (es gibt keinen Amiga-Blitter),
fest in `D3_SUP.S`. `CPU_68020_plus` setzt `D3_einrichten` beim Start nach
dem Bauschalter `D3_CPU`: 0 = immer 68000-Weg, 1 = nach dem Cookie
`_CPU` (Vorgabe seit 2026-09-29, E3), 2 = immer 020-Weg
(`VASM_EXTRA="-DD3_CPU=0"` legt den 68000-Weg fest). Der 68000-Weg ist
Thalions eigener und läuft auf ST und Falcon. `Draw_floor`/`Draw_ceiling`
braucht erst der 020-Weg (Nutzer, 2026-09-28: erst 68000-verträglich, 020
später, wenn es ruckelt; die Weiche soll sich ziehen lassen).

Jede Bibliotheksroutine unten beginnt mit `tst.b Blitter_or_CPU` und
springt in eine von zwei Fassungen. Gelesen ist jeweils die **CPU-Fassung**;
sie ist reiner Speichercode ohne einen 68020-Befehl.

## A4. Die Routinen

Variablen der Bibliothek (BSS, Hunk 9) und Thalions Variablen, die sie
liest:

| Name | Ort | Herkunft |
|---|---|---|
| `MOVEP_ptr` | 9:`$36D4` | Thalion (3D_MAP.S) |
| `zoom_screen`, `zoom_screen2` | 9:`$E6AC`, `$E6B0` | Bibliothek; Thalion setzt sie auf `Zoomscreen_handle` und `+144*144/2` |
| `cls_top`, `cls_bottom` | 9:`$E6C8`, `$E6CA` | Bibliothek |
| `dpoly_koos3d` | 9:`$E6CC` | Bibliothek, 6 Worte |
| `Floor_X`, `Floor_Z`, `Floor_source_gfx` | 9:`$E6B6`, `$E6BA`, 2:`$BC0` | Bibliothek |
| `cx1`, `cy1`, `cx2`, `cy2` | 9:`$EF2`, `$EF4`, `$EF6`, `$EF8` | Thalion |
| `seethru_flag` | 9:`$EEE` | Thalion (`Get_wall_address`, `shi`) |
| `scrx`, `scry` | 4:`$3D10`, 9:`$EF0` | Thalion |
| `zoom_ptrbuff` | 2:`$0000` | Thalion (`Init_zoom_table`) |

### put_dpoly — eine Wand (11:`$0886`, CPU 0:`$29A6E`)

- **IN:** `dpoly_koos3d` = x1, x2, y1, y2, z1, z2 (Kameraraum, Worte);
  `a0` = Wandtextur (128×80, MOVEP-Format, von `Get_wall_address`);
  `seethru_flag`; Clipping `cx1..cx2`, `cy1..cy2`; `MOVEP_ptr`;
  `zoom_ptrbuff`. Kein Register bleibt garantiert (Thalion sichert
  selbst, `Draw_faces`).
- **Nahebene:** Ist ein z < 0, wird die Kante bei z = 0 abgeschnitten, x
  linear nachgezogen (0:`$29F20`); sind beide < 0, nichts.
- **Projektion:** x' = x·256/(z+256) + `scrx`; y' = `scry` − y·256/(z+256),
  für beide Enden je oben und unten (0:`$29E72`).
- **Kanten:** Oberkante und Unterkante **linear im Bildraum** von der linken
  zur rechten Spalte, 16.16-Festkomma, Start mit ½ (Kantenliste,
  11:`$019E`/`$01B4`). Links auf `cx1`, rechts auf `cx2` geschnitten.
- **Textur waagerecht:** u läuft **affin** (linear im Bildraum) über 128
  Texel; wurde vorn abgeschnitten, beginnt u entsprechend später.
- **Textur senkrecht:** Zoomtabelle `zoom_ptrbuff[Höhe−1]` (Höhe bis 320),
  Schritte in Byte (Vielfache von 64 = eine Texturzeile); oben auf `cy1`
  geschnitten, indem die Schritte übersprungen werden, unten auf `cy2`.
- **Pixel:** Spalte für Spalte: 4 Byte der Textur holen, auf die Bitstelle
  der Zielspalte schieben, mit der Spaltenmaske in alle 4 Ebenenbytes
  einsetzen. Mit `seethru_flag` wird ein Pixel mit Farbe 0 übersprungen.

### draw_zoomshape — ein Objekt (11:`$3978`, CPU 0:`$2A036`)

- **IN:** `d0`/`d1` = Ziel links oben, `d2` = Maske (≠ 0: Farbe 0 ist
  durchsichtig; Thalion übergibt −1), `d4`/`d5` = Quellbreite/-höhe,
  `d6`/`d7` = Zielbreite/-höhe, `a0` = Grafik (MOVEP-Format, Breite/2 Byte
  je Zeile); Clipping `cx1..cy2`; `MOVEP_ptr`.
- **Clipping** an allen vier Seiten, die Quellversätze werden
  mitgerechnet.
- **Verkleinern** (Zielhöhe ≤ Quellhöhe): Spalte für Spalte von rechts
  nach links, Bresenham-Tabellen für Zeilen- und Spaltenschritte, Pixel wie
  bei `put_dpoly`.
- **Vergrößern:** erst waagerecht skaliert nach `zoom_screen` (Zeilen zu 72
  Byte), daraus eine Maske nach `zoom_screen2` (ODER der vier
  Ebenenbytes), dann Zeile für Zeile mit dem senkrechten Schritt
  hineinkopiert, Ränder mit Randmasken.

### Insert_horizon (11:`$0000`, CPU 0:`$29A42`)

- **IN:** `a0` = Quelle (vorgeschobener Horizont, Zeilenabstand 144),
  `a1` = Ziel im Puffer (Zeilenabstand 72). Alle Register bleiben.
- Kopiert **20 Zeilen** (`Horizon_height`) zu 72 Byte, ohne Maske.

### Show_MOVEP_screen (0:`$21B06`)

- **IN:** `d0`/`d1` = Schirmposition (x auf 16 Pixel), `d6` = Breite in
  16-Pixel-Stücken (9), `d7` = Zeilen (144), `a0` = Puffer. Alle Register
  bleiben.
- Je 16 Pixel: Byte 0–3 → Ebenen 0–3, linke Hälfte; Byte 4–7 → Ebenen
  0–3, rechte Hälfte. **Ebene 4 bleibt**, wie sie ist.
- **Bei uns** (`D3_SUP.S`) kommen auf dem Falcon die Bankebenen 5–7 dazu:
  die Farbbank der Bildzeile, wo der Punkt nicht 0 ist (0 bleibt 0, wie
  `Put_unmasked_block`).

### Clear_1plane_block (0:`$21592`)

- **IN:** `d0`/`d1` = Position, `d5` = Ebene, `d6` = Breite in 16-Pixel-
  Stücken, `d7` = Zeilen. Löscht diese eine Ebene im Rechteck.
- In `M3_DisUpd` direkt nach `Show_MOVEP_screen`, mit dessen `d0`/`d1`/`d6`,
  `d5` = 4 und `d7` = 72 − `Horizon_height`: Sie nimmt die Sterne des
  vorigen Bildes aus Ebene 4 (sie haben die Farben 28–31).
- **Bei uns** fallen dabei die Bankbits der Punkte, die so zu 0 werden. Auf
  dem ST (vier Ebenen) gibt es Ebene 4 nicht; die Routine tut dann nichts.

### Die übrigen

- **`Copy_screen`** (0:`$21456`): Blitterkopie des sichtbaren Schirms in den
  Arbeitsschirm, damit nach dem Umschalten beide gleich sind. **Bei uns
  endgültig leer**: Wir haben einen Arbeitspuffer, und der bleibt vollständig.
- **`Fade_colour`** (0:`$23332`): `d0` = Farbe `$0RGB`, `d1` = Zielfarbe;
  jeder Anteil rückt um eine Stufe auf das Ziel zu, Ergebnis in `d0`. `d2`/`d3`
  bleiben. Thalions Code, beim Bau herausgezogen (A7).
- **`File_allocate`** (0:`$24050`): `d0` = Größe, `d1` = Dateiart, `d2` =
  Eintrag; fordert Speicher an und schreibt Dateiart und Eintrag in den
  Blockkopf. **`Reallocate_memory`** (0:`$23DCE`): `d0` = Eintrag, `d1` =
  Dateiart → `d0` = Handle eines noch vorhandenen Blocks, sonst 0.
  **`Invalidate_memory`** (0:`$23D52`): `d0` = Handle; der Block gleicht
  seiner Datei nicht mehr (Overlays aufgemalt) und darf nicht
  wiederverwendet werden. Der Speicherverwalter des Originals ist ein
  **Zwischenspeicher** für Dateien. Bei uns lädt `Load_subfile` jedes Mal
  neu; `Reallocate_memory` darf also 0 antworten (dann baut Thalion die
  Zoomtabelle neu), `Invalidate_memory` bleibt leer.
- **`Draw_floor`** (0:`$2A774`), **`Draw_ceiling`** (0:`$2A70A`): noch nicht
  gelesen; erst mit `CPU_68020_plus` nötig. Eingaben laut Thalion:
  `Floor_X`, `Floor_Z`, `Floor_source_gfx` (256×256 Byte, Farbe·8, aus
  `Convert_floor_graphics`), `MPB_ptr` (`Create_MPB_table`); Ausgabe
  `cls_top`/`cls_bottom`.

## A5. Tabellen

| Name | Ort | Inhalt |
|---|---|---|
| `Sinus_table` | 4:`$65C4` | **1024 Worte**, sin·2¹⁴ (`slang` = 1024; Kosinus bei +256) |
| `Race_heights` | 4:`$76A8` | Worte, Größe je Rasse in cm (180, 190, 150, 120, 195, 160, 190, 175, 180 …) |

Beide holt `am2cpu_auszug.py` beim Bau.

## A6. Die Dateien

Mehrteilige Dateien wählt die Bibliothek **nach `Map_nr`** (9:`$3702`;
0:`$29846`), nicht nach dem Eintrag: Karte 1–256 → Teil 1, 257–299 → 2,
300–399 → 3, ab 400 → 2. Das gilt für die neun Dateiarten in der Liste
4:`$799C`: `Map_data`, `Map_text`, `Icon_gfx`, `Wall_3D_CHIP`,
`Wall_3D_FAST`, `Object_3D_CHIP`, `Object_3D_FAST`, `Overlay_3D`,
`Lab_data`. `2Wall3D`/`3Wall3D` und `2Object3D`/`3Object3D` unterscheiden
sich in einigen Einträgen; die Wahl ist also nicht gleichgültig.
Einteilig: `Lab_background.amb`, `Floors.amb`.

`Load_batch_of_subfiles` und `Load_batch_of_unique_subfiles` (0:`$25208`,
`$25354`) geben einem Eintrag, der mehrfach in der Liste steht, dasselbe
Handle. **Bit 15 der Eintragsnummer heißt „eigene Kopie“**: das Bit wird
gelöscht, der Eintrag frisch geladen und nie geteilt. So markiert
`Load_3D_map_data` Wände, auf die Overlays kommen.

## A7. Thalions Rasterer, beim Bau herausgezogen (Entscheidung 2026-09-28)

**Entscheidung (Nutzer, 2026-09-28):** Die CPU-Fassungen der Rasterer
werden nicht nach dem Vertrag nachgeschrieben. Wir nehmen Thalions
übersetzten Code aus `AM2_CPU`, **beim Bau** herausgezogen wie die Daten
(`tools/am2cpu_code.py` → `build/am2cpu_code.i`). Der Code kommt nie ins
Repository und wird nie zur Laufzeit gelesen. Der Nutzer wollte den Weg
aufgeschrieben haben, falls er sich als falsch erweist.

### Was herausgezogen wird

| Stück | `AM2_CPU` | Byte | Einsprung |
|---|---|---|---|
| `Fade_colour` | 0:`$23332`–`$2338A` | 88 | `Fade_colour` |
| `Insert_horizon` | 0:`$29A42`–`$29A6C` | 42 | `Insert_horizon` |
| `put_dpoly` samt Nahebene, Projektion, Kanten, Spaltenmasken | 0:`$29A6E`–`$2A036` | 1480 | `put_dpoly` |
| Kantenliste füllen (Schleife und ausgerollt) | 11:`$019E`–`$0886` | 1768 | nur über Relokation |
| `draw_zoomshape` samt Schritttabellen, Randmasken | 0:`$2A036`–`$2A70A` | 1748 | `draw_zoomshape` |

Die internen Variablen (9:`$E278`–`$E938`, 1728 Byte) legt das Werkzeug als
BSS-Block **in derselben Anordnung** an. Der Code liest mehrere davon in
einem Zug (`movem.w` über die projizierten Punkte, `tst.l` über vier
Merkerbytes). Thalions Namen in diesem Bereich (`dpoly_koos3d`,
`zoom_screen(2)`, `cls_top`, `cls_bottom`, `Floor_X`, `Floor_Z`) stehen dort
an ihrer Stelle; die Platzhalter dafür sind weg.

Nicht übernommen wird die Weiche in Hunk 11 (`tst.b Blitter_or_CPU`, sonst
Blitterfassung). Unsere Namen zeigen auf die CPU-Fassungen.
`Blitter_or_CPU` = `$FF` braucht es trotzdem: Die Kantenroutine fragt den
Merker selbst noch einmal ab.

### Warum (Abwägung)

- **Dafür:** Es ist Thalions Code statt eines Nachbaus (Leitziel 1). Die
  Pixel, Rundungen und Eigenheiten sind dieselben, etwa `and.w #-7` statt
  `-8` bei der Zeilenbreite verkleinerter Objekte. Er ist erprobt, und die
  Arbeit ist ein Bruchteil von drei neuen Rasterern.
- **Dagegen:** Das Tempo auf dem ST ist offen: Auf dem Amiga lief die
  CPU-Fassung auf 020-Maschinen, ein A500 nahm den Blitter. Maschinencode
  ist schwer zu pflegen. Die Bibliothek wurde nie freigegeben: Das ist eine
  Rechtsfrage wie bei den Daten, und darum kommt nichts ins Repository.
- **Grauzone zu „keine Abschriften“ (CLAUDE.md):** Die Regel zielt auf
  Stücke Thalions, die in *unsere* Dateien kopiert werden. Hier liegt im
  Repository nur das Werkzeug mit den Fundstellen; der Code entsteht beim
  Bau aus der Originaldatei, wie `am2cpu_daten.i`.

### Was das Werkzeug prüft (jede Prüfung bricht den Bau ab)

1. Jede Relokation hat einen Namen (`NAMEN` in `am2cpu_lesen.py`), eine
   Marke in einem Stück oder liegt im BSS-Block.
2. Kein Sprung und kein PC-relativer Zugriff verlässt sein Stück.
3. Es gibt keine absolute Adresse ohne Relokation (Amiga-Hardware wie
   `$DFF000`).
4. 68000: objdump liest jeden Befehl als 68000 und als 68030 gleich, und kein
   Index ist skaliert. Die 68000-Gegenprobe des Baus sieht in `dc.w` nichts.
5. Jedes Stück endet mit `rts`/`rte`/`jmp`/`bra`, und jede Tabelle ist
   angegeben (sonst steht `.short` im Code).

Gegenprobe 2026-09-28: Jede Prüfung schlug an einem absichtlich falschen
Stück an (Show_MOVEP_screen, Draw_ceiling, Tabelle als Code, zerteiltes
Fade_colour, Blitterfassung von Insert_horizon).

### Woran wir merken, dass es falsch war

- **Es ruckelt auf dem ST** und lässt sich nicht beheben, ohne den Code
  anzufassen. Die Rasterer sind dann der Engpass (messen, bevor man das
  annimmt: `Show_MOVEP_screen` und Thalions Szenenrechnung kosten auch).
- Ein Fehler lässt sich im Maschinencode nicht finden oder nicht beheben.
- Die Rechtslage verbietet es, auch nur beim Bau zu übernehmen.

### Der Rückweg

1. In `engine/engine.s` die Zeile `INCLUDE "am2cpu_code.i"` streichen und in
   `tools/build_common.sh` den Aufruf von `am2cpu_code.py`.
2. Der Linker nennt dann die fehlenden Namen: `put_dpoly`,
   `draw_zoomshape`, `Insert_horizon`, `Fade_colour` und die Variablen des
   BSS-Blocks.
3. Die Routinen nach den Verträgen in A4 selbst schreiben. Die Variablen
   Thalions (`dpoly_koos3d`, `zoom_screen(2)`, `cls_*`, `Floor_X/Z`) neu
   anlegen, eigene Merker frei wählen.
4. Zum Vergleich taugt der Auszug weiter: `build/am2cpu_code.i` zeigt jeden
   Befehl mit objdump-Lesart, `am2cpu_lesen.py dis` die Umgebung. Ein
   Zwischenweg: nur ein Stück ersetzen und aus `STUECKE` nehmen, etwa ein
   schnelleres `put_dpoly` für den ST hinter derselben Schnittstelle.

`D3_SUP.S` (Schirm, Weichen) hängt nicht daran und bleibt.

# Teil B: Aufwandsrechnung aus der Nachbauzeit

> **Stand 2026-09-28:** Die Messungen gelten weiter. Überholt ist die
> Annahme, der Zeichner arbeite chunky und erst `Show_MOVEP_screen` wandle
> nach planar: Thalions Puffer ist bereits planar je 8 Pixel (A2), die
> Wandtexturen ebenso. Ein eigener Chunky-Zwischenpuffer wäre nur hinter
> der Schnittstelle möglich und müsste Thalions Einträge in den Puffer
> (Himmel, Horizont) mitnehmen.

Ausgewertet aus `ambermoon-main-asm/src/MAP/3D_MAP.S` (3440 Zeilen) und den
Konstanten in `GAME_OFF.S`. Ziel: abschätzen, was ein Bild auf einem
Standard-Falcon kostet, **bevor** Code entsteht.

Ausgewertet aus `ambermoon-main-asm/src/MAP/3D_MAP.S` (3440 Zeilen) und den
Konstanten in `GAME_OFF.S`. Ziel: abschätzen, was ein Bild auf einem
Standard-Falcon kostet, **bevor** Code entsteht.

### 1. Es ist kein Raycaster

Das ist die wichtigste Korrektur an meiner bisherigen Planung. Ambermoon
projiziert texturierte Wandpolygone und sortiert sie nach Tiefe — ein
Maleralgorithmus, kein spaltenweises Strahlverfahren.

Der Ablauf in `Draw_dungeon`:

```
Get_draw_size     Sichttrapez aus vier gedrehten Punkten
Rotate_points     Punktgitter um die Y-Achse drehen
Insert_NPCs       Figuren als Objekte einreihen
Get_faces         sichtbare Flächen sammeln
Quicksort         nach Tiefe sortieren
Draw_faces        Durchgang 1: Clipping prüfen
                  Durchgang 2: put_dpoly je Wand, make_3dzoom2 je Objekt
```

Danach wandelt `Show_MOVEP_screen` den Chunky-Puffer nach Bitplanes. Der
Amiga hat also bereits chunky gerendert und anschließend konvertiert —
genau die Architektur, die für den Falcon vorgesehen ist. Der Weg ist auf
schwächerer Hardware schon einmal gegangen worden.

### 2. Die Konstanten

| Größe | Wert | Quelle |
|---|---|---|
| Sichtfenster | 144 × 144 | `cx2`/`cy2` = 143 in `Draw_dungeon` |
| Wandtextur | 128 × 80, 4 Planes | `Wall_width`, `Wall_size` = 5120 |
| Sichtbare Wände, höchstens | 50 | `Max_visible_walls` |
| Sichtbare Objekte, höchstens | 150 | `Max_visible_objects` |
| Einheiten je Kachel | 512 | `patt_size`, Zweierpotenz |
| Wandhöhe | 170 | `patt_size/3` |
| Winkelschritte | 1024 | `slang` |
| Projektionsfaktor | 256 | `proj_faktor`, `proj_log` = 8 |
| Zoomstufen | 320 | `Max_zoom` |

`Wall_size` = 5120 Byte stimmt exakt mit den gemessenen Wall3D-Einträgen
überein — eine unabhängige Bestätigung der Texturmaße.

### 3. Keine Division im heißen Pfad

Der Grund, warum das auf 7 MHz lief:

- **Projektion** über `proj_log` = 8, also Schieben statt Teilen.
- **Kachelgröße** 512 = 2⁹, `psize_log` = 9 — Koordinatenrechnung per Schieben.
- **Winkel** über eine Sinustabelle mit 1024 Einträgen.
- **Skalierung** über vorberechnete Zoomtabellen.

`Init_zoom_table` legt für jede Zielhöhe von 1 bis 320 eine Bresenham-Tabelle
an, die die Schrittweiten in der Quelltextur enthält. Der Schrittwert `16*4`
= 64 Byte entspricht genau einer Zeile der 128 Pixel breiten Textur bei
4 Planes.

**Speicherbedarf:** Summe 1…320 Einträge à 2 Byte = **100,3 KB**, dazu
1280 Byte Zeigertabelle. Im 4-MB-Budget des Falcon ist das nichts. Diese
Tabellen sollte man unverändert übernehmen — sie sind der Grund für die
Geschwindigkeit.

### 4. Aufwand je Bild — gemessen

Gemessen mit `bench/BENCH.TOS` auf einem Falcon030 mit TOS 4.04, Befehls- und
Datencache eingeschaltet.

| Messung | Zyklen je Einheit |
|---|---|
| Leerlaufschleife | 8,08 je Durchlauf |
| Rasterkern ohne Zoomtabelle | 28,29 je Pixel |
| Rasterkern mit Zoomtabelle | 35,62 je Pixel |
| Chunky nach Planar | 10,69 je Pixel |
| Blockkopie `movem.l` | 5,96 je Byte |
| Kachelblit maskiert | 8,05 je Pixel |

**Die Taktannahme ist bestätigt.** Die Leerlaufschleife braucht 8,08 Zyklen
für `subq.l` plus `bne` — genau der Lehrbuchwert des 68030. Damit stehen alle
anderen Zahlen auf sicherem Grund.

#### Hochrechnung auf ein Bild

| Posten | Zyklen |
|---|---|
| Rasterung, einfach überdeckt | 738 667 |
| Chunky nach Planar | 221 600 |
| Geometrie und Sortierung | ~50 000 |
| **bei doppelter Überdeckung** | **1 748 933** |

Das sind **9,1 Bilder je Sekunde**. Bei anderthalbfacher Überdeckung 11,6,
bei dreifacher 6,4.

#### Was der Emulator verschwiegen hat

Derselbe Test in Hatari, zum Vergleich:

| Messung | Hatari | Falcon | Verhältnis |
|---|---|---|---|
| Leerlauf | 222 | 202 | 0,91 |
| Rasterkern | 173 | 277 | 1,60 |
| Chunky nach Planar | 195 | 277 | 1,42 |
| Blockkopie | 169 | 244 | 1,44 |
| Kachelblit | 190 | 313 | 1,65 |

Bei reiner Rechenarbeit ist Hatari sogar etwas langsamer als die echte
Maschine. Sobald Speicher im Spiel ist, ist es vierzig bis fünfundsechzig
Prozent zu optimistisch — der 16-Bit-Bus des Falcon wird nicht abgebildet.

**Für die Planung heißt das: Emulatorzahlen zu Renderleistung sind wertlos.**
Für Korrektheit bleibt Hatari unverzichtbar; drei echte Fehler im Messprogramm
hat erst er zutage gefördert.

#### Wieviel Luft ist im Rasterkern?

Die Blockkopie zeigt den Boden: 5,96 Zyklen je Byte. Das reine Vollschreiben
des Sichtfensters kostet also 123 586 Zyklen.

Der Rasterkern liegt mit 35,62 Zyklen je Pixel **sechsmal über diesem Boden**.
Er ist damit klar rechen- und nicht bandbreitengebunden — und das ist die gute
Nachricht, denn Rechenarbeit lässt sich wegoptimieren, Bandbreite nicht.

Die Messschleife ist bewusst naiv: byteweise lesen, byteweise schreiben,
Tabellenzugriff, Maskierung, `dbf` — sechs Befehle je Pixel, nichts entrollt,
nichts langwortweise. Ein ernsthafter Zeichner sammelt mehrere Pixel und
schreibt sie als Langwort, entrollt die Schleife und hält die
Adressrechnung aus dem inneren Pfad heraus. Zwölf bis achtzehn Zyklen je
Pixel sind damit realistisch.

Bei fünfzehn Zyklen und doppelter Überdeckung: 622 000 für die Rasterung,
plus eine ebenfalls optimierte Wandlung bei etwa 124 000, plus Geometrie —
zusammen rund 800 000 Zyklen, also **20 Bilder je Sekunde**.

### 5. Was daraus folgt

**Die Architektur übernehmen, nicht neu erfinden.** Zoomtabellen,
Maleralgorithmus, Chunky-Zwischenpuffer und Schiebeprojektion sind auf
schwächerer Hardware erprobt. Ein von Grund auf neuer Raycaster wäre ein
Rückschritt.

**Der Chunky-Puffer ist klein.** 20 736 Byte — er passt in jede
Speicherkonfiguration und kann bei einem CT60 ins schnelle RAM.

**Die Wandlung ist der Posten, den es zu optimieren lohnt**, nicht die
Geometrie. Sie ist gut messbar und unabhängig vom Rest testbar.

**Die offene Frage ist beantwortet.** Ein Pixel kostet im naiven Fall 35,6
Zyklen, der Speicherboden liegt bei 6. Zwischen diesen beiden Zahlen liegt
die Arbeit.

**Bewertung:** Machbar, aber kein Selbstläufer. Mit unoptimiertem Code landet
man bei 9 Bildern je Sekunde, mit sorgfältig geschriebenem Zeichner bei
15 bis 20. Das Original bot auf dem Amiga nicht mehr. Ein K.o.-Kriterium ist
nirgends aufgetaucht — aber der Zeichner ist die eine Stelle, an der
Sorgfalt über das Ergebnis entscheidet, und nicht der Ort für den ersten
Entwurf, der gerade funktioniert.

**Der 2D-Teil ist unkritisch.** 8,05 Zyklen je Pixel für maskiertes
Kachelblitten heißt: ein volles Bild von 320x200 kostet 515 000 Zyklen, also
31 Bilder je Sekunde — und dabei zeichnet man ohnehin nur die veränderten
Bereiche.

### 6. Der Zeichner, gemessen — zweite Runde

`bench/BENCH2.TOS` stellt vier Fassungen desselben Zeichners gegeneinander,
gemessen auf einem Standard-Falcon030 und auf einem CT60.

#### Standard-Falcon030, 16 MHz

| Fassung | Zyklen je Pixel | gegenüber R1 |
|---|---|---|
| R1 Ziel zeilenweise, Textur normal | 37,81 | — |
| R2 Ziel spaltenweise, Textur normal | 37,04 | 1,02× |
| R3 Ziel spaltenweise, Textur transponiert | 32,79 | 1,15× |
| R4 wie R3, entrollt, langwortweise | **27,39** | **1,38×** |

**Die Zielanordnung ist fast wirkungslos** — 37,81 gegen 37,04. Das
widerspricht der Erwartung und hat einen handfesten Grund: Der Datencache des
68030 arbeitet als Write-Through ohne Write-Allocate. Jeder geschriebene Pixel
geht am Cache vorbei auf den Bus, ganz gleich wie günstig er liegt. Lokalität
hilft beim Lesen, beim Schreiben nicht.

**Die Texturanordnung wirkt** (1,15×), und das Entrollen mit langwortweisem
Schreiben wirkt (weitere 1,20×). Zusammen 1,38.

#### Was der Emulator falsch vorhergesagt hat

In Hatari war derselbe Vergleich 1,68×, und die Zielanordnung schien 1,11× zu
bringen. Beides zu optimistisch, weil weder Write-Through-Verhalten noch der
16-Bit-Bus abgebildet werden. Die Rangfolge stimmte, die Abstände nicht.

#### Bildrechnung Standard-Falcon

Mit R4 und dem Merge-Aufwand für die Wandlung:

| Überdeckung | Zyklen | Bilder/s |
|---|---|---|
| 1,5-fach | 1 204 684 | 13,3 |
| 2-fach | 1 488 664 | **10,7** |
| 3-fach | 2 056 623 | 7,8 |

Gegenüber der naiven Fassung aus BENCH1 (9,1) also ein Gewinn von etwa
achtzehn Prozent. Weniger als erhofft, aber in der richtigen Richtung.

#### CT60

| Messung | Faktor gegenüber 030 |
|---|---|
| R4 Zeichner | 15,0× |
| C0 naiver Wandler | 12,2× |
| C1 Merge | 3,1× |
| **C2 movep** | **0,1×** |

Auf einem CT60 ist die 3D-Ansicht kein Thema mehr — der Zeichner läuft
fünfzehnmal schneller, aus zehn Bildern je Sekunde werden über hundert.

**Und ein Fund, der eine Falle markiert:** `movep` ist auf dem 68060 nicht
mehr in Hardware vorhanden und wird per Ausnahme nachgebildet. Die Messung
läuft dort *achtmal langsamer als auf dem 030*, trotz vierfachem Takt — in
Zyklen gerechnet etwa fünfunddreißigmal teurer. Thalions Weg über
`Show_MOVEP_screen` wäre auf beschleunigten Maschinen also ein
Totalausfall gewesen. Gut, das gemessen zu haben, statt es zu übernehmen.

#### Wo der Zeichner jetzt steht

27,39 Zyklen je Pixel gegen einen Speicherboden von 5,96 je Byte — der
Abstand ist von Faktor 6 auf 4,6 geschrumpft. Weiter zu kommen heißt, gegen
das Write-Through-Verhalten zu arbeiten: weniger, dafür breitere
Schreibzugriffe. Langwortweise wird bereits geschrieben; der nächste Schritt
wären `movem.l`-Blöcke über mehrere Spalten hinweg, was die Schleifenstruktur
umkrempelt.

Ob sich das lohnt, ist eine Abwägung: Auf dem Standard-Falcon stünden
vielleicht 13 statt 10,7 Bilder je Sekunde, auf dem CT60 ist es ohnehin egal.

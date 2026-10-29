# Ambermoon auf Atari Falcon030 — Datenfluss- und Speicherplan

**Zielplattform:** Standard-Falcon030, 16 MHz, 4 MB ST-RAM, 8 Bitplanes / 256 Farben.
CT60 wird nicht vorausgesetzt, aber durch die Speicherstrategie automatisch mitgenommen.

**Stand:** August 2026 · Planungsdokument, kein Code

---

## 0. Die zentrale Erkenntnis

Ambermoons Grafiken liegen bereits als **row-interleaved Bitplanes** vor — exakt die Anordnung, die auch der Atari verwendet. Das Original nutzt 3, 4 oder 5 Planes; der Falcon nutzt 8.

Das heißt: Es gibt **keine** Formatkonvertierung im eigentlichen Sinne. Der Konverter füllt Planes auf und rechnet einen Palettenoffset ein. Das ist deutlich weniger Arbeit als bei einem Port von einer chunky-basierten Plattform.

Zweite gute Nachricht: Die 3D-Wandtexturen liegen im Original bereits in **8-Pixel-Chunks** vor — genau weil der Amiga-Raycaster sie in vertikalen Streifen gezeichnet hat. Diese Struktur passt zur geplanten Falcon-Renderstrategie.

---

## 1. Datenquellen

### 1.1 Ausgangsmaterial

"Extracted" in Pyrdacors Releases heißt **nur "aus den ADF-Images herausgelöst"**. Die `.amb`-Dateien sind weiterhin Container:

| Ebene | Status |
|---|---|
| ADF-Disk-Images auslesen | entfällt — extrahierte Releases nutzen |
| AMNC / AMNP Container | **nötig** — in `tools/ambtool.py` vorhanden |
| JH-Verschlüsselung | **nötig** — zurückgerechnet, siehe 1.3 |
| LOB-Dekompression (LZ77, Lothar Becks) | **nötig** — in `ambtool.py` vorhanden |
| Amiga-Hunk / Imploder | nur für Intro/Extro — Datenvariante funktioniert, Executable-Variante fehlerhaft |

Verifizierte Containerstruktur (an allen geprüften Dateien exakt aufgegangen, Restdifferenz 0):

```
Magic (4)  "AMNC" unkomprimiert | "AMNP" LOB-gepackt
Anzahl (2) n
Größen     n × udword
Daten      n Blöcke hintereinander
```

Bei AMNP sind nur die ersten 8 Byte eines Blocks Klartext; der Rest ist JH-verschlüsselt und beginnt mit der gepackten Größe, ausnahmslos `Blockgröße − 12`.

### 1.3 JH-Verschlüsselung

Nicht öffentlich dokumentiert, aus den Daten zurückgerechnet. Der Schlüsselstrom ist ein linearer Kongruenzgenerator:

```
k ← (k · 17 + 87) mod 65536
```

Startschlüssel: bei Einzeldateien `word[0] XOR word[1]`, bei AMNC- und AMNP-Containern die Eintragsnummer.

> **Warnung an mein früheres Ich:** Die Containergrößen gehen auch dann exakt auf, wenn der Inhalt noch verschlüsselt ist. Bei `Palettes.amb` sieht die Struktur (49 × 64 Byte) korrekt aus, die Bytes sind aber Chiffrat — erkennbar daran, dass High-Nibbles ≠ 0 auftreten, was im `$0RGB`-Format unmöglich ist. Strukturprüfung ersetzt keine Inhaltsprüfung.

**Versionsempfehlung:** 1.20 Deutsch, extracted. Ab 1.14 sind Texte, Itemdaten und Button-Grafiken aus dem Executable ausgelagert — das ist genau das, was wir wollen.

### 1.2 Relevante Dateigruppen

> **Hinweis:** Die Dateinamen unten sind die gebräuchlichen Bezeichnungen. Sie haben sich zwischen den Spielversionen teilweise geändert (z. B. `Monster_char_data.amb` → `Monster_char.amb` ab 1.14, `Dictionary.german` → `Dict.amb`). Die tatsächliche Namensliste beim ersten Konverterlauf aus dem entpackten Verzeichnis einlesen, nicht hart kodieren.

| Datei | Inhalt | Zielklasse |
|---|---|---|
| `Palettes.amb` | 32-Farb-Paletten, 4 Bit pro Kanal | Palette |
| `1Map_data.amb` … `3Map_data.amb` | Karten (2D und 3D, gleiches Format) | Struktur |
| Icon-Data (8 Tilesets) | Kartentiles 16×16, 5 Bit | Blit-Grafik |
| `NPC_gfx.amb` | NPC-Sprites 16×32, 5 Bit, variable Framezahl | Blit-Grafik |
| `Lab_data.amb` | Labyrinthdefinition für 3D-Karten | Struktur |
| `2Wall3D.amb`, `3DObject.amb`, `Overlay3D.amb` | 3D-Texturen, 4 Bit, 8-Pixel-Chunks | Textur |
| `Floors.amb` | Böden/Decken, 4 Bit, normales Zeilenformat | Textur |
| `Portraits.amb`, Items | Sonderpalette (nicht in `Palettes.amb`) | Blit-Grafik |
| `Layouts.amb`, `UIGfx`, Buttons | UI, 3 Bit | Blit-Grafik |
| `Text.amb`, `Dict.amb` | Texte und Wörterbuch | Struktur — Aufbau siehe 1.5 |
| `Monster_char.amb`, `NPC_char.amb`, `Party_char.amb` | Charakterdaten | Struktur |
| `Combat_background.amb`, Monster-Gfx | Kampfgrafik, überwiegend 5 Bit | Blit-Grafik |
| `Music.amb` | Musik (eigenes Thema, Phase 6) | Audio |

---

### 1.4 Kacheln: die Indirektion über Icon_data

Karten verweisen **nicht** auf Grafiken, sondern auf Kacheldefinitionen in
`Icon_data.amb`. Je Tileset stehen dort 2500 Definitionen à 8 Byte:

```
l  Flags (Begehbarkeit, Kollisionsklassen, Erscheinung)
w  Grafikindex im zugehörigen XIcon_gfx-Satz (1-basiert)
b  Anzahl Animationsbilder
b  unbekannt
```

Nur 219 der 2500 Einträge sind deckungsgleich mit ihrem Grafikindex. Wer die
Indirektion überspringt, bekommt ein Bild, das zu neunzig Prozent stimmt und
an genau den interessanten Stellen falsch ist — das ist beim Bau dieses
Konverters passiert und fiel per Augenschein nicht auf, sondern erst über die
Zählung der Verweise jenseits der Tilesetgrenze.

Definitionen mit `frames == 0` sind unbenutzte Füllplätze und werden nicht
gezeichnet. Die Flags tragen die Begehbarkeit — für die Kollisionsabfrage der
Engine also Pflichtlektüre, nicht Beiwerk.

### 1.5 Kartenkodierung 2D

Vier Byte je Kachel:

```
b0           Unterlage      (8 Bit)
b1           Ereignisindex  (Nummer der Ereigniskette)
(b2 << 8)|b3 Überlage       (16 Bit)
```

Belegt gegen einen FS-UAE-Speicherauszug von Großvaters Haus (Karte 258):
**79 von 81 Kacheln des Kartenfensters stimmen pixelgenau** mit dem
Amiga-Bildschirm überein. Die zwei Abweichungen liegen übereinander in der
Fenstermitte — das ist die Spielfigur, 16×32 Pixel, kein Kartenelement.

Gegenprobe über alle 271 zweidimensionalen Karten: von 589.173
Überlage-Werten liegt genau einer über den 2500 Definitionen (letzte Kachel
von Karte 167, Randmüll), und das Maximum von Byte 1 überschreitet auf keiner
Karte die Anzahl ihrer Ereignisketten.

#### Der Irrtum davor — und warum er so lange stand

Pyrdacors Dokumentation beschreibt zwei 12-Bit-Indizes, deren obere Bits sich
Byte 1 teilen, und Byte 3 als Ereignisfeld. Damit gerendert sah die Karte
vollkommen überzeugend aus: Räume, Wände, Türen, Teppiche an plausiblen
Stellen. Tatsächlich waren nur 48 von 81 Kacheln richtig.

Der Grund für die Täuschung: Die häufigste Bodenkachel (Grafik 49) ist unter
beiden Lesarten identisch und bedeckt den größten Teil der Fläche. Falsch
waren genau die Stellen mit belegter Überlage — also Möbel und Ausstattung,
das Auffällige, aber Seltene.

Gefunden wurde es nicht durch Hinsehen, sondern durch drei benachbarte
Kacheln, bei denen Byte 3 auf 146/147/148 lief und der Bildschirm die
Grafiken 371/372/373 zeigte. Konstante Differenz bei aufeinanderfolgenden
Werten ist kein Zufall.

**Methodische Lehre:** Ein Bild, das plausibel aussieht, ist kein Beleg. Erst
der pixelgenaue Vergleich gegen eine Quelle, die nicht aus derselben
Umrechnung stammt — hier der Speicherauszug einer laufenden Amiga-Sitzung —
trennt "sieht richtig aus" von "ist richtig".

`MAP_FILE.TXT` (Thalion, 1993) beschreibt an dieser Stelle drei getrennte
Schichten und ein Byte-Feld nach den Ereignisketten. Beides trifft auf die
ausgelieferten Daten nicht mehr zu. Die Originaldokumentation ist wertvoll,
aber älter als das Format auf den Disketten — im Zweifel entscheiden die
Daten.

### 1.6 Kartenkodierung 3D und Texturen

**Kacheln:** zwei Byte je Kachel, verschachtelt — `b0` Wand/Objekt, `b1`
Ereignisindex. Thalions Doku beschreibt auch hier getrennte Schichten; der
Grundriss von Karte 259 entscheidet eindeutig dagegen: verschachtelt ergibt
eine geschlossene Außenmauer mit Labyrinth, schichtweise nur ein
Schachbrettmuster. Über alle 84 dreidimensionalen Karten bleibt `b1` zudem
innerhalb der jeweiligen Ereigniskettenzahl.

**Wandtexturen:** 128×80, 4 Planes, 5120 Byte, im 8-Pixel-Chunk-Format.
Zeilenverschachtelt dekodiert ergibt sich Bildrauschen, chunkweise saubere
Holzbalkenwände mit Fenstern und Efeu. Damit ist auch die Grundlage für den
Raycaster bestätigt: die Quelldaten liegen bereits spaltenfreundlich vor.

### 1.7 Stand der Verifikation

| Gegenstand | Referenz | Ergebnis |
|---|---|---|
| Container, JH, LOB | alle 40 Dateien | fehlerfrei |
| Kacheldekodierung | Amiga-Bildspeicher | bitgenau |
| Palette | aktive Amiga-Palette | exakt |
| 2D-Kodierung, Innenkarte 258 (Tileset 4) | Speicherauszug | 79/81 |
| 2D-Kodierung, Weltkarte 156 (Tileset 1) | Speicherauszug | 80/81 |
| 3D-Kodierung, Karte 259 | Grundrissprüfung | eindeutig |
| Chunk-Texturformat | Bildvergleich | eindeutig |
| 8-Plane-Encoder, Maske, AMFA | Selbsttest | ohne Abweichung |

Die jeweils fehlende Kachel ist in beiden Fällen die Spielfigur in der
Fenstermitte — im Haus zwei Kacheln hoch, auf der Weltkarte eine.

**Noch offen:** Zuordnung der Texturen über die Labdata, Objekte und
Overlays in 3D, Sprites, Portraits und Kampfgrafik.

## 2. Palettenstrategie

Das Original arbeitet mit 32-Farb-Paletten und wechselt sie je nach Kontext. Der Falcon bietet 256 Farben — also **8 Bänke à 32 Farben gleichzeitig**.

### 2.1 Bankbelegung — Stand 2026-09-05

> **Der Entwurf unten stand hier ein halbes Jahr und war in einem Punkt
> falsch.** Er gab der Bedienoberfläche eine eigene Bank mit festem Grau.
> Das Original hat aber **eine einzige Palette zu 32 Farben**, und ihre
> Farben 24..31 *sind* die Rampe der Oberfläche — sie tönt mit der Karte.
> An drei Messungen belegt (Erkenntnis 141):
>
> ```
> Amiga, Kartenbildschirm:   Farbe 28 = (102, 85, 68)   bräunlich
> Amiga, Truhenbildschirm:   Farbe 28 = (102,102, 85)   grau
> Kartenpalette 7 (Nr. 258): Farbe 28 = (102, 85, 68)   ← gleich
> ```
>
> Der Fehler blieb verborgen, solange nur eigener Code die Farben setzte.
> Er fiel auf, als Thalions `Open_window` mit `move.w #Window_colour,d4`
> (= 28) einen rosa Rahmen zeichnete.

| Bank | Indexbereich | Inhalt |
|---|---|---|
| **0** | **0–31** | **Kartenpalette — Kacheln, Gruppe *und* Oberfläche (24..31)** |
| 1 | 32–63 | Ereignisbild (eigene Palette, Nummer 32) |
| 2 | 64–95 | Statusleiste: Portraits mit Sonderpalette, dazu ihre UI-Rampe |
| 3 | 96–127 | Verlauf hinter dem Portrait |
| 4–7 | 128–255 | frei |

**Die Regel dahinter:** was auf einem Amiga-Bildschirm gleichzeitig sichtbar
ist, teilt sich dort *eine* Palette. Bänke sind nur dort richtig, wo das
Original selbst umschaltet — beim Ereignisbild (eigener Bildschirm) und in
der Statusleiste (auf dem Amiga per Copperliste je Rasterzeile).

Wer der Oberfläche eine eigene Bank gibt, muss jede Farbnummer aus Thalions
Quelltext um den Bankversatz korrigieren — an jeder Stelle, in jeder
künftigen Datei. Das ist der Preis, den eine Zugabe kostet, sobald fremder
Code sie sieht.

Nachgemessen nach der Umstellung, direkter Farbvergleich mit dem Amiga:
Tastenfeld 4896/4896 und Rahmen 2304/2304 Punkte farbgleich.

### 2.2 Farbkonvertierung

Original: 4 Bit pro Kanal (Amiga OCS). VIDEL: effektiv **6 Bit** pro Kanal.

Das klingt nach mehr Spielraum, ist aber kein sauberer Faktor: `n/15` entspricht `n·4,2/63` und geht nur für n = 0, 5, 10, 15 glatt auf. Zwölf der sechzehn Stufen verschieben sich. TOS schneidet beim Umrechnen ab.

**Konsequenz:** Die Palette wird bereits im Konverter auf das 6-Bit-Raster gerundet vorgegeben, statt TOS abschneiden zu lassen. Der Gesamtfehler sinkt dadurch von 0,0635 auf 0,0571.

*(Nebenbei: der STE war hier exakt — 4 Bit auf 4 Bit geht glatt auf. Einer der wenigen Punkte, in denen die kleinere Maschine gewinnt.)*

### 2.3 Transparenz

Index 0 ist im Original transparent. Nach dem Bankoffset ist das nicht mehr Index 0, also braucht der Blitter eine Maske.

**Lösung:** Der Konverter erzeugt zu jedem Sprite offline eine 1-Plane-Maske (1 = Pixel sichtbar). Zur Laufzeit klassisches Cookie-Cut-Blitting: `dst = (dst & ~mask) | src`. Kein Vergleich pro Pixel, keine Verzweigung.

---

### 2.4 Palettenbänke und Durchsichtigkeit schließen sich aus

Beim ersten Bild auf echter Hardware ist ein Entwurfsfehler aufgeflogen, der
sich aus zwei für sich richtigen Entscheidungen ergab.

Der Konverter verschiebt Kacheln in eine Palettenbank, aus Index 0 wird also
zum Beispiel 32. Die Engine erkennt durchsichtige Pixel daran, dass in keiner
der acht Ebenen ein Bit gesetzt ist. Nach der Verschiebung hat aber **jedes**
Pixel ein gesetztes Bit — die Maske hält alles für sichtbar, und Überlagen
werden vollflächig gezeichnet. Im Bild saßen Teppiche und Möbel auf schwarzen
Rechtecken.

**Regel daraus:** Wer Bankoffsets benutzt, kann Durchsichtigkeit nicht mehr
am Farbwert 0 erkennen. Es gibt drei Auswege:

1. Kartengrafik in Bank 0 lassen. Reicht, solange nicht mehrere 32er-Paletten
   gleichzeitig sichtbar sein müssen.
2. Vorberechnete Masken in die Datei legen. Kostet Speicher, ist aber
   schneller als die Maske zur Laufzeit zu bilden — und macht die Frage
   gegenstandslos.
3. Den Bankoffset nur auf Pixel ungleich null anwenden (`transparent0=True`)
   und Unterlagen deckend blitten. Dann zeigt Index 0 allerdings auf die
   globale Farbe 0, nicht auf die Farbe 0 der Bank.

Für den 2D-Teil ist Weg 2 die richtige Antwort: Die Masken entstehen ohnehin
schon im Konverter, sie müssen nur mitgeschrieben werden.


### 1.5 `Text.amb` — drei Blöcke in drei Formaten

Nachgemessen 2026-09-05. Die Datei ist **nicht** einheitlich aufgebaut;
naives Zerteilen an Nullbytes ergibt 1173 Texte statt der richtigen Zahlen.

| Versatz | Texte | Tabelle | Inhalt |
|---|---|---|---|
| `0x0002` | 46 | **Versätze** | Disketten- und Fehlermeldungen |
| `0x05d8` | 300 | **Längen** | `Prompts` — das Format von `Find_large_text` |
| `0x379e` | 31 | keine, nur NUL-getrennt | Ereignisnamen (`Rätselmund`, `Teleporter`) |

Der mittlere Block liegt genau so, wie `Find_large_text` ihn erwartet:

```
	move.w	(a0)+,d7		; Anzahl
	move.l	a0,a1			; Längentabelle
	add.w	d7,d7 / add.w d7,a0	; über die Tabelle
.Loop:	add.w	(a1)+,a0
```

Er wandert deshalb **unverändert** in die Szenendatei — kein Umpacken, nicht
einmal ein Kopf. Die Nummerierung ist belegt: sechs Nummern, die der
Originalquelltext nennt, treffen alle.

```
 42  "Dieser Gegenstand ist verflucht!"     Unequip_item
 54  "Wieviele nehmen?"                     Move_backpack_item
 60  "Programm wirklich verlassen?"         Quit_game
 84  "Welcher Gegenstand soll in die Truhe gelegt werden"
 85  "Wieviele verstauen?"                  Drop_item_CHEST
 91  "Die Truhe ist voll."
```

### 1.6 Wo die Oberflächengrafiken herkommen

Nicht alles steht in den `.amb`-Dateien. Belegt (Erkenntnis 131):

| Grafik | Quelle |
|---|---|
| `Control_icons`, 78 Stück 32×13 | Spieldatei `Button_graphics` |
| `Button_up` / `Button_down`, 32×17 | `AM2_CPU` Hunk 3 ab `0x2860` |
| `Window_icons`, 8 Stück 16×16 | `AM2_CPU` Hunk 3 ab `0xC0` |
| `Status_L/M/R/TB` | `AM2_CPU` Hunk 3 ab `0x19D8` |
| Zeichensatz | `AM2_CPU` Hunk 13 |

**Alle in drei Ebenen, Farbbasis 24.** Sie werden *nicht* auf acht Ebenen
aufgezogen: `Put_window_part` rechnet mit einer wörtlichen 96 je Teil
(`3*2*16`), und `Display_up_button` mit `13*12`. Wer sie umpackt, verschiebt
jeden Teil um den Faktor 8/3. Das Aufziehen macht die Blitroutine
(`Put_masked_icon`, `Put_masked_block2`) zur Laufzeit, mit `d5` = Ebenen der
Quelle und `d4` = Farbbasis.

## 3. Zielformate

Zwei Klassen, bewusst unterschiedlich:

### Klasse A — Blit-Grafik (planar, 8 Planes)

Für alles, was als Ganzes kopiert wird: Tiles, Sprites, Portraits, UI, Kampfgrafik.

Layout: word-interleaved wie der Bildschirm selbst — 16 Pixel pro Gruppe, 8 Words hintereinander (Plane 0…7), also 16 Bytes pro 16 Pixel.

Vorteil: `movem.l`-Kopie direkt in den Screen, keine Umrechnung zur Laufzeit.
Kosten: 1 Byte pro Pixel im RAM.

Jedes Sprite bekommt einen kleinen Header: Breite, Höhe, Framezahl, Offset zur Maske.

### Klasse B — Textur (chunky, 1 Byte pro Pixel)

Für alles, was der Raycaster **pixelweise samplet**: Wände, Objekte, Overlays, Böden.

Layout: schlicht 1 Byte pro Pixel, **spaltenweise** abgelegt (transponiert). Der Raycaster zeichnet vertikale Streifen — spaltenweise Ablage macht daraus einen linearen Speicherzugriff mit konstantem Schritt statt eines Sprungs pro Pixel. Das ist der Unterschied zwischen Cache-Treffer und Cache-Miss in der innersten Schleife.

### Warum nicht alles gleich?

Planar ist unschlagbar beim Kopieren ganzer Blöcke und halbiert bei 8 Bit den Speicherbedarf gegenüber Truecolor. Planar ist katastrophal beim Setzen einzelner Pixel. Ambermoon macht beides — also zwei Formate.

### 3.1 Renderfluss auf dem Bildschirm

```
   ┌─────────────────────────────────────┐
   │  Screen: 320×200, 8 Planes, ST-RAM  │
   │  ┌───────────────┐  ┌────────────┐  │
   │  │ 3D-Viewport   │  │ Portraits  │  │
   │  │ ← C2P aus     │  │ ← planar   │  │
   │  │   Chunky-Buf  │  │   geblittet│  │
   │  └───────────────┘  └────────────┘  │
   │  ┌───────────────────────────────┐  │
   │  │ UI / Text ← planar geblittet  │  │
   │  └───────────────────────────────┘  │
   └─────────────────────────────────────┘
```

Der Raycaster schreibt in einen Chunky-Puffer in Viewport-Größe. Ein C2P läuft nur über diesen Ausschnitt — grob ein Achtel der Bildfläche. Der Rest des Bildschirms wird planar geblittet und bei Bedarf gar nicht angefasst.

*(Viewport-Maße im ersten Konverterlauf ausmessen — sie stehen in den Layout-Daten, nicht raten.)*

---

## 4. Ausgabecontainer

Ein einziges Format für alles, damit der Atari-Loader trivial bleibt:

```
Offset  Typ      Inhalt
0x00    char[4]  "AMFA"
0x04    uword    Version
0x06    uword    Anzahl Einträge (n)
0x08    Eintrag[n]:
          udword  Offset ab Dateianfang
          udword  Länge
          uword   Typ (0=planar, 1=maske, 2=chunky, 3=palette, 4=roh)
          uword   Breite
          uword   Höhe
          uword   Frames
        danach: Rohdaten, jeder Eintrag auf 4 Byte ausgerichtet
```

**Wichtig:** Alle Daten bereits big-endian und ausgerichtet ablegen. Der Loader macht dann nur `Fseek` + `Fread` in einen Puffer — keine Umrechnung, keine Dekompression, kein Parsing zur Laufzeit.

Aufteilung in mehrere Dateien nach Ladeeinheit, nicht nach Datentyp:

| Datei | Inhalt | Resident? |
|---|---|---|
| `CORE.AMF` | UI, Font, Layouts, Paletten, Item-/Spell-Tabellen | ja |
| `TILESET1.AMF` … `TILESET8.AMF` | je ein Tileset | eines aktiv |
| `MAPxxx.AMF` | Karte, Events, Texte, NPC-Referenzen | eine aktiv |
| `LABxx.AMF` | Labdata + Texturen eines Labyrinths | eines aktiv |
| `COMBAT.AMF` | Kampfgrafik, Monster | bei Bedarf |
| `NPCGFX.AMF` | NPC-Sprites | ja |

---

### 4.1 Aufbau einer Tileset-Datei

```
Eintrag 0        Palette (256 Langwörter für VsetRGB)
Eintrag 1        Definitionstabelle
Eintrag 2 … n+1  Kachelgrafiken, planar, 16x16
```

Definitionstabelle: `w` Anzahl, dann je 8 Byte `l` Flags, `w` Grafikindex,
`b` Bildzahl, `b` Füllbyte.

**Animationen werden nicht dupliziert.** Die Folgebilder liegen im Tileset
ohnehin fortlaufend hinter dem Grundbild; die Engine zeichnet
`gfx + (takt mod frames) - 1`. Geprüft über alle acht Tilesets: 176 animierte
Definitionen, keine überschreitet die Tilesetgrenze, und keines ihrer
Folgebilder wird von einer anderen Definition beansprucht.

Die Flags in dieser Tabelle tragen die Begehbarkeit und die
Kollisionsklassen — für die Engine also Pflichtdaten, nicht Beiwerk.

## 5. Speicherbudget (4 MB Falcon)

| Bereich | Bedarf | RAM-Typ |
|---|---|---|
| TOS + Systemvariablen | ~250 KB | ST |
| Screen, Double Buffer (320×200×8bpp) | 125 KB | **ST-RAM zwingend** |
| Chunky-Puffer 3D-Viewport (doppelt) | ~40 KB | beliebig |
| DSP-/Audio-Puffer | ~64 KB | **ST-RAM zwingend** |
| Programmcode | ~200 KB | beliebig |
| `CORE.AMF` (resident) | ~300 KB | beliebig |
| Aktives Tileset | ~64 KB | beliebig |
| Aktive Karte + Events + Texte | ~80 KB | beliebig |
| NPC-Grafiken | ~150 KB | beliebig |
| Labdata + 3D-Texturen (aktiv) | ~350 KB | beliebig |
| Kampfgrafik (bei Bedarf) | ~400 KB | beliebig |
| Musik + Samples | ~500 KB | teils ST |
| Party- und Savegame-Zustand | ~60 KB | beliebig |
| **Summe** | **~2,6 MB** | |
| Reserve | ~1,4 MB | |

**Fazit: Speicher ist nicht das Problem.** Der Amiga musste mit 1 MB auskommen und hat deshalb ständig nachgeladen. Mit 4 MB kann fast alles resident bleiben — das ist der größte Einzelgewinn gegenüber dem Original und kompensiert einen Teil des Bandbreitennachteils.

### 5.1 Allokationsregel

Genau zwei Aufrufe unterscheiden:

- `Mxalloc(size, ST_RAM)` — nur für Screen und Audiopuffer
- `Mxalloc(size, PREFER_ALT)` — für alles andere

Auf dem Standard-Falcon fällt der zweite Fall auf ST-RAM zurück. Auf einem CT60 landet er im schnellen TT-RAM. Das kostet jetzt eine Zeile und schenkt später einen Speedup ohne weitere Arbeit.

---

## 6. Vorgehen — die ersten Schritte

### Phase 1 — Konverter: **bereits erledigt**

`tools/ambtool.py` beherrscht JH, LOB, AMNC/AMNP, Amiga-Hunks und Planar→PNG. Alle 59 Dateien aus `Amberfiles` lassen sich entpacken. Es fehlt gegenüber diesem Plan nur noch:

1. Bankoffset-Logik und Maskenerzeugung (bisher pro Szene in `scene2fal.py`, nicht generisch)
2. `AMFA`-Ausgabecontainer
3. Chunky-transponiertes Texturformat für den späteren Raycaster

Kontrolle bleibt: PNG rendern. Wenn das PNG stimmt, stimmen die Daten — Fehler später auf dem Atari zu suchen ist teuer.

> **Merksatz aus der STE-Phase:** Die Maske muss aus den Originaldaten kommen, nicht aus den farbreduzierten. Sonst fallen Farben auf Index 0 und gelten fälschlich als transparent. Und: eine Verifikation, die ihre Referenz aus denselben umgerechneten Daten baut, macht den Fehler mit.

### Phase 2 — Atari-Loader und Tile-Renderer

1. `AMFA` laden, Bänke in die Falcon-Paletten-Register schreiben
2. Videl auf 320×200, 8 Planes, Double Buffer
3. Kartenausschnitt aus Tiles zeichnen
4. VBL-Zähler pro Subsystem einbauen — ab hier gibt es Zahlen

### Phase 3 — Bewegung und Kollision

Party bewegen, Kollision gegen Tile-Flags, Scrolling. Erst hier zeigt sich, ob Vollbild-Redraw reicht oder Dirty Rectangles nötig sind.

### Phase 4 — 3D-Prototyp (das eigentliche Risiko)

Getrennt vom Rest: Labdata + Texturen laden, Raycaster in den Chunky-Puffer, C2P für den Viewport, messen. **Auf echter Hardware messen** — Hatari emuliert den Falcon funktional gut, aber das 030-Timing ist nicht zyklengenau.

Zielmarke: 12–15 fps. Das Original war nicht schneller.

### Phase 5 — Spiellogik: portieren, nicht reimplementieren

**Korrektur gegenüber der ersten Fassung dieses Dokuments.** Von 40 Dateien und 50.723 Zeilen 68000-Assembler im freigegebenen Quellcode greifen **zwei** auf Amiga-Hardware zu: `FAIRY.S` und `HULL/VARIOUS.S`. MAIN, COMBAT, INVENTOR, MAGIC, EVENTS und die gesamte Kartenverwaltung enthalten keine einzige `$dff`-Referenz.

**Nachtrag.** Die Zahl war lange „genau eine", und der Grund dafür ist lehrreich: `HULL/VARIOUS.S` schreibt die Adresse nicht als `$dff`, sondern symbolisch — `move.w #$000f,Custom+dmacon`, zweimal, um vor dem Entfernen der Musik die DMA-Kanäle abzuschalten. Eine Suche nach `$dff` findet das nicht. Erschwerend kommt hinzu, dass genau diese Datei von `grep` für eine Binärdatei gehalten und bei einer Suche über den Baum stillschweigend übersprungen wird. Einzelheiten in Erkenntnis 51.

Die Spiellogik ist hardwareunabhängig geschrieben. Alles Amiga-Spezifische lag in den Basis-Bibliotheken — Laden, Speicherverwaltung, Grafikprimitive, erkennbar an den `Get`/`Free`-Makros — und **diese fehlen im Release**.

Das eigentliche Hindernis für einen Vollport ist damit nicht die Spiellogik, sondern eine neu zu schreibende Bibliotheksschicht. Die ist zielplattformunabhängig zu spezifizieren: Erst die Aufrufkonventionen der fehlenden Makros aus ihrem Gebrauch im vorhandenen Code rekonstruieren, dann gegen Falcon-Primitive implementieren.

Referenz für strittige Semantik bleibt Ambermoon.net.

### Phase 6 — Sound

Zuletzt. DMA-Sound und DSP sind ein eigenes Kapitel.

---

## 7. Offene Punkte

| Punkt | Klärung durch |
|---|---|
| **Fehlende Bibliotheksschicht** — die eigentliche Portierhürde | Aufrufkonventionen der `Get`/`Free`-Makros aus ihrem Gebrauch rekonstruieren |
| Exakte Viewport-Maße des 3D-Fensters | Layout-Daten auslesen |
| Größe der einzelnen Tilesets in KB | Konverterlauf über alle 8 Tilesets |
| Reichen 8 Palettenbänke für alle Kontexte? | Bestandsaufnahme aller 49 Paletten |
| Verhalten bei Palettenfades (Tag/Nacht) | Bank 6 als Zielbank, Interpolation zur Laufzeit prüfen |
| Font-Rendering: planar blitten oder Bitmuster expandieren? | Messen, sobald Text auf dem Schirm ist |
| ~~`imploder_exe.py` liefert falsche Daten~~ | Behoben 2026-09-29: der Ring bleibt zwischen den Aufrufen stehen, und der entpackte Strom ist ein Befehlsstrom für die Hunks (`docs/11-Intro-Extro.md`) |
| Sonic-Arranger-Modul → Falcon | DSP-Ansatz, Phase 6 |

### 7.1 Verifikationsfallen, die schon zugeschlagen haben

Drei Fälle, in denen eine Prüfung grün war und trotzdem falsch:

1. **Containergrößen gehen auch bei verschlüsseltem Inhalt exakt auf.** Struktur ≠ Inhalt.
2. **Der Imploder-Entpacker für Executables** meldete "Eingabe vollständig verbraucht" und "Durchlaufzähler auf null" — beides misst nur den Kontrollfluss, nicht den Inhalt. Von 600 Stichproben fand sich keine im Speicherabbild wieder.
3. **Die Maskenprüfung** baute ihre Referenz aus denselben farbreduzierten Daten und übernahm den Fehler.

Gemeinsamer Nenner: Eine Verifikation, die aus derselben Quelle wie das Prüfobjekt stammt, prüft nichts. Referenzen müssen unabhängig sein — Savestate, Screenshot, oder Rechnung von Hand.

---

## 8. Quellen

- [jhorneman/ambermoon — freigegebener 68000-Quellcode und Thalion-Originaldokumentation](https://github.com/jhorneman/ambermoon)
- [Pyrdacor/Ambermoon — Ressourcen und Spezifikationen](https://github.com/Pyrdacor/Ambermoon)
- [Grafikformate](https://github.com/Pyrdacor/Ambermoon/blob/master/FileSpecs/Graphics.md)
- [Kartenformat](https://github.com/Pyrdacor/Ambermoon/blob/master/FileSpecs/Maps.md)
- [2D-Karten und Tilesets](https://github.com/Pyrdacor/Ambermoon/blob/master/FileSpecs/Maps2D.md)
- [Thalion Source — Ambermoon Dateiliste](http://thethalionsource.w4f.eu/Artikel/Ambermoon_Dateien.htm)
- [Labdata für 3D-Karten](https://github.com/Pyrdacor/Ambermoon/blob/master/FileSpecs/Labdata.md)
- [Ambermoon.net — Referenzimplementierung](https://github.com/Pyrdacor/Ambermoon.net)
- [Containerformate (Amberstar, formatgleich)](https://github.com/Pyrdacor/Amberstar/blob/main/FileSpecs/Containers.md)
- [Chunky-to-Planar Tutorial, The Paranoid / Paradox](https://www.atari-wiki.com/index.php?title=Chunky-to-Planar_for_Dummies:_An_in-depth_tutorial_by_The_Paranoid_/_Paradox)

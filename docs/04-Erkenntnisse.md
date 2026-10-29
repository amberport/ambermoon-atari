# Erkenntnisse und Fallstricke

Was in diesem Projekt schiefging und woran es lag. Die meisten Einträge sind
Fehler, die *plausibel aussahen* — deshalb stehen sie hier.

**Aufbau.** Die Nummern sind fest, denn Code und Doku verweisen auf sie.
- Hier stehen die allgemeinen Einträge 1–13 und ab 121 alles, was beim
  Einbinden von Thalions Quelltext gelernt wurde.
- Entries 14–120 come from the time of the rebuild and are in
  `archiv/04a-Erkenntnisse-Nachbauzeit.md`, which is not part of the
  published repository.
- Ein Eintrag, der überholt, widerlegt oder durch Thalions Code erledigt ist,
  trägt oben einen Vermerk „Stand“.
- Wiederholt sich eine Falle, gehören die Einträge zu einer **Gruppe**
  (unten). Die Regel steht einmal in der Gruppe; jeder Eintrag nennt seine
  Gruppe.

# Die Regeln in Kurzform

Was hier steht, ist jeweils mindestens einmal teuer bezahlt worden. Wer neu
einsteigt oder nach einer Pause weitermacht, liest am besten nur diese
Seite. Maßstab sind die beiden Leitziele (CLAUDE.md): **Thalions Quelltext
unverändert übernehmen, nur Brücken und die Bibliothek schreiben**, und
**die Originaldateien zur Laufzeit lesen**.

**Beim Einbinden von Thalions Quelltext**

- Nichts nachbauen, nichts abschreiben. Fehlt ein Stück, zuerst fragen, ob
  die ganze Originaldatei herein kann. Jede Paraphrase hat bisher Fehler
  eingebaut. *(Gruppe P)*
- Ein Name aus Thalions Bibliothek verpflichtet auf seinen ganzen Vertrag:
  Register, Abschnitt, Strukturlänge, Makroverhalten, Schrittweite. Den
  Vertrag liest man an **allen** Aufrufstellen ab, nicht an einer. Das gilt
  auch für unsere eigenen Aufrufe eines Namens, der den Besitzer wechselt.
  *(Gruppe V)*
- Es kann ein Aufruf fehlen statt eines Namens: zu jedem `Reset_*` und
  jedem `DisUpd` den Rufer suchen. *(Gruppe A)*
- Ein Platzhalter für Code gehört in den Datenabschnitt, sonst überschreibt
  ein `lea`-Ziel ein `rts` (157). Ein Platzhalter für einen **Datensatz**,
  der in einen Baum oder eine Tabelle eingehängt wird, verhält sich wie
  „nichts da“, und weder Bau noch Linker merken es (187).
- Strukturversätze nur an einem Datensatz aus Thalions Quelltext
  festmachen, nie an einer Zugriffsfolge (172).
- Eine Konstante in `vorspann.i` meint, was Thalion meinte, nicht was der
  Falcon hat (`Pal_size` = 32, 185; `Screen_depth` = 5, 191). Die Tiefe
  unseres Schirms heißt `Schirm_ebenen`/`PLANES`. vasm-Warnung 2028 ist ein
  Fehler.
- Ein Satz, den Thalion der Bibliothek übergibt, kann sich danach noch
  ändern: `Init_module` legt die Mouse-Area auf, *dann* rechnet `ModInit`
  sie aus. Die Bibliothek hält Zeiger, keine Abschriften (192).
- Makros der Bibliothek lassen jedes Register stehen, das sie nicht
  zurückgeben, nehmen jedes Register als Argument, auch `d0`, und bleiben
  kurz, weil Thalion mit `bxx.s` über sie springt (164, 186).
- Über die Grenze zwischen `engine.s` und `spiel.s` nur `jsr` (181).
- Texte der Bibliothek liegen an festen Marken in `Textdaten`
  (`build/textmarken.i`); die Lage schreibt `tools/textmarken.py` beim Bau,
  den Inhalt liest `Lade_texte` zur Laufzeit (250).

**Beim Schreiben von Bibliothek und Brücken**

- Wer einen Wert über einen Aufruf hält, prüft, was der Gerufene
  überschreibt. `trap` darf d0–d2 und a0–a2 verändern. *(Gruppe R)*
- Nach `move.b`/`move.w` ist der Rest des Registers Müll; `add.l`, `divu`
  und `mulu` lesen trotzdem 32 Bit. `moveq #0,dn` davor. *(Gruppe W)*
- Ein Rückgabewert ist kein Schmierregister, und jeder Rückgabewert, der
  eine Menge meldet, wird geprüft. *(Gruppe E)*
- Wer eine Routine per `bra` verlässt, lässt ihren Stapelrahmen liegen.
  `start` setzt `sp` auf den eigenen Stapel. *(Gruppe S)*
- Bibliothekseinsprünge laden `lea vars,a5` selbst, denn `a5` gehört nicht
  zu Thalions Vertrag (177).
- Absolute Adressen sind richtig, seit `vlink` die Verschiebetabelle
  schreibt; Thalions `dc.l <Marke>` braucht sie (122). PC-relativ ins BSS
  geht nicht (130).

**Bei Grafik und Farben**

- Originaldaten bleiben im Speicher, wie sie sind; die Bibliothek weitet
  beim Zeichnen auf (165, 176). Eine vorab aufgeweitete Grafik ist ein
  Umweg.
- Farbe = Bank der Bildzeile + `d4` oberhalb `d5` + Quellwert, und **0
  bleibt 0**. Das gilt für **jede** Zeichenroutine, auch `Draw_box` und
  `Put_char` (`Zeilenfarbe`): Hintergründe sichert `Get_block` mit fünf
  Ebenen, und die Bank kommt beim Zurücksetzen aus der Zeile (191).
  *(Gruppe F)*
- `Icon_size` ist der Abstand in Thalions Daten, nicht die Größe auf
  unserem Schirm (176).
- Beim Zeichnen alle acht Ebenen anfassen (21). Der Falcon hat zwei Sätze
  Farbregister; der maßgebliche wird zuletzt geschrieben (15, 77).
- Die Monitorbits werden aus dem Desktop geerbt, nicht gesetzt (152).
  Exception since 2026-10-25 (T65): at RGB `Open_screen` sets `MD_PAL`
  (50 Hz); VGA keeps its mode.

**Beim Prüfen**

- Ein Bild, das richtig aussieht, ist kein Beleg (1). Der Beleg ist ein
  Speicherinhalt: Savestate, Registerabzug, TOS-Nachruf bei `$380` (164,
  166, 182).
- Mauseingaben nicht im Emulator nachstellen, sondern um einen Savestate
  bitten (105, 158).
- Scheitert ein Lauf, zuerst den Messaufbau prüfen, dann den Code. Ein
  Prüfmittel, das nichts findet, erst selbst prüfen. *(Gruppe M)*
- Der Emulator findet andere Fehler als die Hardware (4).
- Programm und Daten müssen zusammenpassen: `tools/pruefe_paar.py` (38).
- In Thalions Quelltext immer `grep -a` (51).

# Gruppen: dieselbe Falle mehrfach

Die Regel steht hier einmal. Die Einträge darunter sind Belege, jeder mit
eigenem Befund. Kursiv: in der Nachbauzeit (04a).

| Gruppe | Regel | Einträge |
|---|---|---|
| **R** Register über einen Aufruf | Wer einen Wert über einen Aufruf hält, kennt dessen Vertrag. Vorbelegen heißt überschreiben. Auch ein Trap ist ein Aufruf (270). | *9, 12, 46, 54, 67, 85, 97, 113*, 166, 178, 270 |
| **W** Oberes Wort, oberes Byte | Nach `move.b`/`move.w` den Rest löschen, bevor 32 Bit gelesen werden. | 13, *102*, 168 |
| **E** Rückgabewerte | Rückgabe nicht überschreiben, Mengen prüfen. | 7, *60, 90*, 173 |
| **S** Stapel | `bra` aus einem Rahmen lässt ihn liegen; `rts` in fremdem Rahmen holt Daten. Eigener Stapel. | 8, *99, 109*, 185 |
| **V** Name heißt Vertrag | Aufrufstellen lesen, alle. Auch Makros, Abschnitte, Strukturversätze. | 157, 160, 161, 164, 165, 167, 169, 170, 171, 172, 173, 177, 186, 263, 267, 268 |
| **A** Es fehlt ein Aufruf | Zu jedem `Reset_*`, `DisUpd`, jeder Freiräum-Routine den Rufer suchen. Eine gesperrte Zeile einer `.Mev`-Liste fehlt in Thalions innerer Schleife wirklich. | *91*, 162, 172, 178, 188 |
| **P** Nachgebaut statt übersetzt | Paraphrase baut Fehler ein. Übernehmen oder fragen. | 5, *29, 111, 120*, 125, 126, 160, 163, 261 |
| **M** Messaufbau vor Befund | Erst den Aufbau prüfen, früh aufhören, um Handarbeit bitten. | 4, *38, 52, 53, 94, 105, 119*, 128, 150, 158, 159 |
| **F** Farben und Bänke | Farbe aus der Bank der Bildzeile, 0 bleibt 0. Die Bank hängt am Platz in der Rasterliste, nie am Inhalt einer Bank. Stand: 176, 264. | *16, 17, 18, 19, 64, 73*, 141, 176, 264, 265, 266, 267, 271 |
| **T** Timer-B-Raster | Stand: 156 (vertagt). 151 ist durch 154 widerlegt. | 143, 145, 150, 151, 153, 154, 155, 156 |
| **Z** Mauszeiger und Tastenmüll | Nachbauzeit. Die Ursache des Flackerns fand 49, den Tastenmüll klärte 62 nicht. Der Zeiger ist ein Sprite und folgt in jedem Bild, nicht im Takt des Spiels (269). | *20, 21, 22, 23, 44, 45, 47, 48, 49, 61, 62, 71, 72, 79, 80, 83, 103, 104, 106, 107*, 269 |
| **D** Mengendialog | Erledigt: Thalions `InputNr_Mod` läuft (A4). | *108, 114, 115, 116* |

# Allgemeine Einträge (1–13)

## 1. Ein Bild, das richtig aussieht, ist kein Beleg


Der häufigste und teuerste Fehlertyp.

**Kartenkodierung.** Pyrdacors Dokumentation beschreibt zwei 12-Bit-Indizes,
die sich Byte 1 teilen, und Byte 3 als Ereignisfeld. Damit gerendert sah eine
Karte vollkommen überzeugend aus: Räume, Wände, Türen, Teppiche an
plausiblen Stellen. Tatsächlich waren nur 48 von 81 Kacheln richtig. Der
Grund: Die häufigste Bodenkachel ist unter beiden Lesarten identisch und
bedeckt den größten Teil der Fläche. Falsch waren genau die Stellen mit
Überlage — Möbel und Ausstattung, das Auffällige, aber Seltene.

Richtig ist:

    b0           Unterlage      (8 Bit)
    b1           Ereignisindex
    (b2 << 8)|b3 Überlage       (16 Bit)

Gefunden nicht durch Hinsehen, sondern durch drei benachbarte Kacheln, bei
denen Byte 3 auf 146/147/148 lief und der Amiga-Bildschirm die Grafiken
371/372/373 zeigte. Konstante Differenz bei fortlaufenden Werten ist kein
Zufall.

**Die Indirektion über Icon_data.** Karten verweisen auf Kacheldefinitionen,
nicht auf Grafiken. Nur 219 von 2500 Definitionen sind deckungsgleich mit
ihrer Grafiknummer. Wer die Indirektion überspringt, bekommt ein Bild, das zu
neunzig Prozent stimmt.

**Lehre:** Referenzen müssen aus einer anderen Quelle stammen als das
Prüfobjekt. Hier waren es Speicherauszüge laufender Amiga-Sitzungen.

## 2. Bei *Bedeutung* hilft Raten nicht


Der Gegenpol zu Punkt 2.

Für die Kollisionsabfrage hatte ich Bit 2 der Kachelflags gewählt, weil es
als einziges ein Muster ergab, das den Mauern im Bild entsprach. Bit 2 ist in
Wirklichkeit die Zeichenreihenfolge. Richtig sind Bit 7 (jede Bewegung
gesperrt) und Bit 8 (Gehen erlaubt) — und es gilt eine Regel, auf die man
nicht von selbst kommt: Sind die Flags der Überlage null oder ist Bit 5
gesetzt, gelten die der Unterlage, sonst die der Überlage. Kein Verodern
beider.

**Lehre:** Formate lassen sich messen, Semantik nicht. Für Flags,
Ereignistypen und Spielwerte zuerst nachschlagen.

## 3. Dokumentation kann älter sein als die Daten


Thalions eigene Beschreibungen (`AMBEDOCS.ORD`, Stand 1993) sind für
Spiellogik und Datenbedeutung Gold wert, für die Dateistruktur aber
teilweise überholt:

- `MAP_FILE.TXT` beschreibt die Kacheldaten als drei getrennte Schichten.
  In den ausgelieferten Daten sind sie verschachtelt.
- Ebenso ein Byte-Feld nach den Ereignisketten, das nicht mehr existiert.
  Mit ihm ergeben sich 270 statt 18 Ereignissen.

Bei 3D-Karten gilt dasselbe: Auch dort beschreibt die Doku Schichten, und
auch dort ist es verschachtelt. Entschieden hat der Grundriss — verschachtelt
ergibt eine geschlossene Außenmauer mit Labyrinth, schichtweise ein
Schachbrettmuster.

**Lehre:** Im Zweifel entscheiden die Daten. Aber siehe Punkt 3.

## 4. Der Emulator findet andere Fehler als die Hardware

> Gruppe **M** (Messaufbau vor Befund), Regel in der Kurzform.

Beides wird gebraucht, für Verschiedenes.

**Nur im Emulator gefunden:** Registerkollisionen zwischen Messschleife und
Messroutine, ein zu klein bemessener Variablenbereich, eine
Kalibrierung, die sich nicht einschwang.

**Nur auf echter Hardware gefunden:** Die Modusmaske behielt das COL80-Bit,
wodurch der Bildschirm 640 statt 320 Byte je Zeile breit war — das Bild
erschien doppelt nebeneinander. Und die Palette wurde beim Verlassen nicht
zurückgestellt.

**Für Messwerte ist der Emulator wertlos.** Bei reiner Rechenarbeit war
Hatari sogar neun Prozent langsamer als die echte Maschine, bei allem mit
Speicherzugriff vierzig bis fünfundsechzig Prozent zu optimistisch — der
16-Bit-Bus wird nicht abgebildet.

## 5. Beschreibungen des Ergebnisses sind keine Bauanleitung

> Gruppe **P** (Nachgebaut statt übersetzt), Regel in der Kurzform.

Pyrdacor beschreibt die Zeichenreihenfolge so, dass "die obere Hälfte der
Figur über den Kacheln" gezeichnet wird. Ich habe die Figur daraufhin in zwei
Hälften zerlegt — und sie verschwand.

Der Originalquelltext zeichnet sie in einem Stück, 32 Zeilen, um eine Kachel
nach oben versetzt. Die Verdeckung entsteht allein aus der Reihenfolge der
Aufrufe: Unterlage, Gruppe, Überlage.

Die tatsächliche Regel ist viel einfacher als gedacht: `Display_2D_map`
prüft ein einziges Bit. Überlagen mit `Overlay_in_sky_bit` (Bit 6) werden in
der Kachelschleife übersprungen und erst nach der Gruppe gezeichnet.

**Türen funktionieren nochmal anders.** Sie verdecken die Figur nicht,
sondern lassen sie verschwinden: `Party_invisible_bit` (Bit 26). Steht die
Gruppe auf einer solchen Kachel, wird sie gar nicht gezeichnet — dadurch
wirkt sie hinter der Tür. Die Beobachtung "Türrahmen verdecken nicht" war
also richtig; sie verdecken tatsächlich nicht.

**Lehre:** `2D_MAP.S` und `3D_MAP.S` zuerst lesen, wenn es um
Anzeigeverhalten geht.

## 6. Was sich als richtig erwiesen hat


Nicht nur Fehler:

- **Amiga-Grafiken sind bereits zeilenverschachtelte Bitplanes** — dieselbe
  Anordnung wie beim Atari, nur mit weniger Ebenen. Keine Formatwandlung
  nötig, nur Ebenen auffüllen.
- **3D-Wandtexturen liegen schon in 8-Pixel-Spalten** vor, weil der
  Amiga-Renderer sie so brauchte. Das kommt dem Falcon-Zeichner entgegen.
- **Thalion hat auf dem Amiga bereits chunky gerendert** und danach
  gewandelt. Die für den Falcon geplante Architektur ist auf schwächerer
  Hardware erprobt.
- **Die Spiellogik ist hardwareunabhängig.** Von 50.723 Zeilen greift genau
  eine Datei auf Amiga-Hardware zu. Was fehlt, ist die Bibliotheksschicht.

## 7. Rückgabewerte, die niemand ansieht

> Gruppe **E** (Rückgabewerte), Regel in der Kurzform.

`Fread` meldet, wieviel wirklich gelesen wurde. Als eine Szenendatei mit
455 KB auf einen Puffer von 400 KB traf, wurde sie abgeschnitten geladen: die
vorderen Einträge kamen an, die hinteren Kacheln fehlten, und das Bild bestand
teils aus ungelesenem Speicher. Der Wert lag die ganze Zeit in `d0`.

**Lehre:** Jeder Rückgabewert, der eine Menge angibt, gehört geprüft — nicht
nur der, der einen Fehler anzeigt.


## 8. Der Stack wächst nach unten in die Variablen

> **Stand 2026-09-26:** Der eigene Stapel ging später wieder verloren: `start` setzte `sp` aufs BSS-Ende, bis 185.
>
> Gruppe **S** (Stapel), Regel in der Kurzform.

Der TOS-Startcode setzt den Stack üblicherweise ans Ende des
Speicherblocks. Liegt der Variablenbereich kurz davor, überschreibt der Stack
ihn nach wenigen Aufrufen. Das Fehlerbild ist charakteristisch: die *höchsten*
Variablenoffsets enthalten Müll, die niedrigen bleiben intakt.

Gekostet hat das einen halben Tag, weil es aussah wie ein Logikfehler im
Zeichner. Lösung: eigener Stack im Programm, mit Abstand zum
Variablenbereich.

## 9. Register als Parameter über Aufrufgrenzen

> **Stand 2026-09-26:** Überholt. „Parameter a5-relativ“ war die Regel des Nachbaus. Thalions Code übergibt in Registern, und die Bibliothek erfüllt seine Registerverträge (Gruppe V).
>
> Gruppe **R** (Register über einen Aufruf), Regel in der Kurzform.

Zweimal derselbe Fehler: Die gerufene Routine sichert ihre Register brav,
benutzt aber dieselben, die der Aufrufer als Parameter gedacht hatte.

Erst im Messprogramm (`a4` und `d6`), dann in der Engine (`d4` und `d6`).

Dritter Fall: `resolve_tile` zerstörte `d1` — und genau darin stand der
Kachelversatz, den der Aufrufer danach für die Überlage brauchte. Ergebnis:
Alle Kacheln lasen an derselben Stelle, der Boden war flächig mit Teppich
überzogen.

**Regel für dieses Projekt:** Parameter zwischen Routinen liegen a5-relativ,
Register nur innerhalb einer Routine. Jede Routine sichert ihre
Arbeitsregister; Ausnahmen sind ausdrücklich zu dokumentieren (bei
`resolve_tile` sind das `d0` als Ein- und Ausgabe und `a3` als Ausgabe).

## 10. movep ist auf dem 68060 eine Falle


Thalions Wandlung von chunky nach planar läuft über `movep`
(`Show_MOVEP_screen`). Auf dem 68060 existiert der Befehl nicht mehr in
Hardware und wird per Ausnahme nachgebildet: **achtmal langsamer als auf dem
030, trotz vierfachem Takt** — in Zyklen gerechnet rund fünfunddreißigmal
teurer.

## 11. Absolute Adressen in einem pc-relativen Programm

> **Stand 2026-09-26:** Überholt durch 122 und 130: Seit `vlink -b ataritos` trägt das Programm eine Verschiebetabelle, absolute Adressen sind richtig, und Thalions `dc.l <Marke>` braucht sie. `mktos.py` gibt es nicht mehr.

Derselbe Fehler zweimal, an ganz verschiedenen Stellen — und beide Male
wirkte er nicht wie ein Fehler, sondern wie eine fehlende Funktion.

Das Programm ist durchgehend pc-relativ übersetzt, und `mktos.py` legt eine
**leere Verschiebetabelle** an. Damit dürfen nirgends absolute Adressen
stehen. Zwei Schreibweisen erzeugen sie aber unbemerkt:

    move.l  d0,kbdv          | schreibt an die Adresse aus dem Linkerlauf
    .long   Map2D_L2         | trägt die Adresse aus dem Linkerlauf ein

Beides muss über den Programmzähler laufen:

    lea     kbdv(pc),a1      | und dann move.l d0,(a1)
    .long   Map2D_L2-Obj_tree | Abstand statt Adresse, Basis zur Laufzeit

Im Testprogramm für die Maus führte die erste Form zu Schreibzugriffen ins
Blaue und damit zu einer Reihe Bomben. Im Objektbaum führte die zweite dazu,
dass `Find_object` nie ein Objekt fand — Klicks blieben schlicht wirkungslos,
ohne Absturz und ohne Hinweis.

**Erkennbar** ist es im Ergebnis: `Find_object` mit den Koordinaten der
mittleren Taste liefert jetzt `3 5` — Tastenfeld, fünfte Taste. Vorher kam
nichts.

## 12. Aufrufe über trap zerstören Register

> Gruppe **R** (Register über einen Aufruf), Regel in der Kurzform.

Die Tastatur ließ das Programm hängen: die Taste erschien gedrückt, dann
ging nichts mehr, nur der Mauszeiger bewegte sich noch.

Die Warteschleife sah harmlos aus:

    move.w  #15,d1
    fb_w:   move.w #Vsync,-(sp)
            trap   #14
            bsr    Update_mouse
            dbf    d1,fb_w

**Aufrufe über `trap` dürfen d0 bis d2 und a0 bis a2 verändern** — das ist
die Aufrufkonvention von TOS. Der Zähler in d1 wurde von jedem `Vsync`
überschrieben, und `dbf` lief praktisch endlos.

Bei der Maus fiel es nicht auf, weil die dortige Warteschleife ohne Zähler
auskommt und nur den Tastenzustand prüft. Genau so beschrieb es der Bericht
vom Gerät: Tastatur hängt, Maus nicht.

**Regel:** Was einen `trap` überlebt, gehört in d3 bis d7 oder a3 bis a6.
Für Schleifenzähler um einen Systemaufruf herum ist d0 bis d2 unbrauchbar.

## 13. Ein Byte laden löscht nicht das Register

> Gruppe **W** (Oberes Wort, oberes Byte), Regel in der Kurzform.

Die Ereignislogik brachte das Programm zum Stehen, sobald Typ 14 auftrat.
`Access_bit_array` war es nicht — isoliert geprüft setzte es Bit 16450
punktgenau. Der Fehler lag im Aufrufer:

    move.b  (a0,d0.w),d1     | laedt nur das unterste Byte
    and.w   #0xFF,d1         | maskiert nur das untere Wort

Die **oberen sechzehn Bit von d1 bleiben stehen**, und `Access_bit_array`
rechnet mit `add.l d1,a1` — die Adressrechnung geht ins Leere. Beim
isolierten Test war d1 durch `moveq` sauber, deshalb fiel dort nichts auf.

Behoben an beiden Enden: die Aufrufer löschen das Register mit `moveq`,
bevor sie ein Byte hineinladen, und `Access_bit_array` maskiert zusätzlich
selbst. Zwei Vorkehrungen für denselben Fehler sind hier angemessen — die
Routine wird von jedem Ereignis gerufen, das etwas ändert.

**Regel:** Wer ein Byte oder Wort in ein Register lädt, das später in eine
Adressrechnung eingeht, löscht es vorher ganz.

# Thalions Quelltext einbinden (ab 121)

## 121. Was den Originalquelltext wirklich aufhält -- gezählt

Die Frage war: was hindert uns daran, Thalions Code unmittelbar zu
übersetzen? Gezählt über alle 40 Dateien und 50 723 Zeilen:

| | |
|---|---|
| Verschiedene Sprungziele | 685 |
| davon im Baum definiert | **600** |
| davon fehlend | **85** |
| Aufrufstellen gesamt | 4 385 |
| davon auf Fehlendes | 1 156 (26 %) |
| Offene `XREF` | 12 -- **alle Daten** |

Die 85 fehlenden Routinen sind sortenrein die Bibliothek: Speicherverwalter
(`Claim_pointer`, `Allocate_CHIP`, `Free_pointer`), Grafikprimitive
(`Draw_box`, `Put_masked_block2`, `Update_screen`), 3D-Renderer
(`Draw_floor`, `put_dpoly`), Dateizugriff (`Load_subfile`, `Decompress`),
Eingabe, Diagnose. **Der freigegebene Baum ist das Spiel; was fehlt, ist die
Hardwareschicht.**

Nach Anteil fehlender Aufrufe je Datei hängt die Geschäftslogik kaum daran:

```
COMBAT/MONSTER_.S  1093 Z.   0%      MODULES.S    1205 Z.   0%
FAIRY.S             858 Z.   0%      GAME_OFF.S   1850 Z.   0%
COMBAT/REVERSE_.S   687 Z.   1%      PERSONS.S    1254 Z.   5%
COMBAT/COMBAT_M.S  3354 Z.   6%      PLACES.S     1947 Z.  11%
MAGIC.S            2067 Z.  14%      COMBAT.S     3412 Z.  16%
EVENTS.S           3707 Z.  21%      INVENTOR.S   3527 Z.  30%
```

Drei Hindernisse, keins grundsätzlich:

1. **441 Stellen `dc.l <Label>`** -- absolute Adressen. Genau daran ist der
   Modulstapel gescheitert (Erkenntnis 119). Umschreiben scheidet bei 441
   Stellen aus. Es geht auch anders: **`vlink -b ataritos` erzeugt ein
   TOS-Programm mit Verschiebetabelle.** Nachgewiesen an einem Beispiel mit
   einem `dc.l` auf ein Label -- die Tabelle steht am Dateiende. Damit fällt
   die ganze Fehlerklasse weg, auch die des `lea vars(pc)`.
2. **Fünf Makros, 1 170 Stellen:** `Get` 427x, `Free` 389x, `Push` 136x,
   `Pop` 105x, `LOCAL` 57x. Ihre Definitionen liegen in einer nicht
   freigegebenen `.i`; es sind Einzeiler über den Speicherverwalter und die
   Stapel.
3. **`Screen_depth`, 31 Stellen,** oft in Rechnungen
   (`mulu.w #16*2*Screen_depth`). Amiga 5, Falcon 8 -- als Konstante
   durchgereicht kostet das Speicher, aber keine Codeänderung.

## 122. vlink -- die Verschiebetabelle als Voraussetzung

Der Umstieg vom selbstgebauten Programmkopf auf `vlink -b ataritos` ist die
Voraussetzung dafür, Thalions Quelltext zu übernehmen, und er hat sich in
drei Schritten als folgenlos erwiesen.

**Erstens** war das erste so gebundene Programm **byteweise dasselbe** wie
das von `mktos.py`: 41 738 Byte, `cmp` ohne Unterschied. Ein Umstieg, der
nichts ändert, kann auch nichts kaputtmachen -- das war ohne Emulatorlauf
zu beweisen.

**Zweitens** trägt es jetzt eine Verschiebetabelle. Nach dem Rücknehmen der
beiden Behelfe -- `lea vars,a5` statt des Umwegs über `lea .hier(pc)`, und
absolute `dc.l` in den Moduldeskriptoren statt der Abstände -- stehen genau
**sieben** Adressen darin: sechs Modulzeiger und `vars`. Beides lief im
Emulator unverändert durch.

Damit fallen zwei Fehlerklassen weg, die beide an einem Tag zugeschlagen
haben (Erkenntnis 119): die absolute Adresse in einer Tabelle, und der
PC-relative Versatz, der die 16-Bit-Grenze des 68000 sprengt. Im
Originalquelltext stehen **441 Stellen** der ersten Art.

**Drittens** gibt es jetzt echte Abschnitte. Die reservierten Puffer standen
bisher als `ds.b` im Codeabschnitt, und `-Fbin` schrieb sie als Nullbytes in
die Datei. Ein `SECTION bss,bss` davor genügte:

```
vorher   Text 41 696   BSS      0   -> Datei 41 724 Byte
nachher  Text 15 446   BSS 26 250   -> Datei 15 532 Byte
```

26 KB Nullen weniger. Der Start rechnete schon richtig damit -- er liest aus
der Basepage Text (12), Daten (20) **und BSS (28)** und setzt den Stapel
über alles; das stand seit jeher da und war nur nie gebraucht worden. Das
Original teilt genauso auf: `SECTION Fast_DATA,data` und
`SECTION Fast_BSS,bss` stehen am Ende fast jeder seiner Dateien.

## 123. Das Spiel fasst keine Amiga-Hardware an

Beim Zählen für Erkenntnis 121 fiel ein Nebenergebnis ab, das für die
Portierung mehr wiegt als die Zahlen selbst. Gesucht wurden direkte
Hardwarezugriffe -- `$dff...` (Amiga-Custom-Chips), `$bfe...` (CIA), die
Blitter-Makros, Aufrufe der Amiga-Bibliotheken:

```
$dff-Zugriffe im ganzen Baum:   10, alle in FAIRY.S
waitblit:                        3, alle in FAIRY.S
OpenLibrary / graphics.library:  0
```

**Eine einzige Datei von vierzig**, 858 von 50 723 Zeilen (1,7 %), und das
ist der Feeneffekt des Vorspanns -- Sprites, Copperliste, Blitter, in
anderem Stil geschrieben als der Rest.

> **BERICHTIGUNG, 2026-09-05 abends.** Es sind **zwei** Dateien, nicht eine.
> `HULL/VARIOUS.S` schreibt die Adresse symbolisch --
> `move.w #$000f,Custom+dmacon`, zweimal, um vor dem Entfernen der Musik die
> DMA-Kanäle abzuschalten. Eine Suche nach `$dff` findet das nicht.
>
> Erschwerend: `grep` hält genau diese Datei für binär und überspringt sie
> **stillschweigend** -- `grep -c "Custom" HULL/VARIOUS.S` gibt gar nichts
> aus, `grep -ac` findet zwei.
>
> Das Ärgerliche daran: **das stand seit Wochen in `docs/01`**, samt
> Warnung vor beiden Fallen (Erkenntnis 51). Ich habe die Zahl neu erhoben,
> statt sie nachzuschlagen, und bin in dieselbe Grube gefallen. Das ist
> heute der dritte Fall dieser Art -- siehe Erkenntnis 131.
>
> Der Schluss bleibt richtig, nur die Zahl war zu schön: 49 000 von 50 700
> Zeilen fassen keine Amiga-Hardware an, und beide Ausnahmen liegen dort,
> wo man sie erwartet -- im Vorspann und in der Musikabschaltung.

Das ist die eigentliche Nachricht: die Trennung, die eine Portierung
braucht, ist im Quelltext bereits gezogen. Nicht als Absicht dokumentiert,
aber sauber durchgehalten.

## 124. Thalions GAME_OFF.S im Bau -- und als Prüfer

Der erste Originalquelltext liegt im Programm, unverändert:

```
	INCLUDE	"vorspann.i"
	SECTION	text,code
	INCLUDE	"GAME_OFF.S"		; Thalions, ueber -I gefunden
	INCLUDE	"src/GAME_OFF.S"	; unsere Ergaenzungen
```

Die Wahl der ersten Datei war nicht beliebig. `GAME_OFF.S` ist die einzige
mit 1850 Zeilen und **keinem einzigen Befehl** — nur `rsreset`-Ketten und
Konstanten. Sie kann nichts kaputtmachen und beschreibt alles: Charaktersatz,
Objektpaket, Karten, Ereignisse, Kampf, die Farben der Hauptpalette.
955 Symbole.

Zwei Dinge mussten vorher stimmen. Der Vorspann (`tools/originalcode/`,
seit August) ersetzt die nicht freigegebene Bibliotheks-Includedatei, und
vlink schreibt die Verschiebetabelle (Erkenntnis 122). Das dritte war
Glück: **keine einzige Namenskollision.** 955 Symbole von Thalion, 941 von
uns, kein Überschneiden -- seine sind englisch, unsere deutsch. Hätte ich
damals englische Namen gewählt, stünde hier jetzt eine Umbenennungsaktion.

Der Gewinn ist nicht der Platz, den es spart, sondern was danach möglich
ist. Am Ende von `src/GAME_OFF.S` steht jetzt:

```
pruefe	macro
	IFNE	\1-(\2)
	FAIL	"\1 weicht von Thalions \2 ab"
	ENDC
	endm

	pruefe	CH_PKT,Object_packet_size
	pruefe	CH_INV,Char_inventory
	pruefe	CH_KOERPER*CH_PKT,Backpack_slots
	pruefe	IB_MULTIPLE,Multiple
	pruefe	WINDOW_COLOUR-UI_BASE,Window_colour
	...
```

Dreizehn Proben, die beim Übersetzen abbrechen, wenn ein Wert abweicht.
Alle dreizehn gehen durch -- die von Hand abgeschriebenen Werte waren also
richtig.

Beim Schreiben hat der Prüfer gleich eine Grenze gezogen, die ich
verwischen wollte: `pruefe OBJ_BITS,Item_bits_STATIC` schlug fehl, 2 gegen
32. **Beide sind richtig.** Unsere Objekttabelle ist auf acht Byte je
Eintrag zusammengezogen, Thalions Satz hat sechzig; die beiden beschreiben
nicht dieselbe Sache. Die Probe dafür gehört an die Stelle, die zwischen
den Formaten umrechnet -- also in den Konverter, und genau dort saß der
Fehler von gestern (Erkenntnis 116).

`tools/ambchest.py` liest jetzt Thalions `rsreset` und rechnet die
`ITEM_*`-Versätze nach. Mit absichtlich falschem Wert:

```
ITEM_BITS_STATIC ist 33, Thalions Item_bits_STATIC liegt auf 32
```

Genau der Fehler, den ich einen Tag zuvor nur bemerkt habe, weil hinterher
kein einziger von 402 Gegenständen mehr stapelbar war. Er ist jetzt Teil
des Bauvorgangs.

**Was ich daraus mitnehme:** ein übernommener Wert ist nicht dasselbe wie
ein geprüfter Wert. Solange ich Versätze abschreibe, sind sie Meinung; erst
wenn die Originaldatei im Bau liegt und dagegenrechnet, sind sie Tatsache.
Und das gilt weit über diese dreizehn hinaus -- jede weitere Datei, die wir
übernehmen, bringt ihre eigenen Proben mit.

## 125. Die erste Originaldatei mit Code

> Gruppe **P** (Nachgebaut statt übersetzt), Regel in der Kurzform.

Nach `GAME_OFF.S` (nur Definitionen) jetzt `HULL/NUMERIC.S` -- 341 Zeilen,
sieben Routinen, echter Code. Unser Nachbau hatte zwei davon und wich in
beiden vom Original ab:

| | Original | Nachbau |
|---|---|---|
| `DecR_convert` Stellenzahl | `d7` | fest 3 |
| `DecR_convert` Füllzeichen | `d6` | fest Leerzeichen |
| Rückgabe `a0` | zeigt auf den Abschluss | unverändert |
| Abschlussbyte | wird geschrieben | keins |

**Angepasst wurden die Aufrufstellen, nicht die Datei.** Das ist die Regel,
und sie hat sich hier zum ersten Mal ausgezahlt: `ostr` trägt drei Zahlen in
einer Zeile, und Thalions Abschlussbyte hätte die Zeile nach der ersten
abgeschnitten. Die Lösung steht im Vertrag selbst -- `a0` zeigt hinterher
auf den Abschluss, also den Trenner dort wieder hinschreiben. Bei `xstr` und
`ystr` fällt er ohnehin genau auf die Null, die dort schon steht.

Drei Dinge, die dabei aufgefallen sind:

**Ein Fehler in Thalions Quelltext.** Die Gewichtstabelle beginnt mit

```
	dc.l 10000000000
Weights:	dc.l 1000000000,...
```

Zehn Milliarden passen nicht in 32 Bit; vasm meldet es sofort. Das ist die
Obergrenzenprüfung für zehnstellige Zahlen, und abgeschnitten steht dort
1410065408. Devpac hat damals genauso abgeschnitten -- der Fehler steckte
also im ausgelieferten Spiel. **Nicht angefasst.** Thalions Dateien bleiben,
wie sie sind; sonst ist der Vergleich mit dem Original nicht mehr eindeutig.

**Abschnittsnamen.** Jede Datei des Originals endet mit
`SECTION Fast_DATA,data` und `SECTION Fast_BSS,bss`, der Code steht in
`Program`. Zwei davon in einem Programm zu haben ging schief: ein
PC-relativer Bezug über eine Abschnittsgrenze liess sich nicht binden
(`INTERNAL ERROR: calc_relocs`). Die Lösung ist, Thalions Namen zu
übernehmen und vlink sie abbilden zu lassen:

```
vlink -b ataritos -s -N Program .text -N Fast_DATA .data -N Fast_BSS .bss
```

Das gilt ab jetzt für jede weitere Datei.

**Der Registerprüfer hat mitgedacht.** Weil `DecR_convert` nun `d6` und `d7`
verlangt, setzt `Display_coordinates` beide -- und sicherte sie nicht.
`tools/register_pruefen.py` meldete es, bevor es jemand am Bild bemerkt
hätte.

**Nachgemessen im Emulator.** Statt am Bildschirmabzug zu raten, schreiben
die Routinen ihre Ergebnisse über `Cconws` in die Konsole:

```
NUM [..7]      DecR 7,    Fuellzeichen ".", 3 Stellen
NUM [421]      DecR 421,  3 Stellen
NUM [***]      DecR 5000, 3 Stellen -- zu gross
NUM [421]      DecL 421,  5 Stellen
NUM [0]        DecL 0
NUM [-   42]   SDecR -42, 5 Stellen
```

Alle sechs richtig. Am Rande: der Testaufbau hat mich zweimal in die Irre
geführt, bevor er funktionierte -- die Ausgabe kam erst nach `Open_screen`
und landete im Grafikbildschirm, und danach filterte `teste.sh` sie weg,
weil mein Präfix mit Leerzeichen begann. **Der Prüfaufbau war jedes Mal der
Fehler, nicht der Code.** Das war heute schon einmal so (Erkenntnis 119, der
falsche Maßstab des Abzugs).

## 126. Der Objektbaum -- und was der Nachbau ausgelassen hatte

> Gruppe **P** (Nachgebaut statt übersetzt), Regel in der Kurzform.

Dritte Originaldatei: `HULL/OBJECT.S`, 135 Zeilen. Unser Nachbau hatte zwei
seiner fünf Routinen (`Find_object`, `Search_layer`) und ließ drei weg --
`Push_Tree`, `Pop_Tree`, `Reset_tree_stack`. Das war kein Versehen, sondern
eine Vereinfachung: unser `Find_object` griff den Baum unmittelbar mit
`lea Obj_tree(pc),a0`. Damit gibt es genau einen Baum, für immer.

Das Original führt einen **Stapel**, aus demselben Grund wie beim
Modulstapel: ein Fenster bringt seinen eigenen Baum mit. `Open_window` tut
beides in drei Zeilen:

```
	move.w	d0,(a0)			; Fensterecke in den Baumkopf
	move.w	d1,2(a0)
	jsr	Push_Tree
```

Damit stimmen die Klickflächen eines Dialogs unabhängig davon, wo er steht.
Unser Mengendialog vergleicht dafür bisher von Hand Koordinaten
(`cmp.w #NR_X+111,d0` und so weiter) -- und der Baum dazu steht im Original
längst da, `InputNr_L1`/`InputNr_L2` in `HULL/CONTROLS.S`, mit den Kennungen
1 = Pfeil hoch, 2 = Pfeil runter, 3 = OK.

**Der Baumkopf war die eigentliche Entdeckung.** Ein Baum beginnt mit zwei
Worten Versatz; `Find_object` zieht sie ab:

```
	move.l	(a0),a0
	sub.w	(a0)+,d0
	sub.w	(a0)+,d1
```

Unser Nachbau hatte den Kopf nicht -- und es fiel nicht auf, weil unser
eigenes `Find_object` ihn auch nicht erwartete. Zwei Fehler, die einander
deckten. Beim Übernehmen der Originaldatei fällt so etwas sofort auf.

Die Versätze `Obj_X1` bis `Obj_child` stehen **nicht** im freigegebenen
Quelltext; sie lagen in der Bibliotheks-Includedatei und mussten in
`vorspann.i`. Geraten ist daran nichts -- drei Stellen legen sie fest: das
wörtliche `move.b 8(a0),d2` in `Search_layer`, der echte Baum `InputNr_L1`
mit seinem `dc.w 0,0 / dc.w 0,143,0,63 / dc.b 1 / even / dc.l 0,InputNr_L2`,
und `Open_window`, das den Kopf schreibt. Ergebnis: X1=0, X2=2, Y1=4, Y2=6,
Kennung=8, Bruder=10, Kind=14, Größe=18 -- genau das, was ich damals aus dem
Verhalten abgeleitet hatte.

Am Rande eine zweite Unstimmigkeit im Original: `Default_Tree` in
`HULL/OBJECT.S` hat diesen Kopf **nicht**. Seine ersten beiden Worte (0 und
319) werden als Versatz gelesen, damit ist Y immer negativ und
`Find_object` findet darin nie etwas. Nicht angefasst.

**Nachgemessen im Emulator**, mit Thalions `Hex_convert` aus NUMERIC.S für
die Ausgabe:

```
OBJ $00020200   (100,100) Kartenfeld -- Ebene 1 = 2, Ebene 2 = 2
OBJ $00020101   (220,150) Taste 1
OBJ $00020109   (290,185) Taste 9
OBJ $00020000   (0,0)     nur die erste Ebene
```

Alle vier wie vorausberechnet.

**Und noch einmal der Prüfaufbau statt des Codes.** Ich hielt den Lauf für
hängengeblieben, weil nach einer Minute nichts kam, und habe den Emulator
abgeschossen. Er war nur langsamer als meine Geduld -- das Ergebnis stand
danach vollständig da. Das ist heute der vierte Fall dieser Art
(Erkenntnisse 119 und 125): **der Messaufbau war jedes Mal der Fehler, nie
der Code.**

## 127. Der Speicherverwalter -- Handles, nicht Zeiger

`HULL/CONTROLS.S` zu übernehmen scheiterte nicht an der Datei, sondern an
dem, was unter ihr fehlt. 21 ihrer Aufrufziele gibt es im freigegebenen
Quelltext nicht; acht davon hatten wir schon, dreizehn nicht. Der Kern
dieser dreizehn ist der Speicherverwalter.

Sein Vertrag steht nirgends geschrieben, aber `Create_string_graphics`
benutzt ihn vollständig und in einem Stück -- das genügt:

```
	jsr	Allocate_CHIP		; d0 = Groesse -> d0 = Handle
	jsr	Clear_memory		; d0 = Handle
	jsr	Claim_pointer		; d0 = Handle -> d0 = Adresse
	Get	d4,a0			; = Claim_pointer nach a0
	Free	d4			; = Free_pointer
	jsr	Free_pointer
	jsr	Free_memory
```

**Handles, keine Zeiger** -- das ist der Punkt, an dem ein Nachbau
auseinanderfällt. Auf dem Amiga durfte die Bibliothek einen nicht
festgenagelten Block verschieben, um Lücken zu schließen; `Claim_pointer`
nagelt fest, `Free_pointer` gibt wieder frei. Über hundert Aufrufstellen im
Originalquelltext arbeiten so.

Bei uns verschiebt nichts, also ist `Free_pointer` leer. Die Routine bleibt
trotzdem stehen: die Aufrufstellen rufen sie, und ein späterer Verdichter
passt genau dort hinein, ohne dass eine einzige Aufrufstelle sich ändert.
`Allocate_CHIP` wird `Mxalloc` mit Modus 0 -- auf dem Amiga heißt „was der
Grafikchip lesen muss" Chip-RAM, auf dem Falcon ST-RAM, und VIDEL liest
nichts anderes.

**Nachgemessen im Emulator**, mit Thalions `Hex_convert` für die Ausgabe:

```
MEM $00010001   erstes Handle
MEM $00018600   Adresse, auf 256 ausgerichtet
MEM $00010002   zweites Handle
MEM $CAFEBABE   geschrieben, ueber Claim_pointer zurueckgelesen
MEM $00000000   nach Clear_memory
MEM $000007D0   Get_memory_length = 2000
MEM $00010001   nach Free_memory wieder das erste Handle
```

Das obere Wort des Handles war Rest aus `trap #1` -- geräumt. Thalions
Aufrufstellen holen es ohnehin mit `move.b`, aber eine Zahl, die aussieht
wie 65537 und 1 bedeutet, wartet nur auf ihren Fehler.

## 128. Fünfmal die Geduld verloren, nie den Code

> Gruppe **M** (Messaufbau vor Befund), Regel in der Kurzform.

Der peinlichste Befund des Tages, und er gehört aufgeschrieben, weil er
teuer war.

Fünfmal habe ich heute einen Emulatorlauf für gescheitert erklärt, und
fünfmal lag es am Messaufbau:

1. Bildschirmabzug im falschen Maßstab gelesen -- Hatari schreibt 640x480,
   der Falcon zeigt 320x200. Marken bei x=8 gesucht, die bei x=16 lagen.
2. `Wait_4_unclick` in `Push_Module` gesetzt, weil das Original dort
   `Reset_mouse_buffer` ruft -- das eine wartet, das andere verwirft.
3. Konsolenausgabe nach `Open_screen` gesetzt; sie landete im
   Grafikbildschirm statt in der Konsole.
4. Präfix `"  ["` gewählt -- `teste.sh` filtert Zeilen, die mit Leerzeichen
   beginnen.
5. Zwei Läufe für hängengeblieben erklärt und den Emulator abgeschossen.
   Beide waren nur langsamer als meine Geduld; die Ergebnisse standen
   danach vollständig da.

**Ein Lauf braucht drei bis fünf Minuten, nicht neunzig Sekunden.** Und
`timeout` auf `teste.sh` beendet das Skript, nicht den Emulator darunter --
was danach als „hängt noch" aussieht, ist ein verwaister Prozess.

Der Code war in keinem der fünf Fälle schuld.

## 129. Die Bibliotheksschicht, Stück für Stück

Dreizehn Routinen fehlten für `HULL/CONTROLS.S`. Sie sind jetzt da, in
drei Gruppen -- und die Verträge kamen alle aus den Aufrufstellen, keiner
aus der Luft.

**Drei sind Sonderfälle von etwas, das wir hatten.** `Draw_rectangle` ruft
`Draw_hline` und `Draw_vline` mit *denselben Registern* wie `Draw_box`:
zwei Ecken und eine Farbe. Eine waagerechte Linie ist ein Rechteck von
einer Zeile Höhe. Das Original hält sie getrennt, weil sein `Draw_box`
über den Blitter geht und für eine Linie zu schwer wäre; bei uns kostet
der Sonderfall nichts.

**`Put_masked_silhouette` war die einzige, bei der ich unsicher war** --
und das zu Unrecht. Die drei Aufrufstellen sagen dasselbe:

```
DISPLAY.S   moveq #5,d5  ... jsr Put_masked_block2     ; Symbol, 5 Ebenen
DISPLAY.S   moveq #26,d4 / moveq #1,d5 / jsr Put_masked_silhouette
AUTOMAPP.S  moveq #Automap_ink_colour,d4 / moveq #1,d5
ACTIONS.S   moveq #0,d4 / moveq #1,d5
```

**d5 ist die Ebenenzahl der Quelle, d4 die Farbe.** Eine Silhouette ist
eine einzelne Bitebene, in einer Farbe gemalt; die Form ist ihre eigene
Maske.

Gegengeprüft am übersetzten Original -- und dabei ist nebenbei eine
Methode entstanden, die künftig jede unklare Bibliotheksroutine
beantwortet:

1. Thalions `HULL/NUMERIC.S` übersetzt und ihre Bytes in `AM2_CPU`
   gesucht -> **70 Byte am Stück identisch**, Hunk 0 ab `0x27508`. Der
   freigegebene Quelltext lässt sich im ausgelieferten Programm
   wiederfinden.
2. Nach dem Muster `moveq #1,d5 ; jsr abs.l` gesucht -> genau ein Ziel,
   dreimal gerufen: `$00022ad2`.
3. Dort steht:

```
48e7 fff6      movem.l  d0-d7/a0-a2/a4-a6,-(sp)
4df9 00dff000  lea      $00dff000,a6      ; Amiga-Custom-Chips
...
4a45           tst.w    d5                ; Ebenenzahl
6d00 019e      bmi      raus
ba7c 0005      cmp.w    #5,d5             ; gegen Screen_depth
6e00 0196      bgt      raus
```

Der Vertrag bestätigt sich am Maschinencode. Die *Umsetzung* nützt uns
nichts -- sie ist Blitter --, aber darum ging es nicht.

**Die Bereichsstapel waren die eigentliche Änderung.** Unser `Push_MA`
nahm vier Kanten in d0-d3 und hatte keinen Stapel. Thalions nimmt einen
Satz in a0, und `Open_window` gibt PA und MA *dieselbe* Adresse:

```
	lea.l	Window_area(a4),a0
	jsr	Push_MA
	jsr	Push_PA
```

Die ersten vier Worte einer Print-Area sind ihre Kanten -- deshalb geht
das. Dasselbe Muster wie beim Modul- und beim Baumstapel, zum dritten
Mal: ein Fenster bringt seinen Bereich mit, der Bildschirm darunter muss
nichts davon wissen.

Im Emulator geprüft, alle sieben Werte richtig: zwei Print-Areas
aufgelegt, die obere gilt, nach `Pop_PA` wieder die untere; `Default_MA`
liefert 304 = 320 − Zeigerbreite; `Strlen` zählt elf.

**Ungeprüft geblieben:** `Get_block` und `Put_masked_silhouette` brauchen
ein Bild und lassen sich nicht über die Konsole nachmessen.

## 130. `bsr` reicht nicht mehr, und PC-relativ ins BSS erst recht nicht

Beim Bauen des Prüflaufs brach vlink ab:

```
Error 35: Calculated value 0x80b8 doesn't fit into relocation type R_PC
          (offset=0, size=16)
```

`0x80b8` ist 32 952 -- größer als das ganze Textsegment. Der Verweis geht
also nicht innerhalb des Codes, sondern **aus dem Code ins BSS**, und das
liegt hinter Text und Daten.

Der Übeltäter war `lea mousebg(pc),a0`, und siebzehn weitere Stellen
derselben Art standen daneben: `procbuf`, `pastack`, `memtab`, `vars`.
Sie funktionierten, solange das BSS nah genug lag. Mit jeder neuen
Originaldatei rückt es weiter weg.

Behoben, indem alle zwanzig absolut wurden -- seit vlink bindet, kostet
das nichts als einen Eintrag in der Verschiebetabelle. **PC-relativ ist
seit dem Umstieg kein Vorteil mehr, sondern nur noch eine Grenze.**

Dasselbe gilt für `bsr` quer durchs Programm: der Sprung vom Anfang von
`MAIN.S` an sein Ende ging beim Prüflauf ebenfalls nicht mehr. Dort hilft
`jsr`. Beides fällt beim Gegenlauf mit `-m68000` auf, nicht auf dem
68030 -- ein weiteres Mal, dass das zweite Zielsystem den Fehler findet.

## 131. Erst im eigenen Werkzeug nachsehen

Für `HULL/CONTROLS.S` fehlen vierzehn Datensymbole. Bei den vier
Grafiken -- `Button_up`, `Button_down`, `Control_icons`, `Chequered` --
habe ich die Suche von vorn begonnen: Formate aus den Zeichenroutinen
abgeleitet (32x17 und 32x13, drei Ebenen, Farbbasis 24), aus einem
Speicherauszug einen Tastenausschnitt zurückgerechnet und in `AM2_CPU`
gesucht.

Kein Treffer -- unter keiner von zwölf durchprobierten Kombinationen aus
Ebenenzahl, Farbbasis und Speicherordnung. Die Erklärung schien
naheliegend: der Bildschirm zeigt die Taste *mit dem Symbol darauf*, also
nicht `Button_up` allein. Also den Truhenbildschirm genommen, der leere
Tasten hat. Wieder nichts.

**Dabei stand die Antwort seit Wochen in `tools/falcon_gfx.py`:**

```
# Tastenfeld.  Rahmen aus AM2_CPU (Hunk 3, 0x2860), Symbole aus
# Button_graphics.  Lage aus der Tabelle Icon_pos in CONTROLS.S:
# drei mal drei ab (208,143), Abstand 32 und 17.
BTN_ADDR = 0x2860
BTN_DOWN_ADDR = BTN_ADDR + (BTN_W // 8) * 3 * BTN_H
```

`Button_up` liegt bei Hunk 3, `0x2860`, `Button_down` unmittelbar
dahinter, und `Control_icons` ist die Spieldatei `Button_graphics` --
kein Programmdatum. Deshalb war es in `AM2_CPU` nicht zu finden. Die
Symbolnummern waren sogar schon am Speicherauszug bestätigt, mit hundert
Prozent Übereinstimmung.

**Was ich daraus mitnehme:** bevor ich etwas aus dem Original herleite,
gehört die Frage gestellt, ob wir es schon hergeleitet haben. Der
Konverter ist zum Nachschlagewerk geworden, ohne dass ich ihn so behandelt
hätte.

`Chequered` ist damit auch geklärt: `Do_control_icons` prüft
`btst.b #7,(a2)` -- das Sperrbit einer CIL -- und legt bei gesperrten
Tasten `Chequered` darüber. Es ist die Schraffur, also eine Silhouette
(eine Bitebene), passend zu `Put_masked_silhouette`.

## 132. Was für CONTROLS.S noch fehlt -- der Stand

Die Bibliotheksschicht steht (Erkenntnis 129). Die vierzehn Datensymbole
zerfallen in drei sehr ungleiche Gruppen:

**Vier Grafiken -- Quellen bekannt, nur die Verpackung fehlt.**
`Button_up`/`Button_down` aus Hunk 3 ab `0x2860`, `Control_icons` aus
`Button_graphics`, `Chequered` noch zu suchen. Unser Konverter setzt
daraus heute **fertige Tastenfelder** zusammen, 96x51 in acht Ebenen;
Thalions Code will die Teile **einzeln** und legt sie selbst übereinander.
Zu tun ist also nicht Suchen, sondern Umpacken -- und dabei fällt Arbeit
weg, nicht an: `baue_pad` und `baue_gedrueckt` verschwinden.

**Sechs Texte.** `Prompts` und `Text_list` sind Textdateien im Format, das
`Find_large_text` erwartet (Wortzahl, dann Blocklängen); dazu vier feste
Zeichenketten für Fehler- und Diskettenmeldungen. Aus den Spieldateien
noch nicht gezogen.

**Vier Moduldeskriptoren** -- `TxtW_Mod`, `Req_Mod`, `DiskReq_Mod`,
`Continuous_Mod`. Das sind unsere Daten, in unserem 14-Byte-Format
geschrieben, für Bildschirme, die es noch nicht gibt. Klein.

Dazu die fünf Kollisionen: `Feedback`, `Draw_standard_box`,
`Display_up_button`, `Display_down_button`, `Draw_scroll_bar` müssen
unsererseits weichen, und ihre Aufrufstellen auf Thalions Verträge
umgestellt werden -- `Display_up_button` etwa nimmt die Symbolnummer in d3
und die Lage in d0/d1, unseres die Tastennummer eins bis neun in d0.

## 133. Die Tasten setzt jetzt die Engine zusammen

Der Konverter baute bisher **fertige Tastenfelder**: neun Rahmen mit ihren
Symbolen darauf, 96x51, sechs Stück, dazu die neun gedrückten Tasten je
Feld einzeln. Die Engine kopierte daraus. Thalions Code arbeitet umgekehrt:

```
Display_up_button:
	lea.l	Button_up,a0 / jsr Put_unmasked_block
	lea.l	Control_icons,a0
	and.w	#$007f,d3 / tst.b d3 / bne .Notzero
	move.w	#Empty_cicon,d3
.Notzero: subq.w #1,d3 / mulu.w #13*12,d3 / add.w d3,a0
	addq.w	#2,d1 / jsr Put_masked_block2
```

Rahmen deckend, Symbol maskiert darauf, zwei Zeilen tiefer -- bei der
gedrückten Taste vier.

**Der Tausch war ein Nettogewinn.** Weg sind: `baue_pad` und
`baue_gedrueckt` im Konverter, die sechs vorgefertigten Felder (Eintrag 7),
die gedrückten Tasten (Eintrag 14), `p_pad`, `p_btndn`, das Nachziehen in
`Set_icon_bank`, und in `Dialog_taste` das Ausschneiden mit
`Put_block_stride`. Dazu kommen: `Icon_pos`, sechs CIL-Tabellen zu neun
Worten, `Display_control_icons`. Die Szenendatei schrumpfte um 29 KB.

Dazu kam etwas, das mit fertigen Feldern gar nicht ginge: das Sperrbit.
`Do_control_icons` prüft `btst.b #7,(a2)` je Taste und legt bei gesperrten
die Schraffur darüber -- in einem vorgefertigten Bild ist dafür kein Platz.

**Die Symbolnummern wandern damit aus dem Konverter in die Engine**, wo sie
hingehören. Im Original stehen sie in den CILs neben den Vektoren
(`M2_CIL` in MAP/2D_MAP.S); bei uns vorerst nur die Nummern, die Vektoren
ersetzt noch `Map_CIL_evaluate`.

**Nachgemessen gegen den Amiga**, Tastenfeld 96x51 = 4896 Punkte:

```
Original-Index -> unsere Farbe        Punkte
   0 -> (0,0,0)                          45
  26 -> (32,32,32)                      887
  27 -> (69,69,52)                      817
  28 -> (101,101,85)                   1930
  29 -> (138,138,117)                   318
  30 -> (170,170,154)                   120
  31 -> (203,203,186)                   779
```

Jeder Index bildet auf **genau eine** Farbe ab, ohne Ausnahme. Der erste
Vergleich sah nach 99 % Abweichung aus -- bis mir auffiel, dass ich RGB
gegen RGB hielt: der Auszug steht auf einer Karte mit bräunlicher Palette,
unsere UI-Farben kommen aus der Statuspalette und sind grau. Die
*Zeichnung* ist punktgenau, nur die Palette eine andere. **Wer Farben
vergleicht, wo Indizes gemeint sind, misst die Palette statt des Bildes.**

## 134. Der Ladepuffer lief still voll

Nach dem Umbau meldete die Engine "Karte nicht gefunden". Kein Absturz,
keine Fehlermeldung des Dateisystems -- die Datei war schlicht zu gross:

```
	cmp.l	#FILEMAX,d6		; Puffer randvoll?  Dann war er zu klein
	bcc	lm_fail
```

`FILEMAX` war 640 KB, die Szenendatei mit den einzelnen Tastenteilen 690.
Die Prüfung ist richtig und die Meldung irreführend: "randvoll" heisst
"abgeschnitten", nicht "nicht gefunden". Angehoben auf 1 MB.

Bemerkenswert ist der Zeitpunkt: die Datei war schon vorher nah an der
Grenze, und dieser Umbau hat sie am Ende *verkleinert* -- die 39 KB der
Einzelteile kamen dazu, bevor die 68 KB der fertigen Felder wegfielen. Wer
zwischendurch gemessen hätte, hätte einen Zuwachs gesehen, der nie von
Dauer war.

## 135. Text.amb trägt drei Blöcke in drei Formaten

Die sechs Textsymbole, die `HULL/CONTROLS.S` braucht, liegen alle in
`Text.amb`. Sie zu finden war aufwendiger als nötig, weil die Datei nicht
einheitlich aufgebaut ist:

```
0x0002    46 Texte, Tabelle aus **Versaetzen**  -- Disketten- und
          Fehlermeldungen ("Bitte legen Sie Diskette ")
0x05d8   300 Texte, Tabelle aus **Laengen**     -- Prompts
0x379e    31 Texte, nur NUL-getrennt            -- Ereignisnamen
          ("Raetselmund", "Teleporter", "Falltuer")
```

Der mittlere Block ist genau das, was `Find_large_text` erwartet:

```
	move.w	(a0)+,d7		; Anzahl
	move.l	a0,a1			; Laengentabelle
	add.w	d7,d7 / add.w d7,a0	; ueber die Tabelle
.Loop:	add.w	(a1)+,a0
```

**Er wandert unverändert in die Szenendatei** -- kein Umpacken, nicht
einmal ein Kopf. Das ist das erste Stück Spieldatei, das die Engine im
Originalformat liest.

Die Nummerierung ist damit belegt, nicht geraten. Sechs Nummern, die der
Quelltext nennt, treffen alle:

```
 42  "Dieser Gegenstand ist verflucht!"     Unequip_item
 54  "Wieviele nehmen?"                     Move_backpack_item
 60  "Programm wirklich verlassen?"         Quit_game
 84  "Welcher Gegenstand soll in die Truhe gelegt werden"
 85  "Wieviele verstauen?"                  Drop_item_CHEST
 91  "Die Truhe ist voll."
```

Nummer 54 stand bei uns als `dc.b "WIEVIELE NEHMEN?"` im Quelltext. Sie ist
jetzt weg; der Dialog schlägt die Meldung nach. **Das ist das zweite
Leitziel in klein** -- Originaldateien zur Laufzeit lesen statt vorher
umzuwandeln.

Zwei Umwege auf dem Weg, beide vermeidbar:

**Erstens** habe ich die Datei naiv an NULs zerteilt und dabei 1173 Texte
gezählt statt 300 -- die drei Blöcke laufen ineinander, und ohne die
Tabellen ist die Numerierung Zufall. Erst das gezielte Suchen nach einer
bekannten Zeichenkette ("verflucht") hat den richtigen Block gefunden.

**Zweitens** hat der Nutzer zu Recht gefragt, ob im Projekt nicht schon
etwas zu den `.amb`-Dateien stehe. Steht es -- aber zu `Text.amb` nur
"Texte und Wörterbuch, Struktur", ohne Format. Diesmal war Nachsehen
richtig und hat nichts gespart; beim vorigen Mal (Erkenntnis 131) hätte es
eine Stunde gespart. Die Frage lohnt sich trotzdem jedes Mal.

## 136. Der Druck war gezeichnet, nur nicht sichtbar

Der Nutzer meldete: die Tasten sind funktional, aber der gedrückte Zustand
erscheint nicht. Die Ursache stand in der Datei, die ich gelöscht hatte.

Unsere alten `Display_up_button` und `Display_down_button` endeten mit
`bsr Button_zeigen` -- und `Button_zeigen` war seit einem früheren Umbau
nur noch `bra Update_screen`. Sie brachten die Taste also selbst auf den
Schirm. Thalions Fassungen tun das nicht; dort steht es beim Aufrufer:

```
	jsr	Display_down_button		; Down
	jsr	Update_screen
```

Beim Übernehmen des Originalvertrags ist der Aufruf zwischen den Stühlen
verlorengegangen: die neuen Routinen zeichnen in den Puffer, und niemand
brachte ihn nach vorn. Der Druck war da -- nur unsichtbar, bis das nächste
Vollbild kam.

**Was das lehrt:** beim Übernehmen einer Originalroutine muss man nicht nur
sie selbst ansehen, sondern auch, was der Aufrufer dort tut. Der Vertrag
einer Routine endet nicht an ihrem `rts`.

`Button_stelle` und `Button_zeigen` sind jetzt weg; die Lage steht in
`Icon_pos`, das Sichtbarmachen beim Aufrufer.

## 137. CONTROLS.S versucht -- und was dabei sichtbar wurde

> **Stand 2026-09-26:** Nachgeholt: `HULL/CONTROLS.S` ist seit Stufe 3b eingebunden (161, 165, 167).

Der Versuch, `HULL/CONTROLS.S` einzubinden, ist gescheitert, und das
Scheitern ist der Ertrag: es hat eine Grenze gezeigt, die ich vorher nicht
gesehen hatte.

Meine Schätzung waren **14 offene Datensymbole**. Das Binden nennt **57**:

| | |
|---|---|
| Variablen | 17 |
| Daten | 10 |
| fehlende Routinen | 6 |
| Moduldeskriptoren | 4 |
| AmigaDOS-Fehlerkonstanten | 19 |
| unser Rest | 1 |

Die Schätzung war zu klein, weil sie nur die `XREF`-Zeilen zählte. `XREF`
nennt nur, was der Autor ausdrücklich als extern deklariert hat; alles
andere -- Variablen, Konstanten -- taucht erst beim Binden auf. **Eine
Vorabzählung über `XREF` misst die Absicht, nicht die Abhängigkeit.**

Die 19 Fehlerkonstanten sind Kleinkram für den Vorspann. Die vier Module
und die sechs Routinen sind Arbeit, aber gewöhnliche. Die beiden anderen
Gruppen sind es nicht:

**Siebzehn Variablen, und der Unterschied ist grundsätzlich.** Thalion
greift absolut zu:

```
	move.w	Mouse_Y,d6
	move.w	#26,Shadow_colour
	btst	#Right_pressed,Button_state
```

Unsere liegen in einem Block, auf den a5 zeigt: `mouse_y(a5)`,
`v_shadow(a5)`, `mbutton(a5)`. Das war richtig, solange kein Fremdcode
mitlas -- ein Register spart bei jedem Zugriff zwei Byte. Jetzt kostet es:
Thalions Code kann a5 nicht kennen.

Das ist kein Fehler, sondern eine Entscheidung, die zurückgenommen werden
muss. Seit vlink bindet, sind absolute Globale gratis; das a5-Modell war
eine Anpassung an die fehlende Verschiebetabelle, und die gibt es nicht
mehr (Erkenntnis 122).

**Zehn Datensymbole, und der Unterschied ist ebenso grundsätzlich.**
Thalion hat `Control_icons`, `Prompts`, `Button_up` einkompiliert -- feste
Adressen. Bei uns kommen sie aus der Szenendatei und stehen erst zur
Laufzeit fest; die Engine merkt sie sich in `p_cicon`, `p_prompt`. Ein
`lea.l Control_icons,a0` kann darauf nicht zeigen.

Auflösbar auf zwei Weisen: entweder feste Puffer, in die der Lader
hineinkopiert, oder ein Umschreiben der Zugriffe. Das erste erhält Thalions
Zeilen unverändert und kostet Speicher; das zweite widerspricht dem
Leitziel.

**Was ich daraus mitnehme:** die Reihenfolge stimmte nicht. Bevor eine
Datei dieser Größe hineinkann, muss das Adressierungsmodell passen -- sonst
kommt die Grenze mitten im Umbau. Die vier bisherigen Dateien
(`GAME_OFF.S`, `NUMERIC.S`, `OBJECT.S`) gingen so glatt, weil keine von
ihnen eine globale Variable anfasst.

Der Versuch ist zurückgenommen; der Stand ist wieder lauffähig.

## 138. Die Variablen liegen jetzt absolut

Nach dem gescheiterten CONTROLS.S-Versuch (Erkenntnis 137) der Umbau, der
vorher hätte kommen müssen: neun Bibliotheksvariablen sind aus dem
a5-Block herausgezogen und heißen jetzt wie bei Thalion.

```
mouse_x(a5)   -> Mouse_X        v_ink(a5)      -> Ink_colour
mouse_y(a5)   -> Mouse_Y        v_shadow(a5)   -> Shadow_colour
mbutton(a5)   -> Button_state   v_ma_x1(a5)    -> MA_X1  (und drei weitere)
```

76 Zugriffsstellen. Der a5-Block war nicht falsch -- er spart bei jedem
Zugriff zwei Byte und war die richtige Antwort auf ein Programm ohne
Verschiebetabelle. Er ist nur nicht mehr die Antwort auf die Frage, die
wir jetzt stellen: **Thalions Code kann a5 nicht kennen.** Er schreibt

```
	move.w	Mouse_Y,d6
	btst	#Right_pressed,Button_state
	move.w	#26,Shadow_colour
```

und seit vlink bindet, kostet das nur einen Eintrag in der
Verschiebetabelle.

Ein Nebeneffekt, der die Sache bestätigt: `Mouse_int` hielt sich die Basis
selbst (`lea vars,a1`), weil ein Interrupt sich nicht auf a5 verlassen
darf. Absolut braucht er gar keine Basis mehr -- die Routine ist um zwei
Befehle kürzer und um ein Register ärmer.

**Die Bitnummern in `Button_state` sind damit keine Vermutung mehr.** Im
Vorspann stand "die Reihenfolge ist geraten"; jetzt ist es unsere Zelle,
`Mouse_int` schreibt das Tastenbyte des IKBD hinein, und dort ist Bit 0 die
rechte Taste. Wer die Zahlen füllt, bestimmt sie -- Thalions Code liest sie
nur.

## 139. Der Prüfer fragte sein eigenes Muster nie

Beim Umbau meldete `tools/vars_pruefen.py` drei Überlappungen:

```
p_tiles     12..15  ueberlappt CI_H        13..14
p_pal       16..19  ueberlappt BTN_H       17..18
PROMPT_QUIT 60..61  ueberlappt viewy       60..61
```

Alle drei falsch: `CI_H`, `BTN_H` und `PROMPT_QUIT` sind Konstanten, keine
Variablenplätze. Und der Prüfer hat dafür seit jeher ein Ausschlussmuster,
`KEINE_VARIABLE`, das genau solche Namen abfängt -- **es wurde in der
Schleife nur nie gefragt.**

Auffallen konnte das nicht, solange keine Konstante zwischen den Variablen
stand. Mit den drei neuen standen dort welche.

Das ist die zweite Erkenntnis dieser Art an einem Tag (Erkenntnis 136: der
Aufrufer, der `Update_screen` machen musste). Beide Male war die Regel
vorhanden und wurde nicht angewandt. **Ein Werkzeug, das seine eigene
Ausnahme nicht kennt, ist schlimmer als keins** -- es meldet Fehler, wo
keine sind, und man gewöhnt sich an das Wegsehen.

## 140. Thalions HULL/WINDOWS.S -- und die Farbfrage dahinter

Nach dem Variablenumbau ging die Datei glatt hinein: 240 Zeilen, und das
Binden nannte genau **zwei** offene Symbole, `Put_masked_icon` und
`Window_icons`. Beide waren zu machen:

**`Window_icons` liegt jetzt im Originalformat.** Put_window_part rechnet

```
	mulu.w	#3*2*16,d4		; 96 Byte je Teil
```

-- die 96 stehen dort **wörtlich**, nicht als `Screen_depth`-Ausdruck, denn
Fensterkacheln haben im Original immer drei Ebenen, unabhängig von der
Bildtiefe des Schirms. Unser Konverter hatte sie auf acht aufgezogen; damit
läge jeder Teil um den Faktor 8/3 falsch. Also bleiben sie dreiebenig --
unverändert aus AM2_CPU --, und `Put_masked_icon` zieht sie beim Zeichnen
auf. Die Truhendatei wurde dabei 3 KB kleiner.

**Feste Adressen für geladene Daten.** Thalion schreibt
`lea.l Window_icons,a0`; unsere Daten kommen aus einer Datei und stehen
erst zur Laufzeit fest. Der Ausweg ist ein Puffer mit genau diesem Namen,
in den der Lader hineinkopiert. Dasselbe Muster wird `Control_icons`,
`Button_up` und `Prompts` brauchen.

**`Screen_depth` ist jetzt 8.** Solange nur Thalions Definitionen gelesen
wurden, beschrieb die 5 seine Daten. Seit `Open_window` bei uns läuft,
beschreibt sie unseren Bildschirm -- sie geht in die Größe des
Hintergrundpuffers ein, und mit 5 wäre er um drei Achtel zu klein.

**Und dann die Farben.** Das Fenster erschien -- in Rosa. Thalion schreibt

```
	move.w	#Window_colour,d4	; = 28
	jsr	Draw_box
```

Unsere UI-Farben liegen aber bei `UI_BASE+28` = 92; die 28 trifft bei uns
eine Kartenfarbe.

Der Grund reicht tiefer als ein Versatz. Gemessen an zwei Speicherauszügen:

```
Amiga, Kartenbildschirm:  Farbe 28 = (102, 85, 68)   braeunlich
Amiga, Truhenbildschirm:  Farbe 28 = (102,102, 85)   grau
Palettes.amb Nr. 2:       Farbe 28 = (102,102, 85)
```

**Das Original hat eine einzige Palette zu 32 Farben, und die
Bedienoberfläche benutzt dieselben Nummern wie die Karte.** Deshalb tönt
sie mit: auf der Karte bräunlich, in der Truhe grau. Unsere Engine gibt der
Oberfläche eine feste graue Palette in einer eigenen Bank -- eine
Falcon-Zugabe, die Thalions Code nicht kennt.

Damit steht eine Entscheidung an, und sie ist nicht meine.

## 141. Eine Palette, wie im Original

> Gruppe **F** (Farben und Bänke), Regel in der Kurzform.

Der rosa Fensterrahmen war kein Zeichenfehler, sondern die Spitze einer
Entscheidung, die vor Monaten gefallen war, ohne dass sie jemand als
Entscheidung ausgesprochen hätte.

Thalion schreibt Farben als absolute Nummern:

```
	move.w	#Window_colour,d4	; = 28
	move.w	#Default_ink,Ink_colour	; = 31
	moveq.l	#24,d4			; Farbbasis der Tastenrahmen
```

Bei uns lagen die Farben der Bedienoberfläche auf `UI_BASE+24..31`, also
88..95 -- eine eigene Palettenbank mit festem Grau. Die 28 traf damit eine
Kartenfarbe.

**Der Grund, warum das überhaupt möglich schien**, steht in drei Messungen:

```
Amiga, Kartenbildschirm:  Farbe 28 = (102, 85, 68)   braeunlich
Amiga, Truhenbildschirm:  Farbe 28 = (102,102, 85)   grau
Kartenpalette 7 (Nr. 258) Farbe 28 = (102, 85, 68)   -- gleich!
```

**Das Original hat eine einzige Palette zu 32 Farben, und ihre Farben
24..31 *sind* die Rampe der Bedienoberfläche.** Sie wechselt mit der Karte;
deshalb ist der Rahmen im Haus bräunlich und in der Truhe grau. Unsere
feste graue Bank war eine Falcon-Zugabe -- und gegenüber dem Original
schlicht falsch.

Die Umstellung war weniger Arbeit als das Verstehen: `UI_BASE` auf null,
und die Kartenpalette von Bank 1 nach Bank 0 (das Ereignisbild, das dort
lag, nach Bank 1). Der Statusleistenbereich behält seine eigene Bank --
dort stehen die Portraits mit ihrer Sonderpalette, und auf dem Amiga
schaltet die Copperliste sie für diese Zeilen um.

**Nachgemessen gegen den Amiga, ohne jede Umrechnung:**

```
Tastenfeld    4896 / 4896 Punkte farbgleich   (100 %)
Rahmen links  2304 / 2304 Punkte farbgleich   (100 %)
```

Vorher war dieselbe Messung nur über eine Indexabbildung möglich, weil die
Paletten verschieden waren (Erkenntnis 133). Jetzt stimmen die Farben
selbst.

**Was ich daraus mitnehme:** eine Zugabe, die das Original nicht kennt, ist
keine Verbesserung, sondern eine Schuld. Sie kostet nichts, solange nur
eigener Code sie sieht -- und alles, sobald fremder dazukommt. Dasselbe galt
für den a5-Block (Erkenntnis 138). Beide Male war die Optimierung richtig
für das Programm, das wir hatten, und falsch für das, das wir wollen.

## 142. Was die Doku-Durchsicht zutage brachte

Der Auftrag war, die Dokumentation auf den Stand zu bringen. Dabei ist
mehr herausgekommen als eine Aktualisierung.

**Ein Dokument hatte recht und ich unrecht.** `docs/01` sagt seit Wochen,
dass *zwei* Dateien Amiga-Hardware anfassen, und warnt ausdrücklich vor den
beiden Fallen -- der symbolischen Schreibweise `Custom+dmacon` und davor,
dass `grep` `HULL/VARIOUS.S` für binär hält. Ich habe die Zahl heute neu
erhoben, bin in beide Gruben gefallen und habe „eine einzige Datei" als
Erkenntnis 123 aufgeschrieben. Berichtigt.

**Drei Dokumente waren an einer Stelle veraltet, die weh tut:**

* `docs/01`, Abschnitt 2.1 beschrieb die Bankbelegung, die wir heute
  zurückgebaut haben -- eine eigene Bank für die Oberfläche. Sie stand dort
  als „Vorschlag" und war ein halbes Jahr lang die Wirklichkeit.
* `docs/06` beschrieb den Bau mit `mktos.py` und listete Dateien, die es
  nicht mehr gibt.
* `docs/03` beschrieb die Bibliotheksschicht als Rekonstruktion, obwohl
  inzwischen ein gutes Drittel davon gebaut und im Emulator geprüft ist.

**Was ich daraus mitnehme:** ein Dokument, das einen Entwurf beschreibt,
altert genau dann gefährlich, wenn der Entwurf gebaut wird. Solange er
Vorschlag ist, schadet er nicht; sobald er Wirklichkeit ist, glaubt man ihm.
Und wenn er dann zurückgebaut wird, glaubt man ihm immer noch.

Die Regel, die daraus folgt und die heute dreimal nötig gewesen wäre:
**erst nachschlagen, dann messen.** Nicht umgekehrt.

## 143. Die Rasterliste erklärt beide Beobachtungen

> Gruppe **T** (Timer-B-Raster), Regel in der Kurzform.

Der Nutzer meldete zwei Dinge: Truhe und Inventar wirken im Original grauer
als bei uns, und beim Umschalten der Bildschirme gibt es eine Verblassung
nach Schwarz -- ab der Zeile, wo die Portraitleiste endet.

Beides ist dieselbe Sache, und sie steht in `MODULES.S`:

```
Main_RL:                              ; Truhe, Inventar, die meisten Schirme
	R_palette 0,Main_pal
	R_range   1,25,35,Portrait_range  ; Farbe 25 zeilenweise ersetzen
	R_palette Middle_Y+1,Main_pal     ; unten: dieselbe feste Palette
	R_end
Map_RL:                               ; Kartenbildschirm
	R_palette 0,Main_pal
	R_range   1,25,35,Portrait_range
	R_palette Middle_Y+1,Current_pal  ; unten: die Palette der Karte
	R_end
Inv_RL:                               ; Inventar
	...
	R_range   49,25,35,Portrait_range ; zweiter Verlauf, grosses Portrait
	R_end
```

**Jedes Modul bringt eine Rasterliste mit** -- sie ist der zehnte der
vierzehn Eintraege eines Moduldeskriptors. Sie sagt, welche Palette ab
welcher Bildzeile gilt.

Damit ist die Frage von heute Mittag vollstaendig beantwortet, und meine
Antwort war nur zur Haelfte richtig:

* **Oben** (Statusleiste) gilt immer `Main_pal`, und Farbe 25 wird
  zeilenweise durch den Portraitverlauf ersetzt. Das hatten wir schon --
  unsere Bank 2 mit `STATUS_PALETTE` ist `Main_pal`, und `PORTRAIT_VERLAUF`
  ist `Portrait_range`.
* **Unten** haengt es vom Bildschirm ab: auf der Karte `Current_pal` (die
  Kartenpalette, braeunlich), in Truhe und Inventar `Main_pal` (grau).

Meine Umstellung von heute (Erkenntnis 141) ist also fuer den
Kartenbildschirm richtig und fuer Truhe und Inventar falsch. Dort muss die
untere Haelfte auf `Main_pal` umschalten.

**Und die Verblassung ist keine Zierde, sondern Teil des Moduls.**
`ClosedChest_Mod` nennt `Fade_out_bottom` als sein DisExit:

```
Fade_out_bottom:
	jsr	Wait_4_fade
	move.w	#Fade_out,d0
	move.w	#Middle_Y,d1		; nur die untere Haelfte
	move.w	#Screen_height-1,d2
	jsr	Set_fade
	jsr	Wait_4_fade
	moveq.l	#0,d0			; und dann schwarz fuellen
	move.w	#Middle_Y,d1 ... jsr Draw_box
	move.w	#Set_new,d0		; neue Palette setzen
```

Erst dunkeln, dann loeschen, dann die neue Palette -- genau die Reihenfolge,
die der Nutzer beschreibt. `Middle_Y` ist die Zeile, wo die Statusleiste
endet; bei uns beginnt das Layout auf Zeile 37, also ist es 36.

**Was das fuer uns heisst:** wir brauchen die Rasterliste nicht
nachzubauen. Der Falcon hat 256 Farben, und die Zweiteilung oben/unten
bilden wir schon mit Baenken ab. Es fehlen zwei Kleinigkeiten:

1. Beim Betreten von Truhe und Inventar Bank 0 auf `Main_pal` umladen, beim
   Verlassen zurueck auf die Kartenpalette. Das ist `R_palette
   Middle_Y+1,...` in klein.
2. `Fade_out_bottom` und `Fade_in_bottom` -- Palette ueber einige Bilder
   abdunkeln. `HULL/FADE.S` sind 224 Zeilen mit elf offenen Symbolen; die
   Datei koennte weitgehend uebernommen werden, nur `Set_fade` und
   `Dim_colours` haengen an der Rasterliste.

**Was ich daraus mitnehme:** der Nutzer hat am Bild gesehen, was ich beim
Lesen der Moduldeskriptoren uebersehen hatte. `dc.l Main_RL,0,Lay3_PA,0`
stand seit Wochen im Dokument, und ich habe den ersten Eintrag als
"brauchen wir noch nicht" abgetan. Er war die Antwort auf eine Frage, die
ich noch nicht gestellt hatte.

## 144. Thalions HULL/FADE.S -- unverändert eingebunden, beim ersten Anlauf

`HULL/FADE.S` ist die vierte Datei Thalions, die im Bau steht, und die
erste, die den Modulsatz *liest*:

```
	move.l	Module_Sp,d0		; Get RL address
	move.l	Raster_list_ptr(a0),d0
```

Damit war unser eigener Moduldeskriptor nicht mehr haltbar. Er hatte vier
Einträge zu 14 Byte -- Kennung, ModInit, ModExit, DisInit --, und das ging,
solange nur unser Code ihn las.

**Den echten Aufbau musste ich nicht raten.** Thalions `src/MODULES.S` ist
freigegeben und zeigt ihn offen:

```
Default_module:
	dc.b Global_mod,0
	dc.l 0
	dc.l 0,0,Wait_Mev,Wait_Kev
	dc.l 0,0,0,0
	dc.l Main_RL,0,0,0
```

Zwei Byte, dann zehn Langworte, dann drei -- 54 belegt von 56. Die
Versätze in `vorspann.i` sind daraus abgezählt und stimmen mit
`Raster_list_ptr = 38` überein, dem einzigen, den `FADE.S` nennt und der
sich damit unabhängig prüfen liess. Die Kennung ist ein **Byte** an Versatz
1, nicht ein Wort an Versatz 0; `MODULE_C.S` liest sie jetzt mit `move.b`.

Nach dieser Umstellung ging `FADE.S` beim ersten Bindelauf durch -- kein
einziges offenes Symbol, das nicht schon dagewesen wäre. Zu stellen waren
`Set_fade`, `Wait_4_fade`, `My_vsync` und `Off_screen`; sie stehen in
`src/HULL/FADE_SUP.S`.

## 145. Das Format der Rasterlisten stand die ganze Zeit im Quelltext

> Gruppe **T** (Timer-B-Raster), Regel in der Kurzform.

In `vorspann.i` stand über den Makros `R_palette`/`R_range`/`R_end` der
Satz: *"Das Format hier ist erfunden."* Das war es nicht mehr nötig.
`Combat_RL` in Thalions `src/MODULES.S` enthält einen Eintrag, den er von
Hand ausgeschrieben hat, weil er einen Zeiger auf den Palettenzeiger
brauchte:

```
	R_range 1,25,35,Portrait_range
	dc.b 0,Middle_Y+1
Combat_pal_ptr:	dc.l Combat_pal
	R_palette Combat_Y+Combat_height+1,Tactic_pal
```

Die mittleren zwei Zeilen **sind** `R_palette Middle_Y+1,Combat_pal`.
Damit ist der Aufbau belegt: Kennbyte, Zeilenbyte, bei `R_palette` ein
Langwort (sechs Byte), bei `R_range` zwei weitere Bytes und ein Langwort
(acht). Nur die Werte der Kennbytes und das Listenende bleiben unsere
Wahl -- der Auswerter steht in der nicht freigegebenen Bibliothek.

**Was ich daraus mitnehme:** eine ausgeschriebene Makroexpansion im
Quelltext ist eine Formatbeschreibung. Ich hatte `Combat_RL` beim ersten
Lesen als Sonderfall abgehakt, statt zu sehen, dass der Sonderfall genau
das zeigt, was die Makros verstecken.

## 146. Fade_out setzt a0 nicht -- der Beweis steht im Aufruf

Mein erster `Set_fade` las in allen drei Betriebsarten die Rasterliste aus
`a0`. Das ist beim Abblenden ein Griff in irgendein Register:

```
Fade_out_bottom:
	movem.l	d0-d4/a0,-(sp)
	jsr	Wait_4_fade
	move.w	#Fade_out,d0
	move.w	#Middle_Y,d1
	move.w	#Screen_height-1,d2
	jsr	Set_fade		; a0 ist hier nicht gesetzt
```

`Fade_out_all` macht es genauso. Nur `Set_new` und `Start_fade_in` bekommen
eine Liste -- und zwar über `lea.l Main_RL,a0` beziehungsweise über
`Raster_list_ptr` des Moduls.

Abgeblendet wird also von dem weg, **was gerade gesetzt ist**. Der Aufrufer
weiss nicht, was das ist, und muss es auch nicht wissen. `FADE_SUP.S` führt
das darum in `Bank0_ist` mit: jedes `Bank0_setzen` schreibt mit, und
`Set_palette` meldet über `Karte_gesetzt`, wenn die Palette an ihm vorbei
gesetzt wurde.

**Was ich daraus mitnehme:** wenn eine Routine ein Register in einer
Betriebsart nicht setzt, ist das der Vertrag, nicht eine Lücke. Die
Registerliste im `movem` sagt nur, was *gerettet* wird.

## 147. Blenden lassen sich nicht pauschal in Push_Module hängen

Zuerst hatte ich `Fade_out_bottom` an den Anfang von `Push_Module` gesetzt
und `Fade_in_bottom` ans Ende. Zwei Dinge gehen dabei kaputt:

**Der Mengendialog.** `Fade_out_bottom` *löscht* die untere Bildhälfte
(`Draw_box` mit Farbe 0). `InputNr_DisInit_M` zeichnet aber nur das
Dialogfeld, nicht das Truhenbild darunter -- der Hintergrund wäre weg.
Genau dafür trägt Thalion das Merkerbyte: `Local_mod` liegt über dem Bild,
`Global_mod` ersetzt es. Sein `Wait_4_user_Mod`, ebenfalls ein Feld über dem
laufenden Bild, ist `Local_mod`.

**Die Karte.** `Map_DisInit` zeichnet die Karte nicht -- es wählt nur das
Tastenfeld. Gezeichnet wird sie im Schleifendurchlauf danach, gesteuert über
`d5`. Ein `Fade_in_bottom` in `Basic_exit` blendet also ein leeres Bild
herauf, und die Karte springt hinterher herein.

Aufgeblendet wird darum an einer einzigen Stelle, in der Hauptschleife bei
`ml_key`, wo beide Wege zusammenlaufen -- Truhe und Inventar hat
`Init_display` gezeichnet, Karte und Optionen der Block darüber. Woran die
Schleife erkennt, dass etwas offensteht, ist **Thalions eigener Merker**:
`Faded_flag`, von `Fade_out_bottom` gelöscht, von `Fade_in_bottom` gesetzt.

**Was ich daraus mitnehme:** Thalions Blenden hängen am DisExit und DisInit
einzelner Module, weil dort der ganze Bildschirm gezeichnet wird. Unsere
Aufteilung ist eine andere, und die Blende musste sich ihr anpassen -- nicht
umgekehrt. Übernommen ist trotzdem alles, was Verhalten trägt: die vier
Blendroutinen, `Dim_colours`, der Merker.

## 148. Dim_colours rechnet in Amiga-Farbworten, und das ist kein Hindernis

`Dim_colours` bewegt jede der drei Nibbles eines `$0RGB`-Wortes um höchstens
`d6` Stufen auf das Ziel zu. Neunzig Zeilen Thalion, die nur laufen, wenn
die Paletten in Amiga-Form vorliegen -- unsere liegen im VIDEL-Format vor.

Das Zurückrechnen ist verlustfrei. Der Konverter bildet die sechzehn
Amiga-Stufen mit `videl_component()` auf sechzehn VIDEL-Bytes ab, und
`Byte >> 4` gibt die Stufe wieder; nachgerechnet für alle sechzehn:

```
0 16 32 52 68 84 100 116 136 152 168 184 200 220 236 252
```

`Paletten_ableiten` holt daraus `Current_pal` (Bank 0, die Karte) und
`Main_pal` (Bank 2, die graue Rampe), `Bank0_setzen` rechnet mit derselben
Tabelle zurück. `Dim_colours` läuft dazwischen unverändert.

**Der Gewinn liegt nicht in den neunzig Zeilen**, sondern darin, dass die
Blende dieselbe Kurve hat wie im Original: gleiche Stufung, gleiche
Reihenfolge, gleiche Abbruchbedingung. Das hätte ich nachgebaut und wäre
danebengelegen.

Und `Main_pal` mussten wir nicht suchen: `STATUS_PALETTE` im Konverter --
aus der Copperliste eines Amiga-Speicherauszugs gelesen -- **ist** sie.
`Portrait_range` in `src/DISPLAY.S` bestätigt auf demselben Weg
`PORTRAIT_VERLAUF`, Wort für Wort.

## 149. Zwei Dateien, ein Name -- die Falle hat zugeschnappt

Der Nutzer fragte nach einem Commit, der `engine/src/GAME_OFF.S` änderte:
*„Game_off.s ist doch orig source. Hast du den verändert?"*

Die Antwort war nein, aber die Frage war berechtigt, und das ist der Punkt.
`engine.s` band **zwei** Dateien desselben Namens ein:

```
	INCLUDE	"GAME_OFF.S"		; Thalions, über -I gefunden
	INCLUDE	"src/GAME_OFF.S"	; unsere Ergänzungen
```

Die erste liegt außerhalb des Repositoriums unter `AMBER_URCODE` und ist
nach Leitziel 1 unantastbar; die zweite ist unsere. Unterschieden hat sie
allein das `src/` im Pfad.

**Der Beleg, dass nichts passiert ist**, ließ sich in drei Schritten führen,
und die Bauart lohnt sich für den nächsten Zweifelsfall:

1. Zeitstempel von Thalions Datei: `May 7 2023` — seit dem Auspacken nicht
   angefasst.
2. `grep` nach den geänderten Symbolen (`MODEMASK`, `MD_VGA`, `MD_VERTFLAG`)
   in Thalions Datei: kein Treffer. Es sind VIDEL-Symbole; sein Quelltext
   kennt gar keine.
3. `grep` nach Schreibzugriffen auf `$URCODE` in allen Werkzeugen: nur zwei
   Existenzprüfungen, kein `cp`, kein `>`, kein `sed -i`.

Also **Vorsicht, nicht Nachsicht**: unsere Datei heißt jetzt
`engine/src/FALCON_OFF.S`. Der Name sagt auch, was drinsteht — die
Falcon-Seite, die Thalions Datei nichts angeht: Bildmaße, VIDEL-Moduswort,
Palettenbänke, GEMDOS-/XBIOS-Nummern, unsere a5-Belegung.

**Die Umbenennung ist belegt folgenlos:** Programmgröße vorher wie nachher
41988 Bytes, `SCREEN.RAW` des Prüflaufs byteidentisch.

Die allgemeine Lehre: wo ein Vorhaben fremden und eigenen Code *bewusst*
mischt, darf die Herkunft nicht am Pfad allein hängen. Ein Pfad wird
überlesen, ein Name nicht.

## 150. Hatari kann den Rasterinterrupt nicht prüfen -- der Prüfstand maß sich selbst

> Gruppe **M** (Messaufbau vor Befund), **T** (Timer-B-Raster), Regel in der Kurzform.

R2 sollte den Timer-B-Raster in RGB kalibrieren. Das Ergebnis ist ein
Negativbefund, aber ein sauberer: **Hatari beantwortet die Frage gar nicht.**

Der Weg dorthin lohnt die Aufschreibung, weil zweimal dasselbe Muster auftrat
-- ein Meßaufbau, der zwei verschiedene Ursachen nicht trennen kann.

**Erster Fehler: der Rand.** Die Prüfliste färbte Farbe 0 ab Zeile N rot, das
Skript suchte die erste rote Bildzeile. Auf Atari-Rechnern trägt der Rand
aber genau die Farbe 0. Gemessen wurde also der obere Rand, nicht die
Rasterkante -- „Kante bei Schirmzeile 0", bei jeder Vorgabe.

**Zweiter Fehler, der schwerere: die Liste war nicht diagnostisch.** Sie fing
schwarz an und wurde bei `RASTERZEILE` rot. Damit sehen zwei gegensätzliche
Defekte identisch aus:

| Ursache | Bild |
|---|---|
| Timer feuert nie | bleibt schwarz |
| Timer feuert sofort (alles in der Austastlücke) | wird ganz rot |

Kein noch so oft wiederholter Lauf kann das trennen. Die Liste wurde deshalb
umgedreht -- **rot ab Zeile 0, schwarz ab `RASTERZEILE`** --, und dann sind
alle Fälle unterscheidbar: rot oben mit Kante = Timer zählt Zeilen;
durchgehend rot = das Schwarz kommt nie; durchgehend schwarz = die Liste ist
durch, bevor gezeichnet wird. Zwei Schritte genügen statt einundsechzig.

**Der Befund.** Erste Fassung (endet rot): Bild durchgehend rot. Zweite
Fassung (endet schwarz): Bild durchgehend schwarz. Beide Male *byteidentische*
Abzüge bei verschiedenen Zeilenvorgaben -- obwohl der Define nachweislich
ankam, die Objektdateien unterschieden sich.

**Die Erklärung stand nicht im Code, sondern in Hataris TODO-Liste.** Für die
Falcon-Videl-Emulation steht dort „Palette switching during screen drawing"
als *noch zu erledigen*. Hatari zeichnet ein Falcon-Bild mit **einem**
Palettenstand; der letzte gewinnt. Endet die Liste rot, ist alles rot; endet
sie schwarz, alles schwarz -- unabhängig davon, ob unser Interrupt
zeilenweise feuert. Der Meßaufbau war blind für genau die Größe, die er
messen sollte.

**Was daraus folgt, auch rückwirkend:** Der ältere VGA-Befund (TBDR 120 und
150 ergaben beide Schirmzeile 34) ist derselbe Emulatormangel und **kein**
Beleg gegen VGA. Damit ist Grund 3 der RGB-Entscheidung unbelegt. Die
Entscheidung steht trotzdem -- Gründe 1 und 2 (ST-verträgliche 15-kHz-Basis;
der STE kann nur RGB) sind hart und hängen nicht am Emulator.

Die allgemeine Lehre: **bevor man ein Ergebnis deutet, prüft man, ob der
Aufbau die Frage überhaupt beantworten kann.** Ein Emulator ist ein Modell,
und ein Modell hat Lücken; die Lücke stand hier öffentlich dokumentiert und
wäre vor der ersten Messung zu finden gewesen.

## 151. Timer B feuert auf dem Falcon -- aber er zählt keine Bildzeilen

> **Stand 2026-09-26:** Widerlegt durch 154: Timer B zählt auf dem Falcon die Bildzeilen doch.
>
> Gruppe **T** (Timer-B-Raster), Regel in der Kurzform.

Der Hardwaretest (wanderndes Prüfband, `IFD RASTERPRUEF`) lief auf einem
echten Falcon030 mit RGB. Beobachtung des Nutzers:

> „normales" Bild mit schwarzem Rand, bei ESC (Verlassen des Programms)
> kurzes Aufblitzen eines vollständig roten Bildschirms

Das ist ein vollständiger Befund, obwohl kein Band zu sehen war -- **weil das
Ausbleiben des Bandes hier nicht mehrdeutig ist.** Die Prüfliste hat genau
zwei Schritte:

| Schritt | Zeile | wirkt | ausgeführt von |
|---|---|---|---|
| 0 | 0 | Farbe 0 = **rot** | `Raster_start`, direkt in der Austastlücke |
| 1 | wandernd 20…180 | Farbe 0 = **schwarz** | `Raster_int`, aus dem Timer |

Daraus liest sich alles ab:

- **Bild und Rand schwarz** → Schritt 1 hat ausgeführt, und zwar *vor* der
  ersten sichtbaren Zeile. Der Interrupt **feuert**.
- **Rotes Aufblitzen beim Verlassen** → Schritt 0 war korrekt gesetzt. Sobald
  `Raster_remove` den Timer stilllegt, fehlt das Schwarz, und das Rot wird
  sichtbar, bis `Close_screen` die Desktop-Palette zurückholt. Liste und
  Palettenschreibarbeit sind also in Ordnung.
- **Hätte der Timer nie gefeuert**, wäre der Schirm durchgehend rot geblieben.
  War er nicht.

Also: **die ganze Liste läuft in der Austastlücke durch.** Timer B feuert,
zählt aber nicht die Bildzeilen des VIDEL.

**Dass die umgedrehte Prüfliste das leisten konnte, war der Punkt.** Die erste
Fassung (schwarz zuerst, rot ab Zeile N) hätte hier ein schwarzes Bild
gezeigt -- ununterscheidbar von „der Interrupt feuert gar nicht". Erkenntnis
150 hat den Aufbau repariert, und erst dadurch trägt diese Messung.

**Der Entwurf ist trotzdem nicht falsch.** Im Atari-Forum ist die kanonische
Bauart für ST/STE genau unsere: *„set the first color in the VBL routine and
the rest with Timer B"* -- `Raster_start` in der VBL, `Raster_int` für den
Rest. Auf ST/STE ist Timer-B-Ereigniszählung seit je bewährt; der
Falcon-VIDEL ist der Sonderfall.

**Folge:** Der Falcon fährt weiter im Raum statt in der Zeit -- Farbbänke,
256 Farben, kein Interrupt. Das war ohnehin der laufende Zustand:
`Raster_liste_setzen` wurde im Normalbau nie gerufen. Neu ist nur, dass die
Entscheidung jetzt einen Namen hat, `RASTER_VERFAHREN` in `FALCON_OFF.S`, und
dass dort steht, welche fünf Stellen mitwandern müssen, wenn jemand sie
umlegt. Umlegen bricht den Bau mit einer Meldung, statt still etwas
Halbfertiges zu bauen.

**Offen, ein Ein-Bit-Versuch wert:** Unser Videomodus löscht `MD_STMODES`,
fährt also VIDEL-eigene Modi. Ob Timer-B-Ereigniszählung am Falcon überhaupt
nur im ST-verträglichen Videopfad an Display-Enable hängt, ist ungeprüft.

## 152. Die Monitorbits gehören dem Monitor -- eine Umstellung, die keine sein durfte

Am 2026-09-12 habe ich `Open_screen` von `MODEMASK` auf ein selbstgebautes
`MODEMASK_RGB` umgestellt und damit 15 kHz erzwungen. Einen Tag später hat
der Nutzer nachgefragt:

> der falcon ist doch grundsätzlich ste kompatibel und sollte Rastereffekte
> über timer b grundsätzlich darstellen können. […] Wenn ein vga monitor dran
> ist, dann stellt er auch st low/med/high mit 31khz dar.

Beides trifft zu, und beides widerlegt die Umstellung.

**Der ursprüngliche Code war adaptiv, und das war seine Qualität:**

```
move.w	oldmode(a5),d0
and.w	#MODEMASK,d0		; MD_VGA+MD_PAL+MD_OVERSCAN+MD_VERTFLAG
or.w	#BPS8+COL40,d0
```

`oldmode` ist der laufende Desktop-Modus, also der, der zum *angeschlossenen*
Monitor passt. `MODEMASK` erbt daraus die vier monitorabhängigen Bits; gesetzt
wird nur, was uns gehört -- acht Ebenen, vierzig Spalten. Dasselbe Programm
läuft damit an RGB und an VGA.

Ich habe ausgerechnet die zwei Bits gelöscht, die den Monitor bedienen:

| Bit | Bedeutung | Folge des Löschens |
|---|---|---|
| `MD_VGA` (4) | Zeitbasis: gesetzt 31 kHz, gelöscht 15 kHz | 15 kHz **auch an VGA** |
| `MD_VERTFLAG` (8) | an VGA Zeilenverdopplung, an TV Interlace | 200 Zeilen füllen den 400-zeiligen Schirm nicht |

`MD_VERTFLAG` ist genau der Mechanismus, mit dem der Falcon ST Low/Med/High an
einem VGA-Monitor zeigt. Ich hatte es als „braucht nur VGA, in 15 kHz sind 200
Zeilen nativ" abgetan -- richtig beobachtet, **falsch geschlossen**: es gehört
zum VGA-Fall, deshalb muss es stehenbleiben, wenn VGA dranhängt.

**Die drei Gründe, einzeln:**

1. *„RGB ist die ST-verträgliche Zeitbasis."* Stimmt, ist aber kein Grund --
   der Falcon kann ST-Auflösungen auch an VGA.
2. *„Der STE kann nur RGB."* Stimmt, betrifft aber einen **eigenen Bau**
   (`PLANES=4`, andere Hardwareschicht). Der Falcon-Bau muss sich dafür nicht
   beschneiden. Das war der eigentliche Denkfehler: eine Eigenschaft des
   künftigen Ports dem gegenwärtigen aufgezwungen.
3. *„Timer-B-Raster sind auf Falcon-VGA unzuverlässig."* Der Emulatorbefund
   dahinter war untauglich (Erkenntnis 150), und die Demoszene macht
   zeilengenaue Palettenwechsel auf dem Falcon sehr wohl -- an beiden
   Monitorarten, mit Jitter-Vorbehalt.

**Damit fällt auch der Schluss aus Erkenntnis 151 zur Hälfte.** Der Befund
bleibt (Timer B feuert, zählt aber keine Bildzeilen); der Schluss „der Falcon
kann das nicht" war zu weit gegriffen. Richtig ist: *unsere* Fassung tut es
noch nicht. Das ist ein Fehler, kein Naturgesetz. Kandidaten stehen am
Schalter in `FALCON_OFF.S`.

**Die Lehre, und sie ist unangenehmer als die Sache selbst:** Die drei Gründe
sahen zusammen überzeugend aus, obwohl keiner für sich trug. Grund 3 war
gemessen (falsch), Grund 1 wahr aber irrelevant, Grund 2 wahr aber auf das
falsche Zielsystem bezogen. Drei schwache Gründe ergeben keinen starken. Und
ein Code, der etwas *erbt*, ist fast immer schlauer als einer, der es
festnagelt -- das Erben war hier die Absicht des Originals, und ich habe sie
für einen Mangel gehalten.

**Addendum 2026-10-25 (T65 passed 2026-10-27): one bit is set after all.**
At RGB `Open_screen` (`FALCON.S`) now always sets `MD_PAL`: Thalion counts
VBLs for 50 Hz (`Realtime`, `VBLs_per_step`, `Delay`), and on a 60 Hz
desktop the game ran a fifth too fast (user, 2026-10-25). VGA keeps its
mode, it has no 50 Hz. The time base (`MD_VGA`) and the line doubling
(`MD_VERTFLAG`) stay inherited, so the program still runs at RGB and VGA.
The ST build does the same in `ST.S` (sync bit, PAL bit on the Falcon).

## 153. Ein Palettenwechsel je Bild ist die Frage -- nicht dreißig

> Gruppe **T** (Timer-B-Raster), Regel in der Kurzform.

Nutzereinwand, nachdem ich den Timer-B-Raster für den Falcon abgeschrieben
hatte:

> und wir brauchen ja nur einen Palettenwechsel pro frame, nicht viele und
> supersynchron. das sollte auch in vga funktionieren, trotz ggf. jitter.

Das trifft, und es entwertet den Vorbehalt, den ich aus der Demoszene
übernommen hatte. Dort geht es um **pixelgenaue Mehrfachwechsel mitten in der
Zeile** -- daher „very unstable on Videl, especially on VGA". Ambermoon
braucht etwas ganz anderes: `Map_RL` legt oben `Main_pal` auf und ab
`Middle_Y+1` `Current_pal`. **Eine** Kante, waagerecht, und ein paar Pixel
Jitter daran sieht in einem Spiel niemand.

Ein fremder Vorbehalt gilt nur für den Anwendungsfall, aus dem er stammt.
Bevor man ihn übernimmt, prüft man, ob der eigene Fall derselbe ist -- meiner
war es nicht.

**Daraus entstand `tools/rastertest/`** -- ein eigenständiges Programm von
gut 1000 Bytes, das genau diese Frage stellt: Farbe 0 in der Austastlücke auf
Rot, Timer B schaltet bei Zeile N auf Grün, Schirm leergeräumt. N läuft
50 → 100 → 150. Die Kante muss wandern.

Drei Entwurfsentscheidungen, jede aus einem Fehler dieser Sitzung gelernt:

1. **Monitorbits werden geerbt** (`and.w #MODEMASK,d0`), damit derselbe Test
   an RGB und VGA läuft -- siehe Erkenntnis 152.
2. **Zeitgesteuert statt tastengesteuert**, damit man nur hinsehen muss.
3. **Die Warteschleife zählt am 200-Hz-Zähler `$4BA`, nicht an Bildern.**
   Zuerst hatte ich einen VBL-Zähler eingebaut -- und damit die Warteschleife
   von genau dem abhängig gemacht, was sie prüfen soll. Hängt der VBL-Haken,
   hinge auch die Schleife, und das Programm wäre stumm statt aussagekräftig.

**Und noch ein Fehlschluss, sofort korrigiert:** Als die Abzüge seltsam
aussahen, vermutete ich, `Bconstat` melde fälschlich „Zeichen da" und alle
Wartestellen fielen durch. Das Muster („der Messaufbau misst sich selbst")
hatte in dieser Sitzung schon zweimal gepasst. Es war trotzdem falsch --
VBL 450 zeigte noch den Hinweistext, die Wartestelle lief also. Ein Datenpunkt,
den ich schon hatte, sprach dagegen, und ich hatte ihn übergangen.

**Und noch eine Namensfalle, dieselbe wie bei `GAME_OFF.S`:** Das Programm
hieß zuerst `RASTTEST.TOS` -- zu nah an `RASTER.TOS`, dem *Engine*-Bau mit
`-DRASTERPRUEF` (47 KB). Der Nutzer startete prompt die Engine und sah
Ambermoon hochfahren statt rot/grün. Zwei Dinge, die sich nur in Nuancen des
Namens unterscheiden, werden verwechselt -- ich hatte diese Lehre am selben
Tag schon einmal gezogen und trotzdem gleich wieder dagegen verstoßen. Jetzt
heißt es `TIMERB.TOS`: anderer Name, anderes Wort, keine Verwechslung.

**Hatari kann diesen Test nicht auswerten** (Erkenntnis 150: eine Palette je
Bild). Der Rauchtest belegt nur, dass das Programm lädt, läuft, nicht bombt
und den Desktop wiederherstellt. Die Antwort kann nur echte Hardware geben.

## 154. Timer B zählt auf dem Falcon doch die Bildzeilen -- 151 war falsch

> Gruppe **T** (Timer-B-Raster), Regel in der Kurzform.

Messung auf echtem Falcon030 (RGB), `tools/rastertest/TIMERB.TOS`, Rohdaten
in `docs/messungen/timerb-falcon-2026-09-13.txt`:

```
VBL-Aufrufe    : 100      2 s bei 50 Hz
TimerB-Aufrufe : 198      = 2 je Bild
Feuern je Bild : 2
Zeile (erstes) : 81       min 81, max 131, SOLL 100
```

**Timer B feuert rund einmal je 100 Bildzeilen.** Zwei Feuer je Bild sind
erwartbar: nach dem Feuern lädt er TBDR neu und zählt weitere 100 Zeilen --
bei rund 200 sichtbaren Zeilen also zweimal. Er zählt also **Bildzeilen**,
nicht etwas anderes, und er feuert nicht in der Austastlücke.

**Damit ist Erkenntnis 151 in ihrem Schluss widerlegt.** Dort stand, aus dem
Engine-Prüfband abgeleitet: „Timer B feuert, zählt aber keine Bildzeilen."
Der *Befund* dort (Bild schwarz, beim Verlassen kurz rot) bleibt richtig; die
*Ursache* war falsch geraten. Der Fehler steckt in unserer Listenabarbeitung
in `HULL/RASTER.S`, nicht im Timer und nicht im VIDEL.

Wie es dazu kam, ist die eigentliche Lehre: Der Engine-Test zeigte **Farben**
und ließ mich aus einem Bild auf eine Ursache schließen. Aus „schwarz, kurz
rot" folgt aber nicht eindeutig „der Timer zählt nicht" -- dasselbe Bild
entsteht auch, wenn die Liste falsch abgearbeitet wird. Ein zählendes
Programm hätte die Frage beim ersten Versuch beantwortet. **Ein Messaufbau,
dessen Ergebnis man interpretieren muss, ist kein Messaufbau.**

**Noch nicht beantwortet, und ehrlich als offen zu führen:** Die gemessene
Zeile ist 81 statt 100, und min/max spannen 81 bis 131. Diese Spanne
vermischt zwei Dinge, die das Programm nicht trennt -- das Zittern des
*ersten* Feuerns über die Bilder hinweg und die Lage des *zweiten* Feuerns.
Solange beides in derselben Zahl steckt, lässt sich nicht sagen, ob die Kante
stabil um 19 Zeilen versetzt liegt (harmlos, einmal ausmessen und abziehen)
oder um ±25 Zeilen zittert (unbrauchbar für einen Palettenwechsel).

Das nächste Programm muss die beiden Feuer je Bild getrennt festhalten und
mehrere SOLL-Werte durchfahren -- wandert die gemessene Zeile proportional
mit, stimmt die Skala.

## 155. Zeilenzähler statt Abstandsrechnung -- und zwei schlafende Fehler

> Gruppe **T** (Timer-B-Raster), Regel in der Kurzform.

Nachdem TIMERB.TOS belegt hatte, dass Timer B die Bildzeilen zählt, schlug der
Nutzer die Bauart vor, die man auf dem STE nimmt: in der VBL einen Zähler
zurücksetzen, Timer B im Ereigniszählmodus laufen lassen, im Interrupt
hochzählen und ab der passenden Zeile die Palette setzen; am Ende den Timer
aus, in der nächsten VBL wieder an.

`HULL/RASTER.S` arbeitet jetzt so:

| | vorher | jetzt |
|---|---|---|
| TBDR | je Schritt der Abstand zum nächsten | fest 1 -- ein Interrupt je Zeile |
| im Interrupt | Timer anhalten, TBDR setzen, neu starten | nur zählen und ausführen |
| welcher Schritt | Index, `mulu.w #RS_SZ` | Zeiger auf den nächsten Schritt |
| fällig | Zeile = erwartete Zeile | Zeile <= Zähler |

**Warum das besser ist:** Den Timer im Interrupt anzuhalten und neu zu starten
kann ein Zeilenereignis verschlucken, und ein TBDR, den man ohne Anhalten
schreibt, gilt erst nach dem *nächsten* Nachladen. Mit TBDR=1 lädt er selbst
nach und wird im Interrupt nie angefasst. „Zeile <= Zähler" holt einen Schritt
eine Zeile später nach, falls doch einmal ein Ereignis verlorengeht, statt ihn
für das ganze Bild ausfallen zu lassen. Und der Zeiger spart das `mulu` --
auf dem 68000 bis zu 70 Takte, jetzt jede Zeile.

**Preis:** ein Interrupt je Zeile bis zum letzten Schritt -- `Map_RL` 37,
`Inv_RL` gut 85. Auf dem Falcon belanglos, auf dem STE grob zwei bis drei
Prozent.

**Beim Lesen dafür aufgefallen, zwei Fehler, die nie gezündet hatten:**

1. **`RS_MAX = 64` war zu klein.** `Inv_RL` und `Dialogue_RL` zerlegen sich in
   72 Schritte (zwei Porträtverläufe zu je 35 Zeilen plus zwei Paletten).
   `Raster_liste_setzen` bricht bei `RS_MAX` still ab -- der zweite Verlauf
   hätte nach 27 Zeilen geendet. Jetzt 96. Gezählt an Thalions `MODULES.S`;
   `C3_RL` mit symbolischer Länge (`C3_horizon`) ist nicht mitgezählt.
2. **`d5` wurde nach der Nullprüfung gesetzt.** Bei einer Liste ohne Zeiger
   sprang `Raster_liste_setzen` nach `rls_fertig` und schrieb den `d5` des
   *Aufrufers* nach `ras_anzahl`. Die VBL hätte dann eine Liste mit
   zufälliger Länge abgearbeitet.

Beide lagen nur deshalb still, weil der Normalbau `Raster_liste_setzen` nie
ruft. Mit `RASTER_ZEIT` wären sie beim ersten Inventar bzw. beim ersten Modul
ohne Rasterliste aufgefallen -- als Bildfehler, nicht als Meldung.

**Neu: `RASTER_VERSATZ`**, der Startwert des Zählers, setzbar über
`-DRASTER_VERSATZ=N`. Vorbelegt mit 0, weil der Versatz noch nicht gemessen
ist: TIMERB ergab Zeile 81 statt 100, aber mit einer Spanne, die Zittern und
zweites Feuern vermischt.

**Stand:** gebaut für 68030 und 68000, Normalbau 41942 Bytes (46 weniger).
**Nicht gemessen** -- weder die Regression noch das Prüfband auf Hardware.

## 156. Timer-B-Raster auf dem Falcon vertagt -- FARBKANT stürzt ab, Grund offen

> Gruppe **T** (Timer-B-Raster), Regel in der Kurzform.

Nach drei Fehlschlägen in Folge (Prüfband in der Engine, RASTZAEH, jetzt
FARBKANT) wird der Timer-B-Weg für den Falcon **erstmal stillgelegt**. Der
Falcon fährt weiter Farbbänke (`RASTER_RAUM`); der Rasterinterrupt bleibt im
Quelltext stehen und ist der Weg für ST/STE. Das ist ein Aufschub, kein
Urteil über die Hardware -- Erkenntnis 154 steht.

**Was FARBKANT.TOS sollte:** die Frage auf ihren Kern bringen. Ein Bild, eine
Farbe, ein Wechsel je Bild -- VBL färbt Farbe 1 rot und macht Timer B scharf
(TBDR=100), der Interrupt färbt grün und legt den Timer wieder still. Oben
rot / unten grün hieße ja, ganz rot "feuert nie", ganz grün "feuert in der
Austastlücke". Kein Band, keine Liste, keine Engine.

**Was herauskam:** eine Exception auf rotem Hintergrund. Rot heißt, dass die
VBL mindestens einmal gelaufen ist und ihre Farbe stand; abgestürzt ist es
danach.

**Was das eingrenzt.** Das Gerüst ist Zeile für Zeile das von TIMERB.TOS,
und das lief am 2026-09-13 auf echter Hardware bis Stufe 4 durch: Mshrink,
Super, VsetMode mit geerbten Monitorbits, VBL-Platz suchen, Timer-B-Vektor,
Ereigniszählmodus, Bericht in eine Datei. Neu und damit verdächtig sind nur
drei Dinge:

1. **das Füllen der Bildfläche** (64000 Bytes ab Physbase, Ebene 0 voll),
2. **das Schreiben der VIDEL-Palette aus VBL und Interrupt heraus**
   ($FFFF9804, Langwort),
3. die Anzeigedauer von zehn statt zwei Sekunden.

Ungeprüft geblieben ist die billigste Auskunft überhaupt: **wie viele Bomben**
bzw. welche Exceptionnummer. Zwei heißt Busfehler (eine Adresse, die es nicht
gibt -- Verdacht 1 oder 2), drei Adressfehler, vier unerlaubter Befehl. Ohne
diese Zahl ist jede weitere Vermutung wieder nur eine Vermutung, und genau
davon gab es in dieser Reihe schon zu viele.

**Regel daraus:** ein Prüfstück, das abstürzt, misst nichts. Die nächste
Fassung fängt deshalb bei Stufe 3 **ohne** Interrupt an (nur füllen, Farbe
setzen, warten) und schaltet den Timer erst dazu, wenn das steht. Wer zwei
neue Dinge gleichzeitig einbaut und dann eine Exception sieht, hat nicht
gemessen, sondern gewürfelt.

## 157. Ein Platzhalter am falschen Ort: geschriebene Ziffern auf einem `rts`

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

Thalions `Inv2_DisInit` fror auf echter Hardware beim Wechsel ins Inventar
ein — Bild blendet ins Schwarze, kein Escape mehr. Die Ursache war kein
Fehler in seinem Quelltext und keine Falcon-Eigenheit, sondern **eine
Platzhalterzeile im falschen Abschnitt unserer Datei**.

`INVENTOR_STUBS.S` hat zwei Abschnitte: Routinen, die nichts tun, und Daten.
Der Routinenabschnitt sieht so aus — viele Marken, ein einziges `rts`:

    Find_small_text:
    Init_scroll_bar:
    Number:
    Pop_Scroll_bar:
    Push_Scroll_bar:
        rts

**Alle diese Marken zeigen auf dieselbe Adresse.** Und `Number` ist im
Original gar keine Routine, sondern ein Zahlentext-Puffer:

    move.b Level_nr(a1),d0      ; Display_small_member_info
    moveq.l #2,d7
    lea.l Number,a0
    jsr DecL_convert            ; schreibt drei ASCII-Ziffern nach (a0)

Damit legt der erste Aufruf drei Ziffern auf das `rts`. Der **erste** Aufruf
läuft noch durch — `Find_small_text` kam davor. Der **zweite** springt in die
Ziffern und führt sie als Befehle aus. Und genau zweimal wird gerufen:
`Inv2_DisInit` ruft `Display_Inv2_member_info`, und die ruft
`Display_small_member_info`, das vorher schon einmal lief.

**Wie es gefunden wurde.** Nicht durch Lesen — drei Verdächtige waren durch
Lesen ausgeschlossen, der richtige war nicht darunter. Gefunden mit einer
Stufenleiter (`-DINV2_STUFE=n`, Thalions Aufrufe einzeln) plus einer Spur auf
der Konsole (`-DINV2_SPUR=1`). Die Spur sagte: Stufe 5 betreten, nie
verlassen. Danach die entscheidende Probe — dieselbe Routine **zweimal**
hintereinander gerufen, ohne alles andere: hängt. Einmal: läuft.

**Zwei Messfehler auf dem Weg dorthin**, beide teuer:

1. *Die VBL-Haltepunkte waren die Bremse.* Der Prüfstand setzt eine Kette von
   Hatari-Haltepunkten (`b VBL > n`); damit kam der Emulator in zehn Minuten
   nur bis VBL 700. Ohne Haltepunkte, mit `--run-vbls` und `--dsp none`:
   **1400 VBL in sieben Sekunden**, also rund zweihundertmal so schnell. Für
   eine Bisektion ist das der Unterschied zwischen machbar und nicht.
2. *Der Prüfstand las alte Abzüge als neue.* `hatari-abzuege/` wird nicht
   geleert; `vbl1500.png` von vorletzter Woche wurde als Ergebnis dieses
   Laufs gemeldet. Nur das Datum verriet es.

**Und ein Messmittel, das besser ist als ein Abzug:** das Tastenskript
schreibt nach dem Inventar `SCREEN.RAW`. Ist die Datei da, kam der Lauf am
Inventar vorbei — eine Ja/Nein-Antwort ohne Bild, ohne Haltepunkt, in sieben
Sekunden. Sie ist aber **nicht hinreichend**: SCREEN.RAW entstand auch, als
Thalions Aufbau hing (die Hauptschleife lief weiter). Erst die Konsolenspur
trennte „durchgelaufen" von „hängengeblieben".

**Fünf weitere Platzhalter standen ebenso falsch** und sind mitgewandert:
`Broken` (Silhouette), `Dissolve` (Animationsliste), `Dissolve_HDOB` und
`Move_key_HDOB` (HDOB-Strukturen, in die geschrieben wird) und
`Combat_party`. Alle werden im Original mit `lea` adressiert, nicht gerufen.

**Regel daraus:** ein Platzhalter für etwas, das im Original mit `lea`
adressiert wird, gehört in den Datenabschnitt — auch wenn er nie gelesen
wird. Im Routinenabschnitt ist er kein harmloser Nichtstuer, sondern eine
Schreibstelle mitten im Programmcode. Die Prüfung ist mechanisch: taucht
`lea <Name>` im Originalquelltext auf, ist es kein Sprungziel.

## 158. Klickeinspeisung -- und warum der Freeze trotzdem nicht im Emulator steht

> **Stand 2026-09-26:** Der Freeze ist gelöst, siehe 160.
>
> Gruppe **M** (Messaufbau vor Befund), Regel in der Kurzform.

Der Nutzer meldete: im Inventarschirm aus Thalions Quelle friert ein Mausklick
auf ein Tastensymbol das Programm ein, **bevor** die Taste gedrückt gezeichnet
wird. Mit dem Tastenskript allein war das nicht nachzustellen — es kennt keine
Maus.

**Was gebaut wurde.** Eine Klickeinspeisung im PRUEFLAUF: die Taste `K` setzt
`Mouse_X`, `Mouse_Y` und `Button_state`, also genau die Stellen, die sonst
`Mouse_int` aus den IKBD-Paketen füllt. Damit läuft der vollständige Weg —
`Inv_slot_at`, `Find_object`, `Feedback`, `Button_nach_nr`,
`Map_CIL_evaluate`.

Zwei Dinge waren dabei nicht offensichtlich:

1. **Das Loslassen muss aus einem Interrupt kommen.** Thalions
   `Wait_4_unclick` ist eine enge Schleife auf `Button_state` ohne einen
   einzigen Aufruf darin. Wer den Druck im Hauptprogramm zurücknehmen will,
   kommt dort nie wieder heraus — das wäre ein selbstgebauter Freeze gewesen
   und hätte den echten verdeckt. Also hängt `Klick_vbl` in der
   VBL-Warteschlange.
2. **`Mouse_int` muss währenddessen stillhalten.** Die Tastatur schickt auch
   ohne Bewegung Pakete; jedes davon berechnete `Button_state` neu und löschte
   den eingespeisten Druck, bevor die Hauptschleife ihn sah. Unter `PRUEFLAUF`
   steigt `Mouse_int` aus, solange `klick_dauer` läuft.

**Das Ergebnis: der Emulator zeigt den Freeze nicht.** Der eingespeiste Klick
auf Exit verlässt den Inventarschirm sauber — geprüft an vier Kombinationen
(4 und 14 MB, RGB und VGA), jedes Mal kommt die Karte zurück.

**Damit ist etwas ausgeschlossen und etwas nicht.** Ausgeschlossen ist, dass
allein die *Abfolge* der Routinen hängt. Nicht ausgeschlossen ist alles, was
an der echten Maus hängt: dass der Zeiger vorher über Thalions Bild bewegt
wurde (unser Softwarezeiger sichert den Hintergrund, und Thalions
Zeichenroutinen wissen nichts davon), die Dauer des Drucks, und die
IKBD-Pakete selbst.

**Ein Umweg, der Zeit gekostet hat.** Die erste Fassung holte die Klickstelle
aus einer Tabelle über einen Zeiger in `Fast_BSS`. Der stand beim ersten
Aufruf auf Programmbytes (`$602E0404`) statt auf dem Listenanfang, die Routine
stieg sofort wieder aus, und mehrere Messungen sagten nur „nichts passiert".
Für **eine** Stelle braucht es keine Tabelle; jetzt stehen die Koordinaten als
Konstanten da. Die Regel dazu ist dieselbe wie bei 157: was in `Fast_BSS`
liegt, ist erst brauchbar, wenn jemand es gesetzt hat — und wer sich darauf
verlässt, dass es genullt ankommt, prüft es besser einmal nach.

**Und ein Messfehler im Filter.** Die Spurzeilen enden auf CR; ein
`grep -E "^[0-9A-F]{8}$"` traf sie deshalb nie, und das sah aus, als hätte die
Routine geschwiegen. Erst `cat -v` zeigte es. Ein Filter, der nichts findet,
ist kein Befund, solange er nicht an etwas Bekanntem geprüft wurde.

## 159. Drei Anzeigen für einen Freeze -- und keine davon belegt

> **Stand 2026-09-26:** Der Freeze ist gelöst, siehe 160.
>
> Gruppe **M** (Messaufbau vor Befund), Regel in der Kurzform.

Nach Erkenntnis 158 (der Emulator zeigt den Klick-Freeze nicht) sollte ein
Messgerät auf die Hardware. Drei Fassungen, drei Fehlschläge -- festgehalten,
weil jeder von ihnen aus demselben Missverständnis kam: **eine Anzeige darf
nichts brauchen, was ein eingefrorenes Programm nicht mehr hat.**

1. **Eine Datei je Stufe** (`KLICK.TXT`), nach dem Muster von `TIMERB.TOS`.
   Dort war es richtig -- dort lief das Programm. Hier stehen die Aufrufe
   mitten im Klickweg und feuern viele Male je Sekunde; GEMDOS-Zugriffe in
   dieser Dichte haben den Lauf umgebracht, bevor er überhaupt bis zum Klick
   kam. Das Programm gab danach nicht einmal mehr seine Startmeldung aus.

2. **Ein Balken aus Bildpunkten.** Er braucht die *sichtbare* Seite des
   Doppelpuffers (`Physbase` ändert sich beim Umschalten und darf nicht
   einmal gemerkt werden), wird im gesunden Lauf von `Update_screen` sofort
   überschrieben, und zwischen Portrait und Statusleiste ist er im Bild nicht
   sicher zu lesen. Dazu ein eigener Fehler: die Ebenenbits rückwärts
   abgefragt, während der Zeiger vorwärts lief -- aus Farbe 31 wurde 248,
   schwarz auf schwarz. **Gezeichnet, aber unsichtbar sieht von außen genau
   aus wie gar nicht gezeichnet.**

3. **Die Rahmenfarbe** (`$FFFF9800`, Farbe 0). Im Selbsttest mit
   `-DKLICKHALT=n` ändert sich am Abzug nichts; zwei der drei Haltepunkte
   liefern sogar byteidentische Bilder. Ob der Halt nicht auslöst oder die
   Farbe nicht durchschlägt, ist **nicht geklärt**.

**Und eine Falle, die nichts mit der Anzeige zu tun hatte:** der
`INCLUDE` der Messroutinen stand **vor** `MAIN.S`, weil die Makros dort
gebraucht werden. Damit wurde `Klickspur` der erste Befehl im Abschnitt
`Program` -- also der Programmeinsprung. Der Lader sprang hinein, das
Programm schwieg vollständig, und **der Bau war fehlerfrei**. Makros gehören
vor `MAIN.S` (sie erzeugen keinen Code), Routinen dahinter; deshalb jetzt
`KLICKSPUR.I` und `KLICKSPUR.S` getrennt.

**Die Regel daraus, und sie ist teuer bezahlt:** wer für eine Messung ein
neues Messgerät baut, misst zuerst das Messgerät. `-DKLICKHALT=n` war der
richtige Gedanke -- nur zu spät. Und solange der Selbsttest nicht sagt
„Halt bei 9 zeigt grün", darf kein Ergebnis dieses Geräts gedeutet werden.

**Was statt dessen zuerst zu fragen war** -- und nichts kostet, weil der
Nutzer das Programm schon hat: läuft im eingefrorenen Zustand noch der
Mauszeiger? Reagiert eine Taste? Das trennt „Hauptschleife steht" von
„Interrupts sind tot" mit einem Blick und ohne eine Zeile Code.

### Nachtrag zu 159: eine offene Frage, die größer ist als das Messgerät

Beim Prüfen der Rahmenfarbe kam ein Ergebnis heraus, das ich **nicht erklären
kann** und deshalb als Frage stehen lasse, nicht als Befund.

Der Versuch: unmittelbar nach `Open_screen` vier Palettenschreibzugriffe und
dann eine Endlosschleife, damit niemand nachfärbt --

    move.l #$FC000000,$FFFF9800   ; VIDEL Farbe 0, Format aus RASTER.S
    move.l #$00FC0000,$FFFF9804   ; VIDEL Farbe 1, andere Byteordnung
    move.w #$0700,$FFFF8240       ; ST-Palette Farbe 0
    move.w #$0070,$FFFF8242       ; ST-Palette Farbe 1

Der Bildschirm bleibt **vollständig schwarz** -- in Hatari, bei 4 MB und VGA.
Der Bildspeicher ist zu diesem Zeitpunkt leer, alles ist also Farbe 0; wäre
einer dieser Schreibzugriffe angekommen, müsste die Fläche rot sein.

**Warum das mehr ist als eine Messgerätefrage:** `HULL/RASTER.S` schreibt im
Timer-B-Interrupt genau so, unmittelbar nach `$FFFF9800`. Wenn dieser Weg
hier nichts bewirkt, wäre das eine mögliche Erklärung für die gesamte
Rastergeschichte -- nicht der Timer und nicht die Liste, sondern das
Schreiben selbst.

**Was dagegen spricht**, und weshalb hier nichts geschlossen wird: das
Registerformat in `RASTER.S` ist nachgemessen worden (zurückgelesen und gegen
die bekannte TOS-Palette gehalten), und die Engine zeigt im Betrieb korrekte
Farben -- allerdings über `VsetRGB`, nicht über direkte Schreibzugriffe.
Zwischen „das Register trägt den Wert" und „der Bildschirm zeigt ihn" liegt
genau der Unterschied, um den es geht, und der ist nie geprüft worden.

**Nächster Schritt, wenn das wieder aufgegriffen wird:** ein eigenständiges
Programm in der Art von `FARBKANT.TOS` -- Modus setzen, Fläche füllen, Farbe
direkt schreiben, anhalten. Ohne Engine, ohne Interrupt, ohne Klickweg. Erst
wenn das eine rote Fläche zeigt, ist der direkte Palettenschreibzugriff
belegt; vorher ist jede Rastermessung auf Sand gebaut.

## 160. Ein Name, zwei Verträge — `Put_masked_block`

> Gruppe **V** (Name heißt Vertrag), **P** (Nachgebaut statt übersetzt), Regel in der Kurzform.

Der Klick-Freeze im Inventarschirm aus Thalions Quelle hatte eine Ursache, die
niemand erraten hätte, und sie stand die ganze Zeit im Quelltext:

**Thalions `Put_masked_block` ist koordinatenbasiert.** `INVENTOR.S:554`:

    move.w #208+6,d0 / move.w #85+35,d1
    moveq #24,d4 / moveq #3,d5 / moveq #1,d6 / moveq #9,d7
    lea.l Swordshield,a0
    jsr Put_masked_block

**Unser `Put_masked_block` war etwas ganz anderes**: der schnelle
16×16-Kachelblitter des Kartenzeichners mit `a3` = Quelle, `a4` = Ziel. Sein
Aufruf landete darin mit `a3 = 0` und einem `a4` aus einem früheren Aufruf und
schrieb **sechzehn Zeilen quer durch unsere Daten** — über `Y_string`,
`Window_stack`, `Offset_X`, `Offset_Y` und **`Tree_Sp`** hinweg.

Danach lief Thalions `Find_object` über `Tree_Sp` in eine Zeigerkette ins
Nichts; `Search_layer` folgt `Obj_brother`, bis eine Null kommt, und fand
keine. Der Rechner stand. **Ein Klick irgendwohin** genügte, weil jeder Klick
durch `Find_object` geht.

**Die Reparatur ist klein.** Unsere Kachelroutine heißt jetzt
`Put_masked_tile` — wie das `Put_unmasked_tile` direkt darüber, das von Anfang
an richtig hieß; der Name war schlicht danebengegriffen. Und `Put_masked_block`
gibt es jetzt wirklich: Thalions Vertrag ist der von `Put_masked_block2`, nur
mit X auf einer Blockgrenze — und eine Blockgrenze ist ein Sonderfall von
„irgendwo". Also ein `bra`.

### Wie es gefunden wurde — und was vorher alles daneben lag

Der Nutzer hat einen **Hatari-Savestate vor dem Klick** geschickt. Daraus:

1. Das Programm im Speicherabbild über eine Zeichenkette gefunden, die
   Ladeadresse aus einem verschobenen Zeiger zurückgerechnet
   (`Obj_tree.child` trägt `Map2D_L2`), damit jede Adresse lesbar.
2. `Tree_Sp` = `0x00E08FB6` — Unsinn. `Offset_X` = 224, `Offset_Y` = 4022.
   Der Baum**stapel** dagegen heil. Also ist der **Zeiger** kaputt, nicht die
   Daten.
3. Im eigenen Emulator dasselbe reproduziert, sobald das Richtige gemessen
   wurde: `Offset_X` wird `0x0FB6` — **derselbe Wert wie im Savestate**.
4. Mit der Stufenleiter auf `Display_small_member_info` eingegrenzt.
5. Hatari-Haltepunkt auf die Speicherstelle
   (`b ($2a71a).w = $0fb6 :once`), Rücksprungadresse vom Stapel geholt, die
   Aufrufstelle disassembliert — und dort stand Thalions Registersatz vor
   einem `jsr` in unsere Kachelroutine.

**Drei eigene Fehlschlüsse auf dem Weg**, alle aus derselben Wurzel:

- „Der Emulator zeigt den Fehler nicht" (Erkenntnis 158) war **falsch**. Er
  zeigte ihn die ganze Zeit; mein Prüfweg hat ihn nicht ausgelöst, und ich
  habe daraus auf die Hardware geschlossen statt auf meinen Prüfweg.
- Die Baumprüfung maß die Baum**daten** und fand sie heil — der kaputte Teil
  war der **Zeiger** daneben. Wer das Falsche misst, misst nichts.
- Die Schranke `Baum_heil` prüfte `Tree_Sp` nur auf „nicht null, gerade",
  nicht gegen den Stapelbereich. Darum ließ sie `0x00E08FB6` durch.

**Auf dem Gerät bestätigt (2026-09-20):** der Klick im Inventarschirm aus
Thalions Quelle friert nicht mehr ein.

**Die Regel, und sie ist größer als dieser Fall:** wo unser Code einen Namen
aus Thalions Bibliothek trägt, muss er **dessen Vertrag** erfüllen — nicht
einen eigenen. Ein abweichender Vertrag unter gleichem Namen ist kein
Übersetzungsfehler, den der Assembler findet, sondern ein stiller Schreiber
im fremden Speicher. Dasselbe Muster wie `Number` (Erkenntnis 157): unsere
Seite hat einen Namen des Originals mit eigener Bedeutung belegt.

## 161. Eine CIL ist mehr als neun Zahlen

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

Beim Einbinden von Thalions `HULL/CONTROLS.S` (Stufe 3b) fror die Engine auf
Hardware in der Anfangssequenz ein — **beim dritten und letzten Klick**, dem,
der das Textfenster schließt und den Kartenschirm aufbaut. Die zwei Klicks
davor blätterten den Text normal weiter, der Mauszeiger lief. Diese Genauigkeit
des Befundes war der halbe Fund: Textblättern zeichnet kein Tastenfeld, der
Aufbau des Kartenschirms schon.

Thalions `Display_control_icons` beginnt so:

    move.l Reeval_ptr(a0),d0    ; Re-evaluate CIL
    beq.s .Zero
    move.l d0,a1
    jsr (a1)

Eine **Control Icon List** ist bei ihm (Versätze aus `GAME_OFF.S`):

    rs.w 9          neun Symbolnummern
    Icon_vectors:   rs.l 9      die Routine je Taste
    Reeval_ptr:     rs.l 1      Neubewertung vor dem Zeichnen

zusammen 58 Bytes. **Unsere `CIL_tab` hatte nur die neun Worte**, sechs
Felder dicht hintereinander. `Reeval_ptr(a0)` traf damit die Symbolnummern
des nächsten Feldes, und `jsr (a1)` sprang dorthin — ein Wildsprung. Danach
steht alles, die Maus mit, weil die Hauptschleife nie zurückkommt.

**Die Reparatur:** unsere Tabelle hat jetzt Thalions Aufbau, mit null
Vektoren und null `Reeval_ptr`; `Aktuelle_CIL` rechnet mit `CIL_SZ` statt
`9*2`. Die Nullen sind kein Behelf, sondern der vorgesehene Zwischenzustand:
`beq.s .Zero` überspringt die Neubewertung, und unsere Hauptschleife wertet
die Tasten weiter über ihre **Nummer** aus (`Map_CIL_evaluate`). Wer einen
Vektor einträgt, schaltet Thalions `Do_control_icons` für genau diese Taste
scharf — eine nach der anderen.

**Dritter Fall derselben Klasse** nach `Number` (157) und `Put_masked_block`
(160): unsere Seite hat eine Struktur des Originals *kürzer* angelegt, als
sie ist. Der Assembler kann das nicht sehen, der Linker auch nicht — es
fällt erst auf, wenn sein Code die Struktur liest.

**Stand danach:** der Kartenschirm wird aufgebaut, der Hänger ist weg. Das
Tastenfeld bleibt aber **leer**: Thalions `Display_up_button` zeichnet aus
`Control_icons` und `Button_up`, und das sind bei uns Nullplatzhalter. Diese
Grafiken zu überbrücken ist der nächste Schritt von Stufe 3b.

## 162. Der dritte Stapel — `Reset_scroll_bar_stack` ruft niemand

> Gruppe **A** (Es fehlt ein Aufruf), Regel in der Kurzform.

Mit Thalions `HULL/CONTROLS.S` (Stufe 3b) blendete das Inventar auf Hardware
ins Schwarze und stand still — Maus eingefroren, kein Bild. Truhe und Karte
liefen. Die Stufenleiter (`-DINV2_STUFE=n`) trennte es in drei Läufen des
Nutzers: Stufe 2, 4 und **5 kommen ins Inventar**, die volle Fassung nicht.
Damit lag es hinter Stufe 5 — und der erste Aufruf dort ist
`Push Scroll_bar,Inv2_scroll_bar`.

    Push_Scroll_bar:
        movea.l Scroll_bar_Sp,a1
        addq.l  #4,a1
        cmpa.l  #Scroll_bar_Stack_end,a1
        beq.s   .Exit
        move.l  a0,(a1)          ; Push
        move.l  a1,Scroll_bar_Sp

`Scroll_bar_Sp` steht beim Start auf null. `addq.l #4` macht daraus 4, und
`move.l a0,(a1)` schreibt **nach Adresse 4** — mitten in die Vektortabelle.

**Die Grundstellung setzt `Reset_scroll_bar_stack`, und die ruft niemand.**
Sie steht in seiner Datei, ist dort `XDEF`-exportiert, wird aber im gesamten
freigegebenen Quelltext kein einziges Mal aufgerufen: das täte seine `MAIN.S`,
und die binden wir nicht ein. Unsere `MAIN.S` setzt Modul- und Baumstapel
längst auf (`Reset_module_stack`, `Reset_tree_stack`) — der dritte fehlte
schlicht.

**Auf dem Gerät bestätigt (2026-09-20):** mit dem Aufruf in der Startfolge
öffnet sich der Inventarschirm aus Thalions Quelle.

**Die Regel dazu:** wer eine Originaldatei neu einbindet, sucht darin nach
`Reset_*`-Routinen und fragt, wer sie ruft. Findet sich kein Aufrufer im
freigegebenen Quelltext, gehört der Aufruf in unsere Startfolge — denn dann
stand er in dem Teil, den Thalion nicht freigegeben hat.

Das ist dieselbe Sorte Lücke wie die fehlenden Symbole, nur unsichtbar: der
Linker vermisst nichts, der Assembler auch nicht. Es fehlt kein Name, es
fehlt ein **Aufruf**.

## 163. Neuzeichnen ist nicht Neuaufbauen

> Gruppe **P** (Nachgebaut statt übersetzt), Regel in der Kurzform.

Mit Thalions Inventarschirm blendete **jeder Klick auf einen Gegenstand** den
ganzen Bildschirm aus und wieder ein. Der Nutzer hat es sofort erkannt: „das
ist im Original nicht so."

Der Grund lag in unserer Seite. Nach einem Gegenstandszug rief
`src/INVENTOR.S` den vollen Bildschirmaufbau (`Inv2_aufbauen`), und Thalions
`Inv2_DisInit` endet mit `jmp Fade_in_bottom`. Solange unser Nachbau zeichnete,
fiel das nicht auf — der blendet nicht.

Im Original sind das **zwei verschiedene Dinge**, und er trennt sie sauber:

    Inv2_DisInit   einmal beim Auflegen des Moduls: Rahmen, Portrait,
                   Plätze, Tastenfeld -- und am Ende die Blende.
    Inv2_DisUpd    bei jeder Änderung: Update_status_block,
                   Update_damage_magic, Update_control_icons,
                   Update_small_member_info, Update_weight -- ohne Blende.

`Inv2_neuzeichnen` (`HULL/INVENTOR_SUP.S`) macht jetzt das Zweite: die neun
Körperplätze, den Rucksack und das Gewicht, dann `Update_screen`. Die übrigen
Teile von `Inv2_DisUpd` kommen dazu, sobald ihre Platzhalter echt sind.

**Die Regel:** wer eine Anzeige nach einer Änderung auffrischt, ruft nicht
ihren Aufbau. Der Aufbau darf blenden, Speicher anfordern und Stapel
auflegen — alles Dinge, die zwischendurch nichts zu suchen haben. Im
Original steht die Trennung in den Modulfeldern (`DisInit` und `DisUpd`)
und ist damit vorgezeichnet; wir müssen sie nur benutzen.

### Offen geblieben: das Symbol im Rucksackplatz

Der Platz wird gezeichnet (grauer Kasten aus `Draw_box` mit Farbe 27), das
Symbol nicht — obwohl der Gegenstand da ist: anklicken hebt ihn auf, und am
Zeiger ist er sichtbar. `Display_object` steigt also bei
`Object_index(a2) = 0` aus, liest mithin einen anderen Platz als unser Code.

Geprüft und **ausgeschlossen**:

- `Backpack_slots` = 9 × `Object_packet_size` = 54 — genau unser
  `CH_KOERPER*CH_PKT`.
- `Icon_size` = `Screen_depth*32` = 256 — genau der Abstand, in dem unser
  `Load_object_graphics` die aufgeweiteten Symbole ablegt.
- `Scroll_bar_result` ist nach `Init_scroll_bar` null (die
  Startposition kommt aus dem Nullplatzhalter
  `Inventory_scroll_bar_positions`), verschiebt den Platz also nicht.

Bleibt `Slotbase_handle`/`Slotbase_offset` und das Feldlayout dahinter. Das
ist zu messen, nicht zu lesen.

## 164. `Get` darf `d0` nicht verbrauchen — der unsichtbare Buckler

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

Im Inventarschirm aus Thalions Quelle blieb der Rucksackplatz grau, obwohl ein
Gegenstand darin lag: anklicken hob ihn auf, am Mauszeiger war er sichtbar,
ablegen ließ ihn wieder verschwinden. Gelöst an einem **Savestate** des
Nutzers, ohne eine einzige weitere Messfassung.

**Was der Savestate zeigte** — alles richtig:

| | |
|---|---|
| `Slotbase_handle` = 6 = `Inventory_handle` | ✓ |
| `Slotbase_offset` = 344 = `Char_inventory`(290) + `Backpack_slots`(54) | ✓ |
| `Object_pos_list` → `Backpack_pos_list` (109,76 …) | ✓ |
| Rucksackplatz 1: `01 00 00 00 00 b1` → `Object_index` = 177 | ✓ |
| Satz aus Handle 6 trägt bei +274 den Namen `THALION` | ✓ |
| `Item_pic` = 40, und Symbol 40 im geladenen Block ist ein Schild | ✓ |
| `Init_scroll_bar` gelaufen: `Row_height` 14, `max_height` 56, Update-Zeiger auf `Update_objects` | ✓ |
| Bildspeicher am Platz: durchgehend Farbe 27, **kein Symbol im ganzen Bild** | ✗ |

Also lief `Display_object`, zeichnete den Kasten und stieg vor dem Symbol aus
— bei `move.w Object_index(a2),d0 / beq .Exit`. Zwischen Kasten und Symbol
liegt genau eine Berechnung, und die beginnt mit unserem `Get`:

    Get   Slotbase_handle,a2        ; d0 = Platznummer
    add.l Slotbase_offset,a2
    add.w Scroll_bar_result,d0      ; <-- rechnet mit d0 weiter
    mulu.w #Object_packet_size,d0
    add.l d0,a2

**Unser `Get`-Makro schrieb die Adresse nach `d0` und ließ sie dort stehen.**
Sein Code rechnete danach „Adresse mal sechs" auf den Satzzeiger, las
`Object_index` aus dem Nichts, bekam null — und zeichnete kein Symbol. Der
Kasten kam trotzdem, weil dessen Koordinaten aus `a3` stammen.

Dasselbe Muster steht in `Display_body_object`, `ACTIONS.S:1218` und an
mehreren Stellen in `MAGIC.S`: **`d0` überlebt `Get`.** Der Rückgabewert ist
der zweite Makroparameter, nicht `d0`; ihn zu retten kostet zwei Befehle.

**Auf dem Gerät bestätigt (2026-09-22):** der Gegenstand erscheint im
Rucksackplatz, auf den man ihn ablegt.

**Vierter Fall derselben Wurzel** nach `Number` (157), `Put_masked_block`
(160) und der zu kurzen CIL (161) — diesmal in einem **Makro** der
nachgebildeten Bibliotheksschicht. Die Prüfung dagegen bleibt dieselbe: die
Aufrufstellen im Original lesen und den Registersatz vergleichen, bevor man
eine Nachbildung für fertig hält. `tools/register_pruefen.py` sieht Makros
nicht — sie werden expandiert, bevor es hinschaut.

## 165. Eine fest verdrahtete Schrittweite bestimmt das Datenformat

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

Das Tastenfeld blieb leer, seit Thalions `HULL/CONTROLS.S` die Bedienelemente
trägt: `Control_icons` und `Button_up` waren Nullplatzhalter. Beim Füllen kam
heraus, dass es dafür nur *einen* möglichen Weg gibt, und dass eine einzige
Zahl in seiner Datei ihn festlegt.

**Die Zahl steht in `Display_up_button`:**

    moveq.l #24,d4 / moveq.l #3,d5 / moveq.l #2,d6 / moveq.l #17,d7
    lea.l   Button_up,a0
    jsr     Put_unmasked_block
    lea.l   Control_icons,a0
    ... subq.w #1,d3 / mulu.w #13*12,d3 / add.w d3,a0

`13*12` ist kein Symbol und keine Konstante von uns — es sind 13 Zeilen zu 32
Punkten in **drei** Ebenen, ausgeschrieben in einer Datei, die wir nicht
ändern. Damit ist entschieden, was hinter `Control_icons` liegen muss:
Originaldaten. Unsere konvertierten acht Ebenen wären 416 Byte je Symbol, und
ab dem ersten Symbol stünde jede Adresse falsch. **Aufgeweitet wird erst beim
Zeichnen** (`pm3_wandeln` in `HULL/LIBRARY.S`), genau wie `Put_unmasked_block`
es für den Rahmen daneben längst tut.

**Was das an Leitziel 2 aufschließt:** die Symbole *sind* eine Spieldatei.
`Button_graphics` ergibt entpackt exakt 78 × 156 = 12168 Byte — Thalions
`Control_icons`, Byte für Byte, ohne einen Handgriff. Sie wird zur Laufzeit
über `Load_file` gelesen (JH+LOB) und unverändert kopiert. In Thalions
Dateinummern-Aufzählung kommt sie nicht vor; im Original füllt die nicht
freigegebene Bibliothek `Control_icons` daraus (Erkenntnis 131). Unsere
Nummer 45 hängt in `vorspann.i` hinten an, die Namenstabelle in
`HULL/FILES_SUP.S` wächst mit.

Der **Tastenrahmen** ist der Gegenfall: er liegt in keiner Spieldatei, nur im
Amiga-Programm (AM2_CPU, Hunk 3 ab 0x2860). Den kann zur Laufzeit niemand
holen, er kommt weiter aus dem Konverter — jetzt aber *roh* hinter den
aufgeweiteten Fassungen von Karteneintrag 27, statt zurückgerechnet zu werden.

**Belegt vor dem ersten Lauf, nicht danach.** Beide Quellen durch Thalions
`d4=24 / d5=3` gerechnet ergeben pixelgenau das, was unser Konverter bisher
erzeugt hat:

| | |
|---|---|
| Rahmen (`Button_up`, `Button_down`) | 544 von 544 Punkten gleich |
| alle 78 Steuersymbole | 32448 von 32448 Punkten gleich |

Das geht, weil der Konverter nur 24 addiert und 24 = `%11000` die unteren drei
Bits nicht anrührt — die unteren drei Ebenen der konvertierten Fassung *sind*
die drei Originalebenen. Auf Hardware bestätigt am 2026-09-22: die Tasten
werden korrekt gezeichnet.

**Die Hässlichkeit, die bleibt, und warum.** `d5` heißt in Thalions Quelltext
„Ebenen der Quelle". An den Objektsymbol-Stellen steht aber überall
`moveq.l #5,d5` — die Amiga-Bildtiefe —, während unser
`Load_object_graphics` den geladenen Block längst auf acht Ebenen aufweitet
(`Symbole_aufweiten`). Dort ist die Fünf ein überholter Wert. `Put_masked_block2`
kann `d5` deshalb nicht allgemein glauben; es gilt: **drei Ebenen heißt
Originaldaten, fünf heißt schon aufgeweitet.**

Auflösen ließe sich das nur, wenn auch die Objektsymbole unaufgeweitet
blieben — und das geht nicht, weil sie den Bankversatz 64 brauchen und
**Thalion den nicht übergibt**: an seinen Aufrufstellen ist `d4` gar nicht
gesetzt oder trägt die Farbe der Umrandung. Im Original brauchte es ihn auch
nicht, dort lagen Symbole und Bedienoberfläche in derselben 32-Farben-Palette.
Der saubere Weg führt also über die Palette des Inventarschirms, nicht über
die Zeichenroutine.

**Die Lehre neben 157, 160, 161 und 164:** ein übernommener Name verpflichtet
nicht nur auf Registersatz und Abschnitt, sondern auch auf **Schrittweite und
Speicherformat**. Wo im Original eine Größe ausgeschrieben dasteht statt als
Symbol, ist sie nicht verhandelbar — sie ist eine Zusage an unsere Daten.

## 166. Ein Register vorzubelegen heißt, es zu überschreiben

> Gruppe **R** (Register über einen Aufruf), Regel in der Kurzform.

Mit Thalions Modulstapel (`-DMODULE_C_THALION=1`) fror das Spiel beim Öffnen
einer Truhe nach der Blende ein. Es sah nach einer Tastaturwarteschleife aus
und war ein Absturz.

**Wie es gefunden wurde.** Die Hatari-Debugger-Aufzeichnung (`history`) zeigte
nur EmuTOS' `bconin2`, das mit `stop #$2300` auf eine Taste wartet, und keinen
einzigen Befehl von uns. Ein Haltepunkt auf den Befehl, mit dem TOS *wegen
leeren Puffers* schlafen geht (`b pc = $e0c9b8`), brachte die Zeile davor ans
Licht: `Bus Error reading at address $736840, PC=$198ee`. Die Warteschleife
war EmuTOS' Absturzmeldung, die in unserem Grafikmodus unsichtbar auf eine
Taste wartet.

- Der Befehl am Absturz-PC (`3411`, `move.w (a1),d2`) kommt im ganzen Programm
  genau einmal vor. Das ergibt die Ladeadresse `$13FC4` und die Stelle `fb_pl`
  in `Draw_box`.
- TOS schreibt bei jedem Absturz einen Nachruf nach `$380` (`proc_lives` =
  `$12345678`, Register, 16 Stapelworte). Aus dem Savestate gelesen, lieferte
  er die Register und den Stapelzeiger, aus dem Stapel die Aufrufkette:
  Kartenklick → `Action_2D` → Ereigniskette → Truhe → `OpenedChest_DisInit`
  → `oc_slot` → `Draw_box`.
- `a2` zeigte nicht auf die Platztabelle `oc_pos`, sondern auf den Text
  dahinter: `"GOLD"`. „GO" = 18255 als X, „LD" = 19524 als Y, und
  `p_buf + 19524*320 + (18255/16)*16` ist **genau** die Absturzadresse.

**Die Ursache.** In der Platzschleife der Truhe ist `d5` der Zähler
(`moveq #12-1,d5` … `dbf d5,oc_slot`). Im Tastenfeld-Schritt (Erkenntnis 165)
stand plötzlich `moveq #PLANES,d5` vor `Put_masked_block2`, damit die Routine
unsere Daten von Thalions Originaldaten (`d5=3`) unterscheiden kann. Jeder
belegte Platz setzte den Zähler damit auf 8 zurück, die Schleife lief über
ihre Tabelle hinaus und las den Text dahinter als Koordinaten. Dasselbe
steckte in unserer Inventar-Platzschleife (`iv_slot`). Die anderen drei
Stellen waren zufällig harmlos.

**Warum es kein Werkzeug fand.** `register_pruefen.py` prüft, ob eine Routine
fremde Register zerstört, also den Vertrag zwischen Aufrufer und Gerufenem.
Hier hat eine Routine ihr **eigenes, noch gebrauchtes** Register
überschrieben. Das ist eine Frage der Lebensdauer, nicht des Vertrags.

**Die Behebung** ist ein eigener Einsprung, `Put_masked_block8` in
`HULL/LIBRARY.S`: er rettet `d5`, setzt es auf `PLANES` und stellt es wieder
her. Unsere fünf Aufrufstellen rufen ihn, und kein eingefügter Befehl
berührt mehr ein Register des Aufrufers.

**Die Regel:** wer vor einem Aufruf ein Register vorbelegt, überschreibt es.
Vor jedem eingefügten `moveq`/`move` nachsehen, ob das Register an dieser
Stelle noch lebt, vor allem in Schleifen mit `dbf`. Besser noch: das
Vorbelegen in einen Einsprung verlegen, der das Register rettet.

**Zwei Nebenbefunde:**
- Die RAM-Abbildung in Hatari-Savestates (Version 2.6.1) ist linear: Atari-
  Adresse `A` steht bei Dateiversatz `$1B0E9 + A`, verankert an `memvalid`,
  `memval2` und `memval3`. Was beim Vergleich mit der Programmdatei wie Drift
  aussah, sind die Adressen, die der Lader verschiebt.
- Thalions `Update_member_status` (`DISPLAY.S`) behauptet „All registers are
  restored", rettet `a5` aber nicht; `a5` ist dort sein Rahmenzeiger. Bei ihm
  ist `a5` ein Hilfsregister, bei uns der Variablenzeiger. Hier war es nicht
  die Ursache, `a5` stimmte beim Absturz. Es ist aber eine Falle für jede
  Stelle, an der wir seinen Code rufen und danach auf `a5` vertrauen.

## 167. `Feedback`: derselbe Name, der sechste Vertrag

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

Jeder Klick aufs Tastenfeld, egal ob Exit, Richtungspfeil oder eine andere
Taste, zeichnete eine gedrückte Taste an den **linken Bildrand** und fror
danach ein. Es trat mit `MODULE_C_THALION` auf, hatte mit dem Modulstapel
aber nichts zu tun.

**Die Ursache.** Unsere Hauptschleife spricht die Tasten über ihre Nummer an
und rief `Feedback` mit unserem alten Vertrag: `d0` = Nummer eins bis neun,
Ergebnis in `d0`. Seit `-DCONTROLS_THALION` ist der Name an Thalions Routine
gebunden, und unsere ist unter `IFND` weggefallen. Seine erwartet:

    Feedback:  IN  d0 = X, d1 = Y, d3 = Symbolnummer
               OUT eq = ausführen, ne = verworfen; alle Register bleiben

Die Tastennummer wurde zur X-Koordinate, daher die Taste am linken Rand. Y war,
was zufällig in `d1` stand. War der Wert groß, schrieb `Put_unmasked_block`
über den Bildpuffer hinaus. Ob und wie es kracht, hing also vom Zufallswert
ab, und deshalb fiel es erst jetzt auf.

Die Übersetzung von Nummer zu Lage und Symbol gab es schon, allerdings nur
fürs Zeichnen (`Button_nach_nr`). `Feedback` hatte sie nie bekommen.

**Die Behebung** ist eine Brücke in `HULL/CONTROLS_SUP.S`:
`Taste_rueckmelden_maus` und `Taste_rueckmelden_taste` nehmen die Nummer,
holen Lage (`Icon_pos`) und Symbol (CIL), setzen `Key_or_mouse` und rufen
seine `Feedback`. Das Ergebnis geben sie wieder in `d0` zurück. Es sind zwei
Einsprünge statt eines Schalterregisters, damit an den Aufrufstellen nichts
vorbelegt werden muss (166). Ohne den Schalter zeigen beide Namen auf unser
altes `Feedback`. Die Brücke fällt weg, sobald `Handle_input` die Tasten über
`.Mev` verteilt.

**Einordnung:** das ist der sechste Fall aus derselben Familie wie 157, 160,
161, 164 und 165 und `Default_MA`. Neu daran ist die Richtung. Bisher rief
*sein* Code einen unserer Namen mit seinem Vertrag. Hier ruft **unser** Code
einen Namen, der unter dem Schalter *ihm* gehört, mit **unserem** Vertrag.
Wer eine Originaldatei hinter einen Schalter stellt, muss deshalb auch die
Aufrufstellen *in unserem Code* für jeden Namen prüfen, der dadurch den Besitzer
wechselt. Bei `CONTROLS.S` waren es 31 Namen.

## 168. Nach `move.w` ist das obere Wort Müll, und `add.l` nimmt es mit

> Gruppe **W** (Oberes Wort, oberes Byte), Regel in der Kurzform.

**Gelöst ist damit der älteste offene Hardwarefehler:** *Inventar per
Buchstabentaste verlassen friert ein, per Leertaste nicht.* Er stand seit
Wochen als unerklärt im Gedächtnis. Der Emulator zeigte ihn nicht, weil
`PRUEFLAUF` die Tastatur umgeht.

**Wie es gefunden wurde.** Der Nutzer schickte einen Savestate und die
Hatari-Warnung `Bus Error reading at address $74a6b4, PC=$18e9a`. Wie in
Erkenntnis 166 lieferte der TOS-Nachruf bei `$380` Register und Stapelzeiger,
und der Stapel die Kette:

    Taste (ml_kbd) → Basic_exit → Pop_Module → Exit_module → Pop_MA → MA_uebernehmen

**Die Ursache** steht in `Pop_MA` und genauso in `Push_MA` (`HULL/AREAS.S`):

    move.w  v_masp(a5),d0     ; setzt nur das untere Wort
    lsl.w   #3,d0
    lea     mastack,a0
    add.l   d0,a0             ; addiert das ganze Register

Das obere Wort von `d0` kam vom Aufrufer, und dort stand die gedrückte Taste.
`Poll_key` liefert nach `swap` den Scancode unten und **das ASCII-Zeichen
oben**. Im Nachruf: `d0 = $0071_0008`. `$71` ist `'q'`, die Taste des
Nutzers, und `$0008` ist Ebene 1 mal 8. `mastack` lag bei `$3A6AC` (dort
standen tatsächlich die Mausbereiche `0,0,304,184`), und `$3A6AC + $710008`
ergibt `$74A6B4`, die Absturzadresse.

**Das erklärt auch den Unterschied:** die Leertaste hat ASCII `$20`, die
Adresse wird `$23A6B4` und liegt noch im RAM. Dort wird Müll gelesen, aber
nichts stürzt ab. Buchstaben ab `$61` landen oberhalb von 4 MB, und dort
antwortet kein Speicher.

**Warum es vorher schon auftrat:** im Normalbau kam der Weg über
`Basic_exit` → `MA_vollbild` → `Push_MA`, und `Push_MA` hat denselben Fehler,
nur **schreibend**. Mit Thalions Modulstapel kam `Pop_MA` über sein
`Exit_module` hinzu.

**Die Regel:** wer ein Wort in ein Datenregister lädt und damit eine Adresse
rechnet, löscht vorher das Register (`moveq #0,dN`) oder rechnet mit
Wortindex (`(aM,dN.w)`). `mulu.w` ist sicher, weil es aus den unteren Wörtern
ein sauberes Langwort macht; `add.l`, `adda.l` und `lea (aM,dN.l)` sind es
nicht, und `divu.w` liest seinen Dividenden ebenfalls 32 Bit breit.
Ein grobes Suchmuster findet 37 weitere Stellen dieser Form in unserem Code.
Durchgesehen sind sie noch nicht.

## 169. Eine Adresse als Strukturversatz: `MA_X1(a1)`

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

Mit Thalions Ereignisliste im Inventar ging der erste Klick in die
Bildlaufleiste. Beim **Ziehen** des Schiebers sprang er an den oberen Rand
und darüber hinaus, danach kam ein Busfehler in `Draw_box` (`$14F1D70`).

**Die Ursache.** Sein `Scroll_bar_pressed` baut beim Ziehen einen
Mausbereich, damit der Zeiger in der Leiste bleibt:

    lea.l   Scroll_bar_MA,a1
    move.w  d0,MA_X1(a1)
    …
    move.w  d0,MA_Y2(a1)
    jsr     Push_MA

`MA_X1` bis `MA_Y2` sind bei ihm **Strukturversätze** aus der nicht
freigegebenen Include-Datei. Bei uns standen dieselben vier Namen als
**Variablen** im BSS (`engine.s`), also als Adressen um `$3A6xx`. Aus
`MA_X1(a1)` wurde `a1 + $3A6xx`: seine vier Schreibbefehle landeten irgendwo
im Speicher, `Scroll_bar_MA` blieb leer, `Push_MA` setzte den Mausbereich
auf 0,0,0,0, und der Zeiger klebte oben. Der Schieber rechnete daraus eine
Lage oberhalb der Leiste, und unser `Draw_box` (ohne Beschneidung) bekam eine
negative Zeile. Blättern ging, weil es keinen Mausbereich braucht.

**Warum es niemand meldete.** Ein Versatz mit einer Adresse passt nicht in
16 Bit. Mit `-m68030` kodiert vasm stillschweigend die volle 68020-Form mit
32-Bit-Basisversatz (`3380 0170 xxxxxxxx`). Auch mit `-m68000` übersetzt und
bindet es klaglos, am Minimalbeispiel geprüft. Die 68000-Gegenprobe hätte es
also nicht gefunden, entgegen meiner ersten Annahme. Sie läuft jetzt trotzdem
auch über den vollen Thalion-Bau, weil sie echte 68020-Befehle meldet.

**Ein Beleg nebenbei:** nach der Umbenennung ist `TASTEN.TOS` 20 Byte
kleiner. Seine vier Befehle werden jetzt mit 16-Bit-Versatz kodiert. Der
Fehler steckte also schon im `CONTROLS_THALION`-Bau und schlief dort, bis
jemand den Schieber zog.

**Die Behebung:** unsere Variablen heißen `Maus_X1` bis `Maus_Y2`, und
`vorspann.i` definiert `MA_X1 equ 0`, `MA_Y1 equ 2`, `MA_X2 equ 4`,
`MA_Y2 equ 6`. Das ist dieselbe Anordnung wie in der Print-Area, denn
`Open_window` übergibt `Push_MA` und `Push_PA` dieselbe Adresse.

**Einordnung:** der siebte Fall der Namensregel (157, 160, 161, 164, 165,
167). Neu ist die Art des Vertrags: nicht Register, Abschnitt oder
Schrittweite, sondern **Konstante gegenüber Adresse**. Er lässt sich
mechanisch finden: jedes `Name(aN)` in Thalions eingebundenen Dateien, bei
dem `Name` bei uns ein Label ist. Das steht als Prüfwerkzeug in docs/05.

## 170. `Draw_scroll_bar`: der zweite Aufruf mit altem Vertrag, und der Prüfgang danach

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

Nach dem ersten Inventarbesuch erschien dessen Bildlaufleiste auf jedem
Truhenschirm. Unser Truhenaufbau rief `Draw_scroll_bar` und meinte *unsere*
Routine: ohne Argumente, gezeichnet an `SB_X`/`SB_Y` nach `v_scroll`. Unter
`CONTROLS_THALION` war sie per `IFND` weggefallen. Der Aufruf traf **seine**
Routine, und die zeichnet die Leiste, auf die `Scroll_bar_data_ptr` zeigt.
Sein `Pop_Scroll_bar` lässt diesen Zeiger stehen, wenn der Stapel wieder
leer ist (`cmp.l #0,a0 / beq .Exit`). Damit blieb die Leiste des Inventars
gemeint, bis in den Truhenschirm. Es ist derselbe Fehlertyp wie bei
`Feedback` (167): unser Code ruft einen Namen, der unter dem Schalter ihm
gehört, mit unserem Vertrag.

**Behebung:** unsere Routine heißt `Truhe_leiste_zeichnen`, steht nicht mehr
unter `IFND` und fällt weg, sobald der Truhenschirm portiert ist.

**Der Prüfgang, den 167 schon nahegelegt hatte**, ist jetzt gemacht, und zwar
mechanisch. Er nahm alle 38 Marken, die in unseren Dateien unter
`IFND CONTROLS_THALION` stehen, dazu die Marken unserer ganzen
`HULL/CONTROLS.S`, und suchte die Stellen, die sie außerhalb solcher Blöcke
aktiv rufen. Übrig blieben acht Namen mit aktiven Aufrufern:

| Name | Befund |
|---|---|
| `Display_control_icons` | `a0` = CIL, gleicher Vertrag; CIL in voller Länge (161) |
| `Display_up_button`/`_down_button` | über `Button_nach_nr` übersetzt; im Mengendialog schon nach seinem Vertrag |
| `Draw_standard_box` | unsere Fassung folgte schon seinem Vertrag (Innenbreite, Innenhöhe) |
| `Find_large_text` | gleicher Vertrag |
| `Icon_pos` | gleiches Tabellenformat |
| `Push_Scroll_bar` | `a0` = Leistendaten, gleicher Vertrag |
| `Feedback` | nur noch aus der Brücke (167) |

Weitere Aufrufe mit altem Vertrag gibt es nach diesem Prüfgang nicht. Er
erfasst allerdings nur `bsr`/`jsr`/`jmp`/`bra`/`lea` auf den Namen. Wer einen
Namen über eine Tabelle anspringt (`dc.l Name`), fällt durch.

## 171. `Display_text`: der dritte Aufruf mit altem Vertrag, vor dem Test gefunden

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

Der Prüfgang aus 170 wurde für `WORDS_THALION` wiederholt, bevor seine
`HULL/WORDS.S` scharf ging. Er fand einen Aufrufer: unser `Show_pictxt`
(`EVENTS.S`), das Bild-und-Text-Fenster der Ereignisse, gleich beim ersten
Text nach dem Start. Es rief `Display_text` mit *unserem* Vertrag: `a0` zeigt
auf eine Zeichenkette, der Bereich steht in `pa_x`, `pa_y` und `pa_h`.
**Sein** `Display_text` will:

- `a0` = eine Liste von Zeichenkettenzeigern, mit 0 am Ende
- `d0` = 0 für einen noch nicht aufbereiteten Text, sonst ein Speicher-Handle
  von `Process_text`
- den Bereich aus dem aufgelegten Druckbereich (`PA_Sp`), nicht aus Variablen

**Behebung** (Brücke in `Show_pictxt`): eine Liste mit einem Eintrag bauen,
seinen `ShowPicTxt_PA` wörtlich als Druckbereich auflegen (`Push_PA`),
`d0` = 0 setzen, `Display_text` rufen und danach `Pop_PA`. Die übrigen Namen,
die unter dem Schalter den Besitzer wechseln, haben entweder keinen aktiven
Aufrufer (`Process_text`, `Erase_PA` …) oder denselben Vertrag
(`Print_centered_string`).

## 172. Druck-, Maus- und Clipbereich liegen als X1, X2, Y1, Y2 im Speicher; `Reset_PA_stack` ohne Aufrufer

> Gruppe **V** (Name heißt Vertrag), **A** (Es fehlt ein Aufruf), Regel in der Kurzform.

Der erste Hardwaretest mit `WORDS_THALION` blieb schwarz:
`Bus Error writing at address $4, PC=$17232`. Der `PC` liegt 18 Bytes hinter
seinem `Push_PA`, bei `move.l a0,(a1)`. Sein `a1` ist `PA_Sp + 4`, und
**`PA_Sp` war null**, weil niemand `Reset_PA_stack` rief. In seinen Quellen
gibt es keinen Aufrufer, im Original ruft ihn die nicht freigegebene
Bibliothek. Das ist derselbe Fall wie 162: zu jeder `Reset_*`-Routine den
Aufrufer suchen. **Behebung:** `jsr Reset_PA_stack` in `MAIN.S`, und zwar
**vor `Reset_module_stack`**. Der erste Versuch stand erst vor
`Mouse_install` und stürzte an derselben Stelle ab (`PC=$17236`, derselbe
Befehl, 4 Bytes weiter). Schon `Reset_module_stack` → `Push_Module` →
`Init_module` legt für das Grundmodul `Default_PA` auf, weil es keinen
eigenen Druckbereich angibt. Beim Suchen nach dem Aufrufer zählt also auch
jeder, der die Routine mittelbar erreicht.

Beim Lesen seines `Default_PA` fiel ein zweiter, älterer Fehler auf. Unsere
`vorspann.i` legte `PA_`, `MA_` und `CA_` als **X1, Y1, X2, Y2** an. Seine
Datensätze sagen etwas anderes:

| Satz | Werte | Datei |
|---|---|---|
| `Default_PA` | 0, 319, 0, 199 | `HULL/WORDS.S` |
| `Status_PA` | 0, 319, 0, 35 | `DISPLAY.S` |
| `ShowPicTxt_PA` | 18, 302, 139, 192 | `MODULES.S` |
| `MemberSel_MA` | 0, 319, 0, 35 | `HULL/CONTROLS.S` |
| `Lay3_ItemSelect_MA` | 16, 166, 139, 192 | `MODULES.S` |
| `Compass_CA` | 208, 239, 0, 199 | `DISPLAY.S` |

Die Reihenfolge ist also **X1, X2, Y1, Y2**, dieselbe wie bei den `Obj_`-Versätzen,
die schon stimmten. Unsere Reihenfolge war aus der Schreibfolge in
`Open_window` erschlossen worden, und die verrät sie gar nicht. Der Fehler
blieb unsichtbar, solange Namen schrieben und dieselben Namen lasen. Er wirkt
erst, wenn ein **Datensatz** über die Namen gelesen wird:

- Mit dem Absturz behoben hätte sein `Init_PA` aus `Default_PA` eine
  Druckbreite von einem Zeichen errechnet.
- Sein `Status_PA` wurde auch im Normalbau schon verdreht gelesen.

Auch meine `MA_`-Versätze aus 169 standen in der falschen Reihenfolge.

**Behebung:** die Versätze umgestellt, dazu unsere vier Sätze, die in unserer
Reihenfolge standen: `Default_MA`, `Default_PA` (Platzhalter), `ca_full` und
`sp_pa`, das jetzt eine wörtliche Kopie von `ShowPicTxt_PA` ist. Der innere
Stapel von `Push_MA` behält seine eigene Anordnung, gefüllt wird er über die
Namen.

**Lehre:** Ein Strukturversatz ist erst belegt, wenn ein Datensatz aus seinem
Quelltext ihn bestätigt. Aus einer Folge von Zugriffen lässt er sich nicht
ablesen.

## 173. `Put_text_line` rückt `a0` vor; `Right_clicked` war geraten

> Gruppe **E** (Rückgabewerte), **V** (Name heißt Vertrag), Regel in der Kurzform.

Nach 172 erschien der Anfangstext, aber falsch: **eine Zeile stand mehrfach
im Textfeld, jedes Mal versetzt und in anderer Farbe.** Ein Mausklick
blätterte weiter, danach war die Maus gefangen, Hoch und Runter verschoben den
Text, und nichts führte zurück auf die Karte.

**Die Zeilen.** Thalions `Refresh_text_window` gibt einen aufbereiteten Text so
aus:

    .Loop2: move.b (a0)+,d6        ; Tintenbyte der Zeile
            subq.w #1,d6 / move.w d6,Ink_colour
            jsr    Put_text_line
            addq.w #Char_height+2,d1
    .Entry2: dbra  d7,.Loop2

`a0` wird dabei nie neu geladen. Also gibt sein `Put_text_line` (nicht
freigegebene Bibliothek) `a0` **hinter der Endnull** zurück. Unseres stellte
`a0` wieder her. Jede weitere Zeile druckte darum denselben Text, ein Zeichen
später beginnend, und der jeweils übersprungene Buchstabe wurde zur Tinte.
Seine übrigen Aufrufer laden `a0` vor jedem Aufruf neu und merken davon
nichts. Deshalb fiel es erst mit seinem `Display_text` auf. Dass sein
`Print_centered_string` „All registers are restored“ verspricht, stimmt
darum nicht ganz: `a0` rückt über `Put_text_line` mit vor.

**Behebung:** unser `Put_text_line` schreibt vor dem Rückweg das
vorgerückte `a0` in seinen Stapelplatz. Alle 18 unserer Aufrufer sind
geprüft: keiner liest `a0` danach, ohne es neu zu laden oder vom Stapel zu
holen.

**Der gefangene Text.** Ist ein Text länger als das Fenster, blättert
`Display_text` erst Seite um Seite (je ein `Wait_4_user`). Danach kommt das
freie Scrollen: `Mouse_off`, ein eigener Mausbereich (`Scroll_MA`), die
Mauslage wird zur Textzeile. Verlassen wird es nur über
`btst #Right_clicked,Button_state`, also mit der **rechten** Maustaste.
`Right_clicked` stand in `vorspann.i` als geratenes Bit 2, und das setzt
unser `Mouse_int` nie. **Behebung:** `Right_clicked equ Right_pressed`,
angenommen, nicht belegt. Gleich danach folgt bei ihm `Wait_4_unclick`, also
genügt die gedrückte Taste.

**Nebenbei:** unser `Wait_4_user_Mod` trägt jetzt, wie seiner in
`MODULES.S`, `Click_Mptr` als Zeiger und `-1` für Druck- und Mausbereich
(nichts auflegen). Vorher standen dort Pfeil, `Default_PA` und
`Default_MA`.

## 174. Befehle bleiben im aufbereiteten Text; `Mouse_off` muss wirken; ein Warten zu viel

Nach 173 stand der Text richtig, aber beim Hochscrollen ragte eine Zeile mit
ihrem letzten Wort rechts über den Rahmen, dazu etwas links davon. Im freien
Scrollen wurde aus dem Klick-Zeiger ein Pfeil am oberen Rand. Nach dem
Rechtsklick brauchte es noch einen Linksklick bis zur Karte.

**Befehle im Text.** Sein `Process_text` lässt `~…~`-Befehle in der Zeile
stehen. `Add_line` kopiert sie mit, beim Umbruch zählen sie nicht zur Breite,
und `Scan_line_for_ink` liest nur die Anfangstinte daraus. Ausgewertet werden
sie also erst beim Setzen, in seinem `Put_text_line` (nicht freigegebene
Bibliothek). Unseres druckte sie als Zeichen, und jede Zeile mit Befehl wurde
um dessen Länge zu breit. Unser früherer Nachbau von `Process_text` hatte sie
vorher entfernt, darum fiel es erst jetzt auf.

Gezählt in den Kartendaten (`build/MAP*.AMF`): `~LEAD~` 17–18, `~SUBJ~` 10,
`~INVN~` 6, `~CAST~` 3, `~SELF~` 1–2 je Karte, **kein** `~INK~`. Die
Überbreite kommt also von den Namensbefehlen. Die ersetzt im Original
`HLC_handler` schon in `Process_text`, über `HLC_table` aus **seiner**
`MAIN.S` (`Insert_leader_name` …), und die ist nicht eingebunden. Bei uns ist
`HLC_table` leer, die Befehle bleiben stehen.

**Behebung:** unser `Put_text_line` überspringt alles zwischen zwei
`Command_char`, `~INK nn~` setzt `Ink_colour` wie in `Scan_line_for_ink`, und
`$` wird als Leerzeichen gesetzt. **Folge:** die Namen fehlen im Text, bis
`HLC_table` gefüllt ist. Ob die Überschreitung *links* denselben Grund hat,
ist nicht belegt.

**`Mouse_off`/`Mouse_on`** waren ein leeres `rts`. Vor dem freien Scrollen
schaltet sein `Display_text` den Zeiger ab und setzt `Mouse_Y` auf die
Scrollstellung. Bei uns blieb der Zeiger sichtbar, als Pfeil (das Wartemodul
war schon abgenommen) und oben am Rand. **Behebung:** eine Merkzelle
`maus_aus`. Solange sie gesetzt ist, lassen `Update_screen` und
`Update_mouse` den Zeiger weg. Sein Ziehen an der Bildlaufleiste ruft das
Paar ebenfalls, dort verschwindet der Zeiger jetzt auch, wie im Original.

**Das zweite Warten.** Sein `Show_pictxt` endet in `Do_text` →
`Display_text_and_wait`, das selbst wartet: bei kurzem Text über
`Wait_4_user`, bei langem mit dem Rechtsklick im freien Scrollen. Unsere
Hauptschleife rief danach noch `Wait_key`. **Behebung:** die Brücke ruft
`Display_text_and_wait`, `Wait_key` steht unter `IFND WORDS_THALION`.

## 175. Sein Umlagern zeichnet in einen Schmierbildschirm: `Work_screen` und `d5` sind Bibliotheksverträge

Erster Versuch mit seinem Umlagerweg (A3, Sprosse 2). Die Zeilen
`Move_body_item`, `Move_backpack_item` und `Move_all_backpack_items` in
`Inv2_Mev`, seine Deskriptoren `Move_item_Mod` und `InputNr_Mod` wörtlich aus
`MODULES.S`. Beim Aufnehmen erschien seine Meldung 55 „Wohin damit?“ an der
richtigen Stelle (siehe unten), dann Grafikmüll unter dem Zeiger und
`Bus Error reading at address $446be4` in unserem `Put_char_at`.

**Die Ursache steht in seinem `Create_object_graphics`** (`INVENTOR.S`), das
das Bild des getragenen Gegenstands baut:

    move.l #5*2*24,d0 / jsr Allocate_CHIP     ; Puffer: 5 Ebenen, 24 Zeilen
    move.l #24*Bytes_per_line,d0 / ...        ; Schmierbildschirm
    move.l d0,Work_screen                     ; ab hier zeichnet alles dorthin
    moveq #5,d5 / jsr Put_masked_block2       ; Symbol, 5 Ebenen
    jsr Print_centered_string                 ; Stueckzahl
    moveq #5,d5 / jsr Get_block               ; 5 Ebenen in den Puffer
    move.l Off_screen,Work_screen

Zwei Verträge seiner Bibliothek, die unsere nicht erfüllt:

- **`Work_screen` ist das Zeichenziel.** Unsere Routinen zeichnen immer nach
  `p_buf`; `Work_screen` war eine leere Zelle. Das Symbol landete oben links
  im echten Bild.
- **`d5` ist die Ebenenzahl der Quelle bzw. des Ziels.** Unser `Get_block`
  kopierte immer 8 Ebenen, 384 Byte in einen 240-Byte-Puffer: 144 Byte
  fremder Speicher überschrieben. Der Busfehler ist sehr wahrscheinlich eine
  Folge davon; gemessen ist das nicht.

`Create_string_graphics` (`HULL/CONTROLS.S`, die Namen beim Überfahren)
folgt demselben Muster.

Ausgezählt über alle Zeichenaufrufe in seinen eingebundenen Dateien: `d5` ist
1 (Silhouetten), 3 (Rahmen, Tasten, mit `d4`=24), 5 (Gegenstände, Portraits,
Statussymbole, HDOBs, **`d4` meist ungesetzt**) oder `Screen_depth` (volle
Kopie). Bei 5 Ebenen gab es auf dem Amiga nichts aufzufüllen; die Palette
je Bildbereich lieferte der Copper. Bei uns muss die Bibliothek die
Farbbank aus der Bildzeile ableiten. **Das ist Plan B**, und es ist
Bibliotheksarbeit: sein Code ist über `Screen_depth`, `d4`/`d5` und
`Work_screen` hardwareunabhängig (siehe CLAUDE.md, „Die Hardwaregrenze liegt
in der Bibliothek“).

**Folge:** die vier Umlagerzeilen sind zurückgestellt, bis B1 steht. Was
bleibt und nicht schadet:

- `Mouse_int` meldet zusätzlich **`$02` = links losgelassen**. *Angenommen:*
  `$02` steht in seinem Quelltext elfmal, jedes Mal am Ende einer Geste
  (`Backpack_item_moved`, `Body_item_moved`, `Member_moved`, `Load_selected`,
  `Option_selected`, `Options_aborted`).
  **Stand 2026-09-28: falsch.** Im Original heißt `$02` „links eben
  gedrückt“, losgelassen ist `$04` (Erkenntnis 252).
- `Move_item_Mod`, `InputNr_Mod`, `Basic_VblQ`/`Basic_ScrQ` wörtlich in
  `MODULES.S`; `Pick_Mptr` als Platzhalter (Pfeil, das Bild fehlt).
- **`Inv2_Mod` trägt seinen Druckbereich** `.PA: dc.w 21,181,50,70,2,0,
  Window_colour`. Mit 0 legte `Init_module` den `Default_PA` auf, den ganzen
  Schirm, und jede Meldung hätte mit `Erase_PA` den ganzen Bildschirm
  gelöscht. Belegt auf Hardware: „Wohin damit?“ stand unter „Inventar“.

## 176. Die Farbbank kommt aus der Bildzeile; `Icon_size` ist der Abstand in seinen Daten

> Gruppe **F** (Farben und Bänke), Regel in der Kurzform.

*2026-09-25, Plan B1c/B3, auf Hardware bestätigt („scheint alles zu passen“).*

**Die Farbregel für Originalgrafik** gilt jetzt in `Put_unmasked_block` und
`Put_masked_block2` gleich, für jede Quelle mit `d5 < 8`:

    Farbe = Farbbank(y) + (d4-Bits von d5 bis 4) + Quellwert,  0 bleibt 0

Von `d4` zählen nur die Bits, die der Amiga-Schirm mit fünf Ebenen hat. Bei
`d5=3`, `d4=24` ergibt das 24..31, bei `d5=5` bleibt nichts. Das passt zu
seinen Aufrufern, die bei Objektsymbolen `d4` gar nicht setzen
(Erkenntnis 175). Der Sonderweg „`d5=3` heißt Original, `d5=5` heißt schon
aufgeweitet“ ist weg.

**Die Bank ersetzt den Copper**, und sie ist nicht fest. `Set_fade` lädt die
Palette, die die Rasterliste nennt, in **Bank 0**: im Inventar `Main_pal`,
auf der Karte `Current_pal`. Bank 2 (64..95) hält immer `Main_pal`. Also:

- Die letzte `R_palette` mit Zeile ≤ y nennt die Palette der Zeile.
- Steht genau die in Bank 0 (`Bank0_pal`, von `Set_fade` und
  `Karte_gesetzt` mitgeschrieben), ist die Bank 0.
- Ist es `Main_pal` und Bank 0 trägt etwas anderes, ist sie `MAIN_BANK` = 64.
- Ein Hilfsschirm (`Work_screen` ≠ `Off_screen`) bekommt Bank 0; `Get_block`
  streift die oberen Ebenen ohnehin ab.

Meine Skizze sagte noch „`Main_pal` → 64“. Das hätte im Inventar die falsche
Bank gegeben, denn dort steht `Main_pal` in Bank 0. Aufgefallen beim Lesen von
`Set_fade`, vor dem Bau.

`R_range` (Farbe 25 wechselt zeilenweise hinter den Portraits) bleibt
unbeachtet: im Inventar ist der Verlauf eine flache Farbe. Mit dem Nutzer
abgesprochen; ein Timer-B als Copper-Ersatz könnte ihn später bringen.

**`Icon_size` ist der Abstand in seinen Daten, nicht die Größe auf unserem
Schirm.** Er rechnet überall `mulu.w #Icon_size,d0` nach `Get
Object_gfx_handle,a0`, auch für Kartensymbole (`Icon_size*2`) und
Statussymbole. Auf dem Amiga war `Screen_depth*32` gleich der Datentiefe mal
32; bei uns sind das zwei Zahlen. `vorspann.i` hat darum `Data_depth` = 5 und
`Icon_size = Data_depth*32` = 160. Vorher war es 256, und
`Load_object_graphics` weitete die Symbole beim Laden auf 8 Ebenen, damit
das passte. Jetzt stehen `Load_object_graphics` und `Free_object_graphics`
wörtlich wie in seiner `MAIN.S`. Die alte Freigabe rief `Destroy_fake_handle`
auf einen echten Speicherblock und gab ihn nie zurück.

**Offen:** `Put_masked_icon` für die Statussymbole bekommt von ihm
`d5=Screen_depth` (`DISPLAY.S`). Kommen die Statussymbole einmal aus seinen
Daten, stimmt dort `d5` nicht zur Quelle. Heute sind sie Platzhalter.

## 177. `a5` gehört nicht zum Bibliotheksvertrag

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

*2026-09-25, A3 Sprosse 2 (Umlagern), vor dem Test gefunden am Absturz
`Bus Error reading $567018, PC $1a056` in `Put_char_at`.*

Aufnehmen legt `Move_item_Mod` auf, ein `Local_mod`. Seine innere Schleife ruft
jedes Bild `Move_item_DisUpd` → `Inv2_DisUpd`. **Das lief bei uns nie**, denn
unser `Inv2_Mod` hat kein `DisUpd`. Darin steckt `Update_status_block` →
`Display_portrait`, und das legt einen lokalen Rahmen an:

    lea.l -Display_member_LDS(sp),sp
    move.l sp,a5
    ...
    jsr Print_centered_string           ; -> unser Put_text_line

Unsere Bibliothek liest ihre Variablen über `a5` (`p_font`, `txt_x`, `txt_y`,
`v_colour`). Aus dem Rahmen heraus war das der Stapel, und `Put_char_at`
schrieb nach `$567018`.

**Seine Bibliothek reserviert `a5` nicht.** In seinen eingebundenen Dateien
benutzen sechs Routinen es als Rahmen- oder Datenzeiger: `Process_text`,
`Drop_HDOB`, `Use_item` (`Current_event_data`), `Scan_4_transfer_victims`,
`Display_portrait`, `Update_member_status`. Gemessen: 13 unserer Routinen, die
sein Code ruft, hängen an `a5` (`Put_text_line`, `Update_screen`,
`Switch_screens`, `Push_MA`/`Pop_MA`, `Push_Mptr`/`Pop_Mptr`, `Set_fade`,
`Handle_event_chain`, `Find_event`, `Check_event_save_status`,
`Close_current_file`, `Exit_program`). Innerhalb eines seiner Rahmen gerufen
werden heute `Put_text_line`, später `Switch_screens` (über `Drop_HDOB`) und
`Handle_event_chain` (über `Use_item`, das dort `a5` absichtlich auf
`Current_event_data` setzt: ein eigener Vertrag, zu prüfen, wenn es läuft).

**Regel:** Ein Bibliothekseinsprung, den sein Code erreicht, holt sich den
Variablenblock selbst (`movem ... a5` / `lea vars,a5`). Umgesetzt in
`Put_text_line` und `Update_screen`. Für die Mausvariablen galt dasselbe
schon einmal, sie stehen darum absolut (Erkenntnis 138).

**Nebenwirkung, gewollt:** `Inv2_DisUpd` zeichnet beim Tragen seine
Portraitleiste. Deren Grafiken (`Status_TB`, `Status_M` …) sind noch
Platzhalter.

## 178. `My_vsync` rettet alle Register; ein `DisUpd` braucht einen Rufer

> Gruppe **R** (Register über einen Aufruf), **A** (Es fehlt ein Aufruf), Regel in der Kurzform.

*2026-09-25, nach dem `Inv2_ModInit`-Schritt. Zwei Hardwarebefunde: Trank
auf Körperplatz → „Kann nicht bereit gemacht werden.“ → Stillstand; Gewicht
kommt beim Ablegen nicht wieder dazu. Der erste am Savestate des Nutzers
gelöst.*

**Stillstand.** Stapel im Savestate: `Move_item_Mod` → `Handle_list` →
`Body_item_moved` → `Do_prompt` → `Do_text` → `Print_text_and_wait` →
`Display_text` → `Delay` → `My_vsync` → XBIOS `Vsync`. Sein `Delay`
(HULL/VARIOUS.S) zählt in `d0`:

    .Loop:  jsr My_vsync
    .Entry: dbra d0,.Loop

Unser `My_vsync` war nur `trap #14`, und XBIOS darf `d0–d2/a0–a2`
überschreiben. Im Abbild stand der Bildzähler `_frclock` = `$67B1` auch in
`d2`, `d0` begann jedes Bild neu. `Delay 10` kehrte nie zurück. Weil niemand
mehr `Update_screen` rief, stand auch der Mauszeiger. VBLs liefen weiter
(CPU gerade im VBL-Interrupt, `vblsem` = 1). Aufgefallen ist es erst, seit
sein `Delay` unseren Nachbau ersetzt. **Regel:** `My_vsync` rettet alle
Register (FADE_SUP.S).

**Gewicht.** Seine Rechnung stimmt (`Backpack_item_moved`, `Add_item_2_body`
zählen wieder dazu). Angezeigt wird es in `Inv2_DisUpd` → `Update_weight`,
und das ruft `Update_display` jedes Bild für das oberste Modul. Beim Tragen
ist das `Move_item_DisUpd`, darum sank die Anzeige. Nach dem Ablegen lag
wieder `Inv2_Mod` oben, mit `DisUpd` = 0, und unsere Hauptschleife rief
`Update_display` gar nicht. Abhilfe (Brücke): `Inv2_DisUpd_Bruecke` (seins
ohne `Update_status_block`) im Deskriptor, die Hauptschleife ruft im
Inventar `Update_display` und `Update_screen`.

**Nebenbei:** `Wait_4_user_Mod` trägt jetzt wie seins −1 bei `DisUpd`,
`VblQ`, `ScrQ` und Rasterliste, erbt also vom Modul darunter.

## 179. `Prompts` und `Object_data` gehören zu AM2_CPU; die Fassung 1.20 trägt sie als Dateien

*2026-09-25, Leitziel 2. Auf Hardware bestätigt: Meldungen, Stapeldialog,
Gewicht, Körperplätze, Kartenwechsel.*

Sein Code liest beide Tabellen über Marken, nicht über Dateien:

    lea.l Prompts,a0 / jsr Do_text             ; CONTROLS.S, Do_prompt
    lea.l Object_data+4,a1                     ; INVENTOR.S, überall

In seiner Dateiaufzählung (`GAME_OFF.S`, `Party_data_file` …
`Object_gfx_file`) stehen sie nicht. Im Original liegen die Bytes in AM2_CPU.
Die deutsche Fassung 1.20 trägt dieselben Bytes als eigene Dateien, beide in
einer JH-Hülle mit LOB:

- **`Text.amb`**, ausgepackt 18.526 Byte, drei Blöcke hintereinander:
  - `$0002`: 46 Texte, Tabelle aus *Versätzen* (Disketten- und
    Fehlermeldungen)
  - `$05D8`: 300 Texte, Tabelle aus *Längen*. Das ist `Prompts`, genau das
    Format von `Find_large_text`, 12.742 Byte.
  - `$379E`: 31 Texte, nur NUL-getrennt (`Find_small_text`,
    Ereignisnamen)
- **`Objects.amb`**, ausgepackt 24.122 Byte: ein Wort Anzahl (402), dann die
  Sätze zu 60 Byte. `Object_data` hat **vier** Byte Kopf (Anzahl,
  Satzlänge), daher sein `+4`. Die Satzlänge setzt `Load_objects`.

**Umsetzung:**
- Die Nummern sind unsere, wie `Button_gfx_file` = 45 (Erkenntnis 131):
  `Text_file` = 46, `Objects_file` = 47 (`vorspann.i`).
- Die Bibliothek lädt beide beim Start über `Load_file` an die Marken und
  gibt das Handle wieder frei (`Lade_meldungen`, `Load_objects`).
- Vorher mit Python gegengerechnet: byte-gleich mit dem alten
  Karteneintrag 30 bzw. `OBJECTS.AMF`.
- Karteneintrag 30 bleibt **leer** stehen, damit die Kacheln bei 31 bleiben.

## 180. `rseven` richtet aus, und Thalions `Party_data` ist der Spielstand

*2026-09-26, beim Einbinden von Thalions `MAIN.S` als zweite
Übersetzungseinheit (`engine/spiel.s`). Ohne Emulator belegt, siehe unten.*

**`rseven` war leer.** In `vorspann.i` stand das Makro ohne Inhalt, mit der
Annahme, vasm richte `rs.w` und `rs.l` selbst aus. Das tut es nicht: nach
einem ungeraden `rs.b` liegt das folgende `rs.w` ungerade. Richtig ist

    rseven  MACRO
            rs.b  __RS&1
            ENDM

(`__RS` ist vasms RS-Zähler). Betroffen sind zwölf Versätze aus
`GAME_OFF.S`, darunter `Trans_data_size` 5 → 6, `Map_data` 331 → 332,
`NPC_data` 11 → 12 und die vier `Monster_*`-Maße. Die Symboltabelle von
`engine.s` war vor und nach der Korrektur gleich: **keiner** dieser Versätze
wird dort benutzt. Erst Thalions `MAIN.S` braucht sie.

**`Party_data` ist `Party_data.sav`.** Der Block in Thalions `MAIN.S`
(`Year` … `Order`, danach `Modifications`) ist Byte für Byte die Datei.
Thalions `Init_program` kopiert `Party_data_size` Byte hinein und übergibt
den Rest der Datei an `Init_modifications`. `Trans_data` ist
`Max_transports*Trans_data_size` groß. Mit dem leeren `rseven` lag darum
alles ab `Quest` 32 Byte zu tief, und `Party_data_size` war 13.770 statt
13.802.

**Beleg:** `spiel.s` prüft am Ende `PD_SIZE` und alle fünfzehn `PD_*`-Versätze
aus `FALCON_OFF.S` gegen Thalions Marken (`pruefe PD_QUEST,Quest-Party_data`
…). Mit dem neuen `rseven` stimmen alle. Mit dem alten schlagen genau
`PD_SIZE` und die neun Versätze ab `Quest` an; `Map_nr` … `Member_nrs` liegen
vor `Trans_data` und bleiben richtig.

**Folge für die Bibliothek:** es darf nur **einen** Spielstand geben.
`Load_party_data` (MAP/MAP.S) lädt jetzt wie Thalions `Init_program`
`Party_data_file` nach `Party_data` und ruft `Init_modifications`. `p_party`
zeigt auf `Party_data`. Unser Puffer `partydat`, `newwords`, unser
`Access_bit_array` und das Konverterprodukt `PARTY.DAT` sind weg
(Leitziel 2).

**Thalions `Access_bit_array` hat einen anderen Vertrag als unser
Nachbau:**
- Beim Prüfen steht das Ergebnis nur im Z-Flag, `d0` bleibt erhalten.
- `d1` geht mit allen 32 Bit in die Adresse ein (`add.l d1,a0`).

Unsere drei auswertenden Aufrufer setzen darum `sne d0` selbst. Alle laden
`d1` mit `moveq`.

**Nebenbefund:** Die alte `Load_party_data` rettete `d0` und stellte es am
Ende wieder her. Ihr eigenes Ergebnis ging dabei verloren, die Meldung
„PARTY.DAT fehlt“ hätte nie erscheinen können.

## 181. Zwei Übersetzungseinheiten, wie bei Thalion

*2026-09-26.*

Thalions Quelltext definiert zwei Namen doppelt: `Number` (MAIN.S und
HULL/MODULE_C.S) und `Control_list_ptr` (MAIN.S und HULL/CONTROLS.S). Das
geht, weil Thalion die HULL-Dateien getrennt übersetzt hat. Sie tragen
`XDEF`/`XREF` (CONTROLS.S allein 77 `XDEF`), und was nicht exportiert ist,
bleibt privat. In einer Einheit stoßen die Namen zusammen, und Thalions
Dateien ändern wir nicht.

Darum zwei Einheiten:
- **`engine.s`** („Bibliothek“): Thalions HULL/, unsere Schicht, unser
  Nachbau, vorerst auch INVENTOR.S und DISPLAY.S.
- **`spiel.s`** („Spiel“): Thalions MAIN.S, dazu `src/MAIN_STUBS.S`.

`tools/einheiten_verbinden.py` übersetzt jede Einheit einmal mit Listing und
schreibt `build/xdef_<einheit>.i` mit genau den Namen, die die andere
braucht. Eine Marke, die in beiden Einheiten definiert ist, bricht den Bau
ab. Sonst gäbe es still zwei Variablen, und Thalions Code schriebe in eine
andere, als unser Code liest. Ausgenommen sind nur die zwei oben. Übersetzt
und gebunden wird an einer Stelle (`tools/engine_uebersetzen.sh`), die
Bau und Prüfweg beide rufen.

**Drei Regeln aus dem ersten Bau:**
- **Kein `bsr` über die Grenze.** Die Einheiten liegen mehr als 32 KB
  auseinander (`bsr Load_object_graphics`: Abstand $D322). Thalions Dateien
  springen dort ohnehin mit `jsr`.
- **Mit einem eingeführten Namen rechnet vasm nicht.**
  `#Party_data_size/2-1` geht in `engine.s` nicht. Wir nehmen die
  gleichwertige Konstante aus `FALCON_OFF.S`, und `spiel.s` prüft die
  Gleichheit.
- **Thalions `MAIN.S` bringt den Abschnitt `Longword_BSS`.** vlink braucht
  dafür `-N Longword_BSS .bss`.

**Was der Wechsel sonst mitbrachte:**
- 107 Doppelte fielen weg, davon 93 Platzhalter.
- `Probe` und `Set_new_travel_mode` sind jetzt Thalions echte Routinen,
  `HLC_table` ist die echte Tabelle (Namen im Text).
- Der Objektbaum ist Thalions `Main_tree`, oben mit Kennung 1 =
  Statusblock (Portraits) und 2 = Layoutbereich. Die Hauptschleife prüft
  darum jetzt auch die erste Ebene.
- `Active_handle` setzt die Brücke in `Fill_party_handles`, wie es Thalions
  `Activate_member` täte. Sonst läse `~LEAD~` einen Namen ab Adresse 0.

## 182. `Load_map` verlor bei jedem Kartenwechsel 1,1 MB; Thalions `Allocate_CHIP`-Aufrufer prüfen nie

*2026-09-26, am Savestate des Nutzers (Hatari, 4 MB ST-RAM): Inventar
benutzt, Karte verlassen, wieder hinein, nach wenigen Schritten
„Bus Error writing at address $0, PC=$1B43A“.*

**Das Abbild.** TOS legt beim Absturz ab `$380` ab (`proc_lives` =
`$12345678`, Datenregister, Adressregister, Ausnahmenummer mit PC,
Stapelabbild). Darin standen:
- Ausnahme 2 bei `$1B43A` = `copm_l`, die Schleife von `Copy_memory`
  (Ladeadresse `$13FC4` wie beim letzten Savestate)
- `a0` = `$197C01` (Block von Handle 4), `d0` = 7.056 = dessen Länge,
  `a1` = 1
- Rücksprünge auf dem Stapel: `Show_layout+30` ← `ml_karte+20`

Thalions `Show_layout` (DISPLAY.S) kopiert den gepackten Layoutblock in
einen neuen Puffer:

    jsr Allocate_CHIP / move.b d0,d3 / jsr Claim_pointer / move.l d0,a1
    ... jsr Copy_memory

Das Handle prüft es nicht. War es 0, liefert `Claim_pointer` 0.

**Warum 0?** In der Handletabelle waren nur 6 von 32 Plätzen belegt. Es
fehlte also Speicher, keine Handles: `Mxalloc` gab nichts mehr.
`Load_map` (MAP/MAP.S) holte bei **jedem** Kartenwechsel mit `Malloc`
`FILEMAX+SCRSZ+1024` Byte (1,1 MB) und gab den alten Puffer nie zurück, ein
`Mfree` gab es in der Datei nicht. Der dritte Puffer lag bei `$2D5DF0`,
`Off_screen` bei `$3D5EF0`, `phystop` ist `$400000`. Der Fehler stammt aus
`8f496d7` und ist nicht erst mit `MAIN.S` gekommen. Auf dem Gerät tritt er
je nach RAM erst nach rund zehn Wechseln auf.

**Abhilfe:**
- `Load_map` fordert den Puffer nur beim ersten Mal an und verwendet ihn
  danach wieder, die Größe ist fest. Aus dem alten Puffer liest nach dem
  Wechsel niemand: `Event_handler` ist fertig, bevor `Load_map` läuft, und
  alle `p_*` werden neu gesetzt. Nebenbei wandern `Off_screen` und
  `Work_screen` nicht mehr.
- `Allocate_CHIP` kehrt ohne Speicher nicht mehr zurück. Es springt nach
  `Speicher_voll` (MAIN.S): Raster und Maus abmelden, TOS-Bildschirm,
  Meldung, Taste, Ende. Thalions acht Aufrufer (Show_layout, Open_window,
  HDOBS, CONTROLS, INVENTOR) prüfen nie. Auf dem Amiga ging der Speicher
  dort nicht aus.

**Offen:** Thalions sechs Aufrufer von `Allocate_memory` (MAIN.S, WORDS.S,
EFFECTS.S) prüfen ebenso wenig. `Allocate_memory` bleibt vorerst still,
weil unsere Aufrufer in FILES_SUP.S die 0 auswerten und ausweichen.

## 183. Karten liegen in drei Behältern, und `Load_subfile` nimmt die Packschicht ab

Anlass: Für Thalions Ereigniskette (EVENTS.S) muss die Karte im
Originalformat im Speicher liegen, so wie es Thalions `Init_map` lädt:
`Load_subfile` mit `Map_data_file`, danach `Map_text_file` und
`Icon_data_file`.

**Drei Behälter für eine Dateinummer.** Thalions Code kennt nur
`Map_data_file` und `Map_text_file` und fragt mit der Kartennummer. Die
Karten liegen aber in `1Map_data.amb` bis `3Map_data.amb`, die Texte in
`1Map_texts.amb` bis `3Map_texts.amb`. Die nicht leeren Einträge
(deutsche Fassung 1.20, die englische zählt gleich):

| Behälter | Einträge | belegt |
|---|---|---|
| 1 | 256 | 1–256 |
| 2 | 528 | 257–299, 400–455, 513–528 |
| 3 | 369 | 300–369 |

Gezählt wird in jedem Behälter ab eins, und der JH-Schlüssel ist die
Kartennummer. Nur die Datei wechselt, die Nummer bleibt.
`Teildatei_waehlen` (FILES_SUP.S) bildet das ab: bis 256 Teil 1, 300–399
Teil 3, sonst Teil 2. Teil 2 und 3 bekommen unsere Dateinummern 48 bis 51.
In 1.20 sind `2Map_data.amb` und `3Map_data.amb` AMPC, nicht AMNP.

**Der Packkopf.** Die Karteneinträge sind LOB-gepackt. Thalions `Init_map`
liest aber gleich nach `Load_subfile` den Kartentyp, ohne `Decompress`.
`Decompress` kommt in Thalions ganzem Quelltext genau einmal vor, in
`Show_layout`. `Layouts.amb` ist AMNC, und dort liegt LOB **unter** der
Verschlüsselung: eine zweite Schicht, die der Aufrufer selbst abnimmt. Bei
AMNP/AMPC trägt jeder Eintrag vorn einen Packkopf. Nachgezählt an allen
Behältern der Fassung 1.20:

    1,"LOB",Größe,gepackte Länge,Rumpf   gepackt, Zähler durchweg 1
    0,0,0,0,Daten                        ungepackt

Bei AMNP bleibt der Kopf klar (acht Byte gepackt, vier ungepackt), der Rest
ist verschlüsselt. Unser `Load_subfile` entschlüsselte immer ab Byte acht
und ließ LOB liegen. Beides fiel nicht auf, weil über `Load_subfile` bisher
nur AMNC (Layouts) und AMBR (Truhen, `Party_char`) liefen. Der Kommentar
„die LOB-Ebene nicht“ war aus dem einen Aufrufer `Show_layout`
verallgemeinert.

**Abhilfe:** `Packkopf_aufloesen` entpackt einen gepackten Eintrag in einen
neuen Block. Bei einem ungepackten rücken die Daten um vier Byte nach vorn,
und der Block schrumpft. AMNC und AMBR bleiben, wie sie waren.

**Derselbe Fehler steckt in `tools/ambtool.py`**, `unpack_entry`: Einen
AMNP-Eintrag ohne LOB gibt es roh zurück, ohne Kopf abzunehmen und ohne zu
entschlüsseln. Darum fand der Konverter für die Karten 157 und 262 keine
Kartentexte („0 Stück“). Richtig entschlüsselt ab Byte 4 beginnt 157 mit
2 Texten, der erste „NORD: … WÜSTE HOIMON“, und 262 mit „GEHEIMZIMMER“.

**Beleg der Kette.** `Gegenprobe_karte` (MAP/MAP.S) vergleicht beim Start
und bei jedem Kartenwechsel die Originalkarte mit der konvertierten: Breite,
Höhe, Zahl der Ketten und Ereignisse und die Kettennummer jedes Feldes. In
Python vorab nachgerechnet für 157/258/262: `Map_data` bei `$14C`
(vasm-Listing ebenso), Ketten 3/23/8, Ereignisse 8/59/9, alle Felder gleich.

## 184. Thalions EVENTS.S: Ereignisbilder in Schirmtiefe, Palettentabelle aus AM2_CPU

> **Stand 2026-09-28:** Befund 1 ist überholt. „Schirmtiefe“ hieß bei
> Thalion fünf, und `Screen_depth` ist bei uns wieder 5 (191).
> `Ereignisbild_aufweiten` ist gelöscht; `Put_unmasked_block` weitet beim
> Zeichnen auf.

*2026-09-26, docs/05 C (EVENTS.S Schritt 2). Gebaut, noch nicht auf
Hardware getestet.*

Thalions EVENTS.S ist eingebunden (Einheit spiel), unsere Ereigniskette
und unser Truhen-Nachbau sind gelöscht. Drei Befunde:

**1. Thalion erklärt die Ereignisbilder zu Daten in Schirmtiefe.**
`ShowPicTxt_ModInit` zeichnet das Bild mit

    moveq.l #Screen_depth,d5 / moveq.l #20,d6 / moveq.l #ShowPicTxt_height,d7
    jsr Put_unmasked_block

Auf dem Amiga ist `Screen_depth` 5, und `Event_pix.amb` hat 5 Ebenen
(320×92, 18.400 Byte je Bild, nachgemessen). Bei uns ist `Screen_depth` 8,
und `Put_unmasked_block` liest d5 = 8 als „unsere Daten, blockverzahnt“ und
kopiert nur. Beim Zeichnen lässt sich das nicht mehr unterscheiden. Darum
weitet `Load_subfile` Einträge aus `Event_pix_file` beim Laden auf
(`Ereignisbild_aufweiten`, FILES_SUP.S): Ebenen 0–4 aus der Quelle, 5–7
null, Farbwert unverändert, also Bank 0. Das ist die Bank, die `Farbbank`
dort liefert: `ShowPicTxt_RL` legt ab `Middle_Y+1` `Batch` auf, und
`Fade_in_bottom` setzt `Batch` in Bank 0.

**Eine bewusste Ausnahme** vom Grundsatz „erst beim Zeichnen aufweiten“.
Sie gilt nur für Dateien, die Thalions Code selbst mit `Screen_depth`
zeichnet. Die 80×80-Bilder (d5 = 5) und Objektsymbole bleiben, wie sie sind.

**2. `Event_pix_palette_table` steht in AM2_CPU.** Kein freigegebener
Quelltext definiert sie. AM2_CPU (1.20) ist nicht gepackt. In Hunk 0 bei
`$143A8` steht einmalig

    41F9 0000770A  lea $770A,a0         ; Verschiebung auf Hunk 4
    1030 2000      move.b 0(a0,d2.w),d0
    721A           moveq #26,d1         ; Palette_file

davor `moveq #5,d5 / moveq #20,d6 / moveq #92,d7`. Hunk 4 ab `$770A`:
**27, 32, 33, 33, 33, 33, 33, 33**, danach eine Wortliste. Das Bild des
Anfangsevents (258, Kette 3, `Event_b1` = 1) bekommt also Palette 32.
`Palettes.amb` ist AMNC mit 64 Byte je Eintrag, Entschlüsseln genügt.

**3. Die Texte „GOLD“/„NAHRUNG“ hängen in 1.20 hinter Zeigern.** Thalions
Quelltext liest sie mit `lea.l Gold_txt,a0`. AM2_CPU hat dort
`movea.l $816C,a0`, einen Zeiger, zur Laufzeit gefüllt aus einem
verschachtelten, NUL-getrennten Block in Text.amb (die Wörter ab `$4711`).
Bis der Block geladen wird, stehen die Wörter als Platzhalter in
DISPLAY_STUBS.S.

**Brücken dazu** (MAP/MAP.S, alle mit `BRUECKE`):
- `Init_map`: Thalions `Normal_MX` wechselt die Karte sofort. Die Brücke
  hinterlegt nur `v_newmap` und die Lage, geladen wird wie bisher in der
  Hauptschleife.
- `Exit_map`: leer.
- `After_move`: ruft `Event_handler`, nur nach einem echten Schritt.
- `Jumped`: `Lage_uebernehmen`, Sprung auf derselben Karte.
- `Save_coordinates`/`Restore_coordinates`: auf `partx`/`party`.

Alle laden a5 selbst (Erkenntnis 177). Module, die es noch nicht gibt
(`Combat_Mod`, `RiddleM_Mod`, `WSelW_Mod`), sind Local_mod mit
`Pop_Module` als ModInit. Ein leerer Global_mod bliebe ohne Rasterliste auf
dem Stapel liegen.

**Nachtrag, erster Test (Hatari):** Busfehler beim Start,
`PC=$1A1B6`, gelesen bei `$42C7C6CF`, Befehl `122A` = `move.b 1(a2),d1`.
Im Programm gibt es sechs Stellen mit `122A`. Mit Ladeadresse `$13FC4`
landet der PC auf `pa_farbe+2` in `Paletten_ableiten`, und a2 kam aus
`p_pal(a5)`. Aufgerufen hatte Thalions `ShowPicTxt_ModInit` →
`Fade_in_bottom` → `Set_fade`, und dort ist a5 `Current_event_data`. Das
ist Erkenntnis 177 an neuer Stelle: Thalions Ereigniscode setzt a5 durchweg
auf den Ereignissatz. Seitdem laden `Set_fade`, `Push_MA`, `Pop_MA`,
`MA_vollbild`, `Push_Mptr`, `Pop_Mptr`, `Basic_exit`, `Map_DisInit` und
`Exit_program` a5 selbst. Das sind die Bibliothekseinsprünge mit
a5-Zugriff, die aus Thalions Modul- und Ereigniscode erreichbar sind,
gesucht mit einem Skript über alle Routinen der Bibliotheksschicht.

## 185. `Pal_size` ist die Palette der Daten (32), nicht die der Hardware; und wir hatten keinen Stapel

> Gruppe **S** (Stapel), Regel in der Kurzform.

**Befund.** Zweiter Test von Schritt 2 (Hatari, zwei Savestates): kurz
Konfetti, dann das Anfangsbild mit Fehlern und einem schwarzen Rechteck
statt des Mauszeigers. Nach dem Klick kam `Address Error reading at
address $9FFFFFFF, PC=$186E4`, Befehl `4E75`, rotes Bild.

**Ursache.** `$186E4` ist das `rts` von Thalions `Pop_Module`. Gerufen
wurde es von `ShowPicTxt_ModInit`, nachdem der Text weggeklickt war. Die
Rücksprungadresse auf dem Stapel war überschrieben. Eine Zeile davor steht
Thalions Palettenkopie:

    lea.l   Batch,a1
    moveq.l #Pal_size-1,d6
    .Loop:  move.w (a0)+,(a1)+
    dbra    d6,.Loop

`vorspann.i` setzte `Pal_size equ 1<<Screen_depth`, also 256. `moveq #255`
passt nicht in ein `moveq`. vasm übersetzt es als `moveq #-1` und warnt nur
(Warnung 2028, „-1 to fix“). `dbra` läuft dann 65 536-mal und kopiert
128 KB nach `Batch`, das nur 64 Worte hat.

**Beleg.** `Batch` liegt bei `$4352A`. a1 stand im Absturz auf **`$6352A`**,
genau `Batch + $20000`. Der Speicher `$4B1DC`–`$6352A` ist Byte für Byte eine
Kopie des Bereichs ab `$1630B2`. Schon im ersten Savestate, vor dem Klick,
ist alles ab `Current_event_data` überschrieben, ebenso der Stapel. Daher
das Konfetti und der fehlende Zeiger.

Dieselbe Warnung stand noch an zwei Stellen: `MAIN.S` Zeile 585 (`#255`)
und `DISPLAY.S` Zeile 1707 (`Adapt_palette`, `#254`).

**Regel.** Thalions `Pal_size` meint die Palette der Daten: Palettenpuffer
(`Current_pal`, `Combat_pal`), Kopien aus `Palette_file` und die
Tintenmaske. `Palettes.amb` hat 32 Farben je Eintrag. Die 256 Register des
Falcon verteilt die Bibliothek als Farbbänke, dafür braucht es `Pal_size`
nicht. Also `Pal_size equ 32`. Das ist wieder Leitgedanke 1: die
Hardwaregrenze steckt in der Bibliothek, nicht in Thalions Konstanten.

**Absicherung.** `tools/engine_uebersetzen.sh` bricht jetzt bei vasm-Warnung
2028 ab. Die Warnung erscheint nur bei Ausdrücken (`#Pal_size-1`), bei einer
wörtlichen `#255` bleibt vasm still. Für Thalions Quelltext reicht das, denn
dort stehen Konstanten.

**Nebenbefund: wir hatten keinen Stapel.** `start` setzte sp auf
Basepage + Text + Daten + BSS + 256. Die 256 sind aber die Basepage selbst,
sp stand also genau auf dem BSS-Ende. Der Stapel wuchs in die letzten
BSS-Variablen hinein (`wall_list0`, 3D, noch ungenutzt), im ersten Savestate
bis `$4B0A0`, also 600 Byte tief. Der 8-KB-Block `stacktop` in `engine.s`
stand da, war aber nie benutzt. Jetzt setzt `start` sp auf `stacktop`, und
der Block hat 16 KB.

## 186. `Free` darf `d0` nicht verbrauchen, und `Get`/`Free` nehmen auch `d0` als Argument

> Gruppe **V** (Name heißt Vertrag), Regel in der Kurzform.

**Befund.** Dritter Test von Schritt 2 (Hardware, dann zwei Savestates vor
und nach dem Klick): Laufen, Inventar und Tasten gehen. Ein Klick auf
Schrank oder Truhe bewirkt nichts, und auch ein Kartenausgang bewirkt
nichts. „Als ob da keine Truhe war.“

**Beleg.** Nach dem Klick steht `Current_event_X/Y` = (5,13). Thalions
`Find_event` wurde also mit der Schrankkachel gerufen, denn es schreibt
beide gleich am Anfang. Die Originalkarte 258 (`2Map_data.amb`) trägt auf
(5,13) und (6,13) Kette 4. `Current_event_entry_nr` stand aber auf **3**,
und `Mapdata_handle` war ebenfalls **3**.

**Ursache.** `Find_event` (EVENTS.S) liest die Kette nach d0, gibt den
Kartenblock frei und prüft erst dann:

    move.b  1(a0,d5.w),d0
    Free    d2
    tst.w   d0              ; Any ?

Unser `Free` in `vorspann.i` lud die Handle-Nummer nach d0 und ließ sie dort
stehen. Also meldete `Find_event` auf **jeder** Kachel Kette 3, das
Startereignis. Dessen Speicherbit war gesetzt, `Check_event_save_status`
brach ab, und es geschah nichts. Das gilt beim Klick wie beim Schritt, auch
für die Ausgänge. Vor dem ersten Durchlauf hätte jede Kachel das
Startereignis ausgelöst.

Es ist dieselbe Falle wie bei `Get` (164). `Free` ist damals nicht
mitgeprüft worden. Das Muster `Free … / tst.w d0 ; Anything there ?` steht
auch in DISPLAY.S und INVENTOR.S. Dort galt ein leerer Platz als belegt,
sobald der Platzblock ein Handle ungleich null hatte.

**Zweiter Fehler im selben Makro.** `Get d0,a0` (EVENTS.S, `Datachange`
für die ganze Gruppe) und `Free d0` (COMBAT/TACTIC.S): Das `moveq #0,d0`
vor `move.b \1,d0` löschte das Argument, und daraus wurde Handle 0. Jetzt
steht für `d0` als Argument nichts davor (`IFNC "\1","d0"`), denn
`Mem_eintrag` nimmt ohnehin nur das untere Byte.

**Nebenbefund: die Makros haben ein Längenmaß.** Mit `and.l #$ff,d0` im
d0-Zweig erreichte Thalions `bpl.s .Exit_all` in `Datachange` sein Ziel
nicht mehr (vasm-Fehler 2029). Seine kurzen Sprünge über `Get`/`Free`
hinweg setzen voraus, dass die Makros kurz sind. Das Retten von d0 kostet
4 Bytes je `Free`, das passt noch.

**Regel.** Ein Bibliotheksmakro lässt jedes Register stehen, das es nicht
ausdrücklich zurückgibt. Bei `Get` ist das \2, bei `Free` nichts.

## 187. `Lay3_L2` war ein leerer Platzhalter: In der Truhe griff kein Klick

**Befund.** Nach 186 öffnet sich die Truhe über Thalions `Item_found`. Im
Truhenschirm wirkt aber kein Klick, weder auf die Gegenstände noch auf die
Tasten rechts. Die Maus bewegt sich, eine Ausnahme gibt es nicht.

**Beleg (Savestate nach einem Klick auf den Buckler).**
- Die CPU steht in Thalions innerer Modulschleife (`Push_Module`, gerufen
  über `ml_karte_links` → `Action_2D` → `Handle_event_chain` →
  `Item_found`).
- Die Ereigniswarteschlange ist leer (`mev_kopf` = `mev_ende`). Der Klick
  bei (72,148) wurde also von `Read_Mev` abgeholt.
- Der Objektbaum hängt so: `Main_tree`, darunter Kennung 2 (Layoutbereich),
  darunter `Lay3_L2`, und dort steht (0,0,0,0) mit Kennung 0, ohne Bruder und
  ohne Kind. `Find_object(72,148)` liefert damit nur `$000002`. Keine Zeile
  der Truhenliste greift (`Move_LAY3_item` `$010202xx`, `Do_control_icons`
  `$010201xx`).

**Ursache.** `Lay3_L2` stand als `ds.b 64` in `DISPLAY_STUBS.S`. Thalions
Baum steht in seiner `ACTIONS.S`, die noch nicht eingebunden ist. Unser
alter Truhen-Nachbau hatte seinen eigenen Klickweg und brauchte den Baum
nicht.

**Behebung.** `Lay3_L2` und `Lay3Obj_L3` wörtlich aus Thalions ACTIONS.S
(Zeile 2149ff.) nach `src/ACTIONS.S`, neben `Lay3_object_pos_list`. Der
Bruder ist `Control_area` (Thalions MAIN.S), der letzte Platz verweist auf
`ScrollBar_L2` (Thalions CONTROLS.S). Das gilt für alle Layout-3-Schirme:
Truhe, Tür, Händler, Dialog.

**Regel.** Ein Platzhalter für einen **Datensatz**, der als Zeiger in einen
Baum oder eine Tabelle eingehängt wird, ist kein harmloser Platzhalter.
Er übersetzt und bindet, verhält sich aber wie „nichts da“. Noch offen
stehen so in `DISPLAY_STUBS.S`: `Automapper_L2`, `BattleOrder_L2`,
`Combat_L2`, `Map3D_L2`.

## 188. Tote Inventartasten aus der Truhe: In Thalions innerer Schleife gilt nur die `.Mev`-Liste

> Gruppe **A** (Es fehlt ein Aufruf), Regel in der Kurzform.

*2026-09-26, fünfter Anlauf von EVENTS Schritt 2. Auf Hardware getestet
am 2026-09-26.*

**Befund.** Öffnet man das Inventar aus der Truhe (Rechtsklick aufs
Portrait), zeigen die neun Tasten weder Druck noch Wirkung. Aus der Karte
geöffnet gehen sie.

**Beleg (Savestate `inv_noexit`, ein Klick auf Exit bei (284,152)).**
- Die Warteschlange ist abgeholt, `Find_object` liefert `$020103`:
  Layoutbereich, Tastenfeld, Taste 3. Das ist richtig.
- `Control_list_ptr` (der aus `HULL/CONTROLS.S`) zeigt auf Thalions
  `ChestInv2_CIL`, Exit ist frei, `Control_icon_flag` ist gesetzt.
- Unsere abgeschriebene `Inv2_Mev` hatte für `$010201xx` keine Zeile:
  `Do_control_icons` stand noch auskommentiert.

**Ursache.** Aus der Karte nahm unsere Hauptschleife die Tasten über den
Nachbau `mc_inv` (`2D_MAP.S`, nur Exit). Aus der Truhe läuft das Inventar
über Thalions `Push_Module` für ein `Local_mod`, also in Thalions innerer
Schleife (`Handle_input` → `Handle_list`). Dort gibt es nur die Liste, und
eine gesperrte Zeile fehlt wirklich.

**Behebung.**
- Thalions Zeile `Do_control_icons` in `Inv2_Mev`, in seiner Reihenfolge.
  Damit führen alle neun Tasten Thalions Routinen aus, auch von der Karte.
- **Brücke `Map_DisInit`:** leitet `v_screen` über `Get_module_ID` ab.
  Thalions `Exit_Inv2` lautet `Save_scroll_bar_position / Pop Module / jmp
  Init_display` und kommt an unserem `Basic_exit` vorbei, das `v_screen`
  sonst setzt. Ohne die Ableitung baute die Karte das Inventarfeld auf.
- **Brücke in der Hauptschleife:** Nimmt Thalions Liste einen Klick, wird
  danach neu gezeichnet (`st d5`). Unser `Map_DisInit` wählt nur das
  Tastenfeld; die Karte zeichnet die Hauptschleife.
- `mc_inv` bleibt vorerst, denn die Tastatur kommt noch dorthin. Thalions
  `Inv2_Mod` trägt eine `.Kev`-Liste, unser Abschrieb hat `0`.

**Thalions Exit_Inv2 ruft kein `Exit_display`.** Thalions `Basic_exit`
(MODULES.S) tut es ausdrücklich vor `Pop Module`, also steckt es nicht im
nicht veröffentlichten `Pop`-Makro. Folgen, die wir so übernehmen:
- keine Abblende beim Verlassen des Inventars über die Taste;
- `Inv2_DisExit` läuft nicht, also bleibt Thalions Bildlaufleiste auf dem
  Stapel (`Pop Scroll_bar` fehlt). `Push_Scroll_bar` weist bei vollem
  Stapel still ab; `Max_scroll_bars` = 8 ist unsere Annahme in
  `vorspann.i`. Nach vielen Inventarbesuchen könnte die Truhe deshalb eine
  fremde Leiste zeigen. Ob Thalions `Map2D_DisInit` das auffängt, sehen wir
  erst mit Thalions `MAP/2D_MAP.S`.

**Regel.** Eine Zeile, die in einer abgeschriebenen `.Mev`-Liste gesperrt
ist, fehlt in Thalions innerer Schleife wirklich. Unsere Hauptschleife
verdeckt das nur, solange das Modul global auf der Karte liegt.

## 189. `btst d0,#Stationary_mask`: kein Fehler im Original, sondern ein Byte

> Ohne Gruppe. Regel: Ein „Fehler im Original“ ist erst einer, wenn
> `AM2_CPU` ihn zeigt.

*2026-09-26, beim Einbinden von Thalions ACTIONS.S. Bau und Gegenprobe
grün, Hardwaretest steht aus.*

**Befund.** vasm lehnt ACTIONS.S:128 ab: `btst d0,#Stationary_mask`, die
Maske ist `%0000011000001110` = `$060E`, Fehler 2037 (Sofortoperand zu
groß). docs/08 hatte das seit der ersten Messung als „Fehler im Original,
Operanden verdreht“ geführt.

**Beleg.** In `AM2_CPU` (deutsch 1.20) steht an genau einer Stelle
`013C 000E`, also `btst d0,#$0E`, davor `B07C 0000 6700 …` und
`B07C 0007 6700 …`: Thalions `cmp.w #On_foot,d0` und
`cmp.w #Swimming,d0` aus den Zeilen davor. Thalions Assembler hat den
Wert auf ein Byte gekürzt.

**Warum das richtig ist.** `btst` mit einem Byte als Ziel nimmt die
Bitnummer modulo 8. Die Maske setzt die Bits 1, 2, 3, 9, 10. Für die
Fortbewegungsarten 9 und 10 prüft das gekürzte `$0E` die Bits 1 und 2, und
die sind gesetzt. Für 0 bis 15 ist das Ergebnis dasselbe wie mit der
ganzen Maske.

**Umsetzung, ohne Thalions Datei zu ändern.**
- `-no-typechk` erzeugt `013C 000E`, schaltet aber jede Bereichsprüfung
  ab, auch Warnung 2028 (Erkenntnis 185) und `addq #9`. Also nicht für den
  ganzen Bau.
- `opt t-` / `opt t+` wirkt nur auf den Abschnitt dazwischen. In `spiel.s`
  steht es um das `INCLUDE "ACTIONS.S"`.
- **Gegenprobe:** `tools/engine_uebersetzen.sh` übersetzt `spiel.s` ein
  zweites Mal mit `-DTYPPROBE` (ohne `opt t-`) und verlangt genau eine
  Meldung, `error 2037` in ACTIONS.S Zeile 128. Jede weitere bricht ab.
- Im fertigen `ENGINE.TOS` steht dieselbe Folge wie in `AM2_CPU`, nur
  `cmp.w #0` ist bei vasm `tst.w`.

**Dazu beim Einbinden von ACTIONS.S gelernt.**
- Thalions `Action_2D` hält nicht alle Register, obwohl der Kopf es
  sagt: `d2` rechnet die Reichweite, und `Handle_visible_events` lässt
  `a5` auf `Current_event_data` stehen. Unser Aufruf sichert alles.
- Die Zahl aus einem getrennten Probelauf (125 fehlende Namen) war zu
  hoch: Namen aus Thalions MAIN.S (`Mapbuf_X`, `Made_area`, `VNPC_data`)
  sieht nur, wer in derselben Einheit übersetzt. In `spiel.s` waren es 46.
- Fehlende Module als Platzhalter nach dem Muster aus `EVENTS_STUBS.S`
  (`Local_mod`, ModInit = `Pop_Module`), nicht als Nullsatz.


## 190. Stufe (c): alle Dateien Thalions auf einmal, und was die Bibliothek dafür tun muss

> Gruppe: Bibliotheksverträge. Regel: Was Thalions Quelltext nirgends
> ruft, ruft die Bibliothek: `Init_program`, `VblQ_handler`,
> `ScrQ_handler`, `Reset_*`.

*2026-09-27. Bau, Bindung und alle Prüfungen grün; Hardwaretest steht aus.*

**Warum auf einmal.** Probeläufe mit nur `MODULES.S` und `MAP/` (C1) oder
mit sechs Dateien mehr (C2) übersetzten, zogen aber 166 bzw. 120 neue
Lücken nach sich, rund 140 davon Namen aus *anderen* Thalion-Dateien:
`MODULES.S` trägt die Deskriptoren aller Module. Ein Zwischenschritt hätte
Platzhalter für Thalions eigene Namen gebraucht, die gleich wieder fallen.
Alle 38 Dateien zusammen (ohne `FAIRY.S`) brauchen dagegen nur die 293
Bibliotheksnamen der Vollprobe.

**Was die Bibliothek jetzt tut (unser `src/MAIN.S`).**
- `start`: Hardware, Bibliotheksdaten, dann `Restart_game`.
- `Restart_game`: Stapel neu, `Kill_all_memory`, `Reset_PA_stack` vor
  `Reset_module_stack` (Erkenntnis 172), `Reset_tree_stack`,
  `Reset_scroll_bar_stack`, dann Thalions `Init_program` („Do not call this
  routine directly, but call Restart_game“) und die äußere Schleife
  `Update_display / Handle_input / Switch_screens`, dieselben drei Schritte
  wie Thalions innere in `Push_Module`. `Load_game` springt ebenfalls hinein.
- `Exit_program` kehrt nie zurück (Stapel neu, Schirm zu, `Pterm0`).
  Vorher setzte unseres nur einen Merker und kehrte zurück, ein
  Vertragsbruch bei `jmp Exit_program`.
- **`VblQ_handler` und `ScrQ_handler` ruft Thalions Quelltext nirgends.**
  Die VBL-Warteschlange zählt `Timer` (`Time_2D`), und `Make_2D_move`
  lässt die Gruppe erst ziehen, wenn `Timer` läuft. Jetzt ruft
  `Bibliothek_vbl` (aus `Raster_vbl`, TOS-VBL-Warteschlange) den
  `VblQ_handler` und zählt `VBL_counter`; `Switch_screens` ruft zuerst den
  `ScrQ_handler`.

**Bibliotheksdaten beim Bau, nie zur Laufzeit aus AM2_CPU** (Nutzer).
`tools/am2cpu_auszug.py` schreibt `build/am2cpu_daten.i`: `Main_pal`
(Hunk 4 `$5B18`, gegen `STATUS_PALETTE` geprüft), `Window_icons`,
`Status_L/M/R/TB`, `Empty_portrait`, `Button_up/down`,
`Event_pix_palette_table`, Zeichensatz, 13 Mauszeiger, `Ouch` und neu
**`World_data`**: Hunk 4 `$75FE`, drei Sätze zu sieben Worten, als Muster
`(.., .., 50, 50, 1, ..)` genau einmal in AM2_CPU. Lyramion 16×16 Karten
ab 1, Waldmond 6×6 ab 300, Morag 4×4 ab 513, Dämmerung 6 und 18 Uhr.
Damit hat `Init_world` Werte, und der Wildnisweg von `Find_event` (die Tür
auf Karte 157) hat seine `Submap_width`.

**Weitere Verträge.**
- `Put_unmasked_icon` = `Put_unmasked_block` mit einem Trunc und 16 Zeilen;
  `d6/d7` bleiben, weil DISPLAY.S danach `d7` liest.
- `Allocate_FAST` = `Allocate_memory`.
- `Current_pal` gehört Thalion. Unser `Paletten_ableiten` überschrieb sie
  bei jedem `Set_fade` aus dem Kartenpuffer; jetzt setzt `Palette_anfang`
  einmal `Main_pal` in Bank 2, Bank 0 gehört `Set_fade`.
- Kachelgrafik liegt in drei Behältern: Satz 1 in `1Icon_gfx.amb`, 3–7 in
  `2Icon_gfx.amb`, 2 und 8 in `3Icon_gfx.amb` (`Teildatei_waehlen`).

**Startweg.** Thalions `Saves` ist im Original leer (letzter Spielstand 0).
Dann legt `Init_program` den Charaktereditor auf (`Chared_Mod`, ein
*lokales* Modul: `Init_program` wartet darin). Auf Wunsch des Nutzers
liefert der Bau vorerst eine Kopie mit 1; `Get_saved_game` ist ein
Platzhalter, die Arbeitsdateien kommen aus `Initial/`.

**Nebenbei gefunden.** `engine_uebersetzen.sh` gab `--extra "$VASM_EXTRA"`
weiter; argparse hielt `-DPRUEFLAUF=1` für eine Option, und **jeder
Diagnosebau scheiterte**. Jetzt `--extra=`. `Pruefe_entpacker`
(ENTPACKPRUEF) adressierte Daten PC-relativ über 32 KB; jetzt absolut.


## 191. `Screen_depth` meint Thalions Daten: fünf, nicht acht

**Befund (Hardwaretest Stufe (c), Savestate `freeze_landscape`).** Auf der
Weltkarte stürzte das Spiel nach einer Weile Laufen ab. Hatari meldete
„Bus Error reading at address $400000, PC=$171ac“. Der TOS-Nachruf bei
`$380` zeigte Bombe 2 in unserem `Put_masked_block2` (`pm2_msk`,
`or.w (a3)+,d0`) mit `d6` = 0 und `d7` = 0: Breite und Höhe null, also
65 536 Durchläufe, bis die Quelle über das RAM-Ende lief. Aufrufer laut
Stapel: Thalions `Display_2D_party`.

**Ursache.** Auf der Weltkarte zeichnet `Display_2D_party` die Gruppe aus
der Reisegrafik und springt zum Bild der Blickrichtung:

    .Loop:  move.w (a0)+,d0 / mulu.w (a0)+,d0
            mulu.w #Screen_depth*2,d0
            lea.l 4(a0,d0.l),a0

Die Daten haben fünf Ebenen, `Screen_depth` war bei uns 8. Für Blickrichtung
0 zählt das nicht, ab dem ersten Richtungswechsel landet der Zeiger in
fremden Daten. Darum kam der Absturz erst „nach einer Weile“.

**Thalion benutzt `Screen_depth` in zwei Bedeutungen**, weil auf dem Amiga
beide fünf waren:

| Bedeutung | Stellen |
|---|---|
| Aufbau der Daten | `2D_MAP.S` 310/539, `EVENTS.S` 1844, `MAIN.S` 570, `DISPLAY.S` 516, `INVENTOR.S` 339/348, `AUTOMAPP.S`, `MINIMAP.S`, `EFFECTS.S` (`Convert_trunc` liest fünf Ebenen fest), `COMOBS.S` 297, `COMBAT.S`, `TACTIC.S`, `COMBAT_M.S`, `rsgfx` in `GAME_OFF.S` |
| Schirmspeicher | `WINDOWS.S` 42/81/190, `HDOBS.S` 127/134/207 |

Halten lässt sich nur die erste. Die zweite legt Puffer an, die die
Bibliothek füllt, und was darin steht, bestimmt die Bibliothek.

**Beleg, dass fünf gemeint ist:** Die originale Bibliothek rechnet selbst
so; ihr `Put_masked_silhouette` beginnt mit `cmp.w #5,d5 / bgt raus` (129).

**Lösung (2026-09-28).**
- `vorspann.i`: `Screen_depth equ 5`, `Data_depth` ist ein zweiter Name
  dafür. Neu `Schirm_ebenen equ 8`, die Tiefe unseres Schirms;
  `FALCON_OFF.S` übernimmt sie als `PLANES`. `Bytes_per_line` hängt an
  `Schirm_ebenen`, denn Thalion legt damit Hilfsschirme an, in die unsere
  Bibliothek im Schirmformat zeichnet.
- Fensterhintergrund und HDOB-Puffer laufen über Wege, die es schon gab:
  `Get_block` sichert mit `d5` = 5 die unteren fünf Ebenen im
  Amiga-Format, `Put_unmasked_block` setzt die Bank der Zeile wieder dazu.
- **Das ist nur verlustfrei, wenn jeder Punkt „Bank der Zeile + Wert“ ist.**
  `Draw_box`, `Put_char_at` und `Put_masked_silhouette` setzten die Farbe
  roh. Sie rufen jetzt `Zeilenfarbe` (0 bleibt 0, ab 32 gilt eine Farbe als
  fertig, so wie `Get_pixel` sie liefert).
- `Ereignisbild_aufweiten` (184) ist weg: Es weitete Ereignisbilder beim
  Laden auf acht Ebenen, weil `d5` = `Screen_depth` = 8 bei uns „schon
  aufbereitet“ hieß. Jetzt kommt `d5` = 5, und `Put_unmasked_block` weitet
  beim Zeichnen auf.
- Die Kennung „`d5` = `PLANES` sind unsere Daten“ in `Put_unmasked_block`,
  `Put_masked_block2` und `Get_block` ist jetzt eindeutig: Kein Aufruf
  Thalions übergibt 8.

**Was es sonst noch traf (nach dem Code, nicht beobachtet):** Objektsymbole
in `DISPLAY.S` und das Totenkreuz im Inventar kamen mit `d5` = 8 als
ungewandelte Daten auf den Schirm, die Automap ebenso.

**Regel.** `Screen_depth` ist eine Eigenschaft von Thalions Daten, kein
Schalter fürs Zielsystem. Der Schalter ist `Schirm_ebenen`.

## 192. Die Mouse-Area wird ausgerechnet, nachdem sie aufliegt

**Befund (Hardwaretest, Savestate `nocenter`).** Stand die Gruppe am
Kartenrand, blieb der Zeiger nach Rechtsklick (Auge, Mund, Hand) in einem
Bereich um die Kartenmitte gefangen. Im Savestate: `Mapbuf_X` = 1,
Thalions `Made_area` = X 23–72 (richtig, um die Gruppe), unsere
Maussperre X 55–120, der Bereich eines früheren Aufrufs mit der Gruppe in
der Mitte.

**Ursache.** Thalions `Init_module` (`HULL/MODULE_C.S`) ruft
`Push_MA` mit der Area des Moduls und **danach** `ModInit`; erst
`Eye_ModInit`, `Mouth_ModInit` usw. (`ACTIONS.S`) schreiben `Made_area`
aus `Mapbuf_X/Y`. Unser `Push_MA` kopierte die vier Kanten beim Auflegen und
sah die neuen nie.

**Lösung.** `mastack` hält Zeiger auf Thalions Sätze, `Maus_bereich` zeigt
auf den obersten. `Mouse_int` liest die Kanten bei jedem Paket mit
`MA_X1(a1)` & Co. aus dem Satz, `Update_mouse` holt den Zeiger einmal je
Bild herein (`Maus_eingrenzen`). Thalions eigener PA-Stapel hält ebenfalls
Zeiger.

**Regel.** Übergibt Thalion der Bibliothek einen Satz, kann er ihn danach
noch ändern. Zeiger halten, zum Gebrauch nachlesen. *(Gruppe V)*

## 193. `Draw_hline` und `Draw_vline` sind nicht `Draw_box`

**Befund (Hardwaretest).** Auf der Weltkarte bei Nacht war oben und unten
Schwarz, dazwischen die volle Kartenbreite: ein Streifen statt des
Lichtkreises. Das Schwarz oben und unten ist richtig, es ist Thalions
`Display_2D_night`, das den Bereich über und unter dem Kreis mit
`Draw_box` löscht. Die Seiten links und rechts vom Kreis zieht
`Draw_two_lines` Zeile für Zeile mit `Draw_hline`, und die fehlten.

**Ursache.** Unser `Draw_hline` war nur ein zweiter Name für `Draw_box`,
abgelesen an `Draw_rectangle` (`HULL/CONTROLS.S`), das vor dem Aufruf
zufällig `d3` = `d1` setzt. `Draw_two_lines` übergibt nur `d0`, `d1`, `d2`;
in `d3` steht dort eine X-Koordinate. Derselbe Fall wie 172: ein Vertrag,
an einer Aufrufstelle abgelesen statt an allen.

**Und die Enden dürfen vertauscht sein.** `Draw_rectangle` zieht die untere
Kante von rechts nach links (`d0` > `d2`) und die linke von unten nach oben
(`d1` > `d3`). `Draw_box` brauchte geordnete Ecken; von einem Rahmen kamen
nach dem Code nur die obere und die rechte Kante.

**Lösung.** `Draw_hline`: `d0`, `d2` = X in beliebiger Folge, `d1` = Y.
`Draw_vline`: `d0` = X, `d1`, `d3` = Y in beliebiger Folge. Beide ordnen
und rufen `Draw_box`. *(Gruppe V)*


> **Nummern:** Ab hier zählen zwei Sessions getrennt, um sich nicht in die
> Quere zu kommen: 194 ff. die 3D-Session (Worktree `3d`), **250 ff. die
> 2D-Seite**. Beim Zusammenführen bleiben die Nummern, wie sie sind.

## 194. Die Bibliothek ist lesbar: `AM2_CPU` hat die Verträge

**Befund.** Bisher lasen wir Verträge an Thalions Aufrufstellen ab. Beim
3D-Teil reicht das nicht: `put_dpoly` bekommt seine Eingaben über einen
Speicherblock, `draw_zoomshape` über neun Register, und welche Pixel sie
treffen, steht nirgends im Quelltext.

**Methode.** `AM2_CPU` ist ein Amiga-Hunk-Executable, Thalions übersetztes
Spiel samt Bibliothek. `tools/am2cpu_lesen.py` zerlegt es samt
Relokationen und disassembliert mit einem m68k-`objdump` (liegt in der
VS-Code-Erweiterung `atari-st-dev`). Gefunden wird eine Routine über eine
Aufrufstelle, deren Quelltext wir haben: ein Bytemuster aus Thalions Code
suchen (`suche`), dann den `jsr abs.l` davor oder danach lesen. Die
Relokation sagt, in welchen Hunk ein Operand zeigt; so ergeben sich auch die
Variablen (Hunk 9 ist das BSS, Hunk 4 die Daten).

**Die Regel.** Gelesen wird der **Vertrag**: Register, Variablen,
Pixelformat, Rückgabe. Jede Routine prüft zuerst `Blitter_or_CPU` und
springt in eine Blitter- oder CPU-Fassung; maßgeblich ist die CPU-Fassung.
Befunde stehen in `docs/02-3D-Renderpfad.md` Teil A, Namen mit Beleg in
`NAMEN` des Werkzeugs.

**Nachtrag (Nutzer, 2026-09-28): reiner Speichercode wird übernommen.**
Die CPU-Fassung einer Routine, die keine Amiga-Hardware anfasst (die
3D-Rasterer, `Fade_colour`), schreiben wir nicht nach. `tools/am2cpu_code.py`
zieht sie beim Bau heraus. Jede Relokation bekommt einen Namen, die internen
Variablen einen BSS-Block in Originalanordnung, und 68000-Tauglichkeit,
Stückgrenzen und fehlende Hardwarezugriffe werden geprüft. Selbst
geschrieben wird, was am Schirm, am Blitter oder am Betriebssystem hängt.
Warum, und wie man zurückgeht: docs/02 A7. *(Gruppe V)*

## 195. Der 3D-Puffer hat Thalions Format, und Thalion hat die 68000-Weiche schon gebaut

**Befund.** Der Zwischenpuffer der 3D-Ansicht ist nicht chunky, wie Teil B
von docs/02 aus der Nachbauzeit annahm, sondern **je 8 Pixel 4 Byte, ein
Byte je Ebene** (MOVEP-Format), 72 Byte je Zeile. Thalions Code schreibt
selbst hinein (Himmel, Boden, Horizont, Overlays auf Wänden), und die
Wandgrafik der Spieldateien liegt schon so. Das Format ist damit Teil der
Schnittstelle; `put_dpoly`, `draw_zoomshape` und `Show_MOVEP_screen` müssen
es sprechen.

**Die Weiche.** `CPU_68020_plus` (Bibliotheks-BSS, zur Laufzeit gesetzt)
schaltet texturierte Böden und Decken ab, wenn es null ist. Das ist Thalions
eigener Weg für den 68000, also für den ST wie gemacht. `Blitter_or_CPU`
wählt in jeder 3D-Routine die CPU-Fassung; sie braucht keinen 68020-Befehl.
Wir setzen fürs Erste `Blitter_or_CPU` = `$FF`, `CPU_68020_plus` = 0.

**Und ein Name, der zu klein war.** Der Platzhalter `Sinus_table` hielt
256 Worte, gebraucht werden 1024 (`slang`, Kosinus bei +256, Maske
`slang*2-1` auf den Byteversatz). Alle Leser (`3D_MAP.S`, `MAP.S`,
`ACTIONS.S`) rechnen mit `Y_angle`, also nur im 3D-Teil; darum fiel es
bisher nicht auf. *(Gruppe V)*

## 196. Bit 15 im Stapellader heißt „eigene Kopie“

**Befund.** `Load_3D_map_data` setzt in der Wandliste Bit 15 bei jeder
Wand, auf die Overlays gemalt werden, und ruft
`Load_batch_of_unique_subfiles`. Thalions Bibliothek (0:`$25354`) löscht
das Bit, lädt den Eintrag frisch (`Load_unique_subfile`) und teilt ihn mit
niemandem; Einträge ohne Bit teilen sich ein Handle, wenn die Nummer
wiederkehrt. Beide Stapellader tun Letzteres.

**Unsere Fassung** stammt aus der Nachbauzeit: Sie teilt jede wiederholte
Nummer, auch mit Bit 15, und gibt die Nummer samt Bit an `Load_subfile`
weiter. Zwei Wände mit derselben Grafik und Overlays hätten sich ein Bild
geteilt, und beide Overlays wären auf beiden gelandet; die Nummer mit Bit
15 lädt ohnehin keinen gültigen Eintrag.

Außerdem: `MEM_MAX` = 32 Handles reicht für einen 3D-Raum nicht (Wände,
Objekte, Puffer). Das Original vergibt Byte-Handles bis 199
(`Invalidate_memory`: `cmp.w #200`). *(Gruppe V)*

## 197. Welcher Teil einer mehrteiligen Datei, bestimmt `Map_nr`

**Befund.** Für Karten, Kartentexte und Kachelgrafik hatten wir die
Aufteilung auf `1…`/`2…`/`3…` an den nicht leeren Einträgen nachgemessen
(183, Stufe (c)). Die Bibliothek (0:`$29846`) fragt aber nicht den Eintrag,
sondern **`Map_nr`**: bis 256 Teil 1, 257–299 Teil 2, 300–399 Teil 3, ab
400 Teil 2. Das gilt für neun Dateiarten (Liste 4:`$799C`), darunter alle
3D-Dateien. Bei den Karten fällt beides zusammen, weil der Eintrag die
Kartennummer ist. Bei `Wall3D` und `Object3D` nicht: `2Wall3D` und
`3Wall3D` haben teils dieselben Nummern mit anderer Grafik. Eine
Messung am Eintrag hätte dort geraten. *(Gruppe V)*

## 198. 68020-Code aus AM2_CPU: nur erlaubte Befehle, geprüft auf einer Probekopie

**Befund.** `Draw_floor`/`Draw_ceiling` (0:`$2A70A`–`$2AA0E`) sind
reiner Speichercode, enthalten aber viermal `divs.l`. Thalion ruft sie
nur, wenn `CPU_68020_plus` gesetzt ist: `Load_3D_map_data` lässt
`Floor_ceiling_potential` sonst 0, und ohne Potenzial gibt es weder
`Load_floor` noch `Draw_floor`. Der 68000 trägt die Bytes also, führt sie
aber nie aus. `Draw_ceiling` springt mit `bra.w` in `Draw_floor` hinein;
beide sind darum ein Stück mit zwei Einsprüngen.

**Prüfung.** Der Vergleich „68000 liest wie 68030“ lässt sich nicht
einfach um Ausnahmen erweitern: Nach `divs.l` gerät objdump als 68000
aus dem Takt (`$4C45` ist dort kein Befehl, das nächste Wort wird ein
Operand), und alle folgenden Befehlsgrenzen weichen ab.
`am2cpu_code.py` ersetzt darum in einer Probekopie die Befehle aus
`ERLAUBT_020` (32-Bit-Division und -Multiplikation) durch NOPs gleicher
Länge und vergleicht dann wie überall. Übernommen werden die Originalbytes.

**Speicher.** Hunk 2 ist `Longword_BSS`: Thalions `MAIN.S` endet dort mit
`wall_list0` bei `$BC0`, dahinter liegt die Bibliothek:
`Floor_source_gfx` (setzt 3D_MAP.S, definiert aber niemand), Eckvektoren,
Zeilentabelle, Texelzeile. Das ist ein zweiter BSS-Block in
Originalanordnung.

**Nebenbei.** Thalions Optionsmenü graut „Boden“ und „Decke“ außerhalb
einer 3D-Karte und im Kampf aus (`OptionsW_ModInit`). Das ist kein
Fehler der Weiche. *(Gruppe V)*

## 199. Der Kampfzoom: Thalions Vorspann und Tabellen, unser Zeichenteil

*2026-09-29, Kampfbildschirm Schritt 2. Auf dem Falcon bestätigt: die
Monster stehen im Kampfbild.*

**Befund.** `Draw_zoom_shape` (0:`$2BD2A`) und `Draw_zoom_silhouette`
(0:`$2C636`) haben keine CPU-Fassung hinter `Blitter_or_CPU`. Sie bestehen
aus drei Teilen: Einsprung mit Vorspann (Merker, Lage, Beschneiden gegen
die CA über `CA_Sp`), den Schritttabellen (0:`$2C534`: je Zielzeile und
Zielspalte der Schritt in der Quelle) und dem Blitterteil ab 0:`$2BE42`
bzw. 0:`$2C74E`. Nur der letzte hängt an der Hardware.

**Vertrag des Blitterteils**, gelesen in beiden Wegen (Verkleinern und
Vergrößern bilden dasselbe ab): Die Spalten laufen **von rechts nach
links**, Quellspalte und -zeile entstehen durch Aufsummieren der
Tabellenschritte, die Spiegelung setzt nur Startpunkt und Vorzeichen.
Maske ist das Oder der fünf Ebenen, Farbe 0 bleibt durchsichtig; die
Silhouette malt dort in `d2`. Einzelheiten im Kopf von `COMBAT_SUP.S`.

**Werkzeug.** `am2cpu_code.py` kann ein Stück jetzt an Thalions Übergang
zum Blitter verlassen: `FORTSETZUNGEN` hängt ein `jmp` in unsere Routine an
das Stückende, `AUSGAENGE` lässt einen Wortsprung aus dem Stück auf eine
eigene Marke zeigen (Befehlsbytes Thalions, Abstand als `dc.w Name-*`).
Kurze Sprünge können das nicht und brechen weiter ab. Die BSS-Variablen
setzen den Block ab `$E278` bis `$ED6C` fort. *(Gruppe V)*

## 200. Thalions Doppelpuffer: umschalten je Bild, kopieren nach Änderungen

*2026-09-29, gelesen in AM2_CPU 1.20 zum Kampf-Rest (`Duplicate_block`).
Nichts davon ist gebaut; den Umbau (B1a) übernimmt die 2D-Session.
Zuordnung von `Update_screen` und `Switch_screens` nach Aufrufzahl, nicht an
einer Aufrufstelle gegengelesen.*

**Schirme.** Zwei Schirme zu 40000 Byte, fünf Ebenen zeilenverschachtelt
(200 Byte je Zeile), angelegt in 0:`$21344` bei 1:`$0C` und 40000 dahinter.
9:`$9CF0` ist der sichtbare, 9:`$9CF4` der hintere (`Off_screen`), und
`Work_screen` (9:`$9CF8`) zeigt auf den hinteren. Beleg für `Off_screen`:
`CONTROLS.S` „`move.l Off_screen,Work_screen ; Reset`“. Das Byte 9:`$9CEA`
schlägt bei jedem Tausch um und sagt, welcher Schirm vorn ist.

| Routine | AM2_CPU | Ablauf |
|---|---|---|
| `Update_screen` | 0:`$2137A` | HDOBs in den hinteren Schirm (0:`$27F50`), tauschen, Anzeige setzen, HDOBs im neuen hinteren löschen (0:`$28050`), **`Copy_screen`**, `ScrQ_handler` (0:`$27B22`) |
| `Switch_screens` | 0:`$213C4` | dasselbe **ohne `Copy_screen`**, danach Blitter abwarten und zwei Aufrufe der graphics.library |
| `Copy_screen` | 0:`$21456` | Blitter A→D, 1000 Zeilen × 20 Worte: der ganze sichtbare Schirm in den hinteren; dann mit umgeschlagenem Merker HDOBs löschen |
| `Duplicate_block` | 0:`$215F0` | wie `Copy_screen`, aber ein Rechteck: `d0`/`d1` Ort (x auf 16 abgerundet), `d5` Ebenen 1–5, `d6` Breite/16, `d7` Höhe; beschnitten gegen `CA_Sp` |

Aufrufe: 189 auf `$2137A` gegen 158 `jsr Update_screen` in Thalions
Quelltext, 39 auf `$213C4` gegen 37 `jsr Switch_screens`.

**HDOBs** haben je Schirm einen gesicherten Hintergrund (Versatz 18 bzw. 24
im Eintrag, gewählt über 9:`$9CEA`). Der Mauszeiger ist auf dem Amiga ein
Sprite und kommt in diesem Ablauf nicht vor.

**Was jedes Bild neu gezeichnet wird.** In Schleifen mit `Switch_screens`
(2D-Karte, 3D-Ansicht, Textblättern, Kampfanimation) ist der hintere
Schirm zwei Bilder alt; dort wird der bewegte Bereich jedes Bild ganz neu
gezeichnet, und am Schleifenende gleicht `Copy_screen` die Schirme an
(`3D_MAP.S` „The end“, `WORDS.S` „Wait“). Alles Feste wird einmal
gezeichnet und mit `Update_screen` gezeigt, das den ganzen Schirm
zurückkopiert. Der Kampf kopiert sparsamer: `Draw_combat_screen`
(`COMOBS.S`) gleicht nur die geänderten CAs (`Combat_CA_list`) mit
`Duplicate_block` an, das ganze Kampffenster nur bei `Complete_update`.

**Bildschütteln.** `Vertical_screen_offset` ist 9:`$9CEC` (Wort; Thalion
setzt −3…+4 und am Ende 0, `COMBAT_M.S` Erdmasse und `REVERSE_.S`). Die
Bibliothek baut damit die Copperliste (0:`$21280`): `DIWSTRT` = `$30`+Versatz,
`DIWSTOP` = `$F8`+Versatz, und 0:`$230F0` baut sie neu, sobald sich der Wert
ändert. Das ganze Bild wandert samt Farbwechseln; der Rand zeigt die
Hintergrundfarbe.

**Folge für uns.** Im heutigen Ein-Puffer-Modell ist `Work_screen` nie
veraltet: `Copy_screen` und `Duplicate_block` als leeres `rts` sind dort
richtig, nicht bloß Platzhalter. Dafür kopiert bei uns *jeder*
`Update_screen` und *jeder* `Switch_screens` 64000 Byte; Thalion kopiert in
der Hauptschleife nichts. Mit echtem Doppelpuffer spart der Falcon dort etwa
4 ms je Bild; auf dem ST ist er Pflicht, weil 32000 Byte mit dem 68000 zu
kopieren länger dauert als ein Bild. *(Gruppe V)*

## 201. Die 3D-Ausgabe schreibt mit `movep.l` und fragt die Bank je Spanne

*2026-10-04, auf dem Falcon des Nutzers gemessen (Spielstand „Keller
Brunnen“, gleiche Stelle, `ZEIGERTAKT`, Erkenntnis 269): ZTALT = Stand
`6c70a10`, ZTTEST = `89c1a10`, sonst gleiche Quelle. Umgesetzt in
`HULL/D3_SUP.S` (`Show_MOVEP_screen`).*

**Befund.** `Show_MOVEP_screen` kostete im Hatari-Profil 9 % eines
3D-Bilds, davon 4 % für die Bank, die es je Zeile neu fragte (271). Die
Ebenen 0–3 setzte es aus 16 Einzelbytes je 16 Punkte zusammen.

**Umbau.** Thalions Puffer liegt im Format für `movep`: je 16 Punkte acht
Byte, die Ebenen 0–3 der linken acht Punkte, dann die der rechten. Zwei
`move.l` und zwei `movep.l` (nach `0(a2)` und `1(a2)`) bringen sie in die
Ebenenwörter, auf dem ST wie auf dem Falcon. Die Bank fragt es nur an der
Grenze aus `Farbbank_spanne`. Hat die Bank keine Bits 5–7, stehen in den
Ebenen 5–7 nur Nullen, ohne Maske.

**Messung** (Blöcke je Bild):

| | ZTALT | ZTTEST |
|---|---|---|
| ohne Boden/Decke | 6 | 5 |
| mit Boden/Decke | 9 | 9 |

Ohne Boden und Decke ein VBL weniger. Mit Boden und Decke reicht der
Gewinn nicht über die VBL-Grenze. `Draw_floor`/`Draw_ceiling` (Thalions
68020-Code aus AM2_CPU) kosten rund 4 VBL je Bild, fast die Hälfte; dort
liegt der nächste Hebel. Bewegte Maus: 1–2 Bilder mehr mit ZTTEST, 2–3
mit ZTALT (Angabe des Nutzers, *nicht weiter zerlegt*).

**Cache des 68030.** Seither schaltet `D3_einrichten` auf dem 68030
(Cookie `_CPU` = 30) Befehls- und Datencache mit Write-Allocate selbst
ein (`Cache030_ein`); `quit` in `MAIN.S` stellt das alte CACR wieder her.
Die Messfassung ZTCACHE zeigte gegen ZTTEST *keinen sichtbaren
Unterschied* in den Strichen. Vermutlich hatte der Desktop die Caches
schon an; *nicht geprüft*. Der Nutzer behält es (2026-10-08): Das Spiel
hängt dann nicht mehr an der Desktop-Einstellung. *(Gruppe F)*

## 202. Das Kampfbild zeichnet je 16 Punkte, und schneller wird es dadurch nicht sichtbar

*2026-10-08 gebaut, 2026-10-09 auf dem Falcon des Nutzers getestet (T7):
„sieht gut aus“. Messfassungen mit `ZEIGERTAKT` (269) an derselben
Kampfstelle: ZTCACHE = Stand `d5a7a98` (alter Zoom), ZTKAMPF = neuer
Zoom, sonst gleiche Quelle. Umgesetzt in `HULL/COMBAT_SUP.S` und
`HULL/D3_SUP.S` (`Clear_1plane_block`).*

**Befund.** Der Blitterteil von `Draw_zoom_shape`/`Draw_zoom_silhouette`
(199) schrieb jeden Zielpunkt einzeln in alle acht Ebenen und fragte die
Bank je Zeile neu. `Clear_1plane_block` fragte sie ebenso je Zeile.

**Umbau.** Die Bits von sechzehn Zielpunkten sammeln sich in Registern, je
Quellebene ein Wort, die Maske ist ihr Oder. Dann geht die Gruppe mit einem
Lesen und einem Schreiben je Ebene auf den Schirm: Ebenen 0–4 direkt aus
den Quellebenen, ohne Umweg über eine Farbnummer, Ebenen 5–7 aus der Bank.
Die Bank kommt nur an der Grenze aus `Farbbank_spanne` (271). Die
Silhouette sammelt nur die Maske, ihre Farbe ist je Zeile fest; mit
`zm_farbe` = 0 löscht sie. `Clear_1plane_block` lässt bei Bank 0 (die
3D-Ansicht immer) das einfache `clr.w` stehen.

**Messung.** ZTCACHE gegen ZTKAMPF: die Striche „nehmen sich nicht viel“
(Nutzer, *keine Zahlen*). Auf dem Falcon ist der Gewinn also unter einem
VBL je Bild; die Zeit des Kampfbilds liegt woanders, *nicht zerlegt*.
Behalten, weil richtig und nicht langsamer, und weil je Punkt weniger
Speicherzugriffe auf dem 68000 mehr zählen.

**Grenze ST.** Die Fassung gibt es nur für acht Ebenen. Für `PLANES` ≠ 8
bricht der Bau mit `FAIL` ab. Auf dem ST geht die Farbe über eine Tabelle
je Zeile auf 16 Register; dort muss je Punkt die Farbnummer gebildet,
nachgeschlagen und in vier Ebenenwörter verteilt werden. Gruppe und
Schreiben bleiben gleich. Das ist zu tun, bevor `st` diesen Stand
übernimmt. *(Gruppe F)*

## 250. `Text.amb` 1.20 trägt Thalions Bibliothekstexte, und die Marken liegen fest

*2026-09-28, Leitziel 2. Auf Hardware bestätigt: Meldungen, Charakterseite,
Optionen, Gegenstandsansicht, Automap-Legende.*

**Befund.** Thalions Code liest Namenslisten und Vorlagen über feste Marken:

    lea.l Race_names,a0 / jsr Find_small_text       ; INVENTOR.S
    lea.l Age_nr,a0 / jsr DecL_convert               ; schreibt in Age_txt
    lea.l Age_txt,a0 / jsr Put_text_line

Im Original stehen sie in AM2_CPU. Die deutsche Fassung 1.20 trägt sie in
`Text.amb`, ausgepackt 18.526 Byte. Erkenntnis 179 sah drei Blöcke; es sind
fünf Teile:

1. `$0000`: 46 Einzeltexte. Wort Langworte, Wort Anzahl, Versatzworte, Texte.
   Weltnamen, Disketten- und Fehlermeldungen, Bausteine für Meldungen
   („ erholt sich um “, „ LP.“).
2. `$05D8`: `Prompts` (179).
3. `$379E`: vierzehn Namenslisten, je `[Wort n][n Langworte]`, innen das
   Format von `Find_small_text`: Automap, Optionen, Lieder, Zauberklassen,
   Zauber (7×30), Sprachen, Klassen, Rassen, Fähigkeiten, Attribute, zwei
   Kurzformlisten, Gegenstandsarten, Zustände. Was vorher wie ein
   Gruppenkopf mit rätselhafter Anzahl aussah (`$13` vor „Musik“), ist die
   Länge in Langworten.
4. 49 Einzeltexte mit Längentabelle. Vor einer Länge steht für jede
   `*_nr`-Marke im Text ein Wort `$FFxx`, xx ist ihr Versatz: bei
   „ALTER:012“ liegt `Age_nr` bei +6, bei „012KG/012KG“ `Weight_nr1` bei 0
   und `Weight_nr2` bei 6.
5. Die zwei Versionszeilen.

**Folge.** `Age_nr` − `Age_txt` hängt von der Sprache ab, Thalion rechnet
aber mit zwei festen Marken. Die Lage muss also beim Binden feststehen:
`tools/textmarken.py` zerlegt die Datei beim Bau, prüft den Aufbau und
schreibt `build/textmarken.i`, einen BSS-Block `Textdaten` mit Thalions
Namen an ihren Versätzen. `Lade_texte` (`HULL/WORDS_SUP.S`) kopiert die
Datei zur Laufzeit hinein, wenn die Länge stimmt; sonst bleibt alles null,
also leere Texte. `Prompts` ist seitdem eine dieser Marken.

**Zuordnung** nach Inhalt und an allen Aufrufstellen gegengelesen, etwa die
festen Schreibversätze `LP_txt` +5/+9, `Goldfood_txt` +2/+10,
`ProtDam_txt` +1. Nur plausibel: „------- DATEN --------“ = `MonKnow_line`,
„Wählen Sie einen Charakter:“ = `Chared_headline`. Nicht in `Text.amb`:
`Charges_txt` „(01)“ und `Attrskill_nr` „ 01“ (AM2_CPU Hunk 4 `$70D`),
`Magic_txt`.

**Die Bausteine aus Teil 1 sind bei Thalion keine Zeichenketten,** sondern
Zeigerlisten mit Lücken, die Thalions Code füllt:

    lea.l Recup1_text,a0 / move.l #Number,8(a0) / jsr Print_member_text

Ihr Aufbau (Name, Baustein, Zahl, Baustein, 0) steht nicht in der Datei,
nur an den Aufrufstellen. Noch offen.

## 251. Spielstände: Arbeitsdateien im Hauptverzeichnis, `Save.00` ist „Neues Spiel“

*2026-09-28, Leitziel 1 und 2. Nachgelesen in AM2_CPU 1.20 mit
`tools/am2cpu_lesen.py` (3D-Session, Erkenntnis 194). Umgesetzt in
`HULL/SPIELSTAND.S`.*

**Befund.** Die vier Bibliotheksnamen, die Thalions `Save_game`,
`Load_game` und `Init_program` rufen:

| Name | 1.20 | Vertrag |
|---|---|---|
| `Get_saved_game` | `0:$29948` | `d0` = Platz. Je Datei `Save.nn/X` laden (`Load_file` mit `d0` = 0, Name in `a0`; entschlüsselt), mit `Save_file` als Arbeitsdatei schreiben |
| `Put_saved_game` | `0:$299A8` | `d0` = Platz, 0 tut nichts. Je Arbeitsdatei laden, mit `Save_encrypted_file` nach `Save.nn/X` |
| `Save_file` | `0:$25C6E` | `d0.l` Länge, `d1.w` Dateinummer oder 0 (Name in `a1`), `a0` Daten; alle Register bleiben |
| `Save_encrypted_file` | `0:$25D5C` | ebenso, mit Kopf `"JH"`, Schlüssel XOR `"JH"`; verschlüsselt an Ort und Stelle, schreibt, entschlüsselt wieder |

Die Pfade stehen in einer Tabelle (`6:$110`: Dateinummer, Pfad), die
Platznummer wird vor jedem Durchgang in „Save.nn“ geschrieben (`0:$29A0E`).
Die Verschlüsselung ist unser `JH_decrypt` (XOR, `k*17+87`), also
symmetrisch.

**Die Ordner.** Die fünf Arbeitsdateien (`Party_data.sav`,
`Party_char.amb`, `Automap.amb`, `Chest_data.amb`, `Merchant_data.amb`)
liegen im Hauptverzeichnis der Spielstanddiskette J (das Vorbyte `\n` = 10
in 1.20s Namenstabelle). **`Save.00` ist die Vorlage „Neues Spiel“**, nicht
der Arbeitsordner; auch `Baby_char` liest `Save.00/Party_char.amb`.
`Initial/` benutzt das Spiel nicht. In den 1.20-Daten sind `Initial/`,
`Save.00` … `Save.10` byte-gleich.

**Der Ladeweg** geht über Thalions Merker `First_time` (`MAIN.S`, vor
`Game_data`, übersteht also den Neustart): `Load_game` setzt
`Initial_save` und springt nach `Restart_game`; beim zweiten Durchlauf
überspringt `Init_program` das Lesen von `Saves` und ruft
`Get_saved_game(Initial_save)`.

**Nebenbefund.** `Intro_menu_choice` setzt in 1.20 der Programmstart: Das
Intro-Programm übergibt in `a0` einen Satz mit der Kennung `$00ABACAB`,
dann das Wort `Intro_menu_choice` und ein Byte (`0:$2A`). Das Startmenü
selbst (WEITERSPIELEN, NEUE QUEST STARTEN, INTRO, QUIT) steht in
`Ambermoon_intro`, nicht in AM2_CPU.

**Falle nebenbei.** `Container_laden` hält einen Platz Cache. Nach
`Kill_all_memory` (`Restart_game`) stand dessen Handle noch da, und nach
`Get_saved_game` hätte er die alte Arbeitsdatei geliefert.
`Cache_verwerfen` räumt beides.

**Abweichungen, bewusst:** kein Requester bei Schreibfehlern;
`Save_encrypted_file` verschlüsselt eine Kopie; der Merker `Neue_quest`
ersetzt vorerst das Startmenü („Neue Quest“ ohne Charaktereditor, der erste
`Get_saved_game` nimmt Platz 0).

## 252. Mausereignisse im VBL: gehalten, gedrückt, losgelassen

*2026-09-28, Leitziel 1. Befund der 3D-Session auf Hardware (Keller: jeder
Klick nur ein Schritt), nachgelesen in AM2_CPU 1.20 mit
`tools/am2cpu_lesen.py`. Umgesetzt in `HULL/LIBRARY.S` (`Maus_vbl`).*

**Das Original.** Der VBL zählt `VBL_counter` hoch und ruft gleich danach
die Mausroutine (0:$21252 → 0:$23812). Sie liest Zähler und Tasten der
Hardware und bildet `Button_state` (Byte, 9:$A00F) neu (0:$238DA–$2391E):

| Bit | Bedeutung |
|---|---|
| 0 / 4 | links / rechts gehalten |
| 1 / 5 | eben gedrückt: `(~alt & neu & $11) << 1` |
| 2 / 6 | eben losgelassen: `(~neu & alt & $11) << 2` |

Danach `Put_Mev` (0:$2396E) mit Lage und `Button_state`; es legt nur ab,
wenn das Wort nicht 0 ist, und verwirft bei voller Schlange (50 Plätze zu
6 Byte, 9:$A080–$A1AC). **Solange eine Taste gehalten wird, kommt in jedem
Bild ein Ereignis** (`$01` gehalten, `$03` im Bild des Drückens, `$04`
beim Loslassen).

**Wer das braucht.** `Mousemove_3D_Mod` und `Continuous_Mod` leben von
den Ereignissen „gehalten“: ohne sie nimmt sich das Modul beim nächsten
Durchlauf herunter, und jeder Klick ist nur ein Schritt. Ablegen und
Menüwahl (`Backpack_item_moved`, `Option_selected` …) prüfen `$02`, also
das **Drücken**, nicht das Loslassen.

**Bei uns bisher.** `Mouse_int` legte nur bei einem IKBD-Paket ab, nur
Flanken, und `$02` hieß „losgelassen“ (Annahme aus der Zeit von
Erkenntnis 175). `Right_clicked` stand in `vorspann.i` auf Bit 4; 1.20 hat
genau eine Stelle `btst #5,Button_state` (0:$26B2A, `Display_text`), also
Bit 5.

**Jetzt.** `Mouse_int` führt nur Lage und rohe Tasten (`Maustasten`).
`Maus_vbl` bildet `Button_state` wie oben und legt ab. Die Schlange hat
64 Plätze.


## 253. Meldungen in 1.20: Textlisten mit Plätzen, gefüllt aus `Text.amb`

*2026-09-28, Leitziel 1 und 2. Nachgelesen in AM2_CPU 1.20 mit
`tools/am2cpu_lesen.py`, umgesetzt in `tools/am2cpu_auszug.py`
(`MELDUNG_*`) und `tools/textmarken.py`.*

**Das Original.** `Text.amb` Teil 1 trägt 46 Einzeltexte: Weltnamen,
Disketten- und Fehlermeldungen und die Bausteine der Meldungen („ erholt
sich um “, „ LP.“ …). In Hunk 6 ab $00 steht eine Tabelle mit 46
Langworten: Text *n* → Platz. Die Plätze 3–45 liegen in Hunk 4
($7D0E–$80C0), fast alle in **Textlisten**, also Folgen von Zeigern mit einer
Null am Ende. In der Datei ist der ganze Bereich null; die Bibliothek trägt
beim Start die Textzeiger ein, und Thalions Code füllt die Lücken:
`Print_member_text` setzt den Namen an 0, `move.l #Number,8(a0)` die Zahl.
Wo eine Liste endet, ergibt sich aus dem Anfang der nächsten; jeder Anfang
ist über ein `lea` in Hunk 0 belegt, und jede Liste endet mit einer Null,
die kein Textplatz ist.

**Freigegebener Quelltext gegen 1.20.** Sechs Namen spricht Thalions
freigegebener Quelltext als Text an (`move.l #Divide_start_text,(a2)+`),
1.20 dagegen als Platz (`move.l $7F88,(a2)+`): `Divide_start/inter/end_text`
(Text 12–14), `That_text` (45), `Text_error_text` (9),
`Out_of_memory_text` (11). Bei uns sind das Marken im geladenen Text, nicht
Plätze. Die übrigen 19 Namen sind in beiden Fassungen Listen.

**`Magic_txt`** setzt die Startroutine in Hunk 8 ($168): Sie überspringt in
`Spell_class_names` sieben Texte. In 1.20 (deutsch) hat die Liste genau
sieben (Heilung … zwei leere … Funktion), dahinter steht das Füllbyte.
**`Magic_txt` ist also leer**, im Original wie bei uns.

**Bei uns.** `am2cpu_auszug.py` schreibt die Listen als
`dc.l Textamb_n,0,…` in den Datenabschnitt und prüft Tabelle, Anfänge,
Enden und die Startroutine gegen. `textmarken.py` setzt `Textamb_0`–`45` auf
die Texte in `Textdaten` und die sechs Einzelnamen dazu. Die Texte liest
`Lade_texte` zur Laufzeit. `Attrskill_nr` („ 01“, Hunk 4 $70E) und
`Charges_txt` („(01)“, $712) sind kleine Schreibpuffer und kommen als
Stücke. 29 Platzhalter weniger.

## 254. Die Blockroutinen beschneiden gegen die oberste CA

*2026-09-28, Leitziel 1. Befund der 3D-Session auf Hardware (Busfehler beim
Kampfbeginn, `or.w (a3)+,d0` in `Put_masked_block2`, Quelle bis $400000),
nachgelesen in AM2_CPU 1.20. Umgesetzt in `HULL/LIBRARY.S`
(`Block_beschneiden`).*

**Das Original.** `Put_unmasked_block` (0:$22CBE), `Put_masked_block`
(Blitter 0:$22646, CPU 0:$228B0) und `Put_masked_silhouette` (0:$22AD2)
beginnen gleich:

1. `d5` < 0 oder > 5: nichts.
2. Gegen den obersten CA-Satz (`CA_Sp`): ganz rechts, unten, links oder oben
   daneben → nichts.
3. Oben abschneiden (`d7` kürzen, Quelle um die Zeilen weiter), unten `d7`
   kürzen.
4. Seitlich ganze Blöcke weglassen.

`Put_unmasked_icon` (0:$22518) prüft keine CA.

**Bei uns bisher.** Keine der drei Routinen beschnitt. Bei `d7` = 0 oder
`d6` = 0 lief eine `dbf`-Schleife 65536 Mal. Thalions Kampf legt
`Combat_CA` auf und verlässt sich darauf (`Draw_all_COMOBs`).

**Jetzt.** `Block_beschneiden` prüft wie das Original. Seitlich schreiben
die Routinen keine Zielblöcke außerhalb von X1/16 bis X2/16. Abweichungen:
- `d5` = 8 (unsere Daten) gilt.
- `d5` = 0, `d6` ≤ 0 und `d7` ≤ 0 zeichnen nichts.
- Die CA wird auf den Schirm begrenzt.

`Restart_game` setzt den CA-Stapel zurück. Zwei Nebenfunde:
- `Put_masked_silhouette` las nur eine Quellebene, Thalions Kampf gibt aber
  `Screen_depth`. Die Form ist jetzt das ODER der `d5` Ebenen.
- `pms_block` überschrieb `d0` und damit den rechten Teil jeder Silhouette
  abseits der Blockgrenze.

Nachtrag 2026-09-29, erster Hardwaretest: Busfehler gleich nach dem
Startmenü in `Put_unmasked_block` (Lesen bei $3010FBC0). `pub_seitlich`
setzte nur das untere Wort von `d3` und addierte es lang auf `a0`. Bei
unseren Daten überschrieb `mulu` das ganze Register, bei Amiga-Daten blieb
das obere Wort des Aufrufers stehen. Im Prüflauf war es zufällig 0. Danach
ist 2D ohne Befund (Inventar, Truhe, Steuersymbole, Minikarte, Automap).

## 255. Thalions Assembler richtete Daten und Versätze gerade aus

*2026-09-29, Leitziel 1. Befund des Nutzers in Hatari (Keller, Rätselmund,
„Sprechen“): Busfehler bei $042A3900 in `Search_layer` (HULL/OBJECT.S).
Umgesetzt als Bauschalter `-align` an allen vasm-Aufrufen.*

**Der Absturz.** Thalions `WORD_SEL.S` beschreibt die Mausfelder des
Wortwahlfensters als Liste (`WSelW_L1`). Nach der Kennung `dc.b 2` folgt dort
ohne `even` ein `dc.l .C3,0`. vasm legte den Zeiger unverändert auf die
ungerade Adresse $42A31. `Search_layer` liest den Bruder aber an Versatz 10,
also bei $42A32, ein Byte daneben: aus $00042A39 wurde $042A3900. Der Fehler
kommt nur, wenn die Maus nicht auf der Wortliste steht. Beim Dialog klickte
der Nutzer auf die Wörter, beim Rätselmund stand die Maus noch auf der Taste.

**Das Original.** In AM2_CPU (Hunk 4 $258) steht an derselben Stelle nach
der Kennung ein Füllbyte, und der Zeiger liegt gerade. Thalions Assembler
richtete `dc.w`/`dc.l` also von selbst aus, wie Devpac. vasm tut es nur mit
`-align`, das auch `rs.w`/`rs.l` ausrichtet.

**Was sich mit `-align` ändert** (Probeübersetzung, Symbolvergleich):
- Vier Datenstellen in Thalions Dateien, die vasm als Warnung 58 meldet:
  `WORD_SEL.S` 367 und 370, `MAGIC.S` 1958, `COMBAT_M.S` 3266.
- Eine Struktur: die Kampfteilnehmer in `GAME_OFF.S`. Nach 13 `rs.b` folgt
  `Part_X: rs.w 1`. Ohne `-align` lag es auf $0D, mit auf $0E;
  `Participant_data_size` wird $28 statt $27, `Combat_data_size` $622
  statt $60A. Ein Wort auf ungerader Adresse wäre auf dem 68000 des A500 ein
  Adressfehler gewesen. Also ist $0E Thalions Wert, und ohne `-align` wäre
  der Kampf auf dem ST abgestürzt.
- Unsere Bibliothek (`engine.s`): keine Änderung.

**Regel.** Die vier Warnungen 58 sind erwartet. Die Typprobe zählt sie nicht
mit. Eine neue Warnung 58 in unserem Code bedeutet ein fehlendes `even`.

## 256. Die 2D-Grafik der Bibliothek liegt lückenlos in AM2_CPU Hunk 3

*2026-09-29, Leitziele 1 und 2. Umgesetzt in `tools/am2cpu_auszug.py`
(beim Bau, zur Laufzeit wird AM2_CPU nicht gelesen).*

**Wie gefunden.** Thalions übersetzter Code steht zweimal zur Verfügung: in
unserem Bau und in AM2_CPU Hunk 0. Zu jedem `lea Name,aX` in unserem Bau
wurden die Befehle davor und danach in Hunk 0 gesucht; wo sie passen, sagt
die Verschiebung des `lea`, wohin es in AM2_CPU zeigt. Alle Stellen eines
Namens zeigen auf dieselbe Adresse (zum Beispiel drei bei `Broken`, zwei bei
`Compass`).

**Wie belegt.** Die Länge jedes Stücks ergibt sich aus Thalions Aufruf
(Breite × Höhe × Ebenen), nicht aus AM2_CPU. Zusammen mit den früheren
Stücken füllen sie Hunk 3 von $A0 bis $35DE **ohne Lücke und ohne
Überlappung**. Die einzige Lücke, $35A4–$35BE (26 Byte), ist `Red_cross`
(16×13, eine Ebene; holt die 3D-Session). `am2cpu_auszug.py` prüft jetzt
jede Überlappung.

| Hunk 3 | Name | Maß |
|---|---|---|
| $00A0 | `Cross_hatch` | 16×16, 1 Ebene |
| $03C0 | `Status_icons` | 23 × 16×16, 5 Ebenen |
| $1220 | `Giant_eagle_shape` | 32×29, 5 Ebenen |
| $1464 | `Damage_star` | 32×26, 5 Ebenen |
| $1780 | `Magic_stars` | 4 × 16×9, 5 Ebenen |
| $18E8 | `Magic8_stars` | 4 × 16×10, 3 Ebenen |
| $1EAC | `Windchain` | 32×15, 3 Ebenen |
| $1F60, $20E0 | `Eye_off`, `Eye_on` | 32×32, 3 Ebenen |
| $2260 | `Daynight_icons` | 4 × 32×32, 3 Ebenen |
| $29F8 | `Chequered` | 32×11, 1 Ebene |
| $2A24 | `Compass` | 32×32, 3 Ebenen |
| $2BA4 | `Swordshield` | 2 × 16×9, 3 Ebenen |
| $2C10 | `Death_mask` | 32×34, 3 Ebenen |
| $3360 | `Ankh_symbol` | 32×29, 5 Ebenen |
| $35BE | `Broken` | 16×16, 1 Ebene |

Dazwischen liegen die früheren Stücke: `Window_icons`, `Ouch`, Statusleiste,
`Spell_icons`, Tastenrahmen, `Empty_portrait`, `Dissolve`.

`Automap_pal` (32 Farbworte) steht in Hunk 4 bei $5B58, direkt hinter
`Main_pal`. Belegt über die Rasterliste des Automap-Moduls (Hunk 4 $346C).
Dieser Satz trägt dieselben Tasten und dasselbe Feld 216,303,45,188 wie
Thalions `MODULES.S`.

Alle Stücke sind im Amiga-Format; die Blockroutinen weiten sie beim
Zeichnen auf. An der Bibliothek ändert sich nichts.

## 257. `Amiga_key` ist Bit 28 der Tastenkennung, nicht Bit 3

**Befund (Test des Nutzers, 2026-09-29):** Im Speicherdialog und in der
Wortwahl kamen einige Buchstaben nicht an, etwa i, z, y, und Return beendete
die Eingabe nicht; nur die linke Maustaste tat es.

**Ursache:** Thalions `Handle_input` (`HULL/MODULE_C.S`) prüft jede Taste
aus `Read_key` mit `btst #Amiga_key,d0` und gibt sie bei gesetztem Bit an
die Diagnoseliste statt an die `.Kev`-Liste des Moduls. Der Wert steht in
Thalions nicht freigegebener Include-Datei; unser `vorspann.i` hatte ihn mit
3 geraten. Bit 3 ist bei uns ein Bit des ASCII-Zeichens (Byte 0 von
`Bconin`). Jede Taste mit gesetztem Bit 3 ging darum an die leere
Diagnoseliste und verschwand: h–o, x–z, die Großbuchstaben dazu, 8, 9,
Return ($0D), Tab ($09).

**Beleg:** AM2_CPU 1.20, Hunk 0 $279E8:

    jsr     Read_key            ; 4EB9 0002631C
    tst.l   d0                  ; 4A80
    beq.s   .Exit
    btst    #28,d0              ; 0800 001C
    beq.s   .None
    lea     Diagnostics_list1,a1

Dieselbe Folge wie in `MODULE_C.S`; in Hunk 0 ist es die einzige mit `btst`
vor einem `lea …,a1` auf die Diagnoseliste. Bit 28 liegt im obersten Byte,
dem der Umschalttasten (Thalions `Input_Mod`: `$ffff0000,$01410000` =
Umschalt + Rücktaste). `Bconin` liefert dort ohne `conterm`-Bit 3 null,
also geht keine Taste mehr an die Diagnose.

**Regel:** Eine Bitnummer aus `vorspann.i` ist so geraten wie jede andere
Konstante dort; eine Fehlzuordnung trifft nur einen Teil der Werte und sieht
darum wie ein Tastaturproblem aus. Belegen an der Aufrufstelle in AM2_CPU.

**Offen, eigener Punkt (docs/05):** Thalions Tastenlisten vergleichen im
Byte 2 mit Amiga-Tastencodes (Rücktaste $41, Cursor $4C–$4F, F-Tasten
$50–$59, Ziffern 1–6 = $01–$06). `Read_key` gibt Atari-Tastencodes weiter;
dort passen die Sondertasten nicht.

## 258. Der Doppelpuffer: gegengelesen in AM2_CPU und bei uns gebaut

*2026-09-29, Umbau B1a.  Ergänzt Erkenntnis 200 der 3D-Session; die dort nur
über die Aufrufzahl zugeordneten Routinen sind hier Befehl für Befehl
gelesen (`tools/am2cpu_lesen.py dis 0:21344 --bis 0:21708`).*

**Bestätigt:** `Update_screen` (0:`$2137A`) und `Switch_screens`
(0:`$213C4`) laufen gleich: `Draw_HDOBs`, `Off_screen` und den sichtbaren
Schirm (9:`$9CF0`) tauschen, Anzeige setzen, `Work_screen` = `Off_screen`,
`not.b Screen_flag` (9:`$9CEA`), `Erase_HDOBs`, dann nur bei
`Update_screen` `Copy_screen`, zuletzt `ScrQ_handler`.  Die
graphics.library-Aufrufe in `Switch_screens` betreffen nur den Blitter.

**Neu gegenüber 200:**
- **Nach dem Tausch wird gewartet.**  0:`$21436` legt den neuen Schirm für
  die Copperliste ab (9:`$9CFC`) und ruft 0:`$21528`, das schleift, bis sich
  das Wort 9:`$9CC6` ändert, also bis zum nächsten Bild.  Erst danach darf in
  den bisher sichtbaren Schirm gezeichnet werden.
- `Copy_screen` kopiert samt HDOBs und nimmt sie im hinteren Schirm mit dem
  Hintergrund des *vorderen* wieder heraus (`not.b Screen_flag` /
  `Erase_HDOBs` / `not.b Screen_flag`).
- `Duplicate_block` kopiert zeilenweise Ebene für Ebene vom sichtbaren in
  den hinteren Schirm; beschnitten wird gegen `CA_Sp` mit X1/X2/Y1/Y2 auf
  0/2/4/6.  Einziger Aufrufer übergibt `d5` = `Screen_depth`.
- `Init_screens` (0:`$21344`) löscht `Vertical_screen_offset`.

**Bei uns (Falcon):**
- Zwei Schirme in einem ST-RAM-Block (Mxalloc Modus 0), je 4 schwarze
  Randzeilen oben und unten, auf 256 Byte ausgerichtet (`Bildpuffer_anlegen`).
- `Basis_setzen` schreibt die Videobasis = `Schirm_vorn` −
  `Vertical_screen_offset` × 320 direkt in `$FF8201/03/0D`, beim Tausch und
  in jedem VBL; `Anzeige_setzen` wartet danach auf `VBL_counter`.  In
  dieser Reihenfolge, weil das Schreiben von H oder M das untere Byte löscht.
- **Falle `screenpt`:** `Setscreen` legt die Adresse in der Systemvariablen
  `$45E` ab, und der VBL von TOS setzt die Basis daraus.  Bliebe sie stehen,
  holte TOS nach jedem Tausch den ersten Schirm zurück.  `Open_screen` wartet
  darum ein Bild und löscht sie; `Close_screen` schaltet unseren VBL vorher ab
  (`Schirme_an`).
- **Der Mauszeiger** ist auf dem Amiga ein Sprite und fehlt in Thalions
  Ablauf.  Bei uns läuft er wie ein HDOB: vor dem Tausch in den hinteren
  Schirm, danach im neuen hinteren heraus, ein Hintergrund je Schirm
  (`zeiger_saetze`, Wahl über `Screen_flag` wie `HDOB_screen1/2`).
  `Copy_screen` und `Duplicate_block` nehmen den mitkopierten Abdruck im
  hinteren Schirm heraus, `Duplicate_block` nur innerhalb seines Rechtecks.
- `Update_mouse` ruft Thalions Code nie.  Unsere Warteschleifen (Startmenü,
  `Wait_key`) brauchen es; es zeichnet im sichtbaren Schirm, weil der hintere
  halbfertig sein kann, und ohne Lücke: getrennte Zeilen erst neu, dann alt
  heraus; gemeinsame Zeilen im Zwischenstück zusammengesetzt und in einem
  Zug zurück.
- `Update_screen` ruft jetzt wie das Original `ScrQ_handler`, und
  `Switch_screens` ruft ihn *nach* dem Tausch statt davor.

**Nachtrag, Test 2026-09-29: Herausnehmen umgekehrt zum Zeichnen.**  Im
ersten Bau kamen nach dem Tausch erst die HDOBs heraus, dann der Zeiger.
Dessen Hintergrund enthält den HDOB darunter, und beim Ziehen eines
Gegenstands steht der Zeiger immer darauf: je Bild blieb ein Stück stehen,
eine Spur über den Schirm.  Richtig ist Zeiger, dann HDOBs, in
`Schirmwechsel` wie in `Copy_screen`.  Vor B1a stimmte die Reihenfolge schon
einmal; beim Umbau ging sie verloren.

**Grenze:** Der einfache ST setzt die Basis nur in 256-Byte-Schritten und
hat kein `$FF820D`; Bildschütteln und die zeilengenaue Basis bleiben dort
offen (ST-Port). *(Gruppe V)*

## 259. Auch Kästen und Text beschneiden gegen die oberste CA

*2026-09-30, Leitziel 1. Befund der 3D-Session auf dem Falcon (Savestate:
Automap in Großvaters Keller), nachgelesen in AM2_CPU. Umgesetzt in
`HULL/LIBRARY.S` (`Draw_box`, `Put_char_at`).*

**Befund.** Öffnet man die Automap in einer gerollten Karte, stehen oben in
der Portraitleiste eine Fläche in der Papierfarbe und zweimal versetzt der
Kartenname. Thalions `Display_automap` (AUTOMAPP.S) legt `Automap_CA` auf
und zeichnet danach den Boden mit `Draw_box` und den Namen mit
`Print_centered_string`, beides relativ zur Rollage. Die Oberkante liegt
dann über der CA; im Original schneidet die CA sie ab. Die Randstücke gehen
über `Put_unmasked_block` und fehlten schon richtig (254).

**Das Original.**
- `Draw_box` (0:$21E64): Ecken ordnen, ganz außerhalb der CA → nichts, sonst
  auf X1..X2/Y1..Y2 klemmen. `Draw_vline` (0:$220F0) und ein Punktsetzer
  (0:$2170A) prüfen ebenso.
- `Put_text_line` (0:$239A8), gefunden über `Print_centered_string`
  (0:$26E90): die ganze Zeile kommt erst in einen Hilfspuffer mit einer
  Ebene, dann wird dieser Block gegen die CA geschnitten. Senkrecht
  zeilengenau, seitlich nur ganze Sechzehnerblöcke, die völlig außerhalb
  X1..X2 liegen. Ragt die Zeile unten über Y2, fällt auch die Schattenzeile
  weg (Merker 9:$A1AC). Diese Fassung ist nur für den Blitter geschrieben;
  eine CPU-Weiche gibt es hier nicht.

**Bei uns bisher.** `Draw_box` und `Put_char_at` schrieben ohne jeden
Schnitt; `Draw_hline`, `Draw_vline` und `Plot_pixel` laufen über `Draw_box`.

**Jetzt.**
- `Draw_box` ordnet, klemmt auf die CA und auf den Schirm und zeichnet
  nichts, wenn danach links hinter rechts oder oben unter unten liegt. Das
  ist dieselbe Entscheidung wie Thalions Verwerfen vor dem Klemmen.
- `Put_char_at` schneidet je Zeichen wie Thalion je Zeile: Musterzeilen
  außerhalb Y1..Y2 fallen weg, jeder der beiden Sechzehnerblöcke wird nur
  geschrieben, wenn er X1..X2 berührt. Weil Thalion nur ganze Blöcke
  verwirft, kommt das aufs Gleiche heraus. Der Schatten ist bei uns ein
  eigener Aufruf eine Zeile tiefer und wird damit ebenso beschnitten.
- Nicht übernommen: Thalion bricht eine Zeile ab X = 314 ab.

Merksatz zu 254: **Jede Zeichenroutine der Bibliothek, die Thalions Code
ruft, beschneidet gegen die oberste CA**, außer `Put_unmasked_icon`. Wer
eine neue schreibt, liest zuerst ihren Anfang in AM2_CPU. *(Gruppe V)*

## 260. Thalions Tastenkennung: Amiga-Rawkey, Qualifier, Zeichen vom System

*2026-09-30, Leitziel 1. Gelesen in AM2_CPU 1.20, umgesetzt in
`HULL/VARIOUS_SUP.S` (`Read_key`, `Amiga_tasten`). Folgt auf 257.*

**Das Original.** Thalions Tastenhandler (0:$26270) hängt am
`input.device` und nimmt nur Tastendrücke (Klasse 1, Bit 7 des Codes frei);
Klasse 16 (Diskette eingelegt) wird zu Bit 29. Je Druck schreibt er ein
Langwort in eine Warteschlange (0:$2634A), `Read_key` (0:$2631C) nimmt es
heraus:

| Teil | Inhalt |
|---|---|
| Bit 0–7 | Zeichen aus `MapRawKey` mit `a2` = 0, also der Tastenbelegung des Systems |
| Bit 16–23 | Amiga-Rawkey (`ie_Code`) |
| Bit 24–28 | Qualifier über die Tabelle 4:$4924: Umschalt 24, Control 25, Alt 26, Caps Lock 27, Amiga 28 |

Die Datei `Keymap` nennt nur `Ambermoon_install`, `AM2_CPU` nicht. Das Spiel
liest sie also nicht selbst; vermutlich richtet die Installation sie als
Systembelegung ein (nicht belegt). Sie ist eine Amiga-Hunkdatei mit einem
`KeyMapNode` namens „d“, der deutschen Belegung.

**Was Thalions Listen erwarten** (alle `.Kev` im Quelltext ausgezählt):
Ziffern 1–6 `$01`–`$06`, Ziffernblock `$1D`–`$1F`/`$2D`–`$2F`/`$3D`–`$3F`,
Rücktaste `$41` (mit Umschalt: Feld leeren), Enter `$43`, Cursor
`$4C`–`$4F`, F1–F6 `$50`–`$55`, dazu Zeichen in Bit 0–7 (Leertaste, j/n/o/y).

**Umlaute:** Thalions `Input_mask_table` (HULL/WORDS.S) kennt die Zeichen
des Atari-Zeichensatzes schon, gekennzeichnet „ATARI“, neben den
Amiga-Latin-1-Zeichen. Thalion kam vom Atari.

**Bei uns.** `Read_key` baut dieselbe Kennung: Atari-Scancode über
`Amiga_tasten` in Bit 16–23 (nach der Lage der Taste, `#` und `~` nach der
Beschriftung), Umschalttasten aus `Kbshift` in Bit 24–27. Bit 28 bleibt 0.

**Das Zeichen aus `Keymap`, nicht vom TOS.** Der erste Bau nahm es von
`Bconin`. Test des Nutzers (EmuTOS, deutsche Sprache): die ö-Taste gab `;`
und `:`, die Belegung des TOS war eine andere als die Tastatur. Jetzt lädt
`Lade_keymap` Thalions `Keymap` (Datei 58, `KEYMAP`), und
`Keymap_zeichen` rechnet wie `MapRawKey`:
- Typ `KCF_NOP`/`KCF_STRING`: kein Zeichen (Thalion nimmt nur Ergebnisse mit
  genau einem Zeichen).
- Sonst vier Zeichen je Taste; der Index zählt die Umschalttasten, die der
  Typ nennt (Umschalt, Alt, Control), Byte = 3 − Index. Bei `KC_VANILLA`
  löscht Control Bit 5 und 6. Caps Lock wirkt auf Tasten mit Caps-Bit wie
  Umschalt.
- `KCF_DEAD`: je Stellung zwei Byte. Die Selbstlaute sind so angelegt
  (`DPF_MOD`, zuerst das Zeichen ohne Tottaste); Tottasten (´ ^ `) geben
  kein Zeichen, zusammengesetzt wird nicht.
Nachgeprüft vor dem Bau mit einer Nachbildung in Python: ö/Ö, ä, ü, ß,
z/y vertauscht, `"` auf Umschalt+2, `@` auf Alt+2, Caps Lock. Fehlt die
Datei, bleibt das Zeichen vom TOS.
Umschalt+F-Taste, Control+Cursor und Alternate+Ziffer haben beim Atari
eigene Scancodes und werden auf die Grundtaste gelegt. Tasten ohne
Gegenstück (Clr/Home, Insert, Undo) werden übergangen, nicht als 0
gemeldet, denn Thalions `Reset_keyboard` liest, bis 0 kommt. Unser
Startmenü prüft jetzt Amiga-Codes (Return `$44`, Enter `$43`, Cursor
`$4C`/`$4D`).

**Regel:** Unsere Eingabe liefert, was Thalions Bibliothek lieferte. Eine
Übersetzung gehört in die Hardwareschicht, nie in Thalions Listen.
*(Gruppe V)*


## 261. Der Charaktereditor als Startweg, SAVES wie im Original

*2026-09-30, Leitziel 1 und 2. Gelesen in Thalions MAIN.S (`Init_program`),
CHARACTE.S und AM2_CPU 1.20; umgesetzt in `tools/am2cpu_auszug.py`,
`HULL/FILES_SUP.S`, `src/MAIN.S`, `HULL/STARTMENUE.S`.*

**Das Original.** Thalions `Init_program` fragt `Intro_menu_choice` (von
`Ambermoon_intro` übergeben). Ist es nicht 0, legt es `Chared_Mod` auf.
Bei 0 lädt es `Saves`, legt Wort 0 in `Initial_save`, und ist das 0,
wieder den Editor. Danach `Get_saved_game(Initial_save)`. `Chared_Mod` ist
ein lokales Modul: `Push_Module` kehrt erst zurück, wenn der Editor sich
herunternimmt, also schreibt `Chared_ModExit` den Helden
(`Save_subfile 1, Baby_char_file`), **bevor** `Get_saved_game(0)` den
Stand „Neues Spiel“ zu Arbeitsdateien macht. Thalions `Saves` trägt 0.

**Was dafür fehlte.**
- `Chared_portraits`, acht Portraitnummern (vier männlich, vier weiblich):
  2, 25, 7, 23, 31, 38, 44, 51. In AM2_CPU 4:$76BA, gefunden über
  `Chared_ModInit` (0:$C4AA: `lea $76BA,a1`). **`Race_heights` davor hat
  dort nur neun Worte**; Thalion liest mit `Max_races` = 15 für Rasse 9–14
  in die Portraitnummern hinein. `am2cpu_auszug.py` erlaubt die Überlappung,
  wie bei 184.
- `Baby_char_file` = 41: AM2_CPU nennt `Save.00/Party_char.amb`
  (Namenstabelle 4:$79B0, Eintrag 41 → 4:$7CD0). Bei uns
  `SAVE.00\PARTYCHR.AMB`, eine eigene Zeichenkette, denn `sp_pchar` bekommt
  die Ziffern des Platzes eingesetzt. AMBR, unverschlüsselt; `Save_subfile`
  schreibt die ganze Datei neu, wie im Original also in den Stand
  „Neues Spiel“.

**Die Übergabe** (abgestimmt mit der Intro-Session): der Lader `AMBER.TOS`
startet `ENGINE.TOS` mit Längenbyte 1 und `'0'` (Weiterspielen) oder `'1'`
(Neue Quest) in der Basepage ab `$80`. `start` legt das in
`Intro_menu_choice` und lässt unser Startmenü weg. Jede andere Zeile, auch
eine leere: unser Startmenü, das `Intro_menu_choice` genauso setzt.
Weiterspielen ist in beiden wählbar, wenn Wort 0 von `SAVES` nicht 0 ist:
Thalions Regel, ohne die Namensprüfung der Zwischenzeit.

**Weggefallen:** die erzeugte `SAVES` mit „letzter = 1“ und der Merker
`Neue_quest` in `Get_saved_game`. Nur die Prüffassung bekommt eine solche
`SAVES` noch, damit das Tastenskript ohne Editor auf die Karte kommt
(`pruefskript.sh`; ohne Ordner `SAVE.01` bleiben die Arbeitsdateien die
von `SAVE.00`).

**Regel:** Wo Thalions Startweg eine Wahl von außen liest, übergeben wir sie
auf demselben Namen, statt den Weg zu umgehen. *(Gruppe P)*

## 262. Spieldaten und Spielstände im Unterordner, wie `Amberfiles/`

*2026-09-30, Wunsch des Nutzers. Gelesen in AM2_CPU 1.20 und im
ausgepackten Original; umgesetzt in `HULL/FILES_SUP.S` (`Datei_name`,
`Ordner_suchen`) und `tools/baue_alles.sh`. Auf Hardware getestet
2026-09-30.*

**Das Original.** Oben liegt nur das Startprogramm `Ambermoon`, alles
andere in `Amberfiles/`: Spieldaten, `Saves`, `Save.00`–`Save.10`, die
Arbeitsdateien und die Programme `AM2_CPU`, `Ambermoon_intro`,
`Fantasy_intro`. AM2_CPU trägt die Zeichenketten `AMBER_ :` (Diskette) und
`Amberfiles/` (Festplatte) vor seiner Namenstabelle und setzt sie jedem
Namen voran; die Namen selbst sind bloß (`Party_data.sav`,
`Save.00/Party_char.amb`).

**Bei uns.** `FALCON/` trägt oben nur die Desktop-Dateien und später den
Lader `AMBER.TOS`; alles andere, auch `ENGINE.TOS`, steht in
`FALCON/AMBFILES/` (8.3). `Datei_name` setzt `AMBFILES\` vor jeden Namen,
auch vor die mit Nummer 0 (`SAVE.nn\…`), und gibt ihn in `dn_voll` zurück.
Alle Lade- und Speicherwege gehen durch `Datei_name` (`Datei_lesen`,
`Datei_sichern`); nur die Diagnoseausgabe von `ENTPACKPRUEF` schreibt
ins Arbeitsverzeichnis.

**Ob der Vorsatz gilt, entscheidet `Ordner_suchen` einmal beim Start:**
Gibt es neben uns einen Ordner `AMBFILES`, ja. So geht beides: der Lader
startet uns aus dem Verzeichnis darüber, der Desktop aus `AMBFILES`
selbst, und die Prüffassung liegt flach. Das Arbeitsverzeichnis wird
nicht umgestellt (`Dsetpath`): unter TOS teilen es sich die Programme,
der Lader stünde danach woanders.

**Regel:** Pfade setzt die Bibliothek an einer Stelle zusammen, wie
AM2_CPU. *(Gruppe V)*

## 263. Die Rückgabewerte für `Return_value` stehen in AM2_CPU

*2026-10-01, Befund der Intro-Sitzung für `GAME_COMPLETED`, die übrigen
nachgelesen. Umgesetzt in `tools/originalcode/vorspann.i`, Platzhalter
`OS_ERROR` aus `HULL/AM2_CPU_STUBS.S` entfernt.*

**Befund.** Die sieben Rückgabewerte, die Thalions Code vor `jmp
Exit_program` nach `Return_value` schreibt, waren bei uns angenommen
(−201 bis −206, nur unterscheidbar). AM2_CPU 1.20 hat sie an den
Aufrufstellen als `move.l #n,$9CB4` (9:$9CB4 = `Return_value`); die
Stellen sind an der umgebenden Befehlsfolge eindeutig Thalions Quelltext
zugeordnet:

| Name | Wert | AM2_CPU | Thalions Stelle |
|---|---|---|---|
| `OS_ERROR` | −1000 | 0:$2924A | `CONTROLS.S` nach `Close_current_file` |
| `MERGED_TEXT_TOO_LONG` | −3001 | 0:$2701C | `WORDS.S`, `Raw_length` |
| `PROCESSED_TEXT_TOO_LONG` | −3002 | 0:$2712C | `WORDS.S`, `Processed_length` |
| `ENDLESS_EVENT` | −4002 | 0:$1291A | `EVENTS.S`, `Chain_to_next_event` |
| `GAME_COMPLETED` | −5000 | 0:$12D4A | `EVENTS.S`, `End_seq` |
| `GAME_COMPLETED2` | −5001 | 0:$12D3E | Valdyn mit „dem Ding“ |
| `GAME_COMPLETED3` | −5002 | 0:$12D26 | Valdyn nicht in der Gruppe |

Dazu schreibt die Bibliothek selbst −2001 bis −2006 (0:$24AA2–$24E4A, die
Speicherverwaltung). Thalions Lader liest die Rückgabe: ab −5000 abwärts
startet er das Extro mit n = −Wert − 5000 (Intro-Sitzung).

**`OS_ERROR` war ein Datenplatzhalter** (`ds.w 1`). Thalion schreibt aber
`move.l #OS_ERROR,Return_value`: gemeint ist eine Zahl, bei uns ging die
Adresse des Platzhalters hinein. Jetzt steht die Zahl in `vorspann.i`, wie
bei den anderen sechs. Die Vollprobe zählt 292 Namen statt 293, denn eine
Konstante ist kein Bibliotheksname.

**Rückgabe an den Lader (E2, Nutzer 2026-10-01).** `Return_value` ist
seitdem eine echte Variable in `src/MAIN.S` (kein Platzhalter mehr), und
`Exit_program` endet mit `Pterm` und ihrem unteren Wort statt mit `Pterm0`.
Der Lader `AMBER.TOS` (Intro-Sitzung) startet bei −5000 bis −5002
`EXTRO.TOS` mit `'0'` bis `'2'`. Ein normales Ende gibt 0 zurück, weil TOS
das BSS beim Start löscht. Zum Prüfen ohne Durchspielen:
`VASM_EXTRA="-DENDETEST=n"`, dann gilt ein Ende ohne eigenen Wert als
Spielende n.

**Regel:** Ein Name hinter `#` ist eine Konstante, auch wenn er fehlt;
sein Wert steht an Thalions Aufrufstelle in AM2_CPU. *(Gruppe V)*

## 264. Eine Farbbank je Platz in der Rasterliste

*2026-10-01, am Savestate des Nutzers („Portraitpalette falsch“, B4,
seit 2026-09-28 offen). Umgesetzt in `HULL/LIBRARY.S` (`Farbbank`) und
`HULL/FADE_SUP.S` (`Set_fade`, `Platz_setzen`, `Platzbank`).*

**Befund.** Im Savestate lief das Ereignisbild „Großvater“, oben lag
`ShowPicTxt_RL`: Zeilen 0–36 `Main_pal`, ab 37 `Batch`. Die ganze obere
Leiste mit Portraits, Rahmen und Balken stand in **Bank 0**. Bank 0 trug
`Batch`, die Palette des Bilds, also zeigte die Leiste deren Farben.
Richtig wäre Bank 2 gewesen, die `Main_pal` trägt. Ausgelesen aus dem
Abbild: Videl-Palette, Schirm, `Bank0_pal` = `Batch` und der Modulstapel.

**Ursache.** `Farbbank` wählte die Bank danach, *was gerade in Bank 0
stand*. Nannte die Rasterliste für eine Zeile `Main_pal` und trug Bank 0
ebenfalls `Main_pal`, gab es Bank 0 zurück. Die Punkte bleiben aber, und
die Bank wechselt:
1. Thalions `Fade_out_bottom` setzt am Ende `Main_RL`, also steht
   `Main_pal` in Bank 0.
2. Das nächste Modul zeichnet die Leiste hinein.
3. `Fade_in_bottom` legt dann die Bildpalette nach Bank 0.

Das geschah bei jedem Modulwechsel dieser Art. Die Bankbits im Abbild sind
belegt; der Zeitpunkt ist erschlossen, nicht mitgeschnitten.

**Jetzt.** Die Bank hängt am **Platz** der `R_palette` in der Liste des
obersten Moduls (`Platzbank`):

| Platz in der Liste | Bank |
|---|---|
| erste `R_palette` | 2 |
| zweite `R_palette` | 0 |
| dritte `R_palette` | 1 |

`Set_fade` legt jeden Platz, dessen `R_palette` im Zeilenbereich d1..d2
beginnt, in seine Bank und blendet alle zugleich. Das ist Thalions
Zeilenbereich aus `FADE.S`:
- `*_bottom` beginnt bei `Middle_Y` und lässt die Leiste stehen.
- `*_all` beginnt bei 0 und nimmt sie mit.
- `Fade_out` kommt ohne Liste. Es nimmt die zuletzt gesetzte
  (`Letzte_RL`) und blendet von `Bank_ist` weg.

Damit hat auch `Combat_RL` mit drei Paletten Platz: `Tactic_pal` liegt jetzt
in Bank 1, bisher teilte sie sich die Bank mit `Combat_pal`.

**Zwei Nachbefunde aus dem ersten Test** (Savestates des Nutzers,
2026-10-01). Beide Fehler gab es schon vorher; das alte Modell verdeckte
sie, weil Bank 0 oft zufällig `Main_pal` trug:
- *Charaktereditor:* Rahmen und Kopf des Fensters waren schwarz. Unser
  `Put_masked_icon` (Fensterteile aus Thalions `Put_window_part`) nahm als
  Farbbasis nur `d4`, ohne die Bank der Zeile, und zeichnete darum immer in
  Bank 0. Die Rasterliste des Editors hat nur eine Palette (Bank 2), also
  blieb Bank 0 schwarz. Jetzt gilt `d4` ODER `Farbbank(y)`.
- *Kampf:* Unten rechts im Portrait stand ein Stück Leiste in Bank 0.
  Thalions `TacticSel_Mod` (Zielwahl) hat die Rasterliste 0 und erbt die
  ScrQ des Kampfs, darunter `Display_combat_status_icons`. Auf dem Amiga
  bleibt bei Rasterliste 0 die Copperliste stehen; `Set_fade` und
  `Reset_current_RL` tun dann nichts. Jetzt geht `Farbbank` im Modulstapel
  abwärts bis zum ersten Modul mit Rasterliste.

**Unverändert:**
- Ohne jede Rasterliste und in Hilfsschirmen gilt Bank 0. Unser Startmenü setzt
  sie mit `Bank0_setzen`, das jetzt der zweite Platz ist.
- ~~Der Mauszeiger zeichnet in Bank 0.~~ Falsch, siehe 266.
- `R_range` bleibt flach.

**Regel:** Die Bank eines Punkts darf nur von seiner Lage abhängen, nie
davon, was eine Bank gerade enthält. Sonst färbt er sich später um.
*(Gruppe F)*

## 265. `d4` gilt nur für die Ebenen ab `d5`, auch in `Put_masked_icon`

*2026-10-01, an zwei Savestates des Nutzers: Falcon und Amiga, beide im
Kampf. Umgesetzt in `HULL/LIBRARY.S` (`Put_masked_icon`).*

**Befund.** Rechts neben dem Portrait zeigt Thalions `Update_status_block`
(DISPLAY.S) das Zustandssymbol, hier das Bewegungskreuz der nächsten
Kampfaktion. Auf dem Amiga besteht es aus den Farben 1, 3, 4 und 7
(Copperliste und Chip-RAM aus dem Savestate). Bei uns waren es 25, 27, 28
und 31, also jeder Punkt um genau 24 verschoben. Die Bank (2, `Main_pal`)
stimmte.

**Ursache.** Thalion löscht die Stelle erst mit `Put_unmasked_icon` (`d4` =
24, `d5` = 3) und zeichnet das Symbol dann mit `Put_masked_icon` und `d5` =
`Screen_depth`, **ohne `d4` neu zu setzen**. Nach dem Vertrag trägt `d4`
nur die Ebenen ab `d5` bei. Bei fünf Quellebenen ist die 24 wirkungslos,
das zeigt der Amiga. Unser `Put_masked_icon` ODERte `d4` aber in alle
Ebenen, auch in die aus der Quelle. `Put_unmasked_block` und
`Quelle_aufweiten` maskierten richtig; nur diese Routine nicht.

Der Fehler ist älter als 264. Nach dem Code betraf er jedes Zustandssymbol
am Portrait, auch auf der Karte (Übergewicht, Krankheiten). Belegt ist nur
das Kreuz im Kampf.

**Jetzt.** Ebenen unter `d5` bekommen nur die Quelle. Farbbits aus `d4` und
der Bank gelten erst ab `d5`; die Bankbits liegen ab Bit 5 und sind davon
nicht berührt.

**Regel** (steht vorn schon, hier verletzt): Farbe = Bank der Bildzeile +
`d4` **oberhalb `d5`** + Quellwert. Thalion lässt `d4` stehen, wo es nicht
zählt; die Bibliothek muss es dort übergehen. *(Gruppe F)*

## 266. Der Mauszeiger trägt die Bank seiner Bildzeile, wie ein Sprite

*2026-10-01, Hardwaretest des Nutzers: im Charaktereditor war der Zeiger
(Schwert) eine schwarze Silhouette, im Spiel stimmten die Farben.
Umgesetzt in `HULL/AREAS.S` (`Set_mouse_ptr`) und `HULL/LIBRARY.S`
(`Zeiger_in_puffer`, `Rasterbank`).*

**Ursache.** `Set_mouse_ptr` weitete den Zeiger auf Farbe 24 + Bildwert in
**Bank 0** auf; 264 hatte das ausdrücklich so gelassen. Seit 264 ist Bank 0
aber der zweite Platz der Rasterliste. Der Editor hat nur eine Palette
(Bank 2), Bank 0 bleibt schwarz. Im Spiel gibt es immer einen zweiten
Platz, darum fiel es dort nicht auf. Die Farben waren dort aber die 24–31
der zweiten Palette, nicht die Graurampe von `Main_pal`.

**Der Amiga** (abgeleitet, nicht an einem Savestate geprüft): Der Zeiger
ist ein Sprite. Seine Farben sind Farbregister, und die setzt die Copper je
Zeile um. Er trägt also die Farben 24–31 der Palette, über der er steht.

**Jetzt.** Wie jede Grafik nimmt der Zeiger die Bank seiner Bildzeile:
- `Set_mouse_ptr` legt die Zeigerpunkte auch in die Ebenen 5 und 6.
- `Zeiger_in_puffer` holt je Zeile `Rasterbank` und lässt die Ebenen ab
  `Data_depth` nur, wo die Bank ihr Bit hat. Die erste gezeichnete Zeile
  ist max(y, 0), auch angeschnitten.
- `Rasterbank` ist `Farbbank` ohne die Hilfsschirmprüfung: Der Zeiger
  steht immer im angezeigten Bild. Welcher Schirm gerade `Work_screen`
  ist, darf seine Farbe nicht ändern.

Über einer Bereichsgrenze ist der Zeiger damit zweifarbig, wie auf dem
Amiga.

**Falle im ersten Wurf** (Savestate des Nutzers, Zeiger weiter schwarz):
`swap d1 / btst d7,d1 / swap d1 / bne` prüft nicht das Bit. `swap` setzt
N und Z nach dem Ergebnis, und `d1` ist nie null; die Ebenen 5 und 6
blieben immer stehen, der Zeiger lag in Bank 3. Jetzt prüft `btst` das
obere Wort direkt (Bitnummer + 16; bei einem Datenregister zählt sie
modulo 32). Zwischen Test und Sprung gehört kein Befehl, der Flags setzt.
*(Gruppe F)*

## 267. Der Diagnoseschirm zeichnet in den sichtbaren Schirm, der Speicherverwalter zählt

*2026-10-01, gelesen in AM2_CPU 1.20, noch nicht auf Hardware geprüft.
Umgesetzt in `HULL/DIAGNOSE_SUP.S` (neu), `HULL/MEMORY.S`, `HULL/LIBRARY.S`
(`Farbbank`), `MAIN.S` (`Restart_game`), `HULL/FILES_SUP.S`.*

**Der Diagnoseschirm** (0:$26414 `Init_diagnostic_screen`, 0:$2646A
`DI_Print_text`, 0:$26452 `Exit_diagnostic_screen`):
- `Init` löscht den **sichtbaren** Schirm und macht ihn zu `Work_screen`.
  Die Schreibstelle steht dann auf 0,0, Maus- und Clipbereich sind das
  Vollbild, die Schriftfarbe ist 31.
- `DI_Print_text` gibt Zeilen mit Endnull aus, die Liste endet mit `$FF`.
  Das Raster ist 6 × 7 Punkte. Nach 28 Zeilen kommt Thalions `Wait_4_click`
  (0:$266D4 ist `VARIOUS.S`), dann wird der Schirm gelöscht.
- `Exit` nimmt die Bereiche herunter, wartet auf den Klick und springt nach
  `Update_screen`. `Work_screen` lässt es stehen, den Tausch erledigt
  `Update_screen`.

**Folge für die Farbe.** Wer in den sichtbaren Schirm zeichnet, bekommt
die Farben der Copperliste, die gerade läuft. Bei uns ist das `Letzte_RL`,
die Liste, die `Set_fade` zuletzt gesetzt hat. Die Liste des obersten
Moduls gilt hier nicht. `Out_of_memory` setzt mit `Fade_out_all` die
`Main_RL`. `Farbbank` nimmt deshalb für `Work_screen = Schirm_vorn` die
`Letzte_RL`. Vorher galt jeder Schirm außer `Off_screen` als Hilfsschirm
mit Bank 0. Diese Bank ist nach `Fade_out_all` zwar ebenfalls `Main_pal`,
aber nur zufällig. *(Gruppe F)*

**Der Speicherverwalter zählt** (0:$24B30 `Claim_pointer`, 0:$24B6E
`Free_pointer`):
- Byte 19 des Blockkopfs ist der Zähler. Er steigt bis 255 und fällt nicht
  unter 0.
- `Clear_all_claims` (0:$23D9E) setzt alle Zähler auf 0.
- `Kill_unclaimed_memory` (0:$23D06) gibt jeden Block frei, der eine Datei
  trägt (Byte 20) und den keiner festhält.

Bei uns verschiebt sich nichts, und `Free_pointer` war bisher leer. Das
genügte, solange nur Thalion zählte. Jetzt zählen unsere Routinen auf
demselben Namen mit: Sie riefen `Claim_pointer` an 26 Stellen ohne
`Free_pointer`. Dann hätte jeder Block, den `Load_subfile` an Thalion
gibt, einen Zähler getragen, den niemand mehr abbaut. Unsere Schicht holt
die Adresse deshalb über `Block_adresse`, ohne zu zählen.

Das Byte 20 des Originals heißt bei uns `MEM_ART`: `Load_file` und
`Load_subfile` kennzeichnen damit ihr Ergebnis (`Dateiblock`).
*(Gruppe V: Mit dem Namen gilt der ganze Vertrag, auch das Zählen.)*

**Out_of_memory wie im Original.** Der Speicherverwalter springt dort mit
`jmp Out_of_memory` hinein (0:$240D8). Unsere `Speicher_voll`-Meldung auf
dem TOS-Schirm bleibt nur als letzter Halt (`Notweg`):
- Vor dem Ende von `Init_program` stünde in `Party_data` nichts, und
  `Out_of_memory` würde das als Spielstand sichern.
- Während `Out_of_memory` läuft, darf es sich nicht selbst rufen.

Unsere Ladeschicht fordert über `Speicher_anfordern` an. Ohne `Notweg`
bekommt sie 0 zurück und weicht aus. Das braucht `Save_subfile`, während
`Out_of_memory` die Gruppe sichert. Danach folgt `Restart_game` mit
`Initial_save = -1`: Thalions `Init_program` überspringt
`Get_saved_game` und lädt die eben gesicherten Arbeitsdateien.

**`Diagnostics_list1`** (4:$4DE0) hat einen Eintrag: Amiga-Taste und „1“
rufen 0:$263DA. Diese Routine schreibt 65 536 Werte nach `COLOR00` und
dient als Messhilfe. Bei uns ist es Videl-Farbe 0, die danach
wiederhergestellt wird. Die Amiga-Taste ist bei uns Help als Vorsatz
(Nutzer, 2026-10-01): `Read_key` schluckt Help und setzt Bit 28 an der
nächsten Taste. Halten lässt sich Help nicht, weil `Bconin` das Loslassen
nicht meldet. Thalions Code fragt die Amiga-Help-Taste (`$5F`) nirgends
ab. Also: Help, dann 1.

## 268. Diskfehler gehen an Thalions Abfrage, ein fehlender Teil an den Ladefehlerschirm

*2026-10-01, gelesen in AM2_CPU 1.20, auf Hardware geprüft (Diskfehler,
Ladefehlerschirm; Help, dann 1 noch nicht).
Umgesetzt in `HULL/FILES_SUP.S` (`Dateifehler`, `Fehler_umsetzen`,
`Datei_lesen`, `Datei_sichern`, `Load_subfile`), `HULL/DIAGNOSE_SUP.S`
(`Ladefehler_schirm`), `HULL/LIBRARY.S` (`Close_current_file`),
`tools/originalcode/vorspann.i` (Fehlernummern).*

Bisher kehrten unsere Laderoutinen bei jedem Fehler still mit 0 zurück, und
Thalions Code las ins Leere. Das Original unterscheidet zwei Fälle.

**Diskfehler** (0:$25FDA, 0:$25FF8). Jede DOS-Routine der Bibliothek holt
bei einem Fehler `IoErr` und ruft Thalions `Disk_error_handler`
(`HULL/CONTROLS.S`):
- Er sucht die Nummer in `Disk_errors` und zeigt „Fehler … Datei …
  Nochmal?“. Den Dateinamen nimmt er aus `Current_filename`.
- „Ja“: zurück, die Routine versucht es von vorn.
- „Nein“: `Close_current_file`, `Return_value = OS_ERROR`,
  `Exit_program`.
- `ERROR_DEVICE_NOT_MOUNTED` ging stattdessen an `Disk_requester`. Das
  kann GEMDOS nicht melden.

Bei uns setzt `Fehler_umsetzen` den GEMDOS-Fehler nach Bedeutung in die
AmigaDOS-Nummer um. Ein zu kurzes Lesen oder Schreiben wird zu Thalions
`ERROR_INCOMPLETE_READ`/`WRITE`. `Datei_lesen` und `Datei_sichern` bilden
bei jedem Versuch den Namen neu, denn `dn_voll` ist flüchtig. Gefragt wird
nur, wenn der Notweg offen ist (267). Vorher und während `Out_of_memory`
fehlen Schirm, Stapel oder Ruhe, und es bleibt beim stillen Fehler.

**Die Fehlernummern stehen in AM2_CPU.** Thalions übersetzte Tabelle
`Disk_errors` liegt bei 0:$2925C. Vier Werte in `vorspann.i` wichen ab, sie
waren „aus dos/dos.h belegt“: `OBJECT_TOO_LARGE` 211 statt 207,
`SEEK_ERROR` 227 statt 219, `INCOMPLETE_READ`/`WRITE` 234/235 statt
500/501. Die beiden letzten sind Thalions eigene Nummern. Solange nur
`Disk_error_handler` sie las, fiel das nicht auf. *(Gruppe V: Auch eine
Konstante ist Teil des Vertrags, und der Beleg ist die übersetzte Stelle.)*

**Ein fehlender Teil ist kein Diskfehler** (0:$2510A, 0:$2637C). Verlangt
Thalion einen Teil hinter dem letzten des Behälters, zeigt die Bibliothek
den Diagnoseschirm:
- „FILE COULDN'T BE LOADED :“, zwei Leerzeilen, den Namen der Dateiart und
  die Teilnummer.
- Dann wartet sie auf einen Klick und das Programm endet.

Die 45 Namen („Memory block“ … „Object graphics“, je 22 Byte) und die
Überschrift zieht `am2cpu_auszug.py`. Das Original findet die Namen über
die Zeigertabelle 4:$4934, deren Zeiger in Schritten zu 22 Byte gehen. Wir
rechnen die Lage aus.

**`Close_current_file`** schloss bisher `f_handle(a5)`. Das setzt niemand,
und `a5` gehört beim Aufruf aus `Disk_error_handler` nicht uns (177). Es
hätte eine fremde Dateikennung geschlossen. Unsere Routinen schließen jede
Datei, bevor sie einen Fehler melden; die Routine ist jetzt leer, und das
ist ihre richtige Übersetzung.

## 269. Der Mauszeiger folgt in jedem Bild, nicht im Takt des Spiels

*2026-10-02, Befund des Nutzers auf dem Falcon (über die Musik-Sitzung),
auf Hardware geprüft (flüssig auf Karte, im 3D, im Kampf, im Inventar). Umgesetzt in `HULL/LIBRARY.S`
(`Zeiger_vbl`, `Zeiger_nachfuehren`, `Update_mouse`, Sperre in
`Schirmwechsel`, `Copy_screen`, `Duplicate_block`), `HULL/AREAS.S`
(`Set_mouse_ptr`), `HULL/DIAGNOSE_SUP.S`, `MAIN.S`; Messung mit dem
Schalter `ZEIGERTAKT`.*

**Befund.** Auf der Karte und im Spiel fühlte sich die Maus ruckelig und
schwammig an. Im Optionsmenü, wo die Maus in der Tastenfläche gefangen
ist, lief sie flüssig. Mit der Musik hatte es nichts zu tun.

**Ursache.** Auf dem Amiga ist der Zeiger ein Hardwaresprite. Die
Bibliothek setzt seine Lage in jedem Bild, gleich wie lange Thalions Code
an einem Bild zeichnet. Der Falcon hat keine Sprites. Bei uns stand der
Zeiger im Bild und wanderte nur beim Schirmwechsel mit
(`Zeiger_hinten_zeichnen`): Er kam so oft voran, wie das Spiel ein Bild
fertig hatte, und zeigte die Lage von vor dem Tausch. Im Optionsmenü gibt
es wenig zu zeichnen, dort wechselt der Schirm fast in jedem Bild.
*Angenommen, bis `ZEIGERTAKT` es auf der Karte zeigt:* dort liegen mehrere
Bilder zwischen zwei Wechseln.

**Umsetzung.** `Bibliothek_vbl` ruft jetzt `Zeiger_vbl`, und das führt den
Zeiger im sichtbaren Schirm nach. Der Weg dafür bestand schon
(`Update_mouse`, flackerfrei für Startmenü und `Wait_key`); er heißt jetzt
`Zeiger_nachfuehren`. Neu ist eine **Sperre** (`zeiger_sperre`, ein
Zähler). Der VBL kommt mitten in den Code. Wer den sichtbaren Schirm samt
Zeiger liest oder den Zeigersatz von vorn benutzt, zählt sie hoch:
- `Schirmwechsel`: Zwischen dem Tausch von `Schirm_vorn` und dem Umschlagen
  von `Screen_flag` wiese `Zeiger_satz_vorn` auf den falschen Satz.
- `Copy_screen` und `Duplicate_block`: Sie kopieren den Zeiger mit und
  nehmen ihn hinten mit dem Hintergrund von vorn heraus. Wanderte er
  dazwischen, wäre die Kopie zerrissen und der Hintergrund falsch.
- `Set_mouse_ptr`: Ein halb umgeschriebenes Bild würde gezeichnet, und
  `zg_neu` wäre schon verbraucht.
- `Update_mouse`, das unsere Warteschleifen noch rufen.

Solange die Sperre steht, bleibt der Zeiger stehen und kommt im nächsten
Bild nach. Ebenso, solange in den sichtbaren Schirm gezeichnet wird
(`Work_screen` = `Schirm_vorn`, der Diagnoseschirm), denn der gesicherte
Hintergrund wäre dort veraltet. `Init_diagnostic_screen` setzt darum erst
`Work_screen` und löscht dann. Thalions eigene Hilfsschirme (`INVENTOR.S`,
`CONTROLS.S`) sind eigene Speicherblöcke und berühren den sichtbaren
Schirm nicht. `Restart_game` gibt die Sperre frei, falls jemand aus einem
gesperrten Stück dorthin sprang.

**Kosten.** Steht die Maus, kostet der VBL einen Vergleich. Teilen alter
und neuer Fleck Zeilen, setzt `Zeiger_nachfuehren` sie im Zwischenstück
zusammen. Bisher kopierte es dafür ganze Zeilen, bis zu 32 mal 320 Byte
hin und zurück, gut 20 KB je Bild. Jetzt nur die Blöcke, die einer der
beiden Flecke berührt, meist drei.

**Messen.** Mit `ZEIGERTAKT` zeichnet `Schirmwechsel` oben links zwei
Balken in den hinteren Schirm, je Bild zwischen zwei Wechseln einen Block:
Zeilen 0–1 der letzte Abstand, Zeilen 3–4 der größte einer Sekunde.

*(Gruppe Z: Was auf dem Amiga die Hardware im Interrupt erledigt, gehört
bei uns in den VBL, nicht in den Takt des Spiels.)*

## 270. Ein TOS-Aufruf zerstört d0–d2/a0–a2, auch wenn Hatari es nicht tut

*2026-10-02, Absturz auf dem Falcon des Nutzers (14 MB, TOS 4.04), belegt
mit `BOMBEN.TOS` und der Symbolkarte desselben Baus; die Korrektur ist
auf dem Falcon geprüft (Start, Karte, 3D, Kampf, Inventar). Umgesetzt in
`FALCON_OFF.S` (Makros `Gemdos`, `Bios`, `Xbios`), allen 62 TOS-Aufrufen
unseres Codes, `MAIN.S` (`Tos_rette`), `tools/trap_pruefen.py`.*

**Befund.** `ENGINE.TOS` zeigte beim Start zwei Bomben. In Hatari mit
demselben TOS-Abbild lief es, in EmuTOS ebenso.

**Beleg.** `BOMBEN.TXT`: Ausnahme 2 (Busfehler), PC $0017F52A, Rahmen
Format $B, Zugriff auf $00E1C2EE, SSW $070D (Schreiben, Langwort,
Supervisor-Daten), A0 = $00E1C2EA. Ladeadresse $0017CDF0, also Versatz
$273A: `am_hat` in `Speicher_holen` (`MEMORY.S`), der Befehl
`move.l d0,MEM_ROH(a0)` unmittelbar nach `Mxalloc`. `MEM_ROH` ist 4, und
a0 + 4 ist genau die Zugriffsadresse. a0 sollte auf `memtab` zeigen; nach
dem Trap zeigte es ins TOS-ROM. Auf dem Falcon ist ein Schreiben ins ROM ein
Busfehler, Hatari übergeht es.

**Ursache.** GEMDOS, BIOS und XBIOS dürfen d0–d2 und a0–a2 zerstören, so
steht es in Ataris Beschreibung, und in `TASTEN.S` stand es schon als
Kommentar. EmuTOS und der Weg durch Hatari lassen diese Register meist
stehen; auf dem Falcon des Nutzers überschrieb sie TOS selbst oder ein
Treiber im AUTO-Ordner. Welches von beiden, ist nicht geklärt und für die
Abhilfe gleich. Weitere Stellen mit derselben Falle: `Free_memory` (a0 nach
`Mfree`), `Datei_lesen` (Name in a2, Puffer in a1, Handle in d2 über
mehrere Traps), `Datei_sichern` (a2, d2 nach `Fclose`), `Datei_schreiben`
im Diagnosebau.

**Abhilfe.** Unser Code ruft TOS nur über drei Makros. Sie retten
d1–d2/a0–a2 in einen festen Platz (`Tos_rette`), rufen den Trap und holen
sie zurück; `movem` lässt die Flags des Traps stehen, d0 bringt das
Ergebnis. Ein fester Platz statt des Stapels, weil die Argumente schon dort
liegen. Das ist sicher, weil kein Code von uns während eines Traps TOS ruft
(kein `Supexec`, im Interrupt kein TOS). Alle 62 Stellen sind umgestellt,
nicht nur die gefundenen. `trap_pruefen.py` bricht den Bau bei einem
nackten Trap ab. Ein kurzer Sprung (`beq.b dsi_fehler`) reichte danach nicht
mehr und wurde lang.

**Hilfsmittel für den nächsten Absturz.** `ENGINE.TOS` meldet beim Start
seine Ladeadresse. `BOMBEN.TOS` (`tools/bomben/bomben.s`, im Bau) zeigt den
Bereich ab `$380`, den TOS beim Absturz füllt, und schreibt ihn nach
`BOMBEN.TXT`. Seine Suche nach der Engine im Speicher fand hier eine alte
Kopie des Suchtexts, nicht die Engine; maßgeblich ist die abgelesene
Ladeadresse.

*(Gruppe R: Auch ein Trap ist ein Aufruf mit Vertrag. Und Gruppe M: Was
Hatari und EmuTOS durchgehen lassen, ist kein Beleg für den Falcon.)*

## 271. Die 2D-Karte war langsam, weil jede Kachel in jedem Bild neu aufgeweitet wurde

*2026-10-02, Befund des Nutzers auf dem Falcon („die Bewegung durch die
2D-Karte bei gedrückter Taste könnte einen Mü schneller sein“), gemessen
mit `ZTTEST.TOS` (269) und dem Hatari-Profiler; auf dem Falcon geprüft:
5 VBL je Bild statt 15–17, mit bewegter Maus 6; Farben und Bild überall in
Ordnung. Umgesetzt in `HULL/LIBRARY.S` (`Farbbank_spanne`, `Kachel_holen`,
`Put_unmasked_block`, `Put_masked_icon`).*

**Befund.** Zwischen zwei Schirmwechseln vergingen auf dem Falcon 15–17
VBL, in Hatari 5–7, im Stehen wie beim Laufen. Thalions `Make_2D_move`
lässt die Gruppe ziehen, sobald `Timer` (+1 je VBL, `Time_2D`) den Wert
`M2_movement_speed` (8) minus `Time_warp` erreicht, und fragt das einmal je
Durchlauf der Hauptschleife. Bei 16 VBL je Bild kam also nur jeder zweite
mögliche Schritt: halbe Geschwindigkeit. Dass der Zeiger trotzdem flüssig
lief, lag an 269.

**Messung** (Hatari, Falcon, TOS 4.04, Spielstand „Anfang“ des Nutzers,
Großvaters Haus, 500 VBL im Stehen): Thalions Code kostete fast nichts.
`Farbbank` 33 %, `Put_unmasked_block` 29 %, `Put_masked_icon` 13 %, Warten
auf den VBL 13 %. Thalion zeichnet die Karte in jedem Bild ganz neu, rund
155 Kacheln, und für jede Zeile jeder Kachel lief `Farbbank` Modulstapel
und Rasterliste ab, und jede Kachel wurde aufs Neue von fünf auf acht Ebenen
aufgeweitet.

**Abhilfe**, nur in unserer Bibliothek (Tempo in der Hardwareschicht,
Freigabe des Nutzers):
- `Farbbank_spanne` gibt mit der Bank die Zeile zurück, ab der eine andere
  gelten kann. `Put_unmasked_block` und `Put_masked_icon` fragen erst an
  dieser Grenze wieder, nicht je Zeile. Die Regel bleibt die von 264.
- `Kachel_holen`: Kachelspeicher mit 1024 Plätzen (456 KB BSS). Eine Kachel
  (ein Block, sechzehn Zeilen, bis fünf Ebenen, eine Bank über alle
  Zeilen) wird einmal mit Maske auf acht Ebenen aufgeweitet und danach nur
  kopiert. Wie `St_kachel` im ST-Port (docs/12, P3).
- **Gültig ist ein Eintrag nur bei gleichem Inhalt der Quelle**, nicht nur
  bei gleicher Adresse: Jeder Platz hält eine Abschrift und vergleicht sie
  ganz. Geplant war ein Ladezähler in `FILES_SUP.S`. Er reicht nicht, denn
  `Get_block` legt Hintergründe immer wieder an derselben Adresse ab, und
  Thalion schreibt Speicher auch ohne Bibliotheksaufruf. Eine Prüfsumme
  wie beim ST erkennt nur fast sicher. Der Vergleich kostet so viel wie das
  Kopieren, das Aufweiten ein Vielfaches.

**Ergebnis in Hatari:** 166 statt 84 Bilder in 500 VBL, also rund 3 statt
6 VBL je Bild. Die Abzüge bei VBL 2000 und 2500 sind punktgleich mit
vorher. Übrig sind vor allem das Kopieren in den Schirm (rund 30 %) und
der Vergleich (13 %). Auf dem Falcon gemessen: 5 statt 16 VBL (erwartet
waren 8). Für Thalions vollen Schritttakt braucht es höchstens 4, mit Maus
und Musik.

**Nachtrag (2026-10-02, auf dem Falcon geprüft):** `Farbbank_spanne`
merkt sich ihr Ergebnis je Rasterliste und Zeilenspanne. Thalions Listen
sind feste Daten in `MODULES.S`, und der Merker traf im Messlauf immer.
`Draw_box` fragte die Farbe noch je Zeile (rund 176 Aufrufe je Bild), der
Mauszeiger je Zeile über `Rasterbank`. Beide fragen jetzt je Spanne,
der Zeiger über `Rasterbank_spanne` ohne Merker, weil er im VBL läuft.
Hatari: rund 7 % weniger Arbeit je Bild (Warten auf den VBL 13 % statt
7 %), Abzüge im Spielbereich punktgleich. **Auf dem Falcon unverändert 5
VBL, mit bewegter Maus 6.** Der Gewinn reicht nicht über eine VBL-Grenze;
er bleibt als Luft für die Musik, die im VBL läuft.

**Das 3D-Bild gemessen** (Spielstand „Keller Brunnen“ des Nutzers,
Großvaters Keller): Hatari 4 VBL je Bild, Falcon 8. Rund zwei Drittel sind
Thalions Rasterer aus `AM2_CPU` (`Draw_floor`/`Draw_ceiling` 29 %,
`put_dpoly` 17 %, `draw_zoomshape` 8 %). Bei uns liegen rund 16 %:
`Show_MOVEP_screen` 9 %, die Bank je Zeile darin 4 %,
`Clear_1plane_block` 2 %. Das gehört der 3D-Sitzung, sie hat den Befund.

*(Gruppe F: Die Bank wechselt nur an den Zeilen, an denen eine R_palette
beginnt; wer zeichnet, fragt einmal je Spanne.)*

## 272. Nach Bomben räumt der Notausgang über etv_term auf

*2026-10-09, auf dem Falcon des Nutzers geprüft (T1, TOS 4.04, Bau mit
`ABSTURZTEST`). Umgesetzt in `MAIN.S` (`Notausgang`), `FALCON.S`
(`Close_screen`), `MEMORY.S` (`Free_memory`); Commit 10804d6.*

**Befund.** Nach Bomben kehrte TOS zum Desktop zurück, aber mit unserem
Bildmodus, unserer Palette, ohne Maus und mit laufendem Ton.

**Weg.** TOS ruft in `Pterm` den Vektor `etv_term` (`$408`, `Setexc`
`$102`), auch nach Bomben. `start` hängt dort `Notausgang` ein. Er nimmt
Musik, Raster, Maus und Schirm herunter, setzt den alten Vektor zurück und
springt hinein. Dabei gelten drei Regeln:
- **Kein GEMDOS**, denn `Pterm` steht noch in GEMDOS (`Im_notausgang`:
  `Close_screen` lässt `Mfree` und `Cconws` aus). XBIOS geht.
- **Interrupts auf `$2300`**, sonst wartet `Vsync` ewig, wenn die Bomben im
  Interrupt kamen.
- **Jede Abbauroutine ist wiederholbar** (`mk_bereit`, `ras_da`, `p_kbd`,
  jetzt auch `Schirm_offen`), denn auf dem normalen Weg hat `Exit_program`
  schon abgebaut, bevor `Pterm` den Notausgang ruft.

Nebenbei: `Free_memory` rief für ein vorgetäuschtes Handle
(`Create_fake_handle`, `MEM_ROH` = 0) `Mfree(0)`, sobald `Kill_all_memory`
beim Neustart darüberlief. Jetzt wird nur der Eintrag geleert.

Nicht abgedeckt: ein Absturz in unserem eigenen VBL.

## 273. Laden im Spiel: die Musik muss vor Kill_all_memory aus

*2026-10-09, auf dem Falcon des Nutzers: Laden im Spiel ergab mal einen
schwarzen Schirm, mal Grafikkonfetti; mit `MUSIK.INF` = `AUS` ging es.
Weiterspielen im Startmenü ging immer. Korrektur in `MAIN.S`
(`Restart_game`), auf dem Falcon geprüft (T14, mit Samples im DSP).*

**Ursache.** Thalions `Load_game` (`ACTIONS.S`) springt nach
`Restart_game`, und das gibt mit `Kill_all_memory` allen Speicher frei,
auch das laufende Musikstück. Der Spieler lief aber weiter, aus dem
freigegebenen Block, und das Laden des Spielstands legte Karten, Grafik
und Puffer genau dorthin. Dazu überdauern Thalions `Loaded_music`,
`Current_music` und `Current_song` den Neustart, denn sie liegen in
`HULL/VARIOUS.S`, nicht in `Game_data` (das `Init_program` löscht, samt
`Music_handle`). Wäre auf der neuen Karte dasselbe Stück dran, hielte
`Set_music` es für geladen und täte nichts.

Beim Start aus dem Menü spielt noch nichts; darum ging das immer. Vor dem
Einmischen der Musik (2026-10-08) gab es keinen Spieler, der hätte stören
können.

**Korrektur.** `Restart_game` ruft vor `Cache_verwerfen` und
`Kill_all_memory` Thalions `Set_music` mit `d0 = 0`, Thalions eigenen Weg,
die Musik auszuschalten: DMACON aus, `Music_stop`, Block frei,
`Music_handle` und `Loaded_music` leer. Unser Mischer übernimmt DMACON im
nächsten Takt vor dem Lesen der Samples (`mk_takt`), auf dem DSP-Weg
ebenso (`md_vbl` → `md_stueck` → `mk_takt`); der DSP hält nur fertig
Gemischtes, und Thalions Takt bricht nach `Music_stop` sofort ab (Musik-
Sitzung, aus dem Code gelesen; gilt auch für Samples im DSP). Danach lädt
`Set_map_music` das Stück neu. Beim ersten Start ist `Music_handle` 0,
dann tut der Aufruf nichts. Dasselbe gilt für den Neustart aus
`Out_of_memory`.

Wer im Original die Musik vor dem Neustart anhielt, steht in `AM2_CPU`
und ist nicht nachgelesen. *(Gruppe A: ein fehlender Aufruf, kein
fehlender Name.)*

## 274. Decrypting and unpacking are Thalion's; an odd last byte was wrong

*2026-10-21, map change on the STE too slow (user). Hatari profile,
the whole game data checked on the host.*

**Where Thalion's code is.** The decrypting loop is in the released source:
`Crypt_block` in `HULL/VARIOUS.S`, which we assemble anyway. The unpacker is
`Decompress` in `AM2_CPU` (0:$26124; four `jsr`, one from the game code,
three from the file loader behind `cmpi.l #$014C4F42`). Its loop behind
the type check (`cmpi.b #6`), 0:$261E4–$2621E, is pure memory code and
now comes in at build time as `Lob_core` (`am2cpu_code.py`). Our
`JH_decrypt` and `LOB_decompress` in `FILES_SUP.S` keep their contracts and
only call the two.

**The odd byte.** `Crypt_block` makes the length even (its header says so):
`(d7+1)>>1` words. An odd last byte is XORed with the high byte of the next
key, and the byte behind the block is touched too. `tools/ambtool.py`, and
our `JH_decrypt` after it, left the last byte as it was. Over all game data:
210 of 1755 encrypted parts have an odd length, all in `?Map_data.amb` (192,
the packed stream behind the AMNP head) and `?Map_texts.amb` (18). With
Thalion's reading every map text ends in a space (32) and the packed maps
mostly in 1; with ours they ended in arbitrary bytes. In 184 of the 192
maps the unpacked result differed in the last 1–6 bytes: zeros with
Thalion's reading, $D9/$DA and the like with ours. No save game has an odd
length (70 parts checked), so old save games still load.

Our wrapper hands `Crypt_block` the whole words only and XORs the last byte
with the high byte of the key `Crypt_block` returns: Thalion's result,
without writing behind the block. `ambtool.py` reads it the same way now.

**The end of the unpacker.** `Lob_core` compares with the end only after a
literal or a whole back reference, so a stream that ended inside a back
reference would write up to 17 bytes too far. A Python copy of exactly
these instructions over all 1641 LOB streams of the game data: every
stream ends exactly at its size, and the result equals `ambtool.py`. Our
wrapper skips size 0, where the loop would still read one token.

**Gain** (Hatari, STE 8 MHz, `Init_map` inclusive): 3D house in
Spannenberg 74.7 → 61.5 M cycles, the cellar 54.2 → 43.9 M; unpacking
about 2.2×, decrypting 1.7× faster. *(Rule: look for Thalion's routine
before writing one; finding 194.)*

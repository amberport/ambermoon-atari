# Das Datenmodell

Ambermoon ist datengetrieben: der Spielzustand steht nicht im Code, sondern
in Bitfeldern des Spielstands, und die Kartendaten sagen, welche Bits
gelesen und gesetzt werden. Die Engine führt das nur aus. Wer das
nachbaut, muss diese Felder nachbauen — sonst laufen Ereignisse mehrfach,
Türen sind immer verschlossen und Tote stehen wieder auf.

## Die Bitfelder

Sie liegen alle im Spielstand, deklariert in `MAIN.S` ab `Party_data:`, und
werden über eine einzige Routine angesprochen: `Access_bit_array` in
`MAIN.S`. Deren Tabelle nennt Größe und Ort:

| Nr. | Feld | Größe | Bedeutung |
|---|---|---|---|
| 0 | `Quest` | 1024 Byte | gelöste Aufgaben |
| 1 | `Chest_open` | 32 Byte | geöffnete Truhen |
| 2 | `Door_open` | 32 Byte | geöffnete Türen |
| 3 | `CD` | 4096 Byte | entfernte Charaktere |
| 4 | `Event` | 8192 Byte | ausgeführte Ereignisketten |
| 5 | `WD` | 128 Byte | bekannte Wörter |
| 6 | `New_words` | 128 Byte | neu gelernte Wörter |
| 7 | `Goto_points` | 32 Byte | bekannte Reiseziele |

`Access_bit_array` nimmt in d0 die Bitnummer, in d1 die Feldnummer und in d2
den Vorgang: 0 löschen, 1 setzen, 2 umschalten, 3 abfragen.

## Wie ein Ereignis sich selbst abhakt

`Event_handler` prüft vor dem Ausführen einer Kette, ob sie schon gelaufen
ist — `Check_event_save_status`. Die Bitnummer errechnet sich als

    (Kartennummer - 1) * Events_per_map + Kettennummer - 1

mit `Events_per_map = 64` aus `GAME_OFF.S`. Gesetzt wird das Bit nicht
automatisch, sondern von einem Ereignis vom Typ 14 (`Modify`), das dafür in
der Kette steht.

**Nachgerechnet an Karte 258.** Auf dem Startfeld (2,15) liegt Kette 3.
Ihre Ereignisse:

    Ereignis 2  Typ  4  Show_pictxt   Bild 2, Text 1     weiter -> 3
    Ereignis 3  Typ 14  Modify        01 01 00 00 00 40 42 00 00

Das zweite entschlüsselt sich so:

| Feld | Wert | Bedeutung |
|---|---|---|
| `Event_b1` | 1 | Art: `Event`-Bitfeld |
| `Event_b2` | 1 | Vorgang: setzen |
| `Event_w6` | 16450 | Bitnummer |

Und 16450 ist genau `(258-1) * 64 + 3 - 1` — die Bitnummer der eigenen
Kette. **Die Kette zeigt den Text und hakt sich danach selbst ab.** Beim
nächsten Betreten überspringt `Event_handler` sie.

## Abfragen und Ändern

Zwei Ereignistypen greifen auf die Felder zu, beide mit derselben Tabelle
von Zielen:

- **Typ 13, `Query`** — fragt ab. Ist die Antwort falsch, springt die Kette
  zu `Event_w8` statt zum nächsten Ereignis: eine Verzweigung in den Daten.
- **Typ 14, `Modify`** — ändert. `Event_b1` wählt das Ziel, `Event_b2` den
  Vorgang, `Event_w6` die Bitnummer.

Die Ziele, aus den Sprungtabellen in `EVENTS.S`:

| `Event_b1` | Ziel | | `Event_b1` | Ziel |
|---|---|---|---|---|
| 0 | Quest | | 11 | Licht (nur Abfrage) |
| 1 | Event | | 12 | Blickrichtung |
| 2 | Tür | | 13 | Bedingung |
| 3 | Truhe | | 14 | berührt (nur Abfrage) |
| 4 | CD — Charakter entfernt | | 15 | Wort gesprochen (nur Abfrage) |
| 5 | Gruppe (nur Abfrage) | | 16 | Fremdenzahl (nur Abfrage) |
| 6 | mitgeführter Gegenstand | | 17 | Schweben (nur Abfrage) |
| 7 | benutzter Gegenstand (nur Abfrage) | | 18 | Gold |
| 8 | bekannte Wörter | | 19 | Nahrung |
| 9 | Erfolg (nur Abfrage) | | 20 | gesehen (nur Abfrage) |
| 10 | interne Merker | | | |

## Was daraus folgt

Der Großvater verschwindet nicht, weil eine Routine das entscheidet, sondern
weil irgendwo ein Ereignis vom Typ 14 mit `Event_b1` = 4 sein CD-Bit setzt.
Bis dahin baut `Init_persons_2D` ihn bei jedem Kartenaufbau wieder auf. Die
Abhängigkeit „erst nach dem Ereignis im Keller" steht also in den
Kartendaten des Kellers, nicht im Code.

Für die Engine heißt das: Ohne die Bitfelder und ohne Typ 13 und 14 bleibt
jede Ereignislogik falsch, egal wie gut die einzelnen Ereignistypen
umgesetzt sind. Sie sind kein Beiwerk, sondern der Kern.

## Stand hier

Umgesetzt sind Typ 1 (Kartenausgang) und Typ 4 (Show_pictxt), beide ohne
Bitfelder. Deshalb läuft der Anfangstext bei jedem Betreten des Feldes neu,
statt nur einmal.

Als nächstes gebraucht:

1. Die Bitfelder als Speicherbereich, mit `Access_bit_array` als einziger
   Zugriffsroutine — wie im Original.
2. `Check_event_save_status` in `Event_handler`, damit erledigte Ketten
   übersprungen werden.
3. Typ 14 (`Modify`), zunächst nur für die Bitfelder.
4. Typ 13 (`Query`) mit der Verzweigung über `Event_w8`.
5. Die Kette wirklich abarbeiten: bisher wird nur das erste Ereignis
   angesehen, nicht `next` verfolgt.

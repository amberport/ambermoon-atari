# Prüfwerkzeuge

Dieses Kapitel beschreibt, womit in diesem Projekt geprüft wird. Der Grund
für den Aufwand: Ein selbst gerendertes Bild kann plausibel aussehen und
trotzdem falsch sein. Jede Behauptung über ein Datenformat braucht deshalb
eine Quelle, die nicht aus derselben Umrechnung stammt wie das Ergebnis.

Und jedes Prüfmittel beantwortet nur die Frage, die es stellt. Zwei
Erkenntnisse dazu, beide teuer bezahlt: Erkenntnis 52 — ein Bildvergleich
fand nichts, weil der Schaden auf der Konsole lag. Erkenntnis 53 — eine
Prüfung meldete nichts, weil der Filter der Auswertung danebengriff.
**Ein Werkzeug, das schweigt, ist erst dann eine Aussage, wenn man es
gegen einen bekannten Fehler gehalten hat.**

## `tools/ussref.py` — Amiga-Speicherauszüge als Referenz

Ein laufender Amiga ist die einzige solche Quelle. Die Speicherauszüge von
FS-UAE und WinUAE (`.uss`) enthalten den Bildspeicher einer echten Sitzung;
was dort steht, ist per Definition richtig.

Der Aufbau: Blöcke mit 4 Byte Name, 4 Byte Größe, 4 Byte Flags. Ist Bit 0
der Flags gesetzt, sind die Daten zlib-gepackt und es steht ein u32 mit der
entpackten Größe davor. Gebraucht werden `CRAM` (Chip-RAM), `FRAM`
(Fast-RAM) und `AGAC` (Farbregister).

| Funktion | Aufgabe |
|---|---|
| `read_chunks` | Blöcke holen, zlib entpacken |
| `find_bitplanes` | Bitplane-Zeiger aus der Copperliste |
| `decode_screen` | Zeilenverschachtelter Bildspeicher → Farbindizes |
| `palette` | Farbregister aus `AGAC` |
| `screen_png` | Kontrollbild schreiben |
| `identify_map` | geladene Karte anhand der Kacheldaten bestimmen |

### Drei Entscheidungen, die nicht offensichtlich sind

**Blöcke werden gesucht, nicht durchlaufen.** Blocklängen und Ausrichtungen
unterscheiden sich zwischen Emulatorversionen; ein unerwarteter Block wirft
sequenzielles Lesen aus dem Tritt. Deshalb gezielte Namenssuche mit
Plausibilitätsprüfung über die angegebene Länge.

**Die Bitplane-Zeiger kommen aus der Copperliste, nicht aus dem
Registerblock.** Der Amiga erhöht die Register während der Bildausgabe; am
Ende des Bildes zeigen sie hinter den Bildspeicher. Verlässlich ist nur die
Copperliste, die sie in jedem Durchlauf neu setzt. Gesucht wird die Stelle,
an der fünf aufeinanderfolgende `move`-Befehle die Register `$E0` bis `$F2`
beschreiben.

**Beim Kartenabgleich reicht eine kurze Probe nicht.** Weltkarten bestehen
über weite Strecken aus derselben Wasserkachel — ein 48-Byte-Ausschnitt
trifft auf dutzende Karten zu. Also kurz vorfiltern, dann den gesamten
Kacheldatenblock prüfen.

`find_bitplanes` liefert eine Liste von Fundstellen, nicht eine Adresse; die
erste ist bisher immer die richtige gewesen, aber die Schleife über alle
Treffer kostet nichts und schützt vor der Annahme.

### Der Mauszeiger — jetzt als feste Funktion

Der Zeiger steht **nicht** im Bildspeicher. Auf dem Amiga ist er ein
Hardware-Sprite und liegt neben den Bitplanes.

| Funktion | Aufgabe |
|---|---|
| `find_sprites` | Sprite-Zeiger `SPR0PT`/`SPR1PT` aus der Copperliste |
| `sprite_image` | zwei verkettete Sprites → Indizes, Größe, Bildschirmlage |
| `sprite_table` | Indizes als Hexzeilen, wie der Konverter sie führt |

So sind der normale Pfeil und das Zielkreuz gewonnen worden (Erkenntnis 20,
43 und 56).

**Die Kontrollwörter sind nicht offensichtlich aufgeteilt** — `VSTART`
Bit 8 steht in `SPRxCTL` Bit 2, nicht Bit 0. Wer das verwechselt, bekommt
Höhen wie −240 heraus; das fällt auf. Bei der *Stelle* fiele es nicht auf.
Die Aufteilung steht deshalb als Kommentar in der Funktion.

Ein Auszug enthält mehrere Copperlisten — die des Spiels liegt neben der mit
den Bitplane-Zeigern.

## `tools/hatari/teste.sh` — Vorabtest im Emulator

Lässt das Gebaute als Falcon030 laufen und legt Bildschirmabzüge ab.
Fensterlos, beendet sich selbst, rund sechzehn Sekunden je Lauf.

    sh tools/hatari/teste.sh
    sh tools/hatari/teste.sh -v 800,2000,6000
    sh tools/hatari/teste.sh -p FANTASY.TOS -l intro

Umgesetzt über Hataris Debugger: ein bedingter Haltepunkt auf `VBL` lädt an
der Marke eine weitere Kommandodatei nach, die den Abzug macht und den
nächsten Haltepunkt setzt. Einzelheiten in `tools/hatari/LIESMICH.txt`.

**Das Skript schreibt auch die `Cconws`-Ausgaben mit** (`--conout 2`). Das
ist mehr als Bequemlichkeit: bei der Umstellung auf vasm war das Bild
byteidentisch und die Meldungen trotzdem still kaputt — aufgefallen ist es
nur daran, dass der Lauf nichts mehr auf die Konsole schrieb (Erkenntnis 52).

## `tools/register_pruefen.py` — beschädigt eine Routine Register?

Sucht Routinen, die ein Register beschreiben, das ihre `movem`-Liste am
Anfang nicht sichert. Läuft bei jedem Bau mit.

Diese Fehlerklasse ist von außen kaum zu erkennen: Der Aufrufer verliert
einen Wert, den er für sicher hielt, und der Schaden zeigt sich woanders.
Ein einziger Hardwaretest hat zwei davon geliefert (Erkenntnis 54) —
`Update_mouse` beschädigte den Zähler einer Warteschleife und ließ das
Programm achtzehn Minuten laufen, `Resolve_tile` den Listenzeiger der
Charakterschleife.

**Routinen ohne `movem` am Anfang kann es nicht prüfen** — es weiß dann
nicht, was gesichert sein sollte. Sie werden am Ende aufgezählt, damit sie
wenigstens sichtbar sind. Genau eine davon hat einen Fehler gekostet:
`Get_entry` benutzt `d2` und sichert nichts (Erkenntnis 67).

**Rückgabewerte sehen genauso aus wie Beschädigungen.** Eine Routine, die
ihr Ergebnis in `d0` liefert, steht zwangsläufig in der Liste; die bekannten
stehen deshalb als Ausnahmen im Werkzeug. Die Ausgabe ist eine Liste zum
Durchsehen, kein Urteil — und jede neue Rückgabe gehört dort eingetragen.

## `tools/trap_pruefen.py` — ruft unser Code TOS nackt?

Seit 2026-10-02 (Erkenntnis 270). Läuft bei jedem Bau mit und bricht ab.

GEMDOS, BIOS und XBIOS dürfen d0–d2/a0–a2 zerstören. Unser Code ruft TOS
darum nur über die Makros `Gemdos`, `Bios` und `Xbios` (`FALCON_OFF.S`), die
d1–d2/a0–a2 retten. Das Werkzeug sucht in `engine/src` jeden nackten
`trap #1/#13/#14` außerhalb dieser Makros. Thalions Quelltext ruft TOS
nicht und liegt nicht in `engine/src`.

**Warum ein Verbot und kein Suchlauf nach gefährdeten Registern:** Ein
solcher Suchlauf folgt den Sprüngen nicht. Die Stelle, die auf dem Falcon
abstürzte (`Speicher_holen`), lag hinter einem `bne` und wäre ihm entgangen.
Gegen einen bekannten Fehler gehalten: Eine Datei mit nacktem `trap #1`
bricht den Bau ab.

## `tools/platzhalter_karte.py` — welcher Weg führt auf einen Platzhalter?

Seit 2026-09-27. Läuft bei jedem Bau mit und schreibt
`build/platzhalter.txt`; auf der Konsole steht die Zusammenfassung.

**Wozu.** Ohne Karte fällt ein Platzhalter erst im Hardwaretest auf („Knopf
geht nicht — war das ein Platzhalter?“). Mit ihr steht vorher fest, welche
Wege auf einen führen. **Was dann trotzdem nicht geht und nicht auf der
Liste steht, ist ein echter Fehler.**

Das Werkzeug liest die Dateien, die `engine.s` und `spiel.s` einbinden, und
baut einen Verweisgraphen: jede globale Marke ein Knoten, jeder Name in
ihrem Rumpf eine Kante (auch `dc.l` in Moduldeskriptoren und
Sprungtabellen), dazu das Durchfallen einer Routine in die nächste. Die
Makros aus `vorspann.i` setzt es eine Stufe tief ein (`Push Module,Eye_Mod`).

**Sorte** — woher das Echte kommt, und damit der Weg:

| Sorte | Herkunft | Weg |
|---|---|---|
| A | in Thalions Quelltext, Datei noch nicht eingebunden | die Datei einbinden; kein Einzelfall |
| B | nicht im Quelltext, Routine oder Mauszeiger | Bibliotheksschicht (AM2_CPU) |
| C | nicht im Quelltext, Daten (Texte, Grafik) | Ladebrücke (Leitziel 2) |

Die Trennung B/C ist eine Näherung über die Art des Platzhalters.

**Gefährlich** (mit `!`) ist ein Platzhalter, der still falsch antwortet:
Thalion wertet nach dem Aufruf Flags oder ein Register aus („Rückgabe“),
springt mit `jmp` hinein („Endsprung“: die Antwort geht an den Aufrufer des
Aufrufers), oder es ist ein Nullmodul. „Register?“ heißt: der nächste Befehl
liest ein Register — das kann ebenso ein bewahrter eigener Wert sein; wurde
das Register kurz vor dem Aufruf geladen, sagt der Eintrag es dazu.

Als Platzhalter zählt auch eine Marke in unseren übrigen Dateien, deren
Rumpf nur `rts` ist und die Thalions Code anspricht („verdeckt“, etwa
`Exit_map`). Was endgültig leer ist, weil es die richtige Übersetzung ist
(`Free_pointer`, `Wait_4_fade`), steht in `ENDGUELTIG_LEER`.

**Reichweite vor einem Test:**

    python3 tools/platzhalter_karte.py --von Map_exit --ohne Teleport,End_seq
    python3 tools/platzhalter_karte.py --wer Seek_transport_HERE

Sie ist eine **Obermenge**: jede Tabelle zählt ganz, auch Zweige, die der
Spielzustand nie nimmt. Der ausgegebene Weg zeigt, warum ein Platzhalter
erreichbar ist; ob der Zweig genommen wird, entscheidet man dort. Mit
`--ohne` schneidet man Zweige ab, die der Test nicht betritt.

**Was es nicht sieht:** Bedingungen (`IFD`), berechnete Sprünge
(`jsr (a0)` über ein Register, das nicht aus einer Tabelle im Rumpf kommt),
Makros außerhalb von `vorspann.i`.

**Schreiber fehlt** (`--schreiber`, auch am Ende von `build/platzhalter.txt`):
die Fehlersorte, die keine Platzhalterliste zeigt. Eine Variable Thalions
steht im Bau (meist in `MAIN.S`), der eingebundene Code liest sie, aber
*geschrieben* wird sie nur in einer Datei, die noch fehlt. Bau und Linker
sind zufrieden, der Wert bleibt null. Anlass (2026-09-27): Auf der
Weltkarte 157 löste die Haustür nicht aus, weil `Find_event` den
Wildnisweg nimmt und `Quad_index`, `Quad_map` und `Submap_width` liest.
Die setzt nur `MAP/2D_WILD.S` (und `Init_world` in `MAP/MAP.S`).
Als geschrieben zählt nur ein Name im Ziel eines Befehls. Über einen
Zeiger geschriebene Blöcke (`Current_world` per `move.w (a0)+,(a1)+`)
sieht die Probe nicht: `Quad_index` meldet sie, `Submap_width` nicht.

## `tools/vollprobe.py` — die ganze Bibliothek, die Thalion nie freigab

Seit 2026-09-27, läuft bei jedem Bau mit, schreibt `build/vollprobe.txt`.

Übersetzt **alle 38 Dateien Thalions** (ohne `FAIRY.S` und `GAME_OFF.S`,
das vorn steht) in zwei Einheiten wie `spiel.s`, mit unserer `vorspann.i`.
Was beide zusammen brauchen und keine definiert, ist die vollständige
Schnittstelle zu `AM2_CPU` und zu Thalions Datendateien: am 2026-09-27
**293 Namen**. Jeder wird gegen unseren Bau gehalten: *echt*,
*Platzhalter* (in einer `*_STUBS.S`, seit Stufe (c) nur noch
`AM2_CPU_STUBS.S`) oder *fehlt*. Das ist die Ziellinie
von Leitziel 1.

Übersetzt die Probe nicht, steht `ACHTUNG` da: dann passt `vorspann.i` nicht
mehr zu Thalions Quelltext, und das träfe jede Datei, die noch hereinkommt.
Gemeldet werden nur Fehler und Warnung 2028; die übrigen Warnungen hat der
Normalbau ebenso.

Was die Probe **nicht** sagt: ob ein echter Name seinen Vertrag erfüllt.
Der Linker prüft nur, dass es ihn gibt (CLAUDE.md, Fallen).

## `tools/am2cpu_lesen.py` — was tut Thalions Bibliothek?

Zerlegt `AM2_CPU` (Amiga-Hunks samt Relokationen) und disassembliert eine
Routine mit einem m68k-`objdump`; an jeden verschobenen Operanden schreibt
es Hunk, Versatz und, wo belegt, den Namen (Tabelle `NAMEN`, jeder Eintrag
mit Beleg). `dis`, `wer` (wer springt hin), `suche` (Bytemuster aus
Thalions Code), `daten`.

**Sagt aus:** den Vertrag einer Bibliotheksroutine: Register, Variablen,
Pixelformat, Rückgabe (Erkenntnis 194).
**Sagt nicht aus:** wie unsere Fassung aussehen soll. Das Werkzeug liest
nur. Das Ende einer Routine errät `dis` (erstes `rts` ohne Sprung darüber);
bei Zweifel `--bis` oder `-n` angeben. Die Ziele der Blitterfassungen sind
für uns belanglos, die CPU-Fassungen zählen.

**Falle beim Lesen:** objdump schreibt einen Indexversatz ohne `0x`, aber
**hexadezimal**: `%a4@(20,%d0:w)` ist `$20`, nicht 20. Im Zweifel das
Erweiterungswort in den Rohbytes lesen.

## `tools/am2cpu_code.py` — Thalions Speicherroutinen, beim Bau

Zieht die Stücke in `STUECKE` aus `AM2_CPU` und schreibt sie nach
`build/am2cpu_code.i`: Befehle als `dc.w` mit der objdump-Lesart als
Kommentar, Relokationen als `dc.l Name`, die internen Variablen als BSS-Block
in Originalanordnung. Warum und wie zurück: docs/02 A7.

**Sagt aus:** Jede Relokation hat einen Namen. Kein Sprung und kein
PC-relativer Zugriff verlässt sein Stück. Es gibt keine absolute Adresse
ohne Relokation (Amiga-Hardware). Jeder Befehl ist ein 68000-Befehl, kein
Index ist skaliert. Jedes Stück endet mit `rts`/`jmp`/`bra`, Tabellen sind
angegeben. Jede Prüfung wurde an einem absichtlich falschen Stück als
wirksam gesehen (2026-09-28).
**Sagt nicht aus:** ob das Stück auf unserer Seite richtig bedient wird.
Registervertrag, Pufferformat und die Werte in Thalions Variablen prüft es
nicht. Ob ein Name in `NAMEN` stimmt, weiß es nicht; dafür steht dort der
Beleg. Der Registerprüfer sieht `build/` nicht.

## `tools/vars_pruefen.py` — liegen zwei Variablen auf demselben Platz?

> **2026-09-05:** Der Prüfer meldete drei Überlappungen, alle falsch —
> `CI_H`, `BTN_H` und `PROMPT_QUIT` sind Konstanten, keine Variablenplätze.
> Er hat dafür seit jeher ein Ausschlussmuster, `KEINE_VARIABLE`, und
> **fragte es in der Schleife nie**. Auffallen konnte das nicht, solange
> keine Konstante zwischen den Variablen stand. Behoben.
>
> Ein Werkzeug, das seine eigene Ausnahme nicht kennt, ist schlimmer als
> keins: es meldet Fehler, wo keine sind, und man gewöhnt sich an das
> Wegsehen.


Die Variablen sind Versätze auf `a5`, von Hand vergeben, und die Liste ist
nach Themen geordnet, nicht nach Zahlen. Wer hinten anhängt, landet mitten in
einem belegten Bereich — viermal geschehen, einmal davon auf `p_tos`, der
Adresse des TOS-Bildschirms (Erkenntnis 58).

Die Größen werden aus dem Namensvorsatz geschätzt: `p_` heißt vier Byte,
sonst zwei. Was davon abweicht, gehört als Ausnahme ins Werkzeug — sonst
bleibt eine Überlappung unentdeckt.

## `tools/archiv/pruefe_paar.py` — passen Programm und Daten zusammen?

> **Not in the build since stage (c) (2026-09-27)**: there are no scene
> files any more, Thalion's code reads the original data itself. Since
> 2026-10-29 in `tools/archiv/`, which is not part of the published
> repository.

Der Fehler ist zweimal vorgekommen und hat beide Male Stunden gekostet: Die
Engine liest einen Eintrag, den der Konverter inzwischen woanders ablegt.
Auf dem Bildschirm sieht das nicht nach falscher Datei aus, sondern nach
kaputter Karte, falscher Startposition und fehlenden Ereignissen.

Geprüft wird, was sich ohne Emulator prüfen lässt: gleiche Zahl von
Kopfeinträgen in allen Szenendateien, Startwerte, Charaktere und Truhen auf
ihren Plätzen, hinter dem Kopf eine echte 16×16-Kachel, und ob `FALCON/`
mit `build/` übereinstimmt.

**Wer einen Kopfeintrag einschiebt, muss drei Stellen mitziehen:** den
Konverter, `KOPF` in diesem Skript und die Eintragsnummer in `MAP.S`.

## `tools/build_all.sh` — alles zusammen bauen

Since 2026-10-15 `build_all.sh` runs `build_falcon.sh` and `build_st.sh`
(formerly `baue_alles.sh` and `baue_st.sh`); the shared part is
`build_common.sh`. Together they take the library data from `AM2_CPU`
(`am2cpu_auszug.py`, only at build time), build the engine for both
machines, copy programs and original files into `ATARI/` and then check by
themselves: `register_pruefen.py`, `vars_pruefen.py`, placeholders, the
full probe and a cross-check whether the source still goes through a
68000. (Bis Stufe (c) baute es auch Szenendateien und den
Truhenbildschirm.)

Zwei Gründe für das Skript:

**Ein neuer Kopfeintrag verschiebt die Kachelnummern in allen Karten.** Wer
nur eine neu baut, bekommt auf dem Gerät eine kaputte Küche zu sehen.

**`cp` mit mehreren Quellen lässt auf dem eingehängten Dateisystem
gelegentlich eine Datei aus** — Rückgabewert 0, keine Meldung, Zieldatei
unverändert. Deshalb eine Quelle je Aufruf und danach `cmp`.

Die Spieldaten gehören nicht ins Repository; `AMBER_DATEN` sagt, wo sie
liegen. Ebenso `AMBER_TOS` für das TOS-Abbild und `AMBER_URCODE` für
Thalions Quelltext.

## Der Emulator braucht länger, als man denkt

Fünfmal an einem Tag habe ich einen Hatari-Lauf für gescheitert erklärt,
und fünfmal lag es am Messaufbau (Erkenntnis 128):

1. Abzug im falschen Maßstab gelesen — Hatari schreibt 640×480, der Falcon
   zeigt 320×200. Marken bei x=8 gesucht, die bei x=16 lagen.
2. Konsolenausgabe **nach** `Open_screen` gesetzt; sie landet dann im
   Grafikbildschirm, nicht in der Konsole.
3. Präfix mit Leerzeichen gewählt — `teste.sh` filtert solche Zeilen weg.
4. und 5. schlicht zu wenig Geduld.

**Ein Lauf braucht drei bis fünf Minuten.** Und `timeout` auf `teste.sh`
beendet das Skript, nicht den Emulator darunter — was danach als „hängt
noch" aussieht, ist ein verwaister Prozess.

Der Abzug erscheint deutlich **vor** der Zusammenfassung: `teste.sh` gibt
sie erst aus, wenn Hatari sich beendet hat. Wer auf die Textausgabe wartet,
wartet länger als nötig; wer auf die PNG-Datei wartet, hat das Ergebnis.

## Konsolenausgabe als Messwerkzeug

Für alles, was kein Bild ist, ist `Cconws` das schärfere Werkzeug — die
Ausgabe steht als Text im Protokoll statt als Pixel im Abzug. Bedingungen:
**vor** `Open_screen` ausgeben, und die Zeile darf nicht mit einem
Leerzeichen beginnen.

So geprüft wurden unter anderem der Speicherverwalter, die Bereichsstapel,
`Find_object` (mit Thalions `Hex_convert` für die Ausgabe) und die
Zahlenumwandlung.

## `tools/archiv/originalcode/` — was vom Original übersetzbar ist

`uebersetzbarkeit.sh` assembled Thalion's source with vasm and counted the
errors per file; `tools/originalcode/vorspann.i` supplies what the release
lacks: the library macros and the constants of the screen layout, split
into *proven* and *working assumption*. Last state: 2 errors in 50,723
lines. Since the build assembles all of Thalion's files, the script lies
in `tools/archiv/originalcode/` (2026-10-29, not published); `vorspann.i`
stays where it is, the build uses it.

**Beim Messen `-Fvobj`, nie `-Ftos`.** Geprüft wird eine einzelne
Übersetzungseinheit; wer ein fertig gebundenes Programm verlangt, macht
jeden Verweis auf eine andere Datei zum Fehler. `PLACES.S` meldete so 765
statt null (Erkenntnis 50).

`nach_vasm.py` (now `tools/archiv/originalcode/` as well) brought the
engine from GNU as to Motorola syntax. It was kept as a script rather than
handwork, so that the conversion can be followed and the diff stays
readable.

## `Save_screen` in `DIAGNOST.S` — Abzug vom Gerät

Schreibt 64000 Byte als `SCREEN.RAW`, unverändert. Damit lässt sich der
Bildschirm des Falcon Punkt für Punkt gegen einen Amiga-Abzug halten.

Daneben steht **`Save_phys_screen`**, das dasselbe vom *sichtbaren*
Bildschirm nach `SCREEN2.RAW` schreibt. `p_buf` zeigt, was gezeichnet wurde,
`p_scr`, was tatsächlich angezeigt wird — sind die beiden verschieden, liegt
der Fehler im Kopieren und nicht im Zeichnen. Die Unterscheidung hat schon
zwei Fehler aufgeklärt und einen ausgeschlossen.

**Vorsicht beim Zusammenspiel mit dem Tastenskript:** Dessen `S` ruft
ebenfalls `Save_screen` und überschreibt damit die Abzüge einer Diagnose, die
im selben Lauf schreibt. Drei Messungen sind so verdorben worden, und alle
drei sahen aus wie Befunde (Erkenntnis 61). Wer beides braucht, nimmt das `S`
aus dem Skript.

## Hatari — und wo seine Aussage endet

**Der Emulator taugt für „stürzt es ab" und „stimmt das Bild".** Nicht für
Mauszeiger, Zeitverhalten und Bildschirmumschaltung. Ein Textbildschirm, der
dort korrekt erscheint und auf dem Gerät schwarz bleibt, hat vier Umbauten
in die falsche Richtung ausgelöst (Erkenntnis 49). Wer die Aussage des
Emulators überdehnt, sucht an der falschen Stelle.

Dazu kommt eine Grenze, die im Ablauf steckt und nicht im Emulator: **weiter
als bis zum ersten Textfenster kommt ein Lauf nicht**, weil niemand eine
Taste drückt. Bewegung, Ereignisse, Kartenwechsel, Blättern und Truhen sind
damit ungeprüft, solange es keinen Schalter für eine Prüffassung gibt.

## Zwei Fallen beim Vergleichen

**`cmp -s` meldet für eine fehlende Datei „verschieden".** Wer einen Abzug
gegen einen älteren hält und der Pfad stimmt nicht mehr, bekommt einen
Rückschritt gemeldet, den es nicht gibt. Vor dem Vergleich prüfen, dass beide
Dateien da sind.

**Ein Vergleichsbild altert.** Zwischen zwei Läufen liegen oft Änderungen, die
das Bild zu Recht verändern. Ein Unterschied ist erst dann ein Rückschritt,
wenn das Vergleichsbild vom Stand unmittelbar davor stammt.

## Die Methode, wenn nichts mehr passt

Nach zwei gescheiterten Anläufen ist der dritte Umbau der falsche Zug. Der
Kontrolltest, der sich bewährt hat:

1. Den unveränderten Stand aus dem Repo bauen und laufen lassen.
2. Läuft er, ist die Umgebung entlastet und die eigene Änderung überführt.
3. Einzeln wieder einbauen, bis es kippt.

Das hat einen Fehler in einem Anlauf gefunden, nachdem das Raten drei
gekostet hatte.

Und wenn ein Werkzeug schweigt: **erst prüfen, ob es zubeißt.** Einen
bekannten Fehler wieder einbauen und nachsehen, ob er gemeldet wird. Das
kostet eine Minute und hat an einem Tag zweimal ein falsches Ergebnis
verhindert.

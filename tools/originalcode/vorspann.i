;***************************************************************************
; vorspann.i -- was Thalions Quelltext braucht, um durch vasm zu gehen
;
; Der freigegebene Quelltext ist Devpac-Motorola-Syntax und laesst sich
; uebersetzen -- aber er bindet eine Datei ein, die nicht mitveroeffentlicht
; wurde.  Darin standen die Bibliotheksmakros und die Konstanten, die den
; Bildaufbau beschreiben.  Diese Datei baut sie nach.
;
; **Thalions Dateien selbst bleiben unveraendert.**  Alles, was fehlt, steht
; hier; keine Zeile des Originals wird angefasst.  Das ist Absicht: solange
; die Quelldateien Byte fuer Byte die des Originals sind, ist jeder Vergleich
; mit ihnen eindeutig, und ein spaeterer Nachschlag im Original findet die
; Stelle unveraendert wieder.
;
; Stand der Messung mit dieser Datei: **2 Fehler auf 50.723 Zeilen**,
; 38 von 40 Dateien gehen fehlerfrei durch.  Die beiden Reste sind keine
; Syntaxfragen mehr, sondern Eigenheiten des Originals -- siehe Erkenntnis 51.
;
; Nachpruefbar mit tools/originalcode/uebersetzbarkeit.sh
;***************************************************************************

;---------------------------------------------------------------------------
; Screen_depth -- die Bildtiefe, **so wie Thalion sie meint: fuenf.**
;
; Auf dem Amiga hatten Schirm und Daten fuenf Ebenen, und Thalions Code
; sagt Screen_depth fuer beides.  Bei uns fallen die zwei auseinander, und
; nur eine der beiden Bedeutungen laesst sich halten (Erkenntnis 191):
;
;   Aufbau der Daten   2D_MAP.S  mulu.w #Screen_depth*2,d0   Reisegrafik
;                      EVENTS.S  moveq.l #Screen_depth,d5    Ereignisbild
;                      DISPLAY.S, INVENTOR.S, AUTOMAPP.S, MINIMAP.S,
;                      EFFECTS.S, der Kampf, rsgfx in GAME_OFF.S
;   Schirmspeicher     WINDOWS.S mulu.w #16*2*Screen_depth,d0  Hintergrund
;                      HDOBS.S   mulu.w #Screen_depth,d0       Hintergrund
;
; Die erste Gruppe liest Originaldaten und muss fuenf sagen.  Die zweite
; legt Puffer an, die die Bibliothek fuellt -- und die Bibliothek darf dort
; ablegen, was sie will: Get_block sichert mit d5 = 5 die unteren fuenf
; Ebenen im Amiga-Format, Put_unmasked_block setzt die Farbbank der Zeile
; wieder dazu (Farbe = Bank + Wert, 0 bleibt 0).  Das ist verlustfrei,
; solange jede Zeichenroutine diese Regel einhaelt.
;
; Die originale Bibliothek rechnet selbst so: ihr Put_masked_silhouette
; beginnt mit "cmp.w #5,d5 / bgt raus" (Erkenntnis 129).
;
; Bis 2026-09-28 stand hier 8, und Display_2D_party sprang auf der
; Weltkarte beim ersten Richtungswechsel in fremde Daten: Put_masked_block2
; bekam Breite und Hoehe null und las ueber das RAM-Ende (Busfehler).
; Dazu hiess d5 = 8 bei uns "schon aufbereitete Daten" -- Ereignisbilder
; und Objektsymbole kamen so ungewandelt auf den Schirm.
;
; Die Tiefe **unseres** Schirms ist Schirm_ebenen (unten, bei den
; Bildmassen); FALCON_OFF.S nennt sie PLANES.
;---------------------------------------------------------------------------
Screen_depth	equ	5

; Data_depth -- ein zweiter Name fuer dasselbe, fuer unsere Bibliothek:
; dort sagt er deutlicher, dass die Originaldaten gemeint sind.
Data_depth	equ	Screen_depth

;---------------------------------------------------------------------------
; Icon_size -- ein Symbol in Byte, **in den Originaldaten**.  Belegt, nicht
; geraten: Object_icons hat 30080 Byte, das sind bei 160 Byte genau 188
; Symbole ohne Rest (siehe tools/ambchest.py).  16x16 Pixel zu fuenf Ebenen:
;     16/8 * Data_depth * 16  =  Data_depth * 32  =  160
; Jeder seiner Aufrufer rechnet damit die Lage eines Symbols in geladenen
; Daten aus ("mulu.w #Icon_size,d0" nach "Get Object_gfx_handle,a0").  Bis
; 2026-09-25 stand hier Screen_depth*32 = 256, und Load_object_graphics
; weitete die Symbole beim Laden auf acht Ebenen auf, damit das passte.
;---------------------------------------------------------------------------
Icon_size	equ	Data_depth*32

; ---------------------------------------------------------------------------
; Button_gfx_file -- **unsere Dateinummer**, nicht Thalions.
;
; Seine Aufzaehlung in GAME_OFF.S laeuft von Party_data_file bis
; Object_gfx_file und kennt Button_graphics nicht: im Original fuellt die
; nicht freigegebene Bibliothek Control_icons aus dieser Datei, und die
; Bibliothek liegt nicht als Quelltext vor (Erkenntnis 131).  Seine Datei
; bleibt unangetastet, die Nummer haengen wir hinten an -- die Namenstabelle
; in HULL/FILES_SUP.S waechst mit (DN_MAX).
; ---------------------------------------------------------------------------
Button_gfx_file	equ	45

; ---------------------------------------------------------------------------
; Text_file, Objects_file -- ebenfalls **unsere Nummern**.
;
; Die Meldungen (Prompts) und die Gegenstandstabelle (Object_data) stehen im
; Original als Marken in AM2_CPU, sein Code liest sie mit "lea Prompts,a0"
; und "lea Object_data+4,a1".  Die deutsche Fassung 1.20 traegt dieselben
; Bytes als eigene Dateien, Text.amb und Objects.amb.  Die Bibliothek laedt
; sie beim Start an die Marken (WORDS_SUP.S, INVENTOR_SUP.S).
; ---------------------------------------------------------------------------
Text_file	equ	46
Objects_file	equ	47

;---------------------------------------------------------------------------
; CA_data_size -- Groesse eines Eintrags in der Combat-CA-Liste.
;
; **Arbeitsannahme, nicht belegt.**  Der Wert wird erst gebraucht, wenn der
; Kampf ansteht, und der ist weit weg.  Bekannt ist: das erste Langwort ist
; null, wenn der Eintrag geloescht ist (tst.l (a0) in COMBAT/COMOBS.S), und
; Max_COMOBs ist 30.  Push_CA und Pop_CA gehoeren zur Bibliotheksschicht
; (docs/03).  Vor der ersten Kampfsitzung zu klaeren.
;---------------------------------------------------------------------------
CA_data_size	equ	16

;---------------------------------------------------------------------------
; Default_safety_factor -- Sicherheitszugabe fuer das Entpacken an Ort und
; Stelle.  Show_layout (DISPLAY.S) fordert damit seinen Puffer an:
;
;     move.l #(199-Middle_Y)*120+Default_safety_factor,d0
;     jsr Allocate_CHIP ... Copy_memory ... jsr Decompress
;
; **Ein Sofortwert, keine Speicherzelle.**  Als "ds.l 1" stand hier vorher
; die *Adresse* des Stubs im Ausdruck -- der Puffer waere mit einer
; Unsinnsgroesse angefordert worden.
;
; Wozu die Zugabe: Decompress entpackt vorwaerts *in denselben Puffer*.  Das
; geht nur, wenn der gepackte Block ans Ende des Puffers rueckt, damit der
; Schreibzeiger den Lesezeiger nie ueberholt.  Rechnerisch ist der Vorsprung
; (geschrieben minus gelesen) am Stromende am groessten und genau dann
; entpackte minus gepackte Groesse -- die Zugabe deckt die Raender ab
; (Kopfbytes, letzte angebrochene Achtergruppe, Ausrichtung).
;
; **Arbeitsannahme.**  Thalions Wert ist nicht ueberliefert; 256 ist reichlich
; und kostet nichts.  Wer ihn belegt, ersetzt ihn hier.
;---------------------------------------------------------------------------
Default_safety_factor	equ	256

;---------------------------------------------------------------------------
; Member_nrs -- Versatz im Party_data-Block: sechs Worte, die Nummern der
; Gruppenmitglieder (null = Platz frei).  MAIN.S baut daraus den Batch:
;
;     lea.l Member_nrs,a1 / moveq.l #6-1,d7
;     .Loop: move.w (a1)+,d1 / beq .Next / move.w d1,(a0)+ / addq.w #1,d0
;     ... jsr Load_batch_of_subfiles
;
; Der Block steht in Thalions MAIN.S ab "Party_data:" als Folge von ds.-
; Deklarationen; der Wert hier ist deren Summe bis Member_nrs.  Gegengeprueft
; an der echten Datei: Initial/Party_data.sav traegt dort [1,0,0,0,0,0] --
; zum Spielbeginn ist nur Charakter 1 (THALION) dabei, und genau so sieht
; unsere Gruppe aus.
;---------------------------------------------------------------------------
MEMBER_NRS	equ	46

;---------------------------------------------------------------------------
; Cheat -- Thalions Entwicklerschalter, "ifne Cheat" an drei Stellen in
; EVENTS.S.  Aus.
;---------------------------------------------------------------------------
Cheat		equ	0

;---------------------------------------------------------------------------
; rseven -- Devpac: den RS-Zaehler auf gerade aufrunden.
;
; Hier stand lange ein leeres Makro, mit der Annahme, vasm richte rs.w und
; rs.l selbst aus.  **Das tut es nicht** (nachgemessen, Erkenntnis 180): nach
; einem ungeraden rs.b liegt das folgende rs.w ungerade.  Betroffen sind
; zwoelf Versaetze aus GAME_OFF.S (Trans_data_size 5 statt 6, Map_data 331
; statt 332, NPC_data 11 statt 12 ...), die nur Thalions MAIN.S benutzt --
; und mit ihnen der Aufbau von Thalions Party_data, also des Spielstands.
; __RS ist vasms RS-Zaehler.
;---------------------------------------------------------------------------
rseven		MACRO
		rs.b	__RS&1
		ENDM

;---------------------------------------------------------------------------
; LOCAL -- Devpac: den Gueltigkeitsbereich lokaler Marken hier beenden.
;
; Beide Assembler binden eine Marke wie .Loop an die zuletzt genannte globale
; Marke.  Devpac kann den Bereich zusaetzlich mitten in einer Routine
; abschliessen; vasm kennt das nicht, und dann kollidiert das zweite .Loop
; mit dem ersten.  Eine erzeugte globale Marke tut dasselbe -- \@ ist bei
; vasm die laufende Nummer des Makroaufrufs und damit eindeutig.
;
; Das allein raeumt 160 der 291 Fehler weg.
;---------------------------------------------------------------------------
LOCAL		MACRO
_lokal\@:
		ENDM

;---------------------------------------------------------------------------
; Get, Free, Push, Pop -- Thalions Bibliotheksmakros.
;
; **Hier stehen Attrappen.**  Sie machen den Quelltext uebersetzbar und sonst
; nichts.  Die richtigen Fassungen gehoeren in die Bibliotheksschicht; die
; Schnittstellen dazu sind in docs/03-Bibliotheksschicht.md rekonstruiert.
;
; Wichtigster Punkt von dort: **das Speichersystem arbeitet mit Handles,
; nicht mit Zeigern.**  Get nagelt ein Handle fest und liefert die Adresse,
; Free gibt es wieder frei.  Wer das mit rohen Zeigern nachbaut, bekommt die
; Spiellogik nicht zum Laufen.
;---------------------------------------------------------------------------
; **Handle ist ein Byte.**  Thalion fuehrt Speicher-Handles als .b ("OUT:
; d0 - Memory handle (.b)") und schreibt sie mit move.b.  Ein Handle aus dem
; Speicher darf darum NICHT als Langwort gelesen werden: big-endian legt das
; Byte ins hohe Byte, und Mem_eintrag maskiert das niedrige (and.w #$FF) ->
; Handle 0 -> falscher Zeiger.  (Fiel erst mit dem ersten aktiven
; "Get <Byte-Handle im Speicher>" auf: Display_body_object zeigte Grafikmuell.)
; move.b liest richtig -- aus Speicher (das Byte) wie aus Register (low byte).
; **Get darf d0 nicht verbrauchen.**  Seine Aufrufstellen rechnen damit
; weiter, und zwar mit dem Wert, der *vor* dem Get darin stand:
;
;     Display_object (DISPLAY.S):
;         Get Slotbase_handle,a2      ; d0 = Platznummer
;         add.l Slotbase_offset,a2
;         add.w Scroll_bar_result,d0
;         mulu.w #Object_packet_size,d0
;         add.l d0,a2
;
;     Display_body_object (DISPLAY.S), ACTIONS.S:1218, MAGIC.S und weitere
;     folgen demselben Muster.
;
; Unsere erste Fassung schrieb die Adresse nach d0 und liess sie dort stehen.
; Danach rechnete sein Code "Adresse mal sechs" auf den Satzzeiger, las
; Object_index aus dem Nichts, bekam null -- und zeichnete kein Symbol.  Auf
; dem Geraet: Rucksackplatz grau, Gegenstand unsichtbar, aber anklickbar
; (am Savestate des Nutzers nachgewiesen, Erkenntnis 164).
;
; Der Rueckgabewert ist \2, nicht d0; d0 zu retten kostet nichts.
;
; **Free darf d0 ebenso wenig verbrauchen** (Erkenntnis 186).  Thalions
; Find_event (EVENTS.S) liest die Kette der Kachel nach d0, gibt den
; Kartenblock frei und prueft erst dann:
;
;     move.b 1(a0,d5.w),d0
;     Free   d2
;     tst.w  d0              ; Any ?
;
; Unser Free liess die Handle-Nummer in d0 stehen.  Mapdata_handle war 3,
; also meldete Find_event auf jeder Kachel Kette 3 -- das Startereignis,
; laengst gelaufen.  Truhe, Tuer und Kartenausgang blieben stumm.  Dasselbe
; Muster ("Free ... / tst.w d0 ; Anything there ?") steht in DISPLAY.S und
; INVENTOR.S.
;
; **Das Argument darf d0 selbst sein**: "Get d0,a0" (EVENTS.S, Datachange)
; und "Free d0" (COMBAT/TACTIC.S).  Ein moveq #0,d0 davor loeschte es, und
; es hiesse Handle 0.  Darum steht dort nichts: Mem_eintrag (MEMORY.S)
; nimmt ohnehin nur das untere Byte.  Kuerzer muss es auch sein -- schon die
; gerettete d0 macht Free vier Bytes laenger, und Thalions bpl.s in
; Datachange (EVENTS.S) reicht knapp.
Get		MACRO
		move.l	d0,-(sp)
		IFNC	"\1","d0"
		moveq	#0,d0
		move.b	\1,d0
		ENDC
		jsr	Claim_pointer
		move.l	d0,\2
		move.l	(sp)+,d0
		ENDM

Free		MACRO
		move.l	d0,-(sp)
		IFNC	"\1","d0"
		moveq	#0,d0
		move.b	\1,d0
		ENDC
		jsr	Free_pointer
		move.l	(sp)+,d0
		ENDM

; Push und Pop nehmen die Art als ersten Wortteil des Routinennamens.  So
; benutzt das Original sie durchgehend:
;
;     Push	Module,OpenedChest_Mod
;     Push	PA,Status_PA
;     Pop	PA
;     Pop	Module
;
; Der Satz kommt in a0 -- Push_Module, Push_PA, Push_MA und Push_Tree
; erwarten ihn alle dort.  Hier standen bis eben Attrappen mit einem
; erfundenen "Push_module"; seit die Stapel wirklich da sind, kann das weg.
Push		MACRO
		lea	\2,a0
		jsr	Push_\1
		ENDM

Pop		MACRO
		jsr	Pop_\1
		ENDM

;***************************************************************************
; Ab hier: die Konstanten und Makros, die ausser den obigen noch fehlen.
;
; **Zwei Klassen, streng getrennt.**  Was belegt ist, steht mit Beleg da.
; Was Arbeitsannahme ist, steht als solche gekennzeichnet -- es macht den
; Quelltext uebersetzbar und sonst nichts.  Wer eine dieser Zahlen fuer den
; Betrieb braucht, muss sie vorher belegen.
;***************************************************************************

;===========================================================================
; BELEGT
;===========================================================================

;---------------------------------------------------------------------------
; Bildmasse.  Screen_width ist 320.
;
; Schirm_ebenen -- die Tiefe **unseres** Schirms: 8 beim Falcon, 4 beim
; STE.  Der Schalter fuers Zielsystem; FALCON_OFF.S uebernimmt ihn als
; PLANES.  Nicht Screen_depth, das meint Thalions Daten (oben).
;
; Bytes_per_line haengt daran, nicht an Screen_depth: Thalion legt damit
; Hilfsschirme an (CONTROLS.S, INVENTOR.S, COMBAT.S) und stellt Work_screen
; darauf um, und hinein zeichnet unsere Bibliothek im Schirmformat.
; COMOBS.S rechnet damit in einem solchen Schirm eine Zeile weiter.
;---------------------------------------------------------------------------
Screen_width	equ	320
;---------------------------------------------------------------------------
; **The machine switch** (library split phase 3, 2026-10-24).  The ST build
; (tools/build_st.sh) assembles with -DZIEL_ST=1: four planes, 16 colour
; registers (docs/12-ST-Port.md).  This block and the includes in
; engine/engine.s are the only places in the shared code that ask; what
; differs beyond that is in the machine parts (FALCON.S, FALCON_LIB.S,
; ST.S, ST_LIB.S) under neutral names.
;
; SCHIRM_RAND -- border lines above and below each screen for the screen
; shake (Vertical_screen_offset -3..+4, finding 200); they stay black.
; **ST: eight lines.**  The ST takes the video base only in steps of 256
; bytes (the low byte came with the STE).  8*160 = 1280 = 5*256, so
; Schirm_vorn and the second screen start on a 256 byte boundary.
;
; MACHINE_NAME -- the first line ENGINE.TOS / ENGINEST.TOS prints (MAIN.S).
;
; The hooks of the memory list (HULL/MEMORY.S).  The ST keeps recoloured
; copies of Thalion's 3D graphics (E12, ST_LIB.S); the Falcon has none,
; so its hooks are empty and cost nothing:
;   MEM_ADDRESS     d0.b = handle, a0 = its entry in memtab: d0.l = the
;                   address to hand out (the ST: the copy, if there is one).
;   MEM_FREE_HOOK   d0.b = handle: a copy of it goes.
;   MEM_KILL_HOOK   all copies go (Kill_unclaimed_memory).
; Each keeps every register except the stated d0.
;---------------------------------------------------------------------------
	IFD	ZIEL_ST
Schirm_ebenen	equ	4
SCHIRM_RAND	equ	8
MACHINE_NAME	macro
	dc.b	"Ambermoon ST"
	endm
MEM_ADDRESS	macro
	jsr	St_abschrift_zeiger
	endm
MEM_FREE_HOOK	macro
	jsr	St_abschrift_weg
	endm
MEM_KILL_HOOK	macro
	jsr	St_abschrift_alle_weg
	endm
	ELSE
Schirm_ebenen	equ	8
SCHIRM_RAND	equ	4
MACHINE_NAME	macro
	dc.b	"Ambermoon Falcon"
	endm
MEM_ADDRESS	macro
	move.l	MEM_ADR(a0),d0
	endm
MEM_FREE_HOOK	macro
	endm
MEM_KILL_HOOK	macro
	endm
	ENDC
Bytes_per_line	equ	Screen_width*Schirm_ebenen/8

;---------------------------------------------------------------------------
; Pal_size -- Farben je Palette **in den Daten**: 32, wie beim Amiga.
; Palettes.amb hat 49 Eintraege zu je 32 Farben (docs/04).
;
; Nicht 1<<Screen_depth.  Thalion nimmt Pal_size fuer Palettenpuffer
; (Current_pal, Combat_pal), fuer Kopien aus Palette_file und fuer die
; Tintenmaske -- ueberall ist die Palette der Daten gemeint, nicht die
; Farbregister der Hardware.  Die 256 Register des Falcon verteilt die
; Bibliothek als Farbbaenke (FADE_SUP.S), dafuer braucht es Pal_size nicht.
;
; **Mit 256 lief es schief** (Erkenntnis 185): "moveq.l #Pal_size-1,d6"
; (EVENTS.S, MAIN.S) wird zu moveq #-1, das dbra kopiert 65536 Worte, und
; ShowPicTxt_ModInit ueberschrieb 128 KB ab Batch -- samt Stapel.
; vasm only warns (2028); since then tools/build_engine.sh stops on it.
;---------------------------------------------------------------------------
Pal_size	equ	32

;---------------------------------------------------------------------------
; Zeichenmasse.  Nachgemessen an einem Amiga-Speicherauszug, Zeile
; "HALLO THALION." -- jedes Zeichen sitzt auf der vorhergesagten Spalte
; (tools/falcon_gfx.py).  Die Schrift ist nicht proportional.
;
;   Vorschub    6 Pixel  = Char_width+1    -> Char_width  = 5
;   Zeilenabstand 7      = Char_height+2   -> Char_height = 5
;
; Das Muster ist fuenf Byte hoch, also fuenf Zeilen -- Char_height stimmt
; damit unabhaengig ueberein (docs/04, Zeichensatz in AM2_CPU Hunk 13).
;---------------------------------------------------------------------------
Char_width	equ	5
Char_height	equ	5

;---------------------------------------------------------------------------
; FALSE -- Thalions Wahrheitswert.  st/sf setzen $FF beziehungsweise 0.
;---------------------------------------------------------------------------
FALSE		equ	0

;===========================================================================
; ARBEITSANNAHME -- nicht belegt, nur damit es uebersetzt
;===========================================================================

;--- Obergrenzen von Listen.  Nur Feldgroessen; falsche Werte fallen beim
;--- ersten Ueberlauf auf, nicht vorher.
Max_HDOBs	equ	16		; Hardware-Display-Objekte
Max_modules	equ	16		; Modulstapel
Max_trees	equ	16		; Objektbaeume

;---------------------------------------------------------------------------
; Der Aufbau eines Objekts -- HULL/OBJECT.S benutzt diese Namen, definiert
; sie aber nicht; sie lagen in der nicht freigegebenen Includedatei.
;
; **Abgeleitet, nicht geraten.**  Drei Stellen des Originals legen den
; Aufbau eindeutig fest:
;
;   1. Search_layer prueft der Reihe nach Obj_X1, Obj_X2, Obj_Y1, Obj_Y2 und
;      holt die Kennung mit "move.b 8(a0),d2" -- die Acht steht dort
;      woertlich, also vier Worte davor.
;   2. Ein echter Baum, InputNr_L1 in HULL/CONTROLS.S:
;           dc.w 0,0                 ; Kopf: Versatz X und Y
;           dc.w 0,143,0,63          ; Kanten
;           dc.b 1                   ; Kennung
;           even                     ; Fuellbyte
;           dc.l 0,InputNr_L2        ; Bruder, dann Kind
;   3. Open_window schreibt den Kopf vor dem Push:
;           move.w d0,(a0) / move.w d1,2(a0) / jsr Push_Tree
;      Ein Baum beginnt also mit zwei Worten Versatz, erst dann kommt das
;      erste Objekt -- Find_object zieht sie mit "sub.w (a0)+" ab.
;
; Am Rande: Default_Tree in HULL/OBJECT.S hat diesen Kopf **nicht**.  Seine
; ersten beiden Worte (0 und 319) werden dadurch als Versatz gelesen, und
; damit findet Find_object darin nie etwas.  Das ist eine Unstimmigkeit im
; Original; angefasst wird sie nicht.
;---------------------------------------------------------------------------
Obj_X1		equ	0
Obj_X2		equ	2
Obj_Y1		equ	4
Obj_Y2		equ	6
Obj_ID		equ	8
Obj_brother	equ	10
Obj_child	equ	14
Obj_data_size	equ	18
Max_windows	equ	8		; Fensterstapel
Max_PA		equ	8		; Print-Areas
Max_scroll_bars	equ	8
Max_input_length equ	32
Max_songs	equ	32
Max_batch	equ	64		; Stapel fuer 3D-Objekte

;--- Clip-Area (Zeichenbegrenzung).  Wie die Print-Area die ersten vier
;--- Worte: X1, X2, Y1, Y2 (belegt: Compass_CA 208,208+31,0,199 in DISPLAY.S;
;--- bis 2026-09-25 stand hier X1,Y1,X2,Y2, Erkenntnis 172).  HULL/EFFECTS.S liest damit die Raender, an denen
;--- fallende Objekte und Explosionspixel verschwinden.  Push_CA/Pop_CA (der
;--- Stapel dazu) fehlen noch; EFFECTS braucht nur die aktuelle Area.
CA_X1		equ	0
CA_X2		equ	2
CA_Y1		equ	4
CA_Y2		equ	6

;--- Feld im Speicherblock-Satz: aus welcher Unterdatei der Block stammt.
;--- Nur Relocate_music (Musik, stillgelegt) liest es; der Wert ist darum
;--- gleichgueltig, muss aber ein gueltiger Versatz sein.
Block_subfile_nr equ	10

;--- Strukturversaetze der Hardware-Display-Objekte (HDOB).  Das sind
;--- Bilder, die HULL/HDOBS.S jedes Bild neu an eine Stelle zeichnet und
;--- vorher den Hintergrund darunter sichert -- der getragene Gegenstand am
;--- Zeiger, die Textgespenster, der fliegende Adler.
;
;--- **Die Versaetze standen nie im freigegebenen Code** -- sie waren in der
;--- Bibliothek.  Hier sind sie aus fuenf ausgeschriebenen HDOB-Saetzen
;--- (Move_item_HDOB, Move_key_HDOB, Dissolve_HDOB, Ghost1/2_HDOB) und der
;--- Benutzung in HDOBS.S/INVENTOR.S/DISPLAY.S/ACTIONS.S abgeleitet:
;---
;---   Move_item_DisUpd:  move.w Mouse_X,(a0)+  ->  drawX = 0
;---                      move.w Mouse_Y,(a0)+  ->  drawY = 2
;---   Create_object_graphics baut 5*2*24 Byte  ->  Tiefe 5, Hoehe 24
;---   der Satz traegt dc.w 1,24,5             ->  Breite 4, Hoehe 6, Tiefe 8
;---   Get_block/Draw_HDOBs lesen offset als .l ->  offset = 12
;---   nur zwei Byte bleiben (gfx_handle, flag) ->  16, 17
;---   dcb.w 6,0 am Ende sind zwei Schirmbloecke -> screen1 = 18, screen2 = 24
;---
;--- Jeder Satz ist 30 Byte lang.  Ein Schirmblock (6 Byte) sichert den
;--- Hintergrund fuer je eine der beiden Bildschirmseiten des Amiga; wir
;--- haben eine Seite, der zweite Block bleibt ungenutzt (Screen_flag steht
;--- fest).
HDOB_drawX	equ	0		; .w  Zeichenort X
HDOB_drawY	equ	2		; .w  Zeichenort Y
HDOB_width	equ	4		; .w  Breite in 16-Punkt-Bloecken
HDOB_height	equ	6		; .w  Hoehe in Zeilen
HDOB_depth	equ	8		; .w  Ebenen (unser Put_masked_block2 egal)
HDOB_base_colour equ	10		; .w  Grundfarbe (dito)
HDOB_offset	equ	12		; .l  Zusatz auf die Grafikadresse
HDOB_gfx_handle	equ	16		; .b  Handle der Grafik, 0 = aus
HDOB_flag	equ	17		; .b  0 = maskiert, sonst Block
HDOB_screen1	equ	18		; erster Schirmblock
HDOB_screen2	equ	24		; zweiter Schirmblock
HDOB_data_size	equ	30
;--- Felder innerhalb eines Schirmblocks:
HDOB_bg_handle	equ	0		; .b  Handle des gesicherten Hintergrunds
HDOB_oldX	equ	2		; .w  wo er gesichert wurde
HDOB_oldY	equ	4		; .w
; Module_data_size -- **berichtigt.**  Hier stand 16, geraten.  Ein Modul
; des Originals hat zwei Byte (Merker, Kennung) und dreizehn Langworte
; (DisUpd, VblQ, ScrQ, Mev, Kev, ModInit, ModExit, DisInit, DisExit,
; RasterList, Mouse_ptr, PA, MA) -- nachzuzaehlen an Inv2_Mod in MODULES.S.
; Das sind 54 Byte; Reset_module_stack rechnet mit "Module_data_size/4",
; also muss der Wert durch vier teilbar sein: 56.
Module_data_size equ	56

;--- Die Eintraege eines Moduls, aus Push_Module und Init_module abgezaehlt.
;--- Zwei Byte (Merker, Kennung), dann zehn Langworte, dann drei.
Module_ID	equ	1
DisUpd_ptr	equ	2
VblQ_ptr	equ	6
ScrQ_ptr	equ	10
Mev_ptr		equ	14
Kev_ptr		equ	18
ModInit_ptr	equ	22
ModExit_ptr	equ	26
DisInit_ptr	equ	30
DisExit_ptr	equ	34
Raster_list_ptr	equ	38
Mouse_ptr	equ	42
PA_ptr		equ	46
MA_ptr		equ	50

;--- Merkerbits im ersten Byte eines Moduls.  Ein Local_mod liegt ueber dem
;--- Bildschirm darunter, statt ihn zu ersetzen; ein Global_mod ersetzt ihn.
;--- Welches Bit Thalion nimmt, steht nirgends geschrieben -- nur die beiden
;--- Namen kommen in den Deskriptoren vor.  Bit 0 ist unsere Wahl.
Local_mod_bit	equ	0
Local_mod	equ	1<<Local_mod_bit
Global_mod	equ	0

;--- Bildhoehe.  Middle_Y -- die Zeile, an der die Statusleiste endet --
;--- steht nicht hier: Thalions GAME_OFF.S definiert es selbst, gleich in
;--- Zeile 5, und zwar als 36.  Genau der Wert, den wir aus LAY_Y im
;--- Konverter abgeleitet hatten.
Screen_height	equ	200

;--- Die Betriebsarten von Set_fade, aus HULL/FADE.S abgelesen.
;--- Set_new setzt die Palette unmittelbar, die beiden anderen blenden.
Set_new		equ	0
Fade_out	equ	1
Start_fade_in	equ	2

;--- Bitnummern in Button_state.
;
; **Nicht mehr geraten, sondern festgelegt.**  Button_state ist seit der
; Umstellung auf absolute Variablen unsere Zelle: Mouse_int schreibt das
; Tastenbyte des IKBD hinein, und dort ist Bit 0 die rechte Taste.  Wer die
; Zahlen fuellt, bestimmt sie -- Thalions Code liest sie nur.
; Tastenbits im Button_state-Byte, wie Thalions Code sie liest
; (VARIOUS.S: "move.b Button_state / and.b #$11" -> Bit 0 und Bit 4).
Left_pressed	equ	0
Right_pressed	equ	4
;--- Die Flankenbits bildet Maus_vbl (HULL/LIBRARY.S) wie AM2_CPU 1.20
;--- (0:$238DA): gedrueckt = gehalten << 1, losgelassen = gehalten << 2
;--- (Erkenntnis 252).  Right_clicked ist "rechts eben gedrueckt"; belegt
;--- durch die einzige Stelle "btst #5,Button_state" in 1.20 (0:$26B2A,
;--- Display_text).  Bis 2026-09-28 stand hier Right_pressed, angenommen.
Right_clicked	equ	5
;--- Amiga_key ist ein Bit der Tastenkennung aus Read_key, nicht von
;--- Button_state.  Belegt in AM2_CPU 1.20, Hunk 0 $279E8 (Handle_input,
;--- MODULE_C.S): "jsr Read_key / tst.l d0 / beq / btst #28,d0 / beq /
;--- lea Diagnostics_list1,a1".  Bis 2026-09-29 stand hier 3, geraten: das
;--- ist ein Bit des ASCII-Zeichens, und alle Tasten mit gesetztem Bit 3
;--- (h-o, x-z, 8, 9, Return ...) gingen an die Diagnoseliste (Erkenntnis 257).
Amiga_key	equ	28

;--- Die Print-Area: Rand, Tinte, Schatten, Papier.
;
; **Abgeleitet aus Open_window** (HULL/WINDOWS.S), das eine vollstaendig
; ausfuellt und dabei die Reihenfolge verraet:
;
;     move.w d4,Window_area+PA_X1(a4)      ; X+16
;     ... move.w d4,Window_area+PA_X2(a4)  ; rechte Kante
;     ... move.w d4,Window_area+PA_Y1(a4)
;     ... move.w d4,Window_area+PA_Y2(a4)
;     move.w #Default_ink,Window_area+PA_Ink(a4)
;     move.w #Default_shadow,Window_area+PA_Shadow(a4)
;     move.w #Window_colour,Window_area+PA_Paper(a4)
;
; Sieben Worte, PA_data_size ist 16 -- ein Wort bleibt uebrig.
;
; **Die Reihenfolge ist X1, X2, Y1, Y2**, belegt aus seinen Datensaetzen:
;     Default_PA   dc.w 0,319,0,199          (HULL/WORDS.S)
;     Status_PA    dc.w 0,319,0,35,31,0,-1   (DISPLAY.S)
;     ShowPicTxt_PA dc.w 18,302,139,192,...  (MODULES.S)
; Bis 2026-09-25 stand hier X1, Y1, X2, Y2 -- aus der Schreibfolge in
; Open_window erschlossen, die die Reihenfolge gar nicht verraet.  Solange
; nur Namen schrieben und lasen, fiel das nicht auf; seine Datensaetze
; wurden verdreht gelesen (Erkenntnis 172).
PA_X1		equ	0
PA_X2		equ	2
PA_Y1		equ	4
PA_Y2		equ	6
PA_Ink		equ	8
PA_Shadow	equ	10
PA_Paper	equ	12
Cursor_colour	equ	1

;--- PA_data_size -- Groesse einer Print-Area.  HULL/WINDOWS.S legt damit
;--- Window_area an; ohne den Wert werden Window_tree und Window_background
;--- unbestimmt und alles, was sie als Versatz benutzt, meldet Fehler.
PA_data_size	equ	16

;--- MA_X1 .. MA_Y2 -- die Felder einer Mouse-Area.  **Strukturversaetze,
;--- keine Variablen.**  Thalions CONTROLS.S baut damit den Bereich der
;--- Bildlaufleiste:  lea.l Scroll_bar_MA,a1 / move.w d0,MA_X1(a1) ...
;--- Die Anordnung ist die der Print-Area, denn Open_window uebergibt Push_MA
;--- und Push_PA dieselbe Adresse: X1, X2, Y1, Y2 (belegt: MemberSel_MA
;--- 0,319,0,35 in CONTROLS.S, Lay3_ItemSelect_MA 16,166,139,192 in
;--- MODULES.S; bis 2026-09-25 verdreht, Erkenntnis 172).
;--- Bis 2026-09-24 standen diese Namen bei uns als BSS-Variablen; sein
;--- MA_X1(a1) wurde dadurch zu a1 plus einer Adresse, schrieb ins Leere,
;--- und der Zeiger klebte oben (Erkenntnis 169).
MA_X1		equ	0
MA_X2		equ	2
MA_Y1		equ	4
MA_Y2		equ	6

;--- Die Textsteuerung -- Thalions HULL/WORDS.S (Process_text, Display_text).
;--- Drei Werte sind **aus den Daten belegt**, an Text.amb und den
;--- Kartentexten nachgezaehlt:
;---   Command_char  "~"     Befehle stehen zwischen Tilden: ~LEAD~, ~SELF~
;---   Ink_command   "INK "  "cmp.l #Ink_command,d1" vergleicht vier Zeichen,
;---                         und im Text steht ~INK 23~ -- mit Leerzeichen
;---   CR            "^"     Zeilenumbruch mitten im Text: "betreten:^^Die"
;--- Angenommen ist nur das Blinktempo der Schreibmarke in Eingabefeldern.
;--- Die Rueckgabewerte fuer Return_value stehen in AM2_CPU 1.20 an Thalions
;--- Aufrufstellen als move.l #n,Return_value (9:$9CB4) vor jmp Exit_program
;--- (2026-10-01).  Thalions Lader liest sie: <= -5000 startet das Extro.
Command_char	equ	"~"
Ink_command	equ	"INK "
CR		equ	"^"
Cursor_interval	equ	25		; angenommen: halbe Sekunde bei 50 Hz
MERGED_TEXT_TOO_LONG	equ	-3001	; WORDS.S, AM2_CPU 0:$2701C
PROCESSED_TEXT_TOO_LONG	equ	-3002	; WORDS.S, AM2_CPU 0:$2712C
; Aus Thalions CONTROLS.S: der Nutzer verzichtet nach einem Dateifehler auf
; den neuen Versuch (Disk_error_handler).
OS_ERROR		equ	-1000	; AM2_CPU 0:$2924A
; Aus Thalions EVENTS.S: eine Kette, die auf sich selbst zeigt
; (Chain_to_next_event), und die drei Enden des Spiels (End_seq).
ENDLESS_EVENT		equ	-4002	; AM2_CPU 0:$1291A
GAME_COMPLETED		equ	-5000	; AM2_CPU 0:$12D4A, Extro 0
GAME_COMPLETED2		equ	-5001	; 0:$12D3E, Valdyn mit dem Ding, Extro 1
GAME_COMPLETED3		equ	-5002	; 0:$12D26, Valdyn fehlt, Extro 2

;--- funkel_anz -- Anzahl der Funkelpunkte in FAIRY.S.  Die Falcon-Fassung
;--- des Intros steht in intro/fantasy.s und hat die Zahl aus dem
;--- Speicherauszug; hier genuegt irgendein Wert.
funkel_anz	equ	32

;--- Fingerprint -- Schalter fuer das FINGERPRINT-Makro ("ifne Fingerprint"
;--- in MAIN.S).  Aus.
Fingerprint	equ	0

;--- Musikbefehle fuer das music-Makro: der Eintrag in der Sprungtabelle
;--- des Spielers (Music_routine, AM2_CPU 0:$2AA0E).  Thalions Set_music
;--- springt nach +0, +12 und +16 (0:$26910, $26932, $2693E; docs/13).
Music_init	equ	0		; +0   a0 = Stueck: Versaetze -> Zeiger
Music_start	equ	3		; +12  d0 = Teilstueck
Music_stop	equ	4		; +16  Stumm-Merker setzen

;===========================================================================
; MAKROS -- Attrappen wie Get/Free/Push/Pop
;===========================================================================

;---------------------------------------------------------------------------
; Rasterlisten.  Das Amiga-Gegenstueck zum Copper: Palettenwechsel mitten im
; Bild, an einer Rasterzeile festgemacht.  Thalions src/MODULES.S baut damit
; Main_RL, Inv_RL, Map_RL, C3_RL und Combat_RL.
;
;   R_palette <Zeile>,<Palette>             ganze Palette ab dieser Zeile
;   R_range   <Zeile>,<Farbe>,<Zeile2>,<Tab>  eine Farbe, Zeile fuer Zeile
;   R_end                                   Ende der Liste
;
; **Das Format ist nicht mehr erfunden -- Combat_RL zeigt es offen.**  Dort
; steht mitten in der Liste eine ausgeschriebene Fassung des ersten Makros,
; weil Thalion einen Zeiger auf den Palettenzeiger brauchte:
;
;     R_range 1,25,35,Portrait_range
;     dc.b 0,Middle_Y+1
;     Combat_pal_ptr: dc.l Combat_pal
;     R_palette Combat_Y+Combat_height+1,Tactic_pal
;
; Die dritte und vierte Zeile *sind* R_palette.  Ein Eintrag beginnt also mit
; einem Kennbyte, dann folgt die Zeilennummer als Byte; bei R_palette schliesst
; ein Langwort an (sechs Byte), bei R_range zwei weitere Bytes und ein Langwort
; (acht).  Beide Laengen sind gerade, die Liste bleibt ohne Ausrichtung lesbar.
;
; Die Kennbytes 0 und 1 und das Ende sind weiterhin unsere Wahl -- der
; Auswerter (Set_fade) steht in der nicht freigegebenen Bibliothek und ist
; hier neu geschrieben.  Nur der *Aufbau* der Eintraege ist belegt.
;
; **Ueberholt:** hier stand, R_range bleibe beim Falcon-Port unbeachtet, weil
; eine Farbe je Bildzeile einen Rasterinterrupt braeuchte -- wir machten im
; Raum, was der Amiga in der Zeit macht (der Portraitverlauf bekam eine eigene
; Palettenbank, siehe PORTRAIT_VERLAUF im Konverter).  Den Rasterinterrupt
; gibt es inzwischen: HULL/RASTER.S zerlegt R_range in seine Einzelzeilen.
; Dass er auf echter Hardware zeilengenau feuert, ist allerdings **noch nicht
; belegt** -- Hatari zeichnet Falcon-Bilder mit nur einer Palette und kann es
; nicht zeigen.  Bis dahin traegt weiterhin die Palettenbank.
;---------------------------------------------------------------------------
RL_PAL		equ	0		; Kennbyte "ganze Palette"
RL_RANGE	equ	1		; Kennbyte "eine Farbe ueber Zeilen"
RL_END		equ	-1		; Kennbyte "Ende"

R_palette	MACRO
		dc.b	RL_PAL,\1
		dc.l	\2
		ENDM

R_range		MACRO
		dc.b	RL_RANGE,\1,\2,\3
		dc.l	\4
		ENDM

R_end		MACRO
		dc.b	RL_END,0
		ENDM

;---------------------------------------------------------------------------
; waitblit -- auf den Amiga-Blitter warten.  Reine Hardware, gehoert in die
; Bibliotheksschicht.  Auf dem Atari steht hier etwas anderes oder nichts.
;---------------------------------------------------------------------------
waitblit	MACRO
		ENDM

;---------------------------------------------------------------------------
; music -- einen Eintrag der Sprungtabelle des Musikspielers anspringen,
; wie in AM2_CPU (jsr 0:$2AA0E + 4*Befehl).  Der Spieler ist Thalions Code
; aus AM2_CPU (am2cpu_code.py), seine Hardware MUSIK_SUP.S (docs/13).
; Register wie dort: der Spieler sichert selbst.
;---------------------------------------------------------------------------
music		MACRO
		jsr	Music_routine+4*(\1)
		ENDM

;---------------------------------------------------------------------------
; FINGERPRINT -- Thalions Marke im uebersetzten Programm, vermutlich zum
; Wiederfinden einer Stelle im Speicherauszug.  Genau dafuer waere sie auch
; uns nuetzlich, wenn wir wuessten, was sie ablegt.
;---------------------------------------------------------------------------
FINGERPRINT	MACRO
		ENDM

;---------------------------------------------------------------------------
; XX -- Diagnosehilfe: Hintergrundfarbe setzen, um zu sehen, wie lange ein
; Abschnitt dauert.  Das Argument ist ein Amiga-Farbwert ($f00 = rot).
;---------------------------------------------------------------------------
XX		MACRO
		ENDM

;---------------------------------------------------------------------------
; Amiga-Hardware.  HULL/VARIOUS.S schaltet vor dem Entfernen der Musik die
; DMA-Kanaele ab: "move.w #$000f,Custom+dmacon".  Das ist echter
; Amiga-Hardwarezugriff und gehoert damit in die Bibliotheksschicht.
; Custom steht darum in MUSIK_SUP.S und zeigt auf den Paula-Schattenblock,
; in den auch der Spieler schreibt (UMBIEGEN in am2cpu_code.py, docs/13):
; Das "aus" kommt beim Mischer an, und $DFF096 bleibt unberuehrt.  Nicht
; hier: vorspann.i gilt fuer beide Einheiten, und in "spiel" waere der
; Schattenblock ein unbenutzter Import (vlink-Warnung 62).
;
; Siehe Erkenntnis 51: dass diese Stelle lange unentdeckt blieb, hat einen
; eigenen Grund.
;---------------------------------------------------------------------------
dmacon		equ	$096

;---------------------------------------------------------------------------
; AmigaDOS-Fehlernummern.  Thalions HULL/CONTROLS.S ordnet ihnen in
; Disk_error_handler Meldungstexte zu (Tabelle Disk_errors):
;
;     cmp.w #ERROR_DISK_WRITE_PROTECTED,d0 / ...
;
; **Die Werte stehen in AM2_CPU**: Thalions uebersetzte Tabelle Disk_errors
; liegt bei 0:$2925C (Erkenntnis 268).  Vier waren hier bis 2026-10-01
; falsch (OBJECT_TOO_LARGE 211, SEEK_ERROR 227, INCOMPLETE_READ/WRITE
; 234/235); INCOMPLETE_READ/WRITE (500/501) sind Thalions eigene, keine aus
; dos/dos.h.  Die GEMDOS-Fehler bildet Fehler_umsetzen (FILES_SUP.S) auf
; diese Nummern ab, dann waehlt Disk_error_handler die Meldung.
;---------------------------------------------------------------------------
ERROR_NO_FREE_STORE		equ	103
ERROR_OBJECT_IN_USE		equ	202
ERROR_OBJECT_EXISTS		equ	203
ERROR_DIR_NOT_FOUND		equ	204
ERROR_OBJECT_NOT_FOUND		equ	205
ERROR_INVALID_COMPONENT_NAME	equ	210
ERROR_OBJECT_TOO_LARGE		equ	207
ERROR_OBJECT_WRONG_TYPE		equ	212
ERROR_DISK_NOT_VALIDATED	equ	213
ERROR_DISK_WRITE_PROTECTED	equ	214
ERROR_RENAME_ACROSS_DEVICES	equ	215
ERROR_DISK_FULL			equ	221
ERROR_WRITE_PROTECTED		equ	223
ERROR_READ_PROTECTED		equ	224
ERROR_NOT_A_DOS_DISK		equ	225
ERROR_SEEK_ERROR		equ	219
ERROR_INCOMPLETE_READ		equ	500
ERROR_INCOMPLETE_WRITE		equ	501

;---------------------------------------------------------------------------
; Save_game_disk -- die **Nummer** der Spielstandsdiskette, keine Variable.
;
; Thalions Disk_requester (HULL/CONTROLS.S:1655) vergleicht damit:
;
;     cmp.w #Save_game_disk,d0    ; Is save-game disk ?
;     ...
;     add.b #"A"-1,d0            ; sonst: Nummer -> Laufwerksbuchstabe
;
; Als BSS-Byte angelegt, wurde daraus ein 16-Bit-Absolutbezug auf eine
; Adresse, die nicht in sechzehn Bit passt -- vlink brach ab.  Derselbe
; Fehler wie bei Number (Erkenntnis 157), nur andersherum: diesmal habe ich
; eine Konstante fuer eine Variable gehalten.
;
; **Arbeitsannahme.**  Der Wert ist nicht ueberliefert, und der ganze Zweig
; ist auf dem Atari tot: wir lesen von der Festplatte, nicht von Disketten.
; Wer den Diskettenwechsel je scharf schaltet, belegt ihn vorher.
;---------------------------------------------------------------------------
Save_game_disk	equ	0

; MAIN.S -- Start, Restart_game, die aeussere Schleife, Exit_program
;
; **Unsere Bibliothek, nicht Thalions MAIN.S** (die steht in spiel.s).  Im
; Original lag das hier in AM2_CPU: Thalions Quelltext ruft Init_program
; nirgends selbst auf, sondern sagt an dessen Kopf
;
;     NOTE : Do not call this routine directly, but call [ Restart_game ]
;
; und Restart_game ist nur ein Name (Load_game springt hinein, ebenso
; DIAGNOST.S).  Genauso Exit_program (ACTIONS.S, EVENTS.S, WORDS.S,
; CONTROLS.S: "jmp Exit_program").  Beide kehren nie zurueck.
;
; Bis Stufe (c) (2026-09-27) stand hier unsere eigene Hauptschleife mit der
; v_screen-Kette, dem Kartenlader und dem Gruppenlauf.  Das ist alles
; Thalions Code geworden; hier bleibt, was die Hardware betrifft.

; ***************************************************************************
; start -- der Programmeinsprung.  Hardware aufsetzen, Bibliotheksdaten
; laden, dann Restart_game.
; ***************************************************************************
start:
	move.l	4(sp),a0
	; ---- Wahl des Laders (Erkenntnis 261) ----
	; AMBER.TOS (Intro-Session) startet uns mit der Wahl aus Thalions
	; Startmenue in der Befehlszeile: Laenge 1, dann '0' (Weiterspielen)
	; oder '1' (Neue Quest).  Sie geht nach Thalions Intro_menu_choice,
	; wie im Original von Ambermoon_intro an AM2_CPU; unser Startmenue
	; entfaellt dann.  Alles andere, auch eine leere Zeile: Startmenue.
	cmp.b	#1,$80(a0)
	bne.b	.keine_wahl
	moveq	#0,d0
	move.b	$81(a0),d0
	sub.b	#'0',d0
	cmp.b	#1,d0
	bhi.b	.keine_wahl
	move.w	d0,Intro_menu_choice
	st	Wahl_vom_lader
.keine_wahl:
	move.l	12(a0),d0
	add.l	20(a0),d0
	add.l	28(a0),d0
	add.l	#256,d0
	; **Eigener Stapel** (engine.s, 16 KB).  Vorher stand sp auf dem
	; BSS-Ende -- die 256 in d0 sind die Basepage, kein Stapelplatz --, und
	; der Stapel wuchs in die letzten BSS-Variablen (Erkenntnis 185).
	; Mshrink behaelt Basepage bis BSS-Ende, stacktop liegt darin.
	lea	stacktop,sp
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#Mshrink,-(sp)
	Gemdos
	lea	12(sp),sp

	lea	vars,a5
	bsr	Enter_supervisor
	; Der Notausgang (unten) haengt an etv_term: TOS ruft ihn bei jedem
	; Programmende, auch nach Bomben.  So frueh wie moeglich, denn ab
	; Open_screen steht ohne ihn nach einem Absturz der Rechner still.
	pea	Notausgang(pc)
	move.w	#ETV_TERM,-(sp)
	move.w	#Setexc,-(sp)
	Bios
	addq.l	#8,sp
	move.l	d0,alter_term

	pea	m_hello(pc)
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp
	; Die Ladeadresse dazu (2026-10-02): Steht nach einem Absturz der PC
	; fest (BOMBEN.TOS), fuehrt sie mit der Symbolkarte zur Routine.
	; start ist der erste Befehl des Programms.
	lea	start(pc),a0
	move.l	a0,d0
	lea	m_adresse_zahl,a0
	lea	m_ziffern(pc),a1
	moveq	#7,d2
.hex:	rol.l	#4,d0
	moveq	#$F,d1
	and.w	d0,d1
	move.b	(a1,d1.w),(a0)+
	dbf	d2,.hex
	pea	m_adresse
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp

; ---- Bibliotheksdaten ----
	; Was im Original in AM2_CPU lag und Thalions Code an festen Adressen
	; erwartet.  Das meiste steht schon im Programm (build/am2cpu_daten.i);
	; zur Laufzeit geladen wird nur, was aus einer Spieldatei kommt.
	bsr	Ordner_suchen		; AMBFILES\ vor jeden Dateinamen? (FILES_SUP.S)
	bsr	Einstellungen_lesen	; AMBER.INF (E17), before Open_screen and Musik_install
	lea	Zeichensatz,a0		; fuer Put_text_line (WORDS_SUP.S)
	move.l	a0,p_font(a5)
	bsr	Load_objects		; Objects.amb -> Object_data
	tst.l	d0
	bpl.b	.objekte_da
	pea	m_noobj(pc)
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp
.objekte_da:
	bsr	Lade_tastengrafik	; Button_graphics -> Control_icons
	jsr	Lade_texte		; Text.amb -> Textdaten (Prompts, Namen, Vorlagen)
	jsr	Lade_keymap		; Keymap -> Tastenbelegung fuer Read_key
	jsr	D3_einrichten		; CPU_68020_plus (D3_SUP.S)

	; Selbsttest des Laufzeit-Entpackers (Leitziel 2).  Nur mit
	; -DENTPACKPRUEF=1 uebersetzt; schreibt LAYOUT.BIN zum Vergleich.
	IFD	ENTPACKPRUEF
	bsr	Pruefe_entpacker
	ENDC

; ---- Bildschirm, Raster, Maus ----
	bsr	Bildpuffer_anlegen
	tst.l	d0
	bpl.b	.puffer_da
	pea	m_voll(pc)		; Schirm noch nicht offen: nur melden
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp
	move.w	#Cconin,-(sp)
	Gemdos
	addq.l	#2,sp
	bra	quit
.puffer_da:
	bsr	Open_screen
	; Der Rasterinterrupt tut nichts, solange keine Liste gesetzt ist, und
	; im Falcon-Bau kommt keine (RASTER_VERFAHREN = RASTER_RAUM,
	; FALCON_OFF.S; Erkenntnis 154).  Raster_install rettet die Vektoren
	; und legt Timer B still.
	bsr	Raster_install
	jsr	Musik_install		; DMA-Ton (MUSIK_SUP.S)
	IFNE	RASTER_VERFAHREN-RASTER_RAUM
	FAIL	"RASTER_ZEIT ist noch nicht verdrahtet -- siehe FALCON_OFF.S"
	ENDC
	IFD	RASTERPRUEF
	lea	Raster_pruefliste,a0
	bsr	Raster_liste_setzen
	ENDC
	; Ein Zeigerhintergrund je Schirm und ein freier (Doppelpuffer B1a).
	lea	zeiger_saetze,a0
	move.l	#mousebg,ZS_BG(a0)
	sf	ZS_DA(a0)
	move.l	#mousebg2,ZS_SIZE+ZS_BG(a0)
	sf	ZS_SIZE+ZS_DA(a0)
	move.l	#mousebg3,zg_frei
	lea	Default_Mptr,a0		; Thalions Pfeil (AM2_CPU, AREAS.S)
	bsr	Set_mouse_ptr
	; Shadow_colour: der Schatten unter der Schrift.  Im Original holt ihn
	; die Ausgabeflaeche; ueblicherweise Default_shadow.
	move.w	#DEFAULT_SHADOW,Shadow_colour
	bsr	Mouse_install
	; Das Startmenue (STARTMENUE.S) setzt Intro_menu_choice; QUIT kehrt
	; nicht zurueck.  Hat der Lader schon gewaehlt, entfaellt es.  Load_game
	; kommt spaeter ohne Menue nach Restart_game und laedt dann den
	; gewaehlten Platz.
	tst.b	Wahl_vom_lader
	bne.b	.ohne_menue
	bsr	Startmenue
.ohne_menue:
	; weiter in Restart_game

; ***************************************************************************
; Restart_game -- stacks back to their start, Thalion's Init_program, then
; the outer loop.  Never returns.
;   IN : Initial_save, Intro_menu_choice (variables); registers and stack
;        do not matter, the stack is set anew.
;
; Gerufen von start und von Thalions Load_game ("jmp Restart_game", nachdem
; Initial_save gesetzt ist).  Der Prozessorstapel wird darum neu gesetzt:
; wer von Load_game kommt, steht tief in Modulen.
;
; **Die Reihenfolge der Stapel ist nicht beliebig** (Erkenntnisse 162, 172):
;   Reset_PA_stack       vor Reset_module_stack -- dessen Init_module legt
;                        fuer ein Modul ohne eigenen Druckbereich Default_PA
;                        auf, und PA_Sp muss dann schon stehen
;   Reset_module_stack   Thalions: legt Default_module auf (MODULES.S)
;   Reset_tree_stack     Default_Tree; Init_program legt Main_tree darauf
;   Reset_scroll_bar_stack  CONTROLS.S; ohne den Aufruf schreibt Push
;                        Scroll_bar nach Adresse 4
; Den Zeigerstapel (AREAS.S) leert niemand sonst: Reset_module_stack legt
; ueber Init_module Default_Mptr auf, und ohne das Leeren bliebe bei jedem
; Laden eines Spielstands ein Eintrag liegen -- nach sieben Ladevorgaengen
; waere der Stapel voll und Push_Mptr taete nichts mehr.  Den Mausbereich
; raeumt MA_vollbild.  Ebenso den Clip-Stapel (EFFECTS_SUP.S): laedt Thalion
; aus einem Fenster mit aufgelegter CA, beschnitte sie sonst jedes Bild danach
; (Block_beschneiden).
; Kill_all_memory clears what a previous game held.  Before it,
; Close_current_file: Out_of_memory or a load error can come here while
; Eintrag_lesen had a container open (FILES_SUP.S).
; Und vorher die Musik aus, mit Thalions eigenem Set_music (d0 = 0): es haelt
; den Spieler an, gibt das Stueck frei und loescht Loaded_music.  Sonst spielte
; der Spieler aus freigegebenem Speicher weiter, den das Laden ueberschreibt
; (schwarzer Schirm oder Grafikkonfetti nach Laden im Spiel, 2026-10-09), und
; weil Loaded_music den Neustart ueberdauert (VARIOUS.S, nicht in Game_data),
; hielte Set_map_music dasselbe Stueck fuer geladen.
; Erst nach Init_program steht Out_of_memory offen (Notweg, MEMORY.S): auch
; Thalions Out_of_memory kommt hierher, mit Initial_save = -1.
; ***************************************************************************
Restart_game:
	lea	stacktop,sp
	lea	vars,a5
	moveq	#0,d0
	jsr	Set_music		; Musik aus, Stueck frei (Thalions VARIOUS.S)
	jsr	Close_current_file	; a way out may have left a container open
	bsr	Kill_all_memory
	jsr	Reset_PA_stack
	clr.w	v_mpsp(a5)		; Zeigerstapel leeren
	sf	zeiger_sperre		; wer hierher sprang, gab sie nicht frei (269)
	move.l	#ca_bottom,CA_Sp	; Clip-Stapel: nur das Vollbild
	jsr	Reset_module_stack
	jsr	Reset_tree_stack
	jsr	Reset_scroll_bar_stack
	bsr	MA_vollbild
	jsr	Init_program
	st	Notweg			; ab jetzt Out_of_memory (MEMORY.S)
	IFD	ABSTURZTEST
	move.w	VBL_counter,at_beginn
	st	at_scharf
	ENDC
	IFD	SPEICHERTEST
	tst.b	Speichertest_scharf
	bne.b	.getestet
	st	Speichertest_scharf
	move.w	#SPEICHERTEST,Speichertest_zaehler
.getestet:
	ENDC

; ***************************************************************************
; Die aeussere Schleife.  Dieselben drei Schritte wie Thalions innere in
; Push_Module (HULL/MODULE_C.S), dort fuer ein lokales Modul:
;
;     .Loop3:  jsr Update_display / jsr Handle_input / jsr Switch_screens
;
; Hier ohne Pop_counter: das globale Modul unten auf dem Stapel wird nie
; heruntergenommen.  Beendet wird ueber Exit_program.
; ***************************************************************************
Main_loop:
	jsr	Update_display
	jsr	Handle_input
	jsr	Switch_screens
	bra.b	Main_loop

; ***************************************************************************
; Einstellungen_lesen -- AMBER.INF, the one settings file (E17,
; shared/SETTINGS.S), read once at the start: after Ordner_suchen (Datei_name
; puts AMBFILES\ in front), before Open_screen (PLAIN_ST, ST.S) and
; Musik_install (MUSIC, MUSIK_SUP.S).  The line under "Ladeadresse" shows
; what was read.  Without the file every setting is SET_NONE, and each
; reader takes its default.
;   All registers are preserved.
; ***************************************************************************
Einstellungen_lesen:
	movem.l	d0-d2/a0-a2,-(sp)
	lea	m_amber_inf,a0
	moveq	#0,d1			; number 0: the name is in a0
	jsr	Datei_name		; FILES_SUP.S
	bsr	Settings_read		; no file: every setting SET_NONE
	lea	m_einstellungen,a0
	bsr	Settings_text
	pea	m_einstellungen
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts

; ***************************************************************************
; Exit_program -- back to the desktop in order.  Never returns.
;   IN : Return_value.l = the result for the loader (Pterm takes its low
;        word); registers and stack do not matter, Thalion jumps in from
;        any depth.
;
; Thalion springt mit jmp hinein, aus beliebiger Tiefe.  Also Stapel und a5
; neu, dann Raster, Maus, Bildschirm und Supervisor in umgekehrter Folge.
;
; **Return_value geht an den Aufrufer** (Erkenntnis 263), wie im Original:
; dort liest Thalions Lader `Ambermoon` die Rueckgabe von AM2_CPU und startet
; ab GAME_COMPLETED (-5000) abwaerts das Extro.  Bei uns endet das Programm
; mit Pterm und dem unteren Wort; der Lader AMBER.TOS (Intro-Session) startet
; bei -5000..-5002 EXTRO.TOS.  Ein normales Ende laesst Return_value auf 0.
;
; Diagnoseschalter ENDETEST=n (VASM_EXTRA="-DENDETEST=1"): ein Ende ohne
; eigenen Wert gilt als Spielende n (0..2), damit sich der Extro-Start
; pruefen laesst, ohne das Spiel durchzuspielen.
; ***************************************************************************
Exit_program:
	lea	stacktop,sp
	lea	vars,a5
	IFD	ENDETEST
	tst.l	Return_value
	bne.b	.eigener_wert
	move.l	#GAME_COMPLETED-ENDETEST,Return_value
.eigener_wert:
	ENDC
	jsr	Musik_remove		; DMA-Ton aus (MUSIK_SUP.S)
	bsr	Raster_remove
	bsr	Mouse_remove
	bsr	Close_screen
	pea	m_done(pc)
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp
quit:
	jsr	Cache030_zurueck	; CACR wie vor dem Start (D3_SUP.S)
	bsr	Leave_supervisor
	move.w	Return_value+2,-(sp)	; unteres Wort
	move.w	#Pterm,-(sp)
	Gemdos

; ***************************************************************************
; Notausgang -- der Abbau, wenn das Programm nicht ueber Exit_program endet.
;
; Haengt an etv_term ($408, start).  GEMDOS ruft den Vektor in Pterm, also
; bei jedem Ende: nach Bomben beendet TOS das Programm selbst mit Pterm.
; Ohne diesen Abbau blieben dann unser VBL in der Warteschlange, der
; Mausvektor und Timer B auf Code, der gleich nicht mehr im Speicher ist,
; dazu Bildschirmmodus, Farben und Ton des Spiels.
;
; Dieselben Schritte wie Exit_program.  Jeder hat seinen Merker und tut
; nach einem geordneten Ende nichts mehr; so darf der Notausgang auch dann
; laufen.  Close_screen laesst hier GEMDOS weg (Im_notausgang, FALCON.S).
;
; Die Interrupts werden fuer die Dauer auf Stufe 3 gesetzt: kam der Absturz
; aus einem Interrupt, stuende die Maske noch hoch, und das Vsync in
; Close_screen wartete auf einen VBL, der nie kommt.  Ein Absturz in unserem
; VBL selbst ist damit nicht abgedeckt.
;
; Zum Schluss den alten Vektor zurueck und an ihn weiter.  Ob GEMDOS
; etv_term je Programm selbst zuruecksetzt, ist nicht belegt; so haengt es
; nicht davon ab.
; ***************************************************************************
Notausgang:
	movem.l	d0-d2/a0-a2/a5,-(sp)
	move.w	sr,-(sp)
	move.w	#$2300,sr
	lea	vars,a5
	st	Im_notausgang
	jsr	Musik_remove		; DMA-Ton aus (MUSIK_SUP.S)
	bsr	Raster_remove
	bsr	Mouse_remove
	bsr	Close_screen
	jsr	Cache030_zurueck	; CACR wie vor dem Start (D3_SUP.S), ohne TOS
	move.l	alter_term,$408.w	; ohne TOS: Setexc ist BIOS
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d2/a0-a2/a5
	move.l	alter_term,-(sp)	; weiter an den vorigen Halter
	rts

	IFD	ABSTURZTEST
; ---------------------------------------------------------------------------
; Absturz_pruefen -- Diagnoseschalter ABSTURZTEST (VASM_EXTRA=
; "-DABSTURZTEST=1"): etwa fuenf Sekunden nach Init_program (250 VBL) ein
; illegaler Befehl, vier Bomben.  Danach muss der Notausgang den Desktop mit
; seinen Farben, Maus und Ruhe zurueckgeben.  Aus Switch_screens (LIBRARY.S),
; das in jeder Schleife jedes Bild laeuft.
Absturz_pruefen:
	tst.b	at_scharf
	beq.b	.raus
	move.w	VBL_counter,d0
	sub.w	at_beginn,d0
	cmp.w	#250,d0
	blo.b	.raus
	illegal
.raus:	rts
	ENDC

; ***************************************************************************
; Bildpuffer_anlegen -- die beiden Schirme des Doppelpuffers.
;
; **Wie im Original zwei Schirme** (AM2_CPU 0:$21344, Erkenntnis 200/258):
; Schirm_vorn wird angezeigt, Off_screen ist der hintere, und Work_screen,
; das Ziel aller Zeichenroutinen, zeigt auf ihn.  Update_screen und
; Switch_screens tauschen die beiden (LIBRARY.S).
;
; Beide liegen in einem Block im ST-RAM (Mxalloc Modus 0): der Bildspeicher
; des Falcon muss dort liegen.  Jeder Schirm hat oben und unten SCHIRM_RAND
; schwarze Zeilen, in die das Bildschuetteln hineinschiebt; die Schirme
; beginnen auf einer 256-Byte-Grenze.  Der ganze Block wird geloescht.
; Zurueck: d0 = 0 gut, -1 kein Speicher.
; ***************************************************************************
Bildpuffer_anlegen:
	move.w	#0,-(sp)		; Modus 0 = ST-RAM
	move.l	#2*SCHIRM_BLOCK+256,-(sp)
	move.w	#Mxalloc,-(sp)
	Gemdos
	addq.l	#8,sp
	tst.l	d0
	beq.b	.nichts
	move.l	d0,p_scrr(a5)		; unausgerichtet, zum Freigeben
	add.l	#255,d0
	and.l	#-256,d0
	move.l	d0,a0
	move.l	#(2*SCHIRM_BLOCK)/4-1,d1
	moveq	#0,d0
.leeren:
	move.l	d0,(a0)+
	subq.l	#1,d1
	bpl.b	.leeren
	suba.l	#2*SCHIRM_BLOCK,a0	; zurueck an den Anfang
	lea	SCHIRM_RAND*SCRROW(a0),a0
	move.l	a0,Schirm_vorn
	adda.l	#SCHIRM_BLOCK,a0
	move.l	a0,Off_screen
	move.l	a0,Work_screen
	sf	Screen_flag
	clr.w	Vertical_screen_offset
	moveq	#0,d0
	rts
.nichts:
	moveq	#-1,d0
	rts

; ***************************************************************************
; Speicher_voll -- der letzte Halt, wenn kein ST-RAM mehr kommt.  Im Spiel
; springt der Speicherverwalter nach Thalions Out_of_memory, wie im Original
; (MEMORY.S, Erkenntnis 267); hierher nur, solange das nicht offen steht:
; vor dem Ende von Init_program und waehrend Out_of_memory selbst laeuft.
; Thalions Aufrufer pruefen das Handle nicht; ohne diesen Halt kopierte
; Show_layout das Layout nach Adresse 0 (Erkenntnis 182).
;
; Schirm zu, Meldung auf den TOS-Bildschirm, Taste, Ende.  Die Taste kommt
; ueber GEMDOS, denn die Maus ist dann abgemeldet.  a5 selbst laden -- der
; Aufrufer kann Thalions Code sein (Erkenntnis 177).
; ***************************************************************************
Speicher_voll:
	lea	stacktop,sp
	lea	vars,a5
	jsr	Musik_remove		; DMA-Ton aus (MUSIK_SUP.S)
	bsr	Raster_remove
	bsr	Mouse_remove
	bsr	Close_screen
	pea	m_voll(pc)
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp
	move.w	#Cconin,-(sp)		; auf eine Taste warten
	Gemdos
	addq.l	#2,sp
	bra	quit

; ***************************************************************************
	even
m_hello: MACHINE_NAME			; per machine in vorspann.i
	dc.b	13,10,0
m_ziffern: dc.b	"0123456789ABCDEF"
m_done:	dc.b	"Fertig.",13,10,0
m_voll:	dc.b	"Speicher voll: Allocate_memory bekam nichts (Erkenntnis 182, 267).",13,10
	dc.b	"Taste beendet.",13,10,0
m_noobj: dc.b	"OBJECTS.AMB fehlt -- kein Gewicht/keine Typpruefung.",13,10,0
	even

	SECTION	Fast_DATA,data
m_adresse:	dc.b	"Ladeadresse $"
m_adresse_zahl:	dc.b	"00000000",13,10,0
m_amber_inf:	dc.b	"AMBER.INF",0
	even

	SECTION	Fast_BSS,bss
	even
; Thalions Rueckgabe an den Aufrufer (Name und Vertrag aus AM2_CPU,
; 9:$9CB4): Thalion schreibt vor jmp Exit_program einen der Werte aus
; vorspann.i hinein (GAME_COMPLETED ...).  TOS loescht das BSS beim Start.
Return_value:	ds.l	1
Tos_rette:	ds.l	5		; d1-d2/a0-a2 ueber einen TOS-Aufruf (FALCON_OFF.S, 270)
Wahl_vom_lader:	ds.b	1		; die Befehlszeile trug '0' oder '1'
Im_notausgang:	ds.b	1		; gesetzt: Abbau aus etv_term, kein GEMDOS
	even
m_einstellungen: ds.b	SET_TEXT_LEN	; the AMBER.INF line (Einstellungen_lesen)
	even
alter_term:	ds.l	1		; etv_term vor uns (Notausgang)
	IFD	ABSTURZTEST
at_beginn:	ds.w	1		; VBL_counter nach Init_program
at_scharf:	ds.b	1
	even
	ENDC
	even
	SECTION	Program,code

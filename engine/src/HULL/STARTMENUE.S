; ===========================================================================
; STARTMENUE.S -- das Startmenue: WEITERSPIELEN, NEUE QUEST STARTEN, INTRO,
; QUIT.  Einheit "bibliothek" (engine.s).
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D4: our own menu instead
; of Thalion's, only when ENGINE.TOS runs alone; texts from Ambermoon_intro
; at build time.
;
; Im Original steht das Menue nicht in AM2_CPU, sondern im eigenen Programm
; Ambermoon_intro (Quelltext nicht freigegeben).  Es uebergibt seine Wahl in
; Intro_menu_choice an AM2_CPU (Erkenntnis 251), und Thalions Init_program
; liest sie:
;
;     tst.w Intro_menu_choice / bne .New      ; 0 = Weiterspielen
;     ... Saves laden, letzter Platz -> Initial_save ...
;     .New: Push Module,Chared_Mod            ; sonst: Charaktereditor
;
; **Schlicht, vorerst** (Nutzer, 2026-09-28): die vier Texte kommen beim Bau
; aus Ambermoon_intro (tools/intro_auszug.py -> build/intro_daten.i), mit
; der Hoehe des Originals; gezeichnet wird mit unserem Zeichensatz auf
; schwarzem Grund.  Bild und Zierschrift des Originals kommen mit dem Intro.
;
; Die Wahl geht wie im Original ueber Intro_menu_choice (Erkenntnis 261):
;   WEITERSPIELEN      0: Init_program laedt den letzten Platz aus Saves
;   NEUE QUEST STARTEN 1: Init_program legt den Charaktereditor auf
;   INTRO              ausgegraut
;   QUIT               Exit_program
; WEITERSPIELEN ist waehlbar, wenn Saves einen letzten Platz nennt (Wort 0
; ungleich null) -- Thalions Regel, dieselbe wie im Lader der Intro-Session.
; Die ausgelieferte SAVES ist Thalions, mit 0; frei wird der Eintrag nach dem
; ersten Speichern.
;
; Kommt ENGINE.TOS vom Lader (AMBER.TOS), steht die Wahl schon in der
; Befehlszeile, und das Menue entfaellt (MAIN.S, start).
;
; Bedienung: Maus (Linksklick waehlt beim Druecken, wie Thalions Menues),
; Pfeil hoch/runter und Return.
; ===========================================================================

SM_ZEILE_OBEN	equ	3		; Trefferfeld um die Textzeile
SM_ZEILE_UNTEN	equ	8
SM_WEITER	equ	0		; Nummern der Eintraege (intro_daten.i)
SM_NEU		equ	1
SM_INTRO	equ	2
SM_QUIT		equ	3
SM_FARBE	equ	Red		; wie im Original: rote Schrift
SM_FARBE_WAHL	equ	Yellow
SM_FARBE_AUS	equ	27		; Grau aus Main_pal (Layoutfarben)

; ***************************************************************************
; Startmenue -- zeigen, waehlen lassen, Intro_menu_choice setzen.  Kehrt zurueck,
; ausser bei QUIT.
;   IN : a5 = vars, Schirm offen, Maus installiert.
;   Alle Register bleiben.
; ***************************************************************************
Startmenue:
	movem.l	d0-d7/a0-a4,-(sp)
	bsr	sm_weiter_pruefen
	lea	Main_pal,a0		; Bank 0: die Farben der Oberflaeche
	jsr	Bank0_setzen
sm_leeren:
	jsr	Read_Mev		; alte Klicks verwerfen
	tst.w	d2
	bne.b	sm_leeren
	moveq	#SM_NEU,d0		; Vorwahl
	tst.b	sm_weiter
	beq.b	sm_vor
	moveq	#SM_WEITER,d0
sm_vor:	move.w	d0,sm_wahl
	move.w	#-1,sm_mx		; Maus noch nicht gesehen
	bsr	sm_zeichnen

sm_l:	jsr	My_vsync
	bsr	Update_mouse
	; ---- Maus bewegt: der Eintrag darunter wird gewaehlt ----
	move.w	Mouse_X,d0
	move.w	Mouse_Y,d1
	cmp.w	sm_mx,d0
	bne.b	sm_bewegt
	cmp.w	sm_my,d1
	beq.b	sm_klick
sm_bewegt:
	move.w	d0,sm_mx
	move.w	d1,sm_my
	bsr	sm_zeile		; d1 -> d0 = Eintrag oder -1
	bmi.b	sm_klick
	bsr	sm_waehlbar
	beq.b	sm_klick
	cmp.w	sm_wahl,d0
	beq.b	sm_klick
	move.w	d0,sm_wahl
	bsr	sm_zeichnen
	; ---- Klick: beim Druecken (Bit 1, Maus_vbl) ----
sm_klick:
	jsr	Read_Mev
	tst.w	d2
	beq.b	sm_taste
	btst	#1,d2			; links eben gedrueckt ?
	beq.b	sm_klick
	bsr	sm_zeile
	bmi.b	sm_klick
	bsr	sm_waehlbar
	beq.b	sm_klick
	move.w	d0,sm_wahl
	bra.b	sm_nehmen
	; ---- Tasten ----
sm_taste:
	jsr	Read_key		; d0: Amiga-Tastencode in Bit 16-23 (260)
	tst.l	d0
	beq	sm_l
	swap	d0
	cmp.b	#$44,d0			; Return
	beq.b	sm_nehmen_w
	cmp.b	#$43,d0			; Enter
	beq.b	sm_nehmen_w
	moveq	#-1,d1			; hoch
	cmp.b	#$4C,d0
	beq.b	sm_schieben
	moveq	#1,d1			; runter
	cmp.b	#$4D,d0
	bne	sm_l
sm_schieben:
	move.w	sm_wahl,d0
	moveq	#4-1,d7			; hoechstens einmal herum
sm_sch_l:
	add.w	d1,d0
	and.w	#3,d0			; vier Eintraege, im Kreis
	bsr	sm_waehlbar
	dbne	d7,sm_sch_l
	move.w	d0,sm_wahl
	bsr	sm_zeichnen
	bra	sm_l
sm_nehmen_w:
	move.w	sm_wahl,d0
sm_nehmen:
	cmp.w	#SM_QUIT,d0
	bne.b	sm_kein_quit
	jmp	Exit_program
sm_kein_quit:
	cmp.w	#SM_WEITER,d0
	sne	d1			; Weiterspielen 0, Neue Quest 1
	and.w	#1,d1
	move.w	d1,Intro_menu_choice
	; Aufraeumen: Schirm schwarz, Bank 0 schwarz -- Thalions Blenden
	; beginnen wie beim Start ohne Menue.
	move.l	Off_screen,a0
	bsr	Clear_screen
	bsr	Update_screen
	lea	sm_schwarz,a0
	jsr	Bank0_setzen
	movem.l	(sp)+,d0-d7/a0-a4
	rts

; ***************************************************************************
; sm_weiter_pruefen -- gibt es einen Stand zum Weiterspielen?  -> sm_weiter
; Saves (1.20): ein Wort letzter Platz, dann Max_saves Namen zu
; Save_name_length+1 Byte (392 Byte).
; ***************************************************************************
sm_weiter_pruefen:
	movem.l	d0-d2/a0,-(sp)
	sf	sm_weiter
	moveq	#Saves_file,d0
	jsr	Load_file
	tst.l	d0
	beq.b	swp_out
	move.w	d0,d2			; Handle
	jsr	Block_adresse
	move.l	d0,a0
	move.w	(a0)+,d1		; letzter Platz
	beq.b	swp_frei
	cmp.w	#Max_saves,d1
	bhi.b	swp_frei
	st	sm_weiter
swp_frei:
	moveq	#0,d0
	move.w	d2,d0
	jsr	Free_memory
swp_out:
	movem.l	(sp)+,d0-d2/a0
	rts

; ***************************************************************************
; sm_zeile -- welcher Eintrag liegt auf Hoehe d1?  -> d0, -1 = keiner
; (Flags nach d0).  Alle uebrigen Register bleiben.
; ***************************************************************************
sm_zeile:
	movem.l	d2/a0,-(sp)
	lea	Menue_y,a0
	moveq	#0,d0
sz_l:	move.w	(a0)+,d2
	sub.w	#SM_ZEILE_OBEN,d2
	cmp.w	d2,d1
	blt.b	sz_next
	add.w	#SM_ZEILE_OBEN+SM_ZEILE_UNTEN,d2
	cmp.w	d2,d1
	ble.b	sz_out
sz_next:
	addq.w	#1,d0
	cmp.w	Menue_anzahl,d0
	blo.b	sz_l
	moveq	#-1,d0
sz_out:	movem.l	(sp)+,d2/a0
	tst.w	d0
	rts

; ***************************************************************************
; sm_waehlbar -- ist Eintrag d0 waehlbar?  Z = nein.  Register bleiben.
; ***************************************************************************
sm_waehlbar:
	cmp.w	#SM_INTRO,d0
	beq.b	sw_out			; Intro: Z gesetzt, kommt spaeter
	cmp.w	#SM_WEITER,d0
	bne.b	sw_out			; die uebrigen: Z geloescht
	tst.b	sm_weiter		; Weiterspielen: nur mit Stand
sw_out:	rts

; ***************************************************************************
; sm_zeichnen -- alle Eintraege, zentriert, in ihrer Farbe.
; ***************************************************************************
sm_zeichnen:
	movem.l	d0-d4/a0-a2,-(sp)
	move.l	Off_screen,a0
	bsr	Clear_screen
	move.w	#Default_shadow,Shadow_colour
	lea	Menue_texte,a1
	lea	Menue_y,a2
	moveq	#0,d3			; Eintrag
szn_l:	move.w	#SM_FARBE,d4
	move.w	d3,d0
	bsr	sm_waehlbar
	bne.b	szn_an
	move.w	#SM_FARBE_AUS,d4
	bra.b	szn_farbe
szn_an:	cmp.w	sm_wahl,d3
	bne.b	szn_farbe
	move.w	#SM_FARBE_WAHL,d4
szn_farbe:
	move.w	d4,Ink_colour
	move.l	(a1)+,a0		; Text
	moveq	#0,d0			; Laenge
szn_len:
	tst.b	(a0,d0.w)
	beq.b	szn_mitte
	addq.w	#1,d0
	bra.b	szn_len
szn_mitte:
	mulu.w	#6,d0			; Vorschub des Zeichensatzes
	neg.w	d0
	add.w	#SCRW,d0
	lsr.w	#1,d0			; x = (Breite - Laenge) / 2
	move.w	(a2)+,d1
	jsr	Put_text_line
	addq.w	#1,d3
	cmp.w	Menue_anzahl,d3
	blo.b	szn_l
	bsr	Update_screen
	movem.l	(sp)+,d0-d4/a0-a2
	rts

	SECTION	Fast_DATA,data
	even
sm_schwarz:	dcb.w	32,0
	SECTION	Fast_BSS,bss
	even
sm_wahl:	ds.w	1		; gewaehlter Eintrag
sm_mx:		ds.w	1		; Maus beim letzten Blick
sm_my:		ds.w	1
sm_weiter:	ds.b	1		; Weiterspielen moeglich
	even
	SECTION	Program,code

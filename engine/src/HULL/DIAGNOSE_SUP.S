; ***************************************************************************
; DIAGNOSE_SUP.S -- der Diagnoseschirm der Bibliothek und Diagnostics_list1.
; Einheit "bibliothek" (engine.s).
;
; **Wie in AM2_CPU 1.20** (Erkenntnis 267).  Thalions Quelltext ruft drei
; Namen, die in keiner freigegebenen Datei stehen:
;
;   Init_diagnostic_screen   0:$26414
;   DI_Print_text            0:$2646A
;   Exit_diagnostic_screen   0:$26452
;
; Gerufen werden sie von Out_of_memory (DIAGNOST.S), dazu von Teilen, die
; hinter Cheat oder Fingerprint stehen und bei uns nicht uebersetzt werden.
; Der Schirm ist schlicht: der sichtbare Schirm wird geloescht, und darauf
; wird unmittelbar geschrieben, ohne Doppelpuffer.  Die Schreibstelle
; zaehlt in Zeichen (6 Punkte breit) und Zeilen (7 Punkte hoch), nach 28
; Zeilen wartet der Schirm auf einen Mausklick und faengt oben neu an.
;
; **Die Farbe.**  Schriftfarbe 31 in der Bank der Bildzeile.  Gezeichnet wird
; in den sichtbaren Schirm, und fuer den gilt die Rasterliste, die gerade
; gesetzt ist (Letzte_RL, FADE_SUP.S), nicht die des obersten Moduls: das ist
; der Copper des Originals.  Out_of_memory setzt vorher mit Fade_out_all die
; Main_RL; Farbbank (LIBRARY.S) unterscheidet das.
;
; Die Satzbereiche fuer Maus und Clip sind im Original zwei Saetze mit dem
; Vollbild (4:$4DF4, 4:$4884).  Wir nehmen Default_MA (aus AM2_CPU, 4:$491A,
; derselbe Inhalt) und ca_full (EFFECTS_SUP.S).
; ***************************************************************************

	SECTION	Program,code

; ***************************************************************************
; Init_diagnostic_screen -- den sichtbaren Schirm loeschen und zum
; Zeichenziel machen, Schreibstelle oben links, Vollbild fuer Maus und Clip,
; Schriftfarbe 31.  Alle Register bleiben.
; ***************************************************************************
Init_diagnostic_screen:
	move.l	a0,-(sp)
	move.l	Schirm_vorn,a0
	move.l	a0,Work_screen		; erst Zeichenziel, dann loeschen: so
	jsr	Clear_screen		; laesst Zeiger_vbl den Schirm in Ruhe (269)
	bsr	DI_Home
	lea	Default_MA,a0
	jsr	Push_MA
	lea	ca_full,a0
	jsr	Push_CA
	move.w	#31,Ink_colour
	move.l	(sp)+,a0
	rts

; ***************************************************************************
; Exit_diagnostic_screen -- Bereiche herunter, auf einen Klick warten, dann
; Update_screen.  Thalions Main_status springt mit jmp hinein; dann kehrt
; Update_screen zu dessen Aufrufer zurueck, wie im Original.
;   All registers are preserved.
;
; Work_screen bleibt hier stehen, wie bei Thalion: Update_screen tauscht die
; Schirme, und Schirmwechsel setzt Work_screen auf den neuen hinteren.
; ***************************************************************************
Exit_diagnostic_screen:
	jsr	Pop_MA
	jsr	Pop_CA
	jsr	Wait_4_click		; Thalions, HULL/VARIOUS.S
	jmp	Update_screen

; ***************************************************************************
; DI_Print_text -- eine Liste von Zeilen ausgeben.
;   a1 = Liste: Zeilen mit Endnull, die Liste endet mit $FF.
; Jede Zeile wird geschrieben, danach eine neue Zeile.  Alle Register
; bleiben.
; ***************************************************************************
DI_Print_text:
	movem.l	d0/a0-a1,-(sp)
dpt_zeile:
	cmp.b	#-1,(a1)
	beq.b	dpt_ende
	bsr.b	DI_Print
	bsr.b	DI_CR
	move.l	a1,a0
	bsr.b	DI_Strlen
	lea	1(a1,d0.w),a1
	bra.b	dpt_zeile
dpt_ende:
	movem.l	(sp)+,d0/a0-a1
	rts

; ***************************************************************************
; DI_Print -- eine Zeichenkette an die Schreibstelle.  a1 = Text mit
; Endnull.  Die Schreibstelle rueckt um seine Laenge vor.  Alle Register
; bleiben.
; ***************************************************************************
DI_Print:
	movem.l	d0-d1/d7/a0,-(sp)
	move.l	a1,a0
	bsr.b	DI_Strlen
	move.w	d0,d7
	move.w	Di_x,d0
	move.w	Di_y,d1
	mulu.w	#6,d0
	mulu.w	#7,d1
	jsr	Put_text_line
	add.w	d7,Di_x
	movem.l	(sp)+,d0-d1/d7/a0
	rts

; ***************************************************************************
; DI_CR -- neue Zeile.  Nach 28 Zeilen auf einen Klick warten, Schirm
; loeschen, oben weiter.  Alle Register bleiben.
; ***************************************************************************
DI_CR:
	move.l	a0,-(sp)
	clr.w	Di_x
	addq.w	#1,Di_y
	cmp.w	#28,Di_y
	bmi.b	dcr_out
	clr.w	Di_y
	jsr	Wait_4_click
	move.l	Work_screen,a0
	jsr	Clear_screen
dcr_out:
	move.l	(sp)+,a0
	rts

; Schreibstelle nach oben links (0:$265C6).
DI_Home:
	clr.w	Di_x
	clr.w	Di_y
	rts

; Laenge der Zeichenkette in a0 ohne Endnull -> d0 (0:$26696).
DI_Strlen:
	move.l	a0,-(sp)
	moveq	#-1,d0
dsl_l:	addq.l	#1,d0
	tst.b	(a0)+
	bne.b	dsl_l
	move.l	(sp)+,a0
	rts

; ***************************************************************************
; Ladefehler_schirm -- "FILE COULDN'T BE LOADED :", Dateiart und Teil, dann
; Programmende.  Wie in AM2_CPU 0:$2637C (Erkenntnis 268).
;
; Load_subfile springt hierher, wenn der Teil, den Thalion verlangt, im
; Behaelter nicht vorkommt (0:$2510A).  Das ist kein Diskfehler -- die
; laufen ueber Disk_error_handler mit "Nochmal?" --, sondern ein Fehler im
; Programm oder in den Daten; weiter geht es nicht.  Texte und die Namen
; der Dateiarten kommen aus AM2_CPU (am2cpu_auszug.py).  Die Tabelle des
; Originals (4:$4934) zeigt in Schritten zu 22 Byte auf die Namen; wir
; rechnen das aus.
;
;   IN : d0.w = Teil, d1.w = Dateiart (Thalions Nummer).  Kehrt nicht zurueck.
; ***************************************************************************
DATEI_ARTEN	equ	45		; Memory block ... Object graphics
DATEI_ART_LEN	equ	22

Ladefehler_schirm:
	move.w	d0,d2
	move.w	d1,d3
	jsr	Close_current_file
	bsr	Init_diagnostic_screen
	lea	Ladefehler_text,a1
	bsr	DI_Print
	bsr	DI_CR
	bsr	DI_CR
	cmp.w	#DATEI_ARTEN,d3
	bcc.b	lfs_nummer		; unsere Zusatznummern haben keinen Namen
	lea	Datei_arten,a1
	mulu.w	#DATEI_ART_LEN,d3
	add.l	d3,a1
	bsr	DI_Print
lfs_nummer:
	moveq	#0,d0
	move.w	d2,d0
	lea	Di_zahl,a0
	moveq	#" ",d6
	moveq	#5,d7
	jsr	DecR_convert		; Thalions, HULL/NUMERIC.S
	lea	Di_zahl,a1
	bsr	DI_Print
	bsr	Exit_diagnostic_screen	; Klick abwarten
	jmp	Exit_program

; ***************************************************************************
; Farbe0_flackern -- der eine Eintrag in Diagnostics_list1 (0:$263DA).
;
; Das Original schreibt 65536 Werte hintereinander nach COLOR00 und laesst
; den Rand aufflackern: ein Messwerkzeug, das zeigt, wie lange die
; Tastenabfrage braucht.  Hier dasselbe mit Farbe 0 der Videl-Palette.  Auf
; dem Amiga setzt der Copper im naechsten Bild die Farbe zurueck; bei uns
; tut das niemand, also wird sie danach wiederhergestellt.  Alle Register
; bleiben.
; ***************************************************************************
Farbe0_flackern:
	movem.l	d0-d1/d7,-(sp)
	move.l	VIDEL_PAL,d1		; Farbe 0 retten
	moveq	#0,d0
	move.w	#-1,d7
f0f_l:	move.l	d0,VIDEL_PAL
	add.l	#$04080004,d0		; Rot, Gruen, Blau laufen verschieden
	dbf	d7,f0f_l
	move.l	d1,VIDEL_PAL
	movem.l	(sp)+,d0-d1/d7
	rts

; ***************************************************************************
; Diagnostics_list1 -- die Diagnosetasten der Bibliothek, wie in AM2_CPU
; (4:$4DE0): ein Eintrag, Amiga-Taste + "1".  Format wie Thalions
; Diagnostics_list2 (DIAGNOST.S), gelesen von Handle_diagnostics_list
; (HULL/MODULE_C.S): Zeichen, auf Wortgrenze, Routine; Ende mit dc.w 0.
;
; Die Amiga-Taste ist bei uns Help als Vorsatz (Read_key, VARIOUS_SUP.S):
; Help, dann 1.
; ***************************************************************************
	SECTION	Fast_DATA,data
	even
Diagnostics_list1:
	dc.b	"1"
	even
	dc.l	Farbe0_flackern
	dc.w	0

	SECTION	Fast_BSS,bss
	even
Di_x:	ds.w	1			; Schreibstelle in Zeichen
Di_y:	ds.w	1			; in Zeilen
Di_zahl:	ds.b	12		; Zahl fuer den Ladefehlerschirm
	even

	SECTION	Program,code

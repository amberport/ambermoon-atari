; HULL/AREAS.S -- die Bereichsstapel
;
; Print-Area, Mouse-Area und Mauszeiger.  Die Datei des Originals ist nicht
; freigegeben; ihre Schnittstellen stehen in den Aufrufstellen, und die sind
; eindeutig.
;
; **Alle drei sind Stapel, und alle drei nehmen den Satz in a0.**  Open_window
; zeigt es in zwei Zeilen:
;
;     lea.l	Window_area(a4),a0
;     jsr	Push_MA
;     jsr	Push_PA
;
; Ein Fenster bringt seinen Bereich mit, und Close_window nimmt ihn wieder
; herunter.  Genau dasselbe Muster wie beim Modul- und beim Baumstapel: der
; Bildschirm darunter braucht nichts davon zu wissen.
;
; Das Original ruft sie meist ueber die Makros:
;     Push	PA,Status_PA
;     Pop	PA
;
; **Was sich dabei geaendert hat:** unser Push_MA nahm die vier Kanten in
; d0-d3 und hatte keinen Stapel.  Das ging, solange es genau einen Bereich
; gab; mit Fenstern geht es nicht mehr.  Die drei Aufrufstellen sind
; umgestellt, Default_MA legt jetzt einen Satz auf.

MAX_AREA = 8			; Ebenen je Stapel

; ***************************************************************************
; Push_MA, Pop_MA -- the mouse area: the pointer cannot leave the topmost
; rectangle.
;   IN : a0 = the area record (Push_MA only)
;   All registers are preserved.
;
; Den Satz nimmt sie in a0, und zwar denselben, den Push_PA bekommt: die
; ersten vier Worte einer Print-Area sind ihre Kanten, MA_X1, MA_X2, MA_Y1,
; MA_Y2 (Erkenntnis 172).  Open_window uebergibt beiden dieselbe Adresse.
;
; **Der Stapel haelt Zeiger, keine Abschriften** (Erkenntnis 192).  Thalions
; Init_module (HULL/MODULE_C.S) legt die Area eines Moduls auf und ruft
; *danach* ModInit -- und Eye_ModInit, Mouth_ModInit & Co. (ACTIONS.S)
; rechnen erst dort Made_area um die Gruppe herum aus.  Bis 2026-09-28
; kopierte Push_MA die vier Kanten beim Auflegen; der Zeiger blieb dann im
; Bereich des *vorigen* Aufrufs gefangen, am Kartenrand also in der Mitte.
; Jetzt liest Mouse_int die Kanten ueber Maus_bereich bei jedem Paket aus
; dem Satz selbst, und Update_mouse holt den Zeiger einmal je Bild herein.
; ***************************************************************************
Push_MA:
	movem.l	d0/a1/a5,-(sp)
	lea	vars,a5		; aus Thalions Code gerufen (Erk. 177)
	; **Das obere Wort von d0 loeschen.**  Weiter unten steht "add.l d0,a...",
	; und das nimmt das ganze Register mit.  Der Aufrufer hat dort oft
	; etwas stehen, etwa das ASCII-Zeichen einer Taste.  Mit 'q'
	; ($71) zeigte a0 nach mastack+$710008 und las ueber das RAM hinaus
	; (Erkenntnis 168).
	moveq	#0,d0
	move.w	v_masp(a5),d0
	addq.w	#1,d0
	cmp.w	#MAX_AREA,d0
	bcc.b	pma_out
	move.w	d0,v_masp(a5)
	lsl.w	#2,d0			; ein Zeiger je Ebene
	lea	mastack,a1
	add.l	d0,a1
	move.l	a0,(a1)
	bsr	MA_uebernehmen
pma_out:
	movem.l	(sp)+,d0/a1/a5
	rts

Pop_MA:
	movem.l	d0/a0/a5,-(sp)
	lea	vars,a5		; aus Thalions Code gerufen (Erk. 177)
	tst.w	v_masp(a5)
	beq.b	poma_out
	subq.w	#1,v_masp(a5)
	moveq	#0,d0			; oberes Wort loeschen, siehe Push_MA
	move.w	v_masp(a5),d0
	lsl.w	#2,d0
	lea	mastack,a0
	move.l	(a0,d0.l),a0
	bsr	MA_uebernehmen
poma_out:
	movem.l	(sp)+,d0/a0/a5
	rts

; a0 = Satz der Area -> laufender Bereich, Zeiger hereinholen.
MA_uebernehmen:
	move.l	a0,Maus_bereich
	; weiter in Maus_eingrenzen

; ***************************************************************************
; Maus_eingrenzen -- den Zeiger in den laufenden Bereich holen.
;
; Das Hereinholen ist kein Beiwerk: steht der Zeiger schon ausserhalb, bliebe
; er dort liegen, bis die Maus sich bewegt.  Gerufen beim Wechsel der Area
; und von Update_mouse einmal je Bild -- denn ein ModInit kann die Kanten
; aendern, nachdem die Area schon aufliegt (siehe oben).  Alle Register
; bleiben.
; ***************************************************************************
Maus_eingrenzen:
	movem.l	d0-d1/a0,-(sp)
	move.l	Maus_bereich,a0
	move.w	sr,d0
	move.w	#$2700,sr
	move.w	Mouse_X,d1
	cmp.w	MA_X1(a0),d1
	bge.b	mau_lx
	move.w	MA_X1(a0),d1
mau_lx:	cmp.w	MA_X2(a0),d1
	ble.b	mau_sx
	move.w	MA_X2(a0),d1
mau_sx:	move.w	d1,Mouse_X
	move.w	Mouse_Y,d1
	cmp.w	MA_Y1(a0),d1
	bge.b	mau_ly
	move.w	MA_Y1(a0),d1
mau_ly:	cmp.w	MA_Y2(a0),d1
	ble.b	mau_sy
	move.w	MA_Y2(a0),d1
mau_sy:	move.w	d1,Mouse_Y
	move.w	d0,sr
	movem.l	(sp)+,d0-d1/a0
	rts

; ***************************************************************************
; Der ganze Bildschirm als Bereich -- Default_MA.
;
; **Zuruecksetzen, nicht auflegen.**  Default_MA heisst "nichts begrenzt die
; Maus mehr", und die Aufrufer meinen es so: Mouse_install beim Start, und die
; Hauptschleife nach jeder Karten-Aktion (MAIN.S) und nach dem Auge-Modus
; (der vorher eine enge Area auflegt, MAP.S).  Wuerde hier nur *aufgelegt*,
; wuechse der Stapel bei jeder Aktion um einen Eintrag -- nach MAX_AREA (acht)
; Aktionen ist er voll, Push_MA tut dann nichts mehr, und das naechste
; Open_window bekommt seine Area nicht mehr auf den Stapel.  Close_window
; nimmt danach einen falschen Eintrag herunter, und der Zeiger klebt in der
; Ecke einer winzigen Area (genau das Bild, das Mouse_install oben beschreibt).
;
; Also erst den Stapel leeren, dann den einen Vollbild-Eintrag auflegen.  Das
; raeumt zugleich eine liegengebliebene Auge-Area weg.  Fenster stoert das
; nicht: Default_MA wird nie gerufen, solange eines offen ist -- die haengen
; ihre Area ueber Open_window an und nehmen sie mit Close_window wieder ab.
; ***************************************************************************
MA_vollbild:
	movem.l	a0/a5,-(sp)
	lea	vars,a5		; aus Thalions Code gerufen (Erk. 177)
	clr.w	v_masp(a5)		; Stapel leeren
	lea	Default_MA,a0		; absolut: der Satz liegt im Datenabschnitt
	bsr	Push_MA			; -> genau ein Eintrag, Vollbild
	movem.l	(sp)+,a0/a5
	rts

; ***************************************************************************
; Push_Mptr, Pop_Mptr, Change_Mptr -- the mouse pointer as a stack.
;   IN : a0 = Thalion's pointer record (Push_Mptr, Change_Mptr)
;   All registers are preserved.
;
; **a0 ist Thalions Zeigersatz.**  Init_module uebergibt ihn so:
;
;     move.l Mouse_ptr(a1),d0 / bne .Ok1
;     lea.l  Default_Mptr,a0
;     .Do1:  jsr Push_Mptr
;
; Die Saetze sind die des Originals (build/am2cpu_daten.i, aus AM2_CPU
; Hunk 4, tools/am2cpu_auszug.py): Hotspot x, y, dann 16 Zeilen zu drei
; Ebenenworten.  Der Stapel fuehrt ihre Adressen.
; ***************************************************************************
Push_Mptr:
	movem.l	d1/a1/a5,-(sp)
	lea	vars,a5		; aus Thalions Code gerufen (Erk. 177)
	move.w	v_mpsp(a5),d1
	addq.w	#1,d1
	cmp.w	#MAX_AREA,d1
	bcc.b	pmp_out
	move.w	d1,v_mpsp(a5)
	lsl.w	#2,d1
	lea	mpstack,a1
	move.l	a0,(a1,d1.w)
	bsr	Set_mouse_ptr
pmp_out:
	movem.l	(sp)+,d1/a1/a5
	rts

Pop_Mptr:
	movem.l	d1/a0/a5,-(sp)
	lea	vars,a5		; aus Thalions Code gerufen (Erk. 177)
	tst.w	v_mpsp(a5)
	beq.b	pomp_out
	subq.w	#1,v_mpsp(a5)
	move.w	v_mpsp(a5),d1
	lsl.w	#2,d1
	lea	mpstack,a0
	move.l	(a0,d1.w),a0
	bsr	Set_mouse_ptr
pomp_out:
	movem.l	(sp)+,d1/a0/a5
	rts

; Change_Mptr: den obersten Zeiger ersetzen, ohne den Stapel zu veraendern.
; Aufrufer bei Thalion: Action2D_switch (ACTIONS.S), Change_mouse und
; Reset_map_mouse (MAP/MAP.S), je "lea <Satz>,a0 / jsr Change_Mptr".
; a0 = Zeigersatz.  Alle Register bleiben.
Change_Mptr:
	movem.l	d1/a1/a5,-(sp)
	lea	vars,a5		; aus Thalions Code gerufen (Erk. 177)
	move.w	v_mpsp(a5),d1
	lsl.w	#2,d1
	lea	mpstack,a1
	move.l	a0,(a1,d1.w)
	bsr	Set_mouse_ptr
	movem.l	(sp)+,d1/a1/a5
	rts

; ***************************************************************************
; Set_mouse_ptr -- einen Zeigersatz Thalions zum laufenden Zeiger machen.
;
;   IN : a0 = Satz (Hotspot x, y; 16 Zeilen zu drei Ebenenworten)
;   Alle Register bleiben; a5 = vars.
;
; **Die Bibliothek weitet auf**, wie bei jeder Grafik mit weniger Ebenen: aus
; drei Ebenen werden acht, Farbe = Bank der Bildzeile + 24 + Bildwert, 0
; bleibt durchsichtig.  Gezeichnet wird mit dem Hotspot auf der Mausstelle
; (Zeigerecke in LIBRARY.S).
;
; **Die Bank kommt je Bildzeile** (Erkenntnis 266).  Auf dem Amiga ist der
; Zeiger ein Sprite, und seine Farben sind Farbregister, die die Copper je
; Zeile umsetzt: er traegt die Farben 24-31 der Palette, ueber der er steht
; (ueber der Portraitleiste die Graurampe von Main_pal).  Darum stehen die
; Zeigerpunkte hier auch in den Ebenen 5 und 6, und Zeiger_in_puffer laesst
; sie nur, wo die Bank der Zeile das Bit hat.  Bis 266 lag der Zeiger fest
; in Bank 0; im Charaktereditor (eine Palette, Bank 2) war er schwarz.
;
; Aendert sich das Bild, muss der Zeiger neu gesetzt werden, auch wenn die
; Maus steht: zg_neu sagt es Update_mouse.
; ***************************************************************************
Set_mouse_ptr:
	movem.l	d0-d4/d7/a0-a2,-(sp)
	addq.b	#1,zeiger_sperre	; kein halbes Bild im VBL (269)
	cmp.l	zg_satz,a0
	beq.b	smp_out
	move.l	a0,zg_satz
	st	zg_neu
	move.w	(a0)+,zg_hx
	move.w	(a0)+,zg_hy
	lea	zg_bild,a1
	lea	zg_maske,a2
	jsr	Pointer_convert		; FALCON_LIB.S, ST_LIB.S
	move.l	#zg_bild,p_mptr(a5)
	move.l	#zg_maske,p_mmsk(a5)
smp_out:
	subq.b	#1,zeiger_sperre
	movem.l	(sp)+,d0-d4/d7/a0-a2
	rts

	SECTION	Fast_BSS,bss
zg_satz:	ds.l	1		; laufender Zeigersatz
zg_hx:		ds.w	1		; sein Hotspot
zg_hy:		ds.w	1
zg_neu:		ds.b	1		; Bild gewechselt, neu zeichnen
	even
zg_bild:	ds.b	MPTR_SIZE	; aufgeweitet, acht Ebenen
zg_maske:	ds.b	MPTR_SIZE
	even
	SECTION	Program,code

; ***************************************************************************
; **Default_MA ist ein Datensatz, keine Routine.**  Thalions Init_module sagt
; es unmissverstaendlich:
;
;     move.l MA_ptr(a1),d0 / bne .Ok3
;     lea.l  Default_MA,a0
;     .Do3:  jsr Push_MA
;
; Bis zum 2026-09-22 trug diesen Namen bei uns die Routine, die den Stapel
; leert und das Vollbild auflegt -- sie heisst jetzt MA_vollbild.  Haette der
; Name so gestanden, haette Push_MA die Befehlsworte der Routine als
; Koordinaten gelesen; der Linker haette nichts gemerkt.  Dieselbe Falle wie
; bei Number (157) und Put_masked_block (160).
;
; **Der Satz kommt seit 2026-09-29 aus AM2_CPU** (am2cpu_auszug.py, 4:$491A):
; 0,319,0,199, das ganze Bild.  Bis dahin stand hier 0,SCRW-MPTR_W,0,
; SCRH-MPTR_H, damit unser Zeigerzeichnen nicht ueber das Bildende schrieb;
; die Maus erreichte so die letzte Reihe der Taktikflaeche und die untere
; Haelfte der Knoepfe nicht.  Jetzt schneidet Zeiger_in_puffer (LIBRARY.S)
; auch rechts und unten.
; ***************************************************************************

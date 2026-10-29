; ===========================================================================
; CONTROLS_SUP.S -- die Tastengrafik fuer Thalions HULL/CONTROLS.S.
;
;
; Sein Display_up_button adressiert drei Namen mit `lea` und rechnet dabei
; mit Amiga-Massen:
;
;     moveq.l #24,d4 / moveq.l #3,d5 / moveq.l #2,d6 / moveq.l #17,d7
;     lea.l   Button_up,a0
;     jsr     Put_unmasked_block
;     lea.l   Control_icons,a0
;     ... subq.w #1,d3 / mulu.w #13*12,d3 / add.w d3,a0
;     addq.w  #2,d1 / moveq.l #13,d7
;     jsr     Put_masked_block2
;
; **Die 12 ist nicht verhandelbar** -- sie steht in seiner Datei und meint 32
; Punkte zu drei Ebenen.  Die Symbole muessen deshalb im Originalformat
; daliegen; aufgeweitet wird erst beim Zeichnen (LIBRARY.S, Quelle_aufweiten).
;
; Woher die Bytes kommen, ist bei den beiden Teilen verschieden:
;
;   Control_icons  ist die Spieldatei **Button_graphics** -- entpackt exakt
;                  78*156 = 12168 Byte.  Sie wird zur Laufzeit gelesen und
;                  unveraendert hierher kopiert (Leitziel 2).  Thalions
;                  Dateinummern-Aufzaehlung kennt sie nicht; im Original
;                  fuellt die nicht freigegebene Bibliothek Control_icons
;                  daraus (Erkenntnis 131).  Unsere Nummer steht in
;                  FALCON_OFF.S.
;
;   Button_up/down liegt in **keiner** Spieldatei, nur im Amiga-Programm
;                  (AM2_CPU, Hunk 3 ab 0x2860).  tools/am2cpu_auszug.py
;                  holt es beim Bau heraus (build/am2cpu_daten.i); zur
;                  Laufzeit wird AM2_CPU nie gelesen.
;
; Chequered -- die Schraffur fuer gesperrte Tasten -- steht ebenfalls nur in
; AM2_CPU (Hunk 3 ab 0x29F8, 32x11, eine Ebene) und kommt wie Button_up/down
; beim Bau heraus (Erkenntnis 256).  Thalions CONTROLS.S legt sie mit
; Put_masked_silhouette in Window_colour ueber die gesperrte Taste.
; ===========================================================================

	SECTION	Fast_BSS,bss
	even
lt_geladen:	ds.b	1	; Button_graphics schon gelesen?
	even

	SECTION	Program,code

; ***************************************************************************
; Lade_tastengrafik -- fuellt Control_icons aus Button_graphics, einmal beim
; Start (MAIN.S).
;
; Alle Register bleiben.  Fehlt die Datei, bleibt der Block null -- dann
; zeichnet Put_masked_block2 nichts, statt Muell zu zeichnen.
; ***************************************************************************
Lade_tastengrafik:
	movem.l	d0-d3/a0-a2,-(sp)

; ---- Symbole aus Button_graphics, einmal ----
.symbole:
	tst.b	lt_geladen
	bne.b	.raus
	st	lt_geladen		; auch ein Fehlschlag wird nicht wiederholt
	moveq	#Button_gfx_file,d0
	bsr	Load_file
	tst.l	d0
	beq.b	.raus
	move.w	d0,d3			; Handle merken
	bsr	Get_memory_length
	move.l	d0,d2			; tatsaechliche Laenge
	moveq	#0,d0
	move.w	d3,d0
	bsr	Block_adresse
	move.l	d0,a0
	; Nie mehr kopieren, als das Feld traegt -- es fasst 128 Symbole.
	cmp.l	#128*CI_ROH_LEN,d2
	bls.b	.laenge_ok
	move.l	#128*CI_ROH_LEN,d2
.laenge_ok:
	subq.l	#1,d2
	bmi.b	.freigeben
	lea	Control_icons,a1
.kopieren:
	move.b	(a0)+,(a1)+
	dbf	d2,.kopieren		; hoechstens 19968 -- passt in dbf
.freigeben:
	moveq	#0,d0
	move.w	d3,d0
	bsr	Free_memory
.raus:
	movem.l	(sp)+,d0-d3/a0-a2
	rts

	SECTION	Fast_BSS,bss
	even
Control_icons:	ds.b	128*CI_ROH_LEN	; aus Button_graphics, Lade_tastengrafik
	even
	SECTION	Program,code

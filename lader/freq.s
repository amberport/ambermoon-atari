; freq.s -- FREQ.TOS: misst die Bildfrequenz des Rechners (50 oder 60 Hz).
;
; Zaehlt fuenf Sekunden lang die VBLs (_frclock) gegen die Uhr des TOS
; (_hz_200, Timer C, 200 je Sekunde) und zeigt das Ergebnis mit einer
; Nachkommastelle.  Fuer die Messdateien der Intros (docs/11 7.6): Thalion
; taktet in VBLs, und ein Bild von 3 VBL dauert bei 60 Hz 50 ms, bei 50 Hz
; 60 ms.  Nur 68000-Befehle, laeuft auch auf dem ST.

Cconws		equ	9
Crawcin		equ	7
Super		equ	$20
Pterm0		equ	0
FRCLOCK		equ	$466		; VBLs seit dem Start (TOS)
HZ200		equ	$4BA		; Takte von Timer C, 200 je Sekunde
DAUER		equ	1000		; 5 Sekunden

	SECTION	Freq_code,code
start:
	pea	Text_start
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp

	clr.l	-(sp)			; Supervisor: die Systemvariablen
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,Alter_ssp
	move.l	HZ200.w,d1		; auf den naechsten Takt warten
.sync:	cmp.l	HZ200.w,d1
	beq.b	.sync
	move.l	HZ200.w,d1
	move.l	FRCLOCK.w,d2
.warten:
	move.l	HZ200.w,d0
	sub.l	d1,d0
	cmp.l	#DAUER,d0
	blo.b	.warten
	move.l	FRCLOCK.w,d3
	move.l	HZ200.w,d4
	sub.l	d2,d3			; VBLs
	sub.l	d1,d4			; Takte
	move.l	d3,Vbls
	move.l	d4,Takte
	move.l	Alter_ssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp

	lea	Text_puffer,a1
	lea	Text_vbls,a0
	bsr	Anhaengen
	move.l	Vbls,d0
	bsr	Zahl
	lea	Text_takte,a0
	bsr	Anhaengen
	move.l	Takte,d0
	bsr	Zahl
	lea	Text_frequenz,a0
	bsr	Anhaengen
	move.l	Vbls,d0			; Zehntel Hz: VBLs * 2000 / Takte
	mulu.w	#2000,d0
	move.l	Takte,d1
	move.l	d1,d2
	lsr.l	#1,d2
	add.l	d2,d0
	divu.w	d1,d0
	and.l	#$FFFF,d0
	divu.w	#10,d0			; Rest: Zehntel
	move.l	d0,-(sp)
	and.l	#$FFFF,d0
	bsr	Zahl
	move.b	#',',(a1)+
	move.l	(sp)+,d0
	swap	d0
	add.b	#'0',d0
	move.b	d0,(a1)+
	lea	Text_ende,a0
	bsr	Anhaengen
	pea	Text_puffer
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
	move.w	#Pterm0,-(sp)
	trap	#1

; Anhaengen -- a0 (mit Null) nach a1, a1 dahinter.
Anhaengen:
	move.b	(a0)+,(a1)+
	bne.b	Anhaengen
	subq.l	#1,a1
	rts

; Zahl -- d0.w ohne Vorzeichen dezimal nach a1, a1 dahinter.
;   Veraendert d0-d2.
Zahl:
	moveq	#0,d2			; Ziffern auf dem Stapel
.teile:	and.l	#$FFFF,d0
	divu.w	#10,d0
	swap	d0
	move.w	d0,-(sp)
	swap	d0
	addq.w	#1,d2
	tst.w	d0
	bne.b	.teile
	subq.w	#1,d2
.schreib:
	move.w	(sp)+,d0
	add.b	#'0',d0
	move.b	d0,(a1)+
	dbf	d2,.schreib
	move.b	#0,(a1)
	rts

	SECTION	Freq_daten,data
Text_start:	dc.b	13,10,"Bildfrequenz messen (5 Sekunden) ...",13,10,0
Text_vbls:	dc.b	"VBLs: ",0
Text_takte:	dc.b	" in 200-Hz-Takten: ",0
Text_frequenz:	dc.b	13,10,"Bildfrequenz: ",0
Text_ende:	dc.b	" Hz",13,10,"Taste druecken.",13,10,0
	even

	SECTION	Freq_bss,bss
Alter_ssp:	ds.l	1
Vbls:		ds.l	1
Takte:		ds.l	1
Text_puffer:	ds.b	128

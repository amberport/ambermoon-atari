; ***************************************************************************
; INTRO_CLOUDS.S -- our clouds before the menu (K3, tools/amiga_programm.py;
; docs/11-Intro-Extro.md 7.8b).
;
; Thalion's cloud loop ($DD2-$F32) draws per frame two columns of the menu
; picture (Clouds_column) and then four clouds with the blitter ($4E2A):
; the left one (hunk 4 $1BF88) at x and the right one ($1E288) at 208 - x,
; each at y = 0 and y = 128.  A cloud is 7 words wide and 128 lines high,
; per line 4 planes and a mask (5 x 14 bytes, Thalion's format); the blit
; is $CA, D = mask ? cloud : screen, planes 0-3, clipped at both edges
; of the screen to the pixel.  On the Amiga that is cheap.  Through our
; software blitter it took most of a frame (T66: slow, and the late frames
; drew into the picture still shown).
;
; For the intros goal 1 may give way at bottlenecks (user, 2026-10-04; for
; the clouds 2026-10-29: "flüssig", own code and Falcon format, visually
; the same).  Clouds_prepare shifts both clouds once at the start into all
; 16 positions, in the target's format: per line 8 groups of 16 pixels,
; each the inverted mask (long, both words alike) and planes 0-3 (two
; longs), the cloud already masked.  Clouds_draw (K3 at $E3A) then puts
; the four clouds straight into the target of the drawing screen: a group
; the mask covers whole is written, one it leaves free is skipped, only
; the others read the target.  Same result as Thalion's blits, pixel for
; pixel; planes 4-7 of the target stay.
; ***************************************************************************

CW_BREITE	equ	7		; Thalion's cloud: words per plane and line
CW_QUELLZEILE	equ	5*CW_BREITE*2	; 4 planes and the mask
CW_ZEILEN	equ	128
CW_GRUPPEN	equ	CW_BREITE+1	; with the shift
CW_GRUPPE	equ	12		; ~mask.l, planes 0-1.l, planes 2-3.l
CW_ZEILE	equ	CW_GRUPPEN*CW_GRUPPE
CW_SCHIEBUNG	equ	CW_ZEILEN*CW_ZEILE
CW_WOLKE	equ	16*CW_SCHIEBUNG

; ***************************************************************************
; Clouds_prepare -- both clouds from hunk 4 into Clouds_left and
; Clouds_right, all 16 shifts.  At the start, before anything is shown.
;   Changes d0-d7/a0-a3.
; ***************************************************************************
Clouds_prepare:
	lea	Intro_h4+$1BF88,a0
	lea	Clouds_left,a1
	bsr.b	Cloud_shift
	lea	Intro_h4+$1E288,a0
	lea	Clouds_right,a1

; Cloud_shift -- a0 = Thalion's cloud, a1 = its table (CW_WOLKE bytes).
Cloud_shift:
	moveq	#0,d7			; shift
.schieb:
	move.l	a0,a2			; source line
	move.w	#CW_ZEILEN-1,d6
.zeile:
	moveq	#0,d5			; group
.gruppe:
	lea	4*CW_BREITE*2(a2),a3	; the mask
	bsr.b	.wort
	not.w	d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	d0,(a1)+
	move.l	a2,a3			; planes 0-3
	moveq	#4-1,d4
.ebene:	bsr.b	.wort
	move.w	d0,(a1)+
	lea	CW_BREITE*2(a3),a3
	dbf	d4,.ebene
	addq.w	#1,d5
	cmp.w	#CW_GRUPPEN,d5
	blo.b	.gruppe
	lea	CW_QUELLZEILE(a2),a2
	dbf	d6,.zeile
	addq.w	#1,d7
	cmp.w	#16,d7
	blo.b	.schieb
	rts

; .wort -- d0.w = group d5 of the row a3 (CW_BREITE words), shifted right
; by d7: the word before in the high half, the word in the low half.
;   Changes d0-d1.
.wort:	moveq	#0,d0
	move.w	d5,d1
	add.w	d1,d1
	tst.w	d5
	beq.b	.erstes
	move.w	-2(a3,d1.w),d0
	swap	d0
.erstes:
	cmp.w	#CW_BREITE,d5
	bhs.b	.schieben
	move.w	0(a3,d1.w),d0
.schieben:
	lsr.l	d7,d0
	rts

; ***************************************************************************
; Clouds_draw -- K3 at $E3A, where Thalion's four cloud blits begin (up to
; $EB2): the four clouds into the target of the drawing screen
; (Intro_h5+$18), in Thalion's order.  The buffer lines are no longer
; valid then; Clouds_column, which Thalion calls twice just before in the
; same frame ($E2E, $E36), has marked all of them.  Outside the table
; Thalion's way.
; Thalion uses no register from here on; a6 = Amiga_register as Thalion's
; blits leave it.  Covered: lea Intro_h4+$1BF88,a0.
; ***************************************************************************
Clouds_draw:
	movem.l	d0-d7/a0-a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	bsr	Ziel_frei		; stale lines: Clouds_column, just before
	move.w	Intro_h5+$12140,d0	; x of the left cloud
	moveq	#0,d1
	lea	Clouds_left,a0
	bsr.b	Cloud_put
	move.w	Intro_h5+$12140,d0
	move.w	#CW_ZEILEN,d1
	lea	Clouds_left,a0
	bsr.b	Cloud_put
	move.w	#208,d0			; the right one
	sub.w	Intro_h5+$12140,d0
	moveq	#0,d1
	lea	Clouds_right,a0
	bsr.b	Cloud_put
	move.w	#208,d0
	sub.w	Intro_h5+$12140,d0
	move.w	#CW_ZEILEN,d1
	lea	Clouds_right,a0
	bsr.b	Cloud_put
	movem.l	(sp)+,d0-d7/a0-a5
	lea	Amiga_register,a6
	jmp	Intro_h0+$EB2
.thalion:
	movem.l	(sp)+,d0-d7/a0-a5
	lea	Intro_h4+$1BF88,a0
	jmp	Intro_h0+$E40

; Cloud_put -- one cloud: d0.w = x (may lie left of or beyond the screen),
; d1.w = y, a0 = its table, a5 = the screen.
;   Changes d0-d7/a0-a3.
Cloud_put:
	moveq	#15,d2
	and.w	d0,d2			; shift
	asr.w	#4,d0			; first group on the screen, may be < 0
	moveq	#0,d3			; first group of the cloud
	tst.w	d0
	bpl.b	.links
	move.w	d0,d3
	neg.w	d3
.links:	moveq	#AMIGA_WORTE-1,d4	; last group of the cloud
	sub.w	d0,d4
	cmp.w	#CW_GRUPPEN-1,d4
	ble.b	.rechts
	moveq	#CW_GRUPPEN-1,d4
.rechts:
	sub.w	d3,d4			; groups - 1
	bmi.b	.aus
	mulu.w	#CW_SCHIEBUNG,d2
	add.l	d2,a0
	move.w	d3,d2
	mulu.w	#CW_GRUPPE,d2
	add.l	d2,a0
	move.l	SCH_ZIEL(a5),a1
	mulu.w	#ZIEL_ZEILE,d1
	add.l	d1,a1
	add.w	d3,d0
	mulu.w	#ZIEL_WORT,d0
	add.l	d0,a1
	moveq	#-1,d5			; ~mask of a free group
	move.w	#CW_ZEILEN-1,d7
.zeile:	move.l	a0,a2
	move.l	a1,a3
	move.w	d4,d6
.gruppe:
	move.l	(a2)+,d0
	beq.b	.voll
	cmp.l	d5,d0
	beq.b	.frei
	move.l	(a3),d1			; planes 0-1
	and.l	d0,d1
	or.l	(a2)+,d1
	move.l	d1,(a3)+
	move.l	(a3),d1			; planes 2-3
	and.l	d0,d1
	or.l	(a2)+,d1
	move.l	d1,(a3)
	lea	ZIEL_WORT-4(a3),a3
	dbf	d6,.gruppe
	bra.b	.weiter
.voll:	move.l	(a2)+,(a3)+
	move.l	(a2)+,(a3)
	lea	ZIEL_WORT-4(a3),a3
	dbf	d6,.gruppe
	bra.b	.weiter
.frei:	addq.l	#8,a2
	lea	ZIEL_WORT(a3),a3
	dbf	d6,.gruppe
.weiter:
	lea	CW_ZEILE(a0),a0
	lea	ZIEL_ZEILE(a1),a1
	dbf	d7,.zeile
.aus:	rts

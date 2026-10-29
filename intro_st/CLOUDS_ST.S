; ***************************************************************************
; CLOUDS_ST.S -- our clouds before the menu on the ST (K3,
; tools/intro_st_program.py; the Falcon's method, intro/INTRO_CLOUDS.S on
; falcon-tempo, docs/11 7.8b).  No SECTION of its own: it lies in the code
; of INTRO_ST.S.
;
; Thalion's cloud loop ($DD2-$F32) draws per frame two columns of the menu
; picture (Clouds_column) and then four clouds with the blitter ($4E2A):
; the left one (hunk 4 $1BF88) at x and the right one ($1E288) at 208 - x,
; each at y = 0 and y = 128.  A cloud is 7 words wide and 128 lines high,
; per line 4 planes and a mask (5 x 14 bytes, Thalion's format); the blit
; is $CA, D = mask ? cloud : screen, planes 0-3, clipped at both edges of
; the screen to the pixel.  Through our $CA way (Way_ca) it took about 140
; cycles a word, 4 x 4096 words a frame: about 14 VBL where Thalion wants 2
; (T97, finding 247: the clouds very slow).
;
; For the intros goal 1 may give way at bottlenecks (user, 2026-10-04; for
; the clouds 2026-10-29, the Falcon's way).  Clouds_prepare shifts both
; clouds once at the start into all 16 positions, in the ST's format: per
; line 8 groups of 16 pixels, each the inverted mask (long, both words
; alike) and planes 0-3 (two longs, as in the ST screen), the cloud
; masked.  Clouds_draw (K3 at $E3A) then puts the four clouds straight
; into the target of the drawing screen: a group the mask covers whole is
; written, one it leaves free is skipped, only the others read the target.
; Same result as Thalion's blits, pixel for pixel, in the rows the target
; has (ST_LINES); Thalion's rows below it (248-255 of the lower clouds) are
; never shown and get no cloud.
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3: the clouds drawn by
; our code from a shifted copy.
; ***************************************************************************

CL_WIDTH	equ	7		; Thalion's cloud: words per plane and line
CL_SOURCE_LINE	equ	5*CL_WIDTH*2	; 4 planes and the mask
CL_ROWS		equ	128
CL_GROUPS	equ	CL_WIDTH+1	; with the shift
CL_GROUP	equ	12		; ~mask.l, planes 0-1.l, planes 2-3.l
CL_LINE		equ	CL_GROUPS*CL_GROUP
CL_SHIFT	equ	CL_ROWS*CL_LINE
CL_CLOUD	equ	16*CL_SHIFT

; ***************************************************************************
; Clouds_prepare -- both clouds from hunk 4 into Clouds_left and
; Clouds_right, all 16 shifts.  At the start, before anything is shown.
;   Changes d0-d7/a0-a4.
; ***************************************************************************
Clouds_prepare:
	lea	Intro_h4+$1BF88,a0
	lea	Clouds_left,a1
	bsr.b	Cloud_shift
	lea	Intro_h4+$1E288,a0
	lea	Clouds_right,a1

; Cloud_shift -- a0 = Thalion's cloud, a1 = its table (CL_CLOUD bytes).
Cloud_shift:
	moveq	#0,d7			; shift
.shift:	move.l	a0,a2			; source line
	move.w	#CL_ROWS-1,d6
.row:	lea	4*CL_WIDTH*2(a2),a3	; the mask first
	move.l	a1,a4
	bsr.b	.mask
	moveq	#4,d4			; then planes 0-3: offset in the group
	move.l	a2,a3
.plane:	move.l	a1,a4
	bsr.b	.plane_words
	addq.w	#2,d4
	cmp.w	#CL_GROUP,d4
	blo.b	.plane
	lea	CL_SOURCE_LINE(a2),a2
	lea	CL_LINE(a1),a1
	dbf	d6,.row
	addq.w	#1,d7
	cmp.w	#16,d7
	blo.b	.shift
	rts

; .mask -- the 7 mask words at a3 shifted right by d7 into the 8 groups at
; a4, inverted, in both words.  Changes d0-d2/a3-a4.
.mask:	moveq	#0,d1
	moveq	#CL_GROUPS-1,d2
.m:	swap	d1			; the word before in the high half
	clr.w	d1
	tst.w	d2
	beq.b	.m_last			; the eighth group: shifted in only
	move.w	(a3)+,d1
.m_last:
	move.l	d1,d0
	lsr.l	d7,d0
	not.w	d0
	move.w	d0,(a4)+
	move.w	d0,(a4)+
	lea	CL_GROUP-4(a4),a4
	dbf	d2,.m
	rts

; .plane_words -- the 7 words of a plane at a3 (a3 then on to the next
; plane) shifted right by d7 into the 8 groups at a4 + d4, masked with the
; group's mask.  Changes d0-d3/a3-a4.
.plane_words:
	moveq	#0,d1
	moveq	#CL_GROUPS-1,d2
.p:	swap	d1
	clr.w	d1
	tst.w	d2
	beq.b	.p_last
	move.w	(a3)+,d1
.p_last:
	move.l	d1,d0
	lsr.l	d7,d0
	move.w	(a4),d3			; ~mask
	not.w	d3
	and.w	d3,d0
	move.w	d0,0(a4,d4.w)
	lea	CL_GROUP(a4),a4
	dbf	d2,.p
	rts

; ***************************************************************************
; Clouds_draw -- K3 at $E3A, where Thalion's four cloud blits begin (up to
; $EB2): the four clouds into the target of the drawing screen
; (Intro_h5+$18), in Thalion's order, once the Shifter no longer shows it
; (Target_free).  Outside the table Thalion's way.
; Thalion uses no register from here on; a6 = Amiga_register as Thalion's
; blits leave it.  Covered: lea Intro_h4+$1BF88,a0.
; ***************************************************************************
Clouds_draw:
	movem.l	d0-d7/a0-a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Screen_find
	beq.b	.thalion
	cmp.w	#4,SC_PLANES(a5)
	bne.b	.thalion
	bsr	Target_free
	moveq	#0,d0			; first: the buffer rows do not hold
	move.w	SC_ROWS(a5),d1
	bsr	Rows_invalid
	move.w	Intro_h5+$12140,d0	; x of the left cloud
	moveq	#0,d1
	lea	Clouds_left,a0
	bsr.b	Cloud_put
	move.w	Intro_h5+$12140,d0
	move.w	#CL_ROWS,d1
	lea	Clouds_left,a0
	bsr.b	Cloud_put
	move.w	#208,d0			; the right one
	sub.w	Intro_h5+$12140,d0
	moveq	#0,d1
	lea	Clouds_right,a0
	bsr.b	Cloud_put
	move.w	#208,d0
	sub.w	Intro_h5+$12140,d0
	move.w	#CL_ROWS,d1
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
	bpl.b	.left
	move.w	d0,d3
	neg.w	d3
.left:	moveq	#AMIGA_ROW/2-1,d4	; last group of the cloud
	sub.w	d0,d4
	cmp.w	#CL_GROUPS-1,d4
	ble.b	.right
	moveq	#CL_GROUPS-1,d4
.right:	sub.w	d3,d4			; groups - 1
	bmi.b	.out
	move.w	SC_ROWS(a5),d7		; rows in the target
	sub.w	d1,d7
	ble.b	.out
	cmp.w	#CL_ROWS,d7
	bls.b	.rows
	move.w	#CL_ROWS,d7
.rows:	subq.w	#1,d7
	mulu.w	#CL_SHIFT,d2
	add.l	d2,a0
	move.w	d3,d2
	mulu.w	#CL_GROUP,d2
	add.l	d2,a0
	move.l	SC_TARGET(a5),a1
	mulu.w	#ST_LINE,d1
	add.l	d1,a1
	add.w	d3,d0
	lsl.w	#3,d0			; 8 bytes a group
	add.w	d0,a1
	moveq	#-1,d5			; ~mask of a free group
.row:	move.l	a0,a2
	move.l	a1,a3
	move.w	d4,d6
.group:	move.l	(a2)+,d0
	beq.b	.full
	cmp.l	d5,d0
	beq.b	.free
	move.l	(a3),d1			; planes 0-1
	and.l	d0,d1
	or.l	(a2)+,d1
	move.l	d1,(a3)+
	move.l	(a3),d1			; planes 2-3
	and.l	d0,d1
	or.l	(a2)+,d1
	move.l	d1,(a3)+
	dbf	d6,.group
	bra.b	.next
.full:	move.l	(a2)+,(a3)+
	move.l	(a2)+,(a3)+
	dbf	d6,.group
	bra.b	.next
.free:	addq.l	#8,a2
	addq.l	#8,a3
	dbf	d6,.group
.next:	lea	CL_LINE(a0),a0
	lea	ST_LINE(a1),a1
	dbf	d7,.row
.out:	rts

; ***************************************************************************
; Menu_st_convert -- the unpacked menu picture (Intro_h5+$12206, Thalion's
; format, 4 planes row by row) into Menu_st in ST format, ST_LINES rows,
; once per clouds scene (Clouds_column; Clouds_begin clears Menu_st_ready).
; Clouds_column then copies whole groups.
;   All registers are preserved.
; ***************************************************************************
Menu_st_convert:
	movem.l	d6-d7/a0-a3,-(sp)
	move.l	Intro_h5+$12206,a0
	lea	Menu_st,a1
	move.w	#ST_LINES-1,d7
.row:	move.l	a0,a2
	moveq	#AMIGA_ROW/2-1,d6
.w:	move.w	(a2),(a1)+
	move.w	AMIGA_ROW(a2),(a1)+
	move.w	2*AMIGA_ROW(a2),(a1)+
	move.w	3*AMIGA_ROW(a2),(a1)+
	addq.l	#2,a2
	dbf	d6,.w
	lea	AMIGA_LINE(a0),a0
	dbf	d7,.row
	st	Menu_st_ready
	movem.l	(sp)+,d6-d7/a0-a3
	rts

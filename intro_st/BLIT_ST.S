; ***************************************************************************
; BLIT_ST.S -- the Amiga blitter in software, on Thalion's Amiga-format
; buffers (K2: K2_trap calls Amiga_blit once Thalion has written BLTSIZE).
;
; The whole blit runs before Thalion's code goes on, so DMACONR never
; shows a busy blitter.  Channels A-D with their pointers and modulos,
; first and last word mask on A, the shifts of A and B, descending mode,
; any minterm; the "old" word of A and B carries over from row to row as
; in the hardware.  After the blit the pointers of the used channels stand
; behind it (Thalion blits column by column with one BLTDPT, docs/11 4.6).
; Not there: line mode and fill mode (not seen in the intro; counted in
; Blit_unsupported, the blit is left out).
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3 (K2).
;
; Fast paths: clear (D only, minterm $00), copy (A to D, minterm $F0,
; no shift, no mask, ascending) and the masked blit (A B C D, minterm $CA,
; ascending).
; ***************************************************************************

; Blit_vars (a5)
BV_FWM		equ	0
BV_LWM		equ	2
BV_ASH		equ	4
BV_BSH		equ	6
BV_WIDTH	equ	8		; words - 1
BV_ROWS		equ	10		; rows left - 1
BV_AMOD		equ	12
BV_BMOD		equ	14
BV_CMOD		equ	16
BV_DMOD		equ	18
BV_ADAT		equ	20
BV_BDAT		equ	22
BV_CDAT		equ	24
BV_LF		equ	26		; minterm
BV_USE		equ	28		; BLTCON0 bits 11-8: A B C D
BV_SIZE		equ	30

USE_A		equ	3		; bits of BV_USE
USE_B		equ	2
USE_C		equ	1
USE_D		equ	0

; ***************************************************************************
; Amiga_blit -- the blit Thalion set up in Amiga_register.  While screens
; are shown directly (TARGET_ST.S), Blit_redirect decides where it goes.
;   Changes d0-d7/a0-a6.
; ***************************************************************************
Amiga_blit:
	lea	Amiga_register,a6
	move.w	AR_BLTCON1(a6),d0
	and.w	#$19,d0			; line mode, fill modes
	beq.b	.ok
	addq.w	#1,Blit_unsupported
	rts
.ok:	tst.l	Direct_to
	bne	Blit_redirect
; Blit_amiga -- the blit on Thalion's memory, as the Amiga blitter does it.
Blit_amiga:
	bsr	Blit_decode
	btst	#1,AR_BLTCON1+1(a6)	; descending
	bne	Blit_generic
	ifd	CHECK_BLIT
	bsr	Blit_check
	endc
Blit_fast:
	move.w	BV_USE(a5),d0
	cmp.w	#1<<USE_D,d0
	bne.b	.copy
	tst.b	BV_LF+1(a5)		; minterm $00: clear
	bne	Blit_generic
	bra	Blit_clear
.copy:	cmp.w	#$F,d0			; A B C D, minterm $CA: masked blit
	bne.b	.copy2
	cmp.b	#$CA,BV_LF+1(a5)
	beq	Blit_ca
	bra	Blit_generic
.copy2:	cmp.w	#(1<<USE_A)|(1<<USE_D),d0
	bne	Blit_generic
	cmp.b	#$F0,BV_LF+1(a5)
	bne	Blit_generic
	tst.w	BV_ASH(a5)
	bne	Blit_generic
	cmp.l	#$FFFFFFFF,BV_FWM(a5)	; both masks
	bne	Blit_generic
	bra	Blit_copy

; ***************************************************************************
; Blit_decode -- Amiga_register into Blit_vars (a5) and the four channel
; pointers a0-a3 (A B C D, bit 0 cleared as the blitter does); a6 =
; Amiga_register.  Changes d0-d1/a0-a3/a5-a6.
; ***************************************************************************
Blit_decode:
	lea	Amiga_register,a6
	lea	Blit_vars,a5
	move.w	AR_BLTSIZE(a6),d0
	move.w	d0,d1
	lsr.w	#6,d0			; rows, 0 = 1024
	subq.w	#1,d0
	and.w	#$3FF,d0
	move.w	d0,BV_ROWS(a5)
	and.w	#$3F,d1			; words, 0 = 64
	subq.w	#1,d1
	and.w	#$3F,d1
	move.w	d1,BV_WIDTH(a5)
	move.w	AR_BLTCON0(a6),d0
	move.w	d0,d1
	and.w	#$FF,d1
	move.w	d1,BV_LF(a5)
	move.w	d0,d1
	lsr.w	#8,d1
	and.w	#$F,d1
	move.w	d1,BV_USE(a5)
	rol.w	#4,d0
	and.w	#15,d0
	move.w	d0,BV_ASH(a5)
	move.w	AR_BLTCON1(a6),d0
	rol.w	#4,d0
	and.w	#15,d0
	move.w	d0,BV_BSH(a5)
	move.w	AR_BLTAFWM(a6),BV_FWM(a5)
	move.w	AR_BLTALWM(a6),BV_LWM(a5)
	move.w	AR_BLTAMOD(a6),BV_AMOD(a5)
	move.w	AR_BLTBMOD(a6),BV_BMOD(a5)
	move.w	AR_BLTCMOD(a6),BV_CMOD(a5)
	move.w	AR_BLTDMOD(a6),BV_DMOD(a5)
	move.w	AR_BLTADAT(a6),BV_ADAT(a5)
	move.w	AR_BLTBDAT(a6),BV_BDAT(a5)
	move.w	AR_BLTCDAT(a6),BV_CDAT(a5)
	moveq	#-2,d0			; the blitter ignores bit 0 of its pointers
	move.l	AR_BLTAPT(a6),d1
	and.l	d0,d1
	move.l	d1,a0
	move.l	AR_BLTBPT(a6),d1
	and.l	d0,d1
	move.l	d1,a1
	move.l	AR_BLTCPT(a6),d1
	and.l	d0,d1
	move.l	d1,a2
	move.l	AR_BLTDPT(a6),d1
	and.l	d0,d1
	move.l	d1,a3
	addq.l	#1,Blit_count
	rts

	ifd	CHECK_BLIT
; ***************************************************************************
; Blit_check -- CHECK_BLIT: a blit that takes a fast path runs the generic
; way first; its D rows are kept, the memory put back, then the fast path
; runs (Amiga_blit goes on) and Blit_compare compares.  Blits not on a fast
; path, descending ones and ones whose D area exceeds the buffer are left.
; ***************************************************************************
BC_MAX		equ	64*1024

Blit_check:
	sf	Blit_checking
	move.w	BV_USE(a5),d0
	btst	#USE_D,d0
	beq	.out
	; D area: rows * (2 * words + DMOD), ascending
	move.w	BV_WIDTH(a5),d1
	addq.w	#1,d1
	add.w	d1,d1
	add.w	BV_DMOD(a5),d1
	ext.l	d1
	moveq	#0,d2
	move.w	BV_ROWS(a5),d2
	addq.l	#1,d2
	muls	d2,d1
	ble	.out
	cmp.l	#BC_MAX,d1
	bhi	.out
	move.l	d1,Bc_bytes
	move.l	a3,Bc_area
	; keep memory, registers and pointers as they are
	move.l	a3,a0
	lea	Bc_before,a1
	bsr	Bc_copy
	movem.l	AR_BLTAPT(a6),d0-d1	; APT, DPT (BLTAPT $50, BLTDPT $54)
	movem.l	d0-d1,Bc_ad
	move.l	AR_BLTBPT(a6),Bc_b
	move.l	AR_BLTCPT(a6),Bc_c
	lea	Blit_vars,a0
	lea	Bc_vars,a1
	moveq	#BV_SIZE/2-1,d0
.v:	move.w	(a0)+,(a1)+
	dbf	d0,.v
	; the generic way
	lea	Blit_vars,a5
	move.l	Bc_ad,a0
	move.l	Bc_b,a1
	move.l	Bc_c,a2
	move.l	Bc_ad+4,a3
	moveq	#-2,d0
	move.l	a0,d1
	and.l	d0,d1
	move.l	d1,a0
	move.l	a1,d1
	and.l	d0,d1
	move.l	d1,a1
	move.l	a2,d1
	and.l	d0,d1
	move.l	d1,a2
	move.l	a3,d1
	and.l	d0,d1
	move.l	d1,a3
	bsr	Blit_generic
	move.l	Bc_area,a0
	lea	Bc_generic,a1
	move.l	Bc_bytes,d1
	bsr	Bc_copy
	lea	Bc_before,a0		; memory back
	move.l	Bc_area,a1
	bsr	Bc_copy
	lea	Bc_vars,a0		; variables and registers back
	lea	Blit_vars,a1
	moveq	#BV_SIZE/2-1,d0
.w:	move.w	(a0)+,(a1)+
	dbf	d0,.w
	movem.l	Bc_ad,d0-d1
	move.l	d0,AR_BLTAPT(a6)
	move.l	d1,AR_BLTDPT(a6)
	move.l	Bc_b,AR_BLTBPT(a6)
	move.l	Bc_c,AR_BLTCPT(a6)
	lea	Blit_vars,a5
	moveq	#-2,d0
	move.l	Bc_ad,d1
	and.l	d0,d1
	move.l	d1,a0
	move.l	Bc_b,d1
	and.l	d0,d1
	move.l	d1,a1
	move.l	Bc_c,d1
	and.l	d0,d1
	move.l	d1,a2
	move.l	Bc_ad+4,d1
	and.l	d0,d1
	move.l	d1,a3
	st	Blit_checking
	; the fast path, then compare: our caller's rts goes to Blit_compare
	move.l	(sp)+,d0		; drop the return into Amiga_blit
	pea	Blit_compare
	move.l	d0,-(sp)
.out:	rts

Blit_compare:
	tst.b	Blit_checking
	beq.b	.out
	addq.l	#1,Blit_checked
	move.l	Bc_area,a0
	lea	Bc_generic,a1
	move.l	Bc_bytes,d1
	subq.l	#1,d1
.c:	cmpm.b	(a0)+,(a1)+
	bne.b	.diff
	subq.l	#1,d1
	bpl.b	.c
.out:	rts
.diff:	addq.l	#1,Blit_errors
	tst.l	Blit_first_error
	bne.b	.out
	move.l	Blit_checked,Blit_first_error
	move.w	AR_BLTCON0(a6),Blit_error_con0
	rts

; Bc_copy -- d1 bytes from a0 to a1.  Keeps d1.
Bc_copy:
	move.l	d1,-(sp)
	subq.l	#1,d1
.c:	move.b	(a0)+,(a1)+
	subq.l	#1,d1
	bpl.b	.c
	move.l	(sp)+,d1
	rts
	endc

; ***************************************************************************
; Blit_clear -- D only, minterm $00, ascending.
; ***************************************************************************
Blit_clear:
	move.w	BV_ROWS(a5),d1
	move.w	BV_DMOD(a5),d6
	moveq	#0,d0
.row:	move.w	BV_WIDTH(a5),d7
.w:	move.w	d0,(a3)+
	dbf	d7,.w
	add.w	d6,a3
	dbf	d1,.row
	move.l	a3,AR_BLTDPT(a6)
	rts

; ***************************************************************************
; Blit_copy -- A to D, minterm $F0, no shift, no mask, ascending.
; ***************************************************************************
Blit_copy:
	move.w	BV_ROWS(a5),d1
	move.w	BV_AMOD(a5),d5
	move.w	BV_DMOD(a5),d6
.row:	move.w	BV_WIDTH(a5),d7
.w:	move.w	(a0)+,(a3)+
	dbf	d7,.w
	add.w	d5,a0
	add.w	d6,a3
	dbf	d1,.row
	move.l	a0,AR_BLTAPT(a6)
	move.l	a3,AR_BLTDPT(a6)
	rts

; ***************************************************************************
; Blit_ca -- A B C D, minterm $CA (D = A ? B : C), ascending, any shift and
; mask: Thalion's masked blits ($4E2A clouds, text).  The first and last
; word of a row take the masks; a row of one word takes both.
;   d3 old:new A, d4 old:new B, d5 = ASH, d6 = BSH, d7 words.
; ***************************************************************************
Blit_ca:
	moveq	#0,d3
	moveq	#0,d4
	move.w	BV_ASH(a5),d5
	move.w	BV_BSH(a5),d6
.row:	move.w	BV_WIDTH(a5),d7
	move.w	BV_FWM(a5),d2		; mask of the first word
	tst.w	d7
	bne.b	.w
	and.w	BV_LWM(a5),d2		; one word: both masks
.w:	swap	d3
	move.w	(a0)+,d3
	and.w	d2,d3
	move.l	d3,d0
	lsr.l	d5,d0			; A
	swap	d4
	move.w	(a1)+,d4
	move.l	d4,d1
	lsr.l	d6,d1			; B
	and.w	d0,d1
	not.w	d0
	and.w	(a2)+,d0		; C
	or.w	d1,d0
	move.w	d0,(a3)+
	moveq	#-1,d2
	subq.w	#1,d7
	bmi.b	.end
	bne.b	.w
	move.w	BV_LWM(a5),d2		; the last word
	bra.b	.w
.end:	add.w	BV_AMOD(a5),a0
	add.w	BV_BMOD(a5),a1
	add.w	BV_CMOD(a5),a2
	add.w	BV_DMOD(a5),a3
	subq.w	#1,BV_ROWS(a5)
	bpl.b	.row
	move.l	a0,AR_BLTAPT(a6)
	move.l	a1,AR_BLTBPT(a6)
	move.l	a2,AR_BLTCPT(a6)
	move.l	a3,AR_BLTDPT(a6)
	rts

; ***************************************************************************
; Blit_generic -- every other blit, word by word.
;   d0 A, d1 B, d2 C, d3 old:new A, d4 old:new B, d6 step +2/-2,
;   d7 words left in the row; a0-a3 the channels, a4 the minterm routine.
; ***************************************************************************
Blit_generic:
	lea	Minterm_routines,a4
.find:	move.w	(a4)+,d0
	bmi.b	.general
	cmp.w	BV_LF(a5),d0
	beq.b	.found
	addq.l	#4,a4
	bra.b	.find
.found:	move.l	(a4),a4
	bra.b	.go
.general:
	lea	Minterm_any,a4
.go:	moveq	#2,d6
	btst	#1,AR_BLTCON1+1(a6)
	beq.b	.asc
	moveq	#-2,d6
	neg.w	BV_AMOD(a5)		; descending: the modulos go backwards
	neg.w	BV_BMOD(a5)
	neg.w	BV_CMOD(a5)
	neg.w	BV_DMOD(a5)
.asc:	moveq	#0,d3
	moveq	#0,d4
.row:	move.w	BV_WIDTH(a5),d7
.word:	; A, masked on the first and last word, shifted with the old word
	move.w	BV_ADAT(a5),d0
	btst	#USE_A,BV_USE+1(a5)
	beq.b	.amask
	move.w	(a0),d0
	add.w	d6,a0
.amask:	cmp.w	BV_WIDTH(a5),d7
	bne.b	.alast
	and.w	BV_FWM(a5),d0
.alast:	tst.w	d7
	bne.b	.ashift
	and.w	BV_LWM(a5),d0
.ashift:
	swap	d3
	move.w	d0,d3			; old:new
	move.l	d3,d0
	move.w	BV_ASH(a5),d5
	tst.w	d6
	bmi.b	.adesc
	lsr.l	d5,d0
	bra.b	.b
.adesc:	swap	d0			; new:old, shifted left
	lsl.l	d5,d0
	swap	d0
.b:	; B, shifted with the old word
	btst	#USE_B,BV_USE+1(a5)
	bne.b	.bread
	move.w	BV_BDAT(a5),d1
	bra.b	.c
.bread:	move.w	(a1),d1
	add.w	d6,a1
	swap	d4
	move.w	d1,d4
	move.l	d4,d1
	move.w	BV_BSH(a5),d5
	tst.w	d6
	bmi.b	.bdesc
	lsr.l	d5,d1
	bra.b	.c
.bdesc:	swap	d1
	lsl.l	d5,d1
	swap	d1
.c:	move.w	BV_CDAT(a5),d2
	btst	#USE_C,BV_USE+1(a5)
	beq.b	.f
	move.w	(a2),d2
	add.w	d6,a2
.f:	jsr	(a4)
	btst	#USE_D,BV_USE+1(a5)
	beq.b	.next
	move.w	d0,(a3)
	add.w	d6,a3
.next:	dbf	d7,.word
	btst	#USE_A,BV_USE+1(a5)
	beq.b	.mb
	add.w	BV_AMOD(a5),a0
.mb:	btst	#USE_B,BV_USE+1(a5)
	beq.b	.mc
	add.w	BV_BMOD(a5),a1
.mc:	btst	#USE_C,BV_USE+1(a5)
	beq.b	.md
	add.w	BV_CMOD(a5),a2
.md:	btst	#USE_D,BV_USE+1(a5)
	beq.b	.mend
	add.w	BV_DMOD(a5),a3
.mend:	subq.w	#1,BV_ROWS(a5)
	bpl	.row
	move.l	a0,AR_BLTAPT(a6)
	move.l	a1,AR_BLTBPT(a6)
	move.l	a2,AR_BLTCPT(a6)
	move.l	a3,AR_BLTDPT(a6)
	rts

; ***************************************************************************
; The minterms: d0 = A, d1 = B, d2 = C in, d0 = D out; may change d1, d5.
; The ones the intro uses (docs/11, 4.4) directly, the rest term by term.
; ***************************************************************************
Minterm_routines:
	dc.w	$F0
	dc.l	Minterm_f0
	dc.w	$CA
	dc.l	Minterm_ca
	dc.w	$E2
	dc.l	Minterm_e2
	dc.w	$FA
	dc.l	Minterm_fa
	dc.w	$0A
	dc.l	Minterm_0a
	dc.w	$00
	dc.l	Minterm_00
	dc.w	$FC
	dc.l	Minterm_fc
	dc.w	$FE
	dc.l	Minterm_fe
	dc.w	-1

Minterm_f0:				; A
	rts
Minterm_ca:				; A ? B : C
	and.w	d0,d1
	not.w	d0
	and.w	d2,d0
	or.w	d1,d0
	rts
Minterm_e2:				; B ? A : C
	and.w	d1,d0
	not.w	d1
	and.w	d2,d1
	or.w	d1,d0
	rts
Minterm_fa:				; A | C
	or.w	d2,d0
	rts
Minterm_0a:				; ~A & C
	not.w	d0
	and.w	d2,d0
	rts
Minterm_00:
	moveq	#0,d0
	rts
Minterm_fc:				; A | B
	or.w	d1,d0
	rts
Minterm_fe:				; A | B | C
	or.w	d1,d0
	or.w	d2,d0
	rts

; Minterm_any -- bit n of the minterm: the term A=n.2, B=n.1, C=n.0.
Minterm_any:
	movem.l	d3-d4/d6-d7,-(sp)
	move.w	BV_LF(a5),d7
	moveq	#0,d5			; D
	moveq	#7,d6			; term
.t:	btst	d6,d7
	beq.b	.n
	moveq	#-1,d4
	move.w	d0,d3
	btst	#2,d6
	bne.b	.a
	not.w	d3
.a:	and.w	d3,d4
	move.w	d1,d3
	btst	#1,d6
	bne.b	.b
	not.w	d3
.b:	and.w	d3,d4
	move.w	d2,d3
	btst	#0,d6
	bne.b	.c
	not.w	d3
.c:	and.w	d3,d4
	or.w	d4,d5
.n:	dbf	d6,.t
	move.w	d5,d0
	movem.l	(sp)+,d3-d4/d6-d7
	rts

	SECTION	Intro_bss,bss
	ifd	CHECK_BLIT
Bc_bytes:		ds.l	1
Bc_area:		ds.l	1
Bc_ad:			ds.l	2
Bc_b:			ds.l	1
Bc_c:			ds.l	1
Blit_checked:		ds.l	1
Blit_errors:		ds.l	1
Blit_first_error:	ds.l	1
Blit_error_con0:	ds.w	1
Bc_vars:		ds.b	BV_SIZE
Blit_checking:		ds.b	1
	even
Bc_before:		ds.b	BC_MAX
Bc_generic:		ds.b	BC_MAX
	endc
Blit_count:		ds.l	1
Blit_vars:		ds.b	BV_SIZE
Blit_unsupported:	ds.w	1
	SECTION	Intro_code,code

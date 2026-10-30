; ***************************************************************************
; TEXT_ST.S -- the scroll text of the ST extro: text over the picture in ST
; format (docs/05c-ST.md "ST extro"; decision S1-S5, docs/11 7.9: "own
; routine: text over the picture in ST format").  No SECTION of its own
; for the code: it lies in the code of EXTRO_ST.S.
;
; **Thalion's way** (hunk 1 $432-$5B0, docs/11 5.3), each step:
;   1. five blits D = C ? B : A (minterm $D8), one per plane: the text mask
;      C (6:$320, one plane, 40 bytes a row) chooses between the text plane
;      B and the background A, into the screen Thalion draws (5:$10)
;   2. a blit moves the mask up one row (rows 1..277 -> 0..276), the CPU
;      clears row 277
;   3. every few steps the CPU writes a new text line into the mask from
;      row 256 ($6E2 or $FEE, from $2B20)
;   4. the screens swap, a new copper list; 2 VBL a step, the closing text 1
;
; **Ours** (K3; the per-plane blits do not fit the ST, where 32 colours go
; to 16 registers across the planes):
;   Step_wait ($43A) replaces the waits of 4: Thalion waits for one or
;       two VBL *after* each step, so the pace is the work plus the waits.
;       On the Amiga the blits of a step take an estimated 1.6-2.5 VBL
;       (not measured), so 3 or 4 VBL a step; ours mixes in about 1.1 VBL
;       (Hatari, 8 MHz STE) and that varies with the amount of text.  So
;       ours waits for a fixed STEP_VBL VBL since the last step began (the
;       closing text one less): an even pace, 4, chosen by the user on
;       the STE against 3 (2 was too fast to read, 2026-10-30).  Thalion's pause
;       (right button, $F62) stays.
;   Text_scroll ($450) replaces 1 and 2: per ST line (Amiga rows ST_FIRST..
;       ST_FIRST+199) screen = A xor (X and mask), all four planes at once,
;       A and X = A xor B from the build (tools/extro_st_data.py), into
;       the next of the three ST screens (EXTRO_ST.S).  A line whose mask
;       row is empty is skipped, unless text was there when this screen
;       was drawn last (Dirty): then A again.
;   The mask is a ring (Ring): moving it up is moving Ring_top down a row;
;       when the window reaches the end of the ring, its rows go back to
;       the start once (Ring_wrap).  Row_text keeps a byte per ring row:
;       text in it or not.  A row is final once it is above the writer's
;       row 256, so each step marks the one row that has just come to the
;       last ST line; the line loop then tests a byte instead of 40.
;   Text_begin ($420) clears the ring where Thalion clears its mask, and
;       Text_row ($534) points Thalion's writer at the ring's row 256.
;   Thalion's own mask (6:$320) is still cleared but no longer written.
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3: our mixing instead
; of Thalion's blits.
;
; MIXTAKT (VASM_EXTRA="-DMIXTAKT"): register 0 red while Text_scroll runs;
; the red band shows how much of the frames the mixing takes (Vbl keeps it
; red while Mixing is set).
; ***************************************************************************

; ***************************************************************************
; Text_begin -- K3 at $420 (start of a text, the closing text excepted):
; the covered lea, the ring cleared, then Thalion's clear of its own mask.
; ***************************************************************************
Text_begin:
	movem.l	d0/a0,-(sp)
	lea	Ring,a0
	move.l	a0,Ring_top
	clr.w	Ring_index
	move.w	#RING_ROWS*MASK_ROW/4-1,d0
.c:	clr.l	(a0)+
	dbf	d0,.c
	lea	Row_text,a0
	move.w	#RING_ROWS-1,d0
.f:	clr.b	(a0)+
	dbf	d0,.f
	movem.l	(sp)+,d0/a0
	lea	Extro_h6+$320,a1	; lea 6:$320,a1
	jmp	Extro_h1+$426

; ***************************************************************************
; Text_row -- K3 at $534: Thalion's writer starts at mask row 256 (the
; covered lea 6:$2B20,a1); in the ring that row moves.
; ***************************************************************************
Text_row:
	move.l	Ring_top,a1
	lea	MASK_WRITE*MASK_ROW(a1),a1
	jmp	Extro_h1+$53A

; ***************************************************************************
; Step_wait -- K3 at $43A, instead of Thalion's bsr $F54, tst.w $3E, bne,
; bsr $F54 ($43A-$449): wait until STEP_VBL VBL (the closing text one
; less) have passed since the last step, then Thalion's pause check, on at
; $44A.  d0 is the VBL counter, as after $F54.
; ***************************************************************************
	ifnd	STEP_VBL
STEP_VBL	equ	4		; VBL a step (VASM_EXTRA="-DSTEP_VBL=n")
	endc
Step_wait:
	move.l	d1,-(sp)
	moveq	#STEP_VBL,d1
	tst.w	Extro_h5+H5_FAST
	beq.b	.t
	moveq	#STEP_VBL-1,d1		; the closing text one less
.t:	add.l	Step_last,d1
.w:	move.l	Extro_h5+H5_COUNT,d0
	cmp.l	d1,d0
	bmi.b	.w
	move.l	d0,Step_last
	move.l	(sp)+,d1
	jsr	Extro_h1+$F62		; Thalion's pause (right button)
	jmp	Extro_h1+$44A

; ***************************************************************************
; Text_scroll -- K3 at $450, instead of Thalion's $450-$524 (the five
; picture blits, the mask blit, the clear of row 277; $44A has set a6):
; mix into the next ST screen, the ring a row up, its row 277 cleared,
; on at $526.  Thalion's code behind $526 takes nothing from the replaced
; part, all registers stay.
; ***************************************************************************
; MIX_GROUP -- 16 pixels: a2 mask word, a0 A, a3 X, a1 the screen, d0 work.
MIX_GROUP	macro
	move.w	(a2)+,d0
	beq.b	.z\@
	move.w	d0,d1
	swap	d0
	move.w	d1,d0			; the mask in both halves
	move.l	(a3)+,d1		; planes 0 and 1
	and.l	d0,d1
	move.l	(a0)+,d2
	eor.l	d2,d1
	move.l	d1,(a1)+
	move.l	(a3)+,d1		; planes 2 and 3
	and.l	d0,d1
	move.l	(a0)+,d2
	eor.l	d2,d1
	move.l	d1,(a1)+
	bra.b	.e\@
.z\@:	move.l	(a0)+,(a1)+		; no text: A
	move.l	(a0)+,(a1)+
	addq.l	#8,a3
.e\@:
	endm

Text_scroll:
	movem.l	d0-d7/a0-a6,-(sp)
	ifd	MIXTAKT
	st	Mixing
	move.w	#$700,ST_PAL.w
	endc
	move.w	Drawn,d0		; the next ST screen (EXTRO_ST.S)
	addq.w	#1,d0
	cmp.w	#ST_SCREENS,d0
	bcs.b	.next
	moveq	#0,d0
.next:	move.w	d0,Drawn
	bsr	Screen_of		; a0 = ST screen, a1 = its row flags
	move.l	a1,a4
	move.l	a0,a1
	move.l	Current_picture,a5
	move.l	SP_A(a5),a0
	move.l	SP_X(a5),a3
	move.l	Ring_top,a2
	lea	(ST_FIRST+ST_LINES-1)*MASK_ROW(a2),a6
	move.l	(a6)+,d0		; the row now at the last ST line
	rept	MASK_ROW/4-1
	or.l	(a6)+,d0
	endr
	lea	Row_text,a6
	add.w	Ring_index,a6
	sne	ST_FIRST+ST_LINES-1(a6)
	lea	ST_FIRST(a6),a6
	lea	ST_FIRST*MASK_ROW(a2),a2
	move.w	#ST_LINES-1,d7
.line:
	tst.b	(a6)+			; any text in this row?
	beq	.empty
	st	(a4)+
	rept	ST_LINE/8
	MIX_GROUP
	endr
	dbf	d7,.line
	bra	.mixed
.empty:
	tst.b	(a4)
	bne.b	.restore
	addq.l	#1,a4			; nothing to do
	lea	ST_LINE(a0),a0
	lea	ST_LINE(a1),a1
	lea	MASK_ROW(a2),a2
	lea	ST_LINE(a3),a3
	dbf	d7,.line
	bra.b	.mixed
.restore:
	sf	(a4)+			; text was here: A again
	movem.l	(a0)+,d0-d6/a5		; 32 bytes at a time
	movem.l	d0-d6/a5,(a1)
	movem.l	(a0)+,d0-d6/a5
	movem.l	d0-d6/a5,32(a1)
	movem.l	(a0)+,d0-d6/a5
	movem.l	d0-d6/a5,64(a1)
	movem.l	(a0)+,d0-d6/a5
	movem.l	d0-d6/a5,96(a1)
	movem.l	(a0)+,d0-d6/a5
	movem.l	d0-d6/a5,128(a1)
	lea	ST_LINE(a1),a1
	lea	MASK_ROW(a2),a2
	lea	ST_LINE(a3),a3
	dbf	d7,.line
.mixed:
	bsr.b	Ring_up
	ifd	MIXTAKT
	sf	Mixing
	endc
	movem.l	(sp)+,d0-d7/a0-a6
	jmp	Extro_h1+$526

; Ring_up -- the mask a row up: Ring_top a row on (back to the start when
; the window would leave the ring, with the rows' Row_text), then row 277
; cleared (Thalion's $50A).  Changes d0-d7/a0-a6.
Ring_up:
	addq.w	#1,Ring_index
	move.l	Ring_top,a0
	lea	MASK_ROW(a0),a0
	cmp.l	#Ring+(MASK_ROWS+1)*MASK_ROW,a0
	bcs.b	.in
	lea	Ring,a1			; Ring_wrap: rows 0..277 to the start
	move.w	#MASK_ROWS-1,d7
.w:	movem.l	(a0)+,d0-d6/a3-a5
	movem.l	d0-d6/a3-a5,(a1)
	lea	MASK_ROW(a1),a1
	dbf	d7,.w
	lea	Row_text,a1
	move.l	a1,a0
	add.w	Ring_index,a0
	move.w	#MASK_ROWS-1,d7
.f:	move.b	(a0)+,(a1)+
	dbf	d7,.f
	clr.w	Ring_index
	lea	Ring,a0
	addq.w	#1,Ring_wraps
.in:	move.l	a0,Ring_top
	lea	(MASK_ROWS-1)*MASK_ROW(a0),a0
	moveq	#0,d0
	rept	MASK_ROW/4
	move.l	d0,(a0)+
	endr
	rts

	SECTION	Extro_bss,bss
Ring_top:		ds.l	1	; mask row 0
Ring_index:		ds.w	1	; Ring_top as a row of the ring
Ring_wraps:		ds.w	1
Drawn:			ds.w	1	; the ST screen drawn last (EXTRO_ST.S)
Step_last:		ds.l	1	; Thalion's VBL counter at the last step
Mixing:			ds.b	1	; MIXTAKT: Text_scroll runs
	cnop	0,4
Dirty:			ds.b	ST_SCREENS*ST_LINES ; per screen and ST line: text
					; when last drawn (Extro_after_copy clears)
Ring:			ds.b	RING_ROWS*MASK_ROW
Row_text:		ds.b	RING_ROWS ; per ring row: $FF text, 0 none
	SECTION	Extro_code,code

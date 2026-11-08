; ***************************************************************************
; D3_WALLS.S -- the column loop of opaque walls, for Falcon and ST alike;
; then the horizontal scaling of enlarged objects (D12); at the end the
; rotation of the point grid and the sort of the faces (D13).
; Unit "bibliothek" (engine.s).
;
; DEVIATION (goal 1), docs/17-deviations.md D8: our loop instead of Thalion's
; inner loop in put_dpoly.  The picture stays the same, point for point
; (WALLCHECK below proves it wall by wall).
;
; **What stays Thalion's:** put_dpoly up to the column loops: near plane,
; projection, edge list, clipping in x.  The build turns its
; "tst.w seethru_flag" into "jmp Wall_columns" (am2cpu_code.py, EINGRIFFE),
; the same length.  See-through walls go back to Thalion's loop
; (put_dpoly_seethru).  Thalion's loop for opaque walls (put_dpoly_opaque)
; stays in the program, for the checks and as the way back:
; VASM_EXTRA="-DWALLS_THALION=1" takes it.
;
; **Why:** Thalion writes every point with two read-modify-writes of a
; longword in the buffer ("and.l d2,(a4)", "or.l d0,(a4)"), and the wall loop
; is the largest item of a 3D frame on the ST (docs/05c).  Eight columns of a
; wall share four bytes per row, so we gather them first, in a column of our
; own, and write each row once.
;
; **How.**  A group is the columns of a wall that share one longword of the
; buffer.  Its edges are straight, so the rows all its columns cover (the
; "block") follow from its first and last column.  In the block every column
; only ORs into wall_column, and the group writes it out at the end.  Above
; and below the block a column writes point by point, as Thalion does.  A
; group with fewer than WC_MIN_COLUMNS columns or fewer than WC_MIN_ROWS
; rows in its block is not worth it and goes point by point altogether.
;
; **Pairs (docs/05c (A), 2026-11-08).**  In the block two neighbouring
; columns go through one loop (wc_pair): each row reads both texels, joins
; them in a register and writes wall_column once, so half the writes there.
; Each column keeps its own texel, steps and shift.  Four loops for the four
; ways the two shifts can point, each once moving (the group's first pair)
; and once ORing; a column left over at the end goes alone, as before.
;
; **Coarse walls (D10, switch Coarse_walls, off unless built with
; -DCOARSE_WALLS=1):** while the view moves, wall_coarse draws pairs of
; columns from one texel; see "Coarse walls while the view moves" below.
;
; The loops are unrolled eight times only: the 68030 has a 256 byte
; instruction cache, and one loop has to fit into it.  Machine independent,
; 68000 code; no machine switch in this file.
;
; IN (from put_dpoly): d5.l = u (16.16), d6.l = step of u, d7.w = columns - 1;
;   Am2cpu_9_0E928 = first column (clipped), Am2cpu_9_0E930 = texture,
;   Am2cpu_9_0E6E8 = edge list (top, bottom per column).
; OUT: nothing.  Thalion's rasterers save no registers (docs/02 A4).
;
; Registers in the loops: d0 free, d1 shift, d2 ~mask (point by point), d3
; counter, d4 mask of this column in all four bytes, d5/d6 u, d7 low columns
; left - 1 behind this group, d7 high bit number of this column; a0 texture,
; a1 buffer at the group's longword in row 0, a2 steps, a3 edge list, a4
; buffer (a6 in wc_points_*), a5 texel, a6 wall_column.  In the pair loops
; the left column has a4 texel, a3 steps, d5 shift, d6 mask; the right one
; a5, a2, d1, d4; d2 is free.
; ***************************************************************************

WC_MIN_COLUMNS	equ	3
WC_MIN_ROWS	equ	5
WC_ROW_BYTES	equ	72		; of the 3D buffer (docs/02 A2)
WC_BUFFER_ROWS	equ	144

	SECTION	Fast_DATA,data
; Coarse_walls -- D10 on ($FF) or off (0).  VASM_EXTRA="-DCOARSE_WALLS=1"
; builds it on.
Coarse_walls:
	IFD	COARSE_WALLS
	dc.b	$FF
	ELSE
	dc.b	0
	ENDC
	even

	SECTION	Fast_BSS,bss
	cnop	0,4
wall_column:	ds.l	WC_BUFFER_ROWS
wc_mask:	ds.l	1		; the group's columns in all four bytes
wc_top:		ds.w	1		; first row of the block
wc_bottom:	ds.w	1		; last row of the block
wc_rows:	ds.w	1		; rows of the block
wc_loops:	ds.w	1		; dbf count of the gather loop
wc_entry:	ds.w	1		; way into the gather loop
wc_columns:	ds.w	1		; columns of the group still to come
wc_loopset:	ds.l	1		; pairs: wc_move_loops or wc_or_loops
wc_keep:	ds.l	4		; pairs: d5, d6, a0, a3 around the loop
wc_a_steps:	ds.l	1		; pairs: the left column's steps
wc_a_shift:	ds.w	1		; ... its shift (negative: to the left)
wc_a_below:	ds.w	1		; ... its rows below the block
wc_b_below:	ds.w	1		; the right column's rows below the block
wc_signs:	ds.w	1		; 8: left shifts left, 4: right shifts left
wc_pairs:	ds.l	1		; D10: left columns of the group's pairs
wc_skip:	ds.l	1		; D10: their right columns
wc_view:	ds.b	14		; D10: the view of the frame before
wc_coarse_now:	ds.b	1		; D10: this frame's walls coarse
wc_is_pair:	ds.b	1		; D10: this column is the left of a pair
wc_bound:	ds.b	1		; D10: wc_bind has run
wc_hooked:	ds.b	1		; D10: $FF, the frame hook is in place
	even
	IFD	WALLCHECK
wchk_walls:	ds.l	1		; walls compared
wchk_bad:	ds.l	1		; walls that differed
wchk_first:	ds.l	4		; the first: offset, Thalion's, ours, column
wchk_gathered:	ds.l	1		; groups with a block
wchk_plain:	ds.l	1		; groups point by point
wchk_regs:	ds.l	3
wchk_left:	ds.l	1		; invented walls still to come; 0 = not begun
wchk_begun:	ds.b	1
	even
wchk_texture:	ds.l	1
	IFD	WALLCHECK_COARSE
wchk_pairbad:	ds.l	1		; pair points that differ
wchk_ignore:	ds.l	WC_ROW_BYTES/4
wchk_pleft:	ds.l	WC_ROW_BYTES/4
	ENDC
wchk_seed:	ds.l	1
wchk_before:	ds.b	WC_ROW_BYTES*(WC_BUFFER_ROWS+2)
wchk_theirs:	ds.b	WC_ROW_BYTES*(WC_BUFFER_ROWS+2)
	ENDC

	SECTION	Program,code

; ---------------------------------------------------------------------------
; WC_SETUP, wc_setup -- the next column: texel, steps, rows, clipped in y.
;   WC_SETUP inline (the pairs), wc_setup the same as a routine.
;   OUT: a5, a2; d1.w = shift (negative: to the left); d2.w = first row, d3.w
;   = last row; N set: the column has no rows.
;   The same reckoning as Thalion's, also where it looks odd: the height is
;   capped at 319 only to pick the step table, and the steps skipped at the
;   top add up in a word.
; ---------------------------------------------------------------------------
WC_SETUP	MACRO
	move.l	d5,d0
	add.l	d6,d5
	clr.w	d0
	swap	d0
	moveq	#7,d1
	and.w	d0,d1
	sub.w	d1,d0
	lsr.w	#1,d0
	lea	0(a0,d0.w),a5
	eor.w	#7,d1
	swap	d7
	sub.w	d7,d1
	subq.w	#1,d7
	swap	d7
	move.w	(a3)+,d2
	move.w	(a3)+,d3
	move.w	d3,d0
	sub.w	d2,d0
	bmi.s	wcs_none\@
	cmp.w	#319,d0
	ble.s	wcs_1\@
	move.w	#319,d0
wcs_1\@:	lea	zoom_ptrbuff,a2
	lsl.w	#2,d0
	move.l	0(a2,d0.w),a2
	cmp.w	cy2,d2
	bgt.s	wcs_none\@
	move.w	d2,d0
	sub.w	cy1,d0
	bge.s	wcs_2\@
	moveq	#0,d2
	neg.w	d0
	subq.w	#1,d0
wcs_s\@:	add.w	(a2)+,d2
	dbf	d0,wcs_s\@
	add.l	d2,a5
	move.w	cy1,d2
wcs_2\@:	cmp.w	cy1,d3
	blt.s	wcs_none\@
	cmp.w	cy2,d3
	ble.s	wcs_3\@
	move.w	cy2,d3
wcs_3\@:	moveq	#0,d0
	bra.s	wcs_x\@
wcs_none\@:
	moveq	#-1,d0
wcs_x\@:
	ENDM

; ---------------------------------------------------------------------------
; WC_COLUMN -- one column of a group with a block.
;   \1 shift (lsr or lsl), \2 first column move, later ones or, \3 its
;   point-by-point routine.  IN: as wc_setup leaves it, d1 >= 0.
;   \4, coarse walls only (D10): the routine for the left column of a pair,
;   taken when wc_is_pair is set.
; ---------------------------------------------------------------------------
WC_POINTS	MACRO
	IFNB	\2
	tst.b	wc_is_pair
	bne.s	wcq\@
	bsr	\1
	bra.s	wcr\@
wcq\@:	bsr	\2
wcr\@:
	ELSE
	bsr	\1
	ENDC
	ENDM

WC_COLUMN	MACRO
	sub.w	wc_bottom,d3		; d3 = rows below the block
	move.w	d3,-(sp)
	move.w	wc_top,d0
	sub.w	d2,d0			; rows above the block
	ble.s	wca\@
	WC_POINTS	\3,\4
wca\@:	move.w	wc_loops,d3
	move.w	wc_entry,d0
	lea	wall_column,a6
	jmp	wct\@(pc,d0.w)
wct\@:
	REPT	8
	move.l	(a5),d0
	\1.l	d1,d0
	and.l	d4,d0
	\2.l	d0,(a6)+
	adda.w	(a2)+,a5
	ENDR
wcz\@:
	IFNE	wcz\@-wct\@-80
	FAIL	"D3_WALLS.S: the entry into the gather loop reckons with 10 bytes"
	ENDC
	dbf	d3,wct\@
	move.w	(sp)+,d0
	ble.s	wce\@
	move.w	wc_bottom,d2
	addq.w	#1,d2
	WC_POINTS	\3,\4
wce\@:
	ENDM

; ---------------------------------------------------------------------------
; WC_HEAD -- the head of a group: its columns, the mask of the first column,
;   the block and the way into the gather loop.  \1 = where a group without a
;   block goes.  IN: d3.w = bit number of the first column, d7.w = columns - 1.
; ---------------------------------------------------------------------------
WC_HEAD	MACRO
	move.w	d3,d2
	cmp.w	d7,d2
	ble.s	wch1\@
	move.w	d7,d2			; d2 = columns of this group - 1
wch1\@:	sub.w	d2,d7
	subq.w	#1,d7
	swap	d7
	move.w	d3,d7
	swap	d7
	move.w	d2,wc_columns
	moveq	#1,d4			; mask of the first column
	lsl.w	d3,d4
	mulu.w	#$0101,d4
	move.w	d4,d0
	swap	d4
	move.w	d0,d4
	cmp.w	#WC_MIN_COLUMNS-1,d2
	blt	\1
; ---- the block: rows that the first and the last column both cover ----
	lsl.w	#2,d2
	move.w	(a3),d0			; top
	cmp.w	0(a3,d2.w),d0
	bge.s	wch2\@
	move.w	0(a3,d2.w),d0
wch2\@:	cmp.w	cy1,d0
	bge.s	wch3\@
	move.w	cy1,d0
wch3\@:	move.w	2(a3),d1		; bottom
	cmp.w	2(a3,d2.w),d1
	ble.s	wch4\@
	move.w	2(a3,d2.w),d1
wch4\@:	cmp.w	cy2,d1
	ble.s	wch5\@
	move.w	cy2,d1
wch5\@:	move.w	d0,wc_top
	move.w	d1,wc_bottom
	sub.w	d0,d1
	addq.w	#1,d1			; d1 = rows of the block
	cmp.w	#WC_MIN_ROWS,d1
	blt	\1
	move.w	d1,wc_rows
	IFD	WALLCHECK
	addq.l	#1,wchk_gathered
	ENDC
	; the way into the gather loop, once for the group
	moveq	#7,d0
	and.w	d1,d0
	lsr.w	#3,d1
	tst.w	d0
	bne.s	wch6\@
	subq.w	#1,d1
	bra.s	wch7\@
wch6\@:	neg.w	d0
	addq.w	#8,d0
	mulu.w	#10,d0
wch7\@:	move.w	d1,wc_loops
	move.w	d0,wc_entry
	; the group's columns in all four bytes
	swap	d7
	move.w	d7,d0			; d0 = bit number of the first column
	swap	d7
	moveq	#2,d1
	lsl.w	d0,d1			; 2 << first
	sub.w	wc_columns,d0
	moveq	#1,d2
	lsl.w	d0,d2			; 1 << last
	sub.w	d2,d1
	mulu.w	#$0101,d1
	move.w	d1,d0
	swap	d1
	move.w	d0,d1
	move.l	d1,wc_mask
	ENDM

; ---------------------------------------------------------------------------
; WC_WRITE -- write the block of a group from wall_column into the buffer.
;   \1 = the next group.
; ---------------------------------------------------------------------------
WC_WRITE	MACRO
	move.w	wc_top,d2
	mulu.w	#WC_ROW_BYTES,d2
	add.l	a1,d2
	move.l	d2,a4
	lea	wall_column,a6
	move.w	wc_rows,d3
	move.l	wc_mask,d2
	not.l	d2
	beq.s	wcw_full\@
	subq.w	#1,d3
wcw_f1\@:	move.l	(a4),d0
	and.l	d2,d0
	or.l	(a6)+,d0
	move.l	d0,(a4)
	lea	WC_ROW_BYTES(a4),a4
	dbf	d3,wcw_f1\@
	bra.s	\1
wcw_full\@:
	moveq	#7,d0
	and.w	d3,d0
	lsr.w	#3,d3
	subq.w	#1,d0
	bmi.s	wcw_f3\@
wcw_f2\@:	move.l	(a6)+,(a4)
	lea	WC_ROW_BYTES(a4),a4
	dbf	d0,wcw_f2\@
wcw_f3\@:	subq.w	#1,d3
	bmi.s	\1
wcw_f4\@:	move.l	(a6)+,(a4)
	move.l	(a6)+,WC_ROW_BYTES(a4)
	move.l	(a6)+,WC_ROW_BYTES*2(a4)
	move.l	(a6)+,WC_ROW_BYTES*3(a4)
	move.l	(a6)+,WC_ROW_BYTES*4(a4)
	move.l	(a6)+,WC_ROW_BYTES*5(a4)
	move.l	(a6)+,WC_ROW_BYTES*6(a4)
	move.l	(a6)+,WC_ROW_BYTES*7(a4)
	lea	WC_ROW_BYTES*8(a4),a4
	dbf	d3,wcw_f4\@
	ENDM

; ---------------------------------------------------------------------------
; WC_START -- the start of a wall: texture, buffer at the first group, edge
;   list; d3.w = bit number of the first column.
; ---------------------------------------------------------------------------
WC_START	MACRO
	move.l	Am2cpu_9_0E930,a0
	move.l	MOVEP_ptr,a1
	move.w	Am2cpu_9_0E928,d0
	moveq	#7,d3
	and.w	d0,d3
	sub.w	d3,d0
	lsr.w	#1,d0
	adda.w	d0,a1
	eor.w	#7,d3			; d3 = bit number of the first column
	lea	Am2cpu_9_0E6E8,a3
	ENDM

; ---------------------------------------------------------------------------
; Wall_columns -- from put_dpoly (see the head of this file).
; ---------------------------------------------------------------------------
Wall_columns:
	IFND	GEOM_THALION
	tst.b	geo_bound		; once: our geometry (D13)
	bne.s	wc_g
	bsr	Geo_bind
wc_g:
	ENDC
	tst.w	seethru_flag
	beq.s	wc_b0
	jmp	put_dpoly_seethru	; jmp: on the ST, ST_LIB.S lies between
wc_b0:
	IFD	WALLS_THALION
	jmp	put_dpoly_opaque
	ENDC
	tst.b	wc_bound		; once: the frame hook (D10)
	bne.s	wc_b1
	bsr	wc_bind
wc_b1:
	IFD	WALLCHECK
	bra	Wall_check
	ENDC
	tst.b	wc_coarse_now
	bne	wall_coarse
wall_ours:
	WC_START

; ---- One group.  d3.w = bit number of its first column, d7.w = columns - 1
wc_group:
	WC_HEAD	wc_plain_group

; ---- gather in pairs: the first pair moves, the others or ----
	move.l	#wc_move_loops,wc_loopset
wc_next_pair:
	bsr	wc_pair
	move.l	#wc_or_loops,wc_loopset
	subq.w	#2,wc_columns
	bmi	wc_flush		; no column left
	bne	wc_next_pair		; two or more
; ---- one column left: alone ----
	WC_SETUP
	tst.w	d1
	bmi	wc_last_left
	WC_COLUMN	lsr,or,wc_points_right
	bra	wc_flush
wc_last_left:
	neg.w	d1
	WC_COLUMN	lsl,or,wc_points_left

; ---- write the block into the buffer ----
wc_flush:
	WC_WRITE	wc_next_group

wc_next_group:
	moveq	#7,d3
	addq.l	#4,a1
	tst.w	d7
	bpl	wc_group
	rts

; ---- a group without a block: point by point, as Thalion does ----
wc_plain_group:
	IFD	WALLCHECK
	addq.l	#1,wchk_plain
	ENDC
wc_plain:
	bsr	wc_setup
	bmi.s	wc_p3
	sub.w	d2,d3
	move.w	d3,d0
	addq.w	#1,d0
	tst.w	d1
	bmi.s	wc_p1
	bsr.s	wc_points_right
	bra.s	wc_p3
wc_p1:	neg.w	d1
	bsr.s	wc_points_left
wc_p3:	ror.l	#1,d4
	subq.w	#1,wc_columns
	bpl.s	wc_plain
	bra.s	wc_next_group

; ---------------------------------------------------------------------------
; wc_points_right, wc_points_left -- d0.w rows from row d2.w, point by point.
;   Keeps d1, d4-d7, a0, a1, a3, a4; a2 and a5 walk on.  Takes d0, d2, d3,
;   a6.  wc_points: the same with d1 signed (negative: to the left).
; ---------------------------------------------------------------------------
wc_points:
	tst.w	d1
	bpl.s	wc_points_right
	neg.w	d1
	bsr.s	wc_points_left
	neg.w	d1
	rts

wc_points_right:
	mulu.w	#WC_ROW_BYTES,d2
	add.l	a1,d2
	move.l	d2,a6
	move.l	d4,d2
	not.l	d2
	move.w	d0,d3
	subq.w	#1,d3
wc_pr1:	move.l	(a5),d0
	lsr.l	d1,d0
	and.l	d4,d0
	and.l	d2,(a6)
	or.l	d0,(a6)
	adda.w	(a2)+,a5
	lea	WC_ROW_BYTES(a6),a6
	dbf	d3,wc_pr1
	rts

wc_points_left:
	mulu.w	#WC_ROW_BYTES,d2
	add.l	a1,d2
	move.l	d2,a6
	move.l	d4,d2
	not.l	d2
	move.w	d0,d3
	subq.w	#1,d3
wc_pl1:	move.l	(a5),d0
	lsl.l	d1,d0
	and.l	d4,d0
	and.l	d2,(a6)
	or.l	d0,(a6)
	adda.w	(a2)+,a5
	lea	WC_ROW_BYTES(a6),a6
	dbf	d3,wc_pl1
	rts

; ---------------------------------------------------------------------------
; wc_pair -- two columns of a group with a block, in one pass (see the head
;   of this file).  IN: d4 = mask of the left column; wc_loopset.  OUT: both
;   columns drawn into wall_column (block) and the buffer (above, below);
;   d4 = mask of the column after them; d5, d6, d7, a3 walked on as by two
;   wc_setup.  Takes d0-d3, a2, a4-a6.
; ---------------------------------------------------------------------------
wc_pair:
	WC_SETUP			; the left column
	sub.w	wc_bottom,d3
	move.w	d3,wc_a_below
	move.w	wc_top,d0
	sub.w	d2,d0			; its rows above the block
	ble.s	wcpr_1
	bsr	wc_points
wcpr_1:	move.w	d1,wc_a_shift
	move.l	a2,wc_a_steps
	move.l	a5,a4
	ror.l	#1,d4
	WC_SETUP			; the right column
	sub.w	wc_bottom,d3
	move.w	d3,wc_b_below
	move.w	wc_top,d0
	sub.w	d2,d0
	ble.s	wcpr_2
	bsr	wc_points
wcpr_2:	movem.l	d5/d6/a0/a3,wc_keep
	move.l	wc_a_steps,a3
	move.w	wc_a_shift,d5
	move.l	d4,d6
	rol.l	#1,d6			; the left column's mask
	moveq	#0,d0			; which loop: by the two shifts
	tst.w	d5
	bpl.s	wcpr_3
	neg.w	d5
	addq.w	#8,d0
wcpr_3:	tst.w	d1
	bpl.s	wcpr_4
	neg.w	d1
	addq.w	#4,d0
wcpr_4:	move.w	d0,wc_signs
	move.l	wc_loopset,a0
	move.l	0(a0,d0.w),a0
	move.w	wc_entry,d0		; the way in: 20 bytes a row here
	add.w	d0,d0
	adda.w	d0,a0
	move.w	wc_loops,d3
	lea	wall_column,a6
	jmp	(a0)
; ---- back from the loop: the points below the block, right then left ----
wc_pair_below:
	move.w	wc_signs,d0
	btst	#2,d0
	beq.s	wcpr_5
	neg.w	d1
wcpr_5:	btst	#3,d0
	beq.s	wcpr_6
	neg.w	d5
wcpr_6:	move.w	wc_b_below,d0
	ble.s	wcpr_7
	move.w	wc_bottom,d2
	addq.w	#1,d2
	bsr	wc_points
wcpr_7:	move.l	a4,a5			; the left column into the usual registers
	move.l	a3,a2
	move.w	d5,d1
	move.l	d6,d4
	move.w	wc_a_below,d0
	ble.s	wcpr_8
	move.w	wc_bottom,d2
	addq.w	#1,d2
	bsr	wc_points
wcpr_8:	movem.l	wc_keep,d5/d6/a0/a3
	ror.l	#2,d4			; the column after the pair
	rts

; ---------------------------------------------------------------------------
; WC_PAIR_LOOP -- the gather loop of a pair.  \1 shift of the left column,
;   \2 of the right one, \3 move or or.  20 bytes a row: wc_pair reckons
;   with it.
; ---------------------------------------------------------------------------
WC_PAIR_LOOP	MACRO
wpl\@:
	REPT	8
	move.l	(a4),d0
	\1.l	d5,d0
	and.l	d6,d0
	move.l	(a5),d2
	\2.l	d1,d2
	and.l	d4,d2
	or.l	d2,d0
	\3.l	d0,(a6)+
	adda.w	(a3)+,a4
	adda.w	(a2)+,a5
	ENDR
wplz\@:
	IFNE	wplz\@-wpl\@-160
	FAIL	"D3_WALLS.S: the entry into the pair loop reckons with 20 bytes"
	ENDC
	dbf	d3,wpl\@
	bra	wc_pair_below
	ENDM

wc_move_loops:
	dc.l	wpm_rr,wpm_rl,wpm_lr,wpm_ll
wc_or_loops:
	dc.l	wpo_rr,wpo_rl,wpo_lr,wpo_ll
wpm_rr:	WC_PAIR_LOOP	lsr,lsr,move
wpm_rl:	WC_PAIR_LOOP	lsr,lsl,move
wpm_lr:	WC_PAIR_LOOP	lsl,lsr,move
wpm_ll:	WC_PAIR_LOOP	lsl,lsl,move
wpo_rr:	WC_PAIR_LOOP	lsr,lsr,or
wpo_rl:	WC_PAIR_LOOP	lsr,lsl,or
wpo_lr:	WC_PAIR_LOOP	lsl,lsr,or
wpo_ll:	WC_PAIR_LOOP	lsl,lsl,or

; ***************************************************************************
; Coarse walls while the view moves (D10).
;
; DEVIATION (goal 1), docs/17-deviations.md D10: while the player turns,
; walks or the camera height changes, opaque walls are drawn in pairs of
; columns, both from the texel of the left one.  Standing still, the picture
; is Thalion's again from the next frame on.  Switch: Coarse_walls (0 = off,
; Thalion's picture always).
;
; **Pairs.**  Columns 2k and 2k+1 of the buffer (bits 7/6, 5/4, 3/2, 1/0 of a
; byte), both in the same wall.  The left one is gathered and drawn as
; always, and in both bits: in the block the write doubles it
; ((v & wc_pairs) >> 1), above and below the block wc_pairs_right/left draw
; two points.  The right one is skipped (wc_skip_column): no texel, no
; steps.  Its rows are those of the left one, so an edge steps in two
; points.  A column at the end of a wall without its partner stays single,
; exactly as in wall_ours; nothing leaves the wall's columns, its rows stay
; clipped to cy1/cy2.
;
; **When.**  D3_frame compares the view (Player_X, Player_Y, Y_angle,
; head_height) with that of the frame before, once a frame, and sets
; wc_coarse_now.  It runs in front of Thalion's Draw_dungeon: wc_bind turns
; the first instruction of Draw_dungeon ("clr.w dface_anz", 6 bytes) into
; "jmp D3_frame" at run time, the first time a wall is drawn, and D3_frame
; does that clr itself.  Thalion's file stays unchanged.  (The call in
; M3_DisUpd cannot be bent: vasm made it a bsr.w, and D3_frame lies out of
; its reach.)
; ***************************************************************************

; ---- a wall, coarse: as wall_ours, with pairs ----
wall_coarse:
	WC_START
wcc_group:
	; the pairs of this group: d3 = bit number of its first column
	move.w	d3,d0
	cmp.w	d7,d0
	ble.s	wcc_1
	move.w	d7,d0			; d0 = columns of the group - 1
wcc_1:	move.w	d3,d1
	sub.w	d0,d1			; d1 = bit number of its last column
	moveq	#2,d2
	lsl.w	d3,d2
	moveq	#1,d0
	lsl.w	d1,d0
	sub.w	d0,d2			; d2 = the group's columns
	move.w	d2,d0
	add.w	d0,d0
	and.w	d2,d0			; ... whose right neighbour is in it too
	and.w	#$AA,d0			; ... on an odd bit: the left of a pair
	mulu.w	#$0101,d0
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	move.l	d0,wc_pairs
	lsr.l	#1,d0
	move.l	d0,wc_skip
	WC_HEAD	wcc_plain_group

; ---- gather; the first column is never the right one of a pair ----
	bsr	wc_setup
	move.l	d4,d0
	and.l	wc_pairs,d0
	sne	wc_is_pair
	tst.w	d1
	bmi	wcc_first_left
	WC_COLUMN	lsr,move,wc_points_right,wc_pairs_right
	bra	wcc_rest
wcc_first_left:
	neg.w	d1
	WC_COLUMN	lsl,move,wc_points_left,wc_pairs_left
wcc_rest:
	ror.l	#1,d4
	subq.w	#1,wc_columns
	bmi	wcc_flush
	move.l	d4,d0
	and.l	wc_skip,d0
	bne	wcc_skip
	bsr	wc_setup
	move.l	d4,d0
	and.l	wc_pairs,d0
	sne	wc_is_pair
	tst.w	d1
	bmi	wcc_rest_left
	WC_COLUMN	lsr,or,wc_points_right,wc_pairs_right
	bra	wcc_rest
wcc_rest_left:
	neg.w	d1
	WC_COLUMN	lsl,or,wc_points_left,wc_pairs_left
	bra	wcc_rest
wcc_skip:
	bsr	wc_skip_column
	bra	wcc_rest

; ---- write the block, the left column of each pair twice ----
wcc_flush:
	move.l	wc_pairs,d4
	beq	wcc_write_plain
	move.w	wc_top,d2
	mulu.w	#WC_ROW_BYTES,d2
	add.l	a1,d2
	move.l	d2,a4
	lea	wall_column,a6
	move.w	wc_rows,d3
	subq.w	#1,d3
	move.l	wc_mask,d2
	not.l	d2
	beq.s	wcc_w2
wcc_w1:	move.l	(a6)+,d0
	move.l	d0,d1
	and.l	d4,d1
	lsr.l	#1,d1
	or.l	d1,d0
	move.l	(a4),d1
	and.l	d2,d1
	or.l	d0,d1
	move.l	d1,(a4)
	lea	WC_ROW_BYTES(a4),a4
	dbf	d3,wcc_w1
	bra	wcc_next_group
wcc_w2:	move.l	(a6)+,d0
	move.l	d0,d1
	and.l	d4,d1
	lsr.l	#1,d1
	or.l	d1,d0
	move.l	d0,(a4)
	lea	WC_ROW_BYTES(a4),a4
	dbf	d3,wcc_w2
	bra.s	wcc_next_group
wcc_write_plain:
	WC_WRITE	wcc_next_group
wcc_next_group:
	moveq	#7,d3
	addq.l	#4,a1
	tst.w	d7
	bpl	wcc_group
	rts

; ---- a group without a block, coarse ----
wcc_plain_group:
	IFD	WALLCHECK
	addq.l	#1,wchk_plain
	ENDC
wcc_plain:
	move.l	d4,d0
	and.l	wc_skip,d0
	bne.s	wcc_p_skip
	move.l	d4,d0
	and.l	wc_pairs,d0
	sne	wc_is_pair
	bsr	wc_setup
	bmi.s	wcc_p3
	sub.w	d2,d3
	move.w	d3,d0
	addq.w	#1,d0
	tst.b	wc_is_pair
	bne.s	wcc_p4
	tst.w	d1
	bmi.s	wcc_p1
	bsr	wc_points_right
	bra.s	wcc_p3
wcc_p1:	neg.w	d1
	bsr	wc_points_left
	bra.s	wcc_p3
wcc_p4:	tst.w	d1
	bmi.s	wcc_p5
	bsr	wc_pairs_right
	bra.s	wcc_p3
wcc_p5:	neg.w	d1
	bsr	wc_pairs_left
	bra.s	wcc_p3
wcc_p_skip:
	bsr	wc_skip_column
wcc_p3:	ror.l	#1,d4
	subq.w	#1,wc_columns
	bpl.s	wcc_plain
	bra.s	wcc_next_group

; wc_skip_column -- the right column of a pair: only walk on (as wc_setup).
wc_skip_column:
	add.l	d6,d5
	addq.l	#4,a3
	swap	d7
	subq.w	#1,d7
	swap	d7
	rts

; ---------------------------------------------------------------------------
; wc_pairs_right, wc_pairs_left -- as wc_points_right/left, for the left
;   column of a pair: each point also into the column right of it.
;   Keeps d1, d4, d5, a0, a1, a3; a2 and a5 walk on.  Takes d0, d2, d3, a4.
; ---------------------------------------------------------------------------
WC_PAIRS	MACRO
	mulu.w	#WC_ROW_BYTES,d2
	add.l	a1,d2
	move.l	d2,a4
	move.l	d4,d2
	lsr.l	#1,d2
	or.l	d4,d2
	not.l	d2			; d2 = neither of the two columns
	move.w	d0,d3
	subq.w	#1,d3
	move.l	d5,-(sp)
wcpp\@:	move.l	(a5),d0
	\1.l	d1,d0
	and.l	d4,d0
	move.l	d0,d5
	lsr.l	#1,d5
	or.l	d5,d0
	and.l	d2,(a4)
	or.l	d0,(a4)
	adda.w	(a2)+,a5
	lea	WC_ROW_BYTES(a4),a4
	dbf	d3,wcpp\@
	move.l	(sp)+,d5
	rts
	ENDM

wc_pairs_right:
	WC_PAIRS	lsr
wc_pairs_left:
	WC_PAIRS	lsl

wc_setup:
	WC_SETUP
	rts

; ---------------------------------------------------------------------------
; D3_frame -- at the head of Thalion's Draw_dungeon (wc_bind): has the view
;   moved since the frame before?  Then this frame's walls are coarse, if
;   Coarse_walls allows it.  Not the first frame of a 3D map (entered,
;   loaded, back from a menu): Thalion's M3_DisInit draws it with NPCs_off
;   set, the only place that sets it in 3D, and wc_view still holds the view
;   of the map before; that frame is full and only takes the view.  Then
;   Draw_dungeon's first instruction, and on behind it; takes d0/a0, as
;   Thalion's Draw_dungeon keeps no registers either.
; ---------------------------------------------------------------------------
D3_frame:
	sf	wc_coarse_now
	IFD	COARSE_ALWAYS
	move.b	Coarse_walls,wc_coarse_now	; measuring build: every frame coarse
	ENDC
	lea	wc_view,a0
	move.l	Player_X,d0
	cmp.l	(a0),d0
	bne.s	d3f_moved
	move.l	Player_Y,d0
	cmp.l	4(a0),d0
	bne.s	d3f_moved
	move.l	Y_angle,d0
	cmp.l	8(a0),d0
	bne.s	d3f_moved
	move.w	head_height,d0
	cmp.w	12(a0),d0
	beq.s	d3f_go
d3f_moved:
	tst.b	NPCs_off		; first frame of the map: stays full
	bne.s	d3f_view
	move.b	Coarse_walls,wc_coarse_now
d3f_view:
	move.l	Player_X,(a0)+
	move.l	Player_Y,(a0)+
	move.l	Y_angle,(a0)+
	move.w	head_height,(a0)
d3f_go:	clr.w	dface_anz		; Draw_dungeon's first instruction
	lea	Draw_dungeon,a0
	jmp	6(a0)

; ---------------------------------------------------------------------------
; wc_bind -- once, at the first wall: with Coarse_walls on, turn the first
;   instruction of Thalion's Draw_dungeon into "jmp D3_frame".  Only if it is
;   what Thalion's source says there, "clr.w dface_anz" with an absolute
;   address; otherwise nothing changes, and the walls stay full (wc_hooked =
;   0 tells).  Draw_dungeon is running already when this happens (the wall
;   comes from its Draw_faces), so the change counts from the next frame.  On
;   the 68030 the instruction cache may still hold the old instruction for a
;   frame; that frame is then simply drawn in full.
;   All registers are preserved.
; ---------------------------------------------------------------------------
wc_bind:
	st	wc_bound
	tst.b	Coarse_walls
	beq.s	wcb_out
	move.l	a0,-(sp)
	lea	Draw_dungeon,a0
	cmp.w	#$4279,(a0)		; clr.w abs.l
	bne.s	wcb_x
	cmp.l	#dface_anz,2(a0)
	bne.s	wcb_x
	move.l	#D3_frame,2(a0)
	move.w	#$4EF9,(a0)		; jmp abs.l
	st	wc_hooked
wcb_x:	move.l	(sp)+,a0
wcb_out:
	rts

	IFD	WALLCHECK
; ---------------------------------------------------------------------------
; Wall_check -- each wall both ways, one row of margin either side of the
; buffer; a difference is counted and the first one kept (wchk_*).  Read them
; in the debugger.  Test build only: -DWALLCHECK=1.  Our picture goes on.
;
; After the first wall of the game WALLCHECK_RANDOM invented walls follow,
; through Thalion's whole put_dpoly, with random corners, depths and clip
; windows: what no walk through the game would reach in reasonable time.
; ---------------------------------------------------------------------------
	IFND	WALLCHECK_RANDOM
WALLCHECK_RANDOM	equ	20000
	ENDC
Wall_check:
	movem.l	d5-d7,wchk_regs
	lea	wchk_before,a1
	bsr	wchk_save
	jsr	put_dpoly_opaque
	lea	wchk_theirs,a1
	bsr	wchk_save
	; back to the buffer as it was
	lea	wchk_before,a0
	move.l	MOVEP_ptr,a1
	lea	-WC_ROW_BYTES(a1),a1
	move.w	#WC_ROW_BYTES*(WC_BUFFER_ROWS+2)/4-1,d0
wchk_1:	move.l	(a0)+,(a1)+
	dbf	d0,wchk_1
	movem.l	wchk_regs,d5-d7
	IFD	WALLCHECK_COARSE
	bsr	wchk_pairs
	movem.l	wchk_regs,d5-d7
	bsr	wall_coarse
	ELSE
	bsr	wall_ours
	ENDC
	addq.l	#1,wchk_walls
	lea	wchk_theirs,a0
	move.l	MOVEP_ptr,a1
	lea	-WC_ROW_BYTES(a1),a1
	IFD	WALLCHECK_COARSE
	; Coarse (D10): every point but the right columns of pairs as Thalion's;
	; and in a row where a pair changed, its right point is its left one.
	lea	wchk_before,a3
	move.w	#WC_BUFFER_ROWS+2-1,d1
wchk_c1:
	lea	wchk_ignore,a2
	moveq	#WC_ROW_BYTES/4-1,d0
wchk_c2:
	move.l	(a0)+,d2
	move.l	(a1)+,d3
	eor.l	d3,d2
	move.l	(a2),d4
	not.l	d4
	and.l	d4,d2
	bne.s	wchk_bad_wall
	move.l	(a3)+,d4
	eor.l	d3,d4			; changed
	move.l	d4,d2
	add.l	d2,d2
	or.l	d4,d2			; ... in the left or the right point
	move.l	d3,d4
	add.l	d4,d4
	eor.l	d3,d4			; right point not the left one
	and.l	d4,d2
	and.l	WC_ROW_BYTES(a2),d2	; at the pairs' left points
	beq.s	wchk_c3
	addq.l	#1,wchk_pairbad
wchk_c3:
	addq.l	#4,a2
	dbf	d0,wchk_c2
	dbf	d1,wchk_c1
	ELSE
	move.w	#WC_ROW_BYTES*(WC_BUFFER_ROWS+2)/4-1,d0
wchk_2:	cmpm.l	(a0)+,(a1)+
	bne.s	wchk_bad_wall
	dbf	d0,wchk_2
	ENDC
	bra.s	wchk_more
wchk_bad_wall:
	tst.l	wchk_bad
	bne.s	wchk_3
	lea	wchk_first,a2
	move.l	a0,d1
	sub.l	#wchk_theirs+4,d1
	move.l	d1,(a2)+		; offset, one row in front of the buffer
	move.l	-4(a0),(a2)+
	move.l	-4(a1),(a2)+
	move.w	Am2cpu_9_0E928,d1
	ext.l	d1
	move.l	d1,(a2)+
wchk_3:	addq.l	#1,wchk_bad
wchk_more:
	tas	wchk_begun
	beq.s	wchk_random
	rts

; ---- the invented walls; the frame around them is lost in this build ----
wchk_random:
	move.l	Am2cpu_9_0E930,wchk_texture
	move.w	cx1,-(sp)
	move.w	cx2,-(sp)
	move.w	cy1,-(sp)
	move.w	cy2,-(sp)
	move.l	#$2545F491,wchk_seed
	move.l	#WALLCHECK_RANDOM-1,wchk_left
wchk_r1:
	lea	dpoly_koos3d,a0
	bsr	wchk_rand
	and.w	#1023,d0
	sub.w	#512,d0
	move.w	d0,(a0)			; x1
	bsr	wchk_rand
	and.w	#1023,d0
	sub.w	#512,d0
	move.w	d0,2(a0)		; x2
	; y within +-127: the edge steps (y difference << 7, divided by the
	; width) must not overflow a word, or Thalion's unclipped loop writes
	; anywhere.  That still gives heights of 254 rows, clipped at both ends.
	bsr	wchk_rand
	and.w	#255,d0
	sub.w	#128,d0
	move.w	d0,d2
	bsr	wchk_rand
	move.w	d0,d1
	and.w	#255,d0
	sub.w	#128,d0
	and.w	#7,d1
	beq.s	wchk_r3			; now and then upside down
	cmp.w	d2,d0
	bge.s	wchk_r3
	exg	d0,d2
wchk_r3:
	move.w	d2,4(a0)		; y1
	move.w	d0,6(a0)		; y2
	bsr	wchk_rand
	and.w	#2047,d0
	move.w	d0,8(a0)		; z1
	bsr	wchk_rand
	and.w	#2047,d0
	move.w	d0,10(a0)		; z2
	; the clip windows: whole in one of four, otherwise random
	bsr	wchk_rand
	moveq	#3,d1
	and.w	d0,d1
	bne.s	wchk_r4
	clr.w	cx1
	move.w	#WC_BUFFER_ROWS-1,cx2
	clr.w	cy1
	move.w	#WC_BUFFER_ROWS-1,cy2
	bra.s	wchk_r5
wchk_r4:
	lea	cx1,a1
	lea	cx2,a2
	bsr	wchk_window
	lea	cy1,a1
	lea	cy2,a2
	bsr	wchk_window
wchk_r5:
	; A wall that starts just behind the window (x = cx2 + 1, or ends at
	; cx1 - 1) leaves Thalion's edge routine with a count of 0, its dbf
	; then fills 65536 entries.  Draw_faces never asks for that, as its
	; window lies on the wall (cx1, cx2 per face), so leave those out.
	lea	dpoly_koos3d,a0
	move.w	(a0),d0
	move.w	8(a0),d1
	bsr	wchk_project
	move.w	d0,d2
	move.w	2(a0),d0
	move.w	10(a0),d1
	bsr	wchk_project
	cmp.w	d0,d2
	ble.s	wchk_r6
	exg	d0,d2			; d2 left, d0 right
wchk_r6:
	addq.w	#1,d0
	cmp.w	cx1,d0
	beq.s	wchk_r7
	subq.w	#1,d2
	cmp.w	cx2,d2
	beq.s	wchk_r7
	move.l	wchk_texture,a0
	jsr	put_dpoly
wchk_r7:
	subq.l	#1,wchk_left
	bpl	wchk_r1
	move.w	(sp)+,cy2
	move.w	(sp)+,cy1
	move.w	(sp)+,cx2
	move.w	(sp)+,cx1
	rts

; wchk_project -- x (d0) at depth d1 on the screen, as Thalion projects it.
wchk_project:
	add.w	#256,d1
	ext.l	d0
	asl.l	#8,d0
	divs	d1,d0
	add.w	scrx,d0
	rts

; wchk_window -- two random numbers 0..143 in order to (a1), (a2).
wchk_window:
	bsr	wchk_rand
	and.w	#127,d0
	move.w	d0,d2
	bsr	wchk_rand
	and.w	#127,d0
	add.w	d2,d0
	cmp.w	#WC_BUFFER_ROWS-1,d0
	ble.s	wchk_w1
	move.w	#WC_BUFFER_ROWS-1,d0
wchk_w1:
	move.w	d2,(a1)
	move.w	d0,(a2)
	rts

; wchk_rand -- d0.l = next of a xorshift generator; takes d1.
wchk_rand:
	move.l	wchk_seed,d0
	move.l	d0,d1
	lsl.l	#8,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	move.l	d0,d1
	swap	d1
	lsr.w	#1,d1
	and.l	#$7FFF,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	move.l	d0,wchk_seed
	rts

	IFD	WALLCHECK_COARSE
; wchk_pairs -- for this wall: wchk_ignore, the right columns of its pairs,
; and wchk_pleft, their left columns, both per longword of a row.
wchk_pairs:
	lea	wchk_ignore,a0
	moveq	#2*WC_ROW_BYTES/4-1,d0
wchk_p1:
	clr.l	(a0)+
	dbf	d0,wchk_p1
	lea	wchk_ignore,a0
	move.w	Am2cpu_9_0E928,d0	; first column
	move.l	wchk_regs+8,d1		; d7: columns - 1
	add.w	d0,d1			; last column
	move.w	d0,d2
wchk_p2:
	addq.w	#1,d2
	cmp.w	d1,d2
	bgt.s	wchk_p3
	btst	#0,d2
	beq.s	wchk_p2			; even: the left of a pair, or single
	moveq	#7,d3
	and.w	d2,d3
	eor.w	#7,d3			; bit number of this right column
	move.l	#$01010101,d4
	lsl.l	d3,d4
	move.w	d2,d3
	lsr.w	#3,d3
	lsl.w	#2,d3
	or.l	d4,0(a0,d3.w)
	add.l	d4,d4
	or.l	d4,WC_ROW_BYTES(a0,d3.w)
	bra.s	wchk_p2
wchk_p3:
	rts
	ENDC

; wchk_save -- the buffer with its margin to a1.
wchk_save:
	move.l	MOVEP_ptr,a0
	lea	-WC_ROW_BYTES(a0),a0
	move.w	#WC_ROW_BYTES*(WC_BUFFER_ROWS+2)/4-1,d0
wchk_s1:
	move.l	(a0)+,(a1)+
	dbf	d0,wchk_s1
	rts
	ENDC

; ***************************************************************************
; Enlarged objects: the horizontal scaling of draw_zoomshape (D12).
;
; DEVIATION (goal 1), docs/17-deviations.md D12: our loop instead of
; Thalion's for the first step of an enlarged object.  The picture stays the
; same, point for point (ZOOMCHECK below proves it object by object).
;
; **What stays Thalion's:** all of draw_zoomshape but this one step: clipping,
; the step tables, the shrunk objects, the mask and the copy down into the
; 3D buffer.  An object is enlarged when it is taller on the screen than in
; its graphic; then Thalion first scales each source row across into
; zoom_screen (72 bytes a row), one destination column after the other, point
; by point, with two read-modify-writes of a longword per point.  The build
; turns the first instruction of that step, "move.w <source height>,d5", into
; "jmp Zoom_columns" (am2cpu_code.py, EINGRIFFE), the same length; we come
; back behind Thalion's call, at draw_zoomshape_hdone, and Thalion makes the
; mask and copies.  Thalion's step stays in the program
; (draw_zoomshape_hscale), for the check and as the way back:
; VASM_EXTRA="-DZOOM_THALION=1" takes it.
;
; **Why:** with an object close by this step is the largest item of a 3D
; frame on the ST, up to 0.5 M cycles at 99 a point (docs/05c, "Objects in
; 3D").
;
; **How.**  Enlarged, neighbouring destination columns mostly take the same
; source column.  Such a run, as far as it stays in one longword, is one
; segment: per row one fetch, one shift, one mask, the bit spread over the
; run, and one write.  The first segment of a longword moves, the others or.
; The bits of a longword outside the object's columns become 0, where Thalion
; leaves what was there; the mask and the copy never take them (edge masks).
;
; IN (at draw_zoomshape 0:$2A4A4 of 1.07): a0 source at the first visible
;   row, a1 zoom_screen at the longword of the rightmost column, a2 column
;   steps (Am2cpu_9_0E29C), a5.w source bytes per row, d3.w bit number of
;   the rightmost column, d4 its mask in all four bytes.
; OUT: to draw_zoomshape_hdone; registers as Thalion leaves them do not
;   matter there (it loads what it needs).
; ***************************************************************************

	SECTION	Fast_BSS,bss
zc_rows:	ds.w	1		; source rows - 1 (dbf)
zc_cols:	ds.w	1		; destination columns still to come
zc_bit:		ds.w	1		; the next segment's first bit
zc_first:	ds.b	1		; $FF: the next segment opens a longword
	even
	IFD	ZOOMCHECK
zchk_objects:	ds.l	1		; objects compared
zchk_bad:	ds.l	1		; objects that differed
zchk_first:	ds.l	5		; the first: row, longword, Thalion's, ours, columns
zchk_regs:	ds.l	6
zchk_real:	ds.l	6		; the real object's, around the invented ones
zchk_left:	ds.l	1		; invented objects still to come
zchk_seed:	ds.l	1
zchk_begun:	ds.b	1
	even
zchk_vars:	ds.b	ZC_VARS_END-Am2cpu_9_0E278
zchk_theirs:	ds.b	WC_ROW_BYTES*WC_BUFFER_ROWS
zchk_src:	ds.b	8192		; graphics of the invented objects
	ENDC

	SECTION	Program,code

; Thalion's variables of draw_zoomshape (1.20 names, docs/02 A7)
ZC_SW		equ	Am2cpu_9_0E27C	; source width
ZC_SH		equ	Am2cpu_9_0E27E	; source height
ZC_X		equ	Am2cpu_9_0E278	; destination x, clipped
ZC_W		equ	Am2cpu_9_0E286	; destination columns, clipped
ZC_TOP		equ	Am2cpu_9_0E28A	; source rows cut at the top
ZC_RIGHT	equ	Am2cpu_9_0E28E	; source columns cut at the right
ZC_BOTTOM	equ	Am2cpu_9_0E290	; source rows cut at the bottom
ZC_VARS_END	equ	Am2cpu_9_0E51C+2*WC_BUFFER_ROWS	; behind the row steps

; ---------------------------------------------------------------------------
; Zoom_columns -- from draw_zoomshape (see above).
; ---------------------------------------------------------------------------
Zoom_columns:
	IFD	ZOOM_THALION
	bsr	zc_thalion_regs
	jsr	draw_zoomshape_hscale
	ELSE
	IFD	ZOOMCHECK
	bra	Zoom_check
	ENDC
	bsr	zoom_ours
	ENDC
	jmp	draw_zoomshape_hdone

; zc_thalion_regs -- d5 and d6 as Thalion sets them for his step.
zc_thalion_regs:
	move.w	ZC_SH,d5
	sub.w	ZC_TOP,d5
	sub.w	ZC_BOTTOM,d5
	moveq	#0,d6
	move.w	ZC_SW,d6
	subq.w	#1,d6
	sub.w	ZC_RIGHT,d6
	rts

; ---------------------------------------------------------------------------
; zoom_ours -- the step, by segments.  Registers outside the loops: a0
; source row 0, a1 the longword of this segment in row 0, a2 column steps,
; a5 source row bytes, a6 the loop table, d3 bit number of the segment's
; first (rightmost) column, d6 its source column.
; In the loops: d0 point, d1 shift, d2 the segment's first bit in all four
; bytes, d4 spread, d5 the run's bits (5 or more columns), d7 rows, a3
; source, a4 zoom_screen.
; ---------------------------------------------------------------------------
zoom_ours:
	move.w	ZC_SH,d0
	sub.w	ZC_TOP,d0
	sub.w	ZC_BOTTOM,d0
	subq.w	#1,d0
	bmi	zc_out			; no row (Thalion's dbf would run 65536)
	move.w	d0,zc_rows
	move.w	ZC_SW,d6
	subq.w	#1,d6
	sub.w	ZC_RIGHT,d6		; source column of the rightmost column
	move.w	ZC_W,zc_cols
	st	zc_first
	lea	zc_tab(pc),a6
zc_segment:
	; the segment: further columns in this longword whose source column
	; stays the same (step 0) or is the next one (step 1)
	moveq	#1,d1			; d1 = columns of the segment
	move.w	(a2)+,d0		; step behind its first column
	move.w	d0,d7			; the steps, summed
	move.w	d0,d5			; its kind: step 0 or 1
	cmp.w	#1,d5
	bhi.s	zc_seg_end		; 2 or more: a column alone
	move.w	zc_cols,d2
zc_seg:
	cmp.w	d2,d1
	bge.s	zc_seg_end		; no column left
	cmp.w	d5,d0
	bne.s	zc_seg_end		; another step
	move.w	d3,d4
	add.w	d1,d4
	cmp.w	#8,d4
	bge.s	zc_seg_end		; the next longword
	addq.w	#1,d1
	move.w	(a2)+,d0
	add.w	d0,d7
	bra.s	zc_seg
zc_seg_end:
	move.w	d6,d4			; source column of the segment's first
	sub.w	d7,d6			; ... and of the next segment's
	moveq	#7,d0
	and.w	d4,d0
	sub.w	d0,d4
	lsr.w	#1,d4
	moveq	#0,d7
	move.w	d4,d7			; unsigned, as Thalion adds it
	lea	0(a0,d7.l),a3		; its longword in the first row
	eor.w	#7,d0			; d0 = bit number of the source point
	move.w	d3,d7
	add.w	d1,d7
	move.w	d7,zc_bit		; the next segment's first bit
	sub.w	d1,zc_cols
	cmp.w	#2,d1
	blt.s	zc_same			; one column
	tst.w	d5
	bne	zc_span
; ---- the same source point: shift, mask, spread over the columns ----
zc_same:
	sub.w	d3,d0			; shift right by d0 (left if < 0)
	move.l	#$01010101,d2
	lsl.l	d3,d2			; the segment's first bit
	moveq	#4,d4
	cmp.w	d4,d1
	bgt.s	zc_s1			; 5 or more columns
	move.w	d1,d4
	subq.w	#1,d4
zc_s1:	lsl.w	#2,d4
	tst.w	d0
	bpl.s	zc_s2
	neg.w	d0
	addq.w	#2,d4
zc_s2:	cmp.w	#5,d1
	blt.s	zc_go
	bsr	zc_bits			; d5 = the columns' bits
	bra.s	zc_go
; ---- consecutive source points: one or two longwords, shifted ----
zc_span:
	bsr	zc_bits
	move.w	d0,d7
	sub.w	d3,d0			; shift right by d0 (left if < 0)
	bmi.s	zc_sp_left
	add.w	d1,d7
	subq.w	#1,d7
	cmp.w	#7,d7
	bgt.s	zc_sp_two		; reaches into the longword to the left
	moveq	#20,d4
	bra.s	zc_go
zc_sp_left:
	neg.w	d0
	moveq	#22,d4
	bra.s	zc_go
zc_sp_two:
	moveq	#-1,d2
	lsr.b	d0,d2			; the right longword's bits in a byte
	move.b	d2,d7
	lsl.w	#8,d2
	move.b	d7,d2
	move.w	d2,d7
	swap	d2
	move.w	d7,d2
	moveq	#8,d3
	sub.w	d0,d3			; the left one shifts left by 8 - d0
	moveq	#24,d4
zc_go:	tst.b	zc_first
	bne.s	zc_g1
	addq.w	#1,d4
zc_g1:	add.w	d4,d4
	move.w	d0,d1
	move.l	a1,a4
	move.w	zc_rows,d7
	move.w	0(a6,d4.w),d4
	jsr	0(a6,d4.w)
	move.w	zc_bit,d3
	sf	zc_first
	cmp.w	#8,d3
	blt.s	zc_g2
	moveq	#0,d3			; on in the longword to the left
	subq.l	#4,a1
	st	zc_first
zc_g2:	tst.w	zc_cols
	bgt	zc_segment
zc_out:	rts

; zc_bits -- d5 = the bits of d1 columns from bit d3, in all four bytes.
zc_bits:
	moveq	#1,d5
	lsl.w	d1,d5
	subq.w	#1,d5
	lsl.w	d3,d5
	move.b	d5,d7
	lsl.w	#8,d5
	move.b	d7,d5
	move.w	d5,d7
	swap	d5
	move.w	d7,d5
	rts

; ZC_LOOP -- the rows of one segment.  \1 lsr or lsl, \2 the run's length
; (1-4, 5 for 5 to 8 columns), \3 move or or.
ZC_LOOP	MACRO
zcl\@:	move.l	(a3),d0
	\1.l	d1,d0
	and.l	d2,d0
	IFGE	\2-2
	move.l	d0,d4			; the point to the next column
	add.l	d4,d4
	or.l	d4,d0
	ENDC
	IFEQ	\2-3
	move.l	d0,d4
	add.l	d4,d4
	or.l	d4,d0
	ENDC
	IFGE	\2-4
	move.l	d0,d4			; ... to the next two
	lsl.l	#2,d4
	or.l	d4,d0
	ENDC
	IFEQ	\2-5
	move.l	d0,d4			; ... to the next four, then cut
	lsl.l	#4,d4
	or.l	d4,d0
	and.l	d5,d0
	ENDC
	\3.l	d0,(a4)
	lea	WC_ROW_BYTES(a4),a4
	adda.w	a5,a3
	dbf	d7,zcl\@
	rts
	ENDM

; ZC_SPAN -- the rows of consecutive source points in one longword.  \1
; lsr or lsl, \2 move or or.
ZC_SPAN	MACRO
zcs\@:	move.l	(a3),d0
	\1.l	d1,d0
	and.l	d5,d0
	\2.l	d0,(a4)
	lea	WC_ROW_BYTES(a4),a4
	adda.w	a5,a3
	dbf	d7,zcs\@
	rts
	ENDM

; ZC_TWO -- the same, from this source longword and the one to the left:
; ((right >> d1) and d2) or ((left << d3) and not d2), then the columns' bits.
ZC_TWO	MACRO
zct\@:	move.l	(a3),d0
	lsr.l	d1,d0
	move.l	-4(a3),d4
	lsl.l	d3,d4
	eor.l	d4,d0
	and.l	d2,d0
	eor.l	d4,d0
	and.l	d5,d0
	\1.l	d0,(a4)
	lea	WC_ROW_BYTES(a4),a4
	adda.w	a5,a3
	dbf	d7,zct\@
	rts
	ENDM

zc_tab:
	dc.w	zc_1rm-zc_tab,zc_1ro-zc_tab,zc_1lm-zc_tab,zc_1lo-zc_tab
	dc.w	zc_2rm-zc_tab,zc_2ro-zc_tab,zc_2lm-zc_tab,zc_2lo-zc_tab
	dc.w	zc_3rm-zc_tab,zc_3ro-zc_tab,zc_3lm-zc_tab,zc_3lo-zc_tab
	dc.w	zc_4rm-zc_tab,zc_4ro-zc_tab,zc_4lm-zc_tab,zc_4lo-zc_tab
	dc.w	zc_5rm-zc_tab,zc_5ro-zc_tab,zc_5lm-zc_tab,zc_5lo-zc_tab
	dc.w	zc_rm-zc_tab,zc_ro-zc_tab,zc_lm-zc_tab,zc_lo-zc_tab
	dc.w	zc_tm-zc_tab,zc_to-zc_tab
zc_1rm:	ZC_LOOP	lsr,1,move
zc_1ro:	ZC_LOOP	lsr,1,or
zc_1lm:	ZC_LOOP	lsl,1,move
zc_1lo:	ZC_LOOP	lsl,1,or
zc_2rm:	ZC_LOOP	lsr,2,move
zc_2ro:	ZC_LOOP	lsr,2,or
zc_2lm:	ZC_LOOP	lsl,2,move
zc_2lo:	ZC_LOOP	lsl,2,or
zc_3rm:	ZC_LOOP	lsr,3,move
zc_3ro:	ZC_LOOP	lsr,3,or
zc_3lm:	ZC_LOOP	lsl,3,move
zc_3lo:	ZC_LOOP	lsl,3,or
zc_4rm:	ZC_LOOP	lsr,4,move
zc_4ro:	ZC_LOOP	lsr,4,or
zc_4lm:	ZC_LOOP	lsl,4,move
zc_4lo:	ZC_LOOP	lsl,4,or
zc_5rm:	ZC_LOOP	lsr,5,move
zc_5ro:	ZC_LOOP	lsr,5,or
zc_5lm:	ZC_LOOP	lsl,5,move
zc_5lo:	ZC_LOOP	lsl,5,or
zc_rm:	ZC_SPAN	lsr,move
zc_ro:	ZC_SPAN	lsr,or
zc_lm:	ZC_SPAN	lsl,move
zc_lo:	ZC_SPAN	lsl,or
zc_tm:	ZC_TWO	move
zc_to:	ZC_TWO	or

	IFD	ZOOMCHECK
; ---------------------------------------------------------------------------
; Zoom_check -- each enlarged object both ways: Thalion's step into
; zoom_screen, kept; then ours over a pattern; the object's points compared
; (the bits the mask and the copy take: its columns, its source rows).  A
; difference is counted and the first one kept (zchk_*).  Read them in the
; debugger.  Test build only: -DZOOMCHECK=1.  Our result goes on.
;
; At the first object of the game ZOOMCHECK_RANDOM invented objects come
; first, through Thalion's whole draw_zoomshape, enlarged, with random
; sizes, places, masks and clip windows.  Thalion's variables of the real
; object are kept around them; the 3D frame around them is lost in this
; build.
; ---------------------------------------------------------------------------
	IFND	ZOOMCHECK_RANDOM
ZOOMCHECK_RANDOM	equ	5000
	ENDC
Zoom_check:
	movem.l	d3/d4/a0-a2/a5,zchk_regs
	tas	zchk_begun
	bne.s	zchk_go
	movem.l	d3/d4/a0-a2/a5,zchk_real	; the invented objects use zchk_regs
	bsr	zchk_random
	movem.l	zchk_real,d3/d4/a0-a2/a5
	movem.l	d3/d4/a0-a2/a5,zchk_regs
zchk_go:
	bsr	zc_thalion_regs
	jsr	draw_zoomshape_hscale
	; Thalion's rows away, then a pattern where ours go
	bsr	zchk_area		; a0 zoom_screen, d7 longwords - 1
	lea	zchk_theirs,a1
zchk_1:	move.l	(a0)+,(a1)+
	dbf	d7,zchk_1
	bsr	zchk_area
zchk_2:	move.l	#$A55A3CC3,(a0)+
	dbf	d7,zchk_2
	movem.l	zchk_regs,d3/d4/a0-a2/a5
	bsr	zoom_ours
	addq.l	#1,zchk_objects
	; compare: rows 0..zc_rows, longwords 0..last, edges masked
	move.w	ZC_X,d0
	and.w	#7,d0			; phase: the first column's place
	move.w	d0,d1
	add.w	ZC_W,d1
	subq.w	#1,d1			; the last column
	moveq	#7,d2
	and.w	d1,d2
	lsr.w	#3,d1			; d1 = last longword
	moveq	#-1,d3
	lsr.b	d0,d3			; left edge in a byte
	moveq	#0,d4
	move.b	#$80,d4
	asr.b	d2,d4			; right edge in a byte
	bsr	zchk_wide		; d3, d4 into all four bytes
	move.l	zoom_screen,a0
	lea	zchk_theirs,a1
	move.w	zc_rows,d5
zchk_r:	moveq	#0,d6			; longword
zchk_l:	moveq	#-1,d7
	tst.w	d6
	bne.s	zchk_l1
	and.l	d3,d7
zchk_l1:
	cmp.w	d1,d6
	bne.s	zchk_l2
	and.l	d4,d7
zchk_l2:
	move.w	d6,d0
	lsl.w	#2,d0
	move.l	0(a0,d0.w),d2
	move.l	0(a1,d0.w),d0
	eor.l	d0,d2
	and.l	d7,d2
	bne.s	zchk_bad_object
	addq.w	#1,d6
	cmp.w	d1,d6
	ble.s	zchk_l
	lea	WC_ROW_BYTES(a0),a0
	lea	WC_ROW_BYTES(a1),a1
	dbf	d5,zchk_r
	bra.s	zchk_out
zchk_bad_object:
	tst.l	zchk_bad
	bne.s	zchk_3
	lea	zchk_first,a2
	move.w	zc_rows,d2
	sub.w	d5,d2
	ext.l	d2
	move.l	d2,(a2)+		; row
	ext.l	d6
	move.l	d6,(a2)+		; longword
	move.w	d6,d0
	lsl.w	#2,d0
	move.l	0(a1,d0.w),(a2)+	; Thalion's
	move.l	0(a0,d0.w),(a2)+	; ours
	move.w	ZC_W,d0
	ext.l	d0
	move.l	d0,(a2)+		; columns
zchk_3:	addq.l	#1,zchk_bad
zchk_out:
	jmp	draw_zoomshape_hdone

; zchk_area -- a0 = zoom_screen, d7 = longwords of the object's rows - 1.
zchk_area:
	move.l	zoom_screen,a0
	move.w	ZC_SH,d7
	sub.w	ZC_TOP,d7
	sub.w	ZC_BOTTOM,d7
	mulu	#WC_ROW_BYTES/4,d7
	subq.w	#1,d7
	rts

; zchk_wide -- the bytes d3 and d4 into all four bytes of each.
zchk_wide:
	move.b	d3,d0
	lsl.w	#8,d3
	move.b	d0,d3
	move.w	d3,d0
	swap	d3
	move.w	d0,d3
	move.b	d4,d0
	lsl.w	#8,d4
	move.b	d0,d4
	move.w	d4,d0
	swap	d4
	move.w	d0,d4
	rts

; ---- the invented objects ----
zchk_random:
	lea	Am2cpu_9_0E278,a0	; Thalion's variables of the real object
	lea	zchk_vars,a1
	move.w	#(ZC_VARS_END-Am2cpu_9_0E278)/2-1,d0
zchk_v1:
	move.w	(a0)+,(a1)+
	dbf	d0,zchk_v1
	move.w	cx1,-(sp)
	move.w	cx2,-(sp)
	move.w	cy1,-(sp)
	move.w	cy2,-(sp)
	move.l	#$3A61C2F5,zchk_seed
	lea	zchk_src,a0		; random graphics
	move.w	#8192/4-1,d2
zchk_v2:
	bsr	zchk_rand
	move.l	d0,(a0)+
	dbf	d2,zchk_v2
	move.l	#ZOOMCHECK_RANDOM-1,zchk_left
zchk_o1:
	bsr	zchk_rand
	moveq	#3,d1
	and.w	d0,d1
	bne.s	zchk_o2
	clr.w	cx1			; a quarter with the whole window
	move.w	#WC_BUFFER_ROWS-1,cx2
	clr.w	cy1
	move.w	#WC_BUFFER_ROWS-1,cy2
	bra.s	zchk_o3
zchk_o2:
	lea	cx1,a1
	lea	cx2,a2
	bsr	zchk_window
	lea	cy1,a1
	lea	cy2,a2
	bsr	zchk_window
zchk_o3:
	bsr	zchk_rand
	moveq	#7,d4
	and.w	d0,d4
	addq.w	#1,d4
	lsl.w	#4,d4			; source width 16..128
	bsr	zchk_rand
	moveq	#127,d5
	and.w	d0,d5
	cmp.w	#4,d5
	bge.s	zchk_o4
	addq.w	#4,d5
zchk_o4:
	cmp.w	#120,d5
	ble.s	zchk_o5
	moveq	#120,d5			; source height 4..120
zchk_o5:
	bsr	zchk_rand
	and.w	#$1FE,d0
	lea	zchk_src,a0
	adda.w	d0,a0			; somewhere in the graphics, even
	bsr	zchk_rand
	move.w	#255,d7
	and.w	d0,d7
	add.w	d5,d7
	addq.w	#1,d7			; height: taller, so enlarged
	bsr	zchk_rand
	move.w	#255,d6
	and.w	d0,d6
	addq.w	#1,d6			; width 1..256
	bsr	zchk_rand
	moveq	#0,d2
	btst	#8,d0
	beq.s	zchk_o6
	moveq	#-1,d2			; colour 0 see-through, as Thalion's
zchk_o6:
	move.w	#255,d1
	and.w	d0,d1
	sub.w	#64,d1			; y
	swap	d0
	and.w	#255,d0
	sub.w	#64,d0			; x
	jsr	draw_zoomshape
	subq.l	#1,zchk_left
	bpl	zchk_o1
	move.w	(sp)+,cy2
	move.w	(sp)+,cy1
	move.w	(sp)+,cx2
	move.w	(sp)+,cx1
	lea	zchk_vars,a0
	lea	Am2cpu_9_0E278,a1
	move.w	#(ZC_VARS_END-Am2cpu_9_0E278)/2-1,d0
zchk_v3:
	move.w	(a0)+,(a1)+
	dbf	d0,zchk_v3
	rts

; zchk_window -- two random numbers 0..143 in order to (a1), (a2).
zchk_window:
	bsr	zchk_rand
	and.w	#127,d0
	move.w	d0,d2
	bsr	zchk_rand
	and.w	#127,d0
	add.w	d2,d0
	cmp.w	#WC_BUFFER_ROWS-1,d0
	ble.s	zchk_w1
	move.w	#WC_BUFFER_ROWS-1,d0
zchk_w1:
	move.w	d2,(a1)
	move.w	d0,(a2)
	rts

; zchk_rand -- d0.l = next of a xorshift generator; takes d1.
zchk_rand:
	move.l	zchk_seed,d0
	move.l	d0,d1
	lsl.l	#8,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	move.l	d0,d1
	swap	d1
	lsr.w	#1,d1
	and.l	#$7FFF,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	move.l	d0,zchk_seed
	rts
	ENDC

; ***************************************************************************
; The geometry of a 3D frame: the point grid and the sort of the faces (D13).
;
; DEVIATION (goal 1), docs/17-deviations.md D13: our routines instead of
; Thalion's rotate_y and Quicksort (3D_MAP.S).  The results stay the same,
; bit for bit (GEOMCHECK below proves it call by call).
;
; **What stays Thalion's:** all of Draw_dungeon but these two: the view
; rectangle, the grid itself (Rotate_points fills it, then projects it),
; NPCs, faces, drawing.  Thalion's file stays unchanged.  Geo_bind turns the
; first six bytes of rotate_y and of Quicksort into "jmp" to ours, at run
; time, the first time a wall is drawn (from Draw_faces; the change counts
; from the next frame), and only if the bytes are what Thalion's source says
; there; otherwise Thalion's routines stay (geo_hooked tells).  Each of ours
; does the six bytes it covers itself where it hands back to Thalion's.
; VASM_EXTRA="-DGEOM_THALION=1" binds nothing: the way back.
;
; **Why:** per 3D frame on the ST the sort costs about 75 k cycles, the
; rotation about 30 k (docs/05c, "Speed in 3D, step 0").
;
; **Rotation.**  Thalion's rotate_y turns each point with four muls.  The
; points from Rotate_points are a grid, patt_size apart in x and in y, so the
; products grow by the same amount from point to point.  Rotate_grid takes
; the products of the first point as Thalion does, then adds.  The sums are
; exact integers, so after Thalion's "asl.l #2" and "swap" every word is the
; same as Thalion's (also the offsets, which go into the high word).
;
; **Sort.**  Thalion's Quicksort always sorts by insertion (the limit is the
; whole list, "immer bubblesort"), ascending by the signed long in front of
; each entry, stable: an entry goes behind the equal ones before it.  The
; faces come mostly in falling order, so that is the slow case.  Sort_faces
; is a merge sort, stable as well, so the order is the same, equal keys
; included.
; ***************************************************************************

GEO_MAX		equ	Max_visible_walls+Max_visible_objects	; entries of wall_list0

	SECTION	Fast_BSS,bss
geo_bound:	ds.b	1		; Geo_bind has run
geo_hooked:	ds.b	1		; bit 0 rotate_y, bit 1 Quicksort bound
	even
geo_save:	ds.l	3		; a4-a6 around the sort
geo_buffer:	ds.l	GEO_MAX*2	; the other half of the merge sort
	IFD	GEOMCHECK
geo_rot_calls:	ds.l	1		; rotations compared
geo_rot_fast:	ds.l	1		; ... of them on the grid path
geo_rot_bad:	ds.l	1		; ... that differed
geo_sort_calls:	ds.l	1		; sorts compared
geo_sort_bad:	ds.l	1		; ... that differed
geo_first:	ds.l	3		; the first difference: kind, count, offset
geo_fast:	ds.b	1
geo_rbegun:	ds.b	1
geo_sbegun:	ds.b	1
	even
geo_seed:	ds.l	1
geo_regs:	ds.l	3
geo_real:	ds.l	3
geo_vars:	ds.w	5		; drawsizex, drawsizey, Y_angle, xoffset, zoffset
geo_in:		ds.l	16*16
geo_out:	ds.l	16*16
geo_rin:	ds.l	16*16		; the real grid, around the invented ones
geo_sin:	ds.l	GEO_MAX*2
geo_sout:	ds.l	GEO_MAX*2
geo_list:	ds.l	GEO_MAX*2	; the invented lists
	ENDC

	SECTION	Program,code

; ---------------------------------------------------------------------------
; Geo_bind -- once, at the first wall: bind rotate_y and Quicksort to ours.
;   All registers are preserved.
; ---------------------------------------------------------------------------
Geo_bind:
	st	geo_bound
	move.l	a0,-(sp)
	move.l	d0,-(sp)
	; rotate_y: "subq.w #1,d7", "bmi.s .Exit" (an rts), "lea Sinus_table,a2"
	lea	rotate_y,a0
	cmp.w	#$5347,(a0)
	bne.s	gb_1
	cmp.b	#$6B,2(a0)
	bne.s	gb_1
	move.b	3(a0),d0
	beq.s	gb_1
	ext.w	d0
	cmp.w	#$4E75,4(a0,d0.w)
	bne.s	gb_1
	cmp.w	#$45F9,4(a0)
	bne.s	gb_1
	cmp.l	#Sinus_table,6(a0)
	bne.s	gb_1
	move.l	#Rotate_grid,2(a0)
	move.w	#$4EF9,(a0)		; jmp abs.l
	bset	#0,geo_hooked
gb_1:	; Quicksort: "move.l a0,a1", "move.w d7,d0", "subq.w #1,d0"
	lea	Quicksort,a0
	cmp.l	#$22483007,(a0)
	bne.s	gb_2
	cmp.w	#$5340,4(a0)
	bne.s	gb_2
	move.l	#Sort_faces,2(a0)
	move.w	#$4EF9,(a0)
	bset	#1,geo_hooked
gb_2:	move.l	(sp)+,d0
	move.l	(sp)+,a0
	rts

; ---------------------------------------------------------------------------
; Rotate_grid -- in place of rotate_y (from Rotate_points).
;   IN: a0 points (x, y words), a1 where to, d7.w number of points; Y_angle,
;   xoffset, zoffset.  OUT: as Thalion's; Thalion keeps no registers.
;   The grid path needs a0 = a1 and d7 = (drawsizex+1)*(drawsizey+1), as
;   Rotate_points calls it; anything else goes to Thalion's.
; ---------------------------------------------------------------------------
Rotate_grid:
	IFD	GEOMCHECK
	bra	Rotate_check
	ENDC
rg_ours:
	cmp.l	a0,a1
	bne	rg_thalion
	tst.w	d7
	ble	rg_thalion
	move.w	drawsizex,d0
	addq.w	#1,d0
	move.w	drawsizey,d1
	addq.w	#1,d1
	mulu.w	d1,d0
	cmp.l	#16*16,d0
	bhi	rg_thalion
	cmp.w	d7,d0
	bne	rg_thalion
	IFD	GEOMCHECK
	st	geo_fast
	ENDC
	; sin and cos, as Thalion takes them
	lea	Sinus_table,a2
	and.w	#slang-1,Y_angle
	move.w	Y_angle,d6
	neg.w	d6
	add.w	#slang,d6
	and.w	#slang-1,d6
	add.w	d6,d6
	move.w	0(a2,d6.w),d0		; sin
	add.w	#slang/2,d6
	and.w	#slang*2-1,d6
	move.w	0(a2,d6.w),d1		; cos
	; the first point, as Thalion turns it, shifted, the offsets on top
	move.w	(a0),d2
	move.w	2(a0),d3
	move.w	d2,d4
	move.w	d3,d5
	muls	d0,d2			; x*sin
	muls	d0,d3			; y*sin
	muls	d1,d4			; x*cos
	muls	d1,d5			; y*cos
	sub.l	d3,d4
	add.l	d2,d5
	asl.l	#2,d4			; d4 = x' of the row's first point, shifted
	asl.l	#2,d5			; d5 = z' of it
	move.w	xoffset,d2
	swap	d2
	clr.w	d2
	add.l	d2,d4
	move.w	zoffset,d2
	swap	d2
	clr.w	d2
	add.l	d2,d5
	; the steps: one square to the right, (cos, sin); one down, (-sin, cos)
	IFNE	patt_size-512
	FAIL	"D3_WALLS.S: Rotate_grid reckons with patt_size 512"
	ENDC
	move.w	d1,d2
	ext.l	d2
	asl.l	#8,d2
	asl.l	#3,d2			; d2 = cos * patt_size, shifted
	move.w	d0,d3
	ext.l	d3
	asl.l	#8,d3
	asl.l	#3,d3			; d3 = sin * patt_size, shifted
	move.w	drawsizex,a2
	move.w	drawsizey,d1		; low word: rows - 1, then columns - 1
rg_row:	swap	d1
	move.w	a2,d1
	move.l	d4,d6
	move.l	d5,d7
rg_col:	move.l	d6,d0
	swap	d0
	move.w	d0,(a1)+
	move.l	d7,d0
	swap	d0
	move.w	d0,(a1)+
	add.l	d2,d6
	add.l	d3,d7
	dbf	d1,rg_col
	sub.l	d3,d4
	add.l	d2,d5
	swap	d1
	dbf	d1,rg_row
	rts

; Thalion's rotate_y: the six bytes it lost, then on behind them.
rg_thalion:
	subq.w	#1,d7
	bmi.s	rg_out
	lea	Sinus_table,a2
	lea	rotate_y,a3		; a3: Thalion's loads it later
	jmp	10(a3)
rg_out:	rts

; ---------------------------------------------------------------------------
; Sort_faces -- in place of Quicksort (from Draw_dungeon).
;   IN: a0 list, d6.l bytes per entry, d7.w entries.  OUT: the list sorted
;   as Thalion's sorts it; Thalion keeps no registers (d0-d7, a0-a3 go).
;   Entries of eight bytes, at most GEO_MAX; anything else goes to Thalion's.
; ---------------------------------------------------------------------------
Sort_faces:
	IFD	GEOMCHECK
	bra	Sort_check
	ENDC
sf_ours:
	cmp.l	#8,d6
	bne	sf_thalion
	cmp.w	#GEO_MAX,d7
	bhi	sf_thalion
	cmp.w	#2,d7
	blt	sf_out
	movem.l	a4-a6,geo_save
	move.w	d7,d5
	lsl.w	#3,d5			; d5 = bytes of the list
	; pairs, in place: the second before the first only if it is smaller
	move.l	a0,a2
	move.w	d7,d0
	lsr.w	#1,d0
	subq.w	#1,d0
sf_pair:
	move.l	8(a2),d1
	cmp.l	(a2),d1
	bge.s	sf_pair_ok
	move.l	(a2),8(a2)
	move.l	d1,(a2)
	move.l	4(a2),d1
	move.l	12(a2),4(a2)
	move.l	d1,12(a2)
sf_pair_ok:
	lea	16(a2),a2
	dbf	d0,sf_pair
	; merge runs of 2, 4, 8 ... entries, back and forth
	move.l	a0,a4			; a4 = from
	lea	geo_buffer,a5		; a5 = to
	moveq	#16,d4			; d4 = bytes of a run
sf_pass:
	cmp.w	d5,d4
	bhs.s	sf_passes_done
	moveq	#0,d6			; d6 = offset of the pair of runs
	move.l	a0,-(sp)
sf_pairs:
	lea	0(a4,d6.w),a2		; left
	lea	0(a5,d6.w),a1		; out
	move.w	d6,d0
	add.w	d4,d0
	cmp.w	d5,d0
	bls.s	sf_1
	move.w	d5,d0
sf_1:	lea	0(a4,d0.w),a3		; end of the left, start of the right
	add.w	d4,d0
	cmp.w	d5,d0
	bls.s	sf_2
	move.w	d5,d0
sf_2:	lea	0(a4,d0.w),a6		; end of the right
	move.l	a3,a0			; right
	cmpa.l	a6,a0
	beq.s	sf_rest_left		; no right run: the left as it is
sf_merge:
	move.l	(a0),d1
	cmp.l	(a2),d1
	blt.s	sf_right		; right smaller: it first; equal: the left
	move.l	(a2)+,(a1)+
	move.l	(a2)+,(a1)+
	cmpa.l	a3,a2
	bne.s	sf_merge
	bra.s	sf_rest_right
sf_right:
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	cmpa.l	a6,a0
	bne.s	sf_merge
sf_rest_left:
	cmpa.l	a3,a2
	beq.s	sf_next
	move.l	(a2)+,(a1)+
	move.l	(a2)+,(a1)+
	bra.s	sf_rest_left
sf_rest_right:
	cmpa.l	a6,a0
	beq.s	sf_next
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	bra.s	sf_rest_right
sf_next:
	add.w	d4,d6
	add.w	d4,d6
	cmp.w	d5,d6
	blo.s	sf_pairs
	move.l	(sp)+,a0
	exg	a4,a5
	add.w	d4,d4
	bra.s	sf_pass
sf_passes_done:
	cmpa.l	a0,a4
	beq.s	sf_done
	; the result lies in geo_buffer: back into the list
	move.w	d7,d0
	subq.w	#1,d0
sf_back:
	move.l	(a4)+,(a0)+
	move.l	(a4)+,(a0)+
	dbf	d0,sf_back
sf_done:
	movem.l	geo_save,a4-a6
sf_out:	rts

; Thalion's Quicksort: the six bytes it lost, then on behind them.
sf_thalion:
	move.l	a0,a1
	move.w	d7,d0
	subq.w	#1,d0
	lea	Quicksort,a2		; a2: Thalion's loads it before use
	jmp	6(a2)

	IFD	GEOMCHECK
; ---------------------------------------------------------------------------
; Rotate_check, Sort_check -- each call both ways, Thalion's and ours; a
; difference is counted and the first one kept (geo_*).  Read them in the
; debugger.  Test build only: -DGEOMCHECK=1.  Our result goes on.
;
; At the first call GEOMCHECK_ROT invented grids and GEOMCHECK_SORT invented
; lists come first: random sizes, places, angles and offsets; random keys,
; many of them equal, falling, rising; the second long of an entry is its
; number, so a change in the order of equal keys shows.
; ---------------------------------------------------------------------------
	IFND	GEOMCHECK_ROT
GEOMCHECK_ROT	equ	2000
	ENDC
	IFND	GEOMCHECK_SORT
GEOMCHECK_SORT	equ	300
	ENDC

Rotate_check:
	movem.l	d7/a0/a1,geo_regs
	tas	geo_rbegun
	bne.s	rc_go
	movem.l	d7/a0/a1,geo_real	; the invented grids use geo_regs
	bsr	rc_random
	movem.l	geo_real,d7/a0/a1
	movem.l	d7/a0/a1,geo_regs
rc_go:	bra	rc_one

; rc_one -- one call (geo_regs) both ways; ours stays.
rc_one:
	movem.l	geo_regs,d7/a0/a1
	cmp.l	a0,a1
	bne	rg_thalion
	tst.w	d7
	ble	rg_thalion
	cmp.w	#16*16,d7
	bhi	rg_thalion
	lea	geo_in,a2
	move.w	d7,d0
	subq.w	#1,d0
rc_1:	move.l	(a0)+,(a2)+
	dbf	d0,rc_1
	movem.l	geo_regs,d7/a0/a1
	bsr	rg_thalion
	movem.l	geo_regs,d7/a0/a1
	lea	geo_out,a2
	lea	geo_in,a3
	move.w	d7,d0
	subq.w	#1,d0
rc_2:	move.l	(a0),(a2)+
	move.l	(a3)+,(a0)+
	dbf	d0,rc_2
	sf	geo_fast
	movem.l	geo_regs,d7/a0/a1
	bsr	rg_ours
	addq.l	#1,geo_rot_calls
	tst.b	geo_fast
	beq.s	rc_3
	addq.l	#1,geo_rot_fast
rc_3:	movem.l	geo_regs,d7/a0/a1
	lea	geo_out,a2
	move.w	d7,d0
	subq.w	#1,d0
rc_4:	cmpm.l	(a0)+,(a2)+
	bne.s	rc_bad
	dbf	d0,rc_4
	rts
rc_bad:	moveq	#1,d0
	bra	geo_bad

; rc_random -- the invented grids, then the real call's state back.
rc_random:
	lea	geo_vars,a0
	move.w	drawsizex,(a0)+
	move.w	drawsizey,(a0)+
	move.w	Y_angle,(a0)+
	move.w	xoffset,(a0)+
	move.w	zoffset,(a0)+
	movem.l	geo_real,d7/a0/a1
	bsr	rc_keep
	move.l	#$6D2B79F5,geo_seed
	move.w	#GEOMCHECK_ROT-1,d7
rcr_1:	move.w	d7,-(sp)
	bsr	geo_rand
	moveq	#15,d2
	and.w	d0,d2
	move.w	d2,drawsizex		; columns - 1
	lsr.w	#4,d0
	and.w	#15,d0
	move.w	d0,drawsizey		; rows - 1
	bsr	geo_rand
	and.w	#$3FFF,d0
	sub.w	#$2000,d0
	move.w	d0,d4			; x of the first point
	swap	d0
	and.w	#$3FFF,d0
	sub.w	#$2000,d0
	move.w	d0,d5			; y of it
	bsr	geo_rand
	move.w	d0,Y_angle		; any word; both "and" it
	swap	d0
	moveq	#0,d2
	moveq	#0,d3
	btst	#0,d0			; offsets now and then
	beq.s	rcr_2
	move.w	d0,d2
	asr.w	#6,d2
	move.w	d0,d3
	asr.w	#3,d3
rcr_2:	move.w	d2,xoffset
	move.w	d3,zoffset
	; the grid, as Rotate_points lays it
	lea	rot_points,a0
	move.w	drawsizey,d3
rcr_3:	move.w	d4,d0
	move.w	drawsizex,d2
rcr_4:	move.w	d0,(a0)+
	move.w	d5,(a0)+
	add.w	#patt_size,d0
	dbf	d2,rcr_4
	add.w	#patt_size,d5
	dbf	d3,rcr_3
	move.w	drawsizex,d7
	addq.w	#1,d7
	move.w	drawsizey,d0
	addq.w	#1,d0
	mulu.w	d0,d7
	lea	rot_points,a0
	move.l	a0,a1
	movem.l	d7/a0/a1,geo_regs
	bsr	rc_one
	move.w	(sp)+,d7
	dbf	d7,rcr_1
	lea	geo_vars,a0
	move.w	(a0)+,drawsizex
	move.w	(a0)+,drawsizey
	move.w	(a0)+,Y_angle
	move.w	(a0)+,xoffset
	move.w	(a0)+,zoffset
	movem.l	geo_real,d7/a0/a1
	bra	rc_back

; rc_keep, rc_back -- the real call's points (d7, a0) away and back.
rc_keep:
	lea	geo_rin,a2
	bra.s	rck_1
rc_back:
	exg	a0,a2
	lea	geo_rin,a0
rck_1:	tst.w	d7
	ble.s	rck_3
	cmp.w	#16*16,d7
	bhi.s	rck_3
	move.w	d7,d0
	subq.w	#1,d0
rck_2:	move.l	(a0)+,(a2)+
	dbf	d0,rck_2
rck_3:	rts

Sort_check:
	movem.l	d6/d7/a0,geo_regs
	tas	geo_sbegun
	bne.s	sc_go
	movem.l	d6/d7/a0,geo_real
	bsr	sc_random
	movem.l	geo_real,d6/d7/a0
	movem.l	d6/d7/a0,geo_regs
sc_go:	bra	sc_one

; sc_one -- one call (geo_regs) both ways; ours stays.
sc_one:
	movem.l	geo_regs,d6/d7/a0
	cmp.l	#8,d6
	bne	sf_thalion
	cmp.w	#GEO_MAX,d7
	bhi	sf_thalion
	cmp.w	#2,d7
	blt	sf_out
	lea	geo_sin,a2
	move.w	d7,d0
	subq.w	#1,d0
sc_1:	move.l	(a0)+,(a2)+
	move.l	(a0)+,(a2)+
	dbf	d0,sc_1
	movem.l	geo_regs,d6/d7/a0
	bsr	sf_thalion
	movem.l	geo_regs,d6/d7/a0
	lea	geo_sout,a2
	lea	geo_sin,a3
	move.w	d7,d0
	add.w	d0,d0
	subq.w	#1,d0
sc_2:	move.l	(a0),(a2)+
	move.l	(a3)+,(a0)+
	dbf	d0,sc_2
	movem.l	geo_regs,d6/d7/a0
	bsr	sf_ours
	addq.l	#1,geo_sort_calls
	movem.l	geo_regs,d6/d7/a0
	lea	geo_sout,a2
	move.w	d7,d0
	add.w	d0,d0
	subq.w	#1,d0
sc_3:	cmpm.l	(a0)+,(a2)+
	bne.s	sc_bad
	dbf	d0,sc_3
	rts
sc_bad:	moveq	#2,d0

; geo_bad -- d0 = kind (1 rotation, 2 sort), d7 = count, a0 behind the
;   long that differed.
geo_bad:
	tst.l	geo_first
	bne.s	gbd_1
	lea	geo_first,a2
	move.l	d0,(a2)+
	move.l	d7,(a2)+
	move.l	a0,(a2)
gbd_1:	cmp.w	#1,d0
	bne.s	gbd_2
	addq.l	#1,geo_rot_bad
	rts
gbd_2:	addq.l	#1,geo_sort_bad
	rts

; sc_random -- the invented lists, in geo_list.
sc_random:
	move.l	#$1B873593,geo_seed
	move.w	#GEOMCHECK_SORT-1,d7
scr_1:	move.w	d7,-(sp)
	bsr	geo_rand
	moveq	#0,d7
	move.b	d0,d7			; entries
	cmp.w	#GEO_MAX,d7
	bls.s	scr_2
	and.w	#127,d7
scr_2:	cmp.w	#2,d7
	bhs.s	scr_3
	addq.w	#2,d7
scr_3:	lsr.w	#8,d0
	moveq	#3,d6
	and.w	d0,d6			; d6 = kind of keys
	lea	geo_list,a0
	moveq	#0,d5			; number of the entry
	move.l	#$40000000,d4		; falling, from here
	moveq	#0,d3			; rising
scr_4:	bsr	geo_rand
	cmp.w	#1,d6
	beq.s	scr_k1
	cmp.w	#2,d6
	beq.s	scr_k2
	cmp.w	#3,d6
	beq.s	scr_k3
	and.l	#7,d0			; 0: few values, many equal
	bra.s	scr_k
scr_k1:	bra.s	scr_k			; 1: any long, signed
scr_k2:	and.l	#$FFF,d0		; 2: falling, now and then not
	sub.l	d0,d4
	move.l	d4,d0
	btst	#0,d5
	beq.s	scr_k
	add.l	#$500,d0
	bra.s	scr_k
scr_k3:	and.l	#3,d0			; 3: rising in small steps, equal ones
	add.l	d0,d3
	move.l	d3,d0
scr_k:	move.l	d0,(a0)+
	move.l	d5,(a0)+
	addq.w	#1,d5
	cmp.w	d7,d5
	blo.s	scr_4
	moveq	#8,d6
	lea	geo_list,a0
	movem.l	d6/d7/a0,geo_regs
	bsr	sc_one
	move.w	(sp)+,d7
	dbf	d7,scr_1
	rts

; geo_rand -- d0.l = next of a xorshift generator; takes d1.
geo_rand:
	move.l	geo_seed,d0
	move.l	d0,d1
	lsl.l	#8,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	move.l	d0,d1
	swap	d1
	lsr.w	#1,d1
	and.l	#$7FFF,d1
	eor.l	d1,d0
	move.l	d0,d1
	lsl.l	#5,d1
	eor.l	d1,d0
	move.l	d0,geo_seed
	rts
	ENDC

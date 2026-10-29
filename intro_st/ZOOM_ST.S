; ***************************************************************************
; ZOOM_ST.S -- our zoom for Thalion's intro on the ST (K3 at $1C98,
; tools/intro_st_program.py; docs/05c-ST.md "ST intro").
;
; Thalion's zoom ($1BAE) clips against the window, computes the step tables
; for rows and columns (bsr $2314) and then draws with the blitter: per
; destination row a blit into a buffer, then per destination column a blit
; one word wide over all rows and planes that sets one bit (docs/11, 4.4).
; In software every destination word is read and written up to 16 times;
; on the ST the zooms of the logos at the start alone took minutes.
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3 (K3).
;
; From $1C98 on the build jumps here.  Clipping and tables stay Thalion's;
; we write the same result into the same screen, each word once:
;
;   1. the source as colour numbers times 4, one byte a pixel, kept in
;      Zoom_store (the pictures lie in Thalion's data hunks 2-4 and do not
;      change; another source is converted for this call only)
;   2. Zoom_fold: per destination row the source row Thalion's row table
;      names, per destination group of 16 pixels the 16 colours through the
;      column map, folded into four plane words and a mask (Zoom_line)
;   3. Zoom_put: the line into Thalion's screen: with mask (d2 <> 0 at
;      $1BAE) only where the source colour is not 0, without mask every
;      pixel of the clipped rectangle
; When the next destination row takes the same source row (magnifying),
; only 3. is done again.  This is the Falcon's method (intro/INTRO_ZOOM.S:
; Zm_wandeln, Zm_falten, Zm_setzen, Zm_setzen_ziel; docs/05c-ST.md "Target
; screens, the Falcon's way").
;
; Thalion's result, read in $1CA8-$2312 (the same reading as the Falcon's
; intro/INTRO_ZOOM.S, not its code): destination row i takes source row
; $11D02 + the sum of the first i row steps; the rightmost destination
; column takes source column width - 1 - $11D06, each further one to the
; left one column step less.  The destination has 160 bytes a row, four
; planes of 40.
;
; Contract ($1BAE): d0/d1 = x/y, d6/d7 = width/height, d2 = mask, source and
; source size in hunk 5.  Thalion's routine changes all registers but a7;
; its callers ($64C planets, $BD8 meteor, $1536 logos at the start) save
; what they need.  Ours the same.
;
; Into a target screen (TARGET_ST.S, the four-plane scenes) the same rows
; go into the ST format: planes side by side, a group 8 bytes on; the
; buffer rows no longer hold.  CHECK_ZOOM compares buffers only and leaves
; those zooms out; CHECK_TARGET compares them.
;
; CHECK_ZOOM (VASM_EXTRA="-DCHECK_ZOOM"): each zoom runs Thalion's way first,
; then ours, and the destination rows are compared (Zoom_errors, the first
; one's call number in Zoom_first_error, the calls in Zoom_calls).
; ***************************************************************************

ZM_BASE		equ	$11CF0		; Thalion's zoom variables in hunk 5:
ZM_X		equ	0		; destination x, clipped
ZM_Y		equ	2		; destination y, clipped
ZM_SWIDTH	equ	4		; source width
ZM_SHEIGHT	equ	6		; source height
ZM_ROWS		equ	$C		; destination rows after clipping
ZM_COLS		equ	$E		; destination columns after clipping
ZM_SROW		equ	$12		; first source row
ZM_RIGHT	equ	$16		; source columns left out on the right
ZM_MASK		equ	$1C		; <> 0: colour 0 leaves the screen
ZM_SOURCE	equ	$1E		; source picture, four planes a row
ZM_COLTAB	equ	$22		; ($11D12) column steps, from the right
ZM_ROWTAB	equ	$2A2		; ($11F92) row steps
ZM_SCREEN	equ	$18		; in hunk 5: Thalion's drawing screen
ZM_LINE		equ	160		; bytes a screen row: four planes of 40
ZM_PLANE	equ	40
ZM_MAXGROUPS	equ	21		; groups a row: (15 + 320 + 15) / 16
ZM_MAXWIDTH	equ	512		; source pixels a row
ZM_STORE	equ	192*1024	; converted pictures
ZM_SLOTS	equ	32		; ... at most this many
INTRO_H4_SIZE	equ	132640		; hunk 4 (tools/amiga_programm.py)
ZS_SOURCE	equ	0		; a slot: source picture,
ZS_DATA		equ	4		; converted, in Zoom_store (0 = free),
ZS_WIDTH	equ	8		; source width,
ZS_HEIGHT	equ	10		; source height
ZS_SIZE		equ	12
ZL_SIZE		equ	10		; Zoom_line a group: 4 plane words, mask

; ***************************************************************************
; Zoom_st -- K3 at $1C98 (replaces move.w Intro_h5+$11CF8,d0).  Ends with
; rts for Thalion's rts at $205E.
; ***************************************************************************
Zoom_st:
	ifd	CHECK_ZOOM
	bra	Zoom_check
Zoom_ours:
	endc
	lea	Intro_h5+ZM_BASE,a6
	tst.w	ZM_ROWS(a6)
	ble	.out
	tst.w	ZM_COLS(a6)
	ble	.out
	cmp.w	#ZM_MAXWIDTH,ZM_SWIDTH(a6)
	bhi	.out			; none in the intro (Zoom_unhandled)
	; the screen in the target format (TARGET_ST.S): the target is written,
	; the buffer rows no longer hold
	clr.l	Zoom_screen
	move.l	Intro_h5+ZM_SCREEN,d0
	bsr	Screen_find
	beq.b	.amiga
	cmp.w	#4,SC_PLANES(a5)
	bne.b	.amiga			; 160 bytes a row: four planes only
	move.l	a5,Zoom_screen
	ifd	CHECK_TARGET
	bsr	Zoom_check_target
	endc
.amiga:	bsr	Zoom_source		; a5 = colour numbers, row by row
	beq	.out
	bsr	Zoom_columns		; Zoom_map, Zoom_masks, d5 = groups
	; first destination group, first screen row (160 bytes a row both ways)
	move.l	Intro_h5+ZM_SCREEN,a1
	move.l	Zoom_screen,d1
	beq.b	.place
	move.l	d1,a1
	move.l	SC_TARGET(a1),a1
.place:	move.w	ZM_Y(a6),d0
	mulu	#ZM_LINE,d0
	add.l	d0,a1
	move.w	ZM_X(a6),d0
	lsr.w	#4,d0
	add.w	d0,d0			; Amiga: 2 bytes a group
	tst.l	d1
	beq.b	.group
	lsl.w	#2,d0			; target: 8
.group:	add.w	d0,a1
	lea	Zoom_put,a4
	tst.l	d1
	beq.b	.first
	lea	Zoom_put_target,a4
.first:	; first source row
	move.w	ZM_SWIDTH(a6),d4	; bytes a converted row
	move.w	ZM_SROW(a6),d0
	mulu	d4,d0
	add.l	d0,a5
	clr.l	Zoom_folded
	lea	ZM_ROWTAB(a6),a2
	move.w	ZM_ROWS(a6),d7
	subq.w	#1,d7
.row:	cmp.l	Zoom_folded,a5		; the same source row: put only
	beq.b	.put
	move.l	a5,Zoom_folded
	movem.l	d4/d7/a1-a2/a4-a5,-(sp)
	bsr	Zoom_fold
	movem.l	(sp)+,d4/d7/a1-a2/a4-a5
.put:	move.l	a1,a0
	jsr	(a4)
	lea	ZM_LINE(a1),a1
	move.w	(a2)+,d0		; Thalion's row step
	mulu	d4,d0
	add.l	d0,a5
	dbf	d7,.row
	move.l	Zoom_screen,d0
	beq.b	.out
	move.l	d0,a5
	move.w	ZM_Y(a6),d0
	move.w	ZM_ROWS(a6),d1
	ifd	CHECK_TARGET
	moveq	#CT_ZOOM,d2
	bsr	Rows_compare
	subq.w	#1,Target_busy
	else
	bsr	Rows_invalid
	endc
.out:	rts

; ***************************************************************************
; Zoom_fold -- the source row a5 (colour numbers times 4) into Zoom_line:
; per destination group the 16 colours through Zoom_map, each one a long
; from Zoom_spread shifted in.  After eight pixels planes 0-3 stand in bytes
; 3-0 of the long, and movep spreads them into four plane words side by
; side (the Falcon's Zm_falten).  Then the group's mask: with mask where the
; colour is not 0, without it the clipped rectangle (Zoom_masks).
;   Changes d0-d6/a0-a4.
; ***************************************************************************
Zoom_fold:
	lea	Zoom_map,a2		; per pixel: offset into the source row
	lea	Zoom_spread,a3
	lea	Zoom_masks,a4		; per group: the clipped rectangle
	lea	Zoom_line,a1
	lea	-1(a5),a0		; offset 0 = the pad pixel left of the row
	move.b	(a0),-(sp)		; keep the byte under the pad
	clr.b	(a0)
	moveq	#0,d4
	move.w	Intro_h5+ZM_BASE+ZM_MASK,d6
	move.w	Zoom_groups,d3
	subq.w	#1,d3
.group:	moveq	#0,d0
	rept	8
	move.w	(a2)+,d5
	move.b	0(a0,d5.w),d4
	add.l	d0,d0
	or.l	0(a3,d4.w),d0
	endr
	moveq	#0,d1
	rept	8
	move.w	(a2)+,d5
	move.b	0(a0,d5.w),d4
	add.l	d1,d1
	or.l	0(a3,d4.w),d1
	endr
	movep.l	d0,0(a1)
	movep.l	d1,1(a1)
	tst.w	d6
	beq.b	.rect
	move.w	(a1),d2			; with mask: only colour <> 0
	or.w	2(a1),d2
	or.w	4(a1),d2
	or.w	6(a1),d2
	bra.b	.mask
.rect:	move.w	(a4)+,d2		; without: the whole rectangle
.mask:	move.w	d2,8(a1)
	lea	ZL_SIZE(a1),a1
	dbf	d3,.group
	move.b	(sp)+,(a0)
	rts

; ***************************************************************************
; Zoom_put -- Zoom_line into a row of Thalion's screen at a0 (plane 0 of
; the first group): plane = plane & ~mask | line.  The line is 0 outside
; the mask.  (The Falcon's Zm_setzen.)
; Zoom_put_target -- the same into a target screen: the planes side by
; side, the next group 8 bytes on (the Falcon's Zm_setzen_ziel).
;   Changes d0-d3/d5-d6/a0/a3.
; ***************************************************************************
Zoom_put:
	lea	Zoom_line,a3
	move.w	Zoom_groups,d6
	subq.w	#1,d6
.group:	movem.w	(a3)+,d0-d3/d5
	cmp.w	#-1,d5
	beq.b	.full
	tst.w	d5
	beq.b	.next
	not.w	d5
	and.w	d5,(a0)
	or.w	d0,(a0)
	and.w	d5,ZM_PLANE(a0)
	or.w	d1,ZM_PLANE(a0)
	and.w	d5,2*ZM_PLANE(a0)
	or.w	d2,2*ZM_PLANE(a0)
	and.w	d5,3*ZM_PLANE(a0)
	or.w	d3,3*ZM_PLANE(a0)
.next:	addq.l	#2,a0
	dbf	d6,.group
	rts
.full:	move.w	d0,(a0)
	move.w	d1,ZM_PLANE(a0)
	move.w	d2,2*ZM_PLANE(a0)
	move.w	d3,3*ZM_PLANE(a0)
	addq.l	#2,a0
	dbf	d6,.group
	rts

Zoom_put_target:
	lea	Zoom_line,a3
	move.w	Zoom_groups,d6
	subq.w	#1,d6
.group:	movem.w	(a3)+,d0-d3/d5
	cmp.w	#-1,d5
	beq.b	.full
	tst.w	d5
	beq.b	.next
	not.w	d5
	and.w	d5,(a0)
	or.w	d0,(a0)
	and.w	d5,2(a0)
	or.w	d1,2(a0)
	and.w	d5,4(a0)
	or.w	d2,4(a0)
	and.w	d5,6(a0)
	or.w	d3,6(a0)
.next:	addq.l	#8,a0
	dbf	d6,.group
	rts
.full:	movem.w	d0-d3,(a0)
	addq.l	#8,a0
	dbf	d6,.group
	rts

; ***************************************************************************
; Zoom_columns -- the column map for this call: per pixel of the destination
; groups the offset into a source row (+1; 0 = the pad pixel, colour 0,
; outside the clipped rectangle), per group the rectangle's mask.
;   OUT: Zoom_groups.  Changes d0-d7/a0-a3.
; ***************************************************************************
Zoom_columns:
	move.w	ZM_X(a6),d0
	move.w	d0,d1
	add.w	ZM_COLS(a6),d1		; first column right of the rectangle
	move.w	d0,d2
	and.w	#-16,d2			; first pixel of the first group
	move.w	d1,d3
	add.w	#15,d3
	and.w	#-16,d3			; end of the last group
	move.w	d3,d4
	sub.w	d2,d4
	lsr.w	#4,d4
	move.w	d4,Zoom_groups
	; the map: all pad, then the rectangle from the right
	lea	Zoom_map,a0
	move.w	d3,d5
	sub.w	d2,d5
	subq.w	#1,d5
.pad:	clr.w	(a0)+
	dbf	d5,.pad
	lea	Zoom_map,a0
	move.w	d1,d5
	sub.w	d2,d5			; index behind the rectangle
	add.w	d5,d5
	add.w	d5,a0
	move.w	ZM_SWIDTH(a6),d6
	subq.w	#1,d6
	sub.w	ZM_RIGHT(a6),d6		; source column of the rightmost pixel
	lea	ZM_COLTAB(a6),a2
	move.w	ZM_COLS(a6),d7
	subq.w	#1,d7
.col:	move.w	d6,d5
	addq.w	#1,d5
	move.w	d5,-(a0)
	sub.w	(a2)+,d6
	dbf	d7,.col
	; the masks: first and last group cut, the rest whole
	lea	Zoom_masks,a0
	move.w	Zoom_groups,d5
	subq.w	#1,d5
.m:	move.w	#$FFFF,(a0)+
	dbf	d5,.m
	moveq	#15,d5
	and.w	d0,d5			; pixels left of the rectangle
	move.w	#$FFFF,d6
	lsr.w	d5,d6
	and.w	d6,Zoom_masks
	moveq	#15,d5
	and.w	d1,d5			; pixels of the last group inside
	beq.b	.out
	move.w	#$FFFF,d6
	lsr.w	d5,d6
	not.w	d6
	and.w	d6,-2(a0)
.out:	rts

; ***************************************************************************
; Zoom_source -- the source picture as colour numbers, a5 = row 0.  Found
; in Zoom_slots, or converted into Zoom_store; a source outside Thalion's
; data hunks is converted into Zoom_scratch for this call only.
;   OUT: Z set when there is no room (Zoom_unhandled counts it).
;   Changes d0-d7/a0-a4.
; ***************************************************************************
Zoom_source:
	move.l	ZM_SOURCE(a6),d0
	move.w	ZM_SWIDTH(a6),d1
	move.w	ZM_SHEIGHT(a6),d2
	cmp.l	#Intro_h2,d0
	blo.b	.foreign
	cmp.l	#Intro_h4+INTRO_H4_SIZE,d0
	bhs.b	.foreign
	lea	Zoom_slots,a0
	moveq	#ZM_SLOTS-1,d7
.find:	tst.l	ZS_DATA(a0)
	beq.b	.new
	cmp.l	ZS_SOURCE(a0),d0
	bne.b	.next
	cmp.w	ZS_WIDTH(a0),d1
	bne.b	.next
	cmp.w	ZS_HEIGHT(a0),d2
	bne.b	.next
	move.l	ZS_DATA(a0),a5
	moveq	#1,d0			; Z clear
	rts
.next:	lea	ZS_SIZE(a0),a0
	dbf	d7,.find
	bra.b	.foreign		; no slot left
.new:	; room in the store?  One pad byte in front of each picture.
	moveq	#0,d3
	move.w	d1,d3
	mulu	d2,d3
	addq.l	#2,d3
	move.l	Zoom_store_used,d4
	add.l	d3,d4
	cmp.l	#ZM_STORE,d4
	bhi.b	.foreign
	lea	Zoom_store,a5
	add.l	Zoom_store_used,a5
	addq.l	#1,a5
	move.l	d4,Zoom_store_used
	move.l	d0,ZS_SOURCE(a0)
	move.l	a5,ZS_DATA(a0)
	move.w	d1,ZS_WIDTH(a0)
	move.w	d2,ZS_HEIGHT(a0)
	bra.b	Zoom_convert
.foreign:
	moveq	#0,d3
	move.w	d1,d3
	mulu	d2,d3
	cmp.l	#ZM_SCRATCH-2,d3
	bhi.b	.none
	lea	Zoom_scratch+1,a5
	bra.b	Zoom_convert
.none:	addq.w	#1,Zoom_unhandled
	moveq	#0,d0			; Z set
	rts

; Zoom_convert -- the picture d0 (width d1, height d2; four planes a row,
; (width & -16) / 8 bytes a plane) into colour numbers times 4 (an offset
; into Zoom_spread) at a5, width bytes a row.  Pixels right of width & -16
; are 0, as Thalion's rows end there.
;   OUT: Z clear.  Changes d0-d7/a0-a4.
Zoom_convert:
	move.l	d0,a0
	move.w	d1,d6
	and.w	#-16,d6
	lsr.w	#3,d6			; bytes a plane row
	move.l	a5,a1
	subq.w	#1,d2
.row:	move.w	d2,-(sp)		; rows left
	move.l	a1,a3
	move.w	d6,d5
	subq.w	#1,d5
	bmi.b	.rest
	move.l	a0,a4
.byte:	move.b	0(a4,d6.w),d1		; plane 1
	move.b	(a4)+,d0		; plane 0
	move.w	d6,d4
	add.w	d4,d4
	move.b	-1(a4,d4.w),d3		; plane 2
	add.w	d6,d4
	move.b	-1(a4,d4.w),d4		; plane 3
	moveq	#8-1,d7
.bit:	moveq	#0,d2
	add.b	d4,d4
	addx.b	d2,d2
	add.b	d3,d3
	addx.b	d2,d2
	add.b	d1,d1
	addx.b	d2,d2
	add.b	d0,d0
	addx.b	d2,d2
	add.b	d2,d2
	add.b	d2,d2
	move.b	d2,(a3)+
	dbf	d7,.bit
	dbf	d5,.byte
.rest:	move.l	a3,d0			; up to the width: colour 0
	sub.l	a1,d0
	move.w	ZM_SWIDTH(a6),d5
	sub.w	d0,d5
	bra.b	.r1
.r0:	clr.b	(a3)+
.r1:	dbf	d5,.r0
	add.w	ZM_SWIDTH(a6),a1
	lea	0(a0,d6.w),a0		; next source row: four planes on
	lea	0(a0,d6.w),a0
	lea	0(a0,d6.w),a0
	lea	0(a0,d6.w),a0
	move.w	(sp)+,d2
	dbf	d2,.row
	moveq	#1,d0			; Z clear
	rts

	ifd	CHECK_TARGET
; ***************************************************************************
; Zoom_check_target -- (CHECK_TARGET) the rows valid, then Thalion's zoom
; into the buffer (blits not redirected), back into Zoom_st, which writes
; the target and compares (Rows_compare).  a5 = the entry, a6 = ZM_BASE.
; ***************************************************************************
Zoom_check_target:
	move.w	ZM_Y(a6),d0
	move.w	ZM_ROWS(a6),d1
	bsr	Check_rows
	st	Blit_no_redirect
	pea	.back
	move.w	Intro_h5+$11CF8,d0	; the replaced instruction, then $1C9E
	jmp	Intro_h0+$1C9E
.back:	sf	Blit_no_redirect
	lea	Intro_h5+ZM_BASE,a6
	rts
	endc

	ifd	CHECK_ZOOM
; ***************************************************************************
; Zoom_check -- Thalion's way, then ours from the same screen, compare the
; destination rows.  Thalion's way: the replaced instruction, then $1C9E,
; whose rts comes back here.
; ***************************************************************************
Zoom_check:
	move.l	Intro_h5+ZM_SCREEN,d0	; a target screen: not here
	bsr	Screen_find
	bne	Zoom_ours
	addq.l	#1,Zoom_calls
	bsr	Zoom_rows_range		; d0 = offset, d1 = bytes
	ble	.only
	move.l	Intro_h5+ZM_SCREEN,a0
	add.l	d0,a0
	lea	Zoom_before,a1
	bsr	Zoom_copy
	pea	.thalion_back
	move.w	Intro_h5+$11CF8,d0
	jmp	Intro_h0+$1C9E
.thalion_back:
	bsr	Zoom_rows_range
	move.l	Intro_h5+ZM_SCREEN,a0
	add.l	d0,a0
	lea	Zoom_thalion,a1
	bsr	Zoom_copy
	bsr	Zoom_rows_range		; screen back as before
	lea	Zoom_before,a0
	move.l	Intro_h5+ZM_SCREEN,a1
	add.l	d0,a1
	bsr	Zoom_copy
	bsr	Zoom_ours
	bsr	Zoom_rows_range
	move.l	Intro_h5+ZM_SCREEN,a0
	add.l	d0,a0
	lea	Zoom_thalion,a1
	lsr.l	#1,d1
	subq.l	#1,d1
.cmp:	cmpm.w	(a0)+,(a1)+
	bne.b	.diff
	subq.l	#1,d1
	bpl.b	.cmp
	rts
.diff:	addq.l	#1,Zoom_errors
	tst.l	Zoom_first_error
	bne.b	.out
	move.l	Zoom_calls,Zoom_first_error
	; keep the case: Thalion's variables and tables, both results
	lea	Intro_h5+ZM_BASE,a0
	lea	Zoom_err_vars,a1
	move.l	#ZM_ROWTAB+2*256,d1
	bsr	Zoom_copy
	bsr	Zoom_rows_range
	lea	Zoom_thalion,a0
	lea	Zoom_err_thalion,a1
	bsr	Zoom_copy
	move.l	Intro_h5+ZM_SCREEN,a0
	add.l	d0,a0
	lea	Zoom_err_ours,a1
	bsr	Zoom_copy
.out:	rts
.only:	bra	Zoom_ours

; Zoom_rows_range -- d0 = offset of the first destination row in the screen,
; d1 = bytes of all destination rows (0 or less: no rows).
Zoom_rows_range:
	moveq	#0,d0
	move.w	Intro_h5+ZM_BASE+ZM_Y,d0
	mulu	#ZM_LINE,d0
	moveq	#0,d1
	move.w	Intro_h5+ZM_BASE+ZM_ROWS,d1
	cmp.w	#ZM_CHECK_ROWS,d1
	bls.b	.r
	move.w	#ZM_CHECK_ROWS,d1
.r:	mulu	#ZM_LINE,d1
	tst.l	d1
	rts

; Zoom_copy -- d1 bytes from a0 to a1 (even).  Keeps d0-d1.
Zoom_copy:
	movem.l	d0-d1/a0-a1,-(sp)
	lsr.l	#1,d1
	bra.b	.c1
.c0:	move.w	(a0)+,(a1)+
.c1:	subq.l	#1,d1
	bpl.b	.c0
	movem.l	(sp)+,d0-d1/a0-a1
	rts
ZM_CHECK_ROWS	equ	256
	endc

	SECTION	Intro_bss,bss
Zoom_store_used:	ds.l	1
Zoom_screen:		ds.l	1	; its entry when the screen is a target
Zoom_slots:		ds.b	ZS_SIZE*ZM_SLOTS
Zoom_groups:		ds.w	1
Zoom_unhandled:		ds.w	1
Zoom_map:		ds.w	16*ZM_MAXGROUPS
Zoom_masks:		ds.w	ZM_MAXGROUPS
Zoom_folded:		ds.l	1	; the source row now in Zoom_line
Zoom_line:		ds.b	ZL_SIZE*ZM_MAXGROUPS
ZM_SCRATCH	equ	ZM_MAXWIDTH*256
Zoom_scratch:		ds.b	ZM_SCRATCH
Zoom_store:		ds.b	ZM_STORE
	ifd	CHECK_ZOOM
Zoom_calls:		ds.l	1
Zoom_errors:		ds.l	1
Zoom_first_error:	ds.l	1
Zoom_before:		ds.b	ZM_LINE*ZM_CHECK_ROWS
Zoom_thalion:		ds.b	ZM_LINE*ZM_CHECK_ROWS
Zoom_err_vars:		ds.b	ZM_ROWTAB+2*256
Zoom_err_thalion:	ds.b	ZM_LINE*ZM_CHECK_ROWS
Zoom_err_ours:		ds.b	ZM_LINE*ZM_CHECK_ROWS
	endc

	SECTION	Intro_data,data
; Zoom_spread -- per colour (times 4) a long with the colour's plane n in
; bit 0 of byte 3-n (the Falcon's Zm_spreiz).
Zoom_spread:
	dc.l	$00000000,$01000000,$00010000,$01010000
	dc.l	$00000100,$01000100,$00010100,$01010100
	dc.l	$00000001,$01000001,$00010001,$01010001
	dc.l	$00000101,$01000101,$00010101,$01010101
	SECTION	Intro_code,code

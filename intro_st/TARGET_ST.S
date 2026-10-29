; ***************************************************************************
; TARGET_ST.S -- Thalion's screens in ST format, shown directly (the ST's
; counterpart of the Falcon's amiga/AMIGA_ZIEL.S, docs/11 7.8; the same
; method, docs/05c-ST.md "ST intro", "Target screens").  No SECTION of its
; own: it lies in the code of INTRO_ST.S.
;
; The program names in Screen_table the Amiga screens the Shifter is to
; show directly (macro SCREEN).  Screens_setup gives each one a target
; screen in ST format (four planes word-interleaved, 160 bytes a line).
; **The target screen is authoritative.**  Thalion's Amiga screen stays as a
; buffer: a line there holds while its flag in SC_VALID is set.
;
; Five planes (the logo phase and the menu; the ST has four): planes 0-3
; go into the target as they are, plane 4 by the screen's mode (SC_MODE):
;   MODE_STARS  the logo phase: plane 4 holds only Thalion's stars, and they
;               live only in the target (Logo_stars draws them each VBL),
;               in Overlay_register, where planes 0-3 are 0, as on the
;               Amiga a star behind the logo stays hidden.  Each screen keeps
;               a list of the pixels it set (SC_STARS), so a star can go
;               again: whoever writes target rows takes the stars out of
;               them first (Stars_remove), fetching takes them out of the
;               buffer copy (Stars_unmix).  "Valid" means planes 0-3.
;   MODE_TEXT   the menu: plane 4 holds Thalion's text and is laid over
;               planes 0-3 in Overlay_register wherever it is set.  That
;               cannot be fetched back, so the buffer of such a screen is
;               always valid: nothing writes the target alone (no Blit_way).
;
; Who writes:
;   - blits (Amiga_blit -> Blit_redirect):
;       * straight into the target where there is a way for it
;         (Blit_way): the buffer lines no longer hold afterwards
;       * otherwise through the buffer: fetch the lines it touches (only the
;         invalid ones), Thalion's blit there, bring the lines of D into the
;         target
;   - our routines instead of Thalion's CPU (K3, INTRO_ST.S): the target,
;     then Rows_invalid
;   - Thalion's CPU at known places (K3): fetch before, bring after
;     (Screen_before/Screen_after, All_ensure/All_bring)
;
; Different from the Falcon, for the ST (docs/05c): fetching and bringing
; is CPU work (the Falcon's blitter does it there), so it does not hold the
; VBL off; a VBL during it fetches the same lines again at most, which
; changes nothing.  The ST shows the target with the window moved through
; the low byte of the video base, which only the STE has; the plain ST
; shows directly only where the base falls on 256 bytes and converts
; elsewhere (Twinlake's shaking).
;
; CHECK_TARGET (VASM_EXTRA="-DCHECK_TARGET", as the Falcon's BLIT_PRUEF):
; every write straight into the target also runs Thalion's way through the
; buffer, and the lines are compared (Target_errors); the VBL compares a
; few valid lines each time (Verify_errors), which finds a Thalion CPU
; writer we do not know.  Every writer of ours runs inside Target_busy, so
; that compare never sees lines written but not yet marked.
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3: Thalion's screens
; in ST format, blits redirected.
; ***************************************************************************

; An entry of Screen_table (macro SCREEN, the table ends with dc.l 0)
SC_AMIGA	equ	0		; .l Thalion's screen (planes row by row)
SC_ROWS		equ	4		; .w in the target (at most ST_LINES)
SC_PLANES	equ	6		; .w 4 or 5 (the ST target has four)
SC_MODE		equ	8		; .w plane 4: MODE_FOUR, _STARS, _TEXT
SC_ALL		equ	10		; .w Thalion's rows (also below the target)
SC_LINE		equ	12		; .w bytes a row of the buffer: planes * 40
SC_END		equ	14		; .l behind the rows in the target
SC_TARGET	equ	18		; .l row 0 of the target screen
SC_VALID	equ	22		; .l a byte a row: buffer = target
SC_STARS	equ	26		; .l MODE_STARS: its star list (STAR_LIST)
SC_INVALID	equ	30		; .b a row does not hold
SC_SIZE		equ	32

SCREEN		macro			; address, rows, planes, mode
	dc.l	\1
	dc.w	\2,\3,\4,\2
	dcb.b	SC_SIZE-12,0
	endm

; ***************************************************************************
; Screens_setup -- from Screen_table: target screens, flags, star lists,
; Direct_from/to.  The buffer is brought into the target once, whole
; (Thalion's screen can carry data).  An entry with other than four or five
; planes, or five without a mode, ends the table.
;   Changes d0-d7/a0-a5.
; ***************************************************************************
Screens_setup:
	clr.l	Direct_from
	clr.l	Direct_to
	move.l	#Target_memory+255,d0
	and.l	#-256,d0
	move.l	d0,d3			; next target screen
	lea	Valid_memory,a2
	lea	Star_lists,a3
	lea	Screen_table,a5
	moveq	#TARGET_MAX-1,d7
.e:	move.l	SC_AMIGA(a5),d1
	beq	.out
	move.w	SC_PLANES(a5),d0
	cmp.w	#4,d0
	beq.b	.planes
	cmp.w	#5,d0
	bne.b	.end
	tst.w	SC_MODE(a5)
	bne.b	.planes
.end:	clr.l	SC_AMIGA(a5)
	bra	.out
.planes:
	mulu	#AMIGA_ROW,d0
	move.w	d0,SC_LINE(a5)
	cmp.w	#ST_LINES,SC_ROWS(a5)
	bls.b	.rows
	move.w	#ST_LINES,SC_ROWS(a5)
.rows:	moveq	#0,d2
	move.w	SC_ROWS(a5),d2
	mulu	d0,d2
	add.l	d1,d2
	move.l	d2,SC_END(a5)
	add.l	#TARGET_MARGIN*ST_LINE,d3	; black lines above and below
	move.l	d3,SC_TARGET(a5)
	add.l	#(ST_LINES+TARGET_MARGIN)*ST_LINE,d3
	move.l	a2,SC_VALID(a5)
	lea	ST_LINES(a2),a2
	move.l	a3,SC_STARS(a5)
	clr.w	(a3)			; no star set
	lea	STAR_LIST(a3),a3
	tst.l	Direct_to		; range of all screens
	beq.b	.first
	cmp.l	Direct_from,d1
	bhs.b	.from
.first:	move.l	d1,Direct_from
.from:	cmp.l	Direct_to,d2
	bls.b	.to
	move.l	d2,Direct_to
.to:	move.l	SC_TARGET(a5),a0	; all black: margins, lines below
	lea	-TARGET_MARGIN*ST_LINE(a0),a0
	move.w	#2*TARGET_MARGIN+ST_LINES,d1
	bsr	Lines_zero
	moveq	#0,d0
	move.w	SC_ROWS(a5),d1
	bsr	Rows_bring
	lea	SC_SIZE(a5),a5
	dbf	d7,.e
.out:	rts

; ***************************************************************************
; Screens_switch -- a0 = another table (SCREEN entries, dc.l 0) or 0 for
; none (the intro changes its screens between scenes).  The screens of the
; old table are fetched whole first, so Thalion's buffers hold everything
; again; then the new table goes into Screen_table and Screens_setup brings
; its screens into the target.  The display is judged anew at the next
; VBL.  The VBL (level 4) is held off meanwhile; the intro switches only
; while the lower part of the picture is black (docs/05c).
;   All registers are preserved.
; ***************************************************************************
Screens_switch:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0400,sr
	bsr	Pointer_remove		; SHOW_ST.S: it may lie in a target
	bsr	All_ensure
	lea	Screen_table,a1
	move.l	a0,d0
	beq.b	.end
	moveq	#TARGET_MAX-1,d1
.e:	tst.l	(a0)
	beq.b	.end
	moveq	#SC_SIZE/2-1,d0
.k:	move.w	(a0)+,(a1)+
	dbf	d0,.k
	dbf	d1,.e
.end:	clr.l	(a1)
	bsr	Screens_setup
	bsr	Display_forget		; SHOW_ST.S: judge the picture anew
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Target_clear -- the target lines d0 .. d0+d1-1 of the screen a5 to 0; the
; buffer lines no longer hold then (Rows_invalid).  Target_fill -- the same
; with the long word d2 in every plane (colour 15: -1).  The stars of those
; lines go first (MODE_STARS).
;   All registers are preserved.
; ***************************************************************************
Target_clear:
	move.l	d2,-(sp)
	moveq	#0,d2
	bsr.b	Target_fill
	move.l	(sp)+,d2
	rts

Target_fill:
	movem.l	d0-d3/a0,-(sp)
	bsr	Rows_clip
	ble.b	.out
	bsr	Stars_remove
	bsr	Rows_invalid		; first: the VBL's check sees no valid row
	move.w	d0,d3			; written
	mulu	#ST_LINE,d3
	move.l	SC_TARGET(a5),a0
	add.l	d3,a0
	bsr	Lines_fill
.out:	movem.l	(sp)+,d0-d3/a0
	rts

; Lines_zero -- d1 ST lines from a0 on to 0.  Lines_fill -- the same with
; the long word d2.  All registers are preserved.
Lines_zero:
	move.l	d2,-(sp)
	moveq	#0,d2
	bsr.b	Lines_fill
	move.l	(sp)+,d2
	rts

Lines_fill:
	movem.l	d0-d7/a0-a4,-(sp)
	tst.w	d1
	ble.b	.out
	move.w	d1,d0
	mulu	#ST_LINE,d0
	add.l	d0,a0			; from the end down
	move.l	d2,d0
	move.l	d2,d3
	move.l	d2,d4
	move.l	d2,d5
	move.l	d2,d6
	move.l	d2,d7
	move.l	d2,a1
	move.l	d2,a2
	move.l	d2,a3
	subq.w	#1,d1
.l:	rept	ST_LINE/40
	movem.l	d0/d2-d7/a1-a3,-(a0)
	endr
	dbf	d1,.l
.out:	movem.l	(sp)+,d0-d7/a0-a4
	rts

; ***************************************************************************
; Screen_before / Screen_after -- around Thalion's CPU writing into the
; screen whose buffer starts at d0 (K3, once a scene): before, all its rows
; from the target into the buffer (only the invalid ones); after, all of
; them back into the target.  Not in the table: nothing.
;   All registers are preserved.
; ***************************************************************************
Screen_before:
	movem.l	d0-d1/a0/a5,-(sp)
	lea	Rows_ensure,a0
	bra.b	Screen_whole
Screen_after:
	movem.l	d0-d1/a0/a5,-(sp)
	lea	Rows_bring,a0
Screen_whole:
	bsr	Screen_find
	beq.b	.out
	moveq	#0,d0
	move.w	SC_ROWS(a5),d1
	jsr	(a0)
.out:	movem.l	(sp)+,d0-d1/a0/a5
	rts

; ***************************************************************************
; Screen_find -- d0.l = address -> a5 = its entry, Z clear; otherwise Z set.
;   Changes a5.
; ***************************************************************************
Screen_find:
	cmp.l	Direct_from,d0
	blo.b	.no
	cmp.l	Direct_to,d0
	bhs.b	.no
	lea	Screen_table,a5
.e:	tst.l	SC_AMIGA(a5)
	beq.b	.no
	cmp.l	SC_AMIGA(a5),d0
	blo.b	.n
	cmp.l	SC_END(a5),d0
	blo.b	.yes
.n:	lea	SC_SIZE(a5),a5
	bra.b	.e
.yes:	andi.b	#$FB,ccr		; Z clear
	rts
.no:	ori.b	#$04,ccr		; Z set
	rts

; ***************************************************************************
; Rows_bring -- rows d0 .. d0+d1-1 of the screen a5 from the buffer into
; the target; they hold afterwards.  Rows_fetch -- the same rows from the
; target into the buffer.  Both clip to the screen.  A row costs about
; 1000 cycles (80 words).  Five planes: planes 0-3 as four; bringing takes
; the stars out of the target rows first (MODE_STARS) or lays the text
; over them afterwards (MODE_TEXT); fetching takes the stars out of the
; buffer copy and leaves plane 4 of the buffer alone.
;   All registers are preserved.
; ***************************************************************************
Rows_bring:
	movem.l	d0-d3/a0-a4,-(sp)
	bsr	Rows_clip
	ble	.out
	bsr	Stars_remove
	bsr	Rows_address
	move.w	SC_LINE(a5),d3
	sub.w	#AMIGA_ROW,d3		; behind plane 0 of a row to the next
	move.w	d1,d2
	subq.w	#1,d2
.row:	lea	AMIGA_ROW(a0),a2
	lea	2*AMIGA_ROW(a0),a3
	lea	3*AMIGA_ROW(a0),a4
	rept	AMIGA_ROW/2
	move.w	(a0)+,(a1)+
	move.w	(a2)+,(a1)+
	move.w	(a3)+,(a1)+
	move.w	(a4)+,(a1)+
	endr
	add.w	d3,a0
	dbf	d2,.row
	cmp.w	#MODE_TEXT,SC_MODE(a5)
	bne.b	.valid
	bsr	Text_overlay
.valid:	subq.w	#1,d1
	bsr	Rows_valid
.out:	movem.l	(sp)+,d0-d3/a0-a4
	rts

Rows_fetch:
	movem.l	d0-d3/a0-a4,-(sp)
	bsr	Rows_clip
	ble	.out
	bsr	Rows_address
	move.w	SC_LINE(a5),d3
	sub.w	#AMIGA_ROW,d3
	move.w	d1,d2
	subq.w	#1,d2
.row:	lea	AMIGA_ROW(a0),a2
	lea	2*AMIGA_ROW(a0),a3
	lea	3*AMIGA_ROW(a0),a4
	rept	AMIGA_ROW/2
	move.w	(a1)+,(a0)+
	move.w	(a1)+,(a2)+
	move.w	(a1)+,(a3)+
	move.w	(a1)+,(a4)+
	endr
	add.w	d3,a0
	dbf	d2,.row
	bsr	Stars_unmix
	subq.w	#1,d1
	bsr	Rows_valid
.out:	movem.l	(sp)+,d0-d3/a0-a4
	rts

; Rows_address -- a0 = buffer, a1 = target of row d0 of the screen a5.
;   Changes d2/a0-a1.
Rows_address:
	move.w	d0,d2
	mulu	SC_LINE(a5),d2
	move.l	SC_AMIGA(a5),a0
	add.l	d2,a0
	move.w	d0,d2
	mulu	#ST_LINE,d2
	move.l	SC_TARGET(a5),a1
	add.l	d2,a1
	rts

; ***************************************************************************
; Text_overlay -- (MODE_TEXT) plane 4 of the buffer rows d0 .. d0+d1-1
; (clipped) over their target rows, in Overlay_register wherever it is set:
; the menu's text.  Groups without a plane-4 pixel cost a test.
;   All registers are preserved.
; ***************************************************************************
Text_overlay:
	movem.l	d0-d7/a0-a1,-(sp)
	bsr	Rows_address
	lea	4*AMIGA_ROW(a0),a0	; plane 4
	move.w	SC_LINE(a5),d6
	sub.w	#AMIGA_ROW,d6
	move.w	Overlay_register,d3	; bits: set or clear in plane n
	subq.w	#1,d1
.row:	moveq	#AMIGA_ROW/2-1,d7
.grp:	move.w	(a0)+,d0
	beq.b	.next
	move.w	d0,d5
	not.w	d5
	moveq	#0,d4			; plane
.p:	btst	d4,d3
	beq.b	.clr
	or.w	d0,(a1)+
	bra.b	.pn
.clr:	and.w	d5,(a1)+
.pn:	addq.w	#1,d4
	cmp.w	#4,d4
	blo.b	.p
	bra.b	.g
.next:	addq.l	#8,a1
.g:	dbf	d7,.grp
	add.w	d6,a0
	dbf	d1,.row
	movem.l	(sp)+,d0-d7/a0-a1
	rts

; Rows_valid -- the flags of rows d0 .. d0+d1 (count d1+1, after a dbf
; loop's subq) set.  Changes d2/a0.
Rows_valid:
	move.l	SC_VALID(a5),a0
	add.w	d0,a0
	move.w	d1,d2
.v:	st	(a0)+
	dbf	d2,.v
	rts

; Rows_clip -- d0/d1 to the rows of the screen a5; flags by d1 (le: none).
;   Changes d0-d1.
Rows_clip:
	tst.w	d0
	bpl.b	.top
	add.w	d0,d1
	moveq	#0,d0
.top:	move.w	SC_ROWS(a5),-(sp)
	sub.w	d0,(sp)			; rows from d0 on
	cmp.w	(sp),d1
	ble.b	.bottom
	move.w	(sp),d1
.bottom:
	addq.l	#2,sp
	tst.w	d1
	rts

; ***************************************************************************
; Rows_ensure -- the invalid ones among rows d0 .. d0+d1-1 of the screen a5
; fetched from the target.  Rows_invalid -- the same rows marked invalid
; (the target was written without the buffer).
;   All registers are preserved.
; ***************************************************************************
Rows_ensure:
	tst.b	SC_INVALID(a5)
	beq.b	.nothing
	movem.l	d0-d3/a0,-(sp)
	bsr	Rows_clip
	ble.b	.out
	move.l	SC_VALID(a5),a0
	move.w	d0,d2
	add.w	d1,d2			; end
.find:	cmp.w	d2,d0			; the next invalid one
	bhs.b	.out
	tst.b	0(a0,d0.w)
	beq.b	.run
	addq.w	#1,d0
	bra.b	.find
.run:	move.w	d0,d3			; up to the next valid one
.r:	addq.w	#1,d3
	cmp.w	d2,d3
	bhs.b	.fetch
	tst.b	0(a0,d3.w)
	beq.b	.r
.fetch:	moveq	#0,d1
	move.w	d3,d1
	sub.w	d0,d1
	bsr	Rows_fetch		; sets the flags
	move.w	d3,d0
	bra.b	.find
.out:	bsr.b	Flags_check
	movem.l	(sp)+,d0-d3/a0
.nothing:
	rts

Rows_invalid:
	movem.l	d0-d1/a0,-(sp)
	bsr	Rows_clip
	ble.b	.out
	move.l	SC_VALID(a5),a0
	add.w	d0,a0
	subq.w	#1,d1
.u:	clr.b	(a0)+
	dbf	d1,.u
	st	SC_INVALID(a5)		; only now: Flags_check in the VBL
.out:	movem.l	(sp)+,d0-d1/a0
	rts

; Flags_check -- SC_INVALID(a5) cleared when all rows hold.  Changes d0/a0.
Flags_check:
	move.l	SC_VALID(a5),a0
	move.w	SC_ROWS(a5),d0
	subq.w	#1,d0
.c:	tst.b	(a0)+
	dbeq	d0,.c
	beq.b	.out			; one does not hold
	clr.b	SC_INVALID(a5)
.out:	rts

; ***************************************************************************
; All_ensure -- all rows of all screens hold (before converting, which reads
; the buffer).  All_bring -- all rows of all screens into the target (after
; Thalion's CPU, K3).
;   All registers are preserved.
; ***************************************************************************
All_ensure:
	movem.l	d0-d1/a0/a5,-(sp)
	lea	Rows_ensure,a0
	bra.b	All_screens
All_bring:
	movem.l	d0-d1/a0/a5,-(sp)
	lea	Rows_bring,a0
All_screens:
	lea	Screen_table,a5
	moveq	#TARGET_MAX-1,d1
.e:	tst.l	SC_AMIGA(a5)
	beq.b	.out
	move.w	d1,-(sp)
	moveq	#0,d0
	move.w	SC_ROWS(a5),d1
	jsr	(a0)
	move.w	(sp)+,d1
	lea	SC_SIZE(a5),a5
	dbf	d1,.e
.out:	movem.l	(sp)+,d0-d1/a0/a5
	rts

; ***************************************************************************
; Target_free -- before writing the target of screen a5 from the main flow:
; if this frame shows it (Frame_base in it) and a new base waits elsewhere
; (Base_now, Base_set), wait for the next VBL, when the Shifter takes the
; new base.  On the Amiga a new copper list also holds from the next frame,
; and Thalion's frames never last longer than Thalion's wait; ours can, and
; then Thalion drew into the picture still shown (the Falcon's T66, the
; clouds; Ziel_frei in amiga/AMIGA_ZIEL.S).  A target that stays shown
; (Base_now in it: the menu) is written at once.  Inside the VBL or with it
; held off (level 4 or more) it returns at once.
;   All registers are preserved.
; ***************************************************************************
Target_free:
	movem.l	d0-d1,-(sp)
	move.w	sr,d0
	and.w	#$0700,d0
	cmp.w	#$0300,d0
	bhi.b	.out			; in the VBL or held off: no wait
	move.l	Frame_base,d0
	bsr.b	.inside
	bhs.b	.out			; this frame shows another picture
	move.l	Base_now,d0
	bsr.b	.inside
	blo.b	.out			; it stays shown
	move.l	Vbl_count,d0
.wait:	cmp.l	Vbl_count,d0
	beq.b	.wait
.out:	movem.l	(sp)+,d0-d1
	rts
; .inside -- C set when the address d0 lies in the target screen of a5,
; its black margins included.  Changes d0-d1.
.inside:
	move.l	SC_TARGET(a5),d1
	sub.l	#TARGET_MARGIN*ST_LINE,d1
	sub.l	d1,d0
	cmp.l	#TARGET_SIZE,d0
	rts

; ***************************************************************************
; Blit_redirect -- from Amiga_blit while screens are in the table.  When no
; channel used lies in a screen, the blit runs as always.  Otherwise
; straight into the target (Blit_way) or through the buffer.  A channel
; counts as in a screen also when it starts one word before it (Thalion's
; clouds at row 0, $4E2A).  While it writes the target shown, the pointer
; and the stars keep out (Shown_enter).
;   Changes d0-d7/a0-a6.
; ***************************************************************************
Blit_redirect:
	ifd	CHECK_TARGET
	tst.b	Blit_no_redirect
	bne	Blit_amiga
	endc
	lea	Amiga_register,a6
	moveq	#0,d7			; channels in a screen: 8 A, 4 B, 2 C, 1 D
	lea	Bl_channel,a0
	lea	Bl_registers,a1
	moveq	#3,d6			; bit 11 (A) .. 8 (D) of BLTCON0
.k:	clr.l	(a0)
	btst	d6,AR_BLTCON0(a6)	; in the high byte: bits 11 .. 8
	beq.b	.kn
	move.w	(a1),d1
	move.l	0(a6,d1.w),d0
	and.w	#-2,d0
	bsr	Screen_find
	bne.b	.in
	addq.l	#2,d0
	bsr	Screen_find
	beq.b	.kn
.in:	move.l	a5,(a0)
	bset	d6,d7
.kn:	addq.l	#4,a0
	addq.l	#4,a1
	dbf	d6,.k
	tst.w	d7
	beq	Blit_amiga
	move.l	Bl_channel+12,d0	; D's target: still shown this frame?
	beq.b	.free
	move.l	d0,a5
	bsr	Target_free
.free:	sf	Bl_shown
	move.l	Bl_channel+12,d0	; D in the target shown?
	beq.b	.way
	cmp.l	Shown_entry,d0
	bne.b	.way
	st	Bl_shown
	bsr	Shown_enter		; SHOW_ST.S
.way:	bsr	Blit_way
	beq.b	.buffer
	addq.l	#1,Blit_direct
	move.l	Bl_channel+12,a5	; its stars out of the rows of D first
	movem.w	Bl_d_rows,d0-d1
	bsr	Stars_remove
	ifd	CHECK_TARGET
	bsr	Blit_way_check
	else
	jsr	(a0)
	bsr	Blit_tail
	endc
	bra.b	.leave

; through the buffer: fetch first, then Thalion's blit, then bring
.buffer:
	bsr.b	.through
.leave:	tst.b	Bl_shown
	beq.b	.out
	bsr	Shown_leave
.out:	rts

.through:
	addq.l	#1,Blit_buffered
	addq.w	#1,Target_busy
	lea	Bl_channel,a0
	lea	Bl_registers,a1
	moveq	#3,d6
.f:	move.l	(a0),d0
	beq.b	.fn
	move.l	d0,a5
	move.w	(a1),d1
	move.l	0(a6,d1.w),d4
	move.w	2(a1),d1
	move.w	0(a6,d1.w),d2
	bsr	Channel_rows
	bsr	Rows_ensure
	tst.w	d6			; D: its rows for afterwards
	bne.b	.fn
	movem.w	d0-d1,Bl_d_rows
.fn:	addq.l	#4,a0
	addq.l	#4,a1
	dbf	d6,.f
	bsr	Blit_amiga
	move.l	Bl_channel+12,d0	; D in a screen?
	beq.b	.done
	move.l	d0,a5
	movem.w	Bl_d_rows,d0-d1
	bsr	Rows_bring
.done:	subq.w	#1,Target_busy
	rts

; ***************************************************************************
; Channel_rows -- the rows of the screen a5 a channel sweeps: d4 = pointer,
; d2 = modulo (bit 0 does not count), a6 = Amiga_register (size,
; direction) -> d0 = first row, d1 = rows (also 0).  The range as the
; blitter runs: row r starts (descending: ends) at pointer + r * step,
; step = 2 * words + modulo, also negative.
;   Changes d0-d5.
; ***************************************************************************
Channel_rows:
	and.w	#-2,d4
	and.w	#-2,d2
	bsr	Blit_size		; d0 rows, d1 words
	add.w	d1,d1			; 2 * words
	add.w	d1,d2			; step
	subq.w	#1,d0
	muls	d2,d0			; (rows - 1) * step
	moveq	#0,d2			; min(0, ..)
	moveq	#0,d3			; max(0, ..)
	tst.l	d0
	bmi.b	.neg
	move.l	d0,d3
	bra.b	.span
.neg:	move.l	d0,d2
.span:	ext.l	d1
	subq.l	#2,d1			; offset of the last word of a row
	btst	#1,AR_BLTCON1+1(a6)
	beq.b	.asc
	move.l	d4,d5			; descending: p - max - row .. p - min
	sub.l	d3,d5
	sub.l	d1,d5
	sub.l	d2,d4
	bra.b	.range
.asc:	move.l	d4,d5			; ascending: p + min .. p + max + row
	add.l	d2,d5
	add.l	d3,d4
	add.l	d1,d4
.range:					; [d5, d4] bytes, both included
	move.l	SC_AMIGA(a5),d0
	sub.l	d0,d5
	bpl.b	.v
	moveq	#0,d5
.v:	sub.l	d0,d4
	move.l	SC_END(a5),d1
	sub.l	d0,d1
	subq.l	#1,d1
	cmp.l	d1,d4
	ble.b	.b
	move.l	d1,d4
.b:	moveq	#0,d1
	cmp.l	d5,d4
	blt.b	.empty
	divu	SC_LINE(a5),d5
	divu	SC_LINE(a5),d4
	moveq	#0,d0
	move.w	d5,d0			; first row
	move.w	d4,d1
	sub.w	d5,d1
	addq.w	#1,d1
	rts
.empty:	moveq	#0,d0
	rts

; Blit_size -- BLTSIZE: d0 = rows (1-1024), d1 = words (1-64).
Blit_size:
	move.w	AR_BLTSIZE(a6),d0
	move.w	d0,d1
	lsr.w	#6,d0
	subq.w	#1,d0
	and.w	#$3FF,d0
	addq.w	#1,d0
	and.w	#$3F,d1
	subq.w	#1,d1
	and.w	#$3F,d1
	addq.w	#1,d1
	rts

; ***************************************************************************
; Blit_way -- a channel lies in a screen (d7 as in Blit_redirect): is there
; a way straight into the target?  Then a0 = the way, Z clear, and Bl_d_*
; and Bl_skip are set.  Conditions: D in a screen that is not MODE_TEXT, A
; and B not, C not used or C = D (pointer and modulo); ascending; each row
; of D stays in one of planes 0-3 of one Amiga row; the step from row to
; row is whole Amiga rows; D stays in the screen.  Then D has a fixed step
; in the target per word (8) and per row (Bl_d_rowstep).  The ways: clear
; ($00, D), copy ($F0, A D, no shift, no mask), the masked blit ($CA,
; A B C D).  The Falcon's ways: $D8 (extro), $CA, $F0 and the text
; (docs/11 7.8b); the ST has these three.
;
; Bl_skip: a $CA blit whose first word cannot change D (AFWM < 1 << ASH:
; A's first word, masked and shifted, is 0, so D = C) starts with its
; second word; the first word only feeds the shifters (Way_ca).  Thalion's
; clouds ($4E2A) start a word left of the row, before the screen at row 0
; and in the plane before elsewhere (the Falcon's Bl_erstes_wort).
;   Changes d0-d6/a0/a5.
; ***************************************************************************
Blit_way:
	btst	#0,d7			; D
	beq	.no
	move.w	d7,d0
	and.w	#%1100,d0		; A, B
	bne	.no
	btst	#1,AR_BLTCON1+1(a6)	; descending
	bne	.no
	move.w	AR_BLTCON0(a6),d2
	btst	#9,d2			; C used: only as C = D
	beq.b	.c
	btst	#1,d7
	beq	.no
	move.l	AR_BLTCPT(a6),d0
	cmp.l	AR_BLTDPT(a6),d0
	bne	.no
	move.w	AR_BLTCMOD(a6),d0
	cmp.w	AR_BLTDMOD(a6),d0
	bne	.no
.c:	move.w	d2,d0			; the way by the pattern
	and.w	#$0FFF,d0
	lea	Way_clear,a0
	cmp.w	#$0100,d0
	beq.b	.geometry
	lea	Way_copy,a0
	cmp.w	#$09F0,d0
	bne.b	.ca
	and.w	#$F000,d2		; A not shifted, no mask
	bne	.no
	cmp.l	#-1,AR_BLTAFWM(a6)
	bne	.no
	bra.b	.geometry
.ca:	lea	Way_ca,a0
	cmp.w	#$0FCA,d0
	bne	.no
.geometry:
	move.l	Bl_channel+12,a5
	cmp.w	#MODE_TEXT,SC_MODE(a5)
	beq	.no			; plane 4 there needs the buffer
	bsr	Blit_size		; d0 rows, d1 words
	move.w	d0,d5
	move.w	d1,d6
	move.w	AR_BLTDMOD(a6),d2
	and.w	#-2,d2
	add.w	d6,d2
	add.w	d6,d2			; step
	ble	.no
	ext.l	d2
	move.l	d2,Bl_d_step
	move.l	AR_BLTDPT(a6),d0
	and.w	#-2,d0
	move.l	d0,d4			; Amiga pointer
	sf	Bl_skip
	cmp.l	#Way_ca,a0
	bne.b	.place
	cmp.w	#2,d6
	blo.b	.place
	move.w	AR_BLTCON0(a6),d1
	rol.w	#4,d1
	and.w	#15,d1			; ASH
	moveq	#1,d3
	lsl.w	d1,d3
	cmp.w	AR_BLTAFWM(a6),d3
	bls.b	.place			; the first word can change D
	st	Bl_skip
	subq.w	#1,d6			; words written
	addq.l	#2,d0
.place:	sub.l	SC_AMIGA(a5),d0
	bmi	.no
	divu	SC_LINE(a5),d0
	moveq	#0,d1
	move.w	d0,d1			; y0
	clr.w	d0
	swap	d0
	divu	#AMIGA_ROW,d0		; plane : byte in the plane
	move.w	d0,d3			; plane
	cmp.w	#4,d3
	bhs	.no			; plane 4 is not in the target
	swap	d0			; byte
	move.w	d6,d2
	add.w	d2,d2
	add.w	d0,d2
	cmp.w	#AMIGA_ROW,d2		; stays in the plane?
	bhi	.no
	lsr.w	#1,d0			; word
	lsl.w	#3,d0			; group in the ST line
	add.w	d3,d3
	add.w	d3,d0			; offset in the target line
	ext.l	d0
	move.l	Bl_d_step,d2
	divu	SC_LINE(a5),d2
	swap	d2
	tst.w	d2
	bne	.no			; not whole rows
	swap	d2			; k
	clr.w	Bl_tail
	move.w	d5,d3
	subq.w	#1,d3
	mulu	d2,d3
	add.l	d1,d3			; last row
	cmp.l	#$FFFF,d3
	bhi	.no
	cmp.w	SC_ROWS(a5),d3
	blo.b	.inside
	; rows below the target (Thalion's clouds reach row 255): the way takes
	; those in it, Blit_tail the rest in the buffer
	moveq	#0,d3
	move.w	SC_ROWS(a5),d3
	subq.w	#1,d3
	sub.w	d1,d3
	bmi	.no			; starts below the target
	divu	d2,d3
	addq.w	#1,d3			; rows in the target
	sub.w	d3,d5
	move.w	d5,Bl_tail
	move.w	d3,d5
	subq.w	#1,d3
	mulu	d2,d3
	add.l	d1,d3			; last row in the target
.inside:
	move.w	d5,Bl_way_rows
	subq.w	#1,Bl_way_rows		; as BV_ROWS
	sub.w	d1,d3
	addq.w	#1,d3
	movem.w	d1/d3,Bl_d_rows		; for Rows_invalid
	mulu	#ST_LINE,d1
	add.l	SC_TARGET(a5),d1
	add.l	d0,d1
	move.l	d1,Bl_d_target
	mulu	#ST_LINE,d2		; row step in the target
	lsl.w	#3,d6
	sub.w	d6,d2
	move.w	d2,Bl_d_rowstep
	move.l	Bl_d_step,d2		; D afterwards, an Amiga address
	mulu	d5,d2
	add.l	d4,d2
	move.l	d2,Bl_d_end
	moveq	#1,d0			; Z clear
	rts
.no:	ori.b	#$04,ccr		; Z set
	rts

; Blit_tail -- after a way: the rows of the blit below the target (Bl_tail)
; in the buffer, from where the way left the pointers.  Changes d0-d7/a0-a6.
Blit_tail:
	move.w	Bl_tail,d1
	beq.b	.out
	lea	Amiga_register,a6
	move.w	AR_BLTSIZE(a6),d0
	and.w	#$3F,d0			; the words
	lsl.w	#6,d1
	or.w	d1,d0
	move.w	d0,AR_BLTSIZE(a6)
	bra	Blit_amiga
.out:	rts

; ***************************************************************************
; The ways into the target (Blit_way): the blit decoded as Amiga_blit does
; (Blit_decode), D (and C = D) in the target 8 bytes a word apart.  Then
; the pointers behind the blit as the blitter leaves them, and the rows of
; D invalid in the buffer.
; ***************************************************************************
Way_clear:
	bsr	Blit_decode
	move.w	Bl_way_rows,BV_ROWS(a5)
	move.l	Bl_d_target,a3
	move.w	Bl_d_rowstep,d6
	move.w	BV_ROWS(a5),d1
	moveq	#0,d0
.row:	move.w	BV_WIDTH(a5),d7
.w:	move.w	d0,(a3)
	addq.l	#8,a3
	dbf	d7,.w
	add.w	d6,a3
	dbf	d1,.row
	bra	Way_end

Way_copy:
	bsr	Blit_decode
	move.w	Bl_way_rows,BV_ROWS(a5)
	move.l	Bl_d_target,a3
	move.w	Bl_d_rowstep,d6
	move.w	BV_AMOD(a5),d5
	move.w	BV_ROWS(a5),d1
.row:	move.w	BV_WIDTH(a5),d7
.w:	move.w	(a0)+,(a3)
	addq.l	#8,a3
	dbf	d7,.w
	add.w	d5,a0
	add.w	d6,a3
	dbf	d1,.row
	bra	Way_end

; Way_ca -- as Blit_ca (BLIT_ST.S), with C read where D is written.  With
; Bl_skip the first word of a row only feeds the shifters (Blit_way).
Way_ca:
	bsr	Blit_decode
	move.w	Bl_way_rows,BV_ROWS(a5)
	move.l	Bl_d_target,a3
	moveq	#0,d3
	moveq	#0,d4
	move.w	BV_ASH(a5),d5
	move.w	BV_BSH(a5),d6
.row:	move.w	BV_WIDTH(a5),d7
	move.w	BV_FWM(a5),d2		; mask of the first word
	tst.b	Bl_skip
	beq.b	.first
	swap	d3
	move.w	(a0)+,d3
	and.w	d2,d3
	swap	d4
	move.w	(a1)+,d4
	moveq	#-1,d2
	subq.w	#1,d7			; two words at least (Blit_way)
	bne.b	.w
	move.w	BV_LWM(a5),d2		; the next is the last
	bra.b	.w
.first:	tst.w	d7
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
	and.w	(a3),d0			; C
	or.w	d1,d0
	move.w	d0,(a3)
	addq.l	#8,a3
	moveq	#-1,d2
	subq.w	#1,d7
	bmi.b	.end
	bne.b	.w
	move.w	BV_LWM(a5),d2		; the last word
	bra.b	.w
.end:	add.w	BV_AMOD(a5),a0
	add.w	BV_BMOD(a5),a1
	add.w	Bl_d_rowstep,a3
	subq.w	#1,BV_ROWS(a5)
	bpl.b	.row

Way_end:
	move.l	a0,AR_BLTAPT(a6)
	move.l	a1,AR_BLTBPT(a6)
	move.l	Bl_d_end,d0
	move.l	d0,AR_BLTDPT(a6)
	btst	#USE_C,BV_USE+1(a5)
	beq.b	.c
	move.l	d0,AR_BLTCPT(a6)
.c:	move.l	Bl_channel+12,a5
	movem.w	Bl_d_rows,d0-d1
	bra	Rows_invalid

	ifd	CHECK_TARGET
; ***************************************************************************
; Blit_way_check -- (CHECK_TARGET) the way into the target (a0) against the
; way through the buffer, as the Falcon's Bl_ziel_pruefen: the rows of D
; made valid, Thalion's blit in the buffer, the pointers kept, put back,
; then the way into the target; the pointers and the rows compared
; (Rows_compare counts in Target_errors and makes equal rows valid).
; ***************************************************************************
Blit_way_check:
	move.l	a0,Ct_way
	addq.w	#1,Target_busy
	move.l	Bl_channel+12,a5
	movem.w	Bl_d_rows,d0-d1
	bsr	Rows_ensure
	movem.l	AR_BLTCPT(a6),d0-d3	; C, B, A, D
	movem.l	d0-d3,Ct_before
	st	Blit_no_redirect
	bsr	Amiga_blit		; into the buffer
	sf	Blit_no_redirect
	lea	Amiga_register,a6
	movem.l	AR_BLTCPT(a6),d0-d3
	movem.l	d0-d3,Ct_after
	movem.l	Ct_before,d0-d3
	movem.l	d0-d3,AR_BLTCPT(a6)
	move.l	Ct_way,a0
	jsr	(a0)			; into the target
	bsr	Blit_tail
	lea	Amiga_register+AR_BLTCPT,a0
	lea	Ct_after,a1
	moveq	#4-1,d0
.p:	cmpm.l	(a0)+,(a1)+
	dbne	d0,.p
	beq.b	.rows
	addq.l	#1,Target_errors
.rows:	move.l	Bl_channel+12,a5
	movem.w	Bl_d_rows,d0-d1
	moveq	#CT_BLIT,d2
	bsr	Rows_compare
	subq.w	#1,Target_busy
	rts

; ***************************************************************************
; Rows_compare -- (CHECK_TARGET) rows d0 .. d0+d1-1 of the screen a5: buffer
; against target.  An equal row becomes valid; a different one counts in
; Target_errors (the first: Target_first = d2 where, row, VBL) and stays
; invalid (the target holds what our routine wrote).
;   All registers are preserved.
; ***************************************************************************
CT_BLIT		equ	1		; where (Target_first_where)
CT_CLEAR	equ	2
CT_STARS	equ	3
CT_EOR		equ	4
CT_COPY		equ	5
CT_ZOOM		equ	6
CT_VERIFY	equ	7

Rows_compare:
	movem.l	d0-d3/a0-a1,-(sp)
	bsr	Rows_clip
	ble.b	.out
	move.w	d1,d3
	subq.w	#1,d3
.row:	bsr	Row_equal
	bne.b	.diff
	move.l	SC_VALID(a5),a0
	st	0(a0,d0.w)
	bra.b	.next
.diff:	bsr	Target_error
.next:	addq.w	#1,d0
	dbf	d3,.row
	bsr	Flags_check
.out:	movem.l	(sp)+,d0-d3/a0-a1
	rts

; Target_error -- count one, the first with d2 (where) and row d0.
Target_error:
	addq.l	#1,Target_errors
	tst.w	Target_first_where
	bne.b	.out
	move.w	d2,Target_first_where
	move.w	d0,Target_first_row
	move.l	Vbl_count,Target_first_vbl
.out:	rts

; Row_equal -- Z set when buffer row d0 of the screen a5 equals its target
; row.  All registers are preserved.
Row_equal:
	movem.l	d1-d2/a0-a4,-(sp)
	bsr	Rows_address
	lea	AMIGA_ROW(a0),a2
	lea	2*AMIGA_ROW(a0),a3
	lea	3*AMIGA_ROW(a0),a4
	moveq	#AMIGA_ROW/2-1,d1
.g:	cmpm.w	(a0)+,(a1)+
	bne.b	.out
	cmpm.w	(a2)+,(a1)+
	bne.b	.out
	cmpm.w	(a3)+,(a1)+
	bne.b	.out
	cmpm.w	(a4)+,(a1)+
	dbne	d1,.g
.out:	movem.l	(sp)+,d1-d2/a0-a4
	rts

; Check_rows -- (CHECK_TARGET) before a write of ours straight into the
; target: rows d0 .. d0+d1-1 of the screen a5 valid, so that Thalion's way
; in the buffer and ours in the target start from the same picture.
;   All registers are preserved.
Check_rows:
	addq.w	#1,Target_busy
	bra	Rows_ensure

; ***************************************************************************
; Target_verify -- (CHECK_TARGET, from the VBL) VERIFY_ROWS valid rows a
; time, round robin over the screens: buffer against target.  A difference
; means a writer that changed one of them without the other (a Thalion CPU
; writer not known to us): Verify_errors, the first in Verify_first_*.
; Not while our own writing runs (Target_busy).
; ***************************************************************************
VERIFY_ROWS	equ	8

Target_verify:
	tst.w	Target_busy
	bne	.out
	tst.l	Direct_to
	beq	.out
	moveq	#VERIFY_ROWS-1,d3
.row:	move.w	Verify_screen,d0
	mulu	#SC_SIZE,d0
	lea	Screen_table,a5
	add.w	d0,a5
	tst.l	SC_AMIGA(a5)
	bne.b	.screen
	clr.w	Verify_screen		; past the last: the first again
	clr.w	Verify_row
	lea	Screen_table,a5
.screen:
	move.w	Verify_row,d0
	cmp.w	SC_ROWS(a5),d0
	blo.b	.check
	clr.w	Verify_row
	addq.w	#1,Verify_screen
	cmp.w	#TARGET_MAX,Verify_screen
	blo.b	.row
	clr.w	Verify_screen
	bra.b	.row
.check:	addq.w	#1,Verify_row
	cmp.w	#4,SC_PLANES(a5)
	bne.b	.next			; five planes: the target is not the buffer
	move.l	SC_VALID(a5),a0
	tst.b	0(a0,d0.w)
	beq.b	.next
	bsr	Row_equal
	beq.b	.next
	addq.l	#1,Verify_errors
	tst.l	Verify_first_vbl
	bne.b	.next
	move.l	Vbl_count,Verify_first_vbl
	move.w	Verify_screen,Verify_first_screen
	move.w	d0,Verify_first_row
.next:	dbf	d3,.row
.out:	rts
	endc

; ***************************************************************************
; The stars of the logo phase in the target (MODE_STARS, header).  A star
; is a pixel Logo_stars set in Overlay_register where planes 0-3 were 0;
; the list of its screen (SC_STARS) holds per star the target word of
; plane 0, the pixel mask and Thalion's offset of its word (row * 200 +
; byte of plane 0, even; = the offset in the buffer, the logo screens have
; 200 bytes a row).
;
; Stars_remove -- the stars in rows d0 .. d0+d1-1 of the screen a5 back to
; colour 0 and out of its list, before anyone writes those target rows.
; The VBL is held off meanwhile (Logo_stars works on the same list).
;   All registers are preserved.
; ***************************************************************************
Stars_remove:
	cmp.w	#MODE_STARS,SC_MODE(a5)
	bne.b	.none
	movem.l	d0-d5/a0-a2,-(sp)
	move.w	sr,-(sp)
	or.w	#$0400,sr
	move.l	SC_STARS(a5),a0
	move.w	(a0)+,d2
	beq.b	.out
	bsr	Stars_range		; d4/d5: target offsets
	move.l	a0,a1			; the stars kept
	moveq	#0,d1
	subq.w	#1,d2
.s:	move.l	(a0),d3
	sub.l	SC_TARGET(a5),d3
	cmp.l	d4,d3
	blo.b	.keep
	cmp.l	d5,d3
	bhs.b	.keep
	move.l	(a0)+,a2
	move.w	(a0)+,d3
	addq.l	#2,a0
	not.w	d3
	and.w	d3,(a2)+
	and.w	d3,(a2)+
	and.w	d3,(a2)+
	and.w	d3,(a2)+
	bra.b	.n
.keep:	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	addq.w	#1,d1
.n:	dbf	d2,.s
	move.l	SC_STARS(a5),a0
	move.w	d1,(a0)
.out:	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d5/a0-a2
.none:	rts

; Stars_range -- rows d0 .. d0+d1-1 as target offsets: d4 from, d5 to.
Stars_range:
	moveq	#0,d4
	move.w	d0,d4
	mulu	#ST_LINE,d4
	moveq	#0,d5
	move.w	d1,d5
	mulu	#ST_LINE,d5
	add.l	d4,d5
	rts

; Stars_unmix -- after Rows_fetch of rows d0 .. d0+d1-1 of the screen a5:
; the star pixels out of planes 0-3 of the buffer (they were 0 there).
;   All registers are preserved.
Stars_unmix:
	cmp.w	#MODE_STARS,SC_MODE(a5)
	bne.b	.none
	movem.l	d0-d5/a0-a2,-(sp)
	bsr	Stars_range
	move.l	SC_STARS(a5),a0
	move.w	(a0)+,d2
	bra.b	.n
.s:	move.l	(a0),d3
	sub.l	SC_TARGET(a5),d3
	cmp.l	d4,d3
	blo.b	.next
	cmp.l	d5,d3
	bhs.b	.next
	bsr.b	Star_buffer_word	; a2
	move.w	4(a0),d3
	not.w	d3
	and.w	d3,(a2)
	and.w	d3,AMIGA_ROW(a2)
	and.w	d3,2*AMIGA_ROW(a2)
	and.w	d3,3*AMIGA_ROW(a2)
.next:	addq.l	#STAR_ENTRY,a0
.n:	dbf	d2,.s
	movem.l	(sp)+,d0-d5/a0-a2
.none:	rts

; Stars_buffer -- plane 4 of the buffer of the screen a5 = its stars, all
; rows (Logo_end: Thalion's next code takes the stars from there).  Planes
; 0-3 must hold (Rows_ensure).  All registers are preserved.
Stars_buffer:
	movem.l	d0-d3/a0-a2,-(sp)
	move.l	SC_AMIGA(a5),a0
	lea	4*AMIGA_ROW(a0),a0
	move.w	SC_ROWS(a5),d1
	subq.w	#1,d1
	moveq	#0,d0
.r:	moveq	#AMIGA_ROW/4-1,d2
	move.l	a0,a1
.c:	move.l	d0,(a1)+
	dbf	d2,.c
	add.w	SC_LINE(a5),a0
	dbf	d1,.r
	move.l	SC_STARS(a5),a0
	move.w	(a0)+,d2
	bra.b	.n
.s:	bsr.b	Star_buffer_word
	move.w	4(a0),d3
	or.w	d3,4*AMIGA_ROW(a2)
	addq.l	#STAR_ENTRY,a0
.n:	dbf	d2,.s
	movem.l	(sp)+,d0-d3/a0-a2
	rts

; Star_buffer_word -- a2 = the buffer word of plane 0 of the star a0.
;   Changes d3/a2.
Star_buffer_word:
	moveq	#0,d3
	move.w	6(a0),d3
	move.l	SC_AMIGA(a5),a2
	add.l	d3,a2
	rts

; Stars_redraw -- every star of the list of the screen a5 drawn again in
; Overlay_register (its target rows were just cleared: Zoom_clear).
;   All registers are preserved.
Stars_redraw:
	cmp.w	#MODE_STARS,SC_MODE(a5)
	bne.b	.none
	movem.l	d2/d4/a0-a2,-(sp)
	bsr.b	Star_or_routine		; a2
	move.l	SC_STARS(a5),a0
	move.w	(a0)+,d2
	bra.b	.n
.s:	move.l	(a0)+,a1
	move.w	(a0)+,d4
	addq.l	#2,a0
	jsr	(a2)
.n:	dbf	d2,.s
	movem.l	(sp)+,d2/d4/a0-a2
.none:	rts

; Star_or_routine -- a2 = the routine that sets the pixels d4 of the group
; a1 to Overlay_register (they are 0: only the planes of its set bits).
;   Changes a2.
Star_or_routine:
	move.l	d0,-(sp)
	move.w	Overlay_register,d0
	and.w	#15,d0
	lsl.w	#2,d0
	lea	Star_or_table,a2
	move.l	0(a2,d0.w),a2
	move.l	(sp)+,d0
	rts

STAR_OR	macro			; label, register
\1:
	ifne	(\2)&1
	or.w	d4,(a1)
	endc
	ifne	(\2)&2
	or.w	d4,2(a1)
	endc
	ifne	(\2)&4
	or.w	d4,4(a1)
	endc
	ifne	(\2)&8
	or.w	d4,6(a1)
	endc
	rts
	endm

	STAR_OR	Star_or0,0
	STAR_OR	Star_or1,1
	STAR_OR	Star_or2,2
	STAR_OR	Star_or3,3
	STAR_OR	Star_or4,4
	STAR_OR	Star_or5,5
	STAR_OR	Star_or6,6
	STAR_OR	Star_or7,7
	STAR_OR	Star_or8,8
	STAR_OR	Star_or9,9
	STAR_OR	Star_or10,10
	STAR_OR	Star_or11,11
	STAR_OR	Star_or12,12
	STAR_OR	Star_or13,13
	STAR_OR	Star_or14,14
	STAR_OR	Star_or15,15

; Star_offsets_setup -- Star_offsets: per word of Thalion's logo screen
; (offset row * 200 + byte, the byte even, as index offset & -2) the
; offset of its group in the target, row * 160 + byte / 2 * 8 (Logo_stars
; without divu and mulu).  Once at the start.  Changes d0-d1/d6-d7/a0.
Star_offsets_setup:
	lea	Star_offsets,a0
	moveq	#0,d0			; row * ST_LINE
	move.w	#200-1,d7
.r:	moveq	#AMIGA_ROW/2-1,d6
	move.w	d0,d1
.w:	move.w	d1,(a0)+
	addq.w	#8,d1
	dbf	d6,.w
	lea	200-AMIGA_ROW(a0),a0	; the other planes of the row: unused
	add.w	#ST_LINE,d0
	dbf	d7,.r
	rts

	SECTION	Intro_data,data
Star_or_table:
	dc.l	Star_or0,Star_or1,Star_or2,Star_or3,Star_or4,Star_or5
	dc.l	Star_or6,Star_or7,Star_or8,Star_or9,Star_or10,Star_or11
	dc.l	Star_or12,Star_or13,Star_or14,Star_or15
	SECTION	Intro_code,code

	SECTION	Intro_bss,bss
Direct_from:		ds.l	1	; range of all Amiga screens of the table
Direct_to:		ds.l	1	; 0: no screens shown directly
Bl_channel:		ds.l	4	; A, B, C, D: entry or 0
Bl_d_target:		ds.l	1	; D in the target
Bl_d_end:		ds.l	1	; BLTDPT afterwards, an Amiga address
Bl_d_step:		ds.l	1	; D from row to row (Amiga)
Blit_direct:		ds.l	1	; blits straight into the target
Blit_buffered:		ds.l	1	; blits through the buffer
Bl_d_rowstep:		ds.w	1	; D from row to row (target), after a row
Bl_d_rows:		ds.w	2	; first row, rows of D
Bl_way_rows:		ds.w	1	; rows the way writes - 1
Bl_tail:		ds.w	1	; rows below the target (Blit_tail)
Target_busy:		ds.w	1	; our writing runs (Target_verify waits)
Bl_skip:		ds.b	1	; Way_ca: the first word feeds only
Bl_shown:		ds.b	1	; Blit_redirect writes the target shown
	ifd	CHECK_TARGET
Ct_way:			ds.l	1
Ct_before:		ds.l	4
Ct_after:		ds.l	4
Target_errors:		ds.l	1
Target_first_vbl:	ds.l	1
Verify_errors:		ds.l	1
Verify_first_vbl:	ds.l	1
Target_first_where:	ds.w	1
Target_first_row:	ds.w	1
Verify_screen:		ds.w	1
Verify_row:		ds.w	1
Verify_first_screen:	ds.w	1
Verify_first_row:	ds.w	1
Blit_no_redirect:	ds.b	1
	even
	endc
Shown_entry:		ds.l	1	; the entry shown directly, or 0
Star_lists:		ds.b	TARGET_MAX*STAR_LIST
Star_offsets:		ds.w	200*100	; Star_offsets_setup
Valid_memory:		ds.b	TARGET_MAX*ST_LINES
	cnop	0,4
Target_memory:		ds.b	TARGET_MAX*TARGET_SIZE+256
	SECTION	Intro_code,code

; the Amiga registers of the channels A, B, C, D: pointer, modulo
	SECTION	Intro_data,data
Bl_registers:
	dc.w	AR_BLTAPT,AR_BLTAMOD
	dc.w	AR_BLTBPT,AR_BLTBMOD
	dc.w	AR_BLTCPT,AR_BLTCMOD
	dc.w	AR_BLTDPT,AR_BLTDMOD
	SECTION	Intro_code,code

; ***************************************************************************
; SHOW_ST.S -- the picture of the ST intro: what Thalion's copper list
; shows, in ST format (step 1 of docs/05c-ST.md "ST intro": correct first,
; fast later; the scenes get their own routines in step 3).
;
; Once a VBL (Display_update, at the end of Thalion's VBL):
;
;   1. read Thalion's copper list ($2452) and the display registers into
;      New_state: plane pointers, planes, row step, window
;   2. if it shows a target screen whole (TARGET_ST.S; Display_direct, the
;      Falcon's Anzeige_direkt): point the ST base into the target screen,
;      nothing to convert, no pointer (step 5 skipped).  Else make sure
;      the table's buffers are right (All_ensure) and go on with 3.  In
;      the main flow Display_switch (Intro_switch, $24BE) does the same at
;      once when Thalion builds a new copper list.
;   3. if it differs from what the ST shows: convert the whole picture into
;      the hidden ST screen and show that from the next frame; otherwise
;      follow up FOLLOW_ROWS rows of the shown picture in the shown ST
;      screen (Thalion draws into the shown screen in the menu, and its
;      VBL sets the stars in plane 4 of the shown screen)
;   4. the 16 ST colours for the next VBL, the colour change of the copper
;      list for Tb_border
;   5. the mouse pointer (sprites 0 and 1) into the shown ST screen
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3: 16 colours, plane 4
; as an overlay, the pointer in the nearest registers (docs/17 lists what
; looks different).
;
; **Colours.**  Four planes: register n = Amiga colour n.  Five planes
; (logo, PRESENTS, menu): planes 0-3 as four, plane 4 is an overlay drawn
; in register Overlay_register, which then shows the overlay's colour:
;   logo type (colours 16-31 all the same, or 17-31 = 1-15: the stars of
;   the logo scenes): only where planes 0-3 are 0 (a star behind the logo
;   stays hidden), in colour 16
;   other (the menu text): everywhere, in colour 31
; Overlay_register is 1 (near white in every five-plane palette of the
; intro, eed, ddd; THALION uses it on 8 pixels) and 13 while the AMBERMOON
; logo zooms (it leaves 13 and 14 unused; Zoom_clear, INTRO_ST.S).  DEVIATION
; (goals 1 and 2), docs/17-deviations.md D3: those 8 THALION pixels show
; the stars' white.  The menu's text colours 16-31 and the highlight are
; one colour.
;
; **Held picture.**  Where Thalion changes the format of its screens with
; the CPU (logo -> space, any scene -> clouds, clouds -> menu), Display_hold
; keeps the picture shown until a copper list shows a screen of the next
; table; nothing is converted meanwhile (E30: no live conversion, docs/11
; 7.8b).  Converting stays as the fallback where no table covers a picture.
;
; The conversion runs with the interrupt mask at 3: Timer B (6) and the
; next VBL (4) may come.  A VBL during a conversion runs Thalion's VBL as
; usual, its display part returns at once (Display_busy).
; ***************************************************************************

; The state of a picture: what the copper list and the registers show
S_PLANES	equ	0		; 4 or 5; 0: nothing shown
S_STEP		equ	2		; bytes from one row of a plane to the next
S_VSTART	equ	4		; raster line of row 0
S_ROWS		equ	6
S_PTR		equ	8		; 5 long words
S_SIZE		equ	28


; ***************************************************************************
; Display_setup -- nothing shown yet, black, no colour change.
; ***************************************************************************
Display_setup:
	lea	Shown_state,a0
	moveq	#S_SIZE/2-1,d0
.s:	clr.w	(a0)+
	dbf	d0,.s
	lea	St_palette,a0
	moveq	#16/2-1,d0
.p:	clr.l	(a0)+
	dbf	d0,.p
	clr.w	Split_count
	clr.w	Follow_row
	clr.w	Planes_waited
	clr.w	Shown_busy
	clr.l	Shown_entry
	move.w	#1,Overlay_register
	lea	Ptr_base,a0		; Pointer_colours: search every v once
	moveq	#16-1,d0
.pb:	move.w	#-1,(a0)+
	dbf	d0,.pb
	clr.l	Ptr_key_spr0
	clr.b	Ptr_map
	move.l	St_shown,Base_now
	sf	Display_busy
	sf	Pointer_on_screen
	sf	Shown_direct
	sf	Display_held
	move.l	#-1,Extent_a		; unknown: the first conversion clears
	move.l	#-1,Extent_b
	rts

; ***************************************************************************
; Display_update -- once a VBL; see the header.  Changes d0-d7/a0-a6.
; ***************************************************************************
Display_update:
	bset	#0,Display_busy
	bne	.out			; a VBL during our conversion
	move.w	sr,-(sp)
	move.w	#$2300,sr
	ifd	CHECK_TARGET
	bsr	Target_verify
	endc
	bsr	Pointer_remove
	bsr	Read_copper_list
	sne	d7
	move.b	d7,-(sp)
	bsr	Colours_prepare
	tst.b	(sp)+
	beq.b	.done			; no list (yet)
	; Thalion writes a copper list with five planes, waits for the VBL and
	; only then sets BPLCON0 (menu, $F94-$FAE): until both agree, at most
	; three VBL, the old picture stays (the Falcon's white frame, T62)
	move.w	Amiga_register+AR_BPLCON0,d0
	rol.w	#4,d0
	and.w	#7,d0
	cmp.w	List_planes,d0
	beq.b	.agree
	addq.w	#1,Planes_waited
	cmp.w	#3,Planes_waited
	bls.b	.done
.agree:	clr.w	Planes_waited
	lea	New_state,a6
	move.w	d0,S_PLANES(a6)
	cmp.w	#4,d0
	blo.b	.done			; nothing we can show
	cmp.w	#5,d0
	bhi.b	.done
	bsr	Window_read
	; a screen in the target format, shown whole: straight to the Shifter
	bsr	Display_direct
	bne.b	.done
	tst.b	Display_held		; Display_hold: until a table shows
	bne.b	.done
	addq.l	#1,Converted		; the fallback (E30: none expected)
	bsr	All_ensure		; converting reads the buffers
	lea	New_state,a6
	; the same picture as shown?
	lea	Shown_state,a5
	moveq	#S_SIZE/2-1,d1
	move.l	a6,a0
	move.l	a5,a1
.cmp:	cmp.w	(a0)+,(a1)+
	dbne	d1,.cmp
	bne.b	.new
	bsr	Follow_up
	bra.b	.done
.new:	bsr	Show_new
.done:	bsr	Pointer_draw
	move.w	(sp)+,sr
	sf	Display_busy
.out:	rts

; ***************************************************************************
; Read_copper_list -- Thalion's list ($2452): a wait for line $20, the
; plane pointers (BPLxPTH/L), optionally a wait for a picture line and
; colours, the end.  Plane pointers into New_state, their number into
; List_planes, the colours after a wait inside the picture into
; New_split (line, count, register and value).
;   OUT: Z set when there is no list.  Changes d0-d4/a0-a1.
; ***************************************************************************
Read_copper_list:
	lea	New_state,a1
	moveq	#S_SIZE/2-1,d0
.c:	clr.w	(a1)+
	dbf	d0,.c
	clr.w	List_planes
	clr.w	New_split_count
	clr.w	New_split_line
	move.l	Amiga_register+AR_COP1LC,d0
	beq	.none
	move.l	d0,a0
	moveq	#0,d3			; raster line of the last wait
	move.w	#64-1,d4		; at most this many instructions
.next:	move.w	(a0)+,d0
	move.w	(a0)+,d1
	btst	#0,d0
	beq.b	.move
	cmp.w	#$FFFF,d0		; end of list
	beq	.end
	move.w	d0,d3
	lsr.w	#8,d3
	bra	.loop
.move:	and.w	#$1FE,d0
	cmp.w	#$E0,d0
	blo.b	.colour
	cmp.w	#$F4,d0
	bhs.b	.colour
	sub.w	#$E0,d0			; plane pointer: 4 bytes a plane
	lea	New_state+S_PTR,a1
	btst	#1,d0
	bne.b	.low
	move.w	d1,0(a1,d0.w)
	lsr.w	#2,d0
	addq.w	#1,d0
	cmp.w	List_planes,d0
	bls	.loop
	move.w	d0,List_planes
	bra	.loop
.low:	move.w	d1,0(a1,d0.w)
	bra	.loop
.colour:
	cmp.w	#AR_COLOR00,d0
	blo	.loop
	cmp.w	#AR_COLOR00+16*2,d0
	bhs.b	.loop			; only 0-15 have a register of their own
	cmp.w	#RASTER_TOP,d3
	bls	.loop
	cmp.w	#4,New_split_count
	bhs	.loop
	move.w	d3,New_split_line
	lea	New_split,a1
	move.w	New_split_count,d2
	lsl.w	#2,d2
	sub.w	#AR_COLOR00,d0
	move.w	d0,0(a1,d2.w)		; register offset
	move.w	d1,2(a1,d2.w)		; Amiga colour
	addq.w	#1,New_split_count
.loop:	dbf	d4,.next
.end:	tst.l	Amiga_register+AR_COP1LC
	rts
.none:	rts

; ***************************************************************************
; Window_read -- step, window and rows into the state at a6.
;   Changes d0-d1.
; ***************************************************************************
Window_read:
	move.w	Amiga_register+AR_BPL1MOD,d0
	add.w	#AMIGA_ROW,d0
	move.w	d0,S_STEP(a6)
	moveq	#0,d0
	move.b	Amiga_register+AR_DIWSTRT,d0	; VSTART, bit 8 = 0
	move.w	d0,S_VSTART(a6)
	moveq	#0,d1
	move.b	Amiga_register+AR_DIWSTOP,d1	; VSTOP, bit 8 = not bit 7
	tst.b	d1
	bmi.b	.v
	add.w	#$100,d1
.v:	sub.w	d0,d1
	bpl.b	.r
	moveq	#0,d1
.r:	move.w	d1,S_ROWS(a6)
	rts

; ***************************************************************************
; Show_new -- the picture in New_state (a6) into the hidden ST screen, the
; lines outside it black, then show it from the next frame.
; ***************************************************************************
Show_new:
	lea	Extent_a,a4
	move.l	St_screen_a,a3
	cmp.l	St_shown,a3
	bne.b	.hidden
	lea	Extent_b,a4
	move.l	St_screen_b,a3
.hidden:
	; extent: first and end ST line of the picture, clipped
	move.w	S_VSTART(a6),d6
	sub.w	#RASTER_TOP,d6
	move.w	d6,d7
	add.w	S_ROWS(a6),d7
	bsr	Extent_clip
	cmp.w	(a4),d6
	bne.b	.clear
	cmp.w	2(a4),d7
	beq.b	.convert
.clear:	move.w	d6,(a4)
	move.w	d7,2(a4)
	moveq	#0,d0			; lines 0 .. d6-1
	move.w	d6,d1
	bsr	Lines_clear
	move.w	d7,d0			; lines d7 .. ST_LINES-1
	move.w	#ST_LINES,d1
	bsr	Lines_clear
.convert:
	moveq	#0,d0			; all rows
	move.w	S_ROWS(a6),d1
	bsr	Rows_convert
	; show it: the base takes effect at the next frame
	move.l	a3,St_shown
	move.l	a3,d0
	bsr	Base_set
	sf	Shown_direct
	clr.l	Shown_entry
	lea	Shown_state,a5
	moveq	#S_SIZE/2-1,d1
.copy:	move.w	(a6)+,(a5)+
	dbf	d1,.copy
	clr.w	Follow_row
	addq.l	#1,Show_count
	rts

; ***************************************************************************
; Base_set -- d0.l = the video base, from the next frame on.  High, mid,
; then the STE's low byte (a write to high or mid clears it).  Which base
; a frame shows, the Vbl reads from the counter (Frame_base).
;   All registers are preserved.
; ***************************************************************************
Base_set:
	movem.l	d0-d1,-(sp)
	move.w	sr,-(sp)
	or.w	#$0700,sr		; the VBL calls it too: no mixed base
	move.l	d0,Base_now
	move.l	d0,d1
	swap	d1
	move.b	d1,VBASE_HIGH.w
	move.w	d0,d1
	lsr.w	#8,d1
	move.b	d1,VBASE_MID.w
	tst.b	Is_ste
	beq.b	.st
	move.b	d0,VBASE_LOW.w
.st:	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d1
	rts

; ***************************************************************************
; Display_direct -- does the state a6 (New_state) show a screen of
; Screen_table whole (TARGET_ST.S)?  Then the base into its target screen,
; Shown_state = the state, Shown_direct set, Z clear.  Otherwise Z set, and
; a picture shown directly so far is converted at once (Shown_state
; forgotten).  Whole means: plane 0 on a row of a screen of the table, as
; many planes as the screen has, each AMIGA_ROW behind the one before, the
; screen's bytes a row, and the window covers the screen rows the ST
; shows.  As the Falcon's Anzeige_direkt (docs/11 7.8); the ST shows
; ST_LINES lines from line 0 (RASTER_TOP).  The window moved (Twinlake)
; moves the base by whole lines: the STE has the low byte for it, the ST
; shows directly only on 256 bytes.  A held picture (Display_hold) ends
; here.
;   Changes d0-d3/a0-a1/a5.
; ***************************************************************************
Display_direct:
	tst.l	Direct_to
	beq	.no
	move.l	S_PTR(a6),d0
	bsr	Screen_find
	beq	.no
	move.w	S_PLANES(a6),d1
	cmp.w	SC_PLANES(a5),d1
	bne	.no
	move.w	S_STEP(a6),d1
	cmp.w	SC_LINE(a5),d1
	bne	.no
	lea	S_PTR(a6),a0		; planes 1.. AMIGA_ROW apart
	move.l	d0,d2
	move.w	SC_PLANES(a5),d1
	subq.w	#2,d1
.p:	add.l	#AMIGA_ROW,d2
	addq.l	#4,a0
	cmp.l	(a0),d2
	bne	.no
	dbf	d1,.p
	sub.l	SC_AMIGA(a5),d0
	divu	SC_LINE(a5),d0
	swap	d0
	tst.w	d0
	bne	.no			; not on a row
	swap	d0			; the list's first row
	; The window shows rows r .. r+h-1 from ST line f0 on (rows above ST
	; line 0 cut, h to the ST's lines).  ST line 0 is then target line
	; r - f0.  Lines above the window show the black margin; below it
	; either the ST's picture ends with the window, or the window ends with
	; the screen (then the black lines below SC_ROWS).
	move.w	S_VSTART(a6),d1
	sub.w	#RASTER_TOP,d1		; f0
	move.w	S_ROWS(a6),d2		; h
	tst.w	d1
	bpl.b	.top
	add.w	d1,d2
	sub.w	d1,d0			; r
	moveq	#0,d1
.top:	move.w	d1,d3
	add.w	d2,d3
	sub.w	#ST_LINES,d3
	ble.b	.h
	sub.w	d3,d2
.h:	tst.w	d2
	bpl.b	.r
	moveq	#0,d2
.r:	move.w	d0,d3
	add.w	d2,d3
	cmp.w	SC_ROWS(a5),d3
	bhi	.no			; the window reaches beyond the screen
	beq.b	.below
	move.w	d1,d3
	add.w	d2,d3
	cmp.w	#ST_LINES,d3
	bne	.no			; screen rows below the window would show
.below:	sub.w	d1,d0			; target line at ST line 0
	cmp.w	#-TARGET_MARGIN,d0
	blt	.no
	cmp.w	#TARGET_MARGIN,d0
	bgt	.no
	muls	#ST_LINE,d0
	add.l	SC_TARGET(a5),d0
	tst.b	Is_ste
	bne.b	.base
	tst.b	d0
	bne	.no			; the ST has no low byte of the base
.base:	bsr	Base_set
	st	Shown_direct
	sf	Display_held
	move.l	a5,Shown_entry
	move.l	a6,a0
	lea	Shown_state,a1
	moveq	#S_SIZE/2-1,d1
.copy:	move.w	(a0)+,(a1)+
	dbf	d1,.copy
	clr.w	Follow_row
	andi.b	#$FB,ccr		; Z clear
	rts
.no:	tst.b	Shown_direct
	beq.b	.z
	sf	Shown_direct		; was direct: convert anew
	clr.l	Shown_entry
	move.w	#-1,Shown_state+S_PLANES
.z:	ori.b	#$04,ccr		; Z set
	rts

; ***************************************************************************
; Display_switch -- from the main flow, right after Thalion has written a
; new copper list (K3 at $24BE, Intro_switch).  A base written in the VBL
; takes effect a frame later (the Falcon's T11, docs/11 7.8): Thalion would
; already draw into the screen still shown.  On the Amiga the list holds
; from the next frame, and so here: if the new list shows a screen of the
; table whole, Display_direct writes the base now, and the VBL finds the
; state.  Otherwise the VBL converts, as before (the Falcon converts here
; too, Anzeige_umschalten; on the ST that would hold the VBL off for more
; than a frame, and Timer B would miss the border).  As the Falcon's
; Anzeige_sofort.
;   All registers are preserved.
; ***************************************************************************
Display_switch:
	tst.l	Direct_to
	beq.b	.out
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0400,sr		; the VBL reads and writes the same
	bsr	Read_copper_list
	beq.b	.done
	move.w	Amiga_register+AR_BPLCON0,d0
	rol.w	#4,d0
	and.w	#7,d0
	cmp.w	List_planes,d0
	bne.b	.done			; the VBL waits for BPLCON0 (T62)
	lea	New_state,a6
	move.w	d0,S_PLANES(a6)
	bsr	Window_read
	bsr	Display_direct
.done:	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d7/a0-a6
.out:	rts

; Display_forget -- the screens changed (Screens_switch): the picture is
; judged anew at the next VBL.
Display_forget:
	move.w	#-1,Shown_state+S_PLANES
	clr.l	Shown_entry
	rts

; ***************************************************************************
; Display_hold -- at a change of scene (K3): Thalion changes the format of
; its screens with the CPU next, and the next scene's table comes later.
; The picture shown now is copied into a hidden ST screen and shown from
; there; the table goes (Screens_switch with none), so Thalion's buffers
; hold everything again; nothing is converted until a copper list shows a
; screen of a table again (Display_direct ends the hold).  Returns after
; the next VBL, when the ST shows the copy.  As the Falcon's Display_hold
; (amiga/AMIGA_RAHMEN.S).  From the main flow only (it waits for the VBL).
;   All registers are preserved.
; ***************************************************************************
Display_hold:
	movem.l	d0-d7/a0-a6,-(sp)
	bsr	Shown_enter		; the pointer out, the stars stay
	move.l	Base_now,a0
	move.l	St_screen_a,a1
	cmp.l	a0,a1
	bne.b	.copy
	move.l	St_screen_b,a1
.copy:	move.l	a1,a3
	move.w	#ST_SCREEN/32-1,d7
.k:	movem.l	(a0)+,d0-d6/a2
	movem.l	d0-d6/a2,(a1)
	lea	32(a1),a1
	dbf	d7,.k
	move.w	sr,-(sp)
	or.w	#$0400,sr
	move.l	a3,St_shown
	move.l	a3,d0
	bsr	Base_set
	sf	Shown_direct
	st	Display_held
	move.l	#-1,Extent_a		; the next conversion clears
	move.l	#-1,Extent_b
	move.w	(sp)+,sr
	sub.l	a0,a0
	bsr	Screens_switch
	bsr	Shown_leave
	move.l	Vbl_count,d0
.vbl:	cmp.l	Vbl_count,d0
	beq.b	.vbl
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Shown_enter / Shown_leave -- around writing the target shown from the
; main flow: the pointer goes (it may lie in that target, the menu), and
; until Shown_leave neither the pointer (Pointer_draw) nor the stars
; (Logo_stars) go into a target.  Pairs may nest.
;   All registers are preserved.
; ***************************************************************************
Shown_enter:
	movem.l	d0-d4/a0-a1,-(sp)
	move.w	sr,-(sp)
	or.w	#$0400,sr
	addq.w	#1,Shown_busy
	bsr	Pointer_remove
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d4/a0-a1
	rts

Shown_leave:
	subq.w	#1,Shown_busy
	rts

; Extent_clip -- d6/d7 = first and end ST line, clipped to 0..ST_LINES.
Extent_clip:
	tst.w	d6
	bpl.b	.t
	moveq	#0,d6
.t:	cmp.w	#ST_LINES,d7
	ble.b	.b
	move.w	#ST_LINES,d7
.b:	cmp.w	d6,d7
	bge.b	.ok
	move.w	d6,d7
.ok:	rts

; Lines_clear -- ST lines d0 .. d1-1 of the screen a3 black.
;   Changes d0-d2/a0.
Lines_clear:
	sub.w	d0,d1
	ble.b	.out
	mulu	#ST_LINE,d0
	lea	0(a3,d0.l),a0
	moveq	#0,d2
	subq.w	#1,d1
.l:	rept	ST_LINE/4
	move.l	d2,(a0)+
	endr
	dbf	d1,.l
.out:	rts

; ***************************************************************************
; Follow_up -- FOLLOW_ROWS rows of the shown picture into the shown ST
; screen, round robin.
; ***************************************************************************
Follow_up:
	lea	Shown_state,a6
	move.l	St_shown,a3
	move.w	S_ROWS(a6),d2
	beq.b	.out
	move.w	Follow_row,d0
	cmp.w	d2,d0
	blo.b	.r
	moveq	#0,d0
.r:	moveq	#FOLLOW_ROWS,d1
	move.w	d0,d3
	add.w	d1,d3
	cmp.w	d2,d3
	bls.b	.n
	move.w	d2,d1
	sub.w	d0,d1
	move.w	d2,d3
.n:	move.w	d3,Follow_row
	bsr	Rows_convert
.out:	rts

; ***************************************************************************
; Rows_convert -- picture rows d0 .. d0+d1-1 of the state a6 into the ST
; screen a3, at ST line S_VSTART-RASTER_TOP+row; rows outside the screen
; are left out.  Four planes are copied word by word; a fifth is laid over
; them afterwards (Overlay_apply).
;   Changes d0-d7/a0-a2/a4-a5.
; ***************************************************************************
Rows_convert:
	move.w	S_VSTART(a6),d2
	sub.w	#RASTER_TOP,d2
	add.w	d0,d2			; ST line of the first row
	bpl.b	.top
	add.w	d2,d1			; rows above the screen: left out
	sub.w	d2,d0
	moveq	#0,d2
.top:	move.w	d2,d3
	add.w	d1,d3
	sub.w	#ST_LINES,d3
	ble.b	.bottom
	sub.w	d3,d1			; rows below the screen: left out
.bottom:
	tst.w	d1
	ble	.out
	movem.w	d0-d2,Convert_rows	; first row, count, first ST line
	mulu	#ST_LINE,d2
	lea	0(a3,d2.l),a1		; ST line
	mulu	S_STEP(a6),d0		; row offset in the planes
	movem.l	S_PTR(a6),a0/a2/a4/a5
	add.l	d0,a0
	add.l	d0,a2
	add.l	d0,a4
	add.l	d0,a5
	move.w	S_STEP(a6),d6
	sub.w	#AMIGA_ROW,d6		; to the next row behind a plane row
	subq.w	#1,d1
.row:	moveq	#AMIGA_ROW/2/4-1,d7	; 20 groups, 4 per round
.grp:	rept	4
	move.w	(a0)+,(a1)+
	move.w	(a2)+,(a1)+
	move.w	(a4)+,(a1)+
	move.w	(a5)+,(a1)+
	endr
	dbf	d7,.grp
	add.w	d6,a0
	add.w	d6,a2
	add.w	d6,a4
	add.w	d6,a5
	dbf	d1,.row
	cmp.w	#5,S_PLANES(a6)
	bne.b	.out
	bsr	Overlay_apply
.out:	rts

; ***************************************************************************
; Overlay_apply -- plane 4 of the rows Rows_convert just did, laid over
; the ST screen a3 in Overlay_register (header).  Groups without a plane-4
; pixel cost a test.
;   Changes d0-d7/a0-a1.
; ***************************************************************************
Overlay_apply:
	movem.w	Convert_rows,d0-d2
	mulu	#ST_LINE,d2
	lea	0(a3,d2.l),a1
	mulu	S_STEP(a6),d0
	move.l	S_PTR+4*4(a6),a0
	add.l	d0,a0
	move.w	S_STEP(a6),d6
	sub.w	#AMIGA_ROW,d6
	move.w	Overlay_register,d3	; bits: set or clear in plane n
	move.b	Overlay_logo,d4		; logo type: only where planes 0-3 are 0
	subq.w	#1,d1
.row:	moveq	#AMIGA_ROW/2-1,d7
.grp:	move.w	(a0)+,d0		; plane 4
	beq.b	.next
	tst.b	d4
	beq.b	.all
	move.w	(a1),d5
	or.w	2(a1),d5
	or.w	4(a1),d5
	or.w	6(a1),d5
	not.w	d5
	and.w	d5,d0			; star pixels over colour 0 only
	beq.b	.next
.all:	move.w	d0,d5
	not.w	d5
	btst	#0,d3
	beq.b	.c0
	or.w	d0,(a1)
	bra.b	.p1
.c0:	and.w	d5,(a1)
.p1:	btst	#1,d3
	beq.b	.c1
	or.w	d0,2(a1)
	bra.b	.p2
.c1:	and.w	d5,2(a1)
.p2:	btst	#2,d3
	beq.b	.c2
	or.w	d0,4(a1)
	bra.b	.p3
.c2:	and.w	d5,4(a1)
.p3:	btst	#3,d3
	beq.b	.c3
	or.w	d0,6(a1)
	bra.b	.next
.c3:	and.w	d5,6(a1)
.next:	addq.l	#8,a1
	dbf	d7,.grp
	add.w	d6,a0
	dbf	d1,.row
	rts

; ***************************************************************************
; Colours_prepare -- St_palette for the next VBL from the colours Thalion's
; VBL wrote (Amiga_register), the overlay colour for five planes, and the
; colour change of the copper list for Tb_border.  Shown_amiga: the Amiga
; colour each of the 16 registers shows (Pointer_colours).
;   Changes d0-d7/a0-a3.
; ***************************************************************************
Colours_prepare:
	lea	Amiga_register+AR_COLOR00,a0
	lea	Colour_table,a1
	lea	Colour_work,a2
	lea	Shown_amiga,a3
	moveq	#16-1,d7
.c:	move.w	(a0)+,d0
	and.w	#$0FFF,d0
	move.w	d0,(a3)+
	add.w	d0,d0
	move.w	0(a1,d0.w),(a2)+
	dbf	d7,.c
	move.w	Amiga_register+AR_BPLCON0,d0
	and.w	#$7000,d0
	cmp.w	#$5000,d0		; five planes
	bne.b	.copy
	; logo type: colours 16-31 all alike, or 17-31 = 1-15
	lea	Amiga_register+AR_COLOR00+16*2,a0
	moveq	#15-1,d7
	move.w	(a0)+,d0
.same:	cmp.w	(a0)+,d0
	dbne	d7,.same
	beq.b	.logo
	lea	Amiga_register+AR_COLOR00+2,a0
	moveq	#15-1,d7
.lt:	move.w	32(a0),d0
	cmp.w	(a0)+,d0
	dbne	d7,.lt
.logo:	seq	Overlay_logo
	move.w	Amiga_register+AR_COLOR00+31*2,d0
	tst.b	Overlay_logo
	beq.b	.over
	move.w	Amiga_register+AR_COLOR00+16*2,d0
.over:	and.w	#$0FFF,d0
	move.w	Overlay_register,d1
	add.w	d1,d1
	lea	Shown_amiga,a2
	move.w	d0,0(a2,d1.w)
	add.w	d0,d0
	lea	Colour_work,a2
	move.w	0(a1,d0.w),0(a2,d1.w)
.copy:	movem.l	Colour_work,d0-d7
	movem.l	d0-d7,St_palette
	; the copper list's colour change: only at ST line 200, in Tb_border
	clr.w	Split_count
	move.w	New_split_line,d0
	sub.w	#RASTER_TOP,d0
	cmp.w	#ST_BORDER+1,d0
	bne.b	.out
	move.w	New_split_count,d6
	beq.b	.out
	lea	New_split,a0
	lea	Split_colours,a2
	subq.w	#1,d6
.s:	move.w	(a0)+,(a2)+		; register offset
	move.w	(a0)+,d0
	and.w	#$0FFF,d0
	add.w	d0,d0
	move.w	0(a1,d0.w),(a2)+
	dbf	d6,.s
	move.w	New_split_count,Split_count
.out:	rts

; ***************************************************************************
; The mouse pointer: Thalion's VBL writes the control words and SPR0PT/
; SPR1PT (docs/11, 4.4), DMACON $8020 switches the sprites on.  Sprites 0
; and 1 attached: pixel value v (1-15) shows Amiga colour 16+v (the menu's
; sword, colours 18-23 from 1:$1E0); not attached, sprite 0 alone.  The ST
; has no register left for them (the menu's background takes 15, the text
; the 16th), so each v is drawn in the register whose shown colour is
; nearest to 16+v (Pointer_colours): the sword's shades, a little off.
; Drawn into the picture shown (Base_now: also a target, the menu), the
; background saved for Pointer_remove.  Not into a target while the main
; flow writes one (Shown_busy).
; ***************************************************************************
POINTER_LINES	equ	24
PS_LINE		equ	10		; Pointer_shape: planes 0-3, mask

Pointer_draw:
	tst.b	Shown_direct
	beq.b	.on
	tst.w	Shown_busy
	bne	.out
.on:	move.w	Amiga_register+AR_DMACON,d0
	and.w	#$8020,d0
	cmp.w	#$8020,d0
	bne	.out
	move.l	Amiga_register+AR_SPR0PT,d0
	beq	.out
	move.l	d0,a0
	move.l	Amiga_register+AR_SPR0PT+4,d0
	beq	.out
	move.l	d0,a2
	move.w	(a0),d0			; POS: VSTART low, HSTART high bits
	move.w	2(a0),d1		; CTL: VSTOP, attach, the high bits
	moveq	#0,d2
	move.b	d0,d2
	add.w	d2,d2
	btst	#0,d1
	beq.b	.h
	addq.w	#1,d2
.h:	sub.w	#$80,d2			; x
	moveq	#0,d3
	move.w	d0,d3
	lsr.w	#8,d3
	btst	#2,d1
	beq.b	.v
	add.w	#$100,d3
.v:	moveq	#0,d4
	move.w	d1,d4
	lsr.w	#8,d4
	btst	#1,d1
	beq.b	.vs
	add.w	#$100,d4
.vs:	sub.w	d3,d4			; lines
	ble	.out
	cmp.w	#POINTER_LINES,d4
	bls.b	.lines
	moveq	#POINTER_LINES,d4
.lines:	sub.w	#RASTER_TOP,d3		; ST line
	tst.w	d2
	bmi	.out
	cmp.w	#320-32,d2
	bhi	.out
	tst.w	d3
	bmi	.out
	move.w	d3,d5
	add.w	d4,d5
	cmp.w	#ST_LINES,d5
	bhi	.out
	movem.w	d2-d4,-(sp)
	btst	#7,3(a2)		; ATT in sprite 1's CTL
	sne	d5
	bsr	Pointer_colours		; a0, a2, d4, d5 -> Pointer_shape
	movem.w	(sp)+,d2-d4
	; place: ST line d3, group x/16, shift x&15
	move.l	Base_now,a1
	mulu	#ST_LINE,d3
	add.l	d3,a1
	move.w	d2,d5
	lsr.w	#4,d5
	lsl.w	#3,d5
	add.w	d5,a1
	and.w	#15,d2
	move.l	a1,Pointer_place
	move.w	d4,Pointer_count
	lea	Pointer_saved,a3
	lea	Pointer_shape,a0
	subq.w	#1,d4
.line:	movem.l	(a1),d0/d1/d5/d6	; two groups, saved
	movem.l	d0/d1/d5/d6,(a3)
	lea	16(a3),a3
	moveq	#0,d5			; the mask over two groups, inverted:
	move.w	8(a0),d5		; high word group 1, low word group 2
	swap	d5
	lsr.l	d2,d5
	not.l	d5
	move.l	a1,a4
	moveq	#4-1,d6
.plane:	moveq	#0,d1
	move.w	(a0)+,d1
	swap	d1
	lsr.l	d2,d1
	swap	d5
	and.w	d5,(a4)
	swap	d1
	or.w	d1,(a4)
	swap	d5
	and.w	d5,8(a4)
	swap	d1
	or.w	d1,8(a4)
	addq.l	#2,a4
	dbf	d6,.plane
	addq.l	#2,a0			; the mask
	lea	ST_LINE(a1),a1
	dbf	d4,.line
	st	Pointer_on_screen
.out:	rts

; ***************************************************************************
; Pointer_colours -- Pointer_shape for the sprites at a0 (sprite 0) and a2
; (sprite 1), d4 lines, d5.b attached: per line planes 0-3 and the mask.
; Rebuilt only when the sprites change or the register of a pixel value
; the shape uses does (Ptr_map: per v the register nearest to Amiga colour
; 16+v among the 16 shown, Shown_amiga; recomputed per v only when that
; colour or the shown ones change, so the menu's cycling colour 30 costs
; one search).
;   Changes d0-d7/a0-a6.
; ***************************************************************************
Pointer_colours:
	; the sprites as before?
	sf	d7			; rebuild
	cmp.l	Ptr_key_spr0,a0
	bne.b	.key
	cmp.l	Ptr_key_spr1,a2
	bne.b	.key
	cmp.w	Ptr_key_lines,d4
	bne.b	.key
	cmp.b	Ptr_key_att,d5
	beq.b	.base
.key:	move.l	a0,Ptr_key_spr0
	move.l	a2,Ptr_key_spr1
	move.w	d4,Ptr_key_lines
	move.b	d5,Ptr_key_att
	st	d7
	; the shown colours as before?  Else every v is searched again.
.base:	lea	Shown_amiga,a3
	lea	Ptr_base,a4
	moveq	#0,d6
	moveq	#16-1,d0
.b:	move.w	(a3)+,d1
	cmp.w	(a4),d1
	beq.b	.bs
	move.w	d1,(a4)
	moveq	#-1,d6
.bs:	addq.l	#2,a4
	dbf	d0,.b
	; the register per v whose colour 16+v changed
	lea	Amiga_register+AR_COLOR00+16*2,a3
	lea	Ptr_src,a4
	lea	Ptr_map,a5
	moveq	#1,d0			; v
.v:	move.w	d0,d1
	add.w	d1,d1
	move.w	0(a3,d1.w),d2
	and.w	#$0FFF,d2
	tst.w	d6
	bne.b	.search
	cmp.w	0(a4,d1.w),d2
	beq.b	.nextv
.search:
	move.w	d2,0(a4,d1.w)
	bsr	Nearest_register
	or.b	#$10,d3			; bit 4: the mask
	cmp.b	0(a5,d0.w),d3
	beq.b	.nextv
	move.b	d3,0(a5,d0.w)
	move.w	Ptr_used,d1
	btst	d0,d1
	beq.b	.nextv
	st	d7
.nextv:	addq.w	#1,d0
	cmp.w	#16,d0
	blo.b	.v
	tst.b	d7
	beq	.out
	; build: per pixel v -> Ptr_map -> one bit in planes 0-3 and the mask
	addq.l	#4,a0			; the sprite lines
	addq.l	#4,a2
	move.w	#4,a4			; sprite 1's step, 0 alone (Zero_long)
	tst.b	d5
	bne.b	.att
	lea	Zero_long,a2
	sub.w	a4,a4
.att:	lea	Pointer_shape,a3
	moveq	#0,d6			; the values used
	subq.w	#1,d4
.line:	clr.l	(a3)
	clr.l	4(a3)
	clr.w	8(a3)
	move.w	(a0)+,d0		; sprite 0: bits 0, 1
	move.w	(a0)+,d1
	move.w	(a2),d2			; sprite 1: bits 2, 3
	move.w	2(a2),d3
	add.l	a4,a2
	moveq	#16-1,d7
.px:	moveq	#0,d5
	add.w	d3,d3
	addx.w	d5,d5
	add.w	d2,d2
	addx.w	d5,d5
	add.w	d1,d1
	addx.w	d5,d5
	add.w	d0,d0
	addx.w	d5,d5			; v
	bset	d5,d6
	move.b	0(a5,d5.w),d5		; register | $10; 0 for v = 0
	lsr.b	#1,d5
	roxl.w	(a3)
	lsr.b	#1,d5
	roxl.w	2(a3)
	lsr.b	#1,d5
	roxl.w	4(a3)
	lsr.b	#1,d5
	roxl.w	6(a3)
	lsr.b	#1,d5
	roxl.w	8(a3)
	dbf	d7,.px
	lea	PS_LINE(a3),a3
	dbf	d4,.line
	move.w	d6,Ptr_used
.out:	rts

; Nearest_register -- d3: the register whose shown colour (Ptr_base) is
; nearest to d2 ($0RGB), by the sum of the squared channel differences.
;   Changes d1/d3/a1.
Nearest_register:
	movem.l	d0/d4-d7/a0,-(sp)
	lea	Ptr_base,a0
	lea	Square+15*2,a1
	move.w	#$7FFF,d7		; the best distance
.r:	move.w	(a0)+,d1
	move.w	d2,d4
	moveq	#15,d5			; blue
	and.w	d1,d5
	moveq	#15,d6
	and.w	d4,d6
	sub.w	d6,d5
	add.w	d5,d5
	move.w	0(a1,d5.w),d0
	lsr.w	#4,d1			; green
	lsr.w	#4,d4
	moveq	#15,d5
	and.w	d1,d5
	moveq	#15,d6
	and.w	d4,d6
	sub.w	d6,d5
	add.w	d5,d5
	add.w	0(a1,d5.w),d0
	lsr.w	#4,d1			; red: what is left of $0RGB
	lsr.w	#4,d4
	sub.w	d4,d1
	add.w	d1,d1
	add.w	0(a1,d1.w),d0
	cmp.w	d7,d0
	bhs.b	.next
	move.w	d0,d7
	move.l	a0,d3
.next:	cmp.l	#Ptr_base+16*2,a0
	blo.b	.r
	sub.l	#Ptr_base+2,d3
	lsr.w	#1,d3
	movem.l	(sp)+,d0/d4-d7/a0
	rts

Square:	dc.w	225,196,169,144,121,100,81,64,49,36,25,16,9,4,1
	dc.w	0,1,4,9,16,25,36,49,64,81,100,121,144,169,196,225
Zero_long:
	dc.l	0
; Pointer_remove -- the background under the pointer back.
Pointer_remove:
	bclr	#0,Pointer_on_screen
	beq.b	.out
	move.l	Pointer_place,a1
	lea	Pointer_saved,a0
	move.w	Pointer_count,d0
	subq.w	#1,d0
.l:	movem.l	(a0)+,d1-d4
	movem.l	d1-d4,(a1)
	lea	ST_LINE(a1),a1
	dbf	d0,.l
.out:	rts

	SECTION	Intro_bss,bss
New_state:		ds.b	S_SIZE
Shown_state:		ds.b	S_SIZE
Pointer_place:		ds.l	1
Show_count:		ds.l	1	; pictures shown (for measuring)
Converted:		ds.l	1	; VBLs that converted (the fallback)
Base_now:		ds.l	1	; the base set last (Base_set)
Overlay_register:	ds.w	1	; five planes: plane 4 in this register
Shown_busy:		ds.w	1	; Shown_enter .. Shown_leave
Extent_a:		ds.w	2	; ST lines of the picture in screen a
Extent_b:		ds.w	2
Convert_rows:		ds.w	3	; Rows_convert -> Overlay_apply
List_planes:		ds.w	1
Planes_waited:		ds.w	1
Follow_row:		ds.w	1
New_split_line:		ds.w	1
New_split_count:	ds.w	1
New_split:		ds.w	2*4
Pointer_count:		ds.w	1
Colour_work:		ds.w	16
Pointer_saved:		ds.l	4*POINTER_LINES
Shown_amiga:		ds.w	16	; the Amiga colour of each register
Ptr_base:		ds.w	16	; Shown_amiga of the last search
Ptr_src:		ds.w	16	; colour 16+v of the last search per v
Ptr_used:		ds.w	1	; bit v: the shape has pixel value v
Ptr_key_spr0:		ds.l	1	; Pointer_shape was built from these
Ptr_key_spr1:		ds.l	1
Ptr_key_lines:		ds.w	1
Pointer_shape:		ds.w	5*POINTER_LINES
Ptr_map:		ds.b	16	; v -> register | $10 (0 for v = 0)
Ptr_key_att:		ds.b	1
Display_busy:		ds.b	1
Overlay_logo:		ds.b	1
Pointer_on_screen:	ds.b	1
Shown_direct:		ds.b	1	; the ST shows a target screen
Display_held:		ds.b	1	; Display_hold: nothing converted
	even
	SECTION	Intro_code,code

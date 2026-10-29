; ***************************************************************************
; STARS_ST.S -- our routines for two of Thalion's in FAIRY.S, ST/STE only.
;
; **Why:** in the logo phase Thalion's make_magic writes each of about 165
; stars a frame into eleven blitter registers (blit_star), and
; Blitter_wait reads them back to find the ST place and image: 5 VBL a
; frame instead of Thalion's 3 (docs/05c-ST.md).  The intro exception of
; CLAUDE.md (goal 1) allows own routines here, it names the logo build-up
; in the fantasy intro.
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3 (E41).
;
; **What stays Thalion's:** FAIRY.S is not changed, its make_magic and
; make_funkel2 just are not called (Fairy_flow).  Ours keep Thalion's
; order of work, its buffers (magic_buffer, plot_buffer2), its tables
; (mani_tab, mbl_masks, puls_tab2), its random and the order of the calls
; to it, magic_x and its steps.  So the same stars come at the same places
; in the same frames.  Only the drawing is ours: straight into the ST
; screen, through the compiled star routines (fantasy_st_stars.i).
;
;   Magic_st   for make_magic (FAIRY.S): logo column, 24 new stars, draw
;              all stars (no_magicmake)
;   Dust_st    for make_funkel2 (FAIRY.S): fine dust, small stars
;
; Dust_st draws a small star at once, then the dust after it on top.
; Thalion's blit_star2 only starts the blit; on the Amiga it is done
; before the next dust pixel, in Blitter_wait only at the next waitblit,
; so there the star lands on top.  CHECK_DEFER (with CHECK_STARS) makes
; Dust_st wait the same way; then Check_stars finds no difference at all.
;
; CHECK_STARS (VASM_EXTRA="-DCHECK_STARS=1"): every frame runs Thalion's
; two routines and ours from the same state and counts the frames in
; which state or picture differ (Check_stars).
; ***************************************************************************

; make_magic: the logo column goes to background+8+146*200 while magic_x
; is in 64..271 (four pixels a frame); magic_x stops at 276.
LOGO_ROW	equ	146
LOGO_X		equ	64
LOGO_X_END	equ	272
MAGIC_X_END	equ	276

; ***************************************************************************
; Stars_setup -- the tables of Magic_st and Dust_st.  After Plot_setup.
;
;   Row_offset   per Amiga row from SPLIT_ROW: ST offset from Plot_target
;   Byte_offset  per byte of a workbase plane row (0..39): ST offset
;   Dust_jmptab  per Amiga colour * 4: Pixel_st of its lower-band register
; ***************************************************************************
Stars_setup:
	lea	Row_offset,a0
	moveq	#0,d0
	move.w	#AMIGA_ROWS-SPLIT_ROW-1,d7
.row:	move.w	d0,(a0)+
	add.w	#ST_LINE,d0
	dbf	d7,.row
	lea	Byte_offset,a0
	moveq	#0,d0
.byte:	move.w	d0,d1
	lsr.w	#1,d1
	lsl.w	#3,d1
	move.w	d0,d2
	and.w	#1,d2
	or.w	d2,d1
	move.w	d1,(a0)+
	addq.w	#1,d0
	cmp.w	#bpscanl/planes,d0
	bne.b	.byte
	lea	Dust_jmptab,a0
	lea	St_map_lower,a1
	lea	Pixel_routines,a2
	moveq	#32-1,d7
.jmp:	moveq	#0,d0
	move.b	(a1)+,d0
	lsl.w	#2,d0
	move.l	0(a2,d0.w),(a0)+
	dbf	d7,.jmp
	rts

; ***************************************************************************
; Magic_st -- for Thalion's make_magic (with no_magicmake and blit_star).
;
; The free slot: Thalion looks from slot 0 for each new star.  Within one
; call no slot is freed, so the lowest free one only moves up; looking on
; from the last one finds the same slots.  No free slot ends the 24, as in
; Thalion's loop.
; ***************************************************************************
Magic_st:
	move.w	magic_x,d4
	bmi	.draw
	cmp.w	#LOGO_X,d4
	blt.b	.new_stars
	cmp.w	#LOGO_X_END,d4
	bge.b	.new_stars
	; --- the logo column: 4 pixels of 16, 83 rows, into the background ---
	move.w	d4,d0
	sub.w	#LOGO_X,d0
	moveq	#15,d2
	and.w	d0,d2
	lsr.w	#2,d2
	add.w	d2,d2
	lea	mbl_masks,a2
	move.w	0(a2,d2.w),d2
	move.w	d2,d1
	swap	d2
	move.w	d1,d2			; the four pixels, both halves
	lsr.w	#4,d0
	lsl.w	#3,d0			; the 16-pixel group
	lea	St_logo,a1
	add.w	d0,a1
	lea	St_background+(LOGO_ROW-AMIGA_FIRST)*ST_LINE+LOGO_X/2,a0
	add.w	d0,a0
	move.w	#ST_LOGO_ROWS-1,d0
.logo:	move.l	(a0),d1			; background ^= (background ^ logo) & mask
	move.l	(a1),d3
	eor.l	d1,d3
	and.l	d2,d3
	eor.l	d3,(a0)
	move.l	4(a0),d1
	move.l	4(a1),d3
	eor.l	d1,d3
	and.l	d2,d3
	eor.l	d3,4(a0)
	lea	ST_LINE(a0),a0
	lea	ST_LOGO_GROUPS*8(a1),a1
	dbf	d0,.logo
.new_stars:
	; --- 24 new stars around magic_x ---
	moveq	#24-1,d7
	lea	magic_buffer,a3		; the lowest slot that may be free
	move.w	#star_anz,d6		; slots not looked at yet
.new:	jsr	random
	move.l	d0,d1
	divu	#88,d1
	swap	d1
	add.w	#148-8,d1		; y
	jsr	random
	move.w	#7*32,d2
	and.w	d0,d2			; animation * 32
	and.w	#7,d0
	subq.w	#4,d0
	add.w	d4,d0			; x
.search:
	subq.w	#1,d6
	bmi.b	.moved			; no free slot
	tst.w	(a3)
	bmi.b	.free
	addq.l	#6,a3
	bra.b	.search
.free:	move.w	d0,(a3)+
	move.w	d1,(a3)+
	move.w	d2,(a3)+
	dbf	d7,.new
.moved:
	addq.w	#4,magic_x
	cmp.w	#MAGIC_X_END,magic_x
	blt.b	.draw
	move.w	#-1,magic_x
	clr.w	magic_doit
.draw:
	; --- draw and animate all stars (no_magicmake) ---
	lea	magic_buffer,a4
	lea	mani_tab,a5
	lea	Star_routines,a6
	lea	Row_offset-SPLIT_ROW*2,a2
	move.l	Plot_target,d6
	move.w	#star_anz-1,d7
.star:	move.w	(a4),d0			; x
	bmi.b	.next
	move.w	4(a4),d2
	move.w	0(a5,d2.w),d2		; image, or -1: the star ends
	bpl.b	.on
	move.w	d2,(a4)
	bra.b	.next
.on:	addq.w	#2,4(a4)
	move.w	2(a4),d1		; y
	add.w	d1,d1
	move.l	d6,a0
	add.w	0(a2,d1.w),a0
	moveq	#15,d3
	and.w	d0,d3			; shift
	and.w	#-16,d0
	lsr.w	#1,d0
	add.w	d0,a0			; the 16-pixel group
	lsl.w	#4,d2
	add.w	d3,d2
	add.w	d2,d2
	add.w	d2,d2
	move.l	0(a6,d2.w),a3
	jsr	(a3)
.next:	addq.l	#6,a4
	dbf	d7,.star
	rts

; ***************************************************************************
; Dust_st -- for Thalion's make_funkel2 (with blit_star2 and the plot
; routines of plot_jmptab).
;
; plot_buffer2, funkel_size2 bytes a slot (made by make_funkel):
;   0  word  pixel mask (low byte), x & 15 in bits 12-15;  0.l = free
;   2  word  byte in the workbase plane row
;   4  word  y * 16
;   6  word  y speed
;   8  word  index into puls_tab2: colour * 4, 0 ends, negative = star
; The rows stay in 134..255: make_funkel starts them there, they only fall.
; ***************************************************************************
Dust_st:
	lea	plot_buffer2,a3
	lea	puls_tab2,a5
	lea	Dust_jmptab,a2
	lea	Row_offset-SPLIT_ROW*2,a6
	lea	Byte_offset,a4
	move.l	Plot_target,d6
	move.w	#funkel_anz2-1,d7
.dust:	move.l	(a3),d0
	beq.b	.next
	move.w	4(a3),d5
	add.w	6(a3),d5
	cmp.w	#256*16,d5
	blt.b	.fall
	clr.l	(a3)			; below the picture: off
	bra.b	.next
.fall:	move.w	d5,4(a3)
	lsr.w	#4,d5
	move.w	8(a3),d3
	move.w	0(a5,d3.w),d2
	bne.b	.on
	clr.l	(a3)			; end of the table: off
	bra.b	.next
.on:	addq.w	#2,d3
	move.w	d3,8(a3)
	add.w	d5,d5
	tst.w	d2
	bmi.b	.star
	move.l	d6,a0
	add.w	0(a6,d5.w),a0
	move.w	d0,d4
	add.w	d4,d4
	add.w	0(a4,d4.w),a0
	swap	d0
	move.w	d0,d1
	not.w	d1
	move.l	0(a2,d2.w),a1
	jsr	(a1)
.next:	lea	funkel_size2(a3),a3
	dbf	d7,.dust
	ifd	CHECK_DEFER
	bra	Deferred_star
	endc
	rts

.star:	cmp.w	#(256-5)*2,d5
	bge.b	.next
	move.l	d6,a0
	add.w	0(a6,d5.w),a0
	move.w	d0,d4
	and.w	#-2,d4			; the Amiga blitter ignores bit 0
	add.w	d4,d4
	add.w	0(a4,d4.w),a0
	swap	d0
	rol.w	#4,d0
	and.w	#15,d0			; shift
	neg.w	d2
	sub.w	#ST_SMALL_IMAGE,d2	; Thalion: stars - 100 - d2
	mulu	#ST_SMALL_RECIP,d2
	swap	d2			; image
	add.w	#ST_STARS_BIG,d2
	lsl.w	#4,d2
	add.w	d0,d2
	add.w	d2,d2
	add.w	d2,d2
	lea	Star_routines,a1
	move.l	0(a1,d2.w),a1
	ifd	CHECK_DEFER
	bsr	Defer_star
	else
	jsr	(a1)
	endc
	bra	.next

	ifd	CHECK_DEFER
; Defer_star -- CHECK_DEFER: draw the star of the last call now and keep
; this one (a0, a1) for later, as Blitter_wait does with Thalion's
; blit_star2: it runs at the next waitblit.  Dust_st then puts pixels
; and stars on top of each other in Thalion's order through
; Blitter_wait, and Check_stars compares only the logic.
Defer_star:
	movem.l	a0-a1,-(sp)
	bsr.b	Deferred_star
	movem.l	(sp)+,a0-a1
	move.l	a0,Deferred_place
	move.l	a1,Deferred_routine
	rts
Deferred_star:
	move.l	Deferred_routine,d0
	beq.b	.none
	move.l	d0,a1
	move.l	Deferred_place,a0
	clr.l	Deferred_routine
	jmp	(a1)
.none:	rts
	endc

; Pixel_st0..15 -- a0 = byte in the ST work screen (plane 0), d0 = its
; pixels, d1 = not d0.  Sets ST register \1 there.  Changes nothing else.
PIXEL_ST	macro
Pixel_st\1:
	ifne	(\1)&1
	or.b	d0,(a0)
	else
	and.b	d1,(a0)
	endc
	ifne	(\1)&2
	or.b	d0,2(a0)
	else
	and.b	d1,2(a0)
	endc
	ifne	(\1)&4
	or.b	d0,4(a0)
	else
	and.b	d1,4(a0)
	endc
	ifne	(\1)&8
	or.b	d0,6(a0)
	else
	and.b	d1,6(a0)
	endc
	rts
	endm

	PIXEL_ST	0
	PIXEL_ST	1
	PIXEL_ST	2
	PIXEL_ST	3
	PIXEL_ST	4
	PIXEL_ST	5
	PIXEL_ST	6
	PIXEL_ST	7
	PIXEL_ST	8
	PIXEL_ST	9
	PIXEL_ST	10
	PIXEL_ST	11
	PIXEL_ST	12
	PIXEL_ST	13
	PIXEL_ST	14
	PIXEL_ST	15

Pixel_routines:
	dc.l	Pixel_st0,Pixel_st1,Pixel_st2,Pixel_st3
	dc.l	Pixel_st4,Pixel_st5,Pixel_st6,Pixel_st7
	dc.l	Pixel_st8,Pixel_st9,Pixel_st10,Pixel_st11
	dc.l	Pixel_st12,Pixel_st13,Pixel_st14,Pixel_st15

	ifd	CHECK_STARS
; ***************************************************************************
; Check_stars -- diagnostic build: Thalion's make_funkel2 and make_magic
; (through Blitter_wait), then ours from the same state; counts in
; Check_frames the frames compared, in Check_state_errors those whose
; buffers, random seed or magic_x differ, in Check_pixel_errors those
; whose lower band (work screen or background) differs.  Check_first_error
; is the first such frame.  Fairy_vbl holds back level3 meanwhile
; (Check_busy, counted in Check_held): it calls random too.
; ***************************************************************************
CHECK_BAND	equ	(ST_PICTURE_LINES-ST_SPLIT)*ST_LINE/2	; words
CHECK_STATE	equ	(star_anz*6+funkel_anz2*funkel_size2)/2+3	; words
CHECK_RECORD	equ	(CHECK_STATE+2*CHECK_BAND)*2		; bytes

Check_stars:
	st	Check_busy
	lea	Check_before,a1
	bsr	Check_save
	jsr	make_funkel2
	jsr	make_magic
	bsr	Blitter_wait
	lea	Check_thalion,a1
	bsr	Check_save
	lea	Check_before,a1
	bsr	Check_restore
	bsr	Dust_st
	bsr	Magic_st
	lea	Check_ours,a1
	bsr	Check_save
	sf	Check_busy
	addq.l	#1,Check_frames
	lea	Check_thalion,a0
	lea	Check_ours,a1
	move.w	#CHECK_STATE,d0
	bsr	Check_same
	beq.b	.state
	addq.l	#1,Check_state_errors
	bsr	Check_first
.state:	move.w	#CHECK_BAND,d0
	bsr	Check_same
	bne.b	.pixel
	move.w	#CHECK_BAND,d0
	bsr	Check_same
	beq.b	.done
.pixel:	addq.l	#1,Check_pixel_errors
	bsr	Check_first
.done:	rts

Check_first:
	tst.l	Check_first_error
	bne.b	.has
	move.l	Check_frames,Check_first_error
.has:	rts

; Check_save -- the state and both lower bands into the record at a1.
Check_save:
	lea	magic_buffer,a0
	move.w	#star_anz*6/2,d0
	bsr	Check_copy
	lea	plot_buffer2,a0
	move.w	#funkel_anz2*funkel_size2/2,d0
	bsr	Check_copy
	move.w	old_random,(a1)+
	move.w	magic_x,(a1)+
	move.w	magic_doit,(a1)+
	move.l	St_work,a0
	lea	ST_SPLIT*ST_LINE(a0),a0
	move.w	#CHECK_BAND,d0
	bsr	Check_copy
	lea	St_background+ST_SPLIT*ST_LINE,a0
	move.w	#CHECK_BAND,d0
	bra.b	Check_copy

; Check_restore -- back from the record at a1.
Check_restore:
	move.l	a1,a0
	lea	magic_buffer,a1
	move.w	#star_anz*6/2,d0
	bsr	Check_copy
	lea	plot_buffer2,a1
	move.w	#funkel_anz2*funkel_size2/2,d0
	bsr	Check_copy
	move.w	(a0)+,old_random
	move.w	(a0)+,magic_x
	move.w	(a0)+,magic_doit
	move.l	St_work,a1
	lea	ST_SPLIT*ST_LINE(a1),a1
	move.w	#CHECK_BAND,d0
	bsr	Check_copy
	lea	St_background+ST_SPLIT*ST_LINE,a1
	move.w	#CHECK_BAND,d0
	; fall through

; Check_copy -- d0 words from a0 to a1, both advance.
Check_copy:
	subq.w	#1,d0
.w:	move.w	(a0)+,(a1)+
	dbf	d0,.w
	rts

; Check_same -- Z set when d0 words at a0 and a1 agree; both advance by
; d0 words either way.
Check_same:
	movem.l	d1/a2-a3,-(sp)
	lea	0(a0,d0.w),a2
	lea	0(a2,d0.w),a2
	lea	0(a1,d0.w),a3
	lea	0(a3,d0.w),a3
	subq.w	#1,d0
.w:	cmpm.w	(a0)+,(a1)+
	dbne	d0,.w
	sne	d1
	move.l	a2,a0
	move.l	a3,a1
	tst.b	d1
	movem.l	(sp)+,d1/a2-a3
	rts
	endc

	SECTION	Fee_bss,bss
Row_offset:		ds.w	AMIGA_ROWS-SPLIT_ROW
Byte_offset:		ds.w	bpscanl/planes
Dust_jmptab:		ds.l	32
	ifd	CHECK_DEFER
Deferred_place:		ds.l	1
Deferred_routine:	ds.l	1
	endc
	ifd	CHECK_STARS
Check_frames:		ds.l	1
Check_state_errors:	ds.l	1
Check_pixel_errors:	ds.l	1
Check_first_error:	ds.l	1
Check_held:		ds.l	1
Check_before:		ds.b	CHECK_RECORD
Check_thalion:		ds.b	CHECK_RECORD
Check_ours:		ds.b	CHECK_RECORD
Check_busy:		ds.b	1
			even
	endc

	SECTION	Fee_code,code

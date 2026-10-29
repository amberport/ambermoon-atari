; ***************************************************************************
; FANTASY_ST.S -- the ST layer under Thalion's FAIRY.S (fantasy intro, ST/STE).
;
; **Who does what** (docs/05c-ST.md, "ST fairy intro, plan"):
;
;   Thalion's FAIRY.S        fairy, dust, stars, logo, level3.  Unchanged.
;   Thalion's Hunk-1 code    fades, screen swap, tables: pulled out of
;                            Fantasy_intro at build time (fantasy_auszug.py),
;                            the same as on the Falcon.
;   tools/fantasy_st_data.py the graphics in ST format, colour tables (V3)
;   this file                what hung on copper, CIA, sprites, blitter and
;                            the OS on the Amiga, in Thalion's order (Hunk 1
;                            $110-$2B0), for the ST.
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3: Thalion's main flow,
; the sprites, plots, blits and copper split are ours here, the graphics
; in ST format from the build (what differs from the Amiga: docs/17).
;
; **K1** as on the Falcon: tools/fairy_umbiegen.py bends the ten $DFFxxx
; operands of FAIRY.S to Amiga_register after linking.
;
; **The picture:** low resolution, ST line 0 = Amiga row AMIGA_FIRST, the
; lower border opened (fantasy_st_defs.i).  Thalion draws into workbase, an
; Amiga buffer nobody shows; what shows is two ST screens, drawn by the
; hooks (step 4: plot_jmptab, Blitter_wait, the sprites).
;
; **Colours:** two bands of 16 ST registers.  Fairy_vbl sets the upper one,
; Timer B the lower one at ST line ST_SPLIT (Amiga row 134, where
; Thalion's copper reloads seven colours).  ST register r shows the Amiga
; colour St_rep_upper/St_rep_lower[r] as level3 last set it, so it follows
; Thalion's fades.
;
; **Drawing** (step 4), all into the ST work screen, all below row 134:
;
;   sparks  make_funkel (Thalion's) through plot_jmptab, which points to
;           Plot_st0..15, one per ST register; Plot_table turns
;           Thalion's workbase address into the ST one
;   dust    Dust_st, ours for Thalion's make_funkel2 (STARS_ST.S)
;   stars   Magic_st, ours for Thalion's make_magic: the compiled routine
;           for image and shift (fantasy_st_stars.i)
;   logo    Magic_st: the 4-pixel column into St_background
;
; Blitter_wait (waitblit) still does Thalion's star and logo blits; since
; Dust_st and Magic_st only the CHECK_STARS build has any.
;   fairy   Fairy_draw, once a frame, after the last blit: frame and place
;           from the sprite pointers and control words level3 wrote (K1),
;           the frame preshifted at start (Fairy_shift_*)
;
; Lower_restore copies the lower band back from St_background every
; frame (Thalion's $BC0 blit), and that erases all of it.
; ***************************************************************************

	SECTION	Fee_code,code

; ***************************************************************************
; start -- program entry.  Our own stack, then give back to GEMDOS what
; the program does not need: the fairy's preshift comes from Malloc.
; ***************************************************************************
start:
	move.l	4(sp),a0		; basepage
	lea	Stack_end,sp
	move.l	$C(a0),d0		; text
	add.l	$14(a0),d0		; data
	add.l	$1C(a0),d0		; bss
	add.l	#$100,d0
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#Mshrink,-(sp)
	trap	#1
	lea	12(sp),sp
	clr.l	-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,Old_ssp
	bsr	Notausgang_einhaengen	; teardown even after bombs (AMIGA_NOTAUS.S)

	bsr	Machine_check
	bne.b	.wrong
	bsr	Fairy_setup
	bsr	Fairy_flow
	bsr	Fairy_teardown
	move.l	Fairy_buffer,d0
	beq.b	.end
	move.l	d0,-(sp)
	move.w	#Mfree,-(sp)
	trap	#1
	addq.l	#6,sp
	bra.b	.end
.wrong:
	pea	Text_no_st
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
.end:
	move.l	Old_ssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Pterm0,-(sp)
	trap	#1

; ***************************************************************************
; Machine_check -- Z set on an ST, STE or Mega STE with a colour monitor.
; Sets Is_ste (STE palette, four bits a channel) and Is_mste.  No cookie
; jar: a plain ST with TOS 1.0x.  TT and Falcon: no (the Falcon has
; FANTASY.TOS; the opened border needs the ST GLUE).
; ***************************************************************************
Machine_check:
	sf	Is_ste
	sf	Is_mste
	move.l	COOKIES.w,d0
	beq.b	.monitor
	move.l	d0,a0
.search:	move.l	(a0)+,d0
	beq.b	.monitor
	move.l	(a0)+,d1
	cmp.l	#'_MCH',d0
	bne.b	.search
	cmp.l	#MCH_MSTE,d1
	seq	Is_mste
	swap	d1
	cmp.w	#MCH_STE,d1
	bhi.b	.no
	seq	Is_ste
.monitor:
	move.w	#Getrez,-(sp)
	trap	#14
	addq.l	#2,sp
	cmp.w	#2,d0			; monochrome monitor
	beq.b	.no
	moveq	#0,d0			; Z: yes
	rts
.no:	moveq	#1,d0
	rts

; ***************************************************************************
; Fairy_setup -- low resolution at 50 Hz, two screens, black, mouse.
; The counterpart of Thalion's start ($000-$10E: switch the OS off).
; ***************************************************************************
Fairy_setup:
	move.w	#Getrez,-(sp)
	trap	#14
	addq.l	#2,sp
	move.w	d0,Old_mode
	move.w	#Physbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,Old_screen
	move.w	#Logbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,Old_log
	movem.l	ST_PAL.w,d0-d7		; desktop colours, before switching
	movem.l	d0-d7,Old_colours
	move.b	SYNC_MODE.w,Old_sync

	pea	Text_cursor_off
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp

	; screens on 256 bytes: the ST has no low base byte, and the border
	; switch reads the line position from the counter's low byte
	move.l	#St_memory+255,d0
	clr.b	d0
	move.l	d0,St_screen_a
	add.l	#ST_SCREEN,d0
	move.l	d0,St_screen_b

	st	Ab_modus		; from here the teardown restores
	clr.w	-(sp)			; low resolution
	move.l	St_screen_a,-(sp)
	move.l	St_screen_a,-(sp)
	move.w	#Setscreen,-(sp)
	trap	#14
	lea	12(sp),sp
	move.w	#XB_Vsync,-(sp)
	trap	#14
	addq.l	#2,sp
	lea	ST_PAL.w,a0		; black until Thalion fades in
	moveq	#16/2-1,d7
.black:	clr.l	(a0)+
	dbf	d7,.black
	bset	#1,SYNC_MODE.w		; 50 Hz, as Thalion's Amiga

	bsr	Colour_table_setup
	bsr	Sources_build

	; the fairy's 16 preshifts; without the memory no fairy
	move.l	#ST_FAIRY_BUFFER,-(sp)
	move.w	#Malloc,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,Fairy_buffer

	; mouse: only the buttons, as Thalion's btst #6,$bfe001
	move.w	#Kbdvbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,a0
	move.l	16(a0),Old_mouse_vector
	move.l	a0,Kbd_vectors
	move.l	#Fairy_mouse,16(a0)
	st	Ab_maus
	rts

; ***************************************************************************
; Colour_table_setup -- Colour_table: Amiga $0RGB -> ST register value, 4096
; words, for this machine (ST three bits a channel, STE four with the low
; bit on top).
; ***************************************************************************
Colour_table_setup:
	lea	Levels_st,a1
	tst.b	Is_ste
	beq.b	.st
	lea	Levels_ste,a1
.st:	lea	Colour_table,a0
	moveq	#0,d0			; Amiga colour
.f:	moveq	#0,d3
	move.w	d0,d1
	lsr.w	#8,d1
	move.b	0(a1,d1.w),d3		; R
	lsl.w	#4,d3
	move.w	d0,d1
	lsr.w	#4,d1
	and.w	#15,d1
	or.b	0(a1,d1.w),d3		; G
	lsl.w	#4,d3
	move.w	d0,d1
	and.w	#15,d1
	or.b	0(a1,d1.w),d3		; B
	move.w	d3,(a0)+
	addq.w	#1,d0
	cmp.w	#$1000,d0
	bne.b	.f
	rts

; ***************************************************************************
; Sources_build -- per ST register the address of the Amiga colour it shows.
; Upper band: the colour level3 wrote to $DFF180 (Amiga_register).  Lower
; band: the same, except the seven colours the copper list reloads from
; Palette_unten at row 134 (Farbwechsel_register, as Fairy_vbl on the Falcon).
; ***************************************************************************
Sources_build:
	lea	St_rep_upper,a0
	lea	Sources_upper,a1
	moveq	#16-1,d7
.o:	moveq	#0,d0
	move.b	(a0)+,d0
	add.w	d0,d0
	lea	Amiga_register+AR_COLOR00,a2
	add.w	d0,a2
	move.l	a2,(a1)+
	dbf	d7,.o
	lea	St_rep_lower,a0
	lea	Sources_lower,a1
	moveq	#16-1,d7
.u:	moveq	#0,d0
	move.b	(a0)+,d0
	add.w	d0,d0
	lea	Amiga_register+AR_COLOR00,a2
	lea	Farbwechsel_register,a3
.search:	move.w	(a3)+,d1
	bmi.b	.set
	cmp.w	d0,d1
	bne.b	.search
	lea	Palette_unten,a2
.set:
	add.w	d0,a2
	move.l	a2,(a1)+
	dbf	d7,.u
	rts

; ***************************************************************************
; Fairy_teardown -- everything back as before the start.
;
; Repeatable (emergency exit, AMIGA_NOTAUS.S): each step only if its flag
; is set, and clears it.  In the emergency exit without GEMDOS.
; ***************************************************************************
Fairy_teardown:
	tst.b	Ab_vbl
	beq.b	.mouse
	move.w	sr,-(sp)
	or.w	#$0700,sr
	clr.b	MFP_TBCR.w
	bclr	#0,MFP_IERA.w
	bclr	#0,MFP_IMRA.w
	move.b	Old_tbdr,MFP_TBDR.w
	move.b	Old_iera,MFP_IERA.w
	move.b	Old_imra,MFP_IMRA.w
	move.l	Old_timerb,VEK_TIMERB.w
	move.b	Old_tbcr,MFP_TBCR.w
	move.l	Alter_vbl,VEK_VBL.w
	sf	Ab_vbl
	move.w	(sp)+,sr
.mouse:	tst.b	Ab_maus
	beq.b	.mode
	move.l	Kbd_vectors,a0
	move.l	Old_mouse_vector,16(a0)
	sf	Ab_maus
.mode:	tst.b	Ab_modus
	beq.b	.out
	sf	Ab_modus
	move.b	Old_sync,SYNC_MODE.w
	move.w	Old_mode,-(sp)
	move.l	Old_screen,-(sp)
	move.l	Old_log,-(sp)
	move.w	#Setscreen,-(sp)
	trap	#14
	lea	12(sp),sp
	move.w	#XB_Vsync,-(sp)
	trap	#14
	addq.l	#2,sp
	movem.l	Old_colours,d0-d7
	movem.l	d0-d7,ST_PAL.w
	tst.b	Im_notausgang
	bne.b	.out
	pea	Text_cursor_on
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
.out:	rts

NOTAUS_ABRAEUMEN	equ	Fairy_teardown
	include	"AMIGA_NOTAUS.S"

; ***************************************************************************
; Fairy_flow -- Thalion's main flow (Hunk 1 $110-$2B0), written out because
; it hangs on copper, CIA and DMA.  Order and values as there and as in
; Falcon's FEE_SUP.S; the addresses in brackets are the places in Hunk 1.
; ***************************************************************************
Fairy_flow:
	bsr	Hardware_setup	; ($D22)
	bsr	Screens_setup	; ($C2C)
	; background on both screens ($118), from the ST copy
	lea	St_background,a0
	move.l	St_show,a1
	move.l	St_work,a2
	move.w	#ST_PICTURE_LINES*ST_LINE/4-1,d7
.bg:	move.l	(a0)+,d0
	move.l	d0,(a1)+
	move.l	d0,(a2)+
	dbf	d7,.bg
	bsr	Plot_setup
	bsr	Stars_setup
	bsr	Fairy_shift_begin
	bsr	Wait_vbl
	; ($144) start values
	move.w	#160,posx
	move.w	#100,posy
	lea	plot_buffer,a0
	move.w	#funkel_anz-1,d7
.pb:	move.w	#-1,(a0)
	add.w	#funkel_size,a0
	dbf	d7,.pb
	lea	plot_buffer2,a0
	move.w	#funkel_anz2-1,d7
.pb2:	clr.l	(a0)
	add.w	#funkel_size2,a0
	dbf	d7,.pb2
	lea	magic_buffer,a0
	move.w	#star_anz-1,d7
.mb:	move.w	#-1,(a0)
	addq.l	#6,a0
	dbf	d7,.mb
	clr.w	elfe_ani
	clr.w	elfe_anidelay
	clr.w	elfe_fcount
	move.w	#2,elfe_fdelay
	clr.w	leave_flag
	clr.w	magic_doit
	move.w	#-1,magic_x
	move.l	#Flugbahn,elfe_kptr
	; ($1D0) fade in: 15 steps, two frames each
	moveq	#14,d6
.in:	bsr	Wait_vbl
	bsr	Wait_vbl
	lea	Palette_oben_quelle,a0
	lea	palette0,a1
	moveq	#32,d7
	bsr	Farben_einblenden
	lea	Palette_unten_quelle,a0
	lea	Palette_unten,a1
	moveq	#32,d7
	bsr	Farben_einblenden
	dbf	d6,.in
	; ($20A) wait up to 50 frames, the mouse button ends it
	moveq	#50,d7
.wait:	bsr	Wait_vbl
	bsr	Mouse_pressed
	dbne	d7,.wait
	bsr	Fairy_shift_finish
	move.w	#-1,vbl_flag		; ($21E) now the fairy flies
; ($226) the loop: three VBL a frame (vindex >= 2, then vsync)
.frame:
	ifd	ABSTURZTEST
	bsr	Absturz_pruefen
	endc
	bsr	Schirme_tauschen	; Thalion's: both Amiga screens are workbase
	bsr	St_swap		; ours: the two ST screens
	bsr	Display_set		; ($C98, copper list)
	jsr	vsync
	clr.l	vindex
	bsr	Lower_restore	; ($BC0)
	jsr	make_funkel
	ifd	CHECK_STARS
	bsr	Check_stars		; Thalion's and ours, compared
	else
	bsr	Dust_st			; ours for make_funkel2 (STARS_ST.S)
	bsr	Magic_st		; ours for make_magic
	endc
	bsr	Fairy_draw		; ours: the sprites
.sync:	cmp.l	#2,vindex
	blt.b	.sync
	; ($254) mouse button: fade out in 16 frames
	bsr	Mouse_pressed
	beq.b	.none
	tst.w	leave_flag
	beq.b	.set
	cmp.w	#16,leave_flag
	ble.b	.none
.set:
	move.w	#16,leave_flag
.none:	tst.w	leave_flag
	beq	.frame
	subq.w	#1,leave_flag
	beq.b	.out
	cmp.w	#16,leave_flag
	bge	.frame
	lea	palette0,a0
	moveq	#32,d7
	bsr	Farben_ausblenden
	lea	Palette_unten,a0
	moveq	#32,d7
	bsr	Farben_ausblenden
	bra	.frame
.out:	rts

; ***************************************************************************
; Hardware_setup -- ($D22) level3 as VBL, start colours, vbl_flag off;
; Timer B for the colour split and the lower border.
;
; On the Amiga level3 is the level 3 interrupt.  Here Fairy_vbl jumps into it
; with the VBL's exception frame on the stack: Thalion's rte returns right.
; ***************************************************************************
Hardware_setup:
	movem.l	Anfangsfarben,d0-d7
	movem.l	d0-d7,Amiga_register+AR_COLOR00
	movem.l	d0-d7,Amiga_register+AR_COLOR00+32
	clr.w	vbl_flag
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	VEK_TIMERB.w,Old_timerb
	move.b	MFP_TBCR.w,Old_tbcr
	move.b	MFP_TBDR.w,Old_tbdr
	move.b	MFP_IERA.w,Old_iera
	move.b	MFP_IMRA.w,Old_imra
	clr.b	MFP_TBCR.w
	move.l	VEK_VBL.w,Alter_vbl
	move.l	#Fairy_vbl,VEK_VBL.w
	st	Ab_vbl
	move.w	(sp)+,sr
	rts

; ***************************************************************************
; Screens_setup -- ($C2C) Thalion's two screens are one buffer nobody
; shows (workbase stays put); ours are St_show and St_work.
; ***************************************************************************
Screens_setup:
	move.l	#Amiga_screen,d0
	move.l	d0,Schirm_arbeit
	move.l	d0,Schirm_zeigen
	move.l	d0,workbase
	move.l	St_screen_a,St_show
	move.l	St_screen_b,St_work
	bsr.b	Plot_target_set
	bsr	Display_set
	jmp	vsync

; St_swap -- the ST screens, next to Thalion's Schirme_tauschen.
St_swap:
	move.l	St_work,d0
	move.l	St_show,St_work
	move.l	d0,St_show
Plot_target_set:
	move.l	St_work,d0
	add.l	#ST_SPLIT*ST_LINE,d0
	move.l	d0,Plot_target
	rts

; ***************************************************************************
; Display_set -- (copper list $C98) show St_show from the next frame
; on.  The ST loads the video counter from the base at the start of the
; vertical blank, so the base is written here, before vsync; Fairy_vbl writes
; it once more with the same value.
; ***************************************************************************
Display_set:
	move.l	d0,-(sp)
	move.l	St_show,d0
	move.l	d0,Display_next
	lsr.w	#8,d0
	move.b	d0,VBASE_MID.w
	swap	d0
	move.b	d0,VBASE_HIGH.w
	move.l	(sp)+,d0
	rts

; ***************************************************************************
; Lower_restore -- ($BC0) Thalion's blit: the rows from SPLIT_ROW on
; from the background into the work screen; there dust and stars fall, and
; there make_magic writes the logo into the background.  Here from the ST
; background, ten registers at a time.
; ***************************************************************************
Lower_restore:
	lea	St_background+ST_SPLIT*ST_LINE,a0
	move.l	St_work,a1
	lea	ST_SPLIT*ST_LINE(a1),a1
	move.w	#(ST_PICTURE_LINES-ST_SPLIT)*ST_LINE/40-1,d7
.k:	movem.l	(a0)+,d0-d6/a2-a4
	movem.l	d0-d6/a2-a4,(a1)
	lea	40(a1),a1
	dbf	d7,.k
	rts

; ***************************************************************************
; Wait_vbl -- Thalion's vsync (wait for the next VBL), but the wait goes into
; the fairy's preshift, one row of one frame at a time (about 20 lines).
; For the fade in and the wait before the flight (80 VBL); what is left
; Fairy_shift_finish does before the fairy flies.
; ***************************************************************************
Wait_vbl:
	move.l	d0,-(sp)
	move.l	vindex,d0
.w:	cmp.l	vindex,d0
	bne.b	.found
	cmp.w	#ST_FAIRY_FRAMES*ST_FAIRY_ROWS,Shift_row
	bcc.b	.w
	bsr	Fairy_shift_step
	bra.b	.w
.found:	move.l	(sp)+,d0
	rts

Fairy_shift_finish:
.w:	cmp.w	#ST_FAIRY_FRAMES*ST_FAIRY_ROWS,Shift_row
	bcc.b	.out
	bsr	Fairy_shift_step
	bra.b	.w
.out:	rts

; ***************************************************************************
; Fairy_shift_begin -- Fairy_shifts: per frame and shift where its rows
; start in Fairy_buffer.  A frame needs St_fairy_groups groups a row once
; shifted (4 or 5), 10 bytes a group: ~mask, planes 0-3.
; ***************************************************************************
Fairy_shift_begin:
	clr.w	Shift_row
	move.l	Fairy_buffer,d0
	bne.b	.found
	move.w	#ST_FAIRY_FRAMES*ST_FAIRY_ROWS,Shift_row	; no memory: no fairy
	rts
.found:	lea	Fairy_shifts,a0
	lea	St_fairy_groups,a1
	moveq	#ST_FAIRY_FRAMES-1,d7
.b:	moveq	#0,d1
	move.b	(a1)+,d1
	mulu	#ST_FAIRY_ROWS*10,d1
	moveq	#16-1,d6
.s:	move.l	d0,(a0)+
	add.l	d1,d0
	dbf	d6,.s
	dbf	d7,.b
	rts

; ***************************************************************************
; Fairy_shift_step -- row Shift_row of St_fairy (frame-major) in all 16
; shifts.  Per plane the four source words go into d0-d3 (d4 takes what
; leaves on the right) and move right one pixel per shift.  The mask is
; stored inverted, for and.l: it shifts in ones.  All registers stay.
; ***************************************************************************
SHIFT_WORD	macro			; \1 = groups (4/5), \2 = word in the group
	move.l	a1,a6
	move.w	\2(a0),d0
	move.w	\2+10(a0),d1
	move.w	\2+20(a0),d2
	move.w	\2+30(a0),d3
	moveq	#0,d4
	ifeq	\2
	not.w	d0
	not.w	d1
	not.w	d2
	not.w	d3
	not.w	d4
	endc
	moveq	#16-1,d7
.s\@:	move.w	d0,\2(a6)
	move.w	d1,\2+10(a6)
	move.w	d2,\2+20(a6)
	move.w	d3,\2+30(a6)
	ifeq	\1-5
	move.w	d4,\2+40(a6)
	endc
	add.l	a5,a6
	ifeq	\2
	move.w	#$10,ccr		; X: a one comes in
	roxr.w	#1,d0
	else
	lsr.w	#1,d0
	endc
	roxr.w	#1,d1
	roxr.w	#1,d2
	roxr.w	#1,d3
	ifeq	\1-5
	roxr.w	#1,d4
	endc
	dbf	d7,.s\@
	endm

Fairy_shift_step:
	movem.l	d0-d7/a0-a1/a5-a6,-(sp)
	moveq	#0,d0
	move.w	Shift_row,d0
	addq.w	#1,Shift_row
	lea	St_fairy,a0
	move.w	d0,d1
	mulu	#4*10,d1
	add.l	d1,a0
	divu	#ST_FAIRY_ROWS,d0	; row : frame
	lea	St_fairy_groups,a1
	moveq	#0,d5
	move.b	0(a1,d0.w),d5
	move.w	d5,d1
	mulu	#ST_FAIRY_ROWS*10,d1
	move.l	d1,a5			; from one shift to the next
	move.w	d0,d1
	lsl.w	#6,d1			; frame * 16 shifts * 4
	lea	Fairy_shifts,a1
	move.l	0(a1,d1.w),a1
	swap	d0
	mulu	d5,d0
	mulu	#10,d0
	add.l	d0,a1			; the row
	cmp.w	#5,d5
	beq.w	.five
	SHIFT_WORD 4,0
	SHIFT_WORD 4,2
	SHIFT_WORD 4,4
	SHIFT_WORD 4,6
	SHIFT_WORD 4,8
	bra.w	.done
.five:	SHIFT_WORD 5,0
	SHIFT_WORD 5,2
	SHIFT_WORD 5,4
	SHIFT_WORD 5,6
	SHIFT_WORD 5,8
.done:
	movem.l	(sp)+,d0-d7/a0-a1/a5-a6
	rts

; ***************************************************************************
; Fairy_draw -- the fairy into the work screen, once a frame (the rest of
; the scene moves once a frame too; on the Amiga the sprites follow level3
; every VBL).  What the sprite DMA shows, from what level3 wrote: the
; pointer of sprite 0 names the frame (Thalion's eight sprites of a frame
; lie one after the other in elfe), its two control words the place
; (Fee_sprites on the Falcon): word 1 VSTART 0-7 | HSTART 1-8, word 2
; VSTOP 0-7 | attach | V8 E8 H0; zero point $80 across, $28 down.  Any other
; pointer (sprite_00 while the fairy is off): nothing.
;
; Clipped to the lower band (Lower_restore erases only there) and to the
; picture's width by groups.
; ***************************************************************************
Fairy_draw:
	movem.l	d0-d7/a0-a2,-(sp)
	cmp.w	#ST_FAIRY_FRAMES*ST_FAIRY_ROWS,Shift_row
	bcs	.out			; not preshifted yet (or no memory)
	tst.l	Fairy_buffer
	beq	.out
	move.l	Amiga_register+AR_SPR0PT,d0
	move.l	d0,a0
	sub.l	#elfe,d0
	bcs	.out
	cmp.l	#ST_FAIRY_FRAMES*ST_FAIRY_FRAME,d0
	bcc	.out
	divu	#ST_FAIRY_FRAME,d0
	move.l	d0,d1
	swap	d1
	tst.w	d1
	bne	.out			; not the start of a frame
	move.w	(a0),d1
	move.w	2(a0),d2
	moveq	#0,d3
	move.b	d1,d3			; HSTART 1-8
	add.w	d3,d3
	btst	#0,d2
	beq.b	.h0
	addq.w	#1,d3
.h0:	sub.w	#$80,d3			; x
	lsr.w	#8,d1			; VSTART
	btst	#2,d2
	beq.b	.v8
	bset	#8,d1
.v8:	sub.w	#$28+AMIGA_FIRST,d1	; ST line of the fairy's row 0
	move.w	d1,d4			; first line drawn
	cmp.w	#ST_SPLIT,d4
	bge.b	.top
	move.w	#ST_SPLIT,d4
.top:	move.w	d1,d5
	add.w	#ST_FAIRY_ROWS,d5
	cmp.w	#ST_PICTURE_LINES,d5
	ble.b	.bottom
	move.w	#ST_PICTURE_LINES,d5
.bottom:	sub.w	d4,d5			; lines drawn
	ble	.out
	; the data: frame d0, shift x & 15, from the first line drawn
	lea	St_fairy_groups,a1
	moveq	#0,d6
	move.b	0(a1,d0.w),d6		; groups a row
	moveq	#15,d7
	and.w	d3,d7
	lsl.w	#4,d0
	add.w	d7,d0
	lsl.w	#2,d0
	lea	Fairy_shifts,a1
	move.l	0(a1,d0.w),a1
	move.w	d6,d7
	mulu	#10,d7			; bytes a row
	move.w	d4,d0
	sub.w	d1,d0
	mulu	d7,d0
	add.l	d0,a1
	; the groups inside the picture
	asr.w	#4,d3			; group of the fairy's left edge
	moveq	#0,d0			; first group drawn
	tst.w	d3
	bpl.b	.left
	move.w	d3,d0
	neg.w	d0
.left:	moveq	#ST_LINE/8,d2
	sub.w	d3,d2			; groups up to the right edge
	cmp.w	d6,d2
	ble.b	.right
	move.w	d6,d2
.right:
	sub.w	d0,d2			; groups drawn
	ble	.out
	move.w	d0,d1
	mulu	#10,d1
	add.w	d1,a1
	move.l	St_work,a2
	mulu	#ST_LINE,d4
	add.l	d4,a2
	add.w	d3,d0
	lsl.w	#3,d0
	add.w	d0,a2
	move.w	d2,d1
	mulu	#10,d1
	sub.w	d1,d7			; data to skip after a row
	move.w	#ST_LINE,d6
	move.w	d2,d1
	lsl.w	#3,d1
	sub.w	d1,d6			; screen to skip after a row
	subq.w	#1,d2
	subq.w	#1,d5
.line:	move.w	d2,d4
.group:
	move.w	(a1)+,d0		; ~mask, into both halves
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)
	and.l	d0,4(a2)
	move.l	(a1)+,d0
	or.l	d0,(a2)+
	move.l	(a1)+,d0
	or.l	d0,(a2)+
	dbf	d4,.group
	add.w	d7,a1
	add.w	d6,a2
	dbf	d5,.line
.out:	movem.l	(sp)+,d0-d7/a0-a2
	rts

; ***************************************************************************
; Plot_setup -- the dust hook.  Plot_table: for each byte of workbase
; from row 134 on, the offset of the same 8 pixels in an ST screen from
; line ST_SPLIT on (Thalion's plots address plane 0; the four other
; Amiga planes of a row get the same, harmless).  plot_jmptab: per Amiga
; colour the ST routine of its register in the lower band.
; ***************************************************************************
Plot_setup:
	lea	Plot_table,a0
	moveq	#0,d0			; ST offset of the line
	move.w	#AMIGA_ROWS-SPLIT_ROW-1,d7
.z:	moveq	#planes-1,d6
.e:	moveq	#0,d1			; byte in the plane's line
.b:	move.w	d1,d2
	lsr.w	#1,d2
	lsl.w	#3,d2
	move.w	d1,d3
	and.w	#1,d3
	or.w	d3,d2
	add.w	d0,d2
	move.w	d2,(a0)+
	addq.w	#1,d1
	cmp.w	#bpscanl/planes,d1
	bne.b	.b
	dbf	d6,.e
	add.w	#ST_LINE,d0
	dbf	d7,.z
	lea	plot_jmptab,a0
	lea	St_map_lower,a1
	lea	Plot_routines,a2
	moveq	#32-1,d7
.j:	moveq	#0,d0
	move.b	(a1)+,d0
	lsl.w	#2,d0
	move.l	0(a2,d0.w),(a0)+
	dbf	d7,.j
	rts

; Plot_st0..15 -- for Thalion's plot_5p2 and make_funkel2 instead of
; .plot00-.plot31: a0 = byte in workbase, d0 = its pixels, d1 = not d0.
; Set ST register \1 there.  All registers stay (plot_5p2 calls a1 again
; with a0 + 1).
PLOT_ST	macro
Plot_st\1:
	movem.l	d2/a0,-(sp)
	move.l	a0,d2
	sub.l	#Amiga_screen+SPLIT_ROW*bpscanl,d2
	cmp.l	#PLOT_BYTES,d2
	bcc.b	.weg\@
	add.l	d2,d2
	lea	Plot_table,a0
	move.w	0(a0,d2.l),d2
	move.l	Plot_target,a0
	add.w	d2,a0
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
.weg\@:	movem.l	(sp)+,d2/a0
	rts
	endm

	PLOT_ST	0
	PLOT_ST	1
	PLOT_ST	2
	PLOT_ST	3
	PLOT_ST	4
	PLOT_ST	5
	PLOT_ST	6
	PLOT_ST	7
	PLOT_ST	8
	PLOT_ST	9
	PLOT_ST	10
	PLOT_ST	11
	PLOT_ST	12
	PLOT_ST	13
	PLOT_ST	14
	PLOT_ST	15

Plot_routines:
	dc.l	Plot_st0,Plot_st1,Plot_st2,Plot_st3
	dc.l	Plot_st4,Plot_st5,Plot_st6,Plot_st7
	dc.l	Plot_st8,Plot_st9,Plot_st10,Plot_st11
	dc.l	Plot_st12,Plot_st13,Plot_st14,Plot_st15

; ***************************************************************************
; Blitter_wait -- waitblit (fantasy_st_defs.i): does the blit FAIRY.S set
; up last in Amiga_register, if any (BLTSIZE not 0), in ST format.  FAIRY.S
; has two kinds (minterm in BLTCON0):
;
;   $CA  a star (blit_star, blit_star2): B the image, A its mask, D the
;        place in workbase, the shift in BLTCON0 bits 12-15.  The image
;        number from B, the routine from fantasy_st_stars.i.
;   $E2  a column of the logo (make_magic): A in flogo, D in background,
;        BLTBDAT the four pixels.  Into St_background.
;
; The Amiga blitter ignores bit 0 of an address; blit_star2 passes odd
; ones.  All registers stay.
; ***************************************************************************
Blitter_wait:
	tst.w	Amiga_register+AR_BLTSIZE
	bne.b	.blit
	rts
.blit:	movem.l	d0-d3/a0-a1,-(sp)
	move.w	Amiga_register+AR_BLTCON0,d0
	cmp.b	#$CA,d0
	beq.b	.star
	cmp.b	#$E2,d0
	beq	.logo
.done:
	clr.w	Amiga_register+AR_BLTSIZE
	movem.l	(sp)+,d0-d3/a0-a1
	rts

.star:	move.l	Amiga_register+AR_BLTDPT,d1
	sub.l	#Amiga_screen+SPLIT_ROW*bpscanl,d1
	cmp.l	#PLOT_BYTES,d1
	bcc	.done
	and.w	#-2,d1
	add.l	d1,d1
	lea	Plot_table,a0
	move.w	0(a0,d1.l),d1
	move.l	Plot_target,a0
	add.w	d1,a0			; the group of the top row
	move.l	Amiga_register+AR_BLTBPT,d1
	sub.l	#overfunkel,d1
	cmp.l	#ST_STARS_BIG*ST_BIG_IMAGE,d1
	bcc.b	.small
	mulu	#ST_BIG_RECIP,d1
	swap	d1			; image
	bra.b	.frame
.small:	move.l	Amiga_register+AR_BLTBPT,d1
	sub.l	#stars,d1
	cmp.l	#ST_STARS_SMALL*ST_SMALL_IMAGE,d1
	bcc	.done
	mulu	#ST_SMALL_RECIP,d1
	swap	d1
	add.w	#ST_STARS_BIG,d1
.frame:	lsl.w	#4,d1
	rol.w	#4,d0
	and.w	#15,d0			; shift
	add.w	d0,d1
	lsl.w	#2,d1
	lea	Star_routines,a1
	move.l	0(a1,d1.w),a1
	jsr	(a1)
	bra	.done

.logo:	move.l	Amiga_register+AR_BLTDPT,d1
	sub.l	#background+SPLIT_ROW*bpscanl,d1
	cmp.l	#PLOT_BYTES,d1
	bcc	.done
	and.w	#-2,d1
	add.l	d1,d1
	lea	Plot_table,a0
	move.w	0(a0,d1.l),d1
	lea	St_background+ST_SPLIT*ST_LINE,a0
	add.w	d1,a0
	move.l	Amiga_register+AR_BLTAPT,d1
	sub.l	#flogo,d1
	cmp.l	#ST_LOGO_GROUPS*2,d1
	bcc	.done
	lsr.w	#1,d1
	lsl.w	#3,d1
	lea	St_logo,a1
	add.w	d1,a1
	move.w	Amiga_register+AR_BLTBDAT,d2
	move.w	d2,d1
	swap	d2
	move.w	d1,d2			; the four pixels, both halves
	moveq	#0,d0
	move.w	Amiga_register+AR_BLTSIZE,d0
	lsr.w	#6,d0
	divu	#planes,d0		; rows
	cmp.w	#ST_LOGO_ROWS,d0
	bls.b	.lines
	moveq	#ST_LOGO_ROWS,d0
.lines:
	subq.w	#1,d0
	bmi	.done
.lrow:	move.l	(a0),d1			; background ^= (background ^ logo) & mask
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
	dbf	d0,.lrow
	bra	.done

; ***************************************************************************
; Mouse_pressed -- Z clear while the left button is down.  Thalion asks
; btst #6,$bfe001 (down = 0); the condition is turned round here.
; ***************************************************************************
Mouse_pressed:
	btst	#1,Mouse_buttons
	rts

; Fairy_mouse -- mouse vector (Kbdvbase+16), a0 = IKBD packet.  Header
; $F8-$FB: bit 1 left, bit 0 right.
Fairy_mouse:
	move.b	(a0),Mouse_buttons
	rts

; ***************************************************************************
; Fairy_vbl -- the VBL.  Starts Timer B for this frame, sets the picture base
; and the colours from what level3 left in the previous VBL, then jumps into
; Thalion's level3 (FAIRY.S), which ends with rte.
;
; Timer B as in tools/st_rand/untrand.s: the pending bit goes before the
; enable, or an event latched last frame fires at once.  TBDR n fires at
; the end of line n-1: Tb_split at the end of line ST_SPLIT-2.
; ***************************************************************************
Fairy_vbl:
	movem.l	d0-d3/a0-a3,-(sp)
	addq.l	#1,FRCLOCK.w		; TOS waits on it, after bombs too (T16)
	ifd	ABSTURZTEST
	addq.l	#1,Absturz_zaehler
	endc
	clr.b	MFP_TBCR.w
	move.l	#Tb_split,VEK_TIMERB.w
	move.b	#ST_SPLIT-1,MFP_TBDR.w
	bclr	#0,MFP_IPRA.w
	bclr	#0,MFP_ISRA.w
	bset	#0,MFP_IERA.w
	bset	#0,MFP_IMRA.w
	move.b	#TB_EVENT_COUNT,MFP_TBCR.w
	move.l	Display_next,d0
	beq.b	.colours			; no screen chosen yet
	lsr.w	#8,d0
	move.b	d0,VBASE_MID.w
	swap	d0
	move.b	d0,VBASE_HIGH.w
.colours:
	; upper band straight to the palette, lower band for Tb_split
	lea	Colour_table,a2
	lea	Sources_upper,a0
	lea	ST_PAL.w,a1
	moveq	#16-1,d3
.o:	move.l	(a0)+,a3
	move.w	(a3),d0
	and.w	#$0FFF,d0
	add.w	d0,d0
	move.w	0(a2,d0.w),(a1)+
	dbf	d3,.o
	lea	Sources_lower,a0
	lea	Colours_lower,a1
	moveq	#16-1,d3
.u:	move.l	(a0)+,a3
	move.w	(a3),d0
	and.w	#$0FFF,d0
	add.w	d0,d0
	move.w	0(a2,d0.w),(a1)+
	dbf	d3,.u
	movem.l	(sp)+,d0-d3/a0-a3
	ifd	CHECK_STARS
	tst.b	Check_busy
	beq.b	.level3
	addq.l	#1,Check_held		; level3 calls random: not now
	rte
.level3:
	endc
	jmp	level3

; ***************************************************************************
; Screen_base -- d4.l = the screen shown in this frame: the one whose memory
; the video counter is in.  Independent of when the ST took the base.
;   IN : a0 = VID_CNT.  Changes d5.
; ***************************************************************************
Screen_base:
	movep.l	-2(a0),d5		; base mid, then counter hi, mid, lo
	and.l	#$00FFFFFF,d5
	move.l	St_screen_b,d4
	cmp.l	d4,d5
	bhs.b	.b
	move.l	St_screen_a,d4
.b:	rts

; ***************************************************************************
; Tb_split -- Timer B at the end of line ST_SPLIT-2: the lower band's
; colours wait in registers, the video counter says when line ST_SPLIT-1
; is over, and the 16 colours go in during its border, before line
; ST_SPLIT shows.  Then count to line ST_BORDER-LEAD (untrand.s tb_split):
; restarted during the border, line ST_SPLIT counts as the first.
; ***************************************************************************
Tb_split:
	movem.l	d0-d7/a0-a5,-(sp)
	movem.l	Colours_lower,d0-d3/a2-a5
	lea	VID_CNT.w,a0
	bsr	Screen_base
	addq.l	#2,a0			; mid and low byte, for movep.w
	move.w	#WAIT_SPLIT-1,d7
.w:	movep.w	0(a0),d5
	sub.w	d4,d5			; offset into the picture
	cmp.w	#ST_SPLIT*ST_LINE,d5
	dbcc	d7,.w
	movem.l	d0-d3/a2-a5,ST_PAL.w
	clr.b	MFP_TBCR.w
	move.l	#Tb_border,VEK_TIMERB.w
	move.b	#(ST_BORDER-LEAD)-(ST_SPLIT-1),MFP_TBDR.w
	move.b	#TB_EVENT_COUNT,MFP_TBCR.w
	movem.l	(sp)+,d0-d7/a0-a5
	bclr	#0,MFP_ISRA.w
	rte

; ***************************************************************************
; Tb_border -- open the lower border (tools/st_rand/untrand.s tb_bottom, T93).
;
; Waits with all interrupts masked until the video counter is SYNC_FROM into
; the picture (line ST_BORDER being fetched), syncs to the cycle (the low
; byte says how far the line is, 2 bytes per 4 cycles; lsl waits the rest),
; DELAY_PRE nops to the end of line ST_BORDER's display, DELAY nops at 60 Hz.
; From the counter read in .w to the switch the code is untrand.s's
; instruction for instruction (sizes of the branches included): DELAY_PRE
; was measured on it.
; ***************************************************************************
Tb_border:
	move.w	#$2700,sr
	movem.l	d0-d5/a0-a1,-(sp)
	clr.b	MFP_TBCR.w		; one border event per frame
	tst.b	Is_mste
	beq.b	.sync
	move.b	MSTE_CLOCK.w,Old_mste_clock
	clr.b	MSTE_CLOCK.w		; 8 MHz, no cache: DELAY in bus cycles
.sync:	lea	VID_CNT.w,a0
	bsr	Screen_base
	addq.l	#2,a0			; mid and low byte, for movep.w
	move.w	d4,d3			; base, low word
	move.w	#WAIT_BORDER-1,d2
.w:	movep.w	0(a0),d0
	sub.w	d3,d0			; offset into the picture
	cmp.w	#SYNC_FROM,d0
	dbcc	d2,.w
	bcs.w	.too_late		; timeout: the border stays shut
	cmp.w	#(ST_BORDER+1)*ST_LINE,d0
	bcc.w	.late			; line ST_BORDER already over: no sync
	moveq	#0,d0
	move.b	2(a0),d0
	sub.b	#SYNC_START&$FF,d0	; bytes into line ST_BORDER
	moveq	#SYNC_K,d1
	sub.w	d0,d1
	bpl.b	.shift
	moveq	#0,d1
.shift:
	lsl.l	d1,d1			; 8+2n cycles: a later read waits less
	rept	DELAY_PRE
	nop
	endr
	bra.b	.switch
.late:	addq.l	#1,Border_late
.switch:
	clr.b	SYNC_MODE.w		; 60 Hz
	rept	DELAY
	nop
	endr
	move.b	#2,SYNC_MODE.w		; 50 Hz
	bra.b	.done
.too_late:
	addq.l	#1,Border_missed
.done:
	tst.b	Is_mste
	beq.b	.out
	move.b	Old_mste_clock,MSTE_CLOCK.w
.out:	bclr	#0,MFP_ISRA.w
	movem.l	(sp)+,d0-d5/a0-a1
	rte

; ***************************************************************************
; Data
; ***************************************************************************
	SECTION	Fee_daten,data
; Amiga level 0-15 -> ST level: three bits; STE: four, the lowest on top
Levels_st:
	dc.b	0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7
Levels_ste:
	dc.b	$0,$8,$1,$9,$2,$A,$3,$B,$4,$C,$5,$D,$6,$E,$7,$F
Text_no_st:
	dc.b	"Das Fantasy-Intro (FANTSYST.TOS) braucht einen ST oder STE",13,10
	dc.b	"mit Farbmonitor.  Taste druecken.",13,10,0
Text_cursor_off:
	dc.b	27,'f',0
Text_cursor_on:
	dc.b	27,'e',0
	even

	SECTION	Fee_bss,bss
Old_ssp:		ds.l	1
Alter_vbl:		ds.l	1
Old_timerb:		ds.l	1
Old_screen:		ds.l	1
Old_log:		ds.l	1
Old_mouse_vector:	ds.l	1
Kbd_vectors:		ds.l	1
Display_next:	ds.l	1
St_screen_a:		ds.l	1
St_screen_b:		ds.l	1	; = St_screen_a + ST_SCREEN (Screen_base)
St_show:		ds.l	1
St_work:		ds.l	1
Border_late:		ds.l	1	; Tb_border: line ST_BORDER over, no sync
Border_missed:		ds.l	1	; Tb_border: counter never got there
Plot_target:		ds.l	1	; St_work, line ST_SPLIT
Fairy_buffer:		ds.l	1	; Malloc, ST_FAIRY_BUFFER bytes, or 0
Fairy_shifts:		ds.l	ST_FAIRY_FRAMES*16	; per frame and shift
Sources_upper:		ds.l	16	; per ST register: its Amiga colour
Sources_lower:		ds.l	16
Old_mode:		ds.w	1
Shift_row:		ds.w	1	; next row to preshift (frame * 71 + row)
Plot_table:		ds.w	PLOT_BYTES	; workbase byte -> ST offset
Old_colours:		ds.w	16
Colours_lower:		ds.w	16	; lower band, Fairy_vbl -> Tb_split
Colour_table:		ds.w	$1000	; Amiga $0RGB -> ST register value
Amiga_register:		ds.b	AR_SIZE
Mouse_buttons:		ds.b	1
Old_sync:		ds.b	1
Old_tbcr:		ds.b	1
Old_tbdr:		ds.b	1
Old_iera:		ds.b	1
Old_imra:		ds.b	1
Old_mste_clock:	ds.b	1
Is_ste:		ds.b	1
Is_mste:		ds.b	1
			even
	include	"amiga_notaus_bss.i"
			even
Amiga_screen:		ds.b	AMIGA_SCREEN
Amiga_overflow:	ds.b	AMIGA_OVERFLOW	; stars below row 255
St_memory:		ds.b	2*ST_SCREEN+256
Stack:			ds.b	4096
Stack_end:

	SECTION	Fee_code,code

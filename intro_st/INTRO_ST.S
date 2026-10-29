; ***************************************************************************
; INTRO_ST.S -- the ST layer under Thalion's intro (Ambermoon_intro, ST/STE;
; docs/05c-ST.md "ST intro").  Own files, independent of the Falcon's
; amiga/ layer; only the emergency exit (amiga/AMIGA_NOTAUS.S) is shared,
; unchanged, as in the fairy.
;
; **Thalion's program** (hunks 0-6) comes unchanged from Ambermoon_intro at
; build time (tools/intro_st_program.py), bound to this layer:
;
;   K1  $DFFxxx -> Amiga_register, $BFE001 -> Amiga_cia_a, ExecBase ->
;       Exec_zeiger
;   K2  every write to BLTSIZE -> trap #8 -> K2_trap -> Amiga_blit
;       (BLIT_ST.S), done before Thalion's code goes on
;   K3  Vbl_end_hook at the end of Thalion's VBL; Zoom_st (ZOOM_ST.S);
;       Intro_switch (the base at once after a new copper list); the
;       target screens of every scene (TARGET_ST.S, the Falcon's method,
;       docs/11 7.8 and 7.8b): Space_begin, Meteor_begin, Logo_begin,
;       Clouds_begin, Menu_begin (the table), Logo_end, Menu_hold (the
;       picture held), Space_clear, Stars_set, City_space, City_meteor,
;       Anim_eor, Copy_shown_hidden, Logo_clear, Zoom_clear, Logo_stars,
;       Presents_row, Clouds_fill, Clouds_column, Clouds_draw (our writers;
;       the clouds in CLOUDS_ST.S), Logo_stages
;       (a scratch screen), City_text, Twinlake_before/after,
;       Clouds_background, Menu_texts (Thalion's CPU code, then bring),
;       Picture_fetch (a reader).  The places and the covered instructions
;       are in tools/intro_st_program.py; the names are the Falcon's where
;       it has them (docs/05c-ST.md).
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3: K3, the blitter
; and the display are ours.
;
; **Thalion's frame** (docs/11, 4.2): record in a0 = {pointer to the music
; player, flag byte}; exec and graphics opened, then trap #0 into the
; supervisor, where everything runs; at the end d0 = the menu choice.
; Thalion finds AttnFlags 0 and takes VBR 0: its VBL goes to $6C, its main
; program to $80 (trap #0).  Our VBL ($70) jumps to $6C.
;
; **The picture** (SHOW_ST.S): a target screen shown directly where the
; copper list shows one whole; at a change of format the picture held; the
; fallback converts what the copper list shows into ST format (E30: not
; expected any more).  The lower border is open (Tb_border).
;
; Music: no YM version of the intro music is known; Thalion's player is a
; table of rts (Music_silent).
; ***************************************************************************

	SECTION	Intro_code,code

; ***************************************************************************
; start -- program entry.  Command line "1" (the loader: a save game
; exists): Thalion's flag byte, no intro, CONTINUE in the menu.  The menu
; choice is the program's return value (lader/lader.s).
; ***************************************************************************
start:
	move.l	4(sp),a0		; basepage
	lea	Stack_end,sp
	cmp.b	#1,$80(a0)
	bne.b	.no_flag
	cmp.b	#'1',$81(a0)
	seq	Handover+4
.no_flag:
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

	move.w	#-1,Result
	bsr	Machine_check
	bne.b	.wrong
	bsr	Clouds_prepare		; our clouds (CLOUDS_ST.S)
	bsr	Intro_setup
	; Thalion's program, as the Amiga loader calls it: a0 = handover
	; record, the menu choice back in d0 (docs/11, 4.2)
	lea	Handover,a0
	jsr	Intro_h0
	SCENE	0
	move.w	d0,Result
	bsr	Intro_teardown
	ifd	SCREEN_DUMP
	bsr	Dumps_write		; DUMP_ST.S, with TOS back
	endc
	ifd	SCENE_LOG
	jsr	Scenes_write
	endc
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
	move.w	Result,-(sp)		; for the loader (lader/lader.s)
	move.w	#Pterm,-(sp)
	trap	#1

; ***************************************************************************
; Machine_check -- Z set on an ST, STE or Mega STE with a colour monitor.
; Sets Is_ste (STE palette, four bits a channel) and Is_mste.  As in the
; fairy (FANTASY_ST.S Machine_check): the opened border needs the ST GLUE.
; ***************************************************************************
Machine_check:
	sf	Is_ste
	sf	Is_mste
	move.l	COOKIES.w,d0
	beq.b	.monitor
	move.l	d0,a0
.find:	move.l	(a0)+,d0
	beq.b	.monitor
	move.l	(a0)+,d1
	cmp.l	#'_MCH',d0
	bne.b	.find
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
; Intro_setup -- low resolution at 50 Hz, two black screens, the Amiga side
; at rest, the library, mouse, vectors.
; ***************************************************************************
Intro_setup:
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
	move.l	d0,St_shown
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
	bsr	Star_offsets_setup	; TARGET_ST.S
	bsr	Display_setup		; SHOW_ST.S
	; Amiga side at rest: no button down
	move.b	#$FF,Amiga_cia_a
	move.w	#$FF00,Amiga_register+AR_POTGOR
	bsr	Library_setup

	move.w	#Kbdvbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,a0
	move.l	16(a0),Old_mouse_vector
	move.l	a0,Kbd_vectors
	move.l	#Mouse_vector,16(a0)
	st	Ab_maus
	ifd	SCREEN_DUMP
	bsr	Dump_setup		; DUMP_ST.S
	endc

	; vectors: $6C gets a bare rte until Thalion puts its VBL there; $80
	; (trap #0) Thalion sets itself.  Timer B: Vbl starts it every frame.
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	VEK_LEVEL3.w,Old_level3
	move.l	VEK_TRAP0.w,Old_trap0
	move.l	VEK_TRAP8.w,Old_trap8
	move.l	#K2_trap,VEK_TRAP8.w
	move.l	#Bare_rte,VEK_LEVEL3.w
	move.b	MFP_TBCR.w,Old_tbcr
	move.b	MFP_TBDR.w,Old_tbdr
	move.b	MFP_IERA.w,Old_iera
	move.b	MFP_IMRA.w,Old_imra
	move.l	VEK_TIMERB.w,Old_timerb
	move.l	VEK_VBL.w,Alter_vbl
	move.l	#Vbl,VEK_VBL.w
	st	Ab_vbl
	move.w	(sp)+,sr
	rts

Bare_rte:
	rte

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
.c:	moveq	#0,d3
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
	bne.b	.c
	rts

; ***************************************************************************
; Intro_teardown -- everything back as before the start.
;
; Repeatable (emergency exit, AMIGA_NOTAUS.S): each step only if its flag
; is set, and clears it.  In the emergency exit without GEMDOS.
; ***************************************************************************
Intro_teardown:
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
	move.l	Old_level3,VEK_LEVEL3.w
	move.l	Old_trap0,VEK_TRAP0.w
	move.l	Old_trap8,VEK_TRAP8.w
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

NOTAUS_ABRAEUMEN	equ	Intro_teardown
	include	"AMIGA_NOTAUS.S"

; ***************************************************************************
; The library: exec and graphics, as far as Thalion's frame calls them
; (docs/11, 4.2: OpenLibrary, CloseLibrary, Supervisor, LoadView,
; WaitTOF).  Per library a table of jmp instructions below the base, as on
; the Amiga; the fields above it are 0 (AttnFlags 0: no 68010+, Thalion
; takes VBR 0; ActiView and copinit 0).  Any other entry lands in
; Library_missing and is counted.
; ***************************************************************************
EXEC_ENTRIES	equ	92		; down to -552 (OpenLibrary)
GFX_ENTRIES	equ	45		; down to -270 (WaitTOF)

Library_setup:
	move.l	#Exec_base,Exec_zeiger
	lea	Exec_base,a0
	moveq	#EXEC_ENTRIES,d0
	bsr.b	.empty
	lea	Gfx_base,a0
	moveq	#GFX_ENTRIES,d0
	bsr.b	.empty
	lea	Exec_base,a0
	lea	-552(a0),a1
	move.l	#Exec_openlibrary,d0
	bsr.b	.jmp
	lea	-414(a0),a1
	move.l	#Exec_closelibrary,d0
	bsr.b	.jmp
	lea	-30(a0),a1
	move.l	#Exec_supervisor,d0
	bsr.b	.jmp
	lea	Gfx_base,a0
	lea	-222(a0),a1
	move.l	#Gfx_loadview,d0
	bsr.b	.jmp
	lea	-270(a0),a1
	move.l	#Gfx_waittof,d0
.jmp:	move.w	#$4EF9,(a1)+		; jmp abs.l
	move.l	d0,(a1)
	rts
; d0 entries below a0: jsr Library_missing
.empty:	subq.w	#1,d0
.e:	subq.l	#6,a0
	move.w	#$4EB9,(a0)		; jsr abs.l
	move.l	#Library_missing,2(a0)
	dbf	d0,.e
	rts

Library_missing:
	addq.l	#4,sp
	addq.w	#1,Library_missed
	moveq	#0,d0
	rts

; OpenLibrary(a1 = name, d0 = version) -> d0 = base.  Thalion opens only
; graphics.library.
Exec_openlibrary:
	move.l	#Gfx_base,d0
	rts

Exec_closelibrary:
Gfx_loadview:
	rts

; Supervisor(a5 = routine): the routine ends with rte.  We are in the
; supervisor already; the exception frame for its rte is built here (68000
; frame: the ST family has no 68010+).
Exec_supervisor:
	move.w	sr,-(sp)
	jmp	(a5)

; WaitTOF: until the next VBL.
Gfx_waittof:
	move.l	d0,-(sp)
	move.l	Vbl_count,d0
.w:	cmp.l	Vbl_count,d0
	beq.b	.w
	move.l	(sp)+,d0
	rts

; ***************************************************************************
; K2_trap -- trap #8 where Thalion writes BLTSIZE (K2).  The stacked PC is
; behind the trap; K2_tabelle names the first word of the original
; instruction:
;   $3D7C  move.w #imm,$58(a6)   value behind the trap, then the distance
;   $3D4n  move.w Dn,$58(a6)     value in Dn, then the distance
;   $3A8n  move.w Dn,(a5)        value in Dn
; The PC is set behind the original instruction.  A place not in the table
; does no blit and is counted in K2_unknown.
; ***************************************************************************
K2_trap:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	15*4+2(sp),d0		; PC behind the trap
	lea	K2_tabelle,a0
.find:	move.l	(a0)+,d1
	beq.b	.unknown
	move.w	(a0)+,d2
	cmp.l	d0,d1
	bne.b	.find
	move.l	d0,a1
	cmp.w	#$3D7C,d2
	bne.b	.dn
	move.w	(a1),d4			; #imm
	addq.l	#4,d0
	bra.b	.write
.dn:	move.w	d2,d3			; Dn from the saved registers
	and.w	#7,d3
	lsl.w	#2,d3
	move.w	2(sp,d3.w),d4
	and.w	#$FFF8,d2
	cmp.w	#$3D40,d2
	bne.b	.write
	addq.l	#2,d0			; the distance $0058
.write:
	move.l	d0,15*4+2(sp)
	move.w	d4,Amiga_register+AR_BLTSIZE
	ifd	ABSTURZTEST
	bsr	Absturz_pruefen		; Thalion's flow calls K2 all the time
	endc
	bsr	Amiga_blit
	movem.l	(sp)+,d0-d7/a0-a6
	rte
.unknown:
	addq.w	#1,K2_unknown
	movem.l	(sp)+,d0-d7/a0-a6
	rte

; ***************************************************************************
; Mouse_vector -- mouse vector (Kbdvbase+16), a0 = IKBD packet.  Header
; $F8-$FB: bit 1 left, bit 0 right; then dx, dy.  To the Amiga side:
;   CIA-A port A bit 6 = left button (0 = down)
;   POTGOR bit 10      = right button (0 = down)
;   JOY0DAT            = counters, y in the high, x in the low byte
; ***************************************************************************
Mouse_vector:
	move.b	(a0),d0
	move.b	#$FF,d1
	btst	#1,d0
	beq.b	.l
	bclr	#6,d1
.l:	move.b	d1,Amiga_cia_a
	move.w	#$FF00,d1
	btst	#0,d0
	beq.b	.r
	bclr	#10,d1
.r:	move.w	d1,Amiga_register+AR_POTGOR
	lea	Amiga_register+AR_JOY0DAT,a1
	move.b	2(a0),d0
	add.b	d0,(a1)			; y
	move.b	1(a0),d0
	add.b	d0,1(a1)		; x
	rts

; ***************************************************************************
; Vbl -- the VBL ($70).  Colours and Timer B for this frame, then Thalion's
; VBL ($6C, ends with rte).  Thalion's VBL calls the display at its end
; (Vbl_end_hook), so stars, colours and pointer show in the frame Thalion
; wrote them for.  Before Thalion puts its VBL there, the display runs
; from here.
;
; Timer B as in tools/st_rand/untrand.s: the pending bit goes before the
; enable, or an event latched last frame fires at once.  TBDR n fires at
; the end of line n-1: Tb_border at the end of line ST_BORDER-LEAD.
;
; TOS's VBL no longer runs; we count _frclock ourselves, because TOS waits
; for it, after bombs even before the emergency exit (T16).
;
; Frame_base: the Shifter reloads the video counter from the base registers
; a few lines before the VBL, and it stands still until the first line is
; fetched.  So the counter read here is the base this frame shows, whatever
; Base_set writes later in the frame (finding 245).
; ***************************************************************************
Vbl:
	movem.l	d0-d7/a0-a1,-(sp)
	lea	VID_CNT.w,a0
	movep.l	-2(a0),d0		; base mid, then counter hi, mid, lo
	and.l	#$00FFFFFF,d0
	move.l	d0,Frame_base
	addq.l	#1,FRCLOCK.w
	addq.l	#1,Vbl_count
	ifd	ABSTURZTEST
	addq.l	#1,Absturz_zaehler
	endc
	clr.b	MFP_TBCR.w
	move.l	#Tb_border,VEK_TIMERB.w
	move.b	#ST_BORDER-LEAD+1,MFP_TBDR.w
	bclr	#0,MFP_IPRA.w
	bclr	#0,MFP_ISRA.w
	bset	#0,MFP_IERA.w
	bset	#0,MFP_IMRA.w
	move.b	#TB_EVENT_COUNT,MFP_TBCR.w
	movem.l	St_palette,d0-d7	; prepared by the last display
	movem.l	d0-d7,ST_PAL.w
	ifd	SCREEN_DUMP
	bsr	Dump_key		; DUMP_ST.S
	endc
	movem.l	(sp)+,d0-d7/a0-a1
	cmp.l	#Intro_h0+THALION_VBL,VEK_LEVEL3.w
	beq.b	.thalion		; display at the end of Thalion's VBL
	movem.l	d0-d7/a0-a6,-(sp)
	bsr	Display_update
	movem.l	(sp)+,d0-d7/a0-a6
.thalion:
	move.l	VEK_LEVEL3.w,-(sp)
	rts

THALION_VBL	equ	$2522		; Thalion's level-3 handler

; ***************************************************************************
; Vbl_end_hook -- K3 at $2824, the end of Thalion's VBL, where all its paths
; meet.  Thalion saved all registers; after the display the replaced
; tst.w Intro_h5+$12148, then back into Thalion's VBL.
; ***************************************************************************
Vbl_end_hook:
	bsr	Display_update
	tst.w	Intro_h5+$12148
	jmp	Intro_h0+$282A

; ***************************************************************************
; Intro_switch -- K3 at Thalion's $24BE, the end of $2452 (new copper list,
; 14 callers): the covered move.l d0,Intro_h5+8 and the next instruction
; ($24C4, move.l d0,COP1LC, a K1 site), then the new list shown from the
; next frame on where it shows a target screen (Display_switch).  Its rts
; stands for Thalion's rts at $24CA.  As the Falcon's Intro_umschalten.
; ***************************************************************************
Intro_switch:
	move.l	d0,Intro_h5+8
	move.l	d0,Amiga_register+AR_COP1LC
	bra	Display_switch

; ***************************************************************************
; The four-plane scenes in the target format (TARGET_ST.S; the same places
; and the same method as the Falcon's intro/INTRO_SUP.S, docs/11 7.8 and
; docs/05c-ST.md).  Thalion's screens there are 6:$C0 and 6:$C0+37760, four
; planes, 160 bytes a row ($42E): 236 rows in the space scene and Twinlake,
; 200 in the meteor scene ($AD4).  From $4F4 (the star list is built) to
; $D00 (the clouds before the menu) they are in Screen_table, and the
; Shifter shows them directly.  Thalion's blits find their way themselves
; (Blit_redirect).  Thalion's CPU writing goes through K3
; (tools/intro_st_program.py):
;   - every frame our routine writes the target: clear ($294E), star
;     picture ($1A42), city picture ($776, $B40), Twinlake's animation
;     ($169C), copy shown -> hidden ($12C0), the zoom (ZOOM_ST.S);
;   - once a scene Thalion's code writes the buffer between Screen_before
;     and Screen_after: the city's text ($7BA), Twinlake's picture ($994 to
;     $A36);
;   - reading: a picture back as mask ($6EE), after Screen_before.
; Outside the table each routine takes Thalion's way.
; ***************************************************************************
SPACE_ROW	equ	AMIGA_LINE	; Thalion's bytes a row in these scenes
; Thalion's list holds one entry per non-zero word of plane 0 in rows
; 0-199 ($4C2-$4F4), so its length depends on the picture (146 with the
; shipped data; it runs past 5:$4FE, Thalion's own layout).  The Falcon's
; STERNE_MAX of 128 cut the last 18 stars (CHECK_TARGET, 2026-10-25); the
; bound here is the most the loop can find.
STARS_MAX	equ	200*AMIGA_ROW/2

; Space_begin -- K3 at $4F4: Thalion has built the star list (5:$3B0) from
; the star picture ($4BC).  Our list for the target, then the table.
; Covered: move.w d2,(a2); moveq #20,d7; the first word of bsr $1250.
Space_begin:
	SCENE	3
	move.w	d2,(a2)
	bsr	Stars_convert
	move.l	a0,-(sp)
	lea	Screens_space,a0
	bsr	Screens_switch
	move.l	(sp)+,a0
	moveq	#20,d7
	jsr	Intro_h0+$1250		; its flags hold at $4FC
	jmp	Intro_h0+$4FC

; Meteor_begin -- K3 at $AD4: the meteor scene shows 200 rows; its table
; ends there, so the lines below are black.  The picture is held first:
; the table comes before Thalion writes the 200-row window ($289A), and a
; VBL between them would see the old 236-row window against the new table
; and convert (the Falcon's fourth hold, docs/11 7.8b).  Covered: move.w
; #200,d0; moveq #4,d1.
Meteor_begin:
	SCENE	4
	bsr	Display_hold
	move.l	a0,-(sp)
	lea	Screens_meteor,a0
	bsr	Screens_switch
	move.l	(sp)+,a0
	move.w	#200,d0
	moveq	#4,d1
	jmp	Intro_h0+$ADA

; Clouds_begin -- K3 at $D00, where every way to the clouds and the menu
; passes (also the click): hold the picture, then the clouds' screens 6:$C0
; and +40960, 320 x 256 x 4 ($D10), into the table.  Covered: move.w
; #256,d0; moveq #4,d1.
Clouds_begin:
	SCENE	5
	sf	Menu_st_ready		; Thalion unpacks the menu picture anew
	move.l	a0,-(sp)
	bsr	Display_hold
	lea	Screens_clouds,a0
	bsr	Screens_switch
	move.l	(sp)+,a0
	move.w	#256,d0
	moveq	#4,d1
	jmp	Intro_h0+$D06

; Stars_convert -- Thalion's star list (count, then per star the distance
; to the last one in bytes and the word for plane 0) into Target_stars: per
; star the offset in the target screen and the word.
Stars_convert:
	movem.l	d0-d3/d7/a0-a1,-(sp)
	lea	Intro_h5+$3B0,a0
	lea	Target_stars,a1
	move.w	(a0)+,d7
	cmp.w	#STARS_MAX,d7
	bls.b	.count
	move.w	#STARS_MAX,d7
.count:	move.w	d7,(a1)+
	moveq	#0,d1			; Thalion's offset
	bra.b	.n
.s:	add.w	(a0)+,d1
	moveq	#0,d0
	move.w	d1,d0
	divu	#SPACE_ROW,d0		; row : byte in the row
	moveq	#0,d2
	swap	d0
	move.w	d0,d2
	clr.w	d0
	swap	d0
	mulu	#ST_LINE,d0
	divu	#AMIGA_ROW,d2		; plane : byte in the plane
	move.w	d2,d3
	add.w	d3,d3			; plane * 2
	add.w	d3,d0
	swap	d2
	lsr.w	#1,d2
	lsl.w	#3,d2			; 8 bytes a group
	add.w	d2,d0
	move.w	d0,(a1)+
	move.w	(a0)+,(a1)+
.n:	dbf	d7,.s
	movem.l	(sp)+,d0-d3/d7/a0-a1
	rts

; Stars_set -- K3 at $1A42, Thalion's star picture: the words into the
; target.  Covered: movea.l Intro_h5+$18,a1.
Stars_set:
	movem.l	d0-d2/a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Screen_find
	beq.b	.thalion
	ifd	CHECK_TARGET
	moveq	#0,d0
	move.w	#200,d1
	bsr	Check_rows
	st	Blit_no_redirect
	pea	.back
	move.l	Intro_h5+$18,a1
	jmp	Intro_h0+$1A48
.back:	sf	Blit_no_redirect
	move.l	Intro_h5+$18,d0
	bsr	Screen_find
	endc
	move.l	SC_TARGET(a5),a1
	lea	Target_stars,a0
	move.w	(a0)+,d7
	bra.b	.n
.s:	move.w	(a0)+,d0
	move.w	(a0)+,0(a1,d0.w)
.n:	dbf	d7,.s
	moveq	#0,d0
	move.w	#200,d1
	ifd	CHECK_TARGET
	moveq	#CT_STARS,d2
	bsr	Rows_compare
	subq.w	#1,Target_busy
	else
	bsr	Rows_invalid
	endc
	movem.l	(sp)+,d0-d2/a5
	rts
.thalion:
	movem.l	(sp)+,d0-d2/a5
	move.l	Intro_h5+$18,a1
	jmp	Intro_h0+$1A48

; Space_clear -- K3 at $294E in Thalion's $2940 (clear rows 0-199 of the
; screen Intro_h5+$18 as four planes of 160 bytes; also used for the logo
; stages, $14E6, now on Logo_scratch): the target.  a6 is Amiga_register
; (Thalion's lea at $2940).  Covered: move.l Intro_h5+$18,$54(a6) (the
; first 6 of 8 bytes).
Space_clear:
	movem.l	d0-d2/a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Screen_find
	beq.b	.thalion
	cmp.w	#4,SC_PLANES(a5)
	bne.b	.thalion		; Thalion's blit finds its way
	moveq	#0,d0
	move.w	#200,d1
	ifd	CHECK_TARGET
	bsr	Check_rows
	st	Blit_no_redirect
	movem.l	d0-d7/a0-a6,-(sp)
	pea	.back
	move.l	Intro_h5+$18,$54(a6)
	jmp	Intro_h0+$2956
.back:	movem.l	(sp)+,d0-d7/a0-a6
	sf	Blit_no_redirect
	endc
	bsr	Target_clear
	ifd	CHECK_TARGET
	moveq	#CT_CLEAR,d2
	bsr	Rows_compare
	subq.w	#1,Target_busy
	endc
	movem.l	(sp)+,d0-d2/a5
	rts
.thalion:
	movem.l	(sp)+,d0-d2/a5
	move.l	Intro_h5+$18,$54(a6)
	jmp	Intro_h0+$2956

; City_space / City_meteor -- K3 at $776 and $B40: Thalion copies the city
; picture (a0) into the screen Intro_h5+$18.  Covered: movea.l
; Intro_h5+$18,a1.
City_space:
	bsr.b	City_target
	beq.b	.thalion
	jmp	Intro_h0+$796
.thalion:
	move.l	Intro_h5+$18,a1
	jmp	Intro_h0+$77C
City_meteor:
	bsr.b	City_target
	beq.b	.thalion
	jmp	Intro_h0+$B72
.thalion:
	move.l	Intro_h5+$18,a1
	jmp	Intro_h0+$B46

; City_target -- the city picture a0 (128 rows, per row four planes of 20
; bytes) into the target at Thalion's place +5770 (row 36, word 5).  Z set:
; the screen is not in the table, nothing done.  Otherwise Z clear and a0
; behind the picture.  Changes d0-d1/d7/a1.
CITY_ROW	macro			; one row: 4 planes of 10 words
.p	set	0
	rept	4
.w	set	0
	rept	10
	move.w	(a0)+,.p*2+.w*8(a1)
.w	set	.w+1
	endr
.p	set	.p+1
	endr
	endm

City_target:
	move.l	a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Screen_find
	beq	.out
	addq.w	#1,Target_busy		; rows written, not yet invalid
	move.l	SC_TARGET(a5),a1
	add.l	#36*ST_LINE+5*8,a1
	moveq	#128-1,d7
.row:	CITY_ROW
	lea	ST_LINE(a1),a1
	dbf	d7,.row
	moveq	#36,d0
	move.w	#128,d1
	bsr	Rows_invalid
	subq.w	#1,Target_busy
	moveq	#1,d0			; Z clear
.out:	move.l	(sp)+,a5
	rts

; City_text -- K3 at $7BA: Thalion's text (big font, $2ADA) into the city
; picture, once a city.  Covered: bsr $2ADA, the first word of bsr $240E.
City_text:
	move.l	d0,-(sp)
	move.l	Intro_h5+$18,d0
	addq.w	#1,Target_busy
	bsr	Screen_before
	move.l	(sp)+,d0
	jsr	Intro_h0+$2ADA
	move.l	Intro_h5+$18,d0
	bsr	Screen_after
	subq.w	#1,Target_busy
	jsr	Intro_h0+$240E
	jmp	Intro_h0+$7C2

; Picture_fetch -- K3 at $6EE: Thalion takes a piece of the screen back as
; mask and planes ($15A6); it reads the buffer.  Covered: bsr $15A6;
; move.w #-1,(a1)+.
Picture_fetch:
	move.l	d0,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Screen_before
	move.l	(sp)+,d0
	jsr	Intro_h0+$15A6
	move.w	#-1,(a1)+
	jmp	Intro_h0+$6F6

; Twinlake_before / Twinlake_after -- K3 at $994 and $A36: between them
; Thalion copies Twinlake's picture into both screens, clears the rows
; below and writes the text, all with the CPU.  Covered at $994: movea.l
; Intro_h5+$12206,a0; at $A36: bsr $165E, the first word of bsr $240E.
Twinlake_before:
	bsr	All_ensure
	addq.w	#1,Target_busy
	move.l	Intro_h5+$12206,a0
	jmp	Intro_h0+$99A
Twinlake_after:
	bsr	All_bring
	subq.w	#1,Target_busy
	jsr	Intro_h0+$165E
	jsr	Intro_h0+$240E
	jmp	Intro_h0+$A3E

; Anim_eor -- K3 at $169C in Thalion's $165E: the unpacked frame (5:$12206)
; EOR into the screen Intro_h5+$18, rows 7-183, bytes 4-35 of each plane.
; Per row a mask of 32 bits, one per byte; a set bit takes four bytes, one
; per plane.  Covered: movea.l Intro_h5+$12206,a0.
Anim_eor:
	move.l	a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Screen_find
	beq	.thalion
	ifd	CHECK_TARGET
	moveq	#7,d0
	move.w	#177,d1
	bsr	Check_rows
	st	Blit_no_redirect
	pea	.back
	move.l	Intro_h5+$12206,a0
	jmp	Intro_h0+$16A2
.back:	sf	Blit_no_redirect
	move.l	Intro_h5+$18,d0
	bsr	Screen_find
	endc
	move.l	Intro_h5+$12206,a0
	move.l	SC_TARGET(a5),a1
	add.l	#7*ST_LINE+2*8,a1
	move.w	#177-1,d7
.row:	move.l	(a0)+,d0
	beq.b	.next
	move.l	a1,a2
.word:	add.l	d0,d0			; high byte of the word
	bcc.b	.lo
	move.b	(a0)+,d1
	eor.b	d1,(a2)
	move.b	(a0)+,d1
	eor.b	d1,2(a2)
	move.b	(a0)+,d1
	eor.b	d1,4(a2)
	move.b	(a0)+,d1
	eor.b	d1,6(a2)
.lo:	add.l	d0,d0			; low byte
	bcc.b	.n
	move.b	(a0)+,d1
	eor.b	d1,1(a2)
	move.b	(a0)+,d1
	eor.b	d1,3(a2)
	move.b	(a0)+,d1
	eor.b	d1,5(a2)
	move.b	(a0)+,d1
	eor.b	d1,7(a2)
.n:	addq.l	#8,a2
	tst.l	d0
	bne.b	.word			; the rest of the row is unchanged
.next:	lea	ST_LINE(a1),a1
	dbf	d7,.row
	moveq	#7,d0
	move.w	#177,d1
	ifd	CHECK_TARGET
	moveq	#CT_EOR,d2
	bsr	Rows_compare
	subq.w	#1,Target_busy
	else
	bsr	Rows_invalid
	endc
	move.l	(sp)+,a5
	rts
.thalion:
	move.l	(sp)+,a5
	move.l	Intro_h5+$12206,a0
	jmp	Intro_h0+$16A2

; Copy_shown_hidden -- K3 at $12C0: Thalion copies rows 7-183, bytes 4-35
; of each plane, from the shown screen into the hidden one (blit $1306).
; Both in the table: target to target, planes 0-3, 128 bytes a row.
; Covered: movea.l Intro_h5+$20,a0.
Copy_shown_hidden:
	move.l	a5,-(sp)
	move.l	Intro_h5+$20,d0
	bsr	Screen_find
	beq	.thalion
	move.l	a5,a4			; the shown one
	move.l	Intro_h5+$1C,d0
	bsr	Screen_find
	beq	.thalion
	ifd	CHECK_TARGET
	exg	a4,a5
	moveq	#7,d0
	move.w	#177,d1
	bsr	Rows_ensure		; Thalion's blit reads it
	exg	a4,a5
	bsr	Check_rows
	st	Blit_no_redirect
	movem.l	a4-a5,-(sp)
	pea	.back
	move.l	Intro_h5+$20,a0
	jmp	Intro_h0+$12C6
.back:	movem.l	(sp)+,a4-a5
	sf	Blit_no_redirect
	endc
	move.l	SC_TARGET(a4),a0
	move.l	SC_TARGET(a5),a1
	move.l	#7*ST_LINE+2*8,d0
	add.l	d0,a0
	add.l	d0,a1
	move.w	#177-1,d7
	movem.l	d2-d6/a2-a3/a6,-(sp)
.row:	movem.l	(a0)+,d0-d6/a2		; 4 x 32 bytes
	movem.l	d0-d6/a2,(a1)
	movem.l	(a0)+,d0-d6/a2
	movem.l	d0-d6/a2,32(a1)
	movem.l	(a0)+,d0-d6/a2
	movem.l	d0-d6/a2,64(a1)
	movem.l	(a0)+,d0-d6/a2
	movem.l	d0-d6/a2,96(a1)
	lea	ST_LINE-128(a0),a0
	lea	ST_LINE(a1),a1
	dbf	d7,.row
	movem.l	(sp)+,d2-d6/a2-a3/a6
	moveq	#7,d0
	move.w	#177,d1
	ifd	CHECK_TARGET
	moveq	#CT_COPY,d2
	bsr	Rows_compare
	subq.w	#1,Target_busy
	else
	bsr	Rows_invalid
	endc
	lea	Amiga_register,a6	; as Thalion's routine leaves it
	move.l	(sp)+,a5
	rts
.thalion:
	move.l	(sp)+,a5
	move.l	Intro_h5+$20,a0
	jmp	Intro_h0+$12C6

; ***************************************************************************
; The logo phase, the clouds and the menu in the target format (E30, docs/11
; 7.8b, docs/05c-ST.md "The intro without live conversion"): the intro
; without live conversion.  Each scene has its table (Screens_logo,
; Screens_clouds, Screens_menu) and the Shifter shows it directly; the
; blits find their way into the target themselves (Blit_redirect: the logo
; stages $F0 and the clouds $CA straight, the text through the buffer).
; Where Thalion changes the format of the screens with the CPU (logo ->
; space at $3C0, any scene -> clouds at $D00, clouds -> menu at $F4E),
; Display_hold keeps the last picture until the next table shows.  The
; places and names are the Falcon's (intro/INTRO_SUP.S); the ST's own:
; Zoom_clear (the Falcon's Zoom_loeschen) and the stars in a register.
; ***************************************************************************

; Logo_begin -- K3 at $1E0 (start, and restart from the menu's INTRO): the
; logo screens 6:$C0 and +40000, 320 x 200 x 5 ($1A4), into the table
; before the first copper list ($200).  The stars in register 1 (THALION;
; Zoom_clear).  Covered: addi.l #880,d0.
Logo_begin:
	SCENE	1
	add.l	#880,d0
	movem.l	d0/a0,-(sp)
	bsr	Display_hold
	move.w	#1,Overlay_register
	lea	Screens_logo,a0
	bsr	Screens_switch
	movem.l	(sp)+,d0/a0
	jmp	Intro_h0+$1E6

; Logo_clear -- K3 at $21E: Thalion clears both screens with the CPU; we
; clear both targets.  Covered: movea.l Intro_h5+$1C,a0.
Logo_clear:
	move.l	a5,-(sp)
	move.l	Intro_h5+$1C,d0
	bsr	Screen_find
	beq.b	.thalion
	move.l	a5,a4
	move.l	Intro_h5+$20,d0
	bsr	Screen_find
	beq.b	.thalion
	bsr	Shown_enter
	moveq	#0,d0
	move.w	SC_ROWS(a5),d1
	bsr	Target_clear
	move.l	a4,a5
	move.w	SC_ROWS(a5),d1
	bsr	Target_clear
	bsr	Shown_leave
	move.l	(sp)+,a5
	moveq	#0,d0			; as Thalion's loop leaves them
	moveq	#-1,d7
	jmp	Intro_h0+$23C
.thalion:
	move.l	(sp)+,a5
	move.l	Intro_h5+$1C,a0
	jmp	Intro_h0+$224

; Zoom_clear -- K3 at $137E, the whole routine (before each logo zoom,
; $131A, and after the last, $3A0): Thalion fills planes 0-3 of both
; screens with 0 (the pattern at 5:$12182, never written); the stars in
; plane 4 stay.  Both targets to 0, their stars drawn again.  The register
; of the stars by the logo coming: the zoom loop takes its palette from
; 5:$121C2 next ($131E); AMBERMOON's (1:$40) leaves 13 and 14 unused, so
; its stars take 13 and the logo keeps all its colours; THALION's uses
; all 16, register 1 on 8 pixels only (docs/05c, docs/17 D3).  Registers
; as free as in Thalion's routine (d0-d7/a0-a4).  Covered: movea.l
; Intro_h5+$1C,a0.
Zoom_clear:
	moveq	#1,d0
	cmp.l	#Intro_h1+$40,Intro_h5+$121C2
	bne.b	.reg
	moveq	#13,d0
.reg:	move.w	d0,Overlay_register
	move.l	a5,-(sp)
	move.l	Intro_h5+$1C,d0
	bsr	Screen_find
	beq.b	.thalion
	move.l	a5,a4
	move.l	Intro_h5+$20,d0
	bsr	Screen_find
	beq.b	.thalion
	bsr	Shown_enter
	bsr.b	.planes
	move.l	a4,a5
	bsr.b	.planes
	bsr	Shown_leave
	move.l	(sp)+,a5
	rts
; planes 0-3 of the target a5 to 0, its stars again
.planes:
	moveq	#0,d0
	move.w	SC_ROWS(a5),d1
	bsr	Rows_invalid		; first: the VBL's check sees no valid row
	move.l	SC_TARGET(a5),a0	; written
	bsr	Lines_zero
	bra	Stars_redraw
.thalion:
	move.l	(sp)+,a5
	move.l	Intro_h5+$1C,a0
	jmp	Intro_h0+$1384

; Logo_stages -- K3 at $14E6, the start of Thalion's precomputation of the
; logo stages: Thalion clears the drawing screen ($2940), zooms the logo
; into it ($1BAE) and reads it back ($1560), each as four planes of 160
; bytes, a scratch use of the hidden screen.  We give it a scratch screen
; of its own (Logo_scratch), so the hidden screen stays a five-plane
; target (the Falcon's finding).  Covered: bsr $2940, the first word of
; movea.l Intro_h5+$12206,a1.
Logo_stages:
	move.l	Intro_h5+$18,-(sp)
	move.l	#Logo_scratch,Intro_h5+$18
	jsr	Intro_h0+$2940
	move.l	Intro_h5+$12206,a1
	jsr	Intro_h0+$14F0		; the rest of Thalion's routine
	move.l	(sp)+,Intro_h5+$18
	rts

; Logo_stars -- K3 at $2646 in Thalion's VBL, while the stars run (5:$2A):
; Thalion clears plane 4 of the shown screen ($29B2) and sets 150 stars
; there ($1AF2).  The shown screen in the table: the stars it set last
; time back to 0, then Thalion's walk ($1AF2: its track pointers at 5:$2C
; advance as there) into the target: Thalion's offset is row * 200 + byte
; of plane 0, the bit in the byte, its group in the target from
; Star_offsets (a divu here took 12 % of the logo phase in Hatari); a
; star goes into Overlay_register where
; planes 0-3 are 0 (behind the logo it stays hidden, as on the Amiga) and
; into the screen's list (TARGET_ST.S).  While the main flow writes the
; target shown (Shown_busy) the walk only advances.  Thalion saved all
; registers ($2528).  Covered: move.l Intro_h5+$18,-(sp).
Logo_stars:
	move.l	Intro_h5+$20,d0
	bsr	Screen_find
	beq	.thalion
	cmp.w	#MODE_STARS,SC_MODE(a5)
	bne	.thalion
	lea	Intro_h5+$2C,a4		; Thalion's track pointers
	move.w	#LOGO_STARS-1,d7
	tst.w	Shown_busy
	bne	.walk
	move.l	SC_STARS(a5),a3
	move.l	a3,d3			; the list
	move.w	(a3)+,d6		; the stars of last time out
	bra.b	.en
.e:	move.l	(a3)+,a0
	move.w	(a3)+,d0
	addq.l	#2,a3
	not.w	d0
	and.w	d0,(a0)+
	and.w	d0,(a0)+
	and.w	d0,(a0)+
	and.w	d0,(a0)+
.en:	dbf	d6,.e
	bsr	Star_or_routine		; a2
	move.l	d3,a3
	addq.l	#2,a3			; the new list
	moveq	#0,d6
	move.l	SC_TARGET(a5),a6
	lea	Star_offsets,a5
.s:	move.l	(a4),a0
	move.w	(a0)+,d0		; bit in the byte
	bpl.b	.da
	move.l	(a0)+,a0		; end of the track: from its start
	move.w	(a0)+,d0
.da:	moveq	#0,d1
	move.w	(a0)+,d1		; row * 200 + byte of plane 0
	move.l	a0,(a4)+
	btst	#0,d1
	bne.b	.lo
	addq.w	#8,d0			; even byte: the high byte of the word
.lo:	moveq	#0,d4
	bset	d0,d4			; the pixel
	and.w	#-2,d1			; Thalion's offset of the word
	move.w	0(a5,d1.l),d5		; its group in the target
	lea	0(a6,d5.w),a1
	move.w	(a1),d5
	or.w	2(a1),d5
	or.w	4(a1),d5
	or.w	6(a1),d5
	and.w	d4,d5
	bne.b	.next			; behind the logo, or a star there already
	move.l	a1,(a3)+
	move.w	d4,(a3)+
	move.w	d1,(a3)+
	addq.w	#1,d6
	jsr	(a2)
.next:	dbf	d7,.s
	move.l	d3,a0
	move.w	d6,(a0)
	jmp	Intro_h0+$2664
.walk:	move.l	(a4),a0
	tst.w	(a0)+
	bpl.b	.w2
	move.l	(a0)+,a0
	addq.l	#2,a0
.w2:	addq.l	#2,a0
	move.l	a0,(a4)+
	dbf	d7,.walk
	jmp	Intro_h0+$2664
.thalion:
	move.l	Intro_h5+$18,-(sp)
	jmp	Intro_h0+$264C

; Presents_row -- K3 at $310, a row of Thalion's PRESENTS wipe ($2FC-
; $324): 40 bytes (a0) into plane 0 of a row of the shown screen (a1).  Into
; the buffer as Thalion does, and into the target, the row's stars out
; first (a star behind a letter is hidden; the next VBL sets them anew).
; Covered: moveq #9,d0; move.l (a0)+,(a1)+; the first word of dbf d0.
Presents_row:
	movem.l	d1-d3/a2-a3/a5,-(sp)
	move.l	a1,d0
	bsr	Screen_find
	beq.b	.buffer
	bsr	Shown_enter
	move.l	a1,d1
	sub.l	SC_AMIGA(a5),d1
	divu	SC_LINE(a5),d1		; row : byte in the row
	move.w	d1,d0			; row
	swap	d1
	moveq	#0,d2
	move.w	d1,d2
	divu	#AMIGA_ROW,d2		; plane : byte in the plane
	moveq	#1,d1
	bsr	Stars_remove
	mulu	#ST_LINE,d0
	move.l	SC_TARGET(a5),a3
	add.l	d0,a3
	move.w	d2,d3
	add.w	d3,d3			; plane * 2
	add.w	d3,a3
	swap	d2
	lsr.w	#1,d2
	lsl.w	#3,d2
	add.w	d2,a3			; + group * 8
	move.l	a0,a2
	moveq	#AMIGA_ROW/2-1,d3
.z:	move.w	(a2)+,(a3)
	addq.l	#8,a3
	dbf	d3,.z
	bsr	Shown_leave
.buffer:
	moveq	#10-1,d3
.p:	move.l	(a0)+,(a1)+
	dbf	d3,.p
	movem.l	(sp)+,d1-d3/a2-a3/a5
	move.l	#$FFFF,d0		; as Thalion's dbf leaves it
	jmp	Intro_h0+$318

; Logo_end -- K3 at $3C0: the stars stand still ($3B6), and Thalion turns
; the shown picture into the space scene's first one with the CPU ($3C0-
; $4BC: copy, 5 -> 4 planes, the star list from plane 4).  The stars live
; only in the target: the shown screen's rows into its buffer and its stars
; into plane 4 there, then hold the picture (no table) until Space_begin
; ($4F4) brings the space scene's.  Covered: movea.l Intro_h5+$20,a0.
Logo_end:
	SCENE	2
	move.l	a5,-(sp)
	move.l	Intro_h5+$20,d0
	bsr	Screen_find
	beq.b	.hold
	cmp.w	#MODE_STARS,SC_MODE(a5)
	bne.b	.hold
	moveq	#0,d0
	move.w	SC_ROWS(a5),d1
	bsr	Rows_ensure
	bsr	Stars_buffer
.hold:	bsr	Display_hold
	move.l	(sp)+,a5
	move.l	Intro_h5+$20,a0
	jmp	Intro_h0+$3C6

; Clouds_background -- K3 at $D74 (the click: no clouds): Thalion copies the
; unpacked menu picture into both screens with the CPU; then into the
; targets.  Covered: movea.l Intro_h5+$12206,a0.
Clouds_background:
	bsr	Shown_enter
	move.l	Intro_h5+$12206,a0
	move.l	Intro_h5+$1C,a1
	move.l	Intro_h5+$20,a2
	moveq	#-1,d0
	move.w	#10240-1,d7
.k:	move.l	(a0),(a1)+
	move.l	(a0)+,(a2)+
	dbf	d7,.k
	bsr	All_bring
	bsr	Shown_leave
	jmp	Intro_h0+$D94

; Clouds_fill -- K3 at $DA2: Thalion fills both screens with colour 15 with
; the CPU; we fill both targets, and Thalion's rows below them in the
; buffers.  Covered: movea.l Intro_h5+$1C,a1.
Clouds_fill:
	move.l	Intro_h5+$1C,d0
	bsr	Screen_find
	beq.b	.thalion
	move.l	a5,a4
	move.l	Intro_h5+$20,d0
	bsr	Screen_find
	beq.b	.thalion
	bsr	Shown_enter
	moveq	#-1,d2
	bsr.b	.fill
	move.l	a4,a5
	bsr.b	.fill
	bsr	Shown_leave
	moveq	#-1,d0			; as Thalion's loop leaves them
	moveq	#-1,d7
	jmp	Intro_h0+$DBC
.fill:	moveq	#0,d0
	move.w	SC_ROWS(a5),d1
	bsr	Target_fill
	move.l	SC_END(a5),a0
	move.w	SC_ALL(a5),d1
	sub.w	SC_ROWS(a5),d1
	mulu	SC_LINE(a5),d1
	lsr.l	#2,d1
	bra.b	.n
.f:	move.l	d2,(a0)+
.n:	dbf	d1,.f
	rts
.thalion:
	move.l	Intro_h5+$1C,a1
	jmp	Intro_h0+$DA8

; Clouds_column -- K3 at $1270, the whole routine: Thalion reveals the menu
; picture column by column, d2 words from word d0 on, all 256 rows and 4
; planes (one blit of 1024 rows, $F0), from the unpacked picture (5:$12206,
; Thalion's format) into the drawing screen.  In the table: whole groups
; from our copy of the picture in ST format (Menu_st, CLOUDS_ST.S) into the
; target, once the Shifter no longer shows it (Target_free); Thalion's rows
; below it from Thalion's picture into the buffer.  All registers are
; preserved, a6 = Amiga_register as Thalion leaves it.  The four clouds
; after it: Clouds_draw (CLOUDS_ST.S).
; Covered: movea.l Intro_h5+$12206,a0.
Clouds_column:
	movem.l	d0-d7/a0-a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Screen_find
	beq	.thalion
	cmp.w	#4,SC_PLANES(a5)
	bne	.thalion
	bsr	Target_free
	tst.b	Menu_st_ready
	bne.b	.ready
	bsr	Menu_st_convert
.ready:	movem.l	(sp),d0-d2
	subq.w	#1,d2			; words - 1
	bmi	.done
	add.w	d0,d0			; byte of the word in a plane row
	move.w	d0,d3
	lsl.w	#2,d0			; group * 8
	lea	Menu_st,a0
	add.w	d0,a0
	move.l	SC_TARGET(a5),a1
	add.w	d0,a1
	moveq	#0,d0			; invalid first (CHECK_TARGET's VBL)
	move.w	SC_ROWS(a5),d1
	bsr	Rows_invalid
	move.w	SC_ROWS(a5),d7
	subq.w	#1,d7
.row:	move.l	a0,a2
	move.l	a1,a3
	move.w	d2,d6
.w:	move.l	(a2)+,(a3)+
	move.l	(a2)+,(a3)+
	dbf	d6,.w
	lea	ST_LINE(a0),a0
	lea	ST_LINE(a1),a1
	dbf	d7,.row
	move.w	SC_ALL(a5),d7		; plane rows below the target
	sub.w	SC_ROWS(a5),d7
	lsl.w	#2,d7
	subq.w	#1,d7
	bmi.b	.done
	move.l	Intro_h5+$12206,a0
	move.w	SC_ROWS(a5),d0
	mulu	#AMIGA_LINE,d0
	add.l	d0,a0
	add.w	d3,a0
	move.l	SC_END(a5),a1
	add.w	d3,a1
.tail:	move.l	a0,a2
	move.l	a1,a3
	move.w	d2,d6
.t:	move.w	(a2)+,(a3)+
	dbf	d6,.t
	lea	AMIGA_ROW(a0),a0
	lea	AMIGA_ROW(a1),a1
	dbf	d7,.tail
.done:	movem.l	(sp)+,d0-d7/a0-a5
	lea	Amiga_register,a6
	rts
.thalion:
	movem.l	(sp)+,d0-d7/a0-a5
	move.l	Intro_h5+$12206,a0
	jmp	Intro_h0+$1276

; Menu_hold -- K3 at $F4E: the clouds are open, the menu picture is shown.
; Thalion now makes the menu's screens with the CPU ($F6C: 4 -> 5 planes
; into 6:$C8C0, $FB2: copied into 6:$C0): hold the picture.  Covered:
; move.l #Intro_h6+$C8C0,d0.
Menu_hold:
	SCENE	6
	bsr	Display_hold
	move.l	#Intro_h6+$C8C0,d0
	jmp	Intro_h0+$F54

; Menu_begin -- K3 at $FB2: Thalion's copy of the shown menu screen into the
; other one, then both into the table (6:$C8C0 and 6:$C0, 320 x 256 x 5,
; MODE_TEXT, the text in register 1).  From here Thalion's menu draws into
; the shown screen: the entries with the CPU (Menu_texts), the highlight
; by blits.  Covered: movea.l Intro_h5+$20,a0.
Menu_begin:
	SCENE	7
	move.l	Intro_h5+$20,a0
	move.l	Intro_h5+$1C,a1
	move.w	#12800-1,d7
.k:	move.l	(a0)+,(a1)+
	dbf	d7,.k
	move.l	a0,-(sp)
	move.w	#1,Overlay_register
	lea	Screens_menu,a0
	bsr	Screens_switch
	move.l	(sp)+,a0
	jmp	Intro_h0+$FC8

; Menu_texts -- K3 at $1030: Thalion has written the menu's entries into
; plane 4 of the shown screen with the CPU ($FE6-$102C): into the target.
; Covered: lea Intro_h1+$180,a4.
Menu_texts:
	bsr	Shown_enter
	move.l	Intro_h5+$20,d0
	bsr	Screen_after
	bsr	Shown_leave
	lea	Intro_h1+$180,a4
	jmp	Intro_h0+$1036

; ***************************************************************************
; Tb_border -- open the lower border (tools/st_rand/untrand.s tb_bottom, T93),
; the code of fantasy_st/FANTASY_ST.S Tb_border unchanged up to the switch back
; to 50 Hz.  Then the colours Thalion's copper list changes at raster $F4
; (ST line 200, the line after ST_BORDER): Split_colours, prepared by the
; display.
;
; Waits with all interrupts masked until the video counter is SYNC_FROM into
; the picture (line ST_BORDER being fetched), syncs to the cycle (the low
; byte says how far the line is, 2 bytes per 4 cycles; lsl waits the rest),
; DELAY_PRE nops to the end of line ST_BORDER's display, DELAY nops at 60 Hz.
;
; The base is the one the Vbl read for this frame (Frame_base), not a guess
; from the counter: two target screens can overlap by a few lines, and a
; wrong base switched inside a displayed line (finding 245).  When line
; ST_BORDER is already over, nothing is switched: a 60 Hz switch at an
; unsynced place can shorten a line, and every line below shows its planes
; turned (245).  The border then stays shut for this frame.
; ***************************************************************************
Tb_border:
	move.w	#$2700,sr
	movem.l	d0-d5/a0-a1,-(sp)
	clr.b	MFP_TBCR.w		; one border event per frame
	tst.b	Is_mste
	beq.b	.sync
	move.b	MSTE_CLOCK.w,Old_mste_clock
	clr.b	MSTE_CLOCK.w		; 8 MHz, no cache: DELAY in bus cycles
.sync:	lea	VID_CNT+2.w,a0		; mid and low byte, for movep.w
	move.l	Frame_base,d4
	move.w	d4,d3			; base, low word
	move.w	d4,d5			; low byte of line ST_BORDER's start
	add.w	#SYNC_START,d5		; (the STE's base need not be on 256)
	move.w	#WAIT_BORDER-1,d2
.w:	movep.w	0(a0),d0
	sub.w	d3,d0			; offset into the picture
	cmp.w	#SYNC_FROM,d0
	dbcc	d2,.w
	bcs.w	.too_late		; timeout: the border stays shut
	cmp.w	#(ST_BORDER+1)*ST_LINE,d0
	bcc.w	.late			; line ST_BORDER already over: no switch
	moveq	#0,d0
	move.b	2(a0),d0
	sub.b	d5,d0			; bytes into line ST_BORDER
	nop				; with the sub: 8 cycles, as subi.b #,d0
	moveq	#SYNC_K,d1
	sub.w	d0,d1
	bpl.b	.shift
	moveq	#0,d1
.shift:
	lsl.l	d1,d1			; 8+2n cycles: a later read waits less
	rept	DELAY_PRE
	nop
	endr
	clr.b	SYNC_MODE.w		; 60 Hz
	rept	DELAY
	nop
	endr
	move.b	#2,SYNC_MODE.w		; 50 Hz
	bra.b	.done
.late:	addq.l	#1,Border_late
	bra.b	.done
.too_late:
	addq.l	#1,Border_missed
.done:
	tst.b	Is_mste
	beq.b	.split
	move.b	Old_mste_clock,MSTE_CLOCK.w
.split:	move.w	Split_count,d0		; the copper list's colours at line 200
	beq.b	.out
	lea	Split_colours,a0
	lea	ST_PAL.w,a1
	subq.w	#1,d0
.s:	move.w	(a0)+,d1		; register offset
	move.w	(a0)+,0(a1,d1.w)
	dbf	d0,.s
.out:	bclr	#0,MFP_ISRA.w
	movem.l	(sp)+,d0-d5/a0-a1
	rte

	include	"SHOW_ST.S"
	include	"TARGET_ST.S"
	include	"BLIT_ST.S"
	include	"ZOOM_ST.S"
	include	"DUMP_ST.S"
	include	"CLOUDS_ST.S"

; ***************************************************************************
; Data
; ***************************************************************************
	SECTION	Intro_data,data
	ifd	SCENE_LOG
; ***************************************************************************
; Scene log (measuring build, finding 247): each scene hook notes the VBL
; and Border_late (SCENE n); Scenes_write puts them into SCENES.TXT at the
; end, one line "name VBL late" each, so the STE's timeline can be laid
; beside Hatari's (docs/05c-ST.md, "The intro without live conversion:
; built").
; ***************************************************************************
SCENE_MAX	equ	64

; Scene_mark -- one entry for Scene_id.  Changes nothing, flags aside.
Scene_mark:
	movem.l	d0/a0,-(sp)
	move.w	Scene_count,d0
	cmp.w	#SCENE_MAX,d0
	bhs.b	.out
	addq.w	#1,Scene_count
	lsl.w	#3,d0
	lea	Scene_log,a0
	add.w	d0,a0
	move.w	Scene_id,(a0)+
	move.l	Vbl_count,(a0)+
	move.w	Border_late+2,(a0)
.out:	movem.l	(sp)+,d0/a0
	rts

; Scenes_write -- SCENES.TXT from Scene_log; with TOS back.
Scenes_write:
	lea	Scene_text,a1
	lea	Scene_log,a2
	move.w	Scene_count,d3
	bra.b	.next
.entry:	move.w	(a2)+,d0		; the name
	lea	Scene_names,a0
	bra.b	.find
.skip:	tst.b	(a0)+
	bne.b	.skip
.find:	dbf	d0,.skip
.name:	move.b	(a0)+,(a1)+
	bne.b	.name
	move.b	#' ',-1(a1)
	move.l	(a2)+,d0
	bsr	Decimal_put
	move.b	#' ',(a1)+
	moveq	#0,d0
	move.w	(a2)+,d0
	bsr	Decimal_put
	move.b	#13,(a1)+
	move.b	#10,(a1)+
.next:	dbf	d3,.entry
	move.l	a1,d4
	sub.l	#Scene_text,d4
	move.w	#0,-(sp)
	pea	Scene_file
	move.w	#Fcreate,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi.b	.out
	move.w	d0,d7
	pea	Scene_text
	move.l	d4,-(sp)
	move.w	d7,-(sp)
	move.w	#Fwrite,-(sp)
	trap	#1
	lea	12(sp),sp
	move.w	d7,-(sp)
	move.w	#Fclose,-(sp)
	trap	#1
	addq.l	#4,sp
.out:	rts

; Decimal_put -- d0.l (below 655360) as decimal digits at a1+.
;   Changes d0-d2.
Decimal_put:
	moveq	#0,d2			; digits on the stack
.div:	divu	#10,d0
	swap	d0
	move.w	d0,-(sp)
	clr.w	d0
	swap	d0
	addq.w	#1,d2
	tst.l	d0
	bne.b	.div
	subq.w	#1,d2
.put:	move.w	(sp)+,d1
	add.b	#'0',d1
	move.b	d1,(a1)+
	dbf	d2,.put
	rts

Scene_file:	dc.b	"SCENES.TXT",0
Scene_names:	dc.b	"end",0,"logo",0,"logo_end",0,"space",0,"meteors",0
		dc.b	"clouds",0,"menu_hold",0,"menu",0
	even
	SECTION	Intro_bss,bss
Scene_log:	ds.b	8*SCENE_MAX
Scene_text:	ds.b	32*SCENE_MAX
Scene_count:	ds.w	1
Scene_id:	ds.w	1
	SECTION	Intro_code,code
	endc

; The record Thalion's frame gets in a0: the music player, the flag byte
Handover:
	dc.l	Music_silent
	dc.b	0,0
	even
; Thalion's music player: a jump table (+0, +12, +16, +24 seen); each
; entry here is an rts.
Music_silent:
	rept	16
	rts
	endr
; Amiga level 0-15 -> ST level: three bits; STE: four, the lowest on top
Levels_st:
	dc.b	0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7
Levels_ste:
	dc.b	$0,$8,$1,$9,$2,$A,$3,$B,$4,$C,$5,$D,$6,$E,$7,$F
; Screens in the target format (TARGET_ST.S): none at the start; each scene
; brings its table (Screens_switch), room for TARGET_MAX.
Screen_table:
	dcb.b	TARGET_MAX*SC_SIZE+4,0
; the logo phase: 320 x 200 x 5 ($194-$1BC), plane 4 the stars
Screens_logo:
	SCREEN	Intro_h6+$C0,200,5,MODE_STARS
	SCREEN	Intro_h6+$C0+40000,200,5,MODE_STARS
	dc.l	0
; Thalion's screens of the space scene and Twinlake ($42E): 320 x 236 x 4
Screens_space:
	SCREEN	Intro_h6+$C0,236,4,MODE_FOUR
	SCREEN	Intro_h6+$C0+37760,236,4,MODE_FOUR
	dc.l	0
; the same in the meteor scene, which shows 200 rows ($AD4)
Screens_meteor:
	SCREEN	Intro_h6+$C0,200,4,MODE_FOUR
	SCREEN	Intro_h6+$C0+37760,200,4,MODE_FOUR
	dc.l	0
; the clouds before the menu: 320 x 256 x 4 ($D06-$D28)
Screens_clouds:
	SCREEN	Intro_h6+$C0,256,4,MODE_FOUR
	SCREEN	Intro_h6+$C0+40960,256,4,MODE_FOUR
	dc.l	0
; the menu: 320 x 256 x 5 ($F4E, $F98-$FAE), plane 4 the text
Screens_menu:
	SCREEN	Intro_h6+$C0,256,5,MODE_TEXT
	SCREEN	Intro_h6+$C8C0,256,5,MODE_TEXT
	dc.l	0
Text_no_st:
	dc.b	"Das Intro (INTROST.TOS) braucht einen ST oder STE",13,10
	dc.b	"mit Farbmonitor.  Taste druecken.",13,10,0
Text_cursor_off:
	dc.b	27,'f',0
Text_cursor_on:
	dc.b	27,'e',0
	even

	SECTION	Intro_bss,bss
Old_ssp:		ds.l	1
Target_stars:		ds.w	1+2*STARS_MAX	; count, per star offset and word
Alter_vbl:		ds.l	1	; AMIGA_NOTAUS.S reads this name
Old_level3:		ds.l	1
Old_trap0:		ds.l	1
Old_trap8:		ds.l	1
Old_timerb:		ds.l	1
Old_screen:		ds.l	1
Old_log:		ds.l	1
Old_mouse_vector:	ds.l	1
Kbd_vectors:		ds.l	1
Vbl_count:		ds.l	1
Border_late:		ds.l	1	; Tb_border: line ST_BORDER over, no switch
Border_missed:		ds.l	1	; Tb_border: counter never got there
Exec_zeiger:		ds.l	1	; K1: what Thalion reads as ExecBase
St_screen_a:		ds.l	1
St_screen_b:		ds.l	1	; = St_screen_a + ST_SCREEN
Frame_base:		ds.l	1	; the base this frame shows (Vbl)
St_shown:		ds.l	1	; the ST screen the base points to
Result:			ds.w	1
Old_mode:		ds.w	1
K2_unknown:		ds.w	1
Library_missed:		ds.w	1
Old_colours:		ds.w	16
St_palette:		ds.w	16	; written to the ST at the next VBL
Split_count:		ds.w	1	; colours Tb_border sets at line 200
Split_colours:		ds.w	2*4	; register offset, ST value
Colour_table:		ds.w	$1000	; Amiga $0RGB -> ST register value
Amiga_register:		ds.b	AR_SIZE
Amiga_cia_a:		ds.b	2
Old_sync:		ds.b	1
Old_tbcr:		ds.b	1
Old_tbdr:		ds.b	1
Old_iera:		ds.b	1
Old_imra:		ds.b	1
Old_mste_clock:		ds.b	1
Is_ste:			ds.b	1
Is_mste:		ds.b	1
Menu_st_ready:		ds.b	1	; Menu_st holds this scene's picture
	even
	include	"amiga_notaus_bss.i"
			ds.b	EXEC_ENTRIES*6
Exec_base:		ds.b	$140	; AttnFlags at $129: 0
			ds.b	GFX_ENTRIES*6
Gfx_base:		ds.b	$40	; ActiView $22, copinit $26: 0
	cnop	0,4
St_memory:		ds.b	2*ST_SCREEN+256
Logo_scratch:		ds.b	200*AMIGA_LINE	; Logo_stages
Clouds_left:		ds.b	CL_CLOUD	; CLOUDS_ST.S: the left cloud, shifted
Clouds_right:		ds.b	CL_CLOUD	; the right one
Menu_st:		ds.b	ST_SCREEN	; the menu picture in ST format
Stack:			ds.b	4096
Stack_end:

; ***************************************************************************
; EXTRO_ST.S -- the ST layer under Thalion's extro (Ambermoon_extro, ST/STE;
; docs/05c-ST.md "ST extro").  Own files (user, 2026-10-29), independent of
; the Falcon's amiga/ layer and of intro_st/; only the emergency exit
; (amiga/AMIGA_NOTAUS.S) is shared, unchanged, as in the fairy and the
; intro.  Thalion's frame is the intro's (docs/11 5.2), so the frame parts
; here are those of intro_st/INTRO_ST.S.
;
; **Thalion's program** (hunks 1-6) comes unchanged from Ambermoon_extro at
; build time (tools/extro_st_program.py), bound to this layer:
;
;   K1  $DFFxxx -> Amiga_register, $BFE001 -> Amiga_cia_a, ExecBase ->
;       Exec_zeiger
;   K2  every write to BLTSIZE -> trap #8 -> K2_trap.  Both sites lie in
;       the part Text_scroll replaces; the trap only counts.
;   K3  the Falcon's places (extro/EXTRO_SUP.S): Extro_after_copy ($2EC,
;       the picture into the ST screens), Extro_switch_1/2 ($1E8, $596,
;       the base at once); the scroll text (TEXT_ST.S): Text_begin ($420),
;       Text_row ($534), Text_scroll ($450), Step_wait ($43A)
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3: K3, the mixing and
; the pictures in ST format are ours.
;
; **The picture.**  Three ST screens in turn (Screen_table): Text_scroll
; draws into the next one, Extro_switch_2 shows it.  A third, because a
; step of the closing text can take longer than a VBL (TEXT_ST.S,
; Step_wait): the screen drawn into is then neither the one shown nor the
; one waiting for the next VBL.  Thalion's own two screens are written
; only once per picture ($2CA) and never shown.  The pictures come in ST format from the build
; (tools/extro_st_data.py): per picture A, X = A xor B and the Amiga colour
; of each of the 16 registers.
;
; **Colours.**  Thalion fades its 32 colours as on the Amiga (K1: into
; Amiga_register); each VBL register r gets the Amiga colour of its
; representative (St_pictures), so the fades work unchanged.  The fairy's
; way (V3, fantasy_st/).
;
; Music: no YM version of the extro music is known; Thalion's player is a
; table of rts (Music_silent).
; ***************************************************************************

	SECTION	Extro_code,code

; ***************************************************************************
; start -- program entry.  The end n (0-2) comes as the command line, one
; digit (the loader: n = -value-5000, docs/11 5.5); started alone or with
; anything else, end 0.  As the Falcon's EXTRO_SUP.S.
; ***************************************************************************
start:
	move.l	4(sp),a0		; basepage
	lea	Stack_end,sp
	cmp.b	#1,$80(a0)
	bne.b	.no_end
	moveq	#0,d0
	move.b	$81(a0),d0
	sub.b	#'0',d0
	cmp.b	#2,d0
	bhi.b	.no_end
	move.b	d0,Handover+4
.no_end:
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
	bsr	Extro_setup
	; Thalion's program, as the Amiga loader calls it: a0 = handover
	; record, back d0 = 0 (docs/11, 5.2)
	lea	Handover,a0
	jsr	Extro_h1
	move.w	d0,Result
	bsr	Extro_teardown
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
; Sets Is_ste (STE palette, four bits a channel).  As in the intro.
; ***************************************************************************
Machine_check:
	sf	Is_ste
	move.l	COOKIES.w,d0
	beq.b	.monitor
	move.l	d0,a0
.find:	move.l	(a0)+,d0
	beq.b	.monitor
	move.l	(a0)+,d1
	cmp.l	#'_MCH',d0
	bne.b	.find
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
; Extro_setup -- low resolution at 50 Hz, two black screens, the Amiga side
; at rest, the library, mouse, vectors.  As the intro's Intro_setup, without
; Timer B: the extro shows 200 lines (S1).
; ***************************************************************************
Extro_setup:
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

	; screens on 256 bytes: the plain ST has no low base byte
	move.l	#St_memory+255,d0
	clr.b	d0
	lea	Screen_table,a0
	moveq	#ST_SCREENS-1,d1
.s:	move.l	d0,(a0)
	addq.l	#8,a0
	add.l	#ST_SCREEN,d0
	dbf	d1,.s
	lea	St_pictures,a0
	move.l	a0,Current_picture	; until Thalion's first copy: black

	st	Ab_modus		; from here the teardown restores
	clr.w	-(sp)			; low resolution
	move.l	Screen_table,-(sp)
	move.l	Screen_table,-(sp)
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

	; vectors: $6C gets a bare rte until Thalion puts its VBL there; $80
	; (trap #0) Thalion sets itself
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	VEK_LEVEL3.w,Old_level3
	move.l	VEK_TRAP0.w,Old_trap0
	move.l	VEK_TRAP8.w,Old_trap8
	move.l	#K2_trap,VEK_TRAP8.w
	move.l	#Bare_rte,VEK_LEVEL3.w
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
; bit on top).  As in the intro.
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
; Extro_teardown -- everything back as before the start.
;
; Repeatable (emergency exit, AMIGA_NOTAUS.S): each step only if its flag
; is set, and clears it.  In the emergency exit without GEMDOS.
; ***************************************************************************
Extro_teardown:
	tst.b	Ab_vbl
	beq.b	.mouse
	move.w	sr,-(sp)
	or.w	#$0700,sr
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

NOTAUS_ABRAEUMEN	equ	Extro_teardown
	include	"AMIGA_NOTAUS.S"

; ***************************************************************************
; The library: exec and graphics, as far as Thalion's frame calls them
; (docs/11, 5.2: the intro's five calls).  Per library a table of jmp
; instructions below the base, as on the Amiga; the fields above it are 0
; (AttnFlags 0: no 68010+, Thalion takes VBR 0; ActiView and copinit 0).
; Any other entry lands in Library_missing and is counted.  As in the intro.
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
; K2_trap -- trap #8 where Thalion writes BLTSIZE (K2).  The extro's two
; sites ($4AA, $4FC, both move.w #imm,$58(a6)) lie in the part Text_scroll
; replaces, so this only counts (K2_unknown) and goes on behind the
; instruction: no blit.
; ***************************************************************************
K2_trap:
	addq.w	#1,K2_unknown
	addq.l	#4,2(sp)		; #imm and $0058 behind the trap
	rte

; ***************************************************************************
; Mouse_vector -- mouse vector (Kbdvbase+16), a0 = IKBD packet.  Header
; $F8-$FB: bit 1 left, bit 0 right.  To the Amiga side:
;   CIA-A port A bit 6 = left button (0 = down): on to the next picture
;   POTGOR bit 10      = right button (0 = down): pause ($F54)
; As in the intro.
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
	rts

; ***************************************************************************
; Vbl -- the VBL ($70).  The 16 ST colours from Thalion's 32 (each register
; the Amiga colour of its representative), then Thalion's VBL ($6C, ends
; with rte: counter 5:$4, music).
;
; TOS's VBL no longer runs; we count _frclock ourselves, because TOS waits
; for it, after bombs even before the emergency exit (T16).
; ***************************************************************************
Vbl:
	movem.l	d0-d1/a0-a3,-(sp)
	addq.l	#1,FRCLOCK.w
	addq.l	#1,Vbl_count
	ifd	ABSTURZTEST
	addq.l	#1,Absturz_zaehler
	endc
	move.l	Current_picture,a0
	lea	SP_REPS(a0),a0
	lea	Amiga_register+AR_COLOR00,a1
	lea	Colour_table,a2
	lea	ST_PAL.w,a3
	moveq	#16-1,d1
.c:	moveq	#0,d0
	move.b	(a0)+,d0
	add.w	d0,d0
	move.w	0(a1,d0.w),d0
	and.w	#$0FFF,d0
	add.w	d0,d0
	move.w	0(a2,d0.w),(a3)+
	dbf	d1,.c
	ifd	MIXTAKT
	tst.b	Mixing
	beq.b	.shown
	move.w	#$700,ST_PAL.w		; TEXT_ST.S: still mixing
.shown:
	endc
	movem.l	(sp)+,d0-d1/a0-a3
	move.l	VEK_LEVEL3.w,-(sp)
	rts

; ***************************************************************************
; Extro_after_copy -- K3 at $2EC: Thalion has cleared the background, put
; the picture into it and copied it into both of its screens ($2CA).  The
; same picture in ST format into all ST screens, its registers from now
; on (the colours are black here: Thalion faded out at $270).  Then the
; three covered instructions and on at $2F4, as the Falcon's
; Extro_nach_kopie.  (sp) is Thalion's picture + 4 ($28C).
; ***************************************************************************
Extro_after_copy:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	15*4(sp),d0
	subq.l	#4,d0
	lea	St_pictures,a0
.find:	move.l	(a0),d1
	beq.b	.unknown
	cmp.l	d0,d1
	beq.b	.found
	lea	ST_PICTURE(a0),a0
	bra.b	.find
.unknown:
	addq.w	#1,Picture_unknown	; the screens keep what they had
	bra.b	.out
.found:
	move.l	a0,Current_picture
	move.l	SP_A(a0),a0
	lea	Screen_table,a5
	moveq	#ST_SCREENS-1,d0
.copy:	move.l	(a5),a1
	addq.l	#8,a5
	movem.l	d0/a0,-(sp)
	bsr	Screen_copy
	movem.l	(sp)+,d0/a0
	dbf	d0,.copy
	lea	Dirty,a0		; no text in any
	move.w	#ST_SCREENS*ST_LINES/4-1,d0
.d:	clr.l	(a0)+
	dbf	d0,.d
.out:	movem.l	(sp)+,d0-d7/a0-a6
	move.l	(sp),a4			; Thalion's move.l (sp),a4
	addq.l	#2,a4			; addq.l #2,a4
	jsr	Extro_h1+$5B2		; bsr $5B2 (fade in)
	jmp	Extro_h1+$2F4

; Screen_copy -- a0 = picture in ST format, a1 = ST screen (ST_SCREEN
; bytes).  Changes d0-d7/a2-a6.
Screen_copy:
	move.l	a0,a6
	move.w	#ST_SCREEN/40-1,d7
.c:	movem.l	(a6)+,d0-d6/a2-a4
	movem.l	d0-d6/a2-a4,(a1)
	lea	40(a1),a1
	dbf	d7,.c
	rts

; ***************************************************************************
; Extro_switch_1/2 -- K3 at $1E8 and $596: Thalion's bsr $EBC (new copper
; list, COP1LC), then the ST base at once (Base_set), as the Falcon's
; Extro_umschalten_1/2.  Then the instruction whose first word the jmp
; covers.
; ***************************************************************************
Extro_switch_1:
	jsr	Extro_h1+$EBC		; bsr $EBC
	bsr	Base_set
	jsr	Extro_h1+$F54		; bsr $F54 (wait for the VBL)
	jmp	Extro_h1+$1F0

Extro_switch_2:
	jsr	Extro_h1+$EBC		; bsr $EBC
	bsr	Base_set
	tst.w	Extro_h5+H5_FAST	; tst.w $3E (hunk 5); the flags hold at $5A0
	jmp	Extro_h1+$5A0

; Base_set -- the ST screen drawn last (Drawn; at $1E8 the first) from the
; next frame on.  All registers stay.
Base_set:
	movem.l	d0/a0-a1,-(sp)
	move.w	Drawn,d0
	bsr	Screen_of
	move.l	a0,d0
	lsr.l	#8,d0
	move.b	d0,VBASE_MID.w
	lsr.w	#8,d0
	move.b	d0,VBASE_HIGH.w
	movem.l	(sp)+,d0/a0-a1
	rts

; Screen_of -- d0.w = an ST screen (0..ST_SCREENS-1) -> a0 = the screen,
; a1 = its row flags (TEXT_ST.S).  Changes d0.
Screen_of:
	lsl.w	#3,d0
	lea	Screen_table,a1
	move.l	0(a1,d0.w),a0
	move.l	4(a1,d0.w),a1
	rts

	include	"TEXT_ST.S"

; ***************************************************************************
; Data
; ***************************************************************************
	SECTION	Extro_data,data

; Per ST screen: its address (set at start), its row flags (TEXT_ST.S)
Screen_table:
	dc.l	0,Dirty
	dc.l	0,Dirty+ST_LINES
	dc.l	0,Dirty+2*ST_LINES

; The record Thalion's frame gets in a0: the music player, the end (0-2;
; start sets it from the command line)
Handover:
	dc.l	Music_silent
	dc.b	0,0
	even
; Thalion's music player: a jump table (+0, +12, +16, +24); each entry
; here is an rts.
Music_silent:
	rept	16
	rts
	endr
; Amiga level 0-15 -> ST level: three bits; STE: four, the lowest on top
Levels_st:
	dc.b	0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7
Levels_ste:
	dc.b	$0,$8,$1,$9,$2,$A,$3,$B,$4,$C,$5,$D,$6,$E,$7,$F
Text_no_st:
	dc.b	"Das Extro (EXTROST.TOS) braucht einen ST oder STE",13,10
	dc.b	"mit Farbmonitor.  Taste druecken.",13,10,0
Text_cursor_off:
	dc.b	27,'f',0
Text_cursor_on:
	dc.b	27,'e',0
	even

; An entry of St_pictures (build/st_extro/extro_st_data.i)
SP_THALION	equ	0		; .l Thalion's picture (hunk 3)
SP_A		equ	4		; .l the picture in ST format
SP_X		equ	8		; .l A xor B (B: the text colours)
SP_REPS		equ	12		; 16 bytes: Amiga colour of each register
	include	"extro_st_data.i"

	SECTION	Extro_bss,bss
Old_ssp:		ds.l	1
Alter_vbl:		ds.l	1	; AMIGA_NOTAUS.S reads this name
Old_level3:		ds.l	1
Old_trap0:		ds.l	1
Old_trap8:		ds.l	1
Old_screen:		ds.l	1
Old_log:		ds.l	1
Old_mouse_vector:	ds.l	1
Kbd_vectors:		ds.l	1
Vbl_count:		ds.l	1
Exec_zeiger:		ds.l	1	; K1: what Thalion reads as ExecBase
Current_picture:	ds.l	1	; its entry in St_pictures
Result:			ds.w	1
Old_mode:		ds.w	1
K2_unknown:		ds.w	1
Library_missed:		ds.w	1
Picture_unknown:	ds.w	1
Old_colours:		ds.w	16
Colour_table:		ds.w	$1000	; Amiga $0RGB -> ST register value
Amiga_register:		ds.b	AR_SIZE
Amiga_cia_a:		ds.b	2
Old_sync:		ds.b	1
Is_ste:			ds.b	1
	even
	include	"amiga_notaus_bss.i"
			ds.b	EXEC_ENTRIES*6
Exec_base:		ds.b	$140	; AttnFlags at $129: 0
			ds.b	GFX_ENTRIES*6
Gfx_base:		ds.b	$40	; ActiView $22, copinit $26: 0
	cnop	0,4
St_memory:		ds.b	ST_SCREENS*ST_SCREEN+256
Stack:			ds.b	4096
Stack_end:

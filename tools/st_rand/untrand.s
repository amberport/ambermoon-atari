; ***************************************************************************
; untrand.s -- probe T93: can the ST fairy intro open the lower border?
;
; One question, nothing else: does a short 60 Hz switch at the end of display
; line 199 give us the lines below it, every frame, on the user's STE and
; monitor, while the mouse and keyboard keep the ACIA busy?
;
; The picture answers most of it:
;
;     16 colour bars and a white tick line every 10 lines, with the line
;     number at both edges.  The lowest number you can read is how far the
;     monitor shows the opened border (Hatari: 47 extra lines, the last two
;     blanked).  From line 134 on, white turns yellow: a second Timer B
;     event in the same frame, as the fairy intro needs (V3 palettes).
;
;     border stays black below 199    the switch does not work here
;     bottom flickers                 it works only in some frames
;     bars below 199 shifted sideways the 60 Hz phase lasted too long
;
; UNTRAND.TXT has the counts: frames, frames with the border open, how late
; the bottom interrupt came (entry line), late frames, timeouts.
;
; How it works.  VBL: Timer B counts 134 lines (palette switch), then counts
; to line 199-LEAD.  That interrupt masks everything and polls the video
; address counter until line 199 is being fetched.  There it syncs to the
; cycle: the low byte of the counter says how far the line is (2 bytes per
; 4 cycles), and lsl waits the rest (8+2n cycles), as demos do.  Then
; DELAY_PRE nops to the end of line 199's display, 60 Hz for DELAY nops, and
; back to 50 Hz.  The GLUE looks at the frequency once per line (Hatari:
; cycle 502 on the STF, 500 on the STE); seeing 60 Hz on line 199 of a 50 Hz
; frame it misses the end of the display, so DE stays on to line 246.
; Following the video counter instead of trusting the Timer B count keeps the
; switch on the right line even when the interrupt comes late (Timer C and
; the IKBD interrupt have the same level and can hold it back).  On a Mega STE
; the window runs at 8 MHz without cache, so the nops mean the same there.
;
; Window in Hatari 2.6.1 (STE, 2026-10-23), DELAY_PRE 46: DELAY 13 to 24
; opens the border cleanly in every frame; 12 and less leaves it closed, 25
; and more shifts the lines below 199 (60 Hz still on when line 200 starts).
; DELAY_PRE below about 32 shifts them too (60 Hz before line 199 ends).
; With the sync the edges are sharp.  LEAD 2 came late in 9 of 750 frames,
; LEAD 3 in 4, LEAD 4 and 6 never.
;
; Cost per frame: from the entry (line 199-LEAD) to the start of line 200,
; about LEAD+1 lines of 512 cycles (LEAD 6: 2.2 %), all interrupts masked.
;
; Build: sh tools/st_rand/baue.sh   (-DDELAY=n etc. for a calibration run)
; ***************************************************************************

; ---- GEMDOS / BIOS / XBIOS ----
Super		equ	$20
Fcreate		equ	$3C
Fwrite		equ	$40
Fclose		equ	$3E
Mshrink		equ	$4A
Bconstat	equ	1
Bconin		equ	2
Physbase	equ	2
Logbase		equ	3
Getrez		equ	4
Setscreen	equ	5
Vsync		equ	37

; ---- picture ----
LINE_BYTES	equ	160
SCR_LINES	equ	200
EXTRA_LINES	equ	48		; Hatari shows 47 below line 199
ALL_LINES	equ	SCR_LINES+EXTRA_LINES
SCR_SIZE	equ	LINE_BYTES*ALL_LINES

SPLIT_LINE	equ	134		; Timer B event 1, the fairy's split
LEAD		equ	6		; event 2 this many lines before line 199
COL15_TOP	equ	$0777		; white
COL15_LOW	equ	$0770		; yellow, from SPLIT_LINE on

SYNC_START	equ	(SCR_LINES-1)*LINE_BYTES	; line 199
SYNC_OFS	equ	SYNC_START+8	; read the counter from here on
SYNC_K		equ	62		; shift count when read at the line start

	ifnd	DELAY_PRE
DELAY_PRE	equ	46		; nops from the sync to 60 Hz (Hatari)
	endc
	ifnd	DELAY
DELAY		equ	18		; nops at 60 Hz, middle of Hatari's 13-24
	endc
	ifnd	RUN_TIME
RUN_TIME	equ	30*200		; 30 s in 200 Hz ticks, Esc ends earlier
	endc
WAIT_LIMIT	equ	200		; poll rounds before giving up (~15 lines)
OPEN_LIMIT	equ	60		; poll rounds for DE on line 200 (~2 lines)

; ---- hardware ----
SYNC_MODE	equ	$FFFF820A	; bit 1: 1 = 50 Hz, 0 = 60 Hz
VID_CNT		equ	$FFFF8205	; hi, mid ($8207), lo ($8209)
PALETTE		equ	$FFFF8240
MSTE_SPEED	equ	$FFFF8E21	; Mega STE: bit 0 16 MHz, bit 1 cache
MFP_IERA	equ	$FFFFFA07	; Timer B is bit 0 in all four
MFP_IPRA	equ	$FFFFFA0B
MFP_ISRA	equ	$FFFFFA0F
MFP_IMRA	equ	$FFFFFA13
MFP_TBCR	equ	$FFFFFA1B
MFP_TBDR	equ	$FFFFFA21
VEC_TIMERB	equ	$120
HZ200		equ	$4BA
NVBLS		equ	$454
VBLQUEUE	equ	$456
COOKIES		equ	$5A0
MCH_MSTE	equ	$00010010

	SECTION	text,code

start:
	move.l	4(sp),a0		; basepage
	move.l	12(a0),d0		; text
	add.l	20(a0),d0		; data
	add.l	28(a0),d0		; bss
	add.l	#$100,d0
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#Mshrink,-(sp)
	trap	#1
	lea	12(sp),sp
	lea	stacktop,sp

	move.w	#1,stage		; 1: started
	bsr	report

	move.w	#Getrez,-(sp)
	trap	#14
	addq.l	#2,sp
	move.w	d0,oldrez
	cmp.w	#2,d0			; monochrome monitor: nothing to test
	beq	leave_user

	dc.w	$A000			; line-A: a1 = font headers
	move.l	4(a1),a0		; the 8x8 font
	move.l	76(a0),font_dat
	move.w	80(a0),font_w

	move.w	#Physbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,oldphys
	move.w	#Logbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,oldlog

	move.l	#screen_mem+255,d0	; the ST wants the base on 256 bytes
	clr.b	d0
	move.l	d0,screen

	clr.l	-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,oldssp

	move.w	#2,stage		; 2: supervisor
	bsr	report

	bsr	find_mch

	lea	PALETTE.w,a0
	lea	oldpal,a1
	moveq	#16-1,d0
sp_save:
	move.w	(a0)+,(a1)+
	dbf	d0,sp_save
	move.b	SYNC_MODE.w,oldsync

	clr.w	-(sp)			; low resolution
	move.l	screen,-(sp)
	move.l	screen,-(sp)
	move.w	#Setscreen,-(sp)
	trap	#14
	lea	12(sp),sp
	move.w	#Vsync,-(sp)
	trap	#14
	addq.l	#2,sp
	bsr	draw_picture		; after Setscreen: it clears 32000 bytes

	lea	newpal(pc),a0
	lea	PALETTE.w,a1
	moveq	#16-1,d0
sp_set:
	move.w	(a0)+,(a1)+
	dbf	d0,sp_set
	bset	#1,SYNC_MODE.w		; 50 Hz

	move.w	#3,stage		; 3: picture on screen
	bsr	report

	ifnd	NOTIMER
	bsr	timer_on
	endc

	move.l	HZ200.w,d7
	add.l	#RUN_TIME,d7
ml_loop:
	cmp.l	HZ200.w,d7
	bls.b	ml_end
	move.w	#2,-(sp)		; console
	move.w	#Bconstat,-(sp)
	trap	#13
	addq.l	#4,sp
	tst.w	d0
	beq.b	ml_loop
	move.w	#2,-(sp)
	move.w	#Bconin,-(sp)
	trap	#13
	addq.l	#4,sp
	swap	d0
	cmp.b	#$01,d0			; Esc
	bne.b	ml_loop
ml_end:
	bsr	timer_off

	move.b	oldsync,SYNC_MODE.w
	move.w	oldrez,-(sp)
	move.l	oldphys,-(sp)
	move.l	oldlog,-(sp)
	move.w	#Setscreen,-(sp)
	trap	#14
	lea	12(sp),sp
	move.w	#Vsync,-(sp)
	trap	#14
	addq.l	#2,sp
	lea	oldpal,a0
	lea	PALETTE.w,a1
	moveq	#16-1,d0
sp_back:
	move.w	(a0)+,(a1)+
	dbf	d0,sp_back

	move.w	#4,stage		; 4: done, everything back
	bsr	report

	move.l	oldssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	bra.b	quit

leave_user:
	move.w	#9,stage		; 9: monochrome, nothing done
	bsr	report
quit:
	clr.w	-(sp)
	trap	#1			; Pterm0

; ***************************************************************************
; find_mch -- Mega STE?  Only there does MSTE_SPEED exist; a write to it on
; any other machine is a bus error.
; ***************************************************************************
find_mch:
	sf	mega_ste
	move.l	COOKIES.w,d0
	beq.b	fm_out
	move.l	d0,a0
fm_loop:
	move.l	(a0)+,d0
	beq.b	fm_out
	move.l	(a0)+,d1
	cmp.l	#'_MCH',d0
	bne.b	fm_loop
	cmp.l	#MCH_MSTE,d1
	seq	mega_ste
fm_out:
	rts

; ***************************************************************************
; draw_picture -- bars, tick lines, line numbers, ALL_LINES lines.
; ***************************************************************************
draw_picture:
	move.l	screen,a0
	moveq	#0,d6			; line
dp_line:
	move.l	d6,d0
	divu.w	#10,d0
	swap	d0			; remainder
	tst.w	d0
	bne.b	dp_bars
	moveq	#LINE_BYTES/4-1,d1	; tick: colour 15 across
dp_tick:
	move.l	#-1,(a0)+
	dbf	d1,dp_tick
	bra.b	dp_next
dp_bars:
	clr.l	(a0)+			; words 0-1: margin
	clr.l	(a0)+
	clr.l	(a0)+
	clr.l	(a0)+
	moveq	#0,d2			; colour = word - 2
dp_bar:
	moveq	#4-1,d3
	move.w	d2,d4
dp_plane:
	lsr.w	#1,d4
	scs	d5
	ext.w	d5
	move.w	d5,(a0)+
	dbf	d3,dp_plane
	addq.w	#1,d2
	cmp.w	#16,d2
	bne.b	dp_bar
	clr.l	(a0)+			; words 18-19: margin
	clr.l	(a0)+
	clr.l	(a0)+
	clr.l	(a0)+
dp_next:
	addq.w	#1,d6
	cmp.w	#ALL_LINES,d6
	bne.b	dp_line

	moveq	#0,d6			; numbers below each tick
dp_num:
	move.w	d6,d0
	moveq	#0,d1			; left edge
	move.w	d6,d2
	addq.w	#1,d2
	bsr	draw_number
	move.w	d6,d0
	moveq	#37,d1			; right edge
	move.w	d6,d2
	addq.w	#1,d2
	bsr	draw_number
	add.w	#10,d6
	cmp.w	#ALL_LINES-9,d6
	bls.b	dp_num
	rts

; draw_number -- d0.w 0-999 as three digits, d1.w column, d2.w line.
draw_number:
	ext.l	d0
	divu.w	#100,d0
	move.l	d0,d7
	add.w	#'0',d0
	bsr	draw_char
	addq.w	#1,d1
	clr.w	d7
	swap	d7
	divu.w	#10,d7
	move.w	d7,d0
	add.w	#'0',d0
	bsr	draw_char
	addq.w	#1,d1
	swap	d7
	move.w	d7,d0
	add.w	#'0',d0
	bsr	draw_char
	rts

; draw_char -- d0.w char in colour 15 at column d1.w (8 pixels), line d2.w.
; Keeps d1, d2, d6, d7.
draw_char:
	movem.l	d1-d3/a0-a1,-(sp)
	move.l	screen,a0
	mulu.w	#LINE_BYTES,d2
	add.l	d2,a0
	move.w	d1,d3
	lsr.w	#1,d3
	lsl.w	#3,d3			; 8 bytes per 16 pixels
	add.w	d3,a0
	and.w	#1,d1
	add.w	d1,a0			; odd column: the low byte
	move.l	font_dat,a1
	and.w	#$FF,d0
	add.w	d0,a1
	moveq	#8-1,d3
dc_row:
	move.b	(a1),d1
	move.b	d1,(a0)
	move.b	d1,2(a0)
	move.b	d1,4(a0)
	move.b	d1,6(a0)
	add.w	font_w,a1
	lea	LINE_BYTES(a0),a0
	dbf	d3,dc_row
	movem.l	(sp)+,d1-d3/a0-a1
	rts

; ***************************************************************************
; timer_on / timer_off -- vector, VBL slot and MFP saved and set.
; ***************************************************************************
timer_on:
	move.w	sr,-(sp)
	move.w	#$2700,sr
	move.l	VEC_TIMERB.w,oldvec
	move.b	MFP_TBCR.w,oldtbcr
	move.b	MFP_TBDR.w,oldtbdr
	move.b	MFP_IERA.w,oldiera
	move.b	MFP_IMRA.w,oldimra
	clr.b	MFP_TBCR.w
	move.l	#tb_split,VEC_TIMERB.w
	move.w	#$FFFF,entry_min
	clr.w	entry_max

	move.w	NVBLS.w,d0		; a free VBL slot
	move.l	VBLQUEUE.w,a0
	subq.w	#1,d0
	bmi.b	to_none
to_find:
	tst.l	(a0)
	beq.b	to_slot
	addq.l	#4,a0
	dbf	d0,to_find
	bra.b	to_none
to_slot:
	move.l	a0,vblslot
	move.l	#vbl_int,(a0)
to_none:
	move.w	(sp)+,sr
	rts

timer_off:
	move.w	sr,-(sp)
	move.w	#$2700,sr
	clr.b	MFP_TBCR.w
	bclr	#0,MFP_IERA.w
	bclr	#0,MFP_IMRA.w
	move.b	oldtbdr,MFP_TBDR.w
	move.b	oldiera,MFP_IERA.w
	move.b	oldimra,MFP_IMRA.w
	move.l	oldvec,VEC_TIMERB.w
	move.b	oldtbcr,MFP_TBCR.w
	move.l	vblslot,d0
	beq.b	tf_none
	move.l	d0,a0
	clr.l	(a0)
	clr.l	vblslot
tf_none:
	move.w	(sp)+,sr
	rts

; ***************************************************************************
; vbl_int -- per frame: white on top, Timer B to the split.
;
; The pending bit goes before the enable, or an event latched last frame
; fires at once.
; ***************************************************************************
vbl_int:
	addq.l	#1,n_vbl
	move.w	#COL15_TOP,PALETTE+30.w
	clr.b	MFP_TBCR.w
	move.l	#tb_split,VEC_TIMERB.w
	move.b	#SPLIT_LINE,MFP_TBDR.w
	bclr	#0,MFP_IPRA.w
	bclr	#0,MFP_ISRA.w
	bset	#0,MFP_IERA.w
	bset	#0,MFP_IMRA.w
	move.b	#8,MFP_TBCR.w		; event count
	rts

; ***************************************************************************
; tb_split -- event 1 (line 134): yellow, then count to line 199-LEAD.
; Fires at the end of line SPLIT_LINE-1; restarting during line SPLIT_LINE
; counts that line as the first.
; ***************************************************************************
tb_split:
	move.w	#COL15_LOW,PALETTE+30.w
	clr.b	MFP_TBCR.w
	move.l	#tb_bottom,VEC_TIMERB.w
	move.b	#(SCR_LINES-1-LEAD)-(SPLIT_LINE-1),MFP_TBDR.w
	move.b	#8,MFP_TBCR.w
	addq.l	#1,n_split
	bclr	#0,MFP_ISRA.w
	rte

; ***************************************************************************
; tb_bottom -- event 2: open the lower border.
;
; Waits with all interrupts masked until the video counter is SYNC_OFS into
; the picture (line 199 being fetched), syncs to the cycle, then DELAY_PRE
; nops and DELAY nops at 60 Hz.  Afterwards it watches for DE on line 200:
; the base is on 256 bytes, so after line 199 the low byte of the counter is
; 0, and it leaves 0 only if the border opened.
; ***************************************************************************
tb_bottom:
	move.w	#$2700,sr
	movem.l	d0-d3/a0-a1,-(sp)
	clr.b	MFP_TBCR.w		; one bottom event per frame
	tst.b	mega_ste
	beq.b	tb_speed
	move.b	MSTE_SPEED.w,oldspeed
	clr.b	MSTE_SPEED.w		; 8 MHz, no cache: DELAY in bus cycles
tb_speed:
	lea	VID_CNT.w,a0
	movep.l	-2(a0),d0		; base mid, then counter hi, mid, lo
	and.l	#$00FFFFFF,d0
	sub.l	screen,d0
	divu.w	#LINE_BYTES,d0		; entry line
	cmp.w	entry_max,d0
	bls.b	tb_nmax
	move.w	d0,entry_max
tb_nmax:
	cmp.w	entry_min,d0
	bcc.b	tb_nmin
	move.w	d0,entry_min
tb_nmin:
	addq.l	#2,a0			; mid and low byte, for movep.w
	move.w	screen+2,d3		; base, low word
	move.w	#WAIT_LIMIT-1,d2
tb_wait:
	movep.w	0(a0),d0
	sub.w	d3,d0			; offset into the picture
	cmp.w	#SYNC_OFS,d0
	dbcc	d2,tb_wait
	bcs.w	tb_timeout
	cmp.w	#SCR_LINES*LINE_BYTES,d0
	bcc.w	tb_late			; line 199 already over: no sync
	moveq	#0,d0
	move.b	2(a0),d0
	sub.b	#SYNC_START&$FF,d0	; bytes into line 199, 2 per 4 cycles
	moveq	#SYNC_K,d1
	sub.w	d0,d1
	bpl.b	tb_shift
	moveq	#0,d1
tb_shift:
	lsl.l	d1,d1			; 8+2n cycles: a later read waits less
	rept	DELAY_PRE		; to the end of line 199's display
	nop
	endr
	bra.b	tb_switch
tb_late:
	addq.l	#1,n_late
tb_switch:
	ifnd	NOSWITCH
	clr.b	SYNC_MODE.w		; 60 Hz
	endc
	rept	DELAY
	nop
	endr
	ifnd	NOSWITCH
	move.b	#2,SYNC_MODE.w		; 50 Hz
	endc
	addq.l	#1,n_switch

	lea	2(a0),a1		; low byte
	move.w	#OPEN_LIMIT-1,d2
tb_de:
	tst.b	(a1)
	dbne	d2,tb_de
	beq.b	tb_done
	addq.l	#1,n_open
	bra.b	tb_done
tb_timeout:
	addq.l	#1,n_timeout
tb_done:
	tst.b	mega_ste
	beq.b	tb_out
	move.b	oldspeed,MSTE_SPEED.w
tb_out:
	addq.l	#1,n_bottom
	bclr	#0,MFP_ISRA.w
	movem.l	(sp)+,d0-d3/a0-a1
	rte

; ***************************************************************************
; report -- write UNTRAND.TXT anew after each stage.  If the program stops
; on the way, the file names the last stage it reached.
; ***************************************************************************
report:
	movem.l	d0-d4/a0-a1,-(sp)
	lea	buffer,a0
	move.l	a0,bp

	lea	t_head(pc),a0
	bsr	add_text
	lea	t_stage(pc),a0
	moveq	#0,d0
	move.w	stage,d0
	bsr	add_line
	lea	t_mste(pc),a0
	moveq	#0,d0
	tst.b	mega_ste
	beq.b	rp_st
	moveq	#1,d0
rp_st:
	bsr	add_line
	lea	t_dpre(pc),a0
	moveq	#DELAY_PRE,d0
	bsr	add_line
	lea	t_delay(pc),a0
	moveq	#DELAY,d0
	bsr	add_line
	lea	t_lead(pc),a0
	moveq	#LEAD,d0
	bsr	add_line
	lea	t_vbl(pc),a0
	move.l	n_vbl,d0
	bsr	add_line
	lea	t_split(pc),a0
	move.l	n_split,d0
	bsr	add_line
	lea	t_bottom(pc),a0
	move.l	n_bottom,d0
	bsr	add_line
	lea	t_switch(pc),a0
	move.l	n_switch,d0
	bsr	add_line
	lea	t_open(pc),a0
	move.l	n_open,d0
	bsr	add_line
	lea	t_timeout(pc),a0
	move.l	n_timeout,d0
	bsr	add_line
	lea	t_late(pc),a0
	move.l	n_late,d0
	bsr	add_line
	lea	t_emin(pc),a0
	moveq	#0,d0
	move.w	entry_min,d0
	bsr	add_line
	lea	t_emax(pc),a0
	moveq	#0,d0
	move.w	entry_max,d0
	bsr	add_line
	lea	t_tail(pc),a0
	bsr	add_text

	move.l	bp,d0
	lea	buffer,a0
	sub.l	a0,d0
	move.l	d0,length

	clr.w	-(sp)
	pea	filename(pc)
	move.w	#Fcreate,-(sp)
	trap	#1
	addq.l	#8,sp
	move.w	d0,handle
	bmi.b	rp_out
	pea	buffer			; Fwrite(handle, count, buffer)
	move.l	length,-(sp)
	move.w	handle,-(sp)
	move.w	#Fwrite,-(sp)
	trap	#1
	lea	12(sp),sp
	move.w	handle,-(sp)
	move.w	#Fclose,-(sp)
	trap	#1
	addq.l	#4,sp
rp_out:
	movem.l	(sp)+,d0-d4/a0-a1
	rts

; add_line -- text a0, then d0 unsigned decimal, then CR LF.
add_line:
	move.l	d0,-(sp)
	bsr	add_text
	move.l	(sp)+,d0
	lea	numbuf+11,a0
	clr.b	-(a0)
	move.l	d0,d1
al_digit:
	move.l	d1,d0			; d1 / 10 in two steps, remainder in d2
	clr.w	d0
	swap	d0
	divu.w	#10,d0
	move.w	d0,d3
	move.w	d1,d0
	divu.w	#10,d0
	move.w	d0,d4
	swap	d0
	move.w	d0,d2
	moveq	#0,d1
	move.w	d3,d1
	swap	d1
	move.w	d4,d1
	add.b	#'0',d2
	move.b	d2,-(a0)
	tst.l	d1
	bne.b	al_digit
	bsr	add_text
	lea	crlf(pc),a0
					; on into add_text
add_text:
	move.l	bp,a1
at_loop:
	move.b	(a0)+,d0
	beq.b	at_end
	move.b	d0,(a1)+
	bra.b	at_loop
at_end:
	move.l	a1,bp
	rts

newpal:
	dc.w	$000,$700,$720,$740,$560,$070,$072,$074
	dc.w	$057,$007,$207,$407,$606,$333,$555,COL15_TOP

filename:	dc.b	"UNTRAND.TXT",0
t_head:		dc.b	13,10,"UNTRAND -- probe T93, lower border on the ST",13,10,13,10,0
t_stage:	dc.b	"stage reached   : ",0
t_mste:		dc.b	"Mega STE        : ",0
t_dpre:		dc.b	"DELAY_PRE (nops): ",0
t_delay:	dc.b	"DELAY (nops)    : ",0
t_lead:		dc.b	"LEAD (lines)    : ",0
t_vbl:		dc.b	"frames (VBL)    : ",0
t_split:	dc.b	"events line 134 : ",0
t_bottom:	dc.b	"events bottom   : ",0
t_switch:	dc.b	"60 Hz switches  : ",0
t_open:		dc.b	"border opened   : ",0
t_timeout:	dc.b	"timeouts        : ",0
t_late:		dc.b	"late (no sync)  : ",0
t_emin:		dc.b	"entry line min  : ",0
t_emax:		dc.b	"entry line max  : ",0
t_tail:
	dc.b	13,10
	dc.b	"Stage 1 started, 2 supervisor, 3 picture shown, 4 done,",13,10
	dc.b	"9 monochrome monitor (nothing tested).",13,10,13,10
	dc.b	"'border opened' should equal 'events bottom'.  An entry",13,10
	dc.b	"line of 200 means the interrupt came too late that frame.",13,10
	dc.b	"The lowest line number readable on the monitor is the",13,10
	dc.b	"usable height; please note it, and any flicker or shift.",13,10,0
crlf:		dc.b	13,10,0
	even

	SECTION	bss,bss

oldrez:		ds.w	1
stage:		ds.w	1
handle:		ds.w	1
font_w:		ds.w	1
entry_min:	ds.w	1
entry_max:	ds.w	1
oldpal:		ds.w	16
oldssp:		ds.l	1
oldphys:	ds.l	1
oldlog:		ds.l	1
oldvec:		ds.l	1
vblslot:	ds.l	1
screen:		ds.l	1
font_dat:	ds.l	1
bp:		ds.l	1
length:		ds.l	1
n_vbl:		ds.l	1
n_split:	ds.l	1
n_bottom:	ds.l	1
n_switch:	ds.l	1
n_open:		ds.l	1
n_timeout:	ds.l	1
n_late:		ds.l	1
oldtbcr:	ds.b	1
oldtbdr:	ds.b	1
oldiera:	ds.b	1
oldimra:	ds.b	1
oldsync:	ds.b	1
oldspeed:	ds.b	1
mega_ste:	ds.b	1
	even
numbuf:		ds.b	12
buffer:		ds.b	1536
	even
		ds.b	4096
stacktop:
screen_mem:	ds.b	SCR_SIZE+256

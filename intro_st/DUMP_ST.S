; ***************************************************************************
; DUMP_ST.S -- the S key takes the picture the ST shows into a file
; (test builds only: VASM_EXTRA="-DSCREEN_DUMP=1", docs/05c-ST.md T96a).
;
; The intro owns the hardware, and GEMDOS must not run from the VBL.  So:
;   - Dump_key (in the Vbl) takes S from TOS's keyboard buffer and copies
;     the screen this frame shows (Frame_base, all ST_LINES lines), the
;     colours and the border counters into the next free slot;
;   - Dumps_write (after Intro_teardown, TOS back) writes each slot as
;     SHOTnn.PI1 (Degas, the first 200 lines and the colours above line
;     200) and SHOTnn.RAW (header and all lines; tools/st_shot.py makes a
;     PNG of it), into the current folder, with the first free number.
; A dump shows what is in memory, not what the Shifter made of it: a right
; dump of a wrong picture points at the display (border, sync).
; ***************************************************************************
	ifd	SCREEN_DUMP

DUMP_MAX	equ	9		; slots; more presses are counted
KEY_S		equ	$1F		; scan code
IO_SIZE		equ	4		; IOREC: buffer, size, head, tail
IO_HEAD		equ	6
IO_TAIL		equ	8

; header of a slot and of SHOTnn.RAW (big endian, as the 68000 writes it)
DH_MAGIC	equ	0		; .l 'AMSD'
DH_VBL		equ	4		; .l Vbl_count
DH_BASE		equ	8		; .l Frame_base: the base of the picture
DH_NEXT		equ	12		; .l the base registers: the next frame's
DH_LATE		equ	16		; .l Border_late
DH_MISSED	equ	20		; .l Border_missed
DH_PALETTE	equ	24		; .w 16 ST registers, lines 0-199
DH_SPLITS	equ	56		; .w Split_count
DH_SPLIT	equ	58		; .w 4 x (register offset, value) at line 200
DH_STE		equ	74		; .b Is_ste
DH_DIRECT	equ	75		; .b Shown_direct: a target screen
DH_LINES	equ	76		; .w ST_LINES
DH_SIZE		equ	80
DUMP_SIZE	equ	DH_SIZE+ST_SCREEN

; Dump_setup -- TOS's keyboard buffer (Iorec 1).
Dump_setup:
	move.w	#1,-(sp)
	move.w	#Iorec,-(sp)
	trap	#14
	addq.l	#4,sp
	move.l	d0,Dump_iorec
	clr.w	Dump_count
	clr.w	Dump_lost
	rts

; ***************************************************************************
; Dump_key -- in the Vbl, after the colours: one key from TOS's buffer; on
; S the picture of this frame into the next slot.  The copy takes about a
; frame (Timer B still fires inside it); one VBL is lost per dump.
;   All registers are preserved.
; ***************************************************************************
Dump_key:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	Dump_iorec,a0
	move.w	IO_HEAD(a0),d0
	cmp.w	IO_TAIL(a0),d0
	beq.w	.out			; no key
	addq.w	#4,d0
	cmp.w	IO_SIZE(a0),d0
	blo.b	.in
	moveq	#0,d0
.in:	move.l	(a0),a1
	move.b	1(a1,d0.w),d1		; the scan code
	move.w	d0,IO_HEAD(a0)		; taken
	cmp.b	#KEY_S,d1
	bne.w	.out
	move.w	Dump_count,d0
	cmp.w	#DUMP_MAX,d0
	bhs.w	.full
	addq.w	#1,Dump_count
	lea	Dumps,a2
	bra.b	.slot_in
.slot:	add.l	#DUMP_SIZE,a2
.slot_in:
	dbf	d0,.slot
	; header
	move.l	#'AMSD',DH_MAGIC(a2)
	move.l	Vbl_count,DH_VBL(a2)
	move.l	Frame_base,DH_BASE(a2)
	moveq	#0,d0
	move.b	VBASE_HIGH.w,d0
	swap	d0
	move.b	VBASE_MID.w,d0
	lsl.w	#8,d0
	tst.b	Is_ste
	beq.b	.st
	move.b	VBASE_LOW.w,d0
.st:	move.l	d0,DH_NEXT(a2)
	move.l	Border_late,DH_LATE(a2)
	move.l	Border_missed,DH_MISSED(a2)
	movem.l	St_palette,d0-d7
	movem.l	d0-d7,DH_PALETTE(a2)
	move.w	Split_count,DH_SPLITS(a2)
	movem.l	Split_colours,d0-d3
	movem.l	d0-d3,DH_SPLIT(a2)
	move.b	Is_ste,DH_STE(a2)
	move.b	Shown_direct,DH_DIRECT(a2)
	move.w	#ST_LINES,DH_LINES(a2)
	; the picture: ST_LINES lines from the base of this frame
	move.l	Frame_base,a0
	lea	DH_SIZE(a2),a1
	move.w	#ST_SCREEN/40-1,d0
.copy:	movem.l	(a0)+,d1-d7/a3-a5	; 40 bytes
	movem.l	d1-d7/a3-a5,(a1)
	lea	40(a1),a1
	dbf	d0,.copy
	bra.b	.out
.full:	addq.w	#1,Dump_lost
.out:	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Dumps_write -- the slots into files, after Intro_teardown (GEMDOS is
; TOS's again).  Per slot the first number nn from 01 on that has no
; SHOTnn.RAW yet, so an older dump stays.  A failed write ends quietly.
; ***************************************************************************
Dumps_write:
	move.w	Dump_count,d6
	beq.w	.out
	subq.w	#1,d6
	lea	Dumps,a3
	moveq	#0,d5			; the number last tried
.slot:
.free:	addq.w	#1,d5			; the next free SHOTnn.RAW
	cmp.w	#99,d5
	bhi.w	.out
	move.l	#'.RAW',Dump_name+6
	bsr	Dump_number
	move.w	#0,-(sp)		; attributes: plain files
	pea	Dump_name
	move.w	#Fsfirst,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	beq.b	.free			; taken
	; SHOTnn.RAW: header and all lines
	move.l	a3,a4
	move.l	#DUMP_SIZE,d4
	bsr	Dump_file
	bne.b	.out
	; SHOTnn.PI1: resolution, the colours, 200 lines
	move.l	#'.PI1',Dump_name+6
	lea	Dump_degas,a4
	clr.w	(a4)			; low resolution
	movem.l	DH_PALETTE(a3),d0-d3/a0-a2/a5
	movem.l	d0-d3/a0-a2/a5,2(a4)
	move.l	#2+32,d4
	bsr	Dump_open
	bmi.b	.out
	move.w	d0,d7
	bsr	Dump_write		; a4, d4
	lea	DH_SIZE(a3),a4
	move.l	#200*ST_LINE,d4
	bsr	Dump_write
	bsr	Dump_close
	add.l	#DUMP_SIZE,a3
	dbf	d6,.slot
.out:	rts

; Dump_number -- d5 = nn into Dump_name ("SHOTnn").
Dump_number:
	moveq	#0,d0
	move.w	d5,d0
	divu	#10,d0
	add.b	#'0',d0
	move.b	d0,Dump_name+4
	swap	d0
	add.b	#'0',d0
	move.b	d0,Dump_name+5
	rts

; Dump_file -- a4/d4: one block into a new file Dump_name.  Z: written.
Dump_file:
	bsr	Dump_open
	bmi.b	.out
	move.w	d0,d7
	bsr	Dump_write
	bsr	Dump_close
	moveq	#0,d0
.out:	rts

; Dump_open -- Fcreate Dump_name; d0.w = handle, N on failure.
Dump_open:
	move.w	#0,-(sp)
	pea	Dump_name
	move.w	#Fcreate,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	rts

; Dump_write -- d4.l bytes from a4 into handle d7.
Dump_write:
	move.l	a4,-(sp)
	move.l	d4,-(sp)
	move.w	d7,-(sp)
	move.w	#Fwrite,-(sp)
	trap	#1
	lea	12(sp),sp
	rts

; Dump_close -- handle d7.
Dump_close:
	move.w	d7,-(sp)
	move.w	#Fclose,-(sp)
	trap	#1
	addq.l	#4,sp
	rts

	SECTION	Intro_data,data
Dump_name:	dc.b	"SHOT00.RAW",0
	even
	SECTION	Intro_bss,bss
Dump_iorec:	ds.l	1
Dump_count:	ds.w	1	; slots taken
Dump_lost:	ds.w	1	; S pressed with all slots taken
Dump_degas:	ds.w	1+16
	cnop	0,4
Dumps:		ds.b	DUMP_MAX*DUMP_SIZE
	SECTION	Intro_code,code

	endc

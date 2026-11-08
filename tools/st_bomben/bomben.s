; ***************************************************************************
; bomben.s -- probe T109: where did a program crash on the ST?
;
; After bombs TOS keeps what it knew of the crash at $380 (TOS 1.x/2.x and
; EmuTOS alike): a magic long, d0-d7, a0-a7, the exception number in the
; first byte of $3C4, the USP and 16 words from the supervisor stack.  The
; ST intro's emergency exit (amiga/AMIGA_NOTAUS.S) hands the exception to
; TOS with registers and stack unchanged, so the frame is the crash's.
;
; Start BOMBEN.TOS from the desktop right after the bombs.  When the desktop
; hangs, a warm reset (reset button) keeps $380 (Mega STE, TOS 2.06, T109).
; BOMBEN clears the magic after reading, so a record shows only once: the
; next start says "no new record" until there are new bombs (T111).
; It shows the block, reads the 68000 frame (bus and address error: status,
; access address, instruction, SR, PC; others: SR, PC), dumps 64 bytes
; around the PC (code without relocation finds the place in the program
; file even without its load address; TOS loads BOMBEN.TOS where the
; crashed program began, so a dump there is marked as ours) and writes the same into BOMBEN.TXT
; beside itself.  A key ends it.
;
; Standalone, without Thalion's source.  Build: tools/st_bomben/baue.sh.
; ***************************************************************************

Pterm0		equ	0
Crawcin		equ	7
Cconws		equ	9
Super		equ	$20
Fcreate		equ	$3C
Fclose		equ	$3E
Fwrite		equ	$40

CRASH		equ	$380		; magic, d0-d7, a0-a7, enum, usp, 16 words
CRASH_LEN	equ	$6C
PHYSTOP		equ	$42E
MAGIC		equ	$12345678

	SECTION	text,code

start:
	move.l	4(sp),a0		; basepage: our own memory, for the dump
	move.l	a0,Own_from
	move.l	$18(a0),d0		; p_bbase + p_blen = our end
	add.l	$1C(a0),d0
	move.l	d0,Own_to
	clr.l	-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,Old_ssp

	lea	CRASH.w,a0
	lea	Save,a1
	moveq	#CRASH_LEN/4-1,d0
.copy:	move.l	(a0)+,(a1)+
	dbf	d0,.copy
	clr.l	CRASH.w			; read once: a later start sees no old record
	move.l	PHYSTOP.w,Phys

	; the frame: bus and address error have status, address, IR first
	lea	Save+$4C,a2
	move.b	Save+$44,d0
	cmp.b	#2,d0
	beq.b	.group0
	cmp.b	#3,d0
	beq.b	.group0
	move.w	(a2),Sr_v
	move.l	2(a2),Pc_v
	bra.b	.mem
.group0:
	st	Group0
	move.w	(a2),Status_v
	move.l	2(a2),Access_v
	move.w	6(a2),Ir_v
	move.w	8(a2),Sr_v
	move.l	10(a2),Pc_v

	; 64 bytes around the PC, only inside RAM and above the system area
.mem:	move.l	Pc_v,d0
	and.l	#$00FFFFFE,d0
	sub.l	#32,d0
	move.l	d0,Mem_from
	cmp.l	#$800,d0
	bcs.b	.user
	add.l	#64,d0
	cmp.l	Phys,d0
	bhi.b	.user
	move.l	Mem_from,a0
	lea	Mem,a1
	moveq	#63,d0
.mb:	move.b	(a0)+,(a1)+
	dbf	d0,.mb
	st	Mem_ok
	move.l	Mem_from,d0		; TOS loads us where the crashed program
	cmp.l	Own_to,d0		; was: there the bytes are ours
	bcc.b	.user
	add.l	#64,d0
	cmp.l	Own_from,d0
	bls.b	.user
	st	Mem_own

.user:	move.l	Old_ssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp

	; ---- the text
	lea	Text,a1
	lea	T_head,a0
	bsr	puts
	cmp.l	#MAGIC,Save
	beq.b	.magic
	lea	T_nomagic,a0
	bsr	puts
.magic:	lea	T_exc,a0
	bsr	puts
	moveq	#0,d0
	move.b	Save+$44,d0
	bsr	hexb
	bsr	crlf

	lea	T_d,a0
	bsr	puts
	lea	Save+4,a2
	bsr	regs
	lea	T_a,a0
	bsr	puts
	lea	Save+$24,a2
	bsr	regs
	lea	T_usp,a0
	bsr	puts
	move.l	Save+$48,d0
	bsr	hexl
	bsr	crlf

	lea	T_stk,a0
	bsr	puts
	lea	Save+$4C,a2
	moveq	#15,d2
.stk:	move.w	(a2)+,d0
	bsr	hexw
	move.b	#' ',(a1)+
	cmp.w	#8,d2
	bne.b	.stk2
	bsr	crlf
	lea	T_ind,a0
	bsr	puts
.stk2:	dbf	d2,.stk
	bsr	crlf

	tst.b	Group0
	beq.b	.sr
	lea	T_status,a0
	bsr	puts
	move.w	Status_v,d0
	bsr	hexw
	lea	T_access,a0
	bsr	puts
	move.l	Access_v,d0
	bsr	hexl
	lea	T_ir,a0
	bsr	puts
	move.w	Ir_v,d0
	bsr	hexw
	bsr	crlf
.sr:	lea	T_sr,a0
	bsr	puts
	move.w	Sr_v,d0
	bsr	hexw
	lea	T_pc,a0
	bsr	puts
	move.l	Pc_v,d0
	bsr	hexl
	bsr	crlf

	tst.b	Mem_ok
	bne.b	.dump
	lea	T_nomem,a0
	bsr	puts
	bra.b	.out
.dump:	tst.b	Mem_own
	beq.b	.dump2
	lea	T_own,a0
	bsr	puts
.dump2:	lea	Mem,a2
	move.l	Mem_from,d3
	moveq	#3,d4
.row:	move.l	d3,d0
	bsr	hexl
	move.b	#':',(a1)+
	moveq	#15,d2
.col:	move.b	#' ',(a1)+
	move.b	(a2)+,d0
	bsr	hexb
	dbf	d2,.col
	bsr	crlf
	add.l	#16,d3
	dbf	d4,.row

.out:	move.l	a1,Text_end
	lea	T_key,a0
	bsr	puts
	clr.b	(a1)

	pea	Text
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp

	clr.w	-(sp)
	pea	T_file
	move.w	#Fcreate,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi.b	.nofile
	move.w	d0,Handle
	pea	Text
	move.l	Text_end,d0
	sub.l	#Text,d0
	move.l	d0,-(sp)
	move.w	Handle,-(sp)
	move.w	#Fwrite,-(sp)
	trap	#1
	lea	12(sp),sp
	move.w	Handle,-(sp)
	move.w	#Fclose,-(sp)
	trap	#1
	addq.l	#4,sp
	bra.b	.wait
.nofile:
	pea	T_nofile
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp

.wait:	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
	move.w	#Pterm0,-(sp)
	trap	#1

; regs -- eight longs from a2, with a line break after four.
regs:	moveq	#7,d2
.r:	move.l	(a2)+,d0
	bsr	hexl
	move.b	#' ',(a1)+
	cmp.w	#4,d2
	bne.b	.r2
	bsr	crlf
	lea	T_ind,a0
	bsr	puts
.r2:	dbf	d2,.r
	bra.b	crlf

; puts -- the string at a0 to a1, without its null.
puts:	move.b	(a0)+,d0
	beq.b	.e
	move.b	d0,(a1)+
	bra.b	puts
.e:	rts

crlf:	move.b	#13,(a1)+
	move.b	#10,(a1)+
	rts

; hexl, hexw, hexb -- d0 as 8, 4 or 2 hex digits to a1.  Uses d1, d5.
hexl:	moveq	#7,d5
	bra.b	hex
hexw:	swap	d0
	moveq	#3,d5
	bra.b	hex
hexb:	ror.l	#8,d0
	moveq	#1,d5
hex:	rol.l	#4,d0
	move.b	d0,d1
	and.b	#15,d1
	add.b	#'0',d1
	cmp.b	#'9',d1
	bls.b	.d
	addq.b	#7,d1
.d:	move.b	d1,(a1)+
	dbf	d5,hex
	rts

	SECTION	data,data
T_head:		dc.b	"BOMBEN (T111): crash record at $380",13,10,0
T_nomagic:	dc.b	"no new record: values below are old",13,10,0
T_exc:		dc.b	"exception ",0
T_d:		dc.b	"D0-D7 ",0
T_a:		dc.b	"A0-A7 ",0
T_ind:		dc.b	"      ",0
T_usp:		dc.b	"USP   ",0
T_stk:		dc.b	"stack ",0
T_status:	dc.b	"status ",0
T_access:	dc.b	" address ",0
T_ir:		dc.b	" IR ",0
T_sr:		dc.b	"SR ",0
T_pc:		dc.b	" PC ",0
T_nomem:	dc.b	"PC outside RAM, no dump",13,10,0
T_own:		dc.b	"(BOMBEN.TOS now lies there: these bytes are its own, not the crash's)",13,10,0
T_key:		dc.b	"BOMBEN.TXT written. Key ends.",13,10,0
T_nofile:	dc.b	"BOMBEN.TXT could not be written",13,10,0
T_file:		dc.b	"BOMBEN.TXT",0
	even

	SECTION	bss,bss
Old_ssp:	ds.l	1
Phys:		ds.l	1
Save:		ds.b	CRASH_LEN
Status_v:	ds.w	1
Access_v:	ds.l	1
Ir_v:		ds.w	1
Sr_v:		ds.w	1
Pc_v:		ds.l	1
Mem_from:	ds.l	1
Mem:		ds.b	64
Text_end:	ds.l	1
Handle:		ds.w	1
Group0:		ds.b	1
Mem_ok:		ds.b	1
Mem_own:	ds.b	1
		even
Own_from:	ds.l	1
Own_to:		ds.l	1
		even
Text:		ds.b	2048

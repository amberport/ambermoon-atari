; ***************************************************************************
; SETTINGS.S -- AMBER.INF, the one settings file for every program (E17).
;
; A module for the game, the intros and the loader.  No SECTION: the code
; and its few bytes of results land in the code section of whoever includes
; it, so each program has its own copy.  Pure 68000, no macros, only GEMDOS
; (trap #1).  Its labels start with Settings_ (public) or set_ (inside).
;
; **The file**, plain text next to the game files (ATARI\AMBFILES\):
;
;	; Ambermoon settings
;	MUSIC=DSP        ; OFF, DSP, CPU, YM
;	PLAIN_ST=NO      ; NO: as detected; YES: an STE runs like a plain ST
;
; One KEY=VALUE per line, case does not matter, blanks around "=" are
; allowed.  ";" or "#" starts a comment, to the end of the line.  A key
; that is missing keeps SET_NONE: the program takes its own default.  An
; unknown key or value is skipped; the first one is kept for the screen
; (Settings_bad).  Read are the first SET_MAX bytes.
;
; A new setting is one entry in set_table and one result byte below; its
; values count from 0 in the order of the table.
;
; **Entry points** (user or supervisor mode):
;   Settings_read  a0 = file name, with its path.  Fills the results.
;                  d0 = 0 read, -1 no file (then every result is SET_NONE).
;   Settings_text  a0 = buffer of SET_TEXT_LEN bytes.  Writes one line for
;                  the screen, "AMBER.INF: MUSIC=DSP PLAIN_ST=NO", CR LF,
;                  null; "-" for a key the file does not name.
; Both keep every register except the stated d0.
;
; **Results** (bytes, SET_NONE = -1 when the file does not say):
;   Settings_music     SET_OFF, SET_DSP, SET_CPU, SET_YM (= MI_* in
;                      HULL/MUSIK_SUP.S)
;   Settings_plain_st  SET_NO, SET_YES
; ***************************************************************************

SET_MAX		equ	512		; bytes of AMBER.INF that are read
SET_TOKEN	equ	16		; a key or value, 15 characters and the null
SET_TEXT_LEN	equ	80		; the buffer for Settings_text

SET_NONE	equ	-1
SET_OFF		equ	0		; MUSIC
SET_DSP		equ	1
SET_CPU		equ	2
SET_YM		equ	3
SET_NO		equ	0		; PLAIN_ST
SET_YES		equ	1

; ---------------------------------------------------------------------------
; Settings_read -- a0 = file name.  d0 = 0 read, -1 no file.
; Frame on the stack: the file, then the key and the value of one line.
Settings_read:
	movem.l	d1-d7/a0-a6,-(sp)
	lea	-SET_MAX-2*SET_TOKEN(sp),sp
	move.l	a0,a2
	lea	Settings(pc),a3
	lea	(sp),a4			; the file
	lea	SET_MAX(sp),a5		; the key
	lea	SET_MAX+SET_TOKEN(sp),a6	; the value
	sf	Settings_found-Settings(a3)
	clr.b	Settings_bad-Settings(a3)
	move.l	a2,-(sp)
	lea	set_table(pc),a2	; every result to SET_NONE
.reset:	move.w	(a2)+,d0
	bmi.s	.open
	move.b	#SET_NONE,(a3,d0.w)
.name:	tst.b	(a2)+
	bne.s	.name
	bsr	set_skip
	bra.s	.reset
.open:	move.l	(sp)+,a2
	clr.w	-(sp)			; Fopen(name, read)
	move.l	a2,-(sp)
	move.w	#$3D,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi	.none
	move.w	d0,d7
	move.l	a4,-(sp)		; Fread(handle, SET_MAX, file)
	move.l	#SET_MAX,-(sp)
	move.w	d7,-(sp)
	move.w	#$3F,-(sp)
	trap	#1
	lea	12(sp),sp
	move.l	d0,d6
	bpl.s	.close
	moveq	#0,d6			; read error: an empty file
.close:	move.w	d7,-(sp)		; Fclose(handle)
	move.w	#$3E,-(sp)
	trap	#1
	addq.l	#4,sp
	st	Settings_found-Settings(a3)
	move.l	a4,a0
	lea	(a4,d6.l),a1		; a0 = here, a1 = end of the file

.line:	bsr	set_blanks
	cmp.l	a1,a0
	bhs.s	.done
	move.b	(a0),d0
	cmp.b	#';',d0
	beq.s	.next
	cmp.b	#'#',d0
	beq.s	.next
	cmp.b	#13,d0
	beq.s	.next
	cmp.b	#10,d0
	beq.s	.next
	move.l	a5,a2
	bsr	set_token		; the key
	bsr	set_blanks
	cmp.l	a1,a0
	bhs.s	.bad
	cmp.b	#'=',(a0)
	bne.s	.bad
	addq.l	#1,a0
	bsr	set_blanks
	move.l	a6,a2
	bsr	set_token		; the value
	bsr	set_find
	bmi.s	.bad
	move.b	d1,(a3,d0.w)
	bra.s	.next
.bad:	tst.b	Settings_bad-Settings(a3)
	bne.s	.next			; the first one stays
	lea	Settings_bad-Settings(a3),a2
	move.l	a5,a4			; (a1 is the end of the file)
	tst.b	(a4)
	bne.s	.copy
	lea	set_t_empty(pc),a4	; a line without a key
.copy:	move.b	(a4)+,(a2)+
	bne.s	.copy
.next:	cmp.l	a1,a0			; to the start of the next line
	bhs.s	.done
	cmp.b	#10,(a0)+
	bne.s	.next
	bra.s	.line

.done:	moveq	#0,d0
	bra.s	.out
.none:	moveq	#-1,d0
.out:	lea	SET_MAX+2*SET_TOKEN(sp),sp
	movem.l	(sp)+,d1-d7/a0-a6
	rts

; ---------------------------------------------------------------------------
; Settings_text -- a0 = buffer of SET_TEXT_LEN bytes.
Settings_text:
	movem.l	d0-d2/a0-a3,-(sp)
	lea	Settings(pc),a3
	lea	set_t_head(pc),a1
	bsr	set_copy
	tst.b	Settings_found-Settings(a3)
	bne.s	.keys
	lea	set_t_missing(pc),a1
	bsr	set_copy
	bra.s	.end
.keys:	lea	set_table(pc),a2
.key:	move.w	(a2)+,d0
	bmi.s	.bad
	move.b	#' ',(a0)+
	move.l	a2,a1
	bsr	set_copy		; the key
	move.l	a1,a2
	move.b	#'=',(a0)+
	move.b	(a3,d0.w),d1
	ext.w	d1
	bmi.s	.dash
	bra.s	.count
.over:	tst.b	(a2)+			; past one value
	bne.s	.over
.count:	dbf	d1,.over
	move.l	a2,a1
	bsr	set_copy		; its value
	move.l	a1,a2
	bra.s	.rest
.dash:	move.b	#'-',(a0)+
.rest:	bsr	set_skip
	bra.s	.key
.bad:	tst.b	Settings_bad-Settings(a3)
	beq.s	.end
	lea	set_t_unknown(pc),a1
	bsr	set_copy
	lea	Settings_bad-Settings(a3),a1
	bsr	set_copy
.end:	move.b	#13,(a0)+
	move.b	#10,(a0)+
	clr.b	(a0)
	movem.l	(sp)+,d0-d2/a0-a3
	rts

; ---------------------------------------------------------------------------
; set_copy -- the string at a1 to (a0)+, without its null; a1 behind the null.
set_copy:
	move.b	(a1)+,(a0)+
	bne.s	set_copy
	subq.l	#1,a0
	rts

; set_skip -- a2 on a value of a table entry (or on its closing null): a2 to
; the next entry.  Changes d2.
set_skip:
	tst.b	(a2)+
	beq.s	.round
.value:	tst.b	(a2)+
	bne.s	.value
	bra.s	set_skip
.round:	move.l	a2,d2
	addq.l	#1,d2
	and.w	#$FFFE,d2
	move.l	d2,a2
	rts

; set_blanks -- a0 past spaces and tabs, not beyond a1.
set_blanks:
	cmp.l	a1,a0
	bhs.s	.out
	cmp.b	#' ',(a0)
	beq.s	.next
	cmp.b	#9,(a0)
	bne.s	.out
.next:	addq.l	#1,a0
	bra.s	set_blanks
.out:	rts

; set_token -- a word from a0 (not beyond a1) to a2, upper case, at most
; SET_TOKEN-1 characters (the rest is dropped), with a null.  It ends at a
; control character, a blank, "=", ";" or "#".  Changes d0, d2, a2.
set_token:
	moveq	#SET_TOKEN-1,d2
.char:	cmp.l	a1,a0
	bhs.s	.end
	move.b	(a0),d0
	cmp.b	#' ',d0
	bls.s	.end
	cmp.b	#'=',d0
	beq.s	.end
	cmp.b	#';',d0
	beq.s	.end
	cmp.b	#'#',d0
	beq.s	.end
	addq.l	#1,a0
	cmp.b	#'a',d0
	blo.s	.put
	cmp.b	#'z',d0
	bhi.s	.put
	sub.b	#'a'-'A',d0
.put:	tst.w	d2
	beq.s	.char
	move.b	d0,(a2)+
	subq.w	#1,d2
	bra.s	.char
.end:	clr.b	(a2)
	rts

; set_cmp -- the string at a2 (table) against a4 (token): Z set if equal.
; a2 behind the table string's null either way.  Changes d1, d2, a4.
set_cmp:
	moveq	#0,d2
.char:	move.b	(a2)+,d1
	tst.b	d2
	bne.s	.rest
	cmp.b	(a4)+,d1
	beq.s	.rest
	moveq	#1,d2			; differs: on to the end of the string
.rest:	tst.b	d1
	bne.s	.char
	tst.b	d2
	rts

; set_find -- key a5, value a6 in set_table.  Found: d0 = offset of the
; result byte, d1 = number of the value, N clear.  Else d0 = -1, N set.
; Changes d1-d3, a2, a4.
set_find:
	lea	set_table(pc),a2
.key:	move.w	(a2)+,d0
	bmi.s	.out
	move.l	a5,a4
	bsr	set_cmp
	beq.s	.values
	bsr	set_skip
	bra.s	.key
.values:
	moveq	#0,d3
.value:	tst.b	(a2)
	beq.s	.unknown
	move.l	a6,a4
	bsr	set_cmp
	beq.s	.found
	addq.w	#1,d3
	bra.s	.value
.found:	move.w	d3,d1
	tst.w	d0
	rts
.unknown:
	moveq	#-1,d0
.out:	rts

; ---------------------------------------------------------------------------
; The keys: offset of the result byte, the key, its values, an extra null.
	even
set_table:
	dc.w	Settings_music-Settings
	dc.b	"MUSIC",0,"OFF",0,"DSP",0,"CPU",0,"YM",0,0
	even
	dc.w	Settings_plain_st-Settings
	dc.b	"PLAIN_ST",0,"NO",0,"YES",0,0
	even
	dc.w	-1

set_t_head:	dc.b	"AMBER.INF:",0
set_t_missing:	dc.b	" missing, defaults",0
set_t_unknown:	dc.b	"  unknown: ",0
set_t_empty:	dc.b	"=",0

; The results.  In the code section of the includer, written at run time.
Settings:
Settings_music:		dc.b	SET_NONE
Settings_plain_st:	dc.b	SET_NONE
Settings_found:		dc.b	0	; set: the file was there
Settings_bad:		ds.b	SET_TOKEN	; the first unknown key, or empty
	even

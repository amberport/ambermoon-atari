; intro_st_defs.i -- constants of the ST intro layer (intro_st/, docs/05c-ST.md
; "ST intro").  Thalion's program needs nothing from here: it only sees the
; labels K1, K2 and K3 bind it to (tools/intro_st_program.py).

; ---------------------------------------------------------------------------
; Operating system
; ---------------------------------------------------------------------------
Pterm		equ	$4C
Cconws		equ	9
Crawcin		equ	7
Super		equ	$20
Mshrink		equ	$4A
Physbase	equ	2
Logbase		equ	3
Getrez		equ	4
Setscreen	equ	5
Kbdvbase	equ	34
Iorec		equ	14		; XBIOS; device 1 = keyboard
Fcreate		equ	$3C
Fclose		equ	$3E
Fwrite		equ	$40
Fsfirst		equ	$4E
XB_Vsync	equ	37
Setexc		equ	5		; BIOS
ETV_TERM	equ	$102		; vector number of etv_term ($408)
VEK_ABSTURZ	equ	$08		; bus error: crash vectors 2-8 from here
ABSTURZ_VEKTOREN equ	7		; 2-8; line-A/F ($28, $2C) belong to TOS
VEK_VBL		equ	$70
VEK_LEVEL3	equ	$6C		; Thalion's VBL (Amiga level 3, VBR 0)
VEK_TRAP0	equ	$80		; Thalion's main program runs here
VEK_TRAP8	equ	$A0		; K2
VEK_TIMERB	equ	$120
FRCLOCK		equ	$466		; _frclock: TOS waits on it (Vsync, bombs)
COOKIES		equ	$5A0

; ---------------------------------------------------------------------------
; ST hardware
; ---------------------------------------------------------------------------
ST_PAL		equ	$FFFF8240	; 16 words
VBASE_HIGH	equ	$FFFF8201
VBASE_MID	equ	$FFFF8203
VBASE_LOW	equ	$FFFF820D	; STE only; a write to HIGH or MID clears it
VID_CNT		equ	$FFFF8205	; video counter hi, mid ($8207), lo ($8209)
SYNC_MODE	equ	$FFFF820A	; bit 1: 1 = 50 Hz, 0 = 60 Hz
MSTE_CLOCK	equ	$FFFF8E21	; Mega STE only: bit 0 16 MHz, bit 1 cache
MFP_IERA	equ	$FFFFFA07	; Timer B is bit 0 in all four
MFP_IPRA	equ	$FFFFFA0B
MFP_ISRA	equ	$FFFFFA0F
MFP_IMRA	equ	$FFFFFA13
MFP_TBCR	equ	$FFFFFA1B
MFP_TBDR	equ	$FFFFFA21
TB_EVENT_COUNT	equ	8		; TBCR: event count (one event per line)
MCH_STE		equ	1		; _MCH high word: 0 ST, 1 STE family
MCH_MSTE	equ	$00010010

; ---------------------------------------------------------------------------
; The Amiga registers Thalion's intro uses, as offsets into the shadow
; block Amiga_register (K1).  Reads find what the layer put there: DMACONR
; 0 (the blitter is never busy, K2 blits at once), JOY0DAT and POTGOR from
; the mouse vector.
; ---------------------------------------------------------------------------
AR_DMACONR	equ	$002
AR_JOY0DAT	equ	$00A
AR_POTGOR	equ	$016
AR_BLTCON0	equ	$040
AR_BLTCON1	equ	$042
AR_BLTAFWM	equ	$044
AR_BLTALWM	equ	$046
AR_BLTCPT	equ	$048
AR_BLTBPT	equ	$04C
AR_BLTAPT	equ	$050
AR_BLTDPT	equ	$054
AR_BLTSIZE	equ	$058
AR_BLTCMOD	equ	$060
AR_BLTBMOD	equ	$062
AR_BLTAMOD	equ	$064
AR_BLTDMOD	equ	$066
AR_BLTCDAT	equ	$070
AR_BLTBDAT	equ	$072
AR_BLTADAT	equ	$074
AR_COP1LC	equ	$080
AR_DIWSTRT	equ	$08E
AR_DIWSTOP	equ	$090
AR_DMACON	equ	$096
AR_SPR0PT	equ	$120		; 8 long words
AR_BPLCON0	equ	$100
AR_BPL1MOD	equ	$108
AR_COLOR00	equ	$180		; 32 words $0RGB
AR_SIZE		equ	$200

; ---------------------------------------------------------------------------
; The picture
;
; Thalion draws Amiga screens (row-interleaved planes, 40 bytes a plane
; row); the layer converts what the copper list shows into two ST screens
; (low resolution, 160 bytes a line, four planes word-interleaved).
;
; ST line 0 = Amiga raster line $2C, the top of every scene (S1: intro and
; menu top-aligned).  Twinlake's moving window (DIWSTRT) shifts the picture
; on the ST screen as on the Amiga.  The lower border is open (as in the
; fairy, T93), so the ST shows lines 0..230 on the user's monitor: the
; space scene (236 lines) nearly whole, the menu down to row 230.
; ---------------------------------------------------------------------------
RASTER_TOP	equ	$2C		; Amiga raster line of ST line 0
ST_LINE		equ	160
ST_LINES	equ	248		; per screen; the opened border shows ~246
ST_SCREEN	equ	ST_LINES*ST_LINE
AMIGA_ROW	equ	40		; bytes of one plane row
FOLLOW_ROWS	equ	24		; rows of the shown picture per VBL

; Target screens (TARGET_ST.S): Thalion's screens of every scene, kept in
; ST format and shown directly (E30, docs/05c-ST.md "The intro without live
; conversion")
AMIGA_LINE	equ	4*AMIGA_ROW	; a row of a four-plane screen, = ST_LINE
TARGET_MAX	equ	2		; target screens at most
TARGET_MARGIN	equ	16		; black lines above and below each one
TARGET_SIZE	equ	(2*TARGET_MARGIN+ST_LINES)*ST_LINE	; 256-aligned
; what plane 4 of a five-plane screen is (SC_MODE)
MODE_FOUR	equ	0		; four planes, no plane 4
MODE_STARS	equ	1		; the logo phase: stars, only in the target
MODE_TEXT	equ	2		; the menu: text, the buffer holds it
LOGO_STARS	equ	150		; Thalion's stars in the logo phase ($1A5C)
STAR_ENTRY	equ	8		; a star in the target: address, mask,
					; Thalion's offset of its word
STAR_LIST	equ	2+LOGO_STARS*STAR_ENTRY	; count, the stars

; Lower border (tools/st_rand/untrand.s, T93 passed 2026-10-23; the same
; values and code as fantasy_st/FANTASY_ST.S Tb_border)
ST_BORDER		equ	199		; last line before the border
LEAD		equ	8		; Timer B this many lines before ST_BORDER
DELAY_PRE	equ	46		; nops from the sync to 60 Hz
DELAY		equ	18		; nops at 60 Hz
SYNC_START	equ	ST_BORDER*ST_LINE	; line ST_BORDER
SYNC_FROM		equ	SYNC_START+8	; read the counter from here on
SYNC_K		equ	62		; shift count when read at the line start
WAIT_BORDER	equ	200		; poll rounds before giving up (~15 lines)

; SCENE n -- with SCENE_LOG, note scene n's VBL (INTRO_ST.S Scene_mark).
SCENE	macro
	ifd	SCENE_LOG
	move.w	#\1,Scene_id
	jsr	Scene_mark
	endc
	endm

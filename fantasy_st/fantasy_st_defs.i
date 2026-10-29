; fantasy_st_defs.i -- what Thalion's FAIRY.S needs and does not bring
; itself, for the ST/STE build (docs/05c-ST.md, "ST fairy intro, plan").
;
; The constants of FAIRY.S (planes, bpscanl ...) come from
; build/fantasy_werte.i (tools/fantasy_auszug.py), as on the Falcon.

; ---------------------------------------------------------------------------
; waitblit -- on the Amiga "wait until the blitter is free".  Here
; Blitter_wait takes the blit FAIRY.S last set up in Amiga_register and
; draws it in ST format (FANTASY_ST.S).  All registers stay.
; ---------------------------------------------------------------------------
waitblit	macro
		jsr	Blitter_wait
		endm

; ---------------------------------------------------------------------------
; Operating system
; ---------------------------------------------------------------------------
Pterm0		equ	0
Cconws		equ	9
Crawcin		equ	7
Super		equ	$20
Physbase	equ	2
Logbase		equ	3
Getrez		equ	4
Setscreen	equ	5
Malloc		equ	$48
Mfree		equ	$49
Mshrink		equ	$4A
Kbdvbase	equ	34
XB_Vsync	equ	37
Setexc		equ	5		; BIOS
ETV_TERM	equ	$102		; vector number of etv_term ($408)
VEK_ABSTURZ	equ	$08		; bus error: crash vectors 2-8 from here
ABSTURZ_VEKTOREN equ	7		; 2-8; line-A/F ($28, $2C) belong to TOS
VEK_VBL		equ	$70
VEK_TIMERB	equ	$120
FRCLOCK		equ	$466		; _frclock: TOS waits on it (Vsync, bombs)
COOKIES		equ	$5A0

; ---------------------------------------------------------------------------
; ST hardware
; ---------------------------------------------------------------------------
ST_PAL		equ	$FFFF8240	; 16 words
VBASE_HIGH	equ	$FFFF8201
VBASE_MID	equ	$FFFF8203
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
; The Amiga registers FAIRY.S writes, as offsets into the shadow block
; Amiga_register (K1, tools/fairy_umbiegen.py).
; ---------------------------------------------------------------------------
AR_BLTCON0	equ	$40
AR_BLTCON1	equ	$42
AR_BLTAFWM	equ	$44
AR_BLTALWM	equ	$46
AR_BLTCPT	equ	$48
AR_BLTBPT	equ	$4C
AR_BLTAPT	equ	$50
AR_BLTDPT	equ	$54
AR_BLTSIZE	equ	$58
AR_BLTCMOD	equ	$60
AR_BLTBMOD	equ	$62
AR_BLTAMOD	equ	$64
AR_BLTDMOD	equ	$66
AR_BLTBDAT	equ	$72
AR_INTREQ	equ	$9C
AR_SPR0PT	equ	$120		; 8 long words
AR_COLOR00	equ	$180		; 32 words $0RGB
AR_SIZE	equ	$200

; ---------------------------------------------------------------------------
; The picture
;
; Thalion draws into one Amiga buffer nobody shows (workbase): 320 x 256,
; planes planes, bpscanl bytes a row.  Its big stars reach 8 rows below
; row 255 (fee_vorspann.i), hence the overflow.
;
; The ST shows low resolution, 160 bytes a line.  Picture position B (user
; 2026-10-23): ST line 0 = Amiga row AMIGA_FIRST, the lower border opened
; below ST line ST_BORDER (T93: DELAY 18, LEAD 8), so ST lines 0..233 carry
; Amiga rows 22..255; the user's monitor shows lines 0..230.  Each screen
; holds ST_LINES lines, the rest below the picture stays black.
; ---------------------------------------------------------------------------
AMIGA_ROWS	equ	256
AMIGA_SCREEN	equ	AMIGA_ROWS*bpscanl
AMIGA_OVERFLOW	equ	10*bpscanl
AMIGA_FIRST	equ	22		; Amiga row of ST line 0
ST_LINE	equ	160
ST_PICTURE_LINES	equ	AMIGA_ROWS-AMIGA_FIRST	; 234 lines with picture
ST_LINES	equ	248		; per screen; the opened border shows ~246
ST_SCREEN	equ	ST_LINES*ST_LINE
; From this Amiga row on the copper list loads seven colours from
; Palette_unten (wait for raster line $AE, picture start $28: docs/11,
; 3.3); everything that moves lies below it.  On the ST: Timer B.
SPLIT_ROW	equ	$AE-$28
ST_SPLIT	equ	SPLIT_ROW-AMIGA_FIRST	; 112, first line of the lower band
PLOT_BYTES	equ	(AMIGA_ROWS-SPLIT_ROW)*bpscanl	; workbase from row 134

; Lower border (tools/st_rand/untrand.s, T93 passed 2026-10-23)
ST_BORDER		equ	199		; last line before the border
LEAD		equ	8		; Timer B this many lines before ST_BORDER
DELAY_PRE	equ	46		; nops from the sync to 60 Hz
DELAY		equ	18		; nops at 60 Hz
SYNC_START	equ	ST_BORDER*ST_LINE	; line ST_BORDER
SYNC_FROM		equ	SYNC_START+8	; read the counter from here on
SYNC_K		equ	62		; shift count when read at the line start
WAIT_BORDER	equ	200		; poll rounds before giving up (~15 lines)
WAIT_SPLIT	equ	40		; poll rounds for the split (~3 lines)

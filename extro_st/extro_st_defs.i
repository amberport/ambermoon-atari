; extro_st_defs.i -- constants of the ST extro layer (extro_st/, docs/05c-ST.md
; "ST extro").  Thalion's program needs nothing from here: it only sees the
; labels K1, K2 and K3 bind it to (tools/extro_st_program.py).  The values
; are those of intro_st/intro_st_defs.i, where both have them.

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
XB_Vsync	equ	37
Setexc		equ	5		; BIOS
ETV_TERM	equ	$102		; vector number of etv_term ($408)
VEK_ABSTURZ	equ	$08		; bus error: crash vectors 2-8 from here
ABSTURZ_VEKTOREN equ	7		; 2-8; line-A/F ($28, $2C) belong to TOS
VEK_VBL		equ	$70
VEK_LEVEL3	equ	$6C		; Thalion's VBL (Amiga level 3, VBR 0)
VEK_TRAP0	equ	$80		; Thalion's main program runs here
VEK_TRAP8	equ	$A0		; K2
FRCLOCK		equ	$466		; _frclock: TOS waits on it (Vsync, bombs)
COOKIES		equ	$5A0

; ---------------------------------------------------------------------------
; ST hardware
; ---------------------------------------------------------------------------
ST_PAL		equ	$FFFF8240	; 16 words
VBASE_HIGH	equ	$FFFF8201
VBASE_MID	equ	$FFFF8203
SYNC_MODE	equ	$FFFF820A	; bit 1: 1 = 50 Hz, 0 = 60 Hz
MCH_STE		equ	1		; _MCH high word: 0 ST, 1 STE family
MCH_MSTE	equ	$00010010

; ---------------------------------------------------------------------------
; The Amiga registers Thalion's extro uses, as offsets into the shadow
; block Amiga_register (K1).  Reads find what the layer put there: DMACONR
; 0 (the blitter is never busy), POTGOR from the mouse vector.
; ---------------------------------------------------------------------------
AR_DMACONR	equ	$002
AR_JOY0DAT	equ	$00A
AR_POTGOR	equ	$016
AR_BLTSIZE	equ	$058
AR_COP1LC	equ	$080
AR_COLOR00	equ	$180		; 32 words $0RGB
AR_SIZE		equ	$200

; ---------------------------------------------------------------------------
; The picture (S1, docs/11 7.9): Thalion's screens have 256 rows; the ST
; shows rows ST_FIRST..ST_FIRST+199 (extro_st_data.i), centred as on the
; Falcon at VGA.  Three ST screens, low resolution, 160 bytes a line.
; ---------------------------------------------------------------------------
ST_LINE		equ	160
ST_LINES	equ	200
ST_SCREEN	equ	ST_LINES*ST_LINE
ST_SCREENS	equ	3		; in turn (EXTRO_ST.S)

; The variables of Thalion's flow (hunk 5)
H5_COUNT	equ	$04		; .l VBL counter (Thalion's VBL)
H5_FAST		equ	$3E		; .w the closing text: one VBL a step
THALION_VBL	equ	$F26		; Thalion's level-3 handler

; ---------------------------------------------------------------------------
; The text mask (TEXT_ST.S): Thalion's 6:$320, 278 rows of 40 bytes; rows
; 0..255 lie over the screen, the writer puts new lines from row 256.  Ours
; is a ring: the scroll moves its top instead of the rows.
; ---------------------------------------------------------------------------
MASK_ROW	equ	40
MASK_ROWS	equ	278
MASK_WRITE	equ	256		; the writer's first row ($2B20)
MASK_SLACK	equ	32		; a text line with CR may write below 277
RING_ROWS	equ	2*MASK_ROWS+MASK_SLACK

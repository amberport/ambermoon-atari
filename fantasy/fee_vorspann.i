; fee_vorspann.i -- what Thalion's FAIRY.S needs and does not bring itself,
; for the Falcon build.
;
; The constants (planes, bpscanl ...) the build writes from the binary into
; build/fantasy_werte.i (tools/fantasy_auszug.py).  Here only what must
; differ from the Amiga.

; ---------------------------------------------------------------------------
; waitblit -- on the Amiga "wait until the blitter is free".  Here
; Blitter_warten takes the blit FAIRY.S last set up in Amiga_register and
; draws it in Falcon format (FEE_SUP.S).  All registers stay.
; ---------------------------------------------------------------------------
waitblit	macro
		jsr	Blitter_warten
		endm

; ---------------------------------------------------------------------------
; Betriebssystem
; ---------------------------------------------------------------------------
Pterm0		equ	0
Cconws		equ	9
Crawcin		equ	7
Super		equ	$20
Fcreate		equ	$3C
Fclose		equ	$3E
Fwrite		equ	$40
Mxalloc		equ	$44
Mfree		equ	$49
Mshrink		equ	$4A
Physbase	equ	2
Setscreen	equ	5
Kbdvbase	equ	34
XB_Vsync	equ	37
VsetMode	equ	88
mon_type	equ	89
Setexc		equ	5		; BIOS
ETV_TERM	equ	$102		; Vektornummer von etv_term ($408)
VEK_ABSTURZ	equ	$08		; Busfehler: die Absturzvektoren 2-8 ab hier
ABSTURZ_VEKTOREN equ	7		; 2-8; Line-A/F ($28, $2C) braucht TOS

; Moduswort (VsetMode)
VM_BPS8		equ	$0003
VM_VGA		equ	$0010
VM_PAL		equ	$0020
VM_VERTFLAG	equ	$0100

; ---------------------------------------------------------------------------
; Falcon-Hardware
; ---------------------------------------------------------------------------
VIDEL_PAL	equ	$FFFF9800	; 256 Langworte $RRGG00BB (RASTER.S)
ST_PAL		equ	$FFFF8240	; 16 Worte
V_BASIS_H	equ	$FFFF8201
V_BASIS_M	equ	$FFFF8203
V_BASIS_L	equ	$FFFF820D
V_VFT		equ	$FFFF82A2	; senkrecht, in Halbzeilen
V_VBB		equ	$FFFF82A4
V_VBE		equ	$FFFF82A6
V_VDB		equ	$FFFF82A8
V_VDE		equ	$FFFF82AA
V_VSS		equ	$FFFF82AC
VEK_VBL		equ	$70
FRCLOCK		equ	$466		; _frclock: TOS wartet darauf (Vsync, Bomben)

; ---------------------------------------------------------------------------
; Die Amiga-Register, die FAIRY.S anspricht, als Versatz im Schattenblock
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
AR_BLTCDAT	equ	$70
AR_BLTBDAT	equ	$72
AR_BLTADAT	equ	$74
AR_INTREQ	equ	$9C
AR_SPR0PT	equ	$120		; 8 Langworte
AR_COLOR00	equ	$180		; 32 Worte $0RGB
AR_GROESSE	equ	$200

; ---------------------------------------------------------------------------
; The picture (E30, user 2026-10-25: the fantasy intro in Falcon format)
;
; Thalion draws into one Amiga buffer nobody shows (workbase): 320 x 256,
; planes planes, bpscanl bytes a row.  What shows is two Falcon screens of
; all 256 Amiga rows, 8 planes word-interleaved, row for row; the Videl
; shows Anzeige_zeilen of them from Anzeige_erste.  Plane 5 carries the
; colour bank (0 above WECHSELZEILE, 1 from there, in the background data),
; planes 6 and 7 are 0.
; ---------------------------------------------------------------------------
AMIGA_ZEILEN	equ	256
AMIGA_SCHIRM	equ	AMIGA_ZEILEN*bpscanl
; Thalion's big stars (blit_star, 9 rows) are dropped only from row 256 and
; reach 8 rows below the screen; nothing writes the Amiga buffer any more,
; the overflow keeps the address range as it was.
AMIGA_UEBERLAUF	equ	10*bpscanl
FALCON_ZEILE	equ	320		; 8 Ebenen wortverschachtelt
FALCON_SCHIRM	equ	AMIGA_ZEILEN*FALCON_ZEILE
; Below each Falcon screen 16 rows nobody shows, for a star that reaches
; below row 255; 16 keeps the second screen on a 256-byte boundary.
FALCON_UEBERLAUF equ	16*FALCON_ZEILE
FALCON_ABSTAND	equ	FALCON_SCHIRM+FALCON_UEBERLAUF
GRUPPEN		equ	FALCON_ZEILE/16	; 16-Punkte-Gruppen je Zeile
; Ab dieser Bildzeile laedt die Copperliste sechs Farben aus Palette_unten
; (Warten auf Rasterzeile $AE, Bildbeginn $28: docs/11, 3.3).  Everything
; that moves lies below it.
WECHSELZEILE	equ	$AE-$28
PLOT_BYTES	equ	(AMIGA_ZEILEN-WECHSELZEILE)*bpscanl	; workbase from row 134
UNTEN_BYTES	equ	(AMIGA_ZEILEN-WECHSELZEILE)*FALCON_ZEILE	; the lower band

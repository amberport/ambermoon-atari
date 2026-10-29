; fee_vorspann.i -- was Thalions FAIRY.S voraussetzt und nicht selbst
; mitbringt.
;
; Die Konstanten (planes, bpscanl ...) schreibt der Bau aus dem Binaercode
; nach build/fantasy_werte.i (tools/fantasy_auszug.py).  Hier steht nur,
; was bei uns anders sein muss als auf dem Amiga.

; ---------------------------------------------------------------------------
; waitblit -- auf dem Amiga "warten, bis der Blitter frei ist".  Bei uns gibt
; es keinen Blitter, der nebenher laeuft; Blitter_warten fuehrt den zuletzt
; eingetragenen Blit aus (FEE_SUP.S).  Alle Register bleiben.
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

; Der Blitter (Falcon, STE, Mega ST; nicht im einfachen ST).  Nur zwei
; Quellen: Quelle und Ziel (dazu das Halbtonmuster, hier unbenutzt).
BL_SRC_XINC	equ	$FFFF8A20
BL_SRC_YINC	equ	$FFFF8A22
BL_SRC		equ	$FFFF8A24
BL_MASKE1	equ	$FFFF8A28	; erstes Wort der Zeile (und das einzige)
BL_MASKE2	equ	$FFFF8A2A
BL_MASKE3	equ	$FFFF8A2C	; letztes Wort
BL_DST_XINC	equ	$FFFF8A2E
BL_DST_YINC	equ	$FFFF8A30
BL_DST		equ	$FFFF8A32
BL_XCOUNT	equ	$FFFF8A36
BL_YCOUNT	equ	$FFFF8A38
BL_HOPOP	equ	$FFFF8A3A	; Wort: HOP im oberen, OP im unteren Byte
BL_STEUER	equ	$FFFF8A3C	; Bit 7 BUSY, Bit 6 HOG
BL_SKEW		equ	$FFFF8A3D	; Bit 7 FXSR, Bit 6 NFSR, 0-3 Verschiebung
BL_BUSY		equ	$80		; starten (ohne HOG: Bus geteilt)
BL_HOG		equ	$40		; der Blitter behaelt den Bus bis zum Ende
BL_FXSR		equ	$80
HOP_QUELLE	equ	2
OP_KOPIE	equ	3		; S
OP_STANZEN	equ	4		; ~S & D
OP_ODER		equ	7		; S | D

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
; Das Bild
; ---------------------------------------------------------------------------
AMIGA_ZEILEN	equ	256		; 320 x 256, planes Ebenen, bpscanl je Zeile
AMIGA_SCHIRM	equ	AMIGA_ZEILEN*bpscanl
; Thalions grosse Sterne (blit_star, 9 Zeilen) werden erst ab Zeile 256
; verworfen und ragen bis 8 Zeilen unter den Schirm.  Im Original liegen
; die beiden Schirme wie bei uns hintereinander (Hunk 4 ab $320); was unter
; den zweiten faellt, ging dort hinter den Hunk.  Bei uns laege dort der
; Falcon-Schirm (Grafikmuell oben, Nutzer 2026-10-02): darum ein Puffer.
AMIGA_UEBERLAUF	equ	10*bpscanl
FALCON_ZEILE	equ	320		; 8 Ebenen wortverschachtelt
FALCON_SCHIRM	equ	AMIGA_ZEILEN*FALCON_ZEILE
GRUPPEN		equ	FALCON_ZEILE/16	; 16-Punkte-Gruppen je Zeile
; Ab dieser Bildzeile laedt die Copperliste sechs Farben aus Palette_unten
; (Warten auf Rasterzeile $AE, Bildbeginn $28: docs/11, 3.3).
WECHSELZEILE	equ	$AE-$28

	include	"amiga_strahl.i"	; Schalter STRAHL

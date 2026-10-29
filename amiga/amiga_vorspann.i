; amiga_vorspann.i -- Konstanten der Amiga-Schicht (AMIGA_RAHMEN.S) unter
; Thalions Intro und Extro (docs/11-Intro-Extro.md 4 und 5).
;
; Betriebssystem, Falcon und Blitter wie in fantasy/fee_vorspann.i.

; ---------------------------------------------------------------------------
; Betriebssystem
; ---------------------------------------------------------------------------
Pterm0		equ	0
Cconws		equ	9
Crawcin		equ	7
Super		equ	$20
Fopen		equ	$3D
Fclose		equ	$3E
Fread		equ	$3F
Pterm		equ	$4C
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

VM_BPS8		equ	$0003
VM_VGA		equ	$0010
VM_PAL		equ	$0020
VM_VERTFLAG	equ	$0100

; ---------------------------------------------------------------------------
; Falcon-Hardware
; ---------------------------------------------------------------------------
VIDEL_PAL	equ	$FFFF9800	; 256 Langworte $RRGG00BB
ST_PAL		equ	$FFFF8240	; 16 Worte
V_BASIS_H	equ	$FFFF8201
V_BASIS_M	equ	$FFFF8203
V_BASIS_L	equ	$FFFF820D
V_ZAEHL_H	equ	$FFFF8205	; video counter: where the Videl reads
V_ZAEHL_M	equ	$FFFF8207
V_ZAEHL_L	equ	$FFFF8209
V_VFC		equ	$FFFF82A0	; vertical counter (assumed: half-lines, T62)
V_VFT		equ	$FFFF82A2	; vertical frame total, half-lines
V_VBB		equ	$FFFF82A4
V_VBE		equ	$FFFF82A6
V_VDB		equ	$FFFF82A8
V_VDE		equ	$FFFF82AA
V_VSS		equ	$FFFF82AC
VEK_LEVEL3	equ	$6C		; Amiga-VBL bei VBR 0 (Thalion setzt ihn)
VEK_VBL		equ	$70
FRCLOCK		equ	$466		; _frclock: TOS wartet darauf (Vsync, Bomben)
VEK_TRAP0	equ	$80		; Thalion biegt ihn auf sein Hauptprogramm
VEK_TRAP8	equ	$A0		; K2: BLTSIZE schreiben

BL_SRC_XINC	equ	$FFFF8A20
BL_SRC_YINC	equ	$FFFF8A22
BL_SRC		equ	$FFFF8A24
BL_MASKE1	equ	$FFFF8A28
BL_MASKE2	equ	$FFFF8A2A
BL_MASKE3	equ	$FFFF8A2C
BL_DST_XINC	equ	$FFFF8A2E
BL_DST_YINC	equ	$FFFF8A30
BL_DST		equ	$FFFF8A32
BL_XCOUNT	equ	$FFFF8A36
BL_YCOUNT	equ	$FFFF8A38
BL_HOPOP	equ	$FFFF8A3A	; Wort: HOP oben, OP unten
BL_STEUER	equ	$FFFF8A3C	; Bit 7 BUSY
BL_SKEW		equ	$FFFF8A3D
BL_BUSY		equ	$80		; starten (ohne HOG: Bus geteilt)
BL_HOG		equ	$40		; der Blitter haelt den Bus bis zum Ende
; HOP (oben) und OP (unten) zusammen: Kopie aus der Quelle; alles 0 oder 1
; ohne Quelle (HOP 0 liest nichts)
HOPOP_KOPIE	equ	$0203
HOPOP_NULL	equ	$0000
HOPOP_EINS	equ	$000F

; ---------------------------------------------------------------------------
; Amiga-Register als Versatz im Schattenblock Amiga_register (K1)
; ---------------------------------------------------------------------------
AR_DMACONR	equ	$02
AR_JOY0DAT	equ	$0A
AR_POTGOR	equ	$16
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
AR_COP1LC	equ	$80
AR_DIWSTRT	equ	$8E
AR_DIWSTOP	equ	$90
AR_DMACON	equ	$96		; zuletzt geschriebener Wert (SET/CLR)
AR_BPLCON0	equ	$100
AR_BPL1MOD	equ	$108
AR_SPR0PT	equ	$120
AR_SPR1PT	equ	$124
AR_COLOR00	equ	$180
AR_GROESSE	equ	$200

; ---------------------------------------------------------------------------
; Das Bild
; ---------------------------------------------------------------------------
AMIGA_OBEN	equ	$2C		; erste Bildzeile (DIWSTRT $2C81, $289A)
AMIGA_WORTE	equ	20		; 320 Punkte je Ebene und Zeile
FALCON_ZEILE	equ	320		; 8 Ebenen wortverschachtelt
FALCON_HOEHE	equ	256
FALCON_SCHIRM	equ	FALCON_HOEHE*FALCON_ZEILE
; Abstand der beiden Falcon-Schirme.  Mit STRAHL eine Luecke: Sonst steht
; das Ende des einen Schirms dort, wo der andere anfaengt, und die Messung
; Tk_vbl koennte beides nicht trennen.
	IFD	STRAHL
FALCON_LUECKE	equ	32*FALCON_ZEILE
	ELSE
FALCON_LUECKE	equ	0
	ENDC
ROLLZEILEN	equ	32		; je VBL nachgefuehrte Zeilen
; Lines the beam may run through while ROLLZEILEN lines are converted: a
; band at least this far ahead of the beam is finished before the beam gets
; there (Roll_strahl, T28).  An estimate, not measured: the beam passes
; some 25-45 lines meanwhile.
ROLL_VORLAUF	equ	64
; How often a copper list may wait for BPLCON0 (Anzeige_nachfuehren, T62):
; Thalion sets the registers one VBL after the list, so two waits are
; expected (the K3 at $24BE, the VBL in Thalion's $288A).
LISTE_WARTEN	equ	3

; ---------------------------------------------------------------------------
; Schirme im Zielformat (AMIGA_ZIEL.S, docs/11 7.8).  Das Format nennen drei
; Werte; der ST bekaeme 4, 160, 8 (und ZIEL_SCHIRM dazu), der Code bleibt.
; ---------------------------------------------------------------------------
ZIEL_SCHIRME	equ	1		; Amiga_blit lenkt um (AMIGA_BLIT.S)
ZIEL_EBENEN	equ	8
ZIEL_ZEILE	equ	FALCON_ZEILE	; Bytes je Bildzeile
ZIEL_WORT	equ	16		; von einem 16-Punkte-Wort zum naechsten
ZIEL_SCHIRM	equ	FALCON_SCHIRM
; Black lines above and below each target screen, kept 0 like the lines
; below its SCH_ZEILEN: a window shorter than the display, or moved off its
; top (the intro's Twinlake shakes up to 8 lines down and 3 up), is then
; shown directly.
ZIEL_RAND_ZEILEN	equ	16
ZIEL_RAND	equ	ZIEL_RAND_ZEILEN*ZIEL_ZEILE
AMIGA_EBENE	equ	AMIGA_WORTE*2	; Bytes einer Ebene in einer Amiga-Zeile
SCH_MAX		equ	2		; hoechstens so viele Schirme direkt

; Ein Eintrag der Schirmtabelle des Programms (Makro SCHIRM, Ende dc.l 0).
; Das Programm nennt Adresse, Zeilen und Ebenen; den Rest rechnet
; Schirme_anlegen.  Thalions Amiga-Schirm bleibt als Zwischenspeicher: Eine
; Zeile dort gilt, wenn ihr Merker in SCH_GUELTIG gesetzt ist.
SCH_AMIGA	equ	0		; .l Thalions Schirm (Ebenen zeilenweise)
SCH_ZEILEN	equ	4		; .w
SCH_EBENEN	equ	6		; .w 1-5
SCH_ENDE	equ	8		; .l hinter dem Amiga-Schirm
SCH_ZIEL	equ	12		; .l der Schirm im Zielformat
SCH_GUELTIG	equ	16		; .l je Zeile ein Byte: Amiga = Ziel
SCH_BANK	equ	20		; .l zuletzt gesetzte Bankteilung
SCH_BPR		equ	24		; .w Bytes je Amiga-Zeile
SCH_UNGUELTIG	equ	26		; .b eine Zeile gilt nicht
SCH_LAENGE	equ	28

SCHIRM		macro			; Adresse, Zeilen, Ebenen
	dc.l	\1
	dc.w	\2,\3
	dcb.b	SCH_LAENGE-8,0
	endm
ZG_MAX		equ	32		; hoechstens so viele Zeilen Zeiger (I3)

	include	"amiga_strahl.i"	; Schalter STRAHL

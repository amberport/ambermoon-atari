; ***************************************************************************
; INTRO_ZOOM.S -- unser Zoom fuer Thalions Intro (K3, tools/amiga_programm.py;
; docs/11-Intro-Extro.md).
;
; Thalions Zoom (Hunk 0, $1BAE) beschneidet gegen das Fenster, rechnet die
; Schritttabellen fuer Zeilen und Spalten (bsr $2314) und zieht das Bild
; dann mit dem Blitter auf: je Zielzeile ein Blit in einen Zwischenpuffer,
; dann je Zielspalte ein Blit, ein Wort breit, ueber die ganze Hoehe mal
; vier Ebenen, der ein einziges Bit setzt.  Auf dem Amiga ist das billig.
; Bei uns rechnet die CPU jeden Blit nach, und jedes Zielwort wird bis zu
; 16-mal gelesen und geschrieben.
;
; Fuer die Vorspaenne darf Leitziel 1 an Engstellen weichen (Nutzer,
; 2026-10-04).  Beschnitt und Tabellen bleiben Thalions; ab $1C98 springt
; der Bau hierher (K3).  Wir schreiben dasselbe Ergebnis in denselben
; Schirm, aber jedes Zielwort nur einmal:
;   1. Zm_wandeln: die Quelle als Farbnummern (mal 4), je Zeile vorn eine 0,
;   2. Zm_falten:  je Zielwort 16 Punkte ueber die Spaltenkarte holen und
;                  zu vier Ebenenworten und einer Maske falten (Zm_linie),
;   3. Zm_setzen:  die Linie mit der Maske in Thalions Schirm setzen.
;      Is the screen in the target format (docs/11 7.8, the 4-plane
;      scenes), Zm_setzen_ziel writes the target instead, and the buffer
;      lines are no longer valid.  ZOOM_PRUEF compares buffers only, so it
;      says nothing about those zooms.
; Gehoert die naechste Zielzeile zur selben Quellzeile (Vergroessern), wird
; nur 3. wiederholt.
;
; Die Quellbilder liegen in Thalions Datenhunks 2-4 und aendern sich nicht.
; Darum wird ein solches Bild beim ersten Zoom ganz gewandelt und bleibt in
; Zm_lager (Zm_quelle_suchen); sonst kostete jede Zielzeile eine ganze
; Quellzeile, bei kleinen Planeten das Vielfache des Faltens.  Liegt die
; Quelle anderswo, wird je Zeile gewandelt.  Dass die Bilder wirklich fest
; sind, belegt ZOOM_PRUEF: es vergleicht mit Thalions Weg aus der Quelle.
;
; Thalions Ergebnis, nachgelesen ($1CA8-$2312): Mit Maske (d2 <> 0) bleibt
; der Schirm, wo der Quellpunkt Farbe 0 hat, sonst wird jeder Zielpunkt im
; beschnittenen Rechteck gesetzt.  Zielzeile i nimmt Quellzeile
; $11D02 + Summe der ersten i Zeilenschritte; die rechte Zielspalte nimmt
; Quellspalte Breite - 1 - $11D06, jede weitere nach links einen
; Spaltenschritt weniger.  Thalions Zwischenpuffer ($12122, $12126) liest
; ausser dem Zoom niemand; wir brauchen sie nicht.
;
; Vertrag ($1BAE): d0/d1 = x/y, d6/d7 = Breite/Hoehe, d2 = Maske, Quelle
; und Quellgroesse in Hunk 5.  Thalions Routine veraendert alle Register
; ausser a7; die drei Aufrufer ($64C Planeten, $BD8 Meteor, $1536 Logos
; beim Start) sichern selbst, was sie brauchen.  Unsere ebenso.
;
; Schalter: ZOOM_THALION nimmt immer Thalions Weg (zum Vergleich der
; Laufzeit).  ZOOM_PRUEF (mit AMIGA_MESSEN) laesst jeden Zoom erst Thalions
; Weg gehen, dann unseren, und vergleicht die Zeilen (Zp_text).
; ***************************************************************************

ZM_BASIS	equ	$11CF0		; Thalions Zoomvariablen in Hunk 5, ab hier:
ZM_X		equ	0		; Ziel-x, beschnitten
ZM_Y		equ	2		; Ziel-y, beschnitten
ZM_QBREITE	equ	4		; Quellbreite
ZM_QHOEHE	equ	6		; Quellhoehe
ZM_ZHOEHE	equ	8		; Zielhoehe vor dem Beschnitt
ZM_ZBREITE	equ	$A		; Zielbreite vor dem Beschnitt
ZM_ZEILEN	equ	$C		; Zielzeilen nach dem Beschnitt
ZM_SPALTEN	equ	$E		; Zielspalten nach dem Beschnitt
ZM_QZEILE	equ	$12		; erste Quellzeile
ZM_RECHTS	equ	$16		; rechts uebergangene Quellspalten
ZM_MASKE	equ	$1C		; <> 0: Farbe 0 laesst den Schirm stehen
ZM_QUELLE	equ	$1E		; Quellbild, je Zeile vier Ebenen
ZM_SPALTENTAB	equ	$22		; ($11D12) Spaltenschritte, von rechts
ZM_ZEILENTAB	equ	$2A2		; ($11F92) Zeilenschritte
ZM_SCHIRM	equ	$18		; in Hunk 5: Zeiger auf Thalions Zeichenschirm
ZM_ZEILE	equ	160		; Bytes je Schirmzeile: 4 Ebenen zu 40
ZM_EBENE	equ	40
ZM_MAXBREITE	equ	512		; breitere Quellen nimmt Thalions Weg
ZM_MAXWORTE	equ	21		; Zielworte je Zeile: (15 + 320 + 15) / 16
ZM_H4_LAENGE	equ	132640		; Hunk 4 (tools/amiga_programm.py)
ZM_LAGER	equ	160*1024	; gewandelte Bilder
ZM_PLAETZE	equ	32		; ... hoechstens so viele
ZL_QUELLE	equ	0		; ein Platz in Zm_plaetze: Quellbild,
ZL_DATEN	equ	4		; gewandelt in Zm_lager (0 = frei),
ZL_BREITE	equ	8		; Quellbreite,
ZL_HOEHE	equ	10		; Quellhoehe,
ZL_SCHRITT	equ	12		; Bytes je gewandelter Zeile
ZL_LAENGE	equ	16

	SECTION	Intro_code,code

; ***************************************************************************
; Zoom_eigen -- Einsprung aus Thalions Zoom an $1C98 (K3).  Beschnitt und
; Tabellen sind gerechnet, die Zielflaeche ist nicht leer.
; ***************************************************************************
Zoom_eigen:
	IFND	ZOOM_THALION
	cmp.w	#ZM_MAXBREITE,Intro_h5+ZM_BASIS+ZM_QBREITE
	bhi.b	Zoom_thalion
	IFD	ZOOM_PRUEF
	bra	Zp_pruefen
	ELSE
	bra.b	Zoom_neu
	ENDC
	ENDC

; Zoom_thalion -- Thalions Weg ab $1C98, mit dem Befehl, den K3 ersetzt hat.
Zoom_thalion:
	move.w	Intro_h5+$11CF8,d0
	jmp	Intro_h0+$1C9E

; ***************************************************************************
; Zoom_neu -- der Zoom auf unserem Weg.  Veraendert alle Register ausser a7.
; ***************************************************************************
Zoom_neu:
	lea	Intro_h5+ZM_BASIS,a5
	; Spaltenkarte: je Punkt der Zielworte der Versatz in Zm_chunky, also
	; Quellspalte + 1; 0 = ausserhalb des Rechtecks, dort steht Farbe 0
	lea	Zm_karte,a0
	moveq	#15,d1
	and.w	ZM_X(a5),d1		; Vorlauf im ersten Wort
	move.w	ZM_SPALTEN(a5),d2
	move.w	d1,d3
	add.w	d2,d3			; Vorlauf + Spalten
	moveq	#15,d4
	add.w	d3,d4
	lsr.w	#4,d4			; Zielworte
	move.w	d4,Zm_worte
	; Randmasken fuer den Weg ohne Maske: nur im Rechteck setzen
	lea	Zm_rand,a1
	move.w	d4,d0
	subq.w	#1,d0
.rand:	move.w	#-1,(a1)+
	dbf	d0,.rand
	moveq	#-1,d0
	lsr.w	d1,d0
	and.w	d0,Zm_rand		; erstes Wort ab dem Vorlauf
	moveq	#15,d5
	move.w	d3,d6
	subq.w	#1,d6
	and.w	d5,d6
	eor.w	d5,d6			; 15 - letzter Punkt im letzten Wort
	moveq	#-1,d0
	lsl.w	d6,d0
	and.w	d0,-2(a1)		; letztes Wort bis zur letzten Spalte
	; Vorlauf
	bra.b	.v1
.v0:	clr.w	(a0)+
.v1:	dbf	d1,.v0
	; die Spalten, von rechts wie bei Thalion
	move.w	d2,d0
	add.w	d0,d0
	add.w	d0,a0			; hinter der letzten Spalte
	move.l	a0,a1
	move.w	ZM_QBREITE(a5),d5
	sub.w	ZM_RECHTS(a5),d5	; Quellspalte der rechten Zielspalte + 1
	lea	ZM_SPALTENTAB(a5),a2
	subq.w	#1,d2
.spalte:
	move.w	d5,-(a1)
	sub.w	(a2)+,d5
	dbf	d2,.spalte
	; Nachlauf bis zum Ende des letzten Worts
	move.w	d4,d0
	lsl.w	#4,d0
	sub.w	d3,d0
	bra.b	.n1
.n0:	clr.w	(a0)+
.n1:	dbf	d0,.n0

	; Quelle: Ebenenabstand (Breite & -16) / 8, Zeile = 4 Ebenen
	move.w	ZM_QBREITE(a5),d0
	moveq	#15,d1
	add.w	d0,d1
	lsr.w	#4,d1
	move.w	d1,Zm_qworte
	and.w	#-16,d0
	lsr.w	#3,d0
	move.w	d0,Zm_ebene
	add.w	d0,d0
	add.w	d0,d0
	move.w	d0,Zm_qzeile_bytes
	clr.b	Zm_chunky		; Farbe 0 fuer "ausserhalb"
	bsr	Zm_quelle_suchen
	lea	Intro_h5+ZM_BASIS,a5

	; Ziel: Thalions Schirm, Zeile y, Wort von x
	move.l	Intro_h5+ZM_SCHIRM,d0
	bsr	Schirm_suchen
	sne	Zm_im_ziel
	bne.b	.ziel
	move.l	d0,a4
	lea	Intro_h5+ZM_BASIS,a5	; Schirm_suchen took a5
	move.w	ZM_Y(a5),d0
	mulu.w	#ZM_ZEILE,d0
	add.l	d0,a4
	move.w	ZM_X(a5),d0
	lsr.w	#4,d0
	add.w	d0,d0
	add.w	d0,a4
	move.l	a4,Zm_ziel
	move.l	#ZM_ZEILE,Zm_zeilenschritt
	bra.b	.ziel_da
	; The screen is in the target format (docs/11 7.8): the target is
	; written, the buffer lines are no longer valid.
.ziel:	move.l	SCH_ZIEL(a5),a4
	move.w	Intro_h5+ZM_BASIS+ZM_Y,d0
	move.w	Intro_h5+ZM_BASIS+ZM_ZEILEN,d1
	bsr	Zeilen_ungueltig
	mulu.w	#ZIEL_ZEILE,d0
	add.l	d0,a4
	move.w	Intro_h5+ZM_BASIS+ZM_X,d0
	lsr.w	#4,d0
	mulu.w	#ZIEL_WORT,d0
	add.l	d0,a4
	move.l	a4,Zm_ziel
	move.l	#ZIEL_ZEILE,Zm_zeilenschritt
.ziel_da:
	lea	Intro_h5+ZM_BASIS,a5

	tst.w	ZM_MASKE(a5)
	sne	Zm_mit_maske
	move.w	ZM_QZEILE(a5),Zm_qz
	move.w	#-1,Zm_gebaut
	pea	ZM_ZEILENTAB(a5)
	move.l	(sp)+,Zm_tab
	move.w	ZM_ZEILEN(a5),d0
	subq.w	#1,d0
	move.w	d0,Zm_rest
.zeile:
	move.w	Zm_qz,d0
	cmp.w	Zm_gebaut,d0
	beq.b	.setzen
	move.w	d0,Zm_gebaut
	move.l	Zm_bild,d1
	beq.b	.wandeln
	mulu.w	Zm_bild_schritt,d0	; Zeile im Lager
	add.l	d1,d0
	move.l	d0,Zm_zeile
	bra.b	.falten
.wandeln:
	mulu.w	Zm_qzeile_bytes,d0	; Zeile einzeln wandeln
	move.l	Intro_h5+ZM_BASIS+ZM_QUELLE,a0
	add.l	d0,a0
	lea	Zm_chunky+1,a1
	bsr	Zm_wandeln
	move.l	#Zm_chunky,Zm_zeile
.falten:
	bsr	Zm_falten
.setzen:
	tst.b	Zm_im_ziel
	bne.b	.im_ziel
	bsr	Zm_setzen
	bra.b	.gesetzt
.im_ziel:
	bsr	Zm_setzen_ziel
.gesetzt:
	move.l	Zm_zeilenschritt,d0
	add.l	d0,Zm_ziel
	move.l	Zm_tab,a0
	move.w	(a0)+,d0
	move.l	a0,Zm_tab
	add.w	d0,Zm_qz
	subq.w	#1,Zm_rest
	bpl	.zeile
	rts

; ***************************************************************************
; Zm_quelle_suchen -- das gewandelte Quellbild im Lager: Zm_bild (0 = nicht
; im Lager, je Zeile wandeln) und Zm_bild_schritt.  Ein neues Bild wird
; ganz gewandelt; ist das Lager voll, wird es geleert.
;   Veraendert d0-d7/a0-a6.
; ***************************************************************************
Zm_quelle_suchen:
	clr.l	Zm_bild
	tst.l	Zm_lager_frei
	bne.b	.bereit
	move.l	#Zm_lager,Zm_lager_frei	; erster Zoom: Lager leer
.bereit:
	lea	Intro_h5+ZM_BASIS,a5
	move.l	ZM_QUELLE(a5),d0
	cmp.l	#Intro_h2,d0		; nur Thalions feste Daten
	blo	.aus
	cmp.l	#Intro_h4+ZM_H4_LAENGE,d0
	bhs	.aus
	move.w	ZM_QBREITE(a5),d1
	move.w	ZM_QHOEHE(a5),d2
	lea	Zm_plaetze,a0
	moveq	#ZM_PLAETZE-1,d3
.such:	tst.l	ZL_DATEN(a0)
	beq.b	.neu
	cmp.l	ZL_QUELLE(a0),d0
	bne.b	.weiter
	cmp.w	ZL_BREITE(a0),d1
	bne.b	.weiter
	cmp.w	ZL_HOEHE(a0),d2
	bne.b	.weiter
	move.l	ZL_DATEN(a0),Zm_bild	; schon gewandelt
	move.w	ZL_SCHRITT(a0),Zm_bild_schritt
.aus:	rts
.weiter:
	lea	ZL_LAENGE(a0),a0
	dbf	d3,.such
	bsr	Zm_lager_leeren		; alle Plaetze belegt
.neu:	; Groesse: je Zeile die 0 und 16 Punkte je Quellwort, gerade
	move.w	Zm_qworte,d3
	lsl.w	#4,d3
	addq.w	#2,d3			; Schritt
	move.w	d3,d4
	mulu.w	d2,d4			; Bytes
	cmp.l	#ZM_LAGER,d4
	bhi.b	.aus			; zu gross: je Zeile wandeln
	move.l	Zm_lager_frei,d5
	add.l	d4,d5
	cmp.l	#Zm_lager+ZM_LAGER,d5
	bls.b	.passt
	bsr	Zm_lager_leeren
	move.l	#Zm_lager,d5
	add.l	d4,d5
.passt:	move.l	Zm_lager_frei,a5	; Platz belegen
	move.l	d5,Zm_lager_frei
	move.l	d0,ZL_QUELLE(a0)
	move.l	a5,ZL_DATEN(a0)
	move.w	d1,ZL_BREITE(a0)
	move.w	d2,ZL_HOEHE(a0)
	move.w	d3,ZL_SCHRITT(a0)
	move.l	a5,Zm_bild
	move.w	d3,Zm_bild_schritt
	move.l	d0,a6			; alle Zeilen wandeln
	move.w	d2,-(sp)
	bra.b	.z1
.z0:	clr.b	(a5)			; Farbe 0 fuer "ausserhalb"
	move.l	a6,a0
	lea	1(a5),a1
	bsr	Zm_wandeln
	add.w	Zm_qzeile_bytes,a6
	add.w	Zm_bild_schritt,a5
.z1:	subq.w	#1,(sp)
	bpl.b	.z0
	addq.l	#2,sp
	rts

; Zm_lager_leeren -- alle Plaetze frei, a0 = erster Platz.
Zm_lager_leeren:
	lea	Zm_plaetze,a0
	moveq	#ZM_PLAETZE-1,d5
.p:	clr.l	ZL_DATEN(a0)
	lea	ZL_LAENGE(a0),a0
	dbf	d5,.p
	move.l	#Zm_lager,Zm_lager_frei
	lea	Zm_plaetze,a0
	rts

; ***************************************************************************
; Zm_wandeln -- eine Quellzeile (a0) als Farbnummern * 4 nach a1.
;   Veraendert d0-d7/a0-a4.
; ***************************************************************************
Zm_wandeln:
	move.w	Zm_ebene,d0
	move.w	d0,a2			; Ebene 1
	add.w	d0,d0
	move.w	d0,a3			; Ebene 2
	add.w	Zm_ebene,d0
	move.w	d0,a4			; Ebene 3
	move.w	Zm_qworte,d7
	subq.w	#1,d7
.wort:	move.w	(a0),d0
	move.w	0(a0,a2.w),d1
	move.w	0(a0,a3.w),d2
	move.w	0(a0,a4.w),d3
	addq.l	#2,a0
	REPT	16
	moveq	#0,d4			; Ebene 3 zuerst: hoechstes Farbbit
	add.w	d3,d3
	addx.b	d4,d4
	add.w	d2,d2
	addx.b	d4,d4
	add.w	d1,d1
	addx.b	d4,d4
	add.w	d0,d0
	addx.b	d4,d4
	add.b	d4,d4
	add.b	d4,d4
	move.b	d4,(a1)+
	ENDR
	dbf	d7,.wort
	rts

; ***************************************************************************
; Zm_falten -- je Zielwort 16 Punkte aus Zm_zeile nach der Spaltenkarte,
; gefaltet zu vier Ebenenworten und der Maske (Zm_linie, je Wort 5 Worte).
; Je Punkt wird ein Langwort aus Zm_spreiz hineingeschoben: nach acht
; Punkten stehen die Ebenen 0-3 in den Bytes 3-0, movep verteilt sie.
;   Veraendert d0-d7/a0-a4.
; ***************************************************************************
Zm_falten:
	lea	Zm_karte,a2
	move.l	Zm_zeile,a0
	lea	Zm_spreiz,a3
	lea	Zm_linie,a1
	lea	Zm_rand,a4
	moveq	#0,d4
	move.b	Zm_mit_maske,d6
	move.w	Zm_worte,d7
	subq.w	#1,d7
.wort:	moveq	#0,d0
	REPT	8
	move.w	(a2)+,d5
	move.b	0(a0,d5.w),d4
	add.l	d0,d0
	or.l	0(a3,d4.w),d0
	ENDR
	moveq	#0,d1
	REPT	8
	move.w	(a2)+,d5
	move.b	0(a0,d5.w),d4
	add.l	d1,d1
	or.l	0(a3,d4.w),d1
	ENDR
	movep.l	d0,0(a1)
	movep.l	d1,1(a1)
	tst.b	d6
	beq.b	.rand
	move.w	(a1),d2			; mit Maske: wo die Farbe nicht 0 ist
	or.w	2(a1),d2
	or.w	4(a1),d2
	or.w	6(a1),d2
	addq.l	#2,a4
	bra.b	.maske
.rand:	move.w	(a4)+,d2		; ohne: das ganze Rechteck
.maske:	move.w	d2,8(a1)
	lea	10(a1),a1
	dbf	d7,.wort
	rts

; ***************************************************************************
; Zm_setzen -- Zm_linie nach Zm_ziel: Ebene = Ebene & ~Maske | Linie.  Die
; Linie ist ausserhalb der Maske 0.
;   Veraendert d0-d4/d7/a0-a1.
; ***************************************************************************
Zm_setzen:
	move.l	Zm_ziel,a0
	lea	Zm_linie,a1
	move.w	Zm_worte,d7
	subq.w	#1,d7
.wort:	movem.w	(a1)+,d0-d4
	cmp.w	#-1,d4
	beq.b	.voll
	tst.w	d4
	beq.b	.weiter
	not.w	d4
	and.w	d4,(a0)
	or.w	d0,(a0)
	and.w	d4,ZM_EBENE(a0)
	or.w	d1,ZM_EBENE(a0)
	and.w	d4,2*ZM_EBENE(a0)
	or.w	d2,2*ZM_EBENE(a0)
	and.w	d4,3*ZM_EBENE(a0)
	or.w	d3,3*ZM_EBENE(a0)
.weiter:
	addq.l	#2,a0
	dbf	d7,.wort
	rts
.voll:	move.w	d0,(a0)
	move.w	d1,ZM_EBENE(a0)
	move.w	d2,2*ZM_EBENE(a0)
	move.w	d3,3*ZM_EBENE(a0)
	addq.l	#2,a0
	dbf	d7,.wort
	rts

; Zm_setzen_ziel -- the same into a screen in the target format (docs/11
; 7.8): the four plane words of a 16-pixel group lie side by side, the next
; group ZIEL_WORT bytes on.
Zm_setzen_ziel:
	move.l	Zm_ziel,a0
	lea	Zm_linie,a1
	move.w	Zm_worte,d7
	subq.w	#1,d7
.wort:	movem.w	(a1)+,d0-d4
	cmp.w	#-1,d4
	beq.b	.voll
	tst.w	d4
	beq.b	.weiter
	not.w	d4
	and.w	d4,(a0)
	or.w	d0,(a0)
	and.w	d4,2(a0)
	or.w	d1,2(a0)
	and.w	d4,4(a0)
	or.w	d2,4(a0)
	and.w	d4,6(a0)
	or.w	d3,6(a0)
.weiter:
	lea	ZIEL_WORT(a0),a0
	dbf	d7,.wort
	rts
.voll:	movem.w	d0-d3,(a0)
	lea	ZIEL_WORT(a0),a0
	dbf	d7,.wort
	rts

	IFD	ZOOM_PRUEF
; ***************************************************************************
; Zp_pruefen -- (ZOOM_PRUEF) erst Thalions Weg, Ergebnis merken, Zeilen
; zurueck, dann unser Weg und vergleichen.  Verglichen werden die ganzen
; Schirmzeilen des beschnittenen Rechtecks; nur dort schreibt Thalion.
; ***************************************************************************
ZP_MAX		equ	256*ZM_ZEILE

Zp_pruefen:
	addq.l	#1,Zp_anzahl
	move.w	Intro_h5+ZM_BASIS+ZM_ZHOEHE,d0
	cmp.w	Intro_h5+ZM_BASIS+ZM_QHOEHE,d0
	blt.b	.a
	addq.l	#1,Zp_weg_b		; Thalions zweiter Weg ($2060)
.a:	bsr	Zp_bereich
	cmp.l	#ZP_MAX/4,d0
	bhi	.zu_gross
	lea	Zp_vorher,a1
	bsr	Zp_kopieren
	bsr	Zoom_thalion
	bsr	Zp_bereich
	lea	Zp_genau,a1
	bsr	Zp_kopieren
	bsr	Zp_bereich		; Zeilen zurueck wie vorher
	move.l	a0,a1
	lea	Zp_vorher,a0
	bsr	Zp_kopieren
	bsr	Zoom_neu
	bsr	Zp_bereich		; vergleichen
	lea	Zp_genau,a1
	moveq	#0,d1			; abweichende Langworte
.vgl:	cmp.l	(a0)+,(a1)+
	beq.b	.gleich
	addq.l	#1,d1
.gleich:
	subq.l	#1,d0
	bne.b	.vgl
	tst.l	d1
	beq.b	.aus
	addq.l	#1,Zp_abweichend
	tst.l	Zp_erster+20
	bne.b	.aus
	lea	Intro_h5+ZM_BASIS,a5	; den ersten abweichenden merken
	lea	Zp_erster,a0
	move.w	ZM_X(a5),(a0)+
	move.w	ZM_Y(a5),(a0)+
	move.w	ZM_SPALTEN(a5),(a0)+
	move.w	ZM_ZEILEN(a5),(a0)+
	move.w	ZM_ZBREITE(a5),(a0)+
	move.w	ZM_ZHOEHE(a5),(a0)+
	move.w	ZM_QBREITE(a5),(a0)+
	move.w	ZM_QHOEHE(a5),(a0)+
	move.w	ZM_MASKE(a5),(a0)+
	move.w	Zp_anzahl+2,(a0)+
	move.l	d1,(a0)+
.aus:	rts
.zu_gross:
	addq.l	#1,Zp_ungeprueft
	bra	Zoom_thalion

; Zp_bereich -- a0 = erste Zeile des Rechtecks in Thalions Schirm,
;   d0.l = Langworte bis zur letzten.
Zp_bereich:
	lea	Intro_h5+ZM_BASIS,a5
	move.l	Intro_h5+ZM_SCHIRM,a0
	move.w	ZM_Y(a5),d0
	mulu.w	#ZM_ZEILE,d0
	add.l	d0,a0
	move.w	ZM_ZEILEN(a5),d0
	mulu.w	#ZM_ZEILE/4,d0
	rts

; Zp_kopieren -- d0.l Langworte von a0 nach a1; a0, d0 bleiben.
Zp_kopieren:
	move.l	a0,-(sp)
	move.l	d0,-(sp)
.k:	move.l	(a0)+,(a1)+
	subq.l	#1,d0
	bne.b	.k
	move.l	(sp)+,d0
	move.l	(sp)+,a0
	rts

; Zp_text -- (Messausgabe, AMIGA_MESSEN.S) das Ergebnis nach a1, a1 dahinter.
;   Veraendert d0-d2/a0.
Zp_text:
	movem.l	d3/a2,-(sp)
	lea	Text_zp_kopf,a0
	bsr	Mess_anhaengen
	move.l	Zp_anzahl,d0
	bsr	Mess_zahl
	lea	Text_zp_weg_b,a0
	bsr	Mess_anhaengen
	move.l	Zp_weg_b,d0
	bsr	Mess_zahl
	lea	Text_zp_abweichend,a0
	bsr	Mess_anhaengen
	move.l	Zp_abweichend,d0
	bsr	Mess_zahl
	lea	Text_zp_ungeprueft,a0
	bsr	Mess_anhaengen
	move.l	Zp_ungeprueft,d0
	bsr	Mess_zahl
	tst.l	Zp_erster+20
	beq.b	.aus
	lea	Text_zp_erster,a0	; x y Spalten Zeilen, Ziel b h, Quelle b h,
	bsr	Mess_anhaengen		; Maske, Aufruf, Langworte
	lea	Zp_erster,a2
	moveq	#10-1,d3
.w:	moveq	#0,d0
	move.w	(a2)+,d0
	bsr	Mess_zahl
	move.b	#' ',(a1)+
	dbf	d3,.w
	move.l	(a2),d0
	bsr	Mess_zahl
.aus:	movem.l	(sp)+,d3/a2
	rts
	ENDC

; ***************************************************************************
; COMBAT_SUP.S -- die Hardwareschicht unter Thalions Kampfbild (COMBAT/).
; Einheit "bibliothek" (engine.s), hinter am2cpu_code.i.
;
; **Draw_zoom_shape und Draw_zoom_silhouette** (COMOBS.S) zeichnen ein
; Kampfobjekt verkleinert, vergroessert oder gespiegelt.  Im Original sind
; es drei Teile, und nur der letzte haengt an der Hardware:
;
;   Einsprung und Vorspann   Merker, Lage, Beschneiden gegen die CA.
;                            Thalions Code aus AM2_CPU (am2cpu_code.py).
;   Zoom_tabellen            je Zielzeile und Zielspalte der Schritt in der
;                            Quelle.  Ebenso aus AM2_CPU.
;   Blitterteil              ab 0:$2BE42 bzw. 0:$2C74E.  Eine CPU-Fassung
;                            gibt es nicht.  Das sind die beiden Routinen
;                            hier; der Vorspann springt am Ende hinein
;                            (FORTSETZUNGEN in am2cpu_code.py).
;
; **Der Vertrag des Blitterteils**, gelesen in AM2_CPU 0:$2BE42..$2C534
; (beide Wege, Verkleinern und Vergroessern, bilden dasselbe ab):
;
;   Zielfeld     ab (zm_x, zm_y), zm_breite Spalten, zm_hoehe Zeilen: schon
;                beschnitten.
;   Zeilen       Zielzeile i nimmt Quellzeile s(i).  s(0) = zm_szeile, bei
;                Spiegelung in Y zm_qhoehe-1-zm_szeile; danach
;                s(i+1) = s(i) + zm_ytab[i] (Worte mit Vorzeichen).
;   Spalten      **von rechts nach links**: Zielspalte zm_x+zm_breite-1-k
;                nimmt Quellspalte q(k), q(k+1) = q(k) - zm_xtab[k].
;                q(0) = zm_qbreite-1-zm_sspalte, bei Spiegelung in X
;                ((zm_rechts*zm_qbreite/zm_zbreite) & -16) + (zm_sspalte & 15)
;                -- so rechnet es Thalion, auch wenn es von zm_sspalte
;                abweichen kann.
;   Quelle       Thalions Format: je Zeile fuenf Ebenen hintereinander,
;                je Ebene (zm_qbreite & -16)/8 Byte.
;   Maske        ein Punkt zaehlt, wo eine der fuenf Ebenen gesetzt ist;
;                Farbe 0 bleibt durchsichtig.
;   Silhouette   dort statt der Quellfarbe zm_farbe (d2 beim Aufruf).
;
; Die Farbe kommt ueber die Farbbank der Zielzeile, **0 bleibt 0** (dieselbe
; Regel wie Zeilenfarbe).  Keine Bank ist hier fest: faellt das Bankmodell
; spaeter zugunsten eines Copper-Ersatzes mit 32 Farben, liefert Farbbank 0,
; und diese Datei bleibt, wie sie ist.
;
; **Tempo** (Erkenntnis 202): Ein Punkt wird nicht mehr einzeln in die acht
; Ebenen geschrieben.  Die Bits von sechzehn Zielpunkten sammeln sich in
; Registern (je Ebene ein Wort, Maske = wo einer gesetzt ist), dann geht
; die Gruppe mit einem Lesen und einem Schreiben je Ebene auf den Schirm.
; Die Ebenen 0..4 kommen ohne Umweg ueber eine Farbnummer direkt aus den
; Quellebenen, die Ebenen 5..7 aus der Bank.  Die Bank fragt Farbbank_spanne
; nur an der Grenze.  Die Silhouette sammelt nur die Maske, ihre Farbe ist
; je Zeile fest.
;
; **ST** (PLANES = 4, ZIEL_ST): Dort geht die Farbe ueber eine Tabelle je
; Zeile auf 16 Register (ST_TAB im Satz der Zeile, ST_LIB.S), die Ebenen
; lassen sich also nicht direkt sammeln.  Der Weg dort: je Punkt die
; Farbnummer aus den fuenf Ebenen, nachschlagen, ihre vier Bits in vier
; Ebenenwoerter verteilen (d3..d6, die Maske in d7); Gruppe und Schreiben
; bleiben wie hier (zst_schreiben).  Die Silhouette nimmt zs_schreiben wie
; der Falcon, mit dem Register ihrer Farbe.  Den Satz holt jede Zeile neu,
; nach einem St_zeilen_pruefen am Anfang.
;
; Register: Thalions Einsprung sichert d0-a6 selbst und stellt sie nach
; unserem rts wieder her.
; ***************************************************************************

; Thalions Variablen der Bibliothek, AM2_CPU 9:$E938.. (BSS-Block aus
; am2cpu_code.py).  Namen von uns, die Lage ist Thalions.
zm_spiegel_x	equ	Am2cpu_9_0E938	; .b <> 0: in X spiegeln
zm_spiegel_y	equ	Am2cpu_9_0E939	; .b <> 0: in Y spiegeln
zm_farbe	equ	Am2cpu_9_0E93A	; .w Silhouettenfarbe
zm_x		equ	Am2cpu_9_0E93C	; .w linke Zielspalte, beschnitten
zm_y		equ	Am2cpu_9_0E93E	; .w obere Zielzeile, beschnitten
zm_qbreite	equ	Am2cpu_9_0E940	; .w Breite der Quelle
zm_qhoehe	equ	Am2cpu_9_0E942	; .w Hoehe der Quelle
zm_zbreite	equ	Am2cpu_9_0E946	; .w Breite im Ziel, unbeschnitten
zm_hoehe	equ	Am2cpu_9_0E948	; .w Zeilen im Ziel, beschnitten
zm_breite	equ	Am2cpu_9_0E94A	; .w Spalten im Ziel, beschnitten
zm_szeile	equ	Am2cpu_9_0E94E	; .w erste Quellzeile (Zoom_tabellen)
zm_rechts	equ	Am2cpu_9_0E950	; .w rechts abgeschnittene Zielspalten
zm_sspalte	equ	Am2cpu_9_0E952	; .w erste Quellspalte (Zoom_tabellen)
zm_quelle	equ	Am2cpu_9_0E958	; .l Quelle (a0 beim Aufruf)
zm_xtab		equ	Am2cpu_9_0E95C	; .w je Zielspalte der Quellschritt
zm_ytab		equ	Am2cpu_9_0EBDC	; .w je Zielzeile der Quellschritt

	IFNE	Screen_depth-5
	FAIL	"COMBAT_SUP.S: die Quelle hat fuenf Ebenen"
	ENDC
	IFD	ZIEL_ST
	IFNE	PLANES-4
	FAIL	"COMBAT_SUP.S: ST mit vier Ebenen"
	ENDC
	ELSE
	IFNE	PLANES-8
	FAIL	"COMBAT_SUP.S: Falcon mit acht Ebenen"
	ENDC
	ENDC

	SECTION	Fast_BSS,bss
zm_ziel:	ds.l	1		; rechte Zielgruppe der aktuellen Zeile
zm_spalten:	ds.w	2*320+1		; je Zielspalte Byte und Bitnummer, -1 am Ende
zm_zeilenlaenge: ds.w	1		; Byte je Quellzeile (fuenf Ebenen)
zm_bit:		ds.w	1		; Bitmaske der rechten Zielspalte
zm_zeilennr:	ds.w	1		; Bildzeile
zm_rest:	ds.w	1		; Zeilen danach
zm_grenze:	ds.w	1		; ab hier neu nach der Bank fragen
zm_bm:		ds.w	3		; Ebenen 5..7: $FFFF, wo die Bank das Bit hat
zm_sfarbe:	ds.w	1		; Silhouette: Farbe samt Bank, 0 bleibt 0
zm_silh:	ds.b	1		; <> 0: Silhouette
	even

	SECTION	Program,code

; ***************************************************************************
; Zoom_zeichnen / Zoom_silhouette_zeichnen -- der Blitterteil als CPU-Code.
;   Nur aus Thalions Vorspann (jmp am Ende der Stuecke in am2cpu_code.i).
;   Zurueck mit rts in Thalions Einsprung, der die Register herstellt.
;
; In den Punktschleifen: d0/d1 Quellbyte und Bitnummer, d2 Zielbit, d3..d7
; die Ebenen 0..4 der Gruppe (Silhouette: d3 die Maske), a0 Quellzeile,
; a1 Zielgruppe, a2 frei, a3 Spaltentabelle, a4 Zeilenschritte, a5 Byte je
; Quellebene.
; ***************************************************************************
Zoom_silhouette_zeichnen:
	jsr	Zoom_tabellen		; im Original erst im Blitterteil
	st	zm_silh
	bra.b	zm_los
Zoom_zeichnen:
	sf	zm_silh
zm_los:
	move.w	zm_breite,d7
	subq.w	#1,d7
	bmi	Zoom_aus
	move.w	zm_hoehe,d0
	subq.w	#1,d0
	bmi	Zoom_aus
	move.w	d0,zm_rest

	; Ebenenabstand und Zeilenlaenge der Quelle
	move.w	zm_qbreite,d5
	and.w	#-16,d5
	lsr.w	#3,d5			; d5 = Byte je Ebene
	move.w	d5,a5
	move.w	d5,d0
	mulu.w	#Screen_depth,d0
	move.w	d0,zm_zeilenlaenge

	; erste Quellspalte
	tst.b	zm_spiegel_x
	beq.b	zm_sp_gerade
	move.w	zm_rechts,d0
	mulu.w	zm_qbreite,d0
	divu.w	zm_zbreite,d0
	and.w	#-16,d0
	moveq	#15,d6
	and.w	zm_sspalte,d6
	add.w	d0,d6
	bra.b	zm_sp_tab
zm_sp_gerade:
	move.w	zm_qbreite,d6
	subq.w	#1,d6
	sub.w	zm_sspalte,d6

	; Spaltentabelle: je Zielspalte von rechts Byte und Bitnummer der Quelle
zm_sp_tab:
	lea	zm_xtab,a2
	lea	zm_spalten,a3
zm_sp_lauf:
	move.w	d6,d0
	lsr.w	#3,d0
	move.w	d0,(a3)+
	move.w	d6,d0
	not.w	d0
	and.w	#7,d0
	move.w	d0,(a3)+
	sub.w	(a2)+,d6
	dbf	d7,zm_sp_lauf
	move.w	#-1,(a3)		; Ende der Zeile

	; erste Quellzeile
	move.w	zm_szeile,d1
	tst.b	zm_spiegel_y
	beq.b	zm_zl_gerade
	move.w	zm_qhoehe,d0
	subq.w	#1,d0
	sub.w	d1,d0
	move.w	d0,d1
zm_zl_gerade:
	mulu.w	zm_zeilenlaenge,d1
	move.l	zm_quelle,a0
	add.l	d1,a0			; a0 = Quellzeile
	lea	zm_ytab,a4

	; rechte Zielgruppe der ersten Zeile und ihre Bitmaske
	move.l	Work_screen,a1
	move.w	zm_y,d0
	move.w	d0,zm_zeilennr
	mulu.w	#SCRROW,d0
	add.l	d0,a1
	move.w	zm_x,d0
	add.w	zm_breite,d0
	subq.w	#1,d0
	move.w	d0,d1
	lsr.w	#4,d1
	mulu.w	#TROW,d1
	add.l	d1,a1
	move.l	a1,zm_ziel
	not.w	d0
	and.w	#15,d0
	moveq	#0,d2
	bset	d0,d2
	move.w	d2,zm_bit
	clr.w	zm_grenze		; die erste Zeile fragt
	IFD	ZIEL_ST
	jsr	St_zeilen_pruefen	; einmal, dann je Zeile schnell
	ENDC

zm_zeile:
	IFD	ZIEL_ST
	; ---- ST: a6 = Satz dieser Zeile, zm_sfarbe = Register der Silhouette
	move.l	a0,-(sp)
	move.w	zm_zeilennr,d0
	jsr	St_zeilensatz_schnell
	move.l	a0,a6
	move.l	(sp)+,a0
	move.w	zm_farbe,d1
	beq.b	zm_st_sf		; 0 bleibt 0
	move.b	ST_TAB(a6,d1.w),d1	; d1 < 32: das obere Byte ist 0
zm_st_sf:
	move.w	d1,zm_sfarbe
	ELSE
	; ---- Bank dieser Zeile, neu erst an der Grenze ----
	move.w	zm_zeilennr,d0
	cmp.w	zm_grenze,d0
	bcs.b	zm_bank_gilt
	jsr	Farbbank_spanne
	move.w	d1,zm_grenze
	lea	zm_bm,a2
	moveq	#5,d2
zm_bm_lauf:
	moveq	#0,d1
	btst	d2,d0
	beq.b	zm_bm_null
	moveq	#-1,d1
zm_bm_null:
	move.w	d1,(a2)+
	addq.w	#1,d2
	cmp.w	#8,d2
	bne.b	zm_bm_lauf
	move.w	zm_farbe,d1
	beq.b	zm_sf_null		; 0 bleibt 0
	or.w	d0,d1
zm_sf_null:
	move.w	d1,zm_sfarbe
zm_bank_gilt:
	ENDC

	move.l	zm_ziel,a1
	move.w	zm_bit,d2
	lea	zm_spalten,a3
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	moveq	#0,d7
	tst.b	zm_silh
	bne.b	zs_punkt
	IFD	ZIEL_ST
	bra	zst_punkt
	ENDC

	; ---- Farbe aus Thalions fuenf Ebenen, direkt in d3..d7 ----
zm_punkt:
	move.w	(a3)+,d0		; Byte in der Quellebene, -1: Zeilenende
	bmi.b	zm_zeilenende
	move.w	(a3)+,d1		; Bitnummer
	lea	0(a0,d0.w),a2
	btst	d1,(a2)
	beq.b	zm_p1
	or.w	d2,d3
zm_p1:	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zm_p2
	or.w	d2,d4
zm_p2:	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zm_p3
	or.w	d2,d5
zm_p3:	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zm_p4
	or.w	d2,d6
zm_p4:	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zm_p5
	or.w	d2,d7
zm_p5:
	add.w	d2,d2			; eine Spalte nach links
	bcc.b	zm_punkt
	bsr.b	zm_schreiben
	moveq	#1,d2
	lea	-TROW(a1),a1
	bra.b	zm_punkt
zm_zeilenende:
	bsr.b	zm_schreiben
	bra.b	zm_naechste

	; ---- Silhouette: nur die Maske, in d3 ----
zs_punkt:
	move.w	(a3)+,d0
	bmi.b	zs_zeilenende
	move.w	(a3)+,d1
	lea	0(a0,d0.w),a2
	btst	d1,(a2)
	bne.b	zs_treffer
	adda.w	a5,a2
	btst	d1,(a2)
	bne.b	zs_treffer
	adda.w	a5,a2
	btst	d1,(a2)
	bne.b	zs_treffer
	adda.w	a5,a2
	btst	d1,(a2)
	bne.b	zs_treffer
	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zs_weiter
zs_treffer:
	or.w	d2,d3
zs_weiter:
	add.w	d2,d2
	bcc.b	zs_punkt
	bsr	zs_schreiben
	moveq	#1,d2
	lea	-TROW(a1),a1
	bra.b	zs_punkt
zs_zeilenende:
	bsr	zs_schreiben

zm_naechste:
	; naechste Quellzeile: Schritt mit Vorzeichen
	move.w	(a4)+,d0
	muls.w	zm_zeilenlaenge,d0
	add.l	d0,a0
	add.l	#SCRROW,zm_ziel
	addq.w	#1,zm_zeilennr
	subq.w	#1,zm_rest
	bpl	zm_zeile
Zoom_aus:
	rts

; zm_schreiben -- die Gruppe aus d3..d7 nach a1: wo einer der Punkte
; gesetzt ist (Maske), die Ebenen 0..4 aus d3..d7, 5..7 aus der Bank; sonst
; bleibt der Schirm.  Danach d3..d7 = 0.  Nimmt d0-d2/a2.
zm_schreiben:
	move.w	d3,d0
	or.w	d4,d0
	or.w	d5,d0
	or.w	d6,d0
	or.w	d7,d0
	beq.b	zms_aus			; ganz durchsichtig
	move.w	d0,d1
	not.w	d1			; d1 = was bleibt
	move.w	(a1),d2
	and.w	d1,d2
	or.w	d3,d2
	move.w	d2,(a1)
	move.w	2(a1),d2
	and.w	d1,d2
	or.w	d4,d2
	move.w	d2,2(a1)
	move.w	4(a1),d2
	and.w	d1,d2
	or.w	d5,d2
	move.w	d2,4(a1)
	move.w	6(a1),d2
	and.w	d1,d2
	or.w	d6,d2
	move.w	d2,6(a1)
	move.w	8(a1),d2
	and.w	d1,d2
	or.w	d7,d2
	move.w	d2,8(a1)
	lea	zm_bm,a2
	move.w	10(a1),d2
	and.w	d1,d2
	move.w	(a2)+,d3
	and.w	d0,d3
	or.w	d3,d2
	move.w	d2,10(a1)
	move.w	12(a1),d2
	and.w	d1,d2
	move.w	(a2)+,d3
	and.w	d0,d3
	or.w	d3,d2
	move.w	d2,12(a1)
	move.w	14(a1),d2
	and.w	d1,d2
	move.w	(a2),d3
	and.w	d0,d3
	or.w	d3,d2
	move.w	d2,14(a1)
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	moveq	#0,d7
zms_aus:
	rts

; zs_schreiben -- die Silhouette aus der Maske d3 nach a1, Farbe zm_sfarbe
; in alle Ebenen.  Danach d3 = 0.  Nimmt d0-d2/d4/a2.
zs_schreiben:
	tst.w	d3
	beq.b	zss_aus
	move.w	d3,d1
	not.w	d1
	move.w	zm_sfarbe,d0
	move.l	a1,a2
	moveq	#PLANES-1,d4
zss_ebene:
	move.w	(a2),d2
	and.w	d1,d2
	lsr.w	#1,d0
	bcc.b	zss_null
	or.w	d3,d2
zss_null:
	move.w	d2,(a2)+
	dbf	d4,zss_ebene
	moveq	#0,d3
zss_aus:
	rts

	IFD	ZIEL_ST
	; ---- ST: Farbnummer aus den fuenf Ebenen, ueber ST_TAB auf ein
	; Register, dessen vier Bits nach d3..d6; d7 die Maske ----
zst_punkt:
	move.w	(a3)+,d0
	bmi.b	zst_zeilenende
	move.w	(a3)+,d1
	lea	0(a0,d0.w),a2
	moveq	#0,d0
	btst	d1,(a2)
	beq.b	zst_p1
	addq.w	#1,d0
zst_p1:	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zst_p2
	addq.w	#2,d0
zst_p2:	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zst_p3
	addq.w	#4,d0
zst_p3:	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zst_p4
	addq.w	#8,d0
zst_p4:	adda.w	a5,a2
	btst	d1,(a2)
	beq.b	zst_p5
	or.w	#16,d0
zst_p5:
	tst.w	d0
	beq.b	zst_weiter		; Farbe 0: durchsichtig
	or.w	d2,d7
	move.b	ST_TAB(a6,d0.w),d0
	lsr.b	#1,d0
	bcc.b	zst_e1
	or.w	d2,d3
zst_e1:	lsr.b	#1,d0
	bcc.b	zst_e2
	or.w	d2,d4
zst_e2:	lsr.b	#1,d0
	bcc.b	zst_e3
	or.w	d2,d5
zst_e3:	lsr.b	#1,d0
	bcc.b	zst_weiter
	or.w	d2,d6
zst_weiter:
	add.w	d2,d2			; eine Spalte nach links
	bcc.b	zst_punkt
	bsr	zst_schreiben
	moveq	#1,d2
	lea	-TROW(a1),a1
	bra.b	zst_punkt
zst_zeilenende:
	bsr	zst_schreiben
	bra	zm_naechste

; zst_schreiben -- ST: die Gruppe nach a1: wo die Maske d7 gesetzt ist, die
; Ebenen 0..3 aus d3..d6; sonst bleibt der Schirm.  Danach d3..d7 = 0.
; Nimmt d0/d1.
zst_schreiben:
	tst.w	d7
	beq.b	zsts_aus		; ganz durchsichtig
	move.w	d7,d1
	not.w	d1			; d1 = was bleibt
	move.w	(a1),d0
	and.w	d1,d0
	or.w	d3,d0
	move.w	d0,(a1)
	move.w	2(a1),d0
	and.w	d1,d0
	or.w	d4,d0
	move.w	d0,2(a1)
	move.w	4(a1),d0
	and.w	d1,d0
	or.w	d5,d0
	move.w	d0,4(a1)
	move.w	6(a1),d0
	and.w	d1,d0
	or.w	d6,d0
	move.w	d0,6(a1)
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	moveq	#0,d7
zsts_aus:
	rts
	ENDC

; AMIGA_BLIT.S -- der Amiga-Blitter in der CPU, gemeinsam fuer das
; Fantasy-Intro und das Intro.  Ohne SECTION: steht im Codeabschnitt dessen,
; der die Datei einbindet; die Variablen in amiga_blit_bss.i.
;
; Braucht Amiga_register und die Versaetze AR_BLT* (Vorspann).

; ***************************************************************************
; Amiga_blit -- der Amiga-Blitter in der CPU, nach den Registern in
; Amiga_register (F3, Intro I2).  Genau, nicht schnell: die Referenz, gegen
; die ein schnellerer Weg ueber den Atari-Blitter spaeter zu pruefen ist.
;
; Je Zeile BLTSIZE&63 Worte (0 = 64), BLTSIZE>>6 Zeilen (0 = 1024).  A wird
; mit der Erst- und Letztwortmaske verundet und dann um ASH verschoben, B um
; BSH; hineingeschoben wird das vorige Wort, auch ueber das Zeilenende
; hinweg.  Ohne USEA/B/C gelten BLTADAT/BDAT/CDAT.  Jeder Minterm; die
; haeufigen direkt.  Adressen und Modulos zaehlen in geraden Bytes.
;
; **Absteigend** (BLTCON1 Bit 1, das Intro zoomt so): Die Zeiger zeigen auf
; das letzte Wort und laufen rueckwaerts, die Modulos werden abgezogen, und
; die Verschiebung geht nach links (das vorige Wort liegt rechts).
;
; **Danach** stehen die Zeiger der benutzten Kanaele hinter dem Blit, wie
; auf dem Amiga: Das Intro setzt BLTDPT einmal und blittet dann Spalte um
; Spalte weiter ($1D46).
;
; Linien- und Fuellmodus sowie ein Blit ohne USED werden nicht ausgefuehrt,
; sondern in Bl_fremd gezaehlt.
;
; **Schnelle Wege** (Tempo, docs/11 7.6): Amiga_blit sucht zuerst ein Muster,
; fuer das es eine enge Schleife gibt, sonst nimmt es Amiga_blit_genau.
; Gezaehlt in Bl_schnell.  Linien- und Fuellmodus laufen immer genau.
;   Bl_schnell_spalte  eine Wortspalte, $CA oder $E2, auf- oder absteigend
;                      (Zoom im Intro)
;   Bl_schnell_stern   $CA wie Bl_schnell_ca, zwei Worte breit, ALWM 0,
;                      ASH = BSH (Thalions Sterne im Fantasy-Intro)
;   Bl_schnell_ca      $CA aufsteigend, ABCD, C = D (Schriftzug)
;   Bl_schnell_d8      $D8 aufsteigend, ABCD, unverschoben (Extro)
;   Bl_schnell_fc      $FC aufsteigend, A, B und D (D = A | B), verschoben
;   Bl_schnell_fe      $FE aufsteigend, ABCD, C = D (D = A | B | C),
;                      verschoben (beide im Intro, Raumszene)
;   Bl_schnell_f0      $F0 aufsteigend, nur A und D, A unverschoben (Kopie)
;   Bl_schnell_00      $00 aufsteigend, nur D (Loeschen)  Mit BLIT_PRUEF laeuft jeder schnelle Blit
; zusaetzlich genau, und Bl_abweichung zaehlt, wo das Ergebnis anders ist.
; Mit BLIT_NUR_GENAU (Diagnose: vorher gegen nachher) gibt es keine.
; BLIT_STATISTIK (mit AMIGA_MESSEN) zaehlt die Blits nach Art (Bs_zaehlen).
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
Amiga_blit:
	IFD	BLIT_STATISTIK
	IFD	AMIGA_MESSEN		; nur mit der Messung (AMIGA_MESSEN.S)
	bsr	Bs_zaehlen
	ENDC
	ENDC
	IFD	ZIEL_SCHIRME		; Schirme im Zielformat (AMIGA_ZIEL.S)
	tst.l	Direkt_bis
	bne	Bl_umlenken
	ENDC
; Amiga_blit_amiga -- der Blit im Amiga-Speicher (Bl_umlenken kommt hierher
; zurueck).
Amiga_blit_amiga:
	IFD	BLIT_NUR_GENAU
	bra	Amiga_blit_genau
	ENDC
	lea	Amiga_register,a4
	moveq	#%11001,d0		; LINE, IFE, EFE: nur genau
	and.w	AR_BLTCON1(a4),d0
	bne	Amiga_blit_genau
	move.w	AR_BLTCON0(a4),d2
	btst	#8,d2			; ohne USED: genau (zaehlt fremd)
	beq	Amiga_blit_genau
	moveq	#63,d0			; eine Wortspalte?
	and.w	AR_BLTSIZE(a4),d0
	cmp.w	#1,d0
	bne.b	.breit
	cmp.b	#$CA,d2
	beq.b	.spalte
	cmp.b	#$E2,d2
	bne.b	.breit
.spalte:
	move.w	d2,d0
	and.w	#$0B00,d0
	cmp.w	#$0B00,d0		; USEA, USEC, USED (B darf fest sein)
	bne.b	.breit
	lea	Bl_schnell_spalte,a0
	bra	.los
.breit:	btst	#1,AR_BLTCON1+1(a4)	; absteigend: nur genau
	bne	Amiga_blit_genau
	move.w	d2,d0
	and.w	#$0F00,d0		; d0 = Kanaele
	cmp.b	#$CA,d2
	beq	.ca
	cmp.b	#$D8,d2
	beq	.d8
	cmp.b	#$F0,d2
	beq	.f0
	cmp.b	#$FC,d2
	beq	.fc
	cmp.b	#$FE,d2
	beq	.fe
	tst.b	d2
	bne	Amiga_blit_genau
	cmp.w	#$0100,d0		; $00: nur D
	bne	Amiga_blit_genau
	lea	Bl_schnell_00,a0
	bra	.los
.f0:	cmp.w	#$0900,d0		; $F0: A und D, A unverschoben
	bne	Amiga_blit_genau
	move.w	d2,d1
	and.w	#$F000,d1
	bne	Amiga_blit_genau
	lea	Bl_schnell_f0,a0
	bra	.los
.fc:	cmp.w	#$0D00,d0		; $FC: A, B und D
	bne	Amiga_blit_genau
	lea	Bl_schnell_fc,a0
	bra	.los
.fe:	cmp.w	#$0F00,d0		; $FE: alle vier, C = D
	bne	Amiga_blit_genau
	move.l	AR_BLTCPT(a4),d0
	cmp.l	AR_BLTDPT(a4),d0
	bne	Amiga_blit_genau
	move.w	AR_BLTCMOD(a4),d0
	cmp.w	AR_BLTDMOD(a4),d0
	bne	Amiga_blit_genau
	lea	Bl_schnell_fe,a0
	bra	.los
.d8:	cmp.w	#$0F00,d0		; $D8: alle vier, nichts verschoben
	bne	Amiga_blit_genau
	move.w	d2,d1
	and.w	#$F000,d1
	bne	Amiga_blit_genau
	move.w	AR_BLTCON1(a4),d1
	and.w	#$F000,d1
	bne	Amiga_blit_genau
	lea	Bl_schnell_d8,a0
	bra	.los
.ca:	cmp.w	#$0F00,d0		; $CA: alle vier
	bne	Amiga_blit_genau
	move.l	AR_BLTCPT(a4),d0	; C und D dieselbe Stelle
	cmp.l	AR_BLTDPT(a4),d0
	bne	Amiga_blit_genau
	move.w	AR_BLTCMOD(a4),d0
	cmp.w	AR_BLTDMOD(a4),d0
	bne	Amiga_blit_genau
	moveq	#63,d0			; zwei Worte, ALWM 0, ASH = BSH: ein Stern
	and.w	AR_BLTSIZE(a4),d0
	cmp.w	#2,d0
	bne.b	.ca_allg
	tst.w	AR_BLTALWM(a4)
	bne.b	.ca_allg
	move.w	AR_BLTCON1(a4),d0
	eor.w	d2,d0
	and.w	#$F000,d0
	bne.b	.ca_allg
	lea	Bl_schnell_stern,a0
	bra	.los
.ca_allg:
	lea	Bl_schnell_ca,a0
.los:
	IFD	BLIT_PRUEF
	move.l	a0,Pr_weg
	bra	Bl_pruefen
	ELSE
	jmp	(a0)
	ENDC

; Amiga_blit_genau -- der allgemeine Weg, die Referenz.
Amiga_blit_genau:
	lea	Amiga_register,a4
	addq.w	#1,Bl_anzahl
	move.w	AR_BLTCON1(a4),d0
	and.w	#%11001,d0		; LINE, IFE, EFE
	bne	.fremd
	btst	#1,AR_BLTCON1+1(a4)	; DESC
	sne	Bl_absteigend
	move.w	AR_BLTCON0(a4),d2
	btst	#8,d2			; USED
	beq	.fremd
	move.w	AR_BLTSIZE(a4),d0
	moveq	#63,d1
	and.w	d0,d1			; Worte
	bne.b	.w
	moveq	#64,d1
.w:	lsr.w	#6,d0			; Zeilen
	bne.b	.h
	move.w	#1024,d0
.h:	move.w	d0,Bl_zeilen
	move.w	d1,Bl_breite
	move.w	d1,d7			; ein fester Wert: Modulo -2*Worte
	add.w	d7,d7
	neg.w	d7

	; Quellen: Zeiger und Modulo, oder ein fester Wert
	move.l	AR_BLTAPT(a4),a0
	move.w	AR_BLTAMOD(a4),Bl_amod
	btst	#11,d2
	bne.b	.a
	lea	Bl_fest_a,a5
	move.w	AR_BLTADAT(a4),d3
	bsr	Bl_fest
	move.l	a5,a0
	move.w	d7,Bl_amod
.a:	move.l	AR_BLTBPT(a4),a1
	move.w	AR_BLTBMOD(a4),Bl_bmod
	btst	#10,d2
	bne.b	.b
	lea	Bl_fest_b,a5
	move.w	AR_BLTBDAT(a4),d3
	bsr	Bl_fest
	move.l	a5,a1
	move.w	d7,Bl_bmod
.b:	move.l	AR_BLTCPT(a4),a2
	move.w	AR_BLTCMOD(a4),Bl_cmod
	btst	#9,d2
	bne.b	.c
	lea	Bl_fest_c,a5
	move.w	AR_BLTCDAT(a4),d3
	bsr	Bl_fest
	move.l	a5,a2
	move.w	d7,Bl_cmod
.c:	move.l	AR_BLTDPT(a4),a3
	move.w	AR_BLTDMOD(a4),Bl_dmod
	move.l	a0,d3			; Bit 0 zaehlt nicht
	and.w	#-2,d3
	move.l	d3,a0
	move.l	a1,d3
	and.w	#-2,d3
	move.l	d3,a1
	move.l	a2,d3
	and.w	#-2,d3
	move.l	d3,a2
	move.l	a3,d3
	and.w	#-2,d3
	move.l	d3,a3
	and.w	#-2,Bl_amod
	and.w	#-2,Bl_bmod
	and.w	#-2,Bl_cmod
	and.w	#-2,Bl_dmod
	move.w	AR_BLTAFWM(a4),Bl_afwm
	move.w	AR_BLTALWM(a4),Bl_alwm

	lea	Minterme,a5		; der Minterm: direkt oder allgemein
.mt:	move.w	(a5)+,d3
	bmi.b	.ma
	cmp.b	d3,d2
	beq.b	.mf
	addq.l	#4,a5
	bra.b	.mt
.mf:	move.l	(a5),a5
	bra.b	.m
.ma:	lea	Minterm_allgemein,a5
	move.b	d2,Bl_minterm
.m:
	moveq	#0,d6			; ASH
	move.w	d2,d6
	rol.w	#4,d6
	and.w	#15,d6
	moveq	#0,d5			; BSH
	move.w	AR_BLTCON1(a4),d5
	rol.w	#4,d5
	and.w	#15,d5
	moveq	#0,d0			; A: voriges Wort oben, jetziges unten
	moveq	#0,d1			; B ebenso
	tst.b	Bl_absteigend
	bne	.ab

.zeile:	move.w	Bl_breite,Bl_rest
	move.w	Bl_afwm,d7
	cmp.w	#1,Bl_rest
	bne.b	.wort
	and.w	Bl_alwm,d7
.wort:	swap	d0
	move.w	(a0)+,d0
	and.w	d7,d0
	move.l	d0,d3
	lsr.l	d6,d3			; A
	swap	d1
	move.w	(a1)+,d1
	move.l	d1,d4
	lsr.l	d5,d4			; B
	move.w	(a2)+,d2		; C
	jsr	(a5)
	move.w	d2,(a3)+		; D
	subq.w	#1,Bl_rest
	beq.b	.zende
	moveq	#-1,d7
	cmp.w	#1,Bl_rest
	bne.b	.wort
	move.w	Bl_alwm,d7
	bra.b	.wort
.zende:	add.w	Bl_amod,a0
	add.w	Bl_bmod,a1
	add.w	Bl_cmod,a2
	add.w	Bl_dmod,a3
	subq.w	#1,Bl_zeilen
	bne.b	.zeile
	bra	.zeiger

; absteigend: Zeiger ein Wort hoeher, damit -(An) beim letzten Wort beginnt
.ab:	addq.l	#2,a0
	addq.l	#2,a1
	addq.l	#2,a2
	addq.l	#2,a3
.azeile:
	move.w	Bl_breite,Bl_rest
	move.w	Bl_afwm,d7
	cmp.w	#1,Bl_rest
	bne.b	.awort
	and.w	Bl_alwm,d7
.awort:	move.w	-(a0),d0		; d0: voriges oben -> jetziges unten
	and.w	d7,d0
	swap	d0			; jetziges oben, voriges unten
	move.l	d0,d3
	lsl.l	d6,d3
	swap	d3			; A
	move.w	-(a1),d1
	swap	d1
	move.l	d1,d4
	lsl.l	d5,d4
	swap	d4			; B
	move.w	-(a2),d2		; C
	jsr	(a5)
	move.w	d2,-(a3)		; D
	subq.w	#1,Bl_rest
	beq.b	.azende
	moveq	#-1,d7
	cmp.w	#1,Bl_rest
	bne.b	.awort
	move.w	Bl_alwm,d7
	bra.b	.awort
.azende:
	sub.w	Bl_amod,a0
	sub.w	Bl_bmod,a1
	sub.w	Bl_cmod,a2
	sub.w	Bl_dmod,a3
	subq.w	#1,Bl_zeilen
	bne.b	.azeile
	subq.l	#2,a0
	subq.l	#2,a1
	subq.l	#2,a2
	subq.l	#2,a3

; die Zeiger der benutzten Kanaele zurueck in die Register
.zeiger:
	move.w	AR_BLTCON0(a4),d2
	btst	#11,d2
	beq.b	.za
	move.l	a0,AR_BLTAPT(a4)
.za:	btst	#10,d2
	beq.b	.zb
	move.l	a1,AR_BLTBPT(a4)
.zb:	btst	#9,d2
	beq.b	.zc
	move.l	a2,AR_BLTCPT(a4)
.zc:	move.l	a3,AR_BLTDPT(a4)
	rts
.fremd:	addq.w	#1,Bl_fremd
	rts

; ***************************************************************************
; Bl_schnell_ca -- Minterm $CA (A ? B : C), aufsteigend, alle vier Kanaele,
; C und D dieselbe Stelle mit demselben Modulo (Amiga_blit prueft das).
; So blittet Thalion maskierte Bilder: die Sterne im Fantasy-Intro
; (blit_star, blit_star2).  Dasselbe Ergebnis wie Amiga_blit_genau:
;   - A und B laufen wie dort durch ein Rohr (voriges Wort oben), auch ueber
;     das Zeilenende; A bekommt Erst- und Letztwortmaske.
;   - Ist das verschobene A-Wort 0, ist D = C, und D steht schon dort: Das
;     Wort wird weder gelesen noch geschrieben.  B laeuft trotzdem weiter.
; Register in der Schleife: d0/d1 Rohr A/B, d2 Zeilen, d3/d4 A/B verschoben,
; d5 BSH, d6 ASH, d7 Worte der Mitte; a0/a1/a2 A/B/C=D, a4/a5/a6 Modulos.
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
; CA_WORT: ein Wort, A schon in d0 (low), bei Bedarf maskiert; \1 = Schritt
; von C = D (2: Amiga, ZIEL_WORT: the target)
CA_WORT	macro
	move.l	d0,d3
	lsr.l	d6,d3			; A
	swap	d1
	move.w	(a1)+,d1
	tst.w	d3
	beq.b	.leer\@
	move.l	d1,d4
	lsr.l	d5,d4			; B
	and.w	d3,d4
	not.w	d3
	and.w	(a2),d3
	or.w	d4,d3
	IFEQ	\1-2
	move.w	d3,(a2)+
	bra.b	.weiter\@
.leer\@:	addq.l	#2,a2
	ELSE
	move.w	d3,(a2)
.leer\@:	lea	\1(a2),a2
	ENDC
.weiter\@:
	endm

; CA_VORBEREITEN: die Register fuer CA_SCHLEIFE aus Amiga_register (a4);
; a2 und a6 (C = D, Zeiger und Modulo) setzt der Aufrufer danach.
CA_VORBEREITEN	macro
	addq.w	#1,Bl_anzahl
	addq.w	#1,Bl_schnell
	move.w	AR_BLTSIZE(a4),d0
	moveq	#63,d1
	and.w	d0,d1			; Worte
	bne.b	.w\@
	moveq	#64,d1
.w\@:	lsr.w	#6,d0			; Zeilen
	bne.b	.h\@
	move.w	#1024,d0
.h\@:	move.w	d0,d2
	move.w	AR_BLTAFWM(a4),d3
	move.w	AR_BLTALWM(a4),d4
	subq.w	#2,d1			; Worte zwischen dem ersten und letzten
	bpl.b	.masken\@
	and.w	d4,d3			; nur ein Wort: beide Masken
.masken\@:
	move.w	d3,Bl_afwm
	move.w	d4,Bl_alwm
	move.w	d1,Bl_rest		; -1: nur das erste Wort
	moveq	#0,d6			; ASH
	move.w	AR_BLTCON0(a4),d6
	rol.w	#4,d6
	and.w	#15,d6
	moveq	#0,d5			; BSH
	move.w	AR_BLTCON1(a4),d5
	rol.w	#4,d5
	and.w	#15,d5
	move.l	AR_BLTAPT(a4),d0	; Zeiger und Modulos gerade
	and.w	#-2,d0
	move.l	d0,a0
	move.l	AR_BLTBPT(a4),d0
	and.w	#-2,d0
	move.l	d0,a1
	move.w	AR_BLTBMOD(a4),d0
	and.w	#-2,d0
	move.w	d0,a5
	endm

; CA_SCHLEIFE: die Zeilen; \1 = Schritt von C = D.  a4 = A-Modulo.
CA_SCHLEIFE	macro
	moveq	#0,d0
	moveq	#0,d1
.zeile\@:
	swap	d0			; erstes Wort
	move.w	(a0)+,d0
	and.w	Bl_afwm,d0
	CA_WORT	\1
	move.w	Bl_rest,d7
	bmi.b	.zende\@
	subq.w	#1,d7
	bmi.b	.letztes\@
.mitte\@:
	swap	d0
	move.w	(a0)+,d0
	CA_WORT	\1
	dbf	d7,.mitte\@
.letztes\@:
	swap	d0
	move.w	(a0)+,d0
	and.w	Bl_alwm,d0
	CA_WORT	\1
.zende\@:
	adda.w	a4,a0
	adda.w	a5,a1
	adda.w	a6,a2
	subq.w	#1,d2
	bne	.zeile\@
	endm

Bl_schnell_ca:
	move.l	a6,-(sp)
	lea	Amiga_register,a4
	CA_VORBEREITEN
	move.l	AR_BLTCPT(a4),d0
	and.w	#-2,d0
	move.l	d0,a2
	move.w	AR_BLTCMOD(a4),d0
	and.w	#-2,d0
	move.w	d0,a6
	move.w	AR_BLTAMOD(a4),d0
	and.w	#-2,d0
	move.w	d0,a4			; Amiga_register erst am Ende wieder
	CA_SCHLEIFE	2
	lea	Amiga_register,a4
	move.l	a0,AR_BLTAPT(a4)
	move.l	a1,AR_BLTBPT(a4)
	move.l	a2,AR_BLTCPT(a4)
	move.l	a2,AR_BLTDPT(a4)
	move.l	(sp)+,a6
	rts

; BL_GROESSE -- aus BLTSIZE (a4 = Amiga_register): \1 = Zeilen (0 = 1024),
; \2 = Worte je Zeile (0 = 64).
BL_GROESSE	macro
	move.w	AR_BLTSIZE(a4),\1
	moveq	#63,\2
	and.w	\1,\2
	bne.b	.w\@
	moveq	#64,\2
.w\@:	lsr.w	#6,\1
	bne.b	.h\@
	move.w	#1024,\1
.h\@:
	endm

; BL_GERADE -- \1 (Langwort aus Amiga_register) gerade nach \2 (An), mit \3.
BL_GERADE	macro
	move.l	\1(a4),\3
	and.w	#-2,\3
	move.l	\3,\2
	endm

; ***************************************************************************
; Bl_schnell_stern -- Minterm $CA wie Bl_schnell_ca, aber zwei Worte breit,
; Letztwortmaske 0 und ASH = BSH (Amiga_blit prueft das).  So blittet
; Thalion die Sterne im Fantasy-Intro (blit_star, blit_star2): je Zeile ein
; Maskenwort (A) und ein Bildwort (B), beide um dieselben Bits verschoben
; und in zwei Worte des Ziels gestanzt.  Dasselbe Ergebnis wie der genaue
; Weg, denn:
;   - A: das zweite Wort wird von der Letztwortmaske 0, also schiebt jede
;     Zeile 0 nach (die erste auch, das Rohr beginnt leer).  Die Maske ist
;     das erste A-Wort mit der Erstwortmaske, als Langwort um ASH verschoben.
;   - B: Wo diese Maske 1 ist, stehen nur Bits des ersten B-Worts (gleich
;     weit verschoben).  Das zweite B-Wort und das Rohr aus der Zeile davor
;     fallen unter die Maske 0.
;   - Maske 0: D = C, die Zeile wird nicht angefasst.
; Je Zeile ein Langwort lesen und schreiben statt zweimal CA_WORT.
; Register in der Schleife: d0 Maske, d1 Bild, d2 Zeilen, d5 AFWM, d6 ASH,
; d7 Schritt C = D; a0/a1/a2 A/B/C=D, a3/a5 Schritt A/B (4 + Modulo).
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
Bl_schnell_stern:
	lea	Amiga_register,a4
	addq.w	#1,Bl_anzahl
	addq.w	#1,Bl_schnell
	move.w	AR_BLTSIZE(a4),d2
	lsr.w	#6,d2			; Zeilen
	bne.b	.h
	move.w	#1024,d2
.h:	subq.w	#1,d2			; fuer dbf
	move.w	AR_BLTAFWM(a4),d5
	moveq	#0,d6			; ASH
	move.w	AR_BLTCON0(a4),d6
	rol.w	#4,d6
	and.w	#15,d6
	BL_GERADE AR_BLTAPT,a0,d0
	BL_GERADE AR_BLTBPT,a1,d0
	BL_GERADE AR_BLTCPT,a2,d0
	move.w	AR_BLTAMOD(a4),d0	; Schritte: zwei Worte und Modulo
	and.w	#-2,d0
	addq.w	#4,d0
	move.w	d0,a3
	move.w	AR_BLTBMOD(a4),d0
	and.w	#-2,d0
	addq.w	#4,d0
	move.w	d0,a5
	move.w	AR_BLTCMOD(a4),d7
	and.w	#-2,d7
	addq.w	#4,d7

.zeile:	move.w	(a0),d0			; Maske (A)
	and.w	d5,d0
	beq.b	.leer			; D = C
	swap	d0
	clr.w	d0
	lsr.l	d6,d0
	move.w	(a1),d1			; Bild (B); unten bleibt Altes stehen,
	swap	d1			; das die Maske loescht
	lsr.l	d6,d1
	and.l	d0,d1
	not.l	d0
	and.l	(a2),d0
	or.l	d1,d0
	move.l	d0,(a2)
.leer:	adda.w	a3,a0
	adda.w	a5,a1
	adda.w	d7,a2
	dbf	d2,.zeile

	move.l	a0,AR_BLTAPT(a4)
	move.l	a1,AR_BLTBPT(a4)
	move.l	a2,AR_BLTCPT(a4)
	move.l	a2,AR_BLTDPT(a4)
	rts

; ***************************************************************************
; Bl_schnell_00 -- Minterm $00, aufsteigend, nur D: D wird 0.  Danach steht
; BLTDPT hinter dem Blit, wie im genauen Weg.
;   Veraendert d0-d7/a3.
; ***************************************************************************
Bl_schnell_00:
	addq.w	#1,Bl_anzahl
	addq.w	#1,Bl_schnell
	BL_GROESSE	d0,d1
	BL_GERADE	AR_BLTDPT,a3,d3
	move.w	AR_BLTDMOD(a4),d3
	and.w	#-2,d3
	moveq	#0,d4
	move.w	d1,d5
	lsr.w	#1,d5			; Langworte je Zeile
	subq.w	#1,d5			; -1: keins
	subq.w	#1,d0
.zeile:	move.w	d5,d7
	bmi.b	.einzeln
.lang:	move.l	d4,(a3)+
	dbf	d7,.lang
.einzeln:
	btst	#0,d1			; ungerade Wortzahl: eins dazu
	beq.b	.zende
	move.w	d4,(a3)+
.zende:	add.w	d3,a3
	dbf	d0,.zeile
	move.l	a3,AR_BLTDPT(a4)
	rts

; ***************************************************************************
; Bl_schnell_f0 -- Minterm $F0 (D = A), aufsteigend, nur A und D, ASH = 0:
; D ist das A-Wort mit Erst- und Letztwortmaske.  BLTAPT und BLTDPT stehen
; danach hinter dem Blit.
;   Veraendert d0-d7/a0/a3.
; ***************************************************************************
Bl_schnell_f0:
	addq.w	#1,Bl_anzahl
	addq.w	#1,Bl_schnell
	BL_GROESSE	d0,d1
	BL_GERADE	AR_BLTAPT,a0,d2
	BL_GERADE	AR_BLTDPT,a3,d2
	move.w	AR_BLTAMOD(a4),d2
	and.w	#-2,d2
	move.w	AR_BLTDMOD(a4),d3
	and.w	#-2,d3
	move.w	AR_BLTAFWM(a4),d4
	move.w	AR_BLTALWM(a4),d5
	subq.w	#2,d1			; Worte zwischen dem ersten und letzten
	bpl.b	.masken
	and.w	d5,d4			; nur ein Wort: beide Masken
.masken:
	subq.w	#1,d0
.zeile:	move.w	(a0)+,d6		; erstes Wort
	and.w	d4,d6
	move.w	d6,(a3)+
	move.w	d1,d7
	bmi.b	.zende
	subq.w	#1,d7
	bmi.b	.letztes
.mitte:	move.w	(a0)+,(a3)+
	dbf	d7,.mitte
.letztes:
	move.w	(a0)+,d6
	and.w	d5,d6
	move.w	d6,(a3)+
.zende:	add.w	d2,a0
	add.w	d3,a3
	dbf	d0,.zeile
	move.l	a0,AR_BLTAPT(a4)
	move.l	a3,AR_BLTDPT(a4)
	rts

; ***************************************************************************
; Bl_schnell_d8 -- Minterm $D8 (C ? B : A), aufsteigend, ABCD, ASH = BSH = 0
; (Extro, Rolltext).  D = A ^ ((A ^ B) & C); A mit Erst- und
; Letztwortmaske.  Alle vier Zeiger stehen danach hinter dem Blit.
; Register: d0 Zeilen, d1 Worte der Mitte, d2 AMOD, d4/d5 Masken,
; a4/a5/a6 Modulos B/C/D.
; Bl_ziel_d8 -- dasselbe mit D im Zielschirm (Bl_umlenken, AMIGA_ZIEL.S):
; D ab Bl_ziel_d, je Wort ZIEL_WORT weiter, je Zeile Bl_ziel_dmod.
; BLTDPT steht danach, wo es auf dem Amiga stuende (Bl_ziel_d_ende); die
; Zeilen im Zwischenspeicher gelten nicht mehr.
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
; D8_WORT: ein Wort, A schon in d6; \1 = Schritt von D (2: Amiga)
D8_WORT	macro
	move.w	(a1)+,d3
	eor.w	d6,d3
	and.w	(a2)+,d3
	eor.w	d6,d3
	IFEQ	\1-2
	move.w	d3,(a3)+
	ELSE
	move.w	d3,(a3)
	lea	\1(a3),a3
	ENDC
	endm

; D8_SCHLEIFE: die Zeilen; \1 = Schritt von D
D8_SCHLEIFE	macro
.zeile\@:
	move.w	(a0)+,d6		; erstes Wort
	and.w	d4,d6
	D8_WORT	\1
	move.w	d1,d7
	bmi.b	.zende\@
	subq.w	#1,d7
	bmi.b	.letztes\@
.mitte\@:
	move.w	(a0)+,d6
	D8_WORT	\1
	dbf	d7,.mitte\@
.letztes\@:
	move.w	(a0)+,d6
	and.w	d5,d6
	D8_WORT	\1
.zende\@:
	add.w	d2,a0
	adda.w	a4,a1
	adda.w	a5,a2
	adda.w	a6,a3
	dbf	d0,.zeile\@
	endm

Bl_schnell_d8:
	move.l	a6,-(sp)
	bsr	D8_vorbereiten
	D8_SCHLEIFE	2
	lea	Amiga_register,a4
	move.l	a0,AR_BLTAPT(a4)
	move.l	a1,AR_BLTBPT(a4)
	move.l	a2,AR_BLTCPT(a4)
	move.l	a3,AR_BLTDPT(a4)
	move.l	(sp)+,a6
	rts

	IFD	ZIEL_SCHIRME
Bl_ziel_d8:
	move.l	a6,-(sp)
	bsr	D8_vorbereiten
	move.l	Bl_ziel_d,a3
	move.w	Bl_ziel_dmod,a6
	D8_SCHLEIFE	ZIEL_WORT
	lea	Amiga_register,a4
	move.l	a0,AR_BLTAPT(a4)
	move.l	a1,AR_BLTBPT(a4)
	move.l	a2,AR_BLTCPT(a4)
	move.l	Bl_ziel_d_ende,AR_BLTDPT(a4)
	move.l	(sp)+,a6
	bra	Bl_ziel_ende
	ENDC

; D8_vorbereiten -- Register fuer D8_SCHLEIFE aus Amiga_register (a4).
D8_vorbereiten:
	addq.w	#1,Bl_anzahl
	addq.w	#1,Bl_schnell
	BL_GROESSE	d0,d1
	BL_GERADE	AR_BLTAPT,a0,d2
	BL_GERADE	AR_BLTBPT,a1,d2
	BL_GERADE	AR_BLTCPT,a2,d2
	BL_GERADE	AR_BLTDPT,a3,d2
	move.w	AR_BLTAFWM(a4),d4
	move.w	AR_BLTALWM(a4),d5
	move.w	AR_BLTDMOD(a4),d2
	and.w	#-2,d2
	move.w	d2,a6
	move.w	AR_BLTCMOD(a4),d2
	and.w	#-2,d2
	move.w	d2,a5
	move.w	AR_BLTAMOD(a4),d2
	and.w	#-2,d2
	move.w	AR_BLTBMOD(a4),d3
	and.w	#-2,d3
	move.w	d3,a4			; Amiga_register erst am Ende wieder
	subq.w	#2,d1
	bpl.b	.masken
	and.w	d5,d4
.masken:
	subq.w	#1,d0
	rts

	IFD	ZIEL_SCHIRME
; ***************************************************************************
; Bl_ziel_ca -- Bl_schnell_ca with C = D in the target screen (Bl_umlenken,
; AMIGA_ZIEL.S): from Bl_ziel_d, ZIEL_WORT a word, Bl_ziel_dmod a line.
; Afterwards BLTCPT and BLTDPT stand where they would on the Amiga
; (Bl_ziel_d_ende), and the buffer lines are no longer valid.  The intro's
; clouds before the menu ($4E2A).
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
Bl_ziel_ca:
	move.l	a6,-(sp)
	CA_VORBEREITEN
	move.l	Bl_ziel_d,a2
	move.w	Bl_ziel_dmod,a6
	move.w	AR_BLTAMOD(a4),d0
	and.w	#-2,d0
	move.w	d0,a4
	CA_SCHLEIFE	ZIEL_WORT
	lea	Amiga_register,a4
	move.l	a0,AR_BLTAPT(a4)
	move.l	a1,AR_BLTBPT(a4)
	move.l	Bl_ziel_d_ende,AR_BLTCPT(a4)
	move.l	Bl_ziel_d_ende,AR_BLTDPT(a4)
	move.l	(sp)+,a6
	bra	Bl_ziel_ende

; ***************************************************************************
; Bl_ziel_f0 -- Bl_schnell_f0 with D in the target screen: D = A with the
; first and last word masks.  The intro's logo stages ($13D0).
;   Veraendert d0-d7/a0/a3.
; ***************************************************************************
Bl_ziel_f0:
	addq.w	#1,Bl_anzahl
	addq.w	#1,Bl_schnell
	BL_GROESSE	d0,d1
	BL_GERADE	AR_BLTAPT,a0,d2
	move.l	Bl_ziel_d,a3
	move.w	AR_BLTAMOD(a4),d2
	and.w	#-2,d2
	move.w	Bl_ziel_dmod,d3
	move.w	AR_BLTAFWM(a4),d4
	move.w	AR_BLTALWM(a4),d5
	subq.w	#2,d1			; Worte zwischen dem ersten und letzten
	bpl.b	.masken
	and.w	d5,d4			; nur ein Wort: beide Masken
.masken:
	subq.w	#1,d0
.zeile:	move.w	(a0)+,d6		; erstes Wort
	and.w	d4,d6
	move.w	d6,(a3)
	lea	ZIEL_WORT(a3),a3
	move.w	d1,d7
	bmi.b	.zende
	subq.w	#1,d7
	bmi.b	.letztes
.mitte:	move.w	(a0)+,(a3)
	lea	ZIEL_WORT(a3),a3
	dbf	d7,.mitte
.letztes:
	move.w	(a0)+,d6
	and.w	d5,d6
	move.w	d6,(a3)
	lea	ZIEL_WORT(a3),a3
.zende:	add.w	d2,a0
	add.w	d3,a3
	dbf	d0,.zeile
	move.l	a0,AR_BLTAPT(a4)
	move.l	Bl_ziel_d_ende,AR_BLTDPT(a4)
	bra	Bl_ziel_ende

; ***************************************************************************
; Bl_ziel_allg -- any minterm, ascending, D in the target screen; C at D's
; place in the target (Bl_ziel_c) or unused (BLTCDAT).  A and B as in
; Amiga_blit_genau, their pointers or a fixed value.  The intro's text
; ($29F4: $FA and $0A).
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
Bl_ziel_allg:
	addq.w	#1,Bl_anzahl
	clr.b	Bl_absteigend		; for Bl_fest
	BL_GROESSE	d0,d1
	move.w	d0,Bl_zeilen
	move.w	d1,Bl_breite
	move.w	d1,d7			; a fixed value: modulo -2 * words
	add.w	d7,d7
	neg.w	d7
	move.w	AR_BLTCON0(a4),d2
	move.l	AR_BLTAPT(a4),a0
	move.w	AR_BLTAMOD(a4),Bl_amod
	btst	#11,d2
	bne.b	.a
	lea	Bl_fest_a,a5
	move.w	AR_BLTADAT(a4),d3
	bsr	Bl_fest
	move.l	a5,a0
	move.w	d7,Bl_amod
.a:	move.l	AR_BLTBPT(a4),a1
	move.w	AR_BLTBMOD(a4),Bl_bmod
	btst	#10,d2
	bne.b	.b
	lea	Bl_fest_b,a5
	move.w	AR_BLTBDAT(a4),d3
	bsr	Bl_fest
	move.l	a5,a1
	move.w	d7,Bl_bmod
.b:	move.l	a0,d3			; Bit 0 zaehlt nicht
	and.w	#-2,d3
	move.l	d3,a0
	move.l	a1,d3
	and.w	#-2,d3
	move.l	d3,a1
	and.w	#-2,Bl_amod
	and.w	#-2,Bl_bmod
	move.l	Bl_ziel_d,a3
	move.w	AR_BLTAFWM(a4),Bl_afwm
	move.w	AR_BLTALWM(a4),Bl_alwm
	lea	Minterme,a5		; der Minterm: direkt oder allgemein
.mt:	move.w	(a5)+,d3
	bmi.b	.ma
	cmp.b	d3,d2
	beq.b	.mf
	addq.l	#4,a5
	bra.b	.mt
.mf:	move.l	(a5),a5
	bra.b	.m
.ma:	lea	Minterm_allgemein,a5
	move.b	d2,Bl_minterm
.m:	moveq	#0,d6			; ASH
	move.w	d2,d6
	rol.w	#4,d6
	and.w	#15,d6
	moveq	#0,d5			; BSH
	move.w	AR_BLTCON1(a4),d5
	rol.w	#4,d5
	and.w	#15,d5
	moveq	#0,d0			; A: voriges Wort oben, jetziges unten
	moveq	#0,d1			; B ebenso
.zeile:	move.w	Bl_breite,Bl_rest
	move.w	Bl_afwm,d7
	cmp.w	#1,Bl_rest
	bne.b	.wort
	and.w	Bl_alwm,d7
.wort:	swap	d0
	move.w	(a0)+,d0
	and.w	d7,d0
	move.l	d0,d3
	lsr.l	d6,d3			; A
	swap	d1
	move.w	(a1)+,d1
	move.l	d1,d4
	lsr.l	d5,d4			; B
	move.w	AR_BLTCDAT(a4),d2	; C: fixed, or at D's place
	tst.b	Bl_ziel_c
	beq.b	.c
	move.w	(a3),d2
.c:	jsr	(a5)
	move.w	d2,(a3)			; D
	lea	ZIEL_WORT(a3),a3
	subq.w	#1,Bl_rest
	beq.b	.zende
	moveq	#-1,d7
	cmp.w	#1,Bl_rest
	bne.b	.wort
	move.w	Bl_alwm,d7
	bra.b	.wort
.zende:	add.w	Bl_amod,a0
	add.w	Bl_bmod,a1
	add.w	Bl_ziel_dmod,a3
	subq.w	#1,Bl_zeilen
	bne.b	.zeile
	move.w	AR_BLTCON0(a4),d2	; the pointers of the channels used
	btst	#11,d2
	beq.b	.za
	move.l	a0,AR_BLTAPT(a4)
.za:	btst	#10,d2
	beq.b	.zb
	move.l	a1,AR_BLTBPT(a4)
.zb:	btst	#9,d2
	beq.b	.zc
	move.l	Bl_ziel_d_ende,AR_BLTCPT(a4)
.zc:	move.l	Bl_ziel_d_ende,AR_BLTDPT(a4)

; Bl_ziel_ende -- after a way into the target.  D's buffer lines were
; marked stale before it (Bl_umlenken_weg, AMIGA_ZIEL.S).
Bl_ziel_ende:
	IFD	AMIGA_MESSEN
	addq.l	#1,Bl_ziel
	ENDC
	rts
	ENDC

; ***************************************************************************
; Bl_schnell_fc, Bl_schnell_fe -- Minterm $FC (D = A | B, ohne C) und $FE
; (D = A | B | C, C und D dieselbe Stelle mit demselben Modulo), aufsteigend,
; mit Verschiebung.  So legt das Intro in der Raumszene Bilder ueber den
; Grund.  Wie Bl_schnell_ca: A und B laufen durch ein Rohr, A bekommt Erst-
; und Letztwortmaske.  Alle benutzten Zeiger stehen danach hinter dem Blit.
; Register in der Schleife: d0/d1 Rohr A/B, d2 Zeilen, d3/d4 A/B verschoben,
; d5 BSH, d6 ASH, d7 Worte der Mitte; a0/a1/a2 A/B/D (= C), a4/a5/a6
; Modulos.
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
; ODER_WORT: ein Wort, A schon in d0 (low), bei Bedarf maskiert; \1 = 0
; ($FC) oder 1 ($FE: C dazu).  Ein leeres Argument bringt vasm um.
ODER_WORT	macro
	move.l	d0,d3
	lsr.l	d6,d3			; A
	swap	d1
	move.w	(a1)+,d1
	move.l	d1,d4
	lsr.l	d5,d4			; B
	or.w	d4,d3
	IF	\1
	or.w	(a2),d3			; C
	ENDC
	move.w	d3,(a2)+		; D
	endm

; ODER_BLIT: der ganze Blit; \1 wie bei ODER_WORT, \2 der Zeiger von D
; (BLTDPT, beim $FE gleich BLTCPT), \3 sein Modulo
ODER_BLIT	macro
	move.l	a6,-(sp)
	addq.w	#1,Bl_anzahl
	addq.w	#1,Bl_schnell
	BL_GROESSE	d2,d1
	move.w	AR_BLTAFWM(a4),d3
	move.w	AR_BLTALWM(a4),d4
	subq.w	#2,d1			; Worte zwischen dem ersten und letzten
	bpl.b	.masken\@
	and.w	d4,d3			; nur ein Wort: beide Masken
.masken\@:
	move.w	d3,Bl_afwm
	move.w	d4,Bl_alwm
	move.w	d1,Bl_rest		; -1: nur das erste Wort
	moveq	#0,d6			; ASH
	move.w	AR_BLTCON0(a4),d6
	rol.w	#4,d6
	and.w	#15,d6
	moveq	#0,d5			; BSH
	move.w	AR_BLTCON1(a4),d5
	rol.w	#4,d5
	and.w	#15,d5
	BL_GERADE	AR_BLTAPT,a0,d0
	BL_GERADE	AR_BLTBPT,a1,d0
	BL_GERADE	\2,a2,d0
	move.w	\3(a4),d0
	and.w	#-2,d0
	move.w	d0,a6
	move.w	AR_BLTBMOD(a4),d0
	and.w	#-2,d0
	move.w	d0,a5
	move.w	AR_BLTAMOD(a4),d0
	and.w	#-2,d0
	move.w	d0,a4			; Amiga_register erst am Ende wieder
	moveq	#0,d0
	moveq	#0,d1
.zeile\@:
	swap	d0			; erstes Wort
	move.w	(a0)+,d0
	and.w	Bl_afwm,d0
	ODER_WORT	\1
	move.w	Bl_rest,d7
	bmi.b	.zende\@
	subq.w	#1,d7
	bmi.b	.letztes\@
.mitte\@:
	swap	d0
	move.w	(a0)+,d0
	ODER_WORT	\1
	dbf	d7,.mitte\@
.letztes\@:
	swap	d0
	move.w	(a0)+,d0
	and.w	Bl_alwm,d0
	ODER_WORT	\1
.zende\@:
	adda.w	a4,a0
	adda.w	a5,a1
	adda.w	a6,a2
	subq.w	#1,d2
	bne	.zeile\@
	lea	Amiga_register,a4
	move.l	a0,AR_BLTAPT(a4)
	move.l	a1,AR_BLTBPT(a4)
	move.l	a2,AR_BLTDPT(a4)
	endm

Bl_schnell_fc:
	ODER_BLIT	0,AR_BLTDPT,AR_BLTDMOD
	move.l	(sp)+,a6
	rts

Bl_schnell_fe:
	ODER_BLIT	1,AR_BLTCPT,AR_BLTCMOD
	move.l	a2,AR_BLTCPT(a4)
	move.l	(sp)+,a6
	rts

; ***************************************************************************
; Bl_schnell_spalte -- eine Wortspalte (BLTSIZE-Breite 1), Minterm $CA oder
; $E2, auf- oder absteigend, mit Verschiebung; USEA, USEC, USED, B aus dem
; Speicher oder fest (BLTBDAT).  So zoomt das Intro.  Wie der genaue Weg,
; nur ohne Aufruf je Wort und ohne Wortzaehler:
;   - A und B laufen durch das Rohr (voriges Wort oben, absteigend unten),
;     auch ueber das Zeilenende; A bekommt beide Masken.
;   - Festes B: Bl_fest_b mit Modulo -2, wie im genauen Weg.
; Register: d0/d1 Rohr A/B, d2 C -> D, d3/d4 A/B, d5 BSH, d6 ASH, d7 Maske;
; a4/a5/a6 Modulos A/B/C, Bl_dmod, Bl_zeilen.  Mit C = D (so zoomt das
; Intro) entfallen a3 und Bl_dmod, und die Zeilen zaehlt das obere Wort
; von d5: kein Speicherzugriff je Zeile ausser A, B, C und D.
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
; SP_AUF/SP_AB: eine Zeile, \1 = der Minterm (d3 = A, d4 = B, d2 = C -> D)
SP_AUF	macro
.z\@:	swap	d0
	move.w	(a0)+,d0
	and.w	d7,d0
	move.l	d0,d3
	lsr.l	d6,d3			; A
	swap	d1
	move.w	(a1)+,d1
	move.l	d1,d4
	lsr.l	d5,d4			; B
	move.w	(a2)+,d2		; C
	\1
	move.w	d2,(a3)+		; D
	adda.w	a4,a0
	adda.w	a5,a1
	adda.w	a6,a2
	add.w	Bl_dmod,a3
	subq.w	#1,Bl_zeilen
	bne.b	.z\@
	endm

SP_AB	macro
.z\@:	move.w	-(a0),d0
	and.w	d7,d0
	swap	d0
	move.l	d0,d3
	lsl.l	d6,d3
	swap	d3			; A
	move.w	-(a1),d1
	swap	d1
	move.l	d1,d4
	lsl.l	d5,d4
	swap	d4			; B
	move.w	-(a2),d2		; C
	\1
	move.w	d2,-(a3)		; D
	suba.w	a4,a0
	suba.w	a5,a1
	suba.w	a6,a2
	sub.w	Bl_dmod,a3
	subq.w	#1,Bl_zeilen
	bne.b	.z\@
	endm

; SP_AUF_CD/SP_AB_CD: dasselbe mit C = D (Zeiger a2, Modulo a6), der
; Zeilenzaehler im oberen Wort von d5 (lsr/lsl nehmen nur die Bits 0-5)
SP_AUF_CD	macro
.z\@:	swap	d0
	move.w	(a0)+,d0
	and.w	d7,d0
	move.l	d0,d3
	lsr.l	d6,d3			; A
	swap	d1
	move.w	(a1)+,d1
	move.l	d1,d4
	lsr.l	d5,d4			; B
	move.w	(a2),d2			; C
	\1
	move.w	d2,(a2)+		; D
	adda.w	a4,a0
	adda.w	a5,a1
	adda.w	a6,a2
	sub.l	#$10000,d5
	bcc.b	.z\@
	endm

SP_AB_CD	macro
.z\@:	move.w	-(a0),d0
	and.w	d7,d0
	swap	d0
	move.l	d0,d3
	lsl.l	d6,d3
	swap	d3			; A
	move.w	-(a1),d1
	swap	d1
	move.l	d1,d4
	lsl.l	d5,d4
	swap	d4			; B
	move.w	-(a2),d2		; C
	\1
	move.w	d2,(a2)			; D
	suba.w	a4,a0
	suba.w	a5,a1
	suba.w	a6,a2
	sub.l	#$10000,d5
	bcc.b	.z\@
	endm

SP_CA	macro				; A ? B : C
	and.w	d3,d4
	not.w	d3
	and.w	d3,d2
	or.w	d4,d2
	endm

SP_E2	macro				; B ? A : C
	and.w	d4,d3
	not.w	d4
	and.w	d4,d2
	or.w	d3,d2
	endm

Bl_schnell_spalte:
	move.l	a6,-(sp)
	addq.w	#1,Bl_anzahl
	addq.w	#1,Bl_schnell
	BL_GROESSE	d0,d1
	move.w	d0,Bl_zeilen
	btst	#1,AR_BLTCON1+1(a4)
	sne	Bl_absteigend
	BL_GERADE	AR_BLTAPT,a0,d2
	BL_GERADE	AR_BLTCPT,a2,d2
	BL_GERADE	AR_BLTDPT,a3,d2
	move.w	AR_BLTAMOD(a4),d2
	and.w	#-2,d2
	move.w	d2,a5			; erst A (unten nach a4)
	move.w	AR_BLTCMOD(a4),d2
	and.w	#-2,d2
	move.w	d2,a6
	move.w	AR_BLTDMOD(a4),d2
	and.w	#-2,d2
	move.w	d2,Bl_dmod
	btst	#10,AR_BLTCON0(a4)	; USEB
	beq.b	.bfest
	BL_GERADE	AR_BLTBPT,a1,d2
	move.w	AR_BLTBMOD(a4),d2
	and.w	#-2,d2
	bra.b	.b
.bfest:	lea	Bl_fest_b,a1		; wie Bl_fest mit einem Wort
	move.w	AR_BLTBDAT(a4),(a1)
	moveq	#-2,d2
.b:	move.w	AR_BLTAFWM(a4),d7	; ein Wort: beide Masken
	and.w	AR_BLTALWM(a4),d7
	moveq	#0,d6			; ASH
	move.w	AR_BLTCON0(a4),d6
	rol.w	#4,d6
	and.w	#15,d6
	moveq	#0,d5			; BSH
	move.w	AR_BLTCON1(a4),d5
	rol.w	#4,d5
	and.w	#15,d5
	move.b	AR_BLTCON0+1(a4),d3	; Minterm
	exg	d2,a5			; a5 = BMOD, d2 = AMOD
	move.w	d2,a4			; Amiga_register erst am Ende wieder
	moveq	#0,d0
	moveq	#0,d1
	cmpa.l	a2,a3			; C = D (der Zoom): alles in Registern
	bne	.allg
	cmpa.w	Bl_dmod,a6
	bne	.allg
	move.w	Bl_zeilen,d2
	subq.w	#1,d2
	swap	d5
	move.w	d2,d5
	swap	d5
	tst.b	Bl_absteigend
	bne	.cd_ab
	cmp.b	#$CA,d3
	bne	.cd_auf_e2
	SP_AUF_CD	SP_CA
	bra	.cd_ende
.cd_auf_e2:
	SP_AUF_CD	SP_E2
	bra	.cd_ende
.cd_ab:	addq.l	#2,a0			; wie im genauen Weg: ein Wort hoeher
	addq.l	#2,a1
	addq.l	#2,a2
	cmp.b	#$CA,d3
	bne	.cd_ab_e2
	SP_AB_CD	SP_CA
	bra	.cd_ab_ende
.cd_ab_e2:
	SP_AB_CD	SP_E2
.cd_ab_ende:
	subq.l	#2,a0
	subq.l	#2,a1
	subq.l	#2,a2
.cd_ende:
	move.l	a2,a3
	bra	.zeiger
.allg:	tst.b	Bl_absteigend
	bne	.ab
	cmp.b	#$CA,d3
	bne	.auf_e2
	SP_AUF	SP_CA
	bra	.zeiger
.auf_e2:
	SP_AUF	SP_E2
	bra	.zeiger
.ab:	addq.l	#2,a0			; wie im genauen Weg: ein Wort hoeher
	addq.l	#2,a1
	addq.l	#2,a2
	addq.l	#2,a3
	cmp.b	#$CA,d3
	bne	.ab_e2
	SP_AB	SP_CA
	bra	.ab_ende
.ab_e2:	SP_AB	SP_E2
.ab_ende:
	subq.l	#2,a0
	subq.l	#2,a1
	subq.l	#2,a2
	subq.l	#2,a3
.zeiger:
	lea	Amiga_register,a4
	move.l	a0,AR_BLTAPT(a4)
	btst	#10,AR_BLTCON0(a4)
	beq.b	.zb
	move.l	a1,AR_BLTBPT(a4)
.zb:	move.l	a2,AR_BLTCPT(a4)
	move.l	a3,AR_BLTDPT(a4)
	move.l	(sp)+,a6
	rts

	IFD	BLIT_PRUEF
; ***************************************************************************
; Bl_pruefen -- (BLIT_PRUEF) den schnellen Weg gegen den genauen: erst
; genau, Ergebnis und Register merken, alles zurueck, dann schnell und
; vergleichen.  Der schnelle Weg steht in Pr_weg (Amiga_blit), a4 =
; Amiga_register.  Geprueft wird der ganze Bereich, den D ueberstreicht
; (auch absteigend und mit negativem Modulo), wenn er in den Puffer passt;
; sonst zaehlt Bl_ungeprueft.
; ***************************************************************************
BL_REG		equ	AR_BLTCON0		; die Blitterregister $40-$75
BL_REG_LAENGE	equ	$36
PR_MAX		equ	131072

Bl_pruefen:
	; Bereich von D: Zeile r beginnt (absteigend: endet) bei
	; D +- r * Schritt, Schritt = 2 * Worte + DMOD, auch negativ
	BL_GROESSE	d0,d1
	add.w	d1,d1			; 2 * Worte
	move.w	AR_BLTDMOD(a4),d2
	and.w	#-2,d2
	add.w	d1,d2			; Schritt
	subq.w	#1,d0
	muls.w	d2,d0			; (Zeilen - 1) * Schritt
	moveq	#0,d2			; min(0, ..)
	moveq	#0,d3			; max(0, ..)
	tst.l	d0
	bmi.b	.neg
	move.l	d0,d3
	bra.b	.spanne
.neg:	move.l	d0,d2
.spanne:
	ext.l	d1
	subq.l	#2,d1			; Versatz des letzten Worts einer Zeile
	move.l	AR_BLTDPT(a4),d4
	and.w	#-2,d4
	btst	#1,AR_BLTCON1+1(a4)
	beq.b	.auf
	move.l	d4,d5			; absteigend: D - max - Zeile .. D - min
	sub.l	d3,d5
	sub.l	d1,d5
	move.l	d4,d6
	sub.l	d2,d6
	bra.b	.bereich
.auf:	move.l	d4,d5			; aufsteigend: D + min .. D + max + Zeile
	add.l	d2,d5
	move.l	d4,d6
	add.l	d3,d6
	add.l	d1,d6
.bereich:
	addq.l	#2,d6			; hinter dem letzten Wort
	sub.l	d5,d6			; Bytes des Bereichs
	cmp.l	#PR_MAX,d6
	bhi	.nicht
	move.l	d5,Pr_ziel
	lsr.l	#1,d6
	move.l	d6,Pr_worte

	lea	BL_REG(a4),a0		; Register und Bereich sichern
	lea	Pr_reg,a1
	bsr	Pr_reg_kopieren
	move.l	Pr_ziel,a0
	lea	Pr_vorher,a1
	bsr	Pr_kopieren
	bsr	Amiga_blit_genau
	subq.w	#1,Bl_anzahl
	move.l	Pr_ziel,a0		; genaues Ergebnis merken
	lea	Pr_genau,a1
	bsr	Pr_kopieren
	lea	Amiga_register+BL_REG,a0
	lea	Pr_reg_genau,a1
	bsr	Pr_reg_kopieren
	lea	Pr_vorher,a0		; zurueck wie vorher
	move.l	Pr_ziel,a1
	bsr	Pr_kopieren
	lea	Pr_reg,a0
	lea	Amiga_register+BL_REG,a1
	bsr	Pr_reg_kopieren
	lea	Amiga_register,a4
	move.l	Pr_weg,a0
	jsr	(a0)
	move.l	Pr_ziel,a0		; vergleichen
	lea	Pr_genau,a1
	move.l	Pr_worte,d0
.v:	cmp.w	(a0)+,(a1)+
	bne.b	.anders
	subq.l	#1,d0
	bne.b	.v
	lea	Amiga_register+BL_REG,a0
	lea	Pr_reg_genau,a1
	moveq	#BL_REG_LAENGE/2-1,d0
.r:	cmp.w	(a0)+,(a1)+
	bne.b	.anders
	dbf	d0,.r
	rts
.anders:
	addq.w	#1,Bl_abweichung
	rts
.nicht:	addq.w	#1,Bl_ungeprueft
	move.w	AR_BLTCON0(a4),Pr_letzt	; fuer Mess_ausgeben: welcher
	move.w	AR_BLTCON1(a4),Pr_letzt+2
	move.w	AR_BLTSIZE(a4),Pr_letzt+4
	move.w	AR_BLTDMOD(a4),Pr_letzt+6
	move.l	Pr_weg,a0
	jmp	(a0)

; Pr_kopieren -- Pr_worte Worte von a0 nach a1.
Pr_kopieren:
	move.l	Pr_worte,d0
.k:	move.w	(a0)+,(a1)+
	subq.l	#1,d0
	bne.b	.k
	rts
; Pr_reg_kopieren -- die Blitterregister von a0 nach a1.
Pr_reg_kopieren:
	moveq	#BL_REG_LAENGE/2-1,d0
.k:	move.w	(a0)+,(a1)+
	dbf	d0,.k
	rts
	ENDC

; Bl_fest -- d1 Worte mit d3 nach a5..: ein fester Wert als Quelle, deren
; Modulo -2*Worte jede Zeile wieder an den Anfang bringt.  Zurueck in a5 der
; Zeiger fuer den Kanal: der Anfang, absteigend das letzte Wort.
Bl_fest:
	move.l	d1,-(sp)
	subq.w	#1,d1
.f:	move.w	d3,(a5)+
	dbf	d1,.f
	move.l	(sp)+,d1
	tst.b	Bl_absteigend
	beq.b	.auf
	subq.l	#2,a5
	rts
.auf:	sub.w	d1,a5
	sub.w	d1,a5
	rts

; Minterme: d3 = A, d4 = B, d2 = C -> d2 = D.  d3/d4 duerfen fallen.
; Minterme -- die direkt ausgefuehrten: Wort Minterm, Langwort Routine.
Minterme:
	dc.w	$CA
	dc.l	Minterm_ca
	dc.w	$E2
	dc.l	Minterm_e2
	dc.w	$F0
	dc.l	Minterm_f0
	dc.w	$FA
	dc.l	Minterm_fa
	dc.w	$0A
	dc.l	Minterm_0a
	dc.w	$00
	dc.l	Minterm_00
	dc.w	$D8
	dc.l	Minterm_d8
	dc.w	-1
Minterm_f0:				; A
	move.w	d3,d2
	rts
Minterm_fa:				; A | C
	or.w	d3,d2
	rts
Minterm_0a:				; ~A & C
	not.w	d3
	and.w	d3,d2
	rts
Minterm_00:
	moveq	#0,d2
	rts
Minterm_ca:				; A ? B : C
	and.w	d3,d4
	not.w	d3
	and.w	d3,d2
	or.w	d4,d2
	rts
Minterm_e2:				; B ? A : C
	and.w	d4,d3
	not.w	d4
	and.w	d4,d2
	or.w	d3,d2
	rts
Minterm_d8:				; C ? B : A (Extro, Rolltext)
	and.w	d2,d4
	not.w	d2
	and.w	d3,d2
	or.w	d4,d2
	rts
; Minterm_allgemein -- jede der acht Kombinationen, deren Bit in
; Bl_minterm gesetzt ist (Bit 7 = ABC ... Bit 0 = abc).
Minterm_allgemein:
	movem.l	d0/d1/d5-d7,-(sp)
	move.b	Bl_minterm,d7
	moveq	#0,d5
	moveq	#7,d6
.term:	btst	d6,d7
	beq.b	.naechst
	move.w	d3,d0			; A oder nicht A
	btst	#2,d6
	bne.b	.ta
	not.w	d0
.ta:	move.w	d4,d1			; B
	btst	#1,d6
	bne.b	.tb
	not.w	d1
.tb:	and.w	d1,d0
	move.w	d2,d1			; C
	btst	#0,d6
	bne.b	.tc
	not.w	d1
.tc:	and.w	d1,d0
	or.w	d0,d5
.naechst:
	dbf	d6,.term
	move.w	d5,d2
	movem.l	(sp)+,d0/d1/d5-d7
	rts


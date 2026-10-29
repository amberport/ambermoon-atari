; ***************************************************************************
; D3_SUP.S -- die Hardwareschicht unter Thalions 3D-Ansicht (MAP/3D_MAP.S).
; Einheit "bibliothek" (engine.s).
;
; **Wer was macht** (docs/02-3D-Renderpfad.md, Teil A):
;
;   Thalions 3D_MAP.S       Szene, Waende, Objekte, Himmel, Horizont
;   Thalions Rasterer       put_dpoly, draw_zoomshape, Insert_horizon,
;                           Fade_colour: beim Bau aus AM2_CPU herausgezogen
;                           (tools/am2cpu_code.py -> build/am2cpu_code.i,
;                           Teil A7).  Sie zeichnen in Thalions 3D-Puffer
;                           (MOVEP_ptr), nie auf den Schirm.
;   diese Datei             was am Schirm haengt: den Puffer zeigen, eine
;                           Ebene loeschen, und die beiden Weichen.
;
; **Der 3D-Puffer** (Erkenntnis 195): 144x144 Punkte, 72 Byte je Zeile, je
; acht Punkte vier Byte, eins je Ebene 0..3.  Die 3D-Ansicht hat 16 Farben;
; Ebene 4 gehoert den Sternen (Draw_stars zeichnet sie mit Plot_pixel
; unmittelbar auf den Schirm).
; ***************************************************************************

; ---------------------------------------------------------------------------
; D3_CPU -- welchen Weg geht Thalions 3D-Code?
;
; Thalion unterscheidet selbst (3D_MAP.S, CPU_68020_plus): ab dem 68020
; zeichnet der Code texturierte Boeden und Decken (Draw_floor/Draw_ceiling),
; darunter nur einfarbige.  Der Schalter zieht die Weiche:
;
;   D3_CPU_68000 (0)  immer der 68000-Weg -- laeuft ueberall
;   D3_CPU_AUTO  (1)  nach dem Cookie _CPU: ab 20 der 68020-Weg (Vorgabe)
;   D3_CPU_68020 (2)  immer der 68020-Weg
;
; Draw_floor/Draw_ceiling sind Thalions 68020-Code aus AM2_CPU
; (am2cpu_code.py, CPU_020; docs/05 E3).  Thalion ruft sie nur bei
; CPU_68020_plus, der 68000 fuehrt sie nie aus.  D3_CPU_68020 auf einem ST
; stuerzt darum ab.  Vorgabe ist seit 2026-09-29 AUTO (Nutzer, nach dem
; Falcon-Test): Falcon mit Boeden, ST und Rechner ohne Cookie-Jar ohne.  Die
; Weiche auf einem echten ST ist noch nicht getestet.  Festlegen beim Bau:
;     VASM_EXTRA="-DD3_CPU=0" ./tools/baue_alles.sh
; ---------------------------------------------------------------------------
D3_CPU_68000	= 0
D3_CPU_AUTO	= 1
D3_CPU_68020	= 2
	IFND	D3_CPU
D3_CPU	= D3_CPU_AUTO
	ENDC

; Show_MOVEP_screen und Clear_1plane_block kennen zwei Schirme: acht Ebenen
; (Falcon, Ebene 4 und die Bankebenen 5..7) und vier (ST).
	IFNE	(PLANES-8)*(PLANES-4)
	FAIL	"D3_SUP.S: nur PLANES = 8 oder 4"
	ENDC

	SECTION	Fast_DATA,data
; Blitter_or_CPU -- $FF: Thalions CPU-Fassungen und die FAST-Dateien
; (Wall3D/Object3D im Format des 3D-Puffers).  Auf dem Atari gibt es keinen
; Amiga-Blitter; die herausgezogenen Rasterer sind die CPU-Fassungen, und
; die Kantenroutine in put_dpoly fragt den Merker selbst noch einmal ab.
Blitter_or_CPU:	dc.b	$FF
	even

	SECTION	Fast_BSS,bss
CPU_68020_plus:	ds.b	1		; 0 = 68000-Weg (D3_einrichten)
cache_gesetzt:	ds.b	1		; $FF: CACR von uns, alter Wert in cache_alt
	even
cache_alt:	ds.l	1
	IFGT	PLANES-Data_depth
; Satz einer Verlaufszeile in Show_MOVEP_screen (je Wort $FFFF oder 0):
; Bits 0..3 der Verlaufsfarbe, Bits 0..3 des Platzes, Bits 5..7 des
; Platzes, und die Bankmasken der Zeile (d2/d5/a3 der Schleife).
SME_FARBE	equ	0
SME_PLATZ	equ	8
SME_PBANK	equ	16
SME_BANK	equ	22
sme_satz:	ds.w	14
	ENDC

	SECTION	Program,code

; ***************************************************************************
; D3_einrichten -- CPU_68020_plus nach D3_CPU setzen, auf dem 68030 die
; Caches einschalten (Cache030_ein).
;   Aus start (MAIN.S), nach Enter_supervisor: der Cookie-Zeiger $5A0 ist
;   nur im Supervisormodus lesbar.
;   Alle Register bleiben.
; ***************************************************************************
D3_einrichten:
	movem.l	d0,-(sp)
	bsr.b	Cpu_kennung
	sf	CPU_68020_plus
	IFEQ	D3_CPU-D3_CPU_68020
	st	CPU_68020_plus
	ENDC
	IFEQ	D3_CPU-D3_CPU_AUTO
	cmp.l	#20,d0			; 0, 10, 20, 30, 40, 60; -1 ohne Cookie
	scc	CPU_68020_plus
	tst.l	d0
	bpl.b	d3e_cpu
	sf	CPU_68020_plus
d3e_cpu:
	ENDC
	cmp.l	#30,d0
	bne.b	d3e_aus
	bsr.b	Cache030_ein
d3e_aus:
	movem.l	(sp)+,d0
	rts

; Cpu_kennung -- d0.l = Wert des Cookies _CPU (0, 10, 20, 30, 40, 60), -1
; ohne Cookie-Jar oder ohne _CPU (alter ST).  Nur im Supervisormodus.
; Nur d0.
Cpu_kennung:
	move.l	a0,-(sp)
	move.l	$5A0.w,d0		; _p_cookies; 0 = kein Cookie-Jar
	beq.b	cpk_keins
	move.l	d0,a0
cpk_such:
	move.l	(a0),d0
	beq.b	cpk_keins		; Ende der Liste, kein _CPU
	cmp.l	#'_CPU',d0
	beq.b	cpk_da
	addq.l	#8,a0
	bra.b	cpk_such
cpk_da:
	move.l	4(a0),d0
	move.l	(sp)+,a0
	rts
cpk_keins:
	moveq	#-1,d0
	move.l	(sp)+,a0
	rts

; ***************************************************************************
; Cache030_ein / Cache030_zurueck -- Befehls- und Datencache des 68030.
;
; Bisher galt, was der Desktop eingestellt hatte (Optionen, Cache).  Ist er
; aus, laeuft alles langsamer, Thalions enge Schleifen (Rasterer, Boden,
; Decke) am meisten.  Wir schalten beide Caches ein, mit Write-Allocate,
; und loeschen sie dabei; die uebrigen Bits (Burst) bleiben, wie TOS sie
; hatte.  Cache030_zurueck setzt beim Beenden den alten Wert und loescht
; die Caches wieder.
;
; Nur auf dem 68030 (Cookie _CPU = 30): der 68040/060 hat ein anderes CACR.
; Die Ein-/Ausgabe ab $FF0000 haelt der Falcon selbst aus dem Cache
; (Annahme: TOS laeuft mit eingeschaltetem Cache genauso).  Unser Code und
; Thalions schreiben keinen Code zur Laufzeit.
;
; movec steht als dc.w da: engine.s muss durch die 68000-Gegenprobe, und
; auf dem ST laeuft diese Stelle nie.
;   CACR: EI Bit 0, CI 3, ED 8, CD 11, WA 13.
; Nur im Supervisormodus.  Alle Register bleiben.
; ***************************************************************************
Cache030_ein:
	move.l	d0,-(sp)
	dc.w	$4E7A,$0002		; movec cacr,d0
	move.l	d0,cache_alt
	or.w	#$2909,d0		; WA, ED, EI; CD und CI loeschen beide
	dc.w	$4E7B,$0002		; movec d0,cacr
	st	cache_gesetzt
	move.l	(sp)+,d0
	rts

Cache030_zurueck:
	tst.b	cache_gesetzt
	beq.b	c3z_aus
	move.l	d0,-(sp)
	move.l	cache_alt,d0
	or.w	#$0808,d0		; CD, CI: nichts Veraltetes stehen lassen
	dc.w	$4E7B,$0002		; movec d0,cacr
	sf	cache_gesetzt
	move.l	(sp)+,d0
c3z_aus:
	rts

; ***************************************************************************
; Show_MOVEP_screen -- den 3D-Puffer auf den Schirm bringen.
;   IN : d0.w/d1.w = linke obere Ecke (x Vielfaches von 16), d6.w = Breite
;        in 16er-Gruppen, d7.w = Zeilen, a0 = Puffer (d6*8 Byte je Zeile)
;   Alle Register bleiben (wie im Original, AM2_CPU 0:$21B06).
;
; Je 16 Punkte liegen im Puffer acht Byte: 0..3 die Ebenen 0..3 der linken
; acht Punkte, 4..7 die der rechten.  Ebene p unseres Schirms ist also das
; Wort (Byte p, Byte p+4).  Das ist Thalions Format fuer movep: Die linke
; Haelfte geht mit einem movep.l in die oberen Bytes der Ebenenwoerter 0..3,
; die rechte in die unteren (auf dem ST wie auf dem Falcon).
;
; **Ebene 4 bleibt stehen**, wie im Original: dort liegen die Sterne
; (Draw_stars), und Clear_1plane_block raeumt sie vor dem naechsten Bild.
; Die Ebenen darueber (nur Falcon) tragen die Farbbank der Zeile, wo der
; Punkt nicht Farbe 0 ist: dieselbe Regel wie in Put_unmasked_block,
; **0 bleibt 0**.
;
; **Tempo** (Erkenntnis 271): Die Bank wird nur an der Grenze aus
; Farbbank_spanne neu gefragt, nicht je Zeile.  Hat sie keine Bits 5..7
; (Bank 0), stehen in den Ebenen 5..7 nur Nullen, und die Maske entfaellt.
;
; **Farbverlauf (R_range, nur Falcon):** Thalions Copper setzt in einem
; Verlauf je Zeile eine Farbe neu, bei C3_RL Farbe 9 (der Himmel der
; 3D-Staedte); unter dem Verlauf behaelt sie den letzten Wert.  Jede Zeile
; fragt darum Zeilenersatz (RASTER.S, eine Tabelle, billig).  Nennt es eine
; Farbe, bekommt jeder Punkt dieser Farbe statt Bank+Farbe den Platz der
; Zeile, Ebenen 0..3 und 5..7.  Erkannt wird an den Ebenen 0..3, denn der
; Puffer hat nur vier (eine Farbe ab 16 kommt darin nicht vor).  Ebene 4
; bleibt auch hier: Die Plaetze im 3D-Fenster haben dort 0, und
; Clear_1plane_block raeumt die Sterne des letzten Bildes danach weg.
;
; Register in der Schleife: d0/d1/d3 frei, d2/d5/a3 Masken der Ebenen 5..7
; ($FFFF, wo die Bank das Bit hat, sonst 0), d4 Gruppen, d6 Breite (oberes
; Wort: Grenze der Bank), d7 Zeilen, a4 Bildzeile.  In einer Verlaufszeile
; liegen die Masken in sme_satz (a5), d2/d5 sind dort frei.
; ***************************************************************************
Show_MOVEP_screen:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	Work_screen,a1
	move.w	d1,a4			; a4 = Bildzeile
	move.w	d1,d2
	mulu.w	#SCRROW,d2
	add.l	d2,a1
	lsr.w	#4,d0
	mulu.w	#TROW,d0
	add.l	d0,a1			; a1 = linke obere Ecke
	subq.w	#1,d6
	bmi	sms_aus
	subq.w	#1,d7
	bmi	sms_aus
	IFD	ZIEL_ST
	; ---- ST: die vier Ebenen ueber zwei Tabellen und movep (ST_LIB.S,
	; St_movep_schirm).  Ebene 4 (die Sterne) hat der ST nicht.
	; Mit Abschriften (E12) traegt der Puffer schon Register: nur
	; kopieren (St_abschrift_zeigen). ----
	jsr	St_abschrift_aktiv
	beq.b	sms_st_alt
	jsr	St_abschrift_zeigen
	bra	sms_aus
sms_st_alt:
	jsr	St_movep_schirm
	bra	sms_aus
	ENDC
	IFGT	PLANES-Data_depth
	swap	d6
	clr.w	d6			; Grenze 0: die erste Zeile fragt
	swap	d6
	ENDC
sms_zeile:
	move.l	a1,a2
	move.w	d6,d4
	IFGT	PLANES-Data_depth
	; ---- Bank dieser Zeile, neu erst an der Grenze ----
	move.w	a4,d0
	swap	d6
	cmp.w	d6,d0
	bcs.b	sms_bank_gilt
	bsr	Farbbank_spanne
	move.w	d1,d6
	moveq	#0,d2
	btst	#5,d0
	beq.b	sms_b6
	moveq	#-1,d2
sms_b6:	moveq	#0,d5
	btst	#6,d0
	beq.b	sms_b7
	moveq	#-1,d5
sms_b7:	sub.l	a3,a3
	btst	#7,d0
	beq.b	sms_bank_gilt
	move.w	#-1,a3
sms_bank_gilt:
	swap	d6
	; ---- Verlauf in dieser Zeile? ----
	move.w	a4,d0
	jsr	Zeilenersatz		; d0 = Farbe (0 keine), d1 = Platz
	bne	sms_verlauf
sms_flach:
	addq.w	#1,a4
	move.w	d2,d0
	or.w	d5,d0
	move.w	a3,d1
	or.w	d1,d0
	beq.b	sms_null		; Bank ohne Bits 5..7
	ENDC
sms_gruppe:
	move.l	(a0)+,d0		; links: Ebenen 0..3
	movep.l	d0,0(a2)
	IFGT	PLANES-Data_depth
	move.l	(a0)+,d3		; rechts: Ebenen 0..3
	movep.l	d3,1(a2)
	; Punkt ungleich 0: ODER der vier Bytes je Haelfte, dazu Ebene 4
	move.l	d0,d1
	swap	d1
	or.w	d1,d0			; d0.w = (L0|L2, L1|L3)
	move.l	d3,d1
	swap	d1
	or.w	d1,d3			; d3.w = (R0|R2, R1|R3)
	move.w	d0,d1
	lsl.w	#8,d1
	or.w	d1,d0			; oberes Byte: links
	move.w	d3,d1
	lsr.w	#8,d1
	or.w	d3,d1			; unteres Byte: rechts
	move.b	d1,d0
	or.w	8(a2),d0		; Ebene 4 bleibt, zaehlt aber mit
	move.w	d0,d1
	and.w	d2,d1
	move.w	d1,10(a2)
	move.w	d0,d1
	and.w	d5,d1
	move.w	d1,12(a2)
	move.w	a3,d1
	and.w	d0,d1
	move.w	d1,14(a2)
	ELSE
	move.l	(a0)+,d0
	movep.l	d0,1(a2)
	ENDC
	lea	TROW(a2),a2
	dbf	d4,sms_gruppe
	IFGT	PLANES-Data_depth
	bra	sms_weiter
sms_null:
	move.l	(a0)+,d0
	movep.l	d0,0(a2)
	move.l	(a0)+,d0
	movep.l	d0,1(a2)
	move.w	d2,10(a2)		; d2 = 0
	move.l	d2,12(a2)
	lea	TROW(a2),a2
	dbf	d4,sms_null
	bra	sms_weiter

	; ---- Verlaufszeile: d0 = Farbe, d1 = Platz ----
sms_verlauf:
	cmp.w	#16,d0
	bcc	sms_flach		; ab 16 nicht im Puffer
	lea	sme_satz,a5
	move.w	d2,SME_BANK(a5)
	move.w	d5,SME_BANK+2(a5)
	move.w	a3,SME_BANK+4(a5)
	move.l	a5,a6
	moveq	#0,d3
smv_bit:
	btst	d3,d0			; Bits 0..3 der Farbe
	sne	d2
	ext.w	d2
	move.w	d2,SME_FARBE(a6)
	btst	d3,d1			; Bits 0..3 des Platzes
	sne	d2
	ext.w	d2
	move.w	d2,SME_PLATZ(a6)
	addq.l	#2,a6
	addq.w	#1,d3
	cmp.w	#4,d3
	bne.b	smv_bit
	lea	SME_PBANK(a5),a6
	moveq	#5,d3
smv_bank:
	btst	d3,d1			; Bits 5..7 des Platzes
	sne	d2
	ext.w	d2
	move.w	d2,(a6)+
	addq.w	#1,d3
	cmp.w	#8,d3
	bne.b	smv_bank
	addq.w	#1,a4
sme_gruppe:
	move.l	(a0)+,d0
	movep.l	d0,0(a2)
	move.l	(a0)+,d0
	movep.l	d0,1(a2)
	; Maske der Verlaufsfarbe: alle vier Ebenen wie die Farbe
	move.w	(a2),d1		; eor nimmt nur ein Datenregister als Quelle
	move.w	SME_FARBE(a5),d2
	eor.w	d2,d1
	move.w	2(a2),d0
	move.w	SME_FARBE+2(a5),d2
	eor.w	d2,d0
	or.w	d0,d1
	move.w	4(a2),d0
	move.w	SME_FARBE+4(a5),d2
	eor.w	d2,d0
	or.w	d0,d1
	move.w	6(a2),d0
	move.w	SME_FARBE+6(a5),d2
	eor.w	d2,d0
	or.w	d0,d1
	not.w	d1			; d1 = Maske
	; Punkt ungleich 0, Ebene 4 zaehlt mit; Bank nur ausserhalb der Maske
	move.w	(a2),d2
	or.w	2(a2),d2
	or.w	4(a2),d2
	or.w	6(a2),d2
	or.w	8(a2),d2
	move.w	d1,d3
	not.w	d3
	and.w	d3,d2
	tst.w	d1
	beq.b	sme_bank
	; Ebenen 0..3 unter der Maske: der Platz
	move.w	SME_PLATZ(a5),d0
	and.w	d1,d0
	and.w	d3,(a2)
	or.w	d0,(a2)
	move.w	SME_PLATZ+2(a5),d0
	and.w	d1,d0
	and.w	d3,2(a2)
	or.w	d0,2(a2)
	move.w	SME_PLATZ+4(a5),d0
	and.w	d1,d0
	and.w	d3,4(a2)
	or.w	d0,4(a2)
	move.w	SME_PLATZ+6(a5),d0
	and.w	d1,d0
	and.w	d3,6(a2)
	or.w	d0,6(a2)
sme_bank:
	; Ebenen 5..7: Bank der Zeile ausserhalb, Bank des Platzes unter der Maske
	move.w	SME_BANK(a5),d0
	and.w	d2,d0
	move.w	SME_PBANK(a5),d5
	and.w	d1,d5
	or.w	d5,d0
	move.w	d0,10(a2)
	move.w	SME_BANK+2(a5),d0
	and.w	d2,d0
	move.w	SME_PBANK+2(a5),d5
	and.w	d1,d5
	or.w	d5,d0
	move.w	d0,12(a2)
	move.w	SME_BANK+4(a5),d0
	and.w	d2,d0
	move.w	SME_PBANK+4(a5),d5
	and.w	d1,d5
	or.w	d5,d0
	move.w	d0,14(a2)
	lea	TROW(a2),a2
	dbf	d4,sme_gruppe
	move.w	SME_BANK(a5),d2		; Bankmasken zurueck
	move.w	SME_BANK+2(a5),d5
	move.w	SME_BANK+4(a5),a3
sms_weiter:
	ENDC
	lea	SCRROW(a1),a1
	dbf	d7,sms_zeile
sms_aus:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Clear_1plane_block -- eine Ebene in einem Rechteck loeschen.
;   IN : d0.w/d1.w = linke obere Ecke (x Vielfaches von 16), d5.w = Ebene,
;        d6.w = Breite in 16er-Gruppen, d7.w = Zeilen
;   Alle Register bleiben (im Original d2/d3/a0/a6 gesichert, der Rest
;   unberuehrt; AM2_CPU 0:$21592).
;
; 3D_MAP.S raeumt damit die Sterne des letzten Bildes aus Ebene 4.  Eine
; Ebene, die unser Schirm nicht hat (ST: Ebene 4), gibt es nicht zu loeschen.
;
; **0 bleibt 0:** Wird ein Punkt dadurch zu Farbe 0 (in Thalions fuenf
; Ebenen), fallen auch seine Bankbits.  Sonst stuende dort die Farbe 0 der
; Bank statt der 0.
;
; **Tempo:** Die Bank wird wie in Show_MOVEP_screen nur an der Grenze aus
; Farbbank_spanne gefragt.  Hat sie keine Bits 5..7 (Bank 0, die 3D-Ansicht
; immer), stehen dort nur Nullen, und es bleibt das clr.w.
; ***************************************************************************
Clear_1plane_block:
	movem.l	d0-d7/a0-a2,-(sp)
	cmp.w	#PLANES,d5
	bcc.b	c1p_aus
	move.l	Work_screen,a1
	move.w	d1,a0			; a0 = Bildzeile
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	lsr.w	#4,d0
	mulu.w	#TROW,d0
	add.l	d0,a1
	subq.w	#1,d6
	bmi.b	c1p_aus
	subq.w	#1,d7
	bmi.b	c1p_aus
	add.w	d5,d5			; Versatz der Ebene in der Gruppe
	IFGT	PLANES-Data_depth
	moveq	#0,d2			; Grenze 0: die erste Zeile fragt
	ENDC
c1p_zeile:
	move.l	a1,a2
	move.w	d6,d4
	IFGT	PLANES-Data_depth
	; ---- Bank dieser Zeile, neu erst an der Grenze ----
	move.w	a0,d0
	cmp.w	d2,d0
	bcs.b	c1p_bank_gilt
	bsr	Farbbank_spanne
	move.w	d1,d2
	move.w	d0,d1
	and.w	#$E0,d1			; d1 = Bits 5..7 der Bank
c1p_bank_gilt:
	addq.w	#1,a0
	tst.w	d1
	bne.b	c1p_gruppe
	add.w	d5,a2
c1p_nur:
	clr.w	(a2)
	lea	TROW(a2),a2
	dbf	d4,c1p_nur
	bra.b	c1p_weiter
	ENDC
c1p_gruppe:
	clr.w	0(a2,d5.w)
	IFGT	PLANES-Data_depth
	move.w	(a2),d3
	or.w	2(a2),d3
	or.w	4(a2),d3
	or.w	6(a2),d3
	or.w	8(a2),d3
	and.w	d3,10(a2)
	and.w	d3,12(a2)
	and.w	d3,14(a2)
	ENDC
	lea	TROW(a2),a2
	dbf	d4,c1p_gruppe
c1p_weiter:
	lea	SCRROW(a1),a1
	dbf	d7,c1p_zeile
c1p_aus:
	movem.l	(sp)+,d0-d7/a0-a2
	rts

; ***************************************************************************
; AMIGA_MESSEN.S -- Messung (Schalter AMIGA_MESSEN, Tempo, docs/11 7.6), fuer
; Fantasy-Intro, Intro und Extro.  Ohne SECTION: im Codeabschnitt des
; Einbinders; Variablen in amiga_messen_bss.i, Texte in
; amiga_messen_daten.i.
;
; MFP Timer A stoesst rund 1000-mal je Sekunde an, auf Stufe 6, also auch
; mitten in einem VBL (Stufe 4).  Mess_timer liest den PC des unterbrochenen
; Codes und zaehlt:
;   - ein Fach je 64 Byte Programm ab `start` (Mess_faecher, Langworte);
;     die Linkkarte ordnet die Faecher den Routinen zu.  Ausserhalb:
;     Mess_fremd.
;   - drei Arten: Blits (MESS_BLIT_VON .. MESS_BLIT_BIS), einen zweiten
;     Bereich (MESS_ZWEI_VON .. MESS_ZWEI_BIS, Name Text_mess_zwei), sonst.
;     Je Sekunde eine Zeile in Mess_verlauf, dazu die Summen.
; Der Einbinder setzt die vier Grenzen (Mess_datei, den Dateinamen, schreibt
; der Bau nach build/mess_name.i) und
; Text_mess_zwei, ruft Mess_starten nach dem Einrichten, Mess_stoppen vor
; dem Abraeumen und Mess_ausgeben danach; sein VBL zaehlt Mess_vbls hoch.
; MESS_MIT_K2: K2_fremd gibt es.
; Mit MESS_ENDE=n endet die Messung nach n Sekunden ueber MESS_ABRAEUMEN;
; alle drei kehren danach zum Desktop zurueck (FEEDIAG, INTRDIAG, fuer die
; Hardware; im Emulator endet der Lauf vorher mit --run-vbls).
; Nur 68000-Befehle.
;
; BLIT_STATISTIK (dazu): Amiga_blit ruft Bs_zaehlen, das jeden Blit nach
; seiner Art in Bs_tabelle zaehlt (Anzahl, Worte, breitester); Mess_timer
; rechnet jede Probe in den Blits der Art des laufenden Blits zu.  Die
; Tabelle steht in der Datei hinter dem Verlauf.
; ***************************************************************************
	IFD	AMIGA_MESSEN
MFP_IERA	equ	$FFFFFA07
MFP_ISRA	equ	$FFFFFA0F
MFP_IMRA	equ	$FFFFFA13
MFP_TACR	equ	$FFFFFA19
MFP_TADR	equ	$FFFFFA1F
VEK_TIMER_A	equ	$134
MESS_TEILER	equ	5		; 2457600 / 64 = 38400 Hz
MESS_DATEN	equ	38		; / 38 = 1010 Hz
MESS_JE_SEKUNDE	equ	1010
MESS_FACH	equ	64		; Bytes je Fach
MESS_FAECHER	equ	1024		; deckt 64 KB Programm
MESS_SEKUNDEN	equ	900		; Verlauf: 15 Minuten
MESS_FCREATE	equ	$3C		; GEMDOS, hier selbst: die Vorspanne
MESS_FCLOSE	equ	$3E		; der Einbinder kennen sie nicht alle
MESS_FWRITE	equ	$40
MESS_HZ200	equ	$4BA		; _hz_200: Timer C des TOS, 200 je Sekunde

Mess_starten:
	move.w	sr,-(sp)
	or.w	#$0700,sr
	st	Mess_laeuft
	clr.l	Mess_vbls
	move.l	MESS_HZ200.w,Mess_hz_start
	move.l	VEK_TIMER_A.w,Mess_alter_vektor
	move.b	MFP_TACR.w,Mess_alt_tacr
	move.b	MFP_IERA.w,Mess_alt_iera
	move.b	MFP_IMRA.w,Mess_alt_imra
	clr.b	MFP_TACR.w
	move.l	#Mess_timer,VEK_TIMER_A.w
	move.b	#MESS_DATEN,MFP_TADR.w
	bset	#5,MFP_IERA.w
	bset	#5,MFP_IMRA.w
	move.b	#MESS_TEILER,MFP_TACR.w
	move.w	(sp)+,sr
	rts

Mess_stoppen:
	tst.b	Mess_laeuft		; wiederholbar (Notausgang)
	bne.b	.laeuft
	rts
.laeuft:
	sf	Mess_laeuft
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	Mess_vbls,Mess_vbl_zahl
	move.l	MESS_HZ200.w,d0		; die Uhr des TOS: echte Laufzeit
	sub.l	Mess_hz_start,d0
	move.l	d0,Mess_hz_zahl
	clr.b	MFP_TACR.w
	bclr	#5,MFP_IERA.w
	bclr	#5,MFP_IMRA.w
	move.b	Mess_alt_iera,d0
	and.b	#$20,d0
	or.b	d0,MFP_IERA.w
	move.b	Mess_alt_imra,d0
	and.b	#$20,d0
	or.b	d0,MFP_IMRA.w
	move.l	Mess_alter_vektor,VEK_TIMER_A.w
	move.b	Mess_alt_tacr,MFP_TACR.w
	move.w	(sp)+,sr
	rts

Mess_timer:
	movem.l	d0-d1/a0,-(sp)
	move.l	12+2(sp),d0		; PC des unterbrochenen Codes
	moveq	#8,d1			; Art: sonst
	cmp.l	#MESS_BLIT_VON,d0
	blo.b	.art
	cmp.l	#MESS_BLIT_BIS,d0
	bhs.b	.anz
	IFD	BLIT_STATISTIK
	move.l	Bs_aktuell,d1		; der laufende Blit, nach Art
	beq.b	.bs_ohne
	move.l	d1,a0
	addq.l	#1,BS_PROBEN(a0)
.bs_ohne:
	ENDC
	moveq	#0,d1			; Blits
	bra.b	.art
.anz:	cmp.l	#MESS_ZWEI_VON,d0
	blo.b	.art
	cmp.l	#MESS_ZWEI_BIS,d0
	bhs.b	.art
	moveq	#4,d1			; zweiter Bereich
.art:	lea	Mess_summe,a0
	addq.l	#1,0(a0,d1.w)
	lsr.w	#1,d1
	lea	Mess_sekunde,a0
	addq.w	#1,0(a0,d1.w)
	sub.l	#start,d0
	cmp.l	#MESS_FAECHER*MESS_FACH,d0
	bhs.b	.fremd
	lsr.l	#6,d0			; MESS_FACH
	lsl.l	#2,d0
	lea	Mess_faecher,a0
	addq.l	#1,0(a0,d0.l)
	bra.b	.zeit
.fremd:	addq.l	#1,Mess_fremd
.zeit:	addq.w	#1,Mess_takt
	cmp.w	#MESS_JE_SEKUNDE,Mess_takt
	blo.b	.aus
	clr.w	Mess_takt
	move.w	Mess_zeilen,d0
	cmp.w	#MESS_SEKUNDEN,d0
	bhs.b	.voll
	mulu.w	#6,d0
	lea	Mess_verlauf,a0
	add.l	d0,a0
	move.l	Mess_sekunde,(a0)+
	move.w	Mess_sekunde+4,(a0)
	addq.w	#1,Mess_zeilen
	IFD	MESS_ENDE
	cmp.w	#MESS_ENDE,Mess_zeilen
	bne.b	.voll
	move.w	#$2700,12(sp)		; zurueck in Mess_abbruch statt ins Programm
	move.l	#Mess_abbruch,12+2(sp)
	ENDC
.voll:	clr.l	Mess_sekunde
	clr.w	Mess_sekunde+4
.aus:	move.b	#%11011111,MFP_ISRA.w	; Ende des Interrupts (Software-EOI)
	movem.l	(sp)+,d0-d1/a0
	rte

	IFD	MESS_ENDE
; Mess_abbruch -- (Diagnose MESS_ENDE=n) nach n Sekunden
; das Programm verlassen, wo es gerade steht: Thalions Menue endet sonst nur
; auf einen Mausklick.  Abraeumen, Messung ausgeben; danach wartet
; Mess_ausgeben auf eine Taste, und der Emulator endet mit --run-vbls.
Mess_abbruch:
	lea	Mess_stapel_oben,sp
	move.w	#$2300,sr
	bsr	MESS_ABRAEUMEN
.halt:	bra.b	.halt
	ENDC

	IFD	BLIT_STATISTIK
; ***************************************************************************
; Bs_zaehlen -- (Diagnose BLIT_STATISTIK) den Blit in Amiga_register nach
; seiner Art zaehlen.  Art (Wort): BLTCON0 Bits 0-11 (USEx, Minterm), dazu
; Bit 12 DESC, Bit 13 Linie oder Fuellen, Bit 14 ASH ungleich 0, Bit 15
; C und D dieselbe Stelle.  Eintrag (BS_LAENGE): Art.w, breitester.w,
; Anzahl.l, Worte.l, Proben.l.  Ist die Tabelle voll: Bs_ueberlauf.
;   Veraendert d0/d1/a0/a4 (Amiga_blit darf das).
; ***************************************************************************
BS_MAX		equ	128
BS_LAENGE	equ	16
BS_BREITE	equ	2
BS_ANZAHL	equ	4
BS_WORTE	equ	8
BS_PROBEN	equ	12

Bs_zaehlen:
	lea	Amiga_register,a4
	move.w	AR_BLTCON0(a4),d0
	and.w	#$0FFF,d0
	move.w	AR_BLTCON1(a4),d1
	btst	#1,d1
	beq.b	.auf
	bset	#12,d0
.auf:	and.w	#%11001,d1		; LINE, IFE, EFE
	beq.b	.flach
	bset	#13,d0
.flach:	move.w	AR_BLTCON0(a4),d1
	and.w	#$F000,d1
	beq.b	.ohne_ash
	bset	#14,d0
.ohne_ash:
	move.l	AR_BLTCPT(a4),d1
	cmp.l	AR_BLTDPT(a4),d1
	bne.b	.getrennt
	bset	#15,d0
.getrennt:
	lea	Bs_tabelle,a0
	move.w	Bs_eintraege,d1
	bra.b	.such_ein
.such:	cmp.w	(a0),d0
	beq.b	.da
	lea	BS_LAENGE(a0),a0
.such_ein:
	dbf	d1,.such
	cmp.w	#BS_MAX,Bs_eintraege	; neue Art
	bhs.b	.voll
	addq.w	#1,Bs_eintraege
	move.w	d0,(a0)
.da:	move.l	a0,Bs_aktuell
	addq.l	#1,BS_ANZAHL(a0)
	move.w	AR_BLTSIZE(a4),d0
	moveq	#63,d1
	and.w	d0,d1			; Worte je Zeile
	bne.b	.w
	moveq	#64,d1
.w:	lsr.w	#6,d0			; Zeilen
	bne.b	.h
	move.w	#1024,d0
.h:	cmp.w	BS_BREITE(a0),d1
	bls.b	.schmal
	move.w	d1,BS_BREITE(a0)
.schmal:
	mulu.w	d1,d0
	add.l	d0,BS_WORTE(a0)
	rts
.voll:	clr.l	Bs_aktuell
	addq.w	#1,Bs_ueberlauf
	rts
	ENDC

; ***************************************************************************
; Mess_ausgeben -- nach dem Abraeumen: Datei schreiben, Summen und die
; vollsten Faecher auf den Desktop, auf eine Taste warten.
; Datei: "AMES", Proben je Sekunde.w, Fachgroesse.w, Faecher.w, Sekunden.w,
; Summen 3.l (Blits, zweiter Bereich, sonst), Mess_fremd.l, Bl_anzahl.w,
; Bl_schnell.w, Bl_fremd.w, K2_fremd.w, dann die Faecher (Langworte) und
; der Verlauf (je Sekunde 3 Worte).  Mit BLIT_STATISTIK danach "BSTA",
; Eintraege.w, Ueberlauf.w und die Eintraege von Bs_tabelle.  Zuletzt
; "VBLS" und die VBLs von Mess_starten bis Mess_stoppen (.l): die echte
; Laufzeit.  Ein HOG-Blit haelt Timer A auf, dort fehlen Proben.  Dahinter
; "H200" und die Takte von _hz_200 (.l): die Laufzeit nach der Uhr des TOS,
; daraus die Bildfrequenz (50 oder 60 Hz).  Setzt der
; Einbinder MESS_ZUSATZ, folgt sein Block: 8 Byte MESS_ZUSATZ_KOPF, dann
; MESS_ZUSATZ_LAENGE Byte ab MESS_ZUSATZ (Fantasy-Intro: "BILD").
; ***************************************************************************
MESS_KOPF_LAENGE	equ	36

Mess_ausgeben:
	move.l	#'AMES',Mess_kopf
	move.w	#MESS_JE_SEKUNDE,Mess_kopf_takt
	move.w	#MESS_FACH,Mess_kopf_fach
	move.w	#MESS_FAECHER,Mess_kopf_faecher
	move.w	Mess_zeilen,Mess_kopf_sekunden
	movem.l	Mess_summe,d0-d2
	movem.l	d0-d2,Mess_kopf_summen
	move.l	Mess_fremd,Mess_kopf_fremd
	move.w	Bl_anzahl,Mess_kopf_blits
	move.w	Bl_schnell,Mess_kopf_blits+2
	move.w	Bl_fremd,Mess_kopf_blits+4
	IFD	MESS_MIT_K2
	move.w	K2_fremd,Mess_kopf_blits+6
	ENDC

	clr.w	-(sp)			; Datei anlegen
	pea	Mess_datei
	move.w	#MESS_FCREATE,-(sp)
	trap	#1
	addq.l	#8,sp
	move.w	d0,Mess_handle
	bmi	.dateifehler
	pea	Mess_kopf
	move.l	#MESS_KOPF_LAENGE+4*MESS_FAECHER,-(sp)
	bsr	.schreiben
	pea	Mess_verlauf
	moveq	#0,d0
	move.w	Mess_zeilen,d0
	mulu.w	#6,d0
	move.l	d0,-(sp)
	bsr	.schreiben
	IFD	BLIT_STATISTIK
	move.l	#'BSTA',Bs_kopf
	pea	Bs_kopf
	moveq	#0,d0
	move.w	Bs_eintraege,d0
	lsl.l	#4,d0			; BS_LAENGE
	addq.l	#8,d0
	move.l	d0,-(sp)
	bsr	.schreiben
	ENDC
	move.l	#'VBLS',Mess_vbl_kopf
	move.l	#'H200',Mess_hz_kopf
	pea	Mess_vbl_kopf		; VBLS und H200
	move.l	#16,-(sp)
	bsr	.schreiben
	IFD	MESS_ZUSATZ		; ein Block des Einbinders: Kopf, Daten
	pea	MESS_ZUSATZ_KOPF
	move.l	#8,-(sp)
	bsr	.schreiben
	pea	MESS_ZUSATZ
	move.l	#MESS_ZUSATZ_LAENGE,-(sp)
	bsr	.schreiben
	ENDC
	move.w	Mess_handle,-(sp)
	move.w	#MESS_FCLOSE,-(sp)
	trap	#1
	addq.l	#4,sp
	lea	Text_mess_datei_ok,a0
	bra	.zeigen
.dateifehler:
	lea	Text_mess_datei_fehler,a0
	bra	.zeigen
; (Laenge.l, Puffer.l auf dem Stapel, hinter der Ruecksprungadresse)
.schreiben:
	move.l	8(sp),-(sp)		; Puffer
	move.l	8(sp),-(sp)		; Laenge
	move.w	Mess_handle,-(sp)
	move.w	#MESS_FWRITE,-(sp)
	trap	#1
	lea	12(sp),sp
	move.l	(sp)+,a0		; zurueck, die zwei Argumente weg
	addq.l	#8,sp
	jmp	(a0)

.zeigen:
	move.l	a0,-(sp)		; Zeile zur Datei
	lea	Mess_text,a1
	lea	Text_mess_kopf,a0
	bsr	Mess_anhaengen
	move.l	Mess_summe,d0
	add.l	Mess_summe+4,d0
	add.l	Mess_summe+8,d0
	move.l	d0,Mess_gesamt
	bsr	Mess_zahl
	lea	Text_mess_blits,a0
	bsr	Mess_anhaengen
	move.l	Mess_summe,d0
	bsr	Mess_prozent
	lea	Text_mess_zwei,a0
	bsr	Mess_anhaengen
	move.l	Mess_summe+4,d0
	bsr	Mess_prozent
	lea	Text_mess_sonst,a0
	bsr	Mess_anhaengen
	move.l	Mess_summe+8,d0
	bsr	Mess_prozent
	lea	Text_mess_vbls,a0
	bsr	Mess_anhaengen
	move.l	Mess_vbl_zahl,d0
	bsr	Mess_zahl
	lea	Text_mess_hz,a0
	bsr	Mess_anhaengen
	move.l	Mess_hz_zahl,d0
	bsr	Mess_zahl
	lea	Text_mess_frequenz,a0
	bsr	Mess_anhaengen
	move.l	Mess_vbl_zahl,d0	; VBLs * 200 / Takte, gerundet
	move.l	Mess_hz_zahl,d1
	beq.b	.ohne_uhr
.klein:	cmp.l	#$FFFF,d1		; Teiler in ein Wort
	bls.b	.teilen
	lsr.l	#1,d1
	lsr.l	#1,d0
	bra.b	.klein
.teilen:
	mulu.w	#200,d0
	move.l	d1,d2
	lsr.l	#1,d2
	add.l	d2,d0
	divu.w	d1,d0
	and.l	#$FFFF,d0
	bsr	Mess_zahl
.ohne_uhr:
	lea	Text_mess_anzahl,a0
	bsr	Mess_anhaengen
	moveq	#0,d0
	move.w	Bl_anzahl,d0
	bsr	Mess_zahl
	lea	Text_mess_schnell,a0
	bsr	Mess_anhaengen
	moveq	#0,d0
	move.w	Bl_schnell,d0
	bsr	Mess_zahl
	IFD	ZIEL_SCHIRME
	lea	Text_mess_ziel,a0	; Schirme im Zielformat (AMIGA_ZIEL.S)
	bsr	Mess_anhaengen
	move.l	Bl_ziel,d0
	bsr	Mess_zahl
	lea	Text_mess_fenster,a0
	bsr	Mess_anhaengen
	move.l	Bl_fenster,d0
	bsr	Mess_zahl
	lea	Text_mess_geholt,a0
	bsr	Mess_anhaengen
	move.l	Zl_geholt,d0
	bsr	Mess_zahl
	lea	Text_mess_gebracht,a0
	bsr	Mess_anhaengen
	move.l	Zl_gebracht,d0
	bsr	Mess_zahl
	lea	Text_mess_umgesetzt,a0	; the fallback (E30): should be 0
	bsr	Mess_anhaengen
	move.l	Anz_umgesetzt,d0
	bsr	Mess_zahl
	lea	Text_mess_gerollt,a0
	bsr	Mess_anhaengen
	move.l	Anz_gerollt,d0
	bsr	Mess_zahl
	IFD	BLIT_PRUEF
	lea	Text_mess_zgeprueft,a0
	bsr	Mess_anhaengen
	move.l	Bl_ziel_geprueft,d0
	bsr	Mess_zahl
	ENDC
	ENDC
	IFD	BLIT_PRUEF
	lea	Text_mess_abweichung,a0
	bsr	Mess_anhaengen
	moveq	#0,d0
	move.w	Bl_abweichung,d0
	bsr	Mess_zahl
	lea	Text_mess_ungeprueft,a0
	bsr	Mess_anhaengen
	moveq	#0,d0
	move.w	Bl_ungeprueft,d0
	bsr	Mess_zahl
	tst.w	Bl_ungeprueft		; der letzte: CON0 CON1 SIZE DMOD
	beq.b	.alle_geprueft
	lea	Pr_letzt,a2
	moveq	#4-1,d3
.letzt:	move.b	#' ',(a1)+
	move.w	(a2)+,d0
	bsr	Mess_hex
	dbf	d3,.letzt
.alle_geprueft:
	ENDC
	IFD	STRAHL
	bsr	St_text
	ENDC
	IFD	ZOOM_PRUEF
	bsr	Zp_text			; intro/INTRO_ZOOM.S
	ENDC
	lea	Text_mess_faecher,a0
	bsr	Mess_anhaengen
	moveq	#6-1,d7			; die sechs vollsten Faecher
.fach:	lea	Mess_faecher,a0
	moveq	#0,d1			; groesster Wert
	moveq	#-1,d2			; sein Fach
	move.w	#MESS_FAECHER-1,d3
	moveq	#0,d4
.such:	move.l	(a0)+,d0
	cmp.l	d1,d0
	bls.b	.kleiner
	move.l	d0,d1
	move.w	d4,d2
.kleiner:
	addq.w	#1,d4
	dbf	d3,.such
	tst.w	d2
	bmi.b	.fertig
	lea	Mess_faecher,a0		; das Fach nicht noch einmal
	moveq	#0,d0
	move.w	d2,d0
	lsl.l	#2,d0
	clr.l	0(a0,d0.l)
	move.l	d1,d5
	move.b	#' ',(a1)+
	move.b	#'+',(a1)+
	move.w	d2,d0
	mulu.w	#MESS_FACH,d0
	bsr	Mess_hex
	move.b	#':',(a1)+
	move.l	d5,d0
	bsr	Mess_prozent
	dbf	d7,.fach
.fertig:
	move.l	(sp)+,a0
	bsr	Mess_anhaengen
	tst.w	Mess_handle
	bmi.b	.ohne_namen
	lea	Mess_datei,a0
	bsr	Mess_anhaengen
.ohne_namen:
	lea	Text_mess_ende,a0
	bsr	Mess_anhaengen
	clr.b	(a1)
	lea	Mess_text,a0		; dieselbe Seite als Text in die Datei
	moveq	#0,d0
	bsr	Mess_text_sichern
	pea	Mess_text
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
	rts

; Mess_text_sichern -- Text a0 (mit Null) in die Textdatei: Mess_datei mit
; der Endung .TXT.  d0 = 0 legt sie neu an, sonst wird angehaengt (der
; Einbinder schreibt so eigene Seiten dazu).  Fehler bleiben still.
;   Veraendert d0-d2/a0-a2.
MESS_FOPEN	equ	$3D
MESS_FSEEK	equ	$42

Mess_text_sichern:
	movem.l	d3-d4/a3,-(sp)
	move.l	a0,a3
	move.w	d0,d4
	lea	Mess_datei,a0		; Name: bis zum Punkt, dann .TXT
	lea	Mess_txt_name,a1
.n:	move.b	(a0)+,d1
	beq.b	.endung
	cmp.b	#'.',d1
	beq.b	.endung
	move.b	d1,(a1)+
	bra.b	.n
.endung:
	move.b	#'.',(a1)+
	move.b	#'T',(a1)+
	move.b	#'X',(a1)+
	move.b	#'T',(a1)+
	clr.b	(a1)
	tst.w	d4
	bne.b	.oeffnen
	clr.w	-(sp)
	pea	Mess_txt_name
	move.w	#MESS_FCREATE,-(sp)
	trap	#1
	addq.l	#8,sp
	move.w	d0,d3
	bmi.b	.aus
	bra.b	.schreiben
.oeffnen:
	move.w	#1,-(sp)		; nur schreiben
	pea	Mess_txt_name
	move.w	#MESS_FOPEN,-(sp)
	trap	#1
	addq.l	#8,sp
	move.w	d0,d3
	bmi.b	.aus
	move.w	#2,-(sp)		; ans Ende
	move.w	d3,-(sp)
	clr.l	-(sp)
	move.w	#MESS_FSEEK,-(sp)
	trap	#1
	lea	10(sp),sp
.schreiben:
	move.l	a3,a0			; Laenge
	moveq	#0,d0
.l:	tst.b	(a0)+
	beq.b	.lang
	addq.l	#1,d0
	bra.b	.l
.lang:	move.l	a3,-(sp)
	move.l	d0,-(sp)
	move.w	d3,-(sp)
	move.w	#MESS_FWRITE,-(sp)
	trap	#1
	lea	12(sp),sp
	move.w	d3,-(sp)
	move.w	#MESS_FCLOSE,-(sp)
	trap	#1
	addq.l	#4,sp
.aus:	movem.l	(sp)+,d3-d4/a3
	rts

; Mess_anhaengen -- a0 (mit Null) nach a1, a1 dahinter.
Mess_anhaengen:
	move.b	(a0)+,(a1)+
	bne.b	Mess_anhaengen
	subq.l	#1,a1
	rts

; Mess_zahl -- d0.l ohne Vorzeichen dezimal nach a1, a1 dahinter.
;   Veraendert d0-d2.
Mess_zahl:
	moveq	#0,d2			; Ziffern auf dem Stapel
.teile:	moveq	#0,d1			; d0 / 10 mit zwei divu.w
	swap	d0
	move.w	d0,d1
	divu.w	#10,d1			; Rest:Quotient des oberen Worts
	move.w	d1,d0
	swap	d0
	move.w	d0,d1
	divu.w	#10,d1			; Rest:Quotient des unteren
	move.w	d1,d0			; d0 = Quotient
	swap	d1
	move.w	d1,-(sp)		; Ziffer
	addq.w	#1,d2
	tst.l	d0
	bne.b	.teile
	subq.w	#1,d2
.schreib:
	move.w	(sp)+,d0
	add.b	#'0',d0
	move.b	d0,(a1)+
	dbf	d2,.schreib
	rts

; Mess_prozent -- d0.l als Anteil an Mess_gesamt, "nn%", nach a1.
;   Veraendert d0-d2.
Mess_prozent:
	move.l	Mess_gesamt,d1
	beq.b	.null
.klein:	cmp.l	#$FFFF,d1
	bls.b	.teilen
	lsr.l	#1,d1
	lsr.l	#1,d0
	bra.b	.klein
.teilen:
	mulu.w	#100,d0
	divu.w	d1,d0
	and.l	#$FFFF,d0
	bsr	Mess_zahl
.null:	move.b	#'%',(a1)+
	rts

; Mess_hex -- d0.w als $hhhh nach a1.  Veraendert d0-d2.
Mess_hex:
	move.b	#'$',(a1)+
	moveq	#4-1,d2
.h:	rol.w	#4,d0
	moveq	#15,d1
	and.w	d0,d1
	move.b	.ziffern(pc,d1.w),(a1)+
	dbf	d2,.h
	rts
.ziffern:
	dc.b	"0123456789ABCDEF"
	even

; ***************************************************************************
; STRAHL (amiga_strahl.i): Schreiben wir in Zeilen, die der Videl gerade
; zeigt?  Der Videozaehler des Videl ($FF8205/07/09) zeigt, welches Byte er
; als naechstes holt.  Er wird vor und nach dem Schreiben gelesen; liegt er
; im geschriebenen Schirm, ergibt er die Zeile des Strahls.  Der Strahl lief
; dazwischen von der einen zur anderen Zeile (ueber das Bildende, wenn die
; zweite kleiner ist).  Ein Treffer: Diese Spanne schneidet die geschriebenen
; Zeilen.  Laeuft ein Schreiben laenger als ein ganzes Bild, sieht das die
; Pruefung nicht.
; ***************************************************************************
	IFD	STRAHL
	IFND	V_ZAEHL_H		; amiga_vorspann.i has them already
V_ZAEHL_H	equ	$FFFF8205
V_ZAEHL_M	equ	$FFFF8207
V_ZAEHL_L	equ	$FFFF8209
	ENDC

; St_vorher -- a0 = Satz: Videozaehler nach ST_VOR.  Alle Register bleiben.
St_vorher:
	move.l	d0,-(sp)
	bsr.b	St_zaehler
	move.l	d0,ST_VOR(a0)
	move.l	(sp)+,d0
	rts

; St_zaehler -- d0.l = Videozaehler.  H und M werden zweimal gelesen; hat
; sich eins dazwischen geaendert, noch einmal.
St_zaehler:
	move.l	d1,-(sp)
.n:	moveq	#0,d0
	move.b	V_ZAEHL_H,d0
	swap	d0
	moveq	#0,d1
	move.b	V_ZAEHL_M,d1
	move.b	V_ZAEHL_L,d0
	cmp.b	V_ZAEHL_M,d1
	bne.b	.n
	swap	d0
	cmp.b	V_ZAEHL_H,d0
	bne.b	.n
	swap	d0
	lsl.w	#8,d1
	or.w	d1,d0
	move.l	(sp)+,d1
	rts

; St_basis -- d0.l = Bildbasis, wie sie in V_BASIS steht.
St_basis:
	moveq	#0,d0
	move.b	V_BASIS_H,d0
	swap	d0
	move.b	V_BASIS_M,d0
	lsl.w	#8,d0
	move.b	V_BASIS_L,d0
	rts

; St_zeile -- d0.l = Videozaehler, a1 = Schirm -> d0.w = Zeile im gezeigten
; Bereich (0 .. Anzeige_zeilen-1), sonst -1.  Veraendert nur d0.
St_zeile:
	sub.l	a1,d0
	bmi.b	.nein
	move.l	d1,-(sp)
	move.w	Anzeige_zeilen,d1
	mulu.w	#FALCON_ZEILE,d1
	cmp.l	d1,d0
	bhs.b	.drunter
	move.l	(sp)+,d1
	divu.w	#FALCON_ZEILE,d0
	rts
.drunter:
	move.l	(sp)+,d1
.nein:	moveq	#-1,d0
	rts

; St_nachher -- a0 = Satz, a1 = Schirm (0: der in V_BASIS), d0.w = erste
; Zeile, d1.w = Zeilen.  Zaehlt Aufruf, Treffer und ob der Strahl danach im
; Bild dieses Schirms steht.  Alle Register bleiben.
St_nachher:
	movem.l	d0-d6/a1,-(sp)
	addq.l	#1,ST_AUFRUFE(a0)
	move.w	d0,d4			; Bereich [d4, d5)
	move.w	d0,d5
	add.w	d1,d5
	move.l	a1,d0
	bne.b	.schirm
	bsr.b	St_basis
	move.l	d0,a1
.schirm:
	bsr.b	St_zaehler
	bsr.b	St_zeile
	move.w	d0,d3			; Strahl danach
	move.l	ST_VOR(a0),d0
	bsr.b	St_zeile
	move.w	d0,d2			; Strahl davor
	moveq	#0,d6			; getroffen?
	move.w	Anzeige_zeilen,d1
	subq.w	#1,d1			; letzte Zeile
	tst.w	d3
	bmi.b	.danach_aus
	addq.l	#1,ST_IMBILD(a0)
	tst.w	d2
	bpl.b	.beide
	moveq	#0,d2			; Bild begann waehrend des Schreibens
	bra.b	.pruefen
.beide:	cmp.w	d2,d3
	bge.b	.pruefen
	move.w	d3,-(sp)		; ueber das Bildende: [d2, Ende], [0, d3]
	move.w	d1,d3
	bsr.b	.test
	move.w	(sp)+,d3
	moveq	#0,d2
.pruefen:
	bsr.b	.test
	bra.b	.zaehlen
.danach_aus:
	tst.w	d2
	bmi.b	.zaehlen
	move.w	d1,d3			; Bild endete waehrend des Schreibens
	bsr.b	.test
.zaehlen:
	tst.w	d6
	beq.b	.aus
	addq.l	#1,ST_TREFFER(a0)
.aus:	movem.l	(sp)+,d0-d6/a1
	rts
; .test -- schneidet [d2, d3] den Bereich [d4, d5)?  Dann d6 = 1.
.test:	cmp.w	d5,d2
	bge.b	.t
	cmp.w	d4,d3
	blt.b	.t
	moveq	#1,d6
.t:	rts

; St_text -- je Satz aus St_liste eine Zeile nach a1, a1 dahinter.
;   Veraendert d0-d2/a0.
St_text:
	move.l	a2,-(sp)
	lea	Text_st_kopf,a0
	bsr	Mess_anhaengen
	lea	St_liste,a2
.satz:	tst.l	(a2)
	beq.b	.aus
	move.b	#13,(a1)+
	move.b	#10,(a1)+
	move.b	#' ',(a1)+
	move.b	#' ',(a1)+
	move.l	4(a2),a0		; Name
	bsr	Mess_anhaengen
	lea	Text_st_aufrufe,a0
	bsr	Mess_anhaengen
	move.l	(a2),a0
	move.l	ST_AUFRUFE(a0),d0
	bsr	Mess_zahl
	lea	Text_st_treffer,a0
	bsr	Mess_anhaengen
	move.l	(a2),a0
	move.l	ST_TREFFER(a0),d0
	bsr	Mess_zahl
	lea	Text_st_imbild,a0
	bsr	Mess_anhaengen
	move.l	(a2),a0
	move.l	ST_IMBILD(a0),d0
	bsr	Mess_zahl
	addq.l	#8,a2
	bra.b	.satz
.aus:	move.l	(sp)+,a2
	IFD	STRAHL_TAKT
	bra	Tk_text			; AMIGA_RAHMEN.S
	ELSE
	rts
	ENDC
	ENDC
	ENDC

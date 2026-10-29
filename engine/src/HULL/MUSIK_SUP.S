; ***************************************************************************
; MUSIK_SUP.S -- die Hardwareschicht unter Thalions Musikspieler.
; Einheit "bibliothek" (engine.s), hinter am2cpu_code.i.  docs/13.
;
; **Der Spieler ist Thalions Code aus AM2_CPU** (Sa_spieler, Thalions Music_routine, 0:$2AA0E,
; am2cpu_code.py), ein Sonic-Arranger-Abspieler mit Sprungtabelle:
;
;   +0   Stueck vorbereiten, a0 = Stueck (Versaetze -> Zeiger)
;   +12  starten, d0 = Teilstueck
;   +16  anhalten (setzt nur Stumm-Merker; DMACON schreibt Set_music)
;   +24  einmal je Bild: der Takt
;   +4, +8, +20   CIA-Interrupt an/ab, Klangeffekt -- vom Spiel nicht gerufen
;
; Er schreibt die Amiga-Hardware direkt.  Der Bau biegt diese Operanden
; hierher um (UMBIEGEN in am2cpu_code.py, wie K1 bei FAIRY.S):
;
;   $DFFxxx   -> Paula_schatten+xxx    Paula (AUDx, DMACON ...), VHPOSR
;   $BFDxxx   -> Cia_b_attrappe+xxx    CIA-B Timer A (Tempo)
;   $BFE001   -> Cia_a_filter          CIA-A PRA, Bit 1 = Tiefpassfilter
;   $4        -> Musik_exec_zeiger     ExecBase (nur in +4, +8, +20)
;
; Der Mischer liest Paula_schatten nach jedem Takt (docs/13 Abschnitt 4).
; Stand 2026-10-04: Set_music laedt Stuecke und ruft +0/+12/+16 (Schritt 2a).
; Bibliothek_vbl ruft in jedem Bild Musik_vbl; das ruft Thalions Takt +24
; einmal je 1/50 s Ton.  Gemischt wird auf dem DSP (Schritt 4c, md_*,
; MUSIK_DSP.A56); ist er belegt, oder mit dem Schalter MUSIK_CPU, auf dem
; Prozessor mit DMA-Ton (Schritt 4b, mk_*).  Musik_install/Musik_remove
; (MAIN.S) schalten die Tonausgabe des Falcon ein und aus.
; Since 2026-10-23 the mixer, or none, is chosen at run time by MUSIC= in
; AMBER.INF beside the game files (OFF, DSP, CPU, YM; E17, Musik_inf_lesen).
; Stand 2026-10-10: Im ST-Bau (ZIEL_ST) faellt der Mischer weg, siehe unten.
; Big Alecs YM-Fassung steht in MUSIK_YM.S, samt der Weiche Music_routine
; vor Thalions Spieler (der heisst darum Sa_spieler).
; Since 2026-10-12 the mixer itself is the module musik/MISCHER.S, shared
; with intro and extro (E14); the names md_* and mk_* live there.
; ***************************************************************************

; ---------------------------------------------------------------------------
; Musik_exec_zeiger -- zeigt auf eine Exec-Attrappe.  Jeder Einsprung
; (-6 ... -498, je 6 Byte) liefert d0 = 0 und kehrt zurueck: OpenResource
; findet also keine ciab.resource, und +4 meldet "kein Interrupt".
; Disable/Enable/Cause tun nichts.  Auf dem Weg des Spiels wird davon nichts
; gerufen.
	SECTION	Fast_DATA,data
	even
Musik_exec_zeiger:
	dc.l	Musik_exec_basis

	SECTION	Program,code
	even
	REPT	83			; -498 = 83 Einsprunge zu 6 Byte
	moveq	#0,d0
	rts
	nop
	ENDR
Musik_exec_basis:
	rts

; ---------------------------------------------------------------------------
; Die Schattenbloecke.  Paula_schatten hat die Lage der Custom-Register
; ($000-$1FF), damit Thalions Versaetze (lea $DFF0A0,a3 / move.w d0,8(a3))
; unveraendert gelten.  Cia_b_attrappe reicht bis $E00 (CRA), weil der
; Spieler ueber lea $BFD000,a0 mit Versatz $600/$700/$D00/$E00 zugreift.
; Custom: Thalions Name fuer die Custom-Chips, benutzt in HULL/VARIOUS.S
; (move.w #$000F,Custom+dmacon in Set_music und Relocate_music).
Custom		equ	Paula_schatten

	SECTION	Fast_BSS,bss
	even
Paula_schatten:
	ds.b	$200
Cia_b_attrappe:
	ds.b	$F00
Cia_a_filter:
	ds.b	2
	even

	SECTION	Program,code

; ---------------------------------------------------------------------------
; Musik_inf_lesen -- the choice of the mixer at run time, from MUSIC= in
; AMBER.INF (E17; MAIN.S reads it in Einstellungen_lesen through
; shared/SETTINGS.S, before Musik_install): OFF, DSP, CPU, YM (MUSIK_YM.S).
; Without the file, or without MUSIC=, DSP applies (in the build with
; MUSIK_CPU: CPU, in the ST build: YM; there only OFF counts).  Result in
; mi_wahl.  The build leaves *.INF in ATARI/AMBFILES, so the choice stays.
; All registers stay.
MI_AUS		equ	SET_OFF
MI_DSP		equ	SET_DSP
MI_CPU		equ	SET_CPU
MI_YM		equ	SET_YM
Musik_inf_lesen:
	movem.l	d0-d1/a0,-(sp)
	IFD	ZIEL_ST
	move.b	#MI_YM,mi_wahl
	ELSE
	IFD	MUSIK_CPU
	move.b	#MI_CPU,mi_wahl
	ELSE
	move.b	#MI_DSP,mi_wahl
	ENDC
	ENDC
	IFD	MUSIKMESS
	bra.s	.raus			; Messfassungen: der Mischer steht im Namen
	ENDC
	move.b	Settings_music,d0
	bmi.s	.raus			; SET_NONE: the default
	move.b	d0,mi_wahl
.raus:	movem.l	(sp)+,d0-d1/a0
	rts

	SECTION	Fast_DATA,data
mi_snd:	dc.b	0			; Cookie _SND, unterstes Byte
mi_wahl:
	dc.b	MI_DSP
	even

	SECTION	Program,code

; ---------------------------------------------------------------------------
; **ST/STE (ZIEL_ST, tools/baue_st.sh):** Beide Mischer brauchen den Ton
; des Falcon und fallen im ST-Bau ganz weg (ueber 40 KB: Lautstaerketabelle,
; Ring, DSP-Code).  Die drei Einsprunge fuer MAIN.S und Bibliothek_vbl
; fuehren zum YM-Spieler (MUSIK_YM.S, seit 2026-10-10); ohne MUSIK_YM.BIN
; oder mit MUSIC=OFF in AMBER.INF bleibt es still.
	IFD	ZIEL_ST
	IFD	MUSIKMESS
	fail	"MUSIKMESS misst den Falcon-Ton, im ST-Bau gibt es ihn nicht"
	ENDC
Musik_install:
	bsr	Musik_inf_lesen
	tst.b	mi_wahl
	beq.s	.aus
	bra	ym_install
.aus:	rts
Musik_remove:
	bra	ym_remove
Musik_vbl:
	bra	ym_vbl
	ELSE

; ***************************************************************************
; The mixer is the module musik/MISCHER.S since 2026-10-12, shared with
; intro and extro (E14, docs/13 4f).  Here only what binds it to the game:
; the parameter block with Thalion's player from AM2_CPU, AMBER.INF, the YM
; switch and the measuring version.
; ***************************************************************************

	INCLUDE	"../musik/MISCHER.S"

; ---------------------------------------------------------------------------
; Musik_install -- from start (MAIN.S), supervisor, after Ordner_suchen.
; MUSIC= in AMBER.INF chooses: OFF silent (and no tick), YM Big Alec's version
; (MUSIK_YM.S), DSP or CPU the mixer.  All registers stay.
Musik_install:
	IFD	MUSIK_AUS
	rts				; measuring version without music (musik_messbau.sh)
	ENDC
	movem.l	d0/a0,-(sp)
	bsr	Musik_inf_lesen
	tst.b	mi_wahl
	beq.s	.raus
	bsr	Mischer_snd
	move.b	d0,mi_snd
	cmp.b	#MI_YM,mi_wahl
	bne.s	.mischer
	bsr	ym_install		; Big Alec's YM version (MUSIK_YM.S)
	bra.s	.raus
.mischer:
	lea	mu_satz,a0
	moveq	#0,d0
	move.b	mi_wahl,d0		; MI_DSP, MI_CPU = MISCHER_DSP, MISCHER_CPU
	move.w	d0,MS_WAHL(a0)
	bsr	Mischer_install
.raus:	movem.l	(sp)+,d0/a0
	rts

; mu_takt -- the tick for the mixer: Thalion's +24 (AM2_CPU 0:$21270), past
; the switch Music_routine.  It saves d0-a6 itself (0:$2ADD6).  The mixer
; calls it only while Music_flag is set, as AM2_CPU does.
mu_takt:
	IFD	MUSIKMESS
	bsr	mm_takt_vor
	jsr	Sa_spieler+24
	bra	mm_takt_nach
	ELSE
	jmp	Sa_spieler+24
	ENDC

; ---------------------------------------------------------------------------
; Musik_remove -- from Exit_program, Speicher_voll and the emergency exit
; (MAIN.S); harmless without Musik_install.  All registers stay.
Musik_remove:
	IFD	MUSIKMESS
	tst.b	Im_notausgang		; from etv_term (MAIN.S): no GEMDOS
	bne.s	.ohne_mess
	bsr	Musik_mess_schreiben	; before switching off: which mixer ran
.ohne_mess:
	ENDC
	bsr	ym_remove		; YM version (MUSIK_YM.S)
	bra	Mischer_remove

; ---------------------------------------------------------------------------
; Musik_vbl -- every frame from Bibliothek_vbl (LIBRARY.S).  All registers
; stay.
Musik_vbl:
	IFD	MUSIKMESS
	bsr	mm_vor			; count, note the clock
	bsr.s	mu_vbl
	bra	mm_nach			; add the time of the music
	ENDC
mu_vbl:
	tst.b	ym_bereit		; YM version instead of the mixer
	bne	ym_vbl
	bra	Mischer_vbl

	SECTION	Fast_DATA,data
	even
mu_satz:				; parameter block (MISCHER.S, MS_*)
	dc.l	Paula_schatten		; shadow
	dc.l	mu_takt			; tick
	dc.l	Music_flag		; music on (Thalion's MAIN.S)
	dc.l	Playing_music		; 4e: song number (Thalion's VARIOUS.S)
	dc.l	Am2cpu_3_03AFE		; 4e: pointer to its first area
	dc.l	Am2cpu_3_037BE		; 4e: the four channel records
	dc.l	Am2cpu_3_03AF6		; 4e: the player's silence
	dc.w	0			; wahl, from AMBER.INF
	even

	SECTION	Program,code

	IFD	MUSIKMESS
; ***************************************************************************
; Die Messfassung (Schalter MUSIKMESS, tools/musik_messbau.sh, docs/13 4c):
; Bilder und Zeit der Musik je 10 s, beim Beenden als Text in eine Datei.
;
; Je VBL zaehlt mm_vor das VBL und, wenn Schirm_vorn gewechselt hat, ein
; Bild.  Die Zeit der Musik ist, was die Uhr zwischen mm_vor und mm_nach
; weiterlaeuft: alles, was Musik_vbl tut, also Thalions Takt und das Mischen
; oder das Fuettern des DSP.  Die Uhr (mm_uhr) ist der 200-Hz-Zaehler von
; TOS samt dem Zaehler von MFP-Timer C, der ihn treibt: 192 Schritte zu
; 26 us je 1/200 s.  (Der Zeilenzaehler des Videl zeigte in Hatari nur ein
; Viertel der Zeit, die der Profiler mass; 2026-10-04.)
; ***************************************************************************

MM_FENSTER	equ	2000		; 10 s in 200-Hz-Schritten
MM_HOECHSTENS	equ	360		; eine Stunde
; HZ_200 ($4BA, the 200 Hz counter) is defined in MUSIK_YM.S.
MFP_TCDR	equ	$FFFFFA23	; Timer C, zaehlt 192 .. 1
MM_SCHRITTE	equ	192		; Timer-C-Schritte je 1/200 s

; Satz je Fenster
mms_bilder	equ	0		; Wort
mms_vbls	equ	2		; Wort
mms_zeit	equ	4		; Langwort, Timer-C-Schritte in Musik_vbl
mms_takte	equ	8		; Wort, 200-Hz-Schritte
mms_takt	equ	10		; Langwort, Timer-C-Schritte in Thalions +24
mms_groesse	equ	14

; Musik_mess_schreiben -- the records as text to MESS_xxx.TXT.  From
; Musik_remove, before switching off.  All registers stay.  It comes first
; and has a capital name because register_pruefen.py counts everything up
; to the next capital label as one routine: its movem covers all mm_*.
Musik_mess_schreiben:
	tst.b	mm_halt
	bne	.raus
	st	mm_halt
	movem.l	d0-d7/a0-a2,-(sp)
	lea	mm_text,a1
	lea	mm_t_kopf,a0
	bsr	mm_kopie
	bsr	Mischer_stand		; which mixer ran?
	lea	mm_t_keiner,a0
	subq.w	#1,d0
	bmi.s	.mischer
	lea	mm_t_cpu,a0
	beq.s	.mischer
	lea	mm_t_dsp,a0
	subq.w	#1,d0
	beq.s	.mischer
	lea	mm_t_tot,a0
.mischer:
	bsr	mm_kopie
	lea	mm_t_spalten,a0
	bsr	mm_kopie
	lea	mm_saetze,a2
	moveq	#0,d7			; Nummer
.satz:	cmp.w	mm_anzahl,d7
	bhs	.datei
	tst.w	mms_vbls(a2)
	beq	.weiter
	moveq	#0,d0			; Nr
	move.w	d7,d0
	addq.w	#1,d0
	moveq	#3,d1
	moveq	#0,d2
	bsr	mm_zahl
	moveq	#0,d0			; ab Sekunde
	move.w	d7,d0
	mulu	#MM_FENSTER/200,d0
	moveq	#6,d1
	bsr	mm_zahl
	moveq	#0,d0			; Bilder
	move.w	mms_bilder(a2),d0
	moveq	#8,d1
	bsr	mm_zahl
	moveq	#0,d0			; VBL
	move.w	mms_vbls(a2),d0
	moveq	#6,d1
	bsr	mm_zahl
	moveq	#0,d0			; Bilder je s, eine Stelle:
	move.w	mms_bilder(a2),d0	; Bilder * 2000 / Takte
	mulu	#2000,d0
	move.w	mms_takte(a2),d3
	bne.s	.b1
	moveq	#0,d0
	bra.s	.b0
.b1:	divu	d3,d0
	and.l	#$FFFF,d0
.b0:	moveq	#10,d1
	moveq	#1,d2
	bsr	mm_zahl
	move.w	mms_bilder(a2),d3	; VBL je Bild, eine Stelle
	bne.s	.vb
	lea	mm_t_strich,a0
	bsr	mm_kopie
	bra.s	.musik
.vb:	moveq	#0,d0
	move.w	mms_vbls(a2),d0
	mulu	#10,d0
	divu	d3,d0
	and.l	#$FFFF,d0
	moveq	#10,d1
	bsr	mm_zahl
.musik:	move.w	mms_takte(a2),d3	; Musik in %, eine Stelle:
	bne.s	.mzeit			; zeit * 10 / Takte * 100 / 192
	lea	mm_t_strich,a0
	bsr	mm_kopie
	bra.s	.zeile
.mzeit:	move.l	mms_zeit(a2),d0
	bsr	mm_prozent
	move.w	mms_takte(a2),d3	; mm_zahl nahm d3
	move.l	mms_takt(a2),d0		; davon Thalions Takt
	bsr	mm_prozent
.zeile:	move.b	#13,(a1)+
	move.b	#10,(a1)+
.weiter:
	lea	mms_groesse(a2),a2
	addq.w	#1,d7
	bra	.satz
.datei:	move.l	a1,d6
	sub.l	#mm_text,d6		; Laenge
	clr.w	-(sp)			; Fcreate(Name, 0)
	pea	mm_name
	move.w	#60,-(sp)
	Gemdos
	addq.l	#8,sp
	tst.w	d0
	bmi.s	.fertig
	move.w	d0,d5
	pea	mm_text			; Fwrite(Handle, Laenge, Text)
	move.l	d6,-(sp)
	move.w	d5,-(sp)
	move.w	#64,-(sp)
	Gemdos
	lea	12(sp),sp
	move.w	d5,-(sp)		; Fclose(Handle)
	move.w	#62,-(sp)
	Gemdos
	addq.l	#4,sp
.fertig:
	movem.l	(sp)+,d0-d7/a0-a2
.raus:	rts

; mm_vor -- am Anfang von Musik_vbl.  Alle Register bleiben.
mm_vor:
	movem.l	d0-d1/a0,-(sp)
	tst.b	mm_halt
	bne	.raus
	move.l	HZ_200.w,d0
	tst.b	mm_laeuft
	bne.s	.laeuft
	st	mm_laeuft
	move.l	d0,mm_start
	move.l	Schirm_vorn,mm_schirm
.laeuft:
	move.l	d0,d1
	sub.l	mm_start,d1
	cmp.l	#MM_FENSTER,d1
	blo.s	.zaehlen
	move.l	d0,mm_start		; Fenster voll: ablegen
	move.w	mm_anzahl,d0
	cmp.w	#MM_HOECHSTENS,d0
	bhs.s	.neu
	mulu	#mms_groesse,d0
	lea	mm_saetze,a0
	add.l	d0,a0
	move.w	mm_bilder,mms_bilder(a0)
	move.w	mm_vbls,mms_vbls(a0)
	move.l	mm_zeit,mms_zeit(a0)
	move.w	d1,mms_takte(a0)
	move.l	mm_takt,mms_takt(a0)
	addq.w	#1,mm_anzahl
.neu:	clr.w	mm_bilder
	clr.w	mm_vbls
	clr.l	mm_zeit
	clr.l	mm_takt
.zaehlen:
	addq.w	#1,mm_vbls
	move.l	Schirm_vorn,d0
	cmp.l	mm_schirm,d0
	beq.s	.gleich
	move.l	d0,mm_schirm
	addq.w	#1,mm_bilder
.gleich:
	bsr.s	mm_uhr
	move.l	d0,mm_t0
.raus:	movem.l	(sp)+,d0-d1/a0
	rts

; mm_uhr -- d0 = Zeit in Timer-C-Schritten (26 us).  Liest _hz_200 vor und
; nach dem Zaehler, bis beide gleich sind.  Aendert d0, d1.
mm_uhr:
	move.l	HZ_200.w,d1
	moveq	#0,d0
	move.b	MFP_TCDR.w,d0
	cmp.l	HZ_200.w,d1
	bne.s	mm_uhr
	neg.w	d0
	add.w	#MM_SCHRITTE,d0		; 0 .. 191 seit dem letzten Schritt
	lsl.l	#6,d1			; * 192 = * 64 + * 128
	add.l	d1,d0
	add.l	d1,d1
	add.l	d1,d0
	rts

; mm_nach -- am Ende von Musik_vbl.  Alle Register bleiben.
mm_nach:
	movem.l	d0-d1,-(sp)
	tst.b	mm_halt
	bne.s	.raus
	bsr.s	mm_uhr
	sub.l	mm_t0,d0
	bmi.s	.raus			; Uhr gesprungen: nicht zaehlen
	add.l	d0,mm_zeit
.raus:	movem.l	(sp)+,d0-d1
	rts

; mm_takt_vor, mm_takt_nach -- around Thalion's tick +24 (mu_takt): its
; time goes to mm_takt.  It is part of the time of Musik_vbl as well.  All
; registers stay.
mm_takt_vor:
	movem.l	d0-d1,-(sp)
	bsr	mm_uhr
	move.l	d0,mm_t1
	movem.l	(sp)+,d0-d1
	rts

mm_takt_nach:
	movem.l	d0-d1,-(sp)
	tst.b	mm_halt
	bne.s	.raus
	bsr	mm_uhr
	sub.l	mm_t1,d0
	bmi.s	.raus			; Uhr gesprungen: nicht zaehlen
	add.l	d0,mm_takt
.raus:	movem.l	(sp)+,d0-d1
	rts

; mm_prozent -- d0 Timer-C-Schritte als Anteil an d3 200-Hz-Schritten, in
; Prozent mit einer Stelle, 10 Zeichen breit: d0 * 10 / d3 * 100 / 192.
; Aendert d0-d4 (d3 ueber mm_zahl).
mm_prozent:
	move.l	d0,d4
	lsl.l	#3,d0
	add.l	d4,d0
	add.l	d4,d0
	divu	d3,d0
	and.l	#$FFFF,d0
	mulu	#100,d0
	divu	#MM_SCHRITTE,d0
	and.l	#$FFFF,d0
	moveq	#10,d1
	moveq	#1,d2
	bra	mm_zahl

; mm_kopie -- Text a0 (Endnull) nach (a1)+.
mm_kopie:
	move.b	(a0)+,(a1)+
	bne.s	mm_kopie
	subq.l	#1,a1
	rts

; mm_zahl -- d0.l (unter 655 360) dezimal nach (a1)+, rechtsbuendig in d1
; Zeichen.  d2 = 1: die letzte Ziffer hinter einen Punkt.  Aendert d0, d3,
; d4.
mm_zahl:
	move.l	a2,-(sp)
	lea	mm_ziffern+16,a2
	moveq	#0,d3			; Zeichen
.ziffer:
	divu	#10,d0
	move.l	d0,d4
	swap	d4			; Rest
	add.b	#'0',d4
	move.b	d4,-(a2)
	addq.w	#1,d3
	and.l	#$FFFF,d0		; Quotient
	tst.w	d2
	beq.s	.ganz
	cmp.w	#1,d3
	bne.s	.ganz
	move.b	#'.',-(a2)
	addq.w	#1,d3
	bra.s	.ziffer			; eine Ziffer vor dem Punkt
.ganz:	tst.l	d0
	bne.s	.ziffer
	move.w	d1,d4
	sub.w	d3,d4
	ble.s	.kopie
	subq.w	#1,d4
.raum:	move.b	#' ',(a1)+
	dbf	d4,.raum
.kopie:	subq.w	#1,d3
.zeichen:
	move.b	(a2)+,(a1)+
	dbf	d3,.zeichen
	move.l	(sp)+,a2
	rts

	SECTION	Fast_DATA,data
mm_name:
	IFD	MUSIK_AUS
	dc.b	'MESS_OHN.TXT',0
	ELSE
	IFD	MUSIK_CPU
	dc.b	'MESS_CPU.TXT',0
	ELSE
	dc.b	'MESS_DSP.TXT',0
	ENDC
	ENDC
mm_t_kopf:
	dc.b	'Ambermoon Musikmessung, je 10 s.  Mischer: ',0
mm_t_keiner:
	dc.b	'keiner (ohne Musik oder Ton belegt)',13,10,0
mm_t_cpu:
	dc.b	'Prozessor',13,10,0
mm_t_dsp:
	dc.b	'DSP',13,10,0
mm_t_tot:
	dc.b	'DSP, ausgefallen (md_tot)',13,10,0
mm_t_spalten:
	dc.b	'Musik = Anteil der Zeit in Musik_vbl (Takt und Mischen),',13,10
	dc.b	'Takt = davon in Thalions Spieler (+24)',13,10
	dc.b	13,10
	dc.b	' Nr  ab s  Bilder   VBL  Bilder/s  VBL/Bild   Musik %    Takt %'
	dc.b	13,10,0
mm_t_strich:
	dc.b	'         -',0
mm_halt:
	dc.b	0			; Messung beendet (Datei geschrieben)
mm_laeuft:
	dc.b	0
	even

	SECTION	Fast_BSS,bss
	even
mm_start:	ds.l	1		; _hz_200 am Anfang des Fensters
mm_schirm:	ds.l	1		; Schirm_vorn beim letzten VBL
mm_zeit:	ds.l	1
mm_bilder:	ds.w	1
mm_vbls:	ds.w	1
mm_t0:		ds.l	1		; mm_uhr am Anfang von Musik_vbl
mm_t1:		ds.l	1		; mm_uhr vor Thalions Takt
mm_takt:	ds.l	1		; Zeit in Thalions Takt, dieses Fenster
mm_anzahl:	ds.w	1
mm_saetze:	ds.b	MM_HOECHSTENS*mms_groesse
mm_ziffern:	ds.b	16
mm_text:	ds.b	300+MM_HOECHSTENS*80
	even

	SECTION	Program,code
	ENDC

	SECTION	Fast_DATA,data
	INCLUDE	"../musik/mischer_daten.i"
	SECTION	Fast_BSS,bss
	INCLUDE	"../musik/mischer_bss.i"
	SECTION	Chip_BSS,bss		; DMA reads only ST-RAM
	INCLUDE	"../musik/mischer_chip.i"

	SECTION	Program,code
	ENDC				; ZIEL_ST

; Die YM-Fassung und die Weiche Music_routine, in beiden Bauten.
	INCLUDE	"src/HULL/MUSIK_YM.S"

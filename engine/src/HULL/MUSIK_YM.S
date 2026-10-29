; ***************************************************************************
; MUSIK_YM.S -- Big Alecs YM-Fassung der Musik und die Weiche davor.
; Eingebunden am Ende von MUSIK_SUP.S, im Falcon- und im ST-Bau.  docs/13 6.
;
; **Die Weiche.**  Thalions Set_music und Remove_music rufen ueber das Makro
; music (vorspann.i) Music_routine+0/+12/+16.  Seit 2026-10-10 ist
; Music_routine diese Sprungtabelle; Thalions Spieler aus AM2_CPU heisst
; Sa_spieler (am2cpu_code.py).  Ohne YM geht jeder Einsprung unveraendert
; dorthin, mit YM nehmen ym_* die Aufrufe an.
;
; **The YM block** (MUSIK_YM.BIN, written at build by ym_auszug.py from
; Big Alec's SNDH file big_alec/ambermon.snd, AMBER_YMSNDH, since
; 2026-10-27; before, from the disk of the "Ambermoon Music Demo"; never in
; the repository): Big Alec's player and 18 pieces, PC-relative only, runs
; at any address.  ym_auszug.py binds the SNDH's Timer B back to Timer D
; and checks the result: the first 241 630 bytes of the demo's block,
; pieces 1-17 the same, piece 18 (untitled, not in musik_ym.inf) shorter.
;   +0  start, d0 = piece 1-18.  Saves the vectors of Timer A ($134) and
;       D ($110) and nine MFP registers inside itself, hooks in its own
;       interrupt routines, sets VR to software end of interrupt.
;   +4  once every 1/50 s.  Does nothing while no piece plays.
;   +8  stop: writes the saved vectors and MFP registers back (without
;       checking that it was started) and silences the YM.
;   Every entry destroys registers; supervisor (MFP, vectors, YM).
; Hence two rules that hold only here (read in the block, 2026-10-10):
; never +8 without a +0 before -- the saved values are still zero then,
; and +8 switched off the keyboard and Timer C --, and never +0 twice
; without +8 between -- +0 would then save its own vectors as the "old"
; ones.  ym_laeuft keeps track of both.
;
; **Timer B bleibt unser** (Raster auf dem ST): +8 schreibt IERA/IMRA und
; IERB/IMRB als Ganzes zurueck.  ym_stop uebernimmt davon nur die Bits von
; Timer A und D, alle anderen bleiben, wie sie vor dem Stop waren.
;
; **Takt:** _hz_200 (Timer C, 200 Hz), je 4 Schritte einmal +4.  So bleibt
; es bei 50 Hz, ob der Schirm mit 50, 60 oder 71 Hz laeuft.
;
; **+4 haelt Timer C an:** Es stellt Timer D, indem es TCDCR ganz
; ueberschreibt (move.b d1,$FFFFFA1D mit d1 = 0-6, im Block bei $67A und
; $7B8), und loescht damit die Bits 4-6, Timer C.  Die Demo merkt das nicht,
; sie ruft +4 aus ihrem VBL.  Bei uns bliebe _hz_200 stehen, der Takt mit
; ihm, und Timer A/D hielten die letzte Note: ein Pfeifton (Hatari STE,
; Nutzer 2026-10-10).  ym_takt setzt Timer C nach jedem +4 zurueck.
;
; **Which piece:** MUSIK_YM.INF next to the game files, plain text, one
; line "Thalion's number  YM piece" each, ";" starts a comment.  Numbers
; not in it stay silent.  Template in the repository: tools/musik_ym.inf.
; The build assembles the template in (ym_inf_vorgabe); without the file
; that applies, so a freshly copied folder plays music too.  A file next to
; the game files wins.
;
; **Tastenklick und Glocke** schreiben den YM aus TOS heraus, waehrend die
; Interrupts des Spielers ihn auch beschreiben; solange der YM-Spieler
; geladen ist, sind beide in conterm ($484) aus.
;
; Alles 68000-Code.
; ***************************************************************************

YM_START	equ	0
YM_TAKT		equ	4
YM_STOP		equ	8
YM_HOECHSTENS	equ	$100000		; it is not larger (241 630 bytes)
YM_INF_GROESSE	equ	2048
YM_STUECKE	equ	18
YM_NUMMERN	equ	32		; Thalions Stuecke 1-32
CONTERM		equ	$484		; Bit 0 Tastenklick, Bit 2 Glocke
HZ_200		equ	$4BA

; ---------------------------------------------------------------------------
; Music_routine -- the switch: Thalion's jump table into the music player
; (4 bytes per entry).  In the code section: Thalion jumps into it.
;   IN : +0 a0 = song (Sonic Arranger), +12 d0 = part, +16 stop, +24 the
;        beat; +4, +8, +20 are not called by the game
	SECTION	Program,code
	even
Music_routine:
	bra.w	mw_init			; +0   a0 = Stueck (Sonic Arranger)
	bra.w	mw_4			; +4   vom Spiel nicht gerufen
	bra.w	mw_8			; +8   vom Spiel nicht gerufen
	bra.w	mw_start		; +12  d0 = Teilstueck
	bra.w	mw_stop			; +16
	bra.w	mw_20			; +20  vom Spiel nicht gerufen
	bra.w	mw_24			; +24  Takt; ruft nur mk_takt, direkt

mw_init:
	tst.b	ym_bereit
	bne.s	.ym
	jmp	Sa_spieler
.ym:	rts				; Thalions Stueckdaten braucht der YM nicht
mw_4:	jmp	Sa_spieler+4
mw_8:	jmp	Sa_spieler+8
mw_20:	jmp	Sa_spieler+20
mw_24:	jmp	Sa_spieler+24

; mw_start -- Playing_music hat Set_music eben gesetzt (Thalions
; VARIOUS.S, vor Music_start).  Das Teilstueck in d0 zaehlt fuer den YM
; nicht.  Alle Register bleiben.
mw_start:
	tst.b	ym_bereit
	bne.s	.ym
	jmp	Sa_spieler+12
.ym:	movem.l	d0-d7/a0-a6,-(sp)
	bsr	ym_stop			; laeuft noch eines: erst anhalten
	moveq	#0,d0
	move.w	Playing_music,d0
	beq.s	.raus
	cmp.w	#YM_NUMMERN,d0
	bhi.s	.raus
	lea	ym_tabelle,a0
	move.b	(a0,d0.w),d0
	beq.s	.raus			; keine YM-Fassung: still
	bsr	ym_start
.raus:	movem.l	(sp)+,d0-d7/a0-a6
	rts

; mw_stop -- Alle Register bleiben (Remove_music: nur d0).
mw_stop:
	tst.b	ym_bereit
	bne.s	.ym
	jmp	Sa_spieler+16
.ym:	movem.l	d0-d7/a0-a6,-(sp)
	bsr	ym_stop
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ---------------------------------------------------------------------------
; ym_start -- d0.b = YM-Stueck 1-18.  Nur, wenn keines laeuft (mw_start
; haelt vorher an).  Register: d0-d7/a0-a6 frei (vom Aufrufer gerettet).
ym_start:
	tst.b	ym_laeuft
	bne.s	.raus
	and.l	#$FF,d0
	cmp.w	#YM_STUECKE,d0
	bhi.s	.raus
	move.l	ym_block,a0
	jsr	YM_START(a0)
	move.b	$FFFFFA1D.w,d0		; Timer C, wie er vor dem ersten +4 laeuft
	and.b	#$70,d0
	move.b	d0,ym_timer_c
	st	ym_laeuft
	move.l	HZ_200.w,ym_hz		; ab jetzt zaehlt der Takt
.raus:	rts

; ym_stop -- haelt an, wenn ein Stueck laeuft.  Alle Register bleiben.
ym_stop:
	tst.b	ym_laeuft
	beq	.raus
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0700,sr		; MFP nicht dazwischen
	lea	$FFFFFA00.w,a1
	move.b	$07(a1),d4		; IERA
	move.b	$09(a1),d5		; IERB
	move.b	$13(a1),d6		; IMRA
	move.b	$15(a1),d7		; IMRB
	move.l	ym_block,a0
	jsr	YM_STOP(a0)
	lea	$FFFFFA00.w,a1		; je Register: Timer A/D von +8, Rest von vorher
	move.b	$07(a1),d2		; IERA, Bit 5 Timer A
	and.b	#$20,d2
	and.b	#$DF,d4
	or.b	d2,d4
	move.b	d4,$07(a1)
	move.b	$13(a1),d2		; IMRA, Bit 5 Timer A
	and.b	#$20,d2
	and.b	#$DF,d6
	or.b	d2,d6
	move.b	d6,$13(a1)
	move.b	$09(a1),d2		; IERB, Bit 4 Timer D
	and.b	#$10,d2
	and.b	#$EF,d5
	or.b	d2,d5
	move.b	d5,$09(a1)
	move.b	$15(a1),d2		; IMRB, Bit 4 Timer D
	and.b	#$10,d2
	and.b	#$EF,d7
	or.b	d2,d7
	move.b	d7,$15(a1)
	move.w	(sp)+,sr
	sf	ym_laeuft
	movem.l	(sp)+,d0-d7/a0-a6
.raus:	rts

; ---------------------------------------------------------------------------
; ym_vbl -- aus Musik_vbl, in jedem Bild.  Je 4 Schritte von _hz_200
; einmal +4, hoechstens zwei je Bild; lag das Spiel laenger fest (Laden),
; geht es ohne Nachholen weiter.  Ist Music_flag aus (Thalion schaltet die
; Musik ab), haelt es an.  Alle Register bleiben.
ym_vbl:
	tst.b	ym_laeuft
	beq.s	.raus
	movem.l	d0-d7/a0-a6,-(sp)
	tst.b	Music_flag		; Thalions MAIN.S
	bne.s	.an
	bsr	ym_stop
	bra.s	.fertig
.an:	move.l	HZ_200.w,d0
	sub.l	ym_hz,d0
	lsr.l	#2,d0			; faellige Takte
	beq.s	.fertig
	cmp.l	#2,d0
	bls.s	.nach
	move.l	HZ_200.w,ym_hz		; zu weit zurueck: neu ansetzen
	moveq	#1,d0
	bra.s	.takt
.nach:	move.l	d0,d1
	lsl.l	#2,d1
	add.l	d1,ym_hz
.takt:	move.w	d0,-(sp)
	bsr.s	ym_takt
	move.w	(sp)+,d0
	subq.w	#1,d0
	bne.s	.takt
.fertig:
	movem.l	(sp)+,d0-d7/a0-a6
.raus:	rts

; ym_takt -- einmal +4, dann Timer C zurueck (siehe oben).  Zwischen dem
; Schreiben im Block und hier steht Timer C kurz; _hz_200 geht dadurch
; etwas nach, der Takt mit ihm (angenommen: unhoerbar).  Timer D behaelt
; seinen Teiler.  Register: d0-d7/a0-a6 frei (ym_vbl rettet sie).
ym_takt:
	move.l	ym_block,a0
	jsr	YM_TAKT(a0)
	move.b	$FFFFFA1D.w,d0
	move.b	d0,d1
	and.b	#$70,d1
	cmp.b	ym_timer_c,d1
	beq.s	.gut
	and.b	#$0F,d0			; Timer D, wie +4 ihn stellte
	or.b	ym_timer_c,d0
	move.b	d0,$FFFFFA1D.w
.gut:	rts

; ---------------------------------------------------------------------------
; ym_install -- MUSIK_YM.BIN laden, MUSIK_YM.INF lesen.  Aus Musik_install,
; Supervisor.  Fehlt der Block oder passt er nicht, bleibt alles still
; (ym_bereit aus), und die Weiche fuehrt zu Thalions Spieler wie bisher.
; Alle Register bleiben.
ym_install:
	movem.l	d0-d3/a0-a2,-(sp)
	lea	ym_name_bin,a0
	moveq	#0,d1
	jsr	Datei_name		; FILES_SUP.S: AMBFILES\ davor
	clr.w	-(sp)			; Fopen(Name, lesen)
	move.l	a0,-(sp)
	move.w	#Fopen,-(sp)
	Gemdos
	addq.l	#8,sp
	tst.l	d0
	bmi	.raus
	move.w	d0,d3
	move.w	#2,-(sp)		; Fseek(0, Kanal, Ende): Laenge
	move.w	d3,-(sp)
	clr.l	-(sp)
	move.w	#Fseek,-(sp)
	Gemdos
	lea	10(sp),sp
	move.l	d0,d2
	clr.w	-(sp)			; Fseek(0, Kanal, Anfang)
	move.w	d3,-(sp)
	clr.l	-(sp)
	move.w	#Fseek,-(sp)
	Gemdos
	lea	10(sp),sp
	cmp.l	#12,d2
	blt	.zu
	cmp.l	#YM_HOECHSTENS,d2
	bhi	.zu
	move.l	d2,-(sp)		; Malloc(Laenge)
	move.w	#Malloc,-(sp)
	Gemdos
	addq.l	#6,sp
	tst.l	d0
	beq	.zu
	move.l	d0,a2
	move.l	a2,-(sp)		; Fread(Kanal, Laenge, Block)
	move.l	d2,-(sp)
	move.w	d3,-(sp)
	move.w	#Fread,-(sp)
	Gemdos
	lea	12(sp),sp
	move.l	d0,d1
	move.w	d3,-(sp)		; Fclose(Kanal)
	move.w	#Fclose,-(sp)
	Gemdos
	addq.l	#4,sp
	cmp.l	d1,d2
	bne.s	.weg			; nicht ganz gelesen
	lea	ym_kennung,a0		; die Sprungtabelle des Blocks
	move.l	a2,a1
	moveq	#3-1,d0
.kenn:	cmpm.l	(a0)+,(a1)+
	bne.s	.weg
	dbra	d0,.kenn
	move.l	a2,ym_block
	bsr	ym_inf_lesen
	bsr	ym_falcon_psg
	move.b	CONTERM.w,ym_conterm
	and.b	#%11111010,CONTERM.w	; kein Tastenklick, keine Glocke
	st	ym_bereit
	bra.s	.raus
.weg:	move.l	a2,-(sp)		; Mfree(Block)
	move.w	#Mfree,-(sp)
	Gemdos
	addq.l	#6,sp
	bra.s	.raus
.zu:	move.w	d3,-(sp)		; Fclose(Kanal)
	move.w	#Fclose,-(sp)
	Gemdos
	addq.l	#4,sp
.raus:	movem.l	(sp)+,d0-d3/a0-a2
	rts

; ym_falcon_psg -- Falcon: den YM ueber den ADC-Eingang in den Ausgang
; legen (Soundcmd ADCINPUT = PSG links und rechts, ADDERIN = ADC).  So
; steht es nach dem Einschalten; nach einem Programm, das die Matrix
; umgestellt hat, nicht unbedingt.  Nur mit 16-Bit-Ton im Cookie _SND.
; Register: d0-d2/a0-a2 frei (ym_install).
ym_falcon_psg:
	btst	#2,mi_snd
	beq.s	.raus
	move.w	#3,-(sp)		; Soundcmd(ADCINPUT, PSG, PSG)
	move.w	#5,-(sp)
	move.w	#xb_Soundcmd_ym,-(sp)
	Xbios
	addq.l	#6,sp
	move.w	#1,-(sp)		; Soundcmd(ADDERIN, ADC)
	move.w	#4,-(sp)
	move.w	#xb_Soundcmd_ym,-(sp)
	Xbios
	addq.l	#6,sp
.raus:	rts

xb_Soundcmd_ym	equ	130

; ym_remove -- anhalten, conterm zurueck.  Aus Musik_remove (Exit_program,
; Speicher_voll, Notausgang): kein GEMDOS, der Block bleibt bis Pterm.
; Alle Register bleiben.
ym_remove:
	tst.b	ym_bereit
	beq.s	.raus
	bsr	ym_stop
	sf	ym_bereit
	move.b	ym_conterm,CONTERM.w
.raus:	rts

; ---------------------------------------------------------------------------
; ym_inf_lesen -- MUSIK_YM.INF nach ym_tabelle (Byte je Thalions Nummer
; 1-32, 0 = silent).  Two numbers per line; space, tab, ";" up to the
; end of the line, CR and LF.  A line without two valid numbers does not
; count.  Without the file, or if it cannot be read, the built-in template
; ym_inf_vorgabe applies.
; Register: d0-d3/a0-a2 frei (ym_install).
ym_inf_lesen:
	lea	ym_name_inf,a0
	moveq	#0,d1
	jsr	Datei_name
	clr.w	-(sp)			; Fopen(Name, lesen)
	move.l	a0,-(sp)
	move.w	#Fopen,-(sp)
	Gemdos
	addq.l	#8,sp
	tst.l	d0
	bmi.s	.vorgabe
	move.w	d0,d3
	pea	ym_inf_puffer		; Fread(Kanal, Groesse-1, Puffer)
	pea	YM_INF_GROESSE-1.w
	move.w	d3,-(sp)
	move.w	#Fread,-(sp)
	Gemdos
	lea	12(sp),sp
	move.l	d0,d1
	move.w	d3,-(sp)		; Fclose(Kanal)
	move.w	#Fclose,-(sp)
	Gemdos
	addq.l	#4,sp
	tst.l	d1
	bmi.s	.vorgabe
	lea	ym_inf_puffer,a0
	clr.b	(a0,d1.l)		; Endnull
	bra.s	.lesen
.vorgabe:
	lea	ym_inf_vorgabe,a0	; built-in tools/musik_ym.inf
.lesen:	lea	ym_tabelle,a2
.zeile:	bsr.s	.zahl			; d0 = Thalions Nummer, -1 = keine
	move.w	d0,d2
	bsr.s	.zahl			; d0 = YM-Stueck
	tst.w	d2
	ble.s	.rest
	cmp.w	#YM_NUMMERN,d2
	bhi.s	.rest
	tst.w	d0
	bmi.s	.rest
	cmp.w	#YM_STUECKE,d0
	bhi.s	.rest
	move.b	d0,(a2,d2.w)
.rest:	move.b	(a0),d1			; bis hinter das Zeilenende
	beq.s	.raus
	addq.l	#1,a0
	cmp.b	#10,d1
	bne.s	.rest
	bra.s	.zeile
.raus:	rts

; .zahl -- Leerraum ueberspringen, dann eine Dezimalzahl ab a0 lesen.
; d0 = Wert, -1 wenn keine Ziffer kommt (dann steht a0 auf dem Zeichen).
.zahl:	move.b	(a0),d1
	cmp.b	#' ',d1
	beq.s	.weiter
	cmp.b	#9,d1
	bne.s	.ziffern
.weiter:
	addq.l	#1,a0
	bra.s	.zahl
.ziffern:
	moveq	#-1,d0
.ziffer:
	move.b	(a0),d1
	sub.b	#'0',d1
	cmp.b	#9,d1
	bhi.s	.ende			; keine Ziffer (vorzeichenlos)
	tst.w	d0
	bpl.s	.mal
	moveq	#0,d0
.mal:	mulu	#10,d0
	ext.w	d1
	add.w	d1,d0
	cmp.w	#999,d0
	bls.s	.naechste
	move.w	#999,d0			; Unsinn bleibt ausser Bereich
.naechste:
	addq.l	#1,a0
	bra.s	.ziffer
.ende:	rts

	SECTION	Fast_DATA,data
	even
ym_kennung:				; bra.w +$0A, bra.w +$1F0, bra.w +$22
	dc.l	$6000000A,$600001F0,$60000022
ym_name_bin:
	dc.b	"MUSIK_YM.BIN",0
ym_name_inf:
	dc.b	"MUSIK_YM.INF",0
ym_inf_vorgabe:				; the template, for a missing MUSIK_YM.INF
	incbin	"../tools/musik_ym.inf"
	dc.b	0
	even
ym_bereit:
	dc.b	0			; Block geladen, die Weiche fuehrt hierher
ym_laeuft:
	dc.b	0			; +0 gerufen, +8 noch nicht
ym_conterm:
	dc.b	0
ym_timer_c:
	dc.b	0			; TCDCR Bits 4-6 vor dem ersten +4
	even

	SECTION	Fast_BSS,bss
	even
ym_block:
	ds.l	1
ym_hz:
	ds.l	1			; _hz_200 beim letzten Takt
ym_tabelle:
	ds.b	YM_NUMMERN+1		; Index = Thalions Nummer
	even
ym_inf_puffer:
	ds.b	YM_INF_GROESSE
	even

	SECTION	Program,code

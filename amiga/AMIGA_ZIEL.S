; ***************************************************************************
; AMIGA_ZIEL.S -- Thalions Schirme im Zielformat (docs/11 7.8).  Ohne
; SECTION: steht im Codeabschnitt dessen, der die Datei einbindet (nach
; AMIGA_BLIT.S); die Variablen in amiga_ziel_bss.i.
;
; Das Programm nennt in Schirm_tabelle die Amiga-Schirme, die der Videl
; direkt zeigen soll (Makro SCHIRM, amiga_vorspann.i).  Zu jedem legt
; Schirme_anlegen einen Schirm im Zielformat an (ZIEL_*: Falcon 8 Ebenen
; wortweise).  **Massgeblich ist der Zielschirm.**  Thalions Amiga-Schirm
; bleibt als Zwischenspeicher stehen: Eine Zeile dort gilt, solange ihr
; Merker in SCH_GUELTIG gesetzt ist.
;
; Wer schreibt:
;   - Blits (Amiga_blit -> Bl_umlenken):
;       * straight into the target where there is a way for it
;         (Bl_ziel_d8): the buffer lines are marked stale first, then
;         written, so a VBL in between never takes them as valid.
;       * sonst ueber den Zwischenspeicher: die beruehrten Zeilen zuerst
;         holen (nur die ungueltigen), Thalions Blit dort ausfuehren, die
;         Zeilen von D ins Ziel bringen.
;   - Thalions CPU an bekannten Stellen (K3): danach Zeilen ins Ziel bringen
;     (Alle_bringen).
; Zeilen holen und bringen macht der Falcon-Blitter, je Ebene ein Blit.
; ***************************************************************************

; ***************************************************************************
; Schirme_anlegen -- aus Schirm_tabelle: Zielschirme, Merker, Direkt_von/bis.
; Der Zwischenspeicher wird einmal ganz ins Ziel gebracht (Thalions Schirm
; kann Daten tragen).  Mehr als SCH_MAX Eintraege bleiben aus.
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
Schirme_anlegen:
	clr.l	Direkt_von
	clr.l	Direkt_bis
	move.l	#Ziel_speicher+255,d0
	and.l	#-256,d0
	move.l	d0,d3			; naechster Zielschirm
	lea	Sch_gueltig_speicher,a2
	lea	Schirm_tabelle,a5
	moveq	#SCH_MAX-1,d7
.e:	move.l	SCH_AMIGA(a5),d1
	beq	.aus
	cmp.w	#FALCON_HOEHE,SCH_ZEILEN(a5)
	bls.b	.zeilen
	move.w	#FALCON_HOEHE,SCH_ZEILEN(a5)
.zeilen:
	move.w	SCH_EBENEN(a5),d2
	mulu.w	#AMIGA_EBENE,d2
	move.w	d2,SCH_BPR(a5)
	mulu.w	SCH_ZEILEN(a5),d2
	add.l	d1,d2
	move.l	d2,SCH_ENDE(a5)
	add.l	#ZIEL_RAND,d3		; black lines above and below it
	move.l	d3,SCH_ZIEL(a5)
	add.l	#ZIEL_SCHIRM+ZIEL_RAND+FALCON_LUECKE,d3
	move.l	a2,SCH_GUELTIG(a5)
	lea	FALCON_HOEHE(a2),a2
	move.l	#$7FFFFFFF,SCH_BANK(a5)	; no split set yet (it can be -1)
	tst.l	Direkt_bis		; Bereich aller Schirme
	beq.b	.erster
	cmp.l	Direkt_von,d1
	bhs.b	.von
.erster:
	move.l	d1,Direkt_von
.von:	cmp.l	Direkt_bis,d2
	bls.b	.bis
	move.l	d2,Direkt_bis
.bis:	move.l	SCH_ZIEL(a5),a1		; all black: margins, other planes
	lea	-ZIEL_RAND(a1),a1	; (a table before may have used it)
	moveq	#0,d0
	move.w	#2*ZIEL_RAND_ZEILEN+FALCON_HOEHE,d1
	move.w	d7,-(sp)
	bsr	Zeilen_loeschen
	move.w	(sp)+,d7
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	bsr	Zeilen_bringen
	lea	SCH_LAENGE(a5),a5
	dbf	d7,.e
.aus:	rts

; ***************************************************************************
; Schirme_wechseln -- a0 = another table (SCHIRM entries, dc.l 0) or 0 for
; none, for a program whose screens change their format between scenes
; (the intro).  The screens of the old table are fetched whole first, so
; Thalion's buffers hold everything again; then the new table goes into
; Schirm_tabelle (room for SCH_MAX entries) and Schirme_anlegen brings its
; screens into the target.  The display is judged anew at the next VBL:
; directly or converted.  The VBL (level 4) is held off meanwhile.
;   All registers are preserved.
; ***************************************************************************
Schirme_wechseln:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0400,sr
	bsr	Zeiger_weg		; no pointer in a target that is fetched
	bsr	Alle_sicherstellen
	lea	Schirm_tabelle,a1
	move.l	a0,d0
	beq.b	.ende
	moveq	#SCH_MAX-1,d1
.e:	tst.l	(a0)
	beq.b	.ende
	moveq	#SCH_LAENGE/2-1,d0
.k:	move.w	(a0)+,(a1)+
	dbf	d0,.k
	dbf	d1,.e
.ende:	clr.l	(a1)
	bsr	Schirme_anlegen
	clr.b	Anzeige_ist_direkt
	move.l	#-1,Zustand_alt		; changed: Anzeige_nachfuehren judges
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Ziel_loeschen -- the target lines d0 .. d0+d1-1 of the screen a5 to 0 in
; the planes the screen has (SCH_EBENEN); the other planes stay.  The
; buffer lines are marked stale first (Zeilen_ungueltig), so a VBL in
; between never takes them as valid (ST's finding).  One blit: each
; 16-pixel group counts as a line of SCH_EBENEN words.
; Target_fill -- the same in planes 0 .. d2-1 only, with d3 = HOPOP_NULL
; (all 0) or HOPOP_EINS (all 1).
;   All registers are preserved.
; ***************************************************************************
Ziel_loeschen:
	movem.l	d0-d3/d7/a1,-(sp)
	move.w	SCH_EBENEN(a5),d2
	moveq	#HOPOP_NULL,d3
	bra.b	Ziel_setzen
Target_fill:
	movem.l	d0-d3/d7/a1,-(sp)
Ziel_setzen:
	bsr	Zeilen_schneiden
	ble.b	.aus
	bsr	Zeilen_ungueltig	; first: the buffer lines are stale
	move.w	sr,-(sp)
	or.w	#$0400,sr		; the VBL uses the blitter too
	move.w	d2,d7			; planes
	move.w	d0,d2
	mulu.w	#ZIEL_ZEILE,d2
	move.l	SCH_ZIEL(a5),a1
	add.l	d2,a1
	move.w	d7,d2
	moveq	#-1,d7
	move.w	d7,BL_MASKE1
	move.w	d7,BL_MASKE2
	move.w	d7,BL_MASKE3
	move.w	#2,BL_DST_XINC
	move.w	d2,BL_XCOUNT
	add.w	d2,d2
	neg.w	d2
	add.w	#ZIEL_WORT+2,d2
	move.w	d2,BL_DST_YINC		; to the next group
	move.w	d3,BL_HOPOP
	clr.b	BL_SKEW
	move.l	a1,BL_DST
	move.w	d1,d2
	mulu.w	#AMIGA_WORTE,d2
	move.w	d2,BL_YCOUNT
	bsr	Blit_starten
	move.w	(sp)+,sr
.aus:	movem.l	(sp)+,d0-d3/d7/a1
	rts

; ***************************************************************************
; Schirm_vorher / Schirm_nachher -- around Thalion's CPU writing into the
; screen whose buffer starts at d0 (K3, once per scene): before, all its
; lines from the target into the buffer (only the invalid ones); after, all
; of them back into the target.  Not in the table: nothing.
;   All registers are preserved.
; ***************************************************************************
Schirm_vorher:
	movem.l	d0-d1/a0/a5,-(sp)
	lea	Zeilen_sicherstellen,a0
	bra.b	Schirm_ganz
Schirm_nachher:
	movem.l	d0-d1/a0/a5,-(sp)
	lea	Zeilen_bringen,a0
Schirm_ganz:
	bsr	Schirm_suchen
	beq.b	.aus
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	jsr	(a0)
.aus:	movem.l	(sp)+,d0-d1/a0/a5
	rts

; ***************************************************************************
; Schirm_suchen -- d0.l = Adresse -> a5 = Eintrag, Z aus; sonst Z gesetzt.
;   Veraendert a5.
; ***************************************************************************
Schirm_suchen:
	cmp.l	Direkt_von,d0
	blo.b	.nein
	cmp.l	Direkt_bis,d0
	bhs.b	.nein
	lea	Schirm_tabelle,a5
.e:	tst.l	SCH_AMIGA(a5)
	beq.b	.nein
	cmp.l	SCH_AMIGA(a5),d0
	blo.b	.n
	cmp.l	SCH_ENDE(a5),d0
	blo.b	.ja
.n:	lea	SCH_LAENGE(a5),a5
	bra.b	.e
.ja:	andi.b	#$FB,ccr		; Z aus
	rts
.nein:	ori.b	#$04,ccr		; Z gesetzt
	rts

; ***************************************************************************
; Zeilen_bringen -- Zeilen d0 .. d0+d1-1 des Schirms a5 aus dem
; Zwischenspeicher ins Ziel; sie gelten danach.  Zeilen_holen -- dieselben
; aus dem Ziel in den Zwischenspeicher.  Beide schneiden auf den Schirm und
; halten den VBL fern, der den Blitter auch benutzt.
;   Alle Register bleiben.
; ***************************************************************************
Zeilen_bringen:
	movem.l	d0-d7/a0-a3,-(sp)
	lea	Ebene_blit,a3
	bra.b	Zeilen_umsetzen
Zeilen_holen:
	movem.l	d0-d7/a0-a3,-(sp)
	lea	Ebene_zurueck,a3
Zeilen_umsetzen:
	bsr	Zeilen_schneiden
	ble.b	.aus
	move.w	sr,-(sp)
	or.w	#$0400,sr		; kein VBL (Stufe 4) dazwischen
	move.w	d0,d2
	mulu.w	SCH_BPR(a5),d2
	move.l	SCH_AMIGA(a5),a2
	add.l	d2,a2			; Amiga, Ebene 0
	move.w	d0,d3
	mulu.w	#ZIEL_ZEILE,d3
	move.l	SCH_ZIEL(a5),a1
	add.l	d3,a1			; Ziel, Ebene 0
	moveq	#0,d4			; Ebene
.eb:	move.l	a2,a0
	move.w	SCH_BPR(a5),d6
	move.w	#HOPOP_KOPIE,d5
	movem.l	d1/d4/a1-a3,-(sp)
	jsr	(a3)
	movem.l	(sp)+,d1/d4/a1-a3
	lea	AMIGA_EBENE(a2),a2
	addq.l	#2,a1
	addq.w	#1,d4
	cmp.w	SCH_EBENEN(a5),d4
	blo.b	.eb
	move.w	(sp)+,sr
	move.l	SCH_GUELTIG(a5),a0	; die Zeilen gelten
	add.w	d0,a0
	subq.w	#1,d1
.g:	st	(a0)+
	dbf	d1,.g
.aus:	movem.l	(sp)+,d0-d7/a0-a3
	rts

; Zeilen_schneiden -- d0/d1 auf die Zeilen des Schirms a5; Flags nach d1
; (le: keine).  Veraendert d0-d1.
Zeilen_schneiden:
	tst.w	d0
	bpl.b	.o
	add.w	d0,d1
	moveq	#0,d0
.o:	move.w	SCH_ZEILEN(a5),-(sp)
	sub.w	d0,(sp)			; Zeilen ab d0
	cmp.w	(sp),d1
	ble.b	.u
	move.w	(sp),d1
.u:	addq.l	#2,sp
	tst.w	d1
	rts

; Ebene_zurueck -- Ebene_blit rueckwaerts: eine Ebene, 20 Worte breit, d1
; Zeilen, aus dem Ziel (a1, jedes ZIEL_WORT-te Byte) in den
; Zwischenspeicher (a0, d6 Bytes je Zeile), HOP/OP d5.
Ebene_zurueck:
	moveq	#-1,d7
	move.w	d7,BL_MASKE1
	move.w	d7,BL_MASKE2
	move.w	d7,BL_MASKE3
	move.w	#ZIEL_WORT,BL_SRC_XINC
	move.w	#ZIEL_ZEILE-(AMIGA_WORTE-1)*ZIEL_WORT,BL_SRC_YINC
	move.w	#2,BL_DST_XINC
	sub.w	#(AMIGA_WORTE-1)*2,d6
	move.w	d6,BL_DST_YINC
	move.w	#AMIGA_WORTE,BL_XCOUNT
	move.w	d5,BL_HOPOP
	clr.b	BL_SKEW
	move.l	a1,BL_SRC
	move.l	a0,BL_DST
	move.w	d1,BL_YCOUNT
	bra	Blit_starten

; ***************************************************************************
; Zeilen_sicherstellen -- die ungueltigen unter den Zeilen d0 .. d0+d1-1 des
; Schirms a5 aus dem Ziel holen.  Zeilen_ungueltig -- dieselben als
; ungueltig merken (das Ziel wurde ohne den Zwischenspeicher beschrieben).
;   Alle Register bleiben.
; ***************************************************************************
Zeilen_sicherstellen:
	tst.b	SCH_UNGUELTIG(a5)
	beq.b	.nichts
	movem.l	d0-d3/a0,-(sp)
	bsr	Zeilen_schneiden
	ble.b	.aus
	move.l	SCH_GUELTIG(a5),a0
	move.w	d0,d2
	add.w	d1,d2			; Ende
.such:	cmp.w	d2,d0			; naechste ungueltige
	bhs.b	.aus
	tst.b	0(a0,d0.w)
	beq.b	.lauf
	addq.w	#1,d0
	bra.b	.such
.lauf:	move.w	d0,d3			; bis zur naechsten gueltigen
.l:	addq.w	#1,d3
	cmp.w	d2,d3
	bhs.b	.holen
	tst.b	0(a0,d3.w)
	beq.b	.l
.holen:	moveq	#0,d1
	move.w	d3,d1
	sub.w	d0,d1
	bsr	Zeilen_holen		; setzt die Merker
	IFD	AMIGA_MESSEN
	add.l	d1,Zl_geholt
	ENDC
	move.w	d3,d0
	bra.b	.such
.aus:	bsr.b	Merker_pruefen
	movem.l	(sp)+,d0-d3/a0
.nichts:
	rts

Zeilen_ungueltig:
	movem.l	d0-d1/a0,-(sp)
	bsr	Zeilen_schneiden
	ble.b	.aus
	move.l	SCH_GUELTIG(a5),a0
	add.w	d0,a0
	subq.w	#1,d1
.u:	clr.b	(a0)+
	dbf	d1,.u
	st	SCH_UNGUELTIG(a5)	; erst danach: Merker_pruefen im VBL
.aus:	movem.l	(sp)+,d0-d1/a0
	rts

; Ziel_frei -- before writing the target of screen a5 directly: if the
; Videl shows it until the next VBL (a new base was set since the last VBL,
; Basis_setzen, and the one before lies in this target), wait for that VBL.
; On the Amiga a new copper list also takes over at the next frame, and
; Thalion's frames never last longer than Thalion's wait; ours can, and then
; Thalion drew into the picture still shown (T66, the clouds).  From the
; main flow only: with the VBL held off (level 4 or more) it returns at
; once.
;   All registers are preserved.
Ziel_frei:
	tst.b	Basis_wartet
	beq.b	.aus
	move.l	d0,-(sp)
	move.w	sr,d0
	and.w	#$0700,d0
	cmp.w	#$0300,d0
	bhi.b	.ende			; in the VBL or held off: no wait
	move.l	Basis_vorher,d0
	sub.l	SCH_ZIEL(a5),d0
	add.l	#ZIEL_RAND,d0
	cmp.l	#2*ZIEL_RAND+ZIEL_SCHIRM,d0
	bhs.b	.ende			; another picture
.w:	tst.b	Basis_wartet
	bne.b	.w
.ende:	move.l	(sp)+,d0
.aus:	rts

; Merker_pruefen -- SCH_UNGUELTIG(a5) loeschen, wenn alle Zeilen gelten.
;   Veraendert d0/a0.
Merker_pruefen:
	move.l	SCH_GUELTIG(a5),a0
	move.w	SCH_ZEILEN(a5),d0
	subq.w	#1,d0
.p:	tst.b	(a0)+
	dbeq	d0,.p
	beq.b	.aus			; eine gilt nicht
	clr.b	SCH_UNGUELTIG(a5)
.aus:	rts

; ***************************************************************************
; Alle_sicherstellen -- alle Zeilen aller Schirme gelten (vor dem Umsetzen
; in Amiga_vbl, das aus dem Zwischenspeicher liest).  Alle_bringen -- alle
; Zeilen aller Schirme ins Ziel (nach Thalions CPU, K3).
;   Alle Register bleiben.
; ***************************************************************************
Alle_sicherstellen:
	movem.l	d0-d1/a0/a5,-(sp)
	lea	Zeilen_sicherstellen,a0
	bra.b	Alle_schirme
Alle_bringen:
	movem.l	d0-d1/a0/a5,-(sp)
	lea	Zeilen_bringen,a0
Alle_schirme:
	lea	Schirm_tabelle,a5
	moveq	#SCH_MAX-1,d1
.e:	tst.l	SCH_AMIGA(a5)
	beq.b	.aus
	move.w	d1,-(sp)
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	jsr	(a0)
	move.w	(sp)+,d1
	lea	SCH_LAENGE(a5),a5
	dbf	d1,.e
.aus:	movem.l	(sp)+,d0-d1/a0/a5
	rts

; ***************************************************************************
; Bl_umlenken -- aus Amiga_blit, wenn Schirme direkt sind.  Beruehrt kein
; benutzter Kanal einen Schirm, laeuft der Blit wie immer.  Sonst direkt
; ins Ziel (nur D im Schirm, or C and D at the same place, and a way for
; it) oder ueber den Zwischenspeicher.  A channel touches the screens by
; its whole range, not by its start: Thalion's clouds ($4E2A) start a word
; left of the line, so at line 0 before the screen or in the one before.
; While the mouse pointer is on and the display direct, the pointer lies in
; the target (menu): it goes first, and the VBL, which draws it again,
; waits until the blit is done.
;   Veraendert d0-d7/a0-a5.
; ***************************************************************************
Bl_umlenken:
	lea	Amiga_register,a4
	move.w	AR_BLTCON1(a4),d0	; Linien und Fuellen: Bereich unklar
	and.w	#%11001,d0
	bne	Amiga_blit_amiga
	moveq	#0,d7			; Kanaele am Schirm: 8 A, 4 B, 2 C, 1 D
	lea	Bl_kanal,a0		; and the screen of each start, or 0
	lea	Bl_zeiger,a1
	moveq	#3,d6			; Bit 11 (A) .. 8 (D) von BLTCON0
.k:	clr.l	(a0)
	btst	d6,AR_BLTCON0(a4)	; im oberen Byte: Bit 11 .. 8
	beq.b	.kn
	move.w	(a1),d1
	move.l	0(a4,d1.w),d4
	move.w	2(a1),d1
	move.w	0(a4,d1.w),d2
	bsr	Kanal_bereich		; [d5, d4]
	cmp.l	Direkt_bis,d5
	bhs.b	.kn
	cmp.l	Direkt_von,d4
	blo.b	.kn
	bset	d6,d7
	move.w	(a1),d1
	move.l	0(a4,d1.w),d0
	and.w	#-2,d0
	bsr	Schirm_suchen
	beq.b	.kn
	move.l	a5,(a0)
.kn:	addq.l	#4,a0
	addq.l	#4,a1
	dbf	d6,.k
	tst.w	d7
	beq	Amiga_blit_amiga
	move.l	Bl_kanal+12,d0		; D's screen: still shown?
	beq.b	.frei
	move.l	d0,a5
	bsr	Ziel_frei
.frei:	tst.b	Zg_dma
	beq.b	Bl_umlenken_weg
	tst.b	Anzeige_ist_direkt
	beq.b	Bl_umlenken_weg
	move.w	sr,-(sp)
	or.w	#$0400,sr
	movem.l	d7/a4,-(sp)
	bsr	Zeiger_weg
	movem.l	(sp)+,d7/a4
	bsr.b	Bl_umlenken_weg
	move.w	(sp)+,sr
	rts

; Bl_umlenken_weg -- d7 = the channels at the screens, a4 = Amiga_register.
Bl_umlenken_weg:
	cmp.w	#1,d7			; nur D?
	beq.b	.d
	cmp.w	#3,d7			; C and D: at the same place?
	bne.b	.fenster
	move.l	AR_BLTCPT(a4),d0
	move.l	AR_BLTDPT(a4),d1
	eor.l	d1,d0
	and.l	#-2,d0
	bne.b	.fenster
	move.w	AR_BLTCMOD(a4),d0
	move.w	AR_BLTDMOD(a4),d1
	eor.w	d1,d0
	and.w	#-2,d0
	bne.b	.fenster
	bsr	Bl_erstes_wort		; $CA whose first word stays as it is?
	beq.b	.d
	move.l	AR_BLTDPT(a4),d0	; then D's screen from the second word
	and.w	#-2,d0
	addq.l	#2,d0
	bsr	Schirm_suchen
	beq.b	.fenster
	move.l	a5,Bl_kanal+8
	move.l	a5,Bl_kanal+12
	bra.b	.w
.d:	clr.b	Bl_ziel_vorn
.w:	tst.l	Bl_kanal+12		; D starts in a screen?
	beq.b	.fenster
	bsr	Bl_ziel_waehlen
	beq.b	.fenster
	IFD	BLIT_PRUEF
	bra	Bl_ziel_pruefen
	ELSE
	movem.w	Bl_d_zeilen,d0-d1	; first: D's buffer lines are stale
	bsr	Zeilen_ungueltig	; (a5 = D's screen), then the way
	jmp	(a0)
	ENDC

; ueber den Zwischenspeicher: erst holen, in every screen a channel touches,
; dann Thalions Blit, dann D's lines bringen
.fenster:
	IFD	AMIGA_MESSEN
	addq.l	#1,Bl_fenster
	ENDC
	lea	Bl_d_bereiche,a3
	moveq	#SCH_MAX-1,d0
.l:	clr.l	(a3)+
	dbf	d0,.l
	lea	Bl_zeiger,a1
	moveq	#3,d6
.h:	btst	d6,d7
	beq.b	.hn
	lea	Schirm_tabelle,a5
	lea	Bl_d_bereiche,a3
.s:	tst.l	SCH_AMIGA(a5)
	beq.b	.hn
	move.w	(a1),d1
	move.l	0(a4,d1.w),d4
	move.w	2(a1),d1
	move.w	0(a4,d1.w),d2
	bsr	Kanal_zeilen
	bsr	Zeilen_sicherstellen
	tst.w	d6			; D: the lines for afterwards
	bne.b	.sn
	movem.w	d0-d1,(a3)
.sn:	addq.l	#4,a3
	lea	SCH_LAENGE(a5),a5
	bra.b	.s
.hn:	addq.l	#4,a1
	dbf	d6,.h
	bsr	Amiga_blit_amiga
	lea	Schirm_tabelle,a5
	lea	Bl_d_bereiche,a3
.b:	tst.l	SCH_AMIGA(a5)
	beq.b	.aus
	movem.w	(a3)+,d0-d1
	tst.w	d1
	beq.b	.bn
	bsr	Zeilen_bringen
	IFD	AMIGA_MESSEN
	add.l	d1,Zl_gebracht
	ENDC
.bn:	lea	SCH_LAENGE(a5),a5
	bra.b	.b
.aus:	rts
; je Kanal A, B, C, D: Versatz des Zeigers und des Modulos in Amiga_register
Bl_zeiger:
	dc.w	AR_BLTAPT,AR_BLTAMOD
	dc.w	AR_BLTBPT,AR_BLTBMOD
	dc.w	AR_BLTCPT,AR_BLTCMOD
	dc.w	AR_BLTDPT,AR_BLTDMOD

; ***************************************************************************
; Bl_erstes_wort -- C = D: is the blit $CA (D = A ? B : C), ascending, with
; two words or more a line, and a first word mask of A that the shift
; empties (AFWM < 1 << ASH)?  Then the first word of every line is D = C,
; and Bl_ziel_vorn is set (Z clear): the way into the target may start
; with the second word.  Thalion's clouds ($4E2A) left of the screen: the
; first word lies before the line, in another plane or screen.
;   Changes d0-d2.
; ***************************************************************************
Bl_erstes_wort:
	clr.b	Bl_ziel_vorn
	move.w	AR_BLTCON0(a4),d0
	cmp.b	#$CA,d0
	bne.b	.nein
	btst	#11,d0			; USEA
	beq.b	.nein
	btst	#1,AR_BLTCON1+1(a4)	; absteigend
	bne.b	.nein
	moveq	#63,d1
	and.w	AR_BLTSIZE(a4),d1
	cmp.w	#2,d1			; 2 .. 63 words (0 = 64)
	bhs.b	.breit
	tst.w	d1
	bne.b	.nein
.breit:	rol.w	#4,d0
	and.w	#15,d0			; ASH
	moveq	#0,d1
	bset	d0,d1			; 1 << ASH
	moveq	#0,d2
	move.w	AR_BLTAFWM(a4),d2
	cmp.l	d1,d2
	bhs.b	.nein
	st	Bl_ziel_vorn
	moveq	#1,d0			; Z clear
	rts
.nein:	moveq	#0,d0			; Z set
	rts

; ***************************************************************************
; Kanal_bereich -- the bytes a channel touches: d4 = Zeiger, d2 = Modulo
; (Bit 0 zaehlt nicht), a4 = Amiga_register (Groesse, Richtung) -> [d5, d4],
; both included.  Der Bereich wie in Bl_pruefen: Zeile r beginnt
; (absteigend: endet) bei Zeiger + r * Schritt, Schritt = 2 * Worte +
; Modulo, auch negativ.
;   Veraendert d0-d5.
; Kanal_zeilen -- welche Zeilen des Schirms a5 der Kanal ueberstreicht:
; d0 = erste Zeile, d1 = Zeilen (auch 0).
;   Veraendert d0-d5.
; ***************************************************************************
Kanal_bereich:
	and.w	#-2,d4
	and.w	#-2,d2
	BL_GROESSE	d0,d1
	add.w	d1,d1			; 2 * Worte
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
	btst	#1,AR_BLTCON1+1(a4)
	beq.b	.auf
	move.l	d4,d5			; absteigend: D - max - Zeile .. D - min
	sub.l	d3,d5
	sub.l	d1,d5
	sub.l	d2,d4
	rts
.auf:	move.l	d4,d5			; aufsteigend: D + min .. D + max + Zeile
	add.l	d2,d5
	add.l	d3,d4
	add.l	d1,d4
	rts

Kanal_zeilen:
	bsr.b	Kanal_bereich		; [d5, d4] Bytes, beide eingeschlossen
	move.l	SCH_AMIGA(a5),d0
	sub.l	d0,d5
	bpl.b	.v
	moveq	#0,d5
.v:	sub.l	d0,d4
	move.l	SCH_ENDE(a5),d1
	sub.l	d0,d1
	subq.l	#1,d1
	cmp.l	d1,d4
	ble.b	.b
	move.l	d1,d4
.b:	moveq	#0,d1
	cmp.l	d5,d4
	blt.b	.leer
	divu.w	SCH_BPR(a5),d5
	divu.w	SCH_BPR(a5),d4
	moveq	#0,d0
	move.w	d5,d0			; erste Zeile
	move.w	d4,d1
	sub.w	d5,d1
	addq.w	#1,d1
	rts
.leer:	moveq	#0,d0
	rts

; ***************************************************************************
; Bl_ziel_waehlen -- D liegt im Schirm (Bl_kanal+12), C is unused, outside
; the screens, or at D's place (Bl_umlenken): Gibt es einen Weg direkt ins
; Ziel?  Dann a0 = der Weg, Z aus, und Bl_ziel_* sind gesetzt.
; Bedingungen: aufsteigend, jede Zeile von D bleibt in einer Ebene einer
; Amiga-Zeile (with Bl_ziel_vorn from the second word on), der Schritt von
; Zeile zu Zeile sind ganze Amiga-Zeilen, und D bleibt im Schirm.  Dann hat D im Ziel einen festen Schritt je Wort
; (ZIEL_WORT) und je Zeile (Bl_ziel_dmod).  The ways (AMIGA_BLIT.S):
;   Bl_ziel_d8    $D8, all four, nothing shifted, C outside (extro)
;   Bl_ziel_ca    $CA, all four, C = D (intro: clouds)
;   Bl_ziel_f0    $F0, A and D, A not shifted (intro: logo stages)
;   Bl_ziel_allg  any other minterm, C = D or unused (intro: text)
;   Veraendert d0-d6/a0/a5.
; ***************************************************************************
Bl_ziel_waehlen:
	btst	#1,AR_BLTCON1+1(a4)	; absteigend
	bne	.nein
	move.l	Bl_kanal+12,a5
	BL_GROESSE	d5,d6		; d5 Zeilen, d6 Worte
	move.l	AR_BLTDPT(a4),d0
	and.w	#-2,d0
	move.l	d0,d4			; Amiga-Zeiger
	tst.b	Bl_ziel_vorn		; the first word stays (Bl_erstes_wort):
	beq.b	.v			; the place from the second
	addq.l	#2,d0
	subq.w	#1,d6
.v:	sub.l	SCH_AMIGA(a5),d0
	divu.w	SCH_BPR(a5),d0
	moveq	#0,d1
	move.w	d0,d1			; y0
	clr.w	d0
	swap	d0
	divu.w	#AMIGA_EBENE,d0		; Ebene : Byte in der Ebene
	move.w	d0,d3			; Ebene
	swap	d0			; Byte
	move.w	d6,d2
	add.w	d2,d2
	add.w	d0,d2
	cmp.w	#AMIGA_EBENE,d2		; bleibt in der Ebene?
	bhi	.nein
	lsr.w	#1,d0			; Wort
	mulu.w	#ZIEL_WORT,d0
	add.w	d3,d3
	add.w	d3,d0			; Versatz in der Zielzeile
	move.w	AR_BLTDMOD(a4),d2
	and.w	#-2,d2
	add.w	d6,d2
	add.w	d6,d2			; Schritt
	ble	.nein
	ext.l	d2
	move.l	d2,Bl_ziel_schritt
	divu.w	SCH_BPR(a5),d2
	swap	d2
	tst.w	d2
	bne	.nein			; keine ganzen Zeilen
	swap	d2			; k
	move.w	d5,d3
	subq.w	#1,d3
	mulu.w	d2,d3
	add.l	d1,d3			; letzte Zeile
	swap	d3
	tst.w	d3
	bne	.nein
	swap	d3
	cmp.w	SCH_ZEILEN(a5),d3
	bhs	.nein
	sub.w	d1,d3
	addq.w	#1,d3
	movem.w	d1/d3,Bl_d_zeilen	; fuer Zeilen_ungueltig
	mulu.w	#ZIEL_ZEILE,d1
	add.l	SCH_ZIEL(a5),d1
	add.l	d0,d1
	tst.b	Bl_ziel_vorn		; the first word: never read or written
	beq.b	.d
	sub.l	#ZIEL_WORT,d1
	addq.w	#1,d6
.d:	move.l	d1,Bl_ziel_d
	mulu.w	#ZIEL_ZEILE,d2		; Zeilenschritt im Ziel
	mulu.w	#ZIEL_WORT,d6
	sub.l	d6,d2
	move.w	d2,Bl_ziel_dmod
	move.l	Bl_ziel_schritt,d2	; D danach, in Amiga-Adressen
	mulu.w	d5,d2
	add.l	d4,d2
	move.l	d2,Bl_ziel_d_ende

	; the way by the pattern
	move.w	AR_BLTCON0(a4),d2
	move.w	d2,d0
	and.w	#$0F00,d0		; channels
	tst.l	Bl_kanal+8
	sne	Bl_ziel_c		; C = D (Bl_umlenken checked the place)
	bne.b	.c_d
	btst	#9,d2			; C used outside the screens: only $D8
	beq.b	.allg
	cmp.b	#$D8,d2
	bne	.nein
	cmp.w	#$0F00,d0
	bne	.nein
	move.w	d2,d0			; nothing shifted
	and.w	#$F000,d0
	bne	.nein
	move.w	AR_BLTCON1(a4),d0
	and.w	#$F000,d0
	bne	.nein
	lea	Bl_ziel_d8,a0
	bra.b	.ja
.c_d:	cmp.b	#$CA,d2
	bne.b	.allg
	cmp.w	#$0F00,d0
	bne.b	.allg
	lea	Bl_ziel_ca,a0
	bra.b	.ja
.allg:	cmp.b	#$F0,d2
	bne.b	.a
	cmp.w	#$0900,d0		; $F0: A and D, A not shifted
	bne.b	.a
	move.w	d2,d1
	and.w	#$F000,d1
	bne.b	.a
	lea	Bl_ziel_f0,a0
	bra.b	.ja
.a:	lea	Bl_ziel_allg,a0
.ja:	moveq	#1,d0			; Z aus
	rts
.nein:	ori.b	#$04,ccr		; Z gesetzt
	rts

	IFD	BLIT_PRUEF
; ***************************************************************************
; Bl_ziel_pruefen -- (BLIT_PRUEF) den Weg ins Ziel (a0) gegen den Weg ueber
; den Zwischenspeicher: dessen Ergebnis im Ziel und die Register merken,
; alles zurueck, dann direkt und vergleichen.  Abweichungen zaehlen in
; Bl_abweichung mit, die Pruefungen in Bl_ziel_geprueft.
; ***************************************************************************
Bl_ziel_pruefen:
	move.l	a0,Pz_weg
	move.l	Bl_kanal+12,a5
	movem.w	Bl_d_zeilen,d0-d1
	movem.w	d0-d1,Pz_zeilen
	bsr	Pz_bereich		; a0 Ziel, d0 Langworte - 1
	lea	Pz_vorher,a1
	bsr	Pz_kopieren
	lea	Amiga_register+BL_REG,a0
	lea	Pz_reg,a1
	bsr	Pr_reg_kopieren
	movem.w	Pz_zeilen,d0-d1		; ueber den Zwischenspeicher
	bsr	Zeilen_sicherstellen
	bsr	Amiga_blit_amiga
	subq.w	#1,Bl_anzahl
	move.l	Bl_kanal+12,a5
	movem.w	Pz_zeilen,d0-d1
	bsr	Zeilen_bringen
	bsr	Pz_bereich		; Ergebnis merken
	lea	Pz_soll,a1
	bsr	Pz_kopieren
	lea	Amiga_register+BL_REG,a0
	lea	Pz_reg_soll,a1
	bsr	Pr_reg_kopieren
	bsr	Pz_bereich		; zurueck wie vorher
	exg	a0,a1
	lea	Pz_vorher,a0
	bsr	Pz_kopieren
	lea	Pz_reg,a0
	lea	Amiga_register+BL_REG,a1
	bsr	Pr_reg_kopieren
	move.l	Bl_kanal+12,a5		; direkt: first the lines stale
	movem.w	Pz_zeilen,d0-d1
	bsr	Zeilen_ungueltig
	lea	Amiga_register,a4
	move.l	Pz_weg,a0
	jsr	(a0)
	addq.l	#1,Bl_ziel_geprueft
	bsr	Pz_bereich		; vergleichen
	lea	Pz_soll,a1
.v:	cmp.l	(a0)+,(a1)+
	dbne	d0,.v
	bne.b	.anders
	lea	Amiga_register+BL_REG,a0
	lea	Pz_reg_soll,a1
	moveq	#BL_REG_LAENGE/2-1,d0
.r:	cmp.w	(a0)+,(a1)+
	dbne	d0,.r
	bne.b	.anders
	rts
.anders:
	addq.w	#1,Bl_abweichung
	rts

; Pz_bereich -- die Zielzeilen Pz_zeilen des Schirms Bl_kanal+12: a0 =
; Anfang, d0 = Langworte - 1.  Veraendert d0-d1/a0.
Pz_bereich:
	move.l	Bl_kanal+12,a0
	move.l	SCH_ZIEL(a0),a0
	movem.w	Pz_zeilen,d0-d1
	mulu.w	#ZIEL_ZEILE,d0
	add.l	d0,a0
	mulu.w	#ZIEL_ZEILE/4,d1
	move.l	d1,d0
	subq.l	#1,d0
	rts
; Pz_kopieren -- d0+1 Langworte von a0 nach a1 (hoechstens ein Schirm).
Pz_kopieren:
	move.l	d0,-(sp)
.k:	move.l	(a0)+,(a1)+
	subq.l	#1,d0
	bpl.b	.k
	move.l	(sp)+,d0
	rts
	ENDC

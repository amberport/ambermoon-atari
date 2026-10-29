; ***************************************************************************
; INTRO_SUP.S -- Thalions Intro (Ambermoon_intro) auf dem Falcon: der
; Programmeinsprung und der Satz, den der Amiga-Lader uebergibt.  Die
; Amiga-Schicht darunter ist fuer Intro und Extro dieselbe
; (amiga/AMIGA_RAHMEN.S; docs/11-Intro-Extro.md, 4).
;
; Thalions Programm (Hunks 0-6) nimmt der Bau unveraendert aus
; Ambermoon_intro (tools/amiga_programm.py intro), mit K1 und K2; K3 biegt
; den Zoom auf INTRO_ZOOM.S.
; ***************************************************************************

	SECTION	Intro_code,code

; ***************************************************************************
; start -- Programmeinsprung.
; ***************************************************************************
start:
	; Der Lader gibt den Merker als Befehlszeile "1" (Spielstand da: kein
	; Vorspann, WEITERSPIELEN im Menue).  Allein gestartet bleibt er 0.
	move.l	4(sp),a0		; Basepage, Befehlszeile ab $80
	cmp.b	#1,$80(a0)
	bne.b	.ohne
	cmp.b	#'1',$81(a0)
	seq	Uebergabe+4
.ohne:
	lea	Musik_datei,a0		; Thalion's music (AMIGA_MUSIK.S)
	lea	Musik_datei+9,a1
	bsr	Musik_laden
	clr.l	-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,Alter_ssp
	bsr	Notausgang_einhaengen	; Abbau auch nach Bomben (AMIGA_NOTAUS.S)

	bsr	Falcon_pruefen
	bne.b	.kein_falcon
	bsr	Amiga_einrichten
	bne.b	.kein_falcon
	lea	Intro_h5+$12148,a0	; Thalion's "music on" ($264, $1152)
	bsr	Musik_mischen
	; Thalions Programm, wie der Amiga-Lader es ruft: a0 = Uebergabesatz,
	; zurueck die Menuewahl in d0 (docs/11, 4.2)
	lea	Uebergabe,a0
	jsr	Intro_h0
	move.w	d0,Rueckgabe
	bsr	Amiga_abraeumen
	bsr	Fehlende_melden
	bra.b	.ende
.kein_falcon:
	pea	Text_kein_falcon
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
	move.w	#-1,Rueckgabe
.ende:
	move.l	Alter_ssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	Rueckgabe,-(sp)		; fuer den Lader (lader/lader.s)
	move.w	#Pterm,-(sp)
	trap	#1

; ***************************************************************************
; Intro_umschalten -- K3 at Thalion's $24BE, the end of $2452 (new copper
; list, called from 14 places): do the covered move.l d0,Intro_h5+8 and the
; next instruction ($24C4, move.l d0,COP1LC, a K1 site), then show the new
; list from the next frame on (Anzeige_umschalten).  Its rts stands for
; Thalion's rts at $24CA.
; ***************************************************************************
Intro_umschalten:
	move.l	d0,Intro_h5+8
	move.l	d0,Amiga_register+AR_COP1LC
	bra	Anzeige_umschalten

; ***************************************************************************
; Zoom_loeschen -- K3 at Thalion's $137E, the whole routine (called before
; the zoom loop, $131A, and at $3A0).  Like Thalion: planes 0-3 of both
; screens with the pattern at Intro_h5+$12182 (0, BSS never written).  In
; the logo phase both screens are in the target format (Screens_logo):
; planes 0-3 of both targets to 0; plane 4 holds the stars (Logo_stars).
; Outside the table Thalion's way, plus plane 4 of the hidden screen, which
; Thalion's VBL clears ($29B2) before the Amiga shows it, and the shown
; screen converted whole (the white frame of T62).  Registers as free as in
; Thalion's routine.
; ***************************************************************************
Zoom_loeschen:
	move.l	Intro_h5+$1C,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	moveq	#4,d2
	moveq	#HOPOP_NULL,d3
	bsr	Target_fill
	move.l	Intro_h5+$20,d0
	bsr	Schirm_suchen
	beq.b	.aus
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	bsr	Target_fill
.aus:	rts
.thalion:
	move.l	Intro_h5+$1C,a0
	move.l	Intro_h5+$20,a1
	move.w	#200-1,d7
	movem.l	Intro_h5+$12182,d0-d6/a2-a4
.zeile:	movem.l	d0-d6/a2-a4,(a0)
	movem.l	d0-d6/a2-a4,40(a0)
	movem.l	d0-d6/a2-a4,80(a0)
	movem.l	d0-d6/a2-a4,120(a0)
	movem.l	d0-d6/a2-a4,(a1)
	movem.l	d0-d6/a2-a4,40(a1)
	movem.l	d0-d6/a2-a4,80(a1)
	movem.l	d0-d6/a2-a4,120(a1)
	lea	200(a0),a0
	lea	200(a1),a1
	dbf	d7,.zeile
	move.l	Intro_h5+$1C,a0		; plane 4 of the hidden screen
	lea	160(a0),a0
	move.w	#200-1,d7
	moveq	#0,d0
.e4:	moveq	#10-1,d1
.l:	move.l	d0,(a0)+
	dbf	d1,.l
	lea	200-40(a0),a0
	dbf	d7,.e4
	move.l	#-1,Zustand_alt
	bra	Anzeige_umschalten

; ***************************************************************************
; Thalion_vbl_ende -- K3 at Thalion's $2824, the common end of Thalion's
; level-3 VBL ($2522): Thalion's own end ($2824-$2846: the beat if music is
; on, registers back, INTREQ), with our display and then the mixer in
; between, after Thalion's work and before the rte (AMIGA_RAHMEN.S,
; Amiga_vbl).  Replaced is
; tst.w Intro_h5+$12148.
; ***************************************************************************
THALION_VBL	equ	Intro_h0+$2522	; Thalion's level-3 handler

Thalion_vbl_ende:
	tst.w	Intro_h5+$12148		; music on
	beq.b	.ohne
	move.l	Intro_h5,a0		; the player
	jsr	24(a0)
.ohne:	movem.l	(sp)+,d0-d7/a0-a6	; saved by Thalion at $2528
	move.w	#$0020,Amiga_register+$9C	; INTREQ, Thalion's $283A
	movem.l	d0-d7/a0-a6,-(sp)
	bsr	Anzeige_vbl
	bsr	Mischer_vbl		; after the display (Amiga_vbl)
	movem.l	(sp)+,d0-d7/a0-a6
	rte

; ***************************************************************************
; The 4-plane scenes in the target format (docs/11 7.8, T63).  Thalion's
; screens there are 6:$C0 and 6:$C0+37760, 4 planes, 160 bytes a line
; ($42E): 236 lines in the space scene and Twinlake, 200 in the meteor scene
; ($AD4).  From $4F4 (the star list is built) to $D00 (the clouds before the
; menu) they are in Schirm_tabelle, and the Videl shows them directly.
; (Before and after them: the logo phase, the clouds and the menu, below.)
; Thalion's blits find their way themselves (Bl_umlenken).  Thalion's CPU
; writing goes through K3 (tools/amiga_programm.py):
;   - every frame our routine writes the target: clear ($294E), star
;     picture ($1A42), city picture ($776, $B40), Twinlake's animation
;     ($169C), copy shown -> hidden ($12C0), the zoom (INTRO_ZOOM.S);
;   - once per scene Thalion's code writes the buffer between Schirm_vorher
;     and Schirm_nachher: the city's text ($7BA), Twinlake's picture ($994
;     to $A36);
;   - reading: a picture back as mask ($6EE), after Schirm_vorher.
; Outside the table each routine takes Thalion's way.
; ***************************************************************************
RAUM_ZEILE	equ	160		; Thalion's bytes a line in these scenes
STERNE_MAX	equ	4000		; one per non-zero word of plane 0, rows
					; 0-199 ($4C2-$4F4); 146 with the shipped
					; data (the ST's finding 244)

; Raum_anfang -- K3 at $4F4: Thalion has built the star list (5:$3B0) from
; the star picture ($4BC).  Our list for the target, then the table.
; Covered: move.w d2,(a2); moveq #20,d7; the first word of bsr $1250.
Raum_anfang:
	move.w	d2,(a2)
	bsr	Sterne_wandeln
	move.l	a0,-(sp)
	lea	Schirme_raum,a0
	bsr	Schirme_wechseln
	move.l	(sp)+,a0
	moveq	#20,d7
	jsr	Intro_h0+$1250		; its flags hold at $4FC
	jmp	Intro_h0+$4FC

; Meteor_anfang -- K3 at $AD4: the meteor scene shows 200 lines; its table
; ends there, so the lines below are black.  Covered: move.w #200,d0;
; moveq #4,d1.  The picture is held: Thalion writes the 200-line window
; only in $289A, after the table; a VBL between them saw the 236-line
; window against the 200-line table and converted once (Hatari, T66).
Meteor_anfang:
	bsr	Display_hold
	move.l	a0,-(sp)
	lea	Schirme_meteor,a0
	bsr	Schirme_wechseln
	move.l	(sp)+,a0
	move.w	#200,d0
	moveq	#4,d1
	jmp	Intro_h0+$ADA

; Sterne_wandeln -- Thalion's star list (count, then per star the distance
; to the last one in bytes and the word for plane 0) into Ziel_sterne: per
; star the offset in the target screen and the word.
Sterne_wandeln:
	movem.l	d0-d3/d7/a0-a1,-(sp)
	lea	Intro_h5+$3B0,a0
	lea	Ziel_sterne,a1
	move.w	(a0)+,d7
	cmp.w	#STERNE_MAX,d7
	bls.b	.anzahl
	move.w	#STERNE_MAX,d7
.anzahl:
	move.w	d7,(a1)+
	moveq	#0,d1			; Thalion's offset
	bra.b	.n
.s:	add.w	(a0)+,d1
	moveq	#0,d0
	move.w	d1,d0
	divu.w	#RAUM_ZEILE,d0		; line : byte in the line
	moveq	#0,d2
	swap	d0
	move.w	d0,d2
	clr.w	d0
	swap	d0
	mulu.w	#ZIEL_ZEILE,d0
	divu.w	#AMIGA_EBENE,d2		; plane : byte in the plane
	move.w	d2,d3
	add.w	d3,d3			; plane * 2
	add.w	d3,d0
	swap	d2
	lsr.w	#1,d2
	mulu.w	#ZIEL_WORT,d2
	add.w	d2,d0
	move.w	d0,(a1)+
	move.w	(a0)+,(a1)+
.n:	dbf	d7,.s
	movem.l	(sp)+,d0-d3/d7/a0-a1
	rts

; Sterne_setzen -- K3 at $1A42, Thalion's star picture: the words into the
; target.  Covered: movea.l Intro_h5+$18,a1.
Sterne_setzen:
	movem.l	d0-d1/a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	move.l	SCH_ZIEL(a5),a1
	lea	Ziel_sterne,a0
	move.w	(a0)+,d7
	bra.b	.n
.s:	moveq	#0,d0
	move.w	(a0)+,d0
	move.w	(a0)+,0(a1,d0.l)
.n:	dbf	d7,.s
	moveq	#0,d0
	move.w	#200,d1
	bsr	Zeilen_ungueltig
	movem.l	(sp)+,d0-d1/a5
	rts
.thalion:
	movem.l	(sp)+,d0-d1/a5
	move.l	Intro_h5+$18,a1
	jmp	Intro_h0+$1A48

; Raum_loeschen -- K3 at $294E in Thalion's $2940 (clear lines 0-199 of the
; screen Intro_h5+$18; also used for the logo stages, $14E6): the target.
; a6 is Amiga_register (Thalion's lea at $2940).  Covered: move.l
; Intro_h5+$18,$54(a6) (the first 6 of 8 bytes).
Raum_loeschen:
	movem.l	d0-d1/a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	moveq	#0,d0
	move.w	#200,d1
	bsr	Ziel_loeschen
	movem.l	(sp)+,d0-d1/a5
	rts
.thalion:
	movem.l	(sp)+,d0-d1/a5
	move.l	Intro_h5+$18,$54(a6)
	jmp	Intro_h0+$2956

; Stadt_raum / Stadt_meteor -- K3 at $776 and $B40: Thalion copies the city
; picture (a0) into the screen Intro_h5+$18.  Covered: movea.l
; Intro_h5+$18,a1.
Stadt_raum:
	bsr.b	Stadt_ziel
	beq.b	.thalion
	jmp	Intro_h0+$796
.thalion:
	move.l	Intro_h5+$18,a1
	jmp	Intro_h0+$77C
Stadt_meteor:
	bsr.b	Stadt_ziel
	beq.b	.thalion
	jmp	Intro_h0+$B72
.thalion:
	move.l	Intro_h5+$18,a1
	jmp	Intro_h0+$B46

; Stadt_ziel -- the city picture a0 (128 lines, per line four planes of 20
; bytes) into the target at Thalion's place +5770 (line 36, word 5).  Z
; set: the screen is not in the table, nothing done.  Otherwise Z clear and
; a0 behind the picture.  Changes d0-d1/d6-d7/a1-a2.
Stadt_ziel:
	move.l	a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Schirm_suchen
	beq.b	.aus
	moveq	#36,d0
	move.w	#128,d1
	bsr	Zeilen_ungueltig
	move.l	SCH_ZIEL(a5),a1
	add.l	#36*ZIEL_ZEILE+5*ZIEL_WORT,a1
	moveq	#128-1,d7
.zeile:	moveq	#0,d6			; plane * 2
.ebene:	lea	0(a1,d6.w),a2
	moveq	#10-1,d1
.wort:	move.w	(a0)+,(a2)
	lea	ZIEL_WORT(a2),a2
	dbf	d1,.wort
	addq.w	#2,d6
	cmp.w	#4*2,d6
	blo.b	.ebene
	lea	ZIEL_ZEILE(a1),a1
	dbf	d7,.zeile
	moveq	#1,d0			; Z clear
.aus:	move.l	(sp)+,a5
	rts

; Stadt_text -- K3 at $7BA: Thalion's text (big font, $2ADA) into the city
; picture, once per city.  Covered: bsr $2ADA, the first word of bsr $240E.
Stadt_text:
	move.l	d0,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Schirm_vorher
	move.l	(sp)+,d0
	jsr	Intro_h0+$2ADA
	move.l	Intro_h5+$18,d0
	bsr	Schirm_nachher
	jsr	Intro_h0+$240E
	jmp	Intro_h0+$7C2

; Bild_holen -- K3 at $6EE: Thalion takes a piece of the screen back as mask
; and planes ($15A6); it reads the buffer.  Covered: bsr $15A6; move.w
; #-1,(a1)+.
Bild_holen:
	move.l	d0,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Schirm_vorher
	move.l	(sp)+,d0
	jsr	Intro_h0+$15A6
	move.w	#-1,(a1)+
	jmp	Intro_h0+$6F6

; Twinlake_vorher / Twinlake_nachher -- K3 at $994 and $A36: between them
; Thalion copies Twinlake's picture into both screens, clears the lines
; below and writes the text, all with the CPU.  Covered at $994: movea.l
; Intro_h5+$12206,a0; at $A36: bsr $165E, the first word of bsr $240E.
Twinlake_vorher:
	bsr	Alle_sicherstellen
	move.l	Intro_h5+$12206,a0
	jmp	Intro_h0+$99A
Twinlake_nachher:
	bsr	Alle_bringen
	jsr	Intro_h0+$165E
	jsr	Intro_h0+$240E
	jmp	Intro_h0+$A3E

; Anim_eor -- K3 at $169C in Thalion's $165E: the unpacked frame (5:$12206)
; EOR into the screen Intro_h5+$18, lines 7-183, bytes 4-35 of each plane.
; Per line a mask of 32 bits, one per byte; a set bit takes four bytes, one
; per plane.  Covered: movea.l Intro_h5+$12206,a0.
Anim_eor:
	move.l	a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Schirm_suchen
	beq	.thalion
	moveq	#7,d0
	move.w	#177,d1
	bsr	Zeilen_ungueltig
	move.l	Intro_h5+$12206,a0
	move.l	SCH_ZIEL(a5),a1
	add.l	#7*ZIEL_ZEILE+2*ZIEL_WORT,a1
	move.w	#177-1,d7
.zeile:	move.l	(a0)+,d0
	beq.b	.naechste
	move.l	a1,a2
.wort:	add.l	d0,d0			; high byte of the word
	bcc.b	.lo
	move.b	(a0)+,d1
	eor.b	d1,(a2)
	move.b	(a0)+,d1
	eor.b	d1,2(a2)
	move.b	(a0)+,d1
	eor.b	d1,4(a2)
	move.b	(a0)+,d1
	eor.b	d1,6(a2)
.lo:	add.l	d0,d0			; low byte
	bcc.b	.n
	move.b	(a0)+,d1
	eor.b	d1,1(a2)
	move.b	(a0)+,d1
	eor.b	d1,3(a2)
	move.b	(a0)+,d1
	eor.b	d1,5(a2)
	move.b	(a0)+,d1
	eor.b	d1,7(a2)
.n:	lea	ZIEL_WORT(a2),a2
	tst.l	d0
	bne.b	.wort			; the rest of the line is unchanged
.naechste:
	lea	ZIEL_ZEILE(a1),a1
	dbf	d7,.zeile
	move.l	(sp)+,a5
	rts
.thalion:
	move.l	(sp)+,a5
	move.l	Intro_h5+$12206,a0
	jmp	Intro_h0+$16A2

; Kopie_vorn_hinten -- K3 at $12C0: Thalion copies lines 7-183, bytes 4-35
; of each plane, from the shown screen into the hidden one (blit $1306).
; Both in the table: target to target, planes 0-3.  Covered: movea.l
; Intro_h5+$20,a0.
Kopie_vorn_hinten:
	move.l	a5,-(sp)
	move.l	Intro_h5+$20,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	move.l	SCH_ZIEL(a5),a0
	move.l	Intro_h5+$1C,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	move.l	SCH_ZIEL(a5),a1
	moveq	#7,d0
	move.w	#177,d1
	bsr	Zeilen_ungueltig
	move.l	#7*ZIEL_ZEILE+2*ZIEL_WORT,d0
	add.l	d0,a0
	add.l	d0,a1
	move.w	#177-1,d7
.zeile:	move.l	a0,a2
	move.l	a1,a3
	moveq	#16-1,d6
.wort:	move.l	(a2)+,(a3)+		; planes 0-3
	move.l	(a2)+,(a3)+
	addq.l	#ZIEL_WORT-8,a2
	addq.l	#ZIEL_WORT-8,a3
	dbf	d6,.wort
	lea	ZIEL_ZEILE(a0),a0
	lea	ZIEL_ZEILE(a1),a1
	dbf	d7,.zeile
	lea	Amiga_register,a6	; as Thalion's routine leaves it
	move.l	(sp)+,a5
	rts
.thalion:
	move.l	(sp)+,a5
	move.l	Intro_h5+$20,a0
	jmp	Intro_h0+$12C6

; ***************************************************************************
; The logo phase, the clouds and the menu in the target format (E30, docs/11
; 7.8a): the intro without live conversion.  Each scene has its table
; (Screens_logo, Screens_clouds, Screens_menu) and the Videl shows it
; directly; the blits find their way into the target themselves
; (Bl_ziel_waehlen: logo stages $F0, clouds $CA, text $FA/$0A).  Where
; Thalion changes the format of the screens with the CPU (logo -> space at
; $3C0, any scene -> clouds at $D00, clouds -> menu at $F4E), Display_hold
; keeps the last picture on the screen until the next table shows.
; ***************************************************************************
LS_STERNE	equ	150		; Thalion's stars in the logo phase ($1A5C)

; Logo_begin -- K3 at $1E0 (start and restart from the menu's INTRO): the
; logo screens 6:$C0 and +40000, 320 x 200 x 5 ($1A4), into the table
; before the first copper list ($200).  Covered: addi.l #880,d0.
Logo_begin:
	add.l	#880,d0
	movem.l	d0/a0,-(sp)
	bsr	Display_hold
	clr.w	Ls_alt			; no stars set in the new targets
	clr.w	Ls_alt+2+4*LS_STERNE
	lea	Screens_logo,a0
	bsr	Schirme_wechseln
	movem.l	(sp)+,d0/a0
	jmp	Intro_h0+$1E6

; Logo_clear -- K3 at $21E: Thalion clears both screens with the CPU; we
; clear both targets.  Covered: movea.l Intro_h5+$1C,a0.
Logo_clear:
	move.l	Intro_h5+$1C,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	bsr	Ziel_loeschen
	move.l	Intro_h5+$20,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	bsr	Ziel_loeschen
	moveq	#0,d0			; as Thalion's loop leaves them
	moveq	#-1,d7
	jmp	Intro_h0+$23C
.thalion:
	move.l	Intro_h5+$1C,a0
	jmp	Intro_h0+$224

; Logo_stages -- K3 at $14E6, the start of Thalion's precomputation of the
; logo stages: Thalion clears the drawing screen ($2940), zooms the logo
; into it ($1BAE) and reads it back ($1560), each as 4 planes of 160 bytes,
; a scratch use of the hidden screen.  We give it a scratch screen of its
; own, so the hidden screen stays in the target format.  Covered: bsr
; $2940, the first word of movea.l Intro_h5+$12206,a1.
Logo_stages:
	move.l	Intro_h5+$18,-(sp)
	move.l	#Logo_scratch,Intro_h5+$18
	jsr	Intro_h0+$2940
	move.l	Intro_h5+$12206,a1
	jsr	Intro_h0+$14F0		; the rest of Thalion's routine
	move.l	(sp)+,Intro_h5+$18
	rts

; Logo_stars -- K3 at $2646 in Thalion's VBL: the stars ($29B2 clears plane
; 4 of the shown screen, $1AF2 sets 150 stars there).  Shown screen in the
; table: the words set last time on this screen to 0, then Thalion's walk
; ($1AF2: Thalion's track pointers at 5:$2C advance as there) with the
; target address: Thalion's offset is line * 200 + byte in plane 0, the
; star goes into plane 4.  Thalion saved all registers ($2528).  Covered:
; move.l Intro_h5+$18,-(sp).
Logo_stars:
	move.l	Intro_h5+$20,d0
	bsr	Schirm_suchen
	beq	.thalion
	lea	Ls_alt,a2		; per screen: count, then the words
	cmp.l	#Schirm_tabelle,a5
	beq.b	.s0
	lea	Ls_alt+2+4*LS_STERNE,a2
.s0:	move.w	(a2)+,d7
	move.l	a2,a3
	bra.b	.cn
.c:	move.l	(a3)+,a0
	clr.w	(a0)
.cn:	dbf	d7,.c
	move.l	SCH_ZIEL(a5),a6
	addq.l	#4*2,a6			; plane 4
	lea	Intro_h5+$2C,a4
	move.l	a2,a3
	move.w	#LS_STERNE-1,d7
.s:	move.l	(a4),a0
	move.w	(a0)+,d0		; bit in the byte
	bpl.b	.da
	move.l	(a0)+,a0		; end of the track: from its start
	move.w	(a0)+,d0
.da:	moveq	#0,d1
	move.w	(a0)+,d1
	move.l	a0,(a4)+
	divu.w	#200,d1			; line : byte
	moveq	#0,d2
	swap	d1
	move.w	d1,d2			; byte
	clr.w	d1
	swap	d1
	mulu.w	#ZIEL_ZEILE,d1
	btst	#0,d2
	bne.b	.lo
	addq.w	#8,d0			; even byte: the high byte of the word
.lo:	lsr.w	#1,d2
	mulu.w	#ZIEL_WORT,d2
	add.l	d2,d1
	lea	0(a6,d1.l),a0
	moveq	#0,d1
	bset	d0,d1
	or.w	d1,(a0)
	move.l	a0,(a3)+
	dbf	d7,.s
	move.w	#LS_STERNE,-2(a2)
	jmp	Intro_h0+$2664
.thalion:
	move.l	Intro_h5+$18,-(sp)
	jmp	Intro_h0+$264C

; Presents_row -- K3 at $310, the start of a row of Thalion's wipe ($2FC-
; $324): 40 bytes of "PRESENTS" (a0) into plane 0 of a line of the shown
; screen (a1).  Into the buffer as Thalion does, and into the target; the
; line's other planes stay.  Covered: moveq #9,d0; move.l (a0)+,(a1)+; the
; first word of dbf d0.
Presents_row:
	movem.l	d1-d3/a2-a3/a5,-(sp)
	move.l	a1,d0
	bsr	Schirm_suchen
	beq.b	.puffer
	move.l	a1,d1			; line : byte in the line
	sub.l	SCH_AMIGA(a5),d1
	divu.w	SCH_BPR(a5),d1
	moveq	#0,d2
	swap	d1
	move.w	d1,d2
	clr.w	d1
	swap	d1
	mulu.w	#ZIEL_ZEILE,d1
	divu.w	#AMIGA_EBENE,d2		; plane : byte in the plane
	move.w	d2,d3
	add.w	d3,d3
	add.w	d3,d1			; plane * 2
	swap	d2
	lsr.w	#1,d2
	mulu.w	#ZIEL_WORT,d2
	add.l	d2,d1
	move.l	SCH_ZIEL(a5),a3
	add.l	d1,a3
	move.l	a0,a2
	moveq	#AMIGA_WORTE-1,d3
.z:	move.w	(a2)+,(a3)
	lea	ZIEL_WORT(a3),a3
	dbf	d3,.z
.puffer:
	moveq	#10-1,d3
.p:	move.l	(a0)+,(a1)+
	dbf	d3,.p
	movem.l	(sp)+,d1-d3/a2-a3/a5
	move.l	#$FFFF,d0		; as Thalion's dbf leaves it
	jmp	Intro_h0+$318

; Logo_end -- K3 at $3C0: the stars stand still ($3B6), and Thalion turns
; the shown picture into the space scene's first one with the CPU ($3C0-
; $4BC: copy, 5 -> 4 planes, the star list from plane 0).  The stars live
; only in the target (Logo_stars): all lines of the shown screen into its
; buffer, then hold the display (no table) until Raum_anfang ($4F4) brings
; the space scene's.  Covered: movea.l Intro_h5+$20,a0.
Logo_end:
	move.l	Intro_h5+$20,d0
	bsr	Schirm_suchen
	beq.b	.halten
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	bsr	Zeilen_holen
.halten:
	bsr	Display_hold
	move.l	Intro_h5+$20,a0
	jmp	Intro_h0+$3C6

; Clouds_begin -- K3 at $D00, where every way to the clouds and the menu
; passes (also the click): hold the picture, then the clouds' screens 6:$C0
; and +40960, 320 x 256 x 4 ($D10), into the table.  Covered: move.w
; #256,d0; moveq #4,d1.
Clouds_begin:
	move.l	a0,-(sp)
	bsr	Display_hold
	lea	Screens_clouds,a0
	bsr	Schirme_wechseln
	move.l	(sp)+,a0
	move.w	#256,d0
	moveq	#4,d1
	jmp	Intro_h0+$D06

; Clouds_background -- K3 at $D74 (the click: no clouds): Thalion copies the
; unpacked menu picture into both screens with the CPU; then into the
; targets.  Covered: movea.l Intro_h5+$12206,a0.
Clouds_background:
	move.l	Intro_h5+$12206,a0
	move.l	Intro_h5+$1C,a1
	move.l	Intro_h5+$20,a2
	moveq	#-1,d0
	move.w	#10240-1,d7
.k:	move.l	(a0),(a1)+
	move.l	(a0)+,(a2)+
	dbf	d7,.k
	bsr	Alle_bringen
	jmp	Intro_h0+$D94

; Clouds_fill -- K3 at $DA2: Thalion fills both screens with colour 15 with
; the CPU; we fill both targets.  Covered: movea.l Intro_h5+$1C,a1.
Clouds_fill:
	move.l	Intro_h5+$1C,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	moveq	#4,d2
	moveq	#HOPOP_EINS,d3
	bsr	Target_fill
	move.l	Intro_h5+$20,d0
	bsr	Schirm_suchen
	beq.b	.thalion
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	bsr	Target_fill
	moveq	#-1,d0			; as Thalion's loop leaves them
	moveq	#-1,d7
	jmp	Intro_h0+$DBC
.thalion:
	move.l	Intro_h5+$1C,a1
	jmp	Intro_h0+$DA8

; Clouds_column -- K3 at $1270, the whole routine: Thalion reveals the menu
; picture column by column, d2 words from word d0 on, all 256 lines and 4
; planes (one blit of 1024 rows), from the unpacked picture (Intro_h5+
; $12206, Thalion's format) into the drawing screen.  In the table: the
; Falcon blitter, one blit per plane, straight into the target.  All
; registers are preserved, a6 = Amiga_register as Thalion leaves it.
; Covered: movea.l Intro_h5+$12206,a0.
Clouds_column:
	movem.l	d0-d7/a0-a5,-(sp)
	move.l	Intro_h5+$18,d0
	bsr	Schirm_suchen
	beq	.thalion
	movem.l	(sp),d0-d2
	move.l	Intro_h5+$12206,a0
	add.w	d0,a0
	add.w	d0,a0			; + 2 * word
	move.l	SCH_ZIEL(a5),a1
	lsl.w	#4,d0
	add.w	d0,a1			; + ZIEL_WORT * word
	move.w	sr,-(sp)
	or.w	#$0400,sr		; the VBL uses the blitter too
	moveq	#-1,d7
	move.w	d7,BL_MASKE1
	move.w	d7,BL_MASKE2
	move.w	d7,BL_MASKE3
	move.w	#2,BL_SRC_XINC
	move.w	d2,d0
	subq.w	#1,d0
	add.w	d0,d0			; (words - 1) * 2
	move.w	#4*AMIGA_EBENE,d1
	sub.w	d0,d1
	move.w	d1,BL_SRC_YINC		; to the next line, same plane
	move.w	#ZIEL_WORT,BL_DST_XINC
	lsl.w	#3,d0			; (words - 1) * ZIEL_WORT
	move.w	#ZIEL_ZEILE,d1
	sub.w	d0,d1
	move.w	d1,BL_DST_YINC
	move.w	#HOPOP_KOPIE,BL_HOPOP
	clr.b	BL_SKEW
	moveq	#4-1,d6			; planes
.eb:	move.w	d2,BL_XCOUNT
	move.l	a0,BL_SRC
	move.l	a1,BL_DST
	move.w	SCH_ZEILEN(a5),BL_YCOUNT
	bsr	Blit_starten
	lea	AMIGA_EBENE(a0),a0
	addq.l	#2,a1
	dbf	d6,.eb
	move.w	(sp)+,sr
	moveq	#0,d0
	move.w	SCH_ZEILEN(a5),d1
	bsr	Zeilen_ungueltig
	movem.l	(sp)+,d0-d7/a0-a5
	lea	Amiga_register,a6
	rts
.thalion:
	movem.l	(sp)+,d0-d7/a0-a5
	move.l	Intro_h5+$12206,a0
	jmp	Intro_h0+$1276

; Menu_hold -- K3 at $F4E: the clouds are open, the menu picture is shown.
; Thalion now makes the menu's screens with the CPU ($F6C: 4 -> 5 planes
; into 6:$C8C0, $FB2: copied into 6:$C0): hold the picture.  Covered:
; move.l #Intro_h6+$C8C0,d0.
Menu_hold:
	bsr	Display_hold
	move.l	#Intro_h6+$C8C0,d0
	jmp	Intro_h0+$F54

; Menu_begin -- K3 at $FB2: Thalion's copy of the shown menu screen into the
; other one, then both into the table (6:$C8C0 and 6:$C0, 320 x 256 x 5).
; From here Thalion's menu draws into the shown screen: the entries with
; the CPU (Menu_texts), the highlight by blits.  Covered: movea.l
; Intro_h5+$20,a0.
Menu_begin:
	move.l	Intro_h5+$20,a0
	move.l	Intro_h5+$1C,a1
	move.w	#12800-1,d7
.k:	move.l	(a0)+,(a1)+
	dbf	d7,.k
	move.l	a0,-(sp)
	lea	Screens_menu,a0
	bsr	Schirme_wechseln
	move.l	(sp)+,a0
	jmp	Intro_h0+$FC8

; Menu_texts -- K3 at $1030: Thalion has written the menu's entries into
; plane 4 of the shown screen with the CPU ($FE6-$102C): into the target.
; Covered: lea Intro_h1+$180,a4.
Menu_texts:
	move.l	Intro_h5+$20,d0
	bsr	Schirm_nachher
	lea	Intro_h1+$180,a4
	jmp	Intro_h0+$1036

	include	"AMIGA_RAHMEN.S"
	include	"INTRO_ZOOM.S"

; ***************************************************************************
; Daten
; ***************************************************************************
	SECTION	Intro_daten,data
; Der Satz, den der Amiga-Lader in a0 uebergibt (docs/11, 4.2): Zeiger auf
; den Musikspieler, dann das Merkerbyte (0: Intro zeigen, kein
; WEITERSPIELEN; setzt start aus der Befehlszeile des Laders).
Uebergabe:
	dc.l	Musik_stumm
	dc.b	0
	even
; Screens in the target format (docs/11 7.8): none at the start; the
; 4-plane scenes bring their table (Schirme_wechseln), room for SCH_MAX.
Schirm_tabelle:
	dcb.b	SCH_MAX*SCH_LAENGE+4,0
; Thalion's screens of the space scene and Twinlake ($42E): 320 x 236 x 4
Schirme_raum:
	SCHIRM	Intro_h6+$C0,236,4
	SCHIRM	Intro_h6+$C0+37760,236,4
	dc.l	0
; the same in the meteor scene, which shows 200 lines ($AD4)
Schirme_meteor:
	SCHIRM	Intro_h6+$C0,200,4
	SCHIRM	Intro_h6+$C0+37760,200,4
	dc.l	0
; the logo phase: 320 x 200 x 5 ($194-$1BC)
Screens_logo:
	SCHIRM	Intro_h6+$C0,200,5
	SCHIRM	Intro_h6+$C0+40000,200,5
	dc.l	0
; the clouds before the menu: 320 x 256 x 4 ($D06-$D28)
Screens_clouds:
	SCHIRM	Intro_h6+$C0,256,4
	SCHIRM	Intro_h6+$C0+40960,256,4
	dc.l	0
; the menu: 320 x 256 x 5 ($F4E, $F98-$FAE)
Screens_menu:
	SCHIRM	Intro_h6+$C0,256,5
	SCHIRM	Intro_h6+$C8C0,256,5
	dc.l	0
	include	"amiga_rahmen_daten.i"
	include	"intro_musik.i"	; build: tools/musik_k1.py
Musik_datei:
	dc.b	"AMBFILES\INTROMUS.DAT",0
	even
	include	"intro_zoom_daten.i"

; ***************************************************************************
	SECTION	Intro_bss,bss
	include	"amiga_rahmen_bss.i"
	include	"intro_zoom_bss.i"
Ziel_sterne:	ds.w	1+2*STERNE_MAX	; count, per star offset and word
Ls_alt:		ds.w	2*(1+2*LS_STERNE)	; per logo screen: count, the
					; words of its stars (Logo_stars)
Logo_scratch:	ds.b	200*RAUM_ZEILE	; Logo_stages

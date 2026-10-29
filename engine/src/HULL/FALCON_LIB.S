; HULL/FALCON_LIB.S -- the Falcon part of the drawing library
;
; Owner: Falcon Tempo (CLAUDE.md, sessions).  Falcon build only: engine.s
; includes it right after LIBRARY.S, so both reach each other with bsr.
;
; LIBRARY.S keeps Thalion's names, the contracts and what both machines
; share (clipping, addresses, the screen format, the pointer); this file
; holds what knows colour banks and eight planes.  The ST counterpart is
; ST_LIB.S.  Library split phase 1 (user, 2026-10-21; docs/developer/05,
; "LIBRARY.S by machine"): the code moved here unchanged; only the seams
; are new (rts instead of a branch back, an own prologue in
; Get_block_orig, the entry label Masked_icon).
;
; Entry points, each called from its routine in LIBRARY.S:
;   Pub_zeilen        Put_unmasked_block, source in Thalion's format
;   Box_fuellen       Draw_box, the fill
;   Quelle_aufweiten  Put_masked_block2, source in Thalion's format
;   Zeilenfarbe       Put_char_at, Put_masked_silhouette
;   Get_block_orig    Get_block, destination in Thalion's format
;   Masked_icon       Put_masked_icon
;   Kachel_holen      the tile cache, for Pub_zeilen and Masked_icon
; Phase 2 (2026-10-23; ST_LIB.S has the same names):
;   Bloecke_nacharbeiten  the block routines, R_range afterwork
;   Zeichen_nacharbeiten  Put_char_at, R_range afterwork
;   Unmasked_icon     Put_unmasked_icon first: nothing yet, straight back
;   Pm2_schnell       Put_masked_block2 first: nothing yet, C set
;   Zeiger_bild       Zeiger_in_puffer first: nothing to do
; Bereich_nacharbeiten, Bereich_rueck (RASTER.S) and Drogen_setzen,
; Drogen_farben (below) are called from LIBRARY.S under their own
; names; the ST has empty ones in ST_LIB.S.
; Phase 3 (2026-10-24; ST_LIB.S has the same names):
;   Pointer_convert   Set_mouse_ptr (AREAS.S), the pointer to eight planes
;   Platz_setzen, Bank0_setzen, Bank_setzen, Palette_anfang  the colour
;                     banks of Set_fade (FADE_SUP.S); Drogen_farben,
;                     Drogen_setzen  Drugged_FX (Vid_stufe stays in
;                     FADE_SUP.S: RASTER.S takes it on both machines)
; Bereiche_sammeln, Bereiche_schritt (RASTER.S) are called from Set_fade;
; the ST has stubs in ST_LIB.S.
; The colour-bank routines (Farbbank, Farbbank_spanne, Rasterbank*,
; Zeichenliste) stay in LIBRARY.S for now: the ST build calls them too.

	IFNE	PLANES-8
	FAIL	"FALCON_LIB.S is for the Falcon build (PLANES = 8)"
	ENDC

	SECTION	Program,code

; ***************************************************************************
; Pub_zeilen -- the lines of Put_unmasked_block for a source in Thalion's
; format (d5 < SCHIRM_FORMAT): eight planes, the bank of each line.
;   IN : as Put_unmasked_block leaves them: a0 = first visible source
;        block, a1 = first visible target block, a2 = first line, d4 =
;        colour offset, d5 = planes of the source, d6 = source width in
;        blocks, d7 = lines - 1 (upper word: the offset bits from d5 up),
;        bl_anzahl = visible blocks.  The caller saves the registers.
; ***************************************************************************
Pub_zeilen:
	; ---- Tempo: eine ganze Kachel (ein Block, sechzehn Zeilen, Amiga-
	; Format, eine Bank) kommt fertig aus dem Kachelspeicher ----
	cmp.w	#1,d6
	bne.b	pub_ohne_kachel
	cmp.w	#1,bl_anzahl
	bne.b	pub_ohne_kachel
	cmp.w	#16-1,d7
	bne.b	pub_ohne_kachel
	move.w	d5,d0
	subq.w	#1,d0
	cmp.w	#Data_depth-1,d0
	bhi.b	pub_ohne_kachel		; keine oder mehr als fuenf Ebenen
	move.w	a2,d0
	bsr	Farbbank_spanne
	move.w	a2,d2
	add.w	#16,d2
	bcs.b	pub_ohne_kachel
	cmp.w	d1,d2
	bhi.b	pub_ohne_kachel		; die Bank wechselt in der Kachel
	moveq	#-1,d2			; Versatzbits ab d5, dazu die Bank
	lsl.w	d5,d2
	and.w	#(1<<Data_depth)-1,d2
	and.w	d2,d4
	or.w	d0,d4
	bsr	Kachel_holen		; a3 = Eintrag
	lea	KC_BILD(a3),a3
	moveq	#16-1,d7
pub_kachel:
	move.l	(a3)+,(a1)+
	move.l	(a3)+,(a1)+
	move.l	(a3)+,(a1)+
	move.l	(a3)+,(a1)
	lea	SCRROW-12(a1),a1
	dbf	d7,pub_kachel
	rts
pub_ohne_kachel:
	clr.w	pub_grenze		; die erste Zeile fragt immer

pub_row:
	; ---- Farbe dieser Zeile: Bank + Versatzbits, nach d4.  Neu gefragt
	; wird erst an der Grenze der Bank (Farbbank_spanne) ----
	move.w	a2,d0
	cmp.w	pub_grenze,d0
	bcs.b	pub_bank_gilt
	bsr	Farbbank_spanne
	move.w	d1,pub_grenze
	move.l	d7,d4
	swap	d4
	or.w	d0,d4
pub_bank_gilt:
	addq.w	#1,a2

	; ---- Maske "Quellwert ungleich null" fuer diese Zeile bilden ----
	;
	; **Der Farbversatz gilt nur fuer Farbe ungleich null.**  Am
	; Amiga-Speicherauszug nachgemessen (tools/falcon_gfx.py): Layoutwert 3
	; erscheint als 27, 7 als 31, 5 als 29 -- aber 0 bleibt 0.  Deckend heisst
	; also nicht "Farbe 0 wird mitversetzt": die Null bleibt die Null, und nur
	; alles darueber wandert in den Palettenabschnitt.
	;
	; Planar heisst das: die Maske ist das ODER aller Quellebenen, und die
	; Ebenen oberhalb der Quelle bekommen diese Maske statt einer vollen Eins.
	lea	pub_nz,a3
	move.w	bl_anzahl,d2
	subq.w	#1,d2
pub_nzclr:
	clr.w	(a3)+
	dbf	d2,pub_nzclr
	moveq	#0,d3
pub_nzpl:
	move.l	a0,a4
	move.w	d3,d1
	mulu.w	d6,d1
	add.l	d1,a4
	add.l	d1,a4			; Quellebene d3 dieser Zeile
	lea	pub_nz,a3
	move.w	bl_anzahl,d2
	subq.w	#1,d2
pub_nzw:
	move.w	(a4)+,d1
	or.w	d1,(a3)+
	dbf	d2,pub_nzw
	addq.w	#1,d3
	cmp.w	d5,d3
	blo.b	pub_nzpl

	; ---- Ebene fuer Ebene ins Ziel ----
	moveq	#0,d3
pub_pl:
	move.l	a1,a4
	move.w	d3,d1
	add.w	d1,d1
	add.w	d1,a4			; Ziel = Zeilenanfang + Ebene*2
	cmp.w	d5,d3
	bcc.b	pub_hoch
	; Ebene aus der Quelle; die Plane-Zeilen liegen hintereinander
	move.l	a0,a3
	move.w	d3,d1
	mulu.w	d6,d1
	add.l	d1,a3
	add.l	d1,a3
	move.w	bl_anzahl,d2
	subq.w	#1,d2
pub_kop:
	move.w	(a3)+,(a4)
	lea	PLANES*2(a4),a4		; im Ziel liegt je Block eine Ebenengruppe
	dbf	d2,pub_kop
	bra.b	pub_plnext
pub_hoch:
	; Ebene oberhalb der Quelle: gesetzt, wo die Farbe der Zeile dieses
	; Bit traegt *und* der Punkt nicht Farbe null ist.
	btst	d3,d4
	beq.b	pub_leer
	lea	pub_nz,a3
	move.w	bl_anzahl,d2
	subq.w	#1,d2
pub_maske:
	move.w	(a3)+,(a4)
	lea	PLANES*2(a4),a4
	dbf	d2,pub_maske
	bra.b	pub_plnext
pub_leer:
	move.w	bl_anzahl,d2
	subq.w	#1,d2
pub_null:
	clr.w	(a4)
	lea	PLANES*2(a4),a4
	dbf	d2,pub_null
pub_plnext:
	addq.w	#1,d3
	cmp.w	#PLANES,d3
	blo.b	pub_pl
	move.w	d5,d1			; eine Quellzeile = d5 Ebenen * d6 Bloecke
	mulu.w	d6,d1
	add.l	d1,a0
	add.l	d1,a0
	lea	SCRROW(a1),a1
	dbf	d7,pub_row
	rts

; ***************************************************************************
; Box_fuellen -- the fill of Draw_box, line by line with the bank per span.
;   IN : as Draw_box leaves them: a0 = first block of the first line, a2 =
;        first line, a3 = Thalion's colour, d0 = offset in the first block,
;        d2 = width in pixels, d3 = lines - 1.  The caller saves the
;        registers.
; ***************************************************************************
Box_fuellen:
	clr.w	fb_grenze		; die erste Zeile fragt immer
fb_row:
	; ---- Farbe dieser Zeile, dieselbe Regel wie Zeilenfarbe (0 bleibt 0,
	; ab 32 fertig, sonst mit der Bank).  Neu gefragt wird erst an der
	; Grenze der Bank (Farbbank_spanne, Erkenntnis 271) ----
	move.w	a2,d1
	cmp.w	fb_grenze,d1
	bcs.b	fb_farbe_gilt
	move.l	d0,-(sp)
	move.w	a2,d0
	bsr	Farbbank_spanne
	move.w	d1,fb_grenze
	move.w	a3,d4
	beq.b	fb_farbe_fertig		; 0 bleibt 0
	cmp.w	#1<<Data_depth,d4
	bcc.b	fb_farbe_fertig		; schon eine Schirmfarbe
	or.w	d0,d4
fb_farbe_fertig:
	move.l	(sp)+,d0
fb_farbe_gilt:
	addq.w	#1,a2
	move.l	a0,a1
	move.w	d2,d6			; verbleibende Pixel
	move.w	d0,d7			; Versatz im ersten Block
fb_blk:
	move.w	#$FFFF,d5		; Maske der betroffenen Pixel
	lsr.w	d7,d5
	move.w	d6,d1
	add.w	d7,d1
	cmp.w	#16,d1
	bcc.b	fb_full
	move.w	#$FFFF,d1
	move.w	d6,d5
	add.w	d7,d5
	sub.w	#16,d5
	neg.w	d5
	lsl.w	d5,d1
	move.w	#$FFFF,d5
	lsr.w	d7,d5
	and.w	d1,d5
fb_full:
	movem.l	d2/d6/a1,-(sp)
	moveq	#0,d1			; Ebene
fb_pl:	move.w	(a1),d2
	move.w	d5,d6
	not.w	d6
	and.w	d6,d2			; Pixel freiraeumen
	btst	d1,d4
	beq.b	fb_zero
	or.w	d5,d2
fb_zero:
	move.w	d2,(a1)+
	addq.w	#1,d1
	cmp.w	#PLANES,d1
	bne.b	fb_pl
	movem.l	(sp)+,d2/d6/a1
	lea	TROW(a1),a1
	move.w	#16,d1
	sub.w	d7,d1			; in diesem Block erledigt
	sub.w	d1,d6
	moveq	#0,d7
	tst.w	d6
	bgt.b	fb_blk
	lea	SCRROW(a0),a0
	dbf	d3,fb_row
	rts

	SECTION	Fast_BSS,bss
	even
pub_nz:		ds.w	64		; je Block ein Wort: wo ist die Farbe nicht null
pub_grenze:	ds.w	1		; ab dieser Zeile die Bank neu fragen
fb_grenze:	ds.w	1		; Draw_box: ab dieser Zeile die Bank neu fragen
	SECTION	Program,code

; ***************************************************************************
; Quelle_aufweiten -- eine Originalgrafik mit d5 < PLANES Ebenen ins Schirmformat.
;
;   IN : a0 = Quelle, zeilenverschachtelt (je Bildzeile d5 Plane-Zeilen zu
;             d6 Worten), d1 = Y, d4 = Farbversatz, d5 = Ebenen,
;             d6 = Bloecke, d7 = Zeilen
;   OUT: a0 = pmo_puffer (acht Ebenen, wortverzahnt) oder 0, wenn es nicht
;             hineinpasst.  Alle uebrigen Register bleiben.
;
; Je Bildzeile wird die Farbe neu bestimmt: Farbbank(y) ODER Versatzbits.
; Eine Grafik ueber der Grenze zweier Rasterbereiche bekaeme so oben und
; unten die richtige Bank.  Die Ebenen unter d5 kommen aus der Quelle, jede
; hoehere traegt die Maske "Quellwert ungleich null", wo die Farbe ihr Bit
; hat, sonst null.
;
; Die Versatzbits liegen im oberen Wort von d7; dbf zaehlt nur das untere.
; ***************************************************************************
Quelle_aufweiten:
	movem.l	d0-d7/a1-a4,-(sp)	; a0 ist das Ergebnis und bleibt draussen
	move.w	d6,d0
	mulu.w	d7,d0
	mulu.w	#TROW,d0
	cmp.l	#PMO_MAX,d0
	bhi	pmo_zuviel
	; ---- Versatzbits: nur die von d5 bis zur Amiga-Tiefe ----
	moveq	#-1,d0
	lsl.w	d5,d0
	and.w	#(1<<Data_depth)-1,d0
	and.w	d4,d0
	swap	d7
	move.w	d0,d7
	swap	d7
	move.w	d6,d0			; Abstand zweier Plane-Zeilen
	add.w	d0,d0
	ext.l	d0
	move.l	d0,a4
	lea	pmo_puffer,a1
	subq.w	#1,d7
	bmi	pmo_fertig
pmo_zeile:
	move.w	d1,d0			; Farbe dieser Zeile
	bsr	Farbbank
	move.l	d7,d3
	swap	d3
	or.w	d0,d3			; d3 = Bank + Versatzbits
	move.l	a0,a3			; Block 0, Ebene 0
	move.w	d6,d4
	subq.w	#1,d4
pmo_block:
	; ---- Maske "Quellwert ungleich null" dieses Blocks ----
	moveq	#0,d0
	move.l	a3,a2
	move.w	d5,d2
	subq.w	#1,d2
pmo_msk:
	or.w	(a2),d0
	add.l	a4,a2
	dbf	d2,pmo_msk
	; ---- die Quellebenen ----
	move.l	a3,a2
	moveq	#0,d2
pmo_tief:
	move.w	(a2),(a1)+
	add.l	a4,a2
	addq.w	#1,d2
	cmp.w	d5,d2
	blo.b	pmo_tief
	; ---- die Ebenen darueber ----
pmo_hoch:
	btst	d2,d3
	beq.b	pmo_null
	move.w	d0,(a1)+
	bra.b	pmo_weiter
pmo_null:
	clr.w	(a1)+
pmo_weiter:
	addq.w	#1,d2
	cmp.w	#PLANES,d2
	blo.b	pmo_hoch
	addq.l	#2,a3			; naechster Block
	dbf	d4,pmo_block
	move.w	d5,d0			; naechste Quellzeile: d5 Plane-Zeilen weiter
	mulu.w	d6,d0
	add.l	d0,a0
	add.l	d0,a0
	addq.w	#1,d1
	dbf	d7,pmo_zeile
pmo_fertig:
	lea	pmo_puffer,a0
	bra.b	pmo_out
pmo_zuviel:
	sub.l	a0,a0
pmo_out:
	movem.l	(sp)+,d0-d7/a1-a4
	rts

; ***************************************************************************
; Zeilenfarbe -- the Falcon version: the bank of the line.  Contract in
; LIBRARY.S.
; ***************************************************************************
Zeilenfarbe:
	tst.w	d1
	beq.b	zf_out			; 0 bleibt 0
	cmp.w	#1<<Data_depth,d1
	bcc.b	zf_out			; schon eine Schirmfarbe
	move.l	d0,-(sp)
	bsr	Farbbank
	or.w	d0,d1
	move.l	(sp)+,d0
zf_out:
	rts

; ***************************************************************************
; Get_block_orig -- Get_block with a destination in Thalion's format (d5 <
; SCHIRM_FORMAT): the lower d5 planes, line by line, in each line plane by
; plane.  Contract in LIBRARY.S; Get_block jumps here with its registers.
; ***************************************************************************
Get_block_orig:
	movem.l	d0-d7/a0-a2,-(sp)
	lsr.w	#4,d0			; Blocknummer
	move.l	Work_screen,a1
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	mulu.w	#TROW,d0
	add.l	d0,a1
	subq.w	#1,d7
	bmi.b	gbo_out
gb_orig:
	moveq	#0,d3			; Ebene
gb_opl:
	move.w	d3,d2
	add.w	d2,d2			; Ebene * 2 = Versatz im Block
	lea	0(a1,d2.w),a2
	move.w	d6,d4
	subq.w	#1,d4
	bmi.b	gb_onext
gb_ocol:
	move.w	(a2),(a0)+
	lea	TROW(a2),a2
	dbf	d4,gb_ocol
	addq.w	#1,d3
	cmp.w	d5,d3
	blo.b	gb_opl
gb_onext:
	add.l	#SCRROW,a1
	dbf	d7,gb_orig
gbo_out:
	movem.l	(sp)+,d0-d7/a0-a2
	jsr	Bereich_rueck		; R_range: Platz -> Bank + Verlaufsfarbe
	rts

; ***************************************************************************
; Masked_icon -- Put_masked_icon on the Falcon.  Contract and method in
; LIBRARY.S.
; ***************************************************************************
Masked_icon:
	movem.l	d0-d7/a0-a3,-(sp)
	move.w	d1,a3			; Bildzeile, fuer die Farbbank
	lsr.w	#4,d0			; Blocknummer
	move.l	Work_screen,a1
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	mulu.w	#TROW,d0
	add.l	d0,a1
	; ---- Tempo: mit einer Bank ueber alle sechzehn Zeilen kommt die
	; Kachel samt Maske fertig aus dem Kachelspeicher ----
	move.w	d5,d0
	subq.w	#1,d0
	cmp.w	#Data_depth-1,d0
	bhi.b	pmi_live		; keine oder mehr als fuenf Ebenen
	move.w	a3,d0
	bsr	Farbbank_spanne
	move.w	a3,d2
	add.w	#16,d2
	bcs.b	pmi_live
	cmp.w	d1,d2
	bhi.b	pmi_live		; die Bank wechselt in der Kachel
	or.w	d4,d0			; Farbbasis wie unten: d4 oder Bank,
	moveq	#-1,d2			; nur die Ebenen ab d5
	lsl.w	d5,d2
	and.w	#(1<<PLANES)-1,d2
	and.w	d2,d0
	move.w	d0,d4
	bsr	Kachel_holen		; a3 = Eintrag
	lea	KC_MASKE(a3),a2
	lea	KC_BILD(a3),a3
	moveq	#16-1,d7
pmi_kachel:
	move.w	(a2)+,d6		; Gegenmaske, in beide Haelften
	not.w	d6
	move.w	d6,d5
	swap	d6
	move.w	d5,d6
	movem.l	(a3)+,d0-d3		; acht Ebenenworte
	and.l	d6,(a1)
	or.l	d0,(a1)+
	and.l	d6,(a1)
	or.l	d1,(a1)+
	and.l	d6,(a1)
	or.l	d2,(a1)+
	and.l	d6,(a1)
	or.l	d3,(a1)
	lea	SCRROW-12(a1),a1
	dbf	d7,pmi_kachel
	bra	pmi_out
pmi_live:
	clr.w	pmi_grenze		; die erste Zeile fragt immer
	move.w	#16-1,d7		; sechzehn Zeilen
pmi_row:
	; ---- Maske: Oder aller Quellebenen ----
	moveq	#0,d2
	move.l	a0,a2
	move.w	d5,d6
	subq.w	#1,d6
	bmi.b	pmi_keine
pmi_msk:
	or.w	(a2)+,d2
	dbf	d6,pmi_msk
pmi_keine:
	move.w	d2,d3
	not.w	d3			; Gegenmaske
	; ---- acht Zielebenen fuellen ----
	move.l	a1,a2
	move.w	a3,d0			; Bank dieser Zeile, neu gefragt erst
	cmp.w	pmi_grenze,d0		; an ihrer Grenze (Farbbank_spanne)
	bcs.b	pmi_bank_gilt
	bsr	Farbbank_spanne
	move.w	d1,pmi_grenze
	move.w	d0,pmi_bank
pmi_bank_gilt:
	move.w	pmi_bank,d0
	or.w	d4,d0
	move.w	d0,d6			; Farbbasis, wird durchgeschoben
	moveq	#0,d1			; Ebenennummer
pmi_pl:
	cmp.w	d5,d1			; gibt es diese Quellebene?
	bcc.b	pmi_keine_quelle
	move.w	d1,d0
	add.w	d0,d0
	move.w	(a0,d0.w),d0		; ja: nur die Quelle, kein Farbbit
	bra.b	pmi_kein_farbbit
pmi_keine_quelle:
	moveq	#0,d0
	btst	#0,d6			; Farbbit dieser Ebene gesetzt?
	beq.b	pmi_kein_farbbit
	move.w	d2,d0			; dann die ganze Maske
pmi_kein_farbbit:
	and.w	d3,(a2)			; freiraeumen
	or.w	d0,(a2)+		; und setzen
	lsr.w	#1,d6
	addq.w	#1,d1
	cmp.w	#PLANES,d1
	blo.b	pmi_pl
	; ---- naechste Zeile ----
	move.w	d5,d0
	add.w	d0,d0			; d5 Woerter je Quellzeile
	add.l	d0,a0
	add.l	#SCRROW,a1
	addq.w	#1,a3
	dbf	d7,pmi_row
pmi_out:
	movem.l	(sp)+,d0-d7/a0-a3
	movem.l	d6-d7,-(sp)		; R_range: Verlaufsfarbe -> Platz
	moveq	#1,d6
	moveq	#16,d7
	bsr	Bloecke_nacharbeiten
	movem.l	(sp)+,d6-d7
	rts

	SECTION	Fast_BSS,bss
pmi_grenze:	ds.w	1		; ab dieser Zeile die Bank neu fragen
pmi_bank:	ds.w	1
	SECTION	Program,code

; ***************************************************************************
; Kachel_holen -- eine Kachel Thalions im Schirmformat, aus dem
; Kachelspeicher.
;
;   IN : a0 = Quelle (Amiga-Format, ein Block breit, sechzehn Zeilen zu d5
;        Ebenenworten), d5.w = Ebenen (1..Data_depth), d4.w = Farbe der
;        Ebenen ab d5 (Bank, Versatzbits; die Bits unter d5 sind null)
;   OUT: a3 = Eintrag: KC_MASKE 16 Worte (wo die Farbe nicht null ist),
;        KC_BILD 16 Zeilen zu acht Ebenenworten.  Gilt bis zum naechsten
;        Aufruf.  Alle uebrigen Register bleiben.
;
; **Tempo** (Messung 2026-10-02, Hatari, 2D-Karte): Thalion zeichnet die
; Karte in jedem Bild ganz neu, rund 200 Kacheln, auch wenn die Gruppe
; steht; das Aufweiten von fuenf auf acht Ebenen kostete je Kachel und
; Bild aufs Neue.  Hier wird jede Kachel einmal aufgeweitet, danach nur
; noch kopiert.  Dasselbe Vorgehen wie St_kachel im ST-Port (docs/12, P3).
; Der Nutzer erlaubt fuer Tempo, in unserer Hardwareschicht zur Laufzeit
; zu wandeln und zu cachen.
;
; **Gefunden wird ein Eintrag ueber Adresse, Farbe und Ebenen, gueltig ist
; er nur, wenn auch der Inhalt der Quelle gleich ist.**  Jeder Eintrag
; haelt eine Abschrift der Quelle (bis 160 Byte) und vergleicht sie ganz.
; Eine Pruefsumme oder ein Ladezaehler genuegt nicht: Get_block legt
; Hintergruende immer wieder an derselben Adresse ab, und Thalion schreibt
; Speicher auch ohne Bibliotheksaufruf.  Der Vergleich ist so teuer wie das
; Kopieren, das Aufweiten kostete ein Vielfaches.
;
; Das Aufweiten ist dieselbe Regel wie in Put_unmasked_block und
; Put_masked_icon: Ebene p < d5 aus der Quelle, Ebene p >= d5 gleich der
; Maske, wenn Bit p der Farbe gesetzt ist, sonst null.
; ***************************************************************************
KACHEL_N	= 1024			; Plaetze, Zweierpotenz
KC_QUELLE	= 0			; .l
KC_FARBE	= 4			; .w
KC_EBENEN	= 6			; .w, 0 = leer
KC_KOPIE	= 8			; Abschrift der Quelle, Data_depth*32 Byte
KC_MASKE	= KC_KOPIE+Data_depth*32
KC_BILD		= KC_MASKE+16*2		; 16 Zeilen zu TROW Byte
KC_GR		= KC_BILD+16*TROW

Kachel_holen:
	movem.l	d0-d3/a0-a2,-(sp)
	; ---- Platz: Adresse und Bank ----
	move.l	a0,d0
	lsr.l	#5,d0
	move.w	d4,d1
	lsr.w	#5,d1
	eor.w	d1,d0
	and.w	#KACHEL_N-1,d0
	mulu.w	#KC_GR,d0
	lea	Kachelspeicher,a3
	add.l	d0,a3
	cmpa.l	KC_QUELLE(a3),a0
	bne.b	kh_neu
	cmp.w	KC_FARBE(a3),d4
	bne.b	kh_neu
	cmp.w	KC_EBENEN(a3),d5
	bne.b	kh_neu
	lea	KC_KOPIE(a3),a1		; Inhalt: d5*8 Langworte
	move.l	a0,a2
	move.w	d5,d0
	lsl.w	#3,d0
	subq.w	#1,d0
kh_vgl:	cmpm.l	(a1)+,(a2)+
	dbne	d0,kh_vgl
	beq.b	kh_da
kh_neu:
	move.l	a0,KC_QUELLE(a3)
	move.w	d4,KC_FARBE(a3)
	move.w	d5,KC_EBENEN(a3)
	lea	KC_KOPIE(a3),a1
	move.l	a0,a2
	move.w	d5,d0
	lsl.w	#3,d0
	subq.w	#1,d0
kh_kopie:
	move.l	(a2)+,(a1)+
	dbf	d0,kh_kopie
	; ---- aufweiten: je Zeile Maske und acht Ebenen ----
	lea	KC_MASKE(a3),a1
	lea	KC_BILD(a3),a2
	moveq	#16-1,d3
kh_zeile:
	move.l	a0,-(sp)
	moveq	#0,d2			; Maske: Oder der Quellebenen
	move.w	d5,d0
	subq.w	#1,d0
kh_msk:	or.w	(a0)+,d2
	dbf	d0,kh_msk
	move.l	(sp)+,a0
	move.w	d2,(a1)+
	moveq	#0,d1			; Ebenennummer
kh_pl:	cmp.w	d5,d1
	bcc.b	kh_hoch
	move.w	(a0)+,(a2)+		; aus der Quelle; so wandert a0 um eine Zeile
	bra.b	kh_weiter
kh_hoch:
	btst	d1,d4
	beq.b	kh_null
	move.w	d2,(a2)+
	bra.b	kh_weiter
kh_null:
	clr.w	(a2)+
kh_weiter:
	addq.w	#1,d1
	cmp.w	#PLANES,d1
	blo.b	kh_pl
	dbf	d3,kh_zeile
kh_da:
	movem.l	(sp)+,d0-d3/a0-a2
	rts

	SECTION	Fast_BSS,bss
	even
Kachelspeicher:	ds.b	KACHEL_N*KC_GR
	SECTION	Program,code

; ***************************************************************************
; Bloecke_nacharbeiten -- R_range afterwork (Bereich_nacharbeiten, RASTER.S)
; after a block routine.  IN: d0/d1 = corner, d6 = width in blocks, d7 =
; height, as called.  All registers are preserved.  (Was nb_bloecke in
; LIBRARY.S.)
;
; Bis X + 16*d6: mit Schiebeweite reicht ein maskierter Block in den Block
; dahinter.  Ein Block zu viel schadet nicht (die Nacharbeit ist ueberall
; richtig), er kostet nur.
; ***************************************************************************
Bloecke_nacharbeiten:
	movem.l	d2-d3,-(sp)
	move.w	d6,d2
	lsl.w	#4,d2
	add.w	d0,d2
	move.w	d7,d3
	add.w	d1,d3
	subq.w	#1,d3
	jsr	Bereich_nacharbeiten
	movem.l	(sp)+,d2-d3
	rts

; ***************************************************************************
; Zeichen_nacharbeiten -- R_range afterwork for one character of
; Put_char_at: eight points from txt_x/txt_y(a5), d6 lines.  All registers
; are preserved.  (Was the end of Put_char_at in LIBRARY.S.)
; ***************************************************************************
Zeichen_nacharbeiten:
	movem.l	d0-d3,-(sp)		; R_range: Verlaufsfarbe -> Platz
	move.w	txt_x(a5),d0
	move.w	txt_y(a5),d1
	move.w	d0,d2
	addq.w	#7,d2			; acht Punkte breit
	move.w	d1,d3
	add.w	d6,d3
	subq.w	#1,d3
	jsr	Bereich_nacharbeiten
	movem.l	(sp)+,d0-d3
	rts

; ***************************************************************************
; Unmasked_icon, Pm2_schnell, Zeiger_bild -- the hooks the ST fills
; (ST_LIB.S).  The Falcon has no fast path there yet: Unmasked_icon goes
; straight back to the generic body, Pm2_schnell says "not drawn" (C set),
; Zeiger_bild has nothing to do.
; ***************************************************************************
Unmasked_icon:
	bra	pui_allgemein

Pm2_schnell:
	ori.b	#1,ccr			; C set: Put_masked_block2 goes on
	rts

Zeiger_bild:
	rts

; ***************************************************************************
; Pointer_convert -- Set_mouse_ptr's conversion of the pointer (AREAS.S
; calls it; the ST's of the same name is in ST_LIB.S).  Library split
; phase 3 (2026-10-24): moved here unchanged from AREAS.S.
;   IN : a0 = Thalion's lines (three plane words per line, 16 lines),
;        a1 = zg_bild, a2 = zg_maske
;   All registers are preserved.
;
; Three planes become eight: colour = bank of the screen line + 24 + the
; pointer's value, 0 stays transparent.  The pointer's points also go into
; planes 5 and 6; Zeiger_in_puffer keeps them only where the bank of the
; line has the bit (finding 266, AREAS.S).
; ***************************************************************************
Pointer_convert:
	movem.l	d0-d4/d7/a0-a2,-(sp)
	moveq	#MPTR_H-1,d7
smp_z:	move.w	(a0)+,d0		; Ebenen 0-2
	move.w	(a0)+,d1
	move.w	(a0)+,d2
	move.w	d0,d3
	or.w	d1,d3
	or.w	d2,d3			; d3 = Punkte des Zeigers
	move.w	d0,(a1)+
	move.w	d1,(a1)+
	move.w	d2,(a1)+
	move.w	d3,(a1)+		; Ebene 3 und 4: Farbversatz 24
	move.w	d3,(a1)+
	move.w	d3,(a1)+		; Ebene 5 und 6: die Bank, nur wo die
	move.w	d3,(a1)+		; Bank der Zeile ihr Bit hat
	clr.w	(a1)+
	not.w	d3			; Maske: 1 = durchsichtig
	moveq	#PLANES-1,d4
smp_m:	move.w	d3,(a2)+
	dbf	d4,smp_m
	dbf	d7,smp_z
	movem.l	(sp)+,d0-d4/d7/a0-a2
	rts

; ***************************************************************************
; The colour banks of Set_fade, the start palette and Drugged_FX.  Library
; split phase 3 (2026-10-24): moved here unchanged from FADE_SUP.S, which
; calls them (Platz_setzen, Bank0_setzen, Palette_anfang) and LIBRARY.S
; (Drogen_farben, Drogen_setzen).  The ST has its own Platz_setzen,
; Bank0_setzen and Palette_anfang (16 registers through the colour table)
; and empty Drogen_* in ST_LIB.S.
; ***************************************************************************
; Platz_setzen -- die Palette eines Platzes der Rasterliste in seine Bank.
;   a0 = 32 Worte $0RGB, d0.w = Platz (0..PLAETZE-1)
;   Alle Register bleiben.
; ***************************************************************************
Platz_setzen:
	movem.l	d0-d3/a0-a2,-(sp)
	; Mitschreiben, was gesetzt wird -- Set_fade blendet beim naechsten Mal
	; von hier weg.
	lea	Bank_ist,a1
	move.w	d0,d1
	lsl.w	#6,d1
	add.w	d1,a1
	move.l	a0,a2
	moveq	#31,d1
pls_merken:
	move.w	(a2)+,(a1)+
	dbf	d1,pls_merken
	add.w	d0,d0
	lea	Platzbank,a1
	move.w	0(a1,d0.w),d0		; erste Farbnummer der Bank
	bsr.b	Bank_setzen
	movem.l	(sp)+,d0-d3/a0-a2
	rts

; ***************************************************************************
; Bank0_setzen -- 32 Amiga-Farbworte nach Bank 0 (Farbe 0 bis 31).
;   a0 = 32 Worte $0RGB.  Alle Register bleiben.
;
; Fuer unser Startmenue, das vor jedem Modul zeichnet: ohne Rasterliste
; gilt Bank 0 (Farbbank).  Bank 0 ist der zweite Platz.
; ***************************************************************************
Bank0_setzen:
	move.w	d0,-(sp)
	moveq	#1,d0
	bsr.b	Platz_setzen
	move.w	(sp)+,d0
	rts

; ***************************************************************************
; Bank_setzen -- 32 Amiga-Farbworte nach VIDEL.
;   a0 = 32 Worte $0RGB, d0 = erste Farbnummer
;   Veraendert d0-d3/a0-a2.
; ***************************************************************************
Bank_setzen:
	move.w	d0,-(sp)
	lea	Videl_puffer,a1
	lea	Vid_stufe(pc),a2
	moveq	#31,d3
b0s_farbe:
	move.w	(a0)+,d0
	moveq	#0,d2
	move.w	d0,d1			; Rot
	lsr.w	#8,d1
	and.w	#$f,d1
	move.b	0(a2,d1.w),d2
	lsl.l	#8,d2
	move.w	d0,d1			; Gruen
	lsr.w	#4,d1
	and.w	#$f,d1
	move.b	0(a2,d1.w),d2
	lsl.l	#8,d2
	move.w	d0,d1			; Blau
	and.w	#$f,d1
	move.b	0(a2,d1.w),d2
	move.l	d2,(a1)+
	dbf	d3,b0s_farbe
	move.w	(sp)+,d0
	pea	Videl_puffer
	move.w	#32,-(sp)
	move.w	d0,-(sp)
	move.w	#VsetRGB,-(sp)
	Xbios
	lea	10(sp),sp
	rts

; ***************************************************************************
; Palette_anfang -- die 256 Farben in Grundstellung, beim Oeffnen des Schirms.
;
;   Bank 2 (Farbe 64..95)  Main_pal, der erste Platz jeder Rasterliste
;   alle uebrigen          schwarz
; Ab jetzt setzt und blendet Set_fade die Baenke je Platz (Platzbank).
;
; **Main_pal ist ein Datensatz aus AM2_CPU** (build/am2cpu_daten.i), und
; Current_pal fuellt Thalions Code selbst.  Bis Stufe (c) leitete
; Paletten_ableiten beide bei jedem Set_fade aus der Palette des
; Kartenpuffers ab (p_pal) und ueberschrieb damit Thalions Current_pal.
; Alle Register bleiben.
; ***************************************************************************
Palette_anfang:
	movem.l	d0-d4/a0-a2,-(sp)
	moveq	#0,d4
pan_bank:
	lea	Schwarz,a0
	move.w	d4,d0
	bsr	Bank_setzen
	add.w	#32,d4
	cmp.w	#256,d4
	bcs.b	pan_bank
	lea	Main_pal,a0		; erster Platz: Main_pal, wie in jeder
	moveq	#0,d0			; Rasterliste Thalions
	bsr	Platz_setzen		; und Bank_ist mitschreiben
	lea	Schwarz,a0
	moveq	#1,d0
	bsr	Platz_setzen
	moveq	#2,d0
	bsr	Platz_setzen
	bsr	Bereiche_anfang		; Plaetze der Verlaeufe: schwarz (RASTER.S)
	clr.l	Letzte_RL
	movem.l	(sp)+,d0-d4/a0-a2
	rts

; ***************************************************************************
; Drogen_farben -- Thalion's Drugged_FX on the colours, every frame (VBL).
;
; As in AM2_CPU 1.20 (0:$233BC): while Drugged_FX is set and no fade runs,
; the copper list is built anew every frame, and every colour 1-31 of each
; R_palette gets its own offset in red or in blue, clipped to 0..15.  Each
; frame one of the offsets is drawn anew, in turn (Dr_lauf steps by 4 in
; 0..124, 0 draws none): which component (Random & 1, 1 = red) and how much
; ((Random & 15) - 9, so -9..+6).  Colour 0 and the gradients (R_range)
; stay.  When it ends, Thalion's Check_active_member calls Reset_current_RL,
; which sets the clean palettes again.
;
; Our copper is the colour banks: the palettes set are in Bank_ist, one bank
; per R_palette of the list (Platzbank).  In the VBL there is no XBIOS, so
; the colours go to the VIDEL registers ourselves, $RRGG00BB (RASTER.S).
;
; **Not here, though.**  Written this late in the VBL (after the pointer),
; the beam is already in the top lines, and VIDEL palette writes during the
; display left sparkles in the portraits (T26, hardware, 2026-10-18).  So
; this routine fills Dr_puffer, and Drogen_setzen writes it at the very
; start of the next VBL, still in the border.  One frame later; the rhythm
; stays Thalion's.
;   All registers are preserved.
; ***************************************************************************
Drogen_farben:
	tst.b	Drugged_FX
	beq.b	df_aus
	tst.b	Blende_laeuft
	bne.b	df_aus
	tst.l	Letzte_RL
	bne.b	df_an
df_aus:	rts
df_an:
	movem.l	d0-d7/a0-a4,-(sp)
	; ---- one offset anew, in turn (0:$233C6) ----
	move.w	Dr_lauf,d0
	addq.w	#4,d0
	and.w	#124,d0
	move.w	d0,Dr_lauf
	beq.b	df_plaetze
	lea	Dr_tab,a0
	add.w	d0,a0
	jsr	Random
	and.w	#1,d0
	move.w	d0,(a0)+		; 0 = blue, 1 = red
	move.w	d0,d1
	jsr	Random
	and.w	#15,d0
	sub.w	#9,d0
	tst.w	d1
	beq.b	df_blau
	asl.w	#8,d0			; red: the offset in the red nibble
df_blau:
	move.w	d0,(a0)
df_plaetze:
	; ---- the R_palette entries of the list, as Set_fade counts them ----
	move.l	Letzte_RL,a3
	move.l	a3,Dr_rl		; the list the buffer belongs to
	lea	Vid_stufe(pc),a4
	moveq	#0,d3			; place
df_liste:
	move.b	(a3),d4
	cmp.b	#RL_END,d4
	beq.b	df_raus
	cmp.b	#RL_PAL,d4
	bne.b	df_range
	cmp.w	#PLAETZE,d3
	bcc.b	df_raus
	bsr.b	Drogen_platz
	addq.w	#1,d3
	addq.l	#6,a3
	bra.b	df_liste
df_range:
	addq.l	#8,a3
	bra.b	df_liste
df_raus:
	move.w	d3,Dr_anzahl		; places in the buffer, for Drogen_setzen
	movem.l	(sp)+,d0-d7/a0-a4
	rts

; ***************************************************************************
; Drogen_setzen -- write Dr_puffer into the VIDEL palette.  First thing in
; the VBL (Bibliothek_vbl), so the writes fall into the top border.
;
; Only if the buffer still fits: Drugged_FX still set, no fade, the same
; raster list.  Thalion clears Drugged_FX before Reset_current_RL, so the
; clean colours of the end are never overwritten by a stale buffer.
;   All registers are preserved.
; ***************************************************************************
Drogen_setzen:
	tst.w	Dr_anzahl
	bne.b	ds_da
	rts
ds_da:
	movem.l	d0/d7/a0-a1,-(sp)
	move.w	Dr_anzahl,d0
	clr.w	Dr_anzahl
	tst.b	Drugged_FX
	beq.b	ds_raus
	tst.b	Blende_laeuft
	bne.b	ds_raus
	move.l	Letzte_RL,a0
	cmp.l	Dr_rl,a0
	bne.b	ds_raus
	lea	Dr_puffer,a0
	subq.w	#1,d0
ds_platz:
	move.l	(a0)+,a1		; the place's colour 1 in the VIDEL palette
	moveq	#31-1,d7
ds_farbe:
	move.l	(a0)+,(a1)+
	dbf	d7,ds_farbe
	dbf	d0,ds_platz
ds_raus:
	movem.l	(sp)+,d0/d7/a0-a1
	rts

; Drogen_platz -- d3.w = place, a4 = Vid_stufe.  Fills the place's part of
; Dr_puffer: the VIDEL address of its colour 1, then 31 colours.
; Changes d0-d2/d4/d7/a0-a2.
Drogen_platz:
	lea	Bank_ist,a0
	move.w	d3,d0
	lsl.w	#6,d0
	add.w	d0,a0
	addq.l	#2,a0			; colour 0 stays
	move.w	d3,d0
	add.w	d0,d0
	lea	Platzbank,a1
	move.w	0(a1,d0.w),d0		; first colour number of the bank
	addq.w	#1,d0
	lsl.w	#2,d0
	lea	VIDEL_PAL,a1
	add.w	d0,a1
	move.w	d3,d0			; 128 bytes per place in the buffer
	lsl.w	#7,d0
	lea	Dr_puffer,a2
	add.w	d0,a2
	move.l	a1,(a2)+
	move.l	a2,a1
	lea	Dr_tab+4,a2
	moveq	#31-1,d7
dp_farbe:
	move.w	(a0)+,d1		; $0RGB
	tst.w	(a2)+
	bne.b	dp_rot
	moveq	#$f,d2			; blue
	and.w	d1,d2
	sub.w	d2,d1
	add.w	(a2)+,d2
	bmi.b	dp_setzen		; below 0: the component is 0
	cmp.w	#$10,d2
	bmi.b	dp_oder
	moveq	#$f,d2
	bra.b	dp_oder
dp_rot:
	move.w	#$f00,d2		; red
	and.w	d1,d2
	sub.w	d2,d1
	add.w	(a2)+,d2
	bmi.b	dp_setzen
	cmp.w	#$1000,d2
	bmi.b	dp_oder
	move.w	#$f00,d2
dp_oder:
	or.w	d2,d1
dp_setzen:
	move.w	d1,d2			; $0RGB -> $RRGG00BB
	lsr.w	#8,d2
	and.w	#$f,d2
	moveq	#0,d4
	move.b	0(a4,d2.w),d4		; red
	lsl.w	#8,d4
	move.w	d1,d2
	lsr.w	#4,d2
	and.w	#$f,d2
	move.b	0(a4,d2.w),d4		; green
	swap	d4
	and.w	#$f,d1
	move.b	0(a4,d1.w),d4		; blue
	move.l	d4,(a1)+
	dbf	d7,dp_farbe
	rts

	SECTION	Fast_BSS,bss
Dr_tab:		ds.l	32		; per colour: .w red (1) or blue (0), .w offset
Dr_lauf:	ds.w	1
Dr_anzahl:	ds.w	1		; places in Dr_puffer, 0 = nothing to write
Dr_rl:		ds.l	1		; Letzte_RL when Dr_puffer was filled
Dr_puffer:	ds.l	PLAETZE*32	; per place: VIDEL address, 31 colours
	SECTION	Program,code


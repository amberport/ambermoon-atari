; HULL/LIBRARY.S -- Bibliotheksschicht, Zeichnen und Maus
;
; This file has no model in the released source: Draw_box,
; Put_unmasked_block, Put_masked_block and Update_screen belong to the
; library Thalion never released.  They carry Thalion's names, so the calls
; in the rest of the code look as in the original; their contracts are in
; docs/developer/ (chapter 4, appendix B).
;
; What is *not* here: the machines.  Screen mode, colour registers and the
; own screen memory are in HULL/FALCON.S (ST: ST.S).  What knows colour
; banks and eight planes is in HULL/FALCON_LIB.S (owner Falcon Tempo), the
; ST counterpart in ST_LIB.S (library split, user 2026-10-21; docs/
; developer/05, "LIBRARY.S by machine").  This file keeps Thalion's
; names, the contracts and the shared part, which works on both machines
; through PLANES, TROW and SCRROW, and calls the machine part under a
; neutral name that both parts define (phase 2, 2026-10-23: no IFD ZIEL_ST
; here any more).  The colour-bank routines (Farbbank and the others) stay
; here for now, because the ST build calls them too.
;
; The system calls that stay here -- Kbdvbase and Ikbdws for the mouse --
; are TOS, not Falcon; the ST has them as well.

; ***************************************************************************
; Put_unmasked_block -- **Thalion's full contract**, not only the name.
;   IN : a0 = source: d5 < 8 Thalion's data, line-interleaved, d5 planes;
;        d5 = 8 our screen format.  d0.w = x (rounded down to a multiple
;        of 16), d1.w = y, d4.w = colour offset for the planes from d5 up,
;        d5.w = planes of the source, d6.w = width in 16-pixel blocks,
;        d7.w = height in lines.  Clipped against the topmost CA.
;   All registers are preserved.
;
; **Hier stand vorher unser Put_block_wh unter beiden Namen, und das war
; falsch.**  Es las immer acht Ebenen und benutzte d4 und d5 sogar als eigene
; Zaehler.  Thalions Aufrufer uebergeben aber durchweg beides:
;
;     DISPLAY.S   moveq #24,d4 / moveq #3,d5   (Layouts, drei Ebenen)
;     DIALOGUE.S  moveq #24,d4 / moveq #3,d5   und moveq #5,d5
;     CHARACTE.S  moveq #5,d5
;     HDOBS.S     moveq #Screen_depth,d5       (Hintergrund zurueck, = 5)
;
; Die Grafiken des Originals haben also *weniger* Ebenen als unser Schirm,
; und der Farbversatz sagt, in welchen Abschnitt der Palette sie gehoeren.
;
; Wie aufgeweitet wird -- dieselbe Regel wie in Put_masked_block2:
;
;     Farbe = Farbbank(y) + (d4-Bits von d5 bis 4) + Quellwert,  0 bleibt 0
;
; Die unteren d5 Ebenen kommen unveraendert aus der Quelle, jede hoehere
; traegt die Maske "Quellwert ungleich null", wo die Farbe ihr Bit hat.  Von
; d4 zaehlen nur die Bits, die der Amiga-Schirm mit seinen fuenf Ebenen
; ueberhaupt hat (d5=3, d4=24 ergibt 24..31; bei d5=5 bleibt nichts).  Die
; Bank ersetzt den Copper und wird je Bildzeile bestimmt (Farbbank).
;
; Mit d5 = PLANES faellt die Aufweitung weg und es bleibt beim schlichten
; Kopieren.  Thalions Code schickt nie acht: Screen_depth ist 5 (Erkenntnis
; 191).  Auch ein Hintergrund, den Open_window oder HDOBS.S mit Get_block
; gesichert hat, kommt mit d5 = 5 zurueck und bekommt hier seine Bank
; wieder -- verlustfrei, solange alle Zeichenroutinen die Regel oben
; einhalten (Zeilenfarbe).
; ***************************************************************************
Put_unmasked_block:
	movem.l	d0-d7/a0-a4,-(sp)
	and.w	#-16,d0			; wie das Original: auf den Block
	bsr	Block_beschneiden
	bcs	pub_out
	bra.b	pub_seitlich
	; **Ohne Beschneiden**: Put_unmasked_icon.  Das Original prueft dort
	; keine CA (AM2_CPU 1.20, 0:$22518).
pub_ohne_ca:
	movem.l	d0-d7/a0-a4,-(sp)
	and.w	#-16,d0
	tst.w	d6
	ble	pub_out
	tst.w	d7
	ble	pub_out
	clr.w	bl_links
	move.w	d6,bl_rechts
	subq.w	#1,bl_rechts
pub_seitlich:
	; ---- seitlich: nur die Bloecke bl_links..bl_rechts, mit d6 geklemmt.
	; d6 bleibt die Breite der Quelle (Schrittweite), bl_anzahl zaehlt ----
	move.w	bl_links,d2
	bpl.b	pub_l_ok
	moveq	#0,d2
pub_l_ok:
	move.w	bl_rechts,d3
	cmp.w	d6,d3
	blt.b	pub_r_ok
	move.w	d6,d3
	subq.w	#1,d3
pub_r_ok:
	sub.w	d2,d3
	addq.w	#1,d3
	ble	pub_out
	move.w	d3,bl_anzahl
	moveq	#0,d3			; ganz: unten wird d3 lang addiert
	move.w	d2,d3			; erster sichtbarer Block
	add.w	d3,d3
	cmp.w	#SCHIRM_FORMAT,d5
	bcs.b	pub_q_amiga
	mulu.w	#PLANES,d3		; unsere Daten: je Block acht Worte
pub_q_amiga:
	add.l	d3,a0			; Quelle auf den ersten sichtbaren Block
	move.w	d1,a2			; Bildzeile, fuer die Farbbank
	move.l	Work_screen,a1
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	asr.w	#4,d0
	add.w	d2,d0
	muls.w	#TROW,d0
	add.l	d0,a1			; a1 = erster sichtbarer Block im Puffer
	subq.w	#1,d7
	bmi	pub_out
	; **Zwei Quellformate, unterscheidbar an d5.**  Hat die Quelle so viele
	; Ebenen wie der Schirm, stammt sie von uns -- dann wird nur kopiert.
	; Hat sie weniger, ist sie im Amiga-Format (Originalgrafik oder ein mit
	; Get_block gesicherter Hintergrund): zeilenverschachtelt und mit
	; Farbversatz und Bank aufzuweiten.
	cmp.w	#SCHIRM_FORMAT,d5
	bcc	pub_schlicht
	; Versatzbits von d5 bis zur Amiga-Tiefe ins obere Wort von d7 (dbf
	; zaehlt nur das untere)
	moveq	#-1,d0
	lsl.w	d5,d0
	and.w	#(1<<Data_depth)-1,d0
	and.w	d4,d0
	swap	d7
	move.w	d0,d7
	swap	d7
	; The machine part: the lines in Thalion's format (Pub_zeilen;
	; FALCON_LIB.S: banks and eight planes, the tile cache; ST_LIB.S: four
	; planes through the colour table)
	bsr	Pub_zeilen
	bra	pub_out

	; ---- Quelle schon im Schirmformat: blockweise durchreichen ----
pub_schlicht:
	move.w	d6,d0			; eine Quellzeile: d6 Bloecke zu TROW
	mulu.w	#TROW,d0
pub_szeile:
	move.l	a1,a2
	move.l	a0,a3
	move.w	bl_anzahl,d2
	subq.w	#1,d2
pub_scol:
	moveq	#PLANES-1,d3
pub_spl:
	move.w	(a3)+,(a2)+
	dbf	d3,pub_spl
	dbf	d2,pub_scol
	add.l	d0,a0
	lea	SCRROW(a1),a1
	dbf	d7,pub_szeile
pub_out:
	movem.l	(sp)+,d0-d7/a0-a4
	jmp	Bloecke_nacharbeiten	; machine part: R_range afterwork

	SECTION	Fast_BSS,bss
	even
fsp_merk_liste:	ds.l	1		; Merker von Farbbank_spanne: Liste,
fsp_von:	ds.w	1		; Spanne von..bis-1
fsp_bis:	ds.w	1
fsp_bank:	ds.w	1
bl_links:	ds.w	1		; Block_beschneiden: sichtbare Zielbloecke,
bl_rechts:	ds.w	1		;  gezaehlt ab X/16
bl_anzahl:	ds.w	1		; Put_unmasked_block: sichtbare Bloecke
	SECTION	Program,code

; ***************************************************************************
; Block_beschneiden -- die Pruefung, mit der Thalions Blockroutinen im
; Original beginnen.  In AM2_CPU 1.20 nachgelesen, in allen dreien gleich:
; Put_unmasked_block 0:$22CBE, Put_masked_block 0:$228B0 (CPU-Fassung;
; die Blitterfassung 0:$22646 ebenso), Put_masked_silhouette 0:$22AD2.
; Gegen die oberste Clip-Area (CA_Sp, EFFECTS_SUP.S; Thalions Push CA).
;
;   IN : d0 = X, d1 = Y, d5 = Ebenen der Quelle, d6 = Breite in Bloecken,
;        d7 = Hoehe, a0 = Quelle (je Bildzeile d5 Plane-Zeilen zu d6 Worten;
;        bei d5 = PLANES unsere Daten, je Zeile d6 Bloecke zu TROW)
;   OUT: C gesetzt = nichts zeichnen.  Sonst sind d1, d7, a0 oben und unten
;        beschnitten, und bl_links/bl_rechts nennen den ersten und letzten
;        sichtbaren Zielblock, gezaehlt ab X/16 (koennen ausserhalb 0..d6
;        liegen).  Alle uebrigen Register bleiben.
;
; Wie im Original:
;   d5 < 0 oder > 5                      nichts
;   X & -16 > X2  oder  Y > Y2           nichts
;   X + 16*d6 - 1 < X1  oder  Y + d7 - 1 < Y1   nichts
;   Y < Y1   oben abschneiden: d7 kuerzen, Quelle um die Zeilen weiter
;   unten    d7 kuerzen
;   seitlich ganze Bloecke weglassen (das Original kuerzt d6 und laesst
;            das Randwort weg; wir schreiben Zielbloecke ausserhalb
;            X1/16..X2/16 nicht)
; Anders als das Original:
;   d5 = PLANES gilt (unsere Daten, Put_masked_block8).
;   d5 = 0 zeichnet nichts.  Das Original malte dann nur die Maske in der
;          Farbe d4; das koennen wir nicht, die Maske rechnen wir aus den
;          Quellebenen.  Kein Aufrufer bekannt.
;   d6 <= 0 oder d7 <= 0 zeichnet nichts.  Das Original prueft nur die Lage;
;          bei uns liefe eine dbf-Schleife 65536 Mal (Absturz beim
;          Kampfbeginn, Befund der 3D-Session 2026-09-28).
;   Die CA wird auf den Schirm begrenzt.
; ***************************************************************************
Block_beschneiden:
	movem.l	d0/d2-d4/a1,-(sp)
	tst.w	d5
	ble	bb_nichts
	cmp.w	#SCHIRM_FORMAT,d5
	beq.b	bb_tiefe
	cmp.w	#Data_depth,d5
	bgt	bb_nichts
bb_tiefe:
	tst.w	d6
	ble	bb_nichts
	tst.w	d7
	ble	bb_nichts
	move.l	CA_Sp,a1
	move.l	(a1),a1			; oberster CA-Satz
	; ---- senkrecht ----
	move.w	CA_Y1(a1),d2
	bpl.b	bb_y1
	moveq	#0,d2
bb_y1:	move.w	CA_Y2(a1),d3
	cmp.w	#SCRH-1,d3
	ble.b	bb_y2
	move.w	#SCRH-1,d3
bb_y2:	cmp.w	d3,d1
	bgt	bb_nichts		; ganz unterhalb
	move.w	d1,d4
	add.w	d7,d4
	subq.w	#1,d4			; letzte Zeile
	cmp.w	d2,d4
	blt	bb_nichts		; ganz oberhalb
	cmp.w	d3,d4
	ble.b	bb_unten
	move.w	d3,d7			; unten abschneiden
	sub.w	d1,d7
	addq.w	#1,d7
bb_unten:
	move.w	d2,d4
	sub.w	d1,d4			; Zeilen ueber Y1
	ble.b	bb_oben
	sub.w	d4,d7			; oben abschneiden
	mulu.w	d6,d4
	mulu.w	d5,d4
	add.l	d4,a0			; d4 Zeilen zu d5*d6 Worten
	add.l	d4,a0
	move.w	d2,d1
bb_oben:
	; ---- seitlich ----
	move.w	CA_X1(a1),d2
	bpl.b	bb_x1
	moveq	#0,d2
bb_x1:	move.w	CA_X2(a1),d3
	cmp.w	#SCRW-1,d3
	ble.b	bb_x2
	move.w	#SCRW-1,d3
bb_x2:	move.w	d0,d4
	and.w	#-16,d4
	cmp.w	d3,d4
	bgt.b	bb_nichts		; ganz rechts daneben
	move.w	d6,d4
	lsl.w	#4,d4
	add.w	d0,d4
	subq.w	#1,d4			; letzter Punkt
	cmp.w	d2,d4
	blt.b	bb_nichts		; ganz links daneben
	asr.w	#4,d0			; Block von X
	asr.w	#4,d2
	asr.w	#4,d3
	sub.w	d0,d2
	sub.w	d0,d3
	move.w	d2,bl_links
	move.w	d3,bl_rechts
	movem.l	(sp)+,d0/d2-d4/a1
	andi.b	#$FE,ccr		; C aus: zeichnen
	rts
bb_nichts:
	movem.l	(sp)+,d0/d2-d4/a1
	ori.b	#1,ccr			; C an: nichts
	rts

; ***************************************************************************
; Bl_sichtbar -- liegt Zielblock d1.w (gezaehlt ab X/16) in
; bl_links..bl_rechts?  C gesetzt = nein.  Alle Register bleiben.
; ***************************************************************************
Bl_sichtbar:
	cmp.w	bl_links,d1
	blt.b	bls_nein
	cmp.w	bl_rechts,d1
	bgt.b	bls_nein
	andi.b	#$FE,ccr
	rts
bls_nein:
	ori.b	#1,ccr
	rts

; ***************************************************************************
; Put_masked_block2 -- **Thalion's full contract**, masked, any x.
;   IN : a0 = graphic, d0.w = x, d1.w = y, d4.w = colour offset, d5.w =
;        planes of the source, d6.w = width in 16-pixel blocks, d7.w =
;        height in lines.  Colour 0 is transparent.  Clipped against the
;        topmost CA.
;   All registers are preserved.
;
; **d5 sagt, was in der Quelle liegt**, genau wie bei Put_unmasked_block:
;
;   d5 = SCHIRM_FORMAT  our data: screen planes, block-interleaved, bank
;                 and offset already applied
;   d5 < PLANES   Thalions Daten: Amiga-zeilenverschachtelt, je Bildzeile d5
;                 Plane-Zeilen zu d6 Worten.  Sie werden erst hier aufgeweitet
;                 (Quelle_aufweiten), nie vorher -- sonst stimmte seine
;                 Schrittweite nicht (Icon_size, "mulu.w #13*12").
;
; Seine Aufrufer: Steuersymbole mit d5=3, d4=24 (CONTROLS.S); Objektsymbole
; mit d5=5 und beliebigem d4 (DISPLAY.S, INVENTOR.S, CONTROLS.S); HDOBs mit
; HDOB_depth.  Bis 2026-09-25 hiess hier nur d5=3 "Originaldaten", d5=5 hiess
; "schon aufgeweitet" -- ein Sonderfall, den Load_object_graphics mit einer
; Aufweitung beim Laden erkaufte.  Die ist weg (Erkenntnis 176).
;
; Die Farbe eines Punktes ist die Amiga-Regel plus die Bank der Bildzeile:
;
;     Farbe = Farbbank(y) + (d4-Bits von d5 bis 4) + Quellwert,  0 bleibt 0
;
; Auf dem Amiga hat der Schirm fuenf Ebenen: was d4 oberhalb der d5
; Quellebenen traegt, fuellt die fehlenden Ebenen (d5=3, d4=24 ergibt 24..31);
; bei d5=5 bleibt fuer d4 nichts.  Die Bank ersetzt den Copper, siehe
; Farbbank.  Die Null bleibt durchsichtig: die Maske ist das ODER der
; Quellebenen.
;
; Das Setzen selbst ist das Verfahren von Put_char: das Quellwort wandert in
; die obere Haelfte eines Langworts und wird um X mod 16 nach rechts
; geschoben.  Danach steht der linke Teil im oberen Wort und der Rest im
; unteren; beide gehoeren zu verschiedenen Bloecken, und die liegen TROW
; auseinander.  Liegt X auf einer Blockgrenze, bleibt das untere Wort leer
; und wird *nicht* geschrieben -- sonst faende ein Symbol am rechten Rand
; einen Block, den es nicht gibt, und traefe den Anfang der naechsten Zeile.
; ***************************************************************************
; ***************************************************************************
; Put_masked_block -- **Thalion's** masked block on a block boundary.
;   IN : as Put_masked_block2, d0.w a multiple of 16
;   All registers are preserved.
;
; Der einzige Unterschied zu Put_masked_block2 ist die Bedingung an X -- und
; eine Blockgrenze ist bloss ein Sonderfall von "irgendwo".  Also dieselbe
; Routine; sie behandelt die Schiebeweite 0 ohnehin gesondert.
; ***************************************************************************
Put_masked_block:
	bra	Put_masked_block2

Put_masked_block2:
	movem.l	d1/d7/a0,-(sp)
	bsr	Block_beschneiden	; wie das Original: gegen die CA
	bcs.b	pm2_nichts
	; Machine part first: Pm2_schnell takes what Maskiert_setzen takes,
	; clipped; C clear = drawn, C set = go on here.  All registers
	; preserved.  (ST_LIB.S: one block on a block border; FALCON_LIB.S:
	; nothing yet.)
	bsr	Pm2_schnell
	bcc.b	pm2_nichts
	cmp.w	#SCHIRM_FORMAT,d5
	bcc.b	pm2_setzen		; unsere Daten: unmittelbar setzen
	bsr	Quelle_aufweiten		; Thalions Daten -> Zwischenpuffer
	cmpa.w	#0,a0
	beq.b	pm2_nichts		; passte nicht: lieber nichts als Muell
pm2_setzen:
	bsr.b	Maskiert_setzen
pm2_nichts:
	movem.l	(sp)+,d1/d7/a0
	rts
; Maskiert_setzen -- der Setzteil von Put_masked_block2: Quelle mit acht
; Ebenen, schon beschnitten (bl_links/bl_rechts).  Alle Register bleiben.
Maskiert_setzen:
	movem.l	d0-d7/a0-a4,-(sp)
	move.w	d0,d5			; Schiebeweite
	and.w	#15,d5
	asr.w	#4,d0			; Blocknummer (X darf links herausragen)
	move.l	Work_screen,a1
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	muls.w	#TROW,d0
	add.l	d0,a1
	subq.w	#1,d7
pm2_row:
	move.l	a1,a2
	move.w	d6,d4
	subq.w	#1,d4
pm2_col:
	; ---- welche der beiden Zielbloecke dieser Spalte sind sichtbar?
	; Bit 16: der linke (Spalte c), Bit 17: der rechte (c+1).  lsr.l
	; zaehlt nur die unteren sechs Bits von d5, tst.w nur das untere Wort ----
	and.l	#$FFFF,d5
	move.w	d6,d1
	sub.w	d4,d1
	subq.w	#1,d1			; Spalte c
	bsr	Bl_sichtbar
	bcs.b	pm2_l_aus
	bset	#16,d5
pm2_l_aus:
	tst.w	d5
	beq.b	pm2_r_aus		; auf der Blockgrenze: kein rechter Teil
	addq.w	#1,d1
	bsr	Bl_sichtbar
	bcs.b	pm2_r_aus
	bset	#17,d5
pm2_r_aus:
	move.l	d5,d1
	swap	d1
	tst.w	d1
	bne.b	pm2_sichtbar
	lea	PLANES*2(a0),a0		; ganze Spalte ausserhalb der CA
	bra.b	pm2_spalte
pm2_sichtbar:
	moveq	#0,d0			; Maske aus den acht Ebenen
	move.l	a0,a3
	moveq	#PLANES-1,d1
pm2_msk:
	or.w	(a3)+,d0
	dbf	d1,pm2_msk
	swap	d0
	clr.w	d0
	lsr.l	d5,d0
	not.l	d0			; 1 = Hintergrund behalten
	moveq	#0,d3			; Versatz der Ebene
	moveq	#PLANES-1,d1
pm2_pl:
	move.w	(a0)+,d2
	swap	d2
	clr.w	d2
	lsr.l	d5,d2
	swap	d0			; linker Teil, erster Block
	swap	d2
	btst	#16,d5
	beq.b	pm2_ohne_links
	and.w	d0,(a2,d3.w)
	or.w	d2,(a2,d3.w)
pm2_ohne_links:
	swap	d0			; rechter Teil, zweiter Block
	swap	d2
	btst	#17,d5			; nur mit Schiebeweite gesetzt
	beq.b	pm2_next
	and.w	d0,TROW(a2,d3.w)
	or.w	d2,TROW(a2,d3.w)
pm2_next:
	addq.w	#2,d3
	dbf	d1,pm2_pl
pm2_spalte:
	lea	TROW(a2),a2
	dbf	d4,pm2_col
	lea	SCRROW(a1),a1
	dbf	d7,pm2_row
	movem.l	(sp)+,d0-d7/a0-a4
	jmp	Bloecke_nacharbeiten	; machine part: R_range afterwork

; ***************************************************************************
; Quelle_aufweiten -- a source in Thalion's format (d5 < PLANES) into the
; screen format, for Put_masked_block2.
;   IN : a0 = source, line-interleaved (per line d5 plane lines of d6
;        words), d1 = y, d4 = colour offset, d5 = planes, d6 = blocks, d7 =
;        lines
;   OUT: a0 = pmo_puffer, or 0 if it does not fit.  All other registers are
;        preserved.
; In the machine part: FALCON_LIB.S, ST_LIB.S.
; ***************************************************************************

	SECTION	Fast_BSS,bss
	even
PMO_MAX	equ	32*TROW*24		; 32 Bloecke zu 24 Zeilen; das groesste
pmo_puffer:	ds.b	PMO_MAX		; bisher ist ein HDOB mit 1x24
	SECTION	Program,code

; ***************************************************************************
; Farbbank -- welche Farbbank gilt in dieser Bildzeile?
;
;   IN : d0.w = Bildzeile
;   OUT: d0.w = Bankversatz (erste Farbnummer der Bank)
;   Alle uebrigen Register bleiben.
;
; **Der Ersatz fuer den Copper.**  Auf dem Amiga schaltet die Rasterliste
; des obersten Moduls die Palette zeilenweise um; jede Grafik hat 32 Farben
; und landet in der Palette, die an ihrer Bildzeile gilt.  Bei uns liegt
; jede R_palette der Liste in einer eigenen Farbbank, **festgemacht an ihrem
; Platz in der Liste** (Platzbank, FADE_SUP.S): die erste in Bank 2, die
; zweite in Bank 0, die dritte in Bank 1.  Set_fade fuellt die Baenke nach
; derselben Tabelle.
;
; Bis Erkenntnis 264 hing die Wahl daran, was gerade in Bank 0 stand.
; Dann wechselte die Farbe eines Punkts mit der Zeit: die Portraitleiste,
; gezeichnet, als Bank 0 Main_pal trug, nahm spaeter die Bildpalette an.
;
; R_range (der Farbverlauf einer Farbe ueber Zeilen) bekommt je Zeile einen
; eigenen Platz in Bank 3-7 (Zeilenersatz, RASTER.S); Set_fade setzt und
; blendet sie.  The drawing routines take them too: after drawing, the
; machine part moves a gradient colour to its slot (Bloecke_nacharbeiten,
; Zeichen_nacharbeiten, Bereich_nacharbeiten), and Get_block maps a slot
; back (Bereich_rueck, RASTER.S).
;
; **Ein Modul ohne Rasterliste erbt die des Moduls darunter.**  Auf dem
; Amiga bleibt dann die Copperliste stehen: Thalions Set_fade und
; Reset_current_RL tun bei Raster_list_ptr = 0 nichts.  So liegt im Kampf
; TacticSel_Mod (Zielwahl, Rasterliste 0) ueber Combat_Mod; ohne das Erben
; zeichnete Display_combat_status_icons die Leiste in Bank 0 (Savestate des
; Nutzers, 2026-10-01).
;
; **Zeichnet jemand unmittelbar in den sichtbaren Schirm** (Work_screen =
; Schirm_vorn, der Diagnoseschirm, DIAGNOSE_SUP.S), gilt die Rasterliste,
; die zuletzt gesetzt wurde (Letzte_RL, FADE_SUP.S), nicht die des Moduls:
; auf dem Amiga ist das die Copperliste, die gerade laeuft.  Out_of_memory
; setzt mit Fade_out_all die Main_RL und zeichnet dann (Erkenntnis 267).
;
; Ohne jede Rasterliste gilt Bank 0.  Zeichnet jemand in einen Hilfsschirm
; (Work_screen weder Off_screen noch Schirm_vorn, so
; Create_object_graphics), gilt ebenfalls Bank 0.  Was dort entsteht, holt Get_block mit seinen d5 Ebenen
; wieder ab, eine Bank waere ohnehin abgestreift.
;
; **Rasterbank** ist derselbe Weg ohne die Hilfsschirmpruefung: fuer den
; Mauszeiger (Zeiger_in_puffer), der immer im angezeigten Bild steht.
; Welcher Schirm gerade Work_screen ist, darf seine Farbe nicht aendern.
; ***************************************************************************
Rasterbank:
	movem.l	d1-d2/a0,-(sp)
	bsr	fbk_stapel
	movem.l	(sp)+,d1-d2/a0
	rts
Farbbank:
	movem.l	d1-d2/a0,-(sp)
	bsr	fbk_kern
	movem.l	(sp)+,d1-d2/a0
	rts

; ***************************************************************************
; Farbbank_spanne -- Farbbank, dazu wie weit sie gilt.
;
;   IN : d0.w = Bildzeile
;   OUT: d0.w = Bankversatz, d1.w = erste Zeile, ab der eine andere Bank
;        gelten kann ($FFFF: keine).  Alle uebrigen Register bleiben.
;
; **Tempo** (Messung 2026-10-02, Hatari, 2D-Karte): Farbbank kostete ein
; Drittel aller Takte, denn die Zeichenroutinen fragten fuer jede Zeile
; jeder Kachel neu und liefen jedes Mal Modulstapel und Rasterliste ab.
; Die Bank wechselt aber nur an den zwei, drei Zeilen, an denen eine
; R_palette beginnt.  Wer zeichnet, fragt also einmal und erst wieder ab
; der Grenze.  Die Grenze gilt nur fuer diesen einen Zeichenaufruf: danach
; koennen Modul, Rasterliste oder Work_screen wechseln.
; ***************************************************************************
;
; **Merker** (Messung 2026-10-02: Farbbank_spanne kostete noch 9 %, einmal
; je Kachel).  Im Normalfall -- Zeichenziel Off_screen, oberstes Modul mit
; eigener Rasterliste -- haengt das Ergebnis nur an der Liste und der
; Zeile.  Thalions Rasterlisten sind feste Daten (MODULES.S, zur Laufzeit
; schreibt niemand hinein), die Adresse der Liste genuegt also als
; Schluessel.  Gemerkt wird die Spanne von der gefragten Zeile bis zur
; Grenze.  Nur fuer die Hauptschleife: der VBL nimmt Rasterbank_spanne.
Farbbank_spanne:
	move.l	a0,-(sp)
	bsr.b	fsp_liste
	beq.b	fsp_rechnen
	cmpa.l	fsp_merk_liste,a0
	bne.b	fsp_rechnen
	cmp.w	fsp_von,d0
	bcs.b	fsp_rechnen
	cmp.w	fsp_bis,d0
	bcc.b	fsp_rechnen
	move.w	fsp_bis,d1
	move.w	fsp_bank,d0
	move.l	(sp)+,a0
	rts
fsp_rechnen:
	move.l	d2,-(sp)
	move.w	d0,-(sp)		; gefragte Zeile; fbk_kern zerstoert d2/a0
	bsr.b	fbk_kern
	move.w	(sp)+,d2
	move.l	d0,-(sp)
	bsr.b	fsp_liste
	beq.b	fsp_ohne		; kein Normalfall: nichts merken
	move.l	a0,fsp_merk_liste
	move.w	d2,fsp_von
	move.w	d1,fsp_bis
	move.l	(sp),d0
	move.w	d0,fsp_bank
fsp_ohne:
	move.l	(sp)+,d0
	move.l	(sp)+,d2
	move.l	(sp)+,a0
	rts

; a0 = Rasterliste im Normalfall (Off_screen, oberstes Modul mit eigener
; Liste), sonst 0; Z gesetzt bei 0.  Nur a0 und die Flags.
fsp_liste:
	move.l	Work_screen,a0
	cmpa.l	Off_screen,a0
	bne.b	fspl_null
	move.l	Module_Sp,a0
	cmpa.w	#0,a0
	beq.b	fspl_null
	move.l	Raster_list_ptr(a0),a0
	cmpa.w	#0,a0
	rts
fspl_null:
	suba.l	a0,a0
	cmpa.w	#0,a0
	rts

; Rasterbank_spanne -- Rasterbank mit Grenze (d1), wie Farbbank_spanne,
; ohne Merker: fuer den Mauszeiger im VBL.
Rasterbank_spanne:
	movem.l	d2/a0,-(sp)
	bsr.b	fbk_stapel
	movem.l	(sp)+,d2/a0
	rts

; Der Kern: d0 = Zeile -> d0 = Bank, d1 = Grenze; zerstoert d2/a0.
fbk_kern:
	bsr.b	Zeichenliste
	bne.b	fbk_liste
	bra	fbk_null
fbk_stapel:
	bsr.b	zl_stapel
	bne.b	fbk_liste
	bra	fbk_null

; Zeichenliste -- die Rasterliste, die fuer eine Zeichnung gilt (die
; Regeln oben bei Farbbank).  Auch Zeilenersatz (RASTER.S) fragt hier.
;   OUT: d1.l = Rasterliste oder 0, Z bei 0.  Zerstoert a0.
; zl_stapel ist derselbe Weg ohne die Schirmpruefung (Rasterbank).
Zeichenliste:
	move.l	Work_screen,d1
	cmp.l	Off_screen,d1
	beq.b	zl_stapel
	cmp.l	Schirm_vorn,d1
	bne.b	zl_null
	move.l	Letzte_RL,d1		; sichtbarer Schirm: die gesetzte Liste
	rts
zl_stapel:
	move.l	Module_Sp,d1
	beq.b	zl_raus
	move.l	d1,a0
zl_modul:
	move.l	Raster_list_ptr(a0),d1
	bne.b	zl_raus
	lea	-Module_data_size(a0),a0	; das Modul darunter
	cmpa.l	#ModStack_start,a0
	bcc.b	zl_modul
zl_null:
	moveq	#0,d1
zl_raus:
	rts
fbk_liste:
	move.l	d1,a0
	moveq	#-1,d2			; Platz, noch keiner
fbk_lauf:
	move.b	(a0),d1
	cmp.b	#RL_END,d1
	beq.b	fbk_listenende
	cmp.b	#RL_PAL,d1
	bne.b	fbk_range
	moveq	#0,d1
	move.b	1(a0),d1		; ab dieser Zeile
	cmp.w	d0,d1
	bhi.b	fbk_ende		; die Liste ist nach Zeilen geordnet; d1 = Grenze
	addq.w	#1,d2
	addq.l	#6,a0
	bra.b	fbk_lauf
fbk_range:
	addq.l	#8,a0
	bra.b	fbk_lauf
fbk_listenende:
	moveq	#-1,d1			; keine Grenze mehr
fbk_ende:
	tst.w	d2
	bmi.b	fbk_bank0		; Zeile vor der ersten Palette
	cmp.w	#PLAETZE,d2
	bcc.b	fbk_bank0
	add.w	d2,d2
	lea	Platzbank,a0
	move.w	0(a0,d2.w),d0
	rts
fbk_null:
	moveq	#-1,d1			; ohne Liste gilt Bank 0 ueberall
fbk_bank0:
	moveq	#0,d0
	rts

; ***************************************************************************
; Zeilenfarbe -- eine Farbe Thalions in die Bank einer Bildzeile legen.
;
;   IN : d0.w = Bildzeile, d1.w = Farbe
;   OUT: d1.w = Farbe in der Bank dieser Zeile
;   Alle uebrigen Register bleiben.
;
; Dieselbe Regel wie in Put_unmasked_block und Put_masked_block2: Farbe =
; Farbbank(y) + Wert, **0 bleibt 0**.  Wer sie nicht einhaelt, zeichnet in
; einer Zeile mit Main_pal die Farbe aus Bank 0 -- und Get_block, das mit
; d5 = 5 nur die unteren fuenf Ebenen sichert, gaebe beim Zuruecksetzen eine
; andere Farbe zurueck (Erkenntnis 191).
;
; Farben ab 32 gelten als fertig: die kennt Thalions Code nicht, die setzt
; nur unsere Bibliothek, und die meint sie so.
;
; In the machine part: FALCON_LIB.S (the bank), ST_LIB.S (the register
; table).
; ***************************************************************************

; ***************************************************************************
; Ein Zeichen setzen.  a1 = Muster, d6 = Zeilen, Lage aus txt_x/txt_y.
;
; Acht Ebenen, wortweise verschachtelt: ein Zeichen ist acht Pixel breit und
; sitzt selten auf einer Blockgrenze, faellt also in zwei Sechzehnerbloecke.
; Das Muster wird deshalb in ein Langwort geschoben -- oberes Wort in den
; ersten Block, unteres in den zweiten.  Je Ebene wird verodert, wenn das
; Farbbit gesetzt ist, sonst mit dem Gegenteil verundet; damit stimmt die
; Farbe auch dann, wenn Text auf gefuelltem Grund steht.
;
; Die beiden Bloecke stehen ausgeschrieben da statt in einer Schleife: so
; gibt es keine Aufrufgrenze, ueber die ein Register verlorengehen koennte.
;
; Gezeichnet wird zweimal: erst der Schatten, um ein Pixel nach rechts und
; unten versetzt, dann die Schrift darueber.  Im Original steht die Farbe
; dafuer in Shadow_colour; sie kommt aus der Ausgabeflaeche (PA_Shadow) und
; ist ueblicherweise Default_shadow, also 0.  Der Wert -1 schaltet den
; Schatten ab.
; ***************************************************************************
Put_char:
	movem.l	d0/a0-a1,-(sp)
	move.w	Shadow_colour,d0
	bmi.b	pc_ink			; -1: ohne Schatten
	move.w	d0,v_colour(a5)
	addq.w	#1,txt_x(a5)
	addq.w	#1,txt_y(a5)
	bsr	Put_char_at
	subq.w	#1,txt_x(a5)
	subq.w	#1,txt_y(a5)
pc_ink:
	move.w	Ink_colour,d0
	move.w	d0,v_colour(a5)
	bsr	Put_char_at
	movem.l	(sp)+,d0/a0-a1
	rts

; ***************************************************************************
; Ein Zeichen in einer Farbe setzen.  a1 = Muster, d6 = Zeilen, Lage aus
; txt_x/txt_y, Farbe aus v_colour.
;
; **Beschnitten gegen die oberste CA, wie Thalions Put_text_line**
; (AM2_CPU 0:$239A8, Erkenntnis 259).  Thalion setzt die ganze Zeile erst in
; einen Hilfspuffer und schneidet dann: senkrecht zeilengenau, seitlich nur
; ganze Sechzehnerbloecke, die ganz ausserhalb X1..X2 liegen.  Wir schneiden
; je Zeichen genauso: Zeilen ausserhalb Y1..Y2 fallen weg, und jeder der
; beiden Bloecke wird nur geschrieben, wenn er X1..X2 beruehrt (Bit 8 und 9
; in d3; lsl.l nimmt vom Zaehler nur die Bits 0-5).  Der Schatten ist ein
; eigener Aufruf eine Zeile tiefer und wird so mitbeschnitten.
; ***************************************************************************
Put_char_at:
	movem.l	d0-d7/a0-a2,-(sp)
	move.l	CA_Sp,a2
	move.l	(a2),a2			; oberster CA-Satz
	; ---- senkrecht: Zeilen ausserhalb Y1..Y2 weglassen ----
	move.w	CA_Y1(a2),d5
	bpl.b	pa_y1
	moveq	#0,d5
pa_y1:	move.w	CA_Y2(a2),d0
	cmp.w	#SCRH-1,d0
	ble.b	pa_y2
	move.w	#SCRH-1,d0
pa_y2:	move.w	txt_y(a5),d7		; erste Zeile
	move.w	d7,d4
	add.w	d6,d4
	subq.w	#1,d4			; letzte Zeile
	cmp.w	d0,d4
	ble.b	pa_unten
	move.w	d0,d4			; unten abschneiden
pa_unten:
	sub.w	d7,d5			; Zeilen ueber Y1
	ble.b	pa_oben
	add.w	d5,d7			; oben abschneiden
	adda.w	d5,a1			; eine Musterzeile je Bildzeile
pa_oben:
	sub.w	d7,d4			; Zeilenzaehler
	bmi	pg_aus			; ganz ausserhalb
	move.w	d7,d0
	mulu.w	#SCRROW,d0
	move.w	txt_x(a5),d1
	move.w	d1,d2
	lsr.w	#4,d2
	mulu.w	#TROW,d2
	add.l	d2,d0
	move.l	Work_screen,a0
	add.l	d0,a0			; a0 = erster Block der ersten Zeile
	and.w	#15,d1
	moveq	#24,d3
	sub.w	d1,d3			; Schiebeweite ins Langwort
	; ---- seitlich: je Sechzehnerblock, ob er X1..X2 beruehrt ----
	move.w	CA_X1(a2),d5
	bpl.b	pa_x1
	moveq	#0,d5
pa_x1:	move.w	CA_X2(a2),d6
	cmp.w	#SCRW-1,d6
	ble.b	pa_x2
	move.w	#SCRW-1,d6
pa_x2:	move.w	txt_x(a5),d7
	and.w	#-16,d7			; erster Block
	cmp.w	d6,d7
	bgt.b	pa_b1
	move.w	d7,d0
	add.w	#15,d0
	cmp.w	d5,d0
	blt.b	pa_b1
	bset	#8,d3			; erster Block wird geschrieben
pa_b1:	add.w	#16,d7			; zweiter Block
	cmp.w	d6,d7
	bgt.b	pa_b2
	move.w	d7,d0
	add.w	#15,d0
	cmp.w	d5,d0
	blt.b	pa_b2
	bset	#9,d3			; zweiter Block wird geschrieben
pa_b2:
	; Farbe dieses Durchgangs, in der Bank der obersten Zeile (ein
	; Zeichen ist sieben Zeilen hoch; eine Bankgrenze mitten hindurch
	; kommt nicht vor, die Textflaechen liegen innerhalb eines Bereichs)
	move.w	txt_y(a5),d0
	move.w	v_colour(a5),d1
	bsr	Zeilenfarbe
	move.w	d1,d2
pg_row:
	moveq	#0,d6
	move.b	(a1)+,d6
	beq	pg_next			; leere Zeile: nichts zu tun
	lsl.l	d3,d6			; d6 bleibt bis zum Zeilenende stehen
	; ---- erster Block: oberes Wort ----
	btst	#8,d3
	beq.b	pg_snd			; ausserhalb der CA
	move.l	d6,d5
	swap	d5
	tst.w	d5
	beq.b	pg_snd
	move.l	a0,a2
	moveq	#0,d1
pg_p1:	btst	d1,d2
	beq.b	pg_c1
	or.w	d5,(a2)
	bra.b	pg_n1
pg_c1:	move.w	d5,d7
	not.w	d7
	and.w	d7,(a2)
pg_n1:	addq.l	#2,a2
	addq.w	#1,d1
	cmp.w	#PLANES,d1
	bne.b	pg_p1
	; ---- zweiter Block: unteres Wort, nur wenn das Zeichen hinueberragt ----
pg_snd:
	btst	#9,d3
	beq.b	pg_next			; ausserhalb der CA
	move.w	d6,d5
	beq.b	pg_next
	lea	TROW(a0),a2
	moveq	#0,d1
pg_p2:	btst	d1,d2
	beq.b	pg_c2
	or.w	d5,(a2)
	bra.b	pg_n2
pg_c2:	move.w	d5,d7
	not.w	d7
	and.w	d7,(a2)
pg_n2:	addq.l	#2,a2
	addq.w	#1,d1
	cmp.w	#PLANES,d1
	bne.b	pg_p2
pg_next:
	lea	SCRROW(a0),a0
	dbf	d4,pg_row
pg_aus:
	movem.l	(sp)+,d0-d7/a0-a2
	jmp	Zeichen_nacharbeiten	; machine part: R_range afterwork

; ***************************************************************************
; Draw_box -- fill a rectangle with one colour.
;   IN : d0.w/d1.w = one corner, d2.w/d3.w = the opposite corner (both
;        inclusive, any order: two corners, not position and size),
;        d4.w = Thalion's colour number (the bank of each line comes on
;        top, 0 stays 0)
;   All registers are preserved.
;
; Acht Ebenen: je Ebene ist das Muster fuer 16 Pixel entweder $0000 oder
; $FFFF, je nachdem ob das Farbbit gesetzt ist.  Randbloecke werden ueber
; eine Maske behandelt.
;
; **Beschnitten gegen die oberste CA, wie Thalions Draw_box** (AM2_CPU
; 0:$21E64, Erkenntnis 259): Ecken ordnen, dann auf X1..X2/Y1..Y2 klemmen;
; liegt danach links hinter rechts oder oben unter unten, lag der Kasten
; ganz ausserhalb.  Zusaetzlich auf den Schirm begrenzt wie
; Block_beschneiden.  Automap: Thalions Display_automap legt Automap_CA auf
; und zeichnet Papier und Kartennamen relativ zur Rollage; ohne den Schnitt
; standen beide in der Portraitleiste.
; ***************************************************************************
Draw_box:
	movem.l	d0-d7/a0-a3,-(sp)
	cmp.w	d0,d2
	bge.b	fb_ox
	exg	d0,d2
fb_ox:	cmp.w	d1,d3
	bge.b	fb_oy
	exg	d1,d3
fb_oy:	move.l	CA_Sp,a0
	move.l	(a0),a0			; oberster CA-Satz
	move.w	CA_X1(a0),d5
	bpl.b	fb_x1
	moveq	#0,d5
fb_x1:	cmp.w	d5,d0
	bge.b	fb_x1k
	move.w	d5,d0
fb_x1k:	move.w	CA_X2(a0),d5
	cmp.w	#SCRW-1,d5
	ble.b	fb_x2
	move.w	#SCRW-1,d5
fb_x2:	cmp.w	d5,d2
	ble.b	fb_x2k
	move.w	d5,d2
fb_x2k:	move.w	CA_Y1(a0),d5
	bpl.b	fb_y1
	moveq	#0,d5
fb_y1:	cmp.w	d5,d1
	bge.b	fb_y1k
	move.w	d5,d1
fb_y1k:	move.w	CA_Y2(a0),d5
	cmp.w	#SCRH-1,d5
	ble.b	fb_y2
	move.w	#SCRH-1,d5
fb_y2:	cmp.w	d5,d3
	ble.b	fb_y2k
	move.w	d5,d3
fb_y2k:	cmp.w	d0,d2
	blt	fb_out			; ganz links oder rechts daneben
	cmp.w	d1,d3
	blt	fb_out			; ganz ober- oder unterhalb
	move.w	d1,a2			; Bildzeile, fuer die Farbbank
	move.w	d4,a3			; Farbe, wie Thalion sie meint
	sub.w	d0,d2
	addq.w	#1,d2			; Breite in Pixeln
	sub.w	d1,d3
	addq.w	#1,d3			; Hoehe
	move.l	Work_screen,a0
	mulu.w	#SCRROW,d1
	add.l	d1,a0
	move.w	d0,d5
	lsr.w	#4,d5
	mulu.w	#TROW,d5
	add.l	d5,a0			; erster Block
	and.w	#15,d0			; Versatz im Block
	subq.w	#1,d3
	bmi	fb_out
	; The machine part: the fill (Box_fuellen; FALCON_LIB.S: the bank per
	; span; ST_LIB.S: whole blocks, the register per line)
	bsr	Box_fuellen
fb_out:
	movem.l	(sp)+,d0-d7/a0-a3
	jsr	Bereich_nacharbeiten	; machine part: R_range, the corners d0-d3 as called
	rts


; ***************************************************************************
; Clear_screen -- fill a whole screen with colour 0.
;   IN : a0 = screen
;   All registers are preserved.
;
; Sein Vertrag steht in HULL/FADE.S: "move.l Off_screen,a0 / jsr
; Clear_screen".  Bis 2026-09-25 loeschte unsere Fassung immer p_buf und
; uebersah a0.
; ***************************************************************************
Clear_screen:
	movem.l	d0-d1/a0,-(sp)
	move.w	#(SCRSZ/4)-1,d0
	moveq	#0,d1
cb1:	move.l	d1,(a0)+
	dbf	d0,cb1
	movem.l	(sp)+,d0-d1/a0
	rts

; ***************************************************************************
; Der Doppelpuffer -- Update_screen, Switch_screens, Copy_screen und
; Duplicate_block des Originals (Erkenntnis 200, 258).
;
; **Zwei Schirme wie bei Thalion** (AM2_CPU 1.20, 0:$2137A-$21708):
; Schirm_vorn wird angezeigt, Off_screen ist der hintere, Work_screen das
; Zeichenziel.  Ein Wechsel zeichnet die HDOBs in den hinteren Schirm,
; tauscht, wartet den Bildwechsel ab und loescht die HDOBs im neuen hinteren
; wieder.  Update_screen kopiert danach den sichtbaren Schirm nach hinten
; (Copy_screen), Switch_screens nicht: in dessen Schleifen (Karte, 3D,
; Kampf) zeichnet Thalions Code den bewegten Teil jedes Bild neu, und der
; hintere Schirm ist zwei Bilder alt.  Zuletzt Thalions ScrQ_handler, wie im
; Original *nach* dem Tausch.
;
; **Der Mauszeiger** ist auf dem Amiga ein Sprite und kommt dort nicht vor.
; Bei uns ist er Teil des Bildes und laeuft wie ein HDOB mit: vor dem Tausch
; in den hinteren Schirm, danach im neuen hinteren wieder heraus, mit einem
; gesicherten Hintergrund je Schirm (zeiger_saetze).  So steht er in jedem
; angezeigten Bild, und kein Schirm behaelt einen Zeigerabdruck.
;
; a5 holt sich jede Routine selbst: Thalions Drop_HDOB ruft Switch_screens
; mit a5 auf einem lokalen Rahmen (Erkenntnis 177).  Alle Register bleiben.
; ***************************************************************************
Update_screen:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	vars,a5
	tst.l	Schirm_vorn
	beq.b	us_ende
	bsr	Schirmwechsel
	bsr	Copy_screen
	jsr	ScrQ_handler
us_ende:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; Switch_screens -- show the back screen; without copying it back
; (above).
;   All registers are preserved.
Switch_screens:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	vars,a5
	tst.l	Schirm_vorn
	beq.b	ss_ende
	bsr	Schirmwechsel
	jsr	ScrQ_handler
	IFD	ABSTURZTEST
	bsr	Absturz_pruefen		; Diagnose: Bomben fuer den Notausgang (MAIN.S)
	ENDC
ss_ende:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ---- der gemeinsame Teil (0:$2137C-$213AE) ----
; Der Zeigersatz des sichtbaren Schirms wechselt hier den Besitzer; solange
; darf Zeiger_vbl nicht nachfuehren (zeiger_sperre).
Schirmwechsel:
	IFD	ZEIGERTAKT
	bsr	Zeigertakt_zeigen
	ENDC
	addq.b	#1,zeiger_sperre
	jsr	Draw_HDOBs		; in den hinteren Schirm
	bsr	Zeiger_hinten_zeichnen	; darueber der Zeiger
	move.l	Off_screen,d0		; tauschen
	move.l	Schirm_vorn,Off_screen
	move.l	d0,Schirm_vorn
	bsr	Anzeige_setzen		; zeigen und den Bildwechsel abwarten
	move.l	Off_screen,Work_screen
	not.b	Screen_flag
	; Im neuen hinteren wieder heraus, **umgekehrt zum Zeichnen**: erst der
	; Zeiger, dann die HDOBs.  Der Hintergrund des Zeigers enthaelt den
	; HDOB darunter; kaeme er zuletzt zurueck, bliebe von einem gezogenen
	; Gegenstand je Bild ein Stueck stehen -- eine Spur (2026-09-29).
	bsr	Zeiger_hinten_weg
	subq.b	#1,zeiger_sperre
	jmp	Erase_HDOBs

	IFD	ZEIGERTAKT
; ***************************************************************************
; Zeigertakt_zeigen -- Diagnose, Schalter ZEIGERTAKT (Erkenntnis 269).
;
; Wie viele Bilder liegen zwischen zwei Schirmwechseln?  So oft kam der
; Zeiger vor 269 voran.  Oben links im hinteren Schirm zwei Balken, je Bild
; ein Block (zwoelf Punkte hell, vier frei): Zeilen 0-1 der letzte Abstand,
; Zeilen 3-4 der groesste in einer Sekunde (50 Bilder).  Farbe 31 der Bank
; der Zeile.  Der Balken bleibt im Schirm stehen; nur fuer den Diagnosebau.
; Alle Register bleiben.
; ***************************************************************************
Zeigertakt_zeigen:
	movem.l	d0-d1,-(sp)
	move.w	VBL_counter,d0
	move.w	d0,d1
	sub.w	zt_letzt,d0		; Bilder seit dem letzten Wechsel
	move.w	d1,zt_letzt
	sub.w	zt_fenster,d1		; eine Sekunde um?
	cmp.w	#50,d1
	bcs.b	ztz_f
	move.w	VBL_counter,zt_fenster
	clr.w	zt_max
ztz_f:	cmp.w	zt_max,d0
	bls.b	ztz_m
	move.w	d0,zt_max
ztz_m:	moveq	#0,d1
	bsr.b	Zeigertakt_balken
	moveq	#1,d1
	bsr.b	Zeigertakt_balken
	move.w	zt_max,d0
	moveq	#3,d1
	bsr.b	Zeigertakt_balken
	moveq	#4,d1
	bsr.b	Zeigertakt_balken
	movem.l	(sp)+,d0-d1
	rts

; d0 = Laenge in Bloecken, d1 = Zeile im hinteren Schirm
Zeigertakt_balken:
	movem.l	d0-d4/a0,-(sp)
	move.w	d0,d3			; Laenge, hoechstens eine Zeile
	cmp.w	#SCRW/16,d3
	bls.b	ztb_l
	move.w	#SCRW/16,d3
ztb_l:	move.l	Off_screen,a0
	move.w	d1,d2
	mulu.w	#SCRROW,d2
	add.l	d2,a0
	move.w	d1,d0
	bsr	Rasterbank		; d0 = Farbversatz der Bank
	or.w	#31,d0
	moveq	#SCRW/16-1,d1
ztb_block:
	moveq	#0,d2			; Muster dieses Blocks
	tst.w	d3
	beq.b	ztb_leer
	subq.w	#1,d3
	move.w	#$FFF0,d2
ztb_leer:
	moveq	#0,d4			; Ebene
ztb_ebene:
	btst	d4,d0
	beq.b	ztb_null
	move.w	d2,(a0)+
	bra.b	ztb_weiter
ztb_null:
	clr.w	(a0)+
ztb_weiter:
	addq.w	#1,d4
	cmp.w	#PLANES,d4
	bne.b	ztb_ebene
	dbf	d1,ztb_block
	movem.l	(sp)+,d0-d4/a0
	rts

	SECTION	Fast_BSS,bss
zt_letzt:	ds.w	1		; VBL_counter beim letzten Wechsel
zt_fenster:	ds.w	1		; Beginn der laufenden Sekunde
zt_max:		ds.w	1		; groesster Abstand darin
	SECTION	Program,code
	ENDC

; ***************************************************************************
; Anzeige_setzen -- den neuen Schirm anzeigen und warten, bis er es ist
; (0:$21436, dort ueber die Copperliste und 0:$21528).  Erst danach darf in
; den bisher sichtbaren Schirm gezeichnet werden, sonst reisst das Bild.
;
; Die Videobasis wird sofort geschrieben; die Hardware uebernimmt sie zu
; Beginn des naechsten Bildes.  Wechselt danach VBL_counter, ist das Bild
; mit dem neuen Schirm angefangen -- oder, falls die Uebernahme erst nach dem
; VBL kommt, liegt das Bild noch im Austastbereich.  Beides ist sicher.
; ***************************************************************************
Anzeige_setzen:
	move.w	d0,-(sp)
	move.w	VBL_counter,d0
	bsr	Basis_setzen
	tst.b	Schirme_an		; ohne unseren Schirm kein Warten
	beq.b	as_out
as_warten:
	cmp.w	VBL_counter,d0
	beq.b	as_warten
as_out:	move.w	(sp)+,d0
	rts

; ***************************************************************************
; Basis_setzen -- die Videobasis aus Schirm_vorn und Vertical_screen_offset.
;
; Das Bildschuetteln (COMBAT_M.S, REVERSE_.S) setzt Vertical_screen_offset
; auf -3..+4 Zeilen; auf dem Amiga schiebt der Copper damit das Bildfenster
; (0:$21280).  Hier wandert die Basis um so viele Zeilen zurueck, das Bild
; also nach unten, und der Rand zeigt die schwarzen Zeilen, die
; Bildpuffer_anlegen um jeden Schirm gelegt hat (SCHIRM_RAND).  Die
; Farbbaenke stecken in den Punkten und wandern mit.
;
; Gerufen beim Tausch und in jedem Bild aus Bibliothek_vbl.  Supervisor.
; Alle Register bleiben.
; ***************************************************************************
Basis_setzen:
	movem.l	d0-d1,-(sp)
	tst.b	Schirme_an
	beq.b	bs_ende
	move.l	Schirm_vorn,d0
	beq.b	bs_ende
	move.w	Vertical_screen_offset,d1
	; The low byte of the video base exists from the STE on (Feinbasis,
	; cleared by ST.S on a plain ST).  Without it the shake would go in
	; steps of 256 bytes only; it is left out.
	tst.b	Feinbasis
	bne.b	bs_fein
	moveq	#0,d1
bs_fein:
	cmp.w	#-SCHIRM_RAND,d1	; nicht ueber den Rand hinaus
	bge.b	bs_o1
	moveq	#-SCHIRM_RAND,d1
bs_o1:	cmp.w	#SCHIRM_RAND,d1
	ble.b	bs_o2
	moveq	#SCHIRM_RAND,d1
bs_o2:	muls.w	#SCRROW,d1
	sub.l	d1,d0
	move.l	d0,d1
	lsr.l	#8,d1			; Bits 8-15 unten
	move.b	d1,-(sp)		; mittleres Byte merken
	lsr.w	#8,d1			; Bits 16-23 unten
	move.b	d1,VIDEO_BASE_H.w	; oben, Mitte, unten -- in dieser
	move.b	(sp)+,VIDEO_BASE_M.w	; Folge, denn H und M loeschen L
	tst.b	Feinbasis		; plain ST: no low byte (bus error)
	beq.b	bs_ende
	move.b	d0,VIDEO_BASE_L.w
bs_ende:
	movem.l	(sp)+,d0-d1
	rts

	SECTION	Fast_DATA,data
Feinbasis:	dc.b	-1		; set: the video base has its low byte
	even				; (Falcon, STE and later; ST.S clears it)
	SECTION	Program,code

; ***************************************************************************
; Copy_screen -- the shown screen whole into the back one (0:$21456).
;   All registers are preserved.
;
; Thalion ruft es selbst (DISPLAY.S, 3D_MAP.S "The end", WORDS.S "Wait"),
; wenn der hintere Schirm veraltet ist.  Mitkopiert werden die HDOBs und der
; Zeiger, die im sichtbaren Schirm stehen; beide kommen im hinteren gleich
; wieder heraus, mit den Hintergruenden des *sichtbaren* Schirms -- dafuer
; schlaegt Screen_flag kurz um, genau wie bei Thalion.
; ***************************************************************************
Copy_screen:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	vars,a5
	addq.b	#1,zeiger_sperre	; der Zeiger vorn bleibt, wo er ist
	move.l	Schirm_vorn,d0
	beq.b	cs_ende
	move.l	d0,a0
	move.l	Off_screen,a1
	move.w	#SCRSZ/32-1,d7
cs_l:	movem.l	(a0)+,d0-d6/a2
	movem.l	d0-d6/a2,(a1)
	lea	32(a1),a1
	dbf	d7,cs_l
	; Umgekehrt zum Zeichnen: erst der Zeiger, dann die HDOBs (Schirmwechsel).
	bsr	Zeiger_satz_vorn	; Zeiger mit dem Hintergrund von vorn
	tst.b	ZS_DA(a2)
	beq.b	cs_hdobs
	move.l	Off_screen,zg_schirm
	move.l	ZS_BG(a2),zg_bg
	move.w	ZS_X(a2),d0
	move.w	ZS_Y(a2),d1
	bsr	Zeiger_aus_puffer
cs_hdobs:
	not.b	Screen_flag		; HDOBs ebenso
	jsr	Erase_HDOBs
	not.b	Screen_flag
cs_ende:
	subq.b	#1,zeiger_sperre
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Duplicate_block -- a rectangle from the shown screen into the back one
; (0:$215F0).  Combat brings changed areas level with it (COMOBS.S
; Draw_combat_screen).
;   IN : d0.w/d1.w = top left corner (x rounded down to 16), d5.w = planes,
;        1 to Screen_depth (else nothing happens), d6.w = width in 16-pixel
;        blocks, d7.w = height in lines
;   All registers are preserved.
;
; Beschnitten gegen die oberste CA, mit Thalions Rechnung.  Kopiert werden
; bei uns immer alle acht Ebenen: die oberen tragen die Farbbank.  Steht der
; Zeiger im Rechteck, kommt sein Abdruck im hinteren Schirm wieder heraus.
; Alle Register bleiben.
; ***************************************************************************
Duplicate_block:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	vars,a5
	addq.b	#1,zeiger_sperre	; der Zeiger vorn bleibt, wo er ist
	tst.l	Schirm_vorn
	beq	db_ende
	tst.w	d5
	ble	db_ende
	cmp.w	#Screen_depth,d5
	bgt	db_ende
	and.w	#-16,d0
	move.l	CA_Sp,a1
	move.l	(a1),a1			; oberste CA
	cmp.w	CA_X2(a1),d0
	bgt	db_ende
	cmp.w	CA_Y2(a1),d1
	bgt	db_ende
	move.w	d6,d2			; rechte Kante
	lsl.w	#4,d2
	add.w	d0,d2
	subq.w	#1,d2
	cmp.w	CA_X1(a1),d2
	bmi	db_ende
	move.w	d1,d3			; untere Kante
	add.w	d7,d3
	subq.w	#1,d3
	cmp.w	CA_Y1(a1),d3
	bmi	db_ende
	cmp.w	CA_Y1(a1),d1		; oben beschneiden
	bpl.b	db_o
	move.w	CA_Y1(a1),d4
	sub.w	d1,d4
	sub.w	d4,d7
	move.w	CA_Y1(a1),d1
db_o:	cmp.w	CA_Y2(a1),d3		; unten
	bmi.b	db_u
	sub.w	CA_Y2(a1),d3
	sub.w	d3,d7
db_u:	cmp.w	CA_X1(a1),d0		; links
	bpl.b	db_l
	move.w	CA_X1(a1),d4
	sub.w	d0,d4
	lsr.w	#4,d4
	sub.w	d4,d6
	move.w	CA_X1(a1),d0
db_l:	cmp.w	CA_X2(a1),d2		; rechts
	ble.b	db_r
	sub.w	CA_X2(a1),d2
	lsr.w	#4,d2
	sub.w	d2,d6
db_r:	tst.w	d6
	bne.b	db_b
	moveq	#1,d6
db_b:	tst.w	d7
	ble	db_ende
	lsr.w	#4,d0			; Block
	move.w	d0,d4			; merken fuer den Zeiger
	move.w	d1,d5
	move.l	Schirm_vorn,a0		; Quelle
	move.l	Off_screen,a1		; Ziel
	move.w	d1,d2
	mulu.w	#SCRROW,d2
	add.l	d2,a0
	add.l	d2,a1
	move.w	d0,d2
	mulu.w	#TROW,d2
	add.l	d2,a0
	add.l	d2,a1
	move.w	d7,d3
	subq.w	#1,d3			; Zeilen - 1
db_z:	move.l	a0,a2
	move.l	a1,a3
	move.w	d6,d2
	subq.w	#1,d2			; Bloecke - 1
db_bl:
	REPT	TROW/4			; ein Block: PLANES Ebenen, TROW Byte
	move.l	(a2)+,(a3)+
	ENDR
	dbf	d2,db_bl
	lea	SCRROW(a0),a0
	lea	SCRROW(a1),a1
	dbf	d3,db_z
	; ---- Zeigerabdruck im Rechteck wieder heraus ----
	bsr	Zeiger_satz_vorn
	tst.b	ZS_DA(a2)
	beq.b	db_ende
	move.w	d4,d2			; Bloecke d2..d3
	move.w	d4,d3
	add.w	d6,d3
	subq.w	#1,d3
	move.w	d5,d4			; Zeilen d4..d5
	add.w	d7,d5
	subq.w	#1,d5
	move.l	Off_screen,zg_schirm
	move.l	ZS_BG(a2),zg_bg
	move.w	ZS_X(a2),d0
	move.w	ZS_Y(a2),d1
	bsr	Zeiger_aus_rechteck
db_ende:
	subq.b	#1,zeiger_sperre
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Die Zeigersaetze: a2 = der des hinteren bzw. des sichtbaren Schirms.
; Satz 1 gehoert dem Schirm, der bei gesetztem Screen_flag hinten ist --
; dieselbe Wahl wie HDOB_screen1/2 in Thalions HDOBS.S.
; ***************************************************************************
Zeiger_satz_hinten:
	lea	zeiger_saetze,a2
	tst.b	Screen_flag
	beq.b	zsh_out
	lea	ZS_SIZE(a2),a2
zsh_out:
	rts

Zeiger_satz_vorn:
	lea	zeiger_saetze,a2
	tst.b	Screen_flag
	bne.b	zsv_out
	lea	ZS_SIZE(a2),a2
zsv_out:
	rts

; ---- vor dem Tausch: den Zeiger in den hinteren Schirm ----
Zeiger_hinten_zeichnen:
	movem.l	d0-d3/a2,-(sp)
	bsr	Zeiger_satz_hinten
	sf	ZS_DA(a2)
	tst.b	maus_aus		; Mouse_off ?  Dann ohne Zeiger
	bne.b	zhz_out
	tst.l	p_mptr(a5)		; Zeigerbild da ?
	beq.b	zhz_out
	move.w	sr,d3
	move.w	#$2700,sr
	move.w	Mouse_X,d0
	move.w	Mouse_Y,d1
	move.w	d3,sr
	bsr	Zeigerecke
	sf	zg_neu			; der Zeiger kommt jetzt ganz neu
	move.l	Off_screen,zg_schirm
	move.l	ZS_BG(a2),zg_bg
	bsr	Zeiger_in_puffer
	move.w	d0,ZS_X(a2)
	move.w	d1,ZS_Y(a2)
	st	ZS_DA(a2)
zhz_out:
	movem.l	(sp)+,d0-d3/a2
	rts

; ---- nach dem Tausch: im neuen hinteren wieder heraus ----
Zeiger_hinten_weg:
	movem.l	d0-d1/a2,-(sp)
	bsr	Zeiger_satz_hinten
	tst.b	ZS_DA(a2)
	beq.b	zhw_out
	sf	ZS_DA(a2)
	move.l	Off_screen,zg_schirm
	move.l	ZS_BG(a2),zg_bg
	move.w	ZS_X(a2),d0
	move.w	ZS_Y(a2),d1
	bsr	Zeiger_aus_puffer
zhw_out:
	movem.l	(sp)+,d0-d1/a2
	rts

; ***************************************************************************
; Zeiger nachfuehren -- im VBL, wie das Sprite des Originals (Erkenntnis 269).
;
; Auf dem Amiga ist der Zeiger ein Hardwaresprite: die Bibliothek setzt
; seine Lage in jedem Bild, gleich wie lange das Spiel an einem Bild
; zeichnet.  Bis 2026-10-02 wanderte er bei uns nur mit dem Schirmwechsel
; mit; auf der Karte, wo ein Bild mehrere VBLs braucht, ruckelte er und hing
; nach (Befund des Nutzers).  Jetzt fuehrt Zeiger_vbl ihn in jedem Bild im
; sichtbaren Schirm nach.
;
; **Die Sperre.**  Der VBL kommt mitten in den Code.  Wer den sichtbaren
; Schirm samt Zeiger liest oder den Zeigersatz von vorn benutzt, zaehlt
; zeiger_sperre hoch und danach herunter: Schirmwechsel, Copy_screen,
; Duplicate_block, Set_mouse_ptr, Update_mouse.  Solange laesst der VBL den
; Zeiger stehen und holt ihn im naechsten Bild nach.  Ebenso, solange in den
; sichtbaren Schirm gezeichnet wird (Work_screen = Schirm_vorn, der
; Diagnoseschirm): der gesicherte Hintergrund waere dort veraltet.
;
; Zeiger_vbl: aus Bibliothek_vbl, Supervisor.  Alle Register bleiben.
; ***************************************************************************
Zeiger_vbl:
	tst.b	zeiger_sperre
	bne.b	zv_out
	tst.b	Schirme_an
	beq.b	zv_out
	move.l	d0,-(sp)
	move.l	Work_screen,d0
	cmp.l	Schirm_vorn,d0
	beq.b	zv_raus			; dort wird gerade gezeichnet
	move.l	a5,-(sp)
	lea	vars,a5
	bsr.b	Zeiger_nachfuehren
	move.l	(sp)+,a5
zv_raus:
	move.l	(sp)+,d0
zv_out:	rts

; ***************************************************************************
; Update_mouse -- der Name des Originals.  Thalions Code ruft ihn nicht (dort
; fuehrt die Bibliothek das Sprite im Interrupt); unsere Warteschleifen
; (Startmenue, Wait_key) rufen ihn noch, unter der Sperre.  Seit Zeiger_vbl
; waere es nicht mehr noetig, schadet aber nicht.  Alle Register bleiben.
; ***************************************************************************
Update_mouse:
	addq.b	#1,zeiger_sperre
	bsr.b	Zeiger_nachfuehren
	subq.b	#1,zeiger_sperre
	rts

; ***************************************************************************
; Zeiger_nachfuehren -- den Zeiger im sichtbaren Schirm an die Mausstelle.
;
; Es zeichnet **im sichtbaren Schirm**, denn der hintere kann gerade
; halbfertig sein.  Dabei darf der Zeiger keinen Augenblick fehlen -- eine
; Luecke von gut hundert Mikrosekunden hat hier frueher geflackert, im
; obersten Bilddrittel, wo der Rasterstrahl nach dem Bildwechsel steht.
; Darum:
;   * liegen alter und neuer Fleck in getrennten Zeilen, kommt erst der
;     neue ins Bild (sein Hintergrund in den freien Satz), dann geht der
;     alte heraus;
;   * teilen sie sich Zeilen, werden diese Zeilen im Zwischenstueck
;     (zg_zwischen) zusammengesetzt und in einem Zug zurueckgeschrieben --
;     nur die Bloecke, die einer der beiden Flecke beruehrt (seit 269: im
;     VBL zaehlt jeder Takt; ganze Zeilen waeren 20 KB je Bild).
; a5 = vars.  Alle Register bleiben.
; ***************************************************************************
Zeiger_nachfuehren:
	movem.l	d0-d7/a0-a3,-(sp)
	tst.l	Schirm_vorn
	beq	um_out
	tst.b	maus_aus		; Mouse_off ?  Dann nicht zeichnen
	bne	um_out
	tst.l	p_mptr(a5)
	beq	um_out
	bsr	Maus_eingrenzen		; die Area kann sich geaendert haben
	move.w	sr,d3			; Position einmal holen und festhalten
	move.w	#$2700,sr
	move.w	Mouse_X,d0
	move.w	Mouse_Y,d1
	move.w	d3,sr
	bsr	Zeigerecke		; ab hier die Ecke des Bilds
	bsr	Zeiger_satz_vorn
	tst.b	ZS_DA(a2)		; steht schon einer da ?
	beq	um_frisch
	tst.b	zg_neu			; neues Bild (Set_mouse_ptr) ?
	bne.b	um_neu
	cmp.w	ZS_X(a2),d0		; an derselben Stelle ?
	bne.b	um_neu
	cmp.w	ZS_Y(a2),d1
	beq	um_out			; dann ist nichts zu tun
um_neu:
	sf	zg_neu
	move.w	d0,d6			; neue Ecke
	move.w	d1,d7
	move.w	ZS_X(a2),d0		; Zeile des alten Flecks
	move.w	ZS_Y(a2),d1
	bsr	Fleck_lage
	move.w	d3,d4
	move.w	d2,um_block		; sein erster Block
	move.w	d6,d0			; Zeile des neuen
	move.w	d7,d1
	bsr	Fleck_lage
	move.w	d3,d5
	sub.w	d4,d5			; Abstand der Zeilen
	bpl.b	um_abs
	neg.w	d5
um_abs:	cmp.w	#MPTR_H,d5
	blt.b	um_zwischen
	; ---- getrennte Zeilen: erst der neue, dann der alte heraus ----
	move.l	Schirm_vorn,zg_schirm
	move.l	zg_frei,zg_bg
	move.w	d6,d0
	move.w	d7,d1
	bsr	Zeiger_in_puffer
	move.l	ZS_BG(a2),zg_bg
	move.w	ZS_X(a2),d0
	move.w	ZS_Y(a2),d1
	bsr	Zeiger_aus_puffer
	bra	um_tausch
um_zwischen:
	; ---- gemeinsame Zeilen: im Zwischenstueck zusammensetzen ----
	; Bloecke: vom kleineren ersten Block bis zum groesseren plus eins
	; (jeder Fleck ist zwei Bloecke breit).  d2 = erster Block des neuen.
	move.w	um_block,d0
	cmp.w	d0,d2
	bge.b	um_b0
	exg	d0,d2			; d0 = kleinerer, d2 = groesserer
um_b0:	sub.w	d0,d2
	addq.w	#1,d2			; Bloecke - 1
	move.w	d2,um_block
	mulu.w	#TROW,d0		; Versatz in der Zeile
	move.l	d0,d1
	cmp.w	d4,d3			; oberste Zeile nach d4
	bge.b	um_z0
	move.w	d3,d4
um_z0:	add.w	#MPTR_H-1,d5		; Zeilen - 1
	move.w	d4,d0
	mulu.w	#SCRROW,d0
	move.l	Schirm_vorn,a0
	add.l	d0,a0			; erste Zeile im Bild
	lea	zg_zwischen,a1
	move.l	a1,a3
	sub.l	d0,a3			; Zwischenstueck als "Schirm"
	add.l	d1,a0			; erster Block
	add.l	d1,a1
	move.l	a0,-(sp)
	move.l	a1,-(sp)
	move.w	d5,d3
um_zin:	movem.l	a0-a1,-(sp)
	move.w	um_block,d2
um_zin2:
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	dbf	d2,um_zin2
	movem.l	(sp)+,a0-a1
	lea	SCRROW(a0),a0
	lea	SCRROW(a1),a1
	dbf	d3,um_zin
	move.l	a3,zg_schirm
	move.l	ZS_BG(a2),zg_bg		; alten heraus
	move.w	ZS_X(a2),d0
	move.w	ZS_Y(a2),d1
	bsr	Zeiger_aus_puffer
	move.l	zg_frei,zg_bg		; neuen hinein
	move.w	d6,d0
	move.w	d7,d1
	bsr	Zeiger_in_puffer
	move.l	(sp)+,a0		; zurueck ins Bild, in einem Zug
	move.l	(sp)+,a1
	move.w	d5,d3
um_zaus:
	movem.l	a0-a1,-(sp)
	move.w	um_block,d2
um_zaus2:
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	dbf	d2,um_zaus2
	movem.l	(sp)+,a0-a1
	lea	SCRROW(a0),a0
	lea	SCRROW(a1),a1
	dbf	d3,um_zaus
um_tausch:
	move.l	zg_frei,d0		; der neue Hintergrund gehoert jetzt
	move.l	ZS_BG(a2),zg_frei	; dem Satz, der alte ist frei
	move.l	d0,ZS_BG(a2)
	move.w	d6,ZS_X(a2)
	move.w	d7,ZS_Y(a2)
	bra.b	um_out
um_frisch:
	; ---- noch keiner da: sichern und zeichnen ----
	sf	zg_neu
	move.l	Schirm_vorn,zg_schirm
	move.l	ZS_BG(a2),zg_bg
	bsr	Zeiger_in_puffer
	move.w	d0,ZS_X(a2)
	move.w	d1,ZS_Y(a2)
	st	ZS_DA(a2)
um_out:	movem.l	(sp)+,d0-d7/a0-a3
	rts

; ***************************************************************************
; Mouse_on, Mouse_off -- show and hide the mouse pointer; the original's
; names.
;   All registers are preserved.
;
; Dort schalten sie ein Hardware-Sprite ein und aus, was nichts kostet und
; sofort wirkt.  Hier ist der Zeiger Teil des Bildes und wird von
; Update_screen und Update_mouse mitgefuehrt.
; ***************************************************************************
; **Seit Erkenntnis 174 wirken sie**, ueber eine Merkzelle: solange sie
; gesetzt ist, lassen Update_screen und Update_mouse den Zeiger weg.
; Thalions Display_text schaltet ihn beim freien Scrollen ab (die Mauslage
; ist dann die Scrollstellung, nicht der Zeiger), sein Ziehen an der
; Bildlaufleiste ebenso.  Beide rufen paarweise.
Mouse_on:
	sf	maus_aus
	rts
Mouse_off:
	st	maus_aus
	rts

	SECTION	Fast_BSS,bss
maus_aus:	ds.b	1		; gesetzt: kein Zeiger im Bild
zeiger_sperre:	ds.b	1		; > 0: Zeiger_vbl fasst nichts an
	even
um_block:	ds.w	1		; Zeiger_nachfuehren: Block, Bloecke - 1
	SECTION	Program,code

; ***************************************************************************
; Maus anschliessen.
;
; Das Original bekommt Mouse_X, Mouse_Y und Button_state von seiner
; Bibliothek; auf dem Falcon holen wir sie uns selbst.  Kbdvbase liefert die
; Vektortabelle der Tastatur, an Platz 16 steht der Mausvektor.  Der wird
; umgebogen, die alte Adresse gemerkt und beim Beenden zurueckgesetzt.
;
; Das Umbiegen braucht Supervisorrechte -- die hat das Programm ohnehin.
; ***************************************************************************
Mouse_install:
	movem.l	d0-d2/a0-a1,-(sp)
	; Der Bereich muss stehen, *bevor* der Vektor haengt: sonst begrenzt
	; das erste Mauspaket auf ein Rechteck aus lauter Nullen und der Zeiger
	; klebt in der Ecke, bis irgendwann Default_MA kommt.
	bsr	MA_vollbild
	move.w	#Kbdvbase,-(sp)
	Xbios
	addq.l	#2,sp
	move.l	d0,p_kbd(a5)
	move.l	d0,a0
	move.w	sr,d2			; Interrupts sperren
	move.w	#$2700,sr
	move.l	16(a0),oldmvec(a5)	; alten Vektor merken
	lea	Mouse_int(pc),a1
	move.l	a1,16(a0)
	move.w	d2,sr
	; ---- dem IKBD sagen, was gebraucht wird ----
	;
	; Nach dem Tastaturprotokoll kann der IKBD die Maustasten wie
	; Tastaturtasten behandeln.  Dann erzeugt ein Klick kein Mauspaket,
	; sondern die Scancodes $74 und $75 -- der Mausvektor sieht davon
	; nichts.  Das erklaert, warum die Bewegung ankam und die Tasten nicht.
	;
	; $08       Bewegung relativ berichten
	; $07 $00  Tasten gehoeren zur Maus, nicht zur Tastatur
	pea	ikbd_rel(pc)
	move.w	#0,-(sp)		; Laenge minus eins
	move.w	#Ikbdws,-(sp)
	Xbios
	lea	8(sp),sp
	pea	ikbd_btn(pc)
	move.w	#1,-(sp)
	move.w	#Ikbdws,-(sp)
	Xbios
	lea	8(sp),sp

	; Zeiger in die Mitte, noch nicht gezeichnet
	move.w	#SCRW/2,Mouse_X
	move.w	#SCRH/2,Mouse_Y
	clr.w	Button_state
	clr.b	Maustasten
	clr.w	mouse_dr(a5)
	movem.l	(sp)+,d0-d2/a0-a1
	rts

	even
ikbd_rel: dc.b	$08			; relative Berichte
	even
ikbd_btn: dc.b	$07,$00		; Tasten gehoeren zur Maus
	even

; ***************************************************************************
; Maus wieder abhaengen.  Ohne das bleibt ein Vektor stehen, der ins Nichts
; zeigt, sobald das Programm aus dem Speicher ist.
; ***************************************************************************
Mouse_remove:
	movem.l	d0-d1/a0,-(sp)
	move.l	p_kbd(a5),d0
	beq.b	mr_out
	move.l	d0,a0
	move.w	sr,d1
	move.w	#$2700,sr
	move.l	oldmvec(a5),16(a0)
	move.w	d1,sr
	clr.l	p_kbd(a5)
mr_out:	movem.l	(sp)+,d0-d1/a0
	rts

; ***************************************************************************
; Der Mausvektor selbst.  Er laeuft im Interrupt, a0 zeigt auf das Paket der
; Tastatur: Tastenbyte, dann die Bewegung in x und y, beide vorzeichenbehaftet.
;
; Im Interrupt ist a5 nicht verlaesslich -- die Variablenbasis wird deshalb
; ueber den Programmzaehler neu geholt.
;
; Das Tastenbyte traegt die Tasten in den unteren zwei Bits.
;
; Die Stelle wird auf den Satz der obersten Mouse-Area begrenzt, im
; Vollbild Thalions Default_MA (0..319, 0..199).  Dass der Zeiger dort ueber
; den Rand ragt, faengt das Zeichnen ab: Fleck_adresse klemmt den Fleck ins
; Bild, Zeiger_in_puffer schneidet rechts und unten weg.
; ***************************************************************************
Mouse_int:
	; a1 als Basis ist weg: die Mausvariablen liegen jetzt absolut, mit
	; Thalions Namen.  Der Interrupt kam ohne a5 aus, indem er sich die
	; Basis selbst holte -- absolut braucht er gar keine.
	movem.l	d0-d2/a1,-(sp)
	; **Nur die rohen Tasten.**  Button_state bildet Maus_vbl einmal je
	; Bild, wie das Original (Erkenntnis 252).  Hier nur, was gehalten
	; wird, in Thalions Bitlage: links Bit 0, rechts Bit 4.  Das IKBD-Paket
	; liefert rechts in Bit 0, links in Bit 1.
	moveq	#0,d1
	move.b	(a0),d0			; IKBD-Tastenbyte
	btst	#1,d0			; links gedrueckt?
	beq.b	mi_nol
	bset	#Left_pressed,d1
mi_nol:	btst	#0,d0			; rechts gedrueckt?
	beq.b	mi_nor
	bset	#Right_pressed,d1
mi_nor:	move.b	d1,Maustasten
	; Die Kanten kommen bei jedem Paket aus dem Satz der obersten Area
	; (Maus_bereich, AREAS.S) -- ein ModInit rechnet sie erst aus, nachdem
	; sie aufgelegt ist (Erkenntnis 192).
	move.l	Maus_bereich,a1
	move.b	1(a0),d1		; Bewegung in x
	ext.w	d1
	add.w	Mouse_X,d1
	cmp.w	MA_X1(a1),d1
	bge.b	mi_x0
	move.w	MA_X1(a1),d1
mi_x0:	cmp.w	MA_X2(a1),d1
	ble.b	mi_x1
	move.w	MA_X2(a1),d1
mi_x1:	move.w	d1,Mouse_X
	move.b	2(a0),d2		; Bewegung in y
	ext.w	d2
	add.w	Mouse_Y,d2
	cmp.w	MA_Y1(a1),d2
	bge.b	mi_y0
	move.w	MA_Y1(a1),d2
mi_y0:	cmp.w	MA_Y2(a1),d2
	ble.b	mi_y1
	move.w	MA_Y2(a1),d2
mi_y1:	move.w	d2,Mouse_Y
mi_ende:
	movem.l	(sp)+,d0-d2/a1
	rts
; Push_MA und Default_MA sind nach HULL/AREAS.S gewandert.  Sie sind dort
; Stapel geworden und nehmen ihren Satz in a0, wie im Original -- ein
; Fenster bringt seinen Bereich mit, und Close_window nimmt ihn wieder
; herunter.

; ***************************************************************************
; Zeigerecke -- aus der Mausstelle die linke obere Ecke des Zeigerbilds.
; d0 = x, d1 = y, hinein und heraus.  Im Original steht der Hotspot im
; Zeigersatz (Set_mouse_ptr, AREAS.S); beim Pfeil ist er 1,1, bei den
; uebrigen 7,7.  Die Ecke kann darum links und oben negativ werden.
; ***************************************************************************
Zeigerecke:
	sub.w	zg_hx,d0
	sub.w	zg_hy,d1
	rts

; ***************************************************************************
; Den Zeiger in einen Schirm setzen.  d0 = x, d1 = y (Ecke, Zeigerecke).
; Welcher Schirm, sagt zg_schirm, wohin der Hintergrund kommt, zg_bg
; (Doppelpuffer B1a: einer je Schirm, zeiger_saetze).
;
; Der Hintergrund wandert vorher nach zg_bg, damit Zeiger_aus_puffer ihn
; zurueckholen kann.  Gesichert und gezeichnet werden zwei Bloecke Breite:
; der Zeiger ist sechzehn Pixel breit und steht selten auf einer Blockgrenze.
;
; Alle acht Ebenen werden angefasst -- unter dem Zeiger liegt ein Bild aus
; 256 Farben, und wer nur die unteren vier setzt, mischt den Hintergrund in
; die Zeigerfarbe.
;
; Die Ebenen ab Data_depth tragen die Bank der Bildzeile (Rasterbank, je
; Zeile): das Zeigerbild hat dort ueberall die Zeigerpunkte, gezeichnet
; werden sie nur, wo die Bank ihr Bit hat (Erkenntnis 266, Set_mouse_ptr).
; ***************************************************************************
Zeiger_in_puffer:
	bsr	Zeiger_bild		; machine part (ST_LIB.S: per line the set of its range)
	movem.l	d0-d7/a0-a3,-(sp)
	bsr	Fleck_adresse		; a1 = Stelle im Schirm
	move.l	zg_bg,a0		; ---- Hintergrund sichern ----
	move.l	a1,a2
	move.w	#MPTR_H-1,d6
zp_s:	move.l	a2,a3
	moveq	#(TROW*2)/2-1,d5
zp_sc:	move.w	(a3)+,(a0)+
	dbf	d5,zp_sc
	lea	SCRROW(a2),a2
	dbf	d6,zp_s
	move.l	p_mptr(a5),a0		; ---- Zeiger hineinzeichnen ----
	move.l	p_mmsk(a5),a2
	; Fleck_adresse klemmt die Ecke ins Bild.  Wie weit das Bild gegen
	; den Fleck versetzt ist, rechnen wir hier mit derselben Klemme nach:
	; links wird dabei geschnitten (Schiebeweite ueber 16), rechts auch
	; (Ecke im rechten Block des Flecks: nach rechts schieben, was ueber
	; den Fleck ragt, faellt heraus), oben werden Bildzeilen
	; uebersprungen, unten weggelassen.
	move.w	d0,d7			; Block des Flecks
	bpl.b	zp_b0
	moveq	#0,d7
zp_b0:	cmp.w	#SCRW-2*MPTR_W,d7
	bls.b	zp_b1
	move.w	#SCRW-2*MPTR_W,d7
zp_b1:	and.w	#$FFF0,d7
	moveq	#16,d4
	add.w	d7,d4
	sub.w	d0,d4			; Schiebeweite = 16 - (x - Block)
	moveq	#0,d0			; d0 = 0: nach links schieben
	tst.w	d4
	bpl.b	zp_b2
	neg.w	d4			; Ecke im rechten Block: um x - Block - 16
	moveq	#1,d0			; nach rechts schieben
zp_b2:	move.w	d1,d6			; Zeile des Flecks
	bpl.b	zp_y0
	moveq	#0,d6
zp_y0:	cmp.w	#SCRH-MPTR_H,d6
	bls.b	zp_y1
	move.w	#SCRH-MPTR_H,d6
zp_y1:	sub.w	d1,d6			; > 0: oben geschnitten, < 0: unten
	bmi.b	zp_unten
	move.w	d6,d7
	mulu.w	#PLANES*2,d7		; Bildzeilen ueberspringen
	add.l	d7,a0
	add.l	d7,a2
	neg.w	d6
	add.w	#MPTR_H-1,d6		; Zeilen - 1
	bra.b	zp_rows
zp_unten:
	move.w	d6,d7
	neg.w	d7
	mulu.w	#SCRROW,d7
	add.l	d7,a1			; tiefer im Fleck anfangen
	add.w	#MPTR_H-1,d6
zp_rows:
	tst.w	d6
	bmi	zp_out
	; Die erste gezeichnete Bildzeile ist max(y, 0): oben geschnitten
	; beginnt sie bei 0, unten geschnitten bei y selbst.
	tst.w	d1
	bpl.b	zp_rows_los
	moveq	#0,d1
zp_rows_los:
	clr.w	-(sp)			; Grenze der Bank: die erste Zeile fragt
zp_row:	cmp.w	(sp),d1			; ---- Bank dieser Bildzeile, neu
	bcs.b	zp_bank_gilt		; gefragt erst an ihrer Grenze ----
	move.l	d0,-(sp)
	move.l	d1,d2			; Zeile; d2 ist hier frei
	move.w	d1,d0
	bsr	Rasterbank_spanne
	move.w	d1,4(sp)		; neue Grenze
	move.l	d2,d1
	swap	d1
	move.w	d0,d1			; oberes Wort von d1: die Bank
	swap	d1
	move.l	(sp)+,d0
zp_bank_gilt:
	move.l	a1,a3
	moveq	#PLANES-1,d5
zp_pl:	moveq	#0,d2
	move.w	(a0)+,d2
	moveq	#PLANES-1,d7		; Ebene ab Data_depth: nur mit Bankbit
	sub.w	d5,d7
	cmp.w	#Data_depth,d7
	blo.b	zp_quelle
	add.w	#16,d7			; die Bank steht im oberen Wort von d1
	btst	d7,d1			; (kein swap dazwischen: es setzt Z neu)
	bne.b	zp_quelle
	moveq	#0,d2
zp_quelle:
	moveq	#0,d3
	move.w	(a2)+,d3
	move.l	#$FFFF,d7
	tst.w	d0
	bne.b	zp_rechts
	lsl.l	d4,d2			; Bild, ausgerichtet
	lsl.l	d4,d3
	lsl.l	d4,d7
	bra.b	zp_masken
zp_rechts:
	lsr.l	d4,d2			; Rest faellt rechts aus dem Bild
	lsr.l	d4,d3
	lsr.l	d4,d7
zp_masken:
	not.l	d7			; Bits ausserhalb des Zeigers
	or.l	d7,d3			; Maske, ausgerichtet
	moveq	#0,d7
	move.w	(a3),d7
	swap	d7
	move.w	TROW(a3),d7
	and.l	d3,d7
	or.l	d2,d7
	move.w	d7,TROW(a3)
	swap	d7
	move.w	d7,(a3)+
	dbf	d5,zp_pl
	lea	SCRROW(a1),a1
	addq.w	#1,d1			; naechste Bildzeile
	dbf	d6,zp_row
	addq.l	#2,sp			; die Grenze
zp_out:	movem.l	(sp)+,d0-d7/a0-a3
	rts

; ***************************************************************************
; Den gesicherten Hintergrund zurueckholen.  d0 = x, d1 = y -- dieselbe
; Stelle wie beim Sichern; zg_schirm und zg_bg wie dort.
; ***************************************************************************
Zeiger_aus_puffer:
	movem.l	d0-d6/a0-a3,-(sp)
	bsr	Fleck_adresse
	move.l	zg_bg,a0
	move.w	#MPTR_H-1,d6
za_row:	move.l	a1,a3
	moveq	#(TROW*2)/2-1,d5
za_c:	move.w	(a0)+,(a3)+
	dbf	d5,za_c
	lea	SCRROW(a1),a1
	dbf	d6,za_row
	movem.l	(sp)+,d0-d6/a0-a3
	rts

; ***************************************************************************
; Den gesicherten Hintergrund nur innerhalb eines Rechtecks zurueckholen.
; d0 = x, d1 = y wie beim Sichern; Bloecke d2..d3, Zeilen d4..d5.
;
; Fuer Duplicate_block: es kopiert ein Rechteck samt Zeiger in den hinteren
; Schirm, und nur dort darf der Abdruck heraus -- ausserhalb steht im
; hinteren Schirm schon Neueres.  zg_schirm und zg_bg wie beim Sichern.
; ***************************************************************************
Zeiger_aus_rechteck:
	movem.l	d0-d7/a0-a3,-(sp)
	move.w	d2,d6			; Blockbereich nach d6/d7
	move.w	d3,d7
	bsr	Fleck_lage		; d2 = erster Block, d3 = erste Zeile
	bsr	Fleck_adresse		; a1 = Stelle im Schirm
	move.l	zg_bg,a0
	moveq	#MPTR_H-1,d1		; Zeilen des Flecks
zr_zeile:
	cmp.w	d4,d3			; Zeile im Rechteck ?
	blt.b	zr_weiter
	cmp.w	d5,d3
	bgt.b	zr_weiter
	move.w	d2,d0			; linker Block des Flecks
	cmp.w	d6,d0
	blt.b	zr_rechts
	cmp.w	d7,d0
	bgt.b	zr_rechts
	move.l	(a0),(a1)		; ein Block, TROW Byte
	move.l	4(a0),4(a1)
	IFGT	TROW-8
	move.l	8(a0),8(a1)
	move.l	12(a0),12(a1)
	ENDC
zr_rechts:
	addq.w	#1,d0			; rechter Block
	cmp.w	d6,d0
	blt.b	zr_weiter
	cmp.w	d7,d0
	bgt.b	zr_weiter
	move.l	TROW(a0),TROW(a1)
	move.l	TROW+4(a0),TROW+4(a1)
	IFGT	TROW-8
	move.l	TROW+8(a0),TROW+8(a1)
	move.l	TROW+12(a0),TROW+12(a1)
	ENDC
zr_weiter:
	lea	TROW*2(a0),a0
	lea	SCRROW(a1),a1
	addq.w	#1,d3
	dbf	d1,zr_zeile
	movem.l	(sp)+,d0-d7/a0-a3
	rts

; ***************************************************************************
; Lage des Flecks zu d0 = x, d1 = y (Ecke): d2 = erster Block, d3 = Zeile,
; geklemmt wie in Fleck_adresse.  d0/d1 bleiben.
; ***************************************************************************
Fleck_lage:
	move.w	d1,d3
	bpl.b	fl_y0
	moveq	#0,d3
fl_y0:	cmp.w	#SCRH-MPTR_H,d3
	bls.b	fl_y1
	move.w	#SCRH-MPTR_H,d3
fl_y1:	move.w	d0,d2
	bpl.b	fl_x0
	moveq	#0,d2
fl_x0:	cmp.w	#SCRW-2*MPTR_W,d2
	bls.b	fl_x1
	move.w	#SCRW-2*MPTR_W,d2
fl_x1:	lsr.w	#4,d2
	rts

; ***************************************************************************
; Stelle im Schirm zg_schirm zu d0 = x, d1 = y.  Zurueck: a1.
;
; Waagerecht wird auf den Block abgerundet -- ein Block sind sechzehn Pixel,
; und der Zeiger darf zwischen zweien stehen.  Beides wird geklemmt, damit
; der Fleck nicht ueber das Pufferende hinausreicht.
; ***************************************************************************
Fleck_adresse:
	movem.l	d0-d2,-(sp)
	tst.w	d1
	bpl.b	fa_y0
	moveq	#0,d1
fa_y0:	cmp.w	#SCRH-MPTR_H,d1
	bls.b	fa_y1
	move.w	#SCRH-MPTR_H,d1
fa_y1:	tst.w	d0
	bpl.b	fa_x0
	moveq	#0,d0
	; Waagerecht bleiben zwei Bloecke Platz noetig, nicht einer: der Fleck
	; ist 32 Pixel breit, damit der Zeiger auch zwischen zwei Bloecken
	; stehen kann.  Wer auf SCRW-MPTR_W klemmt, schreibt bei ganz rechts
	; stehendem Zeiger 336 Pixel weit -- also in die naechste Zeile hinein.
fa_x0:	cmp.w	#SCRW-2*MPTR_W,d0
	bls.b	fa_x1
	move.w	#SCRW-2*MPTR_W,d0
fa_x1:	move.l	zg_schirm,a1
	move.w	d1,d2
	mulu.w	#SCRROW,d2
	add.l	d2,a1
	move.w	d0,d2
	lsr.w	#4,d2
	mulu.w	#TROW,d2
	add.l	d2,a1
	movem.l	(sp)+,d0-d2
	rts

; ***************************************************************************
; Access_bit_array stand hier bis 2026-09-26 als Nachbau (ueber p_party und
; eine Versatztabelle).  Seitdem kommt es aus Thalions MAIN.S und adressiert
; die Bitfelder ueber ihre Marken in Party_data.
;
; **Thalions Vertrag:** das Ergebnis von "pruefen" (d2 = 3) steht nur im
; Z-Flag, d0 bleibt erhalten.  Unser Nachbau gab zusaetzlich d0 = 0/1
; zurueck; unsere Aufrufer (EVENTS.S, PERSONS.S) setzen es jetzt selbst mit
; sne.  Die oberen Bits von d1 gehen dort in die Adressrechnung ein --
; also d1 immer mit moveq laden.
; ***************************************************************************

; ***************************************************************************
; Plot_pixel, Draw_hline, Draw_vline -- a point and lines, through
; Draw_box (clipped against the topmost CA like it).
;
; **Thalions Vertrag steht in seinen Aufrufern** (Erkenntnis 193):
;
;   Draw_hline   d0, d2 = die beiden X, d1 = Y, d4 = Farbe.  d3 bleibt aussen
;                vor: Draw_two_lines (MAP/2D_MAP.S, der Nachtkreis) hat dort
;                eine X-Koordinate stehen.
;   Draw_vline   d0 = X, d1, d3 = die beiden Y, d4 = Farbe.
;   Plot_pixel   d0 = X, d1 = Y, d4 = Farbe.
;
; **Die Enden duerfen vertauscht sein.**  Draw_rectangle (HULL/CONTROLS.S)
; zieht die untere Kante von rechts nach links und die linke von unten nach
; oben:
;
;     move.w d3,d1 / sub.w d6,d2 / jsr Draw_hline    ; d0 rechts, d2 links
;     move.w d2,d0 / sub.w d7,d3 / jsr Draw_vline    ; d1 unten, d3 oben
;
; Gezeichnet wird ueber Draw_box, das die Ecken geordnet braucht.  Bis
; 2026-09-28 hiessen beide Linien nur Draw_box: der Nachtkreis bekam keine
; Seiten (die Weltkarte ein Streifen), und von einem Rahmen erschienen nur
; die obere und die rechte Kante.
; ***************************************************************************

; Draw_hline -- a horizontal line.
;   IN : d0.w/d2.w = the two ends (any order), d1.w = y, d4.w = colour;
;        d3 is not used
;   All registers are preserved.
Draw_hline:
	movem.l	d0/d2-d3,-(sp)
	cmp.w	d0,d2
	bge.b	dh_ok
	exg	d0,d2
dh_ok:	move.w	d1,d3
	bsr	Draw_box
	movem.l	(sp)+,d0/d2-d3
	rts

; Draw_vline -- a vertical line.
;   IN : d0.w = x, d1.w/d3.w = the two ends (any order), d4.w = colour
;   All registers are preserved.
Draw_vline:
	movem.l	d1-d3,-(sp)
	cmp.w	d1,d3
	bge.b	dv_ok
	exg	d1,d3
dv_ok:	move.w	d0,d2
	bsr	Draw_box
	movem.l	(sp)+,d1-d3
	rts

; Plot_pixel -- one point.
;   IN : d0.w = x, d1.w = y, d4.w = colour
;   All registers are preserved.
Plot_pixel:
	movem.l	d2-d3,-(sp)
	move.w	d0,d2
	move.w	d1,d3
	bsr	Draw_box
	movem.l	(sp)+,d2-d3
	rts

; ***************************************************************************
; Get_block -- save a part of Work_screen, in Thalion's format or ours.
;   IN : a0 = destination, d0.w/d1.w = top left corner (x a multiple of
;        16), d5.w = planes of the destination (below), d6.w = width in
;        16-pixel blocks, d7.w = height in lines
;   All registers are preserved.
;
; Die Schnittstelle steht in Open_window, das damit den Fensterhintergrund
; beiseitelegt:
;
;     lea.l Window_background(a4),a0
;     moveq.l #Screen_depth,d5
;     move.w d2,d6 / move.w d3,d7 / lsl.w #4,d7
;     jsr Get_block
;
; **d5 ist die Ebenenzahl des Ziels** (Erkenntnis 175).  Zwei Faelle:
;
;   d5 = PLANES         voller Ausschnitt, blockverzahnt wie der Schirm.
;                       Nur fuer unsere eigenen Aufrufer; Thalions Code
;                       schickt nie acht.
;   d5 < PLANES         Originalformat: die unteren d5 Ebenen, Zeile fuer
;                       Zeile, darin Ebene fuer Ebene (Amiga-verschachtelt).
;                       So baut Thalions Create_object_graphics mit d5=5 das
;                       Bild des getragenen Gegenstands in einen Puffer von
;                       5*2*24 Byte, und so sichern Open_window und HDOBS.S
;                       den Hintergrund (d5 = Screen_depth = 5, Puffer nach
;                       Thalions Rechnung).  Die oberen Ebenen sind die
;                       Farbbank; Put_unmasked_block setzt sie aus der
;                       Bildzeile wieder dazu (Erkenntnis 191).
;
; Bis 2026-09-25 kopierte diese Routine immer acht Ebenen, 384 Byte in jenen
; 240-Byte-Puffer.
;
; X muss auf einer Blockgrenze liegen -- Open_window uebergibt die
; Fensterecke, und die ist ein Vielfaches von sechzehn.
; ***************************************************************************
Get_block:
	cmp.w	#SCHIRM_FORMAT,d5
	bcc.b	gb_schirm
	jmp	Get_block_orig		; machine part: Thalion's format
gb_schirm:
	movem.l	d0-d7/a0-a2,-(sp)
	lsr.w	#4,d0			; Blocknummer
	move.l	Work_screen,a1
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	mulu.w	#TROW,d0
	add.l	d0,a1
	subq.w	#1,d7
	bmi.b	gb_out
gb_row:
	move.l	a1,a2
	move.w	d6,d4
	subq.w	#1,d4
	bmi.b	gb_next
gb_col:
	moveq	#PLANES-1,d1
gb_pl:	move.w	(a2)+,(a0)+
	dbf	d1,gb_pl
	dbf	d4,gb_col
gb_next:
	add.l	#SCRROW,a1
	dbf	d7,gb_row
gb_out:
	movem.l	(sp)+,d0-d7/a0-a2
	jsr	Bereich_rueck		; machine part: R_range, Platz -> Bank + Verlaufsfarbe
	rts

; ***************************************************************************
; Put_masked_silhouette -- the shape of a graphic in one colour.
;   IN : a0 = graphic (Thalion's format), d0.w/d1.w = corner, d4.w =
;        colour, d5.w = planes of the source, d6.w = width in blocks,
;        d7.w = height in lines.  Clipped against the topmost CA.
;   All registers are preserved.
;
; **Die Form ist das ODER der d5 Quellebenen** (Amiga-Format,
; zeilenverschachtelt).  Die drei 2D-Aufrufer unten geben eine Ebene;
; Thalions Kampf (COMBAT/COMOBS.S, Draw_all_COMOBs) gibt Screen_depth.
; Beschnitten wird wie im Original gegen die CA (Block_beschneiden).
;
; Was eine Silhouette ist, sagt keine Aufrufstelle -- aber alle drei sagen
; dasselbe ueber ihre Register:
;
;     DISPLAY.S   moveq #26,d4 / moveq #1,d5   ; "Broken"-Aufdruck
;     AUTOMAPP.S  moveq #Automap_ink_colour,d4 / moveq #1,d5
;     ACTIONS.S   moveq #0,d4 / moveq #1,d5    ; Schraffur
;
; Daneben steht in DISPLAY.S zwei Zeilen vorher "moveq #5,d5" vor
; Put_masked_block2 -- fuenf Ebenen fuer das Symbol, eine fuer die
; Silhouette.  **d5 ist die Ebenenzahl der Quelle, d4 die Farbe.**  Eine
; Silhouette ist also eine einzelne Bitebene, in einer Farbe gemalt; die
; Form ist ihre eigene Maske.
;
; Bestaetigt am uebersetzten Original: bei Hunk 0, Versatz $22ad2 steht die
; Routine, und sie beginnt mit "tst.w d5 / bmi raus / cmp.w #5,d5 / bgt
; raus" -- sie prueft d5 gegen die Bildtiefe (Erkenntnis 129).
;
; Verfahren wie in Put_masked_block2: das Quellwort in die obere Haelfte
; eines Langworts, um X mod 16 nach rechts schieben, dann stehen linker und
; rechter Teil in zwei Bloecken, die TROW auseinanderliegen.
; ***************************************************************************
Put_masked_silhouette:
	movem.l	d0-d7/a0-a4,-(sp)
	bsr	Block_beschneiden	; wie das Original: gegen die CA
	bcs	pms_out
	move.w	d5,pms_ebenen
	move.w	d1,d2			; Bildzeile, fuer die Farbbank
	swap	d4			; Thalions Farbe ins obere Wort; das untere
					;  setzt jede Zeile neu (pms_block liest .w)
	move.w	d0,d5			; Schiebeweite (d5 wird hier frei)
	and.w	#15,d5
	asr.w	#4,d0			; Blocknummer (X darf links herausragen)
	move.l	Work_screen,a1
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	muls.w	#TROW,d0
	add.l	d0,a1
	subq.w	#1,d7
pms_row:
	move.l	d4,d1			; Farbe dieser Zeile (Zeilenfarbe)
	swap	d1
	move.w	d2,d0
	bsr	Zeilenfarbe
	move.w	d1,d4
	addq.w	#1,d2
	move.l	a1,a2
	move.l	a0,a4			; Quelle: Spalte 0, Ebene 0
	move.w	d6,d3
	subq.w	#1,d3
pms_col:
	; ---- Form: ODER der Quellebenen dieser Spalte (Plane-Zeilen liegen
	; d6 Worte auseinander) ----
	moveq	#0,d0
	move.l	a4,a3
	move.w	pms_ebenen,d1
	subq.w	#1,d1
pms_msk:
	or.w	(a3),d0
	add.w	d6,a3
	add.w	d6,a3
	dbf	d1,pms_msk
	addq.l	#2,a4
	swap	d0
	clr.w	d0
	lsr.l	d5,d0			; um X mod 16 schieben
	; d0 oben = linker Teil (Spalte c), unten = rechter Teil (c+1)
	move.w	d6,d1
	sub.w	d3,d1
	subq.w	#1,d1			; Spalte c
	bsr	Bl_sichtbar
	bcs.b	pms_ohne_links
	move.l	d0,d1
	swap	d1			; d1.w = linker Teil
	move.l	a2,a3
	bsr	pms_block		; linken Block setzen
pms_ohne_links:
	tst.w	d5			; steht X auf der Blockgrenze?
	beq.b	pms_kein_rest
	move.w	d6,d1
	sub.w	d3,d1			; Spalte c+1
	bsr	Bl_sichtbar
	bcs.b	pms_kein_rest
	move.w	d0,d1			; rechter Teil
	lea	TROW(a2),a3
	bsr	pms_block
pms_kein_rest:
	lea	TROW(a2),a2
	dbf	d3,pms_col
	move.w	pms_ebenen,d1		; naechste Quellzeile: d5 Plane-Zeilen
	mulu.w	d6,d1
	add.l	d1,a0
	add.l	d1,a0
	add.l	#SCRROW,a1
	dbf	d7,pms_row
pms_out:
	movem.l	(sp)+,d0-d7/a0-a4
	jmp	Bloecke_nacharbeiten	; machine part: R_range afterwork

	SECTION	Fast_BSS,bss
	even
pms_ebenen:	ds.w	1		; d5 des Aufrufers
	SECTION	Program,code

; d1.w = Maske, a3 = Blockanfang, d4 = Farbe.  Acht Ebenen setzen.
pms_block:
	movem.l	d0-d2/d6-d7/a3,-(sp)	; d0 auch: es traegt den rechten Teil
	tst.w	d1
	beq.b	pmsb_out		; nichts zu setzen
	move.w	d1,d2
	not.w	d2			; Gegenmaske
	move.w	d4,d6			; Farbe
	moveq	#PLANES-1,d7
pmsb_pl:
	move.w	(a3),d0
	and.w	d2,d0			; erst freiraeumen
	btst	#0,d6
	beq.b	pmsb_null
	or.w	d1,d0			; Farbbit gesetzt: Maske hinein
pmsb_null:
	move.w	d0,(a3)+
	lsr.w	#1,d6
	dbf	d7,pmsb_pl
pmsb_out:
	movem.l	(sp)+,d0-d2/d6-d7/a3
	rts

; ***************************************************************************
; Bibliothek_vbl -- was die Bibliothek je Bild im VBL tut.  Gerufen aus
; Raster_vbl (RASTER.S), das in der TOS-VBL-Warteschlange haengt.
;
;   Drogen_setzen  first of all (Falcon): the colours of Drugged_FX that
;                Drogen_farben computed in the frame before, so the VIDEL
;                palette is written in the top border (FALCON_LIB.S, T26).
;
;   VBL_counter  zaehlt die Bilder (TACTIC.S: "btst #4,VBL_counter+1")
;   VblQ_handler Thalions VBL-Warteschlange (VblQ_ptr des obersten Moduls):
;                Time_AutoIcon, Realtime, Time_2D -- lauter Zaehler.  Ohne
;                sie steht Timer, und Make_2D_move laesst die Gruppe nie
;                ziehen.  Thalions Quelltext ruft VblQ_handler nirgends.
;
;   Maus_vbl     Button_state und die Mausereignisse, wie im Original
;                direkt nach dem Bildzaehler (AM2_CPU 1.20, 0:$21252).
;
;   Zeiger_vbl   der Mauszeiger im sichtbaren Schirm, an Stelle des
;                Sprites (Erkenntnis 269).
;
;   Musik_vbl    der Tonpuffer (MUSIK_SUP.S, docs/13), wie im Original
;                zuletzt.  Es ruft Thalions Takt Music_routine+24 bei
;                gesetztem Music_flag (0:$21270), aber einmal je 1/50 s Ton
;                statt je Bild: an VGA kommt der VBL 60mal.  In jedem Bild,
;                denn bei Music_flag aus muss es Stille schreiben.
;
; VblQ_handler und Musik_vbl retten alle Register; VblQ_handler prueft
; Module_Sp und Q_block selbst.
; ***************************************************************************
Bibliothek_vbl:
	bsr	Drogen_setzen		; first: the colours of Drugged_FX (FALCON_LIB.S; ST: none)
	addq.w	#1,VBL_counter
	bsr	Basis_setzen		; Videobasis samt Bildschuetteln
	bsr	Maus_vbl
	bsr	Zeiger_vbl		; der Zeiger folgt in jedem Bild (269)
	bsr	Drogen_farben		; Drugged_FX on the colours (FALCON_LIB.S; ST: none)
	jsr	VblQ_handler
	jmp	Musik_vbl		; Tonpuffer und Takt (MUSIK_SUP.S)

; ***************************************************************************
; Maus_vbl -- Button_state bilden und ein Mausereignis ablegen.
;
; **Wie in AM2_CPU 1.20** (0:$238DA-$2391E, Erkenntnis 252).  Aus den
; gehaltenen Tasten jetzt (Maustasten, Mouse_int) und im letzten Bild
; (Button_state):
;
;   gehalten     Bit 0 links, Bit 4 rechts
;   gedrueckt    (~alt & neu & $11) << 1  -> Bit 1 / Bit 5
;   losgelassen  (~neu & alt & $11) << 2  -> Bit 2 / Bit 6
;
; Button_state = gehalten | gedrueckt | losgelassen.  Ist es nicht 0, geht
; ein Ereignis mit der Lage in die Schlange (Put_Mev, 0:$2396E).  Solange
; eine Taste gehalten wird, kommt also **in jedem Bild eines** -- davon
; leben das weiche Laufen (Mousemove_3D_Mod) und die Dauertasten
; (Continuous_Mod).  Das Gedrueckt-Bit steht genau ein Bild lang.
;
; Button_state ist bei uns ein Wort; Thalions Code liest das Byte an seiner
; Adresse (die obere Haelfte).  Alle Register bleiben.
; ***************************************************************************
Maus_vbl:
	movem.l	d0-d3/a1,-(sp)
	tst.b	Drugged_FX		; stoned: the pointer shakes first
	beq.b	mv_ruhig
	bsr	Maus_zittern
mv_ruhig:
	move.b	Button_state,d0		; alt
	move.b	Maustasten,d1		; neu: gehalten
	and.b	#$11,d1
	move.b	d0,d2
	not.b	d2
	and.b	#$11,d2
	and.b	d1,d2			; eben gedrueckt
	move.b	d1,d3
	not.b	d3
	and.b	#$11,d3
	and.b	d0,d3			; eben losgelassen
	add.b	d2,d2			; << 1
	lsl.b	#2,d3			; << 2
	or.b	d2,d1
	or.b	d3,d1
	move.b	d1,Button_state
	beq.b	mv_out			; nichts: kein Ereignis
	move.w	mev_kopf,d2		; ---- Put_Mev ----
	move.w	d2,d0
	addq.w	#1,d0
	and.w	#MEV_ANZ-1,d0
	cmp.w	mev_ende,d0		; voll? dann verwerfen, wie 1.20
	beq.b	mv_out
	lea	mev_puffer,a1
	mulu.w	#6,d2			; mulu liefert ein sauberes Langwort
	add.w	d2,a1			; adda.w: klein und positiv (Erk. 168)
	move.w	Mouse_X,(a1)+
	move.w	Mouse_Y,(a1)+
	and.w	#$FF,d1
	move.w	d1,(a1)
	move.w	d0,mev_kopf
mv_out:	movem.l	(sp)+,d0-d3/a1
	rts

; ***************************************************************************
; Maus_zittern -- the shaking pointer of Thalion's Drugged_FX.
;
; As in AM2_CPU 1.20 (0:$23878): every frame y and then x move by -3..+4
; (Random & 7, minus 3), then the position is clipped to the mouse area.
; Random is Thalion's (HULL/VARIOUS.S); AM2_CPU calls it from the VBL too.
; The mouse interrupt (MFP, level 6) also writes Mouse_X/Y, so the
; read-add-write runs with interrupts off; the two Random calls run before.
;   All registers are preserved.
; ***************************************************************************
Maus_zittern:
	movem.l	d0-d2/a1,-(sp)
	move.l	Maus_bereich,d0
	beq.b	mz_out
	move.l	d0,a1
	jsr	Random
	moveq	#7,d1
	and.w	d0,d1
	subq.w	#3,d1			; d1 = shake in y
	jsr	Random
	moveq	#7,d2
	and.w	d0,d2
	subq.w	#3,d2			; d2 = shake in x
	move.w	sr,-(sp)
	or.w	#$0700,sr
	add.w	Mouse_Y,d1
	cmp.w	MA_Y1(a1),d1
	bge.b	mz_y0
	move.w	MA_Y1(a1),d1
mz_y0:	cmp.w	MA_Y2(a1),d1
	ble.b	mz_y1
	move.w	MA_Y2(a1),d1
mz_y1:	move.w	d1,Mouse_Y
	add.w	Mouse_X,d2
	cmp.w	MA_X1(a1),d2
	bge.b	mz_x0
	move.w	MA_X1(a1),d2
mz_x0:	cmp.w	MA_X2(a1),d2
	ble.b	mz_x1
	move.w	MA_X2(a1),d2
mz_x1:	move.w	d2,Mouse_X
	move.w	(sp)+,sr
mz_out:	movem.l	(sp)+,d0-d2/a1
	rts

	SECTION	Fast_BSS,bss
	even
VBL_counter:	ds.w	1
Maustasten:	ds.b	1		; gehalten, roh (Mouse_int)
	even
	SECTION	Program,code

; (Strlen steht jetzt in Thalions HULL/VARIOUS.S.)

; (Close_current_file is in FILES_SUP.S now, next to ls_offen.)

; ***************************************************************************
; Put_unmasked_icon -- a 16x16 icon, unmasked, not clipped.
;   IN : a0 = icon (Thalion's format), d0.w/d1.w = corner (x rounded down
;        to 16), d4.w = colour offset, d5.w = planes of the source
;   All registers are preserved.
;
; Thalions Aufrufer (DISPLAY.S, MAP/2D_MAP.S) setzen nur a0, d0, d1, d4, d5
; -- also Put_unmasked_block mit einem Trunc Breite und sechzehn Zeilen.
; DISPLAY.S loescht so Teile der Statusleiste ("lea.l Status_M+6,a0": eine
; Zeile tiefer ins 16 Punkte breite Mittelstueck) und liest danach d7
; wieder: die Huelle muss d6/d7 zurueckgeben.
;
; The machine part takes the icon first (Unmasked_icon; wish of the ST
; session, user 2026-10-21): what it does not handle it hands back to
; pui_allgemein with all registers as received.  ST_LIB.S: a tile in one
; go; FALCON_LIB.S: nothing yet, straight back.
; ***************************************************************************
Put_unmasked_icon:
	bra	Unmasked_icon
pui_allgemein:
	movem.l	d6-d7,-(sp)
	moveq	#1,d6
	moveq	#16,d7
	bsr	pub_ohne_ca		; das Original beschneidet hier nicht
	movem.l	(sp)+,d6-d7
	rts

; ***************************************************************************
; Put_masked_icon -- a 16x16 icon, masked (colour 0 transparent).
;   IN : a0 = icon (Thalion's format, d5 plane words per line), d0.w/d1.w
;        = corner (x a multiple of 16), d4.w = colour base, d5.w = planes
;        of the source
;   All registers are preserved.
;
; Die Schnittstelle steht in Put_window_part (HULL/WINDOWS.S); der zweite
; Aufrufer ist Update_status_block (DISPLAY.S, siehe unten):
;
;     lea.l Window_icons,a0
;     mulu.w #3*2*16,d4        ; 96 Byte je Teil
;     add.l d4,a0
;     moveq.l #24,d4 / moveq.l #3,d5
;     jsr Put_masked_icon
;
; **Die 96 stehen dort woertlich**, nicht als Screen_depth-Ausdruck --
; Fensterkacheln haben im Original immer drei Ebenen, unabhaengig von der
; Bildtiefe.  Deshalb bleiben unsere Kacheln dreiebenig, und diese Routine
; zieht sie beim Zeichnen auf acht auf (Erkenntnis 140).
;
; Das Aufziehen ist einfacher, als es klingt.  Je Zeile:
;   Maske   = Oder aller Quellebenen -- gesetzt heisst "hier wird gemalt",
;             denn Index 0 ist durchsichtig
;   Ebene p = Quellebene p, falls es sie gibt (p < d5);
;             sonst die Maske, falls Bit p der Farbbasis gesetzt ist
;   Ziel    = (Ziel und nicht Maske) oder Ebene
;
; **d4 gilt nur fuer die Ebenen ab d5** (Erkenntnis 265), wie in
; Put_unmasked_block.  Thalions Update_status_block (DISPLAY.S) loescht die
; Stelle des Zustandssymbols mit Put_unmasked_icon (d4 = 24, d5 = 3) und
; zeichnet das Symbol dann mit d5 = Screen_depth, ohne d4 neu zu setzen.
; Auf dem Amiga ist die 24 dort wirkungslos; bei uns verschob sie jedes
; Zustandssymbol um 24 Farben (Savestates des Nutzers, 2026-10-01).
;
; **Farbbasis = d4 ODER Farbbank der Bildzeile**, dieselbe Regel wie in
; Put_unmasked_block (Zeilenfarbe).  Bis Erkenntnis 264 fehlte die Bank:
; Fensterteile landeten immer in Bank 0.  Solange Bank 0 zufaellig
; Main_pal trug, fiel das nicht auf; im Charaktereditor (eine R_palette,
; Bank 2) blieben Rahmen und Kopf des Fensters schwarz.
;
; X muss auf einer Blockgrenze liegen.  Put_window_part haelt das ein: die
; Fensterecke ist ein Vielfaches von sechzehn, und jeder weitere Teil sitzt
; sechzehn weiter.
; ***************************************************************************
Put_masked_icon:
	bra	Masked_icon		; machine part


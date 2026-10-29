; HULL/ST_LIB.S -- die Farben des ST: 32 Farben Thalions auf 16 Register
;
; Only in the ST build (-DZIEL_ST=1, tools/build_st.sh).  Plan and
; measurements: docs/12-ST-Port.md.
;
; **Die Bilddaten bleiben, reduziert wird die Palette.**  Thalions Grafik
; traegt Farbnummern 0..31 in fuenf Ebenen.  Der Falcon legt sie mit einer
; Farbbank in 256 Register; der ST hat 16.  Je Palette rechnet diese Datei
; eine Tabelle Nummer -> Register und legt beim Zeichnen das Register in die
; vier Ebenen des Schirms.  Wo der Falcon die Bankebenen setzt, steht beim
; ST die Tabelle.
;
; **Stufe S2: 16 Register je Bildbereich, Timer B an den Grenzen.**  Auf
; dem Amiga stehen mehrere Paletten uebereinander (Main_pal oben, die Karte
; darunter); die Rasterliste sagt, ab welcher Zeile welche gilt.  Hier
; bekommt jeder Platz der Rasterliste (Erkenntnis 264) seinen eigenen Satz:
; seine 31 Farben in 15 Gruppen (k-means; Thalions UI-Rampe 26..31 fuer
; sich, St_bauen), Register 0 bleibt Thalions Farbe 0.  Welcher Satz eine Bildzeile nimmt, sagt der Platz, in dessen
; Bereich sie liegt.  Timer B laedt an jeder Grenze die 16 Register des
; naechsten Bereichs, einmal je Grenze und Bild (St_raster_int).  Die
; Verlaeufe (R_range, Portraits, 3D-Himmel) bleiben flach (Nutzer,
; 2026-10-02).  S1 teilte die 16 Register zwischen beiden Paletten.
;
; **Register 0 gehoert der Farbe 0 allein.**  So bleibt 0 durchsichtig, auch
; im Schirmformat: Maskiert_setzen und Put_masked_icon bilden die Maske aus
; dem ODER der Ebenen.  Eine andere schwarze Farbe bekommt ein eigenes
; Register.
;
; **Zurueck geht es ueber einen Stellvertreter.**  Get_block sichert mit
; d5 = 5 Thalions Format; aus Register r wird die Farbe Rep[r], deren
; Tabelleneintrag wieder r ist.  So gibt ein gesicherter Hintergrund beim
; Zuruecklegen dieselben Register zurueck (Erkenntnis 191, beim ST).
;
; **Tempo** (Nutzer, 2026-10-01: Pflicht, in unserer Hardwareschicht, nur
; zur Laufzeit): P1 Satz je Zeile in einer Tabelle, P2 Merkliste fuer
; Blockzeilen, P3 Kachelspeicher fuer ganze Symbole.  Messung in docs/12.
;
; **The machine part of LIBRARY.S** (library split phase 2, 2026-10-23;
; FALCON_LIB.S has the same names): Pub_zeilen, Box_fuellen,
; Quelle_aufweiten, Zeilenfarbe, Get_block_orig, Masked_icon,
; Unmasked_icon, Pm2_schnell, Zeiger_bild.  What only the Falcon has
; (R_range afterwork, Drugged_FX) is empty here, at the end of this file.

	IFNE	PLANES-4
	FAIL	"ST_LIB.S rechnet mit vier Ebenen"
	ENDC

; Ein Satz je Palette:
ST_TAB	= 0			; 32 Byte   Farbe n -> Register
ST_REP	= 32			; 16 Byte   Register r -> eine Farbe n mit Tab[n] = r
ST_TAB2	= 48			; 32 Langworte n -> Ebenenbits, Byte k Bit 0 = Ebene k
ST_GEN	= 48+32*4		; .w Nummer des Baus (st_gen): Schluessel von P2/P3
ST_SUB	= ST_GEN+2		; 178

; Ein Eintrag im Zwischenspeicher, gefunden ueber den Inhalt der Palette:
SE_KEY	= 0			; 32 Worte, die Palette
SE_S	= 64			; ihr Satz
SE_MITTE = SE_S+ST_SUB		; 16 Worte $0RGB, die Gruppenmitten (0: Farbe 0)
SE_NC	= SE_MITTE+32		; .w Zahl der Gruppen
SE_RMASKE = SE_NC+2		; .w Bit r: Register r rechnet nur aus der Rampe
SE_QUELLE = SE_RMASKE+2		; .l Palette, fuer die er zuletzt galt (st_blende)
SE_KARTE = SE_QUELLE+4		; .w Map_nr dabei
SE_HAND	= SE_KARTE+2		; .w set: from STPAL.DAT (St_from_file)
SE_HWERT = SE_HAND+2		; 16 words $0RGB: register values for this machine
SE_HSUMME = SE_HWERT+32		; 16 x R, G, B, count: the file palette per register
SE_SIZE	= SE_HSUMME+16*8
ST_EINTRAEGE = 8		; drei Plaetze und was beim Blenden dazukommt

; Ein Platz der geltenden Rasterliste (st_pl, St_stand):
PL_ZEILE   = 0			; .w ab dieser Bildzeile
PL_BANK    = 2			; .w Platz in Bank_ist (0..PLAETZE-1)
PL_EINTRAG = 4			; .l Eintrag seiner Palette
PL_GEN     = 8			; .w dessen Bau (ST_GEN)
PL_SZ      = 12

; Die Liste fuer Timer B (st_regs_bauen, St_raster_vbl, St_raster_int):
;   .w Zahl der Grenzen, 16 Worte fuer den ersten Bereich, dann je Grenze
;   .w Zaehler (Bildzeilen bis eine Zeile vor der Grenze) und 16 Worte.
STR_SATZ = 2+32
STR_GR	= 2+32+(PLAETZE-1)*STR_SATZ

ST_PALETTE = $FFFF8240		; die 16 Farbregister

ST_ZEILEN = 200			; Bildzeilen mit eigenem Eintrag in st_zsatz

; ***************************************************************************
; St_zeilensatz -- der Satz einer Bildzeile.
;   IN : d0.w = Bildzeile
;   OUT: a0 = Satz (ST_TAB, ST_REP, ST_TAB2).  Alle uebrigen Register bleiben.
;
; **Tempo (P1):** Welcher Satz zu welcher Zeile gehoert, steht in st_zsatz,
; einer Tabelle mit 200 Zeigern.  St_zeilen_pruefen rechnet sie nur neu,
; wenn sich etwas geaendert hat.  Wer viele Zeilen hintereinander zeichnet,
; ruft St_zeilen_pruefen einmal und dann je Zeile St_zeilensatz_schnell.
; ***************************************************************************
St_zeilensatz:
	bsr	St_zeilen_pruefen
	; weiter in St_zeilensatz_schnell

; ***************************************************************************
; St_zeilensatz_schnell -- wie St_zeilensatz, ohne Pruefung.  Nur nach
; St_zeilen_pruefen, und solange dazwischen weder Palette noch Modul noch
; Zeichenziel wechseln.  Zeilen ausserhalb 0..199 nehmen die naechste.
;   IN : d0.w = Bildzeile   OUT: a0 = Satz.  Alle uebrigen Register bleiben.
; ***************************************************************************
St_zeilensatz_schnell:
	move.w	d0,-(sp)
	bpl.b	szs_nneg
	moveq	#0,d0
szs_nneg:
	cmp.w	#ST_ZEILEN,d0
	bcs.b	szs_drin
	move.w	#ST_ZEILEN-1,d0
szs_drin:
	add.w	d0,d0
	add.w	d0,d0
	lea	st_zsatz,a0
	move.l	0(a0,d0.w),a0
	move.w	(sp)+,d0
	rts

; ***************************************************************************
; St_zeilen_pruefen -- Plaetze, Saetze und st_zsatz auf den Stand bringen.
; Alle Register bleiben.
;
; Zwei Stufen.  **Der kurze Stempel:** die geltende Rasterliste (st_rl),
; Letzte_RL, ob in einen Hilfsschirm gezeichnet wird, und VBL_counter.
; Steht er, ist nichts zu tun.  Sonst liest St_stand die Plaetze und sucht
; je Platz den Eintrag ueber den Inhalt der Palette; haben sich Plaetze,
; Eintraege oder ihr Bau geaendert, werden st_zsatz und die Register neu
; gebaut.
;
; **VBL_counter im kurzen Stempel:** Thalion fuellt eine Palette an Ort und
; Stelle neu (Load_map nach Current_pal), ohne dass sich Liste oder Modul
; aendern.  Der Inhalt wird darum einmal je Bild verglichen, nicht bei jedem
; Zeichnen; Laden dauert ohnehin mehrere Bilder.  Bis S1 lief der Vergleich
; bei jedem Aufruf, rund 28 % der Zeit auf der Karte.  Platz_setzen
; erzwingt den ganzen Weg (szp_rl = -1).
;
; **Tempo (P5): davor ein Vorstempel ohne Listenlauf.**  Gerufen wird bis
; zu 270 Mal je Bild (Messung 2026-10-03, ST, Karte).  Stehen VBL_counter,
; Module_Sp, Work_screen, Off_screen und Letzte_RL wie beim letzten Mal,
; ist nichts zu tun, ohne st_rl.  Was Thalion an einer Liste aendert, ohne
; dass sich davon etwas bewegt, faengt wie bisher der VBL_counter, also
; spaetestens im naechsten Bild.  szp_msp = -1 erzwingt den langen Weg.
; ***************************************************************************
St_zeilen_pruefen:
	move.l	d0,-(sp)
	move.w	VBL_counter,d0
	cmp.w	szp_vbl,d0
	bne.b	szp_lang
	move.l	Module_Sp,d0
	cmp.l	szp_msp,d0
	bne.b	szp_lang
	move.l	Work_screen,d0
	cmp.l	szp_ws,d0
	bne.b	szp_lang
	move.l	Off_screen,d0
	cmp.l	szp_off,d0
	bne.b	szp_lang
	move.l	Letzte_RL,d0
	cmp.l	szp_letzte,d0
	bne.b	szp_lang
	move.l	(sp)+,d0
	rts
szp_lang:
	move.l	(sp)+,d0
	movem.l	d0-d1,-(sp)
	move.l	Module_Sp,szp_msp
	move.l	Work_screen,szp_ws
	move.l	Off_screen,szp_off
	bsr	st_rl
	move.l	d0,st_rl_jetzt
	move.l	Work_screen,d1
	cmp.l	Off_screen,d1
	sne	d1			; gesetzt: Hilfsschirm
	cmp.b	st_hilfs_flag,d1
	bne.b	szp_neu
	cmp.l	szp_rl,d0
	bne.b	szp_neu
	move.l	Letzte_RL,d1
	cmp.l	szp_letzte,d1
	bne.b	szp_neu
	move.w	VBL_counter,d1
	cmp.w	szp_vbl,d1
	beq.b	szp_out
szp_neu:
	move.l	d0,szp_rl
	move.l	Letzte_RL,szp_letzte
	move.w	VBL_counter,szp_vbl
	move.l	Work_screen,d1
	cmp.l	Off_screen,d1
	sne	st_hilfs_flag
	bsr	St_stand
szp_out:
	movem.l	(sp)+,d0-d1
	rts

; ***************************************************************************
; St_stand -- die Plaetze der geltenden Rasterliste und ihre Eintraege.
;   IN : d0 = st_rl_jetzt.  Alle Register bleiben.
;
; Die Liste ist die des obersten Moduls, geerbt vom Modul darunter
; (Erkenntnis 264, wie Farbbank), ohne die die zuletzt gesetzte
; (Letzte_RL).  Jede R_palette ist ein Platz: ab ihrer Zeile, ihre Palette,
; ihr Platz in Bank_ist.  Der erste gilt ab Zeile 0.  Ohne Liste gilt der
; zweite Platz (Bank 0 beim Falcon) fuer das ganze Bild.
;
; **Die Tabelle folgt der Palette der Liste**, nicht dem, was gerade steht
; (Erkenntnis 240): Thalion zeichnet im Dunkeln und blendet danach ein.
; Die Register dagegen kommen aus Bank_ist (st_regs_bauen).
;
; Der Hilfsschirm (Create_object_graphics) nimmt fuer alle Zeilen einen
; Satz: den des ersten Platzes, dessen Palette nicht Main_pal ist, sonst den
; ersten (st_pl_hilfs), wie Bank 0 bei Farbbank.
; ***************************************************************************
St_stand:
	movem.l	d0-d4/d7/a0-a4,-(sp)
	move.w	#-1,st_nr_neu		; Platz mit Batch: noch keiner (241)
	clr.l	st_nr_lneu
	moveq	#-1,d4			; Platz fuer den Hilfsschirm, noch keiner
	moveq	#0,d1			; Plaetze
	lea	st_pl,a2
	tst.l	d0
	bne.b	sst_liste
	move.l	Letzte_RL,d0
	beq.b	sst_ohne
sst_liste:
	move.l	d0,a3		; a3 = Rasterliste (st_platz_eintrag braucht a0)
	move.l	d0,st_nr_lneu
sst_lauf:
	move.b	(a3),d0
	cmp.b	#RL_END,d0
	beq.b	sst_ende
	cmp.b	#RL_PAL,d0
	bne.b	sst_range
	cmp.w	#PLAETZE,d1
	bcc.b	sst_ende		; mehr Plaetze hat keine Liste Thalions
	moveq	#0,d0
	move.b	1(a3),d0
	tst.w	d1
	bne.b	sst_zeile
	moveq	#0,d0			; der erste Platz gilt ab Zeile 0
sst_zeile:
	move.w	d0,PL_ZEILE(a2)
	move.w	d1,PL_BANK(a2)
	move.l	2(a3),a1
	cmpa.l	#Batch,a1		; Palette, die erst nach dem Zeichnen kommt
	bne.b	sst_kein_batch
	move.w	d1,st_nr_neu
sst_kein_batch:
	cmpa.l	#Main_pal,a1
	beq.b	sst_eintrag
	tst.w	d4
	bpl.b	sst_eintrag
	move.w	d1,d4
sst_eintrag:
	bsr	st_platz_eintrag
	lea	PL_SZ(a2),a2
	addq.w	#1,d1
	addq.l	#6,a3
	bra.b	sst_lauf
sst_range:
	addq.l	#8,a3			; R_range: Verlaeufe bleiben flach
	bra.b	sst_lauf
sst_ende:
	tst.w	d1
	bne.b	sst_gezaehlt
sst_ohne:
	lea	st_pl,a2		; eine Liste ohne Palette oder keine
	clr.w	PL_ZEILE(a2)
	move.w	#1,PL_BANK(a2)
	lea	Bank_ist+64,a1
	bsr	st_platz_eintrag
	moveq	#1,d1
sst_gezaehlt:
	tst.w	d4
	bpl.b	sst_hilfs
	moveq	#0,d4
sst_hilfs:
	move.w	d1,st_pl_n
	move.w	d4,st_pl_hilfs
	move.b	st_hilfs_flag,d0
	ext.w	d0
	move.w	d0,st_pl_flag
	bsr	St_nr_stand
	; ---- Stempel: st_pl_n bis zum Ende von st_pl ----
	lea	st_pl_n,a0
	lea	st_pl_alt,a1
	moveq	#ST_PL_BLOCK/2-1,d0
sst_v:	cmpm.w	(a0)+,(a1)+
	dbne	d0,sst_v
	beq.b	sst_out
	lea	st_pl_n,a0
	lea	st_pl_alt,a1
	moveq	#ST_PL_BLOCK/2-1,d0
sst_k:	move.w	(a0)+,(a1)+
	dbf	d0,sst_k
	bsr	st_zeilen_bauen
	bsr	St_zeiger_bilder
	bsr	st_regs_bauen
	tst.b	st_nr_jetzt
	beq.b	sst_out
	bsr	St_nr_zeichnen		; die Palette kam: mit ihr neu zeichnen
sst_out:
	movem.l	(sp)+,d0-d4/d7/a0-a4
	rts

; Den Eintrag fuer die Palette a1 suchen oder bauen, in den Platz a2.
; Veraendert d0/d2-d3/a0.
st_platz_eintrag:
	move.l	PL_EINTRAG(a2),d0	; meist hat ihn der Platz schon
	beq.b	spe_suchen
	move.l	d0,a0
	bsr	St_gleich
	beq.b	spe_da
spe_suchen:
	bsr.b	st_blende		; eine Lichtstufe: Tabelle behalten
	beq.b	spe_da
	lea	st_cache,a0
	move.w	st_anzahl,d2
	subq.w	#1,d2
	bmi.b	spe_neu
spe_s:	bsr	St_gleich
	beq.b	spe_da
	lea	SE_SIZE(a0),a0
	dbf	d2,spe_s
spe_neu:
	bsr	st_opfer
	bsr	St_from_file		; precomputed (STPAL.DAT)?
	beq.b	spe_da
	bsr	St_bauen
spe_da:
	move.l	a0,PL_EINTRAG(a2)
	move.w	SE_S+ST_GEN(a0),PL_GEN(a2)
	move.l	a1,SE_QUELLE(a0)
	move.w	Map_nr,SE_KARTE(a0)
	rts

; ***************************************************************************
; st_blende -- ist die Palette a1 eine neue Lichtstufe, und welcher Eintrag
; gehoert zu ihr?
;   IN : a1 = Palette.  OUT: Z gesetzt und a0 = Eintrag, wenn ja.
;   Veraendert d0/d2/a0.
;
; Thalion blendet die Lichtstufe in 3D an Ort und Stelle: Set_D3_light_level
; (Dungeon) und Set_C3_light_level (Stadt) schreiben die Farben 0..15
; geblendet nach Current_pal und rufen Reset_current_RL.  Fuer den Inhalt
; ist das eine neue Palette; St_bauen braucht rund eine Sekunde und rechnet
; neue Gruppen, und bis das Bild neu steht, passen Register und gezeichnete
; Punkte nicht zusammen (Nutzer, 2026-10-04: falsche Farben beim Wechsel in
; die Daemmerung).
;
; Gemeint ist eine Blende, und dafuer ist der Weg schon da (docs/12,
; Blenden): die Tabelle bleibt, die Register rechnet st_regs_bauen aus
; Bank_ist, also aus den geblendeten Farben.  Als Lichtstufe gilt, was
; Current_pal ist, auf derselben Karte (Map_nr; ein Load_map fuellt
; Current_pal neu) und die Farben 16..31 gleich laesst.  Der Eintrag
; uebernimmt dann die Farben 0..15 als Schluessel; ST_GEN bleibt, Merkliste
; und Kacheln gelten weiter.
; ***************************************************************************
st_blende:
	cmpa.l	#Current_pal,a1
	bne.b	sbl_nein
	lea	st_cache,a0
	move.w	st_anzahl,d2
	subq.w	#1,d2
	bmi.b	sbl_nein
sbl_e:	cmpa.l	SE_QUELLE(a0),a1
	bne.b	sbl_w
	move.w	Map_nr,d0
	cmp.w	SE_KARTE(a0),d0
	bne.b	sbl_w
	movem.l	a2-a3,-(sp)		; Farben 16..31 gleich?
	lea	SE_KEY+32(a0),a2
	lea	32(a1),a3
	moveq	#8-1,d0
sbl_v:	cmpm.l	(a2)+,(a3)+
	dbne	d0,sbl_v
	movem.l	(sp)+,a2-a3		; movem laesst die Bedingungen stehen
	beq.b	sbl_ja
sbl_w:	lea	SE_SIZE(a0),a0
	dbf	d2,sbl_e
sbl_nein:
	moveq	#1,d0			; Z frei
	rts
sbl_ja:
	movem.l	a2-a3,-(sp)		; Schluessel: die Farben 0..15
	lea	SE_KEY(a0),a2
	move.l	a1,a3
	moveq	#8-1,d0
sbl_k:	move.l	(a3)+,(a2)+
	dbf	d0,sbl_k
	movem.l	(sp)+,a2-a3
	moveq	#0,d0			; Z gesetzt
	rts

; Ein Eintrag zum Neubauen: ein freier, sonst reihum, aber keiner, den ein
; Platz gerade traegt.  OUT: a0.  Veraendert d0/d3.
st_opfer:
	moveq	#ST_EINTRAEGE-1,d3
sto_l:	move.w	st_naechster,d0
	move.w	d0,-(sp)
	addq.w	#1,d0
	cmp.w	#ST_EINTRAEGE,d0
	bcs.b	sto_n
	moveq	#0,d0
sto_n:	move.w	d0,st_naechster
	move.w	(sp)+,d0
	mulu.w	#SE_SIZE,d0
	lea	st_cache,a0
	add.l	d0,a0
	cmp.w	#ST_EINTRAEGE,st_anzahl
	bcc.b	sto_voll
	addq.w	#1,st_anzahl		; noch frei
	rts
sto_voll:
	cmpa.l	st_pl+PL_EINTRAG,a0
	beq.b	sto_weiter
	cmpa.l	st_pl+PL_SZ+PL_EINTRAG,a0
	beq.b	sto_weiter
	cmpa.l	st_pl+2*PL_SZ+PL_EINTRAG,a0
	beq.b	sto_weiter
	rts
sto_weiter:
	dbf	d3,sto_l
	rts

; st_zsatz fuellen: je Bildzeile der Satz des Platzes, in dessen Bereich sie
; liegt; im Hilfsschirm ueberall der von st_pl_hilfs.  Dazu st_zplatz: je
; Bildzeile die Nummer dieses Platzes, fuer das Zeigerbild im VBL.
; Alle Register bleiben.
st_zeilen_bauen:
	movem.l	d0-d2/d7/a0-a2/a4,-(sp)
	lea	st_zsatz,a4
	lea	st_zplatz,a2
	lea	st_pl,a1
	moveq	#0,d1			; Nummer des Platzes
	move.w	st_pl_n,d2
	subq.w	#1,d2			; Plaetze, die noch beginnen
	tst.b	st_hilfs_flag
	beq.b	szb_los
	move.w	st_pl_hilfs,d1
	move.w	d1,d0
	mulu.w	#PL_SZ,d0
	add.l	d0,a1
	moveq	#0,d2
szb_los:
	move.l	PL_EINTRAG(a1),a0
	lea	SE_S(a0),a0
	moveq	#0,d7			; Zeile
szb_zeile:
	tst.w	d2
	beq.b	szb_satz
	cmp.w	PL_SZ+PL_ZEILE(a1),d7
	bcs.b	szb_satz
	lea	PL_SZ(a1),a1		; hier beginnt der naechste Platz
	addq.w	#1,d1
	subq.w	#1,d2
	move.l	PL_EINTRAG(a1),a0
	lea	SE_S(a0),a0
	bra.b	szb_zeile
szb_satz:
	move.l	a0,(a4)+
	move.b	d1,(a2)+
	addq.w	#1,d7
	cmp.w	#ST_ZEILEN,d7
	bcs.b	szb_zeile
	movem.l	(sp)+,d0-d2/d7/a0-a2/a4
	rts

; St_zeiger_bilder -- das Zeigerbild einmal je Platz, mit dessen Satz
; (st_zg_bilder: je Platz MPTR_H Zeilen zu vier Worten).  Hauptprogramm:
; gerufen, wenn die Plaetze neu sind (St_stand) und wenn der Zeiger wechselt
; (Pointer_convert).  Unter zeiger_sperre, damit der VBL kein halbes Bild
; abholt (269).  Alle Register bleiben.
St_zeiger_bilder:
	movem.l	d0-d6/a0-a4,-(sp)
	move.l	st_zg_quelle,d0
	beq.b	szi_raus
	addq.b	#1,zeiger_sperre
	lea	st_pl,a4
	lea	st_zg_bilder,a1
	move.w	st_pl_n,d6
	subq.w	#1,d6
	bmi.b	szi_frei
szi_platz:
	move.l	st_zg_quelle,a3
	move.l	PL_EINTRAG(a4),a2
	lea	SE_S+ST_TAB2(a2),a2
	moveq	#MPTR_H-1,d5
szi_zeile:
	move.w	(a3)+,d0
	move.w	(a3)+,d1
	move.w	(a3)+,d2
	move.w	d0,d3
	or.w	d1,d3
	or.w	d2,d3			; Ebene 3 und 4: Farbe 24 + Wert
	move.w	d3,d4
	bsr	St_block		; vier Worte nach (a1)+
	dbf	d5,szi_zeile
	lea	PL_SZ(a4),a4
	dbf	d6,szi_platz
szi_frei:
	subq.b	#1,zeiger_sperre
szi_raus:
	movem.l	(sp)+,d0-d6/a0-a4
	rts

; ***************************************************************************
; Zeilenfarbe -- Zeilenfarbe des ST (LIBRARY.S springt hierher).
;   IN : d0.w = Bildzeile, d1.w = Farbe
;   OUT: d1.w = Register.  Alle uebrigen Register bleiben.
; 0 bleibt 0.  Farben ab 32 setzt nur unsere Bibliothek; beim ST gilt davon
; das Register in den unteren vier Bits.
; ***************************************************************************
Zeilenfarbe:
	tst.w	d1
	beq.b	szf_out
	cmp.w	#1<<Data_depth,d1
	bcs.b	szf_tab
	and.w	#15,d1
	rts
szf_tab:
	move.l	a0,-(sp)
	bsr	St_zeilensatz
	move.b	ST_TAB(a0,d1.w),d1	; d1 < 32: das obere Byte ist schon 0
	move.l	(sp)+,a0
szf_out:
	rts

; ***************************************************************************
; Box_fuellen -- der Rumpf von Draw_box beim ST (LIBRARY.S springt nach
; dem Beschneiden hierher).
;   IN : a0 = erster Block der ersten Zeile, d0.w = Versatz im Block,
;        d2.w = Breite in Punkten, d3.w = Zeilen - 1, a2.w = erste
;        Bildzeile, a3.w = Farbe, wie Thalion sie meint
;   Alle Register bleiben.
;
; **Tempo (P5):** Draw_box setzte jeden Block Ebene fuer Ebene mit btst,
; 7,5 % der Zeit auf der Karte.  Hier werden die Masken des linken und des
; rechten Randblocks einmal je Aufruf gebildet, die vier Ebenenworte der
; Farbe nur, wenn sich das Register aendert, und die vollen Bloecke mit
; zwei Langworten geschrieben.  Die Farbe je Zeile wie Zeilenfarbe
; (0 bleibt 0, ab 32 fertig).
;
; Tempo (2D plan, 2026-10-21): the row set is read straight from st_zsatz
; and the register only worked out again when the set differs from the row
; above; before, every row called St_zeilensatz_schnell.
; ***************************************************************************
Box_fuellen:
	movem.l	d0-d7/a0-a6,-(sp)
	bsr	St_zeilen_pruefen
	cmp.w	#1,st_nr_zustand
	bne.b	sbf_kein_nr
	bsr	St_nr_box		; mitschreiben (Erkenntnis 241)
sbf_kein_nr:
	move.l	a0,a1			; a1 = Zeile
	; ---- Masken: d6 links (1 = setzen), d2 rechts, d7 volle Bloecke ----
	move.w	d0,d1
	add.w	d2,d1			; Ende im ersten Block gezaehlt
	move.w	#$FFFF,d6
	lsr.w	d0,d6
	cmp.w	#16,d1
	bhi.b	sbf_mehr
	move.w	#$FFFF,d7		; ein Block: links und rechts zugleich
	lsr.w	d1,d7
	not.w	d7
	and.w	d7,d6
	moveq	#0,d7
	moveq	#0,d2
	bra.b	sbf_lang
sbf_mehr:
	sub.w	#16,d1
	move.w	d1,d7
	lsr.w	#4,d7			; volle Bloecke
	and.w	#15,d1
	moveq	#0,d2
	tst.w	d1
	beq.b	sbf_lang
	move.w	#$FFFF,d2
	lsr.w	d1,d2
	not.w	d2
sbf_lang:
	move.w	d6,d0			; Masken in beide Worte
	swap	d6
	move.w	d0,d6
	move.w	d2,d0
	swap	d2
	move.w	d0,d2
	move.w	#-1,a4			; Register der letzten Zeile: keins
	sub.l	a6,a6			; Satz der letzten Zeile: keiner
	move.w	a2,d0			; a5 = st_zsatz der ersten Zeile, geklemmt
	bpl.b	sbf_z_nneg
	moveq	#0,d0
sbf_z_nneg:
	cmp.w	#ST_ZEILEN,d0
	bcs.b	sbf_z_drin
	move.w	#ST_ZEILEN-1,d0
sbf_z_drin:
	add.w	d0,d0
	add.w	d0,d0
	lea	st_zsatz,a5
	add.w	d0,a5
sbf_zeile:
	; ---- Register dieser Zeile: nur bei einem anderen Satz ----
	move.l	(a5),d0
	cmp.l	a6,d0
	beq	sbf_gleich
	move.l	d0,a6
	move.l	d0,a0
	move.w	a3,d1
	beq.b	sbf_reg
	cmp.w	#1<<Data_depth,d1
	bcs.b	sbf_tab
	and.w	#15,d1
	bra.b	sbf_reg
sbf_tab:
	move.b	ST_TAB(a0,d1.w),d1	; d1 < 32: das obere Byte ist 0
sbf_reg:
	cmp.w	a4,d1
	beq.b	sbf_gleich
	move.w	d1,a4
	moveq	#0,d4			; Ebene 0 oben, 1 unten
	btst	#0,d1
	beq.b	sbf_e0
	moveq	#-1,d4
sbf_e0:	btst	#1,d1
	bne.b	sbf_e1
	clr.w	d4
	bra.b	sbf_e1x
sbf_e1:	move.w	#-1,d4
sbf_e1x:
	moveq	#0,d5			; Ebene 2 oben, 3 unten
	btst	#2,d1
	beq.b	sbf_e2
	moveq	#-1,d5
sbf_e2:	btst	#3,d1
	bne.b	sbf_e3
	clr.w	d5
	bra.b	sbf_gleich
sbf_e3:	move.w	#-1,d5
sbf_gleich:
	; ---- links (mit Maske), Mitte (ganz), rechts (mit Maske) ----
	move.l	a1,a0
	move.l	(a0),d0
	eor.l	d4,d0
	and.l	d6,d0
	eor.l	d0,(a0)+
	move.l	(a0),d0
	eor.l	d5,d0
	and.l	d6,d0
	eor.l	d0,(a0)+
	move.w	d7,d0
	bra.b	sbf_vt
sbf_vl:	move.l	d4,(a0)+
	move.l	d5,(a0)+
sbf_vt:	dbf	d0,sbf_vl
	tst.l	d2
	beq.b	sbf_weiter
	move.l	(a0),d0
	eor.l	d4,d0
	and.l	d2,d0
	eor.l	d0,(a0)+
	move.l	(a0),d0
	eor.l	d5,d0
	and.l	d2,d0
	eor.l	d0,(a0)
sbf_weiter:
	lea	SCRROW(a1),a1
	addq.w	#1,a2
	move.w	a2,d0			; a5 weiter nur fuer die Zeilen 1..199
	subq.w	#1,d0
	cmp.w	#ST_ZEILEN-2,d0
	bhi.b	sbf_z_fest
	addq.l	#4,a5
sbf_z_fest:
	dbf	d3,sbf_zeile
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Platz_rueck -- Register -> Farbe Thalions (fuer Get_pixel).  The
; Falcon's of the same name is in RASTER.S (EFFECTS_SUP.S calls it).
;   IN : d1.w = Bildzeile, d4.w = Register
;   OUT: d4.w = Farbe.  Alle uebrigen Register bleiben.
; ***************************************************************************
Platz_rueck:
	movem.l	d0/a0,-(sp)
	move.w	d1,d0
	bsr	St_zeilensatz
	and.w	#15,d4
	move.b	ST_REP(a0,d4.w),d4
	movem.l	(sp)+,d0/a0
	rts

; ***************************************************************************
; St_block -- sechzehn Punkte aus Thalions Ebenen in vier Schirmworte.
;   IN : d0..d4 = Ebene 0..4 (Farbe n je Punkt), a2 = ST_TAB2 eines Satzes,
;        a1 = Ziel
;   OUT: vier Worte nach (a1)+.  Alle uebrigen Register bleiben.
;
; **Tempo (P2): eine Merkliste zur Laufzeit.**  Kacheln, Fenster und
; Leiste zeichnen immer wieder dieselben Blockzeilen.  Ein Platz in st_merk
; haelt fuenf Quellworte, die Tabelle (a2), ihren Bau (ST_GEN) und die vier
; Worte des Ergebnisses; gefunden wird er ueber einen Streuwert.  Ein
; Treffer kostet rund 350 Takte statt rund 1500.  Baut St_bauen einen Satz
; neu, bekommt er eine neue Nummer, und die alten Plaetze treffen nicht mehr.  Nur
; unsere Hardwareschicht, Thalions Daten bleiben, wie sie sind (Nutzer,
; 2026-10-01).
;
; Je Punkt: n aus den fuenf Ebenen, dann das Langwort Tab2[n], das je Byte
; ein Bit einer Zielebene traegt.  Nach acht Punkten stehen in den vier
; Bytes die linken acht Punkte der vier Ebenen.
; ***************************************************************************
St_block:
	movem.l	d5-d6/a3,-(sp)
	; ---- Streuwert der fuenf Ebenenworte ----
	move.w	d0,d5
	add.w	d1,d5
	rol.w	#5,d5
	add.w	d2,d5
	rol.w	#5,d5
	add.w	d3,d5
	rol.w	#5,d5
	add.w	d4,d5
	moveq	#0,d6
	move.w	d5,d6
	and.w	#ST_MERK_N-1,d6
	lsl.l	#5,d6			; 32 Byte je Platz
	lea	st_merk,a3
	add.l	d6,a3
	move.l	a3,d6			; Platz merken
	cmp.w	(a3)+,d0
	bne.b	stb_neu
	cmp.w	(a3)+,d1
	bne.b	stb_neu
	cmp.w	(a3)+,d2
	bne.b	stb_neu
	cmp.w	(a3)+,d3
	bne.b	stb_neu
	cmp.w	(a3)+,d4
	bne.b	stb_neu
	cmpa.l	(a3)+,a2
	bne.b	stb_neu
	move.w	ST_GEN-ST_TAB2(a2),d5	; Bau des Satzes
	cmp.w	(a3)+,d5
	bne.b	stb_neu
	move.l	(a3)+,(a1)+		; Treffer: vier Worte
	move.l	(a3)+,(a1)+
	movem.l	(sp)+,d5-d6/a3
	rts
stb_neu:
	move.l	d6,a3			; Platz neu belegen
	move.w	d0,(a3)+
	move.w	d1,(a3)+
	move.w	d2,(a3)+
	move.w	d3,(a3)+
	move.w	d4,(a3)+
	move.l	a2,(a3)+
	move.w	ST_GEN-ST_TAB2(a2),(a3)+
	bsr.b	St_block_direkt
	move.l	-8(a1),(a3)+		; das Ergebnis dazu
	move.l	-4(a1),(a3)+
	movem.l	(sp)+,d5-d6/a3
	rts

; ***************************************************************************
; St_block_direkt -- St_block ohne Merkliste, derselbe Vertrag.  Fuer
; Bilder, die sich jedes Mal aendern (3D): dort traefe die Merkliste nie
; und kostete nur.
; ***************************************************************************
St_block_direkt:
	movem.l	d0-d7,-(sp)
	bsr.b	st_acht
	move.l	d6,-(sp)		; linke acht Punkte
	bsr.b	st_acht
	move.l	(sp)+,d5
	move.b	d5,(a1)+		; Ebene 0: links, rechts
	move.b	d6,(a1)+
	lsr.l	#8,d5
	lsr.l	#8,d6
	move.b	d5,(a1)+		; Ebene 1
	move.b	d6,(a1)+
	lsr.l	#8,d5
	lsr.l	#8,d6
	move.b	d5,(a1)+		; Ebene 2
	move.b	d6,(a1)+
	lsr.l	#8,d5
	lsr.l	#8,d6
	move.b	d5,(a1)+		; Ebene 3
	move.b	d6,(a1)+
	movem.l	(sp)+,d0-d7
	rts

; acht Punkte, die obersten Bits von d0..d4 -> d6 (je Byte eine Ebene)
st_acht:
	moveq	#0,d6
	moveq	#7,d7
sta_punkt:
	moveq	#0,d5
	add.w	d4,d4
	addx.w	d5,d5
	add.w	d3,d3
	addx.w	d5,d5
	add.w	d2,d2
	addx.w	d5,d5
	add.w	d1,d1
	addx.w	d5,d5
	add.w	d0,d0
	addx.w	d5,d5			; d5 = n
	add.w	d5,d5
	add.w	d5,d5			; Langwort-Index
	add.l	d6,d6
	or.l	0(a2,d5.w),d6
	dbf	d7,sta_punkt
	rts

; ***************************************************************************
; St_movep_schirm -- Thalions 3D-Puffer auf den ST-Schirm (Show_MOVEP_screen,
; D3_SUP.S).
;   IN : a0 = Puffer: je 16 Punkte acht Byte, Byte p = Ebene p der linken
;             acht Punkte, Byte 4+p die der rechten (nur Ebenen 0..3)
;        a1 = Ziel, linke obere Ecke; d1.w = deren Bildzeile
;        d6.w = Gruppen je Zeile - 1, d7.w = Zeilen - 1
;   Alle Register bleiben.  Ruft St_zeilen_pruefen selbst.
;
; **Tempo (3D, 2026-10-04):** Bis dahin ging jeder Punkt einzeln durch die
; Tabelle (st_acht, rund 135 Takte je Punkt, 60 % eines 3D-Bilds).  Jetzt
; je acht Punkte zwei Schritte ueber Tabellen:
;   1. st_mv_s verteilt ein Byte der Ebene p auf die Nibbles eines
;      Langworts (Bit k -> Bit 4k+p).  Die vier Ebenen zusammen ergeben acht
;      Farben n als Nibbles: Nibble k = Punkt 7-k.  Die Tabellen stehen fest.
;   2. st_mv_t setzt je ein Byte davon (zwei Punkte) auf die Ebenen des
;      Schirms um, schon in der Lage fuer movep.l: Ebene 0 im obersten
;      Byte.  Vier Tabellen zu 256 Langworten, eine je Byte; sie haengen am
;      Satz der Zeile (ST_TAB) und werden nur neu gebaut, wenn Satz oder
;      sein Bau (ST_GEN) wechseln (st_mv_bauen).
; movep.l schreibt die vier Byte auf die Ebenenworte: links nach 0(a1),
; rechts nach 1(a1).  Die Farben sind dieselben wie ueber ST_TAB2.
; ***************************************************************************
; SMV_HAELFTE -- acht Punkte: vier Ebenenbytes aus (a0)+ -> d7 (movep-Lage).
;   a2 = st_mv_s, a3..a6 = st_mv_t (Byte 0..3); zerstoert d5, d6.
;   Der Index fuer st_mv_s ist (Ebene p * 256 + Byte) * 4: Tabelle p ist
;   die Grundtabelle um p nach links verschoben.
SMV_HAELFTE	MACRO
	; ---- 1. vier Ebenenbytes -> acht Nibbles in d6 ----
	moveq	#0,d5
	move.b	(a0)+,d5
	add.w	d5,d5
	add.w	d5,d5
	move.l	0(a2,d5.w),d6
	move.w	#$100,d5
	move.b	(a0)+,d5
	add.w	d5,d5
	add.w	d5,d5
	or.l	0(a2,d5.w),d6
	move.w	#$200,d5
	move.b	(a0)+,d5
	add.w	d5,d5
	add.w	d5,d5
	or.l	0(a2,d5.w),d6
	move.w	#$300,d5
	move.b	(a0)+,d5
	add.w	d5,d5
	add.w	d5,d5
	or.l	0(a2,d5.w),d6
	; ---- 2. je Byte (zwei Punkte) die Schirmebenen ----
	moveq	#0,d5
	move.b	d6,d5			; Byte 0: Punkte 7, 6
	add.w	d5,d5
	add.w	d5,d5
	move.l	0(a3,d5.w),d7
	move.w	d6,d5
	lsr.w	#8,d5			; Byte 1: Punkte 5, 4
	add.w	d5,d5
	add.w	d5,d5
	or.l	0(a4,d5.w),d7
	swap	d6
	moveq	#0,d5
	move.b	d6,d5			; Byte 2: Punkte 3, 2
	add.w	d5,d5
	add.w	d5,d5
	or.l	0(a5,d5.w),d7
	move.w	d6,d5
	lsr.w	#8,d5			; Byte 3: Punkte 1, 0
	add.w	d5,d5
	add.w	d5,d5
	or.l	0(a6,d5.w),d7
	ENDM

St_movep_schirm:
	movem.l	d0-d7/a0-a6,-(sp)
	bsr	St_zeilen_pruefen
	tst.b	st_mv_s_fertig
	bne.b	smv_s_da
	bsr	st_mv_s_bauen
smv_s_da:
	lea	st_mv_s,a2
	move.w	d7,d3			; Zeilen - 1
	move.w	d1,d2			; Bildzeile
	move.w	d6,d4			; Gruppen - 1
smv_zeile:
	move.l	a0,-(sp)
	move.w	d2,d0
	bsr	St_zeilensatz_schnell	; a0 = Satz
	cmp.l	st_mv_satz,a0
	bne.b	smv_neu
	move.w	ST_GEN(a0),d0
	cmp.w	st_mv_gen,d0
	beq.b	smv_alt
smv_neu:
	bsr	st_mv_bauen
smv_alt:
	move.l	(sp)+,a0
	lea	st_mv_t,a3
	lea	256*4(a3),a4
	lea	256*4(a4),a5
	lea	256*4(a5),a6
	move.l	a1,-(sp)
	movem.w	d2-d4,-(sp)
smv_gruppe:
	SMV_HAELFTE
	movep.l	d7,0(a1)		; die linken acht Punkte, Ebenen 0..3
	SMV_HAELFTE
	movep.l	d7,1(a1)		; die rechten acht Punkte
	addq.l	#8,a1
	dbf	d4,smv_gruppe
	movem.w	(sp)+,d2-d4
	move.l	(sp)+,a1
	lea	SCRROW(a1),a1
	addq.w	#1,d2
	dbf	d3,smv_zeile
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; st_mv_s_bauen -- st_mv_s: je Ebene p Bit k eines Bytes -> Bit 4k+p.  Einmal.
st_mv_s_bauen:
	movem.l	d0-d3/a0,-(sp)
	lea	st_mv_s,a0
	moveq	#0,d3			; Ebene p
smsb_p:	moveq	#0,d0			; das Byte
smsb_b:	moveq	#0,d1
	moveq	#7,d2
smsb_k:	lsl.l	#4,d1
	btst	d2,d0
	beq.b	smsb_n
	addq.l	#1,d1
smsb_n:	dbf	d2,smsb_k
	lsl.l	d3,d1
	move.l	d1,(a0)+
	addq.w	#1,d0
	cmp.w	#256,d0
	bcs.b	smsb_b
	addq.w	#1,d3
	cmp.w	#4,d3
	bcs.b	smsb_p
	st	st_mv_s_fertig
	movem.l	(sp)+,d0-d3/a0
	rts

; st_mv_bauen -- st_mv_t fuer den Satz a0.
;   Erst je Farbe n = 0..15 ein Langwort mit den Ebenenbits ihres Registers
;   in movep-Lage (Ebene q -> Bit 8*(3-q)).  Dann fuer jedes Byte v:
;   T0[v] = P[v & 15] | P[v >> 4] << 1 (das untere Nibble ist der rechte
;   Punkt des Paars), T1..T3 = T0 um 2, 4, 6 nach links.
st_mv_bauen:
	movem.l	d0-d3/a3-a4,-(sp)
	move.l	a0,st_mv_satz
	move.w	ST_GEN(a0),st_mv_gen
	lea	st_mv_p,a4
	moveq	#0,d0
smb_p:	moveq	#0,d1
	move.b	ST_TAB(a0,d0.w),d2
	btst	#0,d2
	beq.b	smb_p0
	bset	#24,d1
smb_p0:	btst	#1,d2
	beq.b	smb_p1
	bset	#16,d1
smb_p1:	btst	#2,d2
	beq.b	smb_p2
	bset	#8,d1
smb_p2:	btst	#3,d2
	beq.b	smb_p3
	bset	#0,d1
smb_p3:	move.l	d1,(a4)+
	addq.w	#1,d0
	cmp.w	#16,d0
	bcs.b	smb_p
	lea	st_mv_p,a4
	lea	st_mv_t,a3
	moveq	#0,d0			; v
smb_t:	move.w	d0,d1
	and.w	#15,d1
	add.w	d1,d1
	add.w	d1,d1
	move.l	0(a4,d1.w),d2
	move.w	d0,d1
	lsr.w	#4,d1
	add.w	d1,d1
	add.w	d1,d1
	move.l	0(a4,d1.w),d3
	add.l	d3,d3
	or.l	d3,d2
	move.l	d2,(a3)
	lsl.l	#2,d2
	move.l	d2,256*4(a3)
	lsl.l	#2,d2
	move.l	d2,2*256*4(a3)
	lsl.l	#2,d2
	move.l	d2,3*256*4(a3)
	addq.l	#4,a3
	addq.w	#1,d0
	cmp.w	#256,d0
	bcs.b	smb_t
	movem.l	(sp)+,d0-d3/a3-a4
	rts

; ***************************************************************************
; St_zeile_amiga -- eine Bildzeile Thalions (Amiga-Format) ins Schirmformat.
;   IN : a3 = Quelle, erster Block, Ebene 0
;        d6.w = Breite der Quelle in Bloecken (Abstand zweier Ebenenzeilen
;               = d6*2 Byte), d5.w = Ebenen der Quelle (1..5)
;        d4.w = Versatzbits (nur die Ebenen ab d5 bis 4)
;        d3.w = Zahl der Bloecke, a1 = Ziel (je Block vier Worte, lueckenlos)
;        a2 = ST_TAB2 des Satzes dieser Zeile
;   Alle Register bleiben.
;
; Die Ebenen ab d5 tragen die Maske "Quellwert ungleich null", wo die
; Versatzbits ihr Bit haben -- dieselbe Regel wie Put_unmasked_block beim
; Falcon, **0 bleibt 0**.
; ***************************************************************************
St_zeile_amiga:
	movem.l	d0-d7/a1/a3-a4,-(sp)
	move.w	d5,sza_tiefe
	move.w	d6,d0
	add.w	d0,d0
	move.w	d0,sza_schritt
	move.w	d4,sza_vers
	move.w	d3,sza_n
	bra	sza_weiter
sza_block:
	move.l	a3,a4
	move.w	sza_schritt,d7
	move.w	sza_tiefe,d6
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	move.w	(a4),d0
	subq.w	#1,d6
	ble.b	sza_geladen
	add.w	d7,a4
	move.w	(a4),d1
	subq.w	#1,d6
	beq.b	sza_geladen
	add.w	d7,a4
	move.w	(a4),d2
	subq.w	#1,d6
	beq.b	sza_geladen
	add.w	d7,a4
	move.w	(a4),d3
	subq.w	#1,d6
	beq.b	sza_geladen
	add.w	d7,a4
	move.w	(a4),d4
sza_geladen:
	move.w	sza_vers,d6
	beq.b	sza_setzen
	move.w	d0,d5
	or.w	d1,d5
	or.w	d2,d5
	or.w	d3,d5
	or.w	d4,d5			; Quellwert ungleich null
	btst	#0,d6
	beq.b	sza_v1
	or.w	d5,d0
sza_v1:	btst	#1,d6
	beq.b	sza_v2
	or.w	d5,d1
sza_v2:	btst	#2,d6
	beq.b	sza_v3
	or.w	d5,d2
sza_v3:	btst	#3,d6
	beq.b	sza_v4
	or.w	d5,d3
sza_v4:	btst	#4,d6
	beq.b	sza_setzen
	or.w	d5,d4
sza_setzen:
	bsr	St_block
	addq.l	#2,a3
sza_weiter:
	subq.w	#1,sza_n
	bpl	sza_block
	movem.l	(sp)+,d0-d7/a1/a3-a4
	rts

; ***************************************************************************
; Pub_zeilen -- der Amiga-Zweig von Put_unmasked_block beim ST.
; Aufgerufen mit dem Stand von Put_unmasked_block vor pub_row:
;   a0 = Quelle am ersten sichtbaren Block, a1 = Ziel, a2.w = Bildzeile,
;   d5 = Ebenen, d6 = Breite der Quelle, d7 = Versatzbits<<16 + Zeilen-1,
;   bl_anzahl = sichtbare Bloecke.  Alle Register bleiben.
; ***************************************************************************
Pub_zeilen:
	movem.l	d0-d7/a0-a4,-(sp)
	bsr	St_zeilen_pruefen
	cmp.w	#1,st_nr_zustand
	bne.b	spz_kein_nr
	bsr	St_nr_pub		; mitschreiben (Erkenntnis 241)
spz_kein_nr:
	; ---- P3: ein Symbol (ein Block, sechzehn Zeilen, alle mit demselben
	; Satz) kommt fertig aus st_kachel ----
	cmp.w	#1,d6
	bne	spz_live
	cmp.w	#1,bl_anzahl
	bne	spz_live
	cmp.w	#16-1,d7
	bne	spz_live
	move.w	a2,d0
	cmp.w	#ST_ZEILEN-16,d0
	bhi	spz_live		; auch negativ
	add.w	d0,d0
	add.w	d0,d0
	lea	st_zsatz,a3
	add.w	d0,a3
	; Erste gegen letzte Zeile genuegt (P5): die Plaetze folgen nach Zeilen
	; aufeinander und liegen weit mehr als sechzehn Zeilen auseinander;
	; tragen zwei Plaetze denselben Satz (Inv_RL: zweimal Main_pal), ist er
	; auch fuer die Zeilen dazwischen richtig.
	move.l	(a3),d0
	cmp.l	15*4(a3),d0
	bne	spz_live		; Satzgrenze im Symbol
	move.l	d0,a2
	lea	ST_TAB2(a2),a2
	move.l	d7,d4
	swap	d4			; Versatzbits
	bsr	St_kachel		; a3 = sechzehn Zeilen zu vier Worten
	; ---- ausgerollt (P5): ohne lea und dbf je Zeile ----
spz_kopie:
ZN	SET	0
	REPT	16
	move.l	(a3)+,ZN*SCRROW(a1)
	move.l	(a3)+,ZN*SCRROW+4(a1)
ZN	SET	ZN+1
	ENDR
	bra	spz_out
spz_live:
	move.l	d7,d4
	swap	d4			; Versatzbits
	move.w	bl_anzahl,d3
	move.w	a2,d2			; Bildzeile
	move.l	a0,a3
spz_zeile:
	move.w	d2,d0
	bsr	St_zeilensatz_schnell
	lea	ST_TAB2(a0),a2
	bsr	St_zeile_amiga
	move.w	d5,d0			; naechste Quellzeile: d5 Ebenenzeilen
	mulu.w	d6,d0
	add.l	d0,a3
	add.l	d0,a3
	lea	SCRROW(a1),a1
	addq.w	#1,d2
	dbf	d7,spz_zeile
spz_out:
	movem.l	(sp)+,d0-d7/a0-a4
	rts

; ***************************************************************************
; Nachreichen: eine Palette, die erst nach dem Zeichnen kommt (Erkenntnis 241)
;
; Thalions Ereignisbild (ShowPicTxt_Mod, auch GameOver_Mod) zeigt den
; unteren Teil mit der Palette in Batch: `R_palette Middle_Y+1,Batch ; !!!`.
; Gezeichnet werden Layout, Kaesten und Bild aber, **bevor** Thalion die
; Palette nach Batch kopiert (EVENTS.S ShowPicTxt_ModInit).  Amiga und
; Falcon schreiben Farbnummern, denen ist das gleich.  Der ST setzt beim
; Zeichnen Nummer -> Register mit der Tabelle der Palette, die gerade in
; Batch steht, und das war eine alte: das Bild kam gelb und blau (Nutzer,
; 2026-10-04, Savestate).  Umrechnen geht danach nicht mehr, die Tabelle
; legt mehrere Nummern auf ein Register.
;
; Darum: Solange ein Platz der Liste Batch traegt und sich deren Inhalt
; noch nicht geaendert hat, schreiben Pub_zeilen und Box_fuellen mit,
; was sie in diesen Platz zeichnen, die Quelle als Abschrift.  Aendert sich
; der Inhalt, zeichnet St_stand alles noch einmal, mit der neuen Tabelle,
; in beide Schirme.  Danach wird nicht mehr mitgeschrieben, bis die Liste
; wechselt.  Thalions Code bleibt unberuehrt.
;
; Ein Satz in st_nr_puffer:
;   .l Laenge des Satzes, .w Art (1 Pub_zeilen, 2 Box_fuellen),
;   .l Ziel minus Work_screen, dann je Art:
;   1: .w a2, d5, d6, .l d7, .w bl_anzahl, die Quelle   (Kopf 22 Byte)
;   2: .w d0, d2, d3, a2, .l a3                          (Kopf 22 Byte)
; Was Masked_icon zeichnet, wird nicht mitgeschrieben (angenommen: vor
; dem Fuellen von Batch zeichnet Thalion dort nichts Maskiertes).
; ***************************************************************************

; St_nr_stand -- aus St_stand, nachdem die Plaetze stehen.  Alle Register
; bleiben.
St_nr_stand:
	movem.l	d0-d2/a0,-(sp)
	move.w	st_nr_neu,d0
	bmi	snrs_aus		; kein Platz mit Batch
	tst.b	st_hilfs_flag
	bne	snrs_out		; Hilfsschirm: beim naechsten Mal
	mulu.w	#PL_SZ,d0
	lea	st_pl,a0
	add.w	d0,a0
	move.l	PL_EINTRAG(a0),d0
	move.w	PL_GEN(a0),d1
	move.l	st_nr_lneu,d2
	tst.w	st_nr_zustand
	beq	snrs_beginn
	cmp.l	st_nr_liste,d2
	bne	snrs_beginn		; eine andere Liste: von vorn
	cmp.w	#1,st_nr_zustand
	bne	snrs_out		; fertig oder voll
	cmp.l	st_nr_eintrag,d0
	bne	snrs_neu
	cmp.w	st_nr_gen,d1
	beq	snrs_out
snrs_neu:
	tst.l	st_nr_laenge
	beq	snrs_merken		; noch nichts gezeichnet: weiter mitschreiben
	st	st_nr_jetzt
	move.w	#2,st_nr_zustand
	bra	snrs_merken
snrs_beginn:
	move.w	#1,st_nr_zustand
	move.l	d2,st_nr_liste
	clr.l	st_nr_laenge
	move.w	PL_ZEILE(a0),st_nr_zeile
snrs_merken:
	move.l	d0,st_nr_eintrag
	move.w	d1,st_nr_gen
	bra	snrs_out
snrs_aus:
	clr.w	st_nr_zustand
	clr.l	st_nr_laenge
snrs_out:
	movem.l	(sp)+,d0-d2/a0
	rts

; St_nr_pub -- aus Pub_zeilen, mit dessen Eingaben.  Alle Register
; bleiben.
St_nr_pub:
	movem.l	d0-d3/a0-a1/a3,-(sp)
	tst.b	st_nr_aktiv
	bne	snrp_out
	tst.b	st_hilfs_flag
	bne	snrp_out
	move.w	a2,d0			; letzte Zeile im Platz mit Batch?
	add.w	d7,d0
	cmp.w	st_nr_zeile,d0
	blt	snrp_out
	; Laenge der Quelle in Worten: bis zum letzten sichtbaren Block der
	; letzten Ebene der letzten Zeile, nicht weiter
	move.w	d5,d0
	mulu.w	d6,d0			; Worte je Zeile
	moveq	#0,d1
	move.w	d7,d1
	mulu.w	d0,d1			; ganze Zeilen davor
	move.w	d5,d0
	subq.w	#1,d0
	mulu.w	d6,d0
	add.l	d0,d1
	moveq	#0,d0
	move.w	bl_anzahl,d0
	add.l	d0,d1			; d1 = Worte
	move.l	d1,d2
	add.l	d2,d2
	add.l	#22,d2			; d2 = Laenge des Satzes
	bsr	snr_platz		; a3 = Satz, oder voll
	bcs.b	snrp_out
	move.l	d2,(a3)+
	move.w	#1,(a3)+
	move.l	a1,d0
	sub.l	Work_screen,d0
	move.l	d0,(a3)+
	move.w	a2,(a3)+
	move.w	d5,(a3)+
	move.w	d6,(a3)+
	move.l	d7,(a3)+
	move.w	bl_anzahl,(a3)+
	bra.b	snrp_k
snrp_l:	move.w	(a0)+,(a3)+
snrp_k:	subq.l	#1,d1
	bpl.b	snrp_l
	addq.w	#1,Data_change_count		; der Puffer ist Quelle fuer St_kachel
snrp_out:
	movem.l	(sp)+,d0-d3/a0-a1/a3
	rts

; St_nr_box -- aus Box_fuellen, mit dessen Eingaben.  Alle Register
; bleiben.
St_nr_box:
	movem.l	d1-d2/a3,-(sp)
	tst.b	st_nr_aktiv
	bne.b	snrb_out
	tst.b	st_hilfs_flag
	bne.b	snrb_out
	move.w	a2,d1
	add.w	d3,d1
	cmp.w	st_nr_zeile,d1
	blt.b	snrb_out
	move.l	a3,-(sp)
	moveq	#22,d2
	bsr	snr_platz
	bcs.b	snrb_voll
	move.l	d2,(a3)+
	move.w	#2,(a3)+
	move.l	a0,d1
	sub.l	Work_screen,d1
	move.l	d1,(a3)+
	move.w	d0,(a3)+
	move.l	8(sp),d1		; d2 vom Aufrufer (unter a3 und d1)
	move.w	d1,(a3)+
	move.w	d3,(a3)+
	move.w	a2,(a3)+
	move.l	(sp),(a3)+		; a3 vom Aufrufer
snrb_voll:
	addq.l	#4,sp
snrb_out:
	movem.l	(sp)+,d1-d2/a3
	rts

; Platz fuer d2.l Byte in st_nr_puffer.  OUT: a3 = Satz, st_nr_laenge
; schon erhoeht; Carry: voll, dann wird nicht mehr nachgereicht.
snr_platz:
	move.l	st_nr_laenge,a3
	add.l	d2,a3
	cmpa.l	#ST_NR_GROESSE,a3
	bhi.b	snrpl_voll
	move.l	a3,st_nr_laenge
	sub.l	d2,a3
	add.l	#st_nr_puffer,a3
	andi.b	#$FE,ccr		; Carry aus
	rts
snrpl_voll:
	move.w	#3,st_nr_zustand
	ori.b	#1,ccr
	rts

; St_nr_zeichnen -- alles Mitgeschriebene noch einmal, in Off_screen und
; Schirm_vorn.  Aus St_stand, wenn Plaetze und Tabellen neu stehen.  Die
; Aufrufe darin finden St_zeilen_pruefen auf dem Stand (der Stempel ist
; schon gesetzt) und schreiben nicht mit (st_nr_aktiv).  Alle Register
; bleiben.
St_nr_zeichnen:
	movem.l	d0-d7/a0-a6,-(sp)
	sf	st_nr_jetzt
	st	st_nr_aktiv
	move.w	bl_anzahl,-(sp)
	lea	st_nr_puffer,a6
	move.l	a6,a5
	add.l	st_nr_laenge,a5
snrz_satz:
	cmpa.l	a5,a6
	bcc.b	snrz_fertig
	move.l	Off_screen,d1
	bsr.b	snrz_einer
	move.l	Schirm_vorn,d1
	cmp.l	Off_screen,d1
	beq.b	snrz_weiter
	bsr.b	snrz_einer
snrz_weiter:
	add.l	(a6),a6
	bra.b	snrz_satz
snrz_fertig:
	move.w	(sp)+,bl_anzahl
	sf	st_nr_aktiv
	clr.l	st_nr_laenge
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; Ein Satz (a6) in den Schirm d1.
snrz_einer:
	cmp.w	#1,4(a6)
	bne.b	snrz_box
	move.l	d1,a1
	add.l	6(a6),a1
	move.w	10(a6),a2
	move.w	12(a6),d5
	move.w	14(a6),d6
	move.l	16(a6),d7
	move.w	20(a6),bl_anzahl
	lea	22(a6),a0
	bra	Pub_zeilen
snrz_box:
	move.l	d1,a0
	add.l	6(a6),a0
	move.w	10(a6),d0
	move.w	12(a6),d2
	move.w	14(a6),d3
	move.w	16(a6),a2
	move.l	18(a6),a3
	bra	Box_fuellen

; ***************************************************************************
; St_kachel -- ein Symbol Thalions (ein Block breit, sechzehn Zeilen, je
; Zeile d5 Ebenenworte) im Schirmformat, aus dem Kachelspeicher.
;   IN : a0 = Quelle, a2 = ST_TAB2 des Satzes, d4.w = Versatzbits (nur die
;        Ebenen ab d5), d5.w = Ebenen der Quelle
;   OUT: a3 = 16 Zeilen zu vier Worten (128 Byte), dahinter 16 Maskenworte
;        (1 = durchsichtig).  Alle uebrigen Register bleiben.  Der Inhalt
;        gilt bis zum naechsten Aufruf.
;
; **Tempo (P3): jedes Symbol nur einmal umsetzen** (Nutzer, 2026-10-01:
; zur Laufzeit, in unserer Hardwareschicht).  Die Karte zeichnet Thalion
; in jedem Bild ganz neu, rund 160 Symbole; umgesetzt kostete das rund
; 28 VBL je Bild.  Ein Platz in st_kachel haelt Quelle, Tabelle, ihren Bau,
; Versatz, Ebenen und eine Pruefsumme der Quelle, dazu das Ergebnis.
; Gefunden wird er ueber die Quelladresse.
;
; **Neue Grafik an alter Adresse: der Ladestand** (P5, Nutzer 2026-10-03).
; Laedt Thalion einen anderen Kachelsatz in denselben Speicher, stimmt die
; Adresse, der Inhalt nicht.  Bis P4 fing das eine Pruefsumme (erstes
; Langwort jeder zweiten Zeile), 7,7 % der Zeit auf der Karte und dabei
; nicht sicher.  Jetzt zaehlt Data_change_count bei allem, was Grafik in den
; Speicher bringt: Speicher holen (MEMORY.S), Datei lesen, Entpacken
; (FILES_SUP.S), Hintergrund sichern (Get_block_orig); ein Platz gilt nur mit
; dem Stand, unter dem er gebaut wurde.  Auf der Karte kommt keins davon
; vor (Messung: kein Aufruf in 500 VBL Laufen).
;
; Dazu je Zeile die Maske fuer Masked_icon (P5): ein Bit je Punkt, 1 wo
; das Register 0 ist, also durchsichtig.
; ***************************************************************************
ST_KACHEL_N	= 2048			; Plaetze, Zweierpotenz
KA_QUELLE	= 0			; .l
KA_TAB		= 4			; .l a2
KA_GEN		= 8			; .w ST_GEN der Tabelle
KA_VERS		= 10			; .w
KA_EBENEN	= 12			; .w
KA_LADE		= 14			; .w Data_change_count beim Bau
KA_BILD		= 32			; 16 Zeilen zu vier Worten
KA_MASKE	= KA_BILD+16*8		; 16 Worte
KA_GR		= KA_MASKE+16*2		; 192 Byte

St_kachel:
	; Hit path (2D plan step 1): only d0 is saved, the rest only when the
	; slot is rebuilt.  The key stays complete (finding 271).
	move.l	d0,-(sp)
	move.l	a0,d0
	lsr.l	#5,d0
	and.w	#ST_KACHEL_N-1,d0
	mulu.w	#KA_GR,d0
	lea	st_kachel,a3
	add.l	d0,a3
	cmpa.l	KA_QUELLE(a3),a0
	bne.b	ska_neu
	cmpa.l	KA_TAB(a3),a2
	bne.b	ska_neu
	move.w	ST_GEN-ST_TAB2(a2),d0	; Bau des Satzes
	cmp.w	KA_GEN(a3),d0
	bne.b	ska_neu
	cmp.w	KA_VERS(a3),d4
	bne.b	ska_neu
	cmp.w	KA_EBENEN(a3),d5
	bne.b	ska_neu
	move.w	Data_change_count,d0
	cmp.w	KA_LADE(a3),d0
	bne.b	ska_neu
	lea	KA_BILD(a3),a3
	move.l	(sp)+,d0
	rts
ska_neu:
	movem.l	d0-d7/a0-a2/a4,-(sp)	; d0 again: register_pruefen.py reads this list
	move.l	a3,a4
	move.l	a0,KA_QUELLE(a4)
	move.l	a2,KA_TAB(a4)
	move.w	ST_GEN-ST_TAB2(a2),KA_GEN(a4)
	move.w	d4,KA_VERS(a4)
	move.w	d5,KA_EBENEN(a4)
	move.w	Data_change_count,KA_LADE(a4)
	; ---- umsetzen: sechzehn Zeilen, ein Block ----
	move.l	a0,a3
	lea	KA_BILD(a4),a1
	moveq	#1,d6			; ein Block: Ebenenworte liegen nebeneinander
	moveq	#1,d3
	moveq	#16-1,d7
	move.w	d5,d2
	add.w	d2,d2			; naechste Quellzeile: d5 Worte
ska_zeile:
	bsr	St_zeile_amiga
	addq.l	#8,a1
	add.w	d2,a3
	dbf	d7,ska_zeile
	; ---- die Masken: 1 = Register 0 ----
	lea	KA_BILD(a4),a1
	lea	KA_MASKE(a4),a3
	moveq	#16-1,d7
ska_maske:
	movem.w	(a1)+,d0-d3
	or.w	d1,d0
	or.w	d2,d0
	or.w	d3,d0
	not.w	d0
	move.w	d0,(a3)+
	dbf	d7,ska_maske
	lea	KA_BILD(a4),a3
	movem.l	(sp)+,d0-d7/a0-a2/a4
	move.l	(sp)+,d0
	rts

; ***************************************************************************
; Quelle_aufweiten -- Quelle_aufweiten des ST, derselbe Vertrag:
;   IN : a0 = Quelle (Amiga-Format), d1 = Y, d4 = Farbversatz, d5 = Ebenen,
;        d6 = Bloecke, d7 = Zeilen
;   OUT: a0 = pmo_puffer (Schirmformat, vier Ebenen) oder 0.  Alle
;        uebrigen Register bleiben.
; ***************************************************************************
Quelle_aufweiten:
	movem.l	d0-d7/a1-a4,-(sp)
	move.w	d6,d0
	mulu.w	d7,d0
	mulu.w	#TROW,d0
	cmp.l	#PMO_MAX,d0
	bhi	sqa_zuviel
	moveq	#-1,d0			; Versatzbits: von d5 bis zur Amiga-Tiefe
	lsl.w	d5,d0
	and.w	#(1<<Data_depth)-1,d0
	and.w	d4,d0
	move.w	d0,d4
	move.w	d6,d3			; alle Bloecke
	move.l	a0,a3
	lea	pmo_puffer,a1
	move.w	d1,d2
	subq.w	#1,d7
	bmi.b	sqa_fertig
	bsr	St_zeilen_pruefen
sqa_zeile:
	move.w	d2,d0
	bsr	St_zeilensatz_schnell
	lea	ST_TAB2(a0),a2
	bsr	St_zeile_amiga
	move.w	d5,d0
	mulu.w	d6,d0
	add.l	d0,a3
	add.l	d0,a3
	move.w	d6,d0
	mulu.w	#TROW,d0
	add.l	d0,a1
	addq.w	#1,d2
	dbf	d7,sqa_zeile
sqa_fertig:
	lea	pmo_puffer,a0
	bra.b	sqa_out
sqa_zuviel:
	sub.l	a0,a0
sqa_out:
	movem.l	(sp)+,d0-d7/a1-a4
	rts

; ***************************************************************************
; Get_block_orig -- Get_block des ST fuer d5 < SCHIRM_FORMAT (Amiga-Format).
;   IN : a0 = Ziel, d0/d1 = linke obere Ecke (x Vielfaches von 16),
;        d5 = Ebenen des Ziels, d6 = Bloecke, d7 = Zeilen
;   Alle Register bleiben.
;
; Je Punkt Register r -> Farbe Rep[r] der Bildzeile; davon die unteren d5
; Bits in die Ebenenzeilen, Zeile fuer Zeile, darin Ebene fuer Ebene.
; ***************************************************************************
Get_block_orig:
	addq.w	#1,Data_change_count		; neuer Inhalt im Ziel (St_kachel)
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	d5,sgb_tiefe
	move.w	d6,d2
	add.w	d2,d2
	move.w	d2,sgb_schritt		; Abstand zweier Ebenenzeilen im Ziel
	move.l	a0,a5			; a5 = Zielzeile
	move.w	d1,sgb_zeile
	lsr.w	#4,d0
	move.l	Work_screen,a1
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	mulu.w	#TROW,d0
	add.l	d0,a1			; a1 = Schirmzeile, erster Block
	subq.w	#1,d7
	bmi	sgb_out
	move.w	d7,sgb_rest		; d7 braucht die Punktschleife
	bsr	St_zeilen_pruefen
sgb_zeile_lauf:
	move.w	sgb_zeile,d0
	bsr	St_zeilensatz_schnell
	lea	ST_REP(a0),a4		; a4 = Rep
	move.l	a1,a2			; Schirmblock
	move.l	a5,a3			; Zielspalte, Ebene 0
	move.w	d6,d4
	subq.w	#1,d4
	bmi	sgb_naechste
	move.w	d4,sgb_n
sgb_block:
	; ---- Durchgang 1: sechzehn Punkte -> Farben in sgb_punkte ----
	move.w	(a2)+,d0
	move.w	(a2)+,d1
	move.w	(a2)+,d2
	move.w	(a2)+,d3
	lea	sgb_punkte,a6
	moveq	#15,d7
sgb_p1:	moveq	#0,d5
	add.w	d3,d3
	addx.w	d5,d5
	add.w	d2,d2
	addx.w	d5,d5
	add.w	d1,d1
	addx.w	d5,d5
	add.w	d0,d0
	addx.w	d5,d5			; r
	move.b	0(a4,d5.w),(a6)+	; n = Rep[r]
	dbf	d7,sgb_p1
	; ---- Durchgang 2: Farben -> fuenf Ebenenworte ----
	lea	sgb_punkte,a6
	moveq	#15,d7
sgb_p2:	move.b	(a6)+,d5
	lsr.b	#1,d5
	addx.w	d0,d0
	lsr.b	#1,d5
	addx.w	d1,d1
	lsr.b	#1,d5
	addx.w	d2,d2
	lsr.b	#1,d5
	addx.w	d3,d3
	lsr.b	#1,d5
	addx.w	d4,d4
	dbf	d7,sgb_p2
	; ---- die unteren sgb_tiefe Ebenen ablegen ----
	move.l	a3,a6
	move.w	sgb_schritt,d7
	move.w	sgb_tiefe,d5
	move.w	d0,(a6)
	subq.w	#1,d5
	ble.b	sgb_abgelegt
	add.w	d7,a6
	move.w	d1,(a6)
	subq.w	#1,d5
	beq.b	sgb_abgelegt
	add.w	d7,a6
	move.w	d2,(a6)
	subq.w	#1,d5
	beq.b	sgb_abgelegt
	add.w	d7,a6
	move.w	d3,(a6)
	subq.w	#1,d5
	beq.b	sgb_abgelegt
	add.w	d7,a6
	move.w	d4,(a6)
sgb_abgelegt:
	addq.l	#2,a3
	subq.w	#1,sgb_n
	bpl	sgb_block
sgb_naechste:
	move.w	sgb_tiefe,d0		; naechste Zielzeile: d5 Ebenenzeilen
	mulu.w	sgb_schritt,d0
	add.l	d0,a5
	lea	SCRROW(a1),a1
	addq.w	#1,sgb_zeile
	subq.w	#1,sgb_rest
	bpl	sgb_zeile_lauf
sgb_out:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Masked_icon -- Put_masked_icon des ST, derselbe Vertrag:
;   a0 = Bild (je Zeile d5 Ebenenworte), d0/d1 = Ecke (x Vielfaches von
;   16), d4 = Farbbasis, d5 = Ebenen der Quelle.  Sechzehn Zeilen, ein Block.
;   Alle Register bleiben.
; Die Farbe nimmt den Satz der ersten Zeile (S2; bis S1 die Tabelle von
; Bank 0).  Ein Symbol ueber einer Bereichsgrenze bekommt so unten die
; Register des oberen Bereichs.
; ***************************************************************************
Masked_icon:
	movem.l	d0-d2/d4/d6-d7/a0-a4,-(sp)
	move.l	a0,a3			; Quelle
	move.l	Work_screen,a4
	move.w	d1,d2
	mulu.w	#SCRROW,d2
	add.l	d2,a4
	lsr.w	#4,d0
	lsl.w	#3,d0			; * TROW
	add.w	d0,a4			; a4 = Ziel
	move.w	d1,d0
	bsr	St_zeilensatz		; S2: der Satz der ersten Zeile
	lea	ST_TAB2(a0),a2
	moveq	#-1,d2			; Versatzbits: ab d5, unter 32
	lsl.w	d5,d2
	and.w	#(1<<Data_depth)-1,d2
	and.w	d2,d4
	move.l	a3,a0
	bsr	St_kachel		; P3: a3 = sechzehn Zeilen zu vier Worten
	bsr	st_maskiert_16
	movem.l	(sp)+,d0-d2/d4/d6-d7/a0-a4
	rts

; ***************************************************************************
; st_maskiert_16 -- set a tile from St_kachel with its mask (colour 0
; transparent), sixteen rows.
;   IN : a3 = tile (KA_BILD), a4 = target.
;   OUT: a4 sixteen rows further.  Changes d0, d6, d7, a1, a3.
; P5: the mask comes ready from the tile cache.  Fully transparent rows
; are skipped, fully opaque ones copied, the others mixed with long words
; (two planes at a time).
; ***************************************************************************
	IFNE	TROW-8
	FAIL	"ST_LIB.S: lsl #3 stands for * TROW"
	ENDC
st_maskiert_16:
	lea	KA_MASKE-KA_BILD(a3),a1
	moveq	#16-1,d7
smi_zeile:
	move.w	(a1)+,d6
	cmp.w	#-1,d6
	beq.b	smi_leer
	tst.w	d6
	beq.b	smi_voll
	move.w	d6,d0
	swap	d6
	move.w	d0,d6			; Maske in beiden Worten
	and.l	d6,(a4)
	move.l	(a3)+,d0
	or.l	d0,(a4)+
	and.l	d6,(a4)
	move.l	(a3)+,d0
	or.l	d0,(a4)
	lea	SCRROW-4(a4),a4
	dbf	d7,smi_zeile
	rts
smi_leer:
	addq.l	#8,a3
	lea	SCRROW(a4),a4
	dbf	d7,smi_zeile
	rts
smi_voll:
	move.l	(a3)+,(a4)+
	move.l	(a3)+,(a4)
	lea	SCRROW-4(a4),a4
	dbf	d7,smi_zeile
	rts

; ***************************************************************************
; Unmasked_icon -- Put_unmasked_icon of the ST (2D plan step 1, docs/05c),
; the same contract: a0 = icon (Thalion's format), d0.w/d1.w = corner (x
; rounded down to 16), d4.w = colour offset, d5.w = planes of the source.
; All registers are preserved.
;
; The map draws about 160 tiles per frame; on the generic path
; (Put_unmasked_icon -> pub_ohne_ca -> Pub_zeilen -> St_kachel) a tile
; cost 3.1 k cycles, 0.65 k of them the copy (profile 2026-10-21).  This
; entry takes exactly the case the map has: 1..5 planes, x on the screen,
; rows 0..ST_ZEILEN-16 with one set over all sixteen, no late palette
; recording (finding 241).  Everything else goes to sui_allgemein with the
; registers as received.  The result is that of the generic tile path.
; ***************************************************************************
Unmasked_icon:
	cmp.w	#ST_ZEILEN-16,d1
	bhi	sui_allgemein		; auch negativ
	cmp.w	#SCRW-1,d0
	bhi	sui_allgemein
	tst.w	d5
	beq	sui_allgemein
	cmp.w	#Data_depth,d5
	bhi	sui_allgemein
	bsr	St_zeilen_pruefen
	cmp.w	#1,st_nr_zustand
	beq	sui_allgemein		; mitschreiben: der allgemeine Weg
	movem.l	d0-d2/d4/a0-a3,-(sp)
	move.w	d1,d2
	add.w	d2,d2
	add.w	d2,d2
	lea	st_zsatz,a3
	move.l	0(a3,d2.w),a2
	cmpa.l	15*4(a3,d2.w),a2
	bne	sui_zurueck		; Satzgrenze im Symbol (P5)
	lea	ST_TAB2(a2),a2
	moveq	#-1,d2			; Versatzbits: ab d5, unter 32
	lsl.w	d5,d2
	and.w	#(1<<Data_depth)-1,d2
	and.w	d2,d4
	move.l	Work_screen,a1
	mulu.w	#SCRROW,d1
	add.l	d1,a1
	lsr.w	#4,d0
	lsl.w	#3,d0			; * TROW
	add.w	d0,a1
	bsr	St_kachel		; a3 = sechzehn Zeilen zu vier Worten
ZN	SET	0
	REPT	16
	move.l	(a3)+,ZN*SCRROW(a1)
	move.l	(a3)+,ZN*SCRROW+4(a1)
ZN	SET	ZN+1
	ENDR
	movem.l	(sp)+,d0-d2/d4/a0-a3
	rts
sui_zurueck:
	movem.l	(sp)+,d0-d2/d4/a0-a3
sui_allgemein:
	; The generic body behind the hook in Put_unmasked_icon (LIBRARY.S).
	jmp	pui_allgemein

; ***************************************************************************
; Pm2_schnell -- Put_masked_block2 of the ST for the common case (2D plan
; step 3, docs/05c), called behind Block_beschneiden.
;   IN : a0 = source (Thalion's format, clipped), d0.w = X, d1.w = Y
;        (clipped), d4.w = colour offset, d5.w = planes, d6.w = blocks,
;        d7.w = rows (clipped), bl_links/bl_rechts
;   OUT: C clear = drawn; C set = not handled, the generic path follows.
;        All registers are preserved.
;
; Party and persons on the map are 16x32 figures; widened by
; Quelle_aufweiten and set by Maskiert_setzen they cost about 96 k
; cycles each (profile 2026-10-21).  Here each sixteen rows are a tile
; from St_kachel, set like Masked_icon.  Handled: one block wide, X on
; a block boundary and visible, 1..5 planes, a multiple of sixteen rows,
; each sixteen with one set.  The mask is the same as in Maskiert_setzen:
; register 0 is transparent.  All checks come before the first write.
; ***************************************************************************
Pm2_schnell:
	cmp.w	#1,d6
	bne	spm_nein
	tst.w	d5
	beq	spm_nein
	cmp.w	#Data_depth,d5
	bhi	spm_nein
	movem.l	d0-d7/a0-a4,-(sp)
	move.w	d0,d2
	and.w	#15,d2
	bne	spm_zurueck		; Schiebeweite
	tst.w	bl_links
	bgt	spm_zurueck
	tst.w	bl_rechts
	bmi	spm_zurueck		; der Block liegt ausserhalb der CA
	move.w	d7,d3
	and.w	#15,d3
	bne	spm_zurueck		; kein Vielfaches von sechzehn Zeilen
	move.w	d1,d2
	bmi	spm_zurueck
	add.w	d7,d2
	cmp.w	#ST_ZEILEN,d2
	bhi	spm_zurueck
	bsr	St_zeilen_pruefen
	; ---- Ziel ----
	move.l	Work_screen,a4
	move.w	d1,d2
	mulu.w	#SCRROW,d2
	add.l	d2,a4
	asr.w	#4,d0
	lsl.w	#3,d0			; * TROW
	add.w	d0,a4
	; ---- erst pruefen: je sechzehn Zeilen ein Satz ----
	add.w	d1,d1
	add.w	d1,d1			; d1 = Versatz in st_zsatz
	lsr.w	#4,d7
	subq.w	#1,d7
	move.w	d7,d3			; d3 = Streifen - 1
	lea	st_zsatz,a2
	add.w	d1,a2
spm_pruef:
	move.l	(a2),d0
	cmp.l	15*4(a2),d0
	bne	spm_zurueck
	lea	16*4(a2),a2
	dbf	d7,spm_pruef
	; ---- zeichnen ----
	moveq	#-1,d2			; Versatzbits: ab d5, unter 32
	lsl.w	d5,d2
	and.w	#(1<<Data_depth)-1,d2
	and.w	d2,d4
	move.w	d5,d2
	lsl.w	#5,d2			; sechzehn Zeilen zu d5 Worten
spm_streifen:
	lea	st_zsatz,a2
	move.l	0(a2,d1.w),a2
	lea	ST_TAB2(a2),a2
	bsr	St_kachel
	bsr	st_maskiert_16
	add.w	d2,a0
	add.w	#16*4,d1
	dbf	d3,spm_streifen
	movem.l	(sp)+,d0-d7/a0-a4
	andi.b	#$FE,ccr		; C aus: gezeichnet
	rts
spm_zurueck:
	movem.l	(sp)+,d0-d7/a0-a4
spm_nein:
	ori.b	#1,ccr			; C an: der allgemeine Weg
	rts

; ***************************************************************************
; Pointer_convert -- Set_mouse_ptr des ST (AREAS.S ruft es; the Falcon's
; of the same name is in FALCON_LIB.S).
;   IN : a0 = Bildzeilen Thalions (je Zeile drei Ebenenworte, 16 Zeilen),
;        a1 = zg_bild, a2 = zg_maske
;   Alle Register bleiben.
; Hier entstehen die Maske und das Bild je Platz (St_zeiger_bilder); das
; Bild an der Stelle setzt Zeiger_bild daraus zusammen (S2).
; ***************************************************************************
Pointer_convert:
	movem.l	d0-d3/d7/a0/a2,-(sp)
	move.l	a0,st_zg_quelle
	moveq	#MPTR_H-1,d7
szw_zeile:
	move.w	(a0)+,d0
	move.w	(a0)+,d1
	move.w	(a0)+,d2
	or.w	d1,d0
	or.w	d2,d0			; Punkte des Zeigers
	not.w	d0			; Maske: 1 = durchsichtig
	move.w	d0,(a2)+
	move.w	d0,(a2)+
	move.w	d0,(a2)+
	move.w	d0,(a2)+
	dbf	d7,szw_zeile
	bsr	St_zeilen_pruefen	; Plaetze auf den Stand, dann die Bilder
	bsr	St_zeiger_bilder
	movem.l	(sp)+,d0-d3/d7/a0/a2
	rts

; ***************************************************************************
; Zeiger_bild -- das Zeigerbild fuer eine Stelle (Zeiger_in_puffer,
; LIBRARY.S, ruft es zuerst).
;   IN : d1.w = Bildzeile der Zeigerecke (darf ausserhalb liegen)
;   Alle Register bleiben.
;
; Auf dem Amiga ist der Zeiger ein Sprite: er traegt die Farben 24 + Wert
; der Palette, ueber der er steht (Erkenntnis 266).  Mit 16 Registern je
; Bereich heisst das: jede Zeile des Zeigers durch den Satz ihrer Bildzeile.
;
; **Auch im VBL** (Zeiger_vbl, 269): darum rechnet es nichts und ruft
; nichts.  Die Bilder je Platz stehen fertig in st_zg_bilder
; (St_zeiger_bilder), welcher Platz zu welcher Zeile gehoert, in st_zplatz;
; hier werden nur sechzehn Zeilen zu acht Byte umkopiert.
; ***************************************************************************
Zeiger_bild:
	movem.l	d0-d3/a0-a2,-(sp)
	tst.l	st_zg_quelle
	beq.b	szbi_raus
	lea	zg_bild,a1
	lea	st_zplatz,a2
	moveq	#0,d3			; Zeile im Zeigerbild, mal acht
szbi_zeile:
	move.w	d1,d0			; Bildzeile ins Bild klemmen
	bpl.b	szbi_nneg
	moveq	#0,d0
szbi_nneg:
	cmp.w	#ST_ZEILEN,d0
	bcs.b	szbi_drin
	move.w	#ST_ZEILEN-1,d0
szbi_drin:
	moveq	#0,d2
	move.b	0(a2,d0.w),d2		; Platz dieser Bildzeile
	mulu.w	#MPTR_H*8,d2
	add.w	d3,d2
	lea	st_zg_bilder,a0
	add.w	d2,a0
	move.l	(a0)+,(a1)+
	move.l	(a0),(a1)+
	addq.w	#1,d1
	addq.w	#8,d3
	cmp.w	#MPTR_H*8,d3
	bcs.b	szbi_zeile
szbi_raus:
	movem.l	(sp)+,d0-d3/a0-a2
	rts

; ***************************************************************************
; st_rl -- die Rasterliste, die gilt: die des obersten Moduls, sonst die des
; naechsten darunter, das eine hat (Erkenntnis 264, wie Farbbank).
;   OUT: d0 = Rasterliste oder 0.  Alle uebrigen Register bleiben.
; ***************************************************************************
st_rl:
	move.l	a0,-(sp)
	move.l	Module_Sp,d0
	beq.b	srl_out
	move.l	d0,a0
srl_modul:
	move.l	Raster_list_ptr(a0),d0
	bne.b	srl_out
	lea	-Module_data_size(a0),a0	; das Modul darunter
	cmpa.l	#ModStack_start,a0
	bcc.b	srl_modul
	moveq	#0,d0
srl_out:
	move.l	(sp)+,a0
	rts

; a0 = Eintrag, a1 = Palette.  Z gesetzt, wenn gleich.  Alle Register bleiben.
St_gleich:
	movem.l	a2-a3,-(sp)
	move.l	a0,a2
	move.l	a1,a3
	REPT	15			; P4: ohne Schleife
	cmpm.l	(a2)+,(a3)+
	bne.b	stg_raus
	ENDR
	cmpm.l	(a2)+,(a3)+
stg_raus:
	movem.l	(sp)+,a2-a3		; movem laesst die Bedingungen stehen
	rts

; ***************************************************************************
; **DEVIATION (goal 2), docs/17-deviations.md D1: precomputed palettes.**
;
; St_bauen needs about one second on 8 MHz for every palette it has not
; seen.  The build therefore reduces every palette the game puts into a
; raster list (Palettes.amb, Main_pal, Tactic_pal, Automap_pal, the combat
; palettes) the same way and writes the result into STPAL.DAT
; (tools/st_palettes.py build); hand corrections come from
; tools/st_palettes.txt.  The ST loads the file once at start; a palette
; found there costs a copy instead of St_bauen.  Thalion's colours still
; come from the original files at run time; the file is only the key to
; find an entry.  Without the file, or for a palette not in it (a fade
; in between, another game version), St_bauen computes as before.
;
; One entry (STP_GROESSE bytes, big-endian, written by the tool):
;   32 words  the palette as Thalion has it (the key)
;   32 bytes  colour -> register (ST_TAB)
;   16 bytes  register -> representative colour (ST_REP)
;   16 words  register values on the STE, $0RGB, 0..15 per channel
;   16 words  register values on the plain ST, on the same scale (the ST
;             shows the upper three bits of each channel)
; In front an 8 byte header: "STP1", .w entries, .w STP_GROESSE.
; ***************************************************************************
STP_KOPF = 8
STP_TAB	= 64
STP_REP	= 96
STP_STE	= 112
STP_ST	= 144
STP_GROESSE = 176		; ENTRY_SIZE in tools/st_palettes.py
STP_MAX	= 112			; MAX_ENTRIES in tools/st_palettes.py

	IFNE	STP_REP-STP_TAB-ST_REP
	FAIL	"St_from_file copies ST_TAB and ST_REP in one go"
	ENDC

; St_load_palettes -- read STPAL.DAT next to the game files (Datei_name puts
; AMBFILES\ in front when the folder is there).  Open_screen (ST.S) calls it
; once.  A missing, short or foreign file leaves stp_anzahl at 0: then
; St_bauen computes every palette.  All registers are kept.
St_load_palettes:
	movem.l	d0-d4/a0,-(sp)
	clr.w	stp_anzahl
	lea	stp_name,a0
	moveq	#0,d1			; number 0: the name is in a0
	jsr	Datei_name		; FILES_SUP.S
	clr.w	-(sp)			; Fopen(name, read)
	move.l	a0,-(sp)
	move.w	#Fopen,-(sp)
	Gemdos
	addq.l	#8,sp
	tst.l	d0
	bmi.b	slp_out
	move.w	d0,d3
	pea	stp_puffer		; Fread(handle, all that fits, buffer)
	move.l	#STP_KOPF+STP_GROESSE*STP_MAX,-(sp)
	move.w	d3,-(sp)
	move.w	#Fread,-(sp)
	Gemdos
	lea	12(sp),sp
	move.l	d0,d4			; bytes read (negative: error)
	move.w	d3,-(sp)		; Fclose(handle)
	move.w	#Fclose,-(sp)
	Gemdos
	addq.l	#4,sp
	lea	stp_puffer,a0
	cmp.l	#'STP1',(a0)
	bne.b	slp_out
	cmp.w	#STP_GROESSE,6(a0)
	bne.b	slp_out
	moveq	#0,d0
	move.w	4(a0),d0
	cmp.w	#STP_MAX,d0
	bhi.b	slp_out
	mulu.w	#STP_GROESSE,d0
	addq.l	#STP_KOPF,d0
	cmp.l	d4,d0			; all entries read?
	bgt.b	slp_out
	move.w	4(a0),stp_anzahl
slp_out:
	movem.l	(sp)+,d0-d4/a0
	rts

	SECTION	Fast_DATA,data
stp_name:	dc.b	"STPAL.DAT",0
	even
	SECTION	Program,code

; St_from_file -- fill entry a0 for palette a1 from STPAL.DAT.
;   OUT: Z set if the file has it.  All registers are kept.
;
; Only the palette exactly as it is.  A 3D light level seen first (a map
; entered in the dark) is not looked up through Backup_pal: Thalion dims
; only colours 0..15, so the groups of the bright palette would put dimmed
; and undimmed colours into one register, and the dark floor came out brown
; in Hatari (2026-10-17).  St_bauen groups the dimmed palette as it is.
; Fades and later light levels keep the entry (st_blende); its registers
; follow the colours through SE_HSUMME (srp_hand).
St_from_file:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	a0,a5			; a5 = entry
	move.w	stp_anzahl,d7
	beq	sff_nein
	subq.w	#1,d7
	lea	stp_puffer+STP_KOPF,a4
	move.w	d7,d6
sff_g:	move.l	a4,a0			; the key is at the start, like SE_KEY
	bsr	St_gleich
	beq.b	sff_da
	lea	STP_GROESSE(a4),a4
	dbf	d6,sff_g
	bra	sff_nein
sff_da:
	addq.w	#1,st_gen		; new number: Merkliste and Kacheln expire
	move.w	st_gen,SE_S+ST_GEN(a5)
	move.l	a1,a2			; key: the palette as it stands
	move.l	a5,a3
	moveq	#16-1,d0
sff_k:	move.l	(a2)+,(a3)+
	dbf	d0,sff_k
	lea	STP_TAB(a4),a2		; table and representatives
	lea	SE_S+ST_TAB(a5),a3
	moveq	#(32+16)/4-1,d0
sff_t:	move.l	(a2)+,(a3)+
	dbf	d0,sff_t
	move.l	a4,-(sp)		; stb_ebenen changes a4
	lea	SE_S(a5),a0
	bsr	stb_ebenen
	move.l	(sp)+,a4
	bsr	st_rmaske
	lea	STP_STE(a4),a2		; the values for this machine
	tst.b	Feinbasis		; STE and later: four bits per channel
	bne.b	sff_ste
	lea	STP_ST(a4),a2
sff_ste:
	lea	SE_HWERT(a5),a3
	moveq	#8-1,d0
sff_w:	move.l	(a2)+,(a3)+
	dbf	d0,sff_w
	lea	st_summe,a0		; the file palette per register
	moveq	#16*4-1,d0
sff_s0:	clr.w	(a0)+
	dbf	d0,sff_s0
	move.l	a4,a2			; (the bright one; a1 may be dimmed)
	lea	SE_S+ST_TAB(a5),a4
	move.w	SE_RMASKE(a5),d3
	bsr	b0st_summieren
	lea	st_summe,a2
	lea	SE_HSUMME(a5),a3
	moveq	#16*8/4-1,d0
sff_s1:	move.l	(a2)+,(a3)+
	dbf	d0,sff_s1
	move.w	#1,SE_HAND(a5)
	moveq	#0,d0			; Z set; movem keeps the flags
	movem.l	(sp)+,d0-d7/a0-a6
	rts
sff_nein:
	moveq	#1,d0			; Z clear
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; St_bauen -- einen Eintrag rechnen.
;   IN : a0 = Eintrag, a1 = Palette.  Alle Register bleiben.
;
; 1. Die Rampe: Thalions Farben 26..31, doppelte nur einmal.  Show_layout
;    legt den Rahmen mit Farbversatz 24 und drei Ebenen, benutzt sind
;    26..31; Fenster (Window_colour 28), Schrift (31) und Inventar auch.
;    Hoechstens ST_RAMPE_REG Gruppen, nur unter sich (wie Schritt 3).
; 2. Die uebrigen Farben 1..25, ohne doppelte und ohne die Werte der Rampe,
;    auf die freien Register: hoechstens 15 Gruppen insgesamt.
; 3. Gruppen: wenige Punkte -- jeder eine.  Sonst die Mitten nach dem
;    weitesten Punkt (ohne feste Mitten der erste Punkt, dann immer der, der
;    von allen Mitten am weitesten liegt), danach acht Runden k-means; die
;    Mitten der Rampe bleiben dabei stehen.  Die Mitten rechnen in
;    Viertelstufen (0..60), gerundet auf die 16 Stufen des STE.
; 4. Tabelle: jede Farbe zur naechsten Mitte, Register = Mitte + 1; eine
;    Farbe der Rampe nur zu einer Mitte der Rampe.  Stellvertreter: die
;    erste Farbe mit diesem Register, sonst die, die der Mitte am naechsten
;    liegt.
;
; **Rampenschutz** (Nutzer, 2026-10-04): Ohne ihn fasste k-means Stufen der
; Rampe mit Kartenfarben zusammen, und das Grau glitt ins Moosgruene ab
; (Inventar mit Main_pal: Hintergrund gruenlich, Figur braun).  Eine
; Kartenfarbe darf ein Rampenregister mitbenutzen, der Abstand dorthin zaehlt
; aber doppelt (stb_naechste), sonst nimmt die Rampe bunten Farben ihr
; Register.  In den Wert eines Rampenregisters rechnen nur Farben der Rampe
; (SE_RMASKE, b0st_summieren).  Bilder und Wahl der Werte:
; tools/st_palettes.py, docs/12.
; ***************************************************************************
ST_RAMPE_ERSTE = 26		; Thalions UI-Rampe: 26..31
ST_RAMPE_REG = 5		; so viele Register hoechstens fuer sie

St_bauen:
	movem.l	d0-d7/a0-a6,-(sp)
	addq.w	#1,st_gen		; neue Nummer: Merkliste und Kacheln verfallen
	move.l	a0,a5			; a5 = Eintrag
	move.w	st_gen,SE_S+ST_GEN(a5)
	clr.w	SE_HAND(a5)		; registers from the group means
	; ---- Schluessel ----
	move.l	a1,a2
	move.l	a5,a3
	moveq	#32-1,d0
stb_k:	move.w	(a2)+,(a3)+
	dbf	d0,stb_k
	; ---- 1. die Rampe, doppelte nur einmal ----
	lea	st_rampe,a3
	moveq	#0,d6
	lea	ST_RAMPE_ERSTE*2(a1),a2
	moveq	#32-ST_RAMPE_ERSTE-1,d2
stb_r1:	move.w	(a2)+,d0
	and.w	#$0FFF,d0
	lea	st_rampe,a0
	move.w	d6,d1
	subq.w	#1,d1
	bmi.b	stb_r3
stb_r2:	cmp.w	(a0)+,d0
	beq.b	stb_r4
	dbf	d1,stb_r2
stb_r3:	move.w	d0,(a3)+
	addq.w	#1,d6
stb_r4:	dbf	d2,stb_r1
	move.w	d6,st_nrp
	; ... gruppiert, nur unter sich
	lea	st_rampe,a0
	lea	st_pkt,a3
	move.w	d6,st_np
	subq.w	#1,d6
stb_r5:	move.w	(a0)+,(a3)+
	dbf	d6,stb_r5
	clr.w	st_nf
	moveq	#ST_RAMPE_REG,d5
	cmp.w	st_np,d5
	bls.b	stb_r6
	move.w	st_np,d5
stb_r6:	bsr	stb_mitten
	move.w	st_nc,st_nf		; ab hier stehen sie fest
	moveq	#0,d4
	bsr	stb_stufen
	; ---- 2. die uebrigen Farben 1..25 ----
	lea	st_pkt,a3
	moveq	#0,d6
	lea	2(a1),a2
	moveq	#ST_RAMPE_ERSTE-1-1,d2
stb_p1:	move.w	(a2)+,d0
	and.w	#$0FFF,d0
	lea	st_rampe,a0		; ein Wert der Rampe gehoert dorthin
	move.w	st_nrp,d1
	subq.w	#1,d1
stb_p2:	cmp.w	(a0)+,d0
	beq.b	stb_p5
	dbf	d1,stb_p2
	lea	st_pkt,a0
	move.w	d6,d1
	subq.w	#1,d1
	bmi.b	stb_p4
stb_p3:	cmp.w	(a0)+,d0
	beq.b	stb_p5
	dbf	d1,stb_p3
stb_p4:	move.w	d0,(a3)+
	addq.w	#1,d6
stb_p5:	dbf	d2,stb_p1
	move.w	d6,st_np
	moveq	#15,d5
	bsr	stb_mitten
	move.w	st_nf,d4
	bsr	stb_stufen
	; ---- 4. Tabellen ----
	move.w	(a5),SE_MITTE(a5)	; Register 0: Farbe 0
	move.w	st_nc,SE_NC(a5)
	lea	SE_S(a5),a0
	move.l	a1,a2
	bsr	stb_satz
	bsr.b	st_rmaske
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; Rampenregister: in ihren Wert rechnen nur Farben der Rampe.  SE_RMASKE
; aus der Tabelle des Eintrags a5.  Veraendert d0/d1/d7.
st_rmaske:
	moveq	#0,d1
	moveq	#ST_RAMPE_ERSTE,d7
stb_m:	move.b	SE_S+ST_TAB(a5,d7.w),d0
	bset	d0,d1
	addq.w	#1,d7
	cmp.w	#32,d7
	bcs.b	stb_m
	move.w	d1,SE_RMASKE(a5)
	rts

; stb_mitten -- Mitten fuer die Punkte in st_pkt (st_np) nach st_mit, hinter
; die st_nf festen, die stehen bleiben.  IN: d5.w = Mitten insgesamt.
; OUT: st_nc.  Veraendert d0-d7/a0/a3/a4.
stb_mitten:
	lea	st_mit,a4
	move.w	st_nf,d0
	mulu.w	#6,d0
	add.w	d0,a4			; a4 = erste freie Mitte
	move.w	d5,d0
	sub.w	st_nf,d0		; freie Mitten
	move.w	st_np,d6
	cmp.w	d0,d6
	bhi.b	stm_kmeans
	; wenige Punkte: jeder eine Mitte
	move.w	st_nf,d0
	add.w	d6,d0
	move.w	d0,st_nc
	lea	st_pkt,a3
	subq.w	#1,d6
	bmi.b	stm_out
stm_jeder:
	move.w	(a3)+,d0
	bsr	stb_viertel		; -> (a4)+
	dbf	d6,stm_jeder
stm_out:
	rts
stm_kmeans:
	move.w	d5,st_nc
	move.w	st_nf,d5		; Mitten bisher
	bne.b	stm_weit
	move.w	st_pkt,d0		; ohne feste Mitten: der erste Punkt
	bsr	stb_viertel
	moveq	#1,d5
stm_weit:
	cmp.w	st_nc,d5
	bcc.b	stm_runden
	; den Punkt suchen, dessen naechste Mitte am weitesten liegt
	lea	st_pkt,a3
	move.w	st_np,d4
	subq.w	#1,d4
	moveq	#-1,d7			; groesster Abstand bisher
	moveq	#0,d6			; sein Punkt
stm_w1:	move.w	(a3)+,d0
	move.w	d5,d2
	bsr	stb_naechste		; d1 = Abstand zur naechsten der d2 Mitten
	cmp.l	d7,d1
	ble.b	stm_w2
	move.l	d1,d7
	move.w	d0,d6
stm_w2:	dbf	d4,stm_w1
	move.w	d6,d0
	bsr	stb_viertel		; neue Mitte ans Ende (a4 zeigt dorthin)
	addq.w	#1,d5
	bra.b	stm_weit
stm_runden:
	; acht Runden k-means
	moveq	#8-1,d7
stm_runde:
	; Summen leeren: je Mitte R, G, B, Anzahl (Worte)
	lea	st_summe,a0
	moveq	#16*4-1,d0
stm_s0:	clr.w	(a0)+
	dbf	d0,stm_s0
	lea	st_pkt,a3
	move.w	st_np,d4
	subq.w	#1,d4
stm_s1:	move.w	(a3)+,d0
	move.w	st_nc,d2
	bsr	stb_naechste		; d3 = Nummer der Mitte
	lea	st_summe,a0
	lsl.w	#3,d3
	add.w	d3,a0
	move.w	d0,d1			; R4
	lsr.w	#6,d1
	and.w	#$3C,d1
	add.w	d1,(a0)+
	move.w	d0,d1			; G4
	lsr.w	#2,d1
	and.w	#$3C,d1
	add.w	d1,(a0)+
	move.w	d0,d1			; B4
	lsl.w	#2,d1
	and.w	#$3C,d1
	add.w	d1,(a0)+
	addq.w	#1,(a0)
	dbf	d4,stm_s1
	; freie Mitten = Mittel (gerundet); leere Gruppen bleiben
	move.w	st_nf,d0
	lea	st_summe,a0
	move.w	d0,d1
	lsl.w	#3,d1
	add.w	d1,a0
	lea	st_mit,a4
	mulu.w	#6,d0
	add.w	d0,a4
	move.w	st_nc,d4
	sub.w	st_nf,d4
	subq.w	#1,d4
stm_m1:	move.w	6(a0),d2		; Anzahl
	beq.b	stm_m2
	moveq	#2,d3			; drei Kanaele
stm_m3:	moveq	#0,d0
	move.w	(a0)+,d0
	move.w	d2,d1
	lsr.w	#1,d1
	add.l	d1,d0			; runden
	divu.w	d2,d0
	move.w	d0,(a4)+
	dbf	d3,stm_m3
	addq.l	#2,a0
	bra.b	stm_m4
stm_m2:	addq.l	#8,a0
	addq.l	#6,a4
stm_m4:	dbf	d4,stm_m1
	dbf	d7,stm_runde
	rts

; stb_stufen -- die Mitten d4..st_nc-1 auf die 16 Stufen: v = (c4 + 2) / 4,
; als $0RGB nach SE_MITTE (a5 = Eintrag) und als v*4 zurueck nach st_mit
; (fuer die Tabellen).  Veraendert d0/d3-d5/a3/a4.
stb_stufen:
	lea	st_mit,a4
	move.w	d4,d0
	mulu.w	#6,d0
	add.w	d0,a4
	lea	SE_MITTE+2(a5),a3
	add.w	d4,a3
	add.w	d4,a3
	move.w	st_nc,d0
	sub.w	d4,d0
	subq.w	#1,d0
	bmi.b	stu_out
	move.w	d0,d4
stu_r1:	moveq	#0,d5			; $0RGB
	moveq	#2,d3
stu_r2:	move.w	(a4),d0
	addq.w	#2,d0
	lsr.w	#2,d0
	cmp.w	#15,d0
	bls.b	stu_r3
	moveq	#15,d0
stu_r3:	lsl.w	#4,d5
	or.w	d0,d5
	lsl.w	#2,d0
	move.w	d0,(a4)+
	dbf	d3,stu_r2
	move.w	d5,(a3)+
	dbf	d4,stu_r1
stu_out:
	rts

; $0RGB in d0 als R4, G4, B4 nach (a4)+.  Veraendert d1.
stb_viertel:
	move.w	d0,d1
	lsr.w	#6,d1
	and.w	#$3C,d1
	move.w	d1,(a4)+
	move.w	d0,d1
	lsr.w	#2,d1
	and.w	#$3C,d1
	move.w	d1,(a4)+
	move.w	d0,d1
	lsl.w	#2,d1
	and.w	#$3C,d1
	move.w	d1,(a4)+
	rts

; Naechste Mitte zu $0RGB in d0, gesucht unter den ersten d2 Mitten
; (st_mit).  Zu den st_nf festen (der Rampe) zaehlt der Abstand doppelt.
; OUT: d1.l = Abstand, d3.w = Nummer.  d0, d2, d4-d7 bleiben.
stb_naechste:
	movem.l	d2/d4-d6/a2,-(sp)
	lea	st_mit,a2
	move.l	#$7FFFFFFF,d5
	moveq	#0,d6			; Nummer der laufenden Mitte
	subq.w	#1,d2
stn_l:	bsr.b	st_abstand		; d1
	cmp.w	st_nf,d6
	bcc.b	stn_frei
	add.l	d1,d1			; Mitte der Rampe: Abstand doppelt
stn_frei:
	cmp.l	d5,d1
	bge.b	stn_w
	move.l	d1,d5
	move.w	d6,d3
stn_w:	addq.l	#6,a2
	addq.w	#1,d6
	dbf	d2,stn_l
	move.l	d5,d1
	movem.l	(sp)+,d2/d4-d6/a2
	rts

; Abstand von $0RGB in d0 zur Mitte (a2): R4, G4, B4.  OUT d1.l.  Veraendert d4.
st_abstand:
	move.w	d0,d4
	lsr.w	#6,d4
	and.w	#$3C,d4
	sub.w	(a2),d4
	muls.w	d4,d4
	move.l	d4,d1
	move.w	d0,d4
	lsr.w	#2,d4
	and.w	#$3C,d4
	sub.w	2(a2),d4
	muls.w	d4,d4
	add.l	d4,d1
	move.w	d0,d4
	lsl.w	#2,d4
	and.w	#$3C,d4
	sub.w	4(a2),d4
	muls.w	d4,d4
	add.l	d4,d1
	rts

; Einen Satz fuellen.  a0 = Satz, a2 = Palette (32 Worte).
; Veraendert d0-d7/a2-a4.
stb_satz:
	; ---- Tabelle ----
	clr.b	ST_TAB(a0)		; 0 bleibt 0
	lea	2(a2),a3
	moveq	#1,d7			; Farbe
sss_t:	move.w	(a3)+,d0
	and.w	#$0FFF,d0
	move.w	st_nc,d2		; (mindestens eine: die Rampe)
	lea	st_rampe,a4		; ein Wert der Rampe nur zu ihren Mitten
	move.w	st_nrp,d1
	subq.w	#1,d1
sss_t1:	cmp.w	(a4)+,d0
	dbeq	d1,sss_t1
	bne.b	sss_t2
	move.w	st_nf,d2
sss_t2:	bsr	stb_naechste
	addq.w	#1,d3
	move.b	d3,ST_TAB(a0,d7.w)
	addq.w	#1,d7
	cmp.w	#32,d7
	bcs.b	sss_t
	; ---- Stellvertreter ----
	clr.b	ST_REP(a0)
	moveq	#1,d6			; Register
sss_r:	moveq	#1,d7
sss_r1:	cmp.b	ST_TAB(a0,d7.w),d6
	beq.b	sss_r3
	addq.w	#1,d7
	cmp.w	#32,d7
	bcs.b	sss_r1
	; keine Farbe hat dieses Register: die naechste zur Mitte
	; (kommt im Bild nicht vor, solange alle Zeichner die Tabelle nehmen)
	moveq	#1,d7
sss_r3:	move.b	d7,ST_REP(a0,d6.w)
	addq.w	#1,d6
	cmp.w	#16,d6
	bcs.b	sss_r
	; weiter in stb_ebenen

; Die Ebenenbits (ST_TAB2) aus der Tabelle des Satzes a0.
; Veraendert d0/d1/d7/a4.
stb_ebenen:
	lea	ST_TAB2(a0),a4
	moveq	#0,d7
sss_e:	moveq	#0,d0
	move.b	ST_TAB(a0,d7.w),d0
	moveq	#0,d1
	btst	#3,d0
	beq.b	sss_e3
	bset	#24,d1
sss_e3:	btst	#2,d0
	beq.b	sss_e2
	bset	#16,d1
sss_e2:	btst	#1,d0
	beq.b	sss_e1
	bset	#8,d1
sss_e1:	btst	#0,d0
	beq.b	sss_e0
	bset	#0,d1
sss_e0:	move.l	d1,(a4)+
	addq.w	#1,d7
	cmp.w	#32,d7
	bcs.b	sss_e
	rts

; ***************************************************************************
; Platz_setzen -- die Palette eines Platzes der Rasterliste (geblendet) in
; die Register.  Der ST-Ersatz fuer die Fassung in FADE_SUP.S, derselbe
; Vertrag:
;   a0 = 32 Worte $0RGB, d0.w = Platz (0..PLAETZE-1).  Alle Register bleiben.
;
; Mitgeschrieben wird in Bank_ist wie beim Falcon; Set_fade blendet beim
; Abblenden von dort.  Die Register rechnet st_regs_bauen aus Bank_ist.
; ***************************************************************************
Platz_setzen:
	movem.l	d0-d1/a0-a1,-(sp)
	lea	Bank_ist,a1
	lsl.w	#6,d0
	add.w	d0,a1
	moveq	#32-1,d1
pls_m:	move.w	(a0)+,(a1)+
	dbf	d1,pls_m
	move.l	#-1,szp_rl		; den ganzen Weg: Set_fade kann eine neue
	move.l	#-1,szp_msp
	bsr	St_zeilen_pruefen	; Liste mit neuem Inhalt bringen
	bsr	st_regs_bauen
	movem.l	(sp)+,d0-d1/a0-a1
	rts

; ***************************************************************************
; Bank0_setzen -- 32 Farben nach Bank 0, beim Falcon der zweite Platz
; (Platzbank).  Fuer das Startmenue, das vor jedem Modul zeichnet.
;   a0 = 32 Worte $0RGB.  Alle Register bleiben.
; ***************************************************************************
Bank0_setzen:
	move.w	d0,-(sp)
	moveq	#1,d0
	bsr.b	Platz_setzen
	move.w	(sp)+,d0
	rts

; ***************************************************************************
; st_regs_bauen -- die 16 Register je Bereich und die Liste fuer Timer B.
; Alle Register bleiben.
;
; Je Platz: das Mittel der Farben jeder Gruppe, aus Bank_ist, also so, wie
; Set_fade sie gerade geblendet hat; die Gruppen sagt der Satz des Platzes
; (St_stand).  So bleibt die Tabelle waehrend einer Blende stehen, und was
; gezeichnet ist, stimmt.  Register 0 = Farbe 0 des Platzes.
;
; **Timer B nur, wo sich etwas aendert:** eine Grenze, hinter der dieselben
; 16 Werte stehen (Inventar: zweimal Main_pal), faellt weg.  Die Liste
; entsteht im freien der beiden Puffer und gilt ab dem Umsetzen von
; str_aktiv (ein Langwort): die VBL liest nie eine halbe.
;
; Gezaehlt wird bis eine Zeile vor der Grenze; den Rest wartet
; St_raster_int ab (dort steht, warum).  Am Falcon an VGA zaehlt Timer B
; vermutlich jede Zeile doppelt (St_zfaktor, ST.S) -- angenommen, nicht
; gemessen.
; ***************************************************************************
st_regs_bauen:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	str_puffer,a5
	cmpa.l	str_aktiv,a5
	bne.b	srb_frei
	lea	str_puffer+STR_GR,a5
srb_frei:
	move.l	a5,a3			; a3 = Schreibstelle
	clr.w	(a3)+			; Zahl der Grenzen
	lea	st_pl,a2
	move.l	a3,a1
	bsr	srb_platz		; erster Bereich
	lea	32(a3),a3
	move.l	a1,a4			; a4 = Werte des Bereichs davor
	moveq	#0,d6			; Zeile der letzten Grenze
	move.w	st_pl_n,d4		; d4: srb_platz braucht d5
	subq.w	#1,d4
	bra.b	srb_weiter
srb_grenze:
	lea	PL_SZ(a2),a2
	lea	2(a3),a1
	bsr	srb_platz
	; dieselben Werte wie davor?  Dann keine Grenze, und der Satz wird
	; vom naechsten Platz ueberschrieben (a4 bleibt auf den alten Werten).
	move.l	a1,a0
	move.l	a4,a6
	moveq	#8-1,d0
srb_v:	cmpm.l	(a0)+,(a6)+
	dbne	d0,srb_v
	beq.b	srb_weiter
	move.l	a1,a4			; ab hier gelten die neuen Werte
	; Zaehler: von der Zeile hinter der letzten Grenze (anfangs Zeile 0)
	; bis zwei vor dieser, also Grenze - letzte - 1 Zeilen; die Zeile
	; davor wartet St_raster_int ab.
	move.w	PL_ZEILE(a2),d1
	move.w	d1,d0
	sub.w	d6,d0
	subq.w	#1,d0
	mulu.w	St_zfaktor,d0
	cmp.w	#1,d0
	bge.b	srb_z1
	moveq	#1,d0			; zu nah: eine Zeile spaeter
srb_z1:	cmp.w	#255,d0
	ble.b	srb_z2
	move.w	#255,d0			; mehr fasst Timer B nicht
srb_z2:	move.w	d0,(a3)
	lea	STR_SATZ(a3),a3
	move.w	d1,d6
	addq.w	#1,(a5)
srb_weiter:
	dbf	d4,srb_grenze
	move.w	St_zfaktor,d0
	move.b	d0,str_warte
	move.l	a5,str_aktiv		; ab jetzt gilt die neue Liste
	; Ohne VBL-Haken (Raster_install fand keinen Platz) wenigstens den
	; ersten Bereich fuer das ganze Bild
	tst.l	ras_vblslot
	bne.b	srb_out
	lea	2(a5),a0
	lea	ST_PALETTE.w,a1
	moveq	#8-1,d0
srb_h:	move.l	(a0)+,(a1)+
	dbf	d0,srb_h
srb_out:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; Die 16 Registerworte eines Platzes.  a2 = Platz (st_pl), a1 = Ziel.
; a1 und a2 bleiben, veraendert d0-d5/d7/a0.
srb_platz:
	movem.l	a1-a3,-(sp)
	lea	st_summe,a0		; je Register R, G, B, Anzahl
	moveq	#16*4-1,d0
srp_l:	clr.w	(a0)+
	dbf	d0,srp_l
	lea	Bank_ist,a3
	move.w	PL_BANK(a2),d0
	lsl.w	#6,d0
	add.w	d0,a3			; a3 = Farben des Platzes
	move.l	PL_EINTRAG(a2),a0
	movem.l	a4,-(sp)
	lea	SE_S+ST_TAB(a0),a4
	move.w	SE_RMASKE(a0),d3
	move.l	a3,a2
	bsr	b0st_summieren		; veraendert a1
	movem.l	(sp)+,a4
	movem.l	(sp),a1			; Ziel zurueck
	; Register 0: Farbe 0
	move.w	(a3),d0
	and.w	#$0FFF,d0
	bsr	st_ste_wort
	move.w	d0,(a1)+
	lea	st_summe+8,a2		; Register 1..15
	tst.w	SE_HAND(a0)
	bne.b	srp_hand
	moveq	#15-1,d7
srp_r:	move.w	6(a2),d2		; Anzahl
	bne.b	srp_r1
	moveq	#0,d0			; leer: schwarz
	addq.l	#8,a2
	bra.b	srp_r3
srp_r1:
	moveq	#0,d5
	moveq	#2,d3
srp_r2:
	moveq	#0,d0
	move.w	(a2)+,d0
	move.w	d2,d1
	lsr.w	#1,d1
	add.l	d1,d0
	divu.w	d2,d0
	lsl.w	#4,d5
	or.w	d0,d5
	dbf	d3,srp_r2
	addq.l	#2,a2
	move.w	d5,d0
srp_r3:
	bsr	st_ste_wort
	move.w	d0,(a1)+
	dbf	d7,srp_r
srp_fertig:
	movem.l	(sp)+,a1-a3
	rts

; The registers of an entry from STPAL.DAT (SE_HAND): each channel of the
; value in the file scaled with what Thalion's fade or light level made of
; the group, value * now / file, both as sums over the group's colours
; (now: Bank_ist, file: SE_HSUMME).  At full brightness that is the value
; itself, in black it is 0, so the precomputed and hand-set values fade like
; Thalion's colours.  A channel that is 0 in the file palette takes the mean
; as without the file; a register without colours keeps its value.
srp_hand:
	movem.l	d4/d6/a4,-(sp)		; st_regs_bauen counts in d4, keeps d6/a4
	lea	SE_HSUMME+8(a0),a3
	lea	SE_HWERT+2(a0),a4
	moveq	#15-1,d7
srh_r:	move.w	(a4)+,d4		; the value from the file
	move.w	6(a2),d6		; colours in the group
	bne.b	srh_g
	move.w	d4,d0			; none: the value as it is
	addq.l	#8,a2
	addq.l	#8,a3
	bra.b	srh_w
srh_g:	moveq	#0,d5			; $0RGB
	moveq	#8,d3			; the channel: shift 8, 4, 0
srh_k:	moveq	#0,d0
	move.w	(a2)+,d0		; sum now
	move.w	(a3)+,d1		; sum in the file palette
	beq.b	srh_mittel
	move.w	d4,d2
	lsr.w	d3,d2
	and.w	#15,d2
	mulu.w	d2,d0			; value * now
	moveq	#0,d2
	move.w	d1,d2
	lsr.w	#1,d2
	add.l	d2,d0			; rounded
	divu.w	d1,d0			; / file
	cmp.w	#15,d0
	bls.b	srh_kanal
	moveq	#15,d0
	bra.b	srh_kanal
srh_mittel:
	moveq	#0,d2			; the mean, rounded
	move.w	d6,d2
	lsr.w	#1,d2
	add.l	d2,d0
	divu.w	d6,d0
srh_kanal:
	lsl.w	#4,d5
	or.w	d0,d5
	subq.w	#4,d3
	bpl.b	srh_k
	addq.l	#2,a2			; past the count
	addq.l	#2,a3
	move.w	d5,d0
srh_w:	bsr	st_ste_wort
	move.w	d0,(a1)+
	dbf	d7,srh_r
	movem.l	(sp)+,d4/d6/a4
	bra.b	srp_fertig

; Farben 1..31 aus (a2) nach Tabelle (a4) in st_summe aufaddieren.  d3.w =
; SE_RMASKE: in ein Register mit gesetztem Bit rechnen nur die Farben der
; Rampe (St_bauen, Rampenschutz).
b0st_summieren:
	moveq	#1,d7
b0su_f:	move.w	d7,d0
	add.w	d0,d0
	move.w	0(a2,d0.w),d0		; $0RGB
	moveq	#0,d1
	move.b	0(a4,d7.w),d1		; Register
	btst	d1,d3
	beq.b	b0su_ja
	cmp.w	#ST_RAMPE_ERSTE,d7
	bcs.b	b0su_n			; Kartenfarbe im Rampenregister: zaehlt nicht
b0su_ja:
	lsl.w	#3,d1
	lea	st_summe,a1
	add.w	d1,a1
	move.w	d0,d1
	lsr.w	#8,d1
	and.w	#15,d1
	add.w	d1,(a1)+
	move.w	d0,d1
	lsr.w	#4,d1
	and.w	#15,d1
	add.w	d1,(a1)+
	move.w	d0,d1
	and.w	#15,d1
	add.w	d1,(a1)+
	addq.w	#1,(a1)
b0su_n:	addq.w	#1,d7
	cmp.w	#32,d7
	bcs.b	b0su_f
	rts

; $0RGB (je vier Bit) in d0 -> Farbwort des STE: je Kanal das unterste Bit
; oben (Bit 3), die oberen drei darunter.  Der ST liest nur die drei.
; Veraendert d1.
st_ste_wort:
	move.w	d0,d1
	and.w	#$0EEE,d1		; obere drei Bits je Kanal ...
	lsr.w	#1,d1			; ... eine Stelle tiefer
	and.w	#$0111,d0		; unterstes Bit je Kanal ...
	lsl.w	#3,d0			; ... nach Bit 3
	or.w	d1,d0
	rts

; ***************************************************************************
; Palette_anfang -- Grundstellung beim Oeffnen des Schirms, wie beim Falcon:
; erster Platz Main_pal, die anderen schwarz, keine Liste gesetzt.  Ohne
; Rasterliste gilt der zweite Platz, die Register sind also schwarz.
; Alle Register bleiben.
; ***************************************************************************
Palette_anfang:
	movem.l	d0/a0,-(sp)
	clr.l	Letzte_RL
	lea	Main_pal,a0
	moveq	#0,d0
	bsr	Platz_setzen
	lea	Schwarz,a0
	moveq	#2,d0
	bsr	Platz_setzen
	moveq	#1,d0
	bsr	Platz_setzen
	movem.l	(sp)+,d0/a0
	rts

; ***************************************************************************
; St_raster_vbl -- je Bild: die Register des ersten Bereichs setzen und
; Timer B auf die erste Grenze stellen.  Raster_vbl (RASTER.S) ruft es aus
; der VBL-Warteschlange.  Alle Register bleiben.
;
; **Ein Interrupt je Grenze, nicht je Zeile** (Nutzer, 2026-10-02).  Timer
; B zaehlt im Ereigniszaehlmodus die Bildzeilen von TBDR herunter und loest
; bei null aus; den Zaehler fuer die naechste Grenze setzt St_raster_int.
; Auf der Karte ist das eine Grenze je Bild, im Kampf zwei, im Inventar
; keine.
; ***************************************************************************
St_raster_vbl:
	movem.l	d0/a0-a1,-(sp)
	clr.b	MFP+MFP_TBCR		; anhalten, was vom letzten Bild laeuft
	move.l	str_aktiv,d0
	beq.b	srv_out			; noch keine Liste
	move.l	d0,a0
	move.w	(a0)+,d0		; Grenzen
	lea	ST_PALETTE.w,a1
	REPT	8
	move.l	(a0)+,(a1)+		; erster Bereich
	ENDR
	tst.w	d0
	beq.b	srv_keine
	move.w	d0,str_rest
	move.l	a0,str_zeiger
	move.b	1(a0),MFP+MFP_TBDR	; angehalten: laedt auch den Zaehler
	move.b	#$FE,MFP+MFP_IPRA
	bset	#0,MFP+MFP_IERA
	bset	#0,MFP+MFP_IMRA
	move.b	#8,MFP+MFP_TBCR		; Ereigniszaehlmodus: Bildzeilen
	bra.b	srv_out
srv_keine:
	bclr	#0,MFP+MFP_IERA
srv_out:
	movem.l	(sp)+,d0/a0-a1
	rts

; ***************************************************************************
; St_raster_int -- Timer B: die 16 Register des naechsten Bereichs.
;
; **Erst laden, dann auf den Rand warten.**  16 Register zu schreiben
; dauert mit allem Drumherum rund 300 Takte, der Rand zwischen zwei Zeilen
; ist rund 190 Takte lang.  Darum loest Timer B eine Zeile zu frueh aus:
; der Interrupt laedt die Werte in Register, stellt den Zaehler auf eine
; Zeile und wartet, bis die Zeile vor der Grenze zu Ende ist (Bit 0 in
; IPRA).  Dann geht alles mit einem movem hinaus, rund 80 Takte.  Das
; Warten kostet eine Zeile je Grenze, gut 500 Takte.
;
; Wartet die Schleife zu lange (keine Bildzeile mehr), gibt sie nach rund
; 15 Zeilen auf und setzt trotzdem.
; ***************************************************************************
St_raster_int:
	movem.l	d0-d7/a0-a2,-(sp)
	move.l	str_zeiger,a0
	addq.l	#2,a0			; hinter den Zaehler
	movem.l	(a0)+,d1-d7/a2		; die 16 Werte
	clr.b	MFP+MFP_TBCR
	move.b	str_warte,MFP+MFP_TBDR	; eine Zeile (VGA am Falcon: zwei)
	move.b	#$FE,MFP+MFP_IPRA
	move.b	#8,MFP+MFP_TBCR
	move.w	#300,d0
sri_warte:
	btst	#0,MFP+MFP_IPRA
	dbne	d0,sri_warte
	lea	ST_PALETTE.w,a1
	movem.l	d1-d7/a2,(a1)		; im Rand vor der ersten Zeile
	clr.b	MFP+MFP_TBCR
	move.b	#$FE,MFP+MFP_IPRA
	subq.w	#1,str_rest
	beq.b	sri_ende		; letzte Grenze: Timer bleibt aus
	move.l	a0,str_zeiger
	move.b	1(a0),MFP+MFP_TBDR
	move.b	#8,MFP+MFP_TBCR
sri_ende:
	move.b	#$FE,MFP+MFP_ISRA	; Timer B quittieren
	movem.l	(sp)+,d0-d7/a0-a2
	rte

; ***************************************************************************
; E12, Weg B: Abschriften der 3D-Bloecke in Registernummern (docs/12,
; Erkenntnis 242).
;
; Der 3D-Puffer (MOVEP_ptr) traegt Farbnummern 0..15, und St_movep_schirm
; setzt jedes Bild alle 144x144 Punkte ueber ST_TAB in Register um (1,27 Mio.
; Takte).  Alles, was Thalion in den Puffer malt, kopiert er unveraendert aus
; drei Sorten Bloecken: Waende (Wall_handles, mit den Overlays darin),
; Objekte (Object_handles) und der vorgeschobene Horizont
; (Horizon_preshift_handle); dazu die Fuellfarben Sky_colour und
; Floor_colour.  Alle haben das Format des Puffers: je acht Punkte vier
; Byte, Ebene 0..3.  Durchsichtig ist "alle vier Bits null", und Register 0
; gehoert der Farbe 0 allein.
;
; **Thalions Bloecke bleiben unveraendert.**  Hier entsteht eine Abschrift in
; Registernummern, in einem eigenen Speicherblock ausserhalb der
; Handle-Tabelle (die hat nur 199 Plaetze).  Waehrend eines 3D-Bilds gibt
; Claim_pointer fuer diese Handles die Abschrift heraus; dann steht im Puffer
; schon das Register, und Show_MOVEP_screen kopiert nur noch (St_abschrift_
; zeigen).  Sky_colour und Floor_colour stehen fuer die Dauer des Bilds in
; Registern und danach wieder wie zuvor.
;
; Ablauf:
;   - The frame starts with Claim_pointer on MOVEP_handle, if the block has
;     the size of the MOVEP buffer: Thalion claims it in Update_3D_display
;     before anything else and only there.  The size check matters: until
;     the next 3D map allocates its buffer, MOVEP_handle names a freed
;     handle whose number may already belong to another block (finding 243).
;     St_abschrift_bild checks, allocates the copies and sets sab_aktiv.
;   - Ende ist Show_MOVEP_screen (D3_SUP.S): St_abschrift_zeigen.
;   - Colouring is lazy: a copy is coloured when Thalion first claims its
;     handle in a frame with the current set (sab_ok, sab_eins_faerben), so
;     a map change colours only what the first picture shows, the rest when
;     it comes into view.  If the set of the 3D rows changes (another entry
;     or ST_GEN), all copies count as uncoloured again; a light level does
;     not change it (st_blende).
;   - If Thalion frees a handle that has a copy (Free_memory) or invalidates
;     it (Invalidate_memory: overlays are painted), all copies go
;     (St_abschrift_weg), but the block is parked, not given back: up to
;     SAB_PARKS maps keep their coloured copies, keyed by length, two
;     checksums of Thalion's block and the set (sab_parken).  Coloring
;     first looks there (sab_aus_park), so town -> house -> town colours the
;     town once.  Parks go when less than SAB_RESERVE stays free, when the
;     copies of a new map find no memory, and in Kill_unclaimed_memory.
; Der alte Weg (St_movep_schirm) bleibt, wenn kein Speicher da ist, die
; 144 Zeilen nicht einen Satz haben oder Draw_floor/Draw_ceiling malen
; (Floor_ceiling_status: nur mit CPU_68020_plus, der ST-Bau auf einem Falcon).
; ***************************************************************************

; ***************************************************************************
; St_abschrift_zeiger -- der Haken in Claim_pointer (MEMORY.S).
;   IN : d0.b = Handle, a0 = sein Eintrag in memtab (gueltig)
;   OUT: d0 = Adresse: im 3D-Bild die Abschrift, wenn es eine gibt, sonst
;        MEM_ADR(a0).  Alle uebrigen Register bleiben.
; ***************************************************************************
SAB_MOVEP_LEN	equ	(144*144)/2+100	; Thalion's MOVEP buffer (3D_MAP.S)
SAB_PARKS	equ	2		; maps whose coloured copies are kept
SAB_PE		equ	128		; copies per park
SAB_RESERVE	equ	512*1024	; free memory a park must leave
PK_BLOCK	equ	0		; .l the block at TOS, 0: park empty
PK_ALTER	equ	4		; .l when parked (sab_uhr)
PK_N		equ	8		; .w entries
PK_KEY		equ	10		; 16 bytes: ST_TAB 0..15 of the set
PK_E		equ	26		; the entries
PE_ADR		equ	0		; .l the copy in PK_BLOCK
PE_LEN		equ	4		; .l MEM_LEN of Thalion's block
PE_SUM		equ	8		; .l its checksums (sab_kennung)
PE_HASH		equ	12
PE_SZ		equ	16
PK_SZ		equ	PK_E+SAB_PE*PE_SZ

St_abschrift_zeiger:
	movem.l	d1/a1,-(sp)
	moveq	#0,d1
	move.b	d0,d1
	cmp.b	MOVEP_handle,d1
	bne.b	saz_kopie
	; Between Remove_3D_map_data and the next allocation MOVEP_handle still
	; names the freed handle, and Allocate_memory hands the number out
	; again: only Thalion's MOVEP buffer itself starts a frame (finding 243).
	cmp.l	#SAB_MOVEP_LEN,MEM_LEN(a0)
	bne.b	saz_kopie
	bsr	St_abschrift_bild	; Beginn eines 3D-Bilds
	bra.b	saz_original
saz_kopie:
	tst.b	sab_aktiv
	beq.b	saz_original
	lea	sab_ok,a1
	tst.b	0(a1,d1.w)
	bne.b	saz_da
	bsr	sab_eins_faerben	; first use with this set (Z: no copy)
	beq.b	saz_original
saz_da:	add.w	d1,d1
	add.w	d1,d1
	lea	sab_tab,a1
	move.l	0(a1,d1.w),d0
	bne.b	saz_aus
saz_original:
	move.l	MEM_ADR(a0),d0
saz_aus:
	movem.l	(sp)+,d1/a1
	rts

; ***************************************************************************
; St_abschrift_weg -- the hook in Free_memory and Invalidate_memory.
;   IN : d0.b = handle.  If it has a copy, all copies go and their block is
;   parked (St_abschrift_parken).
; St_abschrift_alle_weg -- all copies and all parks go back to TOS
;   (Kill_unclaimed_memory, Thalion's way out of a full memory).
;   All registers are preserved.
; ***************************************************************************
St_abschrift_weg:
	movem.l	d0/a0,-(sp)
	and.w	#$FF,d0
	add.w	d0,d0
	add.w	d0,d0
	lea	sab_tab,a0
	tst.l	0(a0,d0.w)
	movem.l	(sp)+,d0/a0		; movem laesst die Bedingungen stehen
	bne.b	St_abschrift_parken
	rts

St_abschrift_parken:
	movem.l	d0-d7/a0-a6,-(sp)
	st	d7
	bsr	sab_weg
	movem.l	(sp)+,d0-d7/a0-a6
	rts

St_abschrift_alle_weg:
	movem.l	d0-d7/a0-a6,-(sp)
	sf	d7
	bsr	sab_weg
	bsr	sab_parks_weg
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; sab_weg -- all copies go; their block is parked (d7.b set) or given back.
; Changes d0-d6/a0-a4.
sab_weg:
	bsr	sab_ende		; ein laufendes Bild faellt auf den alten Weg
	move.l	sab_block,d0
	beq.b	sw_leer
	clr.l	sab_block
	tst.b	d7
	beq.b	sw_frei
	bsr	sab_parken		; reads sab_tab, sab_ok, sab_satz
	bra.b	sw_leer
sw_frei:
	move.l	d0,-(sp)
	move.w	#Mfree,-(sp)
	Gemdos
	addq.l	#6,sp
sw_leer:
	lea	sab_tab,a0
	move.w	#256-1,d0
sw_l:	clr.l	(a0)+
	dbf	d0,sw_l
	bsr	sab_ok_leeren
	clr.l	sab_satz
	rts

; ***************************************************************************
; St_abschrift_bild -- Beginn eines 3D-Bilds.  Alle Register bleiben.
; ***************************************************************************
St_abschrift_bild:
	movem.l	d0-d7/a0-a6,-(sp)
	bsr	sab_ende		; ein Bild ohne Show (sollte nicht sein)
	tst.b	Floor_ceiling_status	; Draw_floor/Draw_ceiling malen Nummern
	bne	sbb_aus
	; ---- ein Satz fuer alle 144 Zeilen ----
	bsr	St_zeilen_pruefen
	move.w	#Map3D_Y,d0
	bsr	St_zeilensatz_schnell
	move.l	a0,a2			; a2 = Satz
	move.w	#144-2,d7
sbb_z:	addq.w	#1,d0
	bsr	St_zeilensatz_schnell
	cmpa.l	a0,a2
	bne	sbb_aus
	dbf	d7,sbb_z
	; ---- hat jedes Handle des Bilds eine Abschrift? ----
	bsr	sab_handles_pruefen	; Z: alle da
	beq.b	sbb_da
	bsr	St_abschrift_parken	; a new handle: the old copies are parked
	bsr	sab_anlegen		; Z: angelegt
	bne	sbb_aus			; kein Speicher: alter Weg
sbb_da:
	; ---- gefaerbt mit diesem Satz? ----
	cmpa.l	sab_satz,a2
	bne.b	sbb_faerben
	move.w	ST_GEN(a2),d0
	cmp.w	sab_gen,d0
	beq.b	sbb_gefaerbt
sbb_faerben:
	bsr	sab_ok_leeren		; colour each copy on its first use
	move.l	ST_TAB(a2),sab_schluessel	; the key of the parks
	move.l	ST_TAB+4(a2),sab_schluessel+4
	move.l	ST_TAB+8(a2),sab_schluessel+8
	move.l	ST_TAB+12(a2),sab_schluessel+12
	move.l	a2,sab_satz
	move.w	ST_GEN(a2),sab_gen
sbb_gefaerbt:
	; ---- Fuellfarben fuer dieses Bild in Registern ----
	bsr	sab_tabellen
	move.l	Sky_colour,d0
	move.l	d0,sab_himmel
	bsr	sab_ein_langwort
	move.l	d0,Sky_colour
	move.l	Floor_colour,d0
	move.l	d0,sab_boden
	bsr	sab_ein_langwort
	move.l	d0,Floor_colour
	st	sab_aktiv
sbb_aus:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; sab_ende -- ein laufendes Bild beenden: Fuellfarben zurueck, sab_aktiv aus.
; Alle Register bleiben.
sab_ende:
	tst.b	sab_aktiv
	beq.b	sae_aus
	sf	sab_aktiv
	move.l	sab_himmel,Sky_colour
	move.l	sab_boden,Floor_colour
sae_aus:
	rts

; sab_handles_pruefen -- jedes Handle des Bilds (Waende, Objekte, Horizont)
; mit Abschrift?  OUT: Z gesetzt, wenn ja.  Veraendert d0-d2/a0-a1.
; sab_handles -- dieselbe Liste: fuer jedes Handle (d0.w, nicht null)
; einmal a1 rufen (auch doppelte).  Veraendert d0-d2/a0, und was a1 tut.
sab_handles_pruefen:
	lea	sabp_eins,a1
	sf	sab_fehlt
	bsr.b	sab_handles
	tst.b	sab_fehlt
	rts
sabp_eins:
	movem.l	d0/a0,-(sp)
	add.w	d0,d0
	add.w	d0,d0
	lea	sab_tab,a0
	tst.l	0(a0,d0.w)
	bne.b	sabp_da
	st	sab_fehlt
sabp_da:
	movem.l	(sp)+,d0/a0
	rts

sab_handles:
	lea	Wall_handles,a0
	move.w	Nr_of_walls,d1
	bsr.b	sabh_reihe
	lea	Object_handles,a0
	move.w	Nr_of_objects,d1
	bsr.b	sabh_reihe
	tst.b	Horizon_flag
	beq.b	sabh_aus
	lea	Horizon_preshift_handle,a0
	moveq	#1,d1
	bsr.b	sabh_reihe
sabh_aus:
	rts
sabh_reihe:
	bra.b	sabh_e
sabh_l:	moveq	#0,d0
	move.b	(a0)+,d0
	beq.b	sabh_e
	movem.l	d1/a0,-(sp)
	jsr	(a1)
	movem.l	(sp)+,d1/a0
sabh_e:	dbf	d1,sabh_l
	rts

; sab_anlegen -- einen Block fuer alle Abschriften holen und verteilen.
; Vorher ist sab_tab leer.  OUT: Z gesetzt, wenn angelegt; sonst bleibt
; sab_tab leer.  Veraendert d0-d7/a0-a1.
sab_anlegen:
	clr.l	sab_summe
	lea	saba_zaehlen,a1		; 1. Laengen zaehlen, jedes Handle einmal
	bsr.b	sab_handles
	move.l	sab_summe,d0
	beq.b	saba_nichts
	bsr	sab_malloc		; gives up parks if it must
	tst.l	d0
	beq.b	saba_nichts
	move.l	d0,sab_block
	move.l	d0,sab_frei
	lea	sab_tab,a0		; 2. Adressen verteilen (-1 = gezaehlt)
	moveq	#0,d0			; Handle
saba_v:	cmp.l	#-1,(a0)
	bne.b	saba_vw
	movem.l	d0/a0,-(sp)
	jsr	Mem_eintrag		; a0 = Eintrag
	move.l	MEM_LEN(a0),d1
	movem.l	(sp)+,d0/a0
	addq.l	#3,d1
	and.w	#-4,d1
	move.l	sab_frei,(a0)
	add.l	d1,sab_frei
saba_vw:
	addq.l	#4,a0
	addq.w	#1,d0
	cmp.w	#256,d0
	bcs.b	saba_v
	clr.l	sab_satz		; noch nicht gefaerbt
	bsr	sab_ok_leeren
	moveq	#0,d0			; Z
	rts
saba_nichts:
	lea	sab_tab,a0		; die Zaehlmarken wieder weg
	move.w	#256-1,d0
saba_l:	clr.l	(a0)+
	dbf	d0,saba_l
	moveq	#1,d0			; Z frei
	rts

saba_zaehlen:
	movem.l	d0-d1/a0-a1,-(sp)
	move.w	d0,d1
	add.w	d1,d1
	add.w	d1,d1
	lea	sab_tab,a1
	tst.l	0(a1,d1.w)
	bne.b	sabz_aus		; schon gezaehlt
	jsr	Mem_eintrag
	beq.b	sabz_aus		; Handle ohne Block
	move.l	#-1,0(a1,d1.w)
	move.l	MEM_LEN(a0),d0
	addq.l	#3,d0
	and.w	#-4,d0
	add.l	d0,sab_summe
sabz_aus:
	movem.l	(sp)+,d0-d1/a0-a1
	rts

; sab_tabellen -- st_mv_s und st_mv_t fuer den Satz a2 bereitstellen.
; Alle Register bleiben.
sab_tabellen:
	movem.l	d0/a0,-(sp)
	tst.b	st_mv_s_fertig
	bne.b	sabt_s
	bsr	st_mv_s_bauen
sabt_s:	move.l	a2,a0
	cmpa.l	st_mv_satz,a0
	bne.b	sabt_neu
	move.w	ST_GEN(a0),d0
	cmp.w	st_mv_gen,d0
	beq.b	sabt_aus
sabt_neu:
	bsr	st_mv_bauen
sabt_aus:
	movem.l	(sp)+,d0/a0
	rts

; sab_ein_langwort -- acht Punkte d0 (movep-Lage) in Register.  Nach
; sab_tabellen.  Alle uebrigen Register bleiben.
sab_ein_langwort:
	movem.l	d5-d7/a0/a2-a6,-(sp)
	move.l	d0,sab_puffer
	lea	sab_puffer,a0
	bsr	sab_zeiger_tabellen
	SMV_HAELFTE
	move.l	d7,d0
	movem.l	(sp)+,d5-d7/a0/a2-a6
	rts

; a2 = st_mv_s, a3..a6 = st_mv_t Byte 0..3, wie in St_movep_schirm.
sab_zeiger_tabellen:
	lea	st_mv_s,a2
	lea	st_mv_t,a3
	lea	256*4(a3),a4
	lea	256*4(a4),a5
	lea	256*4(a5),a6
	rts

; sab_eins_faerben -- colour the copy of one handle for the current set,
; from a park if one has it.  IN: d1.w = handle, a0 = its memtab entry.
; OUT: Z set if the handle has no copy.  All registers are preserved.
sab_eins_faerben:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	d1,d0
	add.w	d0,d0
	add.w	d0,d0
	lea	sab_tab,a1
	move.l	0(a1,d0.w),d0
	beq.b	sef_aus			; no copy: Z
	lea	sab_ok,a1
	st	0(a1,d1.w)
	move.l	d0,a1			; Ziel
	bsr	sab_aus_park		; Z: found and copied
	beq.b	sef_fertig
	move.l	sab_satz,a2
	bsr	sab_tabellen		; st_mv_s, st_mv_t fuer a2
	move.l	MEM_LEN(a0),d4
	addq.l	#3,d4
	lsr.l	#2,d4			; Langworte
	move.l	MEM_ADR(a0),a0		; Quelle
	bsr	sab_block_faerben
sef_fertig:
	moveq	#1,d0			; Z frei
sef_aus:
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; sab_block_faerben -- d4.l longwords from a0 (Thalion's block) to a1 (the
; copy) in register numbers.  After sab_tabellen.  Changes d4-d7/a0-a1.
sab_block_faerben:
	movem.l	a2-a6,-(sp)
	bsr	sab_zeiger_tabellen
	bra.b	sbf_e
sbf_l:	SMV_HAELFTE
	move.l	d7,(a1)+
sbf_e:	subq.l	#1,d4
	bpl	sbf_l
	movem.l	(sp)+,a2-a6
	rts

; sab_kennung -- two checksums over d4.l longwords from a0 (below 65536,
; the largest block is the horizon with 11520): d1 the sum, d2 rotated and
; xor-ed, so the order counts too.  Changes d0-d2/d4/a0.
sab_kennung:
	moveq	#0,d1
	moveq	#0,d2
	subq.l	#1,d4
	bmi.b	skn_aus
skn_l:	move.l	(a0)+,d0
	add.l	d0,d1
	rol.l	#1,d2
	eor.l	d0,d2
	dbf	d4,skn_l
skn_aus:
	rts

; sab_aus_park -- a parked copy of this block with this set?  Then copy it.
; IN: a0 = memtab entry, a1 = the copy.  The checksums of Thalion's block
; are only computed when a park with the same set has an entry of the same
; length.  OUT: Z set if copied.  All registers are preserved.
sab_aus_park:
	movem.l	d0-d7/a0-a4,-(sp)
	move.l	a0,a3			; Eintrag
	move.l	MEM_LEN(a3),d3
	sf	d7			; checksums not computed yet
	lea	sab_parks,a2
	moveq	#SAB_PARKS-1,d6
sap_p:	tst.l	PK_BLOCK(a2)
	beq.b	sap_pw
	lea	PK_KEY(a2),a0		; the same set?
	lea	sab_schluessel,a4
	moveq	#4-1,d0
sap_k:	cmpm.l	(a0)+,(a4)+
	dbne	d0,sap_k
	bne.b	sap_pw
	lea	PK_E(a2),a4
	move.w	PK_N(a2),d5
	bra.b	sap_ee
sap_el:	cmp.l	PE_LEN(a4),d3
	bne.b	sap_ew
	tst.b	d7
	bne.b	sap_hat
	st	d7
	move.l	MEM_ADR(a3),a0
	move.l	d3,d4
	lsr.l	#2,d4
	bsr	sab_kennung
sap_hat:
	cmp.l	PE_SUM(a4),d1
	bne.b	sap_ew
	cmp.l	PE_HASH(a4),d2
	bne.b	sap_ew
	move.l	PE_ADR(a4),a0		; found: copy it
	move.l	d3,d4
	addq.l	#3,d4
	lsr.l	#2,d4
	bra.b	sap_ce
sap_cl:	move.l	(a0)+,(a1)+
sap_ce:	subq.l	#1,d4
	bpl.b	sap_cl
	moveq	#0,d0			; Z
	bra.b	sap_aus
sap_ew:	lea	PE_SZ(a4),a4
sap_ee:	dbf	d5,sap_el
sap_pw:	lea	PK_SZ(a2),a2
	dbf	d6,sap_p
	moveq	#1,d0			; Z frei: none
sap_aus:
	movem.l	(sp)+,d0-d7/a0-a4
	rts

; sab_parken -- keep the block d0.l (the copies) as a park, or give it back
; if no copy is coloured.  An empty park slot is taken, else the oldest is
; given back.  Afterwards SAB_RESERVE must stay free (sab_reserve).
; Changes d0-d6/a0-a4.
sab_parken:
	move.l	d0,d5			; der Block
	tst.l	sab_satz
	beq	spk_frei		; never coloured
	lea	sab_parks,a2		; an empty slot?
	moveq	#SAB_PARKS-1,d6
spk_s:	tst.l	PK_BLOCK(a2)
	beq.b	spk_leer
	lea	PK_SZ(a2),a2
	dbf	d6,spk_s
	bsr	sab_aeltester		; no: the oldest goes
	bsr	sab_park_frei
spk_leer:
	clr.w	PK_N(a2)
	lea	PK_E(a2),a4
	lea	sab_tab,a0
	lea	sab_ok,a1
	moveq	#0,d4			; Handle
spk_h:	move.l	(a0)+,d1		; the copy
	beq.b	spk_hw
	tst.b	0(a1,d4.w)		; coloured with the current set?
	beq.b	spk_hw
	cmp.w	#SAB_PE,PK_N(a2)
	bcc.b	spk_hw
	movem.l	d1/d4/a0,-(sp)
	move.w	d4,d0
	jsr	Mem_eintrag
	beq.b	spk_ohne
	move.l	d1,PE_ADR(a4)
	move.l	MEM_LEN(a0),d0
	move.l	d0,PE_LEN(a4)
	move.l	d0,d4
	lsr.l	#2,d4
	move.l	MEM_ADR(a0),a0
	bsr	sab_kennung
	move.l	d1,PE_SUM(a4)
	move.l	d2,PE_HASH(a4)
	lea	PE_SZ(a4),a4
	addq.w	#1,PK_N(a2)
spk_ohne:
	movem.l	(sp)+,d1/d4/a0
spk_hw:	addq.w	#1,d4
	cmp.w	#256,d4
	bcs.b	spk_h
	tst.w	PK_N(a2)
	beq.b	spk_frei
	move.l	d5,PK_BLOCK(a2)
	addq.l	#1,sab_uhr
	move.l	sab_uhr,PK_ALTER(a2)
	lea	sab_schluessel,a0
	lea	PK_KEY(a2),a1
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	bra.b	sab_reserve
spk_frei:
	move.l	d5,-(sp)
	move.w	#Mfree,-(sp)
	Gemdos
	addq.l	#6,sp
	rts

; sab_reserve -- give parks back, oldest first, until the largest free block
; has SAB_RESERVE.  Changes d0-d1/a0/a2.
sab_reserve:
	move.l	#-1,-(sp)
	move.w	#Malloc,-(sp)
	Gemdos
	addq.l	#6,sp
	cmp.l	#SAB_RESERVE,d0
	bcc.b	srv_aus
	bsr.b	sab_aeltester
	beq.b	srv_aus
	bsr.b	sab_park_frei
	bra.b	sab_reserve
srv_aus:
	rts

; sab_malloc -- Malloc(d0.l) for the copies; without memory the parks go,
; oldest first, and it tries again.  OUT: d0 = block or 0.  Changes d1/a0.
sab_malloc:
	move.l	a2,-(sp)
	move.l	d0,-(sp)
sml_l:	move.l	(sp),-(sp)
	move.w	#Malloc,-(sp)
	Gemdos
	addq.l	#6,sp
	tst.l	d0
	bne.b	sml_aus
	bsr.b	sab_aeltester
	beq.b	sml_aus			; no park left: d0 = 0
	bsr.b	sab_park_frei
	bra.b	sml_l
sml_aus:
	addq.l	#4,sp
	move.l	(sp)+,a2
	rts

; sab_aeltester -- OUT: a2 = the oldest park in use, d0 = a2; Z set if none.
; Changes d0-d1/a0.
sab_aeltester:
	sub.l	a2,a2
	lea	sab_parks,a0
	moveq	#SAB_PARKS-1,d1
sae_l:	tst.l	PK_BLOCK(a0)
	beq.b	sae_w
	move.l	a2,d0
	beq.b	sae_neu
	move.l	PK_ALTER(a0),d0
	cmp.l	PK_ALTER(a2),d0
	bcc.b	sae_w
sae_neu:
	move.l	a0,a2
sae_w:	lea	PK_SZ(a0),a0
	dbf	d1,sae_l
	move.l	a2,d0
	rts

; sab_park_frei -- give the park a2 back to TOS.  Changes d0.
sab_park_frei:
	move.l	PK_BLOCK(a2),d0
	beq.b	spf_aus
	clr.l	PK_BLOCK(a2)
	move.l	d0,-(sp)
	move.w	#Mfree,-(sp)
	Gemdos
	addq.l	#6,sp
spf_aus:
	rts

; sab_parks_weg -- all parks back to TOS.  Changes d0/d6/a2.
sab_parks_weg:
	lea	sab_parks,a2
	moveq	#SAB_PARKS-1,d6
spw_l:	bsr.b	sab_park_frei
	lea	PK_SZ(a2),a2
	dbf	d6,spw_l
	rts

; sab_ok_leeren -- every copy counts as uncoloured.  All registers are
; preserved.
sab_ok_leeren:
	movem.l	d0/a0,-(sp)
	lea	sab_ok,a0
	moveq	#256/4-1,d0
sol_l:	clr.l	(a0)+
	dbf	d0,sol_l
	movem.l	(sp)+,d0/a0
	rts

; ***************************************************************************
; St_abschrift_zeigen -- Show_MOVEP_screen im 3D-Bild mit Abschriften: der
; Puffer traegt schon Register, also nur kopieren, wie beim Falcon.
;   IN : wie St_movep_schirm (a0 Puffer, a1 Schirm, d6 Gruppen - 1,
;        d7 Zeilen - 1).  Beendet das Bild (Fuellfarben zurueck).
;   Alle Register bleiben.
; ***************************************************************************
St_abschrift_zeigen:
	movem.l	d0-d7/a0-a2,-(sp)
sazg_z:	move.l	a1,a2
	move.w	d6,d4
sazg_g:	move.l	(a0)+,d0
	movep.l	d0,0(a2)		; die linken acht Punkte, Ebenen 0..3
	move.l	(a0)+,d0
	movep.l	d0,1(a2)		; die rechten acht Punkte
	addq.l	#8,a2
	dbf	d4,sazg_g
	lea	SCRROW(a1),a1
	dbf	d7,sazg_z
	bsr	sab_ende
	movem.l	(sp)+,d0-d7/a0-a2
	rts

; St_abschrift_aktiv: fuer Show_MOVEP_screen.  Z frei, wenn ein 3D-Bild mit
; Abschriften laeuft.  Alle Register bleiben.
St_abschrift_aktiv:
	tst.b	sab_aktiv
	rts

	SECTION	Fast_BSS,bss
	even
st_cache:	ds.b	SE_SIZE*ST_EINTRAEGE
st_mv_s:	ds.l	4*256		; St_movep_schirm: je Ebene p Bit k -> Bit 4k+p
st_mv_t:	ds.l	4*256		; je Byte der Nibbles die Schirmebenen
st_mv_p:	ds.l	16		; je Farbe 0..15 die Ebenenbits, movep-Lage
st_mv_satz:	ds.l	1		; fuer diesen Satz gilt st_mv_t
st_mv_gen:	ds.w	1		; und dessen Bau
st_mv_s_fertig:	ds.b	1
	even
st_anzahl:	ds.w	1		; belegte Eintraege
st_naechster:	ds.w	1		; der naechste zu ersetzende
st_pkt:		ds.w	64		; Farben $0RGB, ohne doppelte
st_np:		ds.w	1
st_rampe:	ds.w	32-ST_RAMPE_ERSTE	; die Werte der Rampe, ohne doppelte
st_nrp:		ds.w	1
st_nf:		ds.w	1		; Mitten der Rampe, stehen fest (vorn in st_mit)
st_mit:		ds.w	3*16		; Mitten in Viertelstufen
st_nc:		ds.w	1
st_summe:	ds.w	4*16		; je Gruppe R, G, B, Anzahl
st_gen:		ds.w	1		; zaehlt jedes St_bauen
stp_anzahl:	ds.w	1		; entries in STPAL.DAT (0: none loaded)
stp_puffer:	ds.b	STP_KOPF+STP_GROESSE*STP_MAX	; STPAL.DAT, about 20 KB
st_rl_jetzt:	ds.l	1		; St_zeilen_pruefen: geltende Rasterliste
szp_rl:		ds.l	1		; kurzer Stempel (-1: ungueltig)
szp_letzte:	ds.l	1
szp_vbl:	ds.w	1
szp_msp:	ds.l	1		; Vorstempel (P5); -1: ungueltig
szp_ws:		ds.l	1
szp_off:	ds.l	1
st_hilfs_flag:	ds.b	1		; gesetzt: Zeichnen in einen Hilfsschirm
	even
; St_stand: die Plaetze; st_pl_n bis Ende st_pl ist der Stempel
st_pl_n:	ds.w	1		; Plaetze
st_pl_hilfs:	ds.w	1		; Platz fuer den Hilfsschirm
st_pl_flag:	ds.w	1		; st_hilfs_flag, als Teil des Stempels
		ds.w	1
st_pl:		ds.b	PLAETZE*PL_SZ
ST_PL_BLOCK = 8+PLAETZE*PL_SZ
st_pl_alt:	ds.b	ST_PL_BLOCK	; was zuletzt gebaut wurde
str_puffer:	ds.b	2*STR_GR	; zwei Listen fuer Timer B
str_aktiv:	ds.l	1		; die geltende (0: noch keine)
str_zeiger:	ds.l	1		; St_raster_int: naechste Grenze
str_rest:	ds.w	1		; Grenzen in diesem Bild
str_warte:	ds.b	1		; Zeilen, die der Interrupt abwartet
	even
; Nachreichen (St_nr_stand, Erkenntnis 241)
st_nr_zustand:	ds.w	1		; 0 aus, 1 mitschreiben, 2 fertig, 3 voll
st_nr_neu:	ds.w	1		; St_stand: Platz mit Batch, -1 keiner
st_nr_zeile:	ds.w	1		; ab dieser Bildzeile gilt Batch
st_nr_gen:	ds.w	1		; Bau des Eintrags (PL_GEN)
st_nr_liste:	ds.l	1		; die Rasterliste, fuer die mitgeschrieben wird
st_nr_lneu:	ds.l	1		; St_stand: die geltende
st_nr_eintrag:	ds.l	1		; Eintrag des Platzes (PL_EINTRAG)
st_nr_laenge:	ds.l	1		; belegt in st_nr_puffer
st_nr_jetzt:	ds.b	1		; gesetzt: St_stand zeichnet nach
st_nr_aktiv:	ds.b	1		; gesetzt: es wird nachgezeichnet
	even
ST_NR_GROESSE = 48*1024			; Layout 19560 + Bild 18400 + Kaesten
st_nr_puffer:	ds.b	ST_NR_GROESSE
st_zg_quelle:	ds.l	1		; Zeigerbild Thalions (Pointer_convert)
st_zg_bilder:	ds.b	PLAETZE*MPTR_H*8	; Zeigerbild je Platz (St_zeiger_bilder)
st_zplatz:	ds.b	ST_ZEILEN	; Platz je Bildzeile, fuer den VBL
	even
st_zsatz:	ds.l	ST_ZEILEN	; Satz je Bildzeile
ST_MERK_N = 4096			; Plaetze der Merkliste, Zweierpotenz
st_merk:	ds.b	32*ST_MERK_N	; 128 KB
sza_tiefe:	ds.w	1		; St_zeile_amiga
sza_schritt:	ds.w	1
sza_vers:	ds.w	1
sza_n:		ds.w	1
sgb_tiefe:	ds.w	1		; Get_block_orig
sgb_schritt:	ds.w	1
sgb_zeile:	ds.w	1
sgb_n:		ds.w	1
sgb_rest:	ds.w	1
sgb_punkte:	ds.b	16
st_kachel:	ds.b	KA_GR*ST_KACHEL_N ; 384 KB, St_kachel (P3, P5)
	even
; E12, Abschriften der 3D-Bloecke (St_abschrift_*)
sab_tab:	ds.l	256		; je Handle die Abschrift (0: keine; -1 beim Zaehlen)
sab_block:	ds.l	1		; der Block bei TOS (Malloc), 0: keiner
sab_frei:	ds.l	1		; beim Verteilen: naechste freie Stelle
sab_summe:	ds.l	1		; beim Zaehlen: Laenge aller Abschriften
sab_satz:	ds.l	1		; gefaerbt mit diesem Satz (0: noch nicht)
sab_himmel:	ds.l	1		; Sky_colour, wie Thalion es hatte
sab_boden:	ds.l	1		; Floor_colour, ebenso
sab_puffer:	ds.l	1		; sab_ein_langwort
sab_gen:	ds.w	1		; und dessen Bau (ST_GEN)
sab_aktiv:	ds.b	1		; gesetzt: ein 3D-Bild mit Abschriften laeuft
sab_fehlt:	ds.b	1		; sab_handles_pruefen
	even
	SECTION	Fast_BSS,bss
	even
sab_ok:		ds.b	256		; per handle: copy coloured with the current set
sab_schluessel:	ds.b	16		; ST_TAB 0..15 of that set, the key of the parks
sab_uhr:	ds.l	1		; counts the parks (PK_ALTER)
sab_parks:	ds.b	PK_SZ*SAB_PARKS	; parked copies of earlier maps
	even
	SECTION	Program,code

; ***************************************************************************
; What only the Falcon has, empty on the ST (library split phases 2 and
; 3): the R_range afterwork and the gradients in Set_fade (FALCON_LIB.S,
; RASTER.S; the ST keeps the gradients flat) and Drugged_FX on the colours
; (FALCON_LIB.S).  LIBRARY.S and FADE_SUP.S call them on both machines.
; All registers are preserved, except Bereiche_sammeln's d0.
; ***************************************************************************
Bloecke_nacharbeiten:
Zeichen_nacharbeiten:
Bereich_nacharbeiten:
Bereich_rueck:
Drogen_setzen:
Drogen_farben:
Bereiche_schritt:
	rts

; Bereiche_sammeln -- OUT: d0.w = 0, no gradient to fade (Set_fade).
Bereiche_sammeln:
	moveq	#0,d0
	rts

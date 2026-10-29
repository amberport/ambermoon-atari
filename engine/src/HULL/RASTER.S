; ***************************************************************************
; HULL/RASTER.S -- die Rasterliste, also unser Copper.
;
; Thalions Moduldeskriptoren tragen einen Raster_list_ptr, und die Listen
; sagen, welche Palette in welcher Bildzeile gilt:
;
;     Map_RL: R_palette 0,Main_pal            ; Statusleiste
;             R_range   1,25,35,Portrait_range ; Farbe 25 je Zeile
;             R_palette Middle_Y+1,Current_pal ; Kartenfenster
;             R_end
;
; On the Amiga the copper does this in the middle of the picture.  This file
; holds both ways to do it (RASTER_VERFAHREN, FALCON_OFF.S):
;   - RASTER_RAUM, the Falcon's way (user, 2026-09-30): each palette gets a
;     colour bank, the bank follows from the line ("what the Amiga does in
;     time we do in space").  From this file it uses Zeilenersatz, the
;     colour ranges (Bereich_*, Bereiche_*) and Amiga_nach_videl.
;   - RASTER_ZEIT, the time way: a Timer B interrupt rewrites the colour
;     registers at the line borders (Raster_liste_setzen, Raster_int), so
;     the original's 32 colours suffice.  The ST takes it (ST_LIB.S); on
;     the Falcon it is not wired up: MAIN.S installs Timer B only to keep
;     it quiet, sets no list (except under RASTERPRUEF), and refuses
;     RASTER_ZEIT (finding 154).  The text below describes this way.
;
; **Warum Timer B.**  Er zaehlt im Ereigniszaehlmodus die Bildzeilen (das
; Display-Enable-Signal) und ist auf dem Atari die kanonische Wahl fuer
; Rastereffekte; Musikroutinen nehmen ueblicherweise Timer A oder C.  Dass
; Thalion mit ST und Falcon plante, passt dazu.
;
; **Das Registerformat ist nachgesehen, nicht angenommen.**  Die VIDEL-Palette
; liegt ab $FFFF9800, ein Langwort je Farbe, und zwar als
;
;     Byte 0 = Rot, Byte 1 = Gruen, Byte 2 unbenutzt, Byte 3 = Blau
;
; also $RRGG00BB -- nicht $00RRGGBB wie bei VsetRGB.  Gemessen, indem die
; Register nach dem Setzen ausgelesen und gegen die bekannte TOS-Palette
; gehalten wurden (weiss $FCFC00FC, rot $FC000000, blau $000000FC).
;
; Aus dem Interrupt heraus wird direkt geschrieben; XBIOS ist dort verboten.
; Umgerechnet wird deshalb vorher, beim Setzen der Liste.
; ***************************************************************************

MFP		equ	$FFFFFA00
MFP_IERA	equ	$07		; Interrupt Enable A -- Timer B ist Bit 0
MFP_IPRA	equ	$0B		; Interrupt Pending A
MFP_ISRA	equ	$0F		; In Service A
MFP_IMRA	equ	$13		; Interrupt Mask A
MFP_TBCR	equ	$1B		; Timer B Control
MFP_TBDR	equ	$21		; Timer B Data
VEC_TIMERB	equ	$120		; MFP-Interrupt 8
VIDEL_PAL	equ	$FFFF9800

; Schritte je Liste.  **64 war zu knapp:** Inv_RL und Dialogue_RL zerlegen sich
; in 72 Schritte (zwei Portraitverlaeufe zu je 35 Zeilen plus zwei Paletten).
; Raster_liste_setzen bricht bei RS_MAX still ab -- der zweite Verlauf endete
; nach 27 Zeilen, ohne dass es jemand gemerkt haette.  Gezaehlt an Thalions
; MODULES.S; Listen mit symbolischer Laenge (C3_RL: C3_horizon) sind dabei
; nicht mitgezaehlt.
RS_MAX		equ	96

; Der Zeilenzaehler startet je Bild mit diesem Wert.  Liegt die erste
; Timer-B-Unterbrechung auf dem Geraet stabil N Zeilen daneben, gleicht ein
; Startwert das aus.  **Noch nicht gemessen** -- TIMERB.TOS ergab Zeile 81
; statt 100, aber mit einer Spanne, die Zittern und zweites Feuern vermischt.
; Setzbar ueber -DRASTER_VERSATZ=N, ohne die Quelle anzufassen.
	IFND	RASTER_VERSATZ
RASTER_VERSATZ	equ	0
	ENDC
RS_ZEILE	equ	0		; .w Bildzeile
RS_ART		equ	2		; .w 0 = ganze Palette, 1 = eine Farbe
RS_NR		equ	4		; .w Farbnummer (bei Art 1)
RS_WERT		equ	6		; .l Art 0: Zeiger auf 32 Register; Art 1: Wert
RS_SZ		equ	10

	SECTION	Program,code

; ***************************************************************************
; Raster_install / Raster_remove -- den Interrupt aufsetzen und abraeumen.
;
; Abraeumen ist nicht wahlfrei: bleibt der Vektor stehen, zeigt er ins Nichts,
; sobald das Programm aus dem Speicher ist.  Dieselbe Falle wie beim
; Mausvektor (HULL/LIBRARY.S).
; ***************************************************************************
Raster_install:
	movem.l	d0-d1/a0,-(sp)
	move.w	sr,d1			; Interrupts sperren
	move.w	#$2700,sr
	move.l	VEC_TIMERB,ras_altvec	; alten Vektor merken
	move.b	MFP+MFP_TBCR,ras_alttbcr
	move.b	MFP+MFP_TBDR,ras_alttbdr
	move.b	MFP+MFP_IERA,ras_altiera
	move.b	MFP+MFP_IMRA,ras_altimra
	IFD	ZIEL_ST
	move.l	#St_raster_int,VEC_TIMERB	; ST_LIB.S: 16 Register je Grenze
	ELSE
	move.l	#Raster_int,VEC_TIMERB
	ENDC
	clr.b	MFP+MFP_TBCR		; Timer B anhalten
	bclr	#0,MFP+MFP_IERA		; und stillegen, bis eine Liste steht
	bclr	#0,MFP+MFP_IMRA
	clr.w	ras_anzahl
; **Scharf gemacht wird im VBL, nicht in der Hauptschleife.**  Ein
; Vollbild-Neuzeichnen kostet rund dreissig Millisekunden, also mehr als eine
; Bildperiode -- aus der Schleife heraus kaeme das Zuruecksetzen auf Zeile 0
; regelmaessig zu spaet, und die Farbe des Vorbildes stuende noch.  Gemessen:
; die Flaeche blieb dann ueber das ganze Bild eingefaerbt.
;
; Eingehaengt wird in die VBL-Warteschlange (_nvbls/$454, _vblqueue/$456),
; nicht ueber Vektor $70 -- TOS haengt dort selbst viel hinein.
	move.w	$454,d0			; Anzahl der Plaetze
	move.l	$456,a0			; Zeiger auf die Liste
	subq.w	#1,d0
	bmi.b	ri_kein_platz
ri_suche:
	tst.l	(a0)
	beq.b	ri_platz_da
	addq.l	#4,a0
	dbf	d0,ri_suche
	bra.b	ri_kein_platz
ri_platz_da:
	move.l	a0,ras_vblslot
	move.l	#Raster_vbl,(a0)
ri_kein_platz:
	st	ras_da
	move.w	d1,sr
	movem.l	(sp)+,d0-d1/a0
	rts

Raster_remove:
	movem.l	d0-d1/a0,-(sp)
	tst.b	ras_da
	beq.b	rr_out
	move.w	sr,d1
	move.w	#$2700,sr
	clr.b	MFP+MFP_TBCR
	bclr	#0,MFP+MFP_IERA
	bclr	#0,MFP+MFP_IMRA
	move.b	ras_alttbcr,MFP+MFP_TBCR
	move.b	ras_alttbdr,MFP+MFP_TBDR
	move.b	ras_altiera,MFP+MFP_IERA
	move.b	ras_altimra,MFP+MFP_IMRA
	move.l	ras_altvec,VEC_TIMERB
	move.l	ras_vblslot,d0		; aus der VBL-Warteschlange nehmen
	beq.b	rr_kein_slot
	move.l	d0,a0
	clr.l	(a0)
	clr.l	ras_vblslot
rr_kein_slot:
	sf	ras_da
	move.w	d1,sr
rr_out:
	movem.l	(sp)+,d0-d1/a0
	rts

; ***************************************************************************
; Amiga_nach_videl -- ein Farbwort $0RGB in ein VIDEL-Register umrechnen.
;   d0 = $0RGB  ->  d0 = $RRGG00BB
; Vid_stufe (HULL/FADE_SUP.S) ist dieselbe Tabelle, die auch Bank0_setzen
; benutzt: Amiga-Stufe 0..15 auf ein VIDEL-Byte.
; ***************************************************************************
Amiga_nach_videl:
	movem.l	d1-d2/a0,-(sp)
	lea	Vid_stufe,a0
	moveq	#0,d2
	move.w	d0,d1			; Rot
	lsr.w	#8,d1
	and.w	#$f,d1
	move.b	0(a0,d1.w),d2
	lsl.l	#8,d2
	move.w	d0,d1			; Gruen
	lsr.w	#4,d1
	and.w	#$f,d1
	move.b	0(a0,d1.w),d2
	lsl.l	#8,d2			; Byte 2 bleibt null
	lsl.l	#8,d2
	move.w	d0,d1			; Blau
	and.w	#$f,d1
	move.b	0(a0,d1.w),d2
	move.l	d2,d0
	movem.l	(sp)+,d1-d2/a0
	rts

; ***************************************************************************
; Raster_liste_setzen -- Thalions Rasterliste in Schritte uebersetzen.
;
;   IN : a0 = Rasterliste (R_palette / R_range / R_end)
;
; Uebersetzt wird einmal, nicht je Bild: im Interrupt bleibt dann nur noch
; Register schreiben.  R_range wird dabei in seine Einzelzeilen zerlegt --
; eine Farbe je Zeile ist genau ein Schritt.
;
; Die Bedeutung der Felder ist an den Varianten im Original abgelesen:
;
;     R_range 1,25,35,Portrait_range     Startzeile 1, Farbe 25, 35 Zeilen
;     R_range 49,25,35,Portrait_range    dasselbe ab Zeile 49
;     R_range Map3D_Y,C3_raster_colour,C3_horizon,Current_sky
;
; Nur der erste Wert wandert mit der Aufrufstelle, der zweite ist die Farbe.
; ***************************************************************************
Raster_liste_setzen:
	movem.l	d0-d5/a0-a3,-(sp)
; **Erst leeren, dann uebersetzen.**  Die VBL kann jederzeit dazwischenfahren.
; Raster_start prueft ras_anzahl, der Interrupt prueft ras_endzeiger -- beide
; sehen waehrend des Uebersetzens eine leere Liste, und der Interrupt legt den
; Timer beim naechsten Feuern selbst still.  Ohne MFP-Zugriff, also auch aus
; dem Benutzermodus sicher.
	clr.w	ras_anzahl
	lea	ras_schritte,a2
	move.l	a2,ras_endzeiger
; d5 wird **vor** der Nullpruefung gesetzt.  Frueher stand es dahinter, und
; ein Nullzeiger schrieb in rls_fertig den d5 des Aufrufers nach ras_anzahl.
	moveq	#0,d5			; Anzahl der Schritte
	move.l	a0,d0
	beq	rls_fertig		; kein Raster_list_ptr -- nichts zu tun
rls_lauf:
	move.b	(a0),d0			; Kennbyte
	cmp.b	#RL_END,d0
	beq	rls_fertig
	cmp.b	#RL_PAL,d0
	bne.b	rls_range

	; ---- ganze Palette ab einer Zeile ----
	cmp.w	#RS_MAX,d5
	bcc	rls_fertig
	moveq	#0,d1
	move.b	1(a0),d1		; Zeile
	move.w	d1,RS_ZEILE(a2)
	clr.w	RS_ART(a2)
	clr.w	RS_NR(a2)
	; die 32 Amiga-Worte in einen Registersatz umrechnen
	move.l	2(a0),d2
	beq.b	rls_pal_weiter		; Nullzeiger -- ueberspringen
	move.l	d2,a1
	move.l	d5,d3
	mulu.w	#32*4,d3
	lea	ras_farben,a3
	add.l	d3,a3			; je Schritt ein eigener Satz
	move.l	a3,RS_WERT(a2)
	moveq	#31,d3
rls_pal_farbe:
	moveq	#0,d0
	move.w	(a1)+,d0
	bsr	Amiga_nach_videl
	move.l	d0,(a3)+
	dbf	d3,rls_pal_farbe
	lea	RS_SZ(a2),a2
	addq.w	#1,d5
rls_pal_weiter:
	addq.l	#6,a0
	bra	rls_lauf

rls_range:
	; ---- eine Farbe ueber mehrere Zeilen ----
	moveq	#0,d1
	move.b	1(a0),d1		; Startzeile
	moveq	#0,d2
	move.b	2(a0),d2		; Farbnummer
	moveq	#0,d3
	move.b	3(a0),d3		; Anzahl der Zeilen
	move.l	4(a0),d4
	beq.b	rls_range_weiter	; Nullzeiger
	move.l	d4,a1
	subq.w	#1,d3
	bmi.b	rls_range_weiter
rls_range_zeile:
	cmp.w	#RS_MAX,d5
	bcc.b	rls_range_weiter
	move.w	d1,RS_ZEILE(a2)
	move.w	#1,RS_ART(a2)
	move.w	d2,RS_NR(a2)
	moveq	#0,d0
	move.w	(a1)+,d0
	bsr	Amiga_nach_videl
	move.l	d0,RS_WERT(a2)
	lea	RS_SZ(a2),a2
	addq.w	#1,d5
	addq.w	#1,d1			; naechste Bildzeile
	dbf	d3,rls_range_zeile
rls_range_weiter:
	addq.l	#8,a0
	bra	rls_lauf

rls_fertig:
	move.l	a2,ras_endzeiger	; hinter den letzten Schritt
	move.w	d5,ras_anzahl		; zuletzt: erst jetzt macht die VBL scharf
	movem.l	(sp)+,d0-d5/a0-a3
	rts

; ***************************************************************************
; Raster_start -- je Bild einmal, in der VBL.
;
; **Zeilenzaehler statt Abstandsrechnung** (Vorschlag des Nutzers, so wie man
; es auf dem STE macht):
;
;   VBL        Zaehler auf RASTER_VERSATZ, alle Schritte fuer Zeile 0 sofort
;              ausfuehren, Timer B mit TBDR=1 starten -- ein Interrupt je Zeile.
;   Interrupt  Zaehler hochzaehlen; jeder Schritt, dessen Zeile erreicht ist,
;              wird ausgefuehrt; ist die Liste durch, Timer B aus.
;
; Die Vorfassung stellte TBDR im Interrupt jedesmal auf den Abstand zum
; naechsten Schritt und startete den Timer dafuer neu.  Genau das ist heikel:
; Anhalten und Neustarten kann ein Zeilenereignis verschlucken, und ein TBDR,
; den man ohne Anhalten schreibt, gilt erst nach dem *naechsten* Nachladen.
; Mit TBDR=1 laedt der Timer selbst nach und wird im Interrupt nie angefasst --
; nur am Ende einmal abgeschaltet.
;
; Der Preis: ein Interrupt je Zeile bis zum letzten Schritt -- Map_RL 37,
; Inv_RL gut 85.  Auf dem Falcon belanglos, auf dem STE grob zwei bis drei
; Prozent Rechenzeit.
;
; **Das Pending-Bit muss weg, bevor freigegeben wird.**  Ein aus dem Vorbild
; latchierter Timer-B-Interrupt feuert sonst sofort beim Freigeben.
; ***************************************************************************
Raster_start:
	movem.l	d2/a0,-(sp)
	tst.b	ras_da
	beq.b	rs_out
	tst.w	ras_anzahl
	beq.b	rs_out
	move.w	sr,d2
	move.w	#$2700,sr
	clr.b	MFP+MFP_TBCR		; Timer anhalten -- nur hier, nie im Interrupt
	move.w	#RASTER_VERSATZ,ras_zeile
	lea	ras_schritte,a0
rs_sofort:
	cmp.l	ras_endzeiger,a0
	bcc.b	rs_keiner		; Liste nur aus Zeile 0 -- kein Timer noetig
	tst.w	RS_ZEILE(a0)		; noch Zeile null?
	bne.b	rs_scharf
	bsr	Raster_schritt
	lea	RS_SZ(a0),a0
	bra.b	rs_sofort
rs_scharf:
	move.l	a0,ras_zeiger		; ab hier arbeitet der Interrupt
	move.b	#1,MFP+MFP_TBDR		; jede Zeile -- laedt selbst nach
	bclr	#0,MFP+MFP_IPRA
	bclr	#0,MFP+MFP_ISRA
	bset	#0,MFP+MFP_IERA
	bset	#0,MFP+MFP_IMRA
	move.b	#8,MFP+MFP_TBCR		; Ereigniszaehlmodus
	bra.b	rs_fertig
rs_keiner:
	bclr	#0,MFP+MFP_IERA
	bclr	#0,MFP+MFP_IMRA
rs_fertig:
	move.w	d2,sr
rs_out:
	movem.l	(sp)+,d2/a0
	rts

; ***************************************************************************
; Raster_vbl -- haengt in der VBL-Warteschlange und macht je Bild scharf.
; ***************************************************************************
Raster_vbl:
	IFD	ZIEL_ST
	bsr	St_raster_vbl		; ST_LIB.S: erster Bereich, Timer B scharf
	ELSE
	IFD	RASTERPRUEF
	bsr	Raster_pruefschieben
	ENDC
	bsr	Raster_start
	ENDC
	jmp	Bibliothek_vbl		; LIBRARY.S: VBL_counter, Thalions VblQ

	IFD	RASTERPRUEF
; ***************************************************************************
; Raster_pruefschieben -- die Kante je Bild eine Zeile tiefer legen.
;
; **Der Hardwaretest, der ohne Lineal auskommt.**  Ein stehendes Band muss man
; ausmessen und mit einer Vorgabe vergleichen; ein *wanderndes* Band beantwortet
; die Frage von selbst:
;
;   Die Kante wandert langsam nach unten und springt oben wieder hoch
;       -> Timer B zaehlt Bildzeilen.  Der Rasterinterrupt taugt.
;   Das ganze Bild flackert nur zwischen rot und schwarz, ohne Kante
;       -> die Liste laeuft in der Austastluecke durch, der Timer zaehlt nicht.
;   Das Bild bleibt einfarbig
;       -> der Interrupt feuert gar nicht.
;
; Am Scandoubler (15 kHz -> 31 kHz) ist das Band doppelt so hoch; die Aussage
; aendert sich dadurch nicht, nur der Massstab.
;
; Geschoben wird der *zweite* Schritt der Pruefliste -- der, der auf schwarz
; zurueckschaltet.  Schritt null bleibt bei Zeile 0 und faerbt rot.
; ***************************************************************************
RP_VON		equ	20		; oben: noch sicher im Bild
RP_BIS		equ	180		; unten: desgleichen
RP_TEILER	equ	2		; jedes zweite Bild -- gut sichtbar langsam

Raster_pruefschieben:
	movem.l	d0/a0,-(sp)
	cmp.w	#2,ras_anzahl		; die Pruefliste hat genau zwei Schritte
	bne.b	rps_out
	addq.w	#1,rp_zaehler
	move.w	rp_zaehler,d0
	and.w	#RP_TEILER-1,d0
	bne.b	rps_out
	lea	ras_schritte+RS_SZ,a0	; Schritt 1: zurueck auf schwarz
	move.w	RS_ZEILE(a0),d0
	addq.w	#1,d0
	cmp.w	#RP_BIS,d0
	blt.b	rps_setzen
	move.w	#RP_VON,d0
rps_setzen:
	move.w	d0,RS_ZEILE(a0)
rps_out:
	movem.l	(sp)+,d0/a0
	rts
	ENDC

; ***************************************************************************
; Raster_schritt -- einen Schritt ausfuehren.  a0 = Schritt.
; Register ausser a0 bleiben; wird auch aus dem Interrupt gerufen.
; ***************************************************************************
Raster_schritt:
	movem.l	d0-d1/a1-a2,-(sp)
	tst.w	RS_ART(a0)
	bne.b	rsc_eine
	; ---- ganze Palette: 32 Register ----
	move.l	RS_WERT(a0),d0
	beq.b	rsc_out
	move.l	d0,a1
	lea	VIDEL_PAL,a2
	moveq	#31,d0
rsc_farbe:
	move.l	(a1)+,(a2)+
	dbf	d0,rsc_farbe
	bra.b	rsc_out
rsc_eine:
	; ---- eine einzelne Farbe ----
	moveq	#0,d0
	move.w	RS_NR(a0),d0
	lsl.w	#2,d0
	lea	VIDEL_PAL,a2
	move.l	RS_WERT(a0),0(a2,d0.w)
rsc_out:
	movem.l	(sp)+,d0-d1/a1-a2
	rts

; ***************************************************************************
; Raster_int -- der Timer-B-Interrupt, einmal je Bildzeile.
;
; Zaehler hochzaehlen, jeden faelligen Schritt ausfuehren, quittieren.
;
; "Faellig" heisst Zeile <= Zaehler, nicht Zeile = Zaehler.  Geht einmal ein
; Zeilenereignis verloren -- etwa weil eine ganze Palette laenger als eine
; Zeile zum Schreiben braucht --, wird der Schritt eine Zeile spaet nachgeholt
; statt fuer das ganze Bild auszufallen.  Die Listen sind nach Zeilen sortiert,
; also genuegt es, vorn nachzusehen.
;
; Ohne mulu: der Interrupt kommt jede Zeile, und auf dem 68000 kostet ein
; mulu.w bis zu 70 Takte.  Darum ein Zeiger auf den naechsten Schritt statt
; eines Index.
;
; Das grosse Schreiben der ganzen Palette kommt in Thalions Listen zuletzt.
; Dauert es auf dem STE laenger als eine Zeile, stimmt der Zaehler danach
; nicht mehr -- das ist egal, denn danach ist der Timer schon aus.
; ***************************************************************************
Raster_int:
	movem.l	d0/a0,-(sp)
	addq.w	#1,ras_zeile
	move.l	ras_zeiger,a0
ri_lauf:
	cmp.l	ras_endzeiger,a0
	bcc.b	ri_ende
	move.w	RS_ZEILE(a0),d0
	cmp.w	ras_zeile,d0
	bhi.b	ri_quittieren		; naechster Schritt liegt noch tiefer
	bsr	Raster_schritt		; faellig -> jetzt
	lea	RS_SZ(a0),a0
	bra.b	ri_lauf
ri_ende:
	clr.b	MFP+MFP_TBCR		; fuer dieses Bild sind wir durch
ri_quittieren:
	move.l	a0,ras_zeiger
	bclr	#0,MFP+MFP_ISRA		; Timer B quittieren
	movem.l	(sp)+,d0/a0
	rte

	IFD	RASTERPRUEF
; ***************************************************************************
; Kalibrierung: ab RASTERZEILE wird Farbe 0 rot.
;
; Zwei Fragen beantwortet das, und nur die zweite ist die wichtige:
;
;   1. **Wo** faengt das Rot an?  Die Differenz zur programmierten Zeile ist
;      der feste Versatz -- Timer B zaehlt Display-Enable-Impulse, und die
;      beginnen nicht dort, wo unser Bildfenster beginnt.
;   2. **Wandert** es mit?  Verschiebt man RASTERZEILE um N und die rote
;      Kante wandert um N, zaehlt der Timer wirklich Zeilen.  Bleibt sie
;      stehen, zaehlt er etwas anderes (oder gar nicht), und ein fester
;      Versatz waere nur ein Zufallstreffer.
;
; **Hatari kann diese Frage nicht beantworten.**  Seine TODO-Liste fuehrt
; fuer die Falcon-Videl-Emulation "Palette switching during screen drawing"
; als noch zu erledigen (hatari.frama.io/hatari/doc/todo.txt).  Ein
; Falcon-Bild wird dort mit *einem* Palettenstand gezeichnet, der letzte
; gewinnt -- am 2026-09-12 in beide Richtungen gemessen: Liste endet rot ->
; Bild ganz rot, Liste endet schwarz -> Bild ganz schwarz, beides unabhaengig
; von RASTERZEILE.  Das sagt nichts ueber unseren Interrupt.  Ob er
; zeilenweise feuert, kann nur echte Hardware zeigen.
;
; (Auch der aeltere VGA-Befund -- TBDR 120 und 150 ergaben beide Schirmzeile
; 34 -- ist damit neu zu lesen: er war vermutlich derselbe Emulatormangel und
; kein Beleg gegen VGA.  Fuer RGB sprechen die anderen zwei Gruende in
; FALCON_OFF.S weiterhin, die Zeitbasis und der STE.)
;
; Set the line with -DRASTERZEILE=N.  Assembled only with -DRASTERPRUEF=1.
; ***************************************************************************
	IFND	RASTERZEILE
RASTERZEILE	equ	100
	ENDC
; **Die Liste faengt rot an und hoert rot auf.**  Das ist Absicht: eine Liste,
; die bei Schwarz anfaengt und bei RASTERZEILE rot wird, kann "Timer feuert
; nie" und "Timer feuert sofort" nicht auseinanderhalten -- im ersten Fall
; bleibt das Bild schwarz, im zweiten laeuft die ganze Liste in der
; Austastluecke durch und das Bild ist durchgehend rot.  Andersherum sind
; alle drei Faelle am Abzug zu erkennen:
;
;   Rot oben, Schwarz ab einer Kante   Timer zaehlt Zeilen -- Kante messen
;   Bild durchgehend rot               Timer feuert nie (Schwarz kommt nie)
;   Bild durchgehend schwarz           Timer feuert sofort (in der Austastluecke)
;
; Zwei Schritte genuegen dafuer, nicht einundsechzig.
	SECTION	Fast_DATA,data
	even
Raster_pruefliste:
	R_range	0,0,1,Raster_prueffarben	; Zeile 0: Farbe 0 rot
	R_range	RASTERZEILE,0,1,Raster_pruefschwarz	; ab dort: wieder schwarz
	R_end
	even
Raster_pruefschwarz:
	dc.w	$0000
	even
Raster_prueffarben:
	dc.w	$0F00			; kraeftiges Rot
	even
	SECTION	Program,code
	ENDC

	IFND	ZIEL_ST
; ***************************************************************************
; R_range auf dem Falcon: eine Farbe je Zeile, ohne Rasterinterrupt (E3).
;
; Thalions Copper setzt fuer jede Zeile eines Verlaufs ein Farbregister neu
; (AM2_CPU 0:$233B8: WAIT Zeile, MOVE Farbe & 31).  Wir geben jeder solchen
; Zeile einen eigenen **Platz**, eine Farbe in den Baenken 3-7 (96..255),
; und Set_fade schreibt dort den Wert der Tabelle hinein.  Wer in der Zeile
; die Verlaufsfarbe zeichnet, setzt den Platz statt Bank+Farbe
; (Zeilenersatz).
;
; **Gesetzt wird beim Setzen der Liste, nicht je Bild.**  So tut es Thalions
; Set_fade (0:$230BC): die VBL kopiert die Tabellenwerte in eine
; Arbeitsliste (9:$9E0E), und Aenderungen an Current_sky werden erst mit
; Reset_current_RL sichtbar.  Thalion ruft es selbst (Set_C3_light_level).
;
; **Nachlauf.**  Nach dem Verlauf behaelt das Farbregister seinen letzten
; Wert, bis die naechste R_palette alle 32 neu setzt.  Portrait_range endet
; mit 0: Farbe 25 ist in Zeile 36 schwarz.  Unter dem Himmel traegt Farbe 9
; die Horizontfarbe weiter, und Thalion benutzt sie dort (Bodentextur in
; Karte 349, Waende, Objekte; Auszaehlung der 3D-Sitzung, 2026-10-10).
; Diese Zeilen bekommen den Platz der letzten Verlaufszeile.
;
; **Plaetze im 3D-Fenster haben Ebene 4 = 0.**  Clear_1plane_block loescht
; dort in jedem Bild Ebene 4 (Sterne); ein Platz mit Ebene 4 waere danach
; eine andere Farbe.  Zeilen Map3D_Y..Map3D_Y+143 nehmen darum b*32+c,
; alle anderen b*32+16+c (b = 3..7, c = 1..15), je 75.
;
; **c = 0 wird nicht vergeben** (Hinweis der 3D-Sitzung): ein solcher Platz
; hat in den Ebenen 0-4 nur Nullen, und jede Regel "0 bleibt 0", die auf
; die unteren fuenf Ebenen schaut (Zeilenfarbe, Get_block mit d5 = 5,
; Put_unmasked_block), machte aus ihm Farbe 0.  C3_RL braucht 72 Plaetze
; im 3D-Fenster.  Vergeben wird in
; der Reihenfolge der Liste: der Platz einer Zeile haengt nur an der Liste,
; nicht daran, was gerade gesetzt ist (wie Platzbank, Erkenntnis 264).
;
; Liegen zwei Verlaeufe auf einer Zeile, gilt der spaetere; der Nachlauf
; des frueheren endet dann dort.  In Thalions Listen kommt das nicht vor.
; ***************************************************************************
BER_ERSTE	equ	96		; erste Farbe der Plaetze (Bank 3)
BER_ANZAHL	equ	160		; Bank 3..7
BER_TEIL	equ	75		; Plaetze je Sorte (Ebene 4 = 0 / = 1)
BER_FENSTER_BIS	equ	Map3D_Y+2*C3_horizon	; erste Zeile unter dem 3D-Fenster

; ***************************************************************************
; Zeilenersatz -- welche Farbe in einer Zeile ersetzt wird, und wodurch.
;
;   IN : d0.w = Bildzeile
;   OUT: d0.w = Verlaufsfarbe (Thalions Nummer 1..31; 0 = keine),
;        d1.w = Platz (Schirmfarbe 96..255); Z gesetzt bei d0 = 0.
;   Alle uebrigen Register bleiben.
;
; Es gilt die Rasterliste, die auch Farbbank nimmt (Zeichenliste,
; LIBRARY.S).  Die Zeilentabelle wird nur neu gebaut, wenn die Liste
; wechselt; Thalions Listen sind feste Daten.
; ***************************************************************************
Zeilenersatz:
	movem.l	d2/a0,-(sp)
	move.w	d0,d2
	bsr	Zeichenliste		; d1 = Liste oder 0
	cmp.l	zb_liste,d1
	beq.b	ze_da
	move.l	d1,a0
	bsr	Bereich_tabelle
ze_da:
	moveq	#0,d0
	moveq	#0,d1
	cmp.w	#SCRH,d2
	bcc.b	ze_raus			; ausserhalb des Bilds (auch negativ)
	add.w	d2,d2
	lea	Zb_tab,a0
	move.w	0(a0,d2.w),d1
	move.w	d1,d0
	lsr.w	#8,d0			; Farbe
	and.w	#$ff,d1			; Platz
ze_raus:
	tst.w	d0
	movem.l	(sp)+,d2/a0		; movem laesst die Flags stehen
	rts

; ***************************************************************************
; Bereich_nacharbeiten -- nach dem Zeichnen die Verlaufsfarbe auf den Platz
; der Zeile setzen (Schritt 3).
;
;   IN : d0.w/d1.w = eine Ecke, d2.w/d3.w = die andere (einschliesslich,
;        in beliebiger Ordnung), gezeichnet in Work_screen.
;   Alle Register bleiben.
;
; **Die Zeichenroutinen bleiben, wie sie sind.**  Sie legen Thalions Farbe
; wie bisher in die Bank der Zeile (Zeilenfarbe); danach geht diese Routine
; ueber das Rechteck und ersetzt in jeder Verlaufszeile jeden Punkt der
; Farbe Bank+Verlaufsfarbe durch den Platz der Zeile.  Damit braucht
; Farbbank_spanne keine neuen Grenzen, und der Kachelspeicher bleibt
; gueltig: er haelt das Bild vor der Nacharbeit.
;
; Das Ersetzen ist ueberall richtig, auch ausserhalb der CA: ein Punkt
; dieser Farbe in dieser Zeile ist auf dem Amiga das Copper-Register.  Der
; Aufrufer darf das Rechteck also groesser angeben, als er gezeichnet hat.
;
; Je Block und Zeile: Maske = UND ueber die acht Ebenen von (Wort EOR
; bn_muster), das sind die Punkte der alten Farbe; geschrieben wird nur,
; wo sie trifft.  Zeilen ausserhalb zb_von..zb_bis kosten nichts.
; ***************************************************************************
Bereich_nacharbeiten:
	movem.l	d0-d7/a0-a4,-(sp)
	bsr	Bereich_aktuell
	cmp.w	d0,d2
	bge.b	bn_ox
	exg	d0,d2
bn_ox:	cmp.w	d1,d3
	bge.b	bn_oy
	exg	d1,d3
bn_oy:	cmp.w	zb_von,d1		; senkrecht auf die Verlaufszeilen
	bge.b	bn_y1
	move.w	zb_von,d1
bn_y1:	cmp.w	zb_bis,d3
	ble.b	bn_y2
	move.w	zb_bis,d3
bn_y2:	cmp.w	d1,d3
	blt	bn_raus
	tst.w	d0			; seitlich auf den Schirm
	bpl.b	bn_x1
	moveq	#0,d0
bn_x1:	cmp.w	#SCRW-1,d2
	ble.b	bn_x2
	move.w	#SCRW-1,d2
bn_x2:	cmp.w	d0,d2
	blt	bn_raus
	asr.w	#4,d0			; erster Block
	asr.w	#4,d2
	sub.w	d0,d2			; Bloecke - 1
	move.l	Work_screen,a1
	mulu.w	#TROW,d0
	add.l	d0,a1
	move.w	d1,d0
	mulu.w	#SCRROW,d0
	add.l	d0,a1			; a1 = erste Zeile, erster Block
	move.w	d1,d7			; Bildzeile
	sub.w	d1,d3			; Zeilen - 1
	lea	Zb_tab,a2
	add.w	d1,a2
	add.w	d1,a2
bn_zeile:
	move.w	(a2)+,d5		; Farbe<<8 | Platz
	beq.b	bn_zeile_weiter
	bsr	bn_farben		; d0 = Bank+Farbe, d1 = Platz
	bsr	bn_tabellen		; alt d0 -> neu d1
	move.l	a1,a4
	move.w	d2,d4
bn_block:
	move.l	a4,a0
	lea	bn_muster,a3
	moveq	#-1,d0
	moveq	#PLANES-1,d6
bn_maske:
	move.w	(a0)+,d5
	move.w	(a3)+,d1
	eor.w	d1,d5
	and.w	d5,d0
	dbeq	d6,bn_maske		; keine Spur der Farbe mehr: fertig
	tst.w	d0
	beq.b	bn_block_weiter
	move.l	a4,a0
	lea	bn_setzen,a3
	move.w	d0,d5
	not.w	d5
	moveq	#PLANES-1,d6
bn_setz:
	move.w	(a3)+,d1
	and.w	d0,d1
	and.w	d5,(a0)
	or.w	d1,(a0)+
	dbf	d6,bn_setz
bn_block_weiter:
	lea	TROW(a4),a4
	dbf	d4,bn_block
bn_zeile_weiter:
	lea	SCRROW(a1),a1
	addq.w	#1,d7
	dbf	d3,bn_zeile
bn_raus:
	movem.l	(sp)+,d0-d7/a0-a4
	rts

; d5 = Eintrag aus Zb_tab, d7 = Bildzeile -> d0 = Bank der Zeile +
; Verlaufsfarbe, d1 = Platz.  Alle uebrigen Register bleiben.
bn_farben:
	move.w	d7,d0
	bsr	Farbbank_spanne		; d0 = Bank, d1 zerstoert
	move.w	d5,d1
	lsr.w	#8,d1
	add.w	d1,d0
	move.w	d5,d1
	and.w	#$ff,d1
	rts

; d0 = alte Farbe, d1 = neue -> bn_muster, bn_setzen.
; Zerstoert d0, d1, d5, d6, a3.
bn_tabellen:
	lea	bn_muster,a3
	moveq	#PLANES-1,d6
bnt_alt:
	lsr.w	#1,d0
	scc	d5			; Bit 0: hier muss das Wort 0 sein
	ext.w	d5
	move.w	d5,(a3)+
	dbf	d6,bnt_alt
	lea	bn_setzen,a3
	moveq	#PLANES-1,d6
bnt_neu:
	lsr.w	#1,d1
	scs	d5
	ext.w	d5
	move.w	d5,(a3)+
	dbf	d6,bnt_neu
	rts

; ***************************************************************************
; Bereich_aktuell -- Zb_tab fuer die Rasterliste der Zeichnung (Zeichenliste,
; LIBRARY.S); neu gebaut nur, wenn die Liste wechselt.  Alle Register bleiben.
; ***************************************************************************
Bereich_aktuell:
	movem.l	d1/a0,-(sp)
	bsr	Zeichenliste		; d1 = Liste oder 0, zerstoert a0
	cmp.l	zb_liste,d1
	beq.b	bak_da
	move.l	d1,a0
	bsr	Bereich_tabelle
bak_da:
	movem.l	(sp)+,d1/a0
	rts

; ***************************************************************************
; Bereich_rueck -- Get_block: Plaetze im gesicherten Ausschnitt wieder zur
; Farbe, die gezeichnet wurde (Bank + Verlaufsfarbe).
;
;   IN : a0 = Ziel, d0/d1 = Ecke (X auf einer Blockgrenze), d5 = Ebenen des
;        Ziels, d6 = Breite in Bloecken, d7 = Hoehe, wie Get_block.
;   Alle Register bleiben.
;
; **Warum.**  Open_window und HDOBS.S sichern mit d5 = 5 (Erkenntnis 191).
; Von einem Platz (96..255) blieben die unteren fuenf Bits, also irgendeine
; Farbe, und Put_unmasked_block gaebe sie mit der Bank zurueck -- nicht
; Thalions 25, und die Nacharbeit erkennte sie nicht mehr.  Mit Bank + 25
; im Ausschnitt kommt beim Zuruecksetzen 25 an und wird wieder Platz.
;
; Die Maske kommt aus dem Schirm (alle acht Ebenen), geschrieben wird ins
; Ziel: d5 = SCHIRM_FORMAT blockverzahnt wie der Schirm, sonst je Zeile
; Ebene fuer Ebene (Amiga-Format), jeweils nur die d5 Ebenen des Ziels.
; ***************************************************************************
Bereich_rueck:
	movem.l	d0-d7/a0-a5,-(sp)
	bsr	Bereich_aktuell
	tst.w	d5
	ble	br_raus
	tst.w	d6
	ble	br_raus
	cmp.w	zb_bis,d1
	bgt	br_raus			; ganz unter dem letzten Verlauf
	move.w	d5,br_ebenen
	move.w	d5,d4
	mulu.w	d6,d4
	add.l	d4,d4
	move.l	d4,br_zlaenge		; d5 Ebenen * d6 Worte je Zeile
	cmp.w	#SCHIRM_FORMAT,d5
	bcs.b	br_amiga
	move.w	#2,br_schritt_e
	move.w	#TROW,br_schritt_b
	bra.b	br_schritte
br_amiga:
	move.w	d6,d4
	add.w	d4,d4
	move.w	d4,br_schritt_e
	move.w	#2,br_schritt_b
br_schritte:
	move.w	d6,d2
	subq.w	#1,d2			; Bloecke - 1
	move.w	d7,d3
	subq.w	#1,d3			; Zeilen - 1
	bmi	br_raus
	move.l	Work_screen,a1
	lsr.w	#4,d0
	mulu.w	#TROW,d0
	add.l	d0,a1
	move.w	d1,d0
	muls.w	#SCRROW,d0
	add.l	d0,a1			; a1 = Schirm, erste Zeile, erster Block
	move.w	d1,d7			; Bildzeile
br_zeile:
	cmp.w	zb_von,d7
	blt.b	br_weiter
	cmp.w	zb_bis,d7
	bgt.b	br_weiter
	move.w	d7,d1
	add.w	d1,d1
	lea	Zb_tab,a2
	move.w	0(a2,d1.w),d5
	beq.b	br_weiter
	bsr	bn_farben		; d0 = Bank+Farbe, d1 = Platz
	exg	d0,d1			; alt = Platz, neu = Bank+Farbe
	bsr	bn_tabellen
	move.l	a1,a4
	move.l	a0,a5
	move.w	d2,d4
br_block:
	move.l	a4,a2
	lea	bn_muster,a3
	moveq	#-1,d0
	moveq	#PLANES-1,d6
br_maske:
	move.w	(a2)+,d5
	move.w	(a3)+,d1
	eor.w	d1,d5
	and.w	d5,d0
	dbeq	d6,br_maske
	tst.w	d0
	beq.b	br_block_weiter
	move.l	a5,a2
	lea	bn_setzen,a3
	move.w	d0,d5
	not.w	d5
	move.w	br_ebenen,d6
	subq.w	#1,d6
br_setz:
	move.w	(a3)+,d1
	and.w	d0,d1
	and.w	d5,(a2)
	or.w	d1,(a2)
	add.w	br_schritt_e,a2
	dbf	d6,br_setz
br_block_weiter:
	lea	TROW(a4),a4
	add.w	br_schritt_b,a5
	dbf	d4,br_block
br_weiter:
	lea	SCRROW(a1),a1
	add.l	br_zlaenge,a0
	addq.w	#1,d7
	dbf	d3,br_zeile
br_raus:
	movem.l	(sp)+,d0-d7/a0-a5
	rts

; ***************************************************************************
; Platz_rueck -- Get_pixel: ein Platz wird wieder Bank + Verlaufsfarbe.
;   IN : d1.w = Bildzeile, d4.w = Schirmfarbe.  OUT: d4.w.
;   Alle uebrigen Register bleiben.
; ***************************************************************************
Platz_rueck:
	cmp.w	#BER_ERSTE,d4
	bcs.b	plr_raus
	movem.l	d0-d1/d5/a0,-(sp)
	bsr	Bereich_aktuell
	cmp.w	#SCRH,d1
	bcc.b	plr_aus
	move.w	d1,d0
	add.w	d0,d0
	lea	Zb_tab,a0
	move.w	0(a0,d0.w),d5
	beq.b	plr_aus
	cmp.b	d5,d4			; der Platz dieser Zeile?
	bne.b	plr_aus
	move.w	d1,d0
	bsr	Farbbank_spanne		; d0 = Bank
	lsr.w	#8,d5
	add.w	d5,d0
	move.w	d0,d4
plr_aus:
	movem.l	(sp)+,d0-d1/d5/a0
plr_raus:
	rts

; ***************************************************************************
; Bereich_tabelle -- die Zeilentabelle einer Rasterliste bauen.
;   IN : a0 = Rasterliste oder 0.  Alle Register bleiben.
;
; Zb_tab: je Bildzeile ein Wort, oben die Verlaufsfarbe, unten der Platz;
; 0 = kein Verlauf.  zb_liste merkt, fuer welche Liste sie gilt.
; ***************************************************************************
Bereich_tabelle:
	movem.l	d0-d7/a0-a1,-(sp)
	move.l	a0,zb_liste
	lea	Zb_tab,a1
	move.w	#SCRH-1,d0
bt_leer:
	clr.w	(a1)+
	dbf	d0,bt_leer
	lea	Zb_tab,a1
	move.l	a0,d0
	beq	bt_raus
	moveq	#0,d3			; vergebene Plaetze mit Ebene 4 = 0
	moveq	#0,d4			; und mit Ebene 4 = 1
	moveq	#0,d5			; Nachlauf: Farbe<<8 | Platz, 0 = keiner
	moveq	#0,d6			; Nachlauf ab dieser Zeile
bt_lauf:
	move.b	(a0),d0			; Kennbyte
	cmp.b	#RL_END,d0
	beq.b	bt_ende
	moveq	#0,d1
	move.b	1(a0),d1		; Zeile des Eintrags
	bsr	bt_nachlauf		; bis hierher nachlaufen lassen
	cmp.b	#RL_PAL,d0
	bne.b	bt_range
	moveq	#0,d5			; R_palette setzt alle 32 Farben neu
	addq.l	#6,a0
	bra.b	bt_lauf
bt_range:
	moveq	#0,d2
	move.b	2(a0),d2
	and.w	#31,d2			; Farbe, wie Thalions Copper
	beq.b	bt_range_weiter		; Farbe 0 ist nicht darstellbar
	moveq	#0,d7
	move.b	3(a0),d7		; Zeilen
	bra.b	bt_rz_test
bt_rz:
	cmp.w	#SCRH,d1
	bcc.b	bt_rz_aus
	bsr	bt_platz		; d0 = Platz, N: keiner mehr frei
	bmi.b	bt_rz_naechste
	move.w	d2,d5
	lsl.w	#8,d5
	move.b	d0,d5
	move.w	d1,d0
	add.w	d0,d0
	move.w	d5,0(a1,d0.w)
bt_rz_naechste:
	addq.w	#1,d1
bt_rz_test:
	dbf	d7,bt_rz
bt_rz_aus:
	move.w	d1,d6			; Nachlauf ab hier, d5 = letzte Zeile
bt_range_weiter:
	addq.l	#8,a0
	bra.b	bt_lauf
bt_ende:
	move.w	#SCRH,d1
	bsr	bt_nachlauf
bt_raus:
	; ---- erste und letzte Verlaufszeile, fuer den schnellen Ausstieg in
	; Bereich_nacharbeiten (zb_von = SCRH, zb_bis = -1: keine) ----
	lea	Zb_tab,a1
	moveq	#0,d0
	move.w	#SCRH,d1
	moveq	#-1,d2
bt_grenzen:
	tst.w	(a1)+
	beq.b	bt_g_leer
	cmp.w	#SCRH,d1
	bne.b	bt_g_hat
	move.w	d0,d1			; die erste
bt_g_hat:
	move.w	d0,d2			; bisher die letzte
bt_g_leer:
	addq.w	#1,d0
	cmp.w	#SCRH,d0
	bcs.b	bt_grenzen
	move.w	d1,zb_von
	move.w	d2,zb_bis
	movem.l	(sp)+,d0-d7/a0-a1
	rts

; Zeilen d6..d1-1 mit dem Nachlauf d5 fuellen (nichts bei d5 = 0).
; Alle Register bleiben.
bt_nachlauf:
	tst.w	d5
	beq.b	btn_raus
	movem.l	d0-d1,-(sp)
	cmp.w	#SCRH,d1
	bls.b	btn_bis
	move.w	#SCRH,d1
btn_bis:
	move.w	d6,d0
	bra.b	btn_test
btn_zeile:
	add.w	d0,d0
	move.w	d5,0(a1,d0.w)
	lsr.w	#1,d0
	addq.w	#1,d0
btn_test:
	cmp.w	d1,d0
	bcs.b	btn_zeile
	movem.l	(sp)+,d0-d1
btn_raus:
	rts

; Den naechsten Platz fuer Zeile d1 vergeben: d0 = Platz, N bei keinem.
; Zaehlt d3 (Ebene 4 = 0) oder d4 (Ebene 4 = 1) weiter.
bt_platz:
	cmp.w	#Map3D_Y,d1
	bcs.b	btp_eins
	cmp.w	#BER_FENSTER_BIS,d1
	bcc.b	btp_eins
	cmp.w	#BER_TEIL,d3		; im 3D-Fenster: Ebene 4 = 0
	bcc.b	btp_keiner
	move.w	d3,d0
	addq.w	#1,d3
	bra.b	btp_rechnen
btp_eins:
	cmp.w	#BER_TEIL,d4
	bcc.b	btp_keiner
	move.w	d4,d0
	addq.w	#1,d4
	bsr.b	btp_rechnen
	add.w	#16,d0			; Ebene 4 = 1
	rts
btp_rechnen:				; k -> BER_ERSTE + (k/15)*32 + 1 + k%15
	move.w	d1,-(sp)
	and.l	#$ffff,d0
	divu.w	#15,d0			; unten k/15, oben k%15
	move.w	d0,d1
	lsl.w	#5,d1
	swap	d0
	add.w	d1,d0
	add.w	#BER_ERSTE+1,d0
	move.w	(sp)+,d1		; move setzt N nach d1 -- also neu pruefen
	tst.w	d0
	rts
btp_keiner:
	moveq	#-1,d0
	rts

; ***************************************************************************
; Bereiche_sammeln -- die Verlaeufe einer Liste fuer Set_fade.
;   IN : a0 = Rasterliste (oder 0), d1/d2 = Zeilenbereich, d5 = Art
;   OUT: d0.w = Zahl der Plaetze, die Bereiche_schritt blendet
;   Alle uebrigen Register bleiben.
;
; Wie Thalions Set_fade (0:$23130.., 0:$2315C.., 0:$231FC..):
;   Set_new        alle Verlaeufe sofort auf die Tabelle
;   Start_fade_in  im Bereich (nach der Startzeile) von Schwarz auf die
;                  Tabelle blenden, die uebrigen sofort setzen
;   Fade_out       im Bereich vom laufenden Wert auf Schwarz, die uebrigen
;                  bleiben stehen
; Am Ende werden die Plaetze gezeigt.
; ***************************************************************************
Bereiche_sammeln:
	movem.l	d1-d7/a0-a5,-(sp)
	move.w	d1,d6			; von
	move.w	d2,d7			; bis
	bsr	Bereich_tabelle
	clr.w	bb_anzahl
	moveq	#0,d4			; Zahl der zu blendenden Plaetze
	move.l	a0,d0
	beq	bsa_raus
	lea	Bb_platz,a2
	lea	Bb_von,a3
	lea	Bb_ziel,a4
bsa_lauf:
	move.b	(a0),d0
	cmp.b	#RL_END,d0
	beq	bsa_fertig
	cmp.b	#RL_PAL,d0
	bne.b	bsa_range
	addq.l	#6,a0
	bra.b	bsa_lauf
bsa_range:
	move.l	4(a0),d0
	beq	bsa_weiter		; keine Tabelle
	move.l	d0,a1
	moveq	#0,d1
	move.b	1(a0),d1		; Startzeile
	moveq	#0,d2
	move.b	2(a0),d2
	and.w	#31,d2			; Farbe
	moveq	#0,d3
	move.b	3(a0),d3		; Zeilen
	cmp.w	#Set_new,d5
	beq.b	bsa_setzen
	cmp.w	d6,d1			; im Bereich?  Vergleich mit Vorzeichen,
	blt.b	bsa_aussen		; d1 = -1 heisst: alle
	cmp.w	d7,d1
	bgt.b	bsa_aussen
	bra.b	bsa_blenden
bsa_aussen:
	cmp.w	#Fade_out,d5
	beq.b	bsa_weiter		; Abblenden laesst sie stehen

	; ---- sofort setzen ----
bsa_setzen:
	bra.b	bsa_s_test
bsa_s_zeile:
	move.w	(a1)+,-(sp)		; Tabellenwert
	bsr.b	bsa_platz		; d0 = Platz-BER_ERSTE, N: keiner
	bmi.b	bsa_s_nichts
	add.w	d0,d0
	lea	Slot_ist,a5
	move.w	(sp),0(a5,d0.w)
bsa_s_nichts:
	addq.l	#2,sp
	addq.w	#1,d1
bsa_s_test:
	dbf	d3,bsa_s_zeile
	bra.b	bsa_weiter

	; ---- zum Blenden vormerken ----
bsa_blenden:
	bra.b	bsa_b_test
bsa_b_zeile:
	bsr.b	bsa_platz
	bmi.b	bsa_b_nichts
	cmp.w	#BER_ANZAHL,d4
	bcc.b	bsa_b_nichts
	move.w	d0,(a2)+		; Platz
	add.w	d0,d0
	lea	Slot_ist,a5
	cmp.w	#Fade_out,d5
	bne.b	bsa_b_ein
	move.w	0(a5,d0.w),(a3)+	; vom laufenden Wert
	clr.w	(a4)+			; nach Schwarz
	bra.b	bsa_b_gemerkt
bsa_b_ein:
	clr.w	(a3)+			; von Schwarz
	move.w	(a1),(a4)+		; auf die Tabelle
	clr.w	0(a5,d0.w)		; und gleich schwarz, wie Thalion (0:$2326E)
bsa_b_gemerkt:
	addq.w	#1,d4
bsa_b_nichts:
	addq.l	#2,a1
	addq.w	#1,d1
bsa_b_test:
	dbf	d3,bsa_b_zeile
bsa_weiter:
	addq.l	#8,a0
	bra	bsa_lauf
bsa_fertig:
	move.w	d4,bb_anzahl
	bsr	Plaetze_zeigen
bsa_raus:
	move.w	d4,d0
	movem.l	(sp)+,d1-d7/a0-a5
	rts

; Platz der Zeile d1, wenn dort die Farbe d2 ersetzt wird:
; d0 = Platz - BER_ERSTE, sonst N.  Veraendert nur d0 und a5.
bsa_platz:
	moveq	#-1,d0
	cmp.w	#SCRH,d1
	bcc.b	bsp_raus
	move.w	d1,d0
	add.w	d0,d0
	lea	Zb_tab,a5
	move.w	0(a5,d0.w),d0
	ror.w	#8,d0			; Farbe unten, Platz oben
	cmp.b	d2,d0
	bne.b	bsp_keiner		; Zeile gehoert einem anderen Verlauf
	lsr.w	#8,d0
	sub.w	#BER_ERSTE,d0
	rts
bsp_keiner:
	moveq	#-1,d0
bsp_raus:
	rts

; ***************************************************************************
; Bereiche_schritt -- ein Schritt der Blende fuer die vorgemerkten Plaetze.
;   IN : d6.w = Stufe (wie Dim_colours).  Alle Register bleiben.
; ***************************************************************************
Bereiche_schritt:
	movem.l	d0-d7/a0-a5,-(sp)
	move.w	bb_anzahl,d7
	beq.b	bss_raus
	subq.w	#1,d7			; Dim_colours zaehlt mit dbra
	lea	Bb_von,a0
	lea	Bb_ziel,a1
	lea	Bb_stufe,a2
	jsr	Dim_colours
	lea	Bb_platz,a0
	lea	Slot_ist,a1
bss_lauf:
	move.w	(a0)+,d0
	add.w	d0,d0
	move.w	(a2)+,0(a1,d0.w)
	dbf	d7,bss_lauf
	bsr.b	Plaetze_zeigen
bss_raus:
	movem.l	(sp)+,d0-d7/a0-a5
	rts

; ***************************************************************************
; Plaetze_zeigen -- Slot_ist in die Baenke 3-7.  Alle Register bleiben.
; Bereiche_anfang -- alle Plaetze schwarz (Palette_anfang).
; ***************************************************************************
Plaetze_zeigen:
	movem.l	d0-d4/a0-a2,-(sp)
	move.w	#BER_ERSTE,d4
plz_bank:
	lea	Slot_ist-2*BER_ERSTE,a0
	add.w	d4,a0
	add.w	d4,a0
	move.w	d4,d0
	bsr	Bank_setzen		; FADE_SUP.S: 32 Farben ab d0
	add.w	#32,d4
	cmp.w	#BER_ERSTE+BER_ANZAHL,d4
	bcs.b	plz_bank
	movem.l	(sp)+,d0-d4/a0-a2
	rts

Bereiche_anfang:
	movem.l	d0/a0,-(sp)
	lea	Slot_ist,a0
	move.w	#BER_ANZAHL-1,d0
ban_lauf:
	clr.w	(a0)+
	dbf	d0,ban_lauf
	clr.w	bb_anzahl
	move.l	#-1,zb_liste		; Tabelle beim naechsten Mal neu
	movem.l	(sp)+,d0/a0
	rts
	ENDC	; ZIEL_ST

	SECTION	Fast_BSS,bss
	even
	IFND	ZIEL_ST
Zb_tab:		ds.w	SCRH		; je Zeile Verlaufsfarbe<<8 | Platz
zb_liste:	ds.l	1		; Liste, fuer die Zb_tab gilt
zb_von:		ds.w	1		; erste Zeile mit Verlauf (SCRH: keine)
zb_bis:		ds.w	1		; letzte (-1: keine)
bn_muster:	ds.w	PLANES		; je Ebene $FFFF, wo die alte Farbe 0 hat
bn_setzen:	ds.w	PLANES		; je Ebene $FFFF, wo die neue Farbe 1 hat
br_zlaenge:	ds.l	1		; Bereich_rueck: eine Zielzeile in Byte
br_ebenen:	ds.w	1		;  Ebenen des Ziels
br_schritt_e:	ds.w	1		;  von Ebene zu Ebene
br_schritt_b:	ds.w	1		;  von Block zu Block
Slot_ist:	ds.w	BER_ANZAHL	; was in den Plaetzen steht ($0RGB)
Bb_platz:	ds.w	BER_ANZAHL	; vorgemerkt zum Blenden: Platz-BER_ERSTE
Bb_von:		ds.w	BER_ANZAHL
Bb_ziel:	ds.w	BER_ANZAHL
Bb_stufe:	ds.w	BER_ANZAHL
bb_anzahl:	ds.w	1
	ENDC
ras_da:		ds.b	1		; Interrupt aufgesetzt?
	even
ras_anzahl:	ds.w	1		; Schritte in der Liste
ras_zeile:	ds.w	1		; Zeilenzaehler, je Bild ab RASTER_VERSATZ
	even
ras_zeiger:	ds.l	1		; naechster noch nicht ausgefuehrter Schritt
ras_endzeiger:	ds.l	1		; hinter dem letzten Schritt
ras_altvec:	ds.l	1
ras_vblslot:	ds.l	1	; Platz in der VBL-Warteschlange
ras_alttbcr:	ds.b	1
ras_alttbdr:	ds.b	1
ras_altiera:	ds.b	1
ras_altimra:	ds.b	1
	even
	IFD	RASTERPRUEF
rp_zaehler:	ds.w	1		; Bildzaehler des wandernden Pruefbandes
	even
	ENDC
ras_schritte:	ds.b	RS_MAX*RS_SZ
	even
ras_farben:	ds.l	RS_MAX*32	; je Palettenschritt ein Registersatz
	even
	SECTION	Program,code

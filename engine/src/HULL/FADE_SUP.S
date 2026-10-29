; ***************************************************************************
; Unterbau fuer HULL/FADE.S.
;
; FADE.S selbst ist Thalions Datei, unveraendert eingebunden.  Sie ruft vier
; Dinge, die in der nicht freigegebenen Bibliothek standen:
;
;   Set_fade      die Palette setzen oder blenden
;   Wait_4_fade   warten, bis eine laufende Blende fertig ist
;   My_vsync      einen Bildwechsel abwarten
;   Off_screen    Zeiger auf den Zeichenpuffer (.l)
;
; Auf dem Amiga blendet der Copper nebenher: Set_fade traegt den Auftrag ein
; und kehrt sofort zurueck, Wait_4_fade wartet darauf.  Wir haben keinen
; Copper.  Unser Set_fade blendet an Ort und Stelle -- es kehrt erst zurueck,
; wenn die Blende durch ist -- und Wait_4_fade hat darum nichts zu tun.
;
; Fuer FADE.S ist das nicht zu unterscheiden: es ruft Set_fade und danach
; Wait_4_fade, und die Reihenfolge stimmt in beiden Welten.
; ***************************************************************************

; So viele Zwischenstufen hat eine Blende.  Mehr braucht es nicht: eine
; Amiga-Farbstufe geht von 0 bis 15, nach fuenfzehn Schritten ist auch der
; groesste Abstand ueberbrueckt.  Sechzehn Bilder sind rund ein Drittel
; Sekunde -- so lang dauert die Blende im Original.
FADE_STUFEN = 15

; ***************************************************************************
; Set_fade -- read a raster list, set or fade the colour banks.
;   IN : d0.w = kind (Set_new, Fade_out, Start_fade_in), d1.w = first
;        screen line (-1: all), d2.w = last screen line, a0 = raster list
;        (not for Fade_out).  Returns when the fade is done.
;   All registers are preserved.
;
; **Eine Farbbank je Platz in der Rasterliste** (Erkenntnis 264): die erste
; R_palette der Liste liegt in Bank 2, die zweite in Bank 0, die dritte in
; Bank 1 (Platzbank).  Farbbank (LIBRARY.S) rechnet mit derselben Tabelle.
; Die Bank eines Punkts haengt so nur an seiner Zeile, nicht daran, was
; gerade in einer Bank steht: vorher legte Fade_out_bottom Main_pal nach
; Bank 0, das naechste Modul zeichnete die Portraitleiste hinein, und
; Fade_in_bottom setzte Bank 0 auf die Bildpalette -- die Leiste nahm deren
; Farben an (Savestate des Nutzers, 2026-10-01).
;
; Gesetzt oder geblendet werden die Plaetze, deren R_palette im Bereich d1..d2
; beginnt, wie bei Thalion: Fade_in_bottom und Fade_out_bottom (ab Middle_Y)
; lassen die Leiste oben stehen, Fade_*_all (ab 0) nehmen sie mit.
; ***************************************************************************
Set_fade:
	movem.l	d0-d7/a0-a3/a5,-(sp)
	; **a5 selbst laden** (Erkenntnis 177).  Thalions ShowPicTxt_ModInit
	; ruft Fade_in_bottom mit a5 = Current_event_data.
	lea	vars,a5
	move.w	d0,d5			; Art retten

; **Beim Abblenden darf a0 nicht angefasst werden.**  Fade_out_bottom und
; Fade_out_all setzen es vor dem Aufruf gar nicht -- sie blenden von dem weg,
; was gerade gesetzt ist.  Welche Plaetze in den Bereich fallen, sagt dann
; die zuletzt gesetzte Liste (Letzte_RL), wovon geblendet wird, Bank_ist.
	cmp.w	#Fade_out,d5
	bne.b	sf_neue_liste
	move.l	Letzte_RL,d3
	beq	sf_raus			; noch nie etwas gesetzt
	move.l	d3,a0
	bra.b	sf_sammeln
sf_neue_liste:
	move.l	a0,Letzte_RL

	; ---- Plaetze im Bereich sammeln: Bit in d7, Palette nach Sf_pal ----
sf_sammeln:
	moveq	#0,d3			; Platz
	moveq	#0,d7			; Maske
	lea	Sf_pal,a1
sf_lauf:
	move.b	(a0),d4			; Kennbyte
	cmp.b	#RL_END,d4
	beq.b	sf_gesammelt
	cmp.b	#RL_PAL,d4
	bne.b	sf_range
	cmp.w	#PLAETZE,d3
	bcc.b	sf_gesammelt		; mehr Plaetze hat keine Liste Thalions
	moveq	#0,d4
	move.b	1(a0),d4		; Zeile
	cmp.w	d1,d4			; vor dem Bereich ?
	blt.b	sf_weiter
	cmp.w	d2,d4			; dahinter ?
	bgt.b	sf_weiter
	bset	d3,d7
	move.w	d3,d4
	lsl.w	#2,d4
	move.l	2(a0),0(a1,d4.w)
sf_weiter:
	addq.w	#1,d3
	addq.l	#6,a0
	bra.b	sf_lauf
sf_range:
	addq.l	#8,a0			; R_range: Bereiche_sammeln, unten
	bra.b	sf_lauf
sf_gesammelt:
	; Die Verlaeufe (R_range) setzen oder zum Blenden vormerken, nach
	; Thalions Regeln (RASTER.S).  Die Liste steht in Letzte_RL, auch beim
	; Abblenden.  The ST keeps the gradients flat: its Bereiche_sammeln
	; gives d0 = 0 (ST_LIB.S), so only the palettes count there.
	move.l	Letzte_RL,a0
	bsr	Bereiche_sammeln	; d0 = zu blendende Plaetze
	tst.w	d7
	bne.b	sf_paletten
	tst.w	d0
	beq	sf_raus			; weder Palette noch Verlauf im Bereich
	cmp.w	#Set_new,d5
	beq	sf_raus
	bra.b	sf_blende
sf_paletten:
	cmp.w	#Set_new,d5
	bne.b	sf_blende

	; ---- unmittelbar setzen ----
	moveq	#0,d3
sf_neu:
	btst	d3,d7
	beq.b	sf_neu_weiter
	move.w	d3,d4
	lsl.w	#2,d4
	move.l	0(a1,d4.w),a0
	move.w	d3,d0
	bsr	Platz_setzen
sf_neu_weiter:
	addq.w	#1,d3
	cmp.w	#PLAETZE,d3
	bcs.b	sf_neu
	bra	sf_raus

; Blenden.  Dim_colours ist Thalions Code und bewegt jede Farbstufe um
; hoechstens d6 Schritte auf das Ziel zu.  Laesst man d6 von 0 auf 15
; wachsen, ergibt das die ganze Blende -- ohne dass die Zwischenstufen
; irgendwo zurueckgeschrieben werden muessten.  Alle Plaetze des Bereichs
; gehen im selben Bild einen Schritt.
;
; Die Ausgangspalette muss dafuer stehenbleiben, und Bank_ist tut das nicht:
; Platz_setzen schreibt sie bei jedem Schritt neu.  Also einmal wegkopieren:
; beim Abblenden die laufende Palette, beim Einblenden das Ziel.
sf_blende:
	st	Blende_laeuft		; Drogen_farben pauses, as AM2_CPU does
	move.w	d7,a3			; Maske, d7 braucht Dim_colours
	moveq	#0,d3
sf_von:
	btst	d3,d7
	beq.b	sf_von_weiter
	move.w	d3,d4
	lsl.w	#2,d4
	move.l	0(a1,d4.w),a0		; Ziel der Liste
	cmp.w	#Fade_out,d5
	bne.b	sf_von_kopie
	lea	Bank_ist,a0		; laufende Palette des Platzes
	move.w	d3,d4
	lsl.w	#6,d4
	add.w	d4,a0
sf_von_kopie:
	lea	Fade_von,a2
	move.w	d3,d4
	lsl.w	#6,d4
	add.w	d4,a2
	moveq	#31,d0
sf_kopie:
	move.w	(a0)+,(a2)+
	dbf	d0,sf_kopie
sf_von_weiter:
	addq.w	#1,d3
	cmp.w	#PLAETZE,d3
	bcs.b	sf_von

	moveq	#0,d6
sf_schritt:
	moveq	#0,d3
sf_platz:
	move.w	a3,d4
	btst	d3,d4
	beq.b	sf_platz_weiter
	lea	Fade_von,a1
	move.w	d3,d4
	lsl.w	#6,d4
	add.w	d4,a1
	cmp.w	#Fade_out,d5
	bne.b	sf_ein
	move.l	a1,a0			; von der laufenden Palette
	lea	Schwarz,a1		; nach Schwarz
	bra.b	sf_dim
sf_ein:
	lea	Schwarz,a0		; von Schwarz auf die Palette der Liste
sf_dim:
	move.w	#31,d7			; Dim_colours zaehlt mit dbra
	lea	Fade_work,a2
	jsr	Dim_colours
	lea	Fade_work,a0
	move.w	d3,d0
	bsr	Platz_setzen
sf_platz_weiter:
	addq.w	#1,d3
	cmp.w	#PLAETZE,d3
	bcs.b	sf_platz
	bsr	Bereiche_schritt	; die Verlaeufe im selben Bild (ST: none)
	bsr	My_vsync
	addq.w	#1,d6
	cmp.w	#FADE_STUFEN,d6
	bls.b	sf_schritt
sf_raus:
	sf	Blende_laeuft
	movem.l	(sp)+,d0-d7/a0-a3/a5
	rts

; Welcher Platz der Rasterliste in welcher Farbbank liegt (Farbnummer der
; ersten Farbe).  Der erste ist bei Thalion immer Main_pal, oben die
; Portraitleiste: Bank 2, wie vor Erkenntnis 264.  Der zweite ist die
; Karte, das Bild, das Inventar: Bank 0, dort zeichnet auch, wer ohne
; Rasterliste zeichnet.  Der dritte gibt es nur im Kampf (Tactic_pal).
Platzbank:
	dc.w	MAIN_BANK,0,32

; ***************************************************************************
; Wait_4_fade -- in the original, waiting for the copper.  Our Set_fade
; is done when it returns; nothing is left to do here.
;   All registers are preserved.
; ***************************************************************************
Wait_4_fade:
	rts

; ***************************************************************************
; My_vsync -- ein Bild abwarten.  **Rettet alle Register.**
;
; Das ist sein Vertrag, nicht unsere Vorsicht: sein Delay (HULL/VARIOUS.S)
; zaehlt in d0 und ruft dazwischen My_vsync.  XBIOS darf d0-d2/a0-a2
; ueberschreiben, und Vsync hinterlaesst dort den Bildzaehler -- d0 faengt
; dann jedes Bild neu an, und Delay kehrt nie zurueck.  Am Savestate
; nachgewiesen: Meldung "Kann nicht bereit gemacht werden." -> Display_text
; -> Delay 10 -> Stillstand (Erkenntnis 178).
; ***************************************************************************
My_vsync:
	movem.l	d0-d2/a0-a2,-(sp)
	move.w	#Vsync,-(sp)
	Xbios
	addq.l	#2,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts

	SECTION	Fast_BSS,bss
Blende_laeuft:	ds.b	1		; Set_fade is fading (Drogen_farben pauses)
	even
	SECTION	Program,code

; Amiga-Stufe 0..15 -> VIDEL-Byte.  Gleiche Werte wie videl_component() im
; Konverter: min(63, round(n*63/15)) << 2.  Bank_setzen and Drogen_farben
; (FALCON_LIB.S) and Amiga_nach_videl (RASTER.S, assembled on both
; machines) take it.
Vid_stufe:
	dc.b	0,16,32,52,68,84,100,116
	dc.b	136,152,168,184,200,220,236,252
	even

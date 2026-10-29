; ===========================================================================
; WORDS_SUP.S -- Unterbau fuer Thalions HULL/WORDS.S.
;
; **Put_text_line** setzt eine Zeile; Thalions WORDS.S ruft es, aber es steht in
; der nicht freigegebenen Bibliothek.  Bis 2026-09-25 lag es in unserer
; src/HULL/WORDS.S neben dem Nachbau von Process_text und Display_text; der
; ist geloescht, und die Datei mit ihm.
;
; **Texte der Bibliothek.**  Thalions Code liest sie ueber feste Marken:
;
;     lea.l Prompts,a0 / jsr Do_text          ; CONTROLS.S, Do_prompt
;     lea.l Race_names,a0 / jsr Find_small_text   ; INVENTOR.S
;     lea.l Age_nr,a0 / jsr DecL_convert      ; schreibt in Age_txt hinein
;
; Die Tabellen muessen also *an* den Marken liegen, nicht hinter Zeigern.
; Im Original stehen sie in AM2_CPU.  Die Fassung 1.20 traegt sie in
; Text.amb, und Lade_texte holt die ganze Datei zur Laufzeit nach Textdaten
; (Leitziel 2).  Wo darin welcher Name liegt, schreibt tools/textmarken.py
; beim Bau (build/textmarken.i, Aufbau der Datei dort): Age_nr - Age_txt
; haengt von der Sprache ab, Thalion rechnet aber mit zwei festen Marken.
; ===========================================================================

	SECTION	Fast_DATA,data
	even
; Zeigerliste: MAP/MAP.S holt "move.l 0(a0,d0.w),a0" je Welt.
World_map_names:	dc.l	Weltname_1,Weltname_2,Weltname_3

	SECTION	Fast_BSS,bss
ltx_geladen:	ds.b	1
; Rune font on (~RUN1~) or off (~NORM~).  Thalion's Display_text clears it
; before every text; it holds across lines, as in AM2_CPU (9:$A1AD).
Rune_flag:	ds.b	1
	even
	SECTION	Program,code

; ***************************************************************************
; Lade_texte -- Text.amb ganz nach Textdaten (build/textmarken.i).
;
; DEVIATION (goal 2), docs/17-deviations.md D5: the positions inside the
; file are fixed at build time; at run time only the length is checked.
;
; Nur wenn die entpackte Laenge die ist, fuer die gebaut wurde; eine andere
; Fassung hat andere Versaetze.  Sonst bleibt Textdaten null, und jeder Name
; ist ein leerer Text (Find_small_text findet Nullen, Do_prompt zaehlt 0
; Texte).  Einmal; auch ein Fehlschlag wird nicht wiederholt.  Alle
; Register bleiben.
; ***************************************************************************
Lade_texte:
	movem.l	d0-d3/a0-a1,-(sp)
	tst.b	ltx_geladen
	bne.b	ltx_out
	st	ltx_geladen
	moveq	#Text_file,d0
	jsr	Load_file		; JH-Huelle und LOB, ausgepackt
	tst.l	d0
	beq.b	ltx_out
	move.w	d0,d3			; d3 = Handle
	jsr	Get_memory_length	; genau die entpackte Groesse
	cmp.l	#TEXT_LAENGE,d0
	bne.b	ltx_frei
	moveq	#0,d0
	move.w	d3,d0
	jsr	Block_adresse
	move.l	d0,a0
	lea	Textdaten,a1
	move.w	#TEXT_LAENGE-1,d1
ltx_kop:	move.b	(a0)+,(a1)+
	dbf	d1,ltx_kop
ltx_frei:
	moveq	#0,d0
	move.w	d3,d0
	jsr	Free_memory
ltx_out:
	movem.l	(sp)+,d0-d3/a0-a1
	rts

; ***************************************************************************
; Put_text_line -- print one line of text at a position.
;   IN : d0.w = x, d1.w = y, a0 = text, ending with a zero byte.  The ink
;        is not a parameter but the variable Ink_colour, as in the original.
;   OUT: a0 = behind the terminating zero
;   All other registers are preserved.
;
; **Zurueck kommt a0 hinter der Endnull**, alle anderen Register bleiben.
; Das verlangt Thalions Refresh_text_window, das Zeile um Zeile ausgibt, ohne
; a0 neu zu laden:
;
;     .Loop2: move.b (a0)+,d6 / ... / jsr Put_text_line / addq.w #7,d1
;
; Mit erhaltenem a0 druckte jede Zeile denselben Text, um ein Zeichen
; versetzt, und ein Buchstabe wurde zur Tinte (Erkenntnis 173).
;
; **Befehle im Text wertet diese Routine aus**, nicht Process_text.  Thalions
; Process_text laesst "~INK 22~" und Verwandte in der Zeile stehen (Add_line
; kopiert sie mit, beim Umbruch zaehlen sie nicht zur Breite), und sein
; Scan_line_for_ink liest daraus nur die Anfangstinte.  Also: alles zwischen
; zwei Command_char ueberspringen, "INK nn" setzt Ink_colour wie dort
; (zwei Ziffern, "and.w #Pal_size-1").  Unbekannte Befehle -- solange
; HLC_table leer ist auch ~LEAD~ und Verwandte -- fallen still weg.  "$" ist
; ein geschuetztes Leerzeichen: beim Umbruch ein Zeichen, im Bild leer
; (Erkenntnis 174).
;
; Die drei Register werden sofort in a5-relative Plaetze uebernommen; ab da
; laeuft nichts mehr ueber Registergrenzen.  Der Grund steht bei Display_2D_map.
;
; **a5 holt sich die Routine selbst** (Erkenntnis 177).  Sein Display_portrait
; ruft sie ueber Print_centered_string mit a5 auf einem lokalen Rahmen im
; Stapel; mit dem lasen p_font und txt_y Muell, und Put_char_at schrieb
; nach $567018.  a5 gehoert nicht zu seinem Bibliotheksvertrag.
;
; Je Zeichen: ASCII-32 in der Umsetzungstabelle nachschlagen.  $FF heisst
; "kein Zeichen" -- Leerzeichen und alles Undarstellbare landen dort und
; erzeugen nur Vorschub.  Sonst zeigt der Wert auf das Muster, fuenf Zeilen
; zu acht Pixeln.  Vorschub ist konstant 6, die Schrift ist nicht
; proportional; nachgemessen am Amiga-Speicherauszug.
; ***************************************************************************
Put_text_line:
	movem.l	d0-d7/a0-a5,-(sp)
	lea	vars,a5			; unser Variablenblock, nicht seiner
	move.w	d0,txt_x(a5)
	move.w	d1,txt_y(a5)
	move.l	a0,p_txt(a5)
	move.l	p_font(a5),a4
	move.w	4(a4),d7		; Vorschub
	move.w	2(a4),d6		; Zeilen je Zeichen
pt_loop:
	move.l	p_txt(a5),a0
	moveq	#0,d0
	move.b	(a0)+,d0
	beq	pt_out
	move.l	a0,p_txt(a5)
	cmp.b	#Command_char,d0	; Befehl ?
	beq	pt_befehl
	cmp.b	#"$",d0			; geschuetztes Leerzeichen ?
	bne.b	pt_zeichen
	moveq	#" ",d0
pt_zeichen:
	sub.b	#32,d0
	bcs.b	pt_next			; unter dem Leerzeichen: nichts
	lea	FONT_TAB(a4),a0
	tst.b	Rune_flag		; runes: the other table, same glyphs
	beq.b	pt_tabelle
	lea	Runentabelle,a0
pt_tabelle:
	move.b	(a0,d0.w),d0
	and.w	#$ff,d0
	cmp.w	#FONT_NONE,d0
	beq.b	pt_next
	mulu.w	d6,d0
	lea	FONT_GLY(a4),a1
	add.l	d0,a1			; a1 = Muster des Zeichens
	bsr	Put_char
pt_next:
	move.w	txt_x(a5),d0
	add.w	d7,d0
	move.w	d0,txt_x(a5)
	bra	pt_loop
; ---- Befehl: a0 steht hinter dem ersten Command_char ----
; Jede Endnull unterwegs beendet die Zeile; a0 steht dann schon dahinter.
pt_befehl:
	moveq	#0,d1			; vier Zeichen Befehlswort
	moveq	#4-1,d3
pt_bwort:
	move.b	(a0)+,d2
	beq.b	pt_out
	lsl.l	#8,d1
	move.b	d2,d1
	dbf	d3,pt_bwort
	; ~RUN1~ and ~NORM~ switch the font, as in AM2_CPU (0:$23C80); in
	; Super_chicken mode the runes stay readable (0:$23C94).
	cmp.l	#"RUN1",d1
	bne.b	pt_norm
	cmp.w	#Super_chicken,Travel_mode
	beq.b	pt_bende
	st	Rune_flag
	bra.b	pt_bende
pt_norm:
	cmp.l	#"NORM",d1
	bne.b	pt_ink
	sf	Rune_flag
	bra.b	pt_bende
pt_ink:
	cmp.l	#Ink_command,d1		; "INK " ?
	bne.b	pt_bende
	moveq	#0,d1			; zwei Ziffern -> Tinte
	move.b	(a0)+,d1
	beq.b	pt_out
	sub.b	#"0",d1
	mulu.w	#10,d1
	move.b	(a0)+,d2
	beq.b	pt_out
	sub.b	#"0",d2
	add.b	d2,d1
	and.w	#Pal_size-1,d1
	move.w	d1,Ink_colour
pt_bende:
	move.b	(a0)+,d2		; bis hinter das schliessende Command_char
	beq.b	pt_out
	cmp.b	#Command_char,d2
	bne.b	pt_bende
	move.l	a0,p_txt(a5)
	bra	pt_loop
pt_out:
	move.l	a0,8*4(sp)		; a0 hinter der Endnull zurueckgeben
	movem.l	(sp)+,d0-d7/a0-a5
	rts

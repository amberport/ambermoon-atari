; intro_zoom_daten.i -- Daten von INTRO_ZOOM.S, im Datenabschnitt des Intros.

; Zm_spreiz -- je Farbe (Index Farbe * 4) ihre Ebenenbits, eine Ebene je
; Byte: Ebene 0 im obersten.  Acht hineingeschobene Punkte ergeben vier
; Ebenenbytes (Zm_falten).
Zm_spreiz:
	dc.l	$00000000,$01000000,$00010000,$01010000
	dc.l	$00000100,$01000100,$00010100,$01010100
	dc.l	$00000001,$01000001,$00010001,$01010001
	dc.l	$00000101,$01000101,$00010101,$01010101

	IFD	ZOOM_PRUEF
Text_zp_kopf:		dc.b	13,10,"Zoom, Thalions Weg gegen unseren: ",0
Text_zp_weg_b:		dc.b	" Aufrufe, davon Weg $2060: ",0
Text_zp_abweichend:	dc.b	", abweichend: ",0
Text_zp_ungeprueft:	dc.b	", ungeprueft: ",0
Text_zp_erster:		dc.b	13,10,"  erster: x y Spalten Zeilen, Ziel b h, Quelle b h,"
			dc.b	" Maske, Aufruf, Langworte: ",0
	ENDC
	even

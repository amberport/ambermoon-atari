; intro_zoom_bss.i -- Variablen von INTRO_ZOOM.S, im BSS des Intros.

Zm_ziel:		ds.l	1		; Schirmzeile der laufenden Zielzeile
Zm_zeilenschritt:	ds.l	1		; to the next line (Amiga or target)
Zm_zeile:		ds.l	1		; gewandelte Quellzeile, [0] = Farbe 0
Zm_bild:		ds.l	1		; gewandeltes Quellbild im Lager oder 0
Zm_lager_frei:		ds.l	1		; erstes freies Byte in Zm_lager
Zm_bild_schritt:	ds.w	1		; seine Bytes je Zeile
Zm_tab:			ds.l	1		; naechster Zeilenschritt
Zm_worte:		ds.w	1		; Zielworte je Zeile
Zm_qworte:		ds.w	1		; Quellworte je Ebene
Zm_ebene:		ds.w	1		; Abstand der Quellebenen
Zm_qzeile_bytes:	ds.w	1		; Abstand der Quellzeilen
Zm_qz:			ds.w	1		; laufende Quellzeile
Zm_gebaut:		ds.w	1		; Quellzeile in Zm_linie
Zm_rest:		ds.w	1		; Zielzeilen - 1
Zm_rand:		ds.w	ZM_MAXWORTE	; Rechteck je Zielwort
Zm_karte:		ds.w	ZM_MAXWORTE*16	; je Zielpunkt Quellspalte + 1
Zm_linie:		ds.w	ZM_MAXWORTE*5	; je Zielwort 4 Ebenen, Maske
Zm_mit_maske:		ds.b	1
Zm_im_ziel:		ds.b	1		; the screen is in the target format
			even
Zm_chunky:		ds.b	ZM_MAXBREITE+16+2 ; [0] = Farbe 0, ab 1 die Quellzeile
			even
Zm_plaetze:		ds.b	ZM_PLAETZE*ZL_LAENGE
Zm_lager:		ds.b	ZM_LAGER
			IFD	ZOOM_PRUEF
Zp_anzahl:		ds.l	1
Zp_weg_b:		ds.l	1
Zp_abweichend:		ds.l	1
Zp_ungeprueft:		ds.l	1
Zp_erster:		ds.w	10
			ds.l	1
Zp_vorher:		ds.b	ZP_MAX
Zp_genau:		ds.b	ZP_MAX
			ENDC

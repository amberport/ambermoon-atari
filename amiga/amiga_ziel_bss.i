; amiga_ziel_bss.i -- Variablen von AMIGA_ZIEL.S, im BSS des Einbinders.
	IFD	ZIEL_SCHIRME
Direkt_von:		ds.l	1	; Bereich aller Amiga-Schirme der Tabelle
Direkt_bis:		ds.l	1	; 0: keine Schirme direkt
Bl_kanal:		ds.l	4	; A, B, C, D: Eintrag oder 0
Bl_ziel_d:		ds.l	1	; D im Ziel
Bl_ziel_d_ende:		ds.l	1	; BLTDPT danach, Amiga-Adresse
Bl_ziel_schritt:	ds.l	1	; D von Zeile zu Zeile (Amiga)
Bl_ziel_dmod:		ds.w	1	; D von Zeile zu Zeile (Ziel)
Bl_d_zeilen:		ds.w	2	; erste Zeile, Zeilen von D
Bl_d_bereiche:		ds.w	2*SCH_MAX	; the same per screen (Bl_umlenken)
Anzeige_ist_direkt:	ds.b	1
Anzeige_gehalten:	ds.b	1	; Display_hold: nothing is converted
Bl_ziel_c:		ds.b	1	; the blit reads C at D's place
Bl_ziel_vorn:		ds.b	1	; its first word stays (Bl_erstes_wort)
	even
	IFD	AMIGA_MESSEN
Anz_umgesetzt:		ds.l	1	; whole pictures converted (fallback)
Anz_gerollt:		ds.l	1	; bands converted (fallback)
Bl_fenster:		ds.l	1	; Blits ueber den Zwischenspeicher
Bl_ziel:		ds.l	1	; Blits direkt ins Ziel
Zl_geholt:		ds.l	1	; Zeilen aus dem Ziel geholt
Zl_gebracht:		ds.l	1	; Zeilen nach Blits ins Ziel gebracht
	ENDC
	IFD	BLIT_PRUEF
Pz_weg:			ds.l	1
Bl_ziel_geprueft:	ds.l	1
Pz_zeilen:		ds.w	2
Pz_reg:			ds.b	BL_REG_LAENGE
Pz_reg_soll:		ds.b	BL_REG_LAENGE
	even
Pz_vorher:		ds.b	ZIEL_SCHIRM
Pz_soll:		ds.b	ZIEL_SCHIRM
	ENDC
Sch_gueltig_speicher:	ds.b	SCH_MAX*FALCON_HOEHE
Ziel_speicher:		ds.b	SCH_MAX*(2*ZIEL_RAND+ZIEL_SCHIRM+FALCON_LUECKE)+256
	ENDC

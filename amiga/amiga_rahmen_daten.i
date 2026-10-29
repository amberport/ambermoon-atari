; amiga_rahmen_daten.i -- Daten der Amiga-Schicht (AMIGA_RAHMEN.S).
; Ohne SECTION: steht im Datenabschnitt dessen, der sie einbindet.
; Thalion ruft den Spieler bei +0, +12, +16 und +24: an jeder Stelle ein rts.
Musik_stumm:
	rept	16
	rts
	endr
Exec_zeiger:
	dc.l	Exec_basis
Vier_nach_acht:
	dc.b	$00,$11,$22,$33,$44,$55,$66,$77,$88,$99,$AA,$BB,$CC,$DD,$EE,$FF
Text_kein_falcon:
	dc.b	"Braucht einen Falcon an RGB oder VGA.",13,10
	dc.b	"Taste druecken.",13,10,0
Text_cursor_aus:
	dc.b	27,'f',0
Text_cursor_an:
	dc.b	27,'e',0
Text_fehlt:
	dc.b	"Thalion rief eine Bibliotheksroutine, die fehlt: -"
Text_fehlt_zahl:
	dc.b	"0000",13,10,"Taste druecken.",13,10,0
Inf_datei:
	dc.b	"AMBFILES\AMBER.INF",0	; Musik_mischen
	even
	include	"mischer_daten.i"	; musik/, the mixer
	include	"amiga_messen_daten.i"
	IFD	AMIGA_MESSEN
Text_mess_zwei:		dc.b	"  Anzeige (VBL der Schicht): ",0
	ENDC
	IFD	STRAHL
	even
St_liste:	dc.l	St_vbl,Text_st_vbl
		dc.l	St_ganz,Text_st_ganz
		dc.l	St_roll,Text_st_roll
		dc.l	St_sprung,Text_st_sprung
		dc.l	St_farben,Text_st_farben
		dc.l	St_vfc,Text_st_vfc
		dc.l	St_warten,Text_st_warten
		dc.l	0
Text_st_vbl:	dc.b	"VBL der Schicht (ganzes Bild)",0
Text_st_ganz:	dc.b	"Ganzbild auf den verdeckten Schirm",0
Text_st_roll:	dc.b	"Rollzeilen auf den gezeigten Schirm",0
Text_st_sprung:	dc.b	"Rollband uebersprungen, Strahl dort",0
Text_st_farben:	dc.b	"Farben geschrieben (Bereich: VFC im Bild; im Bild: Zaehler im Schirm, beides vorher)",0
Text_st_vfc:	dc.b	"Rollband abgelehnt, Strahl vor dem Bild (VFC)",0
Text_st_warten:	dc.b	"Copperliste wartet auf BPLCON0 (Ebenenzahl)",0
Text_tk_kopf:	dc.b	13,10,"Videl beim Eintritt in unseren VBL (Z = ab Zeile, je 16):",0
Text_tk_umg:	dc.b	13,10,"  nach Umschalten:",0
Text_tk_ohne:	dc.b	13,10,"  ohne Umschalten:",0
Text_tk_neu:	dc.b	"neu ",0
Text_tk_alt:	dc.b	"alt ",0
Text_tk_anders:	dc.b	" anderswo:",0
Text_tk_bsp:	dc.b	13,10,"  erste nach Umschalten, Byte ab neuem Schirm:",0
Text_tk_anfang:	dc.b	"Anfang",0
Text_tk_ende:	dc.b	"Ende",0
Text_tk_dahinter: dc.b	"dahinter",0
Text_tk_vfc:	dc.b	13,10,"  VFC beim Eintritt (Halbzeilen, H = ab, je 32):",0
Text_tk_vft:	dc.b	13,10,"  VFT ",0
Text_tk_vdb:	dc.b	" VDB ",0
Text_tk_vde:	dc.b	" VDE ",0
	even
Tk_namen:	dc.l	Text_tk_anfang,Text_tk_ende,Text_tk_dahinter
	ENDC
	even

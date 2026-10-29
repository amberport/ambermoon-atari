; amiga_messen_daten.i -- Texte von AMIGA_MESSEN.S, im Datenabschnitt des
; Einbinders.
	IFD	AMIGA_MESSEN
; Name der Messdatei: <Programmname>.MES, schreibt der Bau (bauen in
; tools/fantasy_bauen.sh, tools/amiga_bauen.sh); die Textdatei heisst .TXT.
Mess_datei:
	include	"mess_name.i"
	even
Text_mess_kopf:		dc.b	13,10,"Messung (Timer A, 1010 je Sekunde), Proben: ",0
Text_mess_blits:	dc.b	13,10,"Amiga_blit: ",0
Text_mess_sonst:	dc.b	"  Thalion und sonst: ",0
Text_mess_vbls:		dc.b	13,10,"VBLs (echte Laufzeit): ",0
Text_mess_hz:		dc.b	", 200-Hz-Takte: ",0
Text_mess_frequenz:	dc.b	13,10,"Bildfrequenz (Hz): ",0
Text_mess_anzahl:	dc.b	13,10,"Amiga-Blits: ",0
Text_mess_schnell:	dc.b	", schnell: ",0
	IFD	ZIEL_SCHIRME
Text_mess_ziel:		dc.b	13,10,"Blits direkt ins Ziel: ",0
Text_mess_fenster:	dc.b	", ueber den Amiga-Schirm: ",0
Text_mess_geholt:	dc.b	13,10,"Zeilen aus dem Ziel geholt: ",0
Text_mess_gebracht:	dc.b	", nach Blits gebracht: ",0
Text_mess_umgesetzt:	dc.b	13,10,"Converted (fallback): pictures ",0
Text_mess_gerollt:	dc.b	", bands ",0
	IFD	BLIT_PRUEF
Text_mess_zgeprueft:	dc.b	13,10,"Direkt ins Ziel geprueft: ",0
	ENDC
	ENDC
	IFD	BLIT_PRUEF
Text_mess_abweichung:	dc.b	13,10,"Pruefung schnell gegen genau, abweichend: ",0
Text_mess_ungeprueft:	dc.b	", ungeprueft: ",0
	ENDC
Text_mess_faecher:	dc.b	13,10,"Vollste Faecher (Versatz ab start):",13,10,0
Text_mess_datei_ok:	dc.b	13,10,"Datei geschrieben: ",0
Text_mess_datei_fehler:	dc.b	13,10,"Datei NICHT geschrieben.",0
Text_mess_ende:		dc.b	13,10,"Taste druecken.",13,10,0
	IFD	STRAHL
Text_st_kopf:		dc.b	13,10,"Strahl (Videl-Zaehler vor/nach dem Schreiben):",0
Text_st_aufrufe:	dc.b	": ",0
Text_st_treffer:	dc.b	" Mal, Strahl im Bereich ",0
Text_st_imbild:		dc.b	", danach im Bild ",0
	ENDC
	ENDC
	even

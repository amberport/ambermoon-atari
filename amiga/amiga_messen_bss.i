; amiga_messen_bss.i -- Variablen von AMIGA_MESSEN.S, im BSS des Einbinders.
	IFD	AMIGA_MESSEN
Mess_alter_vektor:	ds.l	1
Mess_summe:		ds.l	3	; Blits, Anzeige, sonst
Mess_fremd:		ds.l	1	; PC ausserhalb der Faecher
Mess_gesamt:		ds.l	1
Mess_sekunde:		ds.w	3	; laufende Sekunde, Arten wie oben
Mess_takt:		ds.w	1
Mess_zeilen:		ds.w	1	; Sekunden im Verlauf
Mess_handle:		ds.w	1
Mess_alt_tacr:		ds.b	1
Mess_alt_iera:		ds.b	1
Mess_alt_imra:		ds.b	1
Mess_laeuft:		ds.b	1	; Timer A ist unserer (Mess_starten)
	even
Mess_vbls:		ds.l	1	; der VBL des Einbinders zaehlt hoch
; Kopf und Zahl hintereinander: ein Fwrite
Mess_vbl_kopf:		ds.l	1	; "VBLS"
Mess_vbl_zahl:		ds.l	1	; Mess_vbls bei Mess_stoppen
Mess_hz_kopf:		ds.l	1	; "H200", gleich dahinter geschrieben
Mess_hz_zahl:		ds.l	1	; _hz_200-Takte von Mess_starten bis Mess_stoppen
Mess_hz_start:		ds.l	1
; Kopf und Faecher hintereinander: ein Fwrite
Mess_kopf:		ds.l	1	; "AMES"
Mess_kopf_takt:		ds.w	1
Mess_kopf_fach:		ds.w	1
Mess_kopf_faecher:	ds.w	1
Mess_kopf_sekunden:	ds.w	1
Mess_kopf_summen:	ds.l	3
Mess_kopf_fremd:	ds.l	1
Mess_kopf_blits:	ds.w	4	; Bl_anzahl, Bl_schnell, Bl_fremd, K2_fremd
Mess_faecher:		ds.l	MESS_FAECHER
Mess_verlauf:		ds.w	3*MESS_SEKUNDEN
Mess_text:		ds.b	4096
Mess_txt_name:		ds.b	16	; Mess_datei mit .TXT
	IFD	BLIT_STATISTIK
Bs_aktuell:		ds.l	1	; Eintrag des laufenden Blits oder 0
; Kopf und Tabelle hintereinander: ein Fwrite
Bs_kopf:		ds.l	1	; "BSTA"
Bs_eintraege:		ds.w	1
Bs_ueberlauf:		ds.w	1
Bs_tabelle:		ds.b	BS_MAX*BS_LAENGE
	ENDC
	IFD	MESS_ENDE
			ds.b	2048
Mess_stapel_oben:
	ENDC
	ENDC

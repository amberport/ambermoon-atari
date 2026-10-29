; amiga_notaus_bss.i -- Variablen von AMIGA_NOTAUS.S, im BSS des Einbinders.
Notaus_alt:		ds.l	1	; etv_term vor uns
Absturz_alt:		ds.l	ABSTURZ_VEKTOREN ; Vektoren 2-8 vor uns
Absturz_ziel:		ds.l	1	; Halter von TOS fuer diesen Absturz
Absturz_nr:		ds.w	1	; Versatz in Absturz_alt
	IFD	ABSTURZTEST
Absturz_zaehler:	ds.l	1
	ENDC
Im_notausgang:		ds.b	1	; gesetzt: Abbau aus etv_term, kein GEMDOS
Ab_modus:		ds.b	1	; Modus, Schirm, Farben umgestellt
Ab_maus:		ds.b	1	; Mausvektor ist unserer
Ab_vbl:			ds.b	1	; VBL (und mehr) ist unserer
Ab_absturz:		ds.b	1	; Absturzvektoren 2-8 sind unsere
	even

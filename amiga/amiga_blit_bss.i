; amiga_blit_bss.i -- Variablen von AMIGA_BLIT.S, im BSS des Einbinders.

; Amiga_blit
Bl_zeilen:		ds.w	1
Bl_breite:		ds.w	1
Bl_rest:		ds.w	1
Bl_afwm:		ds.w	1
Bl_alwm:		ds.w	1
Bl_amod:		ds.w	1
Bl_bmod:		ds.w	1
Bl_cmod:		ds.w	1
Bl_dmod:		ds.w	1
Bl_anzahl:		ds.w	1		; ausgefuehrte Blits
Bl_fremd:		ds.w	1		; nicht unterstuetzte
Bl_schnell:		ds.w	1		; davon auf einem schnellen Weg
			IFD	BLIT_PRUEF
Bl_abweichung:		ds.w	1		; schnell anders als genau
Bl_ungeprueft:		ds.w	1		; Bereich zu gross fuer den Puffer
Pr_worte:		ds.l	1
Pr_weg:			ds.l	1		; der schnelle Weg dieses Blits
Pr_letzt:		ds.w	4		; letzter ungepruefter: CON0/1, SIZE, DMOD
Pr_ziel:		ds.l	1
Pr_reg:			ds.b	BL_REG_LAENGE
Pr_reg_genau:		ds.b	BL_REG_LAENGE
Pr_vorher:		ds.b	PR_MAX
Pr_genau:		ds.b	PR_MAX
			ENDC
Bl_minterm:		ds.b	1
Bl_absteigend:		ds.b	1		; $FF: BLTCON1 DESC
			even
Bl_fest_a:		ds.w	64
Bl_fest_b:		ds.w	64
Bl_fest_c:		ds.w	64

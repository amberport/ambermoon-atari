; amiga_rahmen_bss.i -- Variablen der Amiga-Schicht (AMIGA_RAHMEN.S).
; Ohne SECTION: steht im BSS dessen, der sie einbindet.
Alter_ssp:		ds.l	1
Alter_vbl:		ds.l	1
Alter_level3:		ds.l	1
Alter_trap0:		ds.l	1
Alter_trap8:		ds.l	1
Alter_schirm:		ds.l	1
Alter_mausvektor:	ds.l	1
Kbd_vektoren:		ds.l	1
Falcon_vorn:		ds.l	1
Falcon_hinten:		ds.l	1
Basis_jetzt:		ds.l	1	; zuletzt gesetzte Bildbasis (Basis_setzen)
Basis_vorher:		ds.l	1	; die davor
Vbl_zaehler:		ds.l	1
Sv_rueck:		ds.l	1
Alter_modus:		ds.w	1
Neuer_modus:		ds.w	1
Anzeige_zeilen:		ds.w	1
Anzeige_erste:		ds.w	1
Rueckgabe:		ds.w	1
Bib_fehlt_versatz:	ds.w	1
K2_fremd:		ds.w	1
Lage_f0:		ds.w	1
Lage_h:			ds.w	1
Lage_r0:		ds.w	1
Roll_zeile:		ds.w	1
Liste_wartet:		ds.w	1	; T62: the list waited this often
Teil_anzahl:		ds.w	1
Teil_farben:		ds.w	2*8
Farben_neu:		ds.l	64	; the colours of this VBL (Farben_rechnen)
Farben_alt:		ds.l	64	; what the Videl has
Cpu_ab_68010:		ds.b	1
Amiga_cia_a:		ds.b	1
Zg_dma:			ds.b	1	; Sprites an (DMACON)
Zg_verbunden:		ds.b	1	; Sprite 1 an Sprite 0 gehaengt
Zg_zwei:		ds.b	1	; zweite Punktgruppe im Schirm
	even
Zg_adresse:		ds.l	1	; Falcon: erste Zeile, erste Gruppe
Zg_zeilen:		ds.w	1	; gezeichnete Zeilen, 0: keiner
Zg_worte:		ds.w	5	; Ebenen 0-4 einer Zeile
Zg_hinter:		ds.w	10*ZG_MAX	; je Zeile zwei Gruppen, Ebenen 0-4
Zustand:		ds.b	Z_GROESSE
Zustand_alt:		ds.b	Z_GROESSE
Alte_st_farben:		ds.w	16
Alte_videl_farben:	ds.l	256
Amiga_register:		ds.b	AR_GROESSE
	include	"amiga_blit_bss.i"
	include	"amiga_ziel_bss.i"
	include	"amiga_notaus_bss.i"
	include	"amiga_musik_bss.i"
	even
			ds.b	6*EXEC_EINTRAEGE
Exec_basis:		ds.b	300
			ds.b	6*GFX_EINTRAEGE
Gfx_basis:		ds.b	64
	include	"amiga_messen_bss.i"
	IFD	STRAHL
St_vbl:			ds.b	ST_LAENGE
St_ganz:		ds.b	ST_LAENGE
St_roll:		ds.b	ST_LAENGE
St_sprung:		ds.b	ST_LAENGE	; only ST_AUFRUFE counts
St_farben:		ds.b	ST_LAENGE	; T62: palette written
St_vfc:			ds.b	ST_LAENGE	; T62: only ST_AUFRUFE counts
St_warten:		ds.b	ST_LAENGE	; T62: only ST_AUFRUFE counts
Fs_zaehler:		ds.l	1	; video counter at Farben_schreiben
Tk_vfc:			ds.l	TK_VFC_FAECHER
Fs_vfc:			ds.w	1	; VFC at Farben_schreiben
Tk_vft:			ds.w	1
Tk_vdb:			ds.w	1
Tk_vde:			ds.w	1
St_vbl_schirm:		ds.l	1	; Falcon_vorn beim Eintritt in den VBL
St_roll_zeile:		ds.w	1
St_roll_zeilen:		ds.w	1
Tk_faecher:		ds.l	2*TK_FAECHER	; nach einem Umschalten, ohne
Tk_beispiele:		ds.l	TK_BEISPIELE
Tk_bsp_anzahl:		ds.w	1
Tk_umgeschaltet:	ds.b	1	; der vorige VBL schrieb die Bildbasis
	even
	ENDC
Falcon_speicher:	ds.b	2*FALCON_SCHIRM+FALCON_LUECKE+256

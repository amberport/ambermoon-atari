; ***************************************************************************
; AMIGA_RAHMEN.S -- die Amiga-Schicht unter Thalions Programmen ohne
; Quelltext (Intro, Extro; docs/11-Intro-Extro.md, 4.5 und 5.6).  Ohne
; SECTION: steht im Codeabschnitt dessen, der die Datei einbindet.  Die Daten
; in amiga_rahmen_daten.i, die Variablen in amiga_rahmen_bss.i.
;
; Das Programm liefert `start` (Befehlszeile -> Uebergabe, dann Thalions
; Einsprung) und den Satz `Uebergabe`; alles andere steht hier.
;
; **Thalions Rahmen** (Intro und Extro gleich): Satz in a0 = {Zeiger auf den
; Musikspieler, ein Byte}; exec und graphics oeffnen, dann `trap #0` in den
; Supervisor, dort laeuft alles; am Ende d0 als Ergebnis.
;
; **Die Bibliothek:** Thalions Rahmen ruft exec und graphics (OpenLibrary,
; CloseLibrary, Supervisor, LoadView, WaitTOF) und liest dazu ExecBase aus
; $4.  K1 biegt diese vier Lesestellen auf Exec_zeiger; dahinter stehen zwei
; kleine Sprungtabellen (Bibliothek_anlegen).  Ein anderer Aufruf landet in
; Bib_fehlt und wird am Ende gemeldet.
;
; **Die Hardware:** K1 biegt $DFFxxx auf Amiga_register (auch die Basis
; lea $DFF000,a6) und $BFE001 auf Amiga_cia_a.  Thalion setzt den VBR nicht
; (AttnFlags 0 -> VBR 0) und schreibt seinen VBL nach $6C, das
; Hauptprogramm nach $80 (trap #0).  Unser VBL ($70) springt nach $6C.
;
; **The picture:** Thalion's copper list (COP1LC) names the plane pointers
; and one colour change; BPLCON0, BPL1MOD and DIWSTRT/DIWSTOP name the
; number of planes, the line length and the window.  If any of it changes,
; the VBL converts the whole picture into the hidden Falcon screen and
; switches; otherwise it follows up ROLLZEILEN lines per VBL in the shown
; screen (for Thalion drawing into the shown screen, as in the menu), and
; only where the Videl is not reading (Roll_strahl, T28).  Plane 5 carries
; the colour bank: 1 from the line the copper list waits for.
;
; **Die Blits (K2, I2):** Wo Thalion BLTSIZE schreibt, steht beim Bau ein
; trap #8 (tools/amiga_programm.py).  K2_trap schreibt den Wert und fuehrt
; den Blit mit Amiga_blit aus (amiga/AMIGA_BLIT.S), bevor Thalions Code
; weiterlaeuft; die Abfrage von DMACONR findet den Blitter also immer frei.
;
; **Der Mauszeiger (I3):** Sprite 0 und 1 zeichnet die CPU in den gezeigten
; Schirm (Zeiger_zeichnen).
;
; Music: AMIGA_MUSIK.S loads Thalion's player and song and plays them
; through the music session's mixer (musik/MISCHER.S, E14).
; ***************************************************************************

; ***************************************************************************
; Falcon_pruefen -- Z gesetzt, wenn der Cookie _MCH einen Falcon meldet.
; Nebenbei: Cpu_ab_68010 aus _CPU (Supervisor braucht es).
; ***************************************************************************
Falcon_pruefen:
	move.l	#'_CPU',d0
	bsr.b	Cookie_suchen
	bne.b	.cpu
	cmp.l	#10,d0
	scc	Cpu_ab_68010
.cpu:	move.l	#'_MCH',d0
	bsr.b	Cookie_suchen
	bne.b	.nein
	swap	d0
	cmp.w	#3,d0			; $0003xxxx = Falcon
	rts
.nein:	moveq	#1,d0			; Z aus
	rts

; Cookie_suchen -- d0 = Name -> d0 = Wert, Z gesetzt; sonst Z aus.
Cookie_suchen:
	move.l	$5A0.w,d1
	beq.b	.nein
	move.l	d1,a0
.such:	move.l	(a0),d1
	beq.b	.nein
	cmp.l	d0,d1
	beq.b	.da
	addq.l	#8,a0
	bra.b	.such
.da:	move.l	4(a0),d0
	cmp.b	d0,d0			; Z setzen
	rts
.nein:	moveq	#1,d1			; Z aus
	rts

; ***************************************************************************
; Amiga_einrichten -- Modus, Schirme, Maus, Bibliothek, Vektoren.  Das
; Gegenstueck zum Amiga-Betriebssystem, unter dem Thalions Rahmen startet.
;   Z gesetzt: bereit.  Sonst ein Monitor, den wir nicht bedienen.
;
; Zeilen wie beim Fantasy-Intro: an RGB immer PAL (Nutzer, 2026-10-03:
; Thalion zaehlt VBLs fuer 50 Hz), dort 256 Zeilen (Videl_256), sonst 200;
; an VGA 240 bei 60 Hz.  Das Intro oben buendig (Anzeige_erste 0): Die Szenen
; beginnen alle bei Zeile $2C, das Menue passt in 200 Zeilen.  Mit
; ANZEIGE_MITTIG (Extro: Rolltext ueber 256 Zeilen) fehlt oben und unten
; gleich viel.
; ***************************************************************************
Amiga_einrichten:
	move.w	#-1,-(sp)
	move.w	#VsetMode,-(sp)
	trap	#14
	addq.l	#4,sp
	move.w	d0,Alter_modus

	move.w	#mon_type,-(sp)
	trap	#14
	addq.l	#2,sp
	tst.w	d0
	beq	.nein			; Monochrom
	cmp.w	#2,d0
	beq.b	.vga
	move.w	#VM_PAL+VM_BPS8,d0	; immer PAL, 50 Hz wie der Amiga
	move.w	#200,Anzeige_zeilen
	bra.b	.setzen
.vga:	move.w	#VM_VGA+VM_VERTFLAG+VM_BPS8,d0
	move.w	#240,Anzeige_zeilen
.setzen:
	move.w	d0,Neuer_modus
	clr.w	Anzeige_erste

	; Farben des Desktops sichern, *vor* dem Umschalten
	lea	VIDEL_PAL,a0
	lea	Alte_videl_farben,a1
	move.w	#256-1,d7
.sv:	move.l	(a0)+,(a1)+
	dbf	d7,.sv
	movem.l	ST_PAL,d0-d7
	movem.l	d0-d7,Alte_st_farben

	move.w	#Physbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,Alter_schirm

	pea	Text_cursor_aus
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp

	st	Ab_modus		; ab hier stellt der Abbau zurueck
	move.w	Neuer_modus,-(sp)
	move.w	#VsetMode,-(sp)
	trap	#14
	addq.l	#4,sp
	lea	VIDEL_PAL,a0		; schwarz, bis Thalion einblendet
	move.w	#256-1,d7
.sw:	clr.l	(a0)+
	dbf	d7,.sw

	; zwei Falcon-Schirme: 256-Byte-Grenze, im ST-RAM, schwarz (BSS)
	move.l	#Falcon_speicher+255,d0
	and.l	#-256,d0
	move.l	d0,Falcon_vorn
	move.l	d0,Basis_jetzt
	add.l	#FALCON_SCHIRM+FALCON_LUECKE,d0
	move.l	d0,Falcon_hinten
	move.l	d0,Basis_vorher

	move.w	#-1,-(sp)
	move.l	Falcon_vorn,-(sp)
	move.l	Falcon_vorn,-(sp)
	move.w	#Setscreen,-(sp)
	trap	#14
	lea	12(sp),sp
	move.w	#XB_Vsync,-(sp)
	trap	#14
	addq.l	#2,sp

	move.w	Neuer_modus,d0
	and.w	#VM_VGA+VM_PAL,d0
	cmp.w	#VM_PAL,d0
	bne.b	.zeilen_fest
	bsr	Videl_256
	bne.b	.zeilen_fest
	move.w	#FALCON_HOEHE,Anzeige_zeilen
.zeilen_fest:
	IFD	ANZEIGE_MITTIG
	move.w	#FALCON_HOEHE,d0
	sub.w	Anzeige_zeilen,d0
	lsr.w	#1,d0
	move.w	d0,Anzeige_erste
	ENDC

	IFD	ZIEL_SCHIRME
	bsr	Schirme_anlegen		; vor dem VBL: er liest die Tabelle
	ENDC
	; Amiga-Seite in Grundstellung: keine Taste gedrueckt
	move.b	#$FF,Amiga_cia_a
	move.w	#$FF00,Amiga_register+AR_POTGOR
	bsr	Bibliothek_anlegen

	; Maus
	move.w	#Kbdvbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,a0
	move.l	16(a0),Alter_mausvektor
	move.l	a0,Kbd_vektoren
	move.l	#Amiga_maus,16(a0)
	st	Ab_maus

	; Vektoren: $6C bekommt ein blosses rte, bis Thalion seinen VBL
	; eintraegt; $80 (trap #0) setzt Thalion selbst.
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	VEK_LEVEL3.w,Alter_level3
	move.l	VEK_TRAP0.w,Alter_trap0
	move.l	VEK_TRAP8.w,Alter_trap8
	move.l	#K2_trap,VEK_TRAP8.w
	move.l	#Nur_rte,VEK_LEVEL3.w
	move.l	VEK_VBL.w,Alter_vbl
	move.l	#Amiga_vbl,VEK_VBL.w
	st	Ab_vbl
	move.w	(sp)+,sr
	IFD	AMIGA_MESSEN
	bsr	Mess_starten
	ENDC
	moveq	#0,d0			; Z: bereit
	rts
.nein:	moveq	#1,d0
	rts

Nur_rte:
	rte

; ***************************************************************************
; Videl_256 -- wie im Fantasy-Intro (FEE_SUP.S): den Videl von 200 auf 256
; Zeilen ziehen, je 28 Zeilen oben und unten.  Z gesetzt: 256 Zeilen.
; ***************************************************************************
Videl_256:
	move.w	V_VDB,d0
	sub.w	#56,d0
	cmp.w	#32,d0
	blt.b	.nein
	move.w	V_VDE,d1
	add.w	#56,d1
	cmp.w	V_VSS,d1
	bcc.b	.nein
	move.w	V_VBE,d2
	cmp.w	d0,d2
	bls.b	.vbe
	move.w	d0,d2
.vbe:	move.w	V_VBB,d3
	cmp.w	d1,d3
	bcc.b	.vbb
	move.w	d1,d3
.vbb:	cmp.w	V_VSS,d3
	bcc.b	.nein
	move.w	d2,V_VBE
	move.w	d0,V_VDB
	move.w	d1,V_VDE
	move.w	d3,V_VBB
	moveq	#0,d0
	rts
.nein:	moveq	#1,d0
	rts

; ***************************************************************************
; Amiga_abraeumen -- alles zurueck, wie es vor dem Start war.
;
; Wiederholbar (Notausgang, AMIGA_NOTAUS.S): jeder Schritt nur, wenn sein
; Merker steht, und loescht ihn.  Im Notausgang ohne GEMDOS, also ohne den
; Textcursor und ohne Messdatei.
; ***************************************************************************
Amiga_abraeumen:
	IFD	AMIGA_MESSEN
	bsr	Mess_stoppen
	ENDC
	tst.b	Ab_vbl
	beq.b	.maus
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	Alter_vbl,VEK_VBL.w
	move.l	Alter_level3,VEK_LEVEL3.w
	move.l	Alter_trap0,VEK_TRAP0.w
	move.l	Alter_trap8,VEK_TRAP8.w
	sf	Ab_vbl
	move.w	(sp)+,sr
.maus:	bsr	Mischer_remove		; only XBIOS, harmless twice
	tst.b	Ab_maus
	beq.b	.modus
	move.l	Kbd_vektoren,a0
	move.l	Alter_mausvektor,16(a0)
	sf	Ab_maus
.modus:	tst.b	Ab_modus
	beq	.aus
	sf	Ab_modus

	move.w	#-1,-(sp)
	move.l	Alter_schirm,-(sp)
	move.l	Alter_schirm,-(sp)
	move.w	#Setscreen,-(sp)
	trap	#14
	lea	12(sp),sp
	move.w	#XB_Vsync,-(sp)
	trap	#14
	addq.l	#2,sp
	move.w	Alter_modus,-(sp)	; stellt auch die Videl-Zeilen zurueck
	move.w	#VsetMode,-(sp)
	trap	#14
	addq.l	#4,sp

	; beide Farbsaetze zurueck, der massgebliche zuletzt
	move.w	Alter_modus,d0
	btst	#7,d0			; STMODES
	bne.b	.st_zuletzt
	bsr.b	.st
	bsr.b	.videl
	bra.b	.farben
.st_zuletzt:
	bsr.b	.videl
	bsr.b	.st
.farben:
	tst.b	Im_notausgang
	bne.b	.aus
	pea	Text_cursor_an
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	IFD	AMIGA_MESSEN
	bsr	Mess_ausgeben
	ENDC
.aus:	rts
.videl:	lea	Alte_videl_farben,a0
	lea	VIDEL_PAL,a1
	move.w	#256-1,d7
.v:	move.l	(a0)+,(a1)+
	dbf	d7,.v
	rts
.st:	movem.l	Alte_st_farben,d0-d7
	movem.l	d0-d7,ST_PAL
	rts

NOTAUS_ABRAEUMEN	equ	Amiga_abraeumen
	include	"AMIGA_NOTAUS.S"

; ***************************************************************************
; Fehlende_melden -- hat Thalion eine Bibliotheksroutine gerufen, die wir
; nicht nachbilden, steht ihr Versatz in Bib_fehlt_versatz.
; ***************************************************************************
Fehlende_melden:
	move.w	Bib_fehlt_versatz,d0
	beq.b	.aus
	lea	Text_fehlt_zahl+4,a0
	moveq	#4-1,d2
.z:	and.l	#$FFFF,d0
	divu	#10,d0
	swap	d0
	add.b	#'0',d0
	move.b	d0,-(a0)
	clr.w	d0
	swap	d0
	dbf	d2,.z
	pea	Text_fehlt
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
.aus:	rts

; ***************************************************************************
; Die Bibliothek: exec und graphics, soweit Thalions Rahmen sie ruft
; (docs/11, 4.2).  Je Bibliothek eine Tabelle aus jmp-Befehlen unter der
; Basis, wie auf dem Amiga; die Felder dahinter sind 0 (AttnFlags 0: kein
; 68010+, Thalion nimmt VBR 0; ActiView und copinit 0).
; ***************************************************************************
EXEC_EINTRAEGE	equ	92		; bis -552 (OpenLibrary)
GFX_EINTRAEGE	equ	45		; bis -270 (WaitTOF)

Bibliothek_anlegen:
	lea	Exec_basis,a0
	moveq	#EXEC_EINTRAEGE,d0
	bsr.b	.leer
	lea	Gfx_basis,a0
	moveq	#GFX_EINTRAEGE,d0
	bsr.b	.leer
	lea	Exec_basis,a0
	lea	-552(a0),a1
	move.l	#Exec_openlibrary,d0
	bsr.b	.jmp
	lea	-414(a0),a1
	move.l	#Exec_closelibrary,d0
	bsr.b	.jmp
	lea	-30(a0),a1
	move.l	#Exec_supervisor,d0
	bsr.b	.jmp
	lea	Gfx_basis,a0
	lea	-222(a0),a1
	move.l	#Gfx_loadview,d0
	bsr.b	.jmp
	lea	-270(a0),a1
	move.l	#Gfx_waittof,d0
.jmp:	move.w	#$4EF9,(a1)+		; jmp abs.l
	move.l	d0,(a1)
	rts
; d0 Eintraege unter a0: jsr Bib_fehlt (die Ruecksprungadresse nennt den
; Eintrag).  Die nachgebildeten werden danach auf jmp umgestellt.
.leer:	subq.w	#1,d0
.e:	subq.l	#6,a0
	move.w	#$4EB9,(a0)		; jsr abs.l
	move.l	#Bib_fehlt,2(a0)
	dbf	d0,.e
	rts

Bib_fehlt:
	move.l	(sp)+,d0		; hinter dem Eintrag
	move.l	a0,-(sp)
	lea	Exec_basis,a0
	cmp.l	a0,d0
	bhi.b	.gfx
	sub.l	a0,d0
	bra.b	.merken
.gfx:	lea	Gfx_basis,a0
	sub.l	a0,d0
.merken:
	neg.w	d0			; Betrag des Versatzes, +6 wegen jsr
	addq.w	#6,d0
	move.w	d0,Bib_fehlt_versatz
	move.l	(sp)+,a0
	moveq	#0,d0
	rts

; OpenLibrary(a1 = Name, d0 = Version) -> d0 = Basis.  Thalion oeffnet nur
; graphics.library.
Exec_openlibrary:
	move.l	#Gfx_basis,d0
	rts

Exec_closelibrary:
	rts

; Supervisor(a5 = Routine): die Routine endet mit rte.  Wir sind schon im
; Supervisor; der Ausnahmerahmen fuer das rte wird hier gebaut (ab 68010
; mit Formatwort).
Exec_supervisor:
	move.l	(sp)+,Sv_rueck
	tst.b	Cpu_ab_68010
	beq.b	.kurz
	clr.w	-(sp)			; Format 0
.kurz:	move.l	Sv_rueck,-(sp)
	move.w	sr,-(sp)
	jmp	(a5)

Gfx_loadview:
	rts

; WaitTOF: bis zum naechsten VBL.
Gfx_waittof:
	move.l	d0,-(sp)
	move.l	Vbl_zaehler,d0
.w:	cmp.l	Vbl_zaehler,d0
	beq.b	.w
	move.l	(sp)+,d0
	rts

; ***************************************************************************
; K2_trap -- trap #8 an einer Stelle, wo Thalion BLTSIZE schreibt (K2).
; Der gestapelte PC steht hinter dem trap; K2_tabelle nennt dazu das erste
; Wort des Originalbefehls:
;   $3D7C  move.w #imm,$58(a6)   Wert hinter dem trap, danach die Distanz
;   $3D4n  move.w Dn,$58(a6)     Wert in Dn, danach die Distanz
;   $3A8n  move.w Dn,(a5)        Wert in Dn
; Der PC wird hinter den Originalbefehl gestellt.  Ist die Stelle nicht in
; der Tabelle, bleibt der Blit aus und K2_fremd zaehlt.
; ***************************************************************************
K2_trap:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	15*4+2(sp),d0		; PC hinter dem trap
	lea	K2_tabelle,a0
.such:	move.l	(a0)+,d1
	beq.b	.fremd
	move.w	(a0)+,d2
	cmp.l	d0,d1
	bne.b	.such
	move.l	d0,a1
	cmp.w	#$3D7C,d2
	bne.b	.dn
	move.w	(a1),d4			; #imm
	addq.l	#4,d0
	bra.b	.schreiben
.dn:	move.w	d2,d3			; Dn aus den geretteten Registern
	and.w	#7,d3
	lsl.w	#2,d3
	move.w	2(sp,d3.w),d4
	and.w	#$FFF8,d2
	cmp.w	#$3D40,d2
	bne.b	.schreiben
	addq.l	#2,d0			; die Distanz $0058
.schreiben:
	move.l	d0,15*4+2(sp)
	move.w	d4,Amiga_register+AR_BLTSIZE
	IFD	ABSTURZTEST
	bsr	Absturz_pruefen		; Thalions Ablauf ruft K2 laufend
	ENDC
	bsr	Amiga_blit
	movem.l	(sp)+,d0-d7/a0-a6
	rte
.fremd:	addq.w	#1,K2_fremd
	movem.l	(sp)+,d0-d7/a0-a6
	rte

	include	"AMIGA_BLIT.S"
	include	"AMIGA_MUSIK.S"
	IFD	ZIEL_SCHIRME
	include	"AMIGA_ZIEL.S"
	ENDC
Mess_blit_ende:				; AMIGA_MESSEN: K2_trap bis hier = Blits

; ***************************************************************************
; Amiga_maus -- Mausvektor (Kbdvbase+16), a0 = IKBD-Paket.  Kopf $F8-$FB:
; Bit 1 links, Bit 0 rechts; dann dx, dy.  Auf die Amiga-Seite:
;   CIA-A Port A Bit 6 = linke Taste (0 = gedrueckt)
;   POTGOR Bit 10      = rechte Taste (0 = gedrueckt)
;   JOY0DAT            = Zaehler, y im oberen, x im unteren Byte
; ***************************************************************************
Amiga_maus:
	move.b	(a0),d0
	move.b	#$FF,d1
	btst	#1,d0
	beq.b	.l
	bclr	#6,d1
.l:	move.b	d1,Amiga_cia_a
	move.w	#$FF00,d1
	btst	#0,d0
	beq.b	.r
	bclr	#10,d1
.r:	move.w	d1,Amiga_register+AR_POTGOR
	lea	Amiga_register+AR_JOY0DAT,a1
	move.b	2(a0),d0
	add.b	d0,(a1)			; y
	move.b	1(a0),d0
	add.b	d0,1(a1)		; x
	rts

; ***************************************************************************
; Amiga_vbl -- the VBL ($70).  Counters, the colours of the last VBL
; (Farben_schreiben, T62), the display (Anzeige_vbl), then the mixer
; (Mischer_vbl), and Thalion's VBL ($6C, ends with rte).  The
; display comes before the mixer so that it starts right after the picture
; (T27: behind the mixer it mostly started inside the picture); the mixer
; keeps three pieces ahead and does not mind (music session, 2026-10-18).
;
; Order: by default our display comes first, so our view lags one VBL
; behind Thalion's VBL.  A program that defines THALION_VBL (its level-3
; handler) has a K3 at the end of that handler which calls Anzeige_vbl after
; Thalion's work (intro: Thalion_vbl_ende), and then the mixer.  While
; Thalion's handler is in place, we then only jump there, and stars, colours
; and pointer are shown in the frame Thalion wrote them for, as on the Amiga.
;
; TOS's VBL no longer runs; we count _frclock ourselves, because TOS waits
; for it, after bombs even before the emergency exit (T16).
; ***************************************************************************
Amiga_vbl:
	movem.l	d0-d7/a0-a6,-(sp)
	addq.l	#1,FRCLOCK.w
	addq.l	#1,Vbl_zaehler
	sf	Basis_wartet		; the Videl shows Basis_jetzt now
	IFD	ABSTURZTEST
	addq.l	#1,Absturz_zaehler
	ENDC
	IFD	AMIGA_MESSEN
	addq.l	#1,Mess_vbls
	ENDC
	IFD	STRAHL
	bsr	Tk_vbl
	move.l	Basis_jetzt,St_vbl_schirm
	ENDC
	bsr	Farben_schreiben	; first: the beam is mostly behind the picture
	IFD	THALION_VBL
	cmp.l	#THALION_VBL,VEK_LEVEL3.w
	beq.b	.thalion		; display and mixer at the end of Thalion's VBL
	ENDC
	bsr	Anzeige_vbl
	bsr	Mischer_vbl
.thalion:
	movem.l	(sp)+,d0-d7/a0-a6
	move.l	VEK_LEVEL3.w,-(sp)
	rts

; ***************************************************************************
; Anzeige_vbl -- picture and colours from what Thalion wrote into the Amiga
; registers.  Once per VBL, from Amiga_vbl or from the end of Thalion's VBL.
;   Changes d0-d7/a0-a6.
; ***************************************************************************
Anzeige_vbl:
	STRAHL_VOR St_vbl
	bsr	Zeiger_weg
	bsr	Liste_lesen
	bsr	Anzeige_nachfuehren
	bsr	Zeiger_zeichnen
	bsr	Farben_rechnen		; written at the next VBL (Farben_schreiben)
	STRAHL_NACH St_vbl,St_vbl_schirm,#0,Anzeige_zeilen
	rts

; ***************************************************************************
; Liste_lesen -- Thalions Copperliste ($2452) und die Anzeigeregister nach
; Zustand.  Die Liste: ein Warten auf Zeile $20, die Ebenenzeiger
; (BPLxPTH/L), wahlweise ein Warten auf eine Bildzeile und Farben, Ende.
; ***************************************************************************
Z_EBENEN	equ	0		; 0: keine Anzeige
Z_ABSTAND	equ	2		; Bytes je Zeile einer Ebene zur naechsten Zeile
Z_VSTART	equ	4
Z_VSTOP		equ	6
Z_TEILUNG	equ	8		; Rasterzeile des Farbwechsels, 0: keiner
Z_LISTE		equ	10		; planes the list has pointers for (T62)
Z_ZEIGER	equ	12		; 5 Langworte
Z_GROESSE	equ	32

Liste_lesen:
	lea	Zustand,a2
	moveq	#Z_GROESSE/4-1,d0
.l:	clr.l	(a2)+
	dbf	d0,.l
	lea	Zustand,a2
	clr.w	Teil_anzahl
	move.l	Amiga_register+AR_COP1LC,d0
	beq	.aus
	move.l	d0,a0
	moveq	#0,d3			; noch kein Warten auf eine Bildzeile
	lea	Teil_farben,a3
	move.w	#200-1,d7		; Sicherung gegen eine kaputte Liste
.bef:	move.w	(a0)+,d0
	move.w	(a0)+,d1
	btst	#0,d0
	bne.b	.warten
	and.w	#$1FE,d0
	cmp.w	#$E0,d0
	blo.b	.naechster
	cmp.w	#$F4,d0
	bhs.b	.farbe
	sub.w	#$E0,d0			; BPLxPTH/L: Ebene = /4, Bit 1 = unten
	move.w	d0,d2
	lsr.w	#2,d2
	addq.w	#1,d2			; planes named so far
	cmp.w	Z_LISTE(a2),d2
	bls.b	.p
	move.w	d2,Z_LISTE(a2)
.p:	subq.w	#1,d2
	lsl.w	#2,d2
	btst	#1,d0
	bne.b	.unten
	move.w	d1,Z_ZEIGER(a2,d2.w)
	bra.b	.naechster
.unten:	move.w	d1,Z_ZEIGER+2(a2,d2.w)
	bra.b	.naechster
.farbe:	tst.w	d3
	beq.b	.naechster
	cmp.w	#$180,d0
	blo.b	.naechster
	cmp.w	#$1BE,d0
	bhi.b	.naechster
	cmp.w	#8,Teil_anzahl
	bhs.b	.naechster
	sub.w	#$180,d0
	move.w	d0,(a3)+		; Farbversatz (Wort)
	move.w	d1,(a3)+		; $0RGB
	addq.w	#1,Teil_anzahl
	bra.b	.naechster
.warten:
	cmp.w	#$FFFF,d0
	bne.b	.w
	cmp.w	#$FFFE,d1
	beq.b	.ende
.w:	move.w	d0,d2
	lsr.w	#8,d2
	cmp.w	#AMIGA_OBEN,d2
	bls.b	.naechster		; vor dem Bild
	move.w	d2,Z_TEILUNG(a2)
	moveq	#1,d3
.naechster:
	dbf	d7,.bef
.ende:
	move.w	Amiga_register+AR_BPLCON0,d0
	rol.w	#4,d0
	and.w	#7,d0
	cmp.w	#5,d0
	bls.b	.e
	moveq	#5,d0
.e:	move.w	d0,Z_EBENEN(a2)
	move.w	Amiga_register+AR_BPL1MOD,d0
	add.w	#AMIGA_WORTE*2,d0
	move.w	d0,Z_ABSTAND(a2)
	moveq	#0,d0
	move.b	Amiga_register+AR_DIWSTRT,d0
	move.w	d0,Z_VSTART(a2)
	moveq	#0,d0
	move.b	Amiga_register+AR_DIWSTOP,d0
	btst	#7,d0			; V8 = nicht V7
	bne.b	.v8
	add.w	#$100,d0
.v8:	move.w	d0,Z_VSTOP(a2)
.aus:	rts

; ***************************************************************************
; Anzeige_nachfuehren -- if the state has changed, the whole picture into
; the hidden Falcon screen and switch; otherwise up to ROLLZEILEN lines into
; the shown one, as far as Roll_strahl allows.  If the copper list shows a
; screen in the target format whole, the Videl shows it directly
; (Anzeige_direkt), without converting.  Otherwise converting reads the
; buffer, and that must be valid.  Converting is the fallback where no
; table covers the picture (E30: the intro and the extro need none except
; the intro's menu, T70; counted under AMIGA_MESSEN).  While the display is held (Display_hold) nothing is
; converted: the held picture stays until a list can be shown directly, or
; until Display_release.
; ***************************************************************************
Anzeige_nachfuehren:
	lea	Zustand,a0
	tst.w	Z_EBENEN(a0)
	beq	.aus
	lea	Zustand_alt,a1
	moveq	#Z_GROESSE/4-1,d0
.v:	cmpm.l	(a0)+,(a1)+
	dbne	d0,.v
	beq	.rollen
	; A list for another plane count than BPLCON0 waits (T62).  Thalion
	; writes the menu's list (5 planes, 200 bytes a line) at $FA0 and
	; BPLCON0/BPL1MOD only after the next VBL ($FAE); the Amiga sets them
	; in the blank, before the list is shown.  Converted at once, the menu
	; screen showed one frame with the old line length (the white frame).
	; A list with the plane count of the last one does not wait: there
	; Thalion changes only the registers ($406/$42A, 5 pointers, 4 planes).
	lea	Zustand,a0
	move.w	Z_LISTE(a0),d0
	cmp.w	Z_EBENEN(a0),d0
	beq.b	.gilt
	cmp.w	Zustand_alt+Z_LISTE,d0
	beq.b	.gilt
	addq.w	#1,Liste_wartet
	cmp.w	#LISTE_WARTEN,Liste_wartet
	bhi.b	.gilt			; Thalion did not follow: as on the Amiga
	IFD	STRAHL
	addq.l	#1,St_warten+ST_AUFRUFE
	ENDC
	rts				; the shown picture stays
.gilt:	clr.w	Liste_wartet
	lea	Zustand,a0
	lea	Zustand_alt,a1
	moveq	#Z_GROESSE/4-1,d0
.k:	move.l	(a0)+,(a1)+
	dbf	d0,.k
	bsr	Lage_rechnen
	IFD	ZIEL_SCHIRME
	bsr	Anzeige_direkt
	bne	.aus			; Z aus: direkt
	tst.b	Anzeige_gehalten
	bne	.halten
	bsr	Alle_sicherstellen
	ENDC
	IFD	AMIGA_MESSEN
	addq.l	#1,Anz_umgesetzt
	ENDC
	move.l	Falcon_hinten,a1
	STRAHL_VOR St_ganz
	bsr	Ganz_umsetzen
	STRAHL_NACH St_ganz,Falcon_hinten,#0,Anzeige_zeilen
	move.l	Falcon_hinten,d0
	move.l	Falcon_vorn,Falcon_hinten
	move.l	d0,Falcon_vorn
	bsr	Basis_setzen
	clr.w	Roll_zeile
	rts
	IFD	ZIEL_SCHIRME
.halten:
	move.l	#-1,Zustand_alt		; judged again at the next VBL
	rts
	ENDC
.rollen:
	IFD	ZIEL_SCHIRME
	tst.b	Anzeige_ist_direkt
	bne	.aus
	tst.b	Anzeige_gehalten
	bne	.aus
	bsr	Alle_sicherstellen
	ENDC
	move.w	Lage_h,d1
	ble	.aus
	move.w	Roll_zeile,d0
	sub.w	d0,d1			; noch uebrig
	cmp.w	#ROLLZEILEN,d1
	bls.b	.r
	moveq	#ROLLZEILEN,d1
.r:	move.w	d1,d3
	bsr	Roll_strahl
	tst.w	d1
	bgt.b	.r1
	; The beam is there: skip the band, it comes again next round.  Waiting
	; for it stalled the roll where our VBL usually finds the beam (T28).
	add.w	d3,d0
	cmp.w	Lage_h,d0
	blo.b	.s
	moveq	#0,d0
.s:	move.w	d0,Roll_zeile
	IFD	STRAHL
	addq.l	#1,St_sprung+ST_AUFRUFE
	ENDC
	rts
.r1:	move.w	d0,d2
	add.w	d1,d2
	cmp.w	Lage_h,d2
	blo.b	.r2
	moveq	#0,d2
.r2:	move.w	d2,Roll_zeile
	IFD	AMIGA_MESSEN
	addq.l	#1,Anz_gerollt
	ENDC
	move.l	Falcon_vorn,a1
	IFD	STRAHL
	move.w	d0,St_roll_zeile	; Falcon-Zeile: Lage_f0 dazu
	move.w	Lage_f0,d2
	add.w	d2,St_roll_zeile
	move.w	d1,St_roll_zeilen
	STRAHL_VOR St_roll
	bsr	Bereich_umsetzen
	STRAHL_NACH St_roll,Falcon_vorn,St_roll_zeile,St_roll_zeilen
	rts
	ELSE
	bra	Bereich_umsetzen
	ENDC
.aus:	rts

; ***************************************************************************
; Roll_strahl -- may the window lines d0 .. d0+d1-1 be converted into the
; shown screen now?  The beam must not run through them meanwhile (T27:
; it did in 27 % of the rolls, garbage lines in the picture).  Safe are
; lines the beam has passed in this frame, and a band at least
; ROLL_VORLAUF lines ahead of it.  Is the beam not in the picture of
; Falcon_vorn (behind the picture, or in the other screen, which Falcon_vorn
; follows from the next frame on), Strahl_vorlauf gives its distance to the
; top of Falcon_vorn as a line above the picture, and the same rule holds.
; T60 let every band through then, and 412 of them were hit (T60DIAG): the
; work lasted into the next frame.  T28/T29 counted the beam as being at
; line 0 there, and the menu never reached the screen.
;   IN : d0.w = first window line, d1.w = lines
;   OUT: d1.w = lines to convert now from d0 on (the part behind the beam),
;        0 = not now
;   All other registers are preserved.
; ***************************************************************************
Roll_strahl:
	movem.l	d0/d2-d4,-(sp)
	moveq	#0,d4			; 1: the beam is before Falcon_vorn
	move.w	d0,d2
	add.w	Lage_f0,d2		; first Falcon line
	bsr.b	Strahl_zeile
	tst.w	d0
	bpl.b	.bild
	bsr.b	Strahl_vorlauf		; a line above the picture
	moveq	#1,d4
.bild:	move.w	d2,d3
	add.w	d1,d3			; behind the band
	cmp.w	d0,d3
	ble.b	.aus			; all behind the beam
	move.w	d0,d3
	add.w	#ROLL_VORLAUF,d3
	cmp.w	d3,d2
	bge.b	.aus			; far enough ahead
	move.w	d0,d1
	sub.w	d2,d1			; the part behind the beam, or <= 0
	bpl.b	.aus
	moveq	#0,d1
.aus:
	IFD	STRAHL
	tst.w	d4
	beq.b	.z
	tst.w	d1
	bne.b	.z
	addq.l	#1,St_vfc+ST_AUFRUFE	; refused by Strahl_vorlauf
.z:
	ENDC
	movem.l	(sp)+,d0/d2-d4
	rts

; Strahl_vorlauf -- the beam is not in the picture of Falcon_vorn: d0.w =
; minus the lines until the Videl starts it (behind the picture the rest of
; the blank; in the other screen also the rest of that picture), so that
; Roll_strahl takes it as a line above the picture.  From the vertical
; counter VFC, in half-lines like VFT and VDB (assumed; T62DIAG records
; VFC at the VBL).  Odd values (VFT 0, VFC beyond VFT): -32768, every band
; may go, as in T60.  Changes only d0.
Strahl_vorlauf:
	move.l	d1,-(sp)
	move.w	V_VFC,d0
	move.w	V_VFT,d1
	beq.b	.frei
	cmp.w	d1,d0
	bhi.b	.frei
	sub.w	V_VDB,d0		; half-lines since this frame's picture began
	bmi.b	.vor			; it has not begun yet
	sub.w	d1,d0			; to the next frame's picture
.vor:	asr.w	#1,d0			; lines, negative
	move.l	(sp)+,d1
	rts
.frei:	move.w	#-32768,d0
	move.l	(sp)+,d1
	rts

; Strahl_zeile -- d0.w = the line of Falcon_vorn the Videl is reading, or
; -1 if it reads elsewhere.  H and M of the counter are read twice; if one
; changed meanwhile, once more.  Changes only d0.
Strahl_zeile:
	move.l	d1,-(sp)
.n:	moveq	#0,d0
	move.b	V_ZAEHL_H,d0
	swap	d0
	moveq	#0,d1
	move.b	V_ZAEHL_M,d1
	move.b	V_ZAEHL_L,d0
	cmp.b	V_ZAEHL_M,d1
	bne.b	.n
	swap	d0
	cmp.b	V_ZAEHL_H,d0
	bne.b	.n
	swap	d0
	lsl.w	#8,d1
	or.w	d1,d0
	sub.l	Falcon_vorn,d0
	bmi.b	.nein
	move.w	Anzeige_zeilen,d1
	mulu.w	#FALCON_ZEILE,d1
	cmp.l	d1,d0
	bhs.b	.nein
	divu.w	#FALCON_ZEILE,d0
	move.l	(sp)+,d1
	rts
.nein:	moveq	#-1,d0
	move.l	(sp)+,d1
	rts

; Basis_setzen -- d0 = picture base, valid from the next frame on (Tk_vbl
; measures whether it is).  Basis_vorher is the one set before; the Videl
; shows it until the next VBL, and Basis_wartet says so (Ziel_frei).
; Changes d1.
Basis_setzen:
	cmp.l	Basis_jetzt,d0
	beq.b	.aus
	move.l	Basis_jetzt,Basis_vorher
	move.l	d0,Basis_jetzt
	move.l	d0,d1
	swap	d1
	move.b	d1,V_BASIS_H
	move.w	d0,d1
	lsr.w	#8,d1
	move.b	d1,V_BASIS_M
	move.b	d0,V_BASIS_L
	st	Basis_wartet
	IFD	STRAHL
	st	Tk_umgeschaltet
	ENDC
.aus:	rts

	IFD	ZIEL_SCHIRME
; ***************************************************************************
; Anzeige_sofort -- aus dem Hauptablauf, gleich nachdem Thalion eine neue
; Copperliste gesetzt hat (K3).  Der Videl uebernimmt die Bildbasis vor
; unserem VBL; aus Amiga_vbl gesetzt, gilt sie erst ein Bild spaeter (T11,
; docs/11 7.8).  Auf dem Amiga gilt die Liste ab dem naechsten Bild, und so
; jetzt auch hier: Zeigt die neue Liste einen Schirm im Zielformat ganz,
; setzt Anzeige_direkt die Basis jetzt, und der VBL findet den Zustand
; schon vor.  Sonst bleibt alles dem VBL (Umsetzen).
;   Alle Register bleiben.
; ***************************************************************************
Anzeige_sofort:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0700,sr		; Amiga_vbl liest und schreibt dasselbe
	bsr	Zeiger_weg
	bsr	Liste_lesen
	lea	Zustand,a0
	tst.w	Z_EBENEN(a0)
	beq.b	.aus
	lea	Zustand_alt,a1
	moveq	#Z_GROESSE/4-1,d0
.v:	cmpm.l	(a0)+,(a1)+
	dbne	d0,.v
	beq.b	.aus			; nichts Neues
	bsr	Lage_rechnen
	bsr	Anzeige_direkt
	beq.b	.aus			; nicht direkt: der VBL setzt um
	lea	Zustand,a0
	lea	Zustand_alt,a1
	moveq	#Z_GROESSE/4-1,d0
.k:	move.l	(a0)+,(a1)+
	dbf	d0,.k
	clr.w	Roll_zeile
.aus:	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Anzeige_umschalten -- like Anzeige_sofort, for a program without screens
; in the target format (the intro, K3 at Thalion's $24BE): the new list is
; converted right here into the hidden Falcon screen, the pointer is drawn
; and the picture base is written, so it takes effect from the next frame
; on, as the copper list does on the Amiga (T11, docs/11 7.8).  Amiga_vbl
; then finds the state unchanged and only rolls.  The VBL (level 4) is
; held off meanwhile; it shares the state and uses the blitter.
;   All registers are preserved.
; ***************************************************************************
Anzeige_umschalten:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0400,sr
	bsr	Zeiger_weg
	bsr	Liste_lesen
	lea	Zustand,a0
	tst.w	Z_EBENEN(a0)
	beq.b	.zeiger
	lea	Zustand_alt,a1
	moveq	#Z_GROESSE/4-1,d0
.v:	cmpm.l	(a0)+,(a1)+
	dbne	d0,.v
	beq.b	.zeiger			; nothing new
	bsr	Anzeige_nachfuehren	; changed: convert all, switch
.zeiger:
	bsr	Zeiger_zeichnen
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; ***************************************************************************
; Display_hold -- at a change of scene (K3 in the intro): Thalion changes the
; format of the screens with the CPU next, and the table of the next scene
; comes later.  The picture shown now is copied into the hidden Falcon
; screen and shown from there, until a copper list can be shown directly
; again (Anzeige_direkt ends the hold, or Display_release where no table
; follows); meanwhile nothing is converted
; (Anzeige_nachfuehren).  Then the table goes (Schirme_wechseln with none),
; so Thalion's buffers hold everything again.  Returns after the next VBL,
; when the Videl shows the copy, so the targets may be written then.
; Called from the main flow only (it waits for the VBL).
;   All registers are preserved.
; ***************************************************************************
Display_hold:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0400,sr
	bsr	Zeiger_weg
	move.l	Basis_jetzt,a0
	move.l	Falcon_hinten,a1
	move.w	Anzeige_zeilen,d7
	mulu.w	#FALCON_ZEILE/32,d7
	subq.w	#1,d7
.k:	movem.l	(a0)+,d0-d6/a2		; 32 bytes
	movem.l	d0-d6/a2,(a1)
	lea	32(a1),a1
	dbf	d7,.k
	move.l	Falcon_hinten,d0
	move.l	Falcon_vorn,Falcon_hinten
	move.l	d0,Falcon_vorn
	bsr	Basis_setzen
	sub.l	a0,a0
	bsr	Schirme_wechseln
	st	Anzeige_gehalten
	move.w	(sp)+,sr
	move.l	Vbl_zaehler,d0
.vbl:	cmp.l	Vbl_zaehler,d0
	beq.b	.vbl
	movem.l	(sp)+,d0-d7/a0-a6
	rts

; Display_release -- ends the hold for a scene without a table (the intro's
; menu): from the next VBL the picture is converted again, at first whole.
;   All registers are preserved.
Display_release:
	move.w	sr,-(sp)
	or.w	#$0400,sr
	clr.b	Anzeige_gehalten
	move.l	#-1,Zustand_alt		; judged again at the next VBL
	move.w	(sp)+,sr
	rts

; ***************************************************************************
; Anzeige_direkt --zeigt die Copperliste einen Schirm der Schirmtabelle
; ganz?  Dann die Bildbasis in seinen Zielschirm, die Bankebene dort
; nachziehen, Anzeige_ist_direkt setzen, Z aus.  Sonst Anzeige_ist_direkt
; loeschen, Z gesetzt.  Ganz heisst: Ebene 0 in einem Schirm der Tabelle,
; die anderen im Abstand AMIGA_EBENE dahinter, Ebenen und Zeilenlaenge wie
; dort, auf eine Zeile ausgerichtet, und das Fenster fuellt die Anzeige.
; Ohne Fenster oben (Lage_f0) gibt es keine schwarzen Zeilen zu zeichnen.
;   Veraendert d0-d7/a0-a2/a5.
; ***************************************************************************
Anzeige_direkt:
	lea	Zustand,a2
	move.l	Z_ZEIGER(a2),d0
	bsr	Schirm_suchen
	beq	.nein
	move.w	Z_EBENEN(a2),d1
	cmp.w	SCH_EBENEN(a5),d1
	bne	.nein
	move.w	Z_ABSTAND(a2),d2
	cmp.w	SCH_BPR(a5),d2
	bne	.nein
	lea	Z_ZEIGER(a2),a0		; Ebenen 1.. im Abstand AMIGA_EBENE
	move.l	d0,d2
	subq.w	#2,d1
	bmi.b	.lage
.eb:	add.l	#AMIGA_EBENE,d2
	addq.l	#4,a0
	cmp.l	(a0),d2
	bne	.nein
	dbf	d1,.eb
.lage:	sub.l	SCH_AMIGA(a5),d0
	divu.w	SCH_BPR(a5),d0
	swap	d0
	tst.w	d0
	bne	.nein			; nicht auf einer Zeile
	swap	d0
	; The window shows screen lines r .. r+h-1 (r = list line + Lage_r0)
	; from display line Lage_f0 on.  Display line 0 is then target line
	; r - Lage_f0.  Lines above the window show the black margin
	; (ZIEL_RAND_ZEILEN); below it the display must end with the window, or
	; the window with the screen (then the black lines below SCH_ZEILEN).
	add.w	Lage_r0,d0		; r
	move.w	d0,d1
	add.w	Lage_h,d1
	cmp.w	SCH_ZEILEN(a5),d1
	bhi	.nein			; the window reaches beyond the screen
	beq.b	.unten
	move.w	Lage_f0,d1
	add.w	Lage_h,d1
	cmp.w	Anzeige_zeilen,d1
	bne	.nein			; screen lines below the window would show
.unten:	sub.w	Lage_f0,d0		; target line at display line 0
	cmp.w	#-ZIEL_RAND_ZEILEN,d0
	blt	.nein
	move.w	d0,d1
	add.w	Anzeige_zeilen,d1
	cmp.w	#FALCON_HOEHE+ZIEL_RAND_ZEILEN,d1
	bgt	.nein
	; Bank 1 ab der Teilung (in Anzeigezeilen; ohne Teilung keine)
	move.w	Anzeige_zeilen,d1
	move.w	Z_TEILUNG(a2),d2
	beq.b	.bank
	sub.w	#AMIGA_OBEN,d2
	sub.w	Anzeige_erste,d2
	bpl.b	.t
	moveq	#0,d2
.t:	cmp.w	d1,d2
	bhs.b	.bank
	move.w	d2,d1
.bank:	add.w	d0,d1			; erste Zielzeile mit Bank 1
	ext.l	d1
	cmp.l	SCH_BANK(a5),d1
	beq.b	.basis
	move.l	d1,SCH_BANK(a5)
	; bank 0 from the top margin on, bank 1 to the end of the target
	add.w	#ZIEL_RAND_ZEILEN,d1	; counted from the margin
	movem.l	d0-d1,-(sp)
	move.l	SCH_ZIEL(a5),a1
	lea	-ZIEL_RAND(a1),a1
	moveq	#0,d0
	moveq	#HOPOP_NULL,d5
	bsr	Bank_setzen		; Zeilen 0 .. d1-1
	movem.l	(sp),d0-d1
	move.l	SCH_ZIEL(a5),a1
	lea	-ZIEL_RAND(a1),a1
	move.w	d1,d0
	move.w	#2*ZIEL_RAND_ZEILEN+FALCON_HOEHE,d1
	sub.w	d0,d1
	moveq	#HOPOP_EINS,d5
	bsr	Bank_setzen		; ab d1 bis zum Ende
	movem.l	(sp)+,d0-d1
.basis:	muls.w	#ZIEL_ZEILE,d0
	add.l	SCH_ZIEL(a5),d0
	bsr	Basis_setzen
	st	Anzeige_ist_direkt
	clr.b	Anzeige_gehalten
	andi.b	#$FB,ccr		; Z aus
	rts
.nein:	clr.b	Anzeige_ist_direkt
	ori.b	#$04,ccr		; Z gesetzt
	rts
	ENDC

; ***************************************************************************
; Lage_rechnen -- wohin das Amiga-Bild auf den Falcon faellt.  Die Zeile r
; des Bildes steht auf dem Amiga auf Rasterzeile VSTART+r, bei uns in der
; Falcon-Zeile VSTART-$2C+r-Anzeige_erste.
;   Lage_f0 = erste Falcon-Zeile, Lage_h = Zeilen, Lage_r0 = erste Bildzeile
; ***************************************************************************
Lage_rechnen:
	lea	Zustand,a0
	move.w	Z_VSTART(a0),d0
	sub.w	#AMIGA_OBEN,d0
	sub.w	Anzeige_erste,d0	; f0
	move.w	Z_VSTOP(a0),d1
	sub.w	Z_VSTART(a0),d1		; h
	moveq	#0,d2			; r0
	tst.w	d0
	bpl.b	.o
	move.w	d0,d2
	neg.w	d2
	add.w	d0,d1
	moveq	#0,d0
.o:	move.w	d0,d3
	add.w	d1,d3
	sub.w	Anzeige_zeilen,d3
	ble.b	.u
	sub.w	d3,d1
.u:	tst.w	d1
	bpl.b	.h
	moveq	#0,d1
.h:	move.w	d0,Lage_f0
	move.w	d1,Lage_h
	move.w	d2,Lage_r0
	rts

; ***************************************************************************
; Ganz_umsetzen -- das ganze Bild nach a1 (Falcon-Schirm): Zeilen ausserhalb
; des Fensters schwarz, Ebenen 0-4, die Bankebene 5.
; ***************************************************************************
Ganz_umsetzen:
	move.l	a1,-(sp)
	moveq	#0,d0			; oben bis f0
	move.w	Lage_f0,d1
	bsr	Zeilen_loeschen
	move.l	(sp),a1
	move.w	Lage_f0,d0		; unter dem Fenster
	add.w	Lage_h,d0
	move.w	Anzeige_zeilen,d1
	sub.w	d0,d1
	bsr	Zeilen_loeschen
	move.l	(sp),a1
	moveq	#0,d0
	move.w	Lage_h,d1
	beq.b	.aus
	bsr	Bereich_umsetzen
	; Bank: 0 bis zur Teilung, 1 ab da
	move.l	(sp),a1
	move.w	Lage_f0,d0
	move.w	Lage_h,d1
	add.w	d0,d1			; Ende
	move.w	Zustand+Z_TEILUNG,d2
	beq.b	.alle0
	sub.w	#AMIGA_OBEN,d2
	sub.w	Anzeige_erste,d2
	cmp.w	d0,d2
	bge.b	.t1
	move.w	d0,d2
.t1:	cmp.w	d1,d2
	ble.b	.t2
	move.w	d1,d2
.t2:	movem.w	d1-d2,-(sp)
	move.w	d2,d1
	sub.w	d0,d1			; f0 .. Teilung: Bank 0
	moveq	#HOPOP_NULL,d5
	bsr	Bank_setzen
	movem.w	(sp)+,d1-d2
	move.l	(sp),a1
	move.w	d2,d0
	sub.w	d2,d1			; Teilung .. Ende: Bank 1
	moveq	#HOPOP_EINS,d5
	bsr	Bank_setzen
	bra.b	.aus
.alle0:	move.w	Lage_h,d1
	moveq	#HOPOP_NULL,d5
	bsr	Bank_setzen
.aus:	addq.l	#4,sp
	rts

; ***************************************************************************
; Bereich_umsetzen -- Bildzeilen d0 .. d0+d1-1 (ab Lage_r0 gezaehlt) nach a1:
; Ebene p aus dem Zeiger p der Copperliste, ueber Z_EBENEN hinaus 0.
;   Veraendert d0-d7/a0-a3.
; ***************************************************************************
Bereich_umsetzen:
	tst.w	d1
	ble	.aus
	lea	Zustand,a2
	move.w	d0,d2
	add.w	Lage_r0,d2
	mulu.w	Z_ABSTAND(a2),d2	; Versatz in der Amiga-Ebene
	move.w	d0,d3
	add.w	Lage_f0,d3
	mulu.w	#FALCON_ZEILE,d3
	add.l	d3,a1			; Falcon-Zeile, Ebene 0
	moveq	#0,d4			; Ebene
.eb:	move.w	d4,d3
	lsl.w	#2,d3
	move.l	Z_ZEIGER(a2,d3.w),a0
	add.l	d2,a0
	move.w	Z_ABSTAND(a2),d6
	move.w	#HOPOP_KOPIE,d5
	cmp.w	Z_EBENEN(a2),d4
	blo.b	.k
	moveq	#HOPOP_NULL,d5
.k:	movem.l	d1-d2/d4/a1-a2,-(sp)
	bsr	Ebene_blit
	movem.l	(sp)+,d1-d2/d4/a1-a2
	addq.l	#2,a1
	addq.w	#1,d4
	cmp.w	#5,d4
	blo.b	.eb
.aus:	rts

; Bank_setzen -- Ebene 5 der Falcon-Zeilen d0 .. d0+d1-1 von a1 mit d5
; (HOPOP_NULL oder HOPOP_EINS).
Bank_setzen:
	tst.w	d1
	ble.b	.aus
	mulu.w	#FALCON_ZEILE,d0
	lea	10(a1,d0.l),a1		; Ebene 5
	move.l	a1,a0			; Quelle unbenutzt (HOP 0)
	move.w	#FALCON_ZEILE,d6
	bra	Ebene_blit
.aus:	rts

; ***************************************************************************
; Ebene_blit -- eine Ebene, 20 Worte breit, d1 Zeilen: Amiga (a0, d6 Bytes
; je Zeile) nach Falcon (a1, jedes 8. Wort), HOP/OP d5.
; ***************************************************************************
Ebene_blit:
	moveq	#-1,d7
	move.w	d7,BL_MASKE1
	move.w	d7,BL_MASKE2
	move.w	d7,BL_MASKE3
	move.w	#2,BL_SRC_XINC
	sub.w	#(AMIGA_WORTE-1)*2,d6
	move.w	d6,BL_SRC_YINC
	move.w	#16,BL_DST_XINC
	move.w	#FALCON_ZEILE-(AMIGA_WORTE-1)*16,BL_DST_YINC
	move.w	#AMIGA_WORTE,BL_XCOUNT
	move.w	d5,BL_HOPOP
	clr.b	BL_SKEW
	move.l	a0,BL_SRC
	move.l	a1,BL_DST
	move.w	d1,BL_YCOUNT
	bra	Blit_starten

; Zeilen_loeschen -- Falcon-Zeilen d0 .. d0+d1-1 von a1 ganz auf 0.
Zeilen_loeschen:
	tst.w	d1
	ble.b	.aus
	mulu.w	#FALCON_ZEILE,d0
	add.l	d0,a1
	moveq	#-1,d7
	move.w	d7,BL_MASKE1
	move.w	d7,BL_MASKE2
	move.w	d7,BL_MASKE3
	move.w	#2,BL_DST_XINC
	move.w	#2,BL_DST_YINC
	move.w	#FALCON_ZEILE/2,BL_XCOUNT
	move.w	#HOPOP_NULL,BL_HOPOP
	clr.b	BL_SKEW
	move.l	a1,BL_DST
	move.w	d1,BL_YCOUNT
	bra	Blit_starten
.aus:	rts

; Blit_starten -- run the blit the registers describe and wait, in HOG
; mode: the CPU stands until it is done.  With a shared bus the main flow
; starved on the Falcon, the 030's wait loop runs from the cache and hardly
; lets the blitter on the bus (fantasy intro, hardware 2026-10-02, docs/11
; 7.6).  If the CPU then reads what the blitter wrote, the 030's data cache
; counts (Zeiger_zeichnen).
; In pieces of about BLIT_STUECK words, whole lines each (T68): while the
; blitter holds the bus, no interrupt is taken, the ACIA's neither.  The
; IKBD sends a byte every 1.3 ms; a blit over a whole plane lost bytes, and
; then TOS read the mouse packets shifted: the pointer jumped, and a dx of
; $F8-$FB counted as a header with buttons (T67: a menu entry chosen
; without a click).  The blitter carries its addresses on from piece to
; piece; between two pieces the CPU takes what is pending.
; With BLIT_TEILEN (test T60TEIL): without HOG, the blitter gives up the bus
; after 64 accesses; bset starts it again at once, the ST way.  Do the
; garbage lines in animations come from HOG blits during the picture?
;   All registers are preserved.
BLIT_STUECK	equ	512

Blit_starten:
	IFD	BLIT_TEILEN
	move.b	#BL_BUSY,BL_STEUER
.w:	bset.b	#7,BL_STEUER
	nop
	bne.b	.w
	ELSE
	movem.l	d0-d2,-(sp)
	move.w	BL_YCOUNT,d0		; lines in all
	move.l	#BLIT_STUECK,d1
	divu.w	BL_XCOUNT,d1		; lines per piece
	bne.b	.stueck
	moveq	#1,d1			; a line longer than a piece
.stueck:
	move.w	d1,d2
	cmp.w	d0,d2
	bls.b	.n
	move.w	d0,d2			; the last piece
.n:	move.w	d2,BL_YCOUNT
	move.b	#BL_BUSY+BL_HOG,BL_STEUER
.w:	btst.b	#7,BL_STEUER
	bne.b	.w
	sub.w	d2,d0
	bne.b	.stueck
	movem.l	(sp)+,d0-d2
	ENDC
	rts

; ***************************************************************************
; Der Mauszeiger (I3): Thalions VBL ($2522) schreibt im Menue die Lage in die
; Kopfwoerter zweier verbundener Sprites (Hunk 4 $20588) und die Zeiger nach
; SPR0PT/SPR1PT; eingeschaltet wird mit DMACON $8020 ($10C4), aus mit $7FFF.
; Wir lesen das wie die Hardware und zeichnen Sprite 0 und 1 mit der CPU in
; den gezeigten Falcon-Schirm: Ebenen 0-3 der Farbwert, Ebene 4 gesetzt
; (Amiga-Farbe 16+v), die Bankebene 5 bleibt.  Den Hintergrund sichert
; Zeiger_zeichnen, Zeiger_weg schreibt ihn vor dem Umsetzen zurueck.
; Thalion's VBL runs after our display, so the pointer lags one frame,
; except where the display runs at the end of Thalion's VBL (THALION_VBL).
; ***************************************************************************

; Zeiger_weg -- den Hintergrund unter dem zuletzt gezeichneten Zeiger
; zurueck.  Zwischen Sichern und Zurueckschreiben aendert niemand den
; Falcon-Schirm.
Zeiger_weg:
	move.w	Zg_zeilen,d7
	beq.b	.aus
	clr.w	Zg_zeilen
	move.l	Zg_adresse,a1
	lea	Zg_hinter,a0
	subq.w	#1,d7
.z:	move.l	(a0)+,(a1)
	move.l	(a0)+,4(a1)
	move.w	(a0)+,8(a1)
	tst.b	Zg_zwei
	beq.b	.n
	move.l	(a0)+,16(a1)
	move.l	(a0)+,20(a1)
	move.w	(a0)+,24(a1)
	bra.b	.w
.n:	lea	10(a0),a0
.w:	lea	FALCON_ZEILE(a1),a1
	dbf	d7,.z
.aus:	rts

; Zeiger_zeichnen -- Sprite 0 (und 1, wenn verbunden) in das gezeigte Bild
; (Basis_jetzt): Falcon_vorn, or the target shown directly.  In a target the
; pointer must be gone before anyone writes or reads there (Bl_umlenken,
; Schirme_wechseln, Display_hold call Zeiger_weg).
; Kopf: POS = VSTART 7-0 | HSTART 8-1, CTL = VSTOP 7-0 | ATT | - | VSTART 8
; | VSTOP 8 | HSTART 0; dann je Zeile zwei Datenworte.
Zeiger_zeichnen:
	lea	Amiga_register,a4
	move.w	AR_DMACON(a4),d0	; zuletzt geschrieben: SPREN dabei?
	btst	#5,d0
	beq.b	.dma
	tst.w	d0
	smi	Zg_dma			; SET an, CLR aus
.dma:	tst.b	Zg_dma
	beq	.aus
	tst.w	Zustand+Z_EBENEN
	beq	.aus
	move.l	AR_SPR0PT(a4),a2
	move.l	AR_SPR1PT(a4),a3
	btst	#7,3(a3)		; ATT in CTL von Sprite 1
	sne	Zg_verbunden
	addq.l	#4,a3
	move.w	(a2)+,d0		; POS
	move.w	(a2)+,d1		; CTL
	moveq	#0,d2			; VSTART
	move.w	d0,d2
	lsr.w	#8,d2
	btst	#2,d1
	beq.b	.v8
	add.w	#256,d2
.v8:	moveq	#0,d3			; VSTOP
	move.w	d1,d3
	lsr.w	#8,d3
	btst	#1,d1
	beq.b	.s8
	add.w	#256,d3
.s8:	sub.w	d2,d3			; Zeilen
	ble	.aus
	cmp.w	#ZG_MAX,d3
	bls.b	.hx
	moveq	#ZG_MAX,d3
.hx:	and.w	#$FF,d0			; HSTART
	add.w	d0,d0
	btst	#0,d1
	beq.b	.h0
	addq.w	#1,d0
.h0:	sub.w	#$80,d0			; x
	bmi	.aus
	cmp.w	#320,d0
	bhs	.aus
	sub.w	#AMIGA_OBEN,d2		; y
	sub.w	Anzeige_erste,d2
	bpl.b	.oben
	add.w	d2,d3			; oben abschneiden
	ble	.aus
	neg.w	d2
	lsl.w	#2,d2			; 4 Byte je Zeile und Sprite
	add.w	d2,a2
	add.w	d2,a3
	moveq	#0,d2
.oben:	move.w	Anzeige_zeilen,d1	; unten abschneiden
	sub.w	d2,d1
	ble	.aus
	cmp.w	d1,d3
	bls.b	.unten
	move.w	d1,d3
.unten:
	moveq	#15,d6			; Verschiebung in der Gruppe
	and.w	d0,d6
	lsr.w	#4,d0			; Gruppe
	cmp.w	#AMIGA_WORTE-1,d0
	slo	Zg_zwei
	lsl.w	#4,d0
	mulu.w	#FALCON_ZEILE,d2
	move.l	Basis_jetzt,a1		; also a target shown directly (menu)
	add.l	d2,a1
	add.w	d0,a1
	move.l	a1,Zg_adresse
	move.w	d3,Zg_zeilen
	lea	Zg_hinter,a0
	move.w	d3,d7
	subq.w	#1,d7
.zeile:	move.l	(a1),(a0)+		; sichern
	move.l	4(a1),(a0)+
	move.w	8(a1),(a0)+
	tst.b	Zg_zwei
	beq.b	.s1
	move.l	16(a1),(a0)+
	move.l	20(a1),(a0)+
	move.w	24(a1),(a0)+
	bra.b	.s2
.s1:	lea	10(a0),a0
.s2:	move.w	(a2)+,d0		; Sprite 0: Ebenen 0, 1
	move.w	(a2)+,d1
	moveq	#0,d2
	moveq	#0,d3
	tst.b	Zg_verbunden
	beq.b	.e
	move.w	(a3)+,d2		; Sprite 1: Ebenen 2, 3
	move.w	(a3)+,d3
	bra.b	.e2
.e:	addq.l	#4,a3
.e2:	move.w	d0,d4			; Ebene 4 = Maske
	or.w	d1,d4
	or.w	d2,d4
	or.w	d3,d4
	moveq	#0,d5			; Maske verschoben und verneint:
	move.w	d4,d5			; oben Gruppe, unten die naechste
	swap	d5
	lsr.l	d6,d5
	not.l	d5
	movem.w	d0-d4,Zg_worte
	move.l	a1,-(sp)
	lea	Zg_worte,a4
	moveq	#5-1,d4
.eb:	move.w	(a4)+,d0
	swap	d0
	clr.w	d0
	lsr.l	d6,d0
	move.l	d5,d1
	swap	d1
	and.w	d1,(a1)
	swap	d0
	or.w	d0,(a1)
	tst.b	Zg_zwei
	beq.b	.en
	swap	d0
	and.w	d5,16(a1)
	or.w	d0,16(a1)
.en:	addq.l	#2,a1
	dbf	d4,.eb
	move.l	(sp)+,a1
	lea	FALCON_ZEILE(a1),a1
	dbf	d7,.zeile
.aus:	rts

; ***************************************************************************
; Farben_rechnen -- the 64 colours of this VBL into Farben_neu.  Bank 0: the
; 32 colours Thalion's VBL wrote to $DFF180.  Bank 1: the same, with the
; colours behind the wait of the copper list.  Farben_schreiben puts them
; into the Videl at the start of the next VBL.
;   Changes d0-d3/a0-a2.
; ***************************************************************************
Farben_rechnen:
	lea	Amiga_register+AR_COLOR00,a0
	lea	Farben_neu,a1
	lea	Vier_nach_acht,a2
	moveq	#32-1,d3
.b0:	move.w	(a0)+,d0
	bsr	Amiga_nach_videl
	move.l	d1,(a1)+
	dbf	d3,.b0
	moveq	#32-1,d3
.b1:	move.l	-128(a1),(a1)+
	dbf	d3,.b1
	lea	Teil_farben,a0
	move.w	Teil_anzahl,d3
	bra.b	.tn
.t:	move.w	(a0)+,d2		; Wortversatz
	move.w	(a0)+,d0
	bsr	Amiga_nach_videl
	add.w	d2,d2
	lea	Farben_neu+32*4,a1
	move.l	d1,0(a1,d2.w)
.tn:	dbf	d3,.t
	rts

; ***************************************************************************
; Farben_schreiben -- first thing in Amiga_vbl: into the Videl only the
; entries of Farben_neu that differ from Farben_alt.  Writing all 64 every
; VBL, at the end of our work and so mostly while the picture ran, made the
; garbage stripes (T61FARB against T60INTR, docs/11 7.8).  At the start of
; the VBL the beam is mostly behind the picture.  The colours now follow
; Thalion one frame later, as a new picture base does (Basis_setzen).
; Farben_alt starts at 0 (BSS), as the palette does: Amiga_einrichten sets
; it black, and nobody else writes it.
;   Changes d0-d4/a0-a2.
; ***************************************************************************
Farben_schreiben:
	IFD	STRAHL
	bsr	St_zaehler
	move.l	d0,Fs_zaehler
	move.w	V_VFC,Fs_vfc
	ENDC
	lea	Farben_neu,a0
	lea	Farben_alt,a1
	lea	VIDEL_PAL,a2
	moveq	#0,d4			; entries written
	moveq	#64-1,d3
.v:	move.l	(a0)+,d0
	cmp.l	(a1)+,d0
	beq.b	.g
	move.l	d0,-4(a1)
	move.l	d0,(a2)
	addq.w	#1,d4
.g:	addq.l	#4,a2
	dbf	d3,.v
	IFD	STRAHL
	tst.w	d4
	beq.b	.aus
	lea	St_farben,a0		; how often, and with the beam in the picture
	addq.l	#1,ST_AUFRUFE(a0)
	move.w	Fs_vfc,d0
	cmp.w	V_VDB,d0
	blo.b	.zaehler
	cmp.w	V_VDE,d0
	bhs.b	.zaehler
	addq.l	#1,ST_TREFFER(a0)	; by VFC
.zaehler:
	move.l	Fs_zaehler,d0
	move.l	Falcon_vorn,a1
	bsr	St_zeile
	tst.w	d0
	bpl.b	.bild
	move.l	Fs_zaehler,d0
	move.l	Falcon_hinten,a1
	bsr	St_zeile
	tst.w	d0
	bmi.b	.aus
.bild:	addq.l	#1,ST_IMBILD(a0)	; by the video counter
.aus:
	ENDC
	rts

; Amiga_nach_videl -- d0.w = $0RGB -> d1.l = $RRGG00BB; a2 = Vier_nach_acht.
Amiga_nach_videl:
	move.w	d2,-(sp)
	moveq	#0,d1
	move.w	d0,d2
	lsr.w	#8,d2
	and.w	#15,d2
	move.b	0(a2,d2.w),d1
	lsl.w	#8,d1
	move.w	d0,d2
	lsr.w	#4,d2
	and.w	#15,d2
	move.b	0(a2,d2.w),d1
	swap	d1
	move.w	d0,d2
	and.w	#15,d2
	move.b	0(a2,d2.w),d1
	move.w	(sp)+,d2
	rts
Mess_rahmen_ende:			; AMIGA_MESSEN: Amiga_vbl bis hier = Anzeige

	IFD	AMIGA_MESSEN
MESS_BLIT_VON	equ	K2_trap
MESS_BLIT_BIS	equ	Mess_blit_ende
MESS_ZWEI_VON	equ	Amiga_vbl
MESS_ZWEI_BIS	equ	Mess_rahmen_ende
	IFD	MESS_ENDE
MESS_ABRAEUMEN	equ	Amiga_abbruch
	ELSE
MESS_ABRAEUMEN	equ	Amiga_abraeumen
	ENDC
MESS_MIT_K2	equ	1
	IFD	STRAHL
STRAHL_TAKT	equ	1		; St_text ruft Tk_text
	ENDC
	include	"AMIGA_MESSEN.S"

	IFD	STRAHL
; ***************************************************************************
; Tk_vbl -- (STRAHL) beim Eintritt in Amiga_vbl: Wo liest der Videl?  Zaehlt
; in Tk_faecher, getrennt danach, ob der vorige VBL eine neue Bildbasis
; schrieb.  Zwei Fragen fuer die Ablage im Zielformat (docs/11 7.7): Kommt
; der VBL erst nach der letzten Zeile ("Ende")?  Liest der Videl im Bild
; nach dem Umschalten schon den neuen Schirm ("neu"), oder noch den alten?
;   Veraendert d0-d2/a0-a1.
; ***************************************************************************
Tk_vbl:
	bsr	St_zaehler
	lea	Tk_faecher,a0
	tst.b	Tk_umgeschaltet
	bne.b	.umg
	lea	TK_FAECHER*4(a0),a0
	bra.b	.suchen
.umg:	clr.b	Tk_umgeschaltet
	move.w	Tk_bsp_anzahl,d2
	cmp.w	#TK_BEISPIELE,d2
	bhs.b	.suchen
	addq.w	#1,Tk_bsp_anzahl
	lsl.w	#2,d2
	lea	Tk_beispiele,a1
	move.l	d0,d1
	sub.l	Basis_jetzt,d1
	move.l	d1,0(a1,d2.w)
.suchen:
	move.l	Basis_jetzt,a1
	bsr.b	.fach
	bpl.b	.zaehlen
	lea	TK_SCHIRM*4(a0),a0
	move.l	Basis_vorher,a1
	bsr.b	.fach
	bpl.b	.zaehlen
	lea	TK_SCHIRM*4(a0),a0
	moveq	#0,d2			; anderswo
.zaehlen:
	lsl.w	#2,d2
	addq.l	#1,0(a0,d2.w)
	move.w	V_VFC,d2		; T62: the vertical counter, per 32 half-lines
	lsr.w	#5,d2
	cmp.w	#TK_VFC_FAECHER-1,d2
	bls.b	.vf
	moveq	#TK_VFC_FAECHER-1,d2
.vf:	lsl.w	#2,d2
	lea	Tk_vfc,a0
	addq.l	#1,0(a0,d2.w)
	move.w	V_VFT,Tk_vft
	move.w	V_VDB,Tk_vdb
	move.w	V_VDE,Tk_vde
	rts
; .fach -- d0 = Videozaehler, a1 = Schirm -> d2.w = Fach; N: nicht darin
.fach:	move.l	d0,d1
	sub.l	a1,d1
	bmi.b	.nein
	beq.b	.anfang
	move.w	Anzeige_zeilen,d2
	mulu.w	#FALCON_ZEILE,d2
	cmp.l	d2,d1
	blo.b	.zeile
	beq.b	.ende
	cmp.l	#FALCON_SCHIRM+FALCON_LUECKE,d1
	bhs.b	.nein
	moveq	#TK_DAHINTER,d2
	rts
.ende:	moveq	#TK_ENDE,d2
	rts
.anfang:
	moveq	#TK_ANFANG,d2
	rts
.zeile:	divu.w	#FALCON_ZEILE*TK_ZEILEN,d1
	move.w	d1,d2			; 0..15, N aus
	rts
.nein:	moveq	#-1,d2
	rts

; Tk_text -- (STRAHL) die Faecher von Tk_vbl als Text nach a1, a1 dahinter.
; Nur Faecher, die nicht 0 sind: "neu Z240:12" heisst 12-mal im neuen
; Schirm, Zeilen 240-255.  Dann die ersten Zaehler nach einem Umschalten,
; in Byte ab dem neuen Schirm (320 je Zeile).
;   Veraendert d0-d2/a0.
Tk_text:
	movem.l	d3-d6/a2,-(sp)
	lea	Text_tk_kopf,a0
	bsr	Mess_anhaengen
	lea	Tk_faecher,a2
	lea	Text_tk_umg,a0
	bsr	.fall
	lea	Text_tk_ohne,a0
	bsr	.fall
	lea	Text_tk_bsp,a0
	bsr	Mess_anhaengen
	lea	Tk_beispiele,a2
	move.w	Tk_bsp_anzahl,d3
	bra.b	.bn
.b:	move.b	#' ',(a1)+
	move.l	(a2)+,d0
	bpl.b	.pos
	move.b	#'-',(a1)+
	neg.l	d0
.pos:	bsr	Mess_zahl
.bn:	dbf	d3,.b
	lea	Text_tk_vfc,a0		; T62: "H320:12" = 12 times VFC 320-351
	bsr	Mess_anhaengen
	lea	Tk_vfc,a2
	moveq	#0,d5
.h:	move.l	(a2)+,d6
	beq.b	.hl
	move.b	#' ',(a1)+
	move.b	#'H',(a1)+
	moveq	#0,d0
	move.w	d5,d0
	lsl.w	#5,d0
	bsr	Mess_zahl
	move.b	#':',(a1)+
	move.l	d6,d0
	bsr	Mess_zahl
.hl:	addq.w	#1,d5
	cmp.w	#TK_VFC_FAECHER,d5
	blo.b	.h
	lea	Text_tk_vft,a0
	bsr	Mess_anhaengen
	moveq	#0,d0
	move.w	Tk_vft,d0
	bsr	Mess_zahl
	lea	Text_tk_vdb,a0
	bsr	Mess_anhaengen
	moveq	#0,d0
	move.w	Tk_vdb,d0
	bsr	Mess_zahl
	lea	Text_tk_vde,a0
	bsr	Mess_anhaengen
	moveq	#0,d0
	move.w	Tk_vde,d0
	bsr	Mess_zahl
	movem.l	(sp)+,d3-d6/a2
	rts
; .fall -- a0 = Ueberschrift, a2 = TK_FAECHER Zaehler; a2 dahinter.
.fall:	bsr	Mess_anhaengen
	moveq	#0,d4			; Schirm: 0 neu, 1 alt
.schirm:
	moveq	#0,d5			; Fach
.f:	move.l	(a2)+,d6
	beq.b	.leer
	move.b	#' ',(a1)+
	lea	Text_tk_neu,a0
	tst.w	d4
	beq.b	.n
	lea	Text_tk_alt,a0
.n:	bsr	Mess_anhaengen
	cmp.w	#TK_ANFANG,d5
	blo.b	.z
	move.w	d5,d0
	sub.w	#TK_ANFANG,d0
	lsl.w	#2,d0
	lea	Tk_namen,a0
	move.l	0(a0,d0.w),a0
	bsr	Mess_anhaengen
	bra.b	.wert
.z:	move.b	#'Z',(a1)+
	moveq	#0,d0
	move.w	d5,d0
	mulu.w	#TK_ZEILEN,d0
	bsr	Mess_zahl
.wert:	move.b	#':',(a1)+
	move.l	d6,d0
	bsr	Mess_zahl
.leer:	addq.w	#1,d5
	cmp.w	#TK_SCHIRM,d5
	blo.b	.f
	addq.w	#1,d4
	cmp.w	#2,d4
	blo.b	.schirm
	move.l	(a2)+,d6		; anderswo
	beq.b	.aus
	lea	Text_tk_anders,a0
	bsr	Mess_anhaengen
	move.l	d6,d0
	bsr	Mess_zahl
.aus:	rts
	ENDC

	IFD	MESS_ENDE
; Amiga_abbruch -- (Diagnose MESS_ENDE=n, INTRDIAG) nach n Sekunden
; abraeumen, die Messung ausgeben (Amiga_abraeumen) und zurueck zum
; Desktop, auch wenn Thalions Programm festhaengt.  Dem Lader meldet das
; Intro QUIT (3).  Alter_ssp gehoert dem Einbinder.  Kehrt nicht zurueck.
Amiga_abbruch:
	bsr	Amiga_abraeumen
	move.l	Alter_ssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#3,-(sp)
	move.w	#Pterm,-(sp)
	trap	#1
	ENDC
	ENDC

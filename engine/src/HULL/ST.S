; HULL/ST.S -- alles, was mit der Hardware des ST/STE spricht
;
; The counterpart of HULL/FALCON.S, only in the ST build (-DZIEL_ST=1,
; tools/build_st.sh; docs/12-ST-Port.md).  The same names, the same
; contract: Enter_supervisor, Leave_supervisor, Open_screen, Close_screen.
;
; **ST niedrig: 320x200, vier Ebenen, 16 Farbregister.**  Gesetzt ueber
; Setscreen mit Aufloesung 0 auf dem ST und STE, auf dem Falcon ueber
; VsetMode (STMODES, vier Ebenen), damit das VDI unberuehrt bleibt.
; Auf dem Falcon laeuft so der ST-Bau als Pruefstand (Farben, Raster), nicht
; fuers Tempo: auch mit 8 MHz ist ein 68030 mit Cache kein 68000.
;
; **Welche Maschine**, sagen die Cookies:
;   _MCH  0 ST, 1 STE (auch Mega STE), 2 TT, 3 Falcon.  Ab dem STE gibt es
;         das untere Byte der Videobasis (Feinbasis) und 4 Bit je Kanal.
;   _VDO  $0003xxxx: Falcon.  Dann sichern und stellen wir den Videomodus
;         mit VsetMode zurueck, wie FALCON.S; Getrez sagt dort nichts.
; Ohne Cookie-Topf (TOS 1.0-1.04) ist es ein ST.
;
; PLAIN_ST=YES in AMBER.INF (E17, shared/SETTINGS.S) makes an STE or Mega
; STE behave like a plain ST (St_nur_st): the user has no ST, only those two
; (user 2026-10-21).  The 8 MHz STE runs as fast as the ST, so only the
; features are switched off.  Not covered: the older TOS and the memory of a
; real ST.

Getrez	= 4			; XBIOS 4: Aufloesung erfragen
Blitmode = 64			; XBIOS 64: blitter there and on (TOS 1.02+)
VgetMonitor = 89		; XBIOS 89, Falcon: 2 = VGA
ST_BPS4	= 2			; VsetMode: vier Ebenen

; ***************************************************************************
; In den Supervisormodus und zurueck (wie FALCON.S).
; ***************************************************************************
Enter_supervisor:
	clr.l	-(sp)
	move.w	#Super,-(sp)
	Gemdos
	addq.l	#6,sp
	move.l	d0,oldssp(a5)
	rts

Leave_supervisor:
	move.l	oldssp(a5),-(sp)
	move.w	#Super,-(sp)
	Gemdos
	addq.l	#6,sp
	rts

; ***************************************************************************
; St_cookie -- einen Cookie suchen.  Supervisor.
;   IN : d0.l = Name
;   OUT: d0.l = Wert, 0 wenn es ihn nicht gibt.  Alle uebrigen Register bleiben.
; Fuer _MCH und _VDO heisst "fehlt" dasselbe wie der Wert 0: ein ST.
; ***************************************************************************
St_cookie:
	movem.l	d1/a0,-(sp)
	move.l	$5A0.w,d1		; _p_cookies
	beq.b	stc_nicht
	move.l	d1,a0
stc_lauf:
	move.l	(a0)+,d1
	beq.b	stc_nicht		; Ende des Topfs
	cmp.l	d0,d1
	beq.b	stc_da
	addq.l	#4,a0
	bra.b	stc_lauf
stc_da:	move.l	(a0),d0
	bra.b	stc_out
stc_nicht:
	moveq	#0,d0
stc_out:
	movem.l	(sp)+,d1/a0
	rts

; ***************************************************************************
; Bildschirm aufsetzen: Maschine erkennen, alte Palette und Aufloesung
; sichern, ST niedrig, unsere Schirme zeigen.
; ***************************************************************************
Open_screen:
	; ---- Maschine ----
	sf	Feinbasis
	sf	St_falcon
	move.l	#'_MCH',d0
	bsr	St_cookie
	swap	d0			; 0 ST, 1 STE, 2 TT, 3 Falcon
	tst.w	d0
	beq.b	os_mch_st
	st	Feinbasis
os_mch_st:
	move.l	#'_VDO',d0
	bsr	St_cookie
	swap	d0
	cmp.w	#3,d0
	bne.b	os_kein_falcon
	st	St_falcon
os_kein_falcon:
	; ---- Blitter (E40): Blitmode(-1), bit 1 = there.  XBIOS 64 exists
	; from TOS 1.02 on; before that there is no blitter either.  Only
	; detected so far, no code uses it yet (docs/05c, step 4). ----
	sf	St_blitter
	move.l	$4F2.w,a0		; _sysbase
	cmp.w	#$0102,2(a0)		; os_version
	bcs.b	os_kein_blitter
	move.w	#-1,-(sp)
	move.w	#Blitmode,-(sp)
	Xbios
	addq.l	#4,sp
	btst	#1,d0
	beq.b	os_kein_blitter
	st	St_blitter
os_kein_blitter:
	; ---- PLAIN_ST=YES: behave like a plain ST, to test the ST on an STE
	; or Mega STE (user 2026-10-21).  No low video base byte (no screen
	; shake), three bits per channel, no blitter.  Missing (SET_NONE)
	; counts as NO.  MAIN.S has read AMBER.INF before (Einstellungen_lesen,
	; E17). ----
	sf	St_nur_st
	cmp.b	#SET_YES,Settings_plain_st
	bne.b	os_maschine_da
	st	St_nur_st
	sf	Feinbasis
	sf	St_blitter
os_maschine_da:
	; ---- Zeilen, die Timer B je Bildzeile zaehlt (ST_LIB.S, S2) ----
	; Am Falcon an VGA verdoppelt der Videl ST niedrig auf 400 Zeilen;
	; dass Timer B dann jede doppelt zaehlt, ist angenommen, nicht gemessen.
	move.w	#1,St_zfaktor
	tst.b	St_falcon
	beq.b	os_faktor
	move.w	#VgetMonitor,-(sp)
	Xbios
	addq.l	#2,sp
	cmp.w	#2,d0
	bne.b	os_faktor
	move.w	#2,St_zfaktor
os_faktor:

	; ---- alte Aufloesung ----
	tst.b	St_falcon
	beq.b	os_getrez
	move.w	#-1,-(sp)
	move.w	#VsetMode,-(sp)
	Xbios
	addq.l	#4,sp
	move.w	d0,oldmode(a5)
	; Falcon: auch die VIDEL-Farben des Desktops, so viele, wie der Modus
	; traegt (siehe FALCON.S)
	and.w	#7,d0
	cmp.w	#4,d0
	bcc.b	os_echtfarbe
	moveq	#1,d2
	lsl.w	d0,d2
	moveq	#1,d1
	lsl.w	d2,d1
	move.w	d1,v_farbzahl(a5)
	pea	savepal
	move.w	d1,-(sp)
	move.w	#0,-(sp)
	move.w	#VgetRGB,-(sp)
	Xbios
	lea	10(sp),sp
	bra.b	os_st_farben
os_echtfarbe:
	clr.w	v_farbzahl(a5)
	bra.b	os_st_farben
os_getrez:
	move.w	#Getrez,-(sp)
	Xbios
	addq.l	#2,sp
	move.w	d0,oldmode(a5)
os_st_farben:
	; ---- die 16 ST-Register (auf allen dreien vorhanden) ----
	lea	$FFFF8240.w,a0
	lea	savepal16,a1
	moveq	#16-1,d0
os_sp:	move.w	(a0)+,(a1)+
	dbf	d0,os_sp

	pea	cursoff(pc)
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp

	move.w	#Physbase,-(sp)
	Xbios
	addq.l	#2,sp
	move.l	d0,p_tos(a5)		; nur zum Zurueckschalten beim Beenden

	; ---- ST niedrig auf unserem Schirm ----
	; Setscreen setzt die Basis ueber screenpt im naechsten VBL; danach
	; setzt nur noch die Bibliothek sie (Basis_setzen), wie beim Falcon.
	;
	; **Falcon: der Modus ueber VsetMode, nicht ueber Setscreen.**  Setscreen
	; mit Aufloesung 0 stellt dort auch das VDI auf 320x200 um; Close_screen
	; nimmt nur den Modus mit VsetMode zurueck, und das Desktop kam mit der
	; Zeilenlaenge von ST niedrig in den alten Modus: zweimal verkleinert
	; oben, unten weiss (Nutzer, 2026-10-04).  VsetMode laesst das VDI
	; stehen, wie in FALCON.S.  Vom alten Modus bleiben nur VGA und PAL:
	; Overscan und Zeilensprung gibt es in ST niedrig nicht, die
	; Zeilenverdopplung an VGA macht STMODES selbst.
	tst.b	St_falcon
	beq.b	os_st_setscreen
	move.w	oldmode(a5),d0
	and.w	#MD_VGA+MD_PAL,d0
	btst	#4,d0			; MD_VGA: the mode stays (50 Hz below)
	bne.b	os_vga
	or.w	#MD_PAL,d0
os_vga:
	or.w	#MD_STMODES+ST_BPS4+COL40,d0
	move.w	d0,-(sp)
	move.w	#VsetMode,-(sp)
	Xbios
	addq.l	#4,sp
	move.w	#-1,-(sp)		; Aufloesung bleibt
	move.l	Schirm_vorn,-(sp)
	move.l	#-1,-(sp)		; Logbase bleibt die von TOS
	bra.b	os_setscreen
os_st_setscreen:
	move.w	#0,-(sp)		; Aufloesung 0: 320x200, 16 Farben
	move.l	Schirm_vorn,-(sp)
	move.l	Schirm_vorn,-(sp)
os_setscreen:
	move.w	#Setscreen,-(sp)
	Xbios
	lea	12(sp),sp
	move.w	#Vsync,-(sp)
	Xbios
	addq.l	#2,sp
	clr.l	screenpt.w

	; ---- 50 Hz, as Thalion's Amiga (user, 2026-10-25, docs/05c-ST.md):
	; Thalion counts VBLs (Realtime, VBLs_per_step, Time_2D/3D, Delay), at
	; 60 Hz the game runs a fifth too fast.  ST and STE: the sync bit,
	; Close_screen puts the old one back.  Falcon: the PAL bit above, at
	; RGB only; VGA has no 50 Hz. ----
	move.b	$FFFF820A.w,St_old_sync
	tst.b	St_falcon
	bne.b	os_50hz
	bset	#1,$FFFF820A.w		; 50 Hz
os_50hz:

	; ---- The precomputed palettes (STPAL.DAT, ST_LIB.S), before
	; Palette_anfang looks up the first one.  DEVIATION (goal 2),
	; docs/17-deviations.md D1 ----
	bsr	St_load_palettes
	; ---- Palette erst jetzt: der Moduswechsel setzt die Register ----
	bsr	Palette_anfang
	st	Schirme_an
	st	Schirm_offen
	rts

; ***************************************************************************
; Bildschirm abraeumen: zurueck auf den von TOS, alte Aufloesung und Farben.
;
; Dieselbe Wache wie in FALCON.S: **nur einmal und nur nach Open_screen**
; (Schirm_offen), denn der Notausgang (MAIN.S) ruft Close_screen bei jedem
; Programmende, auch nach Exit_program und vor Open_screen.  **Im
; Notausgang kein GEMDOS** (Im_notausgang): den Schirmspeicher gibt TOS
; beim Beenden frei, die Cursorfolge entfaellt.
; ***************************************************************************
Close_screen:
	tst.b	Schirm_offen
	bne.b	cs_offen
	rts
cs_offen:
	sf	Schirm_offen
	sf	Schirme_an
	move.w	#-1,-(sp)
	move.l	p_tos(a5),-(sp)
	move.l	p_tos(a5),-(sp)
	move.w	#Setscreen,-(sp)
	Xbios
	lea	12(sp),sp
	move.w	#Vsync,-(sp)
	Xbios
	addq.l	#2,sp
	tst.b	Im_notausgang
	bne.b	cs_kein_eigener		; gibt TOS frei
	move.l	p_scrr(a5),d0
	beq.b	cs_kein_eigener
	move.l	d0,-(sp)
	move.w	#Mfree,-(sp)
	Gemdos
	addq.l	#6,sp
	clr.l	p_scrr(a5)
cs_kein_eigener:
	tst.b	St_falcon
	beq.b	cs_st
	; ---- Falcon: Modus, dann beide Farbsaetze, der massgebliche zuletzt ----
	move.w	oldmode(a5),-(sp)
	move.w	#VsetMode,-(sp)
	Xbios
	addq.l	#4,sp
	move.w	oldmode(a5),d0
	btst	#7,d0			; STMODES ?
	bne.b	cs_st_zuletzt
	bsr	cs_st_farben
	bsr	cs_videl_farben
	bra.b	cs_fertig
cs_st_zuletzt:
	bsr	cs_videl_farben
	bsr	cs_st_farben
	bra.b	cs_fertig
cs_st:
	move.w	oldmode(a5),-(sp)	; alte Aufloesung
	move.l	#-1,-(sp)
	move.l	#-1,-(sp)
	move.w	#Setscreen,-(sp)
	Xbios
	lea	12(sp),sp
	move.b	St_old_sync,$FFFF820A.w	; the desktop's 50 or 60 Hz
	bsr	cs_st_farben
cs_fertig:
	tst.b	Im_notausgang
	bne.b	cs_ohne_cursor
	pea	curson(pc)
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp
cs_ohne_cursor:
	rts

cs_st_farben:
	lea	savepal16,a0
	lea	$FFFF8240.w,a1
	moveq	#16-1,d0
cs_sf:	move.w	(a0)+,(a1)+
	dbf	d0,cs_sf
	rts

cs_videl_farben:
	move.w	v_farbzahl(a5),d0
	beq.b	cs_vf_out		; Echtfarbe: keine Palette
	pea	savepal
	move.w	d0,-(sp)
	move.w	#0,-(sp)
	move.w	#VsetRGB,-(sp)
	Xbios
	lea	10(sp),sp
cs_vf_out:
	rts

; ***************************************************************************
; VT52-Folgen fuer den Textcursor.
; ***************************************************************************
cursoff: dc.b	27,'f',0
curson:	dc.b	27,'e',0
	even

	SECTION	Fast_BSS,bss
; Feinbasis (set: the video base has its low byte, STE and later) is in
; LIBRARY.S, preset for the Falcon; Open_screen sets it here.
St_falcon:	ds.b	1		; gesetzt: Falcon, Modus ueber VsetMode
St_blitter:	ds.b	1		; set: a blitter is there (and not PLAIN_ST)
St_nur_st:	ds.b	1		; set: PLAIN_ST=YES, behave like a plain ST
St_old_sync:	ds.b	1		; $FF820A before Open_screen (50/60 Hz)
	even
Schirm_offen:	ds.b	1		; gesetzt: Open_screen lief, Close_screen noch nicht
	even
St_zfaktor:	ds.w	1		; Timer-B-Zeilen je Bildzeile (1, VGA 2)
	SECTION	Program,code


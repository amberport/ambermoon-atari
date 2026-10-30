; HULL/FALCON.S -- alles, was mit der Falcon-Hardware spricht
;
; Diese Datei hat kein Vorbild im freigegebenen Quelltext, und sie kann auch
; keines haben: das Aufsetzen des Bildschirms lag bei Thalion im Lader, der
; nicht mitveroeffentlicht wurde.  Die Namen sind deshalb unsere, aber in der
; Familie der vorhandenen -- Clear_screen, Update_screen, Switch_screens
; heissen im Original ebenso.
;
; **Der Zweck dieser Datei ist die Grenze.**  Oberhalb, in MAIN.S und der
; ganzen Spiellogik, steht kein Hardwarezugriff mehr; im Original war das
; ebenso, dort greift von vierzig Dateien nur FAIRY.S und HULL/VARIOUS.S
; auf die Maschine zu.  Wer den STE bedienen will, schreibt HULL/STE.S
; daneben und bindet die andere Datei ein -- alles darueber bleibt eine
; Fassung.
;
; Was hier drinsteht, ist Falcon: VsetMode und VsetRGB gibt es auf dem ST
; nicht, der eigene Bildschirm muss im ST-RAM liegen, und die 256 VIDEL-
; Farbregister haben sechs Bit je Kanal statt vier.

; ***************************************************************************
; In den Supervisormodus und zurueck.
;
; Ohne ihn geht das Umbiegen des Mausvektors nicht: dabei muessen die
; Interrupts gesperrt werden, und schon das Lesen des Statusregisters ist ab
; dem 68010 privilegiert.  Auf dem 68000 waere es durchgegangen -- auf dem
; Falcon nicht, das Programm bricht mit einer Ausnahme ab.
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
; Bildschirm aufsetzen: Modus, Palette, eigener Bildspeicher.
;
; Die Farben setzt Palette_anfang (FADE_SUP.S): Main_pal in Bank 2, sonst
; schwarz.  Den Bildpuffer (Off_screen) legt Bildpuffer_anlegen an (MAIN.S).
; ***************************************************************************
Open_screen:
; ---- Bildschirmmodus setzen ----
	move.w	#-1,-(sp)
	move.w	#VsetMode,-(sp)
	Xbios
	addq.l	#4,sp
	move.w	d0,oldmode(a5)

; ---- alte Palette sichern, **vor** dem Moduswechsel ----
;
; Hier stand der Fehler, der die Desktopfarben kostete: gesichert wurde
; *nach* dem Umschalten, also die Palette des neuen Modus statt der des
; Desktops.  Beim Beenden kam folgerichtig etwas zurueck, das dort nie
; gestanden hatte (Erkenntnis 77).
;
; Beide Registersaetze werden gesichert -- die sechzehn ST-vertraeglichen
; bei $FF8240 und die von VIDEL bei $FF9800.  Welcher angezeigt wird, laesst
; sich dem Moduswort nicht sicher ansehen: der Desktop von TOS 4.04 hat
; sechzehn Farben und haengt trotzdem an VIDEL.  In Hatari nachgemessen --
; Eintrag 14 der VIDEL-Register ist $00a800a8, und dieses Dunkelcyan ist der
; tuerkise Hintergrund.  Die ST-Register bleiben dabei unberuehrt: sie sind
; vor und nach dem Lauf Byte fuer Byte gleich.
;
; **Von VIDEL nur so viele Eintraege, wie der Modus traegt.**  Die
; TOS-Beschreibung sagt es zu VsetRGB ausdruecklich: "One should not try to
; restore more colors than supported by the video mode."  Das ist keine
; Formsache -- mit allen 256 kommt der Desktop kaputt zurueck, mit den
; sechzehn des Modus richtig.  Die Zahl steht in den unteren drei Bits:
; 0,1,2,3 heisst 1,2,4,8 Ebenen und damit 2,4,16,256 Farben; ab 4 ist es
; Echtfarbe und hat keine Palette.
	move.w	d0,d1
	and.w	#7,d1
	cmp.w	#4,d1
	bcc.b	.echtfarbe
	moveq	#1,d2
	lsl.w	d1,d2			; Ebenen
	moveq	#1,d1
	lsl.w	d2,d1			; Farben
	move.w	d1,v_farbzahl(a5)
	pea	savepal
	move.w	d1,-(sp)
	move.w	#0,-(sp)
	move.w	#VgetRGB,-(sp)
	Xbios
	lea	10(sp),sp
	bra.b	.st_sichern
.echtfarbe:
	clr.w	v_farbzahl(a5)
.st_sichern:
	pea	savepal16
	move.w	#16,-(sp)
	move.w	#0,-(sp)
	move.w	#EgetPalette,-(sp)
	Xbios
	lea	10(sp),sp

; ---- jetzt erst umschalten ----
; **The monitor bits are inherited, not set -- with one exception.**  oldmode
; is the mode the machine runs in now, the one that fits the *connected*
; monitor.  MODEMASK keeps MD_VGA (time base 31 or 15 kHz), MD_VERTFLAG (at
; VGA the line doubling that puts 200 lines on a 400-line screen), MD_PAL and
; MD_OVERSCAN.  We set what is ours: eight planes, 40 columns; and at RGB
; MD_PAL, because Thalion counts VBLs for 50 Hz (T65, 2026-10-27).
;
; So the same program runs at RGB *and* at VGA -- the Falcon shows
; ST-compatible resolutions on both.  Fixing a time base here locks out half
; the users; that was the case from 2026-09-12 to 2026-09-13 (finding 152).
; PAL at RGB is not a time base: RGB stays 15 kHz.
	move.w	oldmode(a5),d0
	and.w	#MODEMASK,d0		; Monitorbits vom Desktop uebernehmen
	or.w	#BPS8+COL40,d0
	; At RGB always PAL (main's wish, user 2026-10-25): Thalion counts VBLs
	; for 50 Hz (Realtime, VBLs_per_step "10 seconds on 50 Hz", Delay), and
	; a 60 Hz desktop ran the game a fifth too fast.  VGA keeps its mode.
	btst	#4,d0			; MD_VGA
	bne.b	.vga
	or.w	#MD_PAL,d0
.vga:
	move.w	d0,-(sp)
	move.w	#VsetMode,-(sp)
	Xbios
	addq.l	#4,sp

	pea	cursoff(pc)
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp

; ---- Palette setzen ----
	bsr	Palette_anfang

	move.w	#Physbase,-(sp)
	Xbios
	addq.l	#2,sp
	move.l	d0,p_tos(a5)		; nur zum Zurueckschalten beim Beenden

; ---- unsere Schirme anzeigen ----
;
; Nicht den von TOS: wie gross dessen Speicher ist, sagt niemand.  Er wurde
; im vorherigen Modus angelegt, und bei einem Desktop mit 16 Farben ist er
; halb so gross wie die 64000 Byte, die wir hineinschreiben.  Unsere zwei
; Schirme hat Bildpuffer_anlegen (MAIN.S) schon im ST-RAM angelegt.
;
; **Danach setzt nur noch die Bibliothek die Videobasis** (Basis_setzen,
; LIBRARY.S): bei jedem Tausch und in jedem Bild, wegen des Bildschuettelns.
; Setscreen legt die Adresse in screenpt ab, und der VBL von TOS setzt von
; dort die Basis -- stuende der Wert stehen, holte TOS nach jedem Tausch
; den ersten Schirm zurueck.  Also ein Bild abwarten und screenpt leeren.
	move.w	#-1,-(sp)
	move.l	Schirm_vorn,-(sp)
	move.l	#-1,-(sp)
	move.w	#Setscreen,-(sp)
	Xbios
	lea	12(sp),sp
	move.w	#Vsync,-(sp)
	Xbios
	addq.l	#2,sp
	clr.l	screenpt.w
	st	Schirme_an
	st	Schirm_offen
	rts

; ***************************************************************************
; Bildschirm abraeumen: zurueck auf den von TOS, alten Modus und alte
; Farben wiederherstellen.
;
; **Nur einmal und nur nach Open_screen** (Schirm_offen).  Der Notausgang
; (MAIN.S) ruft Close_screen bei jedem Programmende, also auch nach
; Exit_program; ein zweiter Lauf gaebe den Schirmspeicher zweimal frei.  Und
; Speicher_voll kann kommen, bevor der Schirm offen war: dann stuende in
; oldmode noch nichts.
;
; **Im Notausgang kein GEMDOS** (Im_notausgang): TOS beendet das Programm
; gerade, und dass GEMDOS dabei einen weiteren Aufruf vertraegt, ist nicht
; belegt.  Den Schirmspeicher gibt TOS beim Beenden ohnehin frei, die
; Cursorfolge entfaellt.  XBIOS bleibt, ohne VsetMode und Farben ginge es
; nicht.
; ***************************************************************************
Close_screen:
	tst.b	Schirm_offen
	bne.b	.offen
	rts
.offen:
	sf	Schirm_offen
; ---- wieder auf den Bildschirm von TOS ----
;
; Erst umschalten, dann den Bildwechsel abwarten, dann freigeben.  Wer den
; Speicher freigibt, waehrend die Videobasis noch hineinzeigt, laesst den
; Bildaufbau in fremdem Speicher weiterlaufen.  Vorher schweigt unser VBL
; (Schirme_an), sonst setzte er die Basis gleich wieder auf unseren Schirm.
	sf	Schirme_an
	move.w	#-1,-(sp)
	move.l	p_tos(a5),-(sp)
	move.l	#-1,-(sp)
	move.w	#Setscreen,-(sp)
	Xbios
	lea	12(sp),sp
	move.w	#Vsync,-(sp)
	Xbios
	addq.l	#2,sp
	tst.b	Im_notausgang
	bne.b	.kein_eigener		; gibt TOS frei
	move.l	p_scrr(a5),d0
	beq.b	.kein_eigener
	move.l	d0,-(sp)
	move.w	#Mfree,-(sp)
	Gemdos
	addq.l	#6,sp
	clr.l	p_scrr(a5)
.kein_eigener:

; ---- alten Modus und alte Palette zurueck ----
	move.w	oldmode(a5),-(sp)
	move.w	#VsetMode,-(sp)
	Xbios
	addq.l	#4,sp

	; Beide zurueck, und der massgebliche zuletzt.  Welcher das ist, sagt
	; das STMODES-Bit: bei einem ST-vertraeglichen Modus gelten die
	; sechzehn, sonst die von VIDEL.  Wer immer dieselbe Reihenfolge
	; nimmt, verfaerbt genau einen der beiden Faelle.
	move.w	oldmode(a5),d0
	btst	#7,d0			; STMODES ?
	bne.b	.st_zuletzt
	bsr	Set_st_palette
	bsr	Set_videl_palette
	bra.b	.pal_fertig
.st_zuletzt:
	bsr	Set_videl_palette
	bsr	Set_st_palette
.pal_fertig:

	tst.b	Im_notausgang
	bne.b	.ohne_cursor
	pea	curson(pc)
	move.w	#Cconws,-(sp)
	Gemdos
	addq.l	#6,sp
.ohne_cursor:
	rts

; ***************************************************************************
; Die beiden Farbregistersaetze des Desktops zurueckschreiben.
; ***************************************************************************
Set_videl_palette:
	move.w	v_farbzahl(a5),d0	; so viele, wie der Modus traegt
	beq.b	svp_out			; Echtfarbe: keine Palette
	pea	savepal
	move.w	d0,-(sp)
	move.w	#0,-(sp)
	move.w	#VsetRGB,-(sp)
	Xbios
	lea	10(sp),sp
svp_out:	rts

Set_st_palette:
	pea	savepal16
	move.w	#16,-(sp)
	move.w	#0,-(sp)
	move.w	#EsetPalette,-(sp)
	Xbios
	lea	10(sp),sp
	rts

; ***************************************************************************
; VT52-Folgen fuer den Textcursor.
; ***************************************************************************
cursoff: dc.b	27,'f',0
curson:	dc.b	27,'e',0
	even

	SECTION	Fast_BSS,bss
Schirm_offen:	ds.b	1	; gesetzt: Open_screen lief, Close_screen noch nicht
	even

	SECTION	Program,code

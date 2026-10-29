; ***************************************************************************
; AMIGA_MUSIK.S -- Thalion's music in intro and extro (docs/11 6, E14).
;
; The Amiga loader hands Thalion's program a pointer to the music player
; (Uebergabe+0).  Thalion calls it at +0 (init), +12 (start, d0 = part),
; +16 (stop) and, from Thalion's level-3 VBL, +24 (the beat).  The player
; is raw code at the front of Intro_music/Extro_music, PC-relative except
; for 27 hardware operands (tools/musik_k1.py).
;
; Musik_laden reads the file at run time (goal 2), checks it against the
; build's map and bends the operands (K1 at run time): Paula onto
; Musik_schatten, the CIAs onto Musik_cia.  Thalion then gets
; Musik_tabelle.  Its +24 is empty: the beat comes from the mixer of the
; music session (musik/MISCHER.S, docs/13 4f), once per 1/50 s of sound it
; mixes, not from the VBL.  Musik_mischen starts the mixer, Amiga_vbl calls
; Mischer_vbl, Amiga_abraeumen calls Mischer_remove (also in the emergency
; exit).
;
; Without SECTION: stands in the code section of the program that includes
; it.  The program provides Musik_k1 and MUSIK_LAENGE (build/<name>_musik.i).
; ***************************************************************************

; ***************************************************************************
; Musik_laden -- load the music file and hand it to Thalion.  The file is
; looked for in AMBFILES\ first, then next to the program, like the loader
; does.  Its length and the 27 operands must match Musik_k1; otherwise
; Uebergabe+0 stays Musik_stumm.
;   IN : a0 = file name with AMBFILES\ in front, a1 = without
;   Before Super, in user mode.  All registers are preserved.
; ***************************************************************************
Musik_laden:
	movem.l	d0-d7/a0-a6,-(sp)
	move.l	a0,a4			; TOS destroys d0-d2/a0-a2
	move.l	a1,a5
	move.l	a4,a0
	bsr	.oeffnen
	bpl.b	.offen
	move.l	a5,a0
	bsr	.oeffnen
	bmi	.aus
.offen:	move.w	d0,d7			; handle
	pea	Musik_daten
	move.l	#MUSIK_LAENGE+1,-(sp)	; one more: a longer file is another one
	move.w	d7,-(sp)
	move.w	#Fread,-(sp)
	trap	#1
	lea	12(sp),sp
	move.l	d0,d6
	move.w	d7,-(sp)
	move.w	#Fclose,-(sp)
	trap	#1
	addq.l	#4,sp
	cmp.l	#MUSIK_LAENGE,d6
	bne.b	.aus
	lea	Musik_k1,a2		; first check all, then patch
	lea	Musik_daten,a3
.pruef:	move.w	(a2)+,d0
	bmi.b	.biegen
	move.l	(a2)+,d1
	cmp.l	0(a3,d0.w),d1
	bne.b	.aus
	bra.b	.pruef
.biegen:
	lea	Musik_k1,a2
.b:	move.w	(a2)+,d0
	bmi.b	.fertig
	move.l	(a2)+,d1
	cmp.l	#$DFF000,d1
	blo.b	.cia
	sub.l	#$DFF000,d1
	add.l	#Musik_schatten,d1
	bra.b	.setzen
.cia:	sub.l	#$BFD000,d1
	add.l	#Musik_cia,d1
.setzen:
	move.l	d1,0(a3,d0.w)
	bra.b	.b
.fertig:
	; The 030 instruction cache (256 bytes) holds no line of Musik_daten:
	; nothing ran there since the program was loaded.
	move.l	#Musik_tabelle,Uebergabe
.aus:	movem.l	(sp)+,d0-d7/a0-a6
	rts

; a0 = name -> d0 = handle (N clear) or error (N set)
.oeffnen:
	clr.w	-(sp)			; read only
	move.l	a0,-(sp)
	move.w	#Fopen,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	rts

; ***************************************************************************
; Musik_mischen -- start the mixer (musik/MISCHER.S) on the loaded player.
; MUSIC= in AMBER.INF decides how (E17), the file looked for in AMBFILES\
; first, then next to the program: OFF silent, CPU the processor,
; everything else (DSP, YM, no file, no MUSIC=) the DSP; YM on the Falcon
; means DSP here (user, 2026-10-12).
; Nothing happens when Musik_laden failed.
;   IN : a0 = Thalion's word "music on" (tick only while it is set; Thalion
;        writes -1 or 0, so its first byte will do)
;   Supervisor, after Amiga_einrichten.  All registers are preserved.
; ***************************************************************************
MUSIK_SAETZE	equ	$BC		; four records of MD_SATZ (AM2_CPU 3:$37BE)
MUSIK_STILLE	equ	$3F4		; the silence (AM2_CPU 3:$3AF6)

Musik_mischen:
	movem.l	d0/a0-a1,-(sp)
	cmp.l	#Musik_tabelle,Uebergabe
	bne.b	.aus
	lea	Musik_satz,a1
	move.l	#Musik_schatten,MS_SCHATTEN(a1)
	move.l	#Musik_daten+24,MS_TAKT(a1)	; Thalion's +24, the beat
	move.l	a0,MS_MERKER(a1)
	; Two of the four 4e fields (docs/13 4e, docs/11 7.8): synth and silent
	; channels go the DSP way, the samples stay on the host port (MS_STUECK
	; and MS_LIED stay 0, the samples do not fit into the DSP).  Already
	; before Thalion's init: the mixer only compares addresses with them and
	; reads a record only after a channel played from it.
	move.l	#Musik_daten+MUSIK_SAETZE,MS_SAETZE(a1)
	move.l	#Musik_daten+MUSIK_STILLE,MS_STILLE(a1)
	lea	Inf_datei,a0
	bsr	Settings_read
	tst.l	d0
	bpl.b	.gelesen
	lea	Inf_datei+9,a0		; without AMBFILES\
	bsr	Settings_read
.gelesen:
	moveq	#0,d0
	move.b	Settings_music,d0
	cmp.b	#SET_OFF,d0
	beq.b	.wahl			; OFF
	cmp.b	#SET_CPU,d0
	beq.b	.cpu
	moveq	#MISCHER_DSP,d0		; DSP, YM, no file
	bra.b	.wahl
.cpu:	moveq	#MISCHER_CPU,d0
.wahl:	move.w	d0,MS_WAHL(a1)
	move.l	a1,a0
	bsr	Mischer_install
.aus:	movem.l	(sp)+,d0/a0-a1
	rts

	include	"shared/SETTINGS.S"	; AMBER.INF (E17), from main

; ***************************************************************************
; Musik_tabelle -- what Thalion gets as the player: init, start and stop go
; to Thalion's player, everything else is empty.  +24, the beat, is called
; by the mixer, not by Thalion's VBL.
; ***************************************************************************
Musik_tabelle:
	bra.w	Musik_init		; +0
	bra.w	Musik_nichts		; +4 CIA interrupt on: never called
	bra.w	Musik_nichts		; +8 off
	bra.w	Musik_start		; +12
	bra.w	Musik_stop		; +16
	bra.w	Musik_nichts		; +20 sound effect: never called
	bra.w	Musik_nichts		; +24 the beat: the mixer calls it
Musik_init:
	jmp	Musik_daten
Musik_start:
	jmp	Musik_daten+12
Musik_stop:
	jmp	Musik_daten+16
Musik_nichts:
	rts

	include	"MISCHER.S"		; musik/, the music session's mixer

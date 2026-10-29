; lader.s -- AMBER.TOS: startet die Programme nacheinander, wie auf dem
; Amiga Thalions Lader `Ambermoon` (docs/11-Intro-Extro.md, 1).
;
; Thalions Lader (1.20, Hunk 1 ab $1AE) laedt Saves und setzt den Merker,
; wenn das erste Wort (der zuletzt gespeicherte Platz) nicht 0 ist; startet
; Fantasy_intro, dann Ambermoon_intro mit {Musik, Merker}; bei der Wahl 3
; (QUIT) endet er, sonst startet er das Spiel mit der Wahl.  Wir ebenso:
;
;   SAVES        erstes Wort <> 0 -> Merker.  Fehlt SAVES, ist er 0 (Thalion
;                bricht dort ab).
;   FANTASY.TOS  ohne Befehlszeile.
;   INTRO.TOS    Befehlszeile "1" mit Merker, sonst "0" (-> Merkerbyte).
;                Zurueck kommt die Menuewahl: 0 WEITERSPIELEN,
;                1 NEUE QUEST STARTEN, 3 QUIT.
;   ENGINE.TOS   Befehlszeile "0" (WEITERSPIELEN, nur mit Merker) oder "1"
;                (NEUE QUEST); bei QUIT gar nicht.  Sonst -- INTRO.TOS fehlt,
;                ein Ladefehler, eine unbekannte Wahl -- leer: ENGINE zeigt
;                dann sein eigenes Startmenue (Absprache mit der 2D-Session,
;                2026-09-30).
;   EXTRO.TOS    wenn ENGINE mit -5000 bis -5002 endet (Thalions End_seq):
;                Befehlszeile n = -Wert-5000 ("0"-"2"); danach die Frage,
;                ob das Ende noch einmal laufen soll (Nutzer, 2026-10-01).
;
; Befehlszeile: Laengenbyte 1, eine ASCII-Ziffer, Endnull (nicht in der
; Laenge).  Jedes Programm laeuft auch allein.  Fehlt eines, geht es still
; mit dem naechsten weiter; jeder andere Ladefehler wird gemeldet.
;
; **Ablage wie Amberfiles/ beim Amiga** (Erkenntnis 262): Der Lader liegt
; oben, alles andere im Ordner AMBFILES.  Er sucht jede Datei zuerst als
; AMBFILES\Name, dann als blossen Namen (flache Ablage).  Das
; Arbeitsverzeichnis bleibt seines; ENGINE.TOS findet den Ordner von dort.
;
; **One AMBER.TOS for both machines** (user, 2026-10-21).  At the start
; it reads the cookie _MCH: high word 3 is a Falcon, which starts FANTASY,
; INTRO, ENGINE and EXTRO; anything else, or no cookie jar at all (old ST
; TOS), is an ST, which starts FANTSYST, INTROST, ENGINEST and EXTROST.
; The ST has no intros yet, so it goes straight to the engine's start menu.
; 68000 instructions only.

Cconws		equ	9
Fopen		equ	$3D
Fclose		equ	$3E
Fread		equ	$3F
Mshrink		equ	$4A
Pexec		equ	$4B
Pterm0		equ	0
EFILNF		equ	-33		; Datei nicht gefunden
EPTHNF		equ	-34		; Pfad nicht gefunden
WAHL_WEITER	equ	0		; Menuewahl des Intros
WAHL_NEU	equ	1
WAHL_QUIT	equ	3
SPIELENDE	equ	-5000		; GAME_COMPLETED; -5001, -5002 die anderen
Crawcin		equ	7
Supexec		equ	38		; XBIOS
Cookie_jar	equ	$5A0
MCH_FALCON	equ	3		; high word of _MCH

	SECTION	Lader_code,code
start:
	; Speicher bis zum BSS-Ende behalten, den Rest den Programmen lassen.
	move.l	4(sp),a0
	move.l	12(a0),d0
	add.l	20(a0),d0
	add.l	28(a0),d0
	add.l	#256,d0
	lea	Stapel_oben,sp
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#Mshrink,-(sp)
	trap	#1
	lea	12(sp),sp

	bsr	Rechner_waehlen
	bsr	Merker_lesen

	move.l	Namen,a0
	move.l	(a0),a4			; the fantasy intro
	lea	Leere_zeile,a5
	bsr	Starten

	lea	Zeile_intro,a5
	move.b	#'0',1(a5)
	tst.b	Merker
	beq.b	.intro
	move.b	#'1',1(a5)
.intro:	move.l	Namen,a0
	move.l	4(a0),a4
	bsr	Starten

	; Die Wahl entscheidet, ob und wie das Spiel startet.  Ein Ladefehler
	; ist negativ und faellt wie jede unbekannte Wahl auf die leere Zeile.
	lea	Leere_zeile,a5
	cmp.l	#WAHL_QUIT,d0
	beq	.ende
	cmp.l	#WAHL_NEU,d0
	beq.b	.neu
	cmp.l	#WAHL_WEITER,d0
	bne.b	.engine
	tst.b	Merker			; WEITERSPIELEN gibt es nur mit Merker
	beq.b	.engine
	lea	Zeile_engine,a5
	move.b	#'0',1(a5)
	bra.b	.engine
.neu:	lea	Zeile_engine,a5
	move.b	#'1',1(a5)
.engine:
	move.l	Namen,a0
	move.l	8(a0),a4
	bsr	Starten

	; Spielende (E2): Thalions End_seq gibt -5000 bis -5002 zurueck, sein
	; Lader rechnet das Ende n = -Wert-5000 und zeigt das Extro, danach
	; die Frage, ob es noch einmal laufen soll.  Verglichen wird das
	; untere Wort, denn Pterm gibt nur ein Wort.
	cmp.w	#SPIELENDE,d0
	bgt.b	.ende
	cmp.w	#SPIELENDE-2,d0
	blt.b	.ende
	neg.w	d0
	sub.w	#-SPIELENDE-'0',d0	; n als Ziffer
	lea	Zeile_extro,a5
	move.b	d0,1(a5)
.extro:	move.l	Namen,a0
	move.l	12(a0),a4
	bsr	Starten
	tst.l	d0
	bmi.b	.ende			; fehlt oder geht nicht: keine Frage
	pea	Text_nochmal
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
	and.b	#$DF,d0			; gross
	cmp.b	#'J',d0
	beq.b	.extro
.ende:
	move.w	#Pterm0,-(sp)
	trap	#1

; ***************************************************************************
; Rechner_waehlen -- Falcon or ST, from the cookie _MCH -> Namen.
;   Changes d0-d2/a0-a2 (XBIOS).
; ***************************************************************************
Rechner_waehlen:
	move.l	#Namen_st,Namen
	pea	Cookie_lesen
	move.w	#Supexec,-(sp)
	trap	#14
	addq.l	#6,sp
	cmp.w	#MCH_FALCON,Mch_wert
	bne.b	.aus
	move.l	#Namen_falcon,Namen
.aus:	rts

; In supervisor mode (Supexec): the value of _MCH -> Mch_wert, or 0.
Cookie_lesen:
	clr.l	Mch_wert
	move.l	Cookie_jar.w,d0
	beq.b	.aus			; no cookie jar: an old ST
	move.l	d0,a0
.such:	move.l	(a0)+,d0
	beq.b	.aus			; end of the jar
	cmp.l	#'_MCH',d0
	beq.b	.da
	addq.l	#4,a0
	bra.b	.such
.da:	move.l	(a0),Mch_wert
.aus:	rts

; ***************************************************************************
; Merker_lesen -- Thalions Regel: Merker = erstes Wort von SAVES <> 0.
; Fehlt SAVES oder ist es zu kurz, bleibt der Merker 0.
;   Veraendert d0-d2/a0-a2/a4.
; ***************************************************************************
Merker_lesen:
	clr.b	Merker
	lea	Name_saves,a4
	bsr	Pfad_bauen		; zuerst AMBFILES\SAVES
	bsr.b	.oeffnen
	bpl.b	.offen
	lea	Name_saves,a0		; dann flach
	bsr.b	.oeffnen
	bmi.b	.aus
.offen:
	move.w	d0,-(sp)		; Handle fuer Fclose
	pea	Saves_wort
	move.l	#2,-(sp)
	move.w	d0,-(sp)
	move.w	#Fread,-(sp)
	trap	#1
	lea	12(sp),sp
	cmp.l	#2,d0
	bne.b	.zu
	tst.w	Saves_wort
	sne	Merker
.zu:	move.w	#Fclose,-(sp)		; das Handle liegt schon auf dem Stapel
	trap	#1
	addq.l	#4,sp
.aus:	rts
; a0 = Name -> d0 = Handle oder Fehler (Flags danach)
.oeffnen:
	clr.w	-(sp)			; nur lesen
	move.l	a0,-(sp)
	move.w	#Fopen,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	rts

; ***************************************************************************
; Pfad_bauen -- der Ordner vor den Namen a4 -> a0 (Pfad).
;   Veraendert a0-a2.
; ***************************************************************************
Pfad_bauen:
	lea	Pfad,a0
	move.l	a0,a2
	lea	Ordner,a1
.o:	move.b	(a1)+,(a2)+
	bne.b	.o
	subq.l	#1,a2
	move.l	a4,a1
.n:	move.b	(a1)+,(a2)+
	bne.b	.n
	rts

; ***************************************************************************
; Starten -- Programm a4 mit Befehlszeile a5 laden und starten.
;   OUT: d0 = Rueckgabewert des Programms oder Ladefehler (-1 bis -127).
;   Veraendert d0-d2/a0-a2.
; ***************************************************************************
Starten:
	bsr	Pfad_bauen		; zuerst AMBFILES\Name
	bsr.b	.pexec
	cmp.l	#EFILNF,d0
	beq.b	.flach
	cmp.l	#EPTHNF,d0
	bne.b	.pruefen
.flach:	move.l	a4,a0			; dann der blosse Name
	bsr.b	.pexec
.pruefen:
	; Nur "nicht gefunden" ist gewollt still; alles andere meldet der
	; Lader, und es geht trotzdem weiter.  Ladefehler sind kleine
	; GEMDOS-Nummern; tiefer ist es die Rueckgabe des Programms (-5000 ...).
	tst.l	d0
	bpl.b	.aus
	cmp.l	#-128,d0
	blt.b	.aus
	cmp.l	#EFILNF,d0
	beq.b	.aus
	cmp.l	#EPTHNF,d0
	beq.b	.aus
	move.l	d0,-(sp)
	pea	Text_fehler
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	a4,-(sp)
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	pea	Text_zeilenende
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	(sp)+,d0
.aus:	rts
; a0 = Pfad, a5 = Befehlszeile -> d0
.pexec:
	clr.l	-(sp)			; Umgebung erben
	move.l	a5,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)			; laden und starten
	move.w	#Pexec,-(sp)
	trap	#1
	lea	16(sp),sp
	rts

	SECTION	Lader_daten,data
; The program names are unique per machine, so Falcon and ST share one
; AMBFILES folder (tools/build_common.sh).  Order: fantasy intro, intro,
; engine, extro.
Namen_falcon:	dc.l	Name_fantasy,Name_intro,Name_engine,Name_extro
Namen_st:	dc.l	Name_fantasy_st,Name_intro_st,Name_engine_st,Name_extro_st
Name_fantasy:	dc.b	"FANTASY.TOS",0
Name_intro:	dc.b	"INTRO.TOS",0
Name_engine:	dc.b	"ENGINE.TOS",0
Name_extro:	dc.b	"EXTRO.TOS",0
Name_fantasy_st:	dc.b	"FANTSYST.TOS",0
Name_intro_st:	dc.b	"INTROST.TOS",0
Name_engine_st:	dc.b	"ENGINEST.TOS",0
Name_extro_st:	dc.b	"EXTROST.TOS",0
Name_saves:	dc.b	"SAVES",0
Ordner:		dc.b	"AMBFILES",92,0	; 92 = Rueckstrich
Leere_zeile:	dc.b	0,0		; Befehlszeile: Laenge 0
Zeile_intro:	dc.b	1,"0",0		; die Ziffer setzt der Lader
Zeile_engine:	dc.b	1,"0",0
Zeile_extro:	dc.b	1,"0",0
Text_nochmal:	dc.b	27,"E",13,10,"Das Ende noch einmal sehen? (J/N) ",0
Text_fehler:	dc.b	13,10,"AMBER: Fehler beim Start von ",0
Text_zeilenende:	dc.b	13,10,0
	even

	SECTION	Lader_bss,bss
Saves_wort:	ds.w	1
Namen:		ds.l	1		; Namen_falcon or Namen_st
Mch_wert:	ds.l	1
Pfad:		ds.b	32		; Ordner und ein 8.3-Name
Merker:		ds.b	1
	even
	ds.b	1024
Stapel_oben:

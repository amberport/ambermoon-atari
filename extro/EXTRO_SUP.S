; ***************************************************************************
; EXTRO_SUP.S -- Thalions Extro (Ambermoon_extro) auf dem Falcon: der
; Programmeinsprung und der Satz, den der Amiga-Lader uebergibt.  Die
; Amiga-Schicht darunter ist dieselbe wie beim Intro (amiga/AMIGA_RAHMEN.S;
; docs/11-Intro-Extro.md, 5).
;
; Thalions Programm (Hunks 1-6) nimmt der Bau unveraendert aus
; Ambermoon_extro (tools/amiga_programm.py extro), mit K1, K2 und K3.
;
; Die beiden Schirme liegen im Zielformat (Schirm_tabelle, docs/11 7.8):
; Der Videl zeigt sie direkt, Thalions Bildblit ($4AA) schreibt direkt
; hinein.  Mit der CPU schreibt Thalion nur an einer Stelle in die Schirme
; (Hintergrund in beide, $2CA); danach bringt Extro_nach_kopie sie ins Ziel.
; ***************************************************************************

; Der Rolltext laeuft ueber 256 Zeilen: auf 200 oder 240 Zeilen mittig.
ANZEIGE_MITTIG	equ	1

	SECTION	Extro_code,code

; ***************************************************************************
; start -- Programmeinsprung.
; ***************************************************************************
start:
	; Das Ende n (0-2) kommt als Befehlszeile, eine Ziffer; allein
	; gestartet oder mit etwas anderem Ende 0.  Thalions Lader rechnet n
	; aus der Rueckgabe des Spiels (docs/11, 5.5).
	move.l	4(sp),a0		; Basepage, Befehlszeile ab $80
	cmp.b	#1,$80(a0)
	bne.b	.ohne
	moveq	#0,d0
	move.b	$81(a0),d0
	sub.b	#'0',d0
	cmp.b	#2,d0
	bhi.b	.ohne
	move.b	d0,Uebergabe+4
.ohne:
	lea	Musik_datei,a0		; Thalion's music (AMIGA_MUSIK.S)
	lea	Musik_datei+9,a1
	bsr	Musik_laden
	clr.l	-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,Alter_ssp
	bsr	Notausgang_einhaengen	; Abbau auch nach Bomben (AMIGA_NOTAUS.S)

	bsr	Falcon_pruefen
	bne.b	.kein_falcon
	bsr	Amiga_einrichten
	bne.b	.kein_falcon
	lea	Extro_h5+$38,a0		; Thalion's "music on" ($222, $34C)
	bsr	Musik_mischen
	; Thalions Programm, wie der Amiga-Lader es ruft: a0 = Uebergabesatz,
	; zurueck d0 = 0 (docs/11, 5.2)
	lea	Uebergabe,a0
	jsr	Extro_h1
	move.w	d0,Rueckgabe
	bsr	Amiga_abraeumen
	bsr	Fehlende_melden
	bra.b	.ende
.kein_falcon:
	pea	Text_kein_falcon
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
	move.w	#-1,Rueckgabe
.ende:
	move.l	Alter_ssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	Rueckgabe,-(sp)
	move.w	#Pterm,-(sp)
	trap	#1

; ***************************************************************************
; Extro_nach_kopie -- K3 an $2EC: Thalion hat eben den Hintergrund in beide
; Schirme kopiert ($2CA, in den Zwischenspeicher).  Beide ins Ziel bringen,
; dann die drei Befehle, die der jmp ueberdeckt, und weiter bei $2F4.
; ***************************************************************************
Extro_nach_kopie:
	bsr	Alle_bringen		; alle Register bleiben
	move.l	(sp),a4			; Thalions move.l (sp),a4
	addq.l	#2,a4			; addq.l #2,a4
	jsr	Extro_h1+$5B2		; bsr $5B2
	jmp	Extro_h1+$2F4

; ***************************************************************************
; Extro_umschalten_1/2 -- K3 an $1E8 und $596: Thalions bsr $EBC (neue
; Copperliste, COP1LC), dann gleich die Bildbasis (Anzeige_sofort, T11).
; Danach der Befehl, dessen erstes Wort der jmp ueberdeckt.
; ***************************************************************************
Extro_umschalten_1:
	jsr	Extro_h1+$EBC		; bsr $EBC
	bsr	Anzeige_sofort
	jsr	Extro_h1+$F54		; bsr $F54 (auf den VBL warten)
	jmp	Extro_h1+$1F0

Extro_umschalten_2:
	jsr	Extro_h1+$EBC		; bsr $EBC
	bsr	Anzeige_sofort
	tst.w	Extro_h5+$3E		; tst.w $3E (Hunk 5); die Flags gelten bei $5A0
	jmp	Extro_h1+$5A0

	include	"AMIGA_RAHMEN.S"

; ***************************************************************************
; Daten
; ***************************************************************************
	SECTION	Extro_daten,data
; Der Satz, den der Amiga-Lader in a0 uebergibt (docs/11, 5.2): Zeiger auf
; den Musikspieler, dann das Ende (0-2; setzt start aus der Befehlszeile).
Uebergabe:
	dc.l	Musik_stumm
	dc.b	0
	even
; Thalions Schirme (docs/11 5.3, 7.8): 6:$2E90 und 51200 Byte dahinter,
; 320 x 256 x 5, Ebenen zeilenweise
Schirm_tabelle:
	SCHIRM	Extro_h6+$2E90,256,5
	SCHIRM	Extro_h6+$2E90+51200,256,5
	dc.l	0
	include	"amiga_rahmen_daten.i"
	include	"extro_musik.i"	; build: tools/musik_k1.py
Musik_datei:
	dc.b	"AMBFILES\EXTROMUS.DAT",0
	even

; ***************************************************************************
	SECTION	Extro_bss,bss
	include	"amiga_rahmen_bss.i"

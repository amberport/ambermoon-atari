; ***************************************************************************
; AMIGA_NOTAUS.S -- der Notausgang fuer Fantasy-Intro, Intro und Extro: der
; Abbau, wenn das Programm nicht ueber seinen eigenen Abbau endet.
;
; Muster aus engine/src/MAIN.S (Notausgang, Erkenntnis 272, T1).  TOS ruft
; etv_term ($408) in Pterm, bei jedem Programmende, auch nach Bomben: dann
; beendet TOS das Programm selbst mit Pterm.  Ohne diesen Abbau blieben
; unser VBL, der Mausvektor, die Trap-Vektoren und der Bildschirmmodus auf
; Code, der gleich nicht mehr im Speicher ist.
;
; Der Einbinder setzt NOTAUS_ABRAEUMEN auf seinen Abbau.  Der muss einen
; zweiten Aufruf vertragen (nach einem geordneten Ende ruft Pterm ihn noch
; einmal) und laesst im Notausgang GEMDOS weg (Im_notausgang): Pterm steht
; noch in GEMDOS.  XBIOS geht (T1, mittelbar belegt).  Die Merker dazu:
;   Ab_modus  Modus, Schirm und Farben sind umgestellt
;   Ab_maus   der Mausvektor ist unserer
;   Ab_vbl    der VBL ist unserer (Intro, Extro: auch $6C, trap #0, trap #8)
; Variablen: amiga_notaus_bss.i.
;
; Die Interrupts gehen fuer den Abbau auf Stufe 3: kam der Absturz aus einem
; Interrupt, stuende die Maske noch hoch, und das Vsync im Abbau wartete auf
; einen VBL, der nie kommt.  Vorher, bei gesperrten Interrupts, bekommt der
; VBL seinen alten Vektor zurueck, damit ein Absturz in unserem VBL sich
; nicht wiederholt (das Muster aus MAIN.S deckt diesen Fall nicht ab).
;
; Abbau schon im Absturz (T16, 2026-10-10): EmuTOS zeigt nach einem Absturz
; einen Text und wartet auf eine Taste, bevor es Pterm ruft.  Bis dahin
; liefen unser VBL, unser Modus und unsere Farben weiter, und die Taste kam
; nicht an.  Darum haengen wir uns auch vor die Absturzvektoren 2-8 (Bus-,
; Adressfehler, illegaler Befehl, Division durch null, CHK, TRAPV,
; Privileg).  Unser Halter baut ab, gibt die Vektoren zurueck und springt
; mit unveraenderten Registern und Stapel in den Halter von TOS.  So malt
; TOS 4.04 die Bomben auf den Desktop, und $380 bekommt seine Angaben wie
; bisher (BOMBEN.TOS).  Line-A und Line-F ($28, $2C) bleiben bei TOS: die
; braucht TOS selbst.  Merker Ab_absturz: die Vektoren sind unsere.
; ***************************************************************************

; Notausgang_einhaengen -- aus start, gleich nach Super: etv_term auf den
; Notausgang, den alten Vektor merken; die Absturzvektoren 2-8 auf
; Absturz_2 ... Absturz_8.
;   Veraendert d0-d2/a0-a2 (BIOS).
Notausgang_einhaengen:
	pea	Notausgang
	move.w	#ETV_TERM,-(sp)
	move.w	#Setexc,-(sp)
	trap	#13
	addq.l	#8,sp
	move.l	d0,Notaus_alt
	lea	VEK_ABSTURZ.w,a0
	lea	Absturz_alt,a1
	lea	Absturz_halter,a2
	moveq	#ABSTURZ_VEKTOREN-1,d0
.vek:	move.l	(a0),(a1)+
	move.l	(a2)+,(a0)+
	dbf	d0,.vek
	st	Ab_absturz
	rts

; Absturzvektoren_zurueck -- die Absturzvektoren wieder auf die von TOS.
; Bei gesperrten Interrupts.  Veraendert d0/a0/a1.
Absturzvektoren_zurueck:
	tst.b	Ab_absturz
	beq.b	.aus
	lea	VEK_ABSTURZ.w,a0
	lea	Absturz_alt,a1
	moveq	#ABSTURZ_VEKTOREN-1,d0
.vek:	move.l	(a1)+,(a0)+
	dbf	d0,.vek
	sf	Ab_absturz
.aus:	rts

; Notabbau -- der gemeinsame Teil von Notausgang und Absturz.  Kommt mit
; gesperrten Interrupts, geht auf Stufe 3 zurueck.  Veraendert alles.
Notabbau:
	bsr.b	Absturzvektoren_zurueck	; ein Absturz im Abbau geht gleich an TOS
	st	Im_notausgang
	tst.b	Ab_vbl
	beq.b	.vbl
	move.l	Alter_vbl,VEK_VBL.w	; der Abbau setzt ihn noch einmal
.vbl:	move.w	#$2300,sr
	bra	NOTAUS_ABRAEUMEN

Notausgang:
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	move.w	#$2700,sr
	bsr	Notabbau
	move.l	Notaus_alt,$408.w	; ohne TOS: Setexc ist BIOS
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d7/a0-a6
	move.l	Notaus_alt,-(sp)	; weiter an den vorigen Halter
	rts

; Absturz_2 ... Absturz_8 -- unsere Halter vor den Absturzvektoren.  Jeder
; merkt seine Nummer als Versatz in Absturz_alt, dann der gemeinsame Teil.
; Der Ausnahmerahmen bleibt unberuehrt, TOS liest ihn wie ohne uns.
Absturz_2:	move.w	#0*4,Absturz_nr
	bra.b	Absturz
Absturz_3:	move.w	#1*4,Absturz_nr
	bra.b	Absturz
Absturz_4:	move.w	#2*4,Absturz_nr
	bra.b	Absturz
Absturz_5:	move.w	#3*4,Absturz_nr
	bra.b	Absturz
Absturz_6:	move.w	#4*4,Absturz_nr
	bra.b	Absturz
Absturz_7:	move.w	#5*4,Absturz_nr
	bra.b	Absturz
Absturz_8:	move.w	#6*4,Absturz_nr

Absturz:
	move.w	sr,-(sp)		; Stufe beim Absturz, fuer den Halter von TOS
	move.w	#$2700,sr
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	Absturz_nr,d0
	lea	Absturz_alt,a0
	move.l	(a0,d0.w),Absturz_ziel	; vor Notabbau, der gibt die Vektoren zurueck
	bsr	Notabbau
	move.w	#$2700,sr
	movem.l	(sp)+,d0-d7/a0-a6
	move.w	(sp)+,sr
	move.l	Absturz_ziel,-(sp)	; in den Halter von TOS, Register wie beim Absturz
	rts

; Reihenfolge wie die Vektoren ab VEK_ABSTURZ
Absturz_halter:
	dc.l	Absturz_2,Absturz_3,Absturz_4,Absturz_5,Absturz_6,Absturz_7
	dc.l	Absturz_8

	IFD	ABSTURZTEST
; ---------------------------------------------------------------------------
; Absturz_pruefen -- Diagnoseschalter ABSTURZTEST (VASM_EXTRA=
; "-DABSTURZTEST=1"): nach ABSTURZ_NACH VBL ein illegaler Befehl, vier
; Bomben.  Danach muss der Notausgang den Desktop mit seinen Farben, Maus
; und Ruhe zurueckgeben.  Der VBL des Einbinders zaehlt Absturz_zaehler
; hoch.  Abstuerzen soll der Hauptablauf, nicht ein Interrupt: ueber
; Stufe 3 (etwa ein Blit aus Thalions VBL) wartet es auf den naechsten Aufruf.
;   Alle Register bleiben.
ABSTURZ_NACH	equ	250		; 5 Sekunden bei 50 Hz
Absturz_pruefen:
	cmp.l	#ABSTURZ_NACH,Absturz_zaehler
	blo.b	.aus
	move.w	sr,-(sp)
	and.w	#$0700,(sp)
	cmp.w	#$0300,(sp)+
	bhi.b	.aus
	illegal
.aus:	rts
	ENDC

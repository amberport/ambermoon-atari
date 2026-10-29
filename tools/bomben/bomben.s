; ***************************************************************************
; BOMBEN.TOS -- zeigt, was TOS beim letzten Absturz abgelegt hat.
;
; Nach den Bomben direkt vom Desktop starten (2026-10-02, Absturz von
; ENGINE.TOS auf dem Falcon, den Hatari nicht zeigt).  TOS legt bei jeder
; Ausnahme, die Bomben zeigt, ab $380 ab (Atari, "post-mortem"):
;
;   $380  proc_lives  $12345678, wenn der Satz gueltig ist
;   $384  proc_dregs  d0-d7
;   $3A4  proc_aregs  a0-a7 (a7 = Supervisorstapel beim Absturz)
;   $3C4  proc_enum   erstes Byte: Nummer der Ausnahme (= Zahl der Bomben)
;   $3C8  proc_usp    Benutzerstapel
;   $3CC  proc_stk    16 Worte vom Supervisorstapel: der Ausnahmerahmen
;
; Der Rahmen des 68030 beginnt mit SR (Wort), PC (Langwort), Format und
; Vektor (Wort).  Bei Format $A und $B (Bus- und Adressfehler) steht die
; Adresse, auf die zugegriffen wurde, im Langwort ab Wort 8.
;
; Damit sich der PC einer Routine zuordnen laesst, sucht das Programm
; ausserdem die Engine im Speicher: Nach dem Absturz liegt sie noch dort.
; Gesucht wird "FILE COULDN'T BE LOADED" (Ladefehler_text, in den Daten
; der Engine, weit hinter dem Anfang, den dieses Programm selbst
; ueberschreiben kann).  Aus dem Fundort und der Symbolkarte des Baus
; ergibt sich die Ladeadresse.
;
; Derselbe Bericht geht nach BOMBEN.TXT, in den Ordner, aus dem das
; Programm startet: zum Abschreiben ohne Abtippen.
;
; Reiner 68000-Code, laeuft auch auf dem ST.
; ***************************************************************************

Cconin		equ	1
Cconws		equ	9
Super		equ	32
Pterm0		equ	0
Fcreate		equ	60
Fwrite		equ	64
Fclose		equ	62

	SECTION	text,code

start:
	clr.l	-(sp)			; Supervisor: $380 und der ganze Speicher
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,alter_stapel

	pea	t_cls(pc)		; Schirm leeren, nicht in die Datei
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	lea	t_kopf(pc),a0
	bsr	Text
	cmp.l	#$12345678,$380.w
	beq.b	gueltig
	lea	t_ungueltig(pc),a0
	bsr	Text
gueltig:
	; Hoechstens 40 Zeichen je Zeile: der Desktop kann in ST-niedrig stehen.
	lea	t_ausnahme(pc),a0	; Nummer der Ausnahme
	bsr	Text
	moveq	#0,d0
	move.b	$3C4.w,d0
	moveq	#2,d1
	bsr	Hex
	lea	t_art(pc),a0
	bsr	Text
	lea	t_pc(pc),a0		; PC, SR, Format
	bsr	Text
	move.l	$3CE.w,d0
	moveq	#8,d1
	bsr	Hex
	lea	t_sr(pc),a0
	bsr	Text
	move.w	$3CC.w,d0
	moveq	#4,d1
	bsr	Hex
	bsr	Zeile
	lea	t_format(pc),a0
	bsr	Text
	move.w	$3D2.w,d0
	moveq	#4,d1
	bsr	Hex
	bsr	Zeile
	move.w	$3D2.w,d0		; Format $A oder $B: Fehleradresse
	rol.w	#4,d0
	and.w	#$F,d0
	cmp.w	#$A,d0
	beq.b	mit_adresse
	cmp.w	#$B,d0
	bne.b	ohne_adresse
mit_adresse:
	lea	t_fehler(pc),a0
	bsr	Text
	move.l	$3DC.w,d0
	moveq	#8,d1
	bsr	Hex
	lea	t_ssw(pc),a0
	bsr	Text
	move.w	$3D6.w,d0
	moveq	#4,d1
	bsr	Hex
	bsr	Zeile
ohne_adresse:
	lea	$384.w,a3		; d0-d7, a0-a7: je Zeile zwei
	moveq	#"D",d4
	bsr	Register
	moveq	#"A",d4
	bsr	Register
	lea	t_usp(pc),a0
	bsr	Text
	move.l	$3C8.w,d0
	moveq	#8,d1
	bsr	Hex
	bsr	Zeile
	lea	t_stapel(pc),a0		; der Rahmen, 16 Worte, je Zeile sechs
	bsr	Text
	lea	$3CC.w,a3
	moveq	#0,d3
stapel_l:
	move.w	(a3)+,d0
	moveq	#4,d1
	bsr	Hex
	lea	t_leer(pc),a0
	bsr	Text
	addq.w	#1,d3
	cmp.w	#16,d3
	beq.b	stapel_e
	cmp.w	#6,d3
	beq.b	stapel_z
	cmp.w	#12,d3
	bne.b	stapel_l
stapel_z:
	bsr	Zeile
	lea	t_einzug(pc),a0
	bsr	Text
	bra.b	stapel_l
stapel_e:
	bsr	Zeile

	; ---- die Engine im Speicher suchen ----
	lea	t_suche(pc),a0
	bsr	Text
	lea	$800.w,a3		; ab hier liegt kein Systembereich mehr
	move.l	$42E.w,a4		; phystop: Ende des ST-RAM
	sub.w	#32,a4
	moveq	#0,d4			; Funde
	lea	s_marke(pc),a2
	move.b	(a2),d2			; erstes Zeichen
such_l:
	cmp.l	a4,a3
	bcc.b	such_ende
	cmp.b	(a3)+,d2
	bne.b	such_l
	lea	-1(a3),a0		; Kandidat
	lea	s_marke(pc),a1
such_v:	move.b	(a1)+,d0
	beq.b	such_fund
	cmp.b	(a0)+,d0
	beq.b	such_v
	bra.b	such_l
such_fund:
	cmp.l	#s_marke,a3		; uns selbst nicht zaehlen
	bls.b	such_wir
	cmp.l	#s_marke_ende,a3
	bls.b	such_l
such_wir:
	lea	t_fund(pc),a0
	bsr	Text
	move.l	a3,d0
	subq.l	#1,d0
	moveq	#8,d1
	bsr	Hex
	bsr	Zeile
	addq.w	#1,d4
	cmp.w	#4,d4
	bcs.b	such_l
such_ende:
	tst.w	d4
	bne.b	such_da
	lea	t_nichts(pc),a0
	bsr	Text
such_da:
	bsr	Datei_schreiben
	lea	t_taste(pc),a0
	bsr	Text
	move.w	#Cconin,-(sp)
	trap	#1
	addq.l	#2,sp

	move.l	alter_stapel,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	clr.w	-(sp)
	trap	#1

; ---- acht Register ab a3, d4 = "D" oder "A"; je Zeile zwei ----
Register:
	move.b	#" ",reg_name+2		; "D0 ", Endnull steht schon (BSS)
	moveq	#0,d3
reg_l:	move.b	d4,reg_name
	move.b	d3,d0
	add.b	#"0",d0
	move.b	d0,reg_name+1
	lea	reg_name,a0
	bsr	Text
	move.l	(a3)+,d0
	moveq	#8,d1
	bsr	Hex
	addq.w	#1,d3
	btst	#0,d3
	bne.b	reg_w
	bsr	Zeile
	bra.b	reg_n
reg_w:	lea	t_zwei(pc),a0
	bsr	Text
reg_n:	cmp.w	#8,d3
	bne.b	reg_l
	rts

; ---- d0 hexadezimal, d1 Stellen (rechtsbuendig aus d0) ----
Hex:
	movem.l	d0-d2/a0,-(sp)
	lea	hex_puffer+8,a0
	clr.b	(a0)
	move.w	d1,d2
	subq.w	#1,d2
hex_l:	move.w	d0,d1
	and.w	#$F,d1
	move.b	ziffern(pc,d1.w),-(a0)
	lsr.l	#4,d0
	dbf	d2,hex_l
	bsr.b	Text
	movem.l	(sp)+,d0-d2/a0
	rts
ziffern:
	dc.b	"0123456789ABCDEF"

Zeile:
	move.l	a0,-(sp)
	lea	t_zeile(pc),a0
	bsr.b	Text
	move.l	(sp)+,a0
	rts

; ---- den Bericht nach BOMBEN.TXT; meldet, ob es ging ----
Datei_schreiben:
	movem.l	d0-d2/a0-a2,-(sp)
	clr.w	-(sp)
	pea	t_name(pc)
	move.w	#Fcreate,-(sp)
	trap	#1
	addq.l	#8,sp
	tst.l	d0
	bmi.b	ds_fehler
	move.w	d0,d2			; Kennung
	move.l	bericht_ende,d1
	sub.l	#bericht,d1
	pea	bericht
	move.l	d1,-(sp)
	move.w	d2,-(sp)
	move.w	#Fwrite,-(sp)
	trap	#1
	lea	12(sp),sp
	move.w	d2,-(sp)
	move.w	#Fclose,-(sp)
	trap	#1
	addq.l	#4,sp
	lea	t_datei_ok(pc),a0
	bra.b	ds_melden
ds_fehler:
	lea	t_datei_nein(pc),a0
ds_melden:
	bsr.b	Text
	movem.l	(sp)+,d0-d2/a0-a2
	rts

; ---- Text a0 mit Endnull ausgeben und in den Bericht; Register bleiben ----
Text:
	movem.l	d0-d2/a0-a2,-(sp)
	move.l	bericht_ende,a1		; mitschreiben, solange Platz ist
	cmp.w	#0,a1
	bne.b	tx_da
	lea	bericht,a1
tx_da:	move.l	a0,a2
tx_l:	tst.b	(a2)
	beq.b	tx_ende
	cmp.l	#bericht+BERICHT_MAX,a1
	bcc.b	tx_ende
	move.b	(a2)+,(a1)+
	bra.b	tx_l
tx_ende:
	move.l	a1,bericht_ende
	move.l	a0,-(sp)
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	movem.l	(sp)+,d0-d2/a0-a2
	rts

t_cls:		dc.b	27,"E",0
t_kopf:		dc.b	"BOMBEN: der letzte Absturz",13,10,13,10,0
t_name:		dc.b	"BOMBEN.TXT",0
t_datei_ok:	dc.b	"In BOMBEN.TXT geschrieben.",13,10,0
t_datei_nein:	dc.b	"BOMBEN.TXT ging nicht.",13,10,0
t_ungueltig:	dc.b	"($380 ungueltig: kein Absturz?)",13,10,0
t_ausnahme:	dc.b	"Ausnahme $",0
t_art:		dc.b	" (2 Bus,3 Adr,4 Befehl)",13,10,0
t_pc:		dc.b	"PC $",0
t_sr:		dc.b	"  SR $",0
t_format:	dc.b	"Format/Vektor $",0
t_fehler:	dc.b	"Zugriff $",0
t_ssw:		dc.b	"  SSW $",0
t_einzug:	dc.b	"       ",0
t_zwei:		dc.b	"  ",0
t_usp:		dc.b	"USP $",0
t_stapel:	dc.b	"Rahmen ",0
t_leer:		dc.b	" ",0
t_zeile:	dc.b	13,10,0
t_suche:	dc.b	"Engine (Ladefehler_text):",13,10,0
t_fund:		dc.b	"  bei $",0
t_nichts:	dc.b	"  nicht gefunden",13,10,0
t_taste:	dc.b	"Bitte fotografieren. Taste ...",0
s_marke:	dc.b	"FILE COULDN'T BE LOADED",0
s_marke_ende:
	even

BERICHT_MAX	equ	4096

	SECTION	bss,bss
bericht_ende:	ds.l	1		; 0: noch leer
bericht:	ds.b	BERICHT_MAX
alter_stapel:	ds.l	1
hex_puffer:	ds.b	10
reg_name:	ds.b	4

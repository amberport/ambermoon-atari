; ***************************************************************************
; FEE_SUP.S -- die Amiga-Schicht unter Thalions FAIRY.S (Fantasy-Intro).
;
; **Wer was macht** (docs/11-Intro-Extro.md, 3 und 7):
;
;   Thalions FAIRY.S        Fee, Flugstaub, Sterne, Zauber, level3.  Unveraendert.
;   Thalions Hunk-1-Code    Blenden, Schirmtausch, Tabellen: beim Bau aus
;                           Fantasy_intro herausgezogen (fantasy_auszug.py).
;   diese Datei             alles, was auf dem Amiga an Copper, CIA, Sprites,
;                           Blitter und Betriebssystem hing -- nach Thalions
;                           Vertrag, in Thalions Reihenfolge (Hunk 1 $110-$2B0).
;
; **K1:** FAIRY.S schreibt nach $DFFxxx.  tools/fairy_umbiegen.py biegt nach
; dem Binden genau diese zehn Operanden auf Amiga_register um.  Was dort
; ankommt (Palette, Spritezeiger, Blitterregister), setzt diese Datei um.
;
; **Das Bild:** FAIRY.S zeichnet in Amiga-Puffer (5 Ebenen zeilenverschachtelt,
; bpscanl je Zeile).  Jeder Amiga-Puffer hat einen Falcon-Zwilling (8 Ebenen
; wortverschachtelt).  Ebene 5 traegt die Bank: 0 bis Zeile WECHSELZEILE-1,
; 1 ab da (dort laedt die Copperliste sechs Farben neu).  Ebenen 5 bis 7
; stehen fest und werden nie umgesetzt.
;
; **Der Blitter** (Falcon-Blitter, wie im STE): setzt Amiga-Zeilen auf den
; Falcon-Zwilling um (Ebenen_umsetzen) und stanzt die Fee ein (Fee_sprites),
; immer im HOG-Modus (Blit_starten).  Der VBL blittet auch; er wartet, bis
; der Blitter frei ist, und stellt dessen Register danach wieder her, damit
; ein halb eingerichteter Blit des Hauptablaufs nichts merkt.
;
; Schalter (VASM_EXTRA):  FEE_CPU     Zeilen mit der CPU umsetzen statt
;                                     mit dem Blitter (Vergleich)
;                         FEE_MESSEN  am Ende zaehlen, wie viele Bilder
;                                     knapp oder zu spaet fertig wurden
;
; Stand F3: Thalions Blits (Sterne, Schriftzug) laufen durch Amiga_blit,
; den Amiga-Blitter in der CPU.
; ***************************************************************************

	SECTION	Fee_code,code

; ***************************************************************************
; start -- Programmeinsprung.
; ***************************************************************************
start:
	clr.l	-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.l	d0,Alter_ssp
	bsr	Notausgang_einhaengen	; Abbau auch nach Bomben (AMIGA_NOTAUS.S)

	bsr	Falcon_pruefen
	bne.b	.kein_falcon
	bsr	Fee_einrichten
	bne.b	.kein_falcon
	ifd	AMIGA_MESSEN
	bsr	Mess_starten
	endc
	bsr	Fee_ablauf
	ifd	AMIGA_MESSEN
	bsr	Mess_stoppen
	endc
	bsr	Fee_abraeumen
	ifd	AMIGA_MESSEN
	bsr	Mess_ausgeben		; vor Messung_zeigen: beide warten auf
	endc				; eine Taste, die Datei soll zuerst
	ifd	FEE_MESSEN
	bsr	Messung_zeigen
	endc
	bra	.ende
.kein_falcon:
	pea	Text_kein_falcon
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
.ende:
	move.l	Alter_ssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Pterm0,-(sp)
	trap	#1

; ***************************************************************************
; Falcon_pruefen -- Z gesetzt, wenn der Cookie _MCH einen Falcon meldet.
; ***************************************************************************
Falcon_pruefen:
	move.l	$5A0.w,d0
	beq.b	.nein
	move.l	d0,a0
.such:	move.l	(a0),d0
	beq.b	.nein
	cmp.l	#'_MCH',d0
	beq.b	.da
	addq.l	#8,a0
	bra.b	.such
.da:	cmp.w	#3,4(a0)		; $0003xxxx = Falcon
	rts
.nein:	moveq	#1,d0			; Z aus
	rts

; ***************************************************************************
; Fee_einrichten -- Modus, Zeilenzahl, Schirme, Maus.  Das Gegenstueck zu
; Thalions Start ($000-$10E: Betriebssystem abschalten).
;   Z gesetzt: bereit.  Sonst ein Monitor, den wir nicht bedienen.
;
; **Zeilen (Nutzer, 2026-09-29):** RGB mit PAL (fest, 2026-10-03), und dort
; die vollen 256 Zeilen, wenn der Videl sich darauf ziehen laesst (Videl_256).  Sonst 200 Zeilen und ein
; Ausschnitt ab Anzeige_erste.  An VGA 240 Zeilen, ohne 8 oben und unten.
; ***************************************************************************
Fee_einrichten:
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
	; RGB oder Fernseher: immer PAL, 50 Hz wie Thalions Amiga (Nutzer,
	; 2026-10-03: Takt und Bildzeit wie geplant), ohne Zeilensprung
	move.w	#VM_PAL+VM_BPS8,d0
	move.w	#200,Anzeige_zeilen
	move.w	#28,Anzeige_erste
	bra.b	.setzen
.vga:	move.w	#VM_VGA+VM_VERTFLAG+VM_BPS8,d0
	move.w	#240,Anzeige_zeilen
	move.w	#8,Anzeige_erste
.setzen:
	move.w	d0,Neuer_modus

	; Farben des Desktops sichern, *vor* dem Umschalten (Erkenntnis 77)
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

	; Falcon-Schirme: 256-Byte-Grenze, im ST-RAM (BSS eines TOS-Programms)
	move.l	#Falcon_speicher+255,d0
	and.l	#-256,d0
	move.l	d0,Falcon_a
	add.l	#FALCON_SCHIRM,d0
	move.l	d0,Falcon_b

	move.w	#-1,-(sp)
	move.l	Falcon_a,-(sp)
	move.l	Falcon_a,-(sp)
	move.w	#Setscreen,-(sp)
	trap	#14
	lea	12(sp),sp
	move.w	#XB_Vsync,-(sp)
	trap	#14
	addq.l	#2,sp

	; 256 Zeilen nur an RGB/Fernsehen mit PAL
	move.w	Neuer_modus,d0
	and.w	#VM_VGA+VM_PAL,d0
	cmp.w	#VM_PAL,d0
	bne.b	.zeilen_fest
	bsr	Videl_256
	bne.b	.zeilen_fest
	move.w	#AMIGA_ZEILEN,Anzeige_zeilen
	clr.w	Anzeige_erste
.zeilen_fest:

	move.l	Falcon_a,a0
	bsr	Bankebene_setzen
	move.l	Falcon_b,a0
	bsr	Bankebene_setzen

	; Maus: nur die Tasten, wie Thalions btst #6,$bfe001
	move.w	#Kbdvbase,-(sp)
	trap	#14
	addq.l	#2,sp
	move.l	d0,a0
	move.l	16(a0),Alter_mausvektor
	move.l	a0,Kbd_vektoren
	move.l	#Fee_maus,16(a0)
	st	Ab_maus
	moveq	#0,d0			; Z: bereit
	rts
.nein:	moveq	#1,d0
	rts

; ***************************************************************************
; Videl_256 -- den Videl von 200 auf 256 Zeilen ziehen: je 28 Zeilen oben
; und unten.  Die senkrechten Register zaehlen Halbzeilen, eine Zeile sind
; zwei.  Grenzen: VBE <= VDB < VDE <= VBB < VSS.  Passt es nicht, bleibt
; alles, wie TOS es gesetzt hat.
;   Z gesetzt: 256 Zeilen.  Aufruf gleich nach einem Vsync.
; ***************************************************************************
Videl_256:
	move.w	V_VDB,d0
	sub.w	#56,d0
	cmp.w	#32,d0			; nach dem Synchronimpuls etwas Luft
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
; Bankebene_setzen -- Ebene 5 eines Falcon-Schirms: $FFFF ab der Zeile, die
; der Amiga-Zeile WECHSELZEILE entspricht.  Ebenen 6 und 7 bleiben 0.
;   IN : a0 = Falcon-Schirm
; ***************************************************************************
Bankebene_setzen:
	move.w	#WECHSELZEILE,d0
	sub.w	Anzeige_erste,d0
	bpl.b	.ab
	moveq	#0,d0
.ab:	move.w	Anzeige_zeilen,d1
	sub.w	d0,d1			; so viele Zeilen in Bank 1
	ble.b	.aus
	mulu.w	#FALCON_ZEILE,d0
	lea	10(a0,d0.l),a0		; Ebene 5 der ersten Gruppe
	mulu.w	#FALCON_ZEILE/16,d1
	subq.w	#1,d1
.gr:	move.w	#-1,(a0)
	lea	16(a0),a0
	dbf	d1,.gr
.aus:	rts

; ***************************************************************************
; Fee_abraeumen -- alles zurueck, wie es vor dem Start war.
;
; Wiederholbar (Notausgang, AMIGA_NOTAUS.S): jeder Schritt nur, wenn sein
; Merker steht, und loescht ihn.  Im Notausgang ohne GEMDOS (Textcursor).
; ***************************************************************************
Fee_abraeumen:
	tst.b	Ab_vbl
	beq.b	.maus
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	Alter_vbl,VEK_VBL.w
	sf	Ab_vbl
	move.w	(sp)+,sr
.maus:	tst.b	Ab_maus
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

	; beide Farbsaetze zurueck, der massgebliche zuletzt (FALCON.S)
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

; Fee_notabbau -- der Abbau fuer den Notausgang: im geordneten Ende haelt
; start die Messung vor Fee_abraeumen an.
Fee_notabbau:
	ifd	AMIGA_MESSEN
	bsr	Mess_stoppen
	endc
	bra	Fee_abraeumen

NOTAUS_ABRAEUMEN	equ	Fee_notabbau
	include	"AMIGA_NOTAUS.S"

; ***************************************************************************
; Fee_ablauf -- Thalions Hauptablauf (Hunk 1 $110-$2B0), nachgeschrieben,
; weil er an Copper, CIA und DMA haengt.  Reihenfolge und Werte wie dort; die
; Adressen in Klammern sind die Stellen in Hunk 1.
; ***************************************************************************
Fee_ablauf:
	bsr	Hardware_einrichten	; ($D22)
	bsr	Schirme_einrichten	; ($C2C)
	; Hintergrund auf beide Schirme ($118)
	lea	background,a0
	move.l	Schirm_zeigen,a1
	move.l	Schirm_arbeit,a2
	move.w	#AMIGA_SCHIRM/4-1,d7
.hg:	move.l	(a0)+,d0
	move.l	d0,(a1)+
	move.l	d0,(a2)+
	dbf	d7,.hg
	move.l	Schirm_zeigen,a0	; unser: beide ganz auf den Falcon
	moveq	#0,d0
	move.w	#AMIGA_ZEILEN,d1
	bsr	Zeilen_umsetzen
	move.l	Schirm_arbeit,a0
	moveq	#0,d0
	move.w	#AMIGA_ZEILEN,d1
	bsr	Zeilen_umsetzen
	jsr	vsync
	; ($144) Startwerte
	move.w	#160,posx
	move.w	#100,posy
	lea	plot_buffer,a0
	move.w	#funkel_anz-1,d7
.pb:	move.w	#-1,(a0)
	add.w	#funkel_size,a0
	dbf	d7,.pb
	lea	plot_buffer2,a0
	move.w	#funkel_anz2-1,d7
.pb2:	clr.l	(a0)
	add.w	#funkel_size2,a0
	dbf	d7,.pb2
	lea	magic_buffer,a0
	move.w	#star_anz-1,d7
.mb:	move.w	#-1,(a0)
	addq.l	#6,a0
	dbf	d7,.mb
	clr.w	elfe_ani
	clr.w	elfe_anidelay
	clr.w	elfe_fcount
	move.w	#2,elfe_fdelay
	clr.w	leave_flag
	clr.w	magic_doit
	move.w	#-1,magic_x
	move.l	#Flugbahn,elfe_kptr
	; ($1D0) einblenden: 15 Schritte, je zwei Bilder
	moveq	#14,d6
.ein:	jsr	vsync
	jsr	vsync
	lea	Palette_oben_quelle,a0
	lea	palette0,a1
	moveq	#32,d7
	bsr	Farben_einblenden
	lea	Palette_unten_quelle,a0
	lea	Palette_unten,a1
	moveq	#32,d7
	bsr	Farben_einblenden
	dbf	d6,.ein
	; ($20A) bis zu 50 Bilder warten, Maustaste bricht ab
	moveq	#50,d7
.warte:	jsr	vsync
	bsr	Maustaste
	dbne	d7,.warte
	move.w	#-1,vbl_flag		; ($21E) jetzt fliegt die Fee
; ($226) die Schleife: drei VBL je Bild (vindex >= 2, dann vsync)
.bild:
	ifd	ABSTURZTEST
	bsr	Absturz_pruefen
	endc
	bsr	Schirme_tauschen
	bsr	Anzeige_setzen		; ($C98, Copperliste)
	jsr	vsync
	clr.l	vindex
	bsr	Unten_herstellen	; ($BC0)
	jsr	make_funkel
	jsr	make_funkel2
	jsr	make_magic
	bsr	Blitter_warten		; unser: den letzten Blit ausfuehren
	move.l	workbase,a0		; unser: was sich geaendert hat
	ifd	STRAHL
	bsr	Zwilling
	move.l	a1,St_uz_schirm
	move.w	#WECHSELZEILE,d0
	sub.w	Anzeige_erste,d0
	move.w	d0,St_uz
	endc
	STRAHL_VOR St_umsetzen
	move.w	#WECHSELZEILE,d0
	move.w	#AMIGA_ZEILEN-WECHSELZEILE,d1
	bsr	Zeilen_umsetzen
	STRAHL_NACH St_umsetzen,St_uz_schirm,St_uz,#AMIGA_ZEILEN-WECHSELZEILE
	ifd	FEE_MESSEN
	bsr	Bild_messen
	endc
.takt:	cmp.l	#2,vindex
	blt.b	.takt
	; ($254) Maustaste: in 16 Bildern ausblenden
	bsr	Maustaste
	beq.b	.keine
	tst.w	leave_flag
	beq.b	.setzen
	cmp.w	#16,leave_flag
	ble.b	.keine
.setzen:
	move.w	#16,leave_flag
.keine:	tst.w	leave_flag
	beq	.bild
	subq.w	#1,leave_flag
	beq.b	.aus
	cmp.w	#16,leave_flag
	bge	.bild
	lea	palette0,a0
	moveq	#32,d7
	bsr	Farben_ausblenden
	lea	Palette_unten,a0
	moveq	#32,d7
	bsr	Farben_ausblenden
	bra	.bild
.aus:	rts

; ***************************************************************************
; Hardware_einrichten -- ($D22) level3 als VBL, Anfangsfarben, vbl_flag aus.
;
; Auf dem Amiga ist level3 der Level-3-Interrupt.  Hier springt Fee_vbl
; hinein, mit dem Ausnahmerahmen des Falcon-VBL auf dem Stapel: Thalions
; rte kehrt damit richtig zurueck.
; ***************************************************************************
Hardware_einrichten:
	movem.l	Anfangsfarben,d0-d7
	movem.l	d0-d7,Amiga_register+AR_COLOR00
	movem.l	d0-d7,Amiga_register+AR_COLOR00+32
	clr.w	vbl_flag
	move.w	sr,-(sp)
	or.w	#$0700,sr
	move.l	VEK_VBL.w,Alter_vbl
	move.l	#Fee_vbl,VEK_VBL.w
	st	Ab_vbl
	move.w	(sp)+,sr
	rts

; ***************************************************************************
; Schirme_einrichten -- ($C2C) zwei Amiga-Schirme; gezeichnet wird in
; Schirm_arbeit (= workbase), gezeigt Schirm_zeigen.
; ***************************************************************************
Schirme_einrichten:
	move.l	#Amiga_schirme,d0
	move.l	d0,Schirm_arbeit
	move.l	d0,workbase
	add.l	#AMIGA_SCHIRM,d0
	move.l	d0,Schirm_zeigen
	bsr	Anzeige_setzen
	jmp	vsync

; ***************************************************************************
; Anzeige_setzen -- (copper list $C98) show Schirm_zeigen, i.e. its Falcon
; twin, from the next frame on.  The picture base is written right here:
; the Videl latches it before our VBL, written from Fee_vbl it would only
; take effect one frame later (T11, docs/11 7.8).  Fee_vbl writes it once
; more, with the same value.
; The fairy is drawn into the new screen first.  Otherwise the first frame
; shows it without the fairy until Fee_vbl draws it; Hatari, which renders
; the whole frame at the VBL, showed exactly that as flicker (docs/11 7.8).
; ***************************************************************************
Anzeige_setzen:
	move.l	Schirm_zeigen,a0
	bsr	Zwilling
	movem.l	d0-d7/a0-a6,-(sp)
	move.w	sr,-(sp)
	or.w	#$0700,sr		; Fee_vbl uses the same sprite state
	move.l	a1,Anzeige_naechste
	move.l	a1,a0
	bsr	Fee_sprites
	move.w	(sp)+,sr
	movem.l	(sp)+,d0-d7/a0-a6
	movem.l	d0-d1,-(sp)
	move.l	a1,d0
	move.l	d0,d1
	swap	d1
	move.b	d1,V_BASIS_H
	move.w	d0,d1
	lsr.w	#8,d1
	move.b	d1,V_BASIS_M
	move.b	d0,V_BASIS_L
	movem.l	(sp)+,d0-d1
	rts

; ***************************************************************************
; Zwilling -- a0 = Amiga-Schirm -> a1 = sein Falcon-Schirm.
; ***************************************************************************
Zwilling:
	move.l	Falcon_a,a1
	cmp.l	#Amiga_schirme,a0
	beq.b	.a
	move.l	Falcon_b,a1
.a:	rts

; ***************************************************************************
; Unten_herstellen -- ($BC0) Thalions Blit: die Zeilen ab WECHSELZEILE aus
; dem Hintergrund in den Arbeitsschirm.  Dort fallen Staub und Sterne, und
; dort schreibt make_magic den Schriftzug in den Hintergrund.
; ***************************************************************************
Unten_herstellen:
	lea	background+WECHSELZEILE*bpscanl,a0
	move.l	workbase,a1
	add.l	#WECHSELZEILE*bpscanl,a1
	move.w	#(AMIGA_ZEILEN-WECHSELZEILE)*bpscanl/16-1,d7
.k:	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	move.l	(a0)+,(a1)+
	dbf	d7,.k
	rts

; ***************************************************************************
; Zeilen_umsetzen -- Amiga-Zeilen auf den Falcon-Zwilling.
;   IN : a0 = Amiga-Schirm, d0.w = erste Zeile, d1.w = Anzahl
;   Nur, was im Ausschnitt Anzeige_erste/Anzeige_zeilen liegt.  Ebenen 0-4
;   aus den fuenf Amiga-Zeilen, 5-7 bleiben (Bankebene_setzen).
;   Veraendert d0-d5/d7/a0-a3.
; ***************************************************************************
Zeilen_umsetzen:
	bsr.b	Zwilling
	move.w	Anzeige_erste,d2
	cmp.w	d2,d0			; oben abschneiden
	bge.b	.o
	sub.w	d0,d2
	sub.w	d2,d1
	move.w	Anzeige_erste,d0
.o:	move.w	d0,d2
	add.w	d1,d2
	sub.w	Anzeige_erste,d2
	sub.w	Anzeige_zeilen,d2	; unten abschneiden
	ble.b	.u
	sub.w	d2,d1
.u:	subq.w	#1,d1
	bmi.b	.aus
	move.w	d0,d2
	mulu.w	#bpscanl,d2
	add.l	d2,a0
	sub.w	Anzeige_erste,d0
	mulu.w	#FALCON_ZEILE,d0
	add.l	d0,a1
	ifnd	FEE_CPU
	addq.w	#1,d1
	moveq	#GRUPPEN,d3
	bra	Ebenen_umsetzen
	endc
.zeile:	move.l	a0,a2
	move.l	a1,a3
	moveq	#FALCON_ZEILE/16-1,d7
.gr:	move.w	(a2),(a3)+
	move.w	40(a2),(a3)+
	move.w	80(a2),(a3)+
	move.w	120(a2),(a3)+
	move.w	160(a2),(a3)+
	addq.l	#6,a3
	addq.l	#2,a2
	dbf	d7,.gr
	lea	bpscanl(a0),a0
	lea	FALCON_ZEILE(a1),a1
	dbf	d1,.zeile
.aus:	rts

; ***************************************************************************
; Blitter_warten -- waitblit (fee_vorspann.i).  Fuehrt den Blit aus, den
; FAIRY.S zuletzt in Amiga_register eingetragen hat (BLTSIZE ungleich 0).
;   Alle Register bleiben.
;
; Auf dem Amiga startet das Schreiben von BLTSIZE den Blit, und waitblit
; wartet auf sein Ende.  Hier ist BLTSIZE nur eine Speicherstelle; der Blit
; laeuft beim naechsten waitblit, also bevor FAIRY.S die Register fuer den
; naechsten beschreibt.  Den letzten eines Bildes stoesst Fee_ablauf an.
; Was die CPU dazwischen zeichnet (Flugstaub), kommt damit vor den Blit
; statt danach; das betrifft nur Punkte, die sich ueberdecken.
; ***************************************************************************
Blitter_warten:
	tst.w	Amiga_register+AR_BLTSIZE
	bne.b	.blit
	rts
.blit:	movem.l	d0-d7/a0-a6,-(sp)
	bsr	Amiga_blit
	clr.w	Amiga_register+AR_BLTSIZE
	movem.l	(sp)+,d0-d7/a0-a6
	rts

	include	"AMIGA_BLIT.S"
Mess_blit_ende:				; AMIGA_MESSEN: Blitter_warten bis hier = Blits

; ***************************************************************************
; Maustaste -- Z aus, wenn die linke Taste gedrueckt ist.  Thalion fragt
; btst #6,$bfe001 (gedrueckt = 0); die Bedingung ist hier umgedreht.
; ***************************************************************************
Maustaste:
	btst	#1,Maustasten
	rts

; Fee_maus -- Mausvektor (Kbdvbase+16), a0 = IKBD-Paket.  Kopf $F8-$FB:
; Bit 1 links, Bit 0 rechts.
Fee_maus:
	move.b	(a0),Maustasten
	rts

; ***************************************************************************
; Fee_vbl -- der VBL.  Setzt Bildbasis, Farben und Sprites aus dem, was der
; vorige VBL und der Hauptablauf hinterlassen haben, und springt dann in
; Thalions level3 (FAIRY.S).  level3 endet mit rte.
;
; Die Sprites stehen damit ein Bild hinter level3: Auf dem Amiga zeigt die
; Sprite-DMA, was level3 eben eintrug; hier zeichnen wir, was level3 im
; vorigen VBL eintrug.  Ein Bild (20 ms) Versatz, dafuer ohne Eingriff in
; Thalions Rueckkehr mit rte.
; ***************************************************************************
Fee_vbl:
	movem.l	d0-d7/a0-a6,-(sp)
	addq.l	#1,FRCLOCK.w		; TOS wartet darauf, nach Bomben schon vor dem Notausgang (T16)
	ifd	AMIGA_MESSEN
	addq.l	#1,Mess_vbls
	endc
	ifd	ABSTURZTEST
	addq.l	#1,Absturz_zaehler
	endc
	ifd	STRAHL
	bsr	St_basis		; der bisher gesetzte Schirm
	move.l	d0,St_vbl_schirm
	endc
	STRAHL_VOR St_vbl
	move.l	Anzeige_naechste,d0
	beq.b	.farben			; noch kein Schirm bestimmt
	move.l	d0,d1
	swap	d1
	move.b	d1,V_BASIS_H
	move.w	d0,d1
	lsr.w	#8,d1
	move.b	d1,V_BASIS_M
	move.b	d0,V_BASIS_L
.farben:
	; Bank 0: die 32 Farben, die level3 nach $DFF180 schrieb
	lea	Amiga_register+AR_COLOR00,a0
	lea	VIDEL_PAL,a1
	lea	Vier_nach_acht,a2
	moveq	#32-1,d3
.b0:	move.w	(a0)+,d0
	bsr.b	Amiga_nach_videl
	move.l	d1,(a1)+
	dbf	d3,.b0
	; Bank 1: dieselben, sechs davon aus Palette_unten ($C98, $CDC)
	moveq	#32-1,d3
.b1:	move.l	-128(a1),(a1)+
	dbf	d3,.b1
	lea	Farbwechsel_register,a0
.fw:	move.w	(a0)+,d2
	bmi.b	.fertig
	lea	Palette_unten,a1
	move.w	0(a1,d2.w),d0
	bsr.b	Amiga_nach_videl
	lea	VIDEL_PAL+32*4,a1
	add.w	d2,d2			; Wortversatz -> Langwortversatz
	move.l	d1,0(a1,d2.w)
	bra.b	.fw
.fertig:
	move.l	Anzeige_naechste,d0
	beq.b	.ohne
	move.l	d0,a0
	bsr	Fee_sprites
.ohne:	STRAHL_NACH St_vbl,St_vbl_schirm,#0,Anzeige_zeilen
	movem.l	(sp)+,d0-d7/a0-a6
	jmp	level3

; Amiga_nach_videl -- d0.w = $0RGB -> d1.l = $RRGG00BB; a2 = Vier_nach_acht.
; Veraendert d2 nicht (sichert es).
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

; ***************************************************************************
; Blit_starten -- den eingerichteten Blit ausfuehren.  HOG: der Blitter
; behaelt den Bus, die CPU steht bis zum Ende, Interrupts warten so lange.
;
; Mit geteiltem Bus kam der Blitter auf dem echten Falcon kaum zum Zug
; (FEEDIAG, 2026-10-02: 85 % der Zeit in der Warteschleife, der VBL laenger
; als ein Bild, Thalions Ablauf stand).  Die 030-Schleife laeuft aus dem
; Cache und braucht ihre 64 Buszyklen erst nach langer Zeit.  Mit HOG lief
; das Fantasy-Intro fehlerfrei.  Ataris Neustart (bset in der Schleife)
; zerstoerte auf dem Falcon das Bild und hing.  Die Schleife bleibt fuer
; den Fall, dass ein anderer Busmeister den Blitter aufhaelt.
; ***************************************************************************
Blit_starten:
	move.b	#BL_BUSY+BL_HOG,BL_STEUER
.w:	btst.b	#7,BL_STEUER
	bne.b	.w
	rts

; ***************************************************************************
; Blitter_sichern / Blitter_zurueck -- fuer den VBL: warten, bis ein Blit
; des Hauptablaufs fertig ist, dessen Register sichern und danach
; zuruecksetzen (ohne BUSY).
;   Veraendern d0-d6.
; ***************************************************************************
Blitter_sichern:
.w:	btst.b	#7,BL_STEUER
	bne.b	.w
	movem.l	BL_SRC_XINC,d0-d6	; $8A20-$8A3B
	movem.l	d0-d6,Blitter_zustand
	move.w	BL_STEUER,Blitter_zustand+28
	rts

Blitter_zurueck:
	movem.l	Blitter_zustand,d0-d6
	movem.l	d0-d6,BL_SRC_XINC
	move.w	Blitter_zustand+28,d0
	and.w	#$7FFF,d0		; BUSY aus
	move.w	d0,BL_STEUER
	rts

; ***************************************************************************
; Ebenen_umsetzen -- ein Rechteck Amiga -> Falcon, fuenf Blits (je Ebene
; einer).  Ebenen 5-7 bleiben.
;   IN : a0 = Amiga-Schirm, Zeile und Wort der linken oberen Ecke, Ebene 0
;        a1 = Falcon-Schirm, dieselbe Stelle, Ebene 0
;        d1.w = Zeilen (> 0), d3.w = Worte je Ebene und Zeile (> 0)
;   Veraendert d4/d5/d7/a0/a1.
; ***************************************************************************
Ebenen_umsetzen:
	moveq	#-1,d4
	move.w	d4,BL_MASKE1
	move.w	d4,BL_MASKE2
	move.w	d4,BL_MASKE3
	move.w	#2,BL_SRC_XINC
	move.w	#16,BL_DST_XINC
	move.w	d3,d4
	subq.w	#1,d4
	add.w	d4,d4			; (Worte-1)*2
	move.w	#bpscanl,d5
	sub.w	d4,d5
	move.w	d5,BL_SRC_YINC
	lsl.w	#3,d4			; (Worte-1)*16
	move.w	#FALCON_ZEILE,d5
	sub.w	d4,d5
	move.w	d5,BL_DST_YINC
	move.w	d3,BL_XCOUNT
	move.w	#HOP_QUELLE<<8+OP_KOPIE,BL_HOPOP
	clr.b	BL_SKEW
	moveq	#planes-1,d7
.eb:	move.l	a0,BL_SRC
	move.l	a1,BL_DST
	move.w	d1,BL_YCOUNT
	bsr	Blit_starten
	lea	bpscanl/planes(a0),a0	; naechste Amiga-Ebene
	addq.l	#2,a1			; naechste Falcon-Ebene
	dbf	d7,.eb
	rts

; ***************************************************************************
; Fee_sprites -- die Amiga-Sprites auf den gezeigten Falcon-Schirm (F2).
;   IN : a0 = gezeigter Falcon-Schirm (Anzeige_naechste)
;   Veraendert d0-d7/a0-a6 (Fee_vbl sichert).
;
; Was die Sprite-DMA auf dem Amiga tut, nach den Spritezeigern, die level3
; nach $DFF120 schrieb (K1: Amiga_register+AR_SPR0PT), und den zwei
; Steuerwoertern am Anfang jedes Sprites:
;   Wort 1: VSTART 0-7 | HSTART 1-8        Wort 2: VSTOP 0-7 | Anh. | V8 E8 H0
;   danach je Zeile DATA, DATB; ein ungerades Sprite mit gesetztem
;   Anhaengebit liefert die Bits 2 und 3 zum geraden davor: Farbe 16-31.
; Nur solche Paare (Thalion haengt alle vier an).  Nullpunkt wie bei Thalion
; ($80 waagerecht, $28 senkrecht: "screen_start").
;
; Auf dem Falcon: Ebenen 0-3 ausstanzen und die Daten einodern, Ebene 4
; (Farbe 16+) mit der Maske odern.  Ebene 5 traegt schon die Bank der Zeile,
; die Copperliste wechselt auch Spritefarben (20-22, 29-31); 6 und 7 sind 0.
; Unter der Fee wird nichts gesichert: Das naechste Mal holt Alte_fee_loeschen
; das Rechteck aus dem Amiga-Zwilling zurueck.
;
; Nebeneinander liegende Paare gleicher Hoehe werden ein Lauf und zusammen
; geblittet: je Lauf neun Blits, die Fee ist einer.
; ***************************************************************************
Fee_sprites:
	move.l	a0,Spr_falcon
	lea	Amiga_schirme,a1
	lea	Alte_fee_a,a2
	cmp.l	Falcon_a,a0
	beq.b	.a
	lea	AMIGA_SCHIRM(a1),a1
	lea	Alte_fee_b,a2
.a:	move.l	a1,Spr_amiga
	move.l	a2,Spr_alte
	bsr	Blitter_sichern
	bsr	Alte_fee_loeschen
	STRAHL_VOR St_feeneu
	bsr	Sprites_zerlegen
	STRAHL_NACH St_feeneu,Spr_falcon,Neue_fee,Neue_fee+2
	bra	Blitter_zurueck

; Alte_fee_loeschen -- das Rechteck, in das zuletzt auf diesem Schirm
; gezeichnet wurde, aus dem Amiga-Zwilling neu umsetzen.
Alte_fee_loeschen:
	move.l	Spr_alte,a2
	move.w	2(a2),d1		; Zeilen
	beq.b	.aus
	clr.w	2(a2)
	move.w	(a2),d0			; Falcon-Zeile
	move.w	4(a2),d2		; erste Gruppe
	move.w	6(a2),d3		; Gruppen
	move.l	Spr_amiga,a0
	move.w	d0,d4
	add.w	Anzeige_erste,d4
	mulu.w	#bpscanl,d4
	add.l	d4,a0
	add.w	d2,a0
	add.w	d2,a0
	move.l	Spr_falcon,a1
	move.w	d0,d4
	mulu.w	#FALCON_ZEILE,d4
	add.l	d4,a1
	lsl.w	#4,d2
	add.w	d2,a1
	ifd	STRAHL
	move.w	d0,St_fz
	move.w	d1,St_fn
	STRAHL_VOR St_feealt
	bsr	Ebenen_umsetzen
	STRAHL_NACH St_feealt,Spr_falcon,St_fz,St_fn
	rts
	else
	bra	Ebenen_umsetzen
	endc
.aus:	rts

; Sprites_zerlegen -- die vier Paare lesen, zuschneiden, zu Laeufen
; zusammenfassen und zeichnen.  Das Rechteck um alles Gezeichnete kommt
; nach Spr_alte.
Sprites_zerlegen:
	clr.w	Neue_fee+2		; noch nichts gezeichnet
	clr.w	Lauf_paare
	lea	Amiga_register+AR_SPR0PT,a4
	moveq	#4-1,d7
.paar:	move.l	(a4)+,a0		; gerades Sprite: Bits 0 und 1
	move.l	(a4)+,a1		; ungerades: Bits 2 und 3
	move.l	a0,d0
	beq	.weg
	move.l	a1,d0
	beq	.weg
	btst	#7,3(a1)		; Anhaengebit
	beq	.weg
	move.w	(a0),d0			; Steuerwort 1
	move.w	2(a0),d1		; Steuerwort 2
	move.w	d0,d2			; VSTART
	lsr.w	#8,d2
	btst	#2,d1
	beq.b	.v8
	bset	#8,d2
.v8:	move.w	d1,d3			; VSTOP
	lsr.w	#8,d3
	btst	#1,d1
	beq.b	.e8
	bset	#8,d3
.e8:	sub.w	d2,d3			; Hoehe
	ble	.weg
	and.w	#$FF,d0			; HSTART
	add.w	d0,d0
	btst	#0,d1
	beq.b	.h0
	addq.w	#1,d0
.h0:	sub.w	#$80,d0			; x
	sub.w	#$28,d2			; y (Amiga-Zeile)
	cmp.w	#-16,d0			; ganz links oder rechts draussen?
	ble	.weg
	cmp.w	#GRUPPEN*16,d0
	bge	.weg
	move.w	d2,d4			; oben: max(y, Anzeige_erste)
	cmp.w	Anzeige_erste,d4
	bge.b	.o
	move.w	Anzeige_erste,d4
.o:	move.w	d2,d5			; unten: min(y+Hoehe, Ende der Anzeige)
	add.w	d3,d5
	move.w	Anzeige_erste,d6
	add.w	Anzeige_zeilen,d6
	cmp.w	d6,d5
	ble.b	.u
	move.w	d6,d5
.u:	sub.w	d4,d5			; sichtbare Zeilen
	ble.b	.weg
	move.w	d4,d6			; Daten ab der ersten sichtbaren Zeile
	sub.w	d2,d6
	lsl.w	#2,d6
	lea	4(a0,d6.w),a0
	lea	4(a1,d6.w),a1
	move.w	Lauf_paare,d6		; setzt es den Lauf fort?
	beq.b	.neu
	cmp.w	Lauf_zeile,d4
	bne.b	.schluss
	cmp.w	Lauf_zeilen,d5
	bne.b	.schluss
	lsl.w	#4,d6
	add.w	Lauf_x,d6
	cmp.w	d6,d0
	beq.b	.dazu
.schluss:
	movem.l	d0/d4/d5/d7/a0/a1/a4,-(sp)
	bsr	Lauf_zeichnen
	movem.l	(sp)+,d0/d4/d5/d7/a0/a1/a4
.neu:	clr.w	Lauf_paare
	move.w	d0,Lauf_x
	move.w	d4,Lauf_zeile
	move.w	d5,Lauf_zeilen
.dazu:	move.w	Lauf_paare,d6
	lsl.w	#3,d6
	lea	Lauf_quellen,a2
	movem.l	a0/a1,0(a2,d6.w)
	addq.w	#1,Lauf_paare
.weg:	dbf	d7,.paar
	tst.w	Lauf_paare
	beq.b	.fertig
	bsr	Lauf_zeichnen
.fertig:
	move.l	Spr_alte,a2
	move.l	Neue_fee,(a2)
	move.l	Neue_fee+4,4(a2)
	rts

; ***************************************************************************
; Lauf_zeichnen -- Lauf_paare Paare ab Lauf_x, Amiga-Zeile Lauf_zeile,
; Lauf_zeilen Zeilen (schon zugeschnitten), Daten ab Lauf_quellen.
;
; 1. Die CPU legt fuenf Ebenen in Fee_quelle: Maske, Bit 0, 1, 2, 3.  Je
;    Zeile ein Wort je Paar und ein Nullwort dahinter, fuer das Verschieben.
; 2. Der Blitter stanzt sie ein, verschoben um x & 15.  Ein Wort d des
;    Ziels ist (q[d-g-1] << (16-s)) | (q[d-g] >> s), mit g = x >> 4.
;    Links abgeschnitten liest FXSR das Wort q[d-g-1] vorab; das erste Wort
;    ohne Vorgaenger und das letzte schneiden die Endmasken zu.
; ***************************************************************************
Lauf_zeichnen:
	move.w	Lauf_paare,d5		; Zeilenlaenge in Fee_quelle
	addq.w	#1,d5
	add.w	d5,d5
	move.w	d5,Lauf_r
	move.w	Lauf_zeilen,d0		; Ebenenlaenge
	mulu.w	d5,d0
	move.w	d0,Lauf_p
	moveq	#0,d7
.paar:	lea	Lauf_quellen,a0
	move.w	d7,d0
	lsl.w	#3,d0
	movem.l	0(a0,d0.w),a0/a1
	lea	Fee_quelle,a2
	add.w	d7,a2
	add.w	d7,a2
	move.w	Lauf_p,d0
	lea	0(a2,d0.w),a3
	lea	0(a3,d0.w),a4
	lea	0(a4,d0.w),a5
	lea	0(a5,d0.w),a6
	move.w	Lauf_zeilen,d6
	subq.w	#1,d6
.z:	move.w	(a0)+,d0
	move.w	(a0)+,d1
	move.w	(a1)+,d2
	move.w	(a1)+,d3
	move.w	d0,d4
	or.w	d1,d4
	or.w	d2,d4
	or.w	d3,d4
	move.w	d4,(a2)
	move.w	d0,(a3)
	move.w	d1,(a4)
	move.w	d2,(a5)
	move.w	d3,(a6)
	add.w	d5,a2
	add.w	d5,a3
	add.w	d5,a4
	add.w	d5,a5
	add.w	d5,a6
	dbf	d6,.z
	addq.w	#1,d7
	cmp.w	Lauf_paare,d7
	blt.b	.paar
	lea	Fee_quelle,a2		; die Nullspalte, alle fuenf Ebenen
	add.w	d7,a2
	add.w	d7,a2
	move.w	Lauf_zeilen,d6
	mulu.w	#5,d6
	subq.w	#1,d6
.null:	clr.w	(a2)
	add.w	d5,a2
	dbf	d6,.null

	; Lage.  d0 = g, d1 = s, d2 = erstes Zielwort, d3 = letztes,
	; d4 = natuerliches letztes, d6 = FXSR (0/1)
	move.w	Lauf_x,d0
	moveq	#15,d1
	and.w	d0,d1
	asr.w	#4,d0
	move.w	d0,d4
	add.w	Lauf_paare,d4
	tst.w	d1
	bne.b	.l1
	subq.w	#1,d4
.l1:	move.w	d0,d2
	bpl.b	.l2
	moveq	#0,d2
.l2:	move.w	d4,d3
	cmp.w	#GRUPPEN-1,d3
	ble.b	.l3
	moveq	#GRUPPEN-1,d3
.l3:	moveq	#0,d6
	tst.w	d1
	beq.b	.l4
	cmp.w	d0,d2
	beq.b	.l4
	moveq	#1,d6
.l4:
	; Endmasken: d5 = $FFFF >> s
	move.w	#$FFFF,d5
	lsr.w	d1,d5
	moveq	#-1,d7			; Maske 1
	tst.w	d1
	beq.b	.m1
	cmp.w	d0,d2
	bne.b	.m1
	move.w	d5,d7
.m1:	swap	d7
	move.w	#$FFFF,d7		; Maske 3
	tst.w	d1
	beq.b	.m3
	cmp.w	d4,d3
	bne.b	.m3
	move.w	d5,d7
	not.w	d7
.m3:	cmp.w	d2,d3			; nur ein Wort: Maske 1 allein zaehlt
	bne.b	.m4
	move.w	d7,d5
	swap	d7
	and.w	d5,d7
	swap	d7
.m4:	move.w	d7,BL_MASKE3
	move.w	#$FFFF,BL_MASKE2
	swap	d7
	move.w	d7,BL_MASKE1

	; Zaehler und Schrittweiten
	move.w	d3,d5
	sub.w	d2,d5			; Worte-1
	addq.w	#1,d5
	move.w	d5,BL_XCOUNT
	subq.w	#1,d5
	move.w	d5,d7
	lsl.w	#4,d7
	neg.w	d7
	add.w	#FALCON_ZEILE,d7
	move.w	d7,BL_DST_YINC
	move.w	#16,BL_DST_XINC
	add.w	d6,d5			; Lesezugriffe-1
	add.w	d5,d5
	move.w	Lauf_r,d7
	sub.w	d5,d7
	move.w	d7,BL_SRC_YINC
	move.w	#2,BL_SRC_XINC
	move.w	d1,d7
	tst.w	d6
	beq.b	.sk
	or.w	#BL_FXSR,d7
.sk:	move.b	d7,BL_SKEW

	; Rechteck fuer das naechste Mal
	move.w	Lauf_zeile,d7
	sub.w	Anzeige_erste,d7	; Falcon-Zeile
	bsr	Rechteck_merken

	; Quelle: erstes gelesenes Wort, Ziel: erstes Wort, Ebene 0
	move.w	d2,d5
	sub.w	d0,d5
	sub.w	d6,d5
	add.w	d5,d5
	lea	Fee_quelle,a0
	add.w	d5,a0
	move.l	Spr_falcon,a1
	mulu.w	#FALCON_ZEILE,d7
	add.l	d7,a1
	move.w	d2,d5
	lsl.w	#4,d5
	add.w	d5,a1
	move.w	Lauf_p,d5		; Ebenenlaenge in Fee_quelle
	move.l	a0,a2			; Ebenen 0-3: stanzen, einodern
	moveq	#4-1,d6
.eb:	add.w	d5,a2
	move.l	a0,BL_SRC
	move.l	a1,BL_DST
	move.w	Lauf_zeilen,BL_YCOUNT
	move.w	#HOP_QUELLE<<8+OP_STANZEN,BL_HOPOP
	bsr	Blit_starten
	move.l	a2,BL_SRC
	move.l	a1,BL_DST
	move.w	Lauf_zeilen,BL_YCOUNT
	move.w	#HOP_QUELLE<<8+OP_ODER,BL_HOPOP
	bsr	Blit_starten
	addq.l	#2,a1
	dbf	d6,.eb
	move.l	a0,BL_SRC		; Ebene 4: die Maske
	move.l	a1,BL_DST
	move.w	Lauf_zeilen,BL_YCOUNT
	move.w	#HOP_QUELLE<<8+OP_ODER,BL_HOPOP
	bra	Blit_starten

; Rechteck_merken -- Neue_fee um Falcon-Zeile d7, Lauf_zeilen Zeilen,
; Gruppen d2 bis d3 erweitern.  Veraendert nur a3.
Rechteck_merken:
	movem.l	d0-d4,-(sp)
	lea	Neue_fee,a3
	move.w	d7,d0			; oben
	move.w	d7,d1
	add.w	Lauf_zeilen,d1		; unten (ausschliesslich)
	addq.w	#1,d3			; rechts (ausschliesslich)
	tst.w	2(a3)
	beq.b	.setzen
	move.w	(a3),d4			; bisher oben
	cmp.w	d4,d0
	ble.b	.o
	move.w	d4,d0
.o:	add.w	2(a3),d4		; bisher unten
	cmp.w	d4,d1
	bge.b	.u
	move.w	d4,d1
.u:	move.w	4(a3),d4		; bisher links
	cmp.w	d4,d2
	ble.b	.l
	move.w	d4,d2
.l:	add.w	6(a3),d4		; bisher rechts
	cmp.w	d4,d3
	bge.b	.setzen
	move.w	d4,d3
.setzen:
	move.w	d0,(a3)
	sub.w	d0,d1
	move.w	d1,2(a3)
	move.w	d2,4(a3)
	sub.w	d2,d3
	move.w	d3,6(a3)
	movem.l	(sp)+,d0-d4
	rts

	ifd	FEE_MESSEN
; ***************************************************************************
; Bild_messen -- (FEE_MESSEN) vor dem Warten auf den Takt.  Thalions
; Schleife wartet auf vindex >= 2 und dann noch mit vsync: drei VBL je
; Bild.  Ist vindex hier schon 2, war es knapp, aber noch im Takt; erst ab
; 3 ist das Bild zu spaet.
; ***************************************************************************
Bild_messen:
	move.l	vindex,d0
	ifd	AMIGA_MESSEN
	; je Messsekunde: Bilder, knapp, zu spaet, Summe vindex (Fb_verlauf)
	movem.l	d1/a0,-(sp)
	move.w	Mess_zeilen,d1
	cmp.w	#MESS_SEKUNDEN,d1
	bhs.b	.ohne
	lsl.w	#3,d1
	lea	Fb_verlauf,a0
	add.w	d1,a0
	addq.w	#1,(a0)
	add.w	d0,6(a0)
	cmp.l	#2,d0
	blt.b	.ohne
	bne.b	.v_spaet
	addq.w	#1,2(a0)
	bra.b	.ohne
.v_spaet:
	addq.w	#1,4(a0)
.ohne:	movem.l	(sp)+,d1/a0
	endc
	addq.w	#1,Mess_bilder
	cmp.l	#2,d0
	blt.b	.gut
	bne.b	.spaet
	addq.w	#1,Mess_knapp
	bra.b	.gut
.spaet:	addq.w	#1,Mess_spaet
.gut:	cmp.w	Mess_laengstes,d0
	ble.b	.aus
	move.w	d0,Mess_laengstes
.aus:	rts

; Messung_zeigen -- (FEE_MESSEN) nach dem Abraeumen auf den Desktop
; schreiben und auf eine Taste warten.
Messung_zeigen:
	lea	Text_puffer,a1
	lea	Text_bilder,a0
	bsr	Text_anhaengen
	move.w	Mess_bilder,d0
	bsr	Zahl_schreiben
	lea	Text_knapp,a0
	bsr	Text_anhaengen
	move.w	Mess_knapp,d0
	bsr	Zahl_schreiben
	lea	Text_spaet,a0
	bsr	Text_anhaengen
	move.w	Mess_spaet,d0
	bsr	Zahl_schreiben
	lea	Text_laengstes,a0
	bsr	Text_anhaengen
	move.w	Mess_laengstes,d0
	bsr	Zahl_schreiben
	lea	Text_blits,a0
	bsr	Text_anhaengen
	move.w	Bl_anzahl,d0
	bsr	Zahl_schreiben
	lea	Text_fremd,a0
	bsr	Text_anhaengen
	move.w	Bl_fremd,d0
	bsr	Zahl_schreiben
	lea	Text_schnell,a0
	bsr	Text_anhaengen
	move.w	Bl_schnell,d0
	bsr	Zahl_schreiben
	ifd	BLIT_PRUEF
	lea	Text_abweichung,a0
	bsr	Text_anhaengen
	move.w	Bl_abweichung,d0
	bsr	Zahl_schreiben
	lea	Text_ungeprueft,a0
	bsr	Text_anhaengen
	move.w	Bl_ungeprueft,d0
	bsr	Zahl_schreiben
	endc
	lea	Text_messende,a0
	bsr	Text_anhaengen
	clr.b	(a1)
	ifd	AMIGA_MESSEN
	lea	Text_puffer,a0		; hinter die Seite von Mess_ausgeben
	moveq	#1,d0
	bsr	Mess_text_sichern
	endc
	pea	Text_puffer
	move.w	#Cconws,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Crawcin,-(sp)
	trap	#1
	addq.l	#2,sp
	rts

; Text_anhaengen -- a0 (mit Null) nach a1, a1 dahinter.
Text_anhaengen:
	move.b	(a0)+,(a1)+
	bne	Text_anhaengen
	subq.l	#1,a1
	rts

; Zahl_schreiben -- d0.w dezimal nach a1, a1 dahinter.
Zahl_schreiben:
	and.l	#$FFFF,d0
	moveq	#0,d1
.teile:	divu.w	#10,d0
	swap	d0
	move.w	d0,-(sp)		; Ziffer
	clr.w	d0
	swap	d0
	addq.w	#1,d1
	tst.l	d0
	bne.b	.teile
	subq.w	#1,d1
.schreib:
	move.w	(sp)+,d0
	add.b	#'0',d0
	move.b	d0,(a1)+
	dbf	d1,.schreib
	rts
	endc

; Messung (AMIGA_MESSEN, amiga/AMIGA_MESSEN.S): Blits und Thalions FAIRY.S
	ifd	AMIGA_MESSEN
MESS_BLIT_VON	equ	Blitter_warten
MESS_BLIT_BIS	equ	Mess_blit_ende
MESS_ZWEI_VON	equ	Fairy_anfang
MESS_ZWEI_BIS	equ	Fairy_ende
	ifd	FEE_MESSEN
MESS_ZUSATZ_KOPF	equ	Fb_kopf		; Bilder je Sekunde (Bild_messen)
MESS_ZUSATZ		equ	Fb_verlauf
MESS_ZUSATZ_LAENGE	equ	8*MESS_SEKUNDEN
	endc
	ifd	MESS_ENDE
MESS_ABRAEUMEN	equ	Fee_abbruch
	else
MESS_ABRAEUMEN	equ	Fee_abraeumen
	endc
	include	"AMIGA_MESSEN.S"

	ifd	MESS_ENDE
; Fee_abbruch -- (Diagnose MESS_ENDE=n, FEEDIAG) nach n Sekunden das Ende
; von start, auch wenn Thalions Ablauf festhaengt: messen, abraeumen,
; Messung ausgeben und zurueck zum Desktop.  Kehrt nicht zurueck.
Fee_abbruch:
	bsr	Mess_stoppen
	bsr	Fee_abraeumen
	bsr	Mess_ausgeben
	ifd	FEE_MESSEN
	bsr	Messung_zeigen
	endc
	move.l	Alter_ssp,-(sp)
	move.w	#Super,-(sp)
	trap	#1
	addq.l	#6,sp
	move.w	#Pterm0,-(sp)
	trap	#1
	endc
	endc

; ***************************************************************************
; Daten
; ***************************************************************************
	SECTION	Fee_daten,data
	ifd	AMIGA_MESSEN
Text_mess_zwei:	dc.b	"  Thalions FAIRY.S: ",0
	even
	ifd	FEE_MESSEN
Fb_kopf:	dc.b	"BILD"		; dann Sekunden.w, 0.w; Fb_verlauf
	dc.w	MESS_SEKUNDEN,0
	endc
	endc
	include	"amiga_messen_daten.i"
	ifd	STRAHL
	even
St_liste:	dc.l	St_vbl,Text_st_vbl
		dc.l	St_feealt,Text_st_feealt
		dc.l	St_feeneu,Text_st_feeneu
		dc.l	St_umsetzen,Text_st_umsetzen
		dc.l	0
Text_st_vbl:	dc.b	"VBL (ganzes Bild)",0
Text_st_feealt:	dc.b	"Fee: altes Rechteck zurueck (VBL, gezeigter Schirm)",0
Text_st_feeneu:	dc.b	"Fee: neu zeichnen (VBL, gezeigter Schirm)",0
Text_st_umsetzen: dc.b	"Hauptablauf: Zeilen ab WECHSELZEILE umsetzen",0
	endc
Vier_nach_acht:
	dc.b	$00,$11,$22,$33,$44,$55,$66,$77,$88,$99,$AA,$BB,$CC,$DD,$EE,$FF
Text_kein_falcon:
	dc.b	"Das Fantasy-Intro braucht einen Falcon an RGB oder VGA.",13,10
	dc.b	"Taste druecken.",13,10,0
Text_cursor_aus:
	dc.b	27,'f',0
Text_cursor_an:
	dc.b	27,'e',0
	ifd	FEE_MESSEN
	ifd	FEE_CPU
Text_bilder:	dc.b	"Fantasy-Intro, Zeilen mit der CPU umgesetzt",13,10
	else
Text_bilder:	dc.b	"Fantasy-Intro, Zeilen mit dem Blitter umgesetzt",13,10
	endc
		dc.b	"Bilder: ",0
Text_knapp:	dc.b	13,10,"knapp (erst nach dem 2. VBL fertig): ",0
Text_spaet:	dc.b	13,10,"zu spaet (erst nach dem 3. VBL): ",0
Text_laengstes:	dc.b	13,10,"hoechstes vindex beim Fertigwerden: ",0
Text_blits:	dc.b	13,10,"Amiga-Blits: ",0
Text_fremd:	dc.b	", davon nicht unterstuetzt: ",0
Text_schnell:	dc.b	", schnell: ",0
	ifd	BLIT_PRUEF
Text_abweichung:	dc.b	13,10,"Pruefung schnell gegen genau, abweichend: ",0
Text_ungeprueft:	dc.b	", ungeprueft: ",0
	endc
Text_messende:	dc.b	13,10,"Taste druecken.",13,10,0
	endc
	even

	SECTION	Fee_bss,bss
Alter_ssp:		ds.l	1
Alter_vbl:		ds.l	1
Alter_schirm:		ds.l	1
Alter_mausvektor:	ds.l	1
Kbd_vektoren:		ds.l	1
Anzeige_naechste:	ds.l	1
Falcon_a:		ds.l	1
Falcon_b:		ds.l	1
Alter_modus:		ds.w	1
Neuer_modus:		ds.w	1
Anzeige_zeilen:		ds.w	1
Anzeige_erste:		ds.w	1
Maustasten:		ds.b	1
			even
Alte_st_farben:		ds.w	16
Alte_videl_farben:	ds.l	256
			cnop	0,4
Amiga_register:		ds.b	AR_GROESSE
Blitter_zustand:	ds.b	30		; $8A20-$8A3D, fuer den VBL
Spr_falcon:		ds.l	1		; Fee_sprites: gezeigter Schirm
Spr_amiga:		ds.l	1		; sein Amiga-Zwilling
Spr_alte:		ds.l	1		; Alte_fee_a oder _b
Lauf_quellen:		ds.l	2*4		; je Paar: gerades, ungerades Sprite
; Rechtecke: Falcon-Zeile, Zeilen (0 = leer), erste Gruppe, Gruppen
Alte_fee_a:		ds.w	4		; zuletzt auf Falcon_a gezeichnet
Alte_fee_b:		ds.w	4
Neue_fee:		ds.w	4
Lauf_paare:		ds.w	1
Lauf_x:			ds.w	1
Lauf_zeile:		ds.w	1		; Amiga-Zeile
Lauf_zeilen:		ds.w	1
Lauf_r:			ds.w	1		; Zeilenlaenge in Fee_quelle
Lauf_p:			ds.w	1		; Ebenenlaenge in Fee_quelle
Fee_quelle:		ds.w	5*AMIGA_ZEILEN*(4+1)	; 5 Ebenen, 4 Paare + Null
	include	"amiga_blit_bss.i"
	include	"amiga_messen_bss.i"
	include	"amiga_notaus_bss.i"
	ifd	STRAHL
St_vbl:			ds.b	ST_LAENGE
St_feealt:		ds.b	ST_LAENGE
St_feeneu:		ds.b	ST_LAENGE
St_umsetzen:		ds.b	ST_LAENGE
St_vbl_schirm:		ds.l	1	; V_BASIS beim Eintritt in den VBL
St_uz_schirm:		ds.l	1
St_fz:			ds.w	1
St_fn:			ds.w	1
St_uz:			ds.w	1
	even
	endc
	ifd	FEE_MESSEN
Mess_bilder:		ds.w	1
Mess_knapp:		ds.w	1
Mess_spaet:		ds.w	1
Mess_laengstes:		ds.w	1
Text_puffer:		ds.b	512
	ifd	AMIGA_MESSEN
Fb_verlauf:		ds.w	4*MESS_SEKUNDEN	; Bilder, knapp, spaet, Summe vindex
	endc
	endc
			cnop	0,4
Amiga_schirme:		ds.b	2*AMIGA_SCHIRM
Amiga_ueberlauf:	ds.b	AMIGA_UEBERLAUF	; Sterne unter dem Schirm (Vorspann)
Falcon_speicher:	ds.b	2*FALCON_SCHIRM+256

	SECTION	Fee_code,code

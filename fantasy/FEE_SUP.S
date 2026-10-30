; ***************************************************************************
; FEE_SUP.S -- the Falcon layer under Thalion's FAIRY.S (fantasy intro).
;
; **Who does what** (docs/11-Intro-Extro.md, 3 and 7):
;
;   Thalion's FAIRY.S        fairy, dust, stars, logo, level3.  Unchanged.
;   Thalion's Hunk-1 code    fades, screen swap, tables: pulled out of
;                            Fantasy_intro at build time (fantasy_auszug.py).
;   tools/fantasy_st_data.py the graphics in Falcon format (--falcon), shared
;                            with the ST build
;   this file                what hung on copper, CIA, sprites, blitter and
;                            the OS on the Amiga, in Thalion's order (Hunk 1
;                            $110-$2B0); STARS_FALCON.S: ours for two of
;                            Thalion's routines
;
; E30 (user 2026-10-25), on the model of fantasy_st/: no Amiga screen is
; shown and none is converted.  Thalion draws into workbase, a buffer
; nobody shows; what shows is two Falcon screens (fee_vorspann.i), drawn by
; the hooks:
;
;   sparks  make_funkel (Thalion's) through plot_jmptab, which points to
;           Plot_falcon0..31; Plot_table turns Thalion's workbase address
;           into the Falcon one
;   dust    Dust_falcon, ours for Thalion's make_funkel2 (STARS_FALCON.S)
;   stars   Magic_falcon, ours for Thalion's make_magic: the compiled
;           routine for image and shift (falcon_fantasy_stars.i)
;   logo    Magic_falcon: the 4-pixel column into Falcon_background
;   fairy   Fairy_put, in every VBL into the shown screen, with a
;           save-under: 50 Hz as the Amiga's sprites (E30)
;
; Unten_herstellen copies the lower band back from Falcon_background every
; frame (Thalion's $BC0 blit), and that erases dust and stars.  No blitter
; and no line conversion any more: everything is drawn by the CPU.
;
; DEVIATION (goals 1 and 2), docs/17-deviations.md D3: Thalion's main flow,
; the sprites, plots, blits and copper split are ours here, the graphics in
; Falcon format from the build.
;
; **K1:** FAIRY.S schreibt nach $DFFxxx.  tools/fairy_umbiegen.py biegt nach
; dem Binden genau diese zehn Operanden auf Amiga_register um.  Was dort
; ankommt (Palette, Spritezeiger, Blitterregister), setzt diese Datei um.
;
; Switches (VASM_EXTRA):  FEE_MESSEN    count the frames that were done
;                                       late or just in time (FEEMESS.TOS)
;                         CHECK_STARS   Thalion's make_funkel2 and make_magic
;                                       against ours, every frame
;                                       (FEECHECK.TOS, STARS_FALCON.S)
; ***************************************************************************

	SECTION	Fee_code,code

; ***************************************************************************
; start -- program entry.  Our own stack, then give back to GEMDOS what the
; program does not need: the fairy's preshift comes from Mxalloc.
; ***************************************************************************
start:
	move.l	4(sp),a0		; basepage
	lea	Stapel_ende,sp
	move.l	$C(a0),d0		; text
	add.l	$14(a0),d0		; data
	add.l	$1C(a0),d0		; bss
	add.l	#$100,d0
	move.l	d0,-(sp)
	move.l	a0,-(sp)
	clr.w	-(sp)
	move.w	#Mshrink,-(sp)
	trap	#1
	lea	12(sp),sp
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
	bsr	Fee_ablauf
	bsr	Fee_abraeumen
	ifd	FEE_MESSEN
	bsr	Messung_zeigen
	endc
	ifd	CHECK_STARS
	bsr	Check_report
	endc
	move.l	Fee_puffer,d0
	beq.b	.ende
	move.l	d0,-(sp)
	move.w	#Mfree,-(sp)
	trap	#1
	addq.l	#6,sp
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
; Fee_einrichten -- mode, lines, screens, the fairy's memory, mouse.  The
; counterpart of Thalion's start ($000-$10E: switch the OS off).
;   Z set: ready.  Otherwise a monitor we do not serve.
;
; **Lines (user, 2026-09-29):** RGB with PAL (fixed, 2026-10-03), and there
; all 256 lines if the Videl can be pulled to them (Videl_256).  Otherwise
; 200 lines from Anzeige_erste.  At VGA 240 lines, without 8 at the top and
; the bottom.  The screens always hold all 256 rows; the picture base
; starts the window.
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

	; the fairy's 16 preshifts, TT-RAM if there is any; without the
	; memory no fairy (Fairy_shift_begin)
	bsr	Fairy_buffer_size
	move.w	#3,-(sp)		; either, TT-RAM preferred
	move.l	d0,-(sp)
	move.w	#Mxalloc,-(sp)
	trap	#1
	addq.l	#8,sp
	move.l	d0,Fee_puffer

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
	add.l	#FALCON_ABSTAND,d0
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

NOTAUS_ABRAEUMEN	equ	Fee_abraeumen
	include	"AMIGA_NOTAUS.S"

; ***************************************************************************
; Fee_ablauf -- Thalion's main flow (Hunk 1 $110-$2B0), written out because
; it hangs on copper, CIA and DMA.  Order and values as there and as in
; fantasy_st/FANTASY_ST.S; the addresses in brackets are the places in
; Hunk 1.
; ***************************************************************************
Fee_ablauf:
	bsr	Hardware_einrichten	; ($D22)
	bsr	Schirme_einrichten	; ($C2C)
	; background on both screens ($118), from the Falcon copy
	lea	Falcon_background,a0
	move.l	Falcon_a,a1
	move.l	Falcon_b,a2
	move.w	#FALCON_SCHIRM/4-1,d7
.hg:	move.l	(a0)+,d0
	move.l	d0,(a1)+
	move.l	d0,(a2)+
	dbf	d7,.hg
	bsr	Plot_setup
	bsr	Stars_setup
	bsr	Fairy_shift_begin
	bsr	Wait_vbl
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
.ein:	bsr	Wait_vbl
	bsr	Wait_vbl
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
.warte:	bsr	Wait_vbl
	bsr	Maustaste
	dbne	d7,.warte
	bsr	Fairy_shift_finish
	move.w	#-1,vbl_flag		; ($21E) jetzt fliegt die Fee
; ($226) die Schleife: drei VBL je Bild (vindex >= 2, dann vsync)
.bild:
	ifd	ABSTURZTEST
	bsr	Absturz_pruefen
	endc
	bsr	Schirme_tauschen	; Thalion's: both Amiga screens are workbase
	bsr	Falcon_swap		; ours: the two Falcon screens
	bsr	Anzeige_setzen		; ($C98, Copperliste)
	jsr	vsync
	clr.l	vindex
	bsr	Unten_herstellen	; ($BC0)
	jsr	make_funkel
	ifd	CHECK_STARS
	bsr	Check_stars		; Thalion's and ours, compared
	else
	bsr	Dust_falcon		; ours for make_funkel2 (STARS_FALCON.S)
	bsr	Magic_falcon		; ours for make_magic
	endc
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
; Schirme_einrichten -- ($C2C) Thalion's two screens are one buffer nobody
; shows (workbase stays put); ours are Falcon_show and Falcon_work.
; ***************************************************************************
Schirme_einrichten:
	move.l	#Amiga_schirm,d0
	move.l	d0,Schirm_arbeit
	move.l	d0,Schirm_zeigen
	move.l	d0,workbase
	move.l	Falcon_a,Falcon_show
	move.l	Falcon_b,Falcon_work
	bsr.b	Plot_target_set
	bsr	Anzeige_setzen
	jmp	vsync

; Falcon_swap -- the Falcon screens, next to Thalion's Schirme_tauschen.
Falcon_swap:
	move.l	Falcon_work,d0
	move.l	Falcon_show,Falcon_work
	move.l	d0,Falcon_show
Plot_target_set:
	move.l	Falcon_work,d0
	add.l	#WECHSELZEILE*FALCON_ZEILE,d0
	move.l	d0,Plot_target
	rts

; ***************************************************************************
; Anzeige_setzen -- (copper list $C98) show Falcon_show from the next frame
; on.  The picture base is written right here: the Videl latches it before
; our VBL, written from Fee_vbl it would only take effect one frame later
; (T11, docs/11 7.8).  Fee_vbl writes it once more, with the same value.
;
; The fairy moves to the new screen: its save-under on the old one is
; dropped (Unten_herstellen erases the old screen's lower band, and the
; fairy lies in it), and it is drawn into the new screen first.  Otherwise
; the first frame shows it without the fairy until Fee_vbl draws it;
; Hatari, which renders the whole frame at the VBL, showed exactly that as
; flicker (docs/11 7.8).
;   All registers are preserved.
; ***************************************************************************
Anzeige_setzen:
	movem.l	d0-d7/a0-a4,-(sp)
	move.l	Falcon_show,a2
	move.w	Anzeige_erste,d0
	mulu.w	#FALCON_ZEILE,d0
	add.l	a2,d0
	move.w	sr,-(sp)
	or.w	#$0700,sr		; Fee_vbl uses the same fairy state
	move.l	d0,Anzeige_naechste
	move.l	a2,Fee_schirm
	clr.w	Fee_zeilen
	bsr	Fairy_put
	move.w	(sp)+,sr
	move.l	Anzeige_naechste,d0
	move.l	d0,d1
	swap	d1
	move.b	d1,V_BASIS_H
	move.w	d0,d1
	lsr.w	#8,d1
	move.b	d1,V_BASIS_M
	move.b	d0,V_BASIS_L
	movem.l	(sp)+,d0-d7/a0-a4
	rts

; ***************************************************************************
; Unten_herstellen -- ($BC0) Thalion's blit: the rows from WECHSELZEILE on
; from the background into the work screen; there dust and stars fall, and
; there make_magic writes the logo into the background.  Here from the
; Falcon background, ten registers at a time.
; ***************************************************************************
Unten_herstellen:
	lea	Falcon_background+WECHSELZEILE*FALCON_ZEILE,a0
	move.l	Plot_target,a1
	move.w	#UNTEN_BYTES/40-1,d7
.k:	movem.l	(a0)+,d0-d6/a2-a4
	movem.l	d0-d6/a2-a4,(a1)
	lea	40(a1),a1
	dbf	d7,.k
	rts

; ***************************************************************************
; Wait_vbl -- Thalion's vsync (wait for the next VBL), but the wait goes
; into the fairy's preshift, one row of one frame at a time.  For the fade
; in and the wait before the flight (80 VBL); what is left
; Fairy_shift_finish does before the fairy flies.
; ***************************************************************************
Wait_vbl:
	move.l	d0,-(sp)
	move.l	vindex,d0
.w:	cmp.l	vindex,d0
	bne.b	.found
	cmp.w	#FALCON_FAIRY_FRAMES*FALCON_FAIRY_ROWS,Shift_row
	bcc.b	.w
	bsr	Fairy_shift_step
	bra.b	.w
.found:	move.l	(sp)+,d0
	rts

Fairy_shift_finish:
.w:	cmp.w	#FALCON_FAIRY_FRAMES*FALCON_FAIRY_ROWS,Shift_row
	bcc.b	.out
	bsr	Fairy_shift_step
	bra.b	.w
.out:	rts

; ***************************************************************************
; Fairy_buffer_size -- d0.l = bytes for the 16 preshifts of all frames:
; per frame Falcon_fairy_groups groups a row once shifted (4 or 5), 10
; bytes a group.  Changes d1/d7/a0.
; ***************************************************************************
Fairy_buffer_size:
	moveq	#0,d0
	lea	Falcon_fairy_groups,a0
	moveq	#FALCON_FAIRY_FRAMES-1,d7
.f:	moveq	#0,d1
	move.b	(a0)+,d1
	add.l	d1,d0
	dbf	d7,.f
	mulu.w	#FALCON_FAIRY_ROWS*10*16,d0
	rts

; ***************************************************************************
; Fairy_shift_begin -- Fairy_shifts: per frame and shift where its rows
; start in Fee_puffer.  A group is ~mask, planes 0-3 (the sprite value);
; Fairy_put sets plane 4 under the mask (colour 16 + value).
; ***************************************************************************
Fairy_shift_begin:
	clr.w	Shift_row
	move.l	Fee_puffer,d0
	bgt.b	.found
	clr.l	Fee_puffer		; an error code is no buffer
	move.w	#FALCON_FAIRY_FRAMES*FALCON_FAIRY_ROWS,Shift_row ; no fairy
	rts
.found:	lea	Fairy_shifts,a0
	lea	Falcon_fairy_groups,a1
	moveq	#FALCON_FAIRY_FRAMES-1,d7
.b:	moveq	#0,d1
	move.b	(a1)+,d1
	mulu	#FALCON_FAIRY_ROWS*10,d1
	moveq	#16-1,d6
.s:	move.l	d0,(a0)+
	add.l	d1,d0
	dbf	d6,.s
	dbf	d7,.b
	rts

; ***************************************************************************
; Fairy_shift_step -- row Shift_row of Falcon_fairy (frame-major) in all 16
; shifts.  Per plane the four source words go into d0-d3 (d4 takes what
; leaves on the right) and move right one pixel per shift.  The mask is
; stored inverted, for and.l: it shifts in ones.  All registers stay.
; As Fairy_shift_step in fantasy_st/FANTASY_ST.S, the data have the same
; layout.
; ***************************************************************************
SHIFT_WORD	macro			; \1 = groups (4/5), \2 = word in the group
	move.l	a1,a6
	move.w	\2(a0),d0
	move.w	\2+10(a0),d1
	move.w	\2+20(a0),d2
	move.w	\2+30(a0),d3
	moveq	#0,d4
	ifeq	\2
	not.w	d0
	not.w	d1
	not.w	d2
	not.w	d3
	not.w	d4
	endc
	moveq	#16-1,d7
.s\@:	move.w	d0,\2(a6)
	move.w	d1,\2+10(a6)
	move.w	d2,\2+20(a6)
	move.w	d3,\2+30(a6)
	ifeq	\1-5
	move.w	d4,\2+40(a6)
	endc
	add.l	a5,a6
	ifeq	\2
	move.w	#$10,ccr		; X: a one comes in
	roxr.w	#1,d0
	else
	lsr.w	#1,d0
	endc
	roxr.w	#1,d1
	roxr.w	#1,d2
	roxr.w	#1,d3
	ifeq	\1-5
	roxr.w	#1,d4
	endc
	dbf	d7,.s\@
	endm

Fairy_shift_step:
	movem.l	d0-d7/a0-a1/a5-a6,-(sp)
	moveq	#0,d0
	move.w	Shift_row,d0
	addq.w	#1,Shift_row
	lea	Falcon_fairy,a0
	move.w	d0,d1
	mulu	#FALCON_FAIRY_GROUPS*10,d1
	add.l	d1,a0
	divu	#FALCON_FAIRY_ROWS,d0	; row : frame
	lea	Falcon_fairy_groups,a1
	moveq	#0,d5
	move.b	0(a1,d0.w),d5
	move.w	d5,d1
	mulu	#FALCON_FAIRY_ROWS*10,d1
	move.l	d1,a5			; from one shift to the next
	move.w	d0,d1
	lsl.w	#6,d1			; frame * 16 shifts * 4
	lea	Fairy_shifts,a1
	move.l	0(a1,d1.w),a1
	swap	d0
	mulu	d5,d0
	mulu	#10,d0
	add.l	d0,a1			; the row
	cmp.w	#5,d5
	beq.w	.five
	SHIFT_WORD 4,0
	SHIFT_WORD 4,2
	SHIFT_WORD 4,4
	SHIFT_WORD 4,6
	SHIFT_WORD 4,8
	bra.w	.done
.five:	SHIFT_WORD 5,0
	SHIFT_WORD 5,2
	SHIFT_WORD 5,4
	SHIFT_WORD 5,6
	SHIFT_WORD 5,8
.done:
	movem.l	(sp)+,d0-d7/a0-a1/a5-a6
	rts

; ***************************************************************************
; Fairy_put -- the fairy on the shown screen, from Fee_vbl in every VBL and
; once from Anzeige_setzen: put back what the last call covered
; (Fee_rettung), then save the new place and draw the fairy there.  50 Hz,
; as the Amiga's sprites follow level3 every VBL (E30); the rest of the
; scene moves once a frame.
;   IN : a2 = shown Falcon screen, row 0
;   Changes d0-d7/a0-a3.
;
; What the sprite DMA shows, from what level3 wrote: the pointer of
; sprite 0 names the frame (Thalion's eight sprites of a frame lie one after
; the other in elfe), its two control words the place: word 1 VSTART 0-7 |
; HSTART 1-8, word 2 VSTOP 0-7 | attach | V8 E8 H0; zero point $80 across,
; $28 down.  Any other pointer (sprite_00 while the fairy is off): nothing.
;
; Planes 0-3 take the sprite value, plane 4 is set under the mask (Amiga
; colours 16-31); plane 5 stays the row's bank, as the copper changes the
; sprite colours too.  Clipped to the screen's 256 rows and its width by
; groups.
; ***************************************************************************
Fairy_put:
	tst.w	Fee_zeilen
	beq.b	.find
	bsr	Fairy_restore
.find:	cmp.w	#FALCON_FAIRY_FRAMES*FALCON_FAIRY_ROWS,Shift_row
	bcs	.out			; not preshifted yet (or no memory)
	move.l	Amiga_register+AR_SPR0PT,d0
	move.l	d0,a0
	sub.l	#elfe,d0
	bcs	.out
	cmp.l	#FALCON_FAIRY_FRAMES*FALCON_FAIRY_FRAME,d0
	bcc	.out
	divu	#FALCON_FAIRY_FRAME,d0
	move.l	d0,d1
	swap	d1
	tst.w	d1
	bne	.out			; not the start of a frame
	move.w	(a0),d1
	move.w	2(a0),d2
	moveq	#0,d3
	move.b	d1,d3			; HSTART 1-8
	add.w	d3,d3
	btst	#0,d2
	beq.b	.h0
	addq.w	#1,d3
.h0:	sub.w	#$80,d3			; x
	lsr.w	#8,d1			; VSTART
	btst	#2,d2
	beq.b	.v8
	bset	#8,d1
.v8:	sub.w	#$28,d1			; Amiga row of the fairy's row 0
	move.w	d1,d4			; first row drawn
	bpl.b	.top
	moveq	#0,d4
.top:	move.w	d1,d5
	add.w	#FALCON_FAIRY_ROWS,d5
	cmp.w	#AMIGA_ZEILEN,d5
	ble.b	.bottom
	move.w	#AMIGA_ZEILEN,d5
.bottom:
	sub.w	d4,d5			; rows drawn
	ble	.out
	; the data: frame d0, shift x & 15, from the first row drawn
	lea	Falcon_fairy_groups,a1
	moveq	#0,d6
	move.b	0(a1,d0.w),d6		; groups a row
	moveq	#15,d7
	and.w	d3,d7
	lsl.w	#4,d0
	add.w	d7,d0
	lsl.w	#2,d0
	lea	Fairy_shifts,a1
	move.l	0(a1,d0.w),a1
	move.w	d6,d7
	mulu	#10,d7			; bytes a row
	move.w	d4,d0
	sub.w	d1,d0
	mulu	d7,d0
	add.l	d0,a1
	; the groups inside the picture
	asr.w	#4,d3			; group of the fairy's left edge
	moveq	#0,d0			; first group drawn
	tst.w	d3
	bpl.b	.left
	move.w	d3,d0
	neg.w	d0
.left:	moveq	#GRUPPEN,d2
	sub.w	d3,d2			; groups up to the right edge
	cmp.w	d6,d2
	ble.b	.right
	move.w	d6,d2
.right:	sub.w	d0,d2			; groups drawn
	ble	.out
	move.w	d0,d1
	mulu	#10,d1
	add.w	d1,a1
	mulu	#FALCON_ZEILE,d4
	add.l	d4,a2
	add.w	d3,d0
	lsl.w	#4,d0
	add.w	d0,a2
	move.w	d2,d1
	mulu	#10,d1
	sub.w	d1,d7			; data to skip after a row
	; save what lies there: planes 0-4, 10 bytes a group
	move.l	a2,Fee_platz
	move.w	d5,Fee_zeilen
	move.w	d2,Fee_gruppen
	lea	Fee_rettung,a3
	move.l	a2,a0
	move.w	d5,d0
	subq.w	#1,d0
.srow:	move.w	d2,d1
	subq.w	#1,d1
.sgroup:
	move.l	(a0)+,(a3)+
	move.l	(a0)+,(a3)+
	move.w	(a0),(a3)+
	addq.l	#8,a0
	dbf	d1,.sgroup
	move.w	d2,d1
	lsl.w	#4,d1
	sub.w	d1,a0
	lea	FALCON_ZEILE(a0),a0
	dbf	d0,.srow
	; draw
	move.w	#FALCON_ZEILE,d6
	move.w	d2,d1
	lsl.w	#4,d1
	sub.w	d1,d6			; screen to skip after a row
	subq.w	#1,d2
	subq.w	#1,d5
.line:	move.w	d2,d4
.group:	move.w	(a1)+,d0		; ~mask, into both halves
	move.w	d0,d1
	swap	d0
	move.w	d1,d0
	and.l	d0,(a2)
	and.l	d0,4(a2)
	not.w	d1
	or.w	d1,8(a2)		; plane 4: colour 16 + value
	move.l	(a1)+,d0
	or.l	d0,(a2)+
	move.l	(a1)+,d0
	or.l	d0,(a2)+
	addq.l	#8,a2
	dbf	d4,.group
	add.w	d7,a1
	add.w	d6,a2
	dbf	d5,.line
.out:	rts

; Fairy_restore -- put back what Fairy_put saved (Fee_platz, Fee_zeilen
; rows of Fee_gruppen groups, planes 0-4).  Changes d0/d1/a0/a3.
Fairy_restore:
	move.l	Fee_platz,a0
	lea	Fee_rettung,a3
	move.w	Fee_zeilen,d0
	clr.w	Fee_zeilen
	subq.w	#1,d0
.row:	move.w	Fee_gruppen,d1
	subq.w	#1,d1
.group:	move.l	(a3)+,(a0)+
	move.l	(a3)+,(a0)+
	move.w	(a3)+,(a0)
	addq.l	#8,a0
	dbf	d1,.group
	move.w	Fee_gruppen,d1
	lsl.w	#4,d1
	sub.w	d1,a0
	lea	FALCON_ZEILE(a0),a0
	dbf	d0,.row
	rts

; ***************************************************************************
; Plot_setup -- the sparks' hook.  Plot_table: for each byte of workbase
; from row WECHSELZEILE on, the offset of the same 8 pixels in a Falcon
; screen from that row on (Thalion's plots address plane 0; the four other
; Amiga planes of a row get the same, harmless).  plot_jmptab: per Amiga
; colour the Falcon routine; the colour is the same, plane 5 already
; carries the lower bank.
; ***************************************************************************
Plot_setup:
	lea	Plot_table,a0
	moveq	#0,d0			; Falcon offset of the row
	move.w	#AMIGA_ZEILEN-WECHSELZEILE-1,d7
.z:	moveq	#planes-1,d6
.e:	moveq	#0,d1			; byte in the plane's row
.b:	move.w	d1,d2
	lsr.w	#1,d2
	lsl.w	#4,d2
	move.w	d1,d3
	and.w	#1,d3
	or.w	d3,d2
	add.w	d0,d2
	move.w	d2,(a0)+
	addq.w	#1,d1
	cmp.w	#bpscanl/planes,d1
	bne.b	.b
	dbf	d6,.e
	add.w	#FALCON_ZEILE,d0
	dbf	d7,.z
	lea	plot_jmptab,a0
	lea	Plot_routines,a1
	moveq	#32-1,d7
.j:	move.l	(a1)+,(a0)+
	dbf	d7,.j
	rts

; Plot_falcon0..31 -- for Thalion's plot_5p2 instead of .plot00-.plot31:
; a0 = byte in workbase, d0 = its pixels, d1 = not d0.  Set Amiga colour
; \1 there (Pixel_falcon\1).  All registers stay (plot_5p2 calls a1 again
; with a0 + 1).  The table offsets go up to 38,720: unsigned, add.l.
PLOT_FALCON	macro
Plot_falcon\1:
	movem.l	d2/a0,-(sp)
	move.l	a0,d2
	sub.l	#Amiga_schirm+WECHSELZEILE*bpscanl,d2
	cmp.l	#PLOT_BYTES,d2
	bcc.b	.weg\@
	add.l	d2,d2
	lea	Plot_table,a0
	move.w	0(a0,d2.l),d2		; the high word stays 0
	move.l	Plot_target,a0
	add.l	d2,a0
	bsr	Pixel_falcon\1
.weg\@:	movem.l	(sp)+,d2/a0
	rts
	endm

	PLOT_FALCON	0
	PLOT_FALCON	1
	PLOT_FALCON	2
	PLOT_FALCON	3
	PLOT_FALCON	4
	PLOT_FALCON	5
	PLOT_FALCON	6
	PLOT_FALCON	7
	PLOT_FALCON	8
	PLOT_FALCON	9
	PLOT_FALCON	10
	PLOT_FALCON	11
	PLOT_FALCON	12
	PLOT_FALCON	13
	PLOT_FALCON	14
	PLOT_FALCON	15
	PLOT_FALCON	16
	PLOT_FALCON	17
	PLOT_FALCON	18
	PLOT_FALCON	19
	PLOT_FALCON	20
	PLOT_FALCON	21
	PLOT_FALCON	22
	PLOT_FALCON	23
	PLOT_FALCON	24
	PLOT_FALCON	25
	PLOT_FALCON	26
	PLOT_FALCON	27
	PLOT_FALCON	28
	PLOT_FALCON	29
	PLOT_FALCON	30
	PLOT_FALCON	31

Plot_routines:
	dc.l	Plot_falcon0,Plot_falcon1,Plot_falcon2,Plot_falcon3
	dc.l	Plot_falcon4,Plot_falcon5,Plot_falcon6,Plot_falcon7
	dc.l	Plot_falcon8,Plot_falcon9,Plot_falcon10,Plot_falcon11
	dc.l	Plot_falcon12,Plot_falcon13,Plot_falcon14,Plot_falcon15
	dc.l	Plot_falcon16,Plot_falcon17,Plot_falcon18,Plot_falcon19
	dc.l	Plot_falcon20,Plot_falcon21,Plot_falcon22,Plot_falcon23
	dc.l	Plot_falcon24,Plot_falcon25,Plot_falcon26,Plot_falcon27
	dc.l	Plot_falcon28,Plot_falcon29,Plot_falcon30,Plot_falcon31

; ***************************************************************************
; Blitter_warten -- waitblit (fee_vorspann.i): does the blit FAIRY.S set up
; last in Amiga_register, if any (BLTSIZE not 0), in Falcon format.  Since
; Dust_falcon and Magic_falcon only the CHECK_STARS build has any.  FAIRY.S
; has two kinds (minterm in BLTCON0):
;
;   $CA  a star (blit_star, blit_star2): B the image, A its mask, D the
;        place in workbase, the shift in BLTCON0 bits 12-15.  The image
;        number from B, the routine from falcon_fantasy_stars.i.
;   $E2  a column of the logo (make_magic): A in flogo, D in background,
;        BLTBDAT the four pixels.  Into Falcon_background.
;
; Auf dem Amiga startet das Schreiben von BLTSIZE den Blit, und waitblit
; wartet auf sein Ende.  Hier ist BLTSIZE nur eine Speicherstelle; der Blit
; laeuft beim naechsten waitblit.  The Amiga blitter ignores bit 0 of an
; address; blit_star2 passes odd ones.  All registers stay.
; ***************************************************************************
FALCON_BIG_RECIP	equ	(65536+FALCON_BIG_IMAGE-1)/FALCON_BIG_IMAGE
FALCON_SMALL_RECIP	equ	(65536+FALCON_SMALL_IMAGE-1)/FALCON_SMALL_IMAGE

Blitter_warten:
	tst.w	Amiga_register+AR_BLTSIZE
	bne.b	.blit
	rts
.blit:	movem.l	d0-d3/a0-a1,-(sp)
	move.w	Amiga_register+AR_BLTCON0,d0
	cmp.b	#$CA,d0
	beq.b	.star
	cmp.b	#$E2,d0
	beq	.logo
.done:
	clr.w	Amiga_register+AR_BLTSIZE
	movem.l	(sp)+,d0-d3/a0-a1
	rts

.star:	move.l	Amiga_register+AR_BLTDPT,d1
	sub.l	#Amiga_schirm+WECHSELZEILE*bpscanl,d1
	cmp.l	#PLOT_BYTES,d1
	bcc	.done
	and.w	#-2,d1
	add.l	d1,d1
	lea	Plot_table,a0
	move.w	0(a0,d1.l),d1
	move.l	Plot_target,a0
	add.l	d1,a0			; the group of the top row
	move.l	Amiga_register+AR_BLTBPT,d1
	sub.l	#overfunkel,d1
	cmp.l	#FALCON_STARS_BIG*FALCON_BIG_IMAGE,d1
	bcc.b	.small
	mulu	#FALCON_BIG_RECIP,d1
	swap	d1			; image
	bra.b	.frame
.small:	move.l	Amiga_register+AR_BLTBPT,d1
	sub.l	#stars,d1
	cmp.l	#FALCON_STARS_SMALL*FALCON_SMALL_IMAGE,d1
	bcc	.done
	mulu	#FALCON_SMALL_RECIP,d1
	swap	d1
	add.w	#FALCON_STARS_BIG,d1
.frame:	lsl.w	#4,d1
	rol.w	#4,d0
	and.w	#15,d0			; shift
	add.w	d0,d1
	lsl.w	#2,d1
	lea	Falcon_star_routines,a1
	move.l	0(a1,d1.w),a1
	jsr	(a1)
	bra	.done

.logo:	move.l	Amiga_register+AR_BLTDPT,d1
	sub.l	#background+WECHSELZEILE*bpscanl,d1
	cmp.l	#PLOT_BYTES,d1
	bcc	.done
	and.w	#-2,d1
	add.l	d1,d1
	lea	Plot_table,a0
	move.w	0(a0,d1.l),d1
	lea	Falcon_background+WECHSELZEILE*FALCON_ZEILE,a0
	add.l	d1,a0
	move.l	Amiga_register+AR_BLTAPT,d1
	sub.l	#flogo,d1
	cmp.l	#FALCON_LOGO_GROUPS*2,d1
	bcc	.done
	lsr.w	#1,d1
	mulu	#10,d1
	lea	Falcon_logo,a1
	add.w	d1,a1
	move.w	Amiga_register+AR_BLTBDAT,d2
	move.w	d2,d1
	swap	d2
	move.w	d1,d2			; the four pixels, both halves
	moveq	#0,d0
	move.w	Amiga_register+AR_BLTSIZE,d0
	lsr.w	#6,d0
	divu	#planes,d0		; rows
	cmp.w	#FALCON_LOGO_ROWS,d0
	bls.b	.lines
	moveq	#FALCON_LOGO_ROWS,d0
.lines:
	subq.w	#1,d0
	bmi	.done
.lrow:	bsr	Logo_row
	lea	FALCON_ZEILE(a0),a0
	lea	FALCON_LOGO_GROUPS*10(a1),a1
	dbf	d0,.lrow
	bra	.done

; Logo_row -- one row of a logo group: background ^= (background ^ logo)
; & mask, planes 0-4.  a0 = background group, a1 = logo group (5 words),
; d2 = mask in both halves.  Changes d1/d3.
Logo_row:
	move.l	(a0),d1
	move.l	(a1),d3
	eor.l	d1,d3
	and.l	d2,d3
	eor.l	d3,(a0)
	move.l	4(a0),d1
	move.l	4(a1),d3
	eor.l	d1,d3
	and.l	d2,d3
	eor.l	d3,4(a0)
	move.w	8(a0),d1
	move.w	8(a1),d3
	eor.w	d1,d3
	and.w	d2,d3
	eor.w	d3,8(a0)
	rts

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
; Fee_vbl -- the VBL.  Sets picture base and colours from what the main
; flow and the previous VBL left, puts the fairy on the shown screen
; (Fairy_put), then jumps into Thalion's level3 (FAIRY.S), which ends with
; rte.
;
; The fairy is thus one frame behind level3: on the Amiga the sprite DMA
; shows what level3 just set; here we draw what level3 set in the previous
; VBL.  One frame (20 ms) late, without touching Thalion's return with rte.
; ***************************************************************************
Fee_vbl:
	movem.l	d0-d7/a0-a6,-(sp)
	addq.l	#1,FRCLOCK.w		; TOS wartet darauf, nach Bomben schon vor dem Notausgang (T16)
	ifd	ABSTURZTEST
	addq.l	#1,Absturz_zaehler
	endc
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
	move.l	Fee_schirm,d0
	beq.b	.ohne
	move.l	d0,a2
	bsr	Fairy_put
.ohne:	movem.l	(sp)+,d0-d7/a0-a6
	ifd	CHECK_STARS
	tst.b	Check_busy
	beq.b	.level3
	addq.l	#1,Check_held		; level3 calls random: not now
	rte
.level3:
	endc
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

	ifd	FEE_MESSEN
; ***************************************************************************
; Bild_messen -- (FEE_MESSEN) vor dem Warten auf den Takt.  Thalions
; Schleife wartet auf vindex >= 2 und dann noch mit vsync: drei VBL je
; Bild.  Ist vindex hier schon 2, war es knapp, aber noch im Takt; erst ab
; 3 ist das Bild zu spaet.
; ***************************************************************************
Bild_messen:
	move.l	vindex,d0
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

; Messung_zeigen -- (FEE_MESSEN) after the teardown: write the result into
; FEEMESS.TXT, show it on the desktop and wait for a key.
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
	bra	Bericht_ausgeben
	endc

	ifd	CHECK_STARS
; Check_report -- (CHECK_STARS) after the teardown: the counts of
; Check_stars into FEECHECK.TXT and onto the desktop, wait for a key.
Check_report:
	lea	Text_puffer,a1
	lea	Text_check_frames,a0
	bsr	Text_anhaengen
	move.w	Check_frames+2,d0
	bsr	Zahl_schreiben
	lea	Text_check_state,a0
	bsr	Text_anhaengen
	move.w	Check_state_errors+2,d0
	bsr	Zahl_schreiben
	lea	Text_check_pixel,a0
	bsr	Text_anhaengen
	move.w	Check_pixel_errors+2,d0
	bsr	Zahl_schreiben
	lea	Text_check_first,a0
	bsr	Text_anhaengen
	move.w	Check_first_error+2,d0
	bsr	Zahl_schreiben
	lea	Text_check_held,a0
	bsr	Text_anhaengen
	move.w	Check_held+2,d0
	bsr	Zahl_schreiben
	bra	Bericht_ausgeben
	endc

	ifd	FEE_BERICHT
; Bericht_ausgeben -- the text built at Text_puffer up to a1: end it, write
; it into the file Bericht_name (the build names it after the program),
; show it on the desktop and wait for a key.
Bericht_ausgeben:
	lea	Text_messende,a0
	bsr	Text_anhaengen
	clr.b	(a1)
	move.l	a1,d6
	sub.l	#Text_puffer,d6		; length without the zero
	clr.w	-(sp)
	pea	Bericht_name
	move.w	#Fcreate,-(sp)
	trap	#1
	addq.l	#8,sp
	move.w	d0,d7
	bmi.b	.zeigen
	pea	Text_puffer
	move.l	d6,-(sp)
	move.w	d7,-(sp)
	move.w	#Fwrite,-(sp)
	trap	#1
	lea	12(sp),sp
	move.w	d7,-(sp)
	move.w	#Fclose,-(sp)
	trap	#1
	addq.l	#4,sp
.zeigen:
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

; ***************************************************************************
; Daten
; ***************************************************************************
	SECTION	Fee_daten,data
Vier_nach_acht:
	dc.b	$00,$11,$22,$33,$44,$55,$66,$77,$88,$99,$AA,$BB,$CC,$DD,$EE,$FF
Text_kein_falcon:
	dc.b	"Das Fantasy-Intro braucht einen Falcon an RGB oder VGA.",13,10
	dc.b	"Taste druecken.",13,10,0
Text_cursor_aus:
	dc.b	27,'f',0
Text_cursor_an:
	dc.b	27,'e',0
	ifd	FEE_BERICHT
	include	"fee_name.i"		; Bericht_name, from tools/fantasy_bauen.sh
Text_messende:	dc.b	13,10,"Taste druecken.",13,10,0
	endc
	ifd	FEE_MESSEN
Text_bilder:	dc.b	"Fantasy-Intro (E30), Bilder: ",0
Text_knapp:	dc.b	13,10,"knapp (erst nach dem 2. VBL fertig): ",0
Text_spaet:	dc.b	13,10,"zu spaet (erst nach dem 3. VBL): ",0
Text_laengstes:	dc.b	13,10,"hoechstes vindex beim Fertigwerden: ",0
	endc
	ifd	CHECK_STARS
Text_check_frames:	dc.b	"CHECK_STARS, frames compared: ",0
Text_check_state:	dc.b	13,10,"state differs: ",0
Text_check_pixel:	dc.b	13,10,"lower band differs: ",0
Text_check_first:	dc.b	13,10,"first frame that differs: ",0
Text_check_held:	dc.b	13,10,"level3 held back: ",0
	endc
	even

	SECTION	Fee_bss,bss
Alter_ssp:		ds.l	1
Alter_vbl:		ds.l	1
Alter_schirm:		ds.l	1
Alter_mausvektor:	ds.l	1
Kbd_vektoren:		ds.l	1
Anzeige_naechste:	ds.l	1	; picture base: Falcon_show + Anzeige_erste rows
Falcon_a:		ds.l	1
Falcon_b:		ds.l	1	; = Falcon_a + FALCON_ABSTAND
Falcon_show:		ds.l	1
Falcon_work:		ds.l	1
Plot_target:		ds.l	1	; Falcon_work, row WECHSELZEILE
Fee_schirm:		ds.l	1	; the screen the fairy is put on (Falcon_show)
Fee_puffer:		ds.l	1	; Mxalloc, Fairy_buffer_size bytes, or 0
Fee_platz:		ds.l	1	; Fairy_put: the save-under's first group
Fairy_shifts:		ds.l	FALCON_FAIRY_FRAMES*16	; per frame and shift
Fee_zeilen:		ds.w	1	; rows saved, 0: nothing
Fee_gruppen:		ds.w	1	; groups a row saved
Shift_row:		ds.w	1	; next row to preshift (frame * 71 + row)
Alter_modus:		ds.w	1
Neuer_modus:		ds.w	1
Anzeige_zeilen:		ds.w	1
Anzeige_erste:		ds.w	1
Maustasten:		ds.b	1
			even
Alte_st_farben:		ds.w	16
Alte_videl_farben:	ds.l	256
Plot_table:		ds.w	PLOT_BYTES	; workbase byte -> Falcon offset
Fee_rettung:		ds.b	FALCON_FAIRY_ROWS*5*10	; under the fairy, planes 0-4
			cnop	0,4
Amiga_register:		ds.b	AR_GROESSE
	include	"amiga_notaus_bss.i"
	ifd	FEE_MESSEN
Mess_bilder:		ds.w	1
Mess_knapp:		ds.w	1
Mess_spaet:		ds.w	1
Mess_laengstes:		ds.w	1
	endc
	ifd	FEE_BERICHT
Text_puffer:		ds.b	512
	endc
			cnop	0,4
Amiga_schirm:		ds.b	AMIGA_SCHIRM	; workbase: an address range only
Amiga_ueberlauf:	ds.b	AMIGA_UEBERLAUF	; Sterne unter dem Schirm (Vorspann)
Falcon_speicher:	ds.b	2*FALCON_ABSTAND+256
Stapel:			ds.b	4096
Stapel_ende:

	SECTION	Fee_code,code

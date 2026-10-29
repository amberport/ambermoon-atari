; ***************************************************************************
; EFFECTS_SUP.S -- Rest-Unterbau fuer HULL/EFFECTS.S.
;
; Random, Square_root und Delay standen hier, bis HULL/VARIOUS.S kam -- die
; bringt sie mit, also sind sie hier weg (das war der "ersetzt"-Gewinn).
; Uebrig bleiben Get_pixel, der Kratzpuffer und die Clip-Area, die in keiner
; Originaldatei stehen (siehe docs/09).
; ***************************************************************************

; ***************************************************************************
; Get_pixel -- the colour of a point in Work_screen.
;   IN : d0.w = x, d1.w = y
;   OUT: d4 = colour 0-255.  A gradient slot (R_range) comes back as bank
;        + gradient colour, as it was drawn: Thalion's 3D_MAP.S compares
;        it with C3_raster_colour.  On the ST: Thalion's colour number.
;   All other registers are preserved.
;
; Acht Ebenen, wortverschachtelt; Ebene 0 ist das niederwertigste Bit.
; ***************************************************************************
Get_pixel:
	movem.l	d1-d3/a0-a1,-(sp)
	move.l	Work_screen,a0
	move.w	d1,d2			; Zeile
	mulu.w	#SCRROW,d2
	add.l	d2,a0
	move.w	d0,d2			; Block = x / 16
	lsr.w	#4,d2
	mulu.w	#TROW,d2
	add.l	d2,a0			; a0 = Blockanfang, acht Ebenen
	move.w	d0,d3			; Bitnummer im Wort
	and.w	#15,d3
	moveq	#15,d1
	sub.w	d3,d1			; von links gezaehlt
	moveq	#0,d4			; Farbe sammeln
	lea	(PLANES-1)*2(a0),a1	; bei der hoechsten Ebene anfangen
	moveq	#PLANES-1,d2
gp_l:	move.w	(a1),d3
	btst	d1,d3
	beq.b	gp_null
	bset	d2,d4
gp_null:
	subq.l	#2,a1			; eine Ebene tiefer
	dbf	d2,gp_l
	move.w	2(sp),d1		; die Zeile (d1 war hier die Bitnummer)
	jsr	Platz_rueck		; screen colour -> Thalion's (RASTER.S, ST_LIB.S)
	movem.l	(sp)+,d1-d3/a0-a1
	rts

; ***************************************************************************
; Die Clip-Area als Stapel.  Gelesen wird ueber CA_Sp -> Slot -> Satz die
; Raender (CA_X1..CA_Y2); Thalions Push CA,<Satz> / Pop CA verschachteln sie
; (DISPLAY/MINIMAP/AUTOMAP/COMBAT).  Push_CA/Pop_CA gehoeren zur nicht
; freigegebenen Bibliothek -- Thalion definiert sie nicht, also bauen wir sie.
;
; Aufbau im Speicher (aufsteigende Adresse): ca_stack (freie Slots, oben) ...
; ca_bottom (Vollbild) ... CA_Sp.  Der Stapel waechst nach unten: Push zieht
; CA_Sp um vier herunter in ca_stack, Pop hebt ihn zurueck.
; ***************************************************************************
CA_MAX		equ	8			; Verschachtelungstiefe (mit Vollbild)

	SECTION	Fast_DATA,data
	even
ca_full:	dc.w	0,SCRW-1,0,SCRH-1	; Vollbild-Clip: X1, X2, Y1, Y2 (172)
	even
ca_stack:	ds.l	CA_MAX-1		; Platz fuer verschachtelte Push
ca_bottom:	dc.l	ca_full			; unterster Eintrag: Vollbild
CA_Sp:		dc.l	ca_bottom		; Stapelzeiger -> aktueller Eintrag

	SECTION	Fast_BSS,bss
Pixel_buffer:	ds.b	32			; ein Trunc zu 16 Punkten, mit Luft
	even
	SECTION	Program,code

; ***************************************************************************
; Push_CA, Pop_CA -- put a clip area on top, take the topmost off
; (macros Push CA,<record> / Pop CA).  The full screen is never taken off.
;   IN : a0 = CA record X1, X2, Y1, Y2 (Push_CA only)
;   All registers are preserved.
; ***************************************************************************
Push_CA:
	movem.l	d0/a1,-(sp)
	move.l	CA_Sp,d0
	subq.l	#4,d0			; ein Slot nach unten
	cmp.l	#ca_stack,d0		; Ueberlauf?  Dann nicht weiter
	blo.b	pca_out
	move.l	d0,CA_Sp
	move.l	d0,a1
	move.l	a0,(a1)			; Slot zeigt auf den Satz
pca_out:
	movem.l	(sp)+,d0/a1
	rts

Pop_CA:
	movem.l	d0,-(sp)
	move.l	CA_Sp,d0
	cmp.l	#ca_bottom,d0		; Vollbild nie herunternehmen
	bhs.b	poa_out
	addq.l	#4,d0
	move.l	d0,CA_Sp
poa_out:
	movem.l	(sp)+,d0
	rts

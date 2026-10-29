; ***************************************************************************
; VARIOUS_SUP.S -- Unterbau fuer HULL/VARIOUS.S.
;
; VARIOUS.S ist Thalions Datei, unveraendert.  Sie liefert selbst viel
; (Random, Square_root, Delay, Strlen, Wait_4_unclick, Reset_keyboard, ...)
; und loest damit unsere Nachbauten ab.  Neun Symbole braucht sie von
; ausserhalb; die stehen in keiner Originaldatei (docs/09) und darum hier:
;
;   Read_key, Read_Mev   unsere Falcon-Eingabe (Amiga: in der Bibliothek)
;   Copy_memory          Speicher kopieren
;   ATN_table            Arcustangens-Tabelle (Daten)
;   Wait_4_user_Mod      Modul "auf den Benutzer warten"
;   Load_subfile         jetzt in FILES_SUP.S (siehe unten)
;   Music_flag/-handle   stehen in Thalions MAIN.S (siehe unten)
; ***************************************************************************

; ***************************************************************************
; Read_key -- fetch a key without waiting.
;   OUT: d0.l = key code as in Thalion's Read_key (bits below), 0 = none
;   All other registers are preserved.
;
; Ueber die BIOS-Konsole (Geraet 2).
;
; **Die Kennung wie in Thalions Read_key** (AM2_CPU: Tastenhandler 0:$26270,
; Warteschlange 0:$2634A, Read_key 0:$2631C; Erkenntnis 260).  Thalion haengt
; am input.device und baut aus jedem Tastendruck ein Langwort:
;
;   Bit 0-7    das Zeichen, von MapRawKey mit der Tastenbelegung des Systems
;   Bit 16-23  der Amiga-Tastencode (Rawkey)
;   Bit 24     Umschalt, Bit 25 Control, Bit 26 Alt, Bit 27 Caps Lock,
;   Bit 28     Amiga-Taste (Tabelle 4:$4924)
;
; Thalions .Kev-Listen vergleichen in Bit 16-23 mit Amiga-Codes (Ruecktaste
; $41, Cursor $4C-$4F, F-Tasten $50-$59, Ziffern 1-6 = $01-$06, Ziffernblock).
; Wir setzen darum den Atari-Scancode ueber Amiga_tasten in den Amiga-Code
; um; das ist Hardwareschicht.  **Das Zeichen kommt aus Thalions Datei
; Keymap** (Keymap_zeichen), der deutschen Amiga-Belegung, mit der auf dem
; Amiga MapRawKey rechnet.  Vom TOS kam auf der oe-Taste je nach Einstellung
; ";" (Test des Nutzers 2026-09-30, EmuTOS).  Fehlt die Datei, bleibt das
; Zeichen vom TOS; Thalions Input_mask_table kennt beide Zeichensaetze.
; Die Umschalttasten kommen aus Kbshift.
;
; **Help ist die Amiga-Taste, als Vorsatz** (Nutzer, 2026-10-01): der Atari
; hat keine, und Bconin meldet das Loslassen nicht, also laesst sich Help
; nicht halten wie ein Qualifier.  Help selbst kommt nicht an; die naechste
; Taste traegt Bit 28 und geht an die Diagnoselisten (Handle_input,
; Erkenntnis 257, 267).  Thalions Code fragt die Amiga-Help-Taste ($5F)
; nirgends ab.  Help, dann 1: Farbe 0 flackert (Diagnostics_list1).
;
; **Eine Taste ohne Amiga-Gegenstueck wird uebergangen**, nicht als 0
; gemeldet: Thalions Reset_keyboard liest, bis 0 kommt, und liesse sonst den
; Rest des Puffers liegen.
; ***************************************************************************
Read_key:
	movem.l	d1-d3/a0-a2,-(sp)	; die Traps duerfen d0-d2/a0-a2 zerstoeren
rk_l:	move.w	#2,-(sp)		; Geraet 2 = Tastatur
	move.w	#Bconstat,-(sp)
	Bios
	addq.l	#4,sp
	tst.w	d0			; etwas da?
	beq	rk_none
	move.w	#2,-(sp)
	move.w	#Bconin,-(sp)
	Bios
	addq.l	#4,sp
	; d0: Bit 16-23 Atari-Scancode, Bit 0-7 Zeichen
	move.l	d0,d1
	swap	d1
	and.w	#$FF,d1			; Scancode
	cmp.w	#HELP_TASTE,d1		; Help: Vorsatz fuer die Amiga-Taste
	bne.b	rk_keine_help
	st	Amiga_vorsatz
	bra.b	rk_l
rk_keine_help:
	lea	Amiga_tasten,a0
	moveq	#0,d2
	move.b	(a0,d1.w),d2		; Amiga-Code
	cmp.b	#KEIN_AMIGA,d2
	beq.b	rk_l			; nichts Entsprechendes: naechste Taste
	swap	d2
	and.l	#$FF,d0			; nur das Zeichen
	or.l	d2,d0
	move.l	d0,-(sp)
	move.w	#-1,-(sp)		; Umschalttasten nur lesen
	move.w	#Kbshift,-(sp)
	Bios
	addq.l	#4,sp
	move.l	d0,d1			; Kbshift-Bits
	move.l	(sp)+,d0
	lea	Umschalt_bits,a0
	moveq	#0,d2			; Kbshift-Bit
rk_u:	btst	d2,d1
	beq.b	rk_u2
	move.b	(a0,d2.w),d3
	bset	d3,d0
rk_u2:	addq.w	#1,d2
	cmp.w	#UMSCHALT_ANZ,d2
	bne.b	rk_u
	tst.l	km_basis
	beq.b	rk_fertig		; keine Keymap: Zeichen vom TOS
	bsr	Keymap_zeichen
rk_fertig:
	tst.b	Amiga_vorsatz
	beq.b	rk_raus
	sf	Amiga_vorsatz
	bset	#Amiga_key,d0
rk_raus:
	movem.l	(sp)+,d1-d3/a0-a2
	rts
rk_none:
	moveq	#0,d0
	movem.l	(sp)+,d1-d3/a0-a2
	rts

	SECTION	Fast_DATA,data
; Kbshift-Bit 0-4 (rechts Umschalt, links Umschalt, Control, Alternate,
; Caps Lock) -> Bit in Thalions Kennung, wie seine Tabelle 4:$4924 die
; Amiga-Qualifier verteilt.
Umschalt_bits:
	dc.b	24,24,25,26,27
UMSCHALT_ANZ	equ	5
	even

; Atari-Scancode -> Amiga-Rawkey.  Nach der Lage der Taste, bei den beiden
; Zeichentasten ohne gleiche Lage ($29, $2B) nach der Beschriftung der
; deutschen Atari-Tastatur (# und ^ auf Amiga $2B, ~ und | auf $0D); wo der Atari
; eine Taste hat, die der Amiga nicht kennt (Clr/Home, Insert, Undo), steht
; KEIN_AMIGA.  Umschalt+F1-F10, Control+Cursor und Alternate+Ziffer haben
; beim Atari eigene Scancodes; sie werden auf die Grundtaste gelegt, die
; Umschalttaste steht dann in Bit 24-26.  Die Umschalttasten selbst liefert
; Bconin nicht; ihre Eintraege stehen der Vollstaendigkeit halber da.
KEIN_AMIGA	equ	$FF
HELP_TASTE	equ	$62		; Atari-Scancode, Vorsatz fuer die Amiga-Taste
Amiga_tasten:
	dc.b	KEIN_AMIGA,$45		; $00, $01 Esc
	dc.b	$01,$02,$03,$04,$05	; $02-$06 1-5
	dc.b	$06,$07,$08,$09,$0A	; $07-$0B 6-0
	dc.b	$0B,$0C			; $0C ss, $0D Akut
	dc.b	$41,$42			; $0E Ruecktaste, $0F Tab
	dc.b	$10,$11,$12,$13,$14	; $10-$14 q w e r t
	dc.b	$15,$16,$17,$18,$19	; $15-$19 z u i o p
	dc.b	$1A,$1B			; $1A ue, $1B +
	dc.b	$44,$63			; $1C Return, $1D Control
	dc.b	$20,$21,$22,$23,$24	; $1E-$22 a s d f g
	dc.b	$25,$26,$27,$28		; $23-$26 h j k l
	dc.b	$29,$2A			; $27 oe, $28 ae
	dc.b	$2B,$60,$0D		; $29 # ^, $2A Umschalt links, $2B ~ |
	dc.b	$31,$32,$33,$34		; $2C-$2F y x c v
	dc.b	$35,$36,$37		; $30-$32 b n m
	dc.b	$38,$39,$3A		; $33 Komma, $34 Punkt, $35 Minus
	dc.b	$61,KEIN_AMIGA		; $36 Umschalt rechts, $37
	dc.b	$64,$40,$62		; $38 Alternate, $39 Leertaste, $3A Caps Lock
	dc.b	$50,$51,$52,$53,$54	; $3B-$3F F1-F5
	dc.b	$55,$56,$57,$58,$59	; $40-$44 F6-F10
	dc.b	KEIN_AMIGA,KEIN_AMIGA	; $45, $46
	dc.b	KEIN_AMIGA,$4C		; $47 Clr/Home, $48 hoch
	dc.b	KEIN_AMIGA,$4A		; $49, $4A Block -
	dc.b	$4F,KEIN_AMIGA,$4E	; $4B links, $4C, $4D rechts
	dc.b	$5E,KEIN_AMIGA		; $4E Block +, $4F
	dc.b	$4D,KEIN_AMIGA		; $50 runter, $51
	dc.b	KEIN_AMIGA,$46		; $52 Insert, $53 Delete
	dc.b	$50,$51,$52,$53,$54	; $54-$58 Umschalt+F1-F5
	dc.b	$55,$56,$57,$58,$59	; $59-$5D Umschalt+F6-F10
	dc.b	KEIN_AMIGA,KEIN_AMIGA	; $5E, $5F
	dc.b	$30,KEIN_AMIGA,$5F	; $60 < >, $61 Undo, $62 Help
	dc.b	$5A,$5B,$5C,$5D		; $63-$66 Block ( ) / *
	dc.b	$3D,$3E,$3F		; $67-$69 Block 7 8 9
	dc.b	$2D,$2E,$2F		; $6A-$6C Block 4 5 6
	dc.b	$1D,$1E,$1F		; $6D-$6F Block 1 2 3
	dc.b	$0F,$3C,$43		; $70 Block 0, $71 Block Punkt, $72 Enter
	dc.b	$4F,$4E			; $73 Control+links, $74 Control+rechts
	dc.b	KEIN_AMIGA,KEIN_AMIGA,KEIN_AMIGA ; $75, $76, $77 Control+Clr/Home
	dc.b	$01,$02,$03,$04,$05	; $78-$7C Alternate+1-5
	dc.b	$06,$07,$08,$09,$0A	; $7D-$81 Alternate+6-0
	dc.b	$0B,$0C			; $82, $83 Alternate+ss, Alternate+Akut
AMIGA_TASTEN_ANZ	equ	*-Amiga_tasten
	dcb.b	256-AMIGA_TASTEN_ANZ,KEIN_AMIGA
	even

	SECTION	Fast_BSS,bss
KEYMAP_MAX	equ	2048		; die Datei hat 1516 Byte
km_basis:	ds.l	1		; Anfang des Hunks in Keymap_daten, 0 = keine
Keymap_daten:	ds.b	KEYMAP_MAX
	even

	SECTION	Program,code

; ***************************************************************************
; Lade_keymap -- Thalions Datei Keymap nach Keymap_daten (Erkenntnis 260).
;
; Die Datei ist eine Amiga-Hunkdatei mit einem Hunk: $3F3, keine Namen,
; Tabellengroesse, erster und letzter Hunk, deren Groessen, dann $3E9 (Code)
; oder $3EA (Daten), Laenge, Inhalt.  Der Inhalt ist ein KeyMapNode: ein
; Node (14 Byte), dann die KeyMap mit acht Zeigern.  Die Zeiger sind Versaetze
; vom Hunkanfang (die Relokationen dahinter addieren nur die Ladeadresse);
; Keymap_zeichen rechnet darum mit km_basis + Versatz.
; ***************************************************************************
Lade_keymap:
	movem.l	d0-d3/a0-a1,-(sp)
	clr.l	km_basis
	moveq	#Keymap_file,d0
	jsr	Load_file
	tst.l	d0
	beq.b	lk_out			; fehlt: Zeichen vom TOS
	move.w	d0,d3			; d3 = Handle
	jsr	Get_memory_length
	cmp.l	#KEYMAP_MAX,d0
	bhi.b	lk_frei
	move.l	d0,d1
	moveq	#0,d0
	move.w	d3,d0
	jsr	Block_adresse
	move.l	d0,a0
	lea	Keymap_daten,a1
	subq.w	#1,d1
lk_kop:	move.b	(a0)+,(a1)+
	dbf	d1,lk_kop
	; ---- Hunkkopf lesen ----
	lea	Keymap_daten,a0
	cmp.l	#$3F3,(a0)+		; HUNK_HEADER
	bne.b	lk_frei
	tst.l	(a0)+			; keine Bibliotheksnamen
	bne.b	lk_frei
	addq.l	#4,a0			; Tabellengroesse
	move.l	(a0)+,d1		; erster Hunk
	move.l	(a0)+,d2		; letzter Hunk
	sub.l	d1,d2
	addq.l	#1,d2
	lsl.l	#2,d2
	add.l	d2,a0			; die Groessen uebergehen
	move.l	(a0)+,d1
	and.l	#$3FFFFFFF,d1		; Speicherartbits
	cmp.l	#$3E9,d1		; HUNK_CODE
	beq.b	lk_hunk
	cmp.l	#$3EA,d1		; HUNK_DATA
	bne.b	lk_frei
lk_hunk:
	addq.l	#4,a0			; Laenge
	move.l	a0,km_basis
lk_frei:
	moveq	#0,d0
	move.w	d3,d0
	jsr	Free_memory
lk_out:
	movem.l	(sp)+,d0-d3/a0-a1
	rts

; ***************************************************************************
; Keymap_zeichen -- das Zeichen einer Taste aus der Keymap, wie MapRawKey.
;
;   IN : d0 = Tastenkennung (Rawkey Bit 16-23, Umschalt 24, Control 25,
;             Alt 26, Caps Lock 27)
;   OUT: d0 Bit 0-7 = das Zeichen, 0 = keines
;
; KeyMap ab Versatz 14: Lo- und Hi-Typen, -Tabelle, -Caps, -Repeat (Lo fuer
; Rawkey $00-$3F bei 14/18/22, Hi fuer $40-$67 bei 30/34/38).  Je Taste
; ein Typbyte und ein Langwort:
;
;   KCF_NOP ($80), KCF_STRING ($40)  kein einzelnes Zeichen -> 0.  Thalion
;                        nimmt auch nur Ergebnisse mit genau einem Zeichen.
;   KCF_DEAD ($20)       Langwort = Versatz einer Beschreibung: je Umschalt-
;                        stellung zwei Byte (Art, Wert).  Art 0: Wert ist
;                        das Zeichen.  DPF_MOD (1): Wert ist ein Versatz
;                        in der Beschreibung, dort steht zuerst das Zeichen
;                        ohne vorige Tottaste.  DPF_DEAD (8): selbst eine
;                        Tottaste -> 0.  Tottasten setzen wir nicht zusammen.
;   sonst                vier Zeichen im Langwort, Byte 3 ohne Umschalttaste.
;
; Der Index zaehlt nur die Umschalttasten, die der Typ nennt, in der
; Reihenfolge Umschalt (KCF_SHIFT 1), Alt (KCF_ALT 2), Control
; (KCF_CONTROL 4); Byte = 3 - Index.  Bei KC_VANILLA (7) ohne Tottaste zaehlt
; Control nicht mit, sondern loescht Bit 5 und 6 des Zeichens.  Caps Lock
; wirkt auf Tasten mit gesetztem Caps-Bit wie Umschalt.
; ***************************************************************************
Keymap_zeichen:
	movem.l	d1-d5/a0-a1,-(sp)
	move.l	km_basis,a0
	move.l	d0,d1
	swap	d1
	and.w	#$FF,d1			; Rawkey
	moveq	#14,d2			; Lo-Tabellen
	cmp.w	#$40,d1
	blo.b	kz_lo
	sub.w	#$40,d1
	cmp.w	#$68-$40,d1
	bhs	kz_nichts
	moveq	#30,d2			; Hi-Tabellen
kz_lo:
	; ---- Umschalttasten: d3 Bit 0 Umschalt, 1 Alt, 2 Control ----
	moveq	#0,d3
	btst	#24,d0
	beq.b	kz_q1
	bset	#0,d3
kz_q1:	btst	#26,d0
	beq.b	kz_q2
	bset	#1,d3
kz_q2:	btst	#25,d0
	beq.b	kz_q3
	bset	#2,d3
kz_q3:	btst	#27,d0			; Caps Lock
	beq.b	kz_typ
	move.l	8(a0,d2.w),d4		; Caps-Tabelle, ein Bit je Taste
	lea	(a0,d4.l),a1
	move.w	d1,d4
	lsr.w	#3,d4
	move.b	(a1,d4.w),d4
	move.w	d1,d5
	and.w	#7,d5
	btst	d5,d4
	beq.b	kz_typ
	bset	#0,d3			; wie Umschalt
kz_typ:
	move.l	(a0,d2.w),d4		; Typentabelle
	lea	(a0,d4.l),a1
	moveq	#0,d4
	move.b	(a1,d1.w),d4		; d4 = Typ
	move.l	4(a0,d2.w),d5		; Zeichentabelle
	lea	(a0,d5.l),a1
	lsl.w	#2,d1
	add.w	d1,a1			; a1 = Langwort der Taste
	btst	#7,d4			; KCF_NOP
	bne	kz_nichts
	btst	#6,d4			; KCF_STRING
	bne	kz_nichts
	; ---- Index aus den Umschalttasten, die der Typ nennt ----
	moveq	#0,d5			; Index
	moveq	#1,d2			; naechstes Indexbit
	btst	#0,d4			; KCF_SHIFT
	beq.b	kz_i1
	btst	#0,d3
	beq.b	kz_i0
	or.w	d2,d5
kz_i0:	add.w	d2,d2
kz_i1:	btst	#1,d4			; KCF_ALT
	beq.b	kz_i3
	btst	#1,d3
	beq.b	kz_i2
	or.w	d2,d5
kz_i2:	add.w	d2,d2
kz_i3:	btst	#2,d4			; KCF_CONTROL
	beq.b	kz_i4
	move.w	d4,d1
	and.w	#$27,d1
	cmp.w	#$07,d1			; KC_VANILLA ohne Tottaste: nicht im Index
	beq.b	kz_i4
	btst	#2,d3
	beq.b	kz_i4
	or.w	d2,d5
kz_i4:
	btst	#5,d4			; KCF_DEAD
	bne.b	kz_tot
	; ---- vier Zeichen im Langwort ----
	moveq	#3,d1
	sub.w	d5,d1
	moveq	#0,d2
	move.b	(a1,d1.w),d2
	and.w	#7,d4
	cmp.w	#7,d4			; KC_VANILLA
	bne.b	kz_fertig
	btst	#2,d3			; mit Control
	beq.b	kz_fertig
	and.b	#$9F,d2
	bra.b	kz_fertig
	; ---- Beschreibung einer Tottaste ----
kz_tot:
	move.l	(a1),d1			; Versatz der Beschreibung
	lea	(a0,d1.l),a1
	add.w	d5,d5			; zwei Byte je Stellung
	move.b	(a1,d5.w),d1		; Art
	moveq	#0,d2
	move.b	1(a1,d5.w),d2		; Wert
	tst.b	d1
	beq.b	kz_fertig		; das Zeichen selbst
	btst	#0,d1			; DPF_MOD?
	beq.b	kz_nichts		; DPF_DEAD: selbst eine Tottaste
	move.b	(a1,d2.w),d2		; das Zeichen ohne vorige Tottaste
	bra.b	kz_fertig
kz_nichts:
	moveq	#0,d2
kz_fertig:
	and.l	#$FFFFFF00,d0
	and.w	#$FF,d2
	or.w	d2,d0
	movem.l	(sp)+,d1-d5/a0-a1
	rts

; ***************************************************************************
; Read_Mev -- ein Mausereignis holen, aus der Warteschlange der Bibliothek.
; Gefuellt wird sie im VBL (Maus_vbl, HULL/LIBRARY.S): ein Eintrag je Bild,
; solange Button_state nicht 0 ist.
;
;   OUT: d0 = X, d1 = Y, d2 = Button_state (Maus_vbl), 0 = keines
;
; So erwartet es sein Handle_input ("jsr Read_Mev / tst.w d2 / bne .Mev",
; danach Find_object mit d0/d1) und sein Reset_mouse_buffer, das schleift,
; bis d2 null ist.  Die Interruptsperre haelt Kopf und Ende beisammen.
Read_Mev:
	move.l	a1,-(sp)
	move.w	sr,-(sp)
	ori.w	#$0700,sr
	moveq	#0,d2
	moveq	#0,d1
	move.w	mev_ende,d1
	cmp.w	mev_kopf,d1
	beq.b	rm_leer
	moveq	#0,d0
	move.w	d1,d0
	mulu.w	#6,d0
	lea	mev_puffer,a1
	add.w	d0,a1
	addq.w	#1,d1
	and.w	#MEV_ANZ-1,d1
	move.w	d1,mev_ende
	moveq	#0,d0
	moveq	#0,d1
	move.w	(a1)+,d0		; X
	move.w	(a1)+,d1		; Y
	move.w	(a1),d2			; Tasten
	bra.b	rm_out
rm_leer:
	moveq	#0,d0
	moveq	#0,d1
rm_out:
	move.w	(sp)+,sr
	move.l	(sp)+,a1
	rts

MEV_ANZ	equ	64			; Zweierpotenz; 1.20 hat 50 Plaetze
	SECTION	Fast_BSS,bss
	even
mev_kopf:	ds.w	1		; naechster freier Eintrag
mev_ende:	ds.w	1		; naechster zu lesender
	even
mev_puffer:	ds.w	MEV_ANZ*3	; je X, Y, Tasten
	SECTION	Program,code

; ***************************************************************************
; Copy_memory -- d0 Byte von (a0) nach (a1).  Alle Register bleiben.
; ***************************************************************************
Copy_memory:
	movem.l	d0/a0-a1,-(sp)
	tst.l	d0
	beq.b	copm_out
copm_l:	move.b	(a0)+,(a1)+
	subq.l	#1,d0
	bne.b	copm_l
copm_out:
	movem.l	(sp)+,d0/a0-a1
	rts

; Load_subfile stand hier als Stub ("nichts geladen"), solange wir die
; Spieldaten vorab konvertiert haben.  Der echte Laufzeit-Entpacker ist das
; zweite Leitziel und steht jetzt in HULL/FILES_SUP.S.

; Music_routine stand hier als Stub; seit 2026-10-01 ist es Thalions
; Spieler aus AM2_CPU (am2cpu_code.py, MUSIK_SUP.S, docs/13).

; Wait_4_user_Mod stand hier bis Stufe (c); seitdem kommt es aus Thalions
; MODULES.S.
	SECTION	Fast_DATA,data
	even

; Music_flag steht in Thalions MAIN.S; Thalions Init_program setzt es aus
; Internal_flags.  Ist es gesetzt, ruft Bibliothek_vbl (LIBRARY.S) den Takt
; des Musikspielers (MUSIK_SUP.S, docs/13).

; ***************************************************************************
; ATN_table -- Arcustangens, 1025 Worte.  Index k (0..1024) = Dx/Dy * 1024;
; Wert = round(atan(k/1024) / 2pi * 4096), passend zu Calculate_ATN in
; VARIOUS.S.  **Ungeprueft** -- Calculate_ATN wird von keiner eingebundenen
; Datei gerufen (erst 3D/Kampf); die Herleitung stimmt rechnerisch, ist aber
; im Lauf noch nicht bestaetigt.
	even
ATN_table:
	dc.w	$0000,$0001,$0001,$0002,$0003,$0003,$0004,$0004
	dc.w	$0005,$0006,$0006,$0007,$0008,$0008,$0009,$000a
	dc.w	$000a,$000b,$000b,$000c,$000d,$000d,$000e,$000f
	dc.w	$000f,$0010,$0011,$0011,$0012,$0012,$0013,$0014
	dc.w	$0014,$0015,$0016,$0016,$0017,$0018,$0018,$0019
	dc.w	$0019,$001a,$001b,$001b,$001c,$001d,$001d,$001e
	dc.w	$001f,$001f,$0020,$0020,$0021,$0022,$0022,$0023
	dc.w	$0024,$0024,$0025,$0026,$0026,$0027,$0027,$0028
	dc.w	$0029,$0029,$002a,$002b,$002b,$002c,$002c,$002d
	dc.w	$002e,$002e,$002f,$0030,$0030,$0031,$0032,$0032
	dc.w	$0033,$0033,$0034,$0035,$0035,$0036,$0037,$0037
	dc.w	$0038,$0039,$0039,$003a,$003a,$003b,$003c,$003c
	dc.w	$003d,$003e,$003e,$003f,$003f,$0040,$0041,$0041
	dc.w	$0042,$0043,$0043,$0044,$0045,$0045,$0046,$0046
	dc.w	$0047,$0048,$0048,$0049,$004a,$004a,$004b,$004b
	dc.w	$004c,$004d,$004d,$004e,$004f,$004f,$0050,$0050
	dc.w	$0051,$0052,$0052,$0053,$0054,$0054,$0055,$0055
	dc.w	$0056,$0057,$0057,$0058,$0059,$0059,$005a,$005a
	dc.w	$005b,$005c,$005c,$005d,$005e,$005e,$005f,$005f
	dc.w	$0060,$0061,$0061,$0062,$0063,$0063,$0064,$0064
	dc.w	$0065,$0066,$0066,$0067,$0068,$0068,$0069,$0069
	dc.w	$006a,$006b,$006b,$006c,$006c,$006d,$006e,$006e
	dc.w	$006f,$0070,$0070,$0071,$0071,$0072,$0073,$0073
	dc.w	$0074,$0075,$0075,$0076,$0076,$0077,$0078,$0078
	dc.w	$0079,$0079,$007a,$007b,$007b,$007c,$007d,$007d
	dc.w	$007e,$007e,$007f,$0080,$0080,$0081,$0081,$0082
	dc.w	$0083,$0083,$0084,$0084,$0085,$0086,$0086,$0087
	dc.w	$0088,$0088,$0089,$0089,$008a,$008b,$008b,$008c
	dc.w	$008c,$008d,$008e,$008e,$008f,$008f,$0090,$0091
	dc.w	$0091,$0092,$0092,$0093,$0094,$0094,$0095,$0095
	dc.w	$0096,$0097,$0097,$0098,$0098,$0099,$009a,$009a
	dc.w	$009b,$009c,$009c,$009d,$009d,$009e,$009f,$009f
	dc.w	$00a0,$00a0,$00a1,$00a1,$00a2,$00a3,$00a3,$00a4
	dc.w	$00a4,$00a5,$00a6,$00a6,$00a7,$00a7,$00a8,$00a9
	dc.w	$00a9,$00aa,$00aa,$00ab,$00ac,$00ac,$00ad,$00ad
	dc.w	$00ae,$00af,$00af,$00b0,$00b0,$00b1,$00b2,$00b2
	dc.w	$00b3,$00b3,$00b4,$00b4,$00b5,$00b6,$00b6,$00b7
	dc.w	$00b7,$00b8,$00b9,$00b9,$00ba,$00ba,$00bb,$00bc
	dc.w	$00bc,$00bd,$00bd,$00be,$00be,$00bf,$00c0,$00c0
	dc.w	$00c1,$00c1,$00c2,$00c3,$00c3,$00c4,$00c4,$00c5
	dc.w	$00c5,$00c6,$00c7,$00c7,$00c8,$00c8,$00c9,$00ca
	dc.w	$00ca,$00cb,$00cb,$00cc,$00cc,$00cd,$00ce,$00ce
	dc.w	$00cf,$00cf,$00d0,$00d0,$00d1,$00d2,$00d2,$00d3
	dc.w	$00d3,$00d4,$00d4,$00d5,$00d6,$00d6,$00d7,$00d7
	dc.w	$00d8,$00d8,$00d9,$00da,$00da,$00db,$00db,$00dc
	dc.w	$00dc,$00dd,$00de,$00de,$00df,$00df,$00e0,$00e0
	dc.w	$00e1,$00e1,$00e2,$00e3,$00e3,$00e4,$00e4,$00e5
	dc.w	$00e5,$00e6,$00e7,$00e7,$00e8,$00e8,$00e9,$00e9
	dc.w	$00ea,$00ea,$00eb,$00ec,$00ec,$00ed,$00ed,$00ee
	dc.w	$00ee,$00ef,$00ef,$00f0,$00f1,$00f1,$00f2,$00f2
	dc.w	$00f3,$00f3,$00f4,$00f4,$00f5,$00f6,$00f6,$00f7
	dc.w	$00f7,$00f8,$00f8,$00f9,$00f9,$00fa,$00fa,$00fb
	dc.w	$00fc,$00fc,$00fd,$00fd,$00fe,$00fe,$00ff,$00ff
	dc.w	$0100,$0100,$0101,$0102,$0102,$0103,$0103,$0104
	dc.w	$0104,$0105,$0105,$0106,$0106,$0107,$0107,$0108
	dc.w	$0109,$0109,$010a,$010a,$010b,$010b,$010c,$010c
	dc.w	$010d,$010d,$010e,$010e,$010f,$0110,$0110,$0111
	dc.w	$0111,$0112,$0112,$0113,$0113,$0114,$0114,$0115
	dc.w	$0115,$0116,$0116,$0117,$0117,$0118,$0119,$0119
	dc.w	$011a,$011a,$011b,$011b,$011c,$011c,$011d,$011d
	dc.w	$011e,$011e,$011f,$011f,$0120,$0120,$0121,$0121
	dc.w	$0122,$0122,$0123,$0123,$0124,$0125,$0125,$0126
	dc.w	$0126,$0127,$0127,$0128,$0128,$0129,$0129,$012a
	dc.w	$012a,$012b,$012b,$012c,$012c,$012d,$012d,$012e
	dc.w	$012e,$012f,$012f,$0130,$0130,$0131,$0131,$0132
	dc.w	$0132,$0133,$0133,$0134,$0134,$0135,$0135,$0136
	dc.w	$0136,$0137,$0137,$0138,$0138,$0139,$0139,$013a
	dc.w	$013a,$013b,$013b,$013c,$013c,$013d,$013d,$013e
	dc.w	$013e,$013f,$013f,$0140,$0140,$0141,$0141,$0142
	dc.w	$0142,$0143,$0143,$0144,$0144,$0145,$0145,$0146
	dc.w	$0146,$0147,$0147,$0148,$0148,$0149,$0149,$014a
	dc.w	$014a,$014b,$014b,$014c,$014c,$014d,$014d,$014e
	dc.w	$014e,$014f,$014f,$014f,$0150,$0150,$0151,$0151
	dc.w	$0152,$0152,$0153,$0153,$0154,$0154,$0155,$0155
	dc.w	$0156,$0156,$0157,$0157,$0158,$0158,$0159,$0159
	dc.w	$015a,$015a,$015a,$015b,$015b,$015c,$015c,$015d
	dc.w	$015d,$015e,$015e,$015f,$015f,$0160,$0160,$0161
	dc.w	$0161,$0162,$0162,$0162,$0163,$0163,$0164,$0164
	dc.w	$0165,$0165,$0166,$0166,$0167,$0167,$0168,$0168
	dc.w	$0168,$0169,$0169,$016a,$016a,$016b,$016b,$016c
	dc.w	$016c,$016d,$016d,$016e,$016e,$016e,$016f,$016f
	dc.w	$0170,$0170,$0171,$0171,$0172,$0172,$0173,$0173
	dc.w	$0173,$0174,$0174,$0175,$0175,$0176,$0176,$0177
	dc.w	$0177,$0177,$0178,$0178,$0179,$0179,$017a,$017a
	dc.w	$017b,$017b,$017b,$017c,$017c,$017d,$017d,$017e
	dc.w	$017e,$017f,$017f,$017f,$0180,$0180,$0181,$0181
	dc.w	$0182,$0182,$0183,$0183,$0183,$0184,$0184,$0185
	dc.w	$0185,$0186,$0186,$0186,$0187,$0187,$0188,$0188
	dc.w	$0189,$0189,$0189,$018a,$018a,$018b,$018b,$018c
	dc.w	$018c,$018d,$018d,$018d,$018e,$018e,$018f,$018f
	dc.w	$018f,$0190,$0190,$0191,$0191,$0192,$0192,$0192
	dc.w	$0193,$0193,$0194,$0194,$0195,$0195,$0195,$0196
	dc.w	$0196,$0197,$0197,$0198,$0198,$0198,$0199,$0199
	dc.w	$019a,$019a,$019a,$019b,$019b,$019c,$019c,$019d
	dc.w	$019d,$019d,$019e,$019e,$019f,$019f,$019f,$01a0
	dc.w	$01a0,$01a1,$01a1,$01a1,$01a2,$01a2,$01a3,$01a3
	dc.w	$01a3,$01a4,$01a4,$01a5,$01a5,$01a6,$01a6,$01a6
	dc.w	$01a7,$01a7,$01a8,$01a8,$01a8,$01a9,$01a9,$01aa
	dc.w	$01aa,$01aa,$01ab,$01ab,$01ac,$01ac,$01ac,$01ad
	dc.w	$01ad,$01ae,$01ae,$01ae,$01af,$01af,$01b0,$01b0
	dc.w	$01b0,$01b1,$01b1,$01b2,$01b2,$01b2,$01b3,$01b3
	dc.w	$01b3,$01b4,$01b4,$01b5,$01b5,$01b5,$01b6,$01b6
	dc.w	$01b7,$01b7,$01b7,$01b8,$01b8,$01b9,$01b9,$01b9
	dc.w	$01ba,$01ba,$01ba,$01bb,$01bb,$01bc,$01bc,$01bc
	dc.w	$01bd,$01bd,$01be,$01be,$01be,$01bf,$01bf,$01bf
	dc.w	$01c0,$01c0,$01c1,$01c1,$01c1,$01c2,$01c2,$01c3
	dc.w	$01c3,$01c3,$01c4,$01c4,$01c4,$01c5,$01c5,$01c6
	dc.w	$01c6,$01c6,$01c7,$01c7,$01c7,$01c8,$01c8,$01c9
	dc.w	$01c9,$01c9,$01ca,$01ca,$01ca,$01cb,$01cb,$01cb
	dc.w	$01cc,$01cc,$01cd,$01cd,$01cd,$01ce,$01ce,$01ce
	dc.w	$01cf,$01cf,$01d0,$01d0,$01d0,$01d1,$01d1,$01d1
	dc.w	$01d2,$01d2,$01d2,$01d3,$01d3,$01d4,$01d4,$01d4
	dc.w	$01d5,$01d5,$01d5,$01d6,$01d6,$01d6,$01d7,$01d7
	dc.w	$01d7,$01d8,$01d8,$01d9,$01d9,$01d9,$01da,$01da
	dc.w	$01da,$01db,$01db,$01db,$01dc,$01dc,$01dc,$01dd
	dc.w	$01dd,$01de,$01de,$01de,$01df,$01df,$01df,$01e0
	dc.w	$01e0,$01e0,$01e1,$01e1,$01e1,$01e2,$01e2,$01e2
	dc.w	$01e3,$01e3,$01e3,$01e4,$01e4,$01e4,$01e5,$01e5
	dc.w	$01e6,$01e6,$01e6,$01e7,$01e7,$01e7,$01e8,$01e8
	dc.w	$01e8,$01e9,$01e9,$01e9,$01ea,$01ea,$01ea,$01eb
	dc.w	$01eb,$01eb,$01ec,$01ec,$01ec,$01ed,$01ed,$01ed
	dc.w	$01ee,$01ee,$01ee,$01ef,$01ef,$01ef,$01f0,$01f0
	dc.w	$01f0,$01f1,$01f1,$01f1,$01f2,$01f2,$01f2,$01f3
	dc.w	$01f3,$01f3,$01f4,$01f4,$01f4,$01f5,$01f5,$01f5
	dc.w	$01f6,$01f6,$01f6,$01f7,$01f7,$01f7,$01f8,$01f8
	dc.w	$01f8,$01f9,$01f9,$01f9,$01fa,$01fa,$01fa,$01fb
	dc.w	$01fb,$01fb,$01fc,$01fc,$01fc,$01fc,$01fd,$01fd
	dc.w	$01fd,$01fe,$01fe,$01fe,$01ff,$01ff,$01ff,$0200
	dc.w	$0200

	SECTION	Fast_BSS,bss
; Music_handle steht in Thalions MAIN.S.
	even
	SECTION	Program,code

	SECTION	Fast_BSS,bss
Amiga_vorsatz:	ds.b	1		; gesetzt: Help gedrueckt, Bit 28 fuer die naechste Taste
	even
	SECTION	Program,code

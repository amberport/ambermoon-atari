; ***************************************************************************
; MISCHER.S -- the Paula mixer: Thalion's Sonic Arranger player on the Falcon's sound.
;
; A module for the game (engine/src/HULL/MUSIK_SUP.S), the intro and the
; extro (docs/11, E14).  No SECTION: the code lands in the code section of
; whoever includes it.  Data in mischer_daten.i, variables in
; mischer_bss.i, the DMA ring in mischer_chip.i (it must lie in ST-RAM).
; mischer_daten.i includes build/musik_dsp.dsp (tools/musik_dsp.sh).
;
; **The player writes the Amiga hardware**; the build bends those operands
; onto a shadow block with the layout of the custom registers ($000-$1FF):
; AUDxLC/LEN/PER/VOL at $A0..$DF, DMACON at $96.  The mixer reads that
; shadow after every tick, like the Paula reads her registers.
;
; **Entry points** (supervisor mode):
;   Mischer_install  a0 = parameter block (MS_*, below).  Sets up the sound
;                    and starts it.  Sound locked, wrong machine, or wahl 0:
;                    stays silent, and no tick runs.
;   Mischer_remove   sound off, DSP stopped, the sound registers as they were
;                    before Mischer_install.  Only XBIOS, so it is safe from
;                    etv_term.  Harmless without Mischer_install.
;   Mischer_vbl      once per VBL.  Mixes ahead and calls the tick.
;   Mischer_stand    d0 = 0 silent, 1 CPU, 2 DSP, 3 DSP dead (md_tot).
;   Mischer_snd      d0 = cookie _SND (0 without one).
; Which mixer, if any, the caller takes from Settings_music (AMBER.INF,
; shared/SETTINGS.S, E17).
; All of them keep every register except the stated d0.
;
; **The tick comes from the sound, not from the VBL:** for every 1/50 s of
; sound mixed, the mixer calls the tick routine once (Thalion's +24).  At
; VGA (60 Hz) the music does not run faster.
;
; **Paula:** per channel the mixer keeps what the Paula has inside:
; pointer, length, position.  DMACON with bit 15 restarts the channels from
; AUDxLC/LEN (Thalion writes "off" at a note and "on" at the end of the
; tick; only the "on" stays in the shadow, so "on" means restart here).
; DMACON without bit 15 switches off.  When a block is done, the channel
; reloads LC and LEN from the shadow -- that is how Thalion's loop arrives
; (AM2_CPU 0:$2AD34).  Period and volume count per piece of 1/50 s.  An
; address outside memory is not read (0:$2B38E writes only one word to
; LC): the channel plays silence until it reloads.  The low pass filter is
; ignored.
;
; **Two ways:** the DSP mixes (MUSIK_DSP.A56, md_*), or, when it is taken or
; wahl says so, the processor with DMA sound (mk_*).  Both give 16 bit
; stereo at 12 292 Hz, channels 0 and 3 left, 1 and 2 right.
;
; All 68000 code.  Only the sound hardware is Falcon.  docs/13 4b-4e, E14.
; ***************************************************************************

; ---------------------------------------------------------------------------
; The parameter block (a0 at Mischer_install).  It is copied; the pointers in
; it must stay valid until Mischer_remove.
MS_SCHATTEN	equ	0	; l  Paula shadow, $200 bytes, custom-register layout
MS_TAKT		equ	4	; l  tick routine, called per 1/50 s of sound;
				;    must keep all registers
MS_MERKER	equ	8	; l  byte "music on": tick only if <> 0; 0 = always
MS_STUECK	equ	12	; l  word: number of the playing song (0 = none) ---
MS_LIED		equ	16	; l  long: pointer to its first area                |
MS_SAETZE	equ	20	; l  first of the four channel records         4e, 0 = without
MS_STILLE	equ	24	; l  the player's silence (6 bytes)             ---
MS_WAHL		equ	28	; w  0 silent, MISCHER_DSP, MISCHER_CPU
MS_GROESSE	equ	30

MISCHER_DSP	equ	1		; DSP, if free; else the processor
MISCHER_CPU	equ	2		; always the processor

; The four 4e fields describe the player in AM2_CPU (am2cpu_code.py names
; them Playing_music, Am2cpu_3_03AFE, Am2cpu_3_037BE, Am2cpu_3_03AF6).  With
; them the DSP keeps the song's samples and the synth buffers and only hears
; where each channel reads.  Without them (0) the processor sends the bytes
; each channel reads; that costs more time on the host port, nothing else.

; XBIOS saves no registers: d0-d2/a0-a2 may be destroyed (TOS 4.04 does,
; finding 270).  The arguments are already on the stack, so the registers
; go to a fixed place; nothing in here calls TOS from inside a trap.
Mx_xbios	MACRO
	movem.l	d1-d2/a0-a2,mx_rette
	trap	#14
	movem.l	mx_rette,d1-d2/a0-a2
	ENDM

Mx_gemdos	MACRO
	movem.l	d1-d2/a0-a2,mx_rette
	trap	#1
	movem.l	mx_rette,d1-d2/a0-a2
	ENDM

MUSIK_VORTEILER	equ	7		; 12 292 Hz
MUSIK_STUECK	equ	246		; samples per tick (12 292 / 50)
MUSIK_STUECK_B	equ	MUSIK_STUECK*4	; 16 bit stereo
MUSIK_STUECKE	equ	8		; ring size
MUSIK_RING_B	equ	MUSIK_STUECKE*MUSIK_STUECK_B
MUSIK_VORAUS	equ	3		; pieces ahead of playback
; step = Paula clock / period / output rate, 16.16 fixed point:
; 3 546 895 * 65536 / 12 292 = 18 910 618 = $0120_8D9A.
PAULA_K_HI	equ	$0120
PAULA_K_LO	equ	$8D9A
PAULA_PER_MIN	equ	113		; smallest Paula period (DMA)

; XBIOS, Falcon sound
xb_Locksnd	equ	128
xb_Unlocksnd	equ	129
xb_Soundcmd	equ	130
xb_Setbuffer	equ	131
xb_Setmode	equ	132
xb_Settracks	equ	133
xb_Setmontracks	equ	134
xb_Buffoper	equ	136
xb_Devconnect	equ	139
xb_Sndstatus	equ	140
xb_Dsptristate	equ	137
xb_Dsp_Lock	equ	104
xb_Dsp_Unlock	equ	105
xb_Dsp_ExecBoot	equ	110
xb_Dsp_ReqAbil	equ	113		; Dsp_RequestUniqueAbility

; State per channel
mk_an		equ	0		; byte: DMA on
mk_zeiger	equ	2		; block start (the Paula: internal LC)
mk_laenge	equ	6		; block length in bytes
mk_pos		equ	10		; position in block, integer part
mk_bruch	equ	14		; position, fraction (word)
mk_groesse	equ	16

; ---------------------------------------------------------------------------
; Mischer_snd -- d0 = cookie _SND, 0 without cookie jar or cookie.  Bit 2
; 16-bit sound, bit 3 DSP, bit 4 matrix.  Supervisor.
Mischer_snd:
	move.l	a0,-(sp)
	moveq	#0,d0
	move.l	$5A0.w,a0		; _p_cookies; 0 = no cookie jar
	cmp.w	#0,a0
	beq.s	.raus
.such:	tst.l	(a0)
	beq.s	.raus			; end of the list, no _SND
	cmp.l	#'_SND',(a0)
	beq.s	.da
	addq.l	#8,a0
	bra.s	.such
.da:	move.l	4(a0),d0
.raus:	move.l	(sp)+,a0
	rts

; ---------------------------------------------------------------------------
; Mischer_stand -- d0 = 0 silent, 1 CPU, 2 DSP, 3 DSP dead.
Mischer_stand:
	moveq	#0,d0
	tst.b	mk_bereit
	beq.s	.raus
	moveq	#1,d0
	tst.b	md_dsp
	beq.s	.raus
	moveq	#2,d0
	tst.b	md_tot
	beq.s	.raus
	moveq	#3,d0
.raus:	rts

; ---------------------------------------------------------------------------
; Mischer_install -- a0 = parameter block.  Needs 16-bit sound and the
; matrix in the cookie _SND (2026-10-09: Locksnd alone is not enough,
; Hatari with EmuTOS as STE accepts it), the DSP way also bit 3.
Mischer_install:
	movem.l	d0-d2/a0-a2,-(sp)
	tst.b	mk_bereit
	bne	.raus			; already running
	lea	mx_satz,a1
	moveq	#MS_GROESSE/2-1,d0
.satz:	move.w	(a0)+,(a1)+
	dbf	d0,.satz
	tst.w	mx_satz+MS_WAHL
	beq	.raus			; silent: no sound, no DSP, no tick
	bsr	Mischer_snd
	move.b	d0,mx_snd
	btst	#2,d0			; 16-bit sound
	beq	.raus
	btst	#4,d0			; matrix (Devconnect)
	beq	.raus
	; volume table: row v (0..64), column b (unsigned byte)
	; = (b signed) * v.  Two channels per side stay within 16 bits.
	lea	Musik_lautst,a0
	moveq	#0,d1			; v
.zeile:	moveq	#0,d2			; b
.spalte:
	move.b	d2,d0
	ext.w	d0
	muls	d1,d0
	move.w	d0,(a0)+
	addq.w	#1,d2
	cmp.w	#256,d2
	blo.s	.spalte
	addq.w	#1,d1
	cmp.w	#64,d1
	bls.s	.zeile
	lea	Musik_kanaele,a0	; channels off, nothing in the DSP yet
	moveq	#4*mk_groesse/2-1,d0
.kanal:	clr.w	(a0)+
	dbf	d0,.kanal
	clr.l	mk_schreib
	clr.l	md_s_lied
	clr.l	md_s_anfang
	clr.l	md_s_ende
	clr.w	md_s_nr
	sf	md_syn_gueltig
	move.w	#xb_Locksnd,-(sp)
	Mx_xbios
	addq.l	#2,sp
	cmp.l	#1,d0
	bne	.raus
	bsr	mx_sichern		; the sound registers as TOS left them
	move.w	#1,-(sp)		; Sndstatus(1): reset
	move.w	#xb_Sndstatus,-(sp)
	Mx_xbios
	addq.l	#4,sp
	cmp.w	#MISCHER_CPU,mx_satz+MS_WAHL
	beq.s	.prozessor
	btst	#3,mx_snd		; no DSP
	beq.s	.prozessor
	bsr	md_install		; the DSP mixes
	tst.b	md_dsp
	bne.s	.tonweg
.prozessor:
	clr.l	-(sp)			; Settracks(0,0)
	move.w	#xb_Settracks,-(sp)
	Mx_xbios
	addq.l	#6,sp
	clr.w	-(sp)			; Setmontracks(0)
	move.w	#xb_Setmontracks,-(sp)
	Mx_xbios
	addq.l	#4,sp
	move.w	#1,-(sp)		; Setmode(1): 16 bit stereo
	move.w	#xb_Setmode,-(sp)
	Mx_xbios
	addq.l	#4,sp
	move.w	#1,-(sp)		; no handshake
	move.w	#MUSIK_VORTEILER,-(sp)
	clr.w	-(sp)			; 25.175 MHz
	move.w	#8,-(sp)		; to the DAC
	clr.w	-(sp)			; from DMA playback
	move.w	#xb_Devconnect,-(sp)
	Mx_xbios
	lea	12(sp),sp
.tonweg:
	move.w	#2,-(sp)		; Soundcmd(ADDERIN, matrix)
	move.w	#4,-(sp)
	move.w	#xb_Soundcmd,-(sp)
	Mx_xbios
	addq.l	#6,sp
	clr.w	-(sp)			; Soundcmd(LTATTEN, 0)
	clr.w	-(sp)
	move.w	#xb_Soundcmd,-(sp)
	Mx_xbios
	addq.l	#6,sp
	clr.w	-(sp)			; Soundcmd(RTATTEN, 0)
	move.w	#1,-(sp)
	move.w	#xb_Soundcmd,-(sp)
	Mx_xbios
	addq.l	#6,sp
	tst.b	md_dsp
	bne.s	.bereit
	pea	Musik_ring+MUSIK_RING_B	; Setbuffer(0, start, end)
	pea	Musik_ring
	clr.w	-(sp)
	move.w	#xb_Setbuffer,-(sp)
	Mx_xbios
	lea	12(sp),sp
	move.w	#3,-(sp)		; Buffoper(PLAY_ENABLE|PLAY_REPEAT)
	move.w	#xb_Buffoper,-(sp)
	Mx_xbios
	addq.l	#4,sp
.bereit:
	st	mk_bereit
.raus:	movem.l	(sp)+,d0-d2/a0-a2
	rts

; ---------------------------------------------------------------------------
; Mischer_remove -- sound off, DSP and sound released, and the sound as it
; was before (docs/13 5.7).  Until 2026-10-12 the DSP way ended with
; Sndstatus(1) and left the mixer running in the DSP; afterwards a YM
; game stayed silent, and after either way the desktop had no key click
; (ADDERIN stayed on the matrix).  Now the DSP gets a one-word program that
; only loops (Dsp_ExecBoot resets it, so the SSI stops), and mx_zurueck
; writes back the sound registers saved at Mischer_install.
Mischer_remove:
	tst.b	mk_bereit
	beq	.raus
	sf	mk_bereit
	movem.l	d0-d2/a0-a2,-(sp)
	tst.b	md_dsp
	beq.s	.dma
	sf	md_dsp
	clr.l	-(sp)			; Dsptristate(off, off)
	move.w	#xb_Dsptristate,-(sp)
	Mx_xbios
	addq.l	#6,sp
	move.w	#xb_Dsp_ReqAbil,-(sp)
	Mx_xbios
	addq.l	#2,sp
	move.w	d0,-(sp)		; Dsp_ExecBoot(md_halt, 1 word, ability)
	pea	1.w
	pea	md_halt
	move.w	#xb_Dsp_ExecBoot,-(sp)
	Mx_xbios
	lea	12(sp),sp
	move.w	#xb_Dsp_Unlock,-(sp)
	Mx_xbios
	addq.l	#2,sp
	bra.s	.frei
.dma:	clr.w	-(sp)			; Buffoper(0)
	move.w	#xb_Buffoper,-(sp)
	Mx_xbios
	addq.l	#4,sp
.frei:	bsr	mx_zurueck
	move.w	#xb_Unlocksnd,-(sp)
	Mx_xbios
	addq.l	#2,sp
	movem.l	(sp)+,d0-d2/a0-a2
.raus:	rts

; ---------------------------------------------------------------------------
; mx_sichern, mx_zurueck -- the sound registers of the Falcon that the mixer
; changes, saved before and written back after: track and mode control
; ($FF8920/21), matrix sources and destinations ($FF8930/32), clock
; dividers ($FF8934/35), record tracks ($FF8936), ADDERIN ($FF8937),
; ADCINPUT ($FF8938), gain ($FF8939) and attenuation ($FF893A).  XBIOS has
; no way to ask for the matrix, hence the registers.  The map is from the
; documentation, not measured.  Change only a0.
mx_sichern:
	lea	mx_register,a0
	move.w	$FFFF8920.w,(a0)+
	move.l	$FFFF8930.w,(a0)+
	move.l	$FFFF8934.w,(a0)+
	move.l	$FFFF8938.w,(a0)+
	rts

mx_zurueck:
	lea	mx_register,a0
	move.w	(a0)+,$FFFF8920.w
	move.l	(a0)+,$FFFF8930.w
	move.l	(a0)+,$FFFF8934.w
	move.l	(a0)+,$FFFF8938.w
	rts

; ---------------------------------------------------------------------------
; Mischer_vbl -- every VBL.  Fills the ring up to MUSIK_VORAUS pieces ahead
; of playback.  If playback has overtaken (the caller held the VBL too
; long), it starts again one piece behind it.
Mischer_vbl:
	tst.b	mk_bereit
	beq.s	.raus
	tst.b	md_dsp
	bne	md_vbl
	movem.l	d0-d7/a0-a6,-(sp)
.wieder:
	bsr	mk_spielstand		; d0 = playback offset
	move.l	mk_schreib,d1
	sub.l	d0,d1			; lead
	bpl.s	.pos
	add.l	#MUSIK_RING_B,d1
.pos:	cmp.l	#(MUSIK_VORAUS+2)*MUSIK_STUECK_B,d1
	bls.s	.im_takt
	divu	#MUSIK_STUECK_B,d0	; overtaken: start again behind playback
	addq.w	#1,d0
	mulu	#MUSIK_STUECK_B,d0
	cmp.l	#MUSIK_RING_B,d0
	blo.s	.neu
	moveq	#0,d0
.neu:	move.l	d0,mk_schreib
	bra.s	.wieder
.im_takt:
	cmp.l	#MUSIK_VORAUS*MUSIK_STUECK_B,d1
	bhs.s	.fertig
	bsr	mk_stueck
	bra.s	.wieder
.fertig:
	movem.l	(sp)+,d0-d7/a0-a6
.raus:	rts

; mk_spielstand -- d0 = where playback is in the ring (bytes).  Reads the
; DMA counter twice until it holds still.
mk_spielstand:
	move.l	d1,-(sp)
.lesen:	bsr.s	.zaehler
	move.l	d0,d1
	bsr.s	.zaehler
	cmp.l	d0,d1
	bne.s	.lesen
	sub.l	#Musik_ring,d0
	bmi.s	.null
	cmp.l	#MUSIK_RING_B,d0
	blo.s	.gut
.null:	moveq	#0,d0
.gut:	move.l	(sp)+,d1
	rts
.zaehler:
	moveq	#0,d0
	move.b	$FFFF8909.w,d0
	lsl.l	#8,d0
	move.b	$FFFF890B.w,d0
	lsl.l	#8,d0
	move.b	$FFFF890D.w,d0
	rts

; mk_takt -- DMACON, the tick, DMACON.  Returns a6 = shadow.  Changes d0,
; a0 and what mk_dmacon changes.
mk_takt:
	move.l	mx_satz+MS_SCHATTEN,a6
	bsr	mk_dmacon		; what was written in between (Set_music)
	move.l	mx_satz+MS_MERKER,d0
	beq.s	.takt
	move.l	d0,a0
	tst.b	(a0)
	beq.s	.ohne
.takt:	move.l	mx_satz+MS_TAKT,a0
	jsr	(a0)
	move.l	mx_satz+MS_SCHATTEN,a6
.ohne:	bra	mk_dmacon

; mk_stueck -- one piece: tick, then four channels into the ring.
mk_stueck:
	bsr	mk_takt
	lea	Musik_ring,a2
	add.l	mk_schreib,a2
	lea	$A0(a6),a3		; channel 0: set left
	lea	Musik_kanaele,a4
	move.l	a2,a5
	moveq	#0,d7
	bsr	mk_kanal
	lea	$B0(a6),a3		; channel 1: set right
	lea	mk_groesse(a4),a4
	lea	2(a2),a5
	bsr	mk_kanal
	lea	$C0(a6),a3		; channel 2: add right
	lea	mk_groesse(a4),a4
	lea	2(a2),a5
	moveq	#1,d7
	bsr	mk_kanal
	lea	$D0(a6),a3		; channel 3: add left
	lea	mk_groesse(a4),a4
	move.l	a2,a5
	bsr	mk_kanal
	move.l	mk_schreib,d0
	add.l	#MUSIK_STUECK_B,d0
	cmp.l	#MUSIK_RING_B,d0
	blo.s	.ring
	moveq	#0,d0
.ring:	move.l	d0,mk_schreib
	rts

; mk_dmacon -- evaluate DMACON from the shadow (a6) and clear it.
mk_dmacon:
	move.w	$96(a6),d6
	beq.s	.raus
	clr.w	$96(a6)
	lea	$A0(a6),a3
	lea	Musik_kanaele,a4
	moveq	#0,d5			; channel bit
.kanal:	btst	d5,d6
	beq.s	.naechster
	tst.w	d6
	bmi.s	.start
	sf	mk_an(a4)		; off
	bra.s	.naechster
.start:	bsr	mk_laden		; on: restart from LC/LEN
	clr.l	mk_pos(a4)
	clr.w	mk_bruch(a4)
	st	mk_an(a4)
.naechster:
	lea	16(a3),a3
	lea	mk_groesse(a4),a4
	addq.w	#1,d5
	cmp.w	#4,d5
	blo.s	.kanal
.raus:	rts

; mk_laden -- LC/LEN of the shadow channel a3 into the channel a4.
mk_laden:
	move.l	a0,-(sp)
	move.l	d2,-(sp)
	bsr.s	mk_holen
	move.l	a0,mk_zeiger(a4)
	move.l	d2,mk_laenge(a4)
	move.l	(sp)+,d2
	move.l	(sp)+,a0
	rts

; mk_holen -- a0 = AUDxLC, d2 = AUDxLEN in bytes (0 = 65536 words), from
; the shadow channel a3.  If the block does not lie wholly in memory
; (ST-RAM up to phystop, TT-RAM up to ramtop): the silence.  Changes d0.
mk_holen:
	move.l	(a3),d0
	and.w	#$FFFE,d0
	move.l	d0,a0
	moveq	#0,d2
	move.w	4(a3),d2
	bne.s	.len
	move.l	#$10000,d2
.len:	add.l	d2,d2
	add.l	d2,d0			; end
	bcs.s	.stille
	cmp.l	($42E).w,d0		; phystop
	bls.s	.gut
	cmp.l	#$1357BD13,($5A8).w	; ramvalid: TT-RAM there?
	bne.s	.stille
	cmp.l	#$01000000,a0
	blo.s	.stille
	cmp.l	($5A4).w,d0		; ramtop
	bls.s	.gut
.stille:
	lea	mk_stille,a0
	moveq	#2,d2
.gut:	rts

; mk_kanal -- MUSIK_STUECK samples of channel a4 (shadow a3) to a5, step 4
; bytes.  d7 = 0 set, 1 add.
mk_kanal:
	tst.b	mk_an(a4)
	bne.s	.an
	tst.w	d7
	bne.s	.raus
	move.w	#MUSIK_STUECK-1,d1	; off and first: set silence
.null:	clr.w	(a5)
	addq.l	#4,a5
	dbf	d1,.null
.raus:	rts
.an:	move.w	6(a3),d0		; AUDxPER
	cmp.w	#PAULA_PER_MIN,d0
	bhs.s	.per
	move.w	#PAULA_PER_MIN,d0
.per:	moveq	#0,d3			; step = K / period, 16.16
	move.w	#PAULA_K_HI,d3
	divu	d0,d3			; remainder:integer part
	move.l	d3,d4
	move.w	#PAULA_K_LO,d4
	divu	d0,d4			; d4.w = fraction
	and.l	#$FFFF,d3		; d3 = integer part
	moveq	#0,d0
	move.w	8(a3),d0		; AUDxVOL, 7 bits, above 64 = 64
	and.w	#$7F,d0
	cmp.w	#64,d0
	bls.s	.vol
	moveq	#64,d0
.vol:	lsl.l	#8,d0
	add.l	d0,d0			; * 512
	lea	Musik_lautst,a1
	add.l	d0,a1
	move.l	mk_zeiger(a4),a0
	move.l	mk_laenge(a4),d2
	move.l	mk_pos(a4),d6
	move.w	mk_bruch(a4),d5
	move.w	#MUSIK_STUECK-1,d1
	tst.w	d7
	bne.s	.dazu
.setzen:
	move.b	0(a0,d6.l),d0
	and.w	#$FF,d0
	add.w	d0,d0
	move.w	0(a1,d0.w),(a5)
	addq.l	#4,a5
	add.w	d4,d5
	addx.l	d3,d6
	cmp.l	d2,d6
	bhs.s	.neu_s
.weiter_s:
	dbf	d1,.setzen
	bra.s	.ende
.neu_s:	bsr.s	.nachladen
	bra.s	.weiter_s
.dazu:
	move.b	0(a0,d6.l),d0
	and.w	#$FF,d0
	add.w	d0,d0
	move.w	0(a1,d0.w),d0
	add.w	d0,(a5)
	addq.l	#4,a5
	add.w	d4,d5
	addx.l	d3,d6
	cmp.l	d2,d6
	bhs.s	.neu_d
.weiter_d:
	dbf	d1,.dazu
	bra.s	.ende
.neu_d:	bsr.s	.nachladen
	bra.s	.weiter_d
.ende:	move.l	a0,mk_zeiger(a4)
	move.l	d2,mk_laenge(a4)
	move.l	d6,mk_pos(a4)
	move.w	d5,mk_bruch(a4)
	rts
; block done: like the Paula, LC/LEN again from the shadow.
.nachladen:
	sub.l	d2,d6
	bsr	mk_holen
	cmp.l	d2,d6
	bhs.s	.nachladen
	rts

; ***************************************************************************
; The mixer on the DSP (step 4c).  Counterpart: MUSIK_DSP.A56, which
; describes the protocol.
;
; Per piece the processor does what the Paula does not take off it: the
; tick, DMACON, and it follows each channel through blocks and loops
; (mk_holen, as in 4b).  To the DSP it sends per channel step, position,
; volume and either where the channel reads in the DSP (way 1, 4e) or
; exactly the sample bytes it reads in this piece, three per host word
; (way 2).  Pitch, volume and sum are the DSP's, and it plays through the
; matrix straight to the DAC.
;
; **Tick:** the DSP sets HF2 when it needs a piece and says after each one
; whether another should follow.  So the sound sets the tick here, too.
;
; **No hanging:** every wait on the host port has a limit.  When it is
; reached, the DSP counts as dead (md_tot), and the music falls silent.
; ***************************************************************************

HOST_ISR	equ	$FFFFA202	; bit 0 RXDF, 1 TXDE, 3 HF2
HOST_DATEN	equ	$FFFFA204	; long: unused, high, middle, low
MD_HOECHSTENS	equ	4		; pieces per VBL

; ---------------------------------------------------------------------------
; md_install -- lock the DSP, load the mixer, DSP transmit to the DAC.
; Sets md_dsp if it worked.  From Mischer_install (registers saved there),
; sound already locked and reset.
md_install:
	move.w	#xb_Dsp_Lock,-(sp)
	Mx_xbios
	addq.l	#2,sp
	tst.w	d0
	bne	.raus			; taken: the processor mixes
	move.w	#xb_Dsp_ReqAbil,-(sp)
	Mx_xbios
	addq.l	#2,sp
	move.w	d0,-(sp)		; Dsp_ExecBoot(image, words, ability)
	move.l	#(md_code_ende-md_code)/3,-(sp)
	pea	md_code
	move.w	#xb_Dsp_ExecBoot,-(sp)
	Mx_xbios
	lea	12(sp),sp
	move.w	#1,-(sp)		; Dsptristate(on, on): DSP to the matrix
	move.w	#1,-(sp)
	move.w	#xb_Dsptristate,-(sp)
	Mx_xbios
	addq.l	#6,sp
	move.w	#1,-(sp)		; no handshake
	move.w	#MUSIK_VORTEILER,-(sp)
	clr.w	-(sp)			; 25.175 MHz
	move.w	#8,-(sp)		; to the DAC
	move.w	#1,-(sp)		; from DSP transmit
	move.w	#xb_Devconnect,-(sp)
	Mx_xbios
	lea	12(sp),sp
	sf	md_tot
	st	md_dsp
.raus:	rts

; ---------------------------------------------------------------------------
; md_vbl -- from Mischer_vbl.  Sends pieces as long as the DSP wants them,
; at most MD_HOECHSTENS.  All registers stay.
md_vbl:
	tst.b	md_tot
	bne.s	.raus
	btst	#3,HOST_ISR.w		; HF2: the DSP wants a piece
	beq.s	.raus
	movem.l	d0-d7/a0-a6,-(sp)
	btst	#0,HOST_ISR.w		; a word still waiting: drop it
	beq.s	.leer
	move.l	HOST_DATEN.w,d0
.leer:	bsr	md_proben		; new song: samples into the DSP
	tst.b	md_tot
	bne.s	.fertig
	moveq	#MD_HOECHSTENS-1,d7
.stueck:
	bsr	md_stueck
	tst.b	md_tot
	bne.s	.fertig
	moveq	#-1,d1			; wait for the answer
.antw:	btst	#0,HOST_ISR.w
	dbne	d1,.antw
	beq.s	.tot
	move.l	HOST_DATEN.w,d0
	tst.b	md_tot
	bne.s	.fertig
	and.l	#$00FFFFFF,d0		; 1 = another one right away
	beq.s	.fertig
	dbf	d7,.stueck
.fertig:
	movem.l	(sp)+,d0-d7/a0-a6
.raus:	rts
.tot:	st	md_tot
	bra.s	.fertig

; ---------------------------------------------------------------------------
; Samples in the DSP (2026-10-08, docs/13 4e).  After each song change
; md_proben loads the song's sample area into the DSP once.  Per piece
; md_stueck then only tells the DSP per channel where it reads there (way
; 1); what is not in the DSP goes the old way (way 2: the bytes
; themselves).  The Paula reads from exactly three kinds of memory: the
; song's sample area (Thalion's player only reads it), the four synth
; buffers at the start of Thalion's channel records (the player rewrites
; them every tick; they go over when they have changed) and the silence.
; Needs the 4e fields of the parameter block; without them, way 2 only.
MD_STILLE_B	equ	$200*3		; byte addresses in the DSP's X memory
MD_SYN_B	equ	$202*3		; (MUSIK_DSP.A56: STILLE, SYN, PROBEN)
MD_SYN_SATZ_B	equ	46*3		; SYN_K
MD_SYN_W	equ	43		; words per synth buffer (129 bytes)
MD_PROBEN_B	equ	$300*3
MD_PROBEN_MAX	equ	($4000-$300)*3	; 47 872 bytes
MD_STILLE_LEN	equ	6
MD_LADEN	equ	$10		; first word: samples follow
MD_SATZ		equ	$CE		; channel record, four of them (MS_SAETZE)
MD_SYN_LEN	equ	128		; synth buffer at the start of a record
MD_KOPF_LIED	equ	$28		; first offset in the song (all 32)
MD_HOECHSTE_PROBEN equ	64		; no song has more samples
; plan per channel, longs (md_planen -> md_kanal)
mp_schritt	equ	0
mp_bruch	equ	4
mp_stelle	equ	8
mp_vol		equ	12
mp_art		equ	16		; 0 off, 1 in the DSP, 2 bytes themselves
mp_anzahl	equ	20		; bytes read in this piece
mp_adresse	equ	24		; way 1: byte address in the DSP
mp_rest		equ	28		;        rest of the block
mp_nadresse	equ	32		;        next block (the loop)
mp_nlaenge	equ	36
mp_vor		equ	40		; whole bytes forward
mp_groesse	equ	44

; md_proben -- if a new song is there (MS_STUECK, MS_LIED), its samples into
; the DSP.  The song: 8 offsets in front, the last one points to N, N
; lengths, then the samples one after another (Thalion's +0, 0:$2AABE).
; If it does not fit, md_s_anfang stays 0 and all channels go the old way.
; Changes d0-d2, d4, a0, a1.
md_proben:
	move.l	mx_satz+MS_STUECK,d0
	beq	.raus			; without 4e
	move.l	d0,a0
	move.w	(a0),d0			; number of the playing song
	beq	.raus
	move.l	mx_satz+MS_LIED,a0
	cmp.w	#0,a0
	beq	.raus
	move.l	(a0),a0			; pointer to the first area
	cmp.l	md_s_lied,a0
	bne.s	.neu
	cmp.w	md_s_nr,d0
	beq	.raus
.neu:	move.l	a0,md_s_lied
	move.w	d0,md_s_nr
	clr.l	md_s_anfang
	clr.l	md_s_ende
	lea	-MD_KOPF_LIED(a0),a1	; start of the song
	cmp.l	#MD_KOPF_LIED,(a1)
	bne.s	.raus
	move.l	28(a1),d0		; last offset: the samples
	lea	0(a1,d0.l),a1
	move.l	(a1)+,d1		; N
	beq.s	.raus
	cmp.l	#MD_HOECHSTE_PROBEN,d1
	bhi.s	.raus
	moveq	#0,d2
	subq.w	#1,d1
.len:	add.l	(a1)+,d2
	dbf	d1,.len
	tst.l	d2			; a1 = first sample, d2 = bytes
	beq.s	.raus
	cmp.l	#MD_PROBEN_MAX,d2
	bhi.s	.raus
	moveq	#MD_LADEN,d0
	bsr	md_senden
	move.l	d2,d0
	addq.l	#2,d0
	divu	#3,d0
	and.l	#$FFFF,d0		; W
	bsr	md_senden
	move.l	d0,d1
	move.l	a1,-(sp)
	bsr	md_bytes
	move.l	(sp)+,a1
	tst.b	md_tot
	bne.s	.raus
	move.l	a1,md_s_anfang
	add.l	d2,a1
	move.l	a1,md_s_ende
.raus:	rts

; md_stueck -- one piece: tick, plan the channels, first word with the
; synth buffers, four channels.  Leaves d7.
md_stueck:
	bsr	mk_takt			; a6 = shadow
	sf	md_maske
	lea	$A0(a6),a3
	lea	Musik_kanaele,a4
	lea	md_plan,a2
	bsr	md_planen
	lea	16(a3),a3
	lea	mk_groesse(a4),a4
	lea	mp_groesse(a2),a2
	bsr	md_planen
	lea	16(a3),a3
	lea	mk_groesse(a4),a4
	lea	mp_groesse(a2),a2
	bsr	md_planen
	lea	16(a3),a3
	lea	mk_groesse(a4),a4
	lea	mp_groesse(a2),a2
	bsr	md_planen
	bsr	md_synth
	lea	$A0(a6),a3
	lea	Musik_kanaele,a4
	lea	md_plan,a2
	bsr	md_kanal
	lea	16(a3),a3
	lea	mk_groesse(a4),a4
	lea	mp_groesse(a2),a2
	bsr	md_kanal
	lea	16(a3),a3
	lea	mk_groesse(a4),a4
	lea	mp_groesse(a2),a2
	bsr	md_kanal
	lea	16(a3),a3
	lea	mk_groesse(a4),a4
	lea	mp_groesse(a2),a2
	bra	md_kanal

; md_planen -- channel a4 (shadow a3): header values to a2, and where it
; reads.  Already moves the fraction of the position on.  Leaves a2-a6, d7.
md_planen:
	moveq	#0,d0
	move.l	d0,mp_art(a2)
	tst.b	mk_an(a4)
	bne.s	.an
	move.l	d0,mp_schritt(a2)	; off: all 0
	move.l	d0,mp_bruch(a2)
	move.l	d0,mp_stelle(a2)
	move.l	d0,mp_vol(a2)
	rts
.an:	move.w	6(a3),d0		; AUDxPER
	cmp.w	#PAULA_PER_MIN,d0
	bhs.s	.per
	move.w	#PAULA_PER_MIN,d0
.per:	moveq	#0,d3			; step = K / period, 16.16
	move.w	#PAULA_K_HI,d3
	divu	d0,d3			; remainder:integer part
	move.l	d3,d4
	move.w	#PAULA_K_LO,d4
	divu	d0,d4			; d4.w = fraction
	and.l	#$FFFF,d3		; d3 = integer part
	and.l	#$FFFF,d4
	move.l	d3,mp_schritt(a2)
	move.l	d4,d0
	lsl.l	#8,d0
	move.l	d0,mp_bruch(a2)
	moveq	#0,d0
	move.w	mk_bruch(a4),d0
	lsl.l	#8,d0
	move.l	d0,mp_stelle(a2)
	moveq	#0,d0			; AUDxVOL, 7 bits, above 64 = 64
	move.w	8(a3),d0
	and.w	#$7F,d0
	cmp.w	#64,d0
	bls.s	.vol
	moveq	#64,d0
.vol:	swap	d0			; * 2^15: 64 = 1/4
	lsr.l	#1,d0
	move.l	d0,mp_vol(a2)
	; end = position + 246 * step, 16.16.  The bytes read are position ..
	; position + forward, so forward + 1 of them.
	move.w	d4,d1
	mulu	#MUSIK_STUECK,d1
	move.w	d3,d0
	mulu	#MUSIK_STUECK,d0
	swap	d0
	clr.w	d0
	add.l	d0,d1
	moveq	#0,d0
	move.w	mk_bruch(a4),d0
	add.l	d0,d1
	move.w	d1,mk_bruch(a4)		; new fraction
	clr.w	d1
	swap	d1			; d1 = forward (whole bytes)
	move.l	d1,mp_vor(a2)
	addq.l	#1,d1
	move.l	d1,mp_anzahl(a2)
	move.l	mk_zeiger(a4),a0	; is the block in the DSP?
	move.l	mk_laenge(a4),d2
	bsr	md_ort
	bmi.s	.roh
	add.l	mk_pos(a4),d0
	move.l	d0,mp_adresse(a2)
	move.l	d2,d0
	sub.l	mk_pos(a4),d0
	move.l	d0,mp_rest(a2)
	bsr	mk_holen		; and the next one (LC/LEN in the shadow)?
	bsr	md_ort
	bmi.s	.roh
	move.l	d0,mp_nadresse(a2)
	move.l	d2,mp_nlaenge(a2)
	moveq	#1,d0
	move.l	d0,mp_art(a2)
	rts
.roh:	moveq	#2,d0
	move.l	d0,mp_art(a2)
	rts

; md_ort -- d0 = byte address in the DSP for the block a0, d2 bytes, or -1
; (N set) if it is not there.  A synth buffer goes into md_maske.  Changes
; only d0.
md_ort:
	movem.l	d1/a1,-(sp)
	move.l	md_s_anfang,d1		; in the sample area?
	beq.s	.syn
	move.l	a0,d0
	cmp.l	d1,d0
	blo.s	.syn
	add.l	d2,d0
	cmp.l	md_s_ende,d0
	bhi.s	.syn
	move.l	a0,d0
	sub.l	d1,d0
	add.l	#MD_PROBEN_B,d0
	bra.s	.gut
.syn:	move.l	mx_satz+MS_SAETZE,d0	; in a synth buffer?
	beq.s	.leise
	move.l	d0,a1
	moveq	#0,d1
.satz:	move.l	a0,d0
	sub.l	a1,d0
	bcs.s	.weiter
	add.l	d2,d0
	cmp.l	#MD_SYN_LEN,d0
	bhi.s	.weiter
	bset	d1,md_maske
	move.l	a0,d0
	sub.l	a1,d0
	mulu	#MD_SYN_SATZ_B,d1
	add.l	d1,d0
	add.l	#MD_SYN_B,d0
	bra.s	.gut
.weiter:
	lea	MD_SATZ(a1),a1
	addq.w	#1,d1
	cmp.w	#4,d1
	blo.s	.satz
.leise:	cmp.w	#MD_STILLE_LEN,d2	; silence: ours or the player's
	bhi.s	.nein
	cmp.l	#mk_stille,a0
	beq.s	.still
	move.l	mx_satz+MS_STILLE,d0
	beq.s	.nein
	move.l	d0,a1
	move.l	a0,d0
	sub.l	a1,d0
	bcs.s	.nein
	add.l	d2,d0
	cmp.l	#MD_STILLE_LEN,d0
	bhi.s	.nein
.still:	move.l	#MD_STILLE_B,d0
.gut:	movem.l	(sp)+,d1/a1
	tst.l	d0
	rts
.nein:	movem.l	(sp)+,d1/a1
	moveq	#-1,d0
	rts

; md_synth -- first word, and the synth buffers from md_maske that have
; changed since they were last sent.  Changes d0-d2, d4-d6, a0, a1.
md_synth:
	moveq	#0,d5			; these go over
	moveq	#0,d0
	move.b	md_maske,d0
	beq.s	.senden
	move.l	mx_satz+MS_SAETZE,a0
	lea	md_syn_kopie,a1
	moveq	#0,d1
.satz:	btst	d1,d0
	beq.s	.weiter
	movem.l	a0-a1,-(sp)
	btst	d1,md_syn_gueltig
	beq.s	.neu
	moveq	#MD_SYN_LEN/4-1,d2
.vgl:	cmpm.l	(a0)+,(a1)+
	dbne	d2,.vgl
	beq.s	.gleich
	movem.l	(sp),a0-a1
.neu:	moveq	#MD_SYN_LEN/4-1,d2
.kopie:	move.l	(a0)+,(a1)+
	dbf	d2,.kopie
	bset	d1,d5
	bset	d1,md_syn_gueltig
.gleich:
	movem.l	(sp)+,a0-a1
.weiter:
	lea	MD_SATZ(a0),a0
	lea	MD_SYN_LEN(a1),a1
	addq.w	#1,d1
	cmp.w	#4,d1
	blo.s	.satz
.senden:
	move.l	d5,d0			; first word: which follow
	bsr	md_senden
	move.l	mx_satz+MS_SAETZE,a1
	moveq	#0,d6
.schick:
	btst	d6,d5
	beq.s	.naechster
	move.l	a1,-(sp)
	moveq	#MD_SYN_W,d1
	bsr	md_bytes
	move.l	(sp)+,a1
.naechster:
	lea	MD_SATZ(a1),a1
	addq.w	#1,d6
	cmp.w	#4,d6
	blo.s	.schick
	rts

; md_kanal -- the plan a2 of channel a4 (shadow a3) to the DSP, then move
; the channel on like the Paula.  Leaves a2, a3, a4, a6, d7.
md_kanal:
	move.l	mp_schritt(a2),d0
	bsr	md_senden
	move.l	mp_bruch(a2),d0
	bsr	md_senden
	move.l	mp_stelle(a2),d0
	bsr	md_senden
	move.l	mp_vol(a2),d0
	bsr	md_senden
	move.l	mp_art(a2),d0
	bsr	md_senden
	tst.l	d0
	beq	.raus			; off: nothing more
	cmp.l	#1,d0
	bne.s	.roh
	move.l	mp_anzahl(a2),d0	; way 1: the DSP reads itself
	bsr	md_senden
	move.l	mp_adresse(a2),d0
	bsr	md_senden
	move.l	mp_rest(a2),d0
	bsr	md_senden
	move.l	mp_nadresse(a2),d0
	bsr	md_senden
	move.l	mp_nlaenge(a2),d0
	bsr	md_senden
	bra	.stellen
.roh:	move.l	mp_anzahl(a2),d5	; way 2: the bytes themselves (4c)
	move.l	d5,d3
	addq.l	#2,d3
	divu	#3,d3
	and.l	#$FFFF,d3		; d3 = W, words of 3 bytes
	move.l	d3,d0
	bsr	md_senden
	move.l	mk_zeiger(a4),a0
	move.l	mk_laenge(a4),d2
	move.l	mk_pos(a4),d6
	move.l	d3,d0			; are all 3*W bytes in the block?
	add.l	d3,d0
	add.l	d3,d0
	add.l	d6,d0
	cmp.l	d2,d0
	bhi.s	.sammeln
	lea	0(a0,d6.l),a1		; yes: straight from the block
	bra.s	.schicken
.sammeln:				; no: through the blocks into md_temp
	lea	md_temp,a1
.block:	move.l	d2,d0
	sub.l	d6,d0			; what the block still has
	cmp.l	d5,d0
	bls.s	.teil
	move.l	d5,d0
.teil:	sub.l	d0,d5
	lea	0(a0,d6.l),a5
	subq.w	#1,d0
.kopie:	move.b	(a5)+,(a1)+
	dbf	d0,.kopie
	tst.l	d5
	beq.s	.gesammelt
	moveq	#0,d6			; block done: LC/LEN again
	bsr	mk_holen
	bra.s	.block
.gesammelt:
	lea	md_temp,a1
.schicken:
	move.l	d3,d1
	bsr	md_bytes
.stellen:				; move on, like the Paula (4b)
	move.l	mk_zeiger(a4),a0
	move.l	mk_laenge(a4),d2
	move.l	mk_pos(a4),d6
	add.l	mp_vor(a2),d6
.weiter:
	cmp.l	d2,d6
	blo.s	.fertig
	sub.l	d2,d6
	bsr	mk_holen
	bra.s	.weiter
.fertig:
	move.l	a0,mk_zeiger(a4)
	move.l	d2,mk_laenge(a4)
	move.l	d6,mk_pos(a4)
.raus:	rts

; md_senden -- d0 as one host word (the low 24 bits).  Waits until the port
; is free, at most about 65536 tries; then md_tot.  Changes nothing but
; md_tot.
md_senden:
	tst.b	md_tot
	bne.s	.raus
	move.w	d1,-(sp)
	moveq	#-1,d1
.warte:	btst	#1,HOST_ISR.w		; TXDE
	dbne	d1,.warte
	beq.s	.tot
	move.l	d0,HOST_DATEN.w
	move.w	(sp)+,d1
.raus:	rts
.tot:	st	md_tot
	move.w	(sp)+,d1
	rts

; md_bytes -- d1 words (>= 1) of 3 bytes each from a1 to the DSP, the first
; byte on top.  Changes d0, d1, d4, a1.
md_bytes:
	tst.b	md_tot
	bne.s	.raus
	subq.w	#1,d1
.wort:	move.b	(a1)+,d0
	lsl.l	#8,d0
	move.b	(a1)+,d0
	lsl.l	#8,d0
	move.b	(a1)+,d0
	moveq	#-1,d4
.warte:	btst	#1,HOST_ISR.w		; TXDE
	dbne	d4,.warte
	beq.s	.tot
	move.l	d0,HOST_DATEN.w
	dbf	d1,.wort
.raus:	rts
.tot:	st	md_tot
	rts

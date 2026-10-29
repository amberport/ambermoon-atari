; ===========================================================================
; INVENTOR_SUP.S -- Object_data, Thalions Item-Tabelle, zur Laufzeit geladen.
;
; Bis Stufe (c) (2026-09-27) stand hier auch die Bruecke zwischen unserem
; Party-Block und Thalions Handles (Fill_party_handles,
; Fill_portrait_handles, Inventar_oeffnen ...).  Das tut jetzt Thalions
; Init_program selbst (Load_batch_of_subfiles in Party_handles und
; Portrait_handles), und der Rechtsklick auf ein Portrait ist Thalions
; Member_right.  Die Bruecke ist geloescht.
; ===========================================================================

; ***************************************************************************
; Object_data -- Thalions Item-Tabelle.  Fester Puffer mit genau diesem Namen,
; damit sein "lea Object_data+4,a1" unveraendert laeuft; im Original steht
; sie in AM2_CPU.  Aufbau: 4 Byte Kopf (Anzahl, Satzlaenge), dann die Saetze
; zu Item_data_size; Weight liegt je Satz auf +38.
;
; Die Fassung 1.20 traegt die Saetze in Objects.amb, mit nur einem Wort
; Anzahl davor.  Load_objects liest sie zur Laufzeit (Leitziel 2) und setzt
; die Satzlaenge in den Kopf.  Bis 2026-09-25 baute der Konverter daraus
; OBJECTS.AMF.
; ***************************************************************************
OBJDATMAX	equ	4+512*Item_data_size	; grosszuegig (402 Gegenstaende)

	SECTION	Fast_BSS,bss
	even
Object_data:	ds.b	OBJDATMAX

	SECTION	Program,code

; Load_objects -- Objects.amb in den Object_data-Puffer.
; Zurueck: d0 = 0 wenn geladen, sonst -1.  Fehlt/kaputt -> die Engine laeuft
; weiter (nur Gewicht/Typpruefung ruhen), darum kein Startabbruch.
Load_objects:
	movem.l	d1-d7/a0-a6,-(sp)
	moveq	#Objects_file,d0
	bsr	Load_file		; JH-Huelle und LOB, ausgepackt
	tst.l	d0
	beq	lo_fail
	move.w	d0,d3			; d3 = Handle
	bsr	Get_memory_length
	move.l	d0,d2			; d2 = Laenge der Datei
	moveq	#0,d0
	move.w	d3,d0
	bsr	Block_adresse
	move.l	d0,a0
	moveq	#-1,d7			; Ergebnis, bis es geklappt hat
	cmp.l	#2+Item_data_size,d2	; wenigstens Anzahl und ein Satz?
	blo.b	lo_frei
	moveq	#0,d1
	move.w	(a0)+,d1		; d1 = Anzahl
	beq.b	lo_frei
	move.l	d1,d4
	mulu.w	#Item_data_size,d4	; d4 = Laenge der Saetze
	move.l	d4,d0
	addq.l	#2,d0
	cmp.l	d2,d0			; traegt die Datei sie alle?
	bhi.b	lo_frei
	move.l	d4,d0
	addq.l	#4,d0
	cmp.l	#OBJDATMAX,d0		; und der Puffer?
	bhi.b	lo_frei
	lea	Object_data,a1
	move.w	d1,(a1)+		; Kopf wie in AM2_CPU: Anzahl,
	move.w	#Item_data_size,(a1)+	;  Satzlaenge
	subq.l	#1,d4
lo_kop:	move.b	(a0)+,(a1)+
	dbf	d4,lo_kop		; hoechstens 30720 -- passt in dbf
	moveq	#0,d7
lo_frei:
	moveq	#0,d0
	move.w	d3,d0
	bsr	Free_memory
	move.l	d7,d0
	bra.b	lo_out
lo_fail:
	moveq	#-1,d0
lo_out:	movem.l	(sp)+,d1-d7/a0-a6
	rts


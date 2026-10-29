; ===========================================================================
; SPIELSTAND.S -- Speichern und Laden: Get_saved_game, Put_saved_game,
; Save_file, Save_encrypted_file.  Einheit "bibliothek" (engine.s).
;
; Alle vier stehen im Original in der nicht freigegebenen Bibliothek.  Die
; Vertraege sind in AM2_CPU 1.20 nachgelesen (tools/am2cpu_lesen.py,
; Erkenntnis 251), nicht an Thalions Aufrufstellen erraten:
;
;   Get_saved_game       0:$29948
;   Put_saved_game       0:$299A8
;   Save_file            0:$25C6E
;   Save_encrypted_file  0:$25D5C
;
; **Ordner wie im Original.**  Die fuenf Arbeitsdateien liegen im
; Hauptverzeichnis (bei uns PARTYDAT.SAV ..., FILES_SUP.S).  SAVE.00 ist die
; Vorlage "Neues Spiel", SAVE.01 bis SAVE.10 sind die Plaetze.  Thalions
; Save_game schreibt die Arbeitsdateien und ruft Put_saved_game; Load_game
; setzt Initial_save und springt nach Restart_game, dort holt Init_program
; den Stand mit Get_saved_game.
;
; Die Spielstaende sind JH-verschluesselt, die Arbeitsdateien nicht:
; Put_saved_game schreibt mit Save_encrypted_file, Get_saved_game liest mit
; Load_file (entschluesselt) und schreibt mit Save_file.
; ===========================================================================

	SECTION	Fast_DATA,data
	even
; Je Datei: Dateinummer (Thalions GAME_OFF.S), Pfad im Spielstandordner.
; Reihenfolge wie in AM2_CPU 1.20 (6:$110).  Die Nummer des Ordners steht
; an Versatz 5 und 6 und wird vor jedem Durchgang eingesetzt.
sp_tabelle:
	dc.w	Party_data_file
	dc.l	sp_pdata
	dc.w	Party_char_file
	dc.l	sp_pchar
	dc.w	Automap_file
	dc.l	sp_automap
	dc.w	Chest_data_file
	dc.l	sp_chest
	dc.w	Merchant_data_file
	dc.l	sp_merchant
SP_ANZAHL	equ	5
SP_ZIFFERN	equ	5		; "SAVE.nn": die zwei Ziffern

; Die Namen in den Ordnern sind dieselben 8.3-Namen wie im Hauptverzeichnis
; (FILES_SUP.S, dn_tabelle); tools/baue_alles.sh legt sie so an.
; **Doppelter Backslash**: der Bau uebersetzt mit -esc, und ein einfacher
; "\P" wurde zu einem anderen Zeichen ("SAVE.000PARTYDAT.SAV", Hatari-Test
; 2026-09-28).
sp_pdata:	dc.b	"SAVE.00\\PARTYDAT.SAV",0
sp_pchar:	dc.b	"SAVE.00\\PARTYCHR.AMB",0
sp_automap:	dc.b	"SAVE.00\\AUTOMAP.AMB",0
sp_chest:	dc.b	"SAVE.00\\CHESTDAT.AMB",0
sp_merchant:	dc.b	"SAVE.00\\MERCHANT.AMB",0
	even

	SECTION	Program,code

; ***************************************************************************
; Get_saved_game -- einen Spielstand zu Arbeitsdateien machen.
;
;   IN : d0.w = Platz (0 = Neues Spiel, 1-10)
;   Alle Register bleiben.
;
; Je Datei: SAVE.nn\X laden (Load_file mit Nummer 0, entschluesselt), als
; Arbeitsdatei schreiben (Save_file, unverschluesselt).  Eine Datei, die
; fehlt, wird uebergangen.  (Until 2026-10-21 the container cache was
; emptied afterwards; Load_subfile has none now.)
; ***************************************************************************
Get_saved_game:
	movem.l	d0-d3/d7/a0-a2,-(sp)
	cmp.w	#Max_saves,d0
	bhi.b	gsg_out			; auch negativ (unsigned): nichts
	bsr	Platz_einsetzen
	lea	sp_tabelle,a2
	moveq	#SP_ANZAHL-1,d7
gsg_l:	move.l	2(a2),a0		; Pfad im Spielstandordner
	moveq	#0,d0
	jsr	Load_file
	tst.l	d0
	beq.b	gsg_next
	move.w	d0,d2			; d2 = Handle
	jsr	Block_adresse
	move.l	d0,a0			; a0 = Daten
	moveq	#0,d0
	move.w	d2,d0
	jsr	Get_memory_length	; d0 = Laenge
	move.w	(a2),d1			; als Arbeitsdatei
	bsr	Save_file
	moveq	#0,d0
	move.w	d2,d0
	jsr	Free_memory
gsg_next:
	addq.l	#6,a2
	dbf	d7,gsg_l
gsg_out:
	movem.l	(sp)+,d0-d3/d7/a0-a2
	rts

; ***************************************************************************
; Put_saved_game -- die Arbeitsdateien als Spielstand ablegen.
;
;   IN : d0.w = Platz (1-10; 0 tut nichts, wie in 1.20)
;   Alle Register bleiben.
;
; Je Datei: die Arbeitsdatei laden, verschluesselt nach SAVE.nn\X schreiben.
; Thalions Save_game hat vorher alles hineingeschrieben, was sich geaendert
; hat (Save_subfile, Save_encrypted_file).
; ***************************************************************************
Put_saved_game:
	movem.l	d0-d3/d7/a0-a2,-(sp)
	tst.w	d0
	beq.b	psg_out
	cmp.w	#Max_saves,d0
	bhi.b	psg_out
	bsr	Platz_einsetzen
	lea	sp_tabelle,a2
	moveq	#SP_ANZAHL-1,d7
psg_l:	move.w	(a2),d0			; die Arbeitsdatei
	jsr	Load_file
	tst.l	d0
	beq.b	psg_next
	move.w	d0,d2
	jsr	Block_adresse
	move.l	d0,a0			; a0 = Daten
	moveq	#0,d0
	move.w	d2,d0
	jsr	Get_memory_length	; d0 = Laenge
	moveq	#0,d1			; Name in a1
	move.l	2(a2),a1
	bsr	Save_encrypted_file
	moveq	#0,d0
	move.w	d2,d0
	jsr	Free_memory
psg_next:
	addq.l	#6,a2
	dbf	d7,psg_l
psg_out:
	movem.l	(sp)+,d0-d3/d7/a0-a2
	rts

; ***************************************************************************
; Platz_einsetzen -- die Nummer des Spielstandordners in alle fuenf Pfade
; schreiben ("SAVE.nn").  Wie in 1.20 (0:$29A0E), dort mit DecR_convert.
;
;   IN : d0.w = Platz, 0-10.  Alle Register bleiben.
; ***************************************************************************
Platz_einsetzen:
	movem.l	d0-d2/d7/a0-a1,-(sp)
	and.l	#$FFFF,d0
	divu	#10,d0			; unten Zehner, oben Einer
	move.l	d0,d1
	swap	d1
	add.b	#'0',d0
	add.b	#'0',d1
	lea	sp_tabelle,a1
	moveq	#SP_ANZAHL-1,d7
pe_l:	move.l	2(a1),a0
	move.b	d0,SP_ZIFFERN(a0)
	move.b	d1,SP_ZIFFERN+1(a0)
	addq.l	#6,a1
	dbf	d7,pe_l
	movem.l	(sp)+,d0-d2/d7/a0-a1
	rts

; ***************************************************************************
; Save_file -- einen Speicherblock als ganze Datei schreiben.
;
;   IN : d0.l = Laenge
;        d1.w = Dateinummer; 0 heisst: Name in a1
;        a0   = Daten
;   Alle Register bleiben (1.20: movem d0-d3/a0-a1/a5).
;
; 1.20 fragt bei einem Schreibfehler mit einem Requester nach und versucht
; es erneut; wir kehren still zurueck.
; ***************************************************************************
Save_file:
	move.l	d0,-(sp)
	jsr	Datei_sichern
	move.l	(sp)+,d0
	rts

; ***************************************************************************
; Save_encrypted_file -- like Save_file, but wrapped in JH encryption.
;   IN : d0.l = length, d1.w = file number (0: name in a1), a0 = data
;   All registers are preserved.  The caller's data is never touched.
;
;
; 1.20 schreibt vier Byte Kopf, "JH" und Schluessel XOR "JH", verschluesselt
; die Daten an Ort und Stelle, schreibt sie und entschluesselt sie wieder.
; Die Verschluesselung ist JH_decrypt (XOR-Strom, symmetrisch).  Wir
; verschluesseln eine Kopie mit dem Kopf davor: dieselbe Datei, und die Daten
; des Aufrufers werden nie angefasst.  Reicht der Speicher nicht, wird
; unverschluesselt geschrieben -- Load_file liest beides.
;
; Der Schluessel ist beliebig, die Datei traegt ihn; 1.20 nimmt einen kleinen
; Zufallsgenerator (0:$267C2), wir den Bildzaehler.
;; ***************************************************************************
Save_encrypted_file:
	movem.l	d0-d4/a0-a3,-(sp)
	move.l	a0,a2			; a2 = Daten des Aufrufers
	move.l	a1,a3			; a3 = Name (bei Nummer 0)
	move.l	d0,d3			; d3 = Laenge
	move.w	d1,d4			; d4 = Dateinummer
	addq.l	#4,d0
	jsr	Speicher_anfordern
	tst.l	d0
	beq.b	sef_roh
	move.w	d0,d2			; d2 = Handle der Kopie
	jsr	Block_adresse
	move.l	d0,a1			; a1 = Kopie
	move.w	VBL_counter,d1
	add.w	#$1234,d1		; d1 = Schluessel
	move.w	#'JH',(a1)
	move.w	d1,2(a1)
	eor.w	#'JH',2(a1)		; Wort 1 = Schluessel XOR "JH"
	addq.l	#4,a1
	move.l	a2,a0
	move.l	d3,d0
	jsr	Copy_memory		; Daten hinter den Kopf
	move.l	a1,a0
	jsr	JH_decrypt		; a0, d0 = Laenge, d1 = Schluessel
	subq.l	#4,a0			; a0 = Kopie mit Kopf
	addq.l	#4,d0
	move.w	d4,d1
	move.l	a3,a1
	jsr	Datei_sichern
	moveq	#0,d0
	move.w	d2,d0
	jsr	Free_memory
	bra.b	sef_out
sef_roh:
	move.l	d3,d0			; kein Speicher: unverschluesselt
	move.w	d4,d1
	move.l	a2,a0
	move.l	a3,a1
	jsr	Datei_sichern
sef_out:
	movem.l	(sp)+,d0-d4/a0-a3
	rts

; ***************************************************************************
; HULL/FILES_SUP.S -- Laufzeit-Entpacker fuer Thalions Original-Datendateien.
;
; Leitziel 2: die Original-Amberfiles zur Laufzeit lesen, statt sie vorab zu
; konvertieren.  Load_subfile, Decompress und die JH-Entschluesselung stehen in
; KEINER freigegebenen Originaldatei (docs/09, Bibliotheksluecke) -- sie waren
; in der nicht veroeffentlichten Bibliotheks-Includedatei.  Also gehoeren sie
; per Leitziel 1 hierher, in unsere Schicht, mit Thalions Namen an der
; Schnittstelle.  Thalions Dateien (DISPLAY.S, EVENTS.S, ...) rufen sie
; unveraendert mit "jsr Load_subfile" / "jsr Decompress".
;
; The format (JH encryption, LOB packing, containers) is reconstructed and
; documented in tools/ambtool.py.  Since 2026-10-21 the two inner loops are
; Thalion's: JH_decrypt calls Crypt_block (HULL/VARIOUS.S), LOB_decompress
; calls Lob_core (AM2_CPU, am2cpu_code.py).  The chain around them
; (containers, Load_subfile, Decompress in place) is ours.
;
; Die Dateinamen-Tabelle (dn_tabelle) waechst mit ihren Aufrufern; was dort
; null ist, laedt noch nicht.  Viele Namen sprengen 8.3 und werden in
; tools/baue_alles.sh umbenannt.
; ***************************************************************************

	SECTION	Program,code

; ***************************************************************************
; JH_decrypt -- Jurie Horneman's 16-bit XOR stream.
;
; The work is Thalion's Crypt_block (HULL/VARIOUS.S): word by word,
; plain = word XOR k, then k = k*17 + 87.  Crypt_block makes an odd length
; even and so also touches the byte behind the block; we give it the whole
; words only and XOR the odd last byte with the high byte of the next key,
; which is what Crypt_block leaves there (finding 274).
;
;   IN : a0 = data (decrypted in place)
;        d0 = length in bytes (.l)
;        d1 = start key (.w)
;   All registers are preserved.
; ***************************************************************************
JH_decrypt:
	movem.l	d0/d7/a0,-(sp)
	move.l	d0,d7
	and.w	#$FFFE,d7		; whole words only
	move.w	d1,d0
	jsr	Crypt_block		; Thalion's; d0 = key of the next word
	move.l	(sp),d7
	btst	#0,d7
	beq.b	jh_out
	add.l	d7,a0
	lsr.w	#8,d0
	eor.b	d0,-1(a0)		; odd last byte
jh_out:
	movem.l	(sp)+,d0/d7/a0
	rts

; ***************************************************************************
; LOB_decompress -- unpack a LOB body.
;
; The work is Lob_core, the loop of Thalion's Decompress, taken from AM2_CPU
; at build time (am2cpu_code.i).  Bit-flagged LZ: a header byte gives eight
; flags, MSB first; 1 = a literal byte, 0 = a back reference of two bytes
; b0,b1 (length (b0 & $0F) + 3, offset ((b0 << 4) & $FF00) | b1).
; Lob_core checks the end only after each literal and each back reference;
; every LOB stream in the game data ends exactly there (finding 274).
;
;   IN : a0 = packed body (behind the LOB header)
;        a1 = destination
;        d0 = unpacked size (.l)
;   All registers are preserved.
; ***************************************************************************
LOB_decompress:
	tst.l	d0
	beq.b	lob_leer		; Lob_core would read one token
	movem.l	d0-d3/a0-a2,-(sp)
	add.l	a1,d0			; d0 = end of the destination
	jsr	Lob_core		; Thalion's, from AM2_CPU
	movem.l	(sp)+,d0-d3/a0-a2
lob_leer:
	rts

; ***************************************************************************
; Load_subfile -- Thalions Symbol.  Einen Eintrag aus einem Container holen.
;
; **Die Schnittstelle ist abgelesen, nicht erfunden.**  So rufen es die
; Originaldateien (EVENTS.S, DISPLAY.S, ACTIONS.S, MAIN.S, CHARACTE.S ...):
;
;     moveq.l #0,d0
;     move.b  Event_b4(a5),d0        ; welcher Eintrag
;     addq.w  #1,d0                  ; Eintraege zaehlen ab eins
;     moveq.l #Chest_data_file,d1    ; welche Datei
;     jsr     Load_subfile
;     move.b  d0,Chest_data_handle   ; Rueckgabe ist ein Byte-Handle
;
;   IN : d0 = Nummer des Eintrags (.w, ab eins)
;        d1 = Dateinummer (die rs.b-Aufzaehlung aus GAME_OFF.S)
;   OUT: d0 = Speicher-Handle (.b), null wenn es nicht geklappt hat
;
; Aufbau eines Containers (belegt in tools/ambtool.py):
;     0..3   Kennung "AMNC" / "AMNP" / "AMPC" / "AMBR"
;     4..5   Anzahl der Eintraege
;     6..    je Eintrag ein Langwort mit seiner Laenge
;     dann   die Bloecke hintereinander
;
; Only the entry is read, not the whole container (Eintrag_lesen, since
; 2026-10-21, as in AM2_CPU).
;
; Die Containerebene wird hier ganz aufgeloest, einschliesslich der
; Packschicht der AMNP/AMPC-Eintraege (Packkopf_aufloesen).  Bis 2026-09-26
; stand hier "die LOB-Ebene nicht" -- abgelesen am einzigen Aufrufer, der
; damals lief, Show_layout.  Dessen LOB liegt aber *unter* der AMNC-
; Verschluesselung und bleibt ihm auch weiter; die uebrigen Aufrufer lesen
; ohne Decompress los (Erkenntnis 183).
;
;     AMNC   der ganze Block ist JH-verschluesselt, Schluessel = Eintragsnummer
;     AMNP   Packkopf klar (acht Byte gepackt, vier ungepackt), der Rest
;            verschluesselt, Schluessel = Eintragsnummer; dann ausgepackt
;     AMPC   unverschluesselt, Packkopf wie AMNP; ausgepackt
;     AMBR   roh
;
; Ereignisbilder kommen unveraendert heraus.  Bis 2026-09-28 weitete
; Ereignisbild_aufweiten sie hier auf acht Ebenen, weil Screen_depth 8 war
; und ShowPicTxt_ModInit mit "moveq.l #Screen_depth,d5" zeichnet; seit
; Screen_depth wieder 5 ist, weitet Put_unmasked_block auf (Erkenntnis 191).
; Alle Register bis auf d0 bleiben.
; ***************************************************************************
Load_subfile:
	movem.l	d1-d7/a0-a3,-(sp)
	move.w	d0,d7			; Nummer des Eintrags merken
	beq	lsf_fehler		; null gibt es nicht
	bsr	Teildatei_waehlen	; Karten liegen in drei Behaeltern
	IFD	LADEFEHLERTEST
	; Diagnoseschalter LADEFEHLERTEST: der erste Load_subfile im Spiel
	; verlangt einen Teil hinter dem letzten -> Ladefehlerschirm.
	tst.b	Notweg
	beq.b	.kein_test
	tst.b	lft_fertig
	bne.b	.kein_test
	st	lft_fertig
	st	lft_jetzt		; Eintrag_suchen nimmt dann einen zu viel
.kein_test:
	ENDC
	bsr	Eintrag_lesen		; d0 = Handle, d5 = Laenge, d2 = Kennung
	tst.l	d0
	bne.b	lsf_da
	cmp.w	d3,d7			; gab es so viele Eintraege?
	bls	lsf_fehler		; ja: leer, oder ein Dateifehler (d3 = $FFFF)
	tst.b	Notweg			; nein: im Spiel der Ladefehlerschirm
	beq	lsf_fehler		;  (0:$2510A, Erkenntnis 268)
	move.w	d7,d0
	move.l	(sp),d1			; Thalions Dateiart (Teildatei_waehlen bog d1 um)
	jmp	Ladefehler_schirm	; d0 = Teil, d1 = Dateiart; kehrt nicht zurueck
lsf_da:
	move.w	d0,d6			; d6 = Speicher-Handle

	; ---- Containerebene aufloesen: JH je nach Kennung ----
	bsr	Claim_pointer_d6	; a0 = unser Block (d6 -> Zeiger)
	move.l	a0,a1
	cmp.l	#'AMNC',d2
	beq.b	lsf_amnc
	cmp.l	#'AMNP',d2
	beq.b	lsf_amnp
	cmp.l	#'AMPC',d2
	beq.b	lsf_packkopf		; unverschluesselt, aber mit Packkopf
	bra.b	lsf_fertig		; AMBR: roh

lsf_amnc:
	move.l	a1,a0			; ganzer Block
	move.l	d5,d0
	move.w	d7,d1			; Schluessel = Eintragsnummer
	bsr	JH_decrypt
	bra.b	lsf_fertig

	; AMNP: der Packkopf bleibt klar, verschluesselt ist alles dahinter.
	; Gepackt sind das acht Byte (Zaehler, "LOB", Groesse), ungepackt vier
	; Nullbytes -- nachgemessen an allen AMNP-Behaeltern (Erkenntnis 183).
lsf_amnp:
	cmp.l	#8,d5			; Block muss ueber die Klarbytes hinaus
	bls.b	lsf_fertig
	moveq	#8,d2
	move.l	a1,a0
	bsr	Ist_lob
	beq.b	lsf_amnp_ab
	moveq	#4,d2			; ungepackt: nur vier
lsf_amnp_ab:
	move.l	a1,a0
	add.l	d2,a0
	move.l	d5,d0
	sub.l	d2,d0
	move.w	d7,d1
	bsr	JH_decrypt
lsf_packkopf:
	bsr	Packkopf_aufloesen	; d6 kann danach ein neues Handle sein

lsf_fertig:
	moveq	#0,d0
	move.w	d6,d0			; Rueckgabe: das Handle
	bra.b	lsf_out
lsf_fehler:
	moveq	#0,d0
lsf_out:
	bsr	Dateiblock		; fuer Kill_unclaimed_memory (MEMORY.S)
	movem.l	(sp)+,d1-d7/a0-a3
	rts

; ***************************************************************************
; Eintrag_lesen -- read one entry of a container, and only that entry.
;
; As Thalion's library does it (AM2_CPU 0:$24FFA, finding 268): open the
; file, read the six-byte head and the length table up to the entry, seek
; to the entry, read it, close.  Until 2026-10-21 Datei_lesen read the
; whole container (up to 609 KB) and kept it in a one-slot cache; that cost
; a long pause at every change of file (a map change reads several) and
; the memory of a second copy.  The cache is gone with it.
;
; **If Fseek lands elsewhere**, the whole file is read as before
; (Eintrag_aus_datei).  The comment in FALCON_OFF.S reported Fseek as
; unreliable once (MAP.S, the value "megabytes off"); most likely that was
; finding 270, TOS clobbering d0-d2/a0-a2 before the Gemdos macro saved
; them.  MUSIK_YM.S has used Fseek since without trouble.  The check costs
; one comparison.
;
; While the file is open, its handle is in ls_offen, so that
; Close_current_file can close it when the way out does not come back:
; Out_of_memory (Speicher_anfordern), Disk_error_handler "no", the load
; error screen.
;
;   IN : d1 = file number of the container (after Teildatei_waehlen),
;        d7 = entry (from one)
;   OUT: d0 = memory handle (zero: not loaded), d5 = length,
;        d2 = container id ('AMNC' ...), d3.w = number of entries
;        ($FFFF after a file error), d7 = entry (LADEFEHLERTEST: one past
;        the last)
; ***************************************************************************
Eintrag_lesen:
	addq.w	#1,Data_change_count	; new data (MEMORY.S, the ST's tile cache)
	movem.l	d1/d4/d6/a0-a2,-(sp)
eles_nochmal:
	moveq	#0,d0			; Modus 0 = lesen
	bsr	Behaelter_oeffnen	; a2 = Name
	bmi.b	eles_dos
	beq.b	eles_kaputt		; kein Name hinterlegt
	bsr	Eintrag_suchen		; d2, d3, d4 = Versatz, d5 = Laenge
	tst.l	d0
	beq.b	eles_lesen
	cmp.l	#ES_DANEBEN,d0
	bhi.b	eles_dos_zu		; Lesefehler
	bsr	Close_current_file
	cmp.l	#ES_GIBTSNICHT,d0
	beq.b	eles_nichts
	bsr	Eintrag_aus_datei	; Fseek lag daneben: ganz lesen
	bra.b	eles_out
eles_lesen:
	move.l	d5,d0
	bsr	Speicher_anfordern	; im Spiel: Out_of_memory schliesst die Datei
	tst.l	d0
	beq.b	eles_kein_platz
	move.w	d0,d6			; d6 = Handle
	bsr	Block_adresse
	move.l	d0,a0
	move.l	d5,d0
	bsr	Offen_lesen
	bne.b	eles_kurz
	bsr	Close_current_file
	moveq	#0,d0
	move.w	d6,d0
	bra.b	eles_out
eles_kurz:
	exg	d0,d6			; Fehler merken, den Block freigeben
	and.l	#$FFFF,d0
	bsr	Free_memory
	move.l	d6,d0
eles_dos_zu:
	bsr	Close_current_file
eles_dos:
	bsr	Dateifehler		; a2 = Name, d0 = Fehler
	beq.b	eles_nochmal
eles_kaputt:
	move.w	#$FFFF,d3
	bra.b	eles_nichts
eles_kein_platz:
	bsr	Close_current_file
	move.w	#$FFFF,d3
eles_nichts:
	moveq	#0,d0
eles_out:
	movem.l	(sp)+,d1/d4/d6/a0-a2
	rts

; Rueckgaben von Eintrag_suchen neben 0 (steht am Eintrag) und Lesefehlern
ES_GIBTSNICHT	equ	1		; den Eintrag gibt es nicht, oder er ist leer
ES_DANEBEN	equ	2		; Fseek kam woanders an

; ***************************************************************************
; Eintrag_suchen -- in der offenen Containerdatei an einen Eintrag gehen.
;
; Reads the head (id, number of entries) and the lengths of entries 1 to
; d7, in pieces of ES_STUECK, and seeks to the entry.  The file is open
; (ls_offen) and stands at its start.  The arithmetic is that of
; Eintrag_lage: head six bytes plus one long per entry, then the blocks
; one after the other.
;
;   IN : d7 = entry (from one)
;   OUT: d0 = 0 at the entry, ES_GIBTSNICHT, ES_DANEBEN, or a read error
;        (negative GEMDOS error or ERROR_INCOMPLETE_READ);
;        d2 = id, d3 = number of entries, d4 = offset, d5 = length;
;        d7 = entry (LADEFEHLERTEST: one past the last)
; ***************************************************************************
ES_STUECK	equ	64		; Laengen je Fread

Eintrag_suchen:
	movem.l	d1/d6/a0-a1,-(sp)
	lea	ls_kopf,a0
	moveq	#6,d0
	bsr	Offen_lesen
	bne	esu_out
	move.l	ls_kopf,d2		; Kennung
	moveq	#0,d3
	move.w	ls_kopf+4,d3		; Anzahl der Eintraege
	IFD	LADEFEHLERTEST
	tst.b	lft_jetzt
	beq.b	.kein_test
	sf	lft_jetzt
	move.w	d3,d7
	addq.w	#1,d7
.kein_test:
	ENDC
	moveq	#ES_GIBTSNICHT,d0
	tst.w	d7
	beq.b	esu_out
	cmp.w	d3,d7
	bhi.b	esu_out
	move.l	d3,d4			; Versatz des ersten Blocks
	lsl.l	#2,d4
	addq.l	#6,d4
	move.w	d7,d6			; so viele Laengen noch
esu_stueck:
	moveq	#ES_STUECK,d1
	cmp.w	d1,d6
	bhs.b	esu_voll
	move.w	d6,d1
esu_voll:
	sub.w	d1,d6
	moveq	#0,d0
	move.w	d1,d0
	lsl.l	#2,d0
	lea	ls_laengen,a0
	bsr	Offen_lesen
	bne.b	esu_out
	lea	ls_laengen,a1
	subq.w	#1,d1
esu_summe:
	move.l	(a1)+,d5
	add.l	d5,d4
	dbf	d1,esu_summe
	tst.w	d6
	bne.b	esu_stueck
	sub.l	d5,d4			; der letzte ist der gesuchte selbst
	moveq	#ES_GIBTSNICHT,d0
	tst.l	d5
	beq.b	esu_out			; leerer Eintrag
	clr.w	-(sp)			; Modus 0: vom Dateianfang
	move.w	ls_offen,-(sp)
	move.l	d4,-(sp)
	move.w	#Fseek,-(sp)
	Gemdos
	lea	10(sp),sp
	cmp.l	d4,d0
	beq.b	esu_da
	moveq	#ES_DANEBEN,d0
	bra.b	esu_out
esu_da:
	moveq	#0,d0
esu_out:
	movem.l	(sp)+,d1/d6/a0-a1
	tst.l	d0
	rts

; ***************************************************************************
; Behaelter_oeffnen -- eine Datei oeffnen und ls_offen setzen.
;   IN : d1 = Dateinummer, d0.w = Modus (0 lesen, 2 lesen und schreiben)
;   OUT: a2 = Name; d0 = Handle (> 0), 0 = kein Name hinterlegt, negativ =
;        GEMDOS-Fehler.  Die Flags folgen d0.
; ***************************************************************************
Behaelter_oeffnen:
	movem.l	d2/a0,-(sp)
	move.w	d0,d2			; Modus
	bsr	Datei_name		; a0 = Name, null wenn keiner hinterlegt
	move.l	a0,a2
	move.l	a0,d0
	beq.b	bo_out
	move.w	d2,-(sp)
	move.l	a2,-(sp)
	move.w	#Fopen,-(sp)
	Gemdos
	addq.l	#8,sp
	tst.l	d0
	bmi.b	bo_out
	move.w	d0,ls_offen
bo_out:
	movem.l	(sp)+,d2/a0
	tst.l	d0
	rts

; ***************************************************************************
; Offen_lesen -- aus der offenen Datei (ls_offen) lesen.
;   IN : a0 = Ziel, d0 = Laenge
;   OUT: d0 = 0 alles gelesen, sonst GEMDOS-Fehler (negativ) oder
;        ERROR_INCOMPLETE_READ.  Die Flags folgen d0.
; ***************************************************************************
Offen_lesen:
	movem.l	d1,-(sp)
	move.l	d0,d1
	move.l	a0,-(sp)		; Puffer zuerst, dann Laenge
	move.l	d0,-(sp)
	move.w	ls_offen,-(sp)
	move.w	#Fread,-(sp)
	Gemdos
	lea	12(sp),sp
	cmp.l	d1,d0
	beq.b	ol_gut
	tst.l	d0
	bmi.b	ol_out
	move.l	#ERROR_INCOMPLETE_READ,d0
	bra.b	ol_out
ol_gut:
	moveq	#0,d0
ol_out:
	movem.l	(sp)+,d1
	tst.l	d0
	rts

; ***************************************************************************
; Close_current_file -- close the open file (0:$26220).
;   All registers are preserved.
;
; Thalion's Disk_error_handler and Disk_requester call it before they end
; the program, our Ladefehler_schirm and Speicher_anfordern before they
; leave for good.  Since 2026-10-21 a container stays open while its entry
; is read (Eintrag_lesen), so there can be a file open: its handle is in
; ls_offen, zero when none is.
;
; Bis 2026-10-01 schloss es f_handle(a5), das niemand setzt, und las dabei
; ueber a5, das Thalions Aufrufer nicht auf unsere Variablen stellt
; (Erkenntnis 177) -- es haette eine fremde Dateikennung geschlossen.
; ***************************************************************************
Close_current_file:
	movem.l	d0,-(sp)
	move.w	ls_offen,d0
	beq.b	ccf_out
	clr.w	ls_offen
	move.w	d0,-(sp)
	move.w	#Fclose,-(sp)
	Gemdos
	addq.l	#4,sp
ccf_out:
	movem.l	(sp)+,d0
	rts

; ***************************************************************************
; Eintrag_aus_datei -- the way back when Fseek lands elsewhere: read the
; whole file and copy the entry out, as Load_subfile did until 2026-10-21.
;   IN : d1 = file number, d4 = offset, d5 = length
;   OUT: d0 = memory handle (zero: not loaded)
; ***************************************************************************
Eintrag_aus_datei:
	movem.l	d1-d3/a0-a1,-(sp)
	bsr	Datei_lesen		; d0 = Handle der ganzen Datei, d1 = Laenge
	tst.l	d0
	beq.b	ead_out
	move.l	d0,d3
	bsr	Dateiblock		; Out_of_memory gibt ihn dann frei
	move.l	d4,d2
	add.l	d5,d2
	cmp.l	d1,d2			; liegt der Eintrag in der Datei?
	bhi.b	ead_frei
	move.l	d5,d0
	bsr	Speicher_anfordern
	tst.l	d0
	beq.b	ead_frei
	move.l	d0,d2			; d2 = Handle des Eintrags
	bsr	Block_adresse
	move.l	d0,a1
	move.l	d3,d0
	bsr	Block_adresse
	move.l	d0,a0
	add.l	d4,a0
	move.l	d5,d0
	bsr	Copy_memory
	move.l	d3,d0
	bsr	Free_memory
	move.l	d2,d0
	bra.b	ead_out
ead_frei:
	move.l	d3,d0
	bsr	Free_memory
	moveq	#0,d0
ead_out:
	movem.l	(sp)+,d1-d3/a0-a1
	rts

; ***************************************************************************
; Load_unique_subfile -- ein Teil einer Datei als **eigene Kopie** laden.
;
;   IN : d0.w = Teil, d1.w = Dateinummer (wie Load_subfile)
;   OUT: d0 = Speicher-Handle, null wenn es nicht geklappt hat
;
; Einziger Aufrufer ist Thalions Dialogue_ModInit (DIALOGUE.S): das
; Portrait des Gespraechspartners; Dialogue_ModExit gibt es mit Kill_memory
; wieder her.  In AM2_CPU 1.20 (0:$25162) unterscheidet es sich von
; Load_subfile (0:$250C8) nur am Anfang: Load_subfile nimmt einen schon
; geladenen Block derselben Datei ueber Reallocate_memory wieder her, dieses
; legt eine eigene Kopie an (0:$23E02, File_allocate).  Unsere
; Speicherverwaltung teilt keine Bloecke -- Load_subfile liefert immer eine
; eigene Kopie, also ist es dasselbe.
;
; Bis 2026-09-28 stand hier ein leerer Platzhalter: d0 kam unveraendert
; zurueck, die Portraitnummer galt als Handle, und Dialogue_ModExit gab
; einen fremden Block frei.
; ***************************************************************************
Load_unique_subfile:
	bra	Load_subfile

; ***************************************************************************
; Packkopf_aufloesen -- die Packschicht eines AMNP/AMPC-Eintrags abnehmen.
;
; **Thalions Aufrufer lesen direkt nach Load_subfile los**: Init_map den
; Kartentyp, Load_2D_map_data die Kacheldaten, ShowPicTxt_ModInit das
; Ereignisbild.  Decompress ruft Thalions Quelltext ein einziges Mal, in
; Show_layout -- und Layouts.amb ist AMNC, dort liegt LOB *unter* der
; Verschluesselung, eine zweite Schicht, die der Aufrufer abnimmt.  Die
; Packschicht der AMNP/AMPC-Eintraege hat also das Original-Load_subfile
; selbst aufgeloest (Erkenntnis 183).  Jeder Eintrag beginnt mit einem Kopf:
;
;     1,"LOB",Groesse,gepackte Laenge,Rumpf   gepackt (Zaehler durchweg 1)
;     0,0,0,0,Daten                           ungepackt
;
; Gepackt: neuer Block in der entpackten Groesse, der gepackte wird frei.
; Ungepackt: die Daten ruecken um vier Byte nach vorn, der Block schrumpft.
;
;   IN : d6 = Handle des Eintrags, d5 = seine Laenge
;   OUT: d6 = Handle der Daten (null bei Speichermangel)
; ***************************************************************************
Packkopf_aufloesen:
	movem.l	d0-d3/a0-a1,-(sp)
	bsr	Claim_pointer_d6	; a0 = Eintrag
	bsr	Ist_lob
	beq.b	pka_lob
	cmp.l	#4,d5
	bls.b	pka_out
	tst.l	(a0)
	bne.b	pka_out			; kein Packkopf: so lassen
	move.l	a0,a1			; ungepackt: vier Byte nach vorn
	addq.l	#4,a0
	move.l	d5,d0
	subq.l	#4,d0
	bsr	Copy_memory		; vorwaerts, Ziel vor der Quelle: geht
	moveq	#0,d0
	move.w	d6,d0
	move.l	d5,d1
	subq.l	#4,d1
	bsr	Shrink_memory
	bra.b	pka_out
pka_lob:
	move.l	4(a0),d2
	and.l	#$00FFFFFF,d2		; entpackte Groesse (Byte 4 ist Kennung)
	move.l	d2,d0
	bsr	Speicher_anfordern
	tst.l	d0
	beq.b	pka_fehler
	move.w	d0,d3			; neues Handle
	bsr	Block_adresse
	move.l	d0,a1			; Ziel
	lea	12(a0),a0		; Rumpf hinter dem Kopf
	move.l	d2,d0
	bsr	LOB_decompress
	moveq	#0,d0			; den gepackten Block zurueckgeben
	move.w	d6,d0
	bsr	Free_memory
	move.w	d3,d6
	bra.b	pka_out
pka_fehler:
	moveq	#0,d0
	move.w	d6,d0
	bsr	Free_memory
	moveq	#0,d6
pka_out:
	movem.l	(sp)+,d0-d3/a0-a1
	rts

; a0 = Block -> Z gesetzt, wenn er mit ?,"LOB" beginnt.
Ist_lob:
	cmp.b	#'L',1(a0)
	bne.b	il_out
	cmp.b	#'O',2(a0)
	bne.b	il_out
	cmp.b	#'B',3(a0)
il_out:	rts

; ***************************************************************************
; Teildatei_waehlen -- welcher Behaelter einer mehrteiligen Datei?
;
; Neun Dateiarten liegen auf der Diskette in mehreren Behaeltern:
; 1Map_data.amb bis 3Map_data.amb, ebenso Map_texts und Icon_gfx, und die
; 3D-Dateien 2/3Lab_data, 2/3Wall3D, 2/3Object3D, 2/3Overlay3D.  Thalions Code
; kennt je eine Dateinummer; den Teil waehlt die Bibliothek.
;
; **Sie waehlt nach Map_nr, nicht nach dem Eintrag** (AM2_CPU 0:$29846,
; Erkenntnis 197):
;
;     Map_nr   1-256   Teil 1
;            257-299   Teil 2
;            300-399   Teil 3
;            ab 400    Teil 2
;
; Bis 2026-09-28 stand hier eine Messung an den nicht leeren Eintraegen
; (Erkenntnis 183).  Fuer Karten und Kartentexte faellt beides zusammen, denn
; der Eintrag ist die Kartennummer.  Bei Wall3D und Object3D nicht: 2Wall3D
; und 3Wall3D tragen teils unter derselben Nummer andere Grafik.
;
; Gezaehlt wird in jedem Behaelter ab eins, die Nummer bleibt also, nur die
; Datei wechselt -- und damit auch der JH-Schluessel nicht (Eintragsnummer).
; Die 3D-Dateien haben keinen Teil 1 (Karten bis 256 sind die 2D-Welten);
; dort nimmt die Tabelle Teil 2, wo das Original "1Wall3D.amb" suchen und
; nicht finden wuerde.
;
;   IN : d1 = Dateinummer (Thalions), Map_nr
;   OUT: d1 = Dateinummer des Behaelters (unsere Nummern ab 48)
;   Alle uebrigen Register bleiben.
; ***************************************************************************
Teildatei_waehlen:
	movem.l	d0/a0,-(sp)
	lea	tw_tabelle,a0
tw_such:
	move.w	(a0)+,d0		; Thalions Dateinummer
	bmi.b	tw_out			; Ende: keine mehrteilige Datei
	cmp.w	d0,d1
	beq.b	tw_gefunden
	addq.l	#6,a0			; Teil 1, 2, 3 ueberspringen
	bra.b	tw_such
tw_gefunden:
	move.w	Map_nr,d0
	cmp.w	#257,d0
	bcs.b	tw_eins
	cmp.w	#300,d0
	bcs.b	tw_zwei
	cmp.w	#400,d0
	bcs.b	tw_drei
tw_zwei:
	move.w	2(a0),d1
	bra.b	tw_out
tw_drei:
	move.w	4(a0),d1
	bra.b	tw_out
tw_eins:
	move.w	(a0),d1
tw_out:
	movem.l	(sp)+,d0/a0
	rts

	SECTION	Fast_DATA,data
	even
; Thalions Nummer, dann die Nummern fuer Teil 1, 2, 3 (Liste 4:$799C in
; AM2_CPU: dieselben neun Dateiarten).
tw_tabelle:
	dc.w	Map_data_file,Map_data_file,Map_data2_file,Map_data3_file
	dc.w	Map_text_file,Map_text_file,Map_text2_file,Map_text3_file
	dc.w	Icon_gfx_file,Icon_gfx_file,Icon_gfx2_file,Icon_gfx3_file
	dc.w	Lab_data_file,Lab_data_file,Lab_data_file,Lab_data3_file
	dc.w	Wall_3D_CHIP_file,Wall_3D_CHIP_file,Wall_3D_CHIP_file,Wall_3D3_file
	dc.w	Wall_3D_FAST_file,Wall_3D_FAST_file,Wall_3D_FAST_file,Wall_3D3_file
	dc.w	Object_3D_CHIP_file,Object_3D_CHIP_file,Object_3D_CHIP_file,Object_3D3_file
	dc.w	Object_3D_FAST_file,Object_3D_FAST_file,Object_3D_FAST_file,Object_3D3_file
	dc.w	Overlay_3D_file,Overlay_3D_file,Overlay_3D_file,Overlay_3D3_file
	dc.w	-1
	SECTION	Program,code

; d6 = Handle -> a0 = Zeiger.  Nur ein Handgriff, damit oben nichts mit d0
; durcheinandergeraet.
Claim_pointer_d6:
	movem.l	d0,-(sp)
	moveq	#0,d0
	move.w	d6,d0
	bsr	Block_adresse
	move.l	d0,a0
	movem.l	(sp)+,d0
	rts

; ***************************************************************************
; Eintrag_lage -- wo liegt ein Eintrag im Container und wie lang ist er?
;
; Gemeinsame Rechnung von Load_subfile und Save_subfile.  Der Kopf ist sechs
; Byte (Kennung und Anzahl) plus ein Langwort je Eintrag; danach liegen die
; Bloecke hintereinander, also ist der Versatz die Summe aller Laengen davor.
;
;   IN : a0 = Containeranfang, d0 = Eintragsnummer (ab eins)
;   OUT: d0 = Versatz (null = gibt es nicht oder leer), d1 = Laenge
; ***************************************************************************
Eintrag_lage:
	movem.l	d2-d4/a0-a1,-(sp)
	move.w	d0,d4			; gesuchter Eintrag
	beq.b	el_nichts		; null gibt es nicht
	moveq	#0,d2
	move.w	4(a0),d2		; Anzahl der Eintraege
	cmp.w	d2,d4
	bhi.b	el_nichts
	move.l	d2,d3			; Versatz des ersten Blocks
	lsl.l	#2,d3
	addq.l	#6,d3
	lea	6(a0),a1		; Laengentabelle
	move.w	d4,d2
	subq.w	#1,d2			; so viele liegen davor
	beq.b	el_da
el_summe:
	add.l	(a1)+,d3
	subq.w	#1,d2
	bne.b	el_summe
el_da:
	lea	6(a0),a1		; Laenge des gesuchten Eintrags
	move.w	d4,d2
	subq.w	#1,d2
	lsl.w	#2,d2
	move.l	0(a1,d2.w),d1
	beq.b	el_nichts		; leerer Eintrag
	move.l	d3,d0
	bra.b	el_out
el_nichts:
	moveq	#0,d0
	moveq	#0,d1
el_out:
	movem.l	(sp)+,d2-d4/a0-a1
	rts

; ***************************************************************************
; Datei_sichern -- einen Speicherblock als ganze Datei schreiben.
;
;   IN : d1 = Dateinummer (0: Name in a1), a0 = Daten, d0 = Laenge
;   OUT: d0 = null in Ordnung, negativ bei Fehler
; Fehler gehen wie in Datei_lesen an Disk_error_handler (Dateifehler).
; ***************************************************************************
Datei_sichern:
	movem.l	d1-d3/a0-a2,-(sp)
	move.l	a0,a2			; Daten festhalten
	move.l	d0,d3			; Laenge
dsi_nochmal:
	move.l	4*4(sp),a0		; a1 des Aufrufers: fuer Nummer 0 der Name
	bsr	Datei_name		; a0 = Name
	move.l	a0,d0
	beq	dsi_fehler
	move.l	a0,a1

	clr.w	-(sp)			; Attribut 0
	move.l	a1,-(sp)
	move.w	#Fcreate,-(sp)
	Gemdos
	lea	8(sp),sp
	tst.l	d0
	bmi.b	dsi_dos
	move.w	d0,ls_fhandle

	move.l	a2,-(sp)		; Puffer zuerst, dann Laenge
	move.l	d3,-(sp)
	move.w	ls_fhandle,-(sp)
	move.w	#Fwrite,-(sp)
	Gemdos
	lea	12(sp),sp
	move.l	d0,d2			; geschrieben

	move.w	ls_fhandle,-(sp)
	move.w	#Fclose,-(sp)
	Gemdos
	addq.l	#4,sp

	cmp.l	d3,d2			; alles geschrieben?
	beq.b	dsi_gut
	move.l	d2,d0			; GEMDOS-Fehler oder zu wenig?
	bmi.b	dsi_dos
	move.l	#ERROR_INCOMPLETE_WRITE,d0
dsi_dos:
	move.l	a2,-(sp)
	move.l	a1,a2			; Name fuer die Meldung
	bsr	Dateifehler
	move.l	(sp)+,a2		; (movea aendert die Flags nicht)
	beq	dsi_nochmal
	bra.b	dsi_fehler
dsi_gut:
	moveq	#0,d0
	bra.b	dsi_out
dsi_fehler:
	moveq	#-1,d0
dsi_out:
	movem.l	(sp)+,d1-d3/a0-a2
	rts

; ***************************************************************************
; Load_batch_of_subfiles -- mehrere Eintraege derselben Datei auf einmal.
;
; Abgelesen an MAIN.S und CHARACTE.S:
;
;     lea.l   Batch,a0            ; Liste der Eintragsnummern (Worte)
;     lea.l   Party_handles,a1    ; Liste fuer die Handles (Bytes)
;     moveq.l #Party_char_file,d1
;     jsr     Load_batch_of_subfiles
;
;   IN : d0 = Anzahl, d1 = Dateinummer,
;        a0 = Eintragsnummern (.w), a1 = Ziel fuer die Handles (.b)
;
; Dass die Handles als Byte abgelegt werden, steht in der Aufrufstelle
; daneben: MAIN.S liest sie gleich darauf mit "move.b (a1)+,d1" wieder aus.
; ***************************************************************************
Load_batch_of_subfiles:
	movem.l	d0-d3/a0-a2,-(sp)
	move.w	d0,d3
	subq.w	#1,d3
	bmi.b	lbs_out
lbs_l:
	move.w	(a0)+,d0		; naechste Eintragsnummer
	bsr	Load_subfile		; d1 bleibt die Dateinummer
	move.b	d0,(a1)+
	dbf	d3,lbs_l
lbs_out:
	movem.l	(sp)+,d0-d3/a0-a2
	rts

; ***************************************************************************
; Load_batch_of_unique_subfiles -- dasselbe, mit geteilten und eigenen
; Eintraegen.  Gleiche Schnittstelle.
;
; So laedt 3D_MAP.S seine Waende, und so tut es Thalions Bibliothek
; (AM2_CPU 0:$25354, Erkenntnis 196):
;
; - Kommt eine Eintragsnummer mehrfach vor, bekommt sie dasselbe Handle
;   noch einmal statt einer zweiten Kopie.
; - **Bit 15 der Nummer heisst "eigene Kopie"**: das Bit wird geloescht, der
;   Eintrag frisch geladen und mit niemandem geteilt.  Load_3D_map_data
;   setzt es bei jeder Wand, auf die es Overlays malt -- zwei solche Waende
;   mit derselben Grafik bekaemen sonst beide Overlays auf ein Bild.
;
; Bis 2026-09-28 kannte unsere Fassung (aus der Nachbauzeit) das Bit nicht:
; sie teilte auch markierte Eintraege und gab die Nummer samt Bit an
; Load_subfile weiter.
;
; Eine markierte Nummer steht in der Liste mit gesetztem Bit und gleicht
; darum keiner unmarkierten; geteilt wird also nur unter unmarkierten.
; Remove_3D_map_data gibt jedes Handle der Liste frei, ein geteiltes also
; mehrmals hintereinander; Free_memory uebergeht ein schon freies Handle.
;
;   IN : d0 = Anzahl, d1 = Dateinummer,
;        a0 = Eintragsnummern (.w), a1 = Ziel fuer die Handles (.b)
; ***************************************************************************
Load_batch_of_unique_subfiles:
	movem.l	d0-d5/a0-a3,-(sp)
	move.w	d0,d3
	subq.w	#1,d3
	bmi.b	lbu_out
	move.l	a0,a2			; Anfang der Nummernliste
	move.l	a1,a3			; Anfang der Handleliste
	moveq	#0,d4			; wieviele liegen schon dahinter
lbu_l:
	move.w	(a0)+,d2		; naechste Eintragsnummer
	bclr	#15,d2			; eigene Kopie verlangt?
	bne.b	lbu_neu			; ja: nie teilen
	moveq	#0,d5
	tst.w	d4
	beq.b	lbu_neu			; die erste kann keine Wiederholung sein
lbu_such:
	move.w	d5,d0
	add.w	d0,d0
	cmp.w	0(a2,d0.w),d2		; schon einmal dagewesen (unmarkiert)?
	bne.b	lbu_weiter
	move.b	0(a3,d5.w),(a1)+	; ja: dasselbe Handle noch einmal
	bra.b	lbu_next
lbu_weiter:
	addq.w	#1,d5
	cmp.w	d4,d5
	blo.b	lbu_such
lbu_neu:
	move.w	d2,d0
	bsr	Load_subfile		; d1 bleibt die Dateinummer
	move.b	d0,(a1)+
lbu_next:
	addq.w	#1,d4
	dbf	d3,lbu_l
lbu_out:
	movem.l	(sp)+,d0-d5/a0-a3
	rts

; ***************************************************************************
; Save_subfile -- Thalions Symbol.  Einen Eintrag in den Container zurueck.
;
; Abgelesen an den Aufrufstellen (AUTOMAPP.S, ACTIONS.S, CHARACTE.S,
; EVENTS.S) -- dieselben beiden Nummern wie bei Load_subfile, dazu der Zeiger:
;
;     moveq.l #0,d0 / move.b Event_b4(a5),d0 / addq.w #1,d0
;     moveq.l #Chest_data_file,d1
;     Get     Chest_data_handle,a0
;     jsr     Save_subfile
;
;   IN : d0 = Nummer des Eintrags (.w, ab eins)
;        d1 = Dateinummer
;        a0 = Daten
;
; **Eine Laenge wird nicht uebergeben**, es wird also der vorhandene Eintrag
; ueberschrieben -- und genau das geht auf: die Dateien, in die geschrieben
; wird, sind der Spielstand (Automap.amb, Chest_data.amb, Party_char.amb,
; Merchant_data.amb), und die sind durchweg AMBR mit rohen Eintraegen fester
; Groesse -- kein LOB, keine JH-Huelle.  Nachgesehen mit tools/ambtool.py:
; Chest_data.amb hat 256 Eintraege, davon 185 mit genau 148 Byte und 71 leer.
; Es braucht hier also weder Packer noch Verschluesselung.
;
; Since 2026-10-21 only the entry is written, at its place in the file
; (Eintrag_suchen, Fseek); before, the whole file was read and written anew.
; ***************************************************************************
Save_subfile:
	movem.l	d0-d7/a0-a3,-(sp)
	move.w	d0,d7			; Eintrag
	move.l	a0,a3			; Daten
	move.w	d1,d6			; Dateinummer
ssf_nochmal:
	move.w	d6,d1
	moveq	#2,d0			; Modus 2 = lesen und schreiben
	bsr	Behaelter_oeffnen	; a2 = Name
	bmi.b	ssf_dos
	beq.b	ssf_out			; kein Name hinterlegt
	bsr	Eintrag_suchen		; d4 = Versatz, d5 = Laenge
	tst.l	d0
	beq.b	ssf_schreiben
	cmp.l	#ES_DANEBEN,d0
	bhi.b	ssf_dos_zu		; Lesefehler
	bsr	Close_current_file
	cmp.l	#ES_GIBTSNICHT,d0
	beq.b	ssf_out
	bsr	Eintrag_in_datei	; Fseek lag daneben: ganz schreiben
	bra.b	ssf_out
ssf_schreiben:
	move.l	a3,-(sp)		; Puffer zuerst, dann Laenge
	move.l	d5,-(sp)
	move.w	ls_offen,-(sp)
	move.w	#Fwrite,-(sp)
	Gemdos
	lea	12(sp),sp
	bsr	Close_current_file
	cmp.l	d5,d0			; alles geschrieben?
	beq.b	ssf_out
	tst.l	d0			; GEMDOS-Fehler oder zu wenig?
	bmi.b	ssf_dos
	move.l	#ERROR_INCOMPLETE_WRITE,d0
	bra.b	ssf_dos
ssf_dos_zu:
	bsr	Close_current_file
ssf_dos:
	bsr	Dateifehler		; a2 = Name, d0 = Fehler
	beq.b	ssf_nochmal
ssf_out:
	movem.l	(sp)+,d0-d7/a0-a3
	rts

; ***************************************************************************
; Eintrag_in_datei -- the way back when Fseek lands elsewhere: read the
; whole file, replace the entry, write the whole file, as Save_subfile did
; until 2026-10-21.
;   IN : d6 = file number, d7 = entry, a3 = data
; ***************************************************************************
Eintrag_in_datei:
	movem.l	d0-d1/d4-d5/a0-a1,-(sp)
	move.w	d6,d1
	bsr	Datei_lesen		; d0 = Handle, d1 = Laenge
	tst.l	d0
	beq.b	eid_out
	move.l	d0,d5			; Handle der ganzen Datei
	move.l	d1,d4			; ihre Laenge
	bsr	Block_adresse
	move.l	d0,a0			; Containeranfang
	move.w	d7,d0
	bsr	Eintrag_lage		; d0 = Versatz, d1 = Laenge
	tst.l	d0
	beq.b	eid_frei
	move.l	a0,-(sp)
	lea	0(a0,d0.l),a1
	move.l	a3,a0
	move.l	d1,d0
	bsr	Copy_memory
	move.l	(sp)+,a0
	move.l	d4,d0
	move.w	d6,d1
	bsr	Datei_sichern
eid_frei:
	move.l	d5,d0
	bsr	Free_memory
eid_out:
	movem.l	(sp)+,d0-d1/d4-d5/a0-a1
	rts

; ***************************************************************************
; Dateifehler -- ein GEMDOS-Fehler beim Lesen oder Schreiben.
;
; **Wie in AM2_CPU** (0:$25FDA/$25FF8, Erkenntnis 268): jede DOS-Routine der
; Bibliothek holt bei einem Fehler IoErr und ruft Thalions
; Disk_error_handler (HULL/CONTROLS.S).  Der zeigt "Fehler ... Datei ...
; Nochmal?"; nein heisst Close_current_file und Exit_program mit OS_ERROR,
; ja kehrt zurueck, und die Routine versucht es von vorn.  (Bei
; ERROR_DEVICE_NOT_MOUNTED fragte das Original stattdessen nach der
; Diskette, Disk_requester; das kann GEMDOS nicht melden.)
;
; Nur im Spiel (Notweg, MEMORY.S): die Abfrage ist ein Modul (Req_Mod) und
; braucht Schirm, Stapel und Texte; waehrend Out_of_memory gilt dasselbe
; wie dort.  Sonst kommt Z = 0 zurueck, und der Aufrufer meldet den Fehler
; wie bisher.
;
;   IN : d0.l = GEMDOS-Fehler (negativ) oder ERROR_INCOMPLETE_READ/WRITE,
;        a2 = Name
;   OUT: Z = 1 nochmal versuchen, Z = 0 aufgeben.  Alle Register bleiben.
; ***************************************************************************
Dateifehler:
	tst.b	Notweg
	bne.b	dfe_fragen
	move.w	#0,ccr			; Z = 0: aufgeben
	rts
dfe_fragen:
	movem.l	d0-d7/a0-a6,-(sp)
	lea	df_name,a1		; Name sichern, dn_voll ist fluechtig
	moveq	#DF_NAME_MAX-2,d1
dfe_kop:
	move.b	(a2)+,(a1)+
	dbeq	d1,dfe_kop
	clr.b	(a1)
	move.l	#df_name,Current_filename
	bsr.b	Fehler_umsetzen
	jsr	Disk_error_handler	; kehrt nur bei "nochmal" zurueck
	movem.l	(sp)+,d0-d7/a0-a6
	move.w	#4,ccr			; Z = 1: nochmal
	rts

; Fehler_umsetzen -- d0.l: GEMDOS-Fehler -> AmigaDOS-Nummer (.w), wie sie
; Disk_errors in Thalions CONTROLS.S kennt.  Positive Werte bleiben (das
; sind schon Thalions ERROR_INCOMPLETE_READ/WRITE).  Unbekannte werden 0,
; Disk_error_handler meldet dann Text 93 ("vermutlich Lese-/Schreibfehler").
Fehler_umsetzen:
	move.l	a0,-(sp)
	tst.l	d0
	bpl.b	fu_out
	lea	fu_tabelle,a0
fu_such:
	tst.w	(a0)
	beq.b	fu_unbekannt
	cmp.w	(a0)+,d0
	beq.b	fu_da
	addq.l	#2,a0
	bra.b	fu_such
fu_da:	move.w	(a0),d0
	ext.l	d0
	bra.b	fu_out
fu_unbekannt:
	moveq	#0,d0
fu_out:	move.l	(sp)+,a0
	rts

	SECTION	Fast_DATA,data
; GEMDOS -> AmigaDOS (Erkenntnis 268).  Nach Bedeutung, nicht nach Nummer.
fu_tabelle:
	dc.w	-33,ERROR_OBJECT_NOT_FOUND	; EFILNF Datei nicht gefunden
	dc.w	-34,ERROR_DIR_NOT_FOUND		; EPTHNF Pfad nicht gefunden
	dc.w	-46,ERROR_DIR_NOT_FOUND		; EDRIVE Laufwerk gibt es nicht
	dc.w	-35,ERROR_OBJECT_IN_USE		; ENHNDL keine Dateikennung frei
	dc.w	-36,ERROR_WRITE_PROTECTED	; EACCDN Zugriff verweigert
	dc.w	-39,ERROR_NO_FREE_STORE		; ENSMEM kein Speicher
	dc.w	-13,ERROR_DISK_WRITE_PROTECTED	; EWRPRO Diskette schreibgeschuetzt
	dc.w	-6,ERROR_SEEK_ERROR		; ESEEK Suchfehler
	dc.w	0
	SECTION	Fast_BSS,bss
DF_NAME_MAX	equ	64
df_name:	ds.b	DF_NAME_MAX	; Name fuer Disk_error_handler (Current_filename)
Current_filename:	ds.l	1	; Thalions Name: Zeiger auf den Dateinamen
	IFD	LADEFEHLERTEST
lft_fertig:	ds.b	1
lft_jetzt:	ds.b	1		; Eintrag_suchen nimmt einen zu viel
	even
	ENDC
	even
	SECTION	Program,code

; ***************************************************************************
; Datei_lesen -- eine ganze Datei in einen frischen Speicherblock holen.
; For Load_file, and for Load_subfile and Save_subfile when Fseek lands
; elsewhere (Eintrag_aus_datei, Eintrag_in_datei).
;
; The length comes from the directory entry (Fsfirst fills the DTA, the
; length is at offset 26), so the block is requested at the exact size.  Die alte DTA wird zurueckgestellt: sie gehoert
; dem Aufrufer, nicht uns.
;
;   IN : d1 = Dateinummer (0: Name in a0)
;   OUT: d0 = Speicher-Handle (null = Fehler), d1 = gelesene Laenge
;
; **Ein GEMDOS-Fehler geht an Thalions Disk_error_handler** (Dateifehler,
; Erkenntnis 268): "Nochmal?" -- ja: von vorn, nein: Programmende.  Erst
; im Spiel (Notweg); davor kommt null zurueck wie bisher.  Der Name wird
; bei jedem Versuch neu gebildet: dn_voll gehoert jedem Aufruf von
; Datei_name, und die Abfrage dazwischen koennte selbst etwas laden.
; ***************************************************************************
Datei_lesen:
	addq.w	#1,Data_change_count	; new data (MEMORY.S, the ST's tile cache)
	movem.l	d2-d5/a0-a2,-(sp)
dls_nochmal:
	move.l	4*4(sp),a0		; a0 des Aufrufers (Name bei Nummer 0)
	bsr	Datei_name		; a0 = Name, null wenn keiner hinterlegt
	move.l	a0,d0
	beq	dls_fehler
	move.l	a0,a2

	; ---- Laenge aus dem Verzeichniseintrag ----
	move.w	#Fgetdta,-(sp)		; alte DTA merken, sie gehoert dem Aufrufer
	Gemdos
	addq.l	#2,sp
	move.l	d0,d4
	pea	ls_dta
	move.w	#Fsetdta,-(sp)
	Gemdos
	addq.l	#6,sp
	clr.w	-(sp)			; Attribut 0
	move.l	a2,-(sp)
	move.w	#Fsfirst,-(sp)
	Gemdos
	lea	8(sp),sp
	move.l	d0,d3			; Ergebnis merken
	move.l	d4,-(sp)		; DTA zurueckstellen
	move.w	#Fsetdta,-(sp)
	Gemdos
	addq.l	#6,sp
	move.l	d3,d0
	bmi	dls_dos			; Datei nicht gefunden
	move.l	ls_dta+DTA_LEN,d3	; d3 = Dateilaenge
	beq	dls_fehler

	; ---- Speicher und lesen ----
	move.l	d3,d0
	bsr	Speicher_anfordern
	tst.l	d0
	beq	dls_fehler
	move.w	d0,d2			; d2 = Handle
	bsr	Block_adresse
	move.l	d0,a1

	clr.w	-(sp)			; Modus 0 = lesen
	move.l	a2,-(sp)
	move.w	#Fopen,-(sp)
	Gemdos
	lea	8(sp),sp
	move.l	d0,d5			; Fehler, falls einer kommt
	bmi.b	dls_freigeben
	move.w	d0,ls_fhandle

	move.l	a1,-(sp)		; Puffer zuerst, dann Laenge
	move.l	d3,-(sp)
	move.w	ls_fhandle,-(sp)
	move.w	#Fread,-(sp)
	Gemdos
	lea	12(sp),sp
	move.l	d0,d5			; tatsaechlich gelesen

	move.w	ls_fhandle,-(sp)
	move.w	#Fclose,-(sp)
	Gemdos
	addq.l	#4,sp

	cmp.l	d3,d5			; alles gelesen?
	bne.b	dls_kurz
	moveq	#0,d0
	move.w	d2,d0			; Handle
	move.l	d3,d1			; Laenge
	bra.b	dls_out
dls_kurz:
	tst.l	d5			; GEMDOS-Fehler oder zu wenig?
	bmi.b	dls_freigeben
	move.l	#ERROR_INCOMPLETE_READ,d5
dls_freigeben:
	moveq	#0,d0
	move.w	d2,d0
	bsr	Free_memory
	move.l	d5,d0
dls_dos:
	bsr	Dateifehler		; a2 = Name, d0 = Fehler
	beq	dls_nochmal
dls_fehler:
	moveq	#0,d0
	moveq	#0,d1
dls_out:
	movem.l	(sp)+,d2-d5/a0-a2
	rts

; ***************************************************************************
; Load_file -- Thalions Symbol.  Eine *ganze* Datei holen, ausgepackt.
;
; Abgelesen an den Aufrufstellen (MAIN.S, ACTIONS.S, AUTOMAPP.S) -- und die
; Dateinummer steht hier in d0, nicht in d1 wie bei Load_subfile:
;
;     moveq.l #Dictionary_file,d0
;     jsr     Load_file
;     move.b  d0,Dictionary_handle
;
;   IN : d0 = Dateinummer (0: Name in a0, wie in AM2_CPU 1.20)
;   OUT: d0 = Speicher-Handle (.b), null wenn es nicht geklappt hat
;
; Die Aufrufer lesen danach unmittelbar los ("move.w (a0),d1"), also muss hier
; schon Klartext stehen.  Einzeldateien kommen in drei Macharten vor, belegt
; mit tools/ambtool.py an den tatsaechlich geladenen Dateien:
;
;     Dict.amb, Object_icons, Place_data   JH-Huelle
;     Automap_graphics                     LOB-Block
;     andere                               roh
;
; Die JH-Huelle traegt ihren Schluessel selbst: vier Byte Kopf, Schluessel ist
; Wort 0 ("JH") XOR Wort 1.  Danach kann noch ein LOB-Block folgen.
; ***************************************************************************
Load_file:
	movem.l	d1-d7/a0-a2,-(sp)
	move.w	d0,d1			; Datei_lesen erwartet sie in d1
	bsr	Datei_lesen		; d0 = Handle, d1 = Laenge
	tst.l	d0
	beq	lf_fehler
	move.w	d0,d7			; d7 = Handle der Rohdaten
	move.l	d1,d6			; d6 = Laenge
	bsr	Block_adresse
	move.l	d0,a2			; a2 = Nutzlast
	moveq	#0,d3			; Merker: lag eine JH-Huelle davor?

	; ---- JH-Huelle abziehen ----
	cmp.l	#6,d6
	blo.b	lf_kein_jh
	cmp.w	#'JH',(a2)
	bne.b	lf_kein_jh
	move.w	(a2),d1			; Schluessel = Wort 0 XOR Wort 1
	move.w	2(a2),d0
	eor.w	d0,d1
	lea	4(a2),a0
	move.l	d6,d0
	subq.l	#4,d0
	bsr	JH_decrypt
	addq.l	#4,a2			; Nutzlast beginnt hinter der Huelle
	subq.l	#4,d6
	moveq	#1,d3
lf_kein_jh:

	; ---- LOB-Block entpacken ----
	cmp.l	#12,d6
	blo	lf_roh
	cmp.b	#'L',1(a2)
	bne	lf_roh
	cmp.b	#'O',2(a2)
	bne	lf_roh
	cmp.b	#'B',3(a2)
	bne	lf_roh
	move.l	4(a2),d5
	and.l	#$00FFFFFF,d5		; entpackte Groesse
	beq	lf_roh
	move.l	d5,d0			; Puffer wie Show_layout: Groesse plus Zugabe
	add.l	#Default_safety_factor,d0
	bsr	Speicher_anfordern
	tst.l	d0
	beq	lf_rohfrei
	move.w	d0,d4
	bsr	Block_adresse
	move.l	d0,a1
	move.l	a2,a0
	move.l	d6,d0
	bsr	Copy_memory		; gepackten Block hineinkopieren
	move.l	a1,a0
	bsr	Decompress		; an Ort und Stelle
	moveq	#0,d0			; auf die entpackte Groesse verkleinern
	move.w	d4,d0
	move.l	d5,d1
	bsr	Shrink_memory
	moveq	#0,d0
	move.w	d7,d0
	bsr	Free_memory		; Rohdaten weg
	moveq	#0,d0
	move.w	d4,d0
	bra.b	lf_out

lf_roh:
	; Keine Kompression.  Lag eine JH-Huelle davor, ist die Nutzlast um vier
	; Byte versetzt -- dann in einen genau passenden Block umziehen, damit das
	; Handle auf den Anfang der Nutzdaten zeigt und Get_memory_length stimmt.
	tst.w	d3
	beq.b	lf_roh_fertig
	move.l	d6,d0
	bsr	Speicher_anfordern
	tst.l	d0
	beq.b	lf_rohfrei
	move.w	d0,d4
	bsr	Block_adresse
	move.l	d0,a1
	move.l	a2,a0
	move.l	d6,d0
	bsr	Copy_memory
	moveq	#0,d0
	move.w	d7,d0
	bsr	Free_memory
	moveq	#0,d0
	move.w	d4,d0
	bra.b	lf_out
lf_roh_fertig:
	moveq	#0,d0
	move.w	d7,d0			; Rohblock passt schon
	bra.b	lf_out
lf_rohfrei:
	moveq	#0,d0
	move.w	d7,d0
	bsr	Free_memory
lf_fehler:
	moveq	#0,d0
lf_out:
	bsr	Dateiblock		; fuer Kill_unclaimed_memory (MEMORY.S)
	movem.l	(sp)+,d1-d7/a0-a2
	rts

; ***************************************************************************
; Datei_name -- Dateinummer auf einen Dateinamen abbilden.
;
; **Auch diese Tabelle stand in der nicht freigegebenen Bibliothek**: im
; ganzen Originalquelltext kommt kein einziger Dateiname vor, nur die
; rs.b-Aufzaehlung in GAME_OFF.S (Party_data_file ... Object_gfx_file).  Die
; Zuordnung auf die Amberfiles ist also unsere.
;
; GEMDOS will 8.3, deshalb Grossschreibung ohne Sonderzeichen.
;
;   IN : d1 = Dateinummer,  OUT: a0 = Name (null = noch nicht hinterlegt)
;
; **Nummer 0 heisst: der Name steht schon in a0** (der Ordner kommt auch
; dort davor, siehe unten).  So macht es
; die Bibliothek in AM2_CPU 1.20 (Load_file mit d0 = 0, Save_file mit
; d1 = 0 und dem Namen in a1); Get_saved_game und Put_saved_game
; (SPIELSTAND.S) sprechen die Spielstandordner so an.  Thalions Code nennt
; die 0 nie: in seiner Aufzaehlung ist sie "Memory block (NOT A FILE)".
;
; **Der Ordner kommt davor** (Erkenntnis 262): wie AM2_CPU jedem Namen
; "Amberfiles/" voranstellt, setzt Datei_name "AMBFILES\" davor, wenn
; Ordner_suchen den Ordner beim Start gefunden hat.  Der Name steht dann in
; dn_voll und gilt bis zum naechsten Aufruf.  Das Arbeitsverzeichnis bleibt,
; wie es ist: unter TOS gehoert es nicht uns allein.
; ***************************************************************************
Datei_name:
	movem.l	d0-d1/a1,-(sp)
	tst.w	d1
	beq.b	dn_da			; Nummer 0: Name schon in a0
	sub.l	a0,a0
	cmp.w	#DN_MAX,d1
	bcc.b	dn_out
	move.w	d1,d0
	lsl.w	#2,d0
	lea	dn_tabelle,a0
	move.l	0(a0,d0.w),a0
dn_da:
	move.l	a0,d0
	beq.b	dn_out			; kein Name hinterlegt
	tst.b	dn_im_ordner
	beq.b	dn_out
	move.l	a0,d1			; Name merken
	lea	dn_voll,a1
	lea	dn_ordner,a0
dn_ord:	move.b	(a0)+,(a1)+
	bne.b	dn_ord
	subq.l	#1,a1			; Endnull des Ordners ueberschreiben
	move.l	d1,a0
dn_kop:	move.b	(a0)+,(a1)+
	bne.b	dn_kop
	lea	dn_voll,a0
dn_out:
	movem.l	(sp)+,d0-d1/a1
	rts

; ***************************************************************************
; Ordner_suchen -- liegt neben uns der Ordner AMBFILES?  -> dn_im_ordner
;
; Einmal beim Start (MAIN.S).  Der Lader AMBER.TOS startet uns aus dem
; Verzeichnis darueber, dort gibt es ihn.  Startet man ENGINE.TOS vom
; Desktop, ist das Verzeichnis AMBFILES selbst: kein Ordner darunter, kein
; Vorsatz.  Ebenso bei der flachen Ablage (Pruefassung).
;   Alle Register bleiben.
; ***************************************************************************
Ordner_suchen:
	movem.l	d0-d3/a0-a2,-(sp)
	sf	dn_im_ordner
	move.w	#Fgetdta,-(sp)		; alte DTA merken, sie gehoert dem Aufrufer
	Gemdos
	addq.l	#2,sp
	move.l	d0,d3
	pea	ls_dta
	move.w	#Fsetdta,-(sp)
	Gemdos
	addq.l	#6,sp
	move.w	#$10,-(sp)		; auch Ordner
	pea	dn_ordnername
	move.w	#Fsfirst,-(sp)
	Gemdos
	lea	8(sp),sp
	tst.l	d0
	bmi.b	os_zurueck
	btst	#4,ls_dta+21		; Attribut: ist es ein Ordner?
	sne	dn_im_ordner
os_zurueck:
	move.l	d3,-(sp)		; DTA zurueckstellen
	move.w	#Fsetdta,-(sp)
	Gemdos
	addq.l	#6,sp
	movem.l	(sp)+,d0-d3/a0-a2
	rts

; ***************************************************************************
; Decompress -- Thalions Symbol, entpackt einen LOB-Block an Ort und Stelle.
;
; **Die Schnittstelle ist nicht erfunden, sie ist abgelesen.**  Im ganzen
; Originalquelltext gibt es genau eine Aufrufstelle, Show_layout
; (DISPLAY.S:31), und die schreibt den Vertrag vollstaendig hin:
;
;     move.l #(199-Middle_Y)*120+Default_safety_factor,d0
;     jsr Allocate_CHIP          ; Puffer: entpackte Groesse + Zugabe
;     ... Copy_memory ...        ; gepackten Block an den Pufferanfang
;     move.l a1,a0
;     jsr Decompress             ; a0 allein, sonst nichts
;
; Aufbau des Blocks -- an allen 1642 LOB-Bloecken der Spieldaten nachgemessen,
; nachdem die Containerebene aufgeloest ist (AMNC/AMNP/AMPC, siehe
; Load_subfile):
;
;     0      Anzahl Iterationen  -- durchweg 1
;     1..3   "LOB"
;     4..7   entpackte Groesse   -- Byte 4 durchweg 6, Groesse in den
;            unteren 24 Bit
;     8..11  gepackte Rumpflaenge -- ausnahmslos Blocklaenge minus zwoelf
;     12..   der gepackte Rumpf
;
; **Weil die gepackte Laenge im Kopf steht, braucht Decompress sie nicht als
; Parameter** -- genau deshalb genuegt Thalion das eine a0.  (Mein erster
; Anlauf gab Ziel und Rumpfversatz von aussen mit; das war eine eigene
; Architektur statt der vorhandenen.)
;
; In-place: der Rumpf wandert zuerst ans Ende des Puffers, dann wird von dort
; nach vorn entpackt.  So bleibt der Schreibzeiger immer hinter dem
; Lesezeiger -- dafuer ist Default_safety_factor da (vorspann.i).
;
;   IN : a0 = Puffer, der den gepackten Block am Anfang traegt
;   Alle Register werden erhalten.
; ***************************************************************************
Decompress:
	addq.w	#1,Data_change_count	; new data (MEMORY.S, the ST's tile cache)
	movem.l	d0-d2/a0-a3,-(sp)
	cmp.b	#'L',1(a0)		; ueberhaupt ein LOB-Block?
	bne.b	dc_out
	cmp.b	#'O',2(a0)
	bne.b	dc_out
	cmp.b	#'B',3(a0)
	bne.b	dc_out
	move.l	4(a0),d1
	and.l	#$00FFFFFF,d1		; entpackte Groesse (Byte 4 ist Kennung)
	move.l	8(a0),d2		; gepackte Rumpflaenge
	move.l	a0,a3			; Pufferanfang = spaeteres Ziel
	; ---- Rumpf ans Pufferende schieben ----
	move.l	a3,a1
	add.l	d1,a1
	add.l	#Default_safety_factor,a1
	sub.l	d2,a1			; a1 = neuer Rumpfanfang
	move.l	d2,d0
	beq.b	dc_entpacken		; leerer Rumpf
	lea	12(a3),a0		; hinter das alte Rumpfende
	add.l	d2,a0
	move.l	a1,a2			; hinter das neue Rumpfende
	add.l	d2,a2
dc_kop:	move.b	-(a0),-(a2)		; rueckwaerts -- die Bereiche ueberlappen
	subq.l	#1,d0
	bne.b	dc_kop
dc_entpacken:
	move.l	a1,a0			; Quelle: der verschobene Rumpf
	move.l	a3,a1			; Ziel:   der Pufferanfang
	move.l	d1,d0			; entpackte Groesse
	bsr	LOB_decompress
dc_out:
	movem.l	(sp)+,d0-d2/a0-a3
	rts

; ***************************************************************************
; Die Dateinamen-Tabelle, in der Reihenfolge der rs.b-Aufzaehlung aus
; Thalions GAME_OFF.S (Party_data_file = 0 ... Object_gfx_file = 43).
;
; **Achtung 8.3.**  Etliche Amberfiles heissen laenger, als ein FAT-Dateisystem
; traegt -- "Portraits.amb" hat neun Zeichen vor dem Punkt, "Combat_background.amb"
; siebzehn.  Fuer die Hardware muessen sie umbenannt werden; die Tabelle hier
; ist die eine Stelle, an der das steht.  "Layouts.amb" passt mit sieben.
;
; Gefuellt wird nach und nach -- was null ist, laedt (noch) nicht.
; ***************************************************************************
	SECTION	Fast_DATA,data
	even
; **Die Zaehlung beginnt bei eins, nicht bei null.**  Vor Party_data_file
; steht in Thalions rsreset-Block ein unbenannter Eintrag, den er selbst
; kommentiert:
;
;     rsreset
;     rs.b 1              ; Memory block (NOT A FILE)
;     Party_data_file:	rs.b 1
;
; Damit ist Layout_file 24 und nicht 23.  Wer hier um eins danebenliegt, holt
; stillschweigend die falsche Datei -- meine erste Fassung lieferte dadurch
; einen Nullzeiger.
dn_tabelle:
	dc.l	0			;  0 Memory block -- keine Datei
	dc.l	dn_pdata,dn_pchar,dn_npcchar,dn_monchar	;  1 Party_data, Party_char, NPC_char, Monster_char
	dc.l	dn_portrait,dn_mapdat1,dn_icondat,dn_icongfx1 ;  5 Portraits, Map_data, Icon_data, Icon_gfx
	dc.l	dn_travelgf,dn_npcgfx,dn_labdat2,dn_wall2	;  9 Trans_gfx, NPC_gfx, Lab_data, Wall_3D_CHIP
	dc.l	dn_labback,dn_pics80,dn_maptxt1,dn_chest	; 13 Lab_background, Pic80x80, Map_text, Chest_data
	dc.l	dn_monstgrp,dn_merchant,dn_combatbg,dn_monstgfx	; 17 Monster_data, Merchant_data, Combat_bg, Monster_gfx
	dc.l	dn_automap,dn_objtexts,dn_eventpix	; 21 Automap, Object_texts, Event_pix
	dc.l	dn_layouts		; 24 Layout_file
	dc.l	dn_music,dn_palettes,dn_rmgfx,dn_dict	; 25 Music, Palette, RM_gfx, Dictionary
	dc.l	dn_obj2,dn_ovl2,dn_wall2,0	; 29 Object_3D_CHIP, Overlay_3D, Wall_3D_FAST, Zoombuffer
	dc.l	dn_obj2,dn_saves,dn_partytxt,dn_npctext	; 33 Object_3D_FAST, Saves, Party_text, NPC_text
	dc.l	dn_automapg,dn_placedat,dn_combgfx,dn_floors	; 37 Automap_gfx, Place_data, Combat_gfx, Floor
	dc.l	dn_babychar,dn_stationr,dn_partygfx,dn_objicons	; 41 Baby_char, Stationary, Party_gfx, Object_gfx
; **Ab hier endet Thalions Aufzaehlung.**  Button_graphics steht in keiner
; seiner rs.b-Zeilen -- im Original fuellt die nicht freigegebene Bibliothek
; Control_icons daraus, und die haben wir nicht (Erkenntnis 131).  Die Nummer
; 45 ist deshalb unsere Erweiterung; sie steht in FALCON_OFF.S.
	dc.l	dn_btngfx		; 45 Button_graphics (unsere Nummer)
	dc.l	dn_text,dn_objects	; 46 Text.amb, 47 Objects.amb (unsere)
; Teil 2 und 3 der Karten und Kartentexte (Teildatei_waehlen).  Thalions
; Code nennt diese Nummern nie, nur die Bibliothek.
	dc.l	dn_mapdat2,dn_mapdat3	; 48, 49
	dc.l	dn_maptxt2,dn_maptxt3	; 50, 51
; Teil 2 und 3 der Kachelgrafik (Teildatei_waehlen), seit Stufe (c).
	dc.l	dn_icongfx2,dn_icongfx3	; 52, 53
; Teil 3 der 3D-Dateien (Teildatei_waehlen), seit Plan E.  Teil 2 steht
; unter Thalions Nummer; CHIP und FAST sind dieselbe Datei (Blitter_or_CPU
; waehlt im Original nur die Speicherart).
	dc.l	dn_labdat3,dn_wall3,dn_obj3,dn_ovl3	; 54-57
; Thalions deutsche Tastenbelegung (Erkenntnis 260).  Im Original richtet sie
; die Installation im System ein, und Thalions Read_key holt das Zeichen
; daraus; bei uns liest Read_key sie selbst.
	dc.l	dn_keymap		; 58
DN_MAX	equ	59
Keymap_file	equ	58
Lab_data3_file	equ	54
Wall_3D3_file	equ	55
Object_3D3_file	equ	56
Overlay_3D3_file	equ	57
Icon_gfx2_file	equ	52
Icon_gfx3_file	equ	53
Map_data2_file	equ	48
Map_data3_file	equ	49
Map_text2_file	equ	50
Map_text3_file	equ	51

dn_layouts:	dc.b	"LAYOUTS.AMB",0
	even
; Die 3D-Dateien (Plan E), alle AMNP.  2/3Lab_data und 2/3Overlay3D sind
; byteweise gleich, 2/3Wall3D und 2/3Object3D nicht (Erkenntnis 197).
dn_labdat2:	dc.b	"LABDATA2.AMB",0		; 2Lab_data.amb
	even
dn_labdat3:	dc.b	"LABDATA3.AMB",0		; 3Lab_data.amb
	even
dn_wall2:	dc.b	"WALL3D2.AMB",0		; 2Wall3D.amb
	even
dn_wall3:	dc.b	"WALL3D3.AMB",0		; 3Wall3D.amb
	even
dn_obj2:	dc.b	"OBJ3D2.AMB",0		; 2Object3D.amb
	even
dn_obj3:	dc.b	"OBJ3D3.AMB",0		; 3Object3D.amb
	even
dn_ovl2:	dc.b	"OVL3D2.AMB",0		; 2Overlay3D.amb
	even
dn_ovl3:	dc.b	"OVL3D3.AMB",0		; 3Overlay3D.amb
	even
dn_labback:	dc.b	"LABBACK.AMB",0		; Lab_background.amb
	even
dn_floors:	dc.b	"FLOORS.AMB",0		; Floors.amb
	even
; Diese drei heissen im Original laenger, als 8.3 traegt -- sie werden beim
; Ausliefern umbenannt (tools/baue_alles.sh).  Genau dafuer ist diese Tabelle
; die eine Stelle.
dn_dict:	dc.b	"DICT.AMB",0		; Dict.amb, JH-Huelle
	even
dn_automapg:	dc.b	"AUTOMAPG.DAT",0		; Automap_graphics, LOB-Block
	even
dn_rmgfx:	dc.b	"RIDDLEGF.DAT",0		; Riddlemouth_graphics, LOB-Block
	even
dn_objicons:	dc.b	"OBJICONS.DAT",0		; Object_icons, JH-Huelle
	even
dn_btngfx:	dc.b	"BUTTONGF.DAT",0		; Button_graphics, JH+LOB
	even
dn_keymap:	dc.b	"KEYMAP",0		; Keymap, Amiga-Hunkdatei, roh
	even
dn_text:	dc.b	"TEXT.AMB",0		; Text.amb, JH+LOB
	even
dn_objects:	dc.b	"OBJECTS.AMB",0		; Objects.amb, JH+LOB
	even
dn_mapdat1:	dc.b	"MAPDATA1.AMB",0		; 1Map_data.amb, AMNP
	even
dn_mapdat2:	dc.b	"MAPDATA2.AMB",0		; 2Map_data.amb, AMPC (1.20)
	even
dn_mapdat3:	dc.b	"MAPDATA3.AMB",0		; 3Map_data.amb, AMPC (1.20)
	even
dn_maptxt1:	dc.b	"MAPTEXT1.AMB",0		; 1Map_texts.amb, AMNP
	even
dn_maptxt2:	dc.b	"MAPTEXT2.AMB",0		; 2Map_texts.amb, AMNP
	even
dn_maptxt3:	dc.b	"MAPTEXT3.AMB",0		; 3Map_texts.amb, AMNP
	even
dn_icondat:	dc.b	"ICONDATA.AMB",0		; Icon_data.amb
	even
dn_pics80:	dc.b	"PICS80.AMB",0		; Pics_80x80.amb
	even
dn_eventpix:	dc.b	"EVENTPIX.AMB",0		; Event_pix.amb
	even
dn_palettes:	dc.b	"PALETTES.AMB",0		; Palettes.amb
	even
dn_music:	dc.b	"MUSIC.AMB",0		; Music.amb, AMNP, 32 Stuecke (docs/13)
	even
; Seit Stufe (c): was Thalions Start- und Kartenweg zusaetzlich liest.
dn_npcchar:	dc.b	"NPCCHAR.AMB",0		; NPC_char.amb
	even
dn_monchar:	dc.b	"MONSTCHR.AMB",0		; Monster_char.amb
	even
dn_portrait:	dc.b	"PORTRAIT.AMB",0		; Portraits.amb, AMNC
	even
dn_icongfx1:	dc.b	"ICONGFX1.AMB",0		; 1Icon_gfx.amb
	even
dn_icongfx2:	dc.b	"ICONGFX2.AMB",0		; 2Icon_gfx.amb
	even
dn_icongfx3:	dc.b	"ICONGFX3.AMB",0		; 3Icon_gfx.amb
	even
dn_travelgf:	dc.b	"TRAVELGF.AMB",0		; Travel_gfx.amb
	even
dn_npcgfx:	dc.b	"NPCGFX.AMB",0		; NPC_gfx.amb
	even
dn_objtexts:	dc.b	"OBJTEXTS.AMB",0		; Object_texts.amb
	even
dn_partytxt:	dc.b	"PARTYTXT.AMB",0		; Party_texts.amb
	even
dn_npctext:	dc.b	"NPCTEXT.AMB",0		; NPC_texts.amb
	even
dn_placedat:	dc.b	"PLACEDAT.DAT",0		; Place_data
	even
dn_stationr:	dc.b	"STATIONR.DAT",0		; Stationary
	even
dn_partygfx:	dc.b	"PARTYGFX.AMB",0		; Party_gfx.amb
	even
; Kampf (COMBAT.S Combat_ModInit): Monstergruppe, Hintergrund und
; Monsterbilder ueber Load_subfile, die Kampfgrafik (Taktiksymbole,
; Effekte; FXGFX_handle) als ganze Datei ueber Load_file.
dn_monstgrp:	dc.b	"MONSTGRP.AMB",0		; Monster_groups.amb, AMNP
	even
dn_combatbg:	dc.b	"COMBATBG.AMB",0		; Combat_background.amb, AMNP
	even
dn_monstgfx:	dc.b	"MONSTGFX.AMB",0		; Monster_gfx.amb, AMNP
	even
dn_combgfx:	dc.b	"COMBATGF.DAT",0		; Combat_graphics, JH+LOB
	even
; **Spielstand, nicht statische Daten.**  Die fuenf Arbeitsdateien unten
; liegen wie im Original im Hauptverzeichnis; Get_saved_game fuellt sie aus
; SAVE.nn\, Put_saved_game legt sie dort ab (SPIELSTAND.S).
; **Saves ist eine erzeugte Kopie** (baue_alles.sh, Nutzer 2026-09-27): im
; Original steht dort "letzter Spielstand 0", und Thalions Init_program legte
; dann den Charaktereditor auf.  Die Kopie traegt 1.
dn_saves:	dc.b	"SAVES",0
	even
dn_merchant:	dc.b	"MERCHANT.AMB",0		; Merchant_data.amb
	even
dn_automap:	dc.b	"AUTOMAP.AMB",0		; Automap.amb
	even
dn_chest:	dc.b	"CHESTDAT.AMB",0		; Chest_data.amb, AMBR
	even
dn_pdata:	dc.b	"PARTYDAT.SAV",0		; Party_data.sav, roh
	even
dn_pchar:	dc.b	"PARTYCHR.AMB",0		; Party_char.amb, AMBR
; Baby_char_file: der Held, den der Charaktereditor aendert (Chared_ModExit:
; Save_subfile 1), steht im Stand "Neues Spiel".  AM2_CPU nennt ihn
; Save.00/Party_char.amb (Namenstabelle 4:$79B0, Eintrag 41 -> 4:$7CD0).
; Eine eigene Zeichenkette: sp_pchar in SPIELSTAND.S bekommt die Ziffern
; des jeweiligen Platzes eingesetzt.
dn_babychar:	dc.b	"SAVE.00\\PARTYCHR.AMB",0
; Der Ordner mit Spieldaten und Spielstaenden, wie Amberfiles im Original
; (Erkenntnis 262).  Einmal mit, einmal ohne Trenner.
dn_ordner:	dc.b	"AMBFILES\\",0
dn_ordnername:	dc.b	"AMBFILES",0
	even

	SECTION	Fast_BSS,bss
	even
pe_videl:	ds.l	256		; Auszug der VIDEL-Farbregister
pe_hdl:		ds.b	8		; Handles der beiden Batch-Laeufe
	even
pe_stat:	ds.l	8 		; Zwischenwerte des Selbsttests
ls_fhandle:	ds.w	1		; GEMDOS-Dateihandle waehrend des Lesens
ls_offen:	ds.w	1		; offener Behaelter (Close_current_file), 0 = keiner
ls_kopf:	ds.b	6		; Kennung und Anzahl (Eintrag_suchen)
ls_laengen:	ds.l	ES_STUECK	; ein Stueck der Laengentabelle
ls_dta:		ds.b	44		; Verzeichniseintrag fuer Fsfirst
dn_voll:	ds.b	64		; Ordner + Name (Datei_name)
dn_im_ordner:	ds.b	1		; AMBFILES gefunden (Ordner_suchen)
	even
	SECTION	Program,code

	IFD	ENTPACKPRUEF
; ***************************************************************************
; Pruefe_entpacker -- Selbsttest der ganzen Kette (Stufe B).
;
; Holt Eintrag 11 aus Layouts.amb **genau so, wie Show_layout es tut** --
; Load_subfile, Puffer mit Zugabe, Copy_memory, Decompress -- und schreibt das
; Ergebnis als LAYOUT.BIN.  Auf dem Host laesst es sich Byte fuer Byte gegen
; tools/ambtool.py halten.  Nur mit -DENTPACKPRUEF=1 uebersetzt.
; ***************************************************************************
Pruefe_entpacker:
	movem.l	d0-d7/a0-a3,-(sp)

	; ---- erst den Container allein, damit sich Datei und Eintrag trennen lassen
	moveq	#Layout_file,d1
	bsr	Datei_lesen		; d0 = Handle, d1 = Laenge
	move.l	d1,pe_stat+0		; Containerlaenge (0 = Datei nicht gelesen)
	tst.l	d0
	beq	pe_status_raus
	move.l	d0,d7
	bsr	Block_adresse
	move.l	d0,a1
	moveq	#0,d0
	move.w	4(a1),d0
	move.l	d0,pe_stat+4		; Anzahl der Eintraege
	move.l	(a1),pe_stat+8		; Containerkennung
	move.l	d7,d0
	bsr	Free_memory

	moveq	#11,d0			; Eintrag 11
	moveq	#Layout_file,d1
	bsr	Load_subfile
	move.l	d0,pe_stat+12		; Handle (0 = fehlgeschlagen)
	tst.l	d0
	beq.b	pe_status_raus
	move.w	d0,d7			; Handle des gepackten Blocks
	bsr	Block_adresse
	move.l	d0,a2
	move.l	(a2),pe_stat+16		; LOB-Kopf: Magic
	move.l	4(a2),pe_stat+20	; entpackte Groesse
	move.l	8(a2),pe_stat+24	; gepackte Laenge
	moveq	#0,d0
	move.w	d7,d0
	bsr	Get_memory_length
	move.l	d0,pe_stat+28		; Blocklaenge
	bra.b	pe_weiter
pe_status_raus:
	lea	pe_stat,a0
	moveq	#32,d0
	lea	pe_sname,a1
	bsr	Datei_schreiben
	bra	pe_out
pe_weiter:
	lea	pe_stat,a0
	moveq	#32,d0
	lea	pe_sname,a1
	bsr	Datei_schreiben
	moveq	#0,d0
	move.w	d7,d0			; Handle wieder herstellen
	bsr	Block_adresse
	move.l	d0,a2			; a2 = gepackter Block
	move.l	4(a2),d6
	and.l	#$00FFFFFF,d6		; entpackte Groesse aus dem LOB-Kopf

	; Puffer wie Show_layout: entpackte Groesse plus Sicherheitszugabe
	move.l	d6,d0
	add.l	#Default_safety_factor,d0
	bsr	Speicher_anfordern
	tst.l	d0
	beq	pe_out
	bsr	Block_adresse
	move.l	d0,a3			; a3 = Puffer

	; gepackten Block hineinkopieren -- Laenge ueber das Handle, wie im Original
	moveq	#0,d0
	move.w	d7,d0
	bsr	Get_memory_length
	move.l	a2,a0
	move.l	a3,a1
	bsr	Copy_memory

	move.l	a3,a0
	bsr	Decompress		; an Ort und Stelle

	move.l	a3,a0
	move.l	d6,d0
	lea	pe_name,a1
	bsr	Datei_schreiben

	; ---- Load_file, JH-Huelle: Dict.amb ----
	moveq	#Dictionary_file,d0
	bsr	Load_file
	tst.l	d0
	beq.b	pe_kein_dict
	move.w	d0,d7
	bsr	Block_adresse
	move.l	d0,a2
	moveq	#0,d0
	move.w	d7,d0
	bsr	Get_memory_length
	move.l	a2,a0
	lea	pe_dname,a1
	bsr	Datei_schreiben
pe_kein_dict:

	; ---- Load_file, LOB-Block: Automap_graphics ----
	moveq	#Automap_gfx_file,d0
	bsr	Load_file
	tst.l	d0
	beq	pe_out
	move.w	d0,d7
	bsr	Block_adresse
	move.l	d0,a2
	moveq	#0,d0
	move.w	d7,d0
	bsr	Get_memory_length
	move.l	a2,a0
	lea	pe_aname,a1
	bsr	Datei_schreiben

	; ---- Save_subfile: Truhe 1 laden, Gold setzen, zurueckschreiben ----
	moveq	#1,d0
	moveq	#Chest_data_file,d1
	bsr	Load_subfile
	tst.l	d0
	beq	pe_out
	move.w	d0,d7
	bsr	Block_adresse
	move.l	d0,a2
	move.w	#$1234,CH_GOLD(a2)	; erkennbarer Wert
	move.l	a2,a0
	moveq	#1,d0
	moveq	#Chest_data_file,d1
	bsr	Save_subfile

	; ---- Batch-Laden, Liste mit Wiederholung: 1, 3, 1 ----
	lea	pe_batch,a0
	lea	pe_hdl,a1
	moveq	#3,d0
	moveq	#Chest_data_file,d1
	bsr	Load_batch_of_subfiles
	lea	pe_batch,a0
	lea	pe_hdl+4,a1
	moveq	#3,d0
	moveq	#Chest_data_file,d1
	bsr	Load_batch_of_unique_subfiles
	lea	pe_hdl,a0
	moveq	#8,d0
	lea	pe_bname,a1
	bsr	Datei_schreiben

	; ---- die Objektsymbole ausgeben (Originalformat, fuenf Ebenen) ----
	moveq	#0,d0
	move.b	Object_gfx_handle,d0
	beq	pe_out
	move.w	d0,d7
	bsr	Block_adresse
	move.l	d0,a2
	moveq	#0,d0
	move.w	d7,d0
	bsr	Get_memory_length
	move.l	a2,a0
	lea	pe_iname,a1
	bsr	Datei_schreiben

	; ---- VIDEL-Farbregister auslesen (Format bestimmen) ----
	; VsetRGB hat die Palette gesetzt; wie sie im Register steht, laesst sich
	; nur durch Nachsehen klaeren -- aus einem Rasterinterrupt heraus muss
	; direkt geschrieben werden, XBIOS ist dort verboten.
	lea	$FFFF9800,a0
	lea	pe_videl,a1
	move.w	#256-1,d0
pe_vkop:
	move.l	(a0)+,(a1)+
	dbf	d0,pe_vkop
	lea	pe_videl,a0
	move.l	#256*4,d0
	lea	pe_vname,a1
	bsr	Datei_schreiben
pe_out:
	movem.l	(sp)+,d0-d7/a0-a3
	rts

; a0 = Daten, d0 = Laenge, a1 = Dateiname
Datei_schreiben:
	movem.l	d0-d2/a0-a1,-(sp)
	move.l	d0,d2
	clr.w	-(sp)
	move.l	a1,-(sp)
	move.w	#Fcreate,-(sp)
	Gemdos
	lea	8(sp),sp
	tst.l	d0
	bmi.b	ds_out
	move.w	d0,d1
	move.l	a0,-(sp)		; Puffer zuerst, dann Laenge
	move.l	d2,-(sp)
	move.w	d1,-(sp)
	move.w	#Fwrite,-(sp)
	Gemdos
	lea	12(sp),sp
	move.w	d1,-(sp)
	move.w	#Fclose,-(sp)
	Gemdos
	addq.l	#4,sp
ds_out:
	movem.l	(sp)+,d0-d2/a0-a1
	rts

	SECTION	Fast_DATA,data
pe_name:	dc.b	"LAYOUT.BIN",0
	even
pe_sname:	dc.b	"EPSTAT.BIN",0
	even
pe_dname:	dc.b	"DICT.BIN",0
	even
pe_aname:	dc.b	"AMAP.BIN",0
	even
pe_bname:	dc.b	"BATCH.BIN",0
	even
pe_iname:	dc.b	"ICONS.BIN",0
	even
pe_vname:	dc.b	"VIDELPAL.BIN",0
	even
pe_batch:	dc.w	1,3,1		; absichtlich mit Wiederholung
	even
	SECTION	Program,code
	ENDC

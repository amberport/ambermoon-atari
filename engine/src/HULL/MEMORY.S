; HULL/MEMORY.S -- der Speicherverwalter
;
; Entspricht dem Speicherteil von Thalions Bibliothek.  Die Datei selbst ist
; nicht freigegeben; ihre Schnittstelle steht in den Aufrufstellen, und die
; sind eindeutig.  Create_string_graphics (HULL/CONTROLS.S) benutzt sie
; vollstaendig und in einem Stueck:
;
;     jsr	Allocate_CHIP		; d0 = Groesse -> d0 = Handle
;     move.b	d0,d4
;     move.l	#...,d0
;     jsr	Allocate_CHIP
;     jsr	Clear_memory		; d0 = Handle
;     move.w	d0,-(sp)
;     jsr	Claim_pointer		; d0 = Handle -> d0 = Adresse
;     ...
;     Get	d4,a0			; = Claim_pointer nach a0
;     jsr	Get_block
;     Free	d4			; = Free_pointer
;     ...
;     jsr	Free_pointer
;     jsr	Free_memory
;
; **Handles, keine Zeiger.**  Das ist der wichtigste Punkt und kein Zufall:
; auf dem Amiga durfte die Bibliothek einen nicht festgenagelten Block
; verschieben, um Luecken zu schliessen.  Claim_pointer nagelt fest und
; liefert die Adresse, Free_pointer gibt wieder frei.  Ueber hundert
; Aufrufstellen im Originalquelltext arbeiten so; wer das mit rohen Zeigern
; nachbaut, muss sie alle anfassen.
;
; **Bei uns verschiebt nichts.**  Ein Handle zeigt sein Leben lang auf
; dieselbe Adresse.  Die Handles bleiben trotzdem, weil die Aufrufstellen sie
; fuehren -- und weil ein spaeterer Verdichter genau hier hineinpasst, ohne
; dass eine einzige Aufrufstelle sich aendert.
;
; **Gezaehlt wird trotzdem, wie im Original** (Erkenntnis 267): Claim_pointer
; zaehlt hoch, Free_pointer herunter (AM2_CPU 0:$24B30/$24B6E, Byte 19 des
; Blockkopfs, bei 255 bleibt er stehen).  Davon lebt Kill_unclaimed_memory,
; das Out_of_memory ruft.  **Unsere eigene Schicht zaehlt nicht mit**: sie
; holt Adressen ueber Block_adresse.  Sonst trueg jeder Block, den
; Load_subfile an Thalion gibt, einen Zaehler, den niemand mehr abbaut.
;
; Ein Handle ist eine Zahl ab eins; null heisst "keins".  Das Original
; nimmt dafuer ein Byte ("OUT : d0 - Memory handle (.b)") und vergibt
; hoechstens 199: Invalidate_memory in AM2_CPU uebergeht alles ab 200
; (Erkenntnis 196).  Ein 3D-Raum allein braucht bis zu 32 Waende
; (Max_3D_walls) und 64 Objekte (Max_3D_objects), dazu seine Puffer; die
; frueheren 32 Handles reichten dafuer nicht.

MEM_MAX  = 199			; gleichzeitig vergebene Handles
MEM_ADR  = 0			; .l Adresse, ausgerichtet
MEM_ROH  = 4			; .l Adresse, wie Mxalloc sie gab
MEM_LEN  = 8			; .l angeforderte Laenge
MEM_ZAHL = 12			; .b wie oft festgehalten (Claim_pointer)
MEM_ART  = 13			; .b 1: Dateiblock (Load_file, Load_subfile)
MEM_SZ   = 16

; ***************************************************************************
; Allocate_CHIP, Allocate_FAST, Allocate_memory -- request memory, get a
; handle.
;   IN : d0.l = size in bytes
;   OUT: d0 = handle (1 to MEM_MAX).  Without memory they do not return
;        (below).
;   All other registers are preserved.
;
; Allocate_CHIP, Allocate_FAST und Allocate_memory sind hier dasselbe.  Auf
; dem Amiga trennte das Chip- von Fast-RAM: was der Grafikchip lesen muss,
; gehoert ins Chip-RAM.  Auf dem Falcon gilt dasselbe mit anderen Namen --
; VIDEL liest nur ST-RAM --, deshalb Mxalloc mit Modus 0.
;
; **Ohne Speicher kehren Thalions Namen nicht zurueck**, wie im Original:
; dort springt der Speicherverwalter nach Out_of_memory (0:$240D8 "jmp
; Out_of_memory", Thalions DIAGNOST.S).  Das zeigt einen Hinweis, sichert
; die Gruppe und startet neu (Restart_game).  Thalions Aufrufer pruefen das
; Handle nie; mit 0 kopierte Show_layout das Layout nach Adresse 0
; (Erkenntnis 182).
;
; **Out_of_memory gibt es nur einmal und erst im Spiel** (Notweg): vor
; Init_program stuende in Party_data nichts, und Out_of_memory schriebe das
; als Spielstand.  Und waehrend Out_of_memory laeuft, darf es sich nicht
; selbst wieder rufen.  Ohne Notweg geht es nach Speicher_voll (MAIN.S,
; Meldung auf dem TOS-Schirm, Ende).  Restart_game oeffnet ihn wieder, wenn
; Init_program durch ist.
;
; **Speicher_anfordern ist der Weg unserer eigenen Schicht** (FILES_SUP.S,
; SPIELSTAND.S): ohne Notweg kommt 0 zurueck, und der Aufrufer weicht aus.
; Waehrend Out_of_memory die Gruppe sichert, muss Save_subfile so weiter
; koennen.  Speicher_holen ist die Anforderung selbst.
; ***************************************************************************
Allocate_CHIP:
Allocate_FAST:
Allocate_memory:
	bsr.b	Speicher_holen
	tst.l	d0
	beq.b	am_fehlt
	rts
am_fehlt:
	tst.b	Notweg
	beq.b	am_voll
	sf	Notweg			; nur einmal
	jsr	Close_current_file	; Eintrag_lesen may have a container open
	jmp	Out_of_memory		; Thalions, DIAGNOST.S
am_voll:
	jmp	Speicher_voll

Speicher_anfordern:
	bsr.b	Speicher_holen
	tst.l	d0
	bne.b	san_out
	tst.b	Notweg
	beq.b	san_out			; kein Notweg: 0 zurueck
	sf	Notweg
	jsr	Close_current_file	; Eintrag_lesen may have a container open
	jmp	Out_of_memory
san_out:
	rts

; Diagnoseschalter SPEICHERTEST=n (VASM_EXTRA="-DSPEICHERTEST=5"): die n-te
; Anforderung, nachdem Init_program durch ist, schlaegt einmal fehl.  So
; laesst sich Out_of_memory pruefen.  Speichertest_zaehler stellt
; Restart_game einmal auf n.
Speicher_holen:
	IFD	SPEICHERTEST
	tst.w	Speichertest_zaehler
	beq.b	sh_echt
	subq.w	#1,Speichertest_zaehler
	bne.b	sh_echt
	moveq	#0,d0			; diesmal nicht
	rts
sh_echt:
	ENDC
	movem.l	d1-d2/a0-a1,-(sp)
	move.l	d0,d2			; Laenge merken
	; Einen freien Platz in der Tabelle suchen
	lea	memtab,a0
	moveq	#0,d1
am_such:
	tst.l	MEM_ADR(a0)
	beq.b	am_frei
	lea	MEM_SZ(a0),a0
	addq.w	#1,d1
	cmp.w	#MEM_MAX,d1
	blo.b	am_such
	moveq	#0,d0			; kein Platz mehr
	bra.b	am_out
am_frei:
	; 256 Byte Zugabe wie beim Bildschirmspeicher: manches, was hier
	; angefordert wird, wird spaeter Videobasis, und die will auf einer
	; 256-Byte-Grenze stehen.
	move.w	#0,-(sp)		; Modus 0 = ST-RAM
	move.l	d2,-(sp)
	add.l	#256,(sp)
	move.w	#Mxalloc,-(sp)
	Gemdos
	lea	8(sp),sp
	tst.l	d0
	bne.b	am_hat
	moveq	#0,d0			; kein Speicher
	bra.b	am_out
am_hat:
	addq.w	#1,Data_change_count	; new memory (the ST's tile cache)
	move.l	d0,MEM_ROH(a0)		; zum Freigeben
	add.l	#255,d0
	and.l	#-256,d0
	move.l	d0,MEM_ADR(a0)
	move.l	d2,MEM_LEN(a0)
	clr.w	MEM_ZAHL(a0)		; Zaehler und Art
	moveq	#0,d0			; oberes Wort raeumen -- trap #1 laesst
	move.w	d1,d0			;  dort den Rest der Adresse stehen
	addq.w	#1,d0			; Handles zaehlen ab eins
am_out:
	movem.l	(sp)+,d1-d2/a0-a1
	rts

; ***************************************************************************
; Handle -> Tabelleneintrag in a0.  Z gesetzt, wenn das Handle nichts taugt.
; ***************************************************************************
Mem_eintrag:
	movem.l	d1,-(sp)
	move.w	d0,d1
	and.w	#$FF,d1			; das Original fuehrt ein Byte
	beq.b	me_nix
	subq.w	#1,d1
	cmp.w	#MEM_MAX,d1
	bcc.b	me_nix
	mulu.w	#MEM_SZ,d1
	lea	memtab,a0
	add.l	d1,a0
	tst.l	MEM_ADR(a0)		; belegt?  setzt Z, wenn nicht
	movem.l	(sp)+,d1
	rts
me_nix:
	sub.l	a0,a0
	moveq	#0,d1			; Z setzen
	tst.w	d1
	movem.l	(sp)+,d1
	rts

; ***************************************************************************
; Claim_pointer -- the address of a handle; counts the claim up.
;   IN : d0.b = handle
;   OUT: d0.l = address, 0 if the handle is not in use
;   All other registers are preserved.
;
; Zaehlt hoch, bei 255 nicht weiter (0:$24B30).
;
; Block_adresse -- dasselbe ohne Zaehlen, fuer unsere eigene Schicht.
; ***************************************************************************
Claim_pointer:
	move.l	a0,-(sp)
	bsr	Mem_eintrag
	beq.b	cp_nix
	addq.b	#1,MEM_ZAHL(a0)
	bcc.b	cp_zaehlt
	st	MEM_ZAHL(a0)		; uebergelaufen: bei 255 bleiben
cp_zaehlt:
	MEM_ADDRESS			; the ST: its recoloured copy (vorspann.i)
	move.l	(sp)+,a0
	rts
cp_adr:	move.l	MEM_ADR(a0),d0
	move.l	(sp)+,a0
	rts
cp_nix:
	moveq	#0,d0
	move.l	(sp)+,a0
	rts

Block_adresse:
	move.l	a0,-(sp)
	bsr	Mem_eintrag
	beq.b	cp_nix
	bra.b	cp_adr

; ***************************************************************************
; Free_pointer -- let go of a claimed handle; counts the claim down, not
; below zero (0:$24B6E).
;   IN : d0.b = handle
;   All registers are preserved.
; ***************************************************************************
Free_pointer:
	move.l	a0,-(sp)
	bsr	Mem_eintrag
	beq.b	fp_out
	tst.b	MEM_ZAHL(a0)
	beq.b	fp_out
	subq.b	#1,MEM_ZAHL(a0)
fp_out:	move.l	(sp)+,a0
	rts

; ***************************************************************************
; Dateiblock -- ein Handle als Dateiblock kennzeichnen.  d0 = Handle (0
; geht).  Load_file und Load_subfile rufen es fuer das, was sie Thalion
; geben.  Im Original traegt der Blockkopf dafuer Dateiart und Nummer
; (Byte 20, Reallocate_memory).  Alle Register bleiben.
; ***************************************************************************
Dateiblock:
	move.l	a0,-(sp)
	bsr	Mem_eintrag
	beq.b	db_out
	move.b	#1,MEM_ART(a0)
db_out:	move.l	(sp)+,a0
	rts

; ***************************************************************************
; Clear_all_claims -- set every claim counter to zero (0:$23D9E).
; Thalion's Push_Module calls it when the module below is global
; ("safety").
;   All registers are preserved.
; ***************************************************************************
Clear_all_claims:
	movem.l	d0/a0,-(sp)
	lea	memtab,a0
	move.w	#MEM_MAX-1,d0
cac_l:	clr.b	MEM_ZAHL(a0)
	lea	MEM_SZ(a0),a0
	dbf	d0,cac_l
	movem.l	(sp)+,d0/a0
	rts

; ***************************************************************************
; Kill_unclaimed_memory -- jeden Dateiblock freigeben, den niemand festhaelt
; (0:$23D06).  Nur Out_of_memory ruft es, vor dem Sichern der Gruppe.
;
; Das Original geht durch seine Bloecke und gibt die frei, die eine Datei
; tragen (Byte 20) und keinen Zaehler haben (Byte 19).  Bei uns tragen das
; MEM_ART und MEM_ZAHL.  Alle Register bleiben.  (Until 2026-10-21 it also
; emptied our container cache, Cache_verwerfen; Load_subfile has none now.)
; ***************************************************************************
Kill_unclaimed_memory:
	movem.l	d0-d1/a0,-(sp)
	MEM_KILL_HOOK			; the ST: its copies go (vorspann.i)
	lea	memtab,a0
	moveq	#1,d0			; Handle
kum_l:	tst.l	MEM_ROH(a0)		; belegt und echt angefordert?
	beq.b	kum_weiter
	tst.b	MEM_ART(a0)
	beq.b	kum_weiter
	tst.b	MEM_ZAHL(a0)
	bne.b	kum_weiter
	bsr	Free_memory		; d0 = Handle
kum_weiter:
	lea	MEM_SZ(a0),a0
	addq.w	#1,d0
	cmp.w	#MEM_MAX,d0
	bls.b	kum_l
	movem.l	(sp)+,d0-d1/a0
	rts

; ***************************************************************************
; Create_fake_handle -- wrap memory that is not ours in a handle.
;   IN : a0 = the graphic in memory
;   OUT: d0 = handle, 0 if no slot was free
;   All other registers are preserved.
;
; Das Original wickelt damit rohe Grafikzeiger in Handles, ohne Speicher
; anzufordern: der fliegende Adler (ACTIONS.S) und die Aufloeseffekte
; (EFFECTS.S) haengen so ein festes Bild an einen HDOB, und HDOBS.S kommt an
; die Adresse ueber Claim_pointer wie bei jedem echten Handle.
;
; Der Eintrag traegt MEM_ROH = 0 -- daran erkennen Destroy_fake_handle und
; Free_memory, dass nichts freizugeben ist (Kill_all_memory raeumt beim
; Neustart auch solche Eintraege ab).
; ***************************************************************************
Create_fake_handle:
	movem.l	d1/a1,-(sp)
	lea	memtab,a1
	moveq	#0,d1
cfh_such:
	tst.l	MEM_ADR(a1)
	beq.b	cfh_frei
	lea	MEM_SZ(a1),a1
	addq.w	#1,d1
	cmp.w	#MEM_MAX,d1
	blo.b	cfh_such
	moveq	#0,d0			; kein Platz
	bra.b	cfh_out
cfh_frei:
	move.l	a0,MEM_ADR(a1)		; die Grafik selbst
	clr.l	MEM_ROH(a1)		; nichts anzufordern -> nichts freizugeben
	clr.l	MEM_LEN(a1)
	clr.w	MEM_ZAHL(a1)
	moveq	#0,d0
	move.w	d1,d0
	addq.w	#1,d0			; Handles zaehlen ab eins
cfh_out:
	movem.l	(sp)+,d1/a1
	rts

; ***************************************************************************
; Destroy_fake_handle -- remove a handle made by Create_fake_handle.
;   IN : d0.b = handle
;   All registers are preserved.
;
; Nur den Eintrag leeren, keinen Speicher freigeben -- die Grafik gehoert
; jemand anderem.  Darum nicht Free_memory.
; ***************************************************************************
Destroy_fake_handle:
	movem.l	d0/a0,-(sp)
	bsr	Mem_eintrag
	beq.b	dfh_out
	clr.l	MEM_ADR(a0)
	clr.l	MEM_ROH(a0)
	clr.l	MEM_LEN(a0)
	clr.w	MEM_ZAHL(a0)
dfh_out:
	movem.l	(sp)+,d0/a0
	rts

; ***************************************************************************
; Free_memory -- give a block back.
;   IN : d0.b = handle (an unused one does nothing)
;   All registers are preserved.
;
; Ein vorgetaeuschtes Handle (MEM_ROH = 0, Create_fake_handle) hat nichts
; bei TOS angefordert; dann wird nur der Eintrag geleert.  Vorher bekam TOS
; hier Mfree(0), sobald Kill_all_memory beim Neustart darueber lief.
; ***************************************************************************
Free_memory:
	movem.l	d0-d1/a0,-(sp)
	bsr	Mem_eintrag
	beq.b	fm_out
	MEM_FREE_HOOK			; the ST: a copy of it goes (vorspann.i)
	move.l	MEM_ROH(a0),d0
	beq.b	fm_leeren		; vorgetaeuscht: nichts bei TOS
	move.l	d0,-(sp)
	move.w	#Mfree,-(sp)
	Gemdos
	addq.l	#6,sp
fm_leeren:
	clr.l	MEM_ADR(a0)
	clr.l	MEM_ROH(a0)
	clr.l	MEM_LEN(a0)
	clr.w	MEM_ZAHL(a0)
fm_out:
	movem.l	(sp)+,d0-d1/a0
	rts

; ***************************************************************************
; Kill_memory -- drop a block without writing it back; here the same as
; Free_memory.
;   IN : d0.b = handle
;   All registers are preserved.
;
;
; Thalions OpenedChest_ModExit (EVENTS.S) unterscheidet:
;
;     btst #1,Event_b5(a5) / bne .No      ; zurueckschreiben?
;     ... jsr Save_subfile / jsr Free_pointer / jsr Free_memory
;     .No: move.b Chest_data_handle,d0 / jsr Kill_memory
;
; Auf dem Amiga kann Thalions Speicherverwaltung einen Block auslagern und
; spaeter wieder einlesen; "kill" heisst, der Inhalt ist verloren.  Bei uns
; wird nichts ausgelagert, also ist es dasselbe wie Free_memory.  Bis
; 2026-09-26 ein Platzhalter ohne Wirkung (MAIN_STUBS.S) -- der haette den
; Block liegen lassen.  d0 = Handle (.b).
; ***************************************************************************
Kill_memory:
	bra	Free_memory

; ***************************************************************************
; Der Dateizwischenspeicher des Originals -- File_allocate,
; Reallocate_memory, Invalidate_memory (docs/02 A4, gelesen in AM2_CPU).
;
; Thalions Speicherverwalter merkt sich im Kopf eines Blocks, welcher
; Dateieintrag darin liegt (Dateiart, Nummer).  Wird der Block freigegeben,
; bleibt der Inhalt liegen, bis der Platz anders gebraucht wird, und
; Reallocate_memory holt ihn ohne Laden zurueck.  3D_MAP.S nutzt das fuer
; die Zoomtabelle (100 KB, Dateiart Zoombuffer_file):
;
;     moveq.l #0,d0 / moveq.l #Zoombuffer_file,d1
;     jsr Reallocate_memory / tst.b d0 / beq.s .Load   ; noch da?
;     .Load: move.l #Max_zoom*(Max_zoom+2),d0 / moveq.l #0,d2
;     jsr File_allocate                                ; nein: neu anlegen
;
; **Bei uns gibt es diesen Zwischenspeicher nicht**: Free_memory gibt den
; Speicher sofort an TOS zurueck, und Load_subfile laedt jedes Mal neu.
; "Nichts mehr da" ist aber eine Antwort, die auch das Original gibt, und
; Thalion baut dann die Tabelle neu auf (Init_zoom_table, einmal je Karte).
; Deshalb:
;
; File_allocate      d0 = Laenge, d1 = Dateiart, d2 = Eintrag -> d0 = Handle.
;                    Nur Speicher; die Kennzeichnung braucht niemand.  Haelt
;                    an wie Allocate_CHIP, denn Thalion prueft das Handle
;                    nicht.  d1, d2 und a0 bleiben (das Original sichert d1/a0).
; Reallocate_memory  d0 = Eintrag, d1 = Dateiart -> d0 = 0 (nicht mehr da).
; Invalidate_memory  d0 = Handle.  Das Original sperrt den Block gegen
;                    Wiederverwendung, weil er seiner Datei nicht mehr gleicht
;                    (Overlays aufgemalt).  Bei uns wird nie wiederverwendet:
;                    endgueltig leer.
; ***************************************************************************

; File_allocate -- memory for a file entry; no file cache here.
;   IN : d0.l = length, d1 = file type, d2 = entry
;   OUT: d0 = handle.  Without memory it does not return (Allocate_CHIP).
;   All other registers are preserved.
File_allocate:
	bra	Allocate_CHIP

; Reallocate_memory -- is the entry still in the file cache?  Never here.
;   IN : d0 = entry, d1 = file type
;   OUT: d0 = 0 (not there)
;   All other registers are preserved.
Reallocate_memory:
	moveq	#0,d0
	rts

; Invalidate_memory -- the block no longer matches its file; nothing to do
; without a file cache (on the ST its recoloured copies go).
;   IN : d0.b = handle
;   All registers are preserved.
Invalidate_memory:
	MEM_FREE_HOOK			; the ST: a copy of it goes (vorspann.i)
	rts

; ***************************************************************************
; Clear_memory -- fill a block with zeros.
;   IN : d0.b = handle
;   All registers are preserved.
; ***************************************************************************
Clear_memory:
	movem.l	d0-d1/a0-a1,-(sp)
	bsr	Mem_eintrag
	beq.b	cm_out
	move.l	MEM_ADR(a0),a1
	move.l	MEM_LEN(a0),d1
	lsr.l	#2,d1
	beq.b	cm_out
	subq.l	#1,d1
cm_l:	clr.l	(a1)+
	subq.l	#1,d1
	bpl.b	cm_l
cm_out:
	movem.l	(sp)+,d0-d1/a0-a1
	rts

; ***************************************************************************
; Get_memory_length -- the length of a block.
;   IN : d0.b = handle
;   OUT: d0.l = length in bytes, 0 if the handle is not in use
;   All other registers are preserved.
; ***************************************************************************
Get_memory_length:
	move.l	a0,-(sp)
	bsr	Mem_eintrag
	beq.b	gml_nix
	move.l	MEM_LEN(a0),d0
	move.l	(sp)+,a0
	rts
gml_nix:
	moveq	#0,d0
	move.l	(sp)+,a0
	rts

; ***************************************************************************
; Shrink_memory -- make a block shorter; the address stays.
;   IN : d0.b = handle, d1.l = new length (not longer than now)
;   All registers are preserved.
;
;
; So ruft es Show_layout (DISPLAY.S), nachdem es den entpackten Layoutblock
; nicht mehr in voller Groesse braucht:
;
;     move.b d3,d0 / move.l #(199-Middle_Y)*120,d1 / jsr Shrink_memory
;
; Bei uns verschiebt nichts, die Adresse bleibt also stehen; verkleinert wird
; der Eintrag und der ueberzaehlige Teil geht ans Betriebssystem zurueck.
; Das ist auf einem 4-MB-Falcon kein Beiwerk.  Vergroessern tut es nie -- wer
; das verlangt, bekommt den Block unveraendert.
;
; **Die rohe Adresse liegt bis zu 255 Byte vor der ausgerichteten**
; (Allocate_memory fordert 256 Byte Zugabe an und rundet auf), deshalb geht
; dieser Abstand in die Laenge ein, die Mshrink bekommt.
; ***************************************************************************
Shrink_memory:
	movem.l	d0-d2/a0,-(sp)
	bsr	Mem_eintrag		; a0 = Eintrag, Z wenn das Handle nichts taugt
	beq.b	sm_out
	cmp.l	MEM_LEN(a0),d1
	bcc.b	sm_out			; nicht kleiner: nichts zu tun
	move.l	d1,MEM_LEN(a0)
	move.l	MEM_ADR(a0),d2
	sub.l	MEM_ROH(a0),d2		; Ausrichtungsabstand
	add.l	d1,d2			; neue Laenge ab der rohen Adresse
	move.l	d2,-(sp)
	move.l	MEM_ROH(a0),-(sp)
	clr.w	-(sp)
	move.w	#Mshrink,-(sp)
	Gemdos
	lea	12(sp),sp
sm_out:
	movem.l	(sp)+,d0-d2/a0
	rts

; ***************************************************************************
; Alles zurueckgeben, was noch aussteht -- beim Beenden.
; ***************************************************************************
Kill_all_memory:
	movem.l	d0-d1/a0,-(sp)
	moveq	#1,d0
kam_l:	bsr	Free_memory
	addq.w	#1,d0
	cmp.w	#MEM_MAX,d0
	bls.b	kam_l
	movem.l	(sp)+,d0-d1/a0
	rts

	SECTION	Fast_BSS,bss
Notweg:	ds.b	1			; gesetzt: Out_of_memory steht offen
	even
; Data_change_count -- counts what may bring new graphics into memory: a
; new block here, a load or an unpack in FILES_SUP.S, a drawing target in
; ST_LIB.S.  The ST's tile cache (St_kachel) compares it; the Falcon only
; counts.
Data_change_count:	ds.w	1
	IFD	SPEICHERTEST
Speichertest_zaehler:	ds.w	1	; zaehlt die Anforderungen herunter
Speichertest_scharf:	ds.b	1	; gesetzt: schon einmal gestellt
	even
	ENDC
	SECTION	Program,code

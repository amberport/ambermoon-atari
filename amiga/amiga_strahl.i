; amiga_strahl.i -- Schalter STRAHL (nur mit AMIGA_MESSEN): schreiben wir in
; Zeilen, die der Videl gerade zeigt?  Werte und Makros; der Code steht in
; AMIGA_MESSEN.S.  Eingebunden von amiga_vorspann.i und fee_vorspann.i.
;
; Je beobachteter Stelle ein Satz (ST_LAENGE Byte, BSS des Einbinders):
;   STRAHL_VOR Satz                      vor dem Schreiben: Videozaehler merken
;   STRAHL_NACH Satz,Schirm,Zeile,Zeilen danach: Treffer, wenn der Strahl in
;                                        der Zwischenzeit im Bereich war
; Schirm ist ein Langwort (Falcon-Schirm, Zeile 0) oder #0: der Schirm, der
; in V_BASIS steht.  Zeile und Zeilen sind Worte in Falcon-Zeilen.  Die
; Argumente werden in dieser Reihenfolge nach a1, d0, d1 geladen; keins darf
; also ein Register sein, das ein frueheres schon ueberschrieben hat.
; Alle Register bleiben.  Die Liste St_liste des Einbinders nennt die Saetze
; fuer die Ausgabe.

ST_AUFRUFE	equ	0		; .l so oft geschrieben
ST_TREFFER	equ	4		; .l Strahl war im Bereich
ST_IMBILD	equ	8		; .l Strahl danach im gezeigten Bild dieses Schirms
ST_VOR		equ	12		; .l Videozaehler vorher
ST_LAENGE	equ	16

STRAHL_VOR	macro
	IFD	STRAHL
	move.l	a0,-(sp)
	lea	\1,a0
	bsr	St_vorher
	move.l	(sp)+,a0
	ENDC
	endm

STRAHL_NACH	macro
	IFD	STRAHL
	movem.l	d0-d1/a0-a1,-(sp)
	move.l	\2,a1
	move.w	\3,d0
	move.w	\4,d1
	lea	\1,a0
	bsr	St_nachher
	movem.l	(sp)+,d0-d1/a0-a1
	ENDC
	endm

; Takt (nur AMIGA_RAHMEN, Tk_vbl): Wo liest der Videl, wenn unser VBL
; beginnt?  Je Fall (der vorige VBL schrieb eine neue Bildbasis oder nicht)
; TK_FAECHER Zaehler: je Schirm (neu = Falcon_vorn, alt = Falcon_hinten)
; TK_SCHIRM Faecher, dahinter eins fuer "anderswo".
TK_ZEILEN	equ	16		; Zeilen je Fach
TK_ANFANG	equ	16		; Fach: genau am Schirmanfang
TK_ENDE		equ	17		; Fach: genau hinter der letzten Zeile
TK_DAHINTER	equ	18		; Fach: weiter hinten (in der Luecke)
TK_SCHIRM	equ	19
TK_FAECHER	equ	2*TK_SCHIRM+1
TK_BEISPIELE	equ	8		; die ersten Videozaehler nach einem Umschalten
TK_VFC_FAECHER	equ	40		; T62: VFC at the VBL, per 32 half-lines

; fantasy.s -- das Fantasy-Intro (Thalion).  Bindet nur ein.
;
; Welche Sorte eine Datei ist, sagt der Pfad: "FAIRY.S" ist Thalions Datei,
; unveraendert aus $AMBER_URCODE (-I).  "fantasy_*.i" schreibt der Bau aus
; Fantasy_intro (tools/fantasy_auszug.py).  Der Rest ist unsere Schicht.
; Nach dem Binden biegt tools/fairy_umbiegen.py die $DFFxxx-Operanden von
; FAIRY.S auf Amiga_register um (K1, docs/11-Intro-Extro.md 7.2).

	include	"fee_vorspann.i"
	include	"fantasy_werte.i"

	SECTION	Fee_code,code
	include	"FEE_SUP.S"		; mit start, dem Programmeinsprung

	SECTION	Fee_code,code
Fairy_anfang:
	include	"FAIRY.S"
Fairy_ende:

	include	"fantasy_daten.i"

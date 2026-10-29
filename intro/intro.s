; intro.s -- Thalions Intro (Ambermoon_intro) auf dem Falcon.  Bindet nur ein.
;
; "intro_hunks.i" schreibt der Bau aus Ambermoon_intro (tools/amiga_programm.py):
; Thalions Programm, unveraendert, mit K1 und K2.  INTRO_SUP.S und
; amiga/AMIGA_RAHMEN.S sind unsere Schicht
; (docs/11-Intro-Extro.md, 4).  start in INTRO_SUP.S muss der
; Programmeinsprung sein, darum steht die Schicht vorn.

	include	"amiga_vorspann.i"

	SECTION	Intro_code,code
	include	"INTRO_SUP.S"

	include	"intro_hunks.i"

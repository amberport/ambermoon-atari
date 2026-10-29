; extro.s -- Thalions Extro (Ambermoon_extro) auf dem Falcon.  Bindet nur ein.
;
; "extro_hunks.i" schreibt der Bau aus Ambermoon_extro (tools/amiga_programm.py
; extro): Thalions Programm, unveraendert, mit K1 und K2.  EXTRO_SUP.S und
; amiga/AMIGA_RAHMEN.S sind unsere Schicht (docs/11-Intro-Extro.md, 5).
; start in EXTRO_SUP.S muss der Programmeinsprung sein, darum steht die
; Schicht vorn.

	include	"amiga_vorspann.i"

	SECTION	Extro_code,code
	include	"EXTRO_SUP.S"

	include	"extro_hunks.i"

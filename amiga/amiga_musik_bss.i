; amiga_musik_bss.i -- variables of AMIGA_MUSIK.S and the mixer.  Without
; SECTION; needs MUSIK_LAENGE from build/<name>_musik.i (in the program's
; data section).  The program loads into ST-RAM (no flags in its header), so
; the mixer's DMA ring may lie here.
	cnop	0,4
Musik_daten:		ds.b	MUSIK_LAENGE+2	; player and song, one byte more read
	even
Musik_schatten:		ds.b	$200		; the player's Paula ($DFF000-$DFF1FF)
Musik_cia:		ds.b	$2000		; dummy for $BFD000-$BFEFFF (timer, filter)
Musik_satz:		ds.b	MS_GROESSE	; parameter block for Mischer_install
	include	"mischer_bss.i"
	include	"mischer_chip.i"

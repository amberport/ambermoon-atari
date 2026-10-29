; fantasy_st_main.s -- the fantasy intro (Thalion) on the ST/STE.  Includes only.
;
; Which kind a file is, the path says: "FAIRY.S" is Thalion's file,
; unchanged from $AMBER_URCODE (-I).  "fantasy_*.i" the build writes from
; Fantasy_intro (tools/fantasy_auszug.py, shared with the Falcon build),
; "fantasy_st_*" in ST format (tools/fantasy_st_data.py).  The rest is our
; layer.
; After linking tools/fairy_umbiegen.py bends the $DFFxxx operands of
; FAIRY.S to Amiga_register (K1, docs/11-Intro-Extro.md 7.2).

	include	"fantasy_st_defs.i"
	include	"fantasy_werte.i"

	SECTION	Fee_code,code
	include	"FANTASY_ST.S"		; with start, the program entry
	include	"STARS_ST.S"		; ours for make_magic, make_funkel2

	SECTION	Fee_code,code
Fairy_anfang:
	include	"FAIRY.S"
Fairy_ende:

	include	"fantasy_daten.i"
	include	"fantasy_st_data.i"
	include	"fantasy_st_stars.i"

	ifne	ST_DATA_FIRST-AMIGA_FIRST
	fail	"fantasy_st_data.i was made for another picture position"
	endc
	ifne	ST_DATA_LINES-ST_PICTURE_LINES
	fail	"fantasy_st_data.i has another number of lines"
	endc
	ifne	ST_DATA_SPLIT-SPLIT_ROW
	fail	"fantasy_st_data.i splits the colours at another row"
	endc
	ifne	ST_FAIRY_FRAME-73*32
	fail	"fantasy_st_data.i has another fairy frame size than level3"
	endc

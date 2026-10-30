; fantasy.s -- the fantasy intro (Thalion) on the Falcon.  Includes only.
;
; Which kind a file is, the path says: "FAIRY.S" is Thalion's file,
; unchanged from $AMBER_URCODE (-I).  "fantasy_*.i" the build writes from
; Fantasy_intro (tools/fantasy_auszug.py), "falcon_fantasy_*" in Falcon
; format (tools/fantasy_st_data.py --falcon).  The rest is our layer.
; After linking tools/fairy_umbiegen.py bends the $DFFxxx operands of
; FAIRY.S to Amiga_register (K1, docs/11-Intro-Extro.md 7.2).

	include	"fee_vorspann.i"
	include	"fantasy_werte.i"

; FEE_BERICHT: a build that writes a report at the end (FEE_SUP.S)
	ifd	FEE_MESSEN
FEE_BERICHT	equ	1
	endc
	ifd	CHECK_STARS
	ifnd	FEE_BERICHT
FEE_BERICHT	equ	1
	endc
	endc

	SECTION	Fee_code,code
	include	"FEE_SUP.S"		; mit start, dem Programmeinsprung
	include	"STARS_FALCON.S"	; ours for make_magic, make_funkel2

	SECTION	Fee_code,code
Fairy_anfang:
	include	"FAIRY.S"
Fairy_ende:

	include	"fantasy_daten.i"
	include	"falcon_fantasy_data.i"
	include	"falcon_fantasy_stars.i"

	ifne	FALCON_DATA_ROWS-AMIGA_ZEILEN
	fail	"falcon_fantasy_data.i has another number of rows"
	endc
	ifne	FALCON_DATA_LINE-FALCON_ZEILE
	fail	"falcon_fantasy_data.i has another line length"
	endc
	ifne	FALCON_DATA_SPLIT-WECHSELZEILE
	fail	"falcon_fantasy_data.i sets the bank from another row"
	endc
	ifne	FALCON_FAIRY_FRAME-73*32
	fail	"falcon_fantasy_data.i has another fairy frame size than level3"
	endc

; intro_st_main.s -- INTROST.TOS: Thalion's intro (Ambermoon_intro) on the ST/STE
; (docs/05c-ST.md, "ST intro").  Our layer first (start is the entry),
; then Thalion's program as tools/intro_st_program.py wrote it.

	include	"intro_st_defs.i"

	SECTION	Intro_code,code
	include	"INTRO_ST.S"

	include	"intro_hunks.i"

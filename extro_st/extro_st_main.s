; extro_st_main.s -- EXTROST.TOS: Thalion's extro (Ambermoon_extro) on the ST/STE
; (docs/05c-ST.md, "ST extro").  Our layer first (start is the entry),
; then Thalion's program as tools/extro_st_program.py wrote it.

	include	"extro_st_defs.i"

	SECTION	Extro_code,code
	include	"EXTRO_ST.S"

	include	"extro_hunks.i"

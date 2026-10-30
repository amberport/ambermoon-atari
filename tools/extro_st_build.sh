#!/bin/sh
# Build the extro for the ST/STE: build/st_extro/EXTROST.TOS
# (docs/05c-ST.md, "ST extro").
#
#   1. extro_st_program.py  Thalion's Ambermoon_extro with K1, K2 and the
#                           ST's own K3 -> build/st_extro/extro_hunks.i
#   2. extro_st_data.py     the pictures in ST format -> extro_st_data.i,
#                           extro_st_pictures.bin
#   3. vasm + vlink         extro_st/extro_st_main.s for the 68000
#
# build_st.sh calls it and delivers EXTROST.TOS to ATARI/AMBFILES/
# (main ca91554).  AMBER.TOS starts it on the ST when the
# game ends (lader/lader.s Namen_st).
set -e
cd "$(dirname "$0")/.."
OUT=build/st_extro
mkdir -p $OUT

python3 tools/extro_st_program.py
python3 tools/extro_st_data.py

vasmm68k_mot -m68000 -Fvobj -quiet -Iextro_st -Iamiga -I$OUT \
	$VASM_EXTRA -o $OUT/EXTROST.o extro_st/extro_st_main.s
vlink -b ataritos -s -N Extro_code .text -N Extro_data .data -N Extro_bss .bss \
	-M -o $OUT/EXTROST.TOS $OUT/EXTROST.o > $OUT/EXTROST.map
ls -l $OUT/EXTROST.TOS

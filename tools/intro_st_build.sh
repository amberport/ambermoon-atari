#!/bin/sh
# Build the intro for the ST/STE: build/st_intro/INTROST.TOS
# (docs/05c-ST.md, "ST intro").
#
#   1. intro_st_program.py  Thalion's Ambermoon_intro with K1, K2 and the
#                            ST's own K3 -> build/st_intro/intro_hunks.i
#   2. vasm + vlink          intro_st/intro_st_main.s for the 68000
#
# build_st.sh calls it and delivers INTROST.TOS to ATARI/AMBFILES/ (main,
# wish of 2026-10-29, test T39); AMBER.TOS starts it on the ST.
set -e
cd "$(dirname "$0")/.."
OUT=build/st_intro
mkdir -p $OUT

python3 tools/intro_st_program.py

vasmm68k_mot -m68000 -Fvobj -quiet -Iintro_st -Iamiga -I$OUT \
	$VASM_EXTRA -o $OUT/INTROST.o intro_st/intro_st_main.s
vlink -b ataritos -s -N Intro_code .text -N Intro_data .data -N Intro_bss .bss \
	-M -o $OUT/INTROST.TOS $OUT/INTROST.o > $OUT/INTROST.map
ls -l $OUT/INTROST.TOS

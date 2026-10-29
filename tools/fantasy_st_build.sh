#!/bin/sh
# Build the fantasy intro for the ST/STE: build/st_fantasy/FANTSYST.TOS
# (docs/05c-ST.md, "ST fairy intro, plan").
#
#   1. fantasy_auszug.py   as for the Falcon: Fantasy_intro unpacked, names
#                          and constants checked against Thalion's FAIRY.S,
#                          build/fantasy_*.i
#   2. fantasy_st_data.py  graphics in ST format, the V3 colour tables
#                          -> build/st_fantasy/
#   3. vasm + vlink        fantasy_st/fantasy_st_main.s with the unchanged
#                          FAIRY.S, for the 68000
#   4. fairy_umbiegen.py   K1: the ten $DFFxxx operands to Amiga_register
#
# build_st.sh calls it and delivers FANTSYST.TOS (main 7dd32d7, T38).
set -e
cd "$(dirname "$0")/.."
PFADE=$(python3 tools/paths.py --sh) || exit 1; eval "$PFADE"    # URCODE: Thalion's source
SOURCE=$URCODE
if [ ! -f "$SOURCE/FAIRY.S" ]; then
	echo "Thalion's source is missing: $SOURCE/FAIRY.S (AMBER_URCODE)" >&2
	exit 1
fi
OUT=build/st_fantasy
mkdir -p $OUT

python3 tools/fantasy_auszug.py
python3 tools/fantasy_st_data.py

vasmm68k_mot -m68000 -Fvobj -quiet -I"$SOURCE" -Ifantasy_st -Iamiga -I$OUT -Ibuild \
	$VASM_EXTRA -o $OUT/FANTSYST.o fantasy_st/fantasy_st_main.s
vlink -b ataritos -s -N Fee_code .text -N Fee_daten .data -N Fee_bss .bss \
	-M -o $OUT/FANTSYST.TOS $OUT/FANTSYST.o > $OUT/FANTSYST.map
python3 tools/fairy_umbiegen.py $OUT/FANTSYST.TOS $OUT/FANTSYST.map
ls -l $OUT/FANTSYST.TOS

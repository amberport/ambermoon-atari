#!/bin/sh
# Build the fantasy intro for the Falcon: build/FANTASY.TOS, with the test
# builds FEEMESS.TOS and FEECHECK.TOS (docs/11-Intro-Extro.md).
#
#   1. fantasy_auszug.py         Fantasy_intro unpacked, names and constants
#                                checked against Thalion's FAIRY.S,
#                                build/fantasy_*.i
#   2. fantasy_st_data.py --falcon  the graphics in Falcon format (E30),
#                                -> build/falcon_fantasy/
#   3. vasm + vlink              fantasy/fantasy.s with the unchanged FAIRY.S
#   4. fairy_umbiegen.py         K1: the ten $DFFxxx operands to
#                                Amiga_register
#
# Called from build_falcon.sh or alone; delivered there.
set -e
cd "$(dirname "$0")/.."
PFADE=$(python3 tools/paths.py --sh) || exit 1; eval "$PFADE"    # URCODE: Thalion's source
if [ ! -f "$URCODE/FAIRY.S" ]; then
	echo "Thalions Quelltext fehlt: $URCODE/FAIRY.S (AMBER_URCODE)" >&2
	exit 1
fi

python3 tools/fantasy_auszug.py
python3 tools/fantasy_st_data.py --falcon

# bauen NAME SCHALTER: build/NAME.TOS aus fantasy/fantasy.s.  68030 fuer den
# Falcon; die Gegenprobe fuer den 68000 wie bei der Engine.
bauen() {
	# the report file after the program: FEEMESS.TOS writes FEEMESS.TXT
	printf 'Bericht_name:\tdc.b\t"%s.TXT",0\n' $1 > build/fee_name.i
	vasmm68k_mot -m68030 -Fvobj -quiet -I"$URCODE" -Ifantasy -Iamiga -Ibuild \
		-Ibuild/falcon_fantasy $VASM_EXTRA $2 -o build/$1.o fantasy/fantasy.s
	if vasmm68k_mot -m68000 -Fvobj -quiet -I"$URCODE" -Ifantasy -Iamiga -Ibuild \
		-Ibuild/falcon_fantasy $VASM_EXTRA $2 -o /dev/null fantasy/fantasy.s 2>/dev/null; then
		echo "  68000-tauglich ($1)"
	else
		echo "  ACHTUNG: $1 geht nicht mehr durch einen 68000" >&2
	fi
	vlink -b ataritos -s -N Fee_code .text -N Fee_daten .data -N Fee_bss .bss \
		-M -o build/$1.TOS build/$1.o > build/$1.map
	python3 tools/fairy_umbiegen.py build/$1.TOS build/$1.map
}

bauen FANTASY ""
# Test builds: FEEMESS counts the frames done just in time or late
# (FEE_MESSEN); FEECHECK runs Thalion's make_funkel2 and make_magic against
# ours every frame (CHECK_STARS, CHECK_DEFER).  Both write NAME.TXT.
bauen FEEMESS "-DFEE_MESSEN"
bauen FEECHECK "-DCHECK_STARS=1 -DCHECK_DEFER=1"

#!/bin/sh
# Build the program from both translation units: engine.s (library) and
# spiel.s (Thalion's game files).  Why two: see engine/spiel.s.
#
#     tools/build_engine.sh TARGET.TOS [OBJECT_DIR]
#
# Call from the repository root.  TARGET and OBJECT_DIR relative to it or
# absolute; without OBJECT_DIR the objects land in engine/.  Assembler
# switches come from VASM_EXTRA (e.g. -DZEIGERTAKT=1), the processor from
# VASM_CPU, default 68030; the ST build (tools/build_st.sh) sets 68000 and
# -DZIEL_ST=1.
#
# **The one place.**  tools/build_falcon.sh and tools/build_st.sh both call
# this script.  Once the call stood in two places, and the check path ran
# into nothing after the switch to vlink, because it is walked only rarely
# -- then the emulator checks another program than the one that goes onto
# the hardware.
set -e
WURZEL=$(cd "$(dirname "$0")/.." && pwd)
case "$1" in
	"") echo "Usage: $0 TARGET.TOS [OBJECT_DIR]" >&2; exit 2 ;;
	/*) ZIEL=$1 ;;
	*)  ZIEL=$WURZEL/$1 ;;
esac
case "${2:-engine}" in
	/*) OBJ=$2 ;;
	*)  OBJ=$WURZEL/${2:-engine} ;;
esac
PFADE=$(python3 "$WURZEL/tools/paths.py" --sh) || exit 1; eval "$PFADE"    # URCODE: Thalion's source
CPU=${VASM_CPU:-68030}

# 1. The DSP mixer (docs/13), Falcon only: tools/musik_dsp.sh ->
#    build/musik_dsp.dsp, which musik/mischer_daten.i includes with incbin.
#    **Before the XDEF lists:** einheiten_verbinden.py already assembles
#    engine.s once, and without the file that fails (happened with an empty
#    build/, 2026-10-08).  Under ZIEL_ST, MUSIK_SUP.S leaves the mixer out,
#    so the ST build needs neither the file nor a56.
cd "$WURZEL"
case " $VASM_EXTRA " in
	*" -DZIEL_ST"*) ;;
	*) sh tools/musik_dsp.sh ;;
esac

# 1b. The XDEF lists.  Stops when a name is defined in both units or in
#     neither.
python3 tools/einheiten_verbinden.py --cpu "$CPU" --extra="$VASM_EXTRA"

# 2. Both units.  -I../build brings the XDEF lists.
#
# **Warning 2028 stops the build** ("using signed operand as unsigned").
# vasm silently turns "moveq #255" into "moveq #-1" -- a loop over 256
# colours becomes one over 65536, and that one overwrote 128 KB including
# the stack (finding 185).  With Thalion the value fitted; when it does not
# fit with us, a constant in vorspann.i is wrong.
#
# **-align: align like Thalion's assembler** (finding 255).  Thalion's
# assembler put dc.w/dc.l and rs.w/rs.l on even addresses by itself, vasm
# does so only with -align.  Without it a pointer in WORD_SEL.S stood on an
# odd address, and Search_layer read it one byte off (crash in the word
# selection window); Part_X would lie at offset 13, an address error on a
# 68000.  Proven against AM2_CPU: the pad byte is there.  vasm reports each
# such place as warning 58 ("auto-aligned").
cd "$WURZEL/engine"
for EINHEIT in engine spiel; do
	PROTOKOLL="$OBJ/$EINHEIT.vasm.txt"
	if ! vasmm68k_mot -m$CPU -Fvobj -esc -align -I"$URCODE" -I../tools/originalcode \
		-I../build $VASM_EXTRA -o "$OBJ/$EINHEIT.o" $EINHEIT.s \
		> "$PROTOKOLL" 2>&1; then
		cat "$PROTOKOLL"
		exit 1
	fi
	cat "$PROTOKOLL"
	if grep -q "^warning 2028" "$PROTOKOLL"; then
		echo "STOP: vasm warning 2028 (value does not fit, finding 185):" >&2
		grep -A2 "^warning 2028" "$PROTOKOLL" >&2
		exit 1
	fi
done

# 2b. Cross-check of "opt t-" in spiel.s (Thalion's ACTIONS.S, line 128).
#     Assembled without the switch, exactly this one error must come; any
#     further message of the range check would have been hidden by "opt t-".
PROBE="$OBJ/spiel_typprobe.vasm.txt"
vasmm68k_mot -m$CPU -Fvobj -esc -align -I"$URCODE" -I../tools/originalcode \
	-I../build $VASM_EXTRA -DTYPPROBE=1 -o /dev/null spiel.s \
	> "$PROBE" 2>&1 || true
# Warning 58 ("auto-aligned", -align above) is expected and does not count.
MELDUNGEN=$(grep -E "^(error|warning) " "$PROBE" | grep -vc "^warning 58 " || true)
ERWARTET=$(grep -cE '^error 2037 in line 128 of ".*/ACTIONS\.S"' "$PROBE" || true)
if [ "$MELDUNGEN" != 1 ] || [ "$ERWARTET" != 1 ]; then
	echo "STOP: the cross-check of opt t- (spiel.s) expects exactly" \
		"error 2037 in ACTIONS.S:128, got:" >&2
	grep -A2 -E "^(error|warning) " "$PROBE" >&2
	exit 1
fi
echo "  cross-check opt t-: only ACTIONS.S:128 (btst d0,#Stationary_mask)"

# 3. Link.  **engine.o first**: the program entry is the start of the text
#    section, and that is start in src/MAIN.S.
#
# -N maps Thalion's section names onto the ones the linker script expects.
# Thalion's files end with
#     SECTION Fast_DATA,data
#     SECTION Fast_BSS,bss
# and the code stands in "Program".  MAIN.S adds "Longword_BSS".  Without
# the mapping vlink reports "Section was not recognized by target linker
# script" and puts everything into one pot.
vlink -b ataritos -s -N Program .text -N Fast_DATA .data -N Fast_BSS .bss \
	-N Longword_BSS .bss -N Chip_BSS .bss \
	-o "$ZIEL" "$OBJ/engine.o" "$OBJ/spiel.o"

#!/bin/sh
# The ST build (docs/12-ST-Port.md): everything that goes onto the ST/STE,
# into ATARI/ next to the Falcon programs (layout and program names:
# tools/build_common.sh).  Runs on its own; needs neither a Falcon build nor
# a56, for under ZIEL_ST the DSP mixer drops out.
#
#   sh tools/build_st.sh
#
# **One source tree for both.**  What is repaired in the Falcon build comes
# along here; tools/build_all.sh builds both, so whoever breaks the ST build
# sees it at once.  Target dependent are only ST.S/ST_LIB.S against FALCON.S
# and the places behind IFD ZIEL_ST.  The fantasy intro comes from
# tools/fantasy_st_build.sh (FANTSYST.TOS, Thalion's FAIRY.S unchanged); no
# ST versions of intro and extro yet: AMBER.TOS skips them.
set -e
cd "$(dirname "$0")/.."
. tools/build_common.sh

prepare st
heading "ST"

step "Engine"
mkdir -p build/st
PROTOKOLL=build/st/bau.txt
if ! VASM_CPU=68000 VASM_EXTRA="$VASM_EXTRA -DZIEL_ST=1" \
	sh tools/build_engine.sh build/st/ENGINEST.TOS build/st \
	> "$PROTOKOLL" 2>&1; then
	cat "$PROTOKOLL"
	echo "STOP: the ST build does not assemble" >&2
	exit 1
fi
cat "$PROTOKOLL"
# The same expected messages as in the Falcon build: 58 (auto-aligned,
# -align), 22 in Thalion's NUMERIC.S, 62 (<start>) of the linker.
engine_warnings "$PROTOKOLL"
note "ENGINEST.TOS $(( $(wc -c < build/st/ENGINEST.TOS) / 1024 )) KB, 68000, -DZIEL_ST=1"

# DEVIATION (goal 2), docs/17-deviations.md D1: the ST palettes are reduced
# here, from Palettes.amb and AM2_CPU, with the hand corrections in
# tools/st_palettes.txt; ENGINEST.TOS loads STPAL.DAT once at start.
step "ST palettes"
python3 tools/st_palettes.py build -o build/st/STPAL.DAT
note "STPAL.DAT, sheet build/st_palettes/index.html"

step "Game files and delivery"
clean_output st
deliver_data
deliver build/st/ENGINEST.TOS "$DATA"
deliver build/st/STPAL.DAT "$DATA"
note "game files, save games, YM music, AMBER.INF"

step "Fantasy intro"
# Thalion's FAIRY.S unchanged, graphics in ST format at build time
# (docs/05c-ST.md, "ST fairy intro"); needs AMBER_URCODE, as the Falcon's.
sh tools/fantasy_st_build.sh
deliver build/st_fantasy/FANTSYST.TOS "$DATA"
note "FANTSYST.TOS"

step "Intro"
# Thalion's Ambermoon_intro rebound for the 68000, scenes in ST format
# (docs/05c-ST.md, "ST intro"); AMBER.TOS starts it on the ST.
sh tools/intro_st_build.sh
deliver build/st_intro/INTROST.TOS "$DATA"
note "INTROST.TOS"

step "Loader and tools"
build_loader

build_bomben
note "AMBER.TOS, BOMBEN.TOS"

# Under build_all.sh the Falcon build has run them already.
[ -n "$_AMBER_PREPARED" ] || source_checks

finish_output st
step_done
say "  $(wc -l < build/delivered_st.txt) files delivered to $OUT/"
summary

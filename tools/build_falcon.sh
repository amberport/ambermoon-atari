#!/bin/sh
# The Falcon build: everything that goes onto the Falcon, into ATARI/
# (layout and program names: tools/build_common.sh).  The ST build is
# tools/build_st.sh, both together tools/build_all.sh.
#
#   sh tools/build_falcon.sh
#   VASM_EXTRA="-DZEIGERTAKT=1" sh tools/build_falcon.sh    diagnostic switch
#
# Why everything at once: there was an error that cost half an evening -- a
# scene file got a new entry, the two other maps were not rebuilt, and on
# the machine the party stood in a broken kitchen.  New entries shift the
# tile numbers, and then everything has to come about together.
set -e
cd "$(dirname "$0")/.."
. tools/build_common.sh

prepare falcon
heading "Falcon"

step "Engine"
# vasm in Motorola syntax, the same language as Thalion's source.
#
# -esc is not optional: without it vasm writes "\r\n" literally as
# backslash-r-backslash-n into the string.  Looking at the picture one does
# not notice -- the messages are silently broken (finding 52).
#
# Linked with vlink, which writes the **relocation table**.  Thalion's
# source puts down "dc.l <label>" in 441 places, absolute addresses the
# Amiga loader relocates; whoever takes over this source needs the same
# table (finding 122).
#
# VASM_EXTRA passes assembler switches through, e.g. "-DZEIGERTAKT=1".
# Empty in the normal build.  Two translation units since 2026-09-26 (why: engine/spiel.s).
PROTOKOLL=build/engine_falcon.txt
if ! sh tools/build_engine.sh engine/ENGINE.TOS > "$PROTOKOLL" 2>&1; then
	cat "$PROTOKOLL"
	exit 1
fi
cat "$PROTOKOLL"
engine_warnings "$PROTOKOLL"

# Cross-check for the ST: does the same source also go through a 68000?
# Costs a second and shows at once when a 68020+ instruction creeps in.  Not
# fatal -- only a message; tools/build_st.sh is the real ST build.  Over
# **both** units; the XDEF lists from the run above hold here too.
#
# CAUTION when reading it: vasm reports this as a *fatal error* and stops.
# Whoever checks only for "^error" sees nothing (finding 53).  What it does
# not find: an address used as a structure offset ("MA_X1(a1)" with MA_X1 a
# variable).  That assembles for the 68000 without complaint (finding 169).
ZIEL68000="68000-capable"
cd engine
for EINHEIT in engine spiel; do
	if ! vasmm68k_mot -m68000 -Fvobj -esc -align -quiet -I"$URCODE" \
		-I../tools/originalcode -I../build $VASM_EXTRA -o /dev/null \
		$EINHEIT.s 2>/dev/null; then
		warn "$EINHEIT.s no longer goes through a 68000 -- ST/STE would be closed"
		ZIEL68000="NOT 68000-capable"
		vasmm68k_mot -m68000 -Fvobj -esc -align -I"$URCODE" -I../tools/originalcode \
			-I../build $VASM_EXTRA -o /dev/null $EINHEIT.s 2>&1 | grep -i error >&2
	else
		echo "  68000-capable ($EINHEIT.s${VASM_EXTRA:+, $VASM_EXTRA})"
	fi
done
cd ..
note "ENGINE.TOS $(( $(wc -c < engine/ENGINE.TOS) / 1024 )) KB, $ZIEL68000"

step "Game files and delivery"
clean_output falcon
deliver_data
deliver engine/ENGINE.TOS "$DATA"
note "game files, save games, YM music, AMBER.INF"

step "Fantasy intro"
# Thalion's FAIRY.S unchanged, data at build time from Fantasy_intro
# (docs/11-Intro-Extro.md).
sh tools/fantasy_bauen.sh
deliver build/FANTASY.TOS "$DATA"
deliver build/FEEMESSB.TOS "$DATA"
deliver build/FEEMESSC.TOS "$DATA"
deliver build/FEEPRUEF.TOS "$DATA"
deliver build/FEEDIAG.TOS "$DATA"
deliver build/FEEDIAGC.TOS "$DATA"
note "FANTASY.TOS + 5 test builds"

step "Intro"
# Thalion's Ambermoon_intro, taken over at build time (docs/11-Intro-Extro.md, 4).
sh tools/amiga_bauen.sh intro
deliver build/INTRO.TOS "$DATA"
# Measuring version (AMIGA_MESSEN): where the time goes, file INTROMES.MES;
# check version (BLIT_PRUEF): fast blits against exact ones; ZOOM_PRUEF:
# every zoom on Thalion's way and on ours (intro/INTRO_ZOOM.S), compared.
sh tools/amiga_bauen.sh intro INTROMES "-DAMIGA_MESSEN"
sh tools/amiga_bauen.sh intro INTROPRF "-DAMIGA_MESSEN -DBLIT_PRUEF -DZOOM_PRUEF"
# Diagnosis for the hardware (INTRDIAG): ends by itself after 60 seconds
# and returns to the desktop, writes INTRDIAG.MES and .TXT; STRAHL counts
# how often we write into lines the Videl is showing.
sh tools/amiga_bauen.sh intro INTRDIAG "-DAMIGA_MESSEN -DMESS_ENDE=60 -DSTRAHL"
deliver build/INTROMES.TOS "$DATA"
deliver build/INTRDIAG.TOS "$DATA"
deliver build/INTROPRF.TOS "$DATA"
note "INTRO.TOS + 3 test builds"

step "Extro"
# Thalion's Ambermoon_extro, likewise (docs/11-Intro-Extro.md, 5).
sh tools/amiga_bauen.sh extro
deliver build/EXTRO.TOS "$DATA"
# Diagnosis for the hardware (EXTRDIAG, like INTRDIAG): measurement and
# STRAHL, ends after 60 seconds, writes EXTRDIAG.MES and .TXT.  The whole
# extro is too long for one measurement (user, T12).
sh tools/amiga_bauen.sh extro EXTRDIAG "-DAMIGA_MESSEN -DMESS_ENDE=60 -DSTRAHL"
# Check version (BLIT_PRUEF): every blit directly and through the buffer,
# compared.  Almost a still picture, hence the end after 120 measuring
# seconds; EXTROPRF.TXT names the differences.
sh tools/amiga_bauen.sh extro EXTROPRF "-DAMIGA_MESSEN -DBLIT_PRUEF -DMESS_ENDE=120"
deliver build/EXTRDIAG.TOS "$DATA"
deliver build/EXTROPRF.TOS "$DATA"
note "EXTRO.TOS + 2 test builds"

step "Loader and tools"
build_loader
# FREQ.TOS measures the frame rate (50/60 Hz) for the measuring files; 68000.
vasmm68k_mot -m68000 -Fvobj -quiet -o build/freq.o lader/freq.s
vlink -b ataritos -s -N Freq_code .text -N Freq_daten .data \
	-N Freq_bss .bss -o build/FREQ.TOS build/freq.o
deliver build/FREQ.TOS "$DATA"

build_bomben
note "AMBER.TOS, FREQ.TOS, BOMBEN.TOS"

source_checks
# These two read the XDEF lists of the Falcon build in build/.
step "Placeholders and full probe"
python3 tools/platzhalter_karte.py
VOLL=$(python3 tools/vollprobe.py)
echo "$VOLL"
note "$(echo "$VOLL" | sed -n 's/.*braucht \([0-9]*\) Namen -- echt \([0-9]*\).*/\2 of \1 library names real/p')"

# Generated appendices of the developer documentation, into build/doku/.
# docs/entwickler/ gets them only by hand on main (doku_listen.py --docs).
step "Appendices of the docs"
python3 tools/doku_listen.py
note "build/doku/"

finish_output falcon
step_done
say "  $(wc -l < build/delivered_falcon.txt) files delivered to $OUT/"
summary

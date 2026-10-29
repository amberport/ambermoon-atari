#!/bin/sh
# Build the lower border probe (test T93, docs/05c-ST.md) into build/st_rand/:
#
#   UNTRAND.TOS   DELAY 18, the middle of the window Hatari shows (13-24)
#   UNTR_LO.TOS   DELAY 14, near the lower edge
#   UNTR_HI.TOS   DELAY 23, near the upper edge
#
# If all three open the border cleanly on the hardware, its window is at
# least as wide as Hatari's and the middle is safe.
#
# Standalone, without Thalion's source.  VASM_EXTRA="-DDELAY=n" changes the
# main one for a calibration run.
set -e
cd "$(dirname "$0")"
ZIEL=../../build/st_rand
mkdir -p $ZIEL
baue() {
	vasmm68k_mot -m68000 -Fvobj -esc -quiet $1 -o $ZIEL/untrand.o untrand.s
	vlink -b ataritos -s -o $ZIEL/$2 $ZIEL/untrand.o
	rm -f $ZIEL/untrand.o
}
baue "$VASM_EXTRA" UNTRAND.TOS
baue "-DDELAY=14" UNTR_LO.TOS
baue "-DDELAY=23" UNTR_HI.TOS
ls -l $ZIEL/*.TOS

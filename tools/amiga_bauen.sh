#!/bin/sh
# Thalions Intro oder Extro bauen: build/INTRO.TOS oder build/EXTRO.TOS
# (docs/11-Intro-Extro.md, 4 und 5).
#
#   sh tools/amiga_bauen.sh intro|extro [NAME "SCHALTER"]
#
#   1. amiga_programm.py   das Programm zerlegen, K1, K2, build/<name>_hunks.i
#   2. vasm + vlink        <name>/<name>.s: unsere Schicht und Thalions Programm
#
# Mit NAME und SCHALTER eine Sonderfassung, etwa die Messfassung:
#   sh tools/amiga_bauen.sh intro INTROMES "-DAMIGA_MESSEN"
#
# Called from build_falcon.sh or alone; delivered there.
set -e
cd "$(dirname "$0")/.."
case "$1" in
	intro) NAME=INTRO; ABSCHNITT=Intro ;;
	extro) NAME=EXTRO; ABSCHNITT=Extro ;;
	*) echo "Aufruf: amiga_bauen.sh intro|extro [NAME \"SCHALTER\"]" >&2; exit 1 ;;
esac
SCHALTER=""
if [ -n "$2" ]; then
	NAME=$2
	SCHALTER=$3
fi

python3 tools/amiga_programm.py "$1"
python3 tools/musik_k1.py "$1"
sh tools/musik_dsp.sh			# the mixer's DSP code, build/musik_dsp.dsp
# Messdatei nach dem Programm: INTROMES.TOS schreibt INTROMES.MES
printf '\tdc.b\t"%s.MES",0\n' $NAME > build/mess_name.i

vasmm68k_mot -m68030 -Fvobj -quiet -I"$1" -Iamiga -Imusik -Ibuild $VASM_EXTRA $SCHALTER \
	-o build/$NAME.o "$1/$1.s"
if vasmm68k_mot -m68000 -Fvobj -quiet -I"$1" -Iamiga -Imusik -Ibuild $VASM_EXTRA $SCHALTER \
	-o /dev/null "$1/$1.s" 2>/dev/null; then
	echo "  68000-tauglich ($NAME)"
else
	echo "  ACHTUNG: $NAME geht nicht mehr durch einen 68000" >&2
fi
vlink -b ataritos -s -N ${ABSCHNITT}_code .text -N ${ABSCHNITT}_daten .data \
	-N ${ABSCHNITT}_bss .bss -M -o build/$NAME.TOS build/$NAME.o > build/$NAME.map

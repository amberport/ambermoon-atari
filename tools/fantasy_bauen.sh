#!/bin/sh
# Das Fantasy-Intro bauen: build/FANTASY.TOS, dazu die Messfassungen
# FEEMESSB.TOS und FEEMESSC.TOS (docs/11-Intro-Extro.md).
#
#   1. fantasy_auszug.py   Fantasy_intro entpacken, Namen und Konstanten gegen
#                          Thalions FAIRY.S pruefen, build/fantasy_*.i schreiben
#   2. vasm + vlink        fantasy/fantasy.s mit der unveraenderten FAIRY.S
#   3. fairy_umbiegen.py   K1: die zehn $DFFxxx-Operanden auf Amiga_register
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

# bauen NAME SCHALTER: build/NAME.TOS aus fantasy/fantasy.s.  68030 fuer den
# Falcon; die Gegenprobe fuer den 68000 wie bei der Engine.
bauen() {
	# Messdatei nach dem Programm: FEEDIAG.TOS schreibt FEEDIAG.MES
	printf '\tdc.b\t"%s.MES",0\n' $1 > build/mess_name.i
	vasmm68k_mot -m68030 -Fvobj -quiet -I"$URCODE" -Ifantasy -Iamiga -Ibuild \
		$VASM_EXTRA $2 -o build/$1.o fantasy/fantasy.s
	if vasmm68k_mot -m68000 -Fvobj -quiet -I"$URCODE" -Ifantasy -Iamiga -Ibuild \
		$VASM_EXTRA $2 -o /dev/null fantasy/fantasy.s 2>/dev/null; then
		echo "  68000-tauglich ($1)"
	else
		echo "  ACHTUNG: $1 geht nicht mehr durch einen 68000" >&2
	fi
	vlink -b ataritos -s -N Fee_code .text -N Fee_daten .data -N Fee_bss .bss \
		-M -o build/$1.TOS build/$1.o > build/$1.map
	python3 tools/fairy_umbiegen.py build/$1.TOS build/$1.map
}

bauen FANTASY ""
# Messfassungen (FEE_MESSEN): zaehlen die Bilder, die knapp oder zu spaet
# fertig werden; B setzt die Zeilen mit dem Blitter um, C mit der CPU.
bauen FEEMESSB "-DFEE_MESSEN"
bauen FEEMESSC "-DFEE_MESSEN -DFEE_CPU"
# PruefFassung (BLIT_PRUEF): jeder schnelle Blit laeuft auch genau und wird
# verglichen; langsam, nur fuer den Beleg.
bauen FEEPRUEF "-DFEE_MESSEN -DBLIT_PRUEF"
# Diagnose fuer die Hardware (FEEDIAG): wie FEEMESSB mit Profil
# (AMIGA_MESSEN, schreibt FEEDIAG.MES und .TXT); endet nach 60 Sekunden von selbst,
# auch wenn Thalions Ablauf festhaengt; STRAHL zaehlt, wie oft wir in Zeilen
# schreiben, die der Videl gerade zeigt.  FEEDIAGC setzt die Zeilen mit der
# CPU um, die Fee bleibt beim Blitter.
bauen FEEDIAG "-DFEE_MESSEN -DAMIGA_MESSEN -DMESS_ENDE=60 -DSTRAHL"
bauen FEEDIAGC "-DFEE_MESSEN -DAMIGA_MESSEN -DMESS_ENDE=60 -DFEE_CPU"

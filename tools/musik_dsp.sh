#!/bin/sh
# musik_dsp.sh -- assemble the DSP mixer: musik/MUSIK_DSP.A56 -> build/musik_dsp.dsp.
#
#   sh tools/musik_dsp.sh
#
# a56 (Ubuntu package "a56") reports errors only in its listing
# ("errors=n"), so the listing is checked.  tools/dsp_lod.py turns the
# output into the image for Dsp_ExecBoot that musik/mischer_daten.i
# includes with incbin.  Called by build_engine.sh (game, Falcon only) and
# amiga_bauen.sh (intro, extro); docs/13.
set -e
cd "$(dirname "$0")/.."
command -v a56 >/dev/null || { echo "a56 fehlt (sudo apt install a56)" >&2; exit 1; }
mkdir -p build
a56 -o build/musik_dsp.lod musik/MUSIK_DSP.A56 > build/musik_dsp.lst
if ! grep -q '^errors=0' build/musik_dsp.lst || ! grep -q '^warnings=0' build/musik_dsp.lst; then
	echo "ABBRUCH: a56 meldet Fehler oder Warnungen (build/musik_dsp.lst):" >&2
	grep -iE 'error|warn' build/musik_dsp.lst >&2
	exit 1
fi
python3 tools/dsp_lod.py build/musik_dsp.lod build/musik_dsp.dsp

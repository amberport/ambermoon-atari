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
#
# **a56 is optional:** the assembled image lies in the repository as
# musik/musik_dsp.dsp (our own code, no data of Thalion's), so a build without
# a56 takes that one.  With a56 the result must be equal to it; whoever changes
# the mixer copies the new image there, and it is committed with the source.
set -e
cd "$(dirname "$0")/.."
mkdir -p build
if ! command -v a56 >/dev/null; then
	cp musik/musik_dsp.dsp build/musik_dsp.dsp
	echo "  no a56: the DSP mixer from musik/musik_dsp.dsp"
	exit 0
fi
a56 -o build/musik_dsp.lod musik/MUSIK_DSP.A56 > build/musik_dsp.lst
if ! grep -q '^errors=0' build/musik_dsp.lst || ! grep -q '^warnings=0' build/musik_dsp.lst; then
	echo "ABBRUCH: a56 meldet Fehler oder Warnungen (build/musik_dsp.lst):" >&2
	grep -iE 'error|warn' build/musik_dsp.lst >&2
	exit 1
fi
python3 tools/dsp_lod.py build/musik_dsp.lod build/musik_dsp.dsp
if ! cmp -s build/musik_dsp.dsp musik/musik_dsp.dsp; then
	echo "STOP: musik/musik_dsp.dsp is not what a56 makes of musik/MUSIK_DSP.A56." >&2
	echo "If the mixer changed: cp build/musik_dsp.dsp musik/musik_dsp.dsp" >&2
	exit 1
fi

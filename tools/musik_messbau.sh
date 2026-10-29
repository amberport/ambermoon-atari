#!/bin/sh
# Die drei Messfassungen der Musik bauen (docs/13, 4c): ohne Musik, Mischer
# auf dem Prozessor, Mischer auf dem DSP.  Alle mit dem Schalter MUSIKMESS:
# je 10 s Bilder, VBL und die Zeit in Musik_vbl, beim Beenden nach
# MESS_OHN.TXT, MESS_CPU.TXT oder MESS_DSP.TXT (in den Ordner, aus dem das
# Programm startet).
#
#   sh tools/build_falcon.sh && sh tools/musik_messbau.sh
#
# Legt MESS_OHN.TOS, MESS_CPU.TOS, MESS_DSP.TOS neben ENGINE.TOS in
# ATARI/AMBFILES/.  Engine, save games and everything else stay as
# build_falcon.sh delivered them; the next build (Falcon or ST) clears the
# measuring versions away again.
set -e
cd "$(dirname "$0")/.."
[ -d ATARI/AMBFILES ] || { echo "ATARI/AMBFILES is missing -- run tools/build_falcon.sh first" >&2; exit 1; }

baue() {	# Name, Schalter
	ZIEL=build/messbau_$1
	rm -rf "$ZIEL"
	mkdir -p "$ZIEL"
	echo "== MESS_$1.TOS ($2) =="
	VASM_EXTRA="-DMUSIKMESS=1 $2 $VASM_EXTRA" \
		sh tools/build_engine.sh "$ZIEL/ENGINE.TOS" "$ZIEL" > "$ZIEL/bau.txt" 2>&1 \
		|| { cat "$ZIEL/bau.txt"; exit 1; }
	# Nur die erwarteten Warnungen (CLAUDE.md): 22, viermal 58, 62.
	ANDERE=$(grep -E '^warning|^error' "$ZIEL/bau.txt" | grep -vE '^warning (22|58|62)' || true)
	if [ -n "$ANDERE" ]; then echo "$ANDERE" >&2; exit 1; fi
	cp "$ZIEL/ENGINE.TOS" "ATARI/AMBFILES/MESS_$1.TOS"
	echo "  ATARI/AMBFILES/MESS_$1.TOS"
}
baue OHN -DMUSIK_AUS=1
baue CPU -DMUSIK_CPU=1
baue DSP ""

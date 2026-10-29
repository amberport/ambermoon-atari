#!/bin/sh
# Ein Falcon-Programm in Hatari laufen lassen und Bildschirmabzuege machen.
#
# Wofuer das taugt und wofuer nicht, steht in LIESMICH.txt.  Kurz: fuer
# "stuerzt es ab" und "stimmt das Bild" ja, fuer Mauszeiger und
# Zeitverhalten nein.
#
# Der Lauf ist fensterlos (SDL_VIDEODRIVER=offscreen) und beendet sich
# selbst.  Ohne das laeuft Hatari im Schnellvorlauf und sieht dabei
# eingefroren aus, was schon zweimal zu der Annahme gefuehrt hat, es haenge.
#
#   sh tools/hatari/teste.sh                     ENGINE.TOS, Abzug bei 1500 VBL
#   sh tools/hatari/teste.sh -v 800,2000,6000    mehrere Abzuege
#   sh tools/hatari/teste.sh -p FANTASY.TOS      anderes Programm
#   sh tools/hatari/teste.sh -m rgb              an einem RGB-Monitor
#
# Gemessen: das Kartenbild steht ab VBL 600, davor laeuft noch TOS hoch.
# Die Vorgabe 1500 laesst Luft, ohne den Lauf unnoetig zu verlaengern.
#
# TOS 4.04 is not part of the repository.  AMBER_TOS names the image, as a
# variable or in build.cfg; default TOS404.IMG in the folder
# ambermoon_gamedata/ next to the repository (tools/paths.py).
set -e
cd "$(dirname "$0")/../.."
WURZEL=$(pwd)

PFADE=$(python3 tools/paths.py --sh) || exit 1; eval "$PFADE"    # TOS: AMBER_TOS, as every path (tools/paths.py)
LAUFWERK=${AMBER_LAUFWERK:-$WURZEL/ATARI}
# ENGINE.TOS liegt im Ordner AMBFILES (Erkenntnis 262).  Mit "-p" und "-l"
# geht auch die flache Ablage (Pruefassung).
PROGRAMM=AMBFILES/ENGINE.TOS
MARKEN=1500
# Monitorart.  Die Engine erbt die Monitorbits aus dem Desktop-Modus, laeuft
# also an beiden -- "-m vga" und "-m rgb" sind beide gueltige Pruefungen.
MONITOR=vga
ZIEL=$WURZEL/hatari-abzuege

while [ $# -gt 0 ]; do
	case $1 in
	-v) MARKEN=$2; shift 2 ;;
	-p) PROGRAMM=$2; shift 2 ;;
	-m) MONITOR=$2; shift 2 ;;
	-o) ZIEL=$2; shift 2 ;;
	-l) LAUFWERK=$2; shift 2 ;;
	*)  echo "unbekannt: $1" >&2; exit 2 ;;
	esac
done

[ -f "$TOS" ] || { echo "TOS-Abbild fehlt: $TOS" >&2; exit 1; }
[ -d "$LAUFWERK" ] || { echo "Laufwerk fehlt: $LAUFWERK" >&2; exit 1; }
[ -f "$LAUFWERK/$PROGRAMM" ] || { echo "$PROGRAMM fehlt in $LAUFWERK" >&2; exit 1; }

mkdir -p "$ZIEL"
ARBEIT=$(mktemp -d)
trap 'rm -rf "$ARBEIT"' EXIT

# Die Marken zu einer Kette von Haltepunkten verketten: jeder Abzug setzt den
# naechsten Haltepunkt, der letzte beendet den Emulator.  Hatari kann pro
# Haltepunkt nur eine Datei ausfuehren, deshalb eine Datei je Marke.
VORIGE=
for M in $(echo "$MARKEN" | tr ',' ' '); do
	echo "screenshot $ZIEL/vbl$M.png" > "$ARBEIT/$M.ini"
	if [ -n "$VORIGE" ]; then
		echo "b VBL > $M :once :file $ARBEIT/$M.ini" >> "$ARBEIT/$VORIGE.ini"
	else
		echo "b VBL > $M :once :file $ARBEIT/$M.ini" > "$ARBEIT/start.ini"
	fi
	VORIGE=$M
done
echo "quit 0" >> "$ARBEIT/$VORIGE.ini"

# Accuracy switches, set here explicitly so that a changed hatari.cfg
# does not change them silently: cycle exact CPU, prefetch mode, the
# 68030 data cache (the Falcon has it on).  --fast-forward only changes
# the speed on the host, not the emulated timing (cycles per VBL); there
# is no vsync switch that changes the emulated machine.  Even with all of
# them Hatari is 1.7x (2D) to 4x (3D floor) too fast on the Falcon,
# because it hardly models the bus wait states (docs/entwickler/09).
echo "== $PROGRAMM in Hatari, Abzuege bei VBL $MARKEN =="
SDL_VIDEODRIVER=offscreen timeout 600 hatari \
	--machine falcon --tos "$TOS" \
	--cpulevel 3 --cpuclock 16 --dsp emu --monitor "$MONITOR" --memsize 14 \
	--cpu-exact on --compatible on --data-cache on \
	--sound off --mic off --fast-forward on --fast-boot on --conout 2 \
	--harddrive "$LAUFWERK" --gemdos-drive C \
	--auto "C:\\$(echo "$PROGRAMM" | tr / '\\\\')" \
	--parse "$ARBEIT/start.ini" > "$ARBEIT/log.txt" 2>&1 || true

# Hatari meldet fehlende Symboltabellen als ERROR, das ist keiner -- die
# Engine wird ohne gebaut.
if grep -i 'error' "$ARBEIT/log.txt" | grep -vi 'symbol' | head -5 | grep -q .; then
	echo "-- Meldungen --"
	grep -i 'error' "$ARBEIT/log.txt" | grep -vi 'symbol' | head -5
fi

# Cconws-Ausgaben der Engine.  Das ist das brauchbarste Diagnosewerkzeug:
# Meldungen an verdaechtige Stellen setzen und sehen, wie weit es kommt.
MELDUNGEN=$(grep -vE 'symbol|breakpoint|Breakpoint|debugger|debug mode|screenshot|Screen dump|^>|^[[:space:]]|^-|Changed|^INFO|^WARN|^CPU=|^[0-9a-f]{8} |^$' "$ARBEIT/log.txt" || true)
if [ -n "$MELDUNGEN" ]; then
	echo "-- Ausgaben des Programms --"
	echo "$MELDUNGEN" | sed 's/^/  /'
fi

echo "== Abzuege =="
for M in $(echo "$MARKEN" | tr ',' ' '); do
	if [ -f "$ZIEL/vbl$M.png" ]; then
		echo "  $ZIEL/vbl$M.png"
	else
		echo "  VBL $M: kein Abzug -- so weit kam der Lauf nicht"
	fi
done

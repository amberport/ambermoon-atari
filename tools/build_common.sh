# build_common.sh -- the part tools/build_falcon.sh and tools/build_st.sh
# share.  Sourced, not run: it sets variables and defines functions.
#
# **One delivery folder for both machines.**  ATARI/ holds what goes onto
# the Atari, laid out like the original (finding 262): on top the loader
# AMBER.TOS for both machines (it reads the cookie _MCH), below in AMBFILES/
# the game files, the save games and the programs.  The game files and save
# games are the same for both, so one folder plays on either machine and a
# save game made on one continues on the other.  The program names are
# unique per machine:
#
#   Falcon   ENGINE.TOS    FANTASY.TOS   INTRO.TOS   EXTRO.TOS
#   ST       ENGINEST.TOS  FANTSYST.TOS  INTROST.TOS EXTROST.TOS
#
# There are no ST versions of the intros yet; AMBER.TOS skips a missing
# program silently and the engine shows its own start menu.
#
# Each build delivers the complete game files and only its own programs.
# What it delivered goes into build/delivered_<target>.txt; before
# delivering, a build removes every file in ATARI/ and ATARI/AMBFILES/
# except *.INF and the files the *other* build delivered last time.

OUT=ATARI
DATA=$OUT/AMBFILES

# **Output: one line per step, the rest into build/build.log** (user,
# 2026-10-29).  The script that sources this file first (build_all.sh, or
# build_falcon.sh/build_st.sh on their own) starts the log and sends its
# stdout and stderr there; fd 3 stays the terminal.  The builds it calls
# inherit both and append.  step NAME closes the step before (a tick and
# its time) and opens the next; a step ends badly only by an exit, and the
# EXIT trap then shows the step, a cross and the last lines of the log.
# VERBOSE=1 shows everything on the terminal, as before.
LOG=build/build.log
if [ -z "$_AMBER_LOG" ]; then
	mkdir -p build
	: > "$LOG"
	_AMBER_LOG=$LOG
	_AMBER_T0=$(date +%s)
	export _AMBER_LOG _AMBER_T0
	if [ -t 1 ]; then
		_AMBER_COLOUR=1
		export _AMBER_COLOUR
	fi
	if [ -n "$VERBOSE" ]; then
		exec 3>&1
	else
		exec 3>&1 >>"$LOG" 2>&1
	fi
	_AMBER_TOP=1
fi
if [ -n "$_AMBER_COLOUR" ]; then
	C_OK=$(printf '\033[32m'); C_BAD=$(printf '\033[31m')
	C_WARN=$(printf '\033[33m'); C_HEAD=$(printf '\033[1m'); C_OFF=$(printf '\033[0m')
else
	C_OK=; C_BAD=; C_WARN=; C_HEAD=; C_OFF=
fi
STEP_NAME=
STEP_NOTE=

say() { printf '%s\n' "$*" >&3; }
heading() { step_done; printf '%s%s%s\n' "$C_HEAD" "$1" "$C_OFF" >&3; }
# warn TEXT -- something the reader must see; into the log as well
warn() {
	echo "WARNING: $*"
	if [ -n "$STEP_NAME" ]; then STEP_WARN="$STEP_WARN$*
"; else printf '  %s! %s%s\n' "$C_WARN" "$*" "$C_OFF" >&3; fi
}
note() { STEP_NOTE=$*; }
step() {
	step_done
	STEP_NAME=$1
	STEP_NOTE=
	STEP_WARN=
	STEP_T0=$(date +%s)
	printf '\n==== %s ====\n' "$1"
	[ -n "$VERBOSE" ] || printf '  %-28s ' "$1" >&3
}
step_done() {
	[ -n "$STEP_NAME" ] || return 0
	_s=$(( $(date +%s) - STEP_T0 ))
	[ -z "$VERBOSE" ] || printf '  %-28s ' "$STEP_NAME" >&3
	[ "$_s" -gt 0 ] || _s="<1"
	printf '%s✓%s %3s s   %s\n' "$C_OK" "$C_OFF" "$_s" "$STEP_NOTE" >&3
	if [ -n "$STEP_WARN" ]; then
		printf '%s' "$STEP_WARN" | while IFS= read -r _w; do
			printf '    %s! %s%s\n' "$C_WARN" "$_w" "$C_OFF" >&3
		done
	fi
	STEP_NAME=
}
on_exit() {
	_rc=$1
	if [ "$_rc" -ne 0 ] && [ -n "$STEP_NAME" ]; then
		[ -z "$VERBOSE" ] || printf '  %-28s ' "$STEP_NAME" >&3
		printf '%s✗ FAILED%s\n' "$C_BAD" "$C_OFF" >&3
		if [ -z "$VERBOSE" ]; then
			printf '  ---- last lines of %s ----\n' "$LOG" >&3
			tail -n 25 "$LOG" | sed 's/^/  | /' >&3
		fi
		printf '%sBuild stopped.%s Full log: %s\n' "$C_BAD" "$C_OFF" "$LOG" >&3
	fi
}
trap 'on_exit $?' EXIT

# engine_warnings FILE -- the output of build_engine.sh: the expected
# warnings counted (vasm 22 once in Thalion's NUMERIC.S, vasm 58 four times
# from -align, vlink 62 once for <start>), any other shown.
engine_warnings() {
	_n22=$(grep -c '^warning 22 .*NUMERIC\.S' "$1" || true)
	_n58=$(grep -c '^warning 58 ' "$1" || true)
	_n62=$(grep -c '^warning 62:' "$1" || true)
	if [ "$_n22 $_n58 $_n62" != "1 4 1" ]; then
		warn "expected warnings changed: vasm 22 x$_n22, vasm 58 x$_n58, vlink 62 x$_n62 (1, 4, 1 expected)"
	fi
	_o=$(grep -E '^(error|warning) ' "$1" \
		| grep -v -E '^warning 58 |^warning 22 .*NUMERIC\.S|^warning 62:' || true)
	[ -n "$_o" ] || return 0
	# a here-document, not a pipe: warn must run in this shell
	while IFS= read -r _w; do warn "$_w"; done <<EOF
$_o
EOF
}

# summary -- the last lines, from the script that started the log only
summary() {
	step_done
	[ -n "$_AMBER_TOP" ] || return 0
	_s=$(( $(date +%s) - _AMBER_T0 ))
	_w=$(grep -c '^WARNING: ' "$LOG" || true)
	if [ -n "$VERBOSE" ]; then
		_w="warnings: see above"
	elif [ "$_w" -eq 0 ]; then
		_w="${C_OK}No warnings${C_OFF}"
	else
		_w="${C_WARN}$_w warning(s), see above${C_OFF}"
	fi
	say ""
	say "${C_OK}Done${C_OFF} in $((_s / 60)):$(printf '%02d' $((_s % 60))). $_w. YM music $YM_MUSIC; diagnostic switches: $DIAGNOSE."
	say "Full log: $LOG"
}

zeile() { printf '  %-20s %-9s %-15s %s\n' "$1" "$2" "($3)" "$4"; }

# Paths, without output.  Thalion's source (-I in build_engine.sh), the
# unconverted game files (the directory *above* Amberfiles/), and Big
# Alec's YM version, the SNDH file big_alec/ambermon.snd from the SNDH
# archive (optional).  tools/paths.py looks each up as every tool does:
# environment variable, then build.cfg, then the folder ambermoon_gamedata/
# next to the repository; X_SOURCE says which.
PFADE=$(python3 tools/paths.py --sh) || exit 1; eval "$PFADE"
AMBERFILES=$DATEN/Amberfiles
if [ -f "$YMSNDH" ]; then YM_MUSIC=on; else YM_MUSIC=off; fi
if [ -n "$VASM_EXTRA" ]; then
	DIAGNOSE="$VASM_EXTRA"
else
	DIAGNOSE="none (release build)"
fi

# prepare falcon|st|all -- check the sources, then everything taken from
# the original files at build time.  Under build_all.sh it runs once;
# _AMBER_PREPARED tells the two builds after it to skip it.
prepare() {
	[ -z "$_AMBER_PREPARED" ] || return 0
	case "$1" in falcon) _was=Falcon ;; st) _was=ST ;; *) _was="Falcon and ST" ;; esac
	heading "Ambermoon build: $_was -> $OUT/"
	step "Sources and switches"
	# Everything the build needs from outside, in one place: where it comes
	# from (environment variable, build.cfg or default) and whether it is
	# there.
	# Required sources stop the build; the YM SNDH is optional.
	if [ -f "$URCODE/GAME_OFF.S" ]; then
		zeile "Thalion's source" found "$URCODE_SOURCE" "$URCODE"
	else
		zeile "Thalion's source" MISSING "$URCODE_SOURCE" "$URCODE/GAME_OFF.S" >&2
		echo "Set AMBER_URCODE: as a variable, in build.cfg (template" >&2
		echo "build.cfg.example), or put it at that path." >&2
		exit 1
	fi
	if [ -f "$AMBERFILES/AM2_CPU" ]; then
		zeile "Game files" found "$DATEN_SOURCE" "$AMBERFILES"
	else
		zeile "Game files" MISSING "$DATEN_SOURCE" "$AMBERFILES/AM2_CPU" >&2
		echo "Set AMBER_DATEN, the directory above Amberfiles/: as a variable," >&2
		echo "in build.cfg (template build.cfg.example), or put it at that path." >&2
		exit 1
	fi
	# Set but missing is more likely a typo than intent: stop.
	if [ "$YM_MUSIC" = on ]; then
		zeile "YM SNDH" found "$YMSNDH_SOURCE" "$YMSNDH  -> YM music on"
	elif [ "$YMSNDH_SOURCE" != default ]; then
		zeile "YM SNDH" MISSING "$YMSNDH_SOURCE" "$YMSNDH" >&2
		echo "AMBER_YMSNDH is set ($YMSNDH_SOURCE) but the file is missing.  Fix or clear it." >&2
		exit 1
	else
		zeile "YM SNDH" missing default "$YMSNDH  -> YM music off, the YM stays silent"
	fi
	# m68k objdump for am2cpu_code.py, searched as there (am2cpu_lesen.objdump).
	GEFUNDEN=$(python3 -c 'import sys; sys.path.insert(0, "tools"); from am2cpu_lesen import objdump; print(objdump())') || exit 1
	case "$GEFUNDEN" in
		"$OBJDUMP") WOHER=$OBJDUMP_SOURCE ;;
		*/.vscode/*) WOHER=VS-Code ;;
		*) WOHER=PATH ;;
	esac
	zeile "m68k objdump" found "$WOHER" "$GEFUNDEN"
	# a56 for the DSP mixer, Falcon only (build_engine.sh checks it again).
	if [ "$1" != st ]; then
		if command -v a56 >/dev/null; then
			zeile "a56 (DSP mixer)" found PATH "$(command -v a56)"
		else
			zeile "a56 (DSP mixer)" MISSING PATH "sudo apt install a56" >&2
			exit 1
		fi
	fi
	zeile "Diagnostic switches" "" VASM_EXTRA "$DIAGNOSE"
	_found="Thalion's source, game files, objdump"
	[ "$1" = st ] || _found="$_found, a56"
	[ "$YM_MUSIC" = off ] || _found="$_found, YM SNDH"
	note "$_found"
	[ "$YM_MUSIC" = on ] || warn "no YM SNDH: the YM stays silent (AMBER_YMSNDH, docs/13)"
	[ -z "$VASM_EXTRA" ] || warn "diagnostic switches: $VASM_EXTRA (not a release build)"

	step "Library data from AM2_CPU"
	# At build time, never at run time (user, 2026-09-27): -> build/am2cpu_daten.i
	python3 tools/am2cpu_auszug.py
	# Where Thalion's text names lie in Text.amb (Lade_texte reads the texts
	# themselves at run time): -> build/textmarken.i
	python3 tools/textmarken.py
	# Thalion's 3D rasteriser (CPU versions), likewise at build time (user,
	# 2026-09-28; docs/02 A7): -> build/am2cpu_code.i
	python3 tools/am2cpu_code.py
	# The texts of the start menu from Ambermoon_intro: -> build/intro_daten.i
	python3 tools/intro_auszug.py
	note "data, code, text names, start menu -> build/"

	step "Constants against Thalion's"
	python3 tools/ambchest.py
	note "item offsets as in GAME_OFF.S"

	# The YM pieces from the SNDH (docs/13 6); delivered by deliver_data.
	rm -f build/MUSIK_YM.BIN
	if [ "$YM_MUSIC" = on ]; then
		step "YM music from the SNDH"
		python3 tools/ym_auszug.py --sndh "$YMSNDH" --out build/ym > build/ym_auszug.txt
		cp build/ym/AMBERYM.BIN build/MUSIK_YM.BIN
		note "MUSIK_YM.BIN $(( $(wc -c < build/MUSIK_YM.BIN) / 1024 )) KB"
	fi
	step_done
}

# deliver FILE DIR [DIR] -- copy one file and look whether it arrived.
#
# cp with several sources at once has twice silently left out a file on the
# mounted file system -- return value 0, target unchanged.  The first time
# the party then stood in a broken kitchen, and the search went in quite
# another direction.  So: one source per call, then compare.  Files that
# land in ATARI/ are recorded for the clean-up of the other build.
deliver() {
	for ziel in "$2" "$3"; do
		[ -n "$ziel" ] || continue
		cp "$1" "$ziel/$(basename "$1")"
		if ! cmp -s "$1" "$ziel/$(basename "$1")"; then
			echo "ERROR: $1 did not arrive in $ziel" >&2
			exit 1
		fi
		case "$ziel" in
			"$OUT"|"$OUT"/*) echo "${ziel#$OUT}/$(basename "$1")" | sed 's,^/,,' >> "$MANIFEST_NEW" ;;
		esac
	done
}

# clean_output falcon|st -- empty ATARI/ and ATARI/AMBFILES/ for a fresh
# delivery.  Copying only adds -- what is no longer delivered would stay
# (OBJECTS.AMF after the switch to Objects.amb) and travel onto the card.
# Kept: *.INF (desktop settings and AMBER.INF belong to the user) and the
# files the other build delivered.
clean_output() {
	case "$1" in falcon) ANDERE=st ;; *) ANDERE=falcon ;; esac
	MANIFEST=build/delivered_$1.txt
	MANIFEST_NEW=build/delivered_$1.new
	ANDERE_LISTE=build/delivered_$ANDERE.txt
	mkdir -p build "$DATA"
	: > "$MANIFEST_NEW"
	for f in "$OUT"/* "$DATA"/*; do
		[ -f "$f" ] || continue
		case "$f" in *.INF) continue ;; esac
		if [ -f "$ANDERE_LISTE" ] && grep -qxF "${f#$OUT/}" "$ANDERE_LISTE"; then
			continue
		fi
		rm -f "$f"
	done
}

# finish_output falcon|st -- keep the record, and say whether programs of
# the other machine from an older build lie next to it.
finish_output() {
	mv "$MANIFEST_NEW" "$MANIFEST"
	# Under build_all.sh the other build runs right next to it.
	if [ -z "$_AMBER_PREPARED" ] && [ -f "$ANDERE_LISTE" ]; then
		say "  Next to it: the $ANDERE programs from $(date -r "$ANDERE_LISTE" '+%Y-%m-%d %H:%M')" \
			"(tools/build_$ANDERE.sh renews them)"
	fi
}

# deliver_data -- the game files, the save games and the YM music into
# ATARI/AMBFILES/.
deliver_data() {
	# Unconverted original files, read at run time (goal 2).  Many
	# Amberfiles have longer names than a FAT file system holds; they are
	# renamed to 8.3 here.  The other side is the name table in
	# engine/src/HULL/FILES_SUP.S -- whoever changes something here must
	# change it there too.
	for paar in "Layouts.amb:LAYOUTS.AMB" \
	            "Dict.amb:DICT.AMB" \
	            "Automap_graphics:AUTOMAPG.DAT" \
	            "Object_icons:OBJICONS.DAT" \
	            "Button_graphics:BUTTONGF.DAT" \
	            "Text.amb:TEXT.AMB" \
	            "Objects.amb:OBJECTS.AMB" \
	            "1Map_data.amb:MAPDATA1.AMB" \
	            "2Map_data.amb:MAPDATA2.AMB" \
	            "3Map_data.amb:MAPDATA3.AMB" \
	            "1Map_texts.amb:MAPTEXT1.AMB" \
	            "2Map_texts.amb:MAPTEXT2.AMB" \
	            "3Map_texts.amb:MAPTEXT3.AMB" \
	            "Icon_data.amb:ICONDATA.AMB" \
	            "Pics_80x80.amb:PICS80.AMB" \
	            "Event_pix.amb:EVENTPIX.AMB" \
	            "Palettes.amb:PALETTES.AMB" \
	            "Music.amb:MUSIC.AMB" \
	            "NPC_char.amb:NPCCHAR.AMB" \
	            "Monster_char.amb:MONSTCHR.AMB" \
	            "Portraits.amb:PORTRAIT.AMB" \
	            "1Icon_gfx.amb:ICONGFX1.AMB" \
	            "2Icon_gfx.amb:ICONGFX2.AMB" \
	            "3Icon_gfx.amb:ICONGFX3.AMB" \
	            "Travel_gfx.amb:TRAVELGF.AMB" \
	            "NPC_gfx.amb:NPCGFX.AMB" \
	            "Object_texts.amb:OBJTEXTS.AMB" \
	            "Party_texts.amb:PARTYTXT.AMB" \
	            "NPC_texts.amb:NPCTEXT.AMB" \
	            "Place_data:PLACEDAT.DAT" \
	            "Stationary:STATIONR.DAT" \
	            "Party_gfx.amb:PARTYGFX.AMB" \
	            "2Lab_data.amb:LABDATA2.AMB" \
	            "3Lab_data.amb:LABDATA3.AMB" \
	            "2Wall3D.amb:WALL3D2.AMB" \
	            "3Wall3D.amb:WALL3D3.AMB" \
	            "2Object3D.amb:OBJ3D2.AMB" \
	            "3Object3D.amb:OBJ3D3.AMB" \
	            "2Overlay3D.amb:OVL3D2.AMB" \
	            "3Overlay3D.amb:OVL3D3.AMB" \
	            "Lab_background.amb:LABBACK.AMB" \
	            "Floors.amb:FLOORS.AMB" \
	            "Monster_groups.amb:MONSTGRP.AMB" \
	            "Combat_background.amb:COMBATBG.AMB" \
	            "Monster_gfx.amb:MONSTGFX.AMB" \
	            "Combat_graphics:COMBATGF.DAT" \
	            "Riddlemouth_graphics:RIDDLEGF.DAT" \
	            "Keymap:KEYMAP" \
	            "Intro_music:INTROMUS.DAT" \
	            "Extro_music:EXTROMUS.DAT"; do
		quelle=${paar%%:*}
		name=${paar##*:}
		if [ ! -f "$AMBERFILES/$quelle" ]; then
			echo "ERROR: $quelle is missing in $AMBERFILES" >&2
			exit 1
		fi
		cp "$AMBERFILES/$quelle" "build/$name"
		deliver "build/$name" "$DATA"
	done
	# Save games as in the original (AM2_CPU 1.20, finding 251): the five
	# working files in AMBFILES, SAVE.00 the template "new game", SAVE.01 to
	# SAVE.10 the slots.  Copies, not the originals: Save_subfile,
	# Get_saved_game and Put_saved_game (SPIELSTAND.S) write into them.  A
	# new build thus resets all save games.  The names are the same as in
	# FILES_SUP.S (dn_tabelle) and SPIELSTAND.S (sp_tabelle).
	for platz in 00 01 02 03 04 05 06 07 08 09 10; do
		mkdir -p "build/SAVE.$platz" "$DATA/SAVE.$platz"
	done
	for paar in "Chest_data.amb:CHESTDAT.AMB" \
	            "Party_data.sav:PARTYDAT.SAV" \
	            "Party_char.amb:PARTYCHR.AMB" \
	            "Merchant_data.amb:MERCHANT.AMB" \
	            "Automap.amb:AUTOMAP.AMB"; do
		quelle=${paar%%:*}
		name=${paar##*:}
		for platz in 00 01 02 03 04 05 06 07 08 09 10; do
			if [ ! -f "$AMBERFILES/Save.$platz/$quelle" ]; then
				echo "ERROR: Save.$platz/$quelle is missing in $AMBERFILES" >&2
				exit 1
			fi
			cp "$AMBERFILES/Save.$platz/$quelle" "build/SAVE.$platz/$name"
			deliver "build/SAVE.$platz/$name" "$DATA/SAVE.$platz"
		done
		# working file: the state "new game"
		cp "$AMBERFILES/Save.00/$quelle" "build/$name"
		deliver "build/$name" "$DATA"
	done
	# **Saves unchanged as in the original** (user, 2026-09-30): last save
	# game 0, so Thalion's Init_program puts up the character editor for a
	# new game (Chared_Mod, finding 261).
	cp "$AMBERFILES/Saves" build/SAVES
	deliver build/SAVES "$DATA"

	echo "-- YM music"
	# Big Alec's YM version (docs/13 6), for the ST and with MUSIC=YM in
	# AMBER.INF on the Falcon.  Only with the SNDH file (YMSNDH) does
	# MUSIK_YM.BIN come about; without it the YM stays silent and the build
	# goes on.  Never into the repository.
	if [ "$YM_MUSIC" = on ]; then
		deliver build/MUSIK_YM.BIN "$DATA"
		echo "  MUSIK_YM.BIN: $(wc -c < build/MUSIK_YM.BIN) bytes"
	else
		echo "  without the YM SNDH: no MUSIK_YM.BIN, the YM stays silent"
	fi
	# Which YM piece belongs to which of Thalion's numbers, MUSIK_YM.S reads
	# at run time.  *.INF survives the clean-up: if the user changed the
	# file, it stays.  The template only when there is none.
	if [ ! -f "$DATA/MUSIK_YM.INF" ]; then
		cp tools/musik_ym.inf build/MUSIK_YM.INF
		deliver build/MUSIK_YM.INF "$DATA"
	fi

	echo "-- Settings"
	settings_file
}

# settings_file -- AMBER.INF, the one settings file (E17, cut 2026-10-24).
# An old MUSIK.INF becomes AMBER.INF once (its first three letters, as
# MUSIK_SUP.S read them: AUS -> MUSIC=OFF, DSP, CPU, YM), then MUSIK.INF and
# ST.INF go: from the cut on no program reads them.  Without AMBER.INF the
# template tools/amber.inf; a changed AMBER.INF stays.
settings_file() {
	for ort in "$DATA" "$OUT"; do
		if [ -f "$ort/MUSIK.INF" ] && [ ! -f "$DATA/AMBER.INF" ]; then
			wahl=$(head -c 3 "$ort/MUSIK.INF" | tr a-z A-Z)
			case "$wahl" in
			AUS) wert=OFF ;;
			DSP|CPU) wert=$wahl ;;
			YM*) wert=YM ;;
			*) wert= ;;
			esac
			if [ -n "$wert" ]; then
				sed "s/^MUSIC=DSP /MUSIC=$wert /" tools/amber.inf > build/AMBER.INF
				deliver build/AMBER.INF "$DATA"
				echo "  $ort/MUSIK.INF ($wahl) -> AMBER.INF, MUSIC=$wert"
			fi
		fi
		for alt in MUSIK.INF ST.INF; do
			if [ -f "$ort/$alt" ]; then
				rm -f "$ort/$alt"
				echo "  removed $ort/$alt (read by no program since the E17 cut)"
			fi
		done
	done
	if [ ! -f "$DATA/AMBER.INF" ]; then
		cp tools/amber.inf build/AMBER.INF
		deliver build/AMBER.INF "$DATA"
		echo "  AMBER.INF: template delivered (MUSIC=DSP, PLAIN_ST=NO)"
	else
		echo "  AMBER.INF: kept, $(grep -v '^[;#]' "$DATA/AMBER.INF" | sed 's/[;#].*//' | tr -s ' \t\r\n' ' ')"
	fi
}

# build_loader -- AMBER.TOS, the same for both machines: reads the cookie
# _MCH and starts the fantasy intro, the intro, the engine and the extro of
# its machine one after the other (lader/lader.s).  68000 only.  Both
# builds deliver it, so either one alone leaves a complete ATARI/.
build_loader() {
	vasmm68k_mot -m68000 -Fvobj -quiet -o build/lader.o lader/lader.s
	vlink -b ataritos -s -N Lader_code .text -N Lader_daten .data \
		-N Lader_bss .bss -o build/AMBER.TOS build/lader.o
	deliver build/AMBER.TOS "$OUT"
}

# build_bomben -- BOMBEN.TOS shows after a crash what TOS put down from
# $380 and looks for the engine in memory (2026-10-02).  A tool, not part
# of the game; 68000, the same for both machines.
build_bomben() {
	vasmm68k_mot -m68000 -Ftos -quiet -o build/BOMBEN.TOS tools/bomben/bomben.s
	deliver build/BOMBEN.TOS "$OUT"
}

# source_checks -- the checks that read only our source, not a build.
# Under build_all.sh they run once, after the Falcon build.
source_checks() {
	step "Source checks"
	python3 tools/trap_pruefen.py
	python3 tools/register_pruefen.py
	python3 tools/vars_pruefen.py
	python3 tools/platzhalter_pruefen.py
	note "TOS calls, registers, variables, placeholders"
}

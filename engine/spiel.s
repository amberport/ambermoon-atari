; spiel.s -- die zweite Uebersetzungseinheit: Thalions Spieldateien
;
; **Thalion hat Bibliothek und Spiel getrennt uebersetzt.**  Die Dateien in
; HULL/ tragen XDEF/XREF (CONTROLS.S allein 77 XDEF), die Spieldateien nicht.
; Was eine HULL-Datei nicht exportiert, ist ihr privat -- und so kommt es,
; dass Thalions Quelltext zwei Namen doppelt definiert:
;
;     Number            MAIN.S und HULL/MODULE_C.S
;     Control_list_ptr  MAIN.S und HULL/CONTROLS.S
;
; In einer einzigen Einheit stossen sie zusammen, und Thalions Dateien
; aendern wir nicht.  Also zwei Einheiten wie im Original: engine.s
; ("Bibliothek": Thalions HULL/ und unsere Bibliotheksschicht, also das,
; was im Original AM2_CPU nicht freigab) und diese hier ("Spiel": **alle
; uebrigen Dateien Thalions**, seit Stufe (c), 2026-09-27).  Ausgelassen ist
; nur FAIRY.S (Amiga-Hardware, nicht Teil des Spiels).
;
; Die XDEF-Listen schreibt tools/einheiten_verbinden.py: es liest aus dem
; Listing jeder Einheit, was sie definiert und was ihr fehlt, und exportiert
; genau das, was die andere braucht.  Ein Name, der in beiden Einheiten
; definiert ist, bricht den Bau ab -- sonst gaebe es still zwei Variablen,
; und Thalions Code schriebe in eine andere, als unser Code liest.
; Ausgenommen sind nur die beiden oben, weil sie es im Original ebenso sind.
;
; **Mit einem Namen aus der anderen Einheit rechnet vasm nicht** ("#Name/2-1"
; geht nicht).  Wer eine Konstante von hier in engine.s braucht, nimmt unsere
; gleichwertige aus FALCON_OFF.S; dass beide uebereinstimmen, prueft das
; Ende dieser Datei.
; ---------------------------------------------------------------------------

	INCLUDE	"vorspann.i"

	SECTION	Program,code

	INCLUDE	"GAME_OFF.S"		; Thalions, ueber -I gefunden
	INCLUDE	"src/FALCON_OFF.S"	; unsere Konstanten, nur fuer die Probe unten

; Alle uebrigen Dateien Thalions, unveraendert.  Was sie gemeinsam von
; aussen brauchen, ist genau die Bibliothek aus AM2_CPU (tools/vollprobe.py);
; sie steht in engine.s, echt oder als Platzhalter (HULL/AM2_CPU_STUBS.S).
; Nach jeder Datei SECTION Program,code, weil Thalions Dateien im BSS enden.
	INCLUDE	"MAIN.S"		; Thalions, ueber -I gefunden
	SECTION	Program,code
	INCLUDE	"AUTOMAPP.S"
	SECTION	Program,code
	INCLUDE	"CHARACTE.S"
	SECTION	Program,code
	INCLUDE	"COMBAT/APRES.S"
	SECTION	Program,code
	INCLUDE	"COMBAT/COMBAT.S"
	SECTION	Program,code
	INCLUDE	"COMBAT/COMBAT_M.S"
	SECTION	Program,code
	INCLUDE	"COMBAT/COMOBS.S"
	SECTION	Program,code
	INCLUDE	"COMBAT/MONSTER_.S"
	SECTION	Program,code
	INCLUDE	"COMBAT/REVERSE_.S"
	SECTION	Program,code
	INCLUDE	"COMBAT/TACTIC.S"
	SECTION	Program,code
	INCLUDE	"DIAGNOST.S"
	SECTION	Program,code
	INCLUDE	"DIALOGUE.S"
	SECTION	Program,code
	INCLUDE	"DISPLAY.S"
	SECTION	Program,code
	INCLUDE	"EVENTS.S"
	SECTION	Program,code
	INCLUDE	"INVENTOR.S"
	SECTION	Program,code
	INCLUDE	"MAGIC.S"
	SECTION	Program,code
	INCLUDE	"MAP/2D_CITY.S"
	SECTION	Program,code
	INCLUDE	"MAP/2D_MAP.S"
	SECTION	Program,code
	INCLUDE	"MAP/2D_WILD.S"
	SECTION	Program,code
	INCLUDE	"MAP/3D_MAP.S"
	SECTION	Program,code
	INCLUDE	"MAP/MAP.S"
	SECTION	Program,code
	INCLUDE	"MINIMAP.S"
	SECTION	Program,code
	INCLUDE	"MODULES.S"
	SECTION	Program,code
	INCLUDE	"PERSONS.S"
	SECTION	Program,code
	INCLUDE	"PLACES.S"
	SECTION	Program,code
	INCLUDE	"TIME.S"
	SECTION	Program,code
	INCLUDE	"WORD_SEL.S"
	SECTION	Program,code

; Thalions ACTIONS.S, zuletzt, wegen des Schalters:
;
; **"opt t-" gilt nur fuer diese Datei**, wegen einer einzigen Zeile:
;
;     btst d0,#Stationary_mask     ; ACTIONS.S:128, Maske %0000011000001110
;
; Der Sofortoperand von btst ist ein Byte.  Thalions Assembler hat $0E
; daraus gemacht -- AM2_CPU traegt an dieser Stelle 013C 000E, hinter
; "cmp.w #0,d0 / cmp.w #7,d0".  Das ist auch richtig: btst auf ein Byte
; nimmt die Bitnummer modulo 8, und die Bits 9 und 10 der Maske treffen so
; Bit 1 und 2 von $0E.  vasm lehnt den Wert ab (Fehler 2037), mit "opt t-"
; erzeugt es dieselben Bytes wie Thalion.  Weil "opt t-" jede
; Bereichspruefung abschaltet, uebersetzt tools/engine_uebersetzen.sh diese
; Einheit ein zweites Mal mit -DTYPPROBE (ohne "opt t-") und verlangt genau
; diesen einen Fehler.
	IFND	TYPPROBE
	opt	t-
	ENDC
	INCLUDE	"ACTIONS.S"		; Thalions, ueber -I gefunden
	opt	t+
	SECTION	Program,code

; ***************************************************************************
; Gegenprobe: Thalions Party_data gegen unsere PD_*-Versaetze.
;
; Party_data *ist* der Spielstand (Party_data.sav), unser Code liest ihn ueber
; p_party und PD_*, Thalions ueber die Marken.  Bis zum rseven-Fehler in
; vorspann.i (Erkenntnis 180) lagen die Marken ab Quest 32 Byte daneben --
; genau das faengt diese Probe.
; ***************************************************************************
	pruefe	PD_SIZE,Party_data_size
	pruefe	PD_MAP,Map_nr-Party_data
	pruefe	PD_X,Map_Xcoord-Party_data
	pruefe	PD_Y,Map_Ycoord-Party_data
	pruefe	PD_DIR,View_direction-Party_data
	pruefe	PD_NMEM,Nr_members-Party_data
	pruefe	PD_ACTIVE,Active_member-Party_data
	pruefe	PD_MEMBER,Member_nrs-Party_data
	pruefe	PD_QUEST,Quest-Party_data
	pruefe	PD_EVENT,Event-Party_data
	pruefe	PD_CD,CD-Party_data
	pruefe	PD_WD,WD-Party_data
	pruefe	PD_GOTO,Goto_points-Party_data
	pruefe	PD_CHEST,Chest_open-Party_data
	pruefe	PD_DOOR,Door_open-Party_data
	pruefe	PD_ORDER,Order-Party_data

	INCLUDE	"xdef_spiel.i"		; von tools/einheiten_verbinden.py

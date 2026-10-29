; ***************************************************************************
; FALCON_OFF.S -- **unsere** Konstanten und Variablenbelegung
;
; **Das hier ist nicht Thalions GAME_OFF.S.**  Diese Datei hiess bis
; 2026-09-12 ebenso, und das war eine Falle: engine.s bindet *beide* ein --
;
;	INCLUDE	"GAME_OFF.S"		; Thalions, ueber -I gefunden
;	INCLUDE	"src/FALCON_OFF.S"	; unsere Ergaenzungen
;
; -- die erste liegt ausserhalb des Repositoriums unter AMBER_URCODE und
; wird **nie** angefasst (Leitziel 1), die zweite ist unsere.  Bei gleichem
; Namen unterschied sie nur der Pfad, und wer den ueberliest, aendert die
; falsche.  Darum der eigene Name.
;
; Was hier steht, ist das, was Thalions Datei nicht hat, weil es sie nichts
; angeht: die Falcon-Seite.  Bildschirmmasse und VIDEL-Moduswort,
; Palettenbaenke, Fenstermasse, Kachelflags, GEMDOS-/XBIOS-Nummern und die
; a5-relative Belegung *unserer* Variablen.
;
; Wo ein Wert aus dem Original stammt, nennt der Kommentar daneben den
; Namen, unter dem er dort steht.  Am Ende der Datei steht die Gegenprobe:
; sie stellt unsere abgeschriebenen Versaetze gegen die eingebundenen
; Originalsymbole, sodass ein Abschreibfehler den Bau bricht statt das Bild.
;
; Der Abschnitt heisst wie bei Thalion: jede seiner Dateien schliesst mit
; "SECTION Program,code", "SECTION Fast_DATA,data", "SECTION Fast_BSS,bss".
; baue_alles.sh bildet die drei mit vlinks -N auf .text/.data/.bss ab.
; ***************************************************************************

	SECTION	Program,code
	XDEF	start

; ---- Aufrufe von TOS (Erkenntnis 270) ----
; GEMDOS (trap #1), BIOS (#13) und XBIOS (#14) duerfen d0-d2 und a0-a2
; zerstoeren.  EmuTOS und Hatari lassen sie meist stehen, der echte Falcon
; mit TOS 4.04 nicht: Speicher_holen schrieb nach Mxalloc ueber ein
; zerstoertes a0 ins ROM, zwei Bomben (2026-10-02).  Darum ruft unser Code
; TOS nur ueber diese Makros.  Sie retten d1-d2/a0-a2 und holen sie zurueck;
; d0 bringt das Ergebnis, die Flags bleiben die des Traps (movem aendert sie
; nicht).  Gerettet wird in einen festen Platz, weil die Argumente schon auf
; dem Stapel liegen; das geht, weil nichts von uns waehrend eines Traps TOS
; ruft (kein Supexec, im Interrupt kein TOS).  baue_alles.sh bricht ab,
; wenn unser Code einen dieser Traps nackt benutzt (trap_pruefen.py).
Gemdos	MACRO
	movem.l	d1-d2/a0-a2,Tos_rette
	trap	#1
	movem.l	Tos_rette,d1-d2/a0-a2
	ENDM
Bios	MACRO
	movem.l	d1-d2/a0-a2,Tos_rette
	trap	#13
	movem.l	Tos_rette,d1-d2/a0-a2
	ENDM
Xbios	MACRO
	movem.l	d1-d2/a0-a2,Tos_rette
	trap	#14
	movem.l	Tos_rette,d1-d2/a0-a2
	ENDM

; ---- GEMDOS ----
Cconws  = 9
Cconin  = 1
Fopen   = $3D
Fread   = $3F
Fcreate = $3C
Fwrite  = $40
Fclose  = $3E
Fseek   = $42
; Fsfirst fills the DTA with the directory entry; the file length is at
; offset 26.  Datei_lesen requests a whole file at its exact size with it.
; Load_subfile seeks to its entry with Fseek (Eintrag_suchen, FILES_SUP.S).
Fgetdta = $2F
Fsetdta = $1A
Fsfirst = $4E
DTA_LEN = 26			; .l Dateilaenge im DTA-Satz
Malloc  = $48
Mfree   = $49
Mxalloc = $44			; wie Malloc, aber mit Wahl der Speicherart
Mshrink = $4A
Pterm0  = 0
Pterm   = $4C			; mit Rueckgabewert (Wort)
Super   = $20
Bconstat = 1
Bconin  = 2
Kbshift = 11			; BIOS 11: Umschalttasten (-1: nur lesen)
Setexc  = 5			; BIOS 5: Ausnahmevektor setzen (-1: nur lesen)
ETV_TERM = $102			; Setexc-Nummer von etv_term ($408): ruft Pterm
Vsync   = 37

; ---- XBIOS ----
Physbase = 2
Setscreen = 5			; XBIOS 5: Bildschirmadressen und Modus setzen
screenpt = $45E			; Systemvariable: neue Videobasis fuer den naechsten VBL
VIDEO_BASE_H = $FFFF8201	; Videobasis, oberes, mittleres, unteres Byte
VIDEO_BASE_M = $FFFF8203	; (Falcon/STE; das untere erst seit dem STE,
VIDEO_BASE_L = $FFFF820D	; beim Schreiben von H/M wird es geloescht)
Kbdvbase = 34
Ikbdws   = 25
VsetMode = 88
VsetRGB  = 93
VgetRGB  = 94
EsetPalette = 84
EgetPalette = 85

; Videl: Farbtiefe und Spaltenzahl setzen, Monitorbits behalten
BPS8    = 3
COL40   = 0
; Beim Moduswechsel nur die Monitorbits uebernehmen: VGA, PAL, Overscan und
; vertikal.  Zwei Bits muessen dabei weg:
;
; Bit 3 (COL80).  Bleibt es stehen, ist der Bildschirm 640 Byte je Zeile
; breit, das 320 Byte breite Bild erscheint doppelt nebeneinander und die
; untere Haelfte bleibt Muell.
;
; Bit 7 (STMODES).  Es sagt, dass VIDEL die Bilddaten ST-vertraeglich lesen
; soll, und das vertraegt sich nicht mit acht Ebenen.  Wer aus einem
; 16-Farb-Desktop startet, der ST-vertraeglich laeuft, erbt das Bit und
; bekommt STMODES zusammen mit BPS8 -- einen Modus, den es nicht gibt.  Das
; Bild sieht dann genauso aus wie beim vergessenen COL80.  Aus einem
; Desktop mit 256 Farben faellt es nicht auf, weil dort STMODES nicht
; gesetzt ist.
;
;     $092  STMODES + VGA + BPS4   ein 16-Farb-Desktop
;     $093  STMODES + VGA + BPS8   daraus mit der alten Maske: ungueltig
;     $013            VGA + BPS8   daraus mit dieser Maske: richtig
;
; Die einzelnen Bits, benannt statt gerechnet:
MD_VGA      = $010		; Bit 4: gesetzt = VGA, geloescht = RGB/TV
MD_PAL      = $020		; Bit 5
MD_OVERSCAN = $040		; Bit 6
MD_STMODES  = $080		; Bit 7  (muss weg, siehe oben)
MD_VERTFLAG = $100		; Bit 8: Zeilenverdopplung
MODEMASK = MD_VGA+MD_PAL+MD_OVERSCAN+MD_VERTFLAG	; = $170

; ***************************************************************************
; **Die Monitorbits gehoeren dem Monitor, nicht uns.**
;
; MODEMASK uebernimmt aus oldmode -- dem Modus, in dem der Rechner gerade
; laeuft -- vier Bits, und alle vier haengen am *angeschlossenen* Geraet:
;
;   MD_VGA       Zeitbasis: gesetzt 31 kHz (VGA), geloescht 15 kHz (RGB/TV)
;   MD_VERTFLAG  an VGA die Zeilenverdopplung, die 200 Zeilen auf einen
;                400-zeiligen Schirm bringt; an TV waere es Interlace
;   MD_PAL       Bildnorm
;   MD_OVERSCAN  Rand (an VGA ohnehin ungueltig)
;
; Der Falcon zeigt ST-vertraegliche Aufloesungen **an beiden** Monitorarten --
; ST Low, Medium und High laufen an VGA wie am SC1224.  Erbt man die Bits,
; laeuft dasselbe Programm ueberall; nagelt man eine Zeitbasis fest, sperrt
; man die halbe Anwenderschaft aus.
;
; **Das ist hier schon passiert.**  Vom 2026-09-12 bis 2026-09-13 stand hier
; ein MODEMASK_RGB, das MD_VGA und MD_VERTFLAG *loeschte* und damit 15 kHz
; erzwang.  Die Begruendung hatte drei Gruende, und keiner hat gehalten:
;
;   1. "RGB ist die ST-vertraegliche Zeitbasis."  Stimmt, ist aber kein Grund:
;      der Falcon kann ST-Aufloesungen auch an VGA, per Zeilenverdopplung.
;   2. "Der STE kann nur RGB."  Stimmt ebenfalls -- betrifft aber einen
;      eigenen Bau (PLANES=4, andere Hardwareschicht), nicht diesen hier.
;      Der Falcon-Bau muss sich dafuer nicht beschneiden.
;   3. "Timer-B-Raster sind auf Falcon-VGA unzuverlaessig."  Der Emulator-
;      befund dahinter war untauglich (Hatari zeichnet Falcon-Bilder mit nur
;      einer Palette, Erkenntnis 150).  Und die Demoszene macht zeilengenaue
;      Palettenwechsel auf dem Falcon sehr wohl -- mit Jitter-Vorbehalt, auf
;      VGA mehr als an RGB, aber sie gehen.
;
; Einzelheiten in Erkenntnis 152.  Kurz: erben, nicht setzen -- except PAL
; at RGB.
;
; **Exception since 2026-10-25 (T65):** at RGB Open_screen (FALCON.S) sets
; MD_PAL (50 Hz), because Thalion counts VBLs for 50 Hz; VGA keeps its
; mode, it has no 50 Hz.  The time base (MD_VGA) and the line doubling
; (MD_VERTFLAG) stay inherited.
;
; **Zur Monitorerkennung**, falls sie je gebraucht wird: $FF8006 Bit 7-6
; meldet den angeschlossenen Monitor (00 mono, 01 RGB, 10 VGA, 11 Fernseher).
; Wir brauchen sie nicht -- oldmode traegt die Antwort bereits.
; ***************************************************************************

SCRW    = 320
SCRH    = 200

; PLANES ist die Tiefe unseres Schirms, 8 fuer den Falcon, 4 fuer den STE.
; Der Schalter steht in vorspann.i (Schirm_ebenen), damit Bytes_per_line
; denselben Wert sieht.  Alles Groessenmaessige haengt daran.
;
; **PLANES ist nicht Screen_depth.**  Thalions Screen_depth bleibt 5 und
; meint den Aufbau seiner Daten (Erkenntnis 191); bis 2026-09-28 galten
; beide als dieselbe Zahl.
;
; **Die Zahl allein genuegt nicht.**  Was nicht mitwandert, ist der Code in
; HULL/FALCON.S: VsetRGB und VsetMode gibt es auf dem ST nicht.  Genau
; deshalb steht er in einer eigenen Datei.
PLANES  = Schirm_ebenen
SCRROW  = SCRW*PLANES/8			; 320 Byte je Zeile
SCRSZ   = SCRROW*SCRH			; 64000

; ***************************************************************************
; **Die Hardwareweiche: im Raum oder in der Zeit?**
;
; Thalions Rasterlisten verlangen *gleichzeitig* zwei verschiedene Paletten --
; Map_RL legt oben Main_pal auf (die graue Rampe der Bedienoberflaeche) und ab
; Middle_Y+1 Current_pal (die Kartenpalette).  Der Amiga macht das mit dem
; Copper, also in der **Zeit**.  Dafuer gibt es genau zwei Wege:
;
;   RASTER_RAUM (= 0)   Jede Palette bekommt eine eigene **Farbbank** in den
;                       256 Farben des Falcon; gezeichnet wird mit einem
;                       Farbversatz je Bildbereich.  Braucht 8 Ebenen und
;                       macht Thalions Farbnummern unbrauchbar, kommt aber
;                       **ohne Interrupt** aus.
;
;   RASTER_ZEIT (= 1)   Ein Timer-B-Rasterinterrupt schreibt die Farbregister
;                       an den Zeilengrenzen um (HULL/RASTER.S).  Dann
;                       genuegen die **32 Farben des Originals**, Thalions
;                       Farbnummern gelten woertlich, und 5 Ebenen reichen --
;                       auf dem STE der einzig gangbare Weg.
;
; **Stand der Messung (2026-09-13, echter Falcon030, RGB):**
;
;   Timer B **zaehlt die Bildzeilen**.  tools/rastertest/TIMERB.TOS misst
;   ueber zwei Sekunden 100 VBL-Aufrufe und 198 Timer-B-Aufrufe, also zwei je
;   Bild -- erwartbar, weil der Timer nach dem Feuern TBDR neu laedt und bei
;   rund 200 sichtbaren Zeilen mit TBDR=100 zweimal drankommt.
;
;   Ein frueherer Kommentar an dieser Stelle schloss aus dem Engine-Pruefband
;   ("Bild schwarz, beim Verlassen kurz rot"), Timer B zaehle keine
;   Bildzeilen.  Das war falsch geraten: dasselbe Bild entsteht auch bei
;   falsch abgearbeiteter Liste.  Siehe Erkenntnis 154.
;
; **Der Fehler steckt also in HULL/RASTER.S**, nicht im Timer und nicht im
; VIDEL.  Der Falcon faehrt bis auf weiteres trotzdem RASTER_RAUM -- das ist
; der laufende, funktionierende Zustand --, aber der Weg nach RASTER_ZEIT ist
; offen und nicht mehr durch die Hardware versperrt.
;
; **Seit 2026-09-15 arbeitet RASTER.S mit Zeilenzaehler** (Erkenntnis 155):
; TBDR=1, ein Interrupt je Zeile, der Timer wird im Interrupt nie
; umprogrammiert.  Damit ist der naheliegendste Verdaechtige aus der Vorfassung
; weg -- dort wurde der Timer in jedem Interrupt angehalten, TBDR neu gesetzt
; und wieder gestartet.  Verblieben sind:
;   * fremde Palettenschreiber -- Bank0_setzen (FALCON_LIB.S, je Blendschritt
;     Farben 0-31) und Set_palette (MAIN.S, alle 256 Farben), beide
;     ueberschreiben, was der Raster gesetzt hat;
;   * der Zeitpunkt des Scharfmachens spaet in der VBL-Warteschlange, der
;     einen Versatz oder ein Zittern erzeugen kann (RASTER_VERSATZ).
;
; **Offen, bevor jemand umschaltet:** Die gemessene Zeile war 81 bei SOLL 100,
; mit einer Spanne von 81 bis 131.  Die Spanne vermischt das Zittern des
; ersten Feuerns mit der Lage des zweiten; das Programm trennt beides noch
; nicht.  Ein stabiler Versatz waere harmlos (einmal ausmessen und abziehen),
; ein Zittern von +-25 Zeilen waere fuer einen Palettenwechsel unbrauchbar.
; Das ist zu klaeren, bevor R3 auf dem Raster aufsetzt.
;
; **Wer die Weiche umlegt, muss an diese Stellen:**
;   FALCON_OFF.S       PLANES (8 -> 5) und dieser Schalter
;   MAIN.S             Raster_liste_setzen aus dem Moduldeskriptor rufen
;                      (Raster_list_ptr, MODULES.S: Map_RL/Main_RL/Inv_RL)
;   HULL/FADE_SUP.S    Set_fade fills one bank per R_palette (Platzbank,
;                      finding 264); the time version has one palette only
;                      (Paletten_ableiten, named here before, is gone)
;   tools/falcon_gfx.py  die Bankversaetze in den Grafikdaten
;   Put_unmasked_block   der Farbversatz d4 je Aufrufstelle
; ***************************************************************************
RASTER_RAUM	equ	0		; Farbbaenke, 256 Farben -- Falcon heute
RASTER_ZEIT	equ	1		; Timer-B-Raster, 32 Farben -- STE-Weg
RASTER_VERFAHREN equ RASTER_RAUM

TILE    = 16
TROW    = TILE*PLANES/8			; 16 Byte je Kachelzeile

; One mouse pointer image, widened to our screen depth (AREAS.S).
MPTR_SIZE = (16/16)*PLANES*2*16		; 256

; The frame counter of TOS.  It runs with the display refresh, like the
; Amiga's VBL counter, and is therefore the measure for everything counted
; in frames.
FRCLOCK = $466

; A chest entry in Chest_data.amb: 24 object packets of 6 bytes, then gold
; and food as words.  Checked against Thalion's names at the end of the file.
CH_SLOTS = 24
CH_PKT   = 6			; size of an object packet
CH_GOLD  = CH_SLOTS*CH_PKT	; 144

; Bank 2, Farbe 64..95: der erste Platz jeder Rasterliste, bei Thalion
; immer Main_pal -- die Leiste ueber der Karte.  Eine Bank je Platz
; (Platzbank in FADE_SUP.S, Erkenntnis 264); mehr als drei R_palette hat
; keine Liste Thalions (Combat_RL hat drei).
MAIN_BANK = 64
PLAETZE = 3

; SCHIRM_FORMAT -- ein d5 dieses Werts sagt den Blockroutinen: die Quelle
; liegt schon im Schirmformat (PLANES Ebenen, wortverschraenkt).  Thalions
; Code schickt hoechstens 5.  Beim Falcon ist das PLANES; beim ST (PLANES =
; 4) waere PLANES von Thalions d5 = 4 nicht zu unterscheiden, darum ein
; eigener Wert.
SCHIRM_FORMAT = 8

; The font entry: +0 number of characters, +2 bytes per character,
; +4 advance, +6 line spacing, +8 translation table (256 bytes, indexed
; with ASCII-32), +264 the characters themselves.
FONT_TAB = 8
FONT_GLY = 8+256
FONT_NONE = $ff			; table value "no character"

; Default_shadow aus GAME_OFF.S ist 0.  Der Schatten liegt um ein Pixel nach
; rechts und unten versetzt unter der Schrift; -1 schaltet ihn ab, so macht
; es DISPLAY.S beim Kompass.
DEFAULT_SHADOW = 0

; ***************************************************************************
; Der Spielstand.  Aufbau nach "Party_data:" in MAIN.S; die Offsets sind
; nachgerechnet und am mitgelieferten Stand geprueft.  Die acht Bitfelder
; darin sind der eigentliche Zustand des Spiels: welche Ereignisse gelaufen
; sind, welche Truhen offen, welche Charaktere entfernt.
; ***************************************************************************
PD_SIZE   = 13802
PD_MAP    = 10		; Kartennummer
PD_X      = 12
PD_Y      = 14
PD_DIR    = 16
PD_NMEM   = 42		; Nr_members
PD_ACTIVE = 44
PD_MEMBER = 46		; sechs Woerter
PD_QUEST  = 260
PD_EVENT  = 1284
PD_CD     = 9476
PD_WD     = 13572
PD_GOTO   = 13700
PD_CHEST  = 13732
PD_DOOR   = 13764
PD_ORDER  = 13796

; The mouse pointer is 16 by 16 pixels.
MPTR_W  = 16
MPTR_H  = 16
; Ein Zeigersatz je Schirm (zeiger_saetze in engine.s, Doppelpuffer B1a).
ZS_BG   = 0				; .l  gesicherter Hintergrund
ZS_X    = 4				; .w  Ecke, wie Zeigerecke
ZS_Y    = 6				; .w
ZS_DA   = 8				; .b  gezeichnet
ZS_SIZE = 10
; One screen with its border lines (SCHIRM_RAND, per machine in vorspann.i).
SCHIRM_BLOCK = SCRROW*(SCRH+2*SCHIRM_RAND)	; ein Schirm samt Rand

; Groesse des Puffers fuer den aufbereiteten Text.  Der laengste Kartentext
; hat gut 600 Zeichen; je Zeile kommen ein Tintenbyte und ein Nullbyte dazu.
PROCBUF = 2048

; The control icons are a game file: Button_graphics, 78 icons of 156 bytes
; (Thalion's 13*12: 32 pixels, three planes, 13 lines), read at run time
; and copied unchanged to Control_icons (Leitziel 2).
CI_H   = 13			; icon height
CI_PLANES = 3
CI_ROH_LEN = 32/8*CI_PLANES*CI_H	; 156 Byte je Symbol -- Thalions 13*12

; ***************************************************************************
; The a5 variable block.  The offsets are given by hand; vars_pruefen.py
; reports two variables on the same place and anything beyond vars_size.
;
; Der Variablenblock.  Er muss groesser sein als der hoechste Offset:
; v_step lag bei 256 und damit genau einen Platz zu hoch -- geschrieben
; wurde in die zwei Byte dahinter, und dort faengt laut engine.s der Stack
; an.  Aufgefallen waere das erst, wenn der Stack einmal tief genug
; gewachsen waere, also vermutlich an ganz anderer Stelle.
; ***************************************************************************
vars_size = 512
oldmode = 24
oldssp  = 28
p_font  = 146
txt_x   = 150
txt_y   = 152
p_txt   = 154
v_colour = 200
mouse_dr = 220			; Zeiger steht gerade auf dem Bildschirm
p_mptr  = 222			; Zeigerbild
p_mmsk  = 226			; Zeigermaske
p_kbd   = 230			; Kbdvbase
oldmvec = 234			; alter Mausvektor

; The screens are our own, not the one of TOS: nobody says how large its
; memory is -- with a 16-colour desktop it is half the 64000 bytes we write.
p_tos   = 258			; Bildschirm von TOS, zum Zurueckschalten
p_scrr  = 262			; unausgerichtete Adresse, zum Freigeben

; ---- ab hier neu vergeben ----
;
; Die Liste oben ist nach Themen geordnet, nicht nach Zahlen; wer einfach
; hinten anhaengt, landet mitten in einem belegten Bereich.  Genau das ist
; passiert: v_sit bekam 258 und lag auf p_tos, der Adresse des
; TOS-Bildschirms -- beim Beenden schaltete die Engine dorthin zurueck und
; schrieb stattdessen die Sitzhaltung ins Videoregister.
; tools/vars_pruefen.py sucht das jetzt bei jedem Bau.

; Wie viele Farben der Modus des Desktops traegt.  Nur so viele werden von
; VIDEL gesichert und zurueckgeschrieben; 0 heisst Echtfarbe.
v_farbzahl = 332

; Die Bereichsstapel -- HULL/AREAS.S.  Nur die Zeiger stehen hier; die
; Ebenen selbst liegen als eigene Felder im BSS, sie sind zu gross fuer
; diesen Block.
v_masp   = 454			; Ebene der Mouse-Area
v_mpsp   = 456			; Ebene des Mauszeigers

; ***************************************************************************
; Cross-check against Thalion's GAME_OFF.S
;
; engine.s includes Thalion's file, so its symbols are at hand, and the
; values we took over by hand can be checked against them.  If one differs,
; the build stops and names it.  A wrong offset taken over by hand once cost
; 402 items their flag bits (Item_bits_STATIC one byte off, finding 116).
; Only what describes the same thing is checked.
; ***************************************************************************

pruefe	macro
	IFNE	\1-(\2)
	FAIL	"\1 weicht von Thalions \2 ab"
	ENDC
	endm

	pruefe	CH_PKT,Object_packet_size
	pruefe	CH_SLOTS,Items_per_char
	pruefe	DEFAULT_SHADOW,Default_shadow

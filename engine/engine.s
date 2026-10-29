; engine.s -- Ambermoon auf dem Atari Falcon030
;
; Diese Datei bindet nur ein.  Der Code liegt in src/ und ist dort so auf
; Dateien verteilt, wie ihn Thalion abgelegt hat -- gleiche Namen, gleiche
; Verzeichnisse, und die Routinen tragen die Namen des Originals.  Wer eine
; Stelle im Quelltext von Thalion findet, findet sie hier an derselben.
;
; Die Reihenfolge ist nicht beliebig: GAME_OFF.S bringt die Konstanten mit
; und erzeugt keinen Code, danach muss MAIN.S folgen, weil start der
; Einsprungpunkt am Anfang des Programms sein muss.
;
; **Seit Stufe (c) (2026-09-27) ist das hier nur noch die Bibliothek**:
; Thalions HULL/ und unsere Schicht, also was im Original AM2_CPU enthielt.
; Alle uebrigen Dateien Thalions stehen in spiel.s, und der Nachbau (unsere
; Hauptschleife, Karte, Personen, Moduldeskriptoren) ist geloescht.
;
; **Zwei Sorten, sichtbar am Pfad.**  Ohne Verzeichnis davor -- wie
; "GAME_OFF.S" -- ist es Thalions Datei, von vasm ueber -I ausserhalb des
; Repositoriums gefunden und **unveraendert** (Leitziel 1).  Mit "src/"
; davor ist es unsere.  Unsere Ergaenzung zu GAME_OFF.S hiess frueher
; ebenso und heisst seit 2026-09-12 src/FALCON_OFF.S, damit der Unterschied
; nicht mehr am Pfad allein haengt.

; ---------------------------------------------------------------------------
; Thalions eigener Quelltext, unveraendert eingebunden.
;
; GAME_OFF.S ist die Datei, mit der das anfangen muss: 1850 Zeilen, **kein
; Befehl darin** -- nur rsreset-Ketten und Konstanten.  Sie beschreibt jede
; Struktur des Spiels: den Charaktersatz, das Objektpaket, die Karten, die
; Ereignisse, die Farben der Hauptpalette.  955 Symbole.
;
; Bisher habe ich diese Versaetze einen nach dem anderen von Hand
; nachgeschlagen und abgeschrieben, und genau dabei sind Fehler entstanden
; (Item_bits_STATIC lag ein Byte daneben, Erkenntnis 116).  Ab jetzt steht
; die Wahrheit im Bau.
;
; Zwei Dinge machen das moeglich:
;   vorspann.i  ersetzt die nicht freigegebene Bibliotheks-Includedatei --
;               Get, Free, Push, Pop, LOCAL, Screen_depth und die Konstanten
;               des Bildaufbaus.  Thalions Dateien bleiben unangetastet.
;   vlink       schreibt die Verschiebetabelle, ohne die Thalions Tabellen
;               mit ihren 441 "dc.l <Label>" nicht laufen (Erkenntnis 122).
;
; Es gibt keine einzige Namenskollision: 955 Symbole von Thalion, 941 von
; uns, kein Ueberschneiden -- seine sind englisch, unsere deutsch.
;
; Die Datei liegt nicht im Repository.  Wo sie liegt, sagt AMBER_URCODE;
; baue_alles.sh reicht das als -I an vasm weiter.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; **Thalions Dateien sind der Normalbau** (docs/05, A5, 2026-09-25).
;
; Sein Inventaraufbau, seine CONTROLS.S, sein Modulstapel und seine WORDS.S
; liefen bis hierher hinter Schaltern (INV2_VERFAHREN, CONTROLS_THALION,
; MODULE_C_THALION, WORDS_THALION) neben unseren gleichnamigen Nachbauten.
; Die Schalter sind aufgeloest und die Nachbauten geloescht; wer einen der
; alten Namen sucht, findet ihn in der Git-Geschichte vor diesem Datum.
;
; Bekannte Einbusse: der Mengendialog (InputNr_Mod, ein Local_mod) ist tot,
; bis er seine .Mev-Liste hat (A4).  Portierung geht vor Funktionen, die nur
; der Nachbau hatte.
; ---------------------------------------------------------------------------

	INCLUDE	"vorspann.i"

	SECTION	Program,code

	INCLUDE	"GAME_OFF.S"		; Thalions, ueber -I gefunden
	INCLUDE	"src/FALCON_OFF.S"	; unsere Ergaenzungen (nicht seine!)
	INCLUDE	"src/MAIN.S"
; The one settings file AMBER.INF (E17, cut 2026-10-24): MAIN.S reads it
; once at the start, before Open_screen (PLAIN_ST, ST.S) and Musik_install
; (MUSIC, MUSIK_SUP.S).  SETTINGS.S has no SECTION of its own; MAIN.S ends
; in BSS.
	SECTION	Program,code
	INCLUDE	"../shared/SETTINGS.S"
; **Thalions HULL/WORDS.S**.  Textausgabe mit Seiten und
; Warten (Display_text_and_wait), Eingabefelder und der Print-Area-Stapel
; (Push_PA, Pop_PA, Erase_PA).  Daran haengen seine Meldungen (Do_prompt).
; Seine Datei endet im BSS-Abschnitt.
	INCLUDE	"HULL/WORDS.S"		; Thalions, ueber -I gefunden
	SECTION	Program,code
	INCLUDE	"src/HULL/WORDS_SUP.S"	; Put_text_line, Prompts
; Thalions zweite Datei, und die erste mit Code darin.  341 Zeilen, sieben
; Routinen; unser Nachbau hatte zwei davon und wich in beiden ab:
;   DecR_convert  hatte feste drei Stellen und kein d6; das Original nimmt
;                 die Stellenzahl in d7 und das Fuellzeichen in d6.
;   beide         geben bei Thalion a0 auf den Abschluss zurueck, unsere
;                 erhielten a0.
; Die Aufrufstellen sind darauf umgestellt -- nicht die Datei.
	INCLUDE	"HULL/NUMERIC.S"	; Thalions, ueber -I gefunden
	SECTION	Program,code		; NUMERIC.S laesst ihn offen
; **Thalions Bedienelemente.**  Seine HULL/CONTROLS.S bringt
; Bildlaufleiste, Tastenfeld, Eingabefelder und Textfenster.  Daran haengt
; der Rucksack im Inventarschirm: den zeichnet Update_objects, gerufen ueber
; Scroll_bar_update_ptr aus Init_scroll_bar.
	INCLUDE	"HULL/CONTROLS.S"	; Thalions, ueber -I gefunden
	INCLUDE	"src/HULL/CONTROLS_SUP.S"	; die Tastengrafik im Originalformat
; **Seine Datei endet im BSS-Abschnitt.**  Ohne diese Zeile landet alles
; Folgende ohne eigene SECTION-Angabe dort mit -- MODULES.S legte 194 dc.w
; ins BSS ("initialized data in bss"), und vlink stuerzte beim Binden ab.
; Die Zeile steht hier, nicht in seiner Datei: die bleibt unangetastet.
	SECTION	Program,code
	INCLUDE	"HULL/WINDOWS.S"	; Thalions, ueber -I gefunden
	SECTION	Program,code
; **Thalions HULL/MODULE_C.S**: sein Modulstapel und Eingabeverteiler --
; Handle_input, Handle_list,
; Push_Module/Pop_Module, Init_display/Exit_display/Update_display.  Daran
; haengt der Klick auf die Bildlaufleiste: Scroll_bar_pressed wird im Original
; nirgends gerufen, es steht in den .Mev-Tabellen der Moduldeskriptoren, und
; die arbeitet Handle_list ab.
;
; Seine Datei endet im BSS-Abschnitt -- wie CONTROLS.S, siehe dort.
	INCLUDE	"HULL/MODULE_C.S"	; Thalions, ueber -I gefunden
	SECTION	Program,code
; Thalions dritte Datei.  Push_Tree, Pop_Tree, Reset_tree_stack,
; Find_object, Search_layer -- 135 Zeilen.  Unser Nachbau hatte nur
; Find_object und Search_layer und keinen Baumstapel; die Baeume selbst
; stehen jetzt in MODULES.S, wo sie im Original auch stehen.
	INCLUDE	"HULL/OBJECT.S"		; Thalions, ueber -I gefunden
	SECTION	Program,code
	INCLUDE	"src/HULL/MEMORY.S"
	INCLUDE	"src/HULL/AREAS.S"
; Reading Thalion's game files at run time (goal 2): containers,
; Load_subfile, Decompress.  The inner loops are Thalion's: Crypt_block from
; HULL/VARIOUS.S (below) and Lob_core from am2cpu_code.i.
	INCLUDE	"src/HULL/FILES_SUP.S"
	INCLUDE	"src/HULL/SPIELSTAND.S"	; Get/Put_saved_game, Save_file ...
	INCLUDE	"src/HULL/STARTMENUE.S"	; Startmenue (Texte aus Ambermoon_intro)
	INCLUDE	"src/HULL/LIBRARY.S"
; The machine (library split phase 3, 2026-10-24): with -DZIEL_ST=1
; (tools/build_st.sh) the ST/STE with the colour table instead of the
; colour banks (docs/12-ST-Port.md).  Besides the switch block in
; vorspann.i these two places are the only ones in the shared code that
; ask.  The Falcon part of the drawing library (colour banks, eight
; planes, the tile cache) comes right behind LIBRARY.S: the two reach each
; other with bsr.  The ST part, ST_LIB.S, is further down.
	IFD	ZIEL_ST
	INCLUDE	"src/HULL/ST.S"		; ST_LIB.S steht weiter hinten
	ELSE
	INCLUDE	"src/HULL/FALCON_LIB.S"
	INCLUDE	"src/HULL/FALCON.S"
	ENDC
	INCLUDE	"src/HULL/FADE_SUP.S"
; Die Rasterliste als Timer-B-Interrupt -- unser Copper.  Damit bedeuten
; Thalions Raster_list_ptr wieder woertlich, was dort steht, und die
; Palettenbaenke werden entbehrlich (32 Farben wie auf dem Amiga).
	INCLUDE	"src/HULL/RASTER.S"
; Thalions vierte Datei.  224 Zeilen, sieben Symbole: die vier Blenden, das
; Zuruecksetzen der Rasterliste, Dim_colours und Faded_flag.
;
; Sie ist die erste, die *ueber den Modulsatz* liest -- "move.l Module_Sp,a0"
; und "move.l Raster_list_ptr(a0),d0".  Dafuer musste unser Modulsatz auf
; Thalions Aufbau umgestellt werden; Default_module in seinem src/MODULES.S
; zeigt ihn offen, und unsere Versaetze in vorspann.i stimmen damit ueberein.
;
; Was sie ruft und was wir dafuer stellen, steht in src/HULL/FADE_SUP.S.
	INCLUDE	"HULL/FADE.S"		; Thalions, ueber -I gefunden
	SECTION	Program,code
; Thalions fuenfte Datei.  231 Zeilen: die Hand-Draw-Objekte -- Bilder, die
; jedes Bild neu an eine Stelle gezeichnet werden und den Hintergrund
; darunter sichern.  Der getragene Gegenstand am Zeiger ist eines davon.
;
; Was sie ruft, haben wir: Draw_box, Put_masked_block2, Put_unmasked_block,
; Get_block, Allocate_CHIP, Claim_pointer, Free_pointer, Free_memory.  Die
; Feldversaetze der HDOB-Struktur stehen in vorspann.i, aus fuenf
; ausgeschriebenen Saetzen abgeleitet; Screen_flag und die beiden
; Fake-Handle-Helfer sind neu (BSS unten, MEMORY.S).
;
; Angetrieben wird sie von Update_screen (LIBRARY.S): das ruft Draw_HDOBs vor
; dem Blit und Erase_HDOBs danach.  Auf der Karte, die jedes Bild
; Update_screen ruft, zeichnet ein aufgelegter HDOB damit nachweislich.  Der
; getragene Gegenstand als HDOB wartet noch: Truhe und Inventar rufen
; Update_screen nur bei Aenderung, dort muesste erst ein Bildlauf je Bild
; her.
	INCLUDE	"HULL/HDOBS.S"		; Thalions, ueber -I gefunden
	SECTION	Program,code
; Thalions sechste Datei.  542 Zeilen: die Spezialeffekte -- fallende
; Objekte, Vibrieren, Bewegen, eine Bitmap in Pixel zersprengen.  Sie sitzen
; auf HDOBS.S auf (Create_fake_handle, HDOB_-Felder) und werden von Kampf und
; Magie gerufen; bis die dazukommen, liegt sie ungenutzt, aber gebunden da.
;
; Sechs Bibliothekssymbole stellt src/HULL/EFFECTS_SUP.S: Random, Square_root
; und Delay (im Original in VARIOUS.S -- weichen, sobald die kommt),
; Get_pixel, Pixel_buffer und die Clip-Area.
	INCLUDE	"HULL/EFFECTS.S"	; Thalions, ueber -I gefunden
	SECTION	Program,code
	INCLUDE	"src/HULL/EFFECTS_SUP.S"
	INCLUDE	"src/HULL/DIAGNOSE_SUP.S"	; Diagnoseschirm, Diagnostics_list1 (267)
; Thalions siebte Datei.  647 Zeilen Werkzeug: Sortieren, Zeichenketten,
; Warteroutinen, Zufall, Wurzel, Arcustangens, die Musiksteuerung.  Sie
; loest fuenf unserer Nachbauten ab (Random, Square_root, Delay, Strlen,
; Wait_4_unclick) und bringt viel mit, das spaetere Dateien brauchen.
;
; Neun Symbole stellt src/HULL/VARIOUS_SUP.S: die Falcon-Eingabe
; (Read_key, Read_Mev), Copy_memory, die ATN-Tabelle, Wait_4_user_Mod und
; frueher die Musik (Music_flag/-handle, Load_subfile als Stub).  Die
; Amiga-Hardware in VARIOUS (Custom+dmacon in Set_music) trifft seit dem
; Musik-Schritt 2a den Paula-Schatten in src/HULL/MUSIK_SUP.S (docs/13).
	INCLUDE	"HULL/VARIOUS.S"	; Thalions, ueber -I gefunden
	SECTION	Program,code
	INCLUDE	"src/HULL/VARIOUS_SUP.S"

; Was Thalions Spieldateien (spiel.s) aus AM2_CPU brauchen, das es als
; Quelltext nicht gibt: echt in den *_SUP.S oben und hier, sonst als
; Platzhalter in AM2_CPU_STUBS.S (Sorten B und C, tools/platzhalter_karte.py).
	INCLUDE	"src/HULL/INVENTOR_SUP.S"	; Object_data, Inventory_handle
; Die Daten aus AM2_CPU (Hauptpalette, Fensterkacheln, Statusleiste,
; Tastenrahmen, Zeichensatz, Mauszeiger ...), beim Bau herausgeholt von
; tools/am2cpu_auszug.py.  Zur Laufzeit wird AM2_CPU nie gelesen.
; DEVIATION (goals 1 and 2), docs/17-deviations.md D2 (also am2cpu_code.i).
	INCLUDE	"am2cpu_daten.i"
; Thalions Textnamen (Race_names, Age_txt, Age_nr ...) als Marken in
; Textdaten, den Lade_texte zur Laufzeit mit Text.amb fuellt; die Versaetze
; schreibt tools/textmarken.py beim Bau.
	INCLUDE	"textmarken.i"
	INCLUDE	"intro_daten.i"		; Startmenue aus Ambermoon_intro (intro_auszug.py)
	SECTION	Program,code
	INCLUDE	"am2cpu_code.i"		; Thalions Rasterer, beim Bau (docs/02 A7); DEVIATION (goals 1 and 2), docs/17-deviations.md D2
	INCLUDE	"src/HULL/D3_SUP.S"	; 3D: Schirm, Weichen
	INCLUDE	"src/HULL/COMBAT_SUP.S"	; Kampf: Zoom der Kampfobjekte (hinter am2cpu_code.i)
	INCLUDE	"src/HULL/MUSIK_SUP.S"	; Musik: Schattenbloecke unter Thalions Spieler (docs/13)
	SECTION	Program,code
; Die Farbtabelle des ST erst hier: vorn waere sie zwischen MAIN.S und
; D3_SUP.S gewachsen, und MAIN.S erreicht D3_einrichten mit bsr.
	IFD	ZIEL_ST
	INCLUDE	"src/HULL/ST_LIB.S"
	SECTION	Program,code
	ENDC
	INCLUDE	"src/HULL/AM2_CPU_STUBS.S"
	SECTION	Program,code

; Speicher.  Eigener Abschnitt, kein Anhaengsel des Codes.
;
; Bis hierher standen diese ds.b **im Codeabschnitt**, und -Fbin schrieb
; sie als Nullbytes in die Datei: gut zehn Kilobyte, die nichts enthalten.
; Mit vlink gibt es echte Abschnitte, und der GEMDOS-Lader legt den
; BSS-Bereich selbst an und loescht ihn.  Das Original teilt genauso auf --
; "SECTION Fast_DATA,data" und "SECTION Fast_BSS,bss" stehen am Ende fast
; jeder seiner Dateien.
;
; Der Start rechnet damit bereits richtig: er liest aus der Basepage Text
; (12), Daten (20) **und BSS (28)** und setzt den Stapel ueber alles.

	SECTION	Fast_BSS,bss
; Der Spielstand (partydat) und New_words (newwords) standen hier bis
; 2026-09-26.  Seitdem liegen beide in Thalions MAIN.S: Party_data ist der
; Spielstand selbst, Byte fuer Byte wie Party_data.sav, und p_party zeigt
; darauf (Load_party_data, MAP/MAP.S; Erkenntnis 180).

; Aufbereiteter Text: Zeilenfolge, jede Zeile beginnt mit einem Tintenbyte
; und endet mit 0.  Im Original liegt er in angefordertem Speicher, den
; Process_text sich mit Allocate_memory holt.
procbuf: ds.b	PROCBUF
	even
; Hintergruende unter dem Mauszeiger: je sechzehn Zeilen zu zwei Bloecken
; in acht Ebenen.  Einer je Schirm, wie Thalions HDOBs (Zeiger_satz), und
; ein freier, in den Update_mouse den neuen Fleck sichert, bevor es den alten
; loescht (LIBRARY.S).
mousebg: ds.b	MPTR_H*TROW*2
mousebg2: ds.b	MPTR_H*TROW*2
mousebg3: ds.b	MPTR_H*TROW*2
	even
; Zwischenstueck fuer Update_mouse: die Zeilen, in denen alter und neuer
; Fleck liegen, hoechstens 2*MPTR_H-1.
zg_zwischen: ds.b	2*MPTR_H*SCRROW
	even
savepal: ds.b	1024			; VIDEL-Farbregister des Desktops
savepal16: ds.b 32			; STE-vertraegliche Register
	even
; Die Tabelle des Speicherverwalters -- HULL/MEMORY.S.
memtab:	ds.b	MEM_MAX*MEM_SZ
	even
; Die Bibliotheksvariablen, die Thalions Code absolut anspricht.  Sie lagen
; bis eben im a5-Block; die Namen sind seine.
	even

Mouse_X:	ds.w 1
Mouse_Y:	ds.w 1
Button_state:	ds.w 1
Ink_colour:	ds.w 1
Shadow_colour:	ds.w 1
; Der laufende Mausbereich: Zeiger auf den Satz der obersten Area, gelesen
; mit Thalions Versaetzen MA_X1(a1) & Co. (AREAS.S, Erkenntnis 192).  Die
; Namen MA_X1 & Co. sind bei Thalion Strukturversaetze, nie Variablen
; (Erkenntnis 169).
Maus_bereich:		ds.l 1
	even

; Die Bereichsstapel -- HULL/AREAS.S.
pastack: ds.b	MAX_AREA*PA_data_size
	even
mastack: ds.l	MAX_AREA		; Zeiger auf die Saetze
	even
mpstack: ds.l	MAX_AREA		; Zeiger auf Thalions Zeigersaetze
	even
; Blenden -- HULL/FADE.S und src/HULL/FADE_SUP.S.
;
; **Der Doppelpuffer wie im Original** (Erkenntnis 200, 258; LIBRARY.S).
; Off_screen, Work_screen, Screen_flag und Vertical_screen_offset sind
; Thalions Namen, sein Code liest sie absolut; in AM2_CPU liegen sie bei
; 9:$9CF4, $9CF8, $9CEA und $9CEC.  Schirm_vorn ist der sichtbare Schirm
; (9:$9CF0, Name von uns), Off_screen der hintere, Work_screen das
; Zeichenziel, normalerweise der hintere.  Screen_flag schlaegt bei jedem
; Tausch um; HDOBS.S waehlt damit den Sicherungsblock des hinteren Schirms.
Schirm_vorn:	ds.l 1
Off_screen:	ds.l 1
Work_screen:	ds.l 1
Vertical_screen_offset:	ds.w 1	; Bildschuetteln, -4..4 Zeilen (COMBAT_M.S)
Screen_flag:	ds.b 1
Schirme_an:	ds.b 1		; gesetzt: der VBL setzt die Videobasis
	even
; Der Mauszeiger je Schirm: Hintergrund, Ecke, steht er dort?  Satz 0 gilt
; dem Schirm, der bei Screen_flag = 0 hinten ist (Zeiger_satz, LIBRARY.S;
; Aufbau ZS_* in FALCON_OFF.S).
zeiger_saetze:	ds.b	2*ZS_SIZE
zg_frei:	ds.l 1		; der dritte Hintergrund, frei fuer Update_mouse
zg_schirm:	ds.l 1		; wohin Zeiger_in/aus_puffer zeichnen
zg_bg:		ds.l 1		; welcher Hintergrund dabei gilt
	even
; Current_pal steht in Thalions MAIN.S (ds.w Pal_size, also auch 32 Worte).
; Zwischenstufe einer Blende und das Ziel Schwarz.  Schwarz wird nie
; beschrieben -- der GEMDOS-Lader loescht den BSS-Bereich, und das genuegt.
Fade_work:	ds.w 32
Schwarz:	ds.w 32
; Je Platz der Rasterliste (FADE_SUP.S, Platzbank): was zuletzt in seiner
; Bank gesetzt wurde, und die Ausgangspalette einer laufenden Blende.  Dazu
; die zuletzt gesetzte Liste.  Alles braucht Set_fade, weil Fade_out ohne
; Rasterliste gerufen wird.
Bank_ist:	ds.w 32*PLAETZE
Fade_von:	ds.w 32*PLAETZE
Sf_pal:		ds.l PLAETZE		; Paletten der Plaetze im Bereich
Letzte_RL:	ds.l 1
Videl_puffer:	ds.l 32
	even
vars:	ds.b	vars_size
	even
; Der Stapel.  start setzt sp hierher (src/MAIN.S).  Bis 2026-09-26 stand
; der Block zwar hier, benutzt wurde er aber nie: sp lag auf dem BSS-Ende,
; und der Stapel wuchs in die letzten BSS-Variablen hinein (Erkenntnis 185).
; 16 KB, weil Thalions Ereigniskette tief schachtelt (Push_Module ->
; Init_module -> ModInit -> Do_text ..., jede Stufe mit movem).
	ds.b	16384			; waechst nach unten auf vars zu
stacktop:
	even

; Die Namen, die die zweite Einheit (spiel.s, Thalions Spieldateien) aus
; dieser braucht -- erzeugt von tools/einheiten_verbinden.py.
	SECTION	Program,code
	INCLUDE	"xdef_bibliothek.i"

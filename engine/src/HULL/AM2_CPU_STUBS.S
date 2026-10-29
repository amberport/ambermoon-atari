; ===========================================================================
; AM2_CPU_STUBS.S -- PLATZHALTER fuer die nicht freigegebene Bibliothek.
; Einheit "bibliothek" (engine.s).
;
; **Seit Stufe (c) (2026-09-27) sind alle Dateien Thalions eingebunden.**
; Was hier steht, gibt es in keinem freigegebenen Quelltext: Thalion hatte es
; in AM2_CPU (Routinen, Daten) oder in Texten, die dort einkompiliert waren.
; Es ist genau die Liste von tools/vollprobe.py, abzueglich dessen, was
; unsere Schicht schon echt stellt (*_SUP.S, LIBRARY.S, FALCON.S ...) und
; was tools/am2cpu_auszug.py beim Bau aus AM2_CPU holt
; (build/am2cpu_daten.i).  Diese Datei schrumpft; sie ersetzt die frueheren
; ACTIONS_, CONTROLS_, DISPLAY_, EVENTS_, INVENTOR_, MAIN_, MODULE_C_ und
; WORDS_STUBS.S.
;
; Sorten (tools/platzhalter_karte.py):
;   B  Bibliothek: Routinen, die tun nichts
;   C  Daten: Texte leer, Grafik und Tabellen null
;
; **Daten stehen im Daten- oder BSS-Abschnitt, nie im Routinenblock**
; (Erkenntnis 157, tools/platzhalter_pruefen.py).  Keine Moduldeskriptoren
; mehr: die stehen alle in Thalions MODULES.S.
;
; Fuer Texte mit Find_small_text (WORDS.S) ist Null die sichere Fuellung:
; jede Null beendet einen leeren Text, also sind 64 Nullbytes 64 leere
; Texte.  Die Namenslisten und Vorlagen aus Text.amb sind echt
; (build/textmarken.i, Lade_texte in WORDS_SUP.S).
; ===========================================================================

	SECTION	Program,code

; --- B: Routinen, tun nichts ---
; (Spielstaende: echt in SPIELSTAND.S; Load_unique_subfile: FILES_SUP.S.)
; Clear_all_claims und Kill_unclaimed_memory sind echt (MEMORY.S, 267).
; Copy_screen und Duplicate_block sind mit dem Doppelpuffer echt geworden
; (LIBRARY.S, Erkenntnis 258).
; Recolour_block, Draw_zoom_shape/-silhouette und Draw_floor/Draw_ceiling
; kommen aus AM2_CPU (build/am2cpu_code.i), der Zeichenteil der Zooms steht
; in COMBAT_SUP.S.
; Der Diagnoseschirm und Diagnostics_list1 sind echt (DIAGNOSE_SUP.S, 267).

; --- Meldungen: echt seit 2026-09-28.  Die Textlisten (Recup1_text ...)
; baut tools/am2cpu_auszug.py aus AM2_CPU, die Einzeltexte (Divide_*_text,
; That_text ...) und Magic_txt setzt tools/textmarken.py in Text.amb;
; Attrskill_nr und Charges_txt sind Stuecke aus AM2_CPU. ---

	SECTION	Fast_BSS,bss
	even
; --- C: Grafik: keine mehr.  Die 2D-Grafik (Compass, Eye_*, Status_icons,
; Chequered ...) kommt seit 2026-09-29 aus AM2_CPU (tools/am2cpu_auszug.py,
; Erkenntnis 256), Chared_portraits seit 2026-09-30 (261). ---

; --- Variablen der Bibliothek.  Thalions Code liest oder schreibt sie; wer
; auf der anderen Seite stand, fehlt noch (3D, Kampf). ---
; Current_filename ist echt (FILES_SUP.S, Dateifehler, 268).
; Rune_flag is real since 2026-10-17 (WORDS_SUP.S, ~RUN1~ and ~NORM~); no
; placeholder is left.
; Vertical_screen_offset steht bei den Schirmen in engine.s (B1a).
; Zoomscreen1/2_ptr kommen seit 2026-10-01 aus build/am2cpu_code.i (BSS in
; Originalanordnung), Sky_ranges und C3_palettes aus build/am2cpu_daten.i.

	SECTION	Program,code

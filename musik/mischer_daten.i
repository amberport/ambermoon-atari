; mischer_daten.i -- data of the mixer (MISCHER.S); no SECTION, include it in a data section.
	even
md_code:				; MUSIK_DSP.A56, 3 bytes per word
	incbin	"musik_dsp.dsp"		; build/, tools/musik_dsp.sh
md_code_ende:
md_halt:				; for Mischer_remove: P:0 "jmp 0"
	dc.b	$0C,$00,$00
	even
mk_stille:
	dc.w	0
mk_bereit:
	dc.b	0			; Mischer_install has set up the sound
mx_snd:	dc.b	0			; cookie _SND, lowest byte
md_dsp:
	dc.b	0			; the DSP mixes
md_tot:
	dc.b	0			; the DSP no longer answers
md_maske:
	dc.b	0			; synth buffers a channel reads
md_syn_gueltig:
	dc.b	0			; synth buffers the DSP already has
	even
md_s_lied:
	dc.l	0			; song whose samples the DSP has
md_s_anfang:
	dc.l	0			; ... their area in memory (0 = none)
md_s_ende:
	dc.l	0
md_s_nr:
	dc.w	0			; ... and its number (MS_STUECK)
	even

; mischer_bss.i -- variables of the mixer (MISCHER.S); no SECTION, include it in a bss section.
	even
mx_satz:
	ds.b	MS_GROESSE		; copy of the parameter block
	even
mx_rette:
	ds.l	5			; d1-d2/a0-a2 around XBIOS (Mx_xbios)
mx_register:
	ds.w	7			; sound registers before Mischer_install
mk_schreib:
	ds.l	1			; write position in the ring (bytes)
Musik_kanaele:
	ds.b	4*mk_groesse
Musik_lautst:
	ds.w	65*256
md_temp:
	ds.b	640			; bytes of one channel across block ends
md_plan:
	ds.b	4*mp_groesse
md_syn_kopie:
	ds.b	4*MD_SYN_LEN		; what the DSP has of the synth buffers
	even

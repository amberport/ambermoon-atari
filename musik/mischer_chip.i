; mischer_chip.i -- the DMA ring of the mixer (MISCHER.S); no SECTION, include it where memory is ST-RAM (DMA reads nothing else).
	even
Musik_ring:
	ds.b	MUSIK_RING_B
	even

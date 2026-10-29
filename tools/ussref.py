#!/usr/bin/env python3
"""
ussref.py -- Amiga-Speicherauszüge als unabhängige Referenz.

Ein laufender Amiga ist die einzige Quelle, die nicht aus derselben
Umrechnung stammt wie unser Konverter.  Dokumentation kann veraltet sein,
ein selbst gerendertes Bild kann plausibel aussehen und falsch sein -- der
Bildschirminhalt einer echten Sitzung kann das nicht.

Was hier passiert
=================

1. Der Speicherauszug (FS-UAE/WinUAE, `.uss`) besteht aus Blöcken mit
   4 Byte Name, 4 Byte Größe, 4 Byte Flags.  Ist Bit 0 der Flags gesetzt,
   sind die Daten zlib-gepackt und es steht ein u32 mit der entpackten
   Größe davor.  Gebraucht werden CRAM (Chip-RAM), FRAM (Fast-RAM) und
   AGAC (Farbregister).

2. Die Bitplane-Zeiger stehen **nicht** verwertbar im Registerblock: der
   Amiga erhöht sie während der Bildausgabe, am Ende des Bildes zeigen sie
   hinter den Bildspeicher.  Verlässlich ist die Copperliste, die sie in
   jedem Bilddurchlauf neu setzt.  Gesucht wird die Stelle, an der fünf
   aufeinanderfolgende `move`-Befehle die Register $E0..$F2 beschreiben.

3. Welche Karte geladen ist, verrät der Speicher selbst: die entpackten
   Kacheldaten stehen dort im Klartext und lassen sich gegen alle Karten
   aus den Spieldateien suchen.
"""

import struct
import zlib

BPL1PTH = 0x00E0


def read_chunks(path, names=("CRAM", "FRAM", "AGAC", "CHIP", "CPU")):
    """Gesuchte Blöcke eines Speicherauszugs -> {Name: Daten}.

    Sequenzielles Durchlaufen ist nicht verlässlich: die Blocklängen und
    Ausrichtungen unterscheiden sich zwischen Emulatorversionen, ein
    unerwarteter Block wirft den Rest aus dem Tritt.  Gesucht wird deshalb
    gezielt nach den Blocknamen, mit Plausibilitätsprüfung über die
    angegebene Länge.
    """
    data = open(path, "rb").read()
    out = {}
    for name in names:
        key = name.ljust(4).encode()
        o = -1
        while True:
            o = data.find(key, o + 1)
            if o < 0:
                break
            if o + 12 > len(data):
                break
            size, flags = struct.unpack(">II", data[o + 4:o + 8 + 4])
            if not (12 <= size <= len(data) - o):
                continue
            body = data[o + 12:o + size]
            if flags & 1:
                if len(body) < 4:
                    continue
                try:
                    body = zlib.decompress(body[4:])
                except zlib.error:
                    continue
            out[name] = body
            break
    return out


def find_bitplanes(chip, planes=5):
    """Copperliste nach Bitplane-Zeigern durchsuchen -> Liste von Adressen.

    Muster je Plane: zwei `move`-Befehle, erst das hohe, dann das niedrige
    Wort. Register $E0/$E2 für Plane 0, dann in Viererschritten weiter.
    """
    hits = []
    i = -2
    while True:
        i = chip.find(b"\x00\xe0", i + 2)
        if i < 0 or i + planes * 8 > len(chip):
            break
        if i & 1:
            continue
        ptrs = []
        for p in range(planes):
            hi_reg = bytes([0, BPL1PTH + p * 4])
            lo_reg = bytes([0, BPL1PTH + p * 4 + 2])
            o = i + p * 8
            if chip[o:o + 2] != hi_reg or chip[o + 4:o + 6] != lo_reg:
                break
            hi = struct.unpack(">H", chip[o + 2:o + 4])[0]
            lo = struct.unpack(">H", chip[o + 6:o + 8])[0]
            ptrs.append((hi << 16) | lo)
        if len(ptrs) == planes:
            hits.append((i, ptrs))
    return hits


def decode_screen(chip, base, width=320, height=200, planes=5):
    """Zeilenverschachtelter Bildspeicher -> Farbindizes."""
    stride = width // 8
    row = stride * planes
    px = [0] * (width * height)
    for y in range(height):
        for p in range(planes):
            o = base + y * row + p * stride
            bit = 1 << p
            for xb in range(stride):
                b = chip[o + xb]
                if not b:
                    continue
                bs = y * width + xb * 8
                for k in range(8):
                    if b & (0x80 >> k):
                        px[bs + k] |= bit
    return px


def palette(chunks, count=32):
    """Farbregister -> Liste von (r,g,b) mit je 0..255."""
    agac = chunks.get("AGAC", b"")
    out = []
    for i in range(count):
        c = struct.unpack(">I", agac[i * 4:i * 4 + 4])[0]
        out.append(((c >> 16) & 0xFF, (c >> 8) & 0xFF, c & 0xFF))
    return out


def screen_png(path, px, pal, width=320, height=200, scale=2):
    from PIL import Image
    im = Image.new("P", (width, height))
    flat = []
    for c in pal:
        flat += list(c)
    flat += [0] * (768 - len(flat))
    im.putpalette(flat)
    im.putdata(px)
    im.convert("RGB").resize((width * scale, height * scale),
                             Image.NEAREST).save(path)


def identify_map(chunks, map_entries):
    """Geladene Karte anhand der Kacheldaten im Speicher bestimmen.

    Eine kurze Probe reicht nicht: Weltkarten bestehen über weite Strecken
    aus derselben Wasserkachel, da trifft ein 48-Byte-Ausschnitt auf dutzende
    Karten zu.  Deshalb wird kurz vorgefiltert und anschließend der gesamte
    Kacheldatenblock geprüft.

    map_entries: {(Dateiname, Nummer): Rohdaten}
    Gibt Liste von (Datei, Nummer, Speicherbereich, Offset).
    """
    hits = []
    for (fn, num), raw in map_entries.items():
        if not raw or len(raw) < 0x150:
            continue
        typ = raw[2]
        w, h = raw[4], raw[5]
        n = w * h
        if n == 0:
            continue
        full = raw[0x14C:0x14C + (2 if typ == 1 else 4) * n]
        if len(full) < 64 or len(set(full[:64])) < 3:
            probe = full
        else:
            probe = full[:64]
        for key in ("CRAM", "FRAM"):
            mem = chunks.get(key)
            if not mem:
                continue
            p = -1
            while True:
                p = mem.find(probe, p + 1)
                if p < 0:
                    break
                if mem[p:p + len(full)] == full:
                    hits.append((fn, num, key, p))
                    break
    return hits


SPR0PTH = 0x0120


def find_sprites(chip, pair=0):
    """Sprite-Zeiger eines verketteten Paares aus der Copperliste.

    Der Mauszeiger steht auf dem Amiga **nicht** im Bildspeicher -- er ist
    ein Hardware-Sprite und liegt neben den Bitplanes.  Gesucht wird nach
    demselben Muster wie bei den Bitplanes: zwei `move`-Befehle je Zeiger,
    erst das hohe, dann das niedrige Wort.

    `pair` 0 nimmt SPR0/SPR1, `pair` 1 nimmt SPR2/SPR3.
    Gibt Liste von (Fundstelle, (Adresse0, Adresse1)).
    """
    hits = []
    reg = SPR0PTH + pair * 8
    i = -2
    while True:
        i = chip.find(struct.pack(">H", reg), i + 2)
        if i < 0 or i + 16 > len(chip):
            break
        if i & 1:
            continue
        ptrs = []
        for k in range(2):
            o = i + k * 8
            if (chip[o:o + 2] != struct.pack(">H", reg + k * 4)
                    or chip[o + 4:o + 6] != struct.pack(">H", reg + k * 4 + 2)):
                break
            hi = struct.unpack(">H", chip[o + 2:o + 4])[0]
            lo = struct.unpack(">H", chip[o + 6:o + 8])[0]
            ptrs.append((hi << 16) | lo)
        if len(ptrs) == 2:
            hits.append((i, tuple(ptrs)))
    return hits


def sprite_image(chip, addr0, addr1):
    """Zwei verkettete Sprites -> (Indizes, Breite, Hoehe, x, y).

    Aufbau je Sprite: zwei Kontrollwoerter, dann je Zeile zwei Datenwoerter.
    Sprite 0 liefert die unteren zwei Bit, Sprite 1 die oberen -- zusammen
    vier Bit, also 16 Farben aus den Registern 16 bis 31.

    Die Kontrollwoerter sind nicht offensichtlich aufgeteilt:

        SPRxPOS   15..8 VSTART low        7..0 HSTART Bit 8..1
        SPRxCTL   15..8 VSTOP  low        7 ATTACH
                  2 VSTART Bit 8   1 VSTOP Bit 8   0 HSTART Bit 0

    Wer VSTART Bit 8 in Bit 0 sucht -- der naheliegende Fehler --, bekommt
    Hoehen wie -240 heraus und merkt es sofort; bei der Stelle merkt man es
    nicht.
    """
    pos, ctl = struct.unpack(">2H", chip[addr0:addr0 + 4])
    vstart = (pos >> 8) | (((ctl >> 2) & 1) << 8)
    vstop = (ctl >> 8) | (((ctl >> 1) & 1) << 8)
    hstart = ((pos & 0xFF) << 1) | (ctl & 1)
    h = vstop - vstart
    if h <= 0 or h > 256:
        return None
    idx = []
    for y in range(h):
        w0, w1 = struct.unpack(">2H", chip[addr0 + 4 + y * 4:addr0 + 8 + y * 4])
        w2, w3 = struct.unpack(">2H", chip[addr1 + 4 + y * 4:addr1 + 8 + y * 4])
        for k in range(16):
            idx.append(((w0 >> (15 - k)) & 1)
                       | (((w1 >> (15 - k)) & 1) << 1)
                       | (((w2 >> (15 - k)) & 1) << 2)
                       | (((w3 >> (15 - k)) & 1) << 3))
    # Bildschirmlage: DIWSTRT liegt bei Ambermoon auf $2C81, also x-129, y-44.
    return idx, 16, h, hstart - 129, vstart - 44


def sprite_table(idx, w=16):
    """Indizes als Hexzeilen, wie sie der Konverter als Tabelle fuehrt."""
    zeilen = []
    for y in range(len(idx) // w):
        zeilen.append("0x" + "".join("%X" % v for v in idx[y * w:(y + 1) * w]))
    return zeilen

#!/usr/bin/env python3
"""
imploder.py -- Entpacker für Imploder-Daten ("IMP!"), Albert J. Brouwer.

Die Routine ist keine Nachbildung nach Spezifikation, sondern eine
instruktionsgetreue Übertragung der Entpackroutine aus `Ambermoon_intro`,
CODE-Hunk 0, Offset $4F5C.  Erkannt wurde sie an `cmpi.l #$494D5021,(a0)+`.

Arbeitsweise
============
Der Imploder entpackt **rückwärts und an Ort und Stelle**.  Die gepackten
Daten liegen am Anfang eines Puffers von der Größe der entpackten Daten;
gelesen wird von hinten nach vorn (`move.b -(a3),…`), geschrieben ebenso
(`move.b …,-(a4)`).  Dadurch überholt der Schreibzeiger den Lesezeiger nie.

Aufbau eines Blocks
-------------------
    +0   'IMP!'
    +4   u32  entpackte Größe
    +8   u32  Offset auf das Ende der gepackten Daten
    +12  gepackte Daten …

Am Ende der gepackten Daten folgen 46 Byte Nachspann:

    +0   3 Langwörter  die ersten 12 Bytes des Stroms.  Der 12-Byte-Header
                       überschreibt sie im In-Place-Layout, deshalb liegen
                       sie hier gesichert.  Sie werden nach buf[8], buf[4]
                       und buf[0] zurückgeschrieben — in dieser Reihenfolge.
    +12  u32           Anfangszahl direkt zu kopierender Bytes
    +16  u16           Anfangszustand des Bitpuffers
    +18  28 Byte       Tabellen: 4 Wörter Offset-Basis (niedrig),
                       4 Wörter Offset-Basis (hoch), 12 Byte Bitanzahlen

Blocklänge insgesamt = Offset-auf-Ende + 46, auf 4 Byte aufgerundet.

Bitleser
--------
Klassischer Schieber mit Wächterbit:

    add.b   d3,d3      ; Bit 7 nach C und X
    bne.s   weiter     ; Puffer noch nicht leer
    move.b  -(a3),d3   ; nachladen
    addx.b  d3,d3      ; Wächterbit hineinschieben
    weiter:

Nach jedem Bit gilt X == C == dem gelesenen Bit; genau das nutzen die
`addx`-Befehle, die Bits in Register schieben.

Selbstprüfung
-------------
Der Entpacker gilt nur dann als erfolgreich, wenn der Lesezeiger exakt auf
dem Pufferanfang landet (`cmpa.l a3,a0 / beq`) und der Ausgabezeiger genau
die angegebene Größe gefüllt hat.  Beides wird hier geprüft.
"""

import struct

MAGIC = b"IMP!"
TAIL_SIZE = 46

# PC-relative Tabellen aus dem Code, $50AA und $50AE
TABLE_A = (6, 10, 10, 18)
TABLE_B = (1, 1, 1, 1, 2, 3, 3, 4, 4, 5, 7, 14)


class ImploderError(Exception):
    pass


def _u32(b, o):
    return struct.unpack_from(">I", b, o)[0]


def _u16(b, o):
    return struct.unpack_from(">H", b, o)[0]


def _s16(b, o):
    return struct.unpack_from(">h", b, o)[0]


def block_length(data, off=0):
    """Gesamtlänge eines IMP!-Blocks inklusive Nachspann, auf 4 aufgerundet."""
    end = _u32(data, off + 8)
    return (end + TAIL_SIZE + 3) & ~3


def decompress(data, off=0):
    if data[off:off + 4] != MAGIC:
        raise ImploderError("keine IMP!-Signatur")

    dec_size = _u32(data, off + 4)
    end_off = _u32(data, off + 8)
    if end_off + TAIL_SIZE > len(data) - off:
        raise ImploderError(
            f"Block reicht über das Dateiende hinaus "
            f"({end_off + TAIL_SIZE} > {len(data) - off})")

    # Puffer: gepackte Daten vorn, Rest ist Platz für die Ausgabe
    buf = bytearray(dec_size)
    src = data[off:off + end_off]
    if len(src) > dec_size:
        raise ImploderError("gepackte Daten größer als die entpackte Größe")
    buf[:len(src)] = src

    a4 = dec_size          # Schreibzeiger, läuft rückwärts
    a3 = end_off           # Lesezeiger, läuft rückwärts
    a2 = a3                # zeigt in den Nachspann

    # --- die drei vom Header überschriebenen Langwörter zurückschreiben ----
    a0 = 12
    for _ in range(3):
        v = _u32(data, off + a2)
        a2 += 4
        a0 -= 4
        struct.pack_into(">I", buf, a0, v)
    # a0 == 0

    d2 = _u32(data, off + a2)          # Anzahl direkter Bytes
    a2 += 4
    init = _u16(data, off + a2)        # Bitpuffer
    a2 += 2
    if not (init & 0x8000):
        a3 -= 1
    d3 = init & 0xFF

    tbl = data[off + a2: off + a2 + 28]   # 28 Byte Tabellen
    if len(tbl) < 28:
        raise ImploderError("Nachspann unvollständig")

    off_lo = [struct.unpack_from(">h", tbl, i * 2)[0] for i in range(4)]
    off_hi = [struct.unpack_from(">h", tbl, 8 + i * 2)[0] for i in range(4)]
    bits_tbl = list(tbl[16:28])

    x = 0        # X-Flag

    def getbit():
        """add.b d3,d3 / bne / move.b -(a3),d3 / addx.b d3,d3"""
        nonlocal d3, a3, x
        old = d3
        res = (old << 1) & 0xFF
        c = (old >> 7) & 1
        if res:
            d3 = res
            x = c
            return c
        a3 -= 1
        if a3 < 0:
            raise ImploderError("Lesezeiger vor Pufferanfang")
        b = buf[a3]
        d3 = ((b << 1) | c) & 0xFF     # addx: b + b + X, X war == c
        x = (b >> 7) & 1
        return x

    def readbits(n):
        """do-while wie im Original: n == 0 bedeutet 256 Durchläufe."""
        v = 0
        count = n if n else 256
        for _ in range(count):
            v = (v << 1) | getbit()
        return v

    d4 = 0
    while True:
        # ---- direkte Bytes -------------------------------------------------
        while d2:
            a3 -= 1
            a4 -= 1
            if a3 < 0 or a4 < 0:
                raise ImploderError("Zeiger vor Pufferanfang (Literale)")
            buf[a4] = buf[a3]
            d2 -= 1

        if not a0 < a4:
            break

        # ---- Länge ---------------------------------------------------------
        if not getbit():
            d4, d0 = 2, 0
        elif not getbit():
            d4, d0 = 3, 1
        elif not getbit():
            d4, d0 = 4, 2
        elif not getbit():
            d4, d0 = 5, 3
        elif not getbit():
            d4 = (readbits(3) + 6) & 0xFF
            d0 = 3
        else:
            a3 -= 1
            d4 = buf[a3]
            d0 = 3

        # ---- Anzahl der folgenden direkten Bytes ---------------------------
        d1 = d0
        d5 = 0
        if getbit():
            if getbit():
                d5 = TABLE_A[d0]
                d0 += 8
            else:
                d5 = 2
                d0 += 4
        d2 = (readbits(TABLE_B[d0]) + d5) & 0xFFFF

        # ---- Abstand -------------------------------------------------------
        base = 0
        d0 = d1
        if getbit():
            d1 *= 2
            if getbit():
                base = off_hi[d1 // 2]
                d0 += 8
            else:
                base = off_lo[d1 // 2]
                d0 += 4
        dist = readbits(bits_tbl[d0])

        a2 = a4 + base + dist + 1
        if a2 > dec_size:
            raise ImploderError(f"Rückverweis hinter Pufferende ({a2})")

        # ---- Rückverweis kopieren ------------------------------------------
        for _ in range(d4 if d4 else 256):
            a2 -= 1
            a4 -= 1
            if a4 < 0 or a2 < 0:
                raise ImploderError("Zeiger vor Pufferanfang (Rückverweis)")
            buf[a4] = buf[a2]

    if a3 != a0:
        raise ImploderError(
            f"Selbstprüfung fehlgeschlagen: Lesezeiger steht auf {a3}, "
            f"erwartet {a0}")
    if a4 != 0:
        raise ImploderError(
            f"Selbstprüfung fehlgeschlagen: {a4} Byte der Ausgabe ungefüllt")
    return bytes(buf)


def find_blocks(data):
    """Alle IMP!-Blöcke in einem Puffer, als Liste von (offset, länge, größe)."""
    out = []
    o = 0
    while True:
        i = data.find(MAGIC, o)
        if i < 0:
            break
        try:
            out.append((i, block_length(data, i), _u32(data, i + 4)))
        except Exception:
            pass
        o = i + 4
    return out


if __name__ == "__main__":
    import sys
    d = open(sys.argv[1], "rb").read()
    for o, ln, size in find_blocks(d):
        try:
            r = decompress(d, o)
            print(f"@{o:<8} {ln:>8} -> {len(r):>8} Byte  OK")
            if len(sys.argv) > 2:
                open(f"{sys.argv[2]}_{o:08d}.bin", "wb").write(r)
        except ImploderError as e:
            print(f"@{o:<8} {ln:>8} -> FEHLER: {e}")

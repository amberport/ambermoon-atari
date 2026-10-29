#!/usr/bin/env python3
"""
imploder_exe.py -- Entpacker für Imploder-gepackte Amiga-Programme.

Für `Fantasy_intro` und `Ambermoon_extro`.  Das ist eine andere Variante als
die Datenblöcke mit `IMP!`-Signatur (siehe `imploder.py`): der Kern ist
derselbe, aber drumherum liegt ein Lader, der ein ganzes Programm aufbaut.

Aufbau der Datei (Hunks, Fantasy_intro / Ambermoon_extro)
=========================================================

    0          CODE  120 Byte   Startstück
    1 .. n     BSS             die Hunks des eigentlichen Programms (n = 4 / 6)
    n+1        CODE  512 Byte   Entpacker
    n+2        DATA            gepackter Strom
    n+3        BSS             Ringpuffer (18692 / 18628 Byte)

Das Startstück ruft den Entpacker, legt Hunk 1 als Rücksprungadresse auf
den Stapel und gibt Entpacker, Strom und Ring frei: **das Programm beginnt
am Anfang von Hunk 1.**

Zwei Ebenen
===========
1. **Der Kern** ($84-$1F8) entpackt je Aufruf einen Ring voll, rückwärts
   vom Ringende aus.  Er liest den Strom rückwärts ab `adda.l #n,a1` ($06).
   **Der Ring bleibt zwischen den Aufrufen stehen**: Ein Rückverweis über das
   Ringende hinaus liest Bytes des vorigen Blocks.  Die erste Fassung dieses
   Werkzeugs legte jedes Mal einen leeren Puffer an; der Code kam trotzdem
   richtig heraus, die Grafik in Hunk 2 nicht (20000 Byte verschieden).
2. **Der Befehlsstrom** ($00-$6A) liest den Ring langwortweise vom Ende her:

       Bit 31 gesetzt     nächster Zielhunk (nach dem letzten: fertig)
       Bit 30 gesetzt     Relokationen: je Gruppe Anzahl, Zielhunk - 1,
                          dann Anzahl Abstände (aufsummiert); Gruppe 0 = Ende
       0                  nichts
       sonst              so viele Langworte Daten ab Hunkanfang

   Was ein Zielhunk nicht an Daten bekommt, bleibt 0 (Amiga: MEMF_CLEAR).

Selbstprüfung
=============
Drei Bedingungen müssen zugleich aufgehen: der Lesezeiger steht am Anfang
des Stroms (`a0` = 0), der Durchlaufzähler aus $1EA auf null, und der
Befehlsstrom hat alle Zielhunks abgeschlossen.  Beides trifft bei
`Fantasy_intro` und `Ambermoon_extro` zu.  In `Fantasy_intro` steht danach
in Hunk 1 Thalions `FAIRY.S` (`mani_tab`, `puls_tab`, `plot00`...).

Aufruf
======
    python3 tools/imploder_exe.py <Datei> <Zielverzeichnis>

legt `hunkNN.bin` und `relok.txt` (Hunk, Versatz, Zielhunk) ab.
"""

import os
import struct
import sys


class ExeImploderError(Exception):
    pass


def _w(x):
    return x & 0xFFFF


def _s(x):
    x &= 0xFFFF
    return x - 0x10000 if x & 0x8000 else x


class Kern:
    """Der Entpacker, Befehl für Befehl nach dem 512-Byte-Codehunk."""

    def __init__(self, strom, code):
        self.strom = strom
        self.code = code
        self.a0 = struct.unpack_from(">I", code, 0x08)[0]      # adda.l #n,a1
        self.groesse = struct.unpack_from(">H", code, 0x18)[0]  # move.w #n,d4
        self.ring = bytearray(self.groesse)
        # Zustand bei $1E6: d2.w, d1.b, d0.b, Zähler.l
        self.d2 = struct.unpack_from(">H", code, 0x1E6)[0]
        self.d1 = code[0x1E8]
        self.d0 = code[0x1E9]
        self.zaehler = struct.unpack_from(">I", code, 0x1EA)[0]
        self.a5 = 0
        self.fertig = False

    def _wort(self, adr):
        return _s(struct.unpack_from(">H", self.code, adr)[0])

    def _byte(self):
        self.a0 -= 1
        if self.a0 < 0:
            raise ExeImploderError("Lesezeiger vor dem Anfang des Stroms")
        return self.strom[self.a0]

    def _bit(self):
        # add.b d1,d1 / bne.s / move.b -(a0),d1 / addx.b d1,d1
        alt = self.d1
        self.d1 = (alt << 1) & 0xFF
        c = alt >> 7
        if self.d1 == 0:
            n = self._byte()
            self.d1 = ((n << 1) | c) & 0xFF
            c = n >> 7
        return c

    def fuellen(self):
        """Ein Aufruf ab $84: füllt den Ring vom Ende her."""
        if self.fertig:
            raise ExeImploderError("Befehlsstrom liest über das Ende hinaus")
        ende = self.groesse
        a3 = ende
        d5 = self.groesse
        d2, d0, a5 = self.d2, self.d0, self.a5
        ring = self.ring
        kopie = d0 != 0                          # tst.b d0 / bne $1D8
        pruefen = False
        while True:
            if not kopie:
                while _w(d2):                    # $9C: direkte Bytes
                    d5 = _w(d5 - 1)
                    if d5 & 0x8000:
                        self.d2, self.d0, self.a5 = d2, d0, a5
                        return
                    a3 -= 1
                    ring[a3] = self._byte()
                    d2 = _w(d2 - 1)
                self.zaehler = (self.zaehler - 1) & 0xFFFFFFFF
                if self.zaehler == 0:            # $AC
                    self.fertig = True
                    self.d2, self.d0, self.a5 = d2, d0, a5
                    return
                # Länge ($B2-$114)
                if not self._bit():
                    d0, d7 = 2, 0
                elif not self._bit():
                    d0, d7 = 3, 1
                elif not self._bit():
                    d0, d7 = 4, 2
                elif not self._bit():
                    d0, d7 = 5, 3
                elif not self._bit():
                    for _ in range(3):
                        d0 = ((d0 << 1) | self._bit()) & 0xFF
                    d0 = (d0 + 6) & 0xFF
                    d7 = 3
                else:
                    d0, d7 = self._byte(), 3
                d3 = d7
                # Anzahl der folgenden direkten Bytes ($118-$162)
                if not self._bit():
                    d2 = _w((d2 << 1) | self._bit())
                else:
                    if not self._bit():
                        d6 = 2
                    else:
                        d6 = self.code[0x136 + d7]
                        d7 += 4
                    n = self.code[0x13A + d7]
                    while True:                  # subq.b/bne: 0 heißt 256
                        d2 = _w((d2 << 1) | self._bit())
                        n = (n - 1) & 0xFF
                        if n == 0:
                            break
                    d2 = _w(d2 + d6)
                # Abstand ($164-$1D0)
                d6, a5, d7 = 0, 0, d3
                if self._bit():
                    d3 += d3
                    if self._bit():
                        a5, d7 = self._wort(0x190 + d3), d7 + 8
                    else:
                        a5, d7 = self._wort(0x188 + d3), d7 + 4
                d7 = self.code[0x198 + d7]
                schleife = True
                if d7 & 0x80:                    # ein ganzes Byte, dann Restbits
                    d6 = self._byte()
                    d7 &= 0x0F
                    schleife = d7 != 0
                if schleife:
                    while True:
                        d6 = _w((d6 << 1) | self._bit())
                        d7 = (d7 - 1) & 0xFF
                        if d7 == 0:
                            break
                d6 = _w(d6 + 1)
                a5 += _s(d6) + a3                # adda.w / adda.l
                if a5 > ende:                    # cmpa.l a2,a5 / bls: Ring
                    a5 -= self.groesse
                kopie = pruefen = True
            if pruefen and a5 == 0:              # $1D2: Anfang -> Ende
                a5 = ende
            d5 = _w(d5 - 1)                      # $1D8
            if d5 & 0x8000:
                self.d2, self.d0, self.a5 = d2, d0, a5
                return
            a5 -= 1
            a3 -= 1
            ring[a3] = ring[a5]
            d0 = (d0 - 1) & 0xFF
            kopie = pruefen = d0 != 0


def entpacke(hunks):
    """hunks: Liste aus ambtool.read_hunks().

    Gibt (inhalt, relok) zurück: inhalt = {Hunk: bytes in voller Größe},
    relok = {Hunk: [(Versatz, Zielhunk), ...]}.  Das Programm beginnt am
    Anfang von Hunk 1."""
    code_i = next(h["index"] for h in hunks
                  if h["type"] == "CODE" and h["size"] == 512)
    code = hunks[code_i]["data"]
    strom = hunks[code_i + 1]["data"]
    if hunks[code_i + 1]["type"] != "DATA":
        raise ExeImploderError("hinter dem Entpacker liegt kein DATA-Hunk")
    kern = Kern(strom, code)
    if hunks[code_i + 2]["size"] != kern.groesse:
        raise ExeImploderError("Ringgröße passt nicht zum Hunk dahinter")
    anzahl = struct.unpack_from(">H", code, 0x2A)[0]       # cmpi.w #n,d5
    ziele = list(range(1, anzahl + 1))
    groesse = {h["index"]: h["size"] for h in hunks}
    inhalt = {i: bytearray(groesse[i]) for i in ziele}
    relok = {i: [] for i in ziele}

    lesezeiger = [0]                                         # a2, 0 = leer

    def byte():
        if lesezeiger[0] == 0:
            kern.fuellen()
            lesezeiger[0] = kern.groesse
        lesezeiger[0] -= 1
        return kern.ring[lesezeiger[0]]

    def lang():
        return int.from_bytes(bytes(byte() for _ in range(4)), "big")

    nr = 0
    while True:
        v = lang()
        if v & 0x80000000:
            nr += 1
            if nr == anzahl:
                break
            continue
        hunk = ziele[nr]
        if v & 0x40000000:
            while True:
                n = lang()
                if n == 0:
                    break
                nach = lang() + 1
                versatz = 0
                for _ in range(n):
                    versatz = (versatz + lang()) & 0xFFFFFFFF
                    relok[hunk].append((versatz, nach))
            continue
        if v == 0:
            continue
        if 4 * v > len(inhalt[hunk]):
            raise ExeImploderError(f"Hunk {hunk}: {4 * v} Byte Daten, "
                                   f"Platz für {len(inhalt[hunk])}")
        for j in range(4 * v):
            inhalt[hunk][j] = byte()

    if kern.a0 != 0:
        raise ExeImploderError(f"Selbstprüfung: {kern.a0} Byte des Stroms unverbraucht")
    if kern.zaehler != 0 or not kern.fertig:
        raise ExeImploderError(f"Selbstprüfung: Durchlaufzähler steht auf {kern.zaehler}")
    return {i: bytes(b) for i, b in inhalt.items()}, relok


if __name__ == "__main__":
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from ambtool import read_hunks
    if len(sys.argv) != 3:
        sys.exit("Aufruf: imploder_exe.py <Datei> <Zielverzeichnis>")
    datei, ziel = sys.argv[1], sys.argv[2]
    inhalt, relok = entpacke(read_hunks(open(datei, "rb").read()))
    os.makedirs(ziel, exist_ok=True)
    for i, blob in inhalt.items():
        open(os.path.join(ziel, f"hunk{i:02d}.bin"), "wb").write(blob)
        print(f"Hunk {i}: {len(blob)} Byte, {len(relok[i])} Relokationen")
    with open(os.path.join(ziel, "relok.txt"), "w") as f:
        for i in inhalt:
            for versatz, nach in relok[i]:
                f.write(f"{i} {versatz:06x} {nach}\n")

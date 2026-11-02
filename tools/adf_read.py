#!/usr/bin/env python3
"""adf_read.py -- read the files of an Amiga disk image (ADF, OFS or FFS).

The game data of Thalion's disks and of Pyrdacor's 1.2x come as disk images:
nine or ten ADF (or DMS, which xdms turns into ADF).  tools/game_files.py
puts the files of all disks into one Amberfiles/ folder, as Thalion's
installer does.  This module only reads; it never writes into an image.

Checked while reading: the boot block says DOS, every header block has the
right type and checksum, a file's data blocks add up to its byte size.
Anything else stops with AdfError.

    read(path) -> {"name/of/file": bytes}  (directories as path prefixes)

Usage: adf_read.py IMAGE.adf     list the files with their sizes
"""
import struct
import sys

BLOCK = 512
T_HEADER, T_DATA, T_LIST = 2, 8, 16
ST_ROOT, ST_USERDIR, ST_FILE = 1, 2, -3


class AdfError(Exception):
    pass


def _long(b, o):
    return struct.unpack_from(">I", b, o)[0]


def _slong(b, o):
    return struct.unpack_from(">i", b, o)[0]


class Adf:
    def __init__(self, data, name="image"):
        if len(data) % BLOCK or len(data) < 2 * BLOCK:
            raise AdfError("%s: %d bytes is no disk image" % (name, len(data)))
        self.d = data
        self.name = name
        self.blocks = len(data) // BLOCK
        if data[:3] != b"DOS":
            raise AdfError("%s: no AmigaDOS disk (boot block %r)" % (name, data[:4]))
        self.ffs = data[3] & 1
        self.root = self.blocks // 2

    def block(self, n):
        if not 0 < n < self.blocks:
            raise AdfError("%s: block %d outside the disk" % (self.name, n))
        return self.d[n * BLOCK:(n + 1) * BLOCK]

    def header(self, n, kind=T_HEADER):
        b = self.block(n)
        if _long(b, 0) != kind:
            raise AdfError("%s: block %d has type %d, expected %d"
                            % (self.name, n, _long(b, 0), kind))
        if sum(struct.unpack(">128I", b)) & 0xFFFFFFFF:
            raise AdfError("%s: block %d has a wrong checksum" % (self.name, n))
        return b

    @staticmethod
    def name_von(b):
        n = b[BLOCK - 80]
        return b[BLOCK - 79:BLOCK - 79 + min(n, 30)].decode("latin1")

    def entries(self, n):
        """Block numbers of the entries of directory block n."""
        b = self.header(n)
        seen = set()
        for i in range(72):
            e = _long(b, 24 + 4 * i)
            while e:
                if e in seen:
                    raise AdfError("%s: hash chain loops at block %d" % (self.name, e))
                seen.add(e)
                yield e
                e = _long(self.header(e), BLOCK - 16)

    def file(self, n):
        b = self.header(n)
        size = _long(b, BLOCK - 188)
        parts = []
        header = b
        while True:
            count = _long(header, 8)
            for i in range(count):
                db = _long(header, BLOCK - 204 - 4 * i)
                d = self.block(db)
                if self.ffs:
                    parts.append(d)
                else:
                    if _long(d, 0) != T_DATA:
                        raise AdfError("%s: data block %d has type %d"
                                        % (self.name, db, _long(d, 0)))
                    parts.append(d[24:24 + _long(d, 12)])
            ext = _long(header, BLOCK - 8)
            if not ext:
                break
            header = self.header(ext, T_LIST)
        content = b"".join(parts)
        if len(content) < size:
            raise AdfError("%s: file at block %d has %d of %d bytes"
                            % (self.name, n, len(content), size))
        return content[:size]

    def all_entries(self, n=None, prefix=""):
        n = self.root if n is None else n
        b = self.header(n)
        if n == self.root and _slong(b, BLOCK - 4) != ST_ROOT:
            raise AdfError("%s: block %d is no root block" % (self.name, n))
        result = {}
        for e in self.entries(n):
            k = self.header(e)
            name = prefix + self.name_von(k)
            kind = _slong(k, BLOCK - 4)
            if kind == ST_USERDIR:
                result[name + "/"] = None
                result.update(self.all_entries(e, name + "/"))
            elif kind == ST_FILE:
                result[name] = self.file(e)
            else:
                raise AdfError("%s: %s has the unknown kind %d" % (self.name, name, kind))
        return result


def disk_name(path):
    d = open(path, "rb").read()
    a = Adf(d, path)
    return a.name_von(a.header(a.root))


def read(path):
    """-> {path: bytes}, directories as "path/": None."""
    return Adf(open(path, "rb").read(), path).all_entries()


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__.split("Usage:")[1])
    print("disk %s" % disk_name(sys.argv[1]))
    for name, content in sorted(read(sys.argv[1]).items()):
        print("%9s  %s" % ("dir" if content is None else len(content), name))


if __name__ == "__main__":
    try:
        main()
    except AdfError as e:
        sys.exit("ERROR: %s" % e)

"""m68k.py -- a 68000 on the host, for logging what a music player writes.

Unicorn (``pip install unicorn``, in a venv) runs the player's code.  We call
its routines like subroutines: a return address that points at a stop
marker, ``emu_start`` up to it.  Hardware pages are I/O callbacks; what the
player writes there, the caller logs.

Unicorn's 68k raises ``rte`` as an exception it does not handle itself
(number 256); ``Machine`` pops the 68000 frame (SR, PC) in its hook.  Write
SR before A7: with the S bit, QEMU swaps the stack pointers on an SR write.
"""
import struct
import sys

try:
    from unicorn import Uc, UcError, UC_ARCH_M68K, UC_MODE_BIG_ENDIAN, \
        UC_HOOK_INTR
    from unicorn import m68k_const as K
except ImportError:
    sys.exit("sa_to_ym needs unicorn: python3 -m venv VENV; "
             "VENV/bin/pip install unicorn; run the tool with VENV/bin/python")

RTE = 256                     # QEMU's EXCP_RTE
STOP = 0x400                  # return address of every call; holds a nop
DREGS = [getattr(K, "UC_M68K_REG_D%d" % i) for i in range(8)]
AREGS = [getattr(K, "UC_M68K_REG_A%d" % i) for i in range(8)]


class Machine:
    def __init__(self, ram=0x800000):
        self.uc = Uc(UC_ARCH_M68K, UC_MODE_BIG_ENDIAN,
                     cpu=K.UC_CPU_M68K_M68000)
        self.uc.mem_map(0, ram)
        self.uc.mem_write(STOP, b"\x4e\x71")
        self.uc.hook_add(UC_HOOK_INTR, self._intr)
        self.stack = ram - 0x100
        self.cycles = 0

    def _intr(self, uc, number, _):
        if number != RTE:
            uc.emu_stop()
            raise RuntimeError("68k exception %d at $%X"
                               % (number, uc.reg_read(K.UC_M68K_REG_PC)))
        sp = uc.reg_read(K.UC_M68K_REG_A7)
        sr, pc = struct.unpack(">HI", uc.mem_read(sp, 6))
        uc.reg_write(K.UC_M68K_REG_SR, sr)
        uc.reg_write(K.UC_M68K_REG_A7, sp + 6)
        uc.reg_write(K.UC_M68K_REG_PC, pc)

    def io(self, base, size, read, write):
        """read(offset, size) -> value; write(offset, size, value)."""
        self.uc.mmio_map(base, size,
                         lambda uc, o, s, _: read(o, s) & ((1 << 8 * s) - 1),
                         None,
                         lambda uc, o, s, v, _: write(o, s, v), None)

    def write(self, addr, data):
        self.uc.mem_write(addr, bytes(data))

    def read(self, addr, n):
        return bytes(self.uc.mem_read(addr, n))

    def long(self, addr):
        return struct.unpack(">I", self.read(addr, 4))[0]

    def call(self, addr, d=None, a=None, limit=5_000_000, frame=False):
        """Run the routine at addr until it returns; -> (d, a) registers.
        frame=True enters it as an interrupt handler (ends with rte)."""
        uc = self.uc
        uc.reg_write(K.UC_M68K_REG_SR, 0x2700)
        sp = self.stack
        if frame:
            sp -= 6
            uc.mem_write(sp, struct.pack(">HI", 0x2300, STOP))
        else:
            sp -= 4
            uc.mem_write(sp, struct.pack(">I", STOP))
        uc.reg_write(K.UC_M68K_REG_A7, sp)
        for i, v in (d or {}).items():
            uc.reg_write(DREGS[i], v & 0xFFFFFFFF)
        for i, v in (a or {}).items():
            uc.reg_write(AREGS[i], v & 0xFFFFFFFF)
        try:
            uc.emu_start(addr, STOP, count=limit)
        except UcError as e:
            raise RuntimeError("68k: %s at $%X"
                               % (e, uc.reg_read(K.UC_M68K_REG_PC)))
        if uc.reg_read(K.UC_M68K_REG_PC) != STOP:
            raise RuntimeError("68k: routine at $%X did not return within "
                               "%d instructions" % (addr, limit))
        return ([uc.reg_read(r) for r in DREGS],
                [uc.reg_read(r) for r in AREGS])


def bytes_of(offset, size, value):
    """A write of size bytes at offset -> [(offset, byte)], big-endian."""
    return [(offset + i, (value >> 8 * (size - 1 - i)) & 0xFF)
            for i in range(size)]

"""ym_synth.py -- a YM2149 at 2 MHz in plain Python, from a write log to WAV.

Good enough to listen and compare, not a reference: square tones averaged
over each output sample (less aliasing), the 17-bit noise, the 32-step
envelope with its 16 shapes, a volume table of 1.5 dB per step.  Register
writes take effect at the output sample of their time.

    render(log, clocks, rate) -> bytes of 16-bit mono PCM
    log: [(time in YM clocks, register, value)], sorted by time
"""
import struct
import wave

YM_CLOCK = 2_000_000
LEVEL = [0.0] + [10 ** ((i - 31) * 1.5 / 20) for i in range(1, 32)]


def _square_area(x):
    """Integral of a 0/1 square wave of period 1, high in the first half."""
    n = int(x)
    f = x - n
    return n * 0.5 + (f if f < 0.5 else 0.5)


def render(log, clocks, rate=44100):
    step = YM_CLOCK / rate
    r = [0] * 16
    r[7] = 0xFF
    phase = [0.0, 0.0, 0.0]               # tone phase in periods
    noise_clock, lfsr, noise = 0.0, 1, 1
    env_clock, env_pos, env_att, env_level = 0.0, 0, False, None
    out = bytearray()
    i, n = 0, len(log)
    samples = int(clocks / step)
    for s in range(samples):
        t = s * step
        while i < n and log[i][0] <= t:
            _, reg, v = log[i]
            r[reg] = v
            if reg == 13:
                env_clock, env_pos, env_level = 0.0, 0, None
                env_att = bool(v & 4)
            i += 1
        # noise: shift every 16*NP clocks (NP 0 counts as 1)
        np_ = (r[6] & 0x1F) or 1
        noise_clock += step
        while noise_clock >= 16 * np_:
            noise_clock -= 16 * np_
            bit = (lfsr ^ (lfsr >> 3)) & 1
            lfsr = (lfsr >> 1) | (bit << 16)
            noise = lfsr & 1
        # envelope: 32 steps of 8*EP clocks; at the end of a ramp CONT,
        # HOLD and ALT decide: hold low, hold high or low, or ramp again
        if env_level is None:
            ep = (r[11] | r[12] << 8) or 1
            env_clock += step
            while env_clock >= 8 * ep:
                env_clock -= 8 * ep
                env_pos += 1
                if env_pos < 32:
                    continue
                shape = r[13]
                end = 31 if env_att else 0
                if not shape & 8:
                    env_level = 0
                elif shape & 1:
                    env_level = 31 - end if shape & 2 else end
                else:
                    env_pos = 0
                    if shape & 2:
                        env_att = not env_att
                    continue
                break
        lvl = env_level if env_level is not None else (
            env_pos if env_att else 31 - env_pos)
        mix = 0.0
        for ch in range(3):
            tp = (r[2 * ch] | (r[2 * ch + 1] & 0x0F) << 8) or 1
            per = 16 * tp
            p0 = phase[ch]
            p1 = p0 + step / per
            phase[ch] = p1 - int(p1)
            if r[7] >> ch & 1:
                tone = 1.0
            else:
                tone = (_square_area(p1) - _square_area(p0)) / (p1 - p0)
            if not r[7] >> (ch + 3) & 1:
                tone *= noise
            v = r[8 + ch]
            amp = LEVEL[lvl] if v & 0x10 else LEVEL[(v & 0x0F) * 2 + 1 if v & 0x0F else 0]
            mix += tone * amp
        out += struct.pack("<h", int(mix * 10900) - 16000)
    return bytes(out)


def save_wav(path, pcm, rate=44100):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm)

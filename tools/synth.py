"""Tiny software synthesizer: renders original Western-flavoured music + SFX to 16-bit WAV."""
import numpy as np, math, wave, os, struct, random

SR = 44100


def env(n, attack=0.005, decay=0.0, sustain=1.0, release=0.05, sr=SR):
    a = int(attack * sr); d = int(decay * sr); r = int(release * sr)
    e = np.ones(n, dtype=np.float32)
    if a > 0:
        a = min(a, n)
        e[:a] = np.linspace(0, 1, a)
    if d > 0 and a + d < n:
        d = min(d, n - a)
        e[a:a + d] = np.linspace(1, sustain, d)
        e[a + d:] = sustain
    if r > 0:
        r = min(r, n)
        e[n - r:] *= np.linspace(1, 0, r)
    return e


def noise(n, seed=0):
    rng = np.random.default_rng(seed)
    return rng.standard_normal(n).astype(np.float32) * 0.5


def _onepole(x, a):
    """y[i] = (1-a)x[i] + a y[i-1] — pure python loop (fast enough for short buffers)."""
    y = np.empty_like(x)
    acc = float(x[0])
    la = float(a)
    l1a = 1.0 - la
    xl = x.tolist()
    out = [0.0] * len(xl)
    for i, v in enumerate(xl):
        acc = l1a * v + la * acc
        out[i] = acc
    return np.array(out, dtype=np.float32)


def lowpass(x, cutoff, sr=SR, order=2):
    a = math.exp(-2 * math.pi * cutoff / sr)
    y = x.astype(np.float32)
    for _ in range(order):
        y = _onepole(y, a)
    return y


def highpass(x, cutoff, sr=SR, order=1):
    return x - lowpass(x, cutoff, sr, order)


def pluck(freq, dur, sr=SR, amp=0.5, bright=0.5, decay=3.0):
    """Karplus-Strong plucked string."""
    n = int(dur * sr)
    N = max(2, int(sr / freq))
    rng = np.random.default_rng(int(freq * 1000) & 0xffff)
    buf = rng.uniform(-1, 1, N).astype(np.float32)
    buf = lowpass(buf, 2000 + 6000 * bright, sr, 1).tolist()
    out = np.empty(n, dtype=np.float32)
    damp = math.exp(-decay / max(1.0, freq) * 0.15)
    idx = 0
    for i in range(n):
        v = buf[idx]
        out[i] = v
        nxt = buf[(idx + 1) % N]
        buf[idx] = 0.5 * (v + nxt) * damp
        idx = (idx + 1) % N
    return out * amp * env(n, 0.002, 0.02, 1.0, min(0.2, dur * 0.3))


def tone(freq, dur, kind='sine', amp=0.3, harm=(1.0,), sr=SR):
    n = int(dur * sr)
    t = np.arange(n) / sr
    w = np.zeros(n, dtype=np.float32)
    for k, h in enumerate(harm, start=1):
        if kind == 'saw':
            w += h * np.sin(2 * np.pi * freq * k * t) / k
        elif kind == 'square':
            w += h * np.sign(np.sin(2 * np.pi * freq * k * t)) / k
        else:
            w += h * np.sin(2 * np.pi * freq * k * t)
    return w.astype(np.float32) * amp


def reverb(x, mix=0.25, delays=(0.031, 0.047, 0.067, 0.089), sr=SR):
    out = x.copy()
    for i, d in enumerate(delays):
        k = int(d * sr)
        g = mix * (0.7 ** i)
        y = np.zeros_like(x)
        y[k:] = x[:-k] * g
        out += y
    return out


def write_wav(path, x, sr=SR):
    x = np.asarray(x, dtype=np.float32)
    m = np.max(np.abs(x)) or 1.0
    if m > 0.99:
        x = x / m * 0.99
    data = (x * 32767).astype('<i2').tobytes()
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(data)
    print('wrote', path, len(x) / sr, 's')

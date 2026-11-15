#!/usr/bin/env python3
"""Synthesises the calm background music (made for this project, no samples):
  assets/audio/music.wav   64 s seamless loop: bamboo-flute melody and soft harp over a warm drone,
                           with birdsong and a quiet stream underneath.
Run from the repo root:  python3 tools/build_music.py
"""
import wave
import numpy as np
SR = 22050
BEAT = 1.0                      # 60 BPM, 64 beats
L = int(64 * BEAT * SR)
rng = np.random.default_rng(11)
buf = np.zeros(L)
T = np.arange(L) / SR

def add(at, snd, gain=1.0):
    idx = (int(at * SR) + np.arange(len(snd))) % L
    np.add.at(buf, idx, snd * gain)

def hz(semi):                   # semitones above D3
    return 146.83 * 2 ** (semi / 12.0)

PENTA = [0, 2, 4, 7, 9, 12, 14, 16, 19, 21, 24]      # D major pentatonic

def flute(f, dur):
    n = int((dur + 0.5) * SR); t = np.arange(n) / SR
    vib = 1.0 + 0.006 * np.sin(2 * np.pi * 5.0 * t) * np.clip(t / 0.6, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    x = np.sin(ph) + 0.28 * np.sin(2 * ph) + 0.08 * np.sin(3 * ph)
    breath = rng.standard_normal(n); breath = np.convolve(breath, np.ones(8) / 8, 'same') * 0.10
    env = np.clip(t / 0.12, 0, 1) * np.clip((dur + 0.5 - t) / 0.5, 0, 1)
    return (x + breath) * env

def harp(f, dur=2.6):
    n = int(dur * SR); t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 3) + 0.15 * np.sin(2 * np.pi * 3 * f * t) * np.exp(-t * 6)
    return x * np.exp(-t * 2.2) * np.clip(t / 0.004, 0, 1)

def pad(semis, dur):
    n = int((dur + 2.0) * SR); t = np.arange(n) / SR; x = np.zeros(n)
    for s in semis:
        for det in (-0.6, 0.6):
            x += np.sin(2 * np.pi * (hz(s) + det) * t + rng.uniform(0, 6.28))
    env = np.clip(t / 2.0, 0, 1) * np.clip((dur + 2.0 - t) / 2.0, 0, 1)
    return x * env / len(semis)

def chirp(f0, f1, dur, wob=0.0):
    n = int(dur * SR); t = np.arange(n) / SR
    f = f0 + (f1 - f0) * (t / dur) + wob * np.sin(2 * np.pi * 28 * t)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / dur) ** 2

# warm drone: four chords of 16 beats (D, Bm, G, D)
for i, ch in enumerate([[-12, 0, 7, 16], [-15, -3, 4, 12], [-19, -7, 2, 11], [-12, 0, 7, 14]]):
    add(i * 16 - 1.0, pad(ch, 16.0), 0.16)

# harp: slow rising arpeggios, one note per beat
arps = [[0, 7, 12, 16], [-3, 4, 9, 12], [-7, 2, 7, 11], [0, 7, 12, 14]]
for b in range(64):
    a = arps[b // 16]
    step = b % 8
    if step < 4: add(b * BEAT, harp(hz(a[step])), 0.17)
    elif step == 5: add(b * BEAT, harp(hz(a[2])), 0.10)

# flute: a slow phrase in each 16 beats, (start beat, length, pentatonic step)
phrases = [
    [(2, 3, 5), (5, 1, 6), (6, 2, 7), (8, 4, 6), (13, 2, 5)],
    [(1, 2, 4), (3, 1, 5), (4, 3, 7), (8, 2, 6), (10, 4, 4)],
    [(2, 2, 6), (4, 1, 7), (5, 3, 8), (9, 1, 7), (10, 4, 6)],
    [(1, 3, 7), (4, 1, 6), (5, 2, 5), (8, 5, 5)],
]
for i, ph in enumerate(phrases):
    for st, ln, deg in ph:
        add((i * 16 + st) * BEAT, flute(hz(PENTA[deg] + 12), ln * BEAT), 0.20)

# birdsong: three kinds of call scattered through the loop
t = 1.5
while t < 62.0:
    kind = rng.integers(3); g = rng.uniform(0.03, 0.07)
    if kind == 0:                                   # rising tweets
        for k in range(rng.integers(2, 5)):
            add(t + k * 0.16, chirp(2600 + rng.uniform(-300, 300), 3900, 0.09), g)
    elif kind == 1:                                 # trill
        base = rng.uniform(3200, 4400)
        for k in range(rng.integers(5, 10)):
            add(t + k * 0.07, chirp(base, base - 500, 0.05), g * 0.8)
    else:                                           # two-note whistle
        add(t, chirp(2100, 2300, 0.28, 30), g); add(t + 0.36, chirp(1750, 1700, 0.4, 25), g)
    t += rng.uniform(1.6, 4.5)

# quiet stream: band-limited noise with a slow swell that repeats exactly over the loop
n = rng.standard_normal(L)
spec = np.fft.rfft(n); fr = np.fft.rfftfreq(L, 1 / SR)
spec *= np.exp(-((np.log(np.maximum(fr, 1.0) / 1800.0)) ** 2) / 0.5)
stream = np.fft.irfft(spec, L); stream /= np.abs(stream).max()
buf += stream * (0.035 + 0.015 * np.sin(2 * np.pi * T / 16.0))

x = buf / np.abs(buf).max() * 0.85
with wave.open('assets/audio/music.wav', 'wb') as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype('<i2').tobytes())
print('music', L / SR, 's')

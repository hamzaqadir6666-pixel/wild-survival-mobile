#!/usr/bin/env python3
"""Synthesises the two 'you are being hunted' loops (made for this project, no samples):
  assets/audio/chase.wav      8 s tense drum + drone loop at 150 BPM
  assets/audio/heartbeat.wav  one lub-dub, 0.8 s, looped (the game changes its speed)
Run from the repo root:  python3 tools/build_chase_audio.py
"""
import wave
import numpy as np
SR = 22050

def save(name, x):
    x = x / max(1e-9, np.abs(x).max()) * 0.89
    with wave.open(f'assets/audio/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype('<i2').tobytes())
    print(name, round(len(x) / SR, 2), 's')

def add(buf, at, snd, gain=1.0):
    """mix a sound into the loop, wrapping round the end so the loop is seamless"""
    i = int(at * SR) % len(buf); n = len(snd)
    idx = (i + np.arange(n)) % len(buf)
    np.add.at(buf, idx, snd * gain)

def drum(f0, f1, dur, decay, click=0.0):
    t = np.arange(int(dur * SR)) / SR
    f = f1 + (f0 - f1) * np.exp(-t * 28.0)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * decay)
    if click > 0: x[:60] += np.linspace(click, 0, 60) * np.sign(np.sin(np.arange(60)))
    return x

def noise_hit(dur, decay, rng, hp=0.9):
    n = rng.standard_normal(int(dur * SR)); n = n - hp * np.concatenate([[0], n[:-1]])      # crude high-pass
    return n * np.exp(-np.arange(len(n)) / SR * decay)

def chase():
    rng = np.random.default_rng(7); beat = 60.0 / 150.0; L = int(round(20 * beat * SR)); buf = np.zeros(L)
    t = np.arange(L) / SR
    # driving low drum: every beat, with pushed off-beats
    for b in range(20):
        add(buf, b * beat, drum(150, 52, 0.42, 9.0, 0.3), 1.0)
        if b % 4 in (1, 3): add(buf, (b + 0.5) * beat, drum(120, 60, 0.3, 13.0), 0.6)
        if b % 4 == 3: add(buf, (b + 0.75) * beat, drum(190, 90, 0.2, 16.0), 0.5)
    # shaker on the 16ths, louder on the off-beat
    for s in range(80):
        add(buf, s * beat / 4, noise_hit(0.07, 55.0, rng), 0.10 if s % 2 else 0.05)
    # snare-like hit on beats 2 and 4
    for b in range(1, 20, 2):
        add(buf, b * beat, noise_hit(0.22, 20.0, rng, 0.6), 0.28)
    # pulsing bass drone on A with a tremolo in 8ths, and a minor-second clash that swells every bar
    trem = 0.55 + 0.45 * np.sin(2 * np.pi * t / (beat / 2)) ** 2
    bass = sum(np.sin(2 * np.pi * 55.0 * k * t) / k for k in (1, 2, 3)) * trem * 0.30
    bar = 4 * beat; swell = ((t % bar) / bar) ** 2
    clash = (np.sin(2 * np.pi * 220.0 * t) + np.sin(2 * np.pi * 233.08 * t) + 0.5 * np.sin(2 * np.pi * 329.63 * t)) * swell * 0.11
    save('chase', buf + bass + clash)

def heartbeat():
    L = int(0.8 * SR); buf = np.zeros(L)
    add(buf, 0.02, drum(95, 42, 0.26, 17.0), 1.0)      # lub
    add(buf, 0.27, drum(80, 38, 0.24, 20.0), 0.7)      # dub
    save('heartbeat', buf)

if __name__ == '__main__':
    chase(); heartbeat()

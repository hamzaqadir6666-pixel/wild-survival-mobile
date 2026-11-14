#!/usr/bin/env python3
"""Cuts the downloaded ESC-50 / freesound clips (CC0 and CC-BY only, see CREDITS.md)
into the game's sounds: 22.05 kHz mono 16-bit WAV, seamless loops for ambience,
single one-shots for calls, steps and splashes.   Run: python3 tools/build_audio.py
"""
import wave, os, numpy as np
SRC = 'assets_src/esc50'; OUT = 'assets/audio'; SR = 22050

def read(name):
    w = wave.open(f'{SRC}/{name}'); n = w.getnframes(); a = np.frombuffer(w.readframes(n), np.int16).astype(np.float32) / 32768
    if w.getnchannels() == 2: a = a.reshape(-1, 2).mean(1)
    assert w.getframerate() == 44100
    a = a[:len(a) // 2 * 2].reshape(-1, 2).mean(1)  # 44.1k -> 22.05k
    return a

def write(name, a, peak=0.9):
    m = np.abs(a).max()
    if m > 0: a = a / m * peak
    w = wave.open(f'{OUT}/{name}.wav', 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.clip(a, -1, 1) * 32767).astype(np.int16).tobytes()); w.close()

def trim(a, thr=0.02):
    env = np.abs(a); idx = np.where(env > thr * env.max())[0]
    return a[max(0, idx[0] - 200): idx[-1] + 400] if len(idx) else a

def fade(a, fin=0.005, fout=0.04):
    a = a.copy(); i = int(fin * SR); o = min(int(fout * SR), len(a) // 2)
    a[:i] *= np.linspace(0, 1, i); a[-o:] *= np.linspace(1, 0, o); return a

def loop(a, xf=0.6):
    a = trim(a, 0.001); n = int(xf * SR); body = a[n:].copy()
    t = np.linspace(0, 1, n); body[-n:] = body[-n:] * np.sqrt(1 - t) + a[:n] * np.sqrt(t); return body

def shots(a, count, length, pre=0.02, gap=0.25):
    hop = 220; env = np.array([np.sqrt((a[i:i + hop] ** 2).mean()) for i in range(0, len(a) - hop, hop)])
    out = []; e = env.copy()
    for _ in range(count):
        k = int(np.argmax(e))
        if e[k] <= 0: break
        s = max(0, k * hop - int(pre * SR)); out.append(fade(a[s:s + int(length * SR)], 0.003, length * 0.5))
        g = int(gap * SR / hop); e[max(0, k - g):k + g] = 0
    return out

def call(a, maxlen=3.0):
    return fade(trim(a, 0.04)[:int(maxlen * SR)], 0.01, 0.15)

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    for out, src in {'amb_day': '1-38559-A-14.wav', 'amb_night': '1-59102-A-13.wav', 'amb_water': '1-43760-A-11.wav',
                     'amb_rain': '1-21189-A-10.wav', 'amb_wind': '5-117773-A-16.wav'}.items():
        write(out, loop(read(src)), 0.8)
    for out, src in {'thunder1': '1-101296-A-19.wav', 'thunder2': '1-101296-B-19.wav'}.items():
        write(out, fade(read(src), 0.02, 1.0))
    for out, (src, ln) in {'growl': ('2-117271-A-0.wav', 2.2), 'roar': ('1-202111-A-3.wav', 3.0), 'snarl': ('3-146964-A-5.wav', 2.5),
                           'howl': ('3-146965-A-5.wav', 3.5), 'laugh': ('5-259514-A-26.wav', 2.6), 'hiss': ('5-261464-A-23.wav', 2.0),
                           'grunt': ('3-257858-A-2.wav', 1.6), 'bleat': ('2-119161-A-8.wav', 1.8), 'moo': ('1-58277-A-3.wav', 2.5),
                           'rooster': ('1-34119-A-1.wav', 2.6), 'crow': ('1-56233-A-9.wav', 2.0), 'eat': ('3-169907-A-29.wav', 1.6),
                           'drink': ('1-37226-A-29.wav', 1.8)}.items():
        write(out, call(read(src), ln))
    for i, s in enumerate(shots(read('4-218304-A-25.wav'), 4, 0.22)): write(f'step{i + 1}', s, 0.7)
    for i, s in enumerate(shots(read('1-50623-A-15.wav'), 3, 0.45, gap=0.4)): write(f'splash{i + 1}', s, 0.8)
    write('click', shots(read('2-152964-A-31.wav'), 1, 0.08)[0], 0.6)
    write('thud', shots(read('1-103995-A-30.wav'), 1, 0.3)[0], 0.9)
    tot = 0
    for f in sorted(os.listdir(OUT)):
        if f.endswith('.wav'):
            w = wave.open(f'{OUT}/{f}'); print(f, round(w.getnframes() / SR, 2), 's'); tot += os.path.getsize(f'{OUT}/{f}')
    print('total KB', tot // 1024)

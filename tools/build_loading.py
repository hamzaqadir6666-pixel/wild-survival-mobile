#!/usr/bin/env python3
"""Loading screen art, app icon and loading sounds.
  preview_tmp/loading_src.png, preview_tmp/icon_src.png  AI-generated pictures made for this project (copies kept in assets_src/art/)
    -> assets/ui/loading.jpg (1280x720), icon.png (512), assets/ui/icon_fg.png (432, adaptive-icon foreground)
  assets/audio/loading.wav  8 s loop: the game's own forest and wind recordings under a slow drum and a low drone
  assets/audio/ready.wav    short rising chime played when loading has finished
Run from the repo root:  python3 tools/build_loading.py
"""
import os, wave
import numpy as np
from PIL import Image
SR = 22050

def art():
    src = 'assets_src/art'
    im = Image.open(f'{src}/loading.png').convert('RGB')
    w, h = im.size; th = int(round(w * 9 / 16))
    if th <= h: im = im.crop((0, (h - th) // 2, w, (h - th) // 2 + th))
    im.resize((1280, 720), Image.LANCZOS).save('assets/ui/loading.jpg', quality=88)
    ic = Image.open(f'{src}/icon.png').convert('RGB')
    ic.resize((512, 512), Image.LANCZOS).save('icon.png', optimize=True)
    # adaptive icon: Android crops to the middle 66 %, so the picture is shrunk onto a matching dark canvas
    fg = Image.new('RGB', (432, 432), (10, 22, 14)); small = ic.resize((300, 300), Image.LANCZOS); fg.paste(small, (66, 66))
    fg.save('assets/ui/icon_fg.png', optimize=True)
    Image.new('RGB', (432, 432), (10, 22, 14)).save('assets/ui/icon_bg.png', optimize=True)

def read(name):
    with wave.open(f'assets/audio/{name}.wav', 'rb') as w:
        x = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(float) / 32768.0
        assert w.getframerate() == SR and w.getnchannels() == 1
    return x

def save(name, x, peak=0.89):
    x = x / max(1e-9, np.abs(x).max()) * peak
    with wave.open(f'assets/audio/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes((x * 32767).astype('<i2').tobytes())
    print(name, round(len(x) / SR, 2), 's')

def sound():
    L = 8 * SR; t = np.arange(L) / SR
    def bed(name):      # a recording wrapped to the loop length with a cross-fade at the seam
        x = read(name); x = np.tile(x, int(np.ceil((L + SR) / len(x))))[:L + SR]
        f = np.linspace(0, 1, SR); y = x[:L].copy(); y[:SR] = y[:SR] * f + x[L:L + SR] * (1 - f)
        return y / max(1e-9, np.abs(y).max())
    buf = bed('amb_day') * 0.55 + bed('amb_wind') * 0.30
    # low drone on D with a slow swell, and a soft drum every two seconds (heart of the forest)
    buf += (np.sin(2 * np.pi * 73.42 * t) + 0.5 * np.sin(2 * np.pi * 110.0 * t) + 0.25 * np.sin(2 * np.pi * 146.83 * t)) * (0.16 + 0.08 * np.sin(2 * np.pi * t / 8.0))
    for k in range(4):
        for off, g in ((0.0, 0.5), (0.28, 0.3)):
            n = int(0.5 * SR); tt = np.arange(n) / SR
            f = 48 + 70 * np.exp(-tt * 26); hit = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 9) * g
            i = int((k * 2.0 + off) * SR); idx = (i + np.arange(n)) % L; np.add.at(buf, idx, hit)
    save('loading', buf, 0.8)
    # ready chime: three rising soft mallet notes (D A D)
    n = int(1.6 * SR); tt = np.arange(n) / SR; out = np.zeros(n)
    for k, f in enumerate((293.66, 440.0, 587.33)):
        st = int(k * 0.11 * SR); m = n - st; u = np.arange(m) / SR
        out[st:] += (np.sin(2 * np.pi * f * u) + 0.3 * np.sin(2 * np.pi * 2 * f * u) * np.exp(-u * 8)) * np.exp(-u * 3.2) * np.clip(u / 0.005, 0, 1)
    save('ready', out, 0.7)

if __name__ == '__main__':
    art(); sound()

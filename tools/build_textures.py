#!/usr/bin/env python3
"""Generates the small tileable textures the game uses (ground, fur patterns,
foliage detail, water ripples, clouds, soft sprites). They are made here with
filtered noise because no free texture site could be reached from the build
machine; swap in photo textures with the same file names at any time.
Run: python3 tools/build_textures.py
"""
import os, numpy as np
from PIL import Image, ImageDraw, ImageFilter
OUT = 'assets/textures'; rng = np.random.default_rng(7)

def fnoise(n, beta, seed, aniso=(1.0, 1.0)):
    """Tileable noise with a 1/f^beta spectrum, normalised to 0..1."""
    r = np.random.default_rng(seed); fy = np.fft.fftfreq(n)[:, None] * aniso[1]; fx = np.fft.fftfreq(n)[None, :] * aniso[0]
    f = np.sqrt(fx * fx + fy * fy); f[0, 0] = 1
    spec = (r.normal(size=(n, n)) + 1j * r.normal(size=(n, n))) / f ** beta; spec[0, 0] = 0
    a = np.real(np.fft.ifft2(spec)); a = (a - a.mean()) / a.std()
    return np.clip(0.5 + a * 0.22, 0, 1)

def ramp(v, stops):
    xs = [s[0] for s in stops]; out = np.zeros(v.shape + (3,))
    for c in range(3): out[..., c] = np.interp(v, xs, [s[1][c] for s in stops])
    return out

def save(name, rgb, mode='RGB'):
    Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), mode).save(f'{OUT}/{name}.png', optimize=True)

def ground(name, n, stops, seed, beta=1.6, grain=0.10, extra=None):
    v = fnoise(n, beta, seed) * 0.7 + fnoise(n, 0.9, seed + 1) * 0.3
    col = ramp(v, stops) * (1 - grain + 2 * grain * fnoise(n, 0.35, seed + 2)[..., None])
    if extra is not None: col = extra(col, n, seed)
    save(name, col)

def grass_extra(col, n, seed):  # soft short strokes instead of thin blades
    s = fnoise(n, 1.1, seed + 5, (0.35, 1.6))[..., None]; return col * (0.86 + 0.28 * s)

def litter_extra(col, n, seed):  # scattered fallen leaves
    im = Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)); d = ImageDraw.Draw(im); r = np.random.default_rng(seed)
    for _ in range(n * n // 900):
        x, y = r.integers(0, n, 2); w, h = r.integers(5, 13), r.integers(3, 7); c = r.choice([0, 1, 2])
        colr = [(92, 66, 34), (112, 86, 40), (58, 70, 30)][c]
        for ox in (-n, 0, n):
            for oy in (-n, 0, n): d.ellipse([x + ox, y + oy, x + ox + w, y + oy + h], fill=colr)
    return np.asarray(im.filter(ImageFilter.GaussianBlur(0.7))) / 255.0

def rock_extra(col, n, seed):
    c = np.abs(fnoise(n, 1.9, seed + 9) - 0.5) * 2; crack = np.clip(c * 9, 0, 1)[..., None]
    return col * (0.55 + 0.45 * crack)

def fur(name, kind, n=256, seed=3):
    fine = fnoise(n, 0.7, seed, (2.2, 0.5)); mask = np.ones((n, n))
    y, x = np.mgrid[0:n, 0:n] / n
    if kind == 'stripes':  # wavy vertical bands that taper, tiger-like
        w = fnoise(n, 2.2, seed + 1); ph = x * 9 + (w - 0.5) * 3.2 + np.sin(y * 2 * np.pi) * 0.25
        band = np.abs((ph % 1.0) - 0.5) * 2; thick = 0.34 + 0.25 * fnoise(n, 1.8, seed + 2)
        mask = np.clip((band - thick) * 7 + 0.5, 0, 1)
    elif kind in ('spots', 'blotch'):
        im = Image.new('L', (n, n), 255); d = ImageDraw.Draw(im); r = np.random.default_rng(seed + 4)
        cnt, lo, hi = (170, 4, 8) if kind == 'spots' else (46, 9, 20)
        for _ in range(cnt):
            px, py = r.integers(0, n, 2); a, b = r.integers(lo, hi, 2)
            for ox in (-n, 0, n):
                for oy in (-n, 0, n): d.ellipse([px + ox, py + oy, px + ox + a, py + oy + b], fill=0 if kind == 'spots' else int(r.integers(30, 110)))
        mask = np.asarray(im.filter(ImageFilter.GaussianBlur(1.0 if kind == 'spots' else 2.2))) / 255.0
    elif kind == 'scales':
        cx = (x * 14) % 1 - 0.5; cy = ((y * 14) + (np.floor(x * 14) % 2) * 0.5) % 1 - 0.5
        mask = np.clip(1.25 - np.sqrt(cx * cx + cy * cy) * 2.3, 0, 1); fine = fnoise(n, 0.9, seed)
    elif kind == 'fawn':
        im = Image.new('L', (n, n), 255); d = ImageDraw.Draw(im); r = np.random.default_rng(seed + 8)
        for _ in range(60):
            px, py = r.integers(0, n, 2); a = int(r.integers(6, 11)); d.ellipse([px, py, px + a, py + a], fill=0)
        mask = np.asarray(im.filter(ImageFilter.GaussianBlur(1.2))) / 255.0
    save(name, np.stack([mask, fine, np.zeros((n, n))], -1))

def radial(name, n, power, inner=0.0, col=(1, 1, 1)):
    y, x = np.mgrid[0:n, 0:n]; d = np.sqrt((x - n / 2 + 0.5) ** 2 + (y - n / 2 + 0.5) ** 2) / (n / 2)
    a = np.clip((1 - d) / (1 - inner), 0, 1) ** power
    Image.fromarray((np.dstack([np.ones((n, n, 3)) * np.array(col), a]) * 255).astype(np.uint8), 'RGBA').save(f'{OUT}/{name}.png')

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    ground('t_grass', 512, [(0.2, (0.16, 0.30, 0.08)), (0.5, (0.25, 0.42, 0.13)), (0.8, (0.36, 0.50, 0.18))], 11, extra=grass_extra)
    ground('t_forest', 512, [(0.2, (0.13, 0.11, 0.06)), (0.5, (0.22, 0.19, 0.10)), (0.8, (0.30, 0.27, 0.14))], 21, extra=litter_extra)
    ground('t_dirt', 512, [(0.2, (0.30, 0.21, 0.13)), (0.5, (0.43, 0.31, 0.20)), (0.8, (0.54, 0.41, 0.27))], 31, beta=1.3, grain=0.16)
    ground('t_sand', 512, [(0.2, (0.62, 0.53, 0.36)), (0.5, (0.74, 0.65, 0.46)), (0.8, (0.82, 0.74, 0.56))], 41, beta=1.2, grain=0.12)
    ground('t_mud', 512, [(0.2, (0.15, 0.11, 0.07)), (0.5, (0.24, 0.18, 0.12)), (0.8, (0.33, 0.26, 0.18))], 51, beta=1.8, grain=0.07)
    ground('t_rock', 512, [(0.2, (0.30, 0.29, 0.27)), (0.5, (0.45, 0.44, 0.41)), (0.8, (0.60, 0.58, 0.54))], 61, beta=1.5, grain=0.12, extra=rock_extra)
    for nm, k in [('fur_plain', 'plain'), ('fur_stripes', 'stripes'), ('fur_spots', 'spots'), ('fur_blotch', 'blotch'), ('fur_scales', 'scales'), ('fur_fawn', 'fawn')]: fur(nm, k)
    leaf = np.clip((fnoise(256, 1.5, 71) - 0.5) * 2.4 + 0.5, 0, 1); bark = fnoise(256, 1.2, 72, (3.0, 0.25))
    save('veg_detail', np.stack([leaf, bark, fnoise(256, 0.6, 73)], -1))
    rip = fnoise(256, 1.7, 81); rip = np.abs(rip - 0.5) * 2; save('water_ripple', np.stack([1 - rip, fnoise(256, 1.4, 82), fnoise(256, 2.0, 83)], -1))
    cl = fnoise(512, 2.1, 91) * 0.75 + fnoise(512, 1.2, 92) * 0.25; Image.fromarray((np.clip((cl - 0.47) * 4.2, 0, 1) * 255).astype(np.uint8), 'L').save(f'{OUT}/clouds.png')
    radial('blob', 64, 1.6); radial('glow', 64, 2.2); radial('sun', 128, 3.0, 0.0, (1.0, 0.95, 0.8))
    # moon: disc with soft craters
    n = 128; y, x = np.mgrid[0:n, 0:n]; d = np.sqrt((x - 63.5) ** 2 + (y - 63.5) ** 2) / 64
    disc = np.clip((0.62 - d) * 30, 0, 1); halo = np.clip(1 - d, 0, 1) ** 3 * 0.35
    tone = 0.80 + 0.20 * fnoise(n, 1.8, 95); a = np.clip(disc + halo, 0, 1)
    Image.fromarray((np.dstack([tone * 0.95, tone * 0.97, tone, a]) * 255).astype(np.uint8), 'RGBA').save(f'{OUT}/moon.png')
    # app icon: deer-brown badge with a leaf-green ring (simple, replace freely)
    ic = Image.new('RGBA', (192, 192), (0, 0, 0, 0)); dr = ImageDraw.Draw(ic)
    dr.ellipse([4, 4, 188, 188], fill=(38, 92, 44, 255)); dr.ellipse([22, 22, 170, 170], fill=(150, 100, 58, 255))
    dr.polygon([(96, 44), (132, 110), (96, 150), (60, 110)], fill=(235, 220, 190, 255)); ic.save('icon.png')
    print('textures written:', sorted(os.listdir(OUT)))

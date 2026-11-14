#!/usr/bin/env python3
"""Builds the hand-designed 1 km x 1 km map of Wild Survival.
Everything about the map is decided here once, so it is identical in every game:
heights, ground blend weights, biome grid, river, lakes, clearings, trails, safe
thickets, landmarks, the ~70 fixed rare plants, predator dens and every tree/bush.
Outputs (assets/world): heights.bin, splat.bin, biome.bin, veg.bin, world.json, map.png
Run: python3 tools/build_world.py [--preview]
"""
import os, sys, json, struct
import numpy as np
from PIL import Image
OUT = 'assets/world'; SIZE = 1024.0; CELL = 4.0; N = 257
RIVER = [(560, -30), (540, 90), (600, 200), (560, 320), (500, 430), (540, 540), (610, 640), (570, 760), (520, 880), (550, 1054)]
LAKES = [('Mirror Lake', 300, 300, 55), ('Reed Pond', 760, 520, 40), ('Moon Pool', 330, 760, 46)]
CLEARINGS = [('Sunrise Meadow', 180, 180, 38), ('Fern Hollow', 440, 170, 30), ('Hawk Field', 800, 200, 42), ('East Lawn', 690, 380, 34),
             ('Heart Meadow', 400, 520, 36), ('Moon Meadow', 220, 640, 34), ('Boar Flats', 840, 700, 40), ('South Green', 430, 890, 36), ('Quiet Green', 690, 860, 34)]
TRAIL_EDGES = [(0, 1), (1, 2), (1, 4), (2, 3), (3, 6), (3, 4), (4, 5), (5, 7), (7, 8), (8, 6), (0, 5)]
THICKETS = [(300, 440), (620, 250), (880, 430), (690, 640), (240, 880), (820, 880)]
THICKET_R = 11.0
LANDMARKS = [('salt_lick', 'Western Salt Lick', 150, 420), ('salt_lick', 'Eastern Salt Lick', 880, 560),
             ('giant_tree', 'Old Father Fig', 520, 250), ('giant_tree', 'The Grandmother Tree', 160, 760), ('giant_tree', 'Twisted Elder', 760, 760),
             ('berry_glade', 'North Berry Glade', 350, 130), ('berry_glade', 'River Berry Glade', 630, 470), ('berry_glade', 'South Berry Glade', 330, 930),
             ('banana_grove', 'Banana Grove', 835, 500)]
PLANT_COUNTS = [('clover', 14), ('moonpetal', 3), ('ironbark', 7), ('sunberry', 7), ('ghostfern', 3), ('owleye', 3), ('springlily', 3),
                ('lotus', 3), ('herb', 10), ('honey', 7), ('toadstool', 10)]
VEG = ['tree_a', 'tree_b', 'tree_c', 'tree_d', 'tree_big', 'tree_giant', 'palm_a', 'palm_b', 'banana', 'fern_a', 'fern_b',
       'bush_a', 'bush_b', 'bush_berry', 'tall_grass', 'lily', 'rock_a', 'rock_b', 'rock_c']
VI = {n: i for i, n in enumerate(VEG)}

def fnoise(n, beta, seed):
    r = np.random.default_rng(seed); fy = np.fft.fftfreq(n)[:, None]; fx = np.fft.fftfreq(n)[None, :]
    f = np.sqrt(fx * fx + fy * fy); f[0, 0] = 1
    spec = (r.normal(size=(n, n)) + 1j * r.normal(size=(n, n))) / f ** beta; spec[0, 0] = 0
    a = np.real(np.fft.ifft2(spec)); return (a - a.mean()) / a.std()

def sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)

def seg_dist(px, pz, a, b):
    ax, az = a; bx, bz = b; dx, dz = bx - ax, bz - az
    t = np.clip(((px - ax) * dx + (pz - az) * dz) / (dx * dx + dz * dz), 0, 1)
    return np.hypot(px - (ax + t * dx), pz - (az + t * dz))

def poly_dist(px, pz, pts):
    d = np.full(np.shape(px), 1e9)
    for a, b in zip(pts[:-1], pts[1:]): d = np.minimum(d, seg_dist(px, pz, a, b))
    return d

def trail_points(a, b, k):
    ax, az = CLEARINGS[a][1:3]; bx, bz = CLEARINGS[b][1:3]; r = np.random.default_rng(100 + k); pts = []
    n = max(3, int(np.hypot(bx - ax, bz - az) / 28)); nx, nz = -(bz - az), (bx - ax); L = np.hypot(nx, nz); nx /= L; nz /= L
    for i in range(n + 1):
        t = i / n; w = np.sin(t * np.pi) * r.uniform(-14, 14)
        px, pz = ax + (bx - ax) * t + nx * w, az + (bz - az) * t + nz * w
        for (_, lx, lz, lr) in LAKES:  # trails walk around lakes
            d = np.hypot(px - lx, pz - lz)
            if d < lr * 1.2 + 16: px, pz = lx + (px - lx) / max(d, 1) * (lr * 1.2 + 16), lz + (pz - lz) / max(d, 1) * (lr * 1.2 + 16)
        pts.append((px, pz))
    return pts
TRAILS = [trail_points(a, b, k) for k, (a, b) in enumerate(TRAIL_EDGES)]

def fields(X, Z):
    """All analytic map fields at world positions X, Z (arrays)."""
    lake_s = np.full(X.shape, 1e9)
    for k, (_, lx, lz, lr) in enumerate(LAKES):
        th = np.arctan2(Z - lz, X - lx); rr = lr * (1 + 0.12 * np.sin(3 * th + k * 1.7) + 0.07 * np.sin(5 * th + k))
        lake_s = np.minimum(lake_s, np.hypot(X - lx, Z - lz) - rr)
    river_s = poly_dist(X, Z, RIVER) - (8.0 + 2.5 * np.sin(Z * 0.021) + 1.5 * np.sin(Z * 0.057 + 1.0))
    trail = np.full(X.shape, 1e9)
    for t in TRAILS: trail = np.minimum(trail, poly_dist(X, Z, t))
    clear = np.zeros(X.shape); clear_h = []
    for (_, cx, cz, cr) in CLEARINGS:
        clear = np.maximum(clear, sstep(cr + 10, cr - 5, np.hypot(X - cx, Z - cz)))
    d4 = ((X - 512) ** 4 + (Z - 512) ** 4) ** 0.25
    return lake_s, river_s, trail, clear, d4

def build():
    g = np.arange(N) * CELL; X, Z = np.meshgrid(g, g)  # arrays indexed [j(z), i(x)]
    n1 = fnoise(512, 2.3, 1)[:N, :N]; n2 = fnoise(512, 1.6, 2)[:N, :N]; n3 = fnoise(512, 1.2, 3)[:N, :N]; n4 = fnoise(512, 2.0, 4)[:N, :N]
    lake_s, river_s, trail, clear, d4 = fields(X, Z)
    s = np.minimum(lake_s, river_s)
    base = 4.5 + 3.2 * n1 + 0.9 * n2
    base = np.maximum(base, 1.2)
    for (_, cx, cz, cr) in CLEARINGS:  # flatten clearings to their centre height
        w = sstep(cr + 14, cr - 6, np.hypot(X - cx, Z - cz)); hc = base[int(round(cz / CELL)), int(round(cx / CELL))]
        base = base * (1 - w) + hc * w
    m = np.clip((d4 - 432) / 80, 0, 1.3)
    base = base + m * m * 78 + m * 9 * np.abs(n2) + sstep(0.0, 0.3, m) * 3
    shore = 0.12 + 0.075 * np.maximum(s, 0)
    h = np.where(s < 0, -np.minimum(2.9, -s * 0.33) - 0.02, shore + (base - shore) * sstep(3, 18, s))
    gy, gx = np.gradient(h, CELL); slope = np.hypot(gx, gy)
    # ---- ground blend weights
    rock = np.clip(sstep(0.55, 0.95, slope) + sstep(0.12, 0.45, m), 0, 1) * (s > 1)
    sand = sstep(7.5, 2.5, s) * (s > -5) + sstep(-9, -5, s) * (s <= -5) * 0
    sand = np.where(s <= -5, 0, sand)
    mud = np.where(s <= -2.5, sstep(-2.5, -6, s), 0) + sstep(0.5, 1.2, n3) * sstep(12, 5, s) * (s > 2) * 0.8
    dirt = sstep(4.2, 1.6, trail) * (s > 2)
    glade = sstep(0.45, 0.85, n4) * (m < 0.05)
    grass = np.clip(np.maximum(clear, glade), 0, 1)
    forest = 1 - grass
    w_rock = rock; rem = 1 - w_rock
    w_sand = np.clip(sand, 0, 1) * rem; rem = rem - w_sand
    w_mud = np.clip(mud, 0, 1) * rem; rem = rem - w_mud
    w_dirt = dirt * rem; rem = rem - w_dirt
    w_forest = forest * rem
    splat = np.stack([w_forest, w_dirt, w_sand, w_rock, w_mud], -1)
    biome = np.zeros((N, N), np.uint8)  # 0 forest 1 grass 2 trail 3 shore 4 rock 5 water
    biome[grass > 0.5] = 1; biome[dirt > 0.5] = 2; biome[(w_sand + w_mud) > 0.5] = 3; biome[(rock > 0.5) | (d4 > 448)] = 4; biome[h < -0.15] = 5
    return dict(X=X, Z=Z, h=h, s=s, lake_s=lake_s, river_s=river_s, trail=trail, clear=clear, d4=d4, m=m, slope=slope, splat=splat, biome=biome, grass=grass, n3=n3)

class Sampler:
    def __init__(self, W): self.W = W
    def at(self, name, x, z):
        a = self.W[name]; fx = np.clip(np.asarray(x) / CELL, 0, N - 1.001); fz = np.clip(np.asarray(z) / CELL, 0, N - 1.001)
        i = fx.astype(int); j = fz.astype(int); u = fx - i; v = fz - j
        return a[j, i] * (1 - u) * (1 - v) + a[j, i + 1] * u * (1 - v) + a[j + 1, i] * (1 - u) * v + a[j + 1, i + 1] * u * v
    def biome(self, x, z):
        return self.W['biome'][np.clip(np.round(np.asarray(z) / CELL).astype(int), 0, N - 1), np.clip(np.round(np.asarray(x) / CELL).astype(int), 0, N - 1)]

def spaced(cands, mind, count, existing=()):
    out = []; ex = [tuple(e) for e in existing]
    for c in cands:
        if all((c[0] - o[0]) ** 2 + (c[1] - o[1]) ** 2 >= mind * mind for o in out) and all((c[0] - e[0]) ** 2 + (c[1] - e[1]) ** 2 >= 18 * 18 for e in ex):
            out.append((float(c[0]), float(c[1])))
            if len(out) >= count: break
    return out

def main():
    os.makedirs(OUT, exist_ok=True); W = build(); S = Sampler(W); r = np.random.default_rng(2024)
    for (x, z) in THICKETS: assert S.at('s', x, z) > 20 and S.at('m', x, z) < 0.01 and S.at('clear', x, z) < 0.1, ('thicket', x, z)
    for (_, _, x, z) in LANDMARKS: assert S.at('s', x, z) > 14 and S.at('m', x, z) < 0.01, ('landmark', x, z)
    special = [(x, z) for (x, z) in THICKETS] + [(x, z) for (_, _, x, z) in LANDMARKS]
    # ---- fixed rare plants
    c = r.uniform(70, 954, (6000, 2)); ok = (S.at('s', c[:, 0], c[:, 1]) > 6) & (S.at('d4', c[:, 0], c[:, 1]) < 425) & (S.at('slope', c[:, 0], c[:, 1]) < 0.45)
    land = spaced(c[ok], 30, 67, special)
    c2 = r.uniform(70, 954, (20000, 2)); s2 = S.at('lake_s', c2[:, 0], c2[:, 1]); ok2 = (s2 > 1.0) & (s2 < 3.5)
    lot = spaced(c2[ok2], 120, 3)
    assert len(land) == 67 and len(lot) == 3, (len(land), len(lot))
    types = []
    for n, k in PLANT_COUNTS:
        if n != 'lotus': types += [n] * k
    r.shuffle(types)
    plants = [{'t': t, 'x': round(p[0], 1), 'z': round(p[1], 1)} for t, p in zip(types, land)] + [{'t': 'lotus', 'x': round(p[0], 1), 'z': round(p[1], 1)} for p in lot]
    # ---- dens, crocodile spots, herd homes, fawn
    c = r.uniform(80, 944, (5000, 2)); ok = (S.at('s', c[:, 0], c[:, 1]) > 16) & (S.at('d4', c[:, 0], c[:, 1]) < 415) & (S.at('clear', c[:, 0], c[:, 1]) < 0.2)
    dens = spaced(c[ok], 48, 60, [(x, z) for (x, z) in THICKETS])
    c = r.uniform(60, 964, (60000, 2)); sc = S.at('s', c[:, 0], c[:, 1]); ok = (sc > -1.5) & (sc < 1.0) & (S.at('d4', c[:, 0], c[:, 1]) < 420)
    crocs = spaced(c[ok], 70, 14)
    c = r.uniform(90, 934, (4000, 2)); ok = (S.at('s', c[:, 0], c[:, 1]) > 12) & (S.at('d4', c[:, 0], c[:, 1]) < 410)
    herds = [(float(x), float(z)) for (_, x, z, _) in CLEARINGS] + spaced(c[ok], 90, 12, [(x, z) for (_, x, z, _) in CLEARINGS])
    assert len(dens) >= 52 and len(crocs) >= 12 and len(herds) >= 18, (len(dens), len(crocs), len(herds))
    # ---- vegetation instances
    inst = []  # (type, x, z, scale, rot)
    def add(t, x, z, sc): inst.append((VI[t], float(x), float(z), float(sc), int(r.integers(0, 256))))
    def grid(step, lo=24, hi=1000):
        g = np.arange(lo, hi, step); gx, gz = np.meshgrid(g, g); n = gx.size
        return gx.ravel() + r.uniform(0, step, n), gz.ravel() + r.uniform(0, step, n), r.uniform(0, 1, n)
    sp = np.array(special); pl = np.array([(p['x'], p['z']) for p in plants])
    def clear_of(x, z, pts, d): return np.min(np.hypot(pts[:, 0][None, :] - x[:, None], pts[:, 1][None, :] - z[:, None]), axis=1) > d
    block_types = {}
    def tree_type(x, z, u):
        b = (int(x // 128), int(z // 128))
        if b not in block_types:
            rr = np.random.default_rng(b[0] * 31 + b[1] * 7 + 5); block_types[b] = list(rr.choice(['tree_a', 'tree_b', 'tree_c', 'tree_d', 'tree_big'], 2, replace=False, p=[0.24, 0.22, 0.22, 0.14, 0.18]))
        return block_types[b][0 if u < 0.6 else 1]
    x, z, u = grid(10.5)
    sv = S.at('s', x, z); mv = S.at('m', x, z); gv = S.at('grass', x, z); tv = S.at('trail', x, z)
    ok = (sv > 5) & (mv < 0.62) & (tv > 3.5) & clear_of(x, z, sp, 13) & clear_of(x, z, pl, 3.0) & (u < np.where(gv > 0.4, 0.02, 0.84) * np.where(mv > 0.2, 0.55, 1))
    u2 = r.uniform(0, 1, x.size)
    for k in np.where(ok)[0]:
        if 5 < sv[k] < 24 and u2[k] < 0.55: add('palm_a' if (int(x[k] // 128) + int(z[k] // 128)) % 2 == 0 else 'palm_b', x[k], z[k], r.uniform(2.8, 3.8))
        else:
            t = tree_type(x[k], z[k], u2[k]); add(t, x[k], z[k], r.uniform(5.2, 6.6) if t == 'tree_big' else r.uniform(4.0, 5.6))
    for (kind, _, lx, lz) in LANDMARKS:
        if kind == 'giant_tree': add('tree_giant', lx, lz, 9.0)
        if kind == 'berry_glade':
            for a in range(10): ang = a * 0.628 + r.uniform(0, 0.3); d = r.uniform(4, 10); add('bush_berry', lx + np.cos(ang) * d, lz + np.sin(ang) * d, r.uniform(1.3, 1.9))
        if kind == 'banana_grove':
            for a in range(14): ang = a * 0.449; d = r.uniform(3, 12); add('banana', lx + np.cos(ang) * d, lz + np.sin(ang) * d, r.uniform(5.0, 6.8))
    for (tx, tz) in THICKETS:  # a dense ring of bushes marks every safe thicket
        for a in range(16): ang = a * 0.3927 + r.uniform(-0.1, 0.1); add('bush_a', tx + np.cos(ang) * (THICKET_R - 0.5), tz + np.sin(ang) * (THICKET_R - 0.5), r.uniform(2.0, 2.6))
        for a in range(9): ang = r.uniform(0, 6.28); d = r.uniform(2, 8); add('fern_a', tx + np.cos(ang) * d, tz + np.sin(ang) * d, r.uniform(1.6, 2.2))
    def chunk_pick(x, z, a, b): return a if (int(x // 64) * 13 + int(z // 64) * 7) % 2 == 0 else b
    x, z, u = grid(12.5); sv = S.at('s', x, z); mv = S.at('m', x, z); gv = S.at('grass', x, z); tv = S.at('trail', x, z)
    for k in np.where((sv > 4) & (mv < 0.3) & (tv > 3) & (gv < 0.5) & (u < 0.5) & clear_of(x, z, sp, 12) & clear_of(x, z, pl, 2.5))[0]:
        add(chunk_pick(x[k], z[k], 'bush_a', 'bush_b'), x[k], z[k], r.uniform(1.2, 2.0))
    x, z, u = grid(9.0); sv = S.at('s', x, z); mv = S.at('m', x, z); gv = S.at('grass', x, z); tv = S.at('trail', x, z)
    for k in np.where((sv > 3) & (mv < 0.2) & (tv > 2.5) & (gv < 0.6) & (u < 0.5) & clear_of(x, z, pl, 2.0))[0]:
        add(chunk_pick(x[k], z[k], 'fern_a', 'fern_b'), x[k], z[k], r.uniform(1.3, 2.0))
    x, z, u = grid(12.0); sv = S.at('s', x, z); mv = S.at('m', x, z); tv = S.at('trail', x, z)
    for k in np.where((sv > 7) & (sv < 30) & (mv < 0.05) & (tv > 3) & (u < 0.28))[0]: add('banana', x[k], z[k], r.uniform(4.6, 6.4))
    x, z, u = grid(5.0); sv = S.at('s', x, z); gv = S.at('grass', x, z); tv = S.at('trail', x, z)
    for k in np.where((sv > 5) & (gv > 0.55) & (tv > 3) & (u < 0.5))[0]: add('tall_grass', x[k], z[k], r.uniform(0.9, 1.5))
    x, z, u = grid(14.0); sv = S.at('s', x, z); mv = S.at('m', x, z); sl = S.at('slope', x, z); tv = S.at('trail', x, z)
    for k in np.where((sv > 3) & (tv > 4) & (u < np.where((mv > 0.1) | (sl > 0.5), 0.5, 0.05)) & (mv < 0.8))[0]:
        add(chunk_pick(x[k], z[k], 'rock_a', 'rock_b'), x[k], z[k], r.uniform(1.5, 4.5) if mv[k] > 0.1 else r.uniform(0.8, 1.8))
    x, z, u = grid(6.0); lv = S.at('lake_s', x, z)
    for k in np.where((lv < -3) & (lv > -14) & (u < 0.4))[0]: add('lily', x[k], z[k], r.uniform(1.0, 1.7))
    inst.sort(key=lambda t: (int(t[2] // 64) * 16 + int(t[1] // 64), t[0]))
    with open(f'{OUT}/veg.bin', 'wb') as f:
        f.write(struct.pack('<I', len(inst)))
        for (t, x, z, sc, rot) in inst: f.write(struct.pack('<BBBBHH', t, min(255, int(round(sc * 16))), rot, 0, int(round(x * 60)), int(round(z * 60))))
    W['h'].astype('<f4').tofile(f'{OUT}/heights.bin'); (np.clip(W['splat'], 0, 1) * 255).astype(np.uint8).tofile(f'{OUT}/splat.bin'); W['biome'].tofile(f'{OUT}/biome.bin')
    counts = {VEG[i]: int(sum(1 for t in inst if t[0] == i)) for i in range(len(VEG))}
    json.dump({'size': SIZE, 'cell': CELL, 'n': N, 'river': RIVER, 'lakes': [{'name': a, 'x': b, 'z': c, 'r': d} for a, b, c, d in LAKES],
               'clearings': [{'name': a, 'x': b, 'z': c, 'r': d} for a, b, c, d in CLEARINGS], 'trails': [[(round(x, 1), round(z, 1)) for x, z in t] for t in TRAILS],
               'thickets': [{'x': x, 'z': z, 'r': THICKET_R} for x, z in THICKETS], 'landmarks': [{'kind': k, 'name': n, 'x': x, 'z': z} for k, n, x, z in LANDMARKS],
               'plants': plants, 'dens': [(round(x, 1), round(z, 1)) for x, z in dens], 'crocs': [(round(x, 1), round(z, 1)) for x, z in crocs],
               'herds': [(round(x, 1), round(z, 1)) for x, z in herds], 'fawn': [705.0, 395.0], 'veg_types': VEG, 'veg_counts': counts}, open(f'{OUT}/world.json', 'w'))
    # ---- top-down map picture (also the minimap texture)
    M = 512; gm = (np.arange(M) + 0.5) * SIZE / M; MX, MZ = np.meshgrid(gm, gm)
    hh = S.at('h', MX, MZ)
    w = [np.clip(Sampler({'a': W['splat'][..., k]}).at('a', MX, MZ), 0, 1) for k in range(5)]
    col = np.zeros((M, M, 3)); pal = [(0.13, 0.27, 0.11), (0.52, 0.40, 0.26), (0.76, 0.68, 0.48), (0.47, 0.46, 0.43), (0.30, 0.24, 0.16)]; rem = np.ones((M, M))
    for k in range(5): col += w[k][..., None] * np.array(pal[k]); rem -= w[k]
    col += np.clip(rem, 0, 1)[..., None] * np.array((0.36, 0.52, 0.20))
    gy, gx = np.gradient(hh); shade = np.clip(1 + (gx - gy) * 0.35, 0.6, 1.35); col *= shade[..., None]
    wat = hh < -0.05; col[wat] = np.array((0.16, 0.42, 0.66)) * np.clip(1 + hh[wat] * 0.12, 0.6, 1)[..., None]
    tm = np.zeros((M, M))
    for (t, x, z, sc, rot) in inst:
        if t <= VI['palm_b']: tm[min(M - 1, int(z / SIZE * M)), min(M - 1, int(x / SIZE * M))] = 1
    col *= (1 - 0.22 * tm)[..., None]
    Image.fromarray((np.clip(col, 0, 1) * 255).astype(np.uint8)).save(f'{OUT}/map.png')
    print('instances', len(inst), counts); print('plants', len(plants), 'dens', len(dens), 'crocs', len(crocs), 'herds', len(herds))
    print('land min/max', float(W['h'].min()), float(W['h'].max()), 'water cells', int((W['biome'] == 5).sum()))
    if '--preview' in sys.argv:
        from PIL import ImageDraw
        im = Image.open(f'{OUT}/map.png').resize((1024, 1024)); d = ImageDraw.Draw(im)
        for p in plants: d.ellipse([p['x'] - 3, p['z'] - 3, p['x'] + 3, p['z'] + 3], fill=(255, 80, 255))
        for (x, z) in THICKETS: d.ellipse([x - 11, z - 11, x + 11, z + 11], outline=(0, 255, 0), width=2)
        for (k, n, x, z) in LANDMARKS: d.rectangle([x - 5, z - 5, x + 5, z + 5], outline=(255, 255, 0), width=2)
        for (x, z) in dens: d.ellipse([x - 2, z - 2, x + 2, z + 2], fill=(255, 0, 0))
        for (x, z) in crocs: d.rectangle([x - 3, z - 3, x + 3, z + 3], fill=(0, 255, 255))
        for (n, x, z, rr) in CLEARINGS: d.text((x - 30, z), n, fill=(255, 255, 255))
        im.save('preview_tmp/map_preview.png')
if __name__ == '__main__': main()

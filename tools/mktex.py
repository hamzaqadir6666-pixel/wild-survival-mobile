"""Generate tileable PBR-ish ground textures procedurally (grass, dirt, sand, rock, snow,
wood, planks, leather) at 1024^2 with seamless tiling."""
import numpy as np, sys, os
from PIL import Image, ImageFilter

N = 1024
rng = np.random.default_rng(4242)


def fbm(n, octaves=5, persistence=0.55, tile=True):
    out = np.zeros((n, n), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for o in range(octaves):
        size = max(2, int(2 ** (o + 1)))
        base = rng.random((size, size)).astype(np.float32)
        if tile:
            base = np.tile(base, (3, 3))
        img = Image.fromarray((base * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)
        f = np.asarray(img, dtype=np.float32) / 255.0
        out += f * amp
        total += amp
        amp *= persistence
    return out / total


def wrap_noise(n, scale, seed):
    r = np.random.default_rng(seed)
    s = max(2, int(scale))
    base = r.random((s, s)).astype(np.float32)
    tiled = np.tile(base, (3, 3))
    img = Image.fromarray((tiled * 255).astype(np.uint8)).resize((n * 3, n * 3), Image.BICUBIC)
    a = np.asarray(img, dtype=np.float32) / 255.0
    return a[n:n * 2, n:n * 2]


def normal_from_height(h, strength=2.0):
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nz = np.ones_like(h)
    l = np.sqrt(dx * dx + dy * dy + nz * nz)
    return np.stack([-dx / l, -dy / l, nz / l], -1)


def save_rgb(path, arr):
    a = np.clip(arr, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8)).save(path, quality=92)


def save_gray(path, arr):
    a = np.clip(arr, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8), mode='L').save(path, quality=92)


def blend(c1, c2, t):
    t = t[..., None]
    return c1 * (1 - t) + c2 * t


def make_grass(out):
    h = fbm(N, 6, 0.55) * 0.6 + wrap_noise(N, 128, 1) * 0.4
    fine = wrap_noise(N, 512, 2)
    blades = (fine > 0.62).astype(np.float32) * (fine - 0.62) * 3.0
    dark = np.array([0.11, 0.16, 0.06])
    mid = np.array([0.24, 0.31, 0.11])
    light = np.array([0.35, 0.42, 0.16])
    col = blend(dark, mid, np.clip(h * 1.6, 0, 1))
    col = blend(col, light, np.clip(blades * 1.4, 0, 1))
    col *= (0.85 + 0.3 * wrap_noise(N, 256, 3))[..., None]
    save_rgb(out + '/terrain_grass.png', col)
    save_gray(out + '/terrain_grass_r.png', np.clip(0.85 + 0.15 * h, 0, 1))
    n = normal_from_height(h * 0.5 + blades * 0.3, 3.0)
    save_rgb(out + '/terrain_grass_n.png', n * 0.5 + 0.5)


def make_dirt(out):
    h = fbm(N, 5, 0.5) * 0.7 + wrap_noise(N, 256, 11) * 0.3
    pebbles = wrap_noise(N, 256, 12)
    mask = (pebbles > 0.70).astype(np.float32)
    dark = np.array([0.20, 0.14, 0.09])
    mid = np.array([0.34, 0.25, 0.16])
    col = blend(dark, mid, np.clip(h * 1.5, 0, 1))
    col = col * (1 - mask[..., None] * 0.35) + mask[..., None] * np.array([0.36, 0.33, 0.28]) * 0.65
    col *= (0.9 + 0.2 * wrap_noise(N, 128, 13))[..., None]
    save_rgb(out + '/terrain_dirt.png', col)
    n = normal_from_height(h + mask * 0.8, 4.0)
    save_rgb(out + '/terrain_dirt_n.png', n * 0.5 + 0.5)


def make_sand(out):
    h = fbm(N, 4, 0.45) * 0.5 + wrap_noise(N, 340, 21) * 0.5
    grain = wrap_noise(N, 1024, 22)
    base = np.array([0.68, 0.56, 0.38])
    col = base[None, None, :] * (0.82 + 0.28 * h[..., None])
    col *= (0.92 + 0.16 * grain[..., None])
    # wind ripples
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) / N
    ripple = 0.5 + 0.5 * np.sin(2 * np.pi * (xx * 9 + 0.35 * np.sin(yy * 7 * 2 * np.pi)))
    col *= (0.94 + 0.10 * ripple[..., None])
    save_rgb(out + '/terrain_sand.png', col)
    n = normal_from_height(h * 0.4 + ripple * 0.5, 2.0)
    save_rgb(out + '/terrain_sand_n.png', n * 0.5 + 0.5)


def make_rock(out):
    h = fbm(N, 6, 0.6) * 0.6 + wrap_noise(N, 256, 31) * 0.4
    cracks = np.abs(wrap_noise(N, 64, 32) - 0.5)
    crack_mask = np.clip(1.0 - cracks * 9.0, 0, 1)
    dark = np.array([0.24, 0.23, 0.21])
    mid = np.array([0.44, 0.42, 0.38])
    col = blend(dark, mid, np.clip(h * 1.7, 0, 1))
    col *= (1 - crack_mask[..., None] * 0.45)
    lichen = wrap_noise(N, 128, 33)
    col = blend(col, np.array([0.38, 0.40, 0.28]), np.clip((lichen - 0.62) * 2.4, 0, 1))
    save_rgb(out + '/terrain_rock.png', col)
    n = normal_from_height(h - crack_mask * 0.6, 5.0)
    save_rgb(out + '/terrain_rock_n.png', n * 0.5 + 0.5)


def make_snow(out):
    h = fbm(N, 5, 0.4)
    col = np.array([0.92, 0.94, 0.98])[None, None, :] * (0.9 + 0.12 * h[..., None])
    save_rgb(out + '/terrain_snow.png', col)
    save_rgb(out + '/terrain_snow_n.png', normal_from_height(h, 1.2) * 0.5 + 0.5)


def make_wood(out, planks=True):
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) / N
    warp = wrap_noise(N, 64, 41) * 0.35
    if planks:
        row = (yy * 8).astype(int)
        # grain runs along x within each plank
        g = 0.5 + 0.5 * np.sin(2 * np.pi * ((yy * 8 + warp * 0.12) * 3.0 + wrap_noise(N, 256, 42) * 0.6))
        gap = ((yy * 8) % 1.0)
        gapmask = (gap < 0.05) | (gap > 0.95)
        base = np.array([0.36, 0.24, 0.14])
        col = base[None, None, :] * (0.75 + 0.45 * g[..., None])
        col *= (1 - gapmask[..., None] * 0.55)
        h = g * 0.6 + (1 - gapmask.astype(np.float32)) * 0.3
    else:
        g = 0.5 + 0.5 * np.sin(2 * np.pi * (yy * 22 + warp * 3.0 + wrap_noise(N, 128, 43) * 0.8))
        base = np.array([0.34, 0.23, 0.15])
        col = base[None, None, :] * (0.72 + 0.5 * g[..., None])
        h = g
    col *= (0.9 + 0.2 * wrap_noise(N, 128, 44))[..., None]
    name = 'wood_planks' if planks else 'wood'
    save_rgb(out + '/%s.png' % name, col)
    save_rgb(out + '/%s_n.png' % name, normal_from_height(h, 3.0) * 0.5 + 0.5)


def make_leather(out):
    n1 = wrap_noise(N, 256, 51)
    n2 = wrap_noise(N, 512, 52)
    base = np.array([0.30, 0.18, 0.10])
    col = base[None, None, :] * (0.8 + 0.4 * n1[..., None]) * (0.9 + 0.2 * n2[..., None])
    save_rgb(out + '/leather.png', col)
    save_rgb(out + '/leather_n.png', normal_from_height(n1 * 0.6 + n2 * 0.4, 2.0) * 0.5 + 0.5)


def make_bark(out):
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32) / N
    ridges = 0.5 + 0.5 * np.sin(2 * np.pi * (xx * 18 + wrap_noise(N, 128, 61) * 1.5))
    h = ridges * 0.7 + wrap_noise(N, 256, 62) * 0.3
    base = np.array([0.23, 0.17, 0.12])
    col = base[None, None, :] * (0.55 + 0.8 * h[..., None])
    save_rgb(out + '/bark.png', col)
    save_rgb(out + '/bark_n.png', normal_from_height(h, 4.0) * 0.5 + 0.5)


def make_leaf(out):
    r = np.random.default_rng(71)
    # alpha-cutout leaf cluster sprite
    img = np.zeros((N, N, 4), dtype=np.uint8)
    for i in range(140):
        cx, cy = r.integers(0, N, 2)
        rad = r.integers(18, 54)
        a0 = r.uniform(0, np.pi)
        yy, xx = np.mgrid[-rad:rad, -rad:rad]
        rot = xx * np.cos(a0) + yy * np.sin(a0)
        orth = -xx * np.sin(a0) + yy * np.cos(a0)
        mask = (rot / rad) ** 2 + (orth / (rad * 0.42)) ** 2 <= 1.0
        ys = (np.arange(-rad, rad) + cy) % N
        xs = (np.arange(-rad, rad) + cx) % N
        g = r.uniform(0.35, 0.85)
        sub = img[np.ix_(ys, xs)]
        col = np.array([int(70 * g + 30), int(95 * g + 40), int(38 * g + 16), 235], dtype=np.uint8)
        sub[mask] = col
        img[np.ix_(ys, xs)] = sub
    Image.fromarray(img).save(out + '/leaf_cluster.png')


def make_grass_card(out):
    """A vertical grass billboard texture (alpha cutout tuft)."""
    r = np.random.default_rng(81)
    img = np.zeros((512, 512, 4), dtype=np.uint8)
    img[..., 3] = 0
    for i in range(90):
        x0 = r.uniform(20, 492)
        h0 = r.uniform(180, 500)
        w0 = r.uniform(2.5, 7.0)
        lean = r.uniform(-70, 70)
        g = r.uniform(0.45, 1.0)
        col = np.array([int(58 * g + 22), int(86 * g + 34), int(30 * g + 12), 255], dtype=np.uint8)
        for t in np.linspace(0, 1, 120):
            y = int(512 - t * h0) % 512
            x = int(x0 + lean * t * t)
            w = max(1, int(w0 * (1 - t * 0.85)))
            if 0 <= y < 512:
                img[max(0, y - 5):y + 1, max(0, x - w):x + w] = col
    Image.fromarray(img).save(out + '/grass_card.png')


def make_water_normal(out):
    h = (wrap_noise(N, 48, 91) * 0.6 + wrap_noise(N, 128, 92) * 0.4)
    n = normal_from_height(h, 2.5)
    save_rgb(out + '/water_normal.png', n * 0.5 + 0.5)


def make_cloud(out):
    n = 256
    r = np.random.default_rng(101)
    acc = np.zeros((n, n), dtype=np.float32)
    for i in range(26):
        x, y = r.uniform(0, n, 2)
        rad = r.uniform(14, 54)
        yy, xx = np.mgrid[0:n, 0:n]
        d = np.sqrt((xx - x) ** 2 + (yy - y) ** 2)
        acc += np.clip(1 - d / rad, 0, 1) ** 1.6
    acc = np.clip(acc / acc.max(), 0, 1) ** 1.2
    a = (acc * 255).astype(np.uint8)
    img = np.stack([a, a, a, a], -1)
    Image.fromarray(img).save(out + '/cloud_puff.png')


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    make_grass(out)
    make_dirt(out)
    make_sand(out)
    make_rock(out)
    make_snow(out)
    make_wood(out, True)
    make_wood(out, False)
    make_leather(out)
    make_bark(out)
    make_leaf(out)
    make_grass_card(out)
    make_water_normal(out)
    make_cloud(out)
    print('textures done ->', out)

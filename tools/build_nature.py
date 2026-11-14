#!/usr/bin/env python3
"""Bakes the Quaternius 'Ultimate Nature Pack' models (CC0) for mobile:
node transforms applied, every model merged into ONE surface with vertex colours,
triangle count reduced to the mobile budget, and a second very light LOD for far trees.
Vertex colour alpha = 1 for foliage (sways in the wind, uses the leaf detail pattern),
0 for bark / rock. UVs are a box projection for the tiling detail texture.
Run:  python3 tools/build_nature.py
"""
import os, sys, json
import numpy as np, pyfqmr
sys.path.insert(0, os.path.dirname(__file__))
from gltfutil import static_tris, write_glb, render
SRC = 'assets_src/quaternius_nature'; OUT = 'assets/models/nature'
# name: (source, lod0 tris, lod1 tris or 0)
MODELS = {
    'tree_giant': ('Willow_2', 600, 150), 'tree_big': ('Willow_4', 560, 140), 'tree_a': ('CommonTree_2', 520, 130),
    'tree_b': ('CommonTree_5', 480, 120), 'tree_c': ('Willow_3', 460, 120), 'tree_d': ('CommonTree_1', 520, 130),
    'palm_a': ('PalmTree_1', 420, 110), 'palm_b': ('PalmTree_4', 380, 100),
    'banana': ('Plant_1', 180, 0), 'fern_a': ('Plant_3', 140, 0), 'fern_b': ('Plant_4', 160, 0),
    'bush_a': ('Bush_1', 150, 0), 'bush_b': ('Bush_2', 130, 0), 'bush_berry': ('BushBerries_1', 260, 0),
    'grass_tuft': ('Grass_3', 64, 0), 'tall_grass': ('Wheat', 110, 0), 'lily': ('Lilypad', 130, 0),
    'rock_a': ('Rock_Moss_4', 128, 0), 'rock_b': ('Rock_Moss_6', 116, 0), 'rock_c': ('Rock_1', 70, 0),
    'p_flower': ('Flowers', 200, 0), 'p_spike': ('Plant_5', 240, 0), 'p_corn': ('Corn_2', 240, 0), 'p_twig': ('Plant_2', 160, 0),
    'p_log': ('WoodLog_Moss', 260, 0), 'p_stump': ('TreeStump', 200, 0), 'p_berry': ('BushBerries_2', 260, 0),
}
FOLIAGE = ('Green', 'DarkGreen', 'Yellow', 'Pink', 'Cyan', 'Red')
# richer jungle colours (sRGB) replacing the pack's dull defaults
RECOLOR = {'Green': (0.25, 0.44, 0.17), 'DarkGreen': (0.15, 0.33, 0.14), 'Brown': (0.36, 0.27, 0.20), 'Gray': (0.47, 0.47, 0.45)}
PER_MODEL = {'tall_grass': {'Yellow': (0.36, 0.47, 0.20)}, 'grass_tuft': {'Green': (0.27, 0.43, 0.17)},
             'tree_giant': {'DarkGreen': (0.13, 0.30, 0.13)}, 'banana': {'Green': (0.30, 0.52, 0.18)}}

def simplify(P, I, target):
    if len(I) <= target: return P, I
    s = pyfqmr.Simplify(); s.setMesh(P, I)
    s.simplify_mesh(target_count=int(target), aggressiveness=5, preserve_border=False, verbose=False)
    v, f, _ = s.getMesh(); return np.asarray(v, float), np.asarray(f, np.int64)

def bake(name, src, target):
    P, I, C, M = static_tris(f'{SRC}/{src}.gltf'); M = np.array(M)
    P = P - np.array([(P[:, 0].min() + P[:, 0].max()) / 2 if name.startswith(('rock', 'bush', 'p_', 'lily')) else 0, P[:, 1].min(), (P[:, 2].min() + P[:, 2].max()) / 2 if name.startswith(('rock', 'bush', 'p_', 'lily')) else 0])
    total = len(I); oP = []; oN = []; oC = []; oUV = []
    for mat in sorted(set(M)):
        sel = I[M == mat]
        # weld by position inside this colour group
        used, inv = np.unique(sel.reshape(-1), return_inverse=True)
        pts = P[used]; key = np.round(pts * 2000).astype(np.int64)
        _, first, inv2 = np.unique(key, axis=0, return_index=True, return_inverse=True)
        wp = pts[first]; wi = inv2.reshape(-1)[inv].reshape(-1, 3)
        wi = wi[(wi[:, 0] != wi[:, 1]) & (wi[:, 1] != wi[:, 2]) & (wi[:, 0] != wi[:, 2])]
        tgt = max(8, int(round(target * len(sel) / total)))
        sp, si = simplify(wp, wi, tgt)
        col = PER_MODEL.get(name, {}).get(mat, RECOLOR.get(mat))
        col = np.array(col) ** 2.2 if col is not None else C[M == mat][0]
        a = 1.0 if mat in FOLIAGE else 0.0
        tri = sp[si]; n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); ln = np.linalg.norm(n, axis=1, keepdims=True)
        ok = ln[:, 0] > 1e-10; tri = tri[ok]; n = n[ok] / ln[ok]
        ax = np.argmax(np.abs(n), axis=1)
        for k in range(3):
            v = tri[:, k]
            uv = np.where((ax == 0)[:, None], v[:, [2, 1]], np.where((ax == 1)[:, None], v[:, [0, 2]], v[:, [0, 1]])) * 0.6
            oP.append(v); oN.append(n); oUV.append(uv); oC.append(np.tile(np.append(col, a), (len(v), 1)))
    def inter(L):  # per-corner lists -> triangle-ordered vertex array
        return np.concatenate(L)
    # arrays are grouped [corner0 of group, corner1, corner2] per material; rebuild indices accordingly
    Pn = []; Nn = []; Cn = []; Un = []; idx = []; base = 0
    for g in range(0, len(oP), 3):
        m = len(oP[g])
        for k in range(3):
            Pn.append(oP[g + k]); Nn.append(oN[g + k]); Cn.append(oC[g + k]); Un.append(oUV[g + k])
        idx.append(np.stack([np.arange(m) + base, np.arange(m) + base + m, np.arange(m) + base + 2 * m], 1)); base += 3 * m
    P2 = np.concatenate(Pn); I2 = np.concatenate(idx)
    return P2, np.concatenate(Nn), np.concatenate(Cn), np.concatenate(Un), I2

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True); info = {}; sheet = []
    for name, (src, t0, t1) in MODELS.items():
        P, N, C, UV, I = bake(name, src, t0); write_glb(f'{OUT}/{name}.glb', P, N, C, UV, I, name)
        info[name] = {'source': src, 'tris': int(len(I)), 'height': round(float(P[:, 1].max()), 2), 'radius': round(float(np.abs(P[:, [0, 2]]).max()), 2)}
        sheet.append((name, P, I, C))
        if t1:
            P, N, C, UV, I = bake(name, src, t1); write_glb(f'{OUT}/{name}_lod1.glb', P, N, C, UV, I, name + '_lod1')
            info[name]['lod1_tris'] = int(len(I)); sheet.append((name + '_lod1', P, I, C))
        print(name, info[name])
    json.dump(info, open(f'{OUT}/nature.json', 'w'), indent=1)
    if '--sheet' in sys.argv:
        from PIL import Image, ImageDraw
        S = 150; cols = 9; rows = (len(sheet) + cols - 1) // cols; im = Image.new('RGB', (cols * S, rows * S))
        for k, (nm, P, I, C) in enumerate(sheet):
            tile = Image.fromarray(render(P, I, C[I[:, 0], :3], S)); ImageDraw.Draw(tile).text((3, 3), f'{nm} {len(I)}', fill=(255, 255, 255))
            im.paste(tile, ((k % cols) * S, (k // cols) * S))
        im.save('.cache/nature_baked.png')

#!/usr/bin/env python3
"""Bakes the textured, rigged animals that are NOT Quaternius models:

  assets_src/zeroad_fauna/*.glb   0 A.D. fauna (Wildfire Games, CC BY-SA 3.0): lion, lioness,
                                  crocodile, boar, gazelle, goat.  Clips: Idle, Walk.
  assets_src/poly_google/*.glb    Poly by Google (CC-BY 3.0) hyena, elephant, rhinoceros, rigged on
                                  Quaternius skeletons by the renethack project.  Full clip set.

Per game species it writes assets/models/animals/<species>.glb (one surface, lower-case clip
names, UV = original texture, UV2 = side projection for an optional coat pattern) and the colour
texture as tex_<source>.png, and it merges its numbers into animals.json.
Run after build_animals.py:   python3 tools/build_animals2.py [--sheet]
"""
import json, struct, os, sys, io
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import gltfutil as G
OUT = 'assets/models/animals'
CLIPS = {'Idle': 'idle', 'Walk': 'walk', 'Gallop': 'run', 'Attack': 'attack', 'Death': 'death', 'Hit': 'hit'}
# species -> (source file, texture name)
SPECIES = {
    'lion': ('zeroad_fauna/lion.glb', 'lion'),
    'tiger': ('zeroad_fauna/lioness.glb', 'lioness'),
    'cheetah': ('zeroad_fauna/lioness.glb', 'lioness'),
    'crocodile': ('zeroad_fauna/crocodile.glb', 'crocodile'),
    'boar': ('zeroad_fauna/boar.glb', 'boar'),
    'gazelle': ('zeroad_fauna/gazelle.glb', 'gazelle'),
    'goat': ('zeroad_fauna/goat.glb', 'goat'),
    'hyena': ('poly_google/Hyena.glb', 'hyena'),
    'elephant': ('poly_google/Elephant.glb', 'elephant'),
    'rhino': ('poly_google/Rhinoceros.glb', 'rhino'),
}
TEX_MAX = 256

class Out:
    def __init__(self): self.blob = bytearray(); self.views = []; self.accs = []
    def add(self, arr, typ, ctype, target=None, minmax=False):
        arr = np.ascontiguousarray(arr.astype(G.CT[ctype]))
        while len(self.blob) % 4: self.blob.append(0)
        v = {'buffer': 0, 'byteOffset': len(self.blob), 'byteLength': arr.nbytes}
        if target: v['target'] = target
        self.blob += arr.tobytes(); self.views.append(v)
        a = {'bufferView': len(self.views) - 1, 'componentType': ctype, 'count': int(arr.shape[0]), 'type': typ}
        if minmax:
            a['min'] = [float(x) for x in arr.reshape(arr.shape[0], -1).min(0)]
            a['max'] = [float(x) for x in arr.reshape(arr.shape[0], -1).max(0)]
        self.accs.append(a); return len(self.accs) - 1

def qmul(a, b):
    ax, ay, az, aw = a; bx, by, bz, bw = b
    return np.array([aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                     aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz])

def world_at(d, bufs, anim, t):
    """World matrix of every node at time t of one animation (linear sampling)."""
    loc = {}
    for ch in anim['channels']:
        s = anim['samplers'][ch['sampler']]
        ti = G.acc(d, bufs, s['input'])[:, 0]; v = G.acc(d, bufs, s['output'])
        if len(v) == 3 * len(ti): v = v[1::3]
        k = int(np.clip(np.searchsorted(ti, t) - 1, 0, max(0, len(ti) - 2)))
        if len(ti) == 1: val = v[0]
        else:
            f = float(np.clip((t - ti[k]) / max(1e-9, ti[k + 1] - ti[k]), 0, 1))
            if s.get('interpolation') == 'STEP': f = 0.0
            val = v[k] * (1 - f) + v[k + 1] * f
            if ch['target']['path'] == 'rotation':
                b = v[k + 1] if np.dot(v[k], v[k + 1]) >= 0 else -v[k + 1]
                val = v[k] * (1 - f) + b * f; val = val / np.linalg.norm(val)
        loc.setdefault(ch['target']['node'], {})[ch['target']['path']] = val
    W = {}
    def walk(i, parent):
        n = dict(d['nodes'][i]); n.pop('matrix', None) if i in loc else None
        for k, v in loc.get(i, {}).items(): n[k] = [float(x) for x in v]
        m = parent @ G.node_matrix(n); W[i] = m
        for c in d['nodes'][i].get('children', []): walk(c, m)
    for r in d['scenes'][d.get('scene', 0)]['nodes']: walk(r, np.eye(4))
    return W

def stride_speed(d, bufs, clip, height, duty):
    """(ground speed that matches the clip, seconds per step cycle), from the foot that travels farthest."""
    an = next((a for a in d['animations'] if a['name'] == clip), None)
    if an is None: return 0.0, 1.0
    T = max(float(G.acc(d, bufs, s['input'])[:, 0].max()) for s in an['samplers'])
    joints = d['skins'][0]['joints']; K = 96
    Ws = [world_at(d, bufs, an, T * k / K) for k in range(K + 1)]
    best = 0.0; cycles = 1
    for j in joints:
        ys = np.array([w[j][1, 3] for w in Ws]); zs = np.array([w[j][2, 3] for w in Ws])
        if ys.min() < height * 0.3 and float(np.ptp(zs)) > best:
            best = float(np.ptp(zs)); c = zs - zs.mean()
            cycles = max(1, int(np.sum((c[:-1] < 0) & (c[1:] >= 0))))
    cyc = T / cycles
    return best / (duty * cyc), cyc

def build(species, src, texname, sheet):
    d, bufs = G.load('assets_src/' + src)
    prims = [p for m in d['meshes'] for p in m['primitives']]
    assert len(prims) == 1, (species, len(prims))
    p = prims[0]; at = p['attributes']
    P = G.acc(d, bufs, at['POSITION']).astype(np.float32); N = G.acc(d, bufs, at['NORMAL']).astype(np.float32)
    UV = G.acc(d, bufs, at['TEXCOORD_0']).astype(np.float32)
    J = G.acc(d, bufs, at['JOINTS_0']).astype(np.uint16); W = G.acc(d, bufs, at['WEIGHTS_0']).astype(np.float32)
    if W.dtype != np.float32 or W.max() > 1.5: W = W / 255.0
    I = G.acc(d, bufs, p['indices'])[:, 0].astype(np.uint32)
    H = float(P[:, 1].max() - P[:, 1].min()); L = float(np.ptp(P[:, 2]))
    UV2 = np.stack([P[:, 2] / H, 1.0 - (P[:, 1] + np.abs(P[:, 0]) * 0.35) / H], 1).astype(np.float32)
    # colour texture -> small PNG next to the model
    img_i = d['textures'][d['materials'][p.get('material', 0)]['pbrMetallicRoughness']['baseColorTexture']['index']]['source']
    bv = d['bufferViews'][d['images'][img_i]['bufferView']]
    raw = bufs[0][bv.get('byteOffset', 0): bv.get('byteOffset', 0) + bv['byteLength']]
    im = Image.open(io.BytesIO(raw)).convert('RGB')
    if max(im.size) > TEX_MAX: im = im.resize((TEX_MAX, TEX_MAX * im.size[1] // im.size[0]), Image.LANCZOS)
    im.save(f'{OUT}/tex_{texname}.png')
    o = Out()
    prim = {'attributes': {
        'POSITION': o.add(P, 'VEC3', 5126, 34962, True), 'NORMAL': o.add(N, 'VEC3', 5126, 34962),
        'TEXCOORD_0': o.add(UV, 'VEC2', 5126, 34962), 'TEXCOORD_1': o.add(UV2, 'VEC2', 5126, 34962),
        'JOINTS_0': o.add(J, 'VEC4', 5123, 34962), 'WEIGHTS_0': o.add(W, 'VEC4', 5126, 34962)},
        'indices': o.add(I.reshape(-1, 1), 'SCALAR', 5123, 34963), 'material': 0}
    skins = []
    for s in d['skins']:
        s2 = dict(s); s2['inverseBindMatrices'] = o.add(G.acc(d, bufs, s['inverseBindMatrices']), 'MAT4', 5126); skins.append(s2)
    anims = []; seen = set()
    for an in d['animations']:
        nm = CLIPS.get(an['name'])
        if not nm or nm in seen: continue
        seen.add(nm); remap = {}; samplers = []
        for s in an['samplers']:
            s2 = dict(s)
            for k in ('input', 'output'):
                if s[k] not in remap:
                    a = d['accessors'][s[k]]
                    remap[s[k]] = o.add(G.acc(d, bufs, s[k]), a['type'], a['componentType'], None, k == 'input')
                s2[k] = remap[s[k]]
            samplers.append(s2)
        anims.append({'name': nm, 'channels': an['channels'], 'samplers': samplers})
    nodes = []
    for n in d['nodes']:
        n2 = dict(n)
        if 'mesh' in n2: n2['mesh'] = 0
        nodes.append(n2)
    g = {'asset': {'version': '2.0', 'generator': 'wild-survival build_animals2.py (source: %s)' % src},
         'scene': 0, 'scenes': [{'nodes': d['scenes'][d.get('scene', 0)]['nodes']}], 'nodes': nodes, 'skins': skins,
         'meshes': [{'name': species, 'primitives': [prim]}],
         'materials': [{'name': 'coat', 'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 0.9}}],
         'animations': anims, 'accessors': o.accs, 'bufferViews': o.views, 'buffers': [{'byteLength': len(o.blob)}]}
    js = json.dumps(g, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    while len(o.blob) % 4: o.blob.append(0)
    with open(f'{OUT}/{species}.glb', 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(o.blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(o.blob), 0x004E4942)); f.write(o.blob)
    walk, cyc = stride_speed(d, bufs, 'Walk', H, 0.62)
    walk = float(np.clip(walk, 0.12 * L, 0.9 * L))
    run = stride_speed(d, bufs, 'Gallop', H, 0.36)[0] if 'run' in seen else walk * 2.6
    if sheet is not None:
        tex = np.asarray(im, np.float32) / 255.0
        tri = I.reshape(-1, 3); uvc = UV[tri].mean(1) % 1.0
        col = tex[np.clip((uvc[:, 1] * tex.shape[0]).astype(int), 0, tex.shape[0] - 1), np.clip((uvc[:, 0] * tex.shape[1]).astype(int), 0, tex.shape[1] - 1)] ** 2.2
        sheet.append((species, G.render(P.astype(float), tri, col, 200, yaw=np.pi / 2, pitch=0.0), G.render(P.astype(float), tri, col, 200, yaw=0.9, pitch=0.35)))
    return {'base': src, 'tex': texname, 'flip': src.startswith('zeroad'), 'tris': int(len(I) // 3), 'height': round(H, 3), 'length': round(L, 3),
            'walk_ref': round(walk, 3), 'walk_cycle': round(cyc, 3), 'run_ref': round(run, 3), 'clips': sorted(seen)}

if __name__ == '__main__':
    sheet = [] if '--sheet' in sys.argv else None
    info = json.load(open(f'{OUT}/animals.json'))
    for sp, (src, tex) in SPECIES.items():
        info[sp] = build(sp, src, tex, sheet); print(sp, info[sp])
    json.dump(info, open(f'{OUT}/animals.json', 'w'), indent=1)
    if sheet:
        os.makedirs('preview_tmp', exist_ok=True)
        W = Image.new('RGB', (400 * 2, 220 * ((len(sheet) + 1) // 2)), (40, 40, 40))
        for k, (name, a, b) in enumerate(sheet):
            x = (k % 2) * 400; y = (k // 2) * 220
            W.paste(Image.fromarray(a), (x, y)); W.paste(Image.fromarray(b), (x + 200, y))
        W.save('preview_tmp/animals2.png')

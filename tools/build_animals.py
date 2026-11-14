#!/usr/bin/env python3
"""Turns the Quaternius 'Ultimate Animated Animals' glTF files (CC0) into one
light .glb per game species: all primitives merged into ONE surface (one draw
call per animal), species colours stored as vertex colours, side-projected UVs
for the fur-pattern texture, and only the animation clips the game uses.
Only deer, wolf, fox and buffalo come from this pack now; every other animal is baked by
build_animals2.py, which must run AFTER this script (it adds its entries to animals.json).
Run:  python3 tools/build_animals.py && python3 tools/build_animals2.py
"""
import json, base64, struct, os, sys
import numpy as np
SRC = 'assets_src/quaternius_animals'
OUT = 'assets/models/animals'
CT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8, 5120: np.int8, 5122: np.int16}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}
CLIPS = {'Idle': 'idle', 'Idle_2': 'idle2', 'Walk': 'walk', 'Gallop': 'run', 'Gallop_Jump': 'jump',
         'Attack': 'attack', 'Attack_Headbutt': 'attack', 'Eating': 'eat', 'Death': 'death', 'Idle_HitReact1': 'hit'}

def lin(c):  # sRGB 0..1 -> linear
    return [x ** 2.2 for x in c]

# role of every source material -> (role)
ROLES = {
    'Deer': {'Main': 'main', 'Hooves': 'dark', 'Main_Light': 'light', 'Main_Dark': 'shade', 'Eye_Lighter': 'main', 'Eye_Black': 'eye', 'Eye_White': 'eyew'},
    'Wolf': {'Main': 'main', 'Nose': 'dark', 'Main_Light': 'light', 'Eyes_Black': 'eye'},
    'Husky': {'Material': 'main', 'Material.006': 'dark', 'Material.001': 'light', 'Material.002': 'eye', 'Material.003': 'eyew'},
    'Fox': {'Main': 'main', 'Black': 'dark', 'Eyes': 'eye', 'Main_Light': 'light', 'Grey': 'shade'},
    'Bull': {'Main': 'main', 'Main_Light': 'light', 'Hooves': 'dark', 'Muzzle': 'shade', 'Eye_Black': 'eye', 'Eye_White': 'eyew', 'Horns': 'horn'},
    'Cow': {'Main': 'main', 'Main_Light': 'light', 'Hooves': 'dark', 'Muzzle': 'shade', 'Eye_Black': 'eye', 'Eye_White': 'eyew', 'Horns': 'horn'},
}
# species -> base model, palette (sRGB), pattern strength per role (alpha)
E0 = {'eye': (0.05, 0.05, 0.05), 'eyew': (0.9, 0.9, 0.85)}
SPECIES = {
    'deer':      ('Deer', {'main': (0.60, 0.40, 0.24), 'light': (0.86, 0.78, 0.64), 'shade': (0.42, 0.28, 0.18), 'dark': (0.16, 0.13, 0.12)}),
    'wolf':      ('Wolf', {'main': (0.45, 0.45, 0.44), 'light': (0.72, 0.72, 0.69), 'dark': (0.10, 0.10, 0.10)}),
    'fox':       ('Fox', {'main': (0.80, 0.42, 0.16), 'light': (0.93, 0.91, 0.86), 'shade': (0.30, 0.28, 0.27), 'dark': (0.12, 0.11, 0.10)}),
    'buffalo':   ('Bull', {'main': (0.17, 0.15, 0.14), 'light': (0.26, 0.23, 0.21), 'shade': (0.12, 0.11, 0.10), 'dark': (0.10, 0.09, 0.08), 'horn': (0.55, 0.52, 0.45)}),
}
PATTERN_ALPHA = {'main': 1.0, 'shade': 0.6, 'light': 0.25, 'dark': 0.0, 'eye': 0.0, 'eyew': 0.0, 'horn': 0.0}

def acc(d, buf, i):
    a = d['accessors'][i]; bv = d['bufferViews'][a['bufferView']]
    n = NC[a['type']]; dt = np.dtype(CT[a['componentType']])
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    stride = bv.get('byteStride', 0)
    assert stride in (0, n * dt.itemsize), 'interleaved buffers not supported'
    return np.frombuffer(buf, dt, a['count'] * n, off).reshape(a['count'], n)

class Out:
    def __init__(self):
        self.blob = bytearray(); self.views = []; self.accs = []
    def add(self, arr, typ, ctype, target=None, minmax=False):
        arr = np.ascontiguousarray(arr.astype(CT[ctype]))
        while len(self.blob) % 4: self.blob.append(0)
        v = {'buffer': 0, 'byteOffset': len(self.blob), 'byteLength': arr.nbytes}
        if target: v['target'] = target
        self.blob += arr.tobytes(); self.views.append(v)
        a = {'bufferView': len(self.views) - 1, 'componentType': ctype, 'count': int(arr.shape[0]), 'type': typ}
        if minmax:
            a['min'] = [float(x) for x in arr.reshape(arr.shape[0], -1).min(0)]
            a['max'] = [float(x) for x in arr.reshape(arr.shape[0], -1).max(0)]
        self.accs.append(a); return len(self.accs) - 1

def stride_speed(d, buf, clip):
    names = [n.get('name', '') for n in d['nodes']]
    for an in d['animations']:
        if an['name'] != clip: continue
        rng = []; T = 1.0
        for ch in an['channels']:
            if names[ch['target']['node']] in ('IKFrontLeg.L', 'IKBackLeg.L') and ch['target']['path'] == 'translation':
                s = an['samplers'][ch['sampler']]
                t = acc(d, buf, s['input'])[:, 0]; v = acc(d, buf, s['output'])
                if len(v) != len(t): v = v[1::3]
                rng.append(float(np.ptp(v[:, 2]))); T = float(t[-1])
        duty = 0.62 if clip == 'Walk' else 0.36
        return (sum(rng) / max(1, len(rng))) / (duty * T)
    return 1.0

def build(species, base, pal):
    d = json.load(open(f'{SRC}/{base}.gltf'))
    buf = base64.b64decode(d['buffers'][0]['uri'].split(',')[1])
    o = Out()
    mesh_nodes = [n for n in d['nodes'] if 'mesh' in n]
    assert len(mesh_nodes) == 1 and len(d['meshes']) == 1, base
    P = []; N = []; J = []; W = []; C = []; I = []; base_i = 0
    pal = dict(E0, **pal)
    for p in d['meshes'][0]['primitives']:
        at = p['attributes']
        pos = acc(d, buf, at['POSITION']); P.append(pos); N.append(acc(d, buf, at['NORMAL']))
        J.append(acc(d, buf, at['JOINTS_0']).astype(np.uint16)); W.append(acc(d, buf, at['WEIGHTS_0']).astype(np.float32))
        role = ROLES[base][d['materials'][p['material']]['name']]
        rgb = lin(pal.get(role, pal['main']))
        C.append(np.tile(np.array(rgb + [PATTERN_ALPHA[role]], np.float32), (len(pos), 1)))
        I.append(acc(d, buf, p['indices'])[:, 0].astype(np.uint32) + base_i); base_i += len(pos)
    P = np.concatenate(P); N = np.concatenate(N); J = np.concatenate(J); W = np.concatenate(W); C = np.concatenate(C); I = np.concatenate(I)
    H = float(P[:, 1].max() - P[:, 1].min())
    # side projection: u along the body, v up the body and over the back
    UV = np.stack([P[:, 2] / H, 1.0 - (P[:, 1] + np.abs(P[:, 0]) * 0.35) / H], 1).astype(np.float32)
    prim = {'attributes': {
        'POSITION': o.add(P, 'VEC3', 5126, 34962, True), 'NORMAL': o.add(N, 'VEC3', 5126, 34962),
        'TEXCOORD_0': o.add(UV, 'VEC2', 5126, 34962), 'COLOR_0': o.add(C, 'VEC4', 5126, 34962),
        'JOINTS_0': o.add(J, 'VEC4', 5123, 34962), 'WEIGHTS_0': o.add(W, 'VEC4', 5126, 34962)},
        'indices': o.add(I.reshape(-1, 1), 'SCALAR', 5125 if len(P) > 65535 else 5123, 34963), 'material': 0}
    skins = []
    for s in d['skins']:
        s2 = dict(s); s2['inverseBindMatrices'] = o.add(acc(d, buf, s['inverseBindMatrices']), 'MAT4', 5126); skins.append(s2)
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
                    remap[s[k]] = o.add(acc(d, buf, s[k]), a['type'], a['componentType'], None, k == 'input')
                s2[k] = remap[s[k]]
            samplers.append(s2)
        anims.append({'name': nm, 'channels': an['channels'], 'samplers': samplers})
    need = {'idle', 'walk', 'run', 'attack', 'eat', 'death'}
    assert need <= seen, (species, need - seen)
    g = {'asset': {'version': '2.0', 'generator': 'wild-survival build_animals.py (source: Quaternius, CC0)'},
         'scene': d.get('scene', 0), 'scenes': d['scenes'], 'nodes': d['nodes'], 'skins': skins,
         'meshes': [{'name': species, 'primitives': [prim]}],
         'materials': [{'name': 'fur', 'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 0.9}}],
         'animations': anims, 'accessors': o.accs, 'bufferViews': o.views, 'buffers': [{'byteLength': len(o.blob)}]}
    js = json.dumps(g, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    while len(o.blob) % 4: o.blob.append(0)
    with open(f'{OUT}/{species}.glb', 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(o.blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(o.blob), 0x004E4942)); f.write(o.blob)
    return {'base': base, 'tris': int(len(I) // 3), 'height': round(H, 3), 'length': round(float(np.ptp(P[:, 2])), 3),
            'walk_ref': round(stride_speed(d, buf, 'Walk'), 3), 'run_ref': round(stride_speed(d, buf, 'Gallop'), 3),
            'clips': sorted(seen)}

if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True); info = {}
    for sp, (base, pal) in SPECIES.items():
        info[sp] = build(sp, base, pal); print(sp, info[sp])
    json.dump(info, open(f'{OUT}/animals.json', 'w'), indent=1)

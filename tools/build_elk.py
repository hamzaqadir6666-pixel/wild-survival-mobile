#!/usr/bin/env python3
"""Bakes the player's elk for mobile.
Source: assets_src/sketchfab/elk.glb - "Realistic Animated Elk 3D Model" by WildMesh 3D, CC BY 4.0
        https://sketchfab.com/3d-models/realistic-animated-elk-3d-model-787834f9caa2474d9f1814b807c072d7
Output: assets/models/animals/elk.glb and the "elk" entry of animals.json
Changes: colour textures shrunk to 512 px, normal maps and unused vertex attributes dropped, materials turned into
plain metallic-roughness ones, root motion removed from every clip (the game moves the animal), the vertical leap
flattened out of the jump clip (the game supplies the height), clips renamed, clips the game has no use for dropped.
Run from the repo root:  python3 tools/build_elk.py
"""
import io, json, struct
import numpy as np
from PIL import Image
SRC = 'assets_src/sketchfab/elk.glb'; OUT = 'assets/models/animals'
CLIPS = {
    'Stand_Breathing_01': 'idle', 'Stand_Eating_01': 'eat',
    'Sneak': 'sneak', 'SneakL': 'sneak_l', 'SneakR': 'sneak_r',
    'WalkSlow': 'walkslow', 'WalkSlowL': 'walkslow_l',
    'Walk': 'walk', 'WalkL': 'walk_l', 'WalkR': 'walk_r',
    'Trot': 'trot', 'TrotL': 'trot_l', 'TrotR': 'trot_r',
    'Run': 'run', 'RunL': 'run_l', 'RunR': 'run_r',
    'Sprint': 'sprint', 'SprintL': 'sprint_l', 'SprintR': 'sprint_r',
    'JumpStand': 'jump',
    'Hit_Stand_L01': 'hit', 'Hit_Sitting_L01': 'hit_sit', 'Hit_Lying_L01': 'hit_lie',
    'Death_Stand_R01': 'death', 'Death_Sitting_L01': 'death_sit',
    'Trans_Stand_to_Sitting': 'to_sit', 'SittingSpec_Breathing_01': 'sit', 'Trans_Sitting_to_Stand': 'sit_up',
    'Trans_Sitting_to_Lying': 'to_lie', 'Lying_Breathing_01': 'lie', 'Lying_Idle_02': 'lie2',
    'Trans_Lying_to_Stand': 'lie_up', 'Trans_Lying_to_Sitting': 'lie_to_sit',
    'Trans_TurnL': 'turn_l', 'Trans_TurnR': 'turn_r',
}
GAITS = ['sneak', 'walkslow', 'walk', 'trot', 'run', 'sprint']

def main():
    d = open(SRC, 'rb').read()
    jl = struct.unpack('<I', d[12:16])[0]; j = json.loads(d[20:20 + jl]); b = d[20 + jl + 8:]
    N = j['nodes']
    def acc(i):
        a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
        n = {'SCALAR': 1, 'VEC3': 3, 'VEC4': 4}[a['type']]
        return np.frombuffer(b, dtype='<f4', count=a['count'] * n, offset=bv.get('byteOffset', 0) + a.get('byteOffset', 0)).reshape(-1, n)
    root = next(i for i, n in enumerate(N) if n.get('name') == 'RigRoot_01')
    pelvis = next(i for i, n in enumerate(N) if n.get('name') == 'RigPelvis_02')
    extra = bytearray(); extra_views = []      # new data appended after the original buffer
    def new_view(raw):
        while (len(b) + len(extra)) % 4: extra.append(0)
        extra_views.append({'buffer': 0, 'byteOffset': len(b) + len(extra), 'byteLength': len(raw)}); extra.extend(raw)
        return len(j['bufferViews']) + len(extra_views) - 1
    # ---- clips: keep, rename, strip root motion, measure stride speed
    anims = []; info_gaits = {}; jump = None
    for an in j['animations']:
        if an['name'] not in CLIPS: continue
        name = CLIPS[an['name']]; keep = []
        length = max(j['accessors'][s['input']]['max'][0] for s in an['samplers'])
        for c in an['channels']:
            t = c['target']
            if t['node'] == root:
                if t['path'] == 'translation':
                    v = acc(an['samplers'][c['sampler']]['output'])
                    if name in GAITS: info_gaits[name] = round(float(np.linalg.norm(v[-1] - v[0])) / 100.0 / length, 3)
                continue            # no root motion: the game moves the animal
            if t['node'] == pelvis and t['path'] == 'translation' and name == 'jump':
                s = an['samplers'][c['sampler']]; v = acc(s['output']).copy(); tt = acc(s['input'])[:, 0]
                up = np.where(v[:, 2] > v[0, 2] + 12.0)[0]                 # frames where the body is off the ground
                jump = [round(float(tt[up[0]]), 3), round(float(tt[up[-1]]), 3)]
                v[:, 2] = v[0, 2]                                          # the game lifts the animal itself
                a = dict(j['accessors'][s['output']]); a['bufferView'] = new_view(v.astype('<f4').tobytes()); a['byteOffset'] = 0
                a['min'] = v.min(0).tolist(); a['max'] = v.max(0).tolist()
                j['accessors'].append(a); s2 = dict(s); s2['output'] = len(j['accessors']) - 1
                an['samplers'].append(s2); c = dict(c); c['sampler'] = len(an['samplers']) - 1
            keep.append(c)
        anims.append({'name': name, 'channels': keep, 'samplers': an['samplers']})
    j['animations'] = sorted(anims, key=lambda a: a['name'])
    # ---- materials: colour texture only, 512 px
    images = []; textures = []
    for m in j['materials']:
        sg = m.pop('extensions')['KHR_materials_pbrSpecularGlossiness']; m.pop('normalTexture', None)
        src_img = j['images'][j['textures'][sg['diffuseTexture']['index']]['source']]
        bv = j['bufferViews'][src_img['bufferView']]
        im = Image.open(io.BytesIO(b[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])).convert('RGB')
        if max(im.size) > 512: im = im.resize((512, 512), Image.LANCZOS)
        buf = io.BytesIO(); im.save(buf, 'PNG', optimize=True)
        images.append({'bufferView': new_view(buf.getvalue()), 'mimeType': 'image/png', 'name': m['name']})
        textures.append({'sampler': 0, 'source': len(images) - 1})
        m['pbrMetallicRoughness'] = {'baseColorTexture': {'index': len(textures) - 1}, 'metallicFactor': 0.0, 'roughnessFactor': 1.0}
    old_image_views = {im['bufferView'] for im in j['images']}
    j['images'] = images; j['textures'] = textures
    j.pop('extensionsUsed', None); j.pop('extensionsRequired', None)
    for me in j['meshes']:
        for p in me['primitives']:
            for k in ('TANGENT', 'TEXCOORD_1', 'TEXCOORD_2'): p['attributes'].pop(k, None)
    # ---- drop accessors / buffer views nobody uses any more, and pack the buffer
    j['bufferViews'] += extra_views; full = bytes(b) + bytes(extra)
    used_acc = set()
    for me in j['meshes']:
        for p in me['primitives']:
            used_acc.update(p['attributes'].values()); used_acc.add(p['indices'])
    for s in j['skins']: used_acc.add(s['inverseBindMatrices'])
    for an in j['animations']:
        live = sorted({c['sampler'] for c in an['channels']}); remap = {o: n for n, o in enumerate(live)}
        an['samplers'] = [an['samplers'][o] for o in live]
        for c in an['channels']: c['sampler'] = remap[c['sampler']]
        for s in an['samplers']: used_acc.update((s['input'], s['output']))
    amap = {o: n for n, o in enumerate(sorted(used_acc))}
    j['accessors'] = [j['accessors'][o] for o in sorted(used_acc)]
    for me in j['meshes']:
        for p in me['primitives']:
            p['attributes'] = {k: amap[v] for k, v in p['attributes'].items()}; p['indices'] = amap[p['indices']]
    for s in j['skins']: s['inverseBindMatrices'] = amap[s['inverseBindMatrices']]
    for an in j['animations']:
        for s in an['samplers']: s['input'] = amap[s['input']]; s['output'] = amap[s['output']]
    used_bv = sorted({a['bufferView'] for a in j['accessors']} | {im['bufferView'] for im in j['images']})
    out = bytearray(); views = []; vmap = {}
    for o in used_bv:
        bv = dict(j['bufferViews'][o])
        while len(out) % 4: out.append(0)
        raw = full[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]
        bv['byteOffset'] = len(out); out.extend(raw); vmap[o] = len(views); views.append(bv)
    for a in j['accessors']: a['bufferView'] = vmap[a['bufferView']]
    for im in j['images']: im['bufferView'] = vmap[im['bufferView']]
    while len(out) % 4: out.append(0)
    j['bufferViews'] = views; j['buffers'] = [{'byteLength': len(out)}]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    with open(f'{OUT}/elk.glb', 'wb') as f:
        f.write(struct.pack('<4sII', b'glTF', 2, 12 + 8 + len(js) + 8 + len(out)))
        f.write(struct.pack('<I4s', len(js), b'JSON')); f.write(js)
        f.write(struct.pack('<I4s', len(out), b'BIN\x00')); f.write(out)
    tris = sum(j['accessors'][p['indices']]['count'] for me in j['meshes'] for p in me['primitives']) // 3
    info = json.load(open(f'{OUT}/animals.json'))
    info['elk'] = {'base': 'sketchfab/elk.glb', 'native': True, 'flip': False, 'tris': tris, 'height': 2.0, 'length': 2.3,
                   'walk_ref': info_gaits['walk'], 'run_ref': info_gaits['run'], 'walk_cycle': 1.0,
                   'gaits': [[g, info_gaits[g]] for g in GAITS], 'jump': jump,
                   'clips': sorted(a['name'] for a in j['animations'])}
    json.dump(info, open(f'{OUT}/animals.json', 'w'), indent=1)
    print('elk.glb', len(out) // 1024, 'kB', tris, 'tris', len(j['animations']), 'clips', info['elk']['gaits'], 'jump', jump)

if __name__ == '__main__':
    main()

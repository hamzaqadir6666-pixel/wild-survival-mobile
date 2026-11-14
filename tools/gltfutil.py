"""Small glTF helpers shared by the asset build scripts (numpy only)."""
import json, base64, struct, os
import numpy as np
CT = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8, 5120: np.int8, 5122: np.int16}
NC = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}

def load(path):
    if path.endswith('.glb'):
        raw = open(path, 'rb').read(); jl = struct.unpack_from('<I', raw, 12)[0]
        d = json.loads(raw[20:20 + jl]); return d, [raw[20 + jl + 8:]]
    d = json.load(open(path)); bufs = []
    for b in d['buffers']:
        u = b['uri']
        bufs.append(base64.b64decode(u.split(',')[1]) if u.startswith('data:') else open(os.path.join(os.path.dirname(path), u), 'rb').read())
    return d, bufs

def acc(d, bufs, i):
    a = d['accessors'][i]; bv = d['bufferViews'][a['bufferView']]
    n = NC[a['type']]; dt = np.dtype(CT[a['componentType']])
    off = bv.get('byteOffset', 0) + a.get('byteOffset', 0); stride = bv.get('byteStride', 0)
    buf = bufs[bv['buffer']]
    if stride in (0, n * dt.itemsize):
        return np.frombuffer(buf, dt, a['count'] * n, off).reshape(a['count'], n)
    out = np.zeros((a['count'], n), dt)
    for k in range(a['count']):
        out[k] = np.frombuffer(buf, dt, n, off + k * stride)
    return out

def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])

def node_matrix(n):
    if 'matrix' in n: return np.array(n['matrix'], float).reshape(4, 4).T
    m = np.eye(4)
    m[:3, :3] = quat_mat(n.get('rotation', [0, 0, 0, 1])) @ np.diag(n.get('scale', [1, 1, 1]))
    m[:3, 3] = n.get('translation', [0, 0, 0]); return m

def static_tris(path):
    """Returns (positions Nx3, indices Mx3, colour per triangle Mx3 linear, material names per tri) with node transforms applied."""
    d, bufs = load(path); P = []; I = []; C = []; M = []; base = 0
    def walk(ni, parent):
        nonlocal base
        n = d['nodes'][ni]; m = parent @ node_matrix(n)
        if 'mesh' in n:
            for p in d['meshes'][n['mesh']]['primitives']:
                pos = acc(d, bufs, p['attributes']['POSITION']).astype(float)
                pos = pos @ m[:3, :3].T + m[:3, 3]
                idx = acc(d, bufs, p['indices'])[:, 0].astype(np.int64).reshape(-1, 3) if 'indices' in p else np.arange(len(pos)).reshape(-1, 3)
                mat = d['materials'][p['material']]
                col = mat.get('pbrMetallicRoughness', {}).get('baseColorFactor', [1, 1, 1, 1])[:3]
                P.append(pos); I.append(idx + base); base += len(pos)
                C.append(np.tile(np.array(col), (len(idx), 1))); M.extend([mat['name']] * len(idx))
        for c in n.get('children', []): walk(c, m)
    for r in d['scenes'][d.get('scene', 0)]['nodes']: walk(r, np.eye(4))
    return np.concatenate(P), np.concatenate(I), np.concatenate(C), M

def write_glb(path, P, N, C, UV, I, name='mesh'):
    blob = bytearray(); views = []; accs = []
    def add(arr, typ, ctype, target, minmax=False):
        arr = np.ascontiguousarray(arr.astype(CT[ctype]))
        while len(blob) % 4: blob.append(0)
        views.append({'buffer': 0, 'byteOffset': len(blob), 'byteLength': arr.nbytes, 'target': target}); blob.extend(arr.tobytes())
        a = {'bufferView': len(views) - 1, 'componentType': ctype, 'count': int(arr.shape[0]), 'type': typ}
        if minmax: a['min'] = [float(x) for x in arr.min(0)]; a['max'] = [float(x) for x in arr.max(0)]
        accs.append(a); return len(accs) - 1
    at = {'POSITION': add(P, 'VEC3', 5126, 34962, True), 'NORMAL': add(N, 'VEC3', 5126, 34962), 'COLOR_0': add(C, 'VEC4', 5126, 34962), 'TEXCOORD_0': add(UV, 'VEC2', 5126, 34962)}
    prim = {'attributes': at, 'indices': add(I.reshape(-1, 1), 'SCALAR', 5125 if len(P) > 65535 else 5123, 34963), 'material': 0}
    g = {'asset': {'version': '2.0', 'generator': 'wild-survival asset build (source models: Quaternius, CC0)'}, 'scene': 0, 'scenes': [{'nodes': [0]}],
         'nodes': [{'name': name, 'mesh': 0}], 'meshes': [{'name': name, 'primitives': [prim]}],
         'materials': [{'name': 'veg', 'pbrMetallicRoughness': {'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 1}}],
         'accessors': accs, 'bufferViews': views, 'buffers': [{'byteLength': len(blob)}]}
    js = json.dumps(g, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    while len(blob) % 4: blob.append(0)
    with open(path, 'wb') as f:
        f.write(struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(blob)))
        f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack('<II', len(blob), 0x004E4942)); f.write(blob)

def render(P, I, C, size=256, yaw=0.6, pitch=0.25, bg=(60, 70, 80)):
    """Tiny software rasteriser used only to eyeball assets (orthographic, flat lambert)."""
    cy, sy, cp, sp = np.cos(yaw), np.sin(yaw), np.cos(pitch), np.sin(pitch)
    R = np.array([[cy, 0, -sy], [0, 1, 0], [sy, 0, cy]]); R = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]]) @ R
    V = P @ R.T; mn = V.min(0); mx = V.max(0); s = (size - 8) / max(mx[0] - mn[0], mx[1] - mn[1])
    X = (V[:, 0] - (mn[0] + mx[0]) / 2) * s + size / 2; Y = size / 2 - (V[:, 1] - (mn[1] + mx[1]) / 2) * s; Z = V[:, 2]
    img = np.zeros((size, size, 3), np.float32) + np.array(bg, np.float32) / 255; zb = np.full((size, size), -1e9)
    L = np.array([0.4, 0.8, 0.45]); L /= np.linalg.norm(L)
    for t in range(len(I)):
        a, b, c = I[t]; n = np.cross(V[b] - V[a], V[c] - V[a]); ln = np.linalg.norm(n)
        if ln < 1e-12: continue
        n /= ln; sh = 0.45 + 0.55 * abs(n @ L)
        xs = np.array([X[a], X[b], X[c]]); ys = np.array([Y[a], Y[b], Y[c]]); zs = np.array([Z[a], Z[b], Z[c]])
        x0, x1 = int(max(0, np.floor(xs.min()))), int(min(size - 1, np.ceil(xs.max()))); y0, y1 = int(max(0, np.floor(ys.min()))), int(min(size - 1, np.ceil(ys.max())))
        if x1 < x0 or y1 < y0: continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
        if abs(den) < 1e-9: continue
        w0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
        w1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den; w2 = 1 - w0 - w1
        m = (w0 >= 0) & (w1 >= 0) & (w2 >= 0); z = w0 * zs[0] + w1 * zs[1] + w2 * zs[2]
        sub = zb[y0:y1 + 1, x0:x1 + 1]; m &= z > sub; sub[m] = z[m]
        col = C[t] if callable(C) is False and getattr(C, 'ndim', 1) == 2 else C
        img[y0:y1 + 1, x0:x1 + 1][m] = (np.asarray(col) ** (1 / 2.2)) * sh
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)

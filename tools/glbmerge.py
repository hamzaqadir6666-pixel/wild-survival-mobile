"""Merge the meshes of one GLB (an outfit / character) with the animations of others.

All inputs must share the same rig (Quaternius Universal rig: identical joint
node names).  Output is a single self-contained .glb.
"""
import json, struct, sys, base64, os

COMP = {5120: ('b', 1), 5121: ('B', 1), 5122: ('h', 2), 5123: ('H', 2), 5125: ('I', 4), 5126: ('f', 4)}
NCOMP = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT2': 4, 'MAT3': 9, 'MAT4': 16}


def load(path):
    data = open(path, 'rb').read()
    magic, ver, length = struct.unpack_from('<III', data, 0)
    assert magic == 0x46546C67, path
    off = 12
    js = None
    binchunk = b''
    while off < len(data):
        clen, ctype = struct.unpack_from('<II', data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode('utf-8'))
        elif ctype == 0x004E4942:
            binchunk = chunk
    return js, binchunk


def accessor_bytes(js, binchunk, idx):
    acc = js['accessors'][idx]
    bv = js['bufferViews'][acc['bufferView']]
    fmt, size = COMP[acc['componentType']]
    n = NCOMP[acc['type']]
    stride = bv.get('byteStride') or size * n
    base = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    count = acc['count']
    out = bytearray()
    for i in range(count):
        o = base + i * stride
        out += binchunk[o:o + size * n]
    return bytes(out), acc['componentType'], acc['type'], count, stride == size * n


class Builder:
    def __init__(self):
        self.js = {'asset': {'version': '2.0', 'generator': 'glbmerge'},
                   'scene': 0, 'scenes': [{'nodes': []}],
                   'nodes': [], 'meshes': [], 'materials': [], 'textures': [],
                   'images': [], 'samplers': [], 'accessors': [], 'bufferViews': [],
                   'skins': [], 'animations': []}
        self.bin = bytearray()

    def add_view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin += b'\x00'
        bv = {'buffer': 0, 'byteOffset': len(self.bin), 'byteLength': len(data)}
        if target:
            bv['target'] = target
        self.js['bufferViews'].append(bv)
        self.bin += data
        return len(self.js['bufferViews']) - 1

    def add_accessor(self, data, ctype, atype, count, minmax=None, target=None):
        bv = self.add_view(data, target)
        acc = {'bufferView': bv, 'componentType': ctype, 'type': atype, 'count': count}
        if minmax:
            acc['min'], acc['max'] = minmax
        self.js['accessors'].append(acc)
        return len(self.js['accessors']) - 1

    def finish(self):
        self.js['buffers'] = [{'byteLength': len(self.bin)}]
        jsb = json.dumps(self.js, separators=(',', ':')).encode('utf-8')
        while len(jsb) % 4:
            jsb += b' '
        b = bytes(self.bin)
        while len(b) % 4:
            b += b'\x00'
        total = 12 + 8 + len(jsb) + 8 + len(b)
        out = struct.pack('<III', 0x46546C67, 2, total)
        out += struct.pack('<II', len(jsb), 0x4E4F534A) + jsb
        out += struct.pack('<II', len(b), 0x004E4942) + b
        return out


def _read_accessor_np(js, binchunk, idx):
    import numpy as np
    acc = js['accessors'][idx]
    bv = js['bufferViews'][acc['bufferView']]
    fmt, size = COMP[acc['componentType']]
    n = NCOMP[acc['type']]
    stride = bv.get('byteStride') or size * n
    base = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    if stride == size * n:
        raw = binchunk[base: base + size * n * acc['count']]
        return np.frombuffer(raw, dtype=np.dtype(fmt)).reshape(-1, n).copy()
    out = np.empty((acc['count'], n), dtype=np.dtype(fmt))
    for i in range(acc['count']):
        o = base + i * stride
        out[i] = np.frombuffer(binchunk[o:o + size * n], dtype=np.dtype(fmt))
    return out


def attach_rigid(b, js, binchunk, attach_path, parent_name, offset=(0, 0, 0), scale=1.0,
                 to_parent=True, rotate=(0, 0, 0), material_color=None):
    """Attach a static (unskinned) mesh to a joint.

    The mesh geometry is baked in the joint's rest space so it follows the joint.
    offset is applied in world space *before* the joint inverse (i.e. it is the
    position of the mesh inside the joint rest frame when to_parent is False).
    """
    import math
    ajs, abin = load(attach_path)
    names = {}
    for i, n in enumerate(js['nodes']):
        nm = n.get('name')
        if nm and nm not in names:
            names[nm] = i
    jidx = names.get(parent_name)
    assert jidx is not None, 'joint %s not found' % parent_name
    # rest world matrix of joint = product of node transforms up the chain
    import numpy as np

    def quat_mat(q):
        x, y, z, w = q
        return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])

    def local(n):
        M = np.eye(4)
        s = n.get('scale', [1, 1, 1])
        M[:3, :3] = quat_mat(n.get('rotation', [0, 0, 0, 1])) @ np.diag(s)
        M[:3, 3] = n.get('translation', [0, 0, 0])
        return M

    parent = {}
    for i, n in enumerate(js['nodes']):
        for c in n.get('children', []):
            parent[c] = i

    def world(i):
        M = local(js['nodes'][i])
        p = parent.get(i)
        return M if p is None else world(p) @ M

    jm = world(jidx)
    # placement in world: rotate, scale, translate
    R = np.eye(4)
    from math import cos, sin, radians
    rx, ry, rz = [radians(a) for a in rotate]
    Rx = np.array([[1, 0, 0, 0], [0, cos(rx), -sin(rx), 0], [0, sin(rx), cos(rx), 0], [0, 0, 0, 1]])
    Ry = np.array([[cos(ry), 0, sin(ry), 0], [0, 1, 0, 0], [-sin(ry), 0, cos(ry), 0], [0, 0, 0, 1]])
    Rz = np.array([[cos(rz), -sin(rz), 0, 0], [sin(rz), cos(rz), 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]])
    P = np.eye(4)
    P[:3, :3] = (Ry @ Rx @ Rz)[:3, :3] * scale
    P[:3, 3] = offset
    bake = np.linalg.inv(jm) @ P
    newmeshes = []
    for m in ajs['meshes']:
        prims = []
        for pr in m['primitives']:
            pos = _read_accessor_np(ajs, abin, pr['attributes']['POSITION']).astype(np.float64)
            h = np.concatenate([pos, np.ones((len(pos), 1))], 1)
            pos2 = (bake @ h.T).T[:, :3].astype(np.float32)
            if 'NORMAL' in pr['attributes']:
                nrm = _read_accessor_np(ajs, abin, pr['attributes']['NORMAL']).astype(np.float64)
                nm = (bake[:3, :3] @ nrm.T).T
                nm /= (np.linalg.norm(nm, axis=1, keepdims=True) + 1e-9)
                nrm = nm.astype(np.float32)
            else:
                nrm = None
            attrs = {}
            attrs['POSITION'] = b.add_accessor(pos2.tobytes(), 5126, 'VEC3', len(pos2),
                                               (pos2.min(0).tolist(), pos2.max(0).tolist()), target=34962)
            if nrm is not None:
                attrs['NORMAL'] = b.add_accessor(nrm.tobytes(), 5126, 'VEC3', len(nrm), target=34962)
            if 'TEXCOORD_0' in pr['attributes']:
                uv = _read_accessor_np(ajs, abin, pr['attributes']['TEXCOORD_0']).astype(np.float32)
                attrs['TEXCOORD_0'] = b.add_accessor(uv.tobytes(), 5126, 'VEC2', len(uv), target=34962)
            np_ = {'attributes': attrs}
            if 'indices' in pr:
                ind = _read_accessor_np(ajs, abin, pr['indices']).reshape(-1).astype(np.uint32)
                np_['indices'] = b.add_accessor(ind.tobytes(), 5125, 'SCALAR', len(ind), target=34963)
            # material: reuse existing or add flat one
            mat = pr.get('material')
            if material_color is not None:
                b.js['materials'].append({'name': 'attach_mat%d' % len(b.js['materials']),
                                          'pbrMetallicRoughness': {
                                              'baseColorFactor': list(material_color),
                                              'metallicFactor': 0.0, 'roughnessFactor': 0.8},
                                          'doubleSided': True})
                np_['material'] = len(b.js['materials']) - 1
            elif mat is not None and mat < len(ajs.get('materials', [])):
                src = json.loads(json.dumps(ajs['materials'][mat]))
                src['name'] = (src.get('name', 'mat') + '_att')
                b.js['materials'].append(src)
                np_['material'] = len(b.js['materials']) - 1
            prims.append(np_)
        b.js['meshes'].append({'name': 'att_' + m.get('name', ''), 'primitives': prims})
        newmeshes.append(len(b.js['meshes']) - 1)
    n = {'name': 'attach_' + parent_name, 'mesh': newmeshes[0]}
    if len(newmeshes) > 1:
        n['children'] = []
    # append node and parent it to the joint node
    b.js['nodes'].append(n)
    newidx = len(b.js['nodes']) - 1
    js['nodes'][jidx].setdefault('children', []).append(newidx)
    b.js['nodes'] = json.loads(json.dumps(js['nodes']))
    return newidx


def merge(main_path, anim_paths, out_path, drop_meshes=(), only_meshes=None, attachments=()):
    js, binchunk = load(main_path)
    b = Builder()
    # ---- attachments (hat / props rigidly bound to joints) ----
    b.js['nodes'] = json.loads(json.dumps(js['nodes']))
    # ---- materials, textures, images, samplers ----
    for key in ('samplers', 'images', 'textures', 'materials'):
        b.js[key] = json.loads(json.dumps(js.get(key, [])))
    # images: copy buffers
    for i, img in enumerate(b.js['images']):
        if 'bufferView' in img:
            src = js['bufferViews'][img['bufferView']]
            data = binchunk[src.get('byteOffset', 0):src.get('byteOffset', 0) + src['byteLength']]
            img['bufferView'] = b.add_view(data)
    for att in attachments:
        attach_rigid(b, js, binchunk, att['path'], att['bone'], att.get('offset', (0, 0, 0)),
                     att.get('scale', 1.0), rotate=att.get('rotate', (0, 0, 0)),
                     material_color=att.get('color'))
    # ---- meshes ----
    mesh_map = []
    for mi, m in enumerate(js['meshes']):
        if only_meshes is not None and m.get('name') not in only_meshes:
            continue
        if m.get('name') in drop_meshes:
            continue
        prims = []
        for pr in m['primitives']:
            np_ = dict(pr)
            np_.pop('targets', None)
            attrs = {}
            for k, ai in pr['attributes'].items():
                data, ctype, atype, count, packed = accessor_bytes(js, binchunk, ai)
                acc0 = js['accessors'][ai]
                mm = None
                if 'min' in acc0:
                    mm = (acc0['min'], acc0['max'])
                attrs[k] = b.add_accessor(data, ctype, atype, count, mm,
                                          target=34962 if k != 'JOINTS_0' else None)
            np_['attributes'] = attrs
            if 'indices' in pr:
                data, ctype, atype, count, _ = accessor_bytes(js, binchunk, pr['indices'])
                np_['indices'] = b.add_accessor(data, ctype, atype, count, target=34963)
            prims.append(np_)
        nm = {'name': m.get('name', 'mesh%d' % mi), 'primitives': prims}
        b.js['meshes'].append(nm)
        mesh_map.append((mi, len(b.js['meshes']) - 1))
    # ---- skins (reuse node indices) ----
    b.js['skins'] = json.loads(json.dumps(js.get('skins', [])))
    for s in b.js['skins']:
        if 'inverseBindMatrices' in s:
            data, ctype, atype, count, _ = accessor_bytes(js, binchunk, s['inverseBindMatrices'])
            s['inverseBindMatrices'] = b.add_accessor(data, ctype, atype, count)
    # ---- animations from libraries ----
    for ap in anim_paths:
        ajs, abin = load(ap)
        # name -> node index in destination (by name)
        dst_names = {}
        for i, n in enumerate(b.js['nodes']):
            nm = n.get('name')
            if nm and nm not in dst_names:
                dst_names[nm] = i
        for anim in ajs.get('animations', []):
            chans = []
            ok = True
            for ch in anim['channels']:
                tnode = ajs['nodes'][ch['target']['node']].get('name')
                if tnode not in dst_names:
                    ok = False
                    break
                chans.append({'sampler': ch['sampler'],
                              'target': {'node': dst_names[tnode], 'path': ch['target']['path']}})
            if not ok:
                print('  skip anim (rig mismatch):', anim.get('name'))
                continue
            samplers = []
            for s in anim['samplers']:
                idata, ictype, iatype, icount, _ = accessor_bytes(ajs, abin, s['input'])
                oacc = ajs['accessors'][s['input']]
                a_in = b.add_accessor(idata, ictype, iatype, icount, (oacc['min'], oacc['max']))
                odata, octype, oatype, ocount, _ = accessor_bytes(ajs, abin, s['output'])
                a_out = b.add_accessor(odata, octype, oatype, ocount)
                samplers.append({'input': a_in, 'output': a_out,
                                 'interpolation': s.get('interpolation', 'LINEAR')})
            b.js['animations'].append({'name': anim.get('name'), 'channels': chans, 'samplers': samplers})
    children = set()
    for n in b.js['nodes']:
        for c in n.get('children', []):
            children.add(c)
    # meshes attached to nodes reference mesh index - remap
    remap = dict(mesh_map)
    for i, n in enumerate(b.js['nodes']):
        if 'mesh' in n:
            if n['mesh'] in remap:
                n['mesh'] = remap[n['mesh']]
            else:
                # mesh was dropped; attach nothing
                n.pop('mesh')
    roots = [i for i in range(len(b.js['nodes'])) if i not in children]
    b.js['scenes'][0]['nodes'] = roots
    open(out_path, 'wb').write(b.finish())
    print('wrote', out_path, os.path.getsize(out_path), 'bytes;',
          'meshes', len(b.js['meshes']), 'anims', len(b.js['animations']))


if __name__ == '__main__':
    main = sys.argv[1]
    anims = sys.argv[2].split(',')
    out = sys.argv[3]
    merge(main, anims, out)


def merged_with_hats(main, anims, out, **kw):
    merge(main, anims.split(','), out,
          attachments=[dict(path='/home/user/assets-src/hat.glb', bone='Head',
                            offset=(0.0, 0.055, 0.005), scale=1.0,
                            rotate=(0, 0, 0), color=(0.085, 0.055, 0.035, 1.0))], **kw)

"""Procedurally build a low-poly cowboy hat GLB from a lathe profile."""
import math, struct, sys

def build_hat(path, br=0.44, crown=0.135, ring_pts=None, segs=48):
    """br: brim radius, crown height. Lathe around Y."""
    # profile: (radius, y) going from crown top outward to brim edge
    prof = []
    prof.append((0.001, crown + 0.035))
    prof.append((0.055, crown + 0.03))
    prof.append((0.095, crown + 0.012))
    prof.append((0.108, crown - 0.02))
    prof.append((0.112, crown - 0.06))
    prof.append((0.118, 0.012))         # crown base
    prof.append((0.128, 0.004))         # brim inner
    prof.append((br * 0.55, 0.006))
    prof.append((br * 0.8, 0.018))
    prof.append((br, 0.004))            # brim outer (curved up)
    prof.append((br * 0.98, -0.008))
    prof.append((br * 0.5, -0.012))
    prof.append((0.118, -0.006))
    prof.append((0.155, -0.055))        # band underside
    verts = []
    norms = []
    for (r, y) in prof:
        for i in range(segs):
            a = 2 * math.pi * i / segs
            x = math.cos(a) * r
            z = math.sin(a) * r
            # brim: lift the left/right sides (a cowboy curl)
            if r > 0.2:
                y2 = y + 0.055 * (abs(math.cos(a)) ** 3)
            else:
                y2 = y
            verts.append((x, y2, z))
    # normals: approximate by radial direction blended
    idx = []
    nrow = len(prof)
    for j in range(nrow - 1):
        for i in range(segs):
            i2 = (i + 1) % segs
            a = j * segs + i
            b = j * segs + i2
            c = (j + 1) * segs + i
            d = (j + 1) * segs + i2
            idx += [a, c, b, b, c, d]
    # closed cap at top
    return verts, idx

def write_glb(path, verts, idx, color=(0.085, 0.055, 0.035, 1.0)):
    import json
    vb = b''.join(struct.pack('<fff', *v) for v in verts)
    ib = b''.join(struct.pack('<I', i) for i in idx)
    while len(vb) % 4: vb += b'\x00'
    while len(ib) % 4: ib += b'\x00'
    bin_ = vb + ib
    js = {
        'asset': {'version': '2.0', 'generator': 'mkhat'},
        'scene': 0, 'scenes': [{'nodes': [0]}],
        'nodes': [{'name': 'CowboyHat', 'mesh': 0}],
        'meshes': [{'name': 'CowboyHat', 'primitives': [{
            'attributes': {'POSITION': 0}, 'indices': 1, 'material': 0}]}],
        'materials': [{'name': 'HatFelt', 'pbrMetallicRoughness': {
            'baseColorFactor': list(color), 'metallicFactor': 0.0, 'roughnessFactor': 0.85},
            'doubleSided': True}],
        'accessors': [
            {'bufferView': 0, 'componentType': 5126, 'type': 'VEC3', 'count': len(verts),
             'min': [min(v[0] for v in verts), min(v[1] for v in verts), min(v[2] for v in verts)],
             'max': [max(v[0] for v in verts), max(v[1] for v in verts), max(v[2] for v in verts)]},
            {'bufferView': 1, 'componentType': 5125, 'type': 'SCALAR', 'count': len(idx)},
        ],
        'bufferViews': [
            {'buffer': 0, 'byteOffset': 0, 'byteLength': len(vb), 'target': 34962},
            {'buffer': 0, 'byteOffset': len(vb), 'byteLength': len(ib), 'target': 34963},
        ],
        'buffers': [{'byteLength': len(bin_)}],
    }
    jsb = json.dumps(js, separators=(',', ':')).encode()
    while len(jsb) % 4: jsb += b' '
    total = 12 + 8 + len(jsb) + 8 + len(bin_)
    out = struct.pack('<III', 0x46546C67, 2, total)
    out += struct.pack('<II', len(jsb), 0x4E4F534A) + jsb
    out += struct.pack('<II', len(bin_), 0x004E4942) + bin_
    open(path, 'wb').write(out)

if __name__ == '__main__':
    v, i = build_hat(sys.argv[1])
    write_glb(sys.argv[1], v, i)
    print('wrote', sys.argv[1], len(v), 'verts')

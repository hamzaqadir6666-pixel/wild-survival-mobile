extends Node3D
class_name VoxelWorld

signal generation_progress(done: int, total: int)
signal generation_finished

const CHUNK := 16
const RADIUS := 3
const HEIGHT_LIMIT := 32
const GRASS := 1
const DIRT := 2
const STONE := 3
const WOOD := 4
const LEAVES := 5
const SAND := 6
const PLANKS := 7
const NAMES := ["", "GRASS", "DIRT", "STONE", "LOG", "LEAVES", "SAND", "PLANKS"]
const COLORS := [Color.WHITE, Color("80b85a"), Color("8c6244"), Color("858e90"), Color("9c7046"), Color("508d48"), Color("ddc88d"), Color("c49a62")]
const DIRS := [Vector3i(1,0,0), Vector3i(-1,0,0), Vector3i(0,1,0), Vector3i(0,-1,0), Vector3i(0,0,1), Vector3i(0,0,-1)]
# Counter-clockwise quads; culling is disabled so both renderers show every face.
const CORNERS := [
 [Vector3(1,0,0), Vector3(1,1,0), Vector3(1,1,1), Vector3(1,0,1)],
 [Vector3(0,0,1), Vector3(0,1,1), Vector3(0,1,0), Vector3(0,0,0)],
 [Vector3(0,1,0), Vector3(0,1,1), Vector3(1,1,1), Vector3(1,1,0)],
 [Vector3(0,0,1), Vector3(0,0,0), Vector3(1,0,0), Vector3(1,0,1)],
 [Vector3(1,0,1), Vector3(1,1,1), Vector3(0,1,1), Vector3(0,0,1)],
 [Vector3(0,0,0), Vector3(0,1,0), Vector3(1,1,0), Vector3(1,0,0)]
]

var blocks: Dictionary = {}
var chunks: Dictionary = {}
var heights: Dictionary = {}
var material: StandardMaterial3D
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var ready_to_play := false
var edits: Dictionary = {}

func _ready() -> void:
 material = _make_material()
 noise.seed = 48291
 noise.frequency = 0.018
 noise.fractal_octaves = 4
 detail.seed = 7201
 detail.frequency = 0.055
 _generate()

func _generate() -> void:
 var extent := CHUNK * RADIUS
 for x in range(-extent, extent):
  for z in range(-extent, extent):
   var h := clampi(int(12.0 + noise.get_noise_2d(x, z) * 10.0 + detail.get_noise_2d(x, z) * 3.0), 5, 23)
   heights[Vector2i(x,z)] = h
   for y in range(h + 1):
    var block := STONE
    if y == h:
     block = SAND if h <= 9 else GRASS
    elif y >= h - 3:
     block = SAND if h <= 9 else DIRT
    blocks[Vector3i(x,y,z)] = block
 # Trees are deterministic, with an open spawn area and margins around the map.
 for x in range(-extent + 3, extent - 3):
  for z in range(-extent + 3, extent - 3):
   var h: int = heights[Vector2i(x,z)]
   var v := absi((x * 73856093) ^ (z * 19349663) ^ 81523) % 1000
   if h > 10 and v < 10 and Vector2(x,z).length() > 8:
    _add_tree(x, h + 1, z)
 var save := ConfigFile.new()
 if save.load("user://world.cfg") == OK:
  var stored: Variant = save.get_value("world", "edits", {})
  if stored is Dictionary:
   edits = stored
   for p in edits:
    if p is Vector3i:
     if edits[p] == 0:
      blocks.erase(p)
     else:
      blocks[p] = edits[p]
 var total := RADIUS * RADIUS * 4
 var done := 0
 for cx in range(-RADIUS, RADIUS):
  for cz in range(-RADIUS, RADIUS):
   _rebuild_chunk(Vector2i(cx,cz))
   done += 1
   generation_progress.emit(done, total)
   await get_tree().process_frame
 ready_to_play = true
 generation_finished.emit()

func _add_tree(x: int, y: int, z: int) -> void:
 var trunk := 4 + absi(x * 31 + z * 17) % 2
 for dy in range(trunk):
  blocks[Vector3i(x,y+dy,z)] = WOOD
 for dy in range(-2, 2):
  var r := 2 if dy < 1 else 1
  for dx in range(-r,r+1):
   for dz in range(-r,r+1):
    if absi(dx) == r and absi(dz) == r and dy != 0:
     continue
    var p := Vector3i(x+dx,y+trunk-1+dy,z+dz)
    if not blocks.has(p) and p.y < HEIGHT_LIMIT:
     blocks[p] = LEAVES

func get_block(p: Vector3i) -> int:
 return blocks.get(p, 0)

func edit_block(p: Vector3i, id: int) -> void:
 var extent := CHUNK * RADIUS
 if p.x < -extent or p.x >= extent or p.z < -extent or p.z >= extent or p.y < 0 or p.y >= HEIGHT_LIMIT:
  return
 edits[p] = id
 var save := ConfigFile.new()
 save.set_value("world", "edits", edits)
 save.save("user://world.cfg")
 if id == 0:
  blocks.erase(p)
 else:
  blocks[p] = id
 var c := Vector2i(floori(float(p.x) / CHUNK), floori(float(p.z) / CHUNK))
 _rebuild_chunk(c)
 # Boundary edits must also update the neighbor's formerly hidden faces.
 for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
  if (d.x != 0 and posmod(p.x, CHUNK) == (0 if d.x < 0 else CHUNK - 1)) or (d.y != 0 and posmod(p.z, CHUNK) == (0 if d.y < 0 else CHUNK - 1)):
   var neighbor: Vector2i = c + d
   if chunks.has(neighbor):
    _rebuild_chunk(neighbor)

func _rebuild_chunk(c: Vector2i) -> void:
 if chunks.has(c):
  chunks[c].queue_free()
 var body := StaticBody3D.new()
 body.name = "Chunk_%d_%d" % [c.x,c.y]
 add_child(body)
 chunks[c] = body
 var verts := PackedVector3Array()
 var normals := PackedVector3Array()
 var uvs := PackedVector2Array()
 var colors := PackedColorArray()
 var indices := PackedInt32Array()
 for x in range(c.x * CHUNK, (c.x + 1) * CHUNK):
  for z in range(c.y * CHUNK, (c.y + 1) * CHUNK):
   for y in range(HEIGHT_LIMIT):
    var p := Vector3i(x,y,z)
    var id: int = blocks.get(p, 0)
    if id == 0:
     continue
    for face in range(6):
     if blocks.has(p + DIRS[face]):
      continue
     var tile := _tile_for(id, face)
     var base := verts.size()
     var shade := 1.0 if face == 2 else (0.58 if face == 3 else (0.82 if face < 2 else 0.72))
     for i in range(4):
      verts.append(Vector3(p) + CORNERS[face][i])
      normals.append(Vector3(DIRS[face]))
      var uv: Vector2 = [Vector2(0,1), Vector2(0,0), Vector2(1,0), Vector2(1,1)][i]
      # Half-pixel inset avoids sampling adjacent atlas tiles.
      uvs.append(Vector2((tile * 16.0 + 0.5 + uv.x * 15.0) / 144.0, (0.5 + uv.y * 15.0) / 16.0))
      colors.append(Color(shade,shade,shade,1))
     indices.append_array(PackedInt32Array([base,base+1,base+2,base,base+2,base+3]))
 if verts.is_empty():
  return
 var arrays := []
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX] = verts
 arrays[Mesh.ARRAY_NORMAL] = normals
 arrays[Mesh.ARRAY_TEX_UV] = uvs
 arrays[Mesh.ARRAY_COLOR] = colors
 arrays[Mesh.ARRAY_INDEX] = indices
 var mesh := ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
 mesh.surface_set_material(0, material)
 var instance := MeshInstance3D.new()
 instance.mesh = mesh
 body.add_child(instance)
 var collider := CollisionShape3D.new()
 var shape := mesh.create_trimesh_shape()
 # Blocks are solid from either side, including when mining into a hillside.
 shape.backface_collision = true
 collider.shape = shape
 body.add_child(collider)

func _tile_for(id: int, face: int) -> int:
 match id:
  GRASS: return 0 if face == 2 else (2 if face == 3 else 1)
  DIRT: return 2
  STONE: return 3
  WOOD: return 5 if face == 2 or face == 3 else 4
  LEAVES: return 6
  SAND: return 7
  PLANKS: return 8
 return 3

func _make_material() -> StandardMaterial3D:
 var image := Image.create(144, 16, false, Image.FORMAT_RGBA8)
 var palette := [Color("75ad53"),Color("896044"),Color("8c6245"),Color("87908e"),Color("87603c"),Color("ba8c59"),Color("4e8744"),Color("d9c58a"),Color("ba8d5b")]
 for tile in range(9):
  for x in range(16):
   for y in range(16):
    var n := float(absi((x * 127 + y * 311 + tile * 73) * 92821 ^ (x * y * 1237)) % 27 - 13) / 255.0
    var col: Color = palette[tile]
    if tile == 1 and y < 4 + (x * 7 % 3):
     col = palette[0]
    if tile == 4 and (x % 5 == 0 or x % 7 == 0):
     col = col.darkened(0.18)
    if tile == 5 and (x == 2 or x == 13 or y == 2 or y == 13 or x == 6 or y == 6):
     col = col.darkened(0.17)
    if tile == 8 and (y == 0 or y == 8 or (x == 0 and y < 8) or (x == 8 and y >= 8)):
     col = col.darkened(0.23)
    image.set_pixel(tile * 16 + x, y, Color(clampf(col.r+n,0,1),clampf(col.g+n,0,1),clampf(col.b+n,0,1)))
 var mat := StandardMaterial3D.new()
 mat.albedo_texture = ImageTexture.create_from_image(image)
 mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
 mat.vertex_color_use_as_albedo = true
 mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 mat.roughness = 1.0
 return mat

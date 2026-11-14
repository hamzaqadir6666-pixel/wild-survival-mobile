extends Node
## The fixed map: heights, biome grid and every hand-placed feature (built by tools/build_world.py).
## Pure data + fast queries; no physics engine is used anywhere in the game.

const SIZE := 1024.0
const CELL := 4.0
const N := 257
const WATER_Y := 0.0
const FOREST := 0
const GRASS := 1
const TRAIL := 2
const SHORE := 3
const ROCK := 4
const WATER := 5
const PLAY_LIMIT := 444.0

var heights := PackedFloat32Array()
var splat := PackedByteArray()
var biomes := PackedByteArray()
var info := {}
var thickets: Array = []      # {x,z,r}
var landmarks: Array = []     # {kind,name,x,z}
var lakes: Array = []
var plants: Array = []        # {t,x,z}
var veg_types: Array = []
var tree_grid := {}           # cell key -> PackedFloat32Array [x, z, radius, ...]
var loaded := false

func load_data() -> void:
	if loaded: return
	heights = FileAccess.get_file_as_bytes("res://assets/world/heights.bin").to_float32_array()
	splat = FileAccess.get_file_as_bytes("res://assets/world/splat.bin")
	biomes = FileAccess.get_file_as_bytes("res://assets/world/biome.bin")
	info = JSON.parse_string(FileAccess.get_file_as_string("res://assets/world/world.json"))
	thickets = info.thickets; landmarks = info.landmarks; lakes = info.lakes; plants = info.plants; veg_types = info.veg_types
	assert(heights.size() == N * N and biomes.size() == N * N and splat.size() == N * N * 5)
	loaded = true

func height(x: float, z: float) -> float:
	var fx := clampf(x / CELL, 0.0, N - 1.001)
	var fz := clampf(z / CELL, 0.0, N - 1.001)
	var i := int(fx)
	var j := int(fz)
	var u := fx - i
	var w := fz - j
	var k := j * N + i
	return lerpf(lerpf(heights[k], heights[k + 1], u), lerpf(heights[k + N], heights[k + N + 1], u), w)

func hcell(i: int, j: int) -> float:
	return heights[clampi(j, 0, N - 1) * N + clampi(i, 0, N - 1)]

func biome(x: float, z: float) -> int:
	return biomes[clampi(int(z / CELL + 0.5), 0, N - 1) * N + clampi(int(x / CELL + 0.5), 0, N - 1)]

func depth(x: float, z: float) -> float:
	return maxf(0.0, WATER_Y - height(x, z))

func playable(x: float, z: float) -> bool:
	var dx := x - 512.0
	var dz := z - 512.0
	return dx * dx * dx * dx + dz * dz * dz * dz < PLAY_LIMIT * PLAY_LIMIT * PLAY_LIMIT * PLAY_LIMIT

func thicket_at(x: float, z: float, margin := 0.0) -> int:
	for i in thickets.size():
		var t = thickets[i]
		var r: float = t.r + margin
		if (x - t.x) * (x - t.x) + (z - t.z) * (z - t.z) < r * r: return i
	return -1

func ground_pos(x: float, z: float) -> Vector3:
	return Vector3(x, height(x, z), z)

## true for dry land an animal can stand on
func dry(x: float, z: float) -> bool:
	return playable(x, z) and height(x, z) > 0.35 and biome(x, z) != ROCK

func random_dry_point(rng: RandomNumberGenerator, lo := 90.0, hi := 934.0) -> Vector2:
	for _i in 200:
		var x := rng.randf_range(lo, hi)
		var z := rng.randf_range(lo, hi)
		if dry(x, z) and biome(x, z) != SHORE: return Vector2(x, z)
	return Vector2(400, 520)

func dry_near(rng: RandomNumberGenerator, c: Vector2, rmin: float, rmax: float) -> Vector2:
	for _i in 40:
		var a := rng.randf() * TAU
		var r := rng.randf_range(rmin, rmax)
		var p := c + Vector2(cos(a), sin(a)) * r
		if dry(p.x, p.y): return p
	return c

func add_tree(x: float, z: float, radius: float) -> void:
	var key := int(x / 8.0) + int(z / 8.0) * 1000
	var arr: PackedFloat32Array = tree_grid.get(key, PackedFloat32Array())
	arr.append(x); arr.append(z); arr.append(radius)
	tree_grid[key] = arr

## pushes a position out of tree trunks; returns the corrected position
func collide_trees(p: Vector2, body: float) -> Vector2:
	var cx := int(p.x / 8.0)
	var cz := int(p.y / 8.0)
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var arr = tree_grid.get(cx + ox + (cz + oz) * 1000)
			if arr == null: continue
			var n: int = arr.size()
			var i := 0
			while i < n:
				var dx: float = p.x - arr[i]
				var dz: float = p.y - arr[i + 1]
				var rr: float = arr[i + 2] + body
				var d2 := dx * dx + dz * dz
				if d2 < rr * rr and d2 > 0.0001:
					var d := sqrt(d2)
					p.x += dx / d * (rr - d)
					p.y += dz / d * (rr - d)
				i += 3
	return p

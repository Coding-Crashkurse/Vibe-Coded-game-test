class_name Grid3D
extends RefCounted

const TILE_SIZE := 1.0
const LEVEL_STEP := 3.0     # Meter je Höhenebene NUR fürs Rendering (cell_to_world)

var tiles: Dictionary = {}  # Vector3i -> Tac3DTile
var size_x: int = 0
var size_z: int = 0
var min_level: int = 0
var max_level: int = 0
var _links: Dictionary = {} # Vector3i -> Array (symmetrische Ebenen-Übergänge)

var _bounds_dirty := true


func set_tile(c: Vector3i, t: Tac3DTile) -> void:
	tiles[c] = t
	if tiles.size() == 1:
		size_x = c.x + 1
		size_z = c.z + 1
		min_level = c.y
		max_level = c.y
	else:
		size_x = max(size_x, c.x + 1)
		size_z = max(size_z, c.z + 1)
		min_level = min(min_level, c.y)
		max_level = max(max_level, c.y)
	_bounds_dirty = true


func get_tile(c: Vector3i) -> Tac3DTile:
	return tiles.get(c, null)


func has_tile(c: Vector3i) -> bool:
	return tiles.has(c)


func is_walkable(c: Vector3i) -> bool:
	if not tiles.has(c):
		return false
	var t: Tac3DTile = tiles[c]
	return t != null and t.begehbar


func add_link(a: Vector3i, b: Vector3i) -> void:
	var la: Array = _links.get(a, [])
	if not la.has(b):
		la.append(b)
	_links[a] = la
	var lb: Array = _links.get(b, [])
	if not lb.has(a):
		lb.append(a)
	_links[b] = lb


## True, wenn die Zelle Endpunkt eines Ebenen-Links ist (Bruecke/Rampe/Treppe).
## Solche Zellen duerfen nie von blockierender Deko (Palmen) belegt werden —
## sonst stirbt der einzige Uebergang zwischen zwei Ebenen.
func has_link(c: Vector3i) -> bool:
	return _links.has(c)


func neighbors(c: Vector3i) -> Array:
	var result: Array = []
	var dirs := [
		Vector3i(1, 0, 0),
		Vector3i(-1, 0, 0),
		Vector3i(0, 0, 1),
		Vector3i(0, 0, -1),
	]
	for d in dirs:
		var dd: Vector3i = d
		var n := c + dd  # gleiche ebene (c.y bleibt), KEINE Diagonalen
		if is_walkable(n):
			result.append(n)
	var links: Array = _links.get(c, [])
	for l in links:
		var ll: Vector3i = l
		if is_walkable(ll):
			result.append(ll)
	return result


func all_cells() -> Array:
	return tiles.keys()


func cell_to_world(c: Vector3i) -> Vector3:
	return Vector3(
		(c.x + 0.5) * TILE_SIZE,
		c.y * LEVEL_STEP,
		(c.z + 0.5) * TILE_SIZE
	)


func world_to_cell(p: Vector3, ebene: int) -> Vector3i:
	return Vector3i(floori(p.x / TILE_SIZE), ebene, floori(p.z / TILE_SIZE))


func bounds_world() -> AABB:
	if tiles.is_empty():
		return AABB()
	var first := true
	var mn := Vector3.ZERO
	var mx := Vector3.ZERO
	for k in tiles.keys():
		var c: Vector3i = k
		var w := cell_to_world(c)
		if first:
			mn = w
			mx = w
			first = false
		else:
			mn.x = min(mn.x, w.x)
			mn.y = min(mn.y, w.y)
			mn.z = min(mn.z, w.z)
			mx.x = max(mx.x, w.x)
			mx.y = max(mx.y, w.y)
			mx.z = max(mx.z, w.z)
	# halbe Zelle Rand, damit die Zellen komplett innerhalb der AABB liegen
	var half := Vector3(TILE_SIZE * 0.5, 0.0, TILE_SIZE * 0.5)
	mn -= half
	mx += half
	_bounds_dirty = false
	return AABB(mn, mx - mn)

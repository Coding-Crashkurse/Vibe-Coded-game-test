class_name Pathfinder3D
extends RefCounted

# AStar3D wrapper (fix S9: FLAT cost metric, y always 0).
# astar MUST stay public — the harness calls astar.are_points_connected() directly.

var astar := AStar3D.new()
var grid: Grid3D
var _id_of: Dictionary = {}   # Vector3i -> int
var _cell_of: Dictionary = {} # int -> Vector3i


func build(g: Grid3D) -> void:
	grid = g
	astar = AStar3D.new()
	_id_of.clear()
	_cell_of.clear()
	if grid == null:
		return

	# 1) Points: walkable cells only, consecutive IDs.
	var next_id := 0
	for k in grid.all_cells():
		var c: Vector3i = k
		if not grid.is_walkable(c):
			continue
		var tile: Tac3DTile = grid.get_tile(c)
		if tile == null:
			continue
		var id := next_id
		next_id += 1
		# Fix S9: position is FLAT (y = 0), render height is NOT factored in.
		# A level change via link thus costs ~1 distance unit instead of LEVEL_STEP.
		astar.add_point(id, Vector3(c.x + 0.5, 0.0, c.z + 0.5), tile.weight)
		_id_of[c] = id
		_cell_of[id] = c

	# 2) Edges: bidirectional to all walkable neighbours (including links).
	for k in _id_of.keys():
		var c2: Vector3i = k
		var cid: int = _id_of[c2]
		for n in grid.neighbors(c2):
			var nn: Vector3i = n
			if not _id_of.has(nn):
				continue
			var nid: int = _id_of[nn]
			astar.connect_points(cid, nid, true)


func has_point(c: Vector3i) -> bool:
	return _id_of.has(c)


func point_id(c: Vector3i) -> int:
	return _id_of.get(c, -1)


func path_cells(from: Vector3i, to: Vector3i) -> Array:
	var result: Array = []
	if not _id_of.has(from) or not _id_of.has(to):
		return result
	var from_id: int = _id_of[from]
	var to_id: int = _id_of[to]
	if astar.is_point_disabled(from_id) or astar.is_point_disabled(to_id):
		return result
	var ids := astar.get_id_path(from_id, to_id)
	for pid in ids:
		var pi: int = pid
		if _cell_of.has(pi):
			var cell: Vector3i = _cell_of[pi]
			result.append(cell)
	return result


func path_world(from: Vector3i, to: Vector3i) -> Array:
	var result: Array = []
	if grid == null:
		return result
	for c in path_cells(from, to):
		var cc: Vector3i = c
		result.append(grid.cell_to_world(cc))
	return result


func reachable(from: Vector3i, to: Vector3i) -> bool:
	return not path_cells(from, to).is_empty()


func path_cost(from: Vector3i, to: Vector3i) -> float:
	var cells := path_cells(from, to)
	if cells.is_empty():
		return -1.0
	if grid == null:
		return -1.0
	# Sum of distances along the cells × weight of the destination step (flat metric, y=0).
	var cost := 0.0
	for i in range(1, cells.size()):
		var prev: Vector3i = cells[i - 1]
		var cur: Vector3i = cells[i]
		var flat_prev := Vector3(prev.x + 0.5, 0.0, prev.z + 0.5)
		var flat_cur := Vector3(cur.x + 0.5, 0.0, cur.z + 0.5)
		var step := flat_prev.distance_to(flat_cur)
		var tile: Tac3DTile = grid.get_tile(cur)
		var w := 1.0
		if tile != null:
			w = tile.weight
		cost += step * w
	return cost


func set_cell_blocked(c: Vector3i, blocked: bool) -> void:
	if not _id_of.has(c):
		return
	var id: int = _id_of[c]
	astar.set_point_disabled(id, blocked)


func set_move_type_enabled(mt: Tac3DTile.Move, enabled: bool) -> void:
	if grid == null:
		return
	for k in _id_of.keys():
		var c: Vector3i = k
		var tile: Tac3DTile = grid.get_tile(c)
		if tile == null:
			continue
		if tile.move_type == mt:
			var id: int = _id_of[c]
			astar.set_point_disabled(id, not enabled)

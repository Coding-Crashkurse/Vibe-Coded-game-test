class_name CursorView3D
extends Node3D

# 3D cursor feedback for the interactive 3D combat (p3_1 §2.8).
# Three representations, 1 draw call each:
#   _path_mmi : MultiMeshInstance3D — movement path (thin boxes per cell)
#   _marker   : MeshInstance3D      — target marker (torus, flat in XZ)
#   _disc     : MeshInstance3D      — grenade radius (flat cylinder)
# All materials UNSHADED + TRANSPARENCY_ALPHA (iso look, visible alpha).

const Y := 0.22   # just above the 0.2 box (top edge at +0.1) -> no Z-fighting

# Path colours (vertex colour in the MultiMesh)
const COL_MOVE := Color(0.95, 0.72, 0.25, 0.75)   # amber — within AP range
const COL_FAR := Color(0.58, 0.58, 0.62, 0.55)    # grey — out of range

# Target marker colours per context
const COL_SHOOT := Color(0.92, 0.26, 0.20, 0.85)  # red
const COL_SEARCH := Color(0.32, 0.82, 0.36, 0.85) # green
const COL_TARGET_MOVE := Color(0.95, 0.72, 0.25, 0.85) # amber
const COL_BLOCK := Color(0.96, 0.52, 0.15, 0.85)  # orange (blocked)

# Grenade radius colours
const COL_NADE_OK := Color(0.96, 0.55, 0.15, 0.40)  # orange (valid)
const COL_NADE_BAD := Color(0.90, 0.22, 0.18, 0.40) # red (invalid)

var grid: Grid3D = null

var _path_mmi: MultiMeshInstance3D = null
var _marker: MeshInstance3D = null
var _disc: MeshInstance3D = null
var _marker_mat: StandardMaterial3D = null
var _disc_mat: StandardMaterial3D = null


func setup(g: Grid3D) -> void:
	grid = g

	# --- Path MultiMesh: small flat dot discs along the SMOOTHED curve
	#     (instead of large tile boxes -> no angular staircase look) ---
	var box := CylinderMesh.new()
	box.top_radius = 0.11
	box.bottom_radius = 0.11
	box.height = 0.035
	box.radial_segments = 12
	var path_mat := StandardMaterial3D.new()
	path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	path_mat.vertex_color_use_as_albedo = true
	path_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = path_mat

	# ORDERING TRAP (S7): transform_format + use_colors + mesh FIRST, then instance_count.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = 0

	_path_mmi = MultiMeshInstance3D.new()
	_path_mmi.name = "PathHighlight"
	_path_mmi.multimesh = mm
	# A MultiMesh is not auto-culled — generous AABB.
	if grid != null:
		var b := grid.bounds_world()
		var pad := Vector3(4.0, 8.0, 4.0)
		_path_mmi.custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)
	add_child(_path_mmi)

	# --- Target marker: TorusMesh, lies flat in XZ ---
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.46
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker_mat.albedo_color = COL_TARGET_MOVE
	torus.material = _marker_mat
	_marker = MeshInstance3D.new()
	_marker.name = "TargetMarker"
	_marker.mesh = torus
	_marker.visible = false
	add_child(_marker)

	# --- Granaten-Radius: flacher CylinderMesh ---
	var cyl := CylinderMesh.new()
	cyl.height = 0.02
	cyl.top_radius = 0.5
	cyl.bottom_radius = 0.5
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.albedo_color = COL_NADE_OK
	cyl.material = _disc_mat
	_disc = MeshInstance3D.new()
	_disc.name = "GrenadeDisc"
	_disc.mesh = cyl
	_disc.visible = false
	add_child(_disc)


## Movement path: smoothed dot trail (Chaikin corner cutting, evenly distributed
## discs) instead of an angular cell-to-cell chain. Amber within AP range
## (fraction of the route up to cell `afford`), otherwise grey. Y=0.22.
func show_path(cells: Array, afford: int) -> void:
	if _path_mmi == null:
		return
	_disc.visible = false
	_marker.visible = false
	var mm := _path_mmi.multimesh
	if cells.size() < 2:
		mm.instance_count = 0
		return
	# 1) cell centres -> world points
	var pts: Array = []
	for c in cells:
		var cc: Vector3i = c
		pts.append(grid.cell_to_world(cc) + Vector3(0.0, Y, 0.0))
	# Affordable fraction of the route (afford = prefix size INCLUDING the start cell)
	var afford_frac := clampf(float(afford - 1) / float(cells.size() - 1), 0.0, 1.0)
	# 2) cut corners twice -> soft curve
	pts = _chaikin(_chaikin(pts))
	# 3) place points at fixed intervals along the curve
	var total := 0.0
	for i in range(1, pts.size()):
		total += (pts[i] as Vector3).distance_to(pts[i - 1])
	if total < 0.05:
		mm.instance_count = 0
		return
	var spacing := 0.42
	var count := clampi(int(total / spacing) + 1, 2, 400)
	mm.instance_count = count
	var step := total / float(count - 1)
	var seg := 1
	var seg_start := 0.0
	var seg_len: float = (pts[1] as Vector3).distance_to(pts[0])
	for k in count:
		var s := minf(step * float(k), total)
		while s > seg_start + seg_len and seg < pts.size() - 1:
			seg_start += seg_len
			seg += 1
			seg_len = (pts[seg] as Vector3).distance_to(pts[seg - 1])
		var t := 0.0 if seg_len < 0.0001 else (s - seg_start) / seg_len
		var pos: Vector3 = (pts[seg - 1] as Vector3).lerp(pts[seg], t)
		mm.set_instance_transform(k, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(k, COL_MOVE if s / total <= afford_frac + 0.001 else COL_FAR)


## Chaikin corner cutting: replaces every corner with the 25 %/75 % points of the
## neighbouring segments (endpoints stay). Straight stretches stay straight.
func _chaikin(pts: Array) -> Array:
	if pts.size() < 3:
		return pts
	var out: Array = [pts[0]]
	for i in range(0, pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		if i > 0:
			out.append(a.lerp(b, 0.25))
		if i < pts.size() - 2:
			out.append(a.lerp(b, 0.75))
	out.append(pts[pts.size() - 1])
	return out


## Target marker on a cell. kind: "shoot"|"search"|"move"|"block".
## For kind != "move" the movement path is cleared (shot/search show no path).
func show_target(cell: Vector3i, kind: String) -> void:
	if _marker == null:
		return
	_disc.visible = false
	if kind != "move" and _path_mmi != null:
		_path_mmi.multimesh.instance_count = 0
	match kind:
		"shoot":
			_marker_mat.albedo_color = COL_SHOOT
		"search":
			_marker_mat.albedo_color = COL_SEARCH
		"block":
			_marker_mat.albedo_color = COL_BLOCK
		_:
			_marker_mat.albedo_color = COL_TARGET_MOVE
	_marker.transform = Transform3D(Basis.IDENTITY, grid.cell_to_world(cell) + Vector3(0.0, Y, 0.0))
	_marker.visible = true


## Grenade radius around the target cell. valid -> orange, otherwise red.
func show_grenade(from_cell: Vector3i, target: Vector3i, radius: float, valid: bool) -> void:
	if _disc == null:
		return
	_marker.visible = false
	if _path_mmi != null:
		_path_mmi.multimesh.instance_count = 0
	_disc_mat.albedo_color = COL_NADE_OK if valid else COL_NADE_BAD
	# The base cylinder has radius 0.5 (diameter 1) -> scale = radius*2 yields world radius = radius.
	var b := Basis.IDENTITY.scaled(Vector3(radius * 2.0, 1.0, radius * 2.0))
	_disc.transform = Transform3D(b, grid.cell_to_world(target) + Vector3(0.0, Y, 0.0))
	_disc.visible = true


## Alles ausblenden.
func clear() -> void:
	if _path_mmi != null:
		_path_mmi.multimesh.instance_count = 0
	if _marker != null:
		_marker.visible = false
	if _disc != null:
		_disc.visible = false

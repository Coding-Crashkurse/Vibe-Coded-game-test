class_name Picker3D
extends RefCounted

const NONE := Vector3i(-999, -999, -999)

var grid: Grid3D
var cam: Camera3D
var active_level := 0


func set_active_level(l: int) -> void:
	active_level = l


func cell_under_mouse(vp: Viewport) -> Vector3i:
	if cam == null or grid == null or vp == null:
		return NONE
	var mouse := vp.get_mouse_position()
	var from := cam.project_ray_origin(mouse)
	var dir := cam.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, active_level * Grid3D.LEVEL_STEP)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return NONE
	var c := grid.world_to_cell(hit, active_level)
	return c if grid.has_tile(c) else NONE

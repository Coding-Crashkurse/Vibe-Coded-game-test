class_name CursorView3D
extends Node3D

# 3D-Cursor-Feedback fuer den interaktiven 3D-Kampf (p3_1 §2.8).
# Drei Darstellungen, je 1 Draw-Call:
#   _path_mmi : MultiMeshInstance3D — Laufpfad (duenne Boxen je Zelle)
#   _marker   : MeshInstance3D      — Ziel-Marker (Torus, flach in XZ)
#   _disc     : MeshInstance3D      — Granaten-Radius (flacher Zylinder)
# Alle Materialien UNSHADED + TRANSPARENCY_ALPHA (Iso-Look, sichtbares Alpha).

const Y := 0.22   # knapp ueber der 0,2-Box (Oberkante bei +0.1) -> kein Z-Fighting

# Pfad-Farben (Vertex-Farbe im MultiMesh)
const COL_MOVE := Color(0.95, 0.72, 0.25, 0.75)   # amber — innerhalb AP-Reichweite
const COL_FAR := Color(0.58, 0.58, 0.62, 0.55)    # grau — ausserhalb Reichweite

# Ziel-Marker-Farben je Kontext
const COL_SHOOT := Color(0.92, 0.26, 0.20, 0.85)  # rot
const COL_SEARCH := Color(0.32, 0.82, 0.36, 0.85) # gruen
const COL_TARGET_MOVE := Color(0.95, 0.72, 0.25, 0.85) # amber
const COL_BLOCK := Color(0.96, 0.52, 0.15, 0.85)  # orange (blockiert)

# Granaten-Radius-Farben
const COL_NADE_OK := Color(0.96, 0.55, 0.15, 0.40)  # orange (gueltig)
const COL_NADE_BAD := Color(0.90, 0.22, 0.18, 0.40) # rot (ungueltig)

var grid: Grid3D = null

var _path_mmi: MultiMeshInstance3D = null
var _marker: MeshInstance3D = null
var _disc: MeshInstance3D = null
var _marker_mat: StandardMaterial3D = null
var _disc_mat: StandardMaterial3D = null


func setup(g: Grid3D) -> void:
	grid = g

	# --- Pfad-MultiMesh: duenne BoxMesh, Vertex-Farbe als Albedo ---
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.04, 0.8)
	var path_mat := StandardMaterial3D.new()
	path_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	path_mat.vertex_color_use_as_albedo = true
	path_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material = path_mat

	# REIHENFOLGE-FALLE (S7): transform_format + use_colors + mesh ZUERST, dann instance_count.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = 0

	_path_mmi = MultiMeshInstance3D.new()
	_path_mmi.name = "PathHighlight"
	_path_mmi.multimesh = mm
	# MultiMesh wird nicht auto-gecullt — grosszuegige AABB.
	if grid != null:
		var b := grid.bounds_world()
		var pad := Vector3(4.0, 8.0, 4.0)
		_path_mmi.custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)
	add_child(_path_mmi)

	# --- Ziel-Marker: TorusMesh, liegt flach in XZ ---
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


## Laufpfad: Amber innerhalb Reichweite (i < afford), sonst Grau. Y=0.22.
func show_path(cells: Array, afford: int) -> void:
	if _path_mmi == null:
		return
	_disc.visible = false
	_marker.visible = false
	var mm := _path_mmi.multimesh
	mm.instance_count = maxi(0, cells.size() - 1)
	for i in range(1, cells.size()):
		var c: Vector3i = cells[i]
		var pos := grid.cell_to_world(c) + Vector3(0.0, Y, 0.0)
		mm.set_instance_transform(i - 1, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(i - 1, COL_MOVE if i < afford else COL_FAR)


## Ziel-Marker an eine Zelle. kind: "shoot"|"search"|"move"|"block".
## Bei kind != "move" wird der Laufpfad geloescht (nur Schuss/Suche zeigt keinen Pfad).
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


## Granaten-Radius um die Zielzelle. valid -> orange, sonst rot.
func show_grenade(from_cell: Vector3i, target: Vector3i, radius: float, valid: bool) -> void:
	if _disc == null:
		return
	_marker.visible = false
	if _path_mmi != null:
		_path_mmi.multimesh.instance_count = 0
	_disc_mat.albedo_color = COL_NADE_OK if valid else COL_NADE_BAD
	# Basis-Zylinder hat Radius 0.5 (Durchmesser 1) -> scale = radius*2 ergibt Weltradius = radius.
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

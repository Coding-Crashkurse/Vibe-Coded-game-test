class_name Tac3DUnit
extends Unit3D
## Kampf-Einheit in 3D. Haelt denselben Runtime-Dict wie BattleUnit (2D), plus
## 3D-Node. cell/grid/fast/move_finished/follow_path/set_cell von Unit3D geerbt.
## K1: Team-Identitaet ueber einen EIGENEN Marker-Kind-Node (kleine unshaded
## Kugel). unit3d.gd wird NICHT angefasst. set_seen ueber self.visible.

var data: Dictionary = {}
var is_merc := false
var alive := true
var seen := true
var interrupt_used := false
var home := Vector3i.ZERO        # Leine-Anker (Boss/Elite)
var ap := 0
var ap_max := 0

const COL_MERC := Color(0.30, 0.75, 0.95)
const COL_ENEMY := Color(0.90, 0.28, 0.24)
const COL_BOSS := Color(1.00, 0.82, 0.30)
const COL_DEAD := Color(0.42, 0.35, 0.32)

var _marker: MeshInstance3D = null
var _marker_mat: StandardMaterial3D = null


func setup_combat(g: Grid3D, d: Dictionary, merc: bool, start: Vector3i) -> void:
	data = d
	is_merc = merc
	# Integer-Division bewahren (Balance identisch zu BattleUnit.setup): 20 + agi/5
	ap_max = 20 + int(d["agi"]) / 5
	ap = ap_max
	# Body (moderne Söldner-GLB nach Rolle) + set_cell kommen aus Unit3D.
	# Rolle -> Modell: Boss=BusinessMan, Söldner=SWAT, sonst Gegner=Casual.
	var cid := "boss" if String(d.get("type", "")) == "boss" else ("merc" if merc else "enemy")
	super.setup(g, start, cid)
	# K1: eigener Team-Marker als Kind-Node (kein Zugriff auf Unit3D._mesh/-material).
	_marker = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	_marker.mesh = sphere
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = _marker_mat
	_marker.position = Vector3(0, 1.7, 0)
	add_child(_marker)
	set_tint(team_color())


func set_tint(col: Color) -> void:
	# Faerbt AUSSCHLIESSLICH das eigene Marker-Material (K1).
	if _marker_mat != null:
		_marker_mat.albedo_color = col


func team_color() -> Color:
	if is_merc:
		return COL_MERC
	if String(data.get("type", "")) == "boss":
		return COL_BOSS
	return COL_ENEMY


func hp() -> int:
	return int(data["hp"])


func hp_max() -> int:
	return int(data["hp_max"])


func hurt(dmg: int) -> void:
	data["hp"] = max(0, hp() - dmg)
	if hp() <= 0:
		alive = false
		data["alive"] = false


func die_visual() -> void:
	set_tint(COL_DEAD)
	# leicht absenken (Leiche liegt tiefer)
	position.y -= 0.2


func set_seen(v: bool) -> void:
	seen = v
	# Sichtbarkeit ueber Node3D-Built-in (versteckt Body + Marker gemeinsam, K1).
	# Soeldner und Leichen bleiben immer sichtbar; Gegner nur wenn gesehen.
	self.visible = is_merc or not alive or v


func display_name() -> String:
	if data.has("nick"):
		return String(data["nick"])
	return String(data["name"])


func flat() -> Vector2:
	return Tac3DVision.flat(cell)


func level_up_marks() -> void:
	# 1:1 aus tactical.gd:883 (Stufenaufstieg des Killers).
	data["marks"] = mini(95, int(data["marks"]) + 2)

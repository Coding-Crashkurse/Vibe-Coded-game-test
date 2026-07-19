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
	# #3: Team-Identitaet ueber einen flachen FARBRING am BODEN (statt Blob ueber dem
	# Kopf). Liest sich wie XCOM/JA3 und stoert die Silhouette nicht. Weiter EIGENER
	# Kind-Node -> Unit3D._mesh/-material bleiben unberuehrt (K1).
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.40
	ring.outer_radius = 0.52
	ring.rings = 4
	ring.ring_segments = 20   # TorusMesh liegt flach in XZ (Achse = Y) -> Ring auf dem Boden
	_marker.mesh = ring
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = _marker_mat
	_marker.position = Vector3(0, 0.07, 0)   # knapp ueber der Kachel-Oberkante
	add_child(_marker)
	set_tint(team_color())


func set_tint(col: Color) -> void:
	# Faerbt AUSSCHLIESSLICH das eigene Marker-Material (K1). Leicht transparenter Boden-Ring.
	if _marker_mat != null:
		_marker_mat.albedo_color = Color(col.r, col.g, col.b, 0.85)


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

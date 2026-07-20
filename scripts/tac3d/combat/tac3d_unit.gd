class_name Tac3DUnit
extends Unit3D
## Combat unit in 3D. Holds the same runtime dict as BattleUnit (2D), plus the
## 3D node. cell/grid/fast/move_finished/follow_path/set_cell inherited from Unit3D.
## K1: team identity via a DEDICATED marker child node (small unshaded sphere).
## unit3d.gd is NOT touched. set_seen goes through self.visible.

var data: Dictionary = {}
var is_merc := false
var alive := true
var seen := true
var interrupt_used := false
var home := Vector3i.ZERO        # leash anchor (boss/elite)
var ap := 0
var ap_max := 0
var stance := "stand"            # posture: stand/crouch/prone (Db.STANCES)
var cripple_rounds := 0          # leg hit: remaining rounds with doubled step cost

# Db weapon id -> visible 3D model (Assets3D.WEAPONS). Pistols show the pistol,
# shotguns the long gun (rifle.glb = the best available CC0 approximation).
const WEAPON_MODEL := {
	"p9": "pistol", "k45": "pistol",
	"flinte": "rifle", "drachenmaul": "rifle", "svd": "rifle",
}

const COL_MERC := Color(0.30, 0.75, 0.95)
const COL_ENEMY := Color(0.90, 0.28, 0.24)
const COL_BOSS := Color(1.00, 0.82, 0.30)
const COL_DEAD := Color(0.42, 0.35, 0.32)

var _marker: MeshInstance3D = null
var _marker_mat: StandardMaterial3D = null
var _group_sel := false          # part of the mouse multi-selection -> highlight ring


func setup_combat(g: Grid3D, d: Dictionary, merc: bool, start: Vector3i) -> void:
	data = d
	is_merc = merc
	# preserve integer division (balance identical to BattleUnit.setup): 20 + agi/5
	ap_max = 20 + int(d["agi"]) / 5
	ap = ap_max
	# Body (modern merc GLB by role) + set_cell come from Unit3D.
	# Role -> model: boss=BusinessMan, merc=SWAT, otherwise enemy=Casual.
	var cid := "boss" if String(d.get("type", "")) == "boss" else ("merc" if merc else "enemy")
	# SPEC §4.1 step 4: mercs get their OWN body + their uniform from the Db
	# (Db.MERCS[...]["model"/"uniform"], Tobias Rook from Db.OTTO).
	# If the entry is missing (enemy, boss, old save game), EVERYTHING stays as
	# before: role model, no tinting.
	var look := Db.merc_look(String(d.get("id", "")))
	if look.has("model"):
		cid = String(look["model"])
	super.setup(g, start, cid)
	if look.has("uniform"):
		set_uniform_color(look["uniform"])
	# Visible weapon = the actually equipped sidearm (instead of a blanket rifle).
	refresh_weapon()
	# #3: team identity via a flat COLOUR RING on the GROUND (instead of a blob above
	# the head). Reads like XCOM/JA3 and does not disturb the silhouette. Still a
	# DEDICATED child node -> Unit3D._mesh/material stay untouched (K1).
	_marker = MeshInstance3D.new()
	var ring := TorusMesh.new()
	ring.inner_radius = 0.40
	ring.outer_radius = 0.52
	ring.rings = 4
	ring.ring_segments = 20   # TorusMesh lies flat in XZ (axis = Y) -> ring on the ground
	_marker.mesh = ring
	_marker_mat = StandardMaterial3D.new()
	_marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = _marker_mat
	_marker.position = Vector3(0, 0.07, 0)   # just above the tile's top edge
	add_child(_marker)
	set_tint(team_color())


## Mounts the 3D model of the CURRENTLY equipped sidearm (data["weapon"]).
## Call again after every inventory swap; unknown ids show the rifle.
## The weapon id is PASSED THROUGH so Unit3D can fetch the fit from
## Db.WEAPONS[...]["attach_offset"] (SPEC §4.1 step 3).
func refresh_weapon() -> void:
	var wid := String(data.get("weapon", ""))
	equip_weapon(String(WEAPON_MODEL.get(wid, "rifle")), wid)


func set_tint(col: Color) -> void:
	# Tints EXCLUSIVELY its own marker material (K1). Slightly transparent ground ring.
	if _marker_mat != null:
		if _group_sel:
			var c := col.lightened(0.35)
			_marker_mat.albedo_color = Color(c.r, c.g, c.b, 1.0)
		else:
			_marker_mat.albedo_color = Color(col.r, col.g, col.b, 0.85)


## Mouse multi-selection: highlights the ground ring (brighter, opaque, slightly larger).
func set_group_highlight(on: bool) -> void:
	if _group_sel == on:
		return
	_group_sel = on
	if _marker != null:
		_marker.scale = Vector3.ONE * (1.18 if on else 1.0)
	set_tint(team_color() if alive else COL_DEAD)


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
	# lower slightly (a corpse lies deeper)
	position.y -= 0.2


func set_seen(v: bool) -> void:
	seen = v
	# Visibility via the Node3D built-in (hides body + marker together, K1).
	# Mercs and corpses always stay visible; enemies only when seen.
	self.visible = is_merc or not alive or v


func display_name() -> String:
	if data.has("nick"):
		return String(data["nick"])
	return String(data["name"])


func flat() -> Vector2:
	return Tac3DVision.flat(cell)


func level_up_marks() -> void:
	# 1:1 from tactical.gd:883 (the killer's level-up).
	data["marks"] = mini(95, int(data["marks"]) + 2)

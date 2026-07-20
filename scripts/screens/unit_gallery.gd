extends Control
## Merc gallery (SPEC v5 §4.1 step 5) — a review screen, not a game screen.
##
## Shows ALL NINE hired-able mercs side by side as real 3D models with their
## actual sidearm in hand, so body + uniform colour can be compared at a glance:
## if two mercs are hard to tell apart HERE, they are impossible to tell apart
## at tactical zoom. Also lets the mandatory animation set be stepped through,
## which is the only honest way to see which clips are real and which are
## approximations (see Unit3D._CLIPS / Unit3D.APPROX_CLIPS).
##
## Technique: one SubViewport per merc with its own World3D (own_world_3d), a
## DirectionalLight3D + ambient Environment inside each (gl_compatibility needs
## light, otherwise the models render pitch black), and an orthographic camera.
## Everything runs through Unit3D, so the capsule fallback applies when a GLB is
## missing — the screen never crashes on missing assets.
##
## The bodies come from the PREFABS (res://scenes/units/merc_<id>.tscn) — the
## gallery reviews exactly what the tactical map spawns, not a lookalike built
## just for this screen. A missing prefab silently falls back to the direct
## Assets3D path and the card says so.
##
## Scene wrapper: res://scenes/unit_gallery.tscn (a bare Control with this
## script). Main.goto("unit_gallery") instantiates the script directly and never
## needs the .tscn; the file exists so the screen can be opened standalone for
## review screenshots.

## Animation buttons — only clips that REALLY exist in the rig.
## reload and throw used to sit here as approximations (a static gun-hold pose
## and a sword swing). They were removed on purpose: rather no animation than a
## misleading one. See Unit3D.MISSING_CLIPS.
const ANIM_BUTTONS := [
	{"key": "idle", "label": "IDLE"},
	{"key": "walk", "label": "WALK"},
	{"key": "run", "label": "RUN"},
	{"key": "aim", "label": "AIM"},
	{"key": "shoot", "label": "SHOOT"},
	{"key": "loot", "label": "LOOT"},
	{"key": "hit", "label": "HIT"},
	{"key": "death", "label": "DEATH"},
]

const CARD_W := 150.0
const CARD_H := 330.0

var _units: Array = []          # Unit3D instances, one per merc
var _current := "idle"
var _status: Label = null


func _main() -> Node:
	return get_parent()


func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	var head := UiTheme.header("MERC GALLERY", 34)
	col.add_child(head)
	col.add_child(UiTheme.lbl("Body model, uniform colour and sidearm of every A.I.M. merc — side by side.", 15, UiTheme.COL_DIM))

	# --- the nine model cards (horizontally scrollable, never clipped) --------
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(row)

	for entry in Db.MERCS:
		var md: Dictionary = entry
		_build_card(row, md)

	# --- animation controls ---------------------------------------------------
	col.add_child(UiTheme.lbl(
		"Every button above plays a REAL clip. Missing from the rig entirely: reload, throw"
		+ " and crouch/prone — reloading and throwing simply play no animation, and crouching"
		+ " is faked by squashing the mesh.", 13, UiTheme.COL_DIM))

	var anim_row := HBoxContainer.new()
	anim_row.add_theme_constant_override("separation", 6)
	col.add_child(anim_row)
	for cfg in ANIM_BUTTONS:
		var c: Dictionary = cfg
		var key := String(c["key"])
		var b := UiTheme.btn(String(c["label"]), func() -> void: _set_anim(key), 14)
		b.custom_minimum_size = Vector2(96, 34)
		anim_row.add_child(b)

	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	col.add_child(foot)
	_status = UiTheme.lbl("Playing: idle", 15, UiTheme.COL_AMBER)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_status)
	var back := UiTheme.btn("BACK", _go_back, 16)
	back.custom_minimum_size = Vector2(160, 38)
	foot.add_child(back)


## BACK only leads anywhere inside the Main screen stack. When
## res://scenes/unit_gallery.tscn is opened standalone (review screenshot) there
## is no Main parent — the button is then inert instead of erroring.
func _go_back() -> void:
	var m := _main()
	if m != null and m.has_method("goto"):
		m.goto("title")


## One card: 3D preview on top, identity below. Parents are attached to the tree
## BEFORE the Unit3D is created — Unit3D.setup() reads global_position.
func _build_card(row: HBoxContainer, md: Dictionary) -> void:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 2)
	card.custom_minimum_size = Vector2(CARD_W, 0)
	row.add_child(card)

	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	svc.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.add_child(svc)

	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)

	var world := Node3D.new()
	sv.add_child(world)

	# gl_compatibility: without light (or unshaded materials) the GLB is black.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-32.0, 38.0, 0.0)
	light.light_energy = 1.2
	world.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.70, 0.75, 0.68)
	e.ambient_light_energy = 0.9
	env.environment = e
	world.add_child(env)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.5                       # vertical extent; merc is ~1.85 units tall
	cam.position = Vector3(0.0, 0.95, 4.0)
	world.add_child(cam)
	cam.current = true

	# 1x1 m footprint plate = one tactical tile. Makes the SCALE claim checkable
	# at a glance: every merc has to fit the same cell (SPEC §4.1 step 5).
	var plate := MeshInstance3D.new()
	var plate_mesh := PlaneMesh.new()
	plate_mesh.size = Vector2(1.0, 1.0)
	var plate_mat := StandardMaterial3D.new()
	plate_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate_mat.albedo_color = Color(0.24, 0.19, 0.12)
	plate_mesh.material = plate_mat
	plate.mesh = plate_mesh
	plate.position = Vector3(0.0, 0.004, 0.0)
	world.add_child(plate)

	# --- the merc itself ------------------------------------------------------
	var mid := String(md.get("id", ""))
	var look := Db.merc_look(mid)
	var model_id := String(look.get("model", "merc"))     # fallback = old behaviour
	var wid := String(md.get("weapon", ""))
	var wmodel := String(Tac3DUnit.WEAPON_MODEL.get(wid, "rifle"))

	var u := Unit3D.new()
	world.add_child(u)
	# grid null = free-standing; prefab_id = merc id -> the prefab supplies body,
	# uniform colour and weapon. Missing prefab -> model_id path, unchanged.
	u.setup(null, Vector3i.ZERO, model_id, mid)
	# Set again from the Db: idempotent (Unit3D remembers the original albedo) and
	# it keeps the card correct even when the prefab is absent or out of date.
	if look.has("uniform"):
		u.set_uniform_color(look["uniform"])
	u.equip_weapon(wmodel, wid)
	u.face_toward(Vector3(1.4, 0.95, 4.0), true)          # slight 3/4 view toward the camera
	u.play_anim(_current)
	_units.append(u)

	# --- identity ------------------------------------------------------------
	var nick := UiTheme.header("\"%s\"" % String(md.get("nick", "?")), 19)
	nick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(nick)

	var name_lbl := UiTheme.lbl(String(md.get("name", "?")), 13, UiTheme.COL_TEXT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(name_lbl)

	# Colour swatch = the exact uniform colour, so two similar hues are obvious.
	var swatch := ColorRect.new()
	swatch.color = look.get("uniform", Color(0.5, 0.5, 0.5))
	swatch.custom_minimum_size = Vector2(0, 6)
	swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(swatch)

	var wshort := "-"
	if Db.WEAPONS.has(wid):
		wshort = String(Db.WEAPONS[wid]["short"])
	# Names the SOURCE of the body, so a silently missing prefab is visible here
	# instead of only in the code.
	var src := "prefab" if Assets3D.unit_prefab(mid) != null else "direct"
	var info := UiTheme.lbl("%s · %s · %s" % [model_id, wshort, src], 12, UiTheme.COL_DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(info)


## Plays one logical clip on all nine models at once. One-shot clips (shoot/hit/
## throw/loot) return to idle by themselves; DEATH stays down until another
## button is pressed. No-op-safe for capsule fallbacks (play_anim does nothing).
func _set_anim(which: String) -> void:
	_current = which
	for entry in _units:
		var u: Unit3D = entry
		if is_instance_valid(u):
			u.play_anim(which)
	if _status != null:
		var note := ""
		if which in Unit3D.APPROX_CLIPS:
			note = "   (approximation — no real clip in the rig)"
		elif which in Unit3D.MISSING_CLIPS:
			note = "   (no clip in the rig — falls back to idle)"
		_status.text = "Playing: %s%s" % [which, note]

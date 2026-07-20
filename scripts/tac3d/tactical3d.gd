extends Node3D
# Orchestrator screen of the 3D tactics layer (phase 1). NO class_name (contract §1/§10).
# Builds container nodes FIRST (fix K2), then grid/pathfinder/view/unit,
# emits map_ready deferred (the harness awaits it after add_child).

signal map_ready

var grid: Grid3D
var pathfinder: Pathfinder3D
var rig: CameraRig3D
var ground: GroundView3D
var picker: Picker3D
var unit: Unit3D
var meta: Dictionary
var fast := false

const PAN_SPEED := 12.0

var _world_root: Node3D
var _props_root: Node3D
var _units_root: Node3D
var _hud: CanvasLayer
var _hud_root: Control
var _level_label: Label
var _active_level := 0


func _main() -> Node:
	return get_parent()


func _ready() -> void:
	# 1) fast flag from the parent (main.gd/harness). Null guard (fix S8).
	var m := _main()
	if m != null and m.get("fast") == true:
		fast = true

	# 2) Step 0 (fix K2): FIRST create + name all container nodes,
	#    BEFORE anything is hung inside them.
	rig = CameraRig3D.new()
	rig.name = "CameraRig"
	add_child(rig)

	_world_root = Node3D.new()
	_world_root.name = "WorldRoot"
	add_child(_world_root)

	_props_root = Node3D.new()
	_props_root.name = "PropsRoot"
	add_child(_props_root)

	_units_root = Node3D.new()
	_units_root.name = "UnitsRoot"
	add_child(_units_root)

	_hud = CanvasLayer.new()
	_hud.name = "Hud"
	add_child(_hud)

	_hud_root = Control.new()
	_hud_root.name = "HudRoot"
	_hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(_hud_root)

	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.position = Vector2(12.0, 12.0)
	_hud_root.add_child(_level_label)

	# 3) Map + grid (the truth).
	meta = TestMap3D.build()
	grid = meta["grid"]

	# 4) Hang GroundView under WorldRoot, then build — BEFORE the pathfinder:
	#    Scenery3D marks palm cells as non-walkable (object collision), and the
	#    pathfinder must already see those blocks when it is built.
	ground = GroundView3D.new()
	ground.name = "GroundView"
	_world_root.add_child(ground)
	ground.build(grid)

	# 5) Pathfinder over the grid (including palm blocks from Scenery3D).
	pathfinder = Pathfinder3D.new()
	pathfinder.build(grid)

	# 6) Camera rig to the field bounds, focus on the start cell.
	rig.setup(grid.bounds_world())
	rig.focus_world(grid.cell_to_world(meta["start"]))

	# 7) Picker (uses the rig camera).
	picker = Picker3D.new()
	picker.grid = grid
	picker.cam = rig.cam

	# 8) Unit under UnitsRoot, on the start cell.
	unit = Unit3D.new()
	unit.name = "Unit"
	unit.fast = fast
	_units_root.add_child(unit)
	unit.setup(grid, meta["start"])

	# Initialise the HUD label (the picker exists now).
	set_active_level(0)

	# 9) Light + environment (p2_2 §3.4): additive, so the KayKit models (normal
	#    PBR materials) do not look flat/black. The ground stays UNSHADED
	#    (GroundView material) -> flat iso base. Everything null-safe.
	_setup_lighting()

	# 10) Cover/spawn props in the existing _props_root (previously unused).
	#     Assets3D delivers real GLB crates/barrels OR fallback boxes -> even
	#     without assets the smoke test stays green (purely additive decoration).
	_setup_props()

	# 11) map_ready DEFERRED (fix §10.9): the harness awaits it after add_child.
	map_ready.emit.call_deferred()


## Warm tropical sun + sky/environment (ART PASS). Additive/idempotent.
## Shadows only when NOT fast (headless/bot need no shadow map).
func _setup_lighting() -> void:
	# --- Sun: slightly yellowish morning, visible shadow casting. ---
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Polish: sun lower (-55 -> -45 degrees) = longer late-afternoon shadows.
	# Energy 1.15 -> 1.33 compensates for the shallower incidence on the ground
	# (sin55*1.15 ~ sin45*1.33), otherwise the pixel-tuned art-pass exposure tips over.
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-40.0), 0.0)
	sun.light_color = Color(1.0, 0.91, 0.74)   # warm, late sunlight
	sun.light_energy = 1.33
	if not fast:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		# 72x72 field -> high shadow range, tame acne via bias/normal bias.
		sun.directional_shadow_max_distance = 220.0
		sun.directional_shadow_split_1 = 0.08
		sun.directional_shadow_split_2 = 0.20
		sun.directional_shadow_split_3 = 0.50
		sun.shadow_bias = 0.04
		sun.shadow_normal_bias = 1.5
		sun.shadow_blur = 1.0
	add_child(sun)

	# --- Environment: warm procedural sky, filmic tonemap. ---
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.44, 0.80)       # deeper zenith blue -> contrast
	sky_mat.sky_horizon_color = Color(0.82, 0.80, 0.70)   # warm, hazy horizon
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_bottom_color = Color(0.42, 0.40, 0.34) # warm sand/earth tone
	sky_mat.ground_horizon_color = Color(0.74, 0.72, 0.64)
	sky_mat.sun_angle_max = 30.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky

	# Ambient from the sky -> shadowed areas stay coloured instead of dead black.
	# ART PASS T7b: ambient lowered considerably (1.0->0.45) so the sun models the
	# scene (shadow contrast) instead of flooding it flat and blowing bright
	# textures (wall/sand) out to white.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.6
	e.ambient_light_energy = 0.35

	# Filmic tonemap. ART PASS v2 T9: exposure 0.9->0.74. Pixel measurement showed
	# the beach at 255/255/211 (R,G blown out) AND the meadow at ~233/246 (close to
	# clipping, washed towards yellow) -> the whole pipeline was too hot. Lower
	# exposure pulls the beach out of the clip (real sand tone) and makes the meadow
	# richer/greener.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.74
	e.tonemap_white = 1.0

	# Polish: glow/bloom — available in the gl_compatibility renderer since Godot 4.3.
	# Threshold 1.0 = only genuine HDR peaks bloom (muzzle flash/explosion light on
	# surfaces, sun glints) — the base scene stays untouched, no frosted-glass wash.
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# Colour boost for rich tropical colours (no longer washed out by the ambient).
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.12
	e.adjustment_saturation = 1.22
	e.adjustment_brightness = 1.02

	# Warm atmospheric haze for depth. gl_compatibility renders simple
	# (non-volumetric) depth fog.
	# ART PASS v2 T8: CRITICAL — the ortho camera sits 200 units behind the pivot
	# (camera_rig cam.position.z=200), so EVERY piece of geometry is at ~200 depth.
	# At density 0.008 that yields 1-exp(-0.008*200)=~80 % fog EVERYWHERE -> the
	# whole scene drowns in a yellow milk (no depth cue, just wash).
	# density 0.0009 -> ~1-exp(-0.18)=~16 % subtle base haze, distant parts of the
	# map minimally stronger -> atmosphere instead of frosted glass, real tropical
	# colours preserved.
	e.fog_enabled = true
	e.fog_light_color = Color(0.82, 0.80, 0.70)
	e.fog_density = 0.0009
	e.fog_sky_affect = 0.0

	env.environment = e
	add_child(env)


## Places a few crates/barrels on ground cells near cover/spawns. Null-safe.
func _setup_props() -> void:
	if _props_root == null or grid == null:
		return
	# (cell, prop id) — near the spawn (1,0,5) and near the platform/goal (13,1,3).
	# Walkable ground cells only; water (x=7/8) deliberately left out.
	var placements := [
		[Vector3i(2, 0, 4), "crate"],   # cover next to the spawn
		[Vector3i(2, 0, 6), "barrel"],  # cover next to the spawn
		[Vector3i(5, 0, 4), "crate"],   # west bank in front of the bridge
		[Vector3i(5, 0, 6), "barrel"],  # west bank in front of the bridge
		[Vector3i(11, 0, 4), "crate"],  # east bank in front of the platform
		[Vector3i(12, 0, 3), "barrel"], # east bank in front of the platform
		[Vector3i(12, 0, 5), "crate"],  # east bank
	]
	for p in placements:
		var c: Vector3i = p[0]
		var id: String = p[1]
		_place_prop(id, c)


## Instantiates ONE prop on the tile's top edge (0.2 box -> +0.1). Defensive.
func _place_prop(id: String, c: Vector3i) -> void:
	if not grid.is_walkable(c):
		return
	var prop := Assets3D.prop(id)
	if prop == null:
		return
	prop.position = grid.cell_to_world(c) + Vector3(0.0, 0.1, 0.0)
	_props_root.add_child(prop)


func find_demo_path() -> Array:
	# Fix M3: disable SWIM internally so the demo path takes the BRIDGE (not the
	# deep water), then re-enable SWIM.
	if pathfinder == null:
		return []
	pathfinder.set_move_type_enabled(Tac3DTile.Move.SWIM, false)
	var cells := pathfinder.path_cells(meta["start"], meta["goal"])
	pathfinder.set_move_type_enabled(Tac3DTile.Move.SWIM, true)
	return cells


func move_unit_along(cells: Array) -> void:
	if unit == null or cells.is_empty():
		return
	if fast:
		# Headless: snap directly to the destination.
		var last: Vector3i = cells.back()
		unit.set_cell(last)
		return
	var world_points: Array = []
	for c in cells:
		var cc: Vector3i = c
		world_points.append(grid.cell_to_world(cc))
	unit.follow_path(world_points)


func active_level() -> int:
	return _active_level


func set_active_level(l: int) -> void:
	_active_level = l
	if picker != null:
		picker.set_active_level(l)
	if _level_label != null:
		_level_label.text = "Level: %d" % l


func _unhandled_input(ev) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_Q:
				if rig != null:
					rig.rotate_step(-1)
			KEY_E:
				if rig != null:
					rig.rotate_step(1)
			KEY_PAGEUP:
				set_active_level(_active_level + 1)
			KEY_PAGEDOWN:
				set_active_level(_active_level - 1)
	elif ev is InputEventMouseButton and ev.pressed:
		match ev.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if rig != null:
					rig.zoom_by(0.9)
			MOUSE_BUTTON_WHEEL_DOWN:
				if rig != null:
					rig.zoom_by(1.1)
			MOUSE_BUTTON_LEFT:
				_handle_click()


func _handle_click() -> void:
	if picker == null or unit == null or pathfinder == null:
		return
	var target := picker.cell_under_mouse(get_viewport())
	if target == Picker3D.NONE:
		return
	var cells := pathfinder.path_cells(unit.cell, target)
	if cells.is_empty():
		return
	move_unit_along(cells)


func _process(dt: float) -> void:
	if rig == null:
		return
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_A):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		pan.x += 1.0
	if pan != Vector2.ZERO:
		rig.pan(pan.normalized() * PAN_SPEED * dt)

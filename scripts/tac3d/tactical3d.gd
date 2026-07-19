extends Node3D
# Orchestrator-Screen der 3D-Taktik (Phase 1). KEIN class_name (Vertrag §1/§10).
# Baut Container-Nodes ZUERST (Fix K2), dann Grid/Pathfinder/View/Unit,
# emittiert map_ready deferred (Harness await'et nach add_child).

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
	# 1) fast-Flag aus dem Parent (main.gd/Harness). Null-Guard (Fix S8).
	var m := _main()
	if m != null and m.get("fast") == true:
		fast = true

	# 2) Schritt 0 (Fix K2): ZUERST alle Container-Nodes erzeugen + benennen,
	#    BEVOR irgendetwas hineingehaengt wird.
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

	# 3) Karte + Grid (die Wahrheit).
	meta = TestMap3D.build()
	grid = meta["grid"]

	# 4) Pathfinder ueber dem Grid.
	pathfinder = Pathfinder3D.new()
	pathfinder.build(grid)

	# 5) GroundView unter WorldRoot einhaengen, dann bauen.
	ground = GroundView3D.new()
	ground.name = "GroundView"
	_world_root.add_child(ground)
	ground.build(grid)

	# 6) Kamera-Rig auf Feldgrenzen, Fokus auf Startzelle.
	rig.setup(grid.bounds_world())
	rig.focus_world(grid.cell_to_world(meta["start"]))

	# 7) Picker (nutzt die Rig-Kamera).
	picker = Picker3D.new()
	picker.grid = grid
	picker.cam = rig.cam

	# 8) Unit unter UnitsRoot, auf Startzelle.
	unit = Unit3D.new()
	unit.name = "Unit"
	unit.fast = fast
	_units_root.add_child(unit)
	unit.setup(grid, meta["start"])

	# HUD-Label initialisieren (Picker existiert jetzt).
	set_active_level(0)

	# 9) Licht + Environment (p2_2 §3.4): additiv, damit die KayKit-Modelle
	#    (normale PBR-Materialien) nicht flach/schwarz wirken. Der Boden bleibt
	#    UNSHADED (GroundView-Material) -> flache Iso-Basis. Alles null-sicher.
	_setup_lighting()

	# 10) Deckungs-/Spawn-Props im vorhandenen _props_root (bisher ungenutzt).
	#     Assets3D liefert echte GLB-Kisten/Fässer ODER Fallback-Boxen -> auch
	#     ohne Assets bleibt der Smoke grün (rein additive Deko).
	_setup_props()

	# 11) map_ready DEFERRED (Fix §10.9): Harness await'et nach add_child.
	map_ready.emit.call_deferred()


## Warme Tropen-Sonne + Himmel/Environment (ART-PASS). Additiv/idempotent.
## Schatten nur wenn NICHT fast (Headless/Bot brauchen keine Schattenkarte).
func _setup_lighting() -> void:
	# --- Sonne: leicht gelblicher Vormittag, sichtbarer Schattenwurf. ---
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-40.0), 0.0)
	sun.light_color = Color(1.0, 0.95, 0.82)   # warmes Sonnenlicht
	sun.light_energy = 1.1
	if not fast:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		# 72x72-Feld -> Schattenreichweite hoch, Acne über Bias/Normal-Bias zähmen.
		sun.directional_shadow_max_distance = 220.0
		sun.directional_shadow_split_1 = 0.08
		sun.directional_shadow_split_2 = 0.20
		sun.directional_shadow_split_3 = 0.50
		sun.shadow_bias = 0.04
		sun.shadow_normal_bias = 1.5
		sun.shadow_blur = 1.0
	add_child(sun)

	# --- Environment: warmer Prozedural-Himmel, filmischer Tonemap. ---
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.56, 0.82)       # kräftiges Vormittagsblau
	sky_mat.sky_horizon_color = Color(0.78, 0.82, 0.80)   # dunstiger, warmer Horizont
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_bottom_color = Color(0.44, 0.42, 0.36) # warmer Sand-/Erdton
	sky_mat.ground_horizon_color = Color(0.72, 0.72, 0.66)
	sky_mat.sun_angle_max = 30.0
	sky_mat.sky_curve = 0.09
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky

	# Ambient aus dem Himmel -> Schattenpartien bleiben farbig statt tot-schwarz.
	# ART-PASS T7b: Ambient deutlich gesenkt (1.0->0.45), damit die Sonne die Szene
	# modelliert (Schattenkontrast) statt sie flach zu fluten und helle Texturen
	# (Wand/Sand) ins Weiss zu blasen.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.85
	e.ambient_light_energy = 0.6

	# Filmischer Tonemap; Exposure leicht runter (1.0->0.9) gegen ausgebrannte
	# Weissflaechen an Gebaeudewaenden/Strandsand.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.9
	e.tonemap_white = 1.0

	# Farb-Boost fuer satte Tropenfarben (jetzt nicht mehr vom Ambient gewaschen).
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 1.18
	e.adjustment_brightness = 1.0

	# Dezenter, warmer Luftdunst für Tiefe (gl_compatibility rendert einfachen Fog).
	e.fog_enabled = true
	e.fog_light_color = Color(0.82, 0.80, 0.72)
	e.fog_density = 0.0012
	e.fog_sky_affect = 0.0

	env.environment = e
	add_child(env)


## Setzt ein paar Kisten/Fässer auf Deckungs-/Spawn-nahe Bodenzellen. Null-sicher.
func _setup_props() -> void:
	if _props_root == null or grid == null:
		return
	# (Zell, Prop-Id) — nahe Spawn (1,0,5) und nahe Podest/Goal (13,1,3).
	# Nur begehbare Bodenzellen; Wasser (x=7/8) bewusst ausgespart.
	var placements := [
		[Vector3i(2, 0, 4), "crate"],   # Deckung neben Spawn
		[Vector3i(2, 0, 6), "barrel"],  # Deckung neben Spawn
		[Vector3i(5, 0, 4), "crate"],   # Westufer vor der Brücke
		[Vector3i(5, 0, 6), "barrel"],  # Westufer vor der Brücke
		[Vector3i(11, 0, 4), "crate"],  # Ostufer vor dem Podest
		[Vector3i(12, 0, 3), "barrel"], # Ostufer vor dem Podest
		[Vector3i(12, 0, 5), "crate"],  # Ostufer
	]
	for p in placements:
		var c: Vector3i = p[0]
		var id: String = p[1]
		_place_prop(id, c)


## Instanziiert EIN Prop auf der Kachel-Oberkante (0,2-Box -> +0.1). Defensiv.
func _place_prop(id: String, c: Vector3i) -> void:
	if not grid.is_walkable(c):
		return
	var prop := Assets3D.prop(id)
	if prop == null:
		return
	prop.position = grid.cell_to_world(c) + Vector3(0.0, 0.1, 0.0)
	_props_root.add_child(prop)


func find_demo_path() -> Array:
	# Fix M3: SWIM intern deaktivieren, damit der Demo-Pfad die BRUECKE nimmt
	# (nicht durchs tiefe Wasser), dann SWIM wieder aktivieren.
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
		# Headless: direkt ans Ziel snappen.
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
		_level_label.text = "Ebene: %d" % l


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

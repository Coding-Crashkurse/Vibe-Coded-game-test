class_name Hideout
extends Control
## THE HIDEOUT — SPEC v5 §4.3: a menu that is a PLACE, not a list of buttons.
##
## A small cellar room rendered in 3D behind a perspective camera (FOV 50, fixed,
## slightly elevated — deliberately NOT the tactical ortho gimbal). Every menu
## entry is a physical object you click: the bed deploys you, the laptop is the
## A.I.M. network, the wall map is the sector map, the radio holds the options,
## the notebook saves and loads, the door lets you out.
##
## COMPOSITION. It is an establishing shot: a first-time player must see all six
## clickable things at once, each in its own reading position, none buried behind
## another. Left to right across the frame:
##
##   ~11-34%  bed (left wall)          -> Deploy / Rest & heal
##   ~23-33%  shelf + ashveil jar      -  no hotspot, teal key light
##   ~33-48%  wall map (back wall)     -> Sector map
##   ~35-56%  crate cluster on the rug -> Stash (base mode only), knee height
##   ~52-65%  laptop (desk, left end)  -> A.I.M. network
##   ~63-74%  notebook (desk, right)   -> Save & load
##   ~72-76%  radio (back-right crate) -> Options
##   ~79-86%  door (right wall)        -> Leave / Back to map
##
## The lantern hangs dead centre and high, so the middle of the frame is not a
## hole. Floating labels are anchored individually (see _hotspot) and staggered
## in height wherever two props sit close together in screen x.
##
## DOUBLE USE (the whole point of building it): the SAME room is the in-game home
## base. `mode` switches the hotspot meanings — see MODE_MENU / MODE_BASE below.
##
## HOW IT IS REACHED (binding design decision — it overrides SPEC §4.3 where the
## two disagree): the painted 2D artwork menu (scripts/screens/title.gd) IS the
## title screen and stays the entry point. This room is the IN-GAME HOME BASE
## instead, reached once the cellar has been taken (Game.base_unlocked, §3.3.5):
##
##   Title -> New Game            difficulty -> hire -> island map -> F4.
##                                No base exists yet, so nothing changes.
##   Title -> Continue / Load     lands HERE when Game.base_unlocked is true,
##                                otherwise on the island map exactly as before.
##
## Other packages enter it through the static helper at the bottom of the Modes
## block: `Hideout.enter_base(router)`.
##
## TECHNIQUE (same as scripts/screens/unit_gallery.gd): SubViewportContainer +
## SubViewport with `own_world_3d`, real OmniLight3D lights and an ambient
## Environment inside. gl_compatibility renders unlit materials PITCH BLACK, so
## every surface in here either sees one of the four lights or is explicitly
## SHADING_MODE_UNSHADED (laptop screen, hover boxes, floating labels).
##
## ASSETS: floor and walls are the real KayKit Dungeon GLBs from
## res://assets/models/keller/ (4 m units, hence the 0.5 scale). There are NO
## models for bed / table / laptop / map / radio / lantern / shelf in this
## project, so those are built from BoxMesh + CylinderMesh + QuadMesh, chunky and
## low-poly to match the KayKit look. Every load() is guarded — a missing file
## degrades to a primitive, it never crashes.

# ------------------------------------------------------------------ Modes

enum {MODE_MENU, MODE_BASE}

## MODE_MENU  — menu flavour: bed = new campaign, door = quit, crates inert.
##              Only the boot path and --hideout-shots still ask for it.
## MODE_BASE  — home base, the real mode: bed = rest & heal, laptop = A.I.M.,
##              wall map = deploy, notebook = save/load, radio = options,
##              crates = the stash, door = back to the sector map.
## The router may inject the mode the same way tactical3d_combat.gd reads
## `start_sector` off the parent: a plain `m.get("hideout_mode")` — `goto()` runs
## `_ready()` synchronously, so the property CANNOT be assigned afterwards.
## Without an injected value the mode follows Game.base_unlocked, so a bare
## goto("hideout") on a running campaign always opens the base.
var mode := MODE_MENU

# ------------------------------------------------------------------ Constants

const KELLER_DIR := "res://assets/models/keller/"
const MAP_TEX := "res://assets/textures/worldmap.png"

## The shared centered slot overlay (SPEC v5 §4.4) behind the notebook. Loaded at
## RUNTIME, never preloaded: a preload turns a missing file into a parse error and
## would break the fallback law for the whole screen.
const SAVE_PANEL_PATH := "res://scripts/ui/save_panel.gd"

## KayKit Dungeon Remastered is authored at ~4 m per tile — half it and a floor
## tile is 2x2 m, a wall 2 m wide. Walls get an extra Y factor for a 3 m ceiling.
const GLB_SCALE := 0.5
const WALL_Y := 0.75
const ROOM_H := 3.0

const COL_HOVER := Color(1.0, 0.80, 0.42)
const COL_TEAL := Color(0.36, 0.94, 0.84)

## Hover animation timing. Snappy on the way in, a touch quicker on the way out
## so flicking the mouse across the room does not leave a trail of props still
## easing shut behind the cursor.
const ANIM_IN := 0.22
const ANIM_OUT := 0.15

## Onboarding and the title card are a FIRST VISIT thing. A static var survives
## screen changes because Godot keeps the Script resource cached.
static var _visited := false

# ------------------------------------------------------------------ State

var _svc: SubViewportContainer = null
var _sv: SubViewport = null
var _world: Node3D = null
var _cam: Camera3D = null
var _cam_home := Transform3D()

## One entry per hotspot:
##   id, label, center (Vector3), area (Area3D), box (MeshInstance3D highlight),
##   tag (Label3D), mats (Array of restore-records), active (bool)
var _hotspots: Array = []
var _hover := -1
var _busy := false                 # camera tween running -> ignore clicks
var _overlay: Control = null       # options / stash / confirm panel
var _hint: Label = null
var _music_name := "title"
var _title_card: Control = null
var _title_tw: Tween = null

## Object instance id -> the Tween currently driving it. One tween per animated
## node/material, killed before a new one starts: without this, waving the mouse
## in and out stacks tweens that fight over the same property and the prop ends
## up parked halfway.
var _prop_tweens := {}

## The save/load slot overlay while it is up. It is a CanvasLayer of its own and
## swallows clicks, but the room picks with its OWN raycast on _gui_input, so the
## reference is also the guard that keeps hotspots inert underneath it.
var _save_panel: Node = null

## Live references into the stash panel. All of them are children of `_overlay`,
## so _close_overlay() nulls them again; every user re-checks is_instance_valid.
var _stash_left: VBoxContainer = null      # what The Hideout is holding
var _stash_right: VBoxContainer = null     # the selected merc's pack
var _stash_tabs: HBoxContainer = null      # one button per living merc
var _stash_hint: Label = null
var _stash_gear: Label = null              # "IVAN — Huntsman Shotgun"
var _stash_ammo: Label = null              # "Ammo 4/6 · spare mags 2 · pockets 3/8"
var _stash_merc := 0                       # index into Game.team


func _main() -> Node:
	return get_parent()


# ================================================================= Build

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_ARROW

	_read_mode_from_router()

	_build_viewport()
	_build_room()
	_build_lighting()
	_build_props()
	_build_overlay_ui()

	_music_name = "title" if mode == MODE_MENU else "exploration"
	Sfx.play_music(_music_name)

	if not _visited:
		_visited = true
		_show_onboarding()
		if mode == MODE_MENU:
			_show_title_card()


## Same injection pattern as tactical3d_combat.gd's `start_sector`: read an
## OPTIONAL property off the router. `Node.get()` on a property that does not
## exist returns null, which is exactly the "nothing was injected" case.
##
## Without an explicit request the campaign decides: once the cellar is the
## player's (Game.base_unlocked) the room IS the home base, so a bare
## goto("hideout") from anywhere lands in the right mode.
##
## The property is cleared straight after reading. It is a one-shot request, and
## a leftover "menu" would silently downgrade the next visit — the same reason
## main.gd resets `start_sector` after the combat orchestrator has consumed it.
func _read_mode_from_router() -> void:
	mode = MODE_BASE if Game.base_unlocked else MODE_MENU
	var m := _main()
	if m == null:
		return
	var v = m.get("hideout_mode")
	if v == null:
		return
	m.set("hideout_mode", "")
	var s := String(v).to_lower()
	if s == "base":
		mode = MODE_BASE
	elif s == "menu":
		mode = MODE_MENU


## PUBLIC ENTRY POINT — how any other package hands the player over to the room
## as the in-game home base (the combat orchestrator will want this after the
## rescue in §3.3.5):
##
##     Hideout.enter_base(get_parent())      # get_parent() == the main router
##
## `router` is the Main node that owns goto() and the `hideout_mode` property.
## Setting the mode BEFORE goto() is mandatory: goto() add_child()s the screen,
## so _ready() — and with it _read_mode_from_router() — runs synchronously.
## Everything goes through call()/set(), so a router without those members is a
## no-op instead of a crash.
static func enter_base(router: Node) -> void:
	if router == null or not is_instance_valid(router):
		return
	router.set("hideout_mode", "base")
	router.call("goto", "hideout")


func _build_viewport() -> void:
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	# The Control itself handles the mouse (manual camera-ray picking), the
	# container must not swallow events or forward them into the SubViewport.
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_svc)

	_sv = SubViewport.new()
	_sv.own_world_3d = true
	_sv.transparent_bg = false
	_sv.physics_object_picking = false      # we raycast ourselves
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_svc.add_child(_sv)

	_world = Node3D.new()
	_world.name = "Hideout"
	_sv.add_child(_world)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 50.0
	_cam.near = 0.05
	_cam.far = 100.0
	_world.add_child(_cam)
	# ESTABLISHING SHOT. The camera stands 0.7 m OUTSIDE the room's open front
	# (z = 3) on the centre line, 2.3 m up, pitched 13 deg down. That is the whole
	# composition trick: from inside the room only the back wall was in frame and
	# everything along the side walls fell off the edges; from just outside, both
	# side walls sweep into the picture and every hotspot gets its own slot.
	#
	# It stays leak-proof. A ray only escapes if it clears the side wall before
	# reaching z = 3, i.e. if the frustum is wider than the room at the mouth:
	# half-width there is 0.7 * 0.828 = 0.58 m against a 3 m half-room. The floor
	# and ceiling are also one tile wider than the walls (see _build_room), which
	# catches the grazing corner rays on very wide aspect ratios.
	_cam.position = Vector3(0.0, 2.30, 3.70)
	_cam.look_at(Vector3(0.0, 1.15, -1.30), Vector3.UP)
	_cam_home = _cam.transform
	_cam.current = true


## Floor, ceiling and three walls from the KayKit dungeon GLBs. The front (+Z)
## stays open — that is what the camera looks through.
##
## The floor and ceiling run one tile WIDER than the walls (x = +-4 as well as
## +-2, 0). Those outer tiles are hidden behind the side walls from any sane
## angle; they exist so the extreme bottom/top corner rays of a very wide window
## land on stone instead of on the void.
func _build_room() -> void:
	var floor_scene := _keller_scene("floor_tile_large")
	var wall_scene := _keller_scene("wall")
	var stone := _mat(Color(0.34, 0.31, 0.28), 0.95)

	for gx in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		for gz in [-2.0, 0.0, 2.0]:
			var fx: float = gx
			var fz: float = gz
			_place_tile(floor_scene, stone, Vector3(fx, 0.0, fz), 0.0)
			_place_tile(floor_scene, stone, Vector3(fx, ROOM_H, fz), 180.0)

	# Back wall (z = -3) -------------------------------------------------------
	for gx in [-2.0, 0.0, 2.0]:
		var wx: float = gx
		_place_wall(wall_scene, stone, Vector3(wx, 0.0, -3.0), 0.0)
	# Left (x = -3) and right (x = +3) walls -----------------------------------
	for gz in [-2.0, 0.0, 2.0]:
		var wz: float = gz
		_place_wall(wall_scene, stone, Vector3(-3.0, 0.0, wz), 90.0)
		_place_wall(wall_scene, stone, Vector3(3.0, 0.0, wz), 90.0)


func _place_tile(scene: PackedScene, fallback_mat: StandardMaterial3D, pos: Vector3, rot_x: float) -> void:
	var n := _spawn(scene)
	if n != null:
		n.scale = Vector3(GLB_SCALE, GLB_SCALE, GLB_SCALE)
	else:
		n = _box_node(Vector3(2.0, 0.15, 2.0), fallback_mat)
	n.position = pos
	n.rotation_degrees.x = rot_x
	_world.add_child(n)


func _place_wall(scene: PackedScene, fallback_mat: StandardMaterial3D, pos: Vector3, rot_y: float) -> void:
	var n := _spawn(scene)
	if n != null:
		n.scale = Vector3(GLB_SCALE, WALL_Y, GLB_SCALE)
	else:
		n = _box_node(Vector3(2.0, ROOM_H, 0.5), fallback_mat)
		n.position.y = ROOM_H * 0.5      # fallback box is centred, GLB is base-aligned
	n.position += pos
	n.rotation_degrees.y = rot_y
	_world.add_child(n)


func _keller_scene(base: String) -> PackedScene:
	var path := KELLER_DIR + base + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var res = load(path)
	return res if res is PackedScene else null


func _spawn(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var n := scene.instantiate()
	if n is Node3D:
		return n as Node3D
	n.queue_free()
	return null


# ================================================================= Lighting

## gl_compatibility has no global illumination — four omnis plus a generous
## ambient do the whole job. Shadows stay OFF on purpose: omni shadows in the
## Compatibility renderer are expensive and prone to acne, and without them
## nothing here can ever end up black.
func _build_lighting() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.038, 0.032)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.36, 0.30)
	env.ambient_light_energy = 0.55
	env.fog_enabled = false
	we.environment = env
	_world.add_child(we)

	_omni(Vector3(0.15, 2.05, -1.30), Color(1.0, 0.74, 0.42), 4.6, 9.0)    # lantern (key)
	_omni(Vector3(-0.80, 0.95, -1.80), Color(1.0, 0.68, 0.40), 1.4, 6.5)   # warm bounce over bed/floor
	_omni(Vector3(0.20, 2.00, 2.40), Color(0.30, 0.72, 0.88), 1.7, 12.0)   # cool accent from the front
	# The teal jar light is created together with the shelf (see _prop_shelf).


func _omni(pos: Vector3, col: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = col
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	_world.add_child(l)
	return l


# ================================================================= Props

func _build_props() -> void:
	_prop_rug()
	_prop_lantern()
	_prop_shelf()
	_prop_bed()
	_prop_nightstand_radio()
	_prop_wallmap()
	_prop_table_laptop_notebook()
	_prop_door()
	_prop_crates()
	_refresh_labels()


## A worn rug on the floor of the room's centre. Not interactive — it exists to
## fill the wide empty stretch of bare tiles in the lower half of the frame and
## to give the crate cluster something to stand on.
func _prop_rug() -> void:
	var m := _mat(Color(0.40, 0.20, 0.16), 0.98)
	var q := QuadMesh.new()
	q.size = Vector2(2.80, 2.30)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = m
	mi.position = Vector3(0.0, 0.06, -0.30)     # above the tile top (y 0.025), no z-fight
	mi.rotation_degrees.x = -90.0
	_world.add_child(mi)

	var trim := _mat(Color(0.52, 0.30, 0.20), 0.98)
	var q2 := QuadMesh.new()
	q2.size = Vector2(2.30, 1.80)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = q2
	mi2.material_override = trim
	mi2.position = Vector3(0.0, 0.065, -0.30)
	mi2.rotation_degrees.x = -90.0
	_world.add_child(mi2)


## Hanging lantern in the middle of the room — pure decoration, but the key light
## lives here, and it fills the upper centre of the composition.
func _prop_lantern() -> void:
	var metal := _mat(Color(0.20, 0.17, 0.14), 0.6, 0.4)
	var glass := _mat(Color(1.0, 0.80, 0.45), 0.3)
	glass.emission_enabled = true
	glass.emission = Color(1.0, 0.74, 0.40)
	glass.emission_energy_multiplier = 2.2

	# Dead centre of the frame, high up: it fills the empty middle of the shot and
	# its OmniLight sits where it does the most work.
	var g := Node3D.new()
	g.position = Vector3(0.15, 0.0, -1.30)
	_world.add_child(g)
	_cyl(g, 0.015, 0.72, Vector3(0.0, 2.62, 0.0), metal)          # chain to the ceiling
	_box(g, Vector3(0.24, 0.05, 0.24), Vector3(0.0, 2.38, 0.0), metal)
	_cyl(g, 0.10, 0.24, Vector3(0.0, 2.22, 0.0), glass)
	_box(g, Vector3(0.26, 0.05, 0.26), Vector3(0.0, 2.08, 0.0), metal)


## Back wall, left: plank shelf with the ashveil plant in a jar. The ashveil is
## the plant the island is named after — grey-green by day, teal glow at night.
## Its OmniLight3D is a real key light, not just a story nod.
func _prop_shelf() -> void:
	var wood := _mat(Color(0.32, 0.22, 0.13), 0.9)
	var glass := _mat(Color(0.62, 0.86, 0.82, 0.30), 0.15)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var leaf := _mat(Color(0.46, 0.52, 0.44), 0.85)
	leaf.emission_enabled = true
	leaf.emission = COL_TEAL
	leaf.emission_energy_multiplier = 1.5

	# Back wall far left, directly above the head of the bed. The 0.85 m plank at
	# x -2.32 fits exactly between the left wall's inner face (-2.75) and the left
	# edge of the map frame (-1.86) without intersecting either.
	var g := Node3D.new()
	g.position = Vector3(-2.32, 0.0, -2.61)
	_world.add_child(g)
	_box(g, Vector3(0.85, 0.07, 0.28), Vector3(0.0, 1.50, 0.0), wood)
	_box(g, Vector3(0.06, 0.20, 0.24), Vector3(-0.36, 1.37, 0.0), wood)
	_box(g, Vector3(0.06, 0.20, 0.24), Vector3(0.36, 1.37, 0.0), wood)
	# Two crates' worth of books, so the shelf does not look staged.
	_box(g, Vector3(0.09, 0.22, 0.16), Vector3(0.24, 1.645, 0.0), _mat(Color(0.45, 0.20, 0.16), 0.9))
	_box(g, Vector3(0.07, 0.19, 0.16), Vector3(0.34, 1.63, 0.0), _mat(Color(0.24, 0.28, 0.36), 0.9))

	# The jar
	_cyl(g, 0.10, 0.24, Vector3(-0.25, 1.655, 0.0), glass)
	_cyl(g, 0.105, 0.03, Vector3(-0.25, 1.79, 0.0), _mat(Color(0.36, 0.30, 0.20), 0.8))
	# Three chunky leaves inside
	var l1 := _box(g, Vector3(0.05, 0.13, 0.02), Vector3(-0.28, 1.68, 0.0), leaf)
	l1.rotation_degrees.z = 22.0
	var l2 := _box(g, Vector3(0.05, 0.15, 0.02), Vector3(-0.22, 1.69, 0.01), leaf)
	l2.rotation_degrees.z = -18.0
	var l3 := _box(g, Vector3(0.04, 0.11, 0.02), Vector3(-0.25, 1.66, -0.03), leaf)
	l3.rotation_degrees.x = 14.0

	# IDLE PULSE. The one thing in the room that moves without being touched: the
	# ashveil breathes on a ~2.1 s cycle, light and leaf emission together. Kept
	# to +-15% around the base value — at that depth it registers as the room
	# being alive, not as a blinking prop. The tween is bound to the light node,
	# so it dies with the screen and never outlives it.
	var jar := _omni(Vector3(-2.57, 1.72, -2.50), COL_TEAL, 2.6, 4.5)
	var pulse := jar.create_tween()
	pulse.set_loops()
	pulse.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(jar, "light_energy", 3.0, 1.05)
	pulse.parallel().tween_property(leaf, "emission_energy_multiplier", 1.9, 1.05)
	pulse.tween_property(jar, "light_energy", 2.2, 1.05)
	pulse.parallel().tween_property(leaf, "emission_energy_multiplier", 1.3, 1.05)


## Left wall: the bed. MENU = "Deploy", BASE = "Rest & heal".
func _prop_bed() -> void:
	var frame := _mat(Color(0.30, 0.21, 0.13), 0.92)
	var sheet := _mat(Color(0.72, 0.68, 0.58), 0.95)
	var blanket := _mat(Color(0.30, 0.34, 0.22), 0.95)
	var pillow := _mat(Color(0.80, 0.77, 0.68), 0.95)

	# Pulled forward to z = -1.55 so the bed runs diagonally across the left third
	# of the frame (roughly screen x 11%-34%, y 53%-83%) instead of hiding in the
	# corner. Deploy is the most important action in menu mode; it gets the
	# largest silhouette in the shot.
	var g := Node3D.new()
	g.position = Vector3(-2.20, 0.0, -1.55)
	_world.add_child(g)
	_box(g, Vector3(1.05, 0.30, 2.10), Vector3(0.0, 0.15, 0.0), frame)
	_box(g, Vector3(0.14, 0.55, 0.12), Vector3(0.0, 0.40, -1.02), frame)   # headboard post
	_box(g, Vector3(0.98, 0.16, 2.00), Vector3(0.0, 0.38, 0.0), sheet)
	_box(g, Vector3(0.72, 0.13, 0.34), Vector3(0.0, 0.52, -0.78), pillow)

	# HINGE: the blanket hangs off a pivot at its FOOT edge (local z +0.995), not
	# off its own centre, so hovering peels it back toward the foot of the bed
	# instead of rotating it about the middle of the mattress.
	var fold := Node3D.new()
	fold.position = Vector3(0.0, 0.50, 0.995)
	g.add_child(fold)
	_box(fold, Vector3(1.00, 0.09, 1.15), Vector3(0.0, 0.0, -0.575), blanket)

	var anims: Array = []
	# +16 deg lift and a 0.46 m slide toward the foot: the head edge of the
	# blanket rises ~0.32 m and lands at z +0.35, uncovering the mattress and
	# leaving the rest draped over the foot board. Reads as "turned down".
	_anim_xf(anims, fold, Vector3(0.0, 0.02, 0.46), Vector3(16.0, 0.0, 0.0))

	var mats := [frame, sheet, blanket, pillow]
	var label := "Deploy" if mode == MODE_MENU else "Rest & heal"
	# The box is 0.83 tall (rather than 0.62) so the peeled-back blanket, whose
	# head edge rises to ~0.84, stays inside the hotspot in the hover pose too.
	_hotspot("bed", label, Vector3(-2.20, 0.44, -1.55), Vector3(1.10, 0.83, 2.15),
			Vector3(-2.20, 1.35, -1.55), mats, true, anims)


## Back-RIGHT corner: a crate serving as a side table, with the field radio on
## it. It used to sit back-left, where it was buried behind the bed and the
## shelf; on the right it owns its own slot (~74% screen width) next to the desk.
func _prop_nightstand_radio() -> void:
	var wood := _mat(Color(0.38, 0.27, 0.16), 0.92)
	var body := _mat(Color(0.22, 0.24, 0.22), 0.7, 0.25)
	var dial := _mat(Color(0.55, 0.48, 0.30), 0.5, 0.6)
	var grille := _mat(Color(0.14, 0.14, 0.13), 0.95)
	var led := _unlit(Color(1.0, 0.55, 0.25))

	var g := Node3D.new()
	g.position = Vector3(2.45, 0.0, -2.45)
	_world.add_child(g)
	_box(g, Vector3(0.58, 0.52, 0.52), Vector3(0.0, 0.26, 0.0), wood)

	# Radio: body faces +Z (toward the camera), speaker grille and two dials.
	_box(g, Vector3(0.42, 0.26, 0.26), Vector3(0.0, 0.65, 0.0), body)
	_box(g, Vector3(0.17, 0.17, 0.02), Vector3(-0.09, 0.66, 0.135), grille)
	var d1 := _cyl(g, 0.035, 0.02, Vector3(0.09, 0.70, 0.135), dial)
	d1.rotation_degrees.x = 90.0
	var d2 := _cyl(g, 0.028, 0.02, Vector3(0.09, 0.61, 0.135), dial)
	d2.rotation_degrees.x = 90.0
	_box(g, Vector3(0.03, 0.02, 0.02), Vector3(0.15, 0.755, 0.10), led)
	var ant := _cyl(g, 0.012, 0.55, Vector3(0.17, 1.05, -0.05), body)
	ant.rotation_degrees.z = -14.0

	var anims: Array = []
	# The antenna telescopes: scaling its local Y by 1.55 grows it about its own
	# centre, so it is lifted 0.15 m at the same time to keep the BASE pinned to
	# the radio body and send the whole 0.30 m of extra length upward.
	_anim_xf(anims, ant, Vector3(0.0, 0.15, 0.0), Vector3.ZERO, Vector3(1.0, 1.55, 1.0))
	# ...and the set warms up: dials go amber, the power LED burns brighter.
	_anim_albedo(anims, dial, Color(1.0, 0.74, 0.34))
	_anim_albedo(anims, led, Color(1.0, 0.86, 0.60))

	# Label pushed high (y 1.85) and nudged toward the room centre: it must clear
	# "Save & load" below-left of it and "Leave" above-right of it.
	_hotspot("radio", "Options", Vector3(2.45, 0.68, -2.45), Vector3(0.50, 0.36, 0.34),
			Vector3(2.25, 1.85, -2.45), [body, grille], true, anims)


## Back wall, centre: the framed sector map of Ashveil.
func _prop_wallmap() -> void:
	var frame := _mat(Color(0.29, 0.20, 0.12), 0.9)
	var sheet := _mat(Color(0.55, 0.52, 0.38), 0.95)

	var tex: Texture2D = load(MAP_TEX) if ResourceLoader.exists(MAP_TEX) else null
	if tex != null:
		sheet.albedo_color = Color(1, 1, 1)
		sheet.albedo_texture = tex
		# A touch of self-emission so the map stays legible even at the far end
		# of the lantern's falloff.
		sheet.emission_enabled = true
		sheet.emission_texture = tex
		sheet.emission_energy_multiplier = 0.35

	# Left of centre on the back wall, clear of the shelf to its left and of the
	# desk to its right (~screen x 33%-48%, y 29%-47%).
	var g := Node3D.new()
	g.position = Vector3(-1.05, 1.55, -2.735)
	_world.add_child(g)

	# HINGE along the TOP edge of the sheet (local y +0.525), like a poster pinned
	# at the top: hovering swings the bottom out into the room rather than sliding
	# the whole board off the wall.
	var lean := Node3D.new()
	lean.position = Vector3(0.0, 0.525, 0.0)
	g.add_child(lean)

	var q := QuadMesh.new()
	q.size = Vector2(1.50, 1.05)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = sheet
	mi.position = Vector3(0.0, -0.525, 0.0)
	lean.add_child(mi)
	# Frame: four chunky slats around the sheet.
	_box(lean, Vector3(1.62, 0.07, 0.05), Vector3(0.0, 0.035, 0.01), frame)
	_box(lean, Vector3(1.62, 0.07, 0.05), Vector3(0.0, -1.085, 0.01), frame)
	_box(lean, Vector3(0.07, 1.19, 0.05), Vector3(-0.775, -0.525, 0.01), frame)
	_box(lean, Vector3(0.07, 1.19, 0.05), Vector3(0.775, -0.525, 0.01), frame)

	var anims: Array = []
	# -10 deg about X pushes the bottom edge ~0.18 m off the wall.
	_anim_xf(anims, lean, Vector3.ZERO, Vector3(-10.0, 0.0, 0.0))
	# `sheet` is kept OUT of the emission-boost list below so the amber hover tint
	# cannot stain the map artwork; it brightens along its own emission curve
	# instead (0.35 -> 0.80), which is the "being read" beat.
	if tex != null:
		_anim_emit(anims, sheet, 0.80)

	# In the base the map is how the squad leaves for a sector, so it is labelled
	# for the ACTION, not for the object — the bed is "Rest & heal" there and
	# "Deploy" would otherwise have no home.
	#
	# The box is 0.34 deep (was 0.14) so the leaned-out pose stays inside it.
	var label := "Sector map" if mode == MODE_MENU else "Deploy"
	_hotspot("map", label, Vector3(-1.05, 1.55, -2.66), Vector3(1.66, 1.22, 0.34),
			Vector3(-1.05, 2.38, -2.735), [frame], true, anims)


## Back wall, right: the field desk. Laptop (A.I.M.) and notebook (save/load) are
## two SEPARATE hotspots on the same table.
func _prop_table_laptop_notebook() -> void:
	var wood := _mat(Color(0.35, 0.24, 0.14), 0.9)
	var leg := _mat(Color(0.26, 0.18, 0.11), 0.9)

	# The desk runs from the centre of the back wall to the right corner, and the
	# laptop and notebook sit at OPPOSITE ends of it (1 m apart, ~10% of screen
	# width) instead of side by side. Their labels are staggered by 0.5 m in
	# height on top of that, so the wide "A.I.M. network" string cannot run into
	# "Save & load".
	var t := Node3D.new()
	t.position = Vector3(1.30, 0.0, -2.28)
	_world.add_child(t)
	_box(t, Vector3(1.60, 0.09, 0.85), Vector3(0.0, 0.755, 0.0), wood)
	for sx in [-0.68, 0.68]:
		for sz in [-0.31, 0.31]:
			var lx: float = sx
			var lz: float = sz
			_cyl(t, 0.045, 0.71, Vector3(lx, 0.355, lz), leg)

	_laptop(Vector3(0.85, 0.80, -2.20), -14.0)
	_notebook(Vector3(1.85, 0.80, -2.32), 9.0)


## Laptop — the A.I.M. network terminal. The screen is UNSHADED so it reads as a
## light source even though gl_compatibility gives us no emissive bloom.
##
## REST is now nearly shut (lid at +58 deg, screen dimmed to a dark teal); hover
## swings it to -18 deg, a 76 degree opening arc, and brings the screen up to
## full brightness as it goes. Closing it at rest is what makes the hover read as
## "the laptop opens" rather than "the laptop wobbles".
func _laptop(pos: Vector3, yaw: float) -> void:
	var shell := _mat(Color(0.23, 0.25, 0.24), 0.55, 0.3)
	var keys := _mat(Color(0.13, 0.14, 0.14), 0.8)
	var screen := _unlit(Color(0.13, 0.32, 0.31))

	var g := Node3D.new()
	g.position = pos
	g.rotation_degrees.y = yaw
	_world.add_child(g)

	_box(g, Vector3(0.40, 0.03, 0.29), Vector3(0.0, 0.015, 0.0), shell)
	_box(g, Vector3(0.32, 0.006, 0.16), Vector3(0.0, 0.033, 0.03), keys)

	# HINGE at the BACK edge of the base. +90 would lay the lid flat on the
	# keyboard, 0 stands it upright, negative tips it back toward the viewer.
	var hinge := Node3D.new()
	hinge.position = Vector3(0.0, 0.03, -0.145)
	hinge.rotation_degrees.x = 58.0
	g.add_child(hinge)
	_box(hinge, Vector3(0.40, 0.28, 0.02), Vector3(0.0, 0.14, 0.0), shell)
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.235)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = screen
	mi.position = Vector3(0.0, 0.14, 0.012)
	hinge.add_child(mi)

	var anims: Array = []
	_anim_xf(anims, hinge, Vector3.ZERO, Vector3(-76.0, 0.0, 0.0))
	_anim_albedo(anims, screen, Color(0.42, 0.96, 0.90))

	# The hotspot box is world-axis-aligned and covers base + lid in BOTH poses
	# (lid top reaches y ~0.98 shut and ~1.10 open, box spans 0.77-1.13). The
	# label rides HIGH (above the open lid) — the notebook's rides low, which is
	# what keeps the two apart on screen.
	#
	# `screen` is deliberately NOT in the emission-boost list: it is unshaded, so
	# emission does nothing on it, and its brightness is driven by the albedo
	# tween above instead.
	_hotspot("laptop", "A.I.M. network", pos + Vector3(0.0, 0.15, 0.0),
			Vector3(0.48, 0.36, 0.42), pos + Vector3(0.0, 0.75, 0.0),
			[shell], true, anims)


## Notebook with a pencil — the save/load hotspot.
func _notebook(pos: Vector3, yaw: float) -> void:
	var cover := _mat(Color(0.42, 0.26, 0.16), 0.9)
	var page := _mat(Color(0.84, 0.80, 0.68), 0.95)
	var pencil := _mat(Color(0.72, 0.55, 0.20), 0.7)

	var g := Node3D.new()
	g.position = pos
	g.rotation_degrees.y = yaw
	_world.add_child(g)
	_box(g, Vector3(0.34, 0.025, 0.26), Vector3(0.0, 0.012, 0.0), cover)
	var pl := _box(g, Vector3(0.15, 0.012, 0.23), Vector3(-0.08, 0.031, 0.0), page)
	pl.rotation_degrees.z = 3.0
	var pr := _box(g, Vector3(0.15, 0.012, 0.23), Vector3(0.08, 0.031, 0.0), page)
	pr.rotation_degrees.z = -3.0
	var pen := _cyl(g, 0.008, 0.18, Vector3(0.05, 0.045, 0.06), pencil)
	pen.rotation_degrees = Vector3(0.0, 0.0, 90.0)

	# HINGE at the spine (local x = 0, the notebook's centre line). The front
	# cover lies shut over the right-hand page at rest and swings up 62 deg about
	# Z on hover, which is the axis the spine actually runs along.
	var spine := Node3D.new()
	spine.position = Vector3(0.0, 0.040, 0.0)
	g.add_child(spine)
	_box(spine, Vector3(0.165, 0.016, 0.245), Vector3(0.085, 0.0, 0.0), cover)

	var anims: Array = []
	_anim_xf(anims, spine, Vector3.ZERO, Vector3(0.0, 0.0, 62.0))

	# Box raised to 0.26 tall (was 0.16): the opened cover tips up to ~0.19 above
	# the desk and would otherwise stick out of its own hotspot.
	_hotspot("notebook", "Save & load", pos + Vector3(0.0, 0.10, 0.0),
			Vector3(0.42, 0.26, 0.34), pos + Vector3(0.0, 0.22, 0.0),
			[cover, page], true, anims)


## Right wall: the way out. Flush on the inner face, so the room stays sealed and
## no background can leak past it.
func _prop_door() -> void:
	var wood := _mat(Color(0.27, 0.18, 0.11), 0.92)
	var trim := _mat(Color(0.20, 0.14, 0.09), 0.9)
	var iron := _mat(Color(0.30, 0.29, 0.27), 0.5, 0.7)

	# Moved deeper into the room (z -1.30 instead of -1.55 with the old camera) so
	# it lands around 79%-86% of screen width. Previously the door projected to
	# ~93% and its label ran off the right edge as "Leav".
	var g := Node3D.new()
	g.position = Vector3(2.70, 0.0, -1.30)
	_world.add_child(g)

	# The dark stairwell behind the door. It sits 5 mm proud of the wall's inner
	# face (x 2.75) and INSIDE the closed panel's own volume, so at rest the
	# panel hides it completely; swinging the door ajar reveals it as a sliver of
	# black. Unshaded, so it stays black no matter what the lights do.
	_box(g, Vector3(0.02, 1.95, 1.08), Vector3(0.045, 1.03, 0.0),
			_unlit(Color(0.02, 0.02, 0.025)))

	# Static surround: frame posts and lintel do NOT move with the door.
	_box(g, Vector3(0.12, 2.20, 0.09), Vector3(0.01, 1.10, -0.62), trim)
	_box(g, Vector3(0.12, 2.20, 0.09), Vector3(0.01, 1.10, 0.62), trim)
	_box(g, Vector3(0.12, 0.10, 1.33), Vector3(0.01, 2.15, 0.0), trim)

	# HINGE on the far (-Z) edge of the leaf, i.e. the real hinge line, not the
	# panel centre. Everything that belongs to the moving leaf hangs off it with
	# its Z shifted by +0.575 to compensate.
	var hinge := Node3D.new()
	hinge.position = Vector3(0.0, 0.0, -0.575)
	g.add_child(hinge)
	_box(hinge, Vector3(0.10, 2.05, 1.15), Vector3(0.0, 1.03, 0.575), wood)
	for pz in [0.215, 0.575, 0.935]:
		var dz: float = pz
		_box(hinge, Vector3(0.02, 1.90, 0.30), Vector3(-0.055, 1.03, dz), trim)
	_box(hinge, Vector3(0.04, 0.10, 1.10), Vector3(-0.06, 1.55, 0.575), iron)
	_box(hinge, Vector3(0.04, 0.10, 1.10), Vector3(-0.06, 0.55, 0.575), iron)
	var knob := SphereMesh.new()
	knob.radius = 0.045
	knob.height = 0.09
	var km := MeshInstance3D.new()
	km.mesh = knob
	km.material_override = iron
	km.position = Vector3(-0.08, 1.05, 0.995)
	hinge.add_child(km)

	var anims: Array = []
	# -14 deg about Y swings the free edge 0.28 m into the room, toward the
	# camera. Small on purpose: "ajar", not "flung open".
	_anim_xf(anims, hinge, Vector3.ZERO, Vector3(0.0, -14.0, 0.0))

	# Label anchored 0.3 m INTO the room and up near the lintel: that pulls the
	# text off the screen edge (it now ends around 81% instead of overflowing)
	# and lifts it clear of the radio label below it.
	var label := "Leave" if mode == MODE_MENU else "Back to map"
	_hotspot("door", label, Vector3(2.66, 1.05, -1.30), Vector3(0.20, 2.10, 1.30),
			Vector3(2.35, 2.40, -1.30), [wood, trim, iron], true, anims)


## Floor, centre-left: the ammo crates. Real GLBs via Assets3D (with its own
## primitive fallback). Only interactive in base mode — in the main menu there is
## no campaign whose stash could be opened.
##
## These are SET DRESSING and must read as such. They previously filled the whole
## lower-left quadrant and buried the bed; now they are scaled to knee height
## (nothing over 0.9 m) and sit on the rug in the middle of the floor, filling
## the empty centre stretch instead of blocking the left wall.
func _prop_crates() -> void:
	var g := Node3D.new()
	g.position = Vector3(-0.35, 0.0, -0.55)
	_world.add_child(g)

	# The source GLBs are authored large (the stack alone is 2.14 m tall) — at
	# these factors nothing exceeds 0.9 m, so they never occlude the wall map
	# behind them or the desk to their right.
	var stack: Node3D = Assets3D.prop("crates_stacked")
	if stack != null:
		stack.scale = Vector3(0.40, 0.40, 0.40)
		g.add_child(stack)
	var single: Node3D = Assets3D.prop("crate")
	if single != null:
		single.scale = Vector3(0.50, 0.50, 0.50)
		single.position = Vector3(0.48, 0.0, 0.30)
		single.rotation_degrees.y = 24.0
		g.add_child(single)
	var barrel: Node3D = Assets3D.prop("barrel")
	if barrel != null:
		barrel.scale = Vector3(0.55, 0.55, 0.55)
		barrel.position = Vector3(-0.48, 0.0, 0.30)
		g.add_child(barrel)

	var anims: Array = []
	# The crate GLBs are single meshes with no separable lid, so "open the stash"
	# is sold as the loose crate being lifted off the pile and canted over, with
	# the barrel giving a smaller second beat so the cluster moves as a group
	# rather than one object twitching.
	_anim_xf(anims, single, Vector3(0.0, 0.16, 0.03), Vector3(0.0, 9.0, 7.0))
	_anim_xf(anims, barrel, Vector3(0.0, 0.05, 0.0), Vector3(0.0, -7.0, 0.0))

	# The crate GLBs bring their own textured materials — overriding them for a
	# hover glow would destroy the texture, so this hotspot relies on the
	# translucent highlight box plus the floating label only (mats stays empty).
	# The box stops well short of the bed so the two never fight over the same
	# ray, and it is low enough that rays to the wall map pass clean over it.
	_hotspot("crates", "Stash", Vector3(-0.35, 0.50, -0.55), Vector3(1.62, 1.00, 1.45),
			Vector3(-0.35, 0.95, -0.55), [], mode == MODE_BASE, anims)


# ================================================================= Hotspots

## Creates the Area3D used for picking, the translucent highlight box and the
## floating Label3D. `center`/`size` are WORLD-space and axis aligned — every
## prop is either wall-flush or barely yawed, so an AABB is precise enough and
## keeps the ray maths trivial.
##
## `label_pos` is an EXPLICIT world position for the floating label instead of
## "centre + half height". Billboarded labels are drawn with no_depth_test, so
## two of them sitting at similar screen positions overlap into mush — giving
## each one its own anchor lets neighbouring props (laptop/notebook, radio/door)
## be staggered in height so their labels can never collide, and lets wall props
## pull their label toward the room centre so it cannot clip the screen edge.
func _hotspot(id: String, label: String, center: Vector3, size: Vector3,
		label_pos: Vector3, mats: Array, active: bool, anims := []) -> void:
	var area := Area3D.new()
	area.position = center
	area.input_ray_pickable = true
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	area.add_child(cs)
	_world.add_child(area)

	# Kept deliberately faint: the props now MOVE on hover, and a strong box
	# around a swinging lid or an opening door just fights the motion. It is a
	# supporting cue for "this is clickable", not the main feedback any more.
	var hl := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size * 1.02
	hl.mesh = bm
	var hm := _unlit(Color(COL_HOVER.r, COL_HOVER.g, COL_HOVER.b, 0.09))
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hl.material_override = hm
	hl.position = center
	hl.visible = false
	_world.add_child(hl)

	var tag := Label3D.new()
	tag.text = label
	tag.font_size = 64
	tag.pixel_size = 0.0032
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.no_depth_test = true
	tag.render_priority = 8
	tag.modulate = COL_HOVER
	tag.outline_size = 18
	tag.outline_modulate = Color(0.05, 0.04, 0.03, 0.9)
	tag.position = label_pos
	tag.visible = false
	_world.add_child(tag)

	# Remember each material's original emission so hover can be undone exactly.
	var recs: Array = []
	for e in mats:
		var m: StandardMaterial3D = e
		recs.append({
			"m": m,
			"on": m.emission_enabled,
			"c": m.emission,
			"v": m.emission_energy_multiplier,
		})

	var idx := _hotspots.size()
	area.set_meta("hs", idx)
	_hotspots.append({
		"id": id, "label": label, "center": center,
		"area": area, "box": hl, "tag": tag, "mats": recs, "active": active,
		"anims": anims,
	})


## Hides every floating label except the one currently hovered (used after the
## onboarding fade, which must not steal the label from an active hover).
func _refresh_labels() -> void:
	for i in _hotspots.size():
		var hs: Dictionary = _hotspots[i]
		var tag: Label3D = hs["tag"]
		if not is_instance_valid(tag):
			continue
		if i == _hover:
			tag.modulate = COL_HOVER
			tag.visible = true
		else:
			tag.visible = false


# ================================================================= Picking

func _gui_input(ev: InputEvent) -> void:
	if _busy or _overlay != null:
		return
	# The slot overlay lives on its own CanvasLayer and dims the room behind it.
	# Its dim rect already eats the clicks, but hover raycasts would still light
	# props up underneath it — so the room goes inert while it is open.
	if _save_panel != null and is_instance_valid(_save_panel):
		return
	if ev is InputEventMouseMotion:
		_set_hover(_pick_at(get_local_mouse_position()))
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_skip_title_card()
			var i := _pick_at(mb.position)
			_set_hover(i)
			if i >= 0:
				_activate(i)


## Camera ray -> Area3D. `collide_with_areas` is NOT on by default, and bodies
## must be off, otherwise the room's own collision (if any GLB brings some) eats
## the ray.
func _pick_at(pos: Vector2) -> int:
	if _cam == null or _sv == null:
		return -1
	var w := _sv.world_3d
	if w == null:
		return -1
	var space := w.direct_space_state
	if space == null:
		return -1
	var from := _cam.project_ray_origin(pos)
	var to := from + _cam.project_ray_normal(pos) * 40.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return -1
	var col = hit.get("collider")
	if col == null or not (col is Node) or not col.has_meta("hs"):
		return -1
	var idx := int(col.get_meta("hs"))
	if idx < 0 or idx >= _hotspots.size():
		return -1
	var hs: Dictionary = _hotspots[idx]
	return idx if bool(hs["active"]) else -1


func _set_hover(idx: int) -> void:
	if idx == _hover:
		return
	if _hover >= 0 and _hover < _hotspots.size():
		_apply_hover(_hotspots[_hover], false)
	_hover = idx
	if _hover >= 0:
		_apply_hover(_hotspots[_hover], true)
		Sfx.play("ui_select", -8.0)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _hover >= 0 else Control.CURSOR_ARROW
	if _hint != null:
		_hint.text = "" if _hover < 0 else String(_hotspots[_hover]["label"])


func _apply_hover(hs: Dictionary, on: bool) -> void:
	var box: MeshInstance3D = hs["box"]
	var tag: Label3D = hs["tag"]
	if is_instance_valid(box):
		box.visible = on
	if is_instance_valid(tag):
		tag.visible = on
		tag.modulate.a = 1.0
	for e in hs["mats"]:
		var r: Dictionary = e
		var m: StandardMaterial3D = r["m"]
		if m == null:
			continue
		if on:
			m.emission_enabled = true
			m.emission = COL_HOVER
			m.emission_energy_multiplier = 0.45
		else:
			m.emission_enabled = bool(r["on"])
			m.emission = r["c"]
			m.emission_energy_multiplier = float(r["v"])
	_play_anims(hs, on)


# ================================================================= Hover motion

## The props physically react: the laptop lid swings open, the blanket peels
## back, the door drifts ajar. Three rules make this safe:
##
##  1. REST IS RECORDED AT BUILD TIME (see _anim_xf), never at hover time. If the
##     rest pose were sampled when the mouse enters, a hover landing mid-tween
##     would bake the half-open pose in as the new rest and the prop would drift
##     a little further open on every pass until it fell apart.
##  2. ONE TWEEN PER TARGET. _prop_tween kills whatever is already driving that
##     node or material, so flicking in and out cannot stack tweens.
##  3. THE HITBOXES NEVER MOVE. Every Area3D is a child of _world, not of the
##     animating pivots, and picking only queries areas (collide_with_bodies is
##     false), so no moving mesh can ever pull its own hitbox out from under the
##     cursor. That is what stops the classic hover/unhover flicker loop.
func _play_anims(hs: Dictionary, on: bool) -> void:
	for e in hs.get("anims", []):
		var a: Dictionary = e
		match String(a["kind"]):
			"xf":
				_anim_play_xf(a, on)
			"albedo":
				_anim_play_prop(a, "albedo_color", on)
			"emit":
				_anim_play_prop(a, "emission_energy_multiplier", on)


func _prop_tween(target: Object, on: bool) -> Tween:
	var key := target.get_instance_id()
	if _prop_tweens.has(key):
		var old = _prop_tweens[key]
		if old != null and is_instance_valid(old):
			old.kill()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.set_ease(Tween.EASE_OUT if on else Tween.EASE_IN_OUT)
	_prop_tweens[key] = tw
	return tw


func _anim_play_xf(a: Dictionary, on: bool) -> void:
	var n: Node3D = a["node"]
	if not is_instance_valid(n):
		return
	var d := ANIM_IN if on else ANIM_OUT
	var k := "hover_" if on else "rest_"
	var tw := _prop_tween(n, on)
	# position/rotation/scale are tweened separately on purpose. Interpolating a
	# whole Transform3D goes through the basis component-wise, which shears on
	# larger angles — and the laptop lid swings 76 degrees.
	tw.tween_property(n, "position", a[k + "pos"], d)
	tw.parallel().tween_property(n, "rotation", a[k + "rot"], d)
	tw.parallel().tween_property(n, "scale", a[k + "scl"], d)


func _anim_play_prop(a: Dictionary, prop: String, on: bool) -> void:
	var m: StandardMaterial3D = a["mat"]
	if m == null:
		return
	var tw := _prop_tween(m, on)
	tw.tween_property(m, prop, a["hover"] if on else a["rest"], ANIM_IN if on else ANIM_OUT)


## Registers a moving part. Offsets are DELTAS from the pose the node is in right
## now, in degrees for rotation, which keeps the call sites readable.
func _anim_xf(anims: Array, n: Node3D, dpos: Vector3, drot_deg := Vector3.ZERO,
		dscale := Vector3.ONE) -> void:
	if n == null:
		return
	var rp := n.position
	var rr := n.rotation
	var rs := n.scale
	anims.append({
		"kind": "xf", "node": n,
		"rest_pos": rp, "rest_rot": rr, "rest_scl": rs,
		"hover_pos": rp + dpos,
		"hover_rot": rr + Vector3(deg_to_rad(drot_deg.x), deg_to_rad(drot_deg.y),
				deg_to_rad(drot_deg.z)),
		"hover_scl": rs * dscale,
	})


func _anim_albedo(anims: Array, m: StandardMaterial3D, hover_col: Color) -> void:
	if m == null:
		return
	anims.append({"kind": "albedo", "mat": m, "rest": m.albedo_color, "hover": hover_col})


func _anim_emit(anims: Array, m: StandardMaterial3D, hover_energy: float) -> void:
	if m == null:
		return
	m.emission_enabled = true
	anims.append({"kind": "emit", "mat": m, "rest": m.emission_energy_multiplier,
			"hover": hover_energy})


# ================================================================= Actions

func _activate(idx: int) -> void:
	var hs: Dictionary = _hotspots[idx]
	Sfx.play("ui_click")
	match String(hs["id"]):
		"bed":
			if mode == MODE_MENU:
				_deploy()
			else:
				_rest_and_heal()
		"laptop":
			_zoom_then(hs["center"], Vector3(-0.75, 0.22, 0.62), "hire")
		"map":
			_zoom_then(hs["center"], Vector3(0.30, 0.10, 1.05), "island")
		"notebook":
			_open_notebook()
		"radio":
			_open_options()
		"door":
			if mode == MODE_MENU:
				_confirm_quit()
			else:
				_go("island")
		"crates":
			_open_stash()


func _go(screen: String) -> void:
	var m := _main()
	if m != null:
		m.goto(screen)


## The camera-zoom trick from SPEC §4.3: dolly onto the prop, then hand over to
## the 2D screen. `offset` is where the camera ends up RELATIVE to the prop.
func _zoom_then(target: Vector3, offset: Vector3, screen: String) -> void:
	if _busy or _cam == null:
		return
	_busy = true
	_set_hover(-1)
	var xf := Transform3D(Basis(), target + offset).looking_at(target, Vector3.UP)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_cam, "position", xf.origin, 0.6)
	tw.parallel().tween_property(_cam, "quaternion", xf.basis.get_rotation_quaternion(), 0.6)
	tw.tween_callback(func() -> void: _go(screen))


## Base mode, bed: sleep it off. Heals the squad and advances the campaign day.
func _rest_and_heal() -> void:
	var healed := 0
	for e in Game.team:
		var m: Dictionary = e
		if not bool(m.get("alive", true)):
			continue
		var hp := int(m.get("hp", 0))
		var hp_max := int(m.get("hp_max", hp))
		if hp < hp_max:
			m["hp"] = hp_max
			healed += 1
	Game.advance_day(1)
	Sfx.play("ui_confirm")
	var txt := "You sleep until dawn. Day %d." % Game.day
	if healed > 0:
		txt += "\n%d merc%s back to full health." % [healed, "" if healed == 1 else "s"]
	else:
		txt += "\nNobody needed patching up."
	_message("REST", txt)


# ================================================================= Overlays

## All overlays use the same recipe as the dossier (SPEC §4.2): own CanvasLayer,
## dimming ColorRect that eats clicks, centered PanelContainer.
func _panel(title: String, min_size := Vector2(520, 300)) -> VBoxContainer:
	_close_overlay()
	_set_hover(-1)

	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UiTheme.theme()
	layer.add_child(root)

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.70)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(shade)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	center.add_child(panel)

	var pad := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + String(side), 22)
	panel.add_child(pad)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pad.add_child(v)

	var head := UiTheme.header(title, 30)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)

	_overlay = root
	# The CanvasLayer owns the tree branch; freeing the layer frees the panel.
	root.set_meta("layer", layer)
	return v


func _close_overlay() -> void:
	# Dropped unconditionally: they are children of the overlay that is about to
	# go, and a stale reference would outlive it by a frame (queue_free is
	# deferred) and let _rebuild_stash() write into a corpse.
	_stash_left = null
	_stash_right = null
	_stash_tabs = null
	_stash_hint = null
	_stash_gear = null
	_stash_ammo = null
	if _overlay == null:
		return
	var layer = _overlay.get_meta("layer") if _overlay.has_meta("layer") else null
	_overlay = null
	if layer != null and is_instance_valid(layer):
		layer.queue_free()


func _close_button(v: VBoxContainer, txt := "CLOSE") -> void:
	v.add_child(UiTheme.vspace(6))
	var b := UiTheme.btn(txt, _close_overlay, 18)
	b.custom_minimum_size = Vector2(200, 42)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)


func _message(title: String, body: String) -> void:
	var v := _panel(title, Vector2(480, 220))
	var l := UiTheme.lbl(body, 17, UiTheme.COL_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	_close_button(v, "OK")


## OPTIONS (radio hotspot). Since the bus rework in sfx.gd, music and effects hang
## on buses of their OWN ("Music"/"SFX", both feeding Master), so this offers two
## genuinely independent sliders instead of a single master fader.
func _open_options() -> void:
	var v := _panel("OPTIONS", Vector2(560, 400))

	v.add_child(UiTheme.lbl("Music volume", 17, UiTheme.COL_DIM))
	v.add_child(_volume_slider(Sfx.get_music_volume(), _on_music_volume))

	v.add_child(UiTheme.vspace(2))
	v.add_child(UiTheme.lbl("SFX & voices volume", 17, UiTheme.COL_DIM))
	v.add_child(_volume_slider(Sfx.get_sfx_volume(), _on_sfx_volume))

	v.add_child(UiTheme.vspace(4))
	var music := CheckButton.new()
	music.text = "Music on"
	music.button_pressed = Sfx.current_music != ""
	music.toggled.connect(_on_music_toggled)
	v.add_child(music)

	var mute := CheckButton.new()
	mute.text = "Mute everything"
	mute.button_pressed = Sfx.muted
	mute.toggled.connect(_on_mute_toggled)
	v.add_child(mute)

	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	var wm := DisplayServer.window_get_mode()
	fs.button_pressed = (wm == DisplayServer.WINDOW_MODE_FULLSCREEN
			or wm == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	fs.toggled.connect(_on_fullscreen_toggled)
	v.add_child(fs)

	_close_button(v)


## A 0..1 slider, pre-filled with the current value.
func _volume_slider(value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.02
	s.custom_minimum_size = Vector2(0, 26)
	s.value = value
	s.value_changed.connect(cb)
	return s


func _on_music_volume(x: float) -> void:
	Sfx.set_music_volume(x)


func _on_sfx_volume(x: float) -> void:
	Sfx.set_sfx_volume(x)


func _on_music_toggled(on: bool) -> void:
	if on:
		Sfx.play_music(_music_name)
	else:
		Sfx.stop_music()


func _on_mute_toggled(_on: bool) -> void:
	Sfx.toggle_mute()


func _on_fullscreen_toggled(on: bool) -> void:
	if on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## STASH (crates hotspot, base mode only) — The Hideout's footlocker, and it is the
## place where a squad is made ready between missions. It does three jobs:
##
##   TRANSFER  Game.stash_take(idx) pulls an item into the selected merc's pack,
##             Game.stash_add(id) puts one back.
##   EQUIP     a weapon out of the pack goes into the hand, the old one takes its
##             pocket (see _stash_equip).
##   RELOAD    a magazine of the right calibre tops the held weapon up.
##
## Equip and reload are ports of tactical3d_combat.do_swap()/do_reload() against
## the SAME runtime merc dictionary (Game.team entries are exactly what
## Tac3DUnit.data points at during a mission). Only the AP cost is dropped — in
## the base nobody is shooting back. Every other rule, including the ammo_store
## bookkeeping and the "mag_<cal>" item id, is kept identical, so a weapon
## prepared here behaves the same as one prepared mid-battle.
##
## Every move rebuilds both lists. That is not cosmetic: the buttons carry raw
## indices, and stash_take() shifts every index behind the one it removed, so a
## surviving row would hand a stale index to the next click.
func _open_stash() -> void:
	var v := _panel("STASH", Vector2(780, 520))

	var intro := UiTheme.lbl(
			"Loot from cleared sectors ends up here. Pick who is packing, then arm them.",
			15, UiTheme.COL_DIM)
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(intro)

	_stash_tabs = HBoxContainer.new()
	_stash_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	_stash_tabs.add_theme_constant_override("separation", 6)
	v.add_child(_stash_tabs)

	# LOADOUT READOUT. Point 3 of the brief: the effect of an equip or a reload has
	# to be visible, so what the selected merc is holding sits right above the two
	# columns and is rewritten by every rebuild.
	_stash_gear = UiTheme.lbl("", 16, UiTheme.COL_AMBER)
	_stash_gear.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stash_gear.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_stash_gear)

	_stash_ammo = UiTheme.lbl("", 14, UiTheme.COL_DIM)
	_stash_ammo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_stash_ammo)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(cols)
	_stash_left = _stash_column(cols, "THE HIDEOUT")
	_stash_right = _stash_column(cols, "PACK")

	_stash_hint = UiTheme.lbl("", 14, UiTheme.COL_DIM)
	_stash_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_stash_hint)

	_rebuild_stash()
	_close_button(v)


## One titled, scrolling column. Returns the INNER list box, which is what the
## rebuild fills — the scroll container and heading are built once and stay.
func _stash_column(parent: HBoxContainer, title: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	parent.add_child(col)

	var head := UiTheme.lbl(title, 15, UiTheme.COL_AMBER)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 210)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	return list


## Item name -> button row. The Callable is BOUND (never a lambda closing over the
## loop variable), so the index it carries is the one it was built with.
##
## The name label CLIPS instead of growing: a long item name ("Storehouse Cellar
## Key") would otherwise push the buttons out of the column and misalign the whole
## list. The full string stays reachable as the tooltip.
func _stash_row(item_txt: String, btn_txt: String, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var l := UiTheme.lbl(item_txt, 15, UiTheme.COL_TEXT)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	l.tooltip_text = item_txt
	row.add_child(l)
	_row_button(row, btn_txt, cb, 100)
	return row


func _row_button(row: HBoxContainer, txt: String, cb: Callable, width: int) -> Button:
	var b := UiTheme.btn(txt, cb, 13)
	b.custom_minimum_size = Vector2(width, 30)
	row.add_child(b)
	return b


## A pack row: the item, its CONTEXT action (equip a weapon / load a magazine) and
## the store button. The context button is moved in FRONT of the store button so
## the store column stays flush all the way down the list, whether or not a given
## row has an action.
func _pack_row(m: Dictionary, item_id: String, idx: int) -> HBoxContainer:
	var row := _stash_row(_item_name(item_id), "◂  STORE", _stash_store_from_merc.bind(idx))
	var kind := String(_item_def(item_id).get("kind", ""))
	var act: Button = null
	if kind == "weapon":
		act = _row_button(row, "EQUIP", _stash_equip.bind(idx), 84)
		act.disabled = String(m.get("weapon", "")) == item_id
		act.tooltip_text = "Take it in hand — the weapon carried now takes this pocket."
	elif kind == "ammo":
		act = _row_button(row, "LOAD", _stash_reload.bind(idx), 84)
		var w := _weapon_def(String(m.get("weapon", "")))
		if w.is_empty():
			act.disabled = true
			act.tooltip_text = "Nothing in hand to load."
		elif String(_item_def(item_id).get("cal", "")) != String(w.get("cal", "")):
			act.disabled = true
			act.tooltip_text = "Wrong calibre for the %s." % String(w.get("name", "weapon"))
		elif int(m.get("ammo", 0)) >= int(w.get("mag", 0)):
			act.disabled = true
			act.tooltip_text = "Already full."
		else:
			act.tooltip_text = "Top the %s up to %d rounds." % [
					String(w.get("name", "weapon")), int(w.get("mag", 0))]
	if act != null:
		row.move_child(act, 1)
	return row


func _rebuild_stash() -> void:
	# Normalises _stash_merc first, so the tabs and the pack column agree on who
	# is selected even after the chosen merc died or the team changed.
	var merc := _stash_current_merc()
	_rebuild_stash_tabs()
	_refresh_stash_gear(merc)

	if is_instance_valid(_stash_left):
		_clear_children(_stash_left)
		var items: Array = Game.stash
		if items.is_empty():
			_stash_left.add_child(UiTheme.lbl("— empty —", 15, UiTheme.COL_DIM))
		else:
			for i in items.size():
				_stash_left.add_child(_stash_row(_item_name(String(items[i])),
						"TAKE  ▸", _stash_take_to_merc.bind(i)))

	if is_instance_valid(_stash_right):
		_clear_children(_stash_right)
		if merc.is_empty():
			_stash_right.add_child(UiTheme.lbl("Nobody here to carry it.", 15, UiTheme.COL_DIM))
		else:
			var inv: Array = merc.get("inv", [])
			if inv.is_empty():
				_stash_right.add_child(UiTheme.lbl("— pack empty —", 15, UiTheme.COL_DIM))
			else:
				for i in inv.size():
					_stash_right.add_child(_pack_row(merc, String(inv[i]), i))


func _rebuild_stash_tabs() -> void:
	if not is_instance_valid(_stash_tabs):
		return
	_clear_children(_stash_tabs)
	for raw in _stash_alive():
		var i: int = raw
		var m: Dictionary = Game.team[i]
		var b := UiTheme.btn(_nick_of(m), _on_stash_merc.bind(i), 13)
		b.custom_minimum_size = Vector2(0, 30)
		# The active tab is the disabled one — that is the whole selection state.
		b.disabled = (i == _stash_merc)
		_stash_tabs.add_child(b)


## Indices into Game.team of everyone still standing. Corpses cannot be packed.
func _stash_alive() -> Array:
	var out: Array = []
	for i in Game.team.size():
		var m: Dictionary = Game.team[i]
		if bool(m.get("alive", true)):
			out.append(i)
	return out


## The merc currently being packed — {} when the squad is wiped or empty. Repairs
## _stash_merc on the way, so a dead or removed selection falls back to the first
## living body instead of pointing at nothing.
func _stash_current_merc() -> Dictionary:
	var alive := _stash_alive()
	if alive.is_empty():
		return {}
	if not alive.has(_stash_merc):
		_stash_merc = int(alive[0])
	var m: Dictionary = Game.team[_stash_merc]
	return m


func _on_stash_merc(idx: int) -> void:
	_stash_merc = idx
	Sfx.play("ui_select", -6.0)
	_set_stash_hint("")
	_rebuild_stash()


## Stash -> pack. The pack is checked for room BEFORE stash_take() runs: the call
## removes the item from the stash and only returns it, so taking first and
## failing afterwards would delete the item outright.
func _stash_take_to_merc(idx: int) -> void:
	var m := _stash_current_merc()
	if m.is_empty():
		Sfx.play("ui_error")
		_set_stash_hint("Nobody here to carry it.")
		return
	var inv: Array = m.get("inv", [])
	if inv.size() >= Db.INV_SLOTS:
		Sfx.play("ui_error")
		_set_stash_hint("%s is carrying all %d slots already." % [
				_nick_of(m), Db.INV_SLOTS])
		return
	var iid := Game.stash_take(idx)
	if iid == "":
		_rebuild_stash()
		return
	inv.append(iid)
	Sfx.play("ui_click")
	_set_stash_hint("%s -> %s." % [_item_name(iid), _nick_of(m)])
	_rebuild_stash()


## Pack -> stash.
func _stash_store_from_merc(idx: int) -> void:
	var m := _stash_current_merc()
	if m.is_empty():
		return
	var inv: Array = m.get("inv", [])
	if idx < 0 or idx >= inv.size():
		_rebuild_stash()
		return
	var iid := String(inv[idx])
	inv.remove_at(idx)
	Game.stash_add(iid)
	Sfx.play("ui_click")
	_set_stash_hint("%s stowed in The Hideout." % _item_name(iid))
	_rebuild_stash()


# ---------------------------------------------------------------- Arming up
# Ports of tactical3d_combat.do_swap() / do_reload() minus the AP cost. They run
# against the plain Game.team dictionary, which is the very object a Tac3DUnit
# wraps as `data` during a mission — so there is ONE inventory model, not two.

## Pack -> hand. The old weapon takes the pocket the new one just left, which is
## why this can never overflow Db.INV_SLOTS: the pack size does not change. Each
## weapon's remaining rounds are parked under its own id in "ammo_store", so
## swapping back and forth does not magically refill or empty a magazine.
func _stash_equip(idx: int) -> void:
	var m := _stash_current_merc()
	if m.is_empty():
		Sfx.play("ui_error")
		_set_stash_hint("Nobody here to arm.")
		return
	var inv: Array = m.get("inv", [])
	if idx < 0 or idx >= inv.size():
		_rebuild_stash()
		return
	var new_id := String(inv[idx])
	if String(_item_def(new_id).get("kind", "")) != "weapon":
		Sfx.play("ui_error")
		_set_stash_hint("%s is not a weapon." % _item_name(new_id))
		_rebuild_stash()
		return
	if _weapon_def(new_id).is_empty():
		# An item flagged "weapon" with no WEAPONS entry (hand-edited save): equipping
		# it would leave the merc holding something with no calibre and no magazine.
		Sfx.play("ui_error")
		_set_stash_hint("%s cannot be fired." % _item_name(new_id))
		_rebuild_stash()
		return
	var old_id := String(m.get("weapon", ""))
	if old_id == new_id:
		_rebuild_stash()
		return
	var store := _ammo_store(m)
	if String(_item_def(old_id).get("kind", "")) == "weapon":
		# Park the rounds still in the old weapon under its own id, so picking it
		# back up later returns it exactly as it was laid down.
		store[old_id] = int(m.get("ammo", 0))
		inv[idx] = old_id
	else:
		# Nothing sane to hand back (empty or unknown weapon id) — the pocket is
		# freed rather than filled with a phantom item.
		inv.remove_at(idx)
	m["weapon"] = new_id
	m["ammo"] = int(store.get(new_id, 0))
	Sfx.play("ui_confirm")
	_set_stash_hint("%s takes the %s." % [_nick_of(m), _item_name(new_id)])
	_rebuild_stash()


## Magazine -> weapon. Same rules as do_reload(): one magazine of the weapon's
## calibre is consumed and the weapon goes to a FULL magazine, never to
## "old rounds + magazine size". Refusing a full weapon is what stops a player
## from burning spare mags for nothing.
func _stash_reload(idx: int) -> void:
	var m := _stash_current_merc()
	if m.is_empty():
		Sfx.play("ui_error")
		_set_stash_hint("Nobody here to arm.")
		return
	var w := _weapon_def(String(m.get("weapon", "")))
	if w.is_empty():
		Sfx.play("ui_error")
		_set_stash_hint("Nothing in hand to load.")
		_rebuild_stash()
		return
	var mag_size := int(w.get("mag", 0))
	if int(m.get("ammo", 0)) >= mag_size:
		Sfx.play("ui_error")
		_set_stash_hint("The %s is already full." % String(w.get("name", "weapon")))
		return
	var inv: Array = m.get("inv", [])
	# Combat resolves the magazine by ITEM ID ("mag_" + calibre), not by scanning
	# for a matching "cal" field — mirrored here so both paths consume the exact
	# same item.
	var mag_id := "mag_" + String(w.get("cal", ""))
	# `idx` is the row that was clicked, but it is only a HINT: any magazine of the
	# right calibre does the job, and an index goes stale the moment a list is
	# rebuilt. Fall back to a search, exactly like inv_take() does.
	var slot := -1
	if idx >= 0 and idx < inv.size() and String(inv[idx]) == mag_id:
		slot = idx
	else:
		slot = inv.find(mag_id)
	if slot < 0:
		Sfx.play("ui_error")
		_set_stash_hint("No %s in the pack." % _item_name(mag_id))
		_rebuild_stash()
		return
	inv.remove_at(slot)
	m["ammo"] = mag_size
	Sfx.play("reload")
	_set_stash_hint("%s reloads — %d rounds." % [_nick_of(m), mag_size])
	_rebuild_stash()


## The two readout lines above the columns.
func _refresh_stash_gear(m: Dictionary) -> void:
	var gear := "Nobody left to carry anything."
	var ammo := ""
	if not m.is_empty():
		var w := _weapon_def(String(m.get("weapon", "")))
		var pockets: Array = m.get("inv", [])
		if w.is_empty():
			gear = "%s — bare hands" % _nick_of(m)
			ammo = "Pockets %d/%d" % [pockets.size(), Db.INV_SLOTS]
		else:
			var mags := _mags_for(m)
			gear = "%s — %s" % [_nick_of(m), String(w.get("name", "?"))]
			ammo = "Ammo %d/%d · spare mags %d · pockets %d/%d" % [
					int(m.get("ammo", 0)), int(w.get("mag", 0)), mags,
					pockets.size(), Db.INV_SLOTS]
	if is_instance_valid(_stash_gear):
		_stash_gear.text = gear
	if is_instance_valid(_stash_ammo):
		_stash_ammo.text = ammo


## Spare magazines that fit what the merc is holding — the port of mags_for().
func _mags_for(m: Dictionary) -> int:
	var w := _weapon_def(String(m.get("weapon", "")))
	if w.is_empty():
		return 0
	var cal := String(w.get("cal", ""))
	var n := 0
	var inv: Array = m.get("inv", [])
	for e in inv:
		var d := _item_def(String(e))
		if String(d.get("kind", "")) == "ammo" and String(d.get("cal", "")) == cal:
			n += 1
	return n


## Per-weapon magazine memory. Db._runtime() always creates it, but a hand-edited
## save may not — repaired IN PLACE so the caller can write to what it gets back.
func _ammo_store(m: Dictionary) -> Dictionary:
	var raw: Variant = m.get("ammo_store", null)
	if typeof(raw) != TYPE_DICTIONARY:
		var fresh: Dictionary = {}
		m["ammo_store"] = fresh
		return fresh
	return raw as Dictionary


func _nick_of(m: Dictionary) -> String:
	return String(m.get("nick", m.get("name", "?")))


func _set_stash_hint(txt: String) -> void:
	if is_instance_valid(_stash_hint):
		_stash_hint.text = txt


## Db.item()/Db.weapon() index their dictionaries RAW and crash on an unknown id.
## The stash is fed by loot and by save files, so every lookup in here goes through
## these guarded versions instead ({} == "no such thing").
func _item_def(item_id: String) -> Dictionary:
	if Db.ITEMS.has(item_id):
		var d: Dictionary = Db.ITEMS[item_id]
		return d
	return {}


func _weapon_def(weapon_id: String) -> Dictionary:
	if Db.WEAPONS.has(weapon_id):
		var d: Dictionary = Db.WEAPONS[weapon_id]
		return d
	return {}


func _item_name(item_id: String) -> String:
	var d := _item_def(item_id)
	if d.is_empty():
		return item_id
	return String(d.get("name", item_id))


## remove_child FIRST: queue_free only lands at the end of the frame, so the old
## rows would otherwise still sit in the container next to the new ones.
func _clear_children(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# ================================================================= Save & load

## NOTEBOOK (desk, right) — the pen-and-paper end of the save system. It only
## offers the two doors; the slot list itself is the SHARED overlay from
## scripts/ui/save_panel.gd (SPEC v5 §4.4), the very same one the painted main
## menu opens, so slots, thumbnails and the damaged-file rendering stay identical.
func _open_notebook() -> void:
	if not ResourceLoader.exists(SAVE_PANEL_PATH):
		_message("NOTEBOOK", "The save panel is missing from this build.")
		return
	var v := _panel("NOTEBOOK", Vector2(540, 260))
	var l := UiTheme.lbl("Write the day down, or read an older page.", 17, UiTheme.COL_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	v.add_child(UiTheme.vspace(8))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)

	var save_btn := UiTheme.btn("SAVE", _open_slot_panel.bind("save"), 18)
	save_btn.custom_minimum_size = Vector2(190, 44)
	row.add_child(save_btn)

	var load_btn := UiTheme.btn("LOAD", _open_slot_panel.bind("load"), 18)
	load_btn.custom_minimum_size = Vector2(190, 44)
	load_btn.disabled = not Game.has_any_save()
	load_btn.tooltip_text = "" if Game.has_any_save() else "Nothing written down yet."
	row.add_child(load_btn)

	_close_button(v)


## `which` is "save" or "load". The script is fetched at runtime and kept in an
## UNTYPED variable on purpose: naming the class statically would make a missing
## file a parse error for the whole room instead of a handled miss.
func _open_slot_panel(which: String) -> void:
	if _save_panel != null and is_instance_valid(_save_panel):
		return
	_close_overlay()
	_set_hover(-1)
	if not ResourceLoader.exists(SAVE_PANEL_PATH):
		return
	var scr = load(SAVE_PANEL_PATH)
	if scr == null:
		return
	_save_panel = scr.open(self, which, _on_slot_panel_done)


## The overlay hands back {"action": "load"|"save"|"cancel", "slot": int, "ok": bool}.
func _on_slot_panel_done(res: Dictionary) -> void:
	_save_panel = null
	if not bool(res.get("ok", false)):
		return
	match String(res.get("action", "")):
		"save":
			_message("NOTEBOOK", "Written down. Slot %d." % int(res.get("slot", 0)))
		"load":
			# The LOADED campaign decides where the player lands — the save that
			# was just read may well be from before the cellar was taken.
			if Game.base_unlocked:
				enter_base(_main())
			else:
				_go("island")


## MENU MODE ONLY. SPEC §4.3 calls the bed "Deploy — start/CONTINUE campaign".
## The room is no longer the main menu (the painted title screen is), so this is
## the fallback path for the boot-flag route and --hideout-shots. Without a save
## it goes straight into a new campaign; with one it ASKS, rather than quietly
## overwriting a running game.
func _deploy() -> void:
	if not Game.has_any_save():
		Game.new_game()
		_go("difficulty")
		return
	var v := _panel("DEPLOY", Vector2(560, 260))
	var l := UiTheme.lbl("Continue the running campaign, or start over?", 17, UiTheme.COL_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	v.add_child(UiTheme.vspace(8))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var cont := UiTheme.btn("CONTINUE", _continue_campaign, 18)
	cont.custom_minimum_size = Vector2(200, 44)
	row.add_child(cont)
	var fresh := UiTheme.btn("NEW CAMPAIGN", func() -> void:
		_close_overlay()
		Game.new_game()
		_go("difficulty"), 18)
	fresh.custom_minimum_size = Vector2(200, 44)
	row.add_child(fresh)


## Load the most recent save and resume, exactly like the painted CONTINUE button.
## If loading fails the overlay STAYS open instead of jumping into a broken game —
## the error sound is the signal.
func _continue_campaign() -> void:
	var slot := Game.latest_slot()
	if slot < 0 or not Game.load_game(slot):
		Sfx.play("ui_error")
		return
	Sfx.play("ui_confirm")
	_close_overlay()
	# Same rule as the title screen: a campaign that already owns the cellar
	# resumes IN the base, everything older resumes on the sector map.
	if Game.base_unlocked:
		enter_base(_main())
	else:
		_go("island")


func _confirm_quit() -> void:
	var v := _panel("LEAVE THE HIDEOUT?", Vector2(500, 240))
	var l := UiTheme.lbl("Unsaved progress is lost.", 17, UiTheme.COL_DIM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	v.add_child(UiTheme.vspace(8))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var yes := UiTheme.btn("QUIT", func() -> void: get_tree().quit(), 18)
	yes.custom_minimum_size = Vector2(180, 44)
	row.add_child(yes)
	var no := UiTheme.btn("STAY", _close_overlay, 18)
	no.custom_minimum_size = Vector2(180, 44)
	row.add_child(no)


func _unhandled_key_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey):
		return
	var k := ev as InputEventKey
	if not k.pressed or k.echo:
		return
	if k.keycode == KEY_ESCAPE and _overlay != null:
		_close_overlay()
		get_viewport().set_input_as_handled()


# ================================================================= 2D overlay

func _build_overlay_ui() -> void:
	# Vignette: gl_compatibility forbids screen-reading shaders, so this is a
	# plain radial-alpha texture stretched over the viewport.
	var vg := TextureRect.new()
	vg.texture = _vignette_tex()
	vg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vg.stretch_mode = TextureRect.STRETCH_SCALE
	vg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vg)

	_hint = UiTheme.lbl("", 20, UiTheme.COL_AMBER)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -60
	_hint.offset_bottom = -28
	add_child(_hint)

	var where := "THE HIDEOUT" if mode == MODE_MENU else "THE HIDEOUT · HOME BASE"
	var corner := UiTheme.lbl(where, 15, UiTheme.COL_DIM)
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.modulate.a = 0.65
	corner.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	corner.offset_left = 22
	corner.offset_top = 16
	add_child(corner)


func _vignette_tex() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (n - 1) * 0.5
	for y in n:
		for x in n:
			var d := Vector2(float(x) - c, float(y) - c).length() / c
			var a := clampf((d - 0.55) / 0.75, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, a * 0.62))
	return ImageTexture.create_from_image(img)


## First visit: every label on for 3 s, then fade out. After that, hover only.
func _show_onboarding() -> void:
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_callback(_show_all_labels)
	tw.tween_interval(3.0)
	tw.tween_method(_fade_labels, 1.0, 0.0, 0.8)
	tw.tween_callback(_refresh_labels)


func _show_all_labels() -> void:
	for e in _hotspots:
		var hs: Dictionary = e
		if not bool(hs["active"]):
			continue
		var tag: Label3D = hs["tag"]
		if is_instance_valid(tag):
			tag.modulate = COL_HOVER
			tag.visible = true


func _fade_labels(a: float) -> void:
	for e in _hotspots:
		var hs: Dictionary = e
		var tag: Label3D = hs["tag"]
		if is_instance_valid(tag) and tag.visible:
			tag.modulate.a = a


## "BITTER HARVEST" over the room, gone after 2 s or on the first click.
func _show_title_card() -> void:
	var card := Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)

	var t := UiTheme.header("BITTER HARVEST", 76)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	t.offset_left = -520
	t.offset_right = 520
	t.offset_top = 120
	t.offset_bottom = 220
	card.add_child(t)

	var sub := UiTheme.lbl("Ashveil · The Hideout", 20, UiTheme.COL_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.offset_left = -520
	sub.offset_right = 520
	sub.offset_top = 216
	sub.offset_bottom = 250
	card.add_child(sub)

	_title_card = card
	_title_tw = create_tween()
	_title_tw.tween_interval(2.0)
	_title_tw.tween_property(card, "modulate:a", 0.0, 0.6)
	_title_tw.tween_callback(card.queue_free)


## Any click skips the card. The click is NOT swallowed — the room stays fully
## interactive while the title is up.
func _skip_title_card() -> void:
	if _title_tw != null and is_instance_valid(_title_tw) and _title_tw.is_running():
		_title_tw.kill()
	_title_tw = null
	if _title_card != null and is_instance_valid(_title_card):
		_title_card.queue_free()
	_title_card = null


# ================================================================= Mesh helpers

func _mat(col: Color, rough := 0.9, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m


## Unshaded: independent of every light, so it can NEVER come out black — used
## for the laptop screen, the hover boxes and small emissive details.
func _unlit(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := _box_node(size, mat)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _box_node(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = mat
	return mi


func _cyl(parent: Node3D, radius: float, height: float, pos: Vector3,
		mat: StandardMaterial3D) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 10
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

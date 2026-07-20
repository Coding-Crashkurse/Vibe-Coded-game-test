extends Node3D
## Orchestrator screen of the 3D tactical BATTLE (strand A). NO class_name (contract §1.6/§10).
## Ports the pure combat logic from scripts/screens/tactical.gd (AP, sight/LOS, cover,
## aiming, shot/hit, interrupts, AI/leash, noise, grenades, loot, boss, victory)
## 1:1 onto Grid3D/Pathfinder3D/Tac3DUnit. All ranges run FLAT on (x,z); the
## level (y) only carries height bonuses (sight/hit) + level links (bridge/ramp).
##
## Build order (scaffold pattern from tactical3d.gd): container nodes FIRST, then
## map/pathfinder/view/vision/AI/rig/picker/units, battle_ready DEFERRED.
##
## GDScript traps (binding, p2_1 §7): typed Variant iteration, preserve integer
## division (int(agi)/5 etc.), call_deferred for signals, MOVE_AP.get(move_type, 2),
## duplicate(true) for enemy defs, path_for un-/blocks u.cell, await chains complete.

signal battle_ready
signal battle_finished(result: String)

var grid: Grid3D
var pathfinder: Pathfinder3D
var vision: Tac3DVision
var ai: Tac3DAI
var rig: CameraRig3D
var ground: GroundView3D
var picker: Picker3D
var meta: Dictionary
var fast := false

# SPEC v5 §2/§3.3 — two-sector demo (F4 landing zone -> west exit -> F3 Rookhaven).
# `start_sector` deliberately stays on "F3": ALL four headless test modes expect the
# previous behaviour. For the real game the router (main.gd) injects "F4" via a
# property of the same name on the parent (same pattern as the `fast` flag).
var start_sector := "F3"
var sector := "F3"                   # currently loaded sector
var exit_cells: Dictionary = {}      # Vector3i -> true (sector exit, here: west edge of F4)
var _transitioning := false          # sector change in progress -> abort running moves
var _edge_locked_at := Vector3i(-99, -99, -99)   # last cell that showed the "locked" banner

# In-fiction reasons for the locked map edges (spec §2).
const EDGE_LOCKED := {
	"north": "LOCKED — the northern ridge is a mined Helix exclusion zone.",
	"east": "LOCKED — the eastern cliffs fall straight into the sea.",
	"south": "LOCKED — the boat is gone. There is no way back to the water.",
	"west": "LOCKED — no route leads further west from here.",
}

# SPEC v5 §3.3.3 — the storehouse cellar sits behind a locked, guarded door.
# Three ways in, so the player can never be stuck in front of it:
#   1) kill the guard posted at the hatch (the door falls open with him),
#   2) loot the cellar key off his corpse (Db.ITEMS["cellar_key"]),
#   3) breach the door at adjacency for BREACH_AP.
# Sectors without a cellar (F4) deliver NO_CELL -> every path below is a no-op.
const NO_CELL := Vector3i(-1, -1, -1)   # mirrors Tac3DMapGen.NO_CELL
const BREACH_AP := 8                    # AP to force the hatch open at adjacency
var cellar_door := NO_CELL              # level-0 hatch cell
var cellar_locked := false              # true while the hatch is barred
var cellar_key_taken := false           # the key was looted off the guard

var units: Array = []            # all Tac3DUnit
var mercs: Array = []
var enemies: Array = []
var boss: Tac3DUnit = null
var captive: Tac3DUnit = null    # Otto, until freed (NOT in mercs/units/enemies)
# SPEC v5 §3.3.5 — Rookhaven villagers, spawned when the base goes live. Same
# contract as `captive`: NOT in mercs/units/enemies, so they take no AI turn and
# count towards neither the win nor the lose condition.
var villagers: Array = []
var occupied: Dictionary = {}    # Vector3i -> Tac3DUnit
var corpses: Dictionary = {}     # Vector3i -> Tac3DUnit
var visible_cells: Dictionary = {}   # Vector3i -> true (K2: seen per target cell)
var looted: Dictionary = {}      # Vector3i -> true (emptied crate / destroyed cover)
var loot_cells: Array = []       # walkable cover/loot tiles (from MapGen)

var selected: Tac3DUnit = null
var mode := "move"
var aim_level := 0
# JA2 aiming: right-clicking an enemy builds aim levels on THAT target.
# Switching target or firing resets the aim (it applies to ONE shot).
var _aim_target: Tac3DUnit = null
# JA2 hit zone (key T): torso/kopf/beine — applies to player shots only.
var aim_zone := "torso"
var player_turn := true
var busy := false
var _movers := 0                 # number of do_move coroutines running in parallel (group move)
var battle_over := false
var combat_started := false
var no_contact_rounds := 0
var noise_at := Vector3i(-99, -99, -99)
var turn := 1
var loot_rng := RandomNumberGenerator.new()

# Interactive view/controller layer (only built when not fast; null in the bot run).
var hud = null                       # CombatHud or null
var cursor: CursorView3D = null
var juice = null                     # Juice3D or null (only when not fast; always null in the bot)
## Fog of war (SPEC §6). UNTYPED on purpose, exactly like `juice`: a brand-new
## file's class_name may not be in Godot's global class cache yet (ground_view.gd
## documents the same hazard for Scenery3D). Always null in fast/bot mode.
var fog = null
var hover_cell := Picker3D.NONE
var hover_path: Array = []

# #2 (new): mouse multi-selection (drag a box). `selection` holds the currently
# selected mercs (>=1); with >1 a movement click drags the WHOLE group.
var selection: Array = []            # Tac3DUnit (living mercs only)
var _lmb_down := false               # left mouse button held (click OR box)
var _lmb_start := Vector2.ZERO       # screen position at press time
var _lmb_dragging := false           # threshold exceeded -> box mode
const DRAG_PX := 8.0                 # beyond this mouse travel it is a box, not a click

# Replaces v2 step_cost (2/3 AP, diagonals). Grid3D has no diagonals, water costs more.
const MOVE_AP := {
	Tac3DTile.Move.WALK: 2,
	Tac3DTile.Move.WADE: 4,
	Tac3DTile.Move.SWIM: 6,
	Tac3DTile.Move.CLIMB: 3,
}
const HEIGHT_HIT_BONUS := 8.0    # hit bonus per level of height advantage (spec §6.2)
const PAN_SPEED := 24.0
var _cam_dragging := false   # middle mouse held = grab the map and scroll it
var _drag_last := Vector2.ZERO

var _world_root: Node3D
var _units_root: Node3D


func _main() -> Node:
	return get_parent()


# ================================================================= Build

func _ready() -> void:
	# 1) fast flag from the parent (harness). Null-guarded.
	var m := _main()
	if m != null and m.get("fast") == true:
		fast = true
	loot_rng.seed = 987654 + hash(Game.difficulty)

	# 2) Container nodes FIRST (fix K2/scaffold), BEFORE anything is attached.
	rig = CameraRig3D.new()
	rig.name = "CameraRig"
	add_child(rig)

	_world_root = Node3D.new()
	_world_root.name = "WorldRoot"
	add_child(_world_root)

	_units_root = Node3D.new()
	_units_root.name = "UnitsRoot"
	add_child(_units_root)

	# 2b) Start sector: the router (main.gd) may inject it via the `start_sector`
	#     property (same pattern as `fast`). Without injection it stays "F3" ->
	#     all existing tests run unchanged.
	if m != null:
		var ss = m.get("start_sector")
		if ss != null and String(ss) != "":
			start_sector = String(ss)
	sector = start_sector

	# 3)–9) Map + all map-dependent systems (identical order as before).
	_build_map_systems(sector)

	# 10) Light/environment (additive, so later GLB bodies are not pitch black).
	_setup_lighting()

	# 11) Units: mercs (Game.team) + enemies (MapGen.enemy_spawns).
	_spawn_units()

	# 12) Initial vision + starting selection.
	compute_vision()
	if not mercs.is_empty():
		selected = mercs[0]
		selection = [selected]

	# 12b) Interactive build ONLY outside bot mode (regression: fast => hud/cursor stay null).
	if not fast:
		cursor = CursorView3D.new()
		cursor.name = "CursorView"
		_world_root.add_child(cursor)
		cursor.setup(grid)
		hud = CombatHud.new()
		hud.name = "CombatHud"
		add_child(hud)
		hud.build(self)
		hud.refresh()
		if picker != null and selected != null:
			picker.set_active_level(selected.cell.y)
		# FIX F3: build juice at the END of the not-fast block (AFTER picker.set_active_level,
		# NOT after hud.build) -> disjoint from phase 3. In the bot juice stays null.
		juice = Juice3D.new()
		juice.name = "Juice"
		_world_root.add_child(juice)
		juice.setup(grid, rig)
		# Fog of war (SPEC §6). attach() returns null in fast mode, so the bot
		# never pays for it. load() instead of the FogView3D identifier for the
		# same class-cache reason the member is untyped.
		fog = load("res://scripts/tac3d/fog_view3d.gd").attach(_world_root, grid, fast)

	# 12c) Phase 7 — exploration music (baked, fallback-safe). Only when not fast (keeps the bot clean).
	if not fast:
		Sfx.play_music("exploration")

	# 12d) SPEC v5 §3.3.2 — objective cue for the current sector (F4: west exit).
	_refresh_objective()

	# 13) battle_ready DEFERRED (fix §10.9): the harness awaits it after add_child.
	battle_ready.emit.call_deferred()


## Build steps 3–9: map, GroundView/Scenery, pathfinder, vision, AI, rig, picker.
## Deliberately its own method so `load_sector` can repeat it 1:1.
## The ORDER is contractual: GroundView BEFORE the pathfinder (Scenery3D marks
## palm cells unwalkable), rig BEFORE the picker (the picker takes rig.cam).
func _build_map_systems(sector_id: String) -> void:
	# 3) Map + grid (the source of truth).
	meta = Tac3DMapGen.generate(20260718, Game.difficulty, sector_id)
	grid = meta["grid"]
	loot_cells = meta["loot_cells"]
	# Sector exit as a set (F3 delivers none -> no behaviour changes).
	exit_cells = {}
	for xc in meta.get("exit_cells", []):
		var ex: Vector3i = xc
		exit_cells[ex] = true

	# 4) Attach GroundView under WorldRoot, then build it — BEFORE the pathfinder:
	#    Scenery3D marks palm cells as unwalkable (object collision), and the
	#    pathfinder must already see those blocks while it is being built.
	ground = GroundView3D.new()
	ground.name = "GroundView"
	_world_root.add_child(ground)
	ground.build(grid)

	# 5) Pathfinder on top of the grid (incl. the palm blocks from Scenery3D).
	pathfinder = Pathfinder3D.new()
	pathfinder.build(grid)
	# Fix: block crate/barrel cells (cover, FLAG_DESTRUCT) for movement —
	# units used to stand INSIDE the crate mesh and corpses vanished underneath.
	# ONLY the AStar point is blocked (same as _occupy); tile.begehbar stays
	# true, because the W1 wall guard in do_grenade tells crate from wall by it.
	for k in grid.all_cells():
		var kc: Vector3i = k
		if _is_crate_cell(kc):
			pathfinder.set_cell_blocked(kc, true)

	# SPEC v5 §3.3.3 — locked cellar door. The hatch cell is the ONLY link down to
	# level -1, so blocking its AStar point is enough to bar the way; the tile
	# itself stays walkable (same technique as the crate cells above). Sectors
	# without a cellar deliver NO_CELL, and a run that already freed Tobias finds
	# the door open (returning to F3, or a loaded save).
	var ke = meta.get("keller_entrance", NO_CELL)
	cellar_door = NO_CELL
	if ke is Vector3i:
		cellar_door = ke
	cellar_key_taken = false
	cellar_locked = _has_cellar_door() and not Game.otto_freed
	if cellar_locked:
		pathfinder.set_cell_blocked(cellar_door, true)

	# 6) Vision (grid LOS) on top of the grid.
	vision = Tac3DVision.new()
	vision.grid = grid

	# 7) AI, wired to this orchestrator (ctl is UNTYPED — cyclic-dependency trap).
	ai = Tac3DAI.new()
	ai.setup(self)

	# 8) Camera rig on the field bounds, focused on the merc landing zone.
	rig.setup(grid.bounds_world())
	var mspawns: Array = meta["merc_spawns"]
	if not mspawns.is_empty():
		rig.focus_world(grid.cell_to_world(mspawns[0]))

	# 9) Picker (uses the rig camera).
	picker = Picker3D.new()
	picker.grid = grid
	picker.cam = rig.cam


func _spawn_units() -> void:
	var mspawns: Array = meta["merc_spawns"]
	var placed := 0
	for i in Game.team.size():
		var td: Dictionary = Game.team[i]
		# FIX: mercs killed in an EARLIER sector stay dead across the transition.
		# load_sector re-spawns the squad from Game.team, and a fresh Tac3DUnit
		# always starts with alive=true — so without this guard the F4 -> F3
		# transition resurrected everyone who fell in the landing zone.
		if not bool(td.get("alive", true)) or int(td.get("hp", 1)) <= 0:
			continue
		var start: Vector3i = mspawns[placed % mspawns.size()]
		placed += 1
		var u := Tac3DUnit.new()
		u.fast = fast
		_units_root.add_child(u)
		u.setup_combat(grid, td, true, start)
		# Merc home stays Vector3i.ZERO (leash 9999 -> irrelevant, as in v2).
		_occupy(u, u.cell)
		units.append(u)
		mercs.append(u)

	for es in meta["enemy_spawns"]:
		var esd: Dictionary = es
		var type := String(esd["type"])
		var d := _spawn_enemy_dict(type)
		var u := Tac3DUnit.new()
		u.fast = fast
		_units_root.add_child(u)
		u.setup_combat(grid, d, false, esd["cell"])
		u.home = esd["cell"]
		_occupy(u, u.cell)
		units.append(u)
		enemies.append(u)
		u.set_seen(false)
		if type == "boss":
			boss = u
			u.home = meta["boss_home"]
	_mark_cellar_guard()
	_spawn_otto()


## SPEC v5 §3.3.3 — "guarded door": the militia posted closest to the storehouse
## hatch IS the keyholder. Deliberately no EXTRA unit: the enemy count is a test
## contract (Tac3DMapGen.DEMO_ENEMY_TOTAL, smoke B2/K1), so marking an existing
## guard is the only way to add the beat without breaking the harness.
func _mark_cellar_guard() -> void:
	if not _has_cellar_door():
		return
	var best: Tac3DUnit = null
	var bd := 999999.0
	for e in enemies:
		var en: Tac3DUnit = e
		if en == boss or not en.alive:
			continue
		var d := Tac3DVision.flat(en.cell).distance_to(Tac3DVision.flat(cellar_door))
		if d < bd:
			bd = d
			best = en
	if best == null:
		return
	best.data["cellar_key"] = true
	# Visible cue in the hover tooltip / HUD so the key is findable, not guesswork.
	best.data["name"] = String(best.data["name"]) + " · Keyholder"


## True when this sector HAS a cellar hatch at all (F4 delivers NO_CELL).
func _has_cellar_door() -> bool:
	return cellar_door.x >= 0 and grid != null and grid.has_tile(cellar_door)


func _any_enemy_alive() -> bool:
	for e in enemies:
		var en: Tac3DUnit = e
		if en.alive:
			return true
	return false


## Phase 7 — Otto as a captive. is_merc=true, but NOT in mercs/units/enemies:
## no AI, no valid target, counts towards neither the win nor the lose condition.
## Occupies his cell (pathfinder block), grey until freed.
## Model: since SPEC §4.1 no longer blanket Swat but Db.OTTO["model"]
## ("casual" — he is a village elder, not an operator), resolved in Tac3DUnit.
func _spawn_otto() -> void:
	if not meta.has("otto_spawn"):
		return
	# Sectors without a cellar (F4) deliver the sentinel Tac3DMapGen.NO_CELL. And if Otto
	# is already freed (sector change AFTER the rescue) he sits in Game.team and is
	# spawned above as a regular merc -> no second captive.
	var os: Vector3i = meta["otto_spawn"]
	if os == Tac3DMapGen.NO_CELL or Game.otto_freed:
		return
	var u := Tac3DUnit.new()
	u.fast = fast
	_units_root.add_child(u)
	u.setup_combat(grid, Db.otto_runtime(), true, meta["otto_spawn"])
	u.home = meta["otto_spawn"]
	u.set_tint(Color(0.65, 0.62, 0.55))   # "captive" grey, until freed (then merc blue)
	_occupy(u, u.cell)
	captive = u
	# NOT in mercs/units/enemies! (no AI, no target, no win/lose counting)


# 1:1 from tactical.gd:148-160 — fresh enemy runtime dict. duplicate(true) so the
# shared const dictionary is NOT mutated (marks += marks_mod).
func _spawn_enemy_dict(type: String) -> Dictionary:
	var def: Dictionary = Db.ENEMY_TYPES[type].duplicate(true)
	var w: Dictionary = Db.weapon(def["weapon"])
	return {
		"name": def["name"], "hp": def["hp"], "hp_max": def["hp"],
		"marks": int(def["marks"]) + int(Game.diff()["marks_mod"]), "agi": def["agi"], "med": 0,
		"weapon": def["weapon"], "ammo": int(w["mag"]),
		"inv": [], "ammo_store": {},
		"armor": float(def["armor"]), "sight": int(def["sight"]),
		"sprite": def["sprite"], "tint": def["tint"], "scale": float(def["scale"]),
		"kills": 0, "alive": true, "type": type, "alerted": false, "searched": false,
		"exp": int(def.get("exp", 1)),
	}


func _occupy(u, c: Vector3i) -> void:
	occupied[c] = u
	pathfinder.set_cell_blocked(c, true)


func _vacate(c: Vector3i) -> void:
	occupied.erase(c)
	# In 3D only walkable cells are AStar points at all; unblocking restores
	# walkability (the cell WAS walkable, otherwise nobody could have stood there).
	pathfinder.set_cell_blocked(c, false)
	# Crate cells stay blocked ALWAYS: should a unit ever stand on one (spawn
	# corner case), it must not make the crate walkable by moving away.
	if _is_crate_cell(c):
		pathfinder.set_cell_blocked(c, true)
	# Same guard for the locked cellar hatch: a unit that happens to stand on it
	# (base reinforcement) must not unbar the door by walking away.
	elif cellar_locked and c == cellar_door:
		pathfinder.set_cell_blocked(c, true)


## Crate/barrel cell: a walkable cover tile with an intact FLAG_DESTRUCT prop.
## Walls have begehbar=false and are therefore excluded (the W1 distinction).
func _is_crate_cell(c: Vector3i) -> bool:
	var t: Tac3DTile = grid.get_tile(c)
	return t != null and t.begehbar and t.cover > 0.0 and (t.flags & Tac3DTile.FLAG_DESTRUCT) != 0


func dl(t: float) -> void:
	if fast:
		return
	await get_tree().create_timer(t).timeout


## Warm tropical sun + sky/environment (ART PASS). Additive, fallback-safe.
## Shadows only when NOT fast (headless/bot need no shadow map).
func _setup_lighting() -> void:
	# --- Sun: slightly yellowish morning, visible cast shadows. ---
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Polish: sun lowered (-55 -> -45 degrees) = longer late-afternoon shadows.
	# Energy 1.15 -> 1.33 compensates for the shallower incidence on the ground
	# (sin55*1.15 ~ sin45*1.33), otherwise the pixel-tuned art-pass exposure tips over.
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-40.0), 0.0)
	sun.light_color = Color(1.0, 0.91, 0.74)   # warm, late sunlight
	sun.light_energy = 1.33
	if not fast:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		# 72x72 field -> long shadow range, tame acne via bias/normal bias.
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
	# ART PASS T7b: ambient lowered a lot (1.0->0.45), so the sun MODELS the scene
	# (shadow contrast) instead of flooding it flat and blowing bright textures
	# (wall/sand) out to white.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.6
	e.ambient_light_energy = 0.35

	# Filmic tonemap. ART PASS v2 T9: exposure 0.9->0.74. Pixel measurement showed
	# beach at 255/255/211 (R,G blown out) AND meadow at ~233/246 (near clipping,
	# washed towards yellow) -> the whole pipeline ran too hot. Lower exposure
	# pulls the beach out of clipping (a real sand tone) and makes the meadow richer/greener.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.74
	e.tonemap_white = 1.0

	# Polish: glow/bloom — available in the gl_compatibility renderer since Godot 4.3.
	# Threshold 1.0 = only true HDR peaks bloom (muzzle-flash/explosion light on
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

	# Warm haze for depth. gl_compatibility renders simple (non-volumetric) depth fog.
	# ART PASS v2 T8: CRITICAL — the ortho camera sits 200 units behind the pivot
	# (camera_rig cam.position.z=200), so EVERY piece of geometry sits at ~200
	# depth. At density 0.008 that yields 1-exp(-0.008*200)=~80 % fog EVERYWHERE ->
	# the whole scene drowns in yellow milk (no depth cue, just wash).
	# density 0.0009 -> ~1-exp(-0.18)=~16 % subtle base haze, distant parts of the
	# map minimally stronger -> atmosphere instead of frosted glass, real tropical colours survive.
	e.fog_enabled = true
	e.fog_light_color = Color(0.82, 0.80, 0.70)
	e.fog_density = 0.0009
	e.fog_sky_affect = 0.0

	env.environment = e
	add_child(env)


# ================================================================= Inventory helpers (1:1)

func inv_of(u) -> Array:
	return u.data["inv"]


func inv_count(u, id: String) -> int:
	var n := 0
	for it in inv_of(u):
		if String(it) == id:
			n += 1
	return n


func inv_take(u, id: String) -> bool:
	var inv: Array = inv_of(u)
	for i in inv.size():
		if String(inv[i]) == id:
			inv.remove_at(i)
			return true
	return false


func inv_add(u, id: String) -> bool:
	if inv_of(u).size() >= Db.INV_SLOTS:
		return false
	inv_of(u).append(id)
	return true


func mags_for(u) -> int:
	var cal := String(Db.weapon(u.data["weapon"])["cal"])
	var n := 0
	for it in inv_of(u):
		var d: Dictionary = Db.item(String(it))
		if String(d["kind"]) == "ammo" and String(d.get("cal", "")) == cal:
			n += 1
	return n


func _mag_item_for(cal: String) -> String:
	return "mag_" + cal


# ================================================================= Combat stats (1:1)

func shot_ap(u, aim := 0) -> int:
	return int(Db.weapon(u.data["weapon"])["ap"]) + int(Db.AIM["ap_step"]) * aim


## Experience level (1–6): mercs level up through kills, enemies are fixed.
func level_of(u) -> int:
	if u.is_merc:
		return mini(6, int(u.data.get("exp", 1)) + int(u.data.get("kills", 0)) / 2)
	return int(u.data.get("exp", 1))


# Port of tactical.gd:477-490 + height bonus (spec §6.2). Distance FLAT on (x,z).
# Extended (JA2): hit zone (zone) + stances (a shooter aims better from crouch/
# prone, crouched/prone targets are harder to hit). The defaults
# (zone="torso", both standing) leave the v2 formula EXACTLY unchanged.
func hit_chance(att, def, aim := 0, zone := "torso") -> int:
	var w: Dictionary = Db.weapon(att.data["weapon"])
	var d: float = att.flat().distance_to(def.flat())
	var ch := float(att.data["marks"]) + float(w["acc"])
	var rng := float(w["range"])
	if d <= rng:
		ch -= (d / rng) * 30.0
	else:
		ch -= 30.0 + (d - rng) * 10.0
	if bool(w["shotgun"]) and d < 4.0:
		ch += 15.0
	ch += float(Db.AIM["bonus_step"]) * aim
	ch -= cover_at(def.cell, att.cell) * 100.0
	# Firing downwards hits better: +8 per level of height advantage.
	ch += HEIGHT_HIT_BONUS * maxf(0.0, float(att.cell.y - def.cell.y))
	ch += float(Db.ZONES.get(zone, Db.ZONES["torso"])["hit_mod"])
	ch += float(Db.STANCES.get(att.stance, Db.STANCES["stand"])["att_bonus"])
	ch += float(Db.STANCES.get(def.stance, Db.STANCES["stand"])["def_mod"])
	return clampi(int(ch), 5, 95)


func cover_at(t: Vector3i, f: Vector3i) -> float:
	return vision.cover_at(t, f)


func throw_range(u) -> int:
	return 5 + int(u.data["agi"]) / 8


func grenade_valid(u, c: Vector3i) -> bool:
	if grid.get_tile(c) == null:
		return false
	var d: float = u.flat().distance_to(Tac3DVision.flat(c))
	return d <= float(throw_range(u)) and d >= 1.0 and vision.los(u.cell, c)


# ================================================================= Path / AP

# Movement cost of the TARGET tile per move type (MOVE_AP.get, fallback 2).
func step_ap(to: Vector3i) -> int:
	var t: Tac3DTile = grid.get_tile(to)
	if t == null:
		return 2
	return MOVE_AP.get(t.move_type, 2)


## Step cost for ONE unit: stance (crouch x1.5 / prone x2, integer arithmetic
## per step) and leg hits (x2) make movement more expensive. u=null = same as step_ap.
func step_ap_for(u, to: Vector3i) -> int:
	var c := step_ap(to)
	if u != null:
		var st: Dictionary = Db.STANCES.get(u.stance, Db.STANCES["stand"])
		c = c * int(st["move_num"]) / int(st["move_den"])
		if u.cripple_rounds > 0:
			c *= 2
	return c


func path_ap(cells: Array, u = null) -> int:
	var c := 0
	for i in range(1, cells.size()):
		var to: Vector3i = cells[i]
		c += step_ap_for(u, to)
	return c


# Port of tactical.gd:453-464 — cost per step via step_ap_for (u=null: same as v2).
func prefix_for_ap(cells: Array, ap: int, u = null) -> Array:
	var out: Array = []
	if cells.is_empty():
		return out
	out.append(cells[0])
	var c := 0
	for i in range(1, cells.size()):
		var to: Vector3i = cells[i]
		c += step_ap_for(u, to)
		if c > ap:
			break
		out.append(to)
	return out


# Port of tactical.gd:416-422 — unblock u.cell (guard pathfinder3d.gd:64), find path, block again.
func path_for(u, target: Vector3i) -> Array:
	if not grid.is_walkable(target) or occupied.has(target):
		return []
	pathfinder.set_cell_blocked(u.cell, false)
	var p := pathfinder.path_cells(u.cell, target)
	pathfinder.set_cell_blocked(u.cell, true)
	return p


# Port of tactical.gd:424-442 — neighbour fallback (4/8-cell ring, flat).
func path_toward(u, target: Vector3i) -> Array:
	if grid.is_walkable(target) and not occupied.has(target):
		var direct := path_for(u, target)
		if direct.size() > 1:
			return direct
	var best: Array = []
	var best_len := 999999
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var n: Vector3i = target + Vector3i(dx, 0, dz)
			if not grid.is_walkable(n) or occupied.has(n):
				continue
			var p := path_for(u, n)
			if p.size() > 1 and p.size() < best_len:
				best = p
				best_len = p.size()
	return best


# ================================================================= Vision / approach phase

# K2: test per TARGET CELL (NO neighbourhood pre-fill). For every living merc run
# vision.unit_sees(merc, enemy.cell) over ALL living enemies (real y), then set_seen.
func compute_vision() -> void:
	visible_cells = {}
	for m in mercs:
		var merc: Tac3DUnit = m
		if not merc.alive:
			continue
		for e in enemies:
			var enemy: Tac3DUnit = e
			if not enemy.alive:
				continue
			if visible_cells.has(enemy.cell):
				continue
			if unit_sees(merc, enemy.cell):   # stance-aware (prone enemies spotted later)
				visible_cells[enemy.cell] = true
	for e in enemies:
		var enemy2: Tac3DUnit = e
		enemy2.set_seen(enemy2.alive and visible_cells.has(enemy2.cell))
	# Cellar lid: fold the floor above the hideout open while a merc is down
	# there (Otto counts as captive, NOT as a merc -> the lid starts closed).
	if ground != null:
		var below := false
		for m2 in mercs:
			var mu: Tac3DUnit = m2
			if mu.alive and mu.cell.y < 0:
				below = true
				break
		ground.set_cellar_open(below)

	# Fog of war (SPEC §6): recomputed on movement only — compute_vision() already
	# runs after every step, shot, grenade and sector load. Single line on purpose:
	# with fog == null (bot/headless) the vision scan is never even evaluated.
	if fog != null: fog.refresh(vision.cells_seen_by_units(mercs))


## Stance-aware sight: PRONE targets are only spotted at a shortened distance
## (Db.PRONE_SPOT_MULT) — this makes crawling up on guards possible.
## Without a prone target it is identical to vision.unit_sees (the v2 formula).
func unit_sees(u, c: Vector3i) -> bool:
	var tgt = occupied.get(c, null)
	if tgt != null and tgt is Tac3DUnit and (tgt as Tac3DUnit).stance == "prone":
		var d := Tac3DVision.flat(u.cell).distance_to(Tac3DVision.flat(c))
		return d <= vision.sight_of(u, c) * Db.PRONE_SPOT_MULT and vision.los(u.cell, c)
	return vision.unit_sees(u, c)


func visible_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		var en: Tac3DUnit = e
		if en.alive and en.seen:
			out.append(en)
	return out


func _any_contact() -> bool:
	if visible_enemies().size() > 0:
		return true
	for e in enemies:
		var en: Tac3DUnit = e
		if not en.alive:
			continue
		for m in mercs:
			var merc: Tac3DUnit = m
			if merc.alive and unit_sees(en, merc.cell):
				return true
	return false


## First enemy contact: the approach phase ends, turn-based combat begins.
func start_combat() -> void:
	if combat_started:
		return
	combat_started = true
	no_contact_rounds = 0
	for u2 in units:
		var uu: Tac3DUnit = u2
		uu.ap = uu.ap_max
		uu.interrupt_used = false
	if hud != null:
		hud.banner("ENEMY CONTACT — turn-based combat!")
	# Phase 7 — combat sting + combat music (only when not fast, fallback-safe).
	if not fast:
		Sfx.play("interrupt", -2.0)
		Sfx.play_music("combat")
	_hud_refresh()


## 2 rounds without visual contact: back into exploration mode.
func _end_combat_mode() -> void:
	combat_started = false
	no_contact_rounds = 0
	for m in mercs:
		var merc: Tac3DUnit = m
		merc.ap = merc.ap_max
	# Phase 7 — back to the exploration music.
	if not fast:
		Sfx.play_music("exploration")
	_hud_refresh()


## Noise/sighting: alerts enemies within earshot of `center` (flat).
func alert_enemies(investigate: Vector3i, center: Vector3i, radius: float) -> void:
	noise_at = investigate
	for e in enemies:
		var en: Tac3DUnit = e
		if en.alive and Tac3DVision.flat(en.cell).distance_to(Tac3DVision.flat(center)) <= radius:
			en.data["alerted"] = true


## Sentry leash: the boss sticks (2), elites hold the manor (5), militia hunt freely (9999). Flat.
func _leash_for(u) -> float:
	if u == boss:
		return 2.0
	if not u.is_merc and String(u.data.get("type", "")).begins_with("elite"):
		return 5.0
	return 9999.0


# ================================================================= Actions (coroutines)

# Port of tactical.gd:513-590 — AP, leash, interrupts, contact, movement across levels.
## patient: when a cell is briefly blocked (group moving in parallel), wait a
## moment and retry instead of stopping dead immediately.
## halt_on_combat: abort as soon as combat starts DURING this move
## (group move: ONE visual contact stops the whole group, JA1 rule).
func do_move(u, cells: Array, patient := false, halt_on_combat := false) -> void:
	if cells.size() < 2 or battle_over:
		return
	var move_was_combat := combat_started
	busy = true
	_movers += 1
	# Legs move during movement. do_move has its OWN step loop and does NOT use
	# follow_path (which would otherwise play "walk") -> set it explicitly here,
	# otherwise the idle pose just glides along.
	# PRONE units crawl: NO walk clip (that would look like walking while lying
	# down), use the idle pose instead — the flat-tilted figure then "drags"
	# itself forward believably.
	if not fast:
		u.play_anim("idle" if u.stance == "prone" else "walk")
	var observers: Dictionary = {}
	var watchers: Array = enemies if u.is_merc else mercs
	for o in watchers:
		var ow: Tac3DUnit = o
		observers[ow] = ow.alive and unit_sees(ow, u.cell)
	var seen_before := visible_enemies().size()
	# Spotting: anyone already visible at the start does not trigger a new spot —
	# only enemies that enter the team's field of view DURING this move.
	var prev_seen: Dictionary = {}
	for pv in visible_enemies():
		var pv_u: Tac3DUnit = pv
		prev_seen[pv_u] = true
	for i in range(1, cells.size()):
		if battle_over or not u.alive or _transitioning:
			break
		var to: Vector3i = cells[i]
		# Sentry leash (boss: throne room, elites: manor). Flat.
		if Tac3DVision.flat(to).distance_to(Tac3DVision.flat(u.home)) > _leash_for(u):
			break
		# Group move: ONE enemy contact (by whoever) stops the WHOLE group.
		if halt_on_combat and not move_was_combat and combat_started:
			break
		var cst := step_ap_for(u, to)
		if u.ap < cst:
			break
		if occupied.has(to) and patient:
			# Group moving in parallel: a cell is often only BRIEFLY occupied (a
			# team mate is passing through) -> wait a moment instead of stopping dead.
			for retry in 3:
				await dl(0.22)
				if not occupied.has(to) or battle_over or not u.alive:
					break
		if occupied.has(to):
			break
		u.ap -= cst
		_vacate(u.cell)
		u.cell = to
		_occupy(u, to)
		if fast:
			u.set_cell(to)
		else:
			# Corner cutting ("smooth path"): the interim waypoint = MIDPOINT between
			# this and the NEXT cell -> 90-degree kinks become soft 45-degree cuts;
			# straight runs stay straight (midpoints are collinear). Only the last
			# cell is approached exactly; after the loop we snap to the logical cell
			# anyway (movement stop / interrupt mid-path).
			var wp := grid.cell_to_world(to) + Vector3(0.0, Unit3D.MODEL_Y_OFFSET, 0.0)
			if i < cells.size() - 1:
				var nx: Vector3i = cells[i + 1]
				wp = (grid.cell_to_world(to) + grid.cell_to_world(nx)) * 0.5 \
					+ Vector3(0.0, Unit3D.MODEL_Y_OFFSET, 0.0)
			# #1: the figure turns into its direction of travel (smoothly via Unit3D._process).
			u.face_toward(wp)
			# Polish: footstep sound by surface (2D pattern from tactical.gd) — also for
			# INVISIBLE enemies (noise is classic JA information). Dust, in contrast, ONLY
			# for visible units, otherwise particles would give away hidden positions.
			var st: Tac3DTile = grid.get_tile(to)
			if st != null and st.surface <= 2:
				Sfx.play_step(["grass", "wood", "stone"][st.surface])
			if juice != null and st != null and u.seen and not st.is_water():
				juice.dust_puff(grid.cell_to_world(to))
			var tw := create_tween()
			# Duration ~ distance -> constant speed (corner-cut segments are shorter).
			# Stance visibly slows things down: crouch x1.5, crawl x2.2 (Db.STANCES.tempo).
			var tempo: float = float(Db.STANCES.get(u.stance, Db.STANCES["stand"]).get("tempo", 1.0))
			tw.tween_property(u, "position", wp, maxf(0.05, 0.11 * tempo * u.position.distance_to(wp)))
			await tw.finished
		compute_vision()
		# SPEC v5 §2/§3.3: map edge during EXPLORATION. West edge of F4 -> sector change
		# to F3, all other edges -> "locked" banner. In F3 always a no-op.
		if u.is_merc and _handle_edge(u):
			break
		# Spotting: enemies that newly entered the team's field of view (whether the
		# merc or the enemy moved). The movement stop happens further below; the
		# presentation comes AFTER start_combat, so the name banner overwrites the
		# ENEMY CONTACT banner (not the other way round).
		var newly: Array = []
		for nv in visible_enemies():
			var nv_u: Tac3DUnit = nv
			if not prev_seen.has(nv_u):
				newly.append(nv_u)
				prev_seen[nv_u] = true
		# The approach phase ends at the first visual contact.
		var contact_now := false
		if not combat_started and u.is_merc and _any_contact():
			contact_now = true
			start_combat()
		if not newly.is_empty():
			_on_enemy_spotted(u, newly)
		# Interrupts: observers who just gained sight open fire (chance scales with experience).
		for o in watchers:
			if battle_over or not u.alive:
				break
			var obs: Tac3DUnit = o
			if not obs.alive or obs.interrupt_used:
				continue
			var sees_now: bool = unit_sees(obs, u.cell)
			if sees_now and not bool(observers.get(obs, false)):
				observers[obs] = true
				var owp: Dictionary = Db.weapon(obs.data["weapon"])
				var dd := Tac3DVision.flat(obs.cell).distance_to(Tac3DVision.flat(u.cell))
				if obs.ap >= int(owp["ap"]) and dd <= float(owp["range"]) + 2.0 and int(obs.data["ammo"]) > 0:
					var chance := 15 + level_of(obs) * 7 + int(obs.data["agi"]) / 6
					if randi_range(1, 100) <= chance:
						obs.interrupt_used = true
						if not obs.is_merc:
							obs.data["alerted"] = true
						await dl(0.35)
						await shoot(obs, u, true)
		if contact_now:
			await check_boss_dialog()
			break
		# Movement stop on spotting: EVERY newly discovered enemy stops the move
		# (set-based via `newly`; the old counter comparison stays as a safety net).
		if u.is_merc and (not newly.is_empty() or visible_enemies().size() > seen_before):
			if await check_boss_dialog():
				break
			break
		if u.is_merc:
			if await check_boss_dialog():
				break
	# Sector change triggered: `u` and half the map are about to be torn down —
	# NO trailing tween, no more compute_vision on dead references. load_sector
	# resets busy/_movers itself.
	if _transitioning:
		_movers = maxi(0, _movers - 1)
		busy = _movers > 0
		return
	if not fast and u.alive:
		# Corner-cut follow-up: the last tween can end on a MIDPOINT (movement stop
		# or interrupt mid-path) -> pull the figure exactly onto its logical cell,
		# otherwise it stands half beside its tile.
		var endp: Vector3 = grid.cell_to_world(u.cell) + Vector3(0.0, Unit3D.MODEL_Y_OFFSET, 0.0)
		if u.position.distance_to(endp) > 0.03:
			var tw_end := create_tween()
			tw_end.tween_property(u, "position", endp, maxf(0.05, 0.11 * u.position.distance_to(endp)))
			await tw_end.finished
		u.play_anim("idle")   # move finished -> back to the rest pose (not on death/hit)
	if u.is_merc and not combat_started:
		u.ap = u.ap_max   # approach phase: movement is free
	# Parallel group move: only release busy once the LAST mover is done.
	_movers = maxi(0, _movers - 1)
	busy = _movers > 0
	compute_vision()
	_hud_refresh()


## Spotting event (the "enemy spotted" feature): the move stops (do_move), the enemy
## is marked with a red pulsing ring (NO more "!"), the camera glides over, and the
## SPOTTER is shown as a portrait overlay in the HUD (JA style: the face speaks) —
## audible via its own spot voice line (<id>_spot, baked; fallback <id>_quote).
## Pure presentation: fast/bot => no-op; touches no combat formula.
func _on_enemy_spotted(mover, newly: Array) -> void:
	if fast or battle_over or newly.is_empty():
		return
	var first: Tac3DUnit = newly[0]
	# Spotter = the merc that moved, if HE can see the new enemy; otherwise the first
	# living merc with sight (the enemy stepped into SOMEBODY's field of view).
	var spotter: Tac3DUnit = null
	if mover != null and mover.is_merc and mover.alive and unit_sees(mover, first.cell):
		spotter = mover
	else:
		for m in mercs:
			var merc: Tac3DUnit = m
			if merc.alive and unit_sees(merc, first.cell):
				spotter = merc
				break
	if juice != null:
		for e in newly:
			var en: Tac3DUnit = e
			juice.spot_ping(en)
	if rig != null:
		rig.glide_to(grid.cell_to_world(first.cell))
	if spotter == null:
		return
	var line := "Enemy spotted!" if newly.size() == 1 else "%d enemies spotted!" % newly.size()
	if hud != null:
		hud.show_speaker(spotter, line)
	var vid := _voice_id(spotter) + "_spot"
	if not Sfx.has_voice(vid):
		vid = _voice_id(spotter) + "_quote"   # fallback: character catchphrase
	if Sfx.has_voice(vid):
		Sfx.play_voice(vid)


# Port of tactical.gd:592-652 — damage/buckshot/armor/height. Distance FLAT.
func shoot(att, def, interrupt := false) -> bool:
	if battle_over or not att.alive or not def.alive:
		return false
	var aim: int = aim_level if (att.is_merc and not interrupt) else 0
	# JA2 hit zone: only deliberate player shots; AI/interrupts = torso.
	var zone: String = aim_zone if (att.is_merc and not interrupt) else "torso"
	var w: Dictionary = Db.weapon(att.data["weapon"])
	var cost := shot_ap(att, aim)
	if att.ap < cost:
		return false
	if int(att.data["ammo"]) <= 0:
		if att.ap >= cost + int(w["reload"]) and _can_reload(att):
			do_reload(att)
		else:
			return false
	if not combat_started:
		start_combat()
	att.ap -= cost
	# JA2: accumulated aim applies to ONE shot and expires afterwards.
	if att.is_merc and not interrupt:
		aim_level = 0
		_aim_target = null
	att.data["ammo"] = int(att.data["ammo"]) - 1
	# Phase 5: the shooter visibly fires. Own not-fast block (independent of the juice object);
	# play_anim is null-/fallback-safe (no-op without an AnimationPlayer, or on the capsule).
	if not fast:
		att.face_toward(grid.cell_to_world(def.cell))
		att.play_anim("shoot")
	var investigate: Vector3i = att.cell if att.is_merc else def.cell
	alert_enemies(investigate, att.cell, 9.0)
	if not att.is_merc:
		att.data["alerted"] = true
	if att.is_merc:
		Game.stats["shots"] = int(Game.stats["shots"]) + 1
	var ch := hit_chance(att, def, aim, zone)
	var hit := randi_range(1, 100) <= ch
	# --- Phase 4 (juice): shot FX, independent of whether it hits. Gated (fast/null). ---
	if not fast and juice != null:
		var from_w: Vector3 = att.global_position + Vector3.UP * 1.3
		var to_w: Vector3 = def.global_position + Vector3.UP * 1.1
		var flat_dir: Vector3 = def.global_position - att.global_position
		flat_dir.y = 0.0
		flat_dir = flat_dir.normalized() if flat_dir.length() > 0.001 else Vector3.FORWARD
		var muzzle: Vector3 = from_w + flat_dir * 0.45
		juice.muzzle_flash(muzzle, flat_dir)
		juice.tracer(muzzle, to_w)
		# Polish: the casing ejects (ground height of the shooter's cell, shotgun = red).
		juice.shell_casing(muzzle, flat_dir, grid.cell_to_world(att.cell).y, bool(w["shotgun"]))
		rig.add_trauma(Juice3D.TRAUMA_SHOT)
		Sfx.play(String(w["snd"]), 2.5 if String(w["snd"]) == "shot_r" else (2.0 if bool(w["shotgun"]) else 1.0))
	await dl(0.13)
	if hit:
		if att.is_merc:
			Game.stats["hits"] = int(Game.stats["hits"]) + 1
		var dist: float = att.flat().distance_to(def.flat())
		var dmg := int(w["dmg"]) + randi_range(-int(w["var"]), int(w["var"]))
		if bool(w["shotgun"]) and dist > 3.0:
			dmg -= int((dist - 3.0) * 4.0)
		# JA2 zone: head x1.75 + half armor effect, legs x0.7. Torso (the default,
		# mult 1.0/pierce 0.0) computes EXACTLY as v2 — bot/AI stay unchanged.
		var zd: Dictionary = Db.ZONES.get(zone, Db.ZONES["torso"])
		dmg = int(float(dmg) * float(zd["dmg_mult"]))
		var armor_eff: float = float(def.data["armor"]) * (1.0 - float(zd["pierce"]))
		dmg = int(float(dmg) * (1.0 - armor_eff))
		dmg = maxi(1, dmg)
		def.hurt(dmg)
		# Leg hit: the target limps (double step cost); a heavy hit knocks it
		# to the ground. A head hit gets its own overlay.
		if def.alive and zone == "beine":
			def.cripple_rounds = maxi(def.cripple_rounds, Db.CRIPPLE_ROUNDS)
			if dmg >= Db.CRIPPLE_PRONE_DMG:
				set_stance(def, "prone", true)
			if not fast and juice != null:
				juice.float_text(def.global_position + Vector3.UP * 1.7, "LEG HIT!", Color(1.0, 0.62, 0.2))
		elif zone == "kopf" and not fast and juice != null:
			juice.float_text(def.global_position + Vector3.UP * 1.9, "HEADSHOT!", Color(1.0, 0.25, 0.2))
		# --- Phase 4 (juice): hit FX. hitstop is fire-and-forget (NEVER await it). ---
		if not fast and juice != null:
			var hit_w: Vector3 = def.global_position + Vector3.UP * 1.1
			var ground_w: Vector3 = grid.cell_to_world(def.cell)
			var killed: bool = not def.alive
			juice.hitstop(Juice3D.HITSTOP_KILL if killed else Juice3D.HITSTOP_HIT)
			rig.add_trauma(Juice3D.TRAUMA_KILL if killed else Juice3D.TRAUMA_HIT)
			juice.blood(hit_w, ground_w)
			juice.damage_number(def.global_position + Vector3.UP * 2.0, dmg, killed)
			juice.hit_flash(def)
			if def.alive:
				def.play_anim("hit")
			Sfx.play("hit", 1.0)
			if not def.is_merc:
				Sfx.play("pain_enemy", -2.0)
		if not def.alive:
			await on_death(att, def)
	elif not fast and juice != null:
		Sfx.play("miss", -6.0)
	compute_vision()
	_hud_refresh()
	return true


## #3 (new): free shot into a CELL with no target unit (ground / suppression). Consumes
## shot AP + ammo, deals NO damage. Juice (muzzle flash/tracer) as in shoot().
func shoot_ground(att, cell: Vector3i) -> void:
	if battle_over or not att.alive:
		return
	var w: Dictionary = Db.weapon(att.data["weapon"])
	var cost := shot_ap(att, 0)
	if att.ap < cost:
		return
	if int(att.data["ammo"]) <= 0:
		if att.ap >= cost + int(w["reload"]) and _can_reload(att):
			do_reload(att)
		else:
			return
	att.ap -= cost
	att.data["ammo"] = int(att.data["ammo"]) - 1
	if att.is_merc:
		Game.stats["shots"] = int(Game.stats["shots"]) + 1
	var to_cell: Vector3 = grid.cell_to_world(cell)
	if not fast:
		att.face_toward(to_cell)
		att.play_anim("shoot")
	alert_enemies(cell, att.cell, 9.0)   # noise draws enemies in (like a real shot)
	if not fast and juice != null:
		var from_w: Vector3 = att.global_position + Vector3.UP * 1.3
		var to_w: Vector3 = to_cell + Vector3.UP * 0.2
		var flat_dir: Vector3 = to_cell - att.global_position
		flat_dir.y = 0.0
		flat_dir = flat_dir.normalized() if flat_dir.length() > 0.001 else Vector3.FORWARD
		var muzzle: Vector3 = from_w + flat_dir * 0.45
		juice.muzzle_flash(muzzle, flat_dir)
		juice.tracer(muzzle, to_w)
		# Polish: the casing ejects (ground height of the shooter's cell, shotgun = red).
		juice.shell_casing(muzzle, flat_dir, grid.cell_to_world(att.cell).y, bool(w["shotgun"]))
		rig.add_trauma(Juice3D.TRAUMA_SHOT)
		Sfx.play(String(w["snd"]), 2.5 if String(w["snd"]) == "shot_r" else (2.0 if bool(w["shotgun"]) else 1.0))
	await dl(0.13)
	_refund_if_exploring(att)   # free during the approach phase (like movement)


func _can_reload(u) -> bool:
	if not u.is_merc:
		return true
	return mags_for(u) > 0


# Port of tactical.gd:659-674.
func do_reload(u) -> void:
	var w: Dictionary = Db.weapon(u.data["weapon"])
	if u.ap < int(w["reload"]) or int(u.data["ammo"]) >= int(w["mag"]):
		return
	if u.is_merc:
		if not inv_take(u, _mag_item_for(String(w["cal"]))):
			return
	u.ap -= int(w["reload"])
	u.data["ammo"] = int(w["mag"])
	_refund_if_exploring(u)
	_hud_refresh()


# Port of tactical.gd:676-703 — heals the worst-off neighbour (flat). heal = 15 + med/4.
func do_medkit(u) -> void:
	if inv_count(u, "medkit") <= 0 or u.ap < Db.MEDKIT_AP:
		return
	var target: Tac3DUnit = null
	var worst := 1.0
	for m in mercs:
		var merc: Tac3DUnit = m
		if not merc.alive:
			continue
		if merc != u and merc.flat().distance_to(u.flat()) > 1.6:
			continue
		var frac := float(merc.hp()) / float(merc.hp_max())
		if frac < 1.0 and frac < worst:
			worst = frac
			target = merc
	if target == null:
		return
	u.ap -= Db.MEDKIT_AP
	inv_take(u, "medkit")
	var heal := 15 + int(u.data["med"]) / 4
	target.data["hp"] = mini(target.hp_max(), target.hp() + heal)
	_refund_if_exploring(u)
	_hud_refresh()


# Port of tactical.gd:705-723 — swap the held weapon (SWAP_AP), stashing its ammo.
func do_swap(u, slot: int) -> void:
	var inv: Array = inv_of(u)
	if slot < 0 or slot >= inv.size() or u.ap < Db.SWAP_AP:
		return
	var id := String(inv[slot])
	if String(Db.item(id)["kind"]) != "weapon":
		return
	u.ap -= Db.SWAP_AP
	var old := String(u.data["weapon"])
	u.data["ammo_store"][old] = int(u.data["ammo"])
	inv[slot] = old
	u.data["weapon"] = id
	u.data["ammo"] = int(u.data["ammo_store"].get(id, 0))
	# Swap the visible weapon model in the hand too (pistol <-> long gun).
	u.refresh_weapon()
	_refund_if_exploring(u)
	_hud_refresh()


# Port of tactical.gd:725-795 — radius is flat; W1: FLAG_DESTRUCT only affects walkable
# cover tiles (cover>0) -> cover=0 (no wall destruction, safe for Pathfinder3D).
func do_grenade(u, c: Vector3i) -> void:
	if battle_over or inv_count(u, "granate") <= 0 or u.ap < int(Db.GRENADE["ap"]) or not grenade_valid(u, c):
		return
	busy = true
	mode = "move"
	if not combat_started:
		start_combat()
	inv_take(u, "granate")
	u.ap -= int(Db.GRENADE["ap"])
	alert_enemies(u.cell, c, 12.0)
	if not fast:
		u.face_toward(grid.cell_to_world(c))
		u.play_anim("throw")
		Sfx.play("throw")
	# Wind-up: the grenade only leaves the hand at the end of the arm motion.
	await dl(0.35)
	# --- The visible grenade arcs towards the target tile (juice, gated). ---
	if not fast and juice != null:
		var hand: Vector3 = u.global_position + Vector3.UP * 1.5
		var flight: float = juice.grenade_throw(hand, grid.cell_to_world(c) + Vector3.UP * 0.15)
		await dl(flight)
	# --- Phase 4 (juice): explosion FX on impact. Gated. ---
	if not fast and juice != null:
		var boom_w: Vector3 = grid.cell_to_world(c)
		juice.explosion(boom_w, float(Db.GRENADE["radius"]))
		juice.hitstop(Juice3D.HITSTOP_EXPLOSION)
		rig.add_trauma(Juice3D.TRAUMA_EXPLOSION)
		Sfx.play("explosion", 4.0)
	var radius: float = float(Db.GRENADE["radius"]) + 0.1
	for other in units.duplicate():
		var ot: Tac3DUnit = other
		if not ot.alive:
			continue
		var d := ot.flat().distance_to(Tac3DVision.flat(c))
		if d <= radius:
			var dmg := int(lerpf(float(Db.GRENADE["dmg"]), float(Db.GRENADE["dmg_edge"]), clampf(d / radius, 0, 1)))
			dmg += randi_range(-4, 4)
			dmg = maxi(1, dmg)
			ot.hurt(dmg)
			# --- Phase 4 (juice): damage number + blood per victim. Gated. ---
			if not fast and juice != null:
				juice.damage_number(ot.global_position + Vector3.UP * 2.0, dmg, not ot.alive)
				juice.blood(ot.global_position + Vector3.UP * 1.1, grid.cell_to_world(ot.cell))
			if not ot.alive:
				await on_death(u, ot)
			if battle_over:
				break
	# W1: cover destruction only on walkable FLAG_DESTRUCT tiles with cover>0.
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var cc: Vector3i = c + Vector3i(dx, 0, dz)
			if Vector2(dx, dz).length() > radius:
				continue
			var t: Tac3DTile = grid.get_tile(cc)
			if t != null and t.begehbar and t.cover > 0.0 and (t.flags & Tac3DTile.FLAG_DESTRUCT) != 0:
				t.cover = 0.0
				t.flags = t.flags & ~Tac3DTile.FLAG_DESTRUCT
				looted[cc] = true
	await dl(0.3)
	busy = false
	compute_vision()
	_hud_refresh()


## Exploration mode: actions cost nothing — refill AP immediately.
func _refund_if_exploring(u) -> void:
	if not combat_started and u.is_merc:
		u.ap = u.ap_max


## Searching: crates (FLAG_DESTRUCT cover) and fallen enemies (JA1 looting).
func search_target_at(c: Vector3i) -> String:
	var t: Tac3DTile = grid.get_tile(c)
	if t == null:
		return ""
	if (t.flags & Tac3DTile.FLAG_DESTRUCT) != 0 and not looted.has(c):
		return "crate"
	if corpses.has(c):
		var e: Tac3DUnit = corpses[c]
		if not e.is_merc and not bool(e.data.get("searched", false)):
			return "corpse"
	return ""


# Port of tactical.gd:815-852 — crate/corpse, SEARCH_AP, Db.roll_loot.
# Polish: audible/visible feedback (2D pattern tactical.gd:818-849) — looting used
# to run SILENTLY and therefore felt non-existent. Core logic and the loot_rng
# call order are unchanged (determinism of the bot tests!).
func do_search(u, c: Vector3i) -> void:
	var kind := search_target_at(c)
	if kind == "" or u.flat().distance_to(Tac3DVision.flat(c)) > 1.6 or u.ap < Db.SEARCH_AP:
		if not fast:
			Sfx.play("ui_error")
		return
	u.ap -= Db.SEARCH_AP
	if not fast:
		Sfx.play("search", -4.0)
		u.face_toward(grid.cell_to_world(c))
		u.play_anim("loot")   # interact clip; returns to idle via _on_anim_finished
	var found: Array = []
	if kind == "crate":
		looted[c] = true
		if loot_rng.randf() >= 0.15:
			var n := loot_rng.randi_range(int(Game.diff()["loot_min"]), int(Game.diff()["loot_max"]))
			for k in n:
				found.append(Db.roll_loot(loot_rng))
	else:
		var e: Tac3DUnit = corpses[c]
		e.data["searched"] = true
		# SPEC v5 §3.3.3 — the guard posted at the hatch carries the cellar key.
		# Appended FIRST so it claims the first free pack slot; the door opens
		# either way (see _unlock_cellar), so a full pack can never strand anyone.
		if bool(e.data.get("cellar_key", false)):
			e.data["cellar_key"] = false
			cellar_key_taken = true
			found.append("cellar_key")
			_unlock_cellar("Cellar key recovered — the storehouse hatch is open.")
		var cal := String(Db.weapon(e.data["weapon"])["cal"])
		var r := loot_rng.randf()
		if r < 0.4:
			found.append(_mag_item_for(cal))
		elif r < 0.55:
			found.append("granate")
	if found.is_empty() and not fast and juice != null:
		juice.float_text(grid.cell_to_world(c) + Vector3.UP * 1.2, "Nothing found", Color(0.75, 0.72, 0.6))
	var fi := 0
	for id in found:
		if inv_add(u, String(id)):
			Game.stats["loot"] = int(Game.stats["loot"]) + 1
			if not fast and juice != null:
				juice.float_text(u.global_position + Vector3.UP * (2.0 + 0.35 * fi), "+ " + String(Db.item(String(id))["name"]), Color(0.5, 0.9, 0.45))
				Sfx.play("ui_confirm", -6.0)
			fi += 1
		else:
			if not fast and juice != null:
				juice.float_text(u.global_position + Vector3.UP * (2.0 + 0.35 * fi), "Inventory full!", Color(1.0, 0.6, 0.4))
			break
	_refund_if_exploring(u)
	_hud_refresh()


# Port of tactical.gd:854-895 — XP/level-up, boss, victory/defeat.
func on_death(killer, dead) -> void:
	# #2: remove the fallen from the multi-selection (reset the ring highlight).
	dead.set_group_highlight(false)
	selection.erase(dead)
	dead.die_visual()
	# --- Phase 4 (juice): death reaction (anim + trauma + pain sound). Gated. ---
	if not fast and juice != null:
		dead.play_anim("death")
		rig.add_trauma(Juice3D.TRAUMA_KILL)
		rig.kill_zoom_punch()   # polish: short zoom kick on the kill (after the hitstop)
		if dead.is_merc:
			var vid := _voice_id(dead) + "_pain"   # Otto -> walross_pain
			if Sfx.has_voice(vid):
				Sfx.play_voice(vid)
			else:
				Sfx.play("death_m")
	_vacate(dead.cell)
	if not dead.is_merc:
		corpses[dead.cell] = dead
	if dead.is_merc:
		Game.stats["fallen"].append(dead.display_name())
		var any := false
		for m in mercs:
			var merc: Tac3DUnit = m
			if merc.alive:
				any = true
				break
		if selected == dead:
			for m in mercs:
				var merc2: Tac3DUnit = m
				if merc2.alive:
					selected = merc2
					break
		_hud_refresh()
		if not any:
			await end_battle("defeat")
			return
	else:
		if killer != null and killer.is_merc:
			var lvl_before := level_of(killer)
			killer.data["kills"] = int(killer.data["kills"]) + 1
			if level_of(killer) > lvl_before:
				killer.data["marks"] = mini(95, int(killer.data["marks"]) + 2)
		# SPEC v5 §3.3.3 — the keyholder falls, the barred hatch falls with him.
		# This is the deadlock-proof path: the cellar can NEVER stay shut.
		if bool(dead.data.get("cellar_key", false)):
			_unlock_cellar("The keyholder is down — the storehouse hatch is open.")
		if dead == boss:
			await _boss_defeated()
			return
		if not _any_enemy_alive():
			# SPEC v5 §2: in the LANDING ZONE (F4) a cleared sector does NOT end the
			# demo — the squad moves on westwards. Victory exists only in the target
			# sector F3 (unchanged there: boss, resp. last enemy).
			if sector == "F4":
				if hud != null:
					hud.banner("Landing zone clear — move west to Rookhaven.", 2.4)
			elif _rescue_pending():
				# SPEC v5 §3.3: the demo may NOT end before the rescue. Keep play
				# running and steer the squad to the cellar instead.
				_nag_rescue()
			else:
				await end_battle("victory")


# Port of tactical.gd:897-913 — the boss falls, the remaining militia surrenders, victory.
func _boss_defeated() -> void:
	await dl(1.0)
	var rest := 0
	for e in enemies:
		var en: Tac3DUnit = e
		if en.alive:
			en.alive = false
			en.data["alive"] = false
			en.set_seen(true)
			_vacate(en.cell)
			rest += 1
	if rest > 0:
		await dl(1.2)
	# SPEC v5 §3.3: rescue -> dialogue -> base live -> end card. A cleared village
	# with Tobias still locked up does NOT roll the end card.
	if _rescue_pending():
		_nag_rescue()
		return
	await end_battle("victory")


## The demo may not end before the rescue (SPEC v5 §3.3). In the bot/headless run
## (`fast`) the OLD behaviour stands — a cleared F3 wins — because the headless bot
## never descends into the cellar, and an ungateable victory there would mean an
## endless run. `captive != null` additionally scopes the gate to a map that
## actually holds Tobias.
func _rescue_pending() -> bool:
	if fast:
		return false
	return captive != null and not Game.otto_freed


## Village clear, Tobias still locked up: banner + objective beacon on the hatch,
## and — with nobody left alive to hold the key — the door falls open. So the
## player is never left without a way forward.
func _nag_rescue() -> void:
	if _has_cellar_door() and cellar_locked and not _any_enemy_alive():
		_unlock_cellar("")
	if hud != null:
		hud.banner("Village clear — Tobias Rook is still locked in the storehouse cellar.", 3.2)
	_show_objective(_rescue_marker_cell(), Color(0.35, 0.85, 1.0))


## Where the "go rescue him" beacon sits: the hatch if this sector has one,
## otherwise the captive himself.
func _rescue_marker_cell() -> Vector3i:
	if _has_cellar_door():
		return cellar_door
	if captive != null:
		return captive.cell
	return NO_CELL


## Opens the cellar door for good (key looted, guard down, or breached). Idempotent.
func _unlock_cellar(msg: String) -> void:
	if not _has_cellar_door() or not cellar_locked:
		return
	cellar_locked = false
	if pathfinder != null and not occupied.has(cellar_door):
		pathfinder.set_cell_blocked(cellar_door, false)
	Game.mark_door_open(sector, "cellar")
	if hud != null and msg != "":
		hud.banner(msg, 2.6)
	if not fast:
		Sfx.play("ui_confirm", -3.0)
	_show_objective(_rescue_marker_cell(), Color(0.35, 0.85, 1.0))


## SPEC v5 §3.3.3 — the alternative to the key: force the hatch at adjacency.
## Costs BREACH_AP and is LOUD (alerts the militia in earshot).
func breach_cellar_door(u) -> bool:
	if u == null or not u.alive or not _has_cellar_door() or not cellar_locked:
		return false
	if u.cell.y != cellar_door.y or u.flat().distance_to(Tac3DVision.flat(cellar_door)) > 1.6:
		return false
	if u.ap < BREACH_AP:
		if hud != null:
			hud.banner("Not enough AP to breach the door (%d needed)." % BREACH_AP)
		return false
	u.ap -= BREACH_AP
	if not fast:
		u.face_toward(grid.cell_to_world(cellar_door))
		u.play_anim("loot")
		Sfx.play("search", -2.0)
	alert_enemies(u.cell, u.cell, 9.0)   # breaching a door is not subtle
	_unlock_cellar("Cellar door breached — the way down is open.")
	_refund_if_exploring(u)
	_hud_refresh()
	return true


# Port of tactical.gd:915-925.
func end_battle(result: String) -> void:
	if battle_over:
		return
	battle_over = true
	busy = false
	Game.mission_result = result
	Game.stats["turns"] = turn
	# FIX F2: time_scale is process-global. Hard-reset it to 1.0 before the goto/scene
	# change (belt and braces against a hitstop leaking into the end screen).
	Engine.time_scale = 1.0
	await dl(1.0)
	battle_finished.emit(result)
	if not fast:
		_main().call_deferred("goto", "end")


# ================================================================= Commander sighting (LOGIC only)

## First sighting of the Helix commander. SPEC v5 §3.2 CUTS the warlord boss fight
## and its dialogue scene from the demo, so this no longer opens the modal — it
## keeps only the LOGIC the test harness asserts on (`Game.boss_dialog_seen` set
## exactly once, alert spread, return true on the first sighting) plus a cheap
## banner. `combat_hud.show_boss_dialog()` is deliberately never called any more.
func check_boss_dialog() -> bool:
	if Game.boss_dialog_seen or battle_over or boss == null or not boss.alive:
		return false
	if not visible_cells.has(boss.cell):
		return false
	Game.boss_dialog_seen = true
	boss.data["alerted"] = true
	alert_enemies(_nearest_merc_cell(boss.cell), boss.cell, 9.0)
	if hud != null:
		hud.banner("Helix commander sighted — he is holding the manor.", 2.4)
	await dl(0.2)
	return true


func _nearest_merc_cell(from: Vector3i) -> Vector3i:
	var best := Vector3i(-1, 0, -1)
	var bd := 999999.0
	for m in mercs:
		var merc: Tac3DUnit = m
		if not merc.alive:
			continue
		var d := Tac3DVision.flat(from).distance_to(merc.flat())
		if d < bd:
			bd = d
			best = merc.cell
	return best


# ================================================================= Enemy phase / round

# Port of tactical.gd:1061-1101 — enemy phase (ai.act per enemy), round change, exploration reset.
func end_turn() -> void:
	if busy or not player_turn or battle_over:
		return
	if not combat_started:
		return
	player_turn = false
	busy = true
	mode = "move"
	_hud_refresh()
	for e in enemies:
		if battle_over:
			break
		var en: Tac3DUnit = e
		if en.alive:
			await ai.act(en)
	if not battle_over:
		turn += 1
		for m in mercs:
			var merc: Tac3DUnit = m
			merc.ap = merc.ap_max
			merc.interrupt_used = false
			if merc.cripple_rounds > 0:
				merc.cripple_rounds -= 1
		for e in enemies:
			var en2: Tac3DUnit = e
			en2.ap = en2.ap_max
			en2.interrupt_used = false
			if en2.cripple_rounds > 0:
				en2.cripple_rounds -= 1
		player_turn = true
		compute_vision()
		await check_boss_dialog()
		# 2 rounds without visual contact -> back into exploration mode.
		if _any_contact():
			no_contact_rounds = 0
		else:
			no_contact_rounds += 1
		if no_contact_rounds >= 2:
			_end_combat_mode()
	busy = false
	_hud_refresh()


# ================================================================= Smoke bot

# Port of tactical.gd:1947-2010 — the bot plays until victory/abort. Coroutine.
func auto_battle() -> String:
	var outer := 0
	while not battle_over and outer < 300:
		outer += 1
		if outer % 10 == 0:
			var left := 0
			for e in enemies:
				if e.alive:
					left += 1
			print("SMOKE3D: round %d — enemies left: %d" % [turn, left])
		for m in mercs:
			if battle_over:
				break
			var merc: Tac3DUnit = m
			if not merc.alive:
				continue
			var inner := 0
			var acted := true
			while acted and inner < 24 and merc.alive and not battle_over:
				inner += 1
				acted = false
				var w: Dictionary = Db.weapon(merc.data["weapon"])
				if inv_count(merc, "granate") > 0 and merc.ap >= int(Db.GRENADE["ap"]):
					var gt := _bot_grenade_target(merc)
					if gt.x > -50:
						await do_grenade(merc, gt)
						acted = true
						continue
				var best: Tac3DUnit = null
				var bch := 0
				for e in visible_enemies():
					var en: Tac3DUnit = e
					if vision.los(merc.cell, en.cell):
						var ch := hit_chance(merc, en)
						if ch > bch:
							bch = ch
							best = en
				if best != null and merc.ap >= int(w["ap"]):
					if int(merc.data["ammo"]) <= 0:
						if merc.ap >= int(w["reload"]) and _can_reload(merc):
							do_reload(merc)
							acted = true
							continue
					elif bch >= 18:
						await shoot(merc, best)
						acted = true
						continue
				if inv_count(merc, "medkit") > 0 and merc.ap >= Db.MEDKIT_AP and merc.hp() * 2 < merc.hp_max():
					do_medkit(merc)
					acted = true
					continue
				var tgt := _nearest_alive_enemy_cell(merc.cell)
				if tgt.x >= 0 and merc.ap >= 4:
					var p := path_toward(merc, tgt)
					if p.size() > 1:
						var pre := _bot_trim_to_cover(prefix_for_ap(p, maxi(2, merc.ap - int(w["ap"]))))
						if pre.size() > 1:
							await do_move(merc, pre)
							acted = true
							continue
		if battle_over:
			break
		await end_turn()
	if not battle_over:
		await end_battle("abort")
	return Game.mission_result


func _bot_grenade_target(m) -> Vector3i:
	for e in visible_enemies():
		var en: Tac3DUnit = e
		if not grenade_valid(m, en.cell):
			continue
		var friendly := false
		for mm in mercs:
			var merc: Tac3DUnit = mm
			if merc.alive and merc.flat().distance_to(en.flat()) <= float(Db.GRENADE["radius"]) + 0.2:
				friendly = true
				break
		if friendly:
			continue
		if en == boss:
			return en.cell
		var cluster := 0
		for e2 in enemies:
			var en2: Tac3DUnit = e2
			if en2.alive and en2.flat().distance_to(en.flat()) <= float(Db.GRENADE["radius"]):
				cluster += 1
		if cluster >= 2:
			return en.cell
	return Vector3i(-99, 0, -99)


func _bot_trim_to_cover(p: Array) -> Array:
	if p.size() <= 2:
		return p
	var lim := maxi(2, p.size() - 5)
	for i in range(p.size() - 1, lim - 1, -1):
		var c: Vector3i = p[i]
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dz == 0:
					continue
				var n: Vector3i = c + Vector3i(dx, 0, dz)
				var t: Tac3DTile = grid.get_tile(n)
				if t != null and t.cover > 0.0:
					return p.slice(0, i + 1)
	return p


func _nearest_alive_enemy_cell(from: Vector3i) -> Vector3i:
	var best := Vector3i(-1, 0, -1)
	var bd := 999999.0
	for e in enemies:
		var en: Tac3DUnit = e
		if not en.alive:
			continue
		var d := Tac3DVision.flat(from).distance_to(en.flat())
		if d < bd:
			bd = d
			best = en.cell
	return best


# ================================================================= Interactive (HUD/mouse)

## Null-guarded refresh wrapper. In fast/bot mode hud==null -> no-op (regression guard).
func _hud_refresh() -> void:
	if hud != null:
		hud.refresh()


func _can_act() -> bool:
	return selected != null and selected.alive and player_turn and not busy


func ui_select_slot(i: int) -> void:
	if i >= 0 and i < mercs.size():
		ui_select(mercs[i])


func ui_select(u) -> void:
	if u == null or not u.is_merc or not u.alive:
		return
	# Captive and villagers are is_merc=true but NOT squad members — they must
	# never become the selected unit (a click on one would otherwise hijack the
	# selection). Every legitimate caller passes a member of `mercs`.
	if not mercs.has(u):
		return
	if selected == u and selection.size() <= 1:
		ui_inventory()   # clicking the already selected merc opens the inventory (JA1)
		return
	selected = u
	mode = "move"
	aim_zone = "torso"   # JA2: the zone choice is per merc selection, it does not carry over
	_set_selection([u])   # a single click dissolves the multi-selection
	# Phase 7 — selection quip (Otto=walross via _voice_id; otherwise <id>_select). Only when not fast.
	if not fast:
		Sfx.play_voice(_voice_id(u) + "_select")
	if picker != null:
		picker.set_active_level(u.cell.y)   # resolve clicks/hover on the merc's level
	_hud_refresh()


## #2: set the multi-selection + highlight the mercs' ground rings accordingly.
func _set_selection(list: Array) -> void:
	selection = list
	for m in mercs:
		var mu: Tac3DUnit = m
		mu.set_group_highlight(selection.size() > 1 and selection.has(mu))


## #2: box selection — every living merc whose screen position lies inside the box.
func _box_select(r: Rect2) -> void:
	if battle_over or rig == null or rig.cam == null:
		return
	# Tiny box (a wobbly click) -> treat it as a click, not as an empty selection.
	if r.size.x < 4.0 and r.size.y < 4.0:
		_handle_click()
		return
	var hits: Array = []
	for m in mercs:
		var mu: Tac3DUnit = m
		if not mu.alive:
			continue
		var sp := rig.cam.unproject_position(mu.global_position + Vector3.UP * 0.9)
		if r.has_point(sp):
			hits.append(mu)
	if hits.is_empty():
		return   # nothing inside the box -> leave the selection unchanged
	selected = hits[0]
	mode = "move"
	_set_selection(hits)
	if picker != null:
		picker.set_active_level(selected.cell.y)
	if not fast:
		if hits.size() > 1:
			Sfx.play("ui_confirm", -8.0)
		else:
			Sfx.play_voice(_voice_id(selected) + "_select")
	_hud_refresh()


func ui_reload() -> void:
	if _can_act():
		do_reload(selected)
	_hud_refresh()


func ui_medkit() -> void:
	if _can_act():
		do_medkit(selected)
	_hud_refresh()


func ui_aim() -> void:
	var cap := aim_cap(selected) if selected != null else int(Db.AIM["max"])
	aim_level = (aim_level + 1) % (cap + 1)
	_hud_refresh()


## Set the stance. In combat every transition step costs Db.STANCE_AP
## (stand->prone = 2 steps); the approach phase is free. force=true (e.g. a heavy
## leg hit knocking the unit down) ignores AP. Updates the visuals.
func set_stance(u, s: String, force := false) -> bool:
	if u == null or not Db.STANCES.has(s) or u.stance == s:
		return u != null and u.stance == s
	if not force and combat_started:
		var steps: int = absi(Db.STANCE_ORDER.find(s) - Db.STANCE_ORDER.find(u.stance))
		var cost: int = Db.STANCE_AP * steps
		if u.ap < cost:
			return false
		u.ap -= cost
	u.stance = s
	u.set_stance_visual(s)
	return true


## Key C: cycle the selected merc's stance (stand->crouch->prone).
func ui_stance() -> void:
	if selected == null or not selected.alive or busy or not player_turn or battle_over:
		return
	var i: int = Db.STANCE_ORDER.find(selected.stance)
	var nxt: String = Db.STANCE_ORDER[(i + 1) % Db.STANCE_ORDER.size()]
	if set_stance(selected, nxt):
		if not fast:
			Sfx.play("ui_click")
	elif hud != null:
		hud.banner("Not enough AP to change stance.")
	_hud_refresh()
	_update_hover()


## Key T: cycle the hit zone (torso -> head -> legs).
func ui_zone() -> void:
	if battle_over:
		return
	var i: int = Db.ZONE_ORDER.find(aim_zone)
	aim_zone = Db.ZONE_ORDER[(i + 1) % Db.ZONE_ORDER.size()]
	if not fast:
		Sfx.play("ui_click")
	_hud_refresh()
	_update_hover()


## JA2: the maximum aim levels depend on the WEAPON (pistols 2, sawn-off shotgun 1).
## Falls back to the global Db.AIM["max"] if a weapon has no aim_max.
func aim_cap(u) -> int:
	if u == null:
		return int(Db.AIM["max"])
	return int(Db.weapon(u.data["weapon"]).get("aim_max", int(Db.AIM["max"])))


## JA2 aiming via right-click: click a visible enemy you have a line of fire to
## -> aim level +1 (the shot then costs +ap_step AP per level). Above the weapon
## maximum OR when the AP no longer suffice, the aim drops back to 0 (the
## rotating JA2 cursor). No AP is deducted for the click itself — the cost still
## sits entirely inside shot_ap().
func _rmb_aim() -> void:
	if busy or battle_over or not player_turn:
		return
	if selected == null or not selected.alive:
		return
	if hud != null and hud.modal_active:
		return
	var tgt: Tac3DUnit = occupied.get(hover_cell, null)
	if tgt == null or tgt.is_merc or not tgt.alive or not tgt.seen:
		return
	if not vision.los(selected.cell, tgt.cell):
		return
	if _aim_target != tgt:
		_aim_target = tgt
		aim_level = 0
	var nxt := aim_level + 1
	if nxt > aim_cap(selected) or shot_ap(selected, nxt) > selected.ap:
		aim_level = 0
	else:
		aim_level = nxt
	Sfx.play("ui_click")
	_hud_refresh()
	_update_hover()


func ui_grenade_mode() -> void:
	if not _can_act():
		return
	if inv_count(selected, "granate") <= 0 or selected.ap < int(Db.GRENADE["ap"]):
		return
	mode = "grenade" if mode != "grenade" else "move"
	_hud_refresh()


func ui_end_turn() -> void:
	if not combat_started:
		if hud != null:
			hud.banner("No enemy contact yet")
		return
	await end_turn()
	_hud_refresh()


func ui_inventory() -> void:
	if hud != null:
		hud.toggle_inventory()


func ui_menu() -> void:
	if hud != null:
		hud.toggle_pause()


# ================================================================= Phase 7: Otto / base / audio

## Voice id: Otto carries "voice"="walross" -> walross_*; everyone else falls back to
## their own id (no "voice" field). Used for the _select/_pain clips.
func _voice_id(u) -> String:
	return String(u.data.get("voice", u.data.get("id", "")))


## Interact (key F). Two beats, in this order:
##   1) free Tobias — ONLY from inside the cellar (K1: same level + flat-adjacent);
##      from the village surface (different level) it stays impossible.
##   2) breach the locked cellar door (SPEC v5 §3.3.3) when standing next to it.
func ui_interact() -> void:
	if not _can_act():
		return
	if captive != null and selected.cell.y == captive.cell.y \
	   and selected.flat().distance_to(captive.flat()) <= 1.6:
		await free_otto()
		return
	if breach_cellar_door(selected):
		return
	if hud != null:
		hud.banner("No target in reach to interact with.")


## The rescue = the core story beat. FIX W2: rebuild_slots() IMMEDIATELY after
## mercs/units.append, and NO _hud_refresh()/compute_vision() BEFORE it (otherwise
## an out-of-bounds in refresh, because mercs > _slots).
func free_otto() -> void:
	if captive == null or battle_over:
		return
	var otto := captive
	captive = null                       # reentrancy guard: only once
	otto.set_tint(otto.team_color())     # -> merc blue
	otto.ap = otto.ap_max
	mercs.append(otto)
	units.append(otto)
	if hud != null:
		hud.rebuild_slots()              # W2: rebuild the portrait columns (now 5), BEFORE any refresh
	Game.team.append(otto.data)          # deliberately bypasses TEAM_MAX (5th member)
	Game.otto_freed = true
	Game.base_unlocked = true
	_unlock_cellar("")                   # the hatch stays open from here on
	_hide_objective()                    # the rescue objective is done
	# SPEC v5 §3.3.5 — base is live: three villagers with shotguns show up in the
	# village core as militia set dressing.
	_spawn_villagers()
	# SPEC v5 §4.4: autosave on every sector transition PLUS after the rescue.
	# Deliberately NOT gated on `fast` — the save point is part of the flow.
	Game.sector = sector
	Game.save_game(Game.AUTOSAVE_SLOT, "Rescue · Sector %s" % sector)
	if not fast:
		Sfx.play_voice(_voice_id(otto) + "_select")   # walross_select
	if hud != null:
		hud.banner("TOBIAS ROOK FREED — The Hideout is ours.", 2.0)
	compute_vision()
	_hud_refresh()
	if not fast and hud != null:
		await hud.show_tobias_dialog()    # spec §3.4 — the three infos
		await hud.show_base_panel()       # home base menu (K3)
	# SPEC v5 §3.3 order: rescue -> dialogue -> base live -> end card. If the
	# village was already cleared, the demo ends HERE — the victory path in
	# on_death/_boss_defeated deliberately refused to fire before the rescue.
	if not battle_over and sector != "F4" and not _any_enemy_alive():
		await end_battle("victory")


## SPEC v5 §3.3.5 — the three Rookhaven villagers. Modelled on `captive`: neutral,
## no AI turn, NOT counted towards win/lose (they live in `villagers` only).
func _spawn_villagers() -> void:
	if not villagers.is_empty() or grid == null:
		return
	var cells := _villager_cells()
	for i in cells.size():
		var c: Vector3i = cells[i]
		var u := Tac3DUnit.new()
		u.fast = fast
		_units_root.add_child(u)
		u.setup_combat(grid, Db.villager_runtime(i), true, c)
		u.home = c
		u.set_tint(Color(0.85, 0.72, 0.35))   # villager ochre — friendly, not squad blue
		_occupy(u, c)
		villagers.append(u)


## Spawn cells for the villagers. A sibling package may add "villager_spawns" to
## the map data — used WHEN PRESENT and shaped as expected, otherwise we pick free
## walkable cells around the village core ourselves. So a late (or absent) landing
## of that change cannot break this path.
func _villager_cells() -> Array:
	var out: Array = []
	var taken: Dictionary = {}
	var want: int = Db.VILLAGERS.size()
	var supplied = meta.get("villager_spawns", null)
	if supplied is Array:
		for v in supplied:
			if not (v is Vector3i):
				continue
			var vc: Vector3i = v
			if taken.has(vc) or not _villager_cell_ok(vc):
				continue
			taken[vc] = true
			out.append(vc)
			if out.size() >= want:
				return out
	# Fallback: ring search around the village core (the cellar hatch sits in it).
	var anchor: Vector3i = cellar_door if _has_cellar_door() else Vector3i(grid.size_x / 2, 0, grid.size_z / 2)
	for radius in range(2, 10):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if absi(dx) != radius and absi(dz) != radius:
					continue   # outer ring of this radius only
				var c := Vector3i(anchor.x + dx, 0, anchor.z + dz)
				if taken.has(c) or not _villager_cell_ok(c):
					continue
				taken[c] = true
				out.append(c)
				if out.size() >= want:
					return out
	return out


func _villager_cell_ok(c: Vector3i) -> bool:
	if c.y != 0 or grid == null or c == cellar_door:
		return false
	return grid.is_walkable(c) and not occupied.has(c) \
		and not corpses.has(c) and not _is_crate_cell(c)


## Base action (K3): fully heal the squad. hp_max only, no formula change.
func base_heal_all() -> void:
	for m in mercs:
		var u: Tac3DUnit = m
		u.data["hp"] = u.hp_max()
	_hud_refresh()


## Base action (K3): resupply. Held weapon full + pack filled with magazines up to
## Db.INV_SLOTS. Integer arithmetic untouched (only mag/cal), no hit/AP formula altered.
func base_resupply_all() -> void:
	for m in mercs:
		var u: Tac3DUnit = m
		u.data["ammo"] = int(Db.weapon(u.data["weapon"])["mag"])
		var cal := String(Db.weapon(u.data["weapon"])["cal"])
		while inv_of(u).size() < Db.INV_SLOTS:
			inv_of(u).append("mag_" + cal)
	_hud_refresh()


# ---------------------------------------------------------- Base: stash / save / hire
# SPEC v5 §8.2 wants the base functions LIVE (heal / stash / save / hire), not
# stubbed. The Hideout is a legal save point: §4.4 allows saving "between fights",
# and the rescue has just ended one.

## Base action: put an item from a merc's pack into the stash that survives in
## the save (SPEC v5 §4.4 `base.stash`).
func base_stash_deposit(u, item: String) -> bool:
	if u == null or not inv_take(u, item):
		return false
	Game.stash_add(item)
	_hud_refresh()
	return true

## Base action: take an item back out of the stash. Fails (without losing the
## item) when the merc's pack is full — the stash entry is only removed once the
## item is safely in the pack.
func base_stash_withdraw(u, item: String) -> bool:
	var idx: int = Game.stash.find(item)
	if u == null or idx < 0:
		return false
	if not inv_add(u, item):
		return false
	Game.stash_take(idx)
	_hud_refresh()
	return true

## Base action: write the autosave, so the run survives a restart.
func base_save() -> bool:
	Game.sector = sector
	return Game.save_game(Game.AUTOSAVE_SLOT, "The Hideout · Sector %s" % sector)

## Candidates for base reinforcement: every A.I.M. merc not on the squad yet.
## Affordability is NOT filtered here — the UI greys those out so the player can
## see what a bigger budget would buy.
func base_hire_candidates() -> Array:
	var out: Array = []
	for m in Db.MERCS:
		var id := String(m["id"])
		if not Game.is_hired(id):
			out.append(id)
	return out

## Base action: hire a reinforcement through the laptop. The merc joins at once
## and walks in through The Hideout, so the player sees what they paid for.
func base_hire(id: String) -> bool:
	if battle_over or not Game.hire(id):
		return false
	var data: Dictionary = Game.team.back()
	var cell: Vector3i = _free_base_cell()
	if cell == Tac3DMapGen.NO_CELL:
		Game.fire(id)                    # refund — nowhere to put them
		return false
	var u := Tac3DUnit.new()
	u.fast = fast
	_units_root.add_child(u)
	u.setup_combat(grid, data, true, cell)
	_occupy(u, cell)
	units.append(u)
	mercs.append(u)
	if hud != null:
		hud.rebuild_slots()
	compute_vision()
	_hud_refresh()
	return true

## A free cell for a reinforcement: next to the squad, on the level they stand on
## (the cellar during the rescue). NO_CELL when nothing is free.
func _free_base_cell() -> Vector3i:
	var anchor: Vector3i = mercs[0].cell if not mercs.is_empty() else Vector3i.ZERO
	for radius in range(1, 6):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var c := anchor + Vector3i(dx, 0, dz)
				if grid.is_walkable(c) and not occupied.has(c) and not _is_crate_cell(c):
					return c
	return Tac3DMapGen.NO_CELL


# ================================================================= Objective marker (SPEC v5 §3.3.2)

# Cheap on-map cue: one floating beacon over the cell the squad should head for.
# gl_compatibility-safe (unshaded StandardMaterial3D, no Decal, no GPUParticles).
# Purely visual -> `fast`/bot builds nothing at all.
var _objective: MeshInstance3D = null
var _objective_mat: StandardMaterial3D = null
var _objective_y := 0.0
var _objective_t := 0.0


## Objective cue for the CURRENT sector: F4 points at the west exit (the player
## had no clue which edge was the way out), F3 clears it until the rescue is due.
func _refresh_objective() -> void:
	if fast:
		return
	if sector == "F4":
		_show_objective(_exit_marker_cell(), Color(1.0, 0.85, 0.35))
		if hud != null:
			hud.banner("Objective: head WEST — the exit leads to Sector F3, Rookhaven.", 3.0)
	else:
		_hide_objective()


## The west-exit cell to mark: the map's own `goal` when it is usable, otherwise
## the exit cell closest to the squad.
func _exit_marker_cell() -> Vector3i:
	var g = meta.get("goal", null)
	if g is Vector3i:
		var gc: Vector3i = g
		if grid != null and grid.is_walkable(gc):
			return gc
	var anchor: Vector3i = mercs[0].cell if not mercs.is_empty() else Vector3i.ZERO
	var best := NO_CELL
	var bd := 999999.0
	for k in exit_cells.keys():
		var c: Vector3i = k
		var d := Tac3DVision.flat(c).distance_to(Tac3DVision.flat(anchor))
		if d < bd:
			bd = d
			best = c
	return best


func _show_objective(c: Vector3i, col: Color) -> void:
	if fast or grid == null or _world_root == null or c.x < 0:
		return
	if _objective == null or not is_instance_valid(_objective):
		_objective = MeshInstance3D.new()
		_objective.name = "ObjectiveMarker"
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.45
		cone.height = 1.1
		cone.radial_segments = 10
		cone.rings = 1
		_objective_mat = StandardMaterial3D.new()
		_objective_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_objective_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_objective_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone.material = _objective_mat
		_objective.mesh = cone
		_objective.rotation_degrees = Vector3(180.0, 0.0, 0.0)   # tip points down
		_world_root.add_child(_objective)
	if _objective_mat != null:
		_objective_mat.albedo_color = Color(col.r, col.g, col.b, 0.8)
	var w: Vector3 = grid.cell_to_world(c)
	_objective_y = w.y + 2.3
	_objective.position = Vector3(w.x, _objective_y, w.z)
	_objective.visible = true


func _hide_objective() -> void:
	if _objective != null and is_instance_valid(_objective):
		_objective.visible = false


# ================================================================= SPEC v5 §2/§3.3: sectors

## Complete teardown + rebuild of ALL map-dependent nodes and state.
## The squad (Game.team) survives and is re-placed at the target sector's
## merc_spawns; HUD/rig/light/WorldRoot survive the swap.
## Deliberately WITHOUT await: no frame may run while references are half torn
## down. In the game flow it is therefore called via call_deferred (see _handle_edge).
func load_sector(id: String) -> void:
	if not is_inside_tree() or battle_over:
		_transitioning = false
		return
	busy = true
	_teardown_map()

	sector = id
	Game.sector = id
	_build_map_systems(id)
	_spawn_units()

	# Combat/round state is sector-local: a new sector = a fresh exploration phase.
	combat_started = false
	no_contact_rounds = 0
	turn = 1
	player_turn = true
	mode = "move"
	aim_level = 0
	_aim_target = null
	noise_at = Vector3i(-99, -99, -99)
	_edge_locked_at = Vector3i(-99, -99, -99)

	compute_vision()
	selected = mercs[0] if not mercs.is_empty() else null
	selection = [selected] if selected != null else []
	_rebuild_interactive()
	if hud != null:
		hud.rebuild_slots()   # new Tac3DUnit objects -> rebuild the portrait columns
		hud.refresh()
	if picker != null and selected != null:
		picker.set_active_level(selected.cell.y)
	# SPEC v5 §3.3.2 — objective cue for the sector we just entered.
	_refresh_objective()

	_movers = 0
	busy = false
	_transitioning = false


## Tears down units + map-bound view nodes. remove_child FIRST (takes the node out
## of the tree at once -> nothing renders a map that no longer exists), queue_free
## afterwards.
func _teardown_map() -> void:
	# Kill running movement tweens FIRST: they point at units that are about to be
	# freed (group moving in parallel). The sector change is the only moment where a
	# global tween stop is harmless — banner/speaker overlays are re-set afterwards anyway.
	var st := get_tree()
	if st != null and st.has_method("get_processed_tweens"):
		for t in st.get_processed_tweens():
			var tw: Tween = t
			if tw != null and tw.is_valid():
				tw.kill()

	var doomed: Array = units.duplicate()
	if captive != null:
		doomed.append(captive)
	for v in villagers:
		doomed.append(v)
	for d in doomed:
		var du: Tac3DUnit = d
		if is_instance_valid(du):
			if du.get_parent() != null:
				du.get_parent().remove_child(du)
			du.queue_free()
	units.clear()
	mercs.clear()
	enemies.clear()
	selection.clear()
	villagers.clear()
	boss = null
	captive = null
	selected = null
	occupied.clear()
	corpses.clear()
	looted.clear()
	visible_cells.clear()
	loot_cells = []
	hover_cell = Picker3D.NONE
	hover_path = []

	# The objective beacon hangs under _world_root (which SURVIVES the swap), so it
	# has to be freed here explicitly like ground/cursor/juice.
	# `fog` is in the list for the same reason: without it a stale fog node piles up
	# under _world_root on every sector change and the old map's black quads linger.
	for n in [ground, cursor, juice, _objective, fog]:
		if n != null and is_instance_valid(n):
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			n.queue_free()
	ground = null
	cursor = null
	juice = null
	fog = null
	_objective = null
	_objective_mat = null


## Cursor + juice hang off the grid/rig and have to be rebuilt after a sector
## change. In bot/headless (fast) both stay null — the regression guard holds.
func _rebuild_interactive() -> void:
	if fast:
		return
	cursor = CursorView3D.new()
	cursor.name = "CursorView"
	_world_root.add_child(cursor)
	cursor.setup(grid)
	juice = Juice3D.new()
	juice.name = "Juice"
	_world_root.add_child(juice)
	juice.setup(grid, rig)
	# Required: load_sector() rebuilds the grid, so without this the fog would die
	# on the first sector change (F4 -> F3).
	fog = load("res://scripts/tac3d/fog_view3d.gd").attach(_world_root, grid, fast)


## Map-edge logic of the exploration phase (spec §2/§3.3). Returns true when the
## merc's move should end here. Only takes effect in F4 — in F3 (and therefore in
## all existing tests) it is a pure no-op.
func _handle_edge(u) -> bool:
	if sector != "F4" or _transitioning or battle_over or combat_started:
		return false
	if u == null or not u.is_merc or grid == null:
		return false
	var c: Vector3i = u.cell
	# West edge = the exit to F3.
	if exit_cells.has(c):
		_transitioning = true
		call_deferred("_enter_sector", "F3", "Moving west — Sector F3, Rookhaven")
		return true
	# All other edges are locked in-fiction: banner, but NO sector change.
	var side := ""
	if c.z <= 0:
		side = "north"
	elif c.z >= grid.size_z - 1:
		side = "south"
	elif c.x >= grid.size_x - 1:
		side = "east"
	elif c.x <= 0:
		side = "west"
	if side == "":
		return false
	if _edge_locked_at != c:
		_edge_locked_at = c
		if hud != null:
			hud.banner(String(EDGE_LOCKED[side]), 2.2)
		if not fast:
			Sfx.play("ui_error")
	return true


## Sector change incl. banner + autosave (spec §4.4). Runs deferred so the aborting
## do_move call returns cleanly first.
func _enter_sector(id: String, banner_text: String) -> void:
	load_sector(id)
	if hud != null:
		hud.banner(banner_text, 2.6)
	if not fast:
		Sfx.play("ui_confirm", -4.0)
	Game.save_game(Game.AUTOSAVE_SLOT)


func _unhandled_input(ev) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		# Camera rotation stays available at all times (even after the battle ends).
		if ev.keycode == KEY_Q:
			if rig != null:
				rig.rotate_step(-1)
			return
		if ev.keycode == KEY_E:
			if rig != null:
				rig.rotate_step(1)
			return
		# W1: a modal panel (Vargo dialogue/base) is open -> swallow the action hotkeys.
		if hud != null and hud.modal_active:
			return
		if battle_over:   # FIX M5: lock the action keys once the battle is over.
			return
		match ev.keycode:
			KEY_TAB:
				_cycle_merc()
			KEY_R:
				ui_reload()
			KEY_A:
				ui_aim()
			KEY_G:
				ui_grenade_mode()
			KEY_H:
				ui_medkit()
			KEY_T:
				ui_zone()
			KEY_C:
				ui_stance()
			KEY_F:
				ui_interact()
			KEY_I:
				ui_inventory()
			KEY_ENTER, KEY_KP_ENTER:
				ui_end_turn()
			KEY_ESCAPE:
				if mode == "grenade":
					mode = "move"
					_hud_refresh()
				else:
					ui_menu()
			KEY_1:
				ui_select_slot(0)
			KEY_2:
				ui_select_slot(1)
			KEY_3:
				ui_select_slot(2)
			KEY_4:
				ui_select_slot(3)
	elif ev is InputEventMouseButton:
		if ev.pressed:
			match ev.button_index:
				MOUSE_BUTTON_WHEEL_UP:
					if rig != null:
						rig.zoom_by(0.9)
				MOUSE_BUTTON_WHEEL_DOWN:
					if rig != null:
						rig.zoom_by(1.1)
				MOUSE_BUTTON_LEFT:
					# #2: click OR box is only decided on release (threshold
					# DRAG_PX). The actual click runs in the release branch.
					_lmb_down = true
					_lmb_start = ev.position
					_lmb_dragging = false
				MOUSE_BUTTON_RIGHT:
					if not battle_over and mode == "grenade":
						mode = "move"
						_hud_refresh()
					else:
						_rmb_aim()   # JA2: right-click an enemy = aim more carefully
		elif ev.button_index == MOUSE_BUTTON_LEFT and _lmb_down:
			_lmb_down = false
			if _lmb_dragging:
				_lmb_dragging = false
				if hud != null:
					hud.hide_select_rect()
				_box_select(_drag_rect(ev.position))
			else:
				_handle_click()
	elif ev is InputEventMouseMotion and _lmb_down:
		var mp: Vector2 = ev.position
		if not _lmb_dragging and mp.distance_to(_lmb_start) > DRAG_PX:
			_lmb_dragging = true
		if _lmb_dragging and hud != null:
			hud.show_select_rect(_drag_rect(mp))


## Normalised selection box between the press position and the current mouse position.
func _drag_rect(now: Vector2) -> Rect2:
	return Rect2(_lmb_start, now - _lmb_start).abs()


# FIX C2: busy=true BEFORE await shoot, busy=false AFTER -> no double shot on a double click.
func _handle_click() -> void:
	if busy or battle_over or _transitioning or picker == null or selected == null:
		return
	var target := picker.cell_under_mouse(get_viewport())
	if target == Picker3D.NONE:
		return
	if mode == "grenade":
		await do_grenade(selected, target)   # sets mode="move" internally
		_hud_refresh()
		return
	var tgt: Tac3DUnit = occupied.get(target, null)
	# Phase 7 — captive click BEFORE the merc branch (Otto is is_merc=true and would
	# otherwise be wrongly selected via ui_select). K1: only on the same level + flat-adjacent.
	if captive != null and tgt == captive:
		if selected.alive and selected.cell.y == captive.cell.y \
		   and selected.flat().distance_to(captive.flat()) <= 1.6:
			await free_otto()
		elif hud != null:
			hud.banner("Get closer to Tobias — take the storehouse hatch down into the cellar.")
		return
	# SPEC v5 §3.3.3 — locked hatch: clicking it from an adjacent cell breaches it.
	# Ctrl keeps its meaning (free fire), so it takes precedence and is excluded.
	if cellar_locked and target == cellar_door and not Input.is_key_pressed(KEY_CTRL):
		if not breach_cellar_door(selected) and hud != null:
			hud.banner("The cellar hatch is barred. Breach it from an adjacent tile (F) — or find the key.")
		_hud_refresh()
		return
	# #3 (new): Ctrl held = FREE FIRE. At ANY unit (including your own -> friendly fire
	# is explicitly allowed) OR into the ground. Must sit BEFORE merc selection/move.
	if Input.is_key_pressed(KEY_CTRL) and selected.alive and (captive == null or selected != captive):
		if tgt != null and tgt.alive and tgt != selected and tgt != captive:
			if vision.los(selected.cell, tgt.cell):
				busy = true
				await shoot(selected, tgt)   # shoot checks NO team -> friendly fire is possible
				busy = false
				_hud_refresh()
			elif hud != null:
				hud.banner("No line of sight to target.")
			return
		busy = true
		await shoot_ground(selected, target)   # ground/suppression shot (no damage)
		busy = false
		_hud_refresh()
		return
	if tgt != null and not tgt.is_merc and tgt.alive and tgt.seen:
		if vision.los(selected.cell, tgt.cell):
			busy = true
			await shoot(selected, tgt)
			busy = false
			_hud_refresh()
		return
	if tgt != null and tgt.is_merc and tgt.alive:
		ui_select(tgt)
		return
	if search_target_at(target) != "":
		if selected.flat().distance_to(Tac3DVision.flat(target)) <= 1.6:
			do_search(selected, target)
			_hud_refresh()
			return
		# Polish: a loot target (crate/corpse) clicked from afar -> walk to the
		# nearest free neighbouring tile and search it automatically.
		# (Since the walkability fix, crate cells are blocked in the pathfinder;
		# walking directly onto them is no longer possible.)
		var best: Array = []
		for n in grid.neighbors(target):
			var nn: Vector3i = n
			if occupied.has(nn):
				continue
			var pc := path_for(selected, nn)
			if pc.size() > 1 and (best.is_empty() or pc.size() < best.size()):
				best = pc
		if not best.is_empty():
			var pref2: Array = best if not combat_started else prefix_for_ap(best, selected.ap, selected)
			await do_move(selected, pref2)
			if search_target_at(target) != "" and selected.flat().distance_to(Tac3DVision.flat(target)) <= 1.6:
				do_search(selected, target)
			_hud_refresh()
		return
	# #2 (new): multi-selection (mouse box) -> the WHOLE group moves to the target.
	# Shift+click remains the shortcut for "everyone" during the approach phase.
	if selection.size() > 1:
		await _group_move(target, selection)
		_hud_refresh()
		return
	var cells := path_for(selected, target)
	if cells.size() > 1:
		if not combat_started and Input.is_key_pressed(KEY_SHIFT):
			await _group_move(target, mercs)
		else:
			var pref: Array = cells if not combat_started else prefix_for_ap(cells, selected.ap, selected)
			await do_move(selected, pref)
		_hud_refresh()


## #2: group move — SIMULTANEOUS: every member starts its movement in parallel
## (slightly staggered) and they cover each other; the caller waits until ALL
## have arrived. Enemy contact DURING the move stops the WHOLE group
## (halt_on_combat in do_move). Destinations are still distributed via _free_near;
## if two paths cross on the way, the unit waits briefly (patient) instead of
## stopping dead. Approach phase: free. Turn-based combat: everyone with their OWN AP (prefix).
func _group_move(target: Vector3i, group: Array) -> void:
	var living: Array = []
	for m in group:
		var mu: Tac3DUnit = m
		if mu.alive:
			living.append(mu)
	# Closest to the target first -> more natural formation, less reshuffling.
	living.sort_custom(func(a, b):
		return Tac3DVision.flat(a.cell).distance_to(Tac3DVision.flat(target)) \
			< Tac3DVision.flat(b.cell).distance_to(Tac3DVision.flat(target)))
	# Distribute destinations and paths COMPLETELY before the start (paths avoid the
	# others' starting positions; the rest is handled by the patient wait cycles).
	var claimed: Dictionary = {}
	var jobs: Array = []   # [unit, path]
	for m in living:
		var mu: Tac3DUnit = m
		var dest := _free_near(target, claimed, mu)
		claimed[dest] = true
		var cells := path_for(mu, dest)
		if cells.size() > 1:
			var pref: Array = cells if not combat_started else prefix_for_ap(cells, mu.ap, mu)
			if pref.size() > 1:
				jobs.append([mu, pref])
	if jobs.is_empty():
		return
	var done := [0]   # boxed counter: every parallel coroutine increments it at the end
	for j in jobs:
		var job: Array = j
		_group_member_move(job[0], job[1], done)   # DELIBERATELY without await -> parallel
		await dl(0.1)   # slightly staggered start: fewer collisions, squad-like look
	var guard := 0
	# _transitioning aborts the wait: the old sector's units are torn down and their
	# tweens never fire again -> done[0] would never reach the full count.
	while done[0] < jobs.size() and guard < 3600 and not _transitioning:
		guard += 1
		await get_tree().process_frame


## One group member moves (started in parallel); reports completion via the shared
## done counter (an Array used as a box — the coroutines share the reference).
func _group_member_move(mu: Tac3DUnit, cells: Array, done: Array) -> void:
	await do_move(mu, cells, true, true)
	done[0] += 1


## A free, walkable cell near `target` (not occupied, not already `claimed`). Ring search.
func _free_near(target: Vector3i, claimed: Dictionary, u) -> Vector3i:
	if not occupied.has(target) and not claimed.has(target) and path_for(u, target).size() > 1:
		return target
	for radius in range(1, 6):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dz) != radius:
					continue   # only check the outer ring of this radius
				var c := Vector3i(target.x + dx, target.y, target.z + dz)
				if occupied.has(c) or claimed.has(c):
					continue
				if path_for(u, c).size() > 1:
					return c
	return target


func _cycle_merc() -> void:
	if mercs.is_empty():
		return
	var start := mercs.find(selected)
	for k in range(1, mercs.size() + 1):
		var cand: Tac3DUnit = mercs[(start + k) % mercs.size()]
		if cand.alive:
			if cand != selected:
				ui_select(cand)
			else:
				_hud_refresh()
			return


# Hover feedback (3D cursor + HUD tooltip). Uses the existing combat helpers, mutates nothing.
func _update_hover() -> void:
	if cursor == null or hud == null:
		return
	# FIX M3: mouse outside the grid -> hide everything.
	if hover_cell == Picker3D.NONE:
		cursor.clear()
		hud.hide_cursor()
		hud.hide_crosshair()
		return
	if selected == null:
		cursor.clear()
		hud.hide_cursor()
		hud.hide_crosshair()
		return
	# Default: no crosshair — the enemy branch below brings it back.
	hud.hide_crosshair()
	# FIX M4: screen coordinates of the mouse (the CanvasLayer is camera-independent).
	var mpos := get_viewport().get_mouse_position()
	if mode == "grenade":
		var ok := grenade_valid(selected, hover_cell)
		cursor.show_grenade(selected.cell, hover_cell, float(Db.GRENADE["radius"]), ok)
		if ok:
			hud.set_cursor("Throw grenade: %d AP · radius %.1f" % [int(Db.GRENADE["ap"]), float(Db.GRENADE["radius"])], mpos)
		else:
			hud.set_cursor("Out of range", mpos)
		return
	# Phase 7 — Otto hover (K1: freeing only on the same level + flat-adjacent).
	if captive != null and hover_cell == captive.cell:
		cursor.show_target(hover_cell, "search")
		if selected.cell.y == captive.cell.y and selected.flat().distance_to(captive.flat()) <= 1.6:
			hud.set_cursor("Free Tobias [F]", mpos)
		else:
			hud.set_cursor("Tobias — descend into the cellar", mpos)
		return
	# SPEC v5 §3.3.3 — locked cellar hatch.
	if cellar_locked and hover_cell == cellar_door:
		cursor.show_target(hover_cell, "search")
		if selected.cell.y == cellar_door.y and selected.flat().distance_to(Tac3DVision.flat(cellar_door)) <= 1.6:
			hud.set_cursor("Breach the cellar door [F] — %d AP" % BREACH_AP, mpos)
		else:
			hud.set_cursor("Cellar door — barred. Breach it, or take the key off its guard.", mpos)
		return
	var tgt: Tac3DUnit = occupied.get(hover_cell, null)
	# SPEC v5 §3.3.5 — villagers are neutral set dressing, not a target and not
	# selectable; give them a label instead of a move path onto their tile.
	if tgt != null and villagers.has(tgt):
		cursor.show_target(hover_cell, "search")
		hud.set_cursor("%s — Rookhaven militia" % String(tgt.data.get("name", "Villager")), mpos)
		return
	if tgt != null and not tgt.is_merc and tgt.alive and tgt.seen:
		# JA2: cursor moved onto a DIFFERENT target -> the accumulated aim expires.
		if _aim_target != null and _aim_target != tgt:
			_aim_target = null
			aim_level = 0
			_hud_refresh()
		var los := vision.los(selected.cell, tgt.cell)
		cursor.show_target(hover_cell, "shoot" if los else "block")
		if los:
			# JA2 crosshair over the enemy (grows per aim level, shows the zone).
			var cam := get_viewport().get_camera_3d()
			if cam != null:
				hud.show_crosshair(cam.unproject_position(tgt.global_position + Vector3.UP * 1.1), aim_level, aim_cap(selected), aim_zone)
			hud.set_cursor("%s — Hit: %d %% · %d AP · Aim ×%d/%d [Right-click] · Zone: %s [T]" % [String(tgt.data["name"]), hit_chance(selected, tgt, aim_level, aim_zone), shot_ap(selected, aim_level), aim_level, aim_cap(selected), String(Db.ZONES[aim_zone]["name"])], mpos)
		else:
			hud.set_cursor("No line of fire", mpos)
		return
	if search_target_at(hover_cell) != "":
		cursor.show_target(hover_cell, "search")
		if combat_started:
			hud.set_cursor("Search: %d AP" % Db.SEARCH_AP, mpos)
		else:
			hud.set_cursor("Search (free)", mpos)
		return
	hover_path = path_for(selected, hover_cell)
	if hover_path.size() > 1:
		var afford: int = prefix_for_ap(hover_path, selected.ap, selected).size()
		cursor.show_path(hover_path, afford)
		cursor.show_target(hover_cell, "move")
		if not combat_started:
			hud.set_cursor("Approach: free", mpos)
		else:
			var cost := path_ap(hover_path, selected)
			if cost <= selected.ap:
				hud.set_cursor("Move: %d AP" % cost, mpos)
			else:
				hud.set_cursor("%d AP (only %d possible)" % [cost, maxi(0, afford - 1)], mpos)
	else:
		cursor.clear()
		hud.hide_cursor()


func _process(dt: float) -> void:
	if rig == null:
		return
	# Objective beacon bobs gently. Deliberately no Tween: a looping tween would
	# outlive a sector teardown, and this costs one sin() per frame.
	if _objective != null and is_instance_valid(_objective) and _objective.visible:
		_objective_t += dt
		_objective.position.y = _objective_y + sin(_objective_t * 2.4) * 0.18
	# Middle-mouse drag = scroll the map (frame delta of the mouse position).
	var mpos := get_viewport().get_mouse_position()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		if _cam_dragging and rig.cam != null:
			var wpp := rig.cam.size / float(maxi(1, get_viewport().get_visible_rect().size.y))
			var d := mpos - _drag_last
			rig.pan(Vector2(-d.x, -d.y) * wpp)
		_cam_dragging = true
	else:
		_cam_dragging = false
	_drag_last = mpos
	var pan := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP):
		pan.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_LEFT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT):
		pan.x += 1.0
	if pan != Vector2.ZERO:
		rig.pan(pan.normalized() * PAN_SPEED * dt)
	# #2: the mouse release was lost to a HUD control (MOUSE_FILTER_STOP swallows the
	# ButtonUp event) -> catch up here by polling, otherwise the box gets stuck.
	if _lmb_down and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_lmb_down = false
		if _lmb_dragging:
			_lmb_dragging = false
			if hud != null:
				hud.hide_select_rect()
			_box_select(_drag_rect(get_viewport().get_mouse_position()))
	# FIX M5: hover only while playable (not after the battle ends / during the enemy phase / while busy).
	if hud != null and picker != null and selected != null and not busy and player_turn and not battle_over:
		var c := picker.cell_under_mouse(get_viewport())
		if c != hover_cell:
			hover_cell = c
			_update_hover()

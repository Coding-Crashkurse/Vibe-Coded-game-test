class_name Tac3DMapGen
extends RefCounted
## 3D combat map generator (~72x72) in the spirit of MapGen (spec §3.3):
##   landing zone south (level 0) · dry creek bed with a FLAT boardwalk (level 0)
##   village (buildings) · manor (FLAT, level 0) · cover/loot tiles.
## Data driven like MapGen.ENEMY_SPAWNS. Ranges/distances run flat on (x,z);
## the level (y) only carries height bonuses and level links (boardwalk/ramp).
##
## Important geometry:
##   z grows SOUTHWARD. Merc landing zone z~68 (south). The old river band z=39..41
##   is now DRY GROUND — spec §3.3.2/§6 declare the demo waterless, so this
##   generator emits NO water tiles at all. The wooden boardwalk (level 0,
##   x=34..37) stays as the village's south approach: it spans the dry creek bed
##   and keeps `bridge_cells` meaningful for Scenery3D and the orchestrator.
##   Manor in the north (z~3..14) FLAT on level 0, boss on BOSS_HOME=(58,0,8),
##   entered at ground level through the 2 cell wide south door (x=57/58).

## SPEC v5 §2/§3.3 — the demo spans TWO sectors:
##   "F4" = landing zone (lean, dry, jungle edge; NO creek/boardwalk/village/cellar/boss).
##          The WEST EDGE is the exit -> `exit_cells`; every other edge is barred
##          in fiction (the orchestrator shows the banner).
##   "F3" = Rookhaven (the full village map). `generate(seed, diff)` without a third
##          parameter still yields EXACTLY F3 (the test harness depends on it).
##
## SENTINELS: so that NO caller crashes, BOTH sectors return the same dictionary
## keys. Whatever a sector does not have comes back as a sentinel:
##   * `NO_CELL` = Vector3i(-1, -1, -1) for missing single cells
##     (F4: boss_home, otto_spawn, keller_entrance; BOTH: swim_from, swim_to —
##      the demo has no water, see §3.3.2)
##   * empty array for missing cell sets
##     (F4: bridge_cells; F3: exit_cells)
## `goal` is the boss (BOSS_HOME) in F3 and the middle of the west exit in F4.

const NO_CELL := Vector3i(-1, -1, -1)   # "does not exist in this sector"

## Sectors this generator has a recipe for. `loading.gd` consumes this instead of
## keeping its own copy.
const SECTORS := ["F4", "F3"]

const SIZE := 72
const CREEK_Z0 := 39           # dry creek bed z=39..41 (formerly the river band)
const CREEK_MID := 40
const CREEK_Z1 := 41
const BRIDGE_X0 := 34          # boardwalk spans x=34..37
const BRIDGE_X1 := 37

# Landing zone south, far away (neutral spawn, spec §14.3)
const MERC_SPAWNS := [
	Vector3i(6, 0, 68), Vector3i(7, 0, 68),
	Vector3i(6, 0, 69), Vector3i(7, 0, 69),
]
# Manor — flat on level 0 (no second storey, user requirement)
const BOSS_HOME := Vector3i(58, 0, 8)

# Cellar "The Hideout" UNDER the village. Cellar entrance on level 0, Tobias in the
# cellar room on level -1. Dead end (no pathfinding shortcut).
# Both coordinates are load bearing (orchestrator + --demo3d/--sector3d) — DO NOT MOVE.
const KELLER_ENTRANCE := Vector3i(32, 0, 32)
const OTTO_SPAWN := Vector3i(32, -1, 33)

# STOREHOUSE (spec §3.3.3): the cellar entrance used to be a bare hatch in open
# ground. It now sits inside a proper building shell, so the location reads as the
# storehouse the captive is locked under. The interior (x=30..34, z=30..34) matches
# the cellar footprint exactly -> GroundView3D treats that floor as the cellar lid.
# The door sits in the SOUTH wall, facing the village and the boardwalk approach.
const STOREHOUSE := {"x0": 29, "z0": 29, "w": 7, "h": 7, "door": Vector3i(32, 0, 35)}

# SPEC v5 §3.3.3 — the enemy count is RE-COUPLED to Db.DIFFICULTY[..]["enemies"]
# (8 / 10 / 13). The 2026-07-19 easing that pinned the demo to a flat 4 is superseded.
# Elites ("elite"/"elite_flinte") are tagged "hard" and therefore appear on HARD only.
# The boss is deliberately FIRST so the defensive trim in _filter_spawns() can never
# drop him if Db ever lowers the budget below the authored table size.
const DEMO_ENEMY_TOTAL := 8   # legacy alias == enemy_total("leicht"); prefer enemy_total()
const ENEMY_SPAWNS := [
	# --- always present (8 = EASY budget) ---
	{"cell": Vector3i(58, 0, 8), "type": "boss", "diff": "all"},          # manor, ground level
	{"cell": Vector3i(30, 0, 45), "type": "miliz_p9", "diff": "all"},     # south outpost (first contact)
	{"cell": Vector3i(28, 0, 34), "type": "miliz_p9", "diff": "all"},     # village west
	{"cell": Vector3i(44, 0, 32), "type": "miliz_k45", "diff": "all"},    # village east
	{"cell": Vector3i(20, 0, 26), "type": "miliz_p9", "diff": "all"},     # north-west approach
	{"cell": Vector3i(48, 0, 40), "type": "miliz_k45", "diff": "all"},    # creek bed, east of the boardwalk
	{"cell": Vector3i(36, 0, 22), "type": "miliz_flinte", "diff": "all"}, # north road
	{"cell": Vector3i(56, 0, 16), "type": "miliz_p9", "diff": "all"},     # manor forecourt
	# --- NORMAL and up (+2 = 10) ---
	{"cell": Vector3i(24, 0, 52), "type": "miliz_k45", "diff": "normal"}, # southern picket
	{"cell": Vector3i(62, 0, 26), "type": "miliz_flinte", "diff": "normal"}, # east flank
	# --- HARD only (+3 = 13) — Helix elites, spec §3.3.3 ---
	{"cell": Vector3i(34, 0, 28), "type": "elite", "diff": "hard"},       # village core
	{"cell": Vector3i(57, 0, 10), "type": "elite", "diff": "hard"},       # manor interior
	{"cell": Vector3i(61, 0, 6), "type": "elite_flinte", "diff": "hard"}, # manor interior
]

# SPEC v5 §3.3.5 — once the base goes live, three villagers with shotguns appear in
# the village core as militia set dressing. The generator only PROVIDES the cells;
# the orchestrator spawns the actual units (see also villager_spawns()).
# All three sit in open ground just south of the storehouse, clear of every enemy
# spawn, cover tile and building footprint.
const VILLAGER_SPAWNS := [
	Vector3i(30, 0, 37), Vector3i(33, 0, 37), Vector3i(27, 0, 33),
]

# Village buildings: {x0, z0, w, h, door} (level 0). Deliberately placed so they cover
# NEITHER the boardwalk exits (x=34..37, z=38/42) NOR any enemy/merc spawn.
const VILLAGE_BUILDINGS := [
	{"x0": 10, "z0": 20, "w": 6, "h": 5, "door": Vector3i(12, 0, 24)},
	{"x0": 50, "z0": 20, "w": 7, "h": 6, "door": Vector3i(53, 0, 25)},
	{"x0": 14, "z0": 32, "w": 6, "h": 5, "door": Vector3i(16, 0, 36)},
	{"x0": 40, "z0": 34, "w": 6, "h": 5, "door": Vector3i(42, 0, 38)},
]

# Deterministic cover/loot tiles (walkable, cover>0, FLAG_DESTRUCT) in open terrain —
# they collide with no building and no spawn (>= 5 for smoke K4).
const COVER_CELLS := [
	Vector3i(22, 0, 50), Vector3i(40, 0, 50), Vector3i(55, 0, 50),
	Vector3i(28, 0, 44), Vector3i(44, 0, 44), Vector3i(18, 0, 34),
	Vector3i(58, 0, 30), Vector3i(24, 0, 20),
]


# ------------------------------------------------------------------ F4 (landing zone)
# SPEC v5 §3.3.2 — kept lean: dry terrain, jungle edge feel.
# NO creek, NO boardwalk, NO village, NO cellar, NO boss.
# The squad lands in the SOUTH and moves WEST (x=0) on to F3.

# Landing on the south beach (z>=64 carries the sand band in Scenery3D).
const F4_MERC_SPAWNS := [
	Vector3i(46, 0, 66), Vector3i(47, 0, 66),
	Vector3i(46, 0, 67), Vector3i(47, 0, 67),
]
# 4 Helix patrols (spec §3.3.2: 3-5), spread loosely along the diagonal from the
# drop point to the west exit, so the way to F3 offers contact without crushing the
# squad. The landing zone is an approach tutorial — it is NOT scaled by difficulty.
const F4_ENEMY_TOTAL := 4
const F4_ENEMY_SPAWNS := [
	{"cell": Vector3i(38, 0, 58), "type": "miliz_p9", "diff": "all"},      # beach post
	{"cell": Vector3i(26, 0, 48), "type": "miliz_k45", "diff": "all"},     # jungle trail
	{"cell": Vector3i(14, 0, 40), "type": "miliz_p9", "diff": "all"},      # ridge path
	{"cell": Vector3i(8, 0, 30), "type": "miliz_flinte", "diff": "all"},   # watch fire on the west path
]
# Cover/loot tiles (walkable, cover>0, FLAG_DESTRUCT) — deterministic as in F3.
const F4_COVER_CELLS := [
	Vector3i(42, 0, 60), Vector3i(34, 0, 54), Vector3i(24, 0, 44),
	Vector3i(30, 0, 36), Vector3i(12, 0, 34), Vector3i(18, 0, 52),
]
# Rock/ruin barriers: short WALL strips WITHOUT an interior (=> Scenery3D builds walls
# but no roofs). Pure sight/cover structure, no building, no village.
# {x0, z0, w, h} — deliberately clear of spawns, cover tiles and the west edge.
const F4_ROCK_WALLS := [
	{"x0": 30, "z0": 50, "w": 5, "h": 1},
	{"x0": 20, "z0": 38, "w": 1, "h": 4},
	{"x0": 44, "z0": 56, "w": 4, "h": 1},
	{"x0": 34, "z0": 26, "w": 1, "h": 5},
]
# West exit: column x=0. Its middle serves as `goal` (objective marker / AI reference).
const F4_EXIT_X := 0
const F4_GOAL := Vector3i(0, 0, 36)


## True if this generator has a recipe for `id`. `loading.gd` consumes this instead of
## duplicating the sector list locally.
static func has_sector(id: String) -> bool:
	return SECTORS.has(id)


## Enemy budget for F3 by difficulty — RE-COUPLED to Db.DIFFICULTY (8/10/13, spec §3.3.3).
## Fallback law: read through the autoload defensively, so a bare static call without a
## running SceneTree degrades to the authored numbers instead of crashing.
static func enemy_total(difficulty: String) -> int:
	var authored := {"leicht": 8, "normal": 10, "schwer": 13}
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		# Untyped on purpose: DIFFICULTY is a script constant, not a Node member —
		# a statically typed `Node` base would not resolve it.
		var db = (ml as SceneTree).root.get_node_or_null("/root/Db")
		if db != null:
			var table: Dictionary = db.DIFFICULTY
			if table.has(difficulty):
				return int(table[difficulty]["enemies"])
	return int(authored.get(difficulty, 10))


## Village core cells for the three §3.3.5 villagers. Returns only cells that are
## actually walkable on `g`; a blocked cell is replaced by a walkable neighbour so the
## orchestrator always gets three usable spots (fallback law). Pass `null` to get the
## raw constant.
static func villager_spawns(g: Grid3D) -> Array:
	var out: Array = []
	for vc in VILLAGER_SPAWNS:
		var c: Vector3i = vc
		if g == null or g.is_walkable(c):
			out.append(c)
			continue
		var found := false
		# Bounded ring search (radius 1..3) — never unbounded, never blocking.
		for r in range(1, 4):
			if found:
				break
			for dz in range(-r, r + 1):
				if found:
					break
				for dx in range(-r, r + 1):
					var n := Vector3i(c.x + dx, 0, c.z + dz)
					if n.x < 0 or n.x >= SIZE or n.z < 0 or n.z >= SIZE:
						continue
					if out.has(n) or not g.is_walkable(n):
						continue
					out.append(n)
					found = true
					break
		if not found:
			out.append(c)   # last resort: hand back the authored cell unchanged
	return out


## Map generator. `sector` picks the recipe; the "F3" default keeps ALL existing
## callers (and the headless test modes) unchanged.
static func generate(seed: int, difficulty: String, sector := "F3") -> Dictionary:
	if sector == "F4":
		return _generate_f4(seed, difficulty)
	return _generate_f3(seed, difficulty)


## F4 — landing zone. Returns the same keys as F3 (sentinels, see header).
static func _generate_f4(seed: int, difficulty: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var g := Grid3D.new()
	_fill_ground(g, rng)

	# Rock/ruin barriers (WALL only, no FLOOR -> no roof, no building).
	for w in F4_ROCK_WALLS:
		var wd: Dictionary = w
		_rock_wall(g, int(wd["x0"]), int(wd["z0"]), int(wd["w"]), int(wd["h"]))

	var loot_cells: Array = []
	_scatter_cover_cells(g, F4_COVER_CELLS, loot_cells)

	# §3.3.2: the landing zone keeps its 3-5 patrols on EVERY difficulty — it is the
	# approach tutorial, not a difficulty curve. No trim to Db here on purpose.
	var enemy_spawns: Array = _filter_spawn_list(F4_ENEMY_SPAWNS, difficulty)

	# Safety pass as in F3: every spawn MUST be walkable.
	for sp in F4_MERC_SPAWNS:
		var mc: Vector3i = sp
		if not g.is_walkable(mc):
			g.set_tile(mc, Tac3DTile.make(Tac3DTile.Kind.GROUND, 0))
	for es in enemy_spawns:
		var ec: Vector3i = es["cell"]
		if not g.is_walkable(ec):
			g.set_tile(ec, Tac3DTile.make(Tac3DTile.Kind.GROUND, 0))

	# West edge = exit to F3. Collect the walkable cells of column x=0 AND mark them
	# FLAG_KEEPOUT: no palm tree may block the only way out.
	var exit_cells: Array = []
	for z in range(SIZE):
		var c := Vector3i(F4_EXIT_X, 0, z)
		if g.is_walkable(c):
			exit_cells.append(c)
			_keepout(g, c)

	_mark_keepouts_for(g, F4_MERC_SPAWNS, F4_ENEMY_SPAWNS)

	return {
		"grid": g,
		"pathfinder_ready": false,
		"sector": "F4",
		"merc_spawns": F4_MERC_SPAWNS,
		"enemy_spawns": enemy_spawns,
		"boss_home": NO_CELL,          # sentinel: no boss in the landing zone
		"loot_cells": loot_cells,
		"goal": F4_GOAL,               # west exit instead of the boss
		"swim_from": NO_CELL,          # sentinel: the demo has no water (§3.3.2/§6)
		"swim_to": NO_CELL,            # sentinel: the demo has no water (§3.3.2/§6)
		"bridge_cells": [],            # sentinel: no boardwalk
		"otto_spawn": NO_CELL,         # sentinel: no cellar/captive
		"keller_entrance": NO_CELL,    # sentinel: no cellar
		"villager_spawns": [],         # sentinel: the villagers live in Rookhaven
		"exit_cells": exit_cells,      # west edge -> F3
	}


## F3 — Rookhaven.
static func _generate_f3(seed: int, difficulty: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var g := Grid3D.new()
	_fill_ground(g, rng)
	# NOTE: no _carve_river() any more — spec §3.3.2/§6 declare the demo waterless.
	var bridge_cells: Array = _build_bridge(g)

	for b in VILLAGE_BUILDINGS:
		var bd: Dictionary = b
		_building(g, int(bd["x0"]), int(bd["z0"]), int(bd["w"]), int(bd["h"]), bd["door"])

	_hill_estate(g)

	var loot_cells: Array = []
	_scatter_cover(g, rng, loot_cells)
	_keller(g)

	var enemy_spawns: Array = _filter_spawns(difficulty)

	# Safety pass: every spawn MUST be walkable (smoke K2). Force level-0 spawns onto
	# GROUND if a building part accidentally landed on them; the boss spot is secured
	# separately as manor FLOOR.
	for sp in MERC_SPAWNS:
		var mc: Vector3i = sp
		if not g.is_walkable(mc):
			g.set_tile(mc, Tac3DTile.make(Tac3DTile.Kind.GROUND, 0))
	for es in enemy_spawns:
		var ec: Vector3i = es["cell"]
		if ec.y == 0 and ec != BOSS_HOME and not g.is_walkable(ec):
			g.set_tile(ec, Tac3DTile.make(Tac3DTile.Kind.GROUND, 0))
	if not g.is_walkable(BOSS_HOME):
		g.set_tile(BOSS_HOME, Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))

	_mark_keepouts(g)

	return {
		"grid": g,
		"pathfinder_ready": false,
		"sector": "F3",
		"merc_spawns": MERC_SPAWNS,
		"enemy_spawns": enemy_spawns,
		"boss_home": BOSS_HOME,
		"loot_cells": loot_cells,
		"goal": BOSS_HOME,
		# No water in the demo (§3.3.2/§6) -> the swimming probe cells are sentinels.
		"swim_from": NO_CELL,
		"swim_to": NO_CELL,
		"bridge_cells": bridge_cells,
		# Cellar "The Hideout": captive spawn (level -1) + cellar entrance (level 0).
		"otto_spawn": OTTO_SPAWN,
		"keller_entrance": KELLER_ENTRANCE,
		# §3.3.5 set dressing — cells only, the orchestrator spawns the units.
		"villager_spawns": villager_spawns(g),
		# F3 has NO sector exit (Rookhaven is the demo's destination sector).
		"exit_cells": [],
	}


# ------------------------------------------------------------------ build helpers

## 72x72 GROUND on level 0.
static func _fill_ground(g: Grid3D, _rng: RandomNumberGenerator) -> void:
	for z in range(SIZE):
		for x in range(SIZE):
			g.set_tile(Vector3i(x, 0, z), Tac3DTile.make(Tac3DTile.Kind.GROUND, 0))


## FLAT wooden boardwalk (level 0) across the dry creek bed. The demo has no water
## (spec §3.3.2/§6), so the boardwalk is no longer a barrier crossing — it stays as
## the village's signposted south approach and keeps `bridge_cells` populated for
## Scenery3D (plank deck) and the orchestrator. BRIDGE tiles are walkable (WALK) and
## sit on the same level as the ground around them: no add_link, no orphaned deck.
static func _build_bridge(g: Grid3D) -> Array:
	var cells: Array = []
	for x in range(BRIDGE_X0, BRIDGE_X1 + 1):
		for z in range(CREEK_Z0, CREEK_Z1 + 1):
			var c := Vector3i(x, 0, z)
			g.set_tile(c, Tac3DTile.make(Tac3DTile.Kind.BRIDGE, 0))
			cells.append(c)
	return cells


## Village building: WALL ring (level 0, blocks sight + not walkable) + FLOOR inside +
## DOOR gap.
static func _building(g: Grid3D, x0: int, z0: int, w: int, h: int, door: Vector3i) -> void:
	for dz in range(h):
		for dx in range(w):
			var x := x0 + dx
			var z := z0 + dz
			var on_edge := dx == 0 or dx == w - 1 or dz == 0 or dz == h - 1
			if on_edge:
				g.set_tile(Vector3i(x, 0, z), Tac3DTile.make(Tac3DTile.Kind.WALL, 0))
			else:
				g.set_tile(Vector3i(x, 0, z), Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))
	# Door: walkable FLOOR gap in the wall.
	g.set_tile(door, Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))


## Manor in the north — FLAT on level 0 (user requirement 2026-07-19: NO second
## storey; the old level-1 hill with mesa + ramp made mercs disappear behind the rock
## block at the building's foot). Built like the village houses: FLOOR interior +
## WALL ring, 2 cells wide door in the south.
static func _hill_estate(g: Grid3D) -> void:
	# Interior (level 0): x=52..64, z=4..13.
	for z in range(4, 14):
		for x in range(52, 65):
			g.set_tile(Vector3i(x, 0, z), Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))
	# Wall ring (level 0): north z=3, south z=14, west x=51, east x=65.
	for x in range(51, 66):
		g.set_tile(Vector3i(x, 0, 3), Tac3DTile.make(Tac3DTile.Kind.WALL, 0))
		g.set_tile(Vector3i(x, 0, 14), Tac3DTile.make(Tac3DTile.Kind.WALL, 0))
	for z in range(3, 15):
		g.set_tile(Vector3i(51, 0, z), Tac3DTile.make(Tac3DTile.Kind.WALL, 0))
		g.set_tile(Vector3i(65, 0, z), Tac3DTile.make(Tac3DTile.Kind.WALL, 0))
	# Door (south, x=57/58): FLOOR gap in the z=14 wall — walkable at ground level.
	g.set_tile(Vector3i(57, 0, 14), Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))
	g.set_tile(Vector3i(58, 0, 14), Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))
	# Secure the boss's spot as FLOOR.
	g.set_tile(BOSS_HOME, Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))


## Cover tiles (walkable, cover 0.25, FLAG_DESTRUCT) + loot cells.
static func _scatter_cover(g: Grid3D, _rng: RandomNumberGenerator, loot_out: Array) -> void:
	_scatter_cover_cells(g, COVER_CELLS, loot_out)


## Cover/loot tiles from an arbitrary cell list (F3 + F4 share the logic).
static func _scatter_cover_cells(g: Grid3D, cells: Array, loot_out: Array) -> void:
	for cc in cells:
		var c: Vector3i = cc
		var t := Tac3DTile.make(Tac3DTile.Kind.GROUND, 0)
		t.cover = 0.25
		t.flags = t.flags | Tac3DTile.FLAG_DESTRUCT
		g.set_tile(c, t)
		loot_out.append(c)


## F4 rock/ruin barrier: pure WALL area (no FLOOR interior, no door). Scenery3D draws
## wall segments from it; _build_roofs finds no interior and therefore sets NO roof ->
## reads as rock/ruined masonry, not as a house.
static func _rock_wall(g: Grid3D, x0: int, z0: int, w: int, h: int) -> void:
	for dz in range(h):
		for dx in range(w):
			var c := Vector3i(x0 + dx, 0, z0 + dz)
			if c.x < 0 or c.x >= SIZE or c.z < 0 or c.z >= SIZE:
				continue
			g.set_tile(c, Tac3DTile.make(Tac3DTile.Kind.WALL, 0))


## STOREHOUSE + cellar (level -1) under the village = later home base "The Hideout".
## The storehouse shell (spec §3.3.3) turns the bare hatch into a building: WALL ring
## with a south door, FLOOR interior matching the cellar footprint. KELLER_ENTRANCE is
## an INTERIOR cell and is re-stamped as FLOOR afterwards, so it stays walkable and
## reachable through the door. add_link leads down -> dead end, no pathfinding shortcut.
## Collides with no VILLAGE_BUILDINGS/ENEMY_SPAWNS/COVER_CELLS/VILLAGER_SPAWNS entry.
static func _keller(g: Grid3D) -> void:
	# Building shell around the entrance (x=29..35, z=29..35, door in the south wall).
	_building(g, int(STOREHOUSE["x0"]), int(STOREHOUSE["z0"]),
		int(STOREHOUSE["w"]), int(STOREHOUSE["h"]), STOREHOUSE["door"])
	# Entrance stair inside the storehouse (level 0) — FLOOR cell, visually a hatch.
	g.set_tile(KELLER_ENTRANCE, Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))
	# Cellar room level -1 (x=30..34, z=30..34).
	for z in range(30, 35):
		for x in range(30, 35):
			g.set_tile(Vector3i(x, -1, z), Tac3DTile.make(Tac3DTile.Kind.FLOOR, -1))
	# Stair: entrance (0) <-> cellar cell directly below (-1).
	g.add_link(KELLER_ENTRANCE, Vector3i(32, -1, 32))


## FLAG_KEEPOUT on cells that must NEVER be occupied by blocking decoration (palms,
## Scenery3D): merc/enemy spawns, the boardwalk exits, the storehouse door, the
## villager spots and the apron in front of the manor door. Enemy spawns of ALL grades
## are marked, so the palm layout stays identical regardless of difficulty.
static func _mark_keepouts(g: Grid3D) -> void:
	for sp in MERC_SPAWNS:
		var mc: Vector3i = sp
		_keepout(g, mc)
	for es in ENEMY_SPAWNS:
		var ec: Vector3i = es["cell"]
		_keepout(g, ec)
	for vs in VILLAGER_SPAWNS:
		var vc: Vector3i = vs
		_keepout(g, vc)
	var sh_door: Vector3i = STOREHOUSE["door"]
	_keepout(g, sh_door)
	_keepout(g, Vector3i(32, 0, 36))                # apron in front of the storehouse door
	for x in range(BRIDGE_X0, BRIDGE_X1 + 1):
		_keepout(g, Vector3i(x, 0, CREEK_Z0 - 1))   # north end of the boardwalk
		_keepout(g, Vector3i(x, 0, CREEK_Z1 + 1))   # south end of the boardwalk
	for x in [57, 58]:
		_keepout(g, Vector3i(x, 0, 15))             # lawn in front of the manor door
		_keepout(g, Vector3i(x, 0, 16))


## Generic keepout pass for sectors without boardwalk/manor (F4): spawns only.
static func _mark_keepouts_for(g: Grid3D, merc_spawns: Array, enemy_spawns: Array) -> void:
	for sp in merc_spawns:
		var mc: Vector3i = sp
		_keepout(g, mc)
	for es in enemy_spawns:
		var ec: Vector3i = es["cell"]
		_keepout(g, ec)


static func _keepout(g: Grid3D, c: Vector3i) -> void:
	var t: Tac3DTile = g.get_tile(c)
	if t != null:
		t.flags = t.flags | Tac3DTile.FLAG_KEEPOUT


## F3 enemy roster. Tag filter exactly like MapGen.generate, then RE-COUPLED to
## Db.DIFFICULTY[..]["enemies"] (spec §3.3.3): if the authored table ever delivers more
## than the budget, the surplus is trimmed from the END — the boss is entry 0 and can
## therefore never be trimmed away. Never pads (a shorter table simply yields fewer).
static func _filter_spawns(difficulty: String) -> Array:
	var spawns: Array = _filter_spawn_list(ENEMY_SPAWNS, difficulty)
	var budget := enemy_total(difficulty)
	if budget > 0 and spawns.size() > budget:
		spawns = spawns.slice(0, budget)
	return spawns


## Like _filter_spawns, but over an arbitrary spawn list (F3 + F4 share the rule).
static func _filter_spawn_list(list: Array, difficulty: String) -> Array:
	var spawns: Array = []
	for es in list:
		var tag := String(es["diff"])
		if tag == "all":
			spawns.append({"cell": es["cell"], "type": es["type"], "diff": es["diff"]})
		elif tag == "normal" and difficulty != "leicht":
			spawns.append({"cell": es["cell"], "type": es["type"], "diff": es["diff"]})
		elif tag == "hard" and difficulty == "schwer":
			spawns.append({"cell": es["cell"], "type": es["type"], "diff": es["diff"]})
	# EASY: no elite guards (spec §3.3.3 puts them on HARD only, so the "hard" tag
	# already keeps them out — this stays as a safety net if the table ever changes).
	if difficulty == "leicht":
		var downgrade := {"elite": "miliz_k45", "elite_flinte": "miliz_flinte"}
		var eased: Array = []
		for es in spawns:
			var t := String(es["type"])
			if downgrade.has(t):
				eased.append({"cell": es["cell"], "type": downgrade[t], "diff": es["diff"]})
			else:
				eased.append(es)
		spawns = eased
	return spawns

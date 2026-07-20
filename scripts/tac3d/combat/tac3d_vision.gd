class_name Tac3DVision
extends RefCounted
# Grid LOS + sight in 3D (NO physics raycast).
# 1:1 port from tactical.gd (los/unit_sees/unit_sees_from/cover_at), except:
#   - y -> z (flat distances on (x, z), spec §3/§7.2)
#   - sight[] (transparent) -> Tac3DTile.blocks_sight (opaque, INVERTED)
#   - height bonus is additive (spec §6.2 rooftop sniper)
# K2: compute_visible does NOT live here but in the orchestrator (per target cell).

var grid: Grid3D
const HEIGHT_SIGHT_BONUS := 3.0     # sight range per level of height advantage


# The single conversion point Vector3i -> flat (x, z) plane.
static func flat(c: Vector3i) -> Vector2:
	return Vector2(c.x, c.z)


# Bresenham on (x, z) — exactly the v2 algorithm (tactical.gd:280-302).
# The target cell never blocks (same as v2).
func los(a: Vector3i, b: Vector3i) -> bool:
	var x0 := a.x
	var z0 := a.z
	var dx := absi(b.x - x0)
	var dz := absi(b.z - z0)
	var sx := 1 if b.x > x0 else -1
	var sz := 1 if b.z > z0 else -1
	var err := dx - dz
	while true:
		if x0 == b.x and z0 == b.z:
			return true
		var e2 := err * 2
		if e2 > -dz:
			err -= dz
			x0 += sx
		if e2 < dx:
			err += dx
			z0 += sz
		if x0 == b.x and z0 == b.z:
			return true
		if _sight_blocked(x0, z0, a.y, b.y):
			return false
	return true


# Blocker on the observer's level; if no tile exists there, check the target level.
func _sight_blocked(x: int, z: int, obs_y: int, tgt_y: int) -> bool:
	var t := grid.get_tile(Vector3i(x, obs_y, z))
	if t == null:
		t = grid.get_tile(Vector3i(x, tgt_y, z))
	return t != null and t.blocks_sight


# Effective sight range: base + the observer's height advantage (spec §6.2).
func sight_of(u: Tac3DUnit, target: Vector3i) -> float:
	var base := float(u.data["sight"])
	return base + maxf(0.0, float(u.cell.y - target.y)) * HEIGHT_SIGHT_BONUS


# 1:1 from tactical.gd:304-306 — flat distance <= sight range AND LOS.
func unit_sees(u: Tac3DUnit, target: Vector3i) -> bool:
	var d := flat(u.cell).distance_to(flat(target))
	return d <= sight_of(u, target) and los(u.cell, target)


# 1:1 from tactical.gd:1191-1192 (unit_sees_from) — AI reposition from a hypothetical cell.
func sees_from(from: Vector3i, u: Tac3DUnit, target: Vector3i) -> bool:
	var s := float(u.data["sight"]) + maxf(0.0, float(from.y - target.y)) * HEIGHT_SIGHT_BONUS
	return flat(from).distance_to(flat(target)) <= s and los(from, target)


# Cover -25% (best neighbour in the shooter's direction). Port of tactical.gd:492-500.
# 3D: Vector3i, flat direction sign(f.x-t.x), sign(f.z-t.z).
func cover_at(target: Vector3i, from: Vector3i) -> float:
	var s := Vector3i(signi(from.x - target.x), 0, signi(from.z - target.z))
	if s == Vector3i.ZERO:
		return 0.0
	var best := 0.0
	var cands := [
		target + s,
		target + Vector3i(s.x, 0, 0),
		target + Vector3i(0, 0, s.z),
	]
	for cand in cands:
		var c: Vector3i = cand
		if c == target:
			continue
		var t := grid.get_tile(c)
		if t != null:
			best = maxf(best, t.cover)
	return best


# ================================================ Fog of war (SPEC §6, ADDITIVE)
# Everything below is NEW and read-only: it reuses los()/HEIGHT_SIGHT_BONUS
# unchanged and computes NO new metric. No existing signature or formula is
# touched — the combat maths and the --smoke3d assertions stay exactly as they were.
# Consumer: FogView3D (scripts/tac3d/fog_view3d.gd), display only.

## Per-unit cache so the union scan does not run for EVERY merc on EVERY movement
## step. Keyed by instance id (NOT by object reference -> no dangling pointers to
## freed units after a sector change). Entry: {cell, sight, set}.
## Tile.blocks_sight is written once at map generation and never mutated at
## runtime, so a cache keyed on (cell, sight) can never go stale.
var _seen_cache: Dictionary = {}
const SEEN_CACHE_MAX := 16


## Drops the cache (optional — the cap clears it by itself). Call after a sector swap.
func clear_seen_cache() -> void:
	_seen_cache.clear()


## The set of cells ONE unit can see right now: Vector3i -> true.
## Uses exactly the unit_sees() metric (flat distance <= sight_of, then los), but
## scans outward from the observer instead of testing a single target cell.
## The returned dictionary is CACHE-OWNED — read it, never modify it.
func cells_seen_by(u: Tac3DUnit) -> Dictionary:
	if grid == null or u == null:
		return {}
	var base := float(u.data.get("sight", 0.0))
	if base <= 0.0:
		return {}
	var key := u.get_instance_id()
	var hit = _seen_cache.get(key, null)
	if hit != null and hit["cell"] == u.cell and is_equal_approx(float(hit["sight"]), base):
		var cached: Dictionary = hit["set"]
		return cached
	var out := _scan_seen(u.cell, base)
	if _seen_cache.size() >= SEEN_CACHE_MAX:
		_seen_cache.clear()
	_seen_cache[key] = {"cell": u.cell, "sight": base, "set": out}
	return out


## Union over several units (hand in the merc array) -> Vector3i -> true.
## Dead/freed units are skipped. THE call for FogView3D.refresh().
func cells_seen_by_units(units: Array) -> Dictionary:
	var out: Dictionary = {}
	if grid == null:
		return out
	for m in units:
		# validity check BEFORE the typed assignment (a freed object must never
		# land in a typed variable).
		if m == null or not is_instance_valid(m):
			continue
		var u: Tac3DUnit = m
		if not u.alive:
			continue
		for k in cells_seen_by(u):
			var c: Vector3i = k
			out[c] = true
	return out


## Outward scan over every level of the grid. Per level the sight range is
## base + height bonus (identical to sight_of), the bounding box is derived from
## it and the cheap radius test runs BEFORE the dictionary lookup and the LOS walk.
func _scan_seen(oc: Vector3i, base: float) -> Dictionary:
	var out: Dictionary = {}
	for y in range(grid.min_level, grid.max_level + 1):
		# Height bonus only counts DOWNWARDS (observer above the target) — sight_of.
		var r := base + maxf(0.0, float(oc.y - y)) * HEIGHT_SIGHT_BONUS
		var r2 := r * r
		var ri := ceili(r)
		for x in range(oc.x - ri, oc.x + ri + 1):
			var dx := float(x - oc.x)
			var dx2 := dx * dx
			if dx2 > r2:
				continue
			for z in range(oc.z - ri, oc.z + ri + 1):
				var dz := float(z - oc.z)
				if dx2 + dz * dz > r2:
					continue
				var c := Vector3i(x, y, z)
				if not grid.has_tile(c):
					continue
				if los(oc, c):
					out[c] = true
	return out

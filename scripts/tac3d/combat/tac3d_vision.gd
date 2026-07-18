class_name Tac3DVision
extends RefCounted
# Gitter-LOS + Sicht in 3D (KEIN Physik-Raycast).
# 1:1-Port aus tactical.gd (los/unit_sees/unit_sees_from/cover_at), nur:
#   - y -> z (flache Distanzen auf (x, z), spec §3/§7.2)
#   - sight[] (transparent) -> Tac3DTile.blocks_sight (opak, INVERTIERT)
#   - Höhenbonus additiv (spec §6.2 Dach-Sniper)
# K2: compute_visible liegt NICHT hier, sondern im Orchestrator (pro Zielzelle).

var grid: Grid3D
const HEIGHT_SIGHT_BONUS := 3.0     # Sichtweite je Ebene Höhenvorteil


# Einziger Umrechnungspunkt Vector3i -> flache (x, z)-Ebene.
static func flat(c: Vector3i) -> Vector2:
	return Vector2(c.x, c.z)


# Bresenham auf (x, z) — exakt der v2-Algorithmus (tactical.gd:280-302).
# Die Zielzelle blockt nie (wie v2).
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


# Blocker auf der Beobachter-Ebene; existiert dort keine Kachel, Ziel-Ebene prüfen.
func _sight_blocked(x: int, z: int, obs_y: int, tgt_y: int) -> bool:
	var t := grid.get_tile(Vector3i(x, obs_y, z))
	if t == null:
		t = grid.get_tile(Vector3i(x, tgt_y, z))
	return t != null and t.blocks_sight


# Effektive Sichtweite: Basis + Höhenvorteil des Beobachters (spec §6.2).
func sight_of(u: Tac3DUnit, target: Vector3i) -> float:
	var base := float(u.data["sight"])
	return base + maxf(0.0, float(u.cell.y - target.y)) * HEIGHT_SIGHT_BONUS


# 1:1 aus tactical.gd:304-306 — flache Distanz <= Sichtweite UND LOS.
func unit_sees(u: Tac3DUnit, target: Vector3i) -> bool:
	var d := flat(u.cell).distance_to(flat(target))
	return d <= sight_of(u, target) and los(u.cell, target)


# 1:1 aus tactical.gd:1191-1192 (unit_sees_from) — KI-Reposition von hypothetischer Zelle.
func sees_from(from: Vector3i, u: Tac3DUnit, target: Vector3i) -> bool:
	var s := float(u.data["sight"]) + maxf(0.0, float(from.y - target.y)) * HEIGHT_SIGHT_BONUS
	return flat(from).distance_to(flat(target)) <= s and los(from, target)


# Deckung -25% (bester Nachbar in Schützenrichtung). Port tactical.gd:492-500.
# 3D: Vector3i, flache Richtung sign(f.x-t.x), sign(f.z-t.z).
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

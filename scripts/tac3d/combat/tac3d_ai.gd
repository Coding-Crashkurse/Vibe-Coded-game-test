class_name Tac3DAI
extends RefCounted
# Enemy AI in 3D. 1:1 port of tactical.gd:ai_act (lines 1110-1189).
# All distances run FLAT on (x, z) via Tac3DVision.flat (spec §3/§7.2).
# Callbacks/state live in the orchestrator (Tac3DCombat).
#
# GDScript trap §7.6: `ctl` MUST stay UNTYPED (Tac3DAI <-> Tac3DCombat would
# otherwise be a cycle -> "Could not resolve class"). That is why all ctl.*
# return values are Variant and get bound to typed vars (var p: Array = ...)
# (trap §7.1).

var ctl                 # Tac3DCombat orchestrator — UNTYPED (cycle trap)


func setup(controller) -> void:
	ctl = controller


# Visible, living mercs from e's point of view (port of _enemy_visible_mercs).
func _visible_mercs(e: Tac3DUnit) -> Array:
	var out: Array = []
	for m in ctl.mercs:
		var merc: Tac3DUnit = m
		if merc.alive and ctl.unit_sees(e, merc.cell):
			out.append(merc)
	return out


# Sentry leash (port of tactical.gd:310-315): boss sticks (2), elites at the
# estate (5), militia hunts freely (9999). Flat.
func leash_for(e: Tac3DUnit) -> float:
	if e == ctl.boss:
		return 2.0
	if not e.is_merc and String(e.data.get("type", "")).begins_with("elite"):
		return 5.0
	return 9999.0


# Target-selection score (port of tactical.gd:1155-1159): prefer hit chance +
# wounding - flat distance. Best living, visible merc.
func best_target(e: Tac3DUnit, vism: Array) -> Tac3DUnit:
	var best: Tac3DUnit = null
	var best_score := -999.0
	for m in vism:
		var merc: Tac3DUnit = m
		var sc := float(ctl.hit_chance(e, merc)) \
			+ float(merc.hp_max() - merc.hp()) * 0.3 \
			- e.flat().distance_to(merc.flat())
		if sc > best_score:
			best_score = sc
			best = merc
	return best


# Coroutine — port of ai_act (tactical.gd:1110-1189). Idle wandering, noise
# investigation with leash, target selection, reposition at ch<22, shot.
func act(e: Tac3DUnit) -> void:
	if not e.alive or ctl.battle_over:
		return
	var vism: Array = _visible_mercs(e)
	if not vism.is_empty():
		e.data["alerted"] = true
		ctl.alert_enemies(vism[0].cell, e.cell, 6.0)
	# --- Not alerted: occasionally wander aimlessly, then done ---
	if not bool(e.data.get("alerted", false)):
		if randf() < 0.45:
			for attempt in 8:
				var c: Vector3i = e.cell + Vector3i(randi_range(-3, 3), 0, randi_range(-3, 3))
				if ctl.grid.is_walkable(c) and not ctl.occupied.has(c):
					var p: Array = ctl.path_for(e, c)
					if p.size() > 1:
						# preserve integer division (e.ap is int)
						var pref: Array = ctl.prefix_for_ap(p, e.ap / 2)
						await ctl.do_move(e, pref)
						break
		return
	if e.seen and not ctl.fast:
		await ctl.dl(0.25)
	var w: Dictionary = Db.weapon(e.data["weapon"])
	# --- Alerted, but nobody in sight: investigate the noise source ---
	if vism.is_empty():
		var tgt: Vector3i = ctl.noise_at
		if ctl.grid.get_tile(tgt) == null:
			return
		# sentries hold position instead of chasing after the noise source
		if Tac3DVision.flat(tgt).distance_to(Tac3DVision.flat(e.home)) > leash_for(e):
			return
		if Tac3DVision.flat(e.cell).distance_to(Tac3DVision.flat(tgt)) <= 2.0:
			tgt = e.cell + Vector3i(randi_range(-4, 4), 0, randi_range(-4, 4))
			if ctl.grid.get_tile(tgt) == null:
				return
		var p: Array = ctl.path_toward(e, tgt)
		if p.size() > 1:
			var reserve: int = int(w["ap"])
			var pref: Array = ctl.prefix_for_ap(p, maxi(2, e.ap - reserve))
			await ctl.do_move(e, pref)
		vism = _visible_mercs(e)
	# --- Fire loop: aim, reposition if needed, shoot ---
	var moved := false
	var guard := 0
	while not ctl.battle_over and e.alive and e.ap >= int(w["ap"]) and guard < 12:
		guard += 1
		vism = _visible_mercs(e)
		if vism.is_empty():
			break
		var best: Tac3DUnit = best_target(e, vism)
		if best == null:
			break
		if int(e.data["ammo"]) <= 0:
			if e.ap >= int(w["reload"]):
				ctl.do_reload(e)
				continue
			break
		var ch: int = ctl.hit_chance(e, best)
		# reposition on a poor chance (not the boss, once per turn)
		if ch < 22 and not moved and e.ap >= int(w["ap"]) + 4 and e != ctl.boss:
			var bestc := Vector3i(-99, 0, -99)
			var bestv := float(ch)
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var c: Vector3i = e.cell + Vector3i(dx, 0, dz)
					if not ctl.grid.is_walkable(c) or ctl.occupied.has(c):
						continue
					if not ctl.vision.sees_from(c, e, best.cell):
						continue
					var virt: float = float(e.data["marks"]) \
						- Tac3DVision.flat(c).distance_to(best.flat()) / float(w["range"]) * 30.0 \
						+ ctl.cover_at(c, best.cell) * 40.0
					if virt > bestv:
						bestv = virt
						bestc = c
			if bestc.x > -50:
				var p2: Array = ctl.path_for(e, bestc)
				if p2.size() > 1:
					moved = true
					var pref: Array = ctl.prefix_for_ap(p2, e.ap - int(w["ap"]))
					await ctl.do_move(e, pref)
					continue
			moved = true
		await ctl.shoot(e, best)

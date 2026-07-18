class_name Tac3DAI
extends RefCounted
# Gegner-KI in 3D. 1:1-Port von tactical.gd:ai_act (Zeilen 1110-1189).
# Alle Distanzen laufen FLACH auf (x, z) via Tac3DVision.flat (spec §3/§7.2).
# Callbacks/Zustand liegen im Orchestrator (Tac3DCombat).
#
# GDScript-Falle §7.6: `ctl` MUSS UNTYPED bleiben (Tac3DAI <-> Tac3DCombat
# waeren sonst ein Zyklus -> "Could not resolve class"). Deshalb sind alle
# ctl.*-Rueckgaben Variant und werden an typisierte Vars (var p: Array = ...)
# gebunden (Falle §7.1).

var ctl                 # Tac3DCombat-Orchestrator — UNTYPED (Zyklus-Falle)


func setup(controller) -> void:
	ctl = controller


# Sichtbare, lebende Soeldner aus Sicht von e (Port _enemy_visible_mercs).
func _visible_mercs(e: Tac3DUnit) -> Array:
	var out: Array = []
	for m in ctl.mercs:
		var merc: Tac3DUnit = m
		if merc.alive and ctl.unit_sees(e, merc.cell):
			out.append(merc)
	return out


# Wachposten-Leine (Port tactical.gd:310-315): Boss klebt (2), Eliten am
# Anwesen (5), Miliz jagt frei (9999). Flach.
func leash_for(e: Tac3DUnit) -> float:
	if e == ctl.boss:
		return 2.0
	if not e.is_merc and String(e.data.get("type", "")).begins_with("elite"):
		return 5.0
	return 9999.0


# Zielwahl-Score (Port tactical.gd:1155-1159): Trefferchance + Verwundung
# bevorzugen - flache Distanz. Bester lebender, sichtbarer Merc.
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


# Coroutine — Port ai_act (tactical.gd:1110-1189). Idle-Wandern, Laerm-
# Untersuchung mit Leine, Zielwahl, Reposition bei ch<22, Schuss.
func act(e: Tac3DUnit) -> void:
	if not e.alive or ctl.battle_over:
		return
	var vism: Array = _visible_mercs(e)
	if not vism.is_empty():
		e.data["alerted"] = true
		ctl.alert_enemies(vism[0].cell, e.cell, 6.0)
	# --- Nicht alarmiert: gelegentlich ziellos wandern, dann fertig ---
	if not bool(e.data.get("alerted", false)):
		if randf() < 0.45:
			for attempt in 8:
				var c: Vector3i = e.cell + Vector3i(randi_range(-3, 3), 0, randi_range(-3, 3))
				if ctl.grid.is_walkable(c) and not ctl.occupied.has(c):
					var p: Array = ctl.path_for(e, c)
					if p.size() > 1:
						# Integer-Division bewahren (e.ap ist int)
						var pref: Array = ctl.prefix_for_ap(p, e.ap / 2)
						await ctl.do_move(e, pref)
						break
		return
	if e.seen and not ctl.fast:
		await ctl.dl(0.25)
	var w: Dictionary = Db.weapon(e.data["weapon"])
	# --- Alarmiert, aber niemand in Sicht: Geraeuschquelle untersuchen ---
	if vism.is_empty():
		var tgt: Vector3i = ctl.noise_at
		if ctl.grid.get_tile(tgt) == null:
			return
		# Wachposten halten Stellung statt der Geraeuschquelle hinterherzurennen
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
	# --- Feuer-Schleife: zielen, ggf. reposition, schiessen ---
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
		# Reposition bei schlechter Chance (nicht Boss, einmal pro Zug)
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

extends Node2D
## Taktische Mission »Sektor 43 — Silberquell« im JA1-Stil.
## Anmarschphase → Rundenkampf. Sichtfelder, Deckung, Unterbrechungen,
## gezielte Schüsse, Slot-Inventar, Magazin-Munition, Kisten-/Leichen-Loot,
## Boss-Dialog. HUD mit Portrait-Seitenleisten.

signal battle_ready
signal battle_finished(result: String)
signal dialog_next
signal dialog_choice(i: int)

const TILE := 64

# Kartendaten
var map: Dictionary
var W := 0
var H := 0
var walk: Array = []
var sight: Array = []
var cover: Array = []
var destruct: Array = []
var surface: Array = []
var props_by_cell := {}
var loot_cells: Array = []
var looted := {}

# Einheiten
var units: Array = []
var mercs: Array = []
var enemies: Array = []
var boss: BattleUnit = null
var occupied := {}
var corpses := {}
var astar: AStarGrid2D

# Zustand
var selected: BattleUnit = null
var mode := "move"           # "move" | "grenade"
var aim_level := 0           # Gezielter Schuss in Stufen 0–3 (JA1-Zielen)
var player_turn := true
var busy := false
var battle_over := false
var combat_started := false  # Anmarschphase: frei bewegen bis Feindkontakt
var no_contact_rounds := 0   # Runden ohne Sichtkontakt → zurück in Erkundung
var noise_at := Vector2i(-99, -99)
var turn := 1
var fast := false
var loot_rng := RandomNumberGenerator.new()

# Hover
var hover_cell := Vector2i(-1, -1)
var hover_path: Array = []
var hover_cost := 0
var hover_unit: BattleUnit = null
var hover_search := ""       # "crate" | "corpse" | ""

# Sicht
var vis: Array = []
var fog_img: Image
var fog_tex: ImageTexture
var ghosts := {}

# Nodes
var cam: Camera2D
var overlay: Node2D
var hud: CanvasLayer
var hud_root: Control
var top_label: Label
var enemy_label: Label
var cursor_panel: PanelContainer
var cursor_label: Label
var banner_label: Label
var slot_boxes: Array = []
var weapon_label: Label
var ammo_label: Label
var mags_label: Label
var reload_btn: Button
var aim_btn: Button
var grenade_btn: Button
var medkit_btn: Button
var inv_btn: Button
var endturn_btn: Button
var pause_panel: Control = null
var inv_panel: Control = null
var inv_sel := -1

func _main() -> Node:
	return get_parent()

# ============================================================ Aufbau

func _ready() -> void:
	var pf = _main().get("fast")
	fast = pf == true
	loot_rng.seed = 987654 + hash(Game.difficulty)
	map = MapGen.generate(20260718, Game.difficulty)
	W = map["w"]
	H = map["h"]
	walk = map["walk"]
	sight = map["sight"]
	cover = map["cover"]
	destruct = map["destruct"]
	surface = map["surface"]
	loot_cells = map["loot_cells"]

	var ground := Sprite2D.new()
	ground.texture = map["ground"]
	ground.centered = false
	ground.z_index = -10
	add_child(ground)

	for p in map["props"]:
		var s := Sprite2D.new()
		s.texture = Assets.tex(p["name"])
		s.position = cell_center(p["cell"])
		s.rotation = p["rot"]
		s.modulate = p["mod"]
		s.scale = Vector2.ONE * float(p["scale"])
		var nm: String = p["name"]
		if nm.begins_with("tree_side"):
			s.offset = Vector2(0, -16)   # Baumfuß steht auf der Zelle, Krone ragt nach Norden
		s.z_index = 6 if (nm.begins_with("tree") or nm.begins_with("bush")) else 2
		add_child(s)
		props_by_cell[p["cell"]] = s

	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in H:
		for x in W:
			astar.set_point_solid(Vector2i(x, y), not walk[y * W + x])

	var spawns: Array = map["merc_spawns"]
	for i in Game.team.size():
		var u := BattleUnit.new()
		u.setup(Game.team[i], true)
		add_child(u)
		u.set_cell(spawns[i % spawns.size()])
		u.face_pos(u.position + Vector2(10, -10))
		_occupy(u, u.cell)
		units.append(u)
		mercs.append(u)

	for es in map["enemy_spawns"]:
		var def: Dictionary = Db.ENEMY_TYPES[es["type"]].duplicate(true)
		var w: Dictionary = Db.weapon(def["weapon"])
		var d := {
			"name": def["name"], "hp": def["hp"], "hp_max": def["hp"],
			"marks": int(def["marks"]) + int(Game.diff()["marks_mod"]), "agi": def["agi"], "med": 0,
			"weapon": def["weapon"], "ammo": int(w["mag"]),
			"inv": [], "ammo_store": {},
			"armor": float(def["armor"]), "sight": int(def["sight"]),
			"sprite": def["sprite"], "tint": def["tint"], "scale": float(def["scale"]),
			"kills": 0, "alive": true, "type": es["type"], "alerted": false, "searched": false,
			"exp": int(def.get("exp", 1)),
		}
		var u := BattleUnit.new()
		u.setup(d, false)
		add_child(u)
		u.set_cell(es["cell"])
		u.home = es["cell"]
		u.sprite.rotation = randf_range(0, TAU)
		_occupy(u, u.cell)
		units.append(u)
		enemies.append(u)
		u.set_seen(false)
		if es["type"] == "boss":
			boss = u
			u.home = map["boss_home"]

	overlay = Node2D.new()
	overlay.z_index = 30
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)

	fog_img = Image.create_empty(W, H, false, Image.FORMAT_RGBA8)
	fog_img.fill(Color(0, 0, 0, 0.5))
	fog_tex = ImageTexture.create_from_image(fog_img)
	var fog_sprite := Sprite2D.new()
	fog_sprite.texture = fog_tex
	fog_sprite.centered = false
	fog_sprite.scale = Vector2(TILE, TILE)
	fog_sprite.z_index = 40
	add_child(fog_sprite)

	cam = Camera2D.new()
	cam.position = cell_center(spawns[0]) + Vector2(120, -120)
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = W * TILE
	cam.limit_bottom = H * TILE
	add_child(cam)
	cam.make_current()
	_clamp_zoom()

	_build_hud()
	vis.resize(W * H)
	compute_vision()
	if mercs.size() > 0:
		select_merc(mercs[0])
	refresh_hud()
	Sfx.play_music("exploration")
	if not fast:
		banner_show("ANMARSCH AUF SILBERQUELL — frei bewegen bis Feindkontakt", 2.0)
	battle_ready.emit.call_deferred()

func _occupy(u: BattleUnit, c: Vector2i) -> void:
	occupied[c] = u
	astar.set_point_solid(c, true)

func _vacate(c: Vector2i) -> void:
	occupied.erase(c)
	astar.set_point_solid(c, not walk[c.y * W + c.x])

func idx(c: Vector2i) -> int:
	return c.y * W + c.x

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < W and c.y >= 0 and c.y < H

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c) * TILE + Vector2(TILE / 2.0, TILE / 2.0)

func dl(t: float) -> void:
	if fast:
		return
	await get_tree().create_timer(t).timeout

# ============================================================ Inventar-Helfer

func inv_of(u: BattleUnit) -> Array:
	return u.data["inv"]

func inv_count(u: BattleUnit, id: String) -> int:
	var n := 0
	for it in inv_of(u):
		if String(it) == id:
			n += 1
	return n

func inv_count_kind(u: BattleUnit, kind: String) -> int:
	var n := 0
	for it in inv_of(u):
		if String(Db.item(String(it))["kind"]) == kind:
			n += 1
	return n

func inv_take(u: BattleUnit, id: String) -> bool:
	var inv := inv_of(u)
	for i in inv.size():
		if String(inv[i]) == id:
			inv.remove_at(i)
			return true
	return false

func inv_add(u: BattleUnit, id: String) -> bool:
	if inv_of(u).size() >= Db.INV_SLOTS:
		return false
	inv_of(u).append(id)
	return true

func mags_for(u: BattleUnit) -> int:
	var cal := String(Db.weapon(u.data["weapon"])["cal"])
	var n := 0
	for it in inv_of(u):
		var d: Dictionary = Db.item(String(it))
		if String(d["kind"]) == "ammo" and String(d.get("cal", "")) == cal:
			n += 1
	return n

func _mag_item_for(cal: String) -> String:
	return "mag_" + cal

# ============================================================ Sicht / LOS

func los(a: Vector2i, b: Vector2i) -> bool:
	var x0 := a.x
	var y0 := a.y
	var dx := absi(b.x - x0)
	var dy := absi(b.y - y0)
	var sx := 1 if b.x > x0 else -1
	var sy := 1 if b.y > y0 else -1
	var err := dx - dy
	while true:
		if x0 == b.x and y0 == b.y:
			return true
		var e2 := err * 2
		if e2 > -dy:
			err -= dy
			x0 += sx
		if e2 < dx:
			err += dx
			y0 += sy
		if x0 == b.x and y0 == b.y:
			return true
		if not sight[y0 * W + x0]:
			return false
	return true

func unit_sees(u: BattleUnit, target_cell: Vector2i) -> bool:
	var d := Vector2(u.cell).distance_to(Vector2(target_cell))
	return d <= float(u.data["sight"]) and los(u.cell, target_cell)

## Wachposten-Leine: Boss klebt am Thron, Eliten bleiben am Anwesen,
## Miliz darf frei jagen.
func _leash_for(u: BattleUnit) -> float:
	if u == boss:
		return 2.0
	if not u.is_merc and String(u.data.get("type", "")).begins_with("elite"):
		return 5.0
	return 9999.0

## Lärm/Sichtung: alarmiert Gegner in Hörweite um `center`.
func alert_enemies(investigate: Vector2i, center: Vector2i, radius: float) -> void:
	noise_at = investigate
	for e in enemies:
		if e.alive and Vector2(e.cell).distance_to(Vector2(center)) <= radius:
			e.data["alerted"] = true

func _any_contact() -> bool:
	if visible_enemies().size() > 0:
		return true
	for e in enemies:
		if not e.alive:
			continue
		for m in mercs:
			if m.alive and unit_sees(e, m.cell):
				return true
	return false

## Erster Feindkontakt: Anmarschphase endet, Rundenkampf beginnt.
func start_combat() -> void:
	if combat_started:
		return
	combat_started = true
	no_contact_rounds = 0
	for u2 in units:
		u2.ap = u2.ap_max
		u2.interrupt_used = false
		u2.queue_redraw()
	Sfx.play("interrupt", -2.0)
	Sfx.play_music("combat")
	banner_show("FEINDKONTAKT — Rundenkampf beginnt!", 1.5)
	refresh_hud()

## 2 Runden ohne Sichtkontakt: zurück in den Erkundungsmodus (JA-Gefühl)
func _end_combat_mode() -> void:
	combat_started = false
	no_contact_rounds = 0
	for m in mercs:
		m.ap = m.ap_max
		m.queue_redraw()
	Sfx.play_music("exploration")
	banner_show("Kein Feindkontakt — Erkundungsmodus", 1.6)
	refresh_hud()

func compute_vision() -> void:
	for i in vis.size():
		vis[i] = false
	for m in mercs:
		if not m.alive:
			continue
		var r := int(m.data["sight"])
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c: Vector2i = m.cell + Vector2i(dx, dy)
				if not in_bounds(c):
					continue
				if vis[idx(c)]:
					continue
				if Vector2(dx, dy).length() <= float(r) and los(m.cell, c):
					vis[idx(c)] = true
	for y in H:
		for x in W:
			fog_img.set_pixel(x, y, Color(0, 0, 0, 0.0 if vis[y * W + x] else 0.5))
	fog_tex.update(fog_img)
	for e in enemies:
		var was: bool = e.seen
		var now: bool = e.alive and vis[idx(e.cell)]
		e.set_seen(now)
		if e.alive and was and not now:
			_ghost_add(e)
		elif now:
			_ghost_remove(e)
	_update_enemy_label()

func _ghost_add(e: BattleUnit) -> void:
	_ghost_remove(e)
	var l := Label.new()
	l.text = "?"
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4, 0.85))
	l.position = cell_center(e.cell) - Vector2(9, 22)
	l.z_index = 45
	add_child(l)
	ghosts[e] = l

func _ghost_remove(e: BattleUnit) -> void:
	if ghosts.has(e):
		ghosts[e].queue_free()
		ghosts.erase(e)

func visible_enemies() -> Array:
	var out: Array = []
	for e in enemies:
		if e.alive and e.seen:
			out.append(e)
	return out

# ============================================================ Pfade

func path_for(u: BattleUnit, target: Vector2i) -> Array:
	if not in_bounds(target) or not walk[idx(target)] or occupied.has(target):
		return []
	astar.set_point_solid(u.cell, false)
	var p := astar.get_id_path(u.cell, target)
	astar.set_point_solid(u.cell, true)
	return p

func path_toward(u: BattleUnit, target: Vector2i) -> Array:
	if in_bounds(target) and walk[idx(target)] and not occupied.has(target):
		var direct := path_for(u, target)
		if direct.size() > 1:
			return direct
	var best: Array = []
	var best_len := 999999
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var n := target + Vector2i(dx, dy)
			if not in_bounds(n) or not walk[idx(n)] or occupied.has(n):
				continue
			var p := path_for(u, n)
			if p.size() > 1 and p.size() < best_len:
				best = p
				best_len = p.size()
	return best

func step_cost(a: Vector2i, b: Vector2i) -> int:
	return 3 if (a.x != b.x and a.y != b.y) else 2

func path_cost(p: Array) -> int:
	var c := 0
	for i in range(1, p.size()):
		c += step_cost(p[i - 1], p[i])
	return c

func prefix_for_ap(p: Array, ap: int) -> Array:
	var out: Array = []
	if p.is_empty():
		return out
	out.append(p[0])
	var c := 0
	for i in range(1, p.size()):
		c += step_cost(p[i - 1], p[i])
		if c > ap:
			break
		out.append(p[i])
	return out

# ============================================================ Kampfwerte

func shot_ap(u: BattleUnit, aim := 0) -> int:
	return int(Db.weapon(u.data["weapon"])["ap"]) + int(Db.AIM["ap_step"]) * aim

## Erfahrungsstufe (1–6): Söldner steigen über Abschüsse auf, Gegner sind fix.
func level_of(u: BattleUnit) -> int:
	if u.is_merc:
		return mini(6, int(u.data.get("exp", 1)) + int(u.data.get("kills", 0)) / 2)
	return int(u.data.get("exp", 1))

func hit_chance(att: BattleUnit, def: BattleUnit, aim := 0) -> int:
	var w: Dictionary = Db.weapon(att.data["weapon"])
	var d := Vector2(att.cell).distance_to(Vector2(def.cell))
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
	return clampi(int(ch), 5, 95)

func cover_at(target: Vector2i, from: Vector2i) -> float:
	var s := Vector2i(signi(from.x - target.x), signi(from.y - target.y))
	if s == Vector2i.ZERO:
		return 0.0
	var best := 0.0
	for cand in [target + s, target + Vector2i(s.x, 0), target + Vector2i(0, s.y)]:
		if cand != target and in_bounds(cand):
			best = maxf(best, float(cover[idx(cand)]))
	return best

func throw_range(u: BattleUnit) -> int:
	return 5 + int(u.data["agi"]) / 8

func grenade_valid(u: BattleUnit, c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var d := Vector2(u.cell).distance_to(Vector2(c))
	return d <= float(throw_range(u)) and d >= 1.0 and los(u.cell, c)

# ============================================================ Aktionen

func do_move(u: BattleUnit, p: Array) -> void:
	if p.size() < 2 or battle_over:
		return
	busy = true
	refresh_hud()
	var observers := {}
	var watchers: Array = enemies if u.is_merc else mercs
	for o in watchers:
		observers[o] = o.alive and unit_sees(o, u.cell)
	var seen_before := visible_enemies().size()
	for i in range(1, p.size()):
		if battle_over or not u.alive:
			break
		var to: Vector2i = p[i]
		# Wachposten-Leine (Boss: Thronsaal, Eliten: Anwesen)
		if Vector2(to).distance_to(Vector2(u.home)) > _leash_for(u):
			break
		var cst := step_cost(u.cell, to)
		if u.ap < cst or occupied.has(to):
			break
		u.ap -= cst
		_vacate(u.cell)
		u.face_pos(cell_center(to))
		u.cell = to
		_occupy(u, to)
		if fast:
			u.position = cell_center(to)
		else:
			if u.is_merc or u.seen:
				Sfx.play_step(["grass", "wood", "stone"][int(surface[idx(to)])])
			var tw := create_tween()
			tw.tween_property(u, "position", cell_center(to), 0.11)
			await tw.finished
		compute_vision()
		u.queue_redraw()
		# Anmarschphase endet beim ersten Sichtkontakt
		var contact_now := false
		if not combat_started and u.is_merc and _any_contact():
			contact_now = true
			start_combat()
		# Unterbrechungen
		for o in watchers:
			if battle_over or not u.alive:
				break
			if not o.alive or o.interrupt_used:
				continue
			var sees_now: bool = unit_sees(o, u.cell)
			if sees_now and not bool(observers.get(o, false)):
				observers[o] = true
				var ow: Dictionary = Db.weapon(o.data["weapon"])
				var d := Vector2(o.cell).distance_to(Vector2(u.cell))
				if o.ap >= int(ow["ap"]) and d <= float(ow["range"]) + 2.0 and int(o.data["ammo"]) > 0:
					# Erfahrung bestimmt die Unterbrechungs-Chance (JA1)
					var chance := 15 + level_of(o) * 7 + int(o.data["agi"]) / 6
					if randi_range(1, 100) <= chance:
						o.interrupt_used = true
						if not o.is_merc:
							o.data["alerted"] = true
						Sfx.play("interrupt")
						banner_show("UNTERBRECHUNG! %s" % o.display_name(), 0.9)
						await dl(0.35)
						await shoot(o, u, true)
		if contact_now:
			await check_boss_dialog()
			break
		if u.is_merc and visible_enemies().size() > seen_before:
			if await check_boss_dialog():
				break
			break
		if u.is_merc:
			if await check_boss_dialog():
				break
	if u.is_merc and not combat_started:
		u.ap = u.ap_max   # Anmarsch: Bewegung kostet nichts
	busy = false
	compute_vision()
	refresh_hud()
	overlay.queue_redraw()

func shoot(att: BattleUnit, def: BattleUnit, interrupt := false) -> bool:
	if battle_over or not att.alive or not def.alive:
		return false
	var aim: int = aim_level if (att.is_merc and not interrupt) else 0
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
	att.data["ammo"] = int(att.data["ammo"]) - 1
	var investigate := att.cell if att.is_merc else def.cell
	alert_enemies(investigate, att.cell, 9.0)
	if not att.is_merc:
		att.data["alerted"] = true
	att.face_pos(def.position)
	var dirv := (def.position - att.position).normalized()
	_fx_muzzle(att.position + dirv * 24.0, dirv)
	Sfx.play(String(w["snd"]), 2.0 if bool(w["shotgun"]) else 1.0)
	if att.is_merc:
		Game.stats["shots"] = int(Game.stats["shots"]) + 1
	var ch := hit_chance(att, def, aim)
	var hit := randi_range(1, 100) <= ch
	var endp := def.position
	if not hit:
		var perp := Vector2(-dirv.y, dirv.x)
		endp = def.position + perp * randf_range(-30, 30) + dirv * randf_range(20, 60)
	_fx_tracer(att.position + dirv * 26.0, endp)
	await dl(0.13)
	if hit:
		if att.is_merc:
			Game.stats["hits"] = int(Game.stats["hits"]) + 1
		var dist := Vector2(att.cell).distance_to(Vector2(def.cell))
		var dmg := int(w["dmg"]) + randi_range(-int(w["var"]), int(w["var"]))
		if bool(w["shotgun"]) and dist > 3.0:
			dmg -= int((dist - 3.0) * 4.0)
		dmg = int(float(dmg) * (1.0 - float(def.data["armor"])))
		dmg = maxi(1, dmg)
		def.hurt(dmg)
		_fx_blood(def.position)
		_fx_float(def.position, str(dmg), Color(1, 0.45, 0.35))
		Sfx.play("hit", 1.0)
		if def.alive and not fast:
			if def.is_merc:
				Sfx.play_voice(String(def.data["id"]) + "_pain")
			elif def.seen:
				Sfx.play("pain_enemy", -2.0)
		if not def.alive:
			await on_death(att, def)
	else:
		_fx_float(def.position, "Verfehlt", Color(0.78, 0.75, 0.68))
		Sfx.play("miss", -6.0)
	compute_vision()
	refresh_hud()
	return true

func _can_reload(u: BattleUnit) -> bool:
	if not u.is_merc:
		return true
	return mags_for(u) > 0

func do_reload(u: BattleUnit) -> void:
	var w: Dictionary = Db.weapon(u.data["weapon"])
	if u.ap < int(w["reload"]) or int(u.data["ammo"]) >= int(w["mag"]):
		return
	if u.is_merc:
		if not inv_take(u, _mag_item_for(String(w["cal"]))):
			Sfx.play("ui_error")
			_fx_float(u.position, "Kein Magazin!", Color(1, 0.6, 0.4))
			return
	u.ap -= int(w["reload"])
	u.data["ammo"] = int(w["mag"])
	Sfx.play("reload")
	if u.is_merc:
		_fx_float(u.position, "Nachgeladen", Color(0.85, 0.8, 0.65))
	_refund_if_exploring(u)
	refresh_hud()

func do_medkit(u: BattleUnit) -> void:
	if inv_count(u, "medkit") <= 0 or u.ap < Db.MEDKIT_AP:
		Sfx.play("ui_error")
		return
	var target: BattleUnit = null
	var worst := 1.0
	for m in mercs:
		if not m.alive:
			continue
		if m != u and Vector2(m.cell).distance_to(Vector2(u.cell)) > 1.6:
			continue
		var frac := float(m.hp()) / float(m.hp_max())
		if frac < 1.0 and frac < worst:
			worst = frac
			target = m
	if target == null:
		Sfx.play("ui_error")
		_fx_float(u.position, "Niemand verletzt", Color(0.75, 0.72, 0.6))
		return
	u.ap -= Db.MEDKIT_AP
	inv_take(u, "medkit")
	var heal := 15 + int(u.data["med"]) / 4
	target.data["hp"] = mini(target.hp_max(), target.hp() + heal)
	target.queue_redraw()
	Sfx.play("medkit")
	_fx_float(target.position, "+%d" % heal, UiTheme.COL_GREEN)
	_refund_if_exploring(u)
	refresh_hud()

func do_swap(u: BattleUnit, slot: int) -> void:
	var inv := inv_of(u)
	if slot < 0 or slot >= inv.size() or u.ap < Db.SWAP_AP:
		Sfx.play("ui_error")
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
	u.sprite.texture = Assets.tex("%s_%s" % [String(u.data["sprite"]), String(Db.weapon(id)["pose"])])
	Sfx.play("reload")
	_fx_float(u.position, Db.weapon(id)["short"], Color(0.85, 0.8, 0.65))
	_refund_if_exploring(u)
	refresh_hud()

func do_grenade(u: BattleUnit, c: Vector2i) -> void:
	if battle_over or inv_count(u, "granate") <= 0 or u.ap < int(Db.GRENADE["ap"]) or not grenade_valid(u, c):
		Sfx.play("ui_error")
		return
	busy = true
	mode = "move"
	if not combat_started:
		start_combat()
	inv_take(u, "granate")
	u.ap -= int(Db.GRENADE["ap"])
	alert_enemies(u.cell, c, 12.0)
	u.face_pos(cell_center(c))
	Sfx.play("throw")
	var proj := Sprite2D.new()
	proj.texture = Assets.circle(6, Color(0.25, 0.32, 0.2), false)
	proj.z_index = 20
	add_child(proj)
	var a := u.position
	var b := cell_center(c)
	if fast:
		proj.position = b
	else:
		var tw := create_tween()
		tw.tween_method(func(t: float) -> void:
			proj.position = a.lerp(b, t) + Vector2(0, -sin(PI * t) * 70.0), 0.0, 1.0, 0.5)
		await tw.finished
	proj.queue_free()
	Sfx.play("explosion", 4.0)
	_fx_explosion(b)
	_shake(14.0)
	var radius: float = float(Db.GRENADE["radius"]) + 0.1
	for other in units.duplicate():
		if not other.alive:
			continue
		var d := Vector2(other.cell).distance_to(Vector2(c))
		if d <= radius:
			var dmg := int(lerpf(float(Db.GRENADE["dmg"]), float(Db.GRENADE["dmg_edge"]), clampf(d / radius, 0, 1)))
			dmg += randi_range(-4, 4)
			dmg = maxi(1, dmg)
			other.hurt(dmg)
			_fx_blood(other.position)
			_fx_float(other.position, str(dmg), Color(1, 0.6, 0.2))
			if other.alive and not fast and other.is_merc:
				Sfx.play_voice(String(other.data["id"]) + "_pain")
			if not other.alive:
				await on_death(u, other)
			if battle_over:
				break
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var cc := c + Vector2i(dx, dy)
			if not in_bounds(cc):
				continue
			if Vector2(dx, dy).length() > radius:
				continue
			if destruct[idx(cc)]:
				destruct[idx(cc)] = false
				cover[idx(cc)] = 0.0
				walk[idx(cc)] = true
				looted[cc] = true
				astar.set_point_solid(cc, occupied.has(cc))
				if props_by_cell.has(cc):
					props_by_cell[cc].queue_free()
					props_by_cell.erase(cc)
				_fx_decal(cell_center(cc), "debris", Color(1, 1, 1, 0.9), 1.0)
	_fx_decal(b, "splat_orange", Color(0.22, 0.2, 0.18, 0.9), 1.6)
	await dl(0.3)
	busy = false
	compute_vision()
	refresh_hud()
	overlay.queue_redraw()

## Erkundungsmodus: Aktionen kosten nichts — AP sofort auffüllen
func _refund_if_exploring(u: BattleUnit) -> void:
	if not combat_started and u.is_merc:
		u.ap = u.ap_max
		u.queue_redraw()

## Durchsuchen: Kisten und gefallene Gegner (JA1-Looting)
func search_target_at(c: Vector2i) -> String:
	if not in_bounds(c):
		return ""
	if destruct[idx(c)] and not looted.has(c):
		return "crate"
	if corpses.has(c):
		var e: BattleUnit = corpses[c]
		if not e.is_merc and not bool(e.data.get("searched", false)):
			return "corpse"
	return ""

func do_search(u: BattleUnit, c: Vector2i) -> void:
	var kind := search_target_at(c)
	if kind == "" or Vector2(u.cell).distance_to(Vector2(c)) > 1.6 or u.ap < Db.SEARCH_AP:
		Sfx.play("ui_error")
		return
	u.ap -= Db.SEARCH_AP
	Sfx.play("search", -4.0)
	var found: Array = []
	if kind == "crate":
		looted[c] = true
		if props_by_cell.has(c):
			props_by_cell[c].modulate = Color(0.55, 0.5, 0.45)
		if loot_rng.randf() >= 0.15:
			var n := loot_rng.randi_range(int(Game.diff()["loot_min"]), int(Game.diff()["loot_max"]))
			for k in n:
				found.append(Db.roll_loot(loot_rng))
	else:
		var e: BattleUnit = corpses[c]
		e.data["searched"] = true
		e.sprite.modulate = e.sprite.modulate.darkened(0.2)
		var cal := String(Db.weapon(e.data["weapon"])["cal"])
		var r := loot_rng.randf()
		if r < 0.4:
			found.append(_mag_item_for(cal))
		elif r < 0.55:
			found.append("granate")
	if found.is_empty():
		_fx_float(cell_center(c), "Nichts gefunden", Color(0.75, 0.72, 0.6))
	for id in found:
		if inv_add(u, String(id)):
			Game.stats["loot"] = int(Game.stats["loot"]) + 1
			_fx_float(u.position, "+ " + String(Db.item(String(id))["name"]), UiTheme.COL_GREEN)
			Sfx.play("ui_confirm", -6.0)
		else:
			_fx_float(u.position, "Inventar voll!", Color(1, 0.6, 0.4))
			break
	_refund_if_exploring(u)
	refresh_hud()

func on_death(killer: BattleUnit, dead: BattleUnit) -> void:
	var did := String(dead.data.get("id", ""))
	Sfx.play("death_f" if did in ["granate", "schatten"] else "death_m")
	dead.die_visual()
	_vacate(dead.cell)
	_ghost_remove(dead)
	if not dead.is_merc:
		corpses[dead.cell] = dead
	_fx_decal(dead.position, "splat_dark", Color(0.62, 0.08, 0.08, 0.8), randf_range(0.9, 1.2))
	if dead.is_merc:
		Game.stats["fallen"].append(dead.display_name())
		var any := false
		for m in mercs:
			if m.alive:
				any = true
				break
		if selected == dead:
			for m in mercs:
				if m.alive:
					select_merc(m)
					break
		if not any:
			await end_battle("defeat")
			return
	else:
		if killer != null and killer.is_merc:
			var lvl_before := level_of(killer)
			killer.data["kills"] = int(killer.data["kills"]) + 1
			if level_of(killer) > lvl_before:
				killer.data["marks"] = mini(95, int(killer.data["marks"]) + 2)
				_fx_float(killer.position, "★ Stufe %d!" % level_of(killer), Color(1.0, 0.85, 0.4))
				Sfx.play("ui_confirm", -4.0)
		if dead == boss:
			await _boss_defeated()
			return
		var left := false
		for e in enemies:
			if e.alive:
				left = true
				break
		if not left:
			await end_battle("victory")

func _boss_defeated() -> void:
	banner_show("VARGO IST GEFALLEN!", 1.6)
	await dl(1.0)
	var rest := 0
	for e in enemies:
		if e.alive:
			e.alive = false
			e.data["alive"] = false
			e.sprite.modulate = Color(0.6, 0.6, 0.6, 0.8)
			e.set_seen(true)
			_vacate(e.cell)
			_ghost_remove(e)
			rest += 1
	if rest > 0:
		banner_show("Die restliche Miliz ergibt sich!", 1.6)
		await dl(1.2)
	await end_battle("victory")

func end_battle(result: String) -> void:
	if battle_over:
		return
	battle_over = true
	busy = false
	Game.mission_result = result
	Game.stats["turns"] = turn
	await dl(1.0)
	battle_finished.emit(result)
	if not fast:
		_main().call_deferred("goto", "end")

# ============================================================ Boss-Dialog

func check_boss_dialog() -> bool:
	if Game.boss_dialog_seen or battle_over or boss == null or not boss.alive:
		return false
	if not vis[idx(boss.cell)]:
		return false
	Game.boss_dialog_seen = true
	boss.data["alerted"] = true
	alert_enemies(_nearest_merc_cell(boss.cell), boss.cell, 9.0)
	if fast:
		return true
	await _show_boss_dialog()
	return true

func _show_boss_dialog() -> void:
	Sfx.play("interrupt", -4.0)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(bottom)
	var centerc := CenterContainer.new()
	bottom.add_child(centerc)
	bottom.add_child(UiTheme.vspace(150))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 220)
	centerc.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	panel.add_child(hb)
	var por := TextureRect.new()
	por.texture = Assets.portrait(Db.ENEMY_TYPES["boss"]["portrait"])
	por.custom_minimum_size = Vector2(140, 140)
	por.stretch_mode = TextureRect.STRETCH_SCALE
	por.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	por.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(por)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	hb.add_child(vb)
	var speaker := UiTheme.header("»GENERAL« VARGO", 22)
	vb.add_child(speaker)
	var text := UiTheme.lbl("", 18)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(720, 84)
	vb.add_child(text)
	var btnrow := HBoxContainer.new()
	btnrow.alignment = BoxContainer.ALIGNMENT_END
	btnrow.add_theme_constant_override("separation", 10)
	vb.add_child(btnrow)

	var responder := "Söldner"
	var merc_line := ""
	if Game.has_ivan():
		responder = "Ivan"
		merc_line = Db.IVAN_DIALOG_LINE
	else:
		var tp: Dictionary = Game.top_paid()
		if not tp.is_empty():
			responder = "»%s«" % tp["nick"]

	var vargo_i := 0
	for line in Db.BOSS_DIALOG:
		var is_vargo: bool = line["speaker"] == "vargo"
		speaker.text = "»GENERAL« VARGO" if is_vargo else responder.to_upper()
		speaker.add_theme_color_override("font_color", UiTheme.COL_RED if is_vargo else UiTheme.COL_AMBER)
		var t: String = line["text"]
		if not is_vargo and merc_line != "":
			t = merc_line
		# Vertonung (ElevenLabs)
		if is_vargo:
			vargo_i += 1
			Sfx.play_voice("vargo_%d" % vargo_i)
		elif Game.has_ivan():
			Sfx.play_voice("ivan_dialog")
		else:
			var tp2: Dictionary = Game.top_paid()
			if not tp2.is_empty():
				Sfx.play_voice(String(tp2["id"]) + "_reply")
		await _type_text(text, t)
		for c in btnrow.get_children():
			c.queue_free()
		var next := UiTheme.btn("Weiter  ▸", func() -> void: dialog_next.emit(), 16)
		btnrow.add_child(next)
		await dialog_next

	for c in btnrow.get_children():
		c.queue_free()
	speaker.text = "IHRE ANTWORT"
	speaker.add_theme_color_override("font_color", UiTheme.COL_AMBER)
	text.text = ""
	for i in Db.BOSS_CHOICES.size():
		var ch: Dictionary = Db.BOSS_CHOICES[i]
		var b := UiTheme.btn(ch["label"], func() -> void: dialog_choice.emit(i), 16)
		btnrow.add_child(b)
	var choice: int = await dialog_choice
	var reply := String(Db.BOSS_CHOICES[choice]["reply"])
	if reply != "":
		for c in btnrow.get_children():
			c.queue_free()
		speaker.text = "»GENERAL« VARGO"
		speaker.add_theme_color_override("font_color", UiTheme.COL_RED)
		Sfx.play_voice("vargo_3")
		await _type_text(text, reply)
		var next2 := UiTheme.btn("Kampf!  ▸", func() -> void: dialog_next.emit(), 16)
		btnrow.add_child(next2)
		await dialog_next
	layer.queue_free()
	Sfx.play_voice("vargo_kampf")
	banner_show("VARGO: JETZT GEHT ES UM ALLES!", 1.2)

func _type_text(l: Label, t: String) -> void:
	l.text = t
	if fast:
		return
	l.visible_characters = 0
	var tw := create_tween()
	tw.tween_property(l, "visible_characters", t.length(), t.length() * 0.014)
	await tw.finished
	l.visible_characters = -1

# ============================================================ Feindphase / KI

func end_turn() -> void:
	if busy or not player_turn or battle_over:
		return
	if not combat_started:
		banner_show("Noch kein Feindkontakt — bewegen Sie sich frei.", 1.0)
		return
	player_turn = false
	busy = true
	mode = "move"
	refresh_hud()
	if not fast:
		banner_show("FEINDPHASE", 0.8)
		await dl(0.5)
	for e in enemies:
		if battle_over:
			break
		if e.alive:
			await ai_act(e)
	if not battle_over:
		turn += 1
		for m in mercs:
			m.ap = m.ap_max
			m.interrupt_used = false
			m.queue_redraw()
		for e in enemies:
			e.ap = e.ap_max
			e.interrupt_used = false
		player_turn = true
		compute_vision()
		await check_boss_dialog()
		# 2 Runden ohne Sichtkontakt → zurück in den Erkundungsmodus
		if _any_contact():
			no_contact_rounds = 0
		else:
			no_contact_rounds += 1
		if no_contact_rounds >= 2:
			_end_combat_mode()
		elif not fast:
			banner_show("RUNDE %d — Ihr Zug" % turn, 1.0)
	busy = false
	refresh_hud()

func _enemy_visible_mercs(e: BattleUnit) -> Array:
	var out: Array = []
	for m in mercs:
		if m.alive and unit_sees(e, m.cell):
			out.append(m)
	return out

func ai_act(e: BattleUnit) -> void:
	if not e.alive or battle_over:
		return
	var vism := _enemy_visible_mercs(e)
	if not vism.is_empty():
		e.data["alerted"] = true
		alert_enemies(vism[0].cell, e.cell, 6.0)
	if not bool(e.data.get("alerted", false)):
		if randf() < 0.45:
			for attempt in 8:
				var c := e.cell + Vector2i(randi_range(-3, 3), randi_range(-3, 3))
				if in_bounds(c) and walk[idx(c)] and not occupied.has(c):
					var p := path_for(e, c)
					if p.size() > 1:
						await do_move(e, prefix_for_ap(p, e.ap / 2))
						break
		return
	if e.seen and not fast:
		await dl(0.25)
	var w: Dictionary = Db.weapon(e.data["weapon"])
	if vism.is_empty():
		var tgt := noise_at
		if not in_bounds(tgt):
			return
		# Wachposten halten Stellung, statt der Geräuschquelle hinterherzurennen
		if Vector2(tgt).distance_to(Vector2(e.home)) > _leash_for(e):
			return
		if Vector2(e.cell).distance_to(Vector2(tgt)) <= 2.0:
			tgt = e.cell + Vector2i(randi_range(-4, 4), randi_range(-4, 4))
			if not in_bounds(tgt):
				return
		var p := path_toward(e, tgt)
		if p.size() > 1:
			var reserve: int = int(w["ap"])
			await do_move(e, prefix_for_ap(p, maxi(2, e.ap - reserve)))
		vism = _enemy_visible_mercs(e)
	var moved := false
	var guard := 0
	while not battle_over and e.alive and e.ap >= int(w["ap"]) and guard < 12:
		guard += 1
		vism = _enemy_visible_mercs(e)
		if vism.is_empty():
			break
		var best: BattleUnit = null
		var best_score := -999.0
		for m in vism:
			var sc := float(hit_chance(e, m)) + float(m.hp_max() - m.hp()) * 0.3 - Vector2(e.cell).distance_to(Vector2(m.cell))
			if sc > best_score:
				best_score = sc
				best = m
		if best == null:
			break
		if int(e.data["ammo"]) <= 0:
			if e.ap >= int(w["reload"]):
				do_reload(e)
				continue
			break
		var ch := hit_chance(e, best)
		if ch < 22 and not moved and e.ap >= int(w["ap"]) + 4 and e != boss:
			var bestc := Vector2i(-99, -99)
			var bestv := float(ch)
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					var c := e.cell + Vector2i(dx, dy)
					if not in_bounds(c) or not walk[idx(c)] or occupied.has(c):
						continue
					if not unit_sees_from(c, e, best.cell):
						continue
					var virt := float(e.data["marks"]) - Vector2(c).distance_to(Vector2(best.cell)) / float(w["range"]) * 30.0 + cover_at(c, best.cell) * 40.0
					if virt > bestv:
						bestv = virt
						bestc = c
			if bestc.x > -50:
				var p2 := path_for(e, bestc)
				if p2.size() > 1:
					moved = true
					await do_move(e, prefix_for_ap(p2, e.ap - int(w["ap"])))
					continue
			moved = true
		await shoot(e, best)

func unit_sees_from(from: Vector2i, u: BattleUnit, target: Vector2i) -> bool:
	return Vector2(from).distance_to(Vector2(target)) <= float(u.data["sight"]) and los(from, target)

func _nearest_merc_cell(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 999999.0
	for m in mercs:
		if not m.alive:
			continue
		var d := Vector2(from).distance_to(Vector2(m.cell))
		if d < bd:
			bd = d
			best = m.cell
	return best

# ============================================================ Effekte

func _fx_muzzle(pos: Vector2, dirv: Vector2) -> void:
	if fast:
		return
	var s := Sprite2D.new()
	s.texture = Assets.circle(13, Color(1.0, 0.9, 0.5, 0.95))
	s.position = pos + dirv * 4.0
	s.z_index = 20
	add_child(s)
	var tw := create_tween()
	tw.tween_property(s, "scale", Vector2(0.1, 0.1), 0.13)
	tw.tween_callback(s.queue_free)

func _fx_tracer(a: Vector2, b: Vector2) -> void:
	if fast:
		return
	var l := Line2D.new()
	l.points = PackedVector2Array([a, b])
	l.width = 2.5
	l.default_color = Color(1.0, 0.95, 0.6, 0.9)
	l.z_index = 20
	add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "modulate:a", 0.0, 0.16)
	tw.tween_callback(l.queue_free)

func _fx_blood(pos: Vector2) -> void:
	_fx_decal(pos + Vector2(randf_range(-8, 8), randf_range(-8, 8)), "splat_dark", Color(0.62, 0.08, 0.08, 0.65), randf_range(0.5, 0.8))

func _fx_decal(pos: Vector2, texname: String, mod: Color, scl: float) -> void:
	var s := Sprite2D.new()
	s.texture = Assets.tex(texname)
	s.position = pos
	s.rotation = randf_range(0, TAU)
	s.modulate = mod
	s.scale = Vector2.ONE * scl
	s.z_index = 1
	add_child(s)

func _fx_explosion(pos: Vector2) -> void:
	if fast:
		return
	var s := Sprite2D.new()
	s.texture = Assets.circle(42, Color(1.0, 0.7, 0.25, 0.95))
	s.position = pos
	s.scale = Vector2(0.4, 0.4)
	s.z_index = 21
	add_child(s)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(s, "scale", Vector2(2.6, 2.6), 0.32)
	tw.tween_property(s, "modulate:a", 0.0, 0.34)
	tw.chain().tween_callback(s.queue_free)

func _fx_float(pos: Vector2, txt: String, col: Color) -> void:
	if fast:
		return
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 5)
	l.position = pos + Vector2(-28, -54)
	l.z_index = 60
	add_child(l)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 30.0, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.chain().tween_callback(l.queue_free)

func _shake(strength := 9.0) -> void:
	if fast:
		return
	var tw := create_tween()
	for i in 6:
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * strength * (1.0 - i / 6.0)
		tw.tween_property(cam, "offset", off, 0.04)
	tw.tween_property(cam, "offset", Vector2.ZERO, 0.05)

# ============================================================ HUD (JA1-Layout)

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	hud_root = Control.new()
	hud_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.theme = UiTheme.theme()
	hud.add_child(hud_root)

	# Obere Leiste
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 20)
	top.add_child(th)
	top_label = UiTheme.lbl("", 16, UiTheme.COL_AMBER)
	th.add_child(top_label)
	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp1)
	enemy_label = UiTheme.lbl("", 15)
	th.add_child(enemy_label)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp2)
	th.add_child(UiTheme.lbl("[Tab] Söldner  [Z] Zielen  [G] Granate  [R] Nachladen  [H] Medikit  [I] Inventar  [Enter] Runde", 12, UiTheme.COL_DIM))

	# Portrait-Seitenleisten (JA1): 1–2 links, 3–4 rechts
	slot_boxes = []
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = 8.0
	left.offset_top = -170.0
	left.add_theme_constant_override("separation", 10)
	hud_root.add_child(left)
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	right.offset_right = -8.0
	right.offset_left = -144.0
	right.offset_top = -170.0
	right.add_theme_constant_override("separation", 10)
	hud_root.add_child(right)
	for i in mercs.size():
		var side := left if i < 2 else right
		side.add_child(_build_slot(i))

	# Untere Aktionsleiste (mittig)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -390.0
	bottom.offset_right = 390.0
	bottom.offset_top = -128.0
	bottom.offset_bottom = -6.0
	bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(bottom)
	var act := VBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	bottom.add_child(act)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 14)
	act.add_child(wrow)
	weapon_label = UiTheme.lbl("", 16, UiTheme.COL_AMBER)
	wrow.add_child(weapon_label)
	ammo_label = UiTheme.lbl("", 16)
	wrow.add_child(ammo_label)
	mags_label = UiTheme.lbl("", 14, UiTheme.COL_DIM)
	wrow.add_child(mags_label)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	act.add_child(brow)
	reload_btn = UiTheme.btn("Nachladen (R)", _on_reload, 13)
	brow.add_child(reload_btn)
	aim_btn = UiTheme.btn("Zielen (Z)", _on_aim, 13)
	brow.add_child(aim_btn)
	grenade_btn = UiTheme.btn("Granate (G)", _on_grenade_mode, 13)
	grenade_btn.icon = Assets.item_icon("granate")
	brow.add_child(grenade_btn)
	medkit_btn = UiTheme.btn("Medikit (H)", _on_medkit, 13)
	medkit_btn.icon = Assets.item_icon("medkit")
	brow.add_child(medkit_btn)
	inv_btn = UiTheme.btn("Inventar (I)", toggle_inventory, 13)
	brow.add_child(inv_btn)
	var brow2 := HBoxContainer.new()
	brow2.add_theme_constant_override("separation", 8)
	act.add_child(brow2)
	endturn_btn = UiTheme.btn("RUNDE BEENDEN (Enter)", _on_endturn, 14)
	endturn_btn.custom_minimum_size = Vector2(230, 0)
	brow2.add_child(endturn_btn)
	brow2.add_child(UiTheme.btn("Menü (Esc)", _toggle_pause, 13))

	# Cursor-Info
	cursor_panel = PanelContainer.new()
	cursor_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_panel.visible = false
	cursor_panel.z_index = 90
	hud_root.add_child(cursor_panel)
	cursor_label = UiTheme.lbl("", 14)
	cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor_panel.add_child(cursor_label)

	# Banner
	banner_label = UiTheme.header("", 38)
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_label.offset_top = 140.0
	banner_label.offset_bottom = 200.0
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.modulate.a = 0.0
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(banner_label)

func _build_slot(i: int) -> Button:
	var m: BattleUnit = mercs[i]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(136, 162)
	btn.pressed.connect(_on_slot.bind(i))
	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 3)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(inner)
	var por := TextureRect.new()
	por.texture = Assets.portrait(m.data["portrait"])
	por.custom_minimum_size = Vector2(84, 84)
	por.stretch_mode = TextureRect.STRETCH_SCALE
	por.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	por.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	por.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(por)
	var nm := UiTheme.lbl("»%s«" % m.data["nick"], 14)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(nm)
	var hpb := ProgressBar.new()
	hpb.custom_minimum_size = Vector2(110, 10)
	hpb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hpb.max_value = m.hp_max()
	hpb.value = m.hp()
	hpb.show_percentage = false
	hpb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hpb.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.COL_RED, Color(0, 0, 0, 0), 2, 0, 1))
	inner.add_child(hpb)
	var apb := ProgressBar.new()
	apb.custom_minimum_size = Vector2(110, 8)
	apb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apb.max_value = m.ap_max
	apb.value = m.ap
	apb.show_percentage = false
	apb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(apb)
	var stat := UiTheme.lbl("", 11, UiTheme.COL_DIM)
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(stat)
	slot_boxes.append({"btn": btn, "hp": hpb, "ap": apb, "stat": stat})
	return btn

func banner_show(txt: String, dur := 1.2) -> void:
	if fast:
		return
	banner_label.text = txt
	banner_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(banner_label, "modulate:a", 1.0, 0.18)
	tw.tween_interval(dur)
	tw.tween_property(banner_label, "modulate:a", 0.0, 0.35)

func refresh_hud() -> void:
	if slot_boxes.is_empty():
		return
	if combat_started:
		top_label.text = "SEKTOR 43 · SILBERQUELL — Runde %d — %s" % [turn, "Ihr Zug" if player_turn else "Feindphase"]
	else:
		top_label.text = "SEKTOR 43 · SILBERQUELL — ANMARSCH — frei bewegen · Shift+Klick = ganzer Trupp"
	for i in mercs.size():
		var m: BattleUnit = mercs[i]
		var sb: Dictionary = slot_boxes[i]
		sb["hp"].value = m.hp()
		sb["ap"].value = m.ap
		sb["stat"].text = "HP %d/%d · AP %d · St.%d" % [m.hp(), m.hp_max(), m.ap, level_of(m)]
		if not m.alive:
			sb["btn"].disabled = true
			sb["btn"].modulate = Color(0.55, 0.4, 0.4, 0.7)
			sb["stat"].text = "GEFALLEN"
		if m == selected:
			sb["btn"].add_theme_stylebox_override("normal", UiTheme.box(Color("5e4828"), UiTheme.COL_AMBER, 4, 3, 6))
		else:
			sb["btn"].remove_theme_stylebox_override("normal")
	if selected != null and selected.alive:
		var w: Dictionary = Db.weapon(selected.data["weapon"])
		weapon_label.text = String(w["name"])
		ammo_label.text = "Munition %d/%d" % [int(selected.data["ammo"]), int(w["mag"])]
		mags_label.text = "Magazine ×%d · Granaten ×%d · Medikits ×%d" % [mags_for(selected), inv_count(selected, "granate"), inv_count(selected, "medkit")]
		reload_btn.disabled = not player_turn or busy or selected.ap < int(w["reload"]) or int(selected.data["ammo"]) >= int(w["mag"]) or mags_for(selected) <= 0
		reload_btn.icon = Assets.item_icon(_mag_item_for(String(w["cal"])))
		aim_btn.disabled = not player_turn or busy
		aim_btn.text = "Zielen ×%d (Z)" % aim_level if aim_level > 0 else "Zielen (Z)"
		aim_btn.modulate = Color(1.0, 0.8, 0.45) if aim_level > 0 else Color(1, 1, 1)
		grenade_btn.text = "Granate ×%d (G)" % inv_count(selected, "granate")
		grenade_btn.disabled = not player_turn or busy or inv_count(selected, "granate") <= 0 or selected.ap < int(Db.GRENADE["ap"])
		grenade_btn.modulate = Color(1.0, 0.75, 0.4) if mode == "grenade" else Color(1, 1, 1)
		medkit_btn.text = "Medikit ×%d (H)" % inv_count(selected, "medkit")
		medkit_btn.disabled = not player_turn or busy or inv_count(selected, "medkit") <= 0 or selected.ap < Db.MEDKIT_AP
		inv_btn.disabled = not player_turn or busy
	endturn_btn.disabled = not player_turn or busy or not combat_started
	if inv_panel != null:
		_inv_refresh()

func _update_enemy_label() -> void:
	if enemy_label == null:
		return
	var seen := 0
	var total := 0
	for e in enemies:
		if e.alive:
			total += 1
			if e.seen:
				seen += 1
	enemy_label.text = "Feinde: %d gesichtet · %d verbleibend" % [seen, total]

# ============================================================ Inventar-Panel

func toggle_inventory() -> void:
	if inv_panel != null:
		inv_panel.queue_free()
		inv_panel = null
		inv_sel = -1
		return
	if selected == null or not selected.alive:
		return
	inv_sel = -1
	inv_panel = PanelContainer.new()
	inv_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	inv_panel.offset_right = -156.0
	inv_panel.offset_left = -536.0
	inv_panel.offset_top = -240.0
	inv_panel.offset_bottom = 240.0
	inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(inv_panel)
	_inv_refresh()

func _inv_refresh() -> void:
	if inv_panel == null or selected == null:
		return
	for c in inv_panel.get_children():
		c.queue_free()
	var u := selected
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	inv_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiTheme.header("INVENTAR — »%s«" % u.data["nick"], 20))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiTheme.btn("✕", toggle_inventory, 14))
	v.add_child(UiTheme.lbl("HP %d/%d · TRF %d · BEW %d · MED %d" % [u.hp(), u.hp_max(), int(u.data["marks"]), int(u.data["agi"]), int(u.data["med"])], 13, UiTheme.COL_DIM))
	v.add_child(UiTheme.lbl("Erfahrungsstufe %d · Abschüsse %d" % [level_of(u), int(u.data.get("kills", 0))], 13, UiTheme.COL_DIM))
	var w: Dictionary = Db.weapon(u.data["weapon"])
	var handrow := HBoxContainer.new()
	handrow.add_theme_constant_override("separation", 8)
	v.add_child(handrow)
	var handicon := TextureRect.new()
	handicon.texture = Assets.item_icon(String(u.data["weapon"]))
	handicon.custom_minimum_size = Vector2(32, 32)
	handicon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	handicon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	handrow.add_child(handicon)
	handrow.add_child(UiTheme.lbl("HAND: %s (%d/%d)" % [w["name"], int(u.data["ammo"]), int(w["mag"])], 15, UiTheme.COL_AMBER))
	v.add_child(UiTheme.lbl("Taschen (%d/%d):" % [inv_of(u).size(), Db.INV_SLOTS], 13, UiTheme.COL_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var inv := inv_of(u)
	for i in Db.INV_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(174, 42)
		b.add_theme_font_size_override("font_size", 12)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i < inv.size():
			b.text = String(Db.item(String(inv[i]))["short"])
			b.icon = Assets.item_icon(String(inv[i]))
			if i == inv_sel:
				b.add_theme_stylebox_override("normal", UiTheme.box(Color("5e4828"), UiTheme.COL_AMBER, 4, 2, 8))
			b.pressed.connect(_on_inv_slot.bind(i))
		else:
			b.text = "— leer —"
			b.disabled = true
		grid.add_child(b)
	# Aktionen fürs gewählte Item
	if inv_sel >= 0 and inv_sel < inv.size():
		var id := String(inv[inv_sel])
		var item: Dictionary = Db.item(id)
		v.add_child(UiTheme.vspace(4))
		v.add_child(UiTheme.lbl("Gewählt: " + String(item["name"]), 14))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		var kind := String(item["kind"])
		if kind == "weapon":
			row.add_child(UiTheme.btn("Ausrüsten (%d AP)" % Db.SWAP_AP, _on_inv_equip.bind(inv_sel), 13))
		elif kind == "ammo":
			if String(item.get("cal", "")) == String(w["cal"]):
				row.add_child(UiTheme.btn("Nachladen (%d AP)" % int(w["reload"]), _on_reload, 13))
			else:
				row.add_child(UiTheme.lbl("Passt nicht zur Handwaffe", 13, UiTheme.COL_DIM))
		elif kind == "grenade":
			row.add_child(UiTheme.btn("Bereitmachen (G)", _on_grenade_mode, 13))
		elif kind == "medkit":
			row.add_child(UiTheme.btn("Benutzen (%d AP)" % Db.MEDKIT_AP, _on_medkit, 13))
		row.add_child(UiTheme.btn("Wegwerfen", _on_inv_drop.bind(inv_sel), 13))

func _on_inv_slot(i: int) -> void:
	inv_sel = i
	_inv_refresh()

func _on_inv_equip(i: int) -> void:
	if selected and player_turn and not busy:
		do_swap(selected, i)
		inv_sel = -1
		_inv_refresh()

func _on_inv_drop(i: int) -> void:
	if selected == null:
		return
	var inv := inv_of(selected)
	if i >= 0 and i < inv.size():
		Sfx.play("ui_back")
		inv.remove_at(i)
	inv_sel = -1
	refresh_hud()

# ============================================================ Auswahl & Eingabe

func select_merc(u: BattleUnit) -> void:
	if u == null or not u.alive or not u.is_merc:
		return
	if selected != u and not fast:
		Sfx.play_voice(String(u.data["id"]) + "_select")
	if selected != null:
		selected.selected = false
		selected.queue_redraw()
	selected = u
	u.selected = true
	u.queue_redraw()
	mode = "move"
	if inv_panel != null:
		_inv_refresh()
	refresh_hud()
	overlay.queue_redraw()

func _player_shoot(att: BattleUnit, def: BattleUnit) -> void:
	if busy or battle_over:
		return
	busy = true
	await shoot(att, def)
	busy = false
	refresh_hud()
	overlay.queue_redraw()

func _on_slot(i: int) -> void:
	if i < mercs.size():
		if selected == mercs[i]:
			toggle_inventory()
		else:
			select_merc(mercs[i])
			cam.position = mercs[i].position

func _on_reload() -> void:
	if selected and player_turn and not busy:
		do_reload(selected)

func _on_medkit() -> void:
	if selected and player_turn and not busy:
		do_medkit(selected)

func _on_aim() -> void:
	aim_level = (aim_level + 1) % (int(Db.AIM["max"]) + 1)
	Sfx.play("ui_select", -6.0)
	refresh_hud()

func _on_grenade_mode() -> void:
	if selected == null or not player_turn or busy:
		return
	if inv_count(selected, "granate") <= 0 or selected.ap < int(Db.GRENADE["ap"]):
		Sfx.play("ui_error")
		return
	mode = "grenade" if mode != "grenade" else "move"
	refresh_hud()
	overlay.queue_redraw()

func _on_endturn() -> void:
	end_turn()

func _toggle_pause() -> void:
	if pause_panel != null:
		pause_panel.queue_free()
		pause_panel = null
		return
	pause_panel = Control.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var hd := UiTheme.header("PAUSE", 30)
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hd)
	v.add_child(UiTheme.btn("Fortsetzen", _toggle_pause, 17))
	v.add_child(UiTheme.btn("Mission aufgeben", func() -> void:
		_toggle_pause()
		end_battle("abort"), 17))
	v.add_child(UiTheme.btn("Spiel beenden", func() -> void: get_tree().quit(), 17))

func _min_zoom() -> float:
	var vs := get_viewport_rect().size
	return maxf(vs.x / float(W * TILE), vs.y / float(H * TILE))

func _clamp_zoom() -> void:
	var z := clampf(cam.zoom.x, _min_zoom(), 1.6)
	cam.zoom = Vector2(z, z)

func _unhandled_input(event: InputEvent) -> void:
	if battle_over:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			cam.zoom = cam.zoom * 1.1
			_clamp_zoom()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			cam.zoom = cam.zoom / 1.1
			_clamp_zoom()
			return
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			cam.position -= event.relative / cam.zoom.x
			return
		_update_hover()
		return
	if busy or not player_turn:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_click(event.shift_pressed)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if mode == "grenade":
				mode = "move"
				refresh_hud()
				overlay.queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				_cycle_merc()
			KEY_R:
				_on_reload()
			KEY_Z:
				_on_aim()
			KEY_G:
				_on_grenade_mode()
			KEY_H:
				_on_medkit()
			KEY_I:
				toggle_inventory()
			KEY_ENTER, KEY_KP_ENTER:
				end_turn()
			KEY_ESCAPE:
				if inv_panel != null:
					toggle_inventory()
				else:
					_toggle_pause()
			KEY_1, KEY_2, KEY_3, KEY_4:
				_on_slot(event.keycode - KEY_1)

func _cycle_merc() -> void:
	if mercs.is_empty():
		return
	var start := mercs.find(selected)
	for off in range(1, mercs.size() + 1):
		var m: BattleUnit = mercs[(start + off) % mercs.size()]
		if m.alive:
			select_merc(m)
			cam.position = m.position
			return

func _click(shift := false) -> void:
	if selected == null or not selected.alive:
		return
	if mode == "grenade":
		do_grenade(selected, hover_cell)
		return
	# Erkundung: Shift+Klick bewegt den ganzen Trupp
	if shift and not combat_started and in_bounds(hover_cell) and walk[idx(hover_cell)]:
		_squad_move(hover_cell)
		return
	if occupied.has(hover_cell):
		var u: BattleUnit = occupied[hover_cell]
		if u.is_merc and u.alive:
			if u == selected:
				toggle_inventory()
			else:
				select_merc(u)
			return
		if not u.is_merc and u.alive and u.seen:
			if los(selected.cell, u.cell):
				_player_shoot(selected, u)
			else:
				Sfx.play("ui_error")
				_fx_float(u.position, "Keine Schusslinie", Color(0.8, 0.6, 0.5))
			return
	# Durchsuchen (Kiste / Leiche)
	if hover_search != "" and Vector2(selected.cell).distance_to(Vector2(hover_cell)) <= 1.6:
		do_search(selected, hover_cell)
		return
	if hover_path.size() > 1:
		var pre := prefix_for_ap(hover_path, selected.ap)
		if pre.size() > 1:
			do_move(selected, pre)

## Truppbewegung (nur Erkundung): alle Söldner sammeln sich beim Ziel
func _squad_move(target: Vector2i) -> void:
	for m in mercs:
		if combat_started or battle_over:
			break
		if not m.alive:
			continue
		var p := path_toward(m, target)
		if p.size() > 1:
			await do_move(m, prefix_for_ap(p, m.ap))

func _update_hover() -> void:
	var wp := get_global_mouse_position()
	var c := Vector2i(int(floor(wp.x / TILE)), int(floor(wp.y / TILE)))
	if c == hover_cell:
		return
	hover_cell = c
	if hover_unit != null and is_instance_valid(hover_unit):
		hover_unit.hovered = false
		hover_unit.queue_redraw()
	hover_unit = null
	hover_path = []
	hover_cost = 0
	hover_search = ""
	if not in_bounds(c):
		overlay.queue_redraw()
		return
	if occupied.has(c):
		var u: BattleUnit = occupied[c]
		if u.alive and (u.is_merc or u.seen):
			hover_unit = u
			u.hovered = true
			u.queue_redraw()
	else:
		hover_search = search_target_at(c)
		if selected != null and selected.alive and mode == "move" and player_turn and not busy:
			if walk[idx(c)]:
				hover_path = path_for(selected, c)
				hover_cost = path_cost(hover_path)
	overlay.queue_redraw()

func _process(_delta: float) -> void:
	if cam == null:
		return
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if v != Vector2.ZERO:
		cam.position += v.normalized() * 640.0 * _delta / cam.zoom.x
	_clamp_zoom()
	var vs := get_viewport_rect().size / cam.zoom.x
	cam.position.x = clampf(cam.position.x, vs.x / 2.0, W * TILE - vs.x / 2.0)
	cam.position.y = clampf(cam.position.y, vs.y / 2.0, H * TILE - vs.y / 2.0)
	_update_cursor_info()

func _update_cursor_info() -> void:
	if cursor_panel == null:
		return
	var txt := ""
	if player_turn and not busy and selected != null and selected.alive:
		if mode == "grenade":
			if grenade_valid(selected, hover_cell):
				txt = "Granate werfen: %d AP · Radius %.1f" % [int(Db.GRENADE["ap"]), float(Db.GRENADE["radius"])]
			else:
				txt = "Außer Reichweite / keine Wurfbahn"
		elif hover_unit != null and not hover_unit.is_merc:
			if los(selected.cell, hover_unit.cell):
				var aimtxt := " (gezielt ×%d)" % aim_level if aim_level > 0 else ""
				txt = "%s — Treffer: %d %% · %d AP%s" % [hover_unit.display_name(), hit_chance(selected, hover_unit, aim_level), shot_ap(selected, aim_level), aimtxt]
			else:
				txt = "Keine Schusslinie"
		elif hover_search == "crate":
			txt = "Kiste durchsuchen (frei)" if not combat_started else "Kiste durchsuchen: %d AP" % Db.SEARCH_AP
		elif hover_search == "corpse":
			txt = "Gefallenen durchsuchen (frei)" if not combat_started else "Gefallenen durchsuchen: %d AP" % Db.SEARCH_AP
		elif hover_path.size() > 1:
			var afford := path_cost(prefix_for_ap(hover_path, selected.ap))
			if not combat_started:
				txt = "Anmarsch: Bewegung frei"
			elif hover_cost <= selected.ap:
				txt = "Laufen: %d AP" % hover_cost
			else:
				txt = "Laufen: %d AP (nur %d möglich)" % [hover_cost, afford]
	if txt == "":
		cursor_panel.visible = false
		return
	cursor_panel.visible = true
	cursor_label.text = txt
	cursor_panel.position = hud_root.get_local_mouse_position() + Vector2(20, 16)

func _draw_overlay() -> void:
	if battle_over:
		return
	if in_bounds(hover_cell):
		var r := Rect2(Vector2(hover_cell) * TILE, Vector2(TILE, TILE))
		overlay.draw_rect(r, Color(1, 1, 1, 0.14), true)
		var edge := Color(0.95, 0.85, 0.5, 0.7)
		if hover_search != "":
			edge = Color(0.5, 0.9, 0.5, 0.85)
		overlay.draw_rect(r, edge, false, 2.0)
	if mode == "move" and hover_path.size() > 1 and selected != null:
		var afford := prefix_for_ap(hover_path, selected.ap).size()
		for i in range(1, hover_path.size()):
			var col := Color(0.95, 0.8, 0.4, 0.85) if (i < afford or not combat_started) else Color(0.6, 0.6, 0.6, 0.5)
			overlay.draw_circle(cell_center(hover_path[i]), 5.0, col)
	if mode == "grenade" and selected != null:
		overlay.draw_arc(selected.position, float(throw_range(selected)) * TILE, 0, TAU, 64, Color(1.0, 0.7, 0.3, 0.35), 2.0)
		if in_bounds(hover_cell):
			var okc := grenade_valid(selected, hover_cell)
			var col2 := Color(1.0, 0.5, 0.15, 0.3) if okc else Color(1.0, 0.15, 0.1, 0.25)
			overlay.draw_circle(cell_center(hover_cell), float(Db.GRENADE["radius"]) * TILE, col2)
			overlay.draw_line(selected.position, cell_center(hover_cell), Color(1, 0.8, 0.4, 0.5), 1.5)

# ============================================================ Smoke-Test-Bot

func auto_battle() -> String:
	var outer := 0
	while not battle_over and outer < 300:
		outer += 1
		if outer % 10 == 0:
			var left := 0
			for e in enemies:
				if e.alive:
					left += 1
			print("SMOKE: Runde %d — Gegner übrig: %d" % [turn, left])
		for m in mercs:
			if battle_over:
				break
			if not m.alive:
				continue
			var inner := 0
			var acted := true
			while acted and inner < 24 and m.alive and not battle_over:
				inner += 1
				acted = false
				var w: Dictionary = Db.weapon(m.data["weapon"])
				if inv_count(m, "granate") > 0 and m.ap >= int(Db.GRENADE["ap"]):
					var gt := _bot_grenade_target(m)
					if gt.x > -50:
						await do_grenade(m, gt)
						acted = true
						continue
				var best: BattleUnit = null
				var bch := 0
				for e in visible_enemies():
					if los(m.cell, e.cell):
						var ch := hit_chance(m, e)
						if ch > bch:
							bch = ch
							best = e
				if best != null and m.ap >= int(w["ap"]):
					if int(m.data["ammo"]) <= 0:
						if m.ap >= int(w["reload"]) and _can_reload(m):
							do_reload(m)
							acted = true
							continue
					elif bch >= 18:
						await shoot(m, best)
						acted = true
						continue
				if inv_count(m, "medkit") > 0 and m.ap >= Db.MEDKIT_AP and m.hp() * 2 < m.hp_max():
					do_medkit(m)
					acted = true
					continue
				var tgt := _nearest_alive_enemy_cell(m.cell)
				if tgt.x >= 0 and m.ap >= 4:
					var p := path_toward(m, tgt)
					if p.size() > 1:
						var pre := _bot_trim_to_cover(prefix_for_ap(p, maxi(2, m.ap - int(w["ap"]))))
						if pre.size() > 1:
							await do_move(m, pre)
							acted = true
							continue
		if battle_over:
			break
		await end_turn()
	if not battle_over:
		await end_battle("abort")
	return Game.mission_result

func _bot_grenade_target(m: BattleUnit) -> Vector2i:
	for e in visible_enemies():
		if not grenade_valid(m, e.cell):
			continue
		var friendly := false
		for mm in mercs:
			if mm.alive and Vector2(mm.cell).distance_to(Vector2(e.cell)) <= float(Db.GRENADE["radius"]) + 0.2:
				friendly = true
				break
		if friendly:
			continue
		if e == boss:
			return e.cell
		var cluster := 0
		for e2 in enemies:
			if e2.alive and Vector2(e2.cell).distance_to(Vector2(e.cell)) <= float(Db.GRENADE["radius"]):
				cluster += 1
		if cluster >= 2:
			return e.cell
	return Vector2i(-99, -99)

func _bot_trim_to_cover(p: Array) -> Array:
	if p.size() <= 2:
		return p
	var lim := maxi(2, p.size() - 5)
	for i in range(p.size() - 1, lim - 1, -1):
		var c: Vector2i = p[i]
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var n := c + Vector2i(dx, dy)
				if in_bounds(n) and float(cover[idx(n)]) > 0.0:
					return p.slice(0, i + 1)
	return p

func _nearest_alive_enemy_cell(from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := 999999.0
	for e in enemies:
		if not e.alive:
			continue
		var d := Vector2(from).distance_to(Vector2(e.cell))
		if d < bd:
			bd = d
			best = e.cell
	return best

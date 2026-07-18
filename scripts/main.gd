extends Control
## Main — Screen-Router (Root-Control, füllt automatisch das Fenster).
## Außerdem: Headless-Smoke-Test (--smoke), Kontakt-Sonde (--contact)
## und Screenshot-Modus (--shots=<ordner>).

var current: Node = null
var fast := false

const SCREENS := {
	"title": "res://scripts/screens/title.gd",
	"difficulty": "res://scripts/screens/difficulty.gd",
	"hire": "res://scripts/screens/hire.gd",
	"island": "res://scripts/screens/island.gd",
	"loading": "res://scripts/screens/loading.gd",
	"tactical": "res://scripts/screens/tactical.gd",
	"tactical3d": "res://scripts/tac3d/tactical3d.gd",
	"tactical3d_combat": "res://scripts/tac3d/combat/tactical3d_combat.gd",
	"end": "res://scripts/screens/end_screen.gd",
}

func _ready() -> void:
	get_window().min_size = Vector2i(1152, 648)
	RenderingServer.set_default_clear_color(Color("18120a"))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := OS.get_cmdline_user_args()
	if "--smoke" in args:
		fast = true
		_smoke()
		return
	for a in args:
		if a.begins_with("--shots="):
			_shots(a.substr(8))
			return
		if a.begins_with("--tac3d-shots="):
			_tac3d_shots(a.substr(14))
			return
		if a.begins_with("--hud3d-shots="):
			await _hud3d_shots(a.substr(14))
			return
		if a.begins_with("--juice-shots="):
			await _juice_shots(a.substr(14))
			return
	if "--contact" in args:
		fast = true
		_contact_probe()
		return
	if "--tac3d" in args:
		fast = true
		await _tac3d_probe()
		return
	if "--smoke3d" in args:
		fast = true
		await _smoke3d()
		return
	if "--hud3d" in args:   # OHNE fast=true -> HUD/Cursor werden gebaut (Interaktionstest)
		await _hud3d()
		return
	goto("title")

func goto(screen: String) -> void:
	if current != null:
		current.queue_free()
		current = null
	var s: Script = load(SCREENS[screen])
	var node: Node = s.new()
	node.name = "Screen_" + screen
	current = node
	add_child(node)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_M:
		Sfx.toggle_mute()

## Diagnose: Wer sieht wen beim Missionsstart? (für alle Schwierigkeitsgrade)
func _contact_probe() -> void:
	for diff in ["leicht", "normal", "schwer"]:
		Game.new_game()
		Game.set_difficulty(diff)
		for id in ["ivan", "fuchs", "doc", "nadel"]:
			Game.hire(id)
		goto("tactical")
		var tac = current
		await tac.battle_ready
		var any := false
		for e in tac.enemies:
			for m in tac.mercs:
				if tac.unit_sees(e, m.cell):
					any = true
					print("CONTACT [%s]: %s @%s sieht %s @%s" % [diff, e.data["name"], str(e.cell), m.display_name(), str(m.cell)])
				if tac.unit_sees(m, e.cell):
					any = true
					print("CONTACT [%s]: %s @%s sieht %s @%s" % [diff, m.display_name(), str(m.cell), e.data["name"], str(e.cell)])
		if not any:
			print("CONTACT [%s]: sauber — niemand sieht niemanden (%d Gegner)" % [diff, tac.enemies.size()])
	get_tree().quit()

# ============================================================ 3D-Taktik-Sonde (Phase 1)

func _tac3d_fail(fails: int, msg: String) -> int:
	push_error("TAC3D-FEHLER: " + msg)
	print("TAC3D-FEHLER: ", msg)
	return fails + 1

## Verifikations-Harness für die 3D-Taktik (Vertrag §12): Block A (reine Logik,
## frischer Pathfinder3D pro mutierender Gruppe) + Block B (Szene öffnet, Unit fährt).
func _tac3d_probe() -> void:
	print("TAC3D: Start")
	var fails := 0

	# --- Testkarte einmal bauen (Grid ist unveränderlich; nur der Pathfinder mutiert).
	var meta: Dictionary = TestMap3D.build()
	var g: Grid3D = meta["grid"]
	var start: Vector3i = meta["start"]
	var goal: Vector3i = meta["goal"]
	var west_probe: Vector3i = meta["west_probe"]
	var east_probe: Vector3i = meta["east_probe"]
	var swim_from: Vector3i = meta["swim_from"]
	var swim_to: Vector3i = meta["swim_to"]
	var deep_under_deck: Vector3i = meta["deep_under_deck"]
	var deck_over_deep: Vector3i = meta["deck_over_deep"]
	var bridge_cells: Array = meta["bridge_cells"]
	var podium_cells: Array = meta["podium_cells"]

	# ---------- Block A: reine Logik ----------

	# A1: Kacheln auf Ebene 0 UND Ebene 1; alle Brücken-/Podest-Zellen begehbar.
	var has_l0 := false
	var has_l1 := false
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y == 0:
			has_l0 = true
		elif c.y == 1:
			has_l1 = true
	if not (has_l0 and has_l1):
		fails = _tac3d_fail(fails, "A1: fehlende Ebene (L0=%s, L1=%s)" % [str(has_l0), str(has_l1)])
	for bc in bridge_cells:
		var b: Vector3i = bc
		if not g.has_tile(b) or not g.is_walkable(b):
			fails = _tac3d_fail(fails, "A1: Brückenzelle fehlt/blockiert: %s" % str(b))
	for pc in podium_cells:
		var p: Vector3i = pc
		if not g.has_tile(p) or not g.is_walkable(p):
			fails = _tac3d_fail(fails, "A1: Podestzelle fehlt/blockiert: %s" % str(p))

	# A2: gesperrte Brücke → West/Ost NICHT erreichbar (SWIM aus).
	var pf_a2 := Pathfinder3D.new()
	pf_a2.build(g)
	pf_a2.set_move_type_enabled(Tac3DTile.Move.SWIM, false)
	for bc in bridge_cells:
		var b2: Vector3i = bc
		pf_a2.set_cell_blocked(b2, true)
	if pf_a2.reachable(west_probe, east_probe):
		fails = _tac3d_fail(fails, "A2: West/Ost trotz gesperrter Brücke erreichbar")

	# A3: jede Brückenzelle ist BRIDGE und auf Ebene 1.
	for bc in bridge_cells:
		var b3: Vector3i = bc
		var t3: Tac3DTile = g.get_tile(b3)
		if t3 == null or t3.kind != Tac3DTile.Kind.BRIDGE or b3.y != 1:
			fails = _tac3d_fail(fails, "A3: Brückenzelle falsch: %s" % str(b3))

	# A4: tiefes Wasser vs. Deck darüber — verschiedene IDs, verschiedene Renderhöhe, NICHT verbunden.
	var pf_a4 := Pathfinder3D.new()
	pf_a4.build(g)
	var id_deep := pf_a4.point_id(deep_under_deck)
	var id_deck := pf_a4.point_id(deck_over_deep)
	if id_deep < 0 or id_deck < 0:
		fails = _tac3d_fail(fails, "A4: fehlende Punkte (deep=%d, deck=%d)" % [id_deep, id_deck])
	elif id_deep == id_deck:
		fails = _tac3d_fail(fails, "A4: deep/deck teilen dieselbe ID (%d)" % id_deep)
	else:
		if g.cell_to_world(deep_under_deck).y == g.cell_to_world(deck_over_deep).y:
			fails = _tac3d_fail(fails, "A4: deep/deck haben gleiche Renderhöhe")
		if pf_a4.astar.are_points_connected(id_deep, id_deck):
			fails = _tac3d_fail(fails, "A4: deep/deck fälschlich verbunden")

	# A5: Pfad start→goal (SWIM aus) existiert, endet korrekt, nutzt die BRÜCKE.
	var pf_a5 := Pathfinder3D.new()
	pf_a5.build(g)
	pf_a5.set_move_type_enabled(Tac3DTile.Move.SWIM, false)
	var p5: Array = pf_a5.path_cells(start, goal)
	if p5.is_empty():
		fails = _tac3d_fail(fails, "A5: kein Pfad start→goal (SWIM aus)")
	else:
		if p5.front() != start:
			fails = _tac3d_fail(fails, "A5: Pfad beginnt nicht am Start (%s)" % str(p5.front()))
		if p5.back() != goal:
			fails = _tac3d_fail(fails, "A5: Pfad endet nicht am Ziel (%s)" % str(p5.back()))
		if not _tac3d_has_kind(g, p5, Tac3DTile.Kind.BRIDGE):
			fails = _tac3d_fail(fails, "A5: Pfad nutzt die Brücke nicht")

	# A6: Pfad swim_from→swim_to führt durchs tiefe Wasser.
	# Bei offener Brücke ist das Deck (Kosten ~7) billiger als die Wasserquerung
	# (WADE 4 + SWIM 10 + GROUND 1 = 15), daher wiche der Pfad sonst übers Deck aus
	# und "schwämme" nie. Wie in A2 sperren wir das Brückendeck (SWIM bleibt AN),
	# sodass die einzige verbleibende Querung durch das tiefe Wasser unter der
	# Brücke hindurch führt — genau der zu beweisende Schwimm-unter-der-Brücke-Fall.
	var pf_a6 := Pathfinder3D.new()
	pf_a6.build(g)
	for bc in bridge_cells:
		var b6: Vector3i = bc
		pf_a6.set_cell_blocked(b6, true)
	var p6: Array = pf_a6.path_cells(swim_from, swim_to)
	if p6.is_empty():
		fails = _tac3d_fail(fails, "A6: kein Pfad swim_from→swim_to")
	elif not _tac3d_has_kind(g, p6, Tac3DTile.Kind.WATER_DEEP):
		fails = _tac3d_fail(fails, "A6: Schwimm-Pfad meidet tiefes Wasser")

	# A7: Westufer intern erreichbar.
	var pf_a7 := Pathfinder3D.new()
	pf_a7.build(g)
	if not pf_a7.reachable(Vector3i(1, 0, 5), Vector3i(5, 0, 5)):
		fails = _tac3d_fail(fails, "A7: Westufer (1,0,5)→(5,0,5) nicht erreichbar")

	# A8: start→goal grundsätzlich erreichbar (SWIM an).
	var pf_a8 := Pathfinder3D.new()
	pf_a8.build(g)
	if not pf_a8.reachable(start, goal):
		fails = _tac3d_fail(fails, "A8: start→goal nicht erreichbar")

	# ---------- Block B: Szene öffnet + Unit fährt Pfad ----------
	goto("tactical3d")
	var tac = current
	await tac.map_ready

	# B1: await kehrte zurück → Szene ohne Skriptfehler geöffnet.
	if tac == null:
		fails = _tac3d_fail(fails, "B1: tactical3d-Szene nicht geöffnet")
	else:
		var tmeta: Dictionary = tac.meta

		# B2: Unit existiert und steht am Start.
		if tac.unit == null:
			fails = _tac3d_fail(fails, "B2: Unit ist null")
		elif tac.unit.cell != tmeta["start"]:
			fails = _tac3d_fail(fails, "B2: Unit steht nicht am Start (%s)" % str(tac.unit.cell))

		# B3: Demo-Pfad endet am Ziel und nutzt die Brücke.
		var cells: Array = tac.find_demo_path()
		if cells.is_empty():
			fails = _tac3d_fail(fails, "B3: find_demo_path leer")
		else:
			if cells.back() != tmeta["goal"]:
				fails = _tac3d_fail(fails, "B3: Demo-Pfad endet nicht am Ziel (%s)" % str(cells.back()))
			if not _tac3d_has_kind(tac.grid, cells, Tac3DTile.Kind.BRIDGE):
				fails = _tac3d_fail(fails, "B3: Demo-Pfad nutzt die Brücke nicht")

		# B4: Unit fährt den Pfad und steht danach am Ziel.
		tac.move_unit_along(cells)
		if tac.unit == null or tac.unit.cell != tmeta["goal"]:
			var reached := "null" if tac.unit == null else str(tac.unit.cell)
			fails = _tac3d_fail(fails, "B4: Unit erreichte das Ziel nicht (bei %s)" % reached)

		# B5: Kamera ist orthogonal.
		if tac.rig == null or tac.rig.cam == null:
			fails = _tac3d_fail(fails, "B5: Rig/Kamera fehlt")
		elif tac.rig.cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
			fails = _tac3d_fail(fails, "B5: Kamera nicht orthogonal (%d)" % tac.rig.cam.projection)

	if fails == 0:
		print("TAC3D OK")
	else:
		print("TAC3D FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

## Hilfsfunktion: existiert in cells eine Zelle des gegebenen Kind?
func _tac3d_has_kind(g: Grid3D, cells: Array, kind: int) -> bool:
	for k in cells:
		var c: Vector3i = k
		if not g.has_tile(c):
			continue
		var t: Tac3DTile = g.get_tile(c)
		if t != null and t.kind == kind:
			return true
	return false

# ============================================================ 3D-Schlacht-Smoke (Strang A)

func _smoke3d_fail(fails: int, msg: String) -> int:
	push_error("SMOKE3D-FEHLER: " + msg)
	print("SMOKE3D-FEHLER: ", msg)
	return fails + 1

## Erreichbarkeit ueber den Pathfinder3D (Vertrag §1.7).
func _reachable3d(pf: Pathfinder3D, from: Vector3i, to: Vector3i) -> bool:
	return pf.reachable(from, to)

## Voller Bot-Schlacht-Nachweis der 3D-Taktik (p2_1 §4): Karte (K), Anheuern (H),
## Schlacht bis Sieg (B), Inventar/Loot (I). --smoke / --tac3d bleiben unberuehrt.
func _smoke3d() -> void:
	print("SMOKE3D: Start")
	var fails := 0

	# ---------- Block K: Karte (alle 3 Grade) ----------
	for diff in ["leicht", "normal", "schwer"]:
		var mp := Tac3DMapGen.generate(20260718, diff)
		var g: Grid3D = mp["grid"]
		# K1: Gegnerzahl == Db.DIFFICULTY[diff]["enemies"] (10/13/17).
		var expected := int(Db.DIFFICULTY[diff]["enemies"])
		if mp["enemy_spawns"].size() != expected:
			fails = _smoke3d_fail(fails, "[%s] K1: Gegnerzahl %d statt %d" % [diff, mp["enemy_spawns"].size(), expected])
		# K2: alle Merc-/Gegner-Spawns begehbar.
		for sp in mp["merc_spawns"]:
			var mc: Vector3i = sp
			if not g.is_walkable(mc):
				fails = _smoke3d_fail(fails, "[%s] K2: Merc-Spawn blockiert: %s" % [diff, str(mc)])
		for es in mp["enemy_spawns"]:
			var ec: Vector3i = es["cell"]
			if not g.is_walkable(ec):
				fails = _smoke3d_fail(fails, "[%s] K2: Gegner-Spawn blockiert: %s (%s)" % [diff, str(ec), String(es["type"])])
		# K3: LEICHT ohne Elitewachen (Downgrade greift).
		if diff == "leicht":
			for es in mp["enemy_spawns"]:
				if String(es["type"]).begins_with("elite"):
					fails = _smoke3d_fail(fails, "K3: LEICHT enthaelt Elitewache (%s)" % String(es["type"]))
					break
		# K4: mind. 5 Loot-Kacheln.
		if mp["loot_cells"].size() < 5:
			fails = _smoke3d_fail(fails, "[%s] K4: zu wenige Loot-Kacheln: %d" % [diff, mp["loot_cells"].size()])

	# Struktur-Assertions (Geometrie diff-unabhaengig) auf einer Karte.
	var kmap := Tac3DMapGen.generate(20260718, "leicht")
	var kg: Grid3D = kmap["grid"]
	var mspawn0: Vector3i = kmap["merc_spawns"][0]
	var boss_home: Vector3i = kmap["boss_home"]
	var bridge_cells: Array = kmap["bridge_cells"]

	# K5: Erreichbarkeit ueber die Bruecke (SWIM aus): Pfad Merc->Boss nutzt BRIDGE + RAMP.
	var pf_k5 := Pathfinder3D.new()
	pf_k5.build(kg)
	pf_k5.set_move_type_enabled(Tac3DTile.Move.SWIM, false)
	if not _reachable3d(pf_k5, mspawn0, boss_home):
		fails = _smoke3d_fail(fails, "K5: Boss vom Merc-Spawn nicht erreichbar (SWIM aus)")
	else:
		var p5: Array = pf_k5.path_cells(mspawn0, boss_home)
		if not _tac3d_has_kind(kg, p5, Tac3DTile.Kind.BRIDGE):
			fails = _smoke3d_fail(fails, "K5: Pfad Merc->Boss nutzt die Bruecke nicht")
		if not _tac3d_has_kind(kg, p5, Tac3DTile.Kind.RAMP):
			fails = _smoke3d_fail(fails, "K5: Pfad Merc->Boss nutzt keine Rampe (Ebene 1)")

	# K6: tiefes Wasser vs. Deck darueber — verschiedene IDs/Renderhoehe, NICHT verbunden.
	var pf_k6 := Pathfinder3D.new()
	pf_k6.build(kg)
	var deep: Vector3i = kmap["deep_under_deck"]
	var deck: Vector3i = kmap["deck_over_deep"]
	var id_deep := pf_k6.point_id(deep)
	var id_deck := pf_k6.point_id(deck)
	if id_deep < 0 or id_deck < 0:
		fails = _smoke3d_fail(fails, "K6: fehlende Punkte (deep=%d, deck=%d)" % [id_deep, id_deck])
	elif id_deep == id_deck:
		fails = _smoke3d_fail(fails, "K6: deep/deck teilen dieselbe ID (%d)" % id_deep)
	else:
		if kg.cell_to_world(deep).y == kg.cell_to_world(deck).y:
			fails = _smoke3d_fail(fails, "K6: deep/deck haben gleiche Renderhoehe")
		if pf_k6.astar.are_points_connected(id_deep, id_deck):
			fails = _smoke3d_fail(fails, "K6: deep/deck faelschlich verbunden")

	# K7: Schwimmen unter der Bruecke — Deck gesperrt, SWIM an: Pfad durch WATER_DEEP.
	var pf_k7 := Pathfinder3D.new()
	pf_k7.build(kg)
	for bc in bridge_cells:
		var b7: Vector3i = bc
		pf_k7.set_cell_blocked(b7, true)
	var p7: Array = pf_k7.path_cells(kmap["swim_from"], kmap["swim_to"])
	if p7.is_empty():
		fails = _smoke3d_fail(fails, "K7: kein Pfad swim_from->swim_to")
	elif not _tac3d_has_kind(kg, p7, Tac3DTile.Kind.WATER_DEEP):
		fails = _smoke3d_fail(fails, "K7: Schwimm-Pfad meidet tiefes Wasser")
	print("SMOKE3D: Karte ok (Loot: %d)" % kmap["loot_cells"].size())

	# ---------- Block H: Anheuern (1:1 wiederverwendet) ----------
	Game.new_game()
	Game.set_difficulty("leicht")
	if not Game.hire("ivan"):
		fails = _smoke3d_fail(fails, "H1: Ivan konnte nicht angeheuert werden")
	if not Game.hire("fuchs"):
		fails = _smoke3d_fail(fails, "H1: Fuchs konnte nicht angeheuert werden")
	if not Game.hire("doc"):
		fails = _smoke3d_fail(fails, "H1: Doc konnte nicht angeheuert werden")
	if Game.hire("blitz"):
		fails = _smoke3d_fail(fails, "H1: Blitz haette am Budget scheitern muessen")
	if not Game.hire("nadel"):
		fails = _smoke3d_fail(fails, "H1: Nadel konnte nicht angeheuert werden")
	if Game.team.size() != 4 or Game.budget != 0:
		fails = _smoke3d_fail(fails, "H1: Team %d / Budget %d — erwartet 4 / 0" % [Game.team.size(), Game.budget])
	# H2: Preisfaktor SCHWER == 1,5.
	Game.set_difficulty("schwer")
	if Game.eff_cost(1000) != 1500:
		fails = _smoke3d_fail(fails, "H2: Preisfaktor SCHWER falsch: %d" % Game.eff_cost(1000))
	Game.set_difficulty("leicht")
	# Testboost: Bot spielt grob — mit Boost muss der komplette Siegpfad klappen.
	for m in Game.team:
		m["hp"] = int(m["hp"]) * 2 + 60
		m["hp_max"] = m["hp"]
		m["marks"] = mini(95, int(m["marks"]) + 15)
		var cal := String(Db.weapon(m["weapon"])["cal"])
		while (m["inv"] as Array).size() < Db.INV_SLOTS:
			m["inv"].append("mag_" + cal)
	print("SMOKE3D: Anheuern + Testboost ok")

	# ---------- Block B: Schlacht (B1 alle Grade, B2-B5 + I fuer LEICHT) ----------
	for diff in ["leicht", "normal", "schwer"]:
		Game.set_difficulty(diff)
		goto("tactical3d_combat")
		var tac = current
		await tac.battle_ready
		# B1: neutraler Spawn — kein Kampf, kein Sichtkontakt beim Start (spec §14.3).
		if tac.combat_started or tac._any_contact():
			fails = _smoke3d_fail(fails, "[%s] B1: Missionsstart mit Feindkontakt (Spawn nicht neutral)" % diff)
		if diff != "leicht":
			continue
		# B2: LEICHT hat 10 Gegner.
		if tac.enemies.size() != 10:
			fails = _smoke3d_fail(fails, "B2: Gegnerzahl %d statt 10 (leicht)" % tac.enemies.size())
		# B3: Bot spielt bis Sieg.
		Game.boss_dialog_seen = false
		var res: String = await tac.auto_battle()
		print("SMOKE3D: Ergebnis = %s nach %d Runden (Schuesse: %d, Treffer: %d)" % [res, int(Game.stats["turns"]), int(Game.stats["shots"]), int(Game.stats["hits"])])
		if res != "victory":
			fails = _smoke3d_fail(fails, "B3: Bot-Team siegte nicht (Ergebnis '%s')" % res)
		else:
			# B4: Sieg nur nach Boss-Sichtung.
			if not Game.boss_dialog_seen:
				fails = _smoke3d_fail(fails, "B4: Sieg ohne Boss-Sichtung/Dialog")
			# B5: kein Gegner lebt mehr.
			for e in tac.enemies:
				var en: Tac3DUnit = e
				if en.alive:
					fails = _smoke3d_fail(fails, "B5: nach dem Sieg lebt noch ein Gegner")
					break
		# ---------- Block I: Inventar/Loot (Karte noch geladen) ----------
		fails = _smoke3d_inventory(tac, fails)

	if fails == 0:
		print("SMOKE3D OK")
	else:
		print("SMOKE3D FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

## Block I — Inventar-/Loot-Funktionstests (Logik-Reuse aus _smoke), 3D-API.
func _smoke3d_inventory(tac, fails: int) -> int:
	var mt: Tac3DUnit = null
	for m in tac.mercs:
		var merc: Tac3DUnit = m
		if merc.alive:
			mt = merc
			break
	if mt == null:
		print("SMOKE3D: Block I uebersprungen (kein lebender Soeldner)")
		return fails
	# I1: Nachladen verbraucht genau 1 Magazin.
	var cal2 := String(Db.weapon(mt.data["weapon"])["cal"])
	mt.data["inv"] = ["mag_" + cal2]
	mt.data["ammo"] = 0
	mt.ap = 99
	tac.do_reload(mt)
	if int(mt.data["ammo"]) != int(Db.weapon(mt.data["weapon"])["mag"]) or (mt.data["inv"] as Array).size() != 0:
		fails = _smoke3d_fail(fails, "I1: Nachladen verbrauchte das Magazin nicht korrekt")
	else:
		print("SMOKE3D: I1 Nachladen ok")
	# I2: Waffenwechsel auf k45.
	mt.data["inv"] = ["k45"]
	mt.ap = 99
	tac.do_swap(mt, 0)
	if String(mt.data["weapon"]) != "k45":
		fails = _smoke3d_fail(fails, "I2: Waffenwechsel fehlgeschlagen")
	else:
		print("SMOKE3D: I2 Waffenwechsel ok")
	# I3: Kiste durchsuchen -> als geleert markiert.
	var lootc := Vector3i(-99, 0, -99)
	for c in tac.loot_cells:
		var lc: Vector3i = c
		if tac.search_target_at(lc) == "crate":
			lootc = lc
			break
	if lootc.x <= -50:
		print("SMOKE3D: I3 uebersprungen (keine Kiste vorhanden)")
		return fails
	var placed := false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if placed or (dx == 0 and dz == 0):
				continue
			var n: Vector3i = lootc + Vector3i(dx, 0, dz)
			if tac.grid.is_walkable(n) and not tac.occupied.has(n):
				tac._vacate(mt.cell)
				mt.set_cell(n)
				tac._occupy(mt, n)
				placed = true
	if not placed:
		print("SMOKE3D: I3 uebersprungen (kein freier Nachbar an der Kiste)")
		return fails
	mt.ap = 99
	mt.data["inv"] = []
	tac.do_search(mt, lootc)
	if tac.search_target_at(lootc) == "crate":
		fails = _smoke3d_fail(fails, "I3: Kiste nach Durchsuchen nicht als geleert markiert")
	else:
		print("SMOKE3D: I3 Kisten-Loot ok")
	return fails

# ============================================================ Smoke-Test

func _fail(fails: int, msg: String) -> int:
	push_error("SMOKE-FEHLER: " + msg)
	print("SMOKE-FEHLER: ", msg)
	return fails + 1

func _smoke() -> void:
	print("SMOKE: Start")
	var fails := 0

	# --- Kartengenerierung (alle Schwierigkeitsgrade)
	for diff in ["leicht", "normal", "schwer"]:
		var mp := MapGen.generate(4242, diff)
		var expected := int(Db.DIFFICULTY[diff]["enemies"])
		if mp["enemy_spawns"].size() != expected:
			fails = _fail(fails, "[%s] Gegnerzahl %d statt %d" % [diff, mp["enemy_spawns"].size(), expected])
		var wk: Array = mp["walk"]
		for sp in mp["merc_spawns"]:
			if not wk[sp.y * MapGen.W + sp.x]:
				fails = _fail(fails, "[%s] Söldner-Spawn blockiert: %s" % [diff, str(sp)])
		for es in mp["enemy_spawns"]:
			var c: Vector2i = es["cell"]
			if not wk[c.y * MapGen.W + c.x]:
				fails = _fail(fails, "[%s] Gegner-Spawn blockiert: %s (%s)" % [diff, str(c), es["type"]])
	var map := MapGen.generate(4242, "leicht")
	if not _reachable(map["walk"], Vector2i(3, 24), Vector2i(32, 2)):
		fails = _fail(fails, "Boss vom Spawn aus nicht erreichbar")
	if map["loot_cells"].size() < 5:
		fails = _fail(fails, "Zu wenige Loot-Kisten: %d" % map["loot_cells"].size())
	for es in map["enemy_spawns"]:
		if String(es["type"]).begins_with("elite"):
			fails = _fail(fails, "LEICHT enthält noch Elitewachen (%s)" % es["type"])
			break
	print("SMOKE: Karten ok (Loot-Kisten: %d, Requisiten: %d)" % [map["loot_cells"].size(), map["props"].size()])

	# --- Anheuern (LEICHT: Preisfaktor 1,0 → exakte Budgetrechnung)
	Game.new_game()
	Game.set_difficulty("leicht")
	if not Game.hire("ivan"):
		fails = _fail(fails, "Ivan konnte nicht angeheuert werden")
	if not Game.hire("fuchs"):
		fails = _fail(fails, "Fuchs konnte nicht angeheuert werden")
	if not Game.hire("doc"):
		fails = _fail(fails, "Doc konnte nicht angeheuert werden")
	if Game.hire("blitz"):
		fails = _fail(fails, "Blitz anheuern hätte am Budget scheitern müssen")
	if not Game.hire("nadel"):
		fails = _fail(fails, "Nadel konnte nicht angeheuert werden")
	if Game.team.size() != 4 or Game.budget != 0:
		fails = _fail(fails, "Team %d / Budget %d — erwartet 4 / 0" % [Game.team.size(), Game.budget])
	# Preisfaktor-Check
	Game.set_difficulty("schwer")
	if Game.eff_cost(1000) != 1500:
		fails = _fail(fails, "Preisfaktor SCHWER falsch: %d" % Game.eff_cost(1000))
	Game.set_difficulty("leicht")
	print("SMOKE: Anheuern ok — Team: ", ", ".join(Game.team.map(func(m): return String(m["nick"]))))

	# Testboost: Bot spielt grob — mit Boost muss der komplette Siegpfad klappen.
	for m in Game.team:
		m["hp"] = int(m["hp"]) * 2 + 60
		m["hp_max"] = m["hp"]
		m["marks"] = mini(95, int(m["marks"]) + 15)
		var cal := String(Db.weapon(m["weapon"])["cal"])
		while (m["inv"] as Array).size() < Db.INV_SLOTS:
			m["inv"].append("mag_" + cal)
	print("SMOKE: Testboost für Bot-Team aktiv")

	# --- Taktik-Schlacht (Bot vs. KI, Schwierigkeit LEICHT → 10 Gegner)
	goto("tactical")
	var tac = current
	await tac.battle_ready
	print("SMOKE: Schlacht beginnt — Gegner: %d, Söldner: %d" % [tac.enemies.size(), tac.mercs.size()])
	if tac.enemies.size() != 10:
		fails = _fail(fails, "Gegnerzahl %d statt 10 (leicht)" % tac.enemies.size())
	if tac.combat_started or tac._any_contact():
		fails = _fail(fails, "Mission startet mit Feindkontakt — Spawn liegt im Sichtfeld")
	else:
		print("SMOKE: Spawn neutral — Anmarschphase aktiv")
	var res: String = await tac.auto_battle()
	print("SMOKE: Missionsergebnis = %s nach %d Runden (Schüsse: %d, Treffer: %d)" % [res, int(Game.stats["turns"]), int(Game.stats["shots"]), int(Game.stats["hits"])])
	if res != "victory":
		fails = _fail(fails, "Bot-Team hätte mit Testboost siegen sollen (Ergebnis: '%s')" % res)
	else:
		if not Game.boss_dialog_seen:
			fails = _fail(fails, "Sieg ohne Boss-Sichtung/Dialog")
		for e in tac.enemies:
			if e.alive:
				fails = _fail(fails, "Nach dem Sieg lebt noch ein Gegner")
				break

	# --- Inventar-/Loot-Funktionstests (nach Schlachtende, Karte noch geladen)
	var mt: BattleUnit = null
	for m in tac.mercs:
		if m.alive:
			mt = m
			break
	if mt != null:
		# Nachladen verbraucht ein Magazin
		var cal2 := String(Db.weapon(mt.data["weapon"])["cal"])
		mt.data["inv"] = ["mag_" + cal2]
		mt.data["ammo"] = 0
		mt.ap = 99
		tac.battle_over = false
		tac.do_reload(mt)
		tac.battle_over = true
		if int(mt.data["ammo"]) != int(Db.weapon(mt.data["weapon"])["mag"]) or (mt.data["inv"] as Array).size() != 0:
			fails = _fail(fails, "Nachladen: Magazin wurde nicht korrekt verbraucht")
		else:
			print("SMOKE: Magazin-Nachladen ok")
		# Waffenwechsel
		mt.data["inv"] = ["k45"]
		mt.ap = 99
		tac.do_swap(mt, 0)
		if String(mt.data["weapon"]) != "k45":
			fails = _fail(fails, "Waffenwechsel fehlgeschlagen")
		else:
			print("SMOKE: Waffenwechsel ok")
		# Kiste durchsuchen
		var lootc := Vector2i(-1, -1)
		for c in tac.loot_cells:
			if tac.search_target_at(c) == "crate":
				lootc = c
				break
		if lootc.x >= 0:
			var placed := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if placed or (dx == 0 and dy == 0):
						continue
					var n: Vector2i = lootc + Vector2i(dx, dy)
					if tac.in_bounds(n) and tac.walk[n.y * MapGen.W + n.x] and not tac.occupied.has(n):
						tac._vacate(mt.cell)
						mt.set_cell(n)
						tac._occupy(mt, n)
						placed = true
			if placed:
				mt.ap = 99
				mt.data["inv"] = []
				tac.do_search(mt, lootc)
				if tac.search_target_at(lootc) == "crate":
					fails = _fail(fails, "Kiste nach Durchsuchen nicht als geleert markiert")
				else:
					print("SMOKE: Kisten-Loot ok (%d Item(s) insgesamt gelootet)" % int(Game.stats["loot"]))
		else:
			print("SMOKE: Hinweis — alle Kisten zerstört, Loot-Test übersprungen")

	# --- Endscreen
	goto("end")
	await get_tree().process_frame
	await get_tree().process_frame
	print("SMOKE: Endscreen ok")

	if fails == 0:
		print("SMOKE OK")
	else:
		print("SMOKE FAIL (%d Fehler)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _reachable(walk: Array, from: Vector2i, to: Vector2i) -> bool:
	var w := MapGen.W
	var h := MapGen.H
	var seen := {}
	var queue: Array = [from]
	seen[from] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if seen.has(n) or not walk[n.y * w + n.x]:
				continue
			seen[n] = true
			queue.append(n)
	return false

# ============================================================ Screenshots

func _shots(outdir: String) -> void:
	print("SHOTS: nach ", outdir)
	Sfx.muted = true
	goto("title")
	await _wait(1.0)
	await _snap(outdir + "/01_titel.png")
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	goto("hire")
	await _wait(0.6)
	await _snap(outdir + "/02_anheuern.png")
	goto("island")
	await _wait(0.6)
	await _snap(outdir + "/03_insel.png")
	goto("tactical")
	await current.battle_ready
	current.cam.position = Vector2(16 * 64, 15 * 64)
	await _wait(0.8)
	await _snap(outdir + "/04_taktik.png")
	current.cam.position = Vector2(32 * 64, 5 * 64)
	await _wait(0.4)
	await _snap(outdir + "/05_anwesen.png")
	print("SHOTS: fertig")
	get_tree().quit()

func _tac3d_shots(outdir: String) -> void:
	print("TAC3D-SHOTS: nach ", outdir)
	Sfx.muted = true
	goto("tactical3d")
	await current.map_ready
	# Kamera auf Feldmitte, Zoom so, dass das ganze Testfeld sichtbar ist.
	current.rig.focus_world(current.rig.field.get_center())
	current.rig.set_zoom(26.0)
	await _wait(0.6)
	await _snap(outdir + "/tac3d_01_overview.png")
	# Zweite Perspektive: Kamera um 45° drehen.
	current.rig.rotate_step(1)
	await _wait(0.6)
	await _snap(outdir + "/tac3d_02_rotated.png")
	# Söldner den Demo-Pfad über die Brücke aufs Podest schicken.
	var cells: Array = current.find_demo_path()
	if not cells.is_empty():
		current.move_unit_along(cells)
		if current.unit != null:
			await current.unit.move_finished
	await _wait(0.5)
	await _snap(outdir + "/tac3d_03_bridge.png")
	# Nahaufnahme des Soeldners: KayKit-Charakter + Waffe sichtbar (Strang B, p2_2 §4).
	if current.unit != null:
		current.rig.focus_world(current.unit.position)
		current.rig.set_zoom(8.0)
		await _wait(0.5)
		await _snap(outdir + "/tac3d_04_soldier.png")
		# Schuss-Animation.
		current.unit.play_anim("shoot")
		await _wait(0.4)
		await _snap(outdir + "/tac3d_05_shoot.png")
		# Tod-Animation.
		current.unit.play_anim("death")
		await _wait(0.7)
		await _snap(outdir + "/tac3d_06_death.png")
	print("TAC3D-SHOTS: fertig")
	get_tree().quit()

# ============================================================ 3D-HUD (Phase 3)

func _hud3d_fail(fails: int, msg: String) -> int:
	push_error("HUD3D-FEHLER: " + msg)
	print("HUD3D-FEHLER: ", msg)
	return fails + 1

## Headless-Interaktionstest der spielbaren 3D-Schlacht (p3_1 §4b). Baut die HUD (fast=false),
## prueft Auswahl/Move/Schuss ueber die ui_*-API + HUD-State. Aendert keine Kernlogik.
func _hud3d() -> void:
	print("HUD3D: Start")
	var fails := 0
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	goto("tactical3d_combat")
	var tac = current
	await tac.battle_ready

	# H1: HUD existiert (nur bei not fast gebaut).
	if tac.hud == null:
		fails = _hud3d_fail(fails, "H1: HUD wurde nicht gebaut (hud == null)")
		print("HUD3D FAIL (%d)" % fails)
		get_tree().quit(1)
		return

	# H2: Soeldnerwahl ueber die HUD-API.
	tac.ui_select_slot(1)
	if tac.selected != tac.mercs[1]:
		fails = _hud3d_fail(fails, "H2: ui_select_slot(1) waehlte nicht mercs[1]")
	tac.ui_select_slot(0)
	var m0: Tac3DUnit = tac.mercs[0]

	# H3: Zug-Move (Anmarsch, frei) ueber do_move veraendert die Zelle.
	var tgt: Vector3i = tac._nearest_alive_enemy_cell(m0.cell)
	var cells: Array = tac.prefix_for_ap(tac.path_toward(m0, tgt), 12)
	var before: Vector3i = m0.cell
	await tac.do_move(m0, cells)
	if m0.cell == before:
		fails = _hud3d_fail(fails, "H3: do_move veraenderte die Zelle nicht (%s)" % str(before))

	# H4: HUD spiegelt die Auswahl (Goldrahmen auf Slot 0).
	if not tac.hud.has_selected_frame(0):
		fails = _hud3d_fail(fails, "H4: HUD zeigt keinen Goldrahmen fuer Slot 0")

	# H5: Schuss senkt Munition + HUD-Munitionslabel (deterministisch: Abzug vor Trefferwurf).
	tac.combat_started = true
	var en: Tac3DUnit = null
	for e in tac.enemies:
		var enemy: Tac3DUnit = e
		if enemy.alive:
			en = enemy
			break
	if en == null:
		fails = _hud3d_fail(fails, "H5: kein lebender Gegner fuer den Schuss")
	else:
		var ammo0 := int(m0.data["ammo"])
		m0.ap = 99
		await tac.shoot(m0, en)
		if int(m0.data["ammo"]) != ammo0 - 1:
			fails = _hud3d_fail(fails, "H5: Munition nicht um 1 gesenkt (%d statt %d)" % [int(m0.data["ammo"]), ammo0 - 1])
		tac.hud.refresh()
		if not tac.hud.ammo_text().contains(str(ammo0 - 1)):
			fails = _hud3d_fail(fails, "H5: HUD ammo_text spiegelt die Munition nicht (%s)" % tac.hud.ammo_text())

	if fails == 0:
		print("HUD3D OK")
	else:
		print("HUD3D FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

## Fenster-Screenshot mit HUD (p3_1 §4c). fast=false -> Portraits/HP-AP-Balken/Aktionsleiste
## liegen als CanvasLayer ueber der 3D-Szene und werden vom Viewport-Snap erfasst.
func _hud3d_shots(outdir: String) -> void:
	print("HUD3D-SHOTS: nach ", outdir)
	Sfx.muted = true
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	goto("tactical3d_combat")
	await current.battle_ready
	current.ui_select_slot(0)
	# Kamera auf den gewaehlten Soeldner fokussieren + nah heranzoomen.
	current.rig.focus_world(current.grid.cell_to_world(current.mercs[0].cell))
	current.rig.set_zoom(16.0)
	await _wait(0.6)
	await _snap(outdir + "/hud3d_01_overview.png")
	# Aktionsleisten-Zustand „Zielen ×1" sichtbar machen.
	current.ui_aim()
	await _wait(0.3)
	await _snap(outdir + "/hud3d_02_aim.png")
	get_tree().quit()

# ============================================================ 3D-Juice / Game-Feel (Phase 4)

## Fenster-Screenshot eines Schusses MITTEN im Kampf mit sichtbaren Juice-Effekten
## (Muendungsfeuer/Tracer/Schadenszahl/Blut, Screenshake, Hitstop). Laeuft interaktiv
## (fast bleibt false) -> juice existiert. Deterministische Asserts (FIX F4): nach dem
## Schuss juice-Kinderzahl>0 UND nach kurzem Warten Engine.time_scale==1.0; Label/Blut
## nur "falls Treffer" (hit_chance ist 5-95 geklemmt -> ~5% Miss, kein harter Assert).
func _juice_shots(outdir: String) -> void:
	print("JUICE-SHOTS: nach ", outdir)
	Sfx.muted = true
	# Fenster NICHT drosseln: ein unfokussiertes/vsync-gepacetes Fenster rendert so langsam,
	# dass die kurzen (~60-100ms) Muzzle/Tracer-Effekte zwischen Trigger und Snap ablaufen.
	# Uncapped + vsync aus => Frame-Latenz << Effekt-Lebensdauer, der Snap trifft den Effekt.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	seed(20260718)   # deterministischer globaler RNG fuer den Trefferwurf
	var fails := 0

	# 1) Default-Team aufstellen + Trefferboost, damit der Schuss quasi sicher trifft.
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	for m in Game.team:
		m["marks"] = 95

	# 2) Schlacht oeffnen (interaktiv -> juice wird gebaut).
	goto("tactical3d_combat")
	var tac = current
	await tac.battle_ready
	if tac.juice == null:
		push_error("JUICE-SHOTS: juice ist null (fast faelschlich aktiv?)")
		fails += 1

	# 3) Deterministisches Duell: den Gegner moeglichst WEIT in offenes Terrain legen
	#    (laengster freier Kardinal-Lauf ab merc), damit Muendungsfeuer + Leuchtspur
	#    nicht im Soeldner-Pulk verschwinden. marks=95 haelt den Treffer auch auf Distanz;
	#    Muzzle/Tracer sind ohnehin trefferunabhaengig. Fallback = alte kurze Liste.
	var merc = tac.mercs[0]
	var foe = tac.enemies[0]
	var duel_gap := 5
	var shoot_from: Vector3i = merc.cell + Vector3i(3, 0, 0)
	var best_run := 0
	for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var dv: Vector3i = dir
		var run := 0
		for step in range(1, duel_gap + 1):
			var cand: Vector3i = merc.cell + dv * step
			if tac.grid.is_walkable(cand) and not tac.occupied.has(cand):
				run = step
			else:
				break
		if run > best_run:
			best_run = run
			shoot_from = merc.cell + dv * run
	if best_run < 3:
		for cand in [merc.cell + Vector3i(3, 0, 0), merc.cell + Vector3i(0, 0, 3), merc.cell + Vector3i(-3, 0, 0), merc.cell + Vector3i(0, 0, -3), merc.cell + Vector3i(2, 0, 0)]:
			var c2: Vector3i = cand
			if tac.grid.is_walkable(c2) and not tac.occupied.has(c2):
				shoot_from = c2
				break
	tac._vacate(foe.cell)
	foe.set_cell(shoot_from)
	tac._occupy(foe, shoot_from)
	foe.set_seen(true)
	merc.ap = 99
	tac.combat_started = true
	tac.compute_vision()

	# 4) Kamera aufs Duell (Zoom so, dass Schuetze, Ziel, Leuchtspur + Schadenszahl ins Bild passen).
	tac.rig.focus_world((tac.grid.cell_to_world(merc.cell) + tac.grid.cell_to_world(foe.cell)) * 0.5)
	tac.rig.set_zoom(14.0)
	await _wait(0.4)
	await _snap(outdir + "/juice_00_setup.png")

	# 5) Schuss ausloesen: shoot() ist eine Coroutine — der Muzzle/Tracer-Block laeuft
	#    synchron bis zum ersten `await dl(0.13)`, danach kehrt die Kontrolle sofort zu
	#    uns zurueck. NICHT blockierend awaiten (Effekte leben nur ~60ms -> Snap direkt
	#    nach dem Trigger). Kinderzahl vorher merken.
	var before: int = tac.juice.get_child_count()
	tac.shoot(merc, foe)
	await _snap(outdir + "/juice_01_shot.png")
	# FIX F4: deterministischer Assert — nach dem Schuss existieren Effekt-Nodes.
	if tac.juice.get_child_count() <= before:
		push_error("JUICE-SHOTS: keine Effekt-Nodes nach Schuss (%d)" % tac.juice.get_child_count())
		fails += 1
	# Screenshake wurde ausgeloest (Schuss-Kick, trefferunabhaengig).
	if tac.rig.trauma <= 0.0:
		push_error("JUICE-SHOTS: kein Trauma nach Schuss (Screenshake nicht ausgeloest)")
		fails += 1

	# 6) Kurz warten -> Treffer (nach dl 0.13): Blut + Schadenszahl + Hit-Flash.
	await _wait(0.2)
	var has_label := false
	for c in tac.juice.get_children():
		if c is Label3D:
			has_label = true
			break
	await _snap(outdir + "/juice_02_damage.png")
	# Label/Blut nur "falls Treffer" — kein harter Assert (siehe Doc oben).
	print("JUICE-SHOTS: Treffer bestaetigt (Schadenszahl sichtbar)" if has_label else "JUICE-SHOTS: Miss (kein Label — trefferabhaengig, ok)")

	# 7) FIX F4: der schaerfste Waechter — nach dem Hitstop ist time_scale zurueck auf 1.0.
	await _wait(0.5)
	if Engine.time_scale != 1.0:
		push_error("JUICE-SHOTS: time_scale nicht auf 1.0 zurueck (%.3f) — Hitstop-Reset-Falle!" % Engine.time_scale)
		fails += 1

	if fails == 0:
		print("JUICE OK")
	else:
		print("JUICE FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT: ", path)

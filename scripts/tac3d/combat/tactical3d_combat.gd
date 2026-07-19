extends Node3D
## Orchestrator-Screen der 3D-Taktik-SCHLACHT (Strang A). KEIN class_name (Vertrag Â§1.6/Â§10).
## Portiert die reine Kampf-Logik aus scripts/screens/tactical.gd (AP, Sicht/LOS, Deckung,
## Zielen, Schuss/Treffer, Unterbrechungen, KI/Leine, Laerm, Granaten, Loot, Boss, Sieg)
## 1:1 auf Grid3D/Pathfinder3D/Tac3DUnit. Alle Reichweiten laufen FLACH auf (x,z); die
## Ebene (y) traegt nur Hoehenboni (Sicht/Treffer) + Ebenen-Links (Bruecke/Rampe).
##
## Aufbau-Reihenfolge (Scaffold-Muster von tactical3d.gd): Container-Nodes ZUERST, dann
## Karte/Pathfinder/View/Vision/AI/Rig/Picker/Units, battle_ready DEFERRED.
##
## GDScript-Fallen (verbindlich, p2_1 Â§7): typisierte Variant-Iteration, Integer-Division
## bewahren (int(agi)/5 etc.), call_deferred fuer Signale, MOVE_AP.get(move_type, 2),
## duplicate(true) bei Enemy-Defs, path_for ent-/sperrt u.cell, await-Ketten vollstaendig.

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

var units: Array = []            # alle Tac3DUnit
var mercs: Array = []
var enemies: Array = []
var boss: Tac3DUnit = null
var captive: Tac3DUnit = null    # Otto, bis befreit (NICHT in mercs/units/enemies)
var occupied: Dictionary = {}    # Vector3i -> Tac3DUnit
var corpses: Dictionary = {}     # Vector3i -> Tac3DUnit
var visible_cells: Dictionary = {}   # Vector3i -> true (K2: pro Zielzelle gesehen)
var looted: Dictionary = {}      # Vector3i -> true (geleerte Kiste / zerstoerte Deckung)
var loot_cells: Array = []       # begehbare Deckungs-/Loot-Kacheln (aus MapGen)

var selected: Tac3DUnit = null
var mode := "move"
var aim_level := 0
var player_turn := true
var busy := false
var battle_over := false
var combat_started := false
var no_contact_rounds := 0
var noise_at := Vector3i(-99, -99, -99)
var turn := 1
var loot_rng := RandomNumberGenerator.new()

# Interaktiver View-/Controller-Rand (nur bei not fast gebaut; im Bot-Lauf null).
var hud = null                       # CombatHud oder null
var cursor: CursorView3D = null
var juice = null                     # Juice3D oder null (nur not fast; im Bot immer null)
var hover_cell := Picker3D.NONE
var hover_path: Array = []

# Ersetzt v2 step_cost (2/3 AP, Diagonalen). Grid3D ist diagonalfrei, Wasser teurer.
const MOVE_AP := {
	Tac3DTile.Move.WALK: 2,
	Tac3DTile.Move.WADE: 4,
	Tac3DTile.Move.SWIM: 6,
	Tac3DTile.Move.CLIMB: 3,
}
const HEIGHT_HIT_BONUS := 8.0    # Trefferbonus je Ebene Hoehenvorteil (spec Â§6.2)
const PAN_SPEED := 24.0
var _cam_dragging := false   # Mittelmaus gedrueckt = Karte greifen und scrollen
var _drag_last := Vector2.ZERO

var _world_root: Node3D
var _units_root: Node3D


func _main() -> Node:
	return get_parent()


# ================================================================= Aufbau

func _ready() -> void:
	# 1) fast-Flag aus dem Parent (Harness). Null-Guard.
	var m := _main()
	if m != null and m.get("fast") == true:
		fast = true
	loot_rng.seed = 987654 + hash(Game.difficulty)

	# 2) Container-Nodes ZUERST (Fix K2/Scaffold), BEVOR etwas eingehaengt wird.
	rig = CameraRig3D.new()
	rig.name = "CameraRig"
	add_child(rig)

	_world_root = Node3D.new()
	_world_root.name = "WorldRoot"
	add_child(_world_root)

	_units_root = Node3D.new()
	_units_root.name = "UnitsRoot"
	add_child(_units_root)

	# 3) Karte + Grid (die Wahrheit).
	meta = Tac3DMapGen.generate(20260718, Game.difficulty)
	grid = meta["grid"]
	loot_cells = meta["loot_cells"]

	# 4) GroundView unter WorldRoot einhaengen, dann bauen — VOR dem Pathfinder:
	#    Scenery3D markiert Palmen-Zellen als unbegehbar (Objekt-Kollision), und
	#    der Pathfinder muss diese Sperren beim Bau bereits sehen.
	ground = GroundView3D.new()
	ground.name = "GroundView"
	_world_root.add_child(ground)
	ground.build(grid)

	# 5) Pathfinder ueber dem Grid (inkl. Palmen-Sperren aus Scenery3D).
	pathfinder = Pathfinder3D.new()
	pathfinder.build(grid)

	# 6) Vision (Gitter-LOS) ueber dem Grid.
	vision = Tac3DVision.new()
	vision.grid = grid

	# 7) KI, verdrahtet auf diesen Orchestrator (ctl UNTYPED, Zyklus-Falle).
	ai = Tac3DAI.new()
	ai.setup(self)

	# 8) Kamera-Rig auf Feldgrenzen, Fokus auf die Merc-Landezone.
	rig.setup(grid.bounds_world())
	var mspawns: Array = meta["merc_spawns"]
	if not mspawns.is_empty():
		rig.focus_world(grid.cell_to_world(mspawns[0]))

	# 9) Picker (nutzt die Rig-Kamera).
	picker = Picker3D.new()
	picker.grid = grid
	picker.cam = rig.cam

	# 10) Licht/Environment (additiv, damit spaetere GLB-Bodies nicht schwarz sind).
	_setup_lighting()

	# 11) Einheiten: Soeldner (Game.team) + Gegner (MapGen.enemy_spawns).
	_spawn_units()

	# 12) Erst-Sicht + Startauswahl.
	compute_vision()
	if not mercs.is_empty():
		selected = mercs[0]

	# 12b) Interaktiver Aufbau NUR im Nicht-Bot-Modus (Regression: fast => hud/cursor bleiben null).
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
		# FIX F3: Juice-Aufbau ans ENDE des not-fast-Blocks (NACH picker.set_active_level,
		# NICHT nach hud.build) -> disjunkt von Phase 3. Im Bot bleibt juice==null.
		juice = Juice3D.new()
		juice.name = "Juice"
		_world_root.add_child(juice)
		juice.setup(grid, rig)

	# 12c) Phase 7 â€” Erkundungs-Musik (gebacken, fallback-sicher). Nur not fast (Bot rein).
	if not fast:
		Sfx.play_music("exploration")

	# 13) battle_ready DEFERRED (Fix Â§10.9): Harness await'et nach add_child.
	battle_ready.emit.call_deferred()


func _spawn_units() -> void:
	var mspawns: Array = meta["merc_spawns"]
	for i in Game.team.size():
		var start: Vector3i = mspawns[i % mspawns.size()]
		var u := Tac3DUnit.new()
		u.fast = fast
		_units_root.add_child(u)
		u.setup_combat(grid, Game.team[i], true, start)
		# Merc-home bleibt Vector3i.ZERO (Leash 9999 -> irrelevant, wie v2).
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
	_spawn_otto()


## Phase 7 â€” Otto als Gefangener (captive). is_merc=true -> Swat-Modell (ohne tac3d_unit/
## assets3d anzufassen), aber NICHT in mercs/units/enemies: keine KI, kein Ziel, keine
## Sieg-/Niederlage-Zaehlung. Belegt seine Zelle (Pathfinder-Block), grau bis befreit.
func _spawn_otto() -> void:
	if not meta.has("otto_spawn"):
		return
	var u := Tac3DUnit.new()
	u.fast = fast
	_units_root.add_child(u)
	u.setup_combat(grid, Db.otto_runtime(), true, meta["otto_spawn"])
	u.home = meta["otto_spawn"]
	u.set_tint(Color(0.65, 0.62, 0.55))   # "gefangen"-Grau, bis befreit (dann Merc-Blau)
	_occupy(u, u.cell)
	captive = u
	# NICHT in mercs/units/enemies! (keine KI, kein Ziel, keine Sieg-/Niederlage-Zaehlung)


# 1:1 aus tactical.gd:148-160 â€” frisches Enemy-Runtime-Dict. duplicate(true), damit die
# geteilte const-Dictionary NICHT mutiert wird (marks += marks_mod).
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
	# In 3D sind nur begehbare Zellen ueberhaupt AStar-Punkte; Entsperren stellt die
	# Begehbarkeit wieder her (die Zelle war begehbar, sonst haette dort niemand gestanden).
	pathfinder.set_cell_blocked(c, false)


func dl(t: float) -> void:
	if fast:
		return
	await get_tree().create_timer(t).timeout


## Warme Tropen-Sonne + Himmel/Environment (ART-PASS). Additiv, fallback-sicher.
## Schatten nur wenn NICHT fast (Headless/Bot brauchen keine Schattenkarte).
func _setup_lighting() -> void:
	# --- Sonne: leicht gelblicher Vormittag, sichtbarer Schattenwurf. ---
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# Politur: Sonne tiefer (-55 -> -45 Grad) = laengere Spaetnachmittag-Schatten.
	# Energie 1.15 -> 1.33 kompensiert den flacheren Einfall auf dem Boden
	# (sin55*1.15 ~ sin45*1.33), sonst kippt die pixelgetunte Art-Pass-Belichtung.
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-40.0), 0.0)
	sun.light_color = Color(1.0, 0.91, 0.74)   # warmes, spaetes Sonnenlicht
	sun.light_energy = 1.33
	if not fast:
		sun.shadow_enabled = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		# 72x72-Feld -> Schattenreichweite hoch, Acne Ã¼ber Bias/Normal-Bias zÃ¤hmen.
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
	sky_mat.sky_top_color = Color(0.22, 0.44, 0.80)       # tieferes Zenit-Blau -> Kontrast
	sky_mat.sky_horizon_color = Color(0.82, 0.80, 0.70)   # warmer, dunstiger Horizont
	sky_mat.sky_energy_multiplier = 1.0
	sky_mat.ground_bottom_color = Color(0.42, 0.40, 0.34) # warmer Sand-/Erdton
	sky_mat.ground_horizon_color = Color(0.74, 0.72, 0.64)
	sky_mat.sun_angle_max = 30.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky

	# Ambient aus dem Himmel -> Schattenpartien bleiben farbig statt tot-schwarz.
	# ART-PASS T7b: Ambient deutlich gesenkt (1.0->0.45), damit die Sonne die Szene
	# modelliert (Schattenkontrast) statt sie flach zu fluten und helle Texturen
	# (Wand/Sand) ins Weiss zu blasen.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 0.6
	e.ambient_light_energy = 0.35

	# Filmischer Tonemap. ART-PASS v2 T9: Exposure 0.9->0.74. Pixel-Messung zeigte
	# Strand bei 255/255/211 (R,G ausgebrannt) UND Wiese bei ~233/246 (nah am Clip,
	# ins Gelbliche gewaschen) -> die ganze Pipeline war zu heiss. Tieferes Exposure
	# holt den Strand aus dem Clip (echter Sand-Ton) und macht die Wiese satter/gruener.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.74
	e.tonemap_white = 1.0

	# Politur: Glow/Bloom — seit Godot 4.3 auch im gl_compatibility-Renderer.
	# Threshold 1.0 = nur echte HDR-Spitzen bluehen auf (Muendungsblitz-/
	# Explosions-Licht auf Flaechen, Sonnenglitzer) — die Grundszene bleibt
	# unangetastet, kein Milchglas-Wash.
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

	# Farb-Boost fuer satte Tropenfarben (jetzt nicht mehr vom Ambient gewaschen).
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.12
	e.adjustment_saturation = 1.22
	e.adjustment_brightness = 1.02

	# Warmer Luftdunst fuer Tiefe. gl_compatibility rendert einfachen (nicht-
	# volumetrischen) Tiefen-Fog.
	# ART-PASS v2 T8: KRITISCH â€” die Ortho-Kamera sitzt 200 Einheiten hinter dem
	# Pivot (camera_rig cam.position.z=200), also liegt JEDE Geometrie bei ~200
	# Tiefe. Bei density 0.008 ergibt das 1-exp(-0.008*200)=~80 % Fog UEBERALL ->
	# die ganze Szene ertrinkt in einer gelben Milch (kein Tiefen-Cue, nur Wash).
	# density 0.0009 -> ~1-exp(-0.18)=~16 % dezenter Grunddunst, ferne Kartenteile
	# minimal staerker -> Atmosphaere statt Milchglas, echte Tropenfarben bleiben.
	e.fog_enabled = true
	e.fog_light_color = Color(0.82, 0.80, 0.70)
	e.fog_density = 0.0009
	e.fog_sky_affect = 0.0

	env.environment = e
	add_child(env)


# ================================================================= Inventar-Helfer (1:1)

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


# ================================================================= Kampfwerte (1:1)

func shot_ap(u, aim := 0) -> int:
	return int(Db.weapon(u.data["weapon"])["ap"]) + int(Db.AIM["ap_step"]) * aim


## Erfahrungsstufe (1â€“6): Soeldner steigen ueber Abschuesse auf, Gegner sind fix.
func level_of(u) -> int:
	if u.is_merc:
		return mini(6, int(u.data.get("exp", 1)) + int(u.data.get("kills", 0)) / 2)
	return int(u.data.get("exp", 1))


# Port tactical.gd:477-490 + Hoehenbonus (spec Â§6.2). Distanz FLACH auf (x,z).
func hit_chance(att, def, aim := 0) -> int:
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
	# Feuer nach unten trifft besser: +8 je Ebene Hoehenvorteil.
	ch += HEIGHT_HIT_BONUS * maxf(0.0, float(att.cell.y - def.cell.y))
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


# ================================================================= Pfad / AP

# Bewegungskosten der ZIEL-Kachel je Move-Typ (MOVE_AP.get, Fallback 2).
func step_ap(to: Vector3i) -> int:
	var t: Tac3DTile = grid.get_tile(to)
	if t == null:
		return 2
	return MOVE_AP.get(t.move_type, 2)


func path_ap(cells: Array) -> int:
	var c := 0
	for i in range(1, cells.size()):
		var to: Vector3i = cells[i]
		c += step_ap(to)
	return c


# Port tactical.gd:453-464 â€” Kosten je Schritt via step_ap.
func prefix_for_ap(cells: Array, ap: int) -> Array:
	var out: Array = []
	if cells.is_empty():
		return out
	out.append(cells[0])
	var c := 0
	for i in range(1, cells.size()):
		var to: Vector3i = cells[i]
		c += step_ap(to)
		if c > ap:
			break
		out.append(to)
	return out


# Port tactical.gd:416-422 â€” entsperrt u.cell (Guard pathfinder3d.gd:64), Pfad, wieder sperren.
func path_for(u, target: Vector3i) -> Array:
	if not grid.is_walkable(target) or occupied.has(target):
		return []
	pathfinder.set_cell_blocked(u.cell, false)
	var p := pathfinder.path_cells(u.cell, target)
	pathfinder.set_cell_blocked(u.cell, true)
	return p


# Port tactical.gd:424-442 â€” Nachbarfallback (4er-/8er-Umkreis, flach).
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


# ================================================================= Sicht / Anmarsch

# K2: pro ZIELZELLE testen (KEINE Nachbarschafts-Vorfuellung). Fuer jeden lebenden Merc
# vision.unit_sees(merc, enemy.cell) ueber ALLE lebenden Gegner (echtes y), danach set_seen.
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
			if vision.unit_sees(merc, enemy.cell):
				visible_cells[enemy.cell] = true
	for e in enemies:
		var enemy2: Tac3DUnit = e
		enemy2.set_seen(enemy2.alive and visible_cells.has(enemy2.cell))


func unit_sees(u, c: Vector3i) -> bool:
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


## Erster Feindkontakt: Anmarschphase endet, Rundenkampf beginnt.
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
		hud.banner("FEINDKONTAKT â€” Rundenkampf!")
	# Phase 7 â€” Kampf-Sting + Kampfmusik (nur not fast, fallback-sicher).
	if not fast:
		Sfx.play("interrupt", -2.0)
		Sfx.play_music("combat")
	_hud_refresh()


## 2 Runden ohne Sichtkontakt: zurueck in den Erkundungsmodus.
func _end_combat_mode() -> void:
	combat_started = false
	no_contact_rounds = 0
	for m in mercs:
		var merc: Tac3DUnit = m
		merc.ap = merc.ap_max
	# Phase 7 â€” zurueck zur Erkundungs-Musik.
	if not fast:
		Sfx.play_music("exploration")
	_hud_refresh()


## Laerm/Sichtung: alarmiert Gegner in Hoerweite um `center` (flach).
func alert_enemies(investigate: Vector3i, center: Vector3i, radius: float) -> void:
	noise_at = investigate
	for e in enemies:
		var en: Tac3DUnit = e
		if en.alive and Tac3DVision.flat(en.cell).distance_to(Tac3DVision.flat(center)) <= radius:
			en.data["alerted"] = true


## Wachposten-Leine: Boss klebt (2), Eliten am Anwesen (5), Miliz jagt frei (9999). Flach.
func _leash_for(u) -> float:
	if u == boss:
		return 2.0
	if not u.is_merc and String(u.data.get("type", "")).begins_with("elite"):
		return 5.0
	return 9999.0


# ================================================================= Aktionen (Coroutinen)

# Port tactical.gd:513-590 â€” AP, Leine, Unterbrechungen, Kontakt, Ebenen-Bewegung.
func do_move(u, cells: Array) -> void:
	if cells.size() < 2 or battle_over:
		return
	busy = true
	# Beine laufen waehrend der Bewegung. do_move hat eine EIGENE Schritt-Schleife und nutzt
	# follow_path (das sonst "walk" spielt) NICHT -> hier explizit, sonst gleitet die Idle-Pose.
	if not fast:
		u.play_anim("walk")
	var observers: Dictionary = {}
	var watchers: Array = enemies if u.is_merc else mercs
	for o in watchers:
		var ow: Tac3DUnit = o
		observers[ow] = ow.alive and unit_sees(ow, u.cell)
	var seen_before := visible_enemies().size()
	for i in range(1, cells.size()):
		if battle_over or not u.alive:
			break
		var to: Vector3i = cells[i]
		# Wachposten-Leine (Boss: Thronsaal, Eliten: Anwesen). Flach.
		if Tac3DVision.flat(to).distance_to(Tac3DVision.flat(u.home)) > _leash_for(u):
			break
		var cst := step_ap(to)
		if u.ap < cst or occupied.has(to):
			break
		u.ap -= cst
		_vacate(u.cell)
		u.cell = to
		_occupy(u, to)
		if fast:
			u.set_cell(to)
		else:
			var wp := grid.cell_to_world(to) + Vector3(0.0, Unit3D.MODEL_Y_OFFSET, 0.0)
			# #1: Figur dreht sich in Laufrichtung (weich via Unit3D._process).
			u.face_toward(wp)
			# Politur: Schritt-Sound nach Untergrund (2D-Muster tactical.gd) — auch fuer
			# UNSICHTBARE Gegner (Laerm ist JA-typische Information). Staub dagegen NUR
			# fuer sichtbare Einheiten, sonst verraten Partikel versteckte Positionen.
			var st: Tac3DTile = grid.get_tile(to)
			if st != null and st.surface <= 2:
				Sfx.play_step(["grass", "wood", "stone"][st.surface])
			if juice != null and st != null and u.seen and not st.is_water():
				juice.dust_puff(grid.cell_to_world(to))
			var tw := create_tween()
			tw.tween_property(u, "position", wp, 0.11)
			await tw.finished
		compute_vision()
		# Anmarschphase endet beim ersten Sichtkontakt.
		var contact_now := false
		if not combat_started and u.is_merc and _any_contact():
			contact_now = true
			start_combat()
		# Unterbrechungen: neu ins Sichtfeld getretene Beobachter feuern (Erfahrungschance).
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
		if u.is_merc and visible_enemies().size() > seen_before:
			if await check_boss_dialog():
				break
			break
		if u.is_merc:
			if await check_boss_dialog():
				break
	if not fast and u.alive:
		u.play_anim("idle")   # Bewegung zu Ende -> zurueck in die Ruhepose (nicht bei Tod/Hit)
	if u.is_merc and not combat_started:
		u.ap = u.ap_max   # Anmarsch: Bewegung kostet nichts
	busy = false
	compute_vision()
	_hud_refresh()


# Port tactical.gd:592-652 â€” Schaden/Schrot/Armor/Hoehe. Distanz FLACH.
func shoot(att, def, interrupt := false) -> bool:
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
	# Phase 5: Schuetze feuert sichtbar. Eigener not-fast-Block (unabhaengig vom Juice-Objekt);
	# play_anim ist null-/Fallback-sicher (No-Op ohne AnimationPlayer bzw. bei Kapsel).
	if not fast:
		att.face_toward(grid.cell_to_world(def.cell))
		att.play_anim("shoot")
	var investigate: Vector3i = att.cell if att.is_merc else def.cell
	alert_enemies(investigate, att.cell, 9.0)
	if not att.is_merc:
		att.data["alerted"] = true
	if att.is_merc:
		Game.stats["shots"] = int(Game.stats["shots"]) + 1
	var ch := hit_chance(att, def, aim)
	var hit := randi_range(1, 100) <= ch
	# --- Phase 4 (Juice): Schuss-FX, trefferunabhaengig. Gegated (fast/null). ---
	if not fast and juice != null:
		var from_w: Vector3 = att.global_position + Vector3.UP * 1.3
		var to_w: Vector3 = def.global_position + Vector3.UP * 1.1
		var flat_dir: Vector3 = def.global_position - att.global_position
		flat_dir.y = 0.0
		flat_dir = flat_dir.normalized() if flat_dir.length() > 0.001 else Vector3.FORWARD
		var muzzle: Vector3 = from_w + flat_dir * 0.45
		juice.muzzle_flash(muzzle, flat_dir)
		juice.tracer(muzzle, to_w)
		# Politur: Huelse fliegt raus (Bodenhoehe der Schuetzen-Zelle, Flinte = rot).
		juice.shell_casing(muzzle, flat_dir, grid.cell_to_world(att.cell).y, bool(w["shotgun"]))
		rig.add_trauma(Juice3D.TRAUMA_SHOT)
		Sfx.play(String(w["snd"]), 2.0 if bool(w["shotgun"]) else 1.0)
	await dl(0.13)
	if hit:
		if att.is_merc:
			Game.stats["hits"] = int(Game.stats["hits"]) + 1
		var dist: float = att.flat().distance_to(def.flat())
		var dmg := int(w["dmg"]) + randi_range(-int(w["var"]), int(w["var"]))
		if bool(w["shotgun"]) and dist > 3.0:
			dmg -= int((dist - 3.0) * 4.0)
		dmg = int(float(dmg) * (1.0 - float(def.data["armor"])))
		dmg = maxi(1, dmg)
		def.hurt(dmg)
		# --- Phase 4 (Juice): Treffer-FX. hitstop fire-and-forget (NIE awaiten). ---
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


## #3 (neu): Freier Schuss in eine ZELLE ohne Ziel-Einheit (Boden / Suppression). Verbraucht
## Schuss-AP + Munition, macht KEINEN Schaden. Juice (Muendungsfeuer/Leuchtspur) wie shoot().
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
	alert_enemies(cell, att.cell, 9.0)   # Laerm zieht Gegner an (wie ein echter Schuss)
	if not fast and juice != null:
		var from_w: Vector3 = att.global_position + Vector3.UP * 1.3
		var to_w: Vector3 = to_cell + Vector3.UP * 0.2
		var flat_dir: Vector3 = to_cell - att.global_position
		flat_dir.y = 0.0
		flat_dir = flat_dir.normalized() if flat_dir.length() > 0.001 else Vector3.FORWARD
		var muzzle: Vector3 = from_w + flat_dir * 0.45
		juice.muzzle_flash(muzzle, flat_dir)
		juice.tracer(muzzle, to_w)
		# Politur: Huelse fliegt raus (Bodenhoehe der Schuetzen-Zelle, Flinte = rot).
		juice.shell_casing(muzzle, flat_dir, grid.cell_to_world(att.cell).y, bool(w["shotgun"]))
		rig.add_trauma(Juice3D.TRAUMA_SHOT)
		Sfx.play(String(w["snd"]), 2.0 if bool(w["shotgun"]) else 1.0)
	await dl(0.13)
	_refund_if_exploring(att)   # in der Anmarschphase kostenfrei (wie Bewegung)


func _can_reload(u) -> bool:
	if not u.is_merc:
		return true
	return mags_for(u) > 0


# Port tactical.gd:659-674.
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


# Port tactical.gd:676-703 â€” heilt schlimmsten Nachbarn (flach). heal = 15 + med/4.
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


# Port tactical.gd:705-723 â€” Handwaffe tauschen (SWAP_AP), Munition zwischenspeichern.
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
	_refund_if_exploring(u)
	_hud_refresh()


# Port tactical.gd:725-795 â€” Radius flach; W1: FLAG_DESTRUCT wirkt NUR auf begehbare
# Deckungs-Kacheln (cover>0) -> cover=0 (keine Wand-Zerstoerung, Pathfinder3D-sicher).
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
	# Ausholen: die Granate loest sich erst am Ende der Armbewegung aus der Hand.
	await dl(0.35)
	# --- Sichtbare Granate fliegt im Bogen zur Zielkachel (Juice, gegated). ---
	if not fast and juice != null:
		var hand: Vector3 = u.global_position + Vector3.UP * 1.5
		var flight: float = juice.grenade_throw(hand, grid.cell_to_world(c) + Vector3.UP * 0.15)
		await dl(flight)
	# --- Phase 4 (Juice): Explosions-FX beim Einschlag. Gegated. ---
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
			# --- Phase 4 (Juice): Schadenszahl + Blut je Opfer. Gegated. ---
			if not fast and juice != null:
				juice.damage_number(ot.global_position + Vector3.UP * 2.0, dmg, not ot.alive)
				juice.blood(ot.global_position + Vector3.UP * 1.1, grid.cell_to_world(ot.cell))
			if not ot.alive:
				await on_death(u, ot)
			if battle_over:
				break
	# W1: Deckungs-Zerstoerung nur auf begehbaren FLAG_DESTRUCT-Kacheln mit cover>0.
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


## Erkundungsmodus: Aktionen kosten nichts â€” AP sofort auffuellen.
func _refund_if_exploring(u) -> void:
	if not combat_started and u.is_merc:
		u.ap = u.ap_max


## Durchsuchen: Kisten (FLAG_DESTRUCT-Deckung) und gefallene Gegner (JA1-Looting).
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


# Port tactical.gd:815-852 â€” Kiste/Leiche, SEARCH_AP, Db.roll_loot.
func do_search(u, c: Vector3i) -> void:
	var kind := search_target_at(c)
	if kind == "" or u.flat().distance_to(Tac3DVision.flat(c)) > 1.6 or u.ap < Db.SEARCH_AP:
		return
	u.ap -= Db.SEARCH_AP
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
		var cal := String(Db.weapon(e.data["weapon"])["cal"])
		var r := loot_rng.randf()
		if r < 0.4:
			found.append(_mag_item_for(cal))
		elif r < 0.55:
			found.append("granate")
	for id in found:
		if inv_add(u, String(id)):
			Game.stats["loot"] = int(Game.stats["loot"]) + 1
		else:
			break
	_refund_if_exploring(u)
	_hud_refresh()


# Port tactical.gd:854-895 â€” XP/Stufenaufstieg, Boss, Sieg/Niederlage.
func on_death(killer, dead) -> void:
	dead.die_visual()
	# --- Phase 4 (Juice): Tod-Reaktion (Anim + Trauma + Schmerzlaut). Gegated. ---
	if not fast and juice != null:
		dead.play_anim("death")
		rig.add_trauma(Juice3D.TRAUMA_KILL)
		rig.kill_zoom_punch()   # Politur: kurzer Zoom-Kick zum Kill (nach dem Hitstop)
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
		if dead == boss:
			await _boss_defeated()
			return
		var left := false
		for e in enemies:
			var en: Tac3DUnit = e
			if en.alive:
				left = true
				break
		if not left:
			await end_battle("victory")


# Port tactical.gd:897-913 â€” Boss faellt, restliche Miliz ergibt sich, Sieg.
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
	await end_battle("victory")


# Port tactical.gd:915-925.
func end_battle(result: String) -> void:
	if battle_over:
		return
	battle_over = true
	busy = false
	Game.mission_result = result
	Game.stats["turns"] = turn
	# FIX F2: time_scale ist prozessglobal. Vor dem goto/Szenenwechsel hart auf 1.0
	# zuruecksetzen (Guertel-und-Hosentraeger gegen einen Hitstop-Leak in den Endscreen).
	Engine.time_scale = 1.0
	await dl(1.0)
	battle_finished.emit(result)
	if not fast:
		_main().call_deferred("goto", "end")


# ================================================================= Boss-Dialog (nur LOGIK)

# Port tactical.gd:929-940 â€” Sichtung -> alert -> Game.boss_dialog_seen. UI = spaeterer
# Strang; im fast/Headless terminiert v2 mit `if fast: return true`. Hier immer LOGIK+return.
func check_boss_dialog() -> bool:
	if Game.boss_dialog_seen or battle_over or boss == null or not boss.alive:
		return false
	if not visible_cells.has(boss.cell):
		return false
	Game.boss_dialog_seen = true
	boss.data["alerted"] = true
	alert_enemies(_nearest_merc_cell(boss.cell), boss.cell, 9.0)
	# Phase 7 â€” modaler Vargo-Dialog (nur not fast + hud). boss_dialog_seen steht davor
	# -> genau einmal, auch bei mehreren await check_boss_dialog()-Aufrufstellen.
	if not fast and hud != null:
		await hud.show_boss_dialog()
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


# ================================================================= Feindphase / Runde

# Port tactical.gd:1061-1101 â€” Feindphase (ai.act je Gegner), Rundenwechsel, Erkundungs-Reset.
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
		for e in enemies:
			var en2: Tac3DUnit = e
			en2.ap = en2.ap_max
			en2.interrupt_used = false
		player_turn = true
		compute_vision()
		await check_boss_dialog()
		# 2 Runden ohne Sichtkontakt -> zurueck in den Erkundungsmodus.
		if _any_contact():
			no_contact_rounds = 0
		else:
			no_contact_rounds += 1
		if no_contact_rounds >= 2:
			_end_combat_mode()
	busy = false
	_hud_refresh()


# ================================================================= Smoke-Bot

# Port tactical.gd:1947-2010 â€” Bot spielt bis Sieg/Abbruch. Coroutine.
func auto_battle() -> String:
	var outer := 0
	while not battle_over and outer < 300:
		outer += 1
		if outer % 10 == 0:
			var left := 0
			for e in enemies:
				if e.alive:
					left += 1
			print("SMOKE3D: Runde %d â€” Gegner uebrig: %d" % [turn, left])
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


# ================================================================= Interaktiv (HUD/Maus)

## Null-geschuetzte Refresh-Huelle. Im fast/Bot-Modus ist hud==null -> No-Op (Regression).
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
	if selected == u:
		ui_inventory()   # Klick auf gewaehlten Soeldner oeffnet das Inventar (JA1)
		return
	selected = u
	mode = "move"
	# Phase 7 â€” Auswahl-Spruch (Otto=walross via _voice_id; sonst <id>_select). Nur not fast.
	if not fast:
		Sfx.play_voice(_voice_id(u) + "_select")
	if picker != null:
		picker.set_active_level(u.cell.y)   # Klicks/Hover auf der Ebene des Soeldners aufloesen
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
	aim_level = (aim_level + 1) % (int(Db.AIM["max"]) + 1)
	_hud_refresh()


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
			hud.banner("Noch kein Feindkontakt")
		return
	await end_turn()
	_hud_refresh()


func ui_inventory() -> void:
	if hud != null:
		hud.toggle_inventory()


func ui_menu() -> void:
	if hud != null:
		hud.toggle_pause()


# ================================================================= Phase 7: Otto / Basis / Audio

## Stimm-ID: Otto traegt "voice"="walross" -> walross_*; alle anderen fallen auf ihre id
## zurueck (kein "voice"-Feld). Fuer _select/_pain-Clips.
func _voice_id(u) -> String:
	return String(u.data.get("voice", u.data.get("id", "")))


## Interaktion (Taste F): befreit Otto NUR aus dem Keller (K1: Etagengleichheit +
## flach-adjazent). Von der Dorfoberflaeche aus (andere Ebene) unmoeglich.
func ui_interact() -> void:
	if not _can_act() or captive == null:
		return
	if selected.cell.y == captive.cell.y and selected.flat().distance_to(captive.flat()) <= 1.6:
		await free_otto()
	elif hud != null:
		hud.banner("Kein Ziel zum Interagieren in Reichweite.")


## Befreiung = der Kern-Story-Beat. FIX W2: rebuild_slots() SOFORT nach mercs/units.append,
## DAVOR KEIN _hud_refresh()/compute_vision() (sonst OOB in refresh, mercs > _slots).
func free_otto() -> void:
	if captive == null or battle_over:
		return
	var otto := captive
	captive = null                       # Reentrancy-Guard: nur einmal
	otto.set_tint(otto.team_color())     # -> Merc-Blau
	otto.ap = otto.ap_max
	mercs.append(otto)
	units.append(otto)
	if hud != null:
		hud.rebuild_slots()              # W2: Portrait-Spalten neu (jetzt 5), VOR jedem refresh
	Game.team.append(otto.data)          # umgeht bewusst TEAM_MAX (5. Mitglied)
	Game.otto_freed = true
	Game.base_unlocked = true
	if not fast:
		Sfx.play_voice(_voice_id(otto) + "_select")   # walross_select
	if hud != null:
		hud.banner("OTTO Â»BÃ„RÂ« BRANDT BEFREIT â€” Der Unterschlupf ist unser.", 2.0)
	compute_vision()
	_hud_refresh()
	if not fast and hud != null:
		await hud.show_base_panel()       # Heimatbasis-Menue (K3)


## Basis-Aktion (K3): Trupp voll heilen. Nur hp_max, keine Formel-Aenderung.
func base_heal_all() -> void:
	for m in mercs:
		var u: Tac3DUnit = m
		u.data["hp"] = u.hp_max()
	_hud_refresh()


## Basis-Aktion (K3): Nachschub. Handwaffe voll + Taschen mit Magazinen bis Db.INV_SLOTS.
## Ganzzahlarithmetik unberuehrt (nur mag/cal), keine Treffer-/AP-Formel angefasst.
func base_resupply_all() -> void:
	for m in mercs:
		var u: Tac3DUnit = m
		u.data["ammo"] = int(Db.weapon(u.data["weapon"])["mag"])
		var cal := String(Db.weapon(u.data["weapon"])["cal"])
		while inv_of(u).size() < Db.INV_SLOTS:
			inv_of(u).append("mag_" + cal)
	_hud_refresh()


func _unhandled_input(ev) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		# Kamera-Drehung bleibt immer verfuegbar (auch nach Kampfende).
		if ev.keycode == KEY_Q:
			if rig != null:
				rig.rotate_step(-1)
			return
		if ev.keycode == KEY_E:
			if rig != null:
				rig.rotate_step(1)
			return
		# W1: modales Panel (Vargo-Dialog/Basis) offen -> Aktions-Hotkeys schlucken.
		if hud != null and hud.modal_active:
			return
		if battle_over:   # FIX M5: Aktions-Tasten nach Kampfende sperren.
			return
		match ev.keycode:
			KEY_TAB:
				_cycle_merc()
			KEY_R:
				ui_reload()
			KEY_Z:
				ui_aim()
			KEY_G:
				ui_grenade_mode()
			KEY_H:
				ui_medkit()
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
			MOUSE_BUTTON_RIGHT:
				if not battle_over and mode == "grenade":
					mode = "move"
					_hud_refresh()


# FIX C2: busy=true VOR await shoot, busy=false DANACH -> kein Doppelschuss bei Doppelklick.
func _handle_click() -> void:
	if busy or battle_over or picker == null or selected == null:
		return
	var target := picker.cell_under_mouse(get_viewport())
	if target == Picker3D.NONE:
		return
	if mode == "grenade":
		await do_grenade(selected, target)   # setzt intern mode="move"
		_hud_refresh()
		return
	var tgt: Tac3DUnit = occupied.get(target, null)
	# Phase 7 â€” Captive-Klick VOR dem Merc-Zweig (Otto ist is_merc=true, wuerde sonst
	# faelschlich per ui_select ausgewaehlt). K1: nur bei Etagengleichheit + flach-adjazent.
	if captive != null and tgt == captive:
		if selected.alive and selected.cell.y == captive.cell.y \
		   and selected.flat().distance_to(captive.flat()) <= 1.6:
			await free_otto()
		elif hud != null:
			hud.banner("NÃ¤her an Otto heran (in den Keller absteigen).")
		return
	# #3 (neu): Strg gehalten = FREIES ZIELEN. Auf JEDE Einheit (auch eigene -> Friendly Fire
	# ist ausdruecklich erlaubt) ODER in den Boden schiessen. Muss VOR Merc-Auswahl/Move stehen.
	if Input.is_key_pressed(KEY_CTRL) and selected.alive and (captive == null or selected != captive):
		if tgt != null and tgt.alive and tgt != selected and tgt != captive:
			if vision.los(selected.cell, tgt.cell):
				busy = true
				await shoot(selected, tgt)   # shoot prueft KEIN Team -> Friendly Fire moeglich
				busy = false
				_hud_refresh()
			elif hud != null:
				hud.banner("Keine Sichtlinie zum Ziel.")
			return
		busy = true
		await shoot_ground(selected, target)   # Boden-/Suppressionsschuss (kein Schaden)
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
	if search_target_at(target) != "" and selected.flat().distance_to(Tac3DVision.flat(target)) <= 1.6:
		do_search(selected, target)
		_hud_refresh()
		return
	var cells := path_for(selected, target)
	if cells.size() > 1:
		# #2: In der Anmarsch-/Ruhephase zieht auf Wunsch die GANZE Gruppe zum Ziel
		# (Umschalt/Shift gehalten). Im Rundenkampf bleibt es einzeln (AP-gebunden).
		if not combat_started and Input.is_key_pressed(KEY_SHIFT):
			await _squad_move(target)
		else:
			var pref: Array = cells if not combat_started else prefix_for_ap(cells, selected.ap)
			await do_move(selected, pref)
		_hud_refresh()


## #2: Anmarsch-/Ruhephase — die ganze Gruppe zieht zum Ziel. Jeder Soeldner sucht sich
## eine freie Zelle nahe dem Klickpunkt und laeuft nacheinander dorthin. Bricht ab, sobald
## Feindkontakt den Rundenkampf startet (dann uebernimmt die AP-gebundene Einzelsteuerung).
func _squad_move(target: Vector3i) -> void:
	var living: Array = []
	for m in mercs:
		var mu: Tac3DUnit = m
		if mu.alive:
			living.append(mu)
	# Naechste am Ziel zuerst -> natuerlichere Formation, weniger Umsortieren.
	living.sort_custom(func(a, b):
		return Tac3DVision.flat(a.cell).distance_to(Tac3DVision.flat(target)) \
			< Tac3DVision.flat(b.cell).distance_to(Tac3DVision.flat(target)))
	var claimed: Dictionary = {}
	for m in living:
		if combat_started:
			break   # Feindkontakt -> Gruppenzug beenden, Rundenkampf laeuft
		var mu: Tac3DUnit = m
		var dest := _free_near(target, claimed, mu)
		claimed[dest] = true
		var cells := path_for(mu, dest)
		if cells.size() > 1:
			selected = mu   # HUD/Kamera folgen dem gerade ziehenden Soeldner (ohne Spruch)
			await do_move(mu, cells)


## Freie, begehbare Zelle nahe `target` (nicht belegt, nicht schon `claimed`). Ringsuche.
func _free_near(target: Vector3i, claimed: Dictionary, u) -> Vector3i:
	if not occupied.has(target) and not claimed.has(target) and path_for(u, target).size() > 1:
		return target
	for radius in range(1, 6):
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if abs(dx) != radius and abs(dz) != radius:
					continue   # nur den aeusseren Ring dieses Radius pruefen
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


# Hover-Feedback (3D-Cursor + HUD-Tooltip). Nutzt vorhandene Kampf-Helfer, mutiert nichts.
func _update_hover() -> void:
	if cursor == null or hud == null:
		return
	# FIX M3: Maus ausserhalb des Gitters -> alles ausblenden.
	if hover_cell == Picker3D.NONE:
		cursor.clear()
		hud.hide_cursor()
		return
	if selected == null:
		cursor.clear()
		hud.hide_cursor()
		return
	# FIX M4: Screen-Koordinaten der Maus (CanvasLayer ist kamera-unabhaengig).
	var mpos := get_viewport().get_mouse_position()
	if mode == "grenade":
		var ok := grenade_valid(selected, hover_cell)
		cursor.show_grenade(selected.cell, hover_cell, float(Db.GRENADE["radius"]), ok)
		if ok:
			hud.set_cursor("Granate werfen: %d AP Â· Radius %.1f" % [int(Db.GRENADE["ap"]), float(Db.GRENADE["radius"])], mpos)
		else:
			hud.set_cursor("AuÃŸer Reichweite", mpos)
		return
	# Phase 7 â€” Otto-Hover (K1: Befreien nur bei Etagengleichheit + flach-adjazent).
	if captive != null and hover_cell == captive.cell:
		cursor.show_target(hover_cell, "search")
		if selected.cell.y == captive.cell.y and selected.flat().distance_to(captive.flat()) <= 1.6:
			hud.set_cursor("Otto befreien [F]", mpos)
		else:
			hud.set_cursor("Otto â€” in den Keller absteigen", mpos)
		return
	var tgt: Tac3DUnit = occupied.get(hover_cell, null)
	if tgt != null and not tgt.is_merc and tgt.alive and tgt.seen:
		var los := vision.los(selected.cell, tgt.cell)
		cursor.show_target(hover_cell, "shoot" if los else "block")
		if los:
			hud.set_cursor("%s â€” Treffer: %d %% Â· %d AP" % [String(tgt.data["name"]), hit_chance(selected, tgt, aim_level), shot_ap(selected, aim_level)], mpos)
		else:
			hud.set_cursor("Keine Schusslinie", mpos)
		return
	if search_target_at(hover_cell) != "":
		cursor.show_target(hover_cell, "search")
		if combat_started:
			hud.set_cursor("Durchsuchen: %d AP" % Db.SEARCH_AP, mpos)
		else:
			hud.set_cursor("Durchsuchen (frei)", mpos)
		return
	hover_path = path_for(selected, hover_cell)
	if hover_path.size() > 1:
		var afford: int = prefix_for_ap(hover_path, selected.ap).size()
		cursor.show_path(hover_path, afford)
		cursor.show_target(hover_cell, "move")
		if not combat_started:
			hud.set_cursor("Anmarsch: frei", mpos)
		else:
			var cost := path_ap(hover_path)
			if cost <= selected.ap:
				hud.set_cursor("Laufen: %d AP" % cost, mpos)
			else:
				hud.set_cursor("%d AP (nur %d mÃ¶glich)" % [cost, maxi(0, afford - 1)], mpos)
	else:
		cursor.clear()
		hud.hide_cursor()


func _process(dt: float) -> void:
	if rig == null:
		return
	# Mittelmaus-Ziehen = Karte scrollen (Frame-Delta der Mausposition).
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
	# FIX M5: Hover nur im spielbaren Zustand (nicht nach Kampfende / in Feindphase / busy).
	if hud != null and picker != null and selected != null and not busy and player_turn and not battle_over:
		var c := picker.cell_under_mouse(get_viewport())
		if c != hover_cell:
			hover_cell = c
			_update_hover()

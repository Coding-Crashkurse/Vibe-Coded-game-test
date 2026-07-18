class_name Tac3DMapGen
extends RefCounted
## 3D-Kampfkartengenerator (~72x72) im Geist von MapGen (spec §4):
##   Landezone Sued (Ebene 0) · Fluss mit Bruecke (Deck Ebene 1 ueber Wasser Ebene 0)
##   Dorf (Gebaeude) · Huegel/Anwesen (Ebene 1 via Rampe) · Deckungs-/Loot-Kacheln.
## Datengetrieben wie MapGen.ENEMY_SPAWNS. Reichweiten/Distanzen laufen flach auf (x,z);
## die Ebene (y) traegt nur Hoehenboni + Ebenen-Links (Bruecke/Rampe).
##
## Wichtige Geometrie:
##   z waechst nach SUEDEN. Merc-Landezone z~68 (Sued). Fluss z=39..41 (voller Breite),
##   z=40 = WATER_DEEP (Mitte, nur SWIM), z=39/z=41 = WATER_SHALLOW (Ufer, WADE).
##   => Bei SWIM aus ist die tiefe Mittelreihe die einzige Sperre: die Ufer sind
##      Sackgassen, die einzige Querung ist die BRUECKE (Deck Ebene 1, x=34..37).
##   Anwesen im Norden (z~3..14) auf Ebene 1, Boss auf BOSS_HOME=(58,1,8),
##   Zugang ueber eine RAMP (Ebene 1) mit add_link zur Ebene-0-Wiese davor.

const SIZE := 72
const RIVER_Z0 := 39           # Fluss-Band z=39..41
const RIVER_MID := 40          # tiefe Mitte
const RIVER_Z1 := 41
const BRIDGE_X0 := 34          # Bruecke ueberspannt x=34..37
const BRIDGE_X1 := 37

# Landezone Sued, weit weg (neutraler Spawn, spec §14.3)
const MERC_SPAWNS := [
	Vector3i(6, 0, 68), Vector3i(7, 0, 68),
	Vector3i(6, 0, 69), Vector3i(7, 0, 69),
]
# Anwesen, Ebene 1
const BOSS_HOME := Vector3i(58, 1, 8)

# diff-Tags exakt wie MapGen: "all" (10, inkl. boss) + "normal" (3) + "hard" (4).
# Summe je Grad: leicht 10 · normal 13 · schwer 17 (== Db.DIFFICULTY[diff]["enemies"]).
# Cluster im Dorf (z~24..46) + Vorposten suedlich des Flusses (z~44..46), damit der
# Bot vom Sued-Spawn in wenigen Runden Kontakt bekommt (Kritik M3).
const ENEMY_SPAWNS := [
	# --- all (10) -------------------------------------------------------
	# Vorposten SUEDLICH des Flusses (gleiches Ufer wie die Mercs → schneller Kontakt)
	{"cell": Vector3i(30, 0, 45), "type": "miliz_p9", "diff": "all"},
	{"cell": Vector3i(40, 0, 44), "type": "miliz_p9", "diff": "all"},
	{"cell": Vector3i(35, 0, 46), "type": "miliz_flinte", "diff": "all"},
	# Dorf (noerdlich des Flusses)
	{"cell": Vector3i(28, 0, 34), "type": "miliz_p9", "diff": "all"},
	{"cell": Vector3i(44, 0, 32), "type": "miliz_k45", "diff": "all"},
	{"cell": Vector3i(20, 0, 30), "type": "miliz_p9", "diff": "all"},
	# Anwesen-Vorfeld (Ebene 0 vor der Rampe)
	{"cell": Vector3i(54, 0, 16), "type": "elite", "diff": "all"},
	{"cell": Vector3i(62, 0, 16), "type": "elite_flinte", "diff": "all"},
	{"cell": Vector3i(58, 0, 18), "type": "elite", "diff": "all"},
	# Boss im Anwesen (Ebene 1)
	{"cell": Vector3i(58, 1, 8), "type": "boss", "diff": "all"},
	# --- normal (+3) ----------------------------------------------------
	{"cell": Vector3i(24, 0, 36), "type": "miliz_p9", "diff": "normal"},
	{"cell": Vector3i(48, 0, 36), "type": "miliz_k45", "diff": "normal"},
	{"cell": Vector3i(36, 0, 30), "type": "miliz_p9", "diff": "normal"},
	# --- hard (+4) ------------------------------------------------------
	{"cell": Vector3i(16, 0, 28), "type": "miliz_p9", "diff": "hard"},
	{"cell": Vector3i(52, 0, 30), "type": "miliz_k45", "diff": "hard"},
	{"cell": Vector3i(30, 0, 24), "type": "miliz_p9", "diff": "hard"},
	{"cell": Vector3i(46, 0, 26), "type": "miliz_flinte", "diff": "hard"},
]

# Dorf-Gebaeude: {x0, z0, w, h, door} (Ebene 0). Bewusst so gesetzt, dass sie WEDER
# den Brueckenausgang (x=34..37, z=38/42) NOCH einen Gegner-/Merc-Spawn ueberdecken.
const VILLAGE_BUILDINGS := [
	{"x0": 10, "z0": 20, "w": 6, "h": 5, "door": Vector3i(12, 0, 24)},
	{"x0": 50, "z0": 20, "w": 7, "h": 6, "door": Vector3i(53, 0, 25)},
	{"x0": 14, "z0": 32, "w": 6, "h": 5, "door": Vector3i(16, 0, 36)},
	{"x0": 40, "z0": 34, "w": 6, "h": 5, "door": Vector3i(42, 0, 38)},
]

# Deterministische Deckungs-/Loot-Kacheln (begehbar, cover>0, FLAG_DESTRUCT) in offenem
# Gelaende — kollidieren nicht mit Gebaeuden oder Spawns (>= 5 fuer Smoke K4).
const COVER_CELLS := [
	Vector3i(22, 0, 50), Vector3i(40, 0, 50), Vector3i(55, 0, 50),
	Vector3i(28, 0, 44), Vector3i(44, 0, 44), Vector3i(18, 0, 34),
	Vector3i(58, 0, 30), Vector3i(24, 0, 20),
]


static func generate(seed: int, difficulty: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var g := Grid3D.new()
	_fill_ground(g, rng)
	_carve_river(g)
	var bridge_cells: Array = _build_bridge(g)

	for b in VILLAGE_BUILDINGS:
		var bd: Dictionary = b
		_building(g, int(bd["x0"]), int(bd["z0"]), int(bd["w"]), int(bd["h"]), bd["door"])

	_hill_estate(g)

	var loot_cells: Array = []
	_scatter_cover(g, rng, loot_cells)
	_keller(g)

	var enemy_spawns: Array = _filter_spawns(difficulty)

	# Sicherheitspass: jeder Spawn MUSS begehbar sein (Smoke K2). Ebene-0-Spawns auf
	# GROUND zwingen, falls ein Bauteil versehentlich darauf landete; Boss (Ebene 1)
	# bleibt Anwesen-FLOOR.
	for sp in MERC_SPAWNS:
		var mc: Vector3i = sp
		if not g.is_walkable(mc):
			g.set_tile(mc, Tac3DTile.make(Tac3DTile.Kind.GROUND, 0))
	for es in enemy_spawns:
		var ec: Vector3i = es["cell"]
		if ec.y == 0 and not g.is_walkable(ec):
			g.set_tile(ec, Tac3DTile.make(Tac3DTile.Kind.GROUND, 0))
	if not g.is_walkable(BOSS_HOME):
		g.set_tile(BOSS_HOME, Tac3DTile.make(Tac3DTile.Kind.FLOOR, 1))

	return {
		"grid": g,
		"pathfinder_ready": false,
		"merc_spawns": MERC_SPAWNS,
		"enemy_spawns": enemy_spawns,
		"boss_home": BOSS_HOME,
		"loot_cells": loot_cells,
		"goal": BOSS_HOME,
		# Schwimmen-unter-der-Bruecke: von der Suedreihe (z=41) zur Nordreihe (z=39)
		# MUSS die tiefe Mitte z=40 gequert werden → Pfad enthaelt WATER_DEEP (Smoke K7).
		"swim_from": Vector3i(35, 0, RIVER_Z1),
		"swim_to": Vector3i(35, 0, RIVER_Z0),
		# tiefes Wasser unter dem Deck vs. Deck darueber (Smoke K6).
		"deep_under_deck": Vector3i(35, 0, RIVER_MID),
		"deck_over_deep": Vector3i(35, 1, RIVER_MID),
		"bridge_cells": bridge_cells,
	}


# ------------------------------------------------------------------ Bauhelfer

## 72x72 GROUND auf Ebene 0.
static func _fill_ground(g: Grid3D, _rng: RandomNumberGenerator) -> void:
	for z in range(SIZE):
		for x in range(SIZE):
			g.set_tile(Vector3i(x, 0, z), Tac3DTile.make(Tac3DTile.Kind.GROUND, 0))


## Fluss (voller Breite): z=39/z=41 WATER_SHALLOW (Ufer, WADE), z=40 WATER_DEEP (Mitte,
## nur SWIM). Bei SWIM aus sperrt die tiefe Mittelreihe die Querung komplett — die Ufer
## werden Sackgassen, einzige Querung ist die Bruecke.
static func _carve_river(g: Grid3D) -> void:
	for x in range(SIZE):
		g.set_tile(Vector3i(x, 0, RIVER_Z0), Tac3DTile.make(Tac3DTile.Kind.WATER_SHALLOW, 0))
		g.set_tile(Vector3i(x, 0, RIVER_MID), Tac3DTile.make(Tac3DTile.Kind.WATER_DEEP, 0))
		g.set_tile(Vector3i(x, 0, RIVER_Z1), Tac3DTile.make(Tac3DTile.Kind.WATER_SHALLOW, 0))


## Bruecken-Deck (Ebene 1, x=34..37, z=39..41) ueber dem Wasser. Links verbinden die
## Nord-/Sued-Deckkante mit dem jeweiligen Ufer auf Ebene 0. Rueckgabe: alle Deck-Zellen.
static func _build_bridge(g: Grid3D) -> Array:
	var cells: Array = []
	for x in range(BRIDGE_X0, BRIDGE_X1 + 1):
		for z in range(RIVER_Z0, RIVER_Z1 + 1):
			var c := Vector3i(x, 1, z)
			g.set_tile(c, Tac3DTile.make(Tac3DTile.Kind.BRIDGE, 1))
			cells.append(c)
	# Ebenen-Links zu beiden Ufern (z=38 Nord, z=42 Sued sind GROUND Ebene 0).
	for x in range(BRIDGE_X0, BRIDGE_X1 + 1):
		g.add_link(Vector3i(x, 1, RIVER_Z0), Vector3i(x, 0, RIVER_Z0 - 1))  # Nordufer
		g.add_link(Vector3i(x, 1, RIVER_Z1), Vector3i(x, 0, RIVER_Z1 + 1))  # Suedufer
	return cells


## Dorf-Gebaeude: WALL-Ring (Ebene 0, blockt Sicht + unbegehbar) + FLOOR innen + DOOR-Luecke.
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
	# Tuer: begehbare FLOOR-Luecke in der Wand.
	g.set_tile(door, Tac3DTile.make(Tac3DTile.Kind.FLOOR, 0))


## Huegel/Anwesen im Norden auf Ebene 1: FLOOR-Innenraum + WALL-Ring (mit Tuer im Sueden)
## + RAMP (Ebene 1) mit add_link zur Ebene-0-Wiese davor. Boss steht auf BOSS_HOME.
static func _hill_estate(g: Grid3D) -> void:
	# Innenraum (Ebene 1): x=52..64, z=4..13.
	for z in range(4, 14):
		for x in range(52, 65):
			g.set_tile(Vector3i(x, 1, z), Tac3DTile.make(Tac3DTile.Kind.FLOOR, 1))
	# Wandring (Ebene 1): Nord z=3, Sued z=14, West x=51, Ost x=65.
	for x in range(51, 66):
		g.set_tile(Vector3i(x, 1, 3), Tac3DTile.make(Tac3DTile.Kind.WALL, 1))
		g.set_tile(Vector3i(x, 1, 14), Tac3DTile.make(Tac3DTile.Kind.WALL, 1))
	for z in range(3, 15):
		g.set_tile(Vector3i(51, 1, z), Tac3DTile.make(Tac3DTile.Kind.WALL, 1))
		g.set_tile(Vector3i(65, 1, z), Tac3DTile.make(Tac3DTile.Kind.WALL, 1))
	# Tuer (Sued, x=57/58): FLOOR-Luecke in der Wand z=14.
	g.set_tile(Vector3i(57, 1, 14), Tac3DTile.make(Tac3DTile.Kind.FLOOR, 1))
	g.set_tile(Vector3i(58, 1, 14), Tac3DTile.make(Tac3DTile.Kind.FLOOR, 1))
	# Rampe (Ebene 1, z=15) vor der Tuer + Link hinab zur Wiese (Ebene 0, z=16).
	for x in [57, 58]:
		g.set_tile(Vector3i(x, 1, 15), Tac3DTile.make(Tac3DTile.Kind.RAMP, 1))
		g.add_link(Vector3i(x, 1, 15), Vector3i(x, 0, 16))
	# Boss-Standplatz sicher als FLOOR.
	g.set_tile(BOSS_HOME, Tac3DTile.make(Tac3DTile.Kind.FLOOR, 1))


## Deckungs-Kacheln (begehbar, cover 0.25, FLAG_DESTRUCT) + Loot-Zellen.
static func _scatter_cover(g: Grid3D, _rng: RandomNumberGenerator, loot_out: Array) -> void:
	for cc in COVER_CELLS:
		var c: Vector3i = cc
		var t := Tac3DTile.make(Tac3DTile.Kind.GROUND, 0)
		t.cover = 0.25
		t.flags = t.flags | Tac3DTile.FLAG_DESTRUCT
		g.set_tile(c, t)
		loot_out.append(c)


## Optionaler Keller (Ebene -1) unter dem Anwesen als Andockpunkt (spec §6.2).
## Kleiner FLOOR-Raum, per Link an den Anwesen-Boden angebunden (Sackgasse, kein Shortcut).
static func _keller(g: Grid3D) -> void:
	for z in range(6, 11):
		for x in range(56, 61):
			g.set_tile(Vector3i(x, -1, z), Tac3DTile.make(Tac3DTile.Kind.FLOOR, -1))
	g.add_link(Vector3i(58, -1, 6), Vector3i(58, 1, 6))


## diff-Filter exakt wie MapGen.generate: all/normal/hard + LEICHT-Downgrade elite→miliz.
## Liefert frische Dicts (const-Array bleibt unangetastet).
static func _filter_spawns(difficulty: String) -> Array:
	var spawns: Array = []
	for es in ENEMY_SPAWNS:
		var tag := String(es["diff"])
		if tag == "all":
			spawns.append({"cell": es["cell"], "type": es["type"], "diff": es["diff"]})
		elif tag == "normal" and difficulty != "leicht":
			spawns.append({"cell": es["cell"], "type": es["type"], "diff": es["diff"]})
		elif tag == "hard" and difficulty == "schwer":
			spawns.append({"cell": es["cell"], "type": es["type"], "diff": es["diff"]})
	# LEICHT: keine Elitewachen im Einstiegssektor — normale Miliz uebernimmt die Posten.
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

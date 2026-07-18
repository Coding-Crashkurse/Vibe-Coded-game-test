class_name MapGen
extends RefCounted
## Erzeugt Sektor 43 »Silberquell« (40×28) im JA1-Look:
## Wände werden als DÜNNE Striche in den Boden gebacken (Läufe/Ecken/T-Stücke),
## Innenräume mit Holzdielen sichtbar, Türen als Holzschwellen, Fenster als Glasstriche.
##
## Legende:
##  . Gras   , Erdweg   ~ Wasser   T Baum   t Busch   r Fels
##  # Hauswand (Creme-Mauerwerk)   M Anwesen-Mauer (Stein)   W Fenster   D Tür
##  w Holzboden   s Steinboden   C Teppich   c Kiste (lootbar, zerstörbar)   S Sandsack   O Brunnen

const W := 40
const H := 28
const TILE := 64

const MAP := [
	".T..T.....................MMMMMMMMMMMMM.",
	"...T......................MsMssCCCssMsM.",
	"..........................MsMssCCCssMsM.",
	"..........................MsMsssssssMsM.",
	"..........................MsMMMMDMMMMsM.",
	"..........................MsssssssssscM.",
	"..~~~~~...t...............MssSssssSsssM.",
	"..~~~~~...................McssssssssssM.",
	"..~~~~~...................MMWMM,,MMWMMM.",
	"..~~~~~........................,,....T..",
	"..T.......r....................,,.......",
	"..............######...........,,.......",
	".............c#wwwc#,,,,,,,,,,,,,.......",
	"......#######.##D###,,..................",
	"......#wwwww#.......,,..####.....r......",
	"......#wwwwwD.......,,..Dww#............",
	"......#######.......,,.O####............",
	".............##D####,,.........####.....",
	".............#wwwww#,,.........#wc#.....",
	".............#wwwwwD,,...r.....Dww#.....",
	".............#######,,..c........c......",
	".....t.............S,,S.................",
	"........TTTT........,,..................",
	"........TT..........,,...c..............",
	"....................,,........t.........",
	"....................,,..................",
	".......T............,,..................",
	"T.T.T...............,,..........T.T.....",
]

const FURNITURE := [
	{"name": "bed_top", "cell": Vector2i(29, 1)},
	{"name": "bed_low", "cell": Vector2i(29, 2)},
	{"name": "stove", "cell": Vector2i(35, 1)},
	{"name": "chair_1", "cell": Vector2i(30, 1)},
	{"name": "chair_2", "cell": Vector2i(34, 1)},
	{"name": "table_round", "cell": Vector2i(30, 3)},
	{"name": "pool_l", "cell": Vector2i(33, 3)},
	{"name": "pool_m", "cell": Vector2i(34, 3)},
	{"name": "pool_r", "cell": Vector2i(35, 3)},
	{"name": "sofa_l", "cell": Vector2i(16, 18)},
	{"name": "sofa_m", "cell": Vector2i(17, 18)},
	{"name": "sofa_r", "cell": Vector2i(18, 18)},
	{"name": "bed_top", "cell": Vector2i(7, 14)},
	{"name": "bed_low", "cell": Vector2i(7, 15)},
	{"name": "stove", "cell": Vector2i(11, 14)},
]

## diff: "all" = immer · "normal" = ab NORMAL · "hard" = nur SCHWER
const ENEMY_SPAWNS := [
	{"cell": Vector2i(10, 15), "type": "miliz_p9", "diff": "all"},
	{"cell": Vector2i(17, 12), "type": "miliz_p9", "diff": "all"},
	{"cell": Vector2i(16, 19), "type": "miliz_flinte", "diff": "all"},
	{"cell": Vector2i(25, 15), "type": "miliz_p9", "diff": "all"},
	{"cell": Vector2i(20, 13), "type": "miliz_k45", "diff": "all"},
	{"cell": Vector2i(9, 11), "type": "miliz_p9", "diff": "all"},
	{"cell": Vector2i(30, 6), "type": "elite", "diff": "all"},
	{"cell": Vector2i(35, 6), "type": "elite_flinte", "diff": "all"},
	{"cell": Vector2i(32, 5), "type": "elite", "diff": "all"},
	{"cell": Vector2i(32, 2), "type": "boss", "diff": "all"},
	{"cell": Vector2i(22, 16), "type": "miliz_p9", "diff": "normal"},
	{"cell": Vector2i(20, 20), "type": "miliz_k45", "diff": "normal"},
	{"cell": Vector2i(32, 18), "type": "miliz_p9", "diff": "normal"},
	{"cell": Vector2i(14, 8), "type": "miliz_p9", "diff": "hard"},
	{"cell": Vector2i(27, 20), "type": "miliz_k45", "diff": "hard"},
	{"cell": Vector2i(11, 10), "type": "miliz_p9", "diff": "hard"},
	{"cell": Vector2i(36, 12), "type": "miliz_flinte", "diff": "hard"},
]

# Landezone: neutrale Südwest-Wiese hinter dem Waldriegel
const MERC_SPAWNS := [Vector2i(3, 24), Vector2i(4, 24), Vector2i(3, 25), Vector2i(4, 25)]
const BOSS_HOME := Vector2i(32, 2)

static func _assets() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("Assets")

static func idx(c: Vector2i) -> int:
	return c.y * W + c.x

static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < W and c.y >= 0 and c.y < H

static func char_at(x: int, y: int) -> String:
	if x < 0 or y < 0 or x >= W or y >= H:
		return "."
	return MAP[y][x]

static func _in_estate(x: int, y: int) -> bool:
	return x >= 26 and x <= 38 and y <= 8

static func _wall_like(ch: String) -> bool:
	return ch == "#" or ch == "M" or ch == "W" or ch == "D"

static func generate(rng_seed: int, difficulty: String = "normal") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var A := _assets()

	assert(MAP.size() == H)
	for row in MAP:
		assert(row.length() == W)

	var walk: Array[bool] = []
	var sight: Array[bool] = []
	var cover: Array[float] = []
	var destruct: Array[bool] = []
	var surface: Array[int] = []   # 0 Gras/Erde · 1 Holz · 2 Stein (für Schrittgeräusche)
	walk.resize(W * H)
	sight.resize(W * H)
	cover.resize(W * H)
	destruct.resize(W * H)
	surface.resize(W * H)

	var props: Array = []
	var loot_cells: Array = []
	var ground_img := Image.create_empty(W * TILE, H * TILE, false, Image.FORMAT_RGBA8)
	var src_cache := {}

	for y in H:
		for x in W:
			var ch := char_at(x, y)
			var i := y * W + x
			walk[i] = true
			sight[i] = true
			cover[i] = 0.0
			destruct[i] = false
			var ground := ""
			match ch:
				".":
					ground = _pick(rng, ["grass_1", "grass_1", "grass_1", "grass_2", "grass_2", "grass_3", "grass_4"])
				",":
					ground = _pick(rng, ["dirt_1", "dirt_1", "dirt_2"])
				"~":
					ground = _pick(rng, ["water_1", "water_2"])
					walk[i] = false
				"w":
					ground = _pick(rng, ["floor_wood_1", "floor_wood_1", "floor_wood_2", "floor_wood_3"])
				"s":
					ground = _pick(rng, ["floor_stone_1", "floor_stone_1", "floor_stone_2", "floor_stone_3"])
				"C":
					ground = "carpet_2"
				"#", "M":
					ground = _wall_underlay(x, y)
					walk[i] = false
					sight[i] = false
				"W":
					ground = _wall_underlay(x, y)
					walk[i] = false
					cover[i] = 0.1
				"D":
					ground = "floor_stone_1" if _in_estate(x, y) else _pick(rng, ["floor_wood_1", "floor_wood_2"])
				"T":
					ground = _pick(rng, ["grass_1", "grass_2"])
					walk[i] = false
					sight[i] = false
					var tname := "tree_side_1" if rng.randf() < 0.8 else "tree_side_2"
					props.append({"name": tname, "cell": Vector2i(x, y), "rot": 0.0, "mod": Color(1, 1, 1), "scale": rng.randf_range(0.95, 1.15)})
				"t":
					ground = _pick(rng, ["grass_1", "grass_2"])
					walk[i] = false
					cover[i] = 0.25
					props.append({"name": "bush", "cell": Vector2i(x, y), "rot": rng.randf_range(0, TAU), "mod": Color(1, 1, 1), "scale": 1.0})
				"r":
					ground = _pick(rng, ["grass_1", "grass_3"])
					walk[i] = false
					cover[i] = 0.25
					props.append({"name": _pick(rng, ["rock_1", "rock_2", "rock_3"]), "cell": Vector2i(x, y), "rot": rng.randf_range(0, TAU), "mod": Color(1, 1, 1), "scale": 1.0})
				"c":
					if _in_estate(x, y):
						ground = "floor_stone_1"
					elif char_at(x, y) == "c" and (char_at(x - 1, y) == "w" or char_at(x + 1, y) == "w" or char_at(x, y - 1) == "w" or char_at(x, y + 1) == "w"):
						ground = "floor_wood_1"
					else:
						ground = _pick(rng, ["grass_1", "dirt_1"])
					walk[i] = false
					cover[i] = 0.25
					destruct[i] = true
					loot_cells.append(Vector2i(x, y))
					props.append({"name": _pick(rng, ["crate_1", "crate_1", "crate_1", "crate_2", "crate_o", "crate_big"]), "cell": Vector2i(x, y), "rot": 0.0, "mod": Color(1, 1, 1), "scale": 1.0})
				"S":
					ground = "floor_stone_1" if _in_estate(x, y) else "grass_1"
					walk[i] = false
					cover[i] = 0.25
					props.append({"name": "sandbag", "cell": Vector2i(x, y), "rot": 0.0, "mod": Color(0.93, 0.87, 0.65), "scale": 1.0})
				"O":
					ground = "grass_1"
					walk[i] = false
					cover[i] = 0.25
					props.append({"name": "well", "cell": Vector2i(x, y), "rot": 0.0, "mod": Color(1, 1, 1), "scale": 1.0})
				_:
					ground = "grass_1"
			if ch == "w" or (ch == "D" and not _in_estate(x, y)):
				surface[i] = 1
			elif ch == "s" or ch == "C" or (ch == "D" and _in_estate(x, y)):
				surface[i] = 2
			else:
				surface[i] = 0
			_blit(ground_img, src_cache, A, ground, x, y)

	# JA1-Look: dünne Wände, Fenster, Türschwellen in den Boden backen
	for y in H:
		for x in W:
			var ch := char_at(x, y)
			if ch == "#" or ch == "M":
				_bake_wall(ground_img, x, y, ch == "M")
			elif ch == "W":
				_bake_window(ground_img, x, y)
			elif ch == "D":
				_bake_door(ground_img, x, y)

	# Möbel
	for f in FURNITURE:
		var c: Vector2i = f["cell"]
		var i2 := idx(c)
		walk[i2] = false
		cover[i2] = 0.25
		props.append({"name": f["name"], "cell": c, "rot": 0.0, "mod": Color(1, 1, 1), "scale": 1.0})

	# Gegner nach Schwierigkeit
	var spawns: Array = []
	for es in ENEMY_SPAWNS:
		var tag := String(es["diff"])
		if tag == "all":
			spawns.append(es)
		elif tag == "normal" and difficulty != "leicht":
			spawns.append(es)
		elif tag == "hard" and difficulty == "schwer":
			spawns.append(es)
	# LEICHT: keine Elitewachen im Einstiegssektor — normale Miliz übernimmt die Posten
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

	return {
		"w": W, "h": H,
		"walk": walk, "sight": sight, "cover": cover, "destruct": destruct, "surface": surface,
		"ground": ImageTexture.create_from_image(ground_img),
		"props": props,
		"loot_cells": loot_cells,
		"merc_spawns": MERC_SPAWNS,
		"enemy_spawns": spawns,
		"boss_home": BOSS_HOME,
	}

# ------------------------------------------------------------------ intern

static func _wall_underlay(x: int, y: int) -> String:
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		if char_at(x + d.x, y + d.y) == "w":
			return "floor_wood_1"
	if _in_estate(x, y):
		return "floor_stone_1"
	return "grass_1"

static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	return arr[rng.randi_range(0, arr.size() - 1)]

static func _blit(dst: Image, cache: Dictionary, A: Node, name: String, x: int, y: int) -> void:
	if not cache.has(name):
		var img: Image = A.tex(name).get_image()
		if img == null:
			return
		if img.get_format() != Image.FORMAT_RGBA8:
			img = img.duplicate()
			img.convert(Image.FORMAT_RGBA8)
		cache[name] = img
	var src: Image = cache[name]
	dst.blit_rect(src, Rect2i(0, 0, TILE, TILE), Vector2i(x * TILE, y * TILE))

## Dünner Wandstrich mit Verbindungsarmen (Läufe, Ecken, T-Stücke)
static func _bake_wall(img: Image, x: int, y: int, stone: bool) -> void:
	var outer := Color(0.30, 0.26, 0.18)
	var inner := Color(0.92, 0.88, 0.78)
	if stone:
		outer = Color(0.22, 0.24, 0.28)
		inner = Color(0.64, 0.68, 0.74)
	var px := x * TILE
	var py := y * TILE
	var l := _wall_like(char_at(x - 1, y))
	var r := _wall_like(char_at(x + 1, y))
	var u := _wall_like(char_at(x, y - 1))
	var d := _wall_like(char_at(x, y + 1))
	if not (l or r or u or d):
		r = true
		l = true
	for pass_i in 2:
		var t := 20 if pass_i == 0 else 12
		var col := outer if pass_i == 0 else inner
		var h0 := 32 - t / 2
		img.fill_rect(Rect2i(px + h0, py + h0, t, t), col)
		if l:
			img.fill_rect(Rect2i(px, py + h0, 32 + t / 2, t), col)
		if r:
			img.fill_rect(Rect2i(px + h0, py + h0, TILE - h0, t), col)
		if u:
			img.fill_rect(Rect2i(px + h0, py, t, 32 + t / 2), col)
		if d:
			img.fill_rect(Rect2i(px + h0, py + h0, t, TILE - h0), col)
	# 3/4-Look: sichtbare Wandfront nach Süden + weicher Bodenschatten
	if not _wall_like(char_at(x, y + 1)):
		var fl := px if l else px + 22
		var fr := (px + TILE) if r else px + 42
		var facec := Color(0.79, 0.73, 0.60) if not stone else Color(0.44, 0.47, 0.54)
		var faced := Color(0.60, 0.54, 0.42) if not stone else Color(0.30, 0.32, 0.38)
		img.fill_rect(Rect2i(fl, py + 42, fr - fl, 12), facec)
		img.fill_rect(Rect2i(fl, py + 52, fr - fl, 4), faced)
		img.fill_rect(Rect2i(fl, py + 56, fr - fl, 6), Color(0, 0, 0, 0.20))

## Fenster: Wandarme + Glasstrich quer
static func _bake_window(img: Image, x: int, y: int) -> void:
	_bake_wall(img, x, y, true)
	var px := x * TILE
	var py := y * TILE
	var l := _wall_like(char_at(x - 1, y))
	var r := _wall_like(char_at(x + 1, y))
	var glass := Color(0.66, 0.85, 0.95)
	var frame := Color(0.2, 0.22, 0.26)
	if l or r:
		img.fill_rect(Rect2i(px + 2, py + 27, TILE - 4, 10), frame)
		img.fill_rect(Rect2i(px + 4, py + 29, TILE - 8, 6), glass)
	else:
		img.fill_rect(Rect2i(px + 27, py + 2, 10, TILE - 4), frame)
		img.fill_rect(Rect2i(px + 29, py + 4, 6, TILE - 8), glass)

## Tür: Holzschwelle in der Wandlücke (begehbar)
static func _bake_door(img: Image, x: int, y: int) -> void:
	var px := x * TILE
	var py := y * TILE
	var wood := Color(0.45, 0.30, 0.16)
	var wood2 := Color(0.58, 0.40, 0.22)
	var l := _wall_like(char_at(x - 1, y))
	var r := _wall_like(char_at(x + 1, y))
	if l or r:
		img.fill_rect(Rect2i(px, py + 26, TILE, 12), wood)
		img.fill_rect(Rect2i(px + 3, py + 29, TILE - 6, 6), wood2)
	else:
		img.fill_rect(Rect2i(px + 26, py, 12, TILE), wood)
		img.fill_rect(Rect2i(px + 29, py + 3, 6, TILE - 6), wood2)

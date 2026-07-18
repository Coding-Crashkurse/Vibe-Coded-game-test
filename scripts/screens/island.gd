extends Control
## Inselkarte im JA1-Stil: Sektorraster über der Insel, Zielsektor markiert,
## unteres Panel mit TEAM / GELD / TAG / SEKTOR / EINSATZ.

const MAP_W := 1160
const MAP_H := 620
const COLS := 8
const ROWS := 6
const TARGET := Vector2i(2, 5)   # Spalte 2, Reihe 5 → Sektor 43
const GRID_ORIGIN := Vector2i(60, 30)
const CELL := Vector2i(130, 93)

var _hint: Label

func _main() -> Node:
	return get_parent()

func _sector_number(c: Vector2i) -> int:
	return c.y * COLS + c.x + 1

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 8)
	add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiTheme.hspace(16))
	head.add_child(UiTheme.header("INSEL SILBAROS — SEKTORKARTE", 30))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_hint = UiTheme.lbl("Zielsektor 43 ist markiert. Andere Sektoren sind in der Demo gesperrt.", 14, UiTheme.COL_DIM)
	head.add_child(_hint)
	head.add_child(UiTheme.hspace(16))

	# Karte
	var center := CenterContainer.new()
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(center)
	var map_rect := TextureRect.new()
	map_rect.texture = _build_map_texture()
	map_rect.stretch_mode = TextureRect.STRETCH_KEEP
	map_rect.gui_input.connect(_on_map_input)
	center.add_child(map_rect)

	# Unteres JA1-Panel
	var bottom := PanelContainer.new()
	v.add_child(bottom)
	var bh := HBoxContainer.new()
	bh.add_theme_constant_override("separation", 12)
	bottom.add_child(bh)

	var obj := VBoxContainer.new()
	obj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(obj)
	obj.add_child(UiTheme.lbl("AUFTRAG", 13, UiTheme.COL_DIM))
	obj.add_child(UiTheme.lbl("Dorf Silberquell befreien — »General« Vargo eliminieren.", 15))
	var nicks: Array = []
	for m in Game.team:
		nicks.append("»%s«" % m["nick"])
	obj.add_child(UiTheme.lbl("Einsatzteam: " + ", ".join(nicks), 14, UiTheme.COL_AMBER))

	bh.add_child(_info_box("TEAM", "%d / %d" % [Game.team.size(), Game.TEAM_MAX]))
	bh.add_child(_info_box("GELD", "%d $" % Game.budget))
	bh.add_child(_info_box("TAG", "1"))
	bh.add_child(_info_box("SCHWIERIGKEIT", String(Game.diff()["name"])))
	bh.add_child(_info_box("SEKTOR", str(_sector_number(TARGET))))

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	bh.add_child(actions)
	var go := UiTheme.btn("EINSATZ  ▸", func() -> void: _main().goto("loading"), 20)
	go.custom_minimum_size = Vector2(200, 46)
	actions.add_child(go)
	actions.add_child(UiTheme.btn("◂  Anheuern", func() -> void: _main().goto("hire"), 13))

func _info_box(title: String, value: String) -> PanelContainer:
	var p := PanelContainer.new()
	var iv := VBoxContainer.new()
	p.add_child(iv)
	var t := UiTheme.lbl(title, 12, UiTheme.COL_DIM)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(t)
	var val := UiTheme.lbl(value, 20, UiTheme.COL_AMBER)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	iv.add_child(val)
	return p

func _on_map_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = ev.position
		var cx := int(floor((p.x - GRID_ORIGIN.x) / CELL.x))
		var cy := int(floor((p.y - GRID_ORIGIN.y) / CELL.y))
		if cx < 0 or cy < 0 or cx >= COLS or cy >= ROWS:
			return
		if Vector2i(cx, cy) == TARGET:
			Sfx.play("ui_confirm")
			_main().goto("loading")
		else:
			Sfx.play("ui_error")
			_hint.text = "Sektor %d ist in der Demo nicht verfügbar — Ziel ist Sektor %d." % [_sector_number(Vector2i(cx, cy)), _sector_number(TARGET)]
			_hint.add_theme_color_override("font_color", UiTheme.COL_RED)

# ------------------------------------------------------------------ Inselbild

const ISLES := [
	[580.0, 330.0, 340.0, 190.0],
	[350.0, 220.0, 160.0, 115.0],
	[800.0, 250.0, 170.0, 120.0],
	[700.0, 450.0, 190.0, 125.0],
	[420.0, 470.0, 150.0, 95.0],
	[320.0, 540.0, 110.0, 70.0],
	[1010.0, 150.0, 75.0, 55.0],
]

func _is_land(px: float, py: float, grow := 0.0) -> bool:
	for e in ISLES:
		var dx := (px - float(e[0])) / (float(e[2]) + grow)
		var dy := (py - float(e[1])) / (float(e[3]) + grow)
		if dx * dx + dy * dy <= 1.0:
			return true
	return false

func _build_map_texture() -> Texture2D:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4311
	var img := Image.create_empty(MAP_W, MAP_H, false, Image.FORMAT_RGBA8)
	var ocean := Color(0.11, 0.23, 0.36)
	var ocean2 := Color(0.13, 0.27, 0.42)
	var sand := Color(0.78, 0.70, 0.46)
	var green := Color(0.29, 0.46, 0.23)
	var green2 := Color(0.24, 0.4, 0.19)
	# Ozean mit Wellen-Struktur
	img.fill(ocean)
	for i in 900:
		var x := rng.randi_range(0, MAP_W - 8)
		var y := rng.randi_range(0, MAP_H - 2)
		img.fill_rect(Rect2i(x, y, rng.randi_range(3, 8), 1), ocean2)
	# Insel: erst Sand (größer), dann Grün
	for y in MAP_H:
		for x in MAP_W:
			if _is_land(x, y, 14.0):
				img.set_pixel(x, y, sand)
	for y in MAP_H:
		for x in MAP_W:
			if _is_land(x, y, 0.0):
				img.set_pixel(x, y, green if ((x / 7 + y / 7) % 2 == 0) else green2)
	# Wald-Flecken
	for i in 260:
		var x := rng.randi_range(20, MAP_W - 20)
		var y := rng.randi_range(20, MAP_H - 20)
		if _is_land(x, y, -8.0):
			img.fill_rect(Rect2i(x, y, rng.randi_range(3, 7), rng.randi_range(2, 5)), Color(0.16, 0.3, 0.13))
	# Sektorraster
	var grid_col := Color(0, 0, 0, 0.32)
	for c in COLS + 1:
		var gx := GRID_ORIGIN.x + c * CELL.x
		img.fill_rect(Rect2i(gx, GRID_ORIGIN.y, 2, ROWS * CELL.y), grid_col)
	for r in ROWS + 1:
		var gy := GRID_ORIGIN.y + r * CELL.y
		img.fill_rect(Rect2i(GRID_ORIGIN.x, gy, COLS * CELL.x, 2), grid_col)
	# Feindpräsenz-Punkte (Flavor) + Zielsektor-Markierung
	for r in ROWS:
		for c in COLS:
			var cellpos := GRID_ORIGIN + Vector2i(c * CELL.x, r * CELL.y)
			var cx := cellpos.x + CELL.x / 2
			var cy := cellpos.y + CELL.y / 2
			if not _is_land(cx, cy):
				continue
			if Vector2i(c, r) == TARGET:
				continue
			if rng.randf() < 0.55:
				var n := rng.randi_range(2, 6)
				for k in n:
					img.fill_rect(Rect2i(cellpos.x + 8 + k * 9, cellpos.y + 8, 6, 6), Color(0.05, 0.05, 0.05))
	# Zielsektor: ECHTE Vorschau der Sektorkarte (die Taktikkarte im Kleinformat)
	var t := GRID_ORIGIN + Vector2i(TARGET.x * CELL.x, TARGET.y * CELL.y)
	var ms := 3
	var off := t + Vector2i((CELL.x - MapGen.W * ms) / 2, (CELL.y - MapGen.H * ms) / 2)
	for my in MapGen.H:
		for mx in MapGen.W:
			img.fill_rect(Rect2i(off.x + mx * ms, off.y + my * ms, ms, ms), _mini_color(MapGen.char_at(mx, my), mx, my))
	# Weißer Rahmen (JA1-Stil)
	var wcol := Color(0.97, 0.97, 0.95)
	img.fill_rect(Rect2i(t.x, t.y, CELL.x, 3), wcol)
	img.fill_rect(Rect2i(t.x, t.y + CELL.y - 3, CELL.x, 3), wcol)
	img.fill_rect(Rect2i(t.x, t.y, 3, CELL.y), wcol)
	img.fill_rect(Rect2i(t.x + CELL.x - 3, t.y, 3, CELL.y), wcol)
	# Feindpräsenz: tatsächliche Gegnerzahl der gewählten Schwierigkeit
	var enemy_n := int(Game.diff()["enemies"])
	for k in enemy_n:
		img.fill_rect(Rect2i(t.x + 6 + (k % 9) * 8, t.y + 6 + (k / 9) * 8, 5, 5), Color(0.04, 0.04, 0.04))
	# Grüne Team-Markierung
	for k in Game.team.size():
		img.fill_rect(Rect2i(t.x + 8 + k * 9, t.y + CELL.y - 14, 6, 6), Color(0.35, 0.8, 0.3))
	return ImageTexture.create_from_image(img)

## Minimap-Farbe je Kartenzeichen — die Vorschau entspricht dem echten Sektor.
func _mini_color(ch: String, mx: int, my: int) -> Color:
	match ch:
		",":
			return Color(0.62, 0.5, 0.3)
		"~":
			return Color(0.15, 0.3, 0.5)
		"T":
			return Color(0.13, 0.27, 0.11)
		"t":
			return Color(0.2, 0.36, 0.16)
		"r":
			return Color(0.5, 0.5, 0.5)
		"#":
			return Color(0.34, 0.23, 0.13)
		"M":
			return Color(0.35, 0.37, 0.42)
		"W":
			return Color(0.6, 0.8, 0.9)
		"D":
			return Color(0.5, 0.35, 0.18)
		"w":
			return Color(0.55, 0.4, 0.24)
		"s":
			return Color(0.6, 0.62, 0.64)
		"C":
			return Color(0.75, 0.4, 0.15)
		"c":
			return Color(0.65, 0.45, 0.2)
		"S":
			return Color(0.75, 0.68, 0.45)
		"O":
			return Color(0.3, 0.3, 0.35)
		_:
			if (mx + my) % 2 == 0:
				return Color(0.30, 0.47, 0.24)
			return Color(0.27, 0.43, 0.21)

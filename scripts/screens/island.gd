extends Control
## Sector map "Ashveil Isle" (SPEC v5 §2) — the artwork IS the map.
## Clickable sector rectangles sit as invisible buttons on top of the DRAWN
## grid. The line positions live in data/sectors.json and were measured by a
## pixel scan of the image: the grid is NOT uniform (AI artwork), a formula
## would be off by up to 30 px on the right-hand side.
##
## IMPORTANT — deploy rule (SPEC v5 §2): the squad stands in EXACTLY ONE sector
## (`Game.sector`) and deploys only THERE. A sector flagged as demo content
## ("demo"/"playable" in the JSON) belongs to the demo, but is NOT directly
## selectable: you walk from F4 to F3 through the west exit. A map click
## therefore NEVER changes `Game.sector` — only a sector change in combat does.

const DATA_PATH := "res://data/sectors.json"

## Status values that mean "part of the demo content". The JSON says "demo";
## "playable" is accepted as a synonym so the spec's own wording (§2 table)
## can never silently lock a sector that is meant to be reachable.
const DEMO_STATUS := ["demo", "playable"]

var _cfg: Dictionary = {}
var _sectors: Dictionary = {}       # "F4" -> definition
var _cells: Dictionary = {}         # "F4" -> Button
var _art_size := Vector2(1672.0, 941.0)
var _gx: Array = []
var _gy: Array = []
var _rows: Array = []
var _cols: Array = []
var _stage: Control = null
var _hint: Label = null
var _title_lbl: Label = null
var _panel_row: HBoxContainer = null
var _current := "F4"                # where the squad stands = the only deploy target
var _focus := "F4"                  # clicked sector (display only)

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_cfg()
	# The location comes from the game state (save/sector change), not from here.
	_current = Game.sector if (Game.sector != "" and _sectors.has(Game.sector)) \
		else String(_cfg.get("start_sector", "F4"))
	Game.sector = _current
	_focus = _current

	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 6)
	add_child(v)

	# The artwork carries its own title ("ASHVEIL ISLE" + "SECTOR MAP"), so the
	# header shows the CLICKED sector instead of duplicating it.
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiTheme.hspace(16))
	_title_lbl = UiTheme.header("", 26)
	head.add_child(_title_lbl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_hint = UiTheme.lbl("", 14, UiTheme.COL_DIM)
	head.add_child(_hint)
	head.add_child(UiTheme.hspace(16))

	var map_area := Control.new()
	map_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(map_area)
	_build_map(map_area)

	v.add_child(_build_panel())
	_refresh_title()
	_set_hint(_default_hint(), UiTheme.COL_DIM)

	# The sector map is the save point of the strategy layer: this is where the
	# state comes from that "CONTINUE" in the main menu picks up again.
	Game.save_game(Game.AUTOSAVE_SLOT)

func _default_hint() -> String:
	var onward := _onward_sector()
	if onward == "":
		return "Deploy into %s." % _current
	return "Deploy into %s — %s is reached on foot." % [_current, onward]

## Next demo sector reachable on foot from the current one.
func _onward_sector() -> String:
	for e in (sector_def(_current).get("exits", []) as Array):
		var id := String(e)
		if is_demo(id) and id != _current:
			return id
	return ""

# ------------------------------------------------------------------ Data

func _load_cfg() -> void:
	_cfg = {}
	if FileAccess.file_exists(DATA_PATH):
		var f := FileAccess.open(DATA_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if typeof(parsed) == TYPE_DICTIONARY:
				_cfg = parsed
	var grid: Dictionary = _cfg.get("grid", {})
	_rows = grid.get("rows", ["A", "B", "C", "D", "E", "F"])
	_cols = grid.get("cols", ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10"])
	_gx = grid.get("x", [])
	_gy = grid.get("y", [])
	var isz: Array = _cfg.get("image_size", [1672, 941])
	if isz.size() == 2:
		_art_size = Vector2(float(isz[0]), float(isz[1]))
	# Fallback: uniform grid in case the data list is missing or broken.
	if _gx.size() != _cols.size() + 1:
		_gx = []
		for i in _cols.size() + 1:
			_gx.append(_art_size.x * float(i) / float(_cols.size()))
	if _gy.size() != _rows.size() + 1:
		_gy = []
		for i in _rows.size() + 1:
			_gy.append(_art_size.y * float(i) / float(_rows.size()))
	_sectors = {}
	for s in (_cfg.get("sectors", []) as Array):
		var sd: Dictionary = s
		_sectors[String(sd["id"])] = sd

func sector_def(id: String) -> Dictionary:
	if _sectors.has(id):
		return _sectors[id]
	return {"id": id, "name": "", "status": "locked",
		"note": String(_cfg.get("default_lock", "Locked in the demo."))}

## Is this sector part of the demo content? (NOT the same as "can jump there".)
func is_demo(id: String) -> bool:
	return String(sector_def(id)["status"]) in DEMO_STATUS

## The only deploy target is the sector the squad currently stands in.
func is_deployable(id: String) -> bool:
	return id == _current

func sector_id(r: int, c: int) -> String:
	return String(_rows[r]) + String(_cols[c])

func cell_rect(r: int, c: int) -> Rect2:
	var x0 := float(_gx[c])
	var y0 := float(_gy[r])
	return Rect2(x0, y0, float(_gx[c + 1]) - x0, float(_gy[r + 1]) - y0)

## Artwork pixel -> sector id ("" when outside the grid).
func sector_at_pixel(px: float, py: float) -> String:
	for r in _rows.size():
		for c in _cols.size():
			if cell_rect(r, c).has_point(Vector2(px, py)):
				return sector_id(r, c)
	return ""

# ------------------------------------------------------------------ Map

func _build_map(parent: Control) -> void:
	var ar := AspectRatioContainer.new()
	ar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ar.ratio = _art_size.x / _art_size.y
	ar.stretch_mode = AspectRatioContainer.STRETCH_FIT
	ar.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	ar.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	parent.add_child(ar)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ar.add_child(_stage)

	var path := String(_cfg.get("image", "res://assets/textures/worldmap.png"))
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_stage.add_child(tr)

	for r in _rows.size():
		for c in _cols.size():
			_add_cell(r, c)

func _add_cell(r: int, c: int) -> void:
	var id := sector_id(r, c)
	var d := sector_def(id)
	var nm := String(d["name"])
	var b := Button.new()
	b.text = ""
	# NOT flat=true: flat buttons draw NO StyleBox at all (not even hover).
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if is_deployable(id) else Control.CURSOR_ARROW
	b.tooltip_text = id + ("  —  " + nm if nm != "" else "")
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_place(b, cell_rect(r, c))
	b.pressed.connect(_on_cell.bind(id))
	b.mouse_entered.connect(_on_hover.bind(id))
	_stage.add_child(b)
	_cells[id] = b
	_style_cell(id)

func _style_cell(id: String) -> void:
	var b: Button = _cells[id]
	b.add_theme_stylebox_override("normal", _cell_style(id, false))
	b.add_theme_stylebox_override("hover", _cell_style(id, true))
	b.add_theme_stylebox_override("pressed", _cell_style(id, true))

## Amber = squad stands here (deploy target) · green = demo target, reached on
## foot · darkened = locked.
func _cell_style(id: String, hot: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(2)
	if is_deployable(id):
		var a := UiTheme.COL_AMBER
		sb.bg_color = Color(a.r, a.g, a.b, 0.30 if hot else 0.20)
		sb.set_border_width_all(3)
		sb.border_color = Color(1.0, 0.92, 0.62, 0.95)
		return sb
	if is_demo(id):
		var g := UiTheme.COL_GREEN
		sb.bg_color = Color(g.r, g.g, g.b, 0.20 if hot else 0.10)
		sb.set_border_width_all(2)
		sb.border_color = Color(g.r, g.g, g.b, 0.70)
		return sb
	# Deliberately restrained: the island must stay VISIBLE (SPEC v5 §2 —
	# "everything else is visible but locked"), just not selectable.
	sb.bg_color = Color(0, 0, 0, 0.16 if hot else 0.28)
	if hot:
		sb.set_border_width_all(2)
		sb.border_color = Color(UiTheme.COL_RED.r, UiTheme.COL_RED.g, UiTheme.COL_RED.b, 0.85)
	return sb

## Anchor a Control onto an image region (scales with the artwork).
func _place(c: Control, r: Rect2) -> void:
	c.anchor_left = r.position.x / _art_size.x
	c.anchor_top = r.position.y / _art_size.y
	c.anchor_right = (r.position.x + r.size.x) / _art_size.x
	c.anchor_bottom = (r.position.y + r.size.y) / _art_size.y
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

# ------------------------------------------------------------------ Interaction

func _on_hover(id: String) -> void:
	var nm := String(sector_def(id)["name"])
	var tag := "SQUAD HERE" if is_deployable(id) else ("ON FOOT" if is_demo(id) else "LOCKED")
	_set_hint("%s%s  —  %s" % [id, "  " + nm if nm != "" else "", tag],
		UiTheme.COL_TEXT if is_deployable(id) else UiTheme.COL_DIM)

## A map click only INSPECTS — it never moves the squad.
func _on_cell(id: String) -> void:
	var d := sector_def(id)
	var nm := String(d["name"])
	_focus = id
	if is_deployable(id):
		Sfx.play("ui_confirm")
		_set_hint("%s — your squad is here. DEPLOY to begin." % nm, UiTheme.COL_TEXT)
	elif is_demo(id):
		Sfx.play("ui_click")
		var reach := String(d.get("reach", "Reached on foot from the neighbouring sector."))
		_set_hint("%s — %s" % [nm, reach], UiTheme.COL_AMBER)
	else:
		Sfx.play("ui_error")
		_set_hint("LOCKED — %s%s" % [nm + ": " if nm != "" else "", String(d["note"])], UiTheme.COL_RED)
	_refresh_title()
	_refresh_panel()

func _set_hint(txt: String, col: Color) -> void:
	if _hint == null:
		return
	_hint.text = txt
	_hint.add_theme_color_override("font_color", col)

func _refresh_title() -> void:
	if _title_lbl == null:
		return
	var nm := String(sector_def(_focus)["name"])
	_title_lbl.text = "SECTOR %s%s" % [_focus, "  —  " + nm.to_upper() if nm != "" else ""]

# ------------------------------------------------------------------ Bottom panel

func _build_panel() -> PanelContainer:
	var bottom := PanelContainer.new()
	_panel_row = HBoxContainer.new()
	_panel_row.add_theme_constant_override("separation", 12)
	bottom.add_child(_panel_row)
	_refresh_panel()
	return bottom

## The panel ALWAYS describes the current location — only the header follows
## the click. That way DEPLOY can never accidentally lead somewhere else.
func _refresh_panel() -> void:
	if _panel_row == null:
		return
	for c in _panel_row.get_children():
		c.queue_free()
	var cur := sector_def(_current)

	var obj := VBoxContainer.new()
	obj.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_row.add_child(obj)
	obj.add_child(UiTheme.lbl("MISSION", 13, UiTheme.COL_DIM))
	obj.add_child(UiTheme.lbl(String(cur["note"]), 15))
	var nicks: Array = []
	for m in Game.team:
		nicks.append("»%s«" % m["nick"])
	obj.add_child(UiTheme.lbl("Squad: " + (", ".join(nicks) if not nicks.is_empty() else "—"),
		14, UiTheme.COL_AMBER))

	_panel_row.add_child(_info_box("TEAM", "%d / %d" % [Game.team.size(), Game.TEAM_MAX]))
	_panel_row.add_child(_info_box("FUNDS", "%d $" % Game.budget))
	_panel_row.add_child(_info_box("DAY", "1"))
	_panel_row.add_child(_info_box("DIFFICULTY", String(Game.diff()["name"])))
	_panel_row.add_child(_info_box("SECTOR", _current))

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_panel_row.add_child(actions)
	var go := UiTheme.btn("DEPLOY  ▸  %s" % _current, _deploy, 20)
	go.custom_minimum_size = Vector2(210, 46)
	go.tooltip_text = "Start the mission in sector %s" % _current
	actions.add_child(go)
	actions.add_child(UiTheme.btn("◂  Hire", func() -> void: _main().goto("hire"), 13))

## Deploy ALWAYS into the current sector (never into the merely clicked one).
func _deploy() -> void:
	Game.sector = _current
	_main().goto("loading")

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

extends Control
## Anheuer-Screen: 9 Kandidaten, Budget 6000 $, max. 4 im Team.

var _list: VBoxContainer
var _budget_lbl: Label
var _team_box: VBoxContainer
var _start_btn: Button

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 26)
	add_child(margin)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 22)
	margin.add_child(h)

	# Links: Kandidatenliste
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.2
	h.add_child(left)
	left.add_child(UiTheme.header("SÖLDNER ANHEUERN", 34))
	left.add_child(UiTheme.lbl("A.I.M.-Datennetz · Schwierigkeit: %s (Preisfaktor ×%s) · max. 4 Söldner" % [String(Game.diff()["name"]), str(Game.diff()["cost_mult"])], 15, UiTheme.COL_DIM))
	left.add_child(UiTheme.vspace(8))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	# Rechts: Budget + Team
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_constant_override("separation", 12)
	h.add_child(right)

	var bp := PanelContainer.new()
	right.add_child(bp)
	var bv := VBoxContainer.new()
	bp.add_child(bv)
	bv.add_child(UiTheme.lbl("VERFÜGBARES BUDGET", 14, UiTheme.COL_DIM))
	_budget_lbl = UiTheme.lbl("6.000 $", 34, UiTheme.COL_AMBER)
	bv.add_child(_budget_lbl)

	var tp := PanelContainer.new()
	tp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tp)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 8)
	tp.add_child(_team_box)

	_start_btn = UiTheme.btn("ZUR INSELKARTE  ▸", func() -> void: _main().goto("island"), 19)
	_start_btn.custom_minimum_size = Vector2(0, 52)
	right.add_child(_start_btn)
	var back := UiTheme.btn("◂  ZURÜCK", func() -> void: _main().goto("title"), 15)
	right.add_child(back)

	_refresh()

func _fmt(n: int) -> String:
	var s := str(n)
	if s.length() > 3:
		s = s.substr(0, s.length() - 3) + "." + s.substr(s.length() - 3)
	return s + " $"

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	for def in Db.MERCS:
		_list.add_child(_make_row(def))
	_budget_lbl.text = _fmt(Game.budget)
	for c in _team_box.get_children():
		c.queue_free()
	_team_box.add_child(UiTheme.lbl("TEAM  (%d/%d)" % [Game.team.size(), Game.TEAM_MAX], 14, UiTheme.COL_DIM))
	if Game.team.is_empty():
		_team_box.add_child(UiTheme.lbl("— noch niemand angeheuert —", 15, UiTheme.COL_DIM))
	for m in Game.team:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var tr := TextureRect.new()
		tr.texture = Assets.portrait(m["portrait"])
		tr.custom_minimum_size = Vector2(44, 44)
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(tr)
		var vb := VBoxContainer.new()
		vb.add_child(UiTheme.lbl("»%s«" % m["nick"], 17))
		vb.add_child(UiTheme.lbl(Db.weapon(m["weapon"])["short"] + " · " + _fmt(int(m.get("cost_paid", m["cost"]))), 13, UiTheme.COL_DIM))
		row.add_child(vb)
		_team_box.add_child(row)
	_start_btn.disabled = Game.team.is_empty()

func _make_row(def: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)

	var tr := TextureRect.new()
	tr.texture = Assets.portrait(def["portrait"])
	tr.custom_minimum_size = Vector2(76, 76)
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tr)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	var w: Dictionary = Db.weapon(def["weapon"])
	mid.add_child(UiTheme.lbl("»%s«  %s" % [def["nick"], def["name"]], 19, UiTheme.COL_AMBER))
	mid.add_child(UiTheme.lbl("HP %d  ·  TRF %d  ·  BEW %d  ·  MED %d  ·  ERF-Stufe %d" % [def["hp"], def["marks"], def["agi"], def["med"], def.get("exp", 1)], 15))
	var mags := 0
	var gren := 0
	var meds := 0
	for it in def["inv"]:
		var kind := String(Db.item(String(it))["kind"])
		if kind == "ammo":
			mags += 1
		elif kind == "grenade":
			gren += 1
		elif kind == "medkit":
			meds += 1
	var gear := "%s · %d Magazine · %d Granate(n) · %d Medikit(s)" % [w["name"], mags, gren, meds]
	mid.add_child(UiTheme.lbl(gear, 14, UiTheme.COL_DIM))
	mid.add_child(UiTheme.lbl("»" + def["quote"] + "«", 14, Color(0.7, 0.66, 0.5)))

	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 8)
	h.add_child(side)
	var eff := Game.eff_cost(int(def["cost"]))
	var price := UiTheme.lbl(_fmt(eff), 20, UiTheme.COL_AMBER)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	side.add_child(price)
	var hired := Game.is_hired(def["id"])
	var b: Button
	if hired:
		b = UiTheme.btn("Entlassen", _on_fire.bind(def["id"]), 15)
		b.add_theme_color_override("font_color", UiTheme.COL_RED)
	else:
		b = UiTheme.btn("Anheuern", _on_hire.bind(def["id"]), 15)
		b.disabled = Game.team.size() >= Game.TEAM_MAX or Game.budget < eff
	b.custom_minimum_size = Vector2(120, 40)
	side.add_child(b)
	return p

func _on_hire(id: String) -> void:
	if Game.hire(id):
		Sfx.play("ui_confirm")
		Sfx.play_voice(id + "_quote")
	else:
		Sfx.play("ui_error")
	_refresh()

func _on_fire(id: String) -> void:
	Game.fire(id)
	Sfx.play("ui_back")
	_refresh()

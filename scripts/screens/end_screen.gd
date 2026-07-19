extends Control
## Sieg-/Niederlage-Screen mit Statistik.

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	var res: String = Game.mission_result
	if res == "victory":
		var hd := UiTheme.header("MISSION ERFÜLLT", 44, UiTheme.COL_GREEN)
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hd)
		v.add_child(UiTheme.lbl("»General« Vargo ist gefallen. Die restliche Miliz hat sich ergeben.\nSilberquell ist frei.", 17))
		if Game.otto_freed:
			v.add_child(UiTheme.lbl("Otto Bär Brandt lebt — der Unterschlupf hält.", 17, UiTheme.COL_GREEN))
		if not Sfx.play_music("victory"):
			Sfx.play("victory")
	elif res == "abort":
		var hd := UiTheme.header("MISSION ABGEBROCHEN", 44, UiTheme.COL_AMBER)
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hd)
		v.add_child(UiTheme.lbl("Der Trupp hat sich zurückgezogen. Silberquell bleibt in Vargos Hand.", 17))
		if not Sfx.play_music("defeat"):
			Sfx.play("defeat", -6.0)
	else:
		var hd := UiTheme.header("MISSION GESCHEITERT", 44, UiTheme.COL_RED)
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hd)
		v.add_child(UiTheme.lbl("Ihr Trupp wurde aufgerieben. Vargo lässt die Leichen als Warnung hängen.", 17))
		if not Sfx.play_music("defeat"):
			Sfx.play("defeat")

	v.add_child(UiTheme.vspace(10))
	var st: Dictionary = Game.stats
	var acc := 0
	if int(st.get("shots", 0)) > 0:
		acc = int(round(100.0 * float(st.get("hits", 0)) / float(st.get("shots", 1))))
	v.add_child(UiTheme.lbl("Runden: %d    ·    Schüsse: %d    ·    Trefferquote: %d %%" % [int(st.get("turns", 0)), int(st.get("shots", 0)), acc], 16, UiTheme.COL_DIM))
	v.add_child(UiTheme.vspace(6))

	for m in Game.team:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var tr := TextureRect.new()
		tr.texture = Assets.portrait(m["portrait"])
		tr.custom_minimum_size = Vector2(48, 48)
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(tr)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiTheme.lbl("»%s«  %s" % [m["nick"], m["name"]], 17))
		info.add_child(UiTheme.lbl("Abschüsse: %d" % int(m.get("kills", 0)), 14, UiTheme.COL_DIM))
		row.add_child(info)
		var status := UiTheme.lbl("ÜBERLEBT", 16, UiTheme.COL_GREEN)
		if not bool(m.get("alive", true)):
			status = UiTheme.lbl("GEFALLEN", 16, UiTheme.COL_RED)
		status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(status)
		v.add_child(row)

	v.add_child(UiTheme.vspace(14))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	var b := UiTheme.btn("ZUM HAUPTMENÜ", func() -> void: _main().goto("title"), 18)
	b.custom_minimum_size = Vector2(240, 48)
	hb.add_child(b)
	var q := UiTheme.btn("SPIEL BEENDEN", func() -> void: get_tree().quit(), 18)
	q.custom_minimum_size = Vector2(240, 48)
	hb.add_child(q)

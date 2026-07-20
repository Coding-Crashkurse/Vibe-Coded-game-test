extends Control
## Schwierigkeitswahl: LEICHT / NORMAL / SCHWER.

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

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)

	var hd := UiTheme.header("CHOOSE DIFFICULTY", 40)
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hd)
	v.add_child(UiTheme.vspace(10))

	var keys := ["leicht", "normal", "schwer"]
	for k in keys:
		var d: Dictionary = Db.DIFFICULTY[k]
		var b := UiTheme.btn("", _on_pick.bind(k), 20)
		b.custom_minimum_size = Vector2(640, 84)
		var inner := VBoxContainer.new()
		inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		inner.alignment = BoxContainer.ALIGNMENT_CENTER
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(inner)
		var nm := UiTheme.header(String(d["name"]), 26)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(nm)
		var ds := UiTheme.lbl(String(d["desc"]), 14, UiTheme.COL_DIM)
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ds.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(ds)
		v.add_child(b)

	v.add_child(UiTheme.vspace(12))
	var back := UiTheme.btn("◂  BACK", func() -> void: _main().goto("title"), 15)
	back.custom_minimum_size = Vector2(200, 0)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)

func _on_pick(k: String) -> void:
	Game.set_difficulty(k)
	Sfx.play("ui_confirm")
	_main().goto("hire")

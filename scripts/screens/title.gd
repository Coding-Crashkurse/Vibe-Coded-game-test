extends Control
## Titelscreen mit Menü.

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Dekorative Figuren unten rechts
	var deco := [["soldier1_machine", -320, -180, 0.9], ["survivor1_gun", -210, -260, 0.7], ["hitman1_gun", -140, -150, 0.8]]
	for d in deco:
		var tr := TextureRect.new()
		tr.texture = Assets.tex(d[0])
		tr.custom_minimum_size = Vector2(128, 128)
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		tr.position = Vector2.ZERO
		tr.offset_left = d[1]
		tr.offset_top = d[2]
		tr.offset_right = d[1] + 128
		tr.offset_bottom = d[2] + 128
		tr.rotation = randf_range(-0.4, 0.4)
		tr.modulate = Color(1, 1, 1, float(d[3]) * 0.35)
		add_child(tr)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	center.add_child(v)

	var title := UiTheme.header("SÖLDNERKOMMANDO", 68)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var sub := UiTheme.header("— OPERATION SILBERFUCHS —", 26, UiTheme.COL_TEXT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	var tag := UiTheme.lbl("Ein rundenbasiertes Taktikspiel im Geiste von Jagged Alliance 2", 15, UiTheme.COL_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tag)

	v.add_child(UiTheme.vspace(30))

	var b1 := UiTheme.btn("NEUES SPIEL", _on_new_game, 22)
	b1.custom_minimum_size = Vector2(340, 52)
	v.add_child(b1)

	var b2 := UiTheme.btn("3D-GEFECHT (BETA)", _start_3d_beta, 22)
	b2.custom_minimum_size = Vector2(340, 52)
	v.add_child(b2)

	var b3 := UiTheme.btn("BEENDEN", func() -> void: get_tree().quit(), 22)
	b3.custom_minimum_size = Vector2(340, 52)
	v.add_child(b3)

	var foot := UiTheme.lbl("Grafik: Kenney.nl (CC0) · Sound: prozedural generiert · [M] Ton an/aus", 13, UiTheme.COL_DIM)
	foot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	foot.offset_left = 16
	foot.offset_top = -34
	add_child(foot)

	# Fade-In
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 0.0, 0.7)
	tw.tween_callback(black.queue_free)

	Sfx.play_music()

func _on_new_game() -> void:
	Game.new_game()
	_main().goto("difficulty")

func _start_3d_beta() -> void:
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	_main().goto("tactical3d_combat")

extends Control
## Victory / defeat screen with run statistics.
## SPEC v5 §3.3.6: victory WITH Tobias Rook freed  ->  DEMO END CARD.

## Candidates for the end-card backdrop (first one that exists wins).
## If none is there the styled panel stands on its own — ResourceLoader.exists guards.
const _BG_CANDIDATES := [
	"res://assets/textures/end_card.png",
	"res://assets/textures/main_menu.png",
	"res://assets/textures/worldmap.png",
]

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var res: String = Game.mission_result
	var demo: bool = res == "victory" and Game.otto_freed

	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	if demo:
		_add_backdrop()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)

	if demo:
		_build_demo_card(v)
	elif res == "victory":
		var hd := UiTheme.header("MISSION COMPLETE", 44, UiTheme.COL_GREEN)
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hd)
		# SPEC v5 §3.2 cuts the warlord boss fight, so this branch no longer credits
		# Vargo. It is only reachable when the sector was cleared WITHOUT the rescue
		# (bot/headless runs) — the demo end card above needs `Game.otto_freed`.
		v.add_child(UiTheme.lbl("The Helix garrison is broken. But the storehouse cellar is still\nlocked, and Tobias Rook is still in it.", 17))
		if not Sfx.play_music("victory"):
			Sfx.play("victory")
	elif res == "abort":
		var hd := UiTheme.header("MISSION ABORTED", 44, UiTheme.COL_AMBER)
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hd)
		v.add_child(UiTheme.lbl("The squad pulled out. Rookhaven stays in Helix hands.", 17))
		if not Sfx.play_music("defeat"):
			Sfx.play("defeat", -6.0)
	else:
		var hd := UiTheme.header("MISSION FAILED", 44, UiTheme.COL_RED)
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(hd)
		v.add_child(UiTheme.lbl("Your squad was wiped out. Helix leaves the bodies hanging as a warning.", 17))
		if not Sfx.play_music("defeat"):
			Sfx.play("defeat")

	v.add_child(UiTheme.vspace(10))
	var st: Dictionary = Game.stats
	var acc := 0
	if int(st.get("shots", 0)) > 0:
		acc = int(round(100.0 * float(st.get("hits", 0)) / float(st.get("shots", 1))))
	v.add_child(UiTheme.lbl("Turns: %d    ·    Shots: %d    ·    Hit rate: %d %%" % [int(st.get("turns", 0)), int(st.get("shots", 0)), acc], 16, UiTheme.COL_DIM))
	v.add_child(UiTheme.vspace(6))

	for m in Game.team:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var tr := TextureRect.new()
		tr.texture = Assets.portrait(m["portrait"])
		tr.custom_minimum_size = Vector2(48, 48)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		row.add_child(tr)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiTheme.lbl("\"%s\"  %s" % [m["nick"], m["name"]], 17))
		info.add_child(UiTheme.lbl("Kills: %d" % int(m.get("kills", 0)), 14, UiTheme.COL_DIM))
		row.add_child(info)
		var status := UiTheme.lbl("SURVIVED", 16, UiTheme.COL_GREEN)
		if not bool(m.get("alive", true)):
			status = UiTheme.lbl("KILLED IN ACTION", 16, UiTheme.COL_RED)
		status.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(status)
		v.add_child(row)

	v.add_child(UiTheme.vspace(14))
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	var b := UiTheme.btn("TO MAIN MENU", func() -> void: _main().goto("title"), 18)
	b.custom_minimum_size = Vector2(240, 48)
	hb.add_child(b)
	var q := UiTheme.btn("QUIT GAME", func() -> void: get_tree().quit(), 18)
	q.custom_minimum_size = Vector2(240, 48)
	hb.add_child(q)

	if demo:
		panel.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(panel, "modulate:a", 1.0, 0.6)

# ------------------------------------------------------------ Demo end card

func _build_demo_card(v: VBoxContainer) -> void:
	Game.demo_finished = true

	var over := UiTheme.lbl("END OF DEMO", 15, UiTheme.COL_DIM)
	over.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(over)

	var hd := UiTheme.header("ROOKHAVEN IS FREE.", 46, UiTheme.COL_GREEN)
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hd)

	v.add_child(UiTheme.vspace(6))

	var line := UiTheme.lbl("Maren Rook is out there somewhere. And the mines keep digging — for Helix.", 19)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(line)

	v.add_child(UiTheme.vspace(8))

	var cont := UiTheme.header("TO BE CONTINUED.", 30, UiTheme.COL_AMBER)
	cont.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(cont)

	var sub := UiTheme.lbl("Tobias Rook is alive — The Hideout holds.", 16, UiTheme.COL_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)

	if not Sfx.play_music("victory"):
		Sfx.play("victory")

## Optional backdrop image + dimmer. If the file is missing, nothing happens.
func _add_backdrop() -> void:
	var tex: Texture2D = null
	for p in _BG_CANDIDATES:
		var path := String(p)
		if ResourceLoader.exists(path):
			var r = load(path)
			if r is Texture2D:
				tex = r
				break
	if tex == null:
		return
	var tr := TextureRect.new()
	tr.texture = tex
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(0.55, 0.52, 0.46, 1.0)
	add_child(tr)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

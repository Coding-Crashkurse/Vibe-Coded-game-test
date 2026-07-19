extends Control
## Ladescreen mit Fortschrittsbalken und Taktik-Tipps.

var _bar: ProgressBar
var _step: Label

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
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)

	var h := UiTheme.header("ANFLUG AUF SILBERQUELL …", 34)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(h)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(560, 26)
	_bar.min_value = 0
	_bar.max_value = 100
	_bar.value = 0
	_bar.show_percentage = false
	v.add_child(_bar)

	_step = UiTheme.lbl("Karte wird geladen …", 16, UiTheme.COL_DIM)
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_step)

	v.add_child(UiTheme.vspace(24))
	var tip := UiTheme.lbl(Db.TIPS[randi() % Db.TIPS.size()], 15, Color(0.62, 0.64, 0.5))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(700, 0)
	v.add_child(tip)

	_run()

func _run() -> void:
	var steps := [
		[30.0, "Karte wird generiert …"],
		[60.0, "Einheiten werden platziert …"],
		[85.0, "Sichtfelder werden berechnet …"],
		[100.0, "Bereit. Viel Erfolg, Kommandant."],
	]
	for s in steps:
		_step.text = s[1]
		var tw := create_tween()
		tw.tween_property(_bar, "value", s[0], 0.35)
		await tw.finished
		await get_tree().create_timer(0.12).timeout
	await get_tree().create_timer(0.25).timeout
	# 3D ist jetzt das Hauptspiel (2D-Kampf entfernt): der Anheuern/Sektor-Flow
	# muendet ins 3D-Gefecht.
	_main().goto("tactical3d_combat")

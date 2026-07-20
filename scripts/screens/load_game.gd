extends Control
## Load screen — a thin host around the shared save/load slot overlay
## (scripts/ui/save_panel.gd, SPEC v5 §4.4). The overlay lists the autosave plus
## the manual slots and knows how to render damaged / version-incompatible files.
##
## Loading sets the Game state and then resumes the campaign where it belongs:
## in The Hideout once the cellar base is unlocked (SPEC v5 §3.3.5), otherwise on
## the island sector map, which is what every save from before the rescue gets.

const SavePanelScript := preload("res://scripts/ui/save_panel.gd")

var _panel: Node = null

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = UiTheme.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 10)
	add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiTheme.hspace(18))
	head.add_child(UiTheme.header("LOAD GAME", 34))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiTheme.lbl("Pick a save slot.", 14, UiTheme.COL_DIM))
	head.add_child(UiTheme.hspace(18))

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(filler)

	var foot := HBoxContainer.new()
	v.add_child(foot)
	foot.add_child(UiTheme.hspace(18))
	var back := UiTheme.btn("◂  BACK", _back, 18)
	back.custom_minimum_size = Vector2(180, 44)
	foot.add_child(back)
	v.add_child(UiTheme.vspace(12))

	_open_panel()

func _open_panel() -> void:
	if _panel != null and is_instance_valid(_panel):
		return
	_panel = SavePanelScript.open(self, "load", _on_panel_done)

## The overlay hands back {"action": "load"|"cancel", "slot": int, "ok": bool}.
func _on_panel_done(res: Dictionary) -> void:
	_panel = null
	if String(res.get("action", "")) == "load" and bool(res.get("ok", false)):
		_resume()
	else:
		_back()

## Hideout.enter_base() must set the room's mode on the router BEFORE goto(),
## because goto() add_child()s the screen and thus runs _ready() synchronously.
func _resume() -> void:
	var m := _main()
	if m == null:
		return
	if Game.base_unlocked:
		Hideout.enter_base(m)
	else:
		m.goto("island")

func _back() -> void:
	_main().goto("title")

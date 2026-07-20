extends Control
## Main menu — the artwork IS the menu: START GAME / CONTINUE / LOAD GAME /
## OPTIONS / QUIT are painted into the image, invisible click areas sit on top.
## So the areas land exactly on the painted buttons at EVERY window size, the
## whole thing hangs in an AspectRatioContainer (image ratio, STRETCH_FIT).
## Without the texture (import has not run yet) a text fallback takes over.
##
## BINDING DESIGN DECISION (it overrides SPEC v5 §4.3 where the two disagree):
## this painted artwork IS the title screen and the entry point — it stays. The
## walkable 3D room (scripts/menu/hideout.gd) is not a menu at all, it is the
## IN-GAME HOME BASE, and only a RESUMED campaign can land there:
##
##   START GAME          -> difficulty -> hire -> island map -> F4. Unchanged:
##                          story-wise there is no base until Tobias is rescued.
##   CONTINUE / LOAD     -> The Hideout when the save has the cellar (§3.3.5),
##                          otherwise the island sector map exactly as before.
##
## The invisible hotspot buttons below are pixel-measured over the artwork. Do not
## move them, and never set flat = true on them (see _build_art_menu).

const ART_PATH := "res://assets/textures/main_menu.png"
const ART_SIZE := Vector2(1672.0, 941.0)
const SavePanelScript := preload("res://scripts/ui/save_panel.gd")

## Click areas in image pixels — measured from the artwork (pixel scan).
const HOTSPOTS := [
	{"id": "start",    "label": "START GAME", "rect": Rect2(710, 438, 314, 95)},
	{"id": "continue", "label": "CONTINUE",   "rect": Rect2(735, 554, 266, 62)},
	{"id": "load",     "label": "LOAD GAME",  "rect": Rect2(735, 624, 266, 62)},
	{"id": "options",  "label": "OPTIONS",    "rect": Rect2(735, 700, 266, 62)},
	{"id": "quit",     "label": "QUIT",       "rect": Rect2(735, 771, 266, 62)},
]

var _stage: Control = null
var _options_panel: Control = null
var _save_panel: Node = null
var _buttons := {}          # id -> Button (for tests / verification)

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var art: Texture2D = load(ART_PATH) if ResourceLoader.exists(ART_PATH) else null
	if art != null:
		_build_art_menu(art)
	else:
		_build_fallback_menu()

	# Fade in
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 0.0, 0.7)
	tw.tween_callback(black.queue_free)

	Sfx.play_music()

# ------------------------------------------------------------------ Artwork menu

func _build_art_menu(art: Texture2D) -> void:
	var ar := AspectRatioContainer.new()
	ar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ar.ratio = ART_SIZE.x / ART_SIZE.y
	ar.stretch_mode = AspectRatioContainer.STRETCH_FIT
	ar.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	ar.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	add_child(ar)

	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ar.add_child(_stage)

	var tr := TextureRect.new()
	tr.texture = art
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.add_child(tr)

	var have_save: bool = Game.has_any_save()
	for h in HOTSPOTS:
		var id := String(h["id"])
		var locked: bool = (id == "continue" or id == "load") and not have_save
		var b := Button.new()
		b.text = ""
		# NOT flat=true: a flat button draws NO StyleBox at all — not even
		# hover/pressed. Instead leave "normal" empty (invisible) and draw a
		# glow for hover/pressed only.
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = locked
		b.tooltip_text = String(h["label"]) + ("  (no save yet)" if locked else "")
		b.mouse_default_cursor_shape = Control.CURSOR_ARROW if locked else Control.CURSOR_POINTING_HAND
		b.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("disabled", StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", _glow(0.16, 0.85))
		b.add_theme_stylebox_override("pressed", _glow(0.30, 1.0))
		_place(b, h["rect"])
		b.pressed.connect(_on_pressed.bind(id))
		_stage.add_child(b)
		_buttons[id] = b
		# Darken locked buttons so "no save yet" is visible at a glance.
		if locked:
			var dim := ColorRect.new()
			dim.color = Color(0, 0, 0, 0.55)
			dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_place(dim, h["rect"])
			_stage.add_child(dim)

	var hint := UiTheme.lbl("[M] mute on/off", 13, UiTheme.COL_DIM)
	hint.modulate.a = 0.5
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 18
	hint.offset_top = -32
	_stage.add_child(hint)

## Place a Control on an image region via anchors (scales with the artwork).
func _place(c: Control, r: Rect2) -> void:
	c.anchor_left = r.position.x / ART_SIZE.x
	c.anchor_top = r.position.y / ART_SIZE.y
	c.anchor_right = (r.position.x + r.size.x) / ART_SIZE.x
	c.anchor_bottom = (r.position.y + r.size.y) / ART_SIZE.y
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

func _glow(fill: float, edge: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.82, 0.42, fill)
	sb.set_corner_radius_all(6)
	sb.set_border_width_all(2)
	sb.border_color = Color(1.0, 0.88, 0.55, edge)
	return sb

# ------------------------------------------------------------------ Fallback

## Without the artwork (import has not run yet) the menu stays usable.
func _build_fallback_menu() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 10)
	center.add_child(v)
	var title := UiTheme.header("BITTER HARVEST", 68)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(UiTheme.vspace(24))
	var have_save: bool = Game.has_any_save()
	for h in HOTSPOTS:
		var id := String(h["id"])
		var b := UiTheme.btn(String(h["label"]), _on_pressed.bind(id), 22)
		b.custom_minimum_size = Vector2(340, 52)
		b.disabled = (id == "continue" or id == "load") and not have_save
		v.add_child(b)
		_buttons[id] = b

# ------------------------------------------------------------------ Actions

func _on_pressed(id: String) -> void:
	match id:
		"start":
			Sfx.play("ui_click")
			Game.new_game()
			_main().goto("difficulty")
		"continue":
			_continue()
		"load":
			Sfx.play("ui_click")
			_show_load_panel()
		"options":
			Sfx.play("ui_click")
			_show_options()
		"quit":
			Sfx.play("ui_click")
			get_tree().quit()

## LOAD GAME — the shared slot overlay (SPEC v5 §4.4) opens straight over the
## painted menu, so the artwork stays visible behind it.
func _show_load_panel() -> void:
	if _save_panel != null and is_instance_valid(_save_panel):
		return
	_save_panel = SavePanelScript.open(self, "load", _on_load_panel_done)

## The overlay hands back {"action": "load"|"cancel", "slot": int, "ok": bool}.
func _on_load_panel_done(res: Dictionary) -> void:
	_save_panel = null
	if String(res.get("action", "")) == "load" and bool(res.get("ok", false)):
		_resume()

## CONTINUE — load the most recent save and pick the game back up.
func _continue() -> void:
	var slot := Game.latest_slot()
	if slot < 0 or not Game.load_game(slot):
		Sfx.play("ui_error")
		return
	Sfx.play("ui_confirm")
	_resume()

## Where a freshly loaded campaign continues. Once the cellar under the village
## is the player's (SPEC v5 §3.3.5) it is their home base, and coming back into
## the game means walking into that room — squad, stash and save book all sit
## there. Everything from before the rescue resumes on the sector map, as always.
##
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

## OPTIONS — deliberately still EMPTY (placeholder with a back button).
func _show_options() -> void:
	if _options_panel != null:
		return
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_options_panel = shade

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 260)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	var head := UiTheme.header("OPTIONS", 34)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(head)
	var note := UiTheme.lbl("— empty for now —", 16, UiTheme.COL_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)
	v.add_child(UiTheme.vspace(10))
	var back := UiTheme.btn("BACK", _close_options, 20)
	back.custom_minimum_size = Vector2(200, 46)
	v.add_child(back)

func _close_options() -> void:
	if _options_panel != null:
		_options_panel.queue_free()
		_options_panel = null

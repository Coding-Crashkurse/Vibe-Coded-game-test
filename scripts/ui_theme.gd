class_name UiTheme
extends RefCounted
## JA1-artiges Leder/Holz-Theme + UI-Bau-Helfer (alles per Code).

const COL_BG := Color("18120a")
const COL_PANEL := Color("3a2c19")
const COL_PANEL_LIGHT := Color("4c3a21")
const COL_EDGE := Color("8a6a3a")
const COL_AMBER := Color("e0b264")
const COL_TEXT := Color("e8dcc0")
const COL_DIM := Color("a5906c")
const COL_RED := Color("c2453a")
const COL_GREEN := Color("7fb069")

static var _theme: Theme = null
static var _title_font: Font = null

static func _sfx(sound: String) -> void:
	var ml := Engine.get_main_loop() as SceneTree
	if ml and ml.root.has_node("Sfx"):
		ml.root.get_node("Sfx").play(sound)

static func box(bg: Color, edge := Color(0, 0, 0, 0), radius := 4, border := 2, pad := 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if edge.a > 0.0:
		sb.set_border_width_all(border)
		sb.border_color = edge
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad * 0.6
	sb.content_margin_bottom = pad * 0.6
	return sb

static func theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font_size = 17
	# Buttons (Leder-Look)
	t.set_stylebox("normal", "Button", box(COL_PANEL_LIGHT, COL_EDGE, 4, 2, 12))
	t.set_stylebox("hover", "Button", box(Color("5e4828"), COL_AMBER, 4, 2, 12))
	t.set_stylebox("pressed", "Button", box(Color("2b2010"), COL_AMBER, 4, 2, 12))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 4, 0, 12))
	var dis := box(COL_PANEL_LIGHT, COL_EDGE, 4, 2, 12)
	dis.bg_color.a = 0.4
	dis.border_color.a = 0.3
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_color", "Button", COL_TEXT)
	t.set_color("font_hover_color", "Button", COL_AMBER)
	t.set_color("font_pressed_color", "Button", COL_AMBER)
	t.set_color("font_disabled_color", "Button", Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.5))
	# Panels (Holzrahmen)
	t.set_stylebox("panel", "Panel", box(COL_PANEL, COL_EDGE, 6, 2, 10))
	t.set_stylebox("panel", "PanelContainer", box(COL_PANEL, COL_EDGE, 6, 2, 10))
	# Labels
	t.set_color("font_color", "Label", COL_TEXT)
	# ProgressBar
	t.set_stylebox("background", "ProgressBar", box(Color("221808"), Color("5a4426"), 3, 1, 2))
	t.set_stylebox("fill", "ProgressBar", box(COL_AMBER, Color(0, 0, 0, 0), 3, 0, 2))
	# RichTextLabel
	t.set_color("default_color", "RichTextLabel", COL_TEXT)
	_theme = t
	return t

## Heading font. First hit wins, after that Godot's fallback.
##
## WHY NOT KENNEY ANY MORE: kenney_future_narrow (and kenney_mini) draw the "X"
## like an H and the "Z" like a 2 — "BLITZ" read as "BLIT2", "FOX" as "FOH". The
## glyphs are NOT missing (verified with fontTools), they are simply designed
## that way. For proper names that is unusable. Black Ops One (SIL OFL, the
## licence sits next to it as BlackOpsOne-OFL.txt) is a military stencil face,
## renders X/Z correctly and fits BITTER HARVEST tonally.
const TITLE_FONTS := [
	"res://assets/font/BlackOpsOne-Regular.ttf",
	"res://assets/font/kenney_future_narrow.ttf",
]

static func title_font() -> Font:
	if _title_font != null:
		return _title_font
	for p in TITLE_FONTS:
		var path := String(p)
		if ResourceLoader.exists(path):
			var f: FontFile = load(path)
			if f != null:
				f.fallbacks = [ThemeDB.fallback_font]
				_title_font = f
				return _title_font
	_title_font = ThemeDB.fallback_font
	return _title_font

static func header(txt: String, size := 30, col := COL_AMBER) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

static func lbl(txt: String, size := 17, col := COL_TEXT) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	return l

static func btn(txt: String, cb: Callable, size := 17) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func() -> void: _sfx("ui_click"))
	b.pressed.connect(cb)
	return b

static func vspace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c

static func hspace(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c

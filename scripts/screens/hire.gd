extends Control
## Hiring screen: candidate list + merc dossier as its own overlay.
## v5 BITTER HARVEST — every player-facing string is English.

const CARD_MAX_W := 620.0
const CARD_MAX_H_FRAC := 0.82
const PORTRAIT_PX := 256.0
const DAYS_PER_CONTRACT := 7   # display only, for the daily-rate line
const EXP_MAX := 3.0           # Db exp values run 1..3 (Rookie/Veteran/Elite)

# ------------------------------------------------------------------ Return path
## WHERE THIS SCREEN GOES WHEN THE PLAYER IS DONE.
##
## "" (the default) is the NEW GAME flow and is untouched: difficulty -> hire ->
## island map, with Back going up to the title screen.
##
## RETURN_BASE is the second way in: The Hideout's laptop (the A.I.M. network
## hotspot, §4.3) routes into this very screen out of the running campaign. From
## there the island map is NOT home — the player would be stranded on it — so both
## exits lead back into the room instead, and both say so.
const RETURN_BASE := "base"

## Loaded at RUNTIME, never preloaded: a preload turns a missing file into a parse
## error for the whole screen, which would break the fallback law (see _go_home).
const HIDEOUT_PATH := "res://scripts/menu/hideout.gd"

## PUBLIC ENTRY CONTRACT — how a caller says "I came from the base, send me back".
## One request, three equivalent ways to make it; pick whichever fits the caller:
##
##   1. This static var, set BEFORE the goto (no other file has to cooperate):
##          var hs = load("res://scripts/screens/hire.gd")
##          hs.set("pending_return", "base")
##          router.goto("hire")
##   2. The router property `hire_return`, the same one-shot idiom main.gd already
##      carries as `start_sector` / `hideout_mode` — also set BEFORE the goto:
##          router.set("hire_return", "base")   # needs `var hire_return := ""` in main.gd
##          router.goto("hire")
##   3. After the goto, on the live screen:
##          router.current.call("set_return_target", "base")
##
## For 1 and 2 the value MUST be set before goto(), because goto() add_child()s the
## screen and therefore runs _ready() synchronously. Both are ONE-SHOT and are
## cleared in _ready() right after they are read — a leftover "base" would send the
## next NEW GAME run into the room instead of onto the island map.
static var pending_return := ""

var _list: VBoxContainer
var _budget_lbl: Label
var _team_box: VBoxContainer
var _start_btn: Button
var _back_btn: Button
var _budget_tw: Tween = null

## "" = new-game flow, RETURN_BASE = came from The Hideout.
var _return := ""

# --- Dossier overlay
var _overlay: CanvasLayer = null
var _card: PanelContainer = null
var _scroll: ScrollContainer = null
var _body: VBoxContainer = null
var _chrome_h := 200.0

# --- Focus trap (spec §4.2 point 3): while the dossier is open, keyboard focus
# must not escape into the list behind it. On open every focusable control of the
# screen is set to FOCUS_NONE and remembered; on close the old modes and the
# previously focused control are restored.
var _focus_prev: Control = null
var _focus_frozen: Array = []   # [[Control, old_focus_mode], ...]

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_read_return_request()

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

	# Left: candidate list
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.2
	h.add_child(left)
	left.add_child(UiTheme.header("HIRE MERCS", 34))
	left.add_child(UiTheme.lbl("A.I.M. Network · Difficulty: %s (price factor ×%s) · max. 4 mercs · click a merc for the dossier" % [String(Game.diff()["name"]), str(Game.diff()["cost_mult"])], 15, UiTheme.COL_DIM))
	left.add_child(UiTheme.vspace(8))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	# Right: budget + team
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(380, 0)
	right.add_theme_constant_override("separation", 12)
	h.add_child(right)

	var bp := PanelContainer.new()
	right.add_child(bp)
	var bv := VBoxContainer.new()
	bp.add_child(bv)
	bv.add_child(UiTheme.lbl("AVAILABLE BUDGET", 14, UiTheme.COL_DIM))
	_budget_lbl = UiTheme.lbl("6.000 $", 34, UiTheme.COL_AMBER)
	bv.add_child(_budget_lbl)

	var tp := PanelContainer.new()
	tp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tp)
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 8)
	tp.add_child(_team_box)

	# Both buttons route through named methods rather than inline lambdas: the
	# destination now depends on _return, and the labels have to be rewritten from
	# one place (_apply_return_labels) when the caller announces itself late.
	_start_btn = UiTheme.btn("TO THE ISLAND MAP  ▸", _on_continue, 19)
	_start_btn.custom_minimum_size = Vector2(0, 52)
	right.add_child(_start_btn)
	_back_btn = UiTheme.btn("◂  BACK", _on_back, 15)
	right.add_child(_back_btn)
	_apply_return_labels()

	get_viewport().size_changed.connect(_fit_dossier)
	_refresh()


## Consumes the one-shot "send me back to the base" request from either source
## (see the PUBLIC ENTRY CONTRACT above). Both are cleared as they are read.
##
## Only an exact RETURN_BASE ever flips the flag, and neither source can clear a
## request the other one made — so a router that never declares `hire_return`
## (Node.get() returns null then, exactly the "nothing was injected" case) leaves
## the static path fully working, and vice versa.
func _read_return_request() -> void:
	_return = ""
	if String(pending_return) == RETURN_BASE:
		_return = RETURN_BASE
	pending_return = ""
	var m := _main()
	if m == null:
		return
	var v = m.get("hire_return")
	if v == null:
		return
	m.set("hire_return", "")
	if String(v) == RETURN_BASE:
		_return = RETURN_BASE


## Late announcement (way 3 of the contract): usable at any time, including before
## _ready() has built the buttons — _ready() applies the labels itself afterwards.
func set_return_target(target: String) -> void:
	_return = RETURN_BASE if target == RETURN_BASE else ""
	if _start_btn == null or not is_instance_valid(_start_btn):
		return
	_apply_return_labels()
	_start_btn.disabled = Game.team.is_empty() and _return == ""


## The only place the two exit buttons are labelled. In base mode the big button
## is the one that names the destination; the small one keeps its plain "BACK"
## (it IS going back — to the room the player came from) and spells the room out
## in its tooltip.
func _apply_return_labels() -> void:
	var home := _return == RETURN_BASE
	if _start_btn != null and is_instance_valid(_start_btn):
		_start_btn.text = "◂  BACK TO THE HIDEOUT" if home else "TO THE ISLAND MAP  ▸"
		_start_btn.tooltip_text = "Return to The Hideout" if home else ""
	if _back_btn != null and is_instance_valid(_back_btn):
		_back_btn.tooltip_text = "Back to The Hideout" if home else ""


## Primary button. New-game flow: on to the island map. From the base: home.
func _on_continue() -> void:
	if _return == RETURN_BASE:
		_go_home()
		return
	_main().goto("island")


## Secondary button. New-game flow: up to the title screen. From the base: home —
## the title screen would throw the running campaign away.
func _on_back() -> void:
	if _return == RETURN_BASE:
		_go_home()
		return
	_main().goto("title")


## Hand the player back to The Hideout through its own public entry point.
## Deliberately NOT a preload (fallback law): if the room is ever missing from the
## build this screen must still parse and still offer a way out, so it falls back
## to the sector map — anywhere is better than a dead end.
func _go_home() -> void:
	var m := _main()
	if m == null:
		return
	if ResourceLoader.exists(HIDEOUT_PATH):
		var s = load(HIDEOUT_PATH)
		if s != null and s.has_method("enter_base"):
			s.call("enter_base", m)
			return
	m.goto("island")

func _fmt(n: int) -> String:
	var s := str(n)
	if s.length() > 3:
		s = s.substr(0, s.length() - 3) + "." + s.substr(s.length() - 3)
	return s + " $"

## Experience level as a word (spec §4.2).
func _rank_word(exp_lvl: int) -> String:
	if exp_lvl <= 1:
		return "Rookie"
	if exp_lvl == 2:
		return "Veteran"
	return "Elite"

## Bar colour by percentage (spec §4.2: <40 red, 40-69 gold, >=70 green).
func _bar_col(pct: float) -> Color:
	if pct < 40.0:
		return UiTheme.COL_RED
	if pct < 70.0:
		return UiTheme.COL_AMBER
	return UiTheme.COL_GREEN

## Summarise a merc's equipment: [[item_id, count], ...]
func _gear_of(def: Dictionary) -> Array:
	var out: Array = [[String(def["weapon"]), 1]]
	var order: Array = []
	var counts: Dictionary = {}
	for it in def["inv"]:
		var id := String(it)
		if not counts.has(id):
			counts[id] = 0
			order.append(id)
		counts[id] = int(counts[id]) + 1
	for it2 in order:
		var id2 := String(it2)
		out.append([id2, int(counts[id2])])
	return out

func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	# Candidates sorted by price ascending; already hired ones go to the end.
	var defs: Array = []
	for d in Db.MERCS:
		var def: Dictionary = d
		defs.append(def)
	defs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ha := 1 if Game.is_hired(String(a["id"])) else 0
		var hb := 1 if Game.is_hired(String(b["id"])) else 0
		if ha != hb:
			return ha < hb
		return int(a["cost"]) < int(b["cost"]))
	for d2 in defs:
		var def2: Dictionary = d2
		_list.add_child(_make_row(def2))

	_budget_lbl.text = _fmt(Game.budget)
	for c in _team_box.get_children():
		c.queue_free()
	_team_box.add_child(UiTheme.lbl("TEAM  (%d/%d)" % [Game.team.size(), Game.TEAM_MAX], 14, UiTheme.COL_DIM))
	if Game.team.is_empty():
		_team_box.add_child(UiTheme.lbl("— nobody hired yet —", 15, UiTheme.COL_DIM))
	for m in Game.team:
		var mm: Dictionary = m
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var tr := TextureRect.new()
		tr.texture = Assets.portrait(mm["portrait"])
		tr.custom_minimum_size = Vector2(44, 44)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tr)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		vb.add_child(UiTheme.lbl("\"%s\"" % mm["nick"], 17))
		vb.add_child(UiTheme.lbl(Db.weapon(mm["weapon"])["short"] + " · " + _fmt(int(mm.get("cost_paid", mm["cost"]))), 13, UiTheme.COL_DIM))
		row.add_child(vb)
		# Quick-dismiss (spec §4.2 list-screen polish): small X per hired merc row,
		# uses the same fire path as the list button (refund included).
		var mid := String(mm["id"])
		var xb := UiTheme.btn("✕", _on_fire.bind(mid), 13)
		xb.custom_minimum_size = Vector2(30, 30)
		xb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		xb.tooltip_text = "Dismiss \"%s\" (contract price is refunded)" % String(mm["nick"])
		xb.add_theme_color_override("font_color", UiTheme.COL_RED)
		row.add_child(xb)
		_team_box.add_child(row)
	# An empty squad blocks the START of a mission, which is what this button means
	# in the new-game flow. Coming from the base it only means "go home", and a
	# greyed-out way home would read as a dead end — so it stays live there.
	_start_btn.disabled = Game.team.is_empty() and _return == ""

func _make_row(def: Dictionary) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(def))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)

	var tr := TextureRect.new()
	tr.texture = Assets.portrait(def["portrait"])
	tr.custom_minimum_size = Vector2(76, 76)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(tr)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(mid)
	var w: Dictionary = Db.weapon(def["weapon"])
	mid.add_child(UiTheme.lbl("\"%s\"  %s" % [def["nick"], def["name"]], 19, UiTheme.COL_AMBER))
	var exp_lvl := int(def.get("exp", 1))
	mid.add_child(UiTheme.lbl("HP %d  ·  MRK %d  ·  AGI %d  ·  MED %d  ·  %s" % [def["hp"], def["marks"], def["agi"], def["med"], _rank_word(exp_lvl)], 15))
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
	var gear := "%s · %d mags · %d grenade(s) · %d medkit(s)" % [w["name"], mags, gren, meds]
	mid.add_child(UiTheme.lbl(gear, 14, UiTheme.COL_DIM))
	mid.add_child(UiTheme.lbl("\"" + def["quote"] + "\"", 14, Color(0.7, 0.66, 0.5)))

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
		b = UiTheme.btn("Dismiss", _on_fire.bind(def["id"]), 15)
		b.add_theme_color_override("font_color", UiTheme.COL_RED)
	else:
		b = UiTheme.btn("Hire", _on_hire.bind(def["id"]), 15)
		b.disabled = Game.team.size() >= Game.TEAM_MAX or Game.budget < eff
		if Game.budget < eff:
			b.tooltip_text = "Not enough budget"
		elif Game.team.size() >= Game.TEAM_MAX:
			b.tooltip_text = "Squad is full (%d/%d)" % [Game.team.size(), Game.TEAM_MAX]
	b.custom_minimum_size = Vector2(120, 40)
	side.add_child(b)
	if hired:
		p.modulate = Color(0.78, 0.76, 0.72, 0.85)
	return p

func _on_hire(id: String) -> void:
	var ok := Game.hire(id)
	if ok:
		Sfx.play("ui_confirm")
		Sfx.play_voice(id + "_quote")
	else:
		Sfx.play("ui_error")
	_refresh()
	if not ok:
		_pulse_budget()

func _on_fire(id: String) -> void:
	Game.fire(id)
	Sfx.play("ui_back")
	_refresh()


## Failed purchase (spec §4.2 list-screen polish): the budget display flashes red
## and settles back. Runs after _refresh(), which only rewrites the label's text —
## the node itself survives, so the tween keeps a valid target.
func _pulse_budget() -> void:
	if _budget_lbl == null or not is_instance_valid(_budget_lbl):
		return
	if _budget_tw != null and _budget_tw.is_valid():
		_budget_tw.kill()
	_budget_lbl.modulate = Color(1, 1, 1)
	_budget_tw = create_tween()
	_budget_tw.tween_property(_budget_lbl, "modulate", Color(1.7, 0.32, 0.26), 0.09)
	_budget_tw.tween_property(_budget_lbl, "modulate", Color(1, 1, 1), 0.16)
	_budget_tw.tween_property(_budget_lbl, "modulate", Color(1.7, 0.32, 0.26), 0.09)
	_budget_tw.tween_property(_budget_lbl, "modulate", Color(1, 1, 1), 0.30)


# ------------------------------------------------------------------ Dossier (merc file)
## Own CanvasLayer above everything, exactly centred via CenterContainer.
## Close: click the dimmed background, Esc, or the X button.
func _show_detail(def: Dictionary) -> void:
	_close_detail()
	var id := String(def["id"])

	# Focus trap: freeze the screen behind the card BEFORE the overlay exists, so
	# the overlay's own buttons are never part of the frozen set.
	_freeze_background_focus()

	_overlay = CanvasLayer.new()
	_overlay.layer = 10
	add_child(_overlay)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # eats clicks -> the list behind is locked
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_detail())
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	_card = PanelContainer.new()
	_card.theme = UiTheme.theme()
	_card.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks on the card do not close it
	_card.custom_minimum_size = Vector2(CARD_MAX_W, 0)
	center.add_child(_card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_card.add_child(col)

	# ---------------- Header
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 2)
	col.add_child(head)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	head.add_child(title_row)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_theme_constant_override("separation", 0)
	title_row.add_child(name_box)
	name_box.add_child(UiTheme.header(String(def["name"]).to_upper(), 26))
	var exp_lvl := int(def.get("exp", 1))
	name_box.add_child(UiTheme.lbl("\"%s\"  ·  %s" % [String(def["nick"]), _rank_word(exp_lvl)], 16, UiTheme.COL_DIM))

	var eff := Game.eff_cost(int(def["cost"]))
	var price_box := VBoxContainer.new()
	price_box.add_theme_constant_override("separation", 0)
	title_row.add_child(price_box)
	var price := UiTheme.lbl(_fmt(eff), 30, UiTheme.COL_AMBER)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_box.add_child(price)
	var pl := UiTheme.lbl("contract price", 12, UiTheme.COL_DIM)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_box.add_child(pl)

	var x := UiTheme.btn("✕", _close_detail, 18)
	x.custom_minimum_size = Vector2(44, 40)
	x.tooltip_text = "Close (Esc)"
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_row.add_child(x)

	var rule := ColorRect.new()
	rule.color = UiTheme.COL_EDGE
	rule.custom_minimum_size = Vector2(0, 2)
	head.add_child(rule)

	# ---------------- Content (scrolls on overflow)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 12)
	_scroll.add_child(_body)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	_body.add_child(cols)

	# --- left column: portrait, quote, play
	var lc := VBoxContainer.new()
	lc.custom_minimum_size = Vector2(PORTRAIT_PX, 0)
	lc.add_theme_constant_override("separation", 10)
	cols.add_child(lc)

	var por := TextureRect.new()
	por.texture = Assets.portrait(def["portrait"])
	por.custom_minimum_size = Vector2(PORTRAIT_PX, PORTRAIT_PX)
	por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE   # otherwise the 256px texture forces its own size
	por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	por.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	lc.add_child(por)

	var bubble := PanelContainer.new()
	bubble.add_theme_stylebox_override("panel", UiTheme.box(Color("221808"), UiTheme.COL_EDGE, 10, 1, 10))
	lc.add_child(bubble)
	var q := UiTheme.lbl("\"%s\"" % String(def["quote"]), 15, Color(0.82, 0.78, 0.62))
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.custom_minimum_size = Vector2(PORTRAIT_PX - 30.0, 0)
	bubble.add_child(q)

	var play := UiTheme.btn("▶ Play", func() -> void: Sfx.play_voice(id + "_quote"), 15)
	play.tooltip_text = "Play voice line"
	lc.add_child(play)

	# --- right column: stats, equipment, bio
	var rc := VBoxContainer.new()
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rc.add_theme_constant_override("separation", 10)
	cols.add_child(rc)

	rc.add_child(UiTheme.lbl("ATTRIBUTES", 13, UiTheme.COL_DIM))
	rc.add_child(_stat_bar("HP", float(def["hp"]), 100.0, str(int(def["hp"]))))
	rc.add_child(_stat_bar("MRK", float(def["marks"]), 100.0, str(int(def["marks"]))))
	rc.add_child(_stat_bar("AGI", float(def["agi"]), 100.0, str(int(def["agi"]))))
	rc.add_child(_stat_bar("MED", float(def["med"]), 100.0, str(int(def["med"]))))
	# EXP ran on a 0..6 scale the data never reaches (Db exp is 1..3), so the bar sat
	# permanently in the red band and the gold/green thresholds were unreachable.
	# On the real 1..3 range the SAME colour rule finally means something:
	# Rookie 1/3 = 33 % red, Veteran 2/3 = 67 % gold, Elite 3/3 = 100 % green.
	rc.add_child(_stat_bar("EXP", float(exp_lvl), EXP_MAX, "%d / %d" % [exp_lvl, int(EXP_MAX)]))

	rc.add_child(UiTheme.vspace(4))
	rc.add_child(UiTheme.lbl("EQUIPMENT", 13, UiTheme.COL_DIM))
	for entry in _gear_of(def):
		var e: Array = entry
		rc.add_child(_gear_row(String(e[0]), int(e[1])))

	rc.add_child(UiTheme.vspace(4))
	rc.add_child(UiTheme.lbl("FILE", 13, UiTheme.COL_DIM))
	var bio := UiTheme.lbl(String(def.get("bio", "")), 15)
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.custom_minimum_size = Vector2(200, 0)
	bio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rc.add_child(bio)

	var daily := maxi(1, floori(float(eff) / float(DAYS_PER_CONTRACT)))
	var rate := UiTheme.lbl("Daily rate ≈ %s / day — display only, the full contract price is paid up front." % _fmt(daily), 13, UiTheme.COL_DIM)
	rate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rc.add_child(rate)

	# ---------------- Footer
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	var first_focus: Control = null
	if Game.is_hired(id):
		var fb := UiTheme.btn("Dismiss", _detail_fire.bind(id), 16)
		fb.add_theme_color_override("font_color", UiTheme.COL_RED)
		fb.custom_minimum_size = Vector2(180, 44)
		foot.add_child(fb)
		first_focus = fb
	else:
		var hb := UiTheme.btn("Hire  ·  " + _fmt(eff), _detail_hire.bind(id), 16)
		hb.custom_minimum_size = Vector2(220, 44)
		hb.disabled = Game.team.size() >= Game.TEAM_MAX or Game.budget < eff
		if Game.budget < eff:
			hb.tooltip_text = "Not enough budget"
		elif Game.team.size() >= Game.TEAM_MAX:
			hb.tooltip_text = "Squad is full (%d/%d)" % [Game.team.size(), Game.TEAM_MAX]
		foot.add_child(hb)
		if not hb.disabled:
			first_focus = hb
	var cb := UiTheme.btn("Close (Esc)", _close_detail, 16)
	cb.custom_minimum_size = Vector2(170, 44)
	foot.add_child(cb)
	if first_focus == null:
		first_focus = cb

	# Height of the fixed card parts (header + footer + margins) for the scroll clamp.
	_chrome_h = head.get_combined_minimum_size().y + foot.get_combined_minimum_size().y + 60.0
	_body.resized.connect(_fit_dossier)
	_fit_dossier()
	_fit_dossier.call_deferred()

	# Pull the keyboard focus INTO the card. Deferred: the control has to be inside
	# the tree and laid out before grab_focus() has any effect.
	_grab_into_card.call_deferred(first_focus)

	Sfx.play_voice(id + "_select")


## ---------------------------------------------------------------- Focus trap

## Move the keyboard focus into the open dossier card (spec §4.2 point 3).
func _grab_into_card(c: Control) -> void:
	if _overlay == null or c == null or not is_instance_valid(c):
		return
	if c.focus_mode == Control.FOCUS_NONE:
		return
	c.grab_focus()


## Remember and disable every focusable control of the screen behind the overlay,
## so Tab/arrow navigation cannot leave the dossier. The CanvasLayer of the overlay
## itself is skipped (and does not exist yet when this runs on open).
func _freeze_background_focus() -> void:
	_focus_frozen.clear()
	_focus_prev = get_viewport().gui_get_focus_owner()
	_freeze_walk(self)


func _freeze_walk(n: Node) -> void:
	for child in n.get_children():
		if child is CanvasLayer:
			continue
		if child is Control:
			var c: Control = child
			if c.focus_mode != Control.FOCUS_NONE:
				_focus_frozen.append([c, int(c.focus_mode)])
				c.focus_mode = Control.FOCUS_NONE
		_freeze_walk(child)


## Restore the focus modes taken away on open and hand the focus back to whatever
## held it before. Nodes freed in the meantime (the list is rebuilt by _refresh)
## are simply skipped.
func _thaw_background_focus() -> void:
	for e in _focus_frozen:
		var pair: Array = e
		var c: Control = pair[0]
		if is_instance_valid(c):
			c.focus_mode = int(pair[1])
	_focus_frozen.clear()
	var prev := _focus_prev
	_focus_prev = null
	if prev != null and is_instance_valid(prev) and prev.focus_mode != Control.FOCUS_NONE:
		prev.grab_focus()


## One stat row: name · bar (colour by percentage) · number.
func _stat_bar(name_txt: String, value: float, vmax: float, value_txt: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var n := UiTheme.lbl(name_txt, 14, UiTheme.COL_DIM)
	n.custom_minimum_size = Vector2(46, 0)
	n.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(n)

	var pct := 0.0
	if vmax > 0.0:
		pct = clampf(value / vmax, 0.0, 1.0) * 100.0
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = pct
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(90, 18)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("background", UiTheme.box(Color("221808"), Color("5a4426"), 3, 1, 2))
	bar.add_theme_stylebox_override("fill", UiTheme.box(_bar_col(pct), Color(0, 0, 0, 0), 3, 0, 2))
	row.add_child(bar)

	var v := UiTheme.lbl(value_txt, 14)
	v.custom_minimum_size = Vector2(52, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(v)
	return row


## One equipment row with icon.
func _gear_row(item_id: String, count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var ic := TextureRect.new()
	ic.texture = Assets.item_icon(item_id)
	ic.custom_minimum_size = Vector2(30, 30)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var nm_txt := item_id
	if Db.ITEMS.has(item_id):
		nm_txt = String(Db.item(item_id).get("name", item_id))
	var nm := UiTheme.lbl(nm_txt, 14)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(nm)
	if count > 1:
		var cl := UiTheme.lbl("×%d" % count, 14, UiTheme.COL_AMBER)
		cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cl)
	return row


## Fit the card to the window: max. 620 wide, max. 82 % of the height.
func _fit_dossier() -> void:
	if _overlay == null or not is_instance_valid(_card) or not is_instance_valid(_scroll):
		return
	var vp := get_viewport_rect().size
	var want_w := minf(CARD_MAX_W, maxf(320.0, vp.x - 48.0))
	if absf(_card.custom_minimum_size.x - want_w) > 0.5:
		_card.custom_minimum_size.x = want_w
	var avail := maxf(160.0, vp.y * CARD_MAX_H_FRAC - _chrome_h)
	# Use the minimum height only: it depends solely on the width, not on the scroll
	# height set here -> no feedback loop through the resized signal.
	var need := _body.get_combined_minimum_size().y
	var want_h := clampf(need, 120.0, avail)
	if absf(_scroll.custom_minimum_size.y - want_h) > 1.0:
		_scroll.custom_minimum_size.y = want_h


func _detail_hire(id: String) -> void:
	_close_detail()
	_on_hire(id)


func _detail_fire(id: String) -> void:
	_close_detail()
	_on_fire(id)


func _close_detail() -> void:
	if _overlay != null:
		if is_instance_valid(_body) and _body.resized.is_connected(_fit_dossier):
			_body.resized.disconnect(_fit_dossier)
		_overlay.queue_free()
	_overlay = null
	_card = null
	_scroll = null
	_body = null
	# Release the focus trap last: the overlay is already gone, so the restored
	# focus cannot land on a control that is about to be freed.
	_thaw_background_focus()


func _unhandled_input(ev: InputEvent) -> void:
	if _overlay != null and ev.is_action_pressed("ui_cancel"):
		_close_detail()
		get_viewport().set_input_as_handled()

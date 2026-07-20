class_name SavePanel
extends CanvasLayer
## Reusable centered save/load slot overlay (SPEC v5 §4.4).
##
## Built exactly like the hire dossier: CanvasLayer -> Control (FULL_RECT) ->
## dim ColorRect (alpha 0.55, swallows clicks) -> CenterContainer -> PanelContainer.
## Offers the autosave plus the manual slots 1..MANUAL_SLOTS, shows title, date,
## day, sector and the team portrait thumbs per slot. Overwriting asks first;
## damaged and version-incompatible slots render disabled.
##
## Usage from anywhere (main menu, base panel, pause menu):
##     SavePanel.open(self, "save", func(res: Dictionary) -> void: print(res))
## The callback receives ONE Dictionary:
##     {"action": "load"|"save"|"cancel", "slot": int, "ok": bool}
## ("slot" is -1 when the player cancelled.) The same payload is emitted as the
## `closed` signal, so a caller may connect instead of passing a Callable.

signal closed(result: Dictionary)

## SPEC v5 §4.4: 3 manual slots + autosave.
const MANUAL_SLOTS := 3
const CARD_W := 660.0
const LIST_H := 330.0
const THUMB := 44.0

## "save" or "load" — set before the node enters the tree.
@export var mode := "load"

var _on_done := Callable()
var _root: Control = null
var _list: VBoxContainer = null
var _hint: Label = null
var _confirm: Control = null
var _closing := false

## Dead-simple entry point. Adds the overlay to `parent` and returns it.
## `mode` is "save" or "load"; anything else is treated as "load".
static func open(parent: Node, mode_in: String, on_done: Callable) -> Node:
	var p := SavePanel.new()
	p.mode = "save" if mode_in == "save" else "load"
	p._on_done = on_done
	if parent != null:
		parent.add_child(p)
	return p

func _ready() -> void:
	layer = 20
	_build()

func is_save_mode() -> bool:
	return mode == "save"

# ------------------------------------------------------------------ Structure

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP   # catches clicks: the screen behind is locked
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_cancel())
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var card := PanelContainer.new()
	card.theme = UiTheme.theme()
	card.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks on the card must not close it
	card.custom_minimum_size = Vector2(CARD_W, 0)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	# ---------------- header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	head.add_child(UiTheme.header("SAVE GAME" if is_save_mode() else "LOAD GAME", 28))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var x := UiTheme.btn("✕", _cancel, 18)
	x.custom_minimum_size = Vector2(44, 38)
	x.tooltip_text = "Close (Esc)"
	head.add_child(x)

	var rule := ColorRect.new()
	rule.color = UiTheme.COL_EDGE
	rule.custom_minimum_size = Vector2(0, 2)
	col.add_child(rule)

	# ---------------- slot list
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, LIST_H)
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	# ---------------- footer
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 10)
	col.add_child(foot)
	_hint = UiTheme.lbl(
		"Pick a slot to save into." if is_save_mode() else "Pick a save to load.",
		14, UiTheme.COL_DIM)
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_hint)
	var close_btn := UiTheme.btn("CLOSE (Esc)", _cancel, 16)
	close_btn.custom_minimum_size = Vector2(170, 42)
	foot.add_child(close_btn)

	_rebuild()

func _rebuild() -> void:
	if _list == null:
		return
	# remove_child FIRST: queue_free only takes effect at the end of the frame,
	# so the old rows would still occupy the container next to the new ones.
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_list.add_child(_row(Game.AUTOSAVE_SLOT))
	for slot in range(1, MANUAL_SLOTS + 1):
		_list.add_child(_row(slot))

func _slot_name(slot: int) -> String:
	return "AUTOSAVE" if slot == Game.AUTOSAVE_SLOT else "SLOT %d" % slot

# ------------------------------------------------------------------ One slot row

func _row(slot: int) -> PanelContainer:
	var info := Game.save_info(slot)
	var damaged := bool(info.get("damaged", false))
	var incompatible := bool(info.get("incompatible", false))
	var empty := info.is_empty()
	var broken := damaged or incompatible

	var p := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(col)

	if empty:
		col.add_child(UiTheme.lbl(_slot_name(slot), 19, UiTheme.COL_DIM))
		col.add_child(UiTheme.lbl("— empty —", 14, UiTheme.COL_DIM))
	elif damaged:
		col.add_child(UiTheme.lbl("%s   ·   DAMAGED" % _slot_name(slot), 19, UiTheme.COL_RED))
		col.add_child(UiTheme.lbl("This file is unreadable and cannot be loaded.",
			14, UiTheme.COL_DIM))
	elif incompatible:
		col.add_child(UiTheme.lbl("%s   ·   INCOMPATIBLE" % _slot_name(slot), 19, UiTheme.COL_RED))
		col.add_child(UiTheme.lbl("Saved by another version (v%d) — cannot be loaded."
			% int(info.get("version", 0)), 14, UiTheme.COL_DIM))
	else:
		var title := String(info.get("title", ""))
		if title == "":
			title = String(info.get("label", ""))
		var head_txt := "%s   ·   %s" % [_slot_name(slot), title]
		if bool(info.get("demo_finished", false)):
			head_txt += "   ·   DEMO COMPLETE"
		col.add_child(UiTheme.lbl(head_txt, 19, UiTheme.COL_AMBER))
		var team: Array = info.get("team", [])
		var parts := PackedStringArray()
		for n in team:
			parts.append(String(n))
		var who := ", ".join(parts) if parts.size() > 0 else "no team"
		col.add_child(UiTheme.lbl("Day %d   ·   Sector %s — %s   ·   %s" % [
			int(info.get("day", 1)), String(info.get("sector", "")),
			String(info.get("sector_name", "")), String(info.get("difficulty", ""))],
			14, UiTheme.COL_TEXT))
		col.add_child(UiTheme.lbl("%d $   ·   %s" % [int(info.get("budget", 0)), who],
			14, UiTheme.COL_TEXT))
		col.add_child(UiTheme.lbl("%s   ·   %s played" % [
			String(info.get("saved_at_text", "")), _playtime(info)], 12, UiTheme.COL_DIM))
		var thumbs := _thumbs(info)
		if thumbs != null:
			h.add_child(thumbs)

	# ---------------- actions
	var side := VBoxContainer.new()
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	side.add_theme_constant_override("separation", 6)
	h.add_child(side)

	var act: Button
	if is_save_mode():
		act = UiTheme.btn("SAVE" if empty else "OVERWRITE", _on_save_pressed.bind(slot), 16)
		# Broken files stay untouched until the player deletes them, and the
		# autosave slot belongs to the game, not to the manual save panel.
		if broken:
			act.disabled = true
			act.tooltip_text = "This slot must be deleted before it can be reused."
		elif slot == Game.AUTOSAVE_SLOT:
			act.disabled = true
			act.tooltip_text = "The game writes the autosave itself."
	else:
		act = UiTheme.btn("LOAD", _on_load_pressed.bind(slot), 16)
		act.disabled = empty or broken
		if broken:
			act.tooltip_text = "This save cannot be loaded."
	act.custom_minimum_size = Vector2(130, 38)
	side.add_child(act)

	if not empty:
		var del := UiTheme.btn("DELETE", _on_delete_pressed.bind(slot), 14)
		del.custom_minimum_size = Vector2(130, 32)
		side.add_child(del)

	if broken:
		p.modulate = Color(1.0, 0.86, 0.86, 0.9)
	return p

func _playtime(info: Dictionary) -> String:
	var total := int(float(info.get("playtime_sec", 0.0)))
	var h := total / 3600
	var m := (total % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm" % m

## Portrait thumbs of the saved squad. EXPAND_IGNORE_SIZE is mandatory —
## without it the 256 px source texture blows the row apart.
func _thumbs(info: Dictionary) -> HBoxContainer:
	var ids: Array = info.get("team_ids", [])
	if ids.is_empty():
		return null
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for raw in ids:
		var mid := String(raw)
		var def := Db.merc_def(mid)
		if def.is_empty() or typeof(def.get("portrait")) != TYPE_DICTIONARY:
			continue
		var tr := TextureRect.new()
		tr.texture = Assets.portrait(def["portrait"])
		tr.custom_minimum_size = Vector2(THUMB, THUMB)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tr.tooltip_text = String(def.get("nick", mid))
		box.add_child(tr)
	if box.get_child_count() == 0:
		box.queue_free()
		return null
	return box

# ------------------------------------------------------------------ Actions

func _on_load_pressed(slot: int) -> void:
	if not Game.load_game(slot):
		Sfx.play("ui_error")
		_set_hint("%s could not be loaded." % _slot_name(slot), UiTheme.COL_RED)
		_rebuild()
		return
	Sfx.play("ui_confirm")
	_finish("load", slot, true)

func _on_save_pressed(slot: int) -> void:
	if Game.save_info(slot).is_empty():
		_do_save(slot)
		return
	_ask_confirm("Overwrite %s?" % _slot_name(slot), _do_save.bind(slot))

func _do_save(slot: int) -> void:
	if not Game.save_game(slot):
		Sfx.play("ui_error")
		_set_hint("Saving failed — the previous save is untouched.", UiTheme.COL_RED)
		_rebuild()
		return
	Sfx.play("ui_confirm")
	_finish("save", slot, true)

func _on_delete_pressed(slot: int) -> void:
	_ask_confirm("Delete %s?" % _slot_name(slot), _do_delete.bind(slot))

func _do_delete(slot: int) -> void:
	Game.delete_save(slot)
	Sfx.play("ui_click")
	_set_hint("%s deleted." % _slot_name(slot), UiTheme.COL_DIM)
	_rebuild()

func _set_hint(txt: String, col: Color) -> void:
	if _hint == null:
		return
	_hint.text = txt
	_hint.add_theme_color_override("font_color", col)

# ------------------------------------------------------------------ Confirmation

## Small nested confirm box — same overlay technique, one layer further in.
func _ask_confirm(question: String, on_yes: Callable) -> void:
	_close_confirm()
	if _root == null:
		return

	_confirm = Control.new()
	_confirm.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_confirm)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_close_confirm())
	_confirm.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm.add_child(center)

	var box := PanelContainer.new()
	box.theme = UiTheme.theme()
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	box.add_child(v)
	var q := UiTheme.lbl(question, 19, UiTheme.COL_TEXT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(q)
	var note := UiTheme.lbl("This cannot be undone.", 13, UiTheme.COL_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(note)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	# The lambda is bound to a variable first: a multi-line lambda used as a
	# NON-final call argument does not parse.
	var accept := func() -> void:
		_close_confirm()
		if on_yes.is_valid():
			on_yes.call()
	var yes := UiTheme.btn("YES", accept, 17)
	yes.custom_minimum_size = Vector2(150, 42)
	row.add_child(yes)
	var no := UiTheme.btn("CANCEL", _close_confirm, 17)
	no.custom_minimum_size = Vector2(150, 42)
	row.add_child(no)

func _close_confirm() -> void:
	if is_instance_valid(_confirm):
		_confirm.queue_free()
	_confirm = null

# ------------------------------------------------------------------ Closing

func _cancel() -> void:
	_finish("cancel", -1, false)

func _finish(action: String, slot: int, ok: bool) -> void:
	if _closing:
		return
	_closing = true
	var result := {"action": action, "slot": slot, "ok": ok}
	var cb := _on_done
	_on_done = Callable()
	closed.emit(result)
	queue_free()
	if cb.is_valid():
		cb.call(result)

func _unhandled_input(ev: InputEvent) -> void:
	if _closing:
		return
	if ev.is_action_pressed("ui_cancel"):
		if is_instance_valid(_confirm):
			_close_confirm()
		else:
			_cancel()
		get_viewport().set_input_as_handled()

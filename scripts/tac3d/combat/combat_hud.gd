class_name CombatHud
extends CanvasLayer
## JA1 HUD view for the 3D battle (branch A). Ports the layout from
## scripts/screens/tactical.gd (_build_hud / _build_slot / refresh_hud / _update_enemy_label)
## 1:1 onto the Tac3D orchestrator. NO signal bus: the orchestrator holds `hud` and calls
## `refresh()` after every action; the HUD holds `orch` and triggers actions via Callable(orch,"ui_*").
##
## FIX C1: the pause panel AND the inventory panel are parented under `_root` (a Control below
## the CanvasLayer). A Control placed directly under the Node3D orchestrator would have no canvas
## transform and would NOT be drawn. Therefore toggle_pause()/toggle_inventory() live here in the
## HUD, and the orchestrator only delegates (ui_menu -> hud.toggle_pause, ui_inventory -> hud.toggle_inventory).
##
## GDScript traps: apply PRESET_FULL_RECT ONLY via set_anchors_and_offsets_preset (size-0 trap);
## build(orch) takes orch UNTYPED (cyclic-dependency trap); typed Variant iteration; pull integer
## values exclusively from orch.*/Db.* (identical balance).

var orch = null                       # Orchestrator (UNTYPED — cyclic-dependency trap)

# Phase 7 — dialog/base panel signals (emitted from button callbacks)
signal dialog_next
signal dialog_choice(idx: int)
signal base_closed

# Phase 7 — W1: while a modal panel (Vargo dialog/base) is open, the orchestrator
# swallows its hotkeys (_unhandled_input: `if hud.modal_active: return`).
var modal_active := false

var _root: Control
var _top_label: Label
var _enemy_label: Label
var _weapon_label: Label
var _ammo_label: Label
var _mags_label: Label
var _reload_btn: Button
var _aim_btn: Button
var _grenade_btn: Button
var _medkit_btn: Button
var _stance_btn: Button
var _inv_btn: Button
var _endturn_btn: Button
var _menu_btn: Button
var _cursor_panel: PanelContainer
var _cursor_label: Label
var _banner_label: Label
var _slots: Array = []                 # [{btn,hp,ap,erf,wicon,wlbl}, ...] for orch.mercs
var _sel_slot := -1                    # index of the selected card (test getter has_selected_frame)

# JA2 squad bar: ONE continuous bar along the bottom. All merc cards sit side by
# side in _mercbox; rebuild_slots() (after Otto's rescue) clears and refills it.
# Replaces the earlier portrait side bars (left/right).
var _mercbox: HBoxContainer

var _pause_panel: Control = null
var _inv_panel: PanelContainer = null
var _inv_sel := -1

# Spotting popup (portrait + quip, JA style) + multi-select rectangle
var _speaker_panel: PanelContainer = null
var _speaker_tw: Tween = null
var _select_rect: Panel = null
var _crosshair: CrosshairView = null   # JA2 crosshair drawn over the targeted enemy
var _inv_tab := 0                              # 0 = INVENTORY, 1 = STATS (BiA tabs)
var _doll_view: SubViewportContainer = null    # 3D paper-doll preview (cached, see _ensure_doll)
var _doll_key := ""                            # "charId|weaponModel" of the current doll (rebuild check)
var _grid_texture: ImageTexture = null         # grid background of the doll area
var _bia_theme_c: Theme = null                 # olive theme of the inventory panel (lazy)

# "Back in Action" palette: olive-green panels, khaki borders, yellow = selection,
# green = equipped weapon. Applies ONLY inside the inventory panel (its own sub-theme) —
# the rest of the HUD keeps the brown JA1 leather theme.
const BIA_BG := Color("323a2e")
const BIA_DARK := Color("232a21")
const BIA_SLOT := Color("1b221a")
const BIA_EDGE := Color("77826a")
const BIA_YELLOW := Color("e3c13d")
const BIA_GREEN_BG := Color("46613a")
const BIA_GREEN_EDGE := Color("7ea05e")
const BIA_TEXT := Color("dce3cf")
const BIA_DIM := Color("97a289")

# spec §2 — display names of the demo sectors. The top label used to hardcode
# "SECTOR F3 · ROOKHAVEN" in BOTH branches, so the F4 landing zone announced itself
# as Rookhaven and the label never changed after the west transition. It is now
# driven from the orchestrator's live `sector`; unknown ids fall back to the raw id.
const SECTOR_NAMES := {
	"F4": "LANDING ZONE",
	"F3": "ROOKHAVEN",
}

# The Hideout (spec §3.3.5 / §5.3) — the cellar becomes the home base after the
# rescue. RE-ENTERABLE: `_base_layer` is the open-panel guard, not a one-shot flag,
# so show_base_panel() can be called again from the HUD button at any later point.
var _base_layer: Control = null
var _base_body: VBoxContainer = null
var _base_note: Label = null
var _base_msg := ""                      # survives a tab switch (the label does not)
var _base_tab := 0                       # 0 = SERVICES, 1 = STASH
var _base_carrier := 0                   # index into orch.mercs — whose pack the stash tab edits
var _base_btn: Button = null             # HUD action-bar entry into the base

# Save panel (package D, scripts/ui/save_panel.gd) is loaded LATE and defensively:
# it may not exist yet when this file runs. Never hard-preload it.
const SAVE_PANEL_SCRIPT := "res://scripts/ui/save_panel.gd"


# ================================================================= Construction

func build(o) -> void:
	orch = o
	layer = 10

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)

	# Top bar
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 20)
	top.add_child(th)
	_top_label = UiTheme.lbl("", 16, UiTheme.COL_AMBER)
	th.add_child(_top_label)
	var sp1 := Control.new()
	sp1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp1)
	_enemy_label = UiTheme.lbl("", 15)
	th.add_child(_enemy_label)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(sp2)
	th.add_child(UiTheme.lbl("[Tab] Merc  [Right-click/A] Aim  [T] Zone  [C] Stance  [G] Grenade  [R] Reload  [H] Medkit  [I] Inventory  [Enter] Turn  ·  [Q/E] Rotate  [Wheel] Zoom", 12, UiTheme.COL_DIM))

	# ===== JA2 squad bar at the bottom: ONE continuous bar =====
	# Left: the merc cards (portrait + HP/AP/XP bars + each merc's own weapon icon
	# and ammo PER MERC). Right: the weapon readout + the action buttons of the
	# selected merc. Full width at the bottom, brown leather theme like the rest.
	_slots = []
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_left = 6.0
	bar.offset_right = -6.0
	bar.offset_top = -140.0
	bar.offset_bottom = -6.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bar)
	var barrow := HBoxContainer.new()
	barrow.add_theme_constant_override("separation", 12)
	bar.add_child(barrow)

	# --- Merc cards (row) ---
	_mercbox = HBoxContainer.new()
	_mercbox.add_theme_constant_override("separation", 6)
	_mercbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	barrow.add_child(_mercbox)
	for i in orch.mercs.size():
		_mercbox.add_child(_build_slot(i))

	# --- Stretch gap between the squad (left) and the actions (right) ---
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	barrow.add_child(gap)

	# --- Action area (right): weapon readout + buttons of the selected merc ---
	var act := VBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	barrow.add_child(act)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 14)
	act.add_child(wrow)
	_weapon_label = UiTheme.lbl("", 16, UiTheme.COL_AMBER)
	wrow.add_child(_weapon_label)
	_ammo_label = UiTheme.lbl("", 16)
	wrow.add_child(_ammo_label)
	_mags_label = UiTheme.lbl("", 14, UiTheme.COL_DIM)
	wrow.add_child(_mags_label)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	act.add_child(brow)
	_reload_btn = UiTheme.btn("Reload (R)", Callable(orch, "ui_reload"), 13)
	brow.add_child(_reload_btn)
	_aim_btn = UiTheme.btn("Aim (A)", Callable(orch, "ui_aim"), 13)
	brow.add_child(_aim_btn)
	_grenade_btn = UiTheme.btn("Grenade (G)", Callable(orch, "ui_grenade_mode"), 13)
	_grenade_btn.icon = Assets.item_icon("granate")
	brow.add_child(_grenade_btn)
	_medkit_btn = UiTheme.btn("Medkit (H)", Callable(orch, "ui_medkit"), 13)
	_medkit_btn.icon = Assets.item_icon("medkit")
	brow.add_child(_medkit_btn)
	_stance_btn = UiTheme.btn("Standing (C)", Callable(orch, "ui_stance"), 13)
	brow.add_child(_stance_btn)
	_inv_btn = UiTheme.btn("Inventory (I)", Callable(orch, "ui_inventory"), 13)
	brow.add_child(_inv_btn)
	var brow2 := HBoxContainer.new()
	brow2.add_theme_constant_override("separation", 8)
	act.add_child(brow2)
	_endturn_btn = UiTheme.btn("END TURN (Enter)", Callable(orch, "ui_end_turn"), 14)
	_endturn_btn.custom_minimum_size = Vector2(230, 0)
	brow2.add_child(_endturn_btn)
	# The Hideout is re-enterable: this button reopens the base panel any time after
	# the rescue, instead of the old one-shot modal that only fired from free_otto().
	_base_btn = UiTheme.btn("The Hideout", open_hideout, 13)
	brow2.add_child(_base_btn)
	_menu_btn = UiTheme.btn("Menu (Esc)", Callable(orch, "ui_menu"), 13)
	brow2.add_child(_menu_btn)

	# Cursor info (tooltip)
	_cursor_panel = PanelContainer.new()
	_cursor_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_panel.visible = false
	_cursor_panel.z_index = 90
	_root.add_child(_cursor_panel)
	_cursor_label = UiTheme.lbl("", 14)
	_cursor_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_panel.add_child(_cursor_label)

	# Banner
	_banner_label = UiTheme.header("", 38)
	_banner_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner_label.offset_top = 140.0
	_banner_label.offset_bottom = 200.0
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.modulate.a = 0.0
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_banner_label)


func _build_slot(i: int) -> Button:
	var m: Tac3DUnit = orch.mercs[i]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 106)
	btn.pressed.connect(Callable(orch, "ui_select_slot").bind(i))
	# Style the card frame ourselves (more compact than the default leather button
	# padding): normal = subdued dark, selected/pressed = gold frame, hover = hinted.
	btn.add_theme_stylebox_override("normal", _card_box(false))
	btn.add_theme_stylebox_override("hover", UiTheme.box(Color("3a2c19"), UiTheme.COL_AMBER, 4, 2, 6))
	btn.add_theme_stylebox_override("pressed", _card_box(true))
	btn.add_theme_stylebox_override("disabled", _card_box(false))
	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 2)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(inner)
	# JA1 look: crisp frame around bars + picture, bars vertical on the LEFT inside the frame
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", UiTheme.box(Color(0.09, 0.06, 0.03), Color(0.48, 0.35, 0.18), 2, 2, 3))
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(frame)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(row)
	var hpb := _vbar(UiTheme.COL_RED, m.hp_max(), m.hp())
	row.add_child(hpb)
	var apb := _vbar(Color(0.3, 0.5, 0.85), m.ap_max, m.ap)
	row.add_child(apb)
	var erfb := _vbar(UiTheme.COL_AMBER, 6, 1)
	row.add_child(erfb)
	var por := TextureRect.new()
	por.texture = Assets.portrait(m.data["portrait"])
	por.custom_minimum_size = Vector2(54, 54)
	por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	por.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	por.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(por)
	var nm := UiTheme.lbl("\"%s\"" % m.data["nick"], 13, UiTheme.COL_AMBER)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(nm)
	# Weapon PER MERC (JA2 style): icon + short name + ammo.
	# For downed mercs this row is recoloured into a status readout (DOWN).
	var wrow := HBoxContainer.new()
	wrow.alignment = BoxContainer.ALIGNMENT_CENTER
	wrow.add_theme_constant_override("separation", 4)
	wrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(wrow)
	var wicon := TextureRect.new()
	wicon.custom_minimum_size = Vector2(26, 18)
	wicon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wicon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wicon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrow.add_child(wicon)
	var wlbl := UiTheme.lbl("", 12, UiTheme.COL_DIM)
	wlbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrow.add_child(wlbl)
	_slots.append({"btn": btn, "hp": hpb, "ap": apb, "erf": erfb, "wicon": wicon, "wlbl": wlbl})
	return btn


## Vertical status bar (JA1 card): narrow, fills from the bottom upwards.
func _vbar(col: Color, maxv: float, val: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	b.custom_minimum_size = Vector2(8, 52)
	b.max_value = maxv
	b.value = val
	b.show_percentage = false
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_theme_stylebox_override("background", UiTheme.box(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), 2, 0, 1))
	b.add_theme_stylebox_override("fill", UiTheme.box(col, Color(0, 0, 0, 0), 2, 0, 1))
	return b


## Card background: selected = gold frame (brighter), otherwise subdued dark brown.
## has_selected_frame() no longer reads the selection from the StyleBox (both states
## set "normal") but from _sel_slot — which leaves the look free to be restyled.
func _card_box(selected: bool) -> StyleBoxFlat:
	if selected:
		return UiTheme.box(Color("5e4828"), UiTheme.COL_AMBER, 4, 3, 6)
	return UiTheme.box(Color("241a0e"), UiTheme.COL_EDGE, 4, 1, 6)


# ================================================================= Refresh (workhorse)

## "SECTOR <id> · <NAME>" from the orchestrator's LIVE sector (spec §2). load_sector()
## already calls hud.refresh() after switching, so the label follows the west
## transition F4 -> F3 without any extra wiring.
func _sector_title() -> String:
	var id := "?"
	if orch != null:
		var s = orch.get("sector")
		if s != null and String(s) != "":
			id = String(s)
	return "SECTOR %s · %s" % [id, String(SECTOR_NAMES.get(id, id))]


func refresh() -> void:
	if _slots.is_empty():
		return
	var head_txt := _sector_title()
	if orch.combat_started:
		_top_label.text = "%s — Turn %d — %s" % [head_txt, orch.turn, "Your turn" if orch.player_turn else "Enemy phase"]
	else:
		_top_label.text = "%s — APPROACH — move freely · drag a box: select group · Ctrl+click: aim" % head_txt
	var seen := 0
	var total := 0
	for e in orch.enemies:
		var en: Tac3DUnit = e
		if en.alive:
			total += 1
			if en.seen:
				seen += 1
	_enemy_label.text = "Enemies: %d spotted · %d remaining" % [seen, total]
	_sel_slot = -1
	for i in _slots.size():          # W2: iterate over _slots (not mercs) -> never out of bounds
		var m: Tac3DUnit = orch.mercs[i]
		var sb: Dictionary = _slots[i]
		sb["hp"].max_value = m.hp_max()
		sb["hp"].value = m.hp()
		sb["ap"].max_value = m.ap_max
		sb["ap"].value = m.ap
		sb["erf"].value = orch.level_of(m)
		var mw: Dictionary = Db.weapon(m.data["weapon"])
		sb["btn"].tooltip_text = "%s  ·  HP %d/%d · AP %d · St.%d" % [String(mw["name"]), m.hp(), m.hp_max(), m.ap, orch.level_of(m)]
		# Weapon per merc (JA2): icon + short name + ammo; for downed mercs = status.
		if m.alive:
			sb["wicon"].texture = Assets.item_icon(String(m.data["weapon"]))
			sb["wicon"].modulate = Color(1, 1, 1)
			sb["wlbl"].text = "%s %d/%d" % [String(mw.get("short", mw["name"])), int(m.data["ammo"]), int(mw["mag"])]
			sb["wlbl"].add_theme_color_override("font_color", UiTheme.COL_DIM)
			sb["btn"].disabled = false
			sb["btn"].modulate = Color(1, 1, 1)
		else:
			sb["wicon"].texture = null
			sb["wlbl"].text = "DOWN"
			sb["wlbl"].add_theme_color_override("font_color", UiTheme.COL_RED)
			sb["btn"].disabled = true
			sb["btn"].modulate = Color(0.55, 0.4, 0.4, 0.7)
		# Selection: gold frame + _sel_slot (test getter). Both states set "normal".
		var is_sel: bool = (m == orch.selected)
		if is_sel:
			_sel_slot = i
		sb["btn"].add_theme_stylebox_override("normal", _card_box(is_sel))
	var sel: Tac3DUnit = orch.selected
	if sel != null and sel.alive:
		var w: Dictionary = Db.weapon(sel.data["weapon"])
		var can: bool = orch.player_turn and not orch.busy
		_weapon_label.text = String(w["name"])
		_ammo_label.text = "Ammo %d/%d" % [int(sel.data["ammo"]), int(w["mag"])]
		_mags_label.text = "Mags ×%d · Grenades ×%d · Medkits ×%d" % [orch.mags_for(sel), orch.inv_count(sel, "granate"), orch.inv_count(sel, "medkit")]
		_reload_btn.disabled = not can or sel.ap < int(w["reload"]) or int(sel.data["ammo"]) >= int(w["mag"]) or orch.mags_for(sel) <= 0
		_reload_btn.icon = Assets.item_icon("mag_" + String(w["cal"]))
		_aim_btn.text = ("Aim ×%d (A)" % orch.aim_level) if orch.aim_level > 0 else "Aim (A)"
		_aim_btn.disabled = not can
		_aim_btn.modulate = Color(1.0, 0.8, 0.45) if orch.aim_level > 0 else Color(1, 1, 1)
		_grenade_btn.text = "Grenade ×%d (G)" % orch.inv_count(sel, "granate")
		_grenade_btn.disabled = not can or orch.inv_count(sel, "granate") <= 0 or sel.ap < int(Db.GRENADE["ap"])
		_grenade_btn.modulate = Color(1.0, 0.75, 0.4) if orch.mode == "grenade" else Color(1, 1, 1)
		_medkit_btn.text = "Medkit ×%d (H)" % orch.inv_count(sel, "medkit")
		_medkit_btn.disabled = not can or orch.inv_count(sel, "medkit") <= 0 or sel.ap < Db.MEDKIT_AP
		_stance_btn.text = "%s (C)" % String(Db.STANCES[sel.stance]["name"])
		_stance_btn.disabled = not can
		_stance_btn.modulate = Color(0.75, 0.9, 1.0) if sel.stance != "stand" else Color(1, 1, 1)
		_inv_btn.disabled = not can
	_endturn_btn.disabled = not orch.player_turn or orch.busy or not orch.combat_started
	if _base_btn != null:
		var base_open: bool = Game.base_unlocked
		_base_btn.disabled = not base_open
		_base_btn.tooltip_text = "Heal, resupply, stash and save" if base_open \
			else "The Hideout opens once Tobias Rook is freed."
	if _inv_panel != null:
		_inv_refresh()


# ================================================================= Thin API

func set_selected(_u) -> void:
	refresh()


func set_mode(_m) -> void:
	refresh()


func set_cursor(text: String, screen_pos: Vector2) -> void:
	if text == "":
		_cursor_panel.visible = false
		return
	_cursor_label.text = text
	_cursor_panel.visible = true
	_cursor_panel.position = screen_pos + Vector2(18, 16)


func hide_cursor() -> void:
	if _cursor_panel != null:
		_cursor_panel.visible = false


func banner(text: String, dur := 1.4) -> void:
	if _banner_label == null:
		return
	_banner_label.text = text
	_banner_label.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_banner_label, "modulate:a", 1.0, 0.18)
	tw.tween_interval(dur)
	tw.tween_property(_banner_label, "modulate:a", 0.0, 0.35)


# ================================================================= Spotting: speaker popup

## JA style: on a spotting it is the MERC himself who is shown (portrait + name +
## quip) instead of a "!" marker. Pops up bottom left, holds briefly, fades out.
## A second call replaces the popup that is currently running.
func show_speaker(u, text: String, dur := 2.2) -> void:
	if _root == null or u == null:
		return
	if _speaker_panel != null:
		if _speaker_tw != null:
			_speaker_tw.kill()
		_speaker_panel.queue_free()
		_speaker_panel = null
	_speaker_panel = PanelContainer.new()
	_speaker_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_speaker_panel.offset_left = 10.0
	_speaker_panel.offset_right = 380.0
	_speaker_panel.offset_top = -276.0
	_speaker_panel.offset_bottom = -156.0
	_speaker_panel.z_index = 80
	_root.add_child(_speaker_panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speaker_panel.add_child(hb)
	var por := TextureRect.new()
	por.texture = Assets.portrait(u.data["portrait"])
	por.custom_minimum_size = Vector2(96, 96)
	por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	por.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	por.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	por.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(por)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(vb)
	var nm := UiTheme.header("\"%s\"" % String(u.data["nick"]), 20)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(nm)
	var txt := UiTheme.lbl(text, 15)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(txt)
	# Entrance: slide in from the left + fade in, hold briefly, fade out.
	_speaker_panel.modulate.a = 0.0
	var end_left := _speaker_panel.offset_left
	var end_right := _speaker_panel.offset_right
	_speaker_panel.offset_left = end_left - 46.0
	_speaker_panel.offset_right = end_right - 46.0
	_speaker_tw = create_tween()
	_speaker_tw.set_parallel(true)
	_speaker_tw.tween_property(_speaker_panel, "modulate:a", 1.0, 0.16)
	_speaker_tw.tween_property(_speaker_panel, "offset_left", end_left, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_speaker_tw.tween_property(_speaker_panel, "offset_right", end_right, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_speaker_tw.chain().tween_interval(dur)
	_speaker_tw.chain().tween_property(_speaker_panel, "modulate:a", 0.0, 0.4)
	_speaker_tw.chain().tween_callback(func() -> void:
		if _speaker_panel != null:
			_speaker_panel.queue_free()
			_speaker_panel = null)


# ================================================================= JA2 crosshair (aiming)

## Screen crosshair over the targeted enemy. `level` = current aim level,
## `cap` = the weapon's maximum. The orchestrator calls this every hover frame
## (_update_hover); hide_crosshair() hides it outside the enemy branch.
func show_crosshair(pos: Vector2, level: int, cap: int, zone := "torso") -> void:
	if _root == null:
		return
	if _crosshair == null:
		_crosshair = CrosshairView.new()
		_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.z_index = 85
		_root.add_child(_crosshair)
	_crosshair.visible = true
	_crosshair.position = pos
	_crosshair.set_state(level, cap, zone)


func hide_crosshair() -> void:
	if _crosshair != null:
		_crosshair.visible = false


## Hand-drawn JA2 crosshair: outer ring + 4 directional ticks; every aim level adds
## a TIGHTER inner ring (the aim visibly "contracts").
## Red = unaimed, yellow = aim levels built up. Size 0, draws around `position`.
class CrosshairView:
	extends Control
	var level := 0
	var cap := 3
	var zone := "torso"

	func set_state(l: int, c: int, z := "torso") -> void:
		if l != level or c != cap or z != zone:
			level = l
			cap = c
			zone = z
			queue_redraw()

	func _draw() -> void:
		var col := Color(0.92, 0.30, 0.22) if level == 0 else Color(0.95, 0.78, 0.30)
		var r := 24.0
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, col, 2.0, true)
		for k in 4:
			var dir := Vector2.RIGHT.rotated(TAU * 0.25 * float(k))
			draw_line(dir * (r + 2.0), dir * (r + 10.0), col, 2.0, true)
		for i in level:
			draw_arc(Vector2.ZERO, r - 5.0 - 5.0 * float(i), 0.0, TAU, 40, col, 2.0, true)
		draw_circle(Vector2.ZERO, 1.8, col)
		# Hit zone (T): head/legs as a label below the crosshair + zone arrow on the ring.
		if zone != "torso":
			var f := ThemeDB.fallback_font
			var txt := "HEAD" if zone == "kopf" else "LEGS"
			draw_string(f, Vector2(-24.0, r + 24.0), txt, HORIZONTAL_ALIGNMENT_CENTER, 48.0, 13, col)
			var ay := -r if zone == "kopf" else r
			var tip := Vector2(0.0, ay * 0.62)
			var base_y := ay * 0.92
			draw_colored_polygon(PackedVector2Array([tip, Vector2(-5.0, base_y), Vector2(5.0, base_y)]), col)


# ================================================================= Multi-select rectangle

## Drag rectangle of the mouse multi-selection (screen coordinates). The orchestrator
## calls this once per frame while dragging; hide_select_rect() on release.
func show_select_rect(r: Rect2) -> void:
	if _root == null:
		return
	if _select_rect == null:
		_select_rect = Panel.new()
		_select_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_select_rect.z_index = 70
		_select_rect.add_theme_stylebox_override("panel",
			UiTheme.box(Color(0.95, 0.72, 0.25, 0.14), UiTheme.COL_AMBER, 0, 2, 0))
		_root.add_child(_select_rect)
	_select_rect.visible = true
	_select_rect.position = r.position
	_select_rect.size = r.size


func hide_select_rect() -> void:
	if _select_rect != null:
		_select_rect.visible = false


# ================================================================= Test getters

func has_selected_frame(i: int) -> bool:
	return i == _sel_slot and i >= 0 and i < _slots.size()


func ammo_text() -> String:
	return _ammo_label.text if _ammo_label != null else ""


func top_text() -> String:
	return _top_label.text if _top_label != null else ""


# ================================================================= Pause panel (FIX C1)

func toggle_pause() -> void:
	if _pause_panel != null:
		_pause_panel.queue_free()
		_pause_panel = null
		return
	_pause_panel = Control.new()
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_pause_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 0)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var hd := UiTheme.header("PAUSE", 30)
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hd)
	v.add_child(UiTheme.btn("Resume", toggle_pause, 17))
	v.add_child(UiTheme.btn("Abandon mission", func() -> void:
		toggle_pause()
		orch.end_battle("abort"), 17))
	v.add_child(UiTheme.btn("Quit game", func() -> void: get_tree().quit(), 17))


# ================================================================= Inventory panel (BiA look)
# Styled after "Jagged Alliance: Back in Action": central panel with a header row,
# tabs (INVENTORY/STATS), portrait+level+HP on the left, 3D paper doll in the middle,
# armor/weapons/ammo belt on the right, backpack grid at the bottom.
# PRESENTATION ONLY: the data model stays sidearm + 8 pockets (the inv index is the
# truth); belt/ammo/backpack are purely a display grouping by kind.

func toggle_inventory() -> void:
	if _inv_panel != null:
		_inv_panel.queue_free()
		_inv_panel = null
		_inv_sel = -1
		_doll_view = null           # lives in the panel tree -> was freed along with it
		_doll_key = ""
		return
	var sel: Tac3DUnit = orch.selected
	if sel == null or not sel.alive:
		return
	_inv_sel = -1
	_inv_tab = 0
	_inv_panel = PanelContainer.new()
	_inv_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_inv_panel.offset_left = -380.0
	_inv_panel.offset_right = 380.0
	_inv_panel.offset_top = -315.0
	_inv_panel.offset_bottom = 315.0
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_inv_panel.theme = _bia_theme()
	_inv_panel.add_theme_stylebox_override("panel", UiTheme.box(BIA_BG, BIA_EDGE, 5, 2, 12))
	_root.add_child(_inv_panel)
	_inv_refresh()


func _inv_refresh() -> void:
	if _inv_panel == null:
		return
	var u: Tac3DUnit = orch.selected
	if u == null:
		return
	# Detach the paper doll from the tree BEFORE clearing (the cache survives the refresh).
	if _doll_view != null and _doll_view.get_parent() != null:
		_doll_view.get_parent().remove_child(_doll_view)
	for c in _inv_panel.get_children():
		c.queue_free()
	var inv: Array = orch.inv_of(u)
	if _inv_sel >= inv.size():
		_inv_sel = -1

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_inv_panel.add_child(v)

	# ---------- Header row: name + close
	var headp := PanelContainer.new()
	headp.add_theme_stylebox_override("panel", UiTheme.box(BIA_DARK, BIA_EDGE, 3, 1, 10))
	v.add_child(headp)
	var head := HBoxContainer.new()
	headp.add_child(head)
	head.add_child(UiTheme.header("%s  \"%s\"" % [String(u.data["name"]), String(u.data["nick"])], 20, BIA_TEXT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiTheme.btn("✕", toggle_inventory, 14))

	# ---------- Tabs
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	tabs.add_child(_bia_tab("INVENTORY", 0))
	tabs.add_child(_bia_tab("STATS", 1))

	if _inv_tab == 1:
		_inv_build_skills(v, u)
	else:
		_inv_build_gear(v, u, inv)


## INVENTORY tab: 3 columns (portrait/belt | paper doll | armor/weapons/ammo)
## + backpack grid + action row.
func _inv_build_gear(v: VBoxContainer, u: Tac3DUnit, inv: Array) -> void:
	# Display routing of the pocket slots into BiA areas (the index stays the truth).
	var belt: Array[int] = []      # medkits/grenades -> belt (left)
	var ammo: Array[int] = []      # magazines -> ammo belt (right)
	var pack: Array[int] = []      # remainder -> backpack (bottom)
	var weap2 := -1                # first secondary weapon -> weapon slot 2
	for i in inv.size():
		var kind := String(Db.item(String(inv[i]))["kind"])
		if kind == "ammo" and ammo.size() < 4:
			ammo.append(i)
		elif (kind == "medkit" or kind == "grenade") and belt.size() < 4:
			belt.append(i)
		elif kind == "weapon" and weap2 < 0:
			weap2 = i
		else:
			pack.append(i)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(hb)

	# ---------- left: portrait + level + HP + belt
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(170, 0)
	left.add_theme_constant_override("separation", 6)
	hb.add_child(left)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	left.add_child(prow)
	var pframe := PanelContainer.new()
	pframe.add_theme_stylebox_override("panel", UiTheme.box(BIA_SLOT, BIA_YELLOW, 3, 2, 4))
	prow.add_child(pframe)
	var por := TextureRect.new()
	por.texture = Assets.portrait(u.data["portrait"])
	por.custom_minimum_size = Vector2(84, 84)
	por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	por.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	por.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pframe.add_child(por)
	var pside := VBoxContainer.new()
	pside.add_theme_constant_override("separation", 4)
	prow.add_child(pside)
	pside.add_child(UiTheme.header(str(orch.level_of(u)), 24, BIA_YELLOW))
	var hpb := ProgressBar.new()
	hpb.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	hpb.custom_minimum_size = Vector2(12, 54)
	hpb.max_value = u.hp_max()
	hpb.value = u.hp()
	hpb.show_percentage = false
	hpb.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.COL_RED, Color(0, 0, 0, 0), 2, 0, 1))
	pside.add_child(hpb)
	left.add_child(UiTheme.lbl("HP %d/%d · AP %d/%d" % [u.hp(), u.hp_max(), u.ap, u.ap_max], 12, BIA_DIM))
	left.add_child(_bia_caption("BELT"))
	var bgrid := GridContainer.new()
	bgrid.columns = 2
	bgrid.add_theme_constant_override("h_separation", 5)
	bgrid.add_theme_constant_override("v_separation", 5)
	left.add_child(bgrid)
	for j in 4:
		bgrid.add_child(_bia_item_slot(inv, belt, j))

	# ---------- middle: paper doll (3D preview on a grid background)
	var dollwrap := PanelContainer.new()
	dollwrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dollwrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dollwrap.add_theme_stylebox_override("panel", UiTheme.box(Color("222b1e"), BIA_EDGE, 3, 1, 4))
	hb.add_child(dollwrap)
	var gridbg := TextureRect.new()
	gridbg.texture = _grid_tex()
	gridbg.stretch_mode = TextureRect.STRETCH_TILE
	gridbg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	gridbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dollwrap.add_child(gridbg)
	var doll := _ensure_doll(u)
	if doll != null:
		dollwrap.add_child(doll)

	# ---------- right: armor / weapons / ammo belt
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(220, 0)
	right.add_theme_constant_override("separation", 6)
	hb.add_child(right)
	right.add_child(_bia_caption("ARMOR"))
	var armor := float(u.data.get("armor", 0.0))
	var apanel := PanelContainer.new()
	apanel.add_theme_stylebox_override("panel", UiTheme.box(BIA_SLOT, BIA_EDGE, 3, 1, 8))
	right.add_child(apanel)
	if armor > 0.0:
		apanel.add_child(UiTheme.lbl("Vest — %d %% protection" % int(round(armor * 100.0)), 13, BIA_TEXT))
	else:
		apanel.add_child(UiTheme.lbl("— none —", 13, BIA_DIM))

	right.add_child(_bia_caption("WEAPONS"))
	# Slot 1 = equipped weapon (green = equipped, BiA style)
	var w: Dictionary = Db.weapon(u.data["weapon"])
	var s1 := PanelContainer.new()
	s1.add_theme_stylebox_override("panel", UiTheme.box(BIA_GREEN_BG, BIA_GREEN_EDGE, 3, 2, 6))
	right.add_child(s1)
	var s1h := HBoxContainer.new()
	s1h.add_theme_constant_override("separation", 8)
	s1.add_child(s1h)
	s1h.add_child(UiTheme.header("1", 18, BIA_TEXT))
	var wicon := TextureRect.new()
	wicon.texture = Assets.item_icon(String(u.data["weapon"]))
	wicon.custom_minimum_size = Vector2(40, 40)
	wicon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wicon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s1h.add_child(wicon)
	var wv := VBoxContainer.new()
	wv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s1h.add_child(wv)
	wv.add_child(UiTheme.lbl(String(w["name"]), 13, BIA_TEXT))
	wv.add_child(UiTheme.lbl("%d/%d · Mags ×%d" % [int(u.data["ammo"]), int(w["mag"]), orch.mags_for(u)], 12, BIA_DIM))
	# Slot 2 = secondary weapon from the pockets (click -> select -> "Equip")
	if weap2 >= 0:
		var s2 := Button.new()
		s2.custom_minimum_size = Vector2(0, 46)
		s2.text = "2   " + String(Db.item(String(inv[weap2]))["short"])
		s2.icon = Assets.item_icon(String(inv[weap2]))
		s2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		s2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		s2.add_theme_font_size_override("font_size", 13)
		s2.add_theme_stylebox_override("normal", UiTheme.box(BIA_SLOT, BIA_YELLOW if weap2 == _inv_sel else BIA_EDGE, 3, 2 if weap2 == _inv_sel else 1, 6))
		s2.pressed.connect(_on_inv_slot.bind(weap2))
		right.add_child(s2)
	else:
		var s2e := PanelContainer.new()
		s2e.custom_minimum_size = Vector2(0, 46)
		s2e.add_theme_stylebox_override("panel", UiTheme.box(BIA_SLOT, Color(BIA_EDGE.r, BIA_EDGE.g, BIA_EDGE.b, 0.35), 3, 1, 6))
		s2e.add_child(UiTheme.lbl("2", 14, BIA_DIM))
		right.add_child(s2e)

	right.add_child(_bia_caption("AMMO BELT"))
	var agrid := GridContainer.new()
	agrid.columns = 2
	agrid.add_theme_constant_override("h_separation", 5)
	agrid.add_theme_constant_override("v_separation", 5)
	right.add_child(agrid)
	for j in 4:
		agrid.add_child(_bia_item_slot(inv, ammo, j))

	# ---------- Backpack (remaining items + free pockets as empty slots)
	v.add_child(_bia_caption("BACKPACK  ·  Pockets %d/%d" % [inv.size(), Db.INV_SLOTS]))
	var pgrid := GridContainer.new()
	pgrid.columns = 8
	pgrid.add_theme_constant_override("h_separation", 5)
	pgrid.add_theme_constant_override("v_separation", 5)
	v.add_child(pgrid)
	var free := maxi(0, Db.INV_SLOTS - inv.size())
	for j in pack.size() + free:
		pgrid.add_child(_bia_item_slot(inv, pack, j))

	# ---------- Action row for the selected item
	_inv_action_row(v, u, inv, w)


## STATS tab: core attributes with bars (the BiA "skills" page, adapted to our stats).
func _inv_build_skills(v: VBoxContainer, u: Tac3DUnit) -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var rows := [
		["Marksmanship", int(u.data["marks"])],
		["Agility", int(u.data["agi"])],
		["Medical", int(u.data["med"])],
	]
	for r in rows:
		var row: Array = r
		grid.add_child(UiTheme.lbl(String(row[0]), 14, BIA_TEXT))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(300, 16)
		bar.max_value = 100
		bar.value = int(row[1])
		bar.show_percentage = false
		grid.add_child(bar)
		grid.add_child(UiTheme.lbl(str(int(row[1])), 14, BIA_YELLOW))
	v.add_child(UiTheme.vspace(6))
	v.add_child(UiTheme.lbl("Health  %d/%d" % [u.hp(), u.hp_max()], 14, BIA_TEXT))
	v.add_child(UiTheme.lbl("Action points  %d/%d" % [u.ap, u.ap_max], 14, BIA_TEXT))
	v.add_child(UiTheme.lbl("Experience level  %d" % orch.level_of(u), 14, BIA_TEXT))
	v.add_child(UiTheme.lbl("Kills  %d" % int(u.data.get("kills", 0)), 14, BIA_TEXT))
	var quote := String(u.data.get("quote", ""))
	if quote != "":
		v.add_child(UiTheme.vspace(6))
		var q := UiTheme.lbl("\"%s\"" % quote, 13, BIA_DIM)
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(q)


## Action row below the backpack: context-dependent buttons for the selected item
## (identical logic/callbacks as before the BiA rework — formulas untouched).
func _inv_action_row(v: VBoxContainer, _u: Tac3DUnit, inv: Array, w: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	v.add_child(row)
	if _inv_sel < 0 or _inv_sel >= inv.size():
		row.add_child(UiTheme.lbl("Click an item: Equip · Reload · Use · Drop", 12, BIA_DIM))
		return
	var id := String(inv[_inv_sel])
	var item: Dictionary = Db.item(id)
	row.add_child(UiTheme.lbl(String(item["name"]) + ":", 13, BIA_YELLOW))
	var kind := String(item["kind"])
	if kind == "weapon":
		row.add_child(UiTheme.btn("Equip (%d AP)" % Db.SWAP_AP, _on_inv_equip.bind(_inv_sel), 13))
	elif kind == "ammo":
		if String(item.get("cal", "")) == String(w["cal"]):
			row.add_child(UiTheme.btn("Reload (%d AP)" % int(w["reload"]), _on_inv_reload, 13))
		else:
			row.add_child(UiTheme.lbl("Does not fit the equipped weapon", 13, BIA_DIM))
	elif kind == "grenade":
		row.add_child(UiTheme.btn("Ready (G)", _on_inv_grenade, 13))
	elif kind == "medkit":
		row.add_child(UiTheme.btn("Use (%d AP)" % Db.MEDKIT_AP, _on_inv_medkit, 13))
	row.add_child(UiTheme.btn("Drop", _on_inv_drop.bind(_inv_sel), 13))


# ----------------------------------------------------------------- BiA building blocks

## Olive sub-theme ONLY for the inventory panel (children inherit it automatically).
func _bia_theme() -> Theme:
	if _bia_theme_c != null:
		return _bia_theme_c
	var t := Theme.new()
	t.default_font_size = 14
	t.set_stylebox("normal", "Button", UiTheme.box(Color("3d4637"), BIA_EDGE, 3, 1, 8))
	t.set_stylebox("hover", "Button", UiTheme.box(Color("4a5442"), BIA_YELLOW, 3, 1, 8))
	t.set_stylebox("pressed", "Button", UiTheme.box(BIA_DARK, BIA_YELLOW, 3, 1, 8))
	t.set_stylebox("focus", "Button", UiTheme.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 3, 0, 8))
	var dis := UiTheme.box(Color("343c30"), Color(BIA_EDGE.r, BIA_EDGE.g, BIA_EDGE.b, 0.35), 3, 1, 8)
	t.set_stylebox("disabled", "Button", dis)
	t.set_color("font_color", "Button", BIA_TEXT)
	t.set_color("font_hover_color", "Button", BIA_YELLOW)
	t.set_color("font_pressed_color", "Button", BIA_YELLOW)
	t.set_color("font_disabled_color", "Button", Color(BIA_DIM.r, BIA_DIM.g, BIA_DIM.b, 0.6))
	t.set_stylebox("panel", "Panel", UiTheme.box(BIA_DARK, BIA_EDGE, 3, 1, 6))
	t.set_stylebox("panel", "PanelContainer", UiTheme.box(BIA_DARK, BIA_EDGE, 3, 1, 6))
	t.set_color("font_color", "Label", BIA_TEXT)
	t.set_stylebox("background", "ProgressBar", UiTheme.box(Color("161b14"), Color("4a5442"), 2, 1, 2))
	t.set_stylebox("fill", "ProgressBar", UiTheme.box(BIA_YELLOW, Color(0, 0, 0, 0), 2, 0, 2))
	_bia_theme_c = t
	return _bia_theme_c


## Tab button (active tab: yellow frame + yellow text).
func _bia_tab(txt: String, idx: int) -> Button:
	var b := UiTheme.btn(txt, func() -> void:
		_inv_tab = idx
		_inv_refresh(), 14)
	b.custom_minimum_size = Vector2(150, 30)
	if _inv_tab == idx:
		b.add_theme_stylebox_override("normal", UiTheme.box(Color("46523d"), BIA_YELLOW, 3, 2, 8))
		b.add_theme_color_override("font_color", BIA_YELLOW)
	return b


## Section caption (small khaki small-caps like in BiA).
func _bia_caption(txt: String) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", UiTheme.title_font())
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", BIA_DIM)
	return l


## j-th frame of a display area: item button or empty recess.
func _bia_item_slot(inv: Array, idxs: Array, j: int) -> Control:
	if j < idxs.size():
		return _bia_slot_button(inv, int(idxs[j]))
	return _bia_empty_slot()


## Occupied slot: icon button, selection = yellow frame, tooltip = item name.
func _bia_slot_button(inv: Array, i: int) -> Button:
	var id := String(inv[i])
	var b := Button.new()
	b.custom_minimum_size = Vector2(56, 56)
	b.icon = Assets.item_icon(id)
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.tooltip_text = String(Db.item(id)["name"])
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var selected := i == _inv_sel
	b.add_theme_stylebox_override("normal", UiTheme.box(BIA_SLOT, BIA_YELLOW if selected else BIA_EDGE, 3, 2 if selected else 1, 4))
	b.add_theme_stylebox_override("hover", UiTheme.box(Color("2a3326"), BIA_YELLOW, 3, 1, 4))
	b.add_theme_stylebox_override("pressed", UiTheme.box(BIA_SLOT, BIA_YELLOW, 3, 2, 4))
	b.pressed.connect(_on_inv_slot.bind(i))
	return b


## Empty slot recess (dimmed frame).
func _bia_empty_slot() -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(56, 56)
	p.add_theme_stylebox_override("panel", UiTheme.box(BIA_SLOT, Color(BIA_EDGE.r, BIA_EDGE.g, BIA_EDGE.b, 0.35), 3, 1, 4))
	return p


## Grid texture (48px tiles) for the paper-doll background, lazy + cached.
func _grid_tex() -> ImageTexture:
	if _grid_texture != null:
		return _grid_texture
	var img := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	img.fill(Color("222b1e"))
	var line := Color("2e3a29")
	for x in 48:
		img.set_pixel(x, 0, line)
	for y in 48:
		img.set_pixel(0, y, line)
	_grid_texture = ImageTexture.create_from_image(img)
	return _grid_texture


## 3D paper doll: its own SubViewport (own_world_3d, transparent) holding the merc's
## character model in the idle-gun pose + a mounted sidearm.
## Cached under "mercId|body|weaponModel" — a refresh only reparents (no reload).
## The merc id MUST be part of the key, otherwise two mercs with the same body+weapon
## would share the doll INCLUDING the other merc's uniform colour.
## Fallback-safe: without a GLB Assets3D shows the capsule, without a skeleton no weapon.
func _ensure_doll(u: Tac3DUnit) -> SubViewportContainer:
	var cid := "boss" if String(u.data.get("type", "")) == "boss" else ("merc" if u.is_merc else "enemy")
	# SPEC §4.1: the doll shows THE SAME body and THE SAME uniform as the figure on
	# the map — otherwise the HUD picture would not match the merc in the field.
	# If the Db entry is missing (enemy/boss), everything stays as before (role model).
	var uid := String(u.data.get("id", ""))
	var look := Db.merc_look(uid)
	if look.has("model"):
		cid = String(look["model"])
	var wid := String(u.data.get("weapon", ""))
	# Resolve the merc's OWN weapon mesh (P9 / K45 / Huntsman / Dragonmaw / SVD each
	# have their own), falling back to the generic pistol/rifle when that weapon has
	# no dedicated mesh. Without this the paper doll showed the generic gun while the
	# figure in the field carried the real one.
	var wmodel := Unit3D.weapon_mesh_for(String(Tac3DUnit.WEAPON_MODEL.get(wid, "rifle")), wid)
	# The merc id belongs in the cache key: two mercs with the same body+weapon
	# still have DIFFERENT uniform colours.
	var key := uid + "|" + cid + "|" + wmodel
	if _doll_view != null and _doll_key == key:
		return _doll_view
	if _doll_view != null:
		_doll_view.queue_free()
		_doll_view = null
	_doll_key = key
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sv := SubViewport.new()
	sv.own_world_3d = true
	sv.transparent_bg = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	svc.add_child(sv)
	var world := Node3D.new()
	sv.add_child(world)
	var model := Assets3D.character(cid)
	model.rotation_degrees.y = -22.0    # slight 3/4 view (model front = +Z)
	world.add_child(model)
	if look.has("uniform"):
		Unit3D.paint_uniform(model, look["uniform"])
	# Loop the idle-gun pose (only a real GLB; the fallback capsule has no player).
	var anim := _doll_find_anim(model)
	if anim != null and anim.has_animation("CharacterArmature|Idle_Gun"):
		var a := anim.get_animation("CharacterArmature|Idle_Gun")
		if a != null:
			a.loop_mode = Animation.LOOP_LINEAR
		anim.play("CharacterArmature|Idle_Gun")
	# Mount the sidearm (same fit pattern as Unit3D.equip_weapon).
	var skel := _doll_find_skel(model)
	if skel != null:
		var bone := "Wrist.R"
		if skel.find_bone(bone) < 0 and skel.find_bone("Wrist_R") >= 0:
			bone = "Wrist_R"
		if skel.find_bone(bone) >= 0:
			var att := BoneAttachment3D.new()
			att.bone_name = bone
			skel.add_child(att)
			# Fit taken from the Db (SPEC §4.1 step 3), fallback = WEAPON_FITS.
			var fit := Unit3D.weapon_fit_from(wmodel, Db.weapon_attach(wid))
			var gun := Assets3D.weapon(wmodel)
			gun.scale = fit["scale"]
			gun.position = fit["position"]
			gun.rotation_degrees = fit["rotation"]
			att.add_child(gun)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30.0, 35.0, 0.0)
	light.light_energy = 1.2
	world.add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.75, 0.68)
	e.ambient_light_energy = 0.9
	env.environment = e
	world.add_child(env)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 2.3
	cam.position = Vector3(0.0, 1.0, 3.5)
	world.add_child(cam)
	cam.current = true
	_doll_view = svc
	return _doll_view


## Recursive search for AnimationPlayer/Skeleton3D in the doll model (fallback-safe).
func _doll_find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for child in n.get_children():
		var found := _doll_find_anim(child)
		if found != null:
			return found
	return null


func _doll_find_skel(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for child in n.get_children():
		var found := _doll_find_skel(child)
		if found != null:
			return found
	return null


func _can_act() -> bool:
	var sel: Tac3DUnit = orch.selected
	return sel != null and sel.alive and orch.player_turn and not orch.busy


func _on_inv_slot(i: int) -> void:
	_inv_sel = i
	_inv_refresh()


func _on_inv_equip(i: int) -> void:
	if _can_act():
		orch.do_swap(orch.selected, i)
		_inv_sel = -1
		refresh()


func _on_inv_reload() -> void:
	if _can_act():
		orch.do_reload(orch.selected)
		refresh()


func _on_inv_grenade() -> void:
	orch.ui_grenade_mode()
	refresh()


func _on_inv_medkit() -> void:
	if _can_act():
		orch.do_medkit(orch.selected)
		refresh()


func _on_inv_drop(i: int) -> void:
	var sel: Tac3DUnit = orch.selected
	if sel == null:
		return
	var inv: Array = orch.inv_of(sel)
	if i >= 0 and i < inv.size():
		inv.remove_at(i)
	_inv_sel = -1
	refresh()


# ================================================================= Phase 7: slot rebuild (W2)

## Rebuilds the squad bar's merc cards after Otto's rescue (now 5 cards in _mercbox).
## MUST run inside free_otto directly after mercs.append(otto), BEFORE any
## _hud_refresh()/compute_vision() — otherwise refresh() would write into stale/missing _slots.
func rebuild_slots() -> void:
	if _mercbox == null:
		return
	for c in _mercbox.get_children():
		c.queue_free()
	_slots.clear()
	_sel_slot = -1
	for i in orch.mercs.size():
		_mercbox.add_child(_build_slot(i))
	refresh()


# ================================================================= Phase 7: Vargo dialog (ported from tactical.gd:942, FIX C1)

## Modal boss dialog. The panel is a child of _root (CanvasLayer) — never under the
## Node3D orchestrator. The orchestrator called `await hud.show_boss_dialog()` in
## check_boss_dialog() exactly once (guarded beforehand by Game.boss_dialog_seen).
## DEAD CODE: spec §3.2 cut the boss fight from the demo, so nothing calls this any
## more (see tactical3d_combat.gd). Kept in place deliberately — it must still parse.
func show_boss_dialog() -> void:
	modal_active = true
	Sfx.play("interrupt", -4.0)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(bottom)
	var centerc := CenterContainer.new()
	bottom.add_child(centerc)
	bottom.add_child(UiTheme.vspace(150))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 220)
	centerc.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	panel.add_child(hb)
	var por := TextureRect.new()
	por.texture = Assets.portrait(Db.ENEMY_TYPES["boss"]["portrait"])
	por.custom_minimum_size = Vector2(140, 140)
	por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	por.stretch_mode = TextureRect.STRETCH_SCALE
	por.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	por.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(por)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	hb.add_child(vb)
	var speaker := UiTheme.header("HELIX COMMANDER VARGO", 22)
	vb.add_child(speaker)
	var text := UiTheme.lbl("", 18)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(720, 84)
	vb.add_child(text)
	var btnrow := HBoxContainer.new()
	btnrow.alignment = BoxContainer.ALIGNMENT_END
	btnrow.add_theme_constant_override("separation", 10)
	vb.add_child(btnrow)

	var responder := "Merc"
	var merc_line := ""
	if Game.has_ivan():
		responder = "Ivan"
		merc_line = Db.IVAN_DIALOG_LINE
	else:
		var tp: Dictionary = Game.top_paid()
		if not tp.is_empty():
			responder = "\"%s\"" % tp["nick"]

	var vargo_i := 0
	for line in Db.BOSS_DIALOG:
		var is_vargo: bool = line["speaker"] == "vargo"
		speaker.text = "HELIX COMMANDER VARGO" if is_vargo else responder.to_upper()
		speaker.add_theme_color_override("font_color", UiTheme.COL_RED if is_vargo else UiTheme.COL_AMBER)
		var t: String = line["text"]
		if not is_vargo and merc_line != "":
			t = merc_line
		# Voice-over (baked ElevenLabs clips, fallback-safe)
		if is_vargo:
			vargo_i += 1
			Sfx.play_voice("vargo_%d" % vargo_i)
		elif Game.has_ivan():
			Sfx.play_voice("ivan_dialog")
		else:
			var tp2: Dictionary = Game.top_paid()
			if not tp2.is_empty():
				Sfx.play_voice(String(tp2["id"]) + "_reply")
		await _type_text(text, t)
		for c in btnrow.get_children():
			c.queue_free()
		var next := UiTheme.btn("Continue  ▸", func() -> void: dialog_next.emit(), 16)
		btnrow.add_child(next)
		await dialog_next

	for c in btnrow.get_children():
		c.queue_free()
	speaker.text = "YOUR ANSWER"
	speaker.add_theme_color_override("font_color", UiTheme.COL_AMBER)
	text.text = ""
	for i in Db.BOSS_CHOICES.size():
		var ch: Dictionary = Db.BOSS_CHOICES[i]
		var b := UiTheme.btn(ch["label"], func() -> void: dialog_choice.emit(i), 16)
		btnrow.add_child(b)
	var choice: int = await dialog_choice
	var reply := String(Db.BOSS_CHOICES[choice]["reply"])
	if reply != "":
		for c in btnrow.get_children():
			c.queue_free()
		speaker.text = "HELIX COMMANDER VARGO"
		speaker.add_theme_color_override("font_color", UiTheme.COL_RED)
		Sfx.play_voice("vargo_3")
		await _type_text(text, reply)
		var next2 := UiTheme.btn("Fight!  ▸", func() -> void: dialog_next.emit(), 16)
		btnrow.add_child(next2)
		await dialog_next
	layer.queue_free()
	Sfx.play_voice("vargo_kampf")
	banner("VARGO: NOW IT'S ALL OR NOTHING!", 1.2)
	modal_active = false


## Rescue dialogue (spec §3.4): ONE voiced sequence carrying EXACTLY three pieces
## of information — the situation, Maren, the mines. No choices: Tobias simply
## talks, then The Hideout opens. Same modal scaffolding as the boss dialog
## (panel under _root/CanvasLayer, never under the Node3D orchestrator).
func show_tobias_dialog() -> void:
	modal_active = true
	Sfx.play_voice("tobias_rescue")
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bottom.alignment = BoxContainer.ALIGNMENT_END
	layer.add_child(bottom)
	var centerc := CenterContainer.new()
	bottom.add_child(centerc)
	bottom.add_child(UiTheme.vspace(150))

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(980, 220)
	centerc.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	panel.add_child(hb)
	var por := TextureRect.new()
	por.texture = Assets.portrait(Db.OTTO["portrait"])
	por.custom_minimum_size = Vector2(140, 140)
	por.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	por.stretch_mode = TextureRect.STRETCH_SCALE
	por.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	por.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(por)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	hb.add_child(vb)
	var speaker := UiTheme.header(String(Db.OTTO["name"]).to_upper(), 22)
	speaker.add_theme_color_override("font_color", UiTheme.COL_AMBER)
	vb.add_child(speaker)
	var text := UiTheme.lbl("", 18)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(720, 84)
	vb.add_child(text)
	var btnrow := HBoxContainer.new()
	btnrow.alignment = BoxContainer.ALIGNMENT_END
	btnrow.add_theme_constant_override("separation", 10)
	vb.add_child(btnrow)

	for i in Db.TOBIAS_DIALOG.size():
		var line: Dictionary = Db.TOBIAS_DIALOG[i]
		Sfx.play_voice(String(line["voice"]))
		await _type_text(text, String(line["text"]))
		for c in btnrow.get_children():
			c.queue_free()
		var last: bool = i == Db.TOBIAS_DIALOG.size() - 1
		var lbl_next := "To The Hideout  ▸" if last else "Continue  ▸"
		btnrow.add_child(UiTheme.btn(lbl_next, func() -> void: dialog_next.emit(), 16))
		await dialog_next

	layer.queue_free()
	modal_active = false


## Typewriter effect (ported from tactical.gd:1049). Inside the HUD orch.fast is
## always false (the HUD only exists when not fast) — checked defensively anyway.
func _type_text(l: Label, t: String) -> void:
	l.text = t
	if orch.fast:
		return
	l.visible_characters = 0
	var tw := create_tween()
	tw.tween_property(l, "visible_characters", t.length(), t.length() * 0.014)
	await tw.finished
	l.visible_characters = -1


# ================================================================= Phase 7: home base "The Hideout" (K3, FIX C1)

## Modal base menu, opened ONCE when Tobias is freed. Panel is a child of _root
## (CanvasLayer). SPEC v5 §8.2 requires all four base functions LIVE:
## heal / stash / save / hire — no stubs.
## Base helper: move everything beyond the first four items of each pack into
## The Hideout's stash (SPEC v5 §4.4 `base.stash`) — it survives in the save.
func _base_stash_all() -> String:
	var moved := 0
	for m in orch.mercs:
		var u: Tac3DUnit = m
		var pack: Array = orch.inv_of(u)
		while pack.size() > 4:
			if not orch.base_stash_deposit(u, String(pack[pack.size() - 1])):
				break
			moved += 1
	if moved == 0:
		return "Nothing spare to stash. The Hideout holds %d." % Game.stash.size()
	return "Stashed %d item(s). The Hideout holds %d." % [moved, Game.stash.size()]

## Base helper: hand the top stash item back to the first merc with room.
func _base_stash_take() -> String:
	if Game.stash.is_empty():
		return "The stash is empty."
	var item := String(Game.stash[Game.stash.size() - 1])
	for m in orch.mercs:
		var u: Tac3DUnit = m
		if orch.base_stash_withdraw(u, item):
			return "%s went to %s." % [item, String(u.data["nick"])]
	return "No room in any pack."

## Base helper: hire the first affordable reinforcement through the laptop.
func _base_hire_first() -> String:
	var broke := false
	for cid in orch.base_hire_candidates():
		var def := Db.merc_def(String(cid))
		if def.is_empty():
			continue
		if Game.budget < Game.eff_cost(int(def["cost"])):
			broke = true
			continue
		if orch.base_hire(String(cid)):
			return "%s joined the squad." % String(def["nick"])
		return "No room in The Hideout."
	if broke:
		return "Nobody affordable — budget %d $." % Game.budget
	return "The whole roster is already on the payroll."

## Action-bar entry into The Hideout (the button next to END TURN, enabled only
## once Game.base_unlocked — see refresh()). show_base_panel() is a COROUTINE
## that awaits `base_closed`; a Button callback cannot await, so it is started
## detached. The modal_active guard stops a second panel from stacking on top
## when the button is clicked again while one is already open.
func open_hideout() -> void:
	if modal_active:
		return
	show_base_panel()


func show_base_panel() -> void:
	modal_active = true
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(cc)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	cc.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	var hd := UiTheme.header("THE HIDEOUT", 30, UiTheme.COL_AMBER)
	hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hd)
	v.add_child(UiTheme.lbl("Tobias Rook joins your command. You'll operate out of this cellar — The Hideout.", 15))
	var status := UiTheme.lbl("", 14, UiTheme.COL_DIM)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# All four base functions are LIVE (SPEC v5 §8.2): heal / stash / save / hire.
	v.add_child(UiTheme.btn("Heal squad (free)", func() -> void:
		orch.base_heal_all()
		status.text = "Squad patched up.", 16))
	v.add_child(UiTheme.btn("Resupply (refill ammo)", func() -> void:
		orch.base_resupply_all()
		status.text = "Magazines topped up.", 16))
	v.add_child(UiTheme.btn("Stash — store spare gear", func() -> void:
		status.text = _base_stash_all(), 16))
	v.add_child(UiTheme.btn("Stash — take gear back", func() -> void:
		status.text = _base_stash_take(), 16))
	var hire_btn := UiTheme.btn("Hire reinforcement (laptop)", func() -> void:
		status.text = _base_hire_first(), 16)
	v.add_child(hire_btn)
	v.add_child(UiTheme.btn("Save", func() -> void:
		status.text = "Game saved." if orch.base_save() else "Saving failed.", 16))
	v.add_child(status)
	v.add_child(UiTheme.btn("Continue  ▸", func() -> void: base_closed.emit(), 17))
	await base_closed
	layer.queue_free()
	modal_active = false

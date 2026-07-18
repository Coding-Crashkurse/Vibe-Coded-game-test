class_name CombatHud
extends CanvasLayer
## JA1-HUD-View fuer den 3D-Kampf (Strang A). Portiert 1:1 das Layout aus
## scripts/screens/tactical.gd (_build_hud / _build_slot / refresh_hud / _update_enemy_label)
## auf den Tac3D-Orchestrator. KEIN Signal-Bus: der Orchestrator haelt `hud` und ruft nach
## jeder Aktion `refresh()`; die HUD haelt `orch` und triggert Aktionen ueber Callable(orch,"ui_*").
##
## FIX C1: Pause- UND Inventar-Panel haengen als Kinder von `_root` (Control unter der
## CanvasLayer). Ein Control direkt unter dem Node3D-Orchestrator haette keine Canvas-Transform
## und wuerde NICHT gezeichnet. Deshalb: toggle_pause()/toggle_inventory() leben hier im HUD,
## der Orchestrator delegiert nur (ui_menu -> hud.toggle_pause, ui_inventory -> hud.toggle_inventory).
##
## GDScript-Fallen: PRESET_FULL_RECT NUR via set_anchors_and_offsets_preset (Groesse-0-Falle);
## build(orch) nimmt orch UNTYPED (Zyklus-Falle); typisierte Variant-Iteration; Integer-Werte
## ausschliesslich aus orch.*/Db.* ziehen (identische Balance).

var orch = null                       # Orchestrator (UNTYPED — Zyklus-Falle)

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
var _inv_btn: Button
var _endturn_btn: Button
var _menu_btn: Button
var _cursor_panel: PanelContainer
var _cursor_label: Label
var _banner_label: Label
var _slots: Array = []                 # [{btn,hp,ap,stat}, ...] fuer orch.mercs

var _pause_panel: Control = null
var _inv_panel: PanelContainer = null
var _inv_sel := -1


# ================================================================= Aufbau

func build(o) -> void:
	orch = o
	layer = 10

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.theme()
	add_child(_root)

	# Obere Leiste
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
	th.add_child(UiTheme.lbl("[Tab] Söldner  [Z] Zielen  [G] Granate  [R] Nachladen  [H] Medikit  [I] Inventar  [Enter] Runde  ·  [Q/E] Drehen  [Rad] Zoom", 12, UiTheme.COL_DIM))

	# Portrait-Seitenleisten (JA1): 0–1 links, 2–3 rechts
	_slots = []
	var left := VBoxContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	left.offset_left = 8.0
	left.offset_top = -170.0
	left.add_theme_constant_override("separation", 10)
	_root.add_child(left)
	var right := VBoxContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	right.offset_right = -8.0
	right.offset_left = -144.0
	right.offset_top = -170.0
	right.add_theme_constant_override("separation", 10)
	_root.add_child(right)
	for i in orch.mercs.size():
		var side := left if i < 2 else right
		side.add_child(_build_slot(i))

	# Untere Aktionsleiste (mittig)
	var bottom := PanelContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -390.0
	bottom.offset_right = 390.0
	bottom.offset_top = -128.0
	bottom.offset_bottom = -6.0
	bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(bottom)
	var act := VBoxContainer.new()
	act.add_theme_constant_override("separation", 6)
	bottom.add_child(act)
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
	_reload_btn = UiTheme.btn("Nachladen (R)", Callable(orch, "ui_reload"), 13)
	brow.add_child(_reload_btn)
	_aim_btn = UiTheme.btn("Zielen (Z)", Callable(orch, "ui_aim"), 13)
	brow.add_child(_aim_btn)
	_grenade_btn = UiTheme.btn("Granate (G)", Callable(orch, "ui_grenade_mode"), 13)
	_grenade_btn.icon = Assets.item_icon("granate")
	brow.add_child(_grenade_btn)
	_medkit_btn = UiTheme.btn("Medikit (H)", Callable(orch, "ui_medkit"), 13)
	_medkit_btn.icon = Assets.item_icon("medkit")
	brow.add_child(_medkit_btn)
	_inv_btn = UiTheme.btn("Inventar (I)", Callable(orch, "ui_inventory"), 13)
	brow.add_child(_inv_btn)
	var brow2 := HBoxContainer.new()
	brow2.add_theme_constant_override("separation", 8)
	act.add_child(brow2)
	_endturn_btn = UiTheme.btn("RUNDE BEENDEN (Enter)", Callable(orch, "ui_end_turn"), 14)
	_endturn_btn.custom_minimum_size = Vector2(230, 0)
	brow2.add_child(_endturn_btn)
	_menu_btn = UiTheme.btn("Menü (Esc)", Callable(orch, "ui_menu"), 13)
	brow2.add_child(_menu_btn)

	# Cursor-Info (Tooltip)
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
	btn.custom_minimum_size = Vector2(136, 162)
	btn.pressed.connect(Callable(orch, "ui_select_slot").bind(i))
	var inner := VBoxContainer.new()
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_constant_override("separation", 3)
	inner.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(inner)
	var por := TextureRect.new()
	por.texture = Assets.portrait(m.data["portrait"])
	por.custom_minimum_size = Vector2(84, 84)
	por.stretch_mode = TextureRect.STRETCH_SCALE
	por.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	por.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	por.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(por)
	var nm := UiTheme.lbl("»%s«" % m.data["nick"], 14)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(nm)
	var hpb := ProgressBar.new()
	hpb.custom_minimum_size = Vector2(110, 10)
	hpb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hpb.max_value = m.hp_max()
	hpb.value = m.hp()
	hpb.show_percentage = false
	hpb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hpb.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.COL_RED, Color(0, 0, 0, 0), 2, 0, 1))
	inner.add_child(hpb)
	var apb := ProgressBar.new()
	apb.custom_minimum_size = Vector2(110, 8)
	apb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	apb.max_value = m.ap_max
	apb.value = m.ap
	apb.show_percentage = false
	apb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(apb)
	var stat := UiTheme.lbl("", 11, UiTheme.COL_DIM)
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(stat)
	_slots.append({"btn": btn, "hp": hpb, "ap": apb, "stat": stat})
	return btn


# ================================================================= Refresh (Arbeitspferd)

func refresh() -> void:
	if _slots.is_empty():
		return
	if orch.combat_started:
		_top_label.text = "SEKTOR 43 · SILBERQUELL — Runde %d — %s" % [orch.turn, "Ihr Zug" if orch.player_turn else "Feindphase"]
	else:
		_top_label.text = "SEKTOR 43 · SILBERQUELL — ANMARSCH — frei bewegen bis Feindkontakt"
	var seen := 0
	var total := 0
	for e in orch.enemies:
		var en: Tac3DUnit = e
		if en.alive:
			total += 1
			if en.seen:
				seen += 1
	_enemy_label.text = "Feinde: %d gesichtet · %d verbleibend" % [seen, total]
	for i in orch.mercs.size():
		var m: Tac3DUnit = orch.mercs[i]
		var sb: Dictionary = _slots[i]
		sb["hp"].max_value = m.hp_max()
		sb["hp"].value = m.hp()
		sb["ap"].max_value = m.ap_max
		sb["ap"].value = m.ap
		sb["stat"].text = "HP %d/%d · AP %d · St.%d" % [m.hp(), m.hp_max(), m.ap, orch.level_of(m)]
		if not m.alive:
			sb["btn"].disabled = true
			sb["btn"].modulate = Color(0.55, 0.4, 0.4, 0.7)
			sb["stat"].text = "GEFALLEN"
		if m == orch.selected:
			sb["btn"].add_theme_stylebox_override("normal", UiTheme.box(Color("5e4828"), UiTheme.COL_AMBER, 4, 3, 6))
		else:
			sb["btn"].remove_theme_stylebox_override("normal")
	var sel: Tac3DUnit = orch.selected
	if sel != null and sel.alive:
		var w: Dictionary = Db.weapon(sel.data["weapon"])
		var can: bool = orch.player_turn and not orch.busy
		_weapon_label.text = String(w["name"])
		_ammo_label.text = "Munition %d/%d" % [int(sel.data["ammo"]), int(w["mag"])]
		_mags_label.text = "Magazine ×%d · Granaten ×%d · Medikits ×%d" % [orch.mags_for(sel), orch.inv_count(sel, "granate"), orch.inv_count(sel, "medkit")]
		_reload_btn.disabled = not can or sel.ap < int(w["reload"]) or int(sel.data["ammo"]) >= int(w["mag"]) or orch.mags_for(sel) <= 0
		_reload_btn.icon = Assets.item_icon("mag_" + String(w["cal"]))
		_aim_btn.text = ("Zielen ×%d (Z)" % orch.aim_level) if orch.aim_level > 0 else "Zielen (Z)"
		_aim_btn.disabled = not can
		_aim_btn.modulate = Color(1.0, 0.8, 0.45) if orch.aim_level > 0 else Color(1, 1, 1)
		_grenade_btn.text = "Granate ×%d (G)" % orch.inv_count(sel, "granate")
		_grenade_btn.disabled = not can or orch.inv_count(sel, "granate") <= 0 or sel.ap < int(Db.GRENADE["ap"])
		_grenade_btn.modulate = Color(1.0, 0.75, 0.4) if orch.mode == "grenade" else Color(1, 1, 1)
		_medkit_btn.text = "Medikit ×%d (H)" % orch.inv_count(sel, "medkit")
		_medkit_btn.disabled = not can or orch.inv_count(sel, "medkit") <= 0 or sel.ap < Db.MEDKIT_AP
		_inv_btn.disabled = not can
	_endturn_btn.disabled = not orch.player_turn or orch.busy or not orch.combat_started
	if _inv_panel != null:
		_inv_refresh()


# ================================================================= Duenne API

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


# ================================================================= Test-Getter

func has_selected_frame(i: int) -> bool:
	if i < 0 or i >= _slots.size():
		return false
	var sb: Dictionary = _slots[i]
	return sb["btn"].has_theme_stylebox_override("normal")


func ammo_text() -> String:
	return _ammo_label.text if _ammo_label != null else ""


func top_text() -> String:
	return _top_label.text if _top_label != null else ""


# ================================================================= Pause-Panel (FIX C1)

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
	v.add_child(UiTheme.btn("Fortsetzen", toggle_pause, 17))
	v.add_child(UiTheme.btn("Mission aufgeben", func() -> void:
		toggle_pause()
		orch.end_battle("abort"), 17))
	v.add_child(UiTheme.btn("Spiel beenden", func() -> void: get_tree().quit(), 17))


# ================================================================= Inventar-Panel (FIX C1)

func toggle_inventory() -> void:
	if _inv_panel != null:
		_inv_panel.queue_free()
		_inv_panel = null
		_inv_sel = -1
		return
	var sel: Tac3DUnit = orch.selected
	if sel == null or not sel.alive:
		return
	_inv_sel = -1
	_inv_panel = PanelContainer.new()
	_inv_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_inv_panel.offset_right = -156.0
	_inv_panel.offset_left = -536.0
	_inv_panel.offset_top = -240.0
	_inv_panel.offset_bottom = 240.0
	_inv_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_inv_panel)
	_inv_refresh()


func _inv_refresh() -> void:
	if _inv_panel == null:
		return
	var u: Tac3DUnit = orch.selected
	if u == null:
		return
	for c in _inv_panel.get_children():
		c.queue_free()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_inv_panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(UiTheme.header("INVENTAR — »%s«" % u.data["nick"], 20))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(UiTheme.btn("✕", toggle_inventory, 14))
	v.add_child(UiTheme.lbl("HP %d/%d · TRF %d · BEW %d · MED %d" % [u.hp(), u.hp_max(), int(u.data["marks"]), int(u.data["agi"]), int(u.data["med"])], 13, UiTheme.COL_DIM))
	v.add_child(UiTheme.lbl("Erfahrungsstufe %d · Abschüsse %d" % [orch.level_of(u), int(u.data.get("kills", 0))], 13, UiTheme.COL_DIM))
	var w: Dictionary = Db.weapon(u.data["weapon"])
	var handrow := HBoxContainer.new()
	handrow.add_theme_constant_override("separation", 8)
	v.add_child(handrow)
	var handicon := TextureRect.new()
	handicon.texture = Assets.item_icon(String(u.data["weapon"]))
	handicon.custom_minimum_size = Vector2(32, 32)
	handicon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	handicon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	handrow.add_child(handicon)
	handrow.add_child(UiTheme.lbl("HAND: %s (%d/%d)" % [w["name"], int(u.data["ammo"]), int(w["mag"])], 15, UiTheme.COL_AMBER))
	v.add_child(UiTheme.lbl("Taschen (%d/%d):" % [orch.inv_of(u).size(), Db.INV_SLOTS], 13, UiTheme.COL_DIM))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	var inv: Array = orch.inv_of(u)
	for i in Db.INV_SLOTS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(174, 42)
		b.add_theme_font_size_override("font_size", 12)
		b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if i < inv.size():
			b.text = String(Db.item(String(inv[i]))["short"])
			b.icon = Assets.item_icon(String(inv[i]))
			if i == _inv_sel:
				b.add_theme_stylebox_override("normal", UiTheme.box(Color("5e4828"), UiTheme.COL_AMBER, 4, 2, 8))
			b.pressed.connect(_on_inv_slot.bind(i))
		else:
			b.text = "— leer —"
			b.disabled = true
		grid.add_child(b)
	# Aktionen fuers gewaehlte Item
	if _inv_sel >= 0 and _inv_sel < inv.size():
		var id := String(inv[_inv_sel])
		var item: Dictionary = Db.item(id)
		v.add_child(UiTheme.vspace(4))
		v.add_child(UiTheme.lbl("Gewählt: " + String(item["name"]), 14))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		v.add_child(row)
		var kind := String(item["kind"])
		if kind == "weapon":
			row.add_child(UiTheme.btn("Ausrüsten (%d AP)" % Db.SWAP_AP, _on_inv_equip.bind(_inv_sel), 13))
		elif kind == "ammo":
			if String(item.get("cal", "")) == String(w["cal"]):
				row.add_child(UiTheme.btn("Nachladen (%d AP)" % int(w["reload"]), _on_inv_reload, 13))
			else:
				row.add_child(UiTheme.lbl("Passt nicht zur Handwaffe", 13, UiTheme.COL_DIM))
		elif kind == "grenade":
			row.add_child(UiTheme.btn("Bereitmachen (G)", _on_inv_grenade, 13))
		elif kind == "medkit":
			row.add_child(UiTheme.btn("Benutzen (%d AP)" % Db.MEDKIT_AP, _on_inv_medkit, 13))
		row.add_child(UiTheme.btn("Wegwerfen", _on_inv_drop.bind(_inv_sel), 13))


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

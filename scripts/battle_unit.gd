class_name BattleUnit
extends Node2D
## Eine Einheit auf der Taktikkarte (Söldner oder Gegner).
## Hält Laufzeitdaten (data-Dict), Sprite, HP/AP-Anzeige.

const TILE := 64

var data: Dictionary = {}
var is_merc := false
var cell := Vector2i.ZERO
var alive := true
var seen := true            # Für Gegner: aktuell im Sichtfeld des Teams?
var interrupt_used := false
var home := Vector2i.ZERO   # Anker (Boss verlässt seinen Bereich nicht)
var ap := 0
var ap_max := 0
var sprite: Sprite2D
var hovered := false
var selected := false

func setup(d: Dictionary, merc: bool) -> void:
	data = d
	is_merc = merc
	ap_max = 20 + int(d["agi"]) / 5
	ap = ap_max
	sprite = Sprite2D.new()
	var pose: String = Db.weapon(d["weapon"])["pose"]
	sprite.texture = Assets.tex("%s_%s" % [d["sprite"], pose])
	sprite.modulate = d["tint"]
	sprite.scale = Vector2.ONE * float(d.get("scale", 1.0))
	add_child(sprite)
	z_index = 5

func set_cell(c: Vector2i) -> void:
	cell = c
	position = Vector2(c) * TILE + Vector2(TILE / 2.0, TILE / 2.0)

func face_pos(p: Vector2) -> void:
	if (p - position).length() > 1.0:
		sprite.rotation = (p - position).angle()

func hp() -> int:
	return int(data["hp"])

func hp_max() -> int:
	return int(data["hp_max"])

func hurt(dmg: int) -> void:
	data["hp"] = max(0, hp() - dmg)
	if hp() <= 0:
		alive = false
		data["alive"] = false
	queue_redraw()

func die_visual() -> void:
	z_index = 1
	visible = true
	sprite.modulate = Color(0.42, 0.35, 0.32, 0.92)
	sprite.rotation += randf_range(0.4, 0.9)
	queue_redraw()

func set_seen(v: bool) -> void:
	seen = v
	if is_merc or not alive:
		visible = true
	else:
		visible = v
	queue_redraw()

func display_name() -> String:
	if data.has("nick"):
		return String(data["nick"])
	return String(data["name"])

func _draw() -> void:
	if not alive:
		return
	# Bodenschatten (3/4-Look)
	draw_set_transform(Vector2(0, 12), 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, 15.0, Color(0, 0, 0, 0.26))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if selected:
		draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 40, UiTheme.COL_AMBER, 2.5, true)
	elif hovered and not is_merc:
		draw_arc(Vector2.ZERO, 27.0, 0.0, TAU, 40, UiTheme.COL_RED, 2.5, true)
	if is_merc or seen:
		var w := 40.0
		var frac := clampf(float(hp()) / float(max(1, hp_max())), 0.0, 1.0)
		draw_rect(Rect2(-w / 2.0, -42.0, w, 5.0), Color(0, 0, 0, 0.65))
		var col := UiTheme.COL_GREEN
		if frac <= 0.25:
			col = UiTheme.COL_RED
		elif frac <= 0.5:
			col = UiTheme.COL_AMBER
		draw_rect(Rect2(-w / 2.0, -42.0, w * frac, 5.0), col)
		if is_merc:
			var afrac := clampf(float(ap) / float(max(1, ap_max)), 0.0, 1.0)
			draw_rect(Rect2(-w / 2.0, -36.0, w, 3.0), Color(0, 0, 0, 0.65))
			draw_rect(Rect2(-w / 2.0, -36.0, w * afrac, 3.0), Color(0.92, 0.78, 0.42, 0.95))
	if selected or hovered:
		var f := ThemeDB.fallback_font
		var nm := display_name()
		var ncol := UiTheme.COL_AMBER if is_merc else Color(1.0, 0.55, 0.5)
		draw_string(f, Vector2(-60, -48), nm, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, ncol)

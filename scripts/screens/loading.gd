extends Control
## SPEC v5 §3.3.1 — mission intro: narrator text over black, then the heli
## approach (sound + dust + fade only, the heli itself is never shown) → 3D
## combat. Skippable at any time (click/key). Target screen unchanged:
## "tactical3d_combat".

const _DEST := "tactical3d_combat"

## Sectors the tactical layer actually has a map recipe for (Tac3DMapGen builds
## "F4" and "F3"). A persisted sector outside this list — a locked sector, an
## older or corrupt save — falls back to the start sector instead of dropping
## the player into a silently substituted map.
const _KNOWN_SECTORS := ["F4", "F3"]

## Narrator beats (player-facing text).
const _BEATS := [
	"Ashveil Isle.\nA grey-green weed grows here that closes wounds like nothing else on earth.",
	"Helix Bioscience took the island for it.\nThe mines pay for their soldiers.",
	"Your contact is in Rookhaven.\nFind them.",
]

## Candidates for a rotor sound. If none exists it simply stays silent — a
## missing file must NEVER crash (Sfx.play is a no-op for an unknown key).
const _ROTOR_KEYS := ["heli", "helicopter", "rotor", "chopper", "heli_rotor"]

var _text: Label
var _hint: Label
var _fade: ColorRect
var _dust: CPUParticles2D

var _skipped := false
var _finished := false

func _main() -> Node:
	return get_parent()

func _ready() -> void:
	theme = UiTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 1)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_dust = _make_dust()
	add_child(_dust)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(v)

	_text = UiTheme.lbl("", 24, UiTheme.COL_TEXT)
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(860, 0)
	_text.modulate.a = 0.0
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_text)

	# Fade to black before jumping into combat.
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	_hint = UiTheme.lbl("Click or press any key to skip", 14, Color(0.55, 0.5, 0.4))
	_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.offset_top = -46
	_hint.offset_bottom = -18
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	_run()

# --------------------------------------------------------------- Skipping

func _input(event: InputEvent) -> void:
	if _skipped or _finished:
		return
	var go := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		go = true
	elif event is InputEventKey:
		var k := event as InputEventKey
		go = k.pressed and not k.echo
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		go = true
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		go = true
	if go:
		_skipped = true
		get_viewport().set_input_as_handled()

# --------------------------------------------------------------- Sequence

func _run() -> void:
	# Music is optional — play_music returns false when the track is missing.
	Sfx.play_music("exploration")
	var ok := true
	for b in _BEATS:
		ok = await _beat(String(b))
		if not ok:
			break
	if ok:
		ok = await _heli()
	await _fade_out(0.35 if ok else 0.15)
	_go()

func _beat(txt: String) -> bool:
	_text.text = txt
	_tween_alpha(_text, 1.0, 0.45)
	if not await _wait(0.45):
		return false
	if not await _wait(1.4):
		return false
	_tween_alpha(_text, 0.0, 0.35)
	return await _wait(0.35)

func _heli() -> bool:
	_text.text = ""
	_hint.modulate.a = 0.0
	_play_rotor()
	if _dust != null:
		_dust.position = Vector2(size.x * 0.5, size.y + 40.0)
		_dust.emitting = true
	return await _wait(1.4)

func _fade_out(d: float) -> void:
	if _fade != null:
		var tw := create_tween()
		tw.tween_property(_fade, "color:a", 1.0, d)
	await _wait_raw(d)

func _go() -> void:
	if _finished:
		return
	_finished = true
	if _dust != null:
		_dust.emitting = false
	# SPEC v5 §2/§3.3: a fresh run lands in the F4 landing zone (west exit -> F3),
	# but a continued game deploys into the sector the squad actually stands in —
	# otherwise a player who saved in F3 gets dropped back into F4.
	# Must be set BEFORE goto() — goto() calls add_child() and thus _ready()
	# synchronously.
	_main().start_sector = _resolve_sector()
	_main().goto(_DEST)

## Persisted sector, validated. Falls back to the start sector when `Game.sector`
## is empty or names a sector the tactical layer cannot build.
func _resolve_sector() -> String:
	var s := String(Game.sector)
	if s in _KNOWN_SECTORS:
		return s
	return String(Game.START_SECTOR)

# --------------------------------------------------------------- Helpers

## Waits [sec] seconds, but aborts immediately once skipped. Returns false when
## aborted. Deliberately no `await tween.finished`: after the screen change no
## coroutine may wake up on this node any more.
func _wait(sec: float) -> bool:
	var t := 0.0
	while t < sec:
		if _skipped or _finished:
			return false
		await get_tree().process_frame
		t += _dt()
	return not (_skipped or _finished)

## Like _wait, but not skippable (for the final fade).
func _wait_raw(sec: float) -> void:
	var t := 0.0
	while t < sec:
		if _finished:
			return
		await get_tree().process_frame
		t += _dt()

## Frame delta with a safety net — never 0, or the wait loop would run forever.
func _dt() -> float:
	var d := get_process_delta_time()
	if d <= 0.0:
		d = 1.0 / 60.0
	return d

func _tween_alpha(node: CanvasItem, a: float, d: float) -> void:
	var tw := create_tween()
	tw.tween_property(node, "modulate:a", a, d)

func _play_rotor() -> void:
	# If a real rotor sound exists, use it. Otherwise a few quiet whoosh pulses
	# from a key that does exist — nothing is invented.
	for k in _ROTOR_KEYS:
		if Sfx.streams.has(k):
			Sfx.play(String(k), -4.0, 0.02)
			return
	if not Sfx.streams.has("throw"):
		return
	# Deliberately without await/coroutine: after a skip nothing may wake up on
	# this (possibly already freed) node. The timer callbacks only touch the
	# Sfx autoload.
	for i in 5:
		var vol := -8.0 + float(i) * 0.8
		if i == 0:
			Sfx.play("throw", vol, 0.25)
			continue
		var t := get_tree().create_timer(0.18 * float(i))
		t.timeout.connect(func() -> void: Sfx.play("throw", vol, 0.25))

## Dust/downwash — CanvasItem particles (2D screen, gl_compatibility safe).
func _make_dust() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = _dot_texture()
	p.emitting = false
	p.amount = 90
	p.lifetime = 1.6
	p.explosiveness = 0.15
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(320, 12)
	p.direction = Vector2(0, -1)
	p.spread = 78.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 320.0
	p.gravity = Vector2(0, 90)
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.scale_amount_min = 2.5
	p.scale_amount_max = 7.0
	var g := Gradient.new()
	g.set_color(0, Color(0.72, 0.64, 0.48, 0.0))
	g.set_color(1, Color(0.55, 0.48, 0.36, 0.0))
	g.add_point(0.18, Color(0.78, 0.70, 0.52, 0.55))
	g.add_point(0.6, Color(0.62, 0.55, 0.42, 0.3))
	p.color_ramp = g
	return p

func _dot_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 32
	t.height = 32
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	return t

class_name CameraRig3D
extends Node3D
# CameraRig3D — self = PIVOT (Yaw). Kette: Pivot(self) -> Tilt(Node3D) -> Camera3D.
# Orthographische Iso-Kamera fuer die 3D-Taktik (Phase 1). Vertrag Section 6.

var tilt: Node3D
var cam: Camera3D
var yaw_deg := 45.0
var pitch_deg := -30.0
var zoom_size := 24.0
const ZOOM_MIN := 8.0
const ZOOM_MAX := 60.0
var field: AABB

# --- Phase 4 (Juice) Screenshake: additiv, kollisionsfrei ---
# h_offset/v_offset/rotation.z werden von der bestehenden Kette nirgends benutzt
# (pan=position, zoom=cam.size, yaw=self.rotation.y, pitch=tilt.rotation.x).
var trauma := 0.0
const TRAUMA_DECAY := 1.6          # Trauma/s Abklingrate
const SHAKE_POS := 0.45            # max. Bild-Offset (Welteinheiten bei ortho)
const SHAKE_ROT_DEG := 2.5         # max. Roll

# --- Politur: Kill-Zoom-Punch (kurzer Ortho-Zoom-Kick bei einem Kill) ---
var _punch_tween: Tween
const PUNCH_IN := 0.88             # Faktor auf zoom_size (12 % rein)
const PUNCH_IN_T := 0.09
const PUNCH_HOLD_T := 0.10
const PUNCH_OUT_T := 0.34

func setup(field_bounds: AABB) -> void:
	field = field_bounds

	# Tilt-Node als Kind des Pivots (self).
	tilt = Node3D.new()
	tilt.name = "Tilt"
	add_child(tilt)

	# Kamera als Kind des Tilt-Nodes.
	cam = Camera3D.new()
	cam.name = "Camera3D"
	tilt.add_child(cam)

	# Yaw am Pivot, Pitch am Tilt.
	rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	tilt.rotation = Vector3(deg_to_rad(pitch_deg), 0.0, 0.0)

	# Orthografische Projektion (size = Zoom, NICHT FOV).
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = zoom_size
	cam.near = 0.05
	cam.far = 1000.0
	# Offset entlang der lokalen Tilt-Achse (< far), sonst Near-Clipping (Fix M5).
	cam.position = Vector3(0.0, 0.0, 200.0)
	cam.current = true

	# Pivot ins Feldzentrum, y auf die min_level-Ebene (AABB-Unterkante).
	var center := field_bounds.get_center()
	position = Vector3(center.x, field_bounds.position.y, center.z)

func rotate_step(dir: int) -> void:
	yaw_deg += float(dir) * 45.0
	var target := deg_to_rad(yaw_deg)
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation:y", target, 0.25)

func zoom_by(factor: float) -> void:
	if cam == null:
		return
	# Basis ist zoom_size (nicht cam.size): waehrend eines Kill-Punches ist
	# cam.size temporaer kleiner — User-Zoom bricht den Punch ab und gewinnt.
	_cancel_zoom_punch()
	cam.size = clampf(zoom_size * factor, ZOOM_MIN, ZOOM_MAX)
	zoom_size = cam.size

func set_zoom(size: float) -> void:
	_cancel_zoom_punch()
	zoom_size = clampf(size, ZOOM_MIN, ZOOM_MAX)
	if cam != null:
		cam.size = zoom_size

## Politur: kurzer Zoom-Kick zum Kill — 12 % rein, halten, weich zurueck auf den
## User-Zoom. Laeuft auf Spielzeit: startet waehrend des Kill-Hitstops quasi
## eingefroren und entfaltet sich direkt danach (gewollte Sequenz Hitstop->Punch).
## Reentrancy wie hitstop(): ein zweiter Kill waehrend des Punches wird ignoriert.
func kill_zoom_punch() -> void:
	if cam == null:
		return
	if _punch_tween != null and _punch_tween.is_valid():
		return
	_punch_tween = create_tween()
	_punch_tween.tween_property(cam, "size", zoom_size * PUNCH_IN, PUNCH_IN_T)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_interval(PUNCH_HOLD_T)
	_punch_tween.tween_property(cam, "size", zoom_size, PUNCH_OUT_T)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _cancel_zoom_punch() -> void:
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	_punch_tween = null

func pan(delta_xz: Vector2) -> void:
	# Pan in der Yaw-rotierten Basis: Bildschirm-Delta in Welt-XZ drehen.
	var yaw := deg_to_rad(yaw_deg)
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var world_x := delta_xz.x * cos_y + delta_xz.y * sin_y
	var world_z := -delta_xz.x * sin_y + delta_xz.y * cos_y
	position.x += world_x
	position.z += world_z
	_clamp_to_field()

func focus_world(p: Vector3) -> void:
	position = Vector3(p.x, position.y, p.z)
	_clamp_to_field()

func _clamp_to_field() -> void:
	if field.size == Vector3.ZERO:
		return
	var min_p := field.position
	var max_p := field.position + field.size
	position.x = clampf(position.x, min_p.x, max_p.x)
	position.z = clampf(position.z, min_p.z, max_p.z)

# --- Phase 4 (Juice) Screenshake: additive API + Frame-Anwendung ---
# Wird NUR im interaktiven Modus gerufen (Orchestrator-Hooks: if not fast).
# Im Headless/Bot bleibt trauma == 0 -> _process macht Early-Return.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	if cam == null:
		return
	if trauma <= 0.0:
		# Rest-Offset hart nullen (Falle: sonst bleibt der letzte Rausch-Frame stehen).
		if cam.h_offset != 0.0 or cam.v_offset != 0.0 or cam.rotation.z != 0.0:
			cam.h_offset = 0.0
			cam.v_offset = 0.0
			cam.rotation.z = 0.0
		return
	trauma = maxf(trauma - TRAUMA_DECAY * delta, 0.0)
	var amt := trauma * trauma                    # shake = trauma^2 * rausch
	cam.h_offset = randf_range(-1.0, 1.0) * amt * SHAKE_POS
	cam.v_offset = randf_range(-1.0, 1.0) * amt * SHAKE_POS
	cam.rotation.z = randf_range(-1.0, 1.0) * amt * deg_to_rad(SHAKE_ROT_DEG)

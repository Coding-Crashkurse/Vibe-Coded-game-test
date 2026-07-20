class_name CameraRig3D
extends Node3D
# CameraRig3D — self = PIVOT (yaw). Chain: Pivot(self) -> Tilt(Node3D) -> Camera3D.
# Orthographic iso camera for the 3D tactics layer (phase 1). Contract section 6.

var tilt: Node3D
var cam: Camera3D
var yaw_deg := 45.0
var pitch_deg := -30.0
var zoom_size := 24.0
const ZOOM_MIN := 8.0
const ZOOM_MAX := 60.0
var field: AABB

# --- Phase 4 (juice) screenshake: additive, collision-free ---
# h_offset/v_offset/rotation.z are used nowhere by the existing chain
# (pan=position, zoom=cam.size, yaw=self.rotation.y, pitch=tilt.rotation.x).
var trauma := 0.0
const TRAUMA_DECAY := 1.6          # trauma/s decay rate
const SHAKE_POS := 0.45            # max. image offset (world units under ortho)
const SHAKE_ROT_DEG := 2.5         # max. roll

# --- Polish: kill zoom punch (short ortho zoom kick on a kill) ---
var _punch_tween: Tween
const PUNCH_IN := 0.88             # factor on zoom_size (12 % in)
const PUNCH_IN_T := 0.09
const PUNCH_HOLD_T := 0.10
const PUNCH_OUT_T := 0.34

func setup(field_bounds: AABB) -> void:
	field = field_bounds

	# Tilt node as a child of the pivot (self).
	tilt = Node3D.new()
	tilt.name = "Tilt"
	add_child(tilt)

	# Camera as a child of the tilt node.
	cam = Camera3D.new()
	cam.name = "Camera3D"
	tilt.add_child(cam)

	# Yaw on the pivot, pitch on the tilt.
	rotation = Vector3(0.0, deg_to_rad(yaw_deg), 0.0)
	tilt.rotation = Vector3(deg_to_rad(pitch_deg), 0.0, 0.0)

	# Orthographic projection (size = zoom, NOT FOV).
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = zoom_size
	cam.near = 0.05
	cam.far = 1000.0
	# Offset along the local tilt axis (< far), otherwise near-clipping (fix M5).
	cam.position = Vector3(0.0, 0.0, 200.0)
	cam.current = true

	# Pivot to the field centre, y on the min_level plane (AABB bottom edge).
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
	# The base is zoom_size (not cam.size): during a kill punch cam.size is
	# temporarily smaller — a user zoom cancels the punch and wins.
	_cancel_zoom_punch()
	cam.size = clampf(zoom_size * factor, ZOOM_MIN, ZOOM_MAX)
	zoom_size = cam.size

func set_zoom(size: float) -> void:
	_cancel_zoom_punch()
	zoom_size = clampf(size, ZOOM_MIN, ZOOM_MAX)
	if cam != null:
		cam.size = zoom_size

## Polish: short zoom kick on a kill — 12 % in, hold, softly back to the user
## zoom. Runs on game time: starts virtually frozen during the kill hitstop and
## unfolds right afterwards (the intended hitstop->punch sequence).
## Reentrancy like hitstop(): a second kill during the punch is ignored.
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
	# A user pan cancels a running sighting glide and wins.
	_cancel_glide()
	# Pan in the yaw-rotated basis: rotate the screen delta into world XZ.
	var yaw := deg_to_rad(yaw_deg)
	var cos_y := cos(yaw)
	var sin_y := sin(yaw)
	var world_x := delta_xz.x * cos_y + delta_xz.y * sin_y
	var world_z := -delta_xz.x * sin_y + delta_xz.y * cos_y
	position.x += world_x
	position.z += world_z
	_clamp_to_field()

func focus_world(p: Vector3) -> void:
	_cancel_glide()
	position = Vector3(p.x, position.y, p.z)
	_clamp_to_field()

## Sighting (the "enemy spotted" feature): the camera glides softly to the point
## instead of jumping (focus_world). The target is clamped to the field BEFORE the
## tween so the glide does not overshoot the edge and then snap back.
var _glide_tween: Tween

func glide_to(p: Vector3, dur := 0.5) -> void:
	_cancel_glide()
	var target := Vector3(p.x, position.y, p.z)
	if field.size != Vector3.ZERO:
		var min_p := field.position
		var max_p := field.position + field.size
		target.x = clampf(target.x, min_p.x, max_p.x)
		target.z = clampf(target.z, min_p.z, max_p.z)
	_glide_tween = create_tween()
	_glide_tween.tween_property(self, "position", target, dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _cancel_glide() -> void:
	if _glide_tween != null and _glide_tween.is_valid():
		_glide_tween.kill()
	_glide_tween = null

func _clamp_to_field() -> void:
	if field.size == Vector3.ZERO:
		return
	var min_p := field.position
	var max_p := field.position + field.size
	position.x = clampf(position.x, min_p.x, max_p.x)
	position.z = clampf(position.z, min_p.z, max_p.z)

# --- Phase 4 (juice) screenshake: additive API + per-frame application ---
# Called ONLY in interactive mode (orchestrator hooks: if not fast).
# In headless/bot mode trauma stays == 0 -> _process returns early.
func add_trauma(amount: float) -> void:
	trauma = clampf(trauma + amount, 0.0, 1.0)

func _process(delta: float) -> void:
	if cam == null:
		return
	if trauma <= 0.0:
		# hard-zero the residual offset (trap: otherwise the last noise frame sticks).
		if cam.h_offset != 0.0 or cam.v_offset != 0.0 or cam.rotation.z != 0.0:
			cam.h_offset = 0.0
			cam.v_offset = 0.0
			cam.rotation.z = 0.0
		return
	trauma = maxf(trauma - TRAUMA_DECAY * delta, 0.0)
	var amt := trauma * trauma                    # shake = trauma^2 * noise
	cam.h_offset = randf_range(-1.0, 1.0) * amt * SHAKE_POS
	cam.v_offset = randf_range(-1.0, 1.0) * amt * SHAKE_POS
	cam.rotation.z = randf_range(-1.0, 1.0) * amt * deg_to_rad(SHAKE_ROT_DEG)

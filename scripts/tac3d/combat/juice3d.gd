class_name Juice3D
extends Node3D
## Juice3D — visual game-feel layer of the 3D battle (spec §9).
## FIX F1: class_name Juice3D (peer module like CameraRig3D/CursorView3D; the
## orchestrator uses Juice3D.new() AND Juice3D.TRAUMA_*/HITSTOP_* — without a
## global name => parse error). Node3D, because all effects are rendered and
## tweens/timers need the tree. Instantiated EXCLUSIVELY in interactive mode
## (not fast); the orchestrator gates it additionally.
## Renderer = gl_compatibility -> CPUParticles3D instead of GPUParticles3D,
## QuadMesh ground quad instead of Decal.

var grid: Grid3D
var rig: CameraRig3D
var _hitstop_active := false
var _soft_tex: GradientTexture2D = null   # round soft texture (smoke/scorch), lazy + cached

# ---- central tuning constants (spec §9: "central, so you can tweak quickly") ----
const HITSTOP_HIT := 0.07          # s real time on hit damage
const HITSTOP_KILL := 0.10
const HITSTOP_EXPLOSION := 0.11
const TIME_SCALE_SLOW := 0.05

const TRAUMA_SHOT := 0.15          # shooter kick
const TRAUMA_HIT := 0.35
const TRAUMA_KILL := 0.55
const TRAUMA_EXPLOSION := 0.65

const MUZZLE_LIGHT_ENERGY := 8.0
const MUZZLE_LIGHT_RANGE := 4.5
const MUZZLE_LIFE := 0.10
const TRACER_LIFE := 0.10
const TRACER_RADIUS := 0.05        # m — tracer rod (gl_compatibility: 1px line invisible)
const BLOOD_FADE := 1.8            # s until ground blood disappears
const DMGNUM_RISE := 0.85          # m upwards
const DMGNUM_LIFE := 0.75
const HITFLASH_LIFE := 0.12
const EXPLOSION_LIGHT_ENERGY := 12.0

# Polish: casings / dust / smoke
const SHELL_FLIGHT := 0.45         # s flight time muzzle -> ground
const SHELL_LIFE := 2.4            # s time lying around until it fades out

# Grenade throw: flight time scales with throw distance, arc height likewise.
const GRENADE_FLIGHT_MIN := 0.45   # s base flight time
const GRENADE_FLIGHT_PER_M := 0.045  # s extra per metre of throw distance
const GRENADE_ARC_MIN := 1.2       # m minimum arc height (apex above the chord)
const GRENADE_ARC_FACTOR := 0.30   # arc height = throw distance * factor
const DUST_COLOR := Color(0.60, 0.53, 0.40, 0.55)
const SMOKE_COLOR := Color(0.22, 0.21, 0.19, 0.65)

# Sighting (spot): enemy discovered
const SPOT_LIFE := 1.6                            # s dwell time of the pulse ring
const SPOT_COL_ENEMY := Color(1.0, 0.30, 0.22)    # red: the one discovered

# Explosion (reference look: fireball + big black smoke cloud + scorch mark)
const EXPLO_FIREBALL_T := 0.30     # s growth time of the fireball
const EXPLO_SMOKE_COLOR := Color(0.10, 0.09, 0.09, 0.88)   # almost black
const EXPLO_SCORCH_LIFE := 7.0     # s until the scorch mark fades


func setup(g: Grid3D, camera_rig: CameraRig3D) -> void:
	grid = g
	rig = camera_rig


## FIX F2: the global Engine.time_scale is process-global. If this node is freed
## during a running hitstop (e.g. goto("end")), the reset continuation fizzles
## out and the world stays permanently at 0.05x. Therefore hard-reset it as soon
## as the node leaves the tree.
func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ============================================================ Hitstop
## Short slow motion. IMPORTANT (trap): reset via a REAL-TIME timer
## (ignore_time_scale=true), otherwise the reset itself runs in slow motion and
## the game stays slow. Reentrancy guard: a second hit during a running hitstop
## does not extend it but is ignored.
func hitstop(dur: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = TIME_SCALE_SLOW
	# create_timer(sec, process_always, process_in_physics, ignore_time_scale)
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false


# ============================================================ Muzzle flash
## One-shot spark burst + short OmniLight flash at the muzzle.
func muzzle_flash(world_pos: Vector3, dir: Vector3) -> void:
	# --- light ---
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = MUZZLE_LIGHT_ENERGY
	light.omni_range = MUZZLE_LIGHT_RANGE
	add_child(light)
	light.global_position = world_pos
	_fade_light_and_free(light, MUZZLE_LIFE)

	# --- sparks (CPUParticles3D: gl_compatibility-safe) ---
	var p := _spark_particles(Color(1.0, 0.8, 0.35), 14, 4.0, 0.14)
	p.direction = dir
	p.spread = 28.0
	add_child(p)
	p.global_position = world_pos
	_emit_oneshot_and_free(p, 0.2)


# ============================================================ Tracer
## Bright tracer rod muzzle->target, visible for ~100ms (TRACER_LIFE), then gone.
## CylinderMesh instead of a 1px ImmediateMesh line: in gl_compatibility the GL
## line width is fixed at 1px and is effectively invisible over the bright scene
## (the plan explicitly foresees the cylinder as an upgrade "if the 1px line
## looks too thin"). Solid, unshaded, no_depth_test => clearly visible over geometry.
func tracer(from_world: Vector3, to_world: Vector3) -> void:
	var length := from_world.distance_to(to_world)
	if length < 0.001:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = TRACER_RADIUS
	cyl.bottom_radius = TRACER_RADIUS
	cyl.height = length
	var mat := _unshaded(Color(1.0, 0.92, 0.55), false)   # solid, bright
	mat.no_depth_test = true                               # visible over geometry
	cyl.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	add_child(mi)
	mi.global_position = (from_world + to_world) * 0.5
	mi.look_at(to_world, Vector3.UP)                      # -Z points at the target
	mi.rotate_object_local(Vector3(1, 0, 0), PI / 2.0)    # cylinder axis (+Y) -> -Z
	_free_after(mi, TRACER_LIFE)


# ============================================================ Shell ejection
## Polish: a small brass casing (shotgun: red shell) flies in an arc to the
## right, tumbles, lands with a "clink", lies there briefly, fades out.
## No physics body — parabola via tween_method (cheap, deterministically free).
## ground_y = ground height of the shooter's cell so nothing hangs in mid-air.
## Exception to the "juice is silent" pattern: only the tween chain itself knows
## the landing moment, so IT plays the clink (Sfx.play is fallback-safe).
func shell_casing(muzzle: Vector3, dir: Vector3, ground_y: float, shotgun := false) -> void:
	# ~2x exaggerated (game convention): true-to-scale 5 cm casings are
	# sub-pixel small at ortho zoom 14+ (screenshot measurement) and thus invisible.
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.028 if shotgun else 0.021
	cyl.bottom_radius = cyl.top_radius
	cyl.height = 0.12 if shotgun else 0.08
	var mat := StandardMaterial3D.new()   # lit (sun present): glints
	mat.albedo_color = Color(0.72, 0.18, 0.12) if shotgun else Color(0.82, 0.62, 0.20)
	mat.metallic = 0.2 if shotgun else 0.75
	mat.roughness = 0.35
	cyl.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	add_child(mi)
	mi.global_position = muzzle

	# Ejection: to the right of the firing direction, slightly backwards, with spread.
	var side := dir.cross(Vector3.UP)
	side = side.normalized() if side.length() > 0.001 else Vector3.RIGHT
	var land := muzzle + side * randf_range(0.35, 0.7) - dir * randf_range(0.1, 0.3)
	land.y = ground_y + cyl.top_radius + 0.01

	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_method(_shell_arc.bind(mi, muzzle, land, randf_range(0.22, 0.4)), 0.0, 1.0, SHELL_FLIGHT)
	# Tumble: 1-2 flips around X, lands lying down (x = 90 degrees + full turns).
	var tumble := Vector3(PI * 0.5 + TAU * float(randi_range(1, 2)), randf() * TAU, 0.0)
	tw.tween_property(mi, "rotation", tumble, SHELL_FLIGHT)
	tw.chain().tween_callback(Sfx.play.bind("shell", -8.0, 0.3))
	tw.chain().tween_interval(SHELL_LIFE)
	tw.chain().tween_property(mi, "scale", Vector3.ONE * 0.01, 0.2)
	tw.chain().tween_callback(mi.queue_free)

## Parabola helper for shell_casing (t first, the rest appended via bind).
func _shell_arc(t: float, mi: MeshInstance3D, start: Vector3, land: Vector3, arc_h: float) -> void:
	if not is_instance_valid(mi):
		return
	var p := start.lerp(land, t)
	p.y += arc_h * 4.0 * t * (1.0 - t)
	mi.global_position = p


# ============================================================ Grenade throw
## A visible grenade flies in a high arc from the throwing hand to the target tile.
## Like shell_casing: no physics body — parabola via tween_method (_shell_arc),
## plus tumbling. Returns the FLIGHT TIME so the orchestrator can place the
## explosion exactly on the impact (await dl(flight_time)).
func grenade_throw(from: Vector3, to: Vector3) -> float:
	var dist := from.distance_to(to)
	var flight := GRENADE_FLIGHT_MIN + dist * GRENADE_FLIGHT_PER_M
	# ~2x exaggerated (like the casings): a true-to-scale 6 cm grenade would be
	# sub-pixel small at ortho zoom 14+ and thus invisible.
	var caps := CapsuleMesh.new()
	caps.radius = 0.09
	caps.height = 0.30
	var mat := StandardMaterial3D.new()   # lit: reads as an object, not as a spark
	mat.albedo_color = Color(0.24, 0.32, 0.18)   # olive
	mat.roughness = 0.55
	caps.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = caps
	add_child(mi)
	mi.global_position = from
	# Arc height grows with the throw distance — short throws flatter, long ones higher.
	var arc_h := maxf(GRENADE_ARC_MIN, dist * GRENADE_ARC_FACTOR)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_method(_shell_arc.bind(mi, from, to, arc_h), 0.0, 1.0, flight)
	# Tumble: 2 forward flips + some spin around the vertical axis.
	tw.tween_property(mi, "rotation", Vector3(TAU * 2.0, randf() * TAU, TAU * 0.5), flight)
	tw.chain().tween_callback(mi.queue_free)
	return flight


# ============================================================ Blood
## Ground-decal substitute (quad, NO Decal because of the renderer) + a small red splatter.
func blood(world_pos: Vector3, ground_pos: Vector3) -> void:
	# --- flat ground quad (fades out) ---
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := _unshaded(Color(0.55, 0.03, 0.03, 0.9), false)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	add_child(mi)
	mi.global_position = ground_pos + Vector3.UP * 0.02   # against Z-fighting
	mi.rotation_degrees = Vector3(-90.0, randf() * 360.0, 0.0)  # flat on the ground
	var tw := mi.create_tween()
	tw.tween_interval(BLOOD_FADE * 0.5)
	tw.tween_property(mat, "albedo_color:a", 0.0, BLOOD_FADE * 0.5)
	tw.tween_callback(mi.queue_free)

	# --- splatter at hit height ---
	var p := _spark_particles(Color(0.6, 0.02, 0.02), 8, 2.2, 0.35)
	p.direction = Vector3.UP
	p.spread = 55.0
	p.gravity = Vector3(0, -6.0, 0)
	add_child(p)
	p.global_position = world_pos
	_emit_oneshot_and_free(p, 0.5)


# ============================================================ Damage number
## Label3D above the target, rises + fades out. Kill = bigger + red.
## FIX F5: outline_modulate:a is tweened ALONG, otherwise the outline stays opaque.
func damage_number(world_pos: Vector3, amount: int, killed: bool) -> void:
	var lbl := Label3D.new()
	lbl.text = str(amount)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # turns towards the camera (trap)
	lbl.no_depth_test = true                            # never behind geometry
	lbl.fixed_size = true                               # constant readable size despite zoom
	lbl.render_priority = 10
	lbl.outline_size = 4
	lbl.modulate = Color(1.0, 0.25, 0.2) if killed else Color(1.0, 0.9, 0.4)
	lbl.font_size = 30 if killed else 22
	add_child(lbl)
	lbl.global_position = world_pos
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", world_pos.y + DMGNUM_RISE, DMGNUM_LIFE)
	tw.tween_property(lbl, "modulate:a", 0.0, DMGNUM_LIFE).set_delay(DMGNUM_LIFE * 0.35)
	tw.tween_property(lbl, "outline_modulate:a", 0.0, DMGNUM_LIFE).set_delay(DMGNUM_LIFE * 0.35)  # F5
	tw.chain().tween_callback(lbl.queue_free)


# ============================================================ Floating text
## Polish: free-floating info text (loot feedback "+ Item"/"Nothing found").
## Same style as damage_number (billboard, fixed_size, no_depth_test), but
## smaller, rising more slowly and with a longer reading time.
func float_text(world_pos: Vector3, text: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.render_priority = 10
	lbl.outline_size = 4
	lbl.modulate = col
	lbl.font_size = 20
	add_child(lbl)
	lbl.global_position = world_pos
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", world_pos.y + DMGNUM_RISE, 1.15)
	tw.tween_property(lbl, "modulate:a", 0.0, 1.15).set_delay(0.5)
	tw.tween_property(lbl, "outline_modulate:a", 0.0, 1.15).set_delay(0.5)
	tw.chain().tween_callback(lbl.queue_free)


# ============================================================ Hit flash
## White material overlay over ALL MeshInstance3D of the hit body
## (material_overlay does NOT overwrite the GLB original -> safe, unit3d.gd
## stays untouched). Additionally play_anim("hit") from the caller.
func hit_flash(unit: Node3D) -> void:
	var ov := _unshaded(Color(1, 1, 1, 0.65), true)     # additive white
	for mi in _mesh_instances(unit):
		mi.material_overlay = ov
	var tw := create_tween()
	tw.tween_property(ov, "albedo_color:a", 0.0, HITFLASH_LIFE)
	tw.tween_callback(func() -> void:
		for mi in _mesh_instances(unit):
			mi.material_overlay = null)


# ============================================================ Dust
## Polish: small ground puff on a step. Alpha MIX instead of additive —
## dust is DARKER than the ground; additive would make it glow like sparks.
func dust_puff(ground_pos: Vector3) -> void:
	var p := _puff_particles(DUST_COLOR, 5, 0.45, 0.9)
	p.direction = Vector3.UP
	p.spread = 70.0
	p.gravity = Vector3(0, 0.4, 0)   # slightly rising, hangs briefly in the air
	add_child(p)
	p.global_position = ground_pos + Vector3.UP * 0.06
	_emit_oneshot_and_free(p, 0.6)


# ============================================================ Sighting (spot)
## The "enemy discovered" feature: markers hang on the unit as CHILD NODES — they
## follow it, and if the unit disappears from sight again (set_seen ->
## Node3D.visible), the marker automatically disappears with it. Self-cleaning.

## The DISCOVERED enemy: red pulse ring on the ground (no more "!" — the sighting
## is instead reported by the merc himself via a portrait overlay in the HUD).
func spot_ping(unit: Node3D) -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.55
	ring.outer_radius = 0.68
	ring.rings = 4
	ring.ring_segments = 24   # lies flat in XZ (like the team ring in tac3d_unit)
	var mat := _unshaded(SPOT_COL_ENEMY, false)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	unit.add_child(mi)
	mi.position = Vector3(0, 0.09, 0)   # just above the team colour ring
	mi.scale = Vector3.ONE * 0.35
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.30)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.45).set_delay(SPOT_LIFE - 0.45)
	tw.chain().tween_callback(mi.queue_free)


# ============================================================ Explosion
## Reference look (JA1 screenshot): glaring fireball, THICK black smoke cloud,
## sparks/debris, charred ground. All gl_compatibility-safe
## (CPUParticles3D, meshes, NO Decal/GPU particles).
func explosion(world_pos: Vector3, radius: float) -> void:
	# --- light flash ---
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = EXPLOSION_LIGHT_ENERGY
	light.omni_range = radius * 3.0
	add_child(light)
	light.global_position = world_pos + Vector3.UP * 0.5
	_fade_light_and_free(light, 0.22)

	# --- Fireball: additive double ball (orange outside, blazing yellow inside),
	#     grows quickly to the effect radius and burns out. ---
	_fire_ball(world_pos + Vector3.UP * 0.55, radius * 1.05, Color(1.0, 0.45, 0.08, 0.85))
	_fire_ball(world_pos + Vector3.UP * 0.55, radius * 0.55, Color(1.0, 0.85, 0.35, 0.95))

	# --- sparks (hot fragments) ---
	var p := _spark_particles(Color(1.0, 0.6, 0.15), 48, 7.0, 0.7)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0, -5.0, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.4
	add_child(p)
	p.global_position = world_pos + Vector3.UP * 0.4
	_emit_oneshot_and_free(p, 0.9)

	# --- debris: dark chunks fly in an arc and fall ---
	var deb := CPUParticles3D.new()
	deb.emitting = false
	deb.one_shot = true
	deb.explosiveness = 1.0
	deb.amount = 14
	deb.lifetime = 0.9
	deb.direction = Vector3.UP
	deb.spread = 55.0
	deb.initial_velocity_min = 3.5
	deb.initial_velocity_max = 7.0
	deb.gravity = Vector3(0, -12.0, 0)
	deb.scale_amount_min = 0.5
	deb.scale_amount_max = 1.0
	var deb_mesh := BoxMesh.new()
	deb_mesh.size = Vector3(0.09, 0.07, 0.08)
	deb.mesh = deb_mesh
	var deb_mat := StandardMaterial3D.new()   # lit: reads as solid matter
	deb_mat.albedo_color = Color(0.16, 0.13, 0.10)
	deb_mat.roughness = 0.9
	deb.material_override = deb_mat
	add_child(deb)
	deb.global_position = world_pos + Vector3.UP * 0.4
	_emit_oneshot_and_free(deb, 1.1)

	# --- THE black cloud (reference image): big, sluggish, billows out of the centre ---
	var smoke := _puff_particles(EXPLO_SMOKE_COLOR, 26, 2.6, 1.5)
	smoke.direction = Vector3.UP
	smoke.spread = 40.0
	smoke.gravity = Vector3(0, 0.9, 0)          # slow buoyancy
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = radius * 0.5
	smoke.scale_amount_min = 1.1
	smoke.scale_amount_max = 2.2
	add_child(smoke)
	smoke.global_position = world_pos + Vector3.UP * 0.7
	_emit_oneshot_and_free(smoke, 3.0)

	# --- bright grey smoke as a rim (depth within the cloud) ---
	var smoke2 := _puff_particles(Color(0.35, 0.33, 0.30, 0.55), 10, 2.0, 2.0)
	smoke2.direction = Vector3.UP
	smoke2.spread = 60.0
	smoke2.gravity = Vector3(0, 1.2, 0)
	smoke2.scale_amount_min = 0.8
	smoke2.scale_amount_max = 1.5
	add_child(smoke2)
	smoke2.global_position = world_pos + Vector3.UP * 0.9
	_emit_oneshot_and_free(smoke2, 2.4)

	# --- Scorch mark: charred ground stays behind and fades slowly.
	#     Radial texture -> soft round patch instead of a hard black square. ---
	var quad := QuadMesh.new()
	quad.size = Vector2(radius * 2.3, radius * 2.3)
	var smat := _unshaded(Color(0.05, 0.045, 0.04, 0.8), false)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_texture = _soft_disc()
	quad.material = smat
	var scorch := MeshInstance3D.new()
	scorch.mesh = quad
	add_child(scorch)
	scorch.global_position = world_pos + Vector3.UP * 0.03   # against Z-fighting
	scorch.rotation_degrees = Vector3(-90.0, randf() * 360.0, 0.0)
	var stw := scorch.create_tween()
	stw.tween_interval(EXPLO_SCORCH_LIFE * 0.5)
	stw.tween_property(smat, "albedo_color:a", 0.0, EXPLO_SCORCH_LIFE * 0.5)
	stw.tween_callback(scorch.queue_free)


## Fireball building block: unshaded additive sphere, scales from small up to
## `radius` while fading out. Two balls on top of each other give the ember-core look.
func _fire_ball(center: Vector3, radius: float, col: Color) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var mat := _unshaded(col, true)   # additive -> glows (+ glow via HDR threshold)
	sphere.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	add_child(mi)
	mi.global_position = center
	mi.scale = Vector3.ONE * (radius * 0.15)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, EXPLO_FIREBALL_T)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, EXPLO_FIREBALL_T + 0.18)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.queue_free)


# ------------------------------------------------------------------ internal
func _spark_particles(col: Color, amount: int, speed: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0        # simultaneous burst
	p.amount = amount
	p.lifetime = life
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.18
	var m := QuadMesh.new()
	m.size = Vector2(0.12, 0.12)
	p.mesh = m
	p.material_override = _unshaded(col, true)   # additive, unshaded
	return p

## Polish: soft alpha particles (dust/smoke) — unlike _spark_particles NOT
## additive (dark puffs must be able to darken the ground) and with a fade-out
## ramp: color_ramp (white -> transparent) multiplies p.color.
## BILLBOARD_PARTICLES: the large quads must face the ortho camera, otherwise
## they stand at an angle in the world and look paper-thin.
func _puff_particles(col: Color, amount: int, life: float, speed: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = life
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.damping_min = 0.5
	p.damping_max = 1.2
	p.scale_amount_min = 0.35
	p.scale_amount_max = 0.7
	var m := QuadMesh.new()
	m.size = Vector2(0.5, 0.5)
	p.mesh = m
	var mat := _unshaded(Color(1, 1, 1, 1), false)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# Radial texture -> soft round puffs instead of visible squares (explosion!)
	mat.albedo_texture = _soft_disc()
	p.material_override = mat
	p.color = col
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = g
	return p

## one_shot trap: FIRST add_child (in the tree), THEN emitting=true, otherwise the
## burst fizzles out. Cleanup via an ignore_time_scale timer so it does not freeze
## during a hitstop.
func _emit_oneshot_and_free(p: CPUParticles3D, life: float) -> void:
	p.emitting = true
	_free_after(p, life)

func _fade_light_and_free(light: OmniLight3D, life: float) -> void:
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, life)
	tw.tween_callback(light.queue_free)

func _free_after(n: Node, life: float) -> void:
	await get_tree().create_timer(life, true, false, true).timeout   # ignore_time_scale
	if is_instance_valid(n):
		n.queue_free()

## Round soft texture (white -> transparent, radial). For smoke billboards and the
## scorch mark — turns hard quads into soft round patches. Cached.
func _soft_disc() -> GradientTexture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_soft_tex = GradientTexture2D.new()
		_soft_tex.gradient = g
		_soft_tex.fill = GradientTexture2D.FILL_RADIAL
		_soft_tex.fill_from = Vector2(0.5, 0.5)
		_soft_tex.fill_to = Vector2(0.5, 0.0)
		_soft_tex.width = 64
		_soft_tex.height = 64
	return _soft_tex


func _unshaded(col: Color, additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	if additive:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _mesh_instances(root: Node) -> Array:
	var out: Array = []
	_collect_meshes(root, out)
	return out

func _collect_meshes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for child in n.get_children():
		_collect_meshes(child, out)

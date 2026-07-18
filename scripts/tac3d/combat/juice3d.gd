class_name Juice3D
extends Node3D
## Juice3D — visuelle Game-Feel-Schicht der 3D-Schlacht (spec §9).
## FIX F1: class_name Juice3D (Peer-Modul wie CameraRig3D/CursorView3D; der
## Orchestrator nutzt Juice3D.new() UND Juice3D.TRAUMA_*/HITSTOP_* — ohne
## globalen Namen => Parse-Error). Node3D, weil alle Effekte gerendert werden
## und Tweens/Timer den Baum brauchen. Wird AUSSCHLIESSLICH im interaktiven
## Modus (not fast) instanziiert; der Orchestrator gatet zusaetzlich.
## Renderer = gl_compatibility -> CPUParticles3D statt GPUParticles3D,
## QuadMesh-Bodenquad statt Decal.

var grid: Grid3D
var rig: CameraRig3D
var _hitstop_active := false

# ---- zentrale Tuning-Konstanten (spec §9: "zentral, damit man schnell schrauben kann") ----
const HITSTOP_HIT := 0.07          # s Realzeit bei Trefferschaden
const HITSTOP_KILL := 0.10
const HITSTOP_EXPLOSION := 0.11
const TIME_SCALE_SLOW := 0.05

const TRAUMA_SHOT := 0.15          # Schuetzen-Kick
const TRAUMA_HIT := 0.35
const TRAUMA_KILL := 0.55
const TRAUMA_EXPLOSION := 0.65

const MUZZLE_LIGHT_ENERGY := 8.0
const MUZZLE_LIGHT_RANGE := 4.5
const MUZZLE_LIFE := 0.10
const TRACER_LIFE := 0.10
const TRACER_RADIUS := 0.05        # m — Leuchtspur-Stab (gl_compatibility: 1px-Linie unsichtbar)
const BLOOD_FADE := 1.8            # s bis Bodenblut verschwindet
const DMGNUM_RISE := 0.85          # m nach oben
const DMGNUM_LIFE := 0.75
const HITFLASH_LIFE := 0.12
const EXPLOSION_LIGHT_ENERGY := 12.0


func setup(g: Grid3D, camera_rig: CameraRig3D) -> void:
	grid = g
	rig = camera_rig


## FIX F2: globaler Engine.time_scale ist prozessglobal. Wird dieser Node
## waehrend eines laufenden Hitstops gefreed (z.B. goto("end")), verpufft die
## Reset-Continuation und die Welt bleibt permanent in 0.05x. Deshalb hart
## zuruecksetzen, sobald der Node den Baum verlaesst.
func _exit_tree() -> void:
	Engine.time_scale = 1.0


# ============================================================ Hitstop
## Kurze Zeitlupe. WICHTIG (Falle): Reset ueber einen REALZEIT-Timer
## (ignore_time_scale=true), sonst laeuft der Reset selbst in Zeitlupe und
## das Spiel bleibt langsam. Reentrancy-Guard: ein zweiter Treffer waehrend
## eines laufenden Hitstops verlaengert nicht, sondern wird ignoriert.
func hitstop(dur: float) -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	Engine.time_scale = TIME_SCALE_SLOW
	# create_timer(sec, process_always, process_in_physics, ignore_time_scale)
	await get_tree().create_timer(dur, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false


# ============================================================ Muendungsfeuer
## One-Shot-Funkenburst + kurzer OmniLight-Blitz an der Muendung.
func muzzle_flash(world_pos: Vector3, dir: Vector3) -> void:
	# --- Licht ---
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = MUZZLE_LIGHT_ENERGY
	light.omni_range = MUZZLE_LIGHT_RANGE
	add_child(light)
	light.global_position = world_pos
	_fade_light_and_free(light, MUZZLE_LIFE)

	# --- Funken (CPUParticles3D: gl_compatibility-sicher) ---
	var p := _spark_particles(Color(1.0, 0.8, 0.35), 14, 4.0, 0.14)
	p.direction = dir
	p.spread = 28.0
	add_child(p)
	p.global_position = world_pos
	_emit_oneshot_and_free(p, 0.2)


# ============================================================ Leuchtspur
## Heller Leuchtspur-Stab Muendung->Ziel, ~100ms sichtbar (TRACER_LIFE), dann weg.
## CylinderMesh statt 1px-ImmediateMesh-Linie: in gl_compatibility ist die
## GL-Linienbreite fix 1px und ueber der hellen Szene faktisch unsichtbar
## (der Plan sieht den Cylinder als Upgrade "falls die 1px-Linie zu duenn wirkt"
## explizit vor). Solide, unshaded, no_depth_test => klar sichtbar ueber Geometrie.
func tracer(from_world: Vector3, to_world: Vector3) -> void:
	var length := from_world.distance_to(to_world)
	if length < 0.001:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = TRACER_RADIUS
	cyl.bottom_radius = TRACER_RADIUS
	cyl.height = length
	var mat := _unshaded(Color(1.0, 0.92, 0.55), false)   # solide, hell
	mat.no_depth_test = true                               # ueber Geometrie sichtbar
	cyl.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	add_child(mi)
	mi.global_position = (from_world + to_world) * 0.5
	mi.look_at(to_world, Vector3.UP)                      # -Z zeigt aufs Ziel
	mi.rotate_object_local(Vector3(1, 0, 0), PI / 2.0)    # Cylinder-Achse (+Y) -> -Z
	_free_after(mi, TRACER_LIFE)


# ============================================================ Blut
## Bodendekal-Ersatz (Quad, KEIN Decal wg. Renderer) + kleiner roter Spritzer.
func blood(world_pos: Vector3, ground_pos: Vector3) -> void:
	# --- flaches Bodenquad (faded aus) ---
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := _unshaded(Color(0.55, 0.03, 0.03, 0.9), false)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	add_child(mi)
	mi.global_position = ground_pos + Vector3.UP * 0.02   # gegen Z-Fighting
	mi.rotation_degrees = Vector3(-90.0, randf() * 360.0, 0.0)  # flach auf den Boden
	var tw := mi.create_tween()
	tw.tween_interval(BLOOD_FADE * 0.5)
	tw.tween_property(mat, "albedo_color:a", 0.0, BLOOD_FADE * 0.5)
	tw.tween_callback(mi.queue_free)

	# --- Spritzer in Trefferhoehe ---
	var p := _spark_particles(Color(0.6, 0.02, 0.02), 8, 2.2, 0.35)
	p.direction = Vector3.UP
	p.spread = 55.0
	p.gravity = Vector3(0, -6.0, 0)
	add_child(p)
	p.global_position = world_pos
	_emit_oneshot_and_free(p, 0.5)


# ============================================================ Schadenszahl
## Label3D ueber dem Ziel, steigt auf + blendet aus. Kill = groesser + rot.
## FIX F5: outline_modulate:a wird MITgetweent, sonst bleibt der Umriss opak stehen.
func damage_number(world_pos: Vector3, amount: int, killed: bool) -> void:
	var lbl := Label3D.new()
	lbl.text = str(amount)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED   # dreht sich zur Kamera (Falle)
	lbl.no_depth_test = true                            # nie hinter Geometrie
	lbl.fixed_size = true                               # konstante Lesegroesse trotz Zoom
	lbl.render_priority = 10
	lbl.outline_size = 6
	lbl.modulate = Color(1.0, 0.25, 0.2) if killed else Color(1.0, 0.9, 0.4)
	lbl.font_size = 96 if killed else 64
	add_child(lbl)
	lbl.global_position = world_pos
	var tw := lbl.create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "global_position:y", world_pos.y + DMGNUM_RISE, DMGNUM_LIFE)
	tw.tween_property(lbl, "modulate:a", 0.0, DMGNUM_LIFE).set_delay(DMGNUM_LIFE * 0.35)
	tw.tween_property(lbl, "outline_modulate:a", 0.0, DMGNUM_LIFE).set_delay(DMGNUM_LIFE * 0.35)  # F5
	tw.chain().tween_callback(lbl.queue_free)


# ============================================================ Treffer-Flash
## Weisser Material-Overlay ueber ALLEN MeshInstance3D des getroffenen Bodys
## (material_overlay ueberschreibt das GLB-Original NICHT -> sicher, unit3d.gd
## bleibt unangetastet). Zusaetzlich play_anim("hit") vom Aufrufer.
func hit_flash(unit: Node3D) -> void:
	var ov := _unshaded(Color(1, 1, 1, 0.65), true)     # additiv-weiss
	for mi in _mesh_instances(unit):
		mi.material_overlay = ov
	var tw := create_tween()
	tw.tween_property(ov, "albedo_color:a", 0.0, HITFLASH_LIFE)
	tw.tween_callback(func() -> void:
		for mi in _mesh_instances(unit):
			mi.material_overlay = null)


# ============================================================ Explosion
func explosion(world_pos: Vector3, radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.3)
	light.light_energy = EXPLOSION_LIGHT_ENERGY
	light.omni_range = radius * 2.5
	add_child(light)
	light.global_position = world_pos + Vector3.UP * 0.5
	_fade_light_and_free(light, 0.18)

	var p := _spark_particles(Color(1.0, 0.6, 0.15), 40, 6.0, 0.6)
	p.direction = Vector3.UP
	p.spread = 80.0
	p.gravity = Vector3(0, -4.0, 0)
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.4
	add_child(p)
	p.global_position = world_pos + Vector3.UP * 0.4
	_emit_oneshot_and_free(p, 0.9)


# ------------------------------------------------------------------ intern
func _spark_particles(col: Color, amount: int, speed: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.explosiveness = 1.0        # simultaner Burst
	p.amount = amount
	p.lifetime = life
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.scale_amount_min = 0.08
	p.scale_amount_max = 0.18
	var m := QuadMesh.new()
	m.size = Vector2(0.12, 0.12)
	p.mesh = m
	p.material_override = _unshaded(col, true)   # additiv, unshaded
	return p

## Falle one_shot: ERST add_child (im Baum), DANN emitting=true, sonst verpufft der
## Burst. Cleanup ueber ignore_time_scale-Timer, damit er nicht im Hitstop einfriert.
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

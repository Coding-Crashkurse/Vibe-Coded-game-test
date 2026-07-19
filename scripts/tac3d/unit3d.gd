class_name Unit3D
extends Node3D

## Sichtbarer Body einer 3D-Einheit. Lädt ein modernes Quaternius-Söldner-
## modell (Swat/Casual/BusinessMan.glb, CharacterArmature-Rig inkl.
## Skeleton3D + AnimationPlayer, self-contained) über den Assets3D-Autoload
## und hängt eine Waffe an den Hand-Bone "Wrist.R". Fehlt die GLB, liefert
## Assets3D eine Fallback-Kapsel — dann ist play_anim ein No-Op (kein
## AnimationPlayer). So bleibt der Headless-Smoke auch ganz ohne Assets grün.

signal move_finished

# Modell-Fußpunkt sitzt bei den Füßen -> auf die Kachel-Oberkante (0,2-Box) heben.
const MODEL_Y_OFFSET := 0.1
# S3 VERIFIZIERT (Phase 5): Die Waffe haengt am Wrist.R-Bone. Dessen Weltskala ist 100x
# (das Quaternius-CharacterArmature hat node_scale=100). Die rifle.glb misst bei Skala 1
# schon ~2,26 Welteinheiten (eigene 100x-Mesh-Skala). Ohne Gegenskalierung waere das
# Gewehr also 100*2,26 = ~226 Einheiten lang (frueher *0,6 = ~136 -> die "Riesen-Bloecke"
# im Screenshot). 0,0035 ergibt ~0,79 Einheiten Lauflaenge fuer den 1,85-Einheiten-Soeldner.
const WEAPON_SCALE := 0.0035
# Feinjustage der Waffe im Wrist.R-Bone-Space (Bone-Space ist 100x -> lokale Offsets klein halten).
const WEAPON_OFFSET := Vector3(0.0, 0.0, 0.0)
const WEAPON_EULER_DEG := Vector3(0.0, 0.0, 0.0)

# --- Blickrichtung (Facing) ---------------------------------------------------
# Weiche Drehgeschwindigkeit des Mesh Richtung Ziel-Yaw (rad/s-artiges lerp_angle-Gewicht).
const TURN_SPEED := 10.0
# Das Quaternius-CharacterArmature schaut in seiner Bind-Pose nach WELT +Z (Gesicht,
# Kniepolster und Fussspitzen zeigen bei rotation.y=0 nach +Z — per Frontal-Kamera-
# Screenshot des UNROTIERTEN Swat.glb verifiziert, 2026-07-19; die fruehere "-Z"-
# Behauptung war falsch, die Figuren liefen dadurch rueckwaerts). Unser Yaw ist
# atan2(dx, dz) mit +Z als 0-Richtung; eine +Z-Front braucht also KEINEN Offset.
const FACING_OFFSET_DEG := 0.0

# GDScript-Namen -> Quaternius-Clip-Namen (CharacterArmature-Rig, 24 Anims, kein Retarget).
# S1 VERIFIZIERT (Phase 5): Godot behaelt beim glTF-Import die "CharacterArmature|<Name>"-
# Praefixe UNVERAENDERT bei (keine AnimationLibrary-Umbenennung, kein Strippen). Die echte
# get_animation_list() lautet exakt: Death, Gun_Shoot, HitRecieve, HitRecieve_2, Idle,
# Idle_Gun, Idle_Gun_Pointing, Idle_Gun_Shoot, Idle_Neutral, Idle_Sword, Interact,
# Kick_Left/Right, Punch_Left/Right, Roll, Run, Run_Back/Left/Right, Run_Shoot, Sword_Slash,
# Walk, Wave (je "CharacterArmature|"-praefixiert). Alle 10 Eintraege unten treffen echte
# Clips -> play_anim spielt, das Modell steht im Idle, NICHT in T-Pose.
const _CLIPS := {
	"idle": "CharacterArmature|Idle",
	"walk": "CharacterArmature|Walk",
	"run": "CharacterArmature|Run",
	"shoot": "CharacterArmature|Gun_Shoot",
	"aim": "CharacterArmature|Idle_Gun_Pointing",
	"reload": "CharacterArmature|Idle_Gun",     # KEIN echter Reload-Clip -> Halte-Pose
	"hit": "CharacterArmature|HitRecieve",
	"death": "CharacterArmature|Death",
	"throw": "CharacterArmature|Sword_Slash",    # KEIN echter Throw-Clip -> Armschwung (Wurf-Naeherung)
	"loot": "CharacterArmature|Interact",
}

# Dauer-Anims loopen; One-Shots (shoot/hit/death/throw/loot) laufen einmal.
const _LOOPING := {
	"idle": true, "walk": true, "run": true, "aim": true, "reload": true,
}

var grid: Grid3D
var cell := Vector3i.ZERO
var moving := false
var fast := false            # true = sofort snappen (Headless), kein Tween

var _mesh: Node3D                     # GLB-Wurzel ODER Fallback-Kapsel
var _anim: AnimationPlayer = null     # rekursiv gefunden; null bei Fallback

var _target_yaw := 0.0                 # Ziel-Blickrichtung (Mesh-Yaw), von face_toward gesetzt
var _has_target_yaw := false           # erst nach erstem face_toward/Spawn drehen


func setup(g: Grid3D, start: Vector3i, char_id := "merc") -> void:
	grid = g
	# Body: moderner Söldner nach Rolle (Fallback-Kapsel wenn GLB fehlt).
	_mesh = Assets3D.character(char_id)
	add_child(_mesh)
	# AnimationPlayer null-sicher rekursiv suchen (Fallback-Kapsel hat keinen).
	_anim = _find_anim(_mesh)
	# One-Shot-Anims (Schuss/Treffer) sollen nach Ende zu Idle zurueckkehren.
	if _anim != null and not _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.connect(_on_anim_finished)
	# Waffe an den echten Hand-Bone hängen (nur wenn ein Skelett existiert).
	var skel := _find_skeleton(_mesh)
	if skel != null:
		var att := BoneAttachment3D.new()
		# S2: Wrist.R absichern; Godot kann glTF-Bones umschreiben (Wrist_R).
		var bone := "Wrist.R"
		if skel.find_bone(bone) < 0:
			push_warning("Unit3D: Bone 'Wrist.R' nicht gefunden — versuche 'Wrist_R'.")
			if skel.find_bone("Wrist_R") >= 0:
				bone = "Wrist_R"
		att.bone_name = bone
		skel.add_child(att)
		# S3: primär Gewehr (Söldner-Look); fehlt rifle.glb -> Fallback Pistole.
		var gun_id := "rifle"
		if not ResourceLoader.exists("res://assets/models/weapons/rifle.glb"):
			gun_id = "pistol"
		var gun := Assets3D.weapon(gun_id)
		gun.scale = Vector3.ONE * WEAPON_SCALE
		gun.position = WEAPON_OFFSET
		gun.rotation_degrees = WEAPON_EULER_DEG
		att.add_child(gun)
	# Charakter-Meshes sollen im Sonnenlicht Schatten werfen (rekursiv, Fallback-sicher).
	_enable_shadows(_mesh)
	set_cell(start)
	# Startdrehung: Figur schaut zur Kartenmitte (statt alle identisch in +Z zu stehen).
	# Fallback auf negatives Z, falls die Grid-Groesse noch nicht bekannt ist.
	var center := Vector3(position.x, position.y, position.z - 1.0)
	if grid != null and grid.size_x > 0 and grid.size_z > 0:
		center = grid.cell_to_world(Vector3i(grid.size_x / 2, start.y, grid.size_z / 2))
	face_toward(center, true)   # sofort setzen (Spawn), nicht weich eindrehen
	play_anim("idle")


func set_cell(c: Vector3i) -> void:
	cell = c
	if grid != null:
		position = grid.cell_to_world(c) + Vector3(0, MODEL_Y_OFFSET, 0)


## Spielt einen Clip nach GDScript-Name. No-Op bei Fallback-Kapsel (kein _anim).
func play_anim(which: String) -> void:
	if _anim == null:
		return
	var clip: String = _CLIPS.get(which, "CharacterArmature|Idle")
	if not _anim.has_animation(clip):
		return
	# glTF-Clips importieren OHNE Loop -> Dauer-Anims wuerden EINMAL spielen und
	# einfrieren ("quasi 0 Animation"). Loop-Modus je Clip-Typ setzen.
	var a := _anim.get_animation(clip)
	if a != null:
		a.loop_mode = Animation.LOOP_LINEAR if bool(_LOOPING.get(which, false)) else Animation.LOOP_NONE
	# Custom-Blend (0.18s) -> weiche Uebergaenge Idle<->Laufen<->Schuss statt hartem Cut.
	_anim.play(clip, 0.18)


## One-Shot-Anims kehren nach Ende zu Idle zurueck. Loop-Anims feuern
## animation_finished nie (laufen ewig); der Tod bleibt liegen.
func _on_anim_finished(anim_name: StringName) -> void:
	if _anim == null:
		return
	if String(anim_name) == String(_CLIPS["death"]):
		return
	play_anim("idle")


func follow_path(world_points: Array) -> void:
	if world_points.is_empty():
		moving = false
		move_finished.emit()
		return

	if fast:
		# Headless: sofort ans Ende snappen. Der Orchestrator ruft im
		# fast-Modus set_cell(goal) ohnehin separat; hier nur sauber terminieren.
		# KEINE Animation, kein Tween -> Smoke bleibt schnell & grün.
		var last: Vector3 = world_points.back()
		position = last
		moving = false
		move_finished.emit()
		return

	moving = true
	play_anim("walk")   # durchgehend Laufen bis Pfadende (kein Flackern zwischen Segmenten)
	var tween := create_tween()
	# Konstantes Tempo, weiche Sine-Kurve, Figur schaut in Laufrichtung (nur Y-Achse).
	for p in world_points:
		var pt: Vector3 = p
		var goal := pt + Vector3(0, MODEL_Y_OFFSET, 0)
		# Blickrichtung vor jedem Segment weich zum naechsten Punkt drehen.
		# face_toward setzt nur das Ziel-Yaw; _process dreht das Mesh weich dorthin.
		tween.tween_callback(face_toward.bind(goal))
		tween.tween_property(self, "position", goal, 0.22) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func() -> void:
		moving = false
		play_anim("idle")
		move_finished.emit()
	)


## ÖFFENTLICH: Dreht das Mesh so, dass die Figur die Weltposition ANSIEHT.
##
## Signatur:  face_toward(world_pos: Vector3, instant := false) -> void
##   world_pos — anzublickender Punkt in Weltkoordinaten (nur X/Z zaehlen).
##   instant   — true: sofort snappen (Spawn/fast); false: weich per _process eindrehen.
##
## Der Orchestrator ruft z.B. in shoot() face_toward(ziel.global_position) auf, damit der
## Schuetze zum Ziel schaut. Kampf-Logik/Node-Transform bleiben unberuehrt (nur _mesh dreht).
func face_toward(world_pos: Vector3, instant := false) -> void:
	var dx := world_pos.x - global_position.x
	var dz := world_pos.z - global_position.z
	# Ziel praktisch senkrecht ueber/unter uns -> keine sinnvolle Richtung, alte behalten.
	if Vector2(dx, dz).length() < 0.001:
		return
	# atan2(dx, dz) = Yaw mit +Z als 0-Richtung; FACING_OFFSET_DEG korrigiert die Modell-Front.
	_target_yaw = atan2(dx, dz) + deg_to_rad(FACING_OFFSET_DEG)
	_has_target_yaw = true
	# Im Headless/fast-Modus (oder bewusst instant) hart setzen: kein weiches _process noetig.
	if instant or fast:
		if _mesh != null:
			_mesh.rotation.y = _target_yaw


## Weiche Drehung des Mesh Richtung _target_yaw. Im fast/Headless-Modus billiger No-Op.
func _process(delta: float) -> void:
	if fast or _mesh == null or not _has_target_yaw:
		return
	_mesh.rotation.y = lerp_angle(_mesh.rotation.y, _target_yaw, minf(1.0, TURN_SPEED * delta))


# ------------------------------------------------------------------ intern

## Sucht rekursiv den ersten AnimationPlayer im Baum (null wenn keiner da ist).
func _find_anim(n: Node) -> AnimationPlayer:
	if n == null:
		return null
	if n is AnimationPlayer:
		return n
	for child in n.get_children():
		var found := _find_anim(child)
		if found != null:
			return found
	return null


## Setzt rekursiv cast_shadow ON an allen MeshInstance3D-Kindern (Fallback-Kapsel inklusive).
func _enable_shadows(n: Node) -> void:
	if n == null:
		return
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in n.get_children():
		_enable_shadows(child)


## Sucht rekursiv das erste Skeleton3D im Baum (null bei Fallback-Kapsel).
func _find_skeleton(n: Node) -> Skeleton3D:
	if n == null:
		return null
	if n is Skeleton3D:
		return n
	for child in n.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

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
	"throw": "CharacterArmature|Gun_Shoot",      # KEIN echter Throw-Clip -> Fallback
	"loot": "CharacterArmature|Interact",
}

var grid: Grid3D
var cell := Vector3i.ZERO
var moving := false
var fast := false            # true = sofort snappen (Headless), kein Tween

var _mesh: Node3D                     # GLB-Wurzel ODER Fallback-Kapsel
var _anim: AnimationPlayer = null     # rekursiv gefunden; null bei Fallback


func setup(g: Grid3D, start: Vector3i, char_id := "merc") -> void:
	grid = g
	# Body: moderner Söldner nach Rolle (Fallback-Kapsel wenn GLB fehlt).
	_mesh = Assets3D.character(char_id)
	add_child(_mesh)
	# AnimationPlayer null-sicher rekursiv suchen (Fallback-Kapsel hat keinen).
	_anim = _find_anim(_mesh)
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
	set_cell(start)
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
	if _anim.has_animation(clip):
		_anim.play(clip)


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
	play_anim("walk")
	var tween := create_tween()
	for p in world_points:
		var pt: Vector3 = p
		tween.tween_property(self, "position", pt + Vector3(0, MODEL_Y_OFFSET, 0), 0.15)
	tween.finished.connect(func() -> void:
		moving = false
		play_anim("idle")
		move_finished.emit()
	)


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

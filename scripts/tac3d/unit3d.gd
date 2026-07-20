class_name Unit3D
extends Node3D

## Visible body of a 3D unit. Loads a modern Quaternius merc model
## (Swat/Casual/BusinessMan.glb and the 20 modular bodies — CharacterArmature
## rig incl. Skeleton3D + AnimationPlayer, self-contained) through the Assets3D
## autoload and attaches a weapon to the hand bone "Wrist.R". When the GLB is
## missing Assets3D returns a fallback capsule — play_anim is then a no-op (no
## AnimationPlayer). That keeps the headless smoke green with no assets at all.
##
## SPEC §4.1: the body can alternatively come from a PREFAB
## (res://scenes/units/merc_<id>.tscn) that packs model + uniform colour +
## weapon attachment as data. The prefab is strictly OPTIONAL — if it is absent
## or broken, setup() silently uses the direct Assets3D.character() path.
##
## PREFAB CONTRACT (see res://scenes/units/merc_*.tscn). The prefab is a bare
## Node3D that carries only METADATA — it deliberately does NOT embed the GLB:
##   metadata/model        String — Assets3D.CHARACTERS id of the body
##   metadata/uniform      Color  — uniform colour (alpha > 0 = "set")
##   metadata/weapon_model String — Assets3D.WEAPONS id ("rifle"/"pistol")
##   metadata/weapon_id    String — Db.WEAPONS id ("p9"/"svd"/...)
##   metadata/merc_id      String — Db.MERCS id, for debugging only
## Naming the model instead of referencing the .glb keeps the FALLBACK LAW
## intact: a missing GLB still degrades to the Assets3D capsule instead of
## turning the whole .tscn into an unloadable resource.

signal move_finished

# The model's foot point sits at the feet -> lift it onto the tile top (0.2 box).
const MODEL_Y_OFFSET := 0.1
# S3 VERIFIED (phase 5): the weapon hangs off the Wrist.R bone. Its world scale is
# 100x (the Quaternius CharacterArmature has node_scale=100). rifle.glb already
# measures ~2.26 world units at scale 1 (its own 100x mesh scale). Without counter-
# scaling the rifle would be 100*2.26 = ~226 units long (previously *0.6 = ~136 ->
# the "giant blocks" in the screenshot). 0.0035 yields ~0.79 units of barrel length
# for the 1.85-unit merc.
# Fit per weapon MODEL in Wrist.R bone space (100x -> keep the local values tiny).
# Euler verified by candidate screenshot probe in the aim pose (2026-07-19,
# close-ups; INVISIBLE headless!): Z=+90 points BOTH models forward (sight up,
# barrel along the outstretched arm). The earlier pistol rotation Y=+90 was WRONG
# (barrel across the fist -> pistol practically invisible, user bug report).
# pistol.obj measures ~1.82 units -> 0.0022 yields ~0.40 world units (slightly
# oversized like the shell casings, otherwise it is sub-pixel small).
## FALLBACK table per weapon MODEL. Since SPEC §4.1 step 3 the authoritative
## source is `Db.WEAPONS[<weapon_id>]["attach_offset"]` (data instead of code) —
## this constant only applies when the Db entry is missing (unknown weapon, call
## without a weapon id, foreign code). The numbers are identical, so nothing
## shifts. combat_hud.gd reads it as well -> stays public.
const WEAPON_FITS := {
	"rifle":  {"scale": 0.0035, "offset": Vector3.ZERO, "euler": Vector3(0.0, 0.0, 90.0)},
	"pistol": {"scale": 0.0022, "offset": Vector3.ZERO, "euler": Vector3(0.0, 0.0, 90.0)},
}

# --- Uniform colouring (SPEC §4.1 step 4) ------------------------------------
## BODY materials that are NEVER recoloured (substring compare, lower case).
## Deliberately a DENY list: the 20 modular Quaternius characters name their
## clothing completely differently (Suit, Swat, Worker_Vest, SciFi_Main, Purple,
## Metal, Beige, Brown2 ...) — an allow list would not have matched most models.
## Everything NOT listed here counts as clothing/gear and gets the uniform colour.
## "eye" also covers "Eyebrows", "hair" also covers "Hair_Brown"/"Hair_Blond" etc.
const SKIN_MATERIALS := [
	"skin", "hair", "eye", "brow", "visor", "earring",
	"moustache", "mustache", "beard", "teeth", "tooth", "mouth", "lash",
]
## Blend factor for the EMERGENCY path (no known clothing material found, e.g. a
## fallback capsule or a foreign GLB): a subtle full-body tint instead of an ugly
## full recolour — correctness before aggressiveness.
const UNIFORM_SUBTLE_MIX := 0.35
## Meta key prefix under which a MeshInstance3D remembers the ORIGINAL albedo of
## each surface. Without it a second set_uniform_color() call would recolour an
## already recoloured material and the colour would drift (the prefab bakes the
## colour, Tac3DUnit sets it again from the Db -> two calls are normal).
const UNIFORM_BASE_META := "u3d_albedo_"

# --- Facing -------------------------------------------------------------------
# Soft turn speed of the mesh toward the target yaw (rad/s-like lerp_angle weight).
const TURN_SPEED := 10.0
# The Quaternius CharacterArmature looks toward WORLD +Z in its bind pose (face,
# knee pads and toes point to +Z at rotation.y=0 — verified with a frontal camera
# screenshot of the UNROTATED Swat.glb, 2026-07-19; the earlier "-Z" claim was
# wrong and made the figures walk backwards). Our yaw is atan2(dx, dz) with +Z as
# the 0 direction, so a +Z front needs NO offset.
const FACING_OFFSET_DEG := 0.0

# GDScript names -> Quaternius clip names (CharacterArmature rig, 24 anims, no retarget).
# S1 VERIFIED (phase 5): on glTF import Godot keeps the "CharacterArmature|<name>"
# prefixes UNCHANGED (no AnimationLibrary rename, no stripping). The real
# get_animation_list() is exactly: Death, Gun_Shoot, HitRecieve, HitRecieve_2, Idle,
# Idle_Gun, Idle_Gun_Pointing, Idle_Gun_Shoot, Idle_Neutral, Idle_Sword, Interact,
# Kick_Left/Right, Punch_Left/Right, Roll, Run, Run_Back/Left/Right, Run_Shoot,
# Sword_Slash, Walk, Wave (each "CharacterArmature|"-prefixed).
#
# HONESTY about the animation inventory. SPEC §4.1 step 2 demands the set
# idle, walk, run, crouch_idle, aim, shoot, reload, hit, death — the Quaternius
# rig does NOT cover it completely.
#
# AUDIT 2026-07-20 (hard evidence, not a guess): the glTF JSON chunk of all 24
# character GLBs under assets/models/characters/ was read directly and the
# animation lists compared. Result — exactly TWO distinct rigs ship here:
#   RIG A "CharacterArmature", 24 clips, used by 23 of 24 models: Swat, Casual,
#     BusinessMan and ALL 20 modular bodies. Every one of the 23 carries the
#     IDENTICAL clip set (name sets compared, zero deviation) — the list above
#     It contains NO crouch, NO kneel, NO crawl/prone, NO reload and NO
#     throw clip. The 20 modular characters therefore add ZERO new animations;
#     they are new BODIES on the same 24 clips.
#   RIG B, 76 clips, used by exactly ONE model: Barbarian.glb. It DOES own
#     1H_Ranged_Reload, 2H_Ranged_Reload, Throw and Lie_Down/Lie_Idle/Lie_Pose —
#     but it is a DIFFERENT skeleton (no "CharacterArmature" node, lower-case
#     bones "wrist.r"/"hand.r" instead of "Wrist.R") on a fantasy barbarian body.
#     Its clips can NOT be played on rig A. Reusing them would mean retargeting
#     via BoneMap + SkeletonProfileHumanoid — a separate, much larger job.
# Conclusion: the gaps below are REAL and cannot be closed from the assets in
# this repository. They are left open on purpose instead of being faked.
#
#   REAL (own, matching clip present):
#     idle, walk, run, shoot, aim, hit, death, loot
#   NOT MAPPED AT ALL (rig A has no such clip — deliberately NOT faked):
#     reload      — no reload clip exists. Previously this pointed at Idle_Gun
#                   (a static hold pose) and at Sword_Slash for throwing; both
#                   were dropped on request: rather no animation than a wrong
#                   one. play_anim("reload") falls through to Idle, i.e. the
#                   merc simply keeps standing while reloading.
#     throw       — same story (Sword_Slash is a sword swing, not a throw).
#     crouch_idle / prone — rig A has NEITHER crouch NOR crawl clips.
#                   set_stance_visual() fakes the pose with a pure mesh transform
#                   (squash/tilt). That is a placeholder, not an animation.
#   Closing them needs either the Quaternius Universal Animation Library plus
#   retargeting, or hand-made clips. Nothing was downloaded for this audit.
const _CLIPS := {
	"idle": "CharacterArmature|Idle",            # REAL
	"walk": "CharacterArmature|Walk",            # REAL
	"run": "CharacterArmature|Run",              # REAL
	"shoot": "CharacterArmature|Gun_Shoot",      # REAL
	"aim": "CharacterArmature|Idle_Gun_Pointing",# REAL
	"hit": "CharacterArmature|HitRecieve",       # REAL
	"death": "CharacterArmature|Death",          # REAL
	"loot": "CharacterArmature|Interact",        # REAL
}

## Every entry in _CLIPS is a genuine, fitting clip — no approximations left.
const APPROX_CLIPS := []
## Clips of the mandatory set (SPEC §4.1 step 2) for which the rig has NO clip at
## all. Listed so the gap stays visible instead of being papered over; play_anim
## falls through to Idle for these.
const MISSING_CLIPS := ["reload", "throw", "crouch_idle"]

# Continuous anims loop; one-shots (shoot/hit/death/loot) play once.
const _LOOPING := {
	"idle": true, "walk": true, "run": true, "aim": true,
}

var grid: Grid3D
var cell := Vector3i.ZERO
var moving := false
var fast := false            # true = snap instantly (headless), no tween

var _mesh: Node3D                     # GLB root, prefab root OR fallback capsule
var _anim: AnimationPlayer = null     # found recursively; null for the fallback
var _weapon_att: BoneAttachment3D = null   # hand bone anchor; null for the fallback capsule
var _gun: Node3D = null                    # currently mounted weapon model
var _gun_model := ""                       # model id of the mounted weapon ("rifle"/"pistol")
var _gun_weapon := ""                      # Db weapon id of the mounted weapon ("" = unknown)

var _target_yaw := 0.0                 # target facing (mesh yaw), set by face_toward
var _has_target_yaw := false           # only turn after the first face_toward/spawn


## Builds the body and places the unit.
##
##   g         — grid (may be null: the unit then just stands in world space).
##   start     — start cell.
##   char_id   — Assets3D.CHARACTERS id of the body ("merc"/"m_swat"/...).
##   prefab_id — OPTIONAL merc id ("ivan"). When a prefab
##               res://scenes/units/merc_<id>.tscn exists AND we are not in fast
##               mode, the body comes from it (model + uniform colour + weapon
##               baked in as data). Missing prefab -> char_id path, unchanged.
func setup(g: Grid3D, start: Vector3i, char_id := "merc", prefab_id := "") -> void:
	grid = g
	# Scenery3D (roof fade-out) finds all units through this group.
	add_to_group("tac3d_units")
	# Body: prefab if available, otherwise the modern merc by role/model id
	# (fallback capsule when the GLB is missing).
	_mesh = _make_body(char_id, prefab_id)
	add_child(_mesh)
	# Find the AnimationPlayer recursively, null-safe (the fallback capsule has none).
	_anim = _find_anim(_mesh)
	# One-shot anims (shot/hit) should return to idle when they finish.
	if _anim != null and not _anim.animation_finished.is_connected(_on_anim_finished):
		_anim.animation_finished.connect(_on_anim_finished)
	# Uniform colour baked into the prefab (metadata). No-op on the direct path;
	# Tac3DUnit sets the same colour again from the Db, which is idempotent.
	var prefab_col := _meta_color(_mesh, "uniform", Color(0, 0, 0, 0))
	if prefab_col.a > 0.0:
		set_uniform_color(prefab_col)
	# Attach the weapon anchor to the real hand bone (only when a skeleton exists).
	var skel := _find_skeleton(_mesh)
	if skel != null:
		_weapon_att = BoneAttachment3D.new()
		# S2: guard Wrist.R; Godot may rewrite glTF bones (Wrist_R).
		var bone := "Wrist.R"
		if skel.find_bone(bone) < 0:
			push_warning("Unit3D: bone 'Wrist.R' not found — trying 'Wrist_R'.")
			if skel.find_bone("Wrist_R") >= 0:
				bone = "Wrist_R"
		_weapon_att.bone_name = bone
		skel.add_child(_weapon_att)
		# S3: default rifle (merc look); Tac3DUnit re-equips the REAL inventory
		# weapon afterwards. Missing rifle.glb -> fall back to the pistol.
		var gun_id := "rifle"
		if not ResourceLoader.exists("res://assets/models/weapons/rifle.glb"):
			gun_id = "pistol"
		var gun_weapon := ""
		# Weapon attachment baked into the prefab (metadata) wins over the default.
		var meta_model := _meta_string(_mesh, "weapon_model")
		if meta_model != "":
			gun_id = meta_model
		gun_weapon = _meta_string(_mesh, "weapon_id")
		equip_weapon(gun_id, gun_weapon)
	# Character meshes should cast shadows in the sunlight (recursive, fallback-safe).
	_enable_shadows(_mesh)
	set_cell(start)
	# Start rotation: the figure looks toward the map centre (instead of everyone
	# standing identically in +Z). Falls back to negative Z when the grid size is
	# not known yet.
	var center := Vector3(position.x, position.y, position.z - 1.0)
	if grid != null and grid.size_x > 0 and grid.size_z > 0:
		center = grid.cell_to_world(Vector3i(grid.size_x / 2, start.y, grid.size_z / 2))
	face_toward(center, true)   # set immediately (spawn), do not turn softly
	play_anim("idle")


## Builds the visible body. Prefab first (SPEC §4.1 step 2), then the classic
## Assets3D.character() path. Every failure mode degrades silently:
##   - fast mode (bot/headless)   -> never touches a prefab (keeps the bot cheap)
##   - prefab missing/not a scene -> Assets3D.unit_prefab() returns null
##   - prefab root is not a Node3D -> discarded, direct path
##   - prefab names an unknown model -> Assets3D.character() returns the capsule
func _make_body(char_id: String, prefab_id: String) -> Node3D:
	if prefab_id != "" and not fast:
		var ps := Assets3D.unit_prefab(prefab_id)
		if ps != null:
			var inst := ps.instantiate()
			if inst is Node3D:
				var root := inst as Node3D
				# The prefab is pure DATA and brings no mesh of its own: hang the
				# body it names underneath it. Only when the prefab really is
				# empty — a prefab that DOES ship geometry stays untouched.
				var model := _meta_string(root, "model")
				if model != "" and _find_skeleton(root) == null:
					root.add_child(Assets3D.character(model))
				return root
			if inst != null:
				inst.free()
	return Assets3D.character(char_id)


func set_cell(c: Vector3i) -> void:
	cell = c
	if grid != null:
		position = grid.cell_to_world(c) + Vector3(0, MODEL_Y_OFFSET, 0)


## PUBLIC: mounts the weapon MODEL (Assets3D id "rifle"/"pistol") in the right
## hand. Replaces an already mounted weapon (inventory swap!). No-op for the
## fallback capsule (no skeleton) or when exactly this model/weapon is already
## mounted.
##
## weapon_id (optional) = Db weapon id ("p9"/"svd"/...). When it is set AND
## Db.WEAPONS has an "attach_offset" for it, the fit comes from the DATABASE
## (SPEC §4.1 step 3). Without either, the old WEAPON_FITS table applies —
## identical numbers, so identical looks.
func equip_weapon(model_id: String, weapon_id := "") -> void:
	if _weapon_att == null:
		return
	if model_id == _gun_model and weapon_id == _gun_weapon:
		return
	if _gun != null:
		_gun.queue_free()
		_gun = null
	var fit := weapon_fit(model_id, weapon_id)
	var gun := Assets3D.weapon(model_id)
	gun.scale = fit["scale"]
	gun.position = fit["position"]
	gun.rotation_degrees = fit["rotation"]
	_weapon_att.add_child(gun)
	_enable_shadows(gun)
	_gun = gun
	_gun_model = model_id
	_gun_weapon = weapon_id


## PUBLIC + STATIC: resolve the fit. `db_offset` is the (possibly empty)
## Db.WEAPONS[<id>]["attach_offset"] entry — if it carries a "scale" it WINS
## (data beats code, SPEC §4.1 step 3); otherwise WEAPON_FITS applies.
## ALWAYS returns {"position": Vector3, "rotation": Vector3, "scale": Vector3}.
## Deliberately PARAMETRIC instead of doing its own Db lookup: that keeps the
## function pure and lets the HUD (paper doll without a Unit3D instance) use
## exactly the same fit.
static func weapon_fit_from(model_id: String, db_offset: Dictionary) -> Dictionary:
	if db_offset.has("scale"):
		return {
			"position": _as_vec3(db_offset.get("position", Vector3.ZERO)),
			"rotation": _as_vec3(db_offset.get("rotation", Vector3.ZERO)),
			"scale": _as_scale(db_offset["scale"]),
		}
	var fb: Dictionary = WEAPON_FITS.get(model_id, WEAPON_FITS["rifle"])
	return {
		"position": _as_vec3(fb["offset"]),
		"rotation": _as_vec3(fb["euler"]),
		"scale": _as_scale(fb["scale"]),
	}


## Convenience: looks the Db fit up itself (the Db access deliberately lives here,
## in a NON-static method).
func weapon_fit(model_id: String, weapon_id := "") -> Dictionary:
	var off: Dictionary = {}
	if weapon_id != "":
		off = Db.weapon_attach(weapon_id)
	return weapon_fit_from(model_id, off)


static func _as_vec3(v) -> Vector3:
	if typeof(v) != TYPE_VECTOR3:
		return Vector3.ZERO
	var out: Vector3 = v
	return out


## The scale may live in the Db as a float (uniform) OR as a Vector3.
static func _as_scale(v) -> Vector3:
	if typeof(v) == TYPE_VECTOR3:
		var out: Vector3 = v
		return out
	return Vector3.ONE * float(v)


## Reads a Color from node metadata; returns `fb` when the key is missing or
## holds another type (prefabs are data files — never trust their shape).
static func _meta_color(n: Node, key: String, fb: Color) -> Color:
	if n == null or not n.has_meta(key):
		return fb
	var v = n.get_meta(key)
	if typeof(v) != TYPE_COLOR:
		return fb
	var out: Color = v
	return out


## Reads a String from node metadata; "" when missing.
static func _meta_string(n: Node, key: String) -> String:
	if n == null or not n.has_meta(key):
		return ""
	return String(n.get_meta(key))


## PUBLIC (SPEC §4.1 step 4): paints the CLOTHING of the model in the merc's
## uniform colour. Skin/hair/eyes/visor stay untouched — recognised through the
## material/surface NAMES of the GLB (SKIN_MATERIALS deny list).
##
## Materials are DUPLICATED before being set and applied as surface overrides.
## That is mandatory: the mesh resources come from the Assets3D cache and are
## SHARED between all units — writing to them directly would recolour the whole
## team.
##
## No-op for col.a <= 0 (= "no uniform set") or a missing mesh. Calling it twice
## with different colours is safe: the original albedo is remembered per surface.
##
## Skipped entirely in fast mode (bot/headless) — project law: fast mode builds
## no visual work. See can_paint().
func set_uniform_color(col: Color) -> void:
	if fast:
		return
	paint_uniform(_mesh, col)


## Is there a real rendering device to paint into?
##
## The uniform colour is PURELY COSMETIC. Under the headless dummy renderer
## set_surface_override_material() cannot register the duplicated material and
## Godot logs 'ERROR: Parameter "material" is null.' once per surface
## (servers/rendering/dummy/storage/material_storage.cpp). That noise masks real
## errors in the test log, so we do not paint at all without a display. A
## windowed run is unaffected and colours exactly as before.
static func can_paint() -> bool:
	if OS.has_feature("headless"):
		return false
	return DisplayServer.get_name() != "headless"


## PUBLIC + STATIC: the same for ANY model tree (the HUD builds its paper doll
## without a Unit3D instance and needs the same colouring).
static func paint_uniform(root: Node, col: Color) -> void:
	if root == null or col.a <= 0.0:
		return
	if not can_paint():
		return
	if _paint_uniform(root, col, false) == 0:
		# No known clothing material (fallback capsule/foreign GLB): only blend
		# subtly instead of bluntly repainting everything.
		_paint_uniform(root, col, true)


## Recursive painter. subtle=false: clothing only, the colour is SET.
## subtle=true: all surfaces, the colour is only BLENDED IN. Returns the number
## of repainted surfaces.
static func _paint_uniform(n: Node, col: Color, subtle: bool) -> int:
	var hits := 0
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var mesh: Mesh = mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var base: Material = mi.get_surface_override_material(i)
				if base == null:
					base = mesh.surface_get_material(i)
				if base == null or not (base is BaseMaterial3D):
					continue
				var bm := base as BaseMaterial3D
				var key := _surface_key(bm, mesh, i)
				var is_cloth := not _is_skin(key)
				if not subtle and not is_cloth:
					continue
				var dup := bm.duplicate() as BaseMaterial3D
				if dup == null:
					continue
				# duplicate() may drop the resource name — restore it, otherwise
				# the skin/clothing detection breaks on the SECOND call.
				dup.resource_name = bm.resource_name
				# IDEMPOTENT: always recolour from the ORIGINAL albedo, which is
				# remembered on the MeshInstance3D the first time. Without this a
				# second call (prefab bakes the colour, Tac3DUnit sets it again)
				# would tint an already tinted colour and drift.
				var meta_key := UNIFORM_BASE_META + str(i)
				var old := _meta_color(mi, meta_key, bm.albedo_color)
				if not mi.has_meta(meta_key):
					mi.set_meta(meta_key, old)
				var new_col := old
				if subtle:
					new_col = old.lerp(col, UNIFORM_SUBTLE_MIX)
				else:
					# PRESERVE LUMINANCE: the uniform colour is scaled by the
					# brightness of the original material. Otherwise dark boots,
					# belts and bright vests would merge into ONE flat surface and
					# the figure would lose all of its shape.
					var lum := old.r * 0.299 + old.g * 0.587 + old.b * 0.114
					var shade := clampf(0.35 + lum * 0.9, 0.25, 1.35)
					new_col = Color(col.r * shade, col.g * shade, col.b * shade)
				dup.albedo_color = Color(new_col.r, new_col.g, new_col.b, old.a)
				mi.set_surface_override_material(i, dup)
				hits += 1
	for child in n.get_children():
		hits += _paint_uniform(child, col, subtle)
	return hits


## Is this material key a BODY material (skin/hair/eyes/...)?
## Substring compare so that "Hair_Brown", "Eyebrows", "Skin_Darker" etc. match.
## An empty name (fallback capsule, unnamed material) counts as clothing — the
## capsule is supposed to take the team colour.
static func _is_skin(key: String) -> bool:
	for s in SKIN_MATERIALS:
		if key.contains(String(s)):
			return true
	return false


## Material key of a surface (lower case). Godot's glTF import carries the
## material name over both as the resource name and as the surface name — we
## check both so the detection does not hinge on either one.
static func _surface_key(mat: Material, mesh: Mesh, idx: int) -> String:
	var nm := String(mat.resource_name).strip_edges().to_lower()
	if nm == "" and mesh is ArrayMesh:
		nm = String((mesh as ArrayMesh).surface_get_name(idx)).strip_edges().to_lower()
	return nm


## Stance look (a FALLBACK — the CharacterArmature rig has NO crouch/crawl
## clips): crouching = squashed, slightly bent mesh; prone = mesh tipped flat
## forward just above the ground (head in the facing direction).
## A pure transform change on _mesh — anims/yaw (rotation.y) keep running, the
## gameplay cell/node position stays untouched. No-op safe (capsule: fine).
func set_stance_visual(s: String) -> void:
	if _mesh == null:
		return
	match s:
		"crouch":
			# Squash-and-stretch: a pure y-squash keeps the width and just makes a
			# DWARF (the head shrinks along with everything else). Widening x/z as
			# the body loses height preserves the silhouette mass, so the figure
			# reads as "compressed/braced" instead of "small". Half-strength volume
			# compensation (full 1/sqrt(0.72)=1.18 looks bloated from the ortho cam).
			var sy := 0.72
			var sxz := lerpf(1.0, 1.0 / sqrt(sy), 0.5)
			_mesh.scale = Vector3(sxz, sy, sxz)
			_mesh.rotation.x = deg_to_rad(12.0)
			_mesh.position.y = 0.0
		"prone":
			_mesh.scale = Vector3.ONE
			_mesh.rotation.x = deg_to_rad(84.0)
			_mesh.position.y = 0.22
		_:
			_mesh.scale = Vector3.ONE
			_mesh.rotation.x = 0.0
			_mesh.position.y = 0.0


## Plays a clip by GDScript name. No-op for the fallback capsule (no _anim) and
## for names the rig has no clip for (e.g. "crouch_idle" -> falls back to Idle).
func play_anim(which: String) -> void:
	if _anim == null:
		return
	# Names the rig has no clip for (MISSING_CLIPS: reload/throw/crouch_idle) fall
	# back to "idle" as a KEY, not merely as a clip path. That matters because the
	# loop lookup below must describe the clip we ACTUALLY play: resolving
	# "throw" -> Idle while asking _LOOPING for "throw" (absent -> false) used to
	# stamp LOOP_NONE onto Idle. And Animation resources come from the cached
	# Assets3D PackedScene, i.e. they are SHARED by every unit on the same GLB —
	# so one grenade throw made the whole squad's idle play once and freeze.
	var key: String = which if _CLIPS.has(which) else "idle"
	var clip: String = _CLIPS[key]
	if not _anim.has_animation(clip):
		return
	# glTF clips import WITHOUT loop -> continuous anims would play ONCE and
	# freeze ("basically no animation"). Set the loop mode per clip type.
	# _CLIPS maps every key to a DISTINCT clip, so this write is now deterministic
	# per clip; guard it anyway to avoid churning a shared resource each frame.
	var a := _anim.get_animation(clip)
	if a != null:
		var mode := Animation.LOOP_LINEAR if bool(_LOOPING.get(key, false)) else Animation.LOOP_NONE
		if a.loop_mode != mode:
			a.loop_mode = mode
	# Custom blend (0.18s) -> soft transitions idle<->walk<->shot instead of a hard cut.
	_anim.play(clip, 0.18)


## One-shot anims return to idle when they end. Loop anims never fire
## animation_finished (they run forever); the dead stay down.
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
		# Headless: snap straight to the end. In fast mode the orchestrator calls
		# set_cell(goal) separately anyway; here we only terminate cleanly.
		# NO animation, no tween -> the smoke stays fast and green.
		var last: Vector3 = world_points.back()
		position = last
		moving = false
		move_finished.emit()
		return

	moving = true
	play_anim("walk")   # keep walking until the path ends (no flicker between segments)
	var tween := create_tween()
	# Corner cutting ("smooth path"): the intermediate goals are the MIDPOINTS of
	# the segments instead of the cell centres -> 90 degree kinks become soft 45
	# degree cuts, straight stretches stay straight (midpoints are collinear).
	# Only the LAST point is approached exactly. Constant speed (duration ~ distance).
	var prev := position
	for i in world_points.size():
		var pt: Vector3 = world_points[i]
		var goal := pt + Vector3(0, MODEL_Y_OFFSET, 0)
		if i < world_points.size() - 1:
			var nxt: Vector3 = world_points[i + 1]
			goal = (pt + nxt) * 0.5 + Vector3(0, MODEL_Y_OFFSET, 0)
		# Turn softly toward the next point before every segment. face_toward only
		# sets the target yaw; _process rotates the mesh there smoothly.
		tween.tween_callback(face_toward.bind(goal))
		tween.tween_property(self, "position", goal, maxf(0.06, 0.22 * prev.distance_to(goal)))
		prev = goal
	tween.finished.connect(func() -> void:
		moving = false
		play_anim("idle")
		move_finished.emit()
	)


## PUBLIC: rotates the mesh so the figure LOOKS AT the world position.
##
## Signature:  face_toward(world_pos: Vector3, instant := false) -> void
##   world_pos — point to look at in world coordinates (only X/Z count).
##   instant   — true: snap immediately (spawn/fast); false: turn softly via _process.
##
## The orchestrator calls e.g. face_toward(target.global_position) in shoot() so
## the shooter looks at the target. Combat logic/node transform stay untouched
## (only _mesh rotates).
func face_toward(world_pos: Vector3, instant := false) -> void:
	var dx := world_pos.x - global_position.x
	var dz := world_pos.z - global_position.z
	# Target practically straight above/below us -> no meaningful direction, keep the old one.
	if Vector2(dx, dz).length() < 0.001:
		return
	# atan2(dx, dz) = yaw with +Z as the 0 direction; FACING_OFFSET_DEG corrects the model front.
	_target_yaw = atan2(dx, dz) + deg_to_rad(FACING_OFFSET_DEG)
	_has_target_yaw = true
	# In headless/fast mode (or deliberately instant) set it hard: no soft _process needed.
	if instant or fast:
		if _mesh != null:
			_mesh.rotation.y = _target_yaw


## Soft rotation of the mesh toward _target_yaw. A cheap no-op in fast/headless mode.
func _process(delta: float) -> void:
	if fast or _mesh == null or not _has_target_yaw:
		return
	_mesh.rotation.y = lerp_angle(_mesh.rotation.y, _target_yaw, minf(1.0, TURN_SPEED * delta))


# ------------------------------------------------------------------ internal

## Finds the first AnimationPlayer in the tree recursively (null when there is none).
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


## Sets cast_shadow ON recursively for all MeshInstance3D children (fallback capsule included).
func _enable_shadows(n: Node) -> void:
	if n == null:
		return
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for child in n.get_children():
		_enable_shadows(child)


## Finds the first Skeleton3D in the tree recursively (null for the fallback capsule).
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

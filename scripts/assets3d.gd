extends Node
## Assets3D — loads 3D models (GLB/OBJ) as PackedScene with a cache and builds
## ROBUST primitive fallbacks whenever a file is (still) missing. That way the
## game runs completely WITHOUT the CC0 GLBs and the headless smoke stays green.
## Same principle as assets.gd (prefer the file, fall back to a primitive).

var _cache := {}

const CHARACTERS := {
	"barbarian": "res://assets/models/characters/Barbarian.glb",
	# Modern mercs (Quaternius CharacterArmature rig, 24 anims, CC0, self-contained):
	# ROLE ids (kept for compatibility — tests/HUD/foreign code depend on them):
	"merc": "res://assets/models/characters/Swat.glb",
	"enemy": "res://assets/models/characters/Casual.glb",
	"boss": "res://assets/models/characters/BusinessMan.glb",
	# BODY ids (SPEC §4.1 step 4): the same three GLBs, but named after the MODEL.
	# Db.MERCS[...]["model"] picks the body directly, independent of the role.
	# Same rig, same 24 clips -> the anims play identically.
	"swat": "res://assets/models/characters/Swat.glb",
	"casual": "res://assets/models/characters/Casual.glb",
	"businessman": "res://assets/models/characters/BusinessMan.glb",
	# --- Ultimate Modular Men/Women Pack (Quaternius, CC0) -------------------
	# 20 standalone bodies. VERIFIED (2026-07-20): every one of these GLBs has
	# exactly the same 62 bones and the same 24 "CharacterArmature|" clips as the
	# original Swat.glb -> NO retargeting needed, play_anim() applies 1:1.
	# Suffix _m = Men pack, _w = Women pack.
	"m_adventurer": "res://assets/models/characters/modular/Adventurer_m.glb",
	"m_astronaut": "res://assets/models/characters/modular/Astronaut_m.glb",
	"m_beach": "res://assets/models/characters/modular/BeachCharacter_m.glb",
	"m_businessman": "res://assets/models/characters/modular/BusinessMan_m.glb",
	"m_casual": "res://assets/models/characters/modular/CasualCharacter_m.glb",
	"m_farmer": "res://assets/models/characters/modular/Farmer_m.glb",
	"m_hoodie": "res://assets/models/characters/modular/HoodieCharacter_m.glb",
	"m_king": "res://assets/models/characters/modular/King_m.glb",
	"m_punk": "res://assets/models/characters/modular/Punk_m.glb",
	"m_swat": "res://assets/models/characters/modular/Swat_m.glb",
	"m_worker": "res://assets/models/characters/modular/Worker_m.glb",
	"w_adventurer": "res://assets/models/characters/modular/Adventurer_w.glb",
	"w_animated": "res://assets/models/characters/modular/AnimatedWoman_w.glb",
	"w_medieval": "res://assets/models/characters/modular/Medieval_w.glb",
	"w_punk": "res://assets/models/characters/modular/Punk_w.glb",
	"w_scifi": "res://assets/models/characters/modular/SciFiCharacter_w.glb",
	"w_soldier": "res://assets/models/characters/modular/Soldier_w.glb",
	"w_suit": "res://assets/models/characters/modular/Suit_w.glb",
	"w_witch": "res://assets/models/characters/modular/Witch_w.glb",
	"w_worker": "res://assets/models/characters/modular/Worker_w.glb",
}
const PROPS := {
	"crate": "res://assets/models/props/box_small.glb",
	"barrel": "res://assets/models/props/barrel_small.glb",
	"crates_stacked": "res://assets/models/props/crates_stacked.glb",
	"chest": "res://assets/models/props/chest.glb",
}
const WEAPONS := {
	"pistol": "res://assets/models/weapons/pistol.obj",
	"rifle": "res://assets/models/weapons/rifle.glb",
}
const WATER_SHADER := "res://scripts/shaders/water_compat.gdshader"

## SPEC §4.1 step 2: per-merc prefab scenes live here as "merc_<id>.tscn"
## (res://scenes/units/merc_ivan.tscn and so on). They are PURELY OPTIONAL —
## see unit_prefab().
const UNIT_PREFAB_DIR := "res://scenes/units/"

# merc id -> PackedScene, and merc id -> null for a verified MISS. Caching the
# miss too keeps the fallback path from hitting the filesystem on every spawn.
var _prefab_cache := {}


## Instantiated character GLB (with Skeleton3D + AnimationPlayer) OR fallback capsule.
func character(id: String) -> Node3D:
	return _instance(String(CHARACTERS.get(id, "")), _fallback_capsule)


## Instantiated prop GLB (crate/barrel/chest) OR fallback box.
func prop(id: String) -> Node3D:
	return _instance(String(PROPS.get(id, "")), _fallback_box)


## Instantiated weapon mesh OR fallback box (small, dark).
func weapon(id: String) -> Node3D:
	return _instance(String(WEAPONS.get(id, "")), _fallback_weapon)


## SPEC §4.1/§7.2: the prefab of ONE merc — "res://scenes/units/merc_<id>.tscn".
## It packs the body model, the uniform colour and the weapon attachment as DATA
## (the colour and the weapon ids ride along as node metadata, Unit3D reads them
## on setup).
##
## Returns null when the prefab does not exist or is not a PackedScene. That is
## the NORMAL, supported case, not an error: Unit3D then falls back to the direct
## character() path, so the headless tests never depend on these files existing.
##
## NOTE (deviation from SPEC §7.2): the spec names this function on `Assets`.
## `Assets` is the 2D loader in this project, so the 3D prefabs belong on
## Assets3D — same name, correct home.
func unit_prefab(id: String) -> PackedScene:
	if id == "":
		return null
	if _prefab_cache.has(id):
		var cached = _prefab_cache[id]
		if cached is PackedScene:
			return cached
		return null
	var path := UNIT_PREFAB_DIR + "merc_" + id + ".tscn"
	var found: PackedScene = null
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is PackedScene:
			found = res
	_prefab_cache[id] = found
	return found


## Compatibility-safe water material. Falls back to a plain blue
## StandardMaterial3D when the shader is missing.
func water_material() -> Material:
	if ResourceLoader.exists(WATER_SHADER):
		var sh = _cache.get(WATER_SHADER, null)
		if sh == null:
			sh = load(WATER_SHADER)
			_cache[WATER_SHADER] = sh
		if sh != null:
			var m := ShaderMaterial.new()
			m.shader = sh
			return m
	return _fallback_water()


# ------------------------------------------------------------------ internal

## Loads a model resource (cached) and instantiates it; otherwise a fallback
## primitive. Robust against both Godot import types: GLB -> PackedScene,
## OBJ -> Mesh (ArrayMesh).
func _instance(path: String, fb: Callable) -> Node3D:
	if path != "" and ResourceLoader.exists(path):
		var res: Resource = _cache.get(path, null)
		if res == null:
			res = load(path)
			_cache[path] = res
		if res is PackedScene:
			var inst := (res as PackedScene).instantiate()
			if inst is Node3D:
				return inst
			# Unexpected root type -> wrap it in a Node3D (defensive).
			var holder := Node3D.new()
			holder.add_child(inst)
			return holder
		if res is Mesh:
			# OBJ imports as a Mesh (ArrayMesh), not as a PackedScene: wrap it in
			# a MeshInstance3D underneath a Node3D root.
			var mroot := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = res
			mroot.add_child(mi)
			return mroot
	return fb.call()


## Fallback merc: yellow capsule (unshaded), identical to the old placeholder.
func _fallback_capsule() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.0
	mi.mesh = capsule
	capsule.material = _flat_mat(Color(0.95, 0.82, 0.15))
	mi.position = Vector3(0, 0.5, 0)
	root.add_child(mi)
	return root


## Fallback prop: brown box (unshaded), cover placeholder.
func _fallback_box() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.8, 0.8, 0.8)
	mi.mesh = box
	box.material = _flat_mat(Color(0.6, 0.44, 0.24))
	mi.position = Vector3(0, 0.4, 0)
	root.add_child(mi)
	return root


## Fallback weapon: small dark box (unshaded).
func _fallback_weapon() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.1, 0.1)
	mi.mesh = box
	box.material = _flat_mat(Color(0.18, 0.18, 0.2))
	root.add_child(mi)
	return root


## Fallback water: simple blue transparent material (no shader needed).
func _fallback_water() -> Material:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.18, 0.42, 0.62, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _flat_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


## Like _flat_mat, but LIT — for the ground fallback, so that even the plain
## colour material takes light/shadow (T7 art pass).
func _lit_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


# ================================================================== PHASE 6
# Map look: stylised low-poly, coherent with the Quaternius soldiers.
# EVERYTHING here is ADDITIVE (T7) — nothing above is touched.
# Ground texture = the Kenney PNGs ALREADY in the repo (assets/img/...),
# 0 downloads. Unshaded/flat -> needs no shadow (T6), never black.
# Missing PNG/mesh -> fallback (flat colour / primitive) -> smoke stays green.

# Surface name -> Kenney PNG in the repo. (No sand.png in the repo -> colour fallback.)
const TERRAIN_TEX := {
	"grass": "res://assets/textures/terrain/grass_lush.jpg",   # ambientCG Grass005 CC0, rich green lawn (instead of the olive Grass004)
	"dirt": "res://assets/img/dirt_1.png",
	"wood": "res://assets/img/floor_wood_1.png",
	"rock": "res://assets/img/rock_1.png",
	"wall_brick": "res://assets/img/wall_brick.png",
}

# Tac3DTile.Kind (int) -> surface name. Presentation only, no logic.
const TERRAIN_KIND := {
	Tac3DTile.Kind.GROUND: "grass",
	Tac3DTile.Kind.FLOOR: "wood",
	Tac3DTile.Kind.ROOF: "wood",
	Tac3DTile.Kind.BRIDGE: "wood",
	Tac3DTile.Kind.RAMP: "dirt",
	Tac3DTile.Kind.WALL: "wall_brick",
}

# Flat colour per surface — fallback ONLY when the PNG is missing (T5).
const TERRAIN_COLOR := {
	"grass": Color(0.30, 0.56, 0.20),   # juicy green (fallback without PNG)
	"dirt": Color(0.46, 0.34, 0.20),
	"sand": Color(0.50, 0.45, 0.35),   # art pass v2: heavily toned down — 0.85/0.63 burned the R channel to 255 under the warm sun (flat white beach); now a real sand tone
	"wood": Color(0.55, 0.40, 0.23),
	"rock": Color(0.48, 0.48, 0.50),
	"wall_brick": Color(0.55, 0.32, 0.26),
}

const NATURE := { "palm": "res://assets/models/nature/palm.obj" }
const NATURE_TEX := { "palm": "res://assets/models/nature/palm_tex.png" }
# Target total height (in tile units) per decoration type for the T2 normalisation.
const NATURE_TARGET_H := { "palm": 3.4 }

var _terrain_mat_cache := {}   # surface name (String) -> Material


## Terrain material for a Tac3DTile.Kind (int). Kenney PNG per kind, otherwise a
## flat colour (T5). Cached. 1 tile ~ 1 texture repeat.
func terrain_material(kind: int) -> Material:
	return terrain_material_named(String(TERRAIN_KIND.get(kind, "grass")))


## Terrain material by surface name ("grass"/"dirt"/"sand"/"wood"/"rock"/
## "wall_brick"). Lets Scenery3D request e.g. beach sand directly.
func terrain_material_named(name: String) -> Material:
	if _terrain_mat_cache.has(name):
		return _terrain_mat_cache[name]
	var m := _make_terrain_material(name)
	_terrain_mat_cache[name] = m
	return m


func _make_terrain_material(name: String) -> Material:
	var path := String(TERRAIN_TEX.get(name, ""))
	if path != "" and ResourceLoader.exists(path):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(path)
		# Art pass: tone down bright textures (no burn-out under sun 1.33).
		# Grass gets LESS damping + a slight green cast -> lush lawn; every other
		# surface keeps the proven 0.72 grey.
		if name == "grass":
			# Damp R hard, leave B alone: pulls the yellowish lawn from lime to a
			# rich grass green under the warm sun.
			m.albedo_color = Color(0.45, 0.82, 0.62)
		else:
			m.albedo_color = Color(0.72, 0.72, 0.72)
		m.uv1_triplanar = true          # world-space triplanar: NO UV reset per tile -> no grid look
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3(0.16, 0.16, 0.16)          # 1x1 tile box -> 1 texture per tile
		m.roughness = 0.95                 # matte/diffuse -> the sun shades it softly
		m.metallic = 0.0
		m.texture_repeat = true
		# T7 art pass: LIT, so the DirectionalLight shades the ground and it
		# RECEIVES shadows. Needs light+ambient (light agent) -> bright in game.
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		return m
	# T5 fallback: flat colour (today's box look) only when the PNG is missing.
	# The ground stays lit as a colour material too -> takes light/shadow.
	var col: Color = TERRAIN_COLOR.get(name, Color(0.4, 0.4, 0.4))
	return _lit_mat(col)


## Building material: "wall" -> brick PNG, "floor"/"wood" -> wooden floor PNG.
## Fallback identical to terrain_material (flat colour when the PNG is missing).
func building_material(id: String) -> Material:
	match id:
		"wall", "wall_brick", "brick":
			return terrain_material_named("wall_brick")
		"floor", "wood", "planks":
			return terrain_material_named("wood")
		_:
			return terrain_material_named("wall_brick")


## Decoration instance (palm) as Node3D: MeshInstance3D with a palm_tex.png
## material, T2-normalised (AABB -> target height, base at local y=0), shadows
## OFF (T6). Scenery3D can hang it straight in. Missing mesh -> primitive palm.
func nature_mesh(id: String) -> Node3D:
	var mesh := nature_mesh_raw(id)
	if mesh != null:
		var root := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := nature_material(id)
		if mat != null:
			mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var aabb := mesh.get_aabb()
		var s := _target_scale(id, aabb)
		mi.scale = Vector3(s, s, s)
		mi.position.y = -aabb.position.y * s   # base on the ground (local y=0)
		root.add_child(mi)
		return root
	return _fallback_palm()


## Raw decoration mesh (ArrayMesh) for MultiMesh scatter. Null when missing.
func nature_mesh_raw(id: String) -> Mesh:
	var path := String(NATURE.get(id, ""))
	if path != "" and ResourceLoader.exists(path):
		var res = _cache.get(path, null)
		if res == null:
			res = load(path)
			_cache[path] = res
		if res is Mesh:
			return res
	return null


## Material for a decoration (palm): StandardMaterial3D with palm_tex.png,
## otherwise plain green. Cached by texture path.
func nature_material(id: String) -> Material:
	var path := String(NATURE_TEX.get(id, ""))
	if path != "" and ResourceLoader.exists(path):
		var cached = _cache.get("mat:" + path, null)
		if cached != null:
			return cached
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(path)
		m.roughness = 1.0
		m.metallic = 0.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL   # art pass: lit instead of cardboard
		_cache["mat:" + path] = m
		return m
	return _flat_mat(Color(0.24, 0.5, 0.22))


## Recommended uniform scale factor for the RAW mesh (T2), so that a MultiMesh
## scatter reaches the same target height as nature_mesh().
func nature_normalized_scale(id: String) -> float:
	var mesh := nature_mesh_raw(id)
	if mesh == null:
		return 1.0
	return _target_scale(id, mesh.get_aabb())


func _target_scale(id: String, aabb: AABB) -> float:
	var h: float = aabb.size.y
	if h <= 0.0001:
		return 1.0
	var target: float = NATURE_TARGET_H.get(id, 2.0)
	return target / h


## Fallback palm: brown trunk (cylinder) + green crown (cone), ~3.4 tall,
## unshaded, no shadow — stylised and never black.
func _fallback_palm() -> Node3D:
	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.08
	cyl.bottom_radius = 0.14
	cyl.height = 2.4
	trunk.mesh = cyl
	cyl.material = _flat_mat(Color(0.42, 0.30, 0.18))
	trunk.position = Vector3(0, 1.2, 0)
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(trunk)
	var crown := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.9
	cone.height = 1.4
	crown.mesh = cone
	cone.material = _flat_mat(Color(0.20, 0.5, 0.22))
	crown.position = Vector3(0, 3.0, 0)
	crown.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(crown)
	return root

extends Node
## Assets3D — lädt 3D-Modelle (GLB/OBJ) als PackedScene mit Cache und
## erzeugt ROBUSTE Primitiv-Fallbacks, falls die Datei (noch) fehlt.
## So läuft das Spiel auch ganz OHNE die CC0-GLBs — der Headless-Smoke
## bleibt grün. Analog zu assets.gd (Datei-bevorzugt + Fallback).

var _cache := {}

const CHARACTERS := {
	"barbarian": "res://assets/models/characters/Barbarian.glb",
	# Moderne Söldner (Quaternius CharacterArmature-Rig, 24 Anims, CC0, self-contained):
	"merc": "res://assets/models/characters/Swat.glb",
	"enemy": "res://assets/models/characters/Casual.glb",
	"boss": "res://assets/models/characters/BusinessMan.glb",
	"knight": "res://assets/models/characters/Knight.glb",
	"mage": "res://assets/models/characters/Mage.glb",
	"rogue": "res://assets/models/characters/Rogue.glb",
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


## Instanziierte Charakter-GLB (mit Skeleton3D + AnimationPlayer) ODER Fallback-Kapsel.
func character(id: String) -> Node3D:
	return _instance(String(CHARACTERS.get(id, "")), _fallback_capsule)


## Instanziiertes Prop-GLB (Kiste/Fass/Truhe) ODER Fallback-Box.
func prop(id: String) -> Node3D:
	return _instance(String(PROPS.get(id, "")), _fallback_box)


## Instanziiertes Waffen-Mesh ODER Fallback-Box (kleiner, dunkel).
func weapon(id: String) -> Node3D:
	return _instance(String(WEAPONS.get(id, "")), _fallback_weapon)


## Compatibility-sicheres Wasser-Material. Fällt auf ein einfaches
## blaues StandardMaterial3D zurück, wenn der Shader fehlt.
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


# ------------------------------------------------------------------ intern

## Lädt eine Modell-Ressource (gecacht) und instanziiert sie; sonst Fallback-Primitiv.
## Robust gegen beide Godot-Importtypen: GLB → PackedScene, OBJ → Mesh (ArrayMesh).
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
			# Unerwarteter Wurzeltyp → in Node3D einwickeln (defensiv).
			var holder := Node3D.new()
			holder.add_child(inst)
			return holder
		if res is Mesh:
			# OBJ importiert als Mesh (ArrayMesh), nicht als PackedScene:
			# in eine MeshInstance3D unter einem Node3D-Wurzelknoten einwickeln.
			var mroot := Node3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = res
			mroot.add_child(mi)
			return mroot
	return fb.call()


## Fallback-Söldner: gelbe Kapsel (unshaded), identisch zum alten Platzhalter.
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


## Fallback-Prop: braune Box (unshaded), Deckungs-Platzhalter.
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


## Fallback-Waffe: kleine dunkle Box (unshaded).
func _fallback_weapon() -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.1, 0.1)
	mi.mesh = box
	box.material = _flat_mat(Color(0.18, 0.18, 0.2))
	root.add_child(mi)
	return root


## Fallback-Wasser: einfaches blau-transparentes Material (kein Shader nötig).
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


## Wie _flat_mat, aber GESCHATTET (lit) — fuer den Boden-Fallback, damit auch
## das reine Farbmaterial Licht/Schatten annimmt (T7 Art-Pass).
func _lit_mat(col: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	return mat


# ================================================================== PHASE 6
# Karten-Optik: stylisiert-lowpoly, kohaerent zu den Quaternius-Soldaten.
# ALLES hier ist ADDITIV (T7) — nichts oben Bestehendes wird angefasst.
# Boden-Textur = die Kenney-PNGs, die SCHON im Repo liegen (assets/img/…),
# 0 Download. Unshaded/flach → kein Schatten noetig (T6), nie schwarz.
# Fehlt eine PNG/ein Mesh → Fallback (flache Farbe / Primitiv) → Smoke gruen.

# Surface-Name -> Kenney-PNG im Repo. (Kein sand.png im Repo → Farb-Fallback.)
const TERRAIN_TEX := {
	"grass": "res://assets/img/grass_1.png",
	"dirt": "res://assets/img/dirt_1.png",
	"wood": "res://assets/img/floor_wood_1.png",
	"rock": "res://assets/img/rock_1.png",
	"wall_brick": "res://assets/img/wall_brick.png",
}

# Tac3DTile.Kind (int) -> Surface-Name. Nur Darstellung, keine Logik.
const TERRAIN_KIND := {
	Tac3DTile.Kind.GROUND: "grass",
	Tac3DTile.Kind.FLOOR: "wood",
	Tac3DTile.Kind.ROOF: "wood",
	Tac3DTile.Kind.BRIDGE: "wood",
	Tac3DTile.Kind.RAMP: "dirt",
	Tac3DTile.Kind.WALL: "wall_brick",
}

# Flach-Farbe je Surface — Fallback NUR wenn PNG fehlt (T5).
const TERRAIN_COLOR := {
	"grass": Color(0.33, 0.52, 0.24),
	"dirt": Color(0.46, 0.34, 0.20),
	"sand": Color(0.85, 0.77, 0.55),
	"wood": Color(0.55, 0.40, 0.23),
	"rock": Color(0.48, 0.48, 0.50),
	"wall_brick": Color(0.55, 0.32, 0.26),
}

const NATURE := { "palm": "res://assets/models/nature/palm.obj" }
const NATURE_TEX := { "palm": "res://assets/models/nature/palm_tex.png" }
# Ziel-Gesamthoehe (in Tile-Einheiten) je Deko-Typ fuer T2-Normalisierung.
const NATURE_TARGET_H := { "palm": 3.4 }

var _terrain_mat_cache := {}   # Surface-Name(String) -> Material


## Terrain-Material fuer eine Tac3DTile.Kind (int). Kenney-PNG je Kind,
## sonst flache Farbe (T5). Gecacht. 1 Kachel ~ 1 Texturdurchlauf.
func terrain_material(kind: int) -> Material:
	return terrain_material_named(String(TERRAIN_KIND.get(kind, "grass")))


## Terrain-Material ueber Surface-Name ("grass"/"dirt"/"sand"/"wood"/
## "rock"/"wall_brick"). Erlaubt Scenery3D z.B. Strand-Sand direkt.
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
		m.albedo_color = Color(0.72, 0.72, 0.72)   # Art-Pass: helle Textur daempfen (kein Ausbrennen/Mint)
		m.uv1_scale = Vector3.ONE          # 1x1-Kachel-Box → 1 Textur je Kachel
		m.roughness = 0.95                 # matt/diffus → Sonne shadet weich
		m.metallic = 0.0
		m.texture_repeat = true
		# T7 Art-Pass: GESCHATTET, damit die DirectionalLight den Boden shadet und
		# er Schatten EMPFAENGT. Braucht Licht+Ambient (Licht-Agent) → im Spiel hell.
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
		return m
	# T5-Fallback: flache Farbe (heutige Box-Optik) nur wenn PNG fehlt.
	# Boden bleibt AUCH als Farbmaterial lit → nimmt Licht/Schatten an.
	var col: Color = TERRAIN_COLOR.get(name, Color(0.4, 0.4, 0.4))
	return _lit_mat(col)


## Gebaeude-Material: "wall" → Backstein-PNG, "floor"/"wood" → Holzboden-PNG.
## Fallback identisch zu terrain_material (flache Farbe wenn PNG fehlt).
func building_material(id: String) -> Material:
	match id:
		"wall", "wall_brick", "brick":
			return terrain_material_named("wall_brick")
		"floor", "wood", "planks":
			return terrain_material_named("wood")
		_:
			return terrain_material_named("wall_brick")


## Deko-Instanz (Palme) als Node3D: MeshInstance3D mit palm_tex.png-Material,
## T2-normalisiert (AABB → Ziel-Hoehe, Basis auf lokal y=0), Schatten AUS (T6).
## Scenery3D kann sie direkt einhaengen. Fehlt Mesh → Primitiv-Palme (Fallback).
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
		mi.position.y = -aabb.position.y * s   # Basis auf Boden (lokal y=0)
		root.add_child(mi)
		return root
	return _fallback_palm()


## Roh-Mesh der Deko (ArrayMesh) fuer MultiMesh-Scatter. Null wenn fehlt.
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


## Material fuer eine Deko (Palme): unshaded StandardMaterial3D mit palm_tex.png,
## sonst schlichtes Gruen. Gecacht ueber den Textur-Pfad.
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
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL   # Art-Pass: geschattet statt Karton
		_cache["mat:" + path] = m
		return m
	return _flat_mat(Color(0.24, 0.5, 0.22))


## Empfohlener uniformer Skalierungsfaktor fuer das ROH-Mesh (T2), damit
## MultiMesh-Scatter dieselbe Ziel-Hoehe erreicht wie nature_mesh().
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


## Fallback-Palme: brauner Stamm (Zylinder) + gruene Krone (Kegel), ~3.4 hoch,
## unshaded, kein Schatten — stylisiert und nie schwarz.
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

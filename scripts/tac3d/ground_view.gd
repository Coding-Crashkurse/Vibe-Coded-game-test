class_name GroundView3D
extends MultiMeshInstance3D
## PHASE 6 — Karten-Optik: statt EINER vertexgefaerbten MultiMesh nun
## EINE MultiMesh JE KACHEL-KIND, jede mit Assets3D.terrain_material(kind)
## (Kenney-PNG-Textur aus dem Repo; Fallback = altes flaches Farbmaterial).
## Wasser bleibt ein separates Shader-Overlay (_build_water UNVERAENDERT).
## Am Ende wird EIN Scenery3D-Kind erzeugt (Waende/Deko/Props) — die Optik
## propagiert dadurch automatisch in Demo UND Kampf (Orchestrator ruft build()).
##
## Begehbarkeit/LOS/Kampf werden NICHT beruehrt (reine Darstellung).
## FROZEN FIXES: T1 (idempotent aufraeumen via duplicate()+queue_free(), NIE
## free() waehrend get_children()-Iteration), T3 (WALL wird NUR von Scenery3D
## gezeichnet — die Boden-MM laesst WALL AUS), T5 (Textur→Farb-Fallback ueber
## Assets3D), T6 (Schatten AUS). Fehlt Textur/Autoload → flache Farbe → Smoke gruen.

# Farben je Kind — FALLBACK, wenn Assets3D/PNG fehlt (identisch zur alten Optik).
const COLOR_GROUND := Color(0.30, 0.55, 0.22)        # gruen
const COLOR_WATER_SHALLOW := Color(0.45, 0.72, 0.90) # hellblau
const COLOR_WATER_DEEP := Color(0.10, 0.25, 0.55)    # dunkelblau
const COLOR_BRIDGE := Color(0.50, 0.33, 0.16)        # braun
const COLOR_ROOF := Color(0.55, 0.55, 0.58)          # grau
const COLOR_RAMP := Color(0.80, 0.72, 0.48)          # sandfarben
const COLOR_WALL := Color(0.22, 0.22, 0.24)          # dunkelgrau
const COLOR_FLOOR := Color(0.62, 0.48, 0.30)         # holz (fallback)
const COLOR_DEFAULT := Color(0.80, 0.80, 0.80)

# Wasser-Overlay (separate MultiMesh): duenne PlaneMesh knapp ueber der Box-Oberkante.
const WATER_NODE_NAME := "WaterOverlay"
const WATER_Y := 0.15   # Box-Oberkante liegt bei +0.1; klar ueber der Wellen-Amplitude (amp 0.05)

var _fallback_mat_cache := {}   # int(kind) -> StandardMaterial3D
var _tinted_mat_cache := {}     # int(kind) -> Material (Duplikat mit vertex_color_use_as_albedo)


func build(g: Grid3D) -> void:
	if g == null:
		return

	# T1: idempotent aufraeumen. NICHT free() waehrend get_children()-Iteration —
	# ueber eine Kopie iterieren und queue_free() nutzen.
	for c in get_children().duplicate():
		if c.name.begins_with("MM_") or c.name == "Scenery":
			c.queue_free()

	# self ist selbst eine MultiMeshInstance3D — die alte (vertexgefaerbte)
	# MultiMesh entfernen, damit nur noch die per-Kind-Kinder rendern.
	multimesh = null

	# Gemeinsames Boden-Mesh (1.0 x 0.2 x 1.0) fuer alle Kind-MultiMeshes.
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.2, 1.0)

	# Zellen nach Kind gruppieren. Wasser separat (s. _build_water); WALL AUS (T3,
	# nur Scenery3D zeichnet Waende mit echter Hoehe). Sonst Parität zur alten
	# Optik: nur begehbare Zellen als Boden-Box.
	var by_kind := {}                          # int(kind) -> Array[Vector3i]
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.is_water():
			continue
		if t.kind == Tac3DTile.Kind.WALL:      # T3
			continue
		if not g.is_walkable(c):
			continue
		var ki := int(t.kind)
		if not by_kind.has(ki):
			by_kind[ki] = []
		by_kind[ki].append(c)

	for kind in by_kind:
		_make_kind_mm(g, box, kind, by_kind[kind])

	# custom_aabb grosszuegig (auch wenn self leer ist — harmlos, schadet nie).
	var b := g.bounds_world()
	var pad := Vector3(4.0, 8.0, 4.0)
	custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)

	# Wasser-Overlay (Shader) — UNVERAENDERT.
	_build_water(g)

	# Scenery (Waende mit Hoehe, Daecher, Fels-Mesa, Palmen/Deko, Cover-Props,
	# Steg) als Kind. Greift in BEIDEN Szenen (Demo + Kampf), ohne Orchestrator-Diff.
	# load()+new() statt Scenery3D-Bezeichner: robust auch wenn der globale
	# class_name-Cache (neue Datei) noch nicht regeneriert ist.
	var sc: Node = load("res://scripts/tac3d/scenery3d.gd").new()
	sc.name = "Scenery"
	add_child(sc)
	sc.build(g)


## Eine MultiMeshInstance3D "MM_<kind>" fuer alle Zellen eines Kinds.
## REIHENFOLGE-FALLE: transform_format + use_colors ZUERST, instance_count ZULETZT.
## Material via material_override (das Box-Mesh ist geteilt) — je Kind eigene
## Kenney-PNG-Textur bzw. flacher Farb-Fallback. Schatten AUS (T6).
##
## ART-PASS: pro Kachel eine deterministisch variierte INSTANZ-Farbe
## (use_colors=true; set_instance_color) → moduliert die albedo_texture, damit
## die gleichfoermige Textur aufbricht (fleckige Wiese statt flaches Gruen).
## Wasser (separates Overlay) und BRIDGE bleiben UNVERAENDERT (weisse/keine Farbe).
func _make_kind_mm(g: Grid3D, box: Mesh, kind: int, cells: Array) -> void:
	if cells.is_empty():
		return

	# BRIDGE ist ausgenommen (bleibt exakt wie bisher). Alle anderen Boden-Kinder
	# bekommen Instanz-Farb-Jitter.
	var tint := kind != int(Tac3DTile.Kind.BRIDGE)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	if tint:
		mm.use_colors = true                   # VOR instance_count setzen
	mm.mesh = box
	mm.instance_count = cells.size()           # ZULETZT
	for i in cells.size():
		var c: Vector3i = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, g.cell_to_world(c)))
		if tint:
			mm.set_instance_color(i, _tile_tint(c, kind))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + str(kind)
	mmi.multimesh = mm
	mmi.material_override = _terrain_material_tinted(kind, tint)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # T6
	# custom_aabb Pflicht (MultiMesh wird nicht auto-gecullt).
	var b := g.bounds_world()
	var pad := Vector3(4.0, 8.0, 4.0)
	mmi.custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)
	add_child(mmi)


## Terrain-Material fuer ein Kind: bevorzugt Assets3D (Kenney-PNG → Farbe, T5),
## sonst lokaler flacher Farb-Fallback = alte Box-Optik. Nie null.
func _terrain_material(kind: int) -> Material:
	var a3d := get_node_or_null("/root/Assets3D")
	if a3d != null and a3d.has_method("terrain_material"):
		var m: Material = a3d.terrain_material(kind)
		if m != null:
			return m
	return _fallback_kind_material(kind)


## Wie _terrain_material, aber wenn per-Kachel-Instanzfarben genutzt werden
## (tint=true), wird eine DUPLIKAT-Kopie zurueckgegeben mit
## vertex_color_use_as_albedo=true — nur so moduliert die Instanz-Farbe die
## albedo_texture. Das Original (Assets3D-Cache, auch von Scenery3D genutzt)
## bleibt UNVERAENDERT. Ohne tint identisch zu _terrain_material.
func _terrain_material_tinted(kind: int, tint: bool) -> Material:
	var base := _terrain_material(kind)
	if not tint or base == null:
		return base
	if _tinted_mat_cache.has(kind):
		return _tinted_mat_cache[kind]
	var m: Material = base
	if base is BaseMaterial3D:
		var dup: BaseMaterial3D = base.duplicate()
		dup.vertex_color_use_as_albedo = true
		m = dup
	_tinted_mat_cache[kind] = m
	return m


## Deterministischer Instanz-Farb-Jitter je Zelle (moduliert die Textur um
## Weiss herum). GROUND bekommt zusaetzlich leichten Farbton-Jitter Richtung
## Gelb/Dunkel und einen kleinen Anteil deutlicher Erd-/Dunkelgruen-Flecken.
func _tile_tint(c: Vector3i, kind: int) -> Color:
	# Helligkeit ±8 % (alle getinteten Kinder).
	var bright := 1.0 + (_cell_rng(c, 1) - 0.5) * 0.16
	var col := Color(bright, bright, bright, 1.0)

	if kind == int(Tac3DTile.Kind.GROUND):
		# Farbton-Jitter: Gruen → etwas gelber/dunkler (mehr R, weniger B).
		var h := (_cell_rng(c, 2) - 0.5) * 0.10
		col.r = clampf(col.r + h, 0.0, 2.0)
		col.g = clampf(col.g + h * 0.4, 0.0, 2.0)
		col.b = clampf(col.b - h * 0.6, 0.0, 2.0)
		# Kleiner Anteil (~12 %) deutlicher Erd-/Dunkelgruen-Fleck (Patches).
		if _cell_rng(c, 3) < 0.12:
			var d := 0.60 + _cell_rng(c, 4) * 0.18   # 0.60..0.78 abdunkeln
			col.r *= d * 1.10                         # erdig: R haelt sich
			col.g *= d * 0.92
			col.b *= d * 0.72

	return col


## Deterministischer 0..1-Wert aus Zellkoordinate + Salt (Integer-Hash-Mix,
## kein Random-Seed/Date → in Headless UND Spiel identisch, Smoke-stabil).
func _cell_rng(c: Vector3i, salt: int) -> float:
	var n := int(c.x) * 73856093 ^ int(c.z) * 19349663 ^ int(c.y) * 83492791 ^ (salt * 2654435761)
	n = (n ^ (n >> 13)) * 1274126177
	n = n & 0x7fffffff
	return float(n % 1000003) / 1000003.0


## Lokaler Fallback (unshaded flache Farbe), falls Assets3D-Autoload fehlt.
func _fallback_kind_material(kind: int) -> Material:
	if _fallback_mat_cache.has(kind):
		return _fallback_mat_cache[kind]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _fallback_color(kind)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # nie schwarz ohne Licht
	mat.roughness = 1.0
	_fallback_mat_cache[kind] = mat
	return mat


func _fallback_color(kind: int) -> Color:
	match kind:
		Tac3DTile.Kind.GROUND:
			return COLOR_GROUND
		Tac3DTile.Kind.WATER_SHALLOW:
			return COLOR_WATER_SHALLOW
		Tac3DTile.Kind.WATER_DEEP:
			return COLOR_WATER_DEEP
		Tac3DTile.Kind.BRIDGE:
			return COLOR_BRIDGE
		Tac3DTile.Kind.ROOF:
			return COLOR_ROOF
		Tac3DTile.Kind.RAMP:
			return COLOR_RAMP
		Tac3DTile.Kind.WALL:
			return COLOR_WALL
		Tac3DTile.Kind.FLOOR:
			return COLOR_FLOOR
	return COLOR_DEFAULT


## Legt die Wasser-Kacheln in eine SEPARATE MultiMesh (1 zusaetzlicher Draw-Call).
## Robuster Fallback: fehlt der Assets3D-Autoload, wird KEIN Overlay erzeugt.
## UNVERAENDERT gegenueber Phase 5.
func _build_water(g: Grid3D) -> void:
	# Vorheriges Overlay entfernen (build() kann mehrfach laufen).
	var old := get_node_or_null(WATER_NODE_NAME)
	if old != null:
		old.free()

	# Autoload-Guard: ohne Assets3D kein Shader-Material -> Wasser bleibt Box.
	var a3d := get_node_or_null("/root/Assets3D")
	if a3d == null:
		return

	# Wasserzellen sammeln (flach + tief).
	var water_cells: Array = []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t != null and (t.kind == Tac3DTile.Kind.WATER_SHALLOW or t.kind == Tac3DTile.Kind.WATER_DEEP):
			water_cells.append(c)
	if water_cells.is_empty():
		return

	# Duenne PlaneMesh (1x1), leicht unterteilt fuer weiche Vertex-Wellen.
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	var mat: Material = a3d.water_material()   # Shader ODER StandardMaterial3D-Fallback
	if mat != null:
		plane.material = mat

	# 2. MultiMesh — gleiche Reihenfolge-Falle wie beim Boden beachten.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = plane
	mm.instance_count = water_cells.size()
	for i in range(water_cells.size()):
		var c: Vector3i = water_cells[i]
		var pos := g.cell_to_world(c) + Vector3(0.0, WATER_Y, 0.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = WATER_NODE_NAME
	mmi.multimesh = mm
	# custom_aabb grosszuegig — auch dieser MultiMesh wird nicht auto-gecullt.
	var b := g.bounds_world()
	var pad := Vector3(4.0, 8.0, 4.0)
	mmi.custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)
	add_child(mmi)

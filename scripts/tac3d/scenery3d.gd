class_name Scenery3D
extends Node3D
## PHASE 6 — stylisiert-tropische Insel-Deko ("Isla Corvo").
## REINE DARSTELLUNG: erzeugt Waende (echte Hoehe), Daecher, Fels-Mesa,
## Natur-Scatter (Palmen + Lowpoly), Cover-Props, Strand-Sand und einen Steg.
## Begehbarkeit/LOS/Kampf werden NICHT beruehrt — es entstehen KEINE Collider.
## Alles per MultiMesh/instanziert (Perf 72x72). Fehlt ein Asset -> weglassen
## bzw. Primitiv-Fallback -> Smoke bleibt gruen.
##
## FROZEN FIXES: T1 (build() raeumt idempotent via duplicate()+queue_free()),
## T2 (Palme AABB-normalisiert ueber Assets3D), T3 (WALL NUR hier gezeichnet),
## T6 (kein Schatten). Deterministisch (fester SEED) -> stabile Screenshots.

const SEED := 0xC0FFEE
const BEACH_Z := 64          # Sued-Strandband (rein visuell)
const WALL_H := 1.8          # echte Wandhoehe (m)
const WALL_THICK := 0.24     # Wandsegment-Dicke
const TILE := 1.0            # = Grid3D.TILE_SIZE
const LEVEL_STEP := 3.0      # = Grid3D.LEVEL_STEP
const TOP_Y := 0.1           # Oberkante der Boden-Box (BoxMesh 0.2 hoch)
const WATER_Y := 0.15        # Wasseroberflaeche (fuer Steg)

var _mat_cache := {}


func build(g: Grid3D) -> void:
	# T1: idempotent aufraeumen OHNE free() waehrend get_children()-Iteration.
	for c in get_children().duplicate():
		c.queue_free()
	if g == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	_build_walls(g)         # (a) WALL-Zellen -> Wandsegmente (echte Hoehe), T3
	_build_roofs(g)         # (b) Dach je Gebaeude (Connected-Component)
	_build_estate_mesa(g)   # (c) Fels-Mesa unter Anwesen-Ebene (Luecke y0->3)
	_build_sand_band(g)     # (d1) Strand-Sand ueber dem Suedband
	_scatter(g, rng)        # (d2) Palmen + Lowpoly-Streuung
	_cover_props(g)         # (e) Kisten/Faesser auf cover>0 (nicht im Demo-Dopp.)
	_build_dock(g)          # (f) Steg an der Sued-Landezone


# ---------------------------------------------------------------- (a) WAENDE
func _build_walls(g: Grid3D) -> void:
	var cells := []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t != null and t.kind == Tac3DTile.Kind.WALL:
			cells.append(c)
	if cells.is_empty():
		return

	var box := BoxMesh.new()
	box.size = Vector3(TILE, WALL_H, WALL_THICK)
	box.material = _building_mat("wall")

	var xforms := []
	for c in cells:
		var w := g.cell_to_world(c)
		var pos := Vector3(w.x, w.y + TOP_Y + WALL_H * 0.5, w.z)
		var basis := Basis(Vector3.UP, _outward_yaw(g, c))
		xforms.append(Transform3D(basis, pos))
	_add_mm(g, "Walls", box, xforms)


## Wand quer zur Innenseite drehen: liegt ein begehbarer Nachbar in X, dreht
## das Segment 90 Grad, sodass die Wand entlang der Gebaeudekante laeuft.
func _outward_yaw(g: Grid3D, c: Vector3i) -> float:
	var xp: Tac3DTile = g.get_tile(c + Vector3i(1, 0, 0))
	var xm: Tac3DTile = g.get_tile(c + Vector3i(-1, 0, 0))
	if (xp != null and xp.begehbar) or (xm != null and xm.begehbar):
		return PI * 0.5
	return 0.0


# --------------------------------------------------------------- (b) DAECHER
func _build_roofs(g: Grid3D) -> void:
	# Gebaeude = zusammenhaengende WALL/FLOOR-Zellen (je Ebene).
	var cellset := {}
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t != null and (t.kind == Tac3DTile.Kind.WALL or t.kind == Tac3DTile.Kind.FLOOR):
			cellset[c] = true
	if cellset.is_empty():
		return

	var holder := Node3D.new()
	holder.name = "Roofs"
	add_child(holder)
	var roof_mat := _flat(Color(0.55, 0.28, 0.20))   # Terrakotta, stylisiert

	for comp in _components(cellset):
		if comp.size() < 4:
			continue
		var min_x := 1 << 30
		var max_x := -(1 << 30)
		var min_z := 1 << 30
		var max_z := -(1 << 30)
		var level := 0
		for cc in comp:
			var c: Vector3i = cc
			min_x = min(min_x, c.x); max_x = max(max_x, c.x)
			min_z = min(min_z, c.z); max_z = max(max_z, c.z)
			level = c.y
		var w := float(max_x - min_x + 1) * TILE
		var d := float(max_z - min_z + 1) * TILE
		var cx := float(min_x + max_x + 1) * 0.5 * TILE
		var cz := float(min_z + max_z + 1) * 0.5 * TILE
		var roof_h: float = clampf(minf(w, d) * 0.35, 0.6, 1.8)
		var base_len: float = minf(w, d)
		var ridge_len: float = maxf(w, d)

		var prism := PrismMesh.new()
		prism.size = Vector3(base_len + 0.4, roof_h, ridge_len + 0.4)
		var mi := MeshInstance3D.new()
		mi.mesh = prism
		mi.material_override = roof_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var base_top := float(level) * LEVEL_STEP + TOP_Y + WALL_H
		var yaw := 0.0 if d >= w else PI * 0.5   # First entlang der laengeren Achse
		mi.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(cx, base_top + roof_h * 0.5, cz))
		holder.add_child(mi)


# ------------------------------------------------------------- (c) FELS-MESA
func _build_estate_mesa(g: Grid3D) -> void:
	# Zellen ueber Ebene 0 (Anwesen-Huegel) -> Fels-Box fuellt die Luecke y0->Ebene.
	var cellset := {}
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y >= 1:
			cellset[c] = true
	if cellset.is_empty():
		return

	var holder := Node3D.new()
	holder.name = "Mesa"
	add_child(holder)
	var rock_mat := _terrain_mat("rock")

	for comp in _components(cellset):
		var min_x := 1 << 30
		var max_x := -(1 << 30)
		var min_z := 1 << 30
		var max_z := -(1 << 30)
		var level := 1 << 30
		for cc in comp:
			var c: Vector3i = cc
			min_x = min(min_x, c.x); max_x = max(max_x, c.x)
			min_z = min(min_z, c.z); max_z = max(max_z, c.z)
			level = min(level, c.y)
		var w := float(max_x - min_x + 1) * TILE + 0.1
		var d := float(max_z - min_z + 1) * TILE + 0.1
		var cx := float(min_x + max_x + 1) * 0.5 * TILE
		var cz := float(min_z + max_z + 1) * 0.5 * TILE
		# Von Boden (y0) bis knapp unter die Ebenen-Box-Unterkante.
		var top := float(level) * LEVEL_STEP - TOP_Y
		if top <= 0.2:
			continue
		var boxm := BoxMesh.new()
		boxm.size = Vector3(w, top, d)
		var mi := MeshInstance3D.new()
		mi.mesh = boxm
		mi.material_override = rock_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = Transform3D(Basis.IDENTITY, Vector3(cx, top * 0.5, cz))
		holder.add_child(mi)


# --------------------------------------------------------- (d1) STRAND-SAND
func _build_sand_band(g: Grid3D) -> void:
	# Duenne Sand-Platte knapp ueber der Gras-Box auf dem Suedband (rein optisch).
	var xforms := []
	for k in g.all_cells():
		var c: Vector3i = k
		if c.z < BEACH_Z or c.y != 0:
			continue
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.kind != Tac3DTile.Kind.GROUND:
			continue
		var w := g.cell_to_world(c)
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(w.x, w.y + TOP_Y + 0.02, w.z)))
	if xforms.is_empty():
		return
	var slab := BoxMesh.new()
	slab.size = Vector3(TILE, 0.06, TILE)
	slab.material = _terrain_mat("sand")
	_add_mm(g, "SandBand", slab, xforms)


# --------------------------------------------------------------- (d2) SCATTER
func _scatter(g: Grid3D, rng: RandomNumberGenerator) -> void:
	# Kandidaten deterministisch sortieren (Dictionary-Reihenfolge ist instabil).
	var ground := []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.kind != Tac3DTile.Kind.GROUND:
			continue
		if t.cover > 0.0 or c.y != 0:
			continue
		ground.append(c)
	ground.sort_custom(func(a, b): return (a.z * 100000 + a.x) < (b.z * 100000 + b.x))
	if ground.is_empty():
		return

	var a3d := _a3d()
	# Palme (T2: ueber Assets3D normalisiert) ODER Primitiv-Fallback-Palme.
	var palm_mesh: Mesh = null
	var palm_scale := 1.0
	var palm_mat: Material = null
	if a3d != null and a3d.has_method("nature_mesh_raw"):
		palm_mesh = a3d.nature_mesh_raw("palm")
		palm_scale = a3d.nature_normalized_scale("palm")
		palm_mat = a3d.nature_material("palm")

	var palm_x := []   # Array[Transform3D]
	var bush_x := []
	var rock_x := []

	for c in ground:
		var w := g.cell_to_world(c)
		var base := Vector3(w.x, w.y + TOP_Y, w.z)
		var beach: bool = c.z >= BEACH_Z
		var shore := _is_shore(g, c)
		var r := rng.randf()
		# Palmen: Strand/Ufer palmengesaeumt (Dichte gedrosselt, damit die Soeldner
			# am Spawn nicht hinter einer Palmenwand verschwinden — Kriterium b:
			# lesbar/plausible), spaerlich am Dschungelrand im Inland.
		var palm_p := 0.03
		if beach:
			palm_p = 0.14
		elif shore:
			palm_p = 0.10
		if r < palm_p:
			var yaw := rng.randf() * TAU
			var s := palm_scale * rng.randf_range(0.88, 1.12)
			var jitter := Vector3(rng.randf_range(-0.25, 0.25), 0.0, rng.randf_range(-0.25, 0.25))
			palm_x.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), base + jitter))
			continue
		# Kein Palmen-Feld -> evtl. Busch/Fels (nur Inland, nicht am nackten Strand).
		if beach:
			continue
		if r < 0.03 + 0.12:
			var yaw2 := rng.randf() * TAU
			var s2 := rng.randf_range(0.8, 1.2)
			bush_x.append(Transform3D(Basis(Vector3.UP, yaw2).scaled(Vector3(s2, s2 * 0.75, s2)), base))
		elif r < 0.15 + 0.05:
			var yaw3 := rng.randf() * TAU
			var s3 := rng.randf_range(0.7, 1.3)
			rock_x.append(Transform3D(Basis(Vector3.UP, yaw3).scaled(Vector3(s3, s3, s3)), base))

	# Palmen-MultiMesh (echtes Mesh) — Fallback: einzelne Primitiv-Palmen (begrenzt).
	if not palm_x.is_empty():
		if palm_mesh != null:
			var pm := palm_mesh
			if palm_mat != null and pm is ArrayMesh:
				# Surface-Material am Roh-Mesh sicherstellen (OBJ hat keins).
				var am := pm as ArrayMesh
				if am.get_surface_count() > 0:
					am.surface_set_material(0, palm_mat)
			_add_mm(g, "Palms", pm, palm_x)
		elif a3d != null and a3d.has_method("nature_mesh"):
			var holder := Node3D.new()
			holder.name = "PalmsFallback"
			add_child(holder)
			for i in mini(palm_x.size(), 120):
				var node: Node3D = a3d.nature_mesh("palm")
				if node != null:
					node.transform = palm_x[i]
					holder.add_child(node)

	if not bush_x.is_empty():
		var bush := SphereMesh.new()
		bush.radius = 0.32
		bush.height = 0.6
		bush.radial_segments = 6
		bush.rings = 3
		bush.material = _flat(Color(0.20, 0.44, 0.18))
		_add_mm(g, "Bushes", bush, bush_x)

	if not rock_x.is_empty():
		var rk := SphereMesh.new()
		rk.radius = 0.26
		rk.height = 0.4
		rk.radial_segments = 5
		rk.rings = 2
		rk.material = _flat(Color(0.46, 0.46, 0.48))
		_add_mm(g, "Rocks", rk, rock_x)


func _is_shore(g: Grid3D, c: Vector3i) -> bool:
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var t: Tac3DTile = g.get_tile(c + d)
		if t != null and t.is_water():
			return true
	return false


# ----------------------------------------------------------- (e) COVER-PROPS
func _cover_props(g: Grid3D) -> void:
	# Doppelung vermeiden: setzt ein Orchestrator bereits Props (Demo: PropsRoot),
	# ueberlassen wir ihm die Deckung. Im Kampf (ohne PropsRoot) fuellen wir sie.
	if _ancestor_has("PropsRoot"):
		return
	var a3d := _a3d()
	if a3d == null or not a3d.has_method("prop"):
		return
	var cells := []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t != null and t.begehbar and t.cover > 0.0:
			cells.append(c)
	if cells.is_empty():
		return
	cells.sort_custom(func(a, b): return (a.z * 100000 + a.x) < (b.z * 100000 + b.x))

	var holder := Node3D.new()
	holder.name = "CoverProps"
	add_child(holder)
	var i := 0
	for c in cells:
		var id: String = "crate" if (i % 2 == 0) else "barrel"
		var node: Node3D = a3d.prop(id)
		if node != null:
			node.position = g.cell_to_world(c) + Vector3(0.0, TOP_Y, 0.0)
			holder.add_child(node)
		i += 1


# ---------------------------------------------------------------- (f) STEG
func _build_dock(g: Grid3D) -> void:
	# Planken-Steg von der suedlichen Uferkante ins Wasser (rein optisch).
	var beach := []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t != null and t.kind == Tac3DTile.Kind.GROUND and c.z >= BEACH_Z and c.y == 0:
			beach.append(c)
	if beach.is_empty():
		return
	# Median-x und maximales z (suedlichste Reihe) bestimmen.
	var xs := []
	var mz := -(1 << 30)
	for c in beach:
		xs.append(c.x)
		mz = max(mz, c.z)
	xs.sort()
	var mx: int = xs[xs.size() / 2]

	var plank := BoxMesh.new()
	plank.size = Vector3(1.2, 0.12, 1.0)
	plank.material = _terrain_mat("wood")
	var xforms := []
	for i in range(5):
		var cell := Vector3i(mx, 0, mz + 1 + i)
		var w := g.cell_to_world(cell)
		xforms.append(Transform3D(Basis.IDENTITY, Vector3(w.x, WATER_Y, w.z)))
	if xforms.is_empty():
		return
	_add_mm(g, "Dock", plank, xforms)


# --------------------------------------------------------------- Helfer
## Connected-Components (4-Nachbarn, gleiche Ebene) ueber ein Vector3i-Set.
func _components(cellset: Dictionary) -> Array:
	var seen := {}
	var comps := []
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for key in cellset.keys():
		if seen.has(key):
			continue
		var comp := []
		var stack := [key]
		seen[key] = true
		while not stack.is_empty():
			var cur: Vector3i = stack.pop_back()
			comp.append(cur)
			for d in dirs:
				var nb: Vector3i = cur + d
				if cellset.has(nb) and not seen.has(nb):
					seen[nb] = true
					stack.append(nb)
		comps.append(comp)
	return comps


## Baut eine MultiMeshInstance3D (Reihenfolge-Falle beachtet) + custom_aabb.
func _add_mm(g: Grid3D, node_name: String, mesh: Mesh, xforms: Array) -> void:
	if mesh == null or xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()   # ZULETZT
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # T6
	mmi.custom_aabb = _field_aabb(g)
	add_child(mmi)


func _field_aabb(g: Grid3D) -> AABB:
	var b := g.bounds_world()
	var pad := Vector3(6.0, 16.0, 6.0)
	return AABB(b.position - pad, b.size + pad * 2.0)


func _a3d() -> Node:
	return get_node_or_null("/root/Assets3D")


func _ancestor_has(child_name: String) -> bool:
	var n := get_parent()
	while n != null:
		if n.get_node_or_null(child_name) != null:
			return true
		n = n.get_parent()
	return false


func _terrain_mat(name: String) -> Material:
	var a := _a3d()
	if a != null and a.has_method("terrain_material_named"):
		return a.terrain_material_named(name)
	return _flat(_terrain_fallback_color(name))


func _building_mat(id: String) -> Material:
	var a := _a3d()
	if a != null and a.has_method("building_material"):
		return a.building_material(id)
	return _flat(Color(0.55, 0.32, 0.26))


func _terrain_fallback_color(name: String) -> Color:
	match name:
		"grass": return Color(0.33, 0.52, 0.24)
		"dirt": return Color(0.46, 0.34, 0.20)
		"sand": return Color(0.85, 0.77, 0.55)
		"wood": return Color(0.55, 0.40, 0.23)
		"rock": return Color(0.48, 0.48, 0.50)
	return Color(0.5, 0.5, 0.5)


func _flat(col: Color) -> StandardMaterial3D:
	var key := "flat:" + str(col)
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # nie schwarz ohne Licht
	m.roughness = 1.0
	_mat_cache[key] = m
	return m

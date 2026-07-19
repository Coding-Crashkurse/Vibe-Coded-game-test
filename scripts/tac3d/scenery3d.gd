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
const PALM_MIN_DIST := 4      # Mindestabstand zwischen Palmen (in Zellen)
const PALM_KEEPOUT := 2       # Palmen-Sperrradius um Gebaeude-Zellen (Zellen)
const PALM_P_BEACH := 0.10    # Palmen-Chance am Strand (vor Mindestabstand)
const PALM_P_SHORE := 0.07    # Palmen-Chance am Ufer
const PALM_P_INLAND := 0.025  # Palmen-Chance im Inland (sehr spaerlich)
const GRASS_P := 0.55         # Gras-Bueschel-Chance je Inland-Bodenzelle
const GRASS_P2 := 0.32        # zweites Bueschel je Zelle (Dichte, kleine Cluster)
const PEBBLE_P := 0.09        # Kleinstein-Chance je Inland-Bodenzelle
const PEBBLE_P_BEACH := 0.22  # mehr Kiesel am Strand
const EDGE_INSET := 3         # #5: keine Deko (Palmen/Buesche/Fels) so nah am Kartenrand,
                              #     dass Baeume "abgeschnitten" ueber den Rand ragen.

var _mat_cache := {}


func build(g: Grid3D) -> void:
	# T1: idempotent aufraeumen OHNE free() waehrend get_children()-Iteration.
	for c in get_children().duplicate():
		c.queue_free()
	if g == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	_build_ocean(g)         # (0) grosse Wasser-Ebene rund um die Insel (fuellt das "blaue Nichts")
	_build_walls(g)         # (a) WALL-Zellen -> Wandsegmente (echte Hoehe), T3
	_build_roofs(g)         # (b) Dach je Gebaeude (Connected-Component)
	_build_estate_mesa(g)   # (c) Fels-Mesa unter Anwesen-Ebene (Luecke y0->3)
	_build_sand_band(g)     # (d1) Strand-Sand ueber dem Suedband
	_scatter(g, rng)        # (d2) Palmen + Lowpoly-Streuung
	_scatter_ground_detail(g, rng)  # (d3) feine Gras-/Kiesel-Streuung (Detail)
	_cover_props(g)         # (e) Kisten/Faesser auf cover>0 (nicht im Demo-Dopp.)
	_build_dock(g)          # (f) Steg an der Sued-Landezone


# ---------------------------------------------------------- (0) OZEAN-EBENE
# #4b: Ohne Wasser scheint der Himmel am Kartenrand als flaches, haessliches Blau
# durch ("das blau links oben"). Eine grosse, leicht unter der Grasoberkante liegende
# Wasser-Ebene fuellt den Rand -> die Insel liegt im Meer statt im Nichts.
func _build_ocean(g: Grid3D) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(600.0, 600.0)   # weit ueber die 72er-Karte hinaus (Rand fuellt Sichtfeld)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.32, 0.48)
	m.metallic = 0.0
	m.roughness = 0.28                   # etwas Glanz -> liest sich als Wasser, nicht als blaue Platte
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Emission-Sockel, falls das Licht-Setup mal fehlt -> Wasser nie pechschwarz (Renderer-Falle).
	m.emission_enabled = true
	m.emission = Color(0.05, 0.16, 0.24)
	m.emission_energy_multiplier = 0.35
	plane.material = m
	var mi := MeshInstance3D.new()
	mi.name = "Ocean"
	mi.mesh = plane
	# Auf die Kartenmitte zentrieren, knapp UNTER die Grasoberkante (Ufer taucht ins Wasser).
	var ctr := g.cell_to_world(Vector3i(g.size_x / 2, 0, g.size_z / 2))
	mi.position = Vector3(ctr.x, TOP_Y - 0.10, ctr.z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


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

	# Gebaeude-Zellen (WALL/FLOOR) fuer Keepout: keine Palmen an/in Gebaeuden.
	var building := {}
	for k in g.all_cells():
		var bc: Vector3i = k
		var bt: Tac3DTile = g.get_tile(bc)
		if bt != null and (bt.kind == Tac3DTile.Kind.WALL or bt.kind == Tac3DTile.Kind.FLOOR):
			building[bc] = true

	var palm_x := []      # Array[Transform3D]
	var palm_cells := []  # bereits gesetzte Palmen-Zellen -> Mindestabstand
	var bush_x := []
	var rock_x := []

	for c in ground:
		# #5: Rand-Inset — Deko nicht direkt an die Kartenkante, sonst wirken Baeume
		# "abgeschnitten", wo sie ueber den Boden-Rand ins Nichts/Wasser ragen.
		if c.x < EDGE_INSET or c.x >= g.size_x - EDGE_INSET \
		   or c.z < EDGE_INSET or c.z >= g.size_z - EDGE_INSET:
			continue
		var w := g.cell_to_world(c)
		var base := Vector3(w.x, w.y + TOP_Y, w.z)
		var beach: bool = c.z >= BEACH_Z
		var shore := _is_shore(g, c)
		var r := rng.randf()
		# Palmen: WENIGE, weit gestreut. Strand/Ufer bevorzugt, Inland sehr spaerlich.
		# Mindestabstand (PALM_MIN_DIST) + Gebaeude-Keepout verhindern das fruehere
		# Dickicht -> unterschiedlich grosse Einzelpalmen statt Palmenwand.
		var palm_p := PALM_P_INLAND
		if beach:
			palm_p = PALM_P_BEACH
		elif shore:
			palm_p = PALM_P_SHORE
		if r < palm_p and not _near_building(building, c) and _palm_far_enough(palm_cells, c):
			palm_cells.append(c)
			var yaw := rng.randf() * TAU   # natuerliche Zufalls-Y-Rotation je Palme
			# Etwas kleiner + deutlich mehr Groessen-Variation -> Einzelbaeume statt Klon-Reihe.
			var s := palm_scale * rng.randf_range(0.55, 0.98)
			var jitter := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
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
			_add_mm(g, "Palms", pm, palm_x, true)   # Palmen werfen Schatten
		elif a3d != null and a3d.has_method("nature_mesh"):
			var holder := Node3D.new()
			holder.name = "PalmsFallback"
			add_child(holder)
			for i in mini(palm_x.size(), 120):
				var node: Node3D = a3d.nature_mesh("palm")
				if node != null:
					node.transform = palm_x[i]
					_enable_shadows(node)   # Fallback-Palme wirft Schatten
					holder.add_child(node)

	if not bush_x.is_empty():
		var bush := SphereMesh.new()
		bush.radius = 0.32
		bush.height = 0.6
		bush.radial_segments = 6
		bush.rings = 3
		bush.material = _flat(Color(0.20, 0.44, 0.18))
		_add_mm(g, "Bushes", bush, bush_x, true)   # groessere Deko wirft Schatten

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
			_enable_shadows(node)   # Cover-Props werfen Schatten
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
func _add_mm(g: Grid3D, node_name: String, mesh: Mesh, xforms: Array, cast_shadow := false,
		colors := []) -> void:
	if mesh == null or xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var use_colors := not colors.is_empty()
	mm.use_colors = use_colors   # VOR instance_count setzen (Buffer-Layout)
	mm.mesh = mesh
	mm.instance_count = xforms.size()   # ZULETZT
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	# T6: default kein Schatten (Waende/Daecher/Sand/Steg); Palmen aktivieren ihn.
	mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	mmi.custom_aabb = _field_aabb(g)
	add_child(mmi)


## Palme mind. PALM_KEEPOUT Zellen von jeder Gebaeude-Zelle entfernt halten.
func _near_building(building: Dictionary, c: Vector3i) -> bool:
	for dz in range(-PALM_KEEPOUT, PALM_KEEPOUT + 1):
		for dx in range(-PALM_KEEPOUT, PALM_KEEPOUT + 1):
			if building.has(Vector3i(c.x + dx, c.y, c.z + dz)):
				return true
	return false


## True, wenn c von allen bereits gesetzten Palmen mind. PALM_MIN_DIST entfernt ist.
func _palm_far_enough(placed: Array, c: Vector3i) -> bool:
	for pc in placed:
		var p: Vector3i = pc
		var dx := c.x - p.x
		var dz := c.z - p.z
		if dx * dx + dz * dz < PALM_MIN_DIST * PALM_MIN_DIST:
			return false
	return true


## Schatten fuer eine Prop-/Fallback-Palmen-Hierarchie rekursiv aktivieren.
func _enable_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for ch in n.get_children():
		_enable_shadows(ch)


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


# ------------------------------------------------- (d3) BODEN-DETAIL-STREUUNG
## Dichte, sehr kleine Gras-Bueschel + Kiesel ueber alle Boden-Zellen — bricht die
## Leere der Grasflaeche auf. Alles MultiMesh mit Per-Instanz-Farbe (use_colors),
## deterministisch (fester rng), rein optisch, Primitiv-Fallback-frei (kein Asset).
func _scatter_ground_detail(g: Grid3D, rng: RandomNumberGenerator) -> void:
	var cells := []
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y != 0:
			continue
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.kind != Tac3DTile.Kind.GROUND:
			continue
		cells.append(c)
	if cells.is_empty():
		return
	cells.sort_custom(func(a, b): return (a.z * 100000 + a.x) < (b.z * 100000 + b.x))

	var grass_x := []
	var grass_c := []
	var peb_x := []
	var peb_c := []
	for c in cells:
		var w := g.cell_to_world(c)
		var base := Vector3(w.x, w.y + TOP_Y, w.z)
		var beach: bool = c.z >= BEACH_Z
		# Gras nur im Inland (nicht auf Sand); leichte Cluster durch 2. Chance.
		if not beach:
			if rng.randf() < GRASS_P:
				_add_tuft(grass_x, grass_c, base, rng)
			if rng.randf() < GRASS_P2:
				_add_tuft(grass_x, grass_c, base, rng)
		# Kiesel ueberall, am Strand haeufiger + sandiger getoent.
		var pp: float = PEBBLE_P_BEACH if beach else PEBBLE_P
		if rng.randf() < pp:
			_add_pebble(peb_x, peb_c, base, rng, beach)

	if not grass_x.is_empty():
		_add_mm(g, "GrassTufts", _grass_tuft_mesh(), grass_x, false, grass_c)
	if not peb_x.is_empty():
		var pm := SphereMesh.new()
		pm.radius = 0.12
		pm.height = 0.16
		pm.radial_segments = 5
		pm.rings = 2
		pm.material = _vcol_mat()
		_add_mm(g, "Pebbles", pm, peb_x, false, peb_c)


func _add_tuft(xf: Array, cols: Array, base: Vector3, rng: RandomNumberGenerator) -> void:
	var jitter := Vector3(rng.randf_range(-0.42, 0.42), 0.0, rng.randf_range(-0.42, 0.42))
	var yaw := rng.randf() * TAU
	# ART-PASS v2: kleiner (0.65..1.3 -> 0.55..1.0) + flacher (hy max 1.25 -> 1.05),
	# damit die Bueschel als Boden-Gras lesen, nicht als grosse leuchtende Shards.
	var s := rng.randf_range(0.55, 1.0)                 # kleine bis mittlere Bueschel
	var hy := rng.randf_range(0.8, 1.05)               # Hoehen-Variation
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * hy, s))
	xf.append(Transform3D(b, base + jitter))
	# Farb-Variation um ein Grasgruen; heller Anteil etwas entsaettigt/gedaempft
	# (0.48,0.62,0.26 -> 0.40,0.53,0.24), sonst zieht der Saettigungs-Boost ins Neon-Lime.
	var col := Color(0.24, 0.42, 0.15).lerp(Color(0.40, 0.53, 0.24), rng.randf())
	cols.append(col)


func _add_pebble(xf: Array, cols: Array, base: Vector3, rng: RandomNumberGenerator, beach: bool) -> void:
	var jitter := Vector3(rng.randf_range(-0.42, 0.42), 0.0, rng.randf_range(-0.42, 0.42))
	var s := rng.randf_range(0.55, 1.5)
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.6, s))
	xf.append(Transform3D(b, base + jitter + Vector3(0.0, 0.03, 0.0)))
	var hi := Color(0.72, 0.66, 0.50) if beach else Color(0.58, 0.55, 0.52)
	cols.append(Color(0.40, 0.40, 0.43).lerp(hi, rng.randf()))


## Kleines Gras-Bueschel: 3 gekreuzte Dreieck-Halme (double-sided, unshaded).
## Vertex-Farbe = weiss -> die Per-Instanz-Farbe des MultiMesh bestimmt den Ton.
func _grass_tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var blades := 3
	var hw := 0.13
	var h := 0.36
	for i in blades:
		var ang := float(i) / float(blades) * PI
		var dx := cos(ang) * hw
		var dz := sin(ang) * hw
		st.set_color(Color.WHITE)
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(-dx, 0.0, -dz))
		st.add_vertex(Vector3(dx, 0.0, dz))
		st.add_vertex(Vector3(dx * 0.08, h, dz * 0.08))   # leicht geneigte Spitze
	st.set_material(_vcol_mat())   # Surface-Material -> MultiMesh nutzt es
	return st.commit()


## Material mit Per-Vertex/Instanz-Farbe als Albedo (fuer farbvariable MultiMeshes).
func _vcol_mat() -> StandardMaterial3D:
	if _mat_cache.has("vcol"):
		return _mat_cache["vcol"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # Halme von beiden Seiten sichtbar
	m.roughness = 1.0
	_mat_cache["vcol"] = m
	return m

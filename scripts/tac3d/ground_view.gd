class_name GroundView3D
extends MultiMeshInstance3D
## PHASE 6 — map optics: instead of ONE vertex-coloured MultiMesh there is now
## ONE MultiMesh PER TILE KIND, each with Assets3D.terrain_material(kind)
## (Kenney PNG texture from the repo; fallback = the old flat colour material).
## Water stays a separate shader overlay (_build_water UNCHANGED).
## At the end ONE Scenery3D child is created (walls/decoration/props) — the optics
## therefore propagate automatically into demo AND combat (the orchestrator calls build()).
##
## Walkability/LOS/combat are NOT touched (pure presentation).
## FROZEN FIXES: T1 (clean up idempotently via duplicate()+queue_free(), NEVER
## free() during get_children() iteration), T3 (WALL is drawn ONLY by Scenery3D —
## the ground MM LEAVES WALL OUT), T5 (texture→colour fallback via Assets3D),
## T6 (shadows OFF). If a texture/autoload is missing → flat colour → smoke stays green.

# Colours per kind — FALLBACK when Assets3D/PNG is missing (identical to the old optics).
const COLOR_GROUND := Color(0.30, 0.55, 0.22)        # green
const COLOR_WATER_SHALLOW := Color(0.45, 0.72, 0.90) # light blue
const COLOR_WATER_DEEP := Color(0.10, 0.25, 0.55)    # dark blue
const COLOR_BRIDGE := Color(0.50, 0.33, 0.16)        # brown
const COLOR_ROOF := Color(0.55, 0.55, 0.58)          # grey
const COLOR_RAMP := Color(0.80, 0.72, 0.48)          # sand-coloured
const COLOR_WALL := Color(0.22, 0.22, 0.24)          # dark grey
const COLOR_FLOOR := Color(0.62, 0.48, 0.30)         # wood (fallback)
const COLOR_DEFAULT := Color(0.80, 0.80, 0.80)

# Water overlay (separate MultiMesh): thin PlaneMesh just above the box top edge.
const WATER_NODE_NAME := "WaterOverlay"
const WATER_Y := 0.15   # box top edge is at +0.1; clearly above the wave amplitude (amp 0.05)

var _fallback_mat_cache := {}   # int(kind) -> StandardMaterial3D
var _tinted_mat_cache := {}     # int(kind) -> Material (duplicate with vertex_color_use_as_albedo)
var _lid_mmis: Array = []       # cellar lid MMs (ground ABOVE level -1 rooms)


func build(g: Grid3D) -> void:
	if g == null:
		return

	# T1: clean up idempotently. NO free() during get_children() iteration —
	# iterate over a copy and use queue_free().
	for c in get_children().duplicate():
		if c.name.begins_with("MM_") or c.name == "Scenery":
			c.queue_free()

	# self is itself a MultiMeshInstance3D — remove the old (vertex-coloured)
	# MultiMesh so that only the per-kind children render.
	multimesh = null

	# Shared ground mesh (1.0 x 0.2 x 1.0) for all per-kind MultiMeshes.
	var box := BoxMesh.new()
	box.size = Vector3(1.0, 0.2, 1.0)

	# Group cells by kind. Water separately (see _build_water); WALL OFF (T3, only
	# Scenery3D draws walls with real height). Otherwise parity with the old optics:
	# only walkable cells get a ground box.
	var by_kind := {}                          # int(kind) -> Array[Vector3i]
	var by_kind_lid := {}                      # ditto, CELLAR LIDS only (room directly below)
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.is_water():
			continue
		# Cellar lid: level-0 cells with a room directly below go into DEDICATED
		# MMs -> set_cellar_open() can flip the floor open when someone is down there.
		var target: Dictionary = by_kind_lid if (c.y == 0 and g.get_tile(Vector3i(c.x, -1, c.z)) != null) else by_kind
		if t.kind == Tac3DTile.Kind.WALL:      # T3: only Scenery3D draws wall GEOMETRY.
			# But the GROUND under the wall must still exist: the wall segment is only
			# 0.24 thick — without a ground box a hole gapes in the remaining tile strip
			# down to the ocean plane (visible since roofs can vanish). Wood, as inside.
			var kw := int(Tac3DTile.Kind.FLOOR)
			if not target.has(kw):
				target[kw] = []
			target[kw].append(c)
			continue
		# Palm collision: GROUND cells that Scenery3D marked as non-walkable (a palm
		# occupies the tile) keep their ground box — otherwise a hole would appear
		# under the palm on rebuild. Only genuine non-floors (VOID) stay empty.
		if not g.is_walkable(c) and t.kind != Tac3DTile.Kind.GROUND:
			continue
		var ki := int(t.kind)
		if not target.has(ki):
			target[ki] = []
		target[ki].append(c)

	for kind in by_kind:
		_make_kind_mm(g, box, kind, by_kind[kind])
	_lid_mmis.clear()
	for kind in by_kind_lid:
		var lid_mmi := _make_kind_mm(g, box, kind, by_kind_lid[kind], "_LID")
		if lid_mmi != null:
			_lid_mmis.append(lid_mmi)

	# Generous custom_aabb (even when self is empty — harmless, never hurts).
	var b := g.bounds_world()
	var pad := Vector3(4.0, 8.0, 4.0)
	custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)

	# Water overlay (shader) — UNCHANGED.
	_build_water(g)

	# Scenery (walls with height, roofs, rock mesa, palms/decoration, cover props,
	# dock) as a child. Takes effect in BOTH scenes (demo + combat), without an
	# orchestrator diff. load()+new() instead of the Scenery3D identifier: robust
	# even when the global class_name cache (new file) has not been regenerated yet.
	var sc: Node = load("res://scripts/tac3d/scenery3d.gd").new()
	sc.name = "Scenery"
	add_child(sc)
	sc.build(g)


## One MultiMeshInstance3D "MM_<kind>" for all cells of a kind.
## ORDERING TRAP: transform_format + use_colors FIRST, instance_count LAST.
## Material via material_override (the box mesh is shared) — a dedicated Kenney
## PNG texture per kind, or a flat colour fallback. Shadows OFF (T6).
##
## ART PASS: a deterministically varied INSTANCE colour per tile
## (use_colors=true; set_instance_color) → modulates the albedo_texture so the
## uniform texture breaks up (mottled meadow instead of flat green).
## Water (separate overlay) and BRIDGE stay UNCHANGED (white/no colour).
func _make_kind_mm(g: Grid3D, box: Mesh, kind: int, cells: Array, suffix := "") -> MultiMeshInstance3D:
	if cells.is_empty():
		return null

	# BRIDGE is exempt (stays exactly as before). All other ground kinds get
	# instance colour jitter.
	var tint := kind != int(Tac3DTile.Kind.BRIDGE)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	if tint:
		mm.use_colors = true                   # set BEFORE instance_count
	mm.mesh = box
	mm.instance_count = cells.size()           # LAST
	for i in cells.size():
		var c: Vector3i = cells[i]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, g.cell_to_world(c)))
		if tint:
			mm.set_instance_color(i, _tile_tint(c, kind))

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_" + str(kind) + suffix
	mmi.multimesh = mm
	mmi.material_override = _terrain_material_tinted(kind, tint)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # T6
	# custom_aabb is mandatory (a MultiMesh is not auto-culled).
	var b := g.bounds_world()
	var pad := Vector3(4.0, 8.0, 4.0)
	mmi.custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)
	add_child(mmi)
	return mmi


## Open/close the cellar lid (called by the orchestrator from compute_vision):
## when a merc descends to level -1, the floor above the cellar flips open —
## otherwise the hideout (Otto!) would be hidden by the level-0 floor. Purely optical.
func set_cellar_open(open: bool) -> void:
	for m in _lid_mmis:
		if is_instance_valid(m):
			m.visible = not open


## Terrain material for a kind: prefers Assets3D (Kenney PNG → colour, T5),
## otherwise the local flat colour fallback = the old box optics. Never null.
func _terrain_material(kind: int) -> Material:
	var a3d := get_node_or_null("/root/Assets3D")
	if a3d != null and a3d.has_method("terrain_material"):
		var m: Material = a3d.terrain_material(kind)
		if m != null:
			return m
	return _fallback_kind_material(kind)


## Like _terrain_material, but when per-tile instance colours are used
## (tint=true) a DUPLICATE copy is returned with vertex_color_use_as_albedo=true
## — only that way does the instance colour modulate the albedo_texture. The
## original (Assets3D cache, also used by Scenery3D) stays UNCHANGED.
## Without tint identical to _terrain_material.
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


## Deterministic instance colour jitter per cell (modulates the texture around
## white). GROUND additionally gets a slight hue jitter towards yellow/dark and a
## small proportion of distinct earth/dark-green patches.
func _tile_tint(c: Vector3i, kind: int) -> Color:
	# Brightness ±5 % (all tinted kinds; ±8 % looked like a chessboard).
	var bright := 1.0 + (_cell_rng(c, 1) - 0.5) * 0.10
	var col := Color(bright, bright, bright, 1.0)

	if kind == int(Tac3DTile.Kind.FLOOR):
		# Interior floor CLEARLY darker (wooden planks): the light wood texture read
		# as a "tiled roof" from above — contrast to wall tops/terracotta roof.
		col.r *= 0.58
		col.g *= 0.50
		col.b *= 0.44

	if kind == int(Tac3DTile.Kind.GROUND):
		# Hue jitter: vary around a RICH green (bright-lush ↔ deep green), NO longer
		# towards yellow/earth — that made the meadow dry and olive.
		var h := (_cell_rng(c, 2) - 0.5) * 0.08
		col.r = clampf(col.r - h * 0.5, 0.0, 2.0)
		col.g = clampf(col.g + h * 0.6, 0.0, 2.0)
		col.b = clampf(col.b - h * 0.3, 0.0, 2.0)
		# Small proportion (~12 %) of dark LUSH GREEN patches (damp meadow, not earth).
		if _cell_rng(c, 3) < 0.12:
			var d := 0.70 + _cell_rng(c, 4) * 0.16   # darken by 0.70..0.86
			col.r *= d * 0.82                         # green holds up, R/B drop
			col.g *= d * 1.02
			col.b *= d * 0.80

	return col


## Deterministic 0..1 value from cell coordinate + salt (integer hash mix, no
## random seed/date → identical in headless AND game, smoke-stable).
func _cell_rng(c: Vector3i, salt: int) -> float:
	var n := int(c.x) * 73856093 ^ int(c.z) * 19349663 ^ int(c.y) * 83492791 ^ (salt * 2654435761)
	n = (n ^ (n >> 13)) * 1274126177
	n = n & 0x7fffffff
	return float(n % 1000003) / 1000003.0


## Local fallback (unshaded flat colour) in case the Assets3D autoload is missing.
func _fallback_kind_material(kind: int) -> Material:
	if _fallback_mat_cache.has(kind):
		return _fallback_mat_cache[kind]
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _fallback_color(kind)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # never black without light
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


## Puts the water tiles into a SEPARATE MultiMesh (1 additional draw call).
## Robust fallback: if the Assets3D autoload is missing, NO overlay is created.
## UNCHANGED compared to phase 5.
func _build_water(g: Grid3D) -> void:
	# Remove a previous overlay (build() can run multiple times).
	var old := get_node_or_null(WATER_NODE_NAME)
	if old != null:
		old.free()

	# Autoload guard: without Assets3D there is no shader material -> water stays a box.
	var a3d := get_node_or_null("/root/Assets3D")
	if a3d == null:
		return

	# Collect water cells (shallow + deep).
	var water_cells: Array = []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t != null and (t.kind == Tac3DTile.Kind.WATER_SHALLOW or t.kind == Tac3DTile.Kind.WATER_DEEP):
			water_cells.append(c)
	if water_cells.is_empty():
		return

	# Thin PlaneMesh (1x1), slightly subdivided for soft vertex waves.
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	plane.subdivide_width = 4
	plane.subdivide_depth = 4
	var mat: Material = a3d.water_material()   # shader OR StandardMaterial3D fallback
	if mat != null:
		plane.material = mat

	# 2nd MultiMesh — mind the same ordering trap as for the ground.
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
	# Generous custom_aabb — this MultiMesh is not auto-culled either.
	var b := g.bounds_world()
	var pad := Vector3(4.0, 8.0, 4.0)
	mmi.custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)
	add_child(mmi)

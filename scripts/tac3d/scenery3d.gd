class_name Scenery3D
extends Node3D
## PHASE 6 — stylised tropical island decoration ("Isla Corvo").
## PRESENTATION + palm collision: creates walls (real height), roofs, rock mesa,
## nature scatter (palms + lowpoly), cover props, beach sand and a dock.
## EXCEPTION to the "pure optics" contract: palm cells are marked as non-walkable
## in the grid (begehbar=false) — mercs must not stand INSIDE palms.
## Still NO physics colliders are created; the block lives in the grid (the truth),
## so the pathfinder MUST be built AFTER build(). Cells with FLAG_KEEPOUT
## (spawns/bridge exits/ramp foot, see Tac3DMapGen) stay decoration-free.
## Bush/rock/grass remain passable (pure optics). LOS untouched.
## Everything via MultiMesh/instancing (perf 72x72). If an asset is missing ->
## omit it or use a primitive fallback -> smoke test stays green.
##
## FROZEN FIXES: T1 (build() cleans up idempotently via duplicate()+queue_free()),
## T2 (palm AABB-normalised via Assets3D), T3 (WALL drawn ONLY here),
## T6 (no shadow). Deterministic (fixed SEED) -> stable screenshots.

const SEED := 0xC0FFEE
const BEACH_Z := 64          # southern beach band (purely visual)
const WALL_H := 1.8          # real wall height (m)
const WALL_THICK := 0.24     # wall segment thickness
const TILE := 1.0            # = Grid3D.TILE_SIZE
const LEVEL_STEP := 3.0      # = Grid3D.LEVEL_STEP
const TOP_Y := 0.1           # top edge of the ground box (BoxMesh 0.2 high)
const WATER_Y := 0.15        # water surface (for the dock)
const PALM_MIN_DIST := 4      # minimum distance between palms (in cells)
const PALM_KEEPOUT := 2       # palm exclusion radius around building cells (cells)
const PALM_P_BEACH := 0.10    # palm chance on the beach (before minimum distance)
const PALM_P_SHORE := 0.07    # palm chance on the shore
const PALM_P_INLAND := 0.025  # palm chance inland (very sparse)
const GRASS_P := 0.55         # grass tuft chance per inland ground cell
const GRASS_P2 := 0.32        # second tuft per cell (density, small clusters)
const PEBBLE_P := 0.09        # small-stone chance per inland ground cell
const PEBBLE_P_BEACH := 0.22  # more pebbles on the beach
const EDGE_INSET := 3         # #5: no decoration (palms/bushes/rock) so close to the map
                              #     edge that trees stick out "cut off" over the border.

var _mat_cache := {}


func build(g: Grid3D) -> void:
	# T1: clean up idempotently WITHOUT free() during get_children() iteration.
	for c in get_children().duplicate():
		c.queue_free()
	if g == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED

	_build_ocean(g)         # (0) large water plane around the island (fills the "blue nothing")
	_build_walls(g)         # (a) WALL cells -> wall segments (real height), T3
	_build_door_frames(g)   # (a2) door frames + thresholds: entrances clearly readable
	_build_roofs(g)         # (b) roofs per building — they disappear as soon as a
	                        #     merc (or a seen enemy) stands inside (JA style).
	                        #     No height model/rooftop combat: purely optical.
	_build_estate_mesa(g)   # (c) rock mesa under the estate level (gap y0->3)
	_build_ramp_wedges(g)   # (c2) rock wedges under RAMP cells: visible ascent
	_build_bridge_posts(g)  # (c3) wooden posts under the bridge deck (instead of a rock block)
	_build_cellar_pit(g)    # (c4) earth shaft around the cellar (sight-blocking)
	_build_sand_band(g)     # (d1) beach sand over the southern band
	_scatter(g, rng)        # (d2) palms + lowpoly scatter
	_scatter_ground_detail(g, rng)  # (d3) fine grass/pebble scatter (detail)
	_cover_props(g)         # (e) crates/barrels on cover>0 (not in the demo duplicate)
	_build_dock(g)          # (f) dock at the southern landing zone


# ---------------------------------------------------------- (0) OCEAN PLANE
# #4b: without water the sky shows through at the map edge as a flat, ugly blue
# ("the blue in the top left"). A large water plane sitting slightly below the
# grass top edge fills the border -> the island lies in the sea instead of in the void.
func _build_ocean(g: Grid3D) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.32, 0.48)
	m.metallic = 0.0
	m.roughness = 0.28                   # a bit of gloss -> reads as water, not as a blue slab
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	# Emission floor in case the light setup is ever missing -> water never pitch black (renderer trap).
	m.emission_enabled = true
	m.emission = Color(0.05, 0.16, 0.24)
	m.emission_energy_multiplier = 0.35
	# Cellar cut-out: NO sea surface may lie above underground rooms (y<0) —
	# otherwise, with the cellar lid opened (ground_view set_cellar_open), you look
	# at water instead of into the hideout. The hole = bounding rectangle of all
	# y<0 cells; the sea is built from 4 partial surfaces around it.
	var has_hole := false
	var hx0 := 0.0
	var hx1 := 0.0
	var hz0 := 0.0
	var hz1 := 0.0
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y >= 0:
			continue
		var w := g.cell_to_world(c)
		if not has_hole:
			has_hole = true
			hx0 = w.x - 0.5
			hx1 = w.x + 0.5
			hz0 = w.z - 0.5
			hz1 = w.z + 0.5
		else:
			hx0 = minf(hx0, w.x - 0.5)
			hx1 = maxf(hx1, w.x + 0.5)
			hz0 = minf(hz0, w.z - 0.5)
			hz1 = maxf(hz1, w.z + 0.5)
	# Centre on the map middle, just BELOW the grass top edge (the shore dips into the water).
	var ctr := g.cell_to_world(Vector3i(g.size_x / 2, 0, g.size_z / 2))
	var oy := TOP_Y - 0.10
	var ox0 := ctr.x - 300.0
	var ox1 := ctr.x + 300.0
	var oz0 := ctr.z - 300.0
	var oz1 := ctr.z + 300.0
	var rects: Array = []
	if not has_hole:
		rects.append([ox0, oz0, ox1, oz1])
	else:
		rects.append([ox0, oz0, ox1, hz0])    # north strip (up to the hole edge)
		rects.append([ox0, hz1, ox1, oz1])    # south strip
		rects.append([ox0, hz0, hx0, hz1])    # west strip
		rects.append([hx1, hz0, ox1, hz1])    # east strip
	var oi := 0
	for r in rects:
		var rr: Array = r
		var rw := float(rr[2]) - float(rr[0])
		var rd := float(rr[3]) - float(rr[1])
		if rw <= 0.0 or rd <= 0.0:
			continue
		var pl := PlaneMesh.new()
		pl.size = Vector2(rw, rd)
		pl.material = m
		var mi := MeshInstance3D.new()
		mi.name = "Ocean_%d" % oi
		oi += 1
		mi.mesh = pl
		mi.position = Vector3((float(rr[0]) + float(rr[2])) * 0.5, oy, (float(rr[1]) + float(rr[3])) * 0.5)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)


# ---------------------------------------------------------------- (a) WALLS
# Wall segments are grouped by OUTWARD FACE (bitmask of the outward normals):
# one MultiMesh + one DUPLICATED material per group. _process fades the groups
# whose outward face points TOWARDS THE CAMERA to WALL_FADE_ALPHA — that way the
# interior is always visible, no matter how the player rotates the camera (45° steps).
const WALL_FADE_ALPHA := 0.35   # 0.22 was almost invisible -> the interior read as a "roof"
# Bit -> outward normal (world direction, y=0).
const _OUT_BITS := {1: Vector3(1, 0, 0), 2: Vector3(-1, 0, 0), 4: Vector3(0, 0, 1), 8: Vector3(0, 0, -1)}

var _wall_mats := {}    # mask(int) -> StandardMaterial3D (duplicate, exclusive per group)
var _wall_faded := {}   # mask(int) -> bool (current fade state)
var _last_cam_fwd := Vector3.ZERO
var _roofs := []        # [{node: MultiMeshInstance3D, cells: Dictionary(FLOOR cells)}]


func _build_walls(g: Grid3D) -> void:
	_wall_mats.clear()
	_wall_faded.clear()
	_last_cam_fwd = Vector3.ZERO

	var by_mask := {}   # mask(int) -> Array[Vector3i]
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.kind != Tac3DTile.Kind.WALL:
			continue
		var mask := _outward_mask(g, c)
		if not by_mask.has(mask):
			by_mask[mask] = []
		by_mask[mask].append(c)
	if by_mask.is_empty():
		return

	var box := BoxMesh.new()
	box.size = Vector3(TILE, WALL_H, WALL_THICK)

	for mask in by_mask:
		var xforms := []
		for c in by_mask[mask]:
			var w := g.cell_to_world(c)
			var pos := Vector3(w.x, w.y + TOP_Y + WALL_H * 0.5, w.z)
			var basis := Basis(Vector3.UP, _wall_yaw(g, c))
			xforms.append(Transform3D(basis, pos))
		var mmi := _add_mm(g, "Walls_%d" % int(mask), box, xforms)
		if mmi == null:
			continue
		# DUPLICATE the material per group (the Assets3D original is cached and is
		# also used elsewhere — never mutate it in place).
		var mat: Material = _building_mat("wall")
		if mat is BaseMaterial3D:
			mat = (mat as BaseMaterial3D).duplicate()
		mmi.material_override = mat
		_wall_mats[mask] = mat
		_wall_faded[mask] = false

	# Wall coping: dark capping strip on EVERY wall segment, NEVER fades along — so
	# the building outline stays clearly readable from above, even when the
	# camera-facing wall surfaces are switched to transparent (contrast fix).
	var cap := BoxMesh.new()
	cap.size = Vector3(TILE, 0.08, WALL_THICK + 0.06)
	var cap_xf := []
	for mask in by_mask:
		for c in by_mask[mask]:
			var w := g.cell_to_world(c)
			var pos := Vector3(w.x, w.y + TOP_Y + WALL_H + 0.04, w.z)
			cap_xf.append(Transform3D(Basis(Vector3.UP, _wall_yaw(g, c)), pos))
	var capm := _add_mm(g, "WallCaps", cap, cap_xf)
	if capm != null:
		capm.material_override = _flat(Color(0.15, 0.11, 0.08))


## Orient the wall along the axis on which the wall run CONTINUES — no longer via
## "walkable neighbour" (the old heuristic turned the segments NEXT TO the door
## sideways because the door cell is walkable, and the entrance looked bricked up).
func _wall_yaw(g: Grid3D, c: Vector3i) -> float:
	if _is_wall(g, c + Vector3i(1, 0, 0)) or _is_wall(g, c + Vector3i(-1, 0, 0)):
		return 0.0          # wall run goes along X (box length lies in X)
	if _is_wall(g, c + Vector3i(0, 0, 1)) or _is_wall(g, c + Vector3i(0, 0, -1)):
		return PI * 0.5     # wall run goes along Z
	return 0.0


func _is_wall(g: Grid3D, c: Vector3i) -> bool:
	var t: Tac3DTile = g.get_tile(c)
	return t != null and t.kind == Tac3DTile.Kind.WALL


## Outward bitmask: interior side = FLOOR neighbour (building interior; the
## outside meadow is GROUND and does NOT count). Outward = opposite direction of
## the interior neighbour. Corner/door neighbours can carry 2 bits -> they fade
## along as soon as ONE of their sides faces the camera.
func _outward_mask(g: Grid3D, c: Vector3i) -> int:
	var mask := 0
	if _is_interior_floor(g, c + Vector3i(1, 0, 0)):
		mask |= 2   # interior is at +x -> outward face -x
	if _is_interior_floor(g, c + Vector3i(-1, 0, 0)):
		mask |= 1
	if _is_interior_floor(g, c + Vector3i(0, 0, 1)):
		mask |= 8   # interior is at +z -> outward face -z
	if _is_interior_floor(g, c + Vector3i(0, 0, -1)):
		mask |= 4
	return mask


func _is_interior_floor(g: Grid3D, c: Vector3i) -> bool:
	var t: Tac3DTile = g.get_tile(c)
	return t != null and t.kind == Tac3DTile.Kind.FLOOR


# ------------------------------------------------------- (a2) DOOR FRAMES
## Door = walkable gap in a wall run (wall on BOTH opposite sides).
## Dark wooden frame (2 posts + lintel) + threshold plate on the ground ->
## entrances stand out clearly from wall and floor (contrast fix).
func _build_door_frames(g: Grid3D) -> void:
	var posts := []
	var lintels := []
	var sills := []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.kind == Tac3DTile.Kind.WALL or not g.is_walkable(c):
			continue
		var wx := _door_axis_x(g, c)
		var wz := _door_axis_z(g, c)
		if not (wx or wz):
			continue
		var w := g.cell_to_world(c)
		var basis := Basis(Vector3.UP, 0.0 if wx else PI * 0.5)
		var off := Vector3(TILE * 0.5 - 0.07, 0, 0) if wx else Vector3(0, 0, TILE * 0.5 - 0.07)
		var mid := Vector3(w.x, w.y + TOP_Y + WALL_H * 0.5, w.z)
		posts.append(Transform3D(basis, mid + off))
		posts.append(Transform3D(basis, mid - off))
		lintels.append(Transform3D(basis, Vector3(w.x, w.y + TOP_Y + WALL_H - 0.14, w.z)))
		sills.append(Transform3D(basis, Vector3(w.x, w.y + TOP_Y + 0.03, w.z)))
	if posts.is_empty():
		return
	var wood := _flat(Color(0.26, 0.17, 0.10))
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.14, WALL_H, WALL_THICK + 0.04)
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(TILE, 0.28, WALL_THICK + 0.04)
	var sill_mesh := BoxMesh.new()
	sill_mesh.size = Vector3(TILE * 0.96, 0.06, 0.6)
	var pm := _add_mm(g, "DoorPosts", post_mesh, posts)
	if pm != null:
		pm.material_override = wood
	var lm := _add_mm(g, "DoorLintels", lintel_mesh, lintels)
	if lm != null:
		lm.material_override = wood
	var sm := _add_mm(g, "DoorSills", sill_mesh, sills)
	if sm != null:
		sm.material_override = wood


## Door cell with a wall run along X (wall at +x AND -x)?
func _door_axis_x(g: Grid3D, c: Vector3i) -> bool:
	return _wall_or_door_gap(g, c, Vector3i(1, 0, 0)) and _wall_or_door_gap(g, c, Vector3i(-1, 0, 0))


## Door cell with a wall run along Z (wall at +z AND -z)?
func _door_axis_z(g: Grid3D, c: Vector3i) -> bool:
	return _wall_or_door_gap(g, c, Vector3i(0, 0, 1)) and _wall_or_door_gap(g, c, Vector3i(0, 0, -1))


## Wall directly adjacent OR exactly one walkable gap cell and THEN a wall —
## also detects doors 2 cells wide (estate south gate 57/58): those previously got
## neither a frame nor roof coverage and read as "no door".
func _wall_or_door_gap(g: Grid3D, c: Vector3i, d: Vector3i) -> bool:
	if _is_wall(g, c + d):
		return true
	var n := c + d
	return g.is_walkable(n) and _is_wall(g, n + d)


## Walkable door opening in a wall run (for frames AND roof coverage).
func _is_doorway(g: Grid3D, c: Vector3i) -> bool:
	var t: Tac3DTile = g.get_tile(c)
	if t == null or t.kind == Tac3DTile.Kind.WALL or not g.is_walkable(c):
		return false
	return _door_axis_x(g, c) or _door_axis_z(g, c)


# ------------------------------------------------------------ (b) ROOFS
const ROOF_H := 0.14
const ROOF_LIFT := 0.10   # roof floats just above the wall coping (no Z-fighting)

## One roof per building (= connected FLOOR component, including the adjacent
## wall cells as an overhang). Terracotta, clearly distinguishable from the light
## wooden floor. Visibility is controlled per frame by _update_roofs(): if a merc
## or a SEEN enemy stands inside -> roof gone (JA style).
## The cellar (y<0) gets no roof (it would lie invisible underground).
func _build_roofs(g: Grid3D) -> void:
	_roofs.clear()
	var floors := {}
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y < 0:
			continue
		if _is_interior_floor(g, c):
			floors[c] = true
	if floors.is_empty():
		return
	var box := BoxMesh.new()
	box.size = Vector3(TILE + 0.02, ROOF_H, TILE + 0.02)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.25, 0.16)   # terracotta — deliberately NOT ground-coloured
	mat.roughness = 0.9
	mat.emission_enabled = true                  # renderer trap: never pitch black
	mat.emission = Color(0.18, 0.08, 0.05)
	mat.emission_energy_multiplier = 0.4
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1),
			Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1)]
	var comps := _components(floors)
	var n4 := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for ci in comps.size():
		var comp: Array = comps[ci]
		var cellset := {}
		var cover := {}
		var wall_count := 0
		for cc in comp:
			var c2: Vector3i = cc
			cellset[c2] = true
			cover[c2] = true
			for d in dirs:
				var nb: Vector3i = c2 + d
				# Cover wall cells AND door openings — otherwise a roof hole gapes
				# above every door (walkable GROUND cell in the wall line).
				if _is_wall(g, nb):
					cover[nb] = true
					wall_count += 1
				elif _is_doorway(g, nb):
					cover[nb] = true
					cellset[nb] = true   # whoever stands IN the door also hides the roof
		# FLOOR areas WITHOUT a wall ring (e.g. the free-standing cellar entrance in
		# the village) are not a building -> no floating mini roof.
		if wall_count == 0:
			continue
		# Inclusions inside the room (crate/barrel cells: kind GROUND with cover>0)
		# belong to the room, otherwise roof holes gape. Criterion: at least 2
		# direct FLOOR neighbours of the same component.
		for cc in comp:
			var c4: Vector3i = cc
			for d in n4:
				var nb2: Vector3i = c4 + d
				if cover.has(nb2) or _is_wall(g, nb2):
					continue
				var cnt := 0
				for d2 in n4:
					if cellset.has(nb2 + d2):
						cnt += 1
				if cnt >= 2:
					cover[nb2] = true
					cellset[nb2] = true
		var xforms := []
		for cc in cover.keys():
			var c3: Vector3i = cc
			var w := g.cell_to_world(c3)
			xforms.append(Transform3D(Basis.IDENTITY,
					Vector3(w.x, w.y + TOP_Y + WALL_H + ROOF_LIFT + ROOF_H * 0.5, w.z)))
		var mmi := _add_mm(g, "Roof_%d" % ci, box, xforms)
		if mmi != null:
			mmi.material_override = mat
			_roofs.append({"node": mmi, "cells": cellset})


## Roof invisible as soon as a merc or a SEEN enemy stands on a FLOOR cell of the
## building. Enemies under an intact roof are not seen anyway (walls block LOS) —
## no gameplay leak, pure optics.
## EXPLORED: once a merc has entered the building (door cell counts too), the roof
## stays hidden PERMANENTLY — the interior (e.g. Vargo's throne room) does not
## disappear behind the roof again as soon as you walk out.
func _update_roofs() -> void:
	if _roofs.is_empty() or not is_inside_tree():
		return
	var units := get_tree().get_nodes_in_group("tac3d_units")
	for r in _roofs:
		if bool(r.get("explored", false)):
			r["node"].visible = false
			continue
		var occupied := false
		var entered := false
		for u in units:
			var alive := true
			if u.get("alive") != null:
				alive = bool(u.get("alive"))
			if not alive:
				continue
			# Demo units (plain Unit3D, no is_merc field) count as mercs.
			var is_merc: bool = u.get("is_merc") == null or bool(u.get("is_merc"))
			var relevant: bool = is_merc or (u.get("seen") != null and bool(u.get("seen")))
			if relevant and r["cells"].has(u.get("cell")):
				occupied = true
				if is_merc:
					entered = true
					break   # merc inside -> explored; searching further is unnecessary
		if entered:
			r["explored"] = true
		r["node"].visible = not occupied


## Camera fade: switch wall groups whose outward face points at the camera to
## transparent. Only really runs through on a camera change (45° yaw steps);
## headless (no camera) the guard makes it a no-op -> smoke test untouched.
func _process(_dt: float) -> void:
	_update_roofs()
	if _wall_mats.is_empty() or not is_inside_tree():
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var f: Vector3 = -cam.global_transform.basis.z
	f.y = 0.0
	if f.length_squared() < 0.0001:
		return
	f = f.normalized()
	if f.distance_to(_last_cam_fwd) < 0.02:
		return
	_last_cam_fwd = f

	for mask in _wall_mats:
		var fade := false
		for bit in _OUT_BITS:
			if (int(mask) & int(bit)) != 0 and _OUT_BITS[bit].dot(f) < -0.3:
				fade = true
				break
		if fade == bool(_wall_faded[mask]):
			continue
		_wall_faded[mask] = fade
		var m: Material = _wall_mats[mask]
		if m is BaseMaterial3D:
			var bm := m as BaseMaterial3D
			if fade:
				bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				bm.albedo_color.a = WALL_FADE_ALPHA
			else:
				bm.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				bm.albedo_color.a = 1.0


# ------------------------------------------------------------- (c) ROCK MESA
func _build_estate_mesa(g: Grid3D) -> void:
	# Cells above level 0 (estate hill) -> a rock box fills the gap y0->level.
	# RAMP cells are left OUT: otherwise the mesa bounding box stretched across the
	# full south front IN FRONT OF the door and ramp — the only ascent was visually
	# bricked up ("building without a door"). _build_ramp_wedges draws the ascent.
	var cellset := {}
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y < 1:
			continue
		var t: Tac3DTile = g.get_tile(c)
		if t != null and t.kind == Tac3DTile.Kind.RAMP:
			continue
		# BRIDGE: no rock block under the deck — it read as a "house in the river".
		# Instead _build_bridge_posts draws wooden posts (a real jetty look).
		if t != null and t.kind == Tac3DTile.Kind.BRIDGE:
			continue
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
		# From the ground (y0) up to just below the level box's bottom edge.
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


# ---------------------------------------------------- (c2) RAMP ASCENTS
## Rock wedge under every RAMP cell: visible ascent from the meadow (level 0) to
## the estate door (level 1). The downward direction is derived from the grid
## (walkable neighbour one level lower = ramp foot). Purely optical — walkability/
## links live unchanged in the grid (Tac3DMapGen.add_link).
func _build_ramp_wedges(g: Grid3D) -> void:
	var holder := Node3D.new()
	holder.name = "RampWedges"
	add_child(holder)
	var rock_mat := _terrain_mat("rock")
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.kind != Tac3DTile.Kind.RAMP or c.y < 1:
			continue
		# Which way does the ramp descend? -> walkable neighbour one level lower.
		var down := Vector3i.ZERO
		for d in [Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0)]:
			var dd: Vector3i = d
			if g.is_walkable(Vector3i(c.x + dd.x, c.y - 1, c.z + dd.z)):
				down = dd
				break
		if down == Vector3i.ZERO:
			continue
		var h := float(c.y) * LEVEL_STEP
		# PrismMesh: left_to_right=0 -> right-angled wedge, vertical side at -x,
		# slope falls towards +x. Yaw turns +x into the actual descent direction.
		var prism := PrismMesh.new()
		prism.left_to_right = 0.0
		prism.size = Vector3(TILE, h, TILE)
		var yaw := 0.0
		if down == Vector3i(-1, 0, 0):
			yaw = PI
		elif down == Vector3i(0, 0, 1):
			yaw = -PI * 0.5
		elif down == Vector3i(0, 0, -1):
			yaw = PI * 0.5
		var mi := MeshInstance3D.new()
		mi.mesh = prism
		mi.material_override = rock_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var w := g.cell_to_world(c)
		mi.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(w.x, TOP_Y + h * 0.5, w.z))
		holder.add_child(mi)


# ------------------------------------------------- (c3) BRIDGE POSTS
## Wooden posts under the corners of the bridge deck. Replaces the old mesa rock
## block under the bridge ("house in the river"). Purely optical; the posts stand
## in the water (non-walkable WATER cells), so they block nothing.
func _build_bridge_posts(g: Grid3D) -> void:
	var cells := {}
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t != null and t.kind == Tac3DTile.Kind.BRIDGE and c.y >= 1:
			cells[c] = true
	if cells.is_empty():
		return
	var wood := _flat(Color(0.30, 0.20, 0.11))
	var post := BoxMesh.new()
	for comp in _components(cells):
		var min_x := 1 << 30
		var max_x := -(1 << 30)
		var min_z := 1 << 30
		var max_z := -(1 << 30)
		var level := 1 << 30
		for cc in comp:
			var c2: Vector3i = cc
			min_x = min(min_x, c2.x)
			max_x = max(max_x, c2.x)
			min_z = min(min_z, c2.z)
			max_z = max(max_z, c2.z)
			level = min(level, c2.y)
		# Deck bottom edge (ground box: centre level*3, height 0.2) down below the water line.
		var top := float(level) * LEVEL_STEP - 0.1
		var bottom := -0.35
		var h := top - bottom
		post.size = Vector3(0.22, h, 0.22)
		var holder := Node3D.new()
		holder.name = "BridgePosts"
		add_child(holder)
		# One post per deck CORNER (slightly inset) + centre posts on the long sides.
		var xs := [float(min_x) + 0.6, float(max_x) + 0.4]
		var zs := [float(min_z) + 0.6, float(max_z) + 0.4]
		var mid_x := (float(min_x) + float(max_x)) * 0.5 + 0.5
		for px in xs:
			for pz in zs:
				_add_post(holder, post, wood, Vector3(px, bottom + h * 0.5, pz))
		for pz2 in zs:
			_add_post(holder, post, wood, Vector3(mid_x, bottom + h * 0.5, pz2))


func _add_post(holder: Node3D, mesh: Mesh, mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	holder.add_child(mi)


# ------------------------------------------------- (c4) CELLAR SHAFT
## Sight-blocking earth walls around the cellar (bounding rectangle of all y<0
## cells), from just below the grass top edge down to the cellar floor. Without
## them you look UNDER the island with the cellar lid opened
## (ground_view.set_cellar_open) — sea/sky show through. With them the hole reads
## as an excavated cellar with earthen walls.
func _build_cellar_pit(g: Grid3D) -> void:
	var has := false
	var x0 := 0.0
	var x1 := 0.0
	var z0 := 0.0
	var z1 := 0.0
	var depth := 0.0
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y >= 0:
			continue
		var w := g.cell_to_world(c)
		depth = minf(depth, w.y)
		if not has:
			has = true
			x0 = w.x - 0.5
			x1 = w.x + 0.5
			z0 = w.z - 0.5
			z1 = w.z + 0.5
		else:
			x0 = minf(x0, w.x - 0.5)
			x1 = maxf(x1, w.x + 0.5)
			z0 = minf(z0, w.z - 0.5)
			z1 = maxf(z1, w.z + 0.5)
	if not has:
		return
	var holder := Node3D.new()
	holder.name = "CellarPit"
	add_child(holder)
	var earth := StandardMaterial3D.new()
	earth.albedo_color = Color(0.24, 0.18, 0.12)   # dark soil
	earth.roughness = 1.0
	earth.emission_enabled = true                  # renderer trap: never pitch black
	earth.emission = Color(0.06, 0.045, 0.03)
	earth.emission_energy_multiplier = 0.5
	const TH := 0.30
	# Top edge just BELOW the lid box (0.10) -> no Z-fighting when closed.
	var top := 0.05
	var bottom := depth - 0.1
	var h := top - bottom
	var cy := bottom + h * 0.5
	# North/south (full width), west/east (between the corners), each INSIDE the hole edge.
	_add_pit_wall(holder, earth, Vector3(x1 - x0, h, TH), Vector3((x0 + x1) * 0.5, cy, z0 + TH * 0.5))
	_add_pit_wall(holder, earth, Vector3(x1 - x0, h, TH), Vector3((x0 + x1) * 0.5, cy, z1 - TH * 0.5))
	_add_pit_wall(holder, earth, Vector3(TH, h, z1 - z0 - TH * 2.0), Vector3(x0 + TH * 0.5, cy, (z0 + z1) * 0.5))
	_add_pit_wall(holder, earth, Vector3(TH, h, z1 - z0 - TH * 2.0), Vector3(x1 - TH * 0.5, cy, (z0 + z1) * 0.5))


func _add_pit_wall(holder: Node3D, mat: Material, size: Vector3, pos: Vector3) -> void:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	holder.add_child(mi)


# --------------------------------------------------------- (d1) BEACH SAND
func _build_sand_band(g: Grid3D) -> void:
	# Thin sand slab just above the grass box on the southern band (purely optical).
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
	# Sort candidates deterministically (dictionary order is unstable).
	var ground := []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.kind != Tac3DTile.Kind.GROUND:
			continue
		if t.cover > 0.0 or c.y != 0:
			continue
		# Keepout (MapGen): spawns/bridge exits/ramp foot stay decoration-free —
		# a palm there would lock units in or block the only crossing.
		if (t.flags & Tac3DTile.FLAG_KEEPOUT) != 0:
			continue
		# Never occupy link cells (bridge/ramp/stair endpoints): the only level
		# transition hangs off them (also applies to the test map without flags).
		if g.has_link(c):
			continue
		# Leave cellar lid cells (room underneath) free — a bush/rock/palm would
		# float in mid-air once the lid is flipped open (set_cellar_open).
		if g.get_tile(Vector3i(c.x, -1, c.z)) != null:
			continue
		ground.append(c)
	ground.sort_custom(func(a, b): return (a.z * 100000 + a.x) < (b.z * 100000 + b.x))
	if ground.is_empty():
		return

	var a3d := _a3d()
	# Palm (T2: normalised via Assets3D) OR primitive fallback palm.
	var palm_mesh: Mesh = null
	var palm_scale := 1.0
	var palm_mat: Material = null
	if a3d != null and a3d.has_method("nature_mesh_raw"):
		palm_mesh = a3d.nature_mesh_raw("palm")
		palm_scale = a3d.nature_normalized_scale("palm")
		palm_mat = a3d.nature_material("palm")

	# Building cells (WALL/FLOOR) for keepout: no palms at/inside buildings.
	var building := {}
	for k in g.all_cells():
		var bc: Vector3i = k
		var bt: Tac3DTile = g.get_tile(bc)
		if bt != null and (bt.kind == Tac3DTile.Kind.WALL or bt.kind == Tac3DTile.Kind.FLOOR):
			building[bc] = true

	var palm_x := []      # Array[Transform3D]
	var palm_cells := []  # palm cells already placed -> minimum distance
	var bush_x := []
	var rock_x := []

	for c in ground:
		# #5: edge inset — no decoration right at the map edge, otherwise trees look
		# "cut off" where they stick out over the ground border into the void/water.
		if c.x < EDGE_INSET or c.x >= g.size_x - EDGE_INSET \
		   or c.z < EDGE_INSET or c.z >= g.size_z - EDGE_INSET:
			continue
		var w := g.cell_to_world(c)
		var base := Vector3(w.x, w.y + TOP_Y, w.z)
		var beach: bool = c.z >= BEACH_Z
		var shore := _is_shore(g, c)
		var r := rng.randf()
		# Palms: FEW, widely scattered. Beach/shore preferred, inland very sparse.
		# Minimum distance (PALM_MIN_DIST) + building keepout prevent the former
		# thicket -> individual palms of varying size instead of a wall of palms.
		var palm_p := PALM_P_INLAND
		if beach:
			palm_p = PALM_P_BEACH
		elif shore:
			palm_p = PALM_P_SHORE
		if r < palm_p and not _near_building(building, c) and _palm_far_enough(palm_cells, c):
			palm_cells.append(c)
			# COLLISION: the palm occupies the cell -> non-walkable in the grid.
			# Deterministic (fixed SEED, independent of assets) -> headless == game.
			# The ground is still drawn (GroundView does not drop GROUND cells).
			var pt: Tac3DTile = g.get_tile(c)
			if pt != null:
				pt.begehbar = false
			var yaw := rng.randf() * TAU   # natural random Y rotation per palm
			# A bit smaller + far more size variation -> individual trees instead of a clone row.
			var s := palm_scale * rng.randf_range(0.55, 0.98)
			var jitter := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
			palm_x.append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), base + jitter))
			continue
		# Not a palm cell -> possibly bush/rock (inland only, not on the bare beach).
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

	# Palm MultiMesh (real mesh) — fallback: individual primitive palms (limited).
	if not palm_x.is_empty():
		if palm_mesh != null:
			var pm := palm_mesh
			if palm_mat != null and pm is ArrayMesh:
				# Ensure a surface material on the raw mesh (OBJ has none).
				var am := pm as ArrayMesh
				if am.get_surface_count() > 0:
					am.surface_set_material(0, palm_mat)
			_add_mm(g, "Palms", pm, palm_x, true)   # palms cast shadows
		elif a3d != null and a3d.has_method("nature_mesh"):
			var holder := Node3D.new()
			holder.name = "PalmsFallback"
			add_child(holder)
			for i in mini(palm_x.size(), 120):
				var node: Node3D = a3d.nature_mesh("palm")
				if node != null:
					node.transform = palm_x[i]
					_enable_shadows(node)   # fallback palm casts a shadow
					holder.add_child(node)

	if not bush_x.is_empty():
		var bush := SphereMesh.new()
		bush.radius = 0.32
		bush.height = 0.6
		bush.radial_segments = 6
		bush.rings = 3
		bush.material = _flat(Color(0.20, 0.44, 0.18))
		_add_mm(g, "Bushes", bush, bush_x, true)   # larger decoration casts shadows

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
	# Avoid duplication: if an orchestrator already places props (demo: PropsRoot),
	# we leave the cover to it. In combat (without PropsRoot) we fill it in.
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
			_enable_shadows(node)   # cover props cast shadows
			holder.add_child(node)
		i += 1


# ---------------------------------------------------------------- (f) DOCK
func _build_dock(g: Grid3D) -> void:
	# Plank dock from the southern shore edge into the water (purely optical).
	var beach := []
	for k in g.all_cells():
		var c: Vector3i = k
		var t: Tac3DTile = g.get_tile(c)
		if t != null and t.kind == Tac3DTile.Kind.GROUND and c.z >= BEACH_Z and c.y == 0:
			beach.append(c)
	if beach.is_empty():
		return
	# Determine median x and maximum z (southernmost row).
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


# --------------------------------------------------------------- Helpers
## Connected components (4 neighbours, same level) over a Vector3i set.
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


## Builds a MultiMeshInstance3D (ordering trap observed) + custom_aabb.
## Returns the instance (null if nothing was built) — the wall fade needs it for
## material_override per group.
func _add_mm(g: Grid3D, node_name: String, mesh: Mesh, xforms: Array, cast_shadow := false,
		colors := []) -> MultiMeshInstance3D:
	if mesh == null or xforms.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var use_colors := not colors.is_empty()
	mm.use_colors = use_colors   # set BEFORE instance_count (buffer layout)
	mm.mesh = mesh
	mm.instance_count = xforms.size()   # LAST
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	# T6: no shadow by default (walls/roofs/sand/dock); palms enable it.
	mmi.cast_shadow = (GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	mmi.custom_aabb = _field_aabb(g)
	add_child(mmi)
	return mmi


## Keep a palm at least PALM_KEEPOUT cells away from every building cell.
func _near_building(building: Dictionary, c: Vector3i) -> bool:
	for dz in range(-PALM_KEEPOUT, PALM_KEEPOUT + 1):
		for dx in range(-PALM_KEEPOUT, PALM_KEEPOUT + 1):
			if building.has(Vector3i(c.x + dx, c.y, c.z + dz)):
				return true
	return false


## True if c is at least PALM_MIN_DIST away from every palm already placed.
func _palm_far_enough(placed: Array, c: Vector3i) -> bool:
	for pc in placed:
		var p: Vector3i = pc
		var dx := c.x - p.x
		var dz := c.z - p.z
		if dx * dx + dz * dz < PALM_MIN_DIST * PALM_MIN_DIST:
			return false
	return true


## Recursively enable shadows for a prop/fallback-palm hierarchy.
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
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # never black without light
	m.roughness = 1.0
	_mat_cache[key] = m
	return m


# ------------------------------------------------- (d3) GROUND DETAIL SCATTER
## Dense, very small grass tufts + pebbles over all ground cells — breaks up the
## emptiness of the grass surface. All MultiMesh with per-instance colour
## (use_colors), deterministic (fixed rng), purely optical, free of primitive
## fallbacks (no asset needed).
func _scatter_ground_detail(g: Grid3D, rng: RandomNumberGenerator) -> void:
	var cells := []
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y != 0:
			continue
		var t: Tac3DTile = g.get_tile(c)
		if t == null or t.kind != Tac3DTile.Kind.GROUND:
			continue
		# Leave cellar lid cells (room directly underneath) free: the grass would
		# otherwise float in mid-air above the flipped-open floor.
		if g.get_tile(Vector3i(c.x, -1, c.z)) != null:
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
		# Grass inland only (not on sand); slight clustering via a 2nd chance.
		if not beach:
			if rng.randf() < GRASS_P:
				_add_tuft(grass_x, grass_c, base, rng)
			if rng.randf() < GRASS_P2:
				_add_tuft(grass_x, grass_c, base, rng)
		# Pebbles everywhere, more frequent on the beach + tinted sandier.
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
	# ART PASS v2: smaller (0.65..1.3 -> 0.55..1.0) + flatter (hy max 1.25 -> 1.05),
	# so the tufts read as ground grass, not as large glowing shards.
	var s := rng.randf_range(0.55, 1.0)                 # small to medium tufts
	var hy := rng.randf_range(0.8, 1.05)               # height variation
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s * hy, s))
	xf.append(Transform3D(b, base + jitter))
	# Colour variation around a grass green; the light end is slightly desaturated/
	# muted (0.48,0.62,0.26 -> 0.40,0.53,0.24), otherwise the saturation boost pulls
	# it into neon lime.
	var col := Color(0.24, 0.42, 0.15).lerp(Color(0.40, 0.53, 0.24), rng.randf())
	cols.append(col)


func _add_pebble(xf: Array, cols: Array, base: Vector3, rng: RandomNumberGenerator, beach: bool) -> void:
	var jitter := Vector3(rng.randf_range(-0.42, 0.42), 0.0, rng.randf_range(-0.42, 0.42))
	var s := rng.randf_range(0.55, 1.5)
	var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * 0.6, s))
	xf.append(Transform3D(b, base + jitter + Vector3(0.0, 0.03, 0.0)))
	var hi := Color(0.72, 0.66, 0.50) if beach else Color(0.58, 0.55, 0.52)
	cols.append(Color(0.40, 0.40, 0.43).lerp(hi, rng.randf()))


## Small grass tuft: 3 crossed triangular blades (double-sided, unshaded).
## Vertex colour = white -> the MultiMesh's per-instance colour determines the tone.
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
		st.add_vertex(Vector3(dx * 0.08, h, dz * 0.08))   # slightly tilted tip
	st.set_material(_vcol_mat())   # surface material -> MultiMesh uses it
	return st.commit()


## Material with per-vertex/instance colour as albedo (for colour-varying MultiMeshes).
func _vcol_mat() -> StandardMaterial3D:
	if _mat_cache.has("vcol"):
		return _mat_cache["vcol"]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED   # blades visible from both sides
	m.roughness = 1.0
	_mat_cache["vcol"] = m
	return m

class_name FogView3D
extends MultiMeshInstance3D
## SPEC §6 — FOG OF WAR. Per-cell HIDDEN / EXPLORED / VISIBLE, rendered as exactly
## ONE MultiMeshInstance3D quad layer with per-instance colours (1 draw call).
##
## Pure presentation. This node holds NO combat state and calls NO combat formula:
## the orchestrator computes the currently visible cell set (Tac3DVision.
## cells_seen_by_units) and hands it over via refresh(). Walkability, LOS, hit
## chances and the enemy set_seen logic are untouched.
##
## LAWS OBSERVED
##   - `fast` (bot/headless): setup() builds NOTHING and refresh() is a no-op, so
##     the smoke bot never pays for a mesh it cannot see. attach() even returns
##     null in fast mode -> the orchestrator's `fog` stays null.
##   - FALLBACK: a missing/empty grid, an empty cell set or a call before setup()
##     are all silently tolerated. Nothing here may ever crash a headless run.
##   - RENDERER gl_compatibility: no Decal, no depth/screen shader. Per-instance
##     colour needs MultiMesh.use_colors = true AND the material's
##     vertex_color_use_as_albedo = true; the material MUST be UNSHADED, otherwise
##     it renders pitch black. Same combination as CursorView3D (proven).
##   - ORDERING TRAP: transform_format + use_colors + mesh FIRST, instance_count LAST.
##
## EXPLORED is STICKY: a cell that was seen once never falls back to HIDDEN.

enum State { HIDDEN = 0, EXPLORED = 1, VISIBLE = 2 }

## Quad height above the cell floor. The ground box is 0.2 high (top edge +0.1),
## the water overlay sits at 0.15, the cursor path at 0.22 -> 0.18 keeps the fog
## above ground AND water, but below the movement path (the path stays readable).
const Y := 0.18

## Slight overlap so neighbouring quads show no hairline seam from float error.
const QUAD_SIZE := 1.02

# TUNED AGAINST A SCREENSHOT, do not "clean up" back to opaque. The squad sees
# roughly 320 of a 72x72 map's 5184 cells, so ~94% of any frame is HIDDEN. At
# alpha 1.0 that swallowed the whole art pass — the Kenney ground textures went
# flat olive and the buildings, whose roofs stick up THROUGH the fog plane, were
# left floating in a dark slab. Semi-transparent instead: unseen ground reads as
# clearly dimmed but still legible, which is also how JA2/XCOM present it.
# Never seen: dark blue-grey (NOT pure black — fog, not a hole in the world).
# Seen before: same tone, lighter, so remembered terrain shows through.
# Currently visible: alpha 0 = invisible.
const COL_HIDDEN := Color(0.035, 0.045, 0.065, 0.72)
const COL_EXPLORED := Color(0.045, 0.055, 0.080, 0.34)
const COL_VISIBLE := Color(0.0, 0.0, 0.0, 0.0)

## Safety cap: a plausible map (72x72 over a handful of levels) stays far below.
const MAX_INSTANCES := 50000

## Bot/headless flag — set BEFORE setup(). True => this node builds nothing at all.
var fast := false

var grid: Grid3D = null

var _state: Dictionary = {}        # Vector3i -> State
var _index: Dictionary = {}        # Vector3i -> int (MultiMesh instance index)
var _visible_now: Dictionary = {}  # Vector3i -> true (the last refresh() set)
var _mat: StandardMaterial3D = null


## Convenience constructor for the orchestrator: builds, attaches and sets up in
## one line. Returns null in fast mode (and on a missing parent/grid) so the
## caller's `fog` member stays null and every call site stays free of charge.
static func attach(parent: Node3D, g: Grid3D, is_fast: bool) -> FogView3D:
	if is_fast or parent == null or g == null:
		return null
	var f := FogView3D.new()
	f.name = "FogView"
	f.fast = is_fast
	parent.add_child(f)
	f.setup(g)
	return f


## Builds the quad layer: one instance per grid cell, everything HIDDEN at first.
## Transforms are written EXACTLY ONCE here — refresh() afterwards only ever
## rewrites instance COLOURS, which keeps the per-movement-step cost tiny.
func setup(g: Grid3D) -> void:
	grid = g
	_state.clear()
	_index.clear()
	_visible_now.clear()
	multimesh = null
	if fast or g == null:
		return

	var cells: Array = g.all_cells()
	if cells.is_empty() or cells.size() > MAX_INSTANCES:
		return

	var quad := PlaneMesh.new()
	# Default orientation lies flat in XZ (same as the water overlay in GroundView3D).
	quad.size = Vector2(QUAD_SIZE, QUAD_SIZE)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # or it renders black
	_mat.vertex_color_use_as_albedo = true                     # per-instance colour
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA      # alpha comes from the instance colour
	_mat.albedo_color = Color(1, 1, 1, 1)                      # white -> the instance colour passes through
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED              # visible from below too (cellar)
	quad.material = _mat

	# ORDERING TRAP: transform_format + use_colors + mesh FIRST, instance_count LAST.
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = cells.size()

	for i in cells.size():
		var c: Vector3i = cells[i]
		_index[c] = i
		_state[c] = State.HIDDEN
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY,
				g.cell_to_world(c) + Vector3(0.0, Y, 0.0)))
		mm.set_instance_color(i, COL_HIDDEN)

	multimesh = mm
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A MultiMesh is not auto-culled -> generous AABB (project idiom).
	var b := g.bounds_world()
	var pad := Vector3(4.0, 8.0, 4.0)
	custom_aabb = AABB(b.position - pad, b.size + pad * 2.0)


## THE public update API. `visible_cells` is a SET (Vector3i -> true) of the cells
## the player's team can see right now — hand in Tac3DVision.cells_seen_by_units(mercs).
## Cells that just dropped out of sight become EXPLORED (sticky, never HIDDEN again).
## Only cells whose state actually CHANGED are rewritten.
## Safe to call before setup(), in fast mode, or with an empty dictionary.
func refresh(visible_cells: Dictionary) -> void:
	if fast or multimesh == null:
		return
	# 1) Everything that was visible and no longer is falls back to EXPLORED.
	for k in _visible_now:
		var c: Vector3i = k
		if not visible_cells.has(c):
			_set_state(c, State.EXPLORED)
	# 2) The current sight set becomes VISIBLE.
	for k2 in visible_cells:
		var c2: Vector3i = k2
		_set_state(c2, State.VISIBLE)
	# duplicate(): the caller stays free to reuse or clear its own dictionary.
	_visible_now = visible_cells.duplicate()


## Everything back to HIDDEN, memory wiped (new sector / new game). Keeps the
## already-built instance layer — only the colours are reset.
func reset_fog() -> void:
	_visible_now.clear()
	if fast or multimesh == null:
		return
	# keys() = snapshot: _set_state writes back into _state while we iterate.
	for k in _state.keys():
		var c: Vector3i = k
		_set_state(c, State.HIDDEN)


## Current state of a cell. Unknown cells count as HIDDEN.
func state_of(c: Vector3i) -> int:
	return int(_state.get(c, State.HIDDEN))


## True once the cell has EVER been seen (EXPLORED or VISIBLE) — for a minimap
## or "already discovered" checks.
func is_explored(c: Vector3i) -> bool:
	return state_of(c) != State.HIDDEN


## True while the cell is in the team's field of view right now.
## NOTE: deliberately NOT called is_visible() — Node3D already owns that name.
func is_visible_cell(c: Vector3i) -> bool:
	return state_of(c) == State.VISIBLE


# ---------------------------------------------------------------- internals

## Writes one cell's state + its instance colour. No-op when nothing changed or
## when the cell is not part of the built layer (defensive: cells outside the grid).
func _set_state(c: Vector3i, s: int) -> void:
	var cur: int = int(_state.get(c, -1))
	if cur < 0 or cur == s:
		return
	_state[c] = s
	var i: int = int(_index.get(c, -1))
	if i < 0 or i >= multimesh.instance_count:
		return
	multimesh.set_instance_color(i, _color_for(s))


## if/else instead of match: guarantees to the parser that every path returns.
func _color_for(s: int) -> Color:
	if s == State.VISIBLE:
		return COL_VISIBLE
	if s == State.EXPLORED:
		return COL_EXPLORED
	return COL_HIDDEN

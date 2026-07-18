# BAUVERTRAG — PHASE 1: 3D-Fundament + Brücken/Wasser/Höhen-Beweis (Godot 4.6, GDScript)

> Dies ist die **eingefrorene, verbindliche** Schnittstelle. Jede Datei hält EXAKT diese Signaturen ein, sonst bricht die Integration. Projekt-Wurzel: `c:/Users/User/Desktop/ja2_remasted`. Godot 4.6.3, `gl_compatibility`, GDScript ohne Addons.

## 0. Scope-Entscheidung (bindend)
Phase 1 ist **rein additiv**: neuer Ordner `scripts/tac3d/`, neuer CLI-Modus `--tac3d`, neuer Screen `"tactical3d"`. **KEIN** Eingriff in `tactical.gd`, `battle_unit.gd`, `mapgen.gd`, `db.gd`, `game.gd`, `assets.gd`, `sfx.gd` oder den bestehenden `--smoke`/`--contact`-Pfad. Die v2-`--smoke` MUSS unverändert grün bleiben (die v2-Taktik nutzt `AStarGrid2D` — komplett andere Klasse als unser `AStar3D`, keine Kollision).
Phase 1 beweist bereits **Gehen, Schwimmen (unter der Brücke durch), Brücke (oben drüber), Höhe/Podest** — bewusst vorgezogen, weil die Brücke der Grund für den 3D-Umzug ist.

## 1. Neue Dateien (absolute Pfade)
```
scripts/tac3d/tac3d_tile.gd    class_name Tac3DTile   extends RefCounted
scripts/tac3d/grid3d.gd        class_name Grid3D      extends RefCounted
scripts/tac3d/pathfinder3d.gd  class_name Pathfinder3D extends RefCounted
scripts/tac3d/testmap3d.gd     class_name TestMap3D   extends RefCounted
scripts/tac3d/camera_rig.gd    class_name CameraRig3D extends Node3D
scripts/tac3d/ground_view.gd   class_name GroundView3D extends MultiMeshInstance3D
scripts/tac3d/picker3d.gd      class_name Picker3D    extends RefCounted
scripts/tac3d/unit3d.gd        class_name Unit3D      extends Node3D
scripts/tac3d/tactical3d.gd    (KEIN class_name)      extends Node3D
```
Zu ändern (nur additiv): `scripts/main.gd`.

**FALLE (kritisch):** `class_name TileData` KOLLIDIERT mit Godots eingebauter `TileData` → Parse-Fehler. Deshalb `Tac3DTile`. Niemals `Camera3D`/`AStar3D` etc. als class_name.

## 2. `tac3d_tile.gd` — Tac3DTile (RefCounted)
```
enum Kind { GROUND, FLOOR, ROOF, WATER_SHALLOW, WATER_DEEP, BRIDGE, RAMP, WALL, VOID }
enum Move { WALK, WADE, SWIM, CLIMB }

var kind: Kind = Kind.GROUND
var ebene: int = 0
var begehbar: bool = true
var move_type: Move = Move.WALK
var cover: float = 0.0
var blocks_sight: bool = false
var surface: int = 0        # 0 Gras, 1 Holz, 2 Stein, 3 Wasser
var weight: float = 1.0     # AStar weight_scale
var flags: int = 0
const FLAG_DESTRUCT := 1
const FLAG_SPAWN := 2
const FLAG_GOAL := 4

static func make(k: Kind, ebene: int) -> Tac3DTile   # Defaults je Kind laut Tabelle unten
func kind_name() -> String
func is_water() -> bool      # kind in {WATER_SHALLOW, WATER_DEEP}
```
Defaults je Kind (in `make`):
| Kind | begehbar | move_type | blocks_sight | cover | surface | weight |
|---|---|---|---|---|---|---|
| GROUND | true | WALK | false | 0.0 | 0 | 1.0 |
| FLOOR | true | WALK | false | 0.0 | 1 | 1.0 |
| ROOF | true | WALK | false | 0.0 | 2 | 1.0 |
| WATER_SHALLOW | true | WADE | false | 0.0 | 3 | 4.0 |
| WATER_DEEP | true | SWIM | false | 0.0 | 3 | 10.0 |
| BRIDGE | true | WALK | false | 0.0 | 1 | 1.0 |
| RAMP | true | CLIMB | false | 0.0 | 0 | 1.5 |
| WALL | false | WALK | true | 0.0 | 0 | 1.0 |
| VOID | false | WALK | false | 0.0 | 0 | 1.0 |

## 3. `grid3d.gd` — Grid3D (RefCounted) — DIE WAHRHEIT
```
const TILE_SIZE := 1.0
const LEVEL_STEP := 3.0     # Meter je Höhenebene NUR fürs Rendering (cell_to_world)

var tiles: Dictionary = {}  # Vector3i -> Tac3DTile
var size_x: int = 0
var size_z: int = 0
var min_level: int = 0
var max_level: int = 0
var _links: Dictionary = {} # Vector3i -> Array (symmetrische Ebenen-Übergänge)

func set_tile(c: Vector3i, t: Tac3DTile) -> void   # aktualisiert size_x/size_z/min_level/max_level
func get_tile(c: Vector3i) -> Tac3DTile            # null wenn nicht vorhanden
func has_tile(c: Vector3i) -> bool
func is_walkable(c: Vector3i) -> bool              # has_tile(c) and get_tile(c).begehbar
func add_link(a: Vector3i, b: Vector3i) -> void    # trägt b in _links[a] UND a in _links[b] ein (symmetrisch, dedupe)
func neighbors(c: Vector3i) -> Array               # Array[Vector3i]: begehbare 4-Nachbarn GLEICHER ebene + begehbare _links[c]
func all_cells() -> Array                          # tiles.keys()
func cell_to_world(c: Vector3i) -> Vector3         # Vector3((c.x+0.5)*TILE_SIZE, c.y*LEVEL_STEP, (c.z+0.5)*TILE_SIZE)  RENDER
func world_to_cell(p: Vector3, ebene: int) -> Vector3i  # Vector3i(floori(p.x/TILE_SIZE), ebene, floori(p.z/TILE_SIZE))  floori, NICHT int()!
func bounds_world() -> AABB                        # umfasst alle Zellen inkl. ebenen (für Kamera-Clamp)
```
`neighbors()`: die 4 orthogonalen Nachbarn (±x, ±z) MIT gleicher `ebene` (c.y), sofern `is_walkable`, PLUS alle `is_walkable`-Zellen aus `_links.get(c, [])`. KEINE Diagonalen. Wasser (ebene 0) und Brückendeck (ebene 1) an gleicher XZ sind nie automatisch verbunden — nur `add_link` koppelt Ebenen.
Null-Guard (Fix S8): niemals `get_tile(c).x` ohne vorherigen `has_tile`/`is_walkable`.

## 4. `pathfinder3d.gd` — Pathfinder3D (RefCounted) — AStar3D-Wrapper
```
var astar := AStar3D.new()          # MUSS public bleiben (Harness ruft are_points_connected)
var grid: Grid3D
var _id_of: Dictionary = {}         # Vector3i -> int
var _cell_of: Dictionary = {}       # int -> Vector3i

func build(g: Grid3D) -> void
func has_point(c: Vector3i) -> bool
func point_id(c: Vector3i) -> int   # -1 wenn kein Punkt
func path_cells(from: Vector3i, to: Vector3i) -> Array   # Array[Vector3i]; leer wenn kein Pfad
func path_world(from: Vector3i, to: Vector3i) -> Array   # Array[Vector3] (grid.cell_to_world je Zelle) für Unit3D
func reachable(from: Vector3i, to: Vector3i) -> bool
func path_cost(from: Vector3i, to: Vector3i) -> float
func set_cell_blocked(c: Vector3i, blocked: bool) -> void          # astar.set_point_disabled(id, blocked)
func set_move_type_enabled(mt: Tac3DTile.Move, enabled: bool) -> void  # alle Zellen mit tile.move_type==mt: set_point_disabled(id, not enabled)
```
**KOSTENMETRIK (Fix S9, wichtig):** Die AStar-Punktposition ist FLACH, NICHT die Renderhöhe:
`astar.add_point(id, Vector3(c.x + 0.5, 0.0, c.z + 0.5), tile.weight)`  — y IMMER 0.
So kostet jeder Schritt (auch Ebenenwechsel per Link) ~1 Distanz-Einheit → keine AP-Verzerrung durch LEVEL_STEP. Zwei Zellen gleicher XZ / verschiedener Ebene bekommen dieselbe Position, aber **verschiedene IDs** und werden NICHT verbunden → das ist gültig und korrekt (der Brücken-drüber/drunter-Beweis hängt an fehlenden Kanten, nicht an Positionen).
`build`: für jede begehbare Zelle add_point (ID fortlaufend via _id_of/_cell_of). Dann für jede Zelle `connect_points(id, nid, true)` zu jedem `nid` aus `grid.neighbors(c)` (bidirektional, doppelte Kanten sind idempotent/harmlos — aber gerne dedupen). `path_cost` via Summe oder `astar.get_point_path`-Länge; einfachste Variante: eigene Distanzsumme entlang path_cells × weight, ODER nutze reachable = not path_cells().is_empty().

## 5. `testmap3d.gd` — TestMap3D (RefCounted)
```
static func build() -> Dictionary
```
Feld x=0..15 (16 breit), z=0..11 (12 tief). Ebene 0 komplett; Ebene 1 dünn.
**Ebene 0**, jede Reihe z=0..11 identisch, x=0..15:
`G G G G G G G s d G G G G G G G`  → x0..6 = GROUND, x7 = WATER_SHALLOW, x8 = WATER_DEEP, x9..15 = GROUND.
**Ebene 1** (nur diese Zellen anlegen):
- BRIDGE-Deck: (6,1,5),(7,1,5),(8,1,5),(9,1,5)
- ROOF-Podest: (13,1,3),(13,1,4),(14,1,3),(14,1,4)
**Links (add_link, symmetrisch):**
- (6,1,5) <-> (5,0,5)   (Brücke West aufs Westufer)
- (9,1,5) <-> (10,0,5)  (Brücke Ost aufs Ostufer)
- (13,1,4) <-> (12,0,4) (Podest-Rampe vom Ostufer)
**Rückgabe-Dictionary (exakte Keys):**
```
"grid": Grid3D,
"start": Vector3i(1,0,5),
"goal": Vector3i(13,1,3),
"spawn": Vector3i(1,0,5),
"deep_under_deck": Vector3i(8,0,5),
"deck_over_deep": Vector3i(8,1,5),
"swim_from": Vector3i(6,0,5),
"swim_to": Vector3i(9,0,5),
"west_probe": Vector3i(1,0,5),
"east_probe": Vector3i(13,0,3),
"bridge_cells": [Vector3i(6,1,5),Vector3i(7,1,5),Vector3i(8,1,5),Vector3i(9,1,5)],
"podium_cells": [Vector3i(13,1,3),Vector3i(13,1,4),Vector3i(14,1,3),Vector3i(14,1,4)]
```

## 6. `camera_rig.gd` — CameraRig3D (Node3D = PIVOT/Yaw)
```
var tilt: Node3D
var cam: Camera3D
var yaw_deg := 45.0
var pitch_deg := -30.0
var zoom_size := 24.0
const ZOOM_MIN := 8.0
const ZOOM_MAX := 60.0
var field: AABB

func setup(field_bounds: AABB) -> void   # baut Tilt (child) + Camera3D (child von Tilt).
#   self.rotation.y = deg_to_rad(yaw_deg); tilt.rotation.x = deg_to_rad(pitch_deg)
#   cam.projection = Camera3D.PROJECTION_ORTHOGONAL; cam.size = zoom_size; cam.near = 0.05; cam.far = 1000.0
#   cam.position = Vector3(0, 0, 200)   # (Fix M5) Offset entlang Tilt-Achse < far, sonst Near-Clipping
#   cam.current = true
#   position = field_bounds.get_center()  (Pivot ins Feldzentrum), y auf min_level-Ebene
func rotate_step(dir: int) -> void       # yaw ± 45° per Tween (weich)
func zoom_by(factor: float) -> void      # cam.size = clamp(cam.size*factor, ZOOM_MIN, ZOOM_MAX)
func set_zoom(size: float) -> void
func pan(delta_xz: Vector2) -> void      # Pivot in Yaw-rotierter Basis verschieben, dann _clamp_to_field()
func focus_world(p: Vector3) -> void     # position = p (x/z geklammert)
func _clamp_to_field() -> void           # position.x/z hart in field-Grenzen (nie aus der Karte)
```

## 7. `ground_view.gd` — GroundView3D (MultiMeshInstance3D)
```
func build(g: Grid3D) -> void
```
1 MultiMesh, je BEGEHBARER Zelle eine Box-Instanz (BoxMesh 1.0 x 0.2 x 1.0) an `g.cell_to_world(c)`.
**Reihenfolge-FALLE (Fix S7-Render):** zuerst `var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.use_colors = true; mm.mesh = box`, DANN `mm.instance_count = n`, DANN in Schleife `set_instance_transform` + `set_instance_color`. Material: `StandardMaterial3D` mit `vertex_color_use_as_albedo = true` (sonst Farben unsichtbar), am BoxMesh ODER als material_override. `custom_aabb` großzügig setzen (MultiMesh wird nicht auto-gecullt).
Farben je Kind: GROUND=grün, WATER_SHALLOW=hellblau, WATER_DEEP=dunkelblau, BRIDGE=braun, ROOF=grau, RAMP=sandfarben, WALL=dunkelgrau.

## 8. `picker3d.gd` — Picker3D (RefCounted)
```
const NONE := Vector3i(-999,-999,-999)
var grid: Grid3D
var cam: Camera3D
var active_level := 0
func set_active_level(l: int) -> void
func cell_under_mouse(vp: Viewport) -> Vector3i
#   from = cam.project_ray_origin(vp.get_mouse_position()); dir = cam.project_ray_normal(...)
#   plane = Plane(Vector3.UP, active_level * Grid3D.LEVEL_STEP); hit = plane.intersects_ray(from, dir)
#   if hit == null: return NONE ; c = grid.world_to_cell(hit, active_level); return c if grid.has_tile(c) else NONE
```
Bekannte Grenze (Fix S7): löst nur die AKTIVE Ebene auf (manueller Ebenen-Umschalter). Akzeptiert für Phase 1.

## 9. `unit3d.gd` — Unit3D (Node3D)
```
signal move_finished
var grid: Grid3D
var cell := Vector3i.ZERO
var moving := false
var fast := false            # true = sofort snappen (Headless), kein Tween
func setup(g: Grid3D, start: Vector3i) -> void   # CapsuleMesh-Kind (MeshInstance3D) bauen, set_cell(start)
func set_cell(c: Vector3i) -> void               # cell = c; position = grid.cell_to_world(c) + Vector3(0, 0.5, 0)
func follow_path(world_points: Array) -> void    # fast: position = last, cell aus letztem Punkt; sonst Tween über Punkte; am Ende move_finished.emit
```
Hinweis (Fix M6): `Unit3D` ist KEIN PhysicsBody3D → eine `Area3D.body_entered`-Schwimmerkennung würde nie feuern. Schwimmen wird in Phase 1 AUSSCHLIESSLICH über die Pathfinder-move_type-Logik entschieden, nicht über Area-Trigger. Kein WaterArea nötig.

## 10. `tactical3d.gd` — Orchestrator-Screen (extends Node3D, KEIN class_name)
```
signal map_ready
var grid: Grid3D
var pathfinder: Pathfinder3D
var rig: CameraRig3D
var ground: GroundView3D
var picker: Picker3D
var unit: Unit3D
var meta: Dictionary
var fast := false

func _main() -> Node: return get_parent()        # (Fix M4)
func _ready() -> void
func find_demo_path() -> Array                    # (Fix M3) SWIM intern aus, path_cells(start,goal), SWIM zurück, Array[Vector3i]
func move_unit_along(cells: Array) -> void        # fast: unit.set_cell(cells.back()); sonst unit.follow_path(cell->world)
func active_level() -> int
func set_active_level(l: int) -> void             # picker.set_active_level(l); HUD-Label
func _unhandled_input(ev) -> void                 # Q/E rotate_step, Mausrad zoom_by, PageUp/Down Ebene, Linksklick: picker->path->follow
func _process(dt) -> void                         # WASD-Pan des Rigs
```
**`_ready()`-Ablauf (bindend, mit Fix K2 — Container ZUERST erzeugen):**
1. `fast = (_main().get("fast") == true)`
2. **Schritt 0 (Container):** erzeuge und `add_child` mit Namen: `CameraRig`(=rig, CameraRig3D.new()), `WorldRoot`(Node3D), darunter `GroundView`, `WaterRoot`(optional, nur WaterSurface-PlaneMesh als Deko), `PropsRoot`(Node3D), `UnitsRoot`(Node3D), `Hud`(CanvasLayer) mit `HudRoot`(Control) + Ebenen-Label. NIEMALS in einen noch nicht existierenden Node hängen.
3. `meta = TestMap3D.build(); grid = meta["grid"]`
4. `pathfinder = Pathfinder3D.new(); pathfinder.build(grid)`
5. `ground = GroundView3D.new(); WorldRoot.add_child(ground); ground.build(grid)`
6. `rig.setup(grid.bounds_world()); rig.focus_world(grid.cell_to_world(meta["start"]))`
7. `picker = Picker3D.new(); picker.grid = grid; picker.cam = rig.cam`
8. `unit = Unit3D.new(); unit.fast = fast; UnitsRoot.add_child(unit); unit.setup(grid, meta["start"])`
9. `map_ready.emit.call_deferred()`   # (Fix: deferred, weil Harness nach add_child await'et)
`find_demo_path()` MUSS `pathfinder.set_move_type_enabled(Tac3DTile.Move.SWIM, false)` setzen, `path_cells(meta["start"], meta["goal"])` holen, dann `set_move_type_enabled(SWIM, true)` zurücksetzen, und den Pfad zurückgeben.

## 11. `main.gd` — additive Änderungen (NUR diese; nichts anderes anfassen)
1. `SCREENS`-Dictionary um Eintrag ergänzen: `"tactical3d": "res://scripts/tac3d/tactical3d.gd"`.
2. In `_ready()`, im CLI-Dispatch VOR `goto("title")`, neuen Zweig: `if "--tac3d" in args: fast = true; await _tac3d_probe(); return`. Den bestehenden `--smoke`/`--shots`/`--contact`-Code NICHT verändern.
3. Neue Funktion `_tac3d_probe()` (async) = Verifikations-Harness (§12). Muster wie `_smoke()`/`_fail()`: Fehlerzähler, `push_error`, am Ende `get_tree().quit(0 if fails==0 else 1)` und `print("TAC3D OK")` bzw. `print("TAC3D FAIL (%d)" % fails)`.

## 12. Verifikation `--tac3d` (Assertions)
Aufruf: `godot --headless --path . -- --tac3d` endet mit `TAC3D OK` / Exit 0 oder `TAC3D FAIL (n)` / Exit 1.
**Block A — reine Logik (Fix S10: pro Gruppe FRISCHEN Pathfinder3D bauen):**
- A1: `g` hat Kacheln auf Ebene 0 UND Ebene 1; alle 4 `bridge_cells` + 4 `podium_cells` existieren und sind begehbar.
- A2: frischer pf; `pf.set_move_type_enabled(SWIM,false)`; alle `bridge_cells` `set_cell_blocked(true)` → `pf.reachable(west_probe,east_probe) == false`.
- A3: jede `bridge_cells`-Zelle: `get_tile(c).kind == BRIDGE` und `c.y == 1`.
- A4: frischer pf; `pf.point_id(deep_under_deck) >= 0` und `pf.point_id(deck_over_deep) >= 0`; IDs verschieden; `g.cell_to_world(deep_under_deck).y != g.cell_to_world(deck_over_deep).y`; `pf.astar.are_points_connected(id_deep, id_deck) == false`.
- A5: frischer pf; `pf.set_move_type_enabled(SWIM,false)`; `p = pf.path_cells(start,goal)`; `not p.is_empty()`; `p.front()==start`; `p.back()==goal`; EXISTIERT `c in p` mit `get_tile(c).kind==BRIDGE`.
- A6: frischer pf; `p2 = pf.path_cells(swim_from,swim_to)`; `not p2.is_empty()`; EXISTIERT `c in p2` mit `get_tile(c).kind==WATER_DEEP`.
- A7: frischer pf; `pf.reachable(Vector3i(1,0,5), Vector3i(5,0,5)) == true`.
- A8: frischer pf; `pf.reachable(start,goal) == true`.
**Block B — Szene öffnet + Unit fährt Pfad:**
- `goto("tactical3d"); tac = current; await tac.map_ready`
- B1: `await` kehrt zurück (Szene ohne Skriptfehler geöffnet).
- B2: `tac.unit != null` und `tac.unit.cell == meta["start"]`.
- B3: `cells = tac.find_demo_path()`; `not cells.is_empty()`; `cells.back() == meta["goal"]`; (Fix M3) EXISTIERT `c in cells` mit `tac.grid.get_tile(c).kind == BRIDGE`.
- B4: `tac.move_unit_along(cells)`; danach `tac.unit.cell == meta["goal"]`.
- B5: `tac.rig.cam.projection == Camera3D.PROJECTION_ORTHOGONAL`.

## 13. GDScript-Fallen (alle beachten)
1. `class_name TileData` verboten → `Tac3DTile`.
2. `var x := expr` bei untypisiertem Variant (Dictionary/Array-Iteration): explizit typisieren, z.B. `for id in ids: var cell: Vector3i = _cell_of[id]`; `for n in grid.neighbors(c): var nn: Vector3i = n`.
3. Signal synchron in `_ready()` nach `add_child`: IMMER `map_ready.emit.call_deferred()`.
4. `floori()` statt `int()` in world_to_cell.
5. Ortho-Kamera: `cam.size` ist der Zoom (nicht FOV); `cam.current = true`; `cam.far >= 1000`, `cam.position`-Offset entlang -z < far.
6. MultiMesh: `transform_format` + `use_colors` VOR `instance_count`; `vertex_color_use_as_albedo = true`.
7. AStar3D: IDs sind ints (Vector3i untauglich → _id_of/_cell_of); `connect_points` default bidirektional; `get_point_path` = Welt-PackedVector3Array, `get_id_path` = IDs. `weight_scale` beim add_point setzen.
8. Node3D unter Control-Root: ok; Maus via `get_viewport().get_mouse_position()`.
9. Vector3i (nicht Vector3) als Dict-Key; Lookups immer über world_to_cell → Vector3i.
10. Null-Guard: `get_tile()` kann null sein — immer `has_tile`/`is_walkable` davor.

## 14. Bau-Reihenfolge (Wellen)
- Welle A (parallel): `tac3d_tile.gd`, `camera_rig.gd`
- Welle B: `grid3d.gd` (liest tac3d_tile.gd)
- Welle C (parallel): `pathfinder3d.gd`, `testmap3d.gd`, `ground_view.gd`, `picker3d.gd`, `unit3d.gd` (lesen grid3d.gd + tac3d_tile.gd)
- Welle D: `tactical3d.gd` (liest alle)
- Welle E: `main.gd`-Hook + `_tac3d_probe()`
- Welle F: Verifikation mit echtem Godot (Fix-Schleife) + `--smoke`-Regression.

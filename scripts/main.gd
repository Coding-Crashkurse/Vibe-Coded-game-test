extends Control
## Main — screen router (root Control, fills the window automatically) AND the
## entry point of the whole test harness (SPEC v5 §8).
##
## HEADLESS MODES (exit 0 = pass, 1 = fail):
##   --smoke     §8.9 umbrella run: language gate, voice coverage, map reachability
##               incl. the level-0 <-> level-(-1) stair link, hire, loot, the full
##               F4 -> F3 -> rescue -> end-card loop, save roundtrip, screen smoke.
##   --loop      §8.2 full-loop check only (F4 -> F3 -> rescue -> base -> end card).
##   --lang      §8.1 language gate only (German player-facing strings).
##   --tac3d     3D foundation      --smoke3d  combat bot to victory
##   --hud3d     HUD interaction    --demo3d   demo content
##   --menu      main menu + save slots (incl. damaged/incompatible files)
##   --map       Ashveil sector map  --sector3d  two-sector demo (F4/F3)
##
## WINDOWED SCREENSHOT MODES (need a display — never headless):
##   --tac3d-shots= --hud3d-shots= --juice-shots= --demo3d-shots= --estate-shots=
##   --menu-shots= --map-shots= --hire-shots= --gallery-shots= --hideout-shots=
##
## HANG LAW: an unknown "--*" argument used to fall through to the title screen and
## block forever in a headless run. It now fails fast with exit 1 (see _ready).

var current: Node = null
var fast := false

## Every accepted bare flag. An argument starting with "--" that is neither in
## here nor a prefix of VALID_PREFIXES is a typo and aborts the process (see
## _reject_unknown_args) instead of silently opening the title screen.
const VALID_FLAGS := [
	"--smoke", "--loop", "--lang",
	"--tac3d", "--smoke3d", "--hud3d", "--demo3d",
	"--menu", "--map", "--sector3d",
]

## Accepted "--<name>=<value>" argument prefixes (all screenshot modes).
const VALID_PREFIXES := [
	"--tac3d-shots=", "--hud3d-shots=", "--juice-shots=", "--demo3d-shots=",
	"--estate-shots=", "--menu-shots=", "--map-shots=", "--hire-shots=",
	"--gallery-shots=", "--hideout-shots=", "--boot-shots=",
]
## SPEC v5 §2: Startsektor des naechsten Gefechts. "" = Orchestrator-Default (F3),
## das echte Spiel setzt "F4" (Landezone) im loading-Screen. Alle Headless-Testmodi
## lassen den Wert leer und starten daher unveraendert in F3.
var start_sector := ""
## SPEC v5 §4.3: Modus des Unterschlupf-Raums fuer den naechsten goto("hideout").
## "" or "menu" = main-menu mode, "base" = home base (the bed heals, the crates are
## the stash, the door leads back to the map). Same pattern as start_sector: it MUST
## be set BEFORE goto(), because goto() calls add_child() and thus _ready() synchronously.
var hideout_mode := ""

const SCREENS := {
	"title": "res://scripts/screens/title.gd",
	"difficulty": "res://scripts/screens/difficulty.gd",
	"hire": "res://scripts/screens/hire.gd",
	"load_game": "res://scripts/screens/load_game.gd",
	"island": "res://scripts/screens/island.gd",
	"loading": "res://scripts/screens/loading.gd",
	"tactical3d": "res://scripts/tac3d/tactical3d.gd",
	"tactical3d_combat": "res://scripts/tac3d/combat/tactical3d_combat.gd",
	"end": "res://scripts/screens/end_screen.gd",
	# SPEC v5 §4.1 step 5 — model/uniform/animation review of every merc.
	"unit_gallery": "res://scripts/screens/unit_gallery.gd",
	"hideout": "res://scripts/menu/hideout.gd",
}

func _ready() -> void:
	get_window().min_size = Vector2i(1152, 648)
	RenderingServer.set_default_clear_color(Color("18120a"))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var args := OS.get_cmdline_user_args()
	# HANG LAW (§8.9): validate BEFORE dispatching. A typo must never reach
	# goto("title") — headless there is an endless run, the worst outcome.
	if _reject_unknown_args(args):
		return
	for a in args:
		if a.begins_with("--tac3d-shots="):
			_tac3d_shots(a.substr(14))
			return
		if a.begins_with("--hud3d-shots="):
			await _hud3d_shots(a.substr(14))
			return
		if a.begins_with("--juice-shots="):
			await _juice_shots(a.substr(14))
			return
		if a.begins_with("--demo3d-shots="):
			await _demo3d_shots(a.substr(15))
			return
		if a.begins_with("--estate-shots="):
			await _estate_shots(a.substr(15))
			return
		if a.begins_with("--menu-shots="):
			await _menu_shots(a.substr(13))
			return
		if a.begins_with("--map-shots="):
			await _map_shots(a.substr(12))
			return
		if a.begins_with("--hire-shots="):
			await _hire_shots(a.substr(13))
			return
		if a.begins_with("--gallery-shots="):
			await _gallery_shots(a.substr(16))
			return
		if a.begins_with("--hideout-shots="):
			await _hideout_shots(a.substr(16))
			return
	if "--tac3d" in args:
		fast = true
		await _tac3d_probe()
		return
	if "--smoke3d" in args:
		fast = true
		await _smoke3d()
		return
	if "--demo3d" in args:
		fast = true
		await _demo3d()
		return
	if "--hud3d" in args:   # OHNE fast=true -> HUD/Cursor werden gebaut (Interaktionstest)
		await _hud3d()
		return
	if "--menu" in args:    # Hauptmenue + Speicherstaende
		await _menu_probe()
		return
	if "--map" in args:     # Ashveil sector map (SPEC v4.1 §1)
		await _map_probe()
		return
	if "--sector3d" in args:   # two-sector demo F4 -> F3 (SPEC v5 §2)
		fast = true
		_sector3d()
		return
	if "--smoke" in args:      # §8.9 umbrella run
		fast = true
		await _smoke()
		return
	if "--loop" in args:       # §8.2 full loop F4 -> F3 -> rescue -> end card
		fast = true
		await _loop_probe()
		return
	if "--lang" in args:       # §8.1 language gate
		_lang_probe()
		return
	# SPEC v5 §4.3: with the flag set the walkable Hideout IS the main menu;
	# otherwise the painted 2D menu boots as usual. The flag is DELIBERATELY false
	# (see game.gd) — the room is the in-game home base, not the entry point.
	# Switched here only, never in title.gd: every test mode and every "Back" path
	# calls goto("title") directly and must keep working either way.
	if Game.USE_HIDEOUT_MENU:
		hideout_mode = "menu"
		goto("hideout")
	else:
		goto("title")
	# --boot-shots=<dir>: belegt den ECHTEN Startweg (kein goto von aussen) und
	# schiesst danach ein Bild. Bewusst NACH dem reg. Boot, nicht als Frueh-Return.
	for a2 in args:
		if a2.begins_with("--boot-shots="):
			await _boot_shots(a2.substr(13))
			return


## HANG-PROOFING (§8.9). Returns true when the process was aborted. Anything that
## looks like a flag but is not a known mode is a typo — and a typo that falls
## through to the title screen HANGS a headless run forever. So: name the offender,
## print every valid mode, exit 1.
func _reject_unknown_args(args: PackedStringArray) -> bool:
	var bad: Array = []
	for a in args:
		var arg := String(a)
		if not arg.begins_with("--"):
			continue          # positional arguments stay ignored, as before
		if arg in VALID_FLAGS:
			continue
		var matched := false
		for p in VALID_PREFIXES:
			if arg.begins_with(String(p)):
				matched = true
				break
		if not matched:
			bad.append(arg)
	if bad.is_empty():
		return false
	for b in bad:
		push_error("ARGS: unknown mode '%s'" % String(b))
		print("ARGS: unknown mode '%s'" % String(b))
	print("ARGS: valid modes are:")
	for f in VALID_FLAGS:
		print("  ", String(f))
	for p in VALID_PREFIXES:
		print("  ", String(p), "<absolute directory>")
	print("ARGS FAIL (%d)" % bad.size())
	get_tree().quit(1)
	return true

func goto(screen: String) -> void:
	if current != null:
		current.queue_free()
		current = null
	var s: Script = load(SCREENS[screen])
	var node: Node = s.new()
	node.name = "Screen_" + screen
	current = node
	add_child(node)

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_M:
		Sfx.toggle_mute()

# ============================================================ 3D-Taktik-Sonde (Phase 1)

# ============================================================ Boot-Nachweis (SPEC v5 §4.3)

## Belegt, WO das Spiel ohne CLI-Argumente wirklich landet. Wichtig seit
## Game.USE_HIDEOUT_MENU=true: der Startbildschirm ist jetzt der begehbare Raum,
## und das soll nicht bloss behauptet, sondern gezeigt sein.
func _boot_shots(outdir: String) -> void:
	print("BOOT-SHOTS: nach ", outdir)
	Sfx.muted = true
	get_window().size = Vector2i(1600, 900)
	await _wait(4.0)                    # Titelkarte einblenden + wieder ausblenden lassen
	var who := "?" if current == null else String(current.name)
	print("BOOT-SHOTS: Startbildschirm = ", who)
	await _snap(outdir + "/boot_menu.png")
	print("BOOT-SHOTS: fertig")
	get_tree().quit()

# ============================================================ Unterschlupf-Shots (SPEC v5 §4.3)

## Acceptance proof for the walkable room: once in menu mode, once in base mode.
## Useless headless (3D + lighting) -> window mode.
func _hideout_shots(outdir: String) -> void:
	print("HIDEOUT-SHOTS: to ", outdir)
	Sfx.muted = true
	get_window().size = Vector2i(1600, 900)
	Game.new_game()
	hideout_mode = "menu"
	goto("hideout")
	await _wait(3.6)                      # the "BITTER HARVEST" title card is gone after 2 s
	await _snap(outdir + "/hideout_01_menu.png")
	# Base mode: the bed heals, the crates are the stash, the door leads back to the map.
	Game.base_unlocked = true
	hideout_mode = "base"
	goto("hideout")
	await _wait(3.6)
	await _snap(outdir + "/hideout_02_base.png")
	# Hover-Animationen (SPEC v5 §4.3 "hover feedback"): Ein Screenshot hat keinen
	# Mauszeiger, also erzwingen wir den Hover-Zustand direkt ueber _set_hover().
	# So laesst sich belegen, dass Laptopdeckel, Bettdecke & Co. sich WIRKLICH
	# bewegen — headless waere davon nichts zu sehen.
	for want in ["laptop", "bed", "door", "crates"]:
		var idx := -1
		for i in current._hotspots.size():
			if String(current._hotspots[i]["id"]) == String(want):
				idx = i
				break
		if idx < 0:
			print("HIDEOUT-SHOTS: Hotspot '%s' nicht gefunden" % String(want))
			continue
		current._set_hover(idx)
		await _wait(0.6)            # Hover-Tween laeuft 0.22 s -> sicher durch
		await _snap("%s/hideout_hover_%s.png" % [outdir, String(want)])
		current._set_hover(-1)
		await _wait(0.35)
	print("HIDEOUT-SHOTS: done")
	get_tree().quit()

# ============================================================ Gallery shots (SPEC v5 §4.1/§8.5)

## Acceptance proof for §4.1 step 5: NINE distinguishable mercs, weapons in hand,
## and the shoot animation really playing. Colours, model scale and T-poses are
## invisible headless — hence the window mode.
## Opens res://scenes/unit_gallery.tscn so the shipped SCENE is what gets reviewed;
## a missing .tscn degrades to the script route (fallback law), never a crash.
func _gallery_shots(outdir: String) -> void:
	print("GALLERY-SHOTS: to ", outdir)
	Sfx.muted = true
	get_window().size = Vector2i(1920, 1080)
	if not _goto_scene("res://scenes/unit_gallery.tscn", "unit_gallery"):
		print("GALLERY-SHOTS: scene missing — fell back to the script route")
	await _wait(2.0)
	# Cheap sanity print: the review is worthless if not all nine bodies are there.
	var n := 0
	if current != null:
		n = (current._units as Array).size()
	print("GALLERY-SHOTS: %d figures built (expected 9)" % n)
	await _snap(outdir + "/gallery_01_idle.png")
	# The mandatory clips of the acceptance list, one frame each.
	for step in [["aim", "gallery_02_aim.png"], ["shoot", "gallery_03_shoot.png"],
			["walk", "gallery_04_walk.png"], ["death", "gallery_05_death.png"]]:
		var pair: Array = step
		current._set_anim(String(pair[0]))
		await _wait(0.45)
		await _snap("%s/%s" % [outdir, String(pair[1])])
	current._set_anim("idle")
	print("GALLERY-SHOTS: done")
	get_tree().quit()


## Opens a packed scene as the current screen (same bookkeeping as goto()).
## Returns false and falls back to the SCREENS route when the file is missing.
func _goto_scene(scene_path: String, fallback_screen: String) -> bool:
	if not ResourceLoader.exists(scene_path):
		goto(fallback_screen)
		return false
	var packed = load(scene_path)
	if packed == null or not (packed is PackedScene):
		goto(fallback_screen)
		return false
	var node: Node = (packed as PackedScene).instantiate()
	if node == null:
		goto(fallback_screen)
		return false
	if current != null:
		current.queue_free()
		current = null
	current = node
	add_child(node)
	return true

# ============================================================ Dossier-Shots (SPEC v5 §4.2)

## Acceptance proof for §4.2: the dossier must sit exactly centred at EVERY window
## size and must not clip anything. Shoots one screenshot each at 1280x720 and
## 1920x1080 — precisely the two resolutions the spec demands.
func _hire_shots(outdir: String) -> void:
	print("HIRE-SHOTS: to ", outdir)
	Sfx.muted = true
	Game.new_game()
	Game.set_difficulty("leicht")
	goto("hire")
	await _wait(0.4)
	for res in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var r: Vector2i = res
		get_window().size = r
		await _wait(0.6)
		current._show_detail(Db.MERCS[0])
		await _wait(0.7)
		await _snap("%s/dossier_%dx%d.png" % [outdir, r.x, r.y])
		current._close_detail()
		await _wait(0.3)
	print("HIRE-SHOTS: done")
	get_tree().quit()

# ============================================================ Zwei-Sektoren-Sonde (SPEC v5 §2)

func _sector3d_fail(fails: int, msg: String) -> int:
	push_error("SECTOR3D-ERROR: " + msg)
	print("SECTOR3D-ERROR: ", msg)
	return fails + 1

## Proof for the two-sector demo. Two things must hold: (a) F3 behaves EXACTLY as
## before (the other four test modes depend on it), and (b) F4 is built sensibly —
## above all the west exit must be REACHABLE from the landing point, otherwise the
## demo cannot be played through (softlock).
func _sector3d() -> void:
	print("SECTOR3D: Start")
	var fails := 0

	# ---------- S1: F3 regression (default call == explicit sector) ----------
	var f3 := Tac3DMapGen.generate(20260718, "leicht")
	var f3b := Tac3DMapGen.generate(20260718, "leicht", "F3")
	if f3["enemy_spawns"].size() != Tac3DMapGen.DEMO_ENEMY_TOTAL:
		fails = _sector3d_fail(fails, "S1: F3 enemy count %d instead of %d" % [f3["enemy_spawns"].size(), Tac3DMapGen.DEMO_ENEMY_TOTAL])
	if f3b["enemy_spawns"].size() != f3["enemy_spawns"].size():
		fails = _sector3d_fail(fails, "S1: generate(..., 'F3') differs from the default call")
	var otto3: Vector3i = f3["otto_spawn"]
	if otto3.y != -1:
		fails = _sector3d_fail(fails, "S1: F3 otto_spawn not on level -1 (%s)" % str(otto3))
	if not (f3["exit_cells"] as Array).is_empty():
		fails = _sector3d_fail(fails, "S1: F3 must not carry exit_cells")
	if fails == 0:
		print("SECTOR3D: S1 F3 regression ok")

	# ---------- S2: F4 delivers the same keys (no caller crashes) ----------
	var f4 := Tac3DMapGen.generate(20260718, "leicht", "F4")
	for k in f3.keys():
		if not f4.has(k):
			fails = _sector3d_fail(fails, "S2: F4 is missing the key '%s'" % str(k))
	var g4: Grid3D = f4["grid"]

	# ---------- S3: F4 sentinels (no cellar, no boss, no boardwalk) ----------
	var no_cell: Vector3i = Tac3DMapGen.NO_CELL
	for key in ["otto_spawn", "keller_entrance", "boss_home"]:
		var c: Vector3i = f4[key]
		if c != no_cell:
			fails = _sector3d_fail(fails, "S3: F4 '%s' should be NO_CELL, is %s" % [key, str(c)])
	if not (f4["bridge_cells"] as Array).is_empty():
		fails = _sector3d_fail(fails, "S3: F4 must not carry bridge_cells")

	# ---------- S4: spawns are walkable ----------
	for sp in f4["merc_spawns"]:
		var mc: Vector3i = sp
		if not g4.is_walkable(mc):
			fails = _sector3d_fail(fails, "S4: F4 merc spawn blocked: %s" % str(mc))
	for es in f4["enemy_spawns"]:
		var ec: Vector3i = es["cell"]
		if not g4.is_walkable(ec):
			fails = _sector3d_fail(fails, "S4: F4 enemy spawn blocked: %s" % str(ec))
	if (f4["enemy_spawns"] as Array).is_empty():
		fails = _sector3d_fail(fails, "S4: F4 has no enemies (the approach tutorial needs patrols)")

	# ---------- S5: the west exit exists and is walkable ----------
	var exits: Array = f4["exit_cells"]
	if exits.is_empty():
		fails = _sector3d_fail(fails, "S5: F4 has no exit_cells (no west exit)")
	for e0 in exits:
		var e: Vector3i = e0
		if not g4.is_walkable(e):
			fails = _sector3d_fail(fails, "S5: exit_cell not walkable: %s" % str(e))
			break

	# ---------- S6: CRITICAL — the exit is reachable from the landing point ----------
	if not exits.is_empty() and not (f4["merc_spawns"] as Array).is_empty():
		var pf := Pathfinder3D.new()
		pf.build(g4)
		pf.set_move_type_enabled(Tac3DTile.Move.SWIM, false)
		var start4: Vector3i = f4["merc_spawns"][0]
		var reached := false
		for ec2 in exits:
			var e2: Vector3i = ec2
			if pf.reachable(start4, e2):
				reached = true
				break
		if not reached:
			fails = _sector3d_fail(fails, "S6: NO west exit reachable from the landing point %s — the demo would be unplayable!" % str(start4))
		else:
			print("SECTOR3D: S6 west exit reachable ok")

	if fails == 0:
		print("SECTOR3D OK")
	else:
		print("SECTOR3D FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

# ============================================================ 3D-Taktik-Sonde (Phase 1)

func _tac3d_fail(fails: int, msg: String) -> int:
	push_error("TAC3D-ERROR: " + msg)
	print("TAC3D-ERROR: ", msg)
	return fails + 1

## Verification harness for the 3D tactics layer (contract §12): block A (pure
## logic, a fresh Pathfinder3D per mutating group) + block B (the scene opens, the
## unit walks its path).
func _tac3d_probe() -> void:
	print("TAC3D: Start")
	var fails := 0

	# --- Build the test map once (the grid is immutable; only the pathfinder mutates).
	var meta: Dictionary = TestMap3D.build()
	var g: Grid3D = meta["grid"]
	var start: Vector3i = meta["start"]
	var goal: Vector3i = meta["goal"]
	var west_probe: Vector3i = meta["west_probe"]
	var east_probe: Vector3i = meta["east_probe"]
	var swim_from: Vector3i = meta["swim_from"]
	var swim_to: Vector3i = meta["swim_to"]
	var deep_under_deck: Vector3i = meta["deep_under_deck"]
	var deck_over_deep: Vector3i = meta["deck_over_deep"]
	var bridge_cells: Array = meta["bridge_cells"]
	var podium_cells: Array = meta["podium_cells"]

	# ---------- Block A: pure logic ----------

	# A1: tiles on level 0 AND level 1; every bridge/podium cell walkable.
	var has_l0 := false
	var has_l1 := false
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y == 0:
			has_l0 = true
		elif c.y == 1:
			has_l1 = true
	if not (has_l0 and has_l1):
		fails = _tac3d_fail(fails, "A1: missing level (L0=%s, L1=%s)" % [str(has_l0), str(has_l1)])
	for bc in bridge_cells:
		var b: Vector3i = bc
		if not g.has_tile(b) or not g.is_walkable(b):
			fails = _tac3d_fail(fails, "A1: bridge cell missing/blocked: %s" % str(b))
	for pc in podium_cells:
		var p: Vector3i = pc
		if not g.has_tile(p) or not g.is_walkable(p):
			fails = _tac3d_fail(fails, "A1: podium cell missing/blocked: %s" % str(p))

	# A2: a blocked bridge -> west/east NOT reachable (SWIM off).
	var pf_a2 := Pathfinder3D.new()
	pf_a2.build(g)
	pf_a2.set_move_type_enabled(Tac3DTile.Move.SWIM, false)
	for bc in bridge_cells:
		var b2: Vector3i = bc
		pf_a2.set_cell_blocked(b2, true)
	if pf_a2.reachable(west_probe, east_probe):
		fails = _tac3d_fail(fails, "A2: west/east reachable despite a blocked bridge")

	# A3: every bridge cell is BRIDGE and sits on level 1.
	for bc in bridge_cells:
		var b3: Vector3i = bc
		var t3: Tac3DTile = g.get_tile(b3)
		if t3 == null or t3.kind != Tac3DTile.Kind.BRIDGE or b3.y != 1:
			fails = _tac3d_fail(fails, "A3: wrong bridge cell: %s" % str(b3))

	# A4: deep water vs. the deck above it — different ids, different render height,
	# NOT connected.
	var pf_a4 := Pathfinder3D.new()
	pf_a4.build(g)
	var id_deep := pf_a4.point_id(deep_under_deck)
	var id_deck := pf_a4.point_id(deck_over_deep)
	if id_deep < 0 or id_deck < 0:
		fails = _tac3d_fail(fails, "A4: missing points (deep=%d, deck=%d)" % [id_deep, id_deck])
	elif id_deep == id_deck:
		fails = _tac3d_fail(fails, "A4: deep/deck share the same id (%d)" % id_deep)
	else:
		if g.cell_to_world(deep_under_deck).y == g.cell_to_world(deck_over_deep).y:
			fails = _tac3d_fail(fails, "A4: deep/deck have the same render height")
		if pf_a4.astar.are_points_connected(id_deep, id_deck):
			fails = _tac3d_fail(fails, "A4: deep/deck wrongly connected")

	# A5: the path start -> goal (SWIM off) exists, ends correctly, uses the BRIDGE.
	var pf_a5 := Pathfinder3D.new()
	pf_a5.build(g)
	pf_a5.set_move_type_enabled(Tac3DTile.Move.SWIM, false)
	var p5: Array = pf_a5.path_cells(start, goal)
	if p5.is_empty():
		fails = _tac3d_fail(fails, "A5: no path start -> goal (SWIM off)")
	else:
		if p5.front() != start:
			fails = _tac3d_fail(fails, "A5: the path does not begin at the start (%s)" % str(p5.front()))
		if p5.back() != goal:
			fails = _tac3d_fail(fails, "A5: the path does not end at the goal (%s)" % str(p5.back()))
		if not _tac3d_has_kind(g, p5, Tac3DTile.Kind.BRIDGE):
			fails = _tac3d_fail(fails, "A5: the path does not use the bridge")

	# A6: the path swim_from -> swim_to runs through the deep water.
	# With the bridge open, the deck (cost ~7) is cheaper than the water crossing
	# (WADE 4 + SWIM 10 + GROUND 1 = 15), so the path would take the deck and never
	# "swim". As in A2 we block the bridge deck (SWIM stays ON), which leaves the
	# deep water under the bridge as the only remaining crossing — exactly the
	# swim-under-the-bridge case that is meant to be proven here.
	var pf_a6 := Pathfinder3D.new()
	pf_a6.build(g)
	for bc in bridge_cells:
		var b6: Vector3i = bc
		pf_a6.set_cell_blocked(b6, true)
	var p6: Array = pf_a6.path_cells(swim_from, swim_to)
	if p6.is_empty():
		fails = _tac3d_fail(fails, "A6: no path swim_from -> swim_to")
	elif not _tac3d_has_kind(g, p6, Tac3DTile.Kind.WATER_DEEP):
		fails = _tac3d_fail(fails, "A6: the swim path avoids the deep water")

	# A7: the west bank is internally reachable.
	var pf_a7 := Pathfinder3D.new()
	pf_a7.build(g)
	if not pf_a7.reachable(Vector3i(1, 0, 5), Vector3i(5, 0, 5)):
		fails = _tac3d_fail(fails, "A7: west bank (1,0,5) -> (5,0,5) not reachable")

	# A8: start -> goal is reachable in principle (SWIM on).
	var pf_a8 := Pathfinder3D.new()
	pf_a8.build(g)
	if not pf_a8.reachable(start, goal):
		fails = _tac3d_fail(fails, "A8: start -> goal not reachable")

	# ---------- Block B: the scene opens + the unit walks its path ----------
	goto("tactical3d")
	var tac = current
	await tac.map_ready

	# B1: the await returned -> the scene opened without script errors.
	if tac == null:
		fails = _tac3d_fail(fails, "B1: tactical3d scene did not open")
	else:
		var tmeta: Dictionary = tac.meta

		# B2: the unit exists and stands at the start.
		if tac.unit == null:
			fails = _tac3d_fail(fails, "B2: unit is null")
		elif tac.unit.cell != tmeta["start"]:
			fails = _tac3d_fail(fails, "B2: the unit does not stand at the start (%s)" % str(tac.unit.cell))

		# B3: the demo path ends at the goal and uses the bridge.
		var cells: Array = tac.find_demo_path()
		if cells.is_empty():
			fails = _tac3d_fail(fails, "B3: find_demo_path is empty")
		else:
			if cells.back() != tmeta["goal"]:
				fails = _tac3d_fail(fails, "B3: the demo path does not end at the goal (%s)" % str(cells.back()))
			if not _tac3d_has_kind(tac.grid, cells, Tac3DTile.Kind.BRIDGE):
				fails = _tac3d_fail(fails, "B3: the demo path does not use the bridge")

		# B4: the unit walks the path and stands at the goal afterwards.
		tac.move_unit_along(cells)
		if tac.unit == null or tac.unit.cell != tmeta["goal"]:
			var reached := "null" if tac.unit == null else str(tac.unit.cell)
			fails = _tac3d_fail(fails, "B4: the unit did not reach the goal (at %s)" % reached)

		# B5: the camera is orthographic.
		if tac.rig == null or tac.rig.cam == null:
			fails = _tac3d_fail(fails, "B5: rig/camera missing")
		elif tac.rig.cam.projection != Camera3D.PROJECTION_ORTHOGONAL:
			fails = _tac3d_fail(fails, "B5: camera is not orthographic (%d)" % tac.rig.cam.projection)

	if fails == 0:
		print("TAC3D OK")
	else:
		print("TAC3D FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

## Helper: does `cells` contain a cell of the given kind?
func _tac3d_has_kind(g: Grid3D, cells: Array, kind: int) -> bool:
	for k in cells:
		var c: Vector3i = k
		if not g.has_tile(c):
			continue
		var t: Tac3DTile = g.get_tile(c)
		if t != null and t.kind == kind:
			return true
	return false

# ============================================================ 3D battle smoke (strand A)

func _smoke3d_fail(fails: int, msg: String) -> int:
	push_error("SMOKE3D-ERROR: " + msg)
	print("SMOKE3D-ERROR: ", msg)
	return fails + 1

## Reachability through the Pathfinder3D (contract §1.7).
func _reachable3d(pf: Pathfinder3D, from: Vector3i, to: Vector3i) -> bool:
	return pf.reachable(from, to)

## Full bot-battle proof of the 3D tactics layer (p2_1 §4): map (K), hiring (H),
## battle to victory (B), inventory/loot (I).
func _smoke3d() -> void:
	print("SMOKE3D: Start")
	var fails := 0

	# ---------- Block K: map (all 3 difficulties) ----------
	for diff in ["leicht", "normal", "schwer"]:
		var mp := Tac3DMapGen.generate(20260718, diff)
		var g: Grid3D = mp["grid"]
		# K1: since SPEC v5 §3.3.3 the enemy count depends on the difficulty AGAIN
		# (8/10/13 per Db.DIFFICULTY[..]["enemies"]). It used to be deliberately
		# decoupled to a fixed number — this test still expected that and therefore
		# failed on "normal"/"schwer". Now it queries the SAME source the generator
		# uses instead of maintaining the number twice.
		var expected := Tac3DMapGen.enemy_total(diff)
		if mp["enemy_spawns"].size() != expected:
			fails = _smoke3d_fail(fails, "[%s] K1: enemy count %d instead of %d" % [diff, mp["enemy_spawns"].size(), expected])
		# K2: every merc/enemy spawn is walkable.
		for sp in mp["merc_spawns"]:
			var mc: Vector3i = sp
			if not g.is_walkable(mc):
				fails = _smoke3d_fail(fails, "[%s] K2: merc spawn blocked: %s" % [diff, str(mc)])
		for es in mp["enemy_spawns"]:
			var ec: Vector3i = es["cell"]
			if not g.is_walkable(ec):
				fails = _smoke3d_fail(fails, "[%s] K2: enemy spawn blocked: %s (%s)" % [diff, str(ec), String(es["type"])])
		# K3: LEICHT carries no elite guards (the downgrade works).
		if diff == "leicht":
			for es in mp["enemy_spawns"]:
				if String(es["type"]).begins_with("elite"):
					fails = _smoke3d_fail(fails, "K3: LEICHT contains an elite guard (%s)" % String(es["type"]))
					break
		# K4: at least 5 loot tiles.
		if mp["loot_cells"].size() < 5:
			fails = _smoke3d_fail(fails, "[%s] K4: too few loot tiles: %d" % [diff, mp["loot_cells"].size()])

	# Structural assertions (geometry is difficulty-independent) on one map.
	var kmap := Tac3DMapGen.generate(20260718, "leicht")
	var kg: Grid3D = kmap["grid"]
	var mspawn0: Vector3i = kmap["merc_spawns"][0]
	var boss_home: Vector3i = kmap["boss_home"]
	var bridge_cells: Array = kmap["bridge_cells"]

	# K5: the boss must be reachable from the merc spawn (SWIM off) and stand at
	# ground level. The condition demanded here before — "the path MUST cross the
	# bridge" — no longer holds: since SPEC v5 §3.3.2/§6 the demo is DRY (no river)
	# and the boardwalk is just a walkable plank path. Without water there is no
	# reason to use it, so the pathfinder may legitimately go around. Reachability
	# is the property that actually matters.
	var pf_k5 := Pathfinder3D.new()
	pf_k5.build(kg)
	pf_k5.set_move_type_enabled(Tac3DTile.Move.SWIM, false)
	if not _reachable3d(pf_k5, mspawn0, boss_home):
		fails = _smoke3d_fail(fails, "K5: boss not reachable from the merc spawn (SWIM off)")
	elif boss_home.y != 0:
		fails = _smoke3d_fail(fails, "K5: boss home is not at ground level (flat manor)")

	# K6 (flat deck): the boardwalk lies at ground level (0) and is walkable — the
	# old raised deck (level 1, its own AStar nodes) went away with "everything flat".
	for bc6 in bridge_cells:
		var b6: Vector3i = bc6
		if b6.y != 0 or not kg.is_walkable(b6):
			fails = _smoke3d_fail(fails, "K6: boardwalk cell %s is not flat/walkable" % str(b6))
			break

	# K7: the demo is DRY (SPEC v5 §3.3.2 "dry — no water in the demo", §6
	# "water/bridge flags exist in the data model but are NOT implemented"). The
	# swim path checked here before therefore no longer exists on purpose. Instead
	# of deleting the test, it now guards the NEW promise: the map reports the water
	# sentinels cleanly and contains no deep water any more. So it shows up if
	# somebody accidentally generates a river back in.
	var swim_from: Vector3i = kmap["swim_from"]
	var swim_to: Vector3i = kmap["swim_to"]
	if swim_from != Tac3DMapGen.NO_CELL or swim_to != Tac3DMapGen.NO_CELL:
		fails = _smoke3d_fail(fails, "K7: swim_from/swim_to are not NO_CELL sentinels (%s/%s)" % [str(swim_from), str(swim_to)])
	var wet := 0
	for k7c in kg.all_cells():
		var c7: Vector3i = k7c
		var t7: Tac3DTile = kg.get_tile(c7)
		if t7 != null and t7.kind == Tac3DTile.Kind.WATER_DEEP:
			wet += 1
	if wet > 0:
		fails = _smoke3d_fail(fails, "K7: the demo should be dry, but found %d WATER_DEEP tiles" % wet)
	print("SMOKE3D: map ok (loot: %d)" % kmap["loot_cells"].size())

	# ---------- Block H: hiring (shared with --smoke) ----------
	fails = _check_hire(fails)
	_boost_team()
	print("SMOKE3D: hiring + test boost ok")

	# ---------- Block B: battle (B1 all difficulties, B2-B5 + I for LEICHT) ----------
	for diff in ["leicht", "normal", "schwer"]:
		Game.set_difficulty(diff)
		goto("tactical3d_combat")
		var tac = current
		await tac.battle_ready
		# B1: neutral spawn — no combat, no enemy contact at the start (spec §14.3).
		if tac.combat_started or tac._any_contact():
			fails = _smoke3d_fail(fails, "[%s] B1: mission starts with enemy contact (spawn not neutral)" % diff)
		if diff != "leicht":
			continue
		# B2: toned-down demo — 3 militia + boss (on every difficulty, see Tac3DMapGen).
		if tac.enemies.size() != Tac3DMapGen.DEMO_ENEMY_TOTAL:
			fails = _smoke3d_fail(fails, "B2: enemy count %d instead of %d (leicht)" % [tac.enemies.size(), Tac3DMapGen.DEMO_ENEMY_TOTAL])
		# B3: the bot plays through to victory.
		Game.boss_dialog_seen = false
		var res: String = await tac.auto_battle()
		print("SMOKE3D: result = %s after %d turns (shots: %d, hits: %d)" % [res, int(Game.stats["turns"]), int(Game.stats["shots"]), int(Game.stats["hits"])])
		if res != "victory":
			fails = _smoke3d_fail(fails, "B3: the bot squad did not win (result '%s')" % res)
		else:
			# B4: victory only after the boss was sighted.
			if not Game.boss_dialog_seen:
				fails = _smoke3d_fail(fails, "B4: victory without the boss sighting/dialogue")
			# B5: no enemy is alive any more.
			for e in tac.enemies:
				var en: Tac3DUnit = e
				if en.alive:
					fails = _smoke3d_fail(fails, "B5: an enemy is still alive after the victory")
					break
		# ---------- Block I: inventory/loot (the map is still loaded) ----------
		fails = _smoke3d_inventory(tac, fails)
		# ---------- Block Z: hit zones + stances (JA2) ----------
		fails = await _smoke3d_zones(tac, fails)

	if fails == 0:
		print("SMOKE3D OK")
	else:
		print("SMOKE3D FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

## Block Z — hit zones (head/torso/legs) + stances (JA2). Deterministic formula and
## state checks, no dice: zone penalties, stance step costs, the limp (cripple), and
## the AP cost of a stance change.
func _smoke3d_zones(tac, fails: int) -> int:
	var mz: Tac3DUnit = null
	for m in tac.mercs:
		var merc: Tac3DUnit = m
		if merc.alive:
			mz = merc
			break
	if mz == null or tac.enemies.is_empty():
		print("SMOKE3D: block Z skipped (no units)")
		return fails
	var ez: Tac3DUnit = tac.enemies[0]
	# Z1: head/leg penalties push the hit chance down (or hit the clamp at 5).
	var hc_torso: int = tac.hit_chance(mz, ez, 0, "torso")
	var hc_kopf: int = tac.hit_chance(mz, ez, 0, "kopf")
	var hc_beine: int = tac.hit_chance(mz, ez, 0, "beine")
	if hc_kopf > hc_torso or hc_beine > hc_torso or (hc_torso > 30 and hc_torso < 95 and hc_kopf != hc_torso - 25):
		fails = _smoke3d_fail(fails, "Z1: zone penalties wrong (torso %d, head %d, legs %d)" % [hc_torso, hc_kopf, hc_beine])
	else:
		print("SMOKE3D: Z1 zone penalties ok")
	# Z2: stance step costs follow Db.STANCES (move_num/move_den, integer division).
	var flat_cell: Vector3i = mz.cell + Vector3i(1, 0, 0)
	var base_cost: int = tac.step_ap(flat_cell)
	var exp_prone: int = base_cost * int(Db.STANCES["prone"]["move_num"]) / int(Db.STANCES["prone"]["move_den"])
	var exp_crouch: int = base_cost * int(Db.STANCES["crouch"]["move_num"]) / int(Db.STANCES["crouch"]["move_den"])
	mz.stance = "prone"
	var prone_cost: int = tac.step_ap_for(mz, flat_cell)
	mz.stance = "crouch"
	var crouch_cost: int = tac.step_ap_for(mz, flat_cell)
	mz.stance = "stand"
	if prone_cost != exp_prone or crouch_cost != exp_crouch or tac.step_ap_for(mz, flat_cell) != base_cost:
		fails = _smoke3d_fail(fails, "Z2: stance step costs wrong (%d/%d/%d on a base of %d)" % [prone_cost, crouch_cost, tac.step_ap_for(mz, flat_cell), base_cost])
	else:
		print("SMOKE3D: Z2 stance step costs ok")
	# Z3: a leg hit (limp) doubles the cost on top of that.
	mz.cripple_rounds = 1
	if tac.step_ap_for(mz, flat_cell) != base_cost * 2:
		fails = _smoke3d_fail(fails, "Z3: the limp does not double the step cost")
	else:
		print("SMOKE3D: Z3 limp ok")
	mz.cripple_rounds = 0
	# Z4: a stance change costs Db.STANCE_AP per step (standing->prone = 2 steps).
	mz.ap = 10
	if not tac.set_stance(mz, "prone") or mz.ap != 10 - 2 * Db.STANCE_AP or mz.stance != "prone":
		fails = _smoke3d_fail(fails, "Z4: stance change AP wrong (ap %d, stance %s)" % [mz.ap, mz.stance])
	else:
		print("SMOKE3D: Z4 stance change AP ok")
	tac.set_stance(mz, "stand", true)
	# Z5: a prone unit is only spotted at a shortened distance (PRONE_SPOT_MULT).
	mz.stance = "prone"
	var sight: float = tac.vision.sight_of(ez, mz.cell)
	var d_flat: float = Tac3DVision.flat(ez.cell).distance_to(Tac3DVision.flat(mz.cell))
	var expect: bool = d_flat <= sight * Db.PRONE_SPOT_MULT and tac.vision.los(ez.cell, mz.cell)
	if tac.unit_sees(ez, mz.cell) != expect:
		fails = _smoke3d_fail(fails, "Z5: the prone sight range does not apply")
	else:
		print("SMOKE3D: Z5 prone sight range ok")
	mz.stance = "stand"
	# Z6: parallel group move — both set off, busy/_movers are released again
	# (refcount safeguard; battle_over is lifted briefly, the map is still loaded).
	var mzb: Tac3DUnit = null
	for m2 in tac.mercs:
		var mm: Tac3DUnit = m2
		if mm.alive and mm != mz:
			mzb = mm
			break
	if mzb != null:
		var was_over: bool = tac.battle_over
		tac.battle_over = false
		var gt := Vector3i(-99, 0, -99)
		for gdz in range(-4, 5):
			for gdx in range(-4, 5):
				var gc: Vector3i = mz.cell + Vector3i(gdx, 0, gdz)
				if absi(gdx) + absi(gdz) >= 3 and tac.grid.is_walkable(gc) and not tac.occupied.has(gc):
					gt = gc
		mz.ap = 99
		mzb.ap = 99
		var a0: Vector3i = mz.cell
		var b0: Vector3i = mzb.cell
		if gt.x > -50:
			await tac._group_move(gt, [mz, mzb])
		tac.battle_over = was_over
		if tac.busy or tac._movers != 0:
			fails = _smoke3d_fail(fails, "Z6: busy/_movers not released after the group move (%s/%d)" % [str(tac.busy), tac._movers])
		elif gt.x > -50 and mz.cell == a0 and mzb.cell == b0:
			fails = _smoke3d_fail(fails, "Z6: the group move moved nobody")
		else:
			print("SMOKE3D: Z6 group move ok")
	return fails


## Block I — inventory/loot function tests on the 3D API. Shared with --smoke.
func _smoke3d_inventory(tac, fails: int) -> int:
	var mt: Tac3DUnit = null
	for m in tac.mercs:
		var merc: Tac3DUnit = m
		if merc.alive:
			mt = merc
			break
	if mt == null:
		print("SMOKE3D: block I skipped (no living merc)")
		return fails
	# I1: reloading consumes exactly 1 magazine.
	var cal2 := String(Db.weapon(mt.data["weapon"])["cal"])
	mt.data["inv"] = ["mag_" + cal2]
	mt.data["ammo"] = 0
	mt.ap = 99
	tac.do_reload(mt)
	if int(mt.data["ammo"]) != int(Db.weapon(mt.data["weapon"])["mag"]) or (mt.data["inv"] as Array).size() != 0:
		fails = _smoke3d_fail(fails, "I1: reloading did not consume the magazine correctly")
	else:
		print("SMOKE3D: I1 reload ok")
	# I2: weapon swap to k45.
	mt.data["inv"] = ["k45"]
	mt.ap = 99
	tac.do_swap(mt, 0)
	if String(mt.data["weapon"]) != "k45":
		fails = _smoke3d_fail(fails, "I2: weapon swap failed")
	else:
		print("SMOKE3D: I2 weapon swap ok")
	# I3: search a crate -> it is marked as emptied.
	var lootc := Vector3i(-99, 0, -99)
	for c in tac.loot_cells:
		var lc: Vector3i = c
		if tac.search_target_at(lc) == "crate":
			lootc = lc
			break
	if lootc.x <= -50:
		print("SMOKE3D: I3 skipped (no crate present)")
		return fails
	var placed := false
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if placed or (dx == 0 and dz == 0):
				continue
			var n: Vector3i = lootc + Vector3i(dx, 0, dz)
			if tac.grid.is_walkable(n) and not tac.occupied.has(n):
				tac._vacate(mt.cell)
				mt.set_cell(n)
				tac._occupy(mt, n)
				placed = true
	if not placed:
		print("SMOKE3D: I3 skipped (no free neighbour next to the crate)")
		return fails
	mt.ap = 99
	mt.data["inv"] = []
	tac.do_search(mt, lootc)
	if tac.search_target_at(lootc) == "crate":
		fails = _smoke3d_fail(fails, "I3: the crate was not marked as emptied after the search")
	else:
		print("SMOKE3D: I3 crate loot ok")
	return fails

## Window screenshots of the sector map — proves that the sector rectangles sit on
## the DRAWN grid (not verifiable headless).
func _map_shots(outdir: String) -> void:
	print("MAP-SHOTS: to ", outdir)
	Sfx.muted = true
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs"]:
		Game.hire(id)
	goto("island")
	await _wait(1.0)
	await _snap(outdir + "/map_01_overview.png")
	# Clicking F3 only shows the "on foot" hint; amber/DEPLOY stay on F4.
	current._on_cell("F3")
	await _wait(0.5)
	await _snap(outdir + "/map_02_rookhaven_onfoot.png")
	# Locked sector -> LOCKED + the in-fiction reason in the header.
	current._on_cell("A9")
	await _wait(0.5)
	await _snap(outdir + "/map_03_locked.png")
	Game.delete_save(Game.AUTOSAVE_SLOT)
	print("MAP-SHOTS: done")
	get_tree().quit()

# ============================================================ Sector map (SPEC v4.1 §1)

func _map_fail(fails: int, msg: String) -> int:
	push_error("MAP-ERROR: " + msg)
	print("MAP-ERROR: ", msg)
	return fails + 1

## Proof for the Ashveil sector map. The core point is the pixel -> sector mapping:
## the DRAWN grid is NOT uniform, and a grid error would surface exactly here. The
## reference points are the canonical places from SPEC §1.
func _map_probe() -> void:
	print("MAP: Start")
	var fails := 0
	Sfx.muted = true
	Game.new_game()
	Game.hire("nadel")
	goto("island")
	await get_tree().process_frame
	var isl = current
	if isl == null:
		print("MAP FAIL (1)")
		get_tree().quit(1)
		return

	# ---------- P1: grid from data/sectors.json ----------
	if (isl._gx as Array).size() != 11 or (isl._gy as Array).size() != 7:
		fails = _map_fail(fails, "P1: wrong grid (x=%d, y=%d) — sectors.json not loaded?" % [(isl._gx as Array).size(), (isl._gy as Array).size()])
	if (isl._rows as Array).size() != 6 or (isl._cols as Array).size() != 10:
		fails = _map_fail(fails, "P1: expected 10x6, got %dx%d" % [(isl._cols as Array).size(), (isl._rows as Array).size()])
	if (isl._cells as Dictionary).size() != 60:
		fails = _map_fail(fails, "P1: %d sector tiles instead of 60" % (isl._cells as Dictionary).size())
	else:
		print("MAP: P1 grid 10x6 / 60 tiles ok")

	# ---------- P2: pixel -> sector (canonical places from SPEC §1) ----------
	var pts := [
		[633.0, 774.0, "F4"],    # landing zone
		[476.0, 774.0, "F3"],    # Rookhaven
		[952.0, 650.0, "E6"],    # Widow's Vein Diamond Mine
		[1254.0, 408.0, "C8"],   # Hollowpoint Barracks
		[1551.0, 167.0, "A10"],  # Helix Manor
		[792.0, 167.0, "A5"],    # Stoneglint Diamond Mine
		[156.0, 167.0, "A1"],    # north-west corner
	]
	for p in pts:
		var got: String = isl.sector_at_pixel(float(p[0]), float(p[1]))
		if got != String(p[2]):
			fails = _map_fail(fails, "P2: pixel (%d,%d) -> '%s' instead of '%s'" % [int(p[0]), int(p[1]), got, String(p[2])])
	if isl.sector_at_pixel(10.0, 10.0) != "":
		fails = _map_fail(fails, "P2: a point outside the grid still returns a sector")
	print("MAP: P2 pixel->sector ok")

	# ---------- P3: deploy rule — ONLY the current location is a mission target --
	# SPEC v4.1 §1: start F4, the only way out is west -> F3 ON FOOT. F3 is demo
	# content but must NOT be jumped to directly.
	if not isl.is_deployable("F4"):
		fails = _map_fail(fails, "P3: the location F4 is not deployable")
	if isl.is_deployable("F3"):
		fails = _map_fail(fails, "P3: F3 must NOT be directly deployable (reachable on foot only)")
	if not (isl.is_demo("F4") and isl.is_demo("F3")):
		fails = _map_fail(fails, "P3: F4/F3 are not marked as demo sectors")
	var deployable := 0
	var demo_n := 0
	for r in (isl._rows as Array).size():
		for c in (isl._cols as Array).size():
			var sid: String = isl.sector_id(r, c)
			if isl.is_deployable(sid):
				deployable += 1
			if isl.is_demo(sid):
				demo_n += 1
	if deployable != 1:
		fails = _map_fail(fails, "P3: %d deploy targets instead of exactly 1" % deployable)
	if demo_n != 2:
		fails = _map_fail(fails, "P3: %d demo sectors instead of 2" % demo_n)
	for locked in ["E4", "F2", "C3", "C7", "D8", "E6", "A5", "A9", "B10", "A1", "F10"]:
		if isl.is_demo(locked) or isl.is_deployable(locked):
			fails = _map_fail(fails, "P3: %s should be locked" % locked)
	print("MAP: P3 deploy rule checked (exactly 1 target = F4, F3 on foot only)")

	# ---------- P4: canonical names from SPEC §1 ----------
	var names := {"F3": "Rookhaven", "E6": "Widow's Vein Diamond Mine",
		"C7": "Hollowpoint Barracks", "A9": "Helix Manor", "C3": "Briar Hollow",
		"A5": "Stoneglint Diamond Mine", "F4": "Landing Zone"}
	for id in names:
		var got_name := String(isl.sector_def(id)["name"])
		if got_name != String(names[id]):
			fails = _map_fail(fails, "P4: %s is called '%s' instead of '%s'" % [id, got_name, String(names[id])])
	print("MAP: P4 place names ok")

	# ---------- P5: a map click only INSPECTS — it never relocates the squad ----------
	if isl._current != "F4" or Game.sector != "F4":
		fails = _map_fail(fails, "P5: the start is not F4 (%s / %s)" % [String(isl._current), Game.sector])
	isl._on_cell("A9")                       # locked
	if Game.sector != "F4" or isl._current != "F4":
		fails = _map_fail(fails, "P5: clicking a locked sector relocated the squad (%s)" % Game.sector)
	isl._on_cell("F3")                       # demo target, but on foot only
	if Game.sector != "F4" or isl._current != "F4":
		fails = _map_fail(fails, "P5: clicking F3 relocated the squad (%s) — forbidden!" % Game.sector)
	if isl._focus != "F3":
		fails = _map_fail(fails, "P5: clicking F3 does not display the sector (_focus=%s)" % String(isl._focus))
	print("MAP: P5 a click inspects but does not relocate")

	# ---------- P6: the rule travels with the squad (sector by sector) ----------
	# Once the squad stands in F3, F3 is the target — and F4 no longer is.
	Game.sector = "F3"
	goto("island")
	await get_tree().process_frame
	var isl2 = current
	if not isl2.is_deployable("F3") or isl2.is_deployable("F4"):
		fails = _map_fail(fails, "P6: the deploy target does not travel with the location")
	elif isl2._current != "F3":
		fails = _map_fail(fails, "P6: _current does not follow Game.sector (%s)" % String(isl2._current))
	else:
		print("MAP: P6 the deploy target travels with the location")

	Game.delete_save(Game.AUTOSAVE_SLOT)
	if fails == 0:
		print("MAP OK")
	else:
		print("MAP FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

## Window screenshots of the main menu. IMPORTANT: menu_02 tints the invisible
## hotspots — that is the only way to verify that they sit exactly on the buttons
## PAINTED INTO THE ARTWORK, which is invisible headless.
func _menu_shots(outdir: String) -> void:
	print("MENU-SHOTS: to ", outdir)
	Sfx.muted = true
	Game.delete_save(Game.AUTOSAVE_SLOT)
	# 1) Menu without a save -> CONTINUE/LOAD dimmed.
	goto("title")
	await _wait(1.2)
	await _snap(outdir + "/menu_01_plain.png")
	# 2) Make the hotspots visible (coverage probe).
	for id in current._buttons:
		var b: Button = current._buttons[id]
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 0, 0, 0.30)
		sb.set_border_width_all(2)
		sb.border_color = Color(0, 1, 0, 0.95)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("disabled", sb)
	await _wait(0.5)
	await _snap(outdir + "/menu_02_hotspots.png")
	# 3) With a save -> CONTINUE/LOAD enabled.
	Game.new_game()
	Game.hire("ivan")
	Game.save_game(Game.AUTOSAVE_SLOT, "Screenshot")
	goto("title")
	await _wait(1.2)
	await _snap(outdir + "/menu_03_with_save.png")
	# 4) Options (deliberately empty).
	current._show_options()
	await _wait(0.6)
	await _snap(outdir + "/menu_04_options.png")
	current._close_options()
	# 5) Load screen with an occupied autosave slot.
	goto("load_game")
	await _wait(0.8)
	await _snap(outdir + "/menu_05_load.png")
	Game.delete_save(Game.AUTOSAVE_SLOT)
	print("MENU-SHOTS: done")
	get_tree().quit()

# ============================================================ Main menu + save slots

func _menu_fail(fails: int, msg: String) -> int:
	push_error("MENU-ERROR: " + msg)
	print("MENU-ERROR: ", msg)
	return fails + 1

## Proof for the main menu (artwork hotspots) and the save/load roundtrip.
## Core point: Color/Dictionary fields (tint, portrait) do NOT survive JSON and
## are rebuilt from Db.merc_def() on load — exactly that is asserted here.
## Order matters: M6 needs a world WITHOUT any save file, so the damaged-slot
## block (which writes files) runs last.
func _menu_probe() -> void:
	print("MENU: Start")
	var fails := 0
	Sfx.muted = true
	fails = _check_save_roundtrip(fails)
	fails = await _menu_screens(fails)
	fails = await _check_bad_slots(fails)
	if fails == 0:
		print("MENU OK")
	else:
		print("MENU FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)


## M1-M5 — the save/load roundtrip. Extracted so --smoke can reuse it verbatim
## (§8.9 "a save roundtrip") instead of a second, drifting copy.
func _check_save_roundtrip(fails: int) -> int:
	var test_slot := 2
	Game.delete_save(test_slot)
	Game.delete_save(Game.AUTOSAVE_SLOT)

	# ---------- M1: fresh game, mutate state, save ----------
	Game.new_game()
	# Two CHEAP mercs (Ivan+Fuchs blow the budget on SCHWER); set the difficulty
	# afterwards — the price factor is irrelevant for the save roundtrip.
	for id in ["nadel", "blitz"]:
		Game.hire(id)
	Game.set_difficulty("schwer")
	if Game.team.size() != 2:
		fails = _menu_fail(fails, "M1: team %d instead of 2" % Game.team.size())
	var m0: Dictionary = Game.team[0]
	var first_id := String(m0["id"])
	m0["hp"] = 17
	m0["ammo"] = 3
	m0["kills"] = 5
	m0["inv"] = ["medkit", "granate"]
	m0["alive"] = false
	Game.sector = "F3"
	Game.demo_finished = true
	Game.ending_choice = "burn"
	Game.otto_freed = true
	Game.base_unlocked = true
	Game.stats["turns"] = 12
	var budget_before := Game.budget
	if not Game.save_game(test_slot, "Testpoint"):
		fails = _menu_fail(fails, "M1: save_game failed")
	if not Game.has_save(test_slot):
		fails = _menu_fail(fails, "M1: save file missing after save_game")

	# ---------- M2: destroy the state, load it back, compare everything ----------
	Game.new_game()
	if Game.team.size() != 0 or Game.demo_finished:
		fails = _menu_fail(fails, "M2: new_game did not reset")
	if not Game.load_game(test_slot):
		fails = _menu_fail(fails, "M2: load_game failed")
	if Game.difficulty != "schwer":
		fails = _menu_fail(fails, "M2: difficulty '%s' instead of 'schwer'" % Game.difficulty)
	if Game.budget != budget_before:
		fails = _menu_fail(fails, "M2: budget %d instead of %d" % [Game.budget, budget_before])
	if Game.sector != "F3" or not Game.demo_finished or Game.ending_choice != "burn":
		fails = _menu_fail(fails, "M2: sector/demo_finished/ending_choice not restored")
	if not (Game.otto_freed and Game.base_unlocked):
		fails = _menu_fail(fails, "M2: flags not restored")
	if int(Game.stats["turns"]) != 12:
		fails = _menu_fail(fails, "M2: stats.turns %d instead of 12" % int(Game.stats["turns"]))
	if Game.team.size() != 2:
		fails = _menu_fail(fails, "M2: team %d instead of 2 after loading" % Game.team.size())
	else:
		var r0: Dictionary = Game.team[0]
		if int(r0["hp"]) != 17 or int(r0["ammo"]) != 3 or int(r0["kills"]) != 5:
			fails = _menu_fail(fails, "M2: hp/ammo/kills wrong (%d/%d/%d)" % [int(r0["hp"]), int(r0["ammo"]), int(r0["kills"])])
		if bool(r0["alive"]):
			fails = _menu_fail(fails, "M2: alive=false was lost")
		if (r0["inv"] as Array) != ["medkit", "granate"]:
			fails = _menu_fail(fails, "M2: inventory wrong (%s)" % str(r0["inv"]))
		# M3: JSON delivers numbers as float — the runtime needs real ints.
		if typeof(r0["hp"]) != TYPE_INT or typeof(r0["kills"]) != TYPE_INT:
			fails = _menu_fail(fails, "M3: hp/kills are not ints (%d/%d)" % [typeof(r0["hp"]), typeof(r0["kills"])])
		# M4: static Db data (Color/Dictionary) correctly rebuilt.
		if typeof(r0["tint"]) != TYPE_COLOR:
			fails = _menu_fail(fails, "M4: tint is not a Color (type %d)" % typeof(r0["tint"]))
		if typeof(r0["portrait"]) != TYPE_DICTIONARY:
			fails = _menu_fail(fails, "M4: portrait is not a Dictionary (type %d)" % typeof(r0["portrait"]))
		if String(r0["id"]) != first_id or String(r0["nick"]) == "":
			fails = _menu_fail(fails, "M4: static fields missing (id '%s')" % String(r0["id"]))
	print("MENU: M1-M4 save/load roundtrip ok")

	# ---------- M5: latest_slot / has_any_save / delete_save ----------
	if not Game.has_any_save() or Game.latest_slot() != test_slot:
		fails = _menu_fail(fails, "M5: latest_slot %d instead of %d" % [Game.latest_slot(), test_slot])
	var info := Game.save_info(test_slot)
	if info.is_empty():
		fails = _menu_fail(fails, "M5: save_info empty")
	else:
		# Nicknames do NOT come out of the file (only mutable fields are stored) —
		# they must be resolved from the Db.
		var nicks: Array = info["team"]
		if nicks.size() != 2 or String(nicks[0]) == "?" or String(nicks[0]) == "":
			fails = _menu_fail(fails, "M5: nicknames not resolved (%s)" % str(nicks))
		if String(info["sector"]) != "F3" or int(info["budget"]) != budget_before:
			fails = _menu_fail(fails, "M5: save_info fields wrong (%s / %d)" % [String(info["sector"]), int(info["budget"])])
	Game.delete_save(test_slot)
	if Game.has_save(test_slot):
		fails = _menu_fail(fails, "M5: delete_save did not delete")
	if Game.has_any_save():
		fails = _menu_fail(fails, "M5: has_any_save true despite a deleted save")
	print("MENU: M5 slot management ok")
	return fails


## M6-M8 — the menu screens themselves (title with/without a save, load screen).
func _menu_screens(fails: int) -> int:
	# ---------- M6: title screen builds all 5 buttons ----------
	_wipe_all_slots()
	goto("title")
	await get_tree().process_frame
	var t = current
	if t == null or (t._buttons as Dictionary).size() != 5:
		fails = _menu_fail(fails, "M6: title did not build 5 buttons")
	else:
		for id in ["start", "continue", "load", "options", "quit"]:
			if not (t._buttons as Dictionary).has(id):
				fails = _menu_fail(fails, "M6: button '%s' missing" % id)
		# Without a save, CONTINUE and LOAD must be disabled.
		if not t._buttons["continue"].disabled or not t._buttons["load"].disabled:
			fails = _menu_fail(fails, "M6: CONTINUE/LOAD not disabled without a save")
		if t._buttons["start"].disabled or t._buttons["quit"].disabled:
			fails = _menu_fail(fails, "M6: START/QUIT wrongly disabled")
	print("MENU: M6 title without a save ok")

	# ---------- M7: with a save, CONTINUE/LOAD are enabled ----------
	Game.new_game()
	Game.hire("ivan")
	Game.save_game(Game.AUTOSAVE_SLOT)
	goto("title")
	await get_tree().process_frame
	var t2 = current
	if t2 == null or t2._buttons["continue"].disabled or t2._buttons["load"].disabled:
		fails = _menu_fail(fails, "M7: CONTINUE/LOAD disabled despite a save")
	else:
		print("MENU: M7 title with a save ok")
	Game.delete_save(Game.AUTOSAVE_SLOT)

	# ---------- M8: load screen builds without errors ----------
	goto("load_game")
	await get_tree().process_frame
	if current == null:
		fails = _menu_fail(fails, "M8: load screen did not open")
	else:
		print("MENU: M8 load screen ok")
	return fails

# ============================================================ Screenshots

func _tac3d_shots(outdir: String) -> void:
	print("TAC3D-SHOTS: to ", outdir)
	Sfx.muted = true
	goto("tactical3d")
	await current.map_ready
	# Camera on the centre of the field, zoomed so the whole test field is visible.
	current.rig.focus_world(current.rig.field.get_center())
	current.rig.set_zoom(26.0)
	await _wait(0.6)
	await _snap(outdir + "/tac3d_01_overview.png")
	# Second angle: rotate the camera by 45 degrees.
	current.rig.rotate_step(1)
	await _wait(0.6)
	await _snap(outdir + "/tac3d_02_rotated.png")
	# Send the merc along the demo path over the bridge onto the podium.
	var cells: Array = current.find_demo_path()
	if not cells.is_empty():
		current.move_unit_along(cells)
		if current.unit != null:
			await current.unit.move_finished
	await _wait(0.5)
	await _snap(outdir + "/tac3d_03_bridge.png")
	# Close-up of the merc: KayKit character + weapon visible (strand B, p2_2 §4).
	if current.unit != null:
		current.rig.focus_world(current.unit.position)
		current.rig.set_zoom(8.0)
		await _wait(0.5)
		await _snap(outdir + "/tac3d_04_soldier.png")
		# Shooting animation.
		current.unit.play_anim("shoot")
		await _wait(0.4)
		await _snap(outdir + "/tac3d_05_shoot.png")
		# Death animation.
		current.unit.play_anim("death")
		await _wait(0.7)
		await _snap(outdir + "/tac3d_06_death.png")
	print("TAC3D-SHOTS: done")
	get_tree().quit()

# ============================================================ 3D-HUD (Phase 3)

func _hud3d_fail(fails: int, msg: String) -> int:
	push_error("HUD3D-ERROR: " + msg)
	print("HUD3D-ERROR: ", msg)
	return fails + 1

## Headless interaction test of the playable 3D battle (p3_1 §4b). Builds the HUD
## (fast=false) and checks selection/move/shot through the ui_* API + HUD state.
## Changes no core logic.
func _hud3d() -> void:
	print("HUD3D: Start")
	var fails := 0
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	goto("tactical3d_combat")
	var tac = current
	await tac.battle_ready

	# H1: the HUD exists (only built when not fast).
	if tac.hud == null:
		fails = _hud3d_fail(fails, "H1: the HUD was not built (hud == null)")
		print("HUD3D FAIL (%d)" % fails)
		get_tree().quit(1)
		return

	# H2: merc selection through the HUD API.
	tac.ui_select_slot(1)
	if tac.selected != tac.mercs[1]:
		fails = _hud3d_fail(fails, "H2: ui_select_slot(1) did not select mercs[1]")
	tac.ui_select_slot(0)
	var m0: Tac3DUnit = tac.mercs[0]

	# H3: a move (approach phase, free) through do_move changes the cell.
	var tgt: Vector3i = tac._nearest_alive_enemy_cell(m0.cell)
	var cells: Array = tac.prefix_for_ap(tac.path_toward(m0, tgt), 12)
	var before: Vector3i = m0.cell
	await tac.do_move(m0, cells)
	if m0.cell == before:
		fails = _hud3d_fail(fails, "H3: do_move did not change the cell (%s)" % str(before))

	# H4: the HUD mirrors the selection (gold frame on slot 0).
	if not tac.hud.has_selected_frame(0):
		fails = _hud3d_fail(fails, "H4: the HUD shows no gold frame for slot 0")

	# H5: a shot lowers the ammo and the HUD ammo label (deterministic: the round is
	# deducted before the hit roll).
	tac.combat_started = true
	var en: Tac3DUnit = null
	for e in tac.enemies:
		var enemy: Tac3DUnit = e
		if enemy.alive:
			en = enemy
			break
	if en == null:
		fails = _hud3d_fail(fails, "H5: no living enemy to shoot at")
	else:
		var ammo0 := int(m0.data["ammo"])
		m0.ap = 99
		await tac.shoot(m0, en)
		if int(m0.data["ammo"]) != ammo0 - 1:
			fails = _hud3d_fail(fails, "H5: ammo not lowered by 1 (%d instead of %d)" % [int(m0.data["ammo"]), ammo0 - 1])
		tac.hud.refresh()
		if not tac.hud.ammo_text().contains(str(ammo0 - 1)):
			fails = _hud3d_fail(fails, "H5: the HUD ammo_text does not mirror the ammo (%s)" % tac.hud.ammo_text())

	if fails == 0:
		print("HUD3D OK")
	else:
		print("HUD3D FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

## Window screenshot with the HUD (p3_1 §4c). fast=false -> portraits, HP/AP bars and
## the action bar sit as a CanvasLayer over the 3D scene and are caught by the snap.
func _hud3d_shots(outdir: String) -> void:
	print("HUD3D-SHOTS: to ", outdir)
	Sfx.muted = true
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	goto("tactical3d_combat")
	await current.battle_ready
	current.ui_select_slot(0)
	# Focus the camera on the selected merc and zoom in close.
	current.rig.focus_world(current.grid.cell_to_world(current.mercs[0].cell))
	current.rig.set_zoom(16.0)
	await _wait(0.6)
	await _snap(outdir + "/hud3d_01_overview.png")
	# Make the action-bar state "aim x1" visible.
	current.ui_aim()
	await _wait(0.3)
	await _snap(outdir + "/hud3d_02_aim.png")
	# FIX CHECK animation: two frames during "walk" -> they must differ.
	current.mercs[0].play_anim("walk")
	await _wait(0.15)
	await _snap(outdir + "/hud3d_03_walk_a.png")
	await _wait(0.45)
	await _snap(outdir + "/hud3d_04_walk_b.png")
	# FIX CHECK camera: a large pan -> the view must shift.
	current.rig.pan(Vector2(40.0, 0.0))
	await _wait(0.3)
	await _snap(outdir + "/hud3d_05_panned.png")
	# #1 FACING+LEGS: REALLY move the merc (do_move, not walk-in-place). do_move now
	# calls face_toward (turn into the walking direction) AND play_anim("walk").
	# Start do_move WITHOUT await (it is a coroutine) -> _wait/_snap catch it mid-move.
	# Towards the camera (world +X+Z) -> face; away from it (-X-Z) -> back.
	var mv = current.mercs[0]
	current.ui_select(mv)
	current.rig.set_zoom(6.0)
	var toward: Array = current.path_for(mv, mv.cell + Vector3i(4, 0, 4))
	if toward.size() < 2:
		toward = current.path_for(mv, mv.cell + Vector3i(3, 0, 3))
	var away: Array = current.path_for(mv, mv.cell + Vector3i(-4, 0, -4))
	if toward.size() > 1:
		current.rig.focus_world(current.grid.cell_to_world(toward[toward.size() / 2]))
		await _wait(0.15)
		current.do_move(mv, toward)
		await _wait(0.55)
		await _snap(outdir + "/hud3d_06_move_toward.png")
		await _wait(1.2)
	if away.size() > 1:
		current.rig.focus_world(current.grid.cell_to_world(away[away.size() / 2]))
		await _wait(0.15)
		current.do_move(mv, away)
		await _wait(0.55)
		await _snap(outdir + "/hud3d_07_move_away.png")
		await _wait(1.2)
	# BiA inventory (Back-in-Action look): shoot the INVENTORY tab and the STATS tab.
	current.ui_inventory()
	await _wait(0.6)
	await _snap(outdir + "/hud3d_08_inventar_bia.png")
	current.hud._inv_tab = 1
	current.hud._inv_refresh()
	await _wait(0.3)
	await _snap(outdir + "/hud3d_09_inventar_werte.png")
	current.hud.toggle_inventory()
	# HOUSE CHECK (door gap + wall fade, roofs removed): camera on village building 3
	# (VILLAGE_BUILDINGS[2], x0=14 z0=32, door (16,0,36)). Once at the default yaw,
	# once rotated 180 degrees -> the wall groups facing the camera must be
	# transparent (the interior is visible).
	current.rig.focus_world(current.grid.cell_to_world(Vector3i(16, 0, 34)))
	current.rig.set_zoom(10.0)
	await _wait(0.6)
	await _snap(outdir + "/hud3d_10_haus.png")
	current.rig.rotate_step(1)
	current.rig.rotate_step(1)
	await _wait(1.0)
	await _snap(outdir + "/hud3d_11_haus_gedreht.png")
	# JA2 crosshair (aiming via right click): shown directly, without a mouse hover.
	# With zone "kopf" -> label + zone arrow visible.
	current.hud.show_crosshair(Vector2(800.0, 400.0), 2, 3, "kopf")
	await _wait(0.2)
	await _snap(outdir + "/hud3d_12_fadenkreuz.png")
	current.hud.hide_crosshair()
	# Stances (C): shoot crouching + prone (fallback poses). The landing zone sits at
	# the map edge (camera clamping!) -> move both mercs into free cells near the
	# village centre first, then focus there.
	var hplaced: Array = []
	for hdz in range(0, 8):
		for hdx in range(0, 8):
			var hc := Vector3i(20 + hdx, 0, 38 + hdz)
			if hplaced.size() < 2 and current.grid.is_walkable(hc) and not current.occupied.has(hc):
				hplaced.append(hc)
	if hplaced.size() >= 2:
		_demo3d_place(current, current.mercs[1], hplaced[0])
		_demo3d_place(current, current.mercs[2], hplaced[1])
	current.set_stance(current.mercs[1], "crouch", true)
	current.set_stance(current.mercs[2], "prone", true)
	if hplaced.size() >= 2:
		current.rig.focus_world(current.grid.cell_to_world(hplaced[0]))
	current.rig.set_zoom(5.0)
	await _wait(1.4)
	await _snap(outdir + "/hud3d_13_haltungen.png")
	get_tree().quit()

## Verify the manor entrance visually (flat manor, door 57/58 z=14) plus the
## "explored" roof: enter -> the roof goes; leave again -> the roof MUST stay gone.
func _estate_shots(outdir: String) -> void:
	print("ESTATE-SHOTS: to ", outdir)
	Sfx.muted = true
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	goto("tactical3d_combat")
	await current.battle_ready
	var tac = current
	# South front of the manor: the door must read as an entrance. Lift the pivot to
	# y=0 (the field floor sits at -3 because of the cellar, otherwise the shot is off).
	tac.rig.focus_world(tac.grid.cell_to_world(Vector3i(58, 0, 8)))
	tac.rig.position.y = 0.0
	tac.rig.set_zoom(16.0)
	await _wait(0.8)
	await _snap(outdir + "/estate_01_front.png")
	tac.rig.focus_world(tac.grid.cell_to_world(Vector3i(58, 0, 12)))
	tac.rig.position.y = 0.0
	tac.rig.set_zoom(9.0)
	await _wait(0.4)
	await _snap(outdir + "/estate_02_eingang.png")
	# Put a merc in the doorway -> the roof goes, the boss is visible on LOS.
	_demo3d_place(tac, tac.mercs[0], Vector3i(57, 0, 14))
	tac.compute_vision()
	await _wait(0.5)
	await _snap(outdir + "/estate_03_betreten.png")
	# Back out onto the meadow -> the roof MUST stay gone ("explored").
	_demo3d_place(tac, tac.mercs[0], Vector3i(57, 0, 18))
	tac.compute_vision()
	await _wait(0.5)
	await _snap(outdir + "/estate_04_erkundet.png")
	# 5) Cellar lid: send a merc down to Tobias -> the floor above the hideout opens.
	if tac.captive != null:
		_demo3d_place(tac, tac.mercs[0], Vector3i(31, -1, 33))
		tac.compute_vision()
		tac.rig.focus_world(tac.grid.cell_to_world(Vector3i(32, -1, 32)))
		tac.rig.position.y = -3.0
		tac.rig.set_zoom(7.0)
		await _wait(0.5)
		await _snap(outdir + "/estate_05_keller.png")
	# 6) Bridge: wooden piers instead of a rock block (user: "looked like a house in the river").
	tac.rig.focus_world(tac.grid.cell_to_world(Vector3i(35, 0, 40)))
	tac.rig.position.y = 0.0
	tac.rig.set_zoom(8.0)
	await _wait(0.4)
	await _snap(outdir + "/estate_06_bruecke.png")
	get_tree().quit()


# ============================================================ Demo-Inhalt (Phase 7)

func _demo3d_fail(fails: int, msg: String) -> int:
	push_error("DEMO3D-ERROR: " + msg)
	print("DEMO3D-ERROR: ", msg)
	return fails + 1

## Cleanly relocates a unit onto a free cell (same pattern as _smoke3d_inventory I3).
func _demo3d_place(tac, u, c: Vector3i) -> void:
	tac._vacate(u.cell)
	u.set_cell(c)
	tac._occupy(u, c)

## Fresh bot battle (FIX K2): every sub-section with its own goto runs new_game() +
## set_difficulty() + hire() first, otherwise Tobias (who is in Game.team after the
## rescue) spawns twice — as a regular merc AND as the captive.
func _demo3d_fresh_battle() -> Node:
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	goto("tactical3d_combat")
	var tac = current
	await tac.battle_ready
	return tac

## Headless proof of the demo content (p7_1 §6.2): cellar/Tobias (D1/D2), the rescue
## (D3), base heal/resupply (D4), the commander logic firing exactly once (D5), the
## victory regression (D6) and the level guard K1 (D7). fast=true -> no UI, no audio,
## combat formulas untouched.
func _demo3d() -> void:
	print("DEMO3D: Start")
	var fails := 0

	# ---------- D1: map — cellar reachable, captive spawn walkable on level -1 -------
	var mp := Tac3DMapGen.generate(20260718, "leicht")
	var g: Grid3D = mp["grid"]
	var otto_spawn: Vector3i = mp["otto_spawn"]
	if otto_spawn.y != -1:
		fails = _demo3d_fail(fails, "D1: otto_spawn not on level -1 (%s)" % str(otto_spawn))
	if not g.is_walkable(otto_spawn):
		fails = _demo3d_fail(fails, "D1: otto_spawn not walkable (%s)" % str(otto_spawn))
	if not mp.has("keller_entrance"):
		fails = _demo3d_fail(fails, "D1: keller_entrance missing from the map")
	var pf := Pathfinder3D.new()
	pf.build(g)
	if not pf.reachable(mp["merc_spawns"][0], otto_spawn):
		fails = _demo3d_fail(fails, "D1: the cellar (otto_spawn) is not reachable from the merc spawn")
	print("DEMO3D: D1 map/cellar ok")

	# ---------- D2..D5: one fresh battle ----------
	var tac = await _demo3d_fresh_battle()
	# D2: Tobias spawned as the captive, NOT in mercs/enemies, flags still off.
	if tac.captive == null:
		fails = _demo3d_fail(fails, "D2: captive is null (Tobias did not spawn)")
	else:
		if tac.captive.cell != otto_spawn:
			fails = _demo3d_fail(fails, "D2: the captive does not stand on otto_spawn (%s)" % str(tac.captive.cell))
		if tac.captive in tac.mercs or tac.captive in tac.enemies or tac.captive in tac.units:
			fails = _demo3d_fail(fails, "D2: the captive is wrongly listed in mercs/enemies/units")
	if Game.otto_freed:
		fails = _demo3d_fail(fails, "D2: Game.otto_freed is true before the rescue")

	# D3: the rescue — put a living merc on a free cellar neighbour, then free_otto().
	if tac.captive != null:
		var cap: Tac3DUnit = tac.captive
		var m0: Tac3DUnit = tac.mercs[0]
		var neigh := Vector3i(-999, 0, -999)
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = cap.cell + d
			if n.y == cap.cell.y and tac.grid.is_walkable(n) and not tac.occupied.has(n):
				neigh = n
				break
		if neigh.x < -500:
			fails = _demo3d_fail(fails, "D3: no free cellar neighbour found next to the captive")
		else:
			_demo3d_place(tac, m0, neigh)
			var n0: int = tac.mercs.size()
			await tac.free_otto()
			if tac.captive != null:
				fails = _demo3d_fail(fails, "D3: captive is not null after free_otto")
			if tac.mercs.size() != n0 + 1:
				fails = _demo3d_fail(fails, "D3: mercs did not grow by 1 (%d instead of %d)" % [tac.mercs.size(), n0 + 1])
			if not (Game.otto_freed and Game.base_unlocked):
				fails = _demo3d_fail(fails, "D3: the flags otto_freed/base_unlocked were not set")
			if Game.team.is_empty() or String(Game.team.back()["id"]) != "otto":
				fails = _demo3d_fail(fails, "D3: Tobias was not appended to Game.team")
			var last: Tac3DUnit = tac.mercs.back()
			if not last.is_merc:
				fails = _demo3d_fail(fails, "D3: the freed Tobias is not is_merc")
			print("DEMO3D: D3 rescue ok")

	# D4: base — healing + resupply (for real).
	var mh: Tac3DUnit = tac.mercs[0]
	mh.data["hp"] = 1
	tac.base_heal_all()
	if int(mh.data["hp"]) != mh.hp_max():
		fails = _demo3d_fail(fails, "D4: base_heal_all did not heal to hp_max (%d/%d)" % [int(mh.data["hp"]), mh.hp_max()])
	mh.data["ammo"] = 0
	mh.data["inv"] = []
	tac.base_resupply_all()
	if int(mh.data["ammo"]) != int(Db.weapon(mh.data["weapon"])["mag"]):
		fails = _demo3d_fail(fails, "D4: base_resupply_all did not refill the sidearm (%d)" % int(mh.data["ammo"]))
	if (mh.data["inv"] as Array).size() <= 0:
		fails = _demo3d_fail(fails, "D4: base_resupply_all did not fill the pockets with magazines")
	print("DEMO3D: D4 base (heal/resupply) ok")

	# D5: commander logic — force the boss visible, check_boss_dialog() fires once.
	if tac.boss == null:
		fails = _demo3d_fail(fails, "D5: no boss on the map")
	else:
		Game.boss_dialog_seen = false
		tac.visible_cells[tac.boss.cell] = true
		var r: bool = await tac.check_boss_dialog()
		if not (r and Game.boss_dialog_seen):
			fails = _demo3d_fail(fails, "D5: check_boss_dialog did not return (true, boss_dialog_seen)")
		# A second call must NOT fire again (reentrancy guard).
		if await tac.check_boss_dialog():
			fails = _demo3d_fail(fails, "D5: check_boss_dialog fired a second time")
		print("DEMO3D: D5 commander logic ok")

	# ---------- D7: level guard (FIX K1) — fresh battle ----------
	var tac7 = await _demo3d_fresh_battle()
	if tac7.captive == null:
		fails = _demo3d_fail(fails, "D7: captive is null (Tobias did not spawn)")
	else:
		var cap7: Tac3DUnit = tac7.captive
		var m7: Tac3DUnit = tac7.mercs[0]
		# Wrong: the surface cell directly ABOVE the captive (level 0) — must NOT free him.
		var surface := Vector3i(cap7.cell.x, 0, cap7.cell.z)
		if not tac7.grid.is_walkable(surface):
			fails = _demo3d_fail(fails, "D7: the surface cell above the captive is not walkable (%s)" % str(surface))
		else:
			_demo3d_place(tac7, m7, surface)
			tac7.selected = m7
			tac7.player_turn = true
			tac7.busy = false
			await tac7.ui_interact()
			if tac7.captive == null:
				fails = _demo3d_fail(fails, "D7: Tobias was freed from the village surface (level bug K1!)")
			else:
				# Right: down in the cellar (level -1, flat-adjacent) — MUST free him.
				# Find a free flat-adjacent cellar neighbour (same level as the captive).
				var kn := Vector3i(-999, 0, -999)
				for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
					var n: Vector3i = cap7.cell + d
					if n.y == cap7.cell.y and tac7.grid.is_walkable(n) and not tac7.occupied.has(n):
						kn = n
						break
				if kn.x < -500:
					fails = _demo3d_fail(fails, "D7: no free cellar neighbour for the counter-test")
				else:
					_demo3d_place(tac7, m7, kn)
					tac7.selected = m7
					await tac7.ui_interact()
					if tac7.captive != null:
						fails = _demo3d_fail(fails, "D7: Tobias cannot be freed from the cellar (guard too strict)")
					else:
						print("DEMO3D: D7 level guard ok")

	# ---------- D6: victory regression — fresh battle + test boost (FIX K2) ----------
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	for m in Game.team:
		m["hp"] = int(m["hp"]) * 2 + 60
		m["hp_max"] = m["hp"]
		m["marks"] = mini(95, int(m["marks"]) + 15)
		var cal := String(Db.weapon(m["weapon"])["cal"])
		while (m["inv"] as Array).size() < Db.INV_SLOTS:
			m["inv"].append("mag_" + cal)
	Game.boss_dialog_seen = false
	goto("tactical3d_combat")
	var tac6 = current
	await tac6.battle_ready
	var res: String = await tac6.auto_battle()
	if res != "victory":
		fails = _demo3d_fail(fails, "D6: the bot squad did not win despite the captive (result '%s')" % res)
	elif tac6.captive == null:
		# The captive must not disturb the victory, and this bot run never frees him.
		fails = _demo3d_fail(fails, "D6: Tobias was unexpectedly freed during the bot run")
	else:
		print("DEMO3D: D6 victory regression ok (result %s)" % res)

	if fails == 0:
		print("DEMO3D OK")
	else:
		print("DEMO3D FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

## Window screenshots of the demo content (p7_1 §6.3, NEEDS a display — local only):
## the cellar with Tobias, the base panel, the commander beat. fast stays false, so
## the HUD and its panels exist.
func _demo3d_shots(outdir: String) -> void:
	print("DEMO3D-SHOTS: to ", outdir)
	Sfx.muted = true
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	goto("tactical3d_combat")
	var tac = current
	await tac.battle_ready

	# 1) Cellar: merc flat-adjacent to Tobias (level -1), camera down, active level -1.
	var cap: Tac3DUnit = tac.captive
	if cap != null:
		var m0: Tac3DUnit = tac.mercs[0]
		var neigh := cap.cell
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n: Vector3i = cap.cell + d
			if n.y == cap.cell.y and tac.grid.is_walkable(n) and not tac.occupied.has(n):
				neigh = n
				break
		tac._vacate(m0.cell)
		m0.set_cell(neigh)
		tac._occupy(m0, neigh)
		tac.selected = m0
		if tac.picker != null:
			tac.picker.set_active_level(-1)
		tac.rig.focus_world(tac.grid.cell_to_world(cap.cell))
		tac.rig.set_zoom(10.0)
		tac.compute_vision()
		await _wait(0.6)
		await _snap(outdir + "/demo3d_01_keller.png")

		# 2) Base panel: free_otto() opens show_base_panel (await base_closed) — do NOT
		#    await it blockingly; the panel builds synchronously up to that await.
		tac.free_otto()
		await _wait(0.5)
		await _snap(outdir + "/demo3d_02_basis.png")
		# Close the panel so the commander beat is unobstructed.
		if tac.hud != null:
			tac.hud.base_closed.emit()
		await _wait(0.3)

	# 3) Commander beat: force the boss visible, check_boss_dialog() opens the panel.
	if tac.boss != null:
		Game.boss_dialog_seen = false
		tac.visible_cells[tac.boss.cell] = true
		tac.check_boss_dialog()
		await _wait(0.6)
		await _snap(outdir + "/demo3d_03_vargo.png")
	print("DEMO3D-SHOTS: done")
	get_tree().quit()

# ============================================================ 3D-Juice / Game-Feel (Phase 4)

## Window screenshot of a shot MID-battle with the juice effects visible (muzzle
## flash/tracer/damage number/blood, screenshake, hitstop). Runs interactively (fast
## stays false) -> juice exists. Deterministic asserts (FIX F4): after the shot the
## juice child count is > 0, and after a short wait Engine.time_scale == 1.0. The
## label/blood are only checked "if it hit" (hit_chance is clamped to 5-95, so ~5%
## misses — no hard assert).
func _juice_shots(outdir: String) -> void:
	print("JUICE-SHOTS: to ", outdir)
	Sfx.muted = true
	# Do NOT throttle the window: an unfocused/vsync-paced window renders so slowly that
	# the short (~60-100 ms) muzzle/tracer effects expire between trigger and snap.
	# Uncapped + vsync off => frame latency << effect lifetime, so the snap catches it.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	seed(20260718)   # deterministic global RNG for the hit roll
	var fails := 0

	# 1) Set up the default squad + an accuracy boost so the shot almost surely hits.
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	for m in Game.team:
		m["marks"] = 95

	# 2) Open the battle (interactive -> juice gets built).
	goto("tactical3d_combat")
	var tac = current
	await tac.battle_ready
	if tac.juice == null:
		push_error("JUICE-SHOTS: juice is null (is fast wrongly active?)")
		fails += 1

	# 3) Deterministic duel: place the enemy as FAR out in open terrain as possible
	#    (longest free cardinal run from the merc), so the muzzle flash and tracer do
	#    not vanish inside the squad huddle. marks=95 keeps the hit likely even at
	#    range; muzzle/tracer are hit-independent anyway. Fallback = the old short list.
	var merc = tac.mercs[0]
	var foe = tac.enemies[0]
	var duel_gap := 5
	var shoot_from: Vector3i = merc.cell + Vector3i(3, 0, 0)
	var best_run := 0
	for dir in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var dv: Vector3i = dir
		var run := 0
		for step in range(1, duel_gap + 1):
			var cand: Vector3i = merc.cell + dv * step
			if tac.grid.is_walkable(cand) and not tac.occupied.has(cand):
				run = step
			else:
				break
		if run > best_run:
			best_run = run
			shoot_from = merc.cell + dv * run
	if best_run < 3:
		for cand in [merc.cell + Vector3i(3, 0, 0), merc.cell + Vector3i(0, 0, 3), merc.cell + Vector3i(-3, 0, 0), merc.cell + Vector3i(0, 0, -3), merc.cell + Vector3i(2, 0, 0)]:
			var c2: Vector3i = cand
			if tac.grid.is_walkable(c2) and not tac.occupied.has(c2):
				shoot_from = c2
				break
	tac._vacate(foe.cell)
	foe.set_cell(shoot_from)
	tac._occupy(foe, shoot_from)
	foe.set_seen(true)
	merc.ap = 99
	tac.combat_started = true
	tac.compute_vision()

	# 4) Camera on the duel (zoomed so shooter, target, tracer and damage number fit).
	tac.rig.focus_world((tac.grid.cell_to_world(merc.cell) + tac.grid.cell_to_world(foe.cell)) * 0.5)
	tac.rig.set_zoom(14.0)
	await _wait(0.4)
	await _snap(outdir + "/juice_00_setup.png")

	# 5) Fire: shoot() is a coroutine — the muzzle/tracer block runs synchronously up to
	#    the first `await dl(0.13)`, after which control returns to us immediately. Do
	#    NOT await it blockingly (the effects live only ~60 ms, so the snap must follow
	#    the trigger directly). Remember the child count first.
	var before: int = tac.juice.get_child_count()
	tac.shoot(merc, foe)
	await _snap(outdir + "/juice_01_shot.png")
	# FIX F4: deterministic assert — effect nodes exist after the shot.
	if tac.juice.get_child_count() <= before:
		push_error("JUICE-SHOTS: no effect nodes after the shot (%d)" % tac.juice.get_child_count())
		fails += 1
	# The screenshake fired (shot kick, hit-independent).
	if tac.rig.trauma <= 0.0:
		push_error("JUICE-SHOTS: no trauma after the shot (screenshake did not fire)")
		fails += 1

	# 6) Wait briefly -> the hit lands (after dl 0.13): blood + damage number + flash.
	await _wait(0.2)
	var has_label := false
	for c in tac.juice.get_children():
		if c is Label3D:
			has_label = true
			break
	await _snap(outdir + "/juice_02_damage.png")
	# Label/blood only "if it hit" — no hard assert (see the doc comment above).
	print("JUICE-SHOTS: hit confirmed (damage number visible)" if has_label else "JUICE-SHOTS: miss (no label — hit-dependent, ok)")

	# 7) FIX F4: the sharpest guard — after the hitstop time_scale is back at 1.0.
	await _wait(0.5)
	if Engine.time_scale != 1.0:
		push_error("JUICE-SHOTS: time_scale did not return to 1.0 (%.3f) — hitstop reset trap!" % Engine.time_scale)
		fails += 1

	if fails == 0:
		print("JUICE OK")
	else:
		print("JUICE FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)

# ============================================================ §8.9 umbrella run (--smoke)

## Generic failure reporter for the checks that are shared between modes.
func _chk_fail(tag: String, fails: int, msg: String) -> int:
	push_error("%s-ERROR: %s" % [tag, msg])
	print("%s-ERROR: %s" % [tag, msg])
	return fails + 1


## Removes every save file (autosave + all manual slots) so a probe starts and
## ends on a clean disk.
func _wipe_all_slots() -> void:
	for slot in range(Game.AUTOSAVE_SLOT, Game.SLOT_COUNT + 1):
		Game.delete_save(slot)


## The test boost --smoke3d has always used: the bot plays coarsely, so the full
## victory path only holds with beefed-up mercs. Touches ONLY the runtime dicts in
## Game.team — no combat formula is changed.
func _boost_team() -> void:
	for m in Game.team:
		var md: Dictionary = m
		md["hp"] = int(md["hp"]) * 2 + 60
		md["hp_max"] = md["hp"]
		md["marks"] = mini(95, int(md["marks"]) + 15)
		var cal := String(Db.weapon(md["weapon"])["cal"])
		while (md["inv"] as Array).size() < Db.INV_SLOTS:
			md["inv"].append("mag_" + cal)


## Hiring (§8.9). Leaves a 4-merc squad on "leicht" behind — callers rely on that.
func _check_hire(fails: int) -> int:
	Game.new_game()
	Game.set_difficulty("leicht")
	if not Game.hire("ivan"):
		fails = _chk_fail("HIRE", fails, "H1: could not hire Ivan")
	if not Game.hire("fuchs"):
		fails = _chk_fail("HIRE", fails, "H1: could not hire Fuchs")
	if not Game.hire("doc"):
		fails = _chk_fail("HIRE", fails, "H1: could not hire Doc")
	if Game.hire("blitz"):
		fails = _chk_fail("HIRE", fails, "H1: Blitz should have failed on budget")
	if not Game.hire("nadel"):
		fails = _chk_fail("HIRE", fails, "H1: could not hire Nadel")
	if Game.team.size() != 4 or Game.budget != 0:
		fails = _chk_fail("HIRE", fails, "H1: team %d / budget %d — expected 4 / 0" % [Game.team.size(), Game.budget])
	# H2: price factor SCHWER == 1.5
	Game.set_difficulty("schwer")
	if Game.eff_cost(1000) != 1500:
		fails = _chk_fail("HIRE", fails, "H2: SCHWER price factor wrong: %d" % Game.eff_cost(1000))
	Game.set_difficulty("leicht")
	return fails


## §8.9 map reachability, INCLUDING the level-0 <-> level-(-1) stair link. The
## cellar hatch is the only place in the demo where two levels touch. If that link
## breaks, Tobias is unreachable and the demo is unwinnable — yet every purely flat
## reachability test would still pass. So the link is asserted explicitly, on the
## grid AND in the AStar graph the pathfinder actually walks.
func _check_map_reach(fails: int) -> int:
	var mp := Tac3DMapGen.generate(20260718, "leicht", "F3")
	var g: Grid3D = mp["grid"]
	var entrance: Vector3i = mp["keller_entrance"]
	var otto_spawn: Vector3i = mp["otto_spawn"]
	var spawn0: Vector3i = mp["merc_spawns"][0]

	# R1: both levels exist at all.
	var has_l0 := false
	var has_lm1 := false
	for k in g.all_cells():
		var c: Vector3i = k
		if c.y == 0:
			has_l0 = true
		elif c.y == -1:
			has_lm1 = true
	if not (has_l0 and has_lm1):
		fails = _chk_fail("MAPREACH", fails, "R1: missing level (L0=%s, L-1=%s)" % [str(has_l0), str(has_lm1)])

	# R2: hatch and captive cell are real, walkable, on the expected levels.
	if entrance == Tac3DMapGen.NO_CELL or not g.is_walkable(entrance):
		fails = _chk_fail("MAPREACH", fails, "R2: keller_entrance missing/blocked (%s)" % str(entrance))
	elif entrance.y != 0:
		fails = _chk_fail("MAPREACH", fails, "R2: keller_entrance not on level 0 (%s)" % str(entrance))
	if otto_spawn.y != -1 or not g.is_walkable(otto_spawn):
		fails = _chk_fail("MAPREACH", fails, "R2: otto_spawn not walkable on level -1 (%s)" % str(otto_spawn))

	# R3: the STAIR LINK itself — the hatch carries an explicit level link and one
	# of its neighbours really sits on level -1.
	if not g.has_link(entrance):
		fails = _chk_fail("MAPREACH", fails, "R3: keller_entrance carries no level link (%s)" % str(entrance))
	var down := Vector3i(-999, 0, -999)
	for n in g.neighbors(entrance):
		var nc: Vector3i = n
		if nc.y == -1:
			down = nc
			break
	if down.x < -500:
		fails = _chk_fail("MAPREACH", fails, "R3: no level -1 neighbour of the hatch — stair link broken")

	# R4: the link survives into the AStar graph (a link the pathfinder cannot see
	# is worthless), and the captive is reachable from the landing point.
	var pf := Pathfinder3D.new()
	pf.build(g)
	var id_up := pf.point_id(entrance)
	var id_down := pf.point_id(down)
	if id_up < 0 or id_down < 0:
		fails = _chk_fail("MAPREACH", fails, "R4: hatch/cellar missing as AStar points (%d/%d)" % [id_up, id_down])
	elif not pf.astar.are_points_connected(id_up, id_down):
		fails = _chk_fail("MAPREACH", fails, "R4: level 0 <-> level -1 not connected in the AStar")
	if not pf.reachable(spawn0, otto_spawn):
		fails = _chk_fail("MAPREACH", fails, "R4: captive not reachable from the merc spawn")
	var boss_home: Vector3i = mp["boss_home"]
	if not pf.reachable(spawn0, boss_home):
		fails = _chk_fail("MAPREACH", fails, "R4: boss_home not reachable from the merc spawn")
	print("SMOKE: map reachability + level-0 <-> level-(-1) stair link checked")
	return fails


## §5.2 step 5 — voice coverage. The manifest is the single source of truth for
## every spoken line. 41 of 90 lines are deliberately "pending" (no TTS was ever
## generated — a binding user decision), so PENDING IS NOT A FAILURE. Only a
## MISMATCH between the declared status and what is on disk counts: "present"
## without a file, or "pending" with a file lying around.
func _check_voice(fails: int) -> int:
	var man: Dictionary = Sfx.voice_manifest()
	if man.is_empty():
		return _chk_fail("VOICE", fails, "V1: voice manifest empty or unreadable")
	var dir := String(man.get("voice_dir", "res://assets/sfx/voice/"))
	if not dir.ends_with("/"):
		dir += "/"
	var chars: Variant = man.get("characters", {})
	if typeof(chars) != TYPE_DICTIONARY:
		return _chk_fail("VOICE", fails, "V1: manifest carries no 'characters' dictionary")
	var total := 0
	var present := 0
	var pending := 0
	for ck in (chars as Dictionary):
		var cid := String(ck)
		var centry: Variant = (chars as Dictionary)[ck]
		if typeof(centry) != TYPE_DICTIONARY:
			continue
		var lines: Variant = (centry as Dictionary).get("lines", {})
		if typeof(lines) != TYPE_DICTIONARY:
			continue
		for lk in (lines as Dictionary):
			var raw: Variant = (lines as Dictionary)[lk]
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			var ld: Dictionary = raw
			total += 1
			var file := String(ld.get("file", ""))
			var status := String(ld.get("status", ""))
			if file == "":
				fails = _chk_fail("VOICE", fails, "V2: %s.%s carries no 'file' entry" % [cid, String(lk)])
				continue
			var on_disk := FileAccess.file_exists(dir + file)
			if status == "present":
				present += 1
				if not on_disk:
					fails = _chk_fail("VOICE", fails, "V3: %s.%s says 'present' but %s is not on disk" % [cid, String(lk), file])
			elif status == "pending":
				pending += 1
				if on_disk:
					fails = _chk_fail("VOICE", fails, "V3: %s.%s says 'pending' but %s exists on disk" % [cid, String(lk), file])
			else:
				fails = _chk_fail("VOICE", fails, "V2: %s.%s has unknown status '%s'" % [cid, String(lk), status])
	print("SMOKE: voice manifest — %d lines, %d present, %d pending (pending is not a failure)" % [total, present, pending])
	if total == 0:
		fails = _chk_fail("VOICE", fails, "V1: manifest lists no lines at all")
	return fails


## Cheap screen smoke (§8.1 "opens without script errors"): every entry in SCREENS
## is instantiated once and must survive a frame. This is the only thing that ever
## touches loading.gd / difficulty.gd / end_screen.gd / hideout.gd, so a broken
## _ready() in one of them would otherwise ship unnoticed. Runs with fast=false on
## purpose, so the interactive branches (HUD, cursor, juice, hideout room) are
## really built.
func _check_screens(fails: int) -> int:
	var was_fast := fast
	var was_sector := start_sector
	fast = false
	start_sector = ""
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	Game.mission_result = "victory"
	for key in SCREENS:
		var skey := String(key)
		goto(skey)
		# loading.gd runs a TIMED coroutine that ends in goto("tactical3d_combat").
		# Flagging it finished makes its wait loops return immediately, so it winds
		# down within a frame instead of hijacking the router mid-test.
		if skey == "loading" and current != null:
			current.set("_finished", true)
		await get_tree().process_frame
		if current == null:
			fails = _chk_fail("SCREENS", fails, "S1: goto('%s') left current == null" % skey)
		elif not is_instance_valid(current):
			fails = _chk_fail("SCREENS", fails, "S1: screen '%s' was freed immediately" % skey)
		else:
			print("SMOKE: screen '%s' opens" % skey)
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = null
	fast = was_fast
	start_sector = was_sector
	return fails


# ============================================================ §8.2 full loop (--loop)

## F4 -> west exit -> F3 -> loot -> rescue -> base -> bot battle -> end card.
## HANG LAW: every wait here is bounded by a frame counter or by a helper that
## provably terminates (auto_battle caps itself at 300 rounds). Nothing awaits an
## open-ended signal.
func _check_loop(fails: int) -> int:
	var t := "LOOP"
	Sfx.muted = true
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	_boost_team()
	Game.delete_save(Game.AUTOSAVE_SLOT)

	# ---------- L1: F4 builds as the landing zone ----------
	start_sector = "F4"
	goto("tactical3d_combat")
	var tac = current
	await tac.battle_ready
	start_sector = ""              # never leak the injection into a later mode
	if String(tac.sector) != "F4":
		fails = _chk_fail(t, fails, "L1: sector is '%s' instead of 'F4'" % String(tac.sector))
	if (tac.exit_cells as Dictionary).is_empty():
		fails = _chk_fail(t, fails, "L1: F4 has no exit_cells — no way west")
	if tac.captive != null:
		fails = _chk_fail(t, fails, "L1: F4 must not hold the captive")
	if tac.boss != null:
		fails = _chk_fail(t, fails, "L1: F4 must not hold the boss")
	if (tac.mercs as Array).size() != 4:
		fails = _chk_fail(t, fails, "L1: %d mercs instead of 4" % (tac.mercs as Array).size())
	if tac.combat_started:
		fails = _chk_fail(t, fails, "L1: combat already running at the landing zone")

	# ---------- L2: a merc falls in F4 ----------
	var victim_id := ""
	if (tac.mercs as Array).size() >= 4:
		var victim: Tac3DUnit = tac.mercs[3]
		victim_id = String(victim.data.get("id", ""))
		victim.hurt(victim.hp() + 10)
		await tac.on_death(null, victim)
		if victim.alive or bool(victim.data.get("alive", true)):
			fails = _chk_fail(t, fails, "L2: '%s' did not end up dead" % victim_id)
		if tac.battle_over:
			fails = _chk_fail(t, fails, "L2: one casualty already ended the battle")

	# ---------- L3: drive the squad west, out of the sector ----------
	# The exit tile FURTHEST from every enemy wins: reaching the edge must not trip
	# a sighting first, because _handle_edge is a no-op once combat has started.
	var mover: Tac3DUnit = null
	for m in tac.mercs:
		var mm: Tac3DUnit = m
		if mm.alive:
			mover = mm
			break
	var exit_cell := Vector3i(-999, 0, -999)
	var stage_cell := Vector3i(-999, 0, -999)
	var best_d := -1.0
	for k in (tac.exit_cells as Dictionary):
		var ec: Vector3i = k
		var stage: Vector3i = ec + Vector3i(1, 0, 0)
		if not tac.grid.is_walkable(stage) or tac.occupied.has(stage) or tac.occupied.has(ec):
			continue
		var d := 99999.0
		for e in tac.enemies:
			var en: Tac3DUnit = e
			d = minf(d, Tac3DVision.flat(ec).distance_to(en.flat()))
		if d > best_d:
			best_d = d
			exit_cell = ec
			stage_cell = stage
	if mover == null or exit_cell.x < -500:
		fails = _chk_fail(t, fails, "L3: no usable exit tile with a free approach cell")
	else:
		_demo3d_place(tac, mover, stage_cell)
		mover.ap = mover.ap_max
		await tac.do_move(mover, [stage_cell, exit_cell])
		# _handle_edge defers _enter_sector — wait for it with a BOUNDED counter.
		var spins := 0
		while String(tac.sector) != "F3" and spins < 120:
			spins += 1
			await get_tree().process_frame
		if String(tac.sector) != "F3":
			fails = _chk_fail(t, fails, "L3: no transition into F3 after %d frames (still '%s', combat_started=%s)" % [spins, String(tac.sector), str(tac.combat_started)])

	if String(tac.sector) != "F3":
		# Everything below needs the F3 map. Report and stop rather than fake it.
		print("LOOP: F3 was never reached — the rescue/end-card steps were skipped")
		Game.delete_save(Game.AUTOSAVE_SLOT)
		return fails

	# ---------- L4: F3 is live and the F4 casualty STAYED dead ----------
	if Game.sector != "F3":
		fails = _chk_fail(t, fails, "L4: Game.sector is '%s' instead of 'F3'" % Game.sector)
	if tac.captive == null:
		fails = _chk_fail(t, fails, "L4: F3 holds no captive")
	if (tac.mercs as Array).size() != 3:
		fails = _chk_fail(t, fails, "L4: %d mercs after the transition instead of 3" % (tac.mercs as Array).size())
	for m in tac.mercs:
		var mm2: Tac3DUnit = m
		if String(mm2.data.get("id", "")) == victim_id:
			fails = _chk_fail(t, fails, "L4: '%s' fell in F4 but was resurrected in F3" % victim_id)
	for td in Game.team:
		var tdd: Dictionary = td
		if String(tdd.get("id", "")) == victim_id and bool(tdd.get("alive", true)):
			fails = _chk_fail(t, fails, "L4: the Game.team entry of '%s' is alive again" % victim_id)
	if not Game.has_save(Game.AUTOSAVE_SLOT):
		fails = _chk_fail(t, fails, "L4: the sector transition wrote no autosave")
	print("LOOP: L1-L4 F4 -> F3 transition ok (casualty stayed dead)")

	# ---------- L5: loot (§8.9) — crate mechanics on the live F3 map ----------
	fails = _smoke3d_inventory(tac, fails)
	await get_tree().process_frame
	tac.busy = false
	tac.player_turn = true

	# ---------- L6: rescue Tobias out of the cellar ----------
	var cap: Tac3DUnit = tac.captive
	if cap == null:
		fails = _chk_fail(t, fails, "L6: no captive to free")
	else:
		var rescuer: Tac3DUnit = null
		for m in tac.mercs:
			var mm3: Tac3DUnit = m
			if mm3.alive:
				rescuer = mm3
				break
		var neigh := Vector3i(-999, 0, -999)
		for d2 in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var n2: Vector3i = cap.cell + d2
			if n2.y == cap.cell.y and tac.grid.is_walkable(n2) and not tac.occupied.has(n2):
				neigh = n2
				break
		if rescuer == null or neigh.x < -500:
			fails = _chk_fail(t, fails, "L6: no free cellar cell next to the captive")
		else:
			_demo3d_place(tac, rescuer, neigh)
			tac.selected = rescuer
			tac.player_turn = true
			tac.busy = false
			await tac.ui_interact()
			if tac.captive != null:
				fails = _chk_fail(t, fails, "L6: ui_interact did not free Tobias")
			if not Game.otto_freed:
				fails = _chk_fail(t, fails, "L6: Game.otto_freed not set")
			if not Game.base_unlocked:
				fails = _chk_fail(t, fails, "L6: Game.base_unlocked not set — no home base")
			if Game.team.is_empty() or String(Game.team.back()["id"]) != "otto":
				fails = _chk_fail(t, fails, "L6: Tobias was not appended to Game.team")
			else:
				print("LOOP: L6 rescue ok (Tobias joined the squad)")

	# ---------- L7: the base beats — heal and resupply ----------
	if not (tac.mercs as Array).is_empty():
		var medic: Tac3DUnit = tac.mercs[0]
		medic.data["hp"] = 1
		tac.base_heal_all()
		if int(medic.data["hp"]) != medic.hp_max():
			fails = _chk_fail(t, fails, "L7: base_heal_all did not heal to hp_max (%d/%d)" % [int(medic.data["hp"]), medic.hp_max()])
		medic.data["ammo"] = 0
		tac.base_resupply_all()
		if int(medic.data["ammo"]) != int(Db.weapon(medic.data["weapon"])["mag"]):
			fails = _chk_fail(t, fails, "L7: base_resupply_all did not refill the sidearm")
		else:
			print("LOOP: L7 base heal + resupply ok")

	# ---------- L8: bot battle through to victory ----------
	# Tobias joins unboosted and one merc is down — re-boost the SURVIVORS so the
	# coarse bot can still close it out (same technique --smoke3d uses).
	for m in tac.mercs:
		var mb: Tac3DUnit = m
		if not mb.alive:
			continue
		mb.data["hp"] = mb.hp_max() * 2 + 60
		mb.data["hp_max"] = mb.data["hp"]
		mb.data["marks"] = 95
		var cal2 := String(Db.weapon(mb.data["weapon"])["cal"])
		while (mb.data["inv"] as Array).size() < Db.INV_SLOTS:
			mb.data["inv"].append("mag_" + cal2)
	Game.boss_dialog_seen = false
	var res: String = await tac.auto_battle()
	print("LOOP: battle result = %s after %d turns" % [res, int(Game.stats["turns"])])
	if res != "victory":
		fails = _chk_fail(t, fails, "L8: bot squad did not win (result '%s')" % res)

	# ---------- L9: the end card ----------
	# Cleared on purpose: the END SCREEN has to set it, not this probe.
	Game.demo_finished = false
	goto("end")
	await get_tree().process_frame
	if current == null:
		fails = _chk_fail(t, fails, "L9: end screen did not open")
	elif not Game.demo_finished:
		fails = _chk_fail(t, fails, "L9: end card did not set Game.demo_finished (result '%s', otto_freed %s)" % [Game.mission_result, str(Game.otto_freed)])
	else:
		print("LOOP: L9 demo end card reached")

	Game.delete_save(Game.AUTOSAVE_SLOT)
	return fails


func _loop_probe() -> void:
	print("LOOP: Start")
	Sfx.muted = true
	var fails := await _check_loop(0)
	if fails == 0:
		print("LOOP OK")
	else:
		print("LOOP FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)


# ============================================================ §8.6 damaged save slots

## Slots 1..3 plus the autosave, and the two ways a save file can be bad: garbage
## on disk and a foreign schema version. Neither may crash, both must be refused by
## load_game() and correctly reported by save_info() / slot_state().
func _check_bad_slots(fails: int) -> int:
	_wipe_all_slots()
	DirAccess.make_dir_recursive_absolute(Game.SAVE_DIR)

	# ---------- M9: slots 1..3 + autosave each hold their own state ----------
	var slots := [1, 2, 3, Game.AUTOSAVE_SLOT]
	for s in slots:
		var slot: int = s
		Game.new_game()
		Game.hire("nadel")
		Game.day = 2 + slot
		Game.sector = "F3"
		if not Game.save_game(slot, "Slot %d" % slot):
			fails = _menu_fail(fails, "M9: save_game(%d) failed" % slot)
		if not Game.has_save(slot):
			fails = _menu_fail(fails, "M9: slot %d has no file" % slot)
	for s in slots:
		var slot2: int = s
		Game.new_game()
		if not Game.load_game(slot2):
			fails = _menu_fail(fails, "M9: load_game(%d) failed" % slot2)
		elif Game.day != 2 + slot2:
			fails = _menu_fail(fails, "M9: slot %d carries day %d instead of %d" % [slot2, Game.day, 2 + slot2])
		var inf := Game.save_info(slot2)
		if inf.is_empty() or bool(inf.get("damaged", false)) or bool(inf.get("incompatible", false)):
			fails = _menu_fail(fails, "M9: save_info(%d) reports a healthy slot as unusable" % slot2)
	print("MENU: M9 slots 1..3 + autosave ok")

	# ---------- M10: garbage file ----------
	var junk_slot := 4
	var jf := FileAccess.open(Game.save_path(junk_slot), FileAccess.WRITE)
	if jf == null:
		fails = _menu_fail(fails, "M10: could not write the garbage file")
	else:
		jf.store_string("{ this is not json ][ truncated")
		jf.close()
	Game.new_game()
	var team_before := Game.team.size()
	if Game.load_game(junk_slot):
		fails = _menu_fail(fails, "M10: load_game accepted a garbage file")
	if Game.team.size() != team_before:
		fails = _menu_fail(fails, "M10: the rejected load still touched the runtime state")
	var ji := Game.save_info(junk_slot)
	if ji.is_empty() or not bool(ji.get("damaged", false)):
		fails = _menu_fail(fails, "M10: save_info does not report the garbage file as damaged (%s)" % str(ji))
	if not Game.slot_is_damaged(junk_slot):
		fails = _menu_fail(fails, "M10: slot_state is not DAMAGED (%d)" % Game.slot_state(junk_slot))

	# ---------- M11: foreign schema version ----------
	var ver_slot := 5
	var vf := FileAccess.open(Game.save_path(ver_slot), FileAccess.WRITE)
	if vf == null:
		fails = _menu_fail(fails, "M11: could not write the version file")
	else:
		vf.store_string(JSON.stringify({"version": 999}))
		vf.close()
	if Game.load_game(ver_slot):
		fails = _menu_fail(fails, "M11: load_game accepted a foreign save version")
	var vi := Game.save_info(ver_slot)
	if vi.is_empty() or not bool(vi.get("incompatible", false)):
		fails = _menu_fail(fails, "M11: save_info does not report version 999 as incompatible (%s)" % str(vi))
	if bool(vi.get("damaged", false)):
		fails = _menu_fail(fails, "M11: version 999 was additionally flagged as damaged")
	if not Game.slot_is_incompatible(ver_slot):
		fails = _menu_fail(fails, "M11: slot_state is not INCOMPATIBLE (%d)" % Game.slot_state(ver_slot))
	# Broken files must not win the "most recent save" race either.
	var latest := Game.latest_slot()
	if latest == junk_slot or latest == ver_slot:
		fails = _menu_fail(fails, "M11: latest_slot picked the broken slot %d" % latest)
	print("MENU: M10/M11 damaged + incompatible slots ok")

	# ---------- M12: the load screen still builds with broken files present ----------
	goto("load_game")
	await get_tree().process_frame
	if current == null:
		fails = _menu_fail(fails, "M12: load screen did not open with broken saves present")
	else:
		print("MENU: M12 load screen with broken saves ok")
	_wipe_all_slots()
	return fails


# ============================================================ §8.1 language gate (--lang)

## Umlauts and eszett — the cheapest unambiguous German signal.
const LANG_UMLAUTS := "äöüÄÖÜß"

## German function words and game vocabulary, matched as WHOLE WORDS only (so
## "die" can never fire inside "soldier"). Umlaut spelling AND the ASCII
## transliteration are listed, because this codebase used both.
const LANG_WORDS := [
	"der", "die", "das", "den", "dem", "des", "ein", "eine", "einen", "einem",
	"und", "oder", "nicht", "kein", "keine", "wird", "werden", "wurde",
	"soeldner", "söldner", "gegner", "waffe", "waffen", "munition",
	"runde", "runden", "kampf", "kiste", "kisten", "feld", "felder",
	"zelle", "zellen", "taste", "tasten", "auswahl", "schwierigkeit",
	"zurueck", "zurück", "weiter", "beenden", "abbrechen", "speichern",
	"laden", "anheuern", "schuss", "treffer", "sieg", "niederlage",
	"waehlen", "wählen", "ziel", "ziele", "punkte", "leben", "toten",
]

## Ids FROZEN by contract (difficulty keys, hit zones, stances, item and merc ids,
## animation clips, bone and node-group names). Several of them are German words —
## but they are internal keys, never player-facing text, and renaming any of them
## breaks the game and the harness. A literal that IS one of these is never an
## offender, no matter which sink it sits on.
const LANG_ALLOW := [
	"leicht", "normal", "schwer",
	"kopf", "beine", "torso",
	"stand", "crouch", "prone",
	"flinte", "granate", "drachenmaul", "medkit", "cellar_key",
	"mag_schrot", "mag_9mm", "mag_45", "mag_762", "schrot",
	"otto", "walross", "nadel", "opa", "schatten", "fuchs", "ivan", "doc", "blitz",
	"p9", "k45", "svd", "tac3d_units", "wrist.r",
]

## UI sinks — a German string reaching one of these is READABLE IN GAME. Comments
## are deliberately out of scope (they are migrated separately and are not
## reachable in-game). The quoted entries catch player-visible DATA fields in
## db.gd-style dictionaries, which end up in the UI verbatim.
const LANG_SINKS := [
	".text", ".tooltip_text", ".placeholder_text",
	"UiTheme.lbl(", "UiTheme.header(", "UiTheme.btn(",
	"banner(", "set_hint(",
	"\"name\":", "\"nick\":", "\"quote\":", "\"bio\":", "\"desc\":",
	"\"short\":", "\"label\":", "\"title\":", "\"text\":",
]


func _lang_probe() -> void:
	print("LANG: Start")
	var fails := _check_lang(0)
	if fails == 0:
		print("LANG OK")
	else:
		print("LANG FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _check_lang(fails: int) -> int:
	var gd_files: Array = []
	var json_files: Array = []
	_lang_collect("res://scripts", ".gd", gd_files)
	_lang_collect("res://data", ".json", json_files)
	# A walker that finds nothing would make the gate silently pass forever.
	if gd_files.is_empty():
		return _chk_fail("LANG", fails, "G0: no .gd file under res://scripts — the DirAccess walk is broken")
	gd_files.sort()
	json_files.sort()
	var offenders: Array = []
	for p in gd_files:
		_lang_scan_gd(String(p), offenders)
	for p in json_files:
		_lang_scan_json(String(p), offenders)
	print("LANG: scanned %d .gd + %d .json files" % [gd_files.size(), json_files.size()])
	if offenders.is_empty():
		print("LANG: no German player-facing strings found")
		return fails
	print("LANG: %d German player-facing string(s):" % offenders.size())
	for o in offenders:
		print("  ", String(o))
	return _chk_fail("LANG", fails, "G1: %d German player-facing string(s) — see the list above" % offenders.size())


## Recursive DirAccess walk. A fresh DirAccess per level, so the recursion never
## disturbs the caller's iteration state.
func _lang_collect(dir_path: String, ext: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var full := dir_path.path_join(entry)
			if d.current_is_dir():
				_lang_collect(full, ext, out)
			elif entry.ends_with(ext):
				out.append(full)
		entry = d.get_next()
	d.list_dir_end()


func _lang_scan_gd(path: String, offenders: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var lineno := 0
	while not f.eof_reached():
		var raw := f.get_line()
		lineno += 1
		var code := _lang_code_part(raw)
		if code.strip_edges().is_empty():
			continue
		if not _lang_is_sink(code):
			continue
		for lit in _lang_literals(code):
			var s := String(lit)
			var marker := _lang_marker(s)
			if marker != "":
				offenders.append("%s:%d  [%s]  \"%s\"" % [path, lineno, marker, s])
	f.close()


func _lang_scan_json(path: String, offenders: Array) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var lineno := 0
	while not f.eof_reached():
		var raw := f.get_line()
		lineno += 1
		for lit in _lang_literals(raw):
			var s := String(lit)
			# Keys are internal identifiers; values are what the player reads.
			if _lang_json_is_key(raw, s):
				continue
			var marker := _lang_marker(s)
			if marker != "":
				offenders.append("%s:%d  [%s]  \"%s\"" % [path, lineno, marker, s])
	f.close()


## The CODE part of a GDScript line: everything before the first "#" that sits
## OUTSIDE a string literal. Comments are explicitly not player-facing.
func _lang_code_part(line: String) -> String:
	var in_str := false
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if in_str:
			if ch == "\\":
				i += 2
				continue
			if ch == quote:
				in_str = false
		elif ch == "\"" or ch == "'":
			in_str = true
			quote = ch
		elif ch == "#":
			return line.substr(0, i)
		i += 1
	return line


## All double-quoted literals of one line, escapes collapsed to a space.
func _lang_literals(code: String) -> Array:
	var out: Array = []
	var i := 0
	while i < code.length():
		if code[i] != "\"":
			i += 1
			continue
		var j := i + 1
		var buf := ""
		while j < code.length():
			var c := code[j]
			if c == "\\":
				buf += " "
				j += 2
				continue
			if c == "\"":
				break
			buf += c
			j += 1
		out.append(buf)
		i = j + 1
	return out


func _lang_is_ident_char(c: String) -> bool:
	if c == "_":
		return true
	if "0123456789".contains(c):
		return true
	return c.to_lower() != c.to_upper()


## True when the line writes into a UI sink. ".text" must not match ".texture" or
## ".text_changed", so a bare-identifier sink only counts when the identifier ends
## right there.
func _lang_is_sink(code: String) -> bool:
	for s in LANG_SINKS:
		var needle := String(s)
		var closed := needle.ends_with("(") or needle.ends_with(":")
		var at := code.find(needle)
		while at >= 0:
			var after := at + needle.length()
			if closed or after >= code.length() or not _lang_is_ident_char(code[after]):
				return true
			at = code.find(needle, at + 1)
	return false


## The German marker inside ONE literal, or "" when it is clean.
func _lang_marker(lit: String) -> String:
	var trimmed := lit.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.to_lower() in LANG_ALLOW:
		return ""
	# snake_case identifiers are dictionary KEYS, never player-facing prose.
	# Without this guard "move_den" (movement-cost denominator) tokenises to
	# ["move", "den"] and trips on the German article "den". Real UI text is
	# spaced prose; a literal with an underscore and no space never is.
	if trimmed.contains("_") and not trimmed.contains(" "):
		return ""
	for i in lit.length():
		var ch := lit[i]
		if LANG_UMLAUTS.contains(ch):
			return ch
	for tok in _lang_tokens(lit):
		var w := String(tok)
		if w in LANG_ALLOW:
			continue
		if w in LANG_WORDS:
			return w
	return ""


## Lower-case word tokens of a literal; every non-letter is a separator, so the
## word list is matched as WHOLE WORDS only.
func _lang_tokens(s: String) -> PackedStringArray:
	var buf := ""
	for i in s.length():
		var c := s[i]
		if c.to_lower() != c.to_upper():
			buf += c
		else:
			buf += " "
	return buf.to_lower().split(" ", false)


## True when this literal appears as a JSON KEY on the line ("key": value).
func _lang_json_is_key(line: String, lit: String) -> bool:
	var needle := "\"" + lit + "\""
	var at := line.find(needle)
	while at >= 0:
		var i := at + needle.length()
		while i < line.length() and (line[i] == " " or line[i] == "\t"):
			i += 1
		if i < line.length() and line[i] == ":":
			return true
		at = line.find(needle, at + 1)
	return false


# ============================================================ §8.9 umbrella (--smoke)

## The whole §8.9 checklist in ONE process: language gate, voice coverage, map
## reachability incl. the stair link, hire, the full F4 -> F3 -> rescue -> end-card
## loop (which also covers loot and the bot battle), the save roundtrip, damaged
## slots and the screen smoke.
func _smoke() -> void:
	print("SMOKE: Start")
	Sfx.muted = true
	var fails := 0
	fails = _check_lang(fails)
	fails = _check_voice(fails)
	fails = _check_map_reach(fails)
	fails = _check_hire(fails)
	fails = await _check_loop(fails)
	fails = _check_save_roundtrip(fails)
	fails = await _check_bad_slots(fails)
	fails = await _check_screens(fails)
	_wipe_all_slots()
	if fails == 0:
		print("SMOKE OK")
	else:
		print("SMOKE FAIL (%d)" % fails)
	get_tree().quit(0 if fails == 0 else 1)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT: ", path)

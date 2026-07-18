extends Control
## THROWAWAY verification harness (Phase 6 optics). Boots the real combat map,
## photographs the northern estate (walls) + a full overview. Deleted after use.

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Sfx.muted = true
	Game.new_game()
	Game.set_difficulty("leicht")
	for id in ["ivan", "fuchs", "doc", "nadel"]:
		Game.hire(id)
	var combat: Node = load("res://scripts/tac3d/combat/tactical3d_combat.gd").new()
	combat.name = "Combat"
	add_child(combat)
	await combat.battle_ready
	await get_tree().create_timer(0.3).timeout

	var outdir := OS.get_cmdline_user_args()[0].substr(len("--verifyshots="))
	var g = combat.grid
	var rig = combat.rig

	# 1) Whole-island overview (max zoom out).
	rig.focus_world(rig.field.get_center())
	rig.set_zoom(60.0)
	await _wait(0.5)
	await _snap(outdir + "/combat_overview.png")

	# 2) Northern estate close-up (walls + roofs, z-fighting check).
	var boss_home = combat.meta["boss_home"]
	rig.focus_world(g.cell_to_world(boss_home))
	rig.set_zoom(20.0)
	await _wait(0.4)
	await _snap(outdir + "/combat_north.png")

	# 3) Estate rotated 45 deg (wall height / double-draw check from another angle).
	rig.rotate_step(1)
	await _wait(0.5)
	await _snap(outdir + "/combat_north_rot.png")

	# 4) A village building on level 0 (walls on the ground plane).
	rig.rotate_step(-1)
	rig.focus_world(g.cell_to_world(Vector3i(28, 0, 40)))
	rig.set_zoom(18.0)
	await _wait(0.4)
	await _snap(outdir + "/combat_village.png")

	get_tree().quit()

func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout

func _snap(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("VSHOT: ", path)

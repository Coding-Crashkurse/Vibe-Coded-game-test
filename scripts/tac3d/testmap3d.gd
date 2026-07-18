class_name TestMap3D
extends RefCounted


static func build() -> Dictionary:
	var grid := Grid3D.new()

	# --- Ebene 0: 16 breit (x=0..15), 12 tief (z=0..11) ---
	# Muster je Reihe: x0..6 GROUND, x7 WATER_SHALLOW, x8 WATER_DEEP, x9..15 GROUND
	for z in range(12):
		for x in range(16):
			var k: Tac3DTile.Kind
			if x == 7:
				k = Tac3DTile.Kind.WATER_SHALLOW
			elif x == 8:
				k = Tac3DTile.Kind.WATER_DEEP
			else:
				k = Tac3DTile.Kind.GROUND
			grid.set_tile(Vector3i(x, 0, z), Tac3DTile.make(k, 0))

	# --- Ebene 1: BRIDGE-Deck ---
	var bridge_cells := [
		Vector3i(6, 1, 5),
		Vector3i(7, 1, 5),
		Vector3i(8, 1, 5),
		Vector3i(9, 1, 5),
	]
	for c in bridge_cells:
		var bc: Vector3i = c
		grid.set_tile(bc, Tac3DTile.make(Tac3DTile.Kind.BRIDGE, 1))

	# --- Ebene 1: ROOF-Podest ---
	var podium_cells := [
		Vector3i(13, 1, 3),
		Vector3i(13, 1, 4),
		Vector3i(14, 1, 3),
		Vector3i(14, 1, 4),
	]
	for c in podium_cells:
		var pc: Vector3i = c
		grid.set_tile(pc, Tac3DTile.make(Tac3DTile.Kind.ROOF, 1))

	# --- Links (symmetrische Ebenen-Uebergaenge) ---
	grid.add_link(Vector3i(6, 1, 5), Vector3i(5, 0, 5))    # Bruecke West aufs Westufer
	grid.add_link(Vector3i(9, 1, 5), Vector3i(10, 0, 5))   # Bruecke Ost aufs Ostufer
	grid.add_link(Vector3i(13, 1, 4), Vector3i(12, 0, 4))  # Podest-Rampe vom Ostufer

	return {
		"grid": grid,
		"start": Vector3i(1, 0, 5),
		"goal": Vector3i(13, 1, 3),
		"spawn": Vector3i(1, 0, 5),
		"deep_under_deck": Vector3i(8, 0, 5),
		"deck_over_deep": Vector3i(8, 1, 5),
		"swim_from": Vector3i(6, 0, 5),
		"swim_to": Vector3i(9, 0, 5),
		"west_probe": Vector3i(1, 0, 5),
		"east_probe": Vector3i(13, 0, 3),
		"bridge_cells": bridge_cells,
		"podium_cells": podium_cells,
	}

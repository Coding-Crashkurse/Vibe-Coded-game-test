class_name Tac3DTile
extends RefCounted

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
const FLAG_KEEPOUT := 8   # keine blockierende Deko (Palme) auf dieser Zelle


static func make(k: Kind, ebene: int) -> Tac3DTile:
	var t := Tac3DTile.new()
	t.kind = k
	t.ebene = ebene
	match k:
		Kind.GROUND:
			t.begehbar = true
			t.move_type = Move.WALK
			t.blocks_sight = false
			t.cover = 0.0
			t.surface = 0
			t.weight = 1.0
		Kind.FLOOR:
			t.begehbar = true
			t.move_type = Move.WALK
			t.blocks_sight = false
			t.cover = 0.0
			t.surface = 1
			t.weight = 1.0
		Kind.ROOF:
			t.begehbar = true
			t.move_type = Move.WALK
			t.blocks_sight = false
			t.cover = 0.0
			t.surface = 2
			t.weight = 1.0
		Kind.WATER_SHALLOW:
			t.begehbar = true
			t.move_type = Move.WADE
			t.blocks_sight = false
			t.cover = 0.0
			t.surface = 3
			t.weight = 4.0
		Kind.WATER_DEEP:
			t.begehbar = true
			t.move_type = Move.SWIM
			t.blocks_sight = false
			t.cover = 0.0
			t.surface = 3
			t.weight = 10.0
		Kind.BRIDGE:
			t.begehbar = true
			t.move_type = Move.WALK
			t.blocks_sight = false
			t.cover = 0.0
			t.surface = 1
			t.weight = 1.0
		Kind.RAMP:
			t.begehbar = true
			t.move_type = Move.CLIMB
			t.blocks_sight = false
			t.cover = 0.0
			t.surface = 0
			t.weight = 1.5
		Kind.WALL:
			t.begehbar = false
			t.move_type = Move.WALK
			t.blocks_sight = true
			t.cover = 0.0
			t.surface = 0
			t.weight = 1.0
		Kind.VOID:
			t.begehbar = false
			t.move_type = Move.WALK
			t.blocks_sight = false
			t.cover = 0.0
			t.surface = 0
			t.weight = 1.0
	return t


func kind_name() -> String:
	match kind:
		Kind.GROUND: return "GROUND"
		Kind.FLOOR: return "FLOOR"
		Kind.ROOF: return "ROOF"
		Kind.WATER_SHALLOW: return "WATER_SHALLOW"
		Kind.WATER_DEEP: return "WATER_DEEP"
		Kind.BRIDGE: return "BRIDGE"
		Kind.RAMP: return "RAMP"
		Kind.WALL: return "WALL"
		Kind.VOID: return "VOID"
	return "UNKNOWN"


func is_water() -> bool:
	return kind == Kind.WATER_SHALLOW or kind == Kind.WATER_DEEP

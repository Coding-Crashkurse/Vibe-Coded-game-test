extends Node
## Game — Laufzeit-Zustand: Schwierigkeit, Budget, Team (mit Inventar), Statistik.

const START_BUDGET := 6000
const TEAM_MAX := 4

var difficulty := "normal"
var budget := START_BUDGET
var team: Array = []          # Runtime-Dicts der angeheuerten Söldner
var mission_result := ""      # "", "victory", "defeat", "abort"
var stats := {}
var boss_dialog_seen := false

func _ready() -> void:
	new_game()

func new_game() -> void:
	difficulty = "normal"
	budget = START_BUDGET
	team = []
	mission_result = ""
	boss_dialog_seen = false
	stats = {"turns": 0, "shots": 0, "hits": 0, "loot": 0, "fallen": []}

func set_difficulty(d: String) -> void:
	if Db.DIFFICULTY.has(d):
		difficulty = d

func diff() -> Dictionary:
	return Db.DIFFICULTY[difficulty]

## Effektiver Söldnerpreis nach Schwierigkeitsfaktor (auf 10 $ gerundet)
func eff_cost(base: int) -> int:
	return int(round(float(base) * float(diff()["cost_mult"]) / 10.0)) * 10

func is_hired(id: String) -> bool:
	for m in team:
		if m["id"] == id:
			return true
	return false

func hire(id: String) -> bool:
	var def := Db.merc_def(id)
	if def.is_empty() or is_hired(id) or team.size() >= TEAM_MAX:
		return false
	var price := eff_cost(int(def["cost"]))
	if budget < price:
		return false
	budget -= price
	var m := _runtime(def)
	m["cost_paid"] = price
	team.append(m)
	return true

func fire(id: String) -> void:
	for i in team.size():
		if team[i]["id"] == id:
			budget += int(team[i].get("cost_paid", 0))
			team.remove_at(i)
			return

func _runtime(def: Dictionary) -> Dictionary:
	var w: Dictionary = Db.weapon(def["weapon"])
	var inv: Array = []
	for it in def["inv"]:
		inv.append(it)
	return {
		"id": def["id"], "name": def["name"], "nick": def["nick"],
		"hp": int(def["hp"]), "hp_max": int(def["hp"]),
		"marks": int(def["marks"]), "agi": int(def["agi"]), "med": int(def["med"]),
		"weapon": def["weapon"], "ammo": int(w["mag"]),
		"inv": inv, "ammo_store": {},
		"armor": 0.0, "sight": 13,
		"sprite": def["sprite"], "tint": def["tint"], "portrait": def["portrait"],
		"cost": int(def["cost"]), "kills": 0, "alive": true,
	}

## Bestbezahltes Teammitglied — antwortet im Boss-Dialog.
func top_paid() -> Dictionary:
	var best := {}
	for m in team:
		if best.is_empty() or int(m["cost"]) > int(best["cost"]):
			best = m
	return best

func has_ivan() -> bool:
	return is_hired("ivan")

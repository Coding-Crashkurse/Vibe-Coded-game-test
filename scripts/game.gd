extends Node
## Game — runtime state: difficulty, budget, team (with inventory), statistics,
## world progress (day, sector states, base stash) and the save files.

const START_BUDGET := 6000
const TEAM_MAX := 4
const START_SECTOR := "F4"    # landing zone (SPEC v5 §2)

## SPEC v5 §4.3 — feature flag for booting the walkable 3D room AS THE MAIN MENU.
## TRUE, by the project owner's decision (2026-07-20): the room replaces the
## painted 2D menu as the entry point — "the new model is cooler". This is the
## spec's original "build once, use twice" intent: same room, main menu AND
## in-game home base (see `mode` in scripts/menu/hideout.gd).
##
## The painted menu (scripts/screens/title.gd) and its artwork are KEPT as the
## fallback and stay fully working: set this back to false and it is the boot
## screen again, no other change needed. Everything that navigates with
## goto("title") works either way, and the --menu test still covers it.
## Continue/Load route to the room via Hideout.enter_base() when `base_unlocked`
## is set — that path never depended on this flag.
## Only main.gd reads it.
const USE_HIDEOUT_MENU := true

var difficulty := "normal"
var budget := START_BUDGET
var team: Array = []          # runtime dicts of the hired mercs
var mission_result := ""      # "", "victory", "defeat", "abort"
var stats := {}
var boss_dialog_seen := false
## Rescue flag. The SAVE FILE calls this "tobias_freed" (SPEC v5 §4.4); the
## runtime variable keeps its old name because the combat orchestrator and the
## test harness read `Game.otto_freed`. Both names mean the same thing.
var otto_freed := false
var base_unlocked := false
var sector := START_SECTOR    # current sector on the Ashveil map (SPEC v5 §2)
var demo_finished := false    # SPEC v5 §3.3.6 — end card reached
var ending_choice := ""       # SPEC v5 §3.2 — RESERVED in the save schema (vision)

## SPEC v5 §4.4 schema additions --------------------------------------------
var day := 1                  # campaign day, starts at 1; the combat orchestrator advances it
var playtime_sec := 0.0       # accumulated real playtime in seconds
var logs_found: Array = []    # ids of the Helix radio logs picked up
var stash: Array = []         # base.stash — item ids left in The Hideout
## sector id -> {cleared: bool, enemies_dead: [], loot_taken: [], doors_open: []}
var sectors := {}

## Legacy alias for `stash` — same array, older name.
var base_stash: Array:
	get:
		return stash
	set(value):
		stash = value

func _ready() -> void:
	new_game()

func _process(delta: float) -> void:
	playtime_sec += delta

func new_game() -> void:
	difficulty = "normal"
	budget = START_BUDGET
	team = []
	mission_result = ""
	boss_dialog_seen = false
	otto_freed = false
	base_unlocked = false
	sector = START_SECTOR
	demo_finished = false
	ending_choice = ""
	day = 1
	playtime_sec = 0.0
	logs_found = []
	stash = []
	sectors = {}
	stats = {"turns": 0, "shots": 0, "hits": 0, "loot": 0, "fallen": []}

func set_difficulty(d: String) -> void:
	if Db.DIFFICULTY.has(d):
		difficulty = d

func diff() -> Dictionary:
	return Db.DIFFICULTY[difficulty]

## Effective merc price after the difficulty factor (rounded to 10 $)
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

## Best paid squad member — answers in the boss dialogue.
func top_paid() -> Dictionary:
	var best := {}
	for m in team:
		if best.is_empty() or int(m["cost"]) > int(best["cost"]):
			best = m
	return best

func has_ivan() -> bool:
	return is_hired("ivan")

# ============================================================ World progress
## Small helpers around `day`, `sectors`, `logs_found` and `stash` so the combat
## orchestrator and the HUD never touch the raw dictionaries.

## Advance the campaign day (sector transition / end of a mission).
func advance_day(n := 1) -> void:
	day = maxi(1, day + n)

## Live state of one sector — created on first access, so the caller may mutate
## the returned dictionary in place.
func sector_state(id: String) -> Dictionary:
	if not sectors.has(id):
		sectors[id] = _blank_sector()
	var e: Dictionary = sectors[id]
	return e

func mark_sector_cleared(id: String) -> void:
	var e := sector_state(id)
	e["cleared"] = true

func is_sector_cleared(id: String) -> bool:
	if not sectors.has(id):
		return false
	var e: Dictionary = sectors[id]
	return bool(e.get("cleared", false))

## Remember a dead enemy / looted container / opened door of a sector so a
## revisit does not respawn or re-loot it. Duplicates are ignored.
func mark_enemy_dead(id: String, enemy_id: String) -> void:
	_sector_note(id, "enemies_dead", enemy_id)

func mark_loot_taken(id: String, loot_id: String) -> void:
	_sector_note(id, "loot_taken", loot_id)

func mark_door_open(id: String, door_id: String) -> void:
	_sector_note(id, "doors_open", door_id)

func _sector_note(id: String, key: String, entry: String) -> void:
	if entry == "":
		return
	var e := sector_state(id)
	var arr: Array = e[key]
	if not arr.has(entry):
		arr.append(entry)

func _blank_sector() -> Dictionary:
	return {"cleared": false, "enemies_dead": [], "loot_taken": [], "doors_open": []}

## Rebuild one sector entry from untrusted (JSON) data — every field typed.
func _sector_entry(src: Dictionary) -> Dictionary:
	return {
		"cleared": bool(src.get("cleared", false)),
		"enemies_dead": _str_array(src.get("enemies_dead", [])),
		"loot_taken": _str_array(src.get("loot_taken", [])),
		"doors_open": _str_array(src.get("doors_open", [])),
	}

func _str_array(v: Variant) -> Array:
	var out: Array = []
	if typeof(v) != TYPE_ARRAY:
		return out
	for e in (v as Array):
		out.append(String(e))
	return out

## Number out of untrusted (JSON) data. int()/float() on a Dictionary or an
## Array is a HARD runtime error, so every save field goes through here — a
## hand-edited or truncated file must degrade, never crash (project law).
func _to_int(v: Variant, def_val := 0) -> int:
	var t := typeof(v)
	if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL:
		return int(v)
	if t == TYPE_STRING and (v as String).is_valid_float():
		return int((v as String).to_float())
	return def_val

func _to_float(v: Variant, def_val := 0.0) -> float:
	var t := typeof(v)
	if t == TYPE_INT or t == TYPE_FLOAT or t == TYPE_BOOL:
		return float(v)
	if t == TYPE_STRING and (v as String).is_valid_float():
		return (v as String).to_float()
	return def_val

## Helix radio log found (SPEC v5 §3) — ids stay unique.
func add_log(log_id: String) -> void:
	if log_id == "" or logs_found.has(log_id):
		return
	logs_found.append(log_id)

func has_log(log_id: String) -> bool:
	return logs_found.has(log_id)

# ------------------------------------------------------------------ Base stash
func stash_add(item_id: String) -> void:
	if item_id == "":
		return
	stash.append(item_id)

## Take the item at `idx` out of the stash — "" if the index is out of range.
func stash_take(idx: int) -> String:
	if idx < 0 or idx >= stash.size():
		return ""
	var id := String(stash[idx])
	stash.remove_at(idx)
	return id

# ------------------------------------------------------------------ Sector names
## Display names come from data/sectors.json — loaded lazily and fallback safe:
## without the file the raw sector id is used.

const SECTOR_DATA_PATH := "res://data/sectors.json"

var _sector_names: Dictionary = {}
var _sector_names_loaded := false

func sector_name(id: String) -> String:
	_ensure_sector_names()
	return String(_sector_names.get(id, id))

func _ensure_sector_names() -> void:
	if _sector_names_loaded:
		return
	_sector_names_loaded = true
	if not FileAccess.file_exists(SECTOR_DATA_PATH):
		return
	var f := FileAccess.open(SECTOR_DATA_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var arr: Variant = (parsed as Dictionary).get("sectors", [])
	if typeof(arr) != TYPE_ARRAY:
		return
	for raw in (arr as Array):
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var s: Dictionary = raw
		var sid := String(s.get("id", ""))
		if sid != "":
			_sector_names[sid] = String(s.get("name", sid))

## Save header title (SPEC v5 §4.4): "Day 2 · Rookhaven".
func save_title() -> String:
	return "Day %d · %s" % [day, sector_name(sector)]

## Playtime as a short human string, e.g. "1h 07m" / "12m".
func playtime_text() -> String:
	var total := int(playtime_sec)
	var h := total / 3600
	var m := (total % 3600) / 60
	if h > 0:
		return "%dh %02dm" % [h, m]
	return "%dm" % m

# ============================================================ Save files
# JSON under user://saves/. IMPORTANT: mercs are stored ONLY with their mutable
# state (hp/ammo/inventory/…) — static data (tint/portrait are Color values and
# do NOT survive JSON!) is rebuilt from Db.merc_def() via _runtime() on load.

const SAVE_DIR := "user://saves"
const SAVE_VERSION := 1
const SLOT_COUNT := 5          # manual slots 1..5 (the panel offers 1..3, SPEC v5 §4.4)
const AUTOSAVE_SLOT := 0       # "CONTINUE" picks the most recent state

## State of a save slot as reported by slot_state().
enum SlotState { EMPTY, OK, DAMAGED, INCOMPATIBLE }

## Mutable fields of a team member (everything else comes from the Db).
const SAVED_FIELDS := [
	"hp", "hp_max", "marks", "agi", "med", "weapon", "ammo",
	"inv", "ammo_store", "armor", "sight", "kills", "alive", "cost_paid",
]

func save_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

func has_save(slot: int) -> bool:
	return FileAccess.file_exists(save_path(slot))

func has_any_save() -> bool:
	return latest_slot() >= 0

## Most recent occupied slot (autosave included) — −1 if there is nothing.
## Damaged and version-incompatible files are skipped: they are not loadable.
func latest_slot() -> int:
	var best := -1
	var best_t := -1.0
	for slot in range(AUTOSAVE_SLOT, SLOT_COUNT + 1):
		var d := read_save(slot)
		if d.is_empty():
			continue
		var t := float(d.get("saved_at", 0.0))
		if t > best_t:
			best_t = t
			best = slot
	return best

## Raw parse of a slot file — NO validation. {} when missing/unreadable/garbage.
func _parse_slot(slot: int) -> Dictionary:
	var path := save_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	if txt.strip_edges() == "":
		return {}
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary

func _is_num(v: Variant) -> bool:
	var t := typeof(v)
	return t == TYPE_INT or t == TYPE_FLOAT

## Mandatory fields AND their types — a truncated or hand-edited file must never
## reach the runtime state.
func _schema_ok(d: Dictionary) -> bool:
	if typeof(d.get("difficulty")) != TYPE_STRING:
		return false
	if typeof(d.get("sector")) != TYPE_STRING:
		return false
	if not _is_num(d.get("budget")):
		return false
	if typeof(d.get("team")) != TYPE_ARRAY:
		return false
	if typeof(d.get("flags")) != TYPE_DICTIONARY:
		return false
	if typeof(d.get("stats")) != TYPE_DICTIONARY:
		return false
	for entry in (d["team"] as Array):
		if typeof(entry) != TYPE_DICTIONARY:
			return false
		var m: Dictionary = entry
		if typeof(m.get("id")) != TYPE_STRING:
			return false
	return true

## EMPTY / OK / DAMAGED / INCOMPATIBLE — never raises, whatever is on disk.
func slot_state(slot: int) -> int:
	if not FileAccess.file_exists(save_path(slot)):
		return SlotState.EMPTY
	var d := _parse_slot(slot)
	if d.is_empty():
		return SlotState.DAMAGED
	if not _is_num(d.get("version")):
		return SlotState.DAMAGED
	if int(d["version"]) != SAVE_VERSION:
		return SlotState.INCOMPATIBLE
	if not _schema_ok(d):
		return SlotState.DAMAGED
	return SlotState.OK

func slot_is_damaged(slot: int) -> bool:
	return slot_state(slot) == SlotState.DAMAGED

func slot_is_incompatible(slot: int) -> bool:
	return slot_state(slot) == SlotState.INCOMPATIBLE

## Validated read — {} unless the slot holds a loadable save of THIS version.
## Single parse: the version gate and the schema check run on the parsed dict.
func read_save(slot: int) -> Dictionary:
	var d := _parse_slot(slot)
	if d.is_empty():
		return {}
	if not _is_num(d.get("version")):
		return {}
	if int(d["version"]) != SAVE_VERSION:
		return {}
	if not _schema_ok(d):
		return {}
	return d

## Short info for the slot list (without loading the state).
## Empty slot  → {}
## Broken file → {"slot": n, "damaged": true, "incompatible": false}
## Foreign ver → {"slot": n, "damaged": false, "incompatible": true, "version": v}
func save_info(slot: int) -> Dictionary:
	if not FileAccess.file_exists(save_path(slot)):
		return {}
	var d := _parse_slot(slot)
	if d.is_empty() or not _is_num(d.get("version")):
		return {"slot": slot, "damaged": true, "incompatible": false}
	if int(d["version"]) != SAVE_VERSION:
		return {
			"slot": slot, "damaged": false, "incompatible": true,
			"version": int(d["version"]),
		}
	if not _schema_ok(d):
		return {"slot": slot, "damaged": true, "incompatible": false}
	# The save holds only mutable fields — the nickname is static and gets
	# resolved from the Db (exactly like on load).
	var nicks: Array = []
	var ids: Array = []
	for m in (d.get("team", []) as Array):
		var entry: Dictionary = m
		var mid := String(entry.get("id", ""))
		var def := Db.merc_def(mid)
		nicks.append(String(def["nick"]) if not def.is_empty() else "?")
		if not def.is_empty():
			ids.append(mid)
	var fl: Dictionary = d.get("flags", {})
	var sec := String(d.get("sector", START_SECTOR))
	return {
		"slot": slot,
		"damaged": false,
		"incompatible": false,
		"title": String(d.get("title", d.get("label", ""))),
		"label": String(d.get("label", "")),
		"saved_at_text": String(d.get("saved_at_text", "")),
		"difficulty": String(d.get("difficulty", "normal")),
		"sector": sec,
		"sector_name": sector_name(sec),
		"day": int(d.get("day", 1)),
		"playtime_sec": float(d.get("playtime_sec", 0.0)),
		"budget": int(d.get("budget", 0)),
		"team": nicks,
		"team_ids": ids,
		"demo_finished": bool(fl.get("demo_finished", false)),
	}

## Atomic write (SPEC v5 §4.4): build the file next to the target, close it,
## then rename over the real path. A failure anywhere leaves the previous save
## untouched and returns false — there is never a half-written save.
func save_game(slot: int, label := "") -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		push_error("Save failed, directory missing: %s" % SAVE_DIR)
		return false
	var members: Array = []
	for m in team:
		var src: Dictionary = m
		var out: Dictionary = {"id": String(src["id"])}
		for k in SAVED_FIELDS:
			if src.has(k):
				out[k] = src[k]
		members.append(out)
	var title := save_title()
	var data := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_unix_time_from_system(),
		"saved_at_text": Time.get_datetime_string_from_system(false, true),
		"title": title,
		"label": label if label != "" else title,
		"playtime_sec": playtime_sec,
		"difficulty": difficulty,
		"budget": budget,
		"day": day,
		"sector": sector,
		"mission_result": mission_result,
		"team": members,
		"stats": stats.duplicate(true),
		"base": {"unlocked": base_unlocked, "stash": stash.duplicate()},
		"sectors": _sectors_for_save(),
		"flags": {
			"boss_dialog_seen": boss_dialog_seen,
			# SPEC v5 §4.4 name; "otto_freed" stays as a legacy alias so older
			# builds and the test harness keep reading the same flag.
			"tobias_freed": otto_freed,
			"otto_freed": otto_freed,
			"base_unlocked": base_unlocked,
			"demo_finished": demo_finished,
			"ending_choice": ending_choice,
			"logs_found": logs_found.duplicate(),
		},
		"ending_choice": ending_choice,
		"world": {"current_sector": sector},
	}
	var final_path := save_path(slot)
	var tmp_path := final_path + ".tmp"
	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		push_error("Save failed, cannot open temp file: %s" % tmp_path)
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	if not FileAccess.file_exists(tmp_path):
		push_error("Save failed, temp file was not written: %s" % tmp_path)
		return false
	var err := DirAccess.rename_absolute(tmp_path, final_path)
	if err != OK and FileAccess.file_exists(final_path):
		# Some filesystems refuse to rename ONTO an existing file. Clearing the
		# target first stays safe: the complete new save sits in the temp file,
		# so the worst case is a crash window, not a half-written save.
		DirAccess.remove_absolute(final_path)
		err = DirAccess.rename_absolute(tmp_path, final_path)
	if err != OK:
		DirAccess.remove_absolute(tmp_path)
		push_error("Save failed, could not replace %s (error %d)" % [final_path, err])
		return false
	return true

func _sectors_for_save() -> Dictionary:
	var out: Dictionary = {}
	for k in sectors:
		var raw: Variant = sectors[k]
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		out[String(k)] = _sector_entry(raw as Dictionary)
	return out

## Loads a slot. Returns false for empty, damaged and foreign-version files.
## The runtime state is only touched AFTER the file passed validation, so a
## rejected save can never half-apply a foreign schema.
func load_game(slot: int) -> bool:
	var d := read_save(slot)
	if d.is_empty():
		return false
	difficulty = String(d.get("difficulty", "normal"))
	if not Db.DIFFICULTY.has(difficulty):
		difficulty = "normal"
	budget = int(d.get("budget", START_BUDGET))
	sector = String(d.get("sector", START_SECTOR))
	mission_result = String(d.get("mission_result", ""))
	day = maxi(1, _to_int(d.get("day", 1), 1))
	playtime_sec = maxf(0.0, _to_float(d.get("playtime_sec", 0.0)))
	var fl: Dictionary = d.get("flags", {})
	ending_choice = String(d.get("ending_choice", fl.get("ending_choice", "")))
	boss_dialog_seen = bool(fl.get("boss_dialog_seen", false))
	# SPEC v5 §4.4 names the flag `tobias_freed`; older saves wrote `otto_freed`.
	otto_freed = bool(fl.get("tobias_freed", fl.get("otto_freed", false)))
	demo_finished = bool(fl.get("demo_finished", false))
	logs_found = _str_array(fl.get("logs_found", []))
	var base_d: Dictionary = {}
	if typeof(d.get("base")) == TYPE_DICTIONARY:
		base_d = d["base"]
	base_unlocked = bool(base_d.get("unlocked", fl.get("base_unlocked", false)))
	stash = _str_array(base_d.get("stash", []))
	sectors = {}
	var sc: Variant = d.get("sectors", {})
	if typeof(sc) == TYPE_DICTIONARY:
		for k in (sc as Dictionary):
			var raw: Variant = (sc as Dictionary)[k]
			if typeof(raw) != TYPE_DICTIONARY:
				continue
			sectors[String(k)] = _sector_entry(raw as Dictionary)
	# _schema_ok only guarantees that `stats` IS a Dictionary — its members are
	# still untrusted, so every one of them is coerced defensively.
	var st: Dictionary = d.get("stats", {})
	stats = {
		"turns": _to_int(st.get("turns", 0)), "shots": _to_int(st.get("shots", 0)),
		"hits": _to_int(st.get("hits", 0)), "loot": _to_int(st.get("loot", 0)),
		"fallen": _str_array(st.get("fallen", [])),
	}
	team = []
	for entry in (d.get("team", []) as Array):
		var saved: Dictionary = entry
		var def := Db.merc_def(String(saved.get("id", "")))
		if def.is_empty():
			continue
		var m := _runtime(def)          # static data fresh from the Db
		for k in SAVED_FIELDS:          # mutable state layered on top
			if not saved.has(k):
				continue
			# Every field is coerced defensively: _schema_ok only checked the merc
			# id, so a hand-edited entry may hold anything. A value that does not
			# fit keeps the fresh Db default instead of crashing the load.
			match k:
				"inv":
					m[k] = _str_array(saved[k])
				"ammo_store":
					var store: Dictionary = {}
					if typeof(saved[k]) == TYPE_DICTIONARY:
						var raw_store: Dictionary = saved[k]
						for ak in raw_store:
							store[String(ak)] = _to_int(raw_store[ak])
					m[k] = store
				"alive":
					m[k] = bool(saved[k])
				"armor":
					m[k] = _to_float(saved[k], float(m.get(k, 0.0)))
				"weapon":
					m[k] = String(saved[k])
				_:
					# JSON delivers numbers as float — the runtime needs real ints.
					m[k] = _to_int(saved[k], int(m.get(k, 0)))
		team.append(m)
	return true

func delete_save(slot: int) -> void:
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return
	var fname := "slot_%d.json" % slot
	if FileAccess.file_exists(save_path(slot)):
		dir.remove(fname)
	# A leftover temp file from a crashed write must not survive either.
	if FileAccess.file_exists(save_path(slot) + ".tmp"):
		dir.remove(fname + ".tmp")

extends Node
## Db — statische Spieldaten: Waffen, Items, Söldner, Gegner, Schwierigkeit, Dialoge.

const TILE := 64

# ------------------------------------------------------------------ Waffen
# AP-Ökonomie bewusst JA1-artig: Ein Schuss kostet 12–15 AP.
# Bei 30–38 AP pro Runde sind das 2, maximal 3 Schüsse — selbst im Stand.
const WEAPONS := {
	"p9": {
		"name": "9-mm-Pistole »P9«", "short": "P9", "cal": "9mm",
		"dmg": 24, "var": 6, "range": 10, "ap": 12, "mag": 15, "reload": 6,
		"acc": 5, "pose": "gun", "snd": "shot_p", "shotgun": false,
	},
	"k45": {
		"name": ".45-Pistole »K45«", "short": "K45", "cal": "45",
		"dmg": 30, "var": 7, "range": 8, "ap": 14, "mag": 7, "reload": 6,
		"acc": 0, "pose": "gun", "snd": "shot_p", "shotgun": false,
	},
	"flinte": {
		"name": "Flinte »Jagdstück«", "short": "Flinte", "cal": "schrot",
		"dmg": 40, "var": 10, "range": 6, "ap": 15, "mag": 6, "reload": 7,
		"acc": 0, "pose": "machine", "snd": "shot_s", "shotgun": true,
	},
	"drachenmaul": {
		"name": "Flinte »Drachenmaul«", "short": "Drachenmaul", "cal": "schrot",
		"dmg": 48, "var": 8, "range": 7, "ap": 15, "mag": 8, "reload": 7,
		"acc": 5, "pose": "machine", "snd": "shot_s", "shotgun": true,
	},
}

const GRENADE := {"dmg": 45, "dmg_edge": 22, "radius": 1.5, "ap": 15}
const MEDKIT_AP := 12
const SEARCH_AP := 6
const SWAP_AP := 4
# Gezieltes Schießen in Stufen (JA1): jede Stufe +3 AP und +7 % Trefferchance
const AIM := {"ap_step": 3, "bonus_step": 7, "max": 3}

# ------------------------------------------------------------------ Items (JA1-Inventar)
const ITEMS := {
	"p9": {"name": "9-mm-Pistole »P9«", "short": "P9", "kind": "weapon"},
	"k45": {"name": ".45-Pistole »K45«", "short": "K45", "kind": "weapon"},
	"flinte": {"name": "Flinte »Jagdstück«", "short": "Flinte", "kind": "weapon"},
	"drachenmaul": {"name": "Flinte »Drachenmaul«", "short": "Drachenm.", "kind": "weapon"},
	"mag_9mm": {"name": "9-mm-Magazin (15)", "short": "9mm-Mag", "kind": "ammo", "cal": "9mm"},
	"mag_45": {"name": ".45-Magazin (7)", "short": ".45-Mag", "kind": "ammo", "cal": "45"},
	"mag_schrot": {"name": "Schrot-Schachtel (6)", "short": "Schrot", "kind": "ammo", "cal": "schrot"},
	"granate": {"name": "Handgranate", "short": "Granate", "kind": "grenade"},
	"medkit": {"name": "Medikit", "short": "Medikit", "kind": "medkit"},
}
const INV_SLOTS := 8

## Kisten-Loot: [Gewicht, Item]
const LOOT_TABLE := [
	[30, "mag_9mm"], [22, "mag_45"], [16, "mag_schrot"],
	[12, "granate"], [14, "medkit"], [3, "k45"], [3, "flinte"],
]

# ------------------------------------------------------------------ Schwierigkeit
const DIFFICULTY := {
	"leicht": {
		"name": "LEICHT", "order": 0,
		"desc": "10 Gegner · normale Söldnerpreise · unsichere Schützen · volle Kisten",
		"cost_mult": 1.0, "marks_mod": -5, "loot_min": 2, "loot_max": 2, "enemies": 10,
	},
	"normal": {
		"name": "NORMAL", "order": 1,
		"desc": "13 Gegner · Söldnerpreise ×1,25 · Standard",
		"cost_mult": 1.25, "marks_mod": 0, "loot_min": 1, "loot_max": 2, "enemies": 13,
	},
	"schwer": {
		"name": "SCHWER", "order": 2,
		"desc": "17 Gegner · Söldnerpreise ×1,5 · treffsichere Gegner · karge Kisten",
		"cost_mult": 1.5, "marks_mod": 5, "loot_min": 1, "loot_max": 1, "enemies": 17,
	},
}

# ------------------------------------------------------------------ Söldner
# Portrait-Parameter: skin, hair, style (0 Glatze, 1 kurz, 2 voll, 3 Irokese),
# shades, beard, cap (Farbe oder null), cloth. Ausrüstung als Item-Liste (JA1).
const MERCS := [
	{
		"id": "nadel", "name": "Jörg Nadel", "nick": "Nadel",
		"quote": "Billig, schnell, meistens nüchtern.",
		"hp": 55, "marks": 62, "agi": 70, "med": 20, "exp": 1,
		"weapon": "p9", "inv": ["mag_9mm", "mag_9mm", "mag_9mm", "granate", "medkit"], "cost": 400,
		"sprite": "manBrown", "tint": Color(1, 1, 1),
		"portrait": {"skin": Color(0.85, 0.66, 0.48), "hair": Color(0.32, 0.22, 0.12), "style": 1, "shades": false, "beard": false, "cap": null, "cloth": Color(0.45, 0.36, 0.22)},
	},
	{
		"id": "blitz", "name": "Karl Blitzer", "nick": "Blitz",
		"quote": "Bezahl mich, bevor ich wieder wegrenne.",
		"hp": 65, "marks": 70, "agi": 90, "med": 25, "exp": 1,
		"weapon": "p9", "inv": ["mag_9mm", "mag_9mm", "mag_9mm", "granate", "medkit", "medkit"], "cost": 500,
		"sprite": "manBlue", "tint": Color(1, 1, 1),
		"portrait": {"skin": Color(0.93, 0.76, 0.6), "hair": Color(0.85, 0.7, 0.3), "style": 3, "shades": false, "beard": false, "cap": null, "cloth": Color(0.25, 0.42, 0.6)},
	},
	{
		"id": "opa", "name": "Hannes Krüger", "nick": "Opa",
		"quote": "Ich hab schon Kriege verloren, da warst du noch Munition.",
		"hp": 50, "marks": 84, "agi": 55, "med": 35, "exp": 2,
		"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "granate", "medkit", "medkit"], "cost": 700,
		"sprite": "manOld", "tint": Color(0.95, 0.92, 0.86),
		"portrait": {"skin": Color(0.88, 0.72, 0.58), "hair": Color(0.82, 0.82, 0.8), "style": 1, "shades": false, "beard": true, "cap": null, "cloth": Color(0.4, 0.4, 0.36)},
	},
	{
		"id": "doc", "name": "Dr. Elias Vogel", "nick": "Doc",
		"quote": "Erst flicke ich dich, dann die Rechnung.",
		"hp": 60, "marks": 65, "agi": 65, "med": 95, "exp": 1,
		"weapon": "p9", "inv": ["mag_9mm", "mag_9mm", "mag_9mm", "medkit", "medkit", "medkit", "medkit"], "cost": 900,
		"sprite": "manOld", "tint": Color(0.85, 1.0, 0.92),
		"portrait": {"skin": Color(0.9, 0.74, 0.6), "hair": Color(0.25, 0.2, 0.16), "style": 1, "shades": true, "beard": false, "cap": null, "cloth": Color(0.75, 0.8, 0.78)},
	},
	{
		"id": "walross", "name": "Bruno Wall", "nick": "Walross",
		"quote": "Ich geh vor. Du zahlst die Munition.",
		"hp": 95, "marks": 60, "agi": 50, "med": 15, "exp": 2,
		"weapon": "flinte", "inv": ["mag_schrot", "mag_schrot", "mag_schrot", "granate", "granate", "medkit"], "cost": 1400,
		"sprite": "survivor1", "tint": Color(1, 1, 1),
		"portrait": {"skin": Color(0.8, 0.6, 0.45), "hair": Color(0.15, 0.12, 0.1), "style": 0, "shades": false, "beard": true, "cap": null, "cloth": Color(0.3, 0.3, 0.3)},
	},
	{
		"id": "granate", "name": "Greta Spreng", "nick": "Granate",
		"quote": "Wenn's laut wird, war ich's.",
		"hp": 70, "marks": 68, "agi": 75, "med": 30, "exp": 2,
		"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "granate", "granate", "granate", "granate", "medkit"], "cost": 1600,
		"sprite": "womanGreen", "tint": Color(1, 1, 1),
		"portrait": {"skin": Color(0.92, 0.72, 0.55), "hair": Color(0.65, 0.28, 0.12), "style": 2, "shades": false, "beard": false, "cap": null, "cloth": Color(0.28, 0.5, 0.3)},
	},
	{
		"id": "schatten", "name": "Mira Nacht", "nick": "Schatten",
		"quote": "Du siehst mich nur, wenn ich es will.",
		"hp": 60, "marks": 78, "agi": 88, "med": 40, "exp": 2,
		"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "granate", "granate", "medkit", "medkit"], "cost": 1900,
		"sprite": "hitman1", "tint": Color(1, 1, 1),
		"portrait": {"skin": Color(0.82, 0.64, 0.5), "hair": Color(0.08, 0.08, 0.1), "style": 2, "shades": true, "beard": false, "cap": null, "cloth": Color(0.12, 0.12, 0.14)},
	},
	{
		"id": "ivan", "name": "Ivan Petrow", "nick": "Ivan",
		"quote": "Nu dawai. Ivan erledigt das.",
		"hp": 85, "marks": 88, "agi": 78, "med": 10, "exp": 3,
		"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "mag_45", "granate", "granate", "medkit"], "cost": 2200,
		"sprite": "survivor1", "tint": Color(0.95, 0.78, 0.72),
		"portrait": {"skin": Color(0.87, 0.7, 0.56), "hair": Color(0.2, 0.16, 0.12), "style": 1, "shades": false, "beard": true, "cap": Color(0.55, 0.12, 0.12), "cloth": Color(0.5, 0.16, 0.16)},
	},
	{
		"id": "fuchs", "name": "Viktor Fuchs", "nick": "Fuchs",
		"quote": "Ein Schuss, eine Rechnung.",
		"hp": 70, "marks": 92, "agi": 72, "med": 30, "exp": 3,
		"weapon": "flinte", "inv": ["mag_schrot", "mag_schrot", "mag_schrot", "mag_schrot", "granate", "granate", "medkit", "medkit"], "cost": 2500,
		"sprite": "survivor1", "tint": Color(1.0, 0.82, 0.62),
		"portrait": {"skin": Color(0.9, 0.7, 0.52), "hair": Color(0.75, 0.4, 0.15), "style": 1, "shades": true, "beard": false, "cap": null, "cloth": Color(0.6, 0.42, 0.2)},
	},
]

# ------------------------------------------------------------------ Otto (befreibarer Verbündeter)
# Befreibarer Verbündeter (NICHT in MERCS -> taucht nicht im v2-Anheuern-Screen auf).
# Stimme = bestehende "walross"-Clips (gruff/schwer, passt zum "Bär"). Keine Generierung.
const OTTO := {
	"id": "otto", "name": "Otto Brandt", "nick": "Bär", "voice": "walross",
	"quote": "Habt ihr lang genug gebraucht.",
	"hp": 90, "marks": 80, "agi": 52, "med": 25, "exp": 3,
	"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "granate", "medkit"], "cost": 0,
	"sprite": "survivor1", "tint": Color(1, 1, 1),
	"portrait": {"skin": Color(0.86, 0.66, 0.5), "hair": Color(0.6, 0.55, 0.5), "style": 0, "shades": false, "beard": true, "cap": null, "cloth": Color(0.35, 0.42, 0.3)},
}

# ------------------------------------------------------------------ Gegner
# Gegner sehen einen Tick kürzer als Söldner (12 vs. 13) — der Spieler
# bekommt den ersten Sichtkontakt. Treffsicherheit bewusst moderat.
const ENEMY_TYPES := {
	"miliz_p9": {
		"name": "Milizionär", "exp": 1, "hp": 50, "marks": 48, "agi": 55, "weapon": "p9",
		"armor": 0.0, "sight": 12, "sprite": "soldier1", "tint": Color(1, 1, 1), "scale": 1.0,
	},
	"miliz_k45": {
		"name": "Milizionär", "exp": 1, "hp": 55, "marks": 52, "agi": 55, "weapon": "k45",
		"armor": 0.0, "sight": 12, "sprite": "soldier1", "tint": Color(1, 1, 1), "scale": 1.0,
	},
	"miliz_flinte": {
		"name": "Milizionär", "exp": 1, "hp": 60, "marks": 50, "agi": 50, "weapon": "flinte",
		"armor": 0.0, "sight": 12, "sprite": "soldier1", "tint": Color(1, 1, 1), "scale": 1.0,
	},
	"elite": {
		"name": "Elitewache", "exp": 3, "hp": 80, "marks": 64, "agi": 65, "weapon": "k45",
		"armor": 0.25, "sight": 12, "sprite": "soldier1", "tint": Color(0.8, 0.55, 0.55), "scale": 1.0,
	},
	"elite_flinte": {
		"name": "Elitewache", "exp": 3, "hp": 85, "marks": 60, "agi": 60, "weapon": "flinte",
		"armor": 0.25, "sight": 12, "sprite": "soldier1", "tint": Color(0.8, 0.55, 0.55), "scale": 1.0,
	},
	"boss": {
		"name": "»General« Vargo", "exp": 5, "hp": 180, "marks": 78, "agi": 60, "weapon": "drachenmaul",
		"armor": 0.5, "sight": 14, "sprite": "soldier1", "tint": Color(1.0, 0.85, 0.45), "scale": 1.25,
		"portrait": {"skin": Color(0.8, 0.62, 0.48), "hair": Color(0.2, 0.18, 0.15), "style": 0, "shades": false, "beard": true, "cap": Color(0.65, 0.1, 0.1), "cloth": Color(0.75, 0.62, 0.25)},
	},
}

# ------------------------------------------------------------------ Boss-Dialog
const BOSS_DIALOG := [
	{"speaker": "vargo", "text": "Sieh an. Die Dorfratten haben sich Söldner gekauft. Was hat euch der Bürgermeister versprochen — sein Sparschwein?"},
	{"speaker": "merc", "text": "Genug für die Munition, die in dir landet."},
	{"speaker": "vargo", "text": "Dann kommt. Meine Weste hat schon ganz andere Rechnungen geschluckt."},
]
const BOSS_CHOICES := [
	{"label": "Angreifen!", "reply": ""},
	{"label": "»Wir können über einen Rückzug reden.«", "reply": "Vargo lacht: »Ich verhandle nicht mit Leichen.«"},
]
const IVAN_DIALOG_LINE := "Wsjo, General. Ivan ist hier, um zu kassieren."

# ------------------------------------------------------------------ Texte
const MISSION_TITLE := "SEKTOR 43 — SILBERQUELL"
const MISSION_TEXT := "Der Warlord »General« Vargo hält das Dorf Silberquell besetzt. Die Regierung zahlt nicht mehr, die Dorfbewohner schon — mit allem, was sie haben.\n\nLanden Sie auf der Südwest-Wiese, arbeiten Sie sich durchs Dorf und eliminieren Sie Vargo in seinem Anwesen im Nordosten."
const OBJECTIVES := [
	"Vom Landepunkt im Südwesten vorrücken.",
	"Die Miliz im Dorf ausschalten (oder umgehen).",
	"In das Anwesen im Nordosten eindringen.",
	"»General« Vargo eliminieren.",
]
const TIPS := [
	"Tipp: Kisten und Sandsäcke geben 25 % Deckung — Wände und Bäume blocken Schüsse komplett.",
	"Tipp: Wer sich im Sichtfeld eines Feindes bewegt, riskiert einen Unterbrechungsschuss.",
	"Tipp: Die Flinte ist unter 4 Feldern brutal — auf Distanz fällt ihr Schaden stark ab.",
	"Tipp: Granaten treffen auch das eigene Team. Werfen Sie nicht auf Ihre Vorhut.",
	"Tipp: Munition ist endlich! Durchsuchen Sie Kisten und Gefallene (6 AP) nach Magazinen.",
	"Tipp: Zielen (Z) kostet die Hälfte mehr AP, gibt aber +18 % Trefferchance.",
	"Tipp: Heben Sie sich AP auf — dann kann Ihr Söldner Feinde unterbrechen.",
	"Tipp: Vargos Weste schluckt die Hälfte des Schadens. Granaten interessiert das wenig.",
	"Tipp: Vor dem ersten Feindkontakt bewegt sich der Trupp frei — sichern Sie sich eine gute Position.",
	"Tipp: Im Inventar (I) können Sie Waffen tauschen, Items benutzen und Ballast abwerfen.",
]

static func weapon(id: String) -> Dictionary:
	return WEAPONS[id]

static func item(id: String) -> Dictionary:
	return ITEMS[id]

static func merc_def(id: String) -> Dictionary:
	for m in MERCS:
		if m["id"] == id:
			return m
	return {}

# Laufzeit-Dict für Otto (Spiegel von Game._runtime, aber ohne hire/Budget).
# Damit Orchestrator und Test denselben Dict bekommen.
static func otto_runtime() -> Dictionary:
	var d := OTTO
	var w: Dictionary = weapon(d["weapon"])
	var inv: Array = []
	for it in d["inv"]:
		inv.append(it)
	return {
		"id": d["id"], "name": d["name"], "nick": d["nick"], "voice": d["voice"],
		"hp": int(d["hp"]), "hp_max": int(d["hp"]),
		"marks": int(d["marks"]), "agi": int(d["agi"]), "med": int(d["med"]), "exp": int(d["exp"]),
		"weapon": d["weapon"], "ammo": int(w["mag"]), "inv": inv, "ammo_store": {},
		"armor": 0.0, "sight": 13, "sprite": d["sprite"], "tint": d["tint"],
		"portrait": d["portrait"], "cost": int(d["cost"]), "kills": 0, "alive": true,
	}

static func roll_loot(rng: RandomNumberGenerator) -> String:
	var total := 0
	for e in LOOT_TABLE:
		total += int(e[0])
	var r := rng.randi_range(1, total)
	for e in LOOT_TABLE:
		r -= int(e[0])
		if r <= 0:
			return String(e[1])
	return "mag_9mm"

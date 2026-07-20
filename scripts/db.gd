extends Node
## Db — static game data: weapons, items, mercs, enemies, difficulty, dialogue.
## v5 BITTER HARVEST: all player-facing strings are English. Internal ids/keys
## (difficulty keys leicht/normal/schwer, zone keys kopf/beine, stance keys,
## weapon/item/merc ids, cal values, speaker ids) stay unchanged so the combat
## logic and the headless test harness keep working 1:1.

const TILE := 64

# ------------------------------------------------------------------ Weapons
# AP economy is deliberately JA1-like: one shot costs 12-15 AP.
# At 30-38 AP per turn that is 2, at most 3 shots — even standing still.
#
# SPEC §4.1 step 3: "attach_offset" is the DATA-DRIVEN fit of the weapon mesh
# inside the Wrist.R bone space of the Quaternius CharacterArmature rig.
#   position — Vector3, local offset inside the bone
#   rotation — Vector3, euler degrees (Z=+90 points the barrel along the arm)
#   scale    — float, UNIFORM scale (the bone has 100x world scale, so the
#              values are deliberately tiny; see Unit3D.WEAPON_FITS comment)
# Unit3D reads this table; when the field is missing it falls back to its own
# const table.
#
# "mesh" is the Assets3D.WEAPONS id of the model this weapon SHOWS. Every one of
# the five weapons now owns a distinct silhouette (JA2 recognizability, §4.1
# step 4) instead of the old two-way pistol/rifle split:
#   p9 slim 9mm · k45 heavy .45 · Huntsman long wooden pump · Dragonmaw short
#   black combat shotgun · SVD scoped sniper (by far the longest).
# ATTACH_OFFSET AND MESH BELONG TOGETHER: scale/rotation below are measured
# AGAINST THAT MESH. If the mesh file is missing, Unit3D falls back to the
# generic pistol/rifle model AND to the generic WEAPON_FITS numbers — never to
# this offset on a foreign mesh (which would show a stub or a giant).
#
# The scale is derived, not guessed: world length = obj_length * scale * 100
# (the bone's 100x). The target lengths against the 1.85-unit merc are
#   p9 0.38 · k45 0.44 · Dragonmaw 0.78 · Huntsman 1.00 · SVD 1.20
# — a deliberate size ladder, so weapon class is readable from the silhouette
# alone at ortho zoom. The two shotguns are pulled APART on purpose (0.78 vs
# 1.00): their meshes are only 10% apart in length and the pack's near-black
# materials hide the wood-vs-steel difference, so without the size gap the
# Huntsman and the Dragonmaw read as the same gun at tactical zoom.
#
# "position" corrects meshes whose ORIGIN is not at the grip. The bone applies
# rotation BEFORE translation, and Z=+90 maps mesh +X -> bone +Y and mesh +Y ->
# bone -X; so for a mesh whose grip sits at mesh (0, gy) the correction is
# position.x = +gy * scale. Measured against pistol.obj, whose fit is the
# verified reference: its origin sits 0.123 below the front of the slide.
#   pistol_5 sits 0.055 below -> grip is 0.068 LOWER  -> x = -0.068 * scale
#   pistol_4 sits 0.416 below (its origin is buried in the extended magazine)
#            -> grip is 0.293 HIGHER -> x = +0.293 * scale. Without this the
#            K45 juts sideways out of the fist instead of sitting in it.
# The three long guns already carry their origin at the wrist of the stock, so
# they need no correction.
#
# "snd" is the per-weapon gunshot in assets/sfx/fx. The legacy keys
# shot_p/shot_s/shot_r still exist in Sfx as fallbacks (see sfx.gd).
const WEAPONS := {
	"p9": {
		"name": "P9 9mm Pistol", "short": "P9", "cal": "9mm",
		"dmg": 24, "var": 6, "range": 10, "ap": 12, "mag": 15, "reload": 6,
		"acc": 5, "pose": "gun", "snd": "shot_p9", "shotgun": false, "aim_max": 2,
		"mesh": "pistol_9mm",   # pistol_5.obj — slim service pistol, 1.819 long
		"attach_offset": {"position": Vector3(-0.00014, 0.0, 0.0), "rotation": Vector3(0.0, 0.0, 90.0), "scale": 0.00209},
	},
	"k45": {
		"name": "K45 .45 Pistol", "short": "K45", "cal": "45",
		"dmg": 30, "var": 7, "range": 8, "ap": 14, "mag": 7, "reload": 6,
		"acc": 0, "pose": "gun", "snd": "shot_k45", "shotgun": false, "aim_max": 2,
		"mesh": "pistol_45",    # pistol_4.obj — taller, boxier frame, 1.976 long
		"attach_offset": {"position": Vector3(0.00065, 0.0, 0.0), "rotation": Vector3(0.0, 0.0, 90.0), "scale": 0.00223},
	},
	"flinte": {
		"name": "\"Huntsman\" Shotgun", "short": "Huntsman", "cal": "schrot",
		"dmg": 40, "var": 10, "range": 6, "ap": 15, "mag": 6, "reload": 7,
		"acc": 0, "pose": "machine", "snd": "shot_huntsman", "shotgun": true, "aim_max": 1,
		"mesh": "shotgun_pump",   # shotgun_2.obj — WOODEN stock/forend, 5.785 long
		"attach_offset": {"position": Vector3.ZERO, "rotation": Vector3(0.0, 0.0, 90.0), "scale": 0.00173},
	},
	"drachenmaul": {
		"name": "\"Dragonmaw\" Shotgun", "short": "Dragonmaw", "cal": "schrot",
		"dmg": 48, "var": 8, "range": 7, "ap": 15, "mag": 8, "reload": 7,
		"acc": 5, "pose": "machine", "snd": "shot_dragonmaw", "shotgun": true, "aim_max": 2,
		"mesh": "shotgun_combat", # shotgun_1.obj — all BLACK, shorter, 5.215 long
		"attach_offset": {"position": Vector3.ZERO, "rotation": Vector3(0.0, 0.0, 90.0), "scale": 0.00150},
	},
	"svd": {
		"name": "SVD Sniper Rifle", "short": "SVD", "cal": "762",
		"dmg": 46, "var": 8, "range": 15, "ap": 15, "mag": 10, "reload": 7,
		"acc": 12, "pose": "machine", "snd": "shot_svd", "shotgun": false, "aim_max": 3,
		"mesh": "sniper_scoped",  # sniperrifle_1.obj — SCOPE on top, 7.295 long
		"attach_offset": {"position": Vector3.ZERO, "rotation": Vector3(0.0, 0.0, 90.0), "scale": 0.00164},
	},
}

const GRENADE := {"dmg": 45, "dmg_edge": 22, "radius": 1.5, "ap": 15}
const MEDKIT_AP := 12
const SEARCH_AP := 6
const SWAP_AP := 4
# Aimed fire in steps (JA1): each level +3 AP and +7% hit chance.
const AIM := {"ap_step": 3, "bonus_step": 7, "max": 3}

# Hit zones (JA2): head = risky but lethal (halves armor), legs = less damage
# but the target is crippled. Bot/AI always shoot torso.
const ZONES := {
	"torso": {"name": "Torso", "hit_mod": 0, "dmg_mult": 1.0, "pierce": 0.0},
	"kopf": {"name": "Head", "hit_mod": -25, "dmg_mult": 1.75, "pierce": 0.5},
	"beine": {"name": "Legs", "hit_mod": -10, "dmg_mult": 0.7, "pierce": 0.0},
}
const ZONE_ORDER := ["torso", "kopf", "beine"]
const CRIPPLE_ROUNDS := 2        # Leg hit: rounds with doubled step cost
const CRIPPLE_PRONE_DMG := 18    # from this leg damage the target goes down

# Stances (JA): movement cost factor (num/den, integer per step), own aim bonus,
# penalty for attackers hitting this stance, AP per change step.
# tempo = visible movement slowdown (tween factor, purely cosmetic).
const STANCES := {
	"stand": {"name": "Standing", "move_num": 1, "move_den": 1, "att_bonus": 0, "def_mod": 0, "tempo": 1.0},
	"crouch": {"name": "Crouching", "move_num": 2, "move_den": 1, "att_bonus": 5, "def_mod": -15, "tempo": 1.5},
	"prone": {"name": "Prone", "move_num": 3, "move_den": 1, "att_bonus": 10, "def_mod": -30, "tempo": 2.2},
}
const STANCE_ORDER := ["stand", "crouch", "prone"]
const STANCE_AP := 2             # AP per stance-change step (combat only)
const PRONE_SPOT_MULT := 0.6     # prone units are spotted only at 60% sight range

# ------------------------------------------------------------------ Items (JA1 inventory)
const ITEMS := {
	"p9": {"name": "P9 9mm Pistol", "short": "P9", "kind": "weapon"},
	"k45": {"name": "K45 .45 Pistol", "short": "K45", "kind": "weapon"},
	"flinte": {"name": "\"Huntsman\" Shotgun", "short": "Huntsman", "kind": "weapon"},
	"drachenmaul": {"name": "\"Dragonmaw\" Shotgun", "short": "Dragonmw.", "kind": "weapon"},
	"svd": {"name": "SVD Sniper Rifle", "short": "SVD", "kind": "weapon"},
	"mag_9mm": {"name": "9mm Magazine (15)", "short": "9mm Mag", "kind": "ammo", "cal": "9mm"},
	"mag_45": {"name": ".45 Magazine (7)", "short": ".45 Mag", "kind": "ammo", "cal": "45"},
	"mag_schrot": {"name": "Shotgun Shells (6)", "short": "Shells", "kind": "ammo", "cal": "schrot"},
	"mag_762": {"name": "7.62mm Magazine (10)", "short": "7.62 Mag", "kind": "ammo", "cal": "762"},
	"granate": {"name": "Hand Grenade", "short": "Grenade", "kind": "grenade"},
	"medkit": {"name": "Medkit", "short": "Medkit", "kind": "medkit"},
	# Ashveil Salve — double-strength medkit, lab/elite loot (reserved, §0/§4).
	"ashveil_salve": {"name": "Ashveil Salve", "short": "Salve", "kind": "medkit"},
	# SPEC v5 §3.3.3 — the storehouse cellar is locked. Its key hangs on the
	# guard posted at the hatch; looting his corpse yields this item (the
	# alternative is breaching the door). kind "key" is deliberately NOT one of
	# the inventory action kinds (weapon/ammo/grenade/medkit), so the HUD lists
	# it in the pack without offering a use button.
	"cellar_key": {"name": "Storehouse Cellar Key", "short": "Cellar Key", "kind": "key"},
}
const INV_SLOTS := 8

## Crate loot: [weight, item]
const LOOT_TABLE := [
	[30, "mag_9mm"], [22, "mag_45"], [16, "mag_schrot"], [8, "mag_762"],
	[12, "granate"], [14, "medkit"], [3, "k45"], [3, "flinte"],
]

# ------------------------------------------------------------------ Difficulty
const DIFFICULTY := {
	"leicht": {
		"name": "EASY", "order": 0,
		"desc": "Standard merc rates · shaky enemy aim · full crates",
		"cost_mult": 1.0, "marks_mod": -5, "loot_min": 2, "loot_max": 2, "enemies": 8,
	},
	"normal": {
		"name": "NORMAL", "order": 1,
		"desc": "Merc rates x1.25 · standard",
		"cost_mult": 1.25, "marks_mod": 0, "loot_min": 1, "loot_max": 2, "enemies": 10,
	},
	"schwer": {
		"name": "HARD", "order": 2,
		"desc": "Merc rates x1.5 · sharp enemies · lean crates · Helix elites",
		"cost_mult": 1.5, "marks_mod": 5, "loot_min": 1, "loot_max": 1, "enemies": 13,
	},
}

# ------------------------------------------------------------------ Mercs
# Portrait params: skin, hair, style (0 bald, 1 short, 2 full, 3 mohawk),
# shades, beard, cap (color or null), cloth. Equipment as an item list (JA1).
#
# SPEC §4.1 step 4 — 3D identity: "model" picks the BODY (a key of
# Assets3D.CHARACTERS) and "uniform" recolours ONLY the CLOTHING materials of
# that body — skin, hair, eyes, visor and earrings stay untouched (the deny-list
# lives in Unit3D.SKIN_MATERIALS). The tint PRESERVES each material's luminance,
# so dark boots stay dark and the figure keeps its shape.
#
# Since the Ultimate Modular Men/Women packs landed (20 bodies, same 62-bone rig
# and same 24 clips as the old Swat.glb — no retargeting), every merc has his or
# her OWN body, not just a recolour. Body + hue = recognizability at tactical
# zoom (JA2 principle):
#   Needle  m_beach       tan     Blitz  m_punk        navy   (blue mohawk)
#   Gramps  m_farmer      grey    Doc    m_adventurer  forest
#   Walrus  m_worker      olive   Frag   w_soldier     rust   (FEMALE)
#   Shade   w_scifi       black   Ivan   m_swat        maroon (FEMALE: Shade)
#   Fox     m_hoodie      khaki
# Greta "Frag" and Mira "Shade" are women and now finally render as such.
# The enemy militia keeps "enemy" (Casual.glb) and the Helix commander keeps
# "boss" (BusinessMan.glb), so neither can be confused with one of your mercs.
#
# Both fields are OPTIONAL: Unit3D/Tac3DUnit fall back to the Swat body with no
# tint if they are missing, so nothing breaks for entries without them (Otto,
# enemies, save games written before this field existed).
const MERCS := [
	{
		"id": "nadel", "name": "Jorg Nadel", "nick": "Needle",
		"quote": "Cheap, fast, mostly sober.",
		"bio": "A discount gun who talks fast and shoots faster. Nadel has been run out of three armies and two prisons. Cheap for a reason — but he shows up.",
		"hp": 55, "marks": 62, "agi": 70, "med": 20, "exp": 1,
		"weapon": "p9", "inv": ["mag_9mm", "mag_9mm", "mag_9mm", "granate", "medkit"], "cost": 400,
		"sprite": "manBrown", "tint": Color(1, 1, 1),
		"model": "m_beach", "uniform": Color(0.76, 0.57, 0.35),       # tan — washed-up cheap gun
		"portrait": {"id": "nadel", "skin": Color(0.85, 0.66, 0.48), "hair": Color(0.32, 0.22, 0.12), "style": 1, "shades": false, "beard": false, "cap": null, "cloth": Color(0.45, 0.36, 0.22)},
	},
	{
		"id": "blitz", "name": "Karl Blitzer", "nick": "Blitz",
		"quote": "Pay me before I run off again.",
		"bio": "Quick on his feet and quicker to vanish when the money is late. Blitz sprints where others crawl. Loyal exactly as long as the pay clears.",
		"hp": 65, "marks": 70, "agi": 90, "med": 25, "exp": 1,
		"weapon": "p9", "inv": ["mag_9mm", "mag_9mm", "mag_9mm", "granate", "medkit", "medkit"], "cost": 500,
		"sprite": "manBlue", "tint": Color(1, 1, 1),
		"model": "m_punk", "uniform": Color(0.16, 0.24, 0.47),        # navy — matches his mohawk portrait
		"portrait": {"id": "blitz", "skin": Color(0.93, 0.76, 0.6), "hair": Color(0.85, 0.7, 0.3), "style": 3, "shades": false, "beard": false, "cap": null, "cloth": Color(0.25, 0.42, 0.6)},
	},
	{
		"id": "opa", "name": "Hannes Kruger", "nick": "Gramps",
		"quote": "I was losing wars back when you were still ammunition.",
		"bio": "Forty years behind a rifle and still the steadiest hand in the field. Gramps has forgotten more wars than most mercs will ever see. Slow to move, deadly to face.",
		"hp": 50, "marks": 84, "agi": 55, "med": 35, "exp": 2,
		"weapon": "svd", "inv": ["mag_762", "mag_762", "mag_762", "granate", "medkit", "medkit"], "cost": 700,
		"sprite": "manOld", "tint": Color(0.95, 0.92, 0.86),
		"model": "m_farmer", "uniform": Color(0.47, 0.48, 0.47),      # grey — weathered old-timer (has a moustache)
		"portrait": {"id": "opa", "skin": Color(0.88, 0.72, 0.58), "hair": Color(0.82, 0.82, 0.8), "style": 1, "shades": false, "beard": true, "cap": null, "cloth": Color(0.4, 0.4, 0.36)},
	},
	{
		"id": "doc", "name": "Dr. Elias Vogel", "nick": "Doc",
		"quote": "First I patch you up. Then the bill.",
		"bio": "A surgeon who traded the operating room for the battlefield — and the fee scale came with him. Doc keeps the squad breathing. He also keeps a ledger.",
		"hp": 60, "marks": 65, "agi": 65, "med": 95, "exp": 1,
		"weapon": "p9", "inv": ["mag_9mm", "mag_9mm", "mag_9mm", "medkit", "medkit", "medkit", "medkit"], "cost": 900,
		"sprite": "manOld", "tint": Color(0.85, 1.0, 0.92),
		"model": "m_adventurer", "uniform": Color(0.15, 0.34, 0.21),  # forest — field medic
		"portrait": {"id": "doc", "skin": Color(0.9, 0.74, 0.6), "hair": Color(0.25, 0.2, 0.16), "style": 1, "shades": true, "beard": false, "cap": null, "cloth": Color(0.75, 0.8, 0.78)},
	},
	{
		"id": "walross", "name": "Bruno Wall", "nick": "Walrus",
		"quote": "I'll take point. You're paying for the ammo.",
		"bio": "Built like the door he just kicked in. Walrus takes point, takes hits, and takes his time. Bring extra shells.",
		"hp": 95, "marks": 60, "agi": 50, "med": 15, "exp": 2,
		"weapon": "flinte", "inv": ["mag_schrot", "mag_schrot", "mag_schrot", "granate", "granate", "medkit"], "cost": 1400,
		"sprite": "survivor1", "tint": Color(1, 1, 1),
		"model": "m_worker", "uniform": Color(0.36, 0.40, 0.19),      # olive — broad, vest-wearing bruiser
		"portrait": {"id": "walross", "skin": Color(0.8, 0.6, 0.45), "hair": Color(0.15, 0.12, 0.1), "style": 0, "shades": false, "beard": true, "cap": null, "cloth": Color(0.3, 0.3, 0.3)},
	},
	{
		"id": "granate", "name": "Greta Spreng", "nick": "Frag",
		"quote": "If it got loud, that was me.",
		"bio": "If it went up in smoke, she lit it. Greta never met a problem a grenade could not rephrase. Stand well back.",
		"hp": 70, "marks": 68, "agi": 75, "med": 30, "exp": 2,
		"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "granate", "granate", "granate", "granate", "medkit"], "cost": 1600,
		"sprite": "womanGreen", "tint": Color(1, 1, 1),
		"model": "w_soldier", "uniform": Color(0.60, 0.28, 0.13),     # rust — FEMALE body (Greta Spreng)
		"portrait": {"id": "granate", "skin": Color(0.92, 0.72, 0.55), "hair": Color(0.65, 0.28, 0.12), "style": 2, "shades": false, "beard": false, "cap": null, "cloth": Color(0.28, 0.5, 0.3)},
	},
	{
		"id": "schatten", "name": "Mira Nacht", "nick": "Shade",
		"quote": "You won't hear me. Neither will they.",
		"bio": "You will not hear her coming and neither will the sentry. Mira works the flanks and the dark. By the time she is seen, it is already over.",
		"hp": 60, "marks": 78, "agi": 88, "med": 40, "exp": 2,
		"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "granate", "granate", "medkit", "medkit"], "cost": 1900,
		"sprite": "hitman1", "tint": Color(1, 1, 1),
		"model": "w_scifi", "uniform": Color(0.12, 0.12, 0.15),       # black — FEMALE body (Mira Nacht)
		"portrait": {"id": "schatten", "skin": Color(0.82, 0.64, 0.5), "hair": Color(0.08, 0.08, 0.1), "style": 2, "shades": true, "beard": false, "cap": null, "cloth": Color(0.12, 0.12, 0.14)},
	},
	{
		"id": "ivan", "name": "Ivan Petrov", "nick": "Ivan",
		"quote": "Nu davai. Ivan handles this.",
		"bio": "A legend borrowed from colder wars. Ivan speaks little, hits everything, and asks for his pay in full. Do not get between him and the objective.",
		"hp": 85, "marks": 88, "agi": 78, "med": 10, "exp": 3,
		"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "mag_45", "granate", "granate", "medkit"], "cost": 2200,
		"sprite": "survivor1", "tint": Color(0.95, 0.78, 0.72),
		"model": "m_swat", "uniform": Color(0.45, 0.13, 0.19),        # maroon — heavy tactical
		"portrait": {"id": "ivan", "skin": Color(0.87, 0.7, 0.56), "hair": Color(0.2, 0.16, 0.12), "style": 1, "shades": false, "beard": true, "cap": Color(0.55, 0.12, 0.12), "cloth": Color(0.5, 0.16, 0.16)},
	},
	{
		"id": "fuchs", "name": "Viktor Fuchs", "nick": "Fox",
		"quote": "One shot, one bill.",
		"bio": "One shot, one kill, one invoice. Fox is the most expensive trigger on the roster and worth every coin. Precise to the point of arrogance.",
		"hp": 70, "marks": 92, "agi": 72, "med": 30, "exp": 3,
		"weapon": "flinte", "inv": ["mag_schrot", "mag_schrot", "mag_schrot", "mag_schrot", "granate", "granate", "medkit", "medkit"], "cost": 2500,
		"sprite": "survivor1", "tint": Color(1.0, 0.82, 0.62),
		"model": "m_hoodie", "uniform": Color(0.58, 0.56, 0.33),      # khaki — lean marksman
		"portrait": {"id": "fuchs", "skin": Color(0.9, 0.7, 0.52), "hair": Color(0.75, 0.4, 0.15), "style": 1, "shades": true, "beard": false, "cap": null, "cloth": Color(0.6, 0.42, 0.2)},
	},
]

# ------------------------------------------------------------------ Tobias Rook (rescuable ally)
# Village elder of Rookhaven, held in his own storehouse cellar. NOT in MERCS
# (so he never shows up in the A.I.M. hiring screen). Voice = existing "opa"
# clips (old, gravelly, warm) — no new generation needed. Internal id stays
# "otto" so the orchestrator/test harness keep working; the player only sees
# the name "Tobias Rook".
const OTTO := {
	"id": "otto", "name": "Tobias Rook", "nick": "Elder", "voice": "opa",
	"quote": "Took you long enough.",
	"hp": 90, "marks": 80, "agi": 52, "med": 25, "exp": 3,
	"weapon": "k45", "inv": ["mag_45", "mag_45", "mag_45", "granate", "medkit"], "cost": 0,
	"sprite": "survivor1", "tint": Color(1, 1, 1),
	# Not a merc — a village elder: casual body, washed-out field green.
	"model": "m_casual", "uniform": Color(0.40, 0.45, 0.33),
	"portrait": {"skin": Color(0.86, 0.66, 0.5), "hair": Color(0.6, 0.55, 0.5), "style": 0, "shades": false, "beard": true, "cap": null, "cloth": Color(0.35, 0.42, 0.3)},
}

# ------------------------------------------------------------------ Rookhaven villagers (militia set dressing)
# SPEC v5 §3.3.5: once Tobias is free and The Hideout goes live, three villagers
# with shotguns show up in the village core. They are pure set dressing — the
# orchestrator keeps them out of `mercs`/`units`/`enemies`, so they take no turn
# and count towards neither the win nor the lose condition (same pattern as the
# captive). Ids are prefixed "villager_" and can never collide with a merc id.
const VILLAGERS := [
	{
		"id": "villager_1", "name": "Sena Rook", "nick": "Villager",
		"hp": 45, "marks": 45, "agi": 55, "med": 15, "exp": 1,
		"weapon": "flinte", "inv": ["mag_schrot"],
		"model": "w_adventurer", "uniform": Color(0.55, 0.42, 0.30),
		"sprite": "survivor1", "tint": Color(1, 1, 1),
		"portrait": {"skin": Color(0.86, 0.68, 0.52), "hair": Color(0.28, 0.2, 0.14), "style": 2, "shades": false, "beard": false, "cap": null, "cloth": Color(0.5, 0.4, 0.28)},
	},
	{
		"id": "villager_2", "name": "Aldo Merrin", "nick": "Villager",
		"hp": 50, "marks": 42, "agi": 50, "med": 10, "exp": 1,
		"weapon": "flinte", "inv": ["mag_schrot"],
		"model": "m_farmer", "uniform": Color(0.42, 0.46, 0.34),
		"sprite": "survivor1", "tint": Color(1, 1, 1),
		"portrait": {"skin": Color(0.82, 0.64, 0.48), "hair": Color(0.6, 0.55, 0.5), "style": 1, "shades": false, "beard": true, "cap": null, "cloth": Color(0.4, 0.44, 0.32)},
	},
	{
		"id": "villager_3", "name": "Pel Hask", "nick": "Villager",
		"hp": 55, "marks": 40, "agi": 48, "med": 10, "exp": 1,
		"weapon": "flinte", "inv": ["mag_schrot"],
		"model": "m_worker", "uniform": Color(0.36, 0.38, 0.42),
		"sprite": "survivor1", "tint": Color(1, 1, 1),
		"portrait": {"skin": Color(0.8, 0.62, 0.46), "hair": Color(0.2, 0.16, 0.12), "style": 0, "shades": false, "beard": false, "cap": null, "cloth": Color(0.34, 0.36, 0.4)},
	},
]

## Runtime dict for a villager (mirror of `otto_runtime`, but without hire/budget).
## `i` wraps, so a caller can never index out of range.
static func villager_runtime(i: int) -> Dictionary:
	var d: Dictionary = VILLAGERS[i % VILLAGERS.size()]
	var w: Dictionary = weapon(d["weapon"])
	var inv: Array = []
	for it in d["inv"]:
		inv.append(it)
	return {
		"id": d["id"], "name": d["name"], "nick": d["nick"],
		"hp": int(d["hp"]), "hp_max": int(d["hp"]),
		"marks": int(d["marks"]), "agi": int(d["agi"]), "med": int(d["med"]), "exp": int(d["exp"]),
		"weapon": d["weapon"], "ammo": int(w["mag"]), "inv": inv, "ammo_store": {},
		"armor": 0.0, "sight": 11, "sprite": d["sprite"], "tint": d["tint"],
		"portrait": d["portrait"], "cost": 0, "kills": 0, "alive": true,
	}

## Villager definition by id — {} when the id is not a villager.
static func villager_def(id: String) -> Dictionary:
	for v in VILLAGERS:
		if v["id"] == id:
			return v
	return {}


# ------------------------------------------------------------------ Enemies (Helix Bioscience)
# Enemies see a tick shorter than mercs (12 vs 13) — the player gets first
# sight contact. Marksmanship deliberately moderate.
const ENEMY_TYPES := {
	"miliz_p9": {
		"name": "Helix Militia", "exp": 1, "hp": 50, "marks": 48, "agi": 55, "weapon": "p9",
		"armor": 0.0, "sight": 12, "sprite": "soldier1", "tint": Color(1, 1, 1), "scale": 1.0,
	},
	"miliz_k45": {
		"name": "Helix Militia", "exp": 1, "hp": 55, "marks": 52, "agi": 55, "weapon": "k45",
		"armor": 0.0, "sight": 12, "sprite": "soldier1", "tint": Color(1, 1, 1), "scale": 1.0,
	},
	"miliz_flinte": {
		"name": "Helix Militia", "exp": 1, "hp": 60, "marks": 50, "agi": 50, "weapon": "flinte",
		"armor": 0.0, "sight": 12, "sprite": "soldier1", "tint": Color(1, 1, 1), "scale": 1.0,
	},
	"elite": {
		"name": "Helix Elite", "exp": 3, "hp": 80, "marks": 64, "agi": 65, "weapon": "k45",
		"armor": 0.25, "sight": 12, "sprite": "soldier1", "tint": Color(0.8, 0.55, 0.55), "scale": 1.0,
	},
	"elite_flinte": {
		"name": "Helix Elite", "exp": 3, "hp": 85, "marks": 60, "agi": 60, "weapon": "flinte",
		"armor": 0.25, "sight": 12, "sprite": "soldier1", "tint": Color(0.8, 0.55, 0.55), "scale": 1.0,
	},
	"boss": {
		"name": "Helix Commander Vargo", "exp": 5, "hp": 180, "marks": 78, "agi": 60, "weapon": "drachenmaul",
		"armor": 0.5, "sight": 14, "sprite": "soldier1", "tint": Color(1.0, 0.85, 0.45), "scale": 1.25,
		"portrait": {"skin": Color(0.8, 0.62, 0.48), "hair": Color(0.2, 0.18, 0.15), "style": 0, "shades": false, "beard": true, "cap": Color(0.65, 0.1, 0.1), "cloth": Color(0.75, 0.62, 0.25)},
	},
}

# ------------------------------------------------------------------ Boss dialogue
# SPEC v5 §3.2 CUTS the warlord boss fight (and this dialogue) from the demo —
# the orchestrator no longer opens the modal scene. The three constants below
# stay because `combat_hud.show_boss_dialog()` still reads them and that file is
# owned elsewhere; nothing on the demo path calls into it any more.
const BOSS_DIALOG := [
	{"speaker": "vargo", "text": "Well. The village rats hired themselves some guns. What did the old man promise you — his fishing nets?"},
	{"speaker": "merc", "text": "Enough for the rounds that end up in you."},
	{"speaker": "vargo", "text": "Then come. Helix armor has swallowed bigger bills than yours."},
]
const BOSS_CHOICES := [
	{"label": "Attack!", "reply": ""},
	{"label": "\"We could talk about you pulling out.\"", "reply": "Vargo laughs: \"I don't negotiate with corpses.\""},
]
const IVAN_DIALOG_LINE := "Vsyo, Commander. Ivan is here to collect."

# ------------------------------------------------------------------ Tobias Rook — rescue dialogue
## Spec §3.4: ONE voiced textbox sequence carrying EXACTLY three pieces of
## information — the situation, Maren, the mines. Deliberately no target sector
## for Maren: she is the open hook of the full game. Voice = "opa" clips
## (old, gravelly, warm), keys tobias_1..3 in assets/sfx/voice/.
const TOBIAS_DIALOG := [
	{"speaker": "tobias", "voice": "tobias_1", "text": "Helix owns this island now. The mines, the barracks, that manor out on the rock."},
	{"speaker": "tobias", "voice": "tobias_2", "text": "My daughter. They took her — because of her research. I don't know where."},
	{"speaker": "tobias", "voice": "tobias_3", "text": "Widow's Vein and Stoneglint. Diamonds. That's what pays for all of it. Whoever holds the mines holds the island."},
]

# ------------------------------------------------------------------ Texts
const MISSION_TITLE := "SECTOR F3 — ROOKHAVEN"
const MISSION_TEXT := "Helix Bioscience has seized Ashveil Isle — its mercenaries hold the fishing village of Rookhaven under occupation. The village elder, Tobias Rook, is locked in the storehouse cellar.\n\nInsert from the landing zone, push through the occupied village, and get Rook out alive."
const OBJECTIVES := [
	"Advance from the landing zone.",
	"Clear (or slip past) the Helix militia in the village.",
	"Reach the storehouse and breach the cellar.",
	"Free Tobias Rook.",
]
const TIPS := [
	"Tip: Crates and sandbags give 25% cover — walls and trees block shots completely.",
	"Tip: Move through an enemy's line of sight and you risk an interrupt shot.",
	"Tip: The shotgun is brutal under 4 tiles — at range its damage drops off hard.",
	"Tip: Grenades hit your own team too. Don't lob them onto your point man.",
	"Tip: Ammo is finite! Search crates and the fallen (6 AP) for magazines.",
	"Tip: Aiming (A) costs extra AP but adds hit chance per level.",
	"Tip: Save your AP — then your merc can interrupt enemies.",
	"Tip: Helix elite armor soaks half the damage. Grenades don't care.",
	"Tip: Before first contact the squad moves freely — grab a good position.",
	"Tip: In the inventory (I) you can swap weapons, use items, and drop dead weight.",
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

## SPEC §4.1 step 4 — 3D look of a character by merc id (MERCS + Tobias Rook).
## Returns {"model": String, "uniform": Color}; keys that the entry does not
## define are simply MISSING, so every caller keeps its own default. Unknown ids
## (enemies, boss, ids from old save games) yield an EMPTY dictionary — that is
## the documented "behave exactly as before" path (Swat body, no tint).
static func merc_look(id: String) -> Dictionary:
	var d := merc_def(id)
	if d.is_empty() and id == String(OTTO["id"]):
		d = OTTO
	if d.is_empty():
		d = villager_def(id)
	if d.is_empty():
		return {}
	var look := {}
	if d.has("model"):
		look["model"] = String(d["model"])
	if d.has("uniform"):
		look["uniform"] = d["uniform"]
	return look

## SPEC §4.1 step 3 — weapon fit inside the Wrist.R bone by WEAPON id.
## Returns {} when the id is unknown or carries no attach_offset; the caller
## (Unit3D) then uses its own hardcoded fallback table.
##
## The numbers are measured against weapon_mesh(id) — see the WEAPONS comment.
## A caller showing a DIFFERENT mesh must not apply them; Unit3D.weapon_fit_from
## enforces that.
static func weapon_attach(id: String) -> Dictionary:
	var w: Dictionary = WEAPONS.get(id, {})
	if not w.has("attach_offset"):
		return {}
	var off: Dictionary = w["attach_offset"]
	return off


## Assets3D.WEAPONS id of the model this weapon SHOWS ("" = no own mesh, the
## caller keeps the generic pistol/rifle). Unknown ids yield "" as well, so old
## save games and foreign code simply behave as before.
static func weapon_mesh(id: String) -> String:
	var w: Dictionary = WEAPONS.get(id, {})
	return String(w.get("mesh", ""))

# Runtime dict for Tobias Rook (mirror of Game._runtime, but without hire/budget),
# so the orchestrator and the test get the same dict.
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

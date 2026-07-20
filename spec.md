# SPEC v5 — BITTER HARVEST
### Turn-based mercenary tactics in Godot 4.6 · Full English consolidation

> **Status:** Binding specification **v5**. Supersedes SPEC v3 (DE), v4 (DE) and the v4.1 scope patch (DE). This document is **self-contained** — subagents need only this file. The old German specs remain in the repo under `docs/archive/` for reference.
>
> **What v5 changes:** (1) The entire game — all player-facing text, names, voice lines, code identifiers, comments, file names — switches to **English**. (2) All existing German voice clips are **regenerated in English** via the ElevenLabs MCP pipeline (§6). (3) Scope stays as slimmed down in v4.1: **two playable sectors, one rescue, one dialogue — the gameplay loop first.**

---

## 0. Language policy & migration

- **Everything English:** UI strings, `Db` entries (names, quotes, bios, item names), scene/file names, GDScript identifiers and comments, voice lines, save-slot titles, log/debug output.
- **German voice clips:** move to `assets/audio/voice/_archive/de/` (never delete — they cost money). All roles are regenerated per §6.
- **Input map:** rename actions to English; hotkey change: *Zielen (Z)* becomes **Aim (A)**. Full set: Reload **R** · Aim **A** · Grenade **G** · Medkit **H** · Crouch **C** · Inventory **I** · End turn **Enter** · Menu **Esc**.
- **Canonical renames** (binding; anything not listed keeps its name):

| Old (DE) | New (EN) | Note |
|---|---|---|
| »Söldnerkommando — Operation Silberfuchs« | **BITTER HARVEST** (no subtitle) | poster exists |
| Silberkelch (die Pflanze) | **the ashveil** | the island is named after the plant: grey-green and unremarkable by day ("veiled in ash"), teal glow at night — matches the map's glowing patches |
| Silbersalbe | **Ashveil Salve** | double-strength medkit, lab/elite loot |
| Der Unterschlupf | **The Hideout** | main-menu room + home base |
| »Opa« Hannes Krüger | **"Gramps"** Hannes Krüger | real names stay — international merc roster is genre flavor |
| »Blitz« Karl Blitzer | **"Blitz"** Karl Blitzer | works in English as-is |
| »Nadel« Jörg Nadel | **"Needle"** Jorg Nadel | drop umlauts in code/UI |
| »Doc« Dr. Elias Vogel | **"Doc"** Dr. Elias Vogel | unchanged |
| »Walross« Bruno Wall | **"Walrus"** Bruno Wall | |
| »Granate« Greta Spreng | **"Frag"** Greta Spreng | |
| »Schatten« Mira Nacht | **"Shade"** Mira Nacht | |
| Ivan | **Ivan** | untouchable. JA homage. |
| Flinte »Jagdstück« | shotgun **"Huntsman"** | |
| »Drachenmaul« | **"Dragonmaw"** | |
| »P9«, »K45«, »SVD« | unchanged | already language-neutral |
| Dorfältester Tobias Rook / Dr. Maren Rook / Helix Bioscience | unchanged | named in English already |

- Any roster entries or items not in this table follow the same rule: keep proper names, translate descriptors, drop umlauts in identifiers.

---

## 1. The gameplay loop (north star)

**Hire → enter sector → turn-based combat (move, shoot, cover, interrupts) → loot → base (heal, re-equip, save) → next sector / objective → end card.**

Build order inside the loop: **1. Combat** (if shooting doesn't feel good, nothing else matters) → **2. Loot** → **3. Base** → **4. Story dialogue**. Any feature that does not directly serve this loop gets deferred — even if it is already specified below. Polish starts only once the loop is playable end to end (F4 landing to end card; ugly is fine).

---

## 2. World: Ashveil Isle (map is final)

- The AI-generated map (10×6 grid, rows A–F × columns 1–10) is the **sector-map asset**: `res://assets/textures/worldmap.png`. Clickable sector hitboxes are data-driven (`data/sectors.json`).
- Canonical locations (spelling binding):

| Location | Sector(s) | Role (vision) | Demo |
|---|---|---|---|
| Landing zone (heli) | **F4** | entry point | **playable** |
| **Rookhaven** | **F2–F3** | fishing village, home base | **playable (F3)** |
| Briar Hollow | C3–C4 | second village, loyalty | locked |
| Widow's Vein Diamond Mine | E6 | income | locked |
| Stoneglint Diamond Mine | A5–B5 | income | locked |
| Hollowpoint Barracks | C7–D8 | Helix garrison, mid-boss | locked |
| **Helix Manor** | A9–B10 (pier B9) | corporate seat, **finale** | locked |

- **Demo sector logic:** start in **F4**. Only exit: **west → F3**. North (E4) and every other edge locked; UI shows "LOCKED" plus a one-line reason. In fiction: the northern ridge is a mined Helix exclusion zone — which is also the story reason the island must be liberated sector by sector later.

---

## 3. Story & characters (demo scope + hooks)

### 3.1 Premise
On **Ashveil Isle** grows the plant the island is named after: **the ashveil** — dull grey-green by day, glowing teal at night, its sap closes wounds like no medicine on earth. The pharma corporation **HELIX BIOSCIENCE** ("Helix") has seized the island: private soldiers in grey and black with a teal emblem, both diamond mines running as the war chest, headquarters at Helix Manor. The village of **Rookhaven** lives under occupation. Your anonymous employer (present only as text on the laptop) drops you in by helicopter: *find our contact in Rookhaven.*

### 3.2 Cast (demo)
- **Tobias Rook** — village elder of Rookhaven (the village bears his family's name). Held prisoner; after rescue he is the information giver and base keeper.
- **Dr. Maren Rook** — his daughter, botanist, the leading researcher of the ashveil. **Kidnapped by Helix, whereabouts unknown.** Demo: narration only; she is the main quest hook of the full game.
- **Helix troops** — militia grunts (pistol/shotgun, patrol, investigate noise) and, on HARD only, armored elites.
- Cut from demo, archived for the vision: warlord boss fight, the mad researcher and his lab, the burn/harvest ending choice (the `ending_choice` save field stays reserved). Vision: the mad researcher is Helix's head scientist at the Manor — the plant storyline reattaches there.

### 3.3 Demo flow (complete)
1. **Intro (short):** narrator text over black (mission: find the contact in Rookhaven), then **heli insertion into F4** — rotor noise, dust particles, squad spawns at the drop point. The heli never needs to be on screen (sound + dust + fade is enough).
2. **F4 — landing zone:** approach tutorial. 3–5 Helix patrols, open jungle-edge terrain, dry — **no water in the demo**. Objective marker: west exit.
3. **F3 — Rookhaven:** occupied village (8/10/13 enemies by difficulty; elites HARD only). **Tobias Rook** is locked in the storehouse cellar (level −1) — guarded door, breach it or loot the key from a guard.
4. **Rescue → dialogue scene** (one voiced textbox sequence, exactly three pieces of information, no more):
   - **The situation:** "Helix owns this island now. The mines, the barracks, that manor out on the rock."
   - **Maren:** "My daughter. They took her — because of her research. I don't know where." *(no target sector — deliberately open)*
   - **The mines:** "Widow's Vein and Stoneglint. Diamonds. That's what pays for all of it. Whoever holds the mines holds the island."
5. **Base goes live:** the cellar becomes **The Hideout** (§5.3, base mode: heal, stash, save; hire reinforcements via laptop). Three villagers with shotguns appear as militia set dressing in the village core.
6. **Demo end card** (image + narrator): "Rookhaven is free. Maren Rook is out there somewhere. And the mines keep digging — for Helix. — To be continued." → back to main menu. Flag `demo_finished`.

### 3.4 Hooks (documented, not built)
Mine income (both mines are already on the map) · Maren quest line (trail leads Briar Hollow → Hollowpoint Barracks → Helix Manor) · Manor finale with the head researcher and the burn/harvest choice · Briar Hollow loyalty · the B9 pier as a bridge set piece · ashveil fields = the teal map patches as visitable locations.

---

## 4. Feature specs

## 4.1 Character assets — "JA2-style people, weapons in hand"

**Reality anchor:** the JA3 reference screenshot is hand-crafted commercial art — not obtainable. The achievable target: **stylized low-poly figures visibly carrying weapons, animated through 8 pose states, under good lighting.** With the CC0 stack plus post-processing this looks genuinely presentable.

### Sourcing (all CC0 unless noted)
| What | Pack | Link | Format |
|---|---|---|---|
| Bodies (mercs/enemies/civilians) | **Ultimate Modular Men / Women** (modular heads/torsos/legs → 9 distinct mercs from one pack) | https://quaternius.com | glTF |
| Base rig | **Universal Base Characters** | https://quaternius.com | glTF |
| Animations (idle/walk/run/crouch/aim/shoot/reload/hit/death) | **Universal Animation Library** (120+) | https://quaternius.com | glTF |
| Alt. animations (161 incl. aim/reload/ranged) | **KayKit Character Animations** | https://kaylousberg.itch.io | glTF |
| Weapons with real names (AK47, sniper, 1911, 12-gauge …) | **Low Poly Weapon Pack** (search "byzmod3d") | https://opengameart.org | OBJ |
| Weapons alt. (stylized) | **Ultimate Guns / Animated Guns** | https://quaternius.com | FBX/glTF |
| Extra animations | **Mixamo** (free, **not** CC0 — do not redistribute raw files) | https://www.mixamo.com | FBX |
| GLB shortcut for Quaternius FBX | poly.pizza, Quaternius profile, **CC0 filter on** | https://poly.pizza | GLB |

### Pipeline "figure with weapon" (binding, package E)
1. Import modular character as glTF; on `Skeleton3D` set **BoneMap + SkeletonProfileHumanoid** (retargeting).
2. Retarget animations as an **AnimationLibrary**. Mandatory set: `idle, walk, run, crouch_idle, aim, shoot, reload, hit, death`.
3. Weapon (OBJ/GLB) via **`BoneAttachment3D`** on the right-hand bone; one `Transform3D` offset preset per weapon type in `Db.WEAPONS.attach_offset`.
4. One **prefab per merc** `res://scenes/units/merc_<id>.tscn`: module combo + material colors (uniform!) + weapon. Color code per merc = recognizability at distance (JA2 principle).
5. **Scale** everything to `tile_size = 1 m`; test scene `unit_gallery.tscn` shows all 9 side by side (review screenshot).

### Portraits & 2D art (poster style)
The existing AI portrait pipeline stays. Binding prompt template for consistency:
> *"gritty painted portrait of a mercenary, [age, hair, distinguishing feature, clothing], tropical jungle war setting, muted olive and brown palette, weathered paper texture background, 1990s tactical game character art, oil painting style, head and shoulders, facing slightly left"*
- 512×512 generation, export 256×256 PNG to `res://assets/textures/portraits/<merc_id>.png` (loader already prefers files).
- Every portrait faces slightly left → uniform gallery. Poster/end-card slides: same pipeline, 1920×1080.

## 4.2 Hiring screen — fix + centered dossier

**Bug (current):** the dossier popup renders bottom-right, partially off-screen. Suspected cause: popup is a child of the list container and inherits its anchors instead of living in its own overlay.

**Target:**
1. **Own overlay:** `CanvasLayer` (layer 10) → `Control` (Full Rect) → dimming `ColorRect` (black, alpha 0.55, catches clicks) → `CenterContainer` → `PanelContainer` (dossier card).
2. **Exactly centered** regardless of window size. Max width 620 px, max height 82% of viewport; internal `ScrollContainer` on overflow.
3. **Close:** click on dimmed background, `Esc`, or X button. **Open:** click a merc row. Focus trap while open.

**Dossier content** (two columns — portrait block left, data right):
| Zone | Content |
|---|---|
| Header | Full name · "Nickname" · price (large) · experience rank as a word (Rookie/Veteran/Elite) |
| Left | Portrait 256 px · quote in a speech bubble · **▶ button plays the select/quote voice clip** (`Sfx.play_voice(id, "quote")`) |
| Right top | **All stats as bars** (HP, MRK, AGI, MED, EXP) with numbers; bar color: <40 red, 40–69 gold, ≥70 green |
| Right middle | **Equipment list with icons** (`Assets.item_icon`): weapon, magazines, grenades, medkits |
| Right bottom | **Bio: 2–3 sentences** (new `bio` field in `Db.MERCS`, written by package G) · daily rate (display only) |
| Footer | Buttons: **Hire** (or **Dismiss** if on the team) · Close. Insufficient budget: Hire disabled + tooltip "Not enough budget" |

**List-screen polish:** team panel shows portrait thumb + weapon + price + quick-dismiss; candidates sorted by price ascending, hired ones greyed at the end; budget display pulses red on a failed purchase.

**Acceptance (package B):** screenshot proof at 1280×720 **and** 1920×1080 — dossier optically centered (±4 px), nothing clipped; Esc/outside click closes; voice button plays clip (or synth fallback).

## 4.3 Main menu, JA1 style — the walkable room

**Concept:** the main menu is **a place, not a menu**: The Hideout as a 3D room, fixed camera, hotspot interaction — the JA1 principle (reference: Control / View Team / Save / Restore / Contact A.I.M. / Sleep / Leave). Double use: the same room is the in-game home base — build once, use twice.

**Scene `res://scenes/menu/hideout.tscn`:** KayKit **Dungeon Pack Remastered** (walls/floor/door/stairs) + **Furniture Bits** (bed, table, shelf) + Quaternius **Survival Pack** (crates, lantern, radio). Props: bed, table with **laptop**, **wall map** of the island, **radio**, ammo crates, door. One ashveil plant in a jar on the shelf (teal `OmniLight3D` — story nod + key light). Camera: perspective `Camera3D` (FOV ≈ 50°), slightly elevated — **not** the tactical ortho rig. Warm lantern light + cool teal, light vignette. Title overlay "BITTER HARVEST" on first load, fades after 2 s or click.

**Hotspots** (each `Area3D` + `CollisionShape3D`):
| Hotspot | Action | Implementation |
|---|---|---|
| **Bed** | "Deploy" — start/continue campaign → difficulty (new game only) → island map | existing new-game flow |
| **Laptop** | "A.I.M." — hiring | **camera tween (0.6 s) zooms onto the screen**, crossfade into the 2D hiring screen (§4.2). `Esc` zooms back |
| **Wall map** | view sector map (read-only pre-game; base mode: choose deployment) | same camera-zoom trick |
| **Radio** | options: music/SFX volume, fullscreen | small centered panel (same overlay technique as dossier) |
| **Notebook/field radio** | **Save/Load** (§4.4) | slot panel overlay |
| **Door** | Quit (confirm dialog) | `get_tree().quit()` |

**Feedback (mandatory):** hover = outline/emission boost + floating label ("Deploy", "A.I.M. network", "Save", "Quit" …) + pointer cursor; mouse picking via camera ray. First visit: all labels visible 3 s (onboarding). **Modes:** `mode` enum in `hideout.gd` maps hotspot actions for *main menu* vs *base* (bed = rest/heal, crates = stash, door = back to map). **Feature flag** `Game.USE_HIDEOUT_MENU := false` keeps the current 2D menu until the room is ready.

## 4.4 Save & load

- **JSON** via `FileAccess`: `user://saves/slot_<n>.json` (n = 1..3) + `user://saves/autosave.json`. Header per save: `{"version": 1, "timestamp", "title": "Day 2 · Rookhaven", "playtime_sec"}` — loader rejects unknown versions with a clean message, never a crash.
- **Schema (frozen by P0):**
```
difficulty, budget, day,
team: [ { id, hp, hp_max, xp, level, inventory: [...], equipped: {weapon, ammo_loaded}, alive } ],
base: { unlocked, stash: [...] },
sectors: { "<sector_id>": { cleared, enemies_dead: [ids], loot_taken: [ids], doors_open: [ids] } },
flags: { tobias_freed, demo_finished, ending_choice, logs_found: [] },
world: { current_sector, squad_positions? }
```
- **Save points (demo):** only **between** fights — in The Hideout (notebook hotspot) and **autosave on every sector transition** plus after the rescue. Mid-combat quicksave (F5/F9) = documented expansion; `world.squad_positions` is reserved for it.
- **UI:** slot panel (3 slots + autosave) as centered overlay; per slot: title, date, day, sector, team portrait thumbs. Overwrite with confirmation. Reachable from main menu, base, and pause menu (Esc → Save, disabled during combat).
- **Autoload `SaveGame`:** `save(slot) -> bool`, `load(slot) -> bool`, `list_slots() -> Array[Dictionary]`, `has_autosave() -> bool`; signals `saved(slot)`, `loaded(slot)`. State access **only** through the P0 interfaces of `Game`/`Db` — never direct scene access.
- **Robustness:** write to temp file + rename (no half-written saves); validate mandatory fields on load; corrupt file → slot shown as "damaged", no crash.
- **Acceptance (package D):** headless save→reset→load roundtrip with assertions on budget/team/flags/sector state, exit 0; plus a manual save-quit-restart-load-continue test.

---

## 5. Voices — full English regeneration via ElevenLabs MCP

> **All roles are (re)generated in English.** The German clips move to `assets/audio/voice/_archive/de/`. The pipeline is **manifest-driven** so one subagent (package F) runs it end to end and any future line = one manifest entry + rerun.

### 5.1 Manifest `res://assets/audio/voice_manifest.json` — now covers the full cast
Clip types per merc: `select` (2), `move_ack` (2), `quote` (1), `pain` (2), `death` (1). Plus `tobias` (rescue, base_welcome, info_1..3, battle_1, battle_2) and `narrator` (intro, demo_end).

Reference quotes (English rewrites of the established German lines — package G finalizes the rest in this voice):
| Merc | Quote |
|---|---|
| "Gramps" Hannes Krüger | "I was losing wars back when you were still ammunition." |
| "Doc" Dr. Elias Vogel | "First I patch you up. Then the bill." |
| "Blitz" Karl Blitzer | "Pay me before I run off again." |
| "Needle" Jorg Nadel | "Cheap, fast, mostly sober." |
| "Walrus" Bruno Wall | "I'll take point. You're paying for the ammo." |
| "Frag" Greta Spreng | "If it got loud, that was me." |
| "Shade" Mira Nacht | "You won't hear me. Neither will they." |

Voice-design fields (English descriptions, e.g. `tobias`: "old fisherman, gravelly warm voice, slow, tired but unbroken"; `narrator`: "deep weathered war-documentary narrator, measured"). Pain sounds as text approximations ("Agh!", "Nngh—"), two variants each; combat barks ≤ 6 words; no stage directions in the text — emotion via voice design + phrasing.

### 5.2 Subagent procedure (package F)
1. Read manifest. For every character without a `voice_id`: create the voice via the MCP server from `voice_design`; write the resulting `voice_id` back into the manifest.
2. Per line: TTS via MCP → MP3 → `res://assets/audio/voice/<char>/<line_key>.mp3` (44.1 kHz, mono).
3. **Loudness normalization** to ≈ −16 LUFS (ffmpeg `loudnorm`) — otherwise one merc whispers and another screams.
4. No code changes needed: `sfx.gd` is file-preferred with a synth fallback — clips play as soon as the files exist; a missing file never breaks the game.
5. Acceptance: script compares manifest lines vs files on disk; 100% coverage; spot-check listened.

---

## 6. Engine reference (condensed — full detail lives in archived v3 §7–§9, still technically valid)

- **Camera:** `Camera3D`, `PROJECTION_ORTHOGONAL`, `size` = zoom. Gimbal rig: yaw pivot (45° steps, tweened) → tilt (≈ −30°) → camera; clamped hard to the map; `far` generous (~200) against ortho shadow artifacts.
- **Grid truth:** `Dictionary Vector3i → TileData` (type, level, walkable, cover, sight blocker, flags). GridMap/MultiMesh are display only. Levels: 0 ground, −1 cellar (demo); water/bridge flags exist in the data model but are **not implemented** in the demo.
- **Pathfinding:** `AStar3D`, one point per cell, edges only between truly connected cells; `set_point_weight_scale` for terrain cost, `set_point_disabled` for occupied/locked; AP cost = summed edge weights. Stairs connect level 0 ↔ −1.
- **Picking:** `project_ray_origin/normal` → `intersect_ray` against terrain layer (or per-level `Plane` intersection).
- **Fog of war:** per-cell HIDDEN/EXPLORED/VISIBLE, recomputed on movement only; LOS via raycast against blocker layer; display as one `MultiMeshInstance3D` quad layer with per-instance colors.
- **Units:** glTF + BoneMap/SkeletonProfileHumanoid retargeting; `AnimationTree` state machine (idle/walk/run/crouch/aim/shoot/reload/hit/death); weapons via `BoneAttachment3D`.
- **Performance:** MultiMesh for ground/props/fog; `VisibleOnScreenEnabler3D`; LOD/visibility ranges; chunks on big maps.
- **Juice (mandatory before release, after the loop works):** hitstop (`Engine.time_scale` 0.05 for ~80 ms) · trauma² screenshake · muzzle flash (`GPUParticles3D` + `OmniLight3D` blink) · tracer (~50 ms) · blood `Decal` · `Label3D` damage numbers · white hit-flash · death anim + voice clip. Tuning constants centralized in `juice.gd`.
- **Combat rules (unchanged from v2/v3):** AP 20 + AGI/5; shot 12–15 AP → 2–3/turn; aim levels 0–3 (+3 AP, +7% each); symmetric interrupts (15% + 7%×level + AGI/6); sight 13/12; cover −25%, window −10%; noise alerts radius 9; neutral spawn, combat starts on sight contact, back to exploration after 2 contact-free rounds. Difficulty table from v3 §12 applies.

---

## 7. Parallel roadmap (subagent packages)

### 7.1 Ground rules (prevent merge chaos)
1. **P0 first, alone, small** — freeze interfaces before anything runs in parallel.
2. **File ownership:** every package exclusively owns its folders (table below). No package edits foreign files; missing API = report it, don't patch it.
3. **Contracts, not conversations:** packages communicate only via the P0 autoload signatures, signals, and the save schema.
4. Every package delivers: a runnable state (project opens clean), its headless smoke share, 1–2 proof screenshots, a short CHANGES.md.
5. **Integration (I1–I3) is sequential** and done by one agent (or you) — parallel agents never merge themselves.

### 7.2 P0 — freeze interfaces (blocker, ~1 session)
Final autoload APIs: `Game` (state flags, sector/team access, `USE_HIDEOUT_MENU`), `Db` (MERCS incl. `bio` + English names/quotes per §0, WEAPONS incl. `attach_offset`, ITEMS incl. `ashveil_salve`), `Sfx` (`play_voice(char, key)`), `Assets` (`unit_prefab(id)`, `prop(name)`), `SaveGame` (§4.4). Save schema as `docs/save_schema.md`. Folder conventions (`scenes/menu|units|ui`, `scripts/autoload`, `assets/models/<pack>`, `assets/audio/voice/<char>`). Stub implementations of all new signatures (compiles, `push_warning("stub")`). **P0 also executes the §0 rename table across `Db` and UI strings** — one atomic language migration before parallel work starts.

### 7.3 The seven parallel packages
| Pkg | Mission | Owns (exclusive) | Depends on | Definition of done |
|---|---|---|---|---|
| **A · 3D core** | ortho camera rig, tile layer, AStar3D incl. levels 0/−1 + stairs, picking, fog | `scripts/tactical3d/`, `scenes/tactical3d.tscn` | P0 | test map: cube walks, descends stairs to −1; smoke green |
| **B · UI** | §4.2 (dossier fix + full build-out) + level-switch HUD | `scenes/ui/`, `scripts/ui/` | P0 | §4.2 acceptance incl. 720p/1080p screenshots |
| **C · Main menu** | §4.3 (room, hotspots, camera zooms, both modes) | `scenes/menu/`, `scripts/menu/` | P0 (placeholder meshes until E lands) | all 6 hotspots work; feature-flag fallback intact |
| **D · Save** | §4.4 (SaveGame autoload, slot UI, autosave hooks) | `scripts/autoload/save_game.gd`, `scenes/ui/save_panel.tscn` | P0 (schema) | headless save→load roundtrip exit 0 |
| **E · Asset pipeline** | §4.1: download, import, retarget, 9 merc prefabs with weapons, props library, `unit_gallery.tscn` | `assets/models/`, `scenes/units/` | P0 | gallery screenshot: 9 figures, weapons in hand, `shoot` anim plays |
| **F · Voices** | §5 via ElevenLabs MCP (full English cast) | `assets/audio/voice/`, `voice_manifest.json` | P0 + texts from G (may start with reference quotes, re-run later) | 100% manifest coverage, normalized |
| **G · Story content** | §3: intro text, Tobias dialogue, 2 Helix radio logs (loot), end card, merc bios — all English | `data/story/`, `assets/textures/endings/` | P0 | all texts as JSON, consumable by F & I2 |

### 7.4 Integration (sequential)
- **I1 — units in 3D (A+E):** merc prefabs walk on the A grid, existing combat logic attached, anim states bound to actions. *← the loop's combat beat lives here; start I1 as soon as A and E land, even if B/C/D/F/G are still running.*
- **I2 — sectors & story (C+G+B):** build F4 + F3 (+ cellar), wire rescue → dialogue → base mode → end card, arm D's autosave hooks.
- **I3 — polish:** juice, ashveil lights, balance, loudness check, §8 acceptance run.
- Start order if not all seven run at once: **E and A first** (longest paths), then B/C/D/F/G in any order.

---

## 8. Acceptance criteria (demo, definition of done)
1. Opens in Godot 4.6.x without script errors; flow title → difficulty → hire → island map → **3D tactics** → end card is playable — **entirely in English**, no German string reachable in-game.
2. **The loop** is playable end to end: heli landing F4 → transition F3 → rescue → dialogue (3 infos) → base functions live (heal/stash/save/hire) → end card → `demo_finished` in the save.
3. Main menu = walkable room; all hotspots incl. laptop camera zoom; door quits with confirm; feature-flag fallback works.
4. Dossier exactly centered (720p + 1080p), full info per §4.2, voice button plays a clip.
5. Merc gallery: 9 distinguishable figures **with weapons in hand**, mandatory animation set runs.
6. Save/load: 3 slots + autosave, roundtrip test green, corrupt file doesn't crash.
7. All manifest voices present in English and loudness-matched; missing files fall back to synth, never crash. German clips archived, none referenced.
8. Juice visible on every hit: hitstop + shake + muzzle flash + tracer + decal + damage number.
9. Headless smoke (`-- --smoke`): map reachability (incl. stairs/−1), hire, loot, rescue, bot battle to end card, save roundtrip — **exit 0**.

---

## 9. Asset sources (all CC0 unless noted)
[Quaternius](https://quaternius.com) — characters/animations/guns/village/survival · [KayKit](https://kaylousberg.itch.io) — Dungeon Remastered (cellar!), Furniture/Restaurant Bits, Character Animations · [Kenney](https://kenney.nl) — Nature Kit (palms), Pirate Kit (pier/boat, vision) · [OpenGameArt](https://opengameart.org) — byzmod3d low-poly weapons (real names), CC0 palms · [Poly Haven](https://polyhaven.com) — textures/HDRIs · [godotshaders.com](https://godotshaders.com/shader-license/cc0/) — CC0 water shader (vision) · [poly.pizza](https://poly.pizza) — GLB shortcut (use the CC0 filter!) · [Mixamo](https://www.mixamo.com) — extra animations (free, not CC0, don't redistribute raw files). Portraits/poster/end cards: existing AI pipeline with the §4.1 prompt template.

*Independent fan project inspired by Jagged Alliance 1/2 — contains no original assets or data.*

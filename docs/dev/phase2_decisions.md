# PHASE 2 — ENTSCHEIDUNGEN & OWNERSHIP (verbindlich, überstimmt die Einzelpläne bei Konflikt)

Autoritative Spezifikation (VOLLSTÄNDIG lesen):
- Strang A (Kampf-Port): `C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/feee7203-f9ae-448f-bc8c-fcd8524942aa/scratchpad/p2_1.md`
- Strang B (Assets): `C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/feee7203-f9ae-448f-bc8c-fcd8524942aa/scratchpad/p2_2.md`
- Kritik: `C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/feee7203-f9ae-448f-bc8c-fcd8524942aa/scratchpad/p2_3.md`

Projekt-Wurzel: `c:/Users/User/Desktop/ja2_remasted`. Godot-Console-EXE: `C:/Users/User/Downloads/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe`.

## FROZEN FIXES (aus der Kritik — verbindlich)

**K1 — `unit3d.gd`-Kollision aufgelöst:**
- **`unit3d.gd` gehört AUSSCHLIESSLICH Strang B.** Strang A fasst `unit3d.gd` NICHT an (keine `set_tint`/`mesh_mat`-Ergänzung dort).
- Strang A löst Team-Identität in `Tac3DUnit` (combat/) über einen **eigenen Marker-Kind-Node**: ein kleines farbiges Mesh (z.B. `SphereMesh` r≈0.18, unshaded) als Kind, positioniert über der Einheit (`Vector3(0, 1.7, 0)`). `set_tint(col)` färbt NUR dieses Marker-Material. `set_seen(v)`/Sichtbarkeit über `self.visible = v` (Node3D-Built-in, hidet Body + Marker gemeinsam). So teilen A und B keine mutierbare Fläche.
- **`set_cell`-Offset besitzt B** (Modell-Fußpunkt, `+0.1`). A hartkodiert NIRGENDS `+0.5`, nutzt nur `Unit3D.set_cell`.

**K2 — Sicht pro Zielzelle (nicht Nachbarschaft):** `compute_vision` testet für jeden lebenden Merc `vision.unit_sees(merc, enemy.cell)` über ALLE Gegner (die Gegner-Zellen tragen ihr echtes `y`, auch Ebene 1). KEINE Quadrat-Nachbarschafts-Vorfüllung. Nur so wird der Boss auf `BOSS_HOME=(58,1,8)` je „seen" → `check_boss_dialog` feuert → `Game.boss_dialog_seen=true` → Smoke B4 grün.

**W1 — Granaten-Zerstörung nur auf Deckung:** `FLAG_DESTRUCT` wirkt nur auf **begehbare Deckungs-Kacheln** (`cover>0`, `begehbar=true`) → setzt dort `cover=0`. KEINE Wand-Zerstörung (Pathfinder3D hat für nicht-begehbare Zellen keinen Punkt → würde Rebuild brauchen). Sprengbare Wände = spätere Stufe.

**W2 — jede Download-URL EINZELN prüfen:** vor dem Speichern `curl -sIL <url>` → HTTP 200 UND die ersten 4 Bytes == `glTF` (bei GLB). NICHT von `barrel_small.gltf.glb` auf andere Namen extrapolieren (KayKit-Dungeon-Dateinamen sind uneinheitlich — manche `.gltf.glb`, manche `.glb`). Bei 404 die korrekte URL per GitHub-API/Repo-Listing finden.

**W3 — Import ist PFLICHT-Schritt:** nach den Downloads EINMAL `<console.exe> --headless --path . --import` laufen lassen, sonst schlägt `load("res://…glb")` fehl (kein `.godot/imported/`-Cache). Das ist Voraussetzung, bevor `--tac3d-shots` echte Modelle zeigt.

## DATEI-OWNERSHIP (keine Datei hat zwei Owner ausser main.gd mit getrennten Regionen)

| Datei | Owner | Inhalt |
|---|---|---|
| `scripts/tac3d/combat/tac3d_unit.gd` (Tac3DUnit) | **A** | 3D-Kampfeinheit, Marker-Node für Team (K1), erbt Unit3D |
| `scripts/tac3d/combat/tac3d_vision.gd` (Tac3DVision) | **A** | Gitter-LOS + Sicht (K2-konform) |
| `scripts/tac3d/combat/tac3d_mapgen.gd` (Tac3DMapGen) | **A** | 72×72-Kampfkarte, Fluss/Brücke/Dorf/Anwesen |
| `scripts/tac3d/combat/tac3d_ai.gd` (Tac3DAI) | **A** | Gegner-KI, `ctl` UNTYPED (Zyklus) |
| `scripts/tac3d/combat/tactical3d_combat.gd` (kein class_name) | **A** | Orchestrator/Rundenablauf |
| `scripts/tac3d/unit3d.gd` | **B** | Body-Swap Kapsel→Barbarian.glb + Waffe (handslot.r) + play_anim + follow_path-Anim + set_cell-Offset; ROBUSTER Fallback (Kapsel) wenn Assets3D/GLB fehlt |
| `scripts/assets3d.gd` (+ Autoload in `project.godot`) | **B** | Modell-Loader mit Cache + Primitiv-Fallback |
| `scripts/shaders/water_compat.gdshader` | **B** | Compatibility-sicherer Wasser-Shader (kein depth/screen) |
| `scripts/tac3d/ground_view.gd` | **B** | Wasser-Kacheln als 2. MultiMesh mit Shader (Boden bleibt Vertex-Farbe) |
| `scripts/tac3d/tactical3d.gd` | **B** | DirectionalLight3D + Environment + Props in `_props_root` (Demo-Screen) |
| `assets/models/**` (Downloads) | **B** | KayKit Barbarian + Props/Dungeon-GLBs; OGA-Gun-Zip → 1 OBJ |
| `scripts/main.gd` | **geteilt, getrennte Regionen** | **A:** `SCREENS`-Eintrag `tactical3d_combat` + `_smoke3d()`/`_smoke3d_fail()`/`_reachable3d()`. **B:** `_tac3d_shots`-Erweiterung (Soldat/Shoot/Death-Aufnahmen). |

## ABHÄNGIGKEIT: A und B laufen parallel
Strang A baut gegen das AKTUELLE `unit3d.gd` (Kapsel) — `Tac3DUnit` erbt `Unit3D` und ruft `super.setup()`, egal ob Body Kapsel (jetzt) oder GLB (nach B) ist. A braucht B NICHT. B ersetzt danach den Body; A's Marker + Logik bleiben gültig. `main.gd` wird von EINEM Integrations-Agenten am Ende verdrahtet (beide Regionen), um Schreibkonflikt zu vermeiden.

## BUILD-REIHENFOLGE
1. **Parallel:** (A) combat/* nach p2_1: erst `tac3d_unit.gd` ‖ `tac3d_mapgen.gd` ‖ `tac3d_vision.gd`, dann `tac3d_ai.gd`, dann `tactical3d_combat.gd`. — (B) Downloads+`--import` ‖ `assets3d.gd`+Autoload ‖ `water_compat.gdshader`, dann `unit3d.gd`-Swap, `ground_view.gd`-Wasser, `tactical3d.gd`-Licht/Props.
2. **Integration:** `main.gd` (beide Regionen) durch EINEN Agenten.
3. **Verifikation (Fix-Schleife, echtes Godot):** `--tac3d`=TAC3D OK · `--smoke`=SMOKE OK (Regression) · `--smoke3d`=SMOKE3D OK/Exit 0 (Bot-Schlacht bis Sieg, alle Assertions K/H/B/I aus p2_1 §4) · `--tac3d-shots` rendert echten Barbarian-Söldner (6 PNGs). Bei Fehlern: echte Godot-Meldung lesen → verantwortliche Datei fixen (Ownership beachten) → neu. NIEMALS tactical.gd/mapgen.gd/battle_unit.gd/db.gd/game.gd/sfx.gd/assets.gd anfassen.

## GDScript-FALLEN (aus beiden Plänen, verbindlich)
Typisierte Variant-Iteration (`var c: Vector3i = k`); `floori` statt `floor`; **Integer-Division bewahren** (`int(agi)/5` etc. — Balance!); `battle_ready`/`battle_finished` via `call_deferred`; keine Engine-`class_name`-Kollision (`Tac3D`-Präfix, Orchestrator ohne class_name); **`Tac3DAI.ctl` UNTYPED** (Zyklus-Falle); `Db.ENEMY_TYPES[type].duplicate(true)`; `await`-Ketten vollständig; `path_for` ent-/sperrt `u.cell` (Guard pathfinder3d.gd); `MOVE_AP.get(move_type, 2)`.

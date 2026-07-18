# PHASE 4 (JUICE) — ENTSCHEIDUNGEN & FIXES (verbindlich, überstimmt den Plan bei Konflikt)

Autoritative Spezifikation (VOLLSTÄNDIG lesen):
- Plan: `C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/feee7203-f9ae-448f-bc8c-fcd8524942aa/scratchpad/p4_1.md`
- Kritik: `C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/feee7203-f9ae-448f-bc8c-fcd8524942aa/scratchpad/p4_2.md`

Projekt: `c:/Users/User/Desktop/ja2_remasted`. Godot-Console-EXE: `C:/Users/User/Downloads/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe`.

## RENDERER-FAKT (verbindlich): `gl_compatibility`
`Decal` und `GPUParticles3D` rendern NICHT zuverlässig → **CPUParticles3D** statt GPU, **QuadMesh-Bodenquad** statt Decal fürs Blut. OmniLight3D/Label3D/ImmediateMesh/Engine.time_scale sind ok.

## FROZEN FIXES (aus der Kritik — verbindlich)

**F1 (KRITISCH, sonst kompiliert nichts):** `juice3d.gd` bekommt in Zeile 1 `class_name Juice3D`. Der Orchestrator nutzt `Juice3D.new()` UND `Juice3D.TRAUMA_SHOT/HITSTOP_KILL/...` — ohne class_name Parse-Error. (Der Plan schrieb fälschlich „kein class_name" — das gilt nur für Autoloads/Screens; Juice3D ist ein Peer-Modul wie CameraRig3D/CursorView3D, die alle class_name tragen.)

**F2 (time_scale-Leak):** Gürtel-und-Hosenträger gegen globale Zeitlupe: `Engine.time_scale = 1.0` in `Juice3D._exit_tree()` UND zusätzlich in `end_battle()` vor dem `goto`. Falls der Node während eines Hitstops gefreed wird, bleibt die Welt sonst permanent in 0.05×.

**F3 (Merge mit Phase 3):** Der juice-Aufbau kommt ans ENDE des `if not fast:`-Blocks in `_ready()` (NACH `picker.set_active_level(...)`), NICHT nach `hud.build()`. Feld `var juice = null` separat. Die Hooks in `shoot()`/`on_death()`/`do_grenade()` sind disjunkt von Phase 3 (ui_*/_handle_click/_hud_refresh nicht anfassen).

**F4 (Verifikation deterministisch):** Der Juice-Test darf NICHT an einem zufälligen Treffer hängen (`hit_chance` ist auf 5–95 geklemmt → ~5% Miss). Asserts auf DETERMINISTISCHES: nach einem Schuss (a) `juice`-Kinderzahl > 0 (Mündungsfeuer/Tracer erzeugt), (b) nach dem Hitstop `Engine.time_scale == 1.0` (der schärfste Wächter der Phase). Label3D/Blut nur „falls Treffer" prüfen. Optional globalen RNG vorher seeden.

**Klein (F5):** Schadenszahl-Ausblenden auch `outline_modulate:a → 0` tweenen (sonst bleibt der Umriss opak stehen).

## HEADLESS-GATING-DISZIPLIN (kritisch für den Bot)
`juice` wird NUR im `if not fast:`-Block gebaut. JEDER Hook `if not fast and juice != null:` (bzw. `if not fast:` für Sfx). Im `--smoke3d` (fast=true) ist `juice==null` → kein `Engine.time_scale`, keine Partikel, kein `add_trauma`. **Ein einziger vergessener `if not fast` verlangsamt den Bot fatal.** `--smoke3d` MUSS mit identischer Rundenzahl grün bleiben (auto_battle-Formeln unberührt).

## DATEI-OWNERSHIP
| Datei | Aktion |
|---|---|
| `scripts/tac3d/combat/juice3d.gd` (class_name Juice3D extends Node3D) | NEU — komplette Juice-API (hitstop/muzzle_flash/tracer/blood/damage_number/hit_flash/explosion), CPUParticles3D+QuadMesh, F2 _exit_tree-Reset |
| `scripts/tac3d/camera_rig.gd` | EDIT additiv — Trauma-Feld + `add_trauma(f)` + `_process()`-Shake (h_offset/v_offset/rotation.z sind frei/ungenutzt) |
| `scripts/tac3d/combat/tactical3d_combat.gd` | EDIT additiv — `var juice=null`; Setup am ENDE des not-fast-Blocks (F3); Hooks in shoot()/on_death()/do_grenade(), ALLE `if not fast and juice != null:`; end_battle() time_scale-Reset (F2). Kampf-Formeln UNBERÜHRT. |
| `scripts/main.gd` | EDIT additiv — `--juice-shots=<dir>`-Modus (Fenster-Screenshot eines Schusses mit Effekten), deterministische Asserts (F4) |

NIEMALS ändern: tactical.gd/mapgen.gd/battle_unit.gd/db.gd/game.gd/**sfx.gd**/assets.gd/ui_theme.gd/unit3d.gd/combat_hud.gd/cursor_view3d.gd (nur Sfx.play(...) aufrufen).

## BUILD-REIHENFOLGE
1. Parallel: `juice3d.gd` (NEU, class_name Juice3D, F1/F2) ‖ `camera_rig.gd` EDIT (Trauma-Shake).
2. `tactical3d_combat.gd` EDIT (juice-Feld + Setup am not-fast-Block-Ende + Hooks in shoot/on_death/do_grenade, gegated; end_battle-Reset).
3. `main.gd` EDIT (`--juice-shots`, deterministische Asserts).
4. Verifikation (Fix-Schleife, echtes Godot): `--smoke3d`=SMOKE3D OK (Regression, identische Rundenzahl!), `--hud3d`=HUD3D OK, `--smoke`=SMOKE OK, `--tac3d`=TAC3D OK, `--juice-shots` → Fenster-PNGs zeigen Mündungsfeuer/Tracer/Schadenszahl mitten im Schuss; im Test `Engine.time_scale==1.0` nach Hitstop.

## GDScript-FALLEN
`class_name Juice3D` (F1); Hitstop-Reset via `get_tree().create_timer(dur, true, false, true)` (4. Param ignore_time_scale=true, ECHT realzeit); `_hitstop_active`-Reentrancy-Guard; CPUParticles3D `emitting=true`+`one_shot=true`; transiente Effekt-Nodes `queue_free()` nach Lebensdauer; typisierte Variant-Iteration; Screenshot-Timing: Snap unmittelbar nach Effekt-Trigger (Effekte leben nur ~60ms).

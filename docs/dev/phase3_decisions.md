# PHASE 3 — ENTSCHEIDUNGEN & FIXES (verbindlich, überstimmt den Plan bei Konflikt)

Autoritative Spezifikation (VOLLSTÄNDIG lesen):
- Plan: `C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/feee7203-f9ae-448f-bc8c-fcd8524942aa/scratchpad/p3_1.md`
- Kritik: `C:/Users/User/AppData/Local/Temp/claude/c--Users-User-Desktop-ja2-remasted/feee7203-f9ae-448f-bc8c-fcd8524942aa/scratchpad/p3_2.md`

Projekt: `c:/Users/User/Desktop/ja2_remasted`. Godot-Console-EXE: `C:/Users/User/Downloads/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe`.

## FROZEN FIXES (aus der Kritik — verbindlich einzuarbeiten)

**C1 (KRITISCH) — Pause-/Inventar-Panels gehören ins HUD, nicht in den Node3D-Orchestrator.** Ein `Control` als direktes Kind eines `Node3D` hat keine Canvas-Transform → wird nicht gezeichnet. Deshalb: `CombatHud` baut Pause- und Inventar-Panel als Kinder von `CombatHud._root` (Control unter der CanvasLayer). `CombatHud` bekommt `toggle_pause()` und `toggle_inventory()`. Der Orchestrator delegiert nur: `ui_menu()` → `if hud: hud.toggle_pause()`; `ui_inventory()` → `if hud: hud.toggle_inventory()`. Das **Pause-Panel muss funktionieren** (Fortsetzen / Aufgeben → `end_battle("abort")` / Beenden). Inventar darf MVP sein (Slot-Panel mit Ausrüsten/Benutzen/Wegwerfen über `do_swap`/`do_reload`/`do_medkit`, ODER minimal ein Panel das die Hand+8 Slots listet) — aber im HUD, nicht im Orchestrator.

**C2 (KRITISCH) — Doppelschuss verhindern.** `shoot()` setzt kein `busy`. In `_handle_click` den Schuss klammern: `busy = true` VOR `await shoot(...)`, `busy = false` DANACH (oder lokaler `_click_busy`-Guard, der Re-Entry in `_handle_click` sperrt). Die Kernlogik von `shoot()` NICHT ändern.

**M3 — Hover-Guard:** `_update_hover()` ganz am Anfang: `if hover_cell == Picker3D.NONE: cursor.clear(); hud.hide_cursor(); return`.

**M4 — Cursor-Position:** `hud.set_cursor(text, get_viewport().get_mouse_position())` (Screen-Koordinaten; CanvasLayer ist kamera-unabhängig). NICHT die 3D-Zelle verwenden.

**M5 — battle_over-Gate:** In `_unhandled_input` die Tastenzweige (Tab/R/Z/G/H/I/Enter/Esc/1-4) und `_process`-Hover früh sperren wenn `battle_over` (nach Kampfende läuft Input noch bis zum deferred `goto("end")`).

**Klein:** `refresh()` färbt `_aim_btn.modulate` amber bei `aim_level>0`; `ui_end_turn()` im Anmarsch (kein Kampf) zeigt `hud.banner("Noch kein Feindkontakt")` statt stiller No-Op; `Db.GRENADE["radius"]` (Bracket-Zugriff, typisiert) konsistent; im `--hud3d`-Test H3 `prefix_for_ap(path_toward(m0,tgt), 12)` (mehr AP, robuster).

## DATEI-OWNERSHIP
| Datei | Aktion |
|---|---|
| `scripts/tac3d/combat/combat_hud.gd` (class_name CombatHud extends CanvasLayer) | NEU — HUD-View + Pause-/Inventar-Panel (C1) |
| `scripts/tac3d/combat/cursor_view3d.gd` (class_name CursorView3D extends Node3D) | NEU — Pfad/Ziel/Granaten-Feedback (MultiMesh+Meshe) |
| `scripts/tac3d/combat/tactical3d_combat.gd` | EDIT — Felder + `if not fast`-Aufbau + `ui_*` + `_handle_click`(C2) + `_update_hover`(M3) + `_hud_refresh()`-Hooks; Kernlogik/auto_battle/do_*/shoot UNBERÜHRT |
| `scripts/screens/title.gd` | EDIT — Button „3D-GEFECHT (BETA)" + `_start_3d_beta()` (Default-Team ivan/fuchs/doc/nadel, LEICHT) |
| `scripts/main.gd` | EDIT — Dispatch `--hud3d` (Interaktionstest) + `--hud3d-shots=` (Screenshot), plus `_hud3d()`/`_hud3d_shots()` |

## REGRESSION-GARANTIE
HUD/Cursor werden NUR bei `not fast` gebaut. `--smoke3d`/`--smoke`/`--tac3d` setzen `fast=true` (bzw. nutzen andere Screens) → `hud==null`, alle `_hud_refresh()` sind No-Ops, `auto_battle`/`_bot_*`/`do_*`/`shoot`-Kern werden NICHT editiert. Diese drei müssen grün bleiben. NIEMALS tactical.gd/mapgen.gd/battle_unit.gd/db.gd/game.gd/sfx.gd/assets.gd/ui_theme.gd ändern (ui_theme wird nur GELESEN).

## BUILD-REIHENFOLGE
1. Parallel: `combat_hud.gd` (inkl. C1-Panels) ‖ `cursor_view3d.gd`.
2. `tactical3d_combat.gd` EDIT (referenziert beide neuen Klassen; C2/M3/M4/M5 einarbeiten).
3. Parallel: `title.gd` EDIT ‖ `main.gd` EDIT (`_hud3d`/`_hud3d_shots`).
4. Verifikation (Fix-Schleife, echtes Godot): `--smoke3d`=SMOKE3D OK (Regression), `--smoke`=SMOKE OK, `--tac3d`=TAC3D OK, `--hud3d`=HUD3D OK (Auswahl+Move+Schuss+HUD-State), `--hud3d-shots` → Fenster-PNG zeigt Portraits/HP-AP-Balken/Aktionsleiste über der 3D-Szene.

## GDScript-FALLEN
`PRESET_FULL_RECT` nur via `set_anchors_and_offsets_preset` (NICHT set_anchors_preset — Größe-0-Falle, wie in tactical3d.gd:62 falsch); typisierte Variant-Iteration; `hud.build(orch)` nimmt orch UNTYPED (Zyklus); MultiMesh-Reihenfolge (format/mesh/use_colors vor instance_count) + TRANSPARENCY_ALPHA + UNSHADED; `picker.set_active_level(selected.cell.y)` bei Auswahl; Integer-Division bewahren (nur orch.*-Werte nutzen); await-Ketten fire-and-forget aus _unhandled_input.

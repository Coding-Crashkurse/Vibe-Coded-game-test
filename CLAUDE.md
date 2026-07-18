# Söldnerkommando — Projekt-Kontext für Claude Code

Godot-4.6.3-JA-Klon. **Zwei Spiele im selben Projekt:**
- **v2 2D-Spiel** (fertig, poliert): `scripts/screens/*.gd`, Flow Titel→Schwierigkeit→Anheuern→Insel→Laden→`tactical.gd` (2D). **Nur additiv anfassen — nie brechen.**
- **v3 3D-Umbau** (in Arbeit): `scripts/tac3d/` — echtes 3D mit Ortho-Kamera. Start: **F5 → Titelbutton „3D-GEFECHT (BETA)"**.

Verbindliche Spezifikation: **`spec.md`** (v3). Detail-Bauverträge: **`docs/dev/*.md`**.

## Renderer (KRITISCH)
`project.godot` = **`gl_compatibility`**. → KEIN `Decal`, KEIN `GPUParticles3D` (nutze `CPUParticles3D`), keine depth-/screen-basierten Shader. Materialien brauchen Licht ODER `SHADING_MODE_UNSHADED` (sonst pechschwarz).

## Architektur v3 (`scripts/tac3d/`)
- `tac3d_tile.gd` (Tac3DTile) — Kachel-Daten, `Kind`/`Move`-Enums.
- `grid3d.gd` (Grid3D) — `Vector3i→Tac3DTile` = Wahrheit; `cell_to_world` (y=ebene·3), `neighbors`, `add_link` (Brücke/Rampe).
- `pathfinder3d.gd` (Pathfinder3D) — AStar3D, je Zelle 1 Punkt, **flache Kostenmetrik (y=0)**; Brücke drüber ≠ drunter = getrennte Knoten.
- `camera_rig.gd` (CameraRig3D) — Ortho-Gimbal (Yaw 45°/Pitch −30°), `size`=Zoom, Trauma-Screenshake.
- `ground_view.gd` (GroundView3D) — Boden (per-Kind MultiMesh + Kenney-Repo-Texturen), erzeugt `Scenery3D`.
- `scenery3d.gd` (Scenery3D) — Wände/Dächer/Fels-Mesa/Palmen/Props/Steg (reine Optik).
- `unit3d.gd` (Unit3D) — lädt Quaternius-Charakter-GLB (SWAT/Casual/BusinessMan) + Waffe an Bone `Wrist.R`, `play_anim`. `_CLIPS` mappt auf `CharacterArmature|…`-Clips.
- `picker3d.gd`, `testmap3d.gd`, `tactical3d.gd` (Demo-Screen).
- `combat/`: `tac3d_unit.gd` (Tac3DUnit, Rolle→char_id), `tac3d_vision.gd` (Gitter-LOS + Höhenbonus), `tac3d_mapgen.gd` (72×72 Karte), `tac3d_ai.gd`, `tactical3d_combat.gd` (Orchestrator/Rundenablauf), `combat_hud.gd` (CombatHud), `cursor_view3d.gd`, `juice3d.gd` (Juice3D: Mündungsfeuer/Hitstop/Tracer/Blut/Schadenszahl).
- Autoloads: `Db`, `Assets` (2D), `Sfx`, `Game`, `Assets3D` (3D-Loader mit Fallback).

## Kern-Muster (unbedingt beibehalten)
- **Fallback überall:** fehlt ein GLB/Textur → Kapsel/Box; `play_anim` → No-Op. So bleiben Headless-Tests grün auch ohne Assets.
- **`fast`-Modus:** im Bot/Headless (`fast=true`) werden HUD/Cursor/Juice NICHT gebaut → Bot bleibt schnell, Kampf-Formeln unberührt.
- **Additiv:** v3 fasst v2-Dateien nie an (außer `main.gd` additiv: `SCREENS`-Einträge + CLI-Modi). Die v2-Kampf-Formeln leben in `tactical.gd`/`db.gd`/`game.gd` und werden 1:1 wiederverwendet.

## Tests (Godot-Console-EXE)
```
<godot_console.exe> --headless --path . --import          # Asset-Import-Cache bauen
<godot_console.exe> --headless --path . -- --smoke        # v2-2D-Bot bis Sieg  → SMOKE OK
<godot_console.exe> --headless --path . -- --tac3d        # 3D-Fundament        → TAC3D OK
<godot_console.exe> --headless --path . -- --smoke3d      # 3D-Kampf-Bot        → SMOKE3D OK
<godot_console.exe> --headless --path . -- --hud3d        # HUD-Interaktion     → HUD3D OK
# Fenster-Screenshot-Modi (BRAUCHEN Display, NICHT headless):
<godot_console.exe> --path . -- --hud3d-shots=<absdir>    # HUD über 3D
<godot_console.exe> --path . -- --tac3d-shots=<absdir>    # Testfeld
<godot_console.exe> --path . -- --juice-shots=<absdir>    # Effekte
```
**⚠️ CLOUD-HINWEIS:** In der Cloud gibt es nur **headless** — die Fenster-Screenshot-Modi brauchen einen Bildschirm. Rein visuelle Bugs (schwarze Materialien, falsche Modell-Skalen, T-Pose) sind headless **NICHT** sichtbar und die Smoke-Tests fangen sie nicht. **Nach Cloud-Änderungen lokal per F5 + Screenshot-Modus gegenprüfen.**

## Audio — kein API-Key zur Laufzeit nötig
Alle Stimmen/SFX/Musik sind als **Dateien** gebacken: `assets/sfx/voice/` (40), `assets/sfx/fx/` (14), `assets/music/` (10). `sfx.gd` spielt Dateien ab (Synth-Fallback), ruft **nie** die ElevenLabs-API zur Laufzeit. Der Key (`.env`, **gitignored**) dient nur zum **Generieren neuer** Clips — das **lokal** machen (Netz + Key), nicht in der Cloud. Otto (neuer NPC) kann eine bestehende Söldner-Stimme bekommen → keine Generierung nötig.

## Stand & Nächstes
**Fertig & verifiziert:** Phase 1 (3D-Fundament) · 2 (Kampf-Logik 3D) · 3 (HUD/spielbar) · 4 (Juice) · 5 (Söldner-Modelle) · 6 (Karten-Optik).
**Offen — Phase 7 (Demo-Inhalt + Audio + Politur):**
1. **Demo-Story:** Otto im Dorf-**Keller** befreien → Keller wird **Heimatbasis** (Ausrüsten/Heilen/Anheuern/Speichern) → **Vargo-Dialog** beim Sichtkontakt → Sieg-Ablauf. (spec.md §2/§5)
2. **Audio ins 3D:** gebackene **Söldner-Sprüche** (select/quote), **Vargo-Dialog**, **Kampf-/Erkundungs-Musik** im 3D-Kampf abspielen (das 2D `tactical.gd` zeigt das Muster; im 3D `tactical3d_combat.gd` noch verdrahten).
3. **Politur.**

## Arbeitsweise
Design → adversariale Kritik → Bau → **mit echtem Godot verifizieren** (alle Test-Modi grün). Nichts committen/pushen, was nicht verifiziert ist.
**GDScript-Fallen:** `class_name` nicht mit Engine-Klassen kollidieren (`Tac3D`-Präfix); typisierte Variant-Iteration (`var c: Vector3i = k`); `floori` statt `int`; `signal.emit.call_deferred()` bei Signalen in `_ready` nach `add_child`; Integer-Division bewahren (Balance); `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` bei Code-UIs.

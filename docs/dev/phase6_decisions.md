# PHASE 6 (KARTEN-OPTIK) — ENTSCHEIDUNGEN & FIXES (verbindlich, überstimmt den Plan)

Autoritativ: Plan `.../scratchpad/p6_1.md`, Kritik `.../scratchpad/p6_2.md`.
Projekt: `c:/Users/User/Desktop/ja2_remasted`. Godot-Console-EXE: `.../Godot_v4.6.3-stable_win64_console.exe`.

## GRUND-ENTSCHEIDUNG (Kritik #4 — Stilkohärenz): STYLISIERT-LOWPOLY, kein PBR, kein Pflicht-Download
Die Figuren sind jetzt Quaternius-Lowpoly (SWAT/Miliz/Boss). Der GANZE Look folgt dem: flach-stylisiert, kräftige Farben, unshaded/simpel beleuchtet. **KEIN PolyHaven-Fotoscan-PBR-Boden. KEINE KayKit-Dungeon-Steinwände (falsches Thema: Dungeon auf Tropeninsel).**
- **Boden-Textur = die Kenney-PNGs, die SCHON im Repo liegen** (`assets/img/grass_1..4.png`, `dirt_1/2.png`, `rock_1..3.png`, `floor_wood_1..3.png`, `wall_brick.png`) → stylisiert, kohärent, **0 Download**. (Kritik #5: Fallback WIRKLICH auf diese PNGs verdrahten, nicht auf flache Farbe.)
- **Gebäude/Wände = stylisierte, skalen-normalisierte eigene Meshes** (Wandsegment als schmale Box mit Holz-/Putz-Material `wall_brick`/`floor_wood`, echte Höhe ~1,8 m) + **Dach-Prisma je Gebäude** (Connected-Component-Scan). KEIN KayKit-Dungeon.
- **Deko = OGA-CC0-Palme (curl) + einfache Lowpoly-Streuung**; KayKit-Kisten/Fässer (im Repo) für Deckung/Loot passen (stylisiert genug).
- Optional SPÄTER (Nutzer-Download, nicht jetzt): Quaternius Nature MegaKit / Medieval Village für mehr Vielfalt — als Enhancement notiert, nicht Pflicht.

## FROZEN FIXES (aus der Kritik)
**T1 (Bug):** In `build()` NICHT über `get_children()` iterieren und dabei `free()`. Nutze `for c in get_children().duplicate():` mit `c.queue_free()`.
**T2 (KRITISCH — Skalen-Normalisierung):** JEDES importierte Mesh (Palme, evtl. Gebäude-GLB) auf TILE_SIZE normalisieren: AABB per `get_aabb()`/Mesh-Bounds messen, Skalierungsfaktor berechnen (XZ-Footprint ≈ gewünschte Kachelanzahl, Höhe plausibel), dann `scale` setzen. Ohne das sind Modelle 3–4× zu groß. Gilt für Palme + alle Deko.
**T3 (WALL einmal zeichnen):** WALL wird NUR von Scenery3D als Wandsegment (echte Höhe) gezeichnet — NICHT zusätzlich als Boden-MM-Box. Die per-Kind-Boden-MM lässt WALL AUS.
**T5 (Offline-Fallback verdrahten):** `terrain_material(kind)` Fallback-Kette: (a) Kenney-Repo-PNG (`assets/img/grass_1.png` etc. je Kind) als PRIMÄR → (b) flache Farbe nur wenn PNG fehlt. So ist der Boden per Default texturiert, ohne Download. Behauptung „kein Download nötig" damit ehrlich erfüllt.
**T6 (Schatten):** Bestehende Beleuchtung NICHT auf Schatten umstellen (Acne-/Perf-Risiko auf 72×72/gl_compatibility). Schatten AUS lassen; Look kommt aus Textur + Deko + Wandhöhe. (Sonne/Ambient wie bisher, ggf. minimal wärmer.)
**T7 (assets3d.gd geteilt):** Terrain-Änderungen an `assets3d.gd` NUR ADDITIV (neue Konstanten/Funktionen anhängen), NICHTS Bestehendes (die Soldaten-CHARACTERS/WEAPONS/character/weapon/water_material) umschreiben. Erst NACH Abschluss des Soldaten-Strangs bauen.

## OPTIK JE KACHEL-KIND (nur Darstellung; Begehbarkeit/LOS/Kampf UNVERÄNDERT, Kritik #11 bestätigt)
- GROUND → Gras-Textur (Kenney-PNG), Süd-Band z≥64 = Sand + Palmen + einfacher Steg; Uferreihen = Sand/Schilf.
- FLOOR → Holzboden-Textur. BRIDGE → Holzplanken-Textur. RAMP → Erd-Textur.
- WALL → stylisiertes Wandsegment (Scenery3D, echte Höhe), Türlücke = FLOOR-Zelle.
- Dach je Gebäude (Prisma). Anwesen-Hügel (y 0→3-Lücke) → Fels-Mesa unter der Ebene-1-Fläche.
- WATER → Shader-Overlay UNVERÄNDERT.
- Deckung/Loot (`cover>0`) → KayKit-Kiste/Fass (auch im Kampf; Kritik #9: in der Demo Doppelung mit `tactical3d.gd::_setup_props` prüfen, eine Quelle deaktivieren).

## DATEI-OWNERSHIP
| Datei | Aktion |
|---|---|
| `scripts/tac3d/ground_view.gd` | umbauen: per-Kind-MultiMesh mit `terrain_material(kind)` (Kenney-PNG→Farbe-Fallback); erzeugt `Scenery3D`-Kind; T1/T3 beachten. Boden-Look identisch-oder-besser, Wasser-Overlay unverändert. |
| `scripts/tac3d/scenery3d.gd` | NEU (`class_name Scenery3D extends Node3D`): Wände (Höhe, T2/T3), Dächer, Fels-Mesa, Deko-Scatter (Palme, T2-normalisiert), Cover-Props, Steg. MultiMesh für Masse. Keine Collider (Picker=Plane, LOS=Grid). |
| `scripts/assets3d.gd` | ADDITIV (T7): `terrain_material(kind)`, `nature_mesh(id)` (Palme, T2), Env-Helfer. Bestehendes nicht anfassen. |
| Downloads: OGA-Palme (curl) → `assets/models/nature/palm.obj` + `palm_tex.png` | NEU (`https://opengameart.org/sites/default/files/palm_2.obj` + `palm_2_tex.png`, CC0) |
| Orchestratoren (`tactical3d.gd`, `tactical3d_combat.gd`) | NICHT anfassen (beide rufen `ground.build(grid)` → Optik propagiert automatisch). |

NIEMALS ändern: tactical.gd/mapgen/battle_unit/db/game/sfx/assets(2D)/ui_theme/combat_hud/cursor_view3d/juice3d/camera_rig/unit3d/tac3d_unit/tac3d_mapgen/tactical3d_combat.

## VERIFIKATION
`--smoke3d`/`--hud3d`/`--smoke`/`--tac3d` grün (Optik ist Darstellung + Fallback → Logik/Smoke unberührt); `--hud3d-shots` → PNGs zeigen texturierte Gras-/Sand-Insel mit Palmen, Wänden MIT Höhe (Gebäude lesbar), Props, Söldnern — kohärent stylisiert (kein PBR-Bruch, keine Dungeon-Steine). Mesh-Skalen plausibel (T2 — keine riesigen Palmen/Wände).

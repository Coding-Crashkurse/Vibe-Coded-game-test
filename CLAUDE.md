# BITTER HARVEST — Projekt-Kontext für Claude Code

Godot-4.6.3-JA-Klon, **reines 3D** (der 2D-Teil wurde entfernt).
Verbindliche Spezifikation: **`spec.md` (SPEC v5, Englisch)**. Detail-Bauverträge: **`docs/dev/*.md`**.

**Sprachregel (spec §0):** Das *Spiel* ist komplett **englisch** — UI-Strings, `Db`-Inhalte, Kommentare,
Debug-Ausgaben, Voicelines. Diese Datei und die Konversation bleiben deutsch.
Der Modus `--lang` erzwingt das automatisch (siehe Tests).

## Renderer (KRITISCH)
`project.godot` = **`gl_compatibility`**. → KEIN `Decal`, KEIN `GPUParticles3D` (nutze `CPUParticles3D`),
keine depth-/screen-basierten Shader. Materialien brauchen Licht ODER `SHADING_MODE_UNSHADED`
(sonst pechschwarz).

## Architektur (`scripts/`)
- **Autoloads:** `Db` (Spieldaten), `Assets` (2D), `Assets3D` (3D-Loader + Fallback), `Sfx`, `Game`
  (Laufzeitzustand **und** Save-System).
- `tac3d/` — 3D-Fundament: `tac3d_tile.gd`, `grid3d.gd` (`Vector3i→Tile` = Wahrheit),
  `pathfinder3d.gd` (AStar3D, flache Kostenmetrik y=0), `camera_rig.gd` (Ortho-Gimbal),
  `ground_view.gd`, `scenery3d.gd`, `unit3d.gd` (GLB + Waffe an Bone `Wrist.R` + Uniformfarbe),
  `picker3d.gd`.
- `tac3d/combat/` — `tactical3d_combat.gd` (Orchestrator, ~2800 Z.), `combat_hud.gd` (~1500 Z.),
  `tac3d_mapgen.gd` (Sektoren F4/F3), `tac3d_unit.gd`, `tac3d_vision.gd`, `tac3d_ai.gd`,
  `cursor_view3d.gd`, `juice3d.gd`.
- `screens/` — Titel (gemaltes Menü), Schwierigkeit, Anheuern (+Dossier-Overlay), Insel, Laden,
  Endtafel, Söldner-Galerie.
- `ui/save_panel.gd` — wiederverwendbares, zentriertes Slot-Overlay (Speichern **und** Laden).
- `menu/hideout.gd` — begehbarer 3D-Raum, **inaktiv** hinter `Game.USE_HIDEOUT_MENU = false`.
  Aktives Hauptmenü ist das gemalte `main_menu.png` in `title.gd`.

## Kern-Muster (unbedingt beibehalten)
- **Fallback überall:** fehlt ein GLB/Textur/Audio → Kapsel/Box/Stille. Headless-Tests laufen ohne Assets.
- **`fast`-Modus:** im Bot/Headless werden HUD/Cursor/Juice NICHT gebaut → Kampf-Formeln unberührt.
- **Interne Dictionary-Schlüssel bleiben deutsch** und dürfen NIE umbenannt werden:
  `leicht/normal/schwer`, `kopf/beine/torso`, `flinte/granate/drachenmaul`, Söldner-IDs (`otto`,
  `walross`, …), Clip-Namen (`CharacterArmature|Idle`), Bone `Wrist.R`, Gruppe `tac3d_units`.
  Das Sprach-Gate kennt diese Ausnahmen; Umbenennen bricht Spiel *und* Harness.

## Tests (Godot-Console-EXE)
```
<godot_console.exe> --headless --path . --import      # Asset-Import-Cache bauen
<godot_console.exe> --headless --path . -- --smoke    # §8.9 Gesamt-Abnahme → SMOKE OK
<godot_console.exe> --headless --path . -- --loop     # F4→F3→Rettung→Basis→Endtafel
<godot_console.exe> --headless --path . -- --lang     # Sprach-Gate (keine deutschen UI-Strings)
<godot_console.exe> --headless --path . -- --tac3d    # 3D-Fundament
<godot_console.exe> --headless --path . -- --smoke3d  # Kampf-Bot bis Sieg
<godot_console.exe> --headless --path . -- --hud3d    # HUD-Interaktion
<godot_console.exe> --headless --path . -- --demo3d   # Demo-Inhalt
<godot_console.exe> --headless --path . -- --menu     # Menü + Save/Load + kaputte Saves
<godot_console.exe> --headless --path . -- --map      # Sektorkarte
<godot_console.exe> --headless --path . -- --sector3d # Zwei-Sektoren-Daten
```
**Unbekannte `--`-Modi brechen jetzt sauber mit Exit 1 ab** (früher: Endlos-Hänger).

Fenster-Screenshot-Modi (BRAUCHEN Display, NICHT headless):
`--menu-shots=` · `--map-shots=` · `--hire-shots=` · `--gallery-shots=` · `--hud3d-shots=` ·
`--tac3d-shots=` · `--juice-shots=` · `--demo3d-shots=` · `--estate-shots=` · `--hideout-shots=`
(jeweils `=<absoluter Ordner>`)

**⚠️ CLOUD-HINWEIS:** In der Cloud gibt es nur **headless**. Rein visuelle Bugs (schwarze Materialien,
falsche Modell-Skalen, T-Pose) sind headless **NICHT** sichtbar. **Nach Cloud-Änderungen lokal per
Screenshot-Modus gegenprüfen.**

## Audio — kein API-Key zur Laufzeit nötig
Alle Stimmen/SFX/Musik sind als **Dateien** gebacken. `assets/audio/voice_manifest.json` ist die
Wahrheit (90 Zeilen, 49 vorhanden / 41 `pending`). `sfx.gd` spielt Dateien ab (Synth-Fallback) und ruft
**nie** die ElevenLabs-API zur Laufzeit. Der Key (`.env`, **gitignored**) dient nur zum **Generieren**
— das **lokal** machen. Deutsche Alt-Clips liegen in `assets/sfx/voice/_archive/de/`.

## Stand
**Spec v5 umgesetzt**, alle 10 Headless-Modi grün, visuell gegengeprüft.
- **Stimmen komplett:** Manifest 90/90 `present` (95 Clips). Narrator nutzt die ElevenLabs-**Premade-Stimme
  „Daniel"** (`onwK4e9ZLuTAKqWW03F9`) — Vargos Custom-Stimme wurde im Konto gelöscht und der Boss ist
  ohnehin aus der Demo gestrichen, so bleibt das 10/10-Slot-Limit unangetastet.
- **Fog of War** (`scripts/tac3d/fog_view3d.gd`) läuft: MultiMesh-Quad-Layer, HIDDEN/EXPLORED/VISIBLE,
  im Orchestrator an 4 Stellen verdrahtet (Member · Aufbau in `_ready` **und** `_rebuild_interactive` ·
  `refresh` am Ende von `compute_vision` · Teardown). In `fast`/Headless immer `null` — Bot zahlt nichts.
  **`COL_HIDDEN`/`COL_EXPLORED` sind gegen einen Screenshot getunt** (halbtransparent, nicht deckend):
  der Trupp sieht ~320 von 5184 Zellen, deckend erschlug das die ganze Bodentextur. Nicht „aufräumen".
- **Der 3D-Raum ist Hauptmenü UND Heimatbasis** (`USE_HIDEOUT_MENU = true`, Entscheidung des Projekt-
  eigners am 2026-07-20 — „das neue Modell ist cooler"). Das ist §4.3s ursprüngliches „build once,
  use twice": derselbe Raum, per `mode` einmal als Menü und einmal als Basis.
  Das gemalte `main_menu.png` + `title.gd` bleiben **vollständig funktionsfähig als Fallback** —
  Flag auf `false` und es ist wieder der Startbildschirm, ohne weitere Änderung. `--menu` deckt das ab.
  Continue/Load springen per `Hideout.enter_base(router)` in die Basis, sobald `base_unlocked` —
  dieser Weg hing nie am Flag.

- **Je Waffe ein eigenes Mesh und ein eigener Schuss-Sound** (P9/K45/Huntsman/Dragonmaw/SVD).
  `Db.WEAPONS[<id>]` trägt `"mesh"` (→ `Assets3D.WEAPONS`) + `"attach_offset"` + `"snd"`.
  Fehlt ein Mesh, greift der generische Pistolen-/Gewehr-Pfad (empirisch mit entfernten .obj geprüft).
  **Schusslautstärke hängt an Waffen-EIGENSCHAFTEN, nicht am Soundkey-Namen** — der alte Vergleich
  `snd == "shot_r"` ließ den SVD still auf +1,0 dB fallen, sobald er einen eigenen Key bekam.

Bewusst offen:
- `crouch_idle`/echtes `reload` fehlen im Rig. **Retargeting wurde ernsthaft versucht und ist gescheitert**
  (2026-07-20, Screenshot-belegt, sauber zurückgerollt): Namen lassen sich zwar 51/51 auf
  SkeletonProfileHumanoid abbilden, aber die RUHE-POSEN sind unterschiedliche Posen-*Formen*
  (Rig hängende Arme vs. Bibliothek T-Pose, 95–125° durch die Armkette, links≠rechts).
  `fix_silhouette` überbrückt das NICHT. Ohne gemeinsame Referenzpose lässt sich Achsenkonvention nicht
  von Posendifferenz trennen, und Ausrichtung über kürzeste Drehung verwirft den Bone-Roll → verdrehte
  Unterarme, zerrissene Haut. Nächster Schritt wäre Backen in Blender, nicht Skripten.
  Nebenbefund: Retargeting benennt `Wrist.R` → `RightHand` um, d. h. alle Waffen wären weg.
- Stash bewegt nur Item-Ids (kein Ausrüsten/Nachladen aus der Basis heraus).
- Laptop im Hideout führt zum Anheuern-Screen, aber der Rückweg in die Basis fehlt.

## Arbeitsweise
Design → adversariale Kritik → Bau → **mit echtem Godot verifizieren** (alle Modi grün).
Nichts committen/pushen, was nicht verifiziert ist.
**GDScript-Fallen:** fehlendes `await` = Parse-Fehler = Endlos-Hänger im Headless-Bot (schlimmster Fall);
`class_name` nicht mit Engine-Klassen kollidieren (`Tac3D`-Präfix); typisierte Variant-Iteration
(`var c: Vector3i = k`); `floori` statt `int`; `signal.emit.call_deferred()` bei Signalen in `_ready`
nach `add_child`; Integer-Division bewahren (Balance); `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`
bei Code-UIs; `Button.flat = true` unterdrückt ALLE StyleBoxes (für unsichtbare Klickflächen
`StyleBoxEmpty` auf `normal/focus/disabled`); `JSON.parse_string` liefert Zahlen als float;
`Color`/`Dictionary`-of-`Color` überleben JSON NICHT.

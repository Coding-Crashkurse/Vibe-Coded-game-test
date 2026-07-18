# PHASE 5 (SÖLDNER-MODELLE) — ENTSCHEIDUNGEN & FIXES (verbindlich)

Autoritativ: Plan `.../scratchpad/p5_1.md`, Kritik `.../scratchpad/p5_2.md`.
Projekt: `c:/Users/User/Desktop/ja2_remasted`. Godot-Console-EXE: `C:/Users/User/Downloads/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe`.

## WAS: Barbar → moderne Söldner (Quaternius Ultimate Animated Character Pack, CC0, verifiziert)
Ein Skelett `CharacterArmature`, 24 eingebackene Anims (inkl. `Gun_Shoot`, `Idle_Gun`, `Idle_Gun_Pointing`, `HitRecieve`, `Death`, `Walk`, `Run`), self-contained GLB (0 externe Texturen), **kein Retargeting**, Waffen-Bone `Wrist.R`, kein eingebauter Waffen-Mesh.
Rollen: **merc = SWAT**, **enemy = Casual Character** (Miliz-Look), **boss = Business Man** (Anzug).

## DOWNLOADS (curl, verifizierte static.poly.pizza-UUIDs) → assets/models/characters/
```
Swat.glb        https://static.poly.pizza/713f6535-f4f3-4367-a4c6-ced126ae0936.glb   (Seite /m/Btfn3G5Xv4)
Casual.glb      https://static.poly.pizza/90a9e2d4-053f-42f1-99a2-8f5e1180ea7f.glb   (Seite /m/kZ3DmIoGip)
BusinessMan.glb https://static.poly.pizza/e599abbe-7d73-488c-9d7e-3ead281e705c.glb   (Seite /m/JFrLIKqvCH)
rifle.glb (opt) https://static.poly.pizza/a9b24fa0-ebec-4656-ada6-dc324bae779d.glb   (Seite /m/46615JyFm7) → assets/models/weapons/
```
Falls eine static-URL 404t: UUID neu ziehen mit `curl -sL https://poly.pizza/m/<ID> | grep -oiE 'static\.poly\.pizza/[a-f0-9-]+\.glb' | head -1`. Nach Download: EINMAL `<console.exe> --headless --path . --import`.

## FROZEN FIXES

**S1 (KRITISCH — stiller Fehlschlag):** Die Anim-Namen enthalten `|` (z.B. `CharacterArmature|Idle`). Godot kann sie beim glTF-Import umschreiben/unter eine Library legen. Nach `--import` MUSS der Verify-Schritt die TATSÄCHLICHEN Namen ausgeben (`print(anim.get_animation_list())` an einem instanzierten Modell) und `_CLIPS` in unit3d.gd exakt darauf setzen. Sonst spielt play_anim NICHTS → Modell steht in Bind-/T-Pose (kein Crash, kein roter Test → nur im Screenshot sichtbar). **Vor „fertig" verifizieren: das Modell steht im Idle, NICHT in T-Pose.**

**S2:** `skel.find_bone("Wrist.R")` per assert/print absichern (der Ist-Code nutzt schon `handslot.r` mit Punkt erfolgreich → Punkt überlebt wahrscheinlich; falls doch `Wrist_R`, nachziehen).

**S3 (Waffe):** Primär `rifle.glb` an `Wrist.R` hängen (Söldner-Look!) — ABER die Rifle-GLB hat eigene 100×-Node-Skala + 2 Meshes → eigenen `WEAPON_SCALE`/Offset im Screenshot tunen. Wenn die Rifle zickt: Fallback auf das bestehende `pistol.obj`. In assets3d.gd WEAPONS entsprechend ergänzen, sonst ist die rifle tote Fracht.

**S4 (Orchestrator — ERST NACH JUICE):** Die Kritik las einen MID-BUILD-Stand; NICHT auf ihre Zeilennummern verlassen. Nach Juice-Abschluss die FINALE `tactical3d_combat.gd` lesen. `def.play_anim("hit")` (Schadensnehmer) und `dead.play_anim("death")` sind laut Kritik evtl. schon da — falls ja, NICHT doppeln. Ergänzen: den SCHÜTZEN `att.play_anim("shoot")` in `shoot()` als EIGENEN `if not fast:`-Block (getrennt vom juice-Block); `do_grenade` throw→ in den vorhandenen `if not fast: Sfx.play("throw")`-Block. ALLE play_anim `if not fast`-gegated. Kampf-Formeln unberührt.

## ROLLEN-ZUORDNUNG (Modell je Einheit)
`unit3d.gd::setup()` bekommt optionalen `char_id`-Parameter (Default so, dass Smoke/Fallback grün bleibt). `Tac3DUnit.setup_combat()` wählt: boss→"boss", elif is_merc→"merc", else→"enemy" und reicht ihn an `super.setup(g, start, char_id)`. `_CLIPS` gilt für alle (gleiches Rig).

## DATEI-OWNERSHIP
| Datei | Aktion |
|---|---|
| Downloads assets/models/characters/*.glb (+ opt weapons/rifle.glb) | NEU (curl) |
| `scripts/assets3d.gd` | EDIT — CHARACTERS { merc/enemy/boss }, WEAPONS { rifle } |
| `scripts/tac3d/unit3d.gd` | EDIT — char_id-Param, Assets3D.character(char_id), _CLIPS auf ECHTE Namen (S1), Waffe rifle+Wrist.R (S2/S3), Kopf-Doc aktualisieren (KayKit→Quaternius) |
| `scripts/tac3d/combat/tac3d_unit.gd` | EDIT — Rolle→char_id an super.setup |
| `scripts/tac3d/combat/tactical3d_combat.gd` | EDIT (NACH JUICE) — nur `att.play_anim("shoot")` + ggf. throw; Formeln unberührt |

Fallback bleibt überall: fehlt eine GLB → Kapsel, play_anim = No-Op → `--smoke3d`/`--smoke`/`--tac3d` grün. NIEMALS ändern: tactical.gd/mapgen/battle_unit/db/game/sfx/assets/ui_theme/combat_hud/cursor_view3d/juice3d/camera_rig.

## VERIFIKATION
`--smoke3d`=SMOKE3D OK (identische Rundenzahl), `--hud3d`=HUD3D OK, `--smoke`/`--tac3d` grün; `--hud3d-shots` → PNGs zeigen SWAT-Söldner (links Portraits weiter ok) + Gegner Casual + Boss BusinessMan, **im Idle/Anim, NICHT in T-Pose**, mit Gewehr. S1-Anim-Liste im Log geprüft.

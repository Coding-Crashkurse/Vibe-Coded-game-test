# SPEC v3 — „Söldnerkommando"
### Ein Jagged-Alliance-Nachbau in **echtem 3D** (Godot 4.6) — große Neuausrichtung

> **Status:** Verbindliche Spezifikation **v3**. Ersetzt v2 vollständig.
> **Kernentscheidung:** Umzug von 2D-Draufsicht (Kenney Top-down) auf **echtes 3D mit orthografischer Kamera** (JA3-/XCOM-Prinzip: 3D-Welt, isometrischer Look). Grund: nur so tragen die neuen Ziele — **größere Sektoren, Gehen, Schwimmen, Brücken, Höhenebenen, mehrstöckige Häuser, mehrere Städte**.
> **Look:** stilisiert-lowpoly, **kohärent aus CC0-Quellen** (Quaternius als Rückgrat, Kenney für Tropen). Kein Kauf-Asset, kein Zombie-/Stadt-Setting — es bleibt die **tropische Söldner-Insel** im Geist von JA1/JA2.
> **Recherche-Basis:** Wikipedia & Fandom (JA1 *Metavira*, JA2 *Arulco/Omerta*), StrategyWiki, Bear's Pit/Arulco-Cartography (Sektorgröße 160×160), offizielle Godot-4.6-Doku (Camera3D, AStar3D, NavigationServer3D, NavigationMesh, Retargeting, MultiMesh), Asset-Seiten quaternius.com / kaylousberg.itch.io / kenney.nl (alle CC0 verifiziert). Quellen am Ende.

---

## 0. Was aus v2 erhalten bleibt (nicht wegwerfen!)

Der 3D-Umzug betrifft **Darstellung + Weltgröße + neue Mechaniken** — die inhaltliche Substanz bleibt:

- **Die 9 A.I.M.-Söldner inkl. „Ivan"** mit Attributen, Startausrüstung und **allen ElevenLabs-Stimmen** (Auswahl/Zitat/Dialog/Schmerzlaute). Das Voice-Design ist fertig (10/10) und wird 1:1 weiterbenutzt.
- **„General Vargo"** als Endgegner mit eigenem Dialog und Stimme.
- **JA1-Tempo** (Spieler-Feedback, bindend): neutraler Spawn, **Kampf erst bei Sichtkontakt**, 2–3 Schüsse/Runde, Zielen-Stufen, Boss stationär.
- **Audio-System** (`sfx.gd`): Datei-bevorzugt mit prozeduralem Synthese-Fallback, untergrundabhängige Schritte, Musik-Zustände (Titel/Erkundung/Kampf/Sieg/Niederlage).
- **Slot-Inventar, Magazin-Munition, Kisten-/Leichen-Loot, Unterbrechungen, Deckung, Lärm-Alarm, XP/Erfahrung, 3 Schwierigkeitsgrade.**
- **Datenbank/Autoloads** (`Db`, `Assets`, `Sfx`, `Game`) — bleiben als Struktur; `Assets` wird auf 3D-Ressourcen umgestellt.

Neu gebaut wird: der **Taktik-Layer als `Node3D`** (bisher `Node2D`), das **Kachel-/Höhen-/Pfad-System in 3D**, die **Kamera**, die **3D-Modelle & Animationen** und die **Juice-Schicht**.

---

## 1. Vision (das ganze Spiel) vs. Demo (die vertikale Scheibe)

**Das ganze Spiel** soll ein echtes JA werden: eine **Insel aus vielen Sektoren**, **mehrere Städte** mit **Loyalität**, **Milizen**, **Einkommensquellen (Minen)**, laufende **Söldner-Verträge** und ein Feldzug Sektor für Sektor bis zum Diktator.

**Die Demo** liefert eine **vollständige, runde vertikale Scheibe** dieses Spiels: **3 große, zusammenhängende Sektoren**, in denen du einen gefangenen Verbündeten **befreist**, dessen **Keller zur Heimatbasis** wird — und von dort den lokalen Machthaber stellst. Alle Kernsysteme (3D-Taktik mit Höhe/Wasser/Brücken, Anheuern, Inventar/Loot, Basis, Juice) sind **live und erweiterbar**; die restliche Inselkarte ist sichtbar, aber gesperrt.

| System | Volle Vision | In der Demo |
|---|---|---|
| Weltkarte | ganze Insel, viele Sektoren, Ober- **und Unterebene** | Insel sichtbar, **3 Sektoren spielbar** (+ 1 Keller-Ebene) |
| Städte & Loyalität | mehrere Städte, Loyalität 0–100 %, Quests | **1 Dorf** (Silberquell) mit einfacher Loyalitäts-Anzeige |
| Milizen | ausbilden/bewaffnen, 3 Stufen, halten Sektoren | **erste Villager-Miliz** nach der Befreiung (Deko-Verteidiger) |
| Einkommen | Minen, Tagesgehälter, Budgetdruck | **fixes Startbudget**, Gehälter nur angedeutet |
| Heimatbasis | mehrere Stützpunkte, Nachschub, Reparatur | **1 Keller-Unterschlupf** (Nachschub/Heilen/Anheuern/Speichern) |
| Rekruten via NPC | mehrere befreibare Charaktere | **Otto „Bär" Brandt** wird befreit → Basis + Gratis-Rekrut |

---

## 2. Setting & Story der Demo

**Insel Isla Corvo**, ein vergessenes Tropen-Atoll. Der selbsternannte **„General Vargo"** hat sich das Dorf **Silberquell** unter den Nagel gerissen, presst die Bewohner aus und residiert im alten **Anwesen auf dem Hügel**. Ein gestrandeter A.I.M.-Veteran, **Otto „Bär" Brandt**, hat aus einem versteckten **Keller** unter dem Dorf einen Widerstand aufgebaut — bis Vargos Elite ihn in die Enge trieb.

**Dein Auftrag (Demo):**
1. **Anlanden** an der Südküste (neutraler Strand, Boot/Steg — Kenney Pirate Kit).
2. Durch **Sumpf und Fluss** (Schwimmen **oder** Brücke) ins **Dorf Silberquell** vorstoßen.
3. Im Dorf den **Kellereingang** finden, dich hinunterkämpfen und **Otto befreien**.
   → Der Keller wird deine **Heimatbasis** („Der Unterschlupf"): Otto schließt sich **gratis** an, die Dorfbewohner formieren erste **Miliz**, du kannst dich hier **neu ausrüsten, heilen, anheuern, speichern**.
4. Mit Basis im Rücken das **Anwesen auf dem Hügel** stürmen (Höhenebene, Innenräume, Dach) und **Vargo** stellen (stationär, Dialog, Boss). Vargo fällt → Silberquell ist frei → **Demo-Sieg**.

Der Bogen ist bewusst der JA2-Omerta-Bogen, auf die Insel übersetzt: **Kontakt → Keller-Versteck → befreiter Verbündeter → erste Basis → weiterziehen zum Machtzentrum.**

---

## 3. Der große Wechsel: 2D → echtes 3D

**Warum:** Brücken (unter denen man **durch**läuft und **über** die man geht), Schwimmen, Höhenunterschiede und mehrstöckige Gebäude sind in 2D-Iso Fake und Sortier-Hölle. In 3D mit Ortho-Kamera sind sie **nativ**. Es ist exakt der Weg von Jagged Alliance 3.

**Look-Prinzip:** `Camera3D` im **orthografischen** Modus → isometrische Anmutung ohne Fluchtpunkt, aber echte 3D-Geometrie darunter. Stilisiert-lowpoly, damit CC0-Assets kohärent wirken und die Performance auf großen Karten stimmt.

**Migrationsschnitt:** `scripts/screens/tactical.gd` wird von `Node2D` auf `Node3D` portiert. Die **Spiel-Logik** (AP, Sicht, Deckung, KI, Loot, Boss-Dialog) bleibt weitgehend, weil sie auf **Zell-Koordinaten** rechnet — nur werden aus `Vector2i`-Zellen **`Vector3i`-Zellen (x, Ebene, z)** und aus 2D-Sprites 3D-Instanzen.

---

## 4. Weltstruktur & Sektorgröße

**Recherche-Anker:** JA2-Sektoren sind **160×160 Kacheln** (≈120×120 begehbar) — bewusst **viel größer als der Bildschirm**, man scrollt. JA2-Welt = **16×16-Raster (A1–P16) = 256 Oberflächensektoren** plus **Unterebene** (Keller/Minen). JA1 = Insel *Metavira*, **60 Sektoren**, Heimatbasis Sektor #60.

**Für uns (Kompromiss aus JA-Gefühl und Hobby-Machbarkeit):**
- **Sektor-Taktikkarte: ~72×72 begehbare Kacheln** (Demo-Ziel; tunebar 64–96). Das ist **~4–6× v2** (v2: 40×28) und fühlt sich nach „großem Schlachtfeld" an: Anmarsch über mehrere Runden, Flanken, Scharfschützen-Positionen, Hinterhalte.
- **Kachelgröße:** 1 Kachel = 1 Welt-Einheit (`tile_size = 1.0 m`). Zelle ↔ Welt über eigene Umrechnung (siehe §7).
- **Höhenebenen:** `y` in `Vector3i` = Ebene. Demo nutzt: **Ebene 0 = Boden**, **Ebene 1 = Dächer/Hügel-Oberkante**, **Ebene −1 = Keller/Unterschlupf**. Beliebig erweiterbar.
- **Weltkarte (Hub):** die Insel als Sektorraster wie in v2, Zielsektoren markiert; in der Demo sind **3 Sektoren + 1 Keller** frei, der Rest „In der Demo nicht verfügbar". Panel im JA-Stil (TEAM/GELD/TAG/SEKTOR/LOYALITÄT/EINSATZ).

**Die 3 Demo-Sektoren:**
| Sektor | Inhalt | Neue Mechanik im Fokus |
|---|---|---|
| **Küste (Süd)** | Strand, Steg, Boot, Palmenriegel, neutrale Landezone | **Anmarsch, Gehen**, erster Kontakt |
| **Fluss & Dorf (Mitte)** | Sumpf, **Fluss mit Brücke**, Dorf Silberquell (mehrere Gebäude, Plaza, Brunnen), **Kellereingang** | **Schwimmen vs. Brücke**, Innenräume, **Keller-Ebene (−1)** |
| **Hügel & Anwesen (Nord)** | ansteigendes Gelände, Mauerring, Hof, **mehrstöckiges Haupthaus + Dach**, Thronsaal | **Höhe/Ebene 1, Dach-Sniper**, Boss |

---

## 5. Strategie-Layer

**Recherche-Anker:** A.I.M. (teure Profis) vs. M.E.R.C. (billig); Verträge **1/7/14 Tage** (länger = günstigerer Tagessatz); **Loyalität 0–100 %**, ≥20 % nötig für Miliz-Ausbildung, steuert Minen-Einkommen; **Miliz max. 20/Sektor** in 3 Stufen (Rookie→Regular→Veteran); Minen als Haupteinkommen.

**Demo-Umfang (schlank, aber echt angedockt):**
- **Anheuern:** A.I.M.-Screen wie v2 (9 Kandidaten inkl. Ivan, Budget, max. 4 zu Beginn). Vertragslogik als **Datenfeld vorbereitet**, aber in der Demo ohne Tagesabrechnung.
- **Heimatbasis „Der Unterschlupf"** (nach Befreiung): Menüpunkte **Neu ausrüsten** (Zugriff auf Basis-Lager), **Heilen** (über Zeit/Kosten), **Anheuern/Nachrücken** (weitere A.I.M.-Söldner ins Feld holen), **Speichern**. Das ist die Demo-Version des JA2-Rebellenkellers.
- **Loyalität Silberquell:** ein sichtbarer Balken 0–100 %. Steigt durch **Befreiung** und **keine Zivilisten töten**; fällt bei Zivilistentod. In der Demo v. a. Flavor + Freischalt-Bedingung für die Villager-Miliz.
- **Villager-Miliz:** nach der Befreiung erscheinen 3–5 bewaffnete Dorfbewohner, die den Dorfkern „halten" (einfache Wächter-KI). Andockpunkt für das volle Miliz-System.

**Volle Vision (dokumentiert, nicht in Demo):** mehrere Städte mit eigener Loyalität, Minen-Einkommen mit Tagesabrechnung, Vorarbeiter-Kontakt, Miliz ausbilden/bewaffnen/hochstufen, Söldner-Moral & Beziehungen, Vertragsverlängerung.

---

## 6. Taktik-Layer

### 6.1 Bewährtes aus v2 (bleibt)
- **Anmarschphase:** neutraler Start außer Sichtweite, freie Bewegung, Gegner passiv; **Rundenkampf erst bei Sichtkontakt** oder eigenem Schuss. Nach **2 Runden ohne Kontakt** zurück in die Erkundung (Musikwechsel).
- **AP:** 20 + BEW/5. **Schuss 12–15 AP → 2–3/Runde.** **Zielen Z** in Stufen 0–3 (+3 AP, +7 % je Stufe).
- **Unterbrechungen** (symmetrisch): 15 % + 7 %×Erfahrungsstufe + BEW/6.
- **Sicht & Deckung:** Sichtweite Söldner 13 / Gegner 12 / Boss 14; Deckung −25 % (Kisten/Sandsäcke/Möbel), Fenster −10 %. **Lärm** alarmiert Hörweite 9, Gegner untersuchen die Quelle.
- **Inventar** (Hand + 8 Slots, Taste **I**), **Magazin-Munition** (Nachladen verbraucht Magazin), **Loot** (Kisten & Gefallene, 6 AP), **Erfahrung** (ERF 1–6).
- **Granate** (Wurf, Radius, Friendly Fire), **Medikit** (heilt), **Waffenwechsel**.

### 6.2 NEU durch 3D — Bewegungsarten & Gelände
- **Gehen/Rennen** (Standard) über begehbare Bodenkacheln.
- **Schwimmen:** Wasserkacheln sind **nicht gesperrt, sondern eigener Bewegungstyp** mit **höheren AP-Kosten** und Regeln: langsamer, **kann nicht schießen/zielen während im tiefen Wasser** (nur waten in flachem), Ausrüstung/Sicht eingeschränkt. Nicht-schwimmfähige/überladene Einheiten meiden Tiefwasser (KI) — Andockpunkt für Ausdauer/Ertrinken der vollen Vision.
- **Brücken:** die Brücke ist **Ebene 1** über dem Fluss (Ebene 0). Man kann **oben drüber** gehen **und unten durch**-schwimmen/waten — technisch zwei getrennte Zellen an gleicher X/Z (siehe §7.3). Das ist der eigentliche Grund für den 3D-Umzug.
- **Höhe/Ebenen:** Hügel und **Dächer** sind eigene Kacheln auf Ebene 1. **Höhe gibt Sicht- und Trefferbonus** (Dach-Sniper sehen weiter, +Treffer nach unten). Treppen/Leitern/Rampen verbinden die Ebenen.
- **Keller (Ebene −1):** eigener Raum unter dem Dorf; betreten über Kellertreppe. Der **Unterschlupf** liegt hier.
- **Zerstörbarkeit (leicht, Andockpunkt):** Türen öffnen/aufbrechen; einzelne Wände/Fässer als sprengbar markierbar. Volle Ballistik-Zerstörung = spätere Ausbaustufe.

### 6.3 Haltungen (neu, JA-typisch — Ausbaustufe innerhalb der Demo)
**Stehen / Hocken / Liegen** beeinflussen Treffer, Sichtbarkeit und Trefferfläche. Mindestens **Hocken** (bessere Genauigkeit, kleineres Ziel, in Deckung) soll rein; Liegen optional.

### 6.4 Gegner & Boss (wie v2, in 3D)
- **Milizionäre** (Pistole/Flinte, patrouillieren, jagen Lärm).
- **Elitewachen** (Panzerung) am Anwesen, an ihren Posten gebunden; auf LEICHT durch Miliz ersetzt.
- **General Vargo** im Thronsaal des Haupthauses: hohe HP, Panzerung, **Dialog beim ersten Sichtkontakt**, **stationär (Leine)**. Tod → Rest ergibt sich → Sieg.

---

## 7. 3D-Engine-Spezifikation (das technische Herz)

> Alle genannten Klassen/Methoden sind **echte Godot-4.6-APIs** (gegen die offizielle Doku verifiziert).

### 7.1 Kamera — orthografischer Iso-Look
- `Camera3D` mit `projection = Camera3D.PROJECTION_ORTHOGONAL`. **`size` = Zoom** (Meter-Durchmesser des Sichtfelds).
- **Gimbal-Rig:** Pivot-`Node3D` (Yaw, **Y = 45°**) → Tilt-`Node3D` (Pitch, **X ≈ −30°**, klassisch bis −35,26°) → `Camera3D`.
- **Rotation in 45°-Schritten** um den Pivot (per `Tween` weich), **Zoom** über `cam.size` (geklammert). **Kamera hart aufs Spielfeld begrenzt** (wie v2: nie aus der Karte scrollen/zoomen).
- `far` großzügig (z. B. 200), sonst Ortho-Schatten-Artefakte.

### 7.2 Gitter — eigene Datenschicht als Wahrheit
- **`Dictionary` `Vector3i → TileData`** ist die **Spiel-Wahrheit** (Typ, Ebene, Begehbarkeit, Bewegungstyp, Deckung, Sicht-Blocker, Flags). Godot-`GridMap`/`MultiMesh` sind **nur Darstellung**.
- Umrechnung: `cell = Vector3i(floor(x/tile), ebene, floor(z/tile))`, Zellmitte zurück per eigener Funktion. (GridMap-Alternative: `local_to_map()`/`map_to_local()`.)

### 7.3 Wegfindung — **AStar3D** (löst Brücken elegant)
- **`AStar3D`** ist die offizielle Empfehlung für **zellbasiertes** Gameplay mit diskreten Positionen (nicht Navmesh).
- **Jede Zelle = eigener Punkt** mit eigener ID (`add_point(id, Vector3)`), **Kanten nur zwischen real verbundenen Zellen** (`connect_points`).
- **Brücken/Überlappung:** „auf der Brücke" (Ebene 1) und „unter der Brücke" (Ebene 0) sind **zwei verschiedene Punkte an gleicher X/Z** — sauber getrennt verbunden. Kein Navmesh-Trick nötig.
- **Kosten:** `set_point_weight_scale(id, w)` — Wasser teurer, Straße billiger. **Sperren:** `set_point_disabled(id, true)` (Einheit steht drauf / Tür zu).
- Pfad: `get_id_path()` / `get_point_path()`. AP-Kosten = Summe der Kantengewichte entlang des Pfades.
- *(Für spätere freie Bewegung stünde `NavigationServer3D` + `NavigationRegion3D` + `NavigationLink3D` bereit; für rundenbasiert bleibt AStar3D die richtige Wahl.)*

### 7.4 Wasser & Schwimmen
- Tile-Flags `enum TileKind { GROUND, WATER_SHALLOW, WATER_DEEP, ... }`, Unit-Flag „kann schwimmen".
- AStar3D-Gewicht für Wasser hoch (`set_point_weight_scale`); Tiefwasser für Nicht-Schwimmer per `set_point_disabled`.
- **`Area3D`** über den Wasserzellen → `body_entered` schaltet die Einheit auf „schwimmt" (Animation, Regeln, AP).
- **Optik:** CC0-**Stylized Water Shader** (godotshaders.com, Godot 4: Wellen/Foam/Tiefenfarbe) als `ShaderMaterial` auf die Wasser-Ebene.

### 7.5 Maus → Kachel-Picking
- Kamerastrahl: `camera.project_ray_origin(mpos)` / `project_ray_normal(mpos)`.
- **Variante A (Collider):** `get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to))` gegen Terrain-Layer → `hit.position` → Zelle. Trifft Höhen/Brücken automatisch.
- **Variante B (Ebene):** `Plane(Vector3.UP, level_y).intersects_ray(from, dir)` je aktiver Höhenebene (billig, exakt).

### 7.6 Fog of War / Sichtlinien
- Pro Kachel **3 Zustände:** `HIDDEN` (schwarz) / `EXPLORED` (gedimmt) / `VISIBLE`. **Neuberechnung nur bei Zug/Bewegung**, nicht pro Frame.
- **LOS:** `intersect_ray(auge, ziel)` nur gegen **Wand/Blocker-Layer** → leer = freie Sicht. Höhen-/Reichweiten-/Winkel-Check vorschalten (spart Raycasts).
- **Darstellung:** `MultiMeshInstance3D` aus flachen Quads über den Kacheln, `use_colors = true`, `set_instance_color(i, …)` pro Zustand → ein Draw-Call.

### 7.7 Einheiten & Animation (Mixamo-/Quaternius-Workflow)
- Charakter-glTF importieren; am `Skeleton3D` **`BoneMap` + `SkeletonProfileHumanoid`** → **Retargeting** (Mixamo-Bones `mixamorig:*` werden auto-gemappt).
- **Animationsbibliothek** (Quaternius *Universal Animation Library* / KayKit *Character Animations* / Mixamo) per **AnimationLibrary** + gleichem BoneMap übertragen.
- **`AnimationTree`** mit `AnimationNodeStateMachine`: **Idle / Gehen / Rennen / Schwimmen / Zielen / Schießen / Nachladen / Treffer / Sterben**; Bewegung entlang des AStar-Pfades per Skript, passende Anim dazu.
- **Waffe** als eigenes Mesh via **`BoneAttachment3D`** an den Hand-Bone.

### 7.8 Performance (große Karten)
- **`MultiMeshInstance3D`** für Boden, Gras, gleiche Props, Fog-Overlay (tausende Meshes, ein Draw-Call).
- **Occlusion Culling** (`OccluderInstance3D`, backen) für Hügel/Mauern — *Achtung: MultiMesh wird nicht auto-occludet, Occluder ggf. manuell setzen.*
- **`VisibleOnScreenEnabler3D`** pausiert Off-Screen-Logik; **Mesh-LOD** + `visibility_range_*` für ferne Props; große Karte in **Chunks**.

---

## 8. Assets — der kohärente CC0-Stack

**Lizenz:** Alle drei Quellen sind **CC0 1.0** (kommerziell frei, keine Attribution nötig — Nennung „3D-Assets: Quaternius / Kay Lousberg / Kenney" trotzdem freiwillig im Abspann). Verifiziert auf den Pack-Seiten.

**Kohärenz-Strategie:** **Quaternius bildet das Rückgrat** (ein Künstler → einheitlicher Stil für Held-Elemente: Charaktere, Animationen, Waffen, Gebäude, Props). **Kenney** füllt gezielt die **Tropen-Lücke** (Palmen, Insel, Steg/Boot), die Quaternius/KayKit nicht abdecken. **KayKit** liefert den **Keller** (Dungeon) und Innenräume. So bleibt der Look zusammenhängend statt zusammengewürfelt.

| Zweck | Empfohlenes Pack | Quelle | Format | Hinweis |
|---|---|---|---|---|
| **Söldner/Gegner/NPC/Zivilisten** | **Ultimate Modular Men / Women** (animiert, modular) + **Universal Base Characters** (Rig) | Quaternius | glTF | Universal Humanoid Rig → Retargeting |
| **Animationen** (idle/geh/renn/**schwimm**/schieß/nachlad/**gun**/tod) | **Universal Animation Library** (120+, inkl. Gun- & Swim-Anims) | Quaternius | glTF | Retarget auf die Charaktere |
| — Alternative Anim-Set | **Character Animations** (161, Ranged/Reload/Aim) | KayKit | glTF | gleicher Retarget-Weg |
| **Feuerwaffen (JA-Ton, echte Namen)** | **Low Poly Weapon Pack** (AK47, Kar98k, M16, StG44, Colt 1911, Mauser C96, .44 Magnum, 12-Gauge, Sniper …) | OpenGameArt (byzmod3d) | OBJ | **CC0** — thematisch ideal; statische Meshes an Hand-Bone |
| — Alternative (stilisiert) | **Ultimate Guns** (40) + **Animated Guns** (6) | Quaternius | FBX/glTF | ggf. poly.pizza als GLB |
| — Alternative (mit Magazinen) | **Blaster Kit** (40, abnehmbare Magazine) | Kenney | glTF | leicht Sci-Fi; Magazine passen zur Mechanik |
| **Palmen / Dschungel / Tropen** | **Nature Kit** (330+, **Palmen bestätigt**) | Kenney | glTF | füllt Quaternius' Tropen-Lücke |
| **Insel / Küste / Steg / Boot / Festungsmauer** | **Pirate Kit** (70, tropische Inseln) | Kenney | glTF | Landezone Süd |
| **Dorfgebäude (modular, mehrstöckig, Innen+Außen)** | **Medieval Village MegaKit** (304 Teile, Treppen→Etagen) | Quaternius | glTF | rustikaler Dorf-Look |
| **Keller / Unterschlupf / Bunker** | **Dungeon Pack Remastered** (200+, Wände/Böden/Treppen/Türen) | KayKit | glTF | Godot Asset Library #2126 |
| **Kisten / Fässer / Zelte / Lager (Deckung & Loot)** | **Survival Pack** (53) | Quaternius | FBX → glTF | poly.pizza-GLB als Shortcut |
| **Innenräume / Möbel** | **Restaurant Bits / Furniture Bits** | KayKit | glTF | Schenke, Wohnhäuser |
| **Militär-Flair (Anwesen-Hof)** | **Animated Tanks** (4) | Quaternius | FBX/glTF | optional, Deko |
| **Gelände-Texturen + Tropen-Licht** | **Poly Haven** (Sand/Wasser/Laub-PBR, HDRIs für Tropenlicht) | polyhaven.com | glTF/Textur | alles CC0 |
| **Tropen-Pflanzen (Detail-Filler)** | **CC0 Palm / CC0 3D Plants** (Palmen, Farne) | OpenGameArt | OBJ/glTF | CC0, ergänzt Kenney Nature |
| **Wasser-Optik** | **Stylized Water Shader** | godotshaders.com | .gdshader | CC0, Godot 4 |

**Praktische Import-Regeln (Godot 4.6):**
- **glTF/GLB bevorzugen** (Drag-&-Drop, Animationen eingebettet). **FBX importiert Godot 4.6 nativ** (ufbx-Importer seit 4.3 — **kein FBX2glTF mehr nötig**); GLB ist trotzdem am saubersten, für FBX-only-Packs notfalls GLBs von `poly.pizza/u/Quaternius`. **OBJ** = nur statische Meshes (gut für die Waffen), Material in Godot zuweisen.
- **Charaktere:** Rig kommt oft **ohne** viele Anims → Animationen separat als **AnimationLibrary** importieren und **retargeten** (§7.7). Waffen-OBJs per **`BoneAttachment3D`** an den Hand-Bone.
- **Skalierung** aller Kits konsistent auf `tile_size = 1 m` normieren (wichtig fürs Grid).
- **Lizenz-Hygiene:** Rückgrat strikt **CC0** (Quaternius/KayKit/Kenney/OGA-CC0/Poly Haven — keine Namensnennung). Bei **Poly Pizza** den **CC0-Filter** nutzen (Mischbestand CC0/CC-BY); **Mixamo** ist frei für kommerzielle Spiele *ohne* Attribution, aber **nicht CC0** (Rohdateien nicht weiterverteilen — im Build eingebettet aber ok). **Falle:** bei Sketchfab/Poly Pizza nie der Beschreibung „CC0" trauen, sondern das **formale Lizenzfeld** prüfen. Sobald CC-BY dabei ist → `CREDITS.txt` führen.
- **Lücke Brücken/Wasserläufe:** kein dediziertes CC0-Brücken-Pack gefunden → **einfache modulare Brücken-Meshes** (Planken/Pfeiler) aus Village-/Survival-Teilen bauen oder als schlichtes Eigen-Mesh; Wasser als eigene Fläche + CC0-Shader (§7.4).

---

## 9. Juice / Game-Feel (macht aus „Rechteck bewegt sich" → „da wurde jemand erschossen")

Verbindlich für die Demo. Jeder Treffer/Schuss löst eine Kombination aus:

| Effekt | Godot-Umsetzung |
|---|---|
| **Hitstop** | `Engine.time_scale = 0.05` für ~60–120 ms, per Timer zurück auf 1.0 |
| **Screenshake** | Trauma-Wert (0–1), pro Frame Kamera-Pivot-Offset = Trauma² × Rausch; Treffer erhöht Trauma, klingt ab |
| **Mündungsfeuer** | `GPUParticles3D` (One-Shot) + kurzer `OmniLight3D`-Blitz am Lauf-Bone |
| **Leuchtspur** | dünner Zylinder/`ImmediateMesh` Lauf→Ziel, ~50 ms sichtbar |
| **Blutdekal** | `Decal` am Trefferpunkt (Boden/Wand), faded aus; + kleiner Blut-Partikelspritzer |
| **Schadenszahl** | `Label3D` überm Kopf, `Tween`: nach oben + ausblenden; Kill in Rot/größer |
| **Treffer-Reaktion** | „Hit"-Animation + kurzer Material-Flash (weiß) am getroffenen Modell |
| **Tod** | Sterbe-Animation + Ragdoll-optional; Söldner-Schmerzlaut (vorhandene Voice-Clips!) |

Erster Durchgang realistisch in **~2 Abenden**. Tuning-Werte (Dauer, Stärke) zentral in einem `juice.gd`/Konstanten-Block, damit man schnell schrauben kann.

---

## 10. Audio (unverändert übernommen)

Wie v2: **ElevenLabs-Stimmen** (jeder Söldner + Vargo: select/quote/reply/pain, vargo_1–3/kampf/ivan_dialog), **Waffen-/Schritt-/Kampf-SFX** (untergrundabhängig: Gras/Holz/Stein/**Wasser-Platschen neu**), **Musik-Zustände** (Titel/Erkundung/Kampf/Sieg/Niederlage). **`sfx.gd` lädt Dateien bevorzugt, Synthese als Fallback** — das Spiel läuft auch ohne MP3s. Neu zu ergänzen: **Schwimm-/Wasser-SFX** und ggf. Otto-Brandt-Stimme (gleicher ElevenLabs-Design-Weg wie die übrigen Söldner).

---

## 11. HUD & Steuerung (JA-Layout in 3D)

- **Portrait-Seitenleisten** (Söldner 1–2 links, 3–4 rechts): Portrait, Name, HP-/AP-Balken, Goldrahmen für den Gewählten; Klick = wählen, Doppelklick = Inventar.
- **Untere Aktionsleiste:** Waffe + Munition, Buttons Nachladen (**R**) · Zielen (**Z**) · Granate (**G**) · Medikit (**H**) · Inventar (**I**) · **Hocken (C)** · Runde beenden (**Enter**) · Menü (**Esc**).
- **Kopfzeile:** Sektor, Runde/Anmarsch, gesichtete/verbleibende Feinde, **Loyalität Silberquell**.
- **Neu:** **Ebenen-Umschalter** (Boden/Dach/Keller) + Höhen-Hinweis am Cursor; **Kamera-Rotation** (Q/E) & Zoom.
- **UI-Stil:** braunes Leder/Holz-Theme (JA-Farbwelt).

---

## 12. Schwierigkeitsgrade (wie v2)

| | LEICHT | NORMAL | SCHWER |
|---|---|---|---|
| Gegner (inkl. Boss) | 10 | 13 | 17 |
| Elitewachen | keine (Miliz) | 3, ans Anwesen gebunden | 3, ans Anwesen gebunden |
| Söldner-Preisfaktor | ×1,0 | ×1,25 | ×1,5 |
| Gegner-Treffsicherheit | −5 | ±0 | +5 |
| Kisten-Loot | 2 Items | 1–2 | 1 |

---

## 13. Umsetzungs-Roadmap (realistisch, in Phasen)

Der 3D-Umzug ist groß — deshalb in **überschaubaren Phasen**, jede für sich lauffähig & testbar:

1. **Fundament 3D:** Ortho-Kamera-Rig, Tile-Datenschicht (`Vector3i→TileData`), Boden-MultiMesh, Maus-Picking, **eine** flache Testkarte, ein Würfel-Söldner bewegt sich per AStar3D. *(Smoke-Test grün.)*
2. **Modelle & Animation:** Quaternius-Charakter + Universal Animation Library retargeten (Idle/Geh/Schieß/Tod), Waffe per BoneAttachment, ein Gegner. Alte Kampf-Logik andocken.
3. **Höhe/Wasser/Brücke:** Ebenen 0/1/−1, Schwimm-Bewegungstyp, Brücke drüber/drunter, Ebenen-Umschalter, Fog of War in 3D.
4. **Demo-Inhalt:** die 3 Sektoren bauen (Küste/Dorf+Keller/Anwesen), Otto-Befreiung + Unterschlupf-Basis, Vargo im mehrstöckigen Haupthaus.
5. **Juice:** Hitstop/Shake/Mündungsfeuer/Tracer/Blut/Schadenszahlen (§9).
6. **Politur & Balance:** Loyalität/Miliz-Deko, Audio-Ergänzungen (Wasser/Otto), Schwierigkeit, Screenshots/Smoke aktualisieren.

Jede Phase hält den Grundsatz aus v2: **öffnet ohne Skriptfehler, Headless-Smoke bleibt grün.**

---

## 14. Abnahmekriterien (Definition of Done — Demo v3)

1. Öffnet in Godot 4.6.3 ohne Skriptfehler; Flow Titel→Schwierigkeit→Anheuern→Inselkarte→Laden→**3D-Taktik**→Ende spielbar.
2. **Echtes 3D:** Ortho-Kamera, rotier-/zoombar, **hart aufs Spielfeld begrenzt**.
3. **Größere Sektoren** (~72×72 begehbar) mit mehrrundigem Anmarsch; **Spawn neutral** (niemand sieht niemanden beim Start, alle 3 Grade — Sonde beweist es).
4. **Gehen, Schwimmen, Brücke (drüber & drunter), Höhe/Dach, Keller** funktionieren und sind per Test/Screenshot belegt.
5. **Befreiungs-Loop:** Otto im Keller befreibar → **Unterschlupf-Basis** aktiv (Ausrüsten/Heilen/Anheuern/Speichern) → Otto als Gratis-Rekrut → Villager-Miliz erscheint.
6. **Inventar/Loot/Magazine** wie v2 (öffnen, Waffe wechseln, nachladen verbraucht Magazin, Granate/Medikit, Kiste & Leiche durchsuchen).
7. **Juice** sichtbar: Treffer erzeugt Hitstop + Shake + Mündungsfeuer + Tracer + Blutdekal + Schadenszahl.
8. **Boss:** Vargo stationär im mehrstöckigen Haupthaus, Dialog genau einmal; Tod → Rest ergibt sich → Sieg.
9. **Stimmen/SFX/Musik** spielen (Datei-bevorzugt, Fallback vorhanden); Schritte untergrundabhängig inkl. Wasser.
10. **Headless-Smoke** (`-- --smoke`): Karte/Erreichbarkeit (inkl. Wasser/Brücke/Ebenen), Anheuern, Loot, Befreiung, Bot-Schlacht bis Sieg, Endscreen — **Exit 0**.

---

## 15. Bewusste Demo-Grenzen (Andockpunkte für den Ausbau)

3 Sektoren · 1 Keller-Basis · 1 Dorf mit einfacher Loyalität · Miliz als Deko · kein Tageszyklus/Gehälter-Abrechnung · keine Minen · Haltungen minimal (Hocken) · Zerstörbarkeit leicht · kein Ragdoll-Pflicht. Alles so gebaut, dass **Städte, Loyalität, Milizen, Einkommen und weitere Sektoren** sauber andocken.

Basis „Der Unterschlupf" (MVP) = **Trupp heilen + Nachschub fassen** (beides echt, gratis); **Anheuern** und **Speichern** = Ausbaustufe (post-Demo, als sichtbare `disabled`-Stubs beschriftet).

---

## 16. Quellen & Credits

**JA-Design (recherchiert & verifiziert):**
[Wikipedia — Jagged Alliance 2](https://en.wikipedia.org/wiki/Jagged_Alliance_2) · [Wikipedia — Jagged Alliance (1)](https://en.wikipedia.org/wiki/Jagged_Alliance_(video_game)) · [StrategyWiki — JA2 Map](https://strategywiki.org/wiki/Jagged_Alliance_2/Map) · [StrategyWiki — JA2 Omerta](https://strategywiki.org/wiki/Jagged_Alliance_2/Omerta) · [Fandom — Metavira](https://jaggedalliance.fandom.com/wiki/Metavira) · [Fandom — Omerta](https://jaggedalliance.fandom.com/wiki/Omerta) · [Fandom — Militia](https://jaggedalliance.fandom.com/wiki/Militia) · [Arulco Cartography — 160×160-Karten](http://arulco.blogspot.com/p/cartography.html)

**Godot-4.6-Technik (offizielle Doku, verifiziert):**
[Camera3D](https://docs.godotengine.org/en/stable/classes/class_camera3d.html) · [AStar3D](https://docs.godotengine.org/en/stable/classes/class_astar3d.html) · [3D-Navigation](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_introduction_3d.html) · [GridMaps](https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html) · [Retargeting 3D-Skelette](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/retargeting_3d_skeletons.html) · [AnimationTree](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html) · [MultiMesh-Optimierung](https://docs.godotengine.org/en/stable/tutorials/performance/using_multimesh.html) · [Occlusion Culling](https://docs.godotengine.org/en/stable/tutorials/3d/occlusion_culling.html)

**Assets (CC0 1.0, sofern nicht anders vermerkt):**
[Quaternius](https://quaternius.com) (Charaktere, Animationen, Guns, Natur, Village MegaKit, Survival, Tanks) · [Kay Lousberg / KayKit](https://kaylousberg.itch.io) (Dungeon Remastered, City Builder, Restaurant/Furniture Bits, Character Animations) · [Kenney](https://kenney.nl) (Nature Kit, Pirate Kit, Blaster Kit) · [OpenGameArt CC0](https://opengameart.org) (byzmod3d Low-Poly-Waffen mit echten Namen, CC0-Palmen/Pflanzen) · [Poly Haven](https://polyhaven.com) (CC0-Texturen & Tropen-HDRIs) · [godotshaders.com](https://godotshaders.com/shader-license/cc0/) (CC0-Wasser-Shader) · [poly.pizza](https://poly.pizza) (GLB-Shortcut, **CC0-Filter nutzen** — Mischbestand) · [Mixamo](https://www.mixamo.com) (Zusatz-Animationen, **frei aber nicht CC0** — Rohdateien nicht weiterverteilen). Kuratierte CC0-Liste: [Retro3DGraphicsCollection](https://github.com/Miziziziz/Retro3DGraphicsCollection).

Eigenständiges Fan-Projekt, inspiriert von **Jagged Alliance (1994)** und **Jagged Alliance 2** — keine Original-Assets oder -Daten enthalten.

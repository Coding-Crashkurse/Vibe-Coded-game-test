# Bauvertrag — Sektor-Geometrie F4 / F3 nach dem Weltkarten-Artwork

> **Status:** Entwurf, noch nicht gebaut. Vorgelagert: die Sektor-Klempnerei
> (`generate(seed, diff, sector)`, `exit_cells`, `load_sector`) existiert bereits.
> Dieser Vertrag beschreibt **nur die Gelaendeform** plus das Landezonen-Gespraech.
>
> **Referenz ist das Artwork** `assets/textures/worldmap.png`. Rasterlinien aus
> `data/sectors.json`: F3 = Pixel x 396..556, z 710..838 · F4 = x 556..710, z 710..838.

---

## 0. Was das Artwork zeigt

| | **F4 — Landing Zone** | **F3 — Rookhaven** |
|---|---|---|
| Bebauung | keine | 3 Pfahlbauten in Reihe, Lehmplatz, Zaun suedlich davon |
| Wasser | Ozean-Bucht im **Osten/Suedosten** | Ozean-Band im **Sueden** |
| Strand | Sandsaum entlang der ganzen Kueste | Sandband + Felskueste im Sueden |
| Vegetation | dichter Palmen-Dschungel im **Nordwesten** | Dschungelriegel im **Osten** (Grenze zu F4) |
| Wege | Pfad von Norden (E4) | Pfad von Norden, Dorf laeuft nach Westen (F2 Docks) weiter |
| Anschluss | **Westkante → F3** | **Ostkante → F4**, Westkante gesperrt (F2) |

**Was NICHT ins Bild gehoert** (heute aber in der F3-Karte steckt): der Fluss ueber
die volle Breite, der Steg, das ummauerte Anwesen. Das Anwesen ist **Helix Manor**
(A9/B10, gesperrt) — es hat in F3 nichts verloren. Vargo wird stattdessen
Dorf-Kommandant in Rookhaven (Nutzerentscheidung 2026-07-20).

---

## 1. Gemeinsame Technik (beide Sektoren)

### 1.1 Ozean = **fehlende Zellen**, kein neuer Kachel-Typ

Ozeanflaeche bekommt **gar keine** `Tac3DTile`. Damit ist sie automatisch
unbegehbar (`Grid3D.is_walkable` → `false` bei fehlendem Key), `GroundView3D`
zeichnet dort nichts, und `Scenery3D._build_ocean` legt bereits heute eine grosse
Wasser-Ebene bei `y = TOP_Y - 0.10 = 0.0` unter die ganze Karte — die Inselkante
taucht sichtbar ins Meer.

**Warum nicht `WATER_DEEP`:** die Kachel waere `Move.SWIM`-begehbar (6 AP), ein
Soeldner koennte aufs offene Meer hinausschwimmen. `VOID` ginge auch, kostet aber
5184 nutzlose Dictionary-Eintraege pro Karte.

⚠️ `_build_ocean` schneidet sein Loch aus dem **Bounding-Rechteck aller `y<0`-Zellen**.
In F3 liegt der Keller unter dem Lagerhaus — Loch und Kellerschacht ueberlappen
sauber. In F4 gibt es kein `y<0` → kein Loch → eine durchgehende Flaeche. Passt.

### 1.2 Strand = generalisiertes `_build_sand_band`, **kein** `Kind.SAND`

Heute: `scenery3d.gd:705` legt eine Sand-Platte auf jede `GROUND`-Zelle mit
`c.z >= BEACH_Z (64)` — ein hartkodiertes Suedband.

Neu: Sand auf jede `GROUND`-Zelle, deren **Chebyshev-Abstand zu einer fehlenden
Zelle (= Meer) ≤ 4** ist. Damit umsaeumt der Sand jede Kueste automatisch, egal
wie sie verlaeuft. Faellt auf das alte `z >= BEACH_Z` zurueck, wenn die Karte gar
keine Meereskante hat (Testkarte, Demo-Szene) → Bestandsverhalten bleibt.

Kein Enum-Eintrag, keine Aenderung an `assets3d.gd`/`ground_view.gd`. Die
Sand-Farbe existiert schon (`TERRAIN_COLOR["sand"]`, `terrain_material_named`).

### 1.3 Dschungel = neues `Tac3DTile.FLAG_JUNGLE := 16`

`Scenery3D._scatter` streut Palmen heute mit `PALM_P_INLAND = 0.025` — viel zu
duenn fuer die Dickichte im Artwork. Die MapGen markiert Dschungelzellen mit
`FLAG_JUNGLE`, `_scatter` hebt dort auf `PALM_P_JUNGLE = 0.30` an und senkt
`PALM_MIN_DIST` von 4 auf 2.

Additiv wie `FLAG_KEEPOUT` (Wert 8) — naechster freier Bitwert ist 16.

⚠️ **Palmen machen Zellen unbegehbar** (`scenery3d.gd:802`). Ein zu dichter
Riegel kann den Weg abschneiden. Absicherung existiert bereits: `main.gd` S6 prueft
Erreichbarkeit Landepunkt → Westausgang. Fuer F3 muss ein **gleichwertiger Test**
dazu (Ostkante → Lagerhaus-Tuer → Kellertreppe).

### 1.4 Optional (Phase 2): Zaun = `FLAG_FENCE := 32`

Das Artwork zeigt in F3 einen deutlichen Lattenzaun. Heute wuerde `_cover_props`
dort eine Reihe **Kisten** hinstellen. Ein niedriges Planken-MultiMesh
(`cover 0.3`, `blocks_sight = false`) liest sich richtig. Nicht blockierend fuer
den ersten Durchstich — kann nachgereicht werden.

---

## 2. F4 — Landing Zone

### 2.1 Kuestenlinie

Die Ozean-Bucht frisst sich von **Osten** herein und rollt in die **Suedost-Ecke**.
Zelle `(x, z)` ist Meer (= kein Tile), wenn `x > coast_x(z)`.

Stuetzpunkte, dazwischen **linear interpoliert**:

| z | 0 | 8 | 16 | 24 | 32 | 40 | 48 | 54 | 58 | 62 | 66 | 70 | 71 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `coast_x` | 54 | 56 | 58 | 60 | 61 | 60 | 57 | 53 | 49 | 44 | 38 | 30 | 27 |

Ergebnis: ~62 % Landflaeche, eine gerundete Bucht im SO, Nordkante bis x=54 begehbar.

### 2.2 Landezone, Ausgang, Dschungel

- **Heli-Landung (Sued, auf dem Sand):** `(34,0,63) (35,0,63) (34,0,64) (35,0,64)`
  → `coast_x(63) ≈ 43`, also 8 Zellen westlich der Wasserkante. Der Trupp steht
  mit dem Meer im Ruecken. Diese 4 Zellen tragen `FLAG_KEEPOUT` (keine Palme).
- **Westausgang:** Spalte `x = 0` (Bestand, `F4_EXIT_X`). Marschweite von der LZ
  ≈ 34 Zellen westwaerts — ein echter Zug quer ueber die Karte.
- **Dschungel (`FLAG_JUNGLE`):** Rechteck `x = 0..26`, `z = 0..30` (Nordwest-Masse)
  plus ein Riegel `x = 8..20`, `z = 44..56`, der den direkten Sichtkorridor
  LZ → Ausgang bricht. Beide Rechtecke lassen **Spalte x = 0..2 frei**, damit der
  Ausgang nie zuwachsen kann.
- **Fels-/Ruinenriegel** (`F4_ROCK_WALLS`, Bestand): unveraendert uebernehmen, aber
  gegen die neue Kueste pruefen — `{"x0": 44, "z0": 56, ...}` liegt bei
  `coast_x(56) ≈ 51` noch an Land, `{"x0": 34, "z0": 26, ...}` ebenfalls. OK.

### 2.3 Gegner

`F4_ENEMY_SPAWNS` (Bestand, 4 Patrouillen) auf die neue Diagonale LZ → Westausgang
umsetzen. Alle vier liegen heute bei `x ≤ 38` und damit sicher an Land; nur der
Strandposten `(38,0,58)` gegen `coast_x(58) = 49` pruefen → passt.

---

## 3. F3 — Rookhaven

### 3.1 Kuestenlinie (Sued)

Zelle `(x, z)` ist Meer, wenn `z > coast_z(x)`:

| x | 0 | 12 | 24 | 36 | 48 | 60 | 71 |
|---|---|---|---|---|---|---|---|
| `coast_z` | 66 | 64 | 62 | 61 | 63 | 66 | 68 |

Flacher, ruhiger Suedstrand — im Artwork ist die Kueste hier weit weniger
zerklueftet als in F4.

### 3.2 Dorfkern — drei Pfahlbauten in Reihe

Format wie `VILLAGE_BUILDINGS`: `{x0, z0, w, h, door}`. Alle Tueren nach **Sueden**
(zum Platz hin), so wie im Artwork.

| # | Gebaeude | x0 | z0 | w | h | Tuer |
|---|---|---|---|---|---|---|
| 1 | **Lagerhaus** (gross, Keller!) | 14 | 12 | 12 | 11 | `(20, 0, 22)` |
| 2 | Wohnhaus | 30 | 15 | 9 | 8 | `(34, 0, 22)` |
| 3 | **Helix-Kommandoposten** (Vargo) | 42 | 15 | 9 | 8 | `(46, 0, 22)` |

- **Lehmplatz:** `Kind.FLOOR`-Streifen `z = 23..26`, `x = 12..52` — verbindet die
  drei Tueren, genau der Platz aus dem Artwork.
- **Zaun** (optional, §1.4): `z = 28`, `x = 12..54`, Luecken bei `x = 20..21`,
  `34..35`, `46..47`.
- **Dschungelriegel Ost** (`FLAG_JUNGLE`): `x = 58..71`, `z = 0..58` — die Grenze
  zu F4. **Aussparung fuer den Eingangskorridor:** `z = 32..40` bleibt frei.
- **Westkante (F2, gesperrt):** zwei angeschnittene Huetten bei `x = 0..6`,
  `z = 16..20` bzw. `z = 26..30` + Steg-Stummel — reine Optik, signalisiert
  „das Dorf geht weiter".

### 3.3 Keller = Der Unterschlupf, unter dem Lagerhaus

Spec §3.3.3 verlangt woertlich *„locked in the storehouse cellar (level −1)"* —
der heutige freistehende Kellereingang mitten im Dorf erfuellt das nicht.

- Kellerraum (Ebene −1): `x = 17..22`, `z = 15..20`
- Treppe (Ebene 0, **im Lagerhaus**): `(19, 0, 18)` → `add_link` → `(19, -1, 18)`
- **Tobias/Otto:** `(20, -1, 19)`

Nebeneffekte, die **automatisch stimmen**:
`ground_view.gd:66` sortiert Ebene-0-Zellen mit Raum darunter in eigene `_LID`-
MultiMeshes → `set_cellar_open(true)` klappt den Lagerhausboden auf, sobald jemand
unten steht. `scenery3d._build_cellar_pit` zieht die Erdwaende drumherum.
`_build_roofs` ueberspringt `y < 0` → kein Dach im Keller.

### 3.4 Spawns

- **Merc-Eintritt aus F4 = Ostkante:** `(68,0,34) (69,0,34) (68,0,35) (69,0,35)`
  — liegt in der Dschungel-Aussparung `z = 32..40`.
- **Vargo (`BOSS_HOME`):** `(46, 0, 18)` — im Kommandoposten, Dialog bei Sichtkontakt.
- Uebrige Milizposten auf Platz, Lagerhaustuer und Nordpfad verteilen; Gesamtzahl
  bleibt bei dem Wert, den die Sektor-Session in `DEMO_ENEMY_TOTAL` festgelegt hat.

---

## 4. Landezonen-Gespraech (Ziel = Westen)

**Ausloeser:** direkt nach `battle_ready` in F4, vor der ersten Eingabe.
Guard: `sector == "F4" and not fast and hud != null and not Game.flags.get("lz_banter_seen", false)`.
Im `fast`/Headless-Lauf passiert nichts → Bot-Tests unberuehrt.

**Inhalt** — genau vier Zeilen, sie muessen drei Dinge liefern: *Kontakt sitzt in
Rookhaven* · *Rookhaven liegt im Westen* · *der Nordkamm ist vermint* (die
Fiktions-Begruendung fuer die gesperrten Kanten, spec §2).

Neue Konstante in `db.gd`, neben `TOBIAS_DIALOG`:

```gdscript
## Phase 7 — Wortwechsel zweier Soeldner direkt nach der Heli-Landung in F4.
## `slot` indiziert Game.team; bei nur EINEM Soeldner faellt Slot 1 auf 0 zurueck.
## `voice` ist der SLOT-Schluessel: gespielt wird "<merc_id>_<voice>". Fehlt die
## Datei, greift der Synth-Fallback in sfx.gd — keine Generierung noetig.
const LZ_BANTER := [
	{"slot": 0, "voice": "lz_a", "text": "Bird's gone. That was the last easy ride we get."},
	{"slot": 1, "voice": "lz_b", "text": "Employer says our contact sits in Rookhaven. Fishing village."},
	{"slot": 0, "voice": "lz_c", "text": "And Rookhaven is where, exactly?"},
	{"slot": 1, "voice": "lz_d", "text": "West. Follow the coast. And stay off the north ridge — Helix mined it."},
]
```

**UI:** `CombatHud.show_squad_banter(lines: Array) -> void`, geklont aus
`show_tobias_dialog` (`combat_hud.gd:1274`) — gleiches modales Panel, gleicher
Typewriter, `modal_active` blockt Hotkeys. Einziger Unterschied: Portrait und Name
kommen pro Zeile aus `Game.team[slot]` statt aus einer festen Rolle.

**Vertonungs-Slot (bewusst NICHT jetzt generieren):** die Schluessel
`<merc_id>_lz_a` … `_lz_d` sind reserviert. Voll vertont waeren das 9 Soeldner × 4
Zeilen = **36 Clips** — unverhaeltnismaessig fuer vier Saetze. Empfehlung: erst
den Loop spielbar machen, dann nur fuer die 2–3 meistgeheuerten Soeldner
generieren; alle uebrigen laufen ueber den Synth-Fallback, der ohnehin nie crasht.

---

## 5. Abnahme

1. `--sector3d` (bzw. der Testmodus der Sektor-Session) bleibt gruen, inkl. S6
   „Westausgang vom Landepunkt erreichbar" — **jetzt gegen die neue Kueste**.
2. **Neuer Test F3:** Ostkanten-Eintritt → Lagerhaustuer → Kellertreppe →
   Tobias-Zelle erreichbar. Faengt einen zugewachsenen Dschungelriegel ab.
3. `--smoke3d`, `--hud3d`, `--demo3d`, `--menu` bleiben gruen.
4. **Lokaler Sichtcheck per F5 + Screenshot-Modus** (Cloud/Headless zeigt weder
   Kuestenform noch Palmendichte): Bucht im SO von F4 sichtbar, Sandsaum laeuft der
   Kueste nach, Dorf liest sich als drei Haeuser mit Platz, kein Fluss, kein Anwesen.
5. Landezonen-Gespraech laeuft genau **einmal**, nur in F4, nur im Nicht-Bot-Lauf.

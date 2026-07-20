# 3D asset credits

Per SPEC v5 §9. All models below are CC0 (public domain) unless noted otherwise.

## Quaternius — https://quaternius.com

License: **CC0 1.0 Universal**. No attribution required; credited here voluntarily.

- `characters/modular/` — *Ultimate Modular Characters* (20 rigged GLBs).
  Used to give each of the nine A.I.M. mercs a distinct body, per §4.1 step 4
  ("Color code per merc = recognizability at distance"). Combined with the
  per-merc uniform tint from `Db.MERCS[].tint`.
- `characters/Swat.glb`, `characters/Casual.glb`, `characters/BusinessMan.glb` —
  *Ultimate Modular Men*. Legacy defaults, still used as fallbacks and for
  enemy/boss units.
- `weapons/rifle.glb` — *Ultimate Guns*.
- `weapons/pistol_4.obj`, `weapons/pistol_5.obj`, `weapons/shotgun_1.obj`,
  `weapons/shotgun_2.obj`, `weapons/sniperrifle_1.obj` — *Ultimate Gun Pack*
  (OpenGameArt "Low Poly Guns Pack" / quaternius.com). One distinct mesh per
  Db weapon, so P9, K45, Huntsman, Dragonmaw and SVD are told apart by
  silhouette and not just by name (§4.1 step 4). Each `.obj` ships with its
  `.mtl`; `Db.WEAPONS[<id>]["mesh"]` points at the `Assets3D.WEAPONS` id.
- `props/` — *Survival Pack* (crates, barrels, chest).

## KayKit — https://kaylousberg.itch.io

License: **CC0 1.0 Universal**.

- `keller/` — *Dungeon Remastered* (floor, wall, stairs) — the storehouse cellar.
- `characters/Barbarian.glb` — *Character Pack: Adventurers*. Legacy, no longer
  referenced by the runtime.

## OpenGameArt — https://opengameart.org

- `nature/palm.obj` — CC0 low-poly palm.
- `weapons/pistol.obj` — byzmod3d *Low Poly Weapon Pack*, CC0.

---

**Fallback law:** every model above is optional. If a file is missing, the
runtime degrades to a capsule/box placeholder (see `scripts/assets3d.gd` and
`scripts/tac3d/unit3d.gd`), so headless tests stay green on a bare checkout.

*Independent fan project inspired by Jagged Alliance 1/2 — contains no original
assets or data.*

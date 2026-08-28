# Base Defense

An endless top-down survival shooter / base builder built with Godot 4.

Survive escalating enemy waves on an infinite map. Harvest four resources,
research unlimited upgrades, and build a powered fortress of walls and towers.
A boss appears every 10th wave. Only death ends a run.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Move |
| Mouse | Aim |
| Left mouse button | Shoot / place selected building (hold to drag-paint walls) |
| 1–9, 0, mouse wheel, click | Select hotbar slot |
| X | Toggle grid snapping while placing |
| T | Research tree (pauses) |
| P | Pause |
| Esc | Close open panel / unpause |
| R | Restart after death |

## Systems

- **Resources** — Scrap (kills), Crystal (shoot ore blocks or place Miners
  beside them), Gold (Harvester drones trained at a Command Center haul it
  from gold ore), Energy (Solar Panels; every tower attack consumes some —
  starved devices dim and show a blinking bolt). The HUD energy chip shows
  banked energy plus production/consumption per second.
- **Research** (T) — three tabs. Player Stats and Building Stats upgrades are
  infinitely repeatable (cost ×1.6 per level; gold joins the cost from level
  5): damage, fire rate, crit chance/damage, speed, health, regen, building
  HP, tower speed/damage/crit, miner yield. Unlocks tab: Miner, Walls, six
  towers, Solar Panel, Command Center.
- **Building** — grid-snapped placement with a ghost preview, tower range
  rings, and a tooltip showing cost and blockers. Towers: MG, Grenade,
  Repair Beam, Tesla (chain lightning), Flamethrower, AA Flak (air-only).
  Enemies gnaw through walls; wasps fly over them.
- **Enemies** — grunts, brutes, healers, mages (summon runners), flying
  wasps, and the Broodmother boss every 10 waves. Health scales
  exponentially; off-screen stragglers teleport back after 5s.

## Running

Open the project in the Godot editor and press F5, or:

```sh
godot --path .
```

The main menu has graphics (fullscreen, V-Sync, resolution) and audio
(master/effects volume, mute) settings, persisted to `user://settings.cfg`.

## Project structure

- `scenes/`, `scripts/` — game scenes and their scripts (mostly 1:1);
  `scripts/enemies/`, `scripts/effects/` hold variants and visual effects
- `scripts/game_state.gd` — autoload: resources, research, hotbar, stat and
  building tables (single source of truth for costs/slots/ranges)
- `scripts/settings.gd`, `scripts/sfx.gd` — autoloads: settings, sounds
- `scripts/util.gd`, `scripts/ui_theme.gd`, `scripts/effects.gd` — shared
  helpers (class_name globals)
- `scripts/build_controller.gd` — placement/ghost logic (child of the player)
- `assets/sprites/` — hand-authored SVG sprites (player, enemies, buildings,
  minerals); `assets/icons/` — UI icons; `assets/sfx/` — synthesized WAVs

# Base Defense

An endless top-down survival shooter built with Godot 4.

Survive escalating enemy waves on an infinite map. Harvest Scrap from kills and
Crystal from ore blocks, research upgrades and buildings, and build a fortress
of walls and towers. A boss appears every 10th wave. Only death ends a run.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Move |
| Mouse | Aim |
| Left mouse button | Shoot / place selected building |
| 1–6 | Select hotbar slot |
| T | Research tree (pauses) |
| Esc | Close research |
| R | Restart after death |

## Systems

- **Resources** — Scrap drops from kills; Crystal is chipped off ore blocks by
  bullets or extracted by Miners placed next to them (crystal is infinite).
- **Research tree** (T) — three branches. Offense and Pilot stat upgrades
  (damage, fire rate, crit chance/damage, speed, health, regen) are
  **infinitely repeatable** with costs growing ×1.6 per level. Industry
  one-time unlocks: Miner, Walls, MG Tower, Grenade Tower, Repair Beam Tower.
- **Building** — select a building in the hotbar; a ghost preview (with range
  circle for towers) shows validity; click pays the cost and places it.
  Enemies gnaw through walls; repair towers heal buildings and you.
- **Enemies** — grunts, brutes (tanks), healers, mages (summon runners), and
  the Broodmother boss every 10 waves. All enemy health scales exponentially.
- **XP & levels** — kills grant XP; levels add small passive damage/speed.

## Running

Open the project in the Godot editor and press F5, or:

```sh
godot --path .
```

The main menu has graphics (fullscreen, V-Sync, resolution) and audio
(master/effects volume, mute) settings, persisted to `user://settings.cfg`.

## Project structure

- `scenes/`, `scripts/` — game scenes and their scripts (mostly 1:1)
- `scripts/game_state.gd` — autoload: resources, research, hotbar, stats
- `scripts/settings.gd`, `scripts/sfx.gd` — autoloads: settings, sound effects
- `scripts/ui_theme.gd` — shared UI theme built in code
- `assets/sprites/enemies/` — hand-authored SVG enemy sprites
- `assets/icons/` — SVG UI icons
- `assets/sfx/` — procedurally generated WAV sound effects

All visuals are SVG sprites or placeholder polygons; audio is synthesized —
both are easy to replace with real assets later.

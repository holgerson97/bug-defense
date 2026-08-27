# Base Defense

A 2D top-down base defense shooter built with Godot 4.

Defend the base in the center from waves of enemies. Waves get bigger, faster,
and tougher over time. Survive as long as you can.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Move |
| Mouse | Aim |
| Left mouse button (hold) | Shoot |
| R | Restart after game over |

## Running

Open the project in the Godot editor (import `project.godot`) and press F5,
or from the terminal:

```sh
godot --path .
```

## Project structure

- `scenes/main.tscn` — root scene: base, player, wave manager, HUD
- `scenes/player.tscn` + `scripts/player.gd` — movement, aiming, shooting
- `scenes/bullet.tscn` + `scripts/bullet.gd` — projectile, damages enemies
- `scenes/enemy.tscn` + `scripts/enemy.gd` — chases the base, attacks in range
- `scenes/base.tscn` + `scripts/base.gd` — health, game over signal
- `scenes/hud.tscn` + `scripts/hud.gd` — health/wave/score display, game over screen
- `scripts/wave_manager.gd` — spawns escalating waves in a ring around the base

All visuals are placeholder `Polygon2D` shapes — replace them with sprites
whenever you have art.

## Ideas for next steps

- Player health and enemy attacks on the player
- Multiple enemy types (fast/weak, slow/tank, ranged)
- Buildable turrets and walls between waves
- Upgrades/shop using score as currency
- Sound effects, screen shake, hit flashes
- Sprites and animations instead of polygons

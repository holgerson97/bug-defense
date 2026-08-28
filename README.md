# Base Defense

An endless top-down survival shooter / base builder built with Godot 4.
Single-player or LAN co-op for up to 4 players.

Survive escalating enemy waves on an infinite map. Harvest four resources,
research unlimited upgrades, and build a powered fortress of walls and towers.
A boss appears every 10th wave. Only death ends a run.

## Controls

| Input | Action |
|---|---|
| WASD / arrow keys | Move |
| Mouse | Aim |
| Left mouse button | Shoot / place selected building (hold to drag-paint walls) |
| Right mouse button | Sell the building under the cursor (50% refund) |
| 1–9, 0, mouse wheel, click | Select hotbar slot |
| Space | Toggle auto-attack (aims and fires at the nearest visible enemy) |
| F (hold) | Heal beam — mends the most damaged building in range (costs energy) |
| X | Toggle grid snapping while placing |
| R | Rotate building while placing (45° steps) |
| T | Research tree (pauses offline; the world keeps running in co-op) |
| G | Godmode (no damage, free resources; host-only in co-op, applies to the room) |
| P | Pause (host-only in co-op — pauses every player) |
| Esc | Close open panel / unpause |
| R | Restart after death (co-op: only the host restarts, for everyone) |
| Mouse wheel while dead (co-op) | Cycle the teammate you spectate |

## Systems

- **Resources** — Bug Hearts (dropped by kills, spent on research), Crystal
  (shoot ore blocks or place Miners beside them; pays for every building),
  Gold (Harvester drones trained at a Command Center haul it from gold ore; each center hosts at most 5 workers, shown as an n/5 label),
  Energy (Solar Panels; every tower attack consumes some — starved devices
  dim and show a blinking bolt). Energy storage is capped (base 100); each
  Battery building extends the cap by 100. The HUD energy chip shows
  stored/cap plus production/consumption per second.
- **Power grid** — consumers only work inside grid coverage: Power Poles
  chain to sources (≤250px links, sagging cables drawn between) and cover a
  160px radius; solar panels, batteries and the Command Center feed the grid
  directly. For big output, assemble a power complex: an Intake Station
  burns crystal for energy, but only with a Cooling Tower, a Battery and a
  grid-connected Power Pole within 110px — extra cooling towers (up to 3)
  raise the yield. Light Poles need no power.
- **Research** (T) — three tabs. Player Stats and Building Stats upgrades are
  infinitely repeatable (cost ×1.6 per level; gold joins the cost from level
  5): damage, fire rate, crit chance/damage, speed, health, regen, light
  radius, build range, building HP, tower speed/damage/crit, miner yield.
  Unlocks tab is sorted into three top-down columns — Defense (Walls, six
  towers), Resource (Miner, Command Center), Electricity (Solar Panel,
  Battery, Light Pole, Searchlight).
- **Building** — grid-snapped placement with a ghost preview and a tooltip
  showing cost and blockers. Attack towers are directional: they only engage
  enemies inside a facing wedge, chosen with R while placing; the ghost shows
  the wedge (or a full ring for the omnidirectional Repair Beam). Towers: MG,
  Grenade, Repair Beam, Tesla (chain lightning), Flamethrower (lobs fire
  globs that leave burning ground patches), AA Flak (air-only). Enemies gnaw
  through walls and steer around obstacles; wasps fly over everything.
- **Terrain** — large organic rock formations (blocks, L/U/S shapes) block
  movement, bullets and building — natural cover to anchor walls against.
  Crystals spawn in mineral-line clusters; a countdown between waves shows
  at the top of the screen.
- **Night & light** — pitch-black nights; towers only fire at lit enemies
  and never through rocks. Light Poles cast a static pool; the Searchlight
  reveals a 36° cone of normal visibility, sweeping 140° around its placement
  facing; the player carries a headlamp and a reactor aura that powers
  nearby towers.
- **Enemies** — grunts, brutes, mages (summon wave-scaled runner swarms and
  kite the player), flying wasps (swarming from wave 14), armored Drone air
  tanks (from wave 8, surging on boss waves), and the Broodmother boss every
  10 waves (broods runner rings, raging at 75/50/25% HP). Health scales
  exponentially; off-screen stragglers teleport back after 5s. The HUD shows
  the remaining enemies of the current wave per type, and arrows point to
  the last stragglers.

## Multiplayer (LAN co-op, up to 4 players)

Main menu → **Co-op**. One player presses **Host** (opens UDP port 4514);
the others enter the host's LAN IP and press **Join**. The lobby lists all
connected players (colored by join order); only the host can press **Start**.
Joining a game already in progress works too: the joiner is parked in the
lobby ("Game in progress — joining at next intermission") and drops in beside
a teammate when the next intermission starts, with the full base, economy and
wave state caught up.

- **Host-authoritative**: the host simulates waves, enemies, buildings and
  the economy; clients send intents (build, sell, research, fire) and render
  synced state. Single-player is simply a session with zero peers.
- **Shared economy**: one bug-heart/crystal/gold/energy pool and one research
  tree for the whole team; anyone can spend, everyone benefits.
- **Death & respawn**: a dead player spectates a living teammate (mouse
  wheel cycles targets) and respawns automatically at the start of the next
  intermission. A full team wipe ends the run for everyone; the host can
  restart the run for the whole room with R.
- **Pause & panels**: P pauses everyone but only the host can use it; the
  research panel and Esc menus are local and never stop the shared world.
- Transport is LAN (ENet) behind the `Net` autoload seam — see
  `documentation/reference/multiplayer_net_seam.md` for the Steam swap notes.

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
- `scripts/net.gd` — autoload: the multiplayer seam (peer lifecycle, player
  registry, late-join gate); `scripts/enemy_sync.gd`, `scripts/fx_events.gd`
  — enemy transform batching and the combat-FX event bus
- `scripts/util.gd`, `scripts/ui_theme.gd`, `scripts/effects.gd` — shared
  helpers (class_name globals)
- `scripts/build_controller.gd` — placement/ghost logic (child of the player)
- `assets/sprites/` — hand-authored SVG sprites (player, enemies, buildings,
  minerals); `assets/icons/` — UI icons; `assets/sfx/` — synthesized WAVs

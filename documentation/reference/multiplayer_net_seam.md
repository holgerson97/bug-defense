# Multiplayer Net Seam

**Status**: Stable
**Created**: 2026-08-28

Single source of truth for how networking is layered, what a Steam transport
swap touches, the full RPC surface, the binary packet formats, and the
accepted gaps. Written for the day GodotSteam + `SteamMultiplayerPeer`
replaces LAN ENet.

## Architecture in one paragraph

The game is host-authoritative: the host simulates everything (waves,
enemies, building HP, power/nav grids, the shared economy), clients render
synced state and send intent RPCs. Offline is literally a session with zero
peers — `Net.is_host()` is true with no peer set, so every gameplay branch
takes the direct path with zero RPC overhead. World terrain is never
synced: it regenerates deterministically on every peer from one `run_seed`
(per-chunk `hash(run_seed ^ hash(chunk))` reseed of the global RNG).

## The seam: `scripts/net.gd` (autoload `Net`)

`Net` is the ONLY code that touches the transport. It owns:

- the `MultiplayerPeer` (`_peer`, currently `ENetMultiplayerPeer`) — created
  in `host(port)` / `join(ip, port)`, torn down in `leave()`;
- the replicated player registry `players: {peer_id -> {name, color}}`;
- `is_host()` / `is_online()` — the two predicates every gameplay gate uses;
- the run seed and `game_running` flag (start RPC carries the seed);
- the late-join gate: `SceneMultiplayer.auth_callback` holds joiners in the
  auth phase while a game runs; `release_late_joiners()` (called at each
  intermission) tells them to load `main.tscn` FIRST and only then complete
  auth, so spawner catch-up replication lands in a matching tree.

Everything else in the codebase only calls `Net.is_host()`, `Net.is_online()`,
`Net.players`, `Net.run_seed`, and the signals `player_list_changed`,
`session_ended(reason)`, `late_join_status(message)`.

## What a SteamMultiplayerPeer swap needs

1. **Peer factory**: in `Net.host()` / `Net.join()`, build a
   `SteamMultiplayerPeer` (GodotSteam) instead of `ENetMultiplayerPeer`:
   `create_host()` and `create_client(host_steam_id)`. No other file changes —
   the high-level `multiplayer` API (RPCs, spawners, synchronizers, the
   SceneMultiplayer auth phase) is transport-agnostic.
2. **Lobby mapping**: `join(ip, port)` becomes `join(lobby_id)`; a Steam
   lobby (create/search/invite) resolves to the host's Steam ID. The lobby UI
   in `main_menu.gd` swaps the IP field for a friends/lobby list; the
   existing `players` registry stays (fill `name` from `Steam.getFriendPersonaName`
   instead of the OS username in `_os_name()`).
3. **Port**: `DEFAULT_PORT` (4514) is ENet-only; Steam P2P needs no open
   port (relay/NAT traversal is Steam's).
4. **Keep**: the auth-phase late-join gate, the registry broadcast, the
   session signals — all sit above the peer and work unchanged.
5. **Init/teardown**: `Steam.steamInit()` at boot, run callbacks per frame
   (GodotSteam requirement) — put both in `Net` to keep the seam single-file.

## RPC surface inventory

Direction legend: C→H = client intent (validated on the host), H→C = host
broadcast/state, H→owner = host to one peer. All reliable unless noted.

- `net.gd` — `_rpc_register` (C→H name announce), `_rpc_sync_players`
  (H→C full registry), `_rpc_start_game` (H→all, call_local, carries seed).
  Plus auth-phase payloads via `send_auth`: `{wait}`, `{late, seed}`,
  `{ready}` — not RPCs, but part of the wire surface.
- `game_state.gd` — C→H intents: `_rpc_add_resource`, `_rpc_add_scrap_bounty`,
  `_rpc_spend`, `_rpc_purchase`; H→C: `_rpc_sync_state(resources, purchased,
  godmode)` — full-state mirror, dirty-flag debounced to ≤1/physics frame
  (flushes even while paused: `process_mode` ALWAYS).
- `main.gd` — C→H: `_rpc_scene_ready` (spawn handshake); H→all (call_local):
  `_rpc_game_over`, `_rpc_restart(seed)`, `_rpc_set_paused`; H→one:
  `_rpc_set_score`, `_rpc_sync_building_hp` (late-join batch:
  `{building_name: [health, max_health]}` for pre-damaged buildings).
- `wave_manager.gd` — H→C: `_rpc_wave_started`, `_rpc_intermission`,
  `_rpc_wave_events(counts, points)` (remaining/kill-score batch,
  ≤1/physics frame).
- `enemy_sync.gd` — H→C: `_rpc_transforms` (UNRELIABLE, see format below),
  `_rpc_death(pos, dir)` (death FX; the despawn itself rides the spawner).
- `fx_events.gd` — H→C: `_rpc_events(events)` — one batched reliable RPC per
  flush (per-peer copies only when an event excludes a peer).
- `build_controller.gd` — C→H intents: `_rpc_place_building`,
  `_rpc_sell_building`, `_rpc_place_miner`; H→C events: `_rpc_sell_fx`,
  `_rpc_spawn_miner` (both `any_peer` + sender-must-be-1 guard, because the
  controller's node authority is its OWNING PEER, not the host — an
  `"authority"` annotation here gets host broadcasts rejected).
- `building.gd` — C→H: `_rpc_heal` (player heal beam); H→C:
  `_rpc_set_health` (event-driven authoritative HP).
- `player.gd` — C→H: `_rpc_fire(pos, rot, dmg, crit)` (damage clamped
  host-side); H→owner (sender-1 guarded): `_rpc_take_damage`, `_rpc_revive`.
- `boss_broodmother.gd` — H→C: `_rpc_boss_health` (1 Hz bar mirror).

Spawner/synchronizer surface (not RPCs, but replication):

- `PlayerSpawner` payload `[peer_id, position]`; node name = peer id →
  authority. Player `MultiplayerSynchronizer`: position/rotation/velocity
  always @ 20 Hz unreliable; health/dead on-change reliable.
- `BuildingSpawner` payload `[scene_id, pos, facing]` under `Main/Buildings`.
- `EnemySpawner` payload `[sync_id, kind, pos, stat-override dict]` under
  `Main/Enemies`; node name = `E<sync_id>`.
- Miners are NOT spawner-replicated (they parent under order-dependently
  named deposits): position-keyed `_rpc_spawn_miner` events instead.

## Packet formats

**Enemy transforms** (`enemy_sync.gd`, unreliable, 12 Hz): per packet
`[u16 count, then per enemy: u32 sync_id, f32 x, f32 y, u8 rot*255/TAU]`
= 13 B/enemy. Chunked at 100 enemies/packet (1302 B) to stay under the ENet
MTU (1392 B) — a 350 horde is 4 packets/tick ≈ 55 KB/s per client. Clients
cache `sync_id → node`, snap over 200 px, otherwise exp-smooth (~120 ms).
Soak-measured host peak: ~95 KB/s total sent at 154 enemies + 3 clients.

**FX events** (`fx_events.gd`, reliable, ≤1 flush/physics frame): an array
of `[kind, args]` where kind ∈ TOWER_FIRE, AA_FIRE, TESLA_BOLT, FLAME_GLOB,
FLAK_BURST, GRENADE_LOB, REPAIR_BEAM, HEAL_BEAM, PLAYER_FIRE. Args carry
node paths/positions/angles; replay is pure cosmetics + sfx (cosmetic
tracers/globs/shells have damage disabled). A per-event `except` peer skips
the client whose local visual already exists (own tracer, own heal beam).

## Known gaps (accepted)

- **Client searchlight sweep drift**: puppets run the sweep locally (pure
  visual); phase drifts after pause/late-join. `covers()`/vision only run
  host-side, so nothing gameplay-visible depends on it.
- **Client NavGrid runs unused**: since Phase 5 clients simulate no
  enemies/towers, their NavGrid feeds nothing — left running because it is
  cheap, harmless, and keeps the peer trees identical.
- **Late-joiner building max HP**: buildings rebuilt by spawner catch-up
  compute `max_health` from the joiner's not-yet-synced research mirror.
  Damaged buildings get `[health, max_health]` via `_rpc_sync_building_hp`;
  undamaged ones can show a wrong max if Reinforced Structures levels were
  bought before they were placed (cosmetic — HP is host-owned anyway).
- **Pre-wave-1 late join**: joiners held during the very first intermission
  are only released at the NEXT intermission (after wave 1).
- **Boss HP bar at 1 Hz** on clients; regular enemy HP is not replicated at
  all (client bars would sit full — they are hidden at full HP, so nothing
  shows).
- **Enemy z-order**: the `Enemies` container carries `z_index = 2`, so z-0
  FX (blood, impacts, bullets) render under enemy sprites — subtle, offline
  too, not net-related.

# Co-op Multiplayer (up to 4 Players)

**Status**: Completed
**Created**: 2026-08-28
**Last Updated**: 2026-08-28

## Goal & Context

Base Defense is a fully single-player Godot 4 survival base builder: one autoloaded
`GameState` owns resources/research/energy, the wave manager simulates up to 350
enemies, and every system (power grid, nav grid, lighting, building placement)
assumes exactly one local player. Goal: 2–4 player co-op — shared base, shared
resource pool, everyone builds and fights together — reachable over LAN first,
with the transport abstracted so Steam (GodotSteam + SteamMultiplayerPeer) can be
swapped in later without touching game code.

Confirmed by user (2026-08-28):
- **LAN-first** via built-in `ENetMultiplayerPeer`; Steam is a later thin layer.
- **Fully shared economy**: one scrap/crystal/gold/energy pool, one research tree.
- **Wave respawn**: a dead player spectates until the current wave is cleared
  and respawns at the start of the next intermission; **team wipe ends the run**.
- **Host-authoritative**: the host simulates everything; clients send intents.
- Single-player must keep working unchanged (offline = host with zero peers).

## References

- `scripts/game_state.gd` — autoload to split into host-owned state + replicated view
- `scripts/wave_manager.gd` — host-side simulation loop, signals to replicate
- `scripts/build_controller.gd` — per-player; placement becomes an RPC intent
- `scripts/power_grid.gd`, `scripts/nav_grid.gd` — host-side; clients need only visuals
- `scripts/enemy.gd` + `scripts/enemies/*` — server-sim + transform sync targets
- `scripts/main.gd` — chunk seeding must become seed-deterministic for clients
- Godot docs: High-Level Multiplayer, `MultiplayerSpawner`, `MultiplayerSynchronizer`

## Principles & Key Decisions

- **Host simulates, clients render + send intents.** No client-side game logic
  authority anywhere — placement, damage, spending, wave logic all host-side.
  Rationale: eliminates desync classes; GDScript float determinism is not
  trustworthy enough for lockstep.
- **Transport behind one seam.** A `Net` autoload owns the `MultiplayerPeer`;
  nothing else touches ENet directly. Steam later = new peer factory only.
- **Events over state where possible.** Bullets, muzzle flashes, sfx, fire
  patches: broadcast spawn events, simulate visuals locally. Only long-lived
  gameplay state (enemies, buildings, resources) gets continuous sync.
- **Enemy sync is budget-driven**: 10–15 Hz batched transforms + client-side
  interpolation. 350 enemies × ~10 bytes × 12 Hz ≈ 40 KB/s — fine on LAN;
  interest management is a later optimization, not Phase 1.
- **Pause is redesigned, not replicated.** Research panel no longer pauses the
  world in multiplayer; P (pause) becomes host-only and pauses everyone.
- Each phase ends with the game **playable single-player AND 2-player LAN**.

## Technical Architecture

### New pieces
- `scripts/net.gd` (autoload `Net`): peer lifecycle, host/join/leave, player
  registry (`peer_id -> {name, color}`), `is_host()`, connection signals.
- Lobby UI in main menu: Host / Join(IP) / player list / start button.
- `scripts/net_sync.gd` helpers: enemy transform batching (PackedByteArray over
  unreliable channel), event broadcast helpers.
- Player scene becomes spawnable per peer (`MultiplayerSpawner`), input gated by
  `is_multiplayer_authority()`; each client keeps its own Camera2D active only
  for its player.

### State ownership
| System | Host | Clients |
|---|---|---|
| GameState (resources, research, energy, caps) | simulate + validate | replicated mirror, HUD only |
| Waves/enemies/AI/nav/aggro | simulate | interpolate transforms, play deaths |
| Power grid BFS + coverage | simulate | mirror cable/dim visuals from replicated pole links |
| Building place/sell | validate + spawn | send intent RPC, ghost stays local |
| Player movement/shooting | own player authority (client-owned input, host validates damage) | — |
| Chunk seeding (rocks/deposits) | authoritative RNG seed per chunk | regenerate deterministically from synced seed |
| Hotbar, ghost, camera, godmode | — | fully local per player |

### Integration points
- `Util.nearest_in_group("player"...)` sites → nearest of group "players"
  (aggro, repair tower, spawn centering already handle groups; audit all
  `get_first_node_in_group("player")` calls).
- Wave spawn ring centers on the **centroid of alive players**.
- Enemy `_target` picking: buildings unchanged; "the player" → nearest player.

### Security considerations
LAN co-op with trusted peers: no auth, but host still validates every spend/
placement RPC (range, cost, occupancy) — protects against desync-corrupted
intents, not adversaries. No secrets in transit. Port: single UDP (default
0451 configurable); user opens it only for internet host-without-Steam.

## Actions

### Phase 1: Net foundation + lobby
- [x] `Net` autoload: ENet host/join/disconnect, player registry, signals
- [x] Main-menu lobby: Host, Join by IP, connected player list, Start (host only)
- [x] `multiplayer.multiplayer_peer` unset ⇒ offline mode identical to today
- [x] Acceptance: 4 instances connect on localhost, see each other's names,
      host starts game, clients load `main.tscn` (Final-Phase 4-process soak)
- [x] Verify single-player unchanged; commit

Phase 1 notes: default port is 4514 (not 0451 — ports < 1024 are privileged).
Registry flow verified headless with 2 processes (host/join, name RPC, color
by join order, broadcast, disconnect cleanup); the 4-instance UI acceptance
test remains manual. Voluntary `leave()` does not emit `session_ended` —
only `connection_failed`/`server_disconnected` do.

### Phase 2: Player replication
- [x] Player scene spawned per peer via `MultiplayerSpawner`; input/aim gated by
      authority; per-peer camera; name label + tint per player
- [x] Player transform/health/light via `MultiplayerSynchronizer` (~20 Hz)
- [x] Shooting: fire events broadcast; bullets simulated locally everywhere;
      damage applied host-side only (landed with Phases 5+6: fire intents +
      PLAYER_FIRE events)
- [x] Group rename "player" → "players" + audit every lookup site (enemy aggro,
      repair tower, wave centering, harvester, build range)
- [x] Acceptance: 2 players run around, shoot, take damage, see each other lit
- [x] Verify + commit (headless verify done)

Phase 2 notes (deviations):
- Group KEPT as "player" (singular) — a rename bought nothing; instead every
  `get_first_node_in_group("player")` site was audited and converted:
  enemy fallback + mage kiting → nearest player, wave spawn ring → centroid of
  players in the group, repair tower fallback → nearest player in heal range,
  miner drill orientation → nearest player. `power_grid.covered()` already
  looped the group; harvester/build range never touch the player group.
- `MultiplayerSpawner` uses a custom `spawn_function` carrying
  `[peer_id, position]` — the auto-spawn list cannot replicate spawn position
  for client-authority nodes (client's own player materialized at (0,0)).
  Node name = peer id; `_enter_tree` derives `set_multiplayer_authority`.
- Host spawns all players only after every client RPCs scene-ready from
  `main.gd` (spawn packets sent mid scene change would be lost).
- Sync config: position/rotation/velocity ALWAYS @ 20 Hz (unreliable),
  health/dead ON_CHANGE (reliable). Light needs no sync: each instance carries
  its own LightSource; radius derives from local GameState research.
- Damage still applies on the owning peer and syncs out (each peer also still
  simulates its own enemies/buildings) — host-authoritative damage lands with
  Phase 5, fire-event broadcast with Phase 6; that checkbox stays open.
- Death: offline unchanged; online a dead player is hidden, collision-off and
  dropped from "player" (spectate/respawn = Phase 7). Team wipe: host
  broadcasts game over to all peers.
- The 2-player acceptance run stays manual; a headless 2-process smoke test
  (host+client into main.tscn, both sides assert 2 player nodes, authority,
  single camera, synced position/health) passed clean.

### Phase 3: Shared GameState
- [x] Split GameState: host mutates; `resources_changed`/`upgrades_changed`
      re-broadcast to clients (reliable RPC with full small-dict payload)
- [x] `spend`/`purchase`/`try_spend_energy` become host-validated intent RPCs;
      client HUD shows replicated values; godmode stays host-toggled (design:
      host G toggles for the room)
- [x] Research panel: no world pause in MP; purchases go through intent RPC
- [x] Acceptance: client buys research, all peers see level + resource drop;
      offline path still direct-call (no RPC overhead)
- [x] Verify + commit (headless offline + 2-process main-scene smoke test
      done)

Phase 3 notes (semantics + deviations):
- Offline is a hard early-out: `_is_client()` is false without a session, so
  every GameState call takes the exact pre-MP direct path, zero RPC overhead.
- Client mirror is OPTIMISTIC: `can_afford` checks the mirror; `spend` sends
  the intent AND deducts the mirror immediately (callers like
  build_controller expect a synchronous bool and place instantly); `purchase`
  sends one intent RPC and deducts only resources (not via `spend()`, which
  would double-count) — the level/hotbar wait for the host broadcast. The
  host revalidates every intent; `_rpc_spend`/`_rpc_purchase` mark the sync
  dirty even on reject so the corrective broadcast un-deducts a stale mirror.
- Broadcast: full `resources` + `purchased` + `godmode` via one reliable RPC,
  debounced by a dirty flag to at most once per physics frame (any
  `resources_changed`/`upgrades_changed` emit marks dirty). Clients apply and
  re-emit the local signals, so HUD/research panel/ghosts react unchanged;
  building-unlock hotbar slots are mirrored from `purchased` on apply.
- `try_spend_energy` on clients returns mirror availability WITHOUT spending
  and WITHOUT an RPC: until Phases 4-5 every peer still simulates its own
  towers locally, so only the HOST's copies may drain the shared pool
  (otherwise each attack pays once per peer). Phases 4-5 delete this branch
  together with client-side building simulation. Same reason `add_resource`
  income from client-local sim (suit reactor, client-only solar/miners,
  client-side enemy kills) flows up as intents — known pre-Phase-5 wart:
  per-peer enemy sims mean bounty income roughly scales with peer count
  until Phase 5 makes enemies host-only.
- HANDOFF -> Phase 4: building spawn authority moves host-side; placement
  stops trusting the client's optimistic `spend` (host validates cost +
  occupancy in the placement intent RPC, then spawns via MultiplayerSpawner).
- Godmode: setter in game_state.gd ignores writes on online clients (player.gd
  untouched), host toggles are broadcast with the state so costs stay free
  room-wide. Cosmetic gap: a client's GOD label only refreshes on its own
  (ignored) G press, not on sync — revisit with Phase 7 UX.
- `energy_cap_changed()` skips the clamp on clients (their battery set is
  local-only until Phase 4; the cap readout is HUD-cosmetic, host owns energy).
- Research panel opens without pausing when `Net.is_online()` (hud.gd
  toggle_research); research_panel._close()'s `paused = false` is harmless
  online. P-pause stays local-only until Phase 7 (host-only pause).
- `reset()` needs no gating: it runs on every peer at scene load with
  identical defaults; the host's reset marks dirty and the broadcast
  reconverges mirrors. Online restart flow itself is Phase 7.
- Smoke test (scratchpad, 2 headless processes, real main.tscn): host banks
  500 scrap -> client mirror sees it, client purchases walls_1 + spends 100 +
  bounties 100 + try_spend_energy no-op -> both sides converge on scrap 473,
  walls_1 lvl 1, wall in hotbar slot 2. Offline
  `godot --headless res://scenes/main.tscn --quit-after 300` clean.

### Phase 4: Buildings + world gen
- [x] Placement/sell → intent RPC (host validates cost/range/occupancy, spawns);
      buildings replicated via `MultiplayerSpawner`; `facing` in spawn data
- [x] Power grid host-side; pole link list replicated → clients draw cables/dim
      states; NavGrid stays host-only (DEVIATED — see notes: grids run on all
      peers off the replicated building set instead)
- [x] Chunk seeding: per-chunk RNG seed derived from a synced run seed; clients
      generate rocks/deposits/clusters deterministically; miner placement RPC
- [x] Acceptance: client drag-paints walls, sees same rocks/minerals as host,
      power bolt indicators match on both screens (headless smoke test below;
      on-screen 2-player acceptance stays manual)
- [x] Verify + commit (headless offline + 2-process smoke test done)

Phase 4 notes (design + deviations):
- Building replication: a second `MultiplayerSpawner` (`BuildingSpawner`) with
  spawn container `Main/Buildings`; custom spawn_function carries
  `[scene_id, pos, facing]` so every peer constructs the node identically and
  plays the place sfx. Online the host adds buildings ONLY under Buildings;
  offline keeps the old direct `add_child(current_scene)` path untouched.
  Host `queue_free` (death/sell) despawns everywhere; sell debris/sfx go out
  as a small event RPC since despawns are silent.
- Intent RPCs live on `build_controller.gd` — it exists on every peer under
  the same player node path, so the host validates a client's intent on its
  copy of that client's controller: range from the puppet's synced position,
  occupancy via the host's own physics query, cost via the authoritative
  GameState; sender must match the controller's authority. The client keeps
  local `_placement_valid` for the ghost + optimistic drag UX.
- Miners replicate via a position-keyed spawn-event RPC, NOT the spawner:
  they are children of their deposit, and generated deposits have
  order-dependent node names (paths differ per peer) — deterministic world
  gen makes the deposit POSITION the only path-safe identity. Host resolves
  nearest deposit within 16px, pays, attaches, broadcasts.
- Building HP is host-owned: gnaw sim + `take_damage`/`heal` no-op on online
  clients (their local enemy/tower sims must not double-damage); the host
  broadcasts HP per damage/heal event via a reliable per-building RPC
  (event-driven ≈ a few Hz per gnawed building — no synchronizer needed).
  Clients play destruction FX at HP 0; the free arrives as the despawn. The
  player heal beam is the one client-authoritative heal: routed through
  `building.request_heal()` → host RPC (player.gd touched for this one line).
- Grids DEVIATION: PowerGrid + NavGrid keep running on every peer, derived
  from the local (now replicated, hence matching) scene tree — clients still
  simulate towers/enemies until Phase 5, so host-only grids would starve
  them. Cable visuals/dim states derive locally for free; no link-list
  replication needed. After Phase 5 the client NavGrid (and the client
  tower/enemy sims feeding on it) can be dropped.
- World gen determinism: host rolls `run_seed` (`randi()`) in
  `Net.start_game()`; the start RPC carries it. Starter gen runs off
  `seed(run_seed)`; each chunk reseeds the GLOBAL rng with
  `hash(run_seed ^ hash(chunk))` at the top of `_seed_chunk` — all chunk gen
  (incl. rock generate/_ready jitter + facets) is synchronous inside that
  call, so per-chunk streams are identical on every peer regardless of
  trigger order; rock.gd needed no plumbing. Side effect: gameplay randf
  shares the global rng and gets reseeded on chunk gen — harmless.
  Offline rolls its own run seed (behavior unchanged).
- Live-player clearance in chunk gen was replaced by a deterministic spawn-
  fan check (`PLAYER_SPAWN` + up to MAX_PLAYERS fan positions): live puppet
  positions would desync generation. Safe because a chunk always seeds while
  every player is ≥ 1 full chunk (1024px) away — except the initial ring
  around the spawn, which the fan points cover exactly.
- Producer gating (`Net.is_host()` is true offline, so offline is untouched):
  solar/intake/miner/harvester bank resources host-only; command centers on
  clients train VISUAL-only drones (no spend — mirror affordability check)
  so both screens show the same base; intake stations predict burn FX from
  the mirror. Player suit reactor already runs only in the authority branch,
  and client `add_resource` flows up as the Phase 3 intent — counted once,
  verified unchanged. Known pre-Phase-5 warts that remain: client tower/
  heal-beam energy is effectively free (mirror check, no spend) and per-peer
  enemy sims still multiply bounty income — both die with Phase 5.
  Deposits are infinite (`extract` always yields), so client-side visual
  extraction causes no depletion desync.
- Smoke test (2 headless processes, real main.tscn, temp in-project driver):
  host banks 500 scrap → client mirror sees it → client places a wall via
  the real `_try_place_building_at` path → wall node exists on BOTH peers at
  the same position under Buildings; sorted dumps of all deposit positions
  (42) and rock anchors+bounds (7) are byte-identical across peers. Offline
  `godot --headless res://scenes/main.tscn --quit-after 400` clean.

### Phase 5: Enemy horde sync (hardest)
- [x] Enemies host-simulated; spawn/death via `MultiplayerSpawner` + death events
- [x] Batched transform sync: one unreliable packet per tick (12 Hz) with
      id/pos/rot; client-side interpolation buffer (~120 ms)
- [x] HUD signals (`wave_started`, `remaining_changed`, `intermission_started`,
      score) re-broadcast; wave ring centers on player centroid
- [x] Bandwidth profile at MAX_ALIVE 350; tune cap / tick rate if needed
      (measured 13 B/enemy exactly: 350 ⇒ 4552 B/packet ⇒ ~55 KB/s @ 12 Hz)
- [x] Acceptance: wave 20 horde on 2 clients — smooth movement, counters match,
      no runaway bandwidth (headless 2-process smoke below; the on-screen
      wave-20 2-player run stays manual)
- [x] Verify + commit (headless offline + 2-process smoke test done)

Phase 5 notes (design + deviations):
- Spawn replication: `Enemies` container + `EnemySpawner` in main.tscn; the
  wave manager owns the spawn_function. Payload `[id, kind, pos, overrides]`
  — overrides is a small dict (`max_health`, `speed_delta`, `scrap_value`)
  holding exactly the per-wave stat tweaks `_spawn_kind` used to poke into
  the instance, so every peer rebuilds the node identically. Node name =
  "E<id>" (monotonic counter), also stored as `enemy.sync_id` — the batcher
  keys packets on it. Offline spawns through the same spawner path (spawn()
  works on the offline peer; player spawner precedent), so there is ONE code
  path. `_register` (alive count, `died` hookup) runs host-only inside the
  spawn_function; the wave LOOP (`_start_next_wave_after_delay`) is gated on
  `Net.is_host()`.
- Draw order: enemies were previously appended to Main last (above runtime
  rocks/effects). The container would put them UNDER later-appended rocks —
  flying wasps vanishing under silhouettes — so `Enemies` carries
  `z_index = 2`. Side effect: z-0 FX (blood, impacts, bullets) now render
  under enemy sprites; subtle, revisit with Phase 6 FX if it reads wrong.
- Summons: mage/boss AI only runs on the host (puppet gate), and their
  births now route through `wave_manager.spawn_summon(pos, hp, speed_delta)`
  → the replicated spawner path; `register_enemy` is gone. Their local
  `_summons`/`_brood` caps keep working off the returned host-side node.
- `enemy_sync.gd` (Main/EnemySync): host packs alive enemies at 12 Hz into
  `[u16 count, per enemy: u32 sync_id, f32 x, f32 y, u8 rot*255/TAU]` and
  sends ONE unreliable rpc. Clients cache sync_id→node (one rebuild per
  packet on a miss — spawn packet may still be in flight), snap when >200 px
  (host teleports), otherwise exponentially smooth in `_process`
  (rate 12/s ≈ 120 ms settle). Offline both loops are disabled. Death FX:
  the host broadcasts a tiny reliable `_rpc_death(pos, dir)` (blood + sfx on
  clients) since spawner despawns are silent.
- Puppet gating in enemy.gd: `_is_puppet()` = online non-host. Gates the top
  of `_physics_process` (all variants share it — wasp/drone/mage only
  override `_behave`, which is unreachable on puppets), `take_damage`,
  `heal`, and the AI half of `_ready`; the puppet's CollisionShape2D is
  `set_deferred`-disabled (host resolves physics). Boss overrides
  `_physics_process`: bar tracking runs, brood logic is gated. Gap: enemy HP
  isn't replicated, so the boss health bar sits full on clients — Phase 6.
- Offscreen-straggler relocate: the host's viewport means nothing for remote
  players, so online it relocates on distance to the NEAREST player instead
  (>900 px ≈ viewport half-diagonal, same 5 s timer + embed re-roll);
  offline path untouched. Clients snap via the 200 px rule.
- Wave/HUD signals: host wave_manager re-broadcasts `wave_started` (carries
  `wave` for boss scaling/game-over text) and `intermission_started` as
  reliable RPCs; `remaining_changed` + kill points batch into at most one
  `_rpc_wave_events(counts, points)` per physics frame (spawn bursts and
  grenade multi-kills would otherwise spam). Clients re-emit the local
  signals — hud.gd and main.gd (score) needed zero changes. The FIRST
  intermission is mirrored locally on clients (the host's RPC can race the
  client scene load); later ones arrive via RPC.
- Towers on clients: mg/grenade/tesla/flame/aa/repair gate everything after
  `super._physics_process` (visual shells; fire events land in Phase 6), so
  no client-side bullets/globs/shells/grenades/fire patches exist at all —
  their damage paths needed no extra gating. Searchlight keeps its sweep on
  clients (pure visual; covers()/vision only matter host-side) but skips the
  energy sim — the client beam may drift from the host's until Phase 6.
  Phase 3/4 warts closed: client towers no longer read the energy mirror,
  and bounty income is counted once (enemy kills exist only on the host).
- Player shooting online (client): `_shoot` sends a fire intent
  `_rpc_fire(pos, rot, dmg, crit)` to the host, which validates the sender
  against the node authority, clamps dmg to the shared-research ceiling and
  spawns the authoritative bullet; the client spawns a cosmetic tracer
  (collision mask minus the enemy bit — puppets have no collision anyway;
  walls still stop it). Other clients see no remote-player bullets until
  Phase 6 fire events. Host/offline `_shoot` unchanged.
- Player damage: host-simulated enemies melee player puppets ON the host;
  health stays authority-owned (Phase 2), so host `take_damage` forwards via
  `_rpc_take_damage.rpc_id(authority)` (guarded: sender must be peer 1;
  skipped when the peer already left the registry — lingering puppets until
  Phase 7 despawn handling). The owning peer applies and the synchronizer
  mirrors it back.
- NavGrid/PowerGrid still run on every peer: client enemy/tower sim is gone
  so the client NavGrid is now unused, but it is cheap and harmless —
  ripping it out is a later cleanup, not Phase 5.
- Smoke test (2 headless processes, real main.tscn, temp root-probe driver):
  host force-starts wave 1 → client sees 28 enemies appear under Enemies
  with matching names; E1 moves ~240 px over 2 s on BOTH peers
  (interpolation live); puppet CollisionShape2D disabled; client fires 5
  intents → authoritative bullets spawn on the host and kill grunts;
  host-side kill + bullet kills despawn on the client with counts converging
  (each side count == its remaining sum, wave counter matches); zero
  errors/warnings in either log. Measured packet: 366 B @ 28 enemies
  (2 + 13/enemy ⇒ 1.3 KB @ 100, 4.5 KB @ 350 ≈ 55 KB/s — within the
  <100 KB/s budget, no cap/tick tuning needed). Offline: driver-forced wave
  spawns/moves/kills identically plus clean
  `godot --headless res://scenes/main.tscn --quit-after 400`.

### Phase 6: Combat effects + audio
- [x] Tower fire / tesla bolts / flame globs / fire patches / flak bursts as
      broadcast events, visuals + sfx local per client
- [x] Damage numbers/health bars from replicated health only (no damage
      numbers exist in the game — skipped; boss HP bar now replicated at 1 Hz)
- [x] Acceptance: both screens show same battle, no event spam warnings
      (headless 2-process smoke below; on-screen 2-player run stays manual)
- [x] Verify + commit (headless offline + 2-process smoke test done)

Phase 6 notes (design + deviations):
- Event bus: NEW `scripts/fx_events.gd` (Main/FxEvents, EnemySync pattern,
  group "fx_events", `class_name FxEvents`). The host queues compact events
  at the source and flushes once per physics frame as ONE reliable RPC per
  peer — bursts always batch, not only past a threshold. Emit helpers are
  static (`FxEvents.tower_fire(self, ...)`) and gate on a bus `_active` flag
  (online host only) instead of touching Net from static context; offline
  every emit is a group lookup + early-out, zero behavior change. Per-event
  `except` peer skips the client whose own local visual already exists.
- Event catalog (host emits in the real action's code path; clients replay
  cosmetics + sfx at the host-side volumes):
  TOWER_FIRE(path, variant, from, angle) — MG; variant 0/1 = heavy/normal
  shot (head snap, muzzle flash, sfx, collisionless tracer via bullet.tscn
  with damage 0 + enemy mask bit dropped), variant 2 = burst-tail sfx only.
  AA_FIRE(path, from, angle, burst_point) — head snap + flash + sfx + a
  cosmetic flak shell flying the host's route (frees silently at the fuse).
  TESLA_BOLT(points) — bolt drawing extracted from tesla_tower into
  `Effects.tesla_bolts()` (+ static cached light texture); host visual and
  client replay call the same helper.
  FLAME_GLOB(path, from, to) — cosmetic FireGlob (`cosmetic` flag skips the
  splash; its fire patch spawns with damage ticking disabled — patch visual,
  light and light_sources join identical, cosmetic skips damage ONLY since
  client vision feeds nothing while towers idle). Patch arrays are keyed per
  source tower on the bus so cap/rekindle match the host. Also sets the
  tower's nozzle flare + rotation (flare tick moved above the puppet gate).
  FLAK_BURST(pos) — burst scene + sfx, emitted by the host shell at fuse.
  GRENADE_LOB(from, to) — cosmetic grenade (`cosmetic` flag skips damage;
  arc + explosion FX/sfx at landing play locally).
  REPAIR_BEAM(path, target_pos) — replay calls the client tower's
  `_show_beam` (beam fade timer moved above the puppet gate).
  HEAL_BEAM(peer_id, building_path) — DEVIATION from start/stop: emitted per
  0.5 s heal tick from building.request_heal/_rpc_heal (host side), replay
  keeps one Line2D per healing peer that follows the synced player/target
  for 0.7 s per refresh — self-healing on packet loss, no stuck beams. The
  host draws remote healers' beams via the same `show_heal_beam` path
  (events replay on clients only); the healing peer is excluded.
  PLAYER_FIRE(from, angle, crit) — closes the Phase 5 gap: host's own shots
  broadcast to all clients; client fire intents now also play flash/sfx on
  the host in `_rpc_fire` and relay to the other clients (shooter excluded).
- No double-FX: all replay is client-only (`call_remote` + host never
  receives its own batch); enemy death FX (Phase 5 RPC) verified same
  pattern. Searchlight sweep drift stays (pure cosmetic, not evented).
- Boss/mage summon casts need no event: births already replicate through the
  spawner; there is no host-side cast FX to mirror. Boss HP bar: 1 Hz
  reliable `_rpc_boss_health` on boss_broodmother (node paths match via the
  spawner), puppet clamps + updates its bar.
- Smoke test (2 headless processes, real main.tscn, temp drivers): host
  starts wave 1 + summons runners beside two spawned towers; client replayed
  22 TOWER_FIRE + 7 TESLA_BOLT events (debug_replayed counter on the bus),
  19 blood-splat death replays, wave counter mirrored, zero errors/warnings
  in either log. Offline `--quit-after 400` clean before and after.

### Phase 7: Co-op UX rules
- [x] Death/respawn: dead player enters spectate (camera follows a living
      teammate, wheel cycles targets); respawns at the next intermission start
      beside a living teammate / the Command Center; team wipe → game over for
      all; restart = host vote
- [x] Spectator UI: "Respawning next wave" banner + wave countdown reuse
- [x] Host-only pause; Esc panels local; disconnect handling (client drop =
      despawn player; host drop = session ends with message)
- [x] Intermission drop-in: late joiner spawns during next intermission
- [x] Acceptance: player dies mid-wave, spectates, returns at intermission;
      team wipe ends run for all; client rejoin works during intermission
      (headless 4-scenario 2-process smoke below; on-screen run stays manual)
- [x] Verify + commit (headless offline + 2-process smoke tests done)

Phase 7 notes (design + deviations):
- Spectate: the dead player's node stays hidden/inert (Phase 2) but on the
  authority peer it now lerps its global_position after a living teammate
  every physics frame, so the player's own smoothed Camera2D just works — no
  reparenting, no camera hand-off. Wheel cycles targets via player `_input`
  (runs before the hotbar's `_unhandled_input`; the event is consumed so
  slots don't cycle while dead). Leaver/dead targets re-pick automatically.
  All action gating was already in place: `if dead: return` sits above
  input, shooting, heal beam, suit reactor and `_build.tick` — nothing new
  to gate. HUD banner "Respawning next wave — following <name>" is a
  runtime `duplicate()` of the WaveTimer label placed right below it.
- Respawn: main.gd hooks the host's `intermission_started` → every dead
  player revives beside the first living one (+56 px per corpse; a living
  teammate always exists — a wipe would have ended the run). Host calls
  `player.revive_at(pos)`: own player directly, remote via
  `_rpc_revive.rpc_id(authority)` (sender-1-guarded); the owner repositions,
  refills health, clears `dead` — the Phase 2 synchronizer mirrors all
  three, and the `dead` setter now has an `_apply_revive()` branch that
  un-hides, re-enables collision and rejoins the "player" group on every
  peer. Phase 3 GOD-label gap closed: `_rpc_sync_state` counts a godmode
  flip as `upgrades_differ`, and the player refreshes the label in
  `_on_upgrades_changed`.
- Team wipe / restart vote: `_rpc_game_over` verified pausing all peers with
  the shared score/wave. The game-over hint is role-aware (host "restart for
  everyone", client "waiting for the host"). Host R → `_rpc_restart(seed)`
  (call_local): host reloads immediately; clients pause + wait 0.3 s first
  so the host teardown's despawn packets land in the OLD tree (without the
  grace beat both directions error: client-side ERR_UNAUTHORIZED despawns,
  host-side stale sync spam — both observed then eliminated). A fresh
  `randi()` seed rides the RPC; the kept-alive session re-runs the Phase 2
  scene-ready handshake and respawns everyone.
- Host-only pause: HUD P online routes to `main._rpc_set_paused(bool)`
  (call_local) — engine pause is per-peer, so the flag replicates; client P
  is ignored and the client's panel hint reads "Host paused the game".
  RPC delivery is not gated by pause, so the host can always unpause.
- Disconnects: host prunes leavers on `player_list_changed` (queue_free →
  spawner despawns everywhere) and re-checks team wipe among the remaining
  players (deferred; a leaver may have been the last one alive). Host drop:
  main.gd hooks `session_ended` → pause + game-over panel reskinned as a
  DISCONNECTED modal → R returns to the main menu.
- Late join (full, via SceneMultiplayer auth): the engine sends spawner
  catch-up state at `peer_connected`, so a joiner must already have
  main.tscn loaded when the connection completes. Net now sets
  `auth_callback` (+ `auth_timeout = 0`) and holds joiners in the auth
  phase: host sends {"wait"} while `game_running` (client lobby shows "Game
  in progress — joining at next intermission"), then at intermission
  (`Net.release_late_joiners()`, called from the same main.gd hook)
  {"late", seed}; the client loads main.tscn FIRST, then acks + completes
  auth. On `peer_connected` the spawners replicate every live player/
  building/enemy into the matching tree — verified working for custom
  spawn_function spawners. After the client registers, `spawn_late_joiner`
  spawns its player beside a living teammate and catches up the rest:
  GameState dirty-flag broadcast, score RPC, wave counter + remaining
  counts, and a 1 s-deferred miner replay (miners are position-keyed
  events, not spawner children; the delay lets the joiner's chunk gen run).
  Known cosmetic gaps: pre-damaged building HP reads full until the next
  damage event; a joiner held during the pre-wave-1 intermission waits
  until after wave 1 (release fires on intermission start only).
- Pre-game joins run through the same auth handshake (host {"late": false},
  client acks immediately) — one extra round trip, no behavior change.
- Smoke tests (2 headless processes each, real main.tscn, temp in-project
  driver, all PASS with zero errors/warnings): (A) client suicides →
  puppet dead+hidden+degrouped on host, client spectates (position converges
  onto the host player), forced intermission revives both sides at full
  health, host pause/unpause reflected on the client, restart RPC reloads
  both peers into a fresh handshake with the new seed. (B) host runs solo
  with walls+miner+wave-1 horde; late joiner is held with the wait status,
  released at intermission, and receives players/buildings/enemies via
  spawner catch-up plus economy/wave/miner replay; enemy interpolation
  verified live. (C) abrupt client drop → registry pruned + player
  despawned. (D) host drop → client modal → R → main menu, unpaused.
  Offline `godot --headless res://scenes/main.tscn --quit-after 400` clean.

### Final Phase: Hardening + docs
- [x] 4-player LAN soak test through wave 30+ incl. boss; desync checklist
      (resource totals, remaining counter, building sets match) — DEVIATED:
      soak ran through wave 10 (incl. the wave-10 boss) per the tightened
      scope; desync checks passed byte-identical on all 4 peers (see notes)
- [x] Perf pass host-side (350 enemies + 4 players); README + controls update
- [x] Steam-readiness note: document the `Net` seam for SteamMultiplayerPeer
      (`documentation/reference/multiplayer_net_seam.md`)
- [x] Move this document to `documentation/planning/completed/`

Final Phase notes (soak findings + fixes):
- Soak harness: 4 headless processes (host + 2 clients + 1 LATE client)
  driving the real main.tscn — accelerated waves (1.5 s intermissions,
  0.05 s spawn ticks, driver kill-sweeps), host bankroll + research, walls/
  MG tower/miner placed from TWO different clients, client research
  purchases, client self-kill mid-wave-4 (spectate verified, intermission
  revive verified), 3rd client late-joining mid-run (held at auth, released
  at intermission, full catch-up), replicated host pause toggled at every
  milestone. At waves 3/7/10 the host pauses the room and every peer prints
  a state digest: resources, purchased levels, score, player count, alive
  enemies, miner count, building positions + HP sum. All digests were
  BYTE-IDENTICAL across all peers at all three milestones (enemy counts
  exact at 72/154/93 — no tolerance needed).
- BUG (found + fixed): `_rpc_spawn_miner`/`_rpc_sell_fx` on
  build_controller.gd were `@rpc("authority")` — but that node's authority
  is its OWNING PEER, so host broadcasts from a CLIENT-owned controller
  (client-placed miner / client-sold building) were rejected by every
  receiver: miners silently never replicated unless the host placed them.
  Now `any_peer` + sender-must-be-host guard.
- BUG (found + fixed): the 12 Hz enemy packet blows the ENet MTU (1392 B)
  above ~107 enemies — the engine warns of elevated loss for oversize
  unreliable packets. enemy_sync now chunks at 100 enemies/packet (1302 B;
  350 ⇒ 4 packets/tick). The pack loop also reuses one scratch buffer
  (perf pass) and fx_events flushes exclusion-free batches as a single
  broadcast instead of building one array per peer.
- FIX: GameState's dirty-flag broadcast now runs with process_mode ALWAYS
  (and rate accounting explicitly freezes while paused) — before, a host
  research purchase made from the always-processing HUD during a host pause
  left client mirrors stale until unpause.
- Phase 7 gap closed: on late join the host now sends one batched
  `_rpc_sync_building_hp` with `[health, max_health]` for every pre-damaged
  building (spawner catch-up rebuilds them at full HP). Verified in the
  soak: the late joiner's building HP sum matched the host exactly.
- Bandwidth (measured via ENet host statistics, 2 s sampling): host peak
  94.5 KB/s total sent at 154 alive enemies + 3 clients (~32 KB/s per
  client), ~350 packets/s peak; idle intermission ≈ 4 KB/s. Extrapolated
  350-enemy worst case ≈ 55 KB/s per client — within the <100 KB/s budget.
- Accepted gaps documented in the reference doc: client searchlight sweep
  drift (cosmetic, vision is host-side), client NavGrid left running
  (cheap, keeps peer trees identical), late-joiner max HP of UNdamaged
  buildings derived from a not-yet-synced mirror (cosmetic), pre-wave-1
  late joiners released only after wave 1, boss HP bar at 1 Hz.
- Final verify: offline `godot --headless res://scenes/main.tscn
  --quit-after 400` clean; 4-process soak PASS end-to-end with zero
  script errors/warnings in all four logs.

## Appendix

### Technical details
- Enemy packet: `[u16 count, (u32 id, f32 x, f32 y, u8 rot)]` ≈ 13 B/enemy;
  350 enemies ≈ 4.5 KB/packet, 12 Hz ≈ 55 KB/s worst case, LAN-trivial.
- Reliable channel: spawns, deaths, state dicts. Unreliable: transforms only.
- Run seed: host `randi()` at start, sent in start RPC; chunk seed =
  `hash(run_seed, chunk_coords)`.

### Decision documentation
- Host-authoritative over lockstep: GDScript float nondeterminism + dynamic
  node counts make lockstep fragile; bandwidth is affordable instead.
- ENet before Steam: identical high-level API; Steam adds NAT traversal +
  invites later for ~1 day via GodotSteam.
- Shared economy over per-player: matches single shared base; avoids 4-way
  UI/balance fork.

### Estimate
Roughly 2–3 weeks focused work; Phase 5 carries the most risk.

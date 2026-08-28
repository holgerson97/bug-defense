extends Node
## Phase 5: enemy transform batcher — one node instead of 350 synchronizers.
## Host packs every alive enemy into unreliable packets at 12 Hz (chunked at
## 100 enemies to stay under the ENet MTU):
## [u16 count, per enemy: u32 sync_id, f32 x, f32 y, u8 rot/TAU*255] = 13 B
## per enemy (350 enemies ~ 4 packets ~ 55 KB/s). Clients look puppets up
## by sync_id and exponentially smooth toward the latest sample in _process.
## Death FX ride a tiny reliable event RPC (spawner despawns are silent).
## Offline both loops are disabled: zero overhead.

const TICK := 1.0 / 12.0
const STRIDE := 13
## Chunking: >107 enemies would push one packet past the ENet MTU (1392 B) —
## unreliable oversize packets get fragmented with extra loss (engine warns).
## 100/packet = 1302 B; a 350 horde ships as 4 packets/tick (soak-test find).
const MAX_PER_PACKET := 100
const SMOOTH_RATE := 12.0   ## exp smoothing toward target (~120 ms settle)
const SNAP_DIST := 200.0    ## host teleports (offscreen relocate) snap, no glide

var _accum: float = 0.0
## Reused pack scratch (host): grows to the high-water mark once instead of
## reallocating 4.5 KB every tick at a full 350-enemy horde.
var _buf := PackedByteArray()
var _by_id: Dictionary = {}     ## sync_id -> puppet node (client cache)
## sync_id -> [node, target_pos, target_rot]; nodes despawn via the spawner,
## stale entries are swept during the smoothing loop.
var _targets: Dictionary = {}

@onready var _enemies: Node2D = $"../Enemies"

func _ready() -> void:
	add_to_group("enemy_sync")
	set_physics_process(Net.is_online() and Net.is_host())
	set_process(Net.is_online() and not Net.is_host())

## Host: send the alive set as MTU-sized batched packets, once per tick.
func _physics_process(delta: float) -> void:
	_accum += delta
	if _accum < TICK:
		return
	_accum = 0.0
	var alive: Array = []
	for enemy in _enemies.get_children():
		if not enemy.is_queued_for_deletion():
			alive.append(enemy)
	var start := 0
	while start < alive.size():
		var count := mini(MAX_PER_PACKET, alive.size() - start)
		_rpc_transforms.rpc(_pack(alive, start, count))
		start += count

func _pack(alive: Array, start: int, count: int) -> PackedByteArray:
	var needed := 2 + count * STRIDE
	if _buf.size() < needed:
		_buf.resize(needed)
	var off := 2
	for i in count:
		var enemy = alive[start + i]
		_buf.encode_u32(off, enemy.sync_id)
		_buf.encode_float(off + 4, enemy.global_position.x)
		_buf.encode_float(off + 8, enemy.global_position.y)
		_buf.encode_u8(off + 12, int(wrapf(enemy.rotation, 0.0, TAU) / TAU * 255.0))
		off += STRIDE
	_buf.encode_u16(0, count)
	## slice() copies exactly the sent size; the scratch keeps its capacity.
	return _buf.slice(0, needed)

## Client: store targets; unknown ids trigger one cache rebuild per packet
## (spawn packet may still be in flight — then just skip the id this tick).
@rpc("authority", "call_remote", "unreliable")
func _rpc_transforms(buf: PackedByteArray) -> void:
	if buf.size() < 2:
		return
	var count := buf.decode_u16(0)
	if buf.size() < 2 + count * STRIDE:
		return
	var rebuilt := false
	var off := 2
	for i in count:
		var id := buf.decode_u32(off)
		var pos := Vector2(buf.decode_float(off + 4), buf.decode_float(off + 8))
		var rot := buf.decode_u8(off + 12) / 255.0 * TAU
		off += STRIDE
		var node = _by_id.get(id)
		if node == null or not is_instance_valid(node):
			if not rebuilt:
				_rebuild_cache()
				rebuilt = true
			node = _by_id.get(id)
			if node == null:
				continue
		if not _targets.has(id) or node.global_position.distance_to(pos) > SNAP_DIST:
			node.global_position = pos
			node.rotation = rot
		_targets[id] = [node, pos, rot]

func _rebuild_cache() -> void:
	_by_id.clear()
	for enemy in _enemies.get_children():
		_by_id[enemy.sync_id] = enemy

## Client: smooth every puppet toward its latest sample.
func _process(delta: float) -> void:
	var alpha := 1.0 - exp(-SMOOTH_RATE * delta)
	var stale: Array = []
	for id in _targets:
		var t: Array = _targets[id]
		var node = t[0]
		if not is_instance_valid(node):
			stale.append(id)
			continue
		node.global_position = node.global_position.lerp(t[1], alpha)
		node.rotation = lerp_angle(node.rotation, t[2], alpha)
	for id in stale:
		_targets.erase(id)
		_by_id.erase(id)

## Host -> clients: death feedback (blood + sfx) at the death position; the
## node itself despawns via the spawner without playing its local FX path.
func broadcast_death(pos: Vector2, dir: Vector2) -> void:
	if Net.is_online() and Net.is_host():
		_rpc_death.rpc(pos, dir)

@rpc("authority", "call_remote", "reliable")
func _rpc_death(pos: Vector2, dir: Vector2) -> void:
	Effects.blood_death(self, pos, dir)
	Sfx.play("enemy_die", pos, -4.0)

extends Node
## Autoload (registered FIRST, before GameState): loads res://balance.json once
## and serves gameplay numbers by slash path ("towers/mg_tower/interval").
## Every consumer passes its built-in value as the fallback, so a missing file,
## a malformed file or a missing key silently keeps today's behavior.

const BALANCE_PATH := "res://balance.json"

var _data: Dictionary = {}

func _init() -> void:
	_load()

func _load() -> void:
	if not FileAccess.file_exists(BALANCE_PATH):
		push_warning("Balance: %s not found - using built-in defaults." % BALANCE_PATH)
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BALANCE_PATH))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_warning("Balance: %s is malformed - using built-in defaults." % BALANCE_PATH)

## Walk the nested dict along the slash path; null when any segment is absent.
func _lookup(path: String):
	var node = _data
	for part in path.split("/"):
		if node is Dictionary and node.has(part):
			node = node[part]
		else:
			return null
	return node

func num(path: String, fallback: float) -> float:
	var v = _lookup(path)
	return float(v) if (v is float or v is int) else fallback

func inum(path: String, fallback: int) -> int:
	var v = _lookup(path)
	return int(v) if (v is float or v is int) else fallback

func dict(path: String, fallback: Dictionary) -> Dictionary:
	var v = _lookup(path)
	return v if v is Dictionary else fallback

## Sub-tree accessor; {} when absent (callers .get with their own defaults).
func section(path: String) -> Dictionary:
	return dict(path, {})

## Costs live as int dicts in code ("crystal": 6); JSON numbers parse as
## floats, so coerce every value back to int to keep resource math integral.
func cost_dict(path: String, fallback: Dictionary) -> Dictionary:
	var v = _lookup(path)
	if v is not Dictionary:
		return fallback
	var out := {}
	for kind in v:
		if v[kind] is float or v[kind] is int:
			out[kind] = int(v[kind])
	return out

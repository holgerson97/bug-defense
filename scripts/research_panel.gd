extends Control
## Research tree: branch columns, upgrades placed by tier (requires-depth),
## with connector lines drawn behind the buttons.

const BUTTON_SIZE := Vector2(200, 70)
const LINE_OWNED := Color(0.3, 0.9, 0.4, 0.9)
const LINE_LOCKED := Color(0.5, 0.5, 0.5, 0.35)

var _buttons: Dictionary = {}

@onready var _resources_label: Label = $Center/Panel/Margin/VBox/ResourcesLabel
@onready var _branches: HBoxContainer = $Center/Panel/Margin/VBox/Branches
@onready var _lines: Control = $Lines

func _ready() -> void:
	_build_tree()
	_lines.draw.connect(_draw_lines)
	GameState.resources_changed.connect(_on_resources_changed)
	GameState.upgrades_changed.connect(_refresh)
	visibility_changed.connect(_refresh)
	$Center/Panel/Margin/VBox/CloseButton.pressed.connect(_close)
	_refresh()

func _close() -> void:
	visible = false
	get_tree().paused = false

func _on_resources_changed(_resources: Dictionary) -> void:
	_refresh()

func _cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for kind in cost:
		parts.append("%d %s" % [cost[kind], kind])
	return ", ".join(parts)

## Requires-depth: 0 for roots, 1 + max prerequisite tier otherwise.
func _tier(id: String) -> int:
	var tier := 0
	for req in GameState.UPGRADES[id]["requires"]:
		tier = maxi(tier, _tier(req) + 1)
	return tier

func _build_tree() -> void:
	var max_tier := 0
	var tiers := {}
	for id in GameState.UPGRADES:
		tiers[id] = _tier(id)
		max_tier = maxi(max_tier, tiers[id])
	# Branch columns (definition order), one centered row per tier so tiers
	# line up across branches and leave room for the connector lines.
	var branch_rows := {}
	for id in GameState.UPGRADES:
		var up: Dictionary = GameState.UPGRADES[id]
		var branch: String = up["branch"]
		if not branch_rows.has(branch):
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 26)
			var title := Label.new()
			title.text = branch
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_font_size_override("font_size", 24)
			col.add_child(title)
			var rows: Array = []
			for t in max_tier + 1:
				var row := HBoxContainer.new()
				row.alignment = BoxContainer.ALIGNMENT_CENTER
				row.add_theme_constant_override("separation", 12)
				row.custom_minimum_size = Vector2(0, BUTTON_SIZE.y)
				col.add_child(row)
				rows.append(row)
			_branches.add_child(col)
			branch_rows[branch] = rows
		var btn := Button.new()
		btn.custom_minimum_size = BUTTON_SIZE
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_upgrade_pressed.bind(id))
		branch_rows[branch][tiers[id]].add_child(btn)
		_buttons[id] = btn

func _on_upgrade_pressed(id: String) -> void:
	GameState.purchase(id)

func _refresh() -> void:
	_resources_label.text = "Scrap: %d   Crystal: %d" % [GameState.resources.get("scrap", 0), GameState.resources.get("crystal", 0)]
	for id in _buttons:
		var up: Dictionary = GameState.UPGRADES[id]
		var btn: Button = _buttons[id]
		if GameState.is_purchased(id):
			btn.text = "%s\nOWNED" % up["name"]
			btn.disabled = true
		elif not GameState.is_unlocked(id):
			btn.text = "%s\nLOCKED" % up["name"]
			btn.disabled = true
		else:
			btn.text = "%s\n%s\n%s" % [up["name"], up["desc"], _cost_text(up["cost"])]
			btn.disabled = not GameState.can_purchase(id)
	# Redraw the connectors after the containers have laid the buttons out.
	await get_tree().process_frame
	_lines.queue_redraw()

func _draw_lines() -> void:
	if not visible:
		return
	for id in _buttons:
		var btn: Button = _buttons[id]
		for req in GameState.UPGRADES[id]["requires"]:
			if not _buttons.has(req):
				continue
			var req_btn: Button = _buttons[req]
			var from: Vector2 = req_btn.global_position + Vector2(req_btn.size.x / 2.0, req_btn.size.y) - _lines.global_position
			var to: Vector2 = btn.global_position + Vector2(btn.size.x / 2.0, 0) - _lines.global_position
			var color := LINE_OWNED if GameState.is_purchased(req) else LINE_LOCKED
			_lines.draw_line(from, to, color, 3.0)

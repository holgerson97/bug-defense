extends Control

var _buttons: Dictionary = {}

@onready var _resources_label: Label = $Center/Panel/Margin/VBox/ResourcesLabel
@onready var _branches: HBoxContainer = $Center/Panel/Margin/VBox/Branches

func _ready() -> void:
	_build_tree()
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

func _build_tree() -> void:
	# Branch columns, derived from upgrade definition order.
	var columns := {}
	for id in GameState.UPGRADES:
		var up: Dictionary = GameState.UPGRADES[id]
		var branch: String = up["branch"]
		if not columns.has(branch):
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 8)
			var title := Label.new()
			title.text = branch
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_font_size_override("font_size", 24)
			col.add_child(title)
			_branches.add_child(col)
			columns[branch] = col
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(240, 56)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_upgrade_pressed.bind(id))
		columns[branch].add_child(btn)
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
			btn.text = "%s\n%s  (%s)" % [up["name"], up["desc"], _cost_text(up["cost"])]
			btn.disabled = not GameState.can_purchase(id)

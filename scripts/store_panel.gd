extends Control

var _rows: Dictionary = {}

@onready var _resources_label: Label = $Center/Panel/Margin/VBox/ResourcesLabel
@onready var _rows_box: VBoxContainer = $Center/Panel/Margin/VBox/Rows

func _ready() -> void:
	_build_rows()
	GameState.resources_changed.connect(_on_resources_changed)
	GameState.upgrades_changed.connect(_refresh)
	GameState.inventory_changed.connect(_refresh)
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

func _build_rows() -> void:
	for id in GameState.BUILDINGS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var info := Label.new()
		info.custom_minimum_size = Vector2(440, 0)
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(info)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 44)
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_buy_pressed.bind(id))
		row.add_child(btn)
		_rows_box.add_child(row)
		_rows[id] = {"info": info, "button": btn}

func _on_buy_pressed(id: String) -> void:
	GameState.buy_building(id)

func _refresh() -> void:
	_resources_label.text = "Scrap: %d   Crystal: %d" % [GameState.resources.get("scrap", 0), GameState.resources.get("crystal", 0)]
	for id in _rows:
		var building: Dictionary = GameState.BUILDINGS[id]
		var info: Label = _rows[id]["info"]
		var btn: Button = _rows[id]["button"]
		var owned: int = GameState.inventory.get(id, 0)
		if GameState.is_purchased(building["research"]):
			info.text = "%s — %s (x%d per buy)   Owned: %d" % [building["name"], _cost_text(building["cost"]), building["pack"], owned]
			btn.text = "Buy"
			btn.disabled = not GameState.can_afford(building["cost"])
		else:
			info.text = "%s — Requires: %s" % [building["name"], GameState.UPGRADES[building["research"]]["name"]]
			btn.text = "Locked"
			btn.disabled = true

extends HBoxContainer

var _slots: Array = []

func _ready() -> void:
	GameState.hotbar_changed.connect(_refresh)
	for i in GameState.HOTBAR_SIZE:
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(72, 64)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		panel.add_child(label)
		add_child(panel)
		_slots.append(panel)
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	for i in GameState.HOTBAR_SIZE:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			GameState.select_slot(i)
			return

func _refresh() -> void:
	for i in _slots.size():
		var panel: PanelContainer = _slots[i]
		var label: Label = panel.get_child(0)
		var item = GameState.hotbar[i]
		var item_name: String = item["name"] if item != null else "-"
		label.text = "%d\n%s" % [i + 1, item_name]
		if i == GameState.selected_slot:
			panel.modulate = Color(1, 1, 0.7, 1)
			panel.scale = Vector2(1.0, 1.0)
		else:
			panel.modulate = Color(0.7, 0.7, 0.7, 0.8)

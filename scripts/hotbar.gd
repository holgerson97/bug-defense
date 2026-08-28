extends HBoxContainer

const SLOT_SIZE := Vector2(60, 60)

var _slots: Array = []

func _ready() -> void:
	GameState.hotbar_changed.connect(_refresh)
	GameState.resources_changed.connect(_on_resources_changed)
	for i in GameState.HOTBAR_SIZE:
		_slots.append(_make_slot(i))
	_refresh()

func _make_slot(index: int) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = SLOT_SIZE
	panel.pivot_offset = SLOT_SIZE / 2.0
	panel.add_theme_stylebox_override("panel", UITheme.slot_normal())
	panel.gui_input.connect(_on_slot_gui_input.bind(index))
	var inner := Control.new()
	# Children must not swallow clicks — the panel handles slot selection.
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(inner)
	# Item icon, centered (nudged up to leave room for the cost line).
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_bottom = -8.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(center)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	center.add_child(icon)
	# Slot number badge, top-left ("0" is slot 10; slot 11 is wheel-only).
	var num := Label.new()
	num.text = str((index + 1) % 10) if index < 10 else ""
	num.position = Vector2(5, 1)
	num.add_theme_font_size_override("font_size", 11)
	num.add_theme_color_override("font_color", UITheme.ACCENT)
	inner.add_child(num)
	# Cost line, bottom (buildings only).
	var cost := Label.new()
	cost.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	cost.offset_top = -15.0
	cost.offset_bottom = -2.0
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 10)
	inner.add_child(cost)
	add_child(panel)
	return {"panel": panel, "icon": icon, "num": num, "cost": cost}

func _get_icon(item: Dictionary) -> Texture2D:
	# load() already caches resources per path.
	var path: String = item.get("icon", "")
	return null if path == "" else load(path)

func _on_resources_changed(_resources: Dictionary) -> void:
	_refresh()

func _on_slot_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.select_slot(index)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse wheel cycles through slots, wrapping at both ends.
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			GameState.select_slot(wrapi(GameState.selected_slot - 1, 0, GameState.HOTBAR_SIZE))
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			GameState.select_slot(wrapi(GameState.selected_slot + 1, 0, GameState.HOTBAR_SIZE))
			return
	# Number keys: only the first 10 slots have bound actions (1-9 then 0).
	for i in mini(GameState.HOTBAR_SIZE, 10):
		if event.is_action_pressed("slot_%d" % (i + 1)):
			GameState.select_slot(i)
			return

func _refresh() -> void:
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		var item = GameState.hotbar[i]
		var selected: bool = i == GameState.selected_slot
		# Icon
		if item != null:
			slot["icon"].texture = _get_icon(item)
			slot["icon"].visible = true
			slot["icon"].modulate = Color(1, 1, 1, 1.0 if selected else 0.85)
		else:
			slot["icon"].visible = false
		# Cost (buildings only), red when unaffordable.
		if item != null and GameState.BUILDINGS.has(item["id"]):
			var cost: Dictionary = GameState.BUILDINGS[item["id"]]["cost"]
			slot["cost"].text = Util.cost_text(cost)
			slot["cost"].add_theme_color_override("font_color", UITheme.TEXT_DIM if GameState.can_afford(cost) else UITheme.BAD)
		else:
			slot["cost"].text = ""
		# Style: bright border + slight scale-up when selected, dim when empty.
		var panel: PanelContainer = slot["panel"]
		if selected:
			panel.add_theme_stylebox_override("panel", UITheme.slot_selected())
			panel.scale = Vector2(1.08, 1.08)
		elif item == null:
			panel.add_theme_stylebox_override("panel", UITheme.slot_empty())
			panel.scale = Vector2(1, 1)
		else:
			panel.add_theme_stylebox_override("panel", UITheme.slot_normal())
			panel.scale = Vector2(1, 1)
		slot["num"].modulate = Color(1, 1, 1, 1.0 if item != null else 0.4)

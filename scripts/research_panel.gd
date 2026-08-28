extends Control
## Research tree: branch columns, upgrades placed by tier (requires-depth),
## with connector lines drawn behind the buttons.

const BUTTON_SIZE := Vector2(164, 70)
const LINE_OWNED := Color(0.3, 0.9, 0.4, 0.9)
const LINE_LOCKED := Color(0.5, 0.5, 0.5, 0.35)
const LOCK_ICON := "res://assets/icons/lock.svg"

const TAB_DEFS := [
	{"title": "Player Stats", "branches": ["Offense", "Pilot"]},
	{"title": "Unlocks", "branches": ["Industry"]},
	{"title": "Building Stats", "branches": ["Engineering"]},
]

var _buttons: Dictionary = {}
var _button_ui: Dictionary = {}
var _icon_cache: Dictionary = {}

@onready var _scrap_value: Label = $Center/Panel/Margin/VBox/ResourcesRow/ScrapValue
@onready var _crystal_value: Label = $Center/Panel/Margin/VBox/ResourcesRow/CrystalValue
@onready var _tabs: TabContainer = $Center/Panel/Margin/VBox/Tabs
@onready var _lines: Control = $Lines
@onready var _center: CenterContainer = $Center
@onready var _panel: PanelContainer = $Center/Panel

func _ready() -> void:
	theme = UITheme.build()
	_build_tree()
	_tabs.tab_changed.connect(_on_tab_changed)
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

func _icon(path: String) -> Texture2D:
	if path == "":
		return null
	if not _icon_cache.has(path):
		_icon_cache[path] = load(path)
	return _icon_cache[path]

## Requires-depth: 0 for roots, 1 + max prerequisite tier otherwise.
func _tier(id: String) -> int:
	var tier := 0
	for req in GameState.UPGRADES[id]["requires"]:
		tier = maxi(tier, _tier(req) + 1)
	return tier

func _on_tab_changed(_tab: int) -> void:
	_refresh()

func _build_tree() -> void:
	var tiers := {}
	for id in GameState.UPGRADES:
		tiers[id] = _tier(id)
	# One tab per TAB_DEFS entry; inside, branch columns (definition order)
	# with one centered row per tier so tiers line up across branches.
	for tab in TAB_DEFS:
		var tab_root := HBoxContainer.new()
		tab_root.name = tab["title"]
		tab_root.add_theme_constant_override("separation", 16)
		_tabs.add_child(tab_root)
		var max_tier := 0
		for id in GameState.UPGRADES:
			if GameState.UPGRADES[id]["branch"] in tab["branches"]:
				max_tier = maxi(max_tier, tiers[id])
		var branch_rows := {}
		for id in GameState.UPGRADES:
			var up: Dictionary = GameState.UPGRADES[id]
			var branch: String = up["branch"]
			if not branch in tab["branches"]:
				continue
			if not branch_rows.has(branch):
				var col := VBoxContainer.new()
				col.add_theme_constant_override("separation", 26)
				var title := Label.new()
				title.text = branch
				title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				title.add_theme_font_size_override("font_size", 24)
				title.add_theme_color_override("font_color", UITheme.ACCENT)
				col.add_child(title)
				var rows: Array = []
				for t in max_tier + 1:
					var row := HBoxContainer.new()
					row.alignment = BoxContainer.ALIGNMENT_CENTER
					row.add_theme_constant_override("separation", 10)
					row.custom_minimum_size = Vector2(0, BUTTON_SIZE.y)
					col.add_child(row)
					rows.append(row)
				tab_root.add_child(col)
				branch_rows[branch] = rows
			branch_rows[branch][tiers[id]].add_child(_make_upgrade_button(id))

func _make_upgrade_button(id: String) -> Button:
	var up: Dictionary = GameState.UPGRADES[id]
	var btn := Button.new()
	btn.custom_minimum_size = BUTTON_SIZE
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_upgrade_pressed.bind(id))
	# Custom content (icon + name + desc/status + cost) overlaid on the button.
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	btn.add_child(margin)
	var hbox := HBoxContainer.new()
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_theme_constant_override("separation", 7)
	margin.add_child(hbox)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(icon)
	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	vbox.add_theme_constant_override("separation", 0)
	hbox.add_child(vbox)
	var name_label := Label.new()
	name_label.text = up["name"]
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 13)
	vbox.add_child(name_label)
	var sub_label := Label.new()
	sub_label.clip_text = true
	sub_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_label.add_theme_font_size_override("font_size", 10)
	sub_label.add_theme_color_override("font_color", UITheme.TEXT_DIM)
	vbox.add_child(sub_label)
	var cost_row := HBoxContainer.new()
	cost_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_row.add_theme_constant_override("separation", 6)
	vbox.add_child(cost_row)
	# Always build all three resource pairs; _refresh hides the zero-cost ones
	# (scaled costs can grow a gold component that the base cost lacks).
	var cost_labels := {}
	for kind in ["scrap", "crystal", "gold"]:
		var kind_icon := TextureRect.new()
		kind_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		kind_icon.custom_minimum_size = Vector2(12, 12)
		kind_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		kind_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		kind_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		kind_icon.texture = _icon("res://assets/icons/%s.svg" % kind)
		cost_row.add_child(kind_icon)
		var amount := Label.new()
		amount.text = str(up["cost"].get(kind, 0))
		amount.add_theme_font_size_override("font_size", 11)
		cost_row.add_child(amount)
		cost_labels[kind] = {"icon": kind_icon, "label": amount}
	_buttons[id] = btn
	_button_ui[id] = {"icon": icon, "name": name_label, "sub": sub_label, "cost_row": cost_row, "cost_labels": cost_labels}
	return btn

func _on_upgrade_pressed(id: String) -> void:
	if GameState.purchase(id):
		Sfx.play("levelup")

func _refresh() -> void:
	_scrap_value.text = str(GameState.resources.get("scrap", 0))
	_crystal_value.text = str(GameState.resources.get("crystal", 0))
	for id in _buttons:
		var up: Dictionary = GameState.UPGRADES[id]
		var btn: Button = _buttons[id]
		var ui: Dictionary = _button_ui[id]
		btn.remove_theme_stylebox_override("disabled")
		if GameState.is_purchased(id) and not GameState.is_repeatable(id):
			btn.disabled = true
			btn.add_theme_stylebox_override("disabled", UITheme.owned_style())
			ui["icon"].texture = _icon(up.get("icon", ""))
			ui["icon"].modulate = Color(1, 1, 1, 1)
			ui["name"].modulate = Color(1, 1, 1, 1)
			ui["sub"].text = "OWNED"
			ui["sub"].add_theme_color_override("font_color", UITheme.GOOD)
			ui["cost_row"].visible = false
		elif not GameState.is_unlocked(id):
			btn.disabled = true
			btn.add_theme_stylebox_override("disabled", UITheme.locked_style())
			ui["icon"].texture = _icon(LOCK_ICON)
			ui["icon"].modulate = Color(1, 1, 1, 0.6)
			ui["name"].modulate = Color(1, 1, 1, 0.55)
			ui["sub"].text = "LOCKED"
			ui["sub"].add_theme_color_override("font_color", UITheme.TEXT_DIM)
			ui["cost_row"].visible = false
		else:
			btn.disabled = not GameState.can_purchase(id)
			ui["icon"].texture = _icon(up.get("icon", ""))
			ui["icon"].modulate = Color(1, 1, 1, 1.0 if not btn.disabled else 0.75)
			ui["name"].modulate = Color(1, 1, 1, 1)
			var lvl := GameState.upgrade_level(id)
			ui["sub"].text = up["desc"] if lvl == 0 else "%s  —  Lv %d" % [up["desc"], lvl]
			ui["sub"].add_theme_color_override("font_color", UITheme.TEXT_DIM if lvl == 0 else UITheme.GOOD)
			ui["cost_row"].visible = true
			var cost: Dictionary = GameState.upgrade_cost(id)
			for kind in ui["cost_labels"]:
				var pair: Dictionary = ui["cost_labels"][kind]
				var amount: int = cost.get(kind, 0)
				pair["icon"].visible = amount > 0
				pair["label"].visible = amount > 0
				pair["label"].text = str(amount)
				var enough: bool = GameState.resources.get(kind, 0) >= amount
				pair["label"].add_theme_color_override("font_color", UITheme.TEXT_COLOR if enough else UITheme.BAD)
	# Redraw the connectors after the containers have laid the buttons out,
	# and shrink the whole panel uniformly if the tree is wider than the view.
	await get_tree().process_frame
	var vp := get_viewport_rect().size
	var fit := minf(1.0, minf((vp.x - 24.0) / _panel.size.x, (vp.y - 24.0) / _panel.size.y))
	_center.scale = Vector2(fit, fit)
	_center.pivot_offset = _center.size / 2.0
	_lines.queue_redraw()

func _draw_lines() -> void:
	if not visible:
		return
	for id in _buttons:
		var btn: Button = _buttons[id]
		if not btn.is_visible_in_tree():
			continue
		for req in GameState.UPGRADES[id]["requires"]:
			if not _buttons.has(req):
				continue
			var req_btn: Button = _buttons[req]
			if not req_btn.is_visible_in_tree():
				continue
			# Global transforms so the lines track the auto-fit scale.
			var from: Vector2 = req_btn.get_global_transform() * Vector2(req_btn.size.x / 2.0, req_btn.size.y) - _lines.global_position
			var to: Vector2 = btn.get_global_transform() * Vector2(btn.size.x / 2.0, 0.0) - _lines.global_position
			var color := LINE_OWNED if GameState.is_purchased(req) else LINE_LOCKED
			_lines.draw_line(from, to, color, 3.0)

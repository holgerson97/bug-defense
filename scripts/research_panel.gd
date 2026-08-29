extends Control
## Research tree: one column per branch, upgrades stacked top->bottom by
## tier (requires-depth), with connector lines drawn behind the buttons.

const BUTTON_SIZE := Vector2(164, 70)
const LINE_OWNED := Color(0.3, 0.9, 0.4, 0.9)
const LINE_LOCKED := Color(0.5, 0.5, 0.5, 0.35)
const LOCK_ICON := "res://assets/icons/lock.svg"
## Cost-pair icon overrides: the "scrap" key displays as Bug Hearts.
const COST_ICONS := {"scrap": "res://assets/icons/bug_heart.svg"}

const TAB_DEFS := [
	{"title": "Player Stats", "branches": ["Offense", "Pilot"], "sheet": true},
	{"title": "Unlocks", "branches": ["Defense", "Resource", "Electricity"]},
	{"title": "Building Stats", "branches": ["Engineering"]},
]

## -- Character sheet ("Player Stats" tab) --
## Big rotated class sprite in the middle, one compact card per stat upgrade
## anchored near its body part with a connector line to the sprite.
const CARD_SIZE := Vector2(150, 64)
const SHEET_SIZE := Vector2(900, 600)
const SHEET_SPRITE_SIZE := 260.0
const SHEET_SPRITE_CENTER := Vector2(450, 300)
const FALLBACK_SPRITE := "res://assets/sprites/player_marine.svg"
## Card slots: top-left corner in sheet coords + connector anchor as a fraction
## of the ROTATED sprite rect (sprite art faces +x, drawn rotated -90deg to
## face up: gun/visor at the top, backpack/thrusters at the bottom).
const SHEET_SLOTS := {
	"damage": {"pos": Vector2(285, 40), "anchor": Vector2(0.47, 0.22)},        # gun muzzle
	"crit_damage": {"pos": Vector2(465, 40), "anchor": Vector2(0.53, 0.22)},   # gun muzzle
	"attack_speed": {"pos": Vector2(660, 100), "anchor": Vector2(0.62, 0.42)}, # trigger arm
	"crit_chance": {"pos": Vector2(85, 100), "anchor": Vector2(0.45, 0.34)},   # visor
	"player_light": {"pos": Vector2(85, 190), "anchor": Vector2(0.41, 0.40)},  # head side
	"health": {"pos": Vector2(85, 285), "anchor": Vector2(0.35, 0.55)},        # chest plate
	"regen": {"pos": Vector2(85, 375), "anchor": Vector2(0.38, 0.63)},         # torso side
	"speed": {"pos": Vector2(375, 500), "anchor": Vector2(0.5, 0.86)},         # thrusters
	# Suit systems: stacked column pointing at the backpack/rig edge.
	"build_range": {"pos": Vector2(660, 180), "anchor": Vector2(0.66, 0.68)},
	"heal_range": {"pos": Vector2(660, 252), "anchor": Vector2(0.66, 0.715)},
	"heal_amount": {"pos": Vector2(660, 324), "anchor": Vector2(0.66, 0.75)},
	"player_power": {"pos": Vector2(660, 396), "anchor": Vector2(0.66, 0.785)},
	"player_power_range": {"pos": Vector2(660, 468), "anchor": Vector2(0.66, 0.82)},
}
## Ids without a slot (owner added a new stat) park here, stacked downward.
const SPARE_SLOT_START := Vector2(85, 500)
const SPARE_ANCHOR := Vector2(0.5, 0.55)

var _buttons: Dictionary = {}
var _button_ui: Dictionary = {}
var _sheet: Control = null
var _sheet_sprite: TextureRect = null
var _sheet_lines: Control = null
var _sheet_anchors: Dictionary = {}
var _hover_card := ""

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
	# load() already caches resources per path.
	return null if path == "" else load(path)

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
	# One tab per TAB_DEFS entry; inside, one column per branch (in the tab's
	# branch order) with a header and every upgrade on its own row, stacked
	# top->bottom by tier (roots first), ties in table order.
	for tab in TAB_DEFS:
		if tab.get("sheet", false):
			_build_character_sheet(tab)
			continue
		var tab_root := HBoxContainer.new()
		tab_root.name = tab["title"]
		tab_root.alignment = BoxContainer.ALIGNMENT_CENTER
		tab_root.add_theme_constant_override("separation", 16)
		_tabs.add_child(tab_root)
		for branch in tab["branches"]:
			var ids: Array = []
			var max_tier := 0
			for id in GameState.UPGRADES:
				if GameState.UPGRADES[id]["branch"] == branch:
					ids.append(id)
					max_tier = maxi(max_tier, tiers[id])
			var col := VBoxContainer.new()
			col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			col.add_theme_constant_override("separation", 26)
			var title := Label.new()
			title.text = branch
			title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			title.add_theme_font_size_override("font_size", 24)
			title.add_theme_color_override("font_color", UITheme.ACCENT)
			col.add_child(title)
			for t in max_tier + 1:
				for id in ids:
					if tiers[id] == t:
						var btn := _make_upgrade_button(id)
						btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
						col.add_child(btn)
			tab_root.add_child(col)

## Character sheet tab: fixed-size Control centered in the tab, holding
## (bottom to top) a glow layer, the rotated class sprite, the connector-line
## layer and the upgrade cards. Cards reuse _make_upgrade_button, so purchase,
## affordability and _refresh restyling work exactly like the tree tabs.
func _build_character_sheet(tab: Dictionary) -> void:
	var wrap := CenterContainer.new()
	wrap.name = tab["title"]
	_tabs.add_child(wrap)
	_sheet = Control.new()
	_sheet.custom_minimum_size = SHEET_SIZE
	wrap.add_child(_sheet)
	# Ids come from the live UPGRADES table so owner-added stats still show up;
	# unknown ids get spare slots below the left column (the sheet grows).
	var ids: Array = []
	for id in GameState.UPGRADES:
		if GameState.UPGRADES[id]["branch"] in tab["branches"]:
			ids.append(id)
	var slots := {}
	var spare := 0
	var sheet_h := SHEET_SIZE.y
	for id in ids:
		if SHEET_SLOTS.has(id):
			slots[id] = SHEET_SLOTS[id]
		else:
			var pos: Vector2 = SPARE_SLOT_START + Vector2(0, spare * (CARD_SIZE.y + 8))
			slots[id] = {"pos": pos, "anchor": SPARE_ANCHOR}
			sheet_h = maxf(sheet_h, pos.y + CARD_SIZE.y + 16)
			spare += 1
	_sheet.custom_minimum_size = Vector2(SHEET_SIZE.x, sheet_h)
	var glow := Control.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.draw.connect(_draw_sheet_glow.bind(glow))
	_sheet.add_child(glow)
	_sheet_sprite = TextureRect.new()
	_sheet_sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sheet_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sheet_sprite.size = Vector2(SHEET_SPRITE_SIZE, SHEET_SPRITE_SIZE)
	_sheet_sprite.position = SHEET_SPRITE_CENTER - _sheet_sprite.size / 2.0
	# The art faces +x; rotate -90deg so the marine faces up (gun at the top).
	_sheet_sprite.pivot_offset = _sheet_sprite.size / 2.0
	_sheet_sprite.rotation = -PI / 2.0
	_sheet.add_child(_sheet_sprite)
	_sheet_lines = Control.new()
	_sheet_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sheet_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheet_lines.draw.connect(_draw_sheet_lines)
	_sheet.add_child(_sheet_lines)
	for id in ids:
		var btn := _make_upgrade_button(id)
		btn.custom_minimum_size = CARD_SIZE
		btn.position = slots[id]["pos"]
		btn.size = CARD_SIZE
		btn.mouse_entered.connect(_on_card_hover.bind(id, true))
		btn.mouse_exited.connect(_on_card_hover.bind(id, false))
		_sheet.add_child(btn)
		_sheet_anchors[id] = slots[id]["anchor"]
	_update_sheet_sprite()

func _on_card_hover(id: String, entered: bool) -> void:
	_hover_card = id if entered else ""
	if _sheet_lines != null:
		_sheet_lines.queue_redraw()

## Local player's class model; offline the registry is empty and Net serves
## the local pick. Classes without a dedicated sprite show the tinted marine
## (same rule as player.gd); anything unloadable falls back to the marine.
func _update_sheet_sprite() -> void:
	if _sheet_sprite == null:
		return
	var cls := ""
	var net = get_node_or_null("/root/Net")
	if net != null:
		cls = str(net.player_class(multiplayer.get_unique_id()))
	var path := GameState.class_sprite(cls) if cls != "" else ""
	var tint := Color.WHITE
	if path == "" or not ResourceLoader.exists(path):
		path = FALLBACK_SPRITE
		if cls != "":
			tint = GameState.class_tint(cls)
	_sheet_sprite.texture = load(path)
	_sheet_sprite.modulate = tint

## Subtle radial glow behind the sprite: stacked translucent circles.
func _draw_sheet_glow(layer: Control) -> void:
	if not layer.is_visible_in_tree():
		return
	for i in 16:
		var r := SHEET_SPRITE_SIZE * 0.62 * (1.0 - i / 16.0) + 24.0
		layer.draw_circle(SHEET_SPRITE_CENTER, r, Color(UITheme.ACCENT, 0.016))

## Point on the card's border where the connector should leave, aimed at the
## anchor (center of the facing edge region, not a corner).
func _card_edge_point(btn: Control, target: Vector2) -> Vector2:
	var rect := Rect2(btn.position, btn.size)
	var c := rect.get_center()
	var dir := target - c
	var t := INF
	if absf(dir.x) > 0.001:
		t = minf(t, (rect.size.x / 2.0) / absf(dir.x))
	if absf(dir.y) > 0.001:
		t = minf(t, (rect.size.y / 2.0) / absf(dir.y))
	return c if t == INF else c + dir * t

func _draw_sheet_lines() -> void:
	if not _sheet_lines.is_visible_in_tree():
		return
	var sprite_origin := SHEET_SPRITE_CENTER - Vector2(SHEET_SPRITE_SIZE, SHEET_SPRITE_SIZE) / 2.0
	for id in _sheet_anchors:
		var btn: Button = _buttons[id]
		var anchor: Vector2 = sprite_origin + _sheet_anchors[id] * SHEET_SPRITE_SIZE
		var from := _card_edge_point(btn, anchor)
		var hovered: bool = id == _hover_card
		var color := Color(0.45, 0.65, 0.88, 0.35)
		if GameState.upgrade_level(id) > 0:
			color = Color(UITheme.GOOD, 0.5)
		if hovered:
			color = UITheme.ACCENT
		_sheet_lines.draw_line(from, anchor, color, 3.0 if hovered else 2.0, true)
		_sheet_lines.draw_circle(anchor, 4.0 if hovered else 3.0, color)

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
		kind_icon.texture = _icon(COST_ICONS.get(kind, "res://assets/icons/%s.svg" % kind))
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
	# Resources change every shot/kill; restyling ~30 nodes while hidden is
	# wasted work (visibility_changed re-refreshes on open).
	if not visible:
		return
	# Class can differ per run (and per lobby pick) — re-resolve on every open.
	_update_sheet_sprite()
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
			# Sheet cards are narrower than tree buttons and clip the sub label's
			# tail — put the level FIRST there so it never truncates away.
			if lvl == 0:
				ui["sub"].text = up["desc"]
			elif _sheet_anchors.has(id):
				ui["sub"].text = "Lv %d — %s" % [lvl, up["desc"]]
			else:
				ui["sub"].text = "%s  —  Lv %d" % [up["desc"], lvl]
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
	if _sheet_lines != null:
		_sheet_lines.queue_redraw()

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

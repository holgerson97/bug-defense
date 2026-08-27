class_name UITheme
extends RefCounted
## Shared UI theme, built in code and cached. Assign UITheme.build() to root
## controls so every child inherits it. Not an autoload.

const PANEL_BG := Color(0.10, 0.11, 0.16, 0.92)
const PANEL_BORDER := Color(0.3, 0.5, 0.7, 0.5)
const TEXT_COLOR := Color(0.88, 0.92, 0.97)
const TEXT_DIM := Color(0.62, 0.68, 0.78)
const ACCENT := Color(0.55, 0.82, 1.0)
const GOOD := Color(0.4, 0.9, 0.55)
const BAD := Color(1.0, 0.45, 0.45)

static var _theme: Theme
static var _slot_normal: StyleBoxFlat
static var _slot_selected: StyleBoxFlat
static var _slot_empty: StyleBoxFlat
static var _owned: StyleBoxFlat
static var _locked: StyleBoxFlat

static func flat(bg: Color, border: Color, corner: int = 7, border_width: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(corner)
	return sb

static func build() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	# Panels: dark, semi-transparent, rounded, subtle border.
	var panel := flat(PANEL_BG, PANEL_BORDER, 8, 1)
	panel.content_margin_left = 12.0
	panel.content_margin_right = 12.0
	panel.content_margin_top = 5.0
	panel.content_margin_bottom = 5.0
	_theme.set_stylebox("panel", "PanelContainer", panel)
	_theme.set_stylebox("panel", "Panel", flat(PANEL_BG, PANEL_BORDER, 8, 1))
	# Buttons: distinct normal/hover/pressed/disabled.
	var normal := flat(Color(0.14, 0.16, 0.23, 0.95), Color(0.3, 0.5, 0.7, 0.5), 6, 1)
	var hover := flat(Color(0.19, 0.22, 0.31, 0.97), Color(0.45, 0.65, 0.88, 0.7), 6, 1)
	var pressed := flat(Color(0.08, 0.09, 0.14, 0.97), Color(0.55, 0.82, 1.0, 0.9), 6, 1)
	var disabled := flat(Color(0.11, 0.12, 0.16, 0.6), Color(0.35, 0.4, 0.5, 0.25), 6, 1)
	for sb in [normal, hover, pressed, disabled]:
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 6.0
		sb.content_margin_bottom = 6.0
	_theme.set_stylebox("normal", "Button", normal)
	_theme.set_stylebox("hover", "Button", hover)
	_theme.set_stylebox("pressed", "Button", pressed)
	_theme.set_stylebox("disabled", "Button", disabled)
	_theme.set_color("font_color", "Button", TEXT_COLOR)
	_theme.set_color("font_hover_color", "Button", Color(1, 1, 1))
	_theme.set_color("font_pressed_color", "Button", ACCENT)
	_theme.set_color("font_disabled_color", "Button", Color(0.55, 0.58, 0.66, 0.8))
	_theme.set_color("font_color", "Label", TEXT_COLOR)
	return _theme

# Hotbar slot styleboxes (used as per-slot overrides).
static func slot_normal() -> StyleBoxFlat:
	if _slot_normal == null:
		_slot_normal = flat(Color(0.11, 0.12, 0.18, 0.9), Color(0.3, 0.5, 0.7, 0.45), 8, 1)
	return _slot_normal

static func slot_selected() -> StyleBoxFlat:
	if _slot_selected == null:
		_slot_selected = flat(Color(0.15, 0.18, 0.26, 0.96), Color(0.55, 0.85, 1.0, 0.95), 8, 2)
	return _slot_selected

static func slot_empty() -> StyleBoxFlat:
	if _slot_empty == null:
		_slot_empty = flat(Color(0.09, 0.10, 0.14, 0.6), Color(0.3, 0.4, 0.55, 0.2), 8, 1)
	return _slot_empty

# Research node styleboxes (applied to the "disabled" state of owned/locked buttons).
static func owned_style() -> StyleBoxFlat:
	if _owned == null:
		_owned = flat(Color(0.10, 0.20, 0.13, 0.92), Color(0.35, 0.85, 0.5, 0.6), 6, 1)
		_owned.content_margin_left = 12.0
		_owned.content_margin_right = 12.0
		_owned.content_margin_top = 6.0
		_owned.content_margin_bottom = 6.0
	return _owned

static func locked_style() -> StyleBoxFlat:
	if _locked == null:
		_locked = flat(Color(0.07, 0.075, 0.10, 0.9), Color(0.25, 0.28, 0.36, 0.3), 6, 1)
		_locked.content_margin_left = 12.0
		_locked.content_margin_right = 12.0
		_locked.content_margin_top = 6.0
		_locked.content_margin_bottom = 6.0
	return _locked

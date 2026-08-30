extends CanvasLayer

## Fixed display order for the remaining-enemies readout.
const ENEMY_ORDER := ["Boss", "Drone", "Grunt", "Runner", "Brute", "Wasp", "Mage"]

@onready var _wave_label: Label = $TopRow/WavePanel/HBox/Value
@onready var _wave_timer: Label = $WaveTimer
@onready var _enemies_panel: Control = $TopRow/EnemiesPanel
@onready var _enemies_label: Label = $TopRow/EnemiesPanel/Value
@onready var _score_label: Label = $TopRow/ScorePanel/HBox/Value
@onready var _scrap_label: Label = $TopRow/ScrapPanel/HBox/Value
@onready var _crystal_label: Label = $TopRow/CrystalPanel/HBox/Value
@onready var _gold_label: Label = $TopRow/GoldPanel/HBox/Value
@onready var _energy_label: Label = $TopRow/EnergyPanel/HBox/Value
@onready var _energy_rate: Label = $TopRow/EnergyPanel/HBox/Rate
@onready var _pause_panel: Control = $PausePanel
var _esc_menu: Control
@onready var _pause_hint: Label = $PausePanel/Center/VBox/Hint
@onready var _game_over: Control = $GameOver
@onready var _go_title: Label = $GameOver/Center/Panel/Margin/VBox/Title
@onready var _go_hint: Label = $GameOver/Center/Panel/Margin/VBox/Hint
@onready var _final_score: Label = $GameOver/Center/Panel/Margin/VBox/FinalScore
@onready var _research_panel: Control = $ResearchPanel
@onready var _research_button: Button = $ResearchButton
var _skip_button: Button

## Seconds left in the current between-wave intermission (counted down locally).
var _intermission_left: float = 0.0
## Spectator banner (dead local player), styled like the wave timer.
var _spectate_label: Label
## Game-over panel doubles as the host-drop modal; R then leads to the menu.
var _to_menu := false

func _ready() -> void:
	# Shared theme: assigned to every top-level control so children inherit it.
	var theme := UITheme.build()
	for child in get_children():
		if child is Control:
			child.theme = theme
	_research_button.pressed.connect(toggle_research)
	_build_esc_menu()
	GameState.resources_changed.connect(_on_resources_changed)
	GameState.power_rates_changed.connect(_on_power_rates_changed)
	# Wave manager registers its group before the HUD readies (tree order in main.tscn).
	var wm = get_tree().get_first_node_in_group("wave_manager")
	if wm != null:
		wm.remaining_changed.connect(_on_remaining_changed)
		wm.intermission_started.connect(_on_intermission_started)
		wm.wave_started.connect(_on_wave_started)
		wm.skip_votes_changed.connect(_on_skip_votes_changed)
		_build_skip_button(wm)
	_build_minimap()

## Minimap panel, bottom-right corner above nothing else important.
func _build_minimap() -> void:
	var map = load("res://scripts/minimap.gd").new()
	map.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	map.offset_left = -166.0
	map.offset_top = -166.0
	map.offset_right = -16.0
	map.offset_bottom = -16.0
	add_child(map)
	## Spectator banner clones the wave timer's styling, sitting just below it.
	_spectate_label = _wave_timer.duplicate()
	_spectate_label.name = "SpectateBanner"
	_spectate_label.visible = false
	_spectate_label.offset_top = _wave_timer.offset_bottom + 4.0
	_spectate_label.offset_bottom = _spectate_label.offset_top + 36.0
	_spectate_label.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	add_child(_spectate_label)

func update_wave(wave: int) -> void:
	_wave_label.text = "Wave %d" % wave

## Local countdown mirroring the wave manager's intermission timer.
func _on_intermission_started(seconds: float) -> void:
	_intermission_left = seconds
	_update_wave_timer()
	_wave_timer.visible = true
	if _skip_button != null:
		_skip_button.text = "Skip Day"
		_skip_button.visible = true

func _on_wave_started(_wave: int) -> void:
	_wave_timer.visible = false
	if _skip_button != null:
		_skip_button.visible = false

## Skip Day: ends the intermission early, banking the miners' skipped yield.
## Offline: instant. Co-op: unanimous vote — the label tracks the count.
func _build_skip_button(wm) -> void:
	_skip_button = Button.new()
	_skip_button.text = "Skip Day"
	_skip_button.focus_mode = Control.FOCUS_NONE
	_skip_button.visible = false
	_skip_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_skip_button.offset_top = _wave_timer.offset_bottom + 42.0
	_skip_button.offset_bottom = _skip_button.offset_top + 34.0
	_skip_button.offset_left = -70.0
	_skip_button.offset_right = 70.0
	_skip_button.pressed.connect(wm.request_skip_day)
	add_child(_skip_button)

func _on_skip_votes_changed(count: int, needed: int) -> void:
	if _skip_button == null:
		return
	if needed > 1:
		_skip_button.text = "Skip Day (%d/%d)" % [count, needed]
	else:
		_skip_button.text = "Skip Day"

func _process(delta: float) -> void:
	## HUD processes while paused (process_mode 3); freeze with the game timer.
	if not _wave_timer.visible or get_tree().paused:
		return
	_intermission_left -= delta
	if _intermission_left <= 0.0:
		_wave_timer.visible = false
		return
	_update_wave_timer()

func _update_wave_timer() -> void:
	_wave_timer.text = "Next wave in %d" % ceili(_intermission_left)

## Per-type remaining counts; hidden between waves when nothing is alive.
func _on_remaining_changed(counts: Dictionary) -> void:
	var parts: Array[String] = []
	for type_name in ENEMY_ORDER:
		if counts.get(type_name, 0) > 0:
			parts.append("%s %d" % [type_name, counts[type_name]])
	for type_name in counts:
		if not ENEMY_ORDER.has(type_name) and counts[type_name] > 0:
			parts.append("%s %d" % [type_name, counts[type_name]])
	_enemies_label.text = "  ".join(parts)
	_enemies_panel.visible = not parts.is_empty()

func update_score(score: int) -> void:
	_score_label.text = str(score)

func _on_resources_changed(resources: Dictionary) -> void:
	_scrap_label.text = str(resources.get("scrap", 0))
	_crystal_label.text = str(resources.get("crystal", 0))
	_gold_label.text = str(resources.get("gold", 0))
	# Stored energy over the current cap (batteries raise it).
	_energy_label.text = "%d/%d" % [resources.get("energy", 0), GameState.energy_cap()]

## Energy demand/capacity readout: +production / −consumption per second.
func _on_power_rates_changed(production: float, consumption: float) -> void:
	_energy_rate.text = "+%.1f −%.1f" % [production, consumption]
	_energy_rate.add_theme_color_override("font_color", UITheme.BAD if consumption > production else UITheme.TEXT_DIM)

## Esc menu: Resume / Leave to Main Menu / Quit. Local — pauses offline only.
func _build_esc_menu() -> void:
	_esc_menu = Control.new()
	_esc_menu.theme = UITheme.build()
	_esc_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	_esc_menu.visible = false
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	_esc_menu.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_esc_menu.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 28)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "GAME MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(title)
	vbox.add_child(_esc_button("Resume", toggle_esc_menu))
	vbox.add_child(_esc_button("Leave to Main Menu", _leave_to_menu))
	vbox.add_child(_esc_button("Quit Game", func(): get_tree().quit()))
	add_child(_esc_menu)

func _esc_button(label: String, action) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.custom_minimum_size = Vector2(240, 42)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(action)
	return btn

func toggle_esc_menu() -> void:
	if _game_over.visible or _research_panel.visible or _pause_panel.visible:
		return
	_esc_menu.visible = not _esc_menu.visible
	## Like the research panel: never pauses the shared world online.
	get_tree().paused = _esc_menu.visible and not Net.is_online()

func _leave_to_menu() -> void:
	get_tree().paused = false
	Net.leave()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func toggle_research() -> void:
	if _game_over.visible:
		return
	_esc_menu.visible = false
	_pause_panel.visible = false
	_research_panel.visible = not _research_panel.visible
	## MP: the research panel never pauses the shared world — the waves keep
	## running for everyone; only the local panel opens. (P pause -> Phase 7.)
	get_tree().paused = _research_panel.visible and not Net.is_online()

## P: offline pauses locally; online only the host may pause, and it pauses
## everyone (replicated via main._rpc_set_paused). Client P is ignored.
func toggle_pause() -> void:
	if _game_over.visible or _research_panel.visible:
		return
	_esc_menu.visible = false
	if Net.is_online():
		if Net.is_host():
			get_tree().current_scene._rpc_set_paused.rpc(not _pause_panel.visible)
		return
	_pause_panel.visible = not _pause_panel.visible
	get_tree().paused = _pause_panel.visible

## Replicated pause: show the panel on every peer; only the host can resume.
func set_pause_panel(paused: bool) -> void:
	_pause_hint.text = "Press P to resume" if Net.is_host() else "Host paused the game"
	_pause_panel.visible = paused

## -- spectator banner (dead local player, Phase 7) --

func show_spectate(following: String) -> void:
	_spectate_label.text = "Respawning next wave — following %s" % following
	_spectate_label.visible = true

func hide_spectate() -> void:
	_spectate_label.visible = false

func show_game_over(score: int, wave: int) -> void:
	_research_panel.visible = false
	_pause_panel.visible = false
	_esc_menu.visible = false
	hide_spectate()
	_go_title.text = "YOU DIED"
	_final_score.text = "You survived to wave %d — score %d" % [wave, score]
	if not Net.is_online():
		_go_hint.text = "Press R to restart"
	else:
		_go_hint.text = "Press R to restart for everyone" if Net.is_host() else "Waiting for the host to restart"
	_game_over.visible = true

## Host dropped: reuse the game-over panel as a modal; R returns to the menu.
func show_session_end(reason: String) -> void:
	show_game_over(0, 0)
	_go_title.text = "DISCONNECTED"
	_final_score.text = reason
	_go_hint.text = "Press R for the main menu"
	_to_menu = true

func _unhandled_input(event: InputEvent) -> void:
	if _game_over.visible:
		if event.is_action_pressed("restart"):
			if _to_menu:
				get_tree().paused = false
				Net.leave()
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
			elif not Net.is_online():
				get_tree().paused = false
				get_tree().reload_current_scene()
			elif Net.is_host():
				## Restart vote: host reloads everyone with a fresh world seed.
				get_tree().current_scene._rpc_restart.rpc(randi())
		return
	if event.is_action_pressed("research"):
		toggle_research()
	elif event.is_action_pressed("pause"):
		toggle_pause()
	elif event.is_action_pressed("ui_cancel"):
		if _research_panel.visible:
			toggle_research()
		elif _pause_panel.visible:
			toggle_pause()
		else:
			toggle_esc_menu()

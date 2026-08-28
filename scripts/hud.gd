extends CanvasLayer

@onready var _wave_label: Label = $TopRow/WavePanel/HBox/Value
@onready var _score_label: Label = $TopRow/ScorePanel/HBox/Value
@onready var _xp_label: Label = $TopRow/XPPanel/HBox/Value
@onready var _scrap_label: Label = $TopRow/ScrapPanel/HBox/Value
@onready var _crystal_label: Label = $TopRow/CrystalPanel/HBox/Value
@onready var _gold_label: Label = $TopRow/GoldPanel/HBox/Value
@onready var _game_over: Control = $GameOver
@onready var _final_score: Label = $GameOver/Center/Panel/Margin/VBox/FinalScore
@onready var _research_panel: Control = $ResearchPanel
@onready var _research_button: Button = $ResearchButton

func _ready() -> void:
	# Shared theme: assigned to every top-level control so children inherit it.
	var theme := UITheme.build()
	for child in get_children():
		if child is Control:
			child.theme = theme
	_research_button.pressed.connect(toggle_research)
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.resources_changed.connect(_on_resources_changed)

func update_wave(wave: int) -> void:
	_wave_label.text = "Wave %d" % wave

func update_score(score: int) -> void:
	_score_label.text = str(score)

func _on_xp_changed(xp: int, xp_needed: int, level: int) -> void:
	_xp_label.text = "Lv %d  %d/%d" % [level, xp, xp_needed]

func _on_resources_changed(resources: Dictionary) -> void:
	_scrap_label.text = str(resources.get("scrap", 0))
	_crystal_label.text = str(resources.get("crystal", 0))
	_gold_label.text = str(resources.get("gold", 0))

func toggle_research() -> void:
	if _game_over.visible:
		return
	_research_panel.visible = not _research_panel.visible
	get_tree().paused = _research_panel.visible

func show_game_over(score: int, wave: int) -> void:
	_research_panel.visible = false
	_final_score.text = "You survived to wave %d — score %d" % [wave, score]
	_game_over.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if _game_over.visible:
		if event.is_action_pressed("restart"):
			get_tree().paused = false
			get_tree().reload_current_scene()
		return
	if event.is_action_pressed("research"):
		toggle_research()
	elif event.is_action_pressed("ui_cancel") and _research_panel.visible:
		toggle_research()

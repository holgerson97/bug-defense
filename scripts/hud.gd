extends CanvasLayer

@onready var _wave_label: Label = $TopRow/WaveLabel
@onready var _score_label: Label = $TopRow/ScoreLabel
@onready var _xp_label: Label = $TopRow/XPLabel
@onready var _scrap_label: Label = $TopRow/ScrapLabel
@onready var _crystal_label: Label = $TopRow/CrystalLabel
@onready var _game_over: CenterContainer = $GameOver
@onready var _final_score: Label = $GameOver/VBox/FinalScore
@onready var _research_panel: Control = $ResearchPanel
@onready var _research_button: Button = $ResearchButton
@onready var _store_panel: Control = $StorePanel
@onready var _store_button: Button = $StoreButton

func _ready() -> void:
	_research_button.pressed.connect(toggle_research)
	_store_button.pressed.connect(toggle_store)
	GameState.xp_changed.connect(_on_xp_changed)
	GameState.resources_changed.connect(_on_resources_changed)

func update_wave(wave: int) -> void:
	_wave_label.text = "Wave %d" % wave

func update_score(score: int) -> void:
	_score_label.text = "Score %d" % score

func _on_xp_changed(xp: int, xp_needed: int, level: int) -> void:
	_xp_label.text = "Lv %d  XP %d/%d" % [level, xp, xp_needed]

func _on_resources_changed(resources: Dictionary) -> void:
	_scrap_label.text = "Scrap %d" % resources.get("scrap", 0)
	_crystal_label.text = "Crystal %d" % resources.get("crystal", 0)

func toggle_research() -> void:
	if _game_over.visible:
		return
	var opening := not _research_panel.visible
	_store_panel.visible = false
	_research_panel.visible = opening
	get_tree().paused = opening

func toggle_store() -> void:
	if _game_over.visible:
		return
	var opening := not _store_panel.visible
	_research_panel.visible = false
	_store_panel.visible = opening
	get_tree().paused = opening

func show_game_over(score: int, wave: int) -> void:
	_research_panel.visible = false
	_store_panel.visible = false
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
	elif event.is_action_pressed("store"):
		toggle_store()
	elif event.is_action_pressed("ui_cancel"):
		if _research_panel.visible:
			toggle_research()
		elif _store_panel.visible:
			toggle_store()

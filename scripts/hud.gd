extends CanvasLayer
## HUD - Displays coins, distance, health, and handles pause

@onready var coins_label: Label = $MarginContainer/VBoxContainer/CoinsContainer/CoinsLabel
@onready var distance_label: Label = $MarginContainer/VBoxContainer/DistanceContainer/DistanceLabel
@onready var health_bar: ProgressBar = $MarginContainer/VBoxContainer/HealthContainer/HealthBar
@onready var red_flash: ColorRect = $RedFlash
@onready var pause_menu: Control = $PauseMenu
@onready var music_slider: HSlider = $PauseMenu/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $PauseMenu/VBoxContainer/SFXSlider

var gm: Node  # GameManager reference
var audio: Node  # AudioManager reference

func _ready() -> void:
	gm = get_node("/root/GameManager")
	audio = get_node("/root/AudioManager")
	gm.coins_changed.connect(_on_coins_changed)
	gm.distance_changed.connect(_on_distance_changed)
	gm.game_paused.connect(_on_game_paused)
	gm.health_changed.connect(_on_health_changed)
	gm.player_hit.connect(_on_player_hit)
	
	# Initialize sliders with current volume values
	if audio:
		music_slider.value = audio.get_music_volume()
		sfx_slider.value = audio.get_sfx_volume()
	
	pause_menu.visible = false
	red_flash.visible = false
	_on_coins_changed(gm.coins)
	_on_distance_changed(gm.distance)
	_on_health_changed(gm.health, gm.max_health)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if gm.is_playing:
			if gm.is_paused:
				gm.resume_game()
			else:
				gm.pause_game()

func _on_coins_changed(total: int) -> void:
	coins_label.text = str(total)
	
	# Juice animation
	var tween := create_tween()
	tween.tween_property(coins_label, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(coins_label, "scale", Vector2.ONE, 0.1)

func _on_distance_changed(_dist: float) -> void:
	distance_label.text = gm.get_formatted_distance()

func _on_game_paused(is_paused: bool) -> void:
	pause_menu.visible = is_paused

func _on_health_changed(health: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	
	# Juice animation - shrink and expand
	var tween := create_tween()
	tween.tween_property(health_bar, "scale", Vector2(0.95, 0.8), 0.05)
	tween.tween_property(health_bar, "scale", Vector2.ONE, 0.1)

func _on_player_hit(_damage: int) -> void:
	# Flash red overlay
	red_flash.visible = true
	red_flash.modulate.a = 1.0
	
	var tween := create_tween()
	tween.tween_property(red_flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): red_flash.visible = false)

func _on_settings_pressed() -> void:
	if audio:
		audio.play_button_click()
	gm.pause_game()

func _on_resume_pressed() -> void:
	if audio:
		audio.play_button_click()
	gm.resume_game()

func _on_restart_pressed() -> void:
	if audio:
		audio.play_button_click()
	gm.restart_game()

func _on_menu_pressed() -> void:
	if audio:
		audio.play_button_click()
	gm.go_to_menu()

func _on_music_slider_changed(value: float) -> void:
	if audio:
		audio.set_music_volume(value)

func _on_sfx_slider_changed(value: float) -> void:
	if audio:
		audio.set_sfx_volume(value)

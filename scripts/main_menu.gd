extends Control
## Main Menu with animated boulder, stats tracking, and visual effects

const STATS_FILE := "user://stats.json"
const PLAYER_MODEL_SCENE := preload("res://assets/models/players/player_1.blend")

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var stats_button: Button = $VBoxContainer/StatsButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var settings_panel: Control = $SettingsPanel
@onready var stats_panel: Control = $StatsPanel
@onready var main_vbox: VBoxContainer = $VBoxContainer
@onready var music_slider: HSlider = $SettingsPanel/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $SettingsPanel/VBoxContainer/SFXSlider
@onready var player_model_container: Node3D = $PlayerViewport/SubViewport/PlayerModel

# Stats labels
@onready var max_coins_label: Label = $StatsPanel/VBoxContainer/MaxCoins
@onready var avg_coins_label: Label = $StatsPanel/VBoxContainer/AvgCoins
@onready var max_distance_label: Label = $StatsPanel/VBoxContainer/MaxDistance
@onready var avg_distance_label: Label = $StatsPanel/VBoxContainer/AvgDistance
@onready var games_played_label: Label = $StatsPanel/VBoxContainer/GamesPlayed

var audio_manager: Node
var player_model_instance: Node3D
var model_rotation_speed := 0.5

# Stats data
var stats := {
	"games_played": 0,
	"total_coins": 0,
	"max_coins": 0,
	"total_distance": 0.0,
	"max_distance": 0.0
}

func _ready() -> void:
	audio_manager = get_node("/root/AudioManager")
	
	# Initialize sliders with current volume values
	music_slider.value = audio_manager.get_music_volume()
	sfx_slider.value = audio_manager.get_sfx_volume()
	
	# Start menu music
	audio_manager.play_menu_music()
	
	# Load stats
	_load_stats()
	
	# Setup 3D player model
	_setup_player_model()
	
	# Setup snow particles
	_setup_snow_particles()
	
	# Focus play button
	play_button.grab_focus()
	
	# Entrance animation (if available)
	if animation_player.has_animation("enter"):
		animation_player.play("enter")

func _process(delta: float) -> void:
	# Rotate player model
	if player_model_instance:
		player_model_instance.rotate_y(model_rotation_speed * delta)

func _setup_player_model() -> void:
	if player_model_container and PLAYER_MODEL_SCENE:
		player_model_instance = PLAYER_MODEL_SCENE.instantiate()
		player_model_instance.scale = Vector3(0.3, 0.3, 0.3)
		player_model_container.add_child(player_model_instance)

func _setup_snow_particles() -> void:
	var viewport_size: Vector2i = get_viewport().size
	
	var particles := GPUParticles2D.new()
	particles.name = "SnowParticles"
	particles.amount = 150
	particles.lifetime = 10.0
	particles.preprocess = 5.0
	
	# Create process material
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 5.0
	material.gravity = Vector3(5, 80, 0)
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 40.0
	material.scale_min = 2.0
	material.scale_max = 5.0
	
	# Emission across full width
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(viewport_size.x / 2.0, 10, 1)
	
	particles.process_material = material
	
	# Position at top center of screen
	particles.position = Vector2(viewport_size.x / 2.0, 0)
	particles.visibility_rect = Rect2(-viewport_size.x, -50, viewport_size.x * 2, viewport_size.y + 100)
	
	# Add to background (behind VBoxContainer)
	$Background.add_sibling(particles)

# ========== Stats Management ==========

func _load_stats() -> void:
	if FileAccess.file_exists(STATS_FILE):
		var file := FileAccess.open(STATS_FILE, FileAccess.READ)
		if file:
			var json_string := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(json_string) == OK:
				var data = json.get_data()
				if data is Dictionary:
					stats = data

func _save_stats() -> void:
	var file := FileAccess.open(STATS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(stats))
		file.close()

func _update_stats_display() -> void:
	var games: int = int(stats.get("games_played", 0))
	var max_c: int = int(stats.get("max_coins", 0))
	var total_c: int = int(stats.get("total_coins", 0))
	var max_d: float = float(stats.get("max_distance", 0.0))
	var total_d: float = float(stats.get("total_distance", 0.0))
	
	var avg_coins: int = 0
	var avg_distance: float = 0.0
	if games > 0:
		avg_coins = int(total_c / games)
		avg_distance = total_d / games
	
	max_coins_label.text = "Best: %d" % max_c
	avg_coins_label.text = "Average: %d" % avg_coins
	max_distance_label.text = "Best: %dm" % int(max_d)
	avg_distance_label.text = "Average: %dm" % int(avg_distance)
	games_played_label.text = "Games Played: %d" % games

# Static method to record game results (called from game_manager)
static func record_game_stats(coins: int, distance: float) -> void:
	var stats_data := {}
	
	# Load existing stats
	if FileAccess.file_exists(STATS_FILE):
		var file := FileAccess.open(STATS_FILE, FileAccess.READ)
		if file:
			var json_string := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(json_string) == OK:
				var data = json.get_data()
				if data is Dictionary:
					stats_data = data
	
	# Update stats
	var prev_games: int = int(stats_data.get("games_played", 0))
	var prev_coins: int = int(stats_data.get("total_coins", 0))
	var prev_max_coins: int = int(stats_data.get("max_coins", 0))
	var prev_distance: float = float(stats_data.get("total_distance", 0.0))
	var prev_max_distance: float = float(stats_data.get("max_distance", 0.0))
	
	stats_data["games_played"] = prev_games + 1
	stats_data["total_coins"] = prev_coins + coins
	stats_data["max_coins"] = max(prev_max_coins, coins)
	stats_data["total_distance"] = prev_distance + distance
	stats_data["max_distance"] = max(prev_max_distance, distance)
	
	# Save updated stats
	var file := FileAccess.open(STATS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(stats_data))
		file.close()

# ========== Button Actions ==========

func _on_play_button_pressed() -> void:
	audio_manager.play_button_click()
	if animation_player.has_animation("exit"):
		animation_player.play("exit")
		await animation_player.animation_finished
	var st = get_node("/root/SceneTransition")
	st.change_scene("res://scenes/game.tscn")

func _on_stats_button_pressed() -> void:
	audio_manager.play_button_click()
	_load_stats()
	_update_stats_display()
	stats_panel.visible = true
	main_vbox.visible = false

func _on_stats_back_pressed() -> void:
	audio_manager.play_button_click()
	stats_panel.visible = false
	main_vbox.visible = true

func _on_settings_button_pressed() -> void:
	audio_manager.play_button_click()
	settings_panel.visible = true
	main_vbox.visible = false

func _on_settings_back_pressed() -> void:
	audio_manager.play_button_click()
	settings_panel.visible = false
	main_vbox.visible = true

func _on_quit_button_pressed() -> void:
	audio_manager.play_button_click()
	if animation_player.has_animation("exit"):
		animation_player.play("exit")
		await animation_player.animation_finished
	get_tree().quit()

# ========== Button Hover Effects ==========

func _button_hover(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.1)

func _button_exit(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.1)

func _on_play_button_mouse_entered() -> void:
	_button_hover(play_button)

func _on_play_button_mouse_exited() -> void:
	_button_exit(play_button)

func _on_stats_button_mouse_entered() -> void:
	_button_hover(stats_button)

func _on_stats_button_mouse_exited() -> void:
	_button_exit(stats_button)

func _on_settings_button_mouse_entered() -> void:
	_button_hover(settings_button)

func _on_settings_button_mouse_exited() -> void:
	_button_exit(settings_button)

func _on_quit_button_mouse_entered() -> void:
	_button_hover(quit_button)

func _on_quit_button_mouse_exited() -> void:
	_button_exit(quit_button)

# ========== Settings ==========

func _on_music_slider_value_changed(value: float) -> void:
	audio_manager.set_music_volume(value)

func _on_sfx_slider_value_changed(value: float) -> void:
	audio_manager.set_sfx_volume(value)

func _on_author_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

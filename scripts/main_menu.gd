extends Control
## Main Menu with animated boulder background

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton
@onready var quit_button: Button = $VBoxContainer/QuitButton
@onready var settings_panel: Control = $SettingsPanel
@onready var music_slider: HSlider = $SettingsPanel/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $SettingsPanel/VBoxContainer/SFXSlider

var audio_manager: Node

func _ready() -> void:
	audio_manager = get_node("/root/AudioManager")
	
	# Initialize sliders with current volume values
	music_slider.value = audio_manager.get_music_volume()
	sfx_slider.value = audio_manager.get_sfx_volume()
	
	# Start menu music
	audio_manager.play_menu_music()
	
	# Focus play button
	play_button.grab_focus()
	
	# Entrance animation
	animation_player.play("enter")

func _on_play_button_pressed() -> void:
	audio_manager.play_button_click()
	animation_player.play("exit")
	await animation_player.animation_finished
	var st = get_node("/root/SceneTransition")
	st.change_scene("res://scenes/game.tscn")

func _on_quit_button_pressed() -> void:
	audio_manager.play_button_click()
	animation_player.play("exit")
	await animation_player.animation_finished
	get_tree().quit()

func _on_play_button_mouse_entered() -> void:
	_button_hover(play_button)

func _on_quit_button_mouse_entered() -> void:
	_button_hover(quit_button)

func _button_hover(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.05, 1.05), 0.1)

func _on_button_mouse_exited(button: Button) -> void:
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2.ONE, 0.1)

func _on_play_button_mouse_exited() -> void:
	_on_button_mouse_exited(play_button)

func _on_quit_button_mouse_exited() -> void:
	_on_button_mouse_exited(quit_button)

# ========== Settings ==========

func _on_settings_button_pressed() -> void:
	audio_manager.play_button_click()
	settings_panel.visible = true

func _on_settings_back_pressed() -> void:
	audio_manager.play_button_click()
	settings_panel.visible = false

func _on_music_slider_value_changed(value: float) -> void:
	audio_manager.set_music_volume(value)

func _on_sfx_slider_value_changed(value: float) -> void:
	audio_manager.set_sfx_volume(value)

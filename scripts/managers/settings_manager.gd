extends Node
## SettingsManager - Central hub for all game settings with persistence

const SETTINGS_PATH := "user://settings.cfg"

# ========== Audio Settings ==========
var music_volume: float = 0.7  # 0.0 to 1.0
var sfx_volume: float = 0.8    # 0.0 to 1.0

# ========== Display Settings ==========
var show_pickup_popup: bool = true   # Show +1 coin popup on pickup
var show_damage_popup: bool = true   # Show damage numbers when taking damage

# ========== Gameplay Settings ==========
var haptic_enabled: bool = true      # Enable vibration feedback
var screen_shake_enabled: bool = true  # Screen shake effects on impact

# ========== Control Settings ==========
var control_mode: int = 0            # 0 = gyro, 1 = touch
var tilt_sensitivity: float = 1.0    # 0.5 to 2.0 - how sensitive gyro controls are

func _ready() -> void:
	_load_settings()

# ========== Audio Getters/Setters ==========

func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_save_settings()
	_notify_audio_volume_changed()

func get_music_volume() -> float:
	return music_volume

func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_save_settings()

func get_sfx_volume() -> float:
	return sfx_volume

# ========== Display Getters/Setters ==========

func set_show_pickup_popup(value: bool) -> void:
	show_pickup_popup = value
	_save_settings()

func get_show_pickup_popup() -> bool:
	return show_pickup_popup

func set_show_damage_popup(value: bool) -> void:
	show_damage_popup = value
	_save_settings()

func get_show_damage_popup() -> bool:
	return show_damage_popup

# ========== Gameplay Getters/Setters ==========

func set_haptic_enabled(value: bool) -> void:
	haptic_enabled = value
	_save_settings()

func get_haptic_enabled() -> bool:
	return haptic_enabled

func set_screen_shake_enabled(value: bool) -> void:
	screen_shake_enabled = value
	_save_settings()

func get_screen_shake_enabled() -> bool:
	return screen_shake_enabled

## Vibrate if haptic is enabled
func vibrate(duration_ms: int = 100) -> void:
	if haptic_enabled:
		Input.vibrate_handheld(duration_ms)

# ========== Control Getters/Setters ==========

## Control mode: 0 = gyro, 1 = touch
func set_control_mode(value: int) -> void:
	control_mode = clampi(value, 0, 1)
	_save_settings()

func get_control_mode() -> int:
	return control_mode

func is_touch_mode() -> bool:
	return control_mode == 1

func is_gyro_mode() -> bool:
	return control_mode == 0

## Tilt sensitivity: 0.5 to 2.0
func set_tilt_sensitivity(value: float) -> void:
	tilt_sensitivity = clampf(value, 0.5, 2.0)
	_save_settings()

func get_tilt_sensitivity() -> float:
	return tilt_sensitivity

# ========== Volume Helpers ==========

## Convert linear volume (0-1) to decibels
func get_music_db(base_db: float = 0.0) -> float:
	if music_volume <= 0.0:
		return -80.0
	return base_db + linear_to_db(music_volume)

func get_sfx_db(base_db: float = 0.0) -> float:
	if sfx_volume <= 0.0:
		return -80.0
	return base_db + linear_to_db(sfx_volume)

## Notify AudioManager when volume changes (so it can update playing music)
func _notify_audio_volume_changed() -> void:
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("_apply_music_volume"):
		audio._apply_music_volume()

# ========== Persistence ==========

func _save_settings() -> void:
	var config := ConfigFile.new()
	# Audio
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	# Display
	config.set_value("display", "show_pickup_popup", show_pickup_popup)
	config.set_value("display", "show_damage_popup", show_damage_popup)
	# Gameplay
	config.set_value("gameplay", "haptic_enabled", haptic_enabled)
	config.set_value("gameplay", "screen_shake_enabled", screen_shake_enabled)
	# Controls
	config.set_value("controls", "control_mode", control_mode)
	config.set_value("controls", "tilt_sensitivity", tilt_sensitivity)
	config.save(SETTINGS_PATH)

func _load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		# Audio
		music_volume = config.get_value("audio", "music_volume", 0.7)
		sfx_volume = config.get_value("audio", "sfx_volume", 0.8)
		# Display
		show_pickup_popup = config.get_value("display", "show_pickup_popup", true)
		show_damage_popup = config.get_value("display", "show_damage_popup", true)
		# Legacy: migrate from old "ui" section if present
		if config.has_section_key("ui", "show_pickup_popup"):
			show_pickup_popup = config.get_value("ui", "show_pickup_popup", true)
		if config.has_section_key("ui", "show_damage_popup"):
			show_damage_popup = config.get_value("ui", "show_damage_popup", true)
		if config.has_section_key("ui", "haptic_enabled"):
			haptic_enabled = config.get_value("ui", "haptic_enabled", true)
		# Gameplay
		haptic_enabled = config.get_value("gameplay", "haptic_enabled", haptic_enabled)
		screen_shake_enabled = config.get_value("gameplay", "screen_shake_enabled", true)
		# Controls
		control_mode = config.get_value("controls", "control_mode", 0)
		tilt_sensitivity = config.get_value("controls", "tilt_sensitivity", 1.0)

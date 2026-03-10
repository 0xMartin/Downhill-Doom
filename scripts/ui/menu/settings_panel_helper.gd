class_name SettingsPanelHelper
extends RefCounted
## Helper class for managing the settings panel UI
## Loads UI from scene file and handles logic/signals

const CONTENT_SCENE := preload("res://scenes/ui/settings_panel_content.tscn")

# Color palette for dynamic styling
const COLOR_ACCENT_PRIMARY := Color(0.25, 0.65, 0.96, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.65, 1.0)
const COLOR_BG_DARK := Color(0.06, 0.08, 0.12, 1.0)
const COLOR_BORDER := Color(0.25, 0.32, 0.45, 0.8)

var settings_panel: Control
var audio_manager: Node
var content_instance: Node

# UI References (found from scene using %UniqueNames)
var music_slider: HSlider
var sfx_slider: HSlider
var popup_check: CheckButton
var damage_check: CheckButton
var haptic_check: CheckButton
var screen_shake_check: CheckButton
var control_gyro_btn: Button
var control_touch_btn: Button
var tilt_sensitivity_container: VBoxContainer
var tilt_sensitivity_slider: HSlider
var tilt_sensitivity_label: Label


func _init(panel: Control, audio: Node) -> void:
	settings_panel = panel
	audio_manager = audio


func rebuild() -> void:
	# Clear existing content except Background
	var children_to_remove: Array[Node] = []
	for child in settings_panel.get_children():
		if child.name != "Background":
			children_to_remove.append(child)
	for child in children_to_remove:
		settings_panel.remove_child(child)
		child.free()
	
	# Update background
	var bg: ColorRect = settings_panel.get_node_or_null("Background")
	if bg:
		bg.color = Color(0, 0, 0, 0.92)
	
	# Calculate safe area offset for notch/dynamic island
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size: Vector2 = settings_panel.get_viewport().get_visible_rect().size
	var physical_screen := Vector2(DisplayServer.screen_get_size())
	var scale_y: float = screen_size.y / physical_screen.y if physical_screen.y > 0 else 1.0
	var top_inset: float = safe_area.position.y * scale_y
	
	# Instance and add the content scene
	content_instance = CONTENT_SCENE.instantiate()
	content_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_instance.offset_top = top_inset
	settings_panel.add_child(content_instance)
	
	# Get references to UI elements using %UniqueNames
	_find_ui_references()
	
	# Connect signals
	_connect_signals()
	
	# Apply dynamic styling where needed
	_apply_dynamic_styles()
	
	# Load saved settings
	_load_saved_settings()


func _find_ui_references() -> void:
	music_slider = content_instance.get_node("%MusicSlider") as HSlider
	sfx_slider = content_instance.get_node("%SFXSlider") as HSlider
	popup_check = content_instance.get_node("%PopupCheck") as CheckButton
	damage_check = content_instance.get_node("%DamageCheck") as CheckButton
	haptic_check = content_instance.get_node("%HapticCheck") as CheckButton
	screen_shake_check = content_instance.get_node("%ScreenShakeCheck") as CheckButton
	control_gyro_btn = content_instance.get_node("%GyroButton") as Button
	control_touch_btn = content_instance.get_node("%TouchButton") as Button
	tilt_sensitivity_container = content_instance.get_node("%TiltSensitivityContainer") as VBoxContainer
	tilt_sensitivity_slider = content_instance.get_node("%TiltSensitivitySlider") as HSlider
	tilt_sensitivity_label = content_instance.get_node("%TiltSensitivityValue") as Label


func _connect_signals() -> void:
	if music_slider:
		music_slider.value_changed.connect(_on_music_changed)
	if sfx_slider:
		sfx_slider.value_changed.connect(_on_sfx_changed)
	if popup_check:
		popup_check.toggled.connect(_on_popup_toggled)
	if damage_check:
		damage_check.toggled.connect(_on_damage_toggled)
	if haptic_check:
		haptic_check.toggled.connect(_on_haptic_toggled)
	if screen_shake_check:
		screen_shake_check.toggled.connect(_on_screen_shake_toggled)
	if control_gyro_btn:
		control_gyro_btn.pressed.connect(_on_gyro_pressed)
	if control_touch_btn:
		control_touch_btn.pressed.connect(_on_touch_pressed)
	if tilt_sensitivity_slider:
		tilt_sensitivity_slider.value_changed.connect(_on_tilt_sensitivity_changed)


func _apply_dynamic_styles() -> void:
	# Apply slider styling
	if music_slider:
		_style_slider(music_slider)
	if sfx_slider:
		_style_slider(sfx_slider)
	if tilt_sensitivity_slider:
		_style_slider(tilt_sensitivity_slider)


func _load_saved_settings() -> void:
	if audio_manager:
		if music_slider:
			music_slider.value = audio_manager.get_music_volume()
		if sfx_slider:
			sfx_slider.value = audio_manager.get_sfx_volume()
		if popup_check:
			popup_check.button_pressed = audio_manager.get_show_pickup_popup()
		if damage_check:
			damage_check.button_pressed = audio_manager.get_show_damage_popup()
		if haptic_check:
			haptic_check.button_pressed = audio_manager.get_haptic_enabled()
		_update_control_mode_buttons(audio_manager.get_control_mode())
	
	var settings := settings_panel.get_node_or_null("/root/SettingsManager")
	if settings:
		if screen_shake_check:
			screen_shake_check.button_pressed = settings.get_screen_shake_enabled()
		if tilt_sensitivity_slider:
			tilt_sensitivity_slider.value = settings.get_tilt_sensitivity()
			_update_tilt_sensitivity_label(settings.get_tilt_sensitivity())


func get_back_button() -> Button:
	if content_instance:
		return content_instance.get_node("%BackButton") as Button
	return null


# ========== Styling ==========

func _style_slider(slider: HSlider) -> void:
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = COLOR_BG_DARK
	slider_bg.set_corner_radius_all(25)
	slider_bg.set_content_margin_all(12)
	
	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	grabber_area.set_corner_radius_all(25)
	grabber_area.set_content_margin_all(12)
	
	var grabber_area_hl := StyleBoxFlat.new()
	grabber_area_hl.bg_color = COLOR_ACCENT_PRIMARY
	grabber_area_hl.set_corner_radius_all(25)
	grabber_area_hl.set_content_margin_all(12)
	
	slider.add_theme_stylebox_override("slider", slider_bg)
	slider.add_theme_stylebox_override("grabber_area", grabber_area)
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber_area_hl)
	slider.add_theme_icon_override("grabber", _create_circle_texture(72, COLOR_ACCENT_PRIMARY))
	slider.add_theme_icon_override("grabber_highlight", _create_circle_texture(76, COLOR_ACCENT_PRIMARY.lightened(0.2)))


func _create_circle_texture(size: int, color: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := Vector2(size / 2.0, size / 2.0)
	var radius := size / 2.0 - 1
	
	for x in range(size):
		for y in range(size):
			var dist := Vector2(x, y).distance_to(center)
			if dist <= radius:
				img.set_pixel(x, y, color)
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	
	return ImageTexture.create_from_image(img)


func _update_control_mode_buttons(mode: int) -> void:
	if not control_gyro_btn or not control_touch_btn:
		return
	
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = COLOR_ACCENT_PRIMARY
	active_style.set_corner_radius_all(10)
	active_style.set_border_width_all(2)
	active_style.border_color = COLOR_ACCENT_PRIMARY.lightened(0.3)
	
	var inactive_style := StyleBoxFlat.new()
	inactive_style.bg_color = COLOR_BG_DARK
	inactive_style.set_corner_radius_all(10)
	inactive_style.set_border_width_all(2)
	inactive_style.border_color = COLOR_BORDER
	
	if mode == 0:  # Gyro
		control_gyro_btn.add_theme_stylebox_override("normal", active_style)
		control_gyro_btn.add_theme_stylebox_override("hover", active_style)
		control_gyro_btn.add_theme_stylebox_override("pressed", active_style)
		control_gyro_btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
		control_touch_btn.add_theme_stylebox_override("normal", inactive_style)
		control_touch_btn.add_theme_stylebox_override("hover", inactive_style)
		control_touch_btn.add_theme_stylebox_override("pressed", inactive_style)
		control_touch_btn.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	else:  # Touch
		control_touch_btn.add_theme_stylebox_override("normal", active_style)
		control_touch_btn.add_theme_stylebox_override("hover", active_style)
		control_touch_btn.add_theme_stylebox_override("pressed", active_style)
		control_touch_btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
		control_gyro_btn.add_theme_stylebox_override("normal", inactive_style)
		control_gyro_btn.add_theme_stylebox_override("hover", inactive_style)
		control_gyro_btn.add_theme_stylebox_override("pressed", inactive_style)
		control_gyro_btn.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	
	if tilt_sensitivity_container:
		tilt_sensitivity_container.visible = (mode == 0)


func _update_tilt_sensitivity_label(value: float) -> void:
	if tilt_sensitivity_label:
		tilt_sensitivity_label.text = "%.1fx" % value


# ========== Callbacks ==========

func _on_music_changed(value: float) -> void:
	if audio_manager:
		audio_manager.set_music_volume(value)


func _on_sfx_changed(value: float) -> void:
	if audio_manager:
		audio_manager.set_sfx_volume(value)


func _on_popup_toggled(toggled_on: bool) -> void:
	if audio_manager:
		audio_manager.set_show_pickup_popup(toggled_on)


func _on_damage_toggled(toggled_on: bool) -> void:
	if audio_manager:
		audio_manager.set_show_damage_popup(toggled_on)


func _on_haptic_toggled(toggled_on: bool) -> void:
	if audio_manager:
		audio_manager.set_haptic_enabled(toggled_on)


func _on_screen_shake_toggled(toggled_on: bool) -> void:
	var settings := settings_panel.get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_screen_shake_enabled(toggled_on)


func _on_gyro_pressed() -> void:
	if audio_manager:
		audio_manager.set_control_mode(0)
	_update_control_mode_buttons(0)


func _on_touch_pressed() -> void:
	if audio_manager:
		audio_manager.set_control_mode(1)
	_update_control_mode_buttons(1)


func _on_tilt_sensitivity_changed(value: float) -> void:
	var settings := settings_panel.get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_tilt_sensitivity(value)
	_update_tilt_sensitivity_label(value)

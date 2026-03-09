class_name SettingsPanelHelper
extends RefCounted
## Helper class for building and managing the settings panel UI

# Color palette (shared with main menu)
const COLOR_BG_DARK := Color(0.06, 0.08, 0.12, 1.0)
const COLOR_BG_MEDIUM := Color(0.10, 0.14, 0.20, 1.0)
const COLOR_BG_LIGHT := Color(0.14, 0.18, 0.26, 1.0)
const COLOR_ACCENT_PRIMARY := Color(0.25, 0.65, 0.96, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.7, 0.75, 0.85, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.65, 1.0)
const COLOR_BORDER := Color(0.25, 0.32, 0.45, 0.8)

var settings_panel: Control
var audio_manager: Node

# UI References
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
	# Clear existing content - use free() for immediate removal
	var children_to_remove: Array[Node] = []
	for child in settings_panel.get_children():
		if child.name != "Background":
			children_to_remove.append(child)
	for child in children_to_remove:
		settings_panel.remove_child(child)
		child.free()
	
	# Update background
	var bg: ColorRect = settings_panel.get_node("Background")
	bg.color = Color(0, 0, 0, 0.92)
	
	var screen_size: Vector2 = settings_panel.get_viewport().get_visible_rect().size
	var panel_width: float = minf(720.0, screen_size.x * 0.92)
	var panel_height: float = minf(screen_size.y * 0.88, screen_size.y - 60)
	
	# Create centered VBox for positioning
	var center_vbox := VBoxContainer.new()
	center_vbox.anchors_preset = Control.PRESET_CENTER
	center_vbox.anchor_left = 0.5
	center_vbox.anchor_top = 0.5
	center_vbox.anchor_right = 0.5
	center_vbox.anchor_bottom = 0.5
	center_vbox.offset_left = -panel_width / 2
	center_vbox.offset_right = panel_width / 2
	center_vbox.offset_top = -panel_height / 2
	center_vbox.offset_bottom = panel_height / 2
	center_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	settings_panel.add_child(center_vbox)
	
	# Create main card container
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(panel_width, panel_height)
	
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_BG_MEDIUM
	card_style.set_corner_radius_all(24)
	card_style.set_border_width_all(2)
	card_style.border_color = COLOR_BORDER
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	card_style.shadow_size = 20
	card_style.set_content_margin_all(24)
	card.add_theme_stylebox_override("panel", card_style)
	center_vbox.add_child(card)
	
	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 16)
	card.add_child(inner_vbox)
	
	# Title with glow
	var title := Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	title.add_theme_color_override("font_outline_color", COLOR_ACCENT_PRIMARY)
	title.add_theme_constant_override("outline_size", 2)
	inner_vbox.add_child(title)
	
	# Decoration under title
	var decoration := TextureRect.new()
	var deco_tex = load("res://assets/svg/settings_decoration.svg")
	if deco_tex:
		decoration.texture = deco_tex
		decoration.custom_minimum_size = Vector2(180, 16)
		decoration.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		decoration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		decoration.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		decoration.modulate = COLOR_ACCENT_PRIMARY.lightened(0.3)
		inner_vbox.add_child(decoration)
	
	# Spacer
	var spacer1 := Control.new()
	spacer1.custom_minimum_size = Vector2(0, 8)
	inner_vbox.add_child(spacer1)
	
	# Audio Section
	var audio_card := _create_section("AUDIO")
	inner_vbox.add_child(audio_card)
	
	var audio_content := audio_card.get_child(0)
	
	# Music row
	var music_row := HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 20)
	audio_content.add_child(music_row)
	
	var music_label := Label.new()
	music_label.text = "Music"
	music_label.custom_minimum_size = Vector2(140, 0)
	music_label.add_theme_font_size_override("font_size", 22)
	music_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	music_row.add_child(music_label)
	
	music_slider = HSlider.new()
	music_slider.custom_minimum_size = Vector2(280, 30)
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	music_slider.max_value = 1.0
	music_slider.step = 0.05
	music_slider.value = 0.7
	_style_slider(music_slider)
	music_slider.value_changed.connect(_on_music_changed)
	music_row.add_child(music_slider)
	
	# SFX row
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 20)
	audio_content.add_child(sfx_row)
	
	var sfx_label := Label.new()
	sfx_label.text = "Sound Effects"
	sfx_label.custom_minimum_size = Vector2(140, 0)
	sfx_label.add_theme_font_size_override("font_size", 22)
	sfx_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	sfx_row.add_child(sfx_label)
	
	sfx_slider = HSlider.new()
	sfx_slider.custom_minimum_size = Vector2(280, 30)
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = 0.8
	_style_slider(sfx_slider)
	sfx_slider.value_changed.connect(_on_sfx_changed)
	sfx_row.add_child(sfx_slider)
	
	# Display Section
	var display_card := _create_section("DISPLAY")
	inner_vbox.add_child(display_card)
	
	var display_content := display_card.get_child(0)
	
	popup_check = CheckButton.new()
	popup_check.text = "Show Pickup Popups"
	popup_check.button_pressed = true
	popup_check.add_theme_font_size_override("font_size", 22)
	popup_check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	popup_check.toggled.connect(_on_popup_toggled)
	display_content.add_child(popup_check)
	
	damage_check = CheckButton.new()
	damage_check.text = "Show Damage Numbers"
	damage_check.button_pressed = true
	damage_check.add_theme_font_size_override("font_size", 22)
	damage_check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	damage_check.toggled.connect(_on_damage_toggled)
	display_content.add_child(damage_check)
	
	haptic_check = CheckButton.new()
	haptic_check.text = "Haptic Feedback"
	haptic_check.button_pressed = true
	haptic_check.add_theme_font_size_override("font_size", 22)
	haptic_check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	haptic_check.toggled.connect(_on_haptic_toggled)
	display_content.add_child(haptic_check)
	
	screen_shake_check = CheckButton.new()
	screen_shake_check.text = "Screen Shake"
	screen_shake_check.button_pressed = true
	screen_shake_check.add_theme_font_size_override("font_size", 22)
	screen_shake_check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	screen_shake_check.toggled.connect(_on_screen_shake_toggled)
	display_content.add_child(screen_shake_check)
	
	# Controls Section
	var controls_card := _create_section("CONTROLS")
	inner_vbox.add_child(controls_card)
	
	var controls_content := controls_card.get_child(0)
	
	var control_label := Label.new()
	control_label.text = "Control Mode"
	control_label.add_theme_font_size_override("font_size", 22)
	control_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	controls_content.add_child(control_label)
	
	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 12)
	controls_content.add_child(control_row)
	
	control_gyro_btn = Button.new()
	control_gyro_btn.text = "GYRO"
	control_gyro_btn.custom_minimum_size = Vector2(130, 44)
	control_gyro_btn.add_theme_font_size_override("font_size", 18)
	control_gyro_btn.pressed.connect(_on_gyro_pressed)
	control_row.add_child(control_gyro_btn)
	
	control_touch_btn = Button.new()
	control_touch_btn.text = "TOUCH"
	control_touch_btn.custom_minimum_size = Vector2(130, 44)
	control_touch_btn.add_theme_font_size_override("font_size", 18)
	control_touch_btn.pressed.connect(_on_touch_pressed)
	control_row.add_child(control_touch_btn)
	
	# Tilt Sensitivity
	tilt_sensitivity_container = VBoxContainer.new()
	tilt_sensitivity_container.add_theme_constant_override("separation", 6)
	controls_content.add_child(tilt_sensitivity_container)
	
	var sensitivity_row := HBoxContainer.new()
	tilt_sensitivity_container.add_child(sensitivity_row)
	
	var sensitivity_label := Label.new()
	sensitivity_label.text = "Tilt Sensitivity"
	sensitivity_label.add_theme_font_size_override("font_size", 22)
	sensitivity_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	sensitivity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sensitivity_row.add_child(sensitivity_label)
	
	tilt_sensitivity_label = Label.new()
	tilt_sensitivity_label.text = "1.0x"
	tilt_sensitivity_label.add_theme_font_size_override("font_size", 22)
	tilt_sensitivity_label.add_theme_color_override("font_color", COLOR_ACCENT_PRIMARY)
	sensitivity_row.add_child(tilt_sensitivity_label)
	
	tilt_sensitivity_slider = HSlider.new()
	tilt_sensitivity_slider.min_value = 0.5
	tilt_sensitivity_slider.max_value = 2.0
	tilt_sensitivity_slider.step = 0.1
	tilt_sensitivity_slider.value = 1.0
	tilt_sensitivity_slider.custom_minimum_size = Vector2(250, 32)
	tilt_sensitivity_slider.value_changed.connect(_on_tilt_sensitivity_changed)
	tilt_sensitivity_container.add_child(tilt_sensitivity_slider)
	
	# Spacer before back button
	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 16)
	spacer2.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner_vbox.add_child(spacer2)
	
	# Back Button
	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(200, 56)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 22)
	_style_secondary_button(back_btn)
	inner_vbox.add_child(back_btn)
	
	_load_saved_settings()


func get_back_button() -> Button:
	return settings_panel.find_child("BackButton", true, false) as Button


func _load_saved_settings() -> void:
	if audio_manager:
		music_slider.value = audio_manager.get_music_volume()
		sfx_slider.value = audio_manager.get_sfx_volume()
		popup_check.button_pressed = audio_manager.get_show_pickup_popup()
		damage_check.button_pressed = audio_manager.get_show_damage_popup()
		haptic_check.button_pressed = audio_manager.get_haptic_enabled()
		_update_control_mode_buttons(audio_manager.get_control_mode())
	
	var settings := settings_panel.get_node_or_null("/root/SettingsManager")
	if settings:
		screen_shake_check.button_pressed = settings.get_screen_shake_enabled()
		tilt_sensitivity_slider.value = settings.get_tilt_sensitivity()
		_update_tilt_sensitivity_label(settings.get_tilt_sensitivity())


func _create_section(title_text: String) -> PanelContainer:
	var section := PanelContainer.new()
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = COLOR_BORDER
	style.set_content_margin_all(20)
	section.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	section.add_child(vbox)
	
	var header := Label.new()
	header.text = title_text
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", COLOR_ACCENT_PRIMARY)
	vbox.add_child(header)
	
	return section


func _style_slider(slider: HSlider) -> void:
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = COLOR_BG_DARK
	slider_bg.set_corner_radius_all(6)
	slider_bg.set_content_margin_all(6)
	
	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	grabber_area.set_corner_radius_all(6)
	grabber_area.set_content_margin_all(6)
	
	var grabber_area_hl := StyleBoxFlat.new()
	grabber_area_hl.bg_color = COLOR_ACCENT_PRIMARY
	grabber_area_hl.set_corner_radius_all(6)
	grabber_area_hl.set_content_margin_all(6)
	
	slider.add_theme_stylebox_override("slider", slider_bg)
	slider.add_theme_stylebox_override("grabber_area", grabber_area)
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber_area_hl)
	slider.add_theme_icon_override("grabber", _create_circle_texture(24, COLOR_ACCENT_PRIMARY))
	slider.add_theme_icon_override("grabber_highlight", _create_circle_texture(26, COLOR_ACCENT_PRIMARY.lightened(0.2)))


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


func _style_secondary_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_LIGHT
	normal.set_corner_radius_all(14)
	normal.set_border_width_all(2)
	normal.border_color = COLOR_BORDER
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_BG_LIGHT.lightened(0.1)
	hover.set_corner_radius_all(14)
	hover.set_border_width_all(2)
	hover.border_color = COLOR_ACCENT_PRIMARY
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_ACCENT_PRIMARY)


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
	audio_manager.set_music_volume(value)


func _on_sfx_changed(value: float) -> void:
	audio_manager.set_sfx_volume(value)


func _on_popup_toggled(toggled_on: bool) -> void:
	audio_manager.set_show_pickup_popup(toggled_on)


func _on_damage_toggled(toggled_on: bool) -> void:
	audio_manager.set_show_damage_popup(toggled_on)


func _on_haptic_toggled(toggled_on: bool) -> void:
	audio_manager.set_haptic_enabled(toggled_on)


func _on_screen_shake_toggled(toggled_on: bool) -> void:
	var settings := settings_panel.get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_screen_shake_enabled(toggled_on)


func _on_gyro_pressed() -> void:
	audio_manager.set_control_mode(0)
	_update_control_mode_buttons(0)


func _on_touch_pressed() -> void:
	audio_manager.set_control_mode(1)
	_update_control_mode_buttons(1)


func _on_tilt_sensitivity_changed(value: float) -> void:
	var settings := settings_panel.get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_tilt_sensitivity(value)
	_update_tilt_sensitivity_label(value)

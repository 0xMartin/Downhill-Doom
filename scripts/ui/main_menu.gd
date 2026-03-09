extends Control
## Main Menu with modern Roblox-style UI design
## Features: Dark theme, rounded corners, glow effects, smooth animations

const STATS_FILE := "user://stats.json"
const PLAYER_MODEL_SCENE := preload("res://assets/models/players/player_1.blend")
const ObjectConfigScript := preload("res://scripts/config/object_config.gd")

# ========== COLOR PALETTE ==========
const COLOR_BG_DARK := Color(0.06, 0.08, 0.12, 1.0)
const COLOR_BG_MEDIUM := Color(0.10, 0.14, 0.20, 1.0)
const COLOR_BG_LIGHT := Color(0.14, 0.18, 0.26, 1.0)
const COLOR_ACCENT_PRIMARY := Color(0.25, 0.65, 0.96, 1.0)  # Bright blue
const COLOR_ACCENT_SECONDARY := Color(0.30, 0.85, 0.55, 1.0)  # Green
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)  # Gold
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.7, 0.75, 0.85, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.65, 1.0)
const COLOR_BORDER := Color(0.25, 0.32, 0.45, 0.8)
const COLOR_GLOW := Color(0.25, 0.65, 0.96, 0.3)

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var settings_panel: Control = $SettingsPanel
@onready var stats_panel: Control = $StatsPanel
@onready var shop_panel: Control = $ShopPanel
@onready var main_content: VBoxContainer = $MainContent
@onready var player_model_container: Node3D = $PlayerViewport/SubViewport/PlayerModel

# These will be set dynamically during panel rebuild
var music_slider: HSlider
var sfx_slider: HSlider
var popup_check: CheckButton
var damage_check: CheckButton
var haptic_check: CheckButton
var screen_shake_check: CheckButton
var control_gyro_btn: Button
var control_touch_btn: Button
var tilt_sensitivity_container: VBoxContainer  # Container for tilt sensitivity (hidden in touch mode)
var tilt_sensitivity_slider: HSlider
var tilt_sensitivity_label: Label

var audio_manager: Node
var player_model_instance: Node3D
var model_rotation_speed := 0.5

# UI references created dynamically
var play_button: Button
var stats_button: Button
var settings_button: Button
var shop_button: Button
var quit_button: Button
var balance_container: HBoxContainer
var balance_label: Label

# Object preview viewports
var object_viewports: Array[SubViewportContainer] = []

# Stats sections
const OBJECT_SECTIONS := ["Trees", "Buildings", "Friend NPC", "Enemy NPC", "Enemy Building"]
var current_section_index: int = 0
var object_grid: GridContainer
var section_label: Label

# Shop sections
const SHOP_SECTIONS := ["SKINS", "BOOSTS", "CRATES"]
var shop_section_index: int = 0
var shop_content_container: Control
var shop_section_label: Label
var shop_manager: Node

# Roulette references
var roulette_container: Control
var roulette_hbox: HBoxContainer
var roulette_tween: Tween
var roulette_items: Array = []
var roulette_result: Dictionary = {}
var roulette_crate_type: String = ""

# Animation tweens
var button_tweens: Dictionary = {}

# Stats data
var stats := {
	"games_played": 0,
	"total_coins": 0,
	"max_coins": 0,
	"total_distance": 0.0,
	"max_distance": 0.0,
	"total_time": 0.0,
	"max_time": 0.0,
	"coin_balance": 0,
	"destroyed_objects": {}
}


func _ready() -> void:
	audio_manager = get_node("/root/AudioManager")
	shop_manager = get_node("/root/ShopManager")
	
	audio_manager.play_menu_music()
	_load_stats()
	
	# Rebuild UI with modern design
	_rebuild_main_menu()
	_rebuild_settings_panel()
	_rebuild_stats_panel()
	_rebuild_shop_panel()
	
	_setup_balance_display()
	_apply_safe_area_offset()
	_setup_player_model()
	_setup_speed_lines()
	
	# Connect shop manager signals
	if shop_manager:
		shop_manager.balance_changed.connect(_on_shop_balance_changed)
	
	if play_button:
		play_button.grab_focus()
	
	if animation_player.has_animation("enter"):
		animation_player.play("enter")


func _process(delta: float) -> void:
	if player_model_instance:
		player_model_instance.rotate_y(model_rotation_speed * delta)
	
	for viewport_container in object_viewports:
		if viewport_container and is_instance_valid(viewport_container):
			var viewport: SubViewport = viewport_container.get_node_or_null("SubViewport")
			if viewport:
				var model_holder: Node3D = viewport.get_node_or_null("ModelHolder")
				if model_holder:
					model_holder.rotate_y(model_rotation_speed * 0.8 * delta)


# ========== MODERN UI BUILDERS ==========

func _rebuild_main_menu() -> void:
	# Clear existing content
	for child in main_content.get_children():
		child.queue_free()
	
	main_content.add_theme_constant_override("separation", 25)
	
	# Title Section
	var title_container := VBoxContainer.new()
	title_container.add_theme_constant_override("separation", 8)
	main_content.add_child(title_container)
	
	# Main title with glow effect
	var title := Label.new()
	title.text = "DOWNHILL DOOM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	title.add_theme_color_override("font_shadow_color", COLOR_ACCENT_PRIMARY)
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_color_override("font_outline_color", COLOR_ACCENT_PRIMARY)
	title.add_theme_constant_override("outline_size", 3)
	title_container.add_child(title)
	
	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "Roll. Destroy. Survive."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 22)
	subtitle.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	title_container.add_child(subtitle)
	
	# Decorative line
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(200, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	line.color = COLOR_ACCENT_PRIMARY
	title_container.add_child(line)
	
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	main_content.add_child(spacer)
	
	# Button Grid (3x2 for 5 buttons)
	var button_grid := GridContainer.new()
	button_grid.columns = 3
	button_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button_grid.add_theme_constant_override("h_separation", 15)
	button_grid.add_theme_constant_override("v_separation", 15)
	main_content.add_child(button_grid)
	
	# Create main buttons - Row 1
	play_button = _create_modern_button("PLAY", "res://assets/svg/play.svg", COLOR_ACCENT_SECONDARY)
	play_button.pressed.connect(_on_play_button_pressed)
	button_grid.add_child(play_button)
	
	stats_button = _create_modern_button("STATS", "res://assets/svg/stats.svg", COLOR_ACCENT_PRIMARY)
	stats_button.pressed.connect(_on_stats_button_pressed)
	button_grid.add_child(stats_button)
	
	shop_button = _create_modern_button("SHOP", "res://assets/svg/shop.svg", COLOR_ACCENT_GOLD)
	shop_button.pressed.connect(_on_shop_button_pressed)
	button_grid.add_child(shop_button)
	
	# Row 2
	settings_button = _create_modern_button("SETTINGS", "res://assets/svg/settings.svg", COLOR_ACCENT_PRIMARY)
	settings_button.pressed.connect(_on_settings_button_pressed)
	button_grid.add_child(settings_button)
	
	quit_button = _create_modern_button("QUIT", "res://assets/svg/quit.svg", Color(0.8, 0.3, 0.3, 1.0))
	quit_button.pressed.connect(_on_quit_button_pressed)
	button_grid.add_child(quit_button)


func _create_modern_button(text: String, icon_path: String, accent_color: Color) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 150)
	button.flat = true
	# Set pivot to center for proper scaling animation
	button.pivot_offset = Vector2(75, 75)
	
	# Create container for icon + label
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 0
	vbox.offset_top = 0
	vbox.offset_right = 0
	vbox.offset_bottom = 0
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	button.add_child(vbox)
	
	# Icon container for centering
	var icon_container := CenterContainer.new()
	icon_container.custom_minimum_size = Vector2(52, 52)
	vbox.add_child(icon_container)
	
	# Icon
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = COLOR_TEXT_PRIMARY
	var tex: Texture2D = load(icon_path)
	if tex:
		icon.texture = tex
	icon_container.add_child(icon)
	
	# Label
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	vbox.add_child(label)
	
	# Style normal state
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_LIGHT
	normal.set_corner_radius_all(20)
	normal.set_border_width_all(3)
	normal.border_color = COLOR_BORDER
	normal.shadow_color = Color(0, 0, 0, 0.4)
	normal.shadow_size = 6
	normal.shadow_offset = Vector2(0, 4)
	
	# Style hover state
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_BG_LIGHT.lightened(0.1)
	hover.set_corner_radius_all(20)
	hover.set_border_width_all(3)
	hover.border_color = accent_color
	hover.shadow_color = accent_color * Color(1, 1, 1, 0.4)
	hover.shadow_size = 12
	hover.shadow_offset = Vector2(0, 4)
	
	# Style pressed state
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = accent_color.darkened(0.3)
	pressed.set_corner_radius_all(20)
	pressed.set_border_width_all(3)
	pressed.border_color = accent_color
	pressed.shadow_size = 4
	pressed.shadow_offset = Vector2(0, 2)
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	
	# Connect hover animations
	button.mouse_entered.connect(_on_button_hover_enter.bind(button, accent_color))
	button.mouse_exited.connect(_on_button_hover_exit.bind(button))
	
	return button


func _on_button_hover_enter(button: Button, _accent_color: Color) -> void:
	if button_tweens.has(button) and button_tweens[button]:
		button_tweens[button].kill()
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(button, "scale", Vector2(1.08, 1.08), 0.15)
	button_tweens[button] = tween


func _on_button_hover_exit(button: Button) -> void:
	if button_tweens.has(button) and button_tweens[button]:
		button_tweens[button].kill()
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(button, "scale", Vector2.ONE, 0.2)
	button_tweens[button] = tween


func _rebuild_settings_panel() -> void:
	# Clear existing content
	for child in settings_panel.get_children():
		if child.name != "Background":
			child.queue_free()
	
	# Update background
	var bg: ColorRect = settings_panel.get_node("Background")
	bg.color = Color(0, 0, 0, 0.92)
	
	# Make panel fullscreen like stats
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
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
	
	# Title with glow (same style as stats)
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
	var audio_card := _create_settings_section("AUDIO")
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
	_style_modern_slider(music_slider)
	music_slider.value_changed.connect(_on_music_slider_value_changed)
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
	_style_modern_slider(sfx_slider)
	sfx_slider.value_changed.connect(_on_sfx_slider_value_changed)
	sfx_row.add_child(sfx_slider)
	
	# Display Section
	var display_card := _create_settings_section("DISPLAY")
	inner_vbox.add_child(display_card)
	
	var display_content := display_card.get_child(0)
	
	# Popup check
	popup_check = CheckButton.new()
	popup_check.text = "Show Pickup Popups"
	popup_check.button_pressed = true
	popup_check.add_theme_font_size_override("font_size", 22)
	popup_check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	popup_check.toggled.connect(_on_popup_check_toggled)
	display_content.add_child(popup_check)
	
	# Damage check
	damage_check = CheckButton.new()
	damage_check.text = "Show Damage Numbers"
	damage_check.button_pressed = true
	damage_check.add_theme_font_size_override("font_size", 22)
	damage_check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	damage_check.toggled.connect(_on_damage_check_toggled)
	display_content.add_child(damage_check)
	
	# Haptic check
	haptic_check = CheckButton.new()
	haptic_check.text = "Haptic Feedback"
	haptic_check.button_pressed = true
	haptic_check.add_theme_font_size_override("font_size", 22)
	haptic_check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	haptic_check.toggled.connect(_on_haptic_check_toggled)
	display_content.add_child(haptic_check)
	
	# Screen shake check
	screen_shake_check = CheckButton.new()
	screen_shake_check.text = "Screen Shake"
	screen_shake_check.button_pressed = true
	screen_shake_check.add_theme_font_size_override("font_size", 22)
	screen_shake_check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	screen_shake_check.toggled.connect(_on_screen_shake_check_toggled)
	display_content.add_child(screen_shake_check)
	
	# Controls Section
	var controls_card := _create_settings_section("CONTROLS")
	inner_vbox.add_child(controls_card)
	
	var controls_content := controls_card.get_child(0)
	
	# Control mode label
	var control_label := Label.new()
	control_label.text = "Control Mode"
	control_label.add_theme_font_size_override("font_size", 22)
	control_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	controls_content.add_child(control_label)
	
	# Control mode buttons row
	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 12)
	controls_content.add_child(control_row)
	
	control_gyro_btn = Button.new()
	control_gyro_btn.text = "GYRO"
	control_gyro_btn.custom_minimum_size = Vector2(130, 44)
	control_gyro_btn.add_theme_font_size_override("font_size", 18)
	control_gyro_btn.pressed.connect(_on_control_gyro_pressed)
	control_row.add_child(control_gyro_btn)
	
	control_touch_btn = Button.new()
	control_touch_btn.text = "TOUCH"
	control_touch_btn.custom_minimum_size = Vector2(130, 44)
	control_touch_btn.add_theme_font_size_override("font_size", 18)
	control_touch_btn.pressed.connect(_on_control_touch_pressed)
	control_row.add_child(control_touch_btn)
	
	# Tilt Sensitivity (only visible in gyro mode)
	tilt_sensitivity_container = VBoxContainer.new()
	tilt_sensitivity_container.add_theme_constant_override("separation", 6)
	controls_content.add_child(tilt_sensitivity_container)
	
	# Sensitivity label row with value
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
	
	# Sensitivity slider
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
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(200, 56)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 22)
	_style_secondary_button(back_btn)
	back_btn.pressed.connect(_on_settings_back_pressed)
	inner_vbox.add_child(back_btn)
	
	# Load saved settings from audio manager (which delegates to SettingsManager)
	if audio_manager:
		music_slider.value = audio_manager.get_music_volume()
		sfx_slider.value = audio_manager.get_sfx_volume()
		popup_check.button_pressed = audio_manager.get_show_pickup_popup()
		damage_check.button_pressed = audio_manager.get_show_damage_popup()
		haptic_check.button_pressed = audio_manager.get_haptic_enabled()
		_update_control_mode_buttons(audio_manager.get_control_mode())
	
	# Load settings from SettingsManager for new settings
	var settings := get_node_or_null("/root/SettingsManager")
	if settings:
		screen_shake_check.button_pressed = settings.get_screen_shake_enabled()
		tilt_sensitivity_slider.value = settings.get_tilt_sensitivity()
		_update_tilt_sensitivity_label(settings.get_tilt_sensitivity())


func _create_settings_section(title_text: String) -> PanelContainer:
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


func _style_modern_slider(slider: HSlider) -> void:
	# Background track (unfilled portion)
	var slider_bg := StyleBoxFlat.new()
	slider_bg.bg_color = COLOR_BG_DARK
	slider_bg.set_corner_radius_all(6)
	slider_bg.set_content_margin_all(6)
	
	# Filled portion (grabber area) - the bar from left to handle
	var grabber_area := StyleBoxFlat.new()
	grabber_area.bg_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	grabber_area.set_corner_radius_all(6)
	grabber_area.set_content_margin_all(6)
	
	# Filled portion highlighted
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


func _rebuild_stats_panel() -> void:
	# Clear existing content (except Background)
	for child in stats_panel.get_children():
		if child.name != "Background":
			child.queue_free()
	
	# Update background
	var bg: ColorRect = stats_panel.get_node("Background")
	bg.color = Color(0, 0, 0, 0.92)
	
	# Make panel fullscreen like settings
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
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
	stats_panel.add_child(center_vbox)
	
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
	inner_vbox.add_theme_constant_override("separation", 12)
	card.add_child(inner_vbox)
	
	# Title with glow (same style as settings)
	var title := Label.new()
	title.text = "STATISTICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	title.add_theme_color_override("font_outline_color", COLOR_ACCENT_PRIMARY)
	title.add_theme_constant_override("outline_size", 2)
	inner_vbox.add_child(title)
	
	# Decoration under title (same as settings)
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
	
	# Global Stats Card
	var global_card := _create_stats_card()
	inner_vbox.add_child(global_card)
	
	var global_content := VBoxContainer.new()
	global_content.add_theme_constant_override("separation", 8)
	global_card.add_child(global_content)
	
	_populate_global_stats(global_content)
	
	# Separator
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 8
	sep.modulate = COLOR_BORDER
	inner_vbox.add_child(sep)
	
	# Objects Section Header
	var obj_header := Label.new()
	obj_header.text = "DESTROYED OBJECTS"
	obj_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_header.add_theme_font_size_override("font_size", 22)
	obj_header.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	inner_vbox.add_child(obj_header)
	
	# Section Navigation
	var nav_container := HBoxContainer.new()
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.add_theme_constant_override("separation", 15)
	inner_vbox.add_child(nav_container)
	
	var prev_btn := _create_nav_button("<")
	prev_btn.pressed.connect(_on_section_prev)
	nav_container.add_child(prev_btn)
	
	section_label = Label.new()
	section_label.text = OBJECT_SECTIONS[current_section_index]
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_label.custom_minimum_size = Vector2(180, 40)
	section_label.add_theme_font_size_override("font_size", 24)
	section_label.add_theme_color_override("font_color", COLOR_ACCENT_PRIMARY)
	nav_container.add_child(section_label)
	
	var next_btn := _create_nav_button(">")
	next_btn.pressed.connect(_on_section_next)
	nav_container.add_child(next_btn)
	
	# Scrollable Object Grid
	var scroll := ScrollContainer.new()
	var scroll_height: float = maxf(350.0, screen_size.y * 0.45)
	scroll.custom_minimum_size = Vector2(panel_width - 50, scroll_height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner_vbox.add_child(scroll)
	
	object_grid = GridContainer.new()
	object_grid.columns = 1
	object_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_grid.add_theme_constant_override("v_separation", 12)
	object_grid.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow touch events to pass through for scrolling
	scroll.add_child(object_grid)
	
	_populate_object_cards(object_grid)
	
	# Back Button
	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(180, 50)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 20)
	_style_secondary_button(back_btn)
	back_btn.pressed.connect(_on_stats_back_pressed)
	inner_vbox.add_child(back_btn)


func _create_stats_card() -> PanelContainer:
	var card := PanelContainer.new()
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(1)
	style.border_color = COLOR_BORDER
	style.set_content_margin_all(15)
	card.add_theme_stylebox_override("panel", style)
	
	return card


func _create_nav_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(50, 44)
	btn.add_theme_font_size_override("font_size", 26)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_LIGHT
	normal.set_corner_radius_all(12)
	normal.set_border_width_all(2)
	normal.border_color = COLOR_BORDER
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	hover.set_corner_radius_all(12)
	hover.set_border_width_all(2)
	hover.border_color = COLOR_ACCENT_PRIMARY
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT_PRIMARY)
	
	return btn


func _populate_global_stats(container: VBoxContainer) -> void:
	var coin_icon: Texture2D = load("res://assets/svg/coin.svg")
	var distance_icon: Texture2D = load("res://assets/svg/distance.svg")
	var games_count: int = stats.get("games_played", 0)
	
	# Games played
	var games_row := _create_stat_row("Games Played", str(games_count), null, COLOR_TEXT_SECONDARY)
	container.add_child(games_row)
	
	# Coins stats
	var max_c: int = stats.get("max_coins", 0)
	var total_c: int = stats.get("total_coins", 0)
	var avg_c: int = int(total_c / games_count) if games_count > 0 else 0
	var coins_text := "Best: %d  |  Avg: %d  |  Total: %d" % [max_c, avg_c, total_c]
	var coins_row := _create_stat_row("Coins", coins_text, coin_icon, COLOR_ACCENT_GOLD)
	container.add_child(coins_row)
	
	# Distance stats
	var max_d: float = stats.get("max_distance", 0.0)
	var total_d: float = stats.get("total_distance", 0.0)
	var avg_d: float = total_d / games_count if games_count > 0 else 0.0
	var dist_text := "Best: %dm  |  Avg: %dm" % [int(max_d), int(avg_d)]
	var dist_row := _create_stat_row("Distance", dist_text, distance_icon, COLOR_ACCENT_PRIMARY)
	container.add_child(dist_row)
	
	# Time stats
	var max_t: float = stats.get("max_time", 0.0)
	var total_t: float = stats.get("total_time", 0.0)
	var avg_t: float = total_t / games_count if games_count > 0 else 0.0
	var time_text := "Best: %s  |  Avg: %s  |  Total: %s" % [_format_time(max_t), _format_time(avg_t), _format_time(total_t)]
	var time_row := _create_stat_row("Time", time_text, null, COLOR_ACCENT_SECONDARY)
	container.add_child(time_row)


func _create_stat_row(label_text: String, value_text: String, icon: Texture2D, accent: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	
	if icon:
		var tex := TextureRect.new()
		tex.custom_minimum_size = Vector2(24, 24)
		tex.texture = icon
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.modulate = accent
		row.add_child(tex)
	else:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(24, 24)
		row.add_child(spacer)
	
	var lbl := Label.new()
	lbl.text = label_text + ": "
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", accent)
	row.add_child(lbl)
	
	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	row.add_child(val)
	
	return row


func _format_time(time_seconds: float) -> String:
	var total_seconds := int(time_seconds)
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var seconds := total_seconds % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]


func _populate_object_cards(grid: GridContainer) -> void:
	for child in grid.get_children():
		child.queue_free()
	object_viewports.clear()
	
	var objects: Array = []
	match current_section_index:
		0:
			objects = ObjectConfigScript.get_trees()
		1:
			objects = ObjectConfigScript.get_buildings() + ObjectConfigScript.get_large_buildings()
		2:
			objects = ObjectConfigScript.get_npcs_friend()
		3:
			# Include both ground-based and aerial enemy NPCs (planes)
			objects = ObjectConfigScript.get_objects_by_category(ObjectConfigScript.Category.NPC_ENEMY)
			objects += ObjectConfigScript.get_objects_by_category(ObjectConfigScript.Category.NPC_AERIAL)
		4:
			objects = ObjectConfigScript.get_building_enemies()
	
	var destroyed: Dictionary = stats.get("destroyed_objects", {})
	
	if objects.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No objects in this category"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 18)
		empty_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		grid.add_child(empty_label)
		return
	
	for obj_data in objects:
		var card := _create_object_card(obj_data, destroyed.get(obj_data.id, 0))
		grid.add_child(card)


func _create_object_card(obj_data: RefCounted, kill_count: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(620, 120)
	card.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow touch events to pass through for scrolling
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(2)
	style.border_color = COLOR_BORDER if kill_count > 0 else Color(0.3, 0.3, 0.35, 0.5)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass through touch events
	card.add_child(hbox)
	
	# 3D Preview
	var preview := _create_3d_preview(obj_data, kill_count)
	hbox.add_child(preview)
	object_viewports.append(preview)
	
	# Info section
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass through touch events
	info.add_theme_constant_override("separation", 6)
	hbox.add_child(info)
	
	# Object name
	var name_label := Label.new()
	name_label.text = obj_data.display_name if kill_count > 0 else "???"
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY if kill_count > 0 else COLOR_TEXT_MUTED)
	info.add_child(name_label)
	
	# Stats row
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 20)
	stats_row.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass through touch events
	info.add_child(stats_row)
	
	# Coins
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 5)
	coin_row.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass through touch events
	stats_row.add_child(coin_row)
	
	var coin_icon := TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(20, 20)
	coin_icon.texture = load("res://assets/svg/coin.svg")
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = COLOR_ACCENT_GOLD if kill_count > 0 else COLOR_TEXT_MUTED
	coin_icon.mouse_filter = Control.MOUSE_FILTER_PASS  # Pass through touch events
	coin_row.add_child(coin_icon)
	
	var coin_label := Label.new()
	coin_label.text = "%d" % obj_data.coins if kill_count > 0 else "?"
	coin_label.add_theme_font_size_override("font_size", 16)
	coin_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD if kill_count > 0 else COLOR_TEXT_MUTED)
	coin_row.add_child(coin_label)
	
	# Spawn chance
	var spawn_label := Label.new()
	spawn_label.text = "Spawn: %.0f%%" % (obj_data.spawn_chance * 100) if kill_count > 0 else "Spawn: ?%"
	spawn_label.add_theme_font_size_override("font_size", 15)
	spawn_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY if kill_count > 0 else COLOR_TEXT_MUTED)
	stats_row.add_child(spawn_label)
	
	# Supercharge indicator for large buildings and enemy buildings (spikes)
	if obj_data.category == ObjectConfigScript.Category.BUILDING_LARGE or obj_data.category == ObjectConfigScript.Category.BUILDING_ENEMY:
		var supercharge_label := Label.new()
		supercharge_label.text = "ARMORED" if kill_count > 0 else "???"
		supercharge_label.add_theme_font_size_override("font_size", 14)
		supercharge_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD if kill_count > 0 else COLOR_TEXT_MUTED)
		stats_row.add_child(supercharge_label)
	
	# Kill count badge
	var kill_badge := _create_kill_badge(kill_count)
	info.add_child(kill_badge)
	
	return card


func _create_kill_badge(count: int) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	container.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow touch events to pass through for scrolling
	
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow touch events to pass through for scrolling
	var badge_style := StyleBoxFlat.new()
	badge_style.set_corner_radius_all(10)
	badge_style.set_content_margin_all(6)
	badge_style.content_margin_left = 12
	badge_style.content_margin_right = 12
	
	if count > 0:
		badge_style.bg_color = COLOR_ACCENT_SECONDARY.darkened(0.5)
		badge_style.border_color = COLOR_ACCENT_SECONDARY
	else:
		badge_style.bg_color = COLOR_BG_LIGHT
		badge_style.border_color = COLOR_BORDER
	badge_style.set_border_width_all(1)
	badge.add_theme_stylebox_override("panel", badge_style)
	
	var label := Label.new()
	label.text = "Destroyed: %d" % count
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COLOR_ACCENT_SECONDARY if count > 0 else COLOR_TEXT_MUTED)
	badge.add_child(label)
	
	container.add_child(badge)
	return container


func _create_3d_preview(obj_data: RefCounted, kill_count: int) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(100, 100)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow touch events to pass through for scrolling
	
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.transparent_bg = true
	viewport.size = Vector2i(100, 100)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.own_world_3d = true
	container.add_child(viewport)
	
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1, 1)
	
	var camera := Camera3D.new()
	camera.name = "Camera"
	camera.environment = env
	camera.fov = 35.0
	camera.near = 0.01
	camera.far = 100.0
	viewport.add_child(camera)
	
	var light := DirectionalLight3D.new()
	light.transform.basis = Basis(Vector3(1, 0, 0), -0.5) * Basis(Vector3(0, 1, 0), 0.3)
	viewport.add_child(light)
	
	var holder := Node3D.new()
	holder.name = "ModelHolder"
	viewport.add_child(holder)
	
	if obj_data.model_path and obj_data.model_path != "":
		var model_scene: PackedScene = load(obj_data.model_path)
		if model_scene:
			var model := model_scene.instantiate()
			holder.add_child(model)
			
			var combined_aabb := AABB()
			var first := true
			for mesh_inst: MeshInstance3D in _find_all_mesh_instances(model):
				if mesh_inst.mesh == null:
					continue
				var mesh_aabb := mesh_inst.mesh.get_aabb()
				var local_transform: Transform3D = mesh_inst.transform
				var parent: Node = mesh_inst.get_parent()
				while parent != null and parent != model:
					if parent is Node3D:
						local_transform = (parent as Node3D).transform * local_transform
					parent = parent.get_parent()
				mesh_aabb = local_transform * mesh_aabb
				if first:
					combined_aabb = mesh_aabb
					first = false
				else:
					combined_aabb = combined_aabb.merge(mesh_aabb)
			
			var object_height: float = obj_data.target_height if obj_data.target_height > 0 else 1.0
			var aabb_size := combined_aabb.size
			var aabb_center := combined_aabb.get_center()
			
			if aabb_size.length() > 0.01:
				object_height = maxf(maxf(aabb_size.x, aabb_size.y), aabb_size.z)
			
			var half_fov := deg_to_rad(camera.fov / 2.0)
			var distance := (object_height / 2.0) / tan(half_fov) * 1.4
			distance = clampf(distance, 0.5, 50.0)
			
			if aabb_size.length() > 0.01:
				holder.position.y = -aabb_center.y
			
			# Position camera on Z axis looking at origin (camera default looks -Z)
			camera.position = Vector3(0, 0, distance)
			
			if kill_count == 0:
				_apply_silhouette_material(model)
	
	return container


func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_find_all_mesh_instances(child))
	return result


func _apply_silhouette_material(node: Node) -> void:
	var silhouette_mat := StandardMaterial3D.new()
	silhouette_mat.albedo_color = Color(0.15, 0.18, 0.25, 1.0)
	silhouette_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	for mesh_inst: MeshInstance3D in _find_all_mesh_instances(node):
		mesh_inst.material_override = silhouette_mat


func _setup_player_model() -> void:
	if not player_model_container:
		return
	
	# Remove old model if exists
	if player_model_instance:
		player_model_instance.queue_free()
		player_model_instance = null
	
	# Load selected skin from ShopManager
	var model_scene: PackedScene = null
	var texture_path: String = ""
	
	if shop_manager:
		var model_path: String = shop_manager.get_selected_skin_model_path()
		texture_path = shop_manager.get_selected_skin_texture_path()
		
		if ResourceLoader.exists(model_path):
			model_scene = load(model_path)
	
	# Fallback to default if no custom skin
	if not model_scene:
		model_scene = PLAYER_MODEL_SCENE
	
	if model_scene:
		player_model_instance = model_scene.instantiate()
		player_model_instance.scale = Vector3(0.3, 0.3, 0.3)
		player_model_container.add_child(player_model_instance)
		
		# Apply texture if this is a texture skin
		if texture_path and ResourceLoader.exists(texture_path):
			var texture: Texture2D = load(texture_path)
			if texture:
				_apply_skin_texture_to_model(player_model_instance, texture)
		
		# Apply unshaded material to disable shadows/reflections
		_apply_unshaded_material(player_model_instance)


func _apply_skin_texture_to_model(node: Node, texture: Texture2D) -> void:
	for mesh_inst: MeshInstance3D in _find_all_mesh_instances(node):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				mesh_inst.set_surface_override_material(i, material)


func _apply_unshaded_material(node: Node) -> void:
	## Apply unshaded material to disable lighting effects on preview models
	for mesh_inst: MeshInstance3D in _find_all_mesh_instances(node):
		# Get original material to preserve color
		var original_mat: Material = null
		if mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
			original_mat = mesh_inst.mesh.surface_get_material(0)
		
		var unshaded_mat := StandardMaterial3D.new()
		unshaded_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		# Try to preserve original albedo color/texture
		if original_mat and original_mat is StandardMaterial3D:
			var orig_std: StandardMaterial3D = original_mat as StandardMaterial3D
			unshaded_mat.albedo_color = orig_std.albedo_color
			if orig_std.albedo_texture:
				unshaded_mat.albedo_texture = orig_std.albedo_texture
		else:
			unshaded_mat.albedo_color = Color(0.8, 0.8, 0.8, 1.0)
		
		mesh_inst.material_override = unshaded_mat


# ========== SHOP PANEL ==========

func _rebuild_shop_panel() -> void:
	# Clear existing content (except Background)
	for child in shop_panel.get_children():
		if child.name != "Background":
			child.queue_free()
	
	# Update background
	var bg: ColorRect = shop_panel.get_node("Background")
	bg.color = Color(0, 0, 0, 0.95)
	
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_width: float = minf(720.0, screen_size.x * 0.95)
	var panel_height: float = minf(screen_size.y * 0.92, screen_size.y - 40)
	
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
	shop_panel.add_child(center_vbox)
	
	# Create main card container
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(panel_width, panel_height)
	
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_BG_MEDIUM
	card_style.set_corner_radius_all(24)
	card_style.set_border_width_all(2)
	card_style.border_color = COLOR_ACCENT_GOLD.darkened(0.3)
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	card_style.shadow_size = 20
	card_style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", card_style)
	center_vbox.add_child(card)
	
	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 10)
	card.add_child(inner_vbox)
	
	# Title with gold glow
	var title := Label.new()
	title.text = "SHOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	title.add_theme_color_override("font_outline_color", COLOR_ACCENT_GOLD.darkened(0.3))
	title.add_theme_constant_override("outline_size", 2)
	inner_vbox.add_child(title)
	
	# Balance display in shop
	var balance_row := HBoxContainer.new()
	balance_row.alignment = BoxContainer.ALIGNMENT_CENTER
	balance_row.add_theme_constant_override("separation", 10)
	inner_vbox.add_child(balance_row)
	
	var coin_icon := TextureRect.new()
	coin_icon.texture = load("res://assets/svg/coin.svg")
	coin_icon.custom_minimum_size = Vector2(28, 28)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = COLOR_ACCENT_GOLD
	balance_row.add_child(coin_icon)
	
	var shop_balance_label := Label.new()
	shop_balance_label.name = "ShopBalanceLabel"
	shop_balance_label.text = _format_balance(stats.get("coin_balance", 0))
	shop_balance_label.add_theme_font_size_override("font_size", 28)
	shop_balance_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	balance_row.add_child(shop_balance_label)
	
	# Section Navigation
	var nav_container := HBoxContainer.new()
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.add_theme_constant_override("separation", 15)
	inner_vbox.add_child(nav_container)
	
	var prev_btn := _create_nav_button("<")
	prev_btn.pressed.connect(_on_shop_section_prev)
	nav_container.add_child(prev_btn)
	
	shop_section_label = Label.new()
	shop_section_label.text = SHOP_SECTIONS[shop_section_index]
	shop_section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_section_label.custom_minimum_size = Vector2(140, 40)
	shop_section_label.add_theme_font_size_override("font_size", 24)
	shop_section_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	nav_container.add_child(shop_section_label)
	
	var next_btn := _create_nav_button(">")
	next_btn.pressed.connect(_on_shop_section_next)
	nav_container.add_child(next_btn)
	
	# Content area
	var scroll := ScrollContainer.new()
	var scroll_height: float = maxf(400.0, screen_size.y * 0.55)
	scroll.custom_minimum_size = Vector2(panel_width - 50, scroll_height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner_vbox.add_child(scroll)
	
	shop_content_container = VBoxContainer.new()
	shop_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_content_container.add_theme_constant_override("separation", 12)
	scroll.add_child(shop_content_container)
	
	_populate_shop_section()
	
	# Back Button
	var back_btn := Button.new()
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(180, 50)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 20)
	_style_secondary_button(back_btn)
	back_btn.pressed.connect(_on_shop_back_pressed)
	inner_vbox.add_child(back_btn)


func _populate_shop_section() -> void:
	# Clear existing content
	for child in shop_content_container.get_children():
		child.queue_free()
	
	match shop_section_index:
		0:  # Skins
			_populate_skins_section()
		1:  # Boosts
			_populate_boosts_section()
		2:  # Crates
			_populate_crates_section()


func _populate_skins_section() -> void:
	if not shop_manager:
		return
	
	# Model-based skins (player_1 to player_9)
	var model_header := Label.new()
	model_header.text = "MODEL SKINS"
	model_header.add_theme_font_size_override("font_size", 20)
	model_header.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	shop_content_container.add_child(model_header)
	
	var model_skins := ["player_1", "player_2", "player_3", "player_4", "player_5", "player_6", "player_7", "player_8", "player_9"]
	for skin_id in model_skins:
		var card := _create_skin_card(skin_id, false)
		shop_content_container.add_child(card)
	
	# Texture skins from crates
	var texture_header := Label.new()
	texture_header.text = "SPECIAL SKINS (from crates)"
	texture_header.add_theme_font_size_override("font_size", 20)
	texture_header.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	shop_content_container.add_child(texture_header)
	
	var texture_skins: Array = shop_manager.available_texture_skins
	if texture_skins.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No special skins available yet"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		shop_content_container.add_child(empty_label)
	else:
		for skin_id in texture_skins:
			var card := _create_skin_card(skin_id, true)
			shop_content_container.add_child(card)


func _create_skin_card(skin_id: String, is_texture: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 80)
	
	var is_owned: bool = shop_manager.is_skin_owned(skin_id)
	var is_selected: bool = shop_manager.get_selected_skin() == skin_id
	var price: int = shop_manager.get_skin_price(skin_id)
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	if is_selected:
		style.border_color = COLOR_ACCENT_SECONDARY
	elif is_owned:
		style.border_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	else:
		style.border_color = COLOR_BORDER
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	card.add_child(hbox)
	
	# Skin name
	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_vbox)
	
	var display_name := skin_id.replace("_", " ").capitalize()
	if is_texture:
		display_name += " ★"
	
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY if is_owned else COLOR_TEXT_MUTED)
	name_vbox.add_child(name_label)
	
	# Status or price
	var status_label := Label.new()
	if is_selected:
		status_label.text = "EQUIPPED"
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_SECONDARY)
	elif is_owned:
		status_label.text = "OWNED"
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_PRIMARY)
	elif is_texture:
		status_label.text = "CRATE ONLY"
		status_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	else:
		status_label.text = "%s coins" % _format_balance(price)
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	status_label.add_theme_font_size_override("font_size", 14)
	name_vbox.add_child(status_label)
	
	# Action button
	var action_btn := Button.new()
	action_btn.custom_minimum_size = Vector2(100, 40)
	
	if is_selected:
		action_btn.text = "SELECTED"
		action_btn.disabled = true
	elif is_owned:
		action_btn.text = "SELECT"
		action_btn.pressed.connect(_on_skin_select.bind(skin_id))
	elif not is_texture and price > 0:
		action_btn.text = "BUY"
		action_btn.pressed.connect(_on_skin_buy.bind(skin_id))
	else:
		action_btn.text = "LOCKED"
		action_btn.disabled = true
	
	_style_shop_button(action_btn, is_owned and not is_selected)
	hbox.add_child(action_btn)
	
	return card


func _populate_boosts_section() -> void:
	if not shop_manager:
		return
	
	# Selected boosts info
	var selected: Array = shop_manager.get_selected_boosts()
	var selected_label := Label.new()
	selected_label.text = "Selected for next game: %d/2" % selected.size()
	selected_label.add_theme_font_size_override("font_size", 18)
	selected_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_content_container.add_child(selected_label)
	
	# Boost cards
	var boost_ids: Array = shop_manager.BOOST_PRICES.keys()
	for boost_id in boost_ids:
		var card := _create_boost_card(boost_id)
		shop_content_container.add_child(card)


func _create_boost_card(boost_id: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 90)
	
	var owned_count: int = shop_manager.get_boost_count(boost_id)
	var is_selected: bool = shop_manager.is_boost_selected(boost_id)
	var price: int = shop_manager.BOOST_PRICES.get(boost_id, 0)
	var display_name: String = shop_manager.BOOST_NAMES.get(boost_id, boost_id)
	var icon_path: String = shop_manager.BOOST_ICONS.get(boost_id, "")
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	if is_selected:
		style.border_color = COLOR_ACCENT_SECONDARY
	elif owned_count > 0:
		style.border_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	else:
		style.border_color = COLOR_BORDER
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)
	
	# Icon
	if icon_path and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon)
	
	# Info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	info_vbox.add_child(name_label)
	
	var owned_label := Label.new()
	owned_label.text = "Owned: %d" % owned_count
	owned_label.add_theme_font_size_override("font_size", 14)
	owned_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY if owned_count > 0 else COLOR_TEXT_MUTED)
	info_vbox.add_child(owned_label)
	
	var price_label := Label.new()
	price_label.text = "%s coins" % _format_balance(price)
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	info_vbox.add_child(price_label)
	
	# Buttons
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(btn_vbox)
	
	# Select/deselect button
	var select_btn := Button.new()
	select_btn.custom_minimum_size = Vector2(90, 32)
	if is_selected:
		select_btn.text = "REMOVE"
		select_btn.pressed.connect(_on_boost_toggle.bind(boost_id))
	elif owned_count > 0:
		select_btn.text = "USE"
		select_btn.pressed.connect(_on_boost_toggle.bind(boost_id))
	else:
		select_btn.text = "USE"
		select_btn.disabled = true
	_style_shop_button(select_btn, is_selected)
	btn_vbox.add_child(select_btn)
	
	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "BUY"
	buy_btn.custom_minimum_size = Vector2(90, 32)
	buy_btn.pressed.connect(_on_boost_buy.bind(boost_id))
	_style_shop_button(buy_btn, false)
	btn_vbox.add_child(buy_btn)
	
	return card


func _populate_crates_section() -> void:
	if not shop_manager:
		return
	
	var crate_types := ["basic", "premium", "legendary"]
	for crate_type in crate_types:
		var card := _create_crate_card(crate_type)
		shop_content_container.add_child(card)


func _create_crate_card(crate_type: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 120)
	
	var owned_count: int = shop_manager.get_crate_count(crate_type)
	var price: int = shop_manager.CRATE_PRICES.get(crate_type, 0)
	var display_name: String = shop_manager.CRATE_NAMES.get(crate_type, crate_type)
	var icon_path: String = shop_manager.CRATE_ICONS.get(crate_type, "")
	var chances: Dictionary = shop_manager.CRATE_DROP_CHANCES.get(crate_type, {})
	
	var accent_color := COLOR_TEXT_SECONDARY
	match crate_type:
		"basic":
			accent_color = Color(0.7, 0.7, 0.7)
		"premium":
			accent_color = COLOR_ACCENT_PRIMARY
		"legendary":
			accent_color = COLOR_ACCENT_GOLD
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = accent_color.darkened(0.3)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	card.add_child(hbox)
	
	# Icon
	if icon_path and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon)
	
	# Info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", accent_color)
	info_vbox.add_child(name_label)
	
	var owned_label := Label.new()
	owned_label.text = "Owned: %d" % owned_count
	owned_label.add_theme_font_size_override("font_size", 14)
	owned_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	info_vbox.add_child(owned_label)
	
	# Drop chances
	var chances_label := Label.new()
	chances_label.text = "Boost: %.0f%% | Crate: %.0f%% | Skin: %.0f%%" % [
		chances.get("boost", 0) * 100,
		chances.get("crate", 0) * 100,
		chances.get("skin", 0) * 100
	]
	chances_label.add_theme_font_size_override("font_size", 12)
	chances_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	info_vbox.add_child(chances_label)
	
	var price_label := Label.new()
	price_label.text = "%s coins" % _format_balance(price)
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	info_vbox.add_child(price_label)
	
	# Buttons
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(btn_vbox)
	
	# Open button
	var open_btn := Button.new()
	open_btn.text = "OPEN"
	open_btn.custom_minimum_size = Vector2(90, 36)
	open_btn.disabled = owned_count <= 0
	open_btn.pressed.connect(_on_crate_open.bind(crate_type))
	_style_shop_button(open_btn, owned_count > 0)
	btn_vbox.add_child(open_btn)
	
	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "BUY"
	buy_btn.custom_minimum_size = Vector2(90, 36)
	buy_btn.pressed.connect(_on_crate_buy.bind(crate_type))
	_style_shop_button(buy_btn, false)
	btn_vbox.add_child(buy_btn)
	
	return card


func _style_shop_button(button: Button, is_active: bool) -> void:
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	
	if is_active:
		normal.bg_color = COLOR_ACCENT_SECONDARY.darkened(0.3)
		normal.border_color = COLOR_ACCENT_SECONDARY
		hover.bg_color = COLOR_ACCENT_SECONDARY.darkened(0.1)
		hover.border_color = COLOR_ACCENT_SECONDARY.lightened(0.2)
	else:
		normal.bg_color = COLOR_BG_LIGHT
		normal.border_color = COLOR_BORDER
		hover.bg_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
		hover.border_color = COLOR_ACCENT_PRIMARY
	
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(2)
	hover.set_corner_radius_all(8)
	hover.set_border_width_all(2)
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)


# ========== ROULETTE ANIMATION ==========

func _show_crate_roulette(crate_type: String) -> void:
	roulette_crate_type = crate_type
	roulette_items = shop_manager.generate_roulette_items(crate_type, 35)
	
	# Create roulette overlay
	roulette_container = Control.new()
	roulette_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(roulette_container)
	
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	roulette_container.add_child(bg)
	
	# Center container
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.offset_left = -300
	center.offset_right = 300
	center.offset_top = -150
	center.offset_bottom = 150
	center.add_theme_constant_override("separation", 20)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	roulette_container.add_child(center)
	
	# Title
	var title := Label.new()
	title.text = "OPENING %s" % shop_manager.CRATE_NAMES.get(crate_type, "Crate").to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	center.add_child(title)
	
	# Roulette window with mask
	var window_container := Control.new()
	window_container.custom_minimum_size = Vector2(500, 100)
	window_container.clip_contents = true
	center.add_child(window_container)
	
	# Center marker
	var marker := ColorRect.new()
	marker.color = COLOR_ACCENT_GOLD
	marker.custom_minimum_size = Vector2(4, 100)
	marker.set_anchors_preset(Control.PRESET_CENTER)
	marker.anchor_left = 0.5
	marker.anchor_right = 0.5
	marker.offset_left = -2
	marker.offset_right = 2
	window_container.add_child(marker)
	
	# Items container
	roulette_hbox = HBoxContainer.new()
	roulette_hbox.add_theme_constant_override("separation", 10)
	roulette_hbox.position = Vector2(0, 0)
	window_container.add_child(roulette_hbox)
	
	# Populate items
	for i in range(roulette_items.size()):
		var item := _create_roulette_item(roulette_items[i])
		roulette_hbox.add_child(item)
	
	# Start animation
	_animate_roulette()


func _create_roulette_item(item_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(90, 90)
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(10)
	style.set_border_width_all(2)
	
	match item_data.get("type", ""):
		"boost":
			style.border_color = COLOR_ACCENT_PRIMARY
		"crate":
			style.border_color = COLOR_ACCENT_SECONDARY
		"skin":
			style.border_color = COLOR_ACCENT_GOLD
	
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	
	# Icon
	var icon_path := ""
	match item_data.get("type", ""):
		"boost":
			icon_path = shop_manager.BOOST_ICONS.get(item_data.get("id", ""), "")
		"crate":
			icon_path = shop_manager.CRATE_ICONS.get(item_data.get("id", ""), "")
		"skin":
			icon_path = "res://assets/skins/%s.png" % item_data.get("id", "")
	
	if icon_path and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	
	# Name
	var name_label := Label.new()
	var item_name := ""
	match item_data.get("type", ""):
		"boost":
			item_name = shop_manager.BOOST_NAMES.get(item_data.get("id", ""), item_data.get("id", ""))
		"crate":
			item_name = shop_manager.CRATE_NAMES.get(item_data.get("id", ""), item_data.get("id", ""))
		"skin":
			item_name = item_data.get("id", "Skin").replace("_", " ").capitalize()
	
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_label)
	
	return panel


func _animate_roulette() -> void:
	# Calculate target position - center should stop on item at index ~25 (near the end)
	var winning_index := 25
	var item_width := 100.0  # 90 + 10 spacing
	var window_width := 500.0
	var target_x := -(winning_index * item_width) + (window_width / 2.0) - (item_width / 2.0)
	
	# Start from right side
	roulette_hbox.position.x = window_width
	
	# Get the actual result
	roulette_result = shop_manager.open_crate(roulette_crate_type)
	
	# Make sure the winning item shows the actual result
	if roulette_hbox.get_child_count() > winning_index:
		var winning_panel: PanelContainer = roulette_hbox.get_child(winning_index)
		_update_roulette_item(winning_panel, roulette_result)
	
	# Animate
	roulette_tween = create_tween()
	roulette_tween.set_ease(Tween.EASE_OUT)
	roulette_tween.set_trans(Tween.TRANS_CUBIC)
	roulette_tween.tween_property(roulette_hbox, "position:x", target_x, 4.0)
	roulette_tween.tween_callback(_on_roulette_finished)


func _update_roulette_item(panel: PanelContainer, result: Dictionary) -> void:
	# Clear and rebuild the panel with actual result
	for child in panel.get_children():
		child.queue_free()
	
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	
	match result.get("type", ""):
		"boost":
			style.border_color = COLOR_ACCENT_PRIMARY
		"crate":
			style.border_color = COLOR_ACCENT_SECONDARY
		"skin":
			style.border_color = COLOR_ACCENT_GOLD
	
	panel.add_theme_stylebox_override("panel", style)
	
	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)
	
	# Icon
	var icon_path := ""
	match result.get("type", ""):
		"boost":
			icon_path = shop_manager.BOOST_ICONS.get(result.get("id", ""), "")
		"crate":
			icon_path = shop_manager.CRATE_ICONS.get(result.get("id", ""), "")
		"skin":
			if result.get("is_duplicate", false):
				icon_path = "res://assets/svg/coin.svg"
			else:
				icon_path = "res://assets/skins/%s.png" % result.get("id", "")
	
	if icon_path and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vbox.add_child(icon)
	
	# Name
	var name_label := Label.new()
	var item_name := ""
	match result.get("type", ""):
		"boost":
			item_name = shop_manager.BOOST_NAMES.get(result.get("id", ""), result.get("id", ""))
		"crate":
			item_name = shop_manager.CRATE_NAMES.get(result.get("id", ""), result.get("id", ""))
		"skin":
			if result.get("is_duplicate", false):
				item_name = "Refund: %s" % _format_balance(result.get("refund", 0))
			else:
				item_name = result.get("id", "Skin").replace("_", " ").capitalize()
	
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(name_label)


func _on_roulette_finished() -> void:
	# Show result popup
	await get_tree().create_timer(1.0).timeout
	
	if roulette_container:
		# Clear roulette and show result
		for child in roulette_container.get_children():
			if child != roulette_container.get_child(0):  # Keep background
				child.queue_free()
		
		# Result display
		var result_vbox := VBoxContainer.new()
		result_vbox.set_anchors_preset(Control.PRESET_CENTER)
		result_vbox.anchor_left = 0.5
		result_vbox.anchor_right = 0.5
		result_vbox.anchor_top = 0.5
		result_vbox.anchor_bottom = 0.5
		result_vbox.offset_left = -150
		result_vbox.offset_right = 150
		result_vbox.offset_top = -120
		result_vbox.offset_bottom = 120
		result_vbox.add_theme_constant_override("separation", 15)
		result_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		roulette_container.add_child(result_vbox)
		
		var win_label := Label.new()
		win_label.text = "YOU WON!"
		win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		win_label.add_theme_font_size_override("font_size", 32)
		win_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
		result_vbox.add_child(win_label)
		
		# Build result text
		var result_text := ""
		match roulette_result.get("type", ""):
			"boost":
				result_text = shop_manager.BOOST_NAMES.get(roulette_result.get("id", ""), "Boost")
			"crate":
				result_text = shop_manager.CRATE_NAMES.get(roulette_result.get("id", ""), "Crate")
			"skin":
				if roulette_result.get("is_duplicate", false):
					result_text = "Duplicate! Refund: %s coins" % _format_balance(roulette_result.get("refund", 0))
				else:
					result_text = "%s Skin!" % roulette_result.get("id", "").replace("_", " ").capitalize()
		
		var item_label := Label.new()
		item_label.text = result_text
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_label.add_theme_font_size_override("font_size", 24)
		item_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
		result_vbox.add_child(item_label)
		
		# Close button
		var close_btn := Button.new()
		close_btn.text = "CLOSE"
		close_btn.custom_minimum_size = Vector2(150, 50)
		close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close_btn.add_theme_font_size_override("font_size", 18)
		_style_secondary_button(close_btn)
		close_btn.pressed.connect(_on_roulette_close)
		result_vbox.add_child(close_btn)


func _on_roulette_close() -> void:
	if roulette_container:
		roulette_container.queue_free()
		roulette_container = null
	
	# Refresh shop display
	_load_stats()
	_update_balance_display()
	_update_shop_balance()
	_populate_shop_section()


func _update_shop_balance() -> void:
	var label := shop_panel.find_child("ShopBalanceLabel", true, false)
	if label and label is Label:
		label.text = _format_balance(stats.get("coin_balance", 0))


# ========== SHOP EVENT HANDLERS ==========

func _on_shop_button_pressed() -> void:
	audio_manager.play_button_click()
	_load_stats()
	_rebuild_shop_panel()
	_animate_panel_in(shop_panel)


func _on_shop_back_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_out(shop_panel)


func _on_shop_section_prev() -> void:
	audio_manager.play_button_click()
	shop_section_index -= 1
	if shop_section_index < 0:
		shop_section_index = SHOP_SECTIONS.size() - 1
	_update_shop_section_display()


func _on_shop_section_next() -> void:
	audio_manager.play_button_click()
	shop_section_index += 1
	if shop_section_index >= SHOP_SECTIONS.size():
		shop_section_index = 0
	_update_shop_section_display()


func _update_shop_section_display() -> void:
	if shop_section_label:
		shop_section_label.text = SHOP_SECTIONS[shop_section_index]
	_populate_shop_section()


func _on_skin_buy(skin_id: String) -> void:
	audio_manager.play_button_click()
	if shop_manager.buy_skin(skin_id):
		_load_stats()
		_update_balance_display()
		_update_shop_balance()
		_populate_shop_section()
		_setup_player_model()  # Refresh preview model


func _on_skin_select(skin_id: String) -> void:
	audio_manager.play_button_click()
	if shop_manager.select_skin(skin_id):
		_populate_shop_section()
		_setup_player_model()  # Refresh preview model


func _on_boost_buy(boost_id: String) -> void:
	audio_manager.play_button_click()
	if shop_manager.buy_boost(boost_id):
		_load_stats()
		_update_balance_display()
		_update_shop_balance()
		_populate_shop_section()


func _on_boost_toggle(boost_id: String) -> void:
	audio_manager.play_button_click()
	shop_manager.toggle_boost_selection(boost_id)
	_populate_shop_section()


func _on_crate_buy(crate_type: String) -> void:
	audio_manager.play_button_click()
	if shop_manager.buy_crate(crate_type):
		_load_stats()
		_update_balance_display()
		_update_shop_balance()
		_populate_shop_section()


func _on_crate_open(crate_type: String) -> void:
	audio_manager.play_button_click()
	_show_crate_roulette(crate_type)


func _on_shop_balance_changed(_new_balance: int) -> void:
	_load_stats()
	_update_balance_display()
	_update_shop_balance()


func _setup_balance_display() -> void:
	balance_container = HBoxContainer.new()
	balance_container.name = "BalanceContainer"
	balance_container.anchors_preset = Control.PRESET_TOP_RIGHT
	balance_container.anchor_left = 1.0
	balance_container.anchor_right = 1.0
	balance_container.offset_left = -200
	balance_container.offset_top = 20
	balance_container.offset_right = -20
	balance_container.offset_bottom = 60
	balance_container.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	balance_container.add_theme_constant_override("separation", 10)
	balance_container.alignment = BoxContainer.ALIGNMENT_END
	add_child(balance_container)
	
	# Background panel
	var bg_panel := PanelContainer.new()
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = COLOR_BG_MEDIUM
	bg_style.set_corner_radius_all(14)
	bg_style.set_border_width_all(2)
	bg_style.border_color = COLOR_ACCENT_GOLD.darkened(0.3)
	bg_style.set_content_margin_all(8)
	bg_style.content_margin_left = 14
	bg_style.content_margin_right = 14
	bg_panel.add_theme_stylebox_override("panel", bg_style)
	balance_container.add_child(bg_panel)
	
	var inner_hbox := HBoxContainer.new()
	inner_hbox.add_theme_constant_override("separation", 8)
	bg_panel.add_child(inner_hbox)
	
	var coin_icon := TextureRect.new()
	var coin_texture: Texture2D = load("res://assets/svg/coin.svg")
	if coin_texture:
		coin_icon.texture = coin_texture
	coin_icon.custom_minimum_size = Vector2(32, 32)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = COLOR_ACCENT_GOLD
	inner_hbox.add_child(coin_icon)
	
	balance_label = Label.new()
	balance_label.text = _format_balance(stats.get("coin_balance", 0))
	balance_label.add_theme_font_size_override("font_size", 26)
	balance_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	balance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner_hbox.add_child(balance_label)


func _format_balance(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.1fK" % (amount / 1000.0)
	return str(amount)


func _apply_safe_area_offset() -> void:
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale_y: float = viewport_size.y / float(screen_size.y) if screen_size.y > 0 else 1.0
	var top_inset_screen: float = float(safe_area.position.y)
	var top_inset_viewport: float = top_inset_screen * scale_y
	var min_top_offset: float = 20.0
	var actual_top_offset: float = maxf(top_inset_viewport, min_top_offset)
	
	if balance_container:
		balance_container.offset_top = actual_top_offset
		balance_container.offset_bottom = actual_top_offset + 50.0


func _update_balance_display() -> void:
	if balance_label:
		balance_label.text = _format_balance(stats.get("coin_balance", 0))


func _setup_speed_lines() -> void:
	var viewport_size: Vector2i = get_viewport().size
	
	# Primary speed lines - diagonal motion suggesting downhill movement
	var speed_lines := GPUParticles2D.new()
	speed_lines.name = "SpeedLines"
	speed_lines.amount = 25
	speed_lines.lifetime = 2.5
	speed_lines.preprocess = 2.0
	
	var material := ParticleProcessMaterial.new()
	# Direction pointing bottom-left (diagonal downhill feel)
	material.direction = Vector3(-0.4, 1.0, 0).normalized()
	material.spread = 3.0
	material.gravity = Vector3(0, 0, 0)
	material.initial_velocity_min = 400.0
	material.initial_velocity_max = 600.0
	material.scale_min = 3.0
	material.scale_max = 8.0
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(viewport_size.x * 0.8, 10, 1)
	# Color: cyan/blue with good visibility
	material.color = Color(0.3, 0.6, 0.9, 0.3)
	
	speed_lines.process_material = material
	speed_lines.position = Vector2(viewport_size.x / 2.0 + 200, -50)
	speed_lines.visibility_rect = Rect2(-viewport_size.x, -100, viewport_size.x * 3, viewport_size.y + 200)
	
	$Background.add_sibling(speed_lines)
	
	# Secondary floating orbs - slow ambient movement  
	var orbs := GPUParticles2D.new()
	orbs.name = "FloatingOrbs"
	orbs.amount = 15
	orbs.lifetime = 12.0
	orbs.preprocess = 6.0
	
	var orb_mat := ParticleProcessMaterial.new()
	orb_mat.direction = Vector3(0.2, -0.3, 0).normalized()
	orb_mat.spread = 45.0
	orb_mat.gravity = Vector3(0, 0, 0)
	orb_mat.initial_velocity_min = 15.0
	orb_mat.initial_velocity_max = 35.0
	orb_mat.scale_min = 10.0
	orb_mat.scale_max = 28.0
	orb_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	orb_mat.emission_box_extents = Vector3(viewport_size.x / 2.0, viewport_size.y / 2.0, 1)
	# Accent color glow
	orb_mat.color = Color(0.25, 0.65, 0.96, 0.15)
	
	orbs.process_material = orb_mat
	orbs.position = Vector2(viewport_size.x / 2.0, viewport_size.y / 2.0)
	orbs.visibility_rect = Rect2(-100, -100, viewport_size.x + 200, viewport_size.y + 200)
	
	$Background.add_sibling(orbs)


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
					if not stats.has("destroyed_objects"):
						stats["destroyed_objects"] = {}


func _save_stats() -> void:
	var file := FileAccess.open(STATS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(stats))
		file.close()


func _update_stats_display() -> void:
	_rebuild_stats_panel()


static func record_game_stats(coins: int, distance: float, game_time: float = 0.0) -> void:
	var stats_data := {}
	
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
	
	var prev_games: int = int(stats_data.get("games_played", 0))
	var prev_coins: int = int(stats_data.get("total_coins", 0))
	var prev_max_coins: int = int(stats_data.get("max_coins", 0))
	var prev_distance: float = float(stats_data.get("total_distance", 0.0))
	var prev_max_distance: float = float(stats_data.get("max_distance", 0.0))
	var prev_time: float = float(stats_data.get("total_time", 0.0))
	var prev_max_time: float = float(stats_data.get("max_time", 0.0))
	var prev_balance: int = int(stats_data.get("coin_balance", 0))
	
	stats_data["games_played"] = prev_games + 1
	stats_data["total_coins"] = prev_coins + coins
	stats_data["max_coins"] = max(prev_max_coins, coins)
	stats_data["total_distance"] = prev_distance + distance
	stats_data["max_distance"] = max(prev_max_distance, distance)
	stats_data["total_time"] = prev_time + game_time
	stats_data["max_time"] = max(prev_max_time, game_time)
	stats_data["coin_balance"] = prev_balance + coins
	
	var gm := Engine.get_singleton("GameManager") if Engine.has_singleton("GameManager") else null
	if not gm:
		gm = (func() -> Node:
			var tree := Engine.get_main_loop() as SceneTree
			if tree:
				return tree.root.get_node_or_null("/root/GameManager")
			return null
		).call()
	
	if gm:
		var destroyed: Dictionary = gm.get("destroyed_objects")
		if destroyed:
			var prev_destroyed: Dictionary = stats_data.get("destroyed_objects", {})
			for obj_id: String in destroyed.keys():
				var count: int = destroyed[obj_id]
				var prev_count: int = prev_destroyed.get(obj_id, 0)
				prev_destroyed[obj_id] = prev_count + count
			stats_data["destroyed_objects"] = prev_destroyed
	
	if not stats_data.has("destroyed_objects"):
		stats_data["destroyed_objects"] = {}
	
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
	_animate_panel_in(stats_panel)


func _on_section_prev() -> void:
	audio_manager.play_button_click()
	current_section_index -= 1
	if current_section_index < 0:
		current_section_index = OBJECT_SECTIONS.size() - 1
	_update_section_display()


func _on_section_next() -> void:
	audio_manager.play_button_click()
	current_section_index += 1
	if current_section_index >= OBJECT_SECTIONS.size():
		current_section_index = 0
	_update_section_display()


func _update_section_display() -> void:
	if section_label:
		section_label.text = OBJECT_SECTIONS[current_section_index]
	if object_grid:
		_populate_object_cards(object_grid)


func _on_stats_back_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_out(stats_panel)


func _on_settings_button_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_in(settings_panel)


func _on_settings_back_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_out(settings_panel)


func _on_quit_button_pressed() -> void:
	audio_manager.play_button_click()
	if animation_player.has_animation("exit"):
		animation_player.play("exit")
		await animation_player.animation_finished
	get_tree().quit()


func _animate_panel_in(panel: Control) -> void:
	panel.visible = true
	panel.modulate.a = 0
	main_content.visible = false
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "modulate:a", 1.0, 0.25)


func _animate_panel_out(panel: Control) -> void:
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(panel, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func() -> void:
		panel.visible = false
		main_content.visible = true
		if play_button:
			play_button.grab_focus()
	)


# ========== Settings ==========

func _on_music_slider_value_changed(value: float) -> void:
	audio_manager.set_music_volume(value)


func _on_sfx_slider_value_changed(value: float) -> void:
	audio_manager.set_sfx_volume(value)


func _on_popup_check_toggled(toggled_on: bool) -> void:
	audio_manager.set_show_pickup_popup(toggled_on)


func _on_damage_check_toggled(toggled_on: bool) -> void:
	audio_manager.set_show_damage_popup(toggled_on)


func _on_haptic_check_toggled(toggled_on: bool) -> void:
	audio_manager.set_haptic_enabled(toggled_on)


func _on_control_gyro_pressed() -> void:
	audio_manager.set_control_mode(0)
	_update_control_mode_buttons(0)


func _on_control_touch_pressed() -> void:
	audio_manager.set_control_mode(1)
	_update_control_mode_buttons(1)


func _update_control_mode_buttons(mode: int) -> void:
	if not control_gyro_btn or not control_touch_btn:
		return
	
	# Style active button
	var active_style := StyleBoxFlat.new()
	active_style.bg_color = COLOR_ACCENT_PRIMARY
	active_style.set_corner_radius_all(10)
	active_style.set_border_width_all(2)
	active_style.border_color = COLOR_ACCENT_PRIMARY.lightened(0.3)
	
	# Style inactive button
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
	
	# Show/hide tilt sensitivity based on mode (only relevant for gyro mode)
	if tilt_sensitivity_container:
		tilt_sensitivity_container.visible = (mode == 0)


func _on_screen_shake_check_toggled(toggled_on: bool) -> void:
	var settings := get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_screen_shake_enabled(toggled_on)


func _on_tilt_sensitivity_changed(value: float) -> void:
	var settings := get_node_or_null("/root/SettingsManager")
	if settings:
		settings.set_tilt_sensitivity(value)
	_update_tilt_sensitivity_label(value)


func _update_tilt_sensitivity_label(value: float) -> void:
	if tilt_sensitivity_label:
		tilt_sensitivity_label.text = "%.1fx" % value


func _on_author_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

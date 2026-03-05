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
@onready var main_content: VBoxContainer = $MainContent
@onready var music_slider: HSlider = $SettingsPanel/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $SettingsPanel/VBoxContainer/SFXSlider
@onready var popup_check: CheckButton = $SettingsPanel/VBoxContainer/PopupCheck
@onready var damage_check: CheckButton = $SettingsPanel/VBoxContainer/DamageCheck
@onready var haptic_check: CheckButton = $SettingsPanel/VBoxContainer/HapticCheck
@onready var player_model_container: Node3D = $PlayerViewport/SubViewport/PlayerModel

var audio_manager: Node
var player_model_instance: Node3D
var model_rotation_speed := 0.5

# UI references created dynamically
var play_button: Button
var stats_button: Button
var settings_button: Button
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
	
	# Initialize audio settings
	music_slider.value = audio_manager.get_music_volume()
	sfx_slider.value = audio_manager.get_sfx_volume()
	popup_check.button_pressed = audio_manager.get_show_pickup_popup()
	damage_check.button_pressed = audio_manager.get_show_damage_popup()
	haptic_check.button_pressed = audio_manager.get_haptic_enabled()
	
	audio_manager.play_menu_music()
	_load_stats()
	
	# Rebuild UI with modern design
	_rebuild_main_menu()
	_rebuild_settings_panel()
	_rebuild_stats_panel()
	
	_setup_balance_display()
	_apply_safe_area_offset()
	_setup_player_model()
	_setup_snow_particles()
	
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
	
	# Button Grid (2x2)
	var button_grid := GridContainer.new()
	button_grid.columns = 2
	button_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button_grid.add_theme_constant_override("h_separation", 20)
	button_grid.add_theme_constant_override("v_separation", 20)
	main_content.add_child(button_grid)
	
	# Create main buttons
	play_button = _create_modern_button("PLAY", "res://assets/icons/play.svg", COLOR_ACCENT_SECONDARY)
	play_button.pressed.connect(_on_play_button_pressed)
	button_grid.add_child(play_button)
	
	stats_button = _create_modern_button("STATS", "res://assets/icons/stats.svg", COLOR_ACCENT_PRIMARY)
	stats_button.pressed.connect(_on_stats_button_pressed)
	button_grid.add_child(stats_button)
	
	settings_button = _create_modern_button("SETTINGS", "res://assets/icons/settings.svg", COLOR_ACCENT_PRIMARY)
	settings_button.pressed.connect(_on_settings_button_pressed)
	button_grid.add_child(settings_button)
	
	quit_button = _create_modern_button("QUIT", "res://assets/icons/quit.svg", Color(0.8, 0.3, 0.3, 1.0))
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
	var vbox: VBoxContainer = settings_panel.get_node("VBoxContainer")
	
	# Update background
	var bg: ColorRect = settings_panel.get_node("Background")
	bg.color = Color(0, 0, 0, 0.92)
	
	# Style the VBox as a card
	var panel := PanelContainer.new()
	panel.anchors_preset = Control.PRESET_CENTER
	panel.anchor_left = 0.5
	panel.anchor_top = 0.5
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -220
	panel.offset_top = -280
	panel.offset_right = 220
	panel.offset_bottom = 280
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = COLOR_BG_MEDIUM
	panel_style.set_corner_radius_all(24)
	panel_style.set_border_width_all(2)
	panel_style.border_color = COLOR_BORDER
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 20
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# Move vbox content to panel
	vbox.get_parent().remove_child(vbox)
	vbox.offset_left = 0
	vbox.offset_right = 0
	vbox.offset_top = 0
	vbox.offset_bottom = 0
	vbox.anchors_preset = Control.PRESET_FULL_RECT
	panel.add_child(vbox)
	settings_panel.add_child(panel)
	
	# Style title
	var title: Label = vbox.get_node("Title")
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	title.add_theme_color_override("font_outline_color", COLOR_ACCENT_PRIMARY)
	title.add_theme_constant_override("outline_size", 2)
	
	# Style labels
	for label_name in ["MusicLabel", "SFXLabel"]:
		var lbl: Label = vbox.get_node(label_name)
		lbl.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	
	# Style sliders
	_style_modern_slider(music_slider)
	_style_modern_slider(sfx_slider)
	
	# Style checkboxes
	for check in [popup_check, damage_check, haptic_check]:
		check.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
		check.add_theme_font_size_override("font_size", 16)
	
	# Style back button
	var back_btn: Button = vbox.get_node("BackButton")
	_style_secondary_button(back_btn)


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
	var vbox: VBoxContainer = stats_panel.get_node("VBoxContainer")
	for child in vbox.get_children():
		child.queue_free()
	
	# Update background
	var bg: ColorRect = stats_panel.get_node("Background")
	bg.color = Color(0, 0, 0, 0.92)
	
	# Make panel larger
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_width: float = minf(720.0, screen_size.x * 0.92)
	var panel_height: float = minf(screen_size.y * 0.88, screen_size.y - 60)
	
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
	card_style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", card_style)
	
	vbox.offset_left = -panel_width / 2
	vbox.offset_right = panel_width / 2
	vbox.offset_top = -panel_height / 2
	vbox.offset_bottom = panel_height / 2
	vbox.add_theme_constant_override("separation", 12)
	
	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 12)
	card.add_child(inner_vbox)
	vbox.add_child(card)
	
	# Title with glow
	var title := Label.new()
	title.text = "STATISTICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	title.add_theme_color_override("font_outline_color", COLOR_ACCENT_PRIMARY)
	title.add_theme_constant_override("outline_size", 2)
	inner_vbox.add_child(title)
	
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
	var coin_icon: Texture2D = load("res://assets/icons/coin.svg")
	var distance_icon: Texture2D = load("res://assets/icons/distance.svg")
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
			objects = ObjectConfigScript.get_objects_by_category(ObjectConfigScript.Category.NPC_ENEMY)
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
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(2)
	style.border_color = COLOR_BORDER if kill_count > 0 else Color(0.3, 0.3, 0.35, 0.5)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	card.add_child(hbox)
	
	# 3D Preview
	var preview := _create_3d_preview(obj_data, kill_count)
	hbox.add_child(preview)
	object_viewports.append(preview)
	
	# Info section
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	info.add_child(stats_row)
	
	# Coins
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 5)
	stats_row.add_child(coin_row)
	
	var coin_icon := TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(20, 20)
	coin_icon.texture = load("res://assets/icons/coin.svg")
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = COLOR_ACCENT_GOLD if kill_count > 0 else COLOR_TEXT_MUTED
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
	
	# Kill count badge
	var kill_badge := _create_kill_badge(kill_count)
	info.add_child(kill_badge)
	
	return card


func _create_kill_badge(count: int) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 8)
	
	var badge := PanelContainer.new()
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
	if player_model_container and PLAYER_MODEL_SCENE:
		player_model_instance = PLAYER_MODEL_SCENE.instantiate()
		player_model_instance.scale = Vector3(0.3, 0.3, 0.3)
		player_model_container.add_child(player_model_instance)
		
		# Apply unshaded material to disable shadows/reflections
		_apply_unshaded_material(player_model_instance)


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
	var coin_texture: Texture2D = load("res://assets/icons/coin.svg")
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


func _setup_snow_particles() -> void:
	var viewport_size: Vector2i = get_viewport().size
	
	var particles := GPUParticles2D.new()
	particles.name = "SnowParticles"
	particles.amount = 150
	particles.lifetime = 10.0
	particles.preprocess = 5.0
	
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(0, 1, 0)
	material.spread = 5.0
	material.gravity = Vector3(5, 80, 0)
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 40.0
	material.scale_min = 2.0
	material.scale_max = 5.0
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(viewport_size.x / 2.0, 10, 1)
	
	particles.process_material = material
	particles.position = Vector2(viewport_size.x / 2.0, 0)
	particles.visibility_rect = Rect2(-viewport_size.x, -50, viewport_size.x * 2, viewport_size.y + 100)
	
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


func _on_author_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

extends Control
## Main Menu with animated boulder, enhanced stats tracking, and visual effects

const STATS_FILE := "user://stats.json"
const PLAYER_MODEL_SCENE := preload("res://assets/models/players/player_1.blend")
const ObjectConfigScript := preload("res://scripts/config/object_config.gd")

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var play_button: Button = $MainContent/ButtonGrid/PlayButton
@onready var stats_button: Button = $MainContent/ButtonGrid/StatsButton
@onready var settings_button: Button = $MainContent/ButtonGrid/SettingsButton
@onready var quit_button: Button = $MainContent/ButtonGrid/QuitButton
@onready var settings_panel: Control = $SettingsPanel
@onready var stats_panel: Control = $StatsPanel
@onready var main_content: VBoxContainer = $MainContent
@onready var music_slider: HSlider = $SettingsPanel/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $SettingsPanel/VBoxContainer/SFXSlider
@onready var popup_check: CheckButton = $SettingsPanel/VBoxContainer/PopupCheck
@onready var haptic_check: CheckButton = $SettingsPanel/VBoxContainer/HapticCheck
@onready var player_model_container: Node3D = $PlayerViewport/SubViewport/PlayerModel

var audio_manager: Node
var player_model_instance: Node3D
var model_rotation_speed := 0.5

# Object preview viewports
var object_viewports: Array[SubViewportContainer] = []

# Stats sections for destroyed objects
const OBJECT_SECTIONS := ["Trees", "Buildings", "Friend NPC", "Enemy NPC", "Enemy Building"]
var current_section_index: int = 0
var object_grid: GridContainer  # Reference for section switching
var section_label: Label  # Reference for section label

# Stats data
var stats := {
	"games_played": 0,
	"total_coins": 0,
	"max_coins": 0,
	"total_distance": 0.0,
	"max_distance": 0.0,
	"total_time": 0.0,
	"max_time": 0.0,
	"coin_balance": 0,  # Player's accumulated coin balance
	"destroyed_objects": {}  # {object_id: count}
}

# Balance display references
var balance_container: HBoxContainer
var balance_label: Label

func _ready() -> void:
	audio_manager = get_node("/root/AudioManager")
	
	# Initialize sliders with current volume values
	music_slider.value = audio_manager.get_music_volume()
	sfx_slider.value = audio_manager.get_sfx_volume()
	popup_check.button_pressed = audio_manager.get_show_pickup_popup()
	haptic_check.button_pressed = audio_manager.get_haptic_enabled()
	
	# Start menu music
	audio_manager.play_menu_music()
	
	# Load stats
	_load_stats()
	
	# Setup balance display
	_setup_balance_display()
	_apply_safe_area_offset()
	
	# Setup 3D player model
	_setup_player_model()
	
	# Setup snow particles
	_setup_snow_particles()
	
	# Rebuild stats panel with new design
	_rebuild_stats_panel()
	
	# Focus play button
	play_button.grab_focus()
	
	# Entrance animation (if available)
	if animation_player.has_animation("enter"):
		animation_player.play("enter")

func _process(delta: float) -> void:
	# Rotate player model
	if player_model_instance:
		player_model_instance.rotate_y(model_rotation_speed * delta)
	
	# Rotate object preview models
	for viewport_container in object_viewports:
		if viewport_container and is_instance_valid(viewport_container):
			var viewport: SubViewport = viewport_container.get_node_or_null("SubViewport")
			if viewport:
				var model_holder: Node3D = viewport.get_node_or_null("ModelHolder")
				if model_holder:
					model_holder.rotate_y(model_rotation_speed * 0.8 * delta)

func _setup_player_model() -> void:
	if player_model_container and PLAYER_MODEL_SCENE:
		player_model_instance = PLAYER_MODEL_SCENE.instantiate()
		player_model_instance.scale = Vector3(0.3, 0.3, 0.3)
		player_model_container.add_child(player_model_instance)

func _setup_balance_display() -> void:
	# Create a container for the coin balance in top-right corner
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
	
	# Coin icon
	var coin_icon := TextureRect.new()
	var coin_texture: Texture2D = load("res://assets/icons/coin.svg")
	if coin_texture:
		coin_icon.texture = coin_texture
	coin_icon.custom_minimum_size = Vector2(40, 40)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = Color(1, 0.85, 0.2, 1)  # Gold tint
	balance_container.add_child(coin_icon)
	
	# Balance label
	balance_label = Label.new()
	balance_label.text = _format_balance(stats.get("coin_balance", 0))
	balance_label.add_theme_font_size_override("font_size", 32)
	balance_label.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))  # Gold
	balance_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	balance_label.add_theme_constant_override("shadow_offset_x", 2)
	balance_label.add_theme_constant_override("shadow_offset_y", 2)
	balance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	balance_container.add_child(balance_label)

func _format_balance(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.1fK" % (amount / 1000.0)
	return str(amount)

func _apply_safe_area_offset() -> void:
	# Get safe area rect from OS (accounts for notch, status bar, etc.)
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	
	# Get viewport (design) size
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Calculate scale factor from screen to viewport coordinates
	var scale_y: float = viewport_size.y / float(screen_size.y) if screen_size.y > 0 else 1.0
	
	# Calculate top inset and scale to viewport coordinates
	var top_inset_screen: float = float(safe_area.position.y)
	var top_inset_viewport: float = top_inset_screen * scale_y
	
	# On desktop or if no safe area, use a minimum margin
	var min_top_offset: float = 20.0
	var actual_top_offset: float = maxf(top_inset_viewport, min_top_offset)
	
	# Apply offset to balance container
	if balance_container:
		balance_container.offset_top = actual_top_offset
		balance_container.offset_bottom = actual_top_offset + 40.0

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

# ========== Stats Panel Rebuild ==========

func _rebuild_stats_panel() -> void:
	# Clear existing content
	var vbox: VBoxContainer = stats_panel.get_node("VBoxContainer")
	for child in vbox.get_children():
		child.queue_free()
	
	# Make the stats panel use more screen space
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	var panel_width: float = minf(700.0, screen_size.x * 0.9)
	var panel_height: float = minf(screen_size.y * 0.85, screen_size.y - 80)
	vbox.offset_left = -panel_width / 2
	vbox.offset_right = panel_width / 2
	vbox.offset_top = -panel_height / 2
	vbox.offset_bottom = panel_height / 2
	vbox.add_theme_constant_override("separation", 10)
	
	# Title
	var title := Label.new()
	title.text = "STATISTICS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.7, 1))
	vbox.add_child(title)
	
	# Global Stats Section
	var global_section := _create_global_stats_section()
	vbox.add_child(global_section)
	
	# Separator
	var sep := HSeparator.new()
	sep.custom_minimum_size.y = 10
	vbox.add_child(sep)
	
	# Objects Header
	var obj_header := Label.new()
	obj_header.text = "DESTROYED OBJECTS"
	obj_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	obj_header.add_theme_font_size_override("font_size", 20)
	obj_header.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9, 1))
	vbox.add_child(obj_header)
	
	# Section Navigation (< Section Name >)
	var nav_container := HBoxContainer.new()
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.add_theme_constant_override("separation", 20)
	vbox.add_child(nav_container)
	
	var prev_btn := Button.new()
	prev_btn.text = "<"
	prev_btn.custom_minimum_size = Vector2(50, 40)
	prev_btn.add_theme_font_size_override("font_size", 24)
	_apply_button_style(prev_btn)
	prev_btn.pressed.connect(_on_section_prev)
	nav_container.add_child(prev_btn)
	
	section_label = Label.new()
	section_label.text = OBJECT_SECTIONS[current_section_index]
	section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	section_label.custom_minimum_size = Vector2(200, 40)
	section_label.add_theme_font_size_override("font_size", 22)
	section_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 1))
	nav_container.add_child(section_label)
	
	var next_btn := Button.new()
	next_btn.text = ">"
	next_btn.custom_minimum_size = Vector2(50, 40)
	next_btn.add_theme_font_size_override("font_size", 24)
	_apply_button_style(next_btn)
	next_btn.pressed.connect(_on_section_next)
	nav_container.add_child(next_btn)
	
	# Scrollable Object List - use available screen space
	var scroll := ScrollContainer.new()
	var screen_height: float = get_viewport().get_visible_rect().size.y
	var scroll_height: float = maxf(400.0, screen_height * 0.5)  # At least 50% of screen
	scroll.custom_minimum_size = Vector2(680, scroll_height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	
	object_grid = GridContainer.new()
	object_grid.columns = 2
	object_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_grid.add_theme_constant_override("h_separation", 15)
	object_grid.add_theme_constant_override("v_separation", 15)
	scroll.add_child(object_grid)
	
	# Add object cards
	_populate_object_cards(object_grid)
	
	# Back Button
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(200, 50)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 22)
	_apply_button_style(back_btn)
	back_btn.pressed.connect(_on_stats_back_pressed)
	vbox.add_child(back_btn)

func _create_global_stats_section() -> VBoxContainer:
	var section := VBoxContainer.new()
	section.add_theme_constant_override("separation", 8)
	
	# Load icons
	var coin_icon: Texture2D = load("res://assets/icons/coin.svg")
	var distance_icon: Texture2D = load("res://assets/icons/distance.svg")
	
	# Games played
	var games_label := Label.new()
	var games_count: int = stats.get("games_played", 0)
	games_label.text = "Games Played: %d" % games_count
	games_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	games_label.add_theme_font_size_override("font_size", 18)
	games_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	section.add_child(games_label)
	
	# Coins row
	var coins_row := HBoxContainer.new()
	coins_row.alignment = BoxContainer.ALIGNMENT_CENTER
	section.add_child(coins_row)
	
	var coin_tex := TextureRect.new()
	coin_tex.custom_minimum_size = Vector2(24, 24)
	coin_tex.texture = coin_icon
	coin_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coins_row.add_child(coin_tex)
	
	var max_c: int = stats.get("max_coins", 0)
	var total_c: int = stats.get("total_coins", 0)
	var avg_c: int = 0
	if games_count > 0:
		avg_c = int(total_c / games_count)
	
	var coins_label := Label.new()
	coins_label.text = "  Best: %d  |  Avg: %d  |  Total: %d" % [max_c, avg_c, total_c]
	coins_label.add_theme_font_size_override("font_size", 18)
	coins_row.add_child(coins_label)
	
	# Distance row
	var dist_row := HBoxContainer.new()
	dist_row.alignment = BoxContainer.ALIGNMENT_CENTER
	section.add_child(dist_row)
	
	var dist_tex := TextureRect.new()
	dist_tex.custom_minimum_size = Vector2(24, 24)
	dist_tex.texture = distance_icon
	dist_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dist_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dist_row.add_child(dist_tex)
	
	var max_d: float = stats.get("max_distance", 0.0)
	var total_d: float = stats.get("total_distance", 0.0)
	var avg_d: float = 0.0
	if games_count > 0:
		avg_d = total_d / games_count
	
	var dist_label := Label.new()
	dist_label.text = "  Best: %dm  |  Avg: %dm" % [int(max_d), int(avg_d)]
	dist_label.add_theme_font_size_override("font_size", 18)
	dist_row.add_child(dist_label)
	
	# Time row
	var time_row := HBoxContainer.new()
	time_row.alignment = BoxContainer.ALIGNMENT_CENTER
	section.add_child(time_row)
	
	var time_icon_label := Label.new()
	time_icon_label.text = "⏱"
	time_icon_label.add_theme_font_size_override("font_size", 20)
	time_row.add_child(time_icon_label)
	
	var max_t: float = stats.get("max_time", 0.0)
	var total_t: float = stats.get("total_time", 0.0)
	var avg_t: float = 0.0
	if games_count > 0:
		avg_t = total_t / games_count
	
	var time_label := Label.new()
	time_label.text = "  Best: %s  |  Avg: %s  |  Total: %s" % [_format_time(max_t), _format_time(avg_t), _format_time(total_t)]
	time_label.add_theme_font_size_override("font_size", 18)
	time_row.add_child(time_label)
	
	return section

func _format_time(time_seconds: float) -> String:
	var total_seconds := int(time_seconds)
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var seconds := total_seconds % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%02d:%02d" % [minutes, seconds]

func _populate_object_cards(grid: GridContainer) -> void:
	# Clear existing cards
	for child in grid.get_children():
		child.queue_free()
	object_viewports.clear()
	
	# Get objects based on current section
	# OBJECT_SECTIONS = ["Trees", "Buildings", "Friend NPC", "Enemy NPC", "Enemy Building"]
	var objects: Array = []
	match current_section_index:
		0:  # Trees
			objects = ObjectConfigScript.get_trees()
		1:  # Buildings
			objects = ObjectConfigScript.get_buildings()
		2:  # Friend NPC
			objects = ObjectConfigScript.get_npcs_friend()
		3:  # Enemy NPC (enemies that aren't structures)
			for obj in ObjectConfigScript.get_enemies():
				var o: RefCounted = obj
				if not o.id.begins_with("enemy_spike") and not o.id.begins_with("enemy_building"):
					objects.append(obj)
		4:  # Enemy Building (spikes, structures)
			for obj in ObjectConfigScript.get_enemies():
				var o: RefCounted = obj
				if o.id.begins_with("enemy_spike") or o.id.begins_with("enemy_building"):
					objects.append(obj)
	
	var destroyed: Dictionary = stats.get("destroyed_objects", {})
	
	if objects.is_empty():
		# Show "No objects" message
		var empty_label := Label.new()
		empty_label.text = "No objects in this category"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 18)
		empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7, 1))
		grid.add_child(empty_label)
		return
	
	for obj_data in objects:
		var card := _create_object_card(obj_data, destroyed.get(obj_data.id, 0))
		grid.add_child(card)

func _create_object_card(obj_data: RefCounted, kill_count: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(320, 100)
	
	# Card style
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.2, 0.18, 0.9)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.5, 0.4, 0.8)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	card.add_child(hbox)
	
	# 3D Preview
	var preview := _create_3d_preview(obj_data)
	hbox.add_child(preview)
	object_viewports.append(preview)
	
	# Info section
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hbox.add_child(info)
	
	# Object name
	var name_label := Label.new()
	name_label.text = obj_data.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", Color(1, 0.95, 0.8, 1))
	info.add_child(name_label)
	
	# Coins
	var coin_row := HBoxContainer.new()
	info.add_child(coin_row)
	
	var coin_icon := TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(16, 16)
	coin_icon.texture = load("res://assets/icons/coin.svg")
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_row.add_child(coin_icon)
	
	var coin_label := Label.new()
	coin_label.text = " %d coins" % obj_data.coins
	coin_label.add_theme_font_size_override("font_size", 14)
	coin_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4, 1))
	coin_row.add_child(coin_label)
	
	# Spawn chance
	var spawn_label := Label.new()
	spawn_label.text = "Spawn: %.0f%%" % (obj_data.spawn_chance * 100)
	spawn_label.add_theme_font_size_override("font_size", 14)
	spawn_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8, 1))
	info.add_child(spawn_label)
	
	# Kill count
	var kill_label := Label.new()
	kill_label.text = "Destroyed: %d" % kill_count
	kill_label.add_theme_font_size_override("font_size", 14)
	if kill_count > 0:
		kill_label.add_theme_color_override("font_color", Color(0.5, 1, 0.6, 1))
	else:
		kill_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1))
	info.add_child(kill_label)
	
	return card

func _create_3d_preview(obj_data: RefCounted) -> SubViewportContainer:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(80, 80)
	container.stretch = true
	
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.transparent_bg = true
	viewport.size = Vector2i(80, 80)
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	# CRITICAL: Isolate 3D world so objects don't render in other viewports
	viewport.own_world_3d = true
	container.add_child(viewport)
	
	# Environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1, 1)
	
	# Camera - set position and look direction manually (node not in tree yet)
	var camera := Camera3D.new()
	camera.environment = env
	camera.fov = 35.0  # Narrower FOV for better framing
	var cam_pos := Vector3(0, 0.6, 3.0)  # Further back
	var target := Vector3(0, 0.2, 0)
	camera.transform = Transform3D().looking_at(target - cam_pos, Vector3.UP)
	camera.transform.origin = cam_pos
	viewport.add_child(camera)
	
	# Light
	var light := DirectionalLight3D.new()
	light.transform.basis = Basis(Vector3(1, 0, 0), -0.5) * Basis(Vector3(0, 1, 0), 0.3)
	viewport.add_child(light)
	
	# Model holder (for rotation)
	var holder := Node3D.new()
	holder.name = "ModelHolder"
	viewport.add_child(holder)
	
	# Load model
	if obj_data.model_path and obj_data.model_path != "":
		var model_scene: PackedScene = load(obj_data.model_path)
		if model_scene:
			var model := model_scene.instantiate()
			# Scale to fit in view - use fixed scale for consistency
			var target_h: float = maxf(float(obj_data.target_height), 0.5)
			var scale_factor: float = 0.25 / target_h  # Smaller scale factor
			scale_factor = minf(scale_factor, 0.15)  # Cap maximum scale
			model.scale = Vector3(scale_factor, scale_factor, scale_factor)
			holder.add_child(model)
	
	return container

func _apply_button_style(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.2, 0.35, 0.25, 0.9)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.border_color = Color(0.4, 0.7, 0.5, 1)
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.25, 0.45, 0.3, 0.95)
	hover.border_width_left = 2
	hover.border_width_top = 2
	hover.border_width_right = 2
	hover.border_width_bottom = 2
	hover.border_color = Color(0.5, 0.85, 0.6, 1)
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)

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
					# Ensure destroyed_objects exists
					if not stats.has("destroyed_objects"):
						stats["destroyed_objects"] = {}

func _save_stats() -> void:
	var file := FileAccess.open(STATS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(stats))
		file.close()

func _update_stats_display() -> void:
	# Rebuild the stats panel with current data
	_rebuild_stats_panel()

# Static method to record game results (called from game_manager)
static func record_game_stats(coins: int, distance: float, game_time: float = 0.0) -> void:
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
	stats_data["coin_balance"] = prev_balance + coins  # Add collected coins to balance
	
	# Copy destroyed objects from GameManager
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
	
	# Ensure destroyed_objects exists
	if not stats_data.has("destroyed_objects"):
		stats_data["destroyed_objects"] = {}
	
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
	main_content.visible = false

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
	stats_panel.visible = false
	main_content.visible = true

func _on_settings_button_pressed() -> void:
	audio_manager.play_button_click()
	settings_panel.visible = true
	main_content.visible = false

func _on_settings_back_pressed() -> void:
	audio_manager.play_button_click()
	settings_panel.visible = false
	main_content.visible = true

func _on_quit_button_pressed() -> void:
	audio_manager.play_button_click()
	if animation_player.has_animation("exit"):
		animation_player.play("exit")
		await animation_player.animation_finished
	get_tree().quit()

# ========== Settings ==========

func _on_music_slider_value_changed(value: float) -> void:
	audio_manager.set_music_volume(value)

func _on_sfx_slider_value_changed(value: float) -> void:
	audio_manager.set_sfx_volume(value)

func _on_popup_check_toggled(toggled_on: bool) -> void:
	audio_manager.set_show_pickup_popup(toggled_on)

func _on_haptic_check_toggled(toggled_on: bool) -> void:
	audio_manager.set_haptic_enabled(toggled_on)

func _on_author_link_clicked(meta: Variant) -> void:
	OS.shell_open(str(meta))

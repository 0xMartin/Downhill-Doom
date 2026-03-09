extends Control
## Main Menu with modern Roblox-style UI design
## Uses helper classes for panel management

const STATS_FILE := "user://stats.json"
const PLAYER_MODEL_SCENE := preload("res://assets/models/players/player_1.blend")

const SettingsPanelHelper := preload("res://scripts/ui/menu/settings_panel_helper.gd")
const StatsPanelHelper := preload("res://scripts/ui/menu/stats_panel_helper.gd")
const ShopPanelHelper := preload("res://scripts/ui/menu/shop_panel_helper.gd")

# ========== COLOR PALETTE ==========
const COLOR_BG_DARK := Color(0.06, 0.08, 0.12, 1.0)
const COLOR_BG_MEDIUM := Color(0.10, 0.14, 0.20, 1.0)
const COLOR_BG_LIGHT := Color(0.14, 0.18, 0.26, 1.0)
const COLOR_ACCENT_PRIMARY := Color(0.25, 0.65, 0.96, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.30, 0.85, 0.55, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.7, 0.75, 0.85, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.65, 1.0)
const COLOR_BORDER := Color(0.25, 0.32, 0.45, 0.8)

# Scene node references
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var settings_panel: Control = $SettingsPanel
@onready var stats_panel: Control = $StatsPanel
@onready var shop_panel: Control = $ShopPanel
@onready var main_content: VBoxContainer = $MainContent
@onready var player_model_container: Node3D = $PlayerViewport/SubViewport/PlayerModel
@onready var button_grid: GridContainer = $MainContent/ButtonGrid
@onready var play_button: Button = $MainContent/ButtonGrid/PlayButton
@onready var stats_button: Button = $MainContent/ButtonGrid/StatsButton
@onready var shop_button: Button = $MainContent/ButtonGrid/ShopButton
@onready var settings_button: Button = $MainContent/ButtonGrid/SettingsButton
@onready var quit_button: Button = $MainContent/ButtonGrid/QuitButton

var audio_manager: Node
var shop_manager: Node
var player_model_instance: Node3D
var model_rotation_speed := 0.5

# Helper instances
var settings_helper: RefCounted
var stats_helper: RefCounted
var shop_helper: RefCounted

# Dynamically created
var balance_label: Label
var balance_container: HBoxContainer

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
	
	if audio_manager:
		audio_manager.play_menu_music()
	_load_stats()
	
	# Create helper instances
	settings_helper = SettingsPanelHelper.new(settings_panel, audio_manager)
	stats_helper = StatsPanelHelper.new(stats_panel, stats)
	shop_helper = ShopPanelHelper.new(shop_panel, shop_manager, audio_manager, stats)
	
	# Connect shop helper signals
	shop_helper.stats_reload_needed.connect(_on_stats_reload_needed)
	shop_helper.balance_update_needed.connect(_on_balance_update_needed)
	shop_helper.player_model_refresh_needed.connect(_setup_player_model)
	
	# Build helper panels
	settings_helper.rebuild()
	stats_helper.rebuild()
	shop_helper.rebuild()
	
	# Connect panel back buttons
	_connect_panel_buttons()
	
	_setup_balance_display()
	_apply_safe_area_offset()
	_setup_player_model()
	_setup_speed_lines()
	
	# Connect shop manager signals
	if shop_manager:
		shop_manager.balance_changed.connect(_on_shop_balance_changed)
	
	if play_button:
		play_button.grab_focus()
	
	if animation_player and animation_player.has_animation("enter"):
		animation_player.play("enter")


func _connect_panel_buttons() -> void:
	# Settings panel
	var settings_back: Button = settings_helper.get_back_button()
	if settings_back and not settings_back.pressed.is_connected(_on_settings_back_pressed):
		settings_back.pressed.connect(_on_settings_back_pressed)
	
	# Stats panel
	var stats_back: Button = stats_helper.get_back_button()
	if stats_back and not stats_back.pressed.is_connected(_on_stats_back_pressed):
		stats_back.pressed.connect(_on_stats_back_pressed)
	
	var stats_prev: Button = stats_helper.get_prev_button()
	if stats_prev and not stats_prev.pressed.is_connected(_on_stats_section_prev):
		stats_prev.pressed.connect(_on_stats_section_prev)
	
	var stats_next: Button = stats_helper.get_next_button()
	if stats_next and not stats_next.pressed.is_connected(_on_stats_section_next):
		stats_next.pressed.connect(_on_stats_section_next)
	
	# Shop panel
	var shop_back: Button = shop_helper.get_back_button()
	if shop_back and not shop_back.pressed.is_connected(_on_shop_back_pressed):
		shop_back.pressed.connect(_on_shop_back_pressed)


func _process(delta: float) -> void:
	if player_model_instance:
		player_model_instance.rotate_y(model_rotation_speed * delta)
	
	# Rotate stats panel object previews
	for viewport_container in stats_helper.get_object_viewports():
		if viewport_container and is_instance_valid(viewport_container):
			var viewport: SubViewport = viewport_container.get_node_or_null("SubViewport")
			if viewport:
				var model_holder: Node3D = viewport.get_node_or_null("ModelHolder")
				if model_holder:
					model_holder.rotate_y(model_rotation_speed * 0.8 * delta)


# ========== PLAYER MODEL ==========

func _setup_player_model() -> void:
	if not player_model_container:
		return
	
	if player_model_instance:
		player_model_instance.queue_free()
		player_model_instance = null
	
	var model_scene: PackedScene = null
	var texture_path: String = ""
	
	if shop_manager:
		var model_path: String = shop_manager.get_selected_skin_model_path()
		texture_path = shop_manager.get_selected_skin_texture_path()
		
		if ResourceLoader.exists(model_path):
			model_scene = load(model_path)
	
	if not model_scene:
		model_scene = PLAYER_MODEL_SCENE
	
	if model_scene:
		player_model_instance = model_scene.instantiate()
		player_model_instance.scale = Vector3(0.3, 0.3, 0.3)
		player_model_container.add_child(player_model_instance)
		
		if texture_path and ResourceLoader.exists(texture_path):
			var texture: Texture2D = load(texture_path)
			if texture:
				_apply_skin_texture_to_model(player_model_instance, texture)
		
		_apply_unshaded_material(player_model_instance)


func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_find_all_mesh_instances(child))
	return result


func _apply_skin_texture_to_model(node: Node, texture: Texture2D) -> void:
	for mesh_inst: MeshInstance3D in _find_all_mesh_instances(node):
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				mesh_inst.set_surface_override_material(i, material)


func _apply_unshaded_material(node: Node) -> void:
	for mesh_inst: MeshInstance3D in _find_all_mesh_instances(node):
		# Skip if there's already a surface override material (texture skin)
		var has_override := false
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				if mesh_inst.get_surface_override_material(i) != null:
					has_override = true
					break
		
		if has_override:
			# Already has texture - just ensure it's unshaded (it should be from _apply_skin_texture_to_model)
			continue
		
		var original_mat: Material = null
		if mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
			original_mat = mesh_inst.mesh.surface_get_material(0)
		
		var unshaded_mat := StandardMaterial3D.new()
		unshaded_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		if original_mat and original_mat is StandardMaterial3D:
			var orig_std: StandardMaterial3D = original_mat as StandardMaterial3D
			unshaded_mat.albedo_color = orig_std.albedo_color
			if orig_std.albedo_texture:
				unshaded_mat.albedo_texture = orig_std.albedo_texture
		else:
			unshaded_mat.albedo_color = Color(0.8, 0.8, 0.8, 1.0)
		
		mesh_inst.material_override = unshaded_mat


# ========== BALANCE DISPLAY ==========

func _setup_balance_display() -> void:
	balance_container = HBoxContainer.new()
	balance_container.add_theme_constant_override("separation", 10)
	
	var screen_size := get_viewport().get_visible_rect().size
	balance_container.position = Vector2(screen_size.x - 200, 20)
	
	var coin_icon := TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(32, 32)
	coin_icon.texture = load("res://assets/svg/coin.svg")
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = COLOR_ACCENT_GOLD
	balance_container.add_child(coin_icon)
	
	balance_label = Label.new()
	balance_label.text = _format_balance(stats.get("coin_balance", 0))
	balance_label.add_theme_font_size_override("font_size", 28)
	balance_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	balance_label.add_theme_color_override("font_outline_color", Color(0.1, 0.1, 0.15, 0.8))
	balance_label.add_theme_constant_override("outline_size", 3)
	balance_container.add_child(balance_label)
	
	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.1, 0.15, 0.85)
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = COLOR_ACCENT_GOLD.darkened(0.3)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	
	card.position = Vector2(screen_size.x - 200, 20)
	card.add_child(balance_container)
	balance_container.position = Vector2.ZERO
	
	add_child(card)


func _update_balance_display() -> void:
	if balance_label:
		balance_label.text = _format_balance(stats.get("coin_balance", 0))


func _format_balance(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.1fK" % (amount / 1000.0)
	return str(amount)


# ========== SPEED LINES EFFECT ==========

func _setup_speed_lines() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	
	var lines := GPUParticles2D.new()
	lines.name = "SpeedLines"
	lines.amount = 25
	lines.lifetime = 0.6
	lines.z_index = 1  # Above background but below UI
	lines.local_coords = false
	lines.emitting = true
	
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(viewport_size.x / 2.0, 10, 1)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 0
	mat.initial_velocity_min = 800
	mat.initial_velocity_max = 1200
	mat.gravity = Vector3.ZERO
	mat.angle_min = -5
	mat.angle_max = 5
	mat.scale_min = 0.3
	mat.scale_max = 0.8
	mat.color = Color(0.25, 0.65, 0.96, 0.15)
	
	lines.process_material = mat
	
	# Create a simple line texture for 2D particles
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.25, 0.65, 0.96, 0.3))
	gradient.set_color(1, Color(0.25, 0.65, 0.96, 0.0))
	var line_texture := GradientTexture2D.new()
	line_texture.gradient = gradient
	line_texture.width = 4
	line_texture.height = 64
	line_texture.fill = GradientTexture2D.FILL_LINEAR
	line_texture.fill_from = Vector2(0.5, 0)
	line_texture.fill_to = Vector2(0.5, 1)
	lines.texture = line_texture
	
	lines.position = Vector2(viewport_size.x / 2.0, -100)
	lines.visibility_rect = Rect2(-100, -200, viewport_size.x + 200, viewport_size.y + 400)
	
	$Background.add_sibling(lines)
	
	# Ambient orbs
	var orbs := GPUParticles2D.new()
	orbs.name = "AmbientOrbs"
	orbs.amount = 15
	orbs.lifetime = 4.0
	orbs.z_index = 1  # Above background but below UI
	orbs.local_coords = false
	orbs.emitting = true
	
	var orb_mat := ParticleProcessMaterial.new()
	orb_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	orb_mat.emission_box_extents = Vector3(viewport_size.x / 2.0, viewport_size.y / 2.0, 1)
	orb_mat.direction = Vector3(0, -1, 0)
	orb_mat.spread = 180
	orb_mat.initial_velocity_min = 20
	orb_mat.initial_velocity_max = 50
	orb_mat.gravity = Vector3.ZERO
	orb_mat.scale_min = 0.5
	orb_mat.scale_max = 1.5
	orb_mat.color = Color(0.25, 0.65, 0.96, 0.15)
	
	orbs.process_material = orb_mat
	
	# Create a circular orb texture
	var orb_gradient := Gradient.new()
	orb_gradient.set_color(0, Color(0.25, 0.65, 0.96, 0.3))
	orb_gradient.set_color(1, Color(0.25, 0.65, 0.96, 0.0))
	var orb_texture := GradientTexture2D.new()
	orb_texture.gradient = orb_gradient
	orb_texture.width = 32
	orb_texture.height = 32
	orb_texture.fill = GradientTexture2D.FILL_RADIAL
	orb_texture.fill_from = Vector2(0.5, 0.5)
	orb_texture.fill_to = Vector2(1.0, 0.5)
	orbs.texture = orb_texture
	
	orbs.position = Vector2(viewport_size.x / 2.0, viewport_size.y / 2.0)
	orbs.visibility_rect = Rect2(-100, -100, viewport_size.x + 200, viewport_size.y + 200)
	
	$Background.add_sibling(orbs)


func _apply_safe_area_offset() -> void:
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size := DisplayServer.screen_get_size()
	
	var top_inset := safe_area.position.y
	var bottom_inset := screen_size.y - safe_area.end.y
	
	if top_inset > 0:
		main_content.offset_top = top_inset


# ========== STATS MANAGEMENT ==========

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
	
	var gm: Object = Engine.get_singleton("GameManager") if Engine.has_singleton("GameManager") else null
	if not gm:
		gm = (func() -> Node:
			var tree: SceneTree = Engine.get_main_loop() as SceneTree
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


# ========== BUTTON ACTIONS ==========

func _on_play_button_pressed() -> void:
	audio_manager.play_button_click()
	if animation_player.has_animation("exit"):
		animation_player.play("exit")
		await animation_player.animation_finished
	var st: Node = get_node("/root/SceneTransition")
	st.change_scene("res://scenes/game.tscn")


func _on_stats_button_pressed() -> void:
	audio_manager.play_button_click()
	_load_stats()
	stats_helper.update_stats(stats)
	stats_helper.rebuild()
	_connect_stats_buttons()
	_animate_panel_in(stats_panel)


func _connect_stats_buttons() -> void:
	var stats_back: Button = stats_helper.get_back_button()
	if stats_back and not stats_back.pressed.is_connected(_on_stats_back_pressed):
		stats_back.pressed.connect(_on_stats_back_pressed)
	
	var stats_prev: Button = stats_helper.get_prev_button()
	if stats_prev and not stats_prev.pressed.is_connected(_on_stats_section_prev):
		stats_prev.pressed.connect(_on_stats_section_prev)
	
	var stats_next: Button = stats_helper.get_next_button()
	if stats_next and not stats_next.pressed.is_connected(_on_stats_section_next):
		stats_next.pressed.connect(_on_stats_section_next)


func _on_stats_section_prev() -> void:
	audio_manager.play_button_click()
	stats_helper.prev_section()


func _on_stats_section_next() -> void:
	audio_manager.play_button_click()
	stats_helper.next_section()


func _on_stats_back_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_out(stats_panel)


func _on_settings_button_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_in(settings_panel)


func _on_settings_back_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_out(settings_panel)


func _on_shop_button_pressed() -> void:
	audio_manager.play_button_click()
	_load_stats()
	shop_helper.update_stats(stats)
	shop_helper.rebuild()
	_connect_shop_buttons()
	_animate_panel_in(shop_panel)


func _connect_shop_buttons() -> void:
	var shop_back: Button = shop_helper.get_back_button()
	if shop_back and not shop_back.pressed.is_connected(_on_shop_back_pressed):
		shop_back.pressed.connect(_on_shop_back_pressed)


func _on_shop_back_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_out(shop_panel)


func _on_quit_button_pressed() -> void:
	audio_manager.play_button_click()
	if animation_player.has_animation("exit"):
		animation_player.play("exit")
		await animation_player.animation_finished
	get_tree().quit()


# ========== PANEL ANIMATIONS ==========

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


# ========== HELPER SIGNAL HANDLERS ==========

func _on_stats_reload_needed() -> void:
	_load_stats()
	shop_helper.update_stats(stats)
	shop_helper.update_balance()


func _on_balance_update_needed() -> void:
	_update_balance_display()


func _on_shop_balance_changed(_new_balance: int) -> void:
	_load_stats()
	_update_balance_display()

extends Control
## Main Menu with modern Roblox-style UI design
## Uses helper classes for panel management
## Stats use SecureStorage for encrypted persistence

const PLAYER_MODEL_SCENE := preload("res://assets/models/players/player_1.blend")

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
@onready var quest_panel: Control = $QuestPanel
@onready var main_content: VBoxContainer = $MainContent
@onready var player_model_container: Node3D = $PlayerContainer/PlayerViewport/SubViewport/PlayerModel
@onready var button_grid: GridContainer = $MainContent/ButtonGrid
@onready var play_button: Button = $MainContent/ButtonGrid/PlayButton
@onready var stats_button: Button = $MainContent/ButtonGrid/StatsButton
@onready var shop_button: Button = $MainContent/ButtonGrid/ShopButton
@onready var quest_button: Button = $MainContent/ButtonGrid/QuestButton
@onready var settings_button: Button = $MainContent/ButtonGrid/SettingsButton
@onready var quit_button: Button = $MainContent/ButtonGrid/QuitButton
@onready var title_label: Label = $MainContent/TitleContainer/Title
@onready var balance_card: PanelContainer = $BalanceCard
@onready var balance_label: Label = $BalanceCard/HBox/BalanceLabel

var audio_manager: Node
var title_outline_tween: Tween
var shop_manager: Node
var player_model_instance: Node3D
var model_rotation_speed := 0.5

# Helper instances
var settings_helper: RefCounted
var stats_helper: RefCounted
var shop_helper: RefCounted
var quest_helper: RefCounted

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
	quest_helper = QuestPanelHelper.new(quest_panel)
	
	# Connect shop helper signals
	shop_helper.stats_reload_needed.connect(_on_stats_reload_needed)
	shop_helper.balance_update_needed.connect(_on_balance_update_needed)
	shop_helper.player_model_refresh_needed.connect(_setup_player_model)
	
	# Build helper panels
	settings_helper.rebuild()
	stats_helper.rebuild()
	shop_helper.rebuild()
	quest_helper.rebuild()
	
	# Connect panel back buttons
	_connect_panel_buttons()
	
	_update_balance_display()
	_apply_safe_area_offset()
	_setup_player_model()
	_adjust_particle_positions()
	_setup_title_animation()
	
	# Connect shop manager signals
	if shop_manager:
		shop_manager.balance_changed.connect(_on_shop_balance_changed)
		shop_manager.skin_changed.connect(_on_skin_changed)
	
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
	
	# Quest panel
	var quest_back: Button = quest_helper.get_back_button()
	if quest_back and not quest_back.pressed.is_connected(_on_quest_back_pressed):
		quest_back.pressed.connect(_on_quest_back_pressed)


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
	
	# Rotate quest panel object previews
	for viewport_container in quest_helper.get_object_viewports():
		if viewport_container and is_instance_valid(viewport_container):
			var viewport: SubViewport = viewport_container.get_node_or_null("SubViewport")
			if viewport:
				var model_holder: Node3D = viewport.get_node_or_null("ModelHolder")
				if model_holder:
					model_holder.rotate_y(model_rotation_speed * 0.8 * delta)
	
	# Update quest panel countdown timer
	if quest_panel and quest_panel.visible and quest_helper:
		quest_helper.process(delta)


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
		var skin_material := StandardMaterial3D.new()
		skin_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		skin_material.albedo_texture = texture
		skin_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				mesh_inst.set_surface_override_material(i, skin_material)


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

func _update_balance_display() -> void:
	if balance_label:
		balance_label.text = _format_balance(stats.get("coin_balance", 0))


func _format_balance(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.1fK" % (amount / 1000.0)
	return str(amount)


# ========== PARTICLES ADJUSTMENT ==========

func _adjust_particle_positions() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var center := viewport_size / 2.0
	
	var dust_particles := get_node_or_null("DustParticles") as GPUParticles2D
	if dust_particles:
		dust_particles.position = center
		dust_particles.visibility_rect = Rect2(-100, -100, viewport_size.x + 200, viewport_size.y + 200)
		var mat := dust_particles.process_material as ParticleProcessMaterial
		if mat:
			mat.emission_box_extents = Vector3(center.x, center.y, 1)


# ========== TITLE ANIMATION ==========

func _setup_title_animation() -> void:
	if not title_label:
		return
	
	# Base color: #9c6dff (0.61, 0.43, 1.0)
	# More pronounced variations for visible cycling
	var color_base := Color(0.61, 0.43, 1.0, 1.0)
	var color_warm := Color(1.0, 0.45, 0.75, 1.0)   # Pink/magenta
	var color_cool := Color(0.35, 0.65, 1.0, 1.0)   # Bright blue
	
	_animate_title_outline_loop(color_base, color_warm, color_cool)


func _animate_title_outline_loop(base: Color, warm: Color, cool: Color) -> void:
	if title_outline_tween:
		title_outline_tween.kill()
	
	title_outline_tween = create_tween()
	title_outline_tween.set_loops()  # Infinite loop
	title_outline_tween.set_ease(Tween.EASE_IN_OUT)
	title_outline_tween.set_trans(Tween.TRANS_SINE)
	
	# Smooth cycle: base -> warm -> base -> cool -> base
	title_outline_tween.tween_method(_set_title_outline_color, base, warm, 2.5)
	title_outline_tween.tween_method(_set_title_outline_color, warm, base, 2.5)
	title_outline_tween.tween_method(_set_title_outline_color, base, cool, 2.5)
	title_outline_tween.tween_method(_set_title_outline_color, cool, base, 2.5)


func _set_title_outline_color(color: Color) -> void:
	if title_label:
		title_label.add_theme_color_override("font_outline_color", color)


func _apply_safe_area_offset() -> void:
	var safe_area := DisplayServer.get_display_safe_area()
	var physical_screen := Vector2(DisplayServer.screen_get_size())
	var viewport_size := get_viewport().get_visible_rect().size
	var scale_y: float = viewport_size.y / physical_screen.y
	var top_inset: float = safe_area.position.y * scale_y
	
	if top_inset > 0:
		main_content.offset_top = top_inset
		if balance_card:
			balance_card.offset_top = 20 + top_inset
			balance_card.offset_bottom = 80 + top_inset


# ========== STATS MANAGEMENT (via SecureStorage) ==========

func _load_stats() -> void:
	var storage := get_node_or_null("/root/SecureStorage")
	if storage:
		var secure_stats: Dictionary = storage.get_stats()
		stats["games_played"] = secure_stats.get("total_games", 0)
		stats["total_coins"] = secure_stats.get("total_coins_earned", 0)
		stats["max_coins"] = secure_stats.get("best_coins", 0)
		stats["total_distance"] = secure_stats.get("total_distance", 0.0)
		stats["max_distance"] = secure_stats.get("best_distance", 0.0)
		stats["total_time"] = secure_stats.get("total_time_played", 0.0)
		stats["max_time"] = secure_stats.get("best_time", 0.0)
		stats["coin_balance"] = storage.get_coin_balance()
		# Load destroyed objects from persistent storage
		stats["destroyed_objects"] = storage.get_destroyed_objects()


func _save_stats() -> void:
	# Stats are saved through SecureStorage automatically
	# This function is kept for compatibility but does nothing
	pass


static func record_game_stats(coins: int, distance: float, game_time: float = 0.0) -> void:
	# Use SecureStorage for recording stats
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if not tree:
		return
	
	var storage: Node = tree.root.get_node_or_null("/root/SecureStorage")
	if storage:
		storage.record_game_stats(coins, distance, game_time)


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
	stats_helper.stop_stats_cycling()
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


func _on_quest_button_pressed() -> void:
	audio_manager.play_button_click()
	quest_helper.rebuild()
	# Defer button connection to ensure rebuild is complete
	call_deferred("_connect_quest_buttons")
	_animate_panel_in(quest_panel)


func _connect_quest_buttons() -> void:
	var quest_back: Button = quest_helper.get_back_button()
	if quest_back and not quest_back.pressed.is_connected(_on_quest_back_pressed):
		quest_back.pressed.connect(_on_quest_back_pressed)


func _on_quest_back_pressed() -> void:
	audio_manager.play_button_click()
	_animate_panel_out(quest_panel)


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


func _on_skin_changed(_skin_id: String) -> void:
	_setup_player_model()

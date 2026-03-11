class_name StatsPanelHelper
extends RefCounted
## Helper class for managing the stats panel UI
## Loads UI structure from scene file, dynamically populates object cards

const CONTENT_SCENE := preload("res://scenes/ui/stats_panel_content.tscn")
const ObjectConfigScript := preload("res://scripts/config/object_config.gd")

# Color palette
const COLOR_BG_DARK := Color(0.06, 0.08, 0.12, 1.0)
const COLOR_BG_LIGHT := Color(0.14, 0.18, 0.26, 1.0)
const COLOR_ACCENT_PRIMARY := Color(0.25, 0.65, 0.96, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.30, 0.85, 0.55, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.7, 0.75, 0.85, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.65, 1.0)
const COLOR_BORDER := Color(0.25, 0.32, 0.45, 0.8)

const OBJECT_SECTIONS := ["Trees", "Buildings", "Friend NPC", "Enemy NPC", "Enemy Building"]

var stats_panel: Control
var stats: Dictionary
var content_instance: Node
var current_section_index: int = 0
var object_viewports: Array[SubViewportContainer] = []

# UI References
var global_stats_card: PanelContainer
var games_value_label: RichTextLabel
var coins_value_label: RichTextLabel
var distance_value_label: RichTextLabel
var time_value_label: RichTextLabel
var section_label: Label
var object_grid: GridContainer

# Stats cycling
var stats_cycle_index: int = 0
var stats_cycle_tween: Tween
const STATS_CYCLE_LABELS := ["Best", "Avg", "Total"]
const STATS_CYCLE_INTERVAL := 5.0


func _init(panel: Control, stats_dict: Dictionary) -> void:
	stats_panel = panel
	stats = stats_dict


func rebuild() -> void:
	# Clear existing content except Background
	var children_to_remove: Array[Node] = []
	for child in stats_panel.get_children():
		if child.name != "Background":
			children_to_remove.append(child)
	for child in children_to_remove:
		stats_panel.remove_child(child)
		child.free()
	
	object_viewports.clear()
	
	# Update background
	var bg: ColorRect = stats_panel.get_node_or_null("Background")
	if bg:
		bg.color = Color(0, 0, 0, 0.92)
	
	# Calculate safe area offset
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size: Vector2 = stats_panel.get_viewport().get_visible_rect().size
	var physical_screen := Vector2(DisplayServer.screen_get_size())
	var scale_y: float = screen_size.y / physical_screen.y if physical_screen.y > 0 else 1.0
	var top_inset: float = safe_area.position.y * scale_y
	
	# Instance and add the content scene
	content_instance = CONTENT_SCENE.instantiate()
	content_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_instance.offset_top = top_inset
	stats_panel.add_child(content_instance)
	
	# Get references to UI elements
	_find_ui_references()
	
	# Update global stats values
	_update_global_stats()
	
	# Populate initial object section
	_populate_object_cards()


func _find_ui_references() -> void:
	global_stats_card = content_instance.get_node("%GlobalStatsCard") as PanelContainer
	games_value_label = content_instance.get_node("%GamesValue") as RichTextLabel
	coins_value_label = content_instance.get_node("%CoinsValue") as RichTextLabel
	distance_value_label = content_instance.get_node("%DistanceValue") as RichTextLabel
	time_value_label = content_instance.get_node("%TimeValue") as RichTextLabel
	section_label = content_instance.get_node("%SectionLabel") as Label
	object_grid = content_instance.get_node("%ObjectGrid") as GridContainer


func get_back_button() -> Button:
	if content_instance:
		return content_instance.get_node("%BackButton") as Button
	return null


func get_prev_button() -> Button:
	if content_instance:
		return content_instance.get_node("%PrevButton") as Button
	return null


func get_next_button() -> Button:
	if content_instance:
		return content_instance.get_node("%NextButton") as Button
	return null


func get_object_viewports() -> Array[SubViewportContainer]:
	return object_viewports


func stop_stats_cycling() -> void:
	if stats_cycle_tween and stats_cycle_tween.is_valid():
		stats_cycle_tween.kill()
		stats_cycle_tween = null


func update_stats(new_stats: Dictionary) -> void:
	stats = new_stats


func prev_section() -> void:
	current_section_index = (current_section_index - 1 + OBJECT_SECTIONS.size()) % OBJECT_SECTIONS.size()
	_update_section_display()


func next_section() -> void:
	current_section_index = (current_section_index + 1) % OBJECT_SECTIONS.size()
	_update_section_display()


func _update_section_display() -> void:
	if section_label:
		section_label.text = OBJECT_SECTIONS[current_section_index]
	_populate_object_cards()


func _update_global_stats() -> void:
	var games_count: int = stats.get("games_played", 0)
	
	# Games played
	if games_value_label:
		games_value_label.text = "[right]%s[/right]" % _format_number(games_count)
	
	# Update cycling stats display
	_update_cycling_stats_display()
	
	# Start cycling if not already running
	_start_stats_cycling()


func _start_stats_cycling() -> void:
	if stats_cycle_tween and stats_cycle_tween.is_valid():
		return  # Already running
	
	stats_cycle_tween = stats_panel.create_tween()
	stats_cycle_tween.set_loops()
	stats_cycle_tween.tween_interval(STATS_CYCLE_INTERVAL)
	stats_cycle_tween.tween_callback(_on_stats_cycle)


func _on_stats_cycle() -> void:
	stats_cycle_index = (stats_cycle_index + 1) % 3
	_update_cycling_stats_display()


func _update_cycling_stats_display() -> void:
	var games_count: int = stats.get("games_played", 0)
	var label_prefix: String = STATS_CYCLE_LABELS[stats_cycle_index]
	
	# Coins stats
	if coins_value_label:
		var max_c: int = stats.get("max_coins", 0)
		var total_c: int = stats.get("total_coins", 0)
		var avg_c: int = int(float(total_c) / games_count) if games_count > 0 else 0
		var value: int = [max_c, avg_c, total_c][stats_cycle_index]
		coins_value_label.text = _format_stat_bbcode(label_prefix, _format_number(value), COLOR_ACCENT_GOLD)
	
	# Distance stats
	if distance_value_label:
		var max_d: float = stats.get("max_distance", 0.0)
		var total_d: float = stats.get("total_distance", 0.0)
		var avg_d: float = total_d / games_count if games_count > 0 else 0.0
		var value_d: float = [max_d, avg_d, total_d][stats_cycle_index]
		distance_value_label.text = _format_stat_bbcode(label_prefix, _format_number(int(value_d)) + "m", COLOR_ACCENT_PRIMARY)
	
	# Time stats
	if time_value_label:
		var max_t: float = stats.get("max_time", 0.0)
		var total_t: float = stats.get("total_time", 0.0)
		var avg_t: float = total_t / games_count if games_count > 0 else 0.0
		var value_t: float = [max_t, avg_t, total_t][stats_cycle_index]
		time_value_label.text = _format_stat_bbcode(label_prefix, _format_time(value_t), COLOR_ACCENT_SECONDARY)


func _format_stat_bbcode(label: String, value: String, accent_color: Color) -> String:
	var color_hex := accent_color.to_html(false)
	return "[right][color=#%s]%s[/color]  [color=#ffffff]%s[/color][/right]" % [color_hex, label, value]


func _format_number(amount: int) -> String:
	if amount >= 1000000:
		return "%.3f M" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.3f k" % (amount / 1000.0)
	return str(amount)


func _format_time(time_seconds: float) -> String:
	var total_seconds := int(time_seconds)
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var seconds := total_seconds % 60
	if hours > 0:
		return "%dh %dmin %ds" % [hours, minutes, seconds]
	if minutes > 0:
		return "%dmin %ds" % [minutes, seconds]
	return "%ds" % seconds


func _populate_object_cards() -> void:
	if not object_grid:
		return
	
	for child in object_grid.get_children():
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
			objects += ObjectConfigScript.get_objects_by_category(ObjectConfigScript.Category.NPC_AERIAL)
		4:
			objects = ObjectConfigScript.get_building_enemies()
	
	var destroyed: Dictionary = stats.get("destroyed_objects", {})
	
	if objects.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No objects in this category"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 36)
		empty_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		object_grid.add_child(empty_label)
		return
	
	for obj_data in objects:
		var card := _create_object_card(obj_data, destroyed.get(obj_data.id, 0))
		object_grid.add_child(card)


func _create_object_card(obj_data: RefCounted, kill_count: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 180)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(2)
	style.border_color = COLOR_BORDER if kill_count > 0 else Color(0.3, 0.3, 0.35, 0.5)
	style.set_content_margin_all(16)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_child(hbox)
	
	# 3D Preview
	var preview := _create_3d_preview(obj_data, kill_count)
	hbox.add_child(preview)
	object_viewports.append(preview)
	
	# Info section
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_theme_constant_override("separation", 8)
	hbox.add_child(info)
	
	# Object name
	var name_label := Label.new()
	name_label.text = obj_data.display_name if kill_count > 0 else "???"
	name_label.add_theme_font_size_override("font_size", 44)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY if kill_count > 0 else COLOR_TEXT_MUTED)
	info.add_child(name_label)
	
	# Stats row
	var stats_row := HBoxContainer.new()
	stats_row.add_theme_constant_override("separation", 24)
	stats_row.mouse_filter = Control.MOUSE_FILTER_PASS
	info.add_child(stats_row)
	
	# Coins
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", 8)
	coin_row.mouse_filter = Control.MOUSE_FILTER_PASS
	stats_row.add_child(coin_row)
	
	var coin_icon := TextureRect.new()
	coin_icon.custom_minimum_size = Vector2(36, 36)
	coin_icon.texture = load("res://assets/svg/coin.svg")
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = COLOR_ACCENT_GOLD if kill_count > 0 else COLOR_TEXT_MUTED
	coin_icon.mouse_filter = Control.MOUSE_FILTER_PASS
	coin_row.add_child(coin_icon)
	
	var coin_label := Label.new()
	coin_label.text = "%d" % obj_data.coins if kill_count > 0 else "?"
	coin_label.add_theme_font_size_override("font_size", 36)
	coin_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD if kill_count > 0 else COLOR_TEXT_MUTED)
	coin_row.add_child(coin_label)
	
	# Spawn chance
	var spawn_label := Label.new()
	spawn_label.text = "Spawn: %.0f%%" % (obj_data.spawn_chance * 100) if kill_count > 0 else "Spawn: ?%"
	spawn_label.add_theme_font_size_override("font_size", 28)
	spawn_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY if kill_count > 0 else COLOR_TEXT_MUTED)
	stats_row.add_child(spawn_label)
	
	# Supercharge indicator for large buildings and enemy buildings
	if obj_data.category == ObjectConfigScript.Category.BUILDING_LARGE or obj_data.category == ObjectConfigScript.Category.BUILDING_ENEMY:
		var supercharge_label := Label.new()
		supercharge_label.text = "ARMORED" if kill_count > 0 else "???"
		supercharge_label.add_theme_font_size_override("font_size", 28)
		supercharge_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD if kill_count > 0 else COLOR_TEXT_MUTED)
		stats_row.add_child(supercharge_label)
	
	# Kill count badge
	var kill_badge := _create_kill_badge(kill_count)
	info.add_child(kill_badge)
	
	return card


func _create_kill_badge(count: int) -> HBoxContainer:
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 12)
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_PASS
	var badge_style := StyleBoxFlat.new()
	badge_style.set_corner_radius_all(10)
	badge_style.set_content_margin_all(8)
	badge_style.content_margin_left = 16
	badge_style.content_margin_right = 16
	
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
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", COLOR_ACCENT_SECONDARY if count > 0 else COLOR_TEXT_MUTED)
	badge.add_child(label)
	
	container.add_child(badge)
	return container


func _create_3d_preview(obj_data: RefCounted, kill_count: int) -> SubViewportContainer:
	var preview_width := 156
	var preview_height := 156
	
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(preview_width, preview_height)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.transparent_bg = true
	viewport.size = Vector2i(preview_width, preview_height)
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

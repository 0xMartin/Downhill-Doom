class_name StatsObjectCard
extends PanelContainer
## Reusable card component for displaying object stats in the stats panel

const ObjectConfigScript := preload("res://scripts/config/object_config.gd")

# Color palette
const COLOR_BG_DARK := Color(0.06, 0.08, 0.12, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.30, 0.85, 0.55, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.7, 0.75, 0.85, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.65, 1.0)
const COLOR_BORDER := Color(0.25, 0.32, 0.45, 0.8)
const COLOR_BG_LIGHT := Color(0.14, 0.18, 0.26, 1.0)

var viewport_container: SubViewportContainer


func setup(obj_data: RefCounted, kill_count: int) -> void:
	var discovered := kill_count > 0
	
	# Get UI references (cannot use @onready since setup is called before _ready)
	var preview_container: Control = get_node("HBox/PreviewContainer")
	var name_label: Label = get_node("HBox/Info/NameLabel")
	var coin_icon: TextureRect = get_node("HBox/Info/StatsRow/CoinRow/CoinIcon")
	var coin_label: Label = get_node("HBox/Info/StatsRow/CoinRow/CoinLabel")
	var spawn_label: Label = get_node("HBox/Info/StatsRow/SpawnLabel")
	var armored_icon: TextureRect = get_node("HBox/Info/StatsRow/ArmoredIcon/Icon")
	var badge: PanelContainer = get_node("HBox/KillBadge/Badge")
	var destroyed_label: Label = get_node("HBox/KillBadge/Badge/VBox/DestroyedLabel")
	var kill_count_label: Label = get_node("HBox/KillBadge/Badge/VBox/KillCount")
	
	# Card style
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(2)
	style.border_color = COLOR_BORDER if discovered else Color(0.3, 0.3, 0.35, 0.5)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	
	# Name
	name_label.text = obj_data.display_name if discovered else "???"
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY if discovered else COLOR_TEXT_MUTED)
	
	# Coins
	coin_label.text = "%d" % obj_data.coins if discovered else "?"
	coin_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD if discovered else COLOR_TEXT_MUTED)
	coin_icon.modulate = COLOR_ACCENT_GOLD if discovered else COLOR_TEXT_MUTED
	
	# Spawn chance
	spawn_label.text = "Spawn: %.0f%%" % (obj_data.spawn_chance * 100) if discovered else "Spawn: ?%"
	spawn_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY if discovered else COLOR_TEXT_MUTED)
	
	# Armored indicator for large buildings and enemy buildings
	if obj_data.category == ObjectConfigScript.Category.BUILDING_LARGE or obj_data.category == ObjectConfigScript.Category.BUILDING_ENEMY:
		armored_icon.visible = true
		armored_icon.modulate = COLOR_ACCENT_GOLD if discovered else COLOR_TEXT_MUTED
	else:
		armored_icon.visible = false
	
	# Kill badge
	var badge_style := StyleBoxFlat.new()
	badge_style.set_corner_radius_all(12)
	badge_style.set_content_margin_all(12)
	badge_style.content_margin_left = 20
	badge_style.content_margin_right = 20
	if discovered:
		badge_style.bg_color = COLOR_ACCENT_SECONDARY.darkened(0.5)
		badge_style.border_color = COLOR_ACCENT_SECONDARY
	else:
		badge_style.bg_color = COLOR_BG_LIGHT
		badge_style.border_color = COLOR_BORDER
	badge_style.set_border_width_all(2)
	badge.add_theme_stylebox_override("panel", badge_style)
	
	destroyed_label.add_theme_color_override("font_color", COLOR_ACCENT_SECONDARY if discovered else COLOR_TEXT_MUTED)
	kill_count_label.text = _format_number(kill_count)
	kill_count_label.add_theme_color_override("font_color", COLOR_ACCENT_SECONDARY if discovered else COLOR_TEXT_MUTED)
	
	# 3D Preview
	viewport_container = _create_3d_preview(preview_container, obj_data, kill_count)
	preview_container.add_child(viewport_container)


func get_viewport_container() -> SubViewportContainer:
	return viewport_container


func _create_3d_preview(preview_container: Control, obj_data: RefCounted, kill_count: int) -> SubViewportContainer:
	var preview_width: float = preview_container.size.x if preview_container else 220.0
	var preview_height: float = preview_container.size.y if preview_container else 220.0
	
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(preview_width, preview_height)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.transparent_bg = true
	viewport.size = Vector2i(int(preview_width), int(preview_height))
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


func _format_number(amount: int) -> String:
	if amount >= 1000000:
		return "%.3fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.3fk" % (amount / 1000.0)
	return str(amount)

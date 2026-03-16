class_name QuestCard
extends PanelContainer
## Reusable card component for displaying daily quests

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
const COLOR_ACTIVE := Color(0.25, 0.65, 0.96, 1.0)
const COLOR_COMPLETED := Color(0.30, 0.85, 0.55, 1.0)
const COLOR_EASY := Color(0.4, 0.8, 0.4)
const COLOR_MEDIUM := Color(0.9, 0.7, 0.2)
const COLOR_HARD := Color(0.9, 0.3, 0.3)

signal activate_pressed(quest_id: String)

var quest_data: RefCounted = null
var _quest_id: String = ""


func setup(quest: RefCounted, progress: int, is_active: bool, is_completed: bool) -> void:
	quest_data = quest
	_quest_id = quest.id
	
	# Get UI references using direct paths (% syntax doesn't work when instantiated)
	var type_icon: TextureRect = get_node_or_null("HBox/IconContainer/TypeIcon")
	var target_preview: Control = get_node_or_null("HBox/IconContainer/TargetPreview")
	var title_label: Label = get_node_or_null("HBox/Content/TitleLabel")
	var description_label: Label = get_node_or_null("HBox/Content/DescriptionLabel")
	var progress_bar: ProgressBar = get_node_or_null("HBox/Content/ProgressContainer/ProgressBar")
	var progress_label: Label = get_node_or_null("HBox/Content/ProgressContainer/ProgressLabel")
	var reward_icon: TextureRect = get_node_or_null("HBox/Content/RewardContainer/RewardIcon")
	var reward_value_label: Label = get_node_or_null("HBox/Content/RewardContainer/RewardValueLabel")
	var activate_button: Button = get_node_or_null("HBox/RightPanel/ActivateButton")
	var status_label: Label = get_node_or_null("HBox/RightPanel/StatusLabel")
	
	# Set card style based on state (use metadata styles)
	if is_active or is_completed:
		if has_meta("_active_style"):
			var active_style: StyleBoxFlat = get_meta("_active_style").duplicate()
			if is_completed:
				active_style.border_color = COLOR_COMPLETED
			add_theme_stylebox_override("panel", active_style)
	else:
		if has_meta("_normal_style"):
			add_theme_stylebox_override("panel", get_meta("_normal_style"))
	
	# Type icon
	var icon_path := QuestConfig.get_quest_type_icon(quest.type)
	if type_icon:
		if ResourceLoader.exists(icon_path):
			type_icon.texture = load(icon_path)
			type_icon.visible = true
		else:
			type_icon.visible = false
	
	# Target preview for KILL_SPECIFIC quests
	if target_preview and type_icon:
		if quest.type == QuestConfig.QuestType.KILL_SPECIFIC and not quest.target_object_id.is_empty():
			_setup_target_preview(target_preview, quest.target_object_id)
			target_preview.visible = true
			type_icon.visible = false
		else:
			target_preview.visible = false
	
	# Title and description
	if title_label:
		title_label.text = quest.short_description
	if description_label:
		description_label.text = _get_mode_description(quest)
	
	# Progress bar
	var target: int = quest.target_value
	var current := mini(progress, target)
	if progress_bar:
		progress_bar.max_value = target
		progress_bar.value = current
		# Style progress bar fill
		var fill_style: StyleBoxFlat = progress_bar.get_theme_stylebox("fill").duplicate()
		if is_completed:
			fill_style.bg_color = COLOR_COMPLETED
		elif is_active:
			fill_style.bg_color = COLOR_ACTIVE
		else:
			fill_style.bg_color = COLOR_TEXT_MUTED
		progress_bar.add_theme_stylebox_override("fill", fill_style)
	if progress_label:
		progress_label.text = "%s / %s" % [_format_number(current), _format_number(target)]
	
	# Reward
	if reward_icon and reward_value_label:
		_setup_reward_display(reward_icon, reward_value_label, quest)
	
	# Activate button / Status
	if is_completed:
		if activate_button:
			activate_button.visible = false
		if status_label:
			status_label.visible = true
			status_label.text = "COMPLETED"
			status_label.add_theme_color_override("font_color", COLOR_COMPLETED)
	elif is_active:
		if activate_button:
			activate_button.visible = false
		if status_label:
			status_label.visible = true
			status_label.text = "ACTIVE"
			status_label.add_theme_color_override("font_color", COLOR_ACTIVE)
	else:
		if activate_button:
			activate_button.visible = true
			if not activate_button.pressed.is_connected(_on_activate_pressed):
				activate_button.pressed.connect(_on_activate_pressed)
		if status_label:
			status_label.visible = false


func _setup_target_preview(container: Control, object_id: String) -> void:
	# Clear existing children
	for child in container.get_children():
		child.queue_free()
	
	var obj_data: ObjectConfig.ObjectData = ObjectConfig.get_object(object_id)
	if not obj_data:
		return
	
	# Use the same approach as stats_object_card for 3D preview
	var preview_width: float = 100.0
	var preview_height: float = 100.0
	
	var viewport_container := SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(preview_width, preview_height)
	viewport_container.stretch = true
	viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	
	var viewport := SubViewport.new()
	viewport.name = "SubViewport"
	viewport.transparent_bg = true
	viewport.size = Vector2i(int(preview_width), int(preview_height))
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	viewport.own_world_3d = true
	viewport_container.add_child(viewport)
	
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
				var mesh_aabb: AABB = mesh_inst.mesh.get_aabb()
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
	
	container.add_child(viewport_container)


func _find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_find_all_mesh_instances(child))
	return result


func _setup_reward_display(icon: TextureRect, label: Label, quest: RefCounted) -> void:
	match quest.reward_type:
		QuestConfig.RewardType.COINS:
			if ResourceLoader.exists("res://assets/svg/coin.svg"):
				icon.texture = load("res://assets/svg/coin.svg")
			label.text = _format_number(quest.reward_value)
			label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
		QuestConfig.RewardType.BOOST:
			var boost_icon := _get_boost_icon(quest.reward_value)
			if ResourceLoader.exists(boost_icon):
				icon.texture = load(boost_icon)
			label.text = _get_boost_name(quest.reward_value)
			label.add_theme_color_override("font_color", COLOR_ACCENT_PRIMARY)
		QuestConfig.RewardType.CRATE:
			var crate_icon := _get_crate_icon(quest.reward_value)
			if ResourceLoader.exists(crate_icon):
				icon.texture = load(crate_icon)
			label.text = _get_crate_name(quest.reward_value)
			label.add_theme_color_override("font_color", COLOR_ACCENT_SECONDARY)


func _get_difficulty_color(difficulty: int) -> Color:
	match difficulty:
		QuestConfig.QuestDifficulty.EASY:
			return COLOR_EASY
		QuestConfig.QuestDifficulty.MEDIUM:
			return COLOR_MEDIUM
		QuestConfig.QuestDifficulty.HARD:
			return COLOR_HARD
	return COLOR_TEXT_SECONDARY


func _get_difficulty_text(difficulty: int) -> String:
	match difficulty:
		QuestConfig.QuestDifficulty.EASY:
			return "EASY"
		QuestConfig.QuestDifficulty.MEDIUM:
			return "MEDIUM"
		QuestConfig.QuestDifficulty.HARD:
			return "HARD"
	return "???"


func _get_mode_description(quest: RefCounted) -> String:
	if quest.mode == QuestConfig.QuestMode.MULTI_RUN:
		return "Progress across multiple runs"
	return "Complete in a single run"


func _format_number(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fk" % (value / 1000.0)
	return str(value)


func _get_boost_icon(boost_id: String) -> String:
	const BOOST_ICONS := {
		"double_hp": "res://assets/svg/boost_double_hp.svg",
		"double_coins": "res://assets/svg/boost_double_coins.svg",
		"no_enemy_npc": "res://assets/svg/boost_no_enemy_npc.svg",
		"no_enemy_building": "res://assets/svg/boost_no_enemy_building.svg",
		"no_holes": "res://assets/svg/boost_no_holes.svg",
		"half_supercharge": "res://assets/svg/boost_half_supercharge.svg",
		"double_supercharge": "res://assets/svg/boost_double_supercharge.svg",
	}
	return BOOST_ICONS.get(boost_id, "res://assets/svg/quest.svg")


func _get_boost_name(boost_id: String) -> String:
	const BOOST_NAMES := {
		"double_hp": "Double HP",
		"double_coins": "Double Coins",
		"no_enemy_npc": "No Enemy NPC",
		"no_enemy_building": "No Enemy Buildings",
		"no_holes": "No Holes",
		"half_supercharge": "Half Supercharge",
		"double_supercharge": "Double Supercharge",
	}
	return BOOST_NAMES.get(boost_id, boost_id)


func _get_crate_icon(crate_type: String) -> String:
	const CRATE_ICONS := {
		"basic": "res://assets/svg/crate_basic.svg",
		"premium": "res://assets/svg/crate_premium.svg",
		"legendary": "res://assets/svg/crate_legendary.svg",
	}
	return CRATE_ICONS.get(crate_type, "res://assets/svg/crate_basic.svg")


func _get_crate_name(crate_type: String) -> String:
	const CRATE_NAMES := {
		"basic": "Basic Crate",
		"premium": "Premium Crate",
		"legendary": "Legendary Crate",
	}
	return CRATE_NAMES.get(crate_type, crate_type)


func _on_activate_pressed() -> void:
	activate_pressed.emit(_quest_id)

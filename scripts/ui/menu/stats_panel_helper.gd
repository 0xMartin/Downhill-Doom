class_name StatsPanelHelper
extends RefCounted
## Helper class for managing the stats panel UI
## Loads UI structure from scene file, dynamically populates object cards

const CONTENT_SCENE := preload("res://scenes/ui/menu/stats_panel_content.tscn")
const OBJECT_CARD_SCENE := preload("res://scenes/ui/item/stats_object_card.tscn")
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
		var card = OBJECT_CARD_SCENE.instantiate()
		object_grid.add_child(card)
		card.setup(obj_data, destroyed.get(obj_data.id, 0))
		object_viewports.append(card.get_viewport_container())

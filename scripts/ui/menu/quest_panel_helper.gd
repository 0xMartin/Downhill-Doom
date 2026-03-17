class_name QuestPanelHelper
extends RefCounted
## Helper class for managing the quest panel UI
## Loads UI structure from scene file, dynamically populates quest cards

const CONTENT_SCENE := preload("res://scenes/ui/menu/quest_panel_content.tscn")
const QUEST_CARD_SCENE := preload("res://scenes/ui/item/quest_card.tscn")

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

var quest_panel: Control
var content_instance: Node
var quest_manager: Node
var object_viewports: Array[SubViewportContainer] = []

# UI References
var countdown_label: Label
var quest_list: VBoxContainer
var back_button: Button

# Update timer
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 1.0


func _init(panel: Control) -> void:
	quest_panel = panel
	quest_manager = Engine.get_singleton("QuestManager") if Engine.has_singleton("QuestManager") else null


func rebuild() -> void:
	# Get quest manager reference
	if not quest_manager:
		quest_manager = quest_panel.get_node_or_null("/root/QuestManager")
	if not quest_manager:
		push_error("QuestPanelHelper: Could not find QuestManager autoload")
	
	# Clear existing content except Background
	var children_to_remove: Array[Node] = []
	for child in quest_panel.get_children():
		if child.name != "Background":
			children_to_remove.append(child)
	for child in children_to_remove:
		quest_panel.remove_child(child)
		child.free()
	
	# Update background
	var bg: ColorRect = quest_panel.get_node_or_null("Background")
	if bg:
		bg.color = Color(0, 0, 0, 0.92)
	
	# Calculate safe area offset
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size: Vector2 = quest_panel.get_viewport().get_visible_rect().size
	var physical_screen := Vector2(DisplayServer.screen_get_size())
	var scale_y: float = screen_size.y / physical_screen.y if physical_screen.y > 0 else 1.0
	var top_inset: float = safe_area.position.y * scale_y
	
	# Instance and add the content scene
	content_instance = CONTENT_SCENE.instantiate()
	content_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_instance.offset_top = top_inset
	quest_panel.add_child(content_instance)
	
	# Get references to UI elements (immediate - nodes exist after add_child)
	_find_ui_references()
	
	# Setup back button icon
	_setup_back_button()
	
	# Update countdown
	_update_countdown()
	
	# Populate quests
	_populate_quest_cards()
	
	# Connect to quest manager signals
	if quest_manager:
		if not quest_manager.quest_progress_updated.is_connected(_on_quest_progress_updated):
			quest_manager.quest_progress_updated.connect(_on_quest_progress_updated)
		if not quest_manager.quest_completed.is_connected(_on_quest_completed):
			quest_manager.quest_completed.connect(_on_quest_completed)
		if not quest_manager.quests_refreshed.is_connected(_on_quests_refreshed):
			quest_manager.quests_refreshed.connect(_on_quests_refreshed)


func _find_ui_references() -> void:
	if not content_instance:
		push_error("QuestPanelHelper: content_instance is null")
		return
	
	# Use direct paths since % syntax requires script attached to owner
	countdown_label = content_instance.get_node_or_null("ScrollContainer/MarginContainer/ContentVBox/TimerCard/HBox/CountdownLabel") as Label
	quest_list = content_instance.get_node_or_null("ScrollContainer/MarginContainer/ContentVBox/QuestList") as VBoxContainer
	back_button = content_instance.get_node_or_null("Header/HBoxContainer/BackButton") as Button
	
	if not countdown_label:
		push_error("QuestPanelHelper: countdown_label not found")
	if not quest_list:
		push_error("QuestPanelHelper: quest_list not found")
	if not back_button:
		push_error("QuestPanelHelper: back_button not found")


func _setup_back_button() -> void:
	# Button styling is handled in the scene file
	pass


func get_back_button() -> Button:
	if back_button:
		return back_button
	if content_instance:
		return content_instance.get_node_or_null("Header/HBoxContainer/BackButton") as Button
	return null


func get_object_viewports() -> Array[SubViewportContainer]:
	return object_viewports


func process(delta: float) -> void:
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_countdown()


func _update_countdown() -> void:
	if not countdown_label:
		return
	
	var seconds := QuestConfig.get_seconds_until_reset()
	var hours := seconds / 3600
	var minutes := (seconds % 3600) / 60
	var secs := seconds % 60
	
	countdown_label.text = "%02d:%02d:%02d" % [hours, minutes, secs]


func _populate_quest_cards() -> void:
	if not quest_list:
		push_error("QuestPanelHelper: quest_list is null, cannot populate cards")
		return
	if not quest_manager:
		push_error("QuestPanelHelper: quest_manager is null, cannot get quests")
		return
	
	# Clear existing cards synchronously to prevent duplication
	var children_to_remove: Array[Node] = []
	for child in quest_list.get_children():
		children_to_remove.append(child)
	for child in children_to_remove:
		quest_list.remove_child(child)
		child.queue_free()
	
	# Clear viewport tracking
	object_viewports.clear()
	
	# Get daily quests
	var quests: Array = quest_manager.get_daily_quests()
	if quests.is_empty():
		push_warning("QuestPanelHelper: No quests returned from quest_manager")
		return
	
	for quest in quests:
		var card: QuestCard = QUEST_CARD_SCENE.instantiate()
		quest_list.add_child(card)
		
		var progress: int = quest_manager.get_display_progress(quest)
		var is_active: bool = quest_manager.is_quest_active(quest.id)
		var is_completed: bool = quest_manager.is_quest_completed(quest.id)
		
		card.setup(quest, progress, is_active, is_completed)
		card.activate_pressed.connect(_on_quest_activate_pressed)
		
		# Track viewport container for rotation
		var vc: SubViewportContainer = card.get_viewport_container()
		if vc:
			object_viewports.append(vc)


func _on_quest_activate_pressed(quest_id: String) -> void:
	if quest_manager:
		quest_manager.activate_quest(quest_id)
		_populate_quest_cards()  # Refresh UI


func _on_quest_progress_updated(_quest_id: String, _current: int, _target: int) -> void:
	_populate_quest_cards()


func _on_quest_completed(_quest_id: String) -> void:
	_populate_quest_cards()


func _on_quests_refreshed() -> void:
	_populate_quest_cards()

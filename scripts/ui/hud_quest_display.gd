extends VBoxContainer
## HudQuestDisplay - Compact quest progress indicator for in-game HUD
## Shows below buff indicators on left side of screen

const COLOR_BG := Color(0.06, 0.08, 0.12, 0.85)
const COLOR_BORDER := Color(0.25, 0.65, 0.96, 0.6)
const COLOR_TEXT := Color(1, 1, 1, 1)
const COLOR_TEXT_MUTED := Color(0.7, 0.75, 0.85, 1)
const COLOR_PROGRESS := Color(0.25, 0.65, 0.96, 1)
const COLOR_COMPLETED := Color(0.30, 0.85, 0.55, 1)

var quest_manager: Node
var _current_quest_id: String = ""
var _is_visible := false

# UI elements
var _panel: PanelContainer
var _description_label: Label
var _progress_bar: ProgressBar
var _progress_label: Label


func _ready() -> void:
	visible = false
	_build_ui()
	call_deferred("_connect_signals")


func _build_ui() -> void:
	# Create panel container
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(200, 0)
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG
	style.border_color = COLOR_BORDER
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)
	
	# Content VBox
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	_panel.add_child(content)
	
	# Quest description label
	_description_label = Label.new()
	_description_label.add_theme_color_override("font_color", COLOR_TEXT)
	_description_label.add_theme_font_size_override("font_size", 20)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_description_label.custom_minimum_size.x = 180
	content.add_child(_description_label)
	
	# Progress container
	var progress_hbox := HBoxContainer.new()
	progress_hbox.add_theme_constant_override("separation", 8)
	content.add_child(progress_hbox)
	
	# Progress bar
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(120, 16)
	_progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_bar.show_percentage = false
	
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.1, 0.12, 0.18, 1)
	bar_bg.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)
	
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = COLOR_PROGRESS
	bar_fill.set_corner_radius_all(4)
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	
	progress_hbox.add_child(_progress_bar)
	
	# Progress label
	_progress_label = Label.new()
	_progress_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	_progress_label.add_theme_font_size_override("font_size", 16)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_progress_label.custom_minimum_size.x = 60
	progress_hbox.add_child(_progress_label)
	
	add_child(_panel)


func _connect_signals() -> void:
	quest_manager = get_node_or_null("/root/QuestManager")
	
	if quest_manager:
		if not quest_manager.quest_progress_updated.is_connected(_on_quest_progress_updated):
			quest_manager.quest_progress_updated.connect(_on_quest_progress_updated)
		if not quest_manager.quest_completed.is_connected(_on_quest_completed):
			quest_manager.quest_completed.connect(_on_quest_completed)
		if not quest_manager.active_quest_changed.is_connected(_on_active_quest_changed):
			quest_manager.active_quest_changed.connect(_on_active_quest_changed)
		
		# Initial state
		_update_display()


func _on_active_quest_changed(quest: RefCounted) -> void:
	_update_display()


func _on_quest_progress_updated(quest_id: String, current: int, target: int) -> void:
	if quest_id == _current_quest_id:
		_update_progress(current, target)


func _on_quest_completed(quest_id: String) -> void:
	if quest_id == _current_quest_id:
		_show_completed()


func _update_display() -> void:
	if not quest_manager:
		visible = false
		return
	
	var quest := quest_manager.get_active_quest()
	
	if not quest:
		_current_quest_id = ""
		_animate_out()
		return
	
	_current_quest_id = quest.id
	
	# Check if already completed
	if quest_manager.is_quest_completed(quest.id):
		_show_completed()
		return
	
	# Update description
	_description_label.text = quest.short_description
	
	# Update progress
	var progress := quest_manager.get_display_progress(quest)
	_update_progress(progress, quest.target_value)
	
	# Reset completion styling
	var bar_fill := _progress_bar.get_theme_stylebox("fill").duplicate()
	bar_fill.bg_color = COLOR_PROGRESS
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	
	_animate_in()


func _update_progress(current: int, target: int) -> void:
	_progress_bar.max_value = target
	_progress_bar.value = mini(current, target)
	_progress_label.text = "%s/%s" % [_format_number(current), _format_number(target)]


func _show_completed() -> void:
	_description_label.text = "Quest Complete!"
	_progress_bar.value = _progress_bar.max_value
	_progress_label.text = "Done!"
	
	# Green styling for completed
	var bar_fill := _progress_bar.get_theme_stylebox("fill").duplicate()
	bar_fill.bg_color = COLOR_COMPLETED
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	_progress_label.add_theme_color_override("font_color", COLOR_COMPLETED)


func _animate_in() -> void:
	if _is_visible:
		return
	
	_is_visible = true
	visible = true
	modulate.a = 0
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 1.0, 0.3)


func _animate_out() -> void:
	if not _is_visible:
		return
	
	_is_visible = false
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): visible = false)


func _format_number(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fk" % (value / 1000.0)
	return str(value)

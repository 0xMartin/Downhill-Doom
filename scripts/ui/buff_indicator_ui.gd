extends VBoxContainer
## BuffIndicatorUI - Vertical side panel showing active buffs with circular progress
## Each buff displays as a pie chart showing remaining time

const ICON_SIZE: int = 140
const ICON_SPACING: int = 16

# Map effect types to their display info
const BUFF_DISPLAY: Dictionary = {
	3: {"name": "Speed", "color": Color(0.3, 0.7, 1.0), "icon": "⚡"},  # SPEED_BOOST
	4: {"name": "2x Coins", "color": Color(1.0, 0.84, 0.0), "icon": "💰"},  # DOUBLE_COINS
	5: {"name": "3x Coins", "color": Color(1.0, 0.6, 0.0), "icon": "💎"},  # TRIPLE_COINS
	6: {"name": "Shield", "color": Color(0.3, 0.5, 1.0), "icon": "🛡"},  # SHIELD
	7: {"name": "Slow-Mo", "color": Color(0.8, 0.3, 1.0), "icon": "⏱"},  # SLOW_MOTION
	9: {"name": "Time Stop", "color": Color(0.5, 0.8, 1.0), "icon": "❄"},  # TIME_STOP
}

var _buff_icons: Dictionary = {}  # EffectType -> BuffIcon control
var _buff_durations: Dictionary = {}  # EffectType -> total duration

func _ready() -> void:
	call_deferred("_connect_signals")
	add_theme_constant_override("separation", ICON_SPACING)
	self.visible = false

func _process(_delta: float) -> void:
	_update_buff_progress()

func _connect_signals() -> void:
	var item_manager := get_node_or_null("/root/ItemManager")
	if item_manager:
		item_manager.buff_started.connect(_on_buff_started)
		item_manager.buff_ended.connect(_on_buff_ended)
		item_manager.shield_hit.connect(_on_shield_hit)

func _on_buff_started(buff_type: int, duration: float) -> void:
	_buff_durations[buff_type] = duration
	
	if _buff_icons.has(buff_type):
		# Refresh - just update the stored duration
		return
	
	_create_buff_icon(buff_type, duration)
	self.visible = true

func _on_buff_ended(buff_type: int) -> void:
	if _buff_icons.has(buff_type):
		var icon: Control = _buff_icons[buff_type]
		_play_remove_animation(icon)
		_buff_icons.erase(buff_type)
		_buff_durations.erase(buff_type)
	
	if _buff_icons.is_empty():
		self.visible = false

func _on_shield_hit(remaining: int) -> void:
	if _buff_icons.has(6):
		var icon: Control = _buff_icons[6]
		var count_label: Label = icon.get_node_or_null("CountLabel")
		if count_label:
			count_label.text = str(remaining)
		
		# Flash effect
		var tween := create_tween()
		tween.tween_property(icon, "modulate", Color(2, 2, 2, 1), 0.1)
		tween.tween_property(icon, "modulate", Color.WHITE, 0.2)

func _create_buff_icon(buff_type: int, duration: float) -> void:
	var buff_info: Dictionary = BUFF_DISPLAY.get(buff_type, {"name": "Buff", "color": Color.WHITE, "icon": "?"})
	
	# Main container for this buff
	var container := HBoxContainer.new()
	container.add_theme_constant_override("separation", 12)
	
	# Circular progress indicator
	var circle := BuffCircle.new()
	circle.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	circle.buff_color = buff_info.color
	circle.progress = 1.0
	circle.buff_type = buff_type
	container.add_child(circle)
	
	# Info panel (name + timer)
	var info_panel := VBoxContainer.new()
	info_panel.add_theme_constant_override("separation", 2)
	
	# Buff name
	var name_label := Label.new()
	name_label.text = buff_info.name
	name_label.add_theme_font_size_override("font_size", 36)
	name_label.add_theme_color_override("font_color", buff_info.color)
	name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	name_label.add_theme_constant_override("outline_size", 6)
	info_panel.add_child(name_label)
	
	# Timer label
	var timer_label := Label.new()
	timer_label.name = "TimerLabel"
	timer_label.text = "%.1fs" % duration
	timer_label.add_theme_font_size_override("font_size", 44)
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	timer_label.add_theme_constant_override("outline_size", 6)
	info_panel.add_child(timer_label)
	
	# Shield charge counter (special case)
	if buff_type == 6:
		var count_label := Label.new()
		count_label.name = "CountLabel"
		var item_manager := get_node_or_null("/root/ItemManager")
		if item_manager:
			count_label.text = str(item_manager.shield_charges)
		count_label.add_theme_font_size_override("font_size", 32)
		count_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		count_label.add_theme_color_override("font_outline_color", Color.BLACK)
		count_label.add_theme_constant_override("outline_size", 4)
		info_panel.add_child(count_label)
	
	container.add_child(info_panel)
	add_child(container)
	_buff_icons[buff_type] = container
	
	# Pop-in animation
	container.scale = Vector2.ZERO
	container.pivot_offset = Vector2(ICON_SIZE / 2.0, ICON_SIZE / 2.0)
	var tween := create_tween()
	tween.tween_property(container, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _update_buff_progress() -> void:
	var item_manager := get_node_or_null("/root/ItemManager")
	if not item_manager:
		return
	
	for buff_type in _buff_icons:
		var container: Control = _buff_icons[buff_type]
		var circle: BuffCircle = container.get_child(0) as BuffCircle
		var info_panel: VBoxContainer = container.get_child(1) as VBoxContainer
		var timer_label: Label = info_panel.get_node_or_null("TimerLabel")
		
		var remaining: float = item_manager.get_buff_remaining_time(buff_type)
		var total: float = _buff_durations.get(buff_type, 1.0)
		
		if circle:
			circle.progress = clampf(remaining / total, 0.0, 1.0)
			circle.queue_redraw()
		
		if timer_label:
			if remaining > 0:
				timer_label.text = "%.1fs" % remaining
			else:
				timer_label.text = "0.0s"

func _play_remove_animation(container: Control) -> void:
	var tween := create_tween()
	tween.tween_property(container, "scale", Vector2.ZERO, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_property(container, "modulate:a", 0.0, 0.1)
	tween.tween_callback(container.queue_free)

func reset() -> void:
	for icon in _buff_icons.values():
		icon.queue_free()
	_buff_icons.clear()
	_buff_durations.clear()
	self.visible = false


## Custom Control for drawing circular progress (pie chart)
class BuffCircle extends Control:
	var buff_color: Color = Color.WHITE
	var progress: float = 1.0  # 0.0 to 1.0
	var buff_type: int = 0
	
	const BG_COLOR := Color(0.1, 0.1, 0.15, 0.85)
	const BORDER_WIDTH := 3.0
	
	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - BORDER_WIDTH
		
		# Background circle
		draw_circle(center, radius + BORDER_WIDTH, BG_COLOR)
		
		# Progress arc (pie)
		if progress > 0.001:
			var points := PackedVector2Array()
			points.append(center)
			
			var start_angle := -PI / 2.0  # Start from top
			var end_angle := start_angle + (progress * TAU)
			var segments := int(32 * progress) + 4
			
			for i in range(segments + 1):
				var angle := start_angle + (float(i) / segments) * (end_angle - start_angle)
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			
			if points.size() >= 3:
				draw_colored_polygon(points, buff_color)
		
		# Border ring
		var border_color := buff_color
		border_color.a = 0.9
		draw_arc(center, radius, 0, TAU, 32, border_color, BORDER_WIDTH, true)
		
		# Inner dark circle for contrast
		draw_circle(center, radius * 0.35, BG_COLOR)

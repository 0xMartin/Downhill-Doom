extends HBoxContainer
## BuffIndicatorUI - Displays active buff icons with countdown timers
## Shows above the inventory panel

const MAX_BUFF_ICONS: int = 4
const ICON_SIZE: int = 48

# Map effect types to their display names and icon paths (or placeholder colors)
const BUFF_DISPLAY: Dictionary = {
	# ItemConfig.EffectType values
	3: {"name": "Speed", "color": Color(0.3, 0.7, 1.0)},  # SPEED_BOOST
	4: {"name": "2x Coins", "color": Color(1.0, 0.84, 0.0)},  # DOUBLE_COINS
	5: {"name": "3x Coins", "color": Color(1.0, 0.84, 0.0)},  # TRIPLE_COINS
	6: {"name": "Shield", "color": Color(0.3, 0.5, 1.0)},  # SHIELD
	7: {"name": "Slow-Mo", "color": Color(0.8, 0.3, 1.0)},  # SLOW_MOTION
	9: {"name": "Time Stop", "color": Color(0.5, 0.8, 1.0)},  # TIME_STOP
}

var _buff_icons: Dictionary = {}  # EffectType -> Control

func _ready() -> void:
	# Defer signal connection to ensure autoloads are ready
	call_deferred("_connect_signals")
	self.visible = false  # Hidden until buffs active

func _process(_delta: float) -> void:
	_update_buff_timers()

func _connect_signals() -> void:
	var item_manager := get_node_or_null("/root/ItemManager")
	if item_manager:
		print("[BuffIndicator] Connected to ItemManager")
		item_manager.buff_started.connect(_on_buff_started)
		item_manager.buff_ended.connect(_on_buff_ended)
		item_manager.shield_hit.connect(_on_shield_hit)
	else:
		push_error("[BuffIndicator] ItemManager not found!")

func _on_buff_started(buff_type: int, duration: float) -> void:
	print("[BuffIndicator] buff_started: type=", buff_type, " duration=", duration)
	if _buff_icons.has(buff_type):
		# Refresh existing buff - update timer display
		print("[BuffIndicator] Buff already exists, refreshing")
		return
	
	print("[BuffIndicator] Creating icon for buff type: ", buff_type)
	_create_buff_icon(buff_type, duration)
	self.visible = true
	print("[BuffIndicator] Icon created, visible=", self.visible, " size=", self.size, " position=", self.position)

func _on_buff_ended(buff_type: int) -> void:
	if _buff_icons.has(buff_type):
		var icon: Control = _buff_icons[buff_type]
		_play_remove_animation(icon)
		_buff_icons.erase(buff_type)
	
	if _buff_icons.is_empty():
		self.visible = false

func _on_shield_hit(remaining: int) -> void:
	# Update shield icon if active (type 6 = SHIELD)
	if _buff_icons.has(6):
		var icon: Control = _buff_icons[6]
		var label: Label = icon.get_node_or_null("Count")
		if label:
			label.text = str(remaining)
		
		# Flash effect
		var tween := create_tween()
		tween.tween_property(icon, "modulate", Color(2, 2, 2, 1), 0.1)
		tween.tween_property(icon, "modulate", Color.WHITE, 0.2)

func _create_buff_icon(buff_type: int, _duration: float) -> void:
	var buff_info: Dictionary = BUFF_DISPLAY.get(buff_type, {"name": "Buff", "color": Color.WHITE})
	print("[BuffIndicator] _create_buff_icon: type=", buff_type, " info=", buff_info)
	
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	
	# Background
	var bg := ColorRect.new()
	bg.color = buff_info.color
	bg.color.a = 0.7
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.add_child(bg)
	
	# Timer label
	var timer_label := Label.new()
	timer_label.name = "Timer"
	timer_label.text = ""
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	timer_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	timer_label.add_theme_font_size_override("font_size", 20)
	timer_label.add_theme_color_override("font_color", Color.WHITE)
	timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	timer_label.add_theme_constant_override("outline_size", 4)
	icon.add_child(timer_label)
	
	# Shield charge count (special case)
	if buff_type == 6:  # SHIELD
		var count_label := Label.new()
		count_label.name = "Count"
		var item_manager := get_node_or_null("/root/ItemManager")
		if item_manager:
			count_label.text = str(item_manager.shield_charges)
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		count_label.add_theme_font_size_override("font_size", 28)
		count_label.add_theme_color_override("font_color", Color.WHITE)
		count_label.add_theme_color_override("font_outline_color", Color.BLACK)
		count_label.add_theme_constant_override("outline_size", 4)
		icon.add_child(count_label)
	
	add_child(icon)
	_buff_icons[buff_type] = icon
	
	# Pop-in animation
	icon.scale = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(icon, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _update_buff_timers() -> void:
	var item_manager := get_node_or_null("/root/ItemManager")
	if not item_manager:
		return
	
	for buff_type in _buff_icons:
		var icon: Control = _buff_icons[buff_type]
		var timer_label: Label = icon.get_node_or_null("Timer")
		if not timer_label:
			continue
		
		var remaining: float = item_manager.get_buff_remaining_time(buff_type)
		if remaining > 0:
			timer_label.text = "%.1f" % remaining
		else:
			timer_label.text = ""

func _play_remove_animation(icon: Control) -> void:
	var tween := create_tween()
	tween.tween_property(icon, "scale", Vector2.ZERO, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_callback(icon.queue_free)

func reset() -> void:
	for icon in _buff_icons.values():
		icon.queue_free()
	_buff_icons.clear()
	self.visible = false

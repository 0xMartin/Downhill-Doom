extends VBoxContainer
## BuffIndicatorUI - Vertical side panel showing active buffs with circular progress
## Uses BuffIndicatorItem scene for each buff

const BuffIndicatorItemScene = preload("res://scenes/ui/buff_indicator_item.tscn")

const ICON_SPACING: int = 16

# Map effect types to their display info
const BUFF_DISPLAY: Dictionary = {
	3: {"name": "Speed", "color": Color(0.3, 0.7, 1.0)},  # SPEED_BOOST
	4: {"name": "2x Coins", "color": Color(1.0, 0.84, 0.0)},  # DOUBLE_COINS
	5: {"name": "3x Coins", "color": Color(1.0, 0.6, 0.0)},  # TRIPLE_COINS
	6: {"name": "Shield", "color": Color(0.3, 0.5, 1.0)},  # SHIELD
	7: {"name": "Slow-Mo", "color": Color(0.8, 0.3, 1.0)},  # SLOW_MOTION
	9: {"name": "Time Stop", "color": Color(0.5, 0.8, 1.0)},  # TIME_STOP
}

var _buff_items: Dictionary = {}  # EffectType -> BuffIndicatorItem
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
	
	if _buff_items.has(buff_type):
		# Refresh - update the stored duration
		# For shields, also update the displayed charge count
		if buff_type == 6:  # SHIELD
			var item_manager := get_node_or_null("/root/ItemManager")
			if item_manager:
				var item: BuffIndicatorItem = _buff_items[buff_type]
				item.set_timer_text(str(item_manager.shield_charges))
				item.flash()  # Visual feedback
		return
	
	_create_buff_item(buff_type, duration)
	self.visible = true

func _on_buff_ended(buff_type: int) -> void:
	if _buff_items.has(buff_type):
		var item: BuffIndicatorItem = _buff_items[buff_type]
		item.animate_out()
		_buff_items.erase(buff_type)
		_buff_durations.erase(buff_type)
	
	if _buff_items.is_empty():
		self.visible = false

func _on_shield_hit(remaining: int) -> void:
	if _buff_items.has(6):
		var item: BuffIndicatorItem = _buff_items[6]
		item.set_timer_text(str(remaining))
		item.flash()

func _create_buff_item(buff_type: int, duration: float) -> void:
	var buff_info: Dictionary = BUFF_DISPLAY.get(buff_type, {"name": "Buff", "color": Color.WHITE})
	
	var item: BuffIndicatorItem = BuffIndicatorItemScene.instantiate()
	item.buff_type = buff_type
	
	# Add to scene tree FIRST so _ready() runs and node references are valid
	add_child(item)
	_buff_items[buff_type] = item
	
	# Now set properties (after _ready has run)
	item.buff_color = buff_info.color
	item.set_name_text(buff_info.name)
	
	# Shield shows charge count instead of timer
	if buff_type == 6:
		var item_manager := get_node_or_null("/root/ItemManager")
		if item_manager:
			item.set_timer_text(str(item_manager.shield_charges))
	else:
		item.set_timer_text("%.1fs" % duration)
	
	item.animate_in()

func _update_buff_progress() -> void:
	var item_manager := get_node_or_null("/root/ItemManager")
	if not item_manager:
		return
	
	for buff_type in _buff_items:
		var item: BuffIndicatorItem = _buff_items[buff_type]
		
		var remaining: float = item_manager.get_buff_remaining_time(buff_type)
		var total: float = _buff_durations.get(buff_type, 1.0)
		
		item.progress = remaining / total
		
		# Shield doesn't update timer text (it's updated on hit)
		if buff_type != 6:
			if remaining > 0:
				item.set_timer_text("%.1fs" % remaining)
			else:
				item.set_timer_text("0.0s")

func reset() -> void:
	for item in _buff_items.values():
		item.queue_free()
	_buff_items.clear()
	_buff_durations.clear()
	self.visible = false

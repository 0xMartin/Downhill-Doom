extends Node
## ItemManager - Singleton for managing item effects and active buffs
## Handles applying item effects and tracking timed buffs

signal item_used(item_id: String, item_name: String)
signal buff_started(buff_type: int, duration: float)
signal buff_ended(buff_type: int)
signal shield_hit(remaining_charges: int)
signal coin_multiplier_changed(multiplier: float)
signal speed_multiplier_changed(multiplier: float)

# Active buffs tracking
var _active_buffs: Dictionary = {}  # {EffectType: {timer: float, value: float}}

# Shield system
var shield_charges: int = 0

# Multipliers (for UI display)
var coin_multiplier: float = 1.0
var speed_multiplier: float = 1.0

# Time manipulation
var time_scale_override: float = 1.0
var _original_time_scale: float = 1.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	_update_buffs(delta)

func _update_buffs(delta: float) -> void:
	var buffs_to_remove: Array[int] = []
	
	for effect_type in _active_buffs:
		var buff: Dictionary = _active_buffs[effect_type]
		buff.timer -= delta
		
		if buff.timer <= 0:
			buffs_to_remove.append(effect_type)
	
	for effect_type in buffs_to_remove:
		_end_buff(effect_type)

func _end_buff(effect_type: int) -> void:
	if not _active_buffs.has(effect_type):
		return
	
	_active_buffs.erase(effect_type)
	
	match effect_type:
		ItemConfig.EffectType.SPEED_BOOST:
			speed_multiplier = 1.0
			speed_multiplier_changed.emit(speed_multiplier)
		ItemConfig.EffectType.DOUBLE_COINS, ItemConfig.EffectType.TRIPLE_COINS:
			coin_multiplier = 1.0
			coin_multiplier_changed.emit(coin_multiplier)
		ItemConfig.EffectType.SLOW_MOTION, ItemConfig.EffectType.TIME_STOP:
			Engine.time_scale = _original_time_scale
			time_scale_override = 1.0
	
	buff_ended.emit(effect_type)

## Use an item by its ID
func use_item(item_id: String) -> bool:
	print("[ItemManager] use_item called with: ", item_id)
	var item: ItemConfig.ItemData = ItemConfig.get_item(item_id)
	if item == null:
		push_warning("ItemManager: Unknown item ID: " + item_id)
		return false
	
	print("[ItemManager] Found item: ", item.display_name, " effect_type: ", item.effect_type)
	var success := _apply_effect(item)
	print("[ItemManager] Effect applied: ", success)
	if success:
		item_used.emit(item.id, item.display_name)
	
	return success

## Apply item effect based on type
func _apply_effect(item: ItemConfig.ItemData) -> bool:
	match item.effect_type:
		ItemConfig.EffectType.HEAL:
			return _apply_heal(item.effect_value)
		ItemConfig.EffectType.INSTANT_SUPERCHARGE:
			return _apply_instant_supercharge(item.effect_value)
		ItemConfig.EffectType.SUPER_SUPERCHARGE:
			return _apply_super_supercharge(item.effect_value)
		ItemConfig.EffectType.SPEED_BOOST:
			return _apply_speed_boost(item.effect_value, item.effect_duration)
		ItemConfig.EffectType.DOUBLE_COINS, ItemConfig.EffectType.TRIPLE_COINS:
			return _apply_coin_multiplier(item.effect_value, item.effect_duration)
		ItemConfig.EffectType.SHIELD:
			return _apply_shield(int(item.effect_value))
		ItemConfig.EffectType.SLOW_MOTION:
			return _apply_slow_motion(item.effect_value, item.effect_duration)
		ItemConfig.EffectType.EXPLOSION:
			return _apply_explosion(item.effect_value)
		ItemConfig.EffectType.TIME_STOP:
			return _apply_time_stop(item.effect_duration)
	
	return false

# ========== EFFECT IMPLEMENTATIONS ==========

func _apply_heal(percent: float) -> bool:
	var gm := _get_game_manager()
	if gm == null:
		return false
	
	var heal_amount := int(gm.max_health * percent)
	gm.health = mini(gm.health + heal_amount, gm.max_health)
	gm.health_changed.emit(gm.health, gm.max_health)
	
	# Play heal sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx("heal")
	
	return true

func _apply_instant_supercharge(duration: float) -> bool:
	var gm := _get_game_manager()
	if gm == null:
		return false
	
	# Force activate supercharge with standard duration
	gm.is_supercharged = true
	gm.supercharge = gm.max_supercharge
	gm.supercharge_timer = duration
	gm.supercharge_changed.emit(gm.supercharge, gm.max_supercharge)
	gm.supercharge_activated.emit()
	
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_supercharge_sound"):
		audio.play_supercharge_sound()
	
	return true

func _apply_super_supercharge(duration: float) -> bool:
	var gm := _get_game_manager()
	if gm == null:
		return false
	
	# Force activate with extended duration
	gm.is_supercharged = true
	gm.supercharge = gm.max_supercharge
	gm.supercharge_timer = duration
	gm.supercharge_duration = duration  # Temporarily override duration for gradual drain
	gm.supercharge_changed.emit(gm.supercharge, gm.max_supercharge)
	gm.supercharge_activated.emit()
	
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_supercharge_sound"):
		audio.play_supercharge_sound()
	
	return true

func _apply_speed_boost(multiplier: float, duration: float) -> bool:
	print("[ItemManager] _apply_speed_boost: mult=", multiplier, " dur=", duration)
	# Refresh timer if already active, don't stack multipliers
	_active_buffs[ItemConfig.EffectType.SPEED_BOOST] = {
		"timer": duration,
		"value": multiplier
	}
	
	speed_multiplier = multiplier
	print("[ItemManager] speed_multiplier set to: ", speed_multiplier)
	speed_multiplier_changed.emit(speed_multiplier)
	buff_started.emit(ItemConfig.EffectType.SPEED_BOOST, duration)
	
	return true

func _apply_coin_multiplier(multiplier: float, duration: float) -> bool:
	# Use DOUBLE_COINS as the key for both double and triple
	var effect_type := ItemConfig.EffectType.DOUBLE_COINS
	
	# Refresh timer, don't stack (use higher multiplier if active)
	var current_mult: float = 1.0
	if _active_buffs.has(effect_type):
		current_mult = _active_buffs[effect_type].value
	
	_active_buffs[effect_type] = {
		"timer": duration,
		"value": maxf(multiplier, current_mult)
	}
	
	coin_multiplier = _active_buffs[effect_type].value
	coin_multiplier_changed.emit(coin_multiplier)
	buff_started.emit(effect_type, duration)
	
	return true

func _apply_shield(charges: int) -> bool:
	# Add charges (shields stack)
	shield_charges += charges
	
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx("shield_activate")
	
	return true

func _apply_slow_motion(time_scale: float, duration: float) -> bool:
	_original_time_scale = Engine.time_scale
	Engine.time_scale = time_scale
	time_scale_override = time_scale
	
	_active_buffs[ItemConfig.EffectType.SLOW_MOTION] = {
		"timer": duration * time_scale,  # Adjust for slowed time
		"value": time_scale
	}
	
	buff_started.emit(ItemConfig.EffectType.SLOW_MOTION, duration)
	
	return true

func _apply_explosion(radius: float) -> bool:
	var gm := _get_game_manager()
	if gm == null or gm.player == null:
		return false
	
	var player_pos: Vector3 = gm.player.global_position
	
	# Find all destructible objects in radius
	var space_state: PhysicsDirectSpaceState3D = gm.player.get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, player_pos)
	query.collision_mask = 0xFFFFFFFF  # All layers
	
	var results := space_state.intersect_shape(query, 64)
	
	for result in results:
		var collider: Node = result.collider
		if collider.has_method("destroy"):
			collider.destroy()
		elif collider.has_method("take_damage"):
			collider.take_damage(9999)
	
	# Visual explosion effect
	_spawn_explosion_effect(player_pos, radius)
	
	# Sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx("explosion")
	
	return true

func _apply_time_stop(duration: float) -> bool:
	_original_time_scale = Engine.time_scale
	Engine.time_scale = 0.0001  # Near-zero but not completely stopped
	time_scale_override = 0.0001
	
	_active_buffs[ItemConfig.EffectType.TIME_STOP] = {
		"timer": duration * 0.0001,  # Real-time duration
		"value": 0.0001
	}
	
	buff_started.emit(ItemConfig.EffectType.TIME_STOP, duration)
	
	return true

func _spawn_explosion_effect(position: Vector3, radius: float) -> void:
	# TODO: Add particle effect for explosion
	pass

# ========== SHIELD SYSTEM ==========

## Called by GameManager when player would take damage
## Returns true if damage was blocked
func try_block_damage() -> bool:
	if shield_charges <= 0:
		return false
	
	shield_charges -= 1
	shield_hit.emit(shield_charges)
	
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx("shield_hit")
	
	return true

# ========== BUFF QUERIES ==========

func has_buff(effect_type: int) -> bool:
	return _active_buffs.has(effect_type)

func get_buff_remaining_time(effect_type: int) -> float:
	if _active_buffs.has(effect_type):
		return _active_buffs[effect_type].timer
	return 0.0

func get_active_buffs() -> Dictionary:
	return _active_buffs.duplicate()

func has_shield() -> bool:
	return shield_charges > 0

func get_shield_charges() -> int:
	return shield_charges

# ========== RESET ==========

func reset() -> void:
	"""Reset all buffs and effects - called on game restart"""
	# End all timed buffs
	for effect_type in _active_buffs.keys():
		_end_buff(effect_type)
	_active_buffs.clear()
	
	# Reset shield
	shield_charges = 0
	
	# Reset multipliers
	coin_multiplier = 1.0
	speed_multiplier = 1.0
	
	# Reset time scale
	Engine.time_scale = 1.0
	time_scale_override = 1.0
	_original_time_scale = 1.0

# ========== HELPERS ==========

func _get_game_manager() -> Node:
	return get_node_or_null("/root/GameManager")

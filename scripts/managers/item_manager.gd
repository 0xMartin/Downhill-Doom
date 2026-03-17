extends Node
## ItemManager - Singleton for managing item effects and active buffs
## Handles applying item effects and tracking timed buffs

signal item_used(item_id: String, item_name: String)
signal buff_started(buff_type: int, duration: float)
signal buff_ended(buff_type: int)
signal shield_activated(charges: int)
signal shield_hit(remaining_charges: int)
signal shield_depleted
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
	# Use unscaled delta for time manipulation effects
	var real_delta := delta / Engine.time_scale if Engine.time_scale > 0.001 else delta
	_update_buffs(real_delta)

func _update_buffs(real_delta: float) -> void:
	var buffs_to_remove: Array[int] = []
	
	for effect_type in _active_buffs:
		var buff: Dictionary = _active_buffs[effect_type]
		
		# Special handling for TIME_STOP with phases
		if effect_type == ItemConfig.EffectType.TIME_STOP and buff.has("phase"):
			_update_time_stop(buff, real_delta)
			if buff.phase == "done":
				buffs_to_remove.append(effect_type)
			continue
		
		# Normal buff timer (use scaled delta for non-time effects)
		var effective_delta := real_delta
		if effect_type == ItemConfig.EffectType.SLOW_MOTION:
			effective_delta = real_delta  # Use real time for slow motion too
		
		buff.timer -= effective_delta
		
		if buff.timer <= 0:
			buffs_to_remove.append(effect_type)
	
	for effect_type in buffs_to_remove:
		_end_buff(effect_type)

func _update_time_stop(buff: Dictionary, real_delta: float) -> void:
	const TRANSITION_TIME := 0.5  # Time to slow down / speed up
	const MIN_TIME_SCALE := 0.1  # Minimum time scale (not fully stopped)
	
	match buff.phase:
		"slowing":
			buff.phase_timer -= real_delta
			var progress: float = 1.0 - (float(buff.phase_timer) / TRANSITION_TIME)
			progress = clampf(progress, 0.0, 1.0)
			# Ease out for smooth deceleration
			var eased: float = 1.0 - pow(1.0 - progress, 2.0)
			Engine.time_scale = lerpf(_original_time_scale, MIN_TIME_SCALE, eased)
			time_scale_override = Engine.time_scale
			
			if buff.phase_timer <= 0:
				buff.phase = "stopped"
				buff.phase_timer = buff.timer - TRANSITION_TIME  # Remaining stopped time
				Engine.time_scale = MIN_TIME_SCALE
				time_scale_override = MIN_TIME_SCALE
		
		"stopped":
			buff.phase_timer -= real_delta
			if buff.phase_timer <= 0:
				buff.phase = "speeding"
				buff.phase_timer = TRANSITION_TIME
		
		"speeding":
			buff.phase_timer -= real_delta
			var progress: float = 1.0 - (float(buff.phase_timer) / TRANSITION_TIME)
			progress = clampf(progress, 0.0, 1.0)
			# Ease in for smooth acceleration
			var eased: float = pow(progress, 2.0)
			Engine.time_scale = lerpf(MIN_TIME_SCALE, _original_time_scale, eased)
			time_scale_override = Engine.time_scale
			
			if buff.phase_timer <= 0:
				buff.phase = "done"
				Engine.time_scale = _original_time_scale
				time_scale_override = 1.0

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
	var item: ItemConfig.ItemData = ItemConfig.get_item(item_id)
	if item == null:
		push_warning("ItemManager: Unknown item ID: " + item_id)
		return false
	
	var success := _apply_effect(item)
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
			return _apply_coin_multiplier(item.effect_type, item.effect_value, item.effect_duration)
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
	var actual_heal := mini(heal_amount, gm.max_health - gm.health)  # Cap at missing health
	gm.health = mini(gm.health + heal_amount, gm.max_health)
	gm.health_changed.emit(gm.health, gm.max_health)
	
	# Emit heal event for visual feedback (only if actually healed)
	if actual_heal > 0:
		gm.player_healed.emit(actual_heal)
	
	# Play heal sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx("heal")
	
	return true

func _apply_instant_supercharge(duration_multiplier: float) -> bool:
	var gm := _get_game_manager()
	if gm == null:
		return false
	
	# Force activate supercharge with normal duration (affected by boosts)
	var actual_duration: float = gm.supercharge_duration * duration_multiplier
	gm.is_supercharged = true
	gm.supercharge_timer = actual_duration
	gm.supercharge_activated.emit()
	
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_supercharge_sound"):
		audio.play_supercharge_sound()
	
	return true

func _apply_super_supercharge(duration_multiplier: float) -> bool:
	var gm := _get_game_manager()
	if gm == null:
		return false
	
	# Force activate with extended duration (affected by boosts, then multiplied)
	var actual_duration: float = gm.supercharge_duration * duration_multiplier
	gm.is_supercharged = true
	gm.supercharge_timer = actual_duration
	gm.supercharge_activated.emit()
	
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_supercharge_sound"):
		audio.play_supercharge_sound()
	
	return true

func _apply_speed_boost(multiplier: float, duration: float) -> bool:
	# Refresh timer if already active, don't stack multipliers
	_active_buffs[ItemConfig.EffectType.SPEED_BOOST] = {
		"timer": duration,
		"value": multiplier
	}
	
	speed_multiplier = multiplier
	speed_multiplier_changed.emit(speed_multiplier)
	buff_started.emit(ItemConfig.EffectType.SPEED_BOOST, duration)
	
	return true

func _apply_coin_multiplier(effect_type: int, multiplier: float, duration: float) -> bool:
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
	
	# Emit signal for visual
	shield_activated.emit(shield_charges)
	
	# Also emit as buff for indicator
	buff_started.emit(ItemConfig.EffectType.SHIELD, 0.0)  # 0 duration = until used
	
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_shock_wave_sound"):
		audio.play_shock_wave_sound()
	
	return true

func _apply_slow_motion(time_scale: float, duration: float) -> bool:
	_original_time_scale = Engine.time_scale
	Engine.time_scale = time_scale
	time_scale_override = time_scale
	
	_active_buffs[ItemConfig.EffectType.SLOW_MOTION] = {
		"timer": duration,  # Real seconds (using real_delta in _update_buffs)
		"value": time_scale
	}
	
	buff_started.emit(ItemConfig.EffectType.SLOW_MOTION, duration)
	
	return true

func _apply_explosion(radius: float) -> bool:
	var gm := _get_game_manager()
	if gm == null or gm.player == null:
		return false
	
	var player_pos: Vector3 = gm.player.global_position
	var scene_root: Node = gm.player.get_tree().current_scene
	var destroyed_count := 0
	
	# Destroy trees in radius
	for tree in gm.player.get_tree().get_nodes_in_group("trees"):
		if _is_in_radius(tree, player_pos, radius):
			if tree.has_method("fall"):
				var dir: Vector3 = ((tree as Node3D).global_position - player_pos).normalized()
				dir.y = 0
				if dir.length() < 0.1:
					dir = Vector3(0, 0, -1)
				tree.fall(dir * 15.0)
				destroyed_count += 1
	
	# Destroy friend NPCs
	for npc in gm.player.get_tree().get_nodes_in_group("friend_npcs"):
		if _is_in_radius(npc, player_pos, radius):
			if npc.has_method("die"):
				npc.die(null)
				destroyed_count += 1
	
	# Destroy enemy NPCs
	for enemy_npc in gm.player.get_tree().get_nodes_in_group("enemy_npcs"):
		if _is_in_radius(enemy_npc, player_pos, radius):
			if enemy_npc.has_method("die"):
				enemy_npc.die(null)
				destroyed_count += 1
	
	# Destroy buildings (including large buildings for explosion)
	for building in gm.player.get_tree().get_nodes_in_group("buildings"):
		if _is_in_radius(building, player_pos, radius):
			if building.has_method("destroy"):
				building.destroy(Vector3.ZERO)
				destroyed_count += 1
	
	# Destroy enemy buildings
	for enemy in gm.player.get_tree().get_nodes_in_group("building_enemies"):
		if _is_in_radius(enemy, player_pos, radius):
			if enemy.has_method("destroy"):
				enemy.destroy(Vector3.ZERO)
				destroyed_count += 1
			elif enemy.has_method("die"):
				enemy.die(null)
				destroyed_count += 1
			else:
				enemy.queue_free()
				destroyed_count += 1
	
	# Visual explosion effect
	_spawn_explosion_effect(player_pos, radius)
	
	# Camera shake
	var camera: Camera3D = gm.player.get_viewport().get_camera_3d()
	if camera and camera.has_method("shake"):
		camera.shake(0.5 + destroyed_count * 0.1)
	
	# Sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_shock_wave_sound"):
		audio.play_shock_wave_sound()
	
	return true

func _is_in_radius(node: Node, center: Vector3, radius: float) -> bool:
	if node is Node3D:
		return (node as Node3D).global_position.distance_to(center) <= radius
	return false

func _apply_time_stop(duration: float) -> bool:
	_original_time_scale = Engine.time_scale
	
	# Store the effect in active buffs (use real-time tracking)
	_active_buffs[ItemConfig.EffectType.TIME_STOP] = {
		"timer": duration,
		"value": 0.1,  # Target time scale
		"phase": "slowing",  # slowing -> stopped -> speeding
		"phase_timer": 0.5  # Time for slow-down transition
	}
	
	buff_started.emit(ItemConfig.EffectType.TIME_STOP, duration)
	
	return true

func _spawn_explosion_effect(position: Vector3, radius: float) -> void:
	var gm := _get_game_manager()
	if gm == null or gm.player == null:
		return
	
	# Create expanding sphere effect
	var explosion := MeshInstance3D.new()
	explosion.name = "ExplosionEffect"
	
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	explosion.mesh = sphere
	
	# Bright orange material
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	explosion.material_override = mat
	explosion.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	explosion.global_position = position
	gm.player.get_tree().current_scene.add_child(explosion)
	
	# Animate expansion and fade
	var tween := explosion.create_tween()
	tween.set_parallel(true)
	tween.tween_property(explosion, "scale", Vector3.ONE * radius * 2, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4).set_ease(Tween.EASE_IN)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.4)
	tween.chain().tween_callback(explosion.queue_free)

# ========== SHIELD SYSTEM ==========

## Called by GameManager when player would take damage
## Returns true if damage was blocked
func try_block_damage() -> bool:
	if shield_charges <= 0:
		return false
	
	shield_charges -= 1
	shield_hit.emit(shield_charges)
	
	if shield_charges <= 0:
		shield_depleted.emit()
		buff_ended.emit(ItemConfig.EffectType.SHIELD)
	
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

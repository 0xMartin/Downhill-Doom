extends Node
## GameManager - Global singleton for game state, score, and scene management

signal coins_changed(total: int)
signal distance_changed(distance: float)
signal health_changed(health: int, max_health: int)
signal player_hit(damage: int)
signal player_died
signal game_started
signal game_paused(is_paused: bool)
signal object_destroyed(object_id: String, object_name: String, coins: int)
signal supercharge_changed(charge: float, max_charge: float)
signal supercharge_activated
signal supercharge_ended

# Game state
var coins: int = 0
var distance: float = 0.0
var best_distance: float = 0.0
var best_coins: int = 0
var is_playing := false
var is_paused := false

# Health system
var max_health: int = 100
var health: int = 100
var infinite_health: bool = false  # Debug: skip damage

# Supercharge system
var supercharge: float = 0.0
var max_supercharge: float = 100.0
var is_supercharged: bool = false
var supercharge_duration: float = 6.0  # Duration in seconds
var supercharge_timer: float = 0.0

# Player reference
var player: Node3D
var start_position: Vector3

# Stats tracking - objects destroyed this run
var destroyed_objects: Dictionary = {}  # {object_id: count}
var destroyed_objects_details: Array = []  # [{id, name, coins, timestamp}]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(_delta: float) -> void:
	if is_playing and player and not is_paused:
		# Calculate distance traveled (negative Z direction)
		var current_distance := -player.global_position.z
		if current_distance > distance:
			distance = current_distance
			distance_changed.emit(distance)
		
		# Handle supercharge timer and gradual drain
		if is_supercharged:
			supercharge_timer -= _delta
			# Update the bar to show remaining time as a percentage
			var remaining_ratio := supercharge_timer / supercharge_duration
			supercharge = max_supercharge * remaining_ratio
			supercharge_changed.emit(supercharge, max_supercharge)
			
			if supercharge_timer <= 0:
				end_supercharge()

func start_game() -> void:
	coins = 0
	distance = 0.0
	health = max_health
	is_playing = true
	is_paused = false
	
	# Reset supercharge
	supercharge = 0.0
	is_supercharged = false
	supercharge_timer = 0.0
	supercharge_changed.emit(supercharge, max_supercharge)
	
	# Reset stats
	destroyed_objects.clear()
	destroyed_objects_details.clear()
	
	# Reset item system
	var item_manager := get_node_or_null("/root/ItemManager")
	if item_manager:
		item_manager.reset()
	var inventory_manager := get_node_or_null("/root/InventoryManager")
	if inventory_manager:
		inventory_manager.reset()
	
	coins_changed.emit(coins)
	distance_changed.emit(distance)
	health_changed.emit(health, max_health)
	game_started.emit()
	
	# Start game music
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.start_game_music()

func end_game() -> void:
	is_playing = false
	
	# End supercharge if active (stops blinking effect)
	if is_supercharged:
		end_supercharge()
	
	# Stop rolling sound
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.stop_roll_sound()
	
	# Update best scores
	if distance > best_distance:
		best_distance = distance
	if coins > best_coins:
		best_coins = coins
	
	# Record stats for statistics tracking
	var MainMenu = load("res://scripts/main_menu.gd")
	MainMenu.record_game_stats(coins, distance)
	
	player_died.emit()

func add_coin(amount: int = 1) -> void:
	# Apply ItemManager coin multiplier if active
	var item_manager := get_node_or_null("/root/ItemManager")
	var multiplier: float = 1.0
	if item_manager:
		multiplier = item_manager.coin_multiplier
	
	var final_amount := int(amount * multiplier)
	coins += final_amount
	coins_changed.emit(coins)

## Record a destroyed object for statistics
func record_destroyed_object(object_id: String, object_name: String, coin_value: int) -> void:
	# Update count
	if destroyed_objects.has(object_id):
		destroyed_objects[object_id] += 1
	else:
		destroyed_objects[object_id] = 1
	
	# Store details
	destroyed_objects_details.append({
		"id": object_id,
		"name": object_name,
		"coins": coin_value,
		"distance": distance,
		"timestamp": Time.get_ticks_msec(),
	})
	
	# Emit signal for UI updates
	object_destroyed.emit(object_id, object_name, coin_value)
	
	# Add supercharge from destroying objects (10 charge per object)
	add_supercharge(10.0)

## Get count of destroyed objects by ID
func get_destroyed_count(object_id: String) -> int:
	return destroyed_objects.get(object_id, 0)

## Get total destroyed objects count
func get_total_destroyed() -> int:
	var total := 0
	for count in destroyed_objects.values():
		total += count
	return total

## Get destruction stats summary
func get_destruction_stats() -> Dictionary:
	return {
		"total": get_total_destroyed(),
		"by_object": destroyed_objects.duplicate(),
		"details": destroyed_objects_details.duplicate(),
	}

func take_damage(amount: int) -> void:
	if not is_playing or health <= 0:
		return
	
	# Skip damage if infinite health enabled or supercharged
	if infinite_health or is_supercharged:
		return
	
	# Check if ItemManager shield blocks the damage
	var item_manager := get_node_or_null("/root/ItemManager")
	if item_manager and item_manager.try_block_damage():
		# Shield blocked the hit
		Input.vibrate_handheld(75)  # Shorter vibration for blocked hit
		return
	
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	player_hit.emit(amount)
	
	# Vibrate on mobile devices
	Input.vibrate_handheld(150)  # 150ms vibration (longer for better feel)
	
	if health <= 0:
		# Call player's die() method which handles explosion, sound, and delay
		if player and player.has_method("die"):
			player.die()
		else:
			end_game()

func set_player(p: Node3D) -> void:
	player = p
	if player:
		start_position = player.global_position

func pause_game() -> void:
	is_paused = true
	get_tree().paused = true
	game_paused.emit(true)

func resume_game() -> void:
	is_paused = false
	get_tree().paused = false
	game_paused.emit(false)

func restart_game() -> void:
	is_paused = false
	get_tree().paused = false
	
	# Stop rolling sound before restarting
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.stop_roll_sound()
	
	var st = get_node("/root/SceneTransition")
	st.change_scene("res://scenes/game.tscn")

func go_to_menu() -> void:
	is_paused = false
	get_tree().paused = false
	is_playing = false
	
	# Stop rolling sound and switch to menu music
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.stop_roll_sound()
		audio.play_menu_music()
	var st = get_node("/root/SceneTransition")
	st.change_scene("res://scenes/main_menu.tscn")

func get_formatted_distance() -> String:
	if distance >= 1000:
		return "%.1f km" % (distance / 1000.0)
	return "%d m" % int(distance)

# ========== Supercharge System ==========

## Add charge from destroying objects
func add_supercharge(amount: float) -> void:
	if is_supercharged:
		return  # Don't charge while supercharged
	
	supercharge = minf(supercharge + amount, max_supercharge)
	supercharge_changed.emit(supercharge, max_supercharge)

## Activate supercharge if fully charged
func activate_supercharge() -> bool:
	if supercharge < max_supercharge or is_supercharged:
		return false
	
	is_supercharged = true
	supercharge_timer = supercharge_duration
	# Don't set supercharge to 0 immediately - let _process gradually drain it
	supercharge_activated.emit()
	
	# Play sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_supercharge_sound"):
		audio.play_supercharge_sound()
	
	return true

## End supercharge mode
func end_supercharge() -> void:
	if not is_supercharged:
		return
	
	is_supercharged = false
	supercharge_timer = 0.0
	supercharge = 0.0  # Ensure bar is empty when supercharge ends
	supercharge_changed.emit(supercharge, max_supercharge)
	supercharge_ended.emit()

## Check if supercharge is ready to activate
func is_supercharge_ready() -> bool:
	return supercharge >= max_supercharge and not is_supercharged

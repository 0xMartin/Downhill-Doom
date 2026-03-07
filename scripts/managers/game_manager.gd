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
signal time_changed(time: float)
signal supercharge_changed(current: int, required: int)
signal supercharge_activated
signal supercharge_ended

# Game state
var coins: int = 0
var distance: float = 0.0
var game_time: float = 0.0  # Time in seconds
var best_distance: float = 0.0
var best_coins: int = 0
var is_playing := false
var is_paused := false
var coin_multiplier: int = 1  # Distance-based multiplier (1x per 1000m)

# Health system
var max_health: int = 100
var health: int = 100
var infinite_health: bool = false  # Debug: skip damage

# Supercharge system (count-based with escalating requirements)
var supercharge_objects: int = 0  # Objects destroyed since last supercharge
var supercharge_activations: int = 0  # How many times supercharge has been activated
var is_supercharged: bool = false
var supercharge_duration: float = 10.0  # Duration in seconds
var supercharge_timer: float = 0.0
const SUPERCHARGE_BASE_REQUIREMENT: int = 10  # First activation needs 10, then 20, 30...

# Player reference
var player: Node3D
var start_position: Vector3

# Stats tracking - objects destroyed this run
var destroyed_objects: Dictionary = {}  # {object_id: count}
var destroyed_objects_details: Array = []  # [{id, name, coins, timestamp}]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Auto-pause when app goes to background
	get_tree().root.connect("focus_exited", _on_focus_lost)

func _on_focus_lost() -> void:
	if is_playing and not is_paused:
		pause_game()

func _process(_delta: float) -> void:
	if is_playing and player and not is_paused:
		# Update game time
		game_time += _delta
		time_changed.emit(game_time)
		
		# Calculate distance traveled (negative Z direction)
		var current_distance := -player.global_position.z
		if current_distance > distance:
			distance = current_distance
			distance_changed.emit(distance)
		
		# Handle supercharge timer countdown
		if is_supercharged:
			supercharge_timer -= _delta
			# During supercharge, emit smooth values for progress bar
			# Use 1000x scale for smooth animation, HUD will detect active state
			var remaining_ratio := supercharge_timer / supercharge_duration
			var scaled_current := int(remaining_ratio * 1000.0)
			supercharge_changed.emit(scaled_current, 1000)
			
			if supercharge_timer <= 0:
				end_supercharge()

func start_game() -> void:
	coins = 0
	distance = 0.0
	game_time = 0.0
	health = max_health
	is_playing = true
	is_paused = false
	coin_multiplier = 1
	
	# Reset supercharge
	supercharge_objects = 0
	supercharge_activations = 0
	is_supercharged = false
	supercharge_timer = 0.0
	supercharge_changed.emit(supercharge_objects, get_supercharge_requirement())
	
	# Reset stats
	destroyed_objects.clear()
	destroyed_objects_details.clear()
	
	coins_changed.emit(coins)
	distance_changed.emit(distance)
	time_changed.emit(game_time)
	health_changed.emit(health, max_health)
	game_started.emit()
	
	# Start game music
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.start_game_music()

func end_game() -> void:
	is_playing = false
	
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
	var MainMenu = load("res://scripts/ui/main_menu.gd")
	MainMenu.record_game_stats(coins, distance, game_time)
	
	player_died.emit()

func add_coin(amount: int = 1) -> void:
	var multiplied_amount := amount * coin_multiplier
	coins += multiplied_amount
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
	
	# Add supercharge progress from destroying objects
	add_supercharge_object()

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
	
	health = max(0, health - amount)
	health_changed.emit(health, max_health)
	player_hit.emit(amount)
	
	# Vibrate on mobile devices (respects haptic setting)
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.vibrate(150)
	
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
	
	# Clean up planes and bombs that were added to root
	_cleanup_root_objects()
	
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
	
	# Clean up planes and bombs that were added to root
	_cleanup_root_objects()
	
	var st = get_node("/root/SceneTransition")
	st.change_scene("res://scenes/main_menu.tscn")

func get_formatted_distance() -> String:
	if distance >= 1000:
		return "%.1f km" % (distance / 1000.0)
	return "%d m" % int(distance)

func get_formatted_time() -> String:
	var total_seconds := int(game_time)
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var seconds := total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

static func format_time_static(time_seconds: float) -> String:
	var total_seconds := int(time_seconds)
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var seconds := total_seconds % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

# ========== Supercharge System ==========

## Get current supercharge requirement based on activation count
func get_supercharge_requirement() -> int:
	return SUPERCHARGE_BASE_REQUIREMENT * (supercharge_activations + 1)

## Add one object to supercharge counter (called when destroying objects)
func add_supercharge_object() -> void:
	if is_supercharged:
		return  # Don't charge while supercharged
	
	supercharge_objects += 1
	supercharge_changed.emit(supercharge_objects, get_supercharge_requirement())

## Activate supercharge if fully charged
func activate_supercharge() -> bool:
	if supercharge_objects < get_supercharge_requirement() or is_supercharged:
		return false
	
	is_supercharged = true
	supercharge_timer = supercharge_duration
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
	supercharge_activations += 1  # Increment for next requirement
	supercharge_objects = 0  # Reset counter
	supercharge_changed.emit(supercharge_objects, get_supercharge_requirement())
	supercharge_ended.emit()

## Check if supercharge is ready to activate
func is_supercharge_ready() -> bool:
	return supercharge_objects >= get_supercharge_requirement() and not is_supercharged

## Clean up planes and bombs added to root (they don't get cleaned up with scene change)
func _cleanup_root_objects() -> void:
	var root := get_tree().root
	for node in root.get_children():
		if node.is_in_group("planes") or node.is_in_group("bombs"):
			node.queue_free()

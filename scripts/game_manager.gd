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

func start_game() -> void:
	coins = 0
	distance = 0.0
	health = max_health
	is_playing = true
	is_paused = false
	
	# Reset stats
	destroyed_objects.clear()
	destroyed_objects_details.clear()
	
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
	coins += amount
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
	
	# Skip damage if infinite health enabled
	if infinite_health:
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

extends CharacterBody3D
## Friend NPC - wanders around randomly and can be hit by player for coins
## Uses CharacterBody3D for terrain following, model hops separately

@export var coin_value: int = 3
@export var object_id: String = "npc_unknown"
@export var object_name: String = "NPC"

# Movement settings
var wander_radius_min: float = 4.0
var wander_radius_max: float = 8.0
var move_speed: float = 3.0  # Faster movement
var wait_time_min: float = 0.5
var wait_time_max: float = 2.5

# Physics
var gravity: float = 20.0

# Hop animation settings (model only)
var model_height: float = 0.3  # Set by spawner, used for hop calculation
var hop_height: float = 0.1  # Will be recalculated based on model_height
var hop_speed: float = 12.0

# Internal state
var is_dead := false
var spawn_position: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var is_moving := false
var model: Node3D = null
var model_base_y: float = 0.0
var hop_phase: float = 0.0


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("friend_npcs")
	
	spawn_position = global_position
	target_position = global_position
	
	# Calculate hop height as 30% of model height
	hop_height = model_height * 0.3
	
	# Find model child
	model = get_node_or_null("Model")
	if model:
		model_base_y = model.position.y
		# Rotate model 180 degrees - models are exported facing backwards
		model.rotation.y = PI
	
	# Connect detection area
	if get_tree():
		await get_tree().process_frame
	var detect_area := get_node_or_null("DetectArea") as Area3D
	if detect_area:
		detect_area.body_entered.connect(_on_detect_area_body_entered)
	
	# Start wandering behavior
	_start_wander_cycle()


func _process(delta: float) -> void:
	if is_dead:
		return
	
	# Update hop animation when moving (model only)
	if is_moving and model:
		hop_phase += delta * hop_speed
		var hop_offset: float = abs(sin(hop_phase)) * hop_height
		model.position.y = model_base_y + hop_offset
	elif model:
		# Smoothly return to base when stationary
		model.position.y = lerp(model.position.y, model_base_y, delta * 10.0)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	
	# Move towards target
	if is_moving:
		var direction := (target_position - global_position)
		direction.y = 0  # Horizontal only
		var distance := direction.length()
		
		if distance < 0.3:
			# Reached target
			is_moving = false
			velocity.x = 0
			velocity.z = 0
		else:
			# Move towards target
			direction = direction.normalized()
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
			
			# Face movement direction
			var look_target := global_position + direction
			look_at(look_target, Vector3.UP)
			rotation.x = 0
			rotation.z = 0
	else:
		velocity.x = 0
		velocity.z = 0
	
	move_and_slide()


func _start_wander_cycle() -> void:
	if is_dead:
		return
	
	# Wait for random time
	var wait_time := randf_range(wait_time_min, wait_time_max)
	await get_tree().create_timer(wait_time).timeout
	
	if is_dead:
		return
	
	# Pick new random target within radius
	_pick_new_target()
	is_moving = true
	hop_phase = 0.0
	
	# Wait until we reach target (or timeout)
	var timeout := 10.0
	var elapsed := 0.0
	while is_moving and elapsed < timeout and not is_dead:
		var tree := get_tree()
		if tree == null:
			return
		await tree.process_frame
		elapsed += get_process_delta_time()
	
	# Start next cycle
	if not is_dead:
		_start_wander_cycle()


func _pick_new_target() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	# Random direction and distance
	var angle := rng.randf_range(0, TAU)
	var distance := rng.randf_range(wander_radius_min, wander_radius_max)
	
	# Calculate new position relative to spawn (Y handled by physics)
	var offset := Vector3(cos(angle) * distance, 0, sin(angle) * distance)
	target_position = spawn_position + offset


func _on_detect_area_body_entered(body: Node) -> void:
	if is_dead:
		return
	
	if body.is_in_group("player"):
		die(body)


func die(player: Node = null) -> void:
	if is_dead:
		return
	
	is_dead = true
	is_moving = false
	
	# Play death sound based on NPC type
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		# Extract NPC type from object_id (e.g. "npc_chicken" -> "chicken")
		var npc_type := object_id.replace("npc_", "")
		audio.play_npc_death_sound(npc_type)
	
	# Award coins
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
		gm.record_destroyed_object(object_id, object_name, coin_value)
	
	# Fling animation via DestructionManager
	var dm := get_node_or_null("/root/DestructionManager")
	if dm:
		dm.fling_object(self, player, model)
	else:
		queue_free()


## Called by ObjectPool when this object is retrieved from pool
func _pool_reset() -> void:
	# Re-add to groups (removed when pooled)
	add_to_group("npcs")
	add_to_group("friend_npcs")
	# Reset state
	is_dead = false
	is_moving = false
	hop_phase = 0.0

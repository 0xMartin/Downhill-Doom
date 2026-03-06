extends CharacterBody3D
## Enemy NPC - moves toward player when in detection range, damages on contact
## Uses CharacterBody3D for terrain following, model animates separately
## 
## Types (configured via object_id):
## - dark_pawn: 5dmg, 32m range, slow (3.8 speed), 40 coins
## - dark_knight: 10dmg, 48m range, medium (6.0 speed), 80 coins
## - horse_knight: 15dmg, 60m range, fast (9.0 speed), 140 coins

@export var damage: int = 5
@export var coin_value: int = 40
@export var object_id: String = "npc_enemy_unknown"
@export var object_name: String = "Enemy"

# Detection and movement - will be set based on enemy type
var detection_range: float = 32.0  # Range at which enemy starts chasing
var move_speed: float = 3.8  # Movement speed towards player

# Physics
var gravity: float = 20.0

# Hop animation settings (model only)
var model_height: float = 0.8  # Set by spawner
var hop_height: float = 0.15
var hop_speed: float = 14.0

# Internal state
var is_dead := false
var is_chasing := false
var player: Node3D = null
var model: Node3D = null
var model_base_y: float = 0.0
var hop_phase: float = 0.0
var audio_manager: Node


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("enemy_npcs")
	
	audio_manager = get_node_or_null("/root/AudioManager")
	
	# Configure stats based on enemy type
	_configure_enemy_type()
	
	# Calculate hop height based on model height
	hop_height = model_height * 0.2
	
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
	
	# Find player reference
	player = get_tree().get_first_node_in_group("player") as Node3D


func _configure_enemy_type() -> void:
	## Configure stats based on enemy type (object_id)
	## Detection range 4x original, speed +50% total
	match object_id:
		"npc_enemy_pawn", "npc_dark_pawn":
			damage = 5
			detection_range = 32.0  # 4x original
			move_speed = 3.8  # +50% total
			coin_value = 40
		"npc_enemy_knight", "npc_dark_knight":
			damage = 10
			detection_range = 48.0  # 4x original
			move_speed = 6.0  # +50% total
			coin_value = 80
		"npc_enemy_horse", "npc_horse_knight":
			damage = 15
			detection_range = 60.0  # 4x original
			move_speed = 9.0  # +50% total
			coin_value = 140
		_:
			# Default values already set
			pass


func _process(delta: float) -> void:
	if is_dead:
		return
	
	# Update hop animation when chasing (model only)
	if is_chasing and model:
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
	
	# Check if player is in range and should chase
	_update_chase_state()
	
	# Move towards player if chasing
	if is_chasing and player and is_instance_valid(player):
		var direction := (player.global_position - global_position)
		direction.y = 0  # Horizontal only
		var distance := direction.length()
		
		if distance > 0.5:  # Don't get too close
			direction = direction.normalized()
			velocity.x = direction.x * move_speed
			velocity.z = direction.z * move_speed
			
			# Face player direction
			var look_target := global_position + direction
			look_at(look_target, Vector3.UP)
			rotation.x = 0
			rotation.z = 0
		else:
			velocity.x = 0
			velocity.z = 0
	else:
		# Standing idle
		velocity.x = 0
		velocity.z = 0
	
	move_and_slide()


func _update_chase_state() -> void:
	## Check if player is within detection range
	if not player or not is_instance_valid(player):
		# Only lookup once when invalid, not every frame
		if not player:
			player = get_tree().get_first_node_in_group("player") as Node3D
		is_chasing = false
		return
	
	var distance := global_position.distance_to(player.global_position)
	
	# Start chasing if player enters range
	if distance <= detection_range:
		if not is_chasing:
			is_chasing = true
			hop_phase = 0.0  # Reset hop animation
	elif is_chasing and distance > detection_range * 1.5:
		# Stop chasing if player gets too far (hysteresis to prevent flickering)
		is_chasing = false


func _on_detect_area_body_entered(body: Node) -> void:
	if is_dead:
		return
	
	if body.is_in_group("player"):
		# Don't damage player if they're in the air (jumping)
		if body.has_method("get") and body.get("is_on_ground") == false:
			return
		_damage_player(body)
		die(body)


func _damage_player(player_node: Node) -> void:
	## Deal damage to player before dying
	# Play hurt sound
	if audio_manager:
		audio_manager.play_hurt_sound()
	
	# Deal damage through GameManager
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.take_damage(damage)
	
	# Haptic feedback
	if audio_manager and audio_manager.has_method("vibrate"):
		audio_manager.vibrate(100)


func die(killer: Node = null) -> void:
	if is_dead:
		return
	
	is_dead = true
	is_chasing = false
	
	# Play death sound
	if audio_manager:
		audio_manager.play_npc_death_sound("enemy")
	
	# Award coins
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
		gm.record_destroyed_object(object_id, object_name, coin_value)
	
	# Play death animation - fly off in direction away from killer
	_play_death_animation(killer)


func _play_death_animation(killer: Node = null) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	# Determine fly direction (away from killer or random)
	var fly_direction := Vector3.ZERO
	if killer and killer is Node3D:
		fly_direction = (global_position - killer.global_position).normalized()
		fly_direction.y = 0
	
	if fly_direction.length() < 0.1:
		# Random direction
		var angle := rng.randf_range(0, TAU)
		fly_direction = Vector3(cos(angle), 0, sin(angle))
	
	# Add upward component
	fly_direction = fly_direction.normalized()
	fly_direction.y = rng.randf_range(0.3, 0.5)
	fly_direction = fly_direction.normalized()
	
	# Random rotation velocity (faster spin)
	var rotation_velocity := Vector3(
		rng.randf_range(-15.0, 15.0),
		rng.randf_range(-15.0, 15.0),
		rng.randf_range(-15.0, 15.0)
	)
	
	# Animate flying away
	var anim_velocity := fly_direction * rng.randf_range(20.0, 35.0)
	var anim_gravity := 12.0
	var lifetime := 1.5
	var elapsed := 0.0
	
	while elapsed < lifetime and is_instance_valid(self):
		var delta := get_process_delta_time()
		elapsed += delta
		
		# Apply physics
		anim_velocity.y -= anim_gravity * delta
		global_position += anim_velocity * delta
		
		# Apply rotation
		if model:
			model.rotation += rotation_velocity * delta
		else:
			rotation += rotation_velocity * delta
		
		# Air resistance
		anim_velocity.x *= 0.98
		anim_velocity.z *= 0.98
		
		var tree := get_tree()
		if tree == null:
			break
		await tree.process_frame
	
	# Remove from scene
	if is_instance_valid(self):
		queue_free()

extends CharacterBody3D
class_name CatapultNPC
## Catapult NPC - stationary enemy that shoots projectiles at player
## Rotates to face player, plays animation, shoots ballistic projectiles
## Animation: main.action with 50 frames, shoots at frame 3

@export var damage: int = 30
@export var coin_value: int = 200
@export var object_id: String = "npc_catapult"
@export var object_name: String = "Catapult"

# Detection and firing
const DETECTION_RANGE: float = 80.0  # Increased range
const FIRE_RATE_FRAMES: int = 50  # Animation length in frames
const FIRE_FRAME: int = 3  # Frame at which projectile spawns
const ANIMATION_FPS: float = 24.0  # Standard Blender FPS
const ROTATION_SPEED: float = 2.0  # Radians per second

# Projectile spawn offset (relative to catapult, where the arm is)
const PROJECTILE_SPAWN_HEIGHT: float = 3.0
const PROJECTILE_SPAWN_FORWARD: float = 2.0  # Spawn far enough to avoid self-collision

# Internal state
var is_dead := false
var is_active := false  # Player in range
var player: Node3D = null
var model: Node3D = null
var animation_player: AnimationPlayer = null
var audio_manager: Node
var model_height: float = 2.0

# Animation state
var animation_time: float = 0.0
var fire_time: float = 0.0  # Time at which to spawn projectile
var animation_duration: float = 0.0
var has_fired_this_cycle := false


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("enemy_npcs")
	add_to_group("catapults")
	
	audio_manager = get_node_or_null("/root/AudioManager")
	
	# Calculate animation timing
	animation_duration = FIRE_RATE_FRAMES / ANIMATION_FPS
	fire_time = FIRE_FRAME / ANIMATION_FPS
	
	# Find model and animation player
	await get_tree().process_frame
	model = get_node_or_null("Model")
	if model:
		# No model rotation needed - catapult CharacterBody3D rotates to face player
		# Find AnimationPlayer in model hierarchy
		animation_player = _find_animation_player(model)
		if animation_player:
			_setup_animation()
	
	# Connect detection area
	var detect_area := get_node_or_null("DetectArea") as Area3D
	if detect_area:
		detect_area.body_entered.connect(_on_detect_area_body_entered)
	
	# Find player reference
	player = get_tree().get_first_node_in_group("player") as Node3D


func _find_animation_player(node: Node) -> AnimationPlayer:
	## Recursively find AnimationPlayer in node hierarchy
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null


func _setup_animation() -> void:
	## Setup animation player for catapult firing
	if not animation_player:
		return
	
	# Check available animations
	var anims := animation_player.get_animation_list()
	
	# Look for the main action animation
	var anim_name := ""
	for name in anims:
		if "main" in name.to_lower() or "action" in name.to_lower():
			anim_name = name
			break
	
	if anim_name.is_empty() and anims.size() > 0:
		anim_name = anims[0]
	
	if not anim_name.is_empty():
		# Get actual animation duration
		var anim := animation_player.get_animation(anim_name)
		if anim:
			animation_duration = anim.length
			# Recalculate fire time based on actual duration
			fire_time = animation_duration * (float(FIRE_FRAME) / float(FIRE_RATE_FRAMES))


func _process(delta: float) -> void:
	if is_dead:
		return
	
	# Check if player is in range
	_update_active_state()
	
	if not is_active:
		return
	
	# Rotate towards player
	_rotate_towards_player(delta)
	
	# Handle animation and firing
	_update_firing(delta)


func _update_active_state() -> void:
	## Check if player is within detection range
	if not player or not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player") as Node3D
		is_active = false
		return
	
	var distance := global_position.distance_to(player.global_position)
	is_active = distance <= DETECTION_RANGE


func _rotate_towards_player(delta: float) -> void:
	## Smoothly rotate to face the player
	if not player or not is_instance_valid(player):
		return
	
	var direction := player.global_position - global_position
	direction.y = 0
	
	if direction.length() < 0.1:
		return
	
	# Calculate target rotation to face player (no PI offset - model faces +Z)
	var target_rotation := atan2(direction.x, direction.z)
	
	# Smoothly interpolate rotation
	var current := rotation.y
	var diff := wrapf(target_rotation - current, -PI, PI)
	
	if abs(diff) > 0.01:
		rotation.y += sign(diff) * min(abs(diff), ROTATION_SPEED * delta)


func _update_firing(delta: float) -> void:
	## Handle firing animation and projectile spawning
	animation_time += delta
	
	# Check if it's time to fire
	if not has_fired_this_cycle and animation_time >= fire_time:
		_fire_projectile()
		has_fired_this_cycle = true
	
	# Reset cycle when animation completes
	if animation_time >= animation_duration:
		animation_time = 0.0
		has_fired_this_cycle = false
		
		# Play animation
		if animation_player:
			var anims := animation_player.get_animation_list()
			if anims.size() > 0:
				animation_player.play(anims[0])


func _fire_projectile() -> void:
	## Spawn and launch 3 projectiles with spread at predicted player position
	if not player or not is_instance_valid(player):
		return
	
	# Calculate direction to player (don't rely on catapult rotation)
	var direction_to_player := (player.global_position - global_position).normalized()
	direction_to_player.y = 0
	if direction_to_player.length() < 0.1:
		direction_to_player = Vector3.FORWARD
	else:
		direction_to_player = direction_to_player.normalized()
	
	# Calculate spawn position based on direction to player
	var spawn_pos := global_position + Vector3.UP * PROJECTILE_SPAWN_HEIGHT + direction_to_player * PROJECTILE_SPAWN_FORWARD
	
	# Predict where player will be when projectile lands
	var target_pos := _predict_player_position()
	
	# Fire 3 projectiles with spread
	const SPREAD_RADIUS := 4.0  # Random spread radius in meters
	for i in range(3):
		var spread_offset := Vector3.ZERO
		if i > 0:  # First projectile aims exactly at target
			var angle := randf() * TAU
			var dist := randf() * SPREAD_RADIUS
			spread_offset = Vector3(cos(angle) * dist, 0, sin(angle) * dist)
		
		var projectile := CatapultProjectile.new()
		get_tree().current_scene.add_child(projectile)
		projectile.launch(spawn_pos, target_pos + spread_offset, damage, self, global_position.y)


func _predict_player_position() -> Vector3:
	## Predict where the player will be when projectile arrives
	## Uses exact flight time calculation for accurate prediction
	if not player or not is_instance_valid(player):
		return global_position + Vector3.FORWARD * 10.0
	
	var player_pos := player.global_position
	var player_vel := Vector3.ZERO
	
	# Get player velocity
	if player is RigidBody3D:
		player_vel = (player as RigidBody3D).linear_velocity
	elif player is CharacterBody3D:
		player_vel = (player as CharacterBody3D).velocity
	
	# Calculate horizontal distance to player
	var spawn_offset := Vector3.UP * PROJECTILE_SPAWN_HEIGHT
	var spawn_pos := global_position + spawn_offset
	var horizontal_dist := Vector2(player_pos.x - spawn_pos.x, player_pos.z - spawn_pos.z).length()
	
	# Flight time = distance / projectile_speed (using constant from projectile)
	const PROJECTILE_SPEED := 36.0  # Must match CatapultProjectile.PROJECTILE_SPEED
	var flight_time := horizontal_dist / PROJECTILE_SPEED
	
	# Predict where player will be after flight_time
	var predicted_pos := player_pos + player_vel * flight_time
	
	# Iteratively refine prediction (player moves, so distance changes)
	for _i in range(2):
		horizontal_dist = Vector2(predicted_pos.x - spawn_pos.x, predicted_pos.z - spawn_pos.z).length()
		flight_time = horizontal_dist / PROJECTILE_SPEED
		predicted_pos = player_pos + player_vel * flight_time
	
	# Keep Y at player's current ground level
	predicted_pos.y = player_pos.y
	
	return predicted_pos


func _on_detect_area_body_entered(body: Node) -> void:
	## Player collision with catapult
	if is_dead:
		return
	
	if body.is_in_group("player"):
		# Catapult doesn't deal damage when touched - it's destroyed instead
		die(body)


func die(killer: Node = null) -> void:
	if is_dead:
		return
	
	is_dead = true
	is_active = false
	
	# Play death sound
	if audio_manager:
		audio_manager.play_npc_death_sound("catapult")
	
	# Award coins
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
		gm.record_destroyed_object(object_id, object_name, coin_value)
	
	# Play death animation
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
		var angle := rng.randf_range(0, TAU)
		fly_direction = Vector3(cos(angle), 0, sin(angle))
	
	fly_direction = fly_direction.normalized()
	fly_direction.y = rng.randf_range(0.3, 0.5)
	fly_direction = fly_direction.normalized()
	
	var rotation_velocity := Vector3(
		rng.randf_range(-10.0, 10.0),
		rng.randf_range(-10.0, 10.0),
		rng.randf_range(-10.0, 10.0)
	)
	
	var anim_velocity := fly_direction * rng.randf_range(15.0, 25.0)
	var anim_gravity := 12.0
	var lifetime := 1.5
	var elapsed := 0.0
	
	while elapsed < lifetime and is_instance_valid(self):
		var delta := get_process_delta_time()
		elapsed += delta
		
		anim_velocity.y -= anim_gravity * delta
		global_position += anim_velocity * delta
		
		if model:
			model.rotation += rotation_velocity * delta
		else:
			rotation += rotation_velocity * delta
		
		anim_velocity.x *= 0.98
		anim_velocity.z *= 0.98
		
		await get_tree().process_frame
	
	if is_instance_valid(self):
		queue_free()

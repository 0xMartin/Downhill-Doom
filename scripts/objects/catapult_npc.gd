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
const ROTATION_SPEED: float = 2.8  # Radians per second (increased by 40%)

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
	if get_tree():
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
	
	# Set random spawn rotation facing forward (+Z direction, toward approaching player)
	# Random angle between -PI/2 and +PI/2 (180 degree arc facing forward)
	rotation.y = randf_range(-PI / 2.0, PI / 2.0)


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
	## Check if player is within detection range and in front of catapult
	if not player or not is_instance_valid(player):
		# Only lookup once when invalid, not every frame
		if not player:
			player = get_tree().get_first_node_in_group("player") as Node3D
		is_active = false
		return
	
	# Check distance
	var distance := global_position.distance_to(player.global_position)
	if distance > DETECTION_RANGE:
		is_active = false
		return
	
	# Don't fire at player who has already passed (player moves in -Z direction)
	# If player.z < catapult.z, player has passed the catapult
	if player.global_position.z < global_position.z - 5.0:
		is_active = false
		return
	
	is_active = true


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
	
	# Check if we're facing the player (don't fire while still rotating)
	var direction := player.global_position - global_position
	direction.y = 0
	if direction.length() < 0.1:
		return
	
	var target_angle := atan2(direction.x, direction.z)
	var angle_diff: float = absf(wrapf(target_angle - rotation.y, -PI, PI))
	if angle_diff > 0.3:  # ~17 degrees tolerance
		return  # Not facing player yet, don't fire
	
	# Calculate direction to player
	var direction_to_player := direction.normalized()
	
	# Calculate spawn position based on direction to player
	var spawn_pos := global_position + Vector3.UP * PROJECTILE_SPAWN_HEIGHT + direction_to_player * PROJECTILE_SPAWN_FORWARD
	
	# Fire one projectile at predicted position
	var target_pos: Vector3 = _predict_player_position()
	
	var projectile := CatapultProjectile.new()
	get_tree().current_scene.add_child(projectile)
	projectile.launch(spawn_pos, target_pos, damage, self, global_position.y)


func _predict_player_position() -> Vector3:
	## Predict where the player will be when projectile arrives using exact interception math
	## Solves the quadratic equation for projectile-target interception:
	## |P + V*t - C|² = (s*t)² where P=player pos, V=player vel, C=spawn pos, s=projectile speed
	if not player or not is_instance_valid(player):
		return global_position + Vector3.FORWARD * 10.0
	
	const PROJECTILE_SPEED: float = 36.0
	
	var player_pos: Vector3 = player.global_position
	var player_vel: Vector3 = Vector3.ZERO
	
	# Get player velocity (full 3D for accurate prediction)
	if player is RigidBody3D:
		player_vel = (player as RigidBody3D).linear_velocity
	elif player is CharacterBody3D:
		player_vel = (player as CharacterBody3D).velocity
	
	# Spawn position (where projectile originates)
	var spawn_pos: Vector3 = global_position + Vector3.UP * PROJECTILE_SPAWN_HEIGHT
	
	# Relative position: D = P - C (player position relative to spawn)
	var relative_pos: Vector3 = player_pos - spawn_pos
	
	# Solve quadratic equation: at² + bt + c = 0
	# where: a = |V|² - s², b = 2*D·V, c = |D|²
	var speed_sq: float = PROJECTILE_SPEED * PROJECTILE_SPEED
	var vel_sq: float = player_vel.length_squared()
	
	var a: float = vel_sq - speed_sq
	var b: float = 2.0 * relative_pos.dot(player_vel)
	var c: float = relative_pos.length_squared()
	
	var intercept_time: float = 0.0
	
	if absf(a) < 0.0001:
		# Linear case: player speed ≈ projectile speed
		# bt + c = 0 → t = -c/b
		if absf(b) > 0.0001:
			intercept_time = -c / b
		else:
			# Player stationary or moving parallel - aim at current position
			intercept_time = 0.0
	else:
		# Quadratic case
		var discriminant: float = b * b - 4.0 * a * c
		
		if discriminant < 0.0:
			# No real solution - projectile can't catch player
			# Fall back to aiming at current position
			return player_pos
		
		var sqrt_disc: float = sqrt(discriminant)
		var t1: float = (-b - sqrt_disc) / (2.0 * a)
		var t2: float = (-b + sqrt_disc) / (2.0 * a)
		
		# Choose smallest positive time
		if t1 > 0.0 and t2 > 0.0:
			intercept_time = minf(t1, t2)
		elif t1 > 0.0:
			intercept_time = t1
		elif t2 > 0.0:
			intercept_time = t2
		else:
			# Both negative - player is behind us or moving away too fast
			return player_pos
	
	# Clamp intercept time to reasonable range (0.1s to 3s)
	intercept_time = clampf(intercept_time, 0.1, 3.0)
	
	# Calculate predicted position
	var predicted_pos: Vector3 = player_pos + player_vel * intercept_time
	
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
	
	# Fling animation via DestructionManager (slower rotation for big catapult)
	var dm := get_node_or_null("/root/DestructionManager")
	if dm:
		dm.fling_object(self, killer, model, 22.0, 32.0, 0.5)
	else:
		queue_free()

extends RigidBody3D
## Boulder player controller - automatically rolls forward, player controls left/right

signal died
signal hit_rock(impact_position: Vector3)

# Movement parameters
@export var forward_force: float = 50.0  # Constant forward push
@export var lateral_force: float = 110.0  # Direct sideways steering force (+10%)
@export var max_angular_velocity: float = 30.0  # Cap rotation speed
@export var max_speed: float = 27.5  # Maximum forward speed (+10%)
@export var max_lateral_speed: float = 10.0  # Cap sideways speed
@export var death_height_offset: float = -30.0  # Y offset below terrain that triggers death
@export var rock_damage: int = 12  # Damage taken from rocks (halved)
@export var sphere_radius: float = 0.7  # For calculating proper roll rotation

# Jump parameters
@export var jump_force: float = 60.0  # Upward impulse when jumping (50% reduced)
@export var jump_cooldown_time: float = 0.3  # Minimum time between jumps

# Tilt control - SIMPLE direct mapping
var tilt_multiplier: float = 3.0  # How much accel.x affects steering (higher = more sensitive)

var is_dead := false
var player_model: Node3D  # Visual model (separate from physics)
var can_move := false
var start_y: float = 0.0
var game_manager: Node
var hit_cooldown: float = 0.0  # Prevent multiple hits from same rock

var terrain_slope: float = 15.0  # Will be set from terrain generator
var audio_manager: Node
var item_manager: Node  # Cached reference for item effects
var jump_cooldown: float = 0.0  # Time until next jump allowed
var is_on_ground: bool = true  # Track if player is touching ground

# Supercharge state
var is_supercharged: bool = false
var supercharge_scale_target: float = 1.0
var supercharge_current_scale: float = 1.0
var supercharge_glow: OmniLight3D
var supercharge_particles: GPUParticles3D
var base_forward_force: float
var base_jump_force: float
const SUPERCHARGE_SCALE_MULTIPLIER: float = 2.0
const SUPERCHARGE_SCALE_DURATION: float = 0.4
const SUPERCHARGE_SPEED_BONUS: float = 1.375 
const SUPERCHARGE_JUMP_BONUS: float = 1.15

func _ready() -> void:
	# Get autoload references
	game_manager = get_node("/root/GameManager")
	audio_manager = get_node("/root/AudioManager")
	item_manager = get_node_or_null("/root/ItemManager")
	print("[Player] ItemManager reference: ", item_manager)
	
	# Store base values for supercharge
	base_forward_force = forward_force
	base_jump_force = jump_force
	
	# Connect to supercharge signals
	if game_manager:
		game_manager.supercharge_activated.connect(_on_supercharge_activated)
		game_manager.supercharge_ended.connect(_on_supercharge_ended)
	
	# Get visual model for manual rotation
	player_model = get_node_or_null("PlayerModel")
	if player_model:
		# Make top-level so it doesn't inherit RigidBody rotation
		player_model.top_level = true
		player_model.global_position = global_position
		# Disable shadows and make unshaded
		_setup_unshaded_materials(player_model)
	
	# Enable continuous collision detection for fast-moving physics
	continuous_cd = true
	add_to_group("player")
	
	# Enable contact monitoring for rock collisions
	contact_monitor = true
	max_contacts_reported = 8  # More contacts for reliable detection
	body_entered.connect(_on_body_entered)
	
	# Freeze until terrain is ready
	freeze = true
	start_y = global_position.y
	
	# Wait for terrain
	var terrain = get_tree().get_first_node_in_group("terrain_generator")
	if terrain:
		terrain_slope = terrain.slope_angle
		if terrain.is_ready:
			_start_rolling()
		else:
			terrain.terrain_ready.connect(_start_rolling)
	else:
		# No terrain generator, start immediately
		await get_tree().create_timer(0.1).timeout
		_start_rolling()

func _start_rolling() -> void:
	freeze = false
	can_move = true
	
	# Start rolling sound
	if audio_manager:
		audio_manager.start_roll_sound()
	
	# Register with GameManager
	if game_manager:
		game_manager.set_player(self)
		game_manager.start_game()

func _physics_process(delta: float) -> void:
	if is_dead or not can_move:
		return
	
	# Update hit cooldown
	if hit_cooldown > 0:
		hit_cooldown -= delta
	
	# Update jump cooldown
	if jump_cooldown > 0:
		jump_cooldown -= delta
	
	# Check if on ground (simple raycast down)
	_update_ground_state()
	
	# Update supercharge scale smoothly
	_update_supercharge_scale(delta)
	
	# Death detection disabled for now - terrain goes downhill infinitely
	# TODO: Implement proper death detection (e.g., falling off edges)
	# if global_position.y < death_height_offset:
	# 	die()
	# 	return
	
	# Apply constant forward force only if below max speed
	var current_forward_speed := -linear_velocity.z  # Negative Z is forward
	
	# Get item speed multiplier (speed boost item effect)
	var item_speed_mult: float = 1.0
	if item_manager:
		item_speed_mult = item_manager.speed_multiplier
		if item_speed_mult != 1.0:
			print("[Player] Applying speed multiplier: ", item_speed_mult, " to max_speed: ", max_speed * item_speed_mult)
	else:
		print("[Player] WARNING: item_manager is null!")
	
	var effective_max_speed := max_speed * item_speed_mult
	if current_forward_speed < effective_max_speed:
		# Apply more force when slow, less when approaching max speed
		var speed_factor := 1.0 - (current_forward_speed / effective_max_speed)
		speed_factor = clamp(speed_factor, 0.2, 1.0)
		apply_central_force(Vector3(0, 0, -forward_force * item_speed_mult * speed_factor))
	
	# Get horizontal input (A/D or arrow keys) - for desktop testing
	var keyboard_input: float = 0.0
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("ui_left"):
		keyboard_input = -1.0
	if Input.is_action_pressed("move_right") or Input.is_action_pressed("ui_right"):
		keyboard_input = 1.0
	
	# Tilt controls for mobile - SIMPLE AND DIRECT
	# accel.x: negative when tilted left, positive when tilted right
	# We want: tilt left = move left (negative X), tilt right = move right (positive X)
	var accel := Input.get_accelerometer()
	var tilt_input: float = 0.0
	if accel != Vector3.ZERO:
		# Direct mapping: accel.x typically ranges from -10 to +10
		# Normalize to roughly -1 to +1 and apply multiplier
		tilt_input = clamp(accel.x / 6.0, -1.0, 1.0)
	
	# Use tilt if present, otherwise keyboard
	var final_input: float = tilt_input if abs(tilt_input) > 0.05 else keyboard_input
	
	# Apply direct lateral force - INSTANT RESPONSE
	if final_input != 0.0:
		# Direct sideways velocity change for immediate response
		var target_lateral_velocity: float = final_input * max_lateral_speed
		var current_lateral_velocity: float = linear_velocity.x
		
		# Smoothly move towards target (but still responsive)
		var velocity_diff: float = target_lateral_velocity - current_lateral_velocity
		apply_central_force(Vector3(velocity_diff * lateral_force * delta * 60.0, 0, 0))
	else:
		# Apply drag to stop sideways movement when not steering
		linear_velocity.x *= 0.95
	
	# Hard cap lateral speed
	linear_velocity.x = clamp(linear_velocity.x, -max_lateral_speed, max_lateral_speed)
	
	# Clamp angular velocity to prevent excessive spinning
	if angular_velocity.length() > max_angular_velocity:
		angular_velocity = angular_velocity.normalized() * max_angular_velocity
	
	# Update rolling sound pitch based on speed and ground contact
	if audio_manager:
		var speed_ratio := current_forward_speed / max_speed
		audio_manager.update_roll_pitch(speed_ratio)
		audio_manager.set_roll_ground_contact(is_on_ground)
	
	# Manual visual rotation based on actual velocity (not physics rotation)
	if player_model:
		# Keep visual model at player position
		player_model.global_position = global_position
		
		# Calculate proper angular velocity: omega = v / r
		var rotation_scale := 0.7  # Slow down visual rotation slightly
		# Forward movement (negative Z) rotates around X axis
		var forward_angular := linear_velocity.z / sphere_radius * rotation_scale
		# Sideways movement (X) rotates around Z axis (negated for correct direction)
		var side_angular := -linear_velocity.x / sphere_radius * rotation_scale
		
		# Apply rotation to visual model
		player_model.rotate_x(forward_angular * delta)
		player_model.rotate_z(side_angular * delta)

func _update_ground_state() -> void:
	# Simple ground check: raycast downward (small tolerance for easier jumping)
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, -sphere_radius - 0.8, 0)  # 0.8m tolerance under sphere
	)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	is_on_ground = not result.is_empty()

func _input(event: InputEvent) -> void:
	if is_dead or not can_move:
		return
	
	# Jump on spacebar (desktop)
	if event.is_action_pressed("jump"):
		_try_jump()
		return
	
	# Jump on screen tap (mobile) - but not on UI elements
	if event is InputEventScreenTouch:
		if event.pressed:
			_try_jump()

func _try_jump() -> void:
	if jump_cooldown > 0 or not is_on_ground:
		return
	
	# Reset vertical velocity for consistent jumps (cancel any falling)
	linear_velocity.y = 0.0
	
	# Apply upward impulse
	apply_central_impulse(Vector3(0, jump_force, 0))
	jump_cooldown = jump_cooldown_time

func die() -> void:
	if is_dead:
		return
	
	# Check if we're still in the scene tree
	if not is_inside_tree():
		return
	
	is_dead = true
	
	# Stop rolling sound
	if audio_manager:
		audio_manager.stop_roll_sound()
		audio_manager.play_death_sound()
	
	# Freeze physics immediately
	freeze = true
	
	# Shatter the player model using mesh destruction - fly upward for dramatic effect
	var model: Node3D = get_node_or_null("PlayerModel")
	if model:
		# Impact velocity is downhill direction for debris spread
		var impact_direction := linear_velocity.normalized()
		var impact_velocity := impact_direction * 10.0
		# fly_upward=true makes debris fly up instead of falling
		DestructionManager.shatter(model, impact_velocity, false, true)
	
	# Big and long screen shake on death
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("shake_extended"):
		camera.shake_extended(1.5, 1.2)  # High intensity, slow decay for long shake
	
	# Strong and long vibration on death
	Input.vibrate_handheld(500)  # 500ms vibration
	
	# Hide the ball (model already hidden by shatter)
	visible = false
	
	# Wait before showing death menu (2 seconds)
	await get_tree().create_timer(2.0).timeout
	
	# Now emit died signal and end game
	died.emit()
	if game_manager:
		game_manager.end_game()

func _on_body_entered(body: Node) -> void:
	if is_dead or hit_cooldown > 0:
		return
	
	# Check if we hit an enemy (deals damage)
	if body.is_in_group("enemies"):
		hit_cooldown = 0.5  # Prevent rapid hits
		var impact_pos := global_position
		hit_rock.emit(impact_pos)
		_spawn_rock_impact_particles(impact_pos)
		if audio_manager:
			audio_manager.play_hurt_sound()
		if game_manager:
			game_manager.take_damage(rock_damage)
		return
	
	# Rocks are decoration only - collision/slowdown but no damage
	if body.is_in_group("rocks") or (body is StaticBody3D and body.name.begins_with("Rock")):
		# Just visual/audio feedback, no damage
		pass

func _spawn_rock_impact_particles(impact_pos: Vector3) -> void:
	# Check if we're in the scene tree before spawning
	if not is_inside_tree():
		return
	
	var particles := GPUParticles3D.new()
	particles.name = "RockImpactParticles"
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 25
	particles.lifetime = 0.8
	
	var proc_material := ParticleProcessMaterial.new()
	proc_material.direction = Vector3(0, 1, 0)
	proc_material.spread = 80.0
	proc_material.initial_velocity_min = 4.0
	proc_material.initial_velocity_max = 10.0
	proc_material.gravity = Vector3(0, -15, 0)
	proc_material.scale_min = 0.05
	proc_material.scale_max = 0.12
	proc_material.color = Color(0.5, 0.45, 0.4)  # Gray rock color
	particles.process_material = proc_material
	
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = Color(0.5, 0.45, 0.4)
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh
	
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(particles)
		particles.global_position = impact_pos  # Set position AFTER adding to tree
		particles.emitting = true
		
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(particles):
				particles.queue_free()
		)

func _setup_unshaded_materials(node: Node) -> void:
	# Disable shadows and set unshaded mode on all meshes
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		
		# Make material unshaded
		for i in range(mesh_instance.get_surface_override_material_count()):
			var mat := mesh_instance.get_surface_override_material(i)
			if mat and mat is StandardMaterial3D:
				var new_mat := mat.duplicate() as StandardMaterial3D
				new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh_instance.set_surface_override_material(i, new_mat)
		
		# Also check mesh resource materials
		if mesh_instance.mesh:
			for i in range(mesh_instance.mesh.get_surface_count()):
				var mat := mesh_instance.mesh.surface_get_material(i)
				if mat and mat is StandardMaterial3D:
					var new_mat := mat.duplicate() as StandardMaterial3D
					new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mesh_instance.set_surface_override_material(i, new_mat)
	
	# Recurse to children
	for child in node.get_children():
		_setup_unshaded_materials(child)

# ========== Supercharge System ==========

func _on_supercharge_activated() -> void:
	is_supercharged = true
	supercharge_scale_target = SUPERCHARGE_SCALE_MULTIPLIER
	
	# Apply speed and jump bonuses
	forward_force = base_forward_force * SUPERCHARGE_SPEED_BONUS
	jump_force = base_jump_force * SUPERCHARGE_JUMP_BONUS
	max_speed *= SUPERCHARGE_SPEED_BONUS
	
	# Create red glow light
	_create_supercharge_glow()
	
	# Create particles
	_create_supercharge_particles()

func _on_supercharge_ended() -> void:
	is_supercharged = false
	supercharge_scale_target = 1.0
	
	# Restore normal values
	forward_force = base_forward_force
	jump_force = base_jump_force
	max_speed /= SUPERCHARGE_SPEED_BONUS
	
	# Remove effects
	_remove_supercharge_effects()

func _update_supercharge_scale(delta: float) -> void:
	if absf(supercharge_current_scale - supercharge_scale_target) < 0.01:
		supercharge_current_scale = supercharge_scale_target
		return
	
	# Smoothly interpolate scale
	var scale_speed: float = (SUPERCHARGE_SCALE_MULTIPLIER - 1.0) / SUPERCHARGE_SCALE_DURATION
	if supercharge_current_scale < supercharge_scale_target:
		supercharge_current_scale = minf(supercharge_current_scale + scale_speed * delta, supercharge_scale_target)
	else:
		supercharge_current_scale = maxf(supercharge_current_scale - scale_speed * delta, supercharge_scale_target)
	
	# Apply scale to visual model
	if player_model:
		player_model.scale = Vector3.ONE * supercharge_current_scale
	
	# Scale the collision shape
	var collision_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape and collision_shape.shape is SphereShape3D:
		var sphere := collision_shape.shape as SphereShape3D
		sphere.radius = sphere_radius * supercharge_current_scale

func _create_supercharge_glow() -> void:
	if supercharge_glow:
		return
	
	supercharge_glow = OmniLight3D.new()
	supercharge_glow.name = "SuperchargeGlow"
	supercharge_glow.light_color = Color(1.0, 0.2, 0.1)  # Red glow
	supercharge_glow.light_energy = 3.0
	supercharge_glow.omni_range = 5.0
	supercharge_glow.omni_attenuation = 0.5
	add_child(supercharge_glow)

func _create_supercharge_particles() -> void:
	if supercharge_particles:
		return
	
	supercharge_particles = GPUParticles3D.new()
	supercharge_particles.name = "SuperchargeParticles"
	supercharge_particles.amount = 21
	supercharge_particles.lifetime = 0.8
	supercharge_particles.explosiveness = 0.1
	supercharge_particles.randomness = 0.5
	
	var proc_material := ParticleProcessMaterial.new()
	proc_material.direction = Vector3(0, 1, 0)
	proc_material.spread = 180.0  # Full sphere spread
	proc_material.initial_velocity_min = 2.0
	proc_material.initial_velocity_max = 4.0
	proc_material.gravity = Vector3(0, 2, 0)  # Float up
	proc_material.scale_min = 0.2
	proc_material.scale_max = 0.5
	proc_material.color = Color(1.0, 0.3, 0.1, 0.8)  # Red-orange
	
	# Try to load light beam texture
	var light_texture := load("res://assets/textures/light_beam.png") as Texture2D
	if light_texture:
		var quad_mesh := QuadMesh.new()
		quad_mesh.size = Vector2(0.5, 0.5)
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_texture = light_texture
		mat.albedo_color = Color(1.0, 0.3, 0.1, 0.8)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		quad_mesh.material = mat
		supercharge_particles.draw_pass_1 = quad_mesh
	else:
		# Fallback to simple sphere particles
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = 0.1
		sphere_mesh.height = 0.2
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.3, 0.1, 0.8)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.3, 0.1)
		mat.emission_energy_multiplier = 2.0
		sphere_mesh.material = mat
		supercharge_particles.draw_pass_1 = sphere_mesh
	
	supercharge_particles.process_material = proc_material
	add_child(supercharge_particles)
	supercharge_particles.emitting = true

func _remove_supercharge_effects() -> void:
	if supercharge_glow:
		supercharge_glow.queue_free()
		supercharge_glow = null
	
	if supercharge_particles:
		supercharge_particles.emitting = false
		# Delay removal to let particles fade
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(supercharge_particles):
				supercharge_particles.queue_free()
				supercharge_particles = null
		)

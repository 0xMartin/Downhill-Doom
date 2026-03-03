extends RigidBody3D
## Boulder player controller - automatically rolls forward, player controls left/right

signal died
signal hit_rock(impact_position: Vector3)

# Movement parameters
@export var forward_force: float = 50.0  # Constant forward push
@export var lateral_force: float = 100.0  # Direct sideways steering force
@export var max_angular_velocity: float = 30.0  # Cap rotation speed
@export var max_speed: float = 25.0  # Maximum forward speed
@export var max_lateral_speed: float = 10.0  # Cap sideways speed
@export var death_height_offset: float = -30.0  # Y offset below terrain that triggers death
@export var rock_damage: int = 12  # Damage taken from rocks (halved)
@export var sphere_radius: float = 0.7  # For calculating proper roll rotation

# Jump parameters
@export var jump_force: float = 120.0  # Upward impulse when jumping
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
var jump_cooldown: float = 0.0  # Time until next jump allowed
var is_on_ground: bool = true  # Track if player is touching ground
var was_on_ground: bool = true  # Previous frame ground state
var has_jumped: bool = false  # Track if player initiated a jump (for shock wave)

# Shock wave effect class
const ShockWaveManager := preload("res://scripts/effects/shock_wave_manager.gd")

# Dust particles
var dust_particles: GPUParticles3D

func _ready() -> void:
	# Get autoload references
	game_manager = get_node("/root/GameManager")
	audio_manager = get_node("/root/AudioManager")
	
	# Get visual model for manual rotation
	player_model = get_node_or_null("PlayerModel")
	if player_model:
		# Make top-level so it doesn't inherit RigidBody rotation
		player_model.top_level = true
		player_model.global_position = global_position
		# Disable shadows and make unshaded
		_setup_unshaded_materials(player_model)
	
	# Setup dust particles (under ball when on ground)
	_setup_dust_particles()
	
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
	
	# Save previous ground state for landing detection
	was_on_ground = is_on_ground
	
	# Check if on ground (simple raycast down)
	_update_ground_state()
	
	# Check for landing after jump - trigger shock wave
	if not was_on_ground and is_on_ground and has_jumped:
		has_jumped = false
		_spawn_landing_shock_wave()
	
	# Death detection disabled for now - terrain goes downhill infinitely
	# TODO: Implement proper death detection (e.g., falling off edges)
	# if global_position.y < death_height_offset:
	# 	die()
	# 	return
	
	# Apply constant forward force only if below max speed
	var current_forward_speed := -linear_velocity.z  # Negative Z is forward
	if current_forward_speed < max_speed:
		# Apply more force when slow, less when approaching max speed
		var speed_factor := 1.0 - (current_forward_speed / max_speed)
		speed_factor = clamp(speed_factor, 0.2, 1.0)
		apply_central_force(Vector3(0, 0, -forward_force * speed_factor))
	
	# Get horizontal input (A/D or arrow keys) - for desktop testing
	# Inverted and reduced to 60% intensity compared to tilt
	var keyboard_input: float = 0.0
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("ui_left"):
		keyboard_input = -0.7
	if Input.is_action_pressed("move_right") or Input.is_action_pressed("ui_right"):
		keyboard_input = 0.7
	
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
	
	# Update particle effects
	_update_particles(current_forward_speed)

func _update_particles(speed: float) -> void:
	var speed_ratio := speed / max_speed
	
	# Dust: emit when on ground and moving
	if dust_particles:
		dust_particles.emitting = is_on_ground and speed_ratio > 0.2
		dust_particles.amount_ratio = clampf(speed_ratio * 0.8, 0.2, 1.0)

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
	
	# Mark that player initiated a jump (for shock wave on landing)
	has_jumped = true
	
	# Reset vertical velocity for consistent jumps (cancel any falling)
	linear_velocity.y = 0.0
	
	# Apply upward impulse
	apply_central_impulse(Vector3(0, jump_force, 0))
	jump_cooldown = jump_cooldown_time


## Spawn shock wave effect when landing after a jump
## Destroys trees, NPCs, buildings within radius
func _spawn_landing_shock_wave() -> void:
	# Spawn shock wave at player's position (slightly below for ground effect)
	var shock_position := global_position + Vector3(0, -sphere_radius * 0.5, 0)
	ShockWaveManager.spawn_shock_wave(shock_position, ShockWaveManager.Source.PLAYER)
	
	# Small screen shake for impact
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("shake"):
		camera.shake(0.4)
	
	# Haptic feedback
	if audio_manager:
		audio_manager.vibrate(80)


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
	var player_model: Node3D = get_node_or_null("PlayerModel")
	if player_model:
		# Impact velocity is downhill direction for debris spread
		var impact_direction := linear_velocity.normalized()
		var impact_velocity := impact_direction * 10.0
		# fly_upward=true makes debris fly up instead of falling
		DestructionManager.shatter(player_model, impact_velocity, false, true)
	
	# Big and long screen shake on death
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("shake_extended"):
		camera.shake_extended(1.5, 1.2)  # High intensity, slow decay for long shake
	
	# Strong and long vibration on death
	if audio_manager:
		audio_manager.vibrate(500)
	
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

## Setup dust particles when touching ground
func _setup_dust_particles() -> void:
	dust_particles = GPUParticles3D.new()
	dust_particles.name = "DustParticles"
	dust_particles.amount = 20
	dust_particles.lifetime = 0.8
	dust_particles.explosiveness = 0.0
	dust_particles.emitting = false
	
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.direction = Vector3(0, 1, 0)  # Upward
	proc_mat.spread = 60.0
	proc_mat.initial_velocity_min = 2.0
	proc_mat.initial_velocity_max = 4.0
	proc_mat.gravity = Vector3(0, -3, 0)
	proc_mat.scale_min = 0.1
	proc_mat.scale_max = 0.25
	proc_mat.color = Color(0.95, 0.97, 1.0, 0.6)  # Bright snow/dust color
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.95, 0.97, 1.0, 0.7))
	color_ramp.set_color(1, Color(0.95, 0.97, 1.0, 0.0))
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	proc_mat.color_ramp = color_tex
	dust_particles.process_material = proc_mat
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.98, 0.98, 1.0)
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_mat
	dust_particles.draw_pass_1 = mesh
	
	add_child(dust_particles)
	dust_particles.position = Vector3(0, -sphere_radius, 0)  # At the bottom of the ball

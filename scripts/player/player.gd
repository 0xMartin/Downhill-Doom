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
var terrain_generator: Node  # Reference to terrain for height queries
var audio_manager: Node
var jump_cooldown: float = 0.0  # Time until next jump allowed
var is_on_ground: bool = true  # Track if player is touching ground
var was_on_ground: bool = true  # Previous frame ground state
var has_jumped: bool = false  # Track if player initiated a jump (for shock wave)
var slam_charged: bool = false  # Charged slam attack (tap while falling)
var slam_flash_tween: Tween  # Visual feedback tween

# Supercharge state
var is_supercharged: bool = false
var supercharge_scale_target: float = 1.0
var supercharge_current_scale: float = 1.0
var supercharge_glow: OmniLight3D
var supercharge_particles: GPUParticles3D
var supercharge_trail: GPUParticles3D  # Fire trail behind player
var base_forward_force: float
var base_jump_force: float
var base_max_speed: float
const SUPERCHARGE_SCALE_MULTIPLIER: float = 2.0
const SUPERCHARGE_SCALE_DURATION: float = 0.4
const SUPERCHARGE_SPEED_BONUS: float = 1.3
const SUPERCHARGE_JUMP_BONUS: float = 1.6

# Shock wave effect class
const ShockWaveManager := preload("res://scripts/effects/shock_wave_manager.gd")

# Dust particles
var dust_particles: GPUParticles3D

# Slam cone effect (comet/meteor trail)
var slam_cone: MeshInstance3D
var slam_cone_mesh: CylinderMesh
var slam_cone_material: StandardMaterial3D
var slam_cone_shake_tween: Tween
var slam_cone_grow_tween: Tween
var slam_cone_grow_progress: float = 0.0

# Atmospheric particles (snow/dust in the air)
var atmosphere_particles: GPUParticles3D
var atmosphere_proc_mat: ParticleProcessMaterial

# Rock impact particle template (pre-created for cloning)
var _rock_impact_particle_template: GPUParticles3D

# Edge warning effect
var edge_warning_left: MeshInstance3D
var edge_warning_right: MeshInstance3D
var edge_warning_material: StandardMaterial3D
const EDGE_WARNING_DISTANCE: float = 6.0  # Start showing warning at this distance from edge
const TERRAIN_HALF_WIDTH: float = 18.0  # Half of terrain_width (36/2)

func _ready() -> void:
	# Get autoload references
	game_manager = get_node("/root/GameManager")
	audio_manager = get_node("/root/AudioManager")
	
	# Store base values for supercharge
	base_forward_force = forward_force
	base_jump_force = jump_force
	base_max_speed = max_speed
	
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
	
	# Setup dust particles (under ball when on ground)
	_setup_dust_particles()
	
	# Setup slam cone effect
	_setup_slam_cone()
	
	# Pre-create rock impact particle template
	_create_rock_impact_template()
	
	# Setup edge warning effect
	_setup_edge_warning()
	
	# Pre-create supercharge effects (hidden) to avoid first-activation lag
	_precreate_supercharge_effects()
	
	# Setup atmospheric particles (snow/dust in air)
	_setup_atmosphere_particles()
	
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
	terrain_generator = get_tree().get_first_node_in_group("terrain_generator")
	if terrain_generator:
		terrain_slope = terrain_generator.slope_angle
		if terrain_generator.is_ready:
			_start_rolling()
		else:
			terrain_generator.terrain_ready.connect(_start_rolling)
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
	
	# Update atmosphere particles position (follows player, doesn't rotate)
	# Also adjust particle velocity based on player speed
	if atmosphere_particles and is_instance_valid(atmosphere_particles):
		atmosphere_particles.global_position = global_position + Vector3(0, 4, -8)
		
		# Adapt particle movement to player velocity
		if atmosphere_proc_mat:
			var player_speed := linear_velocity.length()
			# Scale gravity towards camera based on speed (more speed = particles fly faster towards camera)
			var speed_factor := clampf(player_speed / max_speed, 0.2, 1.5)
			atmosphere_proc_mat.gravity = Vector3(0, -0.5, player_speed * 0.7)
			atmosphere_proc_mat.initial_velocity_min = 2.0 + player_speed * 0.15
			atmosphere_proc_mat.initial_velocity_max = 5.0 + player_speed * 0.3
	
	# Update supercharge scale smoothly
	_update_supercharge_scale(delta)
	
	# Check for landing - trigger shock wave only if slam was charged
	if not was_on_ground and is_on_ground:
		if slam_charged:
			_spawn_landing_shock_wave()
		# Reset states
		slam_charged = false
		has_jumped = false
		# Hide cone and stop tweens
		if slam_cone:
			slam_cone.visible = false
		if slam_cone_shake_tween:
			slam_cone_shake_tween.kill()
			slam_cone_shake_tween = null
		if slam_cone_grow_tween:
			slam_cone_grow_tween.kill()
			slam_cone_grow_tween = null
		if slam_flash_tween:
			slam_flash_tween.kill()
			slam_flash_tween = null
		if player_model:
			_set_model_emission(player_model, Color.BLACK)
	
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
	
	# Update slam cone position (it's top_level so needs manual update)
	if slam_cone and slam_cone.visible:
		_update_cone_position()
	
	# Update particle effects
	_update_particles(current_forward_speed)
	
	# Update edge warning
	_update_edge_warning()

func _update_particles(speed: float) -> void:
	var speed_ratio := speed / max_speed
	
	# Dust: emit when on ground and moving
	if dust_particles:
		# Hide dust when supercharged (only show red particles then)
		if is_supercharged:
			dust_particles.emitting = false
		else:
			dust_particles.emitting = is_on_ground and speed_ratio > 0.2
			dust_particles.amount_ratio = clampf(speed_ratio * 0.8, 0.2, 1.0)

func _update_ground_state() -> void:
	# Simple ground check: raycast downward (small tolerance for easier jumping)
	# Scale the raycast length with the current supercharge scale
	var current_radius := sphere_radius * supercharge_current_scale
	
	# Increase ground tolerance when supercharged - larger ball has more terrain irregularity issues
	var base_tolerance := 0.8
	var ground_tolerance: float
	if is_supercharged:
		# Much larger tolerance for 2x scale ball - terrain bumps cause hovering
		ground_tolerance = base_tolerance + current_radius * 0.8  # ~1.9m total when supercharged
	else:
		ground_tolerance = base_tolerance
	
	var space_state := get_world_3d().direct_space_state
	
	# Main center raycast
	var query := PhysicsRayQueryParameters3D.create(
		global_position,
		global_position + Vector3(0, -current_radius - ground_tolerance, 0)
	)
	query.exclude = [get_rid()]
	var result := space_state.intersect_ray(query)
	
	if not result.is_empty():
		is_on_ground = true
		return
	
	# When supercharged, also check additional points around the sphere for better coverage
	if is_supercharged:
		var check_offsets: Array[Vector3] = [
			Vector3(current_radius * 0.7, 0, 0),
			Vector3(-current_radius * 0.7, 0, 0),
			Vector3(0, 0, current_radius * 0.7),
			Vector3(0, 0, -current_radius * 0.7),
		]
		
		for offset: Vector3 in check_offsets:
			var check_pos: Vector3 = global_position + offset
			query = PhysicsRayQueryParameters3D.create(
				check_pos,
				check_pos + Vector3(0, -current_radius - ground_tolerance, 0)
			)
			query.exclude = [get_rid()]
			result = space_state.intersect_ray(query)
			if not result.is_empty():
				is_on_ground = true
				return
	
	is_on_ground = false

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
			# Use Godot's proper GUI hit testing
			var viewport := get_viewport()
			if viewport:
				var touch_pos: Vector2 = event.position
				# Check if a GUI control is at this position
				var is_gui_hit := viewport.gui_is_drag_successful() or _is_touch_on_supercharge_ui(touch_pos)
				if is_gui_hit:
					return  # Don't jump, UI handled it
			_try_jump()

## Check if touch position is over the supercharge UI panel
func _is_touch_on_supercharge_ui(touch_pos: Vector2) -> bool:
	var hud := get_node_or_null("/root/Game/HUD")
	if not hud:
		return false
	
	var panel := hud.get_node_or_null("SuperchargePanel")
	if panel and panel is Control:
		var rect: Rect2 = panel.get_global_rect()
		return rect.has_point(touch_pos)
	return false

func _try_jump() -> void:
	# If in air and falling, charge slam attack
	if not is_on_ground and linear_velocity.y < 0:
		_charge_slam()
		return
	
	if jump_cooldown > 0 or not is_on_ground:
		return
	
	# Reset vertical velocity for consistent jumps (cancel any falling)
	linear_velocity.y = 0.0
	
	# Apply upward impulse
	apply_central_impulse(Vector3(0, jump_force, 0))
	jump_cooldown = jump_cooldown_time
	has_jumped = true  # Mark that player initiated jump (for slam activation)

## Charge slam attack when tapping while falling
func _charge_slam() -> void:
	if slam_charged:
		return  # Already charged
	
	# Only allow slam if player jumped themselves (not knocked into air)
	if not has_jumped:
		return
	
	slam_charged = true
	
	# Show slam cone effect with grow animation
	if slam_cone:
		slam_cone.visible = true
		slam_cone_grow_progress = 0.0
		# Animate cone growing
		if slam_cone_grow_tween:
			slam_cone_grow_tween.kill()
		slam_cone_grow_tween = create_tween()
		slam_cone_grow_tween.tween_property(self, "slam_cone_grow_progress", 1.0, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_start_cone_shake()
	
	# Visual feedback - flash the player model
	if player_model:
		# Kill existing tween
		if slam_flash_tween:
			slam_flash_tween.kill()
		
		# Create pulsing glow effect
		slam_flash_tween = create_tween()
		slam_flash_tween.set_loops()  # Loop until landing
		slam_flash_tween.tween_callback(_slam_flash_on)
		slam_flash_tween.tween_interval(0.1)
		slam_flash_tween.tween_callback(_slam_flash_off)
		slam_flash_tween.tween_interval(0.1)

func _slam_flash_on() -> void:
	if player_model:
		_set_model_emission(player_model, Color(2.0, 1.5, 0.5))  # Bright yellow-orange

func _slam_flash_off() -> void:
	if player_model:
		_set_model_emission(player_model, Color.BLACK)

func _set_model_emission(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		var mat: Material = mesh_node.get_surface_override_material(0)
		if mat == null and mesh_node.mesh:
			mat = mesh_node.mesh.surface_get_material(0)
		if mat is StandardMaterial3D:
			var new_mat := mat.duplicate() as StandardMaterial3D
			new_mat.emission_enabled = color != Color.BLACK
			new_mat.emission = color
			new_mat.emission_energy_multiplier = 2.0 if color != Color.BLACK else 0.0
			mesh_node.set_surface_override_material(0, new_mat)
	for child in node.get_children():
		_set_model_emission(child, color)


## Spawn shock wave effect when landing after a jump
## Destroys trees, NPCs, buildings within radius
func _spawn_landing_shock_wave() -> void:
	# Stop slam flash effect
	if slam_flash_tween:
		slam_flash_tween.kill()
		slam_flash_tween = null
	if player_model:
		_set_model_emission(player_model, Color.BLACK)
	
	# Hide slam cone
	if slam_cone:
		slam_cone.visible = false
	if slam_cone_shake_tween:
		slam_cone_shake_tween.kill()
		slam_cone_shake_tween = null
	if slam_cone_grow_tween:
		slam_cone_grow_tween.kill()
		slam_cone_grow_tween = null
	
	# Spawn shock wave at player's position (slightly below for ground effect)
	var shock_position := global_position + Vector3(0, -sphere_radius * 0.5, 0)
	
	# Calculate radius multiplier based on state
	var radius_mult := 1.0
	var gm: Node = get_node_or_null("/root/GameManager")
	
	# Slam charged = 1.5x radius, supercharged = 2x, both = 3x
	if slam_charged:
		radius_mult *= 1.5
	if gm and gm.is_supercharged:
		radius_mult *= 2.0
	
	var final_radius := ShockWaveManager.SHOCK_WAVE_RADIUS * radius_mult
	ShockWaveManager.spawn_shock_wave(shock_position, ShockWaveManager.Source.PLAYER, final_radius)
	
	# Screen shake intensity based on slam
	var shake_intensity := 0.8
	if slam_charged:
		shake_intensity = 1.5
	
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("shake"):
		camera.shake(shake_intensity)
	
	# Reset slam state
	slam_charged = false


func die() -> void:
	if is_dead:
		return
	
	# Check if we're still in the scene tree
	if not is_inside_tree():
		return
	
	is_dead = true
	
	# Clean up edge warning effects
	_cleanup_edge_warnings()
	
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
	
	# Safety check - scene may have changed during await
	if not is_inside_tree():
		return
	
	# Now emit died signal and end game
	died.emit()
	if game_manager:
		game_manager.end_game()

func _on_body_entered(body: Node) -> void:
	if is_dead or hit_cooldown > 0:
		return
	
	# Check if we hit a building enemy (spikes, etc)
	if body.is_in_group("building_enemies"):
		# If supercharged, destroy the spike instead of taking damage
		if game_manager and game_manager.is_supercharged:
			# Spike's DamageArea will handle the destruction
			return
		
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
	
	# Clone from pre-created template instead of building from scratch
	if not _rock_impact_particle_template:
		return
	
	var particles := _rock_impact_particle_template.duplicate() as GPUParticles3D
	
	var scene_root := get_tree().current_scene
	if scene_root:
		scene_root.add_child(particles)
		particles.global_position = impact_pos
		particles.visible = true
		particles.emitting = true
		
		get_tree().create_timer(2.0).timeout.connect(func():
			if is_instance_valid(particles):
				particles.queue_free()
		)


func _create_rock_impact_template() -> void:
	## Pre-create rock impact particle template for faster spawning
	_rock_impact_particle_template = GPUParticles3D.new()
	_rock_impact_particle_template.name = "RockImpactTemplate"
	_rock_impact_particle_template.one_shot = true
	_rock_impact_particle_template.explosiveness = 0.95
	_rock_impact_particle_template.amount = 25
	_rock_impact_particle_template.lifetime = 0.8
	_rock_impact_particle_template.visible = false  # Hidden template
	_rock_impact_particle_template.emitting = false
	
	var proc_material := ParticleProcessMaterial.new()
	proc_material.direction = Vector3(0, 1, 0)
	proc_material.spread = 80.0
	proc_material.initial_velocity_min = 4.0
	proc_material.initial_velocity_max = 10.0
	proc_material.gravity = Vector3(0, -15, 0)
	proc_material.scale_min = 0.05
	proc_material.scale_max = 0.12
	proc_material.color = Color(0.5, 0.45, 0.4)  # Gray rock color
	_rock_impact_particle_template.process_material = proc_material
	
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = Color(0.5, 0.45, 0.4)
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_material
	_rock_impact_particle_template.draw_pass_1 = mesh
	
	# Add to scene but keep hidden
	add_child(_rock_impact_particle_template)

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
	dust_particles.amount = 30
	dust_particles.lifetime = 0.8
	dust_particles.explosiveness = 0.0
	dust_particles.emitting = false
	
	var proc_mat := ParticleProcessMaterial.new()
	proc_mat.direction = Vector3(0, 1, 0)  # Upward
	proc_mat.spread = 60.0
	proc_mat.initial_velocity_min = 2.0
	proc_mat.initial_velocity_max = 4.0
	proc_mat.gravity = Vector3(0, -3, 0)
	proc_mat.scale_min = 0.15
	proc_mat.scale_max = 0.35
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


## Setup slam cone effect (comet/meteor trail when charging slam)
func _setup_slam_cone() -> void:
	slam_cone = MeshInstance3D.new()
	slam_cone.name = "SlamCone"
	
	# Create cone mesh (cylinder with top radius = 0)
	slam_cone_mesh = CylinderMesh.new()
	slam_cone_mesh.top_radius = 0.0
	slam_cone_mesh.bottom_radius = sphere_radius * 1.2  # Match player radius
	slam_cone_mesh.height = sphere_radius * 6.0  # Long cone trailing
	slam_cone_mesh.radial_segments = 16
	slam_cone_mesh.rings = 1
	
	# Transparent glowing material
	slam_cone_material = StandardMaterial3D.new()
	slam_cone_material.albedo_color = Color(1.0, 0.5, 0.2, 0.25)  # Orange, semi-transparent
	slam_cone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slam_cone_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	slam_cone_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from inside too
	slam_cone_material.emission_enabled = true
	slam_cone_material.emission = Color(1.0, 0.4, 0.1)  # Warm glow
	slam_cone_material.emission_energy_multiplier = 1.5
	slam_cone_mesh.material = slam_cone_material
	
	slam_cone.mesh = slam_cone_mesh
	slam_cone.visible = false  # Hidden until slam charged
	
	add_child(slam_cone)
	slam_cone.top_level = true  # Don't inherit rotation from player
	slam_cone.global_position = global_position + Vector3(0, slam_cone_mesh.height * 0.5, 0)

func _start_cone_shake() -> void:
	if slam_cone_shake_tween:
		slam_cone_shake_tween.kill()
	
	slam_cone_shake_tween = create_tween()
	slam_cone_shake_tween.set_loops()
	
	# Shake by randomly offsetting position slightly
	slam_cone_shake_tween.tween_callback(_shake_cone_step)
	slam_cone_shake_tween.tween_interval(0.03)

func _shake_cone_step() -> void:
	if slam_cone and slam_cone.visible:
		_update_cone_position()

func _update_cone_position() -> void:
	if not slam_cone or not slam_cone_mesh:
		return
	
	# Update cone dimensions based on current player scale and grow progress
	var current_radius := sphere_radius * supercharge_current_scale
	var max_height := current_radius * 6.0
	var min_height := current_radius * 0.5  # Start from small
	var current_height := lerpf(min_height, max_height, slam_cone_grow_progress)
	
	slam_cone_mesh.bottom_radius = current_radius * 1.2  # Match player radius
	slam_cone_mesh.height = current_height
	
	# Update opacity - higher in supercharge mode
	if slam_cone_material:
		var base_opacity := 0.25
		if is_supercharged:
			base_opacity = 0.45  # More visible in supercharge
		slam_cone_material.albedo_color.a = base_opacity
		slam_cone_material.emission_energy_multiplier = 1.5 if not is_supercharged else 2.5
	
	var cone_height: float = slam_cone_mesh.height
	var shake_x := randf_range(-0.1, 0.1)
	var shake_z := randf_range(-0.1, 0.1)
	var shake := Vector3(shake_x, 0, shake_z)
	
	# Get velocity direction
	var vel := linear_velocity
	if vel.length_squared() > 0.1:
		# Cone trails opposite to velocity, but biased upward for visibility
		var trail_dir := -vel.normalized()
		# Bias tip direction towards up so cone is more visible from camera
		var up_bias := Vector3.UP * 0.6
		var tip_dir := (trail_dir + up_bias).normalized()
		
		# Create rotation: align local +Y with tip_dir
		var default_up := Vector3.UP
		var rotation_quat := Quaternion(default_up, tip_dir)
		slam_cone.global_transform.basis = Basis(rotation_quat)
		
		# Position: base at player center, tip extends along tip_dir
		slam_cone.global_position = global_position + tip_dir * cone_height * 0.5 + shake
	else:
		# No velocity, cone points up (default)
		slam_cone.global_transform.basis = Basis.IDENTITY
		slam_cone.global_position = global_position + Vector3(0, cone_height * 0.5, 0) + shake


## Setup atmospheric particles (snow/dust floating in air around player)
func _setup_atmosphere_particles() -> void:
	atmosphere_particles = GPUParticles3D.new()
	atmosphere_particles.name = "AtmosphereParticles"
	atmosphere_particles.amount = 120
	atmosphere_particles.lifetime = 2.0
	atmosphere_particles.explosiveness = 0.0
	atmosphere_particles.randomness = 1.0
	atmosphere_particles.emitting = true
	atmosphere_particles.local_coords = true  # Stay relative to emitter
	atmosphere_particles.visibility_aabb = AABB(Vector3(-25, -10, -30), Vector3(50, 20, 60))
	
	atmosphere_proc_mat = ParticleProcessMaterial.new()
	# Emit from large box around player
	atmosphere_proc_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	atmosphere_proc_mat.emission_box_extents = Vector3(18, 8, 15)
	
	# Base motion - will be modified by velocity
	atmosphere_proc_mat.direction = Vector3(0, 0, 1)  # Toward camera
	atmosphere_proc_mat.spread = 45.0
	atmosphere_proc_mat.initial_velocity_min = 1.0
	atmosphere_proc_mat.initial_velocity_max = 3.0
	atmosphere_proc_mat.gravity = Vector3(0, 0, 5.0)  # Base towards camera
	
	# Small scale for subtle particles
	atmosphere_proc_mat.scale_min = 0.05
	atmosphere_proc_mat.scale_max = 0.1
	
	# White/light blue color with subtle fade
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(1.0, 1.0, 1.0, 0.0))  # Fade in
	color_ramp.add_point(0.1, Color(0.95, 0.97, 1.0, 0.4))
	color_ramp.add_point(0.6, Color(0.9, 0.95, 1.0, 0.35))
	color_ramp.set_color(1, Color(0.9, 0.95, 1.0, 0.0))  # Fade out
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	atmosphere_proc_mat.color_ramp = color_tex
	
	atmosphere_particles.process_material = atmosphere_proc_mat
	
	# Simple quad mesh for snow flakes
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	var quad_mat := StandardMaterial3D.new()
	quad_mat.albedo_color = Color(1.0, 1.0, 1.0)
	quad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	quad_mat.vertex_color_use_as_albedo = true
	quad_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = quad_mat
	atmosphere_particles.draw_pass_1 = quad
	atmosphere_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(atmosphere_particles)
	atmosphere_particles.top_level = true  # Don't inherit rotation from player!
	atmosphere_particles.global_position = global_position + Vector3(0, 4, -8)


## Setup edge warning visual effect (red glow near terrain boundaries)
func _setup_edge_warning() -> void:
	## Create shared material for both warning walls
	edge_warning_material = StandardMaterial3D.new()
	edge_warning_material.albedo_color = Color(1.0, 0.0, 0.0, 0.0)  # Red, starts invisible
	edge_warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	edge_warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge_warning_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from both sides
	edge_warning_material.no_depth_test = false  # Proper depth testing for 3D feel
	edge_warning_material.render_priority = 5
	
	# Create left edge warning wall
	edge_warning_left = _create_edge_warning_mesh()
	edge_warning_left.name = "EdgeWarningLeft"
	get_tree().root.add_child(edge_warning_left)
	
	# Create right edge warning wall
	edge_warning_right = _create_edge_warning_mesh()
	edge_warning_right.name = "EdgeWarningRight"
	get_tree().root.add_child(edge_warning_right)


func _create_edge_warning_mesh() -> MeshInstance3D:
	## Create a tall vertical wall mesh for edge warning (3D barrier effect)
	var mesh_instance := MeshInstance3D.new()
	
	# Create a box mesh that looks like a glowing wall section
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 12.0, 40.0)  # Thin (0.3m), tall (12m), long (40m along Z)
	
	mesh_instance.mesh = box
	mesh_instance.material_override = edge_warning_material
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visible = false  # Start hidden
	
	return mesh_instance


func _update_edge_warning() -> void:
	## Update edge warning visibility based on player proximity to edges
	if not edge_warning_left or not edge_warning_right:
		return
	
	var player_x := global_position.x
	var player_y := global_position.y
	var player_z := global_position.z
	
	# Calculate distance to each edge
	var left_edge := -TERRAIN_HALF_WIDTH
	var right_edge := TERRAIN_HALF_WIDTH
	
	var dist_to_left := player_x - left_edge  # Positive when inside terrain
	var dist_to_right := right_edge - player_x  # Positive when inside terrain
	
	# Left edge warning
	if dist_to_left < EDGE_WARNING_DISTANCE and dist_to_left > 0:
		var intensity := 1.0 - (dist_to_left / EDGE_WARNING_DISTANCE)
		intensity = intensity * intensity  # Quadratic falloff (more intense closer to edge)
		_show_edge_warning(edge_warning_left, left_edge, player_y, player_z, intensity, false)
	else:
		edge_warning_left.visible = false
	
	# Right edge warning
	if dist_to_right < EDGE_WARNING_DISTANCE and dist_to_right > 0:
		var intensity := 1.0 - (dist_to_right / EDGE_WARNING_DISTANCE)
		intensity = intensity * intensity  # Quadratic falloff
		_show_edge_warning(edge_warning_right, right_edge, player_y, player_z, intensity, true)
	else:
		edge_warning_right.visible = false


func _show_edge_warning(warning: MeshInstance3D, edge_x: float, player_y: float, player_z: float, intensity: float, is_right: bool) -> void:
	## Position and show edge warning wall at the actual barrier position
	warning.visible = true
	
	# Use player's Y position as reference (more reliable than calculating edge terrain height)
	# Box is 12m tall centered, so offset 0 puts center at player level
	# This ensures the warning is always visible at the player's horizon
	warning.global_position = Vector3(edge_x, player_y, player_z - 15.0)
	
	# Rotate to match slope angle (tilted downhill - negative X rotation)
	var slope_radians := deg_to_rad(terrain_slope)
	warning.rotation = Vector3(-slope_radians, 0.0, 0.0)  # Tilt down to match slope
	
	# Update material opacity and color based on intensity
	var alpha := clampf(intensity * 0.6, 0.0, 0.6)  # Max 60% opacity
	# Gradient from orange (far) to red (close)
	var red := 1.0
	var green := 0.3 * (1.0 - intensity)  # More orange when further
	edge_warning_material.albedo_color = Color(red, green, 0.0, alpha)


func _cleanup_edge_warnings() -> void:
	## Remove edge warning meshes from scene (they're added to root, not player)
	if edge_warning_left and is_instance_valid(edge_warning_left):
		edge_warning_left.queue_free()
		edge_warning_left = null
	if edge_warning_right and is_instance_valid(edge_warning_right):
		edge_warning_right.queue_free()
		edge_warning_right = null


func _exit_tree() -> void:
	## Clean up edge warnings when player is removed from scene
	_cleanup_edge_warnings()

# ========== Supercharge System ==========

func _on_supercharge_activated() -> void:
	is_supercharged = true
	supercharge_scale_target = SUPERCHARGE_SCALE_MULTIPLIER
	
	# Apply speed and jump bonuses
	forward_force = base_forward_force * SUPERCHARGE_SPEED_BONUS
	jump_force = base_jump_force * SUPERCHARGE_JUMP_BONUS
	max_speed = base_max_speed * SUPERCHARGE_SPEED_BONUS
	
	# Show pre-created effects (no lag since already created)
	if supercharge_glow:
		supercharge_glow.visible = true
		supercharge_glow.light_energy = 4.0  # Boost glow
	if supercharge_particles:
		supercharge_particles.visible = true
		supercharge_particles.emitting = true
	if supercharge_trail:
		supercharge_trail.visible = true
		supercharge_trail.emitting = true

func _on_supercharge_ended() -> void:
	is_supercharged = false
	supercharge_scale_target = 1.0
	
	# Restore normal values
	forward_force = base_forward_force
	jump_force = base_jump_force
	max_speed = base_max_speed
	
	# Hide effects (don't destroy, keep for next supercharge)
	if supercharge_glow:
		supercharge_glow.visible = false
		supercharge_glow.light_energy = 3.0  # Reset
	if supercharge_particles:
		supercharge_particles.emitting = false
		supercharge_particles.visible = false
	if supercharge_trail:
		supercharge_trail.emitting = false
		supercharge_trail.visible = false
	if supercharge_particles:
		supercharge_particles.emitting = false
		supercharge_particles.visible = false

func _update_supercharge_scale(delta: float) -> void:
	if absf(supercharge_current_scale - supercharge_scale_target) < 0.01:
		supercharge_current_scale = supercharge_scale_target
		return
	
	var old_scale := supercharge_current_scale
	
	# Smoothly interpolate scale
	var scale_speed: float = (SUPERCHARGE_SCALE_MULTIPLIER - 1.0) / SUPERCHARGE_SCALE_DURATION
	if supercharge_current_scale < supercharge_scale_target:
		supercharge_current_scale = minf(supercharge_current_scale + scale_speed * delta, supercharge_scale_target)
	else:
		supercharge_current_scale = maxf(supercharge_current_scale - scale_speed * delta, supercharge_scale_target)
	
	# Calculate height difference to lift player appropriately
	var old_radius := sphere_radius * old_scale
	var new_radius := sphere_radius * supercharge_current_scale
	var height_diff := new_radius - old_radius
	
	# Lift extra to compensate for terrain slope (sin of slope angle) and prevent clipping
	# Add 50% more lift when growing to compensate for sloped terrain
	if supercharge_current_scale > old_scale:
		height_diff *= 1.5
	
	# Lift the player so it doesn't clip into terrain
	global_position.y += height_diff
	
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
	supercharge_glow.visible = false  # Start hidden
	add_child(supercharge_glow)

func _create_supercharge_glow_mesh() -> void:
	pass  # Deprecated - using particles instead

## Pre-create supercharge effects (hidden) to avoid lag on first activation
func _precreate_supercharge_effects() -> void:
	_create_supercharge_glow()
	_create_supercharge_particles()
	_create_supercharge_trail()

func _create_supercharge_particles() -> void:
	if supercharge_particles:
		return
	
	# Create particle system that emits glowing particles around the player
	supercharge_particles = GPUParticles3D.new()
	supercharge_particles.name = "SuperchargeParticles"
	supercharge_particles.amount = 40
	supercharge_particles.lifetime = 0.8
	supercharge_particles.explosiveness = 0.0
	supercharge_particles.randomness = 0.3
	supercharge_particles.one_shot = false
	supercharge_particles.visible = false  # Start hidden
	supercharge_particles.emitting = false  # Don't emit until activated
	
	# Configure particle behavior - emit from sphere surface, drift upward
	var proc_material := ParticleProcessMaterial.new()
	proc_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE
	proc_material.emission_sphere_radius = sphere_radius * 1.5
	proc_material.direction = Vector3(0, 1, 0)
	proc_material.spread = 30.0
	proc_material.initial_velocity_min = 0.5
	proc_material.initial_velocity_max = 1.5
	proc_material.gravity = Vector3(0, 0.5, 0)  # Float up slowly
	proc_material.scale_min = 0.18  # 20% larger (was 0.15)
	proc_material.scale_max = 0.42  # 20% larger (was 0.35)
	
	# Color gradient from bright red/orange to transparent
	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(1.0, 0.4, 0.1, 1.0))
	color_ramp.add_point(0.5, Color(1.0, 0.2, 0.05, 0.8))
	color_ramp.add_point(1.0, Color(1.0, 0.1, 0.0, 0.0))
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = color_ramp
	proc_material.color_ramp = gradient_texture
	
	supercharge_particles.process_material = proc_material
	
	# Create glowing quad mesh for particles
	var quad := QuadMesh.new()
	quad.size = Vector2(0.25, 0.25)
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	
	supercharge_particles.draw_pass_1 = quad
	supercharge_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	add_child(supercharge_particles)
	# Don't emit yet - will start when supercharge activates

## Create intense fire trail that streams behind the player during supercharge
func _create_supercharge_trail() -> void:
	if supercharge_trail:
		return
	
	supercharge_trail = GPUParticles3D.new()
	supercharge_trail.name = "SuperchargeTrail"
	supercharge_trail.amount = 200
	supercharge_trail.lifetime = 1.2
	supercharge_trail.explosiveness = 0.0
	supercharge_trail.randomness = 0.2
	supercharge_trail.one_shot = false
	supercharge_trail.visible = false  # Start hidden
	supercharge_trail.emitting = false
	supercharge_trail.trail_enabled = true
	supercharge_trail.trail_lifetime = 0.3
	
	# Configure trail to emit behind and upward
	var proc_material := ParticleProcessMaterial.new()
	proc_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc_material.emission_box_extents = Vector3(sphere_radius * 1.2, 0.4, 0.3)
	proc_material.direction = Vector3(0, 0.8, 1.0)  # Backward and up
	proc_material.spread = 25.0
	proc_material.initial_velocity_min = 4.0
	proc_material.initial_velocity_max = 8.0
	proc_material.gravity = Vector3(0, 2.0, 3.0)  # Rise up and trail back
	proc_material.scale_min = 0.3
	proc_material.scale_max = 0.6
	proc_material.damping_min = 1.0
	proc_material.damping_max = 2.0
	
	# Vibrant fire color gradient
	var color_ramp := Gradient.new()
	color_ramp.add_point(0.0, Color(1.0, 1.0, 0.5, 1.0))  # Bright yellow-white core
	color_ramp.add_point(0.2, Color(1.0, 0.6, 0.1, 1.0))  # Orange
	color_ramp.add_point(0.5, Color(1.0, 0.3, 0.0, 0.9))  # Red-orange
	color_ramp.add_point(0.8, Color(0.8, 0.1, 0.0, 0.5))  # Dark red
	color_ramp.add_point(1.0, Color(0.3, 0.0, 0.0, 0.0))  # Fade to transparent
	var gradient_texture := GradientTexture1D.new()
	gradient_texture.gradient = color_ramp
	proc_material.color_ramp = gradient_texture
	
	# Scale curve - start big, get smaller
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.3, 0.8))
	scale_curve.add_point(Vector2(1.0, 0.2))
	var scale_curve_tex := CurveTexture.new()
	scale_curve_tex.curve = scale_curve
	proc_material.scale_curve = scale_curve_tex
	
	supercharge_trail.process_material = proc_material
	
	# Create glowing quad mesh for trail particles
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 5.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	quad.material = mat
	
	supercharge_trail.draw_pass_1 = quad
	supercharge_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Position trail at the back of the player
	supercharge_trail.position = Vector3(0, 0, sphere_radius * 0.5)
	add_child(supercharge_trail)

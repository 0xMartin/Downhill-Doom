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
	var keyboard_input: float = 0.0
	if Input.is_action_pressed("move_left") or Input.is_action_pressed("ui_left"):
		keyboard_input = 1.0
	if Input.is_action_pressed("move_right") or Input.is_action_pressed("ui_right"):
		keyboard_input = -1.0
	
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
	
	# Update rolling sound pitch based on speed
	if audio_manager:
		var speed_ratio := current_forward_speed / max_speed
		audio_manager.update_roll_pitch(speed_ratio)
	
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

func die() -> void:
	if is_dead:
		return
	
	is_dead = true
	
	# Stop rolling sound
	if audio_manager:
		audio_manager.stop_roll_sound()
		audio_manager.play_death_sound()
	
	# Freeze physics immediately
	freeze = true
	
	# Spawn explosion particles at player position
	var explosion_scene := preload("res://scenes/explosion_effect.tscn")
	var explosion := explosion_scene.instantiate()
	explosion.global_position = global_position
	get_tree().current_scene.add_child(explosion)
	
	# Hide the ball
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
	
	# Check if we hit a rock (in "rocks" group or name starts with "Rock")
	if body.is_in_group("rocks") or (body is StaticBody3D and body.name.begins_with("Rock")):
		hit_cooldown = 0.5  # Prevent rapid hits
		
		# Calculate impact position
		var impact_pos := global_position
		
		# Emit signal for effects (camera shake, red flash)
		hit_rock.emit(impact_pos)
		
		# Spawn impact particles
		_spawn_rock_impact_particles(impact_pos)
		
		# Play hurt sound
		if audio_manager:
			audio_manager.play_hurt_sound()
		
		# Take damage
		if game_manager:
			game_manager.take_damage(rock_damage)

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
		particles.global_position = impact_pos
		scene_root.add_child(particles)
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

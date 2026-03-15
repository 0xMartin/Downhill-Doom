extends Node3D
class_name WizardSpell
## Wizard's magic spell projectile - homing, purple, causes blindness
## Stays at terrain height - player can dodge by jumping
## On hit: damage + blindness effect (fog)

const TRAIL_LENGTH: int = 20
const PROJECTILE_RADIUS: float = 0.35
const PROJECTILE_COLOR := Color(0.6, 0.0, 0.9, 1.0)  # Bright purple
const GLOW_COLOR := Color(0.8, 0.3, 1.0, 0.6)  # Light purple glow
const TRAIL_COLOR := Color(0.5, 0.0, 0.8, 0.8)  # Purple trail
const HOMING_STRENGTH: float = 4.0  # How strongly it tracks player
const MIN_TERRAIN_HEIGHT: float = 1.5  # Height above terrain
const HIT_RADIUS: float = 1.8  # Collision radius with player

var velocity: Vector3 = Vector3.ZERO
var speed: float = 23.4 
var damage: int = 22
var shooter: Node3D = null
var target: Node3D = null
var lifetime: float = 4.0
var time_alive: float = 0.0
var ground_level: float = 0.0  # Y level of ground at spawn

# Blindness settings
var blindness_duration: float = 5.0
var blindness_fog_begin: float = 0.0
var blindness_fog_end: float = 40.0

# Trail
var trail_points: Array[Vector3] = []
var trail_mesh_instance: MeshInstance3D

# Ball
var ball_mesh: MeshInstance3D
var glow_mesh: MeshInstance3D

# Particles
var magic_particles: GPUParticles3D


func _ready() -> void:
	add_to_group("wizard_spells")
	_create_ball()
	_create_glow()
	_create_trail()
	_create_particles()


func _create_ball() -> void:
	## Create the main spell ball (bright purple)
	ball_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = PROJECTILE_RADIUS
	sphere.height = PROJECTILE_RADIUS * 2
	sphere.radial_segments = 16
	sphere.rings = 8
	ball_mesh.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PROJECTILE_COLOR
	mat.emission_enabled = true
	mat.emission = PROJECTILE_COLOR
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_mesh.material_override = mat
	add_child(ball_mesh)


func _create_glow() -> void:
	## Create outer glow effect
	glow_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = PROJECTILE_RADIUS * 2.0
	sphere.height = PROJECTILE_RADIUS * 4.0
	sphere.radial_segments = 12
	sphere.rings = 6
	glow_mesh.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = GLOW_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	glow_mesh.material_override = mat
	add_child(glow_mesh)


func _create_trail() -> void:
	## Create trailing effect
	trail_mesh_instance = MeshInstance3D.new()
	trail_mesh_instance.name = "Trail"
	add_child(trail_mesh_instance)


func _create_particles() -> void:
	## Create magical sparkle particles
	magic_particles = GPUParticles3D.new()
	magic_particles.name = "MagicParticles"
	magic_particles.amount = 10
	magic_particles.lifetime = 0.4
	magic_particles.explosiveness = 0.0
	magic_particles.emitting = true
	
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3(0, 0, 1)
	mat.spread = 180.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 2.0
	mat.gravity = Vector3(0, 0, 0)
	mat.scale_min = 0.05
	mat.scale_max = 0.12
	mat.color = Color(0.8, 0.4, 1.0, 1.0)
	magic_particles.process_material = mat
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	mesh.radial_segments = 6
	mesh.rings = 4
	magic_particles.draw_pass_1 = mesh
	
	add_child(magic_particles)


func _process(delta: float) -> void:
	time_alive += delta
	
	# Check lifetime
	if time_alive >= lifetime:
		_destroy()
		return
	
	# Update target reference if lost
	if not target or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player") as Node3D
	
	# Homing behavior (only horizontal)
	if target and is_instance_valid(target):
		var target_pos := target.global_position
		target_pos.y = global_position.y  # Ignore target Y for homing
		
		var to_target := target_pos - global_position
		to_target.y = 0  # Enforce horizontal only
		
		if to_target.length() > 0.1:
			var desired_dir := to_target.normalized()
			var current_dir := velocity.normalized()
			if current_dir.length() < 0.1:
				current_dir = desired_dir
			
			# Smooth turning towards target
			var new_dir := current_dir.lerp(desired_dir, HOMING_STRENGTH * delta)
			new_dir.y = 0  # Enforce horizontal
			if new_dir.length() > 0.1:
				new_dir = new_dir.normalized()
				velocity = new_dir * speed
	
	# Ensure velocity has no Y component
	velocity.y = 0
	
	# Move horizontally
	global_position += velocity * delta
	
	# Find terrain height below spell via raycast and stay above it
	var terrain_y := _get_terrain_height()
	global_position.y = terrain_y + MIN_TERRAIN_HEIGHT
	
	# Add trail point
	trail_points.insert(0, global_position)
	if trail_points.size() > TRAIL_LENGTH:
		trail_points.resize(TRAIL_LENGTH)
	
	# Update trail mesh
	_update_trail_mesh()
	
	# Pulse glow effect
	if glow_mesh and glow_mesh.material_override:
		var pulse := 0.6 + 0.4 * sin(time_alive * 8.0)
		(glow_mesh.material_override as StandardMaterial3D).albedo_color.a = GLOW_COLOR.a * pulse
	
	# Check player collision
	_check_player_collision()


func _check_player_collision() -> void:
	## Check if spell hit the player
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if not player:
		return
	
	var dist := global_position.distance_to(player.global_position)
	
	# Get current terrain height at spell position
	var terrain_y := _get_terrain_height()
	var player_y := player.global_position.y
	var player_height_above_terrain := player_y - terrain_y
	
	# Only hit if player is close to ground (not jumping high above terrain)
	if dist < HIT_RADIUS and player_height_above_terrain < 2.5:
		_on_hit_player(player)


func _on_hit_player(player_node: Node) -> void:
	## Spell hit the player - deal damage and apply blindness (only if not supercharged)
	var gm := get_node_or_null("/root/GameManager")
	var audio := get_node_or_null("/root/AudioManager")
	
	if gm:
		# Only apply damage and blindness if not in supercharge mode
		if not gm.is_supercharged:
			if audio and audio.has_method("play_hurt_sound"):
				audio.play_hurt_sound()
			gm.take_damage(damage)
			gm.apply_blindness(blindness_duration, blindness_fog_begin, blindness_fog_end)
	
	# Create impact effect
	_create_impact_effect()
	
	_destroy()


func _create_impact_effect() -> void:
	## Create a brief purple flash/explosion effect
	var impact := GPUParticles3D.new()
	impact.amount = 20
	impact.lifetime = 0.5
	impact.explosiveness = 1.0
	impact.one_shot = true
	impact.emitting = true
	
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.5
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 6.0
	mat.gravity = Vector3(0, -5, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.25
	mat.color = Color(0.8, 0.3, 1.0, 1.0)
	impact.process_material = mat
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	impact.draw_pass_1 = mesh
	
	impact.global_position = global_position
	get_tree().root.add_child(impact)
	
	# Auto-destroy impact particles
	var timer := get_tree().create_timer(1.0)
	timer.timeout.connect(func(): if is_instance_valid(impact): impact.queue_free())


func _update_trail_mesh() -> void:
	## Update the trailing ribbon mesh
	if trail_points.size() < 2:
		return
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	
	var cam_pos := camera.global_position
	
	for i in range(trail_points.size()):
		var point := trail_points[i]
		var alpha: float = 1.0 - (float(i) / float(trail_points.size()))
		var width: float = PROJECTILE_RADIUS * alpha
		
		var to_cam := (cam_pos - point).normalized()
		var forward: Vector3
		
		if i < trail_points.size() - 1:
			forward = (trail_points[i] - trail_points[i + 1]).normalized()
		else:
			forward = velocity.normalized()
		
		var right := forward.cross(to_cam).normalized() * width
		
		if right.length() < 0.001:
			right = Vector3.RIGHT * width
		
		var color := TRAIL_COLOR
		color.a *= alpha
		st.set_color(color)
		
		st.add_vertex(point + right)
		st.add_vertex(point - right)
	
	trail_mesh_instance.mesh = st.commit()
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_mesh_instance.material_override = mat


func _get_terrain_height() -> float:
	## Raycast down to find terrain height below the spell
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return ground_level  # Fallback
	
	var ray_origin := global_position + Vector3(0, 10, 0)  # Start above
	var ray_end := global_position + Vector3(0, -50, 0)  # End below
	
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Terrain layer
	query.exclude = []  # Don't exclude anything
	
	var result := space_state.intersect_ray(query)
	if result:
		return result.position.y
	
	return ground_level  # Fallback if no hit


func _destroy() -> void:
	## Clean up and remove spell
	queue_free()

extends RigidBody3D
## Destructible tree - falls over when hit by player and awards coin
## Uses Area3D child for non-blocking collision detection

@export var fall_torque: float = 50.0
@export var coin_value: int = 1

var is_fallen := false

func _ready() -> void:
	# Start as static (frozen) - will unfreeze when hit
	freeze = true
	add_to_group("trees")
	
	# Find and connect to DetectArea child (created by terrain_generator)
	await get_tree().process_frame  # Wait for children to be ready
	var detect_area := get_node_or_null("DetectArea") as Area3D
	if detect_area:
		detect_area.body_entered.connect(_on_detect_area_body_entered)

func _on_detect_area_body_entered(body: Node) -> void:
	if is_fallen:
		return
	
	if body.is_in_group("player"):
		# Get player's velocity to determine fall direction
		var player_velocity := Vector3.FORWARD
		if body is RigidBody3D:
			player_velocity = body.linear_velocity
		fall(player_velocity)

func fall(player_velocity: Vector3) -> void:
	if is_fallen:
		return
	
	is_fallen = true
	
	# Play tree hit sound
	var audio = get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_tree_hit_sound()
	
	# Spawn particles at impact point
	_spawn_fall_particles()
	
	# Calculate fall direction (forward in player's movement direction)
	var fall_direction := player_velocity.normalized()
	fall_direction.y = 0
	if fall_direction.length() < 0.1:
		fall_direction = Vector3(0, 0, -1)  # Default forward
	fall_direction = fall_direction.normalized()
	
	# Instead of physics, use a tween to animate the tree toppling
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Calculate rotation axis (perpendicular to fall direction)
	var rotation_axis := fall_direction.cross(Vector3.UP).normalized()
	
	# Current rotation
	var start_rotation := rotation
	
	# Target rotation - rotate 90 degrees around the axis
	# We need to rotate around the local X axis (pitch forward)
	var target_angle := -PI / 2  # 90 degrees forward
	
	# Animate rotation - tree tips over
	tween.tween_property(self, "rotation:x", rotation.x + target_angle, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# Move slightly in fall direction and down
	var target_pos := position + fall_direction * 2.0 + Vector3(0, -1.5, 0)
	tween.tween_property(self, "position", target_pos, 0.8).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# Award coin
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
	
	# Remove after delay
	await tween.finished
	await get_tree().create_timer(2.0).timeout
	queue_free()

func _spawn_fall_particles() -> void:
	# Check if we're in the scene tree before spawning
	if not is_inside_tree():
		return
	
	# Create simple particle effect - spawn at global position, not as child
	# (because tree is scaled down, child particles would be tiny)
	var particles := GPUParticles3D.new()
	particles.name = "FallParticles"
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.amount = 20
	particles.lifetime = 1.2
	
	# Create particle material
	var proc_material := ParticleProcessMaterial.new()
	proc_material.direction = Vector3(0, 1, 0)
	proc_material.spread = 70.0
	proc_material.initial_velocity_min = 3.0
	proc_material.initial_velocity_max = 7.0
	proc_material.gravity = Vector3(0, -12, 0)
	proc_material.scale_min = 0.08
	proc_material.scale_max = 0.15
	proc_material.color = Color(0.55, 0.4, 0.2)  # Brown/wood color
	particles.process_material = proc_material
	
	# Create visible mesh for particles with material
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 1.0, 1.0)  # Base size, scaled by proc_material
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_color = Color(0.55, 0.4, 0.2)  # Brown wood
	mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mesh_material
	particles.draw_pass_1 = mesh
	
	# Add to scene root at global position (not as child - tree is scaled)
	var scene_root := get_tree().current_scene
	if scene_root:
		var spawn_pos := global_position + Vector3(0, 0.5, 0)
		scene_root.add_child(particles)
		particles.global_position = spawn_pos
		particles.emitting = true
		
		# Auto-remove particles after they finish
		get_tree().create_timer(2.5).timeout.connect(func(): 
			if is_instance_valid(particles):
				particles.queue_free()
		)

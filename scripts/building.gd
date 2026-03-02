extends RigidBody3D
## Destructible building - collapses when hit by player and awards coins
## Similar to tree.gd but with different coin values and destruction animation

@export var fall_torque: float = 40.0
@export var coin_value: int = 20  # Default: 20 coins per building
@export var building_name: String = "Building"

var is_destroyed := false

func _ready() -> void:
	# Start as static (frozen) - will animate destruction when hit
	freeze = true
	add_to_group("buildings")
	
	# Find and connect to DetectArea child (created by object_spawner)
	await get_tree().process_frame  # Wait for children to be ready
	var detect_area := get_node_or_null("DetectArea") as Area3D
	if detect_area:
		detect_area.body_entered.connect(_on_detect_area_body_entered)

func _on_detect_area_body_entered(body: Node) -> void:
	if is_destroyed:
		return
	
	if body.is_in_group("player"):
		# Get player's velocity to determine fall direction
		var player_velocity := Vector3.FORWARD
		if body is RigidBody3D:
			player_velocity = body.linear_velocity
		destroy(player_velocity)

func destroy(player_velocity: Vector3) -> void:
	if is_destroyed:
		return
	
	is_destroyed = true
	
	# Store position before doing anything else
	var spawn_pos := global_position
	
	# Play destruction sound (use tree sound for now)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_tree_hit_sound()  # TODO: Add building destruction sound
	
	# Spawn destruction particles
	_spawn_destruction_particles(spawn_pos)
	
	# Calculate fall direction
	var fall_direction := player_velocity.normalized()
	fall_direction.y = 0
	if fall_direction.length() < 0.1:
		fall_direction = Vector3(0, 0, -1)
	fall_direction = fall_direction.normalized()
	
	# Animate destruction - building tips and collapses
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Rotate forward (tip over)
	var target_angle := -PI / 2.5  # Less than 90 degrees
	tween.tween_property(self, "rotation:x", rotation.x + target_angle, 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# Move in fall direction and down
	var target_pos := position + fall_direction * 1.5 + Vector3(0, -1.0, 0)
	tween.tween_property(self, "position", target_pos, 0.6).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# Scale down slightly (crushing effect)
	tween.tween_property(self, "scale", scale * 0.8, 0.6).set_ease(Tween.EASE_IN)
	
	# Award coins
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
	
	# Remove after delay
	await tween.finished
	await get_tree().create_timer(1.5).timeout
	queue_free()

func _spawn_destruction_particles(spawn_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	
	var particles := GPUParticles3D.new()
	particles.name = "DestructionParticles"
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = 30
	particles.lifetime = 1.5
	
	var proc_material := ParticleProcessMaterial.new()
	proc_material.direction = Vector3(0, 1, 0)
	proc_material.spread = 45.0
	proc_material.initial_velocity_min = 3.0
	proc_material.initial_velocity_max = 6.0
	proc_material.gravity = Vector3(0, -12, 0)
	proc_material.scale_min = 0.1
	proc_material.scale_max = 0.3
	proc_material.color = Color(0.6, 0.5, 0.4)  # Brown/wood color
	particles.process_material = proc_material
	
	# Simple mesh for particles
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.15, 0.15, 0.15)
	particles.draw_pass_1 = mesh
	
	# Set position BEFORE adding to tree (use position, not global_position)
	particles.position = spawn_pos + Vector3(0, 1.0, 0)
	scene_root.add_child(particles)
	
	# Auto-cleanup
	var cleanup_timer := get_tree().create_timer(2.0)
	cleanup_timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)

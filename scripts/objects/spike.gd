extends StaticBody3D
## Spike enemy - damages player on contact, cannot be destroyed
## Uses Area3D for damage detection, StaticBody3D for collision

@export var damage: int = 15
@export var damage_cooldown: float = 1.0  # Time before can damage again
@export var object_id: String = "enemy_unknown"
@export var object_name: String = "Enemy"

var can_damage := true

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("spikes")
	
	# Connect damage area
	await get_tree().process_frame
	var damage_area := get_node_or_null("DamageArea") as Area3D
	if damage_area:
		damage_area.body_entered.connect(_on_damage_area_body_entered)

func _on_damage_area_body_entered(body: Node) -> void:
	if not can_damage:
		return
	
	if body.is_in_group("player"):
		_deal_damage_to_player(body)

func _deal_damage_to_player(player: Node) -> void:
	can_damage = false
	
	# Store position before anything else
	var spawn_pos := global_position
	
	# Play hurt sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_hurt_sound()
	
	# Deal damage through GameManager
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.take_damage(damage)
	
	# Spawn impact effect
	_spawn_impact_particles(spawn_pos)
	
	# Start cooldown
	await get_tree().create_timer(damage_cooldown).timeout
	can_damage = true

func _spawn_impact_particles(spawn_pos: Vector3) -> void:
	if not is_inside_tree():
		return
	
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	
	var particles := GPUParticles3D.new()
	particles.name = "SpikeImpactParticles"
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 15
	particles.lifetime = 0.6
	
	var proc_material := ParticleProcessMaterial.new()
	proc_material.direction = Vector3(0, 1, 0)
	proc_material.spread = 60.0
	proc_material.initial_velocity_min = 2.0
	proc_material.initial_velocity_max = 4.0
	proc_material.gravity = Vector3(0, -15, 0)
	proc_material.scale_min = 0.05
	proc_material.scale_max = 0.1
	proc_material.color = Color(1.0, 0.2, 0.2)  # Red for damage
	particles.process_material = proc_material
	
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	particles.draw_pass_1 = mesh
	
	# Set position BEFORE adding to tree
	particles.position = spawn_pos + Vector3(0, 0.5, 0)
	scene_root.add_child(particles)
	
	var cleanup_timer := get_tree().create_timer(1.0)
	cleanup_timer.timeout.connect(func() -> void:
		if is_instance_valid(particles):
			particles.queue_free()
	)

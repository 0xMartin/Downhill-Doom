extends StaticBody3D
## Spike enemy - damages player on contact, cannot be destroyed UNLESS player is supercharged
## Uses Area3D for damage detection, StaticBody3D for collision

@export var damage: int = 15
@export var damage_cooldown: float = 1.0  # Time before can damage again
@export var object_id: String = "enemy_unknown"
@export var object_name: String = "Enemy"
@export var coin_value: int = 50  # Coins awarded when destroyed by supercharge

var can_damage := true
var is_destroyed := false

func _ready() -> void:
	add_to_group("building_enemies")
	add_to_group("spikes")
	
	# Connect damage area on next frame to ensure children are ready
	call_deferred("_connect_damage_area")

func _connect_damage_area() -> void:
	var damage_area := get_node_or_null("DamageArea") as Area3D
	if damage_area:
		if not damage_area.body_entered.is_connected(_on_damage_area_body_entered):
			damage_area.body_entered.connect(_on_damage_area_body_entered)

func _on_damage_area_body_entered(body: Node) -> void:
	if is_destroyed:
		return
	
	if body.is_in_group("player"):
		# Check if player is supercharged - if so, destroy the spike (ignores cooldown)
		var gm := get_node_or_null("/root/GameManager")
		if gm and gm.is_supercharged:
			_destroy_by_supercharge()
			return
		
		# Normal damage - respect cooldown
		if not can_damage:
			return
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
	
	# Start cooldown - with safety check after await
	await get_tree().create_timer(damage_cooldown).timeout
	if is_instance_valid(self) and is_inside_tree():
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

func _destroy_by_supercharge() -> void:
	is_destroyed = true
	
	# Disable collision immediately so player passes through
	collision_layer = 0
	collision_mask = 0
	var damage_area := get_node_or_null("DamageArea") as Area3D
	if damage_area:
		damage_area.set_deferred("monitoring", false)
	
	# Play destruction sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_tree_hit_sound()  # Reuse tree hit sound
	
	# Award coins and record stats BEFORE destruction
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
		gm.record_destroyed_object(object_id, object_name, coin_value)
	
	# Use DestructionManager to shatter (same as buildings)
	var destruction := get_node_or_null("/root/DestructionManager")
	if destruction:
		destruction.shatter(self, Vector3.FORWARD * 10.0, true)
	else:
		# Fallback: just remove the object
		queue_free()


## Called by ObjectPool when this object is retrieved from pool
func _pool_reset() -> void:
	# Re-add to groups (removed when pooled)
	add_to_group("building_enemies")
	add_to_group("spikes")
	# Reconnect signal (critical for collision to work after pooling)
	_connect_damage_area()
	# Re-enable damage area monitoring
	var damage_area := get_node_or_null("DamageArea") as Area3D
	if damage_area:
		damage_area.monitoring = true
	# Reset state
	is_destroyed = false
	can_damage = true
	collision_layer = 1
	collision_mask = 1

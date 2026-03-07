extends RigidBody3D
## Large building - only destructible when player is in supercharge mode
## Awards more coins and creates bigger destruction effect

@export var fall_torque: float = 60.0
@export var coin_value: int = 100  # Default: 100 coins per large building
@export var object_id: String = "building_large_unknown"
@export var object_name: String = "Large Building"

var is_destroyed := false
var gm: Node = null

func _ready() -> void:
	# Start as static (frozen) - will animate destruction when hit
	freeze = true
	add_to_group("buildings")
	add_to_group("large_buildings")
	
	# Cache GameManager reference
	gm = get_node_or_null("/root/GameManager")
	
	# Find and connect to DetectArea child (created by object_spawner)
	await get_tree().process_frame  # Wait for children to be ready
	var detect_area := get_node_or_null("DetectArea") as Area3D
	if detect_area:
		detect_area.body_entered.connect(_on_detect_area_body_entered)

func _physics_process(_delta: float) -> void:
	if is_destroyed:
		return
	
	# Dynamically toggle collision based on supercharge state
	# When supercharged, disable physical collision so player passes through
	if gm and gm.is_supercharged:
		if collision_layer != 0:
			collision_layer = 0
	else:
		if collision_layer != 1:
			collision_layer = 1

func _on_detect_area_body_entered(body: Node) -> void:
	if is_destroyed:
		return
	
	if body.is_in_group("player"):
		# Check if player is in supercharge mode
		var gm := get_node_or_null("/root/GameManager")
		if gm and gm.is_supercharged:
			# Get player's velocity to determine fall direction
			var player_velocity := Vector3.FORWARD
			if body is RigidBody3D:
				player_velocity = body.linear_velocity
			destroy(player_velocity)
		else:
			# Not supercharged - bounce player back slightly
			_bounce_player(body)

func _bounce_player(player: Node) -> void:
	if player is RigidBody3D:
		# Apply a small bounce impulse away from building
		var bounce_dir: Vector3 = (player.global_position - global_position).normalized()
		bounce_dir.y = 0.3  # Slight upward component
		player.apply_central_impulse(bounce_dir * 15.0)
		
		# Play impact sound
		var audio := get_node_or_null("/root/AudioManager")
		if audio:
			audio.play_hurt_sound()

func destroy(player_velocity: Vector3) -> void:
	if is_destroyed:
		return
	
	is_destroyed = true
	
	# Disable physical collision immediately so player passes through
	collision_layer = 0
	var phys_col := get_node_or_null("PhysicsCollision")
	if phys_col:
		phys_col.set_deferred("disabled", true)
	
	# Play destruction sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_building_hit_sound()
	
	# Award coins and record stats BEFORE destruction
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
		gm.record_destroyed_object(object_id, object_name, coin_value)
	
	# Use DestructionManager to shatter the building with bigger effect
	var destruction := get_node_or_null("/root/DestructionManager")
	if destruction:
		# Large buildings create more dramatic destruction
		destruction.shatter(self, player_velocity, true)
	else:
		# Fallback: just remove the object
		queue_free()


## Called by ObjectPool when this object is retrieved from pool
func _pool_reset() -> void:
	# Re-add to groups (removed when pooled)
	add_to_group("buildings")
	add_to_group("large_buildings")
	# Reset state
	is_destroyed = false
	freeze = true
	collision_layer = 1

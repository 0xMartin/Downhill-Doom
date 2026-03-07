extends RigidBody3D
## Destructible tree - falls over when hit by player and awards coin
## Uses Area3D child for non-blocking collision detection

@export var fall_torque: float = 50.0
@export var coin_value: int = 1
@export var object_id: String = "tree_unknown"
@export var object_name: String = "Tree"

var is_fallen := false

func _ready() -> void:
	# Start as static (frozen) - will unfreeze when hit
	freeze = true
	add_to_group("trees")
	
	# Connect detection area signal
	_connect_detect_area()


func _connect_detect_area() -> void:
	## Connect signal to detect area if not already connected
	var detect_area := get_node_or_null("DetectArea") as Area3D
	if detect_area:
		if detect_area.body_entered.is_connected(_on_detect_area_body_entered):
			return
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
	
	# Calculate fall direction (forward in player's movement direction)
	var fall_direction := player_velocity.normalized()
	fall_direction.y = 0
	if fall_direction.length() < 0.1:
		fall_direction = Vector3(0, 0, -1)  # Default forward
	fall_direction = fall_direction.normalized()
	
	# Calculate the angle to rotate the tree to face fall direction
	var fall_angle := atan2(fall_direction.x, fall_direction.z)
	
	# Instead of physics, use a tween to animate the tree toppling
	var tween := create_tween()
	tween.set_parallel(true)
	
	# First orient the tree to face the fall direction (instant or very fast)
	rotation.y = fall_angle
	
	# Target rotation - rotate 90 degrees forward (around local X axis after Y rotation)
	# Positive X rotation tips the tree forward in its facing direction
	var target_rotation_x := PI / 2  # 90 degrees tip forward
	
	# Animate rotation - tree tips over in the direction it's facing
	tween.tween_property(self, "rotation:x", target_rotation_x, 0.48).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# Move slightly in fall direction and down
	var target_pos := position + fall_direction * 2.0 + Vector3(0, -1.5, 0)
	tween.tween_property(self, "position", target_pos, 0.48).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	
	# Award coin and record stats
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
		gm.record_destroyed_object(object_id, object_name, coin_value)
	
	# Remove after delay (only if still in game world, not returned to pool)
	await tween.finished
	await get_tree().create_timer(2.0).timeout
	# Check if we're still in the game world (not returned to pool)
	if is_inside_tree() and get_parent() and not get_parent().name.begins_with("Pooled"):
		queue_free()


## Called by ObjectPool when this object is retrieved from pool
func _pool_reset() -> void:
	# Re-add to groups (removed when pooled)
	add_to_group("trees")
	# Reconnect signal (critical for collision to work after pooling)
	_connect_detect_area()
	# Reset state
	is_fallen = false
	freeze = true
	rotation = Vector3.ZERO

extends RigidBody3D
## Destructible building - collapses when hit by player and awards coins
## Similar to tree.gd but with different coin values and destruction animation

@export var fall_torque: float = 40.0
@export var coin_value: int = 20  # Default: 20 coins per building
@export var object_id: String = "building_unknown"
@export var object_name: String = "Building"

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
	
	# Play destruction sound (use tree sound for now)
	var audio := get_node_or_null("/root/AudioManager")
	if audio:
		audio.play_tree_hit_sound()  # TODO: Add building destruction sound
	
	# Award coins and record stats BEFORE destruction
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		gm.add_coin(coin_value)
		gm.record_destroyed_object(object_id, object_name, coin_value)
	
	# Use DestructionManager to shatter the building
	var destruction := get_node_or_null("/root/DestructionManager")
	if destruction:
		destruction.shatter(self, player_velocity, true)
	else:
		# Fallback: just remove the object
		queue_free()


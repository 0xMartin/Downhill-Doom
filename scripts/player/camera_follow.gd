extends Camera3D
## Smooth follow camera - tracks the player from behind and above with shake support

@export var target_path: NodePath  # Reference to the player
@export var offset: Vector3 = Vector3(0, 7, 8)  # Position offset (above and behind) - normal mode
@export var supercharge_offset: Vector3 = Vector3(0, 14, 16)  # Zoomed out for supercharge (2x)
@export var follow_speed: float = 5.0  # Smoothing factor
@export var look_ahead: float = 5.0  # How far ahead of player to look
@export var zoom_transition_speed: float = 3.0  # Speed of zoom in/out transition

var target: Node3D
var settings_manager: Node
var shake_intensity: float = 0.0
var shake_decay: float = 5.0
var is_following: bool = true  # Stop following when player dies
var current_offset: Vector3  # Current interpolated offset
var target_offset: Vector3  # Target offset (normal or supercharge)

func _ready() -> void:
	# Get SettingsManager reference
	settings_manager = get_node_or_null("/root/SettingsManager")
	
	# Initialize offsets
	current_offset = offset
	target_offset = offset
	
	if target_path:
		target = get_node(target_path)
	
	# Set initial position if target exists
	if target:
		global_position = target.global_position + offset
		# Connect to player died signal
		if target.has_signal("died"):
			target.died.connect(_on_player_died)
	
	# Connect to GameManager signals
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		if gm.has_signal("player_hit"):
			gm.player_hit.connect(_on_player_hit)
		if gm.has_signal("supercharge_activated"):
			gm.supercharge_activated.connect(_on_supercharge_activated)
		if gm.has_signal("supercharge_ended"):
			gm.supercharge_ended.connect(_on_supercharge_ended)

func _physics_process(delta: float) -> void:
	if not target or not is_following:
		return
	
	# Smoothly transition zoom (offset) for supercharge
	current_offset = current_offset.lerp(target_offset, zoom_transition_speed * delta)
	
	# Calculate desired camera position
	var target_pos := target.global_position
	var desired_position := target_pos + current_offset
	
	# Smoothly interpolate to desired position
	global_position = global_position.lerp(desired_position, follow_speed * delta)
	
	# Apply shake offset
	if shake_intensity > 0:
		var shake_offset := Vector3(
			randf_range(-1, 1) * shake_intensity,
			randf_range(-1, 1) * shake_intensity,
			randf_range(-1, 1) * shake_intensity * 0.5
		)
		global_position += shake_offset
		shake_intensity = maxf(0, shake_intensity - shake_decay * delta)
	
	# Look at a point ahead of the player (in the direction of travel)
	var look_target := target_pos + Vector3(0, 0, -look_ahead)
	look_at(look_target, Vector3.UP)

func shake(intensity: float = 0.5) -> void:
	# Check if screen shake is enabled
	if settings_manager and not settings_manager.get_screen_shake_enabled():
		return
	shake_intensity = intensity


## Extended shake with custom decay rate for longer shakes
func shake_extended(intensity: float, decay: float) -> void:
	# Check if screen shake is enabled
	if settings_manager and not settings_manager.get_screen_shake_enabled():
		return
	shake_intensity = intensity
	shake_decay = decay


func _on_player_hit(_damage: int) -> void:
	shake(0.6)
	shake_decay = 5.0  # Reset to default decay

func _on_player_died() -> void:
	is_following = false

func _on_supercharge_activated() -> void:
	target_offset = supercharge_offset

func _on_supercharge_ended() -> void:
	target_offset = offset

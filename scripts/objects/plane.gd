extends Node3D
class_name PlaneNPC
## Enemy Plane NPC - flies over terrain, drops bombs near player
## Spawns from ahead.Flies forward. Drops bomb pairs when close to player.
## Can be destroyed by player for big coin reward.

const BombScript := preload("res://scripts/objects/bomb.gd")

@export var damage: int = 40  # Bomb shock wave damage
@export var coin_value: int = 1400
@export var object_id: String = "npc_plane"
@export var object_name: String = "Enemy Plane"

# Flight parameters
const FLIGHT_SPEED_MIN: float = 22.0  # m/s
const FLIGHT_SPEED_MAX: float = 28.0
const FLIGHT_ALTITUDE_MIN: float = 10.0  # meters above terrain (lower)
const FLIGHT_ALTITUDE_MAX: float = 14.0
const DESPAWN_DISTANCE: float = 150.0  # Distance behind player to despawn (enough for contrail to fade)

# Bomb dropping
const BOMB_DROP_DISTANCE: float = 50.0  # Start dropping when within this distance
const BOMB_DROP_INTERVAL: float = 0.5  # Seconds between drops (4x faster)
const BOMB_SPREAD: float = 4.0  # Max random X spread
const SHOCK_WAVE_RADIUS: float = 12.0

# Tilt animation
const TILT_SPEED: float = 1.5  # How fast the tilt changes
const TILT_MAX_ANGLE: float = 8.0  # Maximum tilt in degrees

# Internal state
var is_dead := false
var is_active := true
var player: Node3D = null
var model: Node3D = null
var audio_manager: Node
var terrain_generator: Node3D = null

# Flight state
var flight_speed: float = 25.0
var flight_altitude: float = 15.0
var velocity: Vector3 = Vector3.ZERO

# Bomb state
var time_since_last_bomb: float = 0.0
var can_drop_bombs := false
var passed_player := false  # True when plane has passed behind player (stops bombing)

# Animation state
var tilt_phase: float = 0.0
var current_tilt: float = 0.0
var target_tilt: float = 0.0

# Collision
var collision_area: Area3D

# Audio
var jet_audio: AudioStreamPlayer3D

# Contrail (smoke trail)
var contrail: GPUParticles3D


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("enemy_npcs")
	add_to_group("planes")
	
	audio_manager = get_node_or_null("/root/AudioManager")
	terrain_generator = get_tree().get_first_node_in_group("terrain_generator")
	
	# Randomize flight parameters
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	flight_speed = rng.randf_range(FLIGHT_SPEED_MIN, FLIGHT_SPEED_MAX)
	flight_altitude = rng.randf_range(FLIGHT_ALTITUDE_MIN, FLIGHT_ALTITUDE_MAX)
	tilt_phase = rng.randf() * TAU  # Random starting phase
	
	# Find model
	await get_tree().process_frame
	model = get_node_or_null("Model")
	if model:
		# Face toward player (+Z direction since player is at less negative Z)
		model.rotation.y = 0  # Face +Z direction
	
	# Setup collision area for player hit detection
	_setup_collision()
	
	# Setup jet engine sound (spatial 3D audio)
	_setup_jet_audio()
	
	# Setup contrail (smoke trail)
	_setup_contrail()
	
	# Find player reference
	player = get_tree().get_first_node_in_group("player") as Node3D
	
	# Initialize velocity (flying towards player, i.e., in +Z direction)
	# Player moves in -Z, plane spawns ahead (more negative Z) and flies toward player (+Z)
	velocity = Vector3(0, 0, flight_speed)


func _setup_collision() -> void:
	## Create collision area for player to destroy the plane
	collision_area = Area3D.new()
	collision_area.name = "HitArea"
	collision_area.collision_layer = 0
	collision_area.collision_mask = 2  # Detect player (layer 2)
	
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5.5, 2.0, 3.5)  # Wide hitbox to cover wings
	shape.shape = box
	collision_area.add_child(shape)
	
	collision_area.body_entered.connect(_on_player_collision)
	add_child(collision_area)


func _setup_jet_audio() -> void:
	## Create spatial 3D audio for jet engine sound
	jet_audio = AudioStreamPlayer3D.new()
	jet_audio.name = "JetAudio"
	
	# Load jet sound
	var jet_stream := load("res://assets/sounds/sfx/jet_sound.mp3") as AudioStream
	if jet_stream:
		jet_audio.stream = jet_stream
		jet_audio.autoplay = true
		jet_audio.bus = "SFX"
		jet_audio.volume_db = 12.0  # Louder volume
		
		# 3D spatial settings - large range for distant audibility
		jet_audio.unit_size = 50.0  # Reference distance (louder at distance)
		jet_audio.max_distance = 300.0  # Max audible distance
		jet_audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_LOGARITHMIC
		jet_audio.max_db = 6.0  # Max volume boost when close
		
		# Loop the sound
		jet_audio.finished.connect(_on_jet_audio_finished)
		
		add_child(jet_audio)


func _on_jet_audio_finished() -> void:
	## Restart jet sound for looping
	if jet_audio and is_instance_valid(jet_audio) and not is_dead:
		jet_audio.play()


func _setup_contrail() -> void:
	## Create contrail/smoke trail behind the plane
	contrail = GPUParticles3D.new()
	contrail.name = "Contrail"
	contrail.amount = 60
	contrail.lifetime = 3.0  # Long trail
	contrail.explosiveness = 0.0
	contrail.emitting = true
	
	var proc_mat := ParticleProcessMaterial.new()
	# Emit behind the plane (negative Z direction relative to plane)
	proc_mat.direction = Vector3(0, 0, -1)
	proc_mat.spread = 5.0  # Tight spread
	proc_mat.initial_velocity_min = 1.0
	proc_mat.initial_velocity_max = 2.0
	proc_mat.gravity = Vector3(0, 0.5, 0)  # Slight upward drift
	proc_mat.damping_min = 1.0
	proc_mat.damping_max = 2.0
	
	# Scale: start small, grow, then fade
	proc_mat.scale_min = 0.3
	proc_mat.scale_max = 0.5
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 0.3))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 1.5))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	proc_mat.scale_curve = scale_tex
	
	# Color: white smoke that fades out
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(0.9, 0.9, 0.95, 0.7))  # Bright white-gray
	color_ramp.set_color(1, Color(0.7, 0.7, 0.75, 0.0))  # Fade to transparent
	var color_tex := GradientTexture1D.new()
	color_tex.gradient = color_ramp
	proc_mat.color_ramp = color_tex
	
	contrail.process_material = proc_mat
	
	# Simple sphere mesh for smoke puffs
	var mesh := SphereMesh.new()
	mesh.radius = 0.8
	mesh.height = 1.6
	var mesh_mat := StandardMaterial3D.new()
	mesh_mat.albedo_color = Color(0.95, 0.95, 1.0)
	mesh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mesh_mat
	contrail.draw_pass_1 = mesh
	
	# Position behind the plane (at engine/tail)
	contrail.position = Vector3(0, 0, 2.0)  # Behind the plane
	add_child(contrail)


func _process(delta: float) -> void:
	if is_dead or not is_active:
		return
	
	# Update tilt animation
	_update_tilt_animation(delta)
	
	# Move plane
	_update_flight(delta)
	
	# Check if should drop bombs
	_update_bombing(delta)
	
	# Check despawn condition
	_check_despawn()


func _update_tilt_animation(delta: float) -> void:
	## Animate plane with subtle banking/tilting motion
	tilt_phase += delta * TILT_SPEED
	
	# Combine multiple sine waves for organic motion
	var tilt_x := sin(tilt_phase * 1.3) * TILT_MAX_ANGLE * 0.7
	var tilt_z := sin(tilt_phase * 0.9 + 1.5) * TILT_MAX_ANGLE * 0.5
	
	if model:
		model.rotation.x = deg_to_rad(tilt_x)
		model.rotation.z = deg_to_rad(tilt_z)


func _update_flight(delta: float) -> void:
	## Update plane position, maintaining altitude above terrain
	# Move forward
	global_position += velocity * delta
	
	# Maintain altitude above terrain
	if terrain_generator and terrain_generator.has_method("get_height_at"):
		var terrain_height: float = terrain_generator.get_height_at(global_position.x, global_position.z)
		var target_y: float = terrain_height + flight_altitude
		# Fast altitude adjustment (8x faster) for immediate response
		global_position.y = lerpf(global_position.y, target_y, delta * 8.0)


func _update_bombing(delta: float) -> void:
	## Check distance to player and drop bombs if close enough
	if not player:
		player = get_tree().get_first_node_in_group("player") as Node3D
		return
	
	# Don't drop bombs if already passed behind player
	if passed_player:
		return
	
	var distance_to_player := global_position.distance_to(player.global_position)
	
	# Start dropping when close enough
	if distance_to_player <= BOMB_DROP_DISTANCE and not can_drop_bombs:
		can_drop_bombs = true
		# Drop first bomb immediately
		_drop_bombs()
		time_since_last_bomb = 0.0
	
	if can_drop_bombs:
		time_since_last_bomb += delta
		if time_since_last_bomb >= BOMB_DROP_INTERVAL:
			_drop_bombs()
			time_since_last_bomb = 0.0


func _drop_bombs() -> void:
	## Drop a single bomb at random position below plane
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	# Random X offset and small random Z offset for variety
	var random_x := rng.randf_range(-BOMB_SPREAD, BOMB_SPREAD)
	var random_z := rng.randf_range(-1.5, 1.5)
	var bomb_pos := global_position + Vector3(random_x, 0, random_z)
	
	var bomb := _create_bomb()
	get_tree().root.add_child(bomb)
	bomb.global_position = bomb_pos
	bomb.initialize(damage, SHOCK_WAVE_RADIUS)


func _create_bomb() -> Node3D:
	## Create a bomb instance
	var bomb := Node3D.new()
	bomb.set_script(BombScript)
	bomb.name = "Bomb"
	return bomb


func _check_despawn() -> void:
	## Remove plane when it passes far behind the player
	if not player:
		return
	
	# Check if plane has just passed behind player (stop bombing)
	if not passed_player and global_position.z > player.global_position.z + 10.0:
		passed_player = true
		can_drop_bombs = false  # Stop dropping bombs once behind player
	
	# Plane flies in +Z direction, despawn when far enough behind for contrail to fade
	# (contrail lifetime is 3s, at ~25m/s that's ~75m, we use 150m for safety)
	if global_position.z > player.global_position.z + DESPAWN_DISTANCE:
		queue_free()


func _on_player_collision(body: Node3D) -> void:
	## Player hit the plane - destroy it and reward coins
	if is_dead:
		return
	
	if body.is_in_group("player"):
		# Get player velocity for destruction effect
		var player_velocity := Vector3.FORWARD * 20.0
		if body.has_method("get_velocity"):
			player_velocity = body.get_velocity()
		elif "velocity" in body:
			player_velocity = body.velocity
		
		_die(player_velocity)


func _die(player_velocity: Vector3 = Vector3.FORWARD * 20.0) -> void:
	## Plane destroyed by player
	if is_dead:
		return
	is_dead = true
	is_active = false
	
	# Stop jet engine sound
	if jet_audio and is_instance_valid(jet_audio):
		jet_audio.stop()
		jet_audio.queue_free()
	
	# Stop contrail
	if contrail and is_instance_valid(contrail):
		contrail.emitting = false
	
	# Award coins and record stats BEFORE destruction
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm:
		if gm.has_method("add_coins"):
			gm.add_coins(coin_value)
		elif gm.has_method("add_coin"):
			gm.add_coin(coin_value)
		if gm.has_method("record_destroyed_object"):
			gm.record_destroyed_object(object_id, object_name, coin_value)
	
	# Play sound
	if audio_manager and audio_manager.has_method("play_sfx"):
		audio_manager.play_sfx("explosion")
	
	# Use DestructionManager to shatter the plane (like buildings)
	var destruction := get_node_or_null("/root/DestructionManager")
	if destruction and model:
		destruction.shatter(model, player_velocity, true)
		# Remove collision and let destruction handle the rest
		if collision_area:
			collision_area.queue_free()
		# Wait a bit then remove self
		await get_tree().create_timer(0.1).timeout
		if is_instance_valid(self):
			queue_free()
	else:
		# Fallback: spawn explosion and remove
		_spawn_explosion()
		queue_free()


func _spawn_explosion() -> void:
	## Spawn explosion particles at plane position
	var explosion_scene := load("res://scenes/explosion_effect.tscn") as PackedScene
	if explosion_scene:
		var explosion: Node3D = explosion_scene.instantiate() as Node3D
		get_tree().root.add_child(explosion)
		explosion.global_position = global_position


## Initialize plane at spawn position
func initialize(spawn_pos: Vector3, _target_altitude: float = -1.0) -> void:
	global_position = spawn_pos
	if _target_altitude > 0:
		flight_altitude = _target_altitude

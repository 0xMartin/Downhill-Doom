extends CharacterBody3D
class_name WizardNPC
## Wizard NPC - enemy that follows player and shoots homing magic spells
## Spells cause blindness (fog effect) in addition to damage
## Player can dodge spells by jumping (spells stay at terrain height)

@export var damage: int = 22
@export var coin_value: int = 800
@export var object_id: String = "npc_wizard"
@export var object_name: String = "Wizard"

# Detection and movement - larger than horse_knight by 10%
const DETECTION_RANGE: float = 66.0  # 60 * 1.1 = 66 (10% more than horse_knight)
const SHOOTING_RANGE: float = 33.0  # 50% of detection range
const MOVE_SPEED: float = 6.0  # Same as dark_knight

# Spell settings
const SPELL_COOLDOWN: float = 2.0
const SPELL_LIFETIME: float = 5.0
const SPELL_SPEED: float = 23.4  # 30% faster (18 * 1.3)
const BLINDNESS_DURATION: float = 5.0
const BLINDNESS_FOG_BEGIN: float = 0.0
const BLINDNESS_FOG_END: float = 40.0

# Physics
const GRAVITY: float = 20.0

# Hop animation settings (model only)
var model_height: float = 2.7
var hop_height: float = 0.2
var hop_speed: float = 10.0

# Internal state
var is_dead := false
var is_chasing := false
var is_casting := false
var player: Node3D = null
var model: Node3D = null
var model_base_y: float = 0.0
var hop_phase: float = 0.0
var audio_manager: Node
var game_manager: Node

# Spell cooldown
var spell_timer: float = 0.0
var can_shoot := true

# Casting particles
var casting_particles: GPUParticles3D = null


func _ready() -> void:
	add_to_group("npcs")
	add_to_group("enemy_npcs")
	add_to_group("wizards")
	
	audio_manager = get_node_or_null("/root/AudioManager")
	game_manager = get_node_or_null("/root/GameManager")
	
	# Calculate hop height based on model height
	hop_height = model_height * 0.15
	
	# Find model child
	model = get_node_or_null("Model")
	if model:
		model_base_y = model.position.y
		# Rotate model 180 degrees - models are exported facing backwards
		model.rotation.y = PI
	
	# Connect detection area signal
	_connect_detect_area()
	
	# Create casting particles
	_create_casting_particles()
	
	# Find player reference
	player = get_tree().get_first_node_in_group("player") as Node3D


func _connect_detect_area() -> void:
	## Connect signal to detect area if not already connected
	var detect_area := get_node_or_null("DetectArea") as Area3D
	if detect_area:
		if detect_area.body_entered.is_connected(_on_detect_area_body_entered):
			return
		detect_area.body_entered.connect(_on_detect_area_body_entered)


func _create_casting_particles() -> void:
	## Create purple particles for casting effect
	casting_particles = GPUParticles3D.new()
	casting_particles.name = "CastingParticles"
	casting_particles.amount = 10
	casting_particles.lifetime = 0.5
	casting_particles.explosiveness = 0.3
	casting_particles.emitting = false
	casting_particles.one_shot = true
	
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.3
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 2.0
	mat.initial_velocity_max = 4.0
	mat.gravity = Vector3(0, -2, 0)
	mat.scale_min = 0.1
	mat.scale_max = 0.2
	mat.color = Color(0.6, 0.0, 0.9, 1.0)  # Purple
	casting_particles.process_material = mat
	
	# Simple sphere mesh for particles
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	mesh.radial_segments = 8
	mesh.rings = 4
	casting_particles.draw_pass_1 = mesh
	
	# Position at hand height
	casting_particles.position = Vector3(0, model_height * 0.7, 0.3)
	add_child(casting_particles)


func _process(delta: float) -> void:
	if is_dead:
		return
	
	# Update spell cooldown
	if not can_shoot:
		spell_timer += delta
		if spell_timer >= SPELL_COOLDOWN:
			spell_timer = 0.0
			can_shoot = true
	
	# Update hop animation when chasing (model only)
	if is_chasing and model:
		hop_phase += delta * hop_speed
		var hop_offset: float = abs(sin(hop_phase)) * hop_height
		model.position.y = model_base_y + hop_offset
	elif model:
		# Smoothly return to base when stationary
		model.position.y = lerp(model.position.y, model_base_y, delta * 10.0)


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0
	
	# Check if player is in range and should chase/shoot
	_update_state()
	
	# Move towards player if chasing
	if is_chasing and player and is_instance_valid(player):
		var direction := (player.global_position - global_position)
		direction.y = 0  # Horizontal only
		var distance := direction.length()
		
		# Don't move if in shooting range
		if distance > SHOOTING_RANGE and distance > 2.0:
			direction = direction.normalized()
			velocity.x = direction.x * MOVE_SPEED
			velocity.z = direction.z * MOVE_SPEED
		else:
			velocity.x = 0
			velocity.z = 0
		
		# Rotate towards player
		_rotate_towards_player(delta)
		
		# Check if can shoot
		if distance <= SHOOTING_RANGE and can_shoot:
			_cast_spell()
	else:
		velocity.x = 0
		velocity.z = 0
	
	move_and_slide()


func _update_state() -> void:
	## Check if player is within detection range and in front
	if not player or not is_instance_valid(player):
		if not player:
			player = get_tree().get_first_node_in_group("player") as Node3D
		is_chasing = false
		return
	
	var distance := global_position.distance_to(player.global_position)
	
	# Don't chase if player has already passed (like catapult)
	if player.global_position.z < global_position.z - 5.0:
		is_chasing = false
		return
	
	# Start chasing if player enters range
	if distance <= DETECTION_RANGE:
		if not is_chasing:
			is_chasing = true
			hop_phase = 0.0
	elif is_chasing and distance > DETECTION_RANGE * 1.5:
		is_chasing = false


func _rotate_towards_player(_delta: float) -> void:
	## Rotate to face the player direction (using look_at like enemy_npc)
	if not player or not is_instance_valid(player):
		return
	
	var direction := player.global_position - global_position
	direction.y = 0
	
	if direction.length() < 0.5:
		return
	
	# Face player direction (look_at faces Z-forward)
	var look_target := global_position + direction
	look_at(look_target, Vector3.UP)
	rotation.x = 0
	rotation.z = 0


func _cast_spell() -> void:
	## Cast a magic spell at the player
	can_shoot = false
	spell_timer = 0.0
	is_casting = true
	
	# Show casting particles
	if casting_particles:
		casting_particles.emitting = true
	
	# Create spell projectile
	var spell := WizardSpell.new()
	spell.damage = damage
	spell.shooter = self
	spell.blindness_duration = BLINDNESS_DURATION
	spell.blindness_fog_begin = BLINDNESS_FOG_BEGIN
	spell.blindness_fog_end = BLINDNESS_FOG_END
	spell.lifetime = SPELL_LIFETIME
	spell.speed = SPELL_SPEED
	
	# Store ground level for spell to maintain height
	spell.ground_level = global_position.y
	
	# Calculate horizontal direction to player (ignore Y)
	var to_player := player.global_position - global_position
	to_player.y = 0
	var horizontal_dir := to_player.normalized()
	
	# Spawn spell at terrain height + 1m, slightly forward from wizard
	var spawn_pos := global_position
	spawn_pos.y = spell.ground_level + spell.MIN_TERRAIN_HEIGHT
	spawn_pos += horizontal_dir * 2.0  # Spawn forward
	spell.global_position = spawn_pos
	spell.target = player
	
	# Set velocity purely horizontal toward player
	spell.velocity = horizontal_dir * SPELL_SPEED
	
	get_tree().root.add_child(spell)
	
	# Play cast sound
	if audio_manager and audio_manager.has_method("play_spell_cast_sound"):
		audio_manager.play_spell_cast_sound()


func _on_detect_area_body_entered(body: Node) -> void:
	if is_dead:
		return
	
	if body.is_in_group("player"):
		# Don't damage player if they're in the air (jumping)
		if body.has_method("get") and body.get("is_on_ground") == false:
			return
		_damage_player_with_blindness(body)
		die(body)


func _damage_player_with_blindness(player_node: Node) -> void:
	## Deal damage to player and apply blindness before dying (only if not supercharged)
	# Deal damage and apply blindness through GameManager
	if game_manager:
		# Only apply damage and blindness if not in supercharge mode
		if not game_manager.is_supercharged:
			if audio_manager:
				audio_manager.play_hurt_sound()
			game_manager.take_damage(damage)
			game_manager.apply_blindness(BLINDNESS_DURATION, BLINDNESS_FOG_BEGIN, BLINDNESS_FOG_END)


func die(killer: Node = null) -> void:
	if is_dead:
		return
	
	is_dead = true
	is_chasing = false
	
	if audio_manager:
		audio_manager.play_npc_death_sound("enemy")
	
	if game_manager:
		game_manager.add_coin(coin_value)
		game_manager.record_destroyed_object(object_id, object_name, coin_value)
	
	var dm := get_node_or_null("/root/DestructionManager")
	if dm:
		dm.fling_object(self, killer, model)
	else:
		queue_free()


## Called by ObjectPool when this object is retrieved from pool
func _pool_reset() -> void:
	add_to_group("npcs")
	add_to_group("enemy_npcs")
	add_to_group("wizards")
	_connect_detect_area()
	is_dead = false
	is_chasing = false
	is_casting = false
	player = null
	hop_phase = 0.0
	spell_timer = 0.0
	can_shoot = true

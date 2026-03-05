extends Node3D
## Infinite procedural terrain generator - main coordinator
## Uses TerrainMeshBuilder, HoleManager, and ObjectSpawner for modular generation

# Preload sub-system scripts
const TerrainMeshBuilderScript := preload("res://scripts/terrain/terrain_mesh_builder.gd")
const HoleManagerScript := preload("res://scripts/terrain/hole_manager.gd")
const ObjectSpawnerScript := preload("res://scripts/terrain/object_spawner.gd")

signal terrain_chunk_created(chunk: Node3D)
signal terrain_ready

# Chunk configuration
@export var chunk_size: Vector2 = Vector2(100, 50)
@export var chunks_ahead: int = 5
@export var chunks_behind: int = 2
@export var slope_angle: float = 12.0
@export var noise_height: float = 1.0
@export var noise_scale: float = 0.02
@export var barrier_height: float = 10.0
@export var terrain_width: float = 36.0

# Mountain parameters
@export_group("Mountains")
@export var mountain_width: float = 25.0
@export var mountain_height: float = 21.0
@export var peak_curve_width: float = 7.0
@export var mountain_noise_strength: float = 3.5
@export var grid_jitter: float = 0.35

# Object spawning
@export_group("Objects")
@export var tree_density: float = 0.5
@export var rock_spawn_chance: float = 0.6
@export var rock_safe_chunks: int = 2
@export var num_lanes: int = 5

# Hole parameters
@export_group("Holes")
@export var hole_enabled: bool = true
@export var hole_min_spacing: float = 50.0
@export var hole_max_spacing: float = 80.0
@export var hole_safe_chunks: int = 3
@export var narrow_hole_width: float = 8.0
@export var narrow_hole_irregularity: float = 3.0
@export var hole_depth: float = 8.0
@export var narrow_hole_chance: float = 0.4
@export var random_hole_min_radius: float = 6.0
@export var random_hole_max_radius: float = 10.0

# Runtime state
var noise: FastNoiseLite
var chunks: Dictionary = {}
var current_chunk_index: int = 0
var player: Node3D
var is_ready := false

# Sub-systems (use RefCounted base type since class_name isn't recognized at parse time)
var mesh_builder: RefCounted
var hole_manager: RefCounted
var object_spawner: RefCounted

func _ready() -> void:
	add_to_group("terrain_generator")
	
	# Initialize noise
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = noise_scale
	noise.seed = randi()
	
	# Initialize sub-systems with configuration
	_init_subsystems()
	
	# Generate initial chunks
	for i in range(-chunks_behind, chunks_ahead + 1):
		_generate_chunk(i)
	
	is_ready = true
	terrain_ready.emit()
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

func _init_subsystems() -> void:
	# Shared configuration with random seed
	var random_seed := randi()
	var config := {
		"seed": random_seed,
		"noise": noise,
		"terrain_width": terrain_width,
		"noise_height": noise_height,
		"slope_angle": slope_angle,
		"grid_jitter": grid_jitter,
		"chunk_size": chunk_size,
		"mountain_width": mountain_width,
		"mountain_height": mountain_height,
		"peak_curve_width": peak_curve_width,
		"mountain_noise_strength": mountain_noise_strength,
		"hole_depth": hole_depth,
		"narrow_hole_irregularity": narrow_hole_irregularity,
		"hole_enabled": hole_enabled,
		"hole_min_spacing": hole_min_spacing,
		"hole_max_spacing": hole_max_spacing,
		"hole_safe_chunks": hole_safe_chunks,
		"narrow_hole_width": narrow_hole_width,
		"narrow_hole_chance": narrow_hole_chance,
		"random_hole_min_radius": random_hole_min_radius,
		"random_hole_max_radius": random_hole_max_radius,
		"tree_density": tree_density,
		"rock_spawn_chance": rock_spawn_chance,
		"rock_safe_chunks": rock_safe_chunks,
		"num_lanes": num_lanes,
	}
	
	# Create sub-systems
	hole_manager = HoleManagerScript.new(config)
	if not hole_manager:
		push_error("Failed to create HoleManager")
		return
	
	mesh_builder = TerrainMeshBuilderScript.new(config)
	if not mesh_builder:
		push_error("Failed to create TerrainMeshBuilder")
		return
	mesh_builder.set_hole_manager(hole_manager)
	
	object_spawner = ObjectSpawnerScript.new(config)
	if not object_spawner:
		push_error("Failed to create ObjectSpawner")
		return
	object_spawner.set_hole_manager(hole_manager)

func _exit_tree() -> void:
	var all_chunks := chunks.keys().duplicate()
	for chunk_index in all_chunks:
		_cleanup_chunk(chunk_index)
	
	chunks.clear()
	
	# Clear sub-systems
	mesh_builder = null
	hole_manager = null
	object_spawner = null

func _process(_delta: float) -> void:
	if not player:
		player = get_tree().get_first_node_in_group("player")
		return
	
	var player_z := player.global_position.z
	var new_chunk_index := int(floor(-player_z / chunk_size.y))
	
	if new_chunk_index != current_chunk_index:
		current_chunk_index = new_chunk_index
		_update_chunks()

func _update_chunks() -> void:
	for i in range(current_chunk_index - chunks_behind, current_chunk_index + chunks_ahead + 1):
		if not chunks.has(i):
			_generate_chunk(i)
	
	var chunks_to_remove: Array[int] = []
	for chunk_index in chunks.keys():
		if chunk_index < current_chunk_index - chunks_behind:
			chunks_to_remove.append(chunk_index)
	
	for chunk_index in chunks_to_remove:
		_cleanup_chunk(chunk_index)

func _generate_chunk(chunk_index: int) -> void:
	if chunks.has(chunk_index):
		return
	
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d" % chunk_index
	add_child(chunk)
	
	var chunk_z := -chunk_index * chunk_size.y
	var chunk_y := chunk_z * tan(deg_to_rad(slope_angle))
	chunk.position = Vector3(0, chunk_y, chunk_z)
	
	# 1. Pre-calculate holes
	hole_manager.precalculate_holes(chunk_index)
	
	# 2. Create terrain mesh (includes hole walls)
	var terrain: StaticBody3D = mesh_builder.create_terrain(chunk_index)
	chunk.add_child(terrain)
	
	# 3. Create barriers
	_create_barriers(chunk)
	
	# 4. Spawn hole effects (death zones, particles)
	hole_manager.spawn_hole_effects(chunk, chunk_index, get_decoration_height)
	
	# 5. Spawn objects (trees, rocks, etc.)
	if object_spawner:
		object_spawner.spawn_objects(chunk, chunk_index, get_decoration_height)
	else:
		push_error("ObjectSpawner is null in chunk %d - reinitializing" % chunk_index)
		_init_subsystems()
		if object_spawner:
			object_spawner.spawn_objects(chunk, chunk_index, get_decoration_height)
	
	chunks[chunk_index] = chunk
	terrain_chunk_created.emit(chunk)

func _cleanup_chunk(chunk_index: int) -> void:
	if not chunks.has(chunk_index):
		return
	
	var chunk: Node3D = chunks[chunk_index]
	_cleanup_node_recursive(chunk)
	chunk.queue_free()
	
	chunks.erase(chunk_index)
	hole_manager.cleanup_chunk(chunk_index)

func _cleanup_node_recursive(node: Node) -> void:
	if node == null:
		return
	
	if node is GPUParticles3D:
		var particles := node as GPUParticles3D
		particles.emitting = false
		particles.process_material = null
		particles.draw_pass_1 = null
	
	if node is Area3D and node.name == "DeathZone":
		var area := node as Area3D
		area.monitoring = false
	
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			for i in range(mesh_instance.get_surface_override_material_count()):
				mesh_instance.set_surface_override_material(i, null)
	
	if node is CollisionShape3D:
		var col_shape := node as CollisionShape3D
		col_shape.disabled = true
	
	for child in node.get_children():
		_cleanup_node_recursive(child)

func _create_barriers(chunk: Node3D) -> void:
	var half_playable := terrain_width / 2.0
	
	var left_barrier := StaticBody3D.new()
	left_barrier.name = "LeftBarrier"
	left_barrier.position = Vector3(-half_playable - 0.5, 0, -chunk_size.y / 2)
	var left_shape := CollisionShape3D.new()
	var left_box := BoxShape3D.new()
	left_box.size = Vector3(1, barrier_height * 2, chunk_size.y + 10)
	left_shape.shape = left_box
	left_barrier.add_child(left_shape)
	chunk.add_child(left_barrier)
	
	var right_barrier := StaticBody3D.new()
	right_barrier.name = "RightBarrier"
	right_barrier.position = Vector3(half_playable + 0.5, 0, -chunk_size.y / 2)
	var right_shape := CollisionShape3D.new()
	var right_box := BoxShape3D.new()
	right_box.size = Vector3(1, barrier_height * 2, chunk_size.y + 10)
	right_shape.shape = right_box
	right_barrier.add_child(right_shape)
	chunk.add_child(right_barrier)

## Get terrain height at a specific position - used by ObjectSpawner and HoleManager
func get_decoration_height(local_x: float, local_z: float, chunk_index: int) -> float:
	var world_z: float = local_z - chunk_index * chunk_size.y
	var profile_height: float = mesh_builder.get_cross_section_height(local_x, world_z)
	
	var terrain_noise := noise.get_noise_2d(local_x * 3, world_z * 3) * noise_height
	terrain_noise += noise.get_noise_2d(local_x * 0.5, world_z * 0.5) * noise_height * 2
	
	var height: float = profile_height + terrain_noise
	var slope_offset := (-local_z) * tan(deg_to_rad(slope_angle))
	height -= slope_offset
	
	return height

## Get height at world coordinates (for external use)
func get_height_at(world_x: float, world_z: float) -> float:
	# Guard against null mesh_builder (can happen during initialization or far from spawned chunks)
	if not mesh_builder:
		return world_z * tan(deg_to_rad(slope_angle))
	
	var profile_height: float = mesh_builder.get_cross_section_height(world_x, world_z)
	
	var half_terrain := terrain_width / 2.0
	var abs_x := absf(world_x)
	var terrain_noise := 0.0
	if abs_x < half_terrain:
		terrain_noise = noise.get_noise_2d(world_x * 3, world_z * 3) * noise_height
		terrain_noise += noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * noise_height * 2
	
	var height: float = profile_height + terrain_noise
	height += world_z * tan(deg_to_rad(slope_angle))
	
	return height

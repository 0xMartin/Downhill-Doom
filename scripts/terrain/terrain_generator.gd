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
@export var chunks_ahead: int = 3  # Reduced from 5 for mobile performance
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

# Object spawning - reduced 50% total for mobile performance
@export_group("Objects")
@export var tree_density: float = 0.25
@export var rock_spawn_chance: float = 0.30
@export var rock_safe_chunks: int = 2
@export var num_lanes: int = 5

# Hole parameters
@export_group("Holes")
@export var hole_enabled: bool = true
@export var hole_min_spacing: float = 80.0
@export var hole_max_spacing: float = 200.0
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

# Async generation state
var _generating_chunks: Dictionary = {}  # chunk_index -> true (being generated)
var _generation_queue: Array[int] = []  # Chunks waiting to be generated
var _is_generating := false  # Lock for async generation

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
	
	# Generate initial chunks async (spread across frames)
	_generate_initial_chunks()

func _generate_initial_chunks() -> void:
	for i in range(-chunks_behind, chunks_ahead + 1):
		_queue_chunk_generation(i)
	# Start processing queue
	_process_generation_queue()

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
	# Queue chunks for async generation instead of generating immediately
	for i in range(current_chunk_index - chunks_behind, current_chunk_index + chunks_ahead + 1):
		if not chunks.has(i) and not _generating_chunks.has(i):
			_queue_chunk_generation(i)
	
	# Start processing if not already running
	if not _is_generating and _generation_queue.size() > 0:
		_process_generation_queue()
	
	var chunks_to_remove: Array[int] = []
	for chunk_index in chunks.keys():
		if chunk_index < current_chunk_index - chunks_behind:
			chunks_to_remove.append(chunk_index)
	
	for chunk_index in chunks_to_remove:
		_cleanup_chunk(chunk_index)

func _queue_chunk_generation(chunk_index: int) -> void:
	if chunks.has(chunk_index) or _generating_chunks.has(chunk_index):
		return
	if chunk_index not in _generation_queue:
		_generation_queue.append(chunk_index)
		_generating_chunks[chunk_index] = true

func _process_generation_queue() -> void:
	if _is_generating:
		return
	_is_generating = true
	_process_next_chunk()

func _process_next_chunk() -> void:
	if _generation_queue.size() == 0:
		_is_generating = false
		if not is_ready:
			is_ready = true
			terrain_ready.emit()
			player = get_tree().get_first_node_in_group("player")
		return
	
	var chunk_index: int = _generation_queue.pop_front()
	_generate_chunk_async(chunk_index)

func _generate_chunk_async(chunk_index: int) -> void:
	if chunks.has(chunk_index):
		_generating_chunks.erase(chunk_index)
		# Process next after this frame
		call_deferred("_process_next_chunk")
		return
	
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d" % chunk_index
	add_child(chunk)
	
	var chunk_z := -chunk_index * chunk_size.y
	var chunk_y := chunk_z * tan(deg_to_rad(slope_angle))
	chunk.position = Vector3(0, chunk_y, chunk_z)
	
	# 1. Pre-calculate holes (fast)
	if hole_manager:
		hole_manager.precalculate_holes(chunk_index)
	
	# Yield to next frame before heavy mesh generation
	await get_tree().process_frame
	
	# Check if chunk was cleaned up while waiting
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
		_generating_chunks.erase(chunk_index)
		call_deferred("_process_next_chunk")
		return
	
	# 2. Create terrain mesh (HEAVY - main bottleneck)
	var terrain: StaticBody3D = mesh_builder.create_terrain(chunk_index)
	chunk.add_child(terrain)
	
	# Yield after mesh creation
	await get_tree().process_frame
	
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
		_generating_chunks.erase(chunk_index)
		call_deferred("_process_next_chunk")
		return
	
	# 3. Create barriers (fast)
	_create_barriers(chunk)
	
	# 4. Spawn hole effects (medium)
	if hole_manager:
		hole_manager.spawn_hole_effects(chunk, chunk_index, get_decoration_height)
	
	# Yield before object spawning
	await get_tree().process_frame
	
	if not is_instance_valid(chunk) or chunk.is_queued_for_deletion():
		_generating_chunks.erase(chunk_index)
		call_deferred("_process_next_chunk")
		return
	
	# 5. Spawn objects with batched yielding (HEAVY)
	if object_spawner:
		await object_spawner.spawn_objects_async(chunk, chunk_index, get_decoration_height)
	
	# Finalize chunk
	if is_instance_valid(chunk) and not chunk.is_queued_for_deletion():
		chunks[chunk_index] = chunk
		terrain_chunk_created.emit(chunk)
	
	_generating_chunks.erase(chunk_index)
	
	# Process next chunk
	call_deferred("_process_next_chunk")

func _cleanup_chunk(chunk_index: int) -> void:
	if not chunks.has(chunk_index):
		return
	
	var chunk: Node3D = chunks[chunk_index]
	
	# Return poolable objects to pool before destroying chunk
	_return_objects_to_pool(chunk)
	
	_cleanup_node_recursive(chunk)
	chunk.queue_free()
	
	chunks.erase(chunk_index)
	if hole_manager:
		hole_manager.cleanup_chunk(chunk_index)
	if object_spawner:
		object_spawner.cleanup_chunk(chunk_index)


## Return spawned objects to pool for reuse
func _return_objects_to_pool(chunk: Node3D) -> void:
	var pool: Node = Engine.get_main_loop().root.get_node_or_null("ObjectPool")
	if not pool:
		return
	
	# Collect poolable children (don't modify while iterating)
	var poolable_objects: Array[Node3D] = []
	for child in chunk.get_children():
		if child is Node3D and child.has_meta("pool_model_path"):
			poolable_objects.append(child)
	
	# Return each to pool
	for obj in poolable_objects:
		var model_path: String = obj.get_meta("pool_model_path")
		var category: int = obj.get_meta("pool_category")
		pool.return_object(obj, model_path, category)

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
		return global_position.y + world_z * tan(deg_to_rad(slope_angle))
	
	var profile_height: float = mesh_builder.get_cross_section_height(world_x, world_z)
	
	var half_terrain := terrain_width / 2.0
	var abs_x := absf(world_x)
	var terrain_noise := 0.0
	if abs_x < half_terrain:
		terrain_noise = noise.get_noise_2d(world_x * 3, world_z * 3) * noise_height
		terrain_noise += noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * noise_height * 2
	
	var height: float = profile_height + terrain_noise
	height += world_z * tan(deg_to_rad(slope_angle))
	
	# Add TerrainGenerator's world position offset
	return height + global_position.y

## Get actual ground level accounting for holes (for collision detection)
func get_ground_level_at(world_x: float, world_z: float) -> float:
	var base_height := get_height_at(world_x, world_z)
	
	# Check if point is in a hole
	if hole_manager and hole_manager.has_method("is_point_in_hole_world"):
		if hole_manager.is_point_in_hole_world(world_x, world_z):
			return base_height - hole_depth
	
	return base_height

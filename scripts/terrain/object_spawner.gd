class_name ObjectSpawner
extends RefCounted
## Handles spawning of all world objects with zone-based placement
## Uses ObjectConfig for object definitions
## 
## Zone system:
## - FOREST zones: Trees + Building Enemies
## - BUILDING zones: Buildings + Building Enemies (2x density)
## - OPEN zones: Transition areas, only rocks
## - Rocks spawn everywhere
##
## Collision AABB naming convention:
## - Nodes ending with "_nocol" are excluded from AABB calculation
## - Example: windmill blades named "blades_nocol" won't affect collision box

const ObjectConfigScript := preload("res://scripts/config/object_config.gd")
const DistanceConfigScript := preload("res://scripts/config/distance_config.gd")
const ItemConfigScript := preload("res://scripts/config/item_config.gd")

# Preloaded scripts for objects
const TreeScript := preload("res://scripts/objects/tree.gd")
const BuildingScript := preload("res://scripts/objects/building.gd")
const LargeBuildingScript := preload("res://scripts/objects/large_building.gd")
const SpikeScript := preload("res://scripts/objects/spike.gd")
const FriendNPCScript := preload("res://scripts/objects/friend_npc.gd")
const EnemyNPCScript := preload("res://scripts/objects/enemy_npc.gd")
const CatapultNPCScript := preload("res://scripts/objects/catapult_npc.gd")
const WizardNPCScript := preload("res://scripts/objects/wizard_npc.gd")
const PlaneNPCScript := preload("res://scripts/objects/plane.gd")
const ItemPickupScript := preload("res://scripts/objects/item_pickup.gd")
const ItemPickupScene := preload("res://scenes/objects/item_pickup.tscn")

# Golden NPC shader
const GoldenShader := preload("res://scripts/shaders/golden_npc.gdshader")

# Golden NPC configuration
const GOLDEN_NPC_CHANCE: float = 0.10  # 10% chance for golden variant
const GOLDEN_NPC_COIN_MULTIPLIER: int = 5  # 5x coins for golden

# Cached golden material (created once, reused)
static var _golden_material: ShaderMaterial = null

static func _get_golden_material() -> ShaderMaterial:
	if _golden_material == null:
		_golden_material = ShaderMaterial.new()
		_golden_material.shader = GoldenShader
	return _golden_material

# ========== SPAWNING CONFIGURATION ==========

var terrain_width: float = 36.0
var chunk_size: Vector2 = Vector2(100, 50)
var num_lanes: int = 5

# Base density settings (objects per 100 square units) - reduced 50% total for mobile
var tree_density: float = 0.25  # Was 0.5 → 0.4 → 0.25
var rock_density: float = 0.08  # Was 0.15 → 0.12 → 0.08
var building_density: float = 0.10  # Was 0.2 → 0.16 → 0.10
var enemy_density: float = 0.12  # Was 0.24 → 0.19 → 0.12
var npc_friend_density: float = 0.015  # Was 0.03 → 0.024 → 0.015
var npc_enemy_density: float = 0.012  # Was 0.021 → 0.017 → 0.012

# Item spawning configuration
var item_density: float = 0.008  # ~1 item per 125 units
var item_safe_chunks: int = 2  # No items in first 2 chunks
var item_min_spacing: float = 125.0  # Minimum distance between items in Z
var item_last_spawn_z: float = -999999.0  # Track last item spawn position
var height_offset_item: float = 0.5  # Items float above ground

# Urban zone multiplier
var urban_density_multiplier: float = 2.0

# Safe chunks (no spawning for first N chunks)
var rock_safe_chunks: int = 2
var enemy_safe_chunks: int = 4
var building_safe_chunks: int = 3
var npc_friend_safe_chunks: int = 2
var npc_enemy_safe_chunks: int = 5  # Later than friends

# Spike wall chain configuration
var spike_wall_safe_chunks: int = 6  # Start later than regular enemies
var spike_wall_min_spacing: float = 100.0  # Minimum distance between chains (half of hole frequency)
var spike_wall_max_spacing: float = 160.0  # Maximum distance between chains
var spike_wall_min_count: int = 3  # Minimum walls per chain
var spike_wall_max_count: int = 6  # Maximum walls per chain
var spike_wall_width: float = 3.0  # Width of each wall segment
var spike_wall_max_angle: float = 25.0  # Maximum angle deviation per segment (degrees)

# Minimum distance between objects to prevent overlap
var min_object_distance: float = 2.5

# Height offsets per category to compensate for lowpoly terrain noise and grid jitter
# Base values - will be combined with noise_compensation at runtime
var height_offset_tree: float = 0.0  # Trees can be slightly embedded (roots)
var height_offset_rock: float = 0.05  # Rocks sit on surface
var height_offset_building: float = 0.1  # Buildings need slight clearance
var height_offset_npc: float = 0.08  # NPCs on surface
var height_offset_spike: float = 0.1  # Spikes need small clearance

# Compensation for terrain mesh noise/jitter that causes height discrepancy
# This is added to all height offsets to prevent objects sinking into terrain variations
var noise_compensation: float = 0.3  # Loaded from config based on noise_height

# Terrain slope angle for tilting objects
var slope_angle: float = 12.0  # Default, loaded from config

# Player spawn safe zone - no objects spawn in this circle where player lands
var player_spawn_position: Vector3 = Vector3(0.0, 0.0, -25.0)  # From game.tscn
var player_spawn_safe_radius: float = 15.0  # Radius where no objects spawn

# ========== INTERNAL STATE ==========

var hole_manager: RefCounted  # HoleManager
var zone_manager: RefCounted  # ZoneManager

# Object pool reference (lazy-loaded from autoload)
var _object_pool: Node = null

# Track spawned positions per chunk to prevent overlap
var spawned_positions: Dictionary = {}  # chunk_index -> Array[Vector2] (x, z)

# ========== SCENE & AABB CACHING (Performance optimization) ==========
# Cache loaded scenes to avoid repeated load() calls
var _scene_cache: Dictionary = {}  # model_path -> PackedScene
# Cache AABB calculations to avoid re-instantiating models
var _aabb_cache: Dictionary = {}  # model_path -> AABB

# Spike wall chain tracking
var next_spike_wall_z: float = 0.0  # Next Z position for spike wall chain

# Plane spawning (aerial NPC) - global cooldown, spawns at chunk end
var plane_spawn_chance: float = 0.25  # 25% chance per chunk (high frequency)
var plane_cooldown_distance: float = 150.0  # ~7 sec at typical speed (very frequent)
var plane_last_spawn_z: float = 999999.0  # Z position of last plane spawn (positive = no spawn yet)
var plane_safe_chunks: int = 3  # Start spawning very early

func _init(config: Dictionary) -> void:
	terrain_width = config.get("terrain_width", 36.0)
	chunk_size = config.get("chunk_size", Vector2(100, 50))
	tree_density = config.get("tree_density", 0.5)
	num_lanes = config.get("num_lanes", 5)
	rock_safe_chunks = config.get("rock_safe_chunks", 2)
	slope_angle = config.get("slope_angle", 12.0)
	
	# Calculate noise compensation based on terrain noise settings
	# noise_height affects terrain variation, grid_jitter adds more uncertainty
	var noise_height: float = config.get("noise_height", 1.0)
	var grid_jitter: float = config.get("grid_jitter", 0.35)
	# Compensation = base noise variation + jitter effect
	noise_compensation = noise_height * 0.25 + grid_jitter * 0.15
	
	# Apply noise compensation to all height offsets
	height_offset_tree += noise_compensation
	height_offset_rock += noise_compensation
	height_offset_building += noise_compensation
	height_offset_npc += noise_compensation
	height_offset_spike += noise_compensation
	
	# Create zone manager with noise-based zones
	var ZoneManagerScript := preload("res://scripts/terrain/zone_manager.gd")
	zone_manager = ZoneManagerScript.new({
		"seed": config.get("seed", 42),
		"noise_scale": 0.015,  # Larger patches
		"forest_threshold": -0.1,
		"building_threshold": 0.1,
	})

## Get cached PackedScene (avoids repeated load() calls)
func _get_cached_scene(model_path: String) -> PackedScene:
	if _scene_cache.has(model_path):
		return _scene_cache[model_path]
	var scene := load(model_path) as PackedScene
	if scene:
		_scene_cache[model_path] = scene
	return scene

## Get cached AABB for a model (avoids re-instantiating just for size)
func _get_cached_aabb(model_path: String) -> AABB:
	if _aabb_cache.has(model_path):
		return _aabb_cache[model_path]
	# Need to instantiate once to get AABB
	var scene := _get_cached_scene(model_path)
	if not scene:
		return AABB()
	var temp := scene.instantiate()
	var aabb := _get_model_aabb(temp)
	temp.queue_free()
	_aabb_cache[model_path] = aabb
	return aabb

func set_hole_manager(manager: RefCounted) -> void:
	hole_manager = manager

## Calculate player's travel distance (in meters) from chunk_index
func _get_distance_from_chunk(chunk_index: int) -> float:
	return chunk_index * chunk_size.y

## Select a random object from category, filtered by distance
func _select_object_for_distance(category: int, rng: RandomNumberGenerator, distance: float) -> RefCounted:
	var objects: Array = ObjectConfigScript.get_objects_by_category(category)
	if objects.is_empty():
		return null
	
	# Filter by distance
	var available: Array = []
	var total_weight: float = 0.0
	
	for obj in objects:
		if DistanceConfigScript.can_spawn_at_distance(obj.id, distance):
			available.append(obj)
			total_weight += obj.spawn_chance
	
	if available.is_empty():
		return null
	
	# Random selection based on weight
	var roll := rng.randf() * total_weight
	var cumulative: float = 0.0
	
	for obj in available:
		cumulative += obj.spawn_chance
		if roll <= cumulative:
			return obj
	
	return available[-1]

## Get object pool singleton (lazy initialization)
func _get_pool() -> Node:
	if not _object_pool:
		_object_pool = Engine.get_main_loop().root.get_node_or_null("ObjectPool")
	return _object_pool

## Return object to pool for reuse when chunk is cleaned up
func return_object_to_pool(obj: Node3D, model_path: String, category: int) -> void:
	var pool := _get_pool()
	if pool:
		pool.return_object(obj, model_path, category)
	else:
		obj.queue_free()

## Main spawn function - call this for each chunk
## Uses noise-based zone sampling at each spawn position
func spawn_objects(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	# Clear previous spawn positions for this chunk
	spawned_positions[chunk_index] = []
	
	# FIRST: Spawn spike wall chains (before other objects to reserve space)
	if chunk_index >= spike_wall_safe_chunks:
		_spawn_spike_wall_chains(chunk, chunk_index, get_height_func)
	
	# Spawn rocks everywhere (regardless of zone)
	if chunk_index >= rock_safe_chunks:
		_spawn_rocks(chunk, chunk_index, get_height_func)
	
	# Spawn friend NPC clusters (random meadows with animals)
	if chunk_index >= npc_friend_safe_chunks:
		_spawn_npc_clusters(chunk, chunk_index, get_height_func)
	
	# Spawn enemy NPC clusters
	if chunk_index >= npc_enemy_safe_chunks:
		_spawn_enemy_npc_clusters(chunk, chunk_index, get_height_func)
	
	# Try to spawn enemy plane (aerial NPC with global cooldown)
	if chunk_index >= plane_safe_chunks:
		_try_spawn_plane(chunk, chunk_index, get_height_func)
	
	# Spawn trees, buildings, and building enemies based on position-level zone checking
	_spawn_zone_objects(chunk, chunk_index, get_height_func)

## Async version of spawn_objects - spreads work across multiple frames
## Returns when all objects are spawned
func spawn_objects_async(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	# Clear previous spawn positions for this chunk
	spawned_positions[chunk_index] = []
	
	# FIRST: Spawn spike wall chains (before other objects to reserve space)
	if chunk_index >= spike_wall_safe_chunks:
		_spawn_spike_wall_chains(chunk, chunk_index, get_height_func)
	
	# Yield after spike walls
	if not _is_chunk_valid(chunk):
		return
	await _yield_frame(chunk)
	
	# Spawn rocks everywhere (regardless of zone)
	if chunk_index >= rock_safe_chunks:
		await _spawn_rocks_async(chunk, chunk_index, get_height_func)
	
	if not _is_chunk_valid(chunk):
		return
	
	# Spawn friend NPC clusters (random meadows with animals)
	if chunk_index >= npc_friend_safe_chunks:
		_spawn_npc_clusters(chunk, chunk_index, get_height_func)
	
	# Spawn enemy NPC clusters
	if chunk_index >= npc_enemy_safe_chunks:
		_spawn_enemy_npc_clusters(chunk, chunk_index, get_height_func)
	
	# Yield after NPC clusters
	if not _is_chunk_valid(chunk):
		return
	await _yield_frame(chunk)
	
	# Try to spawn enemy plane (aerial NPC with global cooldown)
	if chunk_index >= plane_safe_chunks:
		_try_spawn_plane(chunk, chunk_index, get_height_func)
	
	# Spawn trees, buildings, and building enemies based on position-level zone checking
	await _spawn_zone_objects_async(chunk, chunk_index, get_height_func)
	
	# Spawn collectible items
	if chunk_index >= item_safe_chunks:
		await _spawn_items_async(chunk, chunk_index, get_height_func)

## Helper function to check if chunk is still valid
func _is_chunk_valid(chunk: Node3D) -> bool:
	return is_instance_valid(chunk) and not chunk.is_queued_for_deletion() and chunk.is_inside_tree()

## Helper to yield one frame (gets tree from chunk)
func _yield_frame(chunk: Node3D) -> void:
	if _is_chunk_valid(chunk):
		var tree := chunk.get_tree()
		if tree:
			await tree.process_frame

## Async version of rock spawning - yields every few objects  
func _spawn_rocks_async(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 99999)
	
	var area := chunk_size.x * chunk_size.y
	var object_count := int(area * rock_density / 100.0)
	object_count = max(object_count, 1)
	
	var batch_size := 5  # Spawn 5 rocks before yielding
	var spawned := 0
	
	var current_distance := _get_distance_from_chunk(chunk_index)
	
	for i in range(object_count):
		if not _is_chunk_valid(chunk):
			return
			
		var obj_data: RefCounted = _select_object_for_distance(ObjectConfigScript.Category.ROCK, rng, current_distance)
		if not obj_data:
			continue
		
		var margin := 0.5  # Spawn rocks close to edges
		var x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
		var local_z := rng.randf_range(-chunk_size.y + margin, -margin)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if _is_near_player_spawn(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 1.5):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var obj: Node3D = _create_object(obj_data, rng, ObjectConfigScript.Category.ROCK)
		if not obj:
			continue
		
		obj.position = Vector3(x, height + height_offset_rock, local_z)
		# Rocks can have slight random tilt for natural look
		obj.rotation.x = rng.randf_range(-0.15, 0.15)
		obj.rotation.z = rng.randf_range(-0.15, 0.15)
		obj.rotation.y = rng.randf_range(0, TAU)
		
		var variation: float = obj_data.height_variation
		var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(obj, target_h, obj_data.model_path)
		
		chunk.add_child.call_deferred(obj)
		_register_spawn_position(x, local_z, chunk_index)
		
		spawned += 1
		if spawned % batch_size == 0:
			await _yield_frame(chunk)

## Async version of zone objects spawning - yields periodically
func _spawn_zone_objects_async(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 54321)
	
	# Check for no_enemy_building boost early
	var gm_async: Node = Engine.get_main_loop().root.get_node_or_null("/root/GameManager")
	var building_enemies_blocked_async: bool = gm_async and gm_async.has_boost("no_enemy_building")
	
	# Calculate how many spawn attempts based on combined densities
	var area := chunk_size.x * chunk_size.y
	var combined_density := tree_density + building_density + enemy_density
	var spawn_attempts := int(area * combined_density / 100.0 * 1.5)  # Extra attempts due to zone filtering
	spawn_attempts = max(spawn_attempts, 5)
	
	var chunk_start_z := -chunk_index * chunk_size.y
	var batch_size := 10  # Process 10 spawn attempts before yielding
	
	for i in range(spawn_attempts):
		if not _is_chunk_valid(chunk):
			return
			
		var margin := 1.0  # Spawn trees/buildings close to edges
		var x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
		var local_z := rng.randf_range(-chunk_size.y + margin, -margin)
		
		# Convert to world Z for zone sampling
		var world_z := chunk_start_z + local_z
		
		# Skip if in hole area
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		# Skip if near player spawn zone
		if _is_near_player_spawn(x, local_z, chunk_index):
			continue
		
		# Get zone data at this specific position
		var zone_data: Dictionary = zone_manager.get_zone_at_position(x, world_z)
		var forest_weight: float = zone_data.forest_weight
		var building_weight: float = zone_data.building_weight
		
		# Decide what to spawn based on zone weights
		var roll := rng.randf()
		var category: int = -1
		
		if forest_weight > 0.0 and roll < forest_weight:
			# Try to spawn tree
			category = ObjectConfigScript.Category.TREE
		elif building_weight > 0.0 and roll >= forest_weight:
			# Try to spawn building (with safe chunk check)
			if chunk_index >= building_safe_chunks:
				# 25% chance for large building, 75% for small building
				if rng.randf() < 0.25:
					category = ObjectConfigScript.Category.BUILDING_LARGE
				else:
					category = ObjectConfigScript.Category.BUILDING
		
		# Additionally, try to spawn building enemy with separate probability
		var enemy_roll := rng.randf()
		var should_spawn_enemy := false
		if chunk_index >= enemy_safe_chunks and not building_enemies_blocked_async:
			# Building enemies can spawn in both zones but more likely in building zones
			var enemy_chance := enemy_density / 10.0  # Base chance
			if building_weight > 0.5:
				enemy_chance *= 1.5  # More building enemies near buildings
			should_spawn_enemy = enemy_roll < enemy_chance
		
		# Spawn building enemy if rolled (higher priority than decoration)
		if should_spawn_enemy:
			_try_spawn_at_position(chunk, chunk_index, get_height_func, x, local_z, 
								   ObjectConfigScript.Category.BUILDING_ENEMY, rng)
		elif category >= 0:
			_try_spawn_at_position(chunk, chunk_index, get_height_func, x, local_z, 
								   category, rng)
		
		# Yield every batch_size attempts
		if (i + 1) % batch_size == 0:
			await _yield_frame(chunk)

## Spawn spike wall chains across the terrain
## Chains are generated first to reserve space before other objects
func _spawn_spike_wall_chains(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	# Check for no_enemy_building boost
	var game_manager: Node = Engine.get_main_loop().root.get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_boost("no_enemy_building"):
		return
	
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 55555 + 12345)  # Unique seed for spike walls
	
	# Initialize next_spike_wall_z on first valid chunk
	if next_spike_wall_z == 0.0:
		next_spike_wall_z = -spike_wall_safe_chunks * chunk_size.y - rng.randf_range(spike_wall_min_spacing, spike_wall_max_spacing)
	
	# Calculate chunk Z range
	var chunk_start_z := -chunk_index * chunk_size.y
	var chunk_end_z := chunk_start_z - chunk_size.y
	
	# Check if any chains should spawn in this chunk
	while next_spike_wall_z > chunk_end_z and next_spike_wall_z <= chunk_start_z:
		# Spawn a chain at this Z position
		_create_spike_wall_chain(chunk, chunk_index, next_spike_wall_z, rng, get_height_func)
		
		# Calculate next chain position
		next_spike_wall_z -= rng.randf_range(spike_wall_min_spacing, spike_wall_max_spacing)

## Calculate the actual width of the spike wall model from its bounding box (CACHED)
func _get_spike_wall_actual_width(spike_wall_data: RefCounted) -> float:
	var aabb := _get_cached_aabb(spike_wall_data.model_path)
	if aabb.size == Vector3.ZERO:
		return spike_wall_width  # Fallback to config value
	# Wall width is the X dimension (assuming wall faces Z direction)
	return aabb.size.x

## Create a single spike wall chain (3-10 connected walls)
func _create_spike_wall_chain(chunk: Node3D, chunk_index: int, base_z: float, rng: RandomNumberGenerator, get_height_func: Callable) -> void:
	# Check if spike walls are unlocked at current distance
	var current_distance := _get_distance_from_chunk(chunk_index)
	if not DistanceConfigScript.can_spawn_at_distance("enemy_spike_wall", current_distance):
		return
	
	var spike_wall_data: RefCounted = ObjectConfigScript.get_spike_wall()
	if not spike_wall_data:
		return
	
	# Get actual wall width from model bounding box
	var actual_wall_width := _get_spike_wall_actual_width(spike_wall_data)
	
	# Scale factor for walls (20% smaller)
	var wall_scale_factor := 0.8
	# Spacing between walls - scaled width with significant overlap to ensure tight fit
	var wall_spacing := actual_wall_width * wall_scale_factor * 0.65
	
	# Random starting X position (can start anywhere across terrain)
	var start_x := rng.randf_range(-terrain_width / 2 + 1.5, terrain_width / 2 - 1.5)
	
	# Random chain count
	var wall_count := rng.randi_range(spike_wall_min_count, spike_wall_max_count)
	
	# Random initial direction (primarily perpendicular to travel, but can be diagonal)
	# Base angle: 0 degrees means chain extends along X axis (perpendicular to player travel)
	# with +/- 30 degrees variation for diagonal chains
	var chain_direction := deg_to_rad(rng.randf_range(-30.0, 30.0))
	
	var current_x := start_x
	var current_z := base_z
	
	# Convert to local chunk Z coordinate
	var chunk_start_z := -chunk_index * chunk_size.y

	for i in range(wall_count):
		# Convert to local Z
		var local_z := current_z - chunk_start_z
		
		# Check bounds
		if current_x < -terrain_width / 2 + 0.5 or current_x > terrain_width / 2 - 0.5:
			break
		if local_z < -chunk_size.y or local_z > 0:
			break
		
		# Skip if near a hole
		if _is_near_hole(current_x, local_z, chunk_index):
			# Try to skip this position and continue
			current_x += cos(chain_direction) * wall_spacing
			current_z += sin(chain_direction) * wall_spacing * 0.3
			continue
		
		# Get terrain height
		var height: float = get_height_func.call(current_x, local_z, chunk_index)
		
		# Create the spike wall
		var wall: StaticBody3D = _create_building_enemy(spike_wall_data, rng)
		if not wall:
			continue
		
		wall.position = Vector3(current_x, height + height_offset_spike, local_z)
		# Wall rotation: perpendicular to chain direction (wall faces the player)
		# chain_direction is the direction we're building the chain
		# wall should face perpendicular to that (along Z axis when chain is along X)
		wall.rotation.y = chain_direction
		
		# Scale to target height
		var variation: float = spike_wall_data.height_variation
		var target_h: float = spike_wall_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(wall, target_h, spike_wall_data.model_path)
		
		# Apply additional 20% size reduction
		wall.scale *= wall_scale_factor
		
		chunk.add_child.call_deferred(wall)
		
		# Register position to prevent other objects spawning here
		_register_spawn_position(current_x, local_z, chunk_index)
		# Also register nearby positions to create larger exclusion zone
		_register_spawn_position(current_x - 1.5, local_z, chunk_index)
		_register_spawn_position(current_x + 1.5, local_z, chunk_index)
		
		# Move to next wall position along the chain direction (tight spacing)
		current_x += cos(chain_direction) * wall_spacing
		current_z += sin(chain_direction) * wall_spacing * 0.3  # Slight Z movement for curve
		
		# Add slight angle variation for curve effect (but keep it subtle)
		var angle_change := deg_to_rad(rng.randf_range(-spike_wall_max_angle, spike_wall_max_angle))
		# Dampen the change to prevent too sharp turns
		chain_direction += angle_change * 0.5

## Spawn rocks (zone-independent)
func _spawn_rocks(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 99999)
	
	var area := chunk_size.x * chunk_size.y
	var object_count := int(area * rock_density / 100.0)
	object_count = max(object_count, 1)
	
	var current_distance := _get_distance_from_chunk(chunk_index)
	
	for i in range(object_count):
		var obj_data: RefCounted = _select_object_for_distance(ObjectConfigScript.Category.ROCK, rng, current_distance)
		if not obj_data:
			continue
		
		var margin := 0.5  # Spawn rocks close to edges
		var x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
		var local_z := rng.randf_range(-chunk_size.y + margin, -margin)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if _is_near_player_spawn(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 1.5):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var obj: Node3D = _create_object(obj_data, rng, ObjectConfigScript.Category.ROCK)
		if not obj:
			continue
		
		obj.position = Vector3(x, height + height_offset_rock, local_z)
		# Rocks can have slight random tilt for natural look
		obj.rotation.x = rng.randf_range(-0.15, 0.15)
		obj.rotation.z = rng.randf_range(-0.15, 0.15)
		obj.rotation.y = rng.randf_range(0, TAU)
		
		var variation: float = obj_data.height_variation
		var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(obj, target_h, obj_data.model_path)
		
		chunk.add_child.call_deferred(obj)
		_register_spawn_position(x, local_z, chunk_index)

## Async item spawning - spawns collectible items based on distance-unlocked rarity
func _spawn_items_async(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 88888)
	
	# Only try to spawn ONE item per chunk with low probability
	if rng.randf() > 0.25:  # 25% chance per chunk to have an item
		return
	
	# Calculate chunk Z position (world space)
	var chunk_start_z := -chunk_index * chunk_size.y
	
	# Check minimum spacing from last item
	var distance_from_last := absf(chunk_start_z - item_last_spawn_z)
	if distance_from_last < item_min_spacing:
		return
	
	# Calculate current distance for item unlocking
	var current_distance := _get_distance_from_chunk(chunk_index)
	
	# Get random item based on distance-unlocked rarities
	var item_data = ItemConfigScript.get_random_item_for_distance(current_distance, rng)
	if not item_data:
		return
	
	var margin := 2.0  # Keep items away from edges
	var x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
	var local_z := rng.randf_range(-chunk_size.y + margin, -margin)
	
	# Skip if near hole
	if _is_near_hole(x, local_z, chunk_index):
		return
	
	# Skip if too close to player spawn
	if _is_near_player_spawn(x, local_z, chunk_index):
		return
	
	# Check minimum distance from other spawned objects
	if not _is_position_available(x, local_z, chunk_index, min_object_distance):
		return
	
	var height: float = get_height_func.call(x, local_z, chunk_index)
	
	# Create item pickup instance
	var item: Node3D = ItemPickupScene.instantiate()
	if not item:
		return
	
	# Configure the item
	item.item_id = item_data.id
	item.position = Vector3(x, height + height_offset_item, local_z)
	
	# Load and set the 3D model if available
	if item_data.model_path != "":
		var model_scene := _get_cached_scene(item_data.model_path)
		if model_scene:
			var model_node: Node3D = item.get_node_or_null("Model")
			if model_node:
				var model_instance := model_scene.instantiate()
				model_node.add_child(model_instance)
				# Scale model to reasonable size
				_scale_to_target_height(model_instance, 0.8, item_data.model_path)
	
	chunk.add_child.call_deferred(item)
	_register_spawn_position(x, local_z, chunk_index)
	
	# Track this spawn position for minimum spacing
	item_last_spawn_z = chunk_start_z + local_z
	
	print("[ItemSpawner] Spawned %s at distance %.0fm" % [item_data.id, current_distance])

## Spawn NPC clusters - random meadows with groups of same-type animals
func _spawn_npc_clusters(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 77777)
	
	# 70% chance to have an NPC cluster in this chunk
	if rng.randf() > 0.7:
		return
	
	# Pick random center position for the cluster
	var margin := 3.0  # Allow NPC clusters closer to edges
	var cluster_x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
	var cluster_z := rng.randf_range(-chunk_size.y + margin, -margin)
	
	# Skip if near hole or player spawn
	if _is_near_hole(cluster_x, cluster_z, chunk_index):
		return
	
	if _is_near_player_spawn(cluster_x, cluster_z, chunk_index):
		return
	
	var current_distance := _get_distance_from_chunk(chunk_index)
	
	# Get all available friend NPCs for this distance
	var all_npcs: Array = ObjectConfigScript.get_objects_by_category(ObjectConfigScript.Category.NPC_FRIEND)
	var available_npcs: Array = []
	var total_weight: float = 0.0
	
	for obj in all_npcs:
		if DistanceConfigScript.can_spawn_at_distance(obj.id, current_distance):
			available_npcs.append(obj)
			total_weight += obj.spawn_chance
	
	if available_npcs.is_empty():
		return
	
	# Pick primary animal type based on spawn_chance weights
	var primary_data: RefCounted = _select_weighted_from_array(available_npcs, total_weight, rng)
	if not primary_data:
		return
	
	# Group size: 1-5 animals
	var animal_count := rng.randi_range(1, 5)
	var cluster_radius := 4.0  # Smaller radius for tighter groups
	
	# 50% chance to have one different animal in the group (if more than 1 animal and multiple types available)
	var has_different := animal_count > 1 and available_npcs.size() > 1 and rng.randf() < 0.5
	var different_index := -1
	var different_data: RefCounted = null
	
	if has_different:
		different_index = rng.randi_range(0, animal_count - 1)
		# Pick a different animal type
		var other_npcs: Array = []
		var other_weight: float = 0.0
		for obj in available_npcs:
			if obj.id != primary_data.id:
				other_npcs.append(obj)
				other_weight += obj.spawn_chance
		if not other_npcs.is_empty():
			different_data = _select_weighted_from_array(other_npcs, other_weight, rng)
	
	for i in range(animal_count):
		# Use different animal at the designated index, otherwise primary
		var obj_data: RefCounted = primary_data
		if i == different_index and different_data:
			obj_data = different_data
		
		# Random position within cluster
		var angle := rng.randf_range(0, TAU)
		var dist := rng.randf_range(0.5, cluster_radius)
		var x := cluster_x + cos(angle) * dist
		var local_z := cluster_z + sin(angle) * dist
		
		# Clamp to terrain bounds
		x = clampf(x, -terrain_width / 2 + 0.5, terrain_width / 2 - 0.5)
		local_z = clampf(local_z, -chunk_size.y + 0.5, -0.5)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 2.0):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var obj: Node3D = _create_object(obj_data, rng, ObjectConfigScript.Category.NPC_FRIEND)
		if not obj:
			continue
		
		obj.position = Vector3(x, height + height_offset_npc, local_z)
		obj.rotation.y = rng.randf_range(0, TAU)
		
		# Scale to target height
		var variation: float = obj_data.height_variation
		var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(obj, target_h, obj_data.model_path)
		
		chunk.add_child.call_deferred(obj)
		_register_spawn_position(x, local_z, chunk_index)


## Helper: Select weighted random object from array
func _select_weighted_from_array(objects: Array, total_weight: float, rng: RandomNumberGenerator) -> RefCounted:
	if objects.is_empty() or total_weight <= 0:
		return null
	var roll := rng.randf() * total_weight
	var cumulative: float = 0.0
	for obj in objects:
		cumulative += obj.spawn_chance
		if roll <= cumulative:
			return obj
	return objects[-1]


## Spawn enemy NPC clusters (groups of 3-8 enemies, max 2 catapults)
func _spawn_enemy_npc_clusters(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	# Check for no_enemy_npc boost
	var game_manager: Node = Engine.get_main_loop().root.get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_boost("no_enemy_npc"):
		return
	
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 55555)
	
	# 49% chance to have an enemy NPC cluster (70% * 0.7 = ~49% - 30% less than friend NPCs)
	if rng.randf() > 0.49:
		return
	
	# Pick random center position for the cluster
	var margin := 3.0  # Allow enemy NPC clusters closer to edges
	var cluster_x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
	var cluster_z := rng.randf_range(-chunk_size.y + margin, -margin)
	
	# Skip if near hole or player spawn
	if _is_near_hole(cluster_x, cluster_z, chunk_index):
		return
	
	if _is_near_player_spawn(cluster_x, cluster_z, chunk_index):
		return
	
	# Spawn 3-8 enemy NPCs in the cluster (max 2 catapults)
	var enemy_count := rng.randi_range(3, 8)
	var cluster_radius := 6.0
	var catapult_count := 0
	const MAX_CATAPULTS := 2
	var current_distance := _get_distance_from_chunk(chunk_index)
	
	for i in range(enemy_count):
		var obj_data: RefCounted = _select_object_for_distance(ObjectConfigScript.Category.NPC_ENEMY, rng, current_distance)
		if not obj_data:
			continue
		
		# Limit catapults per group
		if obj_data.id == "npc_catapult":
			if catapult_count >= MAX_CATAPULTS:
				# Re-roll for non-catapult enemy
				for _reroll in range(5):
					obj_data = _select_object_for_distance(ObjectConfigScript.Category.NPC_ENEMY, rng, current_distance)
					if obj_data and obj_data.id != "npc_catapult":
						break
				if not obj_data or obj_data.id == "npc_catapult":
					continue
			else:
				catapult_count += 1
		
		# Random position within cluster
		var angle := rng.randf_range(0, TAU)
		var dist := rng.randf_range(0.5, cluster_radius)
		var x := cluster_x + cos(angle) * dist
		var local_z := cluster_z + sin(angle) * dist
		
		# Clamp to terrain bounds
		x = clampf(x, -terrain_width / 2 + 0.5, terrain_width / 2 - 0.5)
		local_z = clampf(local_z, -chunk_size.y + 0.5, -0.5)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 2.5):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var obj: Node3D = _create_object(obj_data, rng, ObjectConfigScript.Category.NPC_ENEMY)
		if not obj:
			continue
		
		obj.position = Vector3(x, height + height_offset_npc, local_z)
		obj.rotation.y = rng.randf_range(0, TAU)
		
		# Scale to target height
		var variation: float = obj_data.height_variation
		var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(obj, target_h, obj_data.model_path)
		
		chunk.add_child.call_deferred(obj)
		_register_spawn_position(x, local_z, chunk_index)


## Try to spawn an enemy plane (aerial NPC)
## Planes have global cooldown and spawn at the end of the chunk, flying toward player
func _try_spawn_plane(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	# Check if aerial NPCs are unlocked at current distance
	var current_distance := _get_distance_from_chunk(chunk_index)
	if not DistanceConfigScript.can_spawn_aerial(current_distance):
		return
	
	# Use fully random seed for unique results every game
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	# Calculate current chunk Z position (start of this chunk in world coords)
	var chunk_start_z := -chunk_index * chunk_size.y
	var chunk_end_z := chunk_start_z - chunk_size.y  # End of chunk (further from player)
	
	# Check cooldown - need enough distance since last plane
	# Z goes negative as player progresses, so distance = last_spawn_z - chunk_end_z
	var distance_since_last := plane_last_spawn_z - chunk_end_z
	if distance_since_last < plane_cooldown_distance:
		return
	
	# Roll for spawn chance
	if rng.randf() > plane_spawn_chance:
		return
	
	# Get plane data from config
	var obj_data: RefCounted = ObjectConfigScript.get_object("npc_plane")
	if not obj_data:
		return
	
	# Spawn position: random X, at end of chunk, above terrain
	var x := rng.randf_range(-terrain_width / 2 + 5.0, terrain_width / 2 - 5.0)
	var local_z := -chunk_size.y * 2.5  # Spawn much further ahead (2.5 chunks ahead)
	
	# Get terrain height and add altitude
	var height: float = get_height_func.call(x, local_z, chunk_index)
	var altitude := rng.randf_range(12.0, 18.0)  # Random altitude above terrain
	var spawn_y := height + altitude
	
	# Create plane instance
	var plane := Node3D.new()
	plane.set_script(PlaneNPCScript)
	plane.name = "PlaneNPC_%d" % chunk_index
	
	# Set plane properties before adding to tree
	plane.set("coin_value", obj_data.coins)
	plane.set("damage", obj_data.damage)
	
	# Position the plane (it will fly forward towards player)
	plane.position = Vector3(x, spawn_y, local_z)
	
	# Load the model (cached)
	var model_scene := _get_cached_scene(obj_data.model_path)
	if model_scene:
		var model: Node3D = model_scene.instantiate() as Node3D
		if model:
			# Apply color palette material
			_disable_shadows_recursive(model)
			
			# Scale to target height
			_scale_to_target_height(model, obj_data.target_height, obj_data.model_path)
			
			# Make plane 75% smaller (25% of original size)
			# model.scale *= 0.25
			
			# Name the model so plane.gd can find it
			model.name = "Model"
			plane.add_child(model)
	
	# IMPORTANT: Add plane to scene root, NOT to chunk!
	# This prevents the plane from being deleted when the chunk is recycled
	# Convert local position to global (chunk position affects it)
	var chunk_global_pos := chunk.global_position if chunk is Node3D else Vector3.ZERO
	plane.global_position = chunk_global_pos + plane.position
	
	# Add to root
	chunk.get_tree().root.add_child(plane)
	
	# Record spawn for cooldown tracking
	plane_last_spawn_z = chunk_end_z


## Spawn zone-dependent objects (trees, buildings, enemies) with per-position zone check
func _spawn_zone_objects(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 54321)
	
	# Check for no_enemy_building boost early
	var gm_sync: Node = Engine.get_main_loop().root.get_node_or_null("/root/GameManager")
	var building_enemies_blocked_sync: bool = gm_sync and gm_sync.has_boost("no_enemy_building")
	
	# Calculate how many spawn attempts based on combined densities
	var area := chunk_size.x * chunk_size.y
	var combined_density := tree_density + building_density + enemy_density
	var spawn_attempts := int(area * combined_density / 100.0 * 1.5)  # Extra attempts due to zone filtering
	spawn_attempts = max(spawn_attempts, 5)
	
	var chunk_start_z := -chunk_index * chunk_size.y
	
	for i in range(spawn_attempts):
		var margin := 1.0  # Spawn zone objects close to edges
		var x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
		var local_z := rng.randf_range(-chunk_size.y + margin, -margin)
		
		# Convert to world Z for zone sampling
		var world_z := chunk_start_z + local_z
		
		# Skip if in hole area
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		# Skip if near player spawn zone
		if _is_near_player_spawn(x, local_z, chunk_index):
			continue
		
		# Get zone data at this specific position
		var zone_data: Dictionary = zone_manager.get_zone_at_position(x, world_z)
		var forest_weight: float = zone_data.forest_weight
		var building_weight: float = zone_data.building_weight
		
		# Decide what to spawn based on zone weights
		var roll := rng.randf()
		var category: int = -1
		
		if forest_weight > 0.0 and roll < forest_weight:
			# Try to spawn tree
			category = ObjectConfigScript.Category.TREE
		elif building_weight > 0.0 and roll >= forest_weight:
			# Try to spawn building (with safe chunk check)
			if chunk_index >= building_safe_chunks:
				# 25% chance for large building, 75% for small building
				if rng.randf() < 0.25:
					category = ObjectConfigScript.Category.BUILDING_LARGE
				else:
					category = ObjectConfigScript.Category.BUILDING
		
		# Additionally, try to spawn building enemy with separate probability
		var enemy_roll := rng.randf()
		var should_spawn_enemy := false
		if chunk_index >= enemy_safe_chunks and not building_enemies_blocked_sync:
			# Building enemies can spawn in both zones but more likely in building zones
			var enemy_chance := enemy_density / 10.0  # Base chance
			if building_weight > 0.5:
				enemy_chance *= 1.5  # More building enemies near buildings
			should_spawn_enemy = enemy_roll < enemy_chance
		
		# Spawn building enemy if rolled (higher priority than decoration)
		if should_spawn_enemy:
			_try_spawn_at_position(chunk, chunk_index, get_height_func, x, local_z, 
								   ObjectConfigScript.Category.BUILDING_ENEMY, rng)
		elif category >= 0:
			_try_spawn_at_position(chunk, chunk_index, get_height_func, x, local_z, 
								   category, rng)

## Try to spawn a single object at a specific position
func _try_spawn_at_position(chunk: Node3D, chunk_index: int, get_height_func: Callable,
							x: float, local_z: float, category: int, rng: RandomNumberGenerator) -> bool:
	# Select random object from category, filtered by current distance
	var current_distance := _get_distance_from_chunk(chunk_index)
	var obj_data: RefCounted = _select_object_for_distance(category, rng, current_distance)
	if not obj_data:
		return false
	
	# Check minimum distance based on category
	var min_dist := min_object_distance
	if category == ObjectConfigScript.Category.BUILDING:
		min_dist = 4.0
	elif category == ObjectConfigScript.Category.BUILDING_LARGE:
		min_dist = 6.0  # Large buildings need more space
	elif category == ObjectConfigScript.Category.ROCK:
		min_dist = 1.5
	elif category == ObjectConfigScript.Category.NPC_FRIEND:
		min_dist = 3.0  # NPCs need space to wander
	
	if not _is_position_available(x, local_z, chunk_index, min_dist):
		return false
	
	var height: float = get_height_func.call(x, local_z, chunk_index)
	
	# Get height offset based on category
	var height_offset := 0.0
	match category:
		ObjectConfigScript.Category.TREE:
			height_offset = height_offset_tree
		ObjectConfigScript.Category.ROCK:
			height_offset = height_offset_rock
		ObjectConfigScript.Category.BUILDING, ObjectConfigScript.Category.BUILDING_LARGE:
			height_offset = height_offset_building
		ObjectConfigScript.Category.BUILDING_ENEMY:
			height_offset = height_offset_spike
		ObjectConfigScript.Category.NPC_FRIEND, ObjectConfigScript.Category.NPC_ENEMY:
			height_offset = height_offset_npc
	
	# Create object
	var obj: Node3D = _create_object(obj_data, rng, category)
	if not obj:
		return false
	
	obj.position = Vector3(x, height + height_offset, local_z)
	# Objects stand upright (vertical) - only Y rotation for random facing direction
	obj.rotation.y = rng.randf_range(0, TAU)
	
	# Scale to target height
	var variation: float = obj_data.height_variation
	var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
	_scale_to_target_height(obj, target_h, obj_data.model_path)
	
	chunk.add_child.call_deferred(obj)
	_register_spawn_position(x, local_z, chunk_index)
	return true

## Create an object instance based on category
## Uses object pool when available for better performance
func _create_object(obj_data: RefCounted, rng: RandomNumberGenerator, category: int) -> Node3D:
	var model_path: String = obj_data.model_path
	var pool := _get_pool()
	
	# Try to get from pool first
	if pool and pool.has_available(model_path, category):
		var pooled_obj: Node3D = pool.get_object(model_path, category)
		if pooled_obj:
			# Reconfigure pooled object with current data
			_reconfigure_object(pooled_obj, obj_data, category, rng)
			return pooled_obj
	
	# No pooled object available, create new one
	var obj: Node3D = null
	match category:
		ObjectConfigScript.Category.TREE:
			obj = _create_tree(obj_data, rng)
		ObjectConfigScript.Category.BUILDING:
			obj = _create_building(obj_data, rng)
		ObjectConfigScript.Category.BUILDING_LARGE:
			obj = _create_large_building(obj_data, rng)
		ObjectConfigScript.Category.BUILDING_ENEMY:
			obj = _create_building_enemy(obj_data, rng)
		ObjectConfigScript.Category.ROCK:
			obj = _create_rock(obj_data, rng)
		ObjectConfigScript.Category.NPC_FRIEND:
			obj = _create_friend_npc(obj_data, rng)
		ObjectConfigScript.Category.NPC_ENEMY:
			obj = _create_enemy_npc(obj_data, rng)
	
	# Store metadata for later pooling
	if obj:
		obj.set_meta("pool_model_path", model_path)
		obj.set_meta("pool_category", category)
	
	return obj

## Reconfigure a pooled object with new data
func _reconfigure_object(obj: Node3D, obj_data: RefCounted, category: int, rng: RandomNumberGenerator) -> void:
	# Reset transform
	obj.position = Vector3.ZERO
	obj.rotation = Vector3.ZERO
	obj.scale = Vector3.ONE
	
	# Update script properties based on category
	match category:
		ObjectConfigScript.Category.TREE, ObjectConfigScript.Category.BUILDING, ObjectConfigScript.Category.BUILDING_LARGE:
			if obj.has_method("set"):
				obj.set("coin_value", obj_data.coins)
				obj.set("object_id", obj_data.id)
				obj.set("object_name", obj_data.display_name)
			if obj is RigidBody3D:
				obj.freeze = true
				obj.linear_velocity = Vector3.ZERO
				obj.angular_velocity = Vector3.ZERO
		
		ObjectConfigScript.Category.BUILDING_ENEMY:
			if obj.has_method("set"):
				obj.set("damage", obj_data.damage)
				obj.set("coin_value", obj_data.coins)
				obj.set("object_id", obj_data.id)
				obj.set("object_name", obj_data.display_name)
		
		ObjectConfigScript.Category.ROCK:
			pass  # Rocks don't have special properties
		
		ObjectConfigScript.Category.NPC_FRIEND:
			# Handle golden variant for friend NPCs
			var is_golden := rng.randf() < GOLDEN_NPC_CHANCE
			var coins: int = obj_data.coins * GOLDEN_NPC_COIN_MULTIPLIER if is_golden else obj_data.coins
			
			if obj.has_method("set"):
				obj.set("coin_value", coins)
				obj.set("object_id", obj_data.id)
				obj.set("object_name", obj_data.display_name)
				obj.set("is_golden", is_golden)
			
			# Update groups and material for golden status
			if is_golden:
				if not obj.is_in_group("golden_npcs"):
					obj.add_to_group("golden_npcs")
				var model := obj.get_node_or_null("Model")
				if model:
					_apply_golden_material(model)
			else:
				if obj.is_in_group("golden_npcs"):
					obj.remove_from_group("golden_npcs")
				var model := obj.get_node_or_null("Model")
				if model:
					_remove_golden_material(model)
			
			# Reset NPC state
			if obj.has_method("_pool_reset"):
				obj.call("_pool_reset")
		
		ObjectConfigScript.Category.NPC_ENEMY:
			if obj.has_method("set"):
				obj.set("coin_value", obj_data.coins)
				obj.set("object_id", obj_data.id)
				obj.set("object_name", obj_data.display_name)
			# Reset NPC state
			if obj.has_method("_pool_reset"):
				obj.call("_pool_reset")

## Create a tree instance
func _create_tree(obj_data: RefCounted, rng: RandomNumberGenerator) -> RigidBody3D:
	var tree := RigidBody3D.new()
	tree.name = "Tree"
	tree.mass = 20.0
	tree.freeze = true
	tree.collision_layer = 0
	tree.collision_mask = 1
	tree.set_script(TreeScript)
	tree.set("coin_value", obj_data.coins)
	tree.set("object_id", obj_data.id)
	tree.set("object_name", obj_data.display_name)
	
	# Load model (cached)
	var model: Node3D = null
	var model_scene := _get_cached_scene(obj_data.model_path)
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_disable_shadows_recursive(model)
		tree.add_child(model)
	
	# Detection area with AABB-based collision
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	# Calculate bounding box from model and create collision
	if model:
		var aabb := _get_model_aabb(model)
		if aabb.size != Vector3.ZERO:
			var col_data := _create_collision_from_aabb(aabb, obj_data.collision_shape, 1.1)
			detect_area.add_child(col_data.collision_shape)
	
	tree.add_child(detect_area)
	
	return tree

## Create a building instance
func _create_building(obj_data: RefCounted, rng: RandomNumberGenerator) -> RigidBody3D:
	var building := RigidBody3D.new()
	building.name = "Building"
	building.mass = 50.0
	building.freeze = true
	building.collision_layer = 0
	building.collision_mask = 1
	building.set_script(BuildingScript)
	building.set("coin_value", obj_data.coins)
	building.set("object_id", obj_data.id)
	building.set("object_name", obj_data.display_name)
	
	# Load model (cached)
	var model: Node3D = null
	var model_scene := _get_cached_scene(obj_data.model_path)
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_disable_shadows_recursive(model)
		building.add_child(model)
	
	# Detection area with AABB-based collision
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	# Calculate bounding box from model and create collision
	if model:
		var aabb := _get_model_aabb(model)
		if aabb.size != Vector3.ZERO:
			var col_data := _create_collision_from_aabb(aabb, obj_data.collision_shape, 1.1)
			detect_area.add_child(col_data.collision_shape)
	
	building.add_child(detect_area)
	
	return building

## Create a large building instance (only destructible in supercharge)
func _create_large_building(obj_data: RefCounted, rng: RandomNumberGenerator) -> RigidBody3D:
	var building := RigidBody3D.new()
	building.name = "LargeBuilding"
	building.mass = 100.0  # Heavier than small buildings
	building.freeze = true
	building.collision_layer = 1  # Layer 1 so player (mask=1) collides with it
	building.collision_mask = 0  # Don't need to detect other objects
	building.set_script(LargeBuildingScript)
	building.set("coin_value", obj_data.coins)
	building.set("object_id", obj_data.id)
	building.set("object_name", obj_data.display_name)
	
	# Load model (cached)
	var model: Node3D = null
	var model_scene := _get_cached_scene(obj_data.model_path)
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_disable_shadows_recursive(model)
		building.add_child(model)
	
	# Calculate bounding box from model
	var aabb := AABB()
	if model:
		aabb = _get_model_aabb(model)
	
	if aabb.size != Vector3.ZERO:
		# Physical collision shape (blocks player) - slightly smaller
		var phys_data := _create_collision_from_aabb(aabb, obj_data.collision_shape, 0.9)
		phys_data.collision_shape.name = "PhysicsCollision"
		building.add_child(phys_data.collision_shape)
		
		# Detection area for script triggering (slightly larger)
		var detect_area := Area3D.new()
		detect_area.name = "DetectArea"
		detect_area.collision_layer = 0
		detect_area.collision_mask = 2
		detect_area.monitoring = true
		
		var detect_data := _create_collision_from_aabb(aabb, obj_data.collision_shape, 1.1)
		detect_area.add_child(detect_data.collision_shape)
		building.add_child(detect_area)
	
	return building

## Create a building enemy instance (spike, etc.)
func _create_building_enemy(obj_data: RefCounted, rng: RandomNumberGenerator) -> StaticBody3D:
	var enemy := StaticBody3D.new()
	enemy.name = "BuildingEnemy"
	enemy.add_to_group("building_enemies")
	enemy.collision_layer = 1
	enemy.collision_mask = 0
	enemy.set_script(SpikeScript)
	enemy.set("damage", obj_data.damage)
	enemy.set("coin_value", obj_data.coins)
	enemy.set("object_id", obj_data.id)
	enemy.set("object_name", obj_data.display_name)
	
	# Load model (cached)
	var model: Node3D = null
	var model_scene := _get_cached_scene(obj_data.model_path)
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_disable_shadows_recursive(model)
		enemy.add_child(model)
	
	# Calculate AABB from model for collision
	var aabb := AABB()
	if model:
		aabb = _get_model_aabb(model)
	
	if aabb.size != Vector3.ZERO:
		# Physical collision - slightly smaller
		var phys_data := _create_collision_from_aabb(aabb, obj_data.collision_shape, 0.7)
		enemy.add_child(phys_data.collision_shape)
		
		# Damage detection area - slightly larger
		var damage_area := Area3D.new()
		damage_area.name = "DamageArea"
		damage_area.collision_layer = 0
		damage_area.collision_mask = 2
		damage_area.monitoring = true
		
		var dmg_data := _create_collision_from_aabb(aabb, obj_data.collision_shape, 1.1)
		damage_area.add_child(dmg_data.collision_shape)
		enemy.add_child(damage_area)
	
	return enemy

## Create a rock instance
func _create_rock(obj_data: RefCounted, rng: RandomNumberGenerator) -> StaticBody3D:
	var rock := StaticBody3D.new()
	rock.name = "Rock"
	rock.add_to_group("rocks")
	rock.collision_layer = 4  # Layer 3 (separate from terrain for supercharge pass-through)
	rock.collision_mask = 0
	
	# Load model (cached) - uses materials from .blend, disable shadows/reflections
	var model: Node3D = null
	var model_scene := _get_cached_scene(obj_data.model_path)
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_disable_shadows_recursive(model)
		rock.add_child(model)
	
	# Calculate AABB and create collision based on collision_shape
	if model:
		var aabb := _get_model_aabb(model)
		if aabb.size != Vector3.ZERO:
			var col_data := _create_collision_from_aabb(aabb, obj_data.collision_shape, 0.9)
			rock.add_child(col_data.collision_shape)
	
	return rock

## Create a friend NPC instance (chicken, rabbit, etc.)
func _create_friend_npc(obj_data: RefCounted, rng: RandomNumberGenerator) -> CharacterBody3D:
	var npc := CharacterBody3D.new()
	npc.name = "FriendNPC"
	npc.add_to_group("npcs")
	npc.add_to_group("friend_npcs")
	npc.collision_layer = 0  # Don't block anything
	npc.collision_mask = 1   # Collide with terrain for walking
	npc.set_script(FriendNPCScript)
	
	# Check for golden variant (10% chance, 5x coins)
	var is_golden := rng.randf() < GOLDEN_NPC_CHANCE
	var coins: int = obj_data.coins * GOLDEN_NPC_COIN_MULTIPLIER if is_golden else obj_data.coins
	
	npc.set("coin_value", coins)
	npc.set("object_id", obj_data.id)  # Same ID for statistics
	npc.set("object_name", obj_data.display_name)
	npc.set("is_golden", is_golden)
	
	if is_golden:
		npc.add_to_group("golden_npcs")
		npc.name = "GoldenNPC"
	
	# Load model (separate from collision, will hop) - cached
	var model: Node3D = null
	var model_scene := _get_cached_scene(obj_data.model_path)
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_disable_shadows_recursive(model)
		
		# Apply golden material if golden variant
		if is_golden:
			_apply_golden_material(model)
		
		npc.add_child(model)
	
	# Use target_height for collision sizing (not unscaled AABB!)
	var h: float = obj_data.target_height
	
	# Terrain collision shape (capsule for walking) - based on target height
	var terrain_col := CollisionShape3D.new()
	terrain_col.name = "TerrainCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = h * 0.15  # Reasonable width relative to height
	capsule.height = h * 0.7
	terrain_col.position.y = capsule.height / 2
	terrain_col.shape = capsule
	npc.add_child(terrain_col)
	
	# Detection area for player collision - sphere at center of NPC
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = h * 0.6  # Larger hitbox for easier collection
	col_shape.shape = sphere
	col_shape.position.y = h / 2
	detect_area.add_child(col_shape)
	npc.add_child(detect_area)
	
	return npc

## Create an enemy NPC instance (dark pawn, dark knight, horse knight, catapult, etc.)
func _create_enemy_npc(obj_data: RefCounted, rng: RandomNumberGenerator) -> CharacterBody3D:
	var npc := CharacterBody3D.new()
	npc.name = "EnemyNPC"
	npc.add_to_group("npcs")
	npc.add_to_group("enemy_npcs")
	npc.collision_layer = 0  # Don't block anything
	npc.collision_mask = 1   # Collide with terrain for walking
	
	# Use appropriate script based on NPC type
	if obj_data.id == "npc_catapult":
		npc.set_script(CatapultNPCScript)
		npc.name = "CatapultNPC"
	elif obj_data.id == "npc_wizard":
		npc.set_script(WizardNPCScript)
		npc.name = "WizardNPC"
	else:
		npc.set_script(EnemyNPCScript)
	
	npc.set("damage", obj_data.damage)
	npc.set("coin_value", obj_data.coins)
	npc.set("object_id", obj_data.id)
	npc.set("object_name", obj_data.display_name)
	
	# Load model (separate from collision, will hop when chasing) - cached
	var model: Node3D = null
	var model_scene := _get_cached_scene(obj_data.model_path)
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_disable_shadows_recursive(model)
		npc.add_child(model)
	
	# Use target_height for collision sizing (not unscaled AABB!)
	var h: float = obj_data.target_height
	
	# Terrain collision shape (capsule for walking) - based on target height
	var terrain_col := CollisionShape3D.new()
	terrain_col.name = "TerrainCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = h * 0.15
	capsule.height = h * 0.7
	terrain_col.position.y = capsule.height / 2
	terrain_col.shape = capsule
	npc.add_child(terrain_col)
	
	# Detection area for player collision - box based on target height
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	
	# Catapult needs a custom smaller hitbox (just base, not the arm)
	if obj_data.id == "npc_catapult":
		box.size = Vector3(2.5, 2.5, 2.5)
		col_shape.position = Vector3(0.0, 1.25, 0.0)
	else:
		# Box sized relative to target height - LARGER for reliable detection
		# Width/depth at least 1.5m (larger than player radius)
		var box_width := maxf(h * 0.7, 1.5)
		var box_height := maxf(h * 1.0, 1.5)
		box.size = Vector3(box_width, box_height, box_width)
		col_shape.position.y = box_height / 2
	col_shape.shape = box
	detect_area.add_child(col_shape)
	npc.add_child(detect_area)
	
	return npc

# ========== HELPER FUNCTIONS ==========

func _is_near_hole(x: float, z: float, chunk_index: int) -> bool:
	if hole_manager:
		return hole_manager.get_distance_to_nearest_hole(x, z, chunk_index) < 5.0
	return false

## Check if position is within player spawn safe zone (no objects should spawn here)
func _is_near_player_spawn(x: float, local_z: float, chunk_index: int) -> bool:
	# Convert local chunk Z to world Z
	var world_z := -chunk_index * chunk_size.y + local_z
	# Calculate horizontal distance from player spawn (ignore Y)
	var dx := x - player_spawn_position.x
	var dz := world_z - player_spawn_position.z
	var dist := sqrt(dx * dx + dz * dz)
	return dist < player_spawn_safe_radius

func _is_position_available(x: float, z: float, chunk_index: int, min_dist: float = -1.0) -> bool:
	if min_dist < 0:
		min_dist = min_object_distance
	
	if not spawned_positions.has(chunk_index):
		return true
	
	var positions: Array = spawned_positions[chunk_index]
	for pos in positions:
		var p: Vector2 = pos
		var dist := Vector2(x, z).distance_to(p)
		if dist < min_dist:
			return false
	
	return true

func _register_spawn_position(x: float, z: float, chunk_index: int) -> void:
	if not spawned_positions.has(chunk_index):
		spawned_positions[chunk_index] = []
	spawned_positions[chunk_index].append(Vector2(x, z))

## Scale object to target height. For NPCs, also calculates model Y offset.
## Uses cached AABB for consistent sizing.
func _scale_to_target_height(node: Node3D, target_height: float, model_path: String = "") -> void:
	# For CharacterBody3D (NPCs), specifically find the Model child
	var model: Node3D = null
	if node is CharacterBody3D:
		model = node.get_node_or_null("Model")
	else:
		for child in node.get_children():
			if child.name == "Model" or child is MeshInstance3D:
				model = child
				break
	
	if not model:
		node.scale = Vector3.ONE * 0.5
		return
	
	# Always use cached AABB for consistency (avoids issues with model state)
	var aabb: AABB
	if model_path != "":
		aabb = _get_cached_aabb(model_path)  # This properly caches and returns
	else:
		aabb = _get_model_aabb(model)
	
	if aabb.size.y <= 0.001:
		node.scale = Vector3.ONE * 0.5
		return
	
	var current_height := aabb.size.y
	var scale_factor := target_height / current_height
	
	# Sanity check - prevent extremely large or small objects
	scale_factor = clampf(scale_factor, 0.1, 5.0)
	
	# For CharacterBody3D (NPCs), scale only the Model child, not the physics body
	if node is CharacterBody3D:
		model.scale = Vector3(scale_factor, scale_factor, scale_factor)
		# Also set the target_height property for dynamic hop calculation
		if node.has_method("set"):
			node.set("model_height", target_height)
		# Set model Y offset so feet are at y=0 (calculated from original AABB * scale)
		model.position.y = -aabb.position.y * scale_factor
	else:
		node.scale = Vector3(scale_factor, scale_factor, scale_factor)

## Transform an AABB by a Transform3D (transforms all 8 corners and creates new enclosing AABB)
func _transform_aabb(t: Transform3D, aabb: AABB) -> AABB:
	# Get all 8 corners of the AABB
	var p := aabb.position
	var s := aabb.size
	var corners := [
		t * p,
		t * (p + Vector3(s.x, 0, 0)),
		t * (p + Vector3(0, s.y, 0)),
		t * (p + Vector3(0, 0, s.z)),
		t * (p + Vector3(s.x, s.y, 0)),
		t * (p + Vector3(s.x, 0, s.z)),
		t * (p + Vector3(0, s.y, s.z)),
		t * (p + s),
	]
	# Build new AABB from transformed corners
	var result := AABB(corners[0], Vector3.ZERO)
	for i in range(1, 8):
		result = result.expand(corners[i])
	return result

## Calculate AABB from all meshes in model hierarchy, respecting parent transforms
## Nodes ending in "_nocol" are excluded from calculation
func _get_model_aabb(node: Node, parent_transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var combined_aabb := AABB()
	var found_mesh := false
	
	# Skip nodes ending with "_nocol" (excluded from collision calculation)
	if node.name.ends_with("_nocol"):
		return combined_aabb
	
	# Calculate cumulative transform for this node
	var current_transform := parent_transform
	if node is Node3D:
		current_transform = parent_transform * (node as Node3D).transform
	
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			var mesh_aabb := mesh_instance.mesh.get_aabb()
			# Transform AABB by cumulative transform (includes all parent transforms)
			var transformed := _transform_aabb(current_transform, mesh_aabb)
			if not found_mesh:
				combined_aabb = transformed
				found_mesh = true
			else:
				combined_aabb = combined_aabb.merge(transformed)
	
	for child in node.get_children():
		var child_aabb := _get_model_aabb(child, current_transform)
		if child_aabb.size != Vector3.ZERO:
			if not found_mesh:
				combined_aabb = child_aabb
				found_mesh = true
			else:
				combined_aabb = combined_aabb.merge(child_aabb)
	
	return combined_aabb

func _disable_shadows_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		# Disable shadows for all spawned objects (big performance win on mobile)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Make materials unshaded (no reflections, no lighting calculations)
		if mesh_instance.mesh:
			for i in range(mesh_instance.mesh.get_surface_count()):
				var mat := mesh_instance.get_active_material(i)
				if mat is StandardMaterial3D:
					mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	for child in node.get_children():
		_disable_shadows_recursive(child)

## Apply golden shader material to all mesh instances in a node tree
func _apply_golden_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		# Use material_override to replace all materials with golden shader
		mesh_instance.material_override = _get_golden_material()
	
	for child in node.get_children():
		_apply_golden_material(child)

## Remove golden shader material from all mesh instances in a node tree
func _remove_golden_material(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		# Clear material override to restore original materials
		mesh_instance.material_override = null
	
	for child in node.get_children():
		_remove_golden_material(child)

## Create collision shape from AABB with support for box or sphere
## collision_shape: ObjectConfig.CollisionShape.BOX or .SPHERE
## scale_factor: multiplier for collision size (0.9 for physics, 1.1 for detection)
func _create_collision_from_aabb(aabb: AABB, collision_shape: int, scale_factor: float = 1.0) -> Dictionary:
	var col_shape := CollisionShape3D.new()
	
	if collision_shape == ObjectConfigScript.CollisionShape.SPHERE:
		var sphere := SphereShape3D.new()
		# Use max of width/depth for sphere radius
		sphere.radius = max(aabb.size.x, aabb.size.z) / 2.0 * scale_factor
		col_shape.shape = sphere
		col_shape.position = aabb.get_center()
	else:
		var box := BoxShape3D.new()
		box.size = aabb.size * scale_factor
		col_shape.shape = box
		col_shape.position = aabb.get_center()
	
	return {"collision_shape": col_shape, "aabb": aabb}

## Clean up spawn positions for removed chunk
func cleanup_chunk(chunk_index: int) -> void:
	if spawned_positions.has(chunk_index):
		spawned_positions.erase(chunk_index)
	
	# Also clean zone cache for areas behind player
	# chunk_index 0 starts at Z=0, increasing indices go more negative
	# Clean cache for Z values greater than (behind) this chunk
	if zone_manager and zone_manager.has_method("cleanup_old_cache"):
		var chunk_start_z := -chunk_index * chunk_size.y
		zone_manager.cleanup_old_cache(chunk_start_z)

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

const ObjectConfigScript := preload("res://scripts/config/object_config.gd")

# Preloaded scripts for objects
const TreeScript := preload("res://scripts/objects/tree.gd")
const BuildingScript := preload("res://scripts/objects/building.gd")
const SpikeScript := preload("res://scripts/objects/spike.gd")
const FriendNPCScript := preload("res://scripts/objects/friend_npc.gd")
const EnemyNPCScript := preload("res://scripts/objects/enemy_npc.gd")

# ========== SPAWNING CONFIGURATION ==========

var terrain_width: float = 36.0
var chunk_size: Vector2 = Vector2(100, 50)
var num_lanes: int = 5

# Base density settings (objects per 100 square units)
var tree_density: float = 0.5
var rock_density: float = 0.15
var building_density: float = 0.2  # Increased base density
var enemy_density: float = 0.24  # Building enemies (spikes)
var npc_friend_density: float = 0.03
var npc_enemy_density: float = 0.021  # 30% less than friend NPC

# Urban zone multiplier
var urban_density_multiplier: float = 2.0

# Safe chunks (no spawning for first N chunks)
var rock_safe_chunks: int = 2
var enemy_safe_chunks: int = 4
var building_safe_chunks: int = 3
var npc_friend_safe_chunks: int = 2
var npc_enemy_safe_chunks: int = 5  # Later than friends

# Minimum distance between objects to prevent overlap
var min_object_distance: float = 2.5

# ========== INTERNAL STATE ==========

var color_palette_material: StandardMaterial3D
var hole_manager: RefCounted  # HoleManager
var zone_manager: RefCounted  # ZoneManager

# Track spawned positions per chunk to prevent overlap
var spawned_positions: Dictionary = {}  # chunk_index -> Array[Vector2] (x, z)

func _init(config: Dictionary) -> void:
	terrain_width = config.get("terrain_width", 36.0)
	chunk_size = config.get("chunk_size", Vector2(100, 50))
	tree_density = config.get("tree_density", 0.5)
	num_lanes = config.get("num_lanes", 5)
	rock_safe_chunks = config.get("rock_safe_chunks", 2)
	
	_setup_material()
	
	# Create zone manager with noise-based zones
	var ZoneManagerScript := preload("res://scripts/terrain/zone_manager.gd")
	zone_manager = ZoneManagerScript.new({
		"seed": config.get("seed", 42),
		"noise_scale": 0.015,  # Larger patches
		"forest_threshold": -0.1,
		"building_threshold": 0.1,
	})

func _setup_material() -> void:
	color_palette_material = StandardMaterial3D.new()
	var texture := load("res://assets/textures/color-palette.png") as Texture2D
	if texture:
		color_palette_material.albedo_texture = texture
		color_palette_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	color_palette_material.roughness = 0.9
	color_palette_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX

func set_hole_manager(manager: RefCounted) -> void:
	hole_manager = manager

## Main spawn function - call this for each chunk
## Uses noise-based zone sampling at each spawn position
func spawn_objects(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	# Clear previous spawn positions for this chunk
	spawned_positions[chunk_index] = []
	
	# Spawn rocks everywhere (regardless of zone)
	if chunk_index >= rock_safe_chunks:
		_spawn_rocks(chunk, chunk_index, get_height_func)
	
	# Spawn friend NPC clusters (random meadows with animals)
	if chunk_index >= npc_friend_safe_chunks:
		_spawn_npc_clusters(chunk, chunk_index, get_height_func)
	
	# Spawn enemy NPC clusters
	if chunk_index >= npc_enemy_safe_chunks:
		_spawn_enemy_npc_clusters(chunk, chunk_index, get_height_func)
	
	# Spawn trees, buildings, and building enemies based on position-level zone checking
	_spawn_zone_objects(chunk, chunk_index, get_height_func)

## Spawn rocks (zone-independent)
func _spawn_rocks(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 99999)
	
	var area := chunk_size.x * chunk_size.y
	var object_count := int(area * rock_density / 100.0)
	object_count = max(object_count, 1)
	
	for i in range(object_count):
		var obj_data: RefCounted = ObjectConfigScript.select_random_object(ObjectConfigScript.Category.ROCK, rng)
		if not obj_data:
			continue
		
		var margin := 2.0
		var x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
		var local_z := rng.randf_range(-chunk_size.y + margin, -margin)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 1.5):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var obj: Node3D = _create_object(obj_data, rng, ObjectConfigScript.Category.ROCK)
		if not obj:
			continue
		
		obj.position = Vector3(x, height, local_z)
		obj.rotation.y = rng.randf_range(0, TAU)
		
		var variation: float = obj_data.height_variation
		var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(obj, target_h)
		
		chunk.add_child(obj)
		_register_spawn_position(x, local_z, chunk_index)

## Spawn NPC clusters - random meadows with groups of animals
func _spawn_npc_clusters(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 77777)
	
	# 70% chance to have an NPC cluster in this chunk (was 30%)
	if rng.randf() > 0.7:
		return
	
	# Pick random center position for the cluster
	var margin := 8.0
	var cluster_x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
	var cluster_z := rng.randf_range(-chunk_size.y + margin, -margin)
	
	# Skip if near hole
	if _is_near_hole(cluster_x, cluster_z, chunk_index):
		return
	
	# Spawn 4-10 animals in the cluster (was 2-5)
	var animal_count := rng.randi_range(4, 10)
	var cluster_radius := 6.0
	
	for i in range(animal_count):
		var obj_data: RefCounted = ObjectConfigScript.select_random_object(ObjectConfigScript.Category.NPC_FRIEND, rng)
		if not obj_data:
			continue
		
		# Random position within cluster
		var angle := rng.randf_range(0, TAU)
		var dist := rng.randf_range(0.5, cluster_radius)
		var x := cluster_x + cos(angle) * dist
		var local_z := cluster_z + sin(angle) * dist
		
		# Clamp to terrain bounds
		x = clampf(x, -terrain_width / 2 + 2.0, terrain_width / 2 - 2.0)
		local_z = clampf(local_z, -chunk_size.y + 2.0, -2.0)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 2.0):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var obj: Node3D = _create_object(obj_data, rng, ObjectConfigScript.Category.NPC_FRIEND)
		if not obj:
			continue
		
		obj.position = Vector3(x, height, local_z)
		obj.rotation.y = rng.randf_range(0, TAU)
		
		# Scale to target height
		var variation: float = obj_data.height_variation
		var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(obj, target_h)
		
		chunk.add_child(obj)
		_register_spawn_position(x, local_z, chunk_index)


## Spawn enemy NPC clusters (groups of 2-6 enemies)
func _spawn_enemy_npc_clusters(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 55555)
	
	# 49% chance to have an enemy NPC cluster (70% * 0.7 = ~49% - 30% less than friend NPCs)
	if rng.randf() > 0.49:
		return
	
	# Pick random center position for the cluster
	var margin := 8.0
	var cluster_x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
	var cluster_z := rng.randf_range(-chunk_size.y + margin, -margin)
	
	# Skip if near hole
	if _is_near_hole(cluster_x, cluster_z, chunk_index):
		return
	
	# Spawn 2-6 enemy NPCs in the cluster
	var enemy_count := rng.randi_range(2, 6)
	var cluster_radius := 5.0
	
	for i in range(enemy_count):
		var obj_data: RefCounted = ObjectConfigScript.select_random_object(ObjectConfigScript.Category.NPC_ENEMY, rng)
		if not obj_data:
			continue
		
		# Random position within cluster
		var angle := rng.randf_range(0, TAU)
		var dist := rng.randf_range(0.5, cluster_radius)
		var x := cluster_x + cos(angle) * dist
		var local_z := cluster_z + sin(angle) * dist
		
		# Clamp to terrain bounds
		x = clampf(x, -terrain_width / 2 + 2.0, terrain_width / 2 - 2.0)
		local_z = clampf(local_z, -chunk_size.y + 2.0, -2.0)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 2.5):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var obj: Node3D = _create_object(obj_data, rng, ObjectConfigScript.Category.NPC_ENEMY)
		if not obj:
			continue
		
		obj.position = Vector3(x, height, local_z)
		obj.rotation.y = rng.randf_range(0, TAU)
		
		# Scale to target height
		var variation: float = obj_data.height_variation
		var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(obj, target_h)
		
		chunk.add_child(obj)
		_register_spawn_position(x, local_z, chunk_index)


## Spawn zone-dependent objects (trees, buildings, enemies) with per-position zone check
func _spawn_zone_objects(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 54321)
	
	# Calculate how many spawn attempts based on combined densities
	var area := chunk_size.x * chunk_size.y
	var combined_density := tree_density + building_density + enemy_density
	var spawn_attempts := int(area * combined_density / 100.0 * 1.5)  # Extra attempts due to zone filtering
	spawn_attempts = max(spawn_attempts, 5)
	
	var chunk_start_z := -chunk_index * chunk_size.y
	
	for i in range(spawn_attempts):
		var margin := 3.0
		var x := rng.randf_range(-terrain_width / 2 + margin, terrain_width / 2 - margin)
		var local_z := rng.randf_range(-chunk_size.y + margin, -margin)
		
		# Convert to world Z for zone sampling
		var world_z := chunk_start_z + local_z
		
		# Skip if in hole area
		if _is_near_hole(x, local_z, chunk_index):
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
				category = ObjectConfigScript.Category.BUILDING
		
		# Additionally, try to spawn building enemy with separate probability
		var enemy_roll := rng.randf()
		var should_spawn_enemy := false
		if chunk_index >= enemy_safe_chunks:
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
	# Select random object from category
	var obj_data: RefCounted = ObjectConfigScript.select_random_object(category, rng)
	if not obj_data:
		return false
	
	# Check minimum distance based on category
	var min_dist := min_object_distance
	if category == ObjectConfigScript.Category.BUILDING:
		min_dist = 4.0
	elif category == ObjectConfigScript.Category.ROCK:
		min_dist = 1.5
	elif category == ObjectConfigScript.Category.NPC_FRIEND:
		min_dist = 3.0  # NPCs need space to wander
	
	if not _is_position_available(x, local_z, chunk_index, min_dist):
		return false
	
	var height: float = get_height_func.call(x, local_z, chunk_index)
	
	# Create object
	var obj: Node3D = _create_object(obj_data, rng, category)
	if not obj:
		return false
	
	obj.position = Vector3(x, height, local_z)
	obj.rotation.y = rng.randf_range(0, TAU)
	
	# Scale to target height
	var variation: float = obj_data.height_variation
	var target_h: float = obj_data.target_height * rng.randf_range(1.0 - variation, 1.0 + variation)
	_scale_to_target_height(obj, target_h)
	
	chunk.add_child(obj)
	_register_spawn_position(x, local_z, chunk_index)
	return true

## Create an object instance based on category
func _create_object(obj_data: RefCounted, rng: RandomNumberGenerator, category: int) -> Node3D:
	match category:
		ObjectConfigScript.Category.TREE:
			return _create_tree(obj_data, rng)
		ObjectConfigScript.Category.BUILDING:
			return _create_building(obj_data, rng)
		ObjectConfigScript.Category.BUILDING_ENEMY:
			return _create_building_enemy(obj_data, rng)
		ObjectConfigScript.Category.ROCK:
			return _create_rock(obj_data, rng)
		ObjectConfigScript.Category.NPC_FRIEND:
			return _create_friend_npc(obj_data, rng)
		ObjectConfigScript.Category.NPC_ENEMY:
			return _create_enemy_npc(obj_data, rng)
	return null

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
	
	# Load model
	var model: Node3D = null
	var model_scene := load(obj_data.model_path) as PackedScene
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		tree.add_child(model)
	
	# Detection area with AABB-based collision
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	
	# Calculate bounding box from model
	if model:
		var aabb := _get_model_aabb(model)
		if aabb.size != Vector3.ZERO:
			box.size = aabb.size * 1.1  # Slightly larger for better detection
			col_shape.position = aabb.get_center()
		else:
			# Fallback to config values
			box.size = Vector3(obj_data.collision_radius * 2, obj_data.collision_height, obj_data.collision_radius * 2)
			col_shape.position.y = obj_data.collision_height / 2
	else:
		box.size = Vector3(obj_data.collision_radius * 2, obj_data.collision_height, obj_data.collision_radius * 2)
		col_shape.position.y = obj_data.collision_height / 2
	
	col_shape.shape = box
	detect_area.add_child(col_shape)
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
	
	# Load model
	var model: Node3D = null
	var model_scene := load(obj_data.model_path) as PackedScene
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		building.add_child(model)
	
	# Detection area with AABB-based collision
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	
	# Calculate bounding box from model
	if model:
		var aabb := _get_model_aabb(model)
		if aabb.size != Vector3.ZERO:
			box.size = aabb.size * 1.1  # Slightly larger for better detection
			col_shape.position = aabb.get_center()
		else:
			# Fallback to config values
			box.size = obj_data.collision_size
			col_shape.position.y = obj_data.collision_size.y / 2
	else:
		box.size = obj_data.collision_size
		col_shape.position.y = obj_data.collision_size.y / 2
	
	col_shape.shape = box
	detect_area.add_child(col_shape)
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
	enemy.set("object_id", obj_data.id)
	enemy.set("object_name", obj_data.display_name)
	
	# Load model
	var model: Node3D = null
	var model_scene := load(obj_data.model_path) as PackedScene
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		enemy.add_child(model)
	
	# Calculate AABB from model for collision
	var aabb := AABB()
	if model:
		aabb = _get_model_aabb(model)
	
	# Physical collision (box based on AABB)
	var phys_col := CollisionShape3D.new()
	var phys_box := BoxShape3D.new()
	if aabb.size != Vector3.ZERO:
		phys_box.size = aabb.size * 0.7  # Slightly smaller for physical collision
		phys_col.position = aabb.get_center()
	else:
		# Fallback
		phys_box.size = Vector3(obj_data.collision_radius * 1.2, obj_data.collision_radius * 1.2, obj_data.collision_radius * 1.2)
		phys_col.position.y = obj_data.collision_radius * 0.6
	phys_col.shape = phys_box
	enemy.add_child(phys_col)
	
	# Damage detection area (box based on AABB)
	var damage_area := Area3D.new()
	damage_area.name = "DamageArea"
	damage_area.collision_layer = 0
	damage_area.collision_mask = 2
	damage_area.monitoring = true
	
	var dmg_col := CollisionShape3D.new()
	var dmg_box := BoxShape3D.new()
	if aabb.size != Vector3.ZERO:
		dmg_box.size = aabb.size * 1.1  # Slightly larger for damage detection
		dmg_col.position = aabb.get_center()
	else:
		# Fallback
		dmg_box.size = Vector3(obj_data.collision_radius * 2, obj_data.collision_radius * 2, obj_data.collision_radius * 2)
		dmg_col.position.y = obj_data.collision_radius
	dmg_col.shape = dmg_box
	damage_area.add_child(dmg_col)
	enemy.add_child(damage_area)
	
	return enemy

## Create a rock instance
func _create_rock(obj_data: RefCounted, rng: RandomNumberGenerator) -> StaticBody3D:
	var rock := StaticBody3D.new()
	rock.name = "Rock"
	rock.add_to_group("rocks")
	rock.collision_layer = 1
	rock.collision_mask = 0
	
	# Load model
	var model_scene := load(obj_data.model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		rock.add_child(model)
	
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = obj_data.collision_radius
	col_shape.shape = sphere
	col_shape.position.y = sphere.radius * 0.75
	rock.add_child(col_shape)
	
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
	npc.set("coin_value", obj_data.coins)
	npc.set("object_id", obj_data.id)
	npc.set("object_name", obj_data.display_name)
	
	# Terrain collision shape (invisible capsule for walking)
	var terrain_col := CollisionShape3D.new()
	terrain_col.name = "TerrainCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.2
	capsule.height = obj_data.collision_height
	terrain_col.shape = capsule
	terrain_col.position.y = obj_data.collision_height / 2
	npc.add_child(terrain_col)
	
	# Load model (separate from collision, will hop)
	var model: Node3D = null
	var model_scene := load(obj_data.model_path) as PackedScene
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		npc.add_child(model)
	
	# Calculate AABB from model for detection area
	var aabb := AABB()
	if model:
		aabb = _get_model_aabb(model)
	
	# Detection area for player collision
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	if aabb.size != Vector3.ZERO:
		sphere.radius = max(aabb.size.x, aabb.size.z) * 0.6
		col_shape.position = aabb.get_center()
	else:
		sphere.radius = obj_data.collision_radius
		col_shape.position.y = obj_data.collision_height / 2
	col_shape.shape = sphere
	detect_area.add_child(col_shape)
	npc.add_child(detect_area)
	
	return npc

## Create an enemy NPC instance (dark pawn, dark knight, horse knight, etc.)
func _create_enemy_npc(obj_data: RefCounted, rng: RandomNumberGenerator) -> CharacterBody3D:
	var npc := CharacterBody3D.new()
	npc.name = "EnemyNPC"
	npc.add_to_group("npcs")
	npc.add_to_group("enemy_npcs")
	npc.collision_layer = 0  # Don't block anything
	npc.collision_mask = 1   # Collide with terrain for walking
	npc.set_script(EnemyNPCScript)
	npc.set("damage", obj_data.damage)
	npc.set("coin_value", obj_data.coins)
	npc.set("object_id", obj_data.id)
	npc.set("object_name", obj_data.display_name)
	
	# Terrain collision shape (invisible capsule for walking)
	var terrain_col := CollisionShape3D.new()
	terrain_col.name = "TerrainCollision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = obj_data.collision_height
	terrain_col.shape = capsule
	terrain_col.position.y = obj_data.collision_height / 2
	npc.add_child(terrain_col)
	
	# Load model (separate from collision, will hop when chasing)
	var model: Node3D = null
	var model_scene := load(obj_data.model_path) as PackedScene
	if model_scene:
		model = model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		npc.add_child(model)
	
	# Calculate AABB from model for detection area
	var aabb := AABB()
	if model:
		aabb = _get_model_aabb(model)
	
	# Detection area for player collision
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	if aabb.size != Vector3.ZERO:
		# Use exact AABB size for precise collision
		box.size = aabb.size * 0.9  # Slightly smaller than visual
		col_shape.position = aabb.get_center()
	else:
		# Fallback box
		box.size = Vector3(obj_data.collision_radius * 2, obj_data.collision_height, obj_data.collision_radius * 2)
		col_shape.position.y = obj_data.collision_height / 2
	col_shape.shape = box
	detect_area.add_child(col_shape)
	npc.add_child(detect_area)
	
	return npc

# ========== HELPER FUNCTIONS ==========

func _is_near_hole(x: float, z: float, chunk_index: int) -> bool:
	if hole_manager:
		return hole_manager.get_distance_to_nearest_hole(x, z, chunk_index) < 3.0
	return false

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

func _scale_to_target_height(node: Node3D, target_height: float) -> void:
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
	
	var aabb := _get_model_aabb(model)
	if aabb.size.y <= 0.001:
		node.scale = Vector3.ONE * 0.5
		return
	
	var current_height := aabb.size.y
	var scale_factor := target_height / current_height
	
	# For CharacterBody3D (NPCs), scale only the Model child, not the physics body
	if node is CharacterBody3D:
		model.scale = Vector3(scale_factor, scale_factor, scale_factor)
		# Also set the target_height property for dynamic hop calculation
		if node.has_method("set"):
			node.set("model_height", target_height)
	else:
		node.scale = Vector3(scale_factor, scale_factor, scale_factor)

func _get_model_aabb(node: Node) -> AABB:
	var combined_aabb := AABB()
	var found_mesh := false
	
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			var mesh_aabb := mesh_instance.mesh.get_aabb()
			var transformed := mesh_instance.transform * mesh_aabb
			if not found_mesh:
				combined_aabb = transformed
				found_mesh = true
			else:
				combined_aabb = combined_aabb.merge(transformed)
	
	for child in node.get_children():
		var child_aabb := _get_model_aabb(child)
		if child_aabb.size != Vector3.ZERO:
			if not found_mesh:
				combined_aabb = child_aabb
				found_mesh = true
			else:
				combined_aabb = combined_aabb.merge(child_aabb)
	
	return combined_aabb

func _apply_material_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			var surface_count := mesh_instance.mesh.get_surface_count()
			for i in range(surface_count):
				var existing_mat := mesh_instance.get_active_material(i)
				var new_mat: StandardMaterial3D
				
				if existing_mat is StandardMaterial3D:
					new_mat = existing_mat.duplicate() as StandardMaterial3D
				else:
					new_mat = StandardMaterial3D.new()
					new_mat.albedo_color = Color(0.5, 0.5, 0.5)
				
				new_mat.albedo_texture = color_palette_material.albedo_texture
				new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh_instance.set_surface_override_material(i, new_mat)
	
	for child in node.get_children():
		_apply_material_recursive(child)

## Clean up spawn positions for removed chunk
func cleanup_chunk(chunk_index: int) -> void:
	if spawned_positions.has(chunk_index):
		spawned_positions.erase(chunk_index)

class_name ObjectSpawner
extends RefCounted
## Handles spawning of all world objects with zone-based placement
## Supports: trees, rocks, buildings, spikes (enemies)
## 
## Zone system:
## - FOREST zones: Trees spawn here
## - BUILDING zones: Buildings and spikes spawn here
## - OPEN zones: Transition areas, only rocks
## - Rocks spawn everywhere regardless of zone

# ========== OBJECT CONFIGURATION ==========
# Each object type has configurable properties

var object_configs: Dictionary = {
	"tree": {
		"models": [
			"res://assets/models/trees/borovice_1.blend",
			"res://assets/models/trees/borovice_2.blend",
			"res://assets/models/trees/borovice_3.blend",
			"res://assets/models/trees/smrk_1.blend",
			"res://assets/models/trees/smrk_2.blend",
			"res://assets/models/trees/smrk_3.blend",
			"res://assets/models/trees/strom_1.blend",
			"res://assets/models/trees/strom_2.blend",
			"res://assets/models/trees/strom_3.blend",
			"res://assets/models/trees/strom_bez_listi.blend",
			"res://assets/models/trees/strom_bez_listi_2.blend",
		],
		"target_height": 3.0,
		"height_variation": 0.2,  # +/- 20%
		"coins": 1,
		"display_name": "Tree",
		"collision_radius": 0.6,
		"collision_height": 2.5,
	},
	"rock": {
		"models": [
			"res://assets/models/rocks/rock_1.blend",
			"res://assets/models/rocks/rock_2.blend",
			"res://assets/models/rocks/rock_3.blend",
			"res://assets/models/rocks/rock_4.blend",
			"res://assets/models/rocks/rock_5.blend",
			"res://assets/models/rocks/rock_6.blend",
			"res://assets/models/rocks/rock_7.blend",
			"res://assets/models/rocks/rock_8.blend",
			"res://assets/models/rocks/rock_9.blend",
			"res://assets/models/rocks/rock_10.blend",
		],
		"target_height": 0.8,
		"height_variation": 0.3,
		"display_name": "Rock",
		"collision_radius": 0.4,
	},
	"building": {
		"models": [
			"res://assets/models/buildings/tent.blend",
			"res://assets/models/buildings/small_hut.blend",
		],
		"target_height": 2.5,
		"height_variation": 0.15,
		"coins": 20,
		"display_name": "Building",
		"collision_size": Vector3(2.0, 2.0, 2.0),  # Box collider
	},
	"spike": {
		"models": [
			"res://assets/models/enemies/spike.blend",
		],
		"target_height": 1.0,
		"height_variation": 0.1,
		"damage": 15,
		"display_name": "Spike",
		"collision_radius": 0.8,
	},
}

# ========== SPAWNING CONFIGURATION ==========

var terrain_width: float = 36.0
var chunk_size: Vector2 = Vector2(100, 50)
var num_lanes: int = 5

# Density settings (objects per 100 square units)
var tree_density: float = 0.5
var rock_density: float = 0.15  # Rocks everywhere
var building_density: float = 0.08
var spike_density: float = 0.05

# Safe chunks (no spawning for first N chunks)
var rock_safe_chunks: int = 2
var enemy_safe_chunks: int = 4
var building_safe_chunks: int = 3

# Minimum distance between objects to prevent overlap
var min_object_distance: float = 2.5

# ========== INTERNAL STATE ==========

var color_palette_material: StandardMaterial3D
var hole_manager: RefCounted  # HoleManager
var zone_manager: RefCounted  # ZoneManager

# Track spawned positions per chunk to prevent overlap
var spawned_positions: Dictionary = {}  # chunk_index -> Array[Vector2] (x, z)

# Preloaded scripts
const TreeScript := preload("res://scripts/tree.gd")
const BuildingScript := preload("res://scripts/building.gd")
const SpikeScript := preload("res://scripts/spike.gd")

func _init(config: Dictionary) -> void:
	terrain_width = config.get("terrain_width", 36.0)
	chunk_size = config.get("chunk_size", Vector2(100, 50))
	tree_density = config.get("tree_density", 0.5)
	num_lanes = config.get("num_lanes", 5)
	rock_safe_chunks = config.get("rock_safe_chunks", 2)
	
	_setup_material()
	
	# Create zone manager
	var ZoneManagerScript := preload("res://scripts/terrain/zone_manager.gd")
	zone_manager = ZoneManagerScript.new({
		"chunk_size_y": chunk_size.y,
		"min_zone_length": 100.0,
		"max_zone_length": 200.0,
		"open_zone_length": 30.0,
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
func spawn_objects(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	# Clear previous spawn positions for this chunk
	spawned_positions[chunk_index] = []
	
	# Get zone type for this chunk
	var zone_type: int = zone_manager.get_zone_for_chunk(chunk_index)
	
	# Rocks spawn everywhere (regardless of zone)
	if chunk_index >= rock_safe_chunks:
		_spawn_rocks(chunk, chunk_index, get_height_func)
	
	# Zone-specific spawning
	match zone_type:
		0:  # FOREST
			_spawn_trees(chunk, chunk_index, get_height_func)
		1:  # BUILDING
			if chunk_index >= building_safe_chunks:
				_spawn_buildings(chunk, chunk_index, get_height_func)
			if chunk_index >= enemy_safe_chunks:
				_spawn_spikes(chunk, chunk_index, get_height_func)
		2:  # OPEN
			# Only rocks (already spawned above)
			pass

## Check if a position is too close to already spawned objects
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

## Register a spawned position
func _register_spawn_position(x: float, z: float, chunk_index: int) -> void:
	if not spawned_positions.has(chunk_index):
		spawned_positions[chunk_index] = []
	spawned_positions[chunk_index].append(Vector2(x, z))

# ========== TREES ==========

func _spawn_trees(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 12345)
	
	var area := chunk_size.x * chunk_size.y
	var tree_count := int(area * tree_density / 100.0)
	tree_count = max(tree_count, 1)
	
	var config: Dictionary = object_configs["tree"]
	var models: Array = config["models"]
	
	for i in range(tree_count):
		var x := rng.randf_range(-terrain_width / 2 + 2, terrain_width / 2 - 2)
		var local_z := rng.randf_range(-chunk_size.y + 3, -3)
		
		# Skip if in hole area
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		# Skip if position is taken
		if not _is_position_available(x, local_z, chunk_index):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var tree := _create_tree(rng, config, models)
		tree.position = Vector3(x, height, local_z)
		tree.rotation.y = rng.randf_range(0, TAU)
		
		var variation: float = config["height_variation"]
		var target_h: float = config["target_height"] * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(tree, target_h)
		
		chunk.add_child(tree)
		_register_spawn_position(x, local_z, chunk_index)

func _create_tree(rng: RandomNumberGenerator, config: Dictionary, models: Array) -> RigidBody3D:
	var tree := RigidBody3D.new()
	tree.name = "Tree"
	tree.mass = 20.0
	tree.freeze = true
	tree.collision_layer = 0
	tree.collision_mask = 1
	tree.set_script(TreeScript)
	tree.set("coin_value", config.get("coins", 1))
	
	var model_path: String = models[rng.randi() % models.size()]
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		tree.add_child(model)
	
	# Detection area
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = config.get("collision_radius", 0.6)
	capsule.height = config.get("collision_height", 2.5)
	col_shape.shape = capsule
	col_shape.position.y = capsule.height / 2
	detect_area.add_child(col_shape)
	tree.add_child(detect_area)
	
	return tree

# ========== ROCKS ==========

func _spawn_rocks(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 54321 + 999)
	
	var area := chunk_size.x * chunk_size.y
	var rock_count := int(area * rock_density / 100.0)
	rock_count = max(rock_count, 2)
	
	var config: Dictionary = object_configs["rock"]
	var models: Array = config["models"]
	
	for i in range(rock_count):
		var x := rng.randf_range(-terrain_width / 2 + 2, terrain_width / 2 - 2)
		var local_z := rng.randf_range(-chunk_size.y + 3, -3)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 1.5):  # Smaller distance for rocks
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var rock := _create_rock(rng, config, models)
		rock.position = Vector3(x, height, local_z)
		rock.rotation.y = rng.randf_range(0, TAU)
		
		var variation: float = config["height_variation"]
		var target_h: float = config["target_height"] * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(rock, target_h)
		
		chunk.add_child(rock)
		_register_spawn_position(x, local_z, chunk_index)

func _create_rock(rng: RandomNumberGenerator, config: Dictionary, models: Array) -> StaticBody3D:
	var rock := StaticBody3D.new()
	rock.name = "Rock"
	rock.add_to_group("rocks")
	rock.collision_layer = 1
	rock.collision_mask = 0
	
	var model_path: String = models[rng.randi() % models.size()]
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		rock.add_child(model)
	
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = config.get("collision_radius", 0.4)
	col_shape.shape = sphere
	col_shape.position.y = sphere.radius * 0.75
	rock.add_child(col_shape)
	
	return rock

# ========== BUILDINGS ==========

func _spawn_buildings(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 77777)
	
	var area := chunk_size.x * chunk_size.y
	var building_count := int(area * building_density / 100.0)
	building_count = max(building_count, 1)
	
	var config: Dictionary = object_configs["building"]
	var models: Array = config["models"]
	
	for i in range(building_count):
		var x := rng.randf_range(-terrain_width / 2 + 3, terrain_width / 2 - 3)
		var local_z := rng.randf_range(-chunk_size.y + 5, -5)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		# Buildings need more space
		if not _is_position_available(x, local_z, chunk_index, 4.0):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var building := _create_building(rng, config, models)
		building.position = Vector3(x, height, local_z)
		building.rotation.y = rng.randf_range(0, TAU)
		
		var variation: float = config["height_variation"]
		var target_h: float = config["target_height"] * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(building, target_h)
		
		chunk.add_child(building)
		_register_spawn_position(x, local_z, chunk_index)

func _create_building(rng: RandomNumberGenerator, config: Dictionary, models: Array) -> RigidBody3D:
	var building := RigidBody3D.new()
	building.name = "Building"
	building.mass = 50.0
	building.freeze = true
	building.collision_layer = 0
	building.collision_mask = 1
	building.set_script(BuildingScript)
	building.set("coin_value", config.get("coins", 20))
	
	var model_path: String = models[rng.randi() % models.size()]
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		building.add_child(model)
	
	# Detection area (trigger box)
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var col_size: Vector3 = config.get("collision_size", Vector3(2.0, 2.0, 2.0))
	box.size = col_size
	col_shape.shape = box
	col_shape.position.y = col_size.y / 2
	detect_area.add_child(col_shape)
	building.add_child(detect_area)
	
	return building

# ========== SPIKES (ENEMIES) ==========

func _spawn_spikes(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 88888)
	
	var area := chunk_size.x * chunk_size.y
	var spike_count := int(area * spike_density / 100.0)
	spike_count = max(spike_count, 1)
	
	var config: Dictionary = object_configs["spike"]
	var models: Array = config["models"]
	
	for i in range(spike_count):
		var x := rng.randf_range(-terrain_width / 2 + 2, terrain_width / 2 - 2)
		var local_z := rng.randf_range(-chunk_size.y + 4, -4)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		if not _is_position_available(x, local_z, chunk_index, 3.0):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var spike := _create_spike(rng, config, models)
		spike.position = Vector3(x, height, local_z)
		spike.rotation.y = rng.randf_range(0, TAU)
		
		var variation: float = config["height_variation"]
		var target_h: float = config["target_height"] * rng.randf_range(1.0 - variation, 1.0 + variation)
		_scale_to_target_height(spike, target_h)
		
		chunk.add_child(spike)
		_register_spawn_position(x, local_z, chunk_index)

func _create_spike(rng: RandomNumberGenerator, config: Dictionary, models: Array) -> StaticBody3D:
	var spike := StaticBody3D.new()
	spike.name = "Spike"
	spike.add_to_group("enemies")
	spike.add_to_group("spikes")
	spike.collision_layer = 1  # Collide with player
	spike.collision_mask = 0
	spike.set_script(SpikeScript)
	spike.set("damage", config.get("damage", 15))
	
	var model_path: String = models[rng.randi() % models.size()]
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		spike.add_child(model)
	
	# Physical collision (blocks player)
	var phys_col := CollisionShape3D.new()
	var phys_sphere := SphereShape3D.new()
	phys_sphere.radius = config.get("collision_radius", 0.8) * 0.6
	phys_col.shape = phys_sphere
	phys_col.position.y = phys_sphere.radius
	spike.add_child(phys_col)
	
	# Damage detection area (slightly larger)
	var damage_area := Area3D.new()
	damage_area.name = "DamageArea"
	damage_area.collision_layer = 0
	damage_area.collision_mask = 2  # Detect player
	damage_area.monitoring = true
	
	var dmg_col := CollisionShape3D.new()
	var dmg_sphere := SphereShape3D.new()
	dmg_sphere.radius = config.get("collision_radius", 0.8)
	dmg_col.shape = dmg_sphere
	dmg_col.position.y = dmg_sphere.radius
	damage_area.add_child(dmg_col)
	spike.add_child(damage_area)
	
	return spike

# ========== HELPER FUNCTIONS ==========

func _is_near_hole(x: float, z: float, chunk_index: int) -> bool:
	if hole_manager:
		return hole_manager.get_distance_to_nearest_hole(x, z, chunk_index) < 3.0
	return false

func _scale_to_target_height(node: Node3D, target_height: float) -> void:
	var model: Node = null
	for child in node.get_children():
		if child.name == "Model" or child is Node3D:
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

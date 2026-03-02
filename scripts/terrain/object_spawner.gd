class_name ObjectSpawner
extends RefCounted
## Handles spawning of all world objects - trees, rocks, and future object types
## 
## To add a new object type:
## 1. Add model paths to the appropriate array
## 2. Create a spawn function (_create_xxx)
## 3. Add spawning logic in spawn_objects()

# Configuration
var terrain_width: float = 36.0
var chunk_size: Vector2 = Vector2(100, 50)
var tree_density: float = 0.5
var rock_spawn_chance: float = 0.6
var rock_safe_chunks: int = 2
var num_lanes: int = 5

# Target heights for spawned objects
const TARGET_TREE_HEIGHT: float = 3.0
const TARGET_ROCK_HEIGHT: float = 0.8

# Model paths - easy to extend with new object types
var tree_models: Array[String] = [
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
]

var rock_models: Array[String] = [
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
]

# Shared material with color palette texture
var color_palette_material: StandardMaterial3D

# Reference to hole manager for avoiding hole areas
var hole_manager: RefCounted  # HoleManager

func _init(config: Dictionary) -> void:
	terrain_width = config.get("terrain_width", 36.0)
	chunk_size = config.get("chunk_size", Vector2(100, 50))
	tree_density = config.get("tree_density", 0.5)
	rock_spawn_chance = config.get("rock_spawn_chance", 0.6)
	rock_safe_chunks = config.get("rock_safe_chunks", 2)
	num_lanes = config.get("num_lanes", 5)
	
	_setup_material()

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
	_spawn_trees(chunk, chunk_index, get_height_func)
	_spawn_rocks(chunk, chunk_index, get_height_func)
	# Future object types can be added here:
	# _spawn_coins(chunk, chunk_index, get_height_func)
	# _spawn_powerups(chunk, chunk_index, get_height_func)
	# _spawn_obstacles(chunk, chunk_index, get_height_func)

# ========== TREES ==========

func _spawn_trees(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 12345)
	
	var area := chunk_size.x * chunk_size.y
	var tree_count := int(area * tree_density / 100.0)
	tree_count = max(tree_count, 1)
	
	for i in range(tree_count):
		var x := rng.randf_range(-terrain_width / 2 + 2, terrain_width / 2 - 2)
		var local_z := rng.randf_range(-chunk_size.y + 3, -3)
		
		# Skip if in or near hole area
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var tree := _create_tree(rng)
		tree.position = Vector3(x, height, local_z)
		tree.rotation.y = rng.randf_range(0, TAU)
		
		var target_h := TARGET_TREE_HEIGHT * rng.randf_range(0.8, 1.2)
		_scale_to_target_height(tree, target_h)
		chunk.add_child(tree)

func _create_tree(rng: RandomNumberGenerator) -> RigidBody3D:
	var tree := RigidBody3D.new()
	tree.name = "Tree"
	tree.mass = 20.0
	tree.freeze = true
	tree.collision_layer = 0
	tree.collision_mask = 1
	tree.set_script(preload("res://scripts/tree.gd"))
	
	var model_path: String = tree_models[rng.randi() % tree_models.size()]
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		tree.add_child(model)
	
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.6
	capsule.height = 2.5
	col_shape.shape = capsule
	col_shape.position.y = 1.25
	detect_area.add_child(col_shape)
	tree.add_child(detect_area)
	
	return tree

# ========== ROCKS ==========

func _spawn_rocks(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	if chunk_index < rock_safe_chunks:
		return
	
	var rock_rng := RandomNumberGenerator.new()
	rock_rng.seed = hash(chunk_index * 54321 + 999)
	
	var num_rocks := rock_rng.randi_range(4, 8)
	var z_section_size := chunk_size.y / float(num_rocks)
	var used_lanes: Array[int] = []
	
	for rock_i in range(num_rocks):
		var z_start := -chunk_size.y + rock_i * z_section_size + 3
		var z_end := -chunk_size.y + (rock_i + 1) * z_section_size - 3
		var local_z := rock_rng.randf_range(z_start, z_end)
		
		var lane_width := terrain_width / float(num_lanes)
		var lane := rock_rng.randi_range(0, num_lanes - 1)
		
		if used_lanes.size() > 0:
			var attempts := 0
			while lane == used_lanes[-1] and attempts < 3:
				lane = rock_rng.randi_range(0, num_lanes - 1)
				attempts += 1
		
		used_lanes.append(lane)
		if used_lanes.size() > 2:
			used_lanes.remove_at(0)
		
		var lane_center := -terrain_width / 2 + lane_width / 2 + lane * lane_width
		var x := lane_center + rock_rng.randf_range(-lane_width * 0.3, lane_width * 0.3)
		
		if _is_near_hole(x, local_z, chunk_index):
			continue
		
		var height: float = get_height_func.call(x, local_z, chunk_index)
		
		var rock := _create_rock(rock_rng)
		rock.position = Vector3(x, height, local_z)
		rock.rotation.y = rock_rng.randf_range(0, TAU)
		
		var target_h := TARGET_ROCK_HEIGHT * rock_rng.randf_range(0.7, 1.3)
		_scale_to_target_height(rock, target_h)
		chunk.add_child(rock)

func _create_rock(rng: RandomNumberGenerator) -> StaticBody3D:
	var rock := StaticBody3D.new()
	rock.name = "Rock"
	rock.add_to_group("rocks")
	rock.collision_layer = 1
	rock.collision_mask = 0
	
	var model_path: String = rock_models[rng.randi() % rock_models.size()]
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model)
		rock.add_child(model)
	
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	col_shape.shape = sphere
	col_shape.position.y = 0.3
	rock.add_child(col_shape)
	
	return rock

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

# ========== TEMPLATE FOR NEW OBJECT TYPES ==========
# 
# To add a new object type (e.g., coins):
#
# 1. Add model paths:
#    var coin_models: Array[String] = [
#        "res://assets/models/coins/coin.blend",
#    ]
#
# 2. Add configuration:
#    var coin_spawn_chance: float = 0.3
#    const TARGET_COIN_SIZE: float = 0.5
#
# 3. Create spawn function:
#    func _spawn_coins(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
#        var rng := RandomNumberGenerator.new()
#        rng.seed = hash(chunk_index * 98765)
#        
#        if rng.randf() > coin_spawn_chance:
#            return
#        
#        var x := rng.randf_range(-terrain_width / 2 + 2, terrain_width / 2 - 2)
#        var local_z := rng.randf_range(-chunk_size.y + 3, -3)
#        
#        if _is_near_hole(x, local_z, chunk_index):
#            return
#        
#        var height: float = get_height_func.call(x, local_z, chunk_index)
#        var coin := _create_coin(rng)
#        coin.position = Vector3(x, height + 0.5, local_z)  # Float above ground
#        chunk.add_child(coin)
#
# 4. Create object creation function:
#    func _create_coin(rng: RandomNumberGenerator) -> Area3D:
#        var coin := Area3D.new()
#        coin.name = "Coin"
#        coin.add_to_group("coins")
#        # ... setup collision, model, etc.
#        return coin
#
# 5. Call from spawn_objects():
#    _spawn_coins(chunk, chunk_index, get_height_func)

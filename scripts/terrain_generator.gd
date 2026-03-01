extends Node3D
## Infinite procedural terrain generator - creates low-poly terrain chunks as player moves

signal terrain_chunk_created(chunk: Node3D)
signal terrain_ready

@export var chunk_size: Vector2 = Vector2(42, 50)  # Slightly wider than playable area
@export var chunks_ahead: int = 5
@export var chunks_behind: int = 2
@export var slope_angle: float = 12.0
@export var noise_height: float = 1.0
@export var noise_scale: float = 0.02
@export var tree_density: float = 0.5  # trees per 100 sq units (~10 per chunk)
@export var rock_spawn_chance: float = 0.6  # 60% chance of 1 rock per chunk
@export var barrier_height: float = 10.0
@export var terrain_width: float = 36.0  # Playable center
@export var rock_safe_chunks: int = 2  # No rocks in first N chunks (safe zone)
@export var num_lanes: int = 5  # Divide terrain into lanes for rock placement
@export var edge_slope_height: float = 1.5  # Very gentle slope at terrain edges

var noise: FastNoiseLite
var chunks: Dictionary = {}
var current_chunk_index: int = 0
var player: Node3D
var is_ready := false

# Tree and rock model paths
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

# Fallback tree scene
var tree_scene: PackedScene = preload("res://scenes/tree.tscn")

# Shared material with color palette texture
var color_palette_material: StandardMaterial3D

# Target heights for spawned objects (in world units)
const TARGET_TREE_HEIGHT: float = 3.0  # Trees will be ~3 units tall
const TARGET_ROCK_HEIGHT: float = 0.8  # Rocks will be ~0.8 units tall

func _ready() -> void:
	add_to_group("terrain_generator")
	
	# Create shared material with color palette texture
	color_palette_material = StandardMaterial3D.new()
	var texture := load("res://assets/textures/color-palette.png") as Texture2D
	if texture:
		print("Color palette texture loaded: ", texture.get_size())
		color_palette_material.albedo_texture = texture
		# Use NEAREST for pixel-perfect color palette sampling
		color_palette_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		printerr("ERROR: Failed to load color-palette.png!")
	color_palette_material.roughness = 0.9
	color_palette_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX  # Low-poly style
	
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = noise_scale
	noise.seed = randi()
	
	for i in range(-chunks_behind, chunks_ahead + 1):
		_generate_chunk(i)
	
	is_ready = true
	terrain_ready.emit()
	await get_tree().process_frame
	player = get_tree().get_first_node_in_group("player")

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
	
	# Remove chunks that are too far behind (more aggressive cleanup)
	var chunks_to_remove: Array[int] = []
	for chunk_index in chunks.keys():
		if chunk_index < current_chunk_index - chunks_behind:
			chunks_to_remove.append(chunk_index)
	
	for chunk_index in chunks_to_remove:
		chunks[chunk_index].queue_free()
		chunks.erase(chunk_index)

func _generate_chunk(chunk_index: int) -> void:
	if chunks.has(chunk_index):
		return
	
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d" % chunk_index
	add_child(chunk)
	
	# Chunk is at world Z position, Y is calculated from slope
	var chunk_z := -chunk_index * chunk_size.y
	# Base Y height decreases as we go further (more negative Z = lower Y)
	var chunk_y := chunk_z * tan(deg_to_rad(slope_angle))
	chunk.position = Vector3(0, chunk_y, chunk_z)
	
	var terrain := _create_lowpoly_terrain(chunk_index)
	chunk.add_child(terrain)
	
	_create_barriers(chunk)
	_spawn_decorations(chunk, chunk_index)
	
	chunks[chunk_index] = chunk
	terrain_chunk_created.emit(chunk)

func _create_lowpoly_terrain(chunk_index: int) -> StaticBody3D:
	var static_body := StaticBody3D.new()
	static_body.name = "Terrain"
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var resolution := 12
	var cell_width := chunk_size.x / resolution
	var cell_length := chunk_size.y / resolution
	
	var heights: Array = []
	for z in range(resolution + 1):
		var row: Array = []
		for x in range(resolution + 1):
			var world_x := (x - resolution / 2.0) * cell_width
			var world_z := -z * cell_length - chunk_index * chunk_size.y
			
			var height := noise.get_noise_2d(world_x * 3, world_z * 3) * noise_height
			height += noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * noise_height * 2
			
			# Edge zone: gentle gradual slope at terrain edges (where mountains will be placed)
			var half_terrain: float = terrain_width / 2.0
			var half_chunk: float = chunk_size.x / 2.0
			var abs_x: float = absf(world_x)
			if abs_x > half_terrain:
				# Very gentle linear slope in edge zone (25% of width on each side)
				var edge_progress: float = (abs_x - half_terrain) / (half_chunk - half_terrain)
				height += edge_progress * edge_slope_height
			
			var slope_offset := z * cell_length * tan(deg_to_rad(slope_angle))
			height -= slope_offset
			
			row.append(height)
		heights.append(row)
	
	for z in range(resolution):
		for x in range(resolution):
			var x0 := (x - resolution / 2.0) * cell_width
			var x1 := (x + 1 - resolution / 2.0) * cell_width
			var z0 := -z * cell_length
			var z1 := -(z + 1) * cell_length
			
			var h00: float = heights[z][x]
			var h10: float = heights[z][x + 1]
			var h01: float = heights[z + 1][x]
			var h11: float = heights[z + 1][x + 1]
			
			var v0 := Vector3(x0, h00, z0)
			var v1 := Vector3(x1, h10, z0)
			var v2 := Vector3(x0, h01, z1)
			var v3 := Vector3(x1, h11, z1)
			
			# Flip triangle winding for correct normals (facing UP)
			var normal1 := (v2 - v0).cross(v1 - v0).normalized()
			st.set_normal(normal1)
			var color1 := _get_terrain_color(h00, x0, z0 - chunk_index * chunk_size.y)
			st.set_color(color1)
			st.add_vertex(v0)
			st.set_color(color1)
			st.add_vertex(v2)
			st.set_color(color1)
			st.add_vertex(v1)
			
			var normal2 := (v2 - v1).cross(v3 - v1).normalized()
			st.set_normal(normal2)
			var color2 := _get_terrain_color(h11, x1, z1 - chunk_index * chunk_size.y)
			st.set_color(color2)
			st.add_vertex(v1)
			st.set_color(color2)
			st.add_vertex(v2)
			st.set_color(color2)
			st.add_vertex(v3)
	
	var mesh := st.commit()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # No lighting - consistent colors
	mesh_instance.set_surface_override_material(0, material)
	static_body.add_child(mesh_instance)
	
	# Create collision shape from mesh
	var col_shape := CollisionShape3D.new()
	col_shape.shape = mesh.create_trimesh_shape()
	static_body.add_child(col_shape)
	
	return static_body

func _get_terrain_color(height: float, world_x: float, world_z: float) -> Color:
	# Darker colors (50% of original brightness)
	var grass_dark := Color(0.11, 0.21, 0.09)
	var grass_light := Color(0.18, 0.28, 0.13)
	var grass_yellow := Color(0.23, 0.25, 0.10)
	var rock_gray := Color(0.23, 0.22, 0.20)  # Gray rock color for mountains
	var rock_dark := Color(0.18, 0.17, 0.15)  # Darker rock
	
	var color_noise := noise.get_noise_2d(world_x * 5, world_z * 5)
	
	var base_color: Color
	if color_noise > 0.3:
		base_color = grass_light
	elif color_noise > -0.2:
		base_color = grass_dark
	else:
		base_color = grass_yellow
	
	# Edge zone coloring - transition to rock/mountain color in edge zones
	var half_terrain: float = terrain_width / 2.0
	var abs_x: float = absf(world_x)
	if abs_x > half_terrain * 0.7:
		# Transition to rock/mountain color
		var rock_blend: float = (abs_x - half_terrain * 0.7) / (half_terrain * 0.3)
		rock_blend = clampf(rock_blend, 0.0, 1.0)
		var rock_color := rock_gray if color_noise > 0 else rock_dark
		base_color = base_color.lerp(rock_color, rock_blend)
	
	return base_color

func _create_barriers(chunk: Node3D) -> void:
	# Invisible collision barriers at edge of playable area (green/gray boundary)
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

func _spawn_decorations(chunk: Node3D, chunk_index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 12345)
	
	# Spawn trees
	var area := chunk_size.x * chunk_size.y
	var tree_count := int(area * tree_density / 100.0)
	tree_count = max(tree_count, 1)  # At least 1 tree per chunk
	
	for i in range(tree_count):
		var x := rng.randf_range(-terrain_width / 2 + 2, terrain_width / 2 - 2)
		var local_z := rng.randf_range(-chunk_size.y + 3, -3)
		var height := _get_decoration_height(x, local_z, chunk_index)
		
		# Create tree from random model
		var tree := _create_tree(rng)
		# Place exactly on terrain surface
		tree.position = Vector3(x, height, local_z)
		tree.rotation.y = rng.randf_range(0, TAU)
		# Scale tree to target height with some variation
		var target_h := TARGET_TREE_HEIGHT * rng.randf_range(0.8, 1.2)
		_scale_to_target_height(tree, target_h)
		chunk.add_child(tree)
	
	# Spawn rocks - lane-based system (2-4 rocks per chunk, always passable)
	if chunk_index >= rock_safe_chunks:
		# Use separate RNG for rocks to avoid tree spawn count affecting rock spawns
		var rock_rng := RandomNumberGenerator.new()
		rock_rng.seed = hash(chunk_index * 54321 + 999)
		
		# Spawn 4-8 rocks per chunk (2x more), spread across Z axis
		var num_rocks := rock_rng.randi_range(4, 8)
		var z_section_size := chunk_size.y / float(num_rocks)
		var used_lanes: Array[int] = []  # Track recently used lanes to avoid clustering
		
		for rock_i in range(num_rocks):
			# Each rock gets its own Z section to ensure spacing
			var z_start := -chunk_size.y + rock_i * z_section_size + 3
			var z_end := -chunk_size.y + (rock_i + 1) * z_section_size - 3
			var local_z := rock_rng.randf_range(z_start, z_end)
			
			# Pick a lane, avoiding recently used lanes if possible
			var lane_width := terrain_width / float(num_lanes)
			var lane := rock_rng.randi_range(0, num_lanes - 1)
			
			# Try to pick a different lane than the last one
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
			var height := _get_decoration_height(x, local_z, chunk_index)
			
			var rock := _create_rock_from_model(rock_rng)
			# Place exactly on terrain surface
			rock.position = Vector3(x, height, local_z)
			rock.rotation.y = rock_rng.randf_range(0, TAU)
			# Scale rock to target height with some variation
			var target_h := TARGET_ROCK_HEIGHT * rock_rng.randf_range(0.7, 1.3)
			_scale_to_target_height(rock, target_h)
			chunk.add_child(rock)

# Get height at local chunk position (without global slope - chunk Y handles that)
func _get_local_height(local_x: float, local_z: float) -> float:
	var height: float = noise.get_noise_2d(local_x * 3, local_z * 3) * noise_height
	height += noise.get_noise_2d(local_x * 0.5, local_z * 0.5) * noise_height * 2
	
	# Edge zone: gentle linear slope at terrain edges
	var half_terrain: float = terrain_width / 2.0
	var half_chunk: float = chunk_size.x / 2.0
	var abs_x: float = absf(local_x)
	if abs_x > half_terrain:
		var edge_progress: float = (abs_x - half_terrain) / (half_chunk - half_terrain)
		height += edge_progress * edge_slope_height
	
	# Local slope within chunk
	height -= (-local_z) * tan(deg_to_rad(slope_angle))
	
	return height

# Get height for decorations - uses world coordinates for noise sampling to match terrain
func _get_decoration_height(local_x: float, local_z: float, chunk_index: int) -> float:
	# Convert to world coordinates for noise sampling (same as terrain mesh generation)
	var world_z: float = local_z - chunk_index * chunk_size.y
	
	var height: float = noise.get_noise_2d(local_x * 3, world_z * 3) * noise_height
	height += noise.get_noise_2d(local_x * 0.5, world_z * 0.5) * noise_height * 2
	
	# Edge zone: gentle linear slope at terrain edges
	var half_terrain: float = terrain_width / 2.0
	var half_chunk: float = chunk_size.x / 2.0
	var abs_x: float = absf(local_x)
	if abs_x > half_terrain:
		var edge_progress: float = (abs_x - half_terrain) / (half_chunk - half_terrain)
		height += edge_progress * edge_slope_height
	
	# Local slope offset (same formula as terrain: z * cell_length * tan(slope))
	# local_z is negative (going into -Z), so we need to invert it
	var slope_offset := (-local_z) * tan(deg_to_rad(slope_angle))
	height -= slope_offset
	
	return height

func _get_height_at(world_x: float, world_z: float) -> float:
	var height: float = noise.get_noise_2d(world_x * 3, world_z * 3) * noise_height
	height += noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * noise_height * 2
	
	# Edge zone: gentle linear slope at terrain edges
	var half_terrain: float = terrain_width / 2.0
	var half_chunk: float = chunk_size.x / 2.0
	var abs_x: float = absf(world_x)
	if abs_x > half_terrain:
		var edge_progress: float = (abs_x - half_terrain) / (half_chunk - half_terrain)
		height += edge_progress * edge_slope_height
	
	height += world_z * tan(deg_to_rad(slope_angle))
	
	return height

func _create_tree(rng: RandomNumberGenerator) -> RigidBody3D:
	# Create RigidBody3D for physics (falling)
	var tree := RigidBody3D.new()
	tree.name = "Tree"
	tree.mass = 20.0
	tree.freeze = true
	# Tree doesn't block player - collision layer 0
	tree.collision_layer = 0
	tree.collision_mask = 1  # Only collide with terrain when falling
	tree.set_script(preload("res://scripts/tree.gd"))
	
	# Load random tree model
	var model_path: String = tree_models[rng.randi() % tree_models.size()]
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model, color_palette_material)
		tree.add_child(model)
	
	# Add Area3D for detecting player collision (non-blocking)
	# Collision shape will be adjusted after scaling
	var detect_area := Area3D.new()
	detect_area.name = "DetectArea"
	detect_area.collision_layer = 0
	detect_area.collision_mask = 2  # Detect player (layer 2)
	detect_area.monitoring = true
	
	var col_shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# Bigger collision for better detection
	capsule.radius = 0.6
	capsule.height = 2.5
	col_shape.shape = capsule
	col_shape.position.y = 1.25
	detect_area.add_child(col_shape)
	tree.add_child(detect_area)
	
	return tree

# Get combined AABB of all meshes in a node hierarchy
func _get_model_aabb(node: Node) -> AABB:
	var combined_aabb := AABB()
	var found_mesh := false
	
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			var mesh_aabb := mesh_instance.mesh.get_aabb()
			# Transform AABB by node's transform
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

# Scale a node so its model reaches the target height
func _scale_to_target_height(node: Node3D, target_height: float) -> void:
	# Find the model child node
	var model: Node = null
	for child in node.get_children():
		if child.name == "Model" or child is Node3D:
			model = child
			break
	
	if not model:
		# No model found, use default scale
		node.scale = Vector3.ONE * 0.5
		return
	
	# Get the AABB of the model
	var aabb := _get_model_aabb(model)
	if aabb.size.y <= 0.001:
		# Invalid AABB, use default scale
		node.scale = Vector3.ONE * 0.5
		return
	
	# Calculate uniform scale to achieve target height
	var current_height := aabb.size.y
	var scale_factor := target_height / current_height
	node.scale = Vector3(scale_factor, scale_factor, scale_factor)

# Apply material to all MeshInstance3D nodes recursively
# This applies our color palette texture and unshaded mode
func _apply_material_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh:
			var surface_count := mesh_instance.mesh.get_surface_count()
			for i in range(surface_count):
				# Get existing material
				var existing_mat := mesh_instance.get_active_material(i)
				var new_mat: StandardMaterial3D
				
				if existing_mat is StandardMaterial3D:
					# Clone existing material
					new_mat = existing_mat.duplicate() as StandardMaterial3D
				else:
					# No StandardMaterial3D, create new one
					new_mat = StandardMaterial3D.new()
					new_mat.albedo_color = Color(0.5, 0.5, 0.5)
				
				# Apply our color palette texture for consistent look
				new_mat.albedo_texture = color_palette_material.albedo_texture
				new_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				# Make it unshaded for consistent lighting
				new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh_instance.set_surface_override_material(i, new_mat)
	
	for child in node.get_children():
		_apply_material_recursive(child, material)

func _create_rock_from_model(rng: RandomNumberGenerator) -> StaticBody3D:
	var rock := StaticBody3D.new()
	rock.name = "Rock"
	rock.add_to_group("rocks")  # Add to group for reliable collision detection
	# Rocks block the player - collision layer 1
	rock.collision_layer = 1
	rock.collision_mask = 0
	
	# Load random rock model
	var model_path: String = rock_models[rng.randi() % rock_models.size()]
	var model_scene := load(model_path) as PackedScene
	if model_scene:
		var model := model_scene.instantiate()
		model.name = "Model"
		_apply_material_recursive(model, color_palette_material)
		rock.add_child(model)
	
	# Add collision shape (approximate with sphere for rocks)
	# Collision shape values will be correct after _scale_to_target_height
	var col_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.4
	col_shape.shape = sphere
	col_shape.position.y = 0.3
	rock.add_child(col_shape)
	
	return rock

# Fallback procedural rock (not used anymore but kept for reference)
func _create_rock(rng: RandomNumberGenerator) -> StaticBody3D:
	var rock := StaticBody3D.new()
	rock.name = "Rock"
	rock.add_to_group("rocks")  # Add to group for reliable collision detection
	
	var size_x := rng.randf_range(0.4, 1.2)
	var size_y := rng.randf_range(0.3, 0.8)
	var size_z := rng.randf_range(0.4, 1.0)
	
	var mesh_instance := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(size_x, size_y, size_z)
	mesh_instance.mesh = box_mesh
	mesh_instance.position.y = size_y / 2
	
	var material := StandardMaterial3D.new()
	var gray := rng.randf_range(0.15, 0.25)  # Darker values
	material.albedo_color = Color(gray, gray * 0.9, gray * 0.8)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.set_surface_override_material(0, material)
	rock.add_child(mesh_instance)
	
	var col_shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(size_x, size_y, size_z)
	col_shape.shape = box_shape
	col_shape.position.y = size_y / 2
	rock.add_child(col_shape)
	
	return rock

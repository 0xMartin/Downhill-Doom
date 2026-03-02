extends Node3D
## Infinite procedural terrain generator - creates low-poly terrain chunks as player moves

signal terrain_chunk_created(chunk: Node3D)
signal terrain_ready

@export var chunk_size: Vector2 = Vector2(100, 50)  # Wide enough for mountains on both sides
@export var chunks_ahead: int = 5
@export var chunks_behind: int = 2
@export var slope_angle: float = 12.0
@export var noise_height: float = 1.0
@export var noise_scale: float = 0.02
@export var tree_density: float = 0.5  # trees per 100 sq units (~10 per chunk)
@export var rock_spawn_chance: float = 0.6  # 60% chance of 1 rock per chunk
@export var barrier_height: float = 10.0
@export var terrain_width: float = 36.0  # Playable center (green area)
@export var rock_safe_chunks: int = 2  # No rocks in first N chunks (safe zone)
@export var num_lanes: int = 5  # Divide terrain into lanes for rock placement
@export var edge_slope_height: float = 1.5  # Very gentle slope at terrain edges

# Mountain parameters
@export var mountain_width: float = 25.0  # Width of mountain slope on each side
@export var mountain_height: float = 21.0  # Peak height above playable area (25% higher)
@export var peak_curve_width: float = 7.0  # Width of the rounded dome at peak
@export var mountain_noise_strength: float = 3.5  # Variation in mountain shape
@export var grid_jitter: float = 0.35  # Random offset for vertex positions (0-1, relative to cell size)

# Hole parameters
@export_group("Holes")
@export var hole_enabled: bool = true
@export var hole_min_spacing: float = 50.0  # Minimum distance between holes (50-80)
@export var hole_max_spacing: float = 80.0  # Maximum distance between holes
@export var hole_safe_chunks: int = 3  # No holes in first N chunks
@export var narrow_hole_width: float = 8.0  # Width of narrow holes to jump over (doubled)
@export var narrow_hole_irregularity: float = 3.0  # How much the narrow hole varies
@export var hole_depth: float = 8.0  # How deep holes are (5-10)
@export var narrow_hole_chance: float = 0.4  # 40% chance of narrow vs 60% random hole
@export var random_hole_min_radius: float = 6.0  # Min radius of random holes (doubled)
@export var random_hole_max_radius: float = 10.0  # Max radius of random holes (doubled)

var noise: FastNoiseLite
var chunks: Dictionary = {}
var current_chunk_index: int = 0
var player: Node3D
var is_ready := false
var last_hole_z: float = 0.0  # Track last hole Z position for spacing

# Fog texture for hole particles
var fog_texture: Texture2D

# Hole data for terrain cutouts - stored per chunk
# Format: { chunk_index: [{ "type": "narrow"/"random", "local_z": float, "x": float (for random), "radius": float (for random) }] }
var chunk_holes: Dictionary = {}

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
	
	# Load fog texture for hole particles
	fog_texture = load("res://assets/textures/fog.png") as Texture2D
	if not fog_texture:
		printerr("WARNING: Failed to load fog.png for hole particles")
	
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
		chunk_holes.erase(chunk_index)  # Clean up hole data too

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
	
	# Pre-calculate holes for this chunk BEFORE terrain generation
	_precalculate_holes(chunk_index)
	
	var terrain := _create_lowpoly_terrain(chunk_index)
	chunk.add_child(terrain)
	
	_create_barriers(chunk)
	_spawn_holes(chunk, chunk_index)
	_spawn_decorations(chunk, chunk_index)
	
	chunks[chunk_index] = chunk
	terrain_chunk_created.emit(chunk)

func _create_lowpoly_terrain(chunk_index: int) -> StaticBody3D:
	var static_body := StaticBody3D.new()
	static_body.name = "Terrain"
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Separate SurfaceTool for hole walls (rendered as part of terrain mesh)
	var hole_st := SurfaceTool.new()
	hole_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hole_color := Color(0.02, 0.02, 0.03)  # Dark color for hole interior
	
	# Use uniform cell size for 1:1 triangle ratio
	var cell_size := 2.0  # Square cells
	var resolution_x := int(chunk_size.x / cell_size)
	var resolution_z := int(chunk_size.y / cell_size)
	var cell_width := chunk_size.x / resolution_x
	var cell_length := chunk_size.y / resolution_z
	
	# Store vertex data: position and height for each grid point
	var vertex_data: Array = []  # [z][x] = {pos: Vector2, height: float}
	for z in range(resolution_z + 1):
		var row: Array = []
		for x in range(resolution_x + 1):
			var base_x := (x - resolution_x / 2.0) * cell_width
			var base_z := -z * cell_length
			var world_z := base_z - chunk_index * chunk_size.y
			
			# Add jitter to vertex position (but not at edges to ensure chunk connectivity)
			var jitter_x := 0.0
			var jitter_z := 0.0
			var is_edge := (x == 0 or x == resolution_x or z == 0 or z == resolution_z)
			if not is_edge and grid_jitter > 0:
				# Use noise for consistent jitter based on world position
				jitter_x = noise.get_noise_2d(base_x * 7.3 + 1000, world_z * 7.3) * cell_width * grid_jitter
				jitter_z = noise.get_noise_2d(base_x * 7.3, world_z * 7.3 + 1000) * cell_length * grid_jitter
			
			var world_x := base_x + jitter_x
			var local_z := base_z + jitter_z
			var actual_world_z := world_z + jitter_z
			
			# Get U-profile height (mountains on sides, flat center)
			var profile_height := _get_cross_section_height(world_x, actual_world_z)
			
			# Add terrain noise only in playable area
			var abs_x := absf(world_x)
			var half_terrain := terrain_width / 2.0
			var terrain_noise := 0.0
			if abs_x < half_terrain:
				terrain_noise = noise.get_noise_2d(world_x * 3, actual_world_z * 3) * noise_height
				terrain_noise += noise.get_noise_2d(world_x * 0.5, actual_world_z * 0.5) * noise_height * 2
			
			var height := profile_height + terrain_noise
			
			# Apply downhill slope
			var slope_offset := (-local_z) * tan(deg_to_rad(slope_angle))
			height -= slope_offset
			
			row.append({"x": world_x, "z": local_z, "world_z": actual_world_z, "height": height})
		vertex_data.append(row)
	
	# Track hole data for floor and walls
	var hole_min_x: float = INF
	var hole_max_x: float = -INF
	var hole_min_z: float = INF
	var hole_max_z: float = -INF
	var hole_min_y: float = INF
	var hole_vertex_count: int = 0
	
	# First pass: identify all hole quads and their bounds
	var hole_quads: Array[Dictionary] = []
	
	for z in range(resolution_z):
		for x in range(resolution_x):
			var d00: Dictionary = vertex_data[z][x]
			var d10: Dictionary = vertex_data[z][x + 1]
			var d01: Dictionary = vertex_data[z + 1][x]
			var d11: Dictionary = vertex_data[z + 1][x + 1]
			
			var v0 := Vector3(d00["x"], d00["height"], d00["z"])
			var v1 := Vector3(d10["x"], d10["height"], d10["z"])
			var v2 := Vector3(d01["x"], d01["height"], d01["z"])
			var v3 := Vector3(d11["x"], d11["height"], d11["z"])
			
			var center_x: float = (float(d00["x"]) + float(d11["x"])) / 2.0
			var center_z: float = (float(d00["z"]) + float(d11["z"])) / 2.0
			var is_in_hole := _is_point_in_hole(center_x, center_z, chunk_index)
			
			if is_in_hole:
				hole_quads.append({"z": z, "x": x, "v0": v0, "v1": v1, "v2": v2, "v3": v3})
				hole_vertex_count += 1
				
				# Track bounds for floor
				hole_min_x = minf(hole_min_x, minf(v0.x, minf(v1.x, minf(v2.x, v3.x))))
				hole_max_x = maxf(hole_max_x, maxf(v0.x, maxf(v1.x, maxf(v2.x, v3.x))))
				hole_min_z = minf(hole_min_z, minf(v0.z, minf(v1.z, minf(v2.z, v3.z))))
				hole_max_z = maxf(hole_max_z, maxf(v0.z, maxf(v1.z, maxf(v2.z, v3.z))))
				var avg_y := (v0.y + v1.y + v2.y + v3.y) / 4.0
				if avg_y < hole_min_y:
					hole_min_y = avg_y
	
	# Create a lookup for quick hole quad checking
	var hole_quad_lookup: Dictionary = {}
	for hq in hole_quads:
		hole_quad_lookup[Vector2i(hq["x"], hq["z"])] = true
	
	# Second pass: create terrain and hole walls
	for z in range(resolution_z):
		for x in range(resolution_x):
			var d00: Dictionary = vertex_data[z][x]
			var d10: Dictionary = vertex_data[z][x + 1]
			var d01: Dictionary = vertex_data[z + 1][x]
			var d11: Dictionary = vertex_data[z + 1][x + 1]
			
			var v0 := Vector3(d00["x"], d00["height"], d00["z"])
			var v1 := Vector3(d10["x"], d10["height"], d10["z"])
			var v2 := Vector3(d01["x"], d01["height"], d01["z"])
			var v3 := Vector3(d11["x"], d11["height"], d11["z"])
			
			var is_hole_quad := hole_quad_lookup.has(Vector2i(x, z))
			
			if is_hole_quad:
				# Check all 4 neighbors and create walls where needed
				# Front edge (z-1): v0-v1
				var front_is_hole := hole_quad_lookup.has(Vector2i(x, z - 1))
				if not front_is_hole:
					_add_hole_wall_edge(hole_st, hole_color, v0, v1, hole_depth)
				
				# Back edge (z+1): v2-v3
				var back_is_hole := hole_quad_lookup.has(Vector2i(x, z + 1))
				if not back_is_hole:
					_add_hole_wall_edge(hole_st, hole_color, v3, v2, hole_depth)
				
				# Left edge (x-1): v0-v2
				var left_is_hole := hole_quad_lookup.has(Vector2i(x - 1, z))
				if not left_is_hole:
					_add_hole_wall_edge(hole_st, hole_color, v2, v0, hole_depth)
				
				# Right edge (x+1): v1-v3
				var right_is_hole := hole_quad_lookup.has(Vector2i(x + 1, z))
				if not right_is_hole:
					_add_hole_wall_edge(hole_st, hole_color, v1, v3, hole_depth)
				
				continue  # Skip terrain quad
			
			# Calculate distance to nearest hole for dirt color blending
			var center_x: float = (float(d00["x"]) + float(d11["x"])) / 2.0
			var center_z: float = (float(d00["z"]) + float(d11["z"])) / 2.0
			var hole_dist := _get_distance_to_nearest_hole(center_x, center_z, chunk_index)
			
			# Flip triangle winding for correct normals (facing UP)
			var normal1 := (v2 - v0).cross(v1 - v0).normalized()
			st.set_normal(normal1)
			var color1 := _get_terrain_color(d00["height"], d00["x"], d00["world_z"], hole_dist)
			st.set_color(color1)
			st.add_vertex(v0)
			st.set_color(color1)
			st.add_vertex(v2)
			st.set_color(color1)
			st.add_vertex(v1)
			
			var normal2 := (v2 - v1).cross(v3 - v1).normalized()
			st.set_normal(normal2)
			var color2 := _get_terrain_color(d11["height"], d11["x"], d11["world_z"], hole_dist)
			st.set_color(color2)
			st.add_vertex(v1)
			st.set_color(color2)
			st.add_vertex(v2)
			st.set_color(color2)
			st.add_vertex(v3)
	
	# Create hole floor if we have any holes
	if hole_vertex_count > 0:
		var floor_y := hole_min_y - hole_depth
		
		# Create solid floor quad covering all hole area with large margin to prevent escape
		var floor_margin := 10.0  # Large margin to ensure no escape
		var floor_v0 := Vector3(hole_min_x - floor_margin, floor_y, hole_min_z - floor_margin)
		var floor_v1 := Vector3(hole_max_x + floor_margin, floor_y, hole_min_z - floor_margin)
		var floor_v2 := Vector3(hole_min_x - floor_margin, floor_y, hole_max_z + floor_margin)
		var floor_v3 := Vector3(hole_max_x + floor_margin, floor_y, hole_max_z + floor_margin)
		
		# Floor visible from above (player looking down) - use DOWN normal with reversed winding
		hole_st.set_color(hole_color)
		hole_st.set_normal(Vector3.DOWN)
		
		# Triangle 1 (reversed winding for visibility from above)
		hole_st.add_vertex(floor_v0)
		hole_st.add_vertex(floor_v1)
		hole_st.add_vertex(floor_v2)
		
		# Triangle 2
		hole_st.add_vertex(floor_v1)
		hole_st.add_vertex(floor_v3)
		hole_st.add_vertex(floor_v2)
		
		# Store hole floor info for death collider positioning
		if chunk_holes.has(chunk_index) and not chunk_holes[chunk_index].is_empty():
			var hole_center_z := (hole_min_z + hole_max_z) / 2.0
			for hole in chunk_holes[chunk_index]:
				hole["floor_y"] = floor_y
				hole["actual_center_z"] = hole_center_z
	
	var mesh := st.commit()
	if mesh == null:
		printerr("ERROR: Failed to create terrain mesh for chunk ", chunk_index)
		return static_body
	
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # No lighting - consistent colors
	mesh_instance.set_surface_override_material(0, material)
	static_body.add_child(mesh_instance)
	
	# Create hole walls mesh if we have hole geometry
	if hole_vertex_count > 0:
		var hole_mesh := hole_st.commit()
		if hole_mesh != null and hole_mesh.get_surface_count() > 0:
			var hole_mesh_instance := MeshInstance3D.new()
			hole_mesh_instance.name = "HoleWalls"
			hole_mesh_instance.mesh = hole_mesh
			
			var hole_material := StandardMaterial3D.new()
			hole_material.vertex_color_use_as_albedo = true
			hole_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hole_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Show both sides
			hole_mesh_instance.set_surface_override_material(0, hole_material)
			static_body.add_child(hole_mesh_instance)
			
			# Add collision for hole walls
			var hole_col_shape := CollisionShape3D.new()
			hole_col_shape.shape = hole_mesh.create_trimesh_shape()
			static_body.add_child(hole_col_shape)
	
	# Create collision shape from mesh
	if mesh.get_surface_count() > 0:
		var col_shape := CollisionShape3D.new()
		col_shape.shape = mesh.create_trimesh_shape()
		static_body.add_child(col_shape)
	
	return static_body

# Calculate U-shaped cross-section height with rounded mountain peaks
func _get_cross_section_height(world_x: float, world_z: float) -> float:
	var half_terrain := terrain_width / 2.0
	var abs_x := absf(world_x)
	
	# Flat playable area (center)
	if abs_x <= half_terrain:
		return 0.0
	
	# Mountain zone - base position can wobble laterally
	var lateral_wobble := noise.get_noise_2d(world_x * 0.15, world_z * 0.15) * 3.0
	var effective_abs_x := abs_x + lateral_wobble
	effective_abs_x = maxf(effective_abs_x, half_terrain + 0.1)  # Keep positive slope
	
	var mountain_start := half_terrain
	var slope_end := half_terrain + mountain_width - peak_curve_width
	var peak_end := half_terrain + mountain_width
	
	# Add noise variation to mountain shape - more pronounced
	var mountain_noise := noise.get_noise_2d(world_x * 0.4, world_z * 0.4) * mountain_noise_strength * 2.0
	var peak_variation := noise.get_noise_2d(world_x * 0.08, world_z * 0.08) * 10.0  # 40% more variation
	
	if effective_abs_x <= slope_end:
		# Rising slope using smoothstep for smooth curve
		var t := (effective_abs_x - mountain_start) / (slope_end - mountain_start)
		t = clampf(t, 0.0, 1.0)
		var smooth_t := t * t * (3.0 - 2.0 * t)  # smoothstep
		return smooth_t * (mountain_height + peak_variation) + mountain_noise * smooth_t
	else:
		# Peak dome - rounded top that curves back down
		var peak_progress := (effective_abs_x - slope_end) / peak_curve_width
		peak_progress = clampf(peak_progress, 0.0, 1.5)
		var base_height := mountain_height + peak_variation
		# Use cosine for rounded dome shape
		var dome_shape := cos(peak_progress * PI * 0.5)  # Goes from 1 to 0
		# Add small overhang effect - peak curves slightly inward then down
		var overhang := sin(peak_progress * PI) * 1.5
		return base_height * dome_shape + overhang + mountain_noise

func _get_terrain_color(height: float, world_x: float, world_z: float, hole_distance: float = -1.0) -> Color:
	# Grass colors for playable area - moderate contrast
	var grass_light := Color(0.18, 0.28, 0.12)
	var grass_dark := Color(0.10, 0.18, 0.08)
	var grass_yellow := Color(0.20, 0.22, 0.10)
	
	# Dirt/earth colors near holes
	var dirt_light := Color(0.45, 0.30, 0.15)
	var dirt_dark := Color(0.38, 0.25, 0.12)
	
	# Mountain colors - subtle gray variations (low contrast)
	var rock_light := Color(0.30, 0.29, 0.27)
	var rock_medium := Color(0.26, 0.25, 0.24)
	var rock_dark := Color(0.22, 0.21, 0.20)
	
	# Snow/ice for peaks
	var snow_color := Color(0.90, 0.91, 0.93)
	
	var color_noise := noise.get_noise_2d(world_x * 5, world_z * 5)
	var detail_noise := noise.get_noise_2d(world_x * 8, world_z * 8)
	
	var half_terrain := terrain_width / 2.0
	var abs_x := absf(world_x)
	
	# Near hole - blend to dirt color (only in playable area)
	var hole_blend_distance := 8.0
	if hole_distance >= 0.0 and hole_distance < hole_blend_distance and abs_x <= half_terrain:
		# Calculate base grass color
		var base_color: Color
		if color_noise > 0.25:
			base_color = grass_light
		elif color_noise > -0.25:
			var blend := (color_noise + 0.25) / 0.5
			base_color = grass_dark.lerp(grass_light, blend)
		else:
			base_color = grass_dark.lerp(grass_yellow, (-color_noise - 0.25) / 0.75)
		
		# Blend to dirt based on distance (closer = more dirt)
		var dirt_blend := 1.0 - (hole_distance / hole_blend_distance)
		var dirt_target := dirt_light if detail_noise > 0 else dirt_dark
		return base_color.lerp(dirt_target, dirt_blend)  # Full blend to dirt at edge
	
	# Playable area - grass colors with moderate variation
	if abs_x <= half_terrain:
		if color_noise > 0.25:
			return grass_light
		elif color_noise > -0.25:
			var blend := (color_noise + 0.25) / 0.5
			return grass_dark.lerp(grass_light, blend)
		else:
			return grass_dark.lerp(grass_yellow, (-color_noise - 0.25) / 0.75)
	
	# Mountain zone - calculate progress up the mountain
	var mountain_start := half_terrain
	var mountain_progress := (abs_x - mountain_start) / mountain_width
	
	# Transition zone at base of mountain (grass to rock) - very subtle blend
	if mountain_progress < 0.25:
		# Use smoothstep for very gradual transition
		var raw_blend := mountain_progress / 0.25
		var blend := raw_blend * raw_blend * (3.0 - 2.0 * raw_blend)  # smoothstep
		# Start with grass color matching the playable area
		var grass_color: Color
		if color_noise > 0.25:
			grass_color = grass_light
		elif color_noise > -0.25:
			grass_color = grass_dark.lerp(grass_light, (color_noise + 0.25) / 0.5)
		else:
			grass_color = grass_dark.lerp(grass_yellow, (-color_noise - 0.25) / 0.75)
		# Transition to a rock color that's close to the grass initially
		var rock_color := rock_medium.lerp(rock_dark, (detail_noise + 1.0) * 0.3)
		return grass_color.lerp(rock_color, blend)
	
	# Main mountain slope - rock variations
	if mountain_progress < 0.75:
		if detail_noise > 0.2:
			return rock_light
		elif detail_noise > -0.2:
			return rock_medium
		else:
			return rock_dark
	
	# Upper mountain / peak zone - blend rock to snow
	var peak_progress := (mountain_progress - 0.75) / 0.25
	var rock_color := rock_medium if detail_noise > 0 else rock_dark
	
	# Gradual snow blend at the very top
	if peak_progress > 0.35:
		var snow_blend := (peak_progress - 0.35) / 0.65
		return rock_color.lerp(snow_color, snow_blend * 0.7)
	
	return rock_color

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
		
		# Skip if in or near hole area
		if _get_distance_to_nearest_hole(x, local_z, chunk_index) < 3.0:
			continue
		
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
			
			# Skip if in or near hole area
			if _get_distance_to_nearest_hole(x, local_z, chunk_index) < 3.0:
				continue
			
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
	
	# Get U-profile height (should be 0 in playable area)
	var profile_height := _get_cross_section_height(local_x, world_z)
	
	# Add terrain noise (only in playable area)
	var terrain_noise := noise.get_noise_2d(local_x * 3, world_z * 3) * noise_height
	terrain_noise += noise.get_noise_2d(local_x * 0.5, world_z * 0.5) * noise_height * 2
	
	var height := profile_height + terrain_noise
	
	# Local slope offset (same formula as terrain: z * cell_length * tan(slope))
	# local_z is negative (going into -Z), so we need to invert it
	var slope_offset := (-local_z) * tan(deg_to_rad(slope_angle))
	height -= slope_offset
	
	return height

func _get_height_at(world_x: float, world_z: float) -> float:
	# Get U-profile height
	var profile_height := _get_cross_section_height(world_x, world_z)
	
	# Add terrain noise (only in playable area)
	var half_terrain := terrain_width / 2.0
	var abs_x := absf(world_x)
	var terrain_noise := 0.0
	if abs_x < half_terrain:
		terrain_noise = noise.get_noise_2d(world_x * 3, world_z * 3) * noise_height
		terrain_noise += noise.get_noise_2d(world_x * 0.5, world_z * 0.5) * noise_height * 2
	
	var height := profile_height + terrain_noise
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

# ====== HOLE GENERATION ======

# Pre-calculate hole positions for a chunk (called before terrain generation)
func _precalculate_holes(chunk_index: int) -> void:
	if not hole_enabled:
		chunk_holes[chunk_index] = []
		return
	
	# No holes in safe zone
	if chunk_index < hole_safe_chunks:
		chunk_holes[chunk_index] = []
		return
	
	var holes: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 77777)
	
	# Calculate world Z range for this chunk
	var chunk_start_z := -chunk_index * chunk_size.y
	var chunk_end_z := chunk_start_z - chunk_size.y
	
	# Check if we should spawn a hole based on spacing
	var desired_spacing := rng.randf_range(hole_min_spacing, hole_max_spacing)
	var distance_from_last := absf(chunk_start_z - last_hole_z)
	
	if distance_from_last < desired_spacing:
		chunk_holes[chunk_index] = []
		return
	
	# Random chance to skip even if spacing is ok (variation)
	if rng.randf() > 0.4:  # 40% chance to spawn when eligible
		chunk_holes[chunk_index] = []
		return
	
	# Choose position within chunk (avoid edges)
	var hole_z := rng.randf_range(chunk_end_z + 10, chunk_start_z - 10)
	var local_hole_z := hole_z - chunk_start_z  # Convert to local chunk coordinates
	
	# Decide hole type and store data
	if rng.randf() < narrow_hole_chance:
		holes.append({
			"type": "narrow",
			"local_z": local_hole_z,
			"width": narrow_hole_width
		})
	else:
		var hole_x := rng.randf_range(-terrain_width / 2 + random_hole_max_radius + 2, 
									   terrain_width / 2 - random_hole_max_radius - 2)
		var radius := rng.randf_range(random_hole_min_radius, random_hole_max_radius)
		holes.append({
			"type": "random",
			"local_z": local_hole_z,
			"x": hole_x,
			"radius": radius
		})
	
	# Update last hole position (world Z)
	last_hole_z = hole_z
	chunk_holes[chunk_index] = holes

# Check if a point (local coordinates) is inside any hole in the chunk
func _is_point_in_hole(local_x: float, local_z: float, chunk_index: int) -> bool:
	if not chunk_holes.has(chunk_index):
		return false
	
	var holes: Array = chunk_holes[chunk_index]
	var half_terrain := terrain_width / 2.0 - 1.0
	
	for hole in holes:
		if hole["type"] == "narrow":
			# Narrow hole spans entire width, check Z
			var hole_z: float = hole["local_z"]
			var half_width: float = hole["width"] / 2.0 + narrow_hole_irregularity + 1.0  # Extra margin
			# Only in playable area
			if absf(local_x) < half_terrain:
				if local_z > hole_z - half_width and local_z < hole_z + half_width:
					return true
		else:  # random hole
			var hole_x: float = hole["x"]
			var hole_z: float = hole["local_z"]
			var radius: float = hole["radius"] + 1.0  # Extra margin
			var dist := sqrt((local_x - hole_x) ** 2 + (local_z - hole_z) ** 2)
			if dist < radius:
				return true
	
	return false

# Get distance to nearest hole (returns INF if no holes nearby)
func _get_distance_to_nearest_hole(local_x: float, local_z: float, chunk_index: int) -> float:
	if not chunk_holes.has(chunk_index):
		return INF
	
	var holes: Array = chunk_holes[chunk_index]
	var half_terrain := terrain_width / 2.0 - 1.0
	var min_dist := INF
	
	for hole in holes:
		if hole["type"] == "narrow":
			# Narrow hole spans entire width, distance is to Z edge
			var hole_z: float = hole["local_z"]
			var half_width: float = hole["width"] / 2.0 + narrow_hole_irregularity
			# Only consider in playable area
			if absf(local_x) < half_terrain:
				var z_dist := absf(local_z - hole_z) - half_width
				if z_dist < min_dist:
					min_dist = maxf(0.0, z_dist)
		else:  # random hole
			var hole_x: float = hole["x"]
			var hole_z: float = hole["local_z"]
			var radius: float = hole["radius"]
			var dist := sqrt((local_x - hole_x) ** 2 + (local_z - hole_z) ** 2) - radius
			if dist < min_dist:
				min_dist = maxf(0.0, dist)
	
	return min_dist

# Helper function to add a hole wall edge (two triangles forming a quad from top edge to bottom)
func _add_hole_wall_edge(st: SurfaceTool, color: Color, top_a: Vector3, top_b: Vector3, depth: float) -> void:
	var bottom_a := Vector3(top_a.x, top_a.y - depth, top_a.z)
	var bottom_b := Vector3(top_b.x, top_b.y - depth, top_b.z)
	
	# Calculate normal (facing inward to hole)
	var normal := (top_b - top_a).cross(bottom_a - top_a).normalized()
	
	st.set_color(color)
	st.set_normal(normal)
	
	# Triangle 1: top_a, bottom_a, top_b
	st.add_vertex(top_a)
	st.add_vertex(bottom_a)
	st.add_vertex(top_b)
	
	# Triangle 2: top_b, bottom_a, bottom_b
	st.add_vertex(top_b)
	st.add_vertex(bottom_a)
	st.add_vertex(bottom_b)

# Helper function to create hole floor from edge vertices
func _create_hole_floor_from_edges(st: SurfaceTool, color: Color, edge_vertices: Array[Vector3], floor_y: float) -> void:
	if edge_vertices.is_empty():
		return
	
	# Find bounding box of all edge vertices
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	
	for v in edge_vertices:
		min_x = minf(min_x, v.x)
		max_x = maxf(max_x, v.x)
		min_z = minf(min_z, v.z)
		max_z = maxf(max_z, v.z)
	
	# Add padding to ensure full coverage
	min_x -= 0.5
	max_x += 0.5
	min_z -= 0.5
	max_z += 0.5
	
	# Create solid floor as a simple quad covering the entire hole area
	var v0 := Vector3(min_x, floor_y, min_z)
	var v1 := Vector3(max_x, floor_y, min_z)
	var v2 := Vector3(min_x, floor_y, max_z)
	var v3 := Vector3(max_x, floor_y, max_z)
	
	var normal := Vector3.UP
	st.set_color(color)
	st.set_normal(normal)
	
	# Triangle 1
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v1)
	
	# Triangle 2
	st.add_vertex(v1)
	st.add_vertex(v2)
	st.add_vertex(v3)

func _spawn_holes(chunk: Node3D, chunk_index: int) -> void:
	if not hole_enabled:
		return
	
	# Use pre-calculated hole data (walls are already created in terrain mesh)
	if not chunk_holes.has(chunk_index):
		return
	
	var holes: Array = chunk_holes[chunk_index]
	if holes.is_empty():
		return
	
	# Only create death colliders and particles (walls are part of terrain now)
	for hole in holes:
		# Use local_z directly since we're in chunk local coordinates
		var local_z: float = hole["local_z"]
		
		# Calculate floor Y from terrain height at hole position
		var terrain_y := _get_decoration_height(0.0, local_z, chunk_index)
		var floor_y: float = terrain_y - hole_depth
		
		var hole_container := Node3D.new()
		hole_container.name = "HoleEffects"
		chunk.add_child(hole_container)
		
		if hole["type"] == "narrow":
			# Death collider for narrow hole - only at the bottom floor
			# Player must fall deep into the hole to die
			_create_death_collider(hole_container, 
				Vector3(0, floor_y + 1.0, local_z),
				Vector3(terrain_width + 4, 2.0, narrow_hole_width + 6))
			
			# Fog particles
			_create_hole_particles(hole_container,
				Vector3(0, floor_y + 2.5, local_z),
				Vector3(terrain_width - 4, 2, narrow_hole_width + 2))
		else:
			var hole_x: float = hole["x"]
			var radius: float = hole["radius"]
			
			# Recalculate floor Y at actual hole position
			terrain_y = _get_decoration_height(hole_x, local_z, chunk_index)
			floor_y = terrain_y - hole_depth
			
			# Death collider for random hole - only at the bottom floor
			_create_death_collider(hole_container,
				Vector3(hole_x, floor_y + 1.0, local_z),
				Vector3(radius * 2.5, 2.0, radius * 2.5))
			
			# Fog particles
			_create_hole_particles(hole_container,
				Vector3(hole_x, floor_y + 2.5, local_z),
				Vector3(radius * 1.8, 2, radius * 1.8))

func _add_quad(st: SurfaceTool, color: Color, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	# Calculate normal
	var normal := (v1 - v0).cross(v3 - v0).normalized()
	st.set_color(color)
	st.set_normal(normal)
	
	# Triangle 1: v0, v1, v2
	st.add_vertex(v0)
	st.add_vertex(v1)
	st.add_vertex(v2)
	
	# Triangle 2: v0, v2, v3
	st.add_vertex(v0)
	st.add_vertex(v2)
	st.add_vertex(v3)

func _create_death_collider(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var death_area := Area3D.new()
	death_area.name = "DeathZone"
	death_area.collision_layer = 0
	death_area.collision_mask = 2  # Detect player (layer 2)
	death_area.monitoring = true
	death_area.position = pos
	
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col_shape.shape = box
	death_area.add_child(col_shape)
	
	# Connect signal to kill player
	death_area.body_entered.connect(_on_death_zone_body_entered)
	
	parent.add_child(death_area)

func _on_death_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("die"):
		body.die()

func _create_hole_particles(parent: Node3D, pos: Vector3, emission_box: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "HoleFog"
	particles.position = pos
	particles.amount = 64  # 20% less particles
	particles.lifetime = 5.0  # Longer lifetime for smoother fade
	particles.speed_scale = 0.5
	particles.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	particles.emitting = true
	
	# Create process material
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)  # Upward
	mat.spread = 45.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 1.0
	mat.gravity = Vector3(0, 0.12, 0)  # Slight upward drift
	
	# Emission shape - box
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = emission_box / 2.0
	
	# Scale - even bigger particles
	mat.scale_min = 7.0
	mat.scale_max = 14.0
	
	# Color - bright glowing red fog with smooth fade out
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.2, 0.2, 0.0))  # Start transparent
	gradient.add_point(0.08, Color(1.0, 0.15, 0.1, 0.6))  # Quick fade in
	gradient.add_point(0.25, Color(0.95, 0.12, 0.08, 0.55))  # Peak opacity
	gradient.add_point(0.5, Color(0.85, 0.08, 0.04, 0.4))  # Starting to fade
	gradient.add_point(0.75, Color(0.6, 0.04, 0.02, 0.2))  # Fading more
	gradient.add_point(0.9, Color(0.4, 0.02, 0.01, 0.08))  # Almost gone
	gradient.set_color(1, Color(0.2, 0.0, 0.0, 0.0))  # Fully transparent
	
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex
	
	particles.process_material = mat
	
	# Create draw pass (quad mesh with fog texture)
	var quad := QuadMesh.new()
	quad.size = Vector2(8, 8)  # Even bigger quads
	
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if fog_texture:
		draw_mat.albedo_texture = fog_texture
	draw_mat.albedo_color = Color(1.0, 0.3, 0.2)  # Bright red tint
	
	quad.material = draw_mat
	particles.draw_pass_1 = quad
	
	parent.add_child(particles)

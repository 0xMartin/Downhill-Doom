class_name TerrainMeshBuilder
extends RefCounted
## Handles terrain mesh generation - lowpoly terrain with holes and mountain profiles

var noise: FastNoiseLite
var terrain_width: float
var noise_height: float
var slope_angle: float
var grid_jitter: float
var chunk_size: Vector2
var mountain_width: float
var mountain_height: float
var peak_curve_width: float
var mountain_noise_strength: float
var hole_depth: float
var narrow_hole_irregularity: float

# References for hole detection
var hole_manager: RefCounted  # HoleManager

func _init(config: Dictionary) -> void:
	noise = config.get("noise")
	terrain_width = config.get("terrain_width", 36.0)
	noise_height = config.get("noise_height", 1.0)
	slope_angle = config.get("slope_angle", 12.0)
	grid_jitter = config.get("grid_jitter", 0.35)
	chunk_size = config.get("chunk_size", Vector2(100, 50))
	mountain_width = config.get("mountain_width", 25.0)
	mountain_height = config.get("mountain_height", 21.0)
	peak_curve_width = config.get("peak_curve_width", 7.0)
	mountain_noise_strength = config.get("mountain_noise_strength", 3.5)
	hole_depth = config.get("hole_depth", 8.0)
	narrow_hole_irregularity = config.get("narrow_hole_irregularity", 3.0)

func set_hole_manager(manager: RefCounted) -> void:
	hole_manager = manager

func create_terrain(chunk_index: int) -> StaticBody3D:
	var static_body := StaticBody3D.new()
	static_body.name = "Terrain"
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Separate SurfaceTool for hole walls
	var hole_st := SurfaceTool.new()
	hole_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hole_color := Color(0.02, 0.02, 0.03)
	
	var cell_size := 2.0
	var resolution_x := int(chunk_size.x / cell_size)
	var resolution_z := int(chunk_size.y / cell_size)
	var cell_width := chunk_size.x / resolution_x
	var cell_length := chunk_size.y / resolution_z
	
	# Store vertex data
	var vertex_data: Array = []
	for z in range(resolution_z + 1):
		var row: Array = []
		for x in range(resolution_x + 1):
			var base_x := (x - resolution_x / 2.0) * cell_width
			var base_z := -z * cell_length
			var world_z := base_z - chunk_index * chunk_size.y
			
			var jitter_x := 0.0
			var jitter_z := 0.0
			var is_edge := (x == 0 or x == resolution_x or z == 0 or z == resolution_z)
			if not is_edge and grid_jitter > 0:
				jitter_x = noise.get_noise_2d(base_x * 7.3 + 1000, world_z * 7.3) * cell_width * grid_jitter
				jitter_z = noise.get_noise_2d(base_x * 7.3, world_z * 7.3 + 1000) * cell_length * grid_jitter
			
			var world_x := base_x + jitter_x
			var local_z := base_z + jitter_z
			var actual_world_z := world_z + jitter_z
			
			var profile_height := get_cross_section_height(world_x, actual_world_z)
			
			var abs_x := absf(world_x)
			var half_terrain := terrain_width / 2.0
			var terrain_noise := 0.0
			if abs_x < half_terrain:
				terrain_noise = noise.get_noise_2d(world_x * 3, actual_world_z * 3) * noise_height
				terrain_noise += noise.get_noise_2d(world_x * 0.5, actual_world_z * 0.5) * noise_height * 2
			
			var height := profile_height + terrain_noise
			var slope_offset := (-local_z) * tan(deg_to_rad(slope_angle))
			height -= slope_offset
			
			row.append({"x": world_x, "z": local_z, "world_z": actual_world_z, "height": height})
		vertex_data.append(row)
	
	# Track hole data for floor
	var hole_min_x: float = INF
	var hole_max_x: float = -INF
	var hole_min_z: float = INF
	var hole_max_z: float = -INF
	var hole_min_y: float = INF
	var hole_vertex_count: int = 0
	
	# First pass: identify hole quads
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
			var is_in_hole: bool = hole_manager.is_point_in_hole(center_x, center_z, chunk_index) if hole_manager else false
			
			if is_in_hole:
				hole_quads.append({"z": z, "x": x, "v0": v0, "v1": v1, "v2": v2, "v3": v3})
				hole_vertex_count += 1
				
				hole_min_x = minf(hole_min_x, minf(v0.x, minf(v1.x, minf(v2.x, v3.x))))
				hole_max_x = maxf(hole_max_x, maxf(v0.x, maxf(v1.x, maxf(v2.x, v3.x))))
				hole_min_z = minf(hole_min_z, minf(v0.z, minf(v1.z, minf(v2.z, v3.z))))
				hole_max_z = maxf(hole_max_z, maxf(v0.z, maxf(v1.z, maxf(v2.z, v3.z))))
				var avg_y := (v0.y + v1.y + v2.y + v3.y) / 4.0
				if avg_y < hole_min_y:
					hole_min_y = avg_y
	
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
				var front_is_hole := hole_quad_lookup.has(Vector2i(x, z - 1))
				if not front_is_hole:
					_add_hole_wall_edge(hole_st, hole_color, v0, v1, hole_depth)
				
				var back_is_hole := hole_quad_lookup.has(Vector2i(x, z + 1))
				if not back_is_hole:
					_add_hole_wall_edge(hole_st, hole_color, v3, v2, hole_depth)
				
				var left_is_hole := hole_quad_lookup.has(Vector2i(x - 1, z))
				if not left_is_hole:
					_add_hole_wall_edge(hole_st, hole_color, v2, v0, hole_depth)
				
				var right_is_hole := hole_quad_lookup.has(Vector2i(x + 1, z))
				if not right_is_hole:
					_add_hole_wall_edge(hole_st, hole_color, v1, v3, hole_depth)
				
				continue
			
			var center_x: float = (float(d00["x"]) + float(d11["x"])) / 2.0
			var center_z: float = (float(d00["z"]) + float(d11["z"])) / 2.0
			var hole_dist: float = hole_manager.get_distance_to_nearest_hole(center_x, center_z, chunk_index) if hole_manager else INF
			
			var normal1 := (v2 - v0).cross(v1 - v0).normalized()
			st.set_normal(normal1)
			var color1 := get_terrain_color(d00["height"], d00["x"], d00["world_z"], hole_dist)
			st.set_color(color1)
			st.add_vertex(v0)
			st.set_color(color1)
			st.add_vertex(v2)
			st.set_color(color1)
			st.add_vertex(v1)
			
			var normal2 := (v2 - v1).cross(v3 - v1).normalized()
			st.set_normal(normal2)
			var color2 := get_terrain_color(d11["height"], d11["x"], d11["world_z"], hole_dist)
			st.set_color(color2)
			st.add_vertex(v1)
			st.set_color(color2)
			st.add_vertex(v2)
			st.set_color(color2)
			st.add_vertex(v3)
	
	# Create hole floor
	if hole_vertex_count > 0:
		var floor_y := hole_min_y - hole_depth
		var floor_margin := 10.0
		var floor_v0 := Vector3(hole_min_x - floor_margin, floor_y, hole_min_z - floor_margin)
		var floor_v1 := Vector3(hole_max_x + floor_margin, floor_y, hole_min_z - floor_margin)
		var floor_v2 := Vector3(hole_min_x - floor_margin, floor_y, hole_max_z + floor_margin)
		var floor_v3 := Vector3(hole_max_x + floor_margin, floor_y, hole_max_z + floor_margin)
		
		hole_st.set_color(hole_color)
		hole_st.set_normal(Vector3.DOWN)
		hole_st.add_vertex(floor_v0)
		hole_st.add_vertex(floor_v1)
		hole_st.add_vertex(floor_v2)
		hole_st.add_vertex(floor_v1)
		hole_st.add_vertex(floor_v3)
		hole_st.add_vertex(floor_v2)
		
		if hole_manager:
			hole_manager.set_floor_y(chunk_index, floor_y, (hole_min_z + hole_max_z) / 2.0)
	
	var mesh := st.commit()
	if mesh == null:
		printerr("ERROR: Failed to create terrain mesh for chunk ", chunk_index)
		return static_body
	
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh_instance.set_surface_override_material(0, material)
	static_body.add_child(mesh_instance)
	
	if hole_vertex_count > 0:
		var hole_mesh := hole_st.commit()
		if hole_mesh != null and hole_mesh.get_surface_count() > 0:
			var hole_mesh_instance := MeshInstance3D.new()
			hole_mesh_instance.name = "HoleWalls"
			hole_mesh_instance.mesh = hole_mesh
			
			var hole_material := StandardMaterial3D.new()
			hole_material.vertex_color_use_as_albedo = true
			hole_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hole_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			hole_mesh_instance.set_surface_override_material(0, hole_material)
			static_body.add_child(hole_mesh_instance)
			
			var hole_col_shape := CollisionShape3D.new()
			hole_col_shape.shape = hole_mesh.create_trimesh_shape()
			static_body.add_child(hole_col_shape)
	
	if mesh.get_surface_count() > 0:
		var col_shape := CollisionShape3D.new()
		col_shape.shape = mesh.create_trimesh_shape()
		static_body.add_child(col_shape)
	
	return static_body

func get_cross_section_height(world_x: float, world_z: float) -> float:
	var half_terrain := terrain_width / 2.0
	var abs_x := absf(world_x)
	
	if abs_x <= half_terrain:
		return 0.0
	
	var lateral_wobble := noise.get_noise_2d(world_x * 0.15, world_z * 0.15) * 3.0
	var effective_abs_x := abs_x + lateral_wobble
	effective_abs_x = maxf(effective_abs_x, half_terrain + 0.1)
	
	var mountain_start := half_terrain
	var slope_end := half_terrain + mountain_width - peak_curve_width
	
	var mountain_noise := noise.get_noise_2d(world_x * 0.4, world_z * 0.4) * mountain_noise_strength * 2.0
	var peak_variation := noise.get_noise_2d(world_x * 0.08, world_z * 0.08) * 10.0
	
	if effective_abs_x <= slope_end:
		var t := (effective_abs_x - mountain_start) / (slope_end - mountain_start)
		t = clampf(t, 0.0, 1.0)
		var smooth_t := t * t * (3.0 - 2.0 * t)
		return smooth_t * (mountain_height + peak_variation) + mountain_noise * smooth_t
	else:
		var peak_progress := (effective_abs_x - slope_end) / peak_curve_width
		peak_progress = clampf(peak_progress, 0.0, 1.5)
		var base_height := mountain_height + peak_variation
		var dome_shape := cos(peak_progress * PI * 0.5)
		var overhang := sin(peak_progress * PI) * 1.5
		return base_height * dome_shape + overhang + mountain_noise

func get_terrain_color(height: float, world_x: float, world_z: float, hole_distance: float = -1.0) -> Color:
	var grass_light := Color(0.18, 0.28, 0.12)
	var grass_dark := Color(0.10, 0.18, 0.08)
	var grass_yellow := Color(0.20, 0.22, 0.10)
	var dirt_light := Color(0.45, 0.30, 0.15)
	var dirt_dark := Color(0.38, 0.25, 0.12)
	var rock_light := Color(0.30, 0.29, 0.27)
	var rock_medium := Color(0.26, 0.25, 0.24)
	var rock_dark := Color(0.22, 0.21, 0.20)
	var snow_color := Color(0.90, 0.91, 0.93)
	
	var color_noise := noise.get_noise_2d(world_x * 5, world_z * 5)
	var detail_noise := noise.get_noise_2d(world_x * 8, world_z * 8)
	
	var half_terrain := terrain_width / 2.0
	var abs_x := absf(world_x)
	
	var hole_blend_distance := 8.0
	if hole_distance >= 0.0 and hole_distance < hole_blend_distance and abs_x <= half_terrain:
		var base_color: Color
		if color_noise > 0.25:
			base_color = grass_light
		elif color_noise > -0.25:
			var blend := (color_noise + 0.25) / 0.5
			base_color = grass_dark.lerp(grass_light, blend)
		else:
			base_color = grass_dark.lerp(grass_yellow, (-color_noise - 0.25) / 0.75)
		
		var dirt_blend := 1.0 - (hole_distance / hole_blend_distance)
		var dirt_target := dirt_light if detail_noise > 0 else dirt_dark
		return base_color.lerp(dirt_target, dirt_blend)
	
	if abs_x <= half_terrain:
		if color_noise > 0.25:
			return grass_light
		elif color_noise > -0.25:
			var blend := (color_noise + 0.25) / 0.5
			return grass_dark.lerp(grass_light, blend)
		else:
			return grass_dark.lerp(grass_yellow, (-color_noise - 0.25) / 0.75)
	
	var mountain_start := half_terrain
	var mountain_progress := (abs_x - mountain_start) / mountain_width
	
	if mountain_progress < 0.25:
		var raw_blend := mountain_progress / 0.25
		var blend := raw_blend * raw_blend * (3.0 - 2.0 * raw_blend)
		var grass_color: Color
		if color_noise > 0.25:
			grass_color = grass_light
		elif color_noise > -0.25:
			grass_color = grass_dark.lerp(grass_light, (color_noise + 0.25) / 0.5)
		else:
			grass_color = grass_dark.lerp(grass_yellow, (-color_noise - 0.25) / 0.75)
		var rock_color := rock_medium.lerp(rock_dark, (detail_noise + 1.0) * 0.3)
		return grass_color.lerp(rock_color, blend)
	
	if mountain_progress < 0.75:
		if detail_noise > 0.2:
			return rock_light
		elif detail_noise > -0.2:
			return rock_medium
		else:
			return rock_dark
	
	var peak_progress := (mountain_progress - 0.75) / 0.25
	var rock_color := rock_medium if detail_noise > 0 else rock_dark
	
	if peak_progress > 0.35:
		var snow_blend := (peak_progress - 0.35) / 0.65
		return rock_color.lerp(snow_color, snow_blend * 0.7)
	
	return rock_color

func _add_hole_wall_edge(st: SurfaceTool, color: Color, top_a: Vector3, top_b: Vector3, depth: float) -> void:
	var bottom_a := Vector3(top_a.x, top_a.y - depth, top_a.z)
	var bottom_b := Vector3(top_b.x, top_b.y - depth, top_b.z)
	var normal := (top_b - top_a).cross(bottom_a - top_a).normalized()
	
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(top_a)
	st.add_vertex(bottom_a)
	st.add_vertex(top_b)
	st.add_vertex(top_b)
	st.add_vertex(bottom_a)
	st.add_vertex(bottom_b)

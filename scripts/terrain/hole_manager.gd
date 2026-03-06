class_name HoleManager
extends RefCounted
## Manages hole generation, precalculation, death zones and particle effects

signal player_died

# Hole configuration
var hole_enabled: bool = true
var hole_min_spacing: float = 50.0
var hole_max_spacing: float = 140.0
var hole_safe_chunks: int = 3
var narrow_hole_width: float = 7.0
var narrow_hole_irregularity: float = 3.0
var hole_depth: float = 8.0
var narrow_hole_chance: float = 0.4
var random_hole_min_radius: float = 6.0
var random_hole_max_radius: float = 11.0
var terrain_width: float = 36.0
var chunk_size: Vector2

# Hole data storage
# Format: { chunk_index: [{ "type": "narrow"/"random", "local_z": float, ... }] }
var chunk_holes: Dictionary = {}
var last_hole_z: float = 0.0

# Fog texture for particles
var fog_texture: Texture2D

func _init(config: Dictionary) -> void:
	hole_enabled = config.get("hole_enabled", true)
	hole_min_spacing = config.get("hole_min_spacing", 50.0)
	hole_max_spacing = config.get("hole_max_spacing", 80.0)
	hole_safe_chunks = config.get("hole_safe_chunks", 3)
	narrow_hole_width = config.get("narrow_hole_width", 8.0)
	narrow_hole_irregularity = config.get("narrow_hole_irregularity", 3.0)
	hole_depth = config.get("hole_depth", 8.0)
	narrow_hole_chance = config.get("narrow_hole_chance", 0.4)
	random_hole_min_radius = config.get("random_hole_min_radius", 6.0)
	random_hole_max_radius = config.get("random_hole_max_radius", 10.0)
	terrain_width = config.get("terrain_width", 36.0)
	chunk_size = config.get("chunk_size", Vector2(100, 50))
	
	fog_texture = load("res://assets/textures/fog.png") as Texture2D
	if not fog_texture:
		printerr("WARNING: Failed to load fog.png for hole particles")

func precalculate_holes(chunk_index: int) -> void:
	if not hole_enabled:
		chunk_holes[chunk_index] = []
		return
	
	if chunk_index < hole_safe_chunks:
		chunk_holes[chunk_index] = []
		return
	
	var holes: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(chunk_index * 77777)
	
	var chunk_start_z := -chunk_index * chunk_size.y
	var chunk_end_z := chunk_start_z - chunk_size.y
	
	var desired_spacing := rng.randf_range(hole_min_spacing, hole_max_spacing)
	var distance_from_last := absf(chunk_start_z - last_hole_z)
	
	if distance_from_last < desired_spacing:
		chunk_holes[chunk_index] = []
		return
	
	if rng.randf() > 0.4:
		chunk_holes[chunk_index] = []
		return
	
	var hole_z := rng.randf_range(chunk_end_z + 10, chunk_start_z - 10)
	var local_hole_z := hole_z - chunk_start_z
	
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
	
	last_hole_z = hole_z
	chunk_holes[chunk_index] = holes

func is_point_in_hole(local_x: float, local_z: float, chunk_index: int) -> bool:
	if not chunk_holes.has(chunk_index):
		return false
	
	var holes: Array = chunk_holes[chunk_index]
	var half_terrain := terrain_width / 2.0 - 1.0
	
	for hole in holes:
		if hole["type"] == "narrow":
			var hole_z: float = hole["local_z"]
			var half_width: float = hole["width"] / 2.0 + narrow_hole_irregularity + 1.0
			if absf(local_x) < half_terrain:
				if local_z > hole_z - half_width and local_z < hole_z + half_width:
					return true
		else:
			var hole_x: float = hole["x"]
			var hole_z: float = hole["local_z"]
			var radius: float = hole["radius"] + 1.0
			var dist := sqrt((local_x - hole_x) ** 2 + (local_z - hole_z) ** 2)
			if dist < radius:
				return true
	
	return false

## Check if a point in world coordinates is inside a hole
func is_point_in_hole_world(world_x: float, world_z: float) -> bool:
	# Convert world_z to chunk_index and local_z
	var chunk_index := int(floorf(-world_z / chunk_size.y))
	var local_z := world_z + chunk_index * chunk_size.y
	
	# Check the current chunk and adjacent chunks (in case point is near boundary)
	for ci in [chunk_index - 1, chunk_index, chunk_index + 1]:
		if is_point_in_hole(world_x, local_z + (chunk_index - ci) * chunk_size.y, ci):
			return true
	return false

func get_distance_to_nearest_hole(local_x: float, local_z: float, chunk_index: int) -> float:
	if not chunk_holes.has(chunk_index):
		return INF
	
	var holes: Array = chunk_holes[chunk_index]
	var half_terrain := terrain_width / 2.0 - 1.0
	var min_dist := INF
	
	for hole in holes:
		if hole["type"] == "narrow":
			var hole_z: float = hole["local_z"]
			var half_width: float = hole["width"] / 2.0 + narrow_hole_irregularity
			if absf(local_x) < half_terrain:
				var z_dist := absf(local_z - hole_z) - half_width
				if z_dist < min_dist:
					min_dist = maxf(0.0, z_dist)
		else:
			var hole_x: float = hole["x"]
			var hole_z: float = hole["local_z"]
			var radius: float = hole["radius"]
			var dist := sqrt((local_x - hole_x) ** 2 + (local_z - hole_z) ** 2) - radius
			if dist < min_dist:
				min_dist = maxf(0.0, dist)
	
	return min_dist

func set_floor_y(chunk_index: int, floor_y: float, center_z: float) -> void:
	if chunk_holes.has(chunk_index) and not chunk_holes[chunk_index].is_empty():
		for hole in chunk_holes[chunk_index]:
			hole["floor_y"] = floor_y
			hole["actual_center_z"] = center_z

func spawn_hole_effects(chunk: Node3D, chunk_index: int, get_height_func: Callable) -> void:
	if not hole_enabled:
		return
	
	if not chunk_holes.has(chunk_index):
		return
	
	var holes: Array = chunk_holes[chunk_index]
	if holes.is_empty():
		return
	
	for hole in holes:
		var local_z: float = hole["local_z"]
		var terrain_y: float = get_height_func.call(0.0, local_z, chunk_index)
		var floor_y: float = terrain_y - hole_depth
		
		var hole_container := Node3D.new()
		hole_container.name = "HoleEffects"
		chunk.add_child(hole_container)
		
		if hole["type"] == "narrow":
			# Death zone at bottom of hole - thin collider just at the floor
			var collider_width := narrow_hole_width + narrow_hole_irregularity * 2 + 4.0
			_create_death_collider(hole_container, 
				Vector3(0, floor_y + 1.0, local_z),
				Vector3(terrain_width + 4, 2.0, collider_width))
			
			_create_hole_particles(hole_container,
				Vector3(0, floor_y + 2.5, local_z),
				Vector3(terrain_width - 4, 2, narrow_hole_width + 2))
		else:
			var hole_x: float = hole["x"]
			var radius: float = hole["radius"]
			
			terrain_y = get_height_func.call(hole_x, local_z, chunk_index)
			floor_y = terrain_y - hole_depth
			
			# Death zone at bottom of hole - thin collider just at the floor
			var collider_size := (radius + 2.0) * 2.2
			_create_death_collider(hole_container,
				Vector3(hole_x, floor_y + 1.0, local_z),
				Vector3(collider_size, 2.0, collider_size))
			
			_create_hole_particles(hole_container,
				Vector3(hole_x, floor_y + 2.5, local_z),
				Vector3(radius * 1.8, 2, radius * 1.8))

func _create_death_collider(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var death_area := Area3D.new()
	death_area.name = "DeathZone"
	death_area.collision_layer = 0
	death_area.collision_mask = 2
	death_area.monitoring = true
	death_area.position = pos
	
	var col_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col_shape.shape = box
	death_area.add_child(col_shape)
	
	death_area.body_entered.connect(_on_death_zone_body_entered)
	parent.add_child(death_area)

func _on_death_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("die"):
		body.die()

func _create_hole_particles(parent: Node3D, pos: Vector3, emission_box: Vector3) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "HoleFog"
	particles.position = pos
	particles.amount = 40
	particles.lifetime = 5.0
	particles.speed_scale = 0.5
	particles.visibility_aabb = AABB(Vector3(-30, -20, -30), Vector3(60, 40, 60))
	particles.emitting = true
	
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 45.0
	mat.initial_velocity_min = 0.3
	mat.initial_velocity_max = 1.0
	mat.gravity = Vector3(0, 0.12, 0)
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = emission_box / 2.0
	mat.scale_min = 8.4  # 20% larger (was 7.0)
	mat.scale_max = 16.8  # 20% larger (was 14.0)
	
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.2, 0.2, 0.0))
	gradient.add_point(0.08, Color(1.0, 0.15, 0.1, 0.6))
	gradient.add_point(0.25, Color(0.95, 0.12, 0.08, 0.55))
	gradient.add_point(0.5, Color(0.85, 0.08, 0.04, 0.4))
	gradient.add_point(0.75, Color(0.6, 0.04, 0.02, 0.2))
	gradient.add_point(0.9, Color(0.4, 0.02, 0.01, 0.08))
	gradient.set_color(1, Color(0.2, 0.0, 0.0, 0.0))
	
	var gradient_tex := GradientTexture1D.new()
	gradient_tex.gradient = gradient
	mat.color_ramp = gradient_tex
	
	particles.process_material = mat
	
	var quad := QuadMesh.new()
	quad.size = Vector2(8, 8)
	
	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	if fog_texture:
		draw_mat.albedo_texture = fog_texture
	draw_mat.albedo_color = Color(1.0, 0.3, 0.2)
	
	quad.material = draw_mat
	particles.draw_pass_1 = quad
	
	parent.add_child(particles)

func cleanup_chunk(chunk_index: int) -> void:
	chunk_holes.erase(chunk_index)

func get_holes_for_chunk(chunk_index: int) -> Array:
	if chunk_holes.has(chunk_index):
		return chunk_holes[chunk_index]
	return []

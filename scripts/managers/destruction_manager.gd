extends Node
## Universal destruction manager for shattering objects into debris
## Slices the original mesh into fragments that fly apart

## Configuration for shatter effect
const FRAGMENT_COUNT_MIN: int = 5
const FRAGMENT_COUNT_MAX: int = 8
const DEBRIS_VELOCITY_MIN: float = 8.0
const DEBRIS_VELOCITY_MAX: float = 15.0
const DEBRIS_UP_VELOCITY_MIN: float = 1.0
const DEBRIS_UP_VELOCITY_MAX: float = 4.0
const DEBRIS_ROTATION_SPEED: float = 12.0
const DEBRIS_LIFETIME: float = 1.8
const DEBRIS_FADE_START: float = 0.6

## Pre-cached tools to avoid first-frame stutter
var _mdt_cache: MeshDataTool = null
var _st_cache: SurfaceTool = null
var _warmed_up: bool = false

## Cached color palette texture and base material (loaded once, used for all fragments)
var _cached_texture: Texture2D = null
var _cached_base_material: StandardMaterial3D = null


func _ready() -> void:
	# Load color palette texture once at startup
	_cached_texture = load("res://assets/textures/color-palette.png") as Texture2D
	
	# Create base material template with cached texture
	_cached_base_material = StandardMaterial3D.new()
	_cached_base_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_cached_base_material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Double-sided
	if _cached_texture:
		_cached_base_material.albedo_texture = _cached_texture
		_cached_base_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	else:
		_cached_base_material.albedo_color = Color(0.6, 0.5, 0.4)
	
	# Pre-warm the system to avoid first-destruction freeze
	call_deferred("_warmup")


## Pre-initialize tools and run a dummy mesh operation to JIT compile everything
func _warmup() -> void:
	if _warmed_up:
		return
	
	# Pre-create tools
	_mdt_cache = MeshDataTool.new()
	_st_cache = SurfaceTool.new()
	
	# Create a simple test mesh and process it to warm up the JIT
	var test_mesh := BoxMesh.new()
	test_mesh.size = Vector3(1, 1, 1)
	
	# Convert to ArrayMesh for MeshDataTool compatibility
	var st := SurfaceTool.new()
	st.create_from(test_mesh, 0)
	var array_mesh := st.commit()
	
	# Run through the mesh processing pipeline
	var mdt := MeshDataTool.new()
	if mdt.create_from_surface(array_mesh, 0) == OK:
		var _vertex_count := mdt.get_vertex_count()
		var _face_count := mdt.get_face_count()
		# Touch some data to ensure everything is loaded
		if _face_count > 0:
			var _v := mdt.get_vertex(mdt.get_face_vertex(0, 0))
			var _n := mdt.get_vertex_normal(mdt.get_face_vertex(0, 0))
	
	# Build a test fragment
	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	st2.set_normal(Vector3.UP)
	st2.set_uv(Vector2.ZERO)
	st2.add_vertex(Vector3.ZERO)
	st2.add_vertex(Vector3.RIGHT)
	st2.add_vertex(Vector3.FORWARD)
	st2.generate_normals()
	var _test_frag := st2.commit()
	
	# Warm up material duplication (JIT compile duplicate() method)
	if _cached_base_material:
		var _test_mat := _cached_base_material.duplicate() as StandardMaterial3D
		_test_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	_warmed_up = true


## Shatter an object into mesh fragments
func shatter(target: Node3D, impact_velocity: Vector3 = Vector3.ZERO, remove_original: bool = true, fly_upward: bool = false) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree():
		return
	
	var scene_root := get_tree().current_scene
	if not scene_root:
		return
	
	# Get world transform before destruction
	var spawn_position := target.global_position
	var original_transform := target.global_transform
	
	# Find mesh instance in target
	var source_mesh_instance := _find_mesh_instance(target)
	if not source_mesh_instance:
		push_warning("DestructionManager: No MeshInstance3D found in '%s'" % target.name)
		if remove_original:
			target.queue_free()
		return
	
	# Get the mesh and material
	var source_mesh := source_mesh_instance.mesh
	if not source_mesh:
		if remove_original:
			target.queue_free()
		return
	
	# Get material from the mesh instance
	var source_material: Material = null
	if source_mesh_instance.get_surface_override_material_count() > 0:
		source_material = source_mesh_instance.get_surface_override_material(0)
	if not source_material and source_mesh.get_surface_count() > 0:
		source_material = source_mesh.surface_get_material(0)
	
	# Calculate mesh instance world transform
	var mesh_world_transform := source_mesh_instance.global_transform
	
	# Generate fragments from the mesh
	var fragment_count := randi_range(FRAGMENT_COUNT_MIN, FRAGMENT_COUNT_MAX)
	var fragments := _create_mesh_fragments(source_mesh, fragment_count)
	
	# Spawn each fragment
	for i in range(fragments.size()):
		var frag_mesh: ArrayMesh = fragments[i]
		if frag_mesh:
			_spawn_fragment(scene_root, frag_mesh, source_material, mesh_world_transform, impact_velocity, i, fragments.size(), fly_upward)
	
	# Remove original
	if remove_original:
		target.queue_free()


## Find first MeshInstance3D in a node tree
func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var result := _find_mesh_instance(child)
		if result:
			return result
	return null


## Create mesh fragments by slicing the original mesh into pieces
func _create_mesh_fragments(source_mesh: Mesh, fragment_count: int) -> Array[ArrayMesh]:
	var fragments: Array[ArrayMesh] = []
	
	# Get mesh data using MeshDataTool
	var mdt := MeshDataTool.new()
	
	# Try to get data from first surface
	if source_mesh.get_surface_count() == 0:
		return fragments
	
	var err := mdt.create_from_surface(source_mesh, 0)
	if err != OK:
		# Fallback: create simple box fragments
		return _create_fallback_fragments(source_mesh, fragment_count)
	
	var vertex_count := mdt.get_vertex_count()
	var face_count := mdt.get_face_count()
	
	if face_count < fragment_count:
		fragment_count = maxi(1, face_count)
	
	# Calculate mesh bounds for slicing planes
	var bounds_min := Vector3.INF
	var bounds_max := -Vector3.INF
	for i in range(vertex_count):
		var v := mdt.get_vertex(i)
		bounds_min = bounds_min.min(v)
		bounds_max = bounds_max.max(v)
	
	var bounds_center := (bounds_min + bounds_max) * 0.5
	var bounds_size := bounds_max - bounds_min
	
	# Assign each face to a fragment based on its position
	var face_assignments: Array[int] = []
	face_assignments.resize(face_count)
	
	# Create random cluster centers
	var cluster_centers: Array[Vector3] = []
	for i in range(fragment_count):
		cluster_centers.append(Vector3(
			randf_range(bounds_min.x, bounds_max.x),
			randf_range(bounds_min.y, bounds_max.y),
			randf_range(bounds_min.z, bounds_max.z)
		))
	
	# Assign faces to nearest cluster (Voronoi-like partitioning)
	for face_idx in range(face_count):
		# Get face center
		var v0 := mdt.get_vertex(mdt.get_face_vertex(face_idx, 0))
		var v1 := mdt.get_vertex(mdt.get_face_vertex(face_idx, 1))
		var v2 := mdt.get_vertex(mdt.get_face_vertex(face_idx, 2))
		var face_center := (v0 + v1 + v2) / 3.0
		
		# Find nearest cluster
		var nearest_cluster := 0
		var nearest_dist := INF
		for cluster_idx in range(fragment_count):
			var dist := face_center.distance_squared_to(cluster_centers[cluster_idx])
			if dist < nearest_dist:
				nearest_dist = dist
				nearest_cluster = cluster_idx
		
		face_assignments[face_idx] = nearest_cluster
	
	# Build fragment meshes
	for cluster_idx in range(fragment_count):
		var frag_mesh := _build_fragment_mesh(mdt, face_assignments, cluster_idx, bounds_center)
		if frag_mesh:
			fragments.append(frag_mesh)
	
	return fragments


## Build a single fragment mesh from assigned faces
func _build_fragment_mesh(mdt: MeshDataTool, face_assignments: Array[int], cluster_idx: int, bounds_center: Vector3) -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var has_faces := false
	var frag_center := Vector3.ZERO
	var frag_vertex_count := 0
	
	# First pass: calculate fragment center
	for face_idx in range(face_assignments.size()):
		if face_assignments[face_idx] != cluster_idx:
			continue
		
		for i in range(3):
			var vert_idx := mdt.get_face_vertex(face_idx, i)
			frag_center += mdt.get_vertex(vert_idx)
			frag_vertex_count += 1
	
	if frag_vertex_count == 0:
		return null
	
	frag_center /= float(frag_vertex_count)
	
	# Second pass: build mesh with vertices relative to fragment center
	for face_idx in range(face_assignments.size()):
		if face_assignments[face_idx] != cluster_idx:
			continue
		
		has_faces = true
		
		for i in range(3):
			var vert_idx := mdt.get_face_vertex(face_idx, i)
			var vertex := mdt.get_vertex(vert_idx) - frag_center  # Center the fragment
			var normal := mdt.get_vertex_normal(vert_idx)
			var uv := mdt.get_vertex_uv(vert_idx)
			
			surface_tool.set_normal(normal)
			surface_tool.set_uv(uv)
			surface_tool.add_vertex(vertex)
	
	if not has_faces:
		return null
	
	surface_tool.generate_normals()
	var mesh := surface_tool.commit()
	
	# Store fragment center as metadata for positioning
	mesh.set_meta("fragment_center", frag_center)
	
	return mesh


## Fallback: create simple box fragments when mesh processing fails
func _create_fallback_fragments(source_mesh: Mesh, fragment_count: int) -> Array[ArrayMesh]:
	var fragments: Array[ArrayMesh] = []
	
	# Get approximate size from AABB
	var aabb := source_mesh.get_aabb()
	var size := aabb.size
	var frag_size := size / 2.0
	
	for i in range(fragment_count):
		var box := BoxMesh.new()
		box.size = Vector3(
			frag_size.x * randf_range(0.3, 0.8),
			frag_size.y * randf_range(0.3, 0.8),
			frag_size.z * randf_range(0.3, 0.8)
		)
		
		# Convert BoxMesh to ArrayMesh
		var surface_tool := SurfaceTool.new()
		surface_tool.create_from(box, 0)
		var arr_mesh := surface_tool.commit()
		
		# Random offset within bounds
		var offset := Vector3(
			randf_range(-size.x * 0.3, size.x * 0.3),
			randf_range(-size.y * 0.3, size.y * 0.3),
			randf_range(-size.z * 0.3, size.z * 0.3)
		)
		arr_mesh.set_meta("fragment_center", aabb.get_center() + offset)
		
		fragments.append(arr_mesh)
	
	return fragments


## Spawn a fragment with physics animation
func _spawn_fragment(
	scene_root: Node,
	frag_mesh: ArrayMesh,
	material: Material,
	world_transform: Transform3D,
	impact_velocity: Vector3,
	index: int,
	total_count: int,
	fly_upward: bool = false
) -> void:
	var debris := MeshInstance3D.new()
	debris.name = "Fragment_%d" % index
	debris.mesh = frag_mesh
	
	# Apply material - use cached base material (much faster than duplicating each time)
	var fade_material: StandardMaterial3D = _cached_base_material.duplicate() as StandardMaterial3D
	fade_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debris.material_override = fade_material
	
	# Extract scale from world transform to apply to debris
	# This handles non-uniform scaling on objects like barrels
	var mesh_scale := world_transform.basis.get_scale()
	
	# Clamp scale to prevent extreme values (safety check for stretched fragments)
	var max_scale := 3.0
	var min_scale := 0.1
	mesh_scale.x = clampf(mesh_scale.x, min_scale, max_scale)
	mesh_scale.y = clampf(mesh_scale.y, min_scale, max_scale)
	mesh_scale.z = clampf(mesh_scale.z, min_scale, max_scale)
	
	# Position fragment - calculate position before adding to scene
	var frag_center: Vector3 = frag_mesh.get_meta("fragment_center", Vector3.ZERO)
	# Apply scale to fragment center for correct world position
	var scaled_center := frag_center * mesh_scale
	var world_pos := world_transform.origin + world_transform.basis.orthonormalized() * scaled_center
	debris.position = world_pos
	debris.rotation = Vector3(randf() * 0.3, randf() * TAU, randf() * 0.3)
	
	# Apply the original mesh's scale to the debris fragment
	debris.scale = mesh_scale
	
	# Calculate velocity (outward from center + impact direction) - mostly horizontal
	var outward_dir := frag_center
	outward_dir.y = 0  # Force horizontal
	outward_dir = outward_dir.normalized()
	if outward_dir.length() < 0.1:
		# Random horizontal direction
		var rand_angle := randf() * TAU
		outward_dir = Vector3(cos(rand_angle), 0, sin(rand_angle))
	
	# Add random spread to outward direction
	var spread_angle := randf_range(-0.8, 0.8)
	outward_dir = outward_dir.rotated(Vector3.UP, spread_angle)
	
	var velocity_dir: Vector3
	if impact_velocity.length() > 0.1:
		var impact_horizontal := impact_velocity
		impact_horizontal.y = 0
		impact_horizontal = impact_horizontal.normalized()
		# Blend impact direction with outward spread
		velocity_dir = (impact_horizontal * 0.6 + outward_dir * 0.8).normalized()
	else:
		velocity_dir = outward_dir
	
	var velocity_mag := randf_range(DEBRIS_VELOCITY_MIN, DEBRIS_VELOCITY_MAX)
	var up_velocity: float
	if fly_upward:
		# For upward shatter (player death), debris flies up strongly
		up_velocity = randf_range(12.0, 20.0)
	else:
		up_velocity = randf_range(DEBRIS_UP_VELOCITY_MIN, DEBRIS_UP_VELOCITY_MAX)
	var velocity := velocity_dir * velocity_mag + Vector3.UP * up_velocity
	
	var rotation_velocity := Vector3(
		randf_range(-DEBRIS_ROTATION_SPEED, DEBRIS_ROTATION_SPEED),
		randf_range(-DEBRIS_ROTATION_SPEED, DEBRIS_ROTATION_SPEED),
		randf_range(-DEBRIS_ROTATION_SPEED, DEBRIS_ROTATION_SPEED)
	)
	
	scene_root.add_child(debris)
	_animate_fragment(debris, fade_material, velocity, rotation_velocity, fly_upward)


## Animate fragment flying and fading
func _animate_fragment(debris: MeshInstance3D, material: StandardMaterial3D, velocity: Vector3, rotation_velocity: Vector3, fly_upward: bool = false) -> void:
	var elapsed := 0.0
	# For upward shatter, use lower gravity so debris floats up longer
	var gravity := 6.0 if fly_upward else 18.0
	var current_velocity := velocity
	var original_color := material.albedo_color
	
	while elapsed < DEBRIS_LIFETIME and is_instance_valid(debris) and debris.is_inside_tree():
		var delta := get_process_delta_time()
		elapsed += delta
		
		current_velocity.y -= gravity * delta
		debris.position += current_velocity * delta
		debris.rotation += rotation_velocity * delta
		
		# Air resistance
		current_velocity.x *= 0.995
		current_velocity.z *= 0.995
		
		# Fade out
		if elapsed > DEBRIS_LIFETIME * DEBRIS_FADE_START:
			var fade_progress := (elapsed - DEBRIS_LIFETIME * DEBRIS_FADE_START) / (DEBRIS_LIFETIME * (1.0 - DEBRIS_FADE_START))
			material.albedo_color.a = (1.0 - fade_progress) * original_color.a
		
		# Safe await - check scene tree exists before awaiting
		var tree := get_tree()
		if tree == null:
			break
		await tree.process_frame
	
	if is_instance_valid(debris):
		debris.queue_free()


## Extract color from material
func _extract_color_from_material(material: Material) -> Color:
	if material is StandardMaterial3D:
		return (material as StandardMaterial3D).albedo_color
	return Color(0.6, 0.5, 0.4)


## ========== Fling Animation ==========
## Universal fling animation for NPCs and objects when hit by player

## Fling an object forward in the killer's direction with tumbling rotation
## @param target: The Node3D to fling and remove
## @param killer: The player/killer node (used to determine direction)
## @param model_node: Optional child node to rotate (if null, rotates target itself)
## @param speed_min: Minimum launch speed
## @param speed_max: Maximum launch speed
## @param rotation_scale: Multiplier for rotation speed (1.0 = normal, 0.5 = slower for big objects)
func fling_object(
	target: Node3D,
	killer: Node = null,
	model_node: Node3D = null,
	speed_min: float = 25.0,
	speed_max: float = 38.0,
	rotation_scale: float = 1.0
) -> void:
	if not is_instance_valid(target):
		return
	
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	# Determine fly direction - forward in killer's movement direction
	var fly_direction := Vector3(0, 0, -1)  # Default forward
	if killer and killer is Node3D:
		var killer_vel := Vector3.ZERO
		if killer.has_method("get_linear_velocity"):
			killer_vel = killer.get_linear_velocity()
		elif "linear_velocity" in killer:
			killer_vel = killer.linear_velocity
		
		if killer_vel.length() > 1.0:
			fly_direction = killer_vel.normalized()
			fly_direction.y = 0
		else:
			fly_direction = (target.global_position - killer.global_position).normalized()
			fly_direction.y = 0
	
	if fly_direction.length() < 0.1:
		fly_direction = Vector3(0, 0, -1)
	
	fly_direction = fly_direction.normalized()
	
	# Add random horizontal spread (up to ~40 degrees)
	var spread_angle := rng.randf_range(-0.7, 0.7)
	fly_direction = fly_direction.rotated(Vector3.UP, spread_angle)
	
	# Add upward arc
	fly_direction.y = rng.randf_range(0.4, 0.7)
	fly_direction = fly_direction.normalized()
	
	# Tumbling rotation (scaled for object size)
	var rotation_velocity := Vector3(
		rng.randf_range(-15.0, 15.0) * rotation_scale,
		rng.randf_range(-8.0, 8.0) * rotation_scale,
		rng.randf_range(-15.0, 15.0) * rotation_scale
	)
	
	# Launch velocity
	var launch_speed := rng.randf_range(speed_min, speed_max)
	var velocity := fly_direction * launch_speed
	var gravity := 22.0
	var lifetime := 0.9
	var elapsed := 0.0
	
	# Rotate model or target
	var rotate_target: Node3D = model_node if model_node else target
	
	while elapsed < lifetime and is_instance_valid(target):
		var delta := target.get_process_delta_time()
		elapsed += delta
		
		# Parabolic arc
		velocity.y -= gravity * delta
		target.global_position += velocity * delta
		
		# Tumbling
		if is_instance_valid(rotate_target):
			rotate_target.rotation += rotation_velocity * delta
		
		# Air resistance
		velocity.x *= 0.99
		velocity.z *= 0.99
		
		var tree := target.get_tree()
		if tree == null:
			break
		await tree.process_frame
	
	if is_instance_valid(target):
		target.queue_free()

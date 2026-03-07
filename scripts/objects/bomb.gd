extends Node3D
class_name PlaneBomb
## Bomb dropped by enemy plane - falls with gravity, explodes on ground impact
## Creates red shock wave that damages player only

const ShockWaveManager := preload("res://scripts/effects/shock_wave_manager.gd")

const GRAVITY: float = 15.0
const BOMB_RADIUS: float = 0.3
const BOMB_COLOR := Color(0.3, 0.3, 0.3)  # Dark gray
const TRAIL_COLOR := Color(0.8, 0.2, 0.1, 0.6)  # Red-orange trail
const TRAIL_LENGTH: int = 20
const TRAIL_WIDTH: float = 0.12

var velocity: Vector3 = Vector3.ZERO
var damage: int = 40
var shock_wave_radius: float = 9.0
var is_active := true
var ground_level: float = 0.0
var time_alive: float = 0.0

# Visual components
var bomb_mesh: MeshInstance3D
var trail_mesh_instance: MeshInstance3D
var trail_material: StandardMaterial3D
var trail_points: Array[Vector3] = []
var _surface_tool: SurfaceTool  # Reused for trail mesh building
var _trail_array_mesh: ArrayMesh  # Reused mesh to avoid allocations
var min_flight_time: float = 0.5  # Minimum time before bomb can explode (prevents mid-air issue)
const PLAYER_HIT_RADIUS: float = 1.5  # Radius for direct player hit detection

# References
var player: Node3D = null


func _ready() -> void:
	add_to_group("bombs")
	
	player = get_tree().get_first_node_in_group("player") as Node3D
	
	# Pre-allocate reusable objects
	_surface_tool = SurfaceTool.new()
	_trail_array_mesh = ArrayMesh.new()
	
	_create_bomb_mesh()
	_create_trail()


func _create_bomb_mesh() -> void:
	## Create the visual bomb mesh
	bomb_mesh = MeshInstance3D.new()
	bomb_mesh.name = "BombMesh"
	
	# Bomb shape - elongated sphere
	var sphere := SphereMesh.new()
	sphere.radius = BOMB_RADIUS
	sphere.height = BOMB_RADIUS * 2.5
	sphere.radial_segments = 12
	sphere.rings = 6
	bomb_mesh.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BOMB_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bomb_mesh.material_override = mat
	
	add_child(bomb_mesh)


func _create_trail() -> void:
	## Create smoke trail effect
	trail_mesh_instance = MeshInstance3D.new()
	trail_mesh_instance.name = "Trail"
	
	trail_material = StandardMaterial3D.new()
	trail_material.albedo_color = TRAIL_COLOR
	trail_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	trail_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	trail_material.vertex_color_use_as_albedo = true
	
	add_child(trail_mesh_instance)


func _process(delta: float) -> void:
	if not is_active:
		return
	
	time_alive += delta
	
	# Apply gravity
	velocity.y -= GRAVITY * delta
	
	# Move bomb
	global_position += velocity * delta
	
	# Rotate bomb to face velocity direction
	if velocity.length() > 0.1:
		bomb_mesh.look_at(global_position + velocity.normalized(), Vector3.UP)
		bomb_mesh.rotate_object_local(Vector3.RIGHT, PI / 2.0)  # Point nose down
	
	# Update trail
	trail_points.insert(0, global_position)
	if trail_points.size() > TRAIL_LENGTH:
		trail_points.resize(TRAIL_LENGTH)
	_update_trail_mesh()
	
	# Check direct player collision (bomb hits player in air)
	if player and is_instance_valid(player):
		var dist_to_player := global_position.distance_to(player.global_position)
		if dist_to_player <= PLAYER_HIT_RADIUS:
			_on_player_direct_hit()
			return
	
	# Check ground collision using raycast (most accurate)
	if time_alive >= min_flight_time:
		var space_state := get_world_3d().direct_space_state
		if space_state:
			# Raycast from bomb position downward
			var ray_query := PhysicsRayQueryParameters3D.create(
				global_position + Vector3(0, BOMB_RADIUS, 0),  # Start from top of bomb
				global_position + Vector3(0, -BOMB_RADIUS * 2, 0)  # Check below bomb
			)
			ray_query.collision_mask = 1  # Terrain layer
			var result := space_state.intersect_ray(ray_query)
			if not result.is_empty():
				# Hit terrain - explode at hit point
				ground_level = result.position.y
				_on_ground_impact()
				return


func _update_trail_mesh() -> void:
	## Update the visual trail behind the bomb
	if trail_points.size() < 2:
		return
	
	_surface_tool.clear()
	_surface_tool.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	
	var cam_pos := camera.global_position
	
	for i in range(trail_points.size()):
		var point := trail_points[i]
		var alpha: float = 1.0 - (float(i) / float(trail_points.size()))
		var width: float = TRAIL_WIDTH * alpha
		
		# Calculate perpendicular direction for ribbon
		var to_cam := (cam_pos - point).normalized()
		var forward: Vector3
		if i < trail_points.size() - 1:
			forward = (trail_points[i] - trail_points[i + 1]).normalized()
		else:
			forward = velocity.normalized()
		
		var right := forward.cross(to_cam).normalized() * width
		
		# Add vertices with fading alpha
		var color := Color(TRAIL_COLOR.r, TRAIL_COLOR.g, TRAIL_COLOR.b, alpha * TRAIL_COLOR.a)
		
		_surface_tool.set_color(color)
		_surface_tool.add_vertex(point + right - global_position)
		_surface_tool.set_color(color)
		_surface_tool.add_vertex(point - right - global_position)
	
	# Reuse ArrayMesh instead of creating new one
	_trail_array_mesh.clear_surfaces()
	_surface_tool.commit(_trail_array_mesh)
	trail_mesh_instance.mesh = _trail_array_mesh
	trail_mesh_instance.material_override = trail_material


func _on_player_direct_hit() -> void:
	## Bomb hit player directly in the air
	is_active = false
	
	# Deal damage to player directly
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("take_damage"):
		gm.take_damage(damage)
	
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_hurt_sound"):
		audio.play_hurt_sound()
	if audio and audio.has_method("vibrate"):
		audio.vibrate(100)
	
	# Spawn smaller explosion effect at hit position (visual only, damage already dealt)
	ShockWaveManager.spawn_shock_wave(
		global_position,
		ShockWaveManager.Source.ENEMY,
		3.0  # Smaller visual effect for direct hit
	)
	
	# Cleanup
	queue_free()


func _on_ground_impact() -> void:
	## Bomb hit the ground - create red shock wave
	is_active = false
	
	# Spawn shock wave at ground level (damages player if in radius)
	var impact_pos := Vector3(global_position.x, ground_level, global_position.z)
	ShockWaveManager.spawn_shock_wave(
		impact_pos,
		ShockWaveManager.Source.ENEMY,
		shock_wave_radius
	)
	
	# Cleanup
	queue_free()


## Initialize bomb with damage and radius
func initialize(bomb_damage: int, radius: float) -> void:
	damage = bomb_damage
	shock_wave_radius = radius
	# Small forward velocity (in direction plane was flying)
	velocity = Vector3(0, 0, -5.0)

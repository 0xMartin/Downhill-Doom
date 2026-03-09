extends Node3D
class_name CatapultProjectile
## Catapult projectile - gray ball with trail that follows ballistic trajectory
## On impact: direct damage + red shock wave that damages player

const GRAVITY: float = 12.0  # Lower gravity for flatter arc
const PROJECTILE_SPEED: float = 36.0  # Base horizontal speed (20% faster)
const TRAIL_LENGTH: int = 30
const TRAIL_SEGMENT_TIME: float = 0.02
const TRAIL_WIDTH: float = 0.15
const PROJECTILE_RADIUS: float = 0.3
const PROJECTILE_COLOR := Color(0.4, 0.4, 0.4)  # Dark gray
const TRAIL_COLOR := Color(0.6, 0.1, 0.1, 0.8)  # Red trail
const IMPACT_SHOCK_WAVE_RADIUS: float = 10.0  # Shock wave radius (+30%)

var velocity: Vector3 = Vector3.ZERO
var damage: int = 20
var shooter: Node3D = null
var is_active := true
var spawn_immunity_time: float = 0.5  # Brief immunity after spawn
var time_alive: float = 0.0
var ground_level: float = 0.0  # Ground level at catapult position

# Trail
var trail_points: Array[Vector3] = []
var trail_mesh_instance: MeshInstance3D
var trail_material: StandardMaterial3D

# Ball
var ball_mesh: MeshInstance3D


func _ready() -> void:
	add_to_group("catapult_projectiles")
	_create_ball()
	_create_trail()


func _create_ball() -> void:
	ball_mesh = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = PROJECTILE_RADIUS
	sphere.height = PROJECTILE_RADIUS * 2
	sphere.radial_segments = 16
	sphere.rings = 8
	ball_mesh.mesh = sphere
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PROJECTILE_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball_mesh.material_override = mat
	add_child(ball_mesh)


func _create_trail() -> void:
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
	
	# Move
	var old_pos := global_position
	global_position += velocity * delta
	
	# Add trail point
	trail_points.insert(0, global_position)
	if trail_points.size() > TRAIL_LENGTH:
		trail_points.resize(TRAIL_LENGTH)
	
	# Update trail mesh
	_update_trail_mesh()
	
	# Check player collision in mid-air (always active after immunity)
	if time_alive > spawn_immunity_time:
		var player := get_tree().get_first_node_in_group("player") as Node3D
		if player:
			var dist := global_position.distance_to(player.global_position)
			if dist < PROJECTILE_RADIUS + 1.5:  # Direct hit in air
				_on_direct_player_hit()
				return
	
	# Check ground collision using raycast to detect actual terrain
	if time_alive > spawn_immunity_time:
		var terrain_height := _get_terrain_height()
		if global_position.y <= terrain_height + 0.5:
			_on_ground_impact()


func _update_trail_mesh() -> void:
	if trail_points.size() < 2:
		return
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	
	# Get camera for billboard effect
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
		
		st.set_color(color)
		st.add_vertex(point + right - global_position)  # Local space
		st.set_color(color)
		st.add_vertex(point - right - global_position)
	
	trail_mesh_instance.mesh = st.commit()
	trail_mesh_instance.material_override = trail_material


func _on_direct_player_hit() -> void:
	## Called when projectile directly hits player in mid-air
	## Deals direct damage, no shock wave
	is_active = false
	
	# Deal direct damage to player
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("take_damage"):
		gm.take_damage(damage)
	
	var audio: Node = get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_hurt_sound"):
		audio.play_hurt_sound()
	
	# Cleanup
	queue_free()


func _on_ground_impact() -> void:
	## Called when projectile hits the ground/terrain
	## Spawns red shock wave that damages player if in radius
	is_active = false
	
	# Always spawn red shock wave on ground impact
	ShockWaveManager.spawn_shock_wave(global_position, ShockWaveManager.Source.ENEMY, IMPACT_SHOCK_WAVE_RADIUS)
	
	# Cleanup
	queue_free()


## Initialize projectile with launch parameters
func launch(start_pos: Vector3, target_pos: Vector3, projectile_damage: int, source: Node3D = null, catapult_ground_y: float = 0.0) -> void:
	global_position = start_pos
	damage = projectile_damage
	shooter = source
	ground_level = catapult_ground_y  # Use catapult's ground level as reference
	
	# Calculate velocity to hit target with ballistic trajectory
	velocity = _calculate_launch_velocity(start_pos, target_pos)
	
	# Initialize trail with starting position
	trail_points.append(start_pos)


func _get_terrain_height() -> float:
	## Raycast down to find actual terrain height at current position
	var space_state := get_world_3d().direct_space_state
	if not space_state:
		return ground_level  # Fallback
	
	var ray_origin := global_position + Vector3(0, 20, 0)  # Start well above
	var ray_end := global_position + Vector3(0, -100, 0)  # End well below
	
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1  # Terrain layer
	
	var result := space_state.intersect_ray(query)
	if result:
		return result.position.y
	
	return ground_level  # Fallback if no hit


func _calculate_launch_velocity(start: Vector3, target: Vector3) -> Vector3:
	## Calculate velocity to hit target with a simple low arc
	## Uses fixed horizontal speed for predictable timing
	var displacement := target - start
	var horizontal_dist := Vector2(displacement.x, displacement.z).length()
	var vertical_dist := displacement.y
	
	if horizontal_dist < 0.1:
		return Vector3(0, 5, 0)  # Basically straight up if too close
	
	# Flight time based on fixed horizontal speed
	var flight_time := horizontal_dist / PROJECTILE_SPEED
	
	# Calculate vertical velocity needed to hit target at that time
	# y = y0 + vy*t - 0.5*g*t^2
	# vertical_dist = vy*t - 0.5*g*t^2
	# vy = (vertical_dist + 0.5*g*t^2) / t
	var vy := (vertical_dist + 0.5 * GRAVITY * flight_time * flight_time) / flight_time
	
	# Calculate horizontal velocity
	var horizontal_dir := Vector2(displacement.x, displacement.z).normalized()
	var vel := Vector3(
		horizontal_dir.x * PROJECTILE_SPEED,
		vy,
		horizontal_dir.y * PROJECTILE_SPEED
	)
	
	return vel

extends Node
class_name ShockWaveManager
## Manages shock wave effects - expanding sphere that damages objects in radius
##
## Usage:
## - Player landing: ShockWaveManager.spawn_shock_wave(position, Source.PLAYER)
## - Enemy attack (FUTURE): ShockWaveManager.spawn_shock_wave(position, Source.ENEMY)
##
## The shock wave:
## - Visually: Gray transparent sphere that expands and fades
## - Functionally: Damages/destroys objects within radius based on source
##   - PLAYER source: Destroys trees, NPCs, buildings in radius
##   - ENEMY source (FUTURE): Damages player if in radius

## Source of the shock wave - determines what gets affected
enum Source {
	PLAYER,  # Player-created: damages/destroys destructible objects
	ENEMY,   # Enemy-created (FUTURE): damages player
}

## Configuration
const SHOCK_WAVE_RADIUS: float = 8.0  # Maximum radius in meters
const EXPANSION_DURATION: float = 0.4  # Time to reach max radius
const SHOCK_WAVE_DAMAGE: int = 15  # Damage dealt (same as spike)
const SHOCK_WAVE_COLOR_PLAYER := Color(0.7, 0.7, 0.7, 0.4)  # Gray, semi-transparent
const SHOCK_WAVE_COLOR_ENEMY := Color(0.9, 0.2, 0.2, 0.5)  # Red, semi-transparent


## Spawn a shock wave at the given position
## @param position: World position to spawn at
## @param source: Who created the shock wave (affects what gets damaged)
## @param radius_override: Optional custom radius (default: SHOCK_WAVE_RADIUS)
static func spawn_shock_wave(position: Vector3, source: Source, radius_override: float = -1.0) -> void:
	var scene_root: Node = Engine.get_main_loop().current_scene
	if not scene_root:
		return
	
	var radius := radius_override if radius_override > 0 else SHOCK_WAVE_RADIUS
	
	# Play sound
	var audio: Node = scene_root.get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_shock_wave_sound"):
		audio.play_shock_wave_sound()
	
	# Create the visual effect with appropriate color
	var sphere := _create_shock_wave_visual(position, source, scene_root)
	
	# Animate expansion and fade
	_animate_shock_wave(sphere, radius, scene_root)
	
	# Apply damage/destruction after a short delay (when wave reaches objects)
	_apply_shock_wave_effects(position, radius, source, scene_root)


## Create the visual sphere mesh
static func _create_shock_wave_visual(position: Vector3, source: Source, scene_root: Node) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "ShockWave"
	
	# Create sphere mesh - starts small
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = 0.1
	sphere_mesh.height = 0.2
	sphere_mesh.radial_segments = 32
	sphere_mesh.rings = 16
	mesh_instance.mesh = sphere_mesh
	
	# Choose color based on source
	var wave_color := SHOCK_WAVE_COLOR_PLAYER if source == Source.PLAYER else SHOCK_WAVE_COLOR_ENEMY
	
	# Create transparent material
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = wave_color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED  # Visible from inside too
	mesh_instance.material_override = material
	
	# Add to scene FIRST, then set position (must be in tree for global_position)
	scene_root.add_child(mesh_instance)
	mesh_instance.global_position = position
	
	return mesh_instance


## Animate the shock wave expansion and fade
static func _animate_shock_wave(sphere: MeshInstance3D, target_radius: float, scene_root: Node) -> void:
	# Calculate target scale (sphere mesh has radius 0.1, so scale = target/0.1)
	var target_scale := target_radius / 0.1
	
	# Create tween for animation
	var tween := scene_root.create_tween()
	tween.set_parallel(true)
	
	# Scale up
	tween.tween_property(sphere, "scale", Vector3.ONE * target_scale, EXPANSION_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	
	# Fade out
	var mat: StandardMaterial3D = sphere.material_override
	if mat:
		tween.tween_property(mat, "albedo_color:a", 0.0, EXPANSION_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	
	# Cleanup after animation
	tween.set_parallel(false)
	tween.tween_callback(sphere.queue_free)


## Apply damage/destruction effects to objects in radius
static func _apply_shock_wave_effects(position: Vector3, radius: float, source: Source, scene_root: Node) -> void:
	# Apply damage immediately (visual expansion is separate)
	match source:
		Source.PLAYER:
			_damage_destructibles(position, radius, scene_root)
		Source.ENEMY:
			_damage_player(position, radius, scene_root)


## Damage/destroy destructible objects (trees, NPCs, buildings) in radius
## Called when source is PLAYER
static func _damage_destructibles(position: Vector3, radius: float, scene_root: Node) -> void:
	var destroyed_count := 0
	
	# Find all destructible objects in range
	# Trees - use fall() method
	for tree in scene_root.get_tree().get_nodes_in_group("trees"):
		if _is_in_radius(tree, position, radius):
			if tree.has_method("fall"):
				# Calculate direction from shock wave center to tree
				var dir: Vector3 = ((tree as Node3D).global_position - position).normalized()
				dir.y = 0
				if dir.length() < 0.1:
					dir = Vector3(0, 0, -1)
				tree.fall(dir * 10.0)  # Fake velocity in direction away from shock
				destroyed_count += 1
	
	# Friend NPCs (chickens, rabbits) - use die() method
	for npc in scene_root.get_tree().get_nodes_in_group("friend_npcs"):
		if _is_in_radius(npc, position, radius):
			if npc.has_method("die"):
				npc.die(null)
				destroyed_count += 1
	
	# Enemy NPCs (dark pawn, dark knight, horse knight) - use die() method
	for enemy_npc in scene_root.get_tree().get_nodes_in_group("enemy_npcs"):
		if _is_in_radius(enemy_npc, position, radius):
			if enemy_npc.has_method("die"):
				enemy_npc.die(null)
				destroyed_count += 1
	
	# Buildings
	for building in scene_root.get_tree().get_nodes_in_group("buildings"):
		if _is_in_radius(building, position, radius):
			if building.has_method("destroy"):
				building.destroy(Vector3.ZERO)  # Zero velocity for shock wave destruction
				destroyed_count += 1
	
	# Screen shake if we destroyed something
	if destroyed_count > 0:
		var camera := scene_root.get_viewport().get_camera_3d()
		if camera and camera.has_method("shake"):
			camera.shake(0.3 + destroyed_count * 0.1)


## Damage the player if in radius
## Called when source is ENEMY
static func _damage_player(position: Vector3, radius: float, scene_root: Node) -> void:
	var player := scene_root.get_tree().get_first_node_in_group("player")
	if player and _is_in_radius(player, position, radius):
		var gm := scene_root.get_node_or_null("/root/GameManager")
		if gm:
			gm.take_damage(SHOCK_WAVE_DAMAGE)
		
		# Play hurt sound
		var audio := scene_root.get_node_or_null("/root/AudioManager")
		if audio and audio.has_method("play_hurt_sound"):
			audio.play_hurt_sound()


## Check if a node is within radius of position
static func _is_in_radius(node: Node, position: Vector3, radius: float) -> bool:
	if not node is Node3D:
		return false
	var node_pos: Vector3 = (node as Node3D).global_position
	var distance := position.distance_to(node_pos)
	return distance <= radius

class_name ModelRenderer
extends RefCounted
## Utility class for rendering 3D model snapshots to textures
## Useful for skin previews, player profiles, thumbnails, etc.

const DEFAULT_SIZE := Vector2i(256, 256)
const DEFAULT_CAMERA_POSITION := Vector3(0, 0.4, 2.2)
const DEFAULT_CAMERA_ROTATION := Vector3(-8, 0, 0)
const DEFAULT_MODEL_SCALE := Vector3(0.5, 0.5, 0.5)
const DEFAULT_MODEL_POSITION := Vector3(0, -0.05, 0)


## Render a model with optional texture overlay to an ImageTexture
## Returns null if rendering fails
static func render_model_snapshot(
	model_path: String,
	texture_path: String = "",
	size: Vector2i = DEFAULT_SIZE,
	model_rotation_y: float = 0.0
) -> ImageTexture:
	if not ResourceLoader.exists(model_path):
		push_warning("ModelRenderer: Model not found: " + model_path)
		return null
	
	# Create viewport for rendering
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true
	viewport.disable_3d = false
	
	# Add environment for proper lighting in own_world_3d
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	
	# Setup camera
	var camera := Camera3D.new()
	camera.fov = 45
	camera.current = true
	camera.position = DEFAULT_CAMERA_POSITION
	camera.rotation_degrees = DEFAULT_CAMERA_ROTATION
	viewport.add_child(camera)
	
	# Setup lighting
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 45, 0)
	light.light_energy = 2.0
	light.light_color = Color.WHITE
	viewport.add_child(light)
	
	# Add fill light from opposite side
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-30, -135, 0)
	fill_light.light_energy = 0.5
	fill_light.light_color = Color.WHITE
	viewport.add_child(fill_light)
	
	# Load model
	var model_scene: PackedScene = load(model_path)
	if not model_scene:
		push_warning("ModelRenderer: Failed to load model: " + model_path)
		viewport.queue_free()
		return null
	
	var model: Node3D = model_scene.instantiate()
	model.scale = DEFAULT_MODEL_SCALE
	model.position = DEFAULT_MODEL_POSITION
	model.rotation.y = model_rotation_y
	
	# Apply texture if provided
	if texture_path and ResourceLoader.exists(texture_path):
		var texture: Texture2D = load(texture_path)
		if texture:
			_apply_texture_to_model(model, texture)
	
	# Make model unshaded for consistent look
	_apply_unshaded_to_model(model)
	viewport.add_child(model)
	
	# Add viewport to scene tree temporarily (required for rendering)
	var tree := Engine.get_main_loop() as SceneTree
	if not tree:
		viewport.queue_free()
		return null
	
	tree.root.add_child(viewport)
	
	# Wait for render - need multiple frames for model to fully load
	for i in range(5):
		await tree.process_frame
	
	# Force viewport to render now
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await tree.process_frame
	await tree.process_frame
	
	# Capture the rendered image
	var image: Image = viewport.get_texture().get_image()
	
	# Cleanup
	viewport.queue_free()
	
	if not image:
		return null
	
	# Create ImageTexture from the rendered image
	var result_texture := ImageTexture.create_from_image(image)
	return result_texture


## Synchronous version that returns a Control with the snapshot
## Use this when you can't await (e.g., in UI building)
static func create_model_preview_control(
	model_path: String,
	texture_path: String = "",
	size: Vector2 = Vector2(120, 120),
	model_rotation_y: float = 0.3
) -> Control:
	var container := CenterContainer.new()
	container.custom_minimum_size = size
	
	# Create transparent placeholder while rendering
	var placeholder := ColorRect.new()
	placeholder.color = Color(0, 0, 0, 0)
	placeholder.custom_minimum_size = size
	container.add_child(placeholder)
	
	# Start async rendering
	_render_and_display.call_deferred(container, placeholder, model_path, texture_path, size, model_rotation_y)
	
	return container


static func _render_and_display(
	container: Control,
	placeholder: Control,
	model_path: String,
	texture_path: String,
	size: Vector2,
	model_rotation_y: float
) -> void:
	var texture := await render_model_snapshot(model_path, texture_path, Vector2i(int(size.x * 2), int(size.y * 2)), model_rotation_y)
	
	if not is_instance_valid(container):
		return
	
	if placeholder and is_instance_valid(placeholder):
		placeholder.queue_free()
	
	if texture:
		var texture_rect := TextureRect.new()
		texture_rect.texture = texture
		texture_rect.custom_minimum_size = size
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		container.add_child(texture_rect)
	else:
		# Show error placeholder
		var error_rect := ColorRect.new()
		error_rect.color = Color(0.3, 0.1, 0.1, 0.5)
		error_rect.custom_minimum_size = size
		container.add_child(error_rect)


static func _apply_texture_to_model(node: Node, texture: Texture2D) -> void:
	for child in node.get_children():
		_apply_texture_to_model(child, texture)
	
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_texture = texture
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				mesh_inst.set_surface_override_material(i, material)


static func _apply_unshaded_to_model(node: Node) -> void:
	for child in node.get_children():
		_apply_unshaded_to_model(child)
	
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				# Skip if already has override (texture was applied)
				if mesh_inst.get_surface_override_material(i) != null:
					continue
				# Get existing material and make unshaded copy
				var existing: Material = mesh_inst.mesh.surface_get_material(i)
				if existing is StandardMaterial3D:
					var mat_copy: StandardMaterial3D = existing.duplicate()
					mat_copy.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mesh_inst.set_surface_override_material(i, mat_copy)

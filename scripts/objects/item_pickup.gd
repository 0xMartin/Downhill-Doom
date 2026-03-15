extends Node3D
## Item3D - Collectible item that can be picked up by the player
## Spawns on terrain and adds to player's inventory when touched

signal picked_up(item_id: String)

@export var item_id: String = ""
@export var rotation_speed: float = 2.0
@export var bob_speed: float = 2.0
@export var bob_height: float = 0.15

var _initial_y: float = 0.0
var _time: float = 0.0
var _is_picked_up: bool = false

# Cached references
var _model: Node3D
var _particles: GPUParticles3D
var _area: Area3D
var _glow_beam: MeshInstance3D

func _ready() -> void:
	_initial_y = position.y
	_time = randf() * TAU  # Random start phase for variety
	
	_model = get_node_or_null("Model")
	_particles = get_node_or_null("Particles")
	_area = get_node_or_null("PickupArea")
	_glow_beam = get_node_or_null("GlowBeam")
	
	if _area:
		_area.body_entered.connect(_on_body_entered)
	
	# Set particle color based on rarity
	_update_rarity_visuals()
	
	add_to_group("items")

func _process(delta: float) -> void:
	if _is_picked_up:
		return
	
	_time += delta
	
	# Rotate model
	if _model:
		_model.rotate_y(rotation_speed * delta)
	
	# Bob up and down
	var bob_offset := sin(_time * bob_speed) * bob_height
	position.y = _initial_y + bob_offset
	
	# Keep glow beam anchored to ground (compensate for bob)
	if _glow_beam:
		_glow_beam.position.y = 3.2 - bob_offset

func _update_rarity_visuals() -> void:
	var item_data: ItemConfig.ItemData = ItemConfig.get_item(item_id)
	if item_data == null:
		return
	
	var rarity_color: Color = item_data.get_rarity_color()
	
	# Update particle color if exists
	if _particles:
		var mat: ParticleProcessMaterial = _particles.process_material
		if mat:
			mat = mat.duplicate()
			mat.color = rarity_color
			_particles.process_material = mat
	
	# Update glow beam color
	if _glow_beam:
		var mat: ShaderMaterial = _glow_beam.get_surface_override_material(0) as ShaderMaterial
		if mat:
			mat = mat.duplicate()
			mat.set_shader_parameter("glow_color", rarity_color)
			# Increase intensity for higher rarity
			if item_data.rarity == ItemConfig.Rarity.LEGENDARY:
				mat.set_shader_parameter("intensity", 2.5)
				mat.set_shader_parameter("pulse_amount", 0.5)
			elif item_data.rarity == ItemConfig.Rarity.RARE:
				mat.set_shader_parameter("intensity", 2.0)
				mat.set_shader_parameter("pulse_amount", 0.4)
			_glow_beam.set_surface_override_material(0, mat)

func _on_body_entered(body: Node) -> void:
	if _is_picked_up:
		return
	
	if not body.is_in_group("player"):
		return
	
	_try_pickup()

func _try_pickup() -> void:
	var inventory := get_node_or_null("/root/InventoryManager")
	if inventory == null:
		push_error("Item3D: InventoryManager not found!")
		return
	
	# Try to add to inventory
	var slot: int = inventory.add_item(item_id)
	
	if slot >= 0:
		# Successfully picked up
		_is_picked_up = true
		picked_up.emit(item_id)
		_play_pickup_effect()
	else:
		# Inventory full - item stays in place
		_play_inventory_full_feedback()

func _play_pickup_effect() -> void:
	# Play sound
	var audio := get_node_or_null("/root/AudioManager")
	if audio and audio.has_method("play_sfx"):
		audio.play_sfx("item_pickup")
	
	# Show popup
	var item_data: ItemConfig.ItemData = ItemConfig.get_item(item_id)
	if item_data:
		var gm := get_node_or_null("/root/GameManager")
		if gm and gm.has_method("show_popup"):
			gm.show_popup(item_data.display_name, position, Color(0.3, 1.0, 0.3))
	
	# Animate out
	var tween := create_tween()
	tween.set_parallel(true)
	
	# Scale up and fade
	tween.tween_property(self, "scale", Vector3(1.5, 1.5, 1.5), 0.2)
	
	if _model:
		tween.tween_property(_model, "modulate:a", 0.0, 0.2)
	
	# Move up slightly
	tween.tween_property(self, "position:y", position.y + 1.0, 0.2)
	
	# Delete after animation
	tween.chain().tween_callback(queue_free)

func _play_inventory_full_feedback() -> void:
	# Brief shake to indicate can't pick up
	var tween := create_tween()
	var original_pos := position
	
	tween.tween_property(self, "position:x", original_pos.x + 0.1, 0.05)
	tween.tween_property(self, "position:x", original_pos.x - 0.1, 0.1)
	tween.tween_property(self, "position:x", original_pos.x, 0.05)

## Set up the item with specific ID and model
func setup(p_item_id: String, model_scene: PackedScene = null) -> void:
	item_id = p_item_id
	
	if model_scene and _model:
		# Remove existing model children
		for child in _model.get_children():
			child.queue_free()
		
		# Instance new model
		var instance := model_scene.instantiate()
		_model.add_child(instance)
	
	_update_rarity_visuals()

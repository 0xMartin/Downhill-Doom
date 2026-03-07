extends CanvasLayer
## Scene transition with diagonal stripes that slide in one by one
## Each stripe covers a diagonal section and they fit together like puzzle pieces
## - Menu→Game: Stripes slide in from top-left diagonally
## - Game→Menu: Stripes slide out to bottom-right

# Layer configuration
const LAYER_COUNT := 5
const LAYER_PATHS := [
	"res://assets/svg/transition_layer_1.svg",
	"res://assets/svg/transition_layer_2.svg",
	"res://assets/svg/transition_layer_3.svg",
	"res://assets/svg/transition_layer_4.svg",
	"res://assets/svg/transition_layer_5.svg",
]

# Timing - each stripe arrives noticeably after the previous one
const STRIPE_DELAY := 0.12  # Delay between each stripe
const STRIPE_DURATION := 0.25  # How long each stripe takes to slide in

# Scale/rotation animation ranges - dramatic effect
const SCALE_MIN := 0.25
const SCALE_MAX := 2.5
const ROTATION_MAX := 180.0

# Internal
var _target_scene: String = ""
var _layers: Array[TextureRect] = []
var _is_transitioning := false

func _ready() -> void:
	_setup_layers()

func _setup_layers() -> void:
	# Create TextureRect for each layer
	for i in range(LAYER_COUNT):
		var layer := TextureRect.new()
		layer.name = "Stripe%d" % (i + 1)
		layer.texture = load(LAYER_PATHS[i])
		layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		layer.anchors_preset = Control.PRESET_FULL_RECT
		layer.anchor_right = 1.0
		layer.anchor_bottom = 1.0
		layer.visible = false
		layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(layer)
		_layers.append(layer)

## Change scene with direction-aware transition
func change_scene(target: String) -> void:
	if _is_transitioning:
		return
	
	_is_transitioning = true
	_target_scene = target
	
	var going_to_game := target.contains("game.tscn")
	
	if going_to_game:
		await _transition_to_game()
	else:
		await _transition_to_menu()
	
	_is_transitioning = false

## Menu → Game: Stripes slide in diagonally from top-left, one by one
func _transition_to_game() -> void:
	var screen_size := get_viewport().get_visible_rect().size
	
	# Each stripe starts off-screen diagonally (top-left) with random scale/rotation
	for i in range(LAYER_COUNT):
		var offset := Vector2(
			-screen_size.x * (0.6 + i * 0.3),
			-screen_size.y * (0.6 + i * 0.3)
		)
		_layers[i].position = offset
		_layers[i].visible = true
		# Random starting scale and rotation
		var start_scale := randf_range(SCALE_MIN, SCALE_MAX)
		_layers[i].scale = Vector2(start_scale, start_scale)
		var rotation_dir := 1.0 if randf() > 0.5 else -1.0
		_layers[i].rotation = deg_to_rad(randf_range(0.0, ROTATION_MAX) * rotation_dir)
		# Set pivot to center for proper rotation
		_layers[i].pivot_offset = screen_size / 2.0
	
	# Animate stripes sliding in one by one
	var last_tween: Tween
	for i in range(LAYER_COUNT):
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_QUART)
		tween.set_parallel(true)
		
		# Each stripe has increasing delay
		var delay := STRIPE_DELAY * i
		
		# Slide to final position (0,0 - each SVG defines its own shape position)
		tween.tween_property(_layers[i], "position", Vector2.ZERO, STRIPE_DURATION).set_delay(delay)
		tween.tween_property(_layers[i], "scale", Vector2.ONE, STRIPE_DURATION).set_delay(delay)
		tween.tween_property(_layers[i], "rotation", 0.0, STRIPE_DURATION).set_delay(delay)
		last_tween = tween
	
	# Wait for last stripe to arrive
	await last_tween.finished
	await get_tree().create_timer(0.05).timeout
	
	# Change scene while fully covered
	get_tree().change_scene_to_file(_target_scene)
	await get_tree().process_frame
	
	# Phase 2: Stripes slide out to bottom-right, one by one (reverse order)
	# Front layers (higher index) exit first, back layers exit last
	var slowest_tween: Tween
	var max_delay := 0.0
	
	for i in range(LAYER_COUNT):
		var exit_offset := Vector2(
			screen_size.x * (0.6 + i * 0.3),
			screen_size.y * (0.6 + i * 0.3)
		)
		# Random exit scale and rotation
		var exit_scale := randf_range(SCALE_MIN, SCALE_MAX)
		var rotation_dir := 1.0 if randf() > 0.5 else -1.0
		var exit_rotation := deg_to_rad(randf_range(0.0, ROTATION_MAX) * rotation_dir)
		
		var tween := create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_QUART)
		tween.set_parallel(true)
		
		# Reverse order - last stripe (front, i=4) exits first (no delay)
		# First stripe (back, i=0) exits last (most delay)
		var reverse_i := LAYER_COUNT - 1 - i
		var delay := STRIPE_DELAY * reverse_i * 0.8
		
		tween.tween_property(_layers[i], "position", exit_offset, STRIPE_DURATION).set_delay(delay)
		tween.tween_property(_layers[i], "scale", Vector2(exit_scale, exit_scale), STRIPE_DURATION).set_delay(delay)
		tween.tween_property(_layers[i], "rotation", exit_rotation, STRIPE_DURATION).set_delay(delay)
		
		# Track the tween with the longest delay (it will finish last)
		if delay >= max_delay:
			max_delay = delay
			slowest_tween = tween
	
	await slowest_tween.finished
	_hide_all_layers()

## Game → Menu: Calm transition, stripes slide in from bottom-right
func _transition_to_menu() -> void:
	var screen_size := get_viewport().get_visible_rect().size
	var calm_multiplier := 1.3  # Slower for calm feel
	
	# Each stripe starts off-screen diagonally (bottom-right) with random scale/rotation
	for i in range(LAYER_COUNT):
		var reverse_i := LAYER_COUNT - 1 - i
		var offset := Vector2(
			screen_size.x * (0.6 + reverse_i * 0.3),
			screen_size.y * (0.6 + reverse_i * 0.3)
		)
		_layers[i].position = offset
		_layers[i].visible = true
		# Random starting scale and rotation
		var start_scale := randf_range(SCALE_MIN, SCALE_MAX)
		_layers[i].scale = Vector2(start_scale, start_scale)
		var rotation_dir := 1.0 if randf() > 0.5 else -1.0
		_layers[i].rotation = deg_to_rad(randf_range(0.0, ROTATION_MAX) * rotation_dir)
		# Set pivot to center for proper rotation
		_layers[i].pivot_offset = screen_size / 2.0
	
	# Animate stripes sliding in (reverse order - bottom stripes first)
	var last_tween: Tween
	for i in range(LAYER_COUNT - 1, -1, -1):  # 4, 3, 2, 1, 0
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_SINE)  # Smoother for calm feel
		tween.set_parallel(true)
		
		var delay_index := LAYER_COUNT - 1 - i
		var delay := STRIPE_DELAY * delay_index * calm_multiplier
		
		tween.tween_property(_layers[i], "position", Vector2.ZERO, STRIPE_DURATION * calm_multiplier).set_delay(delay)
		tween.tween_property(_layers[i], "scale", Vector2.ONE, STRIPE_DURATION * calm_multiplier).set_delay(delay)
		tween.tween_property(_layers[i], "rotation", 0.0, STRIPE_DURATION * calm_multiplier).set_delay(delay)
		last_tween = tween
	
	await last_tween.finished
	await get_tree().create_timer(0.08).timeout
	
	# Change scene while fully covered
	get_tree().change_scene_to_file(_target_scene)
	await get_tree().process_frame
	
	# Phase 2: Stripes slide out to top-left
	for i in range(LAYER_COUNT):
		var exit_offset := Vector2(
			-screen_size.x * (0.6 + i * 0.3),
			-screen_size.y * (0.6 + i * 0.3)
		)
		# Random exit scale and rotation
		var exit_scale := randf_range(SCALE_MIN, SCALE_MAX)
		var rotation_dir := 1.0 if randf() > 0.5 else -1.0
		var exit_rotation := deg_to_rad(randf_range(0.0, ROTATION_MAX) * rotation_dir)
		
		var tween := create_tween()
		tween.set_ease(Tween.EASE_IN)
		tween.set_trans(Tween.TRANS_SINE)
		tween.set_parallel(true)
		
		var delay := STRIPE_DELAY * i * calm_multiplier
		
		tween.tween_property(_layers[i], "position", exit_offset, STRIPE_DURATION * calm_multiplier).set_delay(delay)
		tween.tween_property(_layers[i], "scale", Vector2(exit_scale, exit_scale), STRIPE_DURATION * calm_multiplier).set_delay(delay)
		tween.tween_property(_layers[i], "rotation", exit_rotation, STRIPE_DURATION * calm_multiplier).set_delay(delay)
		last_tween = tween
	
	await last_tween.finished
	_hide_all_layers()

func _hide_all_layers() -> void:
	for layer in _layers:
		layer.visible = false
		layer.position = Vector2.ZERO
		layer.scale = Vector2.ONE
		layer.rotation = 0.0

## Legacy API support
func fade_in() -> void:
	pass

func fade_out() -> void:
	pass

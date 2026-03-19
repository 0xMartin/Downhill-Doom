extends Node
## TutorialManager - Controls the interactive tutorial flow
## Handles step-by-step guidance with dialog boxes and detection

signal tutorial_completed
signal step_completed(step: int)

enum TutorialStep {
	NONE = 0,
	WAIT_FOR_LANDING,
	TILT_LEFT,
	TILT_RIGHT,
	TAP_TO_JUMP,
	SLAM_ATTACK,
	SUPERCHARGE_INTRO,
	SUPERCHARGE_FILL,
	SUPERCHARGE_ACTIVATE,
	SUPERCHARGE_INFO,
	WAIT_SUPERCHARGE_END,
	INVENTORY_INTRO,
	INVENTORY_PICKUP,
	INVENTORY_USE,
	GAMEPLAY_TIP,
	COMPLETED
}

const TUTORIAL_DIALOG_SCENE := preload("res://scenes/ui/tutorial_dialog.tscn")

# References
var hud: Node
var gm: Node
var player: Node
var inventory: Node
var dialog: Control
var dialog_panel: PanelContainer
var title_label: Label
var message_label: Label
var ok_button: Button

# State
var current_step: TutorialStep = TutorialStep.NONE
var is_active: bool = false
var is_waiting_for_action: bool = false
var was_game_paused: bool = false
var is_transitioning: bool = false  # Prevents multiple await transitions
var safe_area_offset: float = 0.0  # Safe area top offset for dialog position
var dialog_tween: Tween = null  # Track dialog animation tween

# Detection state
var tilt_detected_left: bool = false
var tilt_detected_right: bool = false
var tilt_hold_timer: float = 0.0
var jump_detected: bool = false
var waiting_for_ground: bool = false  # Wait for player to land before detecting new jump
var slam_jump_done: bool = false
var slam_detected: bool = false
var supercharge_button_pressed: bool = false
var item_picked_up: bool = false
var item_used: bool = false

# Highlight tracking
var highlighted_nodes: Array[Control] = []
var highlight_tweens: Array[Tween] = []
var original_styles: Dictionary = {}  # node -> original stylebox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func _process(delta: float) -> void:
	if not is_active:
		return
	
	match current_step:
		TutorialStep.WAIT_FOR_LANDING:
			_check_landing(delta)
		TutorialStep.TILT_LEFT:
			_check_tilt_left(delta)
		TutorialStep.TILT_RIGHT:
			_check_tilt_right(delta)
		TutorialStep.TAP_TO_JUMP:
			_check_jump()
		TutorialStep.SLAM_ATTACK:
			_check_slam()
		TutorialStep.SUPERCHARGE_FILL:
			_check_supercharge_fill()
		TutorialStep.WAIT_SUPERCHARGE_END:
			_check_supercharge_ended()
		TutorialStep.INVENTORY_PICKUP:
			_check_item_pickup()


func initialize(hud_ref: Node) -> void:
	hud = hud_ref
	gm = get_node_or_null("/root/GameManager")
	inventory = get_node_or_null("/root/InventoryManager")
	
	# Calculate safe area offset
	_calculate_safe_area_offset()
	
	# Create dialog instance
	dialog = TUTORIAL_DIALOG_SCENE.instantiate()
	dialog.visible = false
	dialog.z_index = 200
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS  # Work during pause
	hud.add_child(dialog)
	
	# Get dialog components
	dialog_panel = dialog.get_node("DialogPanel")
	dialog_panel.mouse_filter = Control.MOUSE_FILTER_PASS  # Allow clicks to pass through to elements below
	title_label = dialog.get_node("DialogPanel/MarginContainer/VBoxContainer/TitleLabel")
	message_label = dialog.get_node("DialogPanel/MarginContainer/VBoxContainer/MessageLabel")
	ok_button = dialog.get_node("DialogPanel/MarginContainer/VBoxContainer/OkButton")
	
	# Apply safe area offset to dialog panel
	if dialog_panel:
		dialog_panel.offset_top = 60.0 + safe_area_offset
		dialog_panel.offset_bottom = 320.0 + safe_area_offset
	
	ok_button.pressed.connect(_on_ok_pressed)


func _calculate_safe_area_offset() -> void:
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale_y: float = viewport_size.y / float(screen_size.y) if screen_size.y > 0 else 1.0
	var top_inset_viewport: float = float(safe_area.position.y) * scale_y
	var min_top_offset: float = 20.0
	safe_area_offset = maxf(top_inset_viewport, min_top_offset) - min_top_offset  # Extra offset beyond default


func should_start_tutorial() -> bool:
	# Check if tutorial was already completed
	var storage := get_node_or_null("/root/SecureStorage")
	if storage:
		return not storage.is_tutorial_completed()
	return true


func start_tutorial() -> void:
	if is_active:
		return
	
	is_active = true
	set_process(true)
	
	# Get player reference
	if gm:
		player = gm.player
	
	# Start with waiting for player to land
	current_step = TutorialStep.WAIT_FOR_LANDING


func _check_landing(_delta: float) -> void:
	if is_transitioning:
		return
	
	if player == null:
		if gm:
			player = gm.player
		return
	
	# Check if player is on ground
	if player.is_on_ground:
		# Set flag to prevent multiple awaits
		is_transitioning = true
		# Wait 2 seconds then start tutorial
		await get_tree().create_timer(2.0).timeout
		if is_active:
			_advance_to_step(TutorialStep.TILT_LEFT)
		is_transitioning = false


func _advance_to_step(step: TutorialStep) -> void:
	current_step = step
	is_transitioning = false  # Reset transition flag
	step_completed.emit(step - 1)
	
	# Reset detection flags
	tilt_detected_left = false
	tilt_detected_right = false
	tilt_hold_timer = 0.0
	jump_detected = false
	waiting_for_ground = true  # Always wait for ground first before detecting jump
	slam_jump_done = false
	slam_detected = false
	supercharge_button_pressed = false
	item_picked_up = false
	item_used = false
	
	match step:
		TutorialStep.TILT_LEFT:
			_show_dialog("STEERING", "Tilt your phone to the LEFT!", false)
		
		TutorialStep.TILT_RIGHT:
			_show_dialog("STEERING", "Now tilt to the RIGHT!", false)
		
		TutorialStep.TAP_TO_JUMP:
			_show_dialog("JUMPING", "Tap the screen to JUMP!", false)
		
		TutorialStep.SLAM_ATTACK:
			_show_dialog("SLAM ATTACK", "Jump, then TAP AGAIN while falling to slam down hard!", false)
		
		TutorialStep.SUPERCHARGE_INTRO:
			_pause_game()
			_show_dialog("SUPERCHARGE", "Destroy objects to fill your SUPERCHARGE bar on the LEFT side!", true)
		
		TutorialStep.SUPERCHARGE_FILL:
			_reset_supercharge()
			_resume_game()
			_show_dialog("SUPERCHARGE", "Destroy 10 objects to fill the bar!", false)
			_highlight_supercharge_bar()
		
		TutorialStep.SUPERCHARGE_ACTIVATE:
			# DON'T pause for this step - player needs to tap the button!
			_show_dialog("SUPERCHARGE READY!", "Tap the FIRE button to activate!", false)
			_highlight_supercharge_button()
		
		TutorialStep.SUPERCHARGE_INFO:
			_pause_game()
			_clear_highlights()
			await get_tree().create_timer(1.0).timeout
			_show_dialog("SUPERCHARGE MODE", "You are INVINCIBLE and can destroy LARGE and ENEMY buildings!", true)
		
		TutorialStep.WAIT_SUPERCHARGE_END:
			# Resume game and let player enjoy supercharge
			_resume_game()
			_hide_dialog()
		
		TutorialStep.INVENTORY_INTRO:
			_pause_game()
			_clear_inventory()
			_show_dialog("ITEMS", "Collect items to gain powerful abilities!", true)
		
		TutorialStep.INVENTORY_PICKUP:
			_resume_game()
			_show_dialog("COLLECT ITEM", "Look for glowing beams - items spawn there!", false)
		
		TutorialStep.INVENTORY_USE:
			# DON'T pause - player needs to tap the item!
			_show_dialog("USE ITEM", "Tap an item in your inventory to use it!", false)
			_highlight_inventory_slots()
		
		TutorialStep.GAMEPLAY_TIP:
			_pause_game()
			_show_dialog("KEEP ROLLING!", "The further you go, the more coins you earn! Difficulty increases and new obstacles appear.", true)
		
		TutorialStep.COMPLETED:
			_complete_tutorial()


func _show_dialog(title: String, message: String, show_ok: bool) -> void:
	# Kill any existing dialog tween to prevent conflicts
	if dialog_tween and dialog_tween.is_valid():
		dialog_tween.kill()
	
	title_label.text = title
	message_label.text = message
	ok_button.visible = show_ok
	dialog.visible = true
	
	# Animate in
	dialog_panel.modulate.a = 0.0
	dialog_panel.scale = Vector2(0.8, 0.8)
	dialog_panel.pivot_offset = dialog_panel.size / 2
	
	dialog_tween = create_tween()
	dialog_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # Work during pause
	dialog_tween.set_parallel(true)
	dialog_tween.tween_property(dialog_panel, "modulate:a", 1.0, 0.3)
	dialog_tween.tween_property(dialog_panel, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _hide_dialog() -> void:
	# Kill any existing dialog tween to prevent conflicts
	if dialog_tween and dialog_tween.is_valid():
		dialog_tween.kill()
	
	dialog_tween = create_tween()
	dialog_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # Work during pause
	dialog_tween.set_parallel(true)
	dialog_tween.tween_property(dialog_panel, "modulate:a", 0.0, 0.2)
	dialog_tween.tween_property(dialog_panel, "scale", Vector2(0.9, 0.9), 0.2)
	dialog_tween.set_parallel(false)
	dialog_tween.tween_callback(func(): dialog.visible = false)


func _on_ok_pressed() -> void:
	_hide_dialog()
	
	match current_step:
		TutorialStep.SUPERCHARGE_INTRO:
			_advance_to_step(TutorialStep.SUPERCHARGE_FILL)
		TutorialStep.SUPERCHARGE_INFO:
			# Don't go to inventory yet - wait for supercharge to end
			_advance_to_step(TutorialStep.WAIT_SUPERCHARGE_END)
		TutorialStep.INVENTORY_INTRO:
			_advance_to_step(TutorialStep.INVENTORY_PICKUP)
		TutorialStep.GAMEPLAY_TIP:
			_advance_to_step(TutorialStep.COMPLETED)
		TutorialStep.COMPLETED:
			# Final dialog dismissed - wait for hide animation then clean up
			await get_tree().create_timer(0.3).timeout
			if dialog:
				dialog.queue_free()
			queue_free()
		_:
			_resume_game()


func _pause_game() -> void:
	if gm and not gm.is_paused:
		was_game_paused = false
		gm.is_paused = true
		get_tree().paused = true
	else:
		was_game_paused = true


func _resume_game() -> void:
	if not was_game_paused and gm:
		gm.is_paused = false
		get_tree().paused = false


# ========== Detection Functions ==========

func _check_tilt_left(delta: float) -> void:
	if is_transitioning:
		return
	
	var accel := Input.get_accelerometer()
	var detected := false
	
	if accel == Vector3.ZERO:
		# Desktop fallback: check keyboard
		if Input.is_action_pressed("move_left"):
			detected = true
	else:
		var tilt := accel.x / 6.0
		if tilt < -0.3:
			detected = true
	
	if detected:
		tilt_hold_timer += delta
		if tilt_hold_timer >= 0.6:  # Hold for 0.6 seconds
			is_transitioning = true
			_advance_to_step(TutorialStep.TILT_RIGHT)
	else:
		tilt_hold_timer = 0.0  # Reset if not tilting


func _check_tilt_right(delta: float) -> void:
	if is_transitioning:
		return
	
	var accel := Input.get_accelerometer()
	var detected := false
	
	if accel == Vector3.ZERO:
		# Desktop fallback: check keyboard
		if Input.is_action_pressed("move_right"):
			detected = true
	else:
		var tilt := accel.x / 6.0
		if tilt > 0.3:
			detected = true
	
	if detected:
		tilt_hold_timer += delta
		if tilt_hold_timer >= 0.6:  # Hold for 0.6 seconds
			is_transitioning = true
			_advance_to_step(TutorialStep.TAP_TO_JUMP)
	else:
		tilt_hold_timer = 0.0  # Reset if not tilting


func _check_jump() -> void:
	if is_transitioning:
		return
	if player == null:
		return
	
	# First wait for player to be on ground (ensures we detect a NEW jump)
	if waiting_for_ground:
		if player.is_on_ground and not player.has_jumped:
			waiting_for_ground = false
		return
	
	# Now wait for the actual jump
	if player.has_jumped and not jump_detected:
		jump_detected = true
		is_transitioning = true
		_hide_dialog()
		# Small delay before next step
		await get_tree().create_timer(0.5).timeout
		if is_active:
			_advance_to_step(TutorialStep.SLAM_ATTACK)
		is_transitioning = false


func _check_slam() -> void:
	if is_transitioning:
		return
	if player == null:
		return
	
	# Check if player jumped
	if player.has_jumped and not slam_jump_done:
		slam_jump_done = true
	
	# Check if slam was executed (player charged slam while falling)
	if slam_jump_done and player.slam_charged:
		slam_detected = true
	
	# Wait for slam landing
	if slam_detected and player.is_on_ground:
		is_transitioning = true
		_hide_dialog()
		await get_tree().create_timer(1.0).timeout
		if is_active:
			_advance_to_step(TutorialStep.SUPERCHARGE_INTRO)
		is_transitioning = false


func _reset_supercharge() -> void:
	if gm:
		gm.supercharge_objects = 0
		gm.supercharge_activations = 0
		gm.supercharge_changed.emit(0, gm.get_supercharge_requirement())


func _check_supercharge_fill() -> void:
	if is_transitioning:
		return
	if gm and gm.is_supercharge_ready():
		is_transitioning = true
		_clear_highlights()
		_hide_dialog()
		await get_tree().create_timer(0.5).timeout
		if is_active:
			_advance_to_step(TutorialStep.SUPERCHARGE_ACTIVATE)
		is_transitioning = false


func _check_supercharge_ended() -> void:
	if is_transitioning:
		return
	# Check if supercharge is no longer active
	if gm and not gm.is_supercharged:
		is_transitioning = true
		await get_tree().create_timer(1.0).timeout
		if is_active:
			_advance_to_step(TutorialStep.INVENTORY_INTRO)
		is_transitioning = false


## Called by HUD when supercharge button is pressed during tutorial
func on_supercharge_activated() -> void:
	if current_step == TutorialStep.SUPERCHARGE_ACTIVATE:
		_clear_highlights()
		_hide_dialog()
		_advance_to_step(TutorialStep.SUPERCHARGE_INFO)


func _clear_inventory() -> void:
	if inventory:
		inventory.clear()


func _check_item_pickup() -> void:
	if is_transitioning:
		return
	if inventory == null:
		return
	
	# Check if any item was picked up
	for i in range(3):
		if inventory.get_item(i) != "":
			item_picked_up = true
			is_transitioning = true
			_hide_dialog()
			await get_tree().create_timer(0.5).timeout
			if is_active:
				_advance_to_step(TutorialStep.INVENTORY_USE)
			is_transitioning = false


## Called by HUD when inventory item is used during tutorial
func on_item_used() -> void:
	if is_transitioning:
		return
	if current_step == TutorialStep.INVENTORY_USE:
		is_transitioning = true
		_clear_highlights()
		_hide_dialog()
		await get_tree().create_timer(0.5).timeout
		if is_active:
			_advance_to_step(TutorialStep.GAMEPLAY_TIP)
		is_transitioning = false


# ========== Highlight System ==========

func _highlight_node(node: Control) -> void:
	if node == null:
		return
	
	highlighted_nodes.append(node)
	
	# Create red outline effect
	var outline := Panel.new()
	outline.name = "TutorialHighlight"
	outline.set_anchors_preset(Control.PRESET_FULL_RECT)
	outline.offset_left = -6
	outline.offset_top = -6
	outline.offset_right = 6
	outline.offset_bottom = 6
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 8
	style.border_width_top = 8
	style.border_width_right = 8
	style.border_width_bottom = 8
	style.border_color = Color(1, 0.2, 0.2, 1)
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_right = 15
	style.corner_radius_bottom_left = 15
	outline.add_theme_stylebox_override("panel", style)
	
	node.add_child(outline)
	
	# Blinking animation
	var tween := create_tween()
	tween.set_loops()
	tween.tween_property(outline, "modulate:a", 0.3, 0.4)
	tween.tween_property(outline, "modulate:a", 1.0, 0.4)
	highlight_tweens.append(tween)


func _clear_highlights() -> void:
	# Kill all tweens
	for tw in highlight_tweens:
		if tw and tw.is_valid():
			tw.kill()
	highlight_tweens.clear()
	
	# Remove highlight panels
	for node in highlighted_nodes:
		if is_instance_valid(node):
			var highlight := node.get_node_or_null("TutorialHighlight")
			if highlight:
				highlight.queue_free()
	highlighted_nodes.clear()


func _highlight_supercharge_bar() -> void:
	# Find supercharge panel in HUD
	var panel := hud.get_node_or_null("SideBar/SuperchargePanel")
	if panel:
		_highlight_node(panel)


func _highlight_supercharge_button() -> void:
	# Find supercharge button
	var btn := hud.get_node_or_null("SideBar/SuperchargePanel/SuperchargeContainer/ButtonContainer/SuperchargeButton")
	if btn:
		_highlight_node(btn)


func _highlight_inventory_slots() -> void:
	# Find inventory slots
	for i in range(3):
		var slot := hud.get_node_or_null("SideBar/InvSlot%d" % (i + 1))
		if slot:
			_highlight_node(slot)


# ========== Completion ==========

func _complete_tutorial() -> void:
	is_active = false
	set_process(false)
	_clear_highlights()
	_resume_game()
	
	# Save completion to persistent storage
	var storage := get_node_or_null("/root/SecureStorage")
	if storage:
		storage.set_tutorial_completed(true)
	
	tutorial_completed.emit()
	
	# Show completion message
	current_step = TutorialStep.COMPLETED  # Set step so OK button knows what to do
	await get_tree().create_timer(0.5).timeout
	_show_dialog("TUTORIAL COMPLETE!", "You're ready to roll! Good luck!", true)

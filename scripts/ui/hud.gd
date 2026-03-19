extends CanvasLayer
## HUD - Displays coins, distance, health, and handles pause

signal jump_pressed  # Emitted when touch jump button is pressed

@onready var top_bar: PanelContainer = $TopBar
@onready var side_bar: VBoxContainer = $SideBar
@onready var coins_label: Label = $TopBar/MarginContainer/HBoxContainer/CoinsContainer/CoinsLabel
@onready var distance_label: Label = $TopBar/MarginContainer/HBoxContainer/DistanceContainer/DistanceLabel
@onready var health_bar: ProgressBar = $TopBar/MarginContainer/HBoxContainer/HealthContainer/HealthBar
@onready var health_label: Label = $TopBar/MarginContainer/HBoxContainer/HealthContainer/HealthBar/HealthLabel
@onready var red_flash: ColorRect = $RedFlash
@onready var green_flash: ColorRect = $GreenFlash
@onready var pause_menu: Control = $PauseMenu
@onready var music_slider: HSlider = $PauseMenu/PanelContainer/VBoxContainer/AudioSection/AudioVBox/MusicRow/MusicSlider
@onready var sfx_slider: HSlider = $PauseMenu/PanelContainer/VBoxContainer/AudioSection/AudioVBox/SFXRow/SFXSlider
@onready var popup_check: CheckButton = $PauseMenu/PanelContainer/VBoxContainer/DisplaySection/DisplayVBox/PopupCheck
@onready var damage_check: CheckButton = $PauseMenu/PanelContainer/VBoxContainer/DisplaySection/DisplayVBox/DamageCheck
@onready var haptic_check: CheckButton = $PauseMenu/PanelContainer/VBoxContainer/DisplaySection/DisplayVBox/HapticCheck
@onready var sparkle: TextureRect = $TopBar/MarginContainer/HBoxContainer/CoinsContainer/CoinIcon/Sparkle
@onready var popup_container: Control = $PopupContainer
@onready var timer_label: Label = $TimerLabel

var gm: Node  # GameManager reference
var audio: Node  # AudioManager reference
var coin_icon_texture: Texture2D
var heart_icon_texture: Texture2D  # Cached heart icon for damage popups
var last_coin_count: int = 0
var sparkle_time: float = 0.0
var sparkle_tween: Tween  # Track sparkle tween to prevent stacking
var current_multiplier: int = 1

# Supercharge UI
@onready var supercharge_panel: PanelContainer = $SideBar/SuperchargePanel
@onready var supercharge_container: VBoxContainer = $SideBar/SuperchargePanel/SuperchargeContainer
@onready var supercharge_bar: Control = $SideBar/SuperchargePanel/SuperchargeContainer/SuperchargeBar
@onready var supercharge_bar_fill: PanelContainer = $SideBar/SuperchargePanel/SuperchargeContainer/SuperchargeBar/BarBackground/BarFill
@onready var supercharge_button: TextureButton = $SideBar/SuperchargePanel/SuperchargeContainer/ButtonContainer/SuperchargeButton
@onready var supercharge_count_label: Label = $SideBar/SuperchargePanel/SuperchargeContainer/SuperchargeBar/SuperchargeCountLabel
var supercharge_bar_value: float = 0.0
var supercharge_bar_max: float = 100.0
var supercharge_display_value: float = 0.0  # Smoothly animated display value
var supercharge_fill_tween: Tween  # Tween for smooth fill animation
var supercharge_glow_tween: Tween
var supercharge_bar_glow_tween: Tween
var supercharge_ready: bool = false

# Multiplier UI
@onready var multiplier_panel: Control = $SideBar/MultiplierPanel
@onready var multiplier_label: Label = $SideBar/MultiplierPanel/MultiplierLabel
var multiplier_tween: Tween

# Settings button UI (floating)
@onready var settings_button: TextureButton = $SideBar/SettingsButtonPanel/ButtonContainer/SettingsButton

# Touch controls UI (visible in touch mode only)
@onready var touch_controls_container: Control = $TouchControls
@onready var touch_jump_button: TextureButton = $TouchControls/TouchJumpButton
@onready var touch_joystick_base: Control = $TouchControls/TouchJoystickBase
@onready var touch_joystick_knob: TextureRect = $TouchControls/TouchJoystickBase/JoystickKnob
var joystick_center: Vector2 = Vector2.ZERO  # Center of joystick base
var joystick_max_distance: float = 60.0  # Max knob drag distance  
var joystick_input: float = 0.0  # Current joystick X value (-1 to 1)
var joystick_touch_index: int = -1  # Track which finger is on joystick
var jump_button_pressed: bool = false  # Track jump button state

# Combo UI
@onready var combo_label: Label = $ComboLabel
var combo_tween: Tween
var current_combo: int = 0
var last_destroyed_id: String = ""
var skip_combo_popup: int = 0  # Amount to skip from regular popup (for combo bonuses)

# Quest UI
@onready var quest_panel: PanelContainer = $QuestPanel
@onready var quest_description: Label = $QuestPanel/Content/QuestDescription
@onready var quest_progress_bar: ProgressBar = $QuestPanel/Content/QuestProgressBar
@onready var quest_progress_label: Label = $QuestPanel/Content/QuestProgressBar/QuestProgressLabel
@onready var buff_indicator: VBoxContainer = $BuffIndicator
@onready var inventory_ui: Node = $InventoryUI
var quest_manager: Node
var tutorial_manager: Node
var _current_quest_id: String = ""
const COLOR_QUEST_PROGRESS := Color(0.25, 0.65, 0.96, 1)
const COLOR_QUEST_COMPLETED := Color(0.30, 0.85, 0.55, 1)

# Low health effects
var low_health_pulse_time: float = 0.0
var is_low_health: bool = false
const LOW_HEALTH_THRESHOLD: float = 0.3  # 30% health

# Stuck detection system
@onready var stuck_overlay: Control = $StuckOverlay
@onready var stuck_label: Label = $StuckOverlay/CenterContainer/VBoxContainer/StuckLabel
@onready var stuck_progress_bar: ProgressBar = $StuckOverlay/CenterContainer/VBoxContainer/BarContainer/StuckProgressBar
@onready var stuck_countdown_label: Label = $StuckOverlay/CenterContainer/VBoxContainer/CountdownLabel
var stuck_checkpoint_z: float = 0.0  # Z position when we started checking
var stuck_timer: float = 0.0
var stuck_countdown_timer: float = 0.0
var is_stuck_warning_shown: bool = false
var stuck_grace_period: float = 0.0  # Grace period at game start
const STUCK_MIN_MOVEMENT: float = 10.0  # Min Z distance to count as "moved"
const STUCK_WARNING_TIME: float = 3.0  # Seconds before warning shows
const STUCK_DEATH_TIME: float = 10.0  # Seconds to die after warning
const STUCK_GRACE_PERIOD: float = 5.0  # Grace period at game start

## Format large numbers with k/M suffix (13410 -> "13.41k")
static func format_number(n: int) -> String:
	if n >= 1_000_000:
		return "%.2fM" % (n / 1_000_000.0)
	elif n >= 1_000:
		return "%.2fk" % (n / 1_000.0)
	else:
		return str(n)

func _ready() -> void:
	gm = get_node("/root/GameManager")
	audio = get_node("/root/AudioManager")
	coin_icon_texture = load("res://assets/svg/coin.svg")
	heart_icon_texture = load("res://assets/svg/heart.svg")  # Cache heart icon
	gm.coins_changed.connect(_on_coins_changed)
	gm.distance_changed.connect(_on_distance_changed)
	gm.game_paused.connect(_on_game_paused)
	gm.health_changed.connect(_on_health_changed)
	gm.player_hit.connect(_on_player_hit)
	gm.player_healed.connect(_on_player_healed)
	gm.time_changed.connect(_on_time_changed)
	gm.supercharge_changed.connect(_on_supercharge_changed)
	gm.supercharge_activated.connect(_on_supercharge_activated)
	gm.supercharge_ended.connect(_on_supercharge_ended)
	gm.game_started.connect(_on_game_started)
	# Connect object destroyed signal for combo system
	gm.object_destroyed.connect(_on_object_destroyed)
	
	# Initialize touch controls (set visibility based on mode)
	_init_touch_controls()
	
	# Adjust top bar position for mobile safe area (notch, status bar)
	_apply_safe_area_offset()
	
	# Initialize sliders with current volume values
	if audio:
		music_slider.value = audio.get_music_volume()
		sfx_slider.value = audio.get_sfx_volume()
		popup_check.button_pressed = audio.get_show_pickup_popup()
		damage_check.button_pressed = audio.get_show_damage_popup()
		haptic_check.button_pressed = audio.get_haptic_enabled()
	
	pause_menu.visible = false
	red_flash.visible = false
	last_coin_count = gm.coins  # Initialize to prevent popup on start
	_on_coins_changed(gm.coins)
	_on_distance_changed(gm.distance)
	_on_health_changed(gm.health, gm.max_health)
	
	# Connect quest manager signals
	call_deferred("_connect_quest_signals")
	
	# Initialize tutorial manager (must be direct, not deferred, so it's ready for game_started signal)
	_init_tutorial()

func _exit_tree() -> void:
	# Disconnect signals to prevent duplicate connections if re-added
	if gm:
		if gm.coins_changed.is_connected(_on_coins_changed):
			gm.coins_changed.disconnect(_on_coins_changed)
		if gm.distance_changed.is_connected(_on_distance_changed):
			gm.distance_changed.disconnect(_on_distance_changed)
		if gm.game_paused.is_connected(_on_game_paused):
			gm.game_paused.disconnect(_on_game_paused)
		if gm.health_changed.is_connected(_on_health_changed):
			gm.health_changed.disconnect(_on_health_changed)
		if gm.player_hit.is_connected(_on_player_hit):
			gm.player_hit.disconnect(_on_player_hit)
		if gm.player_healed.is_connected(_on_player_healed):
			gm.player_healed.disconnect(_on_player_healed)
		if gm.time_changed.is_connected(_on_time_changed):
			gm.time_changed.disconnect(_on_time_changed)
		if gm.supercharge_changed.is_connected(_on_supercharge_changed):
			gm.supercharge_changed.disconnect(_on_supercharge_changed)
		if gm.supercharge_activated.is_connected(_on_supercharge_activated):
			gm.supercharge_activated.disconnect(_on_supercharge_activated)
		if gm.supercharge_ended.is_connected(_on_supercharge_ended):
			gm.supercharge_ended.disconnect(_on_supercharge_ended)
		if gm.game_started.is_connected(_on_game_started):
			gm.game_started.disconnect(_on_game_started)
		if gm.object_destroyed.is_connected(_on_object_destroyed):
			gm.object_destroyed.disconnect(_on_object_destroyed)

func _process(delta: float) -> void:
	# Sparkle orbits around the coin
	sparkle_time += delta * 1.5
	if sparkle:
		var orbit_radius := 22.0
		var orbit_x := cos(sparkle_time) * orbit_radius
		var orbit_y := sin(sparkle_time) * orbit_radius
		sparkle.position = Vector2(8 + orbit_x, 8 + orbit_y)
		sparkle.rotation = sparkle_time  # Spin while orbiting
		var pulse := 0.6 + 0.3 * sin(sparkle_time * 3.0)
		sparkle.modulate.a = pulse
	
	# Low health pulse effect on health bar
	if is_low_health:
		low_health_pulse_time += delta * 4.0  # Fast pulse
		var pulse_intensity := 0.5 + 0.5 * sin(low_health_pulse_time)
		# Pulse scale
		var scale_pulse := 1.0 + 0.08 * pulse_intensity
		health_bar.scale = Vector2(scale_pulse, scale_pulse)
		# Pulse color (red tint)
		var red_amount := 0.3 * pulse_intensity
		health_bar.modulate = Color(1.0 + red_amount, 1.0 - red_amount * 0.5, 1.0 - red_amount * 0.5, 1.0)
		# Pulse vignette opacity
		if red_flash.visible:
			var vignette_pulse := 0.15 + 0.1 * pulse_intensity
			red_flash.modulate.a = vignette_pulse
	
	# Stuck detection
	_update_stuck_detection(delta)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if gm.is_playing:
			if gm.is_paused:
				gm.resume_game()
			else:
				gm.pause_game()
	
	# Handle joystick touch input (only in touch mode)
	if audio and audio.is_touch_mode() and touch_joystick_base and touch_joystick_base.visible:
		_handle_joystick_input(event)

func _on_coins_changed(total: int) -> void:
	# Show popup for new coins
	var added := total - last_coin_count
	
	# Skip popup for combo bonus coins (they have their own cyan popup)
	if skip_combo_popup > 0:
		added -= skip_combo_popup
		skip_combo_popup = 0
	
	if added > 0 and coin_icon_texture:
		show_pickup_popup(added, coin_icon_texture)
		# Sparkle burst animation
		if sparkle:
			# Kill existing tween to prevent stacking
			if sparkle_tween:
				sparkle_tween.kill()
			sparkle_tween = create_tween()
			sparkle_tween.set_parallel(true)
			sparkle_tween.tween_property(sparkle, "modulate:a", 1.0, 0.05)
			sparkle_tween.tween_property(sparkle, "scale", Vector2(1.5, 1.5), 0.1)
			sparkle_tween.tween_property(sparkle, "rotation", TAU, 0.4)
			sparkle_tween.set_parallel(false)
			sparkle_tween.tween_property(sparkle, "scale", Vector2.ONE, 0.2)
			sparkle_tween.tween_property(sparkle, "modulate:a", 0.6, 0.3)
			sparkle_tween.tween_property(sparkle, "rotation", 0.0, 0.0)
	last_coin_count = total
	
	coins_label.text = format_number(total)
	
	# Juice animation
	var tween := create_tween()
	tween.tween_property(coins_label, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(coins_label, "scale", Vector2.ONE, 0.1)

func _on_distance_changed(dist: float) -> void:
	distance_label.text = gm.get_formatted_distance()
	
	# Update multiplier: 0-999m = 1x, 1000-1999m = 2x, etc.
	var new_multiplier := int(dist / 1000.0) + 1
	if new_multiplier != current_multiplier:
		current_multiplier = new_multiplier
		gm.coin_multiplier = current_multiplier
		_update_multiplier_display(true)
	
func _update_multiplier_display(animate: bool = false) -> void:
	if not multiplier_label:
		return
	multiplier_label.text = "x" + str(current_multiplier)
	
	if animate and multiplier_panel:
		# Kill existing tween
		if multiplier_tween:
			multiplier_tween.kill()
		
		# Flash and scale animation for multiplier increase
		multiplier_tween = create_tween()
		multiplier_tween.set_parallel(true)
		multiplier_tween.tween_property(multiplier_panel, "scale", Vector2(1.4, 1.4), 0.15).set_ease(Tween.EASE_OUT)
		multiplier_tween.tween_property(multiplier_panel, "modulate", Color(1.5, 1.2, 0.5, 1.0), 0.15)
		multiplier_tween.set_parallel(false)
		multiplier_tween.tween_property(multiplier_panel, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_IN_OUT)
		multiplier_tween.tween_property(multiplier_panel, "modulate", Color.WHITE, 0.3)

func _on_time_changed(time: float) -> void:
	timer_label.text = gm.format_time_static(time)

func _on_game_paused(is_paused: bool) -> void:
	pause_menu.visible = is_paused
	# Disable sparkle animation processing when paused to save CPU
	set_process(!is_paused)

func _on_health_changed(health: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	health_label.text = "%d/%d" % [health, max_health]
	
	# Check for low health state
	var health_ratio := float(health) / float(max_health) if max_health > 0 else 1.0
	var was_low_health := is_low_health
	is_low_health = health_ratio <= LOW_HEALTH_THRESHOLD and health > 0
	
	# Show/hide danger vignette for low health
	if is_low_health and not was_low_health:
		# Entering low health - show persistent vignette
		red_flash.visible = true
		red_flash.modulate.a = 0.15
	elif not is_low_health and was_low_health:
		# Exiting low health - hide vignette and reset health bar
		red_flash.visible = false
		health_bar.scale = Vector2.ONE
		health_bar.modulate = Color.WHITE
	
	# Juice animation - shrink and expand (only if not in low health pulse)
	if not is_low_health:
		var tween := create_tween()
		tween.tween_property(health_bar, "scale", Vector2(0.95, 0.8), 0.05)
		tween.tween_property(health_bar, "scale", Vector2.ONE, 0.1)

func _on_player_hit(damage: int) -> void:
	# Flash red overlay (bright flash that fades)
	red_flash.visible = true
	red_flash.modulate.a = 1.0
	
	var tween := create_tween()
	# If low health, fade to vignette level instead of hiding
	if is_low_health:
		tween.tween_property(red_flash, "modulate:a", 0.15, 0.3)
	else:
		tween.tween_property(red_flash, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): red_flash.visible = false)
	
	# Show damage popup
	show_damage_popup(damage)

func _on_settings_pressed() -> void:
	if audio:
		audio.play_button_click()
	gm.pause_game()

func _on_resume_pressed() -> void:
	if audio:
		audio.play_button_click()
	gm.resume_game()

func _on_restart_pressed() -> void:
	if audio:
		audio.play_button_click()
	gm.restart_game()

func _on_menu_pressed() -> void:
	if audio:
		audio.play_button_click()
	gm.go_to_menu()

func _on_music_slider_changed(value: float) -> void:
	if audio:
		audio.set_music_volume(value)

func _on_sfx_slider_changed(value: float) -> void:
	if audio:
		audio.set_sfx_volume(value)

func _on_popup_check_toggled(toggled_on: bool) -> void:
	if audio:
		audio.set_show_pickup_popup(toggled_on)

func _on_damage_check_toggled(toggled_on: bool) -> void:
	if audio:
		audio.set_show_damage_popup(toggled_on)

func _on_haptic_check_toggled(toggled_on: bool) -> void:
	if audio:
		audio.set_haptic_enabled(toggled_on)

# ========== Floating Popup System ==========

## Creates a floating popup with text and optional icon that animates off screen
## Direction: true = upward (heal), false = downward (default)
func _create_floating_popup(text: String, color: Color, outline_color: Color, icon_texture: Texture2D = null, float_up: bool = false) -> void:
	# Create popup container
	var popup := HBoxContainer.new()
	popup.add_theme_constant_override("separation", 12)
	
	# Create label - large, bold style with outline
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 116)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_outline_color", outline_color)
	label.add_theme_constant_override("shadow_offset_x", 4)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("outline_size", 6)
	popup.add_child(label)
	
	# Create icon if provided
	if icon_texture:
		var icon := TextureRect.new()
		icon.texture = icon_texture
		icon.custom_minimum_size = Vector2(104, 104)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = color
		popup.add_child(icon)
	
	# Position at player area
	var popup_container_width: float = popup_container.get_viewport_rect().size.x
	var popup_container_height: float = popup_container.get_viewport_rect().size.y
	var base_x: float = popup_container_width / 2.0
	var base_y: float = popup_container_height * 0.70
	
	# Random offset around spawn point
	var offset_x := randf_range(-120, 120)
	var offset_y := randf_range(-80, 80)
	popup.position = Vector2(base_x - 100 + offset_x, base_y + offset_y)
	popup.pivot_offset = Vector2(120, 60)
	popup_container.add_child(popup)
	
	# Animation direction
	var angle: float
	if float_up:
		angle = randf_range(PI * 1.3, PI * 1.7)  # Upward angles
	else:
		angle = randf_range(PI * 0.3, PI * 0.7)  # Downward angles
	
	var distance := popup_container_height - base_y + 100
	var duration := 1.0
	var target_offset := Vector2(cos(angle), sin(angle)) * distance
	var spin_amount := randf_range(-0.5, 0.5)
	
	# Animate: move off-screen, spin, and fade out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position", popup.position + target_offset, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(popup, "rotation", spin_amount, duration)
	tween.tween_property(popup, "modulate:a", 0.0, duration * 0.8).set_delay(duration * 0.2)
	tween.set_parallel(false)
	tween.tween_callback(popup.queue_free)

# ========== Floating Pickup Popup ==========

func show_pickup_popup(amount: int, icon_texture: Texture2D) -> void:
	if not audio or not audio.get_show_pickup_popup():
		return
	_create_floating_popup(
		"+" + format_number(amount),
		Color(1, 0.9, 0.3, 1),  # Bright gold
		Color(0.4, 0.2, 0, 1),  # Dark gold outline
		icon_texture
	)

# ========== Floating Combo Bonus Popup ==========

func show_combo_popup(amount: int, icon_texture: Texture2D) -> void:
	if not audio or not audio.get_show_pickup_popup():
		return
	_create_floating_popup(
		"+" + format_number(amount),
		Color(0.3, 1.0, 0.9, 1),  # Bright cyan
		Color(0, 0.3, 0.3, 1),    # Dark teal outline
		icon_texture
	)

# ========== Floating Damage Popup ==========

func show_damage_popup(amount: int) -> void:
	if not audio or not audio.get_show_damage_popup():
		return
	_create_floating_popup(
		"-" + str(amount),
		Color(1.0, 0.3, 0.3, 1),  # Bright red
		Color(0.5, 0, 0, 1),       # Dark red outline
		heart_icon_texture
	)

func show_heal_popup(amount: int) -> void:
	if not audio or not audio.get_show_damage_popup():
		return
	_create_floating_popup(
		"+" + str(amount) + "Hp",
		Color(0.3, 1.0, 0.5, 1),   # Bright green
		Color(0, 0.4, 0.15, 1),    # Dark green outline
		heart_icon_texture,
		true  # Float up
	)


func _on_player_healed(heal_amount: int) -> void:
	# Flash green overlay
	green_flash.visible = true
	green_flash.modulate.a = 0.8
	
	var tween := create_tween()
	tween.tween_property(green_flash, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): green_flash.visible = false)
	
	# Show heal popup
	show_heal_popup(heal_amount)


## Adjust top bar offset for mobile safe area (notch, status bar, etc.)
func _apply_safe_area_offset() -> void:
	# Get safe area rect from OS (accounts for notch, status bar, etc.)
	var safe_area: Rect2i = DisplayServer.get_display_safe_area()
	var screen_size: Vector2i = DisplayServer.screen_get_size()
	
	# Get viewport (design) size
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	
	# Calculate scale factor from screen to viewport coordinates
	var scale_y: float = viewport_size.y / float(screen_size.y) if screen_size.y > 0 else 1.0
	
	# Calculate top inset and scale to viewport coordinates
	var top_inset_screen: float = float(safe_area.position.y)
	var top_inset_viewport: float = top_inset_screen * scale_y
	
	# On desktop or if no safe area, use a minimum margin
	var min_top_offset: float = 20.0
	var safe_area_offset: float = maxf(top_inset_viewport, min_top_offset)
	
	# Apply offset to top bar (add to existing scene values)
	if top_bar:
		top_bar.offset_top += safe_area_offset
		top_bar.offset_bottom += safe_area_offset
	
	# Move TimerLabel together with TopBar
	if timer_label:
		timer_label.offset_top += safe_area_offset
		timer_label.offset_bottom += safe_area_offset
	
	# Move ComboLabel together with TimerLabel
	if combo_label:
		combo_label.offset_top += safe_area_offset
		combo_label.offset_bottom += safe_area_offset
	
	# Move QuestPanel together with TopBar
	if quest_panel:
		quest_panel.offset_top += safe_area_offset
		quest_panel.offset_bottom += safe_area_offset
	
	# Move BuffIndicator together with QuestPanel
	if buff_indicator:
		buff_indicator.offset_top += safe_area_offset
		buff_indicator.offset_bottom += safe_area_offset
	
	# Move SideBar down only if offset is large enough to risk overlap with ComboLabel
	# SideBar normally starts at anchor_top 0.22 which may overlap with ComboLabel when offset is applied
	if side_bar and safe_area_offset > min_top_offset:
		var extra_offset: float = safe_area_offset - min_top_offset
		side_bar.offset_top += extra_offset
		side_bar.offset_bottom += extra_offset

# ========== Combo UI ==========

func _on_object_destroyed(object_id: String, _object_name: String, base_coins: int) -> void:
	# Check if same object type as last destroyed
	if object_id == last_destroyed_id:
		current_combo += 1
	else:
		current_combo = 1
		last_destroyed_id = object_id
	
	# Apply combo bonus (combo >= 2 gives bonus coins)
	# Exponential growth: 2^(combo-1), capped at 256x
	# 1=1x, 2=2x, 3=4x, 4=8x, 5=16x, 6=32x, 7=64x, 8=128x, 9+=256x
	if current_combo >= 2:
		var combo_multiplier: int = mini(int(pow(2, current_combo - 1)), 256)  # Cap at 256x
		var combo_bonus: int = base_coins * (combo_multiplier - 1)  # Bonus = total - base
		var multiplied_bonus: int = combo_bonus * gm.coin_multiplier  # Apply same multiplier
		skip_combo_popup = multiplied_bonus  # Skip gold popup for this amount
		gm.add_coin(combo_bonus)  # This will be multiplied internally
		show_combo_popup(multiplied_bonus, coin_icon_texture)  # Show cyan popup for bonus
		_show_combo(combo_multiplier)

func _show_combo(combo: int) -> void:
	if not combo_label:
		return
	
	combo_label.text = "COMBO x%d" % combo
	combo_label.visible = true
	
	# Kill existing tween
	if combo_tween:
		combo_tween.kill()
	
	# Animate: pop in, stay, fade out
	combo_label.scale = Vector2(0.5, 0.5)
	combo_label.modulate = Color(1.5, 1.2, 0.8, 1.0)  # Bright flash
	
	combo_tween = create_tween()
	combo_tween.tween_property(combo_label, "scale", Vector2(1.2, 1.2), 0.1).set_ease(Tween.EASE_OUT)
	combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.1).set_ease(Tween.EASE_IN_OUT)
	combo_tween.tween_property(combo_label, "modulate", Color.WHITE, 0.2)
	combo_tween.tween_interval(1.5)  # Stay visible
	combo_tween.tween_property(combo_label, "modulate:a", 0.0, 0.3)
	combo_tween.tween_callback(func(): combo_label.visible = false; combo_label.modulate.a = 1.0)

# ========== Supercharge UI ==========

func _on_supercharge_changed(current: int, required: int) -> void:
	if not supercharge_bar:
		return
	
	supercharge_bar_max = required
	supercharge_bar_value = current
	_update_supercharge_bar_fill()
	
	# Update count label - during supercharge show remaining seconds
	if supercharge_count_label:
		if gm.is_supercharged:
			# Show remaining time during supercharge
			var remaining_secs := int(ceil(gm.supercharge_timer))
			supercharge_count_label.text = str(remaining_secs) + "\n━\n" + str(int(gm.supercharge_duration))
		else:
			# Cap displayed current at max (don't show values above required)
			var display_current := mini(current, required)
			supercharge_count_label.text = str(display_current) + "\n━\n" + str(required)
	
	# Check if ready
	var was_ready := supercharge_ready
	supercharge_ready = current >= required and not gm.is_supercharged
	
	# Update button appearance
	if supercharge_ready and not was_ready:
		_start_supercharge_glow()
	elif not supercharge_ready and was_ready:
		_stop_supercharge_glow()

func _on_supercharge_activated() -> void:
	supercharge_ready = false
	_stop_supercharge_glow()
	
	# Dim the button during supercharge
	if supercharge_button:
		supercharge_button.modulate = Color(0.5, 0.5, 0.5, 0.6)
	
	# Hide the count label during supercharge (numbers and line)
	if supercharge_count_label:
		supercharge_count_label.visible = false

func _on_supercharge_ended() -> void:
	# Show the count label again when supercharge ends
	if supercharge_count_label:
		supercharge_count_label.visible = true

func _on_game_started() -> void:
	# Reset multiplier display when game starts
	current_multiplier = 1
	_update_multiplier_display(false)
	
	# Reset combo
	current_combo = 0
	last_destroyed_id = ""
	if combo_label:
		combo_label.visible = false
	
	# Reset supercharge bar animation
	supercharge_display_value = 0.0
	
	# Reset stuck detection
	_reset_stuck_detection()
	
	# Start tutorial if needed
	if tutorial_manager and tutorial_manager.should_start_tutorial():
		tutorial_manager.start_tutorial()

func _on_supercharge_button_pressed() -> void:
	if gm and gm.is_supercharge_ready():
		gm.activate_supercharge()
		# Notify tutorial manager
		if tutorial_manager:
			tutorial_manager.on_supercharge_activated()
	# Release focus to prevent repeated activation
	if supercharge_button:
		supercharge_button.release_focus()

func _update_supercharge_bar_fill() -> void:
	if not supercharge_bar_fill or not supercharge_bar:
		return
	
	# Calculate target fill ratio (0 to 1)
	var target_ratio := 0.0
	if supercharge_bar_max > 0:
		target_ratio = clampf(supercharge_bar_value / supercharge_bar_max, 0.0, 1.0)
	
	# Smoothly animate to target value
	if supercharge_fill_tween:
		supercharge_fill_tween.kill()
	
	supercharge_fill_tween = create_tween()
	supercharge_fill_tween.tween_method(_set_supercharge_display, supercharge_display_value, target_ratio, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _set_supercharge_display(ratio: float) -> void:
	if not supercharge_bar_fill:
		return
	
	supercharge_display_value = ratio
	
	# Fill grows from bottom (anchor_top goes from 1.0 to 0.0)
	supercharge_bar_fill.anchor_top = 1.0 - ratio
	supercharge_bar_fill.offset_top = 6 if ratio >= 1.0 else 0  # Top padding only when full

func _start_supercharge_glow() -> void:
	if not supercharge_button:
		return
	
	# Stop any existing tweens
	_stop_supercharge_glow()
	
	# Set to bright state
	supercharge_button.modulate = Color(1.5, 1.2, 1.0, 1.0)
	
	# Create intense pulsing glow animation for button
	supercharge_glow_tween = create_tween()
	supercharge_glow_tween.set_loops()
	# Pulse between very bright orange/white and normal white - more intense glow
	supercharge_glow_tween.tween_property(supercharge_button, "modulate", Color(2.5, 1.5, 0.5, 1.0), 0.3)
	supercharge_glow_tween.tween_property(supercharge_button, "modulate", Color(1.5, 1.2, 1.0, 1.0), 0.3)
	
	# Also pulse the fill bar with glowing effect
	if supercharge_bar_fill:
		supercharge_bar_glow_tween = create_tween()
		supercharge_bar_glow_tween.set_loops()
		supercharge_bar_glow_tween.tween_property(supercharge_bar_fill, "modulate", Color(1.8, 1.4, 1.0, 1.0), 0.3)
		supercharge_bar_glow_tween.tween_property(supercharge_bar_fill, "modulate", Color(1.2, 1.0, 0.9, 1.0), 0.3)

func _stop_supercharge_glow() -> void:
	if supercharge_glow_tween:
		supercharge_glow_tween.kill()
		supercharge_glow_tween = null
	
	if supercharge_bar_glow_tween:
		supercharge_bar_glow_tween.kill()
		supercharge_bar_glow_tween = null
	
	if supercharge_button:
		supercharge_button.modulate = Color(0.5, 0.5, 0.5, 0.6)
	
	if supercharge_bar_fill:
		supercharge_bar_fill.modulate = Color(1.0, 1.0, 1.0, 1.0)

# ========== Touch Controls ==========

func _init_touch_controls() -> void:
	# Only initialize if AudioManager and touch controls are available
	if not audio or not touch_controls_container:
		return
	
	# Set visibility based on touch mode
	touch_controls_container.visible = audio.is_touch_mode()
	
	# Calculate joystick max distance from scene sizes
	if touch_joystick_base and touch_joystick_knob:
		joystick_max_distance = touch_joystick_base.size.x / 2.0 - touch_joystick_knob.size.x / 2.0

func _handle_joystick_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# Check if touch is within joystick area (with expanded hit area)
			var touch_pos := touch.position
			var joystick_rect := touch_joystick_base.get_global_rect()
			# Expand hit area for easier touch
			joystick_rect = joystick_rect.grow(40.0)
			
			if joystick_rect.has_point(touch_pos) and joystick_touch_index == -1:
				joystick_touch_index = touch.index
				_update_joystick_knob(touch_pos)
		else:
			# Touch released
			if touch.index == joystick_touch_index:
				joystick_touch_index = -1
				joystick_input = 0.0
				_reset_joystick_knob()
	
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == joystick_touch_index:
			_update_joystick_knob(drag.position)

func _update_joystick_knob(touch_pos: Vector2) -> void:
	if not touch_joystick_base or not touch_joystick_knob:
		return
	
	# Calculate joystick center dynamically from global rect
	var base_rect := touch_joystick_base.get_global_rect()
	joystick_center = base_rect.position + base_rect.size / 2.0
	
	# Calculate offset from joystick center
	var touch_offset := touch_pos - joystick_center
	var distance := touch_offset.length()
	
	# Clamp to max distance
	if distance > joystick_max_distance:
		touch_offset = touch_offset.normalized() * joystick_max_distance
	
	# Update knob position (relative to base)
	var base_size := touch_joystick_base.size
	var knob_size := touch_joystick_knob.size
	touch_joystick_knob.position = touch_offset + (base_size - knob_size) / 2.0
	
	# Calculate joystick input (-1 to 1) - only X axis for left/right (0.9 = 10% less sensitive)
	joystick_input = clampf(touch_offset.x / joystick_max_distance, -1.0, 1.0) * 0.9

func _reset_joystick_knob() -> void:
	if not touch_joystick_base or not touch_joystick_knob:
		return
	
	# Animate knob back to center
	var base_size := touch_joystick_base.size
	var knob_size := touch_joystick_knob.size
	var center_pos := (base_size - knob_size) / 2.0
	
	var tween := create_tween()
	tween.tween_property(touch_joystick_knob, "position", center_pos, 0.1).set_ease(Tween.EASE_OUT)

func _on_jump_button_down() -> void:
	# Emit signal immediately when button is pressed - same as screen tap in gyro mode
	jump_pressed.emit()
	# Visual feedback
	if touch_jump_button:
		touch_jump_button.modulate = Color(1.3, 1.3, 1.3, 1.0)

func _on_jump_button_up() -> void:
	# Reset visual only
	if touch_jump_button:
		touch_jump_button.modulate = Color(1.0, 1.0, 1.0, 0.85)

## Get the current joystick X input (-1 = left, 0 = center, 1 = right)
func get_joystick_input() -> float:
	return joystick_input

## Update touch controls visibility based on control mode setting
func update_touch_controls_visibility() -> void:
	if touch_controls_container and audio:
		touch_controls_container.visible = audio.is_touch_mode()


## Check if a touch position is over any interactive UI element (for blocking jump in gyro mode)
func is_touch_on_interactive_ui(touch_pos: Vector2) -> bool:
	# Check supercharge button
	if supercharge_button and supercharge_button.visible:
		if supercharge_button.get_global_rect().has_point(touch_pos):
			return true
	
	# Check settings button
	if settings_button and settings_button.visible:
		if settings_button.get_global_rect().has_point(touch_pos):
			return true
	
	# Check inventory slots
	var inv_slots := ["SideBar/InvSlot1/Border/ItemButton", "SideBar/InvSlot2/Border/ItemButton", "SideBar/InvSlot3/Border/ItemButton"]
	for slot_path in inv_slots:
		var slot_btn: TextureButton = get_node_or_null(slot_path) as TextureButton
		if slot_btn and slot_btn.visible:
			if slot_btn.get_global_rect().has_point(touch_pos):
				return true
	
	# Check touch jump button (only relevant when visible in touch mode)
	if touch_jump_button and touch_jump_button.visible:
		if touch_jump_button.get_global_rect().has_point(touch_pos):
			return true
	
	# Check pause menu (if visible, block all touches)
	if pause_menu and pause_menu.visible:
		return true
	
	return false


# ========== Quest Display ==========

func _connect_quest_signals() -> void:
	quest_manager = get_node_or_null("/root/QuestManager")
	
	if quest_manager:
		if not quest_manager.quest_progress_updated.is_connected(_on_quest_progress_updated):
			quest_manager.quest_progress_updated.connect(_on_quest_progress_updated)
		if not quest_manager.quest_completed.is_connected(_on_quest_completed):
			quest_manager.quest_completed.connect(_on_quest_completed)
		if not quest_manager.active_quest_changed.is_connected(_on_active_quest_changed):
			quest_manager.active_quest_changed.connect(_on_active_quest_changed)
		
		# Initial state
		_update_quest_display()


# ========== Tutorial System ==========

func _init_tutorial() -> void:
	const TutorialManager := preload("res://scripts/ui/tutorial_manager.gd")
	tutorial_manager = TutorialManager.new()
	tutorial_manager.name = "TutorialManager"
	add_child(tutorial_manager)
	tutorial_manager.initialize(self)
	
	# Connect inventory slot_clicked to notify tutorial
	if inventory_ui and inventory_ui.has_signal("slot_clicked"):
		inventory_ui.slot_clicked.connect(_on_inventory_slot_clicked)
	
	# If game is already running (signal was emitted before init), start tutorial now
	if gm and gm.is_playing and tutorial_manager.should_start_tutorial():
		tutorial_manager.start_tutorial()


func _on_inventory_slot_clicked(_slot_index: int) -> void:
	# Notify tutorial manager that item was used
	if tutorial_manager:
		tutorial_manager.on_item_used()


func _on_active_quest_changed(_quest: RefCounted) -> void:
	_update_quest_display()


func _on_quest_progress_updated(quest_id: String, current: int, target: int) -> void:
	if quest_id == _current_quest_id:
		_update_quest_progress(current, target)


func _on_quest_completed(quest_id: String) -> void:
	if quest_id == _current_quest_id:
		_show_quest_completed()


func _update_quest_display() -> void:
	if not quest_manager or not quest_panel:
		return
	
	var quest: RefCounted = quest_manager.get_active_quest()
	
	if not quest:
		_current_quest_id = ""
		quest_panel.visible = false
		return
	
	_current_quest_id = quest.id
	
	# Check if already completed - hide panel
	if quest_manager.is_quest_completed(quest.id):
		quest_panel.visible = false
		return
	
	# Update description
	if quest_description:
		quest_description.text = quest.short_description
	
	# Update progress
	var progress: int = quest_manager.get_display_progress(quest)
	_update_quest_progress(progress, quest.target_value)
	
	# Reset to normal styling
	if quest_progress_bar:
		var bar_fill := quest_progress_bar.get_theme_stylebox("fill").duplicate()
		bar_fill.bg_color = COLOR_QUEST_PROGRESS
		quest_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	
	if quest_progress_label:
		quest_progress_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 1))
	
	quest_panel.visible = true


func _update_quest_progress(current: int, target: int) -> void:
	if quest_progress_bar:
		quest_progress_bar.max_value = target
		quest_progress_bar.value = mini(current, target)
	
	if quest_progress_label:
		quest_progress_label.text = "%s/%s" % [format_number(current), format_number(target)]


func _show_quest_completed() -> void:
	if quest_description:
		quest_description.text = "Quest Complete!"
	
	if quest_progress_bar:
		quest_progress_bar.value = quest_progress_bar.max_value
		var bar_fill := quest_progress_bar.get_theme_stylebox("fill").duplicate()
		bar_fill.bg_color = COLOR_QUEST_COMPLETED
		quest_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	
	if quest_progress_label:
		quest_progress_label.text = "Done!"
		quest_progress_label.add_theme_color_override("font_color", COLOR_QUEST_COMPLETED)
	
	quest_panel.visible = true
	
	# Hide after short delay
	await get_tree().create_timer(2.0).timeout
	if quest_panel:
		quest_panel.visible = false


# ========== Stuck Detection ==========

func _reset_stuck_detection() -> void:
	stuck_timer = 0.0
	stuck_countdown_timer = STUCK_DEATH_TIME
	is_stuck_warning_shown = false
	stuck_grace_period = STUCK_GRACE_PERIOD  # Reset grace period
	if stuck_overlay:
		stuck_overlay.visible = false
	if stuck_label:
		stuck_label.modulate = Color(1.0, 1.0, 1.0)  # Reset pulse color
	if gm and gm.player:
		stuck_checkpoint_z = gm.player.global_position.z


func _update_stuck_detection(delta: float) -> void:
	# Only run during active gameplay
	if not gm or not gm.is_playing or gm.is_paused or gm.health <= 0:
		if stuck_overlay and stuck_overlay.visible:
			stuck_overlay.visible = false
		return
	
	if not gm.player:
		return
	
	# Grace period at game start
	if stuck_grace_period > 0.0:
		stuck_grace_period -= delta
		stuck_checkpoint_z = gm.player.global_position.z
		return
	
	var current_z: float = gm.player.global_position.z
	var z_distance: float = abs(current_z - stuck_checkpoint_z)
	
	# Check if player moved enough from checkpoint
	if z_distance > STUCK_MIN_MOVEMENT:
		# Player moved - reset timers and update checkpoint
		stuck_timer = 0.0
		stuck_checkpoint_z = current_z
		if is_stuck_warning_shown:
			is_stuck_warning_shown = false
			if stuck_overlay:
				stuck_overlay.visible = false
			if stuck_label:
				stuck_label.modulate = Color(1.0, 1.0, 1.0)
		return
	
	# Player not moving enough - accumulate time
	stuck_timer += delta
	
	if not is_stuck_warning_shown:
		if stuck_timer >= STUCK_WARNING_TIME:
			# Show warning
			is_stuck_warning_shown = true
			stuck_countdown_timer = STUCK_DEATH_TIME
			if stuck_overlay:
				stuck_overlay.visible = true
				_pulse_warning()
	else:
		# Warning is shown - countdown to death
		stuck_countdown_timer -= delta
		
		# Update UI
		if stuck_progress_bar:
			stuck_progress_bar.value = (stuck_countdown_timer / STUCK_DEATH_TIME) * 100.0
		
		if stuck_countdown_label:
			stuck_countdown_label.text = str(ceili(stuck_countdown_timer))
		
		# Pulse effect on low time
		if stuck_countdown_timer <= 3.0 and stuck_label:
			var pulse := 0.7 + 0.3 * sin(stuck_countdown_timer * 10.0)
			stuck_label.modulate = Color(1.0, pulse, pulse)
		
		# Death!
		if stuck_countdown_timer <= 0.0:
			_kill_player_stuck()


func _pulse_warning() -> void:
	if not stuck_label:
		return
	
	var tween := create_tween()
	tween.set_loops(3)
	tween.tween_property(stuck_label, "scale", Vector2(1.1, 1.1), 0.15).set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(stuck_label, "scale", Vector2(1.0, 1.0), 0.15)


func _kill_player_stuck() -> void:
	is_stuck_warning_shown = false
	if stuck_overlay:
		stuck_overlay.visible = false
	
	# Kill player by taking exactly their remaining health
	if gm:
		gm.take_damage(gm.health)

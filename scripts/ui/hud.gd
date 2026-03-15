extends CanvasLayer
## HUD - Displays coins, distance, health, and handles pause

signal jump_pressed  # Emitted when touch jump button is pressed

@onready var top_bar: PanelContainer = $TopBar
@onready var coins_label: Label = $TopBar/MarginContainer/HBoxContainer/CoinsContainer/CoinsLabel
@onready var distance_label: Label = $TopBar/MarginContainer/HBoxContainer/DistanceContainer/DistanceLabel
@onready var health_bar: ProgressBar = $TopBar/MarginContainer/HBoxContainer/HealthContainer/HealthBar
@onready var health_label: Label = $TopBar/MarginContainer/HBoxContainer/HealthContainer/HealthBar/HealthLabel
@onready var red_flash: ColorRect = $RedFlash
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
@onready var combo_panel: Control = $ComboPanel
@onready var combo_label: Label = $ComboPanel/ComboLabel
var combo_tween: Tween
var current_combo: int = 0
var last_destroyed_id: String = ""
var skip_combo_popup: int = 0  # Amount to skip from regular popup (for combo bonuses)

# Low health effects
var low_health_pulse_time: float = 0.0
var is_low_health: bool = false
const LOW_HEALTH_THRESHOLD: float = 0.3  # 30% health

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

# ========== Floating Pickup Popup ==========

func show_pickup_popup(amount: int, icon_texture: Texture2D) -> void:
	if not audio or not audio.get_show_pickup_popup():
		return
	
	# Create popup container
	var popup := HBoxContainer.new()
	popup.add_theme_constant_override("separation", 12)
	
	# Create +N label - large, bold style with outline
	var label := Label.new()
	label.text = "+" + format_number(amount)
	label.add_theme_font_size_override("font_size", 116)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))  # Bright gold
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0.4, 0.2, 0, 1))  # Dark outline
	label.add_theme_constant_override("shadow_offset_x", 4)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("outline_size", 6)
	popup.add_child(label)
	
	# Create icon - larger
	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(104, 104)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 0.9, 0.3, 1)  # Bright gold tint
	popup.add_child(icon)
	
	# Position at player area - use design resolution (720x1280 with stretch)
	# Center horizontally, 70% from top (30% from bottom)
	var popup_container_width: float = popup_container.get_viewport_rect().size.x
	var popup_container_height: float = popup_container.get_viewport_rect().size.y
	var base_x: float = popup_container_width / 2.0
	var base_y: float = popup_container_height * 0.70
	
	# Larger random offset around spawn point for more spread
	var offset_x := randf_range(-120, 120)
	var offset_y := randf_range(-80, 80)
	# Center the popup (estimate ~200px width for "+1" + icon at 2x size)
	popup.position = Vector2(base_x - 100 + offset_x, base_y + offset_y)
	popup.pivot_offset = Vector2(120, 60)  # Center pivot for rotation
	popup_container.add_child(popup)  # Add to container so it's behind menus
	
	# Fall downward and off-screen
	var angle := randf_range(PI * 0.3, PI * 0.7)  # Downward angles
	var distance := popup_container_height - base_y + 100  # Enough to exit screen at bottom
	var duration := 1.0  # Animation duration
	var target_offset := Vector2(cos(angle), sin(angle)) * distance
	
	# Random spin (mild rotation)
	var spin_amount := randf_range(-0.5, 0.5)
	
	# Animate: fall down off-screen, spin, and fade out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position", popup.position + target_offset, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(popup, "rotation", spin_amount, duration)
	tween.tween_property(popup, "modulate:a", 0.0, duration * 0.8).set_delay(duration * 0.2)
	tween.set_parallel(false)
	tween.tween_callback(popup.queue_free)

# ========== Floating Combo Bonus Popup ==========

func show_combo_popup(amount: int, icon_texture: Texture2D) -> void:
	if not audio or not audio.get_show_pickup_popup():
		return
	
	# Create popup container
	var popup := HBoxContainer.new()
	popup.add_theme_constant_override("separation", 16)
	
	# Create +N label - large, bold style with outline (cyan/turquoise for combo bonus)
	var label := Label.new()
	label.text = "+" + format_number(amount)
	label.add_theme_font_size_override("font_size", 116)
	label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.9, 1))  # Bright cyan/turquoise
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0.3, 0.3, 1))  # Dark teal outline
	label.add_theme_constant_override("shadow_offset_x", 4)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("outline_size", 6)
	popup.add_child(label)
	
	# Create icon - larger
	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(104, 104)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(0.3, 1.0, 0.9, 1)  # Cyan tint to match
	popup.add_child(icon)
	
	# Position at player area - use design resolution (720x1280 with stretch)
	# Center horizontally, 70% from top (30% from bottom)
	var popup_container_width: float = popup_container.get_viewport_rect().size.x
	var popup_container_height: float = popup_container.get_viewport_rect().size.y
	var base_x: float = popup_container_width / 2.0
	var base_y: float = popup_container_height * 0.70
	
	# Larger random offset around spawn point for more spread
	var offset_x := randf_range(-120, 120)
	var offset_y := randf_range(-80, 80)
	# Center the combo popup (2x size = ~200px width)
	popup.position = Vector2(base_x - 100 + offset_x, base_y + offset_y)
	popup.pivot_offset = Vector2(120, 60)  # Center pivot for rotation
	popup_container.add_child(popup)  # Add to container so it's behind menus
	
	# Fall downward and off-screen
	var angle := randf_range(PI * 0.3, PI * 0.7)  # Downward angles
	var distance := popup_container_height - base_y + 100  # Enough to exit screen at bottom
	var duration := 1.0  # Animation duration
	var target_offset := Vector2(cos(angle), sin(angle)) * distance
	
	# Random spin (mild rotation)
	var spin_amount := randf_range(-0.5, 0.5)
	
	# Animate: fall down off-screen, spin, and fade out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position", popup.position + target_offset, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(popup, "rotation", spin_amount, duration)
	tween.tween_property(popup, "modulate:a", 0.0, duration * 0.8).set_delay(duration * 0.2)
	tween.set_parallel(false)
	tween.tween_callback(popup.queue_free)

# ========== Floating Damage Popup ==========

func show_damage_popup(amount: int) -> void:
	if not audio or not audio.get_show_damage_popup():
		return
	
	# Create popup container
	var popup := HBoxContainer.new()
	popup.add_theme_constant_override("separation", 12)
	
	# Create -N label - large, bold style with outline (red theme)
	var label := Label.new()
	label.text = "-" + str(amount)
	label.add_theme_font_size_override("font_size", 116)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1))  # Bright red
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0.5, 0, 0, 1))  # Dark red outline
	label.add_theme_constant_override("shadow_offset_x", 4)
	label.add_theme_constant_override("shadow_offset_y", 4)
	label.add_theme_constant_override("outline_size", 6)
	popup.add_child(label)
	
	# Create heart icon
	var icon := TextureRect.new()
	if heart_icon_texture:
		icon.texture = heart_icon_texture
		icon.custom_minimum_size = Vector2(96, 96)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(1.0, 0.3, 0.3, 1)  # Red tint
		popup.add_child(icon)
	
	# Position at player area - use design resolution (720x1280 with stretch)
	# Center horizontally, 70% from top (30% from bottom)
	var popup_container_width: float = popup_container.get_viewport_rect().size.x
	var popup_container_height: float = popup_container.get_viewport_rect().size.y
	var base_x: float = popup_container_width / 2.0
	var base_y: float = popup_container_height * 0.70
	
	# Larger random offset around spawn point for more spread
	var offset_x := randf_range(-120, 120)
	var offset_y := randf_range(-80, 80)
	# Center the damage popup (2x size = ~180px width)
	popup.position = Vector2(base_x - 90 + offset_x, base_y + offset_y)
	popup.pivot_offset = Vector2(100, 50)  # Center pivot for rotation
	popup_container.add_child(popup)  # Add to container so it's behind menus
	
	# Fall downward and off-screen
	var angle := randf_range(PI * 0.3, PI * 0.7)  # Downward angles
	var distance := popup_container_height - base_y + 100  # Enough to exit screen at bottom
	var duration := 1.0  # Animation duration
	var target_offset := Vector2(cos(angle), sin(angle)) * distance
	
	# Random spin (mild rotation)
	var spin_amount := randf_range(-0.5, 0.5)
	
	# Animate: fall down off-screen, spin, and fade out
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position", popup.position + target_offset, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(popup, "rotation", spin_amount, duration)
	tween.tween_property(popup, "modulate:a", 0.0, duration * 0.8).set_delay(duration * 0.2)
	tween.set_parallel(false)
	tween.tween_callback(popup.queue_free)


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
	
	# Move ComboPanel together with TimerLabel
	if combo_panel:
		combo_panel.offset_top += safe_area_offset
		combo_panel.offset_bottom += safe_area_offset

# ========== Combo UI ==========

func _on_object_destroyed(object_id: String, _object_name: String, base_coins: int) -> void:
	# Check if same object type as last destroyed
	if object_id == last_destroyed_id:
		current_combo += 1
	else:
		current_combo = 1
		last_destroyed_id = object_id
	
	# Apply combo bonus (combo >= 2 gives bonus coins)
	# Slower growth: doubles every 2 combos. 2x, 4x, 8x... max 128x at combo 14+
	if current_combo >= 2:
		var tier: int = (current_combo - 2) / 2  # 0 for combo 2-3, 1 for 4-5, etc.
		var combo_multiplier: int = mini(int(pow(2, tier + 1)), 128)  # Cap at 128x
		var combo_bonus: int = base_coins * (combo_multiplier - 1)  # Bonus = total - base
		var multiplied_bonus: int = combo_bonus * gm.coin_multiplier  # Apply same multiplier
		skip_combo_popup = multiplied_bonus  # Skip gold popup for this amount
		gm.add_coin(combo_bonus)  # This will be multiplied internally
		show_combo_popup(multiplied_bonus, coin_icon_texture)  # Show cyan popup for bonus
		_show_combo(combo_multiplier)

func _show_combo(combo: int) -> void:
	if not combo_panel or not combo_label:
		return
	
	combo_label.text = "COMBO x%d" % combo
	combo_panel.visible = true
	
	# Kill existing tween
	if combo_tween:
		combo_tween.kill()
	
	# Animate: pop in, stay, fade out
	combo_panel.scale = Vector2(0.5, 0.5)
	combo_panel.modulate = Color(1.5, 1.2, 0.8, 1.0)  # Bright flash
	
	combo_tween = create_tween()
	combo_tween.tween_property(combo_panel, "scale", Vector2(1.2, 1.2), 0.1).set_ease(Tween.EASE_OUT)
	combo_tween.tween_property(combo_panel, "scale", Vector2.ONE, 0.1).set_ease(Tween.EASE_IN_OUT)
	combo_tween.tween_property(combo_panel, "modulate", Color.WHITE, 0.2)
	combo_tween.tween_interval(1.5)  # Stay visible
	combo_tween.tween_property(combo_panel, "modulate:a", 0.0, 0.3)
	combo_tween.tween_callback(func(): combo_panel.visible = false; combo_panel.modulate.a = 1.0)

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
	if combo_panel:
		combo_panel.visible = false
	
	# Reset supercharge bar animation
	supercharge_display_value = 0.0

func _on_supercharge_button_pressed() -> void:
	if gm and gm.is_supercharge_ready():
		gm.activate_supercharge()
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

extends CanvasLayer
## HUD - Displays coins, distance, health, and handles pause

@onready var top_bar: PanelContainer = $TopBar
@onready var coins_label: Label = $TopBar/MarginContainer/HBoxContainer/CoinsContainer/CoinsLabel
@onready var distance_label: Label = $TopBar/MarginContainer/HBoxContainer/DistanceContainer/DistanceLabel
@onready var health_bar: ProgressBar = $TopBar/MarginContainer/HBoxContainer/HealthContainer/HealthBar
@onready var health_label: Label = $TopBar/MarginContainer/HBoxContainer/HealthContainer/HealthBar/HealthLabel
@onready var red_flash: ColorRect = $RedFlash
@onready var pause_menu: Control = $PauseMenu
@onready var music_slider: HSlider = $PauseMenu/PanelContainer/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $PauseMenu/PanelContainer/VBoxContainer/SFXSlider
@onready var popup_check: CheckButton = $PauseMenu/PanelContainer/VBoxContainer/PopupCheck
@onready var damage_check: CheckButton = $PauseMenu/PanelContainer/VBoxContainer/DamageCheck
@onready var haptic_check: CheckButton = $PauseMenu/PanelContainer/VBoxContainer/HapticCheck
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

# Supercharge UI
var supercharge_panel: PanelContainer
var supercharge_container: VBoxContainer
var supercharge_bar: ProgressBar
var supercharge_button: TextureButton
var supercharge_glow_tween: Tween
var supercharge_bar_glow_tween: Tween
var supercharge_ready: bool = false

func _ready() -> void:
	gm = get_node("/root/GameManager")
	audio = get_node("/root/AudioManager")
	coin_icon_texture = load("res://assets/icons/coin.svg")
	heart_icon_texture = load("res://assets/icons/heart.svg")  # Cache heart icon
	gm.coins_changed.connect(_on_coins_changed)
	gm.distance_changed.connect(_on_distance_changed)
	gm.game_paused.connect(_on_game_paused)
	gm.health_changed.connect(_on_health_changed)
	gm.player_hit.connect(_on_player_hit)
	gm.time_changed.connect(_on_time_changed)
	gm.supercharge_changed.connect(_on_supercharge_changed)
	gm.supercharge_activated.connect(_on_supercharge_activated)
	gm.supercharge_ended.connect(_on_supercharge_ended)
	
	# Create supercharge UI
	_create_supercharge_ui()
	
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

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if gm.is_playing:
			if gm.is_paused:
				gm.resume_game()
			else:
				gm.pause_game()

func _on_coins_changed(total: int) -> void:
	# Show popup for new coins
	var added := total - last_coin_count
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
	
	coins_label.text = str(total)
	
	# Juice animation
	var tween := create_tween()
	tween.tween_property(coins_label, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(coins_label, "scale", Vector2.ONE, 0.1)

func _on_distance_changed(_dist: float) -> void:
	distance_label.text = gm.get_formatted_distance()

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
	
	# Juice animation - shrink and expand
	var tween := create_tween()
	tween.tween_property(health_bar, "scale", Vector2(0.95, 0.8), 0.05)
	tween.tween_property(health_bar, "scale", Vector2.ONE, 0.1)

func _on_player_hit(damage: int) -> void:
	# Flash red overlay
	red_flash.visible = true
	red_flash.modulate.a = 1.0
	
	var tween := create_tween()
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
	label.text = "+" + str(amount)
	label.add_theme_font_size_override("font_size", 58)
	label.add_theme_color_override("font_color", Color(1, 0.9, 0.3, 1))  # Bright gold
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0.4, 0.2, 0, 1))  # Dark outline
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("outline_size", 4)
	popup.add_child(label)
	
	# Create icon - larger
	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(52, 52)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 0.9, 0.3, 1)  # Bright gold tint
	popup.add_child(icon)
	
	# Position at player area - use design resolution (720x1280 with stretch)
	# Center horizontally, 67% from top vertically
	var design_width: float = 720.0
	var design_height: float = 1280.0
	var base_x: float = design_width / 2.0
	var base_y: float = design_height * 0.67
	
	# Larger random offset around spawn point for more spread
	var offset_x := randf_range(-120, 120)
	var offset_y := randf_range(-80, 80)
	# Center the popup (estimate ~100px width for "+1" + icon)
	popup.position = Vector2(base_x - 50 + offset_x, base_y + offset_y)
	popup.pivot_offset = Vector2(60, 30)  # Center pivot for rotation
	popup_container.add_child(popup)  # Add to container so it's behind menus
	
	# Fall downward and off-screen
	var angle := randf_range(PI * 0.3, PI * 0.7)  # Downward angles
	var distance := design_height - base_y + 100  # Enough to exit screen at bottom
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
	popup.add_theme_constant_override("separation", 8)
	
	# Create -N label - large, bold style with outline (red theme)
	var label := Label.new()
	label.text = "-" + str(amount)
	label.add_theme_font_size_override("font_size", 58)
	label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1))  # Bright red
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0.5, 0, 0, 1))  # Dark red outline
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	label.add_theme_constant_override("outline_size", 4)
	popup.add_child(label)
	
	# Create heart icon
	var icon := TextureRect.new()
	if heart_icon_texture:
		icon.texture = heart_icon_texture
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = Color(1.0, 0.3, 0.3, 1)  # Red tint
		popup.add_child(icon)
	
	# Position at player area - use design resolution (720x1280 with stretch)
	# Center horizontally, 67% from top vertically
	var design_width: float = 720.0
	var design_height: float = 1280.0
	var base_x: float = design_width / 2.0
	var base_y: float = design_height * 0.67
	
	# Larger random offset around spawn point for more spread
	var offset_x := randf_range(-120, 120)
	var offset_y := randf_range(-80, 80)
	# Center the popup
	popup.position = Vector2(base_x - 50 + offset_x, base_y + offset_y)
	popup.pivot_offset = Vector2(60, 30)  # Center pivot for rotation
	popup_container.add_child(popup)  # Add to container so it's behind menus
	
	# Fall downward and off-screen
	var angle := randf_range(PI * 0.3, PI * 0.7)  # Downward angles
	var distance := design_height - base_y + 100  # Enough to exit screen at bottom
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
	var actual_top_offset: float = maxf(top_inset_viewport, min_top_offset)
	
	# Apply offset to top bar
	if top_bar:
		top_bar.offset_top = actual_top_offset
		# Adjust bottom offset to maintain panel height (~64px)
		top_bar.offset_bottom = actual_top_offset + 64.0
	
	# Move TimerLabel together with TopBar (26px gap below TopBar)
	if timer_label:
		timer_label.offset_top = actual_top_offset + 64.0 + 26.0
		timer_label.offset_bottom = timer_label.offset_top + 32.0

# ========== Supercharge UI ==========

func _create_supercharge_ui() -> void:
	# Create panel container as background
	supercharge_panel = PanelContainer.new()
	supercharge_panel.name = "SuperchargePanel"
	supercharge_panel.anchor_left = 1.0
	supercharge_panel.anchor_right = 1.0
	supercharge_panel.anchor_top = 0.5
	supercharge_panel.anchor_bottom = 0.5
	supercharge_panel.offset_left = -80
	supercharge_panel.offset_right = -10
	supercharge_panel.offset_top = -140
	supercharge_panel.offset_bottom = 140
	# Panel captures mouse/touch to prevent falling through to game
	supercharge_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Style the panel with rounded transparent background
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.5)  # Semi-transparent black
	panel_style.corner_radius_top_left = 20
	panel_style.corner_radius_top_right = 20
	panel_style.corner_radius_bottom_left = 20
	panel_style.corner_radius_bottom_right = 20
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.4, 0.4, 0.7)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 10
	panel_style.content_margin_bottom = 10
	supercharge_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(supercharge_panel)
	
	# Create container inside panel
	supercharge_container = VBoxContainer.new()
	supercharge_container.name = "SuperchargeContainer"
	supercharge_container.add_theme_constant_override("separation", 12)
	supercharge_container.alignment = BoxContainer.ALIGNMENT_CENTER
	supercharge_panel.add_child(supercharge_container)
	
	# Create bar container with background texture
	var bar_container := Control.new()
	bar_container.name = "BarContainer"
	bar_container.custom_minimum_size = Vector2(44, 160)
	supercharge_container.add_child(bar_container)
	
	# Add background texture from SVG
	var bar_bg := TextureRect.new()
	bar_bg.name = "BarBackground"
	var bg_texture: Texture2D = load("res://assets/icons/super_charge_bar_bg.svg")
	if bg_texture:
		bar_bg.texture = bg_texture
	bar_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar_bg.stretch_mode = TextureRect.STRETCH_SCALE
	bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_container.add_child(bar_bg)
	
	# Create vertical progress bar
	supercharge_bar = ProgressBar.new()
	supercharge_bar.name = "SuperchargeBar"
	supercharge_bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	supercharge_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	supercharge_bar.show_percentage = false
	supercharge_bar.max_value = 100.0
	supercharge_bar.value = 0.0
	
	# Style the bar with transparent background (SVG provides the visual bg)
	var bar_style := StyleBoxFlat.new()
	bar_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)  # Transparent - SVG bg shows through
	bar_style.corner_radius_top_left = 14
	bar_style.corner_radius_top_right = 14
	bar_style.corner_radius_bottom_left = 14
	bar_style.corner_radius_bottom_right = 14
	supercharge_bar.add_theme_stylebox_override("background", bar_style)
	
	# Fill style with vibrant orange-red gradient
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(1.0, 0.4, 0.1, 1.0)  # Bright orange
	fill_style.corner_radius_top_left = 12
	fill_style.corner_radius_top_right = 12
	fill_style.corner_radius_bottom_left = 12
	fill_style.corner_radius_bottom_right = 12
	# Add inner glow effect
	fill_style.shadow_color = Color(1.0, 0.3, 0.0, 0.5)
	fill_style.shadow_size = 8
	supercharge_bar.add_theme_stylebox_override("fill", fill_style)
	
	bar_container.add_child(supercharge_bar)
	
	# Create CenterContainer to center the circular button
	var button_center := CenterContainer.new()
	button_center.name = "ButtonCenter"
	button_center.custom_minimum_size = Vector2(50, 50)
	supercharge_container.add_child(button_center)
	
	# Create circular button background with glow
	var button_bg := PanelContainer.new()
	button_bg.name = "ButtonBackground"
	button_bg.custom_minimum_size = Vector2(52, 52)
	
	# Style for circular button background with fire theme
	var button_bg_style := StyleBoxFlat.new()
	button_bg_style.bg_color = Color(0.12, 0.05, 0.02, 0.98)
	button_bg_style.corner_radius_top_left = 26
	button_bg_style.corner_radius_top_right = 26
	button_bg_style.corner_radius_bottom_left = 26
	button_bg_style.corner_radius_bottom_right = 26
	button_bg_style.border_width_left = 2
	button_bg_style.border_width_right = 2
	button_bg_style.border_width_top = 2
	button_bg_style.border_width_bottom = 2
	button_bg_style.border_color = Color(0.6, 0.25, 0.1, 0.9)
	button_bg_style.shadow_color = Color(1.0, 0.3, 0.0, 0.3)
	button_bg_style.shadow_size = 6
	button_bg_style.content_margin_left = 0
	button_bg_style.content_margin_right = 0
	button_bg_style.content_margin_top = 0
	button_bg_style.content_margin_bottom = 0
	button_bg.add_theme_stylebox_override("panel", button_bg_style)
	button_center.add_child(button_bg)
	
	# Create activation button inside background
	supercharge_button = TextureButton.new()
	supercharge_button.name = "SuperchargeButton"
	supercharge_button.custom_minimum_size = Vector2(46, 46)
	supercharge_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	supercharge_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	# Load flame icon (custom SVG)
	var icon_texture := load("res://assets/icons/super_charge_flame.svg") as Texture2D
	if not icon_texture:
		# Fallback to original icon
		icon_texture = load("res://assets/icons/super_charge.svg") as Texture2D
	if icon_texture:
		supercharge_button.texture_normal = icon_texture
		supercharge_button.ignore_texture_size = true
		supercharge_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	
	supercharge_button.modulate = Color(0.5, 0.5, 0.5, 0.6)  # Dimmed when not ready
	supercharge_button.pressed.connect(_on_supercharge_button_pressed)
	button_bg.add_child(supercharge_button)

func _on_supercharge_changed(charge: float, max_charge: float) -> void:
	if not supercharge_bar:
		return
	
	supercharge_bar.max_value = max_charge
	supercharge_bar.value = charge
	
	# Check if ready
	var was_ready := supercharge_ready
	supercharge_ready = charge >= max_charge and not gm.is_supercharged
	
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

func _on_supercharge_ended() -> void:
	# Button stays dimmed until recharged
	pass

func _on_supercharge_button_pressed() -> void:
	if gm and gm.is_supercharge_ready():
		gm.activate_supercharge()
	# Release focus to prevent repeated activation
	if supercharge_button:
		supercharge_button.release_focus()

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
	
	# Also pulse the bar with glowing effect
	if supercharge_bar:
		supercharge_bar_glow_tween = create_tween()
		supercharge_bar_glow_tween.set_loops()
		supercharge_bar_glow_tween.tween_property(supercharge_bar, "modulate", Color(1.8, 1.4, 1.0, 1.0), 0.3)
		supercharge_bar_glow_tween.tween_property(supercharge_bar, "modulate", Color(1.2, 1.0, 0.9, 1.0), 0.3)
	
	# Pulse the panel border too
	if supercharge_panel:
		var panel_style := supercharge_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		if panel_style:
			panel_style.border_color = Color(1.0, 0.5, 0.2, 0.9)
			panel_style.border_width_left = 3
			panel_style.border_width_right = 3
			panel_style.border_width_top = 3
			panel_style.border_width_bottom = 3
			supercharge_panel.add_theme_stylebox_override("panel", panel_style)

func _stop_supercharge_glow() -> void:
	if supercharge_glow_tween:
		supercharge_glow_tween.kill()
		supercharge_glow_tween = null
	
	if supercharge_bar_glow_tween:
		supercharge_bar_glow_tween.kill()
		supercharge_bar_glow_tween = null
	
	if supercharge_button:
		supercharge_button.modulate = Color(0.5, 0.5, 0.5, 0.6)
	
	if supercharge_bar:
		supercharge_bar.modulate = Color(1.0, 1.0, 1.0, 1.0)
	
	# Reset panel border
	if supercharge_panel:
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.4)
		panel_style.corner_radius_top_left = 12
		panel_style.corner_radius_top_right = 12
		panel_style.corner_radius_bottom_left = 12
		panel_style.corner_radius_bottom_right = 12
		panel_style.border_width_left = 2
		panel_style.border_width_right = 2
		panel_style.border_width_top = 2
		panel_style.border_width_bottom = 2
		panel_style.border_color = Color(0.3, 0.3, 0.3, 0.6)
		panel_style.content_margin_left = 10
		panel_style.content_margin_right = 10
		panel_style.content_margin_top = 10
		panel_style.content_margin_bottom = 10
		supercharge_panel.add_theme_stylebox_override("panel", panel_style)

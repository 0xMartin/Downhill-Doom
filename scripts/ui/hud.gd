extends CanvasLayer
## HUD - Displays coins, distance, health, and handles pause

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
var supercharge_panel: PanelContainer
var supercharge_container: VBoxContainer
var supercharge_bar: ProgressBar
var supercharge_button: TextureButton
var supercharge_glow_tween: Tween
var supercharge_bar_glow_tween: Tween
var supercharge_ready: bool = false
var supercharge_count_label: Label

# Multiplier UI
var multiplier_panel: Control
var multiplier_label: Label
var multiplier_tween: Tween

# Settings button UI (floating)
var settings_button_panel: Control
var settings_button: TextureButton

# Combo UI
var combo_panel: Control
var combo_label: Label
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
	gm.object_destroyed.connect(_on_object_destroyed)
	
	# Create supercharge UI
	_create_supercharge_ui()
	
	# Create multiplier UI
	_create_multiplier_ui()
	
	# Create settings button UI (floating above multiplier)
	_create_settings_button_ui()
	
	# Create combo UI
	_create_combo_ui()
	
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

# ========== Floating Combo Bonus Popup ==========

func show_combo_popup(amount: int, icon_texture: Texture2D) -> void:
	if not audio or not audio.get_show_pickup_popup():
		return
	
	# Create popup container
	var popup := HBoxContainer.new()
	popup.add_theme_constant_override("separation", 12)
	
	# Create +N label - large, bold style with outline (cyan/turquoise for combo bonus)
	var label := Label.new()
	label.text = "+" + format_number(amount)
	label.add_theme_font_size_override("font_size", 58)
	label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.9, 1))  # Bright cyan/turquoise
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_color_override("font_outline_color", Color(0, 0.3, 0.3, 1))  # Dark teal outline
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
	icon.modulate = Color(0.3, 1.0, 0.9, 1)  # Cyan tint to match
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
	
	# TopBar height (increased by 20% from 64 to 77)
	var top_bar_height: float = 77.0
	var timer_gap: float = 26.0
	var timer_height: float = 32.0
	var combo_gap: float = 10.0
	var combo_height: float = 50.0
	
	# Apply offset to top bar
	if top_bar:
		top_bar.offset_top = actual_top_offset
		top_bar.offset_bottom = actual_top_offset + top_bar_height
	
	# Move TimerLabel together with TopBar
	if timer_label:
		timer_label.offset_top = actual_top_offset + top_bar_height + timer_gap
		timer_label.offset_bottom = timer_label.offset_top + timer_height
	
	# Move ComboPanel together with TimerLabel (below timer with gap)
	if combo_panel:
		combo_panel.offset_top = actual_top_offset + top_bar_height + timer_gap + timer_height + combo_gap
		combo_panel.offset_bottom = combo_panel.offset_top + combo_height

# ========== Multiplier UI ==========

func _create_multiplier_ui() -> void:
	# Clean coin design using SVG frame
	var coin_size := 84.0
	multiplier_panel = Control.new()
	multiplier_panel.name = "MultiplierPanel"
	multiplier_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	multiplier_panel.anchor_left = 1.0
	multiplier_panel.anchor_right = 1.0
	multiplier_panel.anchor_top = 0.5
	multiplier_panel.anchor_bottom = 0.5
	multiplier_panel.offset_left = -96
	multiplier_panel.offset_right = -12
	multiplier_panel.offset_top = -264
	multiplier_panel.offset_bottom = -180
	multiplier_panel.pivot_offset = Vector2(coin_size / 2, coin_size / 2)
	add_child(multiplier_panel)
	
	# Dark circular shadow background
	var shadow_bg := PanelContainer.new()
	shadow_bg.name = "ShadowBackground"
	shadow_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.12, 0.14, 0.92)
	bg_style.corner_radius_top_left = 42
	bg_style.corner_radius_top_right = 42
	bg_style.corner_radius_bottom_left = 42
	bg_style.corner_radius_bottom_right = 42
	bg_style.shadow_color = Color(0, 0, 0, 0.5)
	bg_style.shadow_size = 6
	bg_style.shadow_offset = Vector2(0, 3)
	shadow_bg.add_theme_stylebox_override("panel", bg_style)
	multiplier_panel.add_child(shadow_bg)
	
	# SVG coin frame background
	var coin_frame := TextureRect.new()
	coin_frame.name = "CoinFrame"
	coin_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var frame_texture := load("res://assets/svg/ui_coin_frame.svg") as Texture2D
	if frame_texture:
		coin_frame.texture = frame_texture
		coin_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	multiplier_panel.add_child(coin_frame)
	
	# Multiplier text label centered on coin
	multiplier_label = Label.new()
	multiplier_label.name = "MultiplierLabel"
	multiplier_label.text = "x1"
	multiplier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	multiplier_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	multiplier_label.add_theme_font_size_override("font_size", 32)
	multiplier_label.add_theme_color_override("font_color", Color(0.2, 0.1, 0.0, 1.0))
	multiplier_label.add_theme_color_override("font_shadow_color", Color(1.0, 0.85, 0.4, 0.8))
	multiplier_label.add_theme_color_override("font_outline_color", Color(0.5, 0.3, 0.0, 1.0))
	multiplier_label.add_theme_constant_override("shadow_offset_x", 0)
	multiplier_label.add_theme_constant_override("shadow_offset_y", 1)
	multiplier_label.add_theme_constant_override("outline_size", 4)
	multiplier_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	multiplier_panel.add_child(multiplier_label)

# ========== Settings Button UI ==========

func _create_settings_button_ui() -> void:
	# Settings button same size as coin (84px)
	var button_size := 84.0
	settings_button_panel = Control.new()
	settings_button_panel.name = "SettingsButtonPanel"
	settings_button_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	settings_button_panel.anchor_left = 1.0
	settings_button_panel.anchor_right = 1.0
	settings_button_panel.anchor_top = 0.5
	settings_button_panel.anchor_bottom = 0.5
	settings_button_panel.offset_left = -96
	settings_button_panel.offset_right = -12
	settings_button_panel.offset_top = -264 - 16 - button_size
	settings_button_panel.offset_bottom = -264 - 16
	settings_button_panel.pivot_offset = Vector2(button_size / 2, button_size / 2)
	settings_button_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(settings_button_panel)
	
	# Dark gray circular background (same style as top bar)
	var button_bg := PanelContainer.new()
	button_bg.name = "ButtonBackground"
	button_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.12, 0.12, 0.14, 0.92)
	bg_style.corner_radius_top_left = 42
	bg_style.corner_radius_top_right = 42
	bg_style.corner_radius_bottom_left = 42
	bg_style.corner_radius_bottom_right = 42
	bg_style.border_width_left = 2
	bg_style.border_width_right = 2
	bg_style.border_width_top = 2
	bg_style.border_width_bottom = 2
	bg_style.border_color = Color(0.25, 0.25, 0.28, 0.7)
	bg_style.shadow_color = Color(0, 0, 0, 0.5)
	bg_style.shadow_size = 6
	bg_style.shadow_offset = Vector2(0, 3)
	button_bg.add_theme_stylebox_override("panel", bg_style)
	settings_button_panel.add_child(button_bg)
	
	# Settings icon button (with padding - added to panel not PanelContainer)
	settings_button = TextureButton.new()
	settings_button.name = "SettingsButton"
	settings_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	settings_button.offset_left = 24
	settings_button.offset_top = 24
	settings_button.offset_right = -24
	settings_button.offset_bottom = -24
	
	var icon_texture := load("res://assets/svg/settings.svg") as Texture2D
	if icon_texture:
		settings_button.texture_normal = icon_texture
		settings_button.ignore_texture_size = true
		settings_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	
	settings_button.modulate = Color(0.6, 0.6, 0.65, 0.9)
	settings_button.pressed.connect(_on_settings_pressed)
	settings_button_panel.add_child(settings_button)

# ========== Combo UI ==========

func _create_combo_ui() -> void:
	# Combo display - centered horizontally, below timer label
	# Position will be adjusted by _apply_safe_area_offset()
	combo_panel = Control.new()
	combo_panel.name = "ComboPanel"
	combo_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	combo_panel.anchor_left = 0.5
	combo_panel.anchor_right = 0.5
	combo_panel.anchor_top = 0.0
	combo_panel.anchor_bottom = 0.0
	combo_panel.offset_left = -100
	combo_panel.offset_right = 100
	combo_panel.offset_top = 165  # Initial value, will be adjusted by safe area
	combo_panel.offset_bottom = 215
	combo_panel.pivot_offset = Vector2(100, 25)  # Center pivot
	combo_panel.visible = false  # Hidden until combo starts
	add_child(combo_panel)
	
	# Combo label with dramatic styling
	combo_label = Label.new()
	combo_label.name = "ComboLabel"
	combo_label.text = "COMBO x2"
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	combo_label.add_theme_font_size_override("font_size", 32)
	combo_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1, 1.0))  # Orange-gold
	combo_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	combo_label.add_theme_color_override("font_outline_color", Color(0.3, 0.1, 0.0, 1.0))
	combo_label.add_theme_constant_override("shadow_offset_x", 2)
	combo_label.add_theme_constant_override("shadow_offset_y", 2)
	combo_label.add_theme_constant_override("outline_size", 4)
	combo_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	combo_panel.add_child(combo_label)

func _on_object_destroyed(object_id: String, _object_name: String, base_coins: int) -> void:
	# Check if same object type as last destroyed
	if object_id == last_destroyed_id:
		current_combo += 1
	else:
		current_combo = 1
		last_destroyed_id = object_id
	
	# Apply combo bonus (combo >= 2 gives bonus coins)
	if current_combo >= 2:
		var combo_bonus: int = base_coins * (current_combo - 1)  # x2 = +1x base, x3 = +2x base, etc.
		var multiplied_bonus: int = combo_bonus * gm.coin_multiplier  # Apply same multiplier
		skip_combo_popup = multiplied_bonus  # Skip gold popup for this amount
		gm.add_coin(combo_bonus)  # This will be multiplied internally
		show_combo_popup(multiplied_bonus, coin_icon_texture)  # Show cyan popup for bonus
		_show_combo(current_combo)

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

func _create_supercharge_ui() -> void:
	# Clean supercharge panel with StyleBoxFlat
	supercharge_panel = PanelContainer.new()
	supercharge_panel.name = "SuperchargePanel"
	supercharge_panel.anchor_left = 1.0
	supercharge_panel.anchor_right = 1.0
	supercharge_panel.anchor_top = 0.5
	supercharge_panel.anchor_bottom = 0.5
	supercharge_panel.offset_left = -96
	supercharge_panel.offset_right = -12
	supercharge_panel.offset_top = -168
	supercharge_panel.offset_bottom = 168
	supercharge_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Dark panel with fully rounded ends (50% width = 42px)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.06, 0.14, 0.75)
	panel_style.corner_radius_top_left = 42
	panel_style.corner_radius_top_right = 42
	panel_style.corner_radius_bottom_left = 42
	panel_style.corner_radius_bottom_right = 42
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.4, 0.3, 0.5, 0.6)
	panel_style.shadow_color = Color(0, 0, 0, 0.5)
	panel_style.shadow_size = 8
	panel_style.shadow_offset = Vector2(0, 4)
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 16
	panel_style.content_margin_bottom = 16
	supercharge_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(supercharge_panel)
	
	# Main container
	supercharge_container = VBoxContainer.new()
	supercharge_container.name = "SuperchargeContainer"
	supercharge_container.add_theme_constant_override("separation", 14)
	supercharge_container.alignment = BoxContainer.ALIGNMENT_CENTER
	supercharge_panel.add_child(supercharge_container)
	
	# Progress bar (simple, no extra container)
	supercharge_bar = ProgressBar.new()
	supercharge_bar.name = "SuperchargeBar"
	supercharge_bar.custom_minimum_size = Vector2(52, 200)
	supercharge_bar.fill_mode = ProgressBar.FILL_BOTTOM_TO_TOP
	supercharge_bar.show_percentage = false
	supercharge_bar.max_value = 100.0
	supercharge_bar.value = 0.0
	supercharge_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	# Bar background - fully rounded ends (50% width = 26px)
	var bar_bg_style := StyleBoxFlat.new()
	bar_bg_style.bg_color = Color(0.05, 0.03, 0.08, 0.9)
	bar_bg_style.corner_radius_top_left = 26
	bar_bg_style.corner_radius_top_right = 26
	bar_bg_style.corner_radius_bottom_left = 26
	bar_bg_style.corner_radius_bottom_right = 26
	bar_bg_style.border_width_left = 2
	bar_bg_style.border_width_right = 2
	bar_bg_style.border_width_top = 2
	bar_bg_style.border_width_bottom = 2
	bar_bg_style.border_color = Color(0.3, 0.2, 0.4, 0.5)
	supercharge_bar.add_theme_stylebox_override("background", bar_bg_style)
	
	# Orange fill - fully rounded (same as background)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color(1.0, 0.5, 0.15, 1.0)
	fill_style.corner_radius_top_left = 26
	fill_style.corner_radius_top_right = 26
	fill_style.corner_radius_bottom_left = 26
	fill_style.corner_radius_bottom_right = 26
	fill_style.border_width_top = 2
	fill_style.border_color = Color(1.0, 0.8, 0.4, 0.6)
	supercharge_bar.add_theme_stylebox_override("fill", fill_style)
	supercharge_container.add_child(supercharge_bar)
	
	# Count label - overlaid on bar
	supercharge_count_label = Label.new()
	supercharge_count_label.name = "SuperchargeCountLabel"
	supercharge_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	supercharge_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	supercharge_count_label.text = "0\n━\n10"
	supercharge_count_label.add_theme_font_size_override("font_size", 22)
	supercharge_count_label.add_theme_color_override("font_color", Color.WHITE)
	supercharge_count_label.add_theme_constant_override("outline_size", 5)
	supercharge_count_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	supercharge_count_label.set_anchors_preset(Control.PRESET_CENTER)
	supercharge_count_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	supercharge_count_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	supercharge_bar.add_child(supercharge_count_label)
	
	# Fire button
	supercharge_button = TextureButton.new()
	supercharge_button.name = "SuperchargeButton"
	supercharge_button.custom_minimum_size = Vector2(60, 60)
	supercharge_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	var fire_texture := load("res://assets/svg/ui_fire_button.svg") as Texture2D
	if fire_texture:
		supercharge_button.texture_normal = fire_texture
		supercharge_button.ignore_texture_size = true
		supercharge_button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	
	supercharge_button.modulate = Color(0.5, 0.5, 0.5, 0.6)
	supercharge_button.pressed.connect(_on_supercharge_button_pressed)
	supercharge_container.add_child(supercharge_button)

func _on_supercharge_changed(current: int, required: int) -> void:
	if not supercharge_bar:
		return
	
	supercharge_bar.max_value = required
	supercharge_bar.value = current
	
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
		panel_style.bg_color = Color(0.08, 0.06, 0.14, 0.75)
		panel_style.corner_radius_top_left = 42
		panel_style.corner_radius_top_right = 42
		panel_style.corner_radius_bottom_left = 42
		panel_style.corner_radius_bottom_right = 42
		panel_style.border_width_left = 2
		panel_style.border_width_right = 2
		panel_style.border_width_top = 2
		panel_style.border_width_bottom = 2
		panel_style.border_color = Color(0.4, 0.3, 0.5, 0.6)
		panel_style.shadow_color = Color(0, 0, 0, 0.5)
		panel_style.shadow_size = 8
		panel_style.shadow_offset = Vector2(0, 4)
		panel_style.content_margin_left = 12
		panel_style.content_margin_right = 12
		panel_style.content_margin_top = 16
		panel_style.content_margin_bottom = 16
		supercharge_panel.add_theme_stylebox_override("panel", panel_style)

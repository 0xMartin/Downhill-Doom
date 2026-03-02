extends CanvasLayer
## HUD - Displays coins, distance, health, and handles pause

@onready var top_bar: PanelContainer = $TopBar
@onready var coins_label: Label = $TopBar/MarginContainer/HBoxContainer/CoinsContainer/CoinsLabel
@onready var distance_label: Label = $TopBar/MarginContainer/HBoxContainer/DistanceContainer/DistanceLabel
@onready var health_bar: ProgressBar = $TopBar/MarginContainer/HBoxContainer/HealthContainer/HealthBar
@onready var red_flash: ColorRect = $RedFlash
@onready var pause_menu: Control = $PauseMenu
@onready var music_slider: HSlider = $PauseMenu/PanelContainer/VBoxContainer/MusicSlider
@onready var sfx_slider: HSlider = $PauseMenu/PanelContainer/VBoxContainer/SFXSlider
@onready var popup_check: CheckButton = $PauseMenu/PanelContainer/VBoxContainer/PopupCheck
@onready var sparkle: TextureRect = $TopBar/MarginContainer/HBoxContainer/CoinsContainer/CoinIcon/Sparkle
@onready var popup_container: Control = $PopupContainer

var gm: Node  # GameManager reference
var audio: Node  # AudioManager reference
var coin_icon_texture: Texture2D
var last_coin_count: int = 0
var sparkle_time: float = 0.0

func _ready() -> void:
	gm = get_node("/root/GameManager")
	audio = get_node("/root/AudioManager")
	coin_icon_texture = load("res://assets/icons/coin.svg")
	gm.coins_changed.connect(_on_coins_changed)
	gm.distance_changed.connect(_on_distance_changed)
	gm.game_paused.connect(_on_game_paused)
	gm.health_changed.connect(_on_health_changed)
	gm.player_hit.connect(_on_player_hit)
	
	# Adjust top bar position for mobile safe area (notch, status bar)
	_apply_safe_area_offset()
	
	# Initialize sliders with current volume values
	if audio:
		music_slider.value = audio.get_music_volume()
		sfx_slider.value = audio.get_sfx_volume()
		popup_check.button_pressed = audio.get_show_pickup_popup()
	
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
			var sparkle_tween := create_tween()
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

func _on_game_paused(is_paused: bool) -> void:
	pause_menu.visible = is_paused

func _on_health_changed(health: int, max_health: int) -> void:
	health_bar.max_value = max_health
	health_bar.value = health
	
	# Juice animation - shrink and expand
	var tween := create_tween()
	tween.tween_property(health_bar, "scale", Vector2(0.95, 0.8), 0.05)
	tween.tween_property(health_bar, "scale", Vector2.ONE, 0.1)

func _on_player_hit(_damage: int) -> void:
	# Flash red overlay
	red_flash.visible = true
	red_flash.modulate.a = 1.0
	
	var tween := create_tween()
	tween.tween_property(red_flash, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): red_flash.visible = false)

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

# ========== Floating Pickup Popup ==========

func show_pickup_popup(amount: int, icon_texture: Texture2D) -> void:
	if not audio or not audio.get_show_pickup_popup():
		return
	
	# Create popup container
	var popup := HBoxContainer.new()
	popup.add_theme_constant_override("separation", 8)
	
	# Create +N label (30% bigger)
	var label := Label.new()
	label.text = "+" + str(amount)
	label.add_theme_font_size_override("font_size", 47)
	label.add_theme_color_override("font_color", Color(1, 0.85, 0, 1))  # Gold
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	popup.add_child(label)
	
	# Create icon (30% bigger)
	var icon := TextureRect.new()
	icon.texture = icon_texture
	icon.custom_minimum_size = Vector2(42, 42)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(1, 0.85, 0, 1)  # Gold tint
	popup.add_child(icon)
	
	# Position at player area - use design resolution (720x1280 with stretch)
	# Center horizontally, 67% from top vertically
	var design_width: float = 720.0
	var design_height: float = 1280.0
	var base_x: float = design_width / 2.0
	var base_y: float = design_height * 0.67
	
	# Small random offset around spawn point
	var offset_x := randf_range(-40, 40)
	var offset_y := randf_range(-30, 30)
	# Center the popup (estimate ~80px width for "+1" + icon)
	popup.position = Vector2(base_x - 40 + offset_x, base_y + offset_y)
	popup.pivot_offset = Vector2(50, 25)  # Center pivot for rotation
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

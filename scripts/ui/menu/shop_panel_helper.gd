class_name ShopPanelHelper
extends RefCounted
## Scene-based shop panel helper that loads static UI from scene file
## and handles dynamic content generation (skin cards, boost cards, crate cards, roulette)

const CONTENT_SCENE := preload("res://scenes/ui/menu/shop_panel_content.tscn")
const ROULETTE_SPINNER_SCENE := preload("res://scenes/ui/menu/roulette_spinner.tscn")
const ROULETTE_RESULT_SCENE := preload("res://scenes/ui/menu/roulette_result.tscn")
const MODEL_SKIN_CARD_SCENE := preload("res://scenes/ui/item/model_skin_card.tscn")
const SPECIAL_SKIN_CARD_SCENE := preload("res://scenes/ui/item/special_skin_card.tscn")
const BOOST_CARD_SCENE := preload("res://scenes/ui/item/boost_card.tscn")
const CRATE_CARD_SCENE := preload("res://scenes/ui/item/crate_card.tscn")

# UI Size Constants
const LIST_ITEM_HEIGHT := 184
const LIST_ITEM_HEIGHT_LARGE := 220
const ROULETTE_WINDOW_WIDTH := 980
const ROULETTE_WINDOW_HEIGHT := 280
const ROULETTE_ITEM_WIDTH := 200
const ROULETTE_ITEM_HEIGHT := 220
const ROULETTE_ICON_SIZE := 140
const ROULETTE_ITEM_SPACING := 16
const FONT_SIZE_NORMAL := 48

# Colors
const COLOR_ACCENT_PRIMARY := Color(0.28, 0.76, 0.70, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.62, 0.32, 0.82, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.8, 0.85, 0.9, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.6, 1.0)
const COLOR_BG_DARK := Color(0.08, 0.1, 0.14, 1.0)
const COLOR_BG_LIGHT := Color(0.14, 0.18, 0.26, 1.0)
const COLOR_BORDER := Color(0.3, 0.35, 0.5, 0.6)

const SHOP_SECTIONS := ["SKINS", "BOOSTS", "CRATES"]

# Signals for main menu communication
signal balance_update_needed
signal stats_reload_needed
signal player_model_refresh_needed

# References
var shop_panel: Control
var content_instance: Control
var shop_section_label: Label
var shop_content_container: VBoxContainer
var shop_manager: Node
var audio_manager: Node
var stats: Dictionary

# Roulette state
var roulette_container: Control
var roulette_hbox: HBoxContainer
var roulette_tween: Tween
var roulette_result: Dictionary
var roulette_crate_type: String
var roulette_items: Array
var roulette_last_item_index: int = -1
var roulette_looping_tweens: Array[Tween] = []
var roulette_click_sound: AudioStreamPlayer
var roulette_speed_lines: TextureRect

# Shop state
var shop_section_index: int = 0


func _init(panel: Control, p_shop_manager: Node, p_audio_manager: Node, p_stats: Dictionary) -> void:
	shop_panel = panel
	shop_manager = p_shop_manager
	audio_manager = p_audio_manager
	stats = p_stats


func rebuild() -> void:
	# Clear existing content except Background
	var children_to_remove: Array[Node] = []
	for child in shop_panel.get_children():
		if child.name != "Background":
			children_to_remove.append(child)
	for child in children_to_remove:
		shop_panel.remove_child(child)
		child.free()
	
	# Update background
	var bg: ColorRect = shop_panel.get_node_or_null("Background")
	if bg:
		bg.color = Color(0.04, 0.05, 0.08, 1.0)
	
	# Calculate safe area offset
	var safe_area := DisplayServer.get_display_safe_area()
	var screen_size: Vector2 = shop_panel.get_viewport().get_visible_rect().size
	var physical_screen := Vector2(DisplayServer.screen_get_size())
	var scale_y: float = screen_size.y / physical_screen.y if physical_screen.y > 0 else 1.0
	var top_inset: float = safe_area.position.y * scale_y
	
	# Instantiate the scene
	content_instance = CONTENT_SCENE.instantiate()
	content_instance.set_anchors_preset(Control.PRESET_FULL_RECT)
	content_instance.offset_top = top_inset
	shop_panel.add_child(content_instance)
	
	# Find UI references
	_find_ui_references()
	
	# Connect signals
	_connect_signals()
	
	# Populate initial section
	update_balance()
	_populate_section()


func _find_ui_references() -> void:
	shop_section_label = content_instance.get_node("%SectionLabel") as Label
	shop_content_container = content_instance.get_node("%ShopContentContainer") as VBoxContainer


func _connect_signals() -> void:
	var _back_button := content_instance.get_node("%BackButton") as Button
	# Back button signal connected in main_menu.gd
	
	var prev_button := content_instance.get_node("%PrevButton") as Button
	var next_button := content_instance.get_node("%NextButton") as Button
	
	if prev_button:
		prev_button.pressed.connect(_on_section_prev)
	if next_button:
		next_button.pressed.connect(_on_section_next)


func get_back_button() -> Button:
	if content_instance:
		return content_instance.get_node("%BackButton") as Button
	return null


func update_stats(new_stats: Dictionary) -> void:
	stats = new_stats


func update_balance() -> void:
	var label := content_instance.get_node("%ShopBalanceLabel") as Label
	if label:
		label.text = _format_balance(stats.get("coin_balance", 0))


func _on_section_prev() -> void:
	if audio_manager:
		audio_manager.play_button_click()
	shop_section_index = (shop_section_index - 1 + SHOP_SECTIONS.size()) % SHOP_SECTIONS.size()
	_update_section_display()


func _on_section_next() -> void:
	if audio_manager:
		audio_manager.play_button_click()
	shop_section_index = (shop_section_index + 1) % SHOP_SECTIONS.size()
	_update_section_display()


func _update_section_display() -> void:
	if shop_section_label:
		shop_section_label.text = SHOP_SECTIONS[shop_section_index]
	_populate_section()


func _populate_section() -> void:
	if not shop_content_container:
		return
	
	for child in shop_content_container.get_children():
		child.queue_free()
	
	match shop_section_index:
		0:
			_populate_skins_section()
		1:
			_populate_boosts_section()
		2:
			_populate_crates_section()


func _populate_skins_section() -> void:
	if not shop_manager:
		return
	
	# Model-based skins
	var model_header := Label.new()
	model_header.text = "MODEL SKINS"
	model_header.add_theme_font_size_override("font_size", 34)
	model_header.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	shop_content_container.add_child(model_header)
	
	var model_skins := ["player_1", "player_2", "player_3", "player_4", "player_5", "player_6", "player_7", "player_8", "player_9"]
	for skin_id in model_skins:
		var card = MODEL_SKIN_CARD_SCENE.instantiate()
		shop_content_container.add_child(card)
		var display_name: String = shop_manager.SKIN_NAMES.get(skin_id, skin_id)
		var is_owned: bool = shop_manager.is_skin_owned(skin_id)
		var is_selected: bool = shop_manager.get_selected_skin() == skin_id
		var price: int = shop_manager.get_skin_price(skin_id)
		card.setup(skin_id, display_name, is_owned, is_selected, price)
		card.skin_selected.connect(_on_skin_select)
		card.skin_bought.connect(_on_skin_buy)
	
	# Texture skins from crates
	var texture_header := Label.new()
	texture_header.text = "SPECIAL SKINS (from crates)"
	texture_header.add_theme_font_size_override("font_size", 34)
	texture_header.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	shop_content_container.add_child(texture_header)
	
	var texture_skins: Array = shop_manager.available_texture_skins
	if texture_skins.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No special skins available yet"
		empty_label.add_theme_font_size_override("font_size", 28)
		empty_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		shop_content_container.add_child(empty_label)
	else:
		for skin_id in texture_skins:
			var card = SPECIAL_SKIN_CARD_SCENE.instantiate()
			shop_content_container.add_child(card)
			var display_name: String = skin_id.replace("_", " ").capitalize()
			var is_owned: bool = shop_manager.is_skin_owned(skin_id)
			var is_selected: bool = shop_manager.get_selected_skin() == skin_id
			card.setup(skin_id, display_name, is_owned, is_selected)
			card.skin_selected.connect(_on_skin_select)


func _populate_boosts_section() -> void:
	if not shop_manager:
		return
	
	# Selected boosts info
	var selected: Array = shop_manager.get_selected_boosts()
	var selected_label := Label.new()
	selected_label.text = "Selected for next game: %d/2" % selected.size()
	selected_label.add_theme_font_size_override("font_size", 32)
	selected_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_content_container.add_child(selected_label)
	
	# Boost cards
	var boost_ids: Array = shop_manager.BOOST_PRICES.keys()
	for boost_id in boost_ids:
		var card = BOOST_CARD_SCENE.instantiate()
		shop_content_container.add_child(card)
		var owned_count: int = shop_manager.get_boost_count(boost_id)
		var is_selected: bool = shop_manager.is_boost_selected(boost_id)
		var price: int = shop_manager.BOOST_PRICES.get(boost_id, 0)
		var display_name: String = shop_manager.BOOST_NAMES.get(boost_id, boost_id)
		var icon_path: String = shop_manager.BOOST_ICONS.get(boost_id, "")
		card.setup(boost_id, display_name, icon_path, owned_count, is_selected, price)
		card.boost_toggled.connect(_on_boost_toggle)
		card.boost_bought.connect(_on_boost_buy)


func _populate_crates_section() -> void:
	if not shop_manager:
		return
	
	var crate_types := ["basic", "premium", "legendary"]
	for crate_type in crate_types:
		var card = CRATE_CARD_SCENE.instantiate()
		shop_content_container.add_child(card)
		var owned_count: int = shop_manager.get_crate_count(crate_type)
		var price: int = shop_manager.CRATE_PRICES.get(crate_type, 0)
		var display_name: String = shop_manager.CRATE_NAMES.get(crate_type, crate_type)
		var icon_path: String = shop_manager.CRATE_ICONS.get(crate_type, "")
		var chances: Dictionary = shop_manager.CRATE_DROP_CHANCES.get(crate_type, {})
		card.setup(crate_type, display_name, icon_path, owned_count, chances, price)
		card.crate_opened.connect(_on_crate_open)
		card.crate_bought.connect(_on_crate_buy)


# ========== ROULETTE ==========

func show_roulette(crate_type: String) -> void:
	roulette_crate_type = crate_type
	roulette_items = shop_manager.generate_roulette_items(crate_type, 35)
	
	# Instance the spinner scene
	roulette_container = ROULETTE_SPINNER_SCENE.instantiate()
	shop_panel.add_child(roulette_container)
	
	# Set title text
	var title: Label = roulette_container.get_node("%Title")
	title.text = "OPENING %s" % shop_manager.CRATE_NAMES.get(crate_type, "Crate").to_upper()
	
	# Get references to scene elements
	roulette_hbox = roulette_container.get_node("%ItemsContainer")
	roulette_speed_lines = roulette_container.get_node("%SpeedLines")
	var marker_glow: TextureRect = roulette_container.get_node("%MarkerGlow")
	
	# Animate marker glow
	_animate_marker_glow(marker_glow)
	
	# Position items container vertically centered
	roulette_hbox.position = Vector2(0, (ROULETTE_WINDOW_HEIGHT - ROULETTE_ITEM_HEIGHT) / 2.0)
	
	# Populate items
	for i in range(roulette_items.size()):
		var item := _create_roulette_item(roulette_items[i])
		roulette_hbox.add_child(item)
	
	# Start animation
	_animate_roulette()


func _create_roulette_item(item_data: Dictionary) -> PanelContainer:
	## Creates a single item panel for the roulette spinner.
	## Each item type has distinct colors for easy identification:
	##
	## ROULETTE ITEM COLORS (edit here to change item appearance):
	## ─────────────────────────────────────────────────────────────
	## Boost items:  Teal border/bg    - COLOR_ACCENT_PRIMARY (0.28, 0.76, 0.70)
	## Crate items:  Purple border/bg  - COLOR_ACCENT_SECONDARY (0.62, 0.32, 0.82)
	## Skin items:   Gold border/bg    - COLOR_ACCENT_GOLD (1.0, 0.82, 0.25)
	## Default:      Gray border/bg    - COLOR_BORDER / COLOR_BG_DARK
	##
	## Background alpha: 0.15 for boost/crate, 0.20 for skin (more prominent)
	## Border width: 3px, Corner radius: 10px
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(ROULETTE_ITEM_WIDTH, ROULETTE_ITEM_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var style := StyleBoxFlat.new()
	var border_color := COLOR_BORDER
	var bg_color := COLOR_BG_DARK
	
	# Item type color assignment
	match item_data.get("type", ""):
		"boost":
			# Teal color for boosts
			border_color = COLOR_ACCENT_PRIMARY
			bg_color = Color(COLOR_ACCENT_PRIMARY.r, COLOR_ACCENT_PRIMARY.g, COLOR_ACCENT_PRIMARY.b, 0.15)
		"crate":
			# Purple color for nested crates
			border_color = COLOR_ACCENT_SECONDARY
			bg_color = Color(COLOR_ACCENT_SECONDARY.r, COLOR_ACCENT_SECONDARY.g, COLOR_ACCENT_SECONDARY.b, 0.15)
		"skin":
			# Gold color for skins (most valuable)
			border_color = COLOR_ACCENT_GOLD
			bg_color = Color(COLOR_ACCENT_GOLD.r, COLOR_ACCENT_GOLD.g, COLOR_ACCENT_GOLD.b, 0.2)
	
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(content)
	
	# Icon
	var icon_path := ""
	var is_texture_skin := false
	match item_data.get("type", ""):
		"boost":
			icon_path = shop_manager.BOOST_ICONS.get(item_data.get("id", ""), "")
		"crate":
			icon_path = shop_manager.CRATE_ICONS.get(item_data.get("id", ""), "")
		"skin":
			icon_path = "res://assets/skins/%s.png" % item_data.get("id", "")
			is_texture_skin = ResourceLoader.exists(icon_path)
	
	if is_texture_skin:
		var icon_size := ROULETTE_ICON_SIZE
		var half_icon := icon_size / 2
		var clip_container := Control.new()
		clip_container.clip_contents = true
		clip_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
		clip_container.offset_left = -half_icon
		clip_container.offset_right = half_icon
		clip_container.offset_top = 6
		clip_container.offset_bottom = 6 + icon_size
		content.add_child(clip_container)
		
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		var enlarged_size := icon_size * 2.5
		var icon_offset := (enlarged_size - icon_size) / 2.0
		icon.custom_minimum_size = Vector2(enlarged_size, enlarged_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.position = Vector2(-icon_offset, -icon_offset)
		clip_container.add_child(icon)
	else:
		var icon_size := ROULETTE_ICON_SIZE
		var half_icon := icon_size / 2
		var icon := TextureRect.new()
		if icon_path and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.offset_left = -half_icon
		icon.offset_right = half_icon
		icon.offset_top = 6
		icon.offset_bottom = 6 + icon_size
		content.add_child(icon)
	
	# Name label
	var name_label := Label.new()
	var item_name := ""
	match item_data.get("type", ""):
		"boost":
			item_name = shop_manager.BOOST_NAMES.get(item_data.get("id", ""), item_data.get("id", ""))
		"crate":
			item_name = shop_manager.CRATE_NAMES.get(item_data.get("id", ""), item_data.get("id", ""))
		"skin":
			item_name = item_data.get("id", "Skin").replace("_", " ").capitalize()
	
	if item_name.length() > 12:
		item_name = item_name.substr(0, 10) + ".."
	
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -42
	name_label.offset_bottom = 0
	name_label.offset_left = 2
	name_label.offset_right = -2
	content.add_child(name_label)
	
	return panel


func _animate_marker_glow(glow: TextureRect) -> void:
	var tween := shop_panel.create_tween()
	tween.set_loops()
	tween.tween_property(glow, "modulate:a", 0.9, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow, "modulate:a", 0.4, 0.8).set_trans(Tween.TRANS_SINE)
	roulette_looping_tweens.append(tween)


func _add_win_sparkles(container: Control) -> void:
	var sparkle_positions := [
		Vector2(-200, -180), Vector2(200, -180),
		Vector2(-250, 0), Vector2(250, 0),
		Vector2(-200, 180), Vector2(200, 180),
		Vector2(-100, -250), Vector2(100, -250),
		Vector2(0, 220), Vector2(-150, 120), Vector2(150, 120),
	]
	
	var sparkle_size := 40
	var half_size := sparkle_size / 2
	
	for i in range(sparkle_positions.size()):
		var sparkle := TextureRect.new()
		if ResourceLoader.exists("res://assets/svg/roulette_sparkle.svg"):
			sparkle.texture = load("res://assets/svg/roulette_sparkle.svg")
		sparkle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sparkle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sparkle.custom_minimum_size = Vector2(sparkle_size, sparkle_size)
		sparkle.set_anchors_preset(Control.PRESET_CENTER)
		sparkle.anchor_left = 0.5
		sparkle.anchor_right = 0.5
		sparkle.anchor_top = 0.5
		sparkle.anchor_bottom = 0.5
		sparkle.offset_left = sparkle_positions[i].x - half_size
		sparkle.offset_right = sparkle_positions[i].x + half_size
		sparkle.offset_top = sparkle_positions[i].y - half_size
		sparkle.offset_bottom = sparkle_positions[i].y + half_size
		sparkle.modulate = COLOR_ACCENT_GOLD
		sparkle.modulate.a = 0.0
		sparkle.pivot_offset = Vector2(half_size, half_size)
		container.add_child(sparkle)
		
		var delay := float(i) * 0.1
		var sparkle_tween := shop_panel.create_tween()
		sparkle_tween.set_loops()
		sparkle_tween.tween_interval(delay)
		sparkle_tween.tween_property(sparkle, "modulate:a", 1.0, 0.3)
		sparkle_tween.tween_property(sparkle, "modulate:a", 0.3, 0.5)
		roulette_looping_tweens.append(sparkle_tween)
		
		var rotation_speed := 2.0 + randf() * 2.0
		var rotation_dir := 1.0 if i % 2 == 0 else -1.0
		var rotate_tween := shop_panel.create_tween()
		rotate_tween.set_loops()
		rotate_tween.tween_property(sparkle, "rotation", rotation_dir * TAU, rotation_speed).from(0.0)
		roulette_looping_tweens.append(rotate_tween)


func _animate_win_label(label: Label) -> void:
	label.pivot_offset = label.size / 2
	label.scale = Vector2(0.3, 0.3)
	label.modulate.a = 0.0
	
	var tween := shop_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 1.0, 0.2)
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)
	
	var pulse_tween := shop_panel.create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_interval(0.5)
	pulse_tween.tween_property(label, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
	roulette_looping_tweens.append(pulse_tween)


func _animate_preview_container(container: CenterContainer) -> void:
	container.pivot_offset = container.size / 2
	container.scale = Vector2(0.5, 0.5)
	container.modulate.a = 0.0
	
	# Initial pop-in animation
	var tween := shop_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(container, "scale", Vector2(1.1, 1.1), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(container, "modulate:a", 1.0, 0.3)
	tween.chain().tween_property(container, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)
	
	# Continuous pulsing animation
	var pulse_tween := shop_panel.create_tween()
	pulse_tween.set_loops()
	pulse_tween.tween_interval(0.7)
	pulse_tween.tween_property(container, "scale", Vector2(1.08, 1.08), 0.8).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(container, "scale", Vector2(1.0, 1.0), 0.8).set_trans(Tween.TRANS_SINE)
	roulette_looping_tweens.append(pulse_tween)


func _animate_roulette() -> void:
	var winning_index := 25
	var window_width := float(ROULETTE_WINDOW_WIDTH)
	var window_center := window_width / 2.0
	
	roulette_hbox.position.x = window_width
	roulette_last_item_index = -1
	
	_setup_roulette_click_sound()
	
	roulette_result = shop_manager.open_crate(roulette_crate_type)
	
	if roulette_hbox.get_child_count() > winning_index:
		var winning_panel_update: PanelContainer = roulette_hbox.get_child(winning_index)
		_update_roulette_item(winning_panel_update, roulette_result)
	
	await shop_panel.get_tree().process_frame
	await shop_panel.get_tree().process_frame
	await shop_panel.get_tree().process_frame
	
	var item_size := float(ROULETTE_ITEM_WIDTH)
	var separation := float(ROULETTE_ITEM_SPACING)
	var item_step := item_size + separation
	var item_center := float(winning_index) * item_step + (item_size / 2.0)
	var target_x := window_center - item_center
	
	if not shop_panel.get_tree().process_frame.is_connected(_on_roulette_process):
		shop_panel.get_tree().process_frame.connect(_on_roulette_process)
	
	if roulette_speed_lines:
		var speed_tween := shop_panel.create_tween()
		speed_tween.tween_property(roulette_speed_lines, "modulate:a", 0.7, 0.3)
		speed_tween.tween_interval(0.9)
		speed_tween.tween_property(roulette_speed_lines, "modulate:a", 0.0, 1.5)
	
	roulette_tween = shop_panel.create_tween()
	
	roulette_tween.set_ease(Tween.EASE_IN)
	roulette_tween.set_trans(Tween.TRANS_QUAD)
	var midpoint := (window_width + target_x) * 0.4
	roulette_tween.tween_property(roulette_hbox, "position:x", midpoint, 1.2)
	
	roulette_tween.set_ease(Tween.EASE_OUT)
	roulette_tween.set_trans(Tween.TRANS_QUINT)
	roulette_tween.tween_property(roulette_hbox, "position:x", target_x, 2.8)
	
	roulette_tween.tween_callback(_highlight_winning_item.bind(winning_index))
	roulette_tween.tween_interval(0.8)
	roulette_tween.tween_callback(_on_roulette_finished)


func _highlight_winning_item(index: int) -> void:
	if not roulette_hbox or index < 0 or index >= roulette_hbox.get_child_count():
		return
	
	var winning_item: PanelContainer = roulette_hbox.get_child(index)
	
	var highlight := TextureRect.new()
	if ResourceLoader.exists("res://assets/svg/roulette_item_highlight.svg"):
		highlight.texture = load("res://assets/svg/roulette_item_highlight.svg")
	highlight.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	highlight.stretch_mode = TextureRect.STRETCH_SCALE
	highlight.set_anchors_preset(Control.PRESET_FULL_RECT)
	highlight.offset_left = -4
	highlight.offset_right = 4
	highlight.offset_top = -4
	highlight.offset_bottom = 4
	highlight.modulate.a = 0.0
	winning_item.add_child(highlight)
	highlight.show_behind_parent = false
	
	winning_item.pivot_offset = winning_item.size / 2
	
	var tween := shop_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(highlight, "modulate:a", 1.0, 0.3)
	tween.tween_property(winning_item, "scale", Vector2(1.15, 1.15), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	tween.chain().tween_property(winning_item, "scale", Vector2(1.1, 1.1), 0.15)
	
	var glow_tween := shop_panel.create_tween()
	glow_tween.set_loops(3)
	glow_tween.tween_property(highlight, "modulate:a", 1.0, 0.3)
	glow_tween.tween_property(highlight, "modulate:a", 0.6, 0.3)


func _update_roulette_item(panel: PanelContainer, result: Dictionary) -> void:
	for child in panel.get_children():
		child.queue_free()
	
	var style: StyleBoxFlat = panel.get_theme_stylebox("panel").duplicate()
	var border_color := COLOR_BORDER
	var bg_color := COLOR_BG_DARK
	
	match result.get("type", ""):
		"boost":
			border_color = COLOR_ACCENT_PRIMARY
			bg_color = Color(COLOR_ACCENT_PRIMARY.r, COLOR_ACCENT_PRIMARY.g, COLOR_ACCENT_PRIMARY.b, 0.15)
		"crate":
			border_color = COLOR_ACCENT_SECONDARY
			bg_color = Color(COLOR_ACCENT_SECONDARY.r, COLOR_ACCENT_SECONDARY.g, COLOR_ACCENT_SECONDARY.b, 0.15)
		"skin":
			border_color = COLOR_ACCENT_GOLD
			bg_color = Color(COLOR_ACCENT_GOLD.r, COLOR_ACCENT_GOLD.g, COLOR_ACCENT_GOLD.b, 0.2)
	
	style.border_color = border_color
	style.bg_color = bg_color
	style.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", style)
	
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(content)
	
	var icon_path := ""
	var is_texture_skin := false
	match result.get("type", ""):
		"boost":
			icon_path = shop_manager.BOOST_ICONS.get(result.get("id", ""), "")
		"crate":
			icon_path = shop_manager.CRATE_ICONS.get(result.get("id", ""), "")
		"skin":
			if result.get("is_duplicate", false):
				icon_path = "res://assets/svg/coin.svg"
			else:
				icon_path = "res://assets/skins/%s.png" % result.get("id", "")
				is_texture_skin = ResourceLoader.exists(icon_path)
	
	if is_texture_skin:
		var icon_size := ROULETTE_ICON_SIZE
		var half_icon := icon_size / 2
		var clip_container := Control.new()
		clip_container.clip_contents = true
		clip_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
		clip_container.offset_left = -half_icon
		clip_container.offset_right = half_icon
		clip_container.offset_top = 6
		clip_container.offset_bottom = 6 + icon_size
		content.add_child(clip_container)
		
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		var enlarged_size := icon_size * 2.5
		var icon_offset := (enlarged_size - icon_size) / 2.0
		icon.custom_minimum_size = Vector2(enlarged_size, enlarged_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.position = Vector2(-icon_offset, -icon_offset)
		clip_container.add_child(icon)
	else:
		var icon_size := ROULETTE_ICON_SIZE
		var half_icon := icon_size / 2
		var icon := TextureRect.new()
		if icon_path and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(icon_size, icon_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.offset_left = -half_icon
		icon.offset_right = half_icon
		icon.offset_top = 6
		icon.offset_bottom = 6 + icon_size
		content.add_child(icon)
	
	var name_label := Label.new()
	var item_name := ""
	match result.get("type", ""):
		"boost":
			item_name = shop_manager.BOOST_NAMES.get(result.get("id", ""), result.get("id", ""))
		"crate":
			item_name = shop_manager.CRATE_NAMES.get(result.get("id", ""), result.get("id", ""))
		"skin":
			if result.get("is_duplicate", false):
				item_name = "Refund: %s" % _format_balance(result.get("refund", 0))
			else:
				item_name = result.get("id", "Skin").replace("_", " ").capitalize()
	
	if item_name.length() > 12:
		item_name = item_name.substr(0, 10) + ".."
	
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -42
	name_label.offset_bottom = 0
	name_label.offset_left = 2
	name_label.offset_right = -2
	content.add_child(name_label)


func _on_roulette_finished() -> void:
	if shop_panel.get_tree().process_frame.is_connected(_on_roulette_process):
		shop_panel.get_tree().process_frame.disconnect(_on_roulette_process)
	
	var timer := shop_panel.get_tree().create_timer(1.0)
	await timer.timeout
	
	if roulette_container:
		# Remove the spinner, keep the parent
		roulette_container.queue_free()
		
		# Instance the result scene
		roulette_container = ROULETTE_RESULT_SCENE.instantiate()
		shop_panel.add_child(roulette_container)
		
		# Play lootbox win sound
		if audio_manager and audio_manager.has_method("play_ui_sound"):
			audio_manager.play_ui_sound("res://assets/sounds/ui/lootbox.mp3")
		
		# Get scene references
		var win_label: Label = roulette_container.get_node("%WinLabel")
		var preview_container: CenterContainer = roulette_container.get_node("%PreviewContainer")
		var item_label: Label = roulette_container.get_node("%ItemLabel")
		var close_btn: Button = roulette_container.get_node("%CloseButton")
		var burst_texture: TextureRect = roulette_container.get_node("%BurstTexture")
		
		# Animate burst
		var burst_tween := shop_panel.create_tween()
		burst_tween.tween_property(burst_texture, "modulate:a", 0.8, 0.5)
		
		var burst_rotate_tween := shop_panel.create_tween()
		burst_rotate_tween.set_loops()
		burst_rotate_tween.tween_property(burst_texture, "rotation", TAU, 8.0).from(0.0)
		roulette_looping_tweens.append(burst_rotate_tween)
		
		# Add sparkle effects
		_add_win_sparkles(roulette_container)
		
		# Animate win label
		win_label.ready.connect(_animate_win_label.bind(win_label))
		
		# Determine result content
		var result_text := ""
		var preview_icon_path := ""
		var is_skin := false
		match roulette_result.get("type", ""):
			"boost":
				result_text = shop_manager.BOOST_NAMES.get(roulette_result.get("id", ""), "Boost")
				preview_icon_path = shop_manager.BOOST_ICONS.get(roulette_result.get("id", ""), "")
			"crate":
				result_text = shop_manager.CRATE_NAMES.get(roulette_result.get("id", ""), "Crate")
				preview_icon_path = shop_manager.CRATE_ICONS.get(roulette_result.get("id", ""), "")
			"skin":
				is_skin = true
				if roulette_result.get("is_duplicate", false):
					result_text = "Duplicate skin! Refund: %s coins" % _format_balance(roulette_result.get("refund", 0))
					preview_icon_path = "res://assets/svg/coin.svg"
				else:
					var skin_id: String = roulette_result.get("id", "")
					result_text = "%s Skin!" % skin_id.replace("_", " ").capitalize()
					preview_icon_path = "res://assets/skins/%s.png" % skin_id
		
		# Create preview visual
		if is_skin and not roulette_result.get("is_duplicate", false):
			var skin_id: String = roulette_result.get("id", "")
			var texture_path := "res://assets/skins/%s.png" % skin_id
			var has_texture := ResourceLoader.exists(texture_path)
			
			var model_path := "res://assets/models/players/player_skin.blend"
			
			var specific_model := "res://assets/models/players/%s.blend" % skin_id
			if ResourceLoader.exists(specific_model):
				model_path = specific_model
				has_texture = false
			
			var preview_control := ModelRenderer.create_model_preview_control(
				model_path,
				texture_path if has_texture else "",
				Vector2(600, 600),
				0.3
			)
			preview_container.add_child(preview_control)
		elif is_skin and roulette_result.get("is_duplicate", false):
			var preview_icon := TextureRect.new()
			if ResourceLoader.exists("res://assets/svg/coin.svg"):
				preview_icon.texture = load("res://assets/svg/coin.svg")
			preview_icon.custom_minimum_size = Vector2(400, 400)
			preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview_container.add_child(preview_icon)
		elif preview_icon_path and ResourceLoader.exists(preview_icon_path):
			var preview_icon := TextureRect.new()
			preview_icon.texture = load(preview_icon_path)
			preview_icon.custom_minimum_size = Vector2(400, 400)
			preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview_container.add_child(preview_icon)
		
		# Animate preview container with pulsing effect
		_animate_preview_container(preview_container)
		
		# Set item label text
		item_label.text = result_text
		
		# Connect close button
		close_btn.pressed.connect(_on_roulette_close)


func _on_roulette_close() -> void:
	for tween in roulette_looping_tweens:
		if tween and tween.is_valid():
			tween.kill()
	roulette_looping_tweens.clear()
	
	if shop_panel.get_tree().process_frame.is_connected(_on_roulette_process):
		shop_panel.get_tree().process_frame.disconnect(_on_roulette_process)
	
	if roulette_click_sound:
		roulette_click_sound.queue_free()
		roulette_click_sound = null
	
	roulette_speed_lines = null
	
	if roulette_container:
		roulette_container.queue_free()
		roulette_container = null
	
	stats_reload_needed.emit()
	balance_update_needed.emit()
	_populate_section()


func _setup_roulette_click_sound() -> void:
	roulette_click_sound = AudioStreamPlayer.new()
	var click_stream := load("res://assets/sounds/ui/click.mp3")
	if click_stream:
		roulette_click_sound.stream = click_stream
		roulette_click_sound.volume_db = -5.0
	shop_panel.add_child(roulette_click_sound)


func _on_roulette_process() -> void:
	if not roulette_hbox or not roulette_tween or not roulette_tween.is_running():
		if shop_panel.get_tree().process_frame.is_connected(_on_roulette_process):
			shop_panel.get_tree().process_frame.disconnect(_on_roulette_process)
		return
	
	var window_center := float(ROULETTE_WINDOW_WIDTH) / 2.0
	var item_size := float(ROULETTE_ITEM_WIDTH)
	var separation := float(ROULETTE_ITEM_SPACING)
	var item_step := item_size + separation
	
	var pos_in_hbox := window_center - roulette_hbox.position.x
	var current_item_index := int(pos_in_hbox / item_step)
	
	if current_item_index != roulette_last_item_index and current_item_index >= 0 and current_item_index < roulette_hbox.get_child_count():
		if roulette_last_item_index >= 0 and roulette_last_item_index < roulette_hbox.get_child_count():
			var prev_item: PanelContainer = roulette_hbox.get_child(roulette_last_item_index)
			prev_item.scale = Vector2.ONE
		
		roulette_last_item_index = current_item_index
		
		if roulette_click_sound:
			roulette_click_sound.play()
		
		var current_item: PanelContainer = roulette_hbox.get_child(current_item_index)
		current_item.pivot_offset = current_item.size / 2
		var item_tween := shop_panel.create_tween()
		item_tween.tween_property(current_item, "scale", Vector2(1.08, 1.08), 0.05)
		item_tween.tween_property(current_item, "scale", Vector2.ONE, 0.1)


# ========== EVENT HANDLERS ==========

func _on_skin_buy(skin_id: String) -> void:
	audio_manager.play_button_click()
	if shop_manager.buy_skin(skin_id):
		stats_reload_needed.emit()
		balance_update_needed.emit()
		_populate_section()
		player_model_refresh_needed.emit()


func _on_skin_select(skin_id: String) -> void:
	audio_manager.play_button_click()
	if shop_manager.select_skin(skin_id):
		_populate_section()
		player_model_refresh_needed.emit()


func _on_boost_buy(boost_id: String) -> void:
	audio_manager.play_button_click()
	if shop_manager.buy_boost(boost_id):
		stats_reload_needed.emit()
		balance_update_needed.emit()
		_populate_section()


func _on_boost_toggle(boost_id: String) -> void:
	audio_manager.play_button_click()
	shop_manager.toggle_boost_selection(boost_id)
	_populate_section()


func _on_crate_buy(crate_type: String) -> void:
	audio_manager.play_button_click()
	if shop_manager.buy_crate(crate_type):
		stats_reload_needed.emit()
		balance_update_needed.emit()
		_populate_section()


func _on_crate_open(crate_type: String) -> void:
	show_roulette(crate_type)


# ========== UTILITIES ==========

func _format_balance(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.1fK" % (amount / 1000.0)
	return str(amount)


func _style_secondary_button(button: Button) -> void:
	button.custom_minimum_size = Vector2(200, 88)
	button.add_theme_font_size_override("font_size", FONT_SIZE_NORMAL)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_LIGHT
	normal.set_corner_radius_all(16)
	normal.set_border_width_all(3)
	normal.border_color = COLOR_BORDER
	normal.content_margin_left = 24
	normal.content_margin_right = 24
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_BG_LIGHT.lightened(0.1)
	hover.set_corner_radius_all(16)
	hover.set_border_width_all(3)
	hover.border_color = COLOR_ACCENT_PRIMARY
	hover.content_margin_left = 24
	hover.content_margin_right = 24
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_ACCENT_PRIMARY)


func _style_shop_button(button: Button, is_active: bool) -> void:
	button.custom_minimum_size = Vector2(140, 72)
	
	var normal := StyleBoxFlat.new()
	var hover := StyleBoxFlat.new()
	
	if is_active:
		normal.bg_color = COLOR_ACCENT_SECONDARY.darkened(0.3)
		normal.border_color = COLOR_ACCENT_SECONDARY
		hover.bg_color = COLOR_ACCENT_SECONDARY.darkened(0.1)
		hover.border_color = COLOR_ACCENT_SECONDARY.lightened(0.2)
	else:
		normal.bg_color = COLOR_BG_LIGHT
		normal.border_color = COLOR_BORDER
		hover.bg_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
		hover.border_color = COLOR_ACCENT_PRIMARY
	
	normal.set_corner_radius_all(12)
	normal.set_border_width_all(3)
	normal.content_margin_left = 16
	normal.content_margin_right = 16
	hover.set_corner_radius_all(12)
	hover.set_border_width_all(3)
	hover.content_margin_left = 16
	hover.content_margin_right = 16
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)

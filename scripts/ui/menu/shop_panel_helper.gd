class_name ShopPanelHelper
extends RefCounted
## Helper class for building and managing the shop panel UI

# Signals for communication with main menu
signal balance_update_needed
signal stats_reload_needed
signal player_model_refresh_needed

# Color palette
const COLOR_BG_DARK := Color(0.06, 0.08, 0.12, 1.0)
const COLOR_BG_MEDIUM := Color(0.10, 0.14, 0.20, 1.0)
const COLOR_BG_LIGHT := Color(0.14, 0.18, 0.26, 1.0)
const COLOR_ACCENT_PRIMARY := Color(0.25, 0.65, 0.96, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.30, 0.85, 0.55, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.7, 0.75, 0.85, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.65, 1.0)
const COLOR_BORDER := Color(0.25, 0.32, 0.45, 0.8)

const SHOP_SECTIONS := ["SKINS", "BOOSTS", "CRATES"]

var shop_panel: Control
var shop_manager: Node
var audio_manager: Node
var stats: Dictionary

var shop_section_index: int = 0
var shop_content_container: Control
var shop_section_label: Label

# Roulette state
var roulette_container: Control
var roulette_hbox: HBoxContainer
var roulette_tween: Tween
var roulette_items: Array = []
var roulette_result: Dictionary = {}
var roulette_crate_type: String = ""
var roulette_last_item_index: int = -1
var roulette_click_sound: AudioStreamPlayer
var roulette_speed_lines: TextureRect


func _init(panel: Control, shop_mgr: Node, audio_mgr: Node, stats_dict: Dictionary) -> void:
	shop_panel = panel
	shop_manager = shop_mgr
	audio_manager = audio_mgr
	stats = stats_dict


func update_stats(new_stats: Dictionary) -> void:
	stats = new_stats


func rebuild() -> void:
	# Clear existing content (except Background) - use free() for immediate removal
	var children_to_remove: Array[Node] = []
	for child in shop_panel.get_children():
		if child.name != "Background":
			children_to_remove.append(child)
	for child in children_to_remove:
		shop_panel.remove_child(child)
		child.free()
	
	# Update background
	var bg: ColorRect = shop_panel.get_node("Background")
	bg.color = Color(0, 0, 0, 0.95)
	
	var screen_size: Vector2 = shop_panel.get_viewport().get_visible_rect().size
	var panel_width: float = minf(720.0, screen_size.x * 0.95)
	var panel_height: float = minf(screen_size.y * 0.92, screen_size.y - 40)
	
	# Create centered VBox for positioning
	var center_vbox := VBoxContainer.new()
	center_vbox.anchors_preset = Control.PRESET_CENTER
	center_vbox.anchor_left = 0.5
	center_vbox.anchor_top = 0.5
	center_vbox.anchor_right = 0.5
	center_vbox.anchor_bottom = 0.5
	center_vbox.offset_left = -panel_width / 2
	center_vbox.offset_right = panel_width / 2
	center_vbox.offset_top = -panel_height / 2
	center_vbox.offset_bottom = panel_height / 2
	center_vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center_vbox.grow_vertical = Control.GROW_DIRECTION_BOTH
	shop_panel.add_child(center_vbox)
	
	# Create main card container
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(panel_width, panel_height)
	
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = COLOR_BG_MEDIUM
	card_style.set_corner_radius_all(24)
	card_style.set_border_width_all(2)
	card_style.border_color = COLOR_ACCENT_GOLD.darkened(0.3)
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	card_style.shadow_size = 20
	card_style.set_content_margin_all(20)
	card.add_theme_stylebox_override("panel", card_style)
	center_vbox.add_child(card)
	
	var inner_vbox := VBoxContainer.new()
	inner_vbox.add_theme_constant_override("separation", 10)
	card.add_child(inner_vbox)
	
	# Title with gold glow
	var title := Label.new()
	title.text = "SHOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	title.add_theme_color_override("font_outline_color", COLOR_ACCENT_GOLD.darkened(0.3))
	title.add_theme_constant_override("outline_size", 2)
	inner_vbox.add_child(title)
	
	# Balance display in shop
	var balance_row := HBoxContainer.new()
	balance_row.alignment = BoxContainer.ALIGNMENT_CENTER
	balance_row.add_theme_constant_override("separation", 10)
	inner_vbox.add_child(balance_row)
	
	var coin_icon := TextureRect.new()
	coin_icon.texture = load("res://assets/svg/coin.svg")
	coin_icon.custom_minimum_size = Vector2(28, 28)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = COLOR_ACCENT_GOLD
	balance_row.add_child(coin_icon)
	
	var shop_balance_label := Label.new()
	shop_balance_label.name = "ShopBalanceLabel"
	shop_balance_label.text = _format_balance(stats.get("coin_balance", 0))
	shop_balance_label.add_theme_font_size_override("font_size", 28)
	shop_balance_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	balance_row.add_child(shop_balance_label)
	
	# Section Navigation
	var nav_container := HBoxContainer.new()
	nav_container.alignment = BoxContainer.ALIGNMENT_CENTER
	nav_container.add_theme_constant_override("separation", 15)
	inner_vbox.add_child(nav_container)
	
	var prev_btn := _create_nav_button("<")
	prev_btn.name = "PrevButton"
	prev_btn.pressed.connect(_on_section_prev)
	nav_container.add_child(prev_btn)
	
	shop_section_label = Label.new()
	shop_section_label.text = SHOP_SECTIONS[shop_section_index]
	shop_section_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_section_label.custom_minimum_size = Vector2(140, 40)
	shop_section_label.add_theme_font_size_override("font_size", 24)
	shop_section_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	nav_container.add_child(shop_section_label)
	
	var next_btn := _create_nav_button(">")
	next_btn.name = "NextButton"
	next_btn.pressed.connect(_on_section_next)
	nav_container.add_child(next_btn)
	
	# Content area
	var scroll := ScrollContainer.new()
	var scroll_height: float = maxf(400.0, screen_size.y * 0.55)
	scroll.custom_minimum_size = Vector2(panel_width - 50, scroll_height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inner_vbox.add_child(scroll)
	
	shop_content_container = VBoxContainer.new()
	shop_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shop_content_container.add_theme_constant_override("separation", 12)
	scroll.add_child(shop_content_container)
	
	_populate_section()
	
	# Back Button
	var back_btn := Button.new()
	back_btn.name = "BackButton"
	back_btn.text = "BACK"
	back_btn.custom_minimum_size = Vector2(180, 50)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.add_theme_font_size_override("font_size", 20)
	_style_secondary_button(back_btn)
	inner_vbox.add_child(back_btn)


func get_back_button() -> Button:
	return shop_panel.find_child("BackButton", true, false) as Button


func update_balance() -> void:
	var label := shop_panel.find_child("ShopBalanceLabel", true, false)
	if label and label is Label:
		label.text = _format_balance(stats.get("coin_balance", 0))


func _on_section_prev() -> void:
	shop_section_index = (shop_section_index - 1 + SHOP_SECTIONS.size()) % SHOP_SECTIONS.size()
	_update_section_display()


func _on_section_next() -> void:
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
	model_header.add_theme_font_size_override("font_size", 20)
	model_header.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	shop_content_container.add_child(model_header)
	
	var model_skins := ["player_1", "player_2", "player_3", "player_4", "player_5", "player_6", "player_7", "player_8", "player_9"]
	for skin_id in model_skins:
		var card := _create_skin_card(skin_id, false)
		shop_content_container.add_child(card)
	
	# Texture skins from crates
	var texture_header := Label.new()
	texture_header.text = "SPECIAL SKINS (from crates)"
	texture_header.add_theme_font_size_override("font_size", 20)
	texture_header.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	shop_content_container.add_child(texture_header)
	
	var texture_skins: Array = shop_manager.available_texture_skins
	if texture_skins.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No special skins available yet"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
		shop_content_container.add_child(empty_label)
	else:
		for skin_id in texture_skins:
			var card := _create_skin_card(skin_id, true)
			shop_content_container.add_child(card)


func _create_skin_card(skin_id: String, is_texture: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 80)
	
	var is_owned: bool = shop_manager.is_skin_owned(skin_id)
	var is_selected: bool = shop_manager.get_selected_skin() == skin_id
	var price: int = shop_manager.get_skin_price(skin_id)
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	if is_selected:
		style.border_color = COLOR_ACCENT_SECONDARY
	elif is_owned:
		style.border_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	else:
		style.border_color = COLOR_BORDER
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	card.add_child(hbox)
	
	# Texture preview for texture skins (clipped, enlarged 130%)
	if is_texture:
		var texture_path := "res://assets/skins/%s.png" % skin_id
		if ResourceLoader.exists(texture_path):
			var clip_container := Control.new()
			clip_container.clip_contents = true
			clip_container.custom_minimum_size = Vector2(56, 56)
			hbox.add_child(clip_container)
			
			var preview := TextureRect.new()
			preview.texture = load(texture_path)
			# 250% of container size
			var enlarged_size := 140.0
			var offset := (enlarged_size - 56.0) / 2.0
			preview.custom_minimum_size = Vector2(enlarged_size, enlarged_size)
			preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			preview.position = Vector2(-offset, -offset)
			clip_container.add_child(preview)
	
	# Skin name
	var name_vbox := VBoxContainer.new()
	name_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(name_vbox)
	
	var display_name := skin_id.replace("_", " ").capitalize()
	if is_texture:
		display_name += " ★"
	
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY if is_owned else COLOR_TEXT_MUTED)
	name_vbox.add_child(name_label)
	
	# Status or price
	var status_label := Label.new()
	if is_selected:
		status_label.text = "EQUIPPED"
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_SECONDARY)
	elif is_owned:
		status_label.text = "OWNED"
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_PRIMARY)
	elif is_texture:
		status_label.text = "CRATE ONLY"
		status_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	else:
		status_label.text = "%s coins" % _format_balance(price)
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	status_label.add_theme_font_size_override("font_size", 14)
	name_vbox.add_child(status_label)
	
	# Action button
	var action_btn := Button.new()
	action_btn.custom_minimum_size = Vector2(100, 40)
	
	if is_selected:
		action_btn.text = "SELECTED"
		action_btn.disabled = true
	elif is_owned:
		action_btn.text = "SELECT"
		action_btn.pressed.connect(_on_skin_select.bind(skin_id))
	elif not is_texture and price > 0:
		action_btn.text = "BUY"
		action_btn.pressed.connect(_on_skin_buy.bind(skin_id))
	else:
		action_btn.text = "LOCKED"
		action_btn.disabled = true
	
	_style_shop_button(action_btn, is_owned and not is_selected)
	hbox.add_child(action_btn)
	
	return card


func _populate_boosts_section() -> void:
	if not shop_manager:
		return
	
	# Selected boosts info
	var selected: Array = shop_manager.get_selected_boosts()
	var selected_label := Label.new()
	selected_label.text = "Selected for next game: %d/2" % selected.size()
	selected_label.add_theme_font_size_override("font_size", 18)
	selected_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	selected_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_content_container.add_child(selected_label)
	
	# Boost cards
	var boost_ids: Array = shop_manager.BOOST_PRICES.keys()
	for boost_id in boost_ids:
		var card := _create_boost_card(boost_id)
		shop_content_container.add_child(card)


func _create_boost_card(boost_id: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 90)
	
	var owned_count: int = shop_manager.get_boost_count(boost_id)
	var is_selected: bool = shop_manager.is_boost_selected(boost_id)
	var price: int = shop_manager.BOOST_PRICES.get(boost_id, 0)
	var display_name: String = shop_manager.BOOST_NAMES.get(boost_id, boost_id)
	var icon_path: String = shop_manager.BOOST_ICONS.get(boost_id, "")
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	if is_selected:
		style.border_color = COLOR_ACCENT_SECONDARY
	elif owned_count > 0:
		style.border_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	else:
		style.border_color = COLOR_BORDER
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	card.add_child(hbox)
	
	# Icon
	if icon_path and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(72, 72)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon)
	
	# Info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	info_vbox.add_child(name_label)
	
	var owned_label := Label.new()
	owned_label.text = "Owned: %d" % owned_count
	owned_label.add_theme_font_size_override("font_size", 14)
	owned_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY if owned_count > 0 else COLOR_TEXT_MUTED)
	info_vbox.add_child(owned_label)
	
	var price_label := Label.new()
	price_label.text = "%s coins" % _format_balance(price)
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	info_vbox.add_child(price_label)
	
	# Buttons
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(btn_vbox)
	
	# Select/deselect button
	var select_btn := Button.new()
	select_btn.custom_minimum_size = Vector2(90, 32)
	if is_selected:
		select_btn.text = "REMOVE"
		select_btn.pressed.connect(_on_boost_toggle.bind(boost_id))
	elif owned_count > 0:
		select_btn.text = "USE"
		select_btn.pressed.connect(_on_boost_toggle.bind(boost_id))
	else:
		select_btn.text = "USE"
		select_btn.disabled = true
	_style_shop_button(select_btn, is_selected)
	btn_vbox.add_child(select_btn)
	
	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "BUY"
	buy_btn.custom_minimum_size = Vector2(90, 32)
	buy_btn.pressed.connect(_on_boost_buy.bind(boost_id))
	_style_shop_button(buy_btn, false)
	btn_vbox.add_child(buy_btn)
	
	return card


func _populate_crates_section() -> void:
	if not shop_manager:
		return
	
	var crate_types := ["basic", "premium", "legendary"]
	for crate_type in crate_types:
		var card := _create_crate_card(crate_type)
		shop_content_container.add_child(card)


func _create_crate_card(crate_type: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(0, 120)
	
	var owned_count: int = shop_manager.get_crate_count(crate_type)
	var price: int = shop_manager.CRATE_PRICES.get(crate_type, 0)
	var display_name: String = shop_manager.CRATE_NAMES.get(crate_type, crate_type)
	var icon_path: String = shop_manager.CRATE_ICONS.get(crate_type, "")
	var chances: Dictionary = shop_manager.CRATE_DROP_CHANCES.get(crate_type, {})
	
	var accent_color := COLOR_TEXT_SECONDARY
	match crate_type:
		"basic":
			accent_color = Color(0.7, 0.7, 0.7)
		"premium":
			accent_color = COLOR_ACCENT_PRIMARY
		"legendary":
			accent_color = COLOR_ACCENT_GOLD
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(14)
	style.set_border_width_all(2)
	style.border_color = accent_color.darkened(0.3)
	style.set_content_margin_all(12)
	card.add_theme_stylebox_override("panel", style)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 15)
	card.add_child(hbox)
	
	# Icon
	if icon_path and ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon)
	
	# Info
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	
	var name_label := Label.new()
	name_label.text = display_name
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", accent_color)
	info_vbox.add_child(name_label)
	
	var owned_label := Label.new()
	owned_label.text = "Owned: %d" % owned_count
	owned_label.add_theme_font_size_override("font_size", 14)
	owned_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	info_vbox.add_child(owned_label)
	
	# Drop chances
	var chances_label := Label.new()
	chances_label.text = "Boost: %.0f%% | Crate: %.0f%% | Skin: %.0f%%" % [
		chances.get("boost", 0) * 100,
		chances.get("crate", 0) * 100,
		chances.get("skin", 0) * 100
	]
	chances_label.add_theme_font_size_override("font_size", 12)
	chances_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	info_vbox.add_child(chances_label)
	
	var price_label := Label.new()
	price_label.text = "%s coins" % _format_balance(price)
	price_label.add_theme_font_size_override("font_size", 14)
	price_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	info_vbox.add_child(price_label)
	
	# Buttons
	var btn_vbox := VBoxContainer.new()
	btn_vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(btn_vbox)
	
	# Open button
	var open_btn := Button.new()
	open_btn.text = "OPEN"
	open_btn.custom_minimum_size = Vector2(90, 36)
	open_btn.disabled = owned_count <= 0
	open_btn.pressed.connect(_on_crate_open.bind(crate_type))
	_style_shop_button(open_btn, owned_count > 0)
	btn_vbox.add_child(open_btn)
	
	# Buy button
	var buy_btn := Button.new()
	buy_btn.text = "BUY"
	buy_btn.custom_minimum_size = Vector2(90, 36)
	buy_btn.pressed.connect(_on_crate_buy.bind(crate_type))
	_style_shop_button(buy_btn, false)
	btn_vbox.add_child(buy_btn)
	
	return card


# ========== ROULETTE ==========

func show_roulette(crate_type: String) -> void:
	roulette_crate_type = crate_type
	roulette_items = shop_manager.generate_roulette_items(crate_type, 35)
	
	# Create roulette overlay
	roulette_container = Control.new()
	roulette_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(roulette_container)
	
	# Dark background
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.9)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	roulette_container.add_child(bg)
	
	# Center container
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.anchor_left = 0.5
	center.anchor_right = 0.5
	center.anchor_top = 0.5
	center.anchor_bottom = 0.5
	center.offset_left = -300
	center.offset_right = 300
	center.offset_top = -150
	center.offset_bottom = 150
	center.add_theme_constant_override("separation", 20)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	roulette_container.add_child(center)
	
	# Title
	var title := Label.new()
	title.text = "OPENING %s" % shop_manager.CRATE_NAMES.get(crate_type, "Crate").to_upper()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	center.add_child(title)
	
	# Roulette window with mask - fixed width, centered in VBox
	var window_wrapper := CenterContainer.new()
	center.add_child(window_wrapper)
	
	var window_container := Control.new()
	window_container.custom_minimum_size = Vector2(520, 160)
	window_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	window_container.clip_contents = true
	window_wrapper.add_child(window_container)
	
	# Background glow effect
	var bg_glow := ColorRect.new()
	bg_glow.color = Color(0.05, 0.08, 0.15, 1.0)
	bg_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	window_container.add_child(bg_glow)
	
	# Add decorative frame
	var frame_texture := TextureRect.new()
	if ResourceLoader.exists("res://assets/svg/roulette_frame.svg"):
		frame_texture.texture = load("res://assets/svg/roulette_frame.svg")
	frame_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_texture.stretch_mode = TextureRect.STRETCH_SCALE
	frame_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_texture.z_index = 5
	window_container.add_child(frame_texture)
	
	# Items container - centered vertically
	roulette_hbox = HBoxContainer.new()
	roulette_hbox.add_theme_constant_override("separation", 10)
	roulette_hbox.position = Vector2(0, 28)
	window_container.add_child(roulette_hbox)
	
	# Center marker - fancy gold crystal pointer (on top)
	var marker_container := Control.new()
	marker_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	marker_container.anchor_left = 0.5
	marker_container.anchor_right = 0.5
	marker_container.offset_left = -24
	marker_container.offset_right = 24
	marker_container.offset_top = -8
	marker_container.offset_bottom = 64
	marker_container.z_index = 15
	window_container.add_child(marker_container)
	
	# Marker glow (pulsing)
	var marker_glow := TextureRect.new()
	if ResourceLoader.exists("res://assets/svg/roulette_glow.svg"):
		marker_glow.texture = load("res://assets/svg/roulette_glow.svg")
	marker_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker_glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	marker_glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_glow.modulate.a = 0.6
	marker_container.add_child(marker_glow)
	_animate_marker_glow(marker_glow)
	
	var marker_texture := TextureRect.new()
	if ResourceLoader.exists("res://assets/svg/roulette_indicator.svg"):
		marker_texture.texture = load("res://assets/svg/roulette_indicator.svg")
	marker_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	marker_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker_container.add_child(marker_texture)
	
	# Speed lines effect (visible during fast phase)
	roulette_speed_lines = TextureRect.new()
	if ResourceLoader.exists("res://assets/svg/roulette_speed_lines.svg"):
		roulette_speed_lines.texture = load("res://assets/svg/roulette_speed_lines.svg")
	roulette_speed_lines.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	roulette_speed_lines.stretch_mode = TextureRect.STRETCH_SCALE
	roulette_speed_lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	roulette_speed_lines.modulate.a = 0.0
	roulette_speed_lines.z_index = 3
	window_container.add_child(roulette_speed_lines)
	
	# Populate items
	for i in range(roulette_items.size()):
		var item := _create_roulette_item(roulette_items[i])
		roulette_hbox.add_child(item)
	
	# Start animation
	_animate_roulette()


func _create_roulette_item(item_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	# Fixed size for all items - MUST be consistent
	panel.custom_minimum_size = Vector2(90, 100)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	var style := StyleBoxFlat.new()
	var border_color := COLOR_BORDER
	var bg_color := COLOR_BG_DARK
	
	# Set colors based on rarity/type
	match item_data.get("type", ""):
		"boost":
			border_color = COLOR_ACCENT_PRIMARY
			bg_color = Color(COLOR_ACCENT_PRIMARY.r, COLOR_ACCENT_PRIMARY.g, COLOR_ACCENT_PRIMARY.b, 0.15)
		"crate":
			border_color = COLOR_ACCENT_SECONDARY
			bg_color = Color(COLOR_ACCENT_SECONDARY.r, COLOR_ACCENT_SECONDARY.g, COLOR_ACCENT_SECONDARY.b, 0.15)
		"skin":
			border_color = COLOR_ACCENT_GOLD
			bg_color = Color(COLOR_ACCENT_GOLD.r, COLOR_ACCENT_GOLD.g, COLOR_ACCENT_GOLD.b, 0.2)
	
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_corner_radius_all(10)
	style.set_border_width_all(3)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)
	
	# Use Control for fixed layout instead of VBoxContainer
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(content)
	
	# Icon - fixed position in top area
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
		# Clipped container for texture skins (130% enlarged, clipped)
		var clip_container := Control.new()
		clip_container.clip_contents = true
		clip_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
		clip_container.offset_left = -24
		clip_container.offset_right = 24
		clip_container.offset_top = 4
		clip_container.offset_bottom = 52
		content.add_child(clip_container)
		
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		# 250% of container size (48 * 2.5 = 120)
		var enlarged_size := 120.0
		var offset := (enlarged_size - 48.0) / 2.0
		icon.custom_minimum_size = Vector2(enlarged_size, enlarged_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.position = Vector2(-offset, -offset)
		clip_container.add_child(icon)
	else:
		var icon := TextureRect.new()
		if icon_path and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		# Center icon horizontally, place at top
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.offset_left = -24
		icon.offset_right = 24
		icon.offset_top = 4
		icon.offset_bottom = 52
		content.add_child(icon)
	
	# Name label - fixed position at bottom
	var name_label := Label.new()
	var item_name := ""
	match item_data.get("type", ""):
		"boost":
			item_name = shop_manager.BOOST_NAMES.get(item_data.get("id", ""), item_data.get("id", ""))
		"crate":
			item_name = shop_manager.CRATE_NAMES.get(item_data.get("id", ""), item_data.get("id", ""))
		"skin":
			item_name = item_data.get("id", "Skin").replace("_", " ").capitalize()
	
	# Truncate long names
	if item_name.length() > 12:
		item_name = item_name.substr(0, 10) + ".."
	
	name_label.text = item_name
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Position at bottom
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -28
	name_label.offset_bottom = 0
	name_label.offset_left = 2
	name_label.offset_right = -2
	content.add_child(name_label)
	
	return panel


func _animate_marker_glow(glow: TextureRect) -> void:
	# Create pulsing glow animation
	var tween := shop_panel.create_tween()
	tween.set_loops()
	tween.tween_property(glow, "modulate:a", 0.9, 0.8).set_trans(Tween.TRANS_SINE)
	tween.tween_property(glow, "modulate:a", 0.4, 0.8).set_trans(Tween.TRANS_SINE)


func _add_win_sparkles(container: Control) -> void:
	# Add floating sparkle particles
	var sparkle_positions := [
		Vector2(-150, -100), Vector2(150, -100),
		Vector2(-180, 50), Vector2(180, 50),
		Vector2(-100, -150), Vector2(100, -150),
		Vector2(-120, 100), Vector2(120, 100),
	]
	
	for i in range(sparkle_positions.size()):
		var sparkle := TextureRect.new()
		if ResourceLoader.exists("res://assets/svg/roulette_sparkle.svg"):
			sparkle.texture = load("res://assets/svg/roulette_sparkle.svg")
		sparkle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sparkle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sparkle.custom_minimum_size = Vector2(24, 24)
		sparkle.set_anchors_preset(Control.PRESET_CENTER)
		sparkle.anchor_left = 0.5
		sparkle.anchor_right = 0.5
		sparkle.anchor_top = 0.5
		sparkle.anchor_bottom = 0.5
		sparkle.offset_left = sparkle_positions[i].x - 12
		sparkle.offset_right = sparkle_positions[i].x + 12
		sparkle.offset_top = sparkle_positions[i].y - 12
		sparkle.offset_bottom = sparkle_positions[i].y + 12
		sparkle.modulate.a = 0.0
		sparkle.pivot_offset = Vector2(12, 12)
		container.add_child(sparkle)
		
		# Animate each sparkle with delay - fade in, rotate, fade out
		var delay := float(i) * 0.15
		var sparkle_tween := shop_panel.create_tween()
		sparkle_tween.tween_interval(delay)
		sparkle_tween.tween_property(sparkle, "modulate:a", 1.0, 0.3)
		sparkle_tween.tween_property(sparkle, "modulate:a", 0.0, 0.5)
		sparkle_tween.tween_callback(sparkle.queue_free)
		
		# Rotation animation (different speeds for variety)
		var rotation_speed := 1.5 + randf() * 1.5  # 1.5-3.0 seconds per rotation
		var rotation_dir := 1.0 if i % 2 == 0 else -1.0  # Alternate direction
		var rotate_tween := shop_panel.create_tween()
		rotate_tween.tween_interval(delay)
		rotate_tween.tween_property(sparkle, "rotation", rotation_dir * TAU, rotation_speed).from(0.0)


func _animate_win_label(label: Label) -> void:
	# Bounce and scale animation for win label
	label.pivot_offset = label.size / 2
	label.scale = Vector2(0.3, 0.3)
	label.modulate.a = 0.0
	
	var tween := shop_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2(1.2, 1.2), 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 1.0, 0.2)
	tween.chain().tween_property(label, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_SINE)
	
	# Continuous subtle pulse
	var pulse_tween := shop_panel.create_tween()
	pulse_tween.set_loops()
	pulse_tween.set_delay(0.5)
	pulse_tween.tween_property(label, "scale", Vector2(1.05, 1.05), 0.6).set_trans(Tween.TRANS_SINE)
	pulse_tween.tween_property(label, "scale", Vector2(1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)


func _animate_roulette() -> void:
	var winning_index := 25
	var window_width := 520.0
	var window_center := window_width / 2.0
	
	roulette_hbox.position.x = window_width
	roulette_last_item_index = -1
	
	# Setup click sound
	_setup_roulette_click_sound()
	
	# Get the actual result
	roulette_result = shop_manager.open_crate(roulette_crate_type)
	
	# Update winning item with result
	if roulette_hbox.get_child_count() > winning_index:
		var winning_panel_update: PanelContainer = roulette_hbox.get_child(winning_index)
		_update_roulette_item(winning_panel_update, roulette_result)
	
	# Wait for layout to be fully calculated
	await shop_panel.get_tree().process_frame
	await shop_panel.get_tree().process_frame
	await shop_panel.get_tree().process_frame
	
	# Calculate target position using precise item geometry
	# Each item: 90px wide + 10px separation = 100px step
	# Item N center = N * 100 + 45
	var item_size := 90.0
	var separation := 10.0
	var item_step := item_size + separation
	var item_center := float(winning_index) * item_step + (item_size / 2.0)
	var target_x := window_center - item_center
	
	# Connect to process for click sounds
	if not shop_panel.get_tree().process_frame.is_connected(_on_roulette_process):
		shop_panel.get_tree().process_frame.connect(_on_roulette_process)
	
	# Speed lines animation - show during fast phase, fade out during slow phase
	if roulette_speed_lines:
		var speed_tween := shop_panel.create_tween()
		speed_tween.tween_property(roulette_speed_lines, "modulate:a", 0.7, 0.3)
		speed_tween.tween_interval(0.9)
		speed_tween.tween_property(roulette_speed_lines, "modulate:a", 0.0, 1.5)
	
	# Animate with multiple phases for more dynamic feel
	roulette_tween = shop_panel.create_tween()
	
	# Phase 1: Fast acceleration
	roulette_tween.set_ease(Tween.EASE_IN)
	roulette_tween.set_trans(Tween.TRANS_QUAD)
	var midpoint := (window_width + target_x) * 0.4
	roulette_tween.tween_property(roulette_hbox, "position:x", midpoint, 1.2)
	
	# Phase 2: Slow deceleration to final position
	roulette_tween.set_ease(Tween.EASE_OUT)
	roulette_tween.set_trans(Tween.TRANS_QUINT)
	roulette_tween.tween_property(roulette_hbox, "position:x", target_x, 2.8)
	
	# Highlight winning item at the end
	roulette_tween.tween_callback(_highlight_winning_item.bind(winning_index))
	roulette_tween.tween_interval(0.8)
	roulette_tween.tween_callback(_on_roulette_finished)


func _highlight_winning_item(index: int) -> void:
	if not roulette_hbox or index < 0 or index >= roulette_hbox.get_child_count():
		return
	
	var winning_item: PanelContainer = roulette_hbox.get_child(index)
	
	# Add golden highlight overlay
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
	
	# Pulse and scale animation
	winning_item.pivot_offset = winning_item.size / 2
	
	var tween := shop_panel.create_tween()
	tween.set_parallel(true)
	tween.tween_property(highlight, "modulate:a", 1.0, 0.3)
	tween.tween_property(winning_item, "scale", Vector2(1.15, 1.15), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	tween.chain().tween_property(winning_item, "scale", Vector2(1.1, 1.1), 0.15)
	
	# Continuous glow pulse
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
	
	# Use Control for fixed layout
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(content)
	
	# Icon - fixed position
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
		# Clipped container for texture skins (130% enlarged, clipped)
		var clip_container := Control.new()
		clip_container.clip_contents = true
		clip_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
		clip_container.offset_left = -24
		clip_container.offset_right = 24
		clip_container.offset_top = 4
		clip_container.offset_bottom = 52
		content.add_child(clip_container)
		
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		# 250% of container size
		var enlarged_size := 120.0
		var offset := (enlarged_size - 48.0) / 2.0
		icon.custom_minimum_size = Vector2(enlarged_size, enlarged_size)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.position = Vector2(-offset, -offset)
		clip_container.add_child(icon)
	else:
		var icon := TextureRect.new()
		if icon_path and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_preset(Control.PRESET_CENTER_TOP)
		icon.offset_left = -24
		icon.offset_right = 24
		icon.offset_top = 4
		icon.offset_bottom = 52
		content.add_child(icon)
	
	# Name label - fixed at bottom
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
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_label.offset_top = -28
	name_label.offset_bottom = 0
	name_label.offset_left = 2
	name_label.offset_right = -2
	content.add_child(name_label)


func _on_roulette_finished() -> void:
	# Stop click sound tracking
	if shop_panel.get_tree().process_frame.is_connected(_on_roulette_process):
		shop_panel.get_tree().process_frame.disconnect(_on_roulette_process)
	
	# Wait and show result
	var timer := shop_panel.get_tree().create_timer(1.0)
	await timer.timeout
	
	if roulette_container:
		for child in roulette_container.get_children():
			if child != roulette_container.get_child(0):
				child.queue_free()
		
		# Win burst background effect
		var burst_container := Control.new()
		burst_container.set_anchors_preset(Control.PRESET_CENTER)
		burst_container.anchor_left = 0.5
		burst_container.anchor_right = 0.5
		burst_container.anchor_top = 0.5
		burst_container.anchor_bottom = 0.5
		burst_container.offset_left = -200
		burst_container.offset_right = 200
		burst_container.offset_top = -200
		burst_container.offset_bottom = 200
		burst_container.z_index = -1
		roulette_container.add_child(burst_container)
		
		var burst_texture := TextureRect.new()
		if ResourceLoader.exists("res://assets/svg/roulette_win_burst.svg"):
			burst_texture.texture = load("res://assets/svg/roulette_win_burst.svg")
		burst_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		burst_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		burst_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
		burst_texture.modulate.a = 0.0
		burst_container.add_child(burst_texture)
		
		# Animate burst - fade in and rotate
		var burst_tween := shop_panel.create_tween()
		burst_tween.set_parallel(true)
		burst_tween.tween_property(burst_texture, "modulate:a", 0.8, 0.5)
		
		# Continuous rotation for burst
		var burst_rotate_tween := shop_panel.create_tween()
		burst_rotate_tween.set_loops()
		burst_rotate_tween.tween_property(burst_texture, "rotation", TAU, 8.0).from(0.0)
		
		# Add sparkles
		_add_win_sparkles(roulette_container)
		
		# Result display
		var result_vbox := VBoxContainer.new()
		result_vbox.set_anchors_preset(Control.PRESET_CENTER)
		result_vbox.anchor_left = 0.5
		result_vbox.anchor_right = 0.5
		result_vbox.anchor_top = 0.5
		result_vbox.anchor_bottom = 0.5
		result_vbox.offset_left = -180
		result_vbox.offset_right = 180
		result_vbox.offset_top = -180
		result_vbox.offset_bottom = 180
		result_vbox.add_theme_constant_override("separation", 12)
		result_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		roulette_container.add_child(result_vbox)
		
		var win_label := Label.new()
		win_label.text = "YOU WON!"
		win_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		win_label.add_theme_font_size_override("font_size", 32)
		win_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
		result_vbox.add_child(win_label)
		
		# Animate win label (needs to be called after adding to tree)
		win_label.ready.connect(_animate_win_label.bind(win_label))
		
		# Show preview icon/image of the won item
		var preview_container := CenterContainer.new()
		preview_container.custom_minimum_size = Vector2(120, 120)
		result_vbox.add_child(preview_container)
		
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
					result_text = "Duplicate! Refund: %s coins" % _format_balance(roulette_result.get("refund", 0))
					preview_icon_path = "res://assets/svg/coin.svg"
				else:
					var skin_id: String = roulette_result.get("id", "")
					result_text = "%s Skin!" % skin_id.replace("_", " ").capitalize()
					# For texture skins, show the texture image
					preview_icon_path = "res://assets/skins/%s.png" % skin_id
		
		# Create preview visual
		if is_skin and not roulette_result.get("is_duplicate", false):
			# For skins (both texture and model), create 3D preview
			var skin_id: String = roulette_result.get("id", "")
			var texture_path := "res://assets/skins/%s.png" % skin_id
			var has_texture := ResourceLoader.exists(texture_path)
			
			# Use default player model for texture skins, or specific model for model skins
			var model_path := "res://assets/models/players/player_1.blend"
			var specific_model := "res://assets/models/players/%s.blend" % skin_id
			if ResourceLoader.exists(specific_model):
				model_path = specific_model
			
			var preview_3d := _create_skin_preview_3d_with_texture(model_path, texture_path if has_texture else "")
			if preview_3d:
				preview_container.add_child(preview_3d)
		elif preview_icon_path and ResourceLoader.exists(preview_icon_path):
			var preview_icon := TextureRect.new()
			preview_icon.texture = load(preview_icon_path)
			preview_icon.custom_minimum_size = Vector2(100, 100)
			preview_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			preview_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview_container.add_child(preview_icon)
		
		var item_label := Label.new()
		item_label.text = result_text
		item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item_label.add_theme_font_size_override("font_size", 24)
		item_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
		result_vbox.add_child(item_label)
		
		# Close button
		var close_btn := Button.new()
		close_btn.text = "CLOSE"
		close_btn.custom_minimum_size = Vector2(150, 50)
		close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		close_btn.add_theme_font_size_override("font_size", 18)
		_style_secondary_button(close_btn)
		close_btn.pressed.connect(_on_roulette_close)
		result_vbox.add_child(close_btn)


func _create_skin_preview_3d(model_path: String) -> SubViewportContainer:
	return _create_skin_preview_3d_with_texture(model_path, "")


func _create_skin_preview_3d_with_texture(model_path: String, texture_path: String) -> SubViewportContainer:
	# Create a SubViewport with 3D model preview
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(100, 100)
	container.stretch = true
	
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 200)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	
	# Add camera
	var camera := Camera3D.new()
	camera.transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.3, 1.2))
	camera.look_at(Vector3(0, 0.1, 0), Vector3.UP)
	camera.fov = 45
	viewport.add_child(camera)
	
	# Add light
	var light := DirectionalLight3D.new()
	light.transform = Transform3D(Basis.looking_at(Vector3(-1, -1, -1)), Vector3(2, 2, 2))
	light.light_energy = 1.5
	viewport.add_child(light)
	
	# Load and add model
	var model_scene: PackedScene = load(model_path)
	if model_scene:
		var model := model_scene.instantiate()
		model.scale = Vector3(0.4, 0.4, 0.4)
		model.position = Vector3(0, -0.2, 0)
		
		# Apply texture if provided
		if texture_path and ResourceLoader.exists(texture_path):
			var texture: Texture2D = load(texture_path)
			if texture:
				_apply_texture_to_model(model, texture)
		
		_apply_unshaded_to_model(model)
		viewport.add_child(model)
		
		# Rotate model slowly
		var tween := container.create_tween()
		tween.set_loops()
		tween.tween_property(model, "rotation:y", TAU, 4.0).from(0.0)
	
	return container


func _apply_texture_to_model(node: Node, texture: Texture2D) -> void:
	# Find all mesh instances and apply texture
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


func _apply_unshaded_to_model(node: Node) -> void:
	# Find all mesh instances and make them unshaded
	for child in node.get_children():
		_apply_unshaded_to_model(child)
	
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		# Skip if already has override material (texture was applied)
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				if mesh_inst.get_surface_override_material(i) != null:
					return
		
		# Apply unshaded material
		var original_mat: Material = null
		if mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
			original_mat = mesh_inst.mesh.surface_get_material(0)
		
		var unshaded_mat := StandardMaterial3D.new()
		unshaded_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		
		if original_mat and original_mat is StandardMaterial3D:
			var orig_std: StandardMaterial3D = original_mat as StandardMaterial3D
			unshaded_mat.albedo_color = orig_std.albedo_color
			if orig_std.albedo_texture:
				unshaded_mat.albedo_texture = orig_std.albedo_texture
		else:
			unshaded_mat.albedo_color = Color.WHITE
		
		if mesh_inst.mesh:
			for i in range(mesh_inst.mesh.get_surface_count()):
				mesh_inst.set_surface_override_material(i, unshaded_mat)


func _on_roulette_close() -> void:
	# Disconnect process frame if connected
	if shop_panel.get_tree().process_frame.is_connected(_on_roulette_process):
		shop_panel.get_tree().process_frame.disconnect(_on_roulette_process)
	
	# Cleanup click sound
	if roulette_click_sound:
		roulette_click_sound.queue_free()
		roulette_click_sound = null
	
	# Cleanup speed lines reference
	roulette_speed_lines = null
	
	if roulette_container:
		roulette_container.queue_free()
		roulette_container = null
	
	# Signal main menu to refresh
	stats_reload_needed.emit()
	balance_update_needed.emit()
	_populate_section()


func _setup_roulette_click_sound() -> void:
	# Create dedicated audio player for click sounds
	roulette_click_sound = AudioStreamPlayer.new()
	var click_stream := load("res://assets/sounds/ui/click.mp3")
	if click_stream:
		roulette_click_sound.stream = click_stream
		roulette_click_sound.volume_db = -5.0  # Slightly quieter
	shop_panel.add_child(roulette_click_sound)


func _on_roulette_process() -> void:
	if not roulette_hbox or not roulette_tween or not roulette_tween.is_running():
		# Disconnect when animation done
		if shop_panel.get_tree().process_frame.is_connected(_on_roulette_process):
			shop_panel.get_tree().process_frame.disconnect(_on_roulette_process)
		return
	
	# Calculate which item is currently under the indicator (center of 520px window = 260)
	var window_center := 260.0
	var item_size := 90.0
	var separation := 10.0
	var item_step := item_size + separation
	
	# Position in HBox coordinates = window_center - hbox.position.x
	var pos_in_hbox := window_center - roulette_hbox.position.x
	# Which item index contains this position
	var current_item_index := int(pos_in_hbox / item_step)
	
	# Play click and add visual effect when crossing to new item
	if current_item_index != roulette_last_item_index and current_item_index >= 0 and current_item_index < roulette_hbox.get_child_count():
		# Reset previous item scale
		if roulette_last_item_index >= 0 and roulette_last_item_index < roulette_hbox.get_child_count():
			var prev_item: PanelContainer = roulette_hbox.get_child(roulette_last_item_index)
			prev_item.scale = Vector2.ONE
		
		roulette_last_item_index = current_item_index
		
		# Play sound
		if roulette_click_sound:
			roulette_click_sound.play()
		
		# Bounce current item (quick pop effect)
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


func _create_nav_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(50, 44)
	btn.add_theme_font_size_override("font_size", 26)
	
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_LIGHT
	normal.set_corner_radius_all(12)
	normal.set_border_width_all(2)
	normal.border_color = COLOR_BORDER
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_ACCENT_GOLD.darkened(0.3)
	hover.set_corner_radius_all(12)
	hover.set_border_width_all(2)
	hover.border_color = COLOR_ACCENT_GOLD
	
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", hover)
	btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", COLOR_ACCENT_GOLD)
	
	return btn


func _style_secondary_button(button: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_BG_LIGHT
	normal.set_corner_radius_all(14)
	normal.set_border_width_all(2)
	normal.border_color = COLOR_BORDER
	
	var hover := StyleBoxFlat.new()
	hover.bg_color = COLOR_BG_LIGHT.lightened(0.1)
	hover.set_corner_radius_all(14)
	hover.set_border_width_all(2)
	hover.border_color = COLOR_ACCENT_PRIMARY
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_ACCENT_PRIMARY)


func _style_shop_button(button: Button, is_active: bool) -> void:
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
	
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(2)
	hover.set_corner_radius_all(8)
	hover.set_border_width_all(2)
	
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)

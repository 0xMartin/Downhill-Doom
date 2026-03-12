class_name BoostCard
extends PanelContainer
## Card for displaying boosts in the shop

signal boost_toggled(boost_id: String)
signal boost_bought(boost_id: String)

# Colors
const COLOR_ACCENT_PRIMARY := Color(0.28, 0.76, 0.70, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.62, 0.32, 0.82, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.8, 0.85, 0.9, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.6, 1.0)
const COLOR_BG_DARK := Color(0.08, 0.1, 0.14, 1.0)
const COLOR_BORDER := Color(0.3, 0.35, 0.5, 0.6)

var boost_id: String


func setup(p_boost_id: String, display_name: String, icon_path: String, owned_count: int, is_selected: bool, price: int) -> void:
	boost_id = p_boost_id
	
	var icon: TextureRect = get_node("HBox/IconContainer/Icon")
	var name_label: Label = get_node("HBox/InfoVBox/NameLabel")
	var owned_label: Label = get_node("HBox/InfoVBox/OwnedLabel")
	var price_label: Label = get_node("HBox/InfoVBox/PriceLabel")
	var select_btn: Button = get_node("HBox/ButtonVBox/SelectButton")
	var buy_btn: Button = get_node("HBox/ButtonVBox/BuyButton")
	
	# Card style
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(3)
	if is_selected:
		style.border_color = COLOR_ACCENT_SECONDARY
	elif owned_count > 0:
		style.border_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	else:
		style.border_color = COLOR_BORDER
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	
	# Icon
	if icon_path and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	
	# Name
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	
	# Owned count
	owned_label.text = "Owned: %d" % owned_count
	owned_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY if owned_count > 0 else COLOR_TEXT_MUTED)
	
	# Price
	price_label.text = "%s coins" % _format_balance(price)
	price_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	
	# Select button
	if is_selected:
		select_btn.text = "REMOVE"
		select_btn.pressed.connect(_on_toggle_pressed)
	elif owned_count > 0:
		select_btn.text = "USE"
		select_btn.pressed.connect(_on_toggle_pressed)
	else:
		select_btn.text = "USE"
		select_btn.disabled = true
	_style_button(select_btn, is_selected)
	
	# Buy button
	buy_btn.pressed.connect(_on_buy_pressed)
	_style_button(buy_btn, false)


func _on_toggle_pressed() -> void:
	boost_toggled.emit(boost_id)


func _on_buy_pressed() -> void:
	boost_bought.emit(boost_id)


func _style_button(btn: Button, is_active: bool) -> void:
	var btn_style := StyleBoxFlat.new()
	btn_style.set_corner_radius_all(12)
	btn_style.set_content_margin_all(8)
	
	if btn.disabled:
		btn_style.bg_color = Color(0.15, 0.18, 0.22, 1.0)
		btn.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	elif is_active:
		btn_style.bg_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
		btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	else:
		btn_style.bg_color = Color(0.2, 0.24, 0.32, 1.0)
		btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	
	btn.add_theme_stylebox_override("normal", btn_style)
	btn.add_theme_stylebox_override("hover", btn_style)
	btn.add_theme_stylebox_override("pressed", btn_style)
	btn.add_theme_stylebox_override("disabled", btn_style)


func _format_balance(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.1fk" % (amount / 1000.0)
	return str(amount)

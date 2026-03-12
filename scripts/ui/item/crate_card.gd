class_name CrateCard
extends PanelContainer
## Card for displaying crates in the shop

signal crate_opened(crate_type: String)
signal crate_bought(crate_type: String)

# Colors
const COLOR_ACCENT_PRIMARY := Color(0.28, 0.76, 0.70, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.8, 0.85, 0.9, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.6, 1.0)
const COLOR_BG_DARK := Color(0.08, 0.1, 0.14, 1.0)

var crate_type: String


func setup(p_crate_type: String, display_name: String, icon_path: String, owned_count: int, chances: Dictionary, price: int) -> void:
	crate_type = p_crate_type
	
	var icon: TextureRect = get_node("HBox/IconContainer/Icon")
	var name_label: Label = get_node("HBox/InfoVBox/NameLabel")
	var owned_label: Label = get_node("HBox/InfoVBox/OwnedLabel")
	var chances_label: Label = get_node("HBox/InfoVBox/ChancesLabel")
	var price_label: Label = get_node("HBox/InfoVBox/PriceLabel")
	var open_btn: Button = get_node("HBox/ButtonVBox/OpenButton")
	var buy_btn: Button = get_node("HBox/ButtonVBox/BuyButton")
	
	# Crate type accent color
	var accent_color := COLOR_TEXT_SECONDARY
	match p_crate_type:
		"basic":
			accent_color = Color(0.7, 0.7, 0.7)  # Neutral gray
		"premium":
			accent_color = COLOR_ACCENT_PRIMARY   # Teal
		"legendary":
			accent_color = COLOR_ACCENT_GOLD      # Gold
	
	# Card style
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(3)
	style.border_color = accent_color.darkened(0.3)
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	
	# Icon
	if icon_path and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	
	# Name
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", accent_color)
	
	# Owned count
	owned_label.text = "Owned: %d" % owned_count
	owned_label.add_theme_color_override("font_color", COLOR_TEXT_SECONDARY)
	
	# Drop chances
	chances_label.text = "Boost: %.0f%% | Crate: %.0f%% | Skin: %.0f%%" % [
		chances.get("boost", 0) * 100,
		chances.get("crate", 0) * 100,
		chances.get("skin", 0) * 100
	]
	chances_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	
	# Price
	price_label.text = "%s coins" % _format_balance(price)
	price_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	
	# Open button
	open_btn.disabled = owned_count <= 0
	open_btn.pressed.connect(_on_open_pressed)
	_style_button(open_btn, owned_count > 0)
	
	# Buy button
	buy_btn.pressed.connect(_on_buy_pressed)
	_style_button(buy_btn, false)


func _on_open_pressed() -> void:
	crate_opened.emit(crate_type)


func _on_buy_pressed() -> void:
	crate_bought.emit(crate_type)


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

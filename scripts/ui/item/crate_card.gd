class_name CrateCard
extends PanelContainer
## Card for displaying crates in the shop

signal crate_opened(crate_type: String)
signal crate_bought(crate_type: String)

# Colors
const COLOR_ACCENT_PRIMARY := Color(0.28, 0.76, 0.70, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.8, 0.85, 0.9, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.6, 1.0)

var crate_type: String


func setup(p_crate_type: String, display_name: String, icon_path: String, owned_count: int, chances: Dictionary, price: int) -> void:
	crate_type = p_crate_type
	
	var icon: TextureRect = get_node("MainVBox/TopHBox/IconContainer/Icon")
	var name_label: Label = get_node("MainVBox/TopHBox/InfoVBox/NameLabel")
	var owned_label: Label = get_node("MainVBox/TopHBox/InfoVBox/OwnedLabel")
	var chances_label: Label = get_node("MainVBox/ChancesLabel")
	var price_label: Label = get_node("MainVBox/TopHBox/InfoVBox/PriceLabel")
	var open_btn: Button = get_node("MainVBox/TopHBox/ButtonVBox/OpenButton")
	var buy_btn: Button = get_node("MainVBox/TopHBox/ButtonVBox/BuyButton")
	
	# Crate type accent color
	var accent_color := COLOR_TEXT_SECONDARY
	match p_crate_type:
		"basic":
			accent_color = Color(0.7, 0.7, 0.7)  # Neutral gray
		"premium":
			accent_color = COLOR_ACCENT_PRIMARY   # Teal
		"legendary":
			accent_color = COLOR_ACCENT_GOLD      # Gold
	
	# Card border color only (keeps scene-defined shape/size)
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	style.border_color = accent_color.darkened(0.3)
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
	
	# Open button - state only
	open_btn.disabled = owned_count <= 0
	open_btn.pressed.connect(_on_open_pressed)
	
	# Buy button
	buy_btn.pressed.connect(_on_buy_pressed)


func _on_open_pressed() -> void:
	crate_opened.emit(crate_type)


func _on_buy_pressed() -> void:
	crate_bought.emit(crate_type)


func _format_balance(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.1fk" % (amount / 1000.0)
	return str(amount)

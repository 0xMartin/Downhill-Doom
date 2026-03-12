class_name ModelSkinCard
extends PanelContainer
## Card for displaying model skins in the shop

signal skin_selected(skin_id: String)
signal skin_bought(skin_id: String)

# Colors
const COLOR_ACCENT_PRIMARY := Color(0.28, 0.76, 0.70, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.62, 0.32, 0.82, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.6, 1.0)
const COLOR_BG_DARK := Color(0.08, 0.1, 0.14, 1.0)
const COLOR_BORDER := Color(0.3, 0.35, 0.5, 0.6)

var skin_id: String


func setup(p_skin_id: String, display_name: String, is_owned: bool, is_selected: bool, price: int) -> void:
	skin_id = p_skin_id
	
	var name_label: Label = get_node("HBox/NameVBox/NameLabel")
	var status_label: Label = get_node("HBox/NameVBox/StatusLabel")
	var action_btn: Button = get_node("HBox/ActionButton")
	
	# Card style
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_DARK
	style.set_corner_radius_all(16)
	style.set_border_width_all(3)
	if is_selected:
		style.border_color = COLOR_ACCENT_SECONDARY
	elif is_owned:
		style.border_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	else:
		style.border_color = COLOR_BORDER
	style.set_content_margin_all(16)
	add_theme_stylebox_override("panel", style)
	
	# Name
	name_label.text = display_name
	name_label.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY if is_owned else COLOR_TEXT_MUTED)
	
	# Status
	if is_selected:
		status_label.text = "EQUIPPED"
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_SECONDARY)
	elif is_owned:
		status_label.text = "OWNED"
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_PRIMARY)
	else:
		status_label.text = "%s coins" % _format_balance(price)
		status_label.add_theme_color_override("font_color", COLOR_ACCENT_GOLD)
	
	# Action button
	if is_selected:
		action_btn.text = "SELECTED"
		action_btn.disabled = true
	elif is_owned:
		action_btn.text = "SELECT"
		action_btn.pressed.connect(_on_select_pressed)
	elif price > 0:
		action_btn.text = "BUY"
		action_btn.pressed.connect(_on_buy_pressed)
	else:
		action_btn.text = "LOCKED"
		action_btn.disabled = true
	
	_style_button(action_btn, is_owned and not is_selected)


func _on_select_pressed() -> void:
	skin_selected.emit(skin_id)


func _on_buy_pressed() -> void:
	skin_bought.emit(skin_id)


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

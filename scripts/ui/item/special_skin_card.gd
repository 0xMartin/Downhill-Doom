class_name SpecialSkinCard
extends PanelContainer
## Card for displaying special/texture skins in the shop (with texture preview)

signal skin_selected(skin_id: String)

# Colors
const COLOR_ACCENT_PRIMARY := Color(0.28, 0.76, 0.70, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.62, 0.32, 0.82, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.6, 1.0)
const COLOR_BORDER := Color(0.3, 0.35, 0.5, 0.6)

var skin_id: String


func setup(p_skin_id: String, display_name: String, is_owned: bool, is_selected: bool) -> void:
	skin_id = p_skin_id
	
	var preview: TextureRect = get_node("HBox/PreviewClip/Preview")
	var locked_bg: ColorRect = get_node("HBox/PreviewClip/LockedBg")
	var lock_label: Label = get_node("HBox/PreviewClip/LockLabel")
	var name_label: Label = get_node("HBox/NameVBox/NameLabel")
	var status_label: Label = get_node("HBox/NameVBox/StatusLabel")
	var action_btn: Button = get_node("HBox/ActionButton")
	
	# Card border color only (keeps scene-defined shape/size)
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	if is_selected:
		style.border_color = COLOR_ACCENT_SECONDARY
	elif is_owned:
		style.border_color = COLOR_ACCENT_PRIMARY.darkened(0.3)
	else:
		style.border_color = COLOR_BORDER
	add_theme_stylebox_override("panel", style)
	
	# Preview texture
	if is_owned:
		var texture_path := "res://assets/skins/%s.png" % p_skin_id
		if ResourceLoader.exists(texture_path):
			preview.texture = load(texture_path)
			preview.visible = true
		locked_bg.visible = false
		lock_label.visible = false
	else:
		preview.visible = false
		locked_bg.visible = true
		lock_label.visible = true
		lock_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	
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
		status_label.text = "CRATE ONLY"
		status_label.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	
	# Action button - text and state only
	if is_selected:
		action_btn.text = "SELECTED"
		action_btn.disabled = true
		action_btn.add_theme_color_override("font_color", COLOR_TEXT_MUTED)
	elif is_owned:
		action_btn.text = "SELECT"
		action_btn.disabled = false
		action_btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
		action_btn.pressed.connect(_on_select_pressed)
	else:
		action_btn.text = "LOCKED"
		action_btn.disabled = true
		action_btn.add_theme_color_override("font_color", COLOR_TEXT_MUTED)


func _on_select_pressed() -> void:
	skin_selected.emit(skin_id)

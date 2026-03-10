class_name UIConstants
extends RefCounted
## Centralized UI constants for consistent styling across all menus
## All sizes are designed for base resolution 1080x2410 and scale with viewport

# ========== REFERENCE RESOLUTION ==========
const BASE_WIDTH := 1080.0
const BASE_HEIGHT := 2410.0

# ========== COLORS ==========
const COLOR_BG_DARK := Color(0.06, 0.08, 0.12, 1.0)
const COLOR_BG_MEDIUM := Color(0.10, 0.14, 0.20, 1.0)
const COLOR_BG_LIGHT := Color(0.14, 0.18, 0.26, 1.0)
const COLOR_ACCENT_PRIMARY := Color(0.25, 0.65, 0.96, 1.0)
const COLOR_ACCENT_SECONDARY := Color(0.30, 0.85, 0.55, 1.0)
const COLOR_ACCENT_GOLD := Color(1.0, 0.82, 0.25, 1.0)
const COLOR_ACCENT_RED := Color(0.9, 0.3, 0.3, 1.0)
const COLOR_TEXT_PRIMARY := Color(1.0, 1.0, 1.0, 1.0)
const COLOR_TEXT_SECONDARY := Color(0.7, 0.75, 0.85, 1.0)
const COLOR_TEXT_MUTED := Color(0.5, 0.55, 0.65, 1.0)
const COLOR_BORDER := Color(0.25, 0.32, 0.45, 0.8)
const COLOR_BUTTON_NORMAL := Color(0.15, 0.20, 0.30, 1.0)
const COLOR_BUTTON_HOVER := Color(0.20, 0.28, 0.40, 1.0)
const COLOR_BUTTON_PRESSED := Color(0.12, 0.16, 0.24, 1.0)
const COLOR_BUTTON_DISABLED := Color(0.10, 0.12, 0.16, 1.0)

# ========== FONT SIZES (at 1080p base) - increased by 20% ==========
const FONT_SIZE_TINY := 29    # was 24
const FONT_SIZE_SMALL := 38   # was 32
const FONT_SIZE_NORMAL := 48  # was 40
const FONT_SIZE_MEDIUM := 58  # was 48
const FONT_SIZE_LARGE := 67   # was 56
const FONT_SIZE_XLARGE := 86  # was 72
const FONT_SIZE_TITLE := 115  # was 96
const FONT_SIZE_HUGE := 154   # was 128

# ========== TOGGLE/CHECKBOX SIZES ==========
const TOGGLE_SIZE := 140      # Base size for toggle buttons (much larger for touch)
const TOGGLE_FONT_SIZE := 52  # Font size for toggle labels

# ========== SLIDER SIZES ==========
const SLIDER_HEIGHT := 100    # Height for touch-friendly sliders
const SLIDER_GRABBER_SIZE := 72

# ========== PANEL HEADER ==========
const HEADER_HEIGHT := 100
const HEADER_ICON_SIZE := 56
const HEADER_BACK_BUTTON_WIDTH := 160  # Wide for easier touch
const HEADER_BACK_BUTTON_HEIGHT := 80
const COLOR_HEADER_BG := Color(0.05, 0.07, 0.10, 1.0)  # Slightly darker than panel

# ========== BUTTON SIZES (minimum touch targets) ==========
# Minimum touch target: 88px at 1080p (corresponds to ~48dp on high-DPI)
const BUTTON_MIN_HEIGHT := 88
const BUTTON_MIN_WIDTH := 88

# Standard button sizes
const BUTTON_SMALL_HEIGHT := 80
const BUTTON_SMALL_WIDTH := 120
const BUTTON_NORMAL_HEIGHT := 100
const BUTTON_NORMAL_WIDTH := 200
const BUTTON_LARGE_HEIGHT := 120
const BUTTON_LARGE_WIDTH := 300
const BUTTON_XLARGE_HEIGHT := 140
const BUTTON_XLARGE_WIDTH := 400

# Navigation button (back, arrows)
const BUTTON_NAV_SIZE := 100  # Square nav buttons

# Icon button (just icon, no text)
const BUTTON_ICON_SIZE := 88

# ========== SPACING ==========
const SPACING_TINY := 8
const SPACING_SMALL := 16
const SPACING_NORMAL := 24
const SPACING_MEDIUM := 32
const SPACING_LARGE := 48
const SPACING_XLARGE := 64

# ========== PADDING ==========
const PADDING_TINY := 8
const PADDING_SMALL := 16
const PADDING_NORMAL := 24
const PADDING_MEDIUM := 32
const PADDING_LARGE := 48

# ========== PANEL SIZES ==========
const PANEL_CORNER_RADIUS := 16
const PANEL_BORDER_WIDTH := 2

# ========== LIST ITEM SIZES ==========
const LIST_ITEM_HEIGHT := 184         # Unified height for all cards/entries
const LIST_ITEM_HEIGHT_LARGE := 220   # For items with extra content
const LIST_ITEM_ICON_SIZE := 96       # Larger icons
const LIST_ITEM_SPACING := 20

# ========== ROULETTE SIZES ==========
const ROULETTE_ITEM_WIDTH := 200      # Wider item slots
const ROULETTE_ITEM_HEIGHT := 220     # Taller for larger icons
const ROULETTE_ICON_SIZE := 140       # 3x bigger icons to fill slot
const ROULETTE_WINDOW_WIDTH := 980    # Full screen width for centering
const ROULETTE_WINDOW_HEIGHT := 280   # Taller to fit larger items
const ROULETTE_ITEM_SPACING := 16

# ========== SCROLL SETTINGS ==========
const SCROLL_BAR_WIDTH := 12
const SCROLL_DEADZONE := 10

# ========== HELPER FUNCTIONS ==========

## Get scale factor based on current viewport size
static func get_scale_factor() -> float:
	var viewport_size := DisplayServer.window_get_size()
	var scale_x := viewport_size.x / BASE_WIDTH
	var scale_y := viewport_size.y / BASE_HEIGHT
	# Use the smaller scale to ensure everything fits
	return minf(scale_x, scale_y)


## Scale a value based on viewport size
static func scale(value: float) -> float:
	return value * get_scale_factor()


## Scale an integer value based on viewport size
static func scale_int(value: int) -> int:
	return int(value * get_scale_factor())


## Get scaled font size
static func get_font_size(base_size: int) -> int:
	return maxi(16, scale_int(base_size))


## Get scaled button size
static func get_button_size(width: int, height: int) -> Vector2:
	return Vector2(scale(width), scale(height))


## Get scaled spacing
static func get_spacing(base_spacing: int) -> int:
	return maxi(4, scale_int(base_spacing))


## Create a styled button with consistent look
static func style_button(button: Button, size_preset: String = "normal") -> void:
	var width: int
	var height: int
	var font_size: int
	
	match size_preset:
		"tiny":
			width = BUTTON_SMALL_WIDTH
			height = BUTTON_SMALL_HEIGHT
			font_size = FONT_SIZE_SMALL
		"small":
			width = BUTTON_SMALL_WIDTH
			height = BUTTON_SMALL_HEIGHT
			font_size = FONT_SIZE_NORMAL
		"normal":
			width = BUTTON_NORMAL_WIDTH
			height = BUTTON_NORMAL_HEIGHT
			font_size = FONT_SIZE_MEDIUM
		"large":
			width = BUTTON_LARGE_WIDTH
			height = BUTTON_LARGE_HEIGHT
			font_size = FONT_SIZE_LARGE
		"xlarge":
			width = BUTTON_XLARGE_WIDTH
			height = BUTTON_XLARGE_HEIGHT
			font_size = FONT_SIZE_XLARGE
		"nav":
			width = BUTTON_NAV_SIZE
			height = BUTTON_NAV_SIZE
			font_size = FONT_SIZE_LARGE
		"icon":
			width = BUTTON_ICON_SIZE
			height = BUTTON_ICON_SIZE
			font_size = FONT_SIZE_MEDIUM
		_:
			width = BUTTON_NORMAL_WIDTH
			height = BUTTON_NORMAL_HEIGHT
			font_size = FONT_SIZE_MEDIUM
	
	button.custom_minimum_size = Vector2(width, height)
	button.add_theme_font_size_override("font_size", font_size)
	
	# Create stylebox
	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = COLOR_BUTTON_NORMAL
	style_normal.corner_radius_top_left = PANEL_CORNER_RADIUS
	style_normal.corner_radius_top_right = PANEL_CORNER_RADIUS
	style_normal.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	style_normal.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	style_normal.border_width_left = PANEL_BORDER_WIDTH
	style_normal.border_width_right = PANEL_BORDER_WIDTH
	style_normal.border_width_top = PANEL_BORDER_WIDTH
	style_normal.border_width_bottom = PANEL_BORDER_WIDTH
	style_normal.border_color = COLOR_BORDER
	style_normal.content_margin_left = PADDING_NORMAL
	style_normal.content_margin_right = PADDING_NORMAL
	style_normal.content_margin_top = PADDING_SMALL
	style_normal.content_margin_bottom = PADDING_SMALL
	
	var style_hover := style_normal.duplicate()
	style_hover.bg_color = COLOR_BUTTON_HOVER
	style_hover.border_color = COLOR_ACCENT_PRIMARY
	
	var style_pressed := style_normal.duplicate()
	style_pressed.bg_color = COLOR_BUTTON_PRESSED
	
	var style_disabled := style_normal.duplicate()
	style_disabled.bg_color = COLOR_BUTTON_DISABLED
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	button.add_theme_stylebox_override("disabled", style_disabled)
	button.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT_PRIMARY)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT_SECONDARY)
	button.add_theme_color_override("font_disabled_color", COLOR_TEXT_MUTED)


## Style a primary (accent) button
static func style_primary_button(button: Button, size_preset: String = "normal") -> void:
	style_button(button, size_preset)
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ACCENT_PRIMARY
	style.corner_radius_top_left = PANEL_CORNER_RADIUS
	style.corner_radius_top_right = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	style.content_margin_left = PADDING_NORMAL
	style.content_margin_right = PADDING_NORMAL
	style.content_margin_top = PADDING_SMALL
	style.content_margin_bottom = PADDING_SMALL
	
	var style_hover := style.duplicate()
	style_hover.bg_color = COLOR_ACCENT_PRIMARY.lightened(0.15)
	
	var style_pressed := style.duplicate()
	style_pressed.bg_color = COLOR_ACCENT_PRIMARY.darkened(0.15)
	
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)


## Style a secondary button
static func style_secondary_button(button: Button, size_preset: String = "normal") -> void:
	style_button(button, size_preset)
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BG_LIGHT
	style.corner_radius_top_left = PANEL_CORNER_RADIUS
	style.corner_radius_top_right = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	style.border_width_left = PANEL_BORDER_WIDTH
	style.border_width_right = PANEL_BORDER_WIDTH
	style.border_width_top = PANEL_BORDER_WIDTH
	style.border_width_bottom = PANEL_BORDER_WIDTH
	style.border_color = COLOR_BORDER
	style.content_margin_left = PADDING_NORMAL
	style.content_margin_right = PADDING_NORMAL
	style.content_margin_top = PADDING_SMALL
	style.content_margin_bottom = PADDING_SMALL
	
	var style_hover := style.duplicate()
	style_hover.bg_color = COLOR_BG_LIGHT.lightened(0.1)
	style_hover.border_color = COLOR_ACCENT_PRIMARY
	
	var style_pressed := style.duplicate()
	style_pressed.bg_color = COLOR_BG_MEDIUM
	
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)


## Style a danger (red) button
static func style_danger_button(button: Button, size_preset: String = "normal") -> void:
	style_button(button, size_preset)
	
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_ACCENT_RED
	style.corner_radius_top_left = PANEL_CORNER_RADIUS
	style.corner_radius_top_right = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	style.content_margin_left = PADDING_NORMAL
	style.content_margin_right = PADDING_NORMAL
	style.content_margin_top = PADDING_SMALL
	style.content_margin_bottom = PADDING_SMALL
	
	var style_hover := style.duplicate()
	style_hover.bg_color = COLOR_ACCENT_RED.lightened(0.15)
	
	var style_pressed := style.duplicate()
	style_pressed.bg_color = COLOR_ACCENT_RED.darkened(0.15)
	
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)


## Create a panel stylebox
static func create_panel_style(bg_color: Color = COLOR_BG_MEDIUM, with_border: bool = true) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.corner_radius_top_left = PANEL_CORNER_RADIUS
	style.corner_radius_top_right = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_left = PANEL_CORNER_RADIUS
	style.corner_radius_bottom_right = PANEL_CORNER_RADIUS
	
	if with_border:
		style.border_width_left = PANEL_BORDER_WIDTH
		style.border_width_right = PANEL_BORDER_WIDTH
		style.border_width_top = PANEL_BORDER_WIDTH
		style.border_width_bottom = PANEL_BORDER_WIDTH
		style.border_color = COLOR_BORDER
	
	style.content_margin_left = PADDING_NORMAL
	style.content_margin_right = PADDING_NORMAL
	style.content_margin_top = PADDING_NORMAL
	style.content_margin_bottom = PADDING_NORMAL
	
	return style


## Style a label with consistent font size
static func style_label(label: Label, size_preset: String = "normal", color: Color = COLOR_TEXT_PRIMARY) -> void:
	var font_size: int
	
	match size_preset:
		"tiny":
			font_size = FONT_SIZE_TINY
		"small":
			font_size = FONT_SIZE_SMALL
		"normal":
			font_size = FONT_SIZE_NORMAL
		"medium":
			font_size = FONT_SIZE_MEDIUM
		"large":
			font_size = FONT_SIZE_LARGE
		"xlarge":
			font_size = FONT_SIZE_XLARGE
		"title":
			font_size = FONT_SIZE_TITLE
		"huge":
			font_size = FONT_SIZE_HUGE
		_:
			font_size = FONT_SIZE_NORMAL
	
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)


## Configure a ScrollContainer for touch-friendly scrolling
static func setup_scroll_container(scroll: ScrollContainer) -> void:
	scroll.scroll_deadzone = SCROLL_DEADZONE
	# Make scroll bar wider for touch
	scroll.add_theme_constant_override("scroll_bar_size", SCROLL_BAR_WIDTH)

extends HBoxContainer
class_name BuffIndicatorItem
## BuffIndicatorItem - Single buff indicator with circular progress
## Styles are defined in the scene, script only changes content, visibility, and colors

signal removed

@export var buff_type: int = 0
@export var buff_color: Color = Color.WHITE:
	set(value):
		buff_color = value
		_update_colors()

var progress: float = 1.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

var _circle: Control
var _name_label: Label
var _timer_label: Label
var _count_label: Label

const BG_COLOR := Color(0.1, 0.1, 0.15, 0.85)
const BORDER_WIDTH := 3.0

func _ready() -> void:
	_circle = $Circle
	_name_label = $Info/NameLabel
	_timer_label = $Info/TimerLabel
	_count_label = $Info/CountLabel
	
	# Connect circle drawing
	if _circle:
		_circle.draw.connect(_on_circle_draw)

func _on_circle_draw() -> void:
	if not _circle:
		return
	
	var center := _circle.size / 2.0
	var radius := minf(_circle.size.x, _circle.size.y) / 2.0 - BORDER_WIDTH
	
	# Background circle
	_circle.draw_circle(center, radius + BORDER_WIDTH, BG_COLOR)
	
	# Progress arc (pie)
	if progress > 0.001:
		var points := PackedVector2Array()
		points.append(center)
		
		var start_angle := -PI / 2.0  # Start from top
		var end_angle := start_angle + (progress * TAU)
		var segments := int(32 * progress) + 4
		
		for i in range(segments + 1):
			var angle := start_angle + (float(i) / segments) * (end_angle - start_angle)
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		
		if points.size() >= 3:
			_circle.draw_colored_polygon(points, buff_color)
	
	# Border ring
	var border_color := buff_color
	border_color.a = 0.9
	_circle.draw_arc(center, radius, 0, TAU, 32, border_color, BORDER_WIDTH, true)
	
	# Inner dark circle for contrast
	_circle.draw_circle(center, radius * 0.35, BG_COLOR)

func _process(_delta: float) -> void:
	if _circle:
		_circle.queue_redraw()

func _update_colors() -> void:
	if _name_label:
		_name_label.add_theme_color_override("font_color", buff_color)

## Set the buff name text
func set_name_text(text: String) -> void:
	if _name_label:
		_name_label.text = text

## Set the timer text
func set_timer_text(text: String) -> void:
	if _timer_label:
		_timer_label.text = text

## Set the count text (for shields) and visibility
func set_count(value: int, visible_state: bool = true) -> void:
	if _count_label:
		_count_label.text = str(value)
		_count_label.visible = visible_state

## Show the count label
func show_count() -> void:
	if _count_label:
		_count_label.visible = true

## Hide the count label
func hide_count() -> void:
	if _count_label:
		_count_label.visible = false

## Play pop-in animation
func animate_in() -> void:
	var circle_size := _circle.custom_minimum_size if _circle else Vector2(140, 140)
	scale = Vector2.ZERO
	pivot_offset = Vector2(circle_size.x / 2.0, circle_size.y / 2.0)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

## Play removal animation and emit removed signal
func animate_out() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.15).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "modulate:a", 0.0, 0.1)
	tween.tween_callback(func(): 
		removed.emit()
		queue_free()
	)

## Flash effect (for shield hits etc.)
func flash() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color(2, 2, 2, 1), 0.1)
	tween.tween_property(self, "modulate", Color.WHITE, 0.2)

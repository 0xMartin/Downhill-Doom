extends PanelContainer
## InventoryUI - Displays 3 item slots in the HUD
## Handles clicking to use items and visual updates

signal slot_clicked(slot_index: int)

const SLOT_COUNT: int = 3

@onready var slot_container: VBoxContainer = $SlotContainer
var _slot_buttons: Array[TextureButton] = []
var _slot_borders: Array[PanelContainer] = []

# Rarity border colors
const RARITY_COLORS: Dictionary = {
	ItemConfig.Rarity.COMMON: Color(0.6, 0.6, 0.6, 0.8),
	ItemConfig.Rarity.RARE: Color(0.3, 0.5, 1.0, 0.9),
	ItemConfig.Rarity.LEGENDARY: Color(1.0, 0.84, 0.0, 1.0),
}

func _ready() -> void:
	_setup_slots()
	_connect_signals()
	_update_all_slots()

func _setup_slots() -> void:
	for i in range(SLOT_COUNT):
		var slot: Control = slot_container.get_child(i)
		var border: PanelContainer = slot.get_node("Border")
		var button: TextureButton = slot.get_node("Border/ItemButton")
		
		_slot_borders.append(border)
		_slot_buttons.append(button)
		
		# Connect button press
		var slot_index := i
		button.pressed.connect(func(): _on_slot_pressed(slot_index))

func _connect_signals() -> void:
	var inventory := get_node_or_null("/root/InventoryManager")
	if inventory:
		inventory.inventory_changed.connect(_update_all_slots)
		inventory.item_added.connect(_on_item_added)
		inventory.item_removed.connect(_on_item_removed)

func _update_all_slots() -> void:
	var inventory := get_node_or_null("/root/InventoryManager")
	if inventory == null:
		return
	
	for i in range(SLOT_COUNT):
		_update_slot(i)

func _update_slot(slot_index: int) -> void:
	var inventory := get_node_or_null("/root/InventoryManager")
	if inventory == null:
		return
	
	var item_data: ItemConfig.ItemData = inventory.get_item_data(slot_index)
	var button: TextureButton = _slot_buttons[slot_index]
	var border: PanelContainer = _slot_borders[slot_index]
	
	if item_data == null:
		# Empty slot
		button.texture_normal = null
		button.modulate = Color(1, 1, 1, 0.3)
		_set_border_color(border, Color(0.3, 0.3, 0.3, 0.5))
	else:
		# Has item - load icon
		var icon := load(item_data.icon_path) as Texture2D
		button.texture_normal = icon
		button.modulate = Color.WHITE
		_set_border_color(border, RARITY_COLORS.get(item_data.rarity, Color.WHITE))

func _set_border_color(border: PanelContainer, color: Color) -> void:
	var style: StyleBoxFlat = border.get_theme_stylebox("panel").duplicate()
	style.border_color = color
	border.add_theme_stylebox_override("panel", style)

func _on_slot_pressed(slot_index: int) -> void:
	var inventory := get_node_or_null("/root/InventoryManager")
	if inventory == null:
		return
	
	# Try to use the item
	if inventory.use_item(slot_index):
		_play_use_animation(slot_index)
	
	slot_clicked.emit(slot_index)

func _on_item_added(slot_index: int, _item_id: String) -> void:
	_play_add_animation(slot_index)

func _on_item_removed(slot_index: int, _item_id: String) -> void:
	pass  # Animation handled in _on_slot_pressed

func _play_add_animation(slot_index: int) -> void:
	var button: TextureButton = _slot_buttons[slot_index]
	
	# Scale pop animation
	var tween := create_tween()
	tween.tween_property(button, "scale", Vector2(1.3, 1.3), 0.1)
	tween.tween_property(button, "scale", Vector2(1.0, 1.0), 0.15).set_ease(Tween.EASE_OUT)

func _play_use_animation(slot_index: int) -> void:
	var button: TextureButton = _slot_buttons[slot_index]
	
	# Flash and scale down animation
	var tween := create_tween()
	tween.tween_property(button, "modulate", Color(2, 2, 2, 1), 0.1)
	tween.parallel().tween_property(button, "scale", Vector2(0.8, 0.8), 0.1)
	tween.tween_property(button, "modulate", Color(1, 1, 1, 0.3), 0.15)
	tween.parallel().tween_property(button, "scale", Vector2(1.0, 1.0), 0.15)

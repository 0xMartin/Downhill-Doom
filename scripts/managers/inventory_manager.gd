extends Node
## InventoryManager - Singleton for managing the player's item inventory
## Handles 3 slots, adding items, using items, and inventory state

signal inventory_changed
signal item_added(slot_index: int, item_id: String)
signal item_removed(slot_index: int, item_id: String)
signal inventory_full

const MAX_SLOTS: int = 3

# Inventory slots - each slot stores an item ID or empty string
var _slots: Array[String] = ["", "", ""]

func _ready() -> void:
	# Add test items for debugging
	call_deferred("_add_test_items")

func _add_test_items() -> void:
	# Add 3 different items for testing
	var test_items: Array[String] = ["super_supercharge", "explosion", "time_stop"]
	for item_id in test_items:
		add_item(item_id)
		print("[InventoryManager] Added test item: ", item_id)

## Try to add an item to the inventory
## Returns the slot index if successful, -1 if inventory is full
func add_item(item_id: String) -> int:
	# Find first empty slot
	for i in range(MAX_SLOTS):
		if _slots[i] == "":
			_slots[i] = item_id
			item_added.emit(i, item_id)
			inventory_changed.emit()
			# Play pickup sound
			var audio := get_node_or_null("/root/AudioManager")
			if audio:
				audio.play_item_pickup_sound()
			return i
	
	# Inventory is full
	inventory_full.emit()
	return -1

## Use item in a specific slot
## Returns true if item was used successfully
func use_item(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return false
	
	var item_id: String = _slots[slot_index]
	if item_id == "":
		return false
	
	# Get ItemManager and use the item
	var item_manager := get_node_or_null("/root/ItemManager")
	if item_manager == null:
		push_error("InventoryManager: ItemManager not found!")
		return false
	
	var success: bool = item_manager.use_item(item_id)
	if success:
		_slots[slot_index] = ""
		item_removed.emit(slot_index, item_id)
		inventory_changed.emit()
		# Play use sound
		var audio := get_node_or_null("/root/AudioManager")
		if audio:
			audio.play_item_use_sound()
	
	return success

## Get item ID in a slot (empty string if slot is empty)
func get_item(slot_index: int) -> String:
	if slot_index < 0 or slot_index >= MAX_SLOTS:
		return ""
	return _slots[slot_index]

## Get ItemData for a slot (null if empty)
func get_item_data(slot_index: int) -> ItemConfig.ItemData:
	var item_id := get_item(slot_index)
	if item_id == "":
		return null
	return ItemConfig.get_item(item_id)

## Get all slots as array of item IDs
func get_all_slots() -> Array[String]:
	return _slots.duplicate()

## Check if inventory has any empty slots
func has_space() -> bool:
	for slot in _slots:
		if slot == "":
			return true
	return false

## Check if inventory is completely empty
func is_empty() -> bool:
	for slot in _slots:
		if slot != "":
			return false
	return true

## Check if inventory is completely full
func is_full() -> bool:
	for slot in _slots:
		if slot == "":
			return false
	return true

## Get number of items in inventory
func get_item_count() -> int:
	var count := 0
	for slot in _slots:
		if slot != "":
			count += 1
	return count

## Clear all items from inventory
func clear() -> void:
	for i in range(MAX_SLOTS):
		if _slots[i] != "":
			var old_item := _slots[i]
			_slots[i] = ""
			item_removed.emit(i, old_item)
	inventory_changed.emit()

## Reset inventory - called on game restart
func reset() -> void:
	clear()

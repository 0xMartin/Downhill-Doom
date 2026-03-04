class_name ObjectConfig
extends RefCounted
## Configuration for all spawnable objects in the game
## Each object has unique ID, display name, model path, and spawn parameters

# ========== OBJECT CATEGORIES ==========

enum Category {
	TREE,
	BUILDING,
	BUILDING_ENEMY,
	ROCK,
	NPC_FRIEND,
	NPC_ENEMY,
}

# ========== OBJECT DATA STRUCTURE ==========

class ObjectData:
	var id: String                    # Unique identifier (e.g., "tree_borovice_1")
	var display_name: String          # Human-readable name (e.g., "Borovice")
	var category: int                 # Category enum value
	var model_path: String            # Path to .blend model
	var target_height: float          # Target scale height
	var height_variation: float       # +/- variation (0.2 = 20%)
	var spawn_chance: float           # Probability weight (0.0-1.0)
	var coins: int                    # Coins awarded when destroyed (0 for non-destructible)
	var damage: int                   # Damage dealt to player (0 for non-damaging)
	var is_destructible: bool         # Can be destroyed by player
	var collision_radius: float       # For sphere/capsule colliders
	var collision_height: float       # For capsule colliders (trees)
	var collision_size: Vector3       # For box colliders (buildings)
	
	func _init(data: Dictionary) -> void:
		id = data.get("id", "unknown")
		display_name = data.get("name", "Unknown")
		category = data.get("category", Category.TREE)
		model_path = data.get("model", "")
		target_height = data.get("height", 1.0)
		height_variation = data.get("height_var", 0.15)
		spawn_chance = data.get("spawn_chance", 1.0)
		coins = data.get("coins", 0)
		damage = data.get("damage", 0)
		is_destructible = data.get("destructible", false)
		collision_radius = data.get("col_radius", 0.5)
		collision_height = data.get("col_height", 2.0)
		collision_size = data.get("col_size", Vector3(1.0, 1.0, 1.0))

# ========== OBJECT DEFINITIONS ==========

static var _objects: Dictionary = {}
static var _objects_by_category: Dictionary = {}
static var _initialized: bool = false

static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_init_objects()

static func _init_objects() -> void:
	# ===== TREES =====
	_register_object({
		"id": "tree_borovice_1",
		"name": "Borovice 1",
		"category": Category.TREE,
		"model": "res://assets/models/trees/borovice_1.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_borovice_2",
		"name": "Borovice 2",
		"category": Category.TREE,
		"model": "res://assets/models/trees/borovice_2.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_borovice_3",
		"name": "Borovice 3",
		"category": Category.TREE,
		"model": "res://assets/models/trees/borovice_3.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_smrk_1",
		"name": "Smrk 1",
		"category": Category.TREE,
		"model": "res://assets/models/trees/smrk_1.blend",
		"height": 3.2,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.5,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_smrk_2",
		"name": "Smrk 2",
		"category": Category.TREE,
		"model": "res://assets/models/trees/smrk_2.blend",
		"height": 3.2,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.5,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_smrk_3",
		"name": "Smrk 3",
		"category": Category.TREE,
		"model": "res://assets/models/trees/smrk_3.blend",
		"height": 3.2,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.5,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_strom_1",
		"name": "Strom 1",
		"category": Category.TREE,
		"model": "res://assets/models/trees/strom_1.blend",
		"height": 3.5,
		"height_var": 0.25,
		"spawn_chance": 0.8,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.7,
		"col_height": 2.8,
	})
	_register_object({
		"id": "tree_strom_2",
		"name": "Strom 2",
		"category": Category.TREE,
		"model": "res://assets/models/trees/strom_2.blend",
		"height": 3.5,
		"height_var": 0.25,
		"spawn_chance": 0.8,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.7,
		"col_height": 2.8,
	})
	_register_object({
		"id": "tree_strom_3",
		"name": "Strom 3",
		"category": Category.TREE,
		"model": "res://assets/models/trees/strom_3.blend",
		"height": 3.5,
		"height_var": 0.25,
		"spawn_chance": 0.8,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.7,
		"col_height": 2.8,
	})
	_register_object({
		"id": "tree_bez_listi",
		"name": "Strom bez listí",
		"category": Category.TREE,
		"model": "res://assets/models/trees/strom_bez_listi.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 0.5,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.5,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_bez_listi_2",
		"name": "Strom bez listí 2",
		"category": Category.TREE,
		"model": "res://assets/models/trees/strom_bez_listi_2.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 0.5,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.5,
		"col_height": 2.5,
	})
	
	# ===== BUILDINGS =====
	_register_object({
		"id": "building_tent",
		"name": "Stan",
		"category": Category.BUILDING,
		"model": "res://assets/models/buildings/tent.blend",
		"height": 0.88,  # Reduced by 25% from 1.17
		"height_var": 0.1,
		"spawn_chance": 1.0,
		"coins": 15,
		"destructible": true,
		"col_size": Vector3(0.75, 0.75, 0.75),  # Scaled down with height
	})
	_register_object({
		"id": "building_small_hut",
		"name": "Malá chata",
		"category": Category.BUILDING,
		"model": "res://assets/models/buildings/small_hut.blend",
		"height": 2.5,
		"height_var": 0.1,
		"spawn_chance": 0.8,
		"coins": 25,
		"destructible": true,
		"col_size": Vector3(2.0, 2.0, 2.0),
	})
	
	# ===== BUILDING ENEMIES =====
	_register_object({
		"id": "enemy_spike",
		"name": "Spike",
		"category": Category.BUILDING_ENEMY,
		"model": "res://assets/models/buildings_enemy/spike.blend",
		"height": 1.95, 
		"height_var": 0.1,
		"spawn_chance": 1.0,
		"damage": 15,
		"destructible": false,
		"col_radius": 1.6,  
	})
	
	# ===== ROCKS (decoration) =====
	_register_object({
		"id": "rock_1",
		"name": "Kámen 1",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_1.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_2",
		"name": "Kámen 2",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_2.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_3",
		"name": "Kámen 3",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_3.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_4",
		"name": "Kámen 4",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_4.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_5",
		"name": "Kámen 5",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_5.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_6",
		"name": "Kámen 6",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_6.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_7",
		"name": "Kámen 7",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_7.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_8",
		"name": "Kámen 8",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_8.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_9",
		"name": "Kámen 9",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_9.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	_register_object({
		"id": "rock_10",
		"name": "Kámen 10",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_10.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	
	# ===== FRIEND NPCs =====
	_register_object({
		"id": "npc_chicken",
		"name": "Kuře",
		"category": Category.NPC_FRIEND,
		"model": "res://assets/models/npc_friend/chicken.blend",
		"height": 0.7,
		"height_var": 0.1,
		"spawn_chance": 1.0,
		"coins": 5,
		"destructible": true,
		"col_radius": 0.3,
		"col_height": 0.4,
	})
	_register_object({
		"id": "npc_rabbit",
		"name": "Králík",
		"category": Category.NPC_FRIEND,
		"model": "res://assets/models/npc_friend/rabbit.blend",
		"height": 0.8,
		"height_var": 0.1,
		"spawn_chance": 0.8,
		"coins": 8,
		"destructible": true,
		"col_radius": 0.25,
		"col_height": 0.35,
	})
	
	# ===== ENEMY NPCs =====
	_register_object({
		"id": "npc_dark_pawn",
		"name": "Dark Pawn",
		"category": Category.NPC_ENEMY,
		"model": "res://assets/models/npc_enemy/dark_pawn.blend",
		"height": 1.8,  # 50% larger
		"height_var": 0.1,
		"spawn_chance": 0.6,  # 60% chance (most common)
		"coins": 40,
		"damage": 5,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 1.5,
	})
	_register_object({
		"id": "npc_dark_knight",
		"name": "Dark Knight",
		"category": Category.NPC_ENEMY,
		"model": "res://assets/models/npc_enemy/dark_knight.blend",
		"height": 2.25,  # 50% larger
		"height_var": 0.1,
		"spawn_chance": 0.3,  # 30% chance
		"coins": 80,
		"damage": 10,
		"destructible": true,
		"col_radius": 0.75,
		"col_height": 1.95,
	})
	_register_object({
		"id": "npc_horse_knight",
		"name": "Horse Knight",
		"category": Category.NPC_ENEMY,
		"model": "res://assets/models/npc_enemy/horse_knight.blend",
		"height": 2.7,  # 50% larger
		"height_var": 0.1,
		"spawn_chance": 0.1,  # 10% chance (rare)
		"coins": 140,
		"damage": 15,
		"destructible": true,
		"col_radius": 0.9,
		"col_height": 2.4,
	})

static func _register_object(data: Dictionary) -> void:
	var obj := ObjectData.new(data)
	_objects[obj.id] = obj
	
	var cat: int = obj.category
	if not _objects_by_category.has(cat):
		_objects_by_category[cat] = []
	_objects_by_category[cat].append(obj)

# ========== PUBLIC API ==========

## Get object data by ID
static func get_object(id: String) -> ObjectData:
	_ensure_initialized()
	return _objects.get(id, null)

## Get all objects in a category
static func get_objects_by_category(category: int) -> Array:
	_ensure_initialized()
	return _objects_by_category.get(category, [])

## Get all trees
static func get_trees() -> Array:
	return get_objects_by_category(Category.TREE)

## Get all buildings
static func get_buildings() -> Array:
	return get_objects_by_category(Category.BUILDING)

## Get all building enemies
static func get_building_enemies() -> Array:
	return get_objects_by_category(Category.BUILDING_ENEMY)

## Get all rocks
static func get_rocks() -> Array:
	return get_objects_by_category(Category.ROCK)

## Get all friend NPCs
static func get_npcs_friend() -> Array:
	return get_objects_by_category(Category.NPC_FRIEND)

## Select random object from category based on spawn_chance weights
static func select_random_object(category: int, rng: RandomNumberGenerator) -> ObjectData:
	_ensure_initialized()
	var objects: Array = _objects_by_category.get(category, [])
	if objects.is_empty():
		return null
	
	# Calculate total weight
	var total_weight: float = 0.0
	for obj in objects:
		var o: ObjectData = obj
		total_weight += o.spawn_chance
	
	# Random selection based on weight
	var roll := rng.randf() * total_weight
	var cumulative: float = 0.0
	
	for obj in objects:
		var o: ObjectData = obj
		cumulative += o.spawn_chance
		if roll <= cumulative:
			return o
	
	# Fallback to last object
	return objects[-1] as ObjectData

## Get category name for display
static func get_category_name(category: int) -> String:
	match category:
		Category.TREE:
			return "Tree"
		Category.BUILDING:
			return "Building"
		Category.BUILDING_ENEMY:
			return "Building Enemy"
		Category.ROCK:
			return "Rock"
		Category.NPC_FRIEND:
			return "Friend NPC"
		Category.NPC_ENEMY:
			return "Enemy NPC"
	return "Unknown"

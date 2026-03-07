class_name ObjectConfig
extends RefCounted
## Configuration for all spawnable objects in the game
## Each object has unique ID, display name, model path, and spawn parameters

# ========== OBJECT CATEGORIES ==========

enum Category {
	TREE,
	BUILDING,
	BUILDING_LARGE,
	BUILDING_ENEMY,
	ROCK,
	NPC_FRIEND,
	NPC_ENEMY,
	NPC_AERIAL,
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
		"id": "tree_1",
		"name": "Tree 1",
		"category": Category.TREE,
		"model": "res://assets/models/trees/tree_1.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_2",
		"name": "Tree 2",
		"category": Category.TREE,
		"model": "res://assets/models/trees/tree_2.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_3",
		"name": "Tree 3",
		"category": Category.TREE,
		"model": "res://assets/models/trees/tree_3.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_4",
		"name": "Tree 4",
		"category": Category.TREE,
		"model": "res://assets/models/trees/tree_4.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_5",
		"name": "Tree 5",
		"category": Category.TREE,
		"model": "res://assets/models/trees/tree_5.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	_register_object({
		"id": "tree_6",
		"name": "Tree 6",
		"category": Category.TREE,
		"model": "res://assets/models/trees/tree_6.blend",
		"height": 3.0,
		"height_var": 0.2,
		"spawn_chance": 1.0,
		"coins": 1,
		"destructible": true,
		"col_radius": 0.6,
		"col_height": 2.5,
	})
	
	# ===== BUILDINGS (Small - always destructible) =====
	_register_object({
		"id": "building_well",
		"name": "Well",
		"category": Category.BUILDING,
		"model": "res://assets/models/buildings/well.blend",
		"height": 1.8,
		"height_var": 0.1,
		"spawn_chance": 1.0,
		"coins": 10,
		"destructible": true,
		"col_size": Vector3(1.5, 1.5, 1.5),
	})
	_register_object({
		"id": "building_market_stall",
		"name": "Market Stall",
		"category": Category.BUILDING,
		"model": "res://assets/models/buildings/market_stall.blend",
		"height": 2.2,
		"height_var": 0.1,
		"spawn_chance": 0.9,
		"coins": 12,
		"destructible": true,
		"col_size": Vector3(2.5, 2.0, 2.0),
	})
	_register_object({
		"id": "building_wooden_cart",
		"name": "Wooden Cart",
		"category": Category.BUILDING,
		"model": "res://assets/models/buildings/wooden_cart.blend",
		"height": 1.5,
		"height_var": 0.1,
		"spawn_chance": 0.8,
		"coins": 15,
		"destructible": true,
		"col_size": Vector3(2.0, 1.5, 1.5),
	})
	_register_object({
		"id": "building_barrels",
		"name": "Barrel Pile",
		"category": Category.BUILDING,
		"model": "res://assets/models/buildings/barrels.blend",
		"height": 1.2,
		"height_var": 0.15,
		"spawn_chance": 0.7,
		"coins": 20,
		"destructible": true,
		"col_size": Vector3(1.5, 1.2, 1.5),
	})
	_register_object({
		"id": "building_small_hut",
		"name": "Small Hut",
		"category": Category.BUILDING,
		"model": "res://assets/models/buildings/small_hut.blend",
		"height": 2.5,
		"height_var": 0.1,
		"spawn_chance": 0.6,
		"coins": 40,
		"destructible": true,
		"col_size": Vector3(2.0, 2.0, 2.0),
	})
	_register_object({
		"id": "building_excalibur",
		"name": "Excalibur",
		"category": Category.BUILDING,
		"model": "res://assets/models/buildings/excalibur.blend",
		"height": 1.8,
		"height_var": 0.05,
		"spawn_chance": 0.01,
		"coins": 2200,
		"destructible": true,
		"col_size": Vector3(0.8, 1.8, 0.8),
	})
	
	# ===== LARGE BUILDINGS (only destructible in supercharge) =====
	_register_object({
		"id": "building_house",
		"name": "House",
		"category": Category.BUILDING_LARGE,
		"model": "res://assets/models/buildings/house.blend",
		"height": 4.5,
		"height_var": 0.1,
		"spawn_chance": 1.0,
		"coins": 300,
		"destructible": true,
		"col_size": Vector3(3.5, 4.0, 3.5),
	})
	_register_object({
		"id": "building_chapel",
		"name": "Small Chapel",
		"category": Category.BUILDING_LARGE,
		"model": "res://assets/models/buildings/small_chapel.blend",
		"height": 5.5,
		"height_var": 0.1,
		"spawn_chance": 0.6,
		"coins": 500,
		"destructible": true,
		"col_size": Vector3(3.0, 5.5, 3.0),
	})
	_register_object({
		"id": "building_windmill",
		"name": "Windmill",
		"category": Category.BUILDING_LARGE,
		"model": "res://assets/models/buildings/windmill.blend",
		"height": 7.0,
		"height_var": 0.1,
		"spawn_chance": 0.4,
		"coins": 700,
		"destructible": true,
		"col_size": Vector3(2.0, 7.0, 2.0),
	})
	_register_object({
		"id": "building_tower",
		"name": "Guard Tower",
		"category": Category.BUILDING_LARGE,
		"model": "res://assets/models/buildings/tower.blend",
		"height": 7.0,
		"height_var": 0.1,
		"spawn_chance": 0.2,
		"coins": 900,
		"destructible": true,
		"col_size": Vector3(2.5, 7.0, 2.5),
	})
	_register_object({
		"id": "building_castle",
		"name": "Castle",
		"category": Category.BUILDING_LARGE,
		"model": "res://assets/models/buildings/castle.blend",
		"height": 8.0,
		"height_var": 0.1,
		"spawn_chance": 0.1,
		"coins": 1600,
		"destructible": true,
		"col_size": Vector3(5.0, 8.0, 5.0),
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
		"coins": 700,
		"damage": 15,
		"destructible": false,
		"col_radius": 1.6,  
	})
	_register_object({
		"id": "enemy_spike_wall",
		"name": "Spike Wall",
		"category": Category.BUILDING_ENEMY,
		"model": "res://assets/models/buildings_enemy/spike_wall.blend",
		"height": 2.0, 
		"height_var": 0.05,
		"spawn_chance": 0.0, 
		"coins": 950,
		"damage": 15,
		"destructible": false,
		"col_size": Vector3(3.0, 2.0, 0.8),  
	})
	_register_object({
		"id": "enemy_big_spike_wall",
		"name": "Big Spike Wall",
		"category": Category.BUILDING_ENEMY,
		"model": "res://assets/models/buildings_enemy/big_spike_wall.blend",
		"height": 5.0, 
		"height_var": 0.1,
		"spawn_chance": 0.3, 
		"coins": 1500,
		"damage": 20,
		"destructible": false,
		"col_size": Vector3(5.0, 3.0, 1.0),  
	})
	
	# ===== ROCKS (decoration) =====
	_register_object({
		"id": "rock_1",
		"name": "Rock 1",
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
		"name": "Rock 2",
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
		"name": "Rock 3",
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
		"name": "Rock 4",
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
		"name": "Rock 5",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_5.blend",
		"height": 2.5,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.6,
	})
	_register_object({
		"id": "rock_6",
		"name": "Rock 6",
		"category": Category.ROCK,
		"model": "res://assets/models/rocks/rock_6.blend",
		"height": 0.8,
		"height_var": 0.3,
		"spawn_chance": 1.0,
		"destructible": false,
		"col_radius": 0.4,
	})
	
	# ===== FRIEND NPCs =====
	_register_object({
		"id": "npc_chicken",
		"name": "Chicken",
		"category": Category.NPC_FRIEND,
		"model": "res://assets/models/npc_friend/chicken.blend",
		"height": 0.7,
		"height_var": 0.1,
		"spawn_chance": 1.0,
		"coins": 10,
		"destructible": true,
		"col_radius": 0.3,
		"col_height": 0.4,
	})
	_register_object({
		"id": "npc_rabbit",
		"name": "Rabbit",
		"category": Category.NPC_FRIEND,
		"model": "res://assets/models/npc_friend/rabbit.blend",
		"height": 0.8,
		"height_var": 0.1,
		"spawn_chance": 0.8,
		"coins": 15,
		"destructible": true,
		"col_radius": 0.25,
		"col_height": 0.35,
	})
	_register_object({
		"id": "npc_sheep",
		"name": "Sheep",
		"category": Category.NPC_FRIEND,
		"model": "res://assets/models/npc_friend/sheep.blend",
		"height": 1.0,
		"height_var": 0.1,
		"spawn_chance": 0.6,
		"coins": 20,
		"destructible": true,
		"col_radius": 0.4,
		"col_height": 0.6,
	})
	_register_object({
		"id": "npc_cow",
		"name": "Cow",
		"category": Category.NPC_FRIEND,
		"model": "res://assets/models/npc_friend/cow.blend",
		"height": 1.2,
		"height_var": 0.1,
		"spawn_chance": 0.4,
		"coins": 25,
		"destructible": true,
		"col_radius": 0.5,
		"col_height": 0.8,
	})
	
	# ===== ENEMY NPCs =====
	_register_object({
		"id": "npc_dark_pawn",
		"name": "Dark Pawn",
		"category": Category.NPC_ENEMY,
		"model": "res://assets/models/npc_enemy/dark_pawn.blend",
		"height": 1.8,  
		"height_var": 0.1,
		"spawn_chance": 0.4, 
		"coins": 80,
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
		"height": 2.25, 
		"height_var": 0.1,
		"spawn_chance": 0.22, 
		"coins": 100,
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
		"height": 2.7,  
		"height_var": 0.1,
		"spawn_chance": 0.18, 
		"coins": 220,
		"damage": 17,
		"destructible": true,
		"col_radius": 0.9,
		"col_height": 2.4,
	})
	_register_object({
		"id": "npc_catapult",
		"name": "Catapult",
		"category": Category.NPC_ENEMY,
		"model": "res://assets/models/npc_enemy/catapult.blend",
		"height": 2.4,
		"height_var": 0.1,
		"spawn_chance": 0.10,  
		"coins": 700,
		"damage": 30, 
		"destructible": true,
		"col_radius": 1.2,
		"col_height": 2.0,
	})
	
	# ===== AERIAL NPC =====
	_register_object({
		"id": "npc_plane",
		"name": "Enemy Plane",
		"category": Category.NPC_AERIAL,
		"model": "res://assets/models/npc_enemy/plane.blend",
		"height": 0.75,
		"height_var": 0.0,
		"spawn_chance": 0.10,
		"coins": 3500,
		"damage": 40,
		"destructible": true,
		"col_radius": 2.0,
		"col_height": 1.5,
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

## Get all large buildings
static func get_large_buildings() -> Array:
	return get_objects_by_category(Category.BUILDING_LARGE)

## Get all building enemies
static func get_building_enemies() -> Array:
	return get_objects_by_category(Category.BUILDING_ENEMY)

## Get spike wall data specifically (for chain spawning)
static func get_spike_wall() -> ObjectData:
	_ensure_initialized()
	return _objects.get("enemy_spike_wall", null)

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
		Category.BUILDING_LARGE:
			return "Large Building"
		Category.BUILDING_ENEMY:
			return "Building Enemy"
		Category.ROCK:
			return "Rock"
		Category.NPC_FRIEND:
			return "Friend NPC"
		Category.NPC_ENEMY:
			return "Enemy NPC"
		Category.NPC_AERIAL:
			return "Aerial Enemy"
	return "Unknown"

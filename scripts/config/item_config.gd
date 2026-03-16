class_name ItemConfig
extends RefCounted
## Configuration for all collectible items in the game
## Each item has unique ID, display name, icon, model, rarity, and effect parameters

# ========== ITEM RARITY ==========

enum Rarity {
	COMMON,     
	RARE,       
	LEGENDARY,  
}

# ========== ITEM EFFECT TYPES ==========

enum EffectType {
	HEAL,              # Restore HP percentage
	INSTANT_SUPERCHARGE,  # Activate supercharge immediately
	SUPER_SUPERCHARGE,    # Extended supercharge duration
	SPEED_BOOST,       # Temporary speed increase
	DOUBLE_COINS,      # 2x coin multiplier
	TRIPLE_COINS,      # 3x coin multiplier
	SHIELD,            # Block damage hits
	SLOW_MOTION,       # Slow down time
	EXPLOSION,         # Destroy nearby objects
	TIME_STOP,         # Freeze time completely
}

# ========== RARITY UNLOCK DISTANCES ==========

const RARITY_UNLOCK_DISTANCE: Dictionary = {
	Rarity.COMMON: 0.0,
	Rarity.RARE: 2000.0,
	Rarity.LEGENDARY: 3500.0,
}

# ========== RARITY SPAWN CHANCES ==========

const RARITY_SPAWN_CHANCE: Dictionary = {
	Rarity.COMMON: 0.60,
	Rarity.RARE: 0.30,
	Rarity.LEGENDARY: 0.10,
}

# ========== ITEM DATA STRUCTURE ==========

class ItemData:
	var id: String                    # Unique identifier (e.g., "heal_potion_small")
	var display_name: String          # Human-readable name (e.g., "Small Heal Potion")
	var rarity: int                   # Rarity enum value
	var effect_type: int              # EffectType enum value
	var effect_value: float           # Effect strength (e.g., 0.15 for 15% heal)
	var effect_duration: float        # Duration in seconds (0 for instant effects)
	var icon_path: String             # Path to PNG icon (rendered from 3D model)
	var model_path: String            # Path to .blend model for 3D pickup
	var spawn_weight: float           # Probability weight within rarity tier
	
	func _init(data: Dictionary) -> void:
		id = data.get("id", "unknown")
		display_name = data.get("name", "Unknown Item")
		rarity = data.get("rarity", Rarity.COMMON)
		effect_type = data.get("effect", EffectType.HEAL)
		effect_value = data.get("value", 0.0)
		effect_duration = data.get("duration", 0.0)
		icon_path = data.get("icon", "")
		model_path = data.get("model", "")
		spawn_weight = data.get("spawn_weight", 1.0)
	
	func get_rarity_name() -> String:
		match rarity:
			Rarity.COMMON: return "Common"
			Rarity.RARE: return "Rare"
			Rarity.LEGENDARY: return "Legendary"
			_: return "Unknown"
	
	func get_rarity_color() -> Color:
		match rarity:
			Rarity.COMMON: return Color(0.6, 0.6, 0.6, 1.0)      # Gray
			Rarity.RARE: return Color(0.3, 0.5, 1.0, 1.0)        # Blue
			Rarity.LEGENDARY: return Color(1.0, 0.84, 0.0, 1.0)  # Gold
			_: return Color.WHITE

# ========== ITEM DEFINITIONS ==========

static var _items: Dictionary = {}
static var _items_by_rarity: Dictionary = {}
static var _initialized: bool = false

static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_init_items()

static func _init_items() -> void:
	# Initialize rarity arrays
	_items_by_rarity[Rarity.COMMON] = []
	_items_by_rarity[Rarity.RARE] = []
	_items_by_rarity[Rarity.LEGENDARY] = []
	
	# ===== HEALING ITEMS =====
	_register_item({
		"id": "heal_potion_small",
		"name": "Small Heal Potion",
		"rarity": Rarity.COMMON,
		"effect": EffectType.HEAL,
		"value": 0.15,  # 15% HP
		"duration": 0.0,
		"icon": "res://assets/textures/items/potion_small.png",
		"model": "res://assets/models/items/potion_small.blend",
		"spawn_weight": 1.0,
	})
	_register_item({
		"id": "heal_potion_medium",
		"name": "Medium Heal Potion",
		"rarity": Rarity.RARE,
		"effect": EffectType.HEAL,
		"value": 0.35,  # 35% HP
		"duration": 0.0,
		"icon": "res://assets/textures/items/potion_medium.png",
		"model": "res://assets/models/items/potion_medium.blend",
		"spawn_weight": 1.0,
	})
	_register_item({
		"id": "heal_potion_large",
		"name": "Large Heal Potion",
		"rarity": Rarity.LEGENDARY,
		"effect": EffectType.HEAL,
		"value": 0.75,  # 75% HP
		"duration": 0.0,
		"icon": "res://assets/textures/items/potion_large.png",
		"model": "res://assets/models/items/potion_large.blend",
		"spawn_weight": 1.0,
	})
	
	# ===== SUPERCHARGE ITEMS =====
	_register_item({
		"id": "instant_supercharge",
		"name": "Instant Supercharge",
		"rarity": Rarity.RARE,
		"effect": EffectType.INSTANT_SUPERCHARGE,
		"value": 1.0,  # 100% of normal supercharge duration
		"duration": 0.0,
		"icon": "res://assets/textures/items/crystal_orange.png",
		"model": "res://assets/models/items/crystal_orange.blend",
		"spawn_weight": 0.8,
	})
	_register_item({
		"id": "super_supercharge",
		"name": "Super Supercharge",
		"rarity": Rarity.LEGENDARY,
		"effect": EffectType.SUPER_SUPERCHARGE,
		"value": 1.5,  # 150% of normal supercharge duration
		"duration": 0.0,
		"icon": "res://assets/textures/items/crystal_gold.png",
		"model": "res://assets/models/items/crystal_gold.blend",
		"spawn_weight": 0.6,
	})
	
	# ===== SPEED ITEMS =====
	_register_item({
		"id": "speed_boost",
		"name": "Speed Boost",
		"rarity": Rarity.COMMON,
		"effect": EffectType.SPEED_BOOST,
		"value": 1.4,  # 40% faster
		"duration": 5.0,
		"icon": "res://assets/textures/items/boots_winged.png",
		"model": "res://assets/models/items/boots_winged.blend",
		"spawn_weight": 1.0,
	})
	
	# ===== COIN MULTIPLIER ITEMS =====
	_register_item({
		"id": "double_coins",
		"name": "Double Coins",
		"rarity": Rarity.COMMON,
		"effect": EffectType.DOUBLE_COINS,
		"value": 2.0,  # 2x multiplier
		"duration": 12.0,
		"icon": "res://assets/textures/items/coin_stack.png",
		"model": "res://assets/models/items/coin_stack.blend",
		"spawn_weight": 0.8,
	})
	_register_item({
		"id": "triple_coins",
		"name": "Triple Coins",
		"rarity": Rarity.RARE,
		"effect": EffectType.TRIPLE_COINS,
		"value": 3.0,  # 3x multiplier
		"duration": 10.0,
		"icon": "res://assets/textures/items/coin_pile.png",
		"model": "res://assets/models/items/coin_pile.blend",
		"spawn_weight": 0.7,
	})
	
	# ===== DEFENSIVE ITEMS =====
	_register_item({
		"id": "shield",
		"name": "Shield",
		"rarity": Rarity.RARE,
		"effect": EffectType.SHIELD,
		"value": 1.0,  # Block 1 hit
		"duration": 0.0,  # Until used
		"icon": "res://assets/textures/items/shield_orb.png",
		"model": "res://assets/models/items/shield_orb.blend",
		"spawn_weight": 0.9,
	})
	_register_item({
		"id": "power_shield",
		"name": "Power Shield",
		"rarity": Rarity.LEGENDARY,
		"effect": EffectType.SHIELD,
		"value": 3.0,  # Block 3 hits
		"duration": 0.0,  # Until used
		"icon": "res://assets/textures/items/shield_orb_power.png",
		"model": "res://assets/models/items/shield_orb_power.blend",
		"spawn_weight": 0.5,
	})
	
	# ===== SPECIAL ITEMS =====
	_register_item({
		"id": "slow_motion",
		"name": "Slow Motion",
		"rarity": Rarity.RARE,
		"effect": EffectType.SLOW_MOTION,
		"value": 0.5,  # 50% time scale
		"duration": 20.0,
		"icon": "res://assets/textures/items/hourglass.png",
		"model": "res://assets/models/items/hourglass.blend",
		"spawn_weight": 0.6,
	})
	_register_item({
		"id": "explosion",
		"name": "Explosion",
		"rarity": Rarity.LEGENDARY,
		"effect": EffectType.EXPLOSION,
		"value": 45.0, 
		"duration": 0.0,
		"icon": "res://assets/textures/items/bomb.png",
		"model": "res://assets/models/items/bomb.blend",
		"spawn_weight": 0.7,
	})
	_register_item({
		"id": "time_stop",
		"name": "Time Stop",
		"rarity": Rarity.LEGENDARY,
		"effect": EffectType.TIME_STOP,
		"value": 1.0,  # Full stop
		"duration": 5.0,
		"icon": "res://assets/textures/items/clock_frozen.png",
		"model": "res://assets/models/items/clock_frozen.blend",
		"spawn_weight": 0.4,
	})

static func _register_item(data: Dictionary) -> void:
	var item := ItemData.new(data)
	_items[item.id] = item
	_items_by_rarity[item.rarity].append(item)

# ========== PUBLIC API ==========

static func get_item(id: String) -> ItemData:
	_ensure_initialized()
	return _items.get(id)

static func get_all_items() -> Array:
	_ensure_initialized()
	return _items.values()

static func get_items_by_rarity(rarity: int) -> Array:
	_ensure_initialized()
	return _items_by_rarity.get(rarity, [])

static func get_available_items_for_distance(current_distance: float) -> Array:
	"""Returns all items that can spawn at the given distance."""
	_ensure_initialized()
	var available: Array = []
	for rarity in RARITY_UNLOCK_DISTANCE:
		if current_distance >= RARITY_UNLOCK_DISTANCE[rarity]:
			available.append_array(_items_by_rarity[rarity])
	return available

static func get_random_item_for_distance(current_distance: float, rng: RandomNumberGenerator = null) -> ItemData:
	"""Picks a random item based on rarity chances and distance unlocks."""
	_ensure_initialized()
	
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	
	# Determine which rarities are unlocked
	var available_rarities: Array[int] = []
	var total_chance: float = 0.0
	
	for rarity in RARITY_UNLOCK_DISTANCE:
		if current_distance >= RARITY_UNLOCK_DISTANCE[rarity]:
			available_rarities.append(rarity)
			total_chance += RARITY_SPAWN_CHANCE[rarity]
	
	if available_rarities.is_empty():
		return null
	
	# Pick a rarity based on weighted chance
	var roll := rng.randf() * total_chance
	var cumulative: float = 0.0
	var chosen_rarity: int = available_rarities[0]
	
	for rarity in available_rarities:
		cumulative += RARITY_SPAWN_CHANCE[rarity]
		if roll <= cumulative:
			chosen_rarity = rarity
			break
	
	# Pick a random item from that rarity tier based on spawn weights
	var rarity_items: Array = _items_by_rarity[chosen_rarity]
	if rarity_items.is_empty():
		return null
	
	var total_weight: float = 0.0
	for item in rarity_items:
		total_weight += item.spawn_weight
	
	var weight_roll := rng.randf() * total_weight
	var weight_cumulative: float = 0.0
	
	for item in rarity_items:
		weight_cumulative += item.spawn_weight
		if weight_roll <= weight_cumulative:
			return item
	
	return rarity_items[0]

static func get_rarity_color(rarity: int) -> Color:
	match rarity:
		Rarity.COMMON: return Color(0.6, 0.6, 0.6, 1.0)
		Rarity.RARE: return Color(0.3, 0.5, 1.0, 1.0)
		Rarity.LEGENDARY: return Color(1.0, 0.84, 0.0, 1.0)
		_: return Color.WHITE

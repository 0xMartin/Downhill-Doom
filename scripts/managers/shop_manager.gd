extends Node
## ShopManager - Handles shop data, purchases, and persistence

signal balance_changed(new_balance: int)
signal skin_changed(skin_id: String)
signal boosts_changed
signal crates_changed

const SHOP_DATA_PATH := "user://shop_data.json"

# ========== PRICING ==========
# Based on ~100k average earnings per game

# Skin prices (player_1 is free, others cost progressively more)
const SKIN_PRICES := {
	"player_1": 0,      # Default - free
	"player_2": 50000,
	"player_3": 75000,
	"player_4": 100000,
	"player_5": 150000,
	"player_6": 200000,
	"player_7": 300000,
	"player_8": 450000,
	"player_9": 600000,
}

# Texture skins from crates (cannot be bought directly)
const TEXTURE_SKIN_VALUE := 400000  # Refund value calculation base

# Boost prices
const BOOST_PRICES := {
	"double_hp": 25000,
	"double_coins": 30000,
	"no_enemy_npc": 35000,
	"no_enemy_building": 40000,
	"no_holes": 45000,
	"half_supercharge": 20000,
	"double_supercharge": 35000,
}

# Boost display names
const BOOST_NAMES := {
	"double_hp": "Double HP",
	"double_coins": "Double Coins",
	"no_enemy_npc": "No Enemy NPC",
	"no_enemy_building": "No Enemy Buildings",
	"no_holes": "No Holes",
	"half_supercharge": "Half Supercharge Cost",
	"double_supercharge": "Double Supercharge Time",
}

# Boost icons
const BOOST_ICONS := {
	"double_hp": "res://assets/svg/boost_double_hp.svg",
	"double_coins": "res://assets/svg/boost_double_coins.svg",
	"no_enemy_npc": "res://assets/svg/boost_no_enemy_npc.svg",
	"no_enemy_building": "res://assets/svg/boost_no_enemy_building.svg",
	"no_holes": "res://assets/svg/boost_no_holes.svg",
	"half_supercharge": "res://assets/svg/boost_half_supercharge.svg",
	"double_supercharge": "res://assets/svg/boost_double_supercharge.svg",
}

# Crate prices and properties
const CRATE_PRICES := {
	"basic": 80000,
	"premium": 200000,
	"legendary": 500000,
}

const CRATE_DROP_CHANCES := {
	"basic": {"boost": 0.60, "crate": 0.35, "skin": 0.05},
	"premium": {"boost": 0.45, "crate": 0.45, "skin": 0.10},
	"legendary": {"boost": 0.30, "crate": 0.50, "skin": 0.20},
}

const CRATE_NAMES := {
	"basic": "Basic Crate",
	"premium": "Premium Crate",
	"legendary": "Legendary Crate",
}

const CRATE_ICONS := {
	"basic": "res://assets/svg/crate_basic.svg",
	"premium": "res://assets/svg/crate_premium.svg",
	"legendary": "res://assets/svg/crate_legendary.svg",
}

# Available texture skins from crates
var available_texture_skins := ["emerald_basilisk", "steampunk"]

# ========== SHOP DATA ==========
var shop_data := {
	"selected_skin": "player_1",  # Currently equipped skin
	"owned_model_skins": ["player_1"],  # Owned model-based skins (player_1-9)
	"owned_texture_skins": [],  # Owned texture skins from crates
	"owned_boosts": {},  # {boost_id: count}
	"selected_boosts": [],  # Array of boost_ids for next game (max 2)
	"owned_crates": {},  # {crate_type: count}
}

func _ready() -> void:
	_load_shop_data()
	_scan_texture_skins()

func _scan_texture_skins() -> void:
	# Scan for available texture skins in the skins folder
	var dir := DirAccess.open("res://assets/skins")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(".png") and file_name != "mask.png":
				var skin_name := file_name.replace(".png", "")
				if skin_name not in available_texture_skins:
					available_texture_skins.append(skin_name)
			file_name = dir.get_next()
		dir.list_dir_end()

# ========== GETTERS ==========

func get_selected_skin() -> String:
	return shop_data.get("selected_skin", "player_1")

func get_owned_model_skins() -> Array:
	return shop_data.get("owned_model_skins", ["player_1"])

func get_owned_texture_skins() -> Array:
	return shop_data.get("owned_texture_skins", [])

func is_skin_owned(skin_id: String) -> bool:
	if skin_id.begins_with("player_"):
		return skin_id in get_owned_model_skins()
	else:
		return skin_id in get_owned_texture_skins()

func get_skin_price(skin_id: String) -> int:
	if skin_id in SKIN_PRICES:
		return SKIN_PRICES[skin_id]
	return 0  # Texture skins cannot be bought

func is_texture_skin(skin_id: String) -> bool:
	return not skin_id.begins_with("player_")

func get_owned_boosts() -> Dictionary:
	return shop_data.get("owned_boosts", {})

func get_boost_count(boost_id: String) -> int:
	return get_owned_boosts().get(boost_id, 0)

func get_selected_boosts() -> Array:
	return shop_data.get("selected_boosts", [])

func get_owned_crates() -> Dictionary:
	return shop_data.get("owned_crates", {})

func get_crate_count(crate_type: String) -> int:
	return get_owned_crates().get(crate_type, 0)

# ========== PURCHASES ==========

func buy_skin(skin_id: String) -> bool:
	if is_skin_owned(skin_id):
		return false  # Already owned
	
	var price := get_skin_price(skin_id)
	if price <= 0:
		return false  # Cannot buy texture skins or invalid
	
	var balance := _get_coin_balance()
	if balance < price:
		return false  # Not enough coins
	
	# Deduct coins and add skin
	_set_coin_balance(balance - price)
	
	if skin_id.begins_with("player_"):
		var owned: Array = shop_data.get("owned_model_skins", ["player_1"])
		owned.append(skin_id)
		shop_data["owned_model_skins"] = owned
	
	_save_shop_data()
	balance_changed.emit(_get_coin_balance())
	return true

func select_skin(skin_id: String) -> bool:
	if not is_skin_owned(skin_id):
		return false
	
	shop_data["selected_skin"] = skin_id
	_save_shop_data()
	skin_changed.emit(skin_id)
	return true

func buy_boost(boost_id: String) -> bool:
	if boost_id not in BOOST_PRICES:
		return false
	
	var price: int = BOOST_PRICES[boost_id]
	var balance := _get_coin_balance()
	if balance < price:
		return false
	
	_set_coin_balance(balance - price)
	
	var owned: Dictionary = shop_data.get("owned_boosts", {})
	owned[boost_id] = owned.get(boost_id, 0) + 1
	shop_data["owned_boosts"] = owned
	
	_save_shop_data()
	balance_changed.emit(_get_coin_balance())
	boosts_changed.emit()
	return true

func toggle_boost_selection(boost_id: String) -> bool:
	var selected: Array = shop_data.get("selected_boosts", [])
	var owned_count := get_boost_count(boost_id)
	
	if boost_id in selected:
		# Deselect
		selected.erase(boost_id)
		shop_data["selected_boosts"] = selected
		_save_shop_data()
		boosts_changed.emit()
		return true
	else:
		# Select (max 2)
		if selected.size() >= 2:
			return false  # Already have 2 selected
		if owned_count <= 0:
			return false  # Don't own any
		
		selected.append(boost_id)
		shop_data["selected_boosts"] = selected
		_save_shop_data()
		boosts_changed.emit()
		return true

func is_boost_selected(boost_id: String) -> bool:
	return boost_id in get_selected_boosts()

func buy_crate(crate_type: String) -> bool:
	if crate_type not in CRATE_PRICES:
		return false
	
	var price: int = CRATE_PRICES[crate_type]
	var balance := _get_coin_balance()
	if balance < price:
		return false
	
	_set_coin_balance(balance - price)
	
	var owned: Dictionary = shop_data.get("owned_crates", {})
	owned[crate_type] = owned.get(crate_type, 0) + 1
	shop_data["owned_crates"] = owned
	
	_save_shop_data()
	balance_changed.emit(_get_coin_balance())
	crates_changed.emit()
	return true

func add_crate(crate_type: String, count: int = 1) -> void:
	var owned: Dictionary = shop_data.get("owned_crates", {})
	owned[crate_type] = owned.get(crate_type, 0) + count
	shop_data["owned_crates"] = owned
	_save_shop_data()
	crates_changed.emit()

# ========== CRATE OPENING ==========

## Returns the reward from opening a crate: {type: "boost"|"crate"|"skin", id: String, is_duplicate: bool, refund: int}
func open_crate(crate_type: String) -> Dictionary:
	var owned: Dictionary = shop_data.get("owned_crates", {})
	if owned.get(crate_type, 0) <= 0:
		return {}  # Don't have this crate
	
	# Remove one crate
	owned[crate_type] = owned[crate_type] - 1
	if owned[crate_type] <= 0:
		owned.erase(crate_type)
	shop_data["owned_crates"] = owned
	
	# Roll for reward
	var chances: Dictionary = CRATE_DROP_CHANCES.get(crate_type, CRATE_DROP_CHANCES["basic"])
	var roll := randf()
	
	var reward := {}
	
	if roll < chances["boost"]:
		# Boost reward
		var boost_ids := BOOST_PRICES.keys()
		var random_boost: String = boost_ids[randi() % boost_ids.size()]
		
		var owned_boosts: Dictionary = shop_data.get("owned_boosts", {})
		owned_boosts[random_boost] = owned_boosts.get(random_boost, 0) + 1
		shop_data["owned_boosts"] = owned_boosts
		
		reward = {"type": "boost", "id": random_boost, "is_duplicate": false, "refund": 0}
		
	elif roll < chances["boost"] + chances["crate"]:
		# Crate reward - same or lower tier
		var crate_tiers := ["basic", "premium", "legendary"]
		var current_tier := crate_tiers.find(crate_type)
		var max_tier := mini(current_tier + 1, crate_tiers.size())
		var random_tier := randi() % max_tier
		var reward_crate: String = crate_tiers[random_tier]
		
		owned[reward_crate] = owned.get(reward_crate, 0) + 1
		shop_data["owned_crates"] = owned
		
		reward = {"type": "crate", "id": reward_crate, "is_duplicate": false, "refund": 0}
		
	else:
		# Skin reward
		var unowned_skins: Array = []
		for skin in available_texture_skins:
			if skin not in get_owned_texture_skins():
				unowned_skins.append(skin)
		
		if unowned_skins.is_empty():
			# All skins owned - give refund (70% of crate price)
			var refund := int(CRATE_PRICES[crate_type] * 0.7)
			_set_coin_balance(_get_coin_balance() + refund)
			reward = {"type": "skin", "id": "", "is_duplicate": true, "refund": refund}
		else:
			# Give random unowned skin
			var random_skin: String = unowned_skins[randi() % unowned_skins.size()]
			var owned_skins: Array = shop_data.get("owned_texture_skins", [])
			owned_skins.append(random_skin)
			shop_data["owned_texture_skins"] = owned_skins
			
			reward = {"type": "skin", "id": random_skin, "is_duplicate": false, "refund": 0}
	
	_save_shop_data()
	crates_changed.emit()
	boosts_changed.emit()
	balance_changed.emit(_get_coin_balance())
	
	return reward

## Generate a list of possible rewards for roulette display
func generate_roulette_items(crate_type: String, count: int = 30) -> Array:
	var items: Array = []
	var chances: Dictionary = CRATE_DROP_CHANCES.get(crate_type, CRATE_DROP_CHANCES["basic"])
	
	for i in range(count):
		var roll := randf()
		
		if roll < chances["boost"]:
			var boost_ids := BOOST_PRICES.keys()
			var random_boost: String = boost_ids[randi() % boost_ids.size()]
			items.append({"type": "boost", "id": random_boost})
		elif roll < chances["boost"] + chances["crate"]:
			var crate_tiers := ["basic", "premium", "legendary"]
			var current_tier := crate_tiers.find(crate_type)
			var max_tier := mini(current_tier + 1, crate_tiers.size())
			var random_tier := randi() % max_tier
			items.append({"type": "crate", "id": crate_tiers[random_tier]})
		else:
			if available_texture_skins.is_empty():
				items.append({"type": "boost", "id": BOOST_PRICES.keys()[0]})
			else:
				var random_skin: String = available_texture_skins[randi() % available_texture_skins.size()]
				items.append({"type": "skin", "id": random_skin})
	
	return items

# ========== GAME INTEGRATION ==========

## Call this when starting a game - consumes selected boosts
func consume_selected_boosts() -> Array:
	var selected: Array = get_selected_boosts().duplicate()
	var owned: Dictionary = shop_data.get("owned_boosts", {})
	
	for boost_id in selected:
		if owned.get(boost_id, 0) > 0:
			owned[boost_id] -= 1
			if owned[boost_id] <= 0:
				owned.erase(boost_id)
	
	shop_data["owned_boosts"] = owned
	shop_data["selected_boosts"] = []  # Clear selection after use
	_save_shop_data()
	boosts_changed.emit()
	
	return selected

## Get the model path for the currently selected skin
func get_selected_skin_model_path() -> String:
	var skin_id := get_selected_skin()
	
	if skin_id.begins_with("player_"):
		# Model-based skin
		return "res://assets/models/players/%s.blend" % skin_id
	else:
		# Texture-based skin - use player_skin.blend
		return "res://assets/models/players/player_skin.blend"

## Get the texture path for texture-based skins (or empty for model skins)
func get_selected_skin_texture_path() -> String:
	var skin_id := get_selected_skin()
	
	if skin_id.begins_with("player_"):
		return ""  # No texture needed for model skins
	else:
		return "res://assets/skins/%s.png" % skin_id

# ========== PERSISTENCE ==========

func _get_coin_balance() -> int:
	# Read from stats file (same as main_menu uses)
	const STATS_FILE := "user://stats.json"
	if FileAccess.file_exists(STATS_FILE):
		var file := FileAccess.open(STATS_FILE, FileAccess.READ)
		if file:
			var json_string := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(json_string) == OK:
				var data = json.get_data()
				if data is Dictionary:
					return int(data.get("coin_balance", 0))
	return 0

func _set_coin_balance(new_balance: int) -> void:
	const STATS_FILE := "user://stats.json"
	var stats_data := {}
	
	if FileAccess.file_exists(STATS_FILE):
		var file := FileAccess.open(STATS_FILE, FileAccess.READ)
		if file:
			var json_string := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(json_string) == OK:
				var data = json.get_data()
				if data is Dictionary:
					stats_data = data
	
	stats_data["coin_balance"] = new_balance
	
	var file := FileAccess.open(STATS_FILE, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(stats_data))
		file.close()

func _load_shop_data() -> void:
	if FileAccess.file_exists(SHOP_DATA_PATH):
		var file := FileAccess.open(SHOP_DATA_PATH, FileAccess.READ)
		if file:
			var json_string := file.get_as_text()
			file.close()
			var json := JSON.new()
			if json.parse(json_string) == OK:
				var data = json.get_data()
				if data is Dictionary:
					# Merge with defaults
					for key in data.keys():
						shop_data[key] = data[key]
					
					# Ensure player_1 is always owned
					var owned_models: Array = shop_data.get("owned_model_skins", [])
					if "player_1" not in owned_models:
						owned_models.insert(0, "player_1")
						shop_data["owned_model_skins"] = owned_models

func _save_shop_data() -> void:
	var file := FileAccess.open(SHOP_DATA_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(shop_data))
		file.close()

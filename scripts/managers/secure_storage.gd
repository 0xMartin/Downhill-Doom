extends Node
## SecureStorage - Encrypted save/load with HMAC integrity verification and device binding
## Provides tamper-resistant persistence for game data (coins, skins, boosts, stats)

const SAVE_VERSION := 1
const SECURE_DATA_PATH := "user://game_data.sav"

# Obfuscated key components (split to make static analysis harder)
const _K1 := "evAy65CmK6x5bbJdTOxM" 
const _K2 := "WNU7jj5nDQNKwGahW6Pk"
const _K3 := "Av3HMMUeLFe7fgZiND2V"
const _HMAC_SALT := "nnc8sRo4UCrjPDFvfhp0"

# Cached derived keys
var _encryption_key: String = ""
var _hmac_key: String = ""
var _device_id: String = ""

# In-memory data cache
var _data: Dictionary = {}
var _is_loaded := false

signal data_changed
signal storage_ready  # Emitted when initial data load is complete


func _ready() -> void:
	_derive_keys()
	_load_data()
	# Emit ready signal after data is loaded
	storage_ready.emit()


# ========== KEY DERIVATION ==========

func _derive_keys() -> void:
	# Get device-specific identifier
	_device_id = _get_device_fingerprint()
	
	# Derive encryption key from multiple sources
	var key_material := _K1 + _device_id.substr(0, 8) + _K2 + _K3
	_encryption_key = key_material.sha256_text()
	
	# Derive HMAC key (different from encryption key)
	var hmac_material := _HMAC_SALT + _device_id + _K3 + _K1
	_hmac_key = hmac_material.sha256_text()


func _get_device_fingerprint() -> String:
	# Combine multiple device identifiers for uniqueness
	var parts: PackedStringArray = []
	
	# Primary: OS unique ID (most reliable)
	var unique_id := OS.get_unique_id()
	if unique_id.is_empty():
		unique_id = "fallback_id"
	parts.append(unique_id)
	
	# Secondary: Device model
	parts.append(OS.get_model_name())
	
	# Tertiary: Locale for additional entropy
	parts.append(OS.get_locale())
	
	# Hash the combination
	return ":".join(parts).sha256_text()


# ========== HMAC COMPUTATION ==========

func _compute_hmac(data_string: String) -> String:
	# HMAC-like computation: hash(key + data + key)
	# Not true HMAC but sufficient for tamper detection
	var combined := _hmac_key + data_string + _hmac_key
	return combined.sha256_text()


func _verify_hmac(data_string: String, expected_hmac: String) -> bool:
	var computed := _compute_hmac(data_string)
	return computed == expected_hmac


# ========== SAVE / LOAD ==========

func _load_data() -> void:
	_data = _get_default_data()
	
	if not FileAccess.file_exists(SECURE_DATA_PATH):
		# No encrypted file exists - try migration from old unencrypted files
		_migrate_from_legacy()
		_is_loaded = true
		return
	
	# Open encrypted file
	var file := FileAccess.open_encrypted_with_pass(
		SECURE_DATA_PATH, 
		FileAccess.READ, 
		_encryption_key
	)
	
	if not file:
		push_warning("[SecureStorage] Failed to open encrypted file, using defaults")
		_is_loaded = true
		return
	
	var content := file.get_as_text()
	file.close()
	
	# Parse JSON wrapper
	var json := JSON.new()
	if json.parse(content) != OK:
		push_warning("[SecureStorage] Failed to parse JSON, using defaults")
		_is_loaded = true
		return
	
	var wrapper = json.get_data()
	if not wrapper is Dictionary:
		push_warning("[SecureStorage] Invalid data format, using defaults")
		_is_loaded = true
		return
	
	# Verify version
	var version: int = wrapper.get("v", 0)
	if version != SAVE_VERSION:
		push_warning("[SecureStorage] Version mismatch (got %d, expected %d), migrating..." % [version, SAVE_VERSION])
		# Future: add migration logic here
	
	# Verify HMAC integrity
	var stored_hmac: String = wrapper.get("hmac", "")
	var data_json: String = wrapper.get("data", "")
	
	if not _verify_hmac(data_json, stored_hmac):
		push_error("[SecureStorage] HMAC verification failed! Data may be tampered.")
		_is_loaded = true
		return
	
	# Verify device binding
	var stored_device: String = wrapper.get("device", "")
	if stored_device != _device_id:
		push_warning("[SecureStorage] Device mismatch! Data from different device.")
		# Optionally: could reject completely, but we'll allow with warning
		# For stricter security, uncomment the return:
		# _is_loaded = true
		# return
	
	# Parse actual data
	var data_json_parser := JSON.new()
	if data_json_parser.parse(data_json) != OK:
		push_warning("[SecureStorage] Failed to parse inner data JSON")
		_is_loaded = true
		return
	
	var parsed_data = data_json_parser.get_data()
	if parsed_data is Dictionary:
		# Merge with defaults (preserves new fields)
		for key in parsed_data.keys():
			_data[key] = parsed_data[key]
	
	_is_loaded = true


func save_data() -> void:
	if not _is_loaded:
		return
	
	# Prepare data JSON
	var data_json := JSON.stringify(_data)
	
	# Compute HMAC
	var hmac := _compute_hmac(data_json)
	
	# Create wrapper with metadata
	var wrapper := {
		"v": SAVE_VERSION,
		"device": _device_id,
		"hmac": hmac,
		"data": data_json,
		"ts": Time.get_unix_time_from_system(),
	}
	
	var wrapper_json := JSON.stringify(wrapper)
	
	# Save encrypted
	var file := FileAccess.open_encrypted_with_pass(
		SECURE_DATA_PATH,
		FileAccess.WRITE,
		_encryption_key
	)
	
	if not file:
		push_error("[SecureStorage] Failed to create encrypted file!")
		return
	
	file.store_string(wrapper_json)
	file.close()


func _get_default_data() -> Dictionary:
	return {
		# Coin balance
		"coin_balance": 0,
		
		# Shop data
		"selected_skin": "player_1",
		"owned_model_skins": ["player_1"],
		"owned_texture_skins": [],
		"owned_boosts": {},
		"selected_boosts": [],
		"owned_crates": {},
		
		# Statistics
		"total_games": 0,
		"total_distance": 0.0,
		"total_coins_earned": 0,
		"total_time_played": 0.0,
		"best_distance": 0.0,
		"best_coins": 0,
		"best_time": 0.0,
		
		# Kill statistics (object_id -> count)
		"destroyed_objects": {},
	}


# ========== PUBLIC API - COINS ==========

func is_storage_ready() -> bool:
	return _is_loaded


func get_coin_balance() -> int:
	return int(_data.get("coin_balance", 0))


func set_coin_balance(new_balance: int) -> void:
	_data["coin_balance"] = max(0, new_balance)
	save_data()
	data_changed.emit()


func add_coins(amount: int) -> void:
	set_coin_balance(get_coin_balance() + amount)


func spend_coins(amount: int) -> bool:
	if get_coin_balance() >= amount:
		set_coin_balance(get_coin_balance() - amount)
		return true
	return false


# ========== PUBLIC API - SHOP ==========

func get_selected_skin() -> String:
	return _data.get("selected_skin", "player_1")


func set_selected_skin(skin_id: String) -> void:
	_data["selected_skin"] = skin_id
	save_data()
	data_changed.emit()


func get_owned_model_skins() -> Array:
	return _data.get("owned_model_skins", ["player_1"])


func add_owned_model_skin(skin_id: String) -> void:
	var skins: Array = get_owned_model_skins()
	if skin_id not in skins:
		skins.append(skin_id)
		_data["owned_model_skins"] = skins
		save_data()
		data_changed.emit()


func get_owned_texture_skins() -> Array:
	return _data.get("owned_texture_skins", [])


func add_owned_texture_skin(skin_id: String) -> void:
	var skins: Array = get_owned_texture_skins()
	if skin_id not in skins:
		skins.append(skin_id)
		_data["owned_texture_skins"] = skins
		save_data()
		data_changed.emit()


func is_skin_owned(skin_id: String) -> bool:
	if skin_id.begins_with("player_"):
		return skin_id in get_owned_model_skins()
	else:
		return skin_id in get_owned_texture_skins()


func get_owned_boosts() -> Dictionary:
	return _data.get("owned_boosts", {})


func set_owned_boosts(boosts: Dictionary) -> void:
	_data["owned_boosts"] = boosts
	save_data()
	data_changed.emit()


func add_boost(boost_id: String, count: int = 1) -> void:
	var boosts: Dictionary = get_owned_boosts()
	boosts[boost_id] = boosts.get(boost_id, 0) + count
	set_owned_boosts(boosts)


func use_boost(boost_id: String) -> bool:
	var boosts: Dictionary = get_owned_boosts()
	if boosts.get(boost_id, 0) > 0:
		boosts[boost_id] -= 1
		if boosts[boost_id] <= 0:
			boosts.erase(boost_id)
		set_owned_boosts(boosts)
		return true
	return false


func get_boost_count(boost_id: String) -> int:
	return get_owned_boosts().get(boost_id, 0)


func get_selected_boosts() -> Array:
	return _data.get("selected_boosts", [])


func set_selected_boosts(boosts: Array) -> void:
	_data["selected_boosts"] = boosts
	save_data()
	data_changed.emit()


func get_owned_crates() -> Dictionary:
	return _data.get("owned_crates", {})


func set_owned_crates(crates: Dictionary) -> void:
	_data["owned_crates"] = crates
	save_data()
	data_changed.emit()


func add_crate(crate_type: String, count: int = 1) -> void:
	var crates: Dictionary = get_owned_crates()
	crates[crate_type] = crates.get(crate_type, 0) + count
	set_owned_crates(crates)


func use_crate(crate_type: String) -> bool:
	var crates: Dictionary = get_owned_crates()
	if crates.get(crate_type, 0) > 0:
		crates[crate_type] -= 1
		if crates[crate_type] <= 0:
			crates.erase(crate_type)
		set_owned_crates(crates)
		return true
	return false


func get_crate_count(crate_type: String) -> int:
	return get_owned_crates().get(crate_type, 0)


# ========== PUBLIC API - STATISTICS ==========

func get_stats() -> Dictionary:
	return {
		"total_games": _data.get("total_games", 0),
		"total_distance": _data.get("total_distance", 0.0),
		"total_coins_earned": _data.get("total_coins_earned", 0),
		"total_time_played": _data.get("total_time_played", 0.0),
		"best_distance": _data.get("best_distance", 0.0),
		"best_coins": _data.get("best_coins", 0),
		"best_time": _data.get("best_time", 0.0),
	}


func record_game_stats(coins_earned: int, distance: float, game_time: float) -> void:
	_data["total_games"] = _data.get("total_games", 0) + 1
	_data["total_distance"] = _data.get("total_distance", 0.0) + distance
	_data["total_coins_earned"] = _data.get("total_coins_earned", 0) + coins_earned
	_data["total_time_played"] = _data.get("total_time_played", 0.0) + game_time
	
	if distance > _data.get("best_distance", 0.0):
		_data["best_distance"] = distance
	if coins_earned > _data.get("best_coins", 0):
		_data["best_coins"] = coins_earned
	if game_time > _data.get("best_time", 0.0):
		_data["best_time"] = game_time
	
	# Add coins to balance
	add_coins(coins_earned)


func get_total_games() -> int:
	return _data.get("total_games", 0)


func get_best_distance() -> float:
	return _data.get("best_distance", 0.0)


func get_best_coins() -> int:
	return _data.get("best_coins", 0)


func get_best_time() -> float:
	return _data.get("best_time", 0.0)


func get_destroyed_objects() -> Dictionary:
	return _data.get("destroyed_objects", {}).duplicate()


func add_destroyed_objects(destroyed: Dictionary) -> void:
	# Merge game's destroyed objects with persistent stats
	var current: Dictionary = _data.get("destroyed_objects", {})
	for object_id in destroyed.keys():
		current[object_id] = current.get(object_id, 0) + destroyed[object_id]
	_data["destroyed_objects"] = current
	save_data()


# ========== DEBUG / MIGRATION ==========

## Import data from old unencrypted files (one-time migration)
## Called automatically when no encrypted file exists
func _migrate_from_legacy() -> bool:
	var migrated := false
	
	# Try migrating from old stats.json
	const OLD_STATS_PATH := "user://stats.json"
	if FileAccess.file_exists(OLD_STATS_PATH):
		var file := FileAccess.open(OLD_STATS_PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var old_data = json.get_data()
				if old_data is Dictionary:
					# Migrate stats
					if old_data.has("coin_balance"):
						_data["coin_balance"] = old_data["coin_balance"]
					if old_data.has("total_games"):
						_data["total_games"] = old_data["total_games"]
					if old_data.has("total_distance"):
						_data["total_distance"] = old_data["total_distance"]
					if old_data.has("total_coins"):
						_data["total_coins_earned"] = old_data["total_coins"]
					if old_data.has("total_time"):
						_data["total_time_played"] = old_data["total_time"]
					if old_data.has("best_distance"):
						_data["best_distance"] = old_data["best_distance"]
					if old_data.has("best_coins"):
						_data["best_coins"] = old_data["best_coins"]
					if old_data.has("best_time"):
						_data["best_time"] = old_data["best_time"]
					migrated = true
			file.close()
		# Delete old file after migration
		DirAccess.remove_absolute(OLD_STATS_PATH)
	
	# Try migrating from old shop_data.json
	const OLD_SHOP_PATH := "user://shop_data.json"
	if FileAccess.file_exists(OLD_SHOP_PATH):
		var file := FileAccess.open(OLD_SHOP_PATH, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				var old_data = json.get_data()
				if old_data is Dictionary:
					# Migrate shop data
					if old_data.has("selected_skin"):
						_data["selected_skin"] = old_data["selected_skin"]
					if old_data.has("owned_model_skins"):
						_data["owned_model_skins"] = old_data["owned_model_skins"]
					if old_data.has("owned_texture_skins"):
						_data["owned_texture_skins"] = old_data["owned_texture_skins"]
					if old_data.has("owned_boosts"):
						_data["owned_boosts"] = old_data["owned_boosts"]
					if old_data.has("selected_boosts"):
						_data["selected_boosts"] = old_data["selected_boosts"]
					if old_data.has("owned_crates"):
						_data["owned_crates"] = old_data["owned_crates"]
					migrated = true
			file.close()
		# Delete old file after migration
		DirAccess.remove_absolute(OLD_SHOP_PATH)
	
	if migrated:
		save_data()
		print("[SecureStorage] Migration from legacy files completed (old files removed)")
	
	return migrated


## Reset all data (for testing)
func reset_all_data() -> void:
	_data = _get_default_data()
	save_data()
	data_changed.emit()

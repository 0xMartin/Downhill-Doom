class_name QuestConfig
extends RefCounted
## Configuration for daily quest system
## Defines quest types, templates, rewards, and generation rules

# ========== ENUMS ==========

enum QuestType {
	COLLECT_COINS,      # Collect X coins
	TRAVEL_DISTANCE,    # Travel X meters
	KILL_ANY,           # Kill X enemies/objects (any type)
	KILL_SPECIFIC,      # Kill X of a specific object type
	SURVIVE_TIME,       # Survive for X seconds
	ACTIVATE_SUPERCHARGE, # Activate supercharge X times
}

enum QuestMode {
	SINGLE_RUN,    # Must complete in one run
	MULTI_RUN,     # Progress persists across runs
}

enum RewardType {
	COINS,
	BOOST,
	CRATE,
}

enum QuestDifficulty {
	EASY,
	MEDIUM,
	HARD,
}

# ========== QUEST DATA STRUCTURE ==========

class QuestData:
	var id: String                     # Unique quest ID (e.g., "quest_1")
	var type: int                      # QuestType enum
	var mode: int                      # QuestMode enum
	var difficulty: int                # QuestDifficulty enum
	var target_value: int              # Goal value (coins, distance, kills, seconds)
	var target_object_id: String       # For KILL_SPECIFIC: object ID to kill
	var reward_type: int               # RewardType enum
	var reward_value: Variant          # Coins amount, boost_id, or crate_type
	var description: String            # Human-readable description
	var short_description: String      # Short version for HUD
	
	func _init(data: Dictionary = {}) -> void:
		id = data.get("id", "")
		type = data.get("type", QuestType.COLLECT_COINS)
		mode = data.get("mode", QuestMode.SINGLE_RUN)
		difficulty = data.get("difficulty", QuestDifficulty.EASY)
		target_value = data.get("target_value", 100)
		target_object_id = data.get("target_object_id", "")
		reward_type = data.get("reward_type", RewardType.COINS)
		reward_value = data.get("reward_value", 5000)
		description = data.get("description", "")
		short_description = data.get("short_description", "")
	
	func to_dict() -> Dictionary:
		return {
			"id": id,
			"type": type,
			"mode": mode,
			"difficulty": difficulty,
			"target_value": target_value,
			"target_object_id": target_object_id,
			"reward_type": reward_type,
			"reward_value": reward_value,
			"description": description,
			"short_description": short_description,
		}
	
	static func from_dict(data: Dictionary) -> QuestData:
		return QuestData.new(data)

# ========== QUEST TEMPLATES ==========

# Value ranges for each difficulty
const COIN_TARGETS := {
	QuestDifficulty.EASY: [5000, 15000],
	QuestDifficulty.MEDIUM: [25000, 50000],
	QuestDifficulty.HARD: [75000, 150000],
}

const DISTANCE_TARGETS := {
	QuestDifficulty.EASY: [1000, 2000],
	QuestDifficulty.MEDIUM: [3000, 5000],
	QuestDifficulty.HARD: [7500, 12000],
}

const KILL_ANY_TARGETS := {
	QuestDifficulty.EASY: [50, 100],
	QuestDifficulty.MEDIUM: [150, 300],
	QuestDifficulty.HARD: [500, 1000],
}

const KILL_SPECIFIC_TARGETS := {
	QuestDifficulty.EASY: [10, 25],
	QuestDifficulty.MEDIUM: [30, 60],
	QuestDifficulty.HARD: [75, 150],
}

const SURVIVE_TIME_TARGETS := {
	QuestDifficulty.EASY: [60, 90],
	QuestDifficulty.MEDIUM: [120, 180],
	QuestDifficulty.HARD: [240, 360],
}

const SUPERCHARGE_TARGETS := {
	QuestDifficulty.EASY: [2, 3],
	QuestDifficulty.MEDIUM: [4, 6],
	QuestDifficulty.HARD: [8, 12],
}

# ========== REWARDS ==========

const COIN_REWARDS := {
	QuestDifficulty.EASY: [5000, 15000],
	QuestDifficulty.MEDIUM: [20000, 50000],
	QuestDifficulty.HARD: [75000, 150000],
}

const CRATE_REWARDS := {
	QuestDifficulty.EASY: "basic",
	QuestDifficulty.MEDIUM: "premium",
	QuestDifficulty.HARD: "legendary",
}

# Boost rewards pool
const BOOST_REWARD_POOL := [
	"double_hp",
	"double_coins",
	"no_enemy_npc",
	"no_enemy_building",
	"no_holes",
	"half_supercharge",
	"double_supercharge",
]

# ========== KILLABLE OBJECTS ==========

# Objects that can be targets for KILL_SPECIFIC quests
# Pulled from ObjectConfig categories
static func get_killable_object_ids() -> Array:
	var killable := []
	
	# Trees
	for obj in ObjectConfig.get_trees():
		if obj.is_destructible:
			killable.append(obj.id)
	
	# Buildings
	for obj in ObjectConfig.get_buildings():
		if obj.is_destructible:
			killable.append(obj.id)
	
	# Enemy NPCs
	for obj in ObjectConfig.get_objects_by_category(ObjectConfig.Category.NPC_ENEMY):
		killable.append(obj.id)
	
	# Aerial NPCs
	for obj in ObjectConfig.get_objects_by_category(ObjectConfig.Category.NPC_AERIAL):
		killable.append(obj.id)
	
	# Enemy buildings
	for obj in ObjectConfig.get_building_enemies():
		if obj.is_destructible:
			killable.append(obj.id)
	
	return killable

# Subset of more interesting targets for specific kill quests
static func get_specific_kill_targets() -> Array:
	var targets := []
	
	# Enemy NPCs are most interesting targets
	for obj in ObjectConfig.get_objects_by_category(ObjectConfig.Category.NPC_ENEMY):
		targets.append(obj.id)
	
	# Aerial NPCs
	for obj in ObjectConfig.get_objects_by_category(ObjectConfig.Category.NPC_AERIAL):
		targets.append(obj.id)
	
	# Add some common trees (interesting variety)
	var trees := ObjectConfig.get_trees()
	if trees.size() > 0:
		targets.append(trees[0].id)  # First tree type
	
	return targets

# ========== QUEST GENERATION ==========

static func generate_random_quest(quest_id: String, difficulty: int, used_types: Array = []) -> QuestData:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	
	# Available quest types
	var available_types := [
		QuestType.COLLECT_COINS,
		QuestType.TRAVEL_DISTANCE,
		QuestType.KILL_ANY,
		QuestType.KILL_SPECIFIC,
		QuestType.SURVIVE_TIME,
		QuestType.ACTIVATE_SUPERCHARGE,
	]
	
	# Remove already used types if possible (allow duplicates if all used)
	var filtered_types := available_types.filter(func(t): return t not in used_types)
	if filtered_types.is_empty():
		filtered_types = available_types
	
	var quest_type: int = filtered_types[rng.randi() % filtered_types.size()]
	
	# Determine mode - harder quests more likely to be multi-run
	var mode: int = QuestMode.SINGLE_RUN
	if difficulty == QuestDifficulty.HARD:
		mode = QuestMode.MULTI_RUN if rng.randf() < 0.7 else QuestMode.SINGLE_RUN
	elif difficulty == QuestDifficulty.MEDIUM:
		mode = QuestMode.MULTI_RUN if rng.randf() < 0.4 else QuestMode.SINGLE_RUN
	else:
		mode = QuestMode.MULTI_RUN if rng.randf() < 0.2 else QuestMode.SINGLE_RUN
	
	# Generate target value
	var target_value := _get_target_value(quest_type, difficulty, rng)
	
	# For specific kills, pick a random target
	var target_object_id := ""
	if quest_type == QuestType.KILL_SPECIFIC:
		var targets := get_specific_kill_targets()
		if targets.size() > 0:
			target_object_id = targets[rng.randi() % targets.size()]
	
	# Generate reward
	var reward_type: int
	var reward_value: Variant
	
	# Determine reward type based on difficulty and randomness
	var reward_roll := rng.randf()
	if difficulty == QuestDifficulty.HARD:
		if reward_roll < 0.4:
			reward_type = RewardType.CRATE
			reward_value = CRATE_REWARDS[difficulty]
		elif reward_roll < 0.7:
			reward_type = RewardType.BOOST
			reward_value = BOOST_REWARD_POOL[rng.randi() % BOOST_REWARD_POOL.size()]
		else:
			reward_type = RewardType.COINS
			var coin_range: Array = COIN_REWARDS[difficulty]
			reward_value = rng.randi_range(coin_range[0], coin_range[1])
	elif difficulty == QuestDifficulty.MEDIUM:
		if reward_roll < 0.3:
			reward_type = RewardType.CRATE
			reward_value = CRATE_REWARDS[difficulty]
		elif reward_roll < 0.5:
			reward_type = RewardType.BOOST
			reward_value = BOOST_REWARD_POOL[rng.randi() % BOOST_REWARD_POOL.size()]
		else:
			reward_type = RewardType.COINS
			var coin_range: Array = COIN_REWARDS[difficulty]
			reward_value = rng.randi_range(coin_range[0], coin_range[1])
	else:
		if reward_roll < 0.2:
			reward_type = RewardType.CRATE
			reward_value = CRATE_REWARDS[difficulty]
		else:
			reward_type = RewardType.COINS
			var coin_range: Array = COIN_REWARDS[difficulty]
			reward_value = rng.randi_range(coin_range[0], coin_range[1])
	
	# Round coin rewards to nice numbers
	if reward_type == RewardType.COINS:
		reward_value = _round_to_nice_number(reward_value)
	
	# Generate description
	var description := _generate_description(quest_type, target_value, target_object_id, mode)
	var short_description := _generate_short_description(quest_type, target_value, target_object_id)
	
	return QuestData.new({
		"id": quest_id,
		"type": quest_type,
		"mode": mode,
		"difficulty": difficulty,
		"target_value": target_value,
		"target_object_id": target_object_id,
		"reward_type": reward_type,
		"reward_value": reward_value,
		"description": description,
		"short_description": short_description,
	})

static func _get_target_value(quest_type: int, difficulty: int, rng: RandomNumberGenerator) -> int:
	var ranges: Dictionary
	match quest_type:
		QuestType.COLLECT_COINS:
			ranges = COIN_TARGETS
		QuestType.TRAVEL_DISTANCE:
			ranges = DISTANCE_TARGETS
		QuestType.KILL_ANY:
			ranges = KILL_ANY_TARGETS
		QuestType.KILL_SPECIFIC:
			ranges = KILL_SPECIFIC_TARGETS
		QuestType.SURVIVE_TIME:
			ranges = SURVIVE_TIME_TARGETS
		QuestType.ACTIVATE_SUPERCHARGE:
			ranges = SUPERCHARGE_TARGETS
		_:
			return 100
	
	var range_array: Array = ranges[difficulty]
	var value := rng.randi_range(range_array[0], range_array[1])
	return _round_to_nice_number(value)

static func _round_to_nice_number(value: int) -> int:
	# Round to nearest nice number based on magnitude
	if value >= 10000:
		return int(round(value / 5000.0)) * 5000
	elif value >= 1000:
		return int(round(value / 500.0)) * 500
	elif value >= 100:
		return int(round(value / 50.0)) * 50
	elif value >= 10:
		return int(round(value / 5.0)) * 5
	return value

static func _generate_description(quest_type: int, target_value: int, target_object_id: String, mode: int) -> String:
	var mode_suffix := " (across multiple runs)" if mode == QuestMode.MULTI_RUN else " in a single run"
	
	match quest_type:
		QuestType.COLLECT_COINS:
			return "Collect %s coins%s" % [_format_number(target_value), mode_suffix]
		QuestType.TRAVEL_DISTANCE:
			return "Travel %s meters%s" % [_format_number(target_value), mode_suffix]
		QuestType.KILL_ANY:
			return "Destroy %s objects%s" % [_format_number(target_value), mode_suffix]
		QuestType.KILL_SPECIFIC:
			var obj_name := _get_object_display_name(target_object_id)
			return "Destroy %s %s%s" % [_format_number(target_value), obj_name, mode_suffix]
		QuestType.SURVIVE_TIME:
			return "Survive for %s seconds%s" % [_format_number(target_value), mode_suffix]
		QuestType.ACTIVATE_SUPERCHARGE:
			return "Activate supercharge %s times%s" % [_format_number(target_value), mode_suffix]
	return "Unknown quest"

static func _generate_short_description(quest_type: int, target_value: int, target_object_id: String) -> String:
	match quest_type:
		QuestType.COLLECT_COINS:
			return "Collect %s coins" % _format_number(target_value)
		QuestType.TRAVEL_DISTANCE:
			return "Travel %sm" % _format_number(target_value)
		QuestType.KILL_ANY:
			return "Destroy %s objects" % _format_number(target_value)
		QuestType.KILL_SPECIFIC:
			var obj_name := _get_object_display_name(target_object_id)
			return "Destroy %s %s" % [_format_number(target_value), obj_name]
		QuestType.SURVIVE_TIME:
			return "Survive %ss" % _format_number(target_value)
		QuestType.ACTIVATE_SUPERCHARGE:
			return "Supercharge x%s" % _format_number(target_value)
	return "Quest"

static func _format_number(value: int) -> String:
	if value >= 1000000:
		return "%.1fM" % (value / 1000000.0)
	elif value >= 1000:
		return "%.1fk" % (value / 1000.0)
	return str(value)

static func _get_object_display_name(object_id: String) -> String:
	var obj_data: ObjectConfig.ObjectData = ObjectConfig.get_object(object_id)
	if obj_data:
		return obj_data.display_name
	return object_id

# ========== DAILY QUEST GENERATION ==========

static func generate_daily_quests(date_seed: int) -> Array[QuestData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = date_seed
	
	var quests: Array[QuestData] = []
	var used_types: Array = []
	
	# Generate 5 quests with varying difficulties:
	# 2 Easy, 2 Medium, 1 Hard
	var difficulties := [
		QuestDifficulty.EASY,
		QuestDifficulty.EASY,
		QuestDifficulty.MEDIUM,
		QuestDifficulty.MEDIUM,
		QuestDifficulty.HARD,
	]
	
	# Shuffle difficulties
	for i in range(difficulties.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var temp: int = difficulties[i]
		difficulties[i] = difficulties[j]
		difficulties[j] = temp
	
	for i in range(5):
		var quest := generate_random_quest("quest_%d" % i, difficulties[i], used_types)
		used_types.append(quest.type)
		quests.append(quest)
	
	return quests

static func get_date_seed() -> int:
	# Generate seed based on UTC date (resets at midnight UTC)
	var datetime := Time.get_datetime_dict_from_system(true)  # true = UTC
	return datetime.year * 10000 + datetime.month * 100 + datetime.day

static func get_current_utc_date_string() -> String:
	var datetime := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [datetime.year, datetime.month, datetime.day]

static func get_seconds_until_reset() -> int:
	var datetime := Time.get_datetime_dict_from_system(true)
	var seconds_today: int = int(datetime.hour) * 3600 + int(datetime.minute) * 60 + int(datetime.second)
	return 86400 - seconds_today  # Seconds until midnight UTC

# ========== REWARD DISPLAY HELPERS ==========

static func get_reward_description(quest: QuestData) -> String:
	match quest.reward_type:
		RewardType.COINS:
			return "%s coins" % _format_number(quest.reward_value)
		RewardType.BOOST:
			return _get_boost_name(quest.reward_value)
		RewardType.CRATE:
			return _get_crate_name(quest.reward_value)
	return "Unknown reward"

static func _get_boost_name(boost_id: String) -> String:
	const BOOST_NAMES := {
		"double_hp": "Double HP",
		"double_coins": "Double Coins",
		"no_enemy_npc": "No Enemy NPC",
		"no_enemy_building": "No Enemy Buildings",
		"no_holes": "No Holes",
		"half_supercharge": "Half Supercharge Cost",
		"double_supercharge": "Double Supercharge Time",
	}
	return BOOST_NAMES.get(boost_id, boost_id)

static func _get_crate_name(crate_type: String) -> String:
	const CRATE_NAMES := {
		"basic": "Basic Crate",
		"premium": "Premium Crate",
		"legendary": "Legendary Crate",
	}
	return CRATE_NAMES.get(crate_type, crate_type)

static func get_quest_type_icon(quest_type: int) -> String:
	match quest_type:
		QuestType.COLLECT_COINS:
			return "res://assets/svg/coin.svg"
		QuestType.TRAVEL_DISTANCE:
			return "res://assets/svg/distance.svg"
		QuestType.KILL_ANY:
			return "res://assets/svg/games.svg"
		QuestType.KILL_SPECIFIC:
			return "res://assets/svg/games.svg"
		QuestType.SURVIVE_TIME:
			return "res://assets/svg/time.svg"
		QuestType.ACTIVATE_SUPERCHARGE:
			return "res://assets/svg/boost_double_supercharge.svg"
	return "res://assets/svg/quest.svg"

static func get_difficulty_color(difficulty: int) -> Color:
	match difficulty:
		QuestDifficulty.EASY:
			return Color(0.4, 0.8, 0.4)  # Green
		QuestDifficulty.MEDIUM:
			return Color(0.9, 0.7, 0.2)  # Yellow/Gold
		QuestDifficulty.HARD:
			return Color(0.9, 0.3, 0.3)  # Red
	return Color.WHITE

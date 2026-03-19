class_name QuestConfig
extends RefCounted
## Configuration for daily quest system
## Defines quest types, templates, rewards, and generation rules
##
## Balance notes (based on 5 min run = 100-200k coins):
## - EASY quest = ~1 run effort (5 min)
## - MEDIUM quest = ~2-3 runs effort (10-15 min)
## - HARD quest = ~5+ runs effort (25+ min)
##
## Reward distribution target: 30% coins, 50% boosts, 20% crates

# ========== ENUMS ==========

enum QuestType {
	COLLECT_COINS,        # Collect X coins
	TRAVEL_DISTANCE,      # Travel X meters
	KILL_ANY,             # Kill X enemies/objects (any type)
	KILL_SPECIFIC,        # Kill X of a specific object type
	SURVIVE_TIME,         # Survive for X seconds
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

# Object rarity based on spawn_chance
enum ObjectRarity {
	COMMON,    # spawn_chance >= 0.3 (Chicken, Rabbit, Sheep, Trees)
	UNCOMMON,  # spawn_chance 0.1-0.29 (Dog, Cat, Dark Pawn, Dark Knight)
	RARE,      # spawn_chance < 0.1 (Squirrel, Penguin, Lord Penguin, Wizard, Plane)
}

# ========== QUEST DATA STRUCTURE ==========

class QuestData:
	var id: String
	var type: int
	var mode: int
	var difficulty: int
	var target_value: int
	var target_object_id: String
	var reward_type: int
	var reward_value: Variant
	var description: String
	var short_description: String
	
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

# ========== QUEST TARGET VALUES ==========
# Based on: 1 run = 5 min = ~150k coins, ~2000m distance

# Coin targets (EASY=1 run, MEDIUM=2-3 runs, HARD=5+ runs)
const COIN_TARGETS := {
	QuestDifficulty.EASY: [50000, 100000],     # ~1 run
	QuestDifficulty.MEDIUM: [150000, 250000],  # ~2 runs
	QuestDifficulty.HARD: [400000, 600000],    # ~4-5 runs
}

const DISTANCE_TARGETS := {
	QuestDifficulty.EASY: [1500, 2500],    # ~1 run
	QuestDifficulty.MEDIUM: [4000, 6000],  # ~2-3 runs
	QuestDifficulty.HARD: [10000, 15000],  # ~5+ runs
}

const KILL_ANY_TARGETS := {
	QuestDifficulty.EASY: [75, 125],      # ~1 run
	QuestDifficulty.MEDIUM: [200, 350],   # ~2-3 runs
	QuestDifficulty.HARD: [600, 1000],    # ~5+ runs
}

# Kill specific targets - adjusted by object RARITY, not just category
# COMMON objects (spawn >= 30%): high counts
const KILL_SPECIFIC_COMMON := {
	QuestDifficulty.EASY: [15, 25],       # Common object, easy quest
	QuestDifficulty.MEDIUM: [40, 60],     # Common object, medium quest
	QuestDifficulty.HARD: [100, 150],     # Common object, hard quest
}

# UNCOMMON objects (spawn 10-29%): medium counts
const KILL_SPECIFIC_UNCOMMON := {
	QuestDifficulty.EASY: [8, 15],        # Uncommon object, easy quest
	QuestDifficulty.MEDIUM: [20, 35],     # Uncommon object, medium quest
	QuestDifficulty.HARD: [50, 80],       # Uncommon object, hard quest
}

# RARE objects (spawn < 10%): low counts - these are actually hard to find!
const KILL_SPECIFIC_RARE := {
	QuestDifficulty.EASY: [3, 5],         # Rare object (squirrel 7%), easy quest
	QuestDifficulty.MEDIUM: [8, 12],      # Rare object, medium quest
	QuestDifficulty.HARD: [18, 25],       # Rare object, hard quest
}

# AERIAL/LEGENDARY objects (plane, lord penguin): very low counts
const KILL_SPECIFIC_LEGENDARY := {
	QuestDifficulty.EASY: [1, 2],         # Legendary object, easy quest
	QuestDifficulty.MEDIUM: [3, 5],       # Legendary object, medium quest
	QuestDifficulty.HARD: [8, 12],        # Legendary object, hard quest
}

const SURVIVE_TIME_TARGETS := {
	QuestDifficulty.EASY: [90, 150],      # 1.5-2.5 min
	QuestDifficulty.MEDIUM: [180, 270],   # 3-4.5 min (challenging single run)
	QuestDifficulty.HARD: [360, 480],     # 6-8 min (very long run or multi)
}

# Supercharge targets - calculated based on escalating costs:
# 1st=10, 2nd=17, 3rd=29, 4th=49, 5th=83, 6th=141, 7th=240 objects needed
# With ~600 max kills per run, realistic limits are:
# - Single run: 5-6 supercharges max (needs ~330 objects)
# - Multi-run: 7-8 supercharges realistic (needs ~570-980 objects over 2 runs)
const SUPERCHARGE_TARGETS := {
	QuestDifficulty.EASY: [2, 3],     # Needs 27-56 objects - easy
	QuestDifficulty.MEDIUM: [3, 4],   # Needs 56-105 objects - moderate
	QuestDifficulty.HARD: [5, 6],     # Needs 188-329 objects - challenging but doable
}

# ========== REWARDS ==========
# Rewards should be BONUS value on top of what player earns during quest

# Coin rewards - should feel rewarding, not just matching effort
const COIN_REWARDS := {
	QuestDifficulty.EASY: [25000, 45000],      # Nice bonus for 5 min
	QuestDifficulty.MEDIUM: [60000, 100000],   # Good bonus for 15 min
	QuestDifficulty.HARD: [150000, 250000],    # Big bonus for 30+ min
}

# Crate rewards by difficulty (only MEDIUM+ get crates, HARD gets better crates)
const CRATE_REWARDS_BY_DIFFICULTY := {
	QuestDifficulty.EASY: [],                          # No crates for easy
	QuestDifficulty.MEDIUM: ["basic", "basic"],        # Basic only
	QuestDifficulty.HARD: ["premium", "legendary"],    # Premium or legendary
}

# Boost rewards pool with rough values for reference
# (50k each approximately)
const BOOST_REWARD_POOL := [
	"double_hp",
	"double_coins",
	"no_enemy_npc",
	"no_enemy_building",
	"no_holes",
	"half_supercharge",
	"double_supercharge",
]

# Reward type distribution per difficulty
# Target overall: 30% coins, 50% boost, 20% crate
const REWARD_CHANCES := {
	QuestDifficulty.EASY: {
		RewardType.COINS: 0.35,   # 35% coins
		RewardType.BOOST: 0.65,   # 65% boost
		RewardType.CRATE: 0.0,    # 0% crate (too valuable for easy)
	},
	QuestDifficulty.MEDIUM: {
		RewardType.COINS: 0.30,   # 30% coins
		RewardType.BOOST: 0.50,   # 50% boost
		RewardType.CRATE: 0.20,   # 20% crate (basic)
	},
	QuestDifficulty.HARD: {
		RewardType.COINS: 0.25,   # 25% coins
		RewardType.BOOST: 0.40,   # 40% boost
		RewardType.CRATE: 0.35,   # 35% crate (premium/legendary)
	},
}

# ========== OBJECT RARITY CLASSIFICATION ==========

# Get object rarity based on spawn_chance from ObjectConfig
static func get_object_rarity(object_id: String) -> int:
	var obj_data := ObjectConfig.get_object(object_id)
	if obj_data == null:
		return ObjectRarity.COMMON
	
	# Special cases - aerial and legendary objects always LEGENDARY tier
	if object_id == "npc_plane" or object_id == "npc_lord_penguin":
		return ObjectRarity.RARE + 1  # Use value 3 for LEGENDARY
	
	var spawn_chance: float = obj_data.spawn_chance
	
	if spawn_chance >= 0.3:
		return ObjectRarity.COMMON
	elif spawn_chance >= 0.1:
		return ObjectRarity.UNCOMMON
	else:
		return ObjectRarity.RARE

# Get all killable objects with their rarity
static func get_killable_objects_with_rarity() -> Array:
	var objects := []
	
	# Trees - check spawn chance
	for obj in ObjectConfig.get_trees():
		if obj.is_destructible:
			objects.append({
				"id": obj.id,
				"rarity": _classify_spawn_chance(obj.spawn_chance),
				"category": "tree",
			})
	
	# Small buildings
	for obj in ObjectConfig.get_buildings():
		if obj.is_destructible:
			objects.append({
				"id": obj.id,
				"rarity": _classify_spawn_chance(obj.spawn_chance),
				"category": "building",
			})
	
	# Friend NPCs - these vary significantly in spawn chance!
	for obj in ObjectConfig.get_npcs_friend():
		var rarity: int
		if obj.id == "npc_lord_penguin":
			rarity = ObjectRarity.RARE + 1  # LEGENDARY
		else:
			rarity = _classify_spawn_chance(obj.spawn_chance)
		objects.append({
			"id": obj.id,
			"rarity": rarity,
			"category": "friend_npc",
		})
	
	# Enemy NPCs
	for obj in ObjectConfig.get_objects_by_category(ObjectConfig.Category.NPC_ENEMY):
		objects.append({
			"id": obj.id,
			"rarity": _classify_spawn_chance(obj.spawn_chance),
			"category": "enemy_npc",
		})
	
	# Aerial NPCs - always LEGENDARY (hardest to kill)
	for obj in ObjectConfig.get_objects_by_category(ObjectConfig.Category.NPC_AERIAL):
		objects.append({
			"id": obj.id,
			"rarity": ObjectRarity.RARE + 1,  # LEGENDARY
			"category": "aerial",
		})
	
	return objects

static func _classify_spawn_chance(spawn_chance: float) -> int:
	if spawn_chance >= 0.3:
		return ObjectRarity.COMMON
	elif spawn_chance >= 0.1:
		return ObjectRarity.UNCOMMON
	else:
		return ObjectRarity.RARE

# ========== QUEST GENERATION ==========

static func generate_random_quest(quest_id: String, difficulty: int, used_types: Array = [], rng: RandomNumberGenerator = null) -> QuestData:
	if rng == null:
		rng = RandomNumberGenerator.new()
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
	
	# Remove already used types if possible
	var filtered_types := available_types.filter(func(t): return t not in used_types)
	if filtered_types.is_empty():
		filtered_types = available_types
	
	var quest_type: int = filtered_types[rng.randi() % filtered_types.size()]
	
	# Determine mode - harder quests more likely to be multi-run
	var mode := _determine_quest_mode(difficulty, quest_type, rng)
	
	# For specific kills, pick a target based on quest difficulty and rarity
	var target_object_id := ""
	var object_rarity: int = ObjectRarity.COMMON
	
	if quest_type == QuestType.KILL_SPECIFIC:
		var result := _select_kill_target(difficulty, rng)
		target_object_id = result.id
		object_rarity = result.rarity
	
	# Generate target value
	var target_value := _calculate_target_value(quest_type, difficulty, object_rarity, rng)
	
	# Generate reward
	var reward := _generate_reward(difficulty, rng)
	
	# Generate descriptions
	var description := _generate_description(quest_type, target_value, target_object_id, mode)
	var short_description := _generate_short_description(quest_type, target_value, target_object_id)
	
	return QuestData.new({
		"id": quest_id,
		"type": quest_type,
		"mode": mode,
		"difficulty": difficulty,
		"target_value": target_value,
		"target_object_id": target_object_id,
		"reward_type": reward.type,
		"reward_value": reward.value,
		"description": description,
		"short_description": short_description,
	})

static func _determine_quest_mode(difficulty: int, quest_type: int, rng: RandomNumberGenerator) -> int:
	# Some quest types work better as multi-run
	var multi_run_chance: float
	
	match difficulty:
		QuestDifficulty.EASY:
			multi_run_chance = 0.1  # 10% - easy quests mostly single run
		QuestDifficulty.MEDIUM:
			multi_run_chance = 0.4  # 40%
		QuestDifficulty.HARD:
			multi_run_chance = 0.7  # 70% - hard quests often need multiple runs
		_:
			multi_run_chance = 0.3
	
	# Survival quests prefer single run (more intense)
	if quest_type == QuestType.SURVIVE_TIME:
		multi_run_chance *= 0.5
	
	return QuestMode.MULTI_RUN if rng.randf() < multi_run_chance else QuestMode.SINGLE_RUN

static func _select_kill_target(difficulty: int, rng: RandomNumberGenerator) -> Dictionary:
	var all_objects := get_killable_objects_with_rarity()
	
	# Filter by appropriate rarity for quest difficulty
	var appropriate_objects: Array
	
	match difficulty:
		QuestDifficulty.EASY:
			# Easy quests: only COMMON and UNCOMMON objects
			appropriate_objects = all_objects.filter(func(o): 
				return o.rarity <= ObjectRarity.UNCOMMON
			)
		QuestDifficulty.MEDIUM:
			# Medium quests: prefer UNCOMMON/RARE, allow COMMON
			appropriate_objects = all_objects.filter(func(o): 
				return o.rarity <= ObjectRarity.RARE
			)
		QuestDifficulty.HARD:
			# Hard quests: all objects including LEGENDARY
			appropriate_objects = all_objects
	
	if appropriate_objects.is_empty():
		appropriate_objects = all_objects
	
	# Weight selection towards appropriate difficulty
	# For MEDIUM/HARD, prefer harder objects
	var weighted_selection: Array = []
	for obj in appropriate_objects:
		var weight := 1
		if difficulty == QuestDifficulty.MEDIUM:
			if obj.rarity == ObjectRarity.UNCOMMON:
				weight = 3
			elif obj.rarity == ObjectRarity.RARE:
				weight = 2
		elif difficulty == QuestDifficulty.HARD:
			if obj.rarity == ObjectRarity.RARE:
				weight = 3
			elif obj.rarity > ObjectRarity.RARE:  # LEGENDARY
				weight = 2
		
		for i in range(weight):
			weighted_selection.append(obj)
	
	var selected: Dictionary = weighted_selection[rng.randi() % weighted_selection.size()]
	return {"id": selected.id, "rarity": selected.rarity}

static func _calculate_target_value(quest_type: int, difficulty: int, object_rarity: int, rng: RandomNumberGenerator) -> int:
	var ranges: Dictionary
	
	match quest_type:
		QuestType.COLLECT_COINS:
			ranges = COIN_TARGETS
		QuestType.TRAVEL_DISTANCE:
			ranges = DISTANCE_TARGETS
		QuestType.KILL_ANY:
			ranges = KILL_ANY_TARGETS
		QuestType.KILL_SPECIFIC:
			# Use object rarity to determine kill count
			if object_rarity > ObjectRarity.RARE:  # LEGENDARY
				ranges = KILL_SPECIFIC_LEGENDARY
			elif object_rarity == ObjectRarity.RARE:
				ranges = KILL_SPECIFIC_RARE
			elif object_rarity == ObjectRarity.UNCOMMON:
				ranges = KILL_SPECIFIC_UNCOMMON
			else:
				ranges = KILL_SPECIFIC_COMMON
		QuestType.SURVIVE_TIME:
			ranges = SURVIVE_TIME_TARGETS
		QuestType.ACTIVATE_SUPERCHARGE:
			ranges = SUPERCHARGE_TARGETS
		_:
			return 100
	
	var range_array: Array = ranges[difficulty]
	var value := rng.randi_range(range_array[0], range_array[1])
	return _round_to_nice_number(value)

static func _generate_reward(difficulty: int, rng: RandomNumberGenerator) -> Dictionary:
	var chances: Dictionary = REWARD_CHANCES[difficulty]
	var roll := rng.randf()
	
	var reward_type: int
	var reward_value: Variant
	
	var coin_threshold: float = chances[RewardType.COINS]
	var boost_threshold: float = coin_threshold + chances[RewardType.BOOST]
	
	if roll < coin_threshold:
		# Coin reward
		reward_type = RewardType.COINS
		var coin_range: Array = COIN_REWARDS[difficulty]
		reward_value = _round_to_nice_number(rng.randi_range(coin_range[0], coin_range[1]))
		
	elif roll < boost_threshold:
		# Boost reward
		reward_type = RewardType.BOOST
		reward_value = BOOST_REWARD_POOL[rng.randi() % BOOST_REWARD_POOL.size()]
		
	else:
		# Crate reward
		var crate_options: Array = CRATE_REWARDS_BY_DIFFICULTY[difficulty]
		if crate_options.is_empty():
			# Fallback to boost if no crates for this difficulty
			reward_type = RewardType.BOOST
			reward_value = BOOST_REWARD_POOL[rng.randi() % BOOST_REWARD_POOL.size()]
		else:
			reward_type = RewardType.CRATE
			reward_value = crate_options[rng.randi() % crate_options.size()]
	
	return {"type": reward_type, "value": reward_value}

static func _round_to_nice_number(value: int) -> int:
	if value >= 100000:
		return int(round(value / 25000.0)) * 25000
	elif value >= 10000:
		return int(round(value / 5000.0)) * 5000
	elif value >= 1000:
		return int(round(value / 500.0)) * 500
	elif value >= 100:
		return int(round(value / 25.0)) * 25
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
	var obj_data := ObjectConfig.get_object(object_id)
	if obj_data:
		return obj_data.display_name
	return object_id

# ========== DAILY QUEST GENERATION ==========

static func generate_daily_quests(date_seed: int) -> Array[QuestData]:
	var rng := RandomNumberGenerator.new()
	rng.seed = date_seed
	
	var quests: Array[QuestData] = []
	var used_types: Array = []
	
	# Generate 5 quests: 2 Easy, 2 Medium, 1 Hard
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
		var quest := generate_random_quest("quest_%d" % i, difficulties[i], used_types, rng)
		used_types.append(quest.type)
		quests.append(quest)
	
	return quests

static func get_date_seed() -> int:
	var datetime := Time.get_datetime_dict_from_system(true)
	return datetime.year * 10000 + datetime.month * 100 + datetime.day

static func get_current_utc_date_string() -> String:
	var datetime := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02d" % [datetime.year, datetime.month, datetime.day]

static func get_seconds_until_reset() -> int:
	var datetime := Time.get_datetime_dict_from_system(true)
	var seconds_today: int = int(datetime.hour) * 3600 + int(datetime.minute) * 60 + int(datetime.second)
	return 86400 - seconds_today

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
		QuestType.KILL_ANY, QuestType.KILL_SPECIFIC:
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

# ========== LEGACY COMPATIBILITY ==========

# Legacy functions kept for compatibility
static func get_killable_object_ids() -> Array:
	var killable := []
	for obj in get_killable_objects_with_rarity():
		killable.append(obj.id)
	return killable

static func get_object_difficulty(object_id: String) -> int:
	# Map new rarity to old difficulty system
	var rarity := get_object_rarity(object_id)
	if rarity > ObjectRarity.RARE:
		return 2  # HARD
	elif rarity == ObjectRarity.RARE:
		return 2  # HARD (rare objects are hard to find)
	elif rarity == ObjectRarity.UNCOMMON:
		return 1  # MEDIUM
	return 0  # EASY

static func get_specific_kill_targets_for_difficulty(_quest_difficulty: int) -> Array:
	return get_killable_objects_with_rarity()

static func get_specific_kill_targets() -> Array:
	return get_killable_object_ids()

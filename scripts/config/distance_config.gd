class_name DistanceConfig
extends RefCounted
## Configuration for distance-based spawn unlocking
## Objects and features unlock progressively as the player travels further
##
## Each milestone defines the minimum distance (in meters) required
## for objects/features to start spawning

# ========== FEATURE UNLOCK DISTANCES ==========

## Distance at which terrain holes start appearing
const HOLES_START_DISTANCE: float = 2400.0

## Distance at which aerial enemies start appearing
const AERIAL_START_DISTANCE: float = 4800.0

# ========== SPAWN MILESTONES ==========
## Organized by distance threshold for easy reading

## Objects available from the start (0m)
const MILESTONE_0: Array[String] = [
	# Trees (all)
	"tree_1", "tree_2", "tree_3", "tree_4", "tree_5", "tree_6",
	# Rocks (all)
	"rock_1", "rock_2", "rock_3", "rock_4", "rock_5", "rock_6",
	# Basic buildings
	"building_well", "building_market_stall", "building_wooden_cart",
	# Friendly animals (all)
	"npc_chicken", "npc_rabbit", "npc_sheep", "npc_cow",
]

## Objects unlocked at 960m
const MILESTONE_960: Array[String] = [
	"building_barrels",
	"building_small_hut",
	"enemy_spike",
	"npc_dark_pawn",
]

## Objects unlocked at 1800m
const MILESTONE_1800: Array[String] = [
	"building_house",
	"building_house_2",
	"npc_dark_knight",
]

## Objects unlocked at 2400m (also holes start here)
const MILESTONE_2400: Array[String] = [
	"building_excalibur",
	"building_chapel",
	"building_windmill",
	"npc_horse_knight",
]

## Objects unlocked at 3600m
const MILESTONE_3600: Array[String] = [
	"npc_catapult",
	"enemy_spike_wall",
	"building_tower",
	"building_castle",
]

## Objects unlocked at 4800m (also aerial NPCs start)
const MILESTONE_4800: Array[String] = [
	"npc_plane",
	"enemy_big_spike_wall",
	"building_wizard_tower",
]

## Objects unlocked at 6000m
const MILESTONE_6000: Array[String] = [
	"npc_wizard",
]

# ========== DISTANCE LOOKUP TABLE ==========
## Pre-computed minimum distance for each object ID
## Built from milestones for O(1) lookup

static var _min_distances: Dictionary = {}
static var _initialized: bool = false

static func _ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	_build_distance_table()

static func _build_distance_table() -> void:
	## Build lookup table from milestones
	for obj_id in MILESTONE_0:
		_min_distances[obj_id] = 0.0
	
	for obj_id in MILESTONE_960:
		_min_distances[obj_id] = 960.0
	
	for obj_id in MILESTONE_1800:
		_min_distances[obj_id] = 1800.0
	
	for obj_id in MILESTONE_2400:
		_min_distances[obj_id] = 2400.0
	
	for obj_id in MILESTONE_3600:
		_min_distances[obj_id] = 3600.0
	
	for obj_id in MILESTONE_4800:
		_min_distances[obj_id] = 4800.0
	
	for obj_id in MILESTONE_6000:
		_min_distances[obj_id] = 6000.0

# ========== PUBLIC API ==========

## Get minimum spawn distance for an object (0.0 if not found = always available)
static func get_min_distance(object_id: String) -> float:
	_ensure_initialized()
	return _min_distances.get(object_id, 0.0)

## Check if an object can spawn at the given distance
static func can_spawn_at_distance(object_id: String, current_distance: float) -> bool:
	_ensure_initialized()
	var min_dist: float = _min_distances.get(object_id, 0.0)
	return current_distance >= min_dist

## Check if terrain holes should be generated at the given distance
static func can_spawn_holes(current_distance: float) -> bool:
	return current_distance >= HOLES_START_DISTANCE

## Check if aerial NPCs can spawn at the given distance
static func can_spawn_aerial(current_distance: float) -> bool:
	return current_distance >= AERIAL_START_DISTANCE

## Get all unlocked object IDs at a given distance
static func get_unlocked_objects(current_distance: float) -> Array[String]:
	_ensure_initialized()
	var unlocked: Array[String] = []
	for obj_id in _min_distances:
		if _min_distances[obj_id] <= current_distance:
			unlocked.append(obj_id)
	return unlocked

## Get the milestone distances in order
static func get_milestones() -> Array[float]:
	return [0.0, 960.0, 1800.0, 2400.0, 3600.0, 4800.0, 6000.0]

## Debug: Print unlock summary
static func print_unlock_summary() -> void:
	_ensure_initialized()
	print("=== Distance Unlock Summary ===")
	print("Holes start at: ", HOLES_START_DISTANCE, "m")
	print("Aerial NPCs start at: ", AERIAL_START_DISTANCE, "m")
	print("")
	for milestone in get_milestones():
		print("--- ", milestone, "m ---")
		for obj_id in _min_distances:
			if _min_distances[obj_id] == milestone:
				print("  ", obj_id)

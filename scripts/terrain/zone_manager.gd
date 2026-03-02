class_name ZoneManager
extends RefCounted
## Manages terrain zones - determines what objects can spawn in each area
## Zone types: FOREST (trees), BUILDING (buildings + enemies), OPEN (rocks only)

enum ZoneType {
	FOREST,    # Trees spawn here
	BUILDING,  # Buildings and enemies (spikes) spawn here
	OPEN       # Only rocks (transition between zones)
}

# Zone configuration
var min_zone_length: float = 100.0  # Minimum zone length in Z units
var max_zone_length: float = 200.0  # Maximum zone length in Z units
var open_zone_length: float = 30.0  # Transition zone between forest/building
var chunk_size_y: float = 50.0

# Zone data: Dictionary[int chunk_index, ZoneType]
var chunk_zones: Dictionary = {}
var zone_boundaries: Array[Dictionary] = []  # [{start_z, end_z, type}]

# RNG for consistent zone generation
var zone_rng: RandomNumberGenerator

func _init(config: Dictionary = {}) -> void:
	min_zone_length = config.get("min_zone_length", 100.0)
	max_zone_length = config.get("max_zone_length", 200.0)
	open_zone_length = config.get("open_zone_length", 30.0)
	chunk_size_y = config.get("chunk_size_y", 50.0)
	
	zone_rng = RandomNumberGenerator.new()
	zone_rng.seed = config.get("seed", 42)
	
	# Pre-generate initial zones
	_generate_zones_until(10)

## Get the zone type for a specific chunk
func get_zone_for_chunk(chunk_index: int) -> ZoneType:
	# Ensure zones are generated far enough
	_ensure_zones_generated(chunk_index)
	
	if chunk_zones.has(chunk_index):
		return chunk_zones[chunk_index]
	
	# Calculate which zone this chunk falls into
	var chunk_start_z := chunk_index * chunk_size_y
	var chunk_end_z := chunk_start_z + chunk_size_y
	
	for boundary in zone_boundaries:
		if chunk_start_z >= boundary.start_z and chunk_start_z < boundary.end_z:
			chunk_zones[chunk_index] = boundary.type
			return boundary.type
	
	# Default to OPEN if not found
	return ZoneType.OPEN

## Check if a specific Z position is in a given zone type
func is_position_in_zone(world_z: float, zone_type: ZoneType) -> bool:
	for boundary in zone_boundaries:
		if world_z >= boundary.start_z and world_z < boundary.end_z:
			return boundary.type == zone_type
	return false

## Get zone type at a specific world Z position
func get_zone_at_position(world_z: float) -> ZoneType:
	for boundary in zone_boundaries:
		if world_z >= boundary.start_z and world_z < boundary.end_z:
			return boundary.type
	return ZoneType.OPEN

func _ensure_zones_generated(chunk_index: int) -> void:
	var needed_z := (chunk_index + 5) * chunk_size_y
	
	if zone_boundaries.is_empty():
		_generate_zones_until(chunk_index + 10)
		return
	
	var last_boundary: Dictionary = zone_boundaries[-1]
	while last_boundary.end_z < needed_z:
		_extend_zones()
		last_boundary = zone_boundaries[-1]

func _generate_zones_until(max_chunk: int) -> void:
	var current_z := 0.0
	var target_z := max_chunk * chunk_size_y
	
	# Start with a forest zone (safe start)
	var last_type := ZoneType.FOREST
	
	while current_z < target_z:
		var zone_length: float
		var zone_type: ZoneType
		
		if last_type == ZoneType.OPEN:
			# After open, alternate between forest and building
			zone_type = ZoneType.FOREST if zone_rng.randf() < 0.5 else ZoneType.BUILDING
			zone_length = zone_rng.randf_range(min_zone_length, max_zone_length)
		else:
			# After forest or building, add open transition
			zone_type = ZoneType.OPEN
			zone_length = open_zone_length
		
		zone_boundaries.append({
			"start_z": current_z,
			"end_z": current_z + zone_length,
			"type": zone_type
		})
		
		current_z += zone_length
		last_type = zone_type
	
	# Cache chunk zones
	_cache_chunk_zones()

func _extend_zones() -> void:
	if zone_boundaries.is_empty():
		_generate_zones_until(10)
		return
	
	var last_boundary: Dictionary = zone_boundaries[-1]
	var current_z: float = last_boundary.end_z
	var last_type: ZoneType = last_boundary.type
	
	var zone_length: float
	var zone_type: ZoneType
	
	if last_type == ZoneType.OPEN:
		zone_type = ZoneType.FOREST if zone_rng.randf() < 0.5 else ZoneType.BUILDING
		zone_length = zone_rng.randf_range(min_zone_length, max_zone_length)
	else:
		zone_type = ZoneType.OPEN
		zone_length = open_zone_length
	
	zone_boundaries.append({
		"start_z": current_z,
		"end_z": current_z + zone_length,
		"type": zone_type
	})
	
	_cache_chunk_zones()

func _cache_chunk_zones() -> void:
	for boundary in zone_boundaries:
		var start_chunk := int(boundary.start_z / chunk_size_y)
		var end_chunk := int(boundary.end_z / chunk_size_y) + 1
		
		for chunk_i in range(start_chunk, end_chunk):
			if not chunk_zones.has(chunk_i):
				chunk_zones[chunk_i] = boundary.type

## Debug: Get zone info string
func get_zone_info(chunk_index: int) -> String:
	var zone := get_zone_for_chunk(chunk_index)
	match zone:
		ZoneType.FOREST:
			return "FOREST"
		ZoneType.BUILDING:
			return "BUILDING"
		ZoneType.OPEN:
			return "OPEN"
	return "UNKNOWN"

class_name ZoneManager
extends RefCounted
## Manages terrain zones using 2D noise for organic distribution
## Creates natural-looking patches of forest and building areas

enum ZoneType {
	FOREST,    # Trees spawn here (noise < low_threshold)
	BUILDING,  # Buildings spawn here (noise > high_threshold)
	MIXED      # Transition zone - both can spawn with probability
}

# ========== NOISE CONFIGURATION ==========

## FastNoiseLite instance for zone generation
var noise: FastNoiseLite

## Noise thresholds for zone determination
## noise value range: -1.0 to 1.0
var forest_threshold: float = -0.15   # Below this = pure forest
var building_threshold: float = 0.15  # Above this = pure buildings
## Between thresholds = mixed zone with probability-based spawning

## Noise scale - larger = bigger zone patches
var noise_scale: float = 0.02  # Controls how quickly zones change

## Secondary noise for micro-variation within zones
var detail_noise: FastNoiseLite
var detail_scale: float = 0.1

# ========== CACHE ==========

## Cache for already computed positions
var _zone_cache: Dictionary = {}  # {Vector2i: {type: ZoneType, forest_weight: float}}
var _cache_resolution: float = 5.0  # Cache every 5 units

func _init(config: Dictionary = {}) -> void:
	# Main zone noise
	noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = config.get("seed", 42)
	noise.frequency = config.get("noise_scale", noise_scale)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	noise.fractal_lacunarity = 2.0
	noise.fractal_gain = 0.5
	
	# Detail noise for variation
	detail_noise = FastNoiseLite.new()
	detail_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail_noise.seed = config.get("seed", 42) + 1000
	detail_noise.frequency = config.get("detail_scale", detail_scale)
	
	# Thresholds
	forest_threshold = config.get("forest_threshold", -0.15)
	building_threshold = config.get("building_threshold", 0.15)

## Get zone type and probability weights at a world position
## Returns: {type: ZoneType, forest_weight: float, building_weight: float}
func get_zone_at_position(world_x: float, world_z: float) -> Dictionary:
	# Check cache first
	var cache_key := Vector2i(
		int(world_x / _cache_resolution),
		int(world_z / _cache_resolution)
	)
	
	if _zone_cache.has(cache_key):
		return _zone_cache[cache_key]
	
	# Sample noise at position
	var noise_value: float = noise.get_noise_2d(world_x, world_z)
	
	# Add detail variation
	var detail_value: float = detail_noise.get_noise_2d(world_x, world_z) * 0.1
	noise_value += detail_value
	
	var result: Dictionary = _calculate_zone_weights(noise_value)
	
	# Cache result
	_zone_cache[cache_key] = result
	return result

## Calculate zone type and weights from noise value
func _calculate_zone_weights(noise_value: float) -> Dictionary:
	var zone_type: ZoneType
	var forest_weight: float
	var building_weight: float
	
	if noise_value < forest_threshold:
		# Pure forest zone
		zone_type = ZoneType.FOREST
		forest_weight = 1.0
		building_weight = 0.0
	elif noise_value > building_threshold:
		# Pure building zone
		zone_type = ZoneType.BUILDING
		forest_weight = 0.0
		building_weight = 1.0
	else:
		# Mixed/transition zone - interpolate weights
		zone_type = ZoneType.MIXED
		var range_size: float = building_threshold - forest_threshold
		var normalized: float = (noise_value - forest_threshold) / range_size
		
		# Smooth interpolation using smoothstep
		normalized = _smoothstep(normalized)
		
		forest_weight = 1.0 - normalized
		building_weight = normalized
	
	return {
		"type": zone_type,
		"forest_weight": forest_weight,
		"building_weight": building_weight,
		"noise_value": noise_value
	}

## Smoothstep function for nice transitions
func _smoothstep(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

## Check if trees should spawn at this position
## Returns true if in forest zone OR wins probability roll in mixed zone
func should_spawn_tree(world_x: float, world_z: float, rng: RandomNumberGenerator) -> bool:
	var zone_data := get_zone_at_position(world_x, world_z)
	
	match zone_data.type:
		ZoneType.FOREST:
			return true
		ZoneType.BUILDING:
			return false
		ZoneType.MIXED:
			return rng.randf() < zone_data.forest_weight
	
	return false

## Check if buildings should spawn at this position
## Returns true if in building zone OR wins probability roll in mixed zone
func should_spawn_building(world_x: float, world_z: float, rng: RandomNumberGenerator) -> bool:
	var zone_data := get_zone_at_position(world_x, world_z)
	
	match zone_data.type:
		ZoneType.FOREST:
			return false
		ZoneType.BUILDING:
			return true
		ZoneType.MIXED:
			return rng.randf() < zone_data.building_weight
	
	return false

## Get the dominant zone type for a chunk (for density calculations)
## Samples multiple points and returns the most common type
func get_dominant_zone_for_chunk(chunk_x_start: float, chunk_z_start: float, 
								  chunk_width: float, chunk_depth: float) -> ZoneType:
	var sample_count := 4
	var forest_samples := 0
	var building_samples := 0
	
	for i in sample_count:
		for j in sample_count:
			var x := chunk_x_start + (i + 0.5) * chunk_width / sample_count
			var z := chunk_z_start + (j + 0.5) * chunk_depth / sample_count
			var zone_data := get_zone_at_position(x, z)
			
			if zone_data.forest_weight > zone_data.building_weight:
				forest_samples += 1
			else:
				building_samples += 1
	
	if forest_samples > building_samples:
		return ZoneType.FOREST
	elif building_samples > forest_samples:
		return ZoneType.BUILDING
	else:
		return ZoneType.MIXED

## Get zone info string for debugging
func get_zone_info(world_x: float, world_z: float) -> String:
	var zone_data := get_zone_at_position(world_x, world_z)
	var type_name: String
	
	match zone_data.type:
		ZoneType.FOREST:
			type_name = "FOREST"
		ZoneType.BUILDING:
			type_name = "BUILDING"
		ZoneType.MIXED:
			type_name = "MIXED"
	
	return "%s (F:%.0f%% B:%.0f%%)" % [
		type_name,
		zone_data.forest_weight * 100,
		zone_data.building_weight * 100
	]

## Clear cache (call when changing noise parameters)
func clear_cache() -> void:
	_zone_cache.clear()

## Clear cache entries behind player (Z > threshold)
## Call periodically to prevent memory growth during long sessions
func cleanup_old_cache(min_z: float) -> void:
	var threshold_key_z := int(min_z / _cache_resolution)
	var keys_to_remove: Array[Vector2i] = []
	
	for key in _zone_cache.keys():
		# Cache key Y corresponds to world Z
		if key.y > threshold_key_z:
			keys_to_remove.append(key)
	
	for key in keys_to_remove:
		_zone_cache.erase(key)

## Legacy compatibility: Get zone for chunk by index
## For backwards compatibility with old object_spawner
func get_zone_for_chunk(chunk_index: int, chunk_size_y: float = 50.0, 
						chunk_width: float = 100.0) -> ZoneType:
	var chunk_z := chunk_index * chunk_size_y
	var chunk_x := 0.0  # Center of terrain
	return get_dominant_zone_for_chunk(chunk_x - chunk_width/2, chunk_z, 
									   chunk_width, chunk_size_y)

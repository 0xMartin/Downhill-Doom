extends Node
## Object Pool Manager - Reuses game objects to reduce instantiation overhead
## 
## Usage:
##   ObjectPool.get_object(model_path, category) -> Node3D or null
##   ObjectPool.return_object(obj, model_path, category) -> void
##   ObjectPool.clear_pool() -> void (call on scene change)
##
## Objects are pooled by model_path + category combination.
## When retrieved from pool, objects are reset to default state.

# Pool storage: { "model_path:category" -> Array[Node3D] }
var _pools: Dictionary = {}

# Maximum objects per pool type
const MAX_POOL_SIZE := 15

# Stats for debugging
var _stats_retrieved := 0
var _stats_created := 0
var _stats_returned := 0

# Pool holder node (keeps pooled objects in scene tree but hidden)
var _pool_holder: Node3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Create holder node for pooled objects
	_pool_holder = Node3D.new()
	_pool_holder.name = "PooledObjects"
	_pool_holder.visible = false
	add_child(_pool_holder)


## Get pool key for a model+category combination
func _get_pool_key(model_path: String, category: int) -> String:
	return "%s:%d" % [model_path, category]


## Check if pool has available objects
func has_available(model_path: String, category: int) -> bool:
	var key := _get_pool_key(model_path, category)
	return _pools.has(key) and _pools[key].size() > 0


## Get an object from pool (or null if pool is empty)
## Caller is responsible for creating new object if null is returned
func get_object(model_path: String, category: int) -> Node3D:
	var key := _get_pool_key(model_path, category)
	
	if not _pools.has(key) or _pools[key].size() == 0:
		return null
	
	var obj: Node3D = _pools[key].pop_back()
	
	# Validate object is still valid
	if not is_instance_valid(obj):
		# Try to get another one
		return get_object(model_path, category)
	
	# Remove from pool holder
	if obj.get_parent() == _pool_holder:
		_pool_holder.remove_child(obj)
	
	# Reset object state
	_reset_object(obj)
	
	_stats_retrieved += 1
	return obj


## Return an object to the pool for reuse
func return_object(obj: Node3D, model_path: String, category: int) -> void:
	if not is_instance_valid(obj):
		return
	
	var key := _get_pool_key(model_path, category)
	
	# Initialize pool array if needed
	if not _pools.has(key):
		_pools[key] = []
	
	# Check pool size limit
	if _pools[key].size() >= MAX_POOL_SIZE:
		# Pool full, destroy object
		obj.queue_free()
		return
	
	# Remove from current parent
	var current_parent := obj.get_parent()
	if current_parent:
		current_parent.remove_child(obj)
	
	# Prepare object for pooling
	_prepare_for_pool(obj)
	
	# Add to pool holder (keeps in tree but hidden)
	_pool_holder.add_child(obj)
	_pools[key].append(obj)
	
	_stats_returned += 1


## Reset object to default state when retrieved from pool
func _reset_object(obj: Node3D) -> void:
	obj.visible = true
	obj.position = Vector3.ZERO
	obj.rotation = Vector3.ZERO
	obj.scale = Vector3.ONE
	
	# Re-enable processing
	obj.set_process(true)
	obj.set_physics_process(true)
	
	# Re-enable collision shapes
	for child in obj.get_children():
		if child is CollisionShape3D:
			child.disabled = false
		elif child is Area3D:
			child.monitoring = true
			child.monitorable = true
	
	# Reset RigidBody state if applicable
	if obj is RigidBody3D:
		var rb := obj as RigidBody3D
		rb.freeze = true
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	
	# Call _pool_reset on object if it has the method (for custom reset logic)
	if obj.has_method("_pool_reset"):
		obj.call("_pool_reset")


## Prepare object for storage in pool
func _prepare_for_pool(obj: Node3D) -> void:
	obj.visible = false
	
	# Disable processing
	obj.set_process(false)
	obj.set_physics_process(false)
	
	# Disable collision shapes to prevent phantom collisions
	for child in obj.get_children():
		if child is CollisionShape3D:
			child.disabled = true
		elif child is Area3D:
			child.monitoring = false
			child.monitorable = false
	
	# Freeze RigidBody if applicable
	if obj is RigidBody3D:
		var rb := obj as RigidBody3D
		rb.freeze = true
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	
	# Call _pool_prepare on object if it has the method (for custom cleanup)
	if obj.has_method("_pool_prepare"):
		obj.call("_pool_prepare")


## Clear all pools (call on scene change or game restart)
func clear_pool() -> void:
	for key in _pools.keys():
		var pool_array: Array = _pools[key]
		for obj in pool_array:
			if is_instance_valid(obj):
				obj.queue_free()
		pool_array.clear()
	_pools.clear()
	
	# Reset stats
	_stats_retrieved = 0
	_stats_created = 0
	_stats_returned = 0


## Clear specific pool category
func clear_category_pool(category: int) -> void:
	var keys_to_clear: Array[String] = []
	for key in _pools.keys():
		if key.ends_with(":%d" % category):
			keys_to_clear.append(key)
	
	for key in keys_to_clear:
		var pool_array: Array = _pools[key]
		for obj in pool_array:
			if is_instance_valid(obj):
				obj.queue_free()
		pool_array.clear()
		_pools.erase(key)


## Get pool statistics (for debugging)
func get_stats() -> Dictionary:
	var total_pooled := 0
	for key in _pools.keys():
		total_pooled += _pools[key].size()
	
	return {
		"total_pooled": total_pooled,
		"retrieved": _stats_retrieved,
		"created": _stats_created,
		"returned": _stats_returned,
		"hit_rate": _stats_retrieved / float(max(_stats_retrieved + _stats_created, 1))
	}


## Print pool stats to console (debug)
func print_stats() -> void:
	var stats := get_stats()
	print("ObjectPool Stats: pooled=%d, retrieved=%d, created=%d, hit_rate=%.1f%%" % [
		stats.total_pooled, stats.retrieved, stats.created, stats.hit_rate * 100
	])

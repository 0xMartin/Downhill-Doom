extends Node
## QuestManager - Handles daily quest generation, tracking, and rewards
## Autoload singleton that persists quest state via SecureStorage

signal quest_progress_updated(quest_id: String, current: int, target: int)
signal quest_completed(quest_id: String)
signal quests_refreshed
signal active_quest_changed(quest: RefCounted)  # QuestConfig.QuestData or null

# Current daily quests
var _daily_quests: Array = []  # Array of QuestConfig.QuestData
var _active_quest_id: String = ""
var _quest_progress: Dictionary = {}  # {quest_id: current_value}
var _completed_today: Array = []  # Quest IDs completed today
var _last_reset_date: String = ""

# Run tracking
var _run_progress: Dictionary = {}  # Progress accumulated in current run
var _is_in_run: bool = false

# References
var _storage: Node = null
var _game_manager: Node = null


func _ready() -> void:
	# Get references when available
	call_deferred("_setup_references")


func _setup_references() -> void:
	_storage = get_node_or_null("/root/SecureStorage")
	_game_manager = get_node_or_null("/root/GameManager")
	
	if _storage:
		# Wait for storage to be ready
		if _storage.is_storage_ready():
			_load_quest_data()
		else:
			_storage.storage_ready.connect(_on_storage_ready, CONNECT_ONE_SHOT)
	
	if _game_manager:
		_connect_game_signals()


func _on_storage_ready() -> void:
	_load_quest_data()


func _connect_game_signals() -> void:
	if not _game_manager:
		return
	
	# Connect to game events for tracking
	if not _game_manager.coins_changed.is_connected(_on_coins_changed):
		_game_manager.coins_changed.connect(_on_coins_changed)
	
	if not _game_manager.distance_changed.is_connected(_on_distance_changed):
		_game_manager.distance_changed.connect(_on_distance_changed)
	
	if not _game_manager.object_destroyed.is_connected(_on_object_destroyed):
		_game_manager.object_destroyed.connect(_on_object_destroyed)
	
	if not _game_manager.time_changed.is_connected(_on_time_changed):
		_game_manager.time_changed.connect(_on_time_changed)
	
	if not _game_manager.supercharge_activated.is_connected(_on_supercharge_activated):
		_game_manager.supercharge_activated.connect(_on_supercharge_activated)
	
	if not _game_manager.game_started.is_connected(_on_game_started):
		_game_manager.game_started.connect(_on_game_started)
	
	if not _game_manager.player_died.is_connected(_on_game_ended):
		_game_manager.player_died.connect(_on_game_ended)


# ========== PUBLIC API ==========

## Get all daily quests
func get_daily_quests() -> Array:
	_check_daily_reset()
	# Ensure quests always exist - generate if empty
	if _daily_quests.is_empty():
		_generate_new_quests()
	return _daily_quests


## Get active quest or null
func get_active_quest() -> RefCounted:
	if _active_quest_id.is_empty():
		return null
	
	for quest in _daily_quests:
		if quest.id == _active_quest_id:
			return quest
	return null


## Activate a quest
func activate_quest(quest_id: String) -> bool:
	# Can't activate already completed quest
	if quest_id in _completed_today:
		return false
	
	# Find quest
	var found := false
	for quest in _daily_quests:
		if quest.id == quest_id:
			found = true
			break
	
	if not found:
		return false
	
	_active_quest_id = quest_id
	_save_quest_data()
	
	var quest := get_active_quest()
	active_quest_changed.emit(quest)
	
	return true


## Deactivate current quest
func deactivate_quest() -> void:
	_active_quest_id = ""
	_save_quest_data()
	active_quest_changed.emit(null)


## Get progress for a quest
func get_quest_progress(quest_id: String) -> int:
	return _quest_progress.get(quest_id, 0)


## Get progress during current run (for single-run quests)
func get_run_progress(quest_id: String) -> int:
	return _run_progress.get(quest_id, 0)


## Check if quest is completed
func is_quest_completed(quest_id: String) -> bool:
	return quest_id in _completed_today


## Check if quest is active
func is_quest_active(quest_id: String) -> bool:
	return _active_quest_id == quest_id


## Get display progress (considers quest mode)
func get_display_progress(quest: RefCounted) -> int:
	if quest.mode == QuestConfig.QuestMode.SINGLE_RUN:
		return get_run_progress(quest.id)
	else:
		return get_quest_progress(quest.id)


## Claim reward for completed quest
func claim_reward(quest_id: String) -> bool:
	if not is_quest_completed(quest_id):
		return false
	
	var quest: RefCounted = null
	for q in _daily_quests:
		if q.id == quest_id:
			quest = q
			break
	
	if not quest:
		return false
	
	# Award reward
	match quest.reward_type:
		QuestConfig.RewardType.COINS:
			if _storage:
				_storage.add_coins(quest.reward_value)
		QuestConfig.RewardType.BOOST:
			if _storage:
				_storage.add_boost(quest.reward_value)
		QuestConfig.RewardType.CRATE:
			if _storage:
				_storage.add_crate(quest.reward_value)
	
	return true


## Get seconds until daily reset
func get_seconds_until_reset() -> int:
	return QuestConfig.get_seconds_until_reset()


## Force refresh quests (for testing)
func force_refresh() -> void:
	_generate_new_quests()


# ========== GAME EVENT HANDLERS ==========

func _on_game_started() -> void:
	_is_in_run = true
	_run_progress.clear()


func _on_game_ended() -> void:
	_is_in_run = false
	
	# For multi-run quests, add run progress to total
	var active := get_active_quest()
	if active and active.mode == QuestConfig.QuestMode.MULTI_RUN:
		var run_value: int = int(_run_progress.get(active.id, 0))
		if run_value > 0:
			_quest_progress[active.id] = _quest_progress.get(active.id, 0) + run_value
			_run_progress[active.id] = 0  # Clear run progress after transferring to avoid double-counting in _check_quest_completion
			_check_quest_completion(active)
			_save_quest_data()
			quest_progress_updated.emit(active.id, _quest_progress[active.id], active.target_value)


func _on_coins_changed(total: int) -> void:
	if not _is_in_run:
		return
	
	var active := get_active_quest()
	if not active or active.type != QuestConfig.QuestType.COLLECT_COINS:
		return
	
	# Track run coins (total from GameManager)
	var gm := _game_manager
	if gm:
		_update_progress(active, gm.coins)


func _on_distance_changed(distance: float) -> void:
	if not _is_in_run:
		return
	
	var active := get_active_quest()
	if not active or active.type != QuestConfig.QuestType.TRAVEL_DISTANCE:
		return
	
	_update_progress(active, int(distance))


func _on_object_destroyed(object_id: String, _object_name: String, _coins: int) -> void:
	if not _is_in_run:
		return
	
	var active := get_active_quest()
	if not active:
		return
	
	match active.type:
		QuestConfig.QuestType.KILL_ANY:
			_increment_progress(active, 1)
		QuestConfig.QuestType.KILL_SPECIFIC:
			if object_id == active.target_object_id:
				_increment_progress(active, 1)


func _on_time_changed(time: float) -> void:
	if not _is_in_run:
		return
	
	var active := get_active_quest()
	if not active or active.type != QuestConfig.QuestType.SURVIVE_TIME:
		return
	
	_update_progress(active, int(time))


func _on_supercharge_activated() -> void:
	if not _is_in_run:
		return
	
	var active := get_active_quest()
	if not active or active.type != QuestConfig.QuestType.ACTIVATE_SUPERCHARGE:
		return
	
	_increment_progress(active, 1)


# ========== PROGRESS TRACKING ==========

func _update_progress(quest: RefCounted, value: int) -> void:
	if quest.mode == QuestConfig.QuestMode.SINGLE_RUN:
		_run_progress[quest.id] = value
		_check_quest_completion(quest)
		quest_progress_updated.emit(quest.id, value, quest.target_value)
	else:
		# For multi-run, track in run_progress, will be added at end
		_run_progress[quest.id] = value
		var total: int = int(_quest_progress.get(quest.id, 0)) + value
		quest_progress_updated.emit(quest.id, total, quest.target_value)


func _increment_progress(quest: RefCounted, amount: int) -> void:
	if quest.mode == QuestConfig.QuestMode.SINGLE_RUN:
		_run_progress[quest.id] = _run_progress.get(quest.id, 0) + amount
		_check_quest_completion(quest)
		quest_progress_updated.emit(quest.id, _run_progress[quest.id], quest.target_value)
	else:
		# For multi-run, track in run_progress, will be added at end
		_run_progress[quest.id] = _run_progress.get(quest.id, 0) + amount
		var total: int = int(_quest_progress.get(quest.id, 0)) + int(_run_progress[quest.id])
		quest_progress_updated.emit(quest.id, total, quest.target_value)


func _check_quest_completion(quest: RefCounted) -> void:
	if quest.id in _completed_today:
		return
	
	var progress: int
	if quest.mode == QuestConfig.QuestMode.SINGLE_RUN:
		progress = _run_progress.get(quest.id, 0)
	else:
		progress = _quest_progress.get(quest.id, 0) + _run_progress.get(quest.id, 0)
	
	if progress >= quest.target_value:
		_completed_today.append(quest.id)
		_save_quest_data()
		quest_completed.emit(quest.id)
		
		# Auto-claim reward
		claim_reward(quest.id)


# ========== PERSISTENCE ==========

func _load_quest_data() -> void:
	if not _storage:
		return
	
	var quest_data: Dictionary = _storage.get_quest_data()
	
	_last_reset_date = quest_data.get("last_reset_date", "")
	_active_quest_id = quest_data.get("active_quest_id", "")
	_quest_progress = quest_data.get("quest_progress", {})
	_completed_today = quest_data.get("completed_today", [])
	
	# Reconstruct quest objects
	_daily_quests.clear()
	var quests_data: Array = quest_data.get("daily_quests", [])
	for qd in quests_data:
		_daily_quests.append(QuestConfig.QuestData.from_dict(qd))
	
	# Check if we need a daily reset
	_check_daily_reset()
	
	# Emit initial state
	var active := get_active_quest()
	active_quest_changed.emit(active)


func _save_quest_data() -> void:
	if not _storage:
		return
	
	var quests_data := []
	for quest in _daily_quests:
		quests_data.append(quest.to_dict())
	
	var data := {
		"last_reset_date": _last_reset_date,
		"daily_quests": quests_data,
		"active_quest_id": _active_quest_id,
		"quest_progress": _quest_progress,
		"completed_today": _completed_today,
	}
	
	_storage.set_quest_data(data)


func _check_daily_reset() -> void:
	var current_date := QuestConfig.get_current_utc_date_string()
	
	if _last_reset_date != current_date:
		_generate_new_quests()


func _generate_new_quests() -> void:
	_last_reset_date = QuestConfig.get_current_utc_date_string()
	_active_quest_id = ""
	_quest_progress.clear()
	_completed_today.clear()
	_run_progress.clear()
	
	# Generate new quests based on date seed
	var date_seed := QuestConfig.get_date_seed()
	_daily_quests = QuestConfig.generate_daily_quests(date_seed)
	
	_save_quest_data()
	quests_refreshed.emit()
	active_quest_changed.emit(null)

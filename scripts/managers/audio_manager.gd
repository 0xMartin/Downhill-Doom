extends Node
## AudioManager - Handles all game audio with proper transitions
## Settings are handled by SettingsManager - this only plays audio

# Sound paths
const BUTTON_CLICK := "res://assets/sounds/ui/button_click.mp3"
const MENU_MUSIC := "res://assets/sounds/ui/music.mp3"
const BOULDER_ROLL := "res://assets/sounds/player/boulder_roll.mp3"
const HURT_SOUND := "res://assets/sounds/player/hurt.mp3"
const DEATH_SOUND := "res://assets/sounds/player/death.mp3"
const SHOCK_WAVE_SOUND := "res://assets/sounds/sfx/shock_wave.mp3"
const SUPERCHARGE_SOUND := "res://assets/sounds/player/supercharge.mp3"
const SPELL_CAST_SOUND := "res://assets/sounds/sfx/spell_cast.mp3"

var game_music_tracks: Array[String] = [
	"res://assets/sounds/music/music_1.mp3",
	"res://assets/sounds/music/music_2.mp3",
	"res://assets/sounds/music/music_3.mp3",
]

var tree_hit_sounds: Array[String] = [
	"res://assets/sounds/hit/tree/tree_1.mp3",
	"res://assets/sounds/hit/tree/tree_2.mp3",
]

var building_hit_sounds: Array[String] = [
	"res://assets/sounds/hit/building/building_1.mp3",
]

var npc_death_sounds: Dictionary = {
	"chicken": "res://assets/sounds/hit/npc/chicken.mp3",
	"rabbit": "res://assets/sounds/hit/npc/rabbit.mp3",
	"cow": "res://assets/sounds/hit/npc/cow.mp3",
	"sheep": "res://assets/sounds/hit/npc/sheep.mp3",
	"dog": "res://assets/sounds/hit/npc/dog.mp3",
	"cat": "res://assets/sounds/hit/npc/cat.mp3",
	"enemy": "res://assets/sounds/hit/npc/enemy_npc.mp3",
	"catapult": "res://assets/sounds/hit/npc/catapult.mp3",
	"plane": "res://assets/sounds/hit/npc/plane.mp3",
}

# Audio players
var menu_music_player: AudioStreamPlayer
var game_music_player: AudioStreamPlayer
var roll_sound_player: AudioStreamPlayer
var sfx_player: AudioStreamPlayer  # One-shot SFX

var current_game_track_index: int = -1
var is_in_game: bool = false
var roll_sound_playing: bool = false
var roll_target_volume: float = -80.0  # Target volume for fade
var roll_ground_contact: bool = false  # Is player on ground?
var roll_ground_timer: float = 0.0  # Debounce timer
const ROLL_FADE_TIME: float = 0.15  # Fade duration (half)
const ROLL_DEBOUNCE_TIME: float = 0.1  # Debounce for ground contact changes
const ROLL_SILENT_DB: float = -80.0  # Volume at which sound is considered silent

# Supercharge pitch shift
var is_supercharged: bool = false
const SUPERCHARGE_PITCH_BOOST: float = 1.2  # 20% higher pitch during supercharge

# Reference to SettingsManager
var settings: Node

func _ready() -> void:
	# Get SettingsManager reference
	settings = get_node("/root/SettingsManager")
	
	# Connect to GameManager for supercharge state
	var gm := get_node_or_null("/root/GameManager")
	if gm:
		if gm.has_signal("supercharge_activated"):
			gm.supercharge_activated.connect(_on_supercharge_activated)
		if gm.has_signal("supercharge_ended"):
			gm.supercharge_ended.connect(_on_supercharge_ended)
	
	# Create audio players
	menu_music_player = AudioStreamPlayer.new()
	menu_music_player.name = "MenuMusicPlayer"
	menu_music_player.volume_db = -5.0
	menu_music_player.process_mode = Node.PROCESS_MODE_ALWAYS  # Keep playing when paused
	add_child(menu_music_player)
	
	game_music_player = AudioStreamPlayer.new()
	game_music_player.name = "GameMusicPlayer"
	game_music_player.volume_db = -8.0
	game_music_player.process_mode = Node.PROCESS_MODE_ALWAYS  # Keep playing when paused
	game_music_player.finished.connect(_on_game_music_finished)
	add_child(game_music_player)
	
	roll_sound_player = AudioStreamPlayer.new()
	roll_sound_player.name = "RollSoundPlayer"
	roll_sound_player.volume_db = -12.0
	roll_sound_player.finished.connect(_on_roll_sound_finished)
	add_child(roll_sound_player)
	
	sfx_player = AudioStreamPlayer.new()
	sfx_player.name = "SFXPlayer"
	sfx_player.volume_db = 0.0
	add_child(sfx_player)
	
	# Load rolling sound as looping
	var roll_stream := load(BOULDER_ROLL) as AudioStream
	if roll_stream:
		roll_sound_player.stream = roll_stream
	
	# Load menu music as looping
	var menu_stream := load(MENU_MUSIC) as AudioStreamMP3
	if menu_stream:
		menu_stream.loop = true
		menu_music_player.stream = menu_stream
	
	# Disable processing by default - enabled when roll sound starts
	set_process(false)

func _process(delta: float) -> void:
	# Handle roll sound fade based on ground contact with debounce
	# Only process when roll sound is active (optimization)
	if not roll_sound_playing:
		set_process(false)
		return
	
	# Smooth volume transition
	var current_vol := roll_sound_player.volume_db
	if abs(current_vol - roll_target_volume) > 0.5:
		var fade_speed := 80.0 / ROLL_FADE_TIME  # dB per second (faster for larger range)
		if current_vol < roll_target_volume:
			roll_sound_player.volume_db = min(current_vol + fade_speed * delta, roll_target_volume)
		else:
			roll_sound_player.volume_db = max(current_vol - fade_speed * delta, roll_target_volume)
	
	# Pause playback when fully silent to save resources
	if roll_sound_player.volume_db <= ROLL_SILENT_DB + 1.0 and not roll_ground_contact:
		roll_sound_player.stream_paused = true
	elif roll_ground_contact and roll_sound_player.stream_paused:
		roll_sound_player.stream_paused = false

# ========== UI Sounds ==========

func play_button_click() -> void:
	var stream := load(BUTTON_CLICK) as AudioStream
	if stream:
		sfx_player.stream = stream
		sfx_player.volume_db = _get_sfx_db(-5.0)
		sfx_player.play()

# ========== Menu Music ==========

func play_menu_music() -> void:
	is_in_game = false
	_crossfade_to_menu()

func stop_menu_music() -> void:
	var tween := create_tween()
	tween.tween_property(menu_music_player, "volume_db", -40.0, 0.5)
	tween.tween_callback(menu_music_player.stop)

func _crossfade_to_menu() -> void:
	# Fade out game music
	if game_music_player.playing:
		var tween := create_tween()
		tween.tween_property(game_music_player, "volume_db", -40.0, 1.0)
		tween.tween_callback(game_music_player.stop)
	
	# Fade in menu music
	menu_music_player.volume_db = -40.0
	menu_music_player.play()
	var tween2 := create_tween()
	tween2.tween_property(menu_music_player, "volume_db", _get_music_db(-5.0), 1.0)

# ========== Game Music ==========

func start_game_music() -> void:
	is_in_game = true
	_crossfade_to_game()

func stop_game_music() -> void:
	var tween := create_tween()
	tween.tween_property(game_music_player, "volume_db", -40.0, 0.5)
	tween.tween_callback(game_music_player.stop)

func _crossfade_to_game() -> void:
	# Fade out menu music
	if menu_music_player.playing:
		var tween := create_tween()
		tween.tween_property(menu_music_player, "volume_db", -40.0, 1.0)
		tween.tween_callback(menu_music_player.stop)
	
	# Play random game track
	_play_random_game_track()

func _play_random_game_track() -> void:
	if game_music_tracks.is_empty():
		return
	
	# Pick a different track than the current one
	var new_index := randi() % game_music_tracks.size()
	if game_music_tracks.size() > 1:
		while new_index == current_game_track_index:
			new_index = randi() % game_music_tracks.size()
	
	current_game_track_index = new_index
	var stream := load(game_music_tracks[new_index]) as AudioStream
	if stream:
		game_music_player.stream = stream
		game_music_player.volume_db = -40.0
		game_music_player.play()
		var tween := create_tween()
		tween.tween_property(game_music_player, "volume_db", _get_music_db(-8.0), 1.0)

func _on_game_music_finished() -> void:
	if is_in_game:
		_play_random_game_track()

# ========== Rolling Sound ==========

func start_roll_sound() -> void:
	if not roll_sound_playing and roll_sound_player.stream:
		roll_sound_player.volume_db = ROLL_SILENT_DB  # Start silent
		roll_target_volume = ROLL_SILENT_DB
		roll_sound_player.stream_paused = true  # Start paused
		roll_sound_player.play()
		roll_sound_playing = true
		set_process(true)  # Re-enable processing for volume fading

func stop_roll_sound() -> void:
	roll_sound_player.stop()
	roll_sound_playing = false
	roll_ground_contact = false
	roll_ground_timer = 0.0

func _on_roll_sound_finished() -> void:
	# Restart rolling sound if still playing (loop behavior)
	if roll_sound_playing:
		roll_sound_player.play()

func set_roll_ground_contact(on_ground: bool) -> void:
	# Direct update - debouncing handled by the gradual fade
	roll_ground_contact = on_ground

func update_roll_pitch(speed_ratio: float) -> void:
	# Pitch ranges from 0.5 (slow) to 1.5 (fast)
	# speed_ratio is current_speed / max_speed (0.0 to 1.0+)
	var pitch := lerpf(0.6, 1.2, clampf(speed_ratio, 0.0, 1.0))
	roll_sound_player.pitch_scale = pitch
	
	# Set target volume based on speed and ground contact
	var base_vol := lerpf(-20.0, -8.0, clampf(speed_ratio, 0.0, 1.0))
	if roll_ground_contact:
		roll_target_volume = _get_sfx_db(base_vol)
	else:
		roll_target_volume = ROLL_SILENT_DB  # Fade out when in air

# ========== Player Sounds ==========

func play_hurt_sound() -> void:
	var stream := load(HURT_SOUND) as AudioStream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = _get_sfx_db(-3.0)
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

func play_death_sound() -> void:
	var stream := load(DEATH_SOUND) as AudioStream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = _get_sfx_db(0.0)  # Full volume for death
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

func play_shock_wave_sound() -> void:
	var stream := load(SHOCK_WAVE_SOUND) as AudioStream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = _get_sfx_db(-2.0)  # Slightly loud impact sound
		player.pitch_scale = _get_sfx_pitch(randf_range(0.95, 1.05))
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

func play_supercharge_sound() -> void:
	var stream := load(SUPERCHARGE_SOUND) as AudioStream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = _get_sfx_db(0.0)  # Full volume for epic effect
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)
	else:
		push_warning("Supercharge sound not found: " + SUPERCHARGE_SOUND)

func play_spell_cast_sound() -> void:
	var stream := load(SPELL_CAST_SOUND) as AudioStream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = _get_sfx_db(-3.0)
		player.pitch_scale = _get_sfx_pitch(randf_range(0.95, 1.05))
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

# ========== Hit Sounds ==========

func play_tree_hit_sound() -> void:
	if tree_hit_sounds.is_empty():
		return
	
	var random_index := randi() % tree_hit_sounds.size()
	var stream := load(tree_hit_sounds[random_index]) as AudioStream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = _get_sfx_db(-5.0)
		player.pitch_scale = _get_sfx_pitch(randf_range(0.9, 1.1))
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

func play_building_hit_sound() -> void:
	if building_hit_sounds.is_empty():
		return
	
	var random_index := randi() % building_hit_sounds.size()
	var stream := load(building_hit_sounds[random_index]) as AudioStream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = _get_sfx_db(-3.0)
		player.pitch_scale = _get_sfx_pitch(randf_range(0.9, 1.1))
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

func play_npc_death_sound(npc_type: String) -> void:
	if not npc_death_sounds.has(npc_type):
		return
	
	var sound_path: String = npc_death_sounds[npc_type]
	var stream := load(sound_path) as AudioStream
	if stream:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = _get_sfx_db(-2.0)
		player.pitch_scale = _get_sfx_pitch(randf_range(0.95, 1.05))
		add_child(player)
		player.play()
		player.finished.connect(player.queue_free)

func play_jump_sound() -> void:
	# Simple procedural jump sound - short "whoosh"
	var sample_rate := 22050
	var duration := 0.15
	var sample_count := int(sample_rate * duration)
	
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_8_BITS
	audio.mix_rate = sample_rate
	audio.stereo = false
	
	var data := PackedByteArray()
	data.resize(sample_count)
	
	for i in range(sample_count):
		var t := float(i) / sample_rate
		var progress := float(i) / sample_count
		# Rising pitch "whoosh" effect
		var freq := 200.0 + progress * 400.0
		var envelope := (1.0 - progress) * (1.0 - progress)  # Fade out
		var sample := sin(t * freq * TAU) * envelope
		# Add some noise for "air" effect
		sample += (randf() - 0.5) * 0.3 * envelope
		data[i] = int((sample * 0.5 + 0.5) * 255)
	
	audio.data = data
	
	var player := AudioStreamPlayer.new()
	player.stream = audio
	player.volume_db = _get_sfx_db(-8.0)
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

# ========== Volume Control (delegates to SettingsManager) ==========
# These methods are kept for backward compatibility with existing code

func set_music_volume(value: float) -> void:
	settings.set_music_volume(value)
	_apply_music_volume()

func set_sfx_volume(value: float) -> void:
	settings.set_sfx_volume(value)

func get_music_volume() -> float:
	return settings.get_music_volume()

func get_sfx_volume() -> float:
	return settings.get_sfx_volume()

func set_show_pickup_popup(value: bool) -> void:
	settings.set_show_pickup_popup(value)

func get_show_pickup_popup() -> bool:
	return settings.get_show_pickup_popup()

func set_show_damage_popup(value: bool) -> void:
	settings.set_show_damage_popup(value)

func get_show_damage_popup() -> bool:
	return settings.get_show_damage_popup()

func set_haptic_enabled(value: bool) -> void:
	settings.set_haptic_enabled(value)

func get_haptic_enabled() -> bool:
	return settings.get_haptic_enabled()

## Control mode: 0 = gyro, 1 = touch
func set_control_mode(value: int) -> void:
	settings.set_control_mode(value)

func get_control_mode() -> int:
	return settings.get_control_mode()

func is_touch_mode() -> bool:
	return settings.is_touch_mode()

## Vibrate if haptic is enabled
func vibrate(duration_ms: int = 100) -> void:
	settings.vibrate(duration_ms)

func _get_music_db(base_db: float = 0.0) -> float:
	return settings.get_music_db(base_db)

func _get_sfx_db(base_db: float = 0.0) -> float:
	return settings.get_sfx_db(base_db)


## Get pitch with supercharge boost applied
func _get_sfx_pitch(base_pitch: float = 1.0) -> float:
	if is_supercharged:
		return base_pitch * SUPERCHARGE_PITCH_BOOST
	return base_pitch


func _on_supercharge_activated() -> void:
	is_supercharged = true


func _on_supercharge_ended() -> void:
	is_supercharged = false


func _apply_music_volume() -> void:
	var target_db := _get_music_db(-5.0)
	if menu_music_player.playing:
		menu_music_player.volume_db = target_db
	if game_music_player.playing:
		game_music_player.volume_db = _get_music_db(-8.0)

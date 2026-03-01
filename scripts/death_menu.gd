extends CanvasLayer
## Death Menu - Shows when player dies with stats and options

@onready var distance_label: Label = $Panel/VBoxContainer/StatsContainer/DistanceValue
@onready var coins_label: Label = $Panel/VBoxContainer/StatsContainer/CoinsValue
@onready var best_distance_label: Label = $Panel/VBoxContainer/StatsContainer/BestDistanceValue
@onready var panel: Control = $Panel
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var gm: Node  # GameManager reference
var audio: Node  # AudioManager reference

func _ready() -> void:
	gm = get_node("/root/GameManager")
	audio = get_node("/root/AudioManager")
	visible = false
	gm.player_died.connect(_on_player_died)

func _on_player_died() -> void:
	# Update stats
	distance_label.text = gm.get_formatted_distance()
	coins_label.text = str(gm.coins)
	best_distance_label.text = "%.0f m" % gm.best_distance
	
	# Show with animation
	visible = true
	animation_player.play("show")

func _on_restart_pressed() -> void:
	if audio:
		audio.play_button_click()
	animation_player.play("hide")
	await animation_player.animation_finished
	gm.restart_game()

func _on_menu_pressed() -> void:
	if audio:
		audio.play_button_click()
	animation_player.play("hide")
	await animation_player.animation_finished
	gm.go_to_menu()

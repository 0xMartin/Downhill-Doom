extends CanvasLayer
## Scene transition with smooth fade animation

@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var color_rect: ColorRect = $ColorRect

var _target_scene: String = ""

func _ready() -> void:
	color_rect.visible = false
	color_rect.color = Color.BLACK

func change_scene(target: String) -> void:
	_target_scene = target
	color_rect.visible = true
	animation_player.play("fade_out")
	await animation_player.animation_finished
	get_tree().change_scene_to_file(_target_scene)
	animation_player.play("fade_in")
	await animation_player.animation_finished
	color_rect.visible = false

func fade_in() -> void:
	color_rect.visible = true
	color_rect.color.a = 1.0
	animation_player.play("fade_in")
	await animation_player.animation_finished
	color_rect.visible = false

func fade_out() -> void:
	color_rect.visible = true
	animation_player.play("fade_out")
	await animation_player.animation_finished

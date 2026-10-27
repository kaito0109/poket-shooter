extends Node2D
## Pocket Shooter - main scene: spawning, score, lives, HUD, game over.

const PlayerScript := preload("res://player.gd")
const EnemyScript := preload("res://enemy.gd")
const ExplosionScript := preload("res://explosion.gd")
const StarfieldScript := preload("res://starfield.gd")

var screen_size := Vector2(720, 960)
var score: int = 0
var lives: int = 3
var is_game_over: bool = false
var elapsed: float = 0.0

var player: Area2D
var spawn_timer: Timer
var score_label: Label
var lives_label: Label
var center_label: Label
var restart_button: Button

func _ready() -> void:
	screen_size = Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 720),
		ProjectSettings.get_setting("display/window/size/viewport_height", 960)
	)
	add_to_group("main")

	var starfield := StarfieldScript.new()
	starfield.z_index = -100
	add_child(starfield)

	player = PlayerScript.new()
	player.position = Vector2(screen_size.x * 0.5, screen_size.y - 130.0)
	add_child(player)

	_build_hud()

	spawn_timer = Timer.new()
	spawn_timer.wait_time = 0.9
	spawn_timer.timeout.connect(_on_spawn_timer_timeout)
	add_child(spawn_timer)
	spawn_timer.start()

	_spawn_enemy()

func _process(delta: float) -> void:
	if is_game_over:
		return
	elapsed += delta
	# Gentle difficulty ramp: spawn a bit faster over time.
	spawn_timer.wait_time = maxf(0.35, 0.9 - elapsed * 0.006)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	score_label = Label.new()
	score_label.position = Vector2(16, 10)
	score_label.add_theme_font_size_override("font_size", 30)
	score_label.text = "SCORE 0"
	layer.add_child(score_label)

	lives_label = Label.new()
	lives_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lives_label.position = Vector2(-170, 10)
	lives_label.add_theme_font_size_override("font_size", 30)
	lives_label.text = "LIFE x 3"
	layer.add_child(lives_label)

	var help_label := Label.new()
	help_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	help_label.position = Vector2(0, -44)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.add_theme_font_size_override("font_size", 20)
	help_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	help_label.text = "WASD / 矢印キー / ドラッグで移動（ショットは自動）"
	layer.add_child(help_label)

	center_label = Label.new()
	center_label.set_anchors_preset(Control.PRESET_CENTER)
	center_label.position = Vector2(-260, -90)
	center_label.size = Vector2(520, 80)
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_label.add_theme_font_size_override("font_size", 52)
	center_label.visible = false
	layer.add_child(center_label)

	restart_button = Button.new()
	restart_button.set_anchors_preset(Control.PRESET_CENTER)
	restart_button.position = Vector2(-130, 10)
	restart_button.size = Vector2(260, 64)
	restart_button.add_theme_font_size_override("font_size", 28)
	restart_button.text = "もう一度プレイ"
	restart_button.visible = false
	restart_button.pressed.connect(_on_restart_pressed)
	layer.add_child(restart_button)

func _on_spawn_timer_timeout() -> void:
	if not is_game_over:
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy := EnemyScript.new()
	var x := randf_range(48.0, screen_size.x - 48.0)
	enemy.position = Vector2(x, -36.0)
	enemy.set("fall_speed", randf_range(130.0, 195.0) + minf(elapsed * 1.2, 90.0))
	add_child(enemy)

func add_score(value: int) -> void:
	score += value
	score_label.text = "SCORE %d" % score

func spawn_explosion(at_position: Vector2) -> void:
	var explosion := ExplosionScript.new()
	explosion.position = at_position
	add_child(explosion)

func lose_life() -> void:
	if is_game_over:
		return
	lives -= 1
	lives_label.text = "LIFE x %d" % maxi(lives, 0)
	if lives <= 0:
		_game_over()

func _game_over() -> void:
	is_game_over = true
	spawn_timer.stop()
	if is_instance_valid(player):
		player.queue_free()
	center_label.text = "GAME OVER\nSCORE %d" % score
	center_label.visible = true
	restart_button.visible = true

func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()

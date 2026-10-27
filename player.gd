extends Area2D
## Player ship: keyboard / touch-drag movement, automatic shooting.

const BulletScript := preload("res://bullet.gd")

var speed: float = 430.0
var margin: float = 26.0
var pointer_active: bool = false
var pointer_target := Vector2.ZERO
var invincible: bool = false

func _ready() -> void:
	add_to_group("player")
	z_index = 10
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(38, 38)
	shape_node.shape = shape
	add_child(shape_node)
	area_entered.connect(_on_area_entered)

	var fire_timer := Timer.new()
	fire_timer.wait_time = 0.22
	fire_timer.autostart = true
	fire_timer.timeout.connect(_on_fire_timer_timeout)
	add_child(fire_timer)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		pointer_active = event.pressed
		pointer_target = event.position
	elif event is InputEventScreenDrag:
		pointer_active = true
		pointer_target = event.position
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			pointer_active = event.pressed
			pointer_target = event.position
	elif event is InputEventMouseMotion:
		if pointer_active:
			pointer_target = event.position

func _physics_process(delta: float) -> void:
	var velocity := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		velocity.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		velocity.x += 1.0
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		velocity.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		velocity.y += 1.0

	if velocity != Vector2.ZERO:
		position += velocity.normalized() * speed * delta
	elif pointer_active:
		var to_target := pointer_target - position
		var step := speed * 1.6 * delta
		if to_target.length() > 4.0:
			position += to_target.normalized() * minf(step, to_target.length())

	var view := get_viewport_rect().size
	position.x = clampf(position.x, margin, view.x - margin)
	position.y = clampf(position.y, margin, view.y - margin)

func _on_fire_timer_timeout() -> void:
	var main := get_parent()
	if main != null and main.get("is_game_over"):
		return
	var bullet := BulletScript.new()
	bullet.position = position + Vector2(0, -30)
	if main != null:
		main.add_child(bullet)

func _on_area_entered(area: Area2D) -> void:
	if invincible or not area.is_in_group("enemies"):
		return
	area.queue_free()
	var main := get_parent()
	if main != null and main.has_method("spawn_explosion"):
		main.spawn_explosion(position)
	if main != null and main.has_method("lose_life"):
		main.lose_life()
	_start_invincibility()

func _start_invincibility() -> void:
	invincible = true
	modulate.a = 0.35
	await get_tree().create_timer(1.2).timeout
	if is_inside_tree():
		modulate.a = 1.0
		invincible = false

func _draw() -> void:
	# Ship body (points up).
	var body := PackedVector2Array([
		Vector2(0, -24), Vector2(17, 16), Vector2(6, 10),
		Vector2(-6, 10), Vector2(-17, 16)
	])
	draw_colored_polygon(body, Color(0.22, 0.78, 0.85))
	draw_circle(Vector2(0, -4), 6.0, Color(0.92, 1.0, 1.0))
	# Engine flame.
	var flame := PackedVector2Array([
		Vector2(-5, 17), Vector2(5, 17), Vector2(0, 28)
	])
	draw_colored_polygon(flame, Color(1.0, 0.62, 0.25, 0.9))

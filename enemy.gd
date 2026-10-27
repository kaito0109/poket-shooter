extends Area2D
## Enemy ship: drifts down with a gentle sway. 2 hits to destroy.

var fall_speed: float = 160.0
var hp: int = 2
var sway_phase: float = 0.0
var spawn_x: float = 0.0
var age: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	z_index = 8
	spawn_x = position.x
	sway_phase = randf() * TAU
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(42, 32)
	shape_node.shape = shape
	add_child(shape_node)

func _physics_process(delta: float) -> void:
	age += delta
	position.y += fall_speed * delta
	position.x = spawn_x + sin(age * 2.2 + sway_phase) * 26.0
	if position.y > 1010.0:
		queue_free()

func take_hit(damage: int) -> void:
	hp -= damage
	modulate = Color(1.0, 0.45, 0.45)
	if hp <= 0:
		var main := get_parent()
		if main != null and main.has_method("add_score"):
			main.add_score(100)
		if main != null and main.has_method("spawn_explosion"):
			main.spawn_explosion(global_position)
		queue_free()
	else:
		await get_tree().create_timer(0.07).timeout
		if is_inside_tree():
			modulate = Color.WHITE

func _draw() -> void:
	# Enemy body (points down).
	var body := PackedVector2Array([
		Vector2(0, 22), Vector2(20, -14), Vector2(7, -8),
		Vector2(-7, -8), Vector2(-20, -14)
	])
	draw_colored_polygon(body, Color(0.9, 0.3, 0.35))
	draw_circle(Vector2(0, 2), 5.5, Color(1.0, 0.85, 0.6))

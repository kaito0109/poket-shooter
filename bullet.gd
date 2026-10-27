extends Area2D
## Player bullet: flies straight up, hits enemies.

var speed: float = 760.0

func _ready() -> void:
	add_to_group("bullets")
	z_index = 5
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(8, 18)
	shape_node.shape = shape
	add_child(shape_node)
	area_entered.connect(_on_area_entered)

func _physics_process(delta: float) -> void:
	position.y -= speed * delta
	if position.y < -30.0:
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("enemies") and area.has_method("take_hit"):
		area.take_hit(1)
		queue_free()

func _draw() -> void:
	draw_rect(Rect2(-3, -10, 6, 20), Color(1.0, 0.9, 0.35))
	draw_circle(Vector2(0, -10), 3.5, Color(1.0, 1.0, 0.75))

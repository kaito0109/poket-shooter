extends Node3D
## Thrown frag grenade: bounces, then explodes after a short fuse.

var thrower: Node3D = null
var velocity: Vector3 = Vector3.ZERO
var fuse: float = 2.6
var resting: bool = false

func setup(p_thrower: Node3D, from: Vector3, vel: Vector3) -> void:
	thrower = p_thrower
	global_position = from
	velocity = vel
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.09
	sphere.height = 0.18
	body.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.32, 0.18)
	body.material_override = mat
	add_child(body)
	var pin := MeshInstance3D.new()
	var pin_mesh := BoxMesh.new()
	pin_mesh.size = Vector3(0.05, 0.07, 0.05)
	pin.mesh = pin_mesh
	pin.position.y = 0.11
	var pin_mat := StandardMaterial3D.new()
	pin_mat.albedo_color = Color(0.6, 0.6, 0.62)
	pin.material_override = pin_mat
	add_child(pin)

func _physics_process(delta: float) -> void:
	fuse -= delta
	if fuse <= 0.0:
		var main: Node = get_tree().get_first_node_in_group("main")
		if main != null:
			main.call("explode", global_position, thrower)
		queue_free()
		return
	if resting:
		return
	velocity.y -= 18.0 * delta
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var remaining: float = velocity.length() * delta
	var dir: Vector3 = velocity.normalized()
	var steps: int = 0
	while remaining > 0.0 and steps < 6:
		steps += 1
		var step: float = minf(remaining, 0.35)
		var from: Vector3 = global_position
		var to: Vector3 = from + dir * step
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1))
		if hit.is_empty():
			global_position = to
			remaining -= step
		else:
			global_position = (hit["position"] as Vector3) - dir * 0.06
			var normal: Vector3 = hit["normal"]
			velocity = velocity.bounce(normal) * 0.38
			if velocity.length() < 1.4:
				velocity = Vector3.ZERO
				resting = true
			else:
				dir = velocity.normalized()
			remaining = 0.0

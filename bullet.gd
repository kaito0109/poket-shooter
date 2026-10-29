extends Node3D
## A projectile with travel time and damage falloff (not hitscan).

var shooter: Node3D = null
var weapon_id: String = ""
var damage: float = 0.0
var speed: float = 200.0
var falloff_from: float = 100.0
var direction: Vector3 = Vector3.FORWARD
var start_pos: Vector3 = Vector3.ZERO
var traveled: float = 0.0
var life: float = 0.0
const MAX_RANGE: float = 420.0

func setup(p_shooter: Node3D, p_weapon_id: String, from: Vector3, dir: Vector3) -> void:
	shooter = p_shooter
	weapon_id = p_weapon_id
	var data: Dictionary = Weapons.DATA[p_weapon_id]
	damage = float(data["dmg"])
	speed = float(data["speed"])
	falloff_from = float(data["falloff"])
	direction = dir.normalized()
	start_pos = from
	global_position = from
	look_at(from + direction, Vector3.UP)
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.05, 0.85)
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.35)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.7, 0.25)
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = StandardMaterial3D.SHADING_MODE_UNSHADED
	mesh_inst.material_override = mat
	mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mesh_inst)

func _physics_process(delta: float) -> void:
	life += delta
	var remaining: float = speed * delta
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if shooter != null and is_instance_valid(shooter):
		exclude.append((shooter as CollisionObject3D).get_rid())
	while remaining > 0.0:
		var step: float = minf(remaining, 1.6)
		var from: Vector3 = global_position
		var to: Vector3 = from + direction * step
		var query := PhysicsRayQueryParameters3D.create(from, to, 3, exclude)
		var hit: Dictionary = space.intersect_ray(query)
		if not hit.is_empty():
			_on_hit(hit)
			queue_free()
			return
		global_position = to
		traveled += step
		remaining -= step
		if traveled > MAX_RANGE:
			queue_free()
			return

func _on_hit(hit: Dictionary) -> void:
	var collider: Object = hit.get("collider")
	var pos: Vector3 = hit.get("position", global_position)
	var main: Node = get_tree().get_first_node_in_group("main")
	if collider is Node3D and (collider as Node).is_in_group("actors"):
		var target: Node3D = collider as Node3D
		var dist: float = start_pos.distance_to(pos)
		var factor: float = 1.0
		if dist > falloff_from:
			factor = lerpf(1.0, 0.45, clampf((dist - falloff_from) / 300.0, 0.0, 1.0))
		if target.has_method("take_damage"):
			target.call("take_damage", damage * factor, shooter, pos, false)
		if main != null and shooter != null and shooter.is_in_group("player"):
			main.call("on_player_hit")
	else:
		if main != null:
			main.call("spawn_spark", pos, Color(0.85, 0.8, 0.6))

extends CharacterBody3D
## Simple bot: approach the player, keep distance, fire bursts with spread.

const ModelUtil := preload("res://model_util.gd")

const MAX_HP: int = 100
const SPEED: float = 3.4
const GRAVITY: float = 24.0
const STOP_DISTANCE: float = 15.0
const SIGHT_RANGE: float = 30.0
const MODEL_FACING_OFFSET: float = PI

var hp: int = MAX_HP
var dead: bool = false
var active: bool = false

var model_root: Node3D
var mesh_instance: MeshInstance3D
var anim_player: AnimationPlayer
var tint_material: StandardMaterial3D
var base_tint := Color(1.35, 0.5, 0.5)

var head_marker: MeshInstance3D
var burst_left: int = 0
var burst_timer: float = 0.0
var think_timer: float = 0.0
var strafe_dir: float = 1.0
var flash_timer: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 1 | 4

	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape_node.shape = capsule
	shape_node.position.y = 0.85
	add_child(shape_node)

	var attached: Dictionary = ModelUtil.attach_character(self, "res://assets/player.glb", 1.78, base_tint)
	model_root = attached.get("model", null)
	mesh_instance = attached.get("mesh", null)
	anim_player = attached.get("anim_player", null)
	if model_root != null:
		model_root.rotation.y = MODEL_FACING_OFFSET
	if mesh_instance != null:
		tint_material = mesh_instance.material_override as StandardMaterial3D
	# Overhead marker so bots stay visible at range.
	head_marker = MeshInstance3D.new()
	var marker_mesh := SphereMesh.new()
	marker_mesh.radius = 0.09
	marker_mesh.height = 0.18
	marker_mesh.radial_segments = 10
	marker_mesh.rings = 6
	head_marker.mesh = marker_mesh
	var marker_mat := StandardMaterial3D.new()
	marker_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_mat.albedo_color = Color(1.0, 0.2, 0.15)
	head_marker.material_override = marker_mat
	head_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head_marker.position = Vector3(0, 2.05, 0)
	add_child(head_marker)
	burst_timer = randf_range(0.8, 1.6)
	think_timer = randf() * 0.5
	if randf() < 0.5:
		strafe_dir = -1.0

func _physics_process(delta: float) -> void:
	if dead:
		return
	if flash_timer > 0.0:
		flash_timer -= delta
		if flash_timer <= 0.0 and tint_material != null:
			tint_material.albedo_color = base_tint

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -0.5

	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	if not active or player == null or not is_instance_valid(player):
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		ModelUtil.set_locomotion(anim_player, false, 0.0)
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()
	var dir_to_player: Vector3 = to_player.normalized() if dist > 0.01 else Vector3.FORWARD

	# Face the player.
	var target_yaw: float = atan2(dir_to_player.x, dir_to_player.z)
	if model_root != null:
		model_root.rotation.y = target_yaw + MODEL_FACING_OFFSET

	var move_dir := Vector3.ZERO
	if dist > STOP_DISTANCE:
		move_dir = dir_to_player
	elif dist < STOP_DISTANCE * 0.7:
		move_dir = -dir_to_player * 0.6
	else:
		# Strafe slowly around the player.
		think_timer -= delta
		if think_timer <= 0.0:
			think_timer = randf_range(1.2, 2.6)
			if randf() < 0.4:
				strafe_dir = -strafe_dir
		move_dir = Vector3(-dir_to_player.z, 0, dir_to_player.x) * strafe_dir * 0.45

	# Gentle separation from other bots.
	for other: Node in get_tree().get_nodes_in_group("enemies"):
		if other == self or not (other is Node3D):
			continue
		var diff: Vector3 = global_position - (other as Node3D).global_position
		diff.y = 0.0
		var d: float = diff.length()
		if d > 0.01 and d < 1.6:
			move_dir += diff.normalized() * (1.6 - d)

	velocity.x = move_dir.x * SPEED
	velocity.z = move_dir.z * SPEED
	move_and_slide()
	ModelUtil.set_locomotion(anim_player, Vector2(velocity.x, velocity.z).length() > 0.4, 0.55)

	# Shooting: burst fire with distance-based accuracy when in sight.
	burst_timer -= delta
	if dist < SIGHT_RANGE and _has_line_of_sight(player):
		if burst_left > 0:
			if burst_timer <= 0.0:
				burst_timer = 0.17
				burst_left -= 1
				_bot_shoot(player, dist)
		elif burst_timer <= -randf_range(1.2, 2.2):
			burst_left = 4
			burst_timer = 0.0

func _has_line_of_sight(player: Node3D) -> bool:
	var from: Vector3 = global_position + Vector3(0, 1.5, 0)
	var to: Vector3 = player.global_position + Vector3(0, 1.2, 0)
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 2, [get_rid()])
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if result.is_empty():
		return true
	var collider: Object = result["collider"]
	return collider == player

func _bot_shoot(player: Node3D, dist: float) -> void:
	var main = get_parent()
	var muzzle_pos: Vector3 = global_position + Vector3(0, 1.4, 0) + (player.global_position - global_position).normalized() * 0.5
	var target_pos: Vector3 = player.global_position + Vector3(0, 1.1, 0)
	var hit_chance: float = clampf(0.95 - dist / 30.0, 0.15, 0.62)
	var is_hit: bool = randf() < hit_chance
	var end_point: Vector3 = target_pos
	if is_hit:
		if player.has_method("take_damage"):
			player.call("take_damage", 5, self)
	else:
		end_point = target_pos + Vector3(randf_range(-1.6, 1.6), randf_range(-0.5, 1.2), randf_range(-1.6, 1.6))
	if main != null and main.has_method("spawn_tracer"):
		main.spawn_tracer(muzzle_pos, end_point, Color(1.0, 0.45, 0.35, 0.9))
		main.spawn_spark(muzzle_pos, Color(1.0, 0.6, 0.35))

func take_damage(amount: int, _from: Node3D) -> void:
	if dead:
		return
	hp -= amount
	if tint_material != null:
		tint_material.albedo_color = Color(3.0, 3.0, 3.0)
		flash_timer = 0.07
	if hp <= 0:
		_die()

func _die() -> void:
	dead = true
	if head_marker != null:
		head_marker.visible = false
	collision_layer = 0
	collision_mask = 0
	var main = get_parent()
	if main != null and main.has_method("on_bot_killed"):
		main.on_bot_killed(self)
	if model_root != null:
		var tween: Tween = create_tween()
		tween.tween_property(model_root, "rotation:x", -PI * 0.5, 0.35)
		tween.tween_interval(2.2)
		tween.tween_property(model_root, "position:y", model_root.position.y - 1.2, 1.0)
		tween.tween_callback(queue_free)
	else:
		queue_free()

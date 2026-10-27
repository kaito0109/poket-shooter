extends CharacterBody3D
## TPS player: camera-relative movement, mouse/touch look, hitscan shooting.

const ModelUtil := preload("res://model_util.gd")

const MAX_HP: int = 100
const MAX_AMMO: int = 30
const WALK_SPEED: float = 5.2
const SPRINT_SPEED: float = 7.6
const GRAVITY: float = 24.0
const JUMP_VELOCITY: float = 8.6
const FIRE_INTERVAL: float = 0.13
const RELOAD_TIME: float = 1.3
const MODEL_FACING_OFFSET: float = 0.0  # This GLB character faces -Z after Godot import (verified by screenshot).

var hp: int = MAX_HP
var ammo: int = MAX_AMMO
var reloading: bool = false
var dead: bool = false
var input_enabled: bool = false

var yaw: float = 0.0
var pitch: float = -0.18
var fire_cooldown: float = 0.0
var jump_requested: bool = false

var touch_move: Vector2 = Vector2.ZERO
var touch_firing: bool = false

var model_root: Node3D
var anim_player: AnimationPlayer
var yaw_node: Node3D
var camera: Camera3D
var muzzle: Marker3D

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4

	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.7
	shape_node.shape = capsule
	shape_node.position.y = 0.85
	add_child(shape_node)

	var attached: Dictionary = ModelUtil.attach_character(self, "res://assets/player.glb", 1.75, Color.WHITE)
	model_root = attached.get("model", null)
	anim_player = attached.get("anim_player", null)
	if model_root != null:
		model_root.rotation.y = MODEL_FACING_OFFSET

	# Camera rig: yaw -> pitch -> spring arm -> camera (over-the-shoulder).
	yaw_node = Node3D.new()
	yaw_node.position = Vector3(0, 1.55, 0)
	add_child(yaw_node)
	var pitch_node := Node3D.new()
	pitch_node.name = "Pitch"
	yaw_node.add_child(pitch_node)
	var spring := SpringArm3D.new()
	spring.spring_length = 4.4
	spring.margin = 0.3
	spring.position = Vector3(0.85, 0.3, 0)
	spring.collision_mask = 1
	pitch_node.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	spring.add_child(camera)

	muzzle = Marker3D.new()
	muzzle.position = Vector3(0.32, 1.32, -0.55)
	add_child(muzzle)

	_apply_camera_rotation()

func _apply_camera_rotation() -> void:
	yaw_node.rotation.y = yaw
	var pitch_node: Node = yaw_node.get_node("Pitch")
	(pitch_node as Node3D).rotation.x = pitch
	if model_root != null:
		model_root.rotation.y = yaw + MODEL_FACING_OFFSET

func add_look_input(relative_px: Vector2) -> void:
	if not input_enabled or dead:
		return
	yaw -= relative_px.x * 0.0042
	pitch = clampf(pitch - relative_px.y * 0.0042, -0.95, 0.6)
	_apply_camera_rotation()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and input_enabled and not dead:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			yaw -= motion.relative.x * 0.0026
			pitch = clampf(pitch - motion.relative.y * 0.0026, -0.95, 0.6)
			_apply_camera_rotation()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			yaw -= motion.relative.x * 0.004
			pitch = clampf(pitch - motion.relative.y * 0.004, -0.95, 0.6)
			_apply_camera_rotation()
	if event is InputEventMouseButton and event.pressed and input_enabled and not dead:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			var main = get_parent()
			if main != null and main.has_method("request_mouse_capture"):
				main.request_mouse_capture()
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		if key.physical_keycode == KEY_SPACE:
			jump_requested = true
		elif key.physical_keycode == KEY_R:
			start_reload()

func _physics_process(delta: float) -> void:
	if dead:
		return
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)

	var input_dir := Vector2.ZERO
	if input_enabled:
		if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
			input_dir.x -= 1.0
		if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
			input_dir.x += 1.0
		if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
			input_dir.y -= 1.0
		if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
			input_dir.y += 1.0
		input_dir += touch_move
		if input_dir.length() > 1.0:
			input_dir = input_dir.normalized()

	var sprinting: bool = Input.is_physical_key_pressed(KEY_SHIFT) and input_dir.y < 0.0
	var speed: float = SPRINT_SPEED if sprinting else WALK_SPEED
	var forward: Vector3 = -yaw_node.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = yaw_node.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	# input_dir.y is -1 when pressing forward (W), so move along +forward.
	var wish_dir: Vector3 = (right * input_dir.x + forward * -input_dir.y)
	wish_dir.y = 0.0
	if wish_dir.length() > 1.0:
		wish_dir = wish_dir.normalized()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		if jump_requested and input_enabled:
			velocity.y = JUMP_VELOCITY
		elif velocity.y < 0.0:
			velocity.y = -0.5
	jump_requested = false

	velocity.x = wish_dir.x * speed
	velocity.z = wish_dir.z * speed
	move_and_slide()

	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	ModelUtil.set_locomotion(anim_player, horizontal_speed > 0.4, horizontal_speed / SPRINT_SPEED)

	# Shooting.
	var firing: bool = false
	if input_enabled:
		firing = touch_firing or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	if firing and fire_cooldown <= 0.0 and not reloading:
		if ammo > 0:
			_shoot()
			fire_cooldown = FIRE_INTERVAL
		else:
			start_reload()

func _shoot() -> void:
	ammo -= 1
	_notify_hud()
	var main = get_parent()
	var from: Vector3 = camera.global_position
	var center: Vector2 = get_viewport().get_visible_rect().size * 0.5
	var dir: Vector3 = camera.project_ray_normal(center)
	var to: Vector3 = from + dir * 140.0
	var query := PhysicsRayQueryParameters3D.create(from, to, 1 | 4, [get_rid()])
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var result: Dictionary = space.intersect_ray(query)
	var end_point: Vector3 = to
	if not result.is_empty():
		end_point = result["position"]
		var collider: Object = result["collider"]
		if collider != null and collider.has_method("take_damage"):
			collider.call("take_damage", 34, self)
		if main != null and main.has_method("spawn_spark"):
			main.spawn_spark(end_point, Color(1.0, 0.7, 0.3))
	if main != null and main.has_method("spawn_tracer"):
		main.spawn_tracer(muzzle.global_position, end_point, Color(1.0, 0.85, 0.4, 0.9))
		main.spawn_spark(muzzle.global_position, Color(1.0, 0.8, 0.4))
	pitch = clampf(pitch + 0.004, -0.95, 0.6)
	_apply_camera_rotation()

func start_reload() -> void:
	if reloading or ammo == MAX_AMMO or dead:
		return
	reloading = true
	_notify_hud()
	await get_tree().create_timer(RELOAD_TIME).timeout
	if not is_inside_tree() or dead:
		return
	ammo = MAX_AMMO
	reloading = false
	_notify_hud()

func request_jump() -> void:
	jump_requested = true

func take_damage(amount: int, _from: Node3D) -> void:
	if dead or not input_enabled:
		return
	hp -= amount
	var main = get_parent()
	if main != null and main.has_method("on_player_damaged"):
		main.on_player_damaged(hp, MAX_HP, _from)
	if hp <= 0:
		hp = 0
		dead = true
		if main != null and main.has_method("game_over"):
			main.game_over(false)

func _notify_hud() -> void:
	var main = get_parent()
	if main != null and main.has_method("on_ammo_changed"):
		main.on_ammo_changed(ammo, MAX_AMMO, reloading)

extends CharacterBody3D
## TPS player: camera-relative movement, mouse/touch look, hitscan shooting,
## ADS, crouch, first-person toggle, healing items, vest/rifle upgrades.

const ModelUtil := preload("res://model_util.gd")

const MAX_HP: int = 100
const BASE_MAX_AMMO: int = 30
const UPGRADED_MAX_AMMO: int = 40
const WALK_SPEED: float = 5.2
const SPRINT_SPEED: float = 7.6
const GRAVITY: float = 24.0
const JUMP_VELOCITY: float = 8.6
const BASE_FIRE_INTERVAL: float = 0.13
const BASE_DAMAGE: int = 34
const HEAL_TIME: float = 3.0
const HEAL_AMOUNT: int = 55
const DRINK_AMOUNT: int = 25
const MODEL_FACING_OFFSET: float = 0.0  # This GLB character faces -Z after Godot import.

var hp: int = MAX_HP
var ammo: int = BASE_MAX_AMMO
var max_ammo: int = BASE_MAX_AMMO
var damage_per_shot: int = BASE_DAMAGE
var fire_interval: float = BASE_FIRE_INTERVAL
var reloading: bool = false
var dead: bool = false
var input_enabled: bool = false

var medkits: int = 0
var drinks: int = 0
var has_vest: bool = false
var rifle_upgraded: bool = false
var healing: bool = false
var heal_time_left: float = 0.0

var aiming: bool = false
var touch_aiming: bool = false
var crouching: bool = false
var first_person: bool = false

var yaw: float = 0.0
var pitch: float = -0.18
var fire_cooldown: float = 0.0
var jump_requested: bool = false

var touch_move: Vector2 = Vector2.ZERO
var touch_firing: bool = false

var model_root: Node3D
var model_base_scale: Vector3 = Vector3.ONE
var anim_player: AnimationPlayer
var yaw_node: Node3D
var pitch_node: Node3D
var spring: SpringArm3D
var camera: Camera3D
var muzzle: Marker3D
var gun_root: Node3D
var capsule: CapsuleShape3D
var shape_node: CollisionShape3D
var sfx: Node

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1 | 4

	shape_node = CollisionShape3D.new()
	capsule = CapsuleShape3D.new()
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
		model_base_scale = model_root.scale

	_build_gun()

	# Camera rig: yaw -> pitch -> spring arm -> camera (over-the-shoulder).
	yaw_node = Node3D.new()
	yaw_node.position = Vector3(0, 1.55, 0)
	add_child(yaw_node)
	pitch_node = Node3D.new()
	pitch_node.name = "Pitch"
	yaw_node.add_child(pitch_node)
	spring = SpringArm3D.new()
	spring.spring_length = 4.4
	spring.margin = 0.3
	spring.position = Vector3(0.85, 0.3, 0)
	spring.collision_mask = 1
	pitch_node.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	spring.add_child(camera)

	_apply_camera_rotation()

func _build_gun() -> void:
	gun_root = Node3D.new()
	gun_root.position = Vector3(0.3, 1.28, -0.25)
	add_child(gun_root)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.35, 0.35, 0.38)
	var receiver := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(0.08, 0.15, 0.55)
	receiver.mesh = rbox
	receiver.material_override = dark
	gun_root.add_child(receiver)
	var barrel := MeshInstance3D.new()
	var bcyl := CylinderMesh.new()
	bcyl.top_radius = 0.025
	bcyl.bottom_radius = 0.025
	bcyl.height = 0.4
	barrel.mesh = bcyl
	barrel.material_override = accent
	barrel.rotation.x = PI * 0.5
	barrel.position = Vector3(0, 0.03, -0.45)
	gun_root.add_child(barrel)
	var mag := MeshInstance3D.new()
	var mbox := BoxMesh.new()
	mbox.size = Vector3(0.06, 0.2, 0.11)
	mag.mesh = mbox
	mag.material_override = accent
	mag.position = Vector3(0, -0.15, -0.05)
	gun_root.add_child(mag)
	muzzle = Marker3D.new()
	muzzle.position = Vector3(0, 0.03, -0.68)
	gun_root.add_child(muzzle)

func _sfx(sound_name: String, volume_db: float = 0.0) -> void:
	if sfx == null:
		sfx = get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", sound_name, volume_db)

func _apply_camera_rotation() -> void:
	yaw_node.rotation.y = yaw
	pitch_node.rotation.x = pitch
	if model_root != null:
		model_root.rotation.y = yaw + MODEL_FACING_OFFSET
	if gun_root != null:
		gun_root.rotation.y = yaw

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
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not aiming:
			yaw -= motion.relative.x * 0.004
			pitch = clampf(pitch - motion.relative.y * 0.004, -0.95, 0.6)
			_apply_camera_rotation()
	if event is InputEventMouseButton and event.pressed and input_enabled and not dead:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			var main: Node = get_parent()
			if main != null and main.has_method("request_mouse_capture"):
				main.request_mouse_capture()
	if event is InputEventKey and event.pressed and not event.echo:
		var key: InputEventKey = event as InputEventKey
		match key.physical_keycode:
			KEY_SPACE:
				jump_requested = true
			KEY_R:
				start_reload()
			KEY_C:
				toggle_crouch()
			KEY_V:
				toggle_first_person()
			KEY_H:
				start_heal()
			KEY_F:
				use_drink()

func _process(delta: float) -> void:
	# Camera feel: distance/FOV ease for ADS and first-person.
	var target_len: float = 4.4
	var target_fov: float = 70.0
	var target_spring_x: float = 0.85
	if first_person:
		target_len = 0.0
		target_fov = 74.0
		target_spring_x = 0.0
	elif aiming:
		target_len = 2.1
		target_fov = 52.0
	var k: float = 1.0 - exp(-11.0 * delta)
	spring.spring_length = lerpf(spring.spring_length, target_len, k)
	spring.position.x = lerpf(spring.position.x, target_spring_x, k)
	camera.fov = lerpf(camera.fov, target_fov, k)
	var target_cam_y: float = 1.02 if crouching else 1.55
	yaw_node.position.y = lerpf(yaw_node.position.y, target_cam_y, k)

func _physics_process(delta: float) -> void:
	if dead:
		return
	fire_cooldown = maxf(fire_cooldown - delta, 0.0)

	aiming = touch_aiming or (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)

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

	# Healing channel.
	if healing:
		if input_dir.length() > 0.15:
			healing = false
			_sync_hud()
		else:
			heal_time_left -= delta
			_sync_hud()
			if heal_time_left <= 0.0:
				healing = false
				medkits -= 1
				hp = mini(MAX_HP, hp + HEAL_AMOUNT)
				_sfx("heal")
				_sync_hud()

	var sprinting: bool = Input.is_physical_key_pressed(KEY_SHIFT) and input_dir.y < 0.0 and not crouching and not aiming
	var speed: float = SPRINT_SPEED if sprinting else WALK_SPEED
	if crouching:
		speed *= 0.52
	if aiming:
		speed *= 0.6
	var forward: Vector3 = -yaw_node.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = yaw_node.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var wish_dir: Vector3 = (right * input_dir.x + forward * -input_dir.y)
	wish_dir.y = 0.0
	if wish_dir.length() > 1.0:
		wish_dir = wish_dir.normalized()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		if jump_requested and input_enabled and not crouching:
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
	if firing and fire_cooldown <= 0.0 and not reloading and not healing:
		if ammo > 0:
			_shoot()
			fire_cooldown = fire_interval
		else:
			start_reload()

func _shoot() -> void:
	ammo -= 1
	_sync_hud()
	_sfx("shot", -6.0)
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
			collider.call("take_damage", damage_per_shot, self)
			if main != null and main.has_method("on_player_hit"):
				main.on_player_hit()
		if main != null and main.has_method("spawn_spark"):
			main.spawn_spark(end_point, Color(1.0, 0.7, 0.3))
	if main != null and main.has_method("spawn_tracer"):
		main.spawn_tracer(muzzle.global_position, end_point, Color(1.0, 0.85, 0.4, 0.9))
		main.spawn_spark(muzzle.global_position, Color(1.0, 0.8, 0.4))
	pitch = clampf(pitch + 0.004, -0.95, 0.6)
	_apply_camera_rotation()

func start_reload() -> void:
	if reloading or ammo == max_ammo or dead:
		return
	reloading = true
	healing = false
	_sfx("reload", -4.0)
	_sync_hud()
	await get_tree().create_timer(1.3).timeout
	if not is_inside_tree() or dead:
		return
	ammo = max_ammo
	reloading = false
	_sync_hud()

func start_heal() -> bool:
	if healing or dead or medkits <= 0 or hp >= MAX_HP:
		return false
	healing = true
	heal_time_left = HEAL_TIME
	_sync_hud()
	return true

func use_drink() -> bool:
	if dead or drinks <= 0 or hp >= MAX_HP:
		return false
	drinks -= 1
	hp = mini(MAX_HP, hp + DRINK_AMOUNT)
	_sfx("heal", -2.0)
	_sync_hud()
	return true

func apply_loot(loot_type: String) -> String:
	match loot_type:
		"medkit":
			medkits += 1
			_sync_hud()
			return "医療キットを拾った（Hで使用）"
		"drink":
			drinks += 1
			_sync_hud()
			return "エナジードリンクを拾った（Fで使用）"
		"rifle":
			if rifle_upgraded:
				ammo = max_ammo
				_sync_hud()
				return "強化ライフルは装備済み（弾薬を補充）"
			rifle_upgraded = true
			damage_per_shot = 46
			fire_interval = 0.115
			max_ammo = UPGRADED_MAX_AMMO
			ammo = max_ammo
			_sync_hud()
			return "強化ライフルを装備！ ダメージと弾数がアップ"
		"vest":
			if has_vest:
				hp = mini(MAX_HP, hp + 20)
				_sync_hud()
				return "ベストは装備済み（少し回復）"
			has_vest = true
			_sync_hud()
			return "防弾ベストを装備！ 被ダメージ-30%"
	return ""

func toggle_crouch() -> void:
	if dead:
		return
	crouching = not crouching
	var h: float = 1.15 if crouching else 1.7
	capsule.height = h
	shape_node.position.y = h * 0.5
	if model_root != null:
		var y_ratio: float = 0.72 if crouching else 1.0
		model_root.scale = Vector3(model_base_scale.x, model_base_scale.y * y_ratio, model_base_scale.z)
	if gun_root != null:
		gun_root.position.y = 0.95 if crouching else 1.28

func toggle_first_person() -> void:
	if dead:
		return
	first_person = not first_person
	if model_root != null:
		model_root.visible = not first_person

func request_jump() -> void:
	jump_requested = true

func take_damage(amount: int, from_node: Node3D = null, is_zone: bool = false) -> void:
	if dead:
		return
	if not is_zone and not input_enabled:
		return
	var final_amount: int = amount
	if has_vest and not is_zone:
		final_amount = maxi(1, int(round(float(amount) * 0.7)))
	hp -= final_amount
	healing = false
	if not is_zone:
		_sfx("hurt", -6.0)
	var main = get_parent()
	if main != null and main.has_method("on_player_damaged"):
		main.on_player_damaged(hp, MAX_HP, from_node)
	_sync_hud()
	if hp <= 0:
		hp = 0
		dead = true
		if main != null and main.has_method("game_over"):
			main.game_over(false)

func heal_progress() -> float:
	if not healing:
		return -1.0
	return clampf(1.0 - heal_time_left / HEAL_TIME, 0.0, 1.0)

func _sync_hud() -> void:
	var main = get_parent()
	if main != null and main.has_method("sync_hud"):
		main.sync_hud()

extends CharacterBody3D
## Player: plane ride, freefall, parachute, looting, PUBG-style weapons/items.

const ModelUtil := preload("res://model_util.gd")
const MAX_HP: int = 100

var display_name: String = "You"
var hp: int = MAX_HP
var dead: bool = false
var state: String = "plane"  # plane | fall | chute | ground
var input_enabled: bool = false

var yaw: float = 0.0
var pitch: float = -0.12
var capsule: CollisionShape3D
var model_root: Node3D
var model_base_scale: float = 1.0
var anim: AnimationPlayer
var spring: SpringArm3D
var camera: Camera3D
var gun_root: Node3D
var muzzle: Marker3D
var canopy: Node3D
var model_anim_time: float = 0.0
var was_moving: bool = false

# Weapons / inventory
var slots: Array = ["", ""]
var slot_mags: Array = [0, 0]
var current_slot: int = 0
var reserve: Dictionary = {"9mm": 0, "556": 0, "762": 0, "shell": 0}
var helmet_lv: int = 0
var vest_lv: int = 0
var bandages: int = 0
var firstaids: int = 0
var medkits: int = 0
var drinks: int = 0
var painkillers: int = 0
var boost: float = 0.0
var boost_tick: float = 0.0
var last_loot_message: String = ""

var fire_timer: float = 0.0
var reloading: bool = false
var reload_left: float = 0.0
var heal_kind: String = ""
var heal_left: float = 0.0
var heal_duration: float = 0.0
var aiming: bool = false
var crouching: bool = false
var first_person: bool = false
var kick_offset: float = 0.0
var lean: float = 0.0
var fall_time: float = 0.0
var air_forward: Vector3 = Vector3.ZERO
var last_attacker: Node3D = null

# Touch controls (set by HUD)
var touch_move: Vector2 = Vector2.ZERO
var touch_firing: bool = false
var touch_aiming: bool = false
var touch_jump: bool = false
var _prev_fire_held: bool = false

func _ready() -> void:
	add_to_group("player")
	add_to_group("actors")
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.6
	var shape_node := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.35
	shape.height = 1.7
	shape_node.shape = shape
	shape_node.position.y = 0.85
	add_child(shape_node)
	capsule = shape_node

	var attached: Dictionary = ModelUtil.attach_character(self, "res://assets/player.glb", 1.75, Color.WHITE)
	model_root = attached.get("model")
	anim = attached.get("anim_player")
	if model_root != null:
		model_base_scale = model_root.scale.y

	spring = SpringArm3D.new()
	spring.position = Vector3(0.55, 1.55, 0)
	spring.spring_length = 4.4
	spring.collision_mask = 1
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	spring.add_child(camera)

	gun_root = Node3D.new()
	gun_root.position = Vector3(0.34, 1.28, -0.25)
	add_child(gun_root)
	muzzle = Marker3D.new()
	gun_root.add_child(muzzle)
	_build_gun("")

func is_grounded() -> bool:
	return state == "ground"

func current_weapon_id() -> String:
	return String(slots[current_slot])

func current_data() -> Dictionary:
	var wid: String = current_weapon_id()
	if wid == "":
		return {}
	return Weapons.DATA[wid]

# --- Plane / air ---

func eject(from_pos: Vector3, forward: Vector3) -> void:
	if state != "plane":
		return
	state = "fall"
	fall_time = 0.0
	global_position = from_pos + Vector3(0, -3, 0)
	air_forward = Vector3(forward.x, 0, forward.z).normalized()
	yaw = atan2(-air_forward.x, -air_forward.z)
	velocity = air_forward * 24.0
	visible = true
	input_enabled = true
	_apply_camera_rotation()

func _open_chute() -> void:
	state = "chute"
	canopy = Node3D.new()
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.7
	sphere.height = 1.6
	dome.mesh = sphere
	dome.scale = Vector3(1.15, 0.42, 1.15)
	dome.position.y = 3.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.55, 0.15)
	dome.material_override = mat
	canopy.add_child(dome)
	for sx in [-0.5, 0.5]:
		var line := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.015
		cyl.bottom_radius = 0.015
		cyl.height = 2.1
		line.mesh = cyl
		line.position = Vector3(sx, 2.55, 0)
		line.rotation.z = sx * 0.45
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(0.1, 0.1, 0.1)
		line.material_override = lm
		canopy.add_child(line)
	add_child(canopy)
	_play_sfx("chute", -6.0)

func _land() -> void:
	state = "ground"
	if canopy != null:
		canopy.queue_free()
		canopy = null
	velocity = Vector3.ZERO

# --- Damage / healing ---

func take_damage(amount: float, from_node: Node3D = null, hit_pos: Vector3 = Vector3.ZERO, is_zone: bool = false) -> void:
	if dead or state == "plane":
		return
	var final_amount: float = amount
	if not is_zone:
		var rel_y: float = hit_pos.y - global_position.y
		var head_line: float = (capsule.shape as CapsuleShape3D).height * 0.84
		if rel_y > head_line:
			var helmet_red: Array = [0.0, 0.3, 0.4, 0.55]
			final_amount = amount * 2.0 * (1.0 - float(helmet_red[helmet_lv]))
		else:
			var vest_red: Array = [0.0, 0.2, 0.3, 0.4]
			final_amount = amount * (1.0 - float(vest_red[vest_lv]))
	if from_node != null:
		last_attacker = from_node
	hp = maxi(hp - int(round(final_amount)), 0)
	if heal_kind != "":
		heal_kind = ""
		heal_left = 0.0
	var main: Node = get_tree().get_first_node_in_group("main")
	if main != null:
		if not is_zone:
			main.call("on_player_damaged", hp, MAX_HP, from_node)
		main.call("sync_hud")
	_play_sfx("hurt", -10.0)
	if hp <= 0 and not dead:
		dead = true
		input_enabled = false
		if main != null:
			main.call("on_actor_killed", self, last_attacker)
		var tween := create_tween()
		tween.tween_property(model_root, "rotation:x", -PI * 0.5, 0.6)

func heal_progress() -> float:
	if heal_kind == "" or heal_duration <= 0.0:
		return -1.0
	return clampf(1.0 - heal_left / heal_duration, 0.0, 1.0)

func start_use_item(kind: String) -> bool:
	if dead or state != "ground" or heal_kind != "" or reloading:
		return false
	match kind:
		"bandage":
			if bandages <= 0 or hp >= 75:
				return false
			heal_duration = 2.5
		"firstaid":
			if firstaids <= 0 or hp >= 75:
				return false
			heal_duration = 4.0
		"medkit":
			if medkits <= 0 or hp >= MAX_HP:
				return false
			heal_duration = 6.0
		"drink":
			if drinks <= 0 or boost >= 100.0:
				return false
			heal_duration = 3.0
		"painkiller":
			if painkillers <= 0 or boost >= 100.0:
				return false
			heal_duration = 5.0
		_:
			return false
	heal_kind = kind
	heal_left = heal_duration
	return true

func _complete_heal() -> void:
	match heal_kind:
		"bandage":
			bandages -= 1
			hp = mini(hp + 10, 75)
		"firstaid":
			firstaids -= 1
			hp = maxi(hp, 75)
		"medkit":
			medkits -= 1
			hp = MAX_HP
		"drink":
			drinks -= 1
			boost = minf(boost + 40.0, 100.0)
		"painkiller":
			painkillers -= 1
			boost = minf(boost + 60.0, 100.0)
	heal_kind = ""
	heal_left = 0.0
	_play_sfx("heal", -6.0)
	_sync()

# --- Loot ---

func apply_loot(item: Node) -> int:
	var type: String = String(item.get("loot_type"))
	var amount: int = int(item.get("amount"))
	if Weapons.DATA.has(type):
		var free_slot: int = -1
		for i in slots.size():
			if String(slots[i]) == "":
				free_slot = i
				break
		if free_slot == -1:
			return 0
		slots[free_slot] = type
		slot_mags[free_slot] = 0
		current_slot = free_slot
		_build_gun(type)
		_auto_load()
		last_loot_message = "%s を拾った" % Weapons.display_name(type)
		_sync()
		return 1
	if type.begins_with("ammo_"):
		var kind: String = type.trim_prefix("ammo_")
		reserve[kind] = mini(int(reserve.get(kind, 0)) + amount, 999)
		last_loot_message = "%s +%d" % [Weapons.AMMO_NAMES.get(kind, kind), amount]
		_sync()
		return 1
	if type.begins_with("helmet"):
		var lv: int = int(type.trim_prefix("helmet"))
		if lv > helmet_lv:
			helmet_lv = lv
			last_loot_message = "ヘルメット Lv%d を装備" % lv
			_sync()
			return 1
		return 0
	if type.begins_with("vest"):
		var lv2: int = int(type.trim_prefix("vest"))
		if lv2 > vest_lv:
			vest_lv = lv2
			last_loot_message = "ベスト Lv%d を装備" % lv2
			_sync()
			return 1
		return 0
	match type:
		"bandage": bandages += 1
		"firstaid": firstaids += 1
		"medkit": medkits += 1
		"drink": drinks += 1
		"painkiller": painkillers += 1
		_: return 0
	last_loot_message = "%s を拾った" % String(item.call("display_name"))
	_sync()
	return 1

func swap_with_loot(item: Node) -> void:
	var new_id: String = String(item.get("loot_type"))
	if not Weapons.DATA.has(new_id):
		return
	var old_id: String = current_weapon_id()
	var main: Node = get_tree().get_first_node_in_group("main")
	if old_id != "":
		var old_data: Dictionary = Weapons.DATA[old_id]
		var kind: String = String(old_data["ammo"])
		reserve[kind] = mini(int(reserve.get(kind, 0)) + int(slot_mags[current_slot]), 999)
		if main != null:
			main.call("spawn_loot", old_id, global_position + Vector3(0, 0.1, 0) - global_transform.basis.z * 1.2, 0)
	slots[current_slot] = new_id
	slot_mags[current_slot] = 0
	item.queue_free()
	_build_gun(new_id)
	_auto_load()
	last_loot_message = "%s に持ち替えた" % Weapons.display_name(new_id)
	_sync()

func _auto_load() -> void:
	var data: Dictionary = current_data()
	if data.is_empty():
		return
	var kind: String = String(data["ammo"])
	var have: int = int(reserve.get(kind, 0))
	if int(slot_mags[current_slot]) == 0 and have > 0:
		var load_n: int = mini(int(data["mag"]), have)
		slot_mags[current_slot] = load_n
		reserve[kind] = have - load_n

# --- Input actions used by HUD buttons ---

func toggle_crouch() -> void:
	crouching = not crouching
	var shape: CapsuleShape3D = capsule.shape as CapsuleShape3D
	shape.height = 1.15 if crouching else 1.7
	capsule.position.y = shape.height * 0.5
	model_root.scale.y = model_base_scale * (0.72 if crouching else 1.0)
	spring.position.y = 1.02 if crouching else 1.55
	gun_root.position.y = 0.95 if crouching else 1.28

func toggle_first_person() -> void:
	first_person = not first_person
	model_root.visible = not first_person

func switch_slot(idx: int) -> void:
	if idx < 0 or idx >= slots.size() or idx == current_slot:
		return
	if String(slots[idx]) == "":
		return
	current_slot = idx
	reloading = false
	heal_kind = ""
	_build_gun(current_weapon_id())
	_sync()

# --- Gun model ---

func _build_gun(weapon_id: String) -> void:
	for child: Node in gun_root.get_children():
		if child != muzzle:
			child.queue_free()
	gun_root.visible = weapon_id != ""
	if weapon_id == "":
		return
	var data: Dictionary = Weapons.DATA[weapon_id]
	var len_: float = float(data["len"])
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.13, 0.13, 0.15)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.35, 0.24, 0.14) if weapon_id in ["kar98", "s686"] else Color(0.2, 0.2, 0.23)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.07, 0.11, len_ * 0.6)
	body.mesh = body_mesh
	body.position = Vector3(0, 0, -len_ * 0.2)
	body.material_override = body_mat
	gun_root.add_child(body)
	var barrel := MeshInstance3D.new()
	var barrel_mesh := CylinderMesh.new()
	barrel_mesh.top_radius = 0.02
	barrel_mesh.bottom_radius = 0.02
	barrel_mesh.height = len_ * 0.5
	barrel.mesh = barrel_mesh
	barrel.rotation_degrees.x = 90
	barrel.position = Vector3(0, 0.02, -len_ * 0.72)
	barrel.material_override = dark
	gun_root.add_child(barrel)
	if weapon_id == "s686":
		var barrel2 := MeshInstance3D.new()
		barrel2.mesh = barrel_mesh
		barrel2.rotation_degrees.x = 90
		barrel2.position = Vector3(0.045, 0.02, -len_ * 0.72)
		barrel2.material_override = dark
		gun_root.add_child(barrel2)
	if weapon_id == "kar98":
		var scope := MeshInstance3D.new()
		var scope_mesh := CylinderMesh.new()
		scope_mesh.top_radius = 0.028
		scope_mesh.bottom_radius = 0.028
		scope_mesh.height = 0.2
		scope.mesh = scope_mesh
		scope.rotation_degrees.x = 90
		scope.position = Vector3(0, 0.1, -0.1)
		scope.material_override = dark
		gun_root.add_child(scope)
	var grip := MeshInstance3D.new()
	var grip_mesh := BoxMesh.new()
	grip_mesh.size = Vector3(0.06, 0.14, 0.07)
	grip.mesh = grip_mesh
	grip.position = Vector3(0, -0.1, 0.05)
	grip.material_override = dark
	gun_root.add_child(grip)
	muzzle.position = Vector3(0, 0.02, -len_ * 1.0)

# --- Main loop ---

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or dead:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		yaw -= mm.relative.x * 0.0026
		pitch = clampf(pitch - mm.relative.y * 0.0026, -1.25, 1.35)
		_apply_camera_rotation()
	if event is InputEventMouseButton and event.pressed:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			var main: Node = get_tree().get_first_node_in_group("main")
			if main != null:
				main.call("request_mouse_capture")
	if event is InputEventKey and event.pressed and not event.echo:
		var k: InputEventKey = event as InputEventKey
		match k.keycode:
			KEY_F:
				if state == "plane":
					var main2: Node = get_tree().get_first_node_in_group("main")
					if main2 != null:
						main2.call("player_eject_requested")
				elif state == "ground":
					var main3: Node = get_tree().get_first_node_in_group("main")
					if main3 != null and main3.get("near_weapon_loot") != null:
						swap_with_loot(main3.get("near_weapon_loot"))
			KEY_R: _start_reload()
			KEY_C: toggle_crouch()
			KEY_V: toggle_first_person()
			KEY_1: switch_slot(0)
			KEY_2: switch_slot(1)
			KEY_4: start_use_item("bandage")
			KEY_5: start_use_item("firstaid")
			KEY_6: start_use_item("medkit")
			KEY_7: start_use_item("drink")
			KEY_8: start_use_item("painkiller")

func add_look_input(relative_px: Vector2) -> void:
	yaw -= relative_px.x * 0.0042
	pitch = clampf(pitch - relative_px.y * 0.0042, -1.25, 1.35)
	_apply_camera_rotation()

func _apply_camera_rotation() -> void:
	rotation.y = yaw
	if spring != null:
		spring.rotation.x = pitch + kick_offset

func _physics_process(delta: float) -> void:
	if dead:
		velocity = Vector3.ZERO
		return
	fire_timer -= delta
	kick_offset = move_toward(kick_offset, 0.0, delta * 0.12)
	if state == "plane":
		velocity = Vector3.ZERO
		return
	if state == "fall":
		fall_time += delta
		velocity.y = maxf(velocity.y - 32.0 * delta, -58.0)
		var fall_input: Vector2 = _move_input()
		var wish: Vector3 = (global_transform.basis * Vector3(fall_input.x, 0, fall_input.y))
		velocity.x = move_toward(velocity.x, wish.x * 14.0 + air_forward.x * 8.0, delta * 12.0)
		velocity.z = move_toward(velocity.z, wish.z * 14.0 + air_forward.z * 8.0, delta * 12.0)
		move_and_slide()
		model_root.rotation.x = -0.45
		if fall_time >= 1.25:
			_open_chute()
		return
	if state == "chute":
		var chute_input: Vector2 = _move_input()
		var wish2: Vector3 = (global_transform.basis * Vector3(chute_input.x, 0, chute_input.y))
		var descend: float = 6.2
		var horiz: Vector3 = wish2 * 3.0
		if chute_input.y < -0.3:
			horiz = wish2 * 8.0
			descend = 7.6
		elif chute_input.length() < 0.1:
			horiz = air_forward * 2.5
		velocity = Vector3(horiz.x, -descend, horiz.z)
		move_and_slide()
		model_root.rotation.x = -0.12 if chute_input.y < -0.3 else 0.0
		if is_on_floor():
			_land()
		return
	# Ground state.
	_handle_ground(delta)

func _move_input() -> Vector2:
	var v: Vector2 = touch_move
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		v.y += 1.0
	return v.limit_length(1.0)

func _handle_ground(delta: float) -> void:
	var main: Node = get_tree().get_first_node_in_group("main")
	# Heal channel.
	if heal_kind != "":
		heal_left -= delta
		if heal_left <= 0.0:
			_complete_heal()
		else:
			_sync()
	# Boost regen.
	if boost > 0.0:
		boost_tick += delta
		if boost_tick >= 0.9:
			boost_tick = 0.0
			boost = maxf(boost - 1.5, 0.0)
			if hp > 0 and hp < MAX_HP:
				hp = mini(hp + 1, MAX_HP)
			_sync()
	# Reload.
	if reloading:
		reload_left -= delta
		if reload_left <= 0.0:
			reloading = false
			var data: Dictionary = current_data()
			if not data.is_empty():
				var kind: String = String(data["ammo"])
				var need: int = int(data["mag"]) - int(slot_mags[current_slot])
				var take: int = mini(need, int(reserve.get(kind, 0)))
				slot_mags[current_slot] = int(slot_mags[current_slot]) + take
				reserve[kind] = int(reserve.get(kind, 0)) - take
			_sync()
	# Aim / lean state.
	var mouse_captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	aiming = (mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)) or touch_aiming
	var lean_target: float = 0.0
	if Input.is_key_pressed(KEY_Q):
		lean_target = -1.0
	elif Input.is_key_pressed(KEY_E):
		lean_target = 1.0
	lean = move_toward(lean, lean_target, delta * 6.0)
	# Movement.
	var input_vec: Vector2 = _move_input() if input_enabled else Vector2.ZERO
	var sprinting: bool = (Input.is_key_pressed(KEY_SHIFT) or touch_move.y < -0.92) and input_vec.y < -0.3 and not aiming and not crouching and heal_kind == ""
	var speed: float = 5.6
	if sprinting:
		speed = 7.8
	elif crouching:
		speed = 2.6
	if aiming:
		speed *= 0.55
	if heal_kind != "":
		speed *= 0.35
	speed *= 1.0 + boost * 0.0008
	var dir3: Vector3 = (global_transform.basis * Vector3(input_vec.x, 0, input_vec.y))
	if dir3.length() > 1.0:
		dir3 = dir3.normalized()
	velocity.x = dir3.x * speed
	velocity.z = dir3.z * speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.5
		if input_enabled and (Input.is_key_pressed(KEY_SPACE) or touch_jump):
			velocity.y = 5.4
			touch_jump = false
	move_and_slide()
	# Model facing + walk animation.
	var moving: bool = Vector2(velocity.x, velocity.z).length() > 0.4
	model_root.rotation.z = -lean * 0.22
	ModelUtil.set_locomotion(anim, moving, Vector2(velocity.x, velocity.z).length() / 7.8)
	# RMB-drag fallback look (when pointer is not captured).
	if input_enabled and not mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		pass
	# Shooting.
	_handle_shooting(delta, mouse_captured)
	# Camera follow-through.
	_update_camera(delta)
	_apply_camera_rotation()
	if main != null:
		pass

func _handle_shooting(_delta: float, mouse_captured: bool) -> void:
	var data: Dictionary = current_data()
	var fire_held: bool = (mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) or touch_firing
	var want_fire: bool = false
	if not data.is_empty() and input_enabled and heal_kind == "":
		if bool(data["auto"]):
			want_fire = fire_held
		else:
			want_fire = fire_held and not _prev_fire_held
	_prev_fire_held = fire_held
	if not want_fire or reloading or fire_timer > 0.0:
		return
	if int(slot_mags[current_slot]) <= 0:
		fire_timer = 0.3
		_start_reload()
		return
	slot_mags[current_slot] = int(slot_mags[current_slot]) - 1
	fire_timer = float(data["interval"])
	var pellets: int = int(data.get("pellets", 1))
	var spread_deg: float = float(data["spread"])
	if aiming:
		spread_deg *= 0.55
	if crouching:
		spread_deg *= 0.8
	var main: Node = get_tree().get_first_node_in_group("main")
	var cam_basis: Basis = camera.global_transform.basis
	for i in pellets:
		var dir: Vector3 = -cam_basis.z
		var ang: float = deg_to_rad(spread_deg)
		dir = dir.rotated(cam_basis.x, randf_range(-ang, ang)).rotated(cam_basis.y, randf_range(-ang, ang)).normalized()
		if main != null:
			main.call("spawn_bullet", self, muzzle.global_position, dir, current_weapon_id())
	kick_offset -= float(data["kick"]) * 0.014
	pitch = clampf(pitch + float(data["kick"]) * 0.002, -1.25, 1.35)
	_play_sfx(String(data["sfx"]), -3.0)
	if main != null:
		main.call("spawn_spark", muzzle.global_position, Color(1.0, 0.75, 0.3))
	_sync()

func _start_reload() -> void:
	var data: Dictionary = current_data()
	if data.is_empty() or reloading or heal_kind != "":
		return
	var kind: String = String(data["ammo"])
	if int(slot_mags[current_slot]) >= int(data["mag"]) or int(reserve.get(kind, 0)) <= 0:
		return
	reloading = true
	reload_left = float(data["reload"])
	_play_sfx("reload", -6.0)
	_sync()

func _update_camera(delta: float) -> void:
	var data: Dictionary = current_data()
	var target_len: float = 4.4
	var target_fov: float = 70.0
	if first_person:
		target_len = 0.0
	elif aiming and not data.is_empty():
		target_len = 2.0
		target_fov = float(data["ads_fov"])
	if state == "chute" or state == "fall":
		target_len = 7.0
	spring.spring_length = lerpf(spring.spring_length, target_len, clampf(delta * 10.0, 0.0, 1.0))
	camera.fov = lerpf(camera.fov, target_fov, clampf(delta * 10.0, 0.0, 1.0))
	spring.position.x = 0.55 + lean * 0.5
	gun_root.position.x = 0.34 + lean * 0.3

func _play_sfx(sound_name: String, volume_db: float) -> void:
	var sfx: Node = get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", sound_name, volume_db)

func _sync() -> void:
	var main: Node = get_tree().get_first_node_in_group("main")
	if main != null:
		main.call("sync_hud")

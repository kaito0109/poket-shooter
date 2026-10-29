extends CharacterBody3D
## Bot: parachutes in, loots weapons/items, roams, fights any actor
## (player or other bots), heals, and plays the zone — like a PUBG player.

const ModelUtil := preload("res://model_util.gd")
const MAX_HP: int = 100

var display_name: String = "BOT"
var bot_name: String:
	get: return display_name
	set(v): display_name = v
var hp: int = MAX_HP
var max_hp: int = MAX_HP
var dead: bool = false
var active: bool = false
var state: String = "chute"  # chute | loot | roam | combat | heal
var last_hit_by_player: bool = false

var anim_player: AnimationPlayer
var model_root: Node3D
var gun_root: Node3D
var muzzle: Marker3D
var canopy: Node3D
var capsule: CollisionShape3D

var weapon_id: String = ""
var mag_ammo: int = 0
var reserve: Dictionary = {"9mm": 0, "556": 0, "762": 0, "shell": 0}
var reloading: bool = false
var reload_left: float = 0.0
var helmet_lv: int = 0
var vest_lv: int = 0
var heal_items: int = 1

var skill_spread: float = 2.2
var landing_point: Vector3 = Vector3.ZERO
var move_target: Vector3 = Vector3.ZERO
var has_move_target: bool = false
var target_actor: Node3D = null
var last_seen_pos: Vector3 = Vector3.ZERO
var last_seen_time: float = -99.0
var last_damage_time: float = -99.0
var last_attacker: Node3D = null
var think_timer: float = 0.0
var fire_timer: float = 0.0
var burst_left: int = 0
var burst_pause: float = 0.0
var strafe_dir: float = 1.0
var strafe_timer: float = 0.0
var heal_left: float = 0.0
var zone_tick: float = 0.0
var stuck_time: float = 0.0
var last_pos: Vector3 = Vector3.ZERO
var avoid_side: float = 1.0
var roam_wait: float = 0.0
var gear: Dictionary = {}
var time_alive: float = 0.0

func _ready() -> void:
	add_to_group("enemies")
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
	gun_root = Node3D.new()
	gun_root.position = Vector3(0.34, 1.28, -0.25)
	add_child(gun_root)
	muzzle = Marker3D.new()
	gun_root.add_child(muzzle)
	_rebuild_gun()

func is_grounded() -> bool:
	return state != "chute"

func configure(p_name: String, tint: Color) -> void:
	display_name = p_name
	skill_spread = randf_range(1.7, 2.9)
	var attached: Dictionary = ModelUtil.attach_character(self, "res://assets/player.glb", randf_range(1.7, 1.8), tint)
	model_root = attached.get("model")
	anim_player = attached.get("anim_player")
	if model_root != null:
		gear = ModelUtil.build_gear(model_root)

func start_chute(at_pos: Vector3, landing: Vector3) -> void:
	visible = true
	global_position = at_pos
	landing_point = landing
	state = "chute"
	active = true
	canopy = Node3D.new()
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.7
	sphere.height = 1.6
	dome.mesh = sphere
	dome.scale = Vector3(1.15, 0.42, 1.15)
	dome.position.y = 3.6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.9, 0.92)
	dome.material_override = mat
	canopy.add_child(dome)
	add_child(canopy)

func _rebuild_gun() -> void:
	for child: Node in gun_root.get_children():
		if child != muzzle:
			child.queue_free()
	gun_root.visible = weapon_id != ""
	if weapon_id == "":
		return
	var data: Dictionary = Weapons.DATA[weapon_id]
	var len_: float = float(data["len"])
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.07, 0.11, len_ * 0.75)
	body.mesh = body_mesh
	body.position = Vector3(0, 0, -len_ * 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.18)
	body.material_override = mat
	gun_root.add_child(body)
	muzzle.position = Vector3(0, 0.02, -len_ * 1.05)

func take_damage(amount: float, from_node: Node3D = null, hit_pos: Vector3 = Vector3.ZERO, is_zone: bool = false) -> void:
	if dead:
		return
	var final_amount: float = amount
	if not is_zone:
		var rel_y: float = hit_pos.y - global_position.y
		if rel_y > 1.43:
			var helmet_red: Array = [0.0, 0.3, 0.4, 0.55]
			final_amount = amount * 2.0 * (1.0 - float(helmet_red[helmet_lv]))
		else:
			var vest_red: Array = [0.0, 0.2, 0.3, 0.4]
			final_amount = amount * (1.0 - float(vest_red[vest_lv]))
	hp = maxi(hp - int(round(final_amount)), 0)
	last_damage_time = time_alive
	if from_node != null:
		last_attacker = from_node
		last_hit_by_player = from_node.is_in_group("player")
		if global_position.distance_to(from_node.global_position) < 150.0:
			target_actor = from_node
			last_seen_pos = from_node.global_position
			last_seen_time = time_alive
	if state == "heal":
		state = "roam"
		heal_left = 0.0
	if hp <= 0 and not dead:
		dead = true
		active = false
		var main: Node = get_tree().get_first_node_in_group("main")
		if main != null:
			main.call("on_actor_killed", self, last_attacker)
		var tween := create_tween()
		tween.tween_property(model_root, "rotation:x", -PI * 0.5, 0.6)

func apply_loot(item: Node) -> int:
	var type: String = String(item.get("loot_type"))
	var amount: int = int(item.get("amount"))
	if Weapons.DATA.has(type):
		if weapon_id == "":
			_take_weapon(type)
			return 1
		if Weapons.power(type) > Weapons.power(weapon_id):
			var main: Node = get_tree().get_first_node_in_group("main")
			if main != null:
				main.call("spawn_loot", weapon_id, global_position + Vector3(0, 0.1, 0), 0)
			_take_weapon(type)
			return 1
		return 0
	if type.begins_with("ammo_"):
		var kind: String = type.trim_prefix("ammo_")
		reserve[kind] = mini(int(reserve.get(kind, 0)) + amount, 300)
		_maybe_reload()
		return 1
	if type.begins_with("helmet"):
		var lv: int = int(type.trim_prefix("helmet"))
		if lv > helmet_lv:
			helmet_lv = lv
			return 1
		return 0
	if type.begins_with("vest"):
		var lv2: int = int(type.trim_prefix("vest"))
		if lv2 > vest_lv:
			vest_lv = lv2
			return 1
		return 0
	match type:
		"bandage", "firstaid", "drink", "painkiller":
			if heal_items < 5:
				heal_items += 1
				return 1
			return 0
		"medkit":
			if heal_items < 5:
				heal_items += 2
				return 1
			return 0
	return 0

func _take_weapon(type: String) -> void:
	weapon_id = type
	mag_ammo = 0
	reloading = false
	_rebuild_gun()
	_maybe_reload()

func _weapon_data() -> Dictionary:
	if weapon_id == "":
		return {}
	return Weapons.DATA[weapon_id]

func _maybe_reload() -> void:
	var data: Dictionary = _weapon_data()
	if data.is_empty() or reloading:
		return
	var kind: String = String(data["ammo"])
	if mag_ammo < int(data["mag"]) and int(reserve.get(kind, 0)) > 0:
		reloading = true
		reload_left = float(data["reload"]) * 1.25

func _finish_reload() -> void:
	reloading = false
	var data: Dictionary = _weapon_data()
	if data.is_empty():
		return
	var kind: String = String(data["ammo"])
	var take: int = mini(int(data["mag"]) - mag_ammo, int(reserve.get(kind, 0)))
	mag_ammo += take
	reserve[kind] = int(reserve.get(kind, 0)) - take

func _pref_range() -> float:
	match weapon_id:
		"kar98": return 68.0
		"m416": return 36.0
		"uzi": return 15.0
		"s686": return 8.5
		"p92": return 13.0
	return 0.0

func _max_engage() -> float:
	match weapon_id:
		"kar98": return 160.0
		"m416": return 115.0
		"uzi": return 48.0
		"s686": return 17.0
		"p92": return 42.0
	return 0.0

func _physics_process(delta: float) -> void:
	if dead or not active:
		return
	time_alive += delta
	if state == "chute":
		var to_land: Vector3 = landing_point - global_position
		var horiz := Vector3(to_land.x, 0, to_land.z)
		var dir: Vector3 = horiz.normalized() if horiz.length() > 1.0 else Vector3.ZERO
		velocity = Vector3(dir.x * 6.5, -7.2, dir.z * 6.5)
		if horiz.length() > 1.0:
			_face_toward(global_position + dir, delta, 6.0)
		move_and_slide()
		if is_on_floor():
			state = "loot"
			if canopy != null:
				canopy.queue_free()
				canopy = null
		return
	# Ground behavior.
	think_timer -= delta
	if think_timer <= 0.0:
		think_timer = 0.22
		_think()
		ModelUtil.set_gear(gear, helmet_lv, vest_lv, weapon_id != "" or heal_items > 1)
	if reloading:
		reload_left -= delta
		if reload_left <= 0.0:
			_finish_reload()
	fire_timer -= delta
	_act(delta)
	# Stuck detection.
	if has_move_target and state != "heal":
		if global_position.distance_to(last_pos) < 0.25:
			stuck_time += delta
		else:
			stuck_time = 0.0
			last_pos = global_position
		if stuck_time > 1.1:
			avoid_side = -avoid_side
			stuck_time = 0.0
	ModelUtil.set_locomotion(anim_player, Vector2(velocity.x, velocity.z).length() > 0.4, Vector2(velocity.x, velocity.z).length() / 6.8)

func _think() -> void:
	# Perception: nearest visible actor (player or bot) on the ground.
	var eye: Vector3 = global_position + Vector3(0, 1.5, 0)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var best: Node3D = null
	var best_dist: float = 120.0
	for node: Node in get_tree().get_nodes_in_group("actors"):
		if node == self:
			continue
		var actor: Node3D = node as Node3D
		if actor == null or bool(actor.get("dead")):
			continue
		if not bool(actor.call("is_grounded")):
			continue
		var d: float = global_position.distance_to(actor.global_position)
		if d > best_dist:
			continue
		var query := PhysicsRayQueryParameters3D.create(eye, actor.global_position + Vector3(0, 1.25, 0), 1)
		if space.intersect_ray(query).is_empty():
			best = actor
			best_dist = d
	if best != null:
		target_actor = best
		last_seen_pos = best.global_position
		last_seen_time = time_alive
	elif time_alive - last_seen_time > 3.5:
		target_actor = null
	# Zone awareness.
	var zone: Node = get_tree().get_first_node_in_group("zone")
	var outside: bool = zone != null and bool(zone.call("is_outside", global_position))
	# State selection.
	if state == "heal":
		return
	if hp <= 45 and heal_items > 0 and target_actor == null and time_alive - last_damage_time > 3.0:
		state = "heal"
		heal_left = 3.5
		return
	if target_actor != null and weapon_id != "":
		state = "combat"
		return
	if target_actor != null and weapon_id == "":
		state = "roam"  # unarmed: keep away, go loot
		move_target = _pick_loot_or_zone_point()
		has_move_target = true
		return
	if outside:
		state = "roam"
		move_target = _point_inside_zone()
		has_move_target = true
		return
	if weapon_id == "" or (mag_ammo == 0 and int(reserve.get(String(_weapon_data().get("ammo", "")), 0)) == 0 and weapon_id != ""):
		state = "loot"
		var loot_pos: Variant = _nearest_wanted_loot()
		if loot_pos != null:
			move_target = loot_pos
			has_move_target = true
		else:
			state = "roam"
			_pick_roam()
		return
	state = "roam"
	if not has_move_target or global_position.distance_to(move_target) < 4.0:
		_pick_roam()

func _pick_roam() -> void:
	roam_wait -= 0.22
	var zone: Node = get_tree().get_first_node_in_group("zone")
	if zone != null and bool(zone.get("running")):
		move_target = _point_inside_zone()
	else:
		move_target = Vector3(randf_range(-140, 140), 0, randf_range(-140, 140))
	move_target.y = global_position.y
	has_move_target = true

func _point_inside_zone() -> Vector3:
	var zone: Node = get_tree().get_first_node_in_group("zone")
	if zone == null:
		return Vector3.ZERO
	var c: Vector2 = zone.get("center")
	var r: float = float(zone.get("radius")) * 0.62
	var p := Vector2(randf_range(-r, r), randf_range(-r, r))
	return Vector3(c.x + p.x, global_position.y, c.y + p.y)

func _pick_loot_or_zone_point() -> Vector3:
	var loot_pos: Variant = _nearest_wanted_loot()
	if loot_pos != null:
		return loot_pos
	return _point_inside_zone()

func _nearest_wanted_loot() -> Variant:
	var best: Node3D = null
	var best_dist: float = 170.0
	for node: Node in get_tree().get_nodes_in_group("loot"):
		var item: Node3D = node as Node3D
		if item == null:
			continue
		var type: String = String(item.get("loot_type"))
		if not _wants(type):
			continue
		var d: float = global_position.distance_to(item.global_position)
		if d < best_dist:
			best_dist = d
			best = item
	if best == null:
		return null
	return best.global_position

func _wants(type: String) -> bool:
	if Weapons.DATA.has(type):
		return weapon_id == "" or Weapons.power(type) > Weapons.power(weapon_id)
	if type.begins_with("ammo_"):
		if weapon_id == "":
			return false
		return String(_weapon_data().get("ammo", "")) == type.trim_prefix("ammo_")
	if type.begins_with("helmet"):
		return int(type.trim_prefix("helmet")) > helmet_lv
	if type.begins_with("vest"):
		return int(type.trim_prefix("vest")) > vest_lv
	return heal_items < 3

func _act(delta: float) -> void:
	var speed: float = 0.0
	var desired := Vector3.ZERO
	match state:
		"heal":
			heal_left -= delta
			velocity.x = 0.0
			velocity.z = 0.0
			if heal_left <= 0.0:
				heal_items -= 1
				hp = mini(hp + 40, MAX_HP)
				state = "roam"
				has_move_target = false
		"combat":
			if target_actor == null or not is_instance_valid(target_actor) or bool(target_actor.get("dead")):
				state = "roam"
				has_move_target = false
				return
			var tp: Vector3 = target_actor.global_position
			var dist: float = global_position.distance_to(tp)
			_face_toward(tp, delta, 10.0)
			var pref: float = _pref_range()
			var to_target: Vector3 = (tp - global_position)
			to_target.y = 0
			to_target = to_target.normalized()
			strafe_timer -= delta
			if strafe_timer <= 0.0:
				strafe_timer = randf_range(1.4, 2.6)
				strafe_dir = -strafe_dir if randf() < 0.6 else strafe_dir
			if dist > pref * 1.3:
				desired = to_target
				speed = 5.0
			elif dist < pref * 0.55:
				desired = -to_target
				speed = 4.2
			else:
				desired = Vector3(-to_target.z, 0, to_target.x) * strafe_dir
				speed = 3.4
			_try_shoot(dist)
		"loot", "roam":
			if has_move_target:
				var to: Vector3 = move_target - global_position
				to.y = 0
				if to.length() > 1.6:
					desired = to.normalized()
					speed = 6.6 if _outside_zone() else 5.3
					_face_toward(global_position + desired, delta, 8.0)
				else:
					has_move_target = false
	if desired != Vector3.ZERO:
		desired = _avoid(desired)
		velocity.x = desired.x * speed
		velocity.z = desired.z * speed
	else:
		if state != "combat":
			velocity.x = 0.0
			velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()

func _outside_zone() -> bool:
	var zone: Node = get_tree().get_first_node_in_group("zone")
	return zone != null and bool(zone.call("is_outside", global_position))

func _avoid(dir: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * 2.4, 1)
	if not space.intersect_ray(query).is_empty():
		var rotated: Vector3 = dir.rotated(Vector3.UP, avoid_side * 0.9)
		return rotated.normalized()
	return dir

func _face_toward(world_pos: Vector3, delta: float, rate: float) -> void:
	var to: Vector3 = world_pos - global_position
	if to.length() < 0.1:
		return
	var target_yaw: float = atan2(-to.x, -to.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * rate, 0.0, 1.0))

func _try_shoot(dist: float) -> void:
	if weapon_id == "" or reloading or target_actor == null:
		return
	if dist > _max_engage():
		return
	if burst_pause > 0.0:
		burst_pause -= get_physics_process_delta_time()
		return
	if fire_timer > 0.0:
		return
	# LOS right now?
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var eye: Vector3 = global_position + Vector3(0, 1.5, 0)
	var chest: Vector3 = target_actor.global_position + Vector3(0, 1.25, 0)
	if not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, chest, 1)).is_empty():
		return
	if mag_ammo <= 0:
		_maybe_reload()
		return
	var data: Dictionary = _weapon_data()
	mag_ammo -= 1
	fire_timer = float(data["interval"]) * 1.15
	var pellets: int = int(data.get("pellets", 1))
	var main: Node = get_tree().get_first_node_in_group("main")
	var spread_ang: float = deg_to_rad(float(data["spread"]) * skill_spread * (1.0 + dist / 110.0))
	for i in pellets:
		var dir: Vector3 = (chest - muzzle.global_position).normalized()
		dir = dir.rotated(Vector3.UP, randf_range(-spread_ang, spread_ang))
		var right: Vector3 = dir.cross(Vector3.UP).normalized()
		if right.length() > 0.01:
			dir = dir.rotated(right, randf_range(-spread_ang, spread_ang)).normalized()
		if main != null:
			main.call("spawn_bullet", self, muzzle.global_position, dir, weapon_id)
	var sfx: Node = get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		var player_node: Node = get_tree().get_first_node_in_group("player")
		var pd: float = 200.0
		if player_node != null:
			pd = global_position.distance_to((player_node as Node3D).global_position)
		var vol: float = clampf(-2.0 - pd * 0.13, -30.0, -2.0)
		sfx.call("play", String(data["sfx"]), vol, randf_range(0.94, 1.05))
	burst_left -= 1
	if burst_left <= 0:
		if bool(data["auto"]):
			burst_left = randi_range(3, 7)
		elif weapon_id == "kar98":
			burst_left = 1
		else:
			burst_left = randi_range(1, 3)
		burst_pause = randf_range(0.7, 1.5) * (skill_spread / 2.2)

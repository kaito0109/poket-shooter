extends Node3D
## Pocket TPS (PUBG-style): terrain island, compounds, plane drop, loot,
## zone, bot ecosystem, kill feed and match flow.

const PlayerScript := preload("res://player.gd")
const EnemyScript := preload("res://enemy.gd")
const HudScript := preload("res://hud.gd")
const TracerScript := preload("res://tracer.gd")
const ZoneScript := preload("res://zone.gd")
const SfxScript := preload("res://sfx.gd")
const LootScript := preload("res://loot.gd")
const BulletScript := preload("res://bullet.gd")
const GrenadeScript := preload("res://grenade.gd")

const BOT_COUNT: int = 24
const WORLD_HALF: float = 240.0
const TERRAIN_HALF: float = 340.0
const PLANE_Y: float = 112.0

const BOT_NAMES: Array = [
	"Takeshi", "momo_22", "GhostJP", "yuki_san", "PANDA-X", "kuro", "Hina", "DORA",
	"shun_7", "Mika", "ZERO", "bobu", "Akira", "nana", "GON", "sora",
	"Rin", "tetsu", "YUMA", "pico", "KAZE", "mochi", "JIRO", "hana",
]
const BOT_TINTS: Array[Color] = [
	Color(0.9, 0.85, 0.8), Color(0.8, 0.6, 0.55), Color(0.6, 0.7, 0.9), Color(0.7, 0.85, 0.6),
	Color(0.95, 0.75, 0.6), Color(0.65, 0.6, 0.8), Color(0.85, 0.7, 0.85), Color(0.55, 0.75, 0.75),
]

var game_font: Font
var player: CharacterBody3D
var hud
var zone
var sfx: Node
var started: bool = false
var is_game_over: bool = false
var kills: int = 0
var bots_alive: int = 0
var panel_mode: String = "start"
var near_weapon_loot: Node = null

var noise := FastNoiseLite.new()
var compounds: Array = []  # {name, center: Vector2, height: float, radius: float}
var building_rects: Array = []
var rng := RandomNumberGenerator.new()

var plane: Node3D
var plane_active: bool = false
var plane_z: float = 0.0
var bots: Array = []
var bot_eject_x: Dictionary = {}
var bot_landing: Dictionary = {}
var player_ejected: bool = false
var zone_tick_timer: float = 0.0
var loot_poll_timer: float = 0.0

func _ready() -> void:
	add_to_group("main")
	_load_game_font()
	rng.randomize()
	noise.seed = 20261029
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 1.0
	_define_compounds()
	_build_environment()
	_build_terrain()
	_build_compounds()
	_scatter_nature()

	zone = ZoneScript.new()
	add_child(zone)
	var zone_center := Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
	zone.call("configure", 330.0, [
		[50.0, 35.0, 0.55, 1], [40.0, 30.0, 0.55, 2], [35.0, 25.0, 0.5, 4],
		[30.0, 20.0, 0.45, 7], [25.0, 15.0, 0.4, 10], [20.0, 12.0, 0.35, 14],
	], zone_center)
	zone.phase_changed.connect(_on_zone_phase_changed)

	sfx = SfxScript.new()
	add_child(sfx)

	player = PlayerScript.new()
	player.position = Vector3(0, -300, 0)
	player.visible = false
	add_child(player)
	(player.get("camera") as Camera3D).far = 1500.0

	_spawn_bots()
	_spawn_all_loot()
	_build_plane()

	hud = HudScript.new()
	add_child(hud)
	hud.bind(self, player)
	hud.set_minimap_buildings(building_rects)
	hud.set_minimap_radius(245.0)
	sync_hud()
	hud.show_panel("POCKET TPS",
		"飛行機から降下して、武器を拾って、最後の1人まで生き残れ！\n降下: Fキー（飛行中）　武器: 歩いて拾う / Fで持ち替え\n射撃: クリック　狙う: 右クリック　しゃがみ: C　リーン: Q/E\n回復: 4 包帯 / 5 応急 / 6 医療 / 7 ドリンク　マップ: M\nゾーン（青い壁）の外はダメージ。敵も武器を拾って戦うぞ。",
		"スタート")

func _load_game_font() -> void:
	if ResourceLoader.exists("res://assets/jpfont.ttf"):
		game_font = load("res://assets/jpfont.ttf") as Font
	if game_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", "Yu Gothic UI", "Yu Gothic", "Meiryo", "sans-serif"])
		game_font = sf

# --- World gen ---

func _raw_height(x: float, z: float) -> float:
	return noise.get_noise_2d(x * 0.011, z * 0.011) * 3.4 + noise.get_noise_2d(x * 0.05 + 100.0, z * 0.05 + 100.0) * 0.5

func ground_height(x: float, z: float) -> float:
	var h: float = _raw_height(x, z)
	var p := Vector2(x, z)
	for c: Dictionary in compounds:
		var center: Vector2 = c["center"]
		var radius: float = c["radius"]
		var d: float = p.distance_to(center)
		if d < radius:
			var t: float = clampf(1.0 - d / radius, 0.0, 1.0)
			var f: float = t * t * (3.0 - 2.0 * t)
			h = lerpf(h, float(c["height"]), f)
	return h

func _define_compounds() -> void:
	var defs: Array = [
		["学校", Vector2(0, -40)], ["港町", Vector2(-60, 170)], ["農場", Vector2(-170, -60)],
		["住宅地", Vector2(150, 60)], ["倉庫", Vector2(90, -180)],
	]
	for d: Array in defs:
		var center: Vector2 = d[1]
		compounds.append({
			"name": d[0], "center": center,
			"height": _raw_height(center.x, center.y), "radius": 42.0,
		})

func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.75)
	sky_mat.sky_horizon_color = Color(0.78, 0.83, 0.9)
	sky_mat.ground_bottom_color = Color(0.2, 0.24, 0.2)
	sky_mat.ground_horizon_color = Color(0.78, 0.83, 0.9)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.82, 0.92)
	env.fog_density = 0.0016
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, -38, 0)
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 320.0
	add_child(sun)

func _build_terrain() -> void:
	var cell: float = 4.0
	var n: int = int(TERRAIN_HALF * 2.0 / cell)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var color_noise := FastNoiseLite.new()
	color_noise.seed = 777
	for gz in n:
		for gx in n:
			var x0: float = -TERRAIN_HALF + gx * cell
			var z0: float = -TERRAIN_HALF + gz * cell
			var corners: Array = [
				Vector3(x0, ground_height(x0, z0), z0),
				Vector3(x0 + cell, ground_height(x0 + cell, z0), z0),
				Vector3(x0 + cell, ground_height(x0 + cell, z0 + cell), z0 + cell),
				Vector3(x0, ground_height(x0, z0 + cell), z0 + cell),
			]
			for idx: int in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = corners[idx]
				var cn: float = color_noise.get_noise_2d(v.x * 0.03, v.z * 0.03)
				var col := Color(0.32, 0.48, 0.26).lerp(Color(0.45, 0.52, 0.3), clampf(cn * 0.5 + 0.5, 0.0, 1.0))
				st.set_color(col)
				st.add_vertex(v)
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mesh.surface_set_material(0, mat)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	body.add_child(mi)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh.get_faces())
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)

func _static_box(parent: Node, pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var mesh_inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mesh_inst.material_override = mat
	body.add_child(mesh_inst)
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)

func _build_house(center: Vector2, size: Vector2, wall_color: Color, door_side: int) -> Vector3:
	var ground_y: float = ground_height(center.x, center.y)
	var house := Node3D.new()
	house.position = Vector3(center.x, ground_y, center.y)
	add_child(house)
	var w: float = size.x
	var d: float = size.y
	var h: float = 3.0
	var t: float = 0.25
	_static_box(house, Vector3(0, 0.08, 0), Vector3(w + 0.5, 0.16, d + 0.5), Color(0.5, 0.48, 0.45))
	# Walls: 0=N(-z) 1=S(+z) 2=W(-x) 3=E(+x); door gap 1.7 wide at center of door_side.
	for side in 4:
		var horiz: bool = side < 2
		var wall_len: float = w if horiz else d
		var fixed: float = (-d * 0.5 if side == 0 else (d * 0.5 if side == 1 else (-w * 0.5 if side == 2 else w * 0.5)))
		if side == door_side:
			var seg_len: float = (wall_len - 1.7) * 0.5
			for sgn: float in [-1.0, 1.0]:
				var off: float = sgn * (1.7 * 0.5 + seg_len * 0.5)
				var pos := Vector3(off, h * 0.5, fixed) if horiz else Vector3(fixed, h * 0.5, off)
				var sz := Vector3(seg_len, h, t) if horiz else Vector3(t, h, seg_len)
				_static_box(house, pos, sz, wall_color)
			# Lintel above the door.
			var lpos := Vector3(0, h - 0.35, fixed) if horiz else Vector3(fixed, h - 0.35, 0)
			var lsz := Vector3(1.7, 0.7, t) if horiz else Vector3(t, 0.7, 1.7)
			_static_box(house, lpos, lsz, wall_color)
		else:
			var pos2 := Vector3(0, h * 0.5, fixed) if horiz else Vector3(fixed, h * 0.5, 0)
			var sz2 := Vector3(wall_len, h, t) if horiz else Vector3(t, h, wall_len)
			_static_box(house, pos2, sz2, wall_color)
	_static_box(house, Vector3(0, h + 0.12, 0), Vector3(w + 0.8, 0.22, d + 0.8), Color(0.32, 0.3, 0.3))
	building_rects.append(Rect2(center.x - w * 0.5, center.y - d * 0.5, w, d))
	return house.position

func _build_compounds() -> void:
	var layouts: Dictionary = {
		"学校": [[Vector2(-14, -10), Vector2(12, 9)], [Vector2(12, -12), Vector2(10, 8)], [Vector2(-2, 12), Vector2(14, 10)], [Vector2(18, 10), Vector2(9, 8)], [Vector2(-20, 12), Vector2(9, 7)]],
		"港町": [[Vector2(-16, -6), Vector2(11, 8)], [Vector2(8, -14), Vector2(10, 9)], [Vector2(16, 8), Vector2(12, 8)], [Vector2(-10, 14), Vector2(9, 8)], [Vector2(-24, 10), Vector2(8, 7)]],
		"農場": [[Vector2(-12, -8), Vector2(12, 8)], [Vector2(14, -4), Vector2(10, 8)], [Vector2(0, 14), Vector2(11, 9)], [Vector2(-18, 12), Vector2(9, 7)]],
		"住宅地": [[Vector2(-14, -12), Vector2(10, 8)], [Vector2(10, -10), Vector2(11, 9)], [Vector2(-6, 10), Vector2(12, 8)], [Vector2(16, 12), Vector2(9, 8)], [Vector2(-22, 6), Vector2(8, 7)]],
		"倉庫": [[Vector2(-12, -10), Vector2(14, 10)], [Vector2(14, -8), Vector2(12, 9)], [Vector2(-4, 12), Vector2(12, 8)], [Vector2(18, 10), Vector2(10, 8)]],
	}
	var palette: Array[Color] = [Color(0.68, 0.64, 0.58), Color(0.6, 0.66, 0.7), Color(0.7, 0.66, 0.55), Color(0.62, 0.68, 0.6), Color(0.66, 0.6, 0.64)]
	for ci: int in compounds.size():
		var c: Dictionary = compounds[ci]
		var center: Vector2 = c["center"]
		var houses: Array = layouts[c["name"]]
		c["house_positions"] = []
		for hi: int in houses.size():
			var off: Vector2 = houses[hi][0]
			var sz: Vector2 = houses[hi][1]
			var pos: Vector3 = _build_house(center + off, sz, palette[(ci + hi) % palette.size()], hi % 4)
			(c["house_positions"] as Array).append(pos)
			# A crate or two beside each house.
			if hi % 2 == 0:
				var cx: float = center.x + off.x + sz.x * 0.5 + 1.6
				var cz: float = center.y + off.y
				_static_box(self, Vector3(cx, ground_height(cx, cz) + 0.6, cz), Vector3(1.2, 1.2, 1.2), Color(0.55, 0.42, 0.28))
	# Scattered lone houses.
	var lone: Array = [
		[Vector2(-120, 60), Vector2(10, 8)], [Vector2(60, 120), Vector2(11, 8)],
		[Vector2(190, -80), Vector2(10, 9)], [Vector2(-60, -150), Vector2(11, 8)],
		[Vector2(-190, 130), Vector2(9, 8)], [Vector2(30, -90), Vector2(10, 7)],
	]
	for li: int in lone.size():
		_build_house(lone[li][0], lone[li][1], palette[li % palette.size()], li % 4)

func _scatter_nature() -> void:
	for i in 130:
		var x: float = rng.randf_range(-WORLD_HALF + 8, WORLD_HALF - 8)
		var z: float = rng.randf_range(-WORLD_HALF + 8, WORLD_HALF - 8)
		if _near_compound(Vector2(x, z), 30.0):
			continue
		_make_tree(Vector3(x, ground_height(x, z), z))
	for i in 36:
		var x2: float = rng.randf_range(-WORLD_HALF + 8, WORLD_HALF - 8)
		var z2: float = rng.randf_range(-WORLD_HALF + 8, WORLD_HALF - 8)
		if _near_compound(Vector2(x2, z2), 26.0):
			continue
		_make_rock(Vector3(x2, ground_height(x2, z2), z2))

func _near_compound(p: Vector2, dist: float) -> bool:
	for c: Dictionary in compounds:
		if p.distance_to(c["center"]) < dist:
			return true
	return false

func _make_tree(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var trunk := MeshInstance3D.new()
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.16
	trunk_mesh.bottom_radius = 0.26
	trunk_mesh.height = 2.4
	trunk.mesh = trunk_mesh
	trunk.position.y = 1.2
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.4, 0.29, 0.18)
	trunk.material_override = trunk_mat
	body.add_child(trunk)
	var shape_node := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.32
	shape.height = 2.4
	shape_node.shape = shape
	shape_node.position.y = 1.2
	body.add_child(shape_node)
	var foliage := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = rng.randf_range(1.3, 2.0)
	sphere.height = sphere.radius * 2.0
	foliage.mesh = sphere
	foliage.position.y = 2.4 + sphere.radius * 0.8
	var leaf_mat := StandardMaterial3D.new()
	leaf_mat.albedo_color = Color(0.22, 0.43, 0.2)
	foliage.material_override = leaf_mat
	body.add_child(foliage)
	add_child(body)

func _make_rock(pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var rm := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	var rr: float = rng.randf_range(0.9, 1.7)
	sphere.radius = rr
	sphere.height = rr * 2.0
	rm.mesh = sphere
	rm.scale = Vector3(1.3, 0.75, 1.1)
	rm.position.y = rr * 0.45
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.5, 0.5, 0.52)
	rm.material_override = rmat
	body.add_child(rm)
	var rshape := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(rr * 2.0, rr * 1.1, rr * 1.8)
	rshape.shape = rbox
	rshape.position.y = rr * 0.5
	body.add_child(rshape)
	add_child(body)

# --- Actors / loot spawning ---

func _spawn_bots() -> void:
	bots_alive = BOT_COUNT
	for i in BOT_COUNT:
		var bot: CharacterBody3D = EnemyScript.new()
		bot.position = Vector3(0, -300, 0)
		bot.visible = false
		add_child(bot)
		bot.call("configure", BOT_NAMES[i], BOT_TINTS[i % BOT_TINTS.size()])
		bots.append(bot)
		bot_eject_x[i] = rng.randf_range(-270.0, 270.0)
		# Land near a compound (weighted) or open field.
		if rng.randf() < 0.8:
			var c: Dictionary = compounds[rng.randi() % compounds.size()]
			var cc: Vector2 = c["center"]
			bot_landing[i] = Vector3(cc.x + rng.randf_range(-26, 26), 0, cc.y + rng.randf_range(-26, 26))
		else:
			bot_landing[i] = Vector3(rng.randf_range(-200, 200), 0, rng.randf_range(-200, 200))

func spawn_loot(type: String, pos: Vector3, amount: int = 0) -> void:
	var item: Node3D = LootScript.new()
	item.add_to_group("loot")
	add_child(item)
	item.position = Vector3(pos.x, ground_height(pos.x, pos.z) + 0.05, pos.z)
	item.call("setup", type, amount)

func _spawn_all_loot() -> void:
	for c: Dictionary in compounds:
		var houses: Array = c.get("house_positions", [])
		for hpos: Vector3 in houses:
			_loot_in_house(hpos)
		# Porch/field loot around the compound.
		for i in 3:
			var cc: Vector2 = c["center"]
			spawn_loot(_random_item(), Vector3(cc.x + rng.randf_range(-30, 30), 0, cc.y + rng.randf_range(-30, 30)))
	# Field sprinkles.
	for i in 12:
		spawn_loot(_random_item(), Vector3(rng.randf_range(-210, 210), 0, rng.randf_range(-210, 210)))

func _loot_in_house(hpos: Vector3) -> void:
	var inner := Vector2(hpos.x, hpos.z)
	# One weapon per house (weighted) with matching ammo.
	if rng.randf() < 0.82:
		var wid: String = _random_weapon()
		spawn_loot(wid, Vector3(inner.x + rng.randf_range(-2, 2), 0, inner.y + rng.randf_range(-2, 2)))
		var kind: String = String(Weapons.DATA[wid]["ammo"])
		spawn_loot("ammo_" + kind, Vector3(inner.x + rng.randf_range(-2.5, 2.5), 0, inner.y + rng.randf_range(-2.5, 2.5)), int(Weapons.AMMO_PACKS[kind]))
		if rng.randf() < 0.6:
			spawn_loot("ammo_" + kind, Vector3(inner.x + rng.randf_range(-2.5, 2.5), 0, inner.y + rng.randf_range(-2.5, 2.5)), int(Weapons.AMMO_PACKS[kind]))
	if rng.randf() < 0.3:
		spawn_loot("grenade", Vector3(inner.x + rng.randf_range(-2, 2), 0, inner.y + rng.randf_range(-2, 2)))
	# Armor and heals.
	if rng.randf() < 0.55:
		spawn_loot(_random_armor(), Vector3(inner.x + rng.randf_range(-2, 2), 0, inner.y + rng.randf_range(-2, 2)))
	spawn_loot(_random_heal(), Vector3(inner.x + rng.randf_range(-2, 2), 0, inner.y + rng.randf_range(-2, 2)))
	if rng.randf() < 0.5:
		spawn_loot(_random_heal(), Vector3(inner.x + rng.randf_range(-2, 2), 0, inner.y + rng.randf_range(-2, 2)))

func _random_weapon() -> String:
	var roll: float = rng.randf()
	if roll < 0.3:
		return "m416"
	if roll < 0.52:
		return "uzi"
	if roll < 0.7:
		return "s686"
	if roll < 0.85:
		return "kar98"
	return "p92"

func _random_armor() -> String:
	var kind: String = "helmet" if rng.randf() < 0.5 else "vest"
	var roll: float = rng.randf()
	var lv: int = 1 if roll < 0.5 else (2 if roll < 0.85 else 3)
	return "%s%d" % [kind, lv]

func _random_heal() -> String:
	var roll: float = rng.randf()
	if roll < 0.38:
		return "bandage"
	if roll < 0.58:
		return "firstaid"
	if roll < 0.68:
		return "medkit"
	if roll < 0.86:
		return "drink"
	return "painkiller"

func _random_item() -> String:
	var roll: float = rng.randf()
	if roll < 0.3:
		return _random_heal()
	if roll < 0.5:
		return _random_armor()
	if roll < 0.75:
		var kinds: Array = ["9mm", "556", "762", "shell"]
		var kind: String = kinds[rng.randi() % kinds.size()]
		return "ammo_" + kind
	return _random_heal()

# --- Plane ---

func _build_plane() -> void:
	plane = Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.58, 0.62)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.3, 0.32, 0.36)
	var fus := MeshInstance3D.new()
	var fus_mesh := CylinderMesh.new()
	fus_mesh.top_radius = 1.6
	fus_mesh.bottom_radius = 1.9
	fus_mesh.height = 26.0
	fus.mesh = fus_mesh
	fus.rotation_degrees.z = 90
	fus.material_override = mat
	plane.add_child(fus)
	var wing := MeshInstance3D.new()
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = Vector3(5.0, 0.3, 30.0)
	wing.mesh = wing_mesh
	wing.position = Vector3(1, 0.4, 0)
	wing.material_override = dark
	plane.add_child(wing)
	var tail := MeshInstance3D.new()
	var tail_mesh := BoxMesh.new()
	tail_mesh.size = Vector3(3.4, 0.25, 10.0)
	tail.mesh = tail_mesh
	tail.position = Vector3(-12.4, 0.8, 0)
	tail.material_override = dark
	plane.add_child(tail)
	var fin := MeshInstance3D.new()
	var fin_mesh := BoxMesh.new()
	fin_mesh.size = Vector3(3.2, 3.4, 0.25)
	fin.mesh = fin_mesh
	fin.position = Vector3(-12.4, 2.4, 0)
	fin.material_override = dark
	plane.add_child(fin)
	plane.position = Vector3(-360, PLANE_Y, plane_z)
	plane.visible = false
	add_child(plane)

func player_eject_requested() -> void:
	if not started or plane_active == false or player_ejected:
		return
	player_ejected = true
	player.call("eject", plane.global_position + Vector3(0, -2, 0), Vector3.RIGHT)

# --- Match flow ---

func on_panel_button() -> void:
	if panel_mode == "start":
		start_game()
	else:
		get_tree().reload_current_scene()

func start_game() -> void:
	started = true
	panel_mode = "restart"
	hud.hide_panel()
	plane_z = rng.randf_range(-140.0, 140.0)
	plane.position = Vector3(-360, PLANE_Y, plane_z)
	plane.visible = true
	plane_active = true
	player.global_position = plane.position
	zone.start_match()
	hud.show_center_message("飛行機から降下せよ！")

func request_mouse_capture() -> void:
	if not DisplayServer.is_touchscreen_available():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func game_over(won: bool) -> void:
	if is_game_over:
		return
	is_game_over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if won:
		sfx.call("play", "win", -2.0)
		hud.show_panel("CHICKEN DINNER!", "WINNER WINNER CHICKEN DINNER!\n25人中 1位！（キル数: %d）" % kills, "もう一度プレイ")
	else:
		var rank: int = bots_alive + 1
		hud.show_panel("GAME OVER", "#%d 位 / %d 人中\nキル数: %d" % [rank, BOT_COUNT + 1, kills], "もう一度プレイ")

func on_actor_killed(victim: Node, killer: Node) -> void:
	var victim_name: String = String(victim.get("display_name"))
	if victim.is_in_group("enemies"):
		bots_alive -= 1
		# Death crate: the victim's weapon, some ammo and a heal drop.
		var vpos: Vector3 = (victim as Node3D).global_position
		var wid: String = String(victim.get("weapon_id"))
		if wid != "":
			spawn_loot(wid, vpos + Vector3(0.8, 0, 0.3))
			spawn_loot("ammo_" + String(Weapons.DATA[wid]["ammo"]), vpos + Vector3(-0.8, 0, -0.4), 20)
		spawn_loot("bandage", vpos + Vector3(0.2, 0, 0.9))
	if killer != null and is_instance_valid(killer):
		var killer_name: String = "You" if killer.is_in_group("player") else String(killer.get("display_name"))
		hud.add_feed("%s ▸ %s" % [killer_name, victim_name])
		if killer.is_in_group("player"):
			kills += 1
			sfx.call("play", "die", -6.0)
			if bots_alive > 0:
				hud.show_center_message("キル！ 残り %d 人" % (bots_alive + 1))
	else:
		hud.add_feed("%s はゾーンで力尽きた" % victim_name)
	sync_hud()
	if victim.is_in_group("player"):
		game_over(false)
	elif bots_alive <= 0:
		game_over(true)

func on_player_damaged(_hp: int, _max_hp: int, attacker: Node3D = null) -> void:
	if attacker != null:
		hud.flash_damage()
		hud.show_hit_direction(attacker.global_position, player.global_position, float(player.get("yaw")))

func on_player_hit() -> void:
	hud.flash_hitmarker()
	sfx.call("play", "hit", -10.0)

func sync_hud() -> void:
	if hud == null or player == null:
		return
	hud.refresh()
	var alive: int = bots_alive + (0 if bool(player.get("dead")) else 1)
	hud.set_stats(alive, kills)

func _on_zone_phase_changed() -> void:
	if not started or is_game_over:
		return
	if zone.state == "shrinking":
		hud.show_center_message("ゾーンが縮小している！")
		sfx.call("play", "zone", -4.0)

# --- Per-frame ---

func _process(delta: float) -> void:
	if not started or is_game_over:
		return
	# Plane flight + bot ejection.
	if plane_active:
		plane.position.x += 52.0 * delta
		if not player_ejected:
			player.global_position = plane.position + Vector3(0, -3, 0)
		for i in bots.size():
			var bot: Node = bots[i]
			if bot.get("state") == "chute" or bool(bot.get("dead")):
				continue
			if not bot.visible and plane.position.x >= float(bot_eject_x[i]):
				var land: Vector3 = bot_landing[i]
				bot.call("start_chute", plane.position + Vector3(0, -2, rng.randf_range(-6, 6)), land)
		if plane.position.x > 330.0:
			plane_active = false
			plane.visible = false
			if not player_ejected:
				player_eject_requested()
			for i in bots.size():
				var b2: Node = bots[i]
				if not b2.visible and not bool(b2.get("dead")):
					b2.call("start_chute", Vector3(rng.randf_range(-200, 200), PLANE_Y, plane_z), bot_landing[i])
	# Zone status + ticks.
	var player_outside: bool = zone.is_outside(player.global_position)
	hud.set_zone_status(zone.status_text(), player_outside and String(player.get("state")) == "ground")
	zone_tick_timer += delta
	if zone_tick_timer >= 1.0:
		zone_tick_timer = 0.0
		_zone_tick()
	loot_poll_timer += delta
	if loot_poll_timer >= 0.15:
		loot_poll_timer = 0.0
		_poll_loot()

func _zone_tick() -> void:
	if not bool(zone.get("running")) or int(zone.get("current_dps")) <= 0:
		return
	var dps: int = int(zone.get("current_dps"))
	for node: Node in get_tree().get_nodes_in_group("actors"):
		var actor: Node3D = node as Node3D
		if actor == null or bool(actor.get("dead")):
			continue
		if not bool(actor.call("is_grounded")):
			continue
		if zone.is_outside(actor.global_position):
			actor.call("take_damage", float(dps), null, actor.global_position + Vector3(0, 0.6, 0), true)
			if actor.is_in_group("player"):
				var center3 := Vector3(zone.center.x, actor.global_position.y, zone.center.y)
				hud.show_hit_direction(center3, actor.global_position, float(player.get("yaw")))

func _poll_loot() -> void:
	var loot_items: Array = get_tree().get_nodes_in_group("loot")
	# Player near-weapon detection for the swap prompt.
	var new_near: Node = null
	if String(player.get("state")) == "ground" and not bool(player.get("dead")):
		var slots_full: bool = true
		for s: Variant in player.get("slots"):
			if String(s) == "":
				slots_full = false
		if slots_full:
			var best_d: float = 2.6
			for item: Node in loot_items:
				var it3: Node3D = item as Node3D
				if it3 == null or not Weapons.DATA.has(String(item.get("loot_type"))):
					continue
				var d: float = it3.global_position.distance_to(player.global_position)
				if d < best_d:
					best_d = d
					new_near = item
	if new_near != near_weapon_loot:
		near_weapon_loot = new_near
		hud.refresh()
	# Pickups for every actor on the ground.
	for node: Node in get_tree().get_nodes_in_group("actors"):
		var actor: Node3D = node as Node3D
		if actor == null or bool(actor.get("dead")) or not bool(actor.call("is_grounded")):
			continue
		for item: Node in loot_items:
			if not is_instance_valid(item):
				continue
			var it3b: Node3D = item as Node3D
			if it3b.global_position.distance_to(actor.global_position) < 1.9:
				var consumed: int = int(actor.call("apply_loot", item))
				if consumed == 1:
					if actor.is_in_group("player"):
						var msg: String = String(player.get("last_loot_message"))
						if msg != "":
							hud.show_toast(msg)
						sfx.call("play", "pickup", -5.0)
					item.queue_free()
					if item == near_weapon_loot:
						near_weapon_loot = null
					break

# --- Effects / bullets ---

func spawn_bullet(shooter: Node3D, from: Vector3, dir: Vector3, weapon_id: String) -> void:
	var bullet: Node3D = BulletScript.new()
	add_child(bullet)
	bullet.call("setup", shooter, weapon_id, from, dir)

func spawn_grenade(thrower: Node3D, from: Vector3, vel: Vector3) -> void:
	var grenade: Node3D = GrenadeScript.new()
	add_child(grenade)
	grenade.call("setup", thrower, from, vel)

func explode(at_pos: Vector3, thrower: Node3D) -> void:
	var player_dist: float = player.global_position.distance_to(at_pos)
	sfx.call("play", "boom", clampf(-2.0 - player_dist * 0.1, -24.0, -2.0))
	spawn_spark(at_pos + Vector3(0, 0.4, 0), Color(1.0, 0.55, 0.15))
	spawn_spark(at_pos + Vector3(0, 0.9, 0), Color(0.4, 0.4, 0.4))
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for node: Node in get_tree().get_nodes_in_group("actors"):
		var actor: Node3D = node as Node3D
		if actor == null or bool(actor.get("dead")):
			continue
		var chest: Vector3 = actor.global_position + Vector3(0, 1.1, 0)
		var d: float = at_pos.distance_to(chest)
		if d > 6.0:
			continue
		var dmg: float = lerpf(95.0, 18.0, clampf(d / 6.0, 0.0, 1.0))
		var query := PhysicsRayQueryParameters3D.create(at_pos + Vector3(0, 0.3, 0), chest, 1)
		if not space.intersect_ray(query).is_empty():
			dmg *= 0.45
		actor.call("take_damage", dmg, thrower, chest, false)
	if player_dist < 13.0 and not bool(player.get("dead")):
		player.set("kick_offset", float(player.get("kick_offset")) - 0.05 * (1.0 - player_dist / 13.0))

func spawn_tracer(from: Vector3, to: Vector3, color: Color) -> void:
	var tracer: MeshInstance3D = TracerScript.new()
	add_child(tracer)
	tracer.setup_line(from, to, color)

func spawn_spark(at_position: Vector3, color: Color) -> void:
	var spark: MeshInstance3D = TracerScript.new()
	add_child(spark)
	spark.setup_spark(at_position, color)

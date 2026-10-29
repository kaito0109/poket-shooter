extends CanvasLayer
## HUD: bars, compass, minimap + big map, weapon panel, kill feed, touch UI.

const JoystickScript := preload("res://joystick.gd")
const MinimapScript := preload("res://minimap.gd")
const CompassScript := preload("res://compass.gd")

var main: Node
var player: Node

var hp_bar: ColorRect
var hp_bar_bg: ColorRect
var boost_bar: ColorRect
var hp_label: Label
var armor_label: Label
var items_label: Label
var compass: Control
var zone_label: Label
var stats_label: Label
var minimap: Control
var big_map: Control
var big_map_bg: ColorRect
var big_map_open: bool = false
var weapon_label: Label
var ammo_label: Label
var slots_label: Label
var heal_bar_bg: ColorRect
var heal_bar: ColorRect
var heal_label: Label
var prompt_label: Label
var flight_label: Label
var center_label: Label
var crosshair: Label
var hitmarker: Label
var damage_overlay: ColorRect
var hit_dir: Control
var toast_label: Label
var panel: Panel
var panel_title: Label
var panel_text: Label
var panel_button: Button
var feed_labels: Array[Label] = []
var feed_timers: Array[float] = []
var touch_root: Control
var joystick: Control
var touch_buttons: Dictionary = {}
var center_msg_timer: float = 0.0
var toast_timer: float = 0.0
var vignette_alpha: float = 0.0
var hitmarker_alpha: float = 0.0
var hit_dir_alpha: float = 0.0
var hit_dir_angle: float = 0.0
var look_dragging: bool = false
var touch_mode: bool = false

class HitDir:
	extends Control
	var angle: float = 0.0
	var alpha: float = 0.0
	func _draw() -> void:
		if alpha <= 0.01:
			return
		var c: Vector2 = size * 0.5
		var phi: float = angle - PI * 0.5
		draw_arc(c, 52.0, phi - 0.55, phi + 0.55, 12, Color(1, 0.2, 0.15, alpha), 7.0)

func _mk_label(text: String, size_px: int, color: Color = Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func bind(p_main: Node, p_player: Node) -> void:
	main = p_main
	player = p_player
	_build()

func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Damage vignette.
	damage_overlay = ColorRect.new()
	damage_overlay.color = Color(0.85, 0.1, 0.05, 0.0)
	damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_overlay)
	# HP / boost.
	hp_bar_bg = ColorRect.new()
	hp_bar_bg.color = Color(0, 0, 0, 0.55)
	root.add_child(hp_bar_bg)
	hp_bar = ColorRect.new()
	hp_bar.color = Color(0.35, 0.85, 0.35)
	root.add_child(hp_bar)
	boost_bar = ColorRect.new()
	boost_bar.color = Color(0.98, 0.8, 0.2)
	root.add_child(boost_bar)
	hp_label = _mk_label("HP 100", 17)
	root.add_child(hp_label)
	armor_label = _mk_label("", 14, Color(0.9, 0.9, 0.95))
	root.add_child(armor_label)
	items_label = _mk_label("", 14, Color(0.95, 0.95, 0.85))
	root.add_child(items_label)
	# Compass + zone.
	compass = CompassScript.new()
	root.add_child(compass)
	zone_label = _mk_label("", 16, Color(0.85, 0.9, 1.0))
	zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(zone_label)
	center_label = _mk_label("", 30, Color(1.0, 0.85, 0.3))
	center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(center_label)
	# Stats + minimap.
	stats_label = _mk_label("", 19)
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(stats_label)
	minimap = MinimapScript.new()
	root.add_child(minimap)
	for i in 4:
		var fl := _mk_label("", 14, Color(1.0, 0.95, 0.8))
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		root.add_child(fl)
		feed_labels.append(fl)
		feed_timers.append(0.0)
	# Big map overlay.
	big_map_bg = ColorRect.new()
	big_map_bg.color = Color(0, 0, 0, 0.55)
	big_map_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	big_map_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	big_map_bg.visible = false
	root.add_child(big_map_bg)
	big_map = MinimapScript.new()
	big_map.visible = false
	root.add_child(big_map)
	# Weapon panel.
	weapon_label = _mk_label("素手", 18, Color(1, 1, 1))
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(weapon_label)
	ammo_label = _mk_label("", 30)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(ammo_label)
	slots_label = _mk_label("", 13, Color(0.85, 0.85, 0.85))
	slots_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(slots_label)
	# Heal bar + prompts.
	heal_bar_bg = ColorRect.new()
	heal_bar_bg.color = Color(0, 0, 0, 0.55)
	heal_bar_bg.visible = false
	root.add_child(heal_bar_bg)
	heal_bar = ColorRect.new()
	heal_bar.color = Color(0.4, 0.9, 0.95)
	heal_bar.visible = false
	root.add_child(heal_bar)
	heal_label = _mk_label("", 15, Color(0.85, 0.98, 1.0))
	heal_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(heal_label)
	prompt_label = _mk_label("", 17, Color(1.0, 0.9, 0.4))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)
	flight_label = _mk_label("", 22, Color(1.0, 0.95, 0.6))
	flight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(flight_label)
	toast_label = _mk_label("", 17, Color(0.8, 1.0, 0.85))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(toast_label)
	# Crosshair / hitmarker / hit direction.
	crosshair = _mk_label("+", 22, Color(1, 1, 1, 0.9))
	crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(crosshair)
	hitmarker = _mk_label("✕", 20, Color(1, 1, 1, 0))
	hitmarker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(hitmarker)
	hit_dir = HitDir.new()
	hit_dir.set_anchors_preset(Control.PRESET_FULL_RECT)
	hit_dir.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hit_dir)
	_build_touch(root)
	_build_panel(root)
	get_viewport().size_changed.connect(_layout)
	_layout()
	refresh()

func _build_touch(root: Control) -> void:
	touch_root = Control.new()
	touch_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_root.visible = false
	root.add_child(touch_root)
	joystick = JoystickScript.new()
	touch_root.add_child(joystick)
	_add_touch_button("FIRE", "FIRE")
	_add_touch_button("JUMP", "JUMP")
	_add_touch_button("RELOAD", "RELOAD")
	_add_touch_button("AIM", "狙う")
	_add_touch_button("WEAPON", "武器")
	_add_touch_button("HEAL", "回復")
	_add_touch_button("DRINK", "ドリンク")
	_add_touch_button("CROUCH", "しゃがみ")
	_add_touch_button("FPP", "視点")
	_add_touch_button("MAP", "マップ")
	_add_touch_button("EJECT", "降下！")
	_add_touch_button("SWAP", "持ち替え")
	touch_buttons["FIRE"].button_down.connect(func() -> void: player.set("touch_firing", true))
	touch_buttons["FIRE"].button_up.connect(func() -> void: player.set("touch_firing", false))
	touch_buttons["JUMP"].button_down.connect(func() -> void: player.set("touch_jump", true))
	touch_buttons["AIM"].toggled.connect(func(on: bool) -> void: player.set("touch_aiming", on))
	touch_buttons["RELOAD"].pressed.connect(func() -> void: player.call("_start_reload"))
	touch_buttons["WEAPON"].pressed.connect(func() -> void: player.call("switch_slot", 1 - int(player.get("current_slot"))))
	touch_buttons["HEAL"].pressed.connect(func() -> void: _smart_heal())
	touch_buttons["DRINK"].pressed.connect(func() -> void:
		if not player.call("start_use_item", "drink"):
			player.call("start_use_item", "painkiller"))
	touch_buttons["CROUCH"].toggled.connect(func(_on: bool) -> void: player.call("toggle_crouch"))
	touch_buttons["FPP"].pressed.connect(func() -> void: player.call("toggle_first_person"))
	touch_buttons["MAP"].pressed.connect(func() -> void: _toggle_big_map())
	touch_buttons["EJECT"].pressed.connect(func() -> void:
		if main != null:
			main.call("player_eject_requested"))
	touch_buttons["SWAP"].pressed.connect(func() -> void:
		if main != null and main.get("near_weapon_loot") != null:
			player.call("swap_with_loot", main.get("near_weapon_loot")))

func _smart_heal() -> void:
	if int(player.get("hp")) < 55 and int(player.get("medkits")) > 0:
		player.call("start_use_item", "medkit")
	elif not player.call("start_use_item", "firstaid"):
		player.call("start_use_item", "bandage")

func _add_touch_button(id: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 15)
	b.modulate = Color(1, 1, 1, 0.85)
	touch_root.add_child(b)
	touch_buttons[id] = b

func _build_panel(root: Control) -> void:
	panel = Panel.new()
	panel.custom_minimum_size = Vector2(560, 380)
	root.add_child(panel)
	panel_title = _mk_label("", 34, Color(1.0, 0.85, 0.3))
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(panel_title)
	panel_text = _mk_label("", 16)
	panel_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(panel_text)
	panel_button = Button.new()
	panel_button.text = "スタート"
	panel_button.add_theme_font_size_override("font_size", 20)
	panel.add_child(panel_button)
	panel_button.pressed.connect(func() -> void:
		if main != null:
			main.call("on_panel_button"))

func _layout() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	hp_bar_bg.position = Vector2(16, 14)
	hp_bar_bg.size = Vector2(244, 20)
	hp_label.position = Vector2(20, 15)
	armor_label.position = Vector2(16, 56)
	items_label.position = Vector2(16, 78)
	compass.position = Vector2(vp.x * 0.5 - 280, 6)
	compass.size = Vector2(560, 34)
	zone_label.position = Vector2(vp.x * 0.5 - 300, 44)
	zone_label.size = Vector2(600, 24)
	center_label.position = Vector2(vp.x * 0.5 - 400, 120)
	center_label.size = Vector2(800, 40)
	stats_label.position = Vector2(vp.x - 216, 12)
	stats_label.size = Vector2(200, 26)
	minimap.position = Vector2(vp.x - 206, 44)
	minimap.size = Vector2(190, 190)
	for i in feed_labels.size():
		feed_labels[i].position = Vector2(vp.x - 416, 244 + i * 22)
		feed_labels[i].size = Vector2(400, 22)
	big_map.position = Vector2(vp.x * 0.5 - 280, vp.y * 0.5 - 280)
	big_map.size = Vector2(560, 560)
	weapon_label.position = Vector2(vp.x - 316, vp.y - 118)
	weapon_label.size = Vector2(300, 24)
	ammo_label.position = Vector2(vp.x - 316, vp.y - 94)
	ammo_label.size = Vector2(300, 38)
	slots_label.position = Vector2(vp.x - 316, vp.y - 52)
	slots_label.size = Vector2(300, 20)
	heal_bar_bg.position = Vector2(vp.x * 0.5 - 150, vp.y - 108)
	heal_bar_bg.size = Vector2(300, 12)
	heal_label.position = Vector2(vp.x * 0.5 - 200, vp.y - 134)
	heal_label.size = Vector2(400, 22)
	prompt_label.position = Vector2(vp.x * 0.5 - 300, vp.y - 168)
	prompt_label.size = Vector2(600, 24)
	flight_label.position = Vector2(vp.x * 0.5 - 400, vp.y - 220)
	flight_label.size = Vector2(800, 30)
	toast_label.position = Vector2(vp.x * 0.5 - 300, vp.y - 196)
	toast_label.size = Vector2(600, 24)
	crosshair.position = Vector2(vp.x * 0.5 - 25, vp.y * 0.5 - 16)
	crosshair.size = Vector2(50, 32)
	hitmarker.position = Vector2(vp.x * 0.5 - 25, vp.y * 0.5 - 40)
	hitmarker.size = Vector2(50, 28)
	panel.position = Vector2(vp.x * 0.5 - 280, vp.y * 0.5 - 190)
	panel.size = Vector2(560, 380)
	panel_title.position = Vector2(10, 22)
	panel_title.size = Vector2(540, 46)
	panel_text.position = Vector2(24, 84)
	panel_text.size = Vector2(512, 190)
	panel_button.position = Vector2(180, 300)
	panel_button.size = Vector2(200, 52)
	# Touch UI.
	joystick.position = Vector2(26, vp.y - 206)
	var pos_map: Dictionary = {
		"FIRE": [vp.x - 128, vp.y - 250, 104, 104],
		"JUMP": [vp.x - 238, vp.y - 128, 84, 84],
		"RELOAD": [vp.x - 232, vp.y - 238, 78, 62],
		"AIM": [vp.x - 128, vp.y - 372, 84, 62],
		"WEAPON": [vp.x - 330, vp.y - 128, 78, 62],
		"HEAL": [vp.x - 330, vp.y - 206, 78, 62],
		"DRINK": [vp.x - 330, vp.y - 284, 78, 62],
		"CROUCH": [vp.x - 238, vp.y - 330, 84, 62],
		"FPP": [16, 120, 70, 52],
		"MAP": [16, 182, 70, 52],
		"EJECT": [vp.x * 0.5 - 70, vp.y - 300, 140, 64],
		"SWAP": [vp.x * 0.5 - 70, vp.y - 260, 140, 56],
	}
	for id: String in pos_map.keys():
		var r: Array = pos_map[id]
		(touch_buttons[id] as Button).position = Vector2(r[0], r[1])
		(touch_buttons[id] as Button).size = Vector2(r[2], r[3])

func _process(delta: float) -> void:
	# Touch mode detection + joystick feed.
	if DisplayServer.is_touchscreen_available():
		touch_mode = true
	if touch_mode and not touch_root.visible:
		touch_root.visible = true
	if touch_root.visible and player != null:
		player.set("touch_move", joystick.get("value"))
	# Per-frame visual updates.
	if player != null:
		var pstate: String = String(player.get("state"))
		crosshair.visible = pstate == "ground" and not bool(player.get("dead"))
		if touch_root.visible:
			touch_buttons["EJECT"].visible = pstate == "plane"
			var near_w: Variant = main.get("near_weapon_loot") if main != null else null
			touch_buttons["SWAP"].visible = pstate == "ground" and near_w != null
		# Flight prompt.
		match pstate:
			"plane":
				flight_label.text = "飛行機で移動中… 好きな場所で Fキー / 降下ボタン！"
			"fall":
				flight_label.text = "降下中… まもなくパラシュートが開く"
			"chute":
				flight_label.text = "パラシュート降下中　W: 前進加速 / S: 減速"
			_:
				flight_label.text = ""
		# HP/boost bars follow current values every frame (cheap + always fresh).
		var hp_now: int = int(player.get("hp"))
		hp_bar.size = Vector2(244.0 * clampf(float(hp_now) / 100.0, 0.0, 1.0), 20)
		hp_bar.position = hp_bar_bg.position
		hp_bar.color = Color(0.9, 0.3, 0.25) if hp_now <= 30 else Color(0.35, 0.85, 0.35)
		boost_bar.size = Vector2(244.0 * clampf(float(player.get("boost")) / 100.0, 0.0, 1.0), 5)
		boost_bar.position = hp_bar_bg.position + Vector2(0, 23)
		hp_label.text = "HP %d" % hp_now
		# Heal progress.
		var prog: float = float(player.call("heal_progress"))
		var healing: bool = prog >= 0.0
		heal_bar_bg.visible = healing
		heal_bar.visible = healing
		if healing:
			heal_bar.position = heal_bar_bg.position
			heal_bar.size = Vector2(300.0 * prog, 12)
			heal_label.text = "使用中…（被弾で中断）"
		else:
			heal_label.text = ""
	# Fades.
	if center_msg_timer > 0.0:
		center_msg_timer -= delta
		if center_msg_timer <= 0.0:
			center_label.text = ""
	if toast_timer > 0.0:
		toast_timer -= delta
		if toast_timer <= 0.0:
			toast_label.text = ""
	if vignette_alpha > 0.0:
		vignette_alpha = maxf(vignette_alpha - delta * 0.7, 0.0)
		damage_overlay.color.a = vignette_alpha * 0.32
	if hitmarker_alpha > 0.0:
		hitmarker_alpha = maxf(hitmarker_alpha - delta * 3.2, 0.0)
		hitmarker.add_theme_color_override("font_color", Color(1, 1, 1, hitmarker_alpha))
	hitmarker.visible = hitmarker_alpha > 0.02
	if hit_dir_alpha > 0.0:
		hit_dir_alpha = maxf(hit_dir_alpha - delta * 1.4, 0.0)
		hit_dir.set("alpha", hit_dir_alpha)
		hit_dir.queue_redraw()
	for i in feed_labels.size():
		if feed_timers[i] > 0.0:
			feed_timers[i] -= delta
			if feed_timers[i] <= 0.0:
				feed_labels[i].text = ""

func refresh() -> void:
	if player == null:
		return
	var helmet: int = int(player.get("helmet_lv"))
	var vest: int = int(player.get("vest_lv"))
	armor_label.text = "ヘルメット %s　ベスト %s" % [("Lv%d" % helmet) if helmet > 0 else "なし", ("Lv%d" % vest) if vest > 0 else "なし"]
	items_label.text = "包帯×%d 応急×%d 医療×%d ドリンク×%d 鎮痛×%d" % [
		int(player.get("bandages")), int(player.get("firstaids")), int(player.get("medkits")),
		int(player.get("drinks")), int(player.get("painkillers"))]
	# Weapon panel.
	var slots: Array = player.get("slots")
	var mags: Array = player.get("slot_mags")
	var cur: int = int(player.get("current_slot"))
	var reserve: Dictionary = player.get("reserve")
	var wid: String = String(slots[cur])
	if wid == "":
		weapon_label.text = "素手（武器を探そう）"
		ammo_label.text = ""
	else:
		var data: Dictionary = Weapons.DATA[wid]
		weapon_label.text = Weapons.display_name(wid)
		ammo_label.text = "%d / %d" % [int(mags[cur]), int(reserve.get(String(data["ammo"]), 0))]
		if bool(player.get("reloading")):
			ammo_label.text += "  リロード中"
	var slot_texts: Array[String] = []
	for i in slots.size():
		var s_id: String = String(slots[i])
		var nm: String = Weapons.display_name(s_id) if s_id != "" else "—"
		slot_texts.append("[%d] %s%s" % [i + 1, nm, " ◀" if i == cur else ""])
	slots_label.text = "　".join(slot_texts)
	# Prompt for weapon swap.
	if main != null:
		var near_w: Variant = main.get("near_weapon_loot")
		if near_w != null and String(player.get("state")) == "ground":
			prompt_label.text = "Fキー / 持ち替えボタン: %s と交換" % String((near_w as Node).call("display_name"))
		else:
			prompt_label.text = ""

func set_stats(alive: int, kills: int) -> void:
	stats_label.text = "ALIVE %d　KILLS %d" % [alive, kills]

func set_zone_status(text: String, danger: bool) -> void:
	zone_label.text = text
	zone_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35) if danger else Color(0.85, 0.9, 1.0))

func set_minimap_buildings(rects: Array) -> void:
	minimap.call("set_buildings", rects)
	big_map.call("set_buildings", rects)

func set_minimap_radius(r: float) -> void:
	minimap.set("WORLD_RADIUS", r)
	big_map.set("WORLD_RADIUS", r)

func add_feed(text: String) -> void:
	for i in range(feed_labels.size() - 1, 0, -1):
		feed_labels[i].text = feed_labels[i - 1].text
		feed_timers[i] = feed_timers[i - 1]
	feed_labels[0].text = text
	feed_timers[0] = 5.0

func show_center_message(text: String) -> void:
	center_label.text = text
	center_msg_timer = 2.6

func show_toast(text: String) -> void:
	toast_label.text = text
	toast_timer = 2.2

func flash_damage() -> void:
	vignette_alpha = 1.0

func flash_hitmarker() -> void:
	hitmarker_alpha = 1.0

func show_hit_direction(attacker_pos: Vector3, player_pos: Vector3, _yaw: float) -> void:
	if player == null:
		return
	var heading: float = -float(player.get("yaw"))
	var d: Vector3 = attacker_pos - player_pos
	var a: float = atan2(d.x, -d.z)
	hit_dir_angle = wrapf(a - heading, -PI, PI)
	hit_dir.set("angle", hit_dir_angle)
	hit_dir_alpha = 1.0
	hit_dir.set("alpha", 1.0)
	hit_dir.queue_redraw()

func show_panel(title: String, text: String, button: String) -> void:
	panel.visible = true
	panel_title.text = title
	panel_text.text = text
	panel_button.text = button

func hide_panel() -> void:
	panel.visible = false

func _toggle_big_map() -> void:
	big_map_open = not big_map_open
	big_map.visible = big_map_open
	big_map_bg.visible = big_map_open

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_M:
			_toggle_big_map()
	# Touch look: drag on the right half (mouse events emulate touch on web).
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and _is_look_area(mb.position):
				look_dragging = true
				touch_mode = true
			elif not mb.pressed:
				look_dragging = false
	elif event is InputEventMouseMotion and look_dragging:
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		if player != null and String(player.get("state")) != "plane":
			player.call("add_look_input", mm.relative)
		touch_mode = true

func _is_look_area(pos: Vector2) -> bool:
	if panel.visible:
		return false
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if pos.x < vp.x * 0.42:
		return false
	if touch_root.visible:
		for id: String in touch_buttons.keys():
			var b: Button = touch_buttons[id] as Button
			if b.visible and b.get_global_rect().has_point(pos):
				return false
		if joystick.get_global_rect().has_point(pos):
			return false
	return true

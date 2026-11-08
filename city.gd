extends Node
# City: coins, shops, weapons, missions, hide spots, police, evidence, extra dogs, tips.

const SAVE := "user://progress.cfg"
const SWORD_PRICE := 12
const GUN_PRICE := 25
const AMMO_PRICE := 4
const AMMO_PACK := 6

static var sfx_cache := {}

const TIPS := [
	{"x": 1.0, "text": "Move with < >. Jump with A.\nCollect the coins!"},
	{"x": 14.0, "text": "Hold X (PUSH) beside a crate to push or pull it."},
	{"x": 29.5, "text": "The ARMORY sells a sword. Stand at the counter and press USE."},
	{"x": 30.5, "text": "Press B (DOWN) to crouch and crawl through vents."},
	{"x": 39.0, "text": "Dogs hear less when you crouch.\nHide in a green dumpster with USE."},
	{"x": 43.0, "text": "Dogs cannot climb. Stand on a platform and they give up."},
	{"x": 61.0, "text": "Careful: a gap ahead. Run and jump!"},
	{"x": 73.0, "text": "The BLACK MARKET sells a pistol.\nPress USE at the counter."},
	{"x": 100.0, "text": "The police station is at the end of the street."},
]

# progress (saved)
var coins := 0
var pickups := 0
var collected := {}
var evidence_ids := {}
var has_sword := false
var has_gun := false
var ammo := 0
var weapon := 0
var kills := 0
var radio_done := false
var mission_idx := 0

# runtime
var lv: Node = null
var menu_done: Node = null
var age := 0
var t := 0.0
var hidden := false
var hide_anchor := Vector3.ZERO
var shop_open := false
var shop_kind := ""
var shake := 0.0
var cooldown := 0.0
var attack_t := 0.0
var attack_dur := 0.35
var banner_t := 0.0
var tips_shown := {}
var interactables: Array = []
var coin_nodes: Array = []
var sirens: Array = []
var weapon_nodes: Array = []
var sfx := {}
var ui: CanvasLayer = null
var pad2 = null
var coin_label: Label
var weapon_label: Label
var mission_label: Label
var banner_label: Label
var shop_panel: Control
var shop_title: Label
var shop_coins: Label
var shop_buttons: Array = []


class Pad2 extends Control:
	var pressed := {}
	var use_text := "USE"
	var use_ready := false

	func layout() -> Array:
		var sz := get_viewport_rect().size
		return [
			{"id": "attack", "pos": Vector2(sz.x - 130.0, 330.0), "r": 60.0, "label": "ATK", "col": Color(1.0, 0.75, 0.2)},
			{"id": "use", "pos": Vector2(sz.x - 295.0, 300.0), "r": 58.0, "label": use_text, "col": Color(0.4, 0.9, 0.9)},
			{"id": "swap", "pos": Vector2(sz.x - 130.0, 190.0), "r": 44.0, "label": "SWAP", "col": Color(0.8, 0.8, 0.8)},
		]

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for b in layout():
			var p: Vector2 = b["pos"]
			var r: float = b["r"]
			var col: Color = b["col"]
			var on: bool = pressed.get(b["id"], false)
			var dim := 0.9
			if b["id"] == "use" and not use_ready:
				dim = 0.35
			draw_circle(p, r, Color(col.r, col.g, col.b, (0.5 if on else 0.16) * dim))
			draw_arc(p, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.8 * dim), 4.0, true)
			var label: String = b["label"]
			draw_string(font, p + Vector2(-r, 10), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 28, Color(1, 1, 1, 0.9 * dim))


func _ready() -> void:
	_load()


# ---------- save / load ----------

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE) != OK:
		return
	coins = int(cf.get_value("p", "coins", 0))
	pickups = int(cf.get_value("p", "pickups", 0))
	for id in cf.get_value("p", "collected", []):
		collected[int(id)] = true
	for id in cf.get_value("p", "evidence", []):
		evidence_ids[int(id)] = true
	has_sword = bool(cf.get_value("p", "sword", false))
	has_gun = bool(cf.get_value("p", "gun", false))
	ammo = int(cf.get_value("p", "ammo", 0))
	weapon = int(cf.get_value("p", "weapon", 0))
	kills = int(cf.get_value("p", "kills", 0))
	radio_done = bool(cf.get_value("p", "radio", false))
	mission_idx = int(cf.get_value("p", "mission", 0))


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("p", "coins", coins)
	cf.set_value("p", "pickups", pickups)
	cf.set_value("p", "collected", collected.keys())
	cf.set_value("p", "evidence", evidence_ids.keys())
	cf.set_value("p", "sword", has_sword)
	cf.set_value("p", "gun", has_gun)
	cf.set_value("p", "ammo", ammo)
	cf.set_value("p", "weapon", weapon)
	cf.set_value("p", "kills", kills)
	cf.set_value("p", "radio", radio_done)
	cf.set_value("p", "mission", mission_idx)
	cf.save(SAVE)


func _reset_progress() -> void:
	coins = 0
	pickups = 0
	collected.clear()
	evidence_ids.clear()
	has_sword = false
	has_gun = false
	ammo = 0
	weapon = 0
	kills = 0
	radio_done = false
	mission_idx = 0
	_save()


# ---------- scene detection ----------

func _process(delta: float) -> void:
	t += delta
	var cs := get_tree().current_scene
	if cs == null:
		return
	if cs.get("settings_box") != null and cs.get("about_box") != null:
		if menu_done != cs:
			menu_done = cs
			_inject_menu(cs)
		lv = null
		return
	if cs.get("player") != null and cs.get("env") != null and cs.get("cam") != null and cs.get("weather") != null:
		if lv != cs:
			lv = cs
			age = 0
			_reset_runtime()
		age += 1
		if age == 5:
			_setup()
		elif age > 5:
			_update(delta)
	else:
		lv = null


func _reset_runtime() -> void:
	hidden = false
	shop_open = false
	shake = 0.0
	cooldown = 0.0
	attack_t = 0.0
	banner_t = 0.0
	tips_shown.clear()
	interactables.clear()
	coin_nodes.clear()
	sirens.clear()
	weapon_nodes.clear()
	sfx.clear()
	shop_buttons.clear()
	ui = null
	pad2 = null


func _inject_menu(menu: Node) -> void:
	var box = menu.get("settings_box")
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(520, 84)
	btn.add_theme_font_size_override("font_size", 36)
	btn.text = "RESET PROGRESS"
	btn.pressed.connect(func():
		_reset_progress()
		btn.text = "PROGRESS RESET")
	box.add_child(btn)
	box.move_child(btn, maxi(box.get_child_count() - 2, 0))


# ---------- helpers ----------

func _mat(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _mi(parent: Node, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _label3d(text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = size
	lb.pixel_size = 0.01
	lb.modulate = color
	lb.outline_size = 6
	lb.position = pos
	lv.add_child(lb)
	return lb


func _light(pos: Vector3, color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	lv.add_child(l)
	return l


func _player() -> Node:
	return lv.get("player")


# ---------- audio ----------

func _to_wav(samples: PackedFloat32Array, rate: int, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


func _make_coin_sfx() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.28)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var tt := float(i) / rate
		var f := 988.0 if tt < 0.07 else 1319.0
		var env := exp(-tt * 9.0)
		s[i] = (sin(TAU * f * tt) * 0.4 + sin(TAU * f * 2.0 * tt) * 0.1) * env
	return _to_wav(s, rate)


func _make_buy() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var notes := [523.0, 659.0, 784.0]
	for i in n:
		var tt := float(i) / rate
		var idx := mini(int(tt / 0.1), 2)
		var local := tt - idx * 0.1
		s[i] = sin(TAU * float(notes[idx]) * tt) * 0.35 * exp(-local * 12.0)
	return _to_wav(s, rate)


func _make_gun() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.5
		s[i] = (lp * 1.2 * exp(-tt * 16.0) + sin(TAU * 70.0 * tt) * exp(-tt * 20.0) * 0.8) * 0.9
	return _to_wav(s, rate)


func _make_swish() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.25)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.2
		s[i] = lp * sin(PI * tt / 0.25) * 0.9
	return _to_wav(s, rate)


func _make_kill() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.35)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var tt := float(i) / rate
		var f := 700.0 - 1500.0 * tt
		s[i] = sin(TAU * f * tt) * 0.5 * exp(-tt * 8.0) + sin(TAU * 60.0 * tt) * 0.4 * exp(-tt * 12.0)
	return _to_wav(s, rate)


func _make_siren() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 3
	var s := PackedFloat32Array()
	s.resize(n)
	var ph := 0.0
	for i in n:
		var tt := float(i) / rate
		var f := 750.0 + 350.0 * sin(TAU * tt / 3.0 - PI / 2.0)
		ph += TAU * f / rate
		var fade := clampf(minf(tt, 3.0 - tt) / 0.05, 0.0, 1.0)
		s[i] = (sin(ph) + 0.3 * sin(3.0 * ph)) * 0.35 * fade
	return _to_wav(s, rate, true)


func _sfx_player(key: String, maker: Callable, db: float) -> AudioStreamPlayer:
	if not sfx_cache.has(key):
		sfx_cache[key] = maker.call()
	var p := AudioStreamPlayer.new()
	p.stream = sfx_cache[key]
	p.volume_db = db
	lv.add_child(p)
	return p


func _sfx(key: String) -> void:
	if sfx.has(key):
		var p: AudioStreamPlayer = sfx[key]
		p.pitch_scale = randf_range(0.95, 1.05)
		p.play()


func _build_audio() -> void:
	sfx["coin"] = _sfx_player("coin", _make_coin_sfx, -9.0)
	sfx["buy"] = _sfx_player("buy", _make_buy, -8.0)
	sfx["gun"] = _sfx_player("gun", _make_gun, -4.0)
	sfx["swish"] = _sfx_player("swish", _make_swish, -8.0)
	sfx["kill"] = _sfx_player("kill", _make_kill, -6.0)


# ---------- setup ----------

func _setup() -> void:
	_build_audio()
	_build_ui()
	_spawn_coins()
	_build_shops()
	_build_hide_spots()
	_build_police()
	_build_evidence()
	_build_station()
	_add_dogs()
	_attach_weapons()
	_refresh_ui()
	_banner("Mission: " + str(_mission(mission_idx)[0]), 4.0)


func _add_dogs() -> void:
	if lv.has_method("_add_dog"):
		lv.call("_add_dog", 69.0, 67.4, 71.2)
		lv.call("_add_dog", 104.5, 102.0, 107.0)
	var dogs = lv.get("dogs")
	if dogs != null:
		for d in dogs:
			_dress_dog(d)


func _dress_dog(d: Node) -> void:
	var neck = d.get("neck")
	if neck == null:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.088
	cyl.bottom_radius = 0.088
	cyl.height = 0.05
	_mi(neck, cyl, _glow(Color(0.8, 0.1, 0.08), 1.2), Vector3(0, 0.06, 0))


# ---------- UI ----------

func _ui_label(text: String, size: int, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	ui.add_child(l)
	return l


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 12
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	lv.add_child(ui)

	pad2 = Pad2.new()
	pad2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(pad2)

	coin_label = _ui_label("", 30, Vector2(24, 64))
	coin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	weapon_label = _ui_label("", 24, Vector2(24, 104))
	mission_label = _ui_label("", 24, Vector2(24, 144))
	mission_label.size = Vector2(640, 90)
	mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))

	banner_label = Label.new()
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_label.offset_top = 70.0
	banner_label.offset_bottom = 230.0
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	banner_label.add_theme_font_size_override("font_size", 34)
	banner_label.add_theme_color_override("font_outline_color", Color.BLACK)
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.modulate.a = 0.0
	banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(banner_label)

	_build_shop_panel()


func _build_shop_panel() -> void:
	shop_panel = Control.new()
	shop_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_panel.visible = false
	ui.add_child(shop_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shop_panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	shop_title = Label.new()
	shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_title.add_theme_font_size_override("font_size", 60)
	box.add_child(shop_title)
	shop_coins = Label.new()
	shop_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_coins.add_theme_font_size_override("font_size", 32)
	shop_coins.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(shop_coins)
	for i in 2:
		var b := Button.new()
		b.custom_minimum_size = Vector2(560, 84)
		b.add_theme_font_size_override("font_size", 34)
		b.pressed.connect(_shop_pressed.bind(i))
		box.add_child(b)
		shop_buttons.append(b)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(560, 84)
	close.add_theme_font_size_override("font_size", 34)
	close.pressed.connect(_close_shop)
	box.add_child(close)


func _refresh_ui() -> void:
	if coin_label == null:
		return
	coin_label.text = "COINS  %d" % coins
	var names := ["FISTS", "SWORD", "PISTOL"]
	weapon_label.text = "WEAPON  " + names[weapon] + (("   AMMO %d" % ammo) if weapon == 2 else "")
	var m := _mission(mission_idx)
	mission_label.text = "MISSION %d/6\n%s" % [mission_idx + 1, str(m[0])]


func _banner(text: String, secs := 3.5) -> void:
	if banner_label == null:
		return
	banner_label.text = text
	banner_label.modulate.a = 1.0
	banner_t = secs


# ---------- shops ----------

func _open_shop(kind: String) -> void:
	shop_kind = kind
	shop_open = true
	get_tree().paused = true
	shop_panel.visible = true
	_shop_refresh()


func _close_shop() -> void:
	shop_open = false
	get_tree().paused = false
	shop_panel.visible = false


func _shop_refresh() -> void:
	shop_coins.text = "COINS  %d" % coins
	var b0: Button = shop_buttons[0]
	var b1: Button = shop_buttons[1]
	if shop_kind == "armory":
		shop_title.text = "ARMORY"
		b0.text = "SWORD  -  OWNED" if has_sword else "SWORD  -  %d coins" % SWORD_PRICE
		b0.disabled = has_sword
		b1.visible = false
	else:
		shop_title.text = "BLACK MARKET"
		b0.text = "PISTOL  -  OWNED" if has_gun else "PISTOL  -  %d coins" % GUN_PRICE
		b0.disabled = has_gun
		b1.visible = has_gun
		b1.text = "AMMO x%d  -  %d coins" % [AMMO_PACK, AMMO_PRICE]
		b1.disabled = false


func _shop_pressed(i: int) -> void:
	if shop_kind == "armory" and i == 0 and not has_sword and coins >= SWORD_PRICE:
		coins -= SWORD_PRICE
		has_sword = true
		weapon = 1
		_sfx("buy")
		_banner("Sword bought! Tap ATK to swing.", 3.0)
	elif shop_kind == "market" and i == 0 and not has_gun and coins >= GUN_PRICE:
		coins -= GUN_PRICE
		has_gun = true
		ammo += AMMO_PACK
		weapon = 2
		_sfx("buy")
		_banner("Pistol bought with %d bullets. Noise attracts dogs!" % AMMO_PACK, 3.5)
	elif shop_kind == "market" and i == 1 and has_gun and coins >= AMMO_PRICE:
		coins -= AMMO_PRICE
		ammo += AMMO_PACK
		_sfx("buy")
	else:
		_banner("Not enough coins", 1.5)
	_save()
	_shop_refresh()
	_refresh_ui()
	_check_missions()


func _shop(x: float, kind: String, title: String, col: Color) -> void:
	_mi(lv, _box(Vector3(3.8, 3.2, 0.3)), _mat(Color(0.12, 0.11, 0.12), 0.8), Vector3(x, 1.6, -2.3))
	_mi(lv, _box(Vector3(3.2, 1.0, 0.9)), _mat(Color(0.2, 0.14, 0.1), 0.7), Vector3(x, 0.5, -1.6))
	var aw := _mi(lv, _box(Vector3(3.8, 0.07, 1.2)), _mat(Color(col.r * 0.4, col.g * 0.4, col.b * 0.4), 0.9), Vector3(x, 2.55, -1.8))
	aw.rotation_degrees.x = 10.0
	_mi(lv, _box(Vector3(3.0, 0.08, 0.05)), _glow(col, 3.0), Vector3(x, 2.4, -1.2))
	_label3d(title, Vector3(x, 2.95, -2.1), 72, Color(col.r * 1.6, col.g * 1.6, col.b * 1.6))
	_light(Vector3(x, 2.2, -0.6), col, 1.2, 6.0)
	for k in 4:
		_mi(lv, _box(Vector3(0.25, 0.12, 0.12)), _mat(Color(0.3 + k * 0.1, 0.3, 0.35), 0.4, 0.7), Vector3(x - 1.0 + k * 0.65, 1.06, -1.6))
	interactables.append({"x": x, "kind": kind, "r": 2.0})


func _build_shops() -> void:
	_shop(28.7, "armory", "ARMORY", Color(1.0, 0.5, 0.2))
	_shop(74.5, "market", "BLACK MARKET", Color(0.9, 0.2, 0.3))


# ---------- hide spots ----------

func _build_hide_spots() -> void:
	for x in [42.0, 57.8, 77.6, 84.0]:
		_mi(lv, _box(Vector3(1.8, 1.0, 1.0)), _mat(Color(0.06, 0.18, 0.1), 0.5, 0.5), Vector3(x, 0.5, -1.0))
		var lid := _mi(lv, _box(Vector3(1.9, 0.08, 1.05)), _mat(Color(0.05, 0.14, 0.08), 0.5, 0.5), Vector3(x, 1.04, -1.0))
		lid.rotation_degrees.x = -6.0
		_mi(lv, _box(Vector3(1.2, 0.04, 0.04)), _glow(Color(0.2, 1.0, 0.4), 2.0), Vector3(x, 1.12, -0.48))
		_label3d("HIDE", Vector3(x, 1.5, -0.5), 40, Color(0.4, 1.0, 0.6))
		interactables.append({"x": x, "kind": "hide", "r": 1.6})


func _toggle_hide(spot_x: float) -> void:
	var player = _player()
	var rig = player.get("rig")
	var dogs = lv.get("dogs")
	if not hidden:
		hidden = true
		hide_anchor = player.global_position
		player.set_physics_process(false)
		player.global_position = Vector3(spot_x, -6.0, 0.0)
		if rig != null:
			rig.visible = false
		if dogs != null:
			for d in dogs:
				d.set("chasing", false)
				d.set("ignore_timer", 5.0)
		_banner("HIDDEN\nWait for the dog to leave, then press USE", 3.5)
	else:
		hidden = false
		player.global_position = hide_anchor
		player.velocity = Vector3.ZERO
		player.set_physics_process(true)
		if rig != null:
			rig.visible = true


# ---------- police ----------

func _police_car(x: float, flip: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, 0.0, -1.55)
	if flip:
		root.rotation.y = PI
	lv.add_child(root)
	var white := _mat(Color(0.75, 0.77, 0.8), 0.35, 0.5)
	var dark := _mat(Color(0.05, 0.07, 0.15), 0.35, 0.5)
	var glass := _mat(Color(0.02, 0.03, 0.04), 0.05, 0.9)
	_mi(root, _box(Vector3(3.9, 0.35, 1.7)), dark, Vector3(0, 0.45, 0))
	_mi(root, _box(Vector3(3.9, 0.3, 1.7)), white, Vector3(0, 0.78, 0))
	_mi(root, _box(Vector3(2.0, 0.5, 1.5)), glass, Vector3(-0.2, 1.18, 0))
	_mi(root, _box(Vector3(1.9, 0.08, 1.55)), white, Vector3(-0.2, 1.47, 0))
	var wheel_mat := _mat(Color(0.03, 0.03, 0.03), 0.9)
	for wx in [-1.2, 1.2]:
		for wz in [-0.8, 0.8]:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.33
			cyl.bottom_radius = 0.33
			cyl.height = 0.22
			var wh := _mi(root, cyl, wheel_mat, Vector3(wx, 0.33, wz))
			wh.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var red_mat := _glow(Color(1.0, 0.05, 0.05), 3.0)
	var blue_mat := _glow(Color(0.1, 0.3, 1.0), 3.0)
	_mi(root, _box(Vector3(0.3, 0.1, 0.6)), red_mat, Vector3(-0.2, 1.56, -0.4))
	_mi(root, _box(Vector3(0.3, 0.1, 0.6)), blue_mat, Vector3(-0.2, 1.56, 0.4))
	var rl := OmniLight3D.new()
	rl.position = Vector3(-0.2, 2.0, -0.6)
	rl.light_color = Color(1.0, 0.1, 0.1)
	rl.omni_range = 9.0
	rl.light_energy = 3.0
	root.add_child(rl)
	var bl := OmniLight3D.new()
	bl.position = Vector3(-0.2, 2.0, 0.6)
	bl.light_color = Color(0.2, 0.4, 1.0)
	bl.omni_range = 9.0
	bl.light_energy = 3.0
	root.add_child(bl)
	_label3d("POLICE", Vector3(x, 2.3, -1.4), 44, Color(0.6, 0.8, 1.2))

	if not sfx_cache.has("siren"):
		sfx_cache["siren"] = _make_siren()
	var sp := AudioStreamPlayer3D.new()
	sp.stream = sfx_cache["siren"]
	sp.unit_size = 8.0
	sp.max_distance = 45.0
	sp.volume_db = -8.0
	root.add_child(sp)
	sp.play()
	sirens.append({"red": rl, "blue": bl, "red_mat": red_mat, "blue_mat": blue_mat})


func _build_police() -> void:
	_police_car(-3.0, false)
	_police_car(60.5, true)
	interactables.append({"x": 60.5, "kind": "radio", "r": 2.6})


func _radio() -> void:
	radio_done = true
	_banner("DISPATCH: A gang is hunting with guard dogs in old Kasserine.\nGet to the police station. Do not stop.", 6.0)
	_save()
	_check_missions()


func _build_station() -> void:
	_mi(lv, _box(Vector3(9.0, 7.0, 5.0)), _mat(Color(0.14, 0.15, 0.18), 0.8), Vector3(113.5, 3.5, -5.0))
	_mi(lv, _box(Vector3(2.0, 3.0, 0.1)), _glow(Color(0.5, 0.7, 1.0), 1.5), Vector3(113.5, 1.5, -2.45))
	_label3d("POLICE", Vector3(113.5, 4.6, -2.4), 110, Color(0.6, 0.8, 2.0))
	var beacon := _mi(lv, _box(Vector3(0.5, 0.3, 0.5)), _glow(Color(0.1, 0.3, 1.0), 3.0), Vector3(113.5, 7.2, -5.0))
	beacon.name = "Beacon"
	_light(Vector3(113.5, 5.0, -1.0), Color(0.3, 0.5, 1.0), 2.5, 12.0)


# ---------- evidence ----------

func _build_evidence() -> void:
	var spots := [Vector3(33.0, 0.35, 0.0), Vector3(50.5, 1.4, 0.0), Vector3(90.0, 0.35, 0.0)]
	for i in spots.size():
		if evidence_ids.has(i):
			continue
		var pos: Vector3 = spots[i]
		var a := Area3D.new()
		a.position = pos
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.6
		cs.shape = sh
		a.add_child(cs)
		_mi(a, _box(Vector3(0.3, 0.04, 0.22)), _glow(Color(0.7, 0.9, 1.0), 3.0), Vector3.ZERO)
		var l := OmniLight3D.new()
		l.light_color = Color(0.6, 0.8, 1.0)
		l.light_energy = 0.8
		l.omni_range = 3.0
		a.add_child(l)
		lv.add_child(a)
		a.body_entered.connect(_on_evidence.bind(i, a))


func _on_evidence(body: Node3D, id: int, area: Area3D) -> void:
	if body != _player():
		return
	evidence_ids[id] = true
	area.queue_free()
	_sfx("coin")
	_banner("Evidence folder %d/3" % evidence_ids.size(), 2.5)
	_save()
	_refresh_ui()
	_check_missions()


# ---------- coins ----------

func _coin_positions() -> Array:
	var p: Array = []
	for x in [2.0, 3.2, 4.4]:
		p.append(Vector3(x, 0.6, 0.0))
	p.append(Vector3(6.0, 1.5, 0.0))
	p.append(Vector3(9.0, 1.9, 0.0))
	p.append(Vector3(11.0, 0.6, 0.0))
	p.append(Vector3(12.5, 1.3, 0.0))
	for x in [18.0, 19.0, 20.0, 24.0]:
		p.append(Vector3(x, 0.6, 0.0))
	p.append(Vector3(30.8, 0.6, 0.0))
	p.append(Vector3(33.5, 0.5, 0.0))
	p.append(Vector3(40.5, 1.5, 0.0))
	p.append(Vector3(44.5, 0.6, 0.0))
	p.append(Vector3(46.5, 0.6, 0.0))
	p.append(Vector3(50.5, 1.5, 0.0))
	p.append(Vector3(54.0, 0.6, 0.0))
	p.append(Vector3(59.0, 0.6, 0.0))
	p.append(Vector3(62.0, 0.6, 0.0))
	p.append(Vector3(64.5, 1.6, 0.0))
	p.append(Vector3(65.2, 2.0, 0.0))
	p.append(Vector3(65.9, 1.6, 0.0))
	p.append(Vector3(68.0, 0.6, 0.0))
	p.append(Vector3(76.2, 0.6, 0.0))
	p.append(Vector3(80.0, 2.6, 0.0))
	for x in [83.0, 86.0, 89.0]:
		p.append(Vector3(x, 0.6, 0.0))
	p.append(Vector3(93.5, 1.2, 0.0))
	p.append(Vector3(99.5, 1.2, 0.0))
	for x in [103.0, 105.0, 107.0]:
		p.append(Vector3(x, 0.6, 0.0))
	return p


func _spawn_coins() -> void:
	var pts := _coin_positions()
	for i in pts.size():
		if not collected.has(i):
			_make_coin(pts[i], i)


func _make_coin(pos: Vector3, id: int) -> void:
	var a := Area3D.new()
	a.position = pos
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.4
	cs.shape = sh
	a.add_child(cs)
	var pivot := Node3D.new()
	a.add_child(pivot)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.17
	cyl.bottom_radius = 0.17
	cyl.height = 0.04
	var m := _mi(pivot, cyl, _gold(), Vector3.ZERO)
	m.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	lv.add_child(a)
	a.body_entered.connect(_on_coin.bind(id, a))
	coin_nodes.append({"area": a, "pivot": pivot})


var gold_mat: StandardMaterial3D = null


func _gold() -> StandardMaterial3D:
	if gold_mat == null:
		gold_mat = StandardMaterial3D.new()
		gold_mat.albedo_color = Color(1.0, 0.8, 0.2)
		gold_mat.metallic = 0.8
		gold_mat.roughness = 0.3
		gold_mat.emission_enabled = true
		gold_mat.emission = Color(1.0, 0.7, 0.1)
		gold_mat.emission_energy_multiplier = 1.5
	return gold_mat


func _on_coin(body: Node3D, id: int, area: Area3D) -> void:
	if body != _player():
		return
	coins += 1
	pickups += 1
	if id >= 0:
		collected[id] = true
	area.queue_free()
	_sfx("coin")
	_save()
	_refresh_ui()
	_check_missions()


# ---------- weapons ----------

func _attach_weapons() -> void:
	var rig = _player().get("rig")
	if rig == null:
		return
	var fores = rig.get("arm_l")
	if fores == null:
		return
	var metal := _mat(Color(0.7, 0.72, 0.78), 0.25, 0.9)
	var grip := _mat(Color(0.12, 0.08, 0.05), 0.8)
	var gun_mat := _mat(Color(0.05, 0.05, 0.06), 0.4, 0.8)
	for i in 2:
		var fore: Node3D = fores[i]
		var sword := Node3D.new()
		fore.add_child(sword)
		_mi(sword, _box(Vector3(0.03, 0.12, 0.03)), grip, Vector3(0, -0.28, 0))
		_mi(sword, _box(Vector3(0.14, 0.025, 0.03)), metal, Vector3(0, -0.34, 0))
		_mi(sword, _box(Vector3(0.045, 0.62, 0.012)), metal, Vector3(0, -0.66, 0))
		var gun := Node3D.new()
		fore.add_child(gun)
		_mi(gun, _box(Vector3(0.04, 0.09, 0.2)), gun_mat, Vector3(0, -0.27, 0.08))
		_mi(gun, _box(Vector3(0.03, 0.05, 0.12)), gun_mat, Vector3(0, -0.24, 0.2))
		sword.visible = false
		gun.visible = false
		weapon_nodes.append([sword, gun])


func _swap() -> void:
	var owned: Array = [0]
	if has_sword:
		owned.append(1)
	if has_gun:
		owned.append(2)
	var idx := owned.find(weapon)
	weapon = owned[(idx + 1) % owned.size()]
	var names := ["FISTS", "SWORD", "PISTOL"]
	_banner("Weapon: " + names[weapon], 1.5)
	_save()
	_refresh_ui()


func _dogs() -> Array:
	var d = lv.get("dogs")
	if d == null:
		return []
	return d


func _attack() -> void:
	if cooldown > 0.0 or hidden or shop_open:
		return
	if weapon == 2 and has_gun:
		if ammo <= 0:
			_banner("Out of ammo. Buy more at the BLACK MARKET.", 2.5)
			return
		ammo -= 1
		_shoot()
	elif weapon == 1 and has_sword:
		_sfx("swish")
		_melee()
	else:
		_banner("No weapon equipped. Buy a sword at the ARMORY.", 2.5)
		return
	cooldown = 0.5
	attack_t = attack_dur
	_save()
	_refresh_ui()


func _melee() -> void:
	var player = _player()
	var face: float = player.get("facing")
	var pp: Vector3 = player.global_position
	for d in _dogs():
		var dp: Vector3 = d.global_position
		var dx := dp.x - pp.x
		if signf(dx) == face and absf(dx) < 1.7 and absf(dp.y - pp.y) < 1.2:
			_kill_dog(d)
			return


func _shoot() -> void:
	var player = _player()
	var face: float = player.get("facing")
	var pp: Vector3 = player.global_position
	_sfx("gun")
	shake = 0.35
	var muzzle := Vector3(pp.x + face * 0.7, pp.y + 1.05, 0.0)
	var fl := _light(muzzle, Color(1.0, 0.7, 0.3), 3.0, 5.0)
	get_tree().create_timer(0.08).timeout.connect(fl.queue_free)

	var target = null
	var best := 14.0
	for d in _dogs():
		var dp: Vector3 = d.global_position
		var dx := dp.x - pp.x
		if signf(dx) == face and absf(dx) < best and absf(dp.y + 0.4 - (pp.y + 1.0)) < 1.3:
			best = absf(dx)
			target = d
	var end := Vector3(pp.x + face * 14.0, muzzle.y, 0.0)
	if target != null:
		end = Vector3(target.global_position.x, muzzle.y, 0.0)
	_tracer(muzzle, end)
	if target != null:
		_kill_dog(target)
	# the noise wakes up the dogs nearby
	for d in _dogs():
		if absf(d.global_position.x - pp.x) < 14.0:
			d.set("chasing", true)


func _tracer(a: Vector3, b: Vector3) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(a)
	im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.5)
	mi.material_override = m
	lv.add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)


func _kill_dog(d: Node) -> void:
	kills += 1
	var pos: Vector3 = d.global_position
	var dogs: Array = _dogs()
	dogs.erase(d)
	var vis = d.get("visual")
	if vis != null:
		vis.reparent(lv)
		vis.global_position.y = 0.18
		vis.rotate_object_local(Vector3.RIGHT, deg_to_rad(88.0))
		_dim_eyes(vis)
	d.queue_free()
	_sfx("kill")
	for i in 4:
		_make_coin(pos + Vector3(i * 0.4 - 0.6, 0.6, 0.0), -1)
	_banner("Dog down! +4 coins to grab", 2.0)
	_save()
	_check_missions()


func _dim_eyes(node: Node) -> void:
	if node is MeshInstance3D:
		var m := node.material_override as StandardMaterial3D
		if m != null and m.emission_enabled:
			var m2 := m.duplicate() as StandardMaterial3D
			m2.emission_enabled = false
			node.material_override = m2
	for c in node.get_children():
		_dim_eyes(c)


# ---------- missions ----------

func _mission(i: int) -> Array:
	match i:
		0:
			return ["Collect 10 coins  (%d/10)" % mini(pickups, 10), pickups >= 10, 3]
		1:
			return ["Buy a sword at the ARMORY", has_sword, 5]
		2:
			return ["Find the evidence folders  (%d/3)" % evidence_ids.size(), evidence_ids.size() >= 3, 10]
		3:
			return ["Neutralize a criminal dog  (%d/1)" % mini(kills, 1), kills >= 1, 8]
		4:
			return ["Use the radio on the police car", radio_done, 5]
	return ["Reach the POLICE STATION at the end of the street", false, 0]


func _check_missions() -> void:
	var guard := 0
	while mission_idx < 5 and guard < 6:
		guard += 1
		var m := _mission(mission_idx)
		if not m[1]:
			break
		coins += int(m[2])
		_banner("MISSION COMPLETE\n%s\n+%d coins" % [str(m[0]), int(m[2])], 4.5)
		mission_idx += 1
		_sfx("buy")
	_save()
	_refresh_ui()


# ---------- input ----------

func _hit(pos: Vector2) -> String:
	if pad2 == null:
		return ""
	for b in pad2.layout():
		if (b["pos"] as Vector2).distance_to(pos) < float(b["r"]) * 1.2:
			return b["id"]
	return ""


func _input(event: InputEvent) -> void:
	if lv == null or shop_open or pad2 == null:
		return
	if get_tree().paused:
		return
	if event is InputEventScreenTouch and event.pressed:
		var id := _hit(event.position)
		if id != "":
			pad2.pressed = {id: true}
			pad2.queue_redraw()
			get_tree().create_timer(0.15).timeout.connect(func():
				if pad2 != null:
					pad2.pressed = {}
					pad2.queue_redraw())
			match id:
				"attack":
					_attack()
				"swap":
					_swap()
				"use":
					_use()


func _nearest_interactable():
	var px: float = _player().global_position.x
	var best = null
	var bd := 1000.0
	for it in interactables:
		var d := absf(float(it["x"]) - px)
		if d < float(it["r"]) and d < bd:
			best = it
			bd = d
	return best


func _use() -> void:
	if hidden:
		_toggle_hide(0.0)
		return
	var it = _nearest_interactable()
	if it == null:
		return
	match str(it["kind"]):
		"armory":
			_open_shop("armory")
		"market":
			_open_shop("market")
		"hide":
			_toggle_hide(float(it["x"]))
		"radio":
			_radio()


# ---------- per frame ----------

func _update(delta: float) -> void:
	cooldown = maxf(0.0, cooldown - delta)
	attack_t = maxf(0.0, attack_t - delta)
	shake = maxf(0.0, shake - delta * 1.5)

	# banner fade
	if banner_label != null:
		banner_t -= delta
		banner_label.modulate.a = clampf(banner_t / 0.6, 0.0, 1.0)

	# coins spin
	for c in coin_nodes:
		var pv = c["pivot"]
		if is_instance_valid(pv):
			pv.rotation.y += delta * 3.0

	# sirens flash
	var phase := int(t * 4.0) % 2
	for s in sirens:
		(s["red"] as OmniLight3D).light_energy = 3.0 if phase == 0 else 0.2
		(s["blue"] as OmniLight3D).light_energy = 0.2 if phase == 0 else 3.0
		(s["red_mat"] as StandardMaterial3D).emission_energy_multiplier = 3.0 if phase == 0 else 0.2
		(s["blue_mat"] as StandardMaterial3D).emission_energy_multiplier = 0.2 if phase == 0 else 3.0

	var player = _player()
	if player == null:
		return

	# tips
	var px: float = hide_anchor.x if hidden else player.global_position.x
	for i in TIPS.size():
		if not tips_shown.has(i) and px > float(TIPS[i]["x"]):
			tips_shown[i] = true
			_banner(str(TIPS[i]["text"]), 4.0)
			break

	# USE button context
	if pad2 != null:
		var txt := "USE"
		var ready := false
		if hidden:
			txt = "EXIT"
			ready = true
		else:
			var it = _nearest_interactable()
			if it != null:
				ready = true
				match str(it["kind"]):
					"armory", "market":
						txt = "SHOP"
					"hide":
						txt = "HIDE"
					"radio":
						txt = "RADIO"
		if txt != pad2.use_text or ready != pad2.use_ready:
			pad2.use_text = txt
			pad2.use_ready = ready
			pad2.queue_redraw()

	_update_weapon_visuals(player)


func _update_weapon_visuals(player: Node) -> void:
	if weapon_nodes.is_empty():
		return
	var rig = player.get("rig")
	if rig == null or rig.get("arm_u") == null:
		return
	var facing: float = player.get("facing")
	var near := 0 if facing > 0.0 else 1
	for i in 2:
		var pair: Array = weapon_nodes[i]
		(pair[0] as Node3D).visible = weapon == 1 and has_sword and i == near
		(pair[1] as Node3D).visible = weapon == 2 and has_gun and i == near
	if attack_t > 0.0 and not hidden:
		var p := 1.0 - attack_t / attack_dur
		var arm: Node3D = rig.get("arm_u")[near]
		var fore: Node3D = rig.get("arm_l")[near]
		if weapon == 1:
			arm.rotation.x = lerpf(-2.9, -0.4, p * p)
			fore.rotation.x = -0.3
		else:
			arm.rotation.x = -1.55 - 0.15 * (1.0 - p)
			fore.rotation.x = -0.1

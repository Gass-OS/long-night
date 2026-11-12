extends Node
# Drone: opening cinematic. A drone flies over Kasserine at night, dives toward the hero,
# then blends into the game camera and the game starts. Tap to skip.

const DURATION := 17.0
const P0 := Vector3(-360.0, 330.0, 200.0)
const P1 := Vector3(-220.0, 210.0, 90.0)
const P2 := Vector3(-110.0, 110.0, 40.0)
const P3 := Vector3(-30.0, 40.0, 20.0)
const CITY_CENTER := Vector3(50.0, 10.0, -200.0)

static var played := false


class DroneHud extends Control:
	var alt := 300.0
	var spd := 0.0
	var tc := "00:00:00"
	var blink := 0.0

	func _draw() -> void:
		var sz := get_viewport_rect().size
		var font := ThemeDB.fallback_font
		var c := Color(1, 1, 1, 0.85)
		var m := 56.0
		var x0 := m
		var y0 := m + 20.0
		var x1 := sz.x - m
		var y1 := sz.y - m - 20.0
		var l := 46.0
		draw_polyline(PackedVector2Array([Vector2(x0, y0 + l), Vector2(x0, y0), Vector2(x0 + l, y0)]), c, 3.0)
		draw_polyline(PackedVector2Array([Vector2(x1 - l, y0), Vector2(x1, y0), Vector2(x1, y0 + l)]), c, 3.0)
		draw_polyline(PackedVector2Array([Vector2(x0, y1 - l), Vector2(x0, y1), Vector2(x0 + l, y1)]), c, 3.0)
		draw_polyline(PackedVector2Array([Vector2(x1 - l, y1), Vector2(x1, y1), Vector2(x1, y1 - l)]), c, 3.0)
		var cx := sz.x * 0.5
		var cy := sz.y * 0.5
		draw_line(Vector2(cx - 16, cy), Vector2(cx + 16, cy), Color(1, 1, 1, 0.5), 2.0)
		draw_line(Vector2(cx, cy - 16), Vector2(cx, cy + 16), Color(1, 1, 1, 0.5), 2.0)
		if int(blink * 2.0) % 2 == 0:
			draw_circle(Vector2(x0 + 14, y0 + 40), 8.0, Color(1.0, 0.1, 0.1, 0.95))
		draw_string(font, Vector2(x0 + 32, y0 + 50), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(cx - 90, y0 + 50), tc, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(x1 - 190, y0 + 50), "BAT 87%", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(x0, y1 - 44), "KASSERINE  -  TUNISIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(x0, y1 - 12), "35.17 N    8.84 E", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.65))
		draw_string(font, Vector2(x1 - 260, y1 - 44), "ALT  %d m" % int(alt), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(x1 - 260, y1 - 12), "SPD  %d m/s" % int(spd), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.65))
		draw_string(font, Vector2(cx - 80, y1 - 12), "TAP TO SKIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.4))


var lv: Node = null
var age := 0
var active := false
var t := 0.0
var dcam: Camera3D = null
var hud_layer: CanvasLayer = null
var hud: DroneHud = null
var cover_layer: CanvasLayer = null
var cover: ColorRect = null
var city_root: Node3D = null
var rotor: AudioStreamPlayer = null
var saved_fog := 0.0
var saved_vfog := false
var last_pos := Vector3.ZERO
var layer_timer := 0.0


func _process(delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	if cs.get("main_box") != null or cs.name == "Intro":
		played = false
		lv = null
		return
	var stage1 := cs.get("player") != null and cs.get("env") != null and cs.get("cam") != null and cs.get("weather") != null and cs.get("dogs") != null and cs.get("stage") == null
	if not stage1:
		lv = null
		return
	if lv != cs:
		lv = cs
		age = 0
		active = false
	age += 1
	if age == 1 and not played:
		_begin(cs)
	elif active:
		_fly(delta)


func _input(event: InputEvent) -> void:
	if active and t > 1.0 and event is InputEventScreenTouch and event.pressed:
		_end(true)


# ---------- helpers ----------

func _hide_layers(hide: bool) -> void:
	for c in lv.get_children():
		if c is CanvasLayer and c != hud_layer and c != cover_layer:
			c.visible = not hide


func _mat(color: Color, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _multimesh(parent: Node, xf: Array, size: Vector3, mat: Material, colors: Array) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() == xf.size()
	mm.mesh = _box(size)
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ---------- the city seen from the sky ----------

func _build_city(cs: Node) -> void:
	city_root = Node3D.new()
	cs.add_child(city_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	_mi(city_root, _box(Vector3(1800.0, 1.0, 1800.0)), _mat(Color(0.03, 0.03, 0.035)), Vector3(60.0, -1.2, -400.0))

	var xf: Array = []
	var colors: Array = []
	var lit: Array = []
	var lamps: Array = []
	var gx := -320.0
	while gx < 420.0:
		var gz := -75.0
		while gz > -360.0:
			if rng.randf() < 0.88:
				var w := rng.randf_range(7.0, 11.0)
				var d := rng.randf_range(7.0, 11.0)
				var h := rng.randf_range(5.0, 20.0)
				if rng.randf() < 0.08:
					h += rng.randf_range(10.0, 28.0)
				var cx := gx + rng.randf_range(-1.5, 1.5)
				var cz := gz + rng.randf_range(-1.5, 1.5)
				xf.append(Transform3D(Basis().scaled(Vector3(w, h, d)), Vector3(cx, h / 2.0, cz)))
				var tone := rng.randf_range(0.1, 0.24)
				colors.append(Color(tone, tone * 0.94, tone * 0.82))
				if rng.randf() < 0.5:
					for k in rng.randi_range(2, 6):
						lit.append(Transform3D(Basis(), Vector3(cx + rng.randf_range(-w * 0.4, w * 0.4), rng.randf_range(2.0, maxf(h - 1.0, 2.5)), cz + d / 2.0 + 0.05)))
			lamps.append(Transform3D(Basis(), Vector3(gx + 7.0, 4.5, gz + 7.0)))
			gz -= 14.0
		gx += 14.0
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 1.0
	_multimesh(city_root, xf, Vector3(1, 1, 1), bmat, colors)
	_multimesh(city_root, lit, Vector3(1.2, 1.6, 0.1), _glow(Color(1.0, 0.72, 0.3), 3.0), [])
	_multimesh(city_root, lamps, Vector3(0.6, 0.6, 0.6), _glow(Color(1.0, 0.7, 0.35), 4.0), [])

	# minarets
	var wall := _mat(Color(0.3, 0.27, 0.22))
	for mp in [Vector2(-60.0, -180.0), Vector2(140.0, -250.0), Vector2(250.0, -120.0), Vector2(0.0, -310.0)]:
		_mi(city_root, _box(Vector3(3.0, 44.0, 3.0)), wall, Vector3(mp.x, 22.0, mp.y))
		_mi(city_root, _box(Vector3(4.2, 0.8, 4.2)), wall, Vector3(mp.x, 37.0, mp.y))
		_mi(city_root, _box(Vector3(4.4, 0.35, 4.4)), _glow(Color(0.1, 1.0, 0.5), 2.5), Vector3(mp.x, 37.6, mp.y))
		_mi(city_root, _box(Vector3(2.4, 6.0, 2.4)), wall, Vector3(mp.x, 47.0, mp.y))
		var dome := SphereMesh.new()
		dome.radius = 1.6
		dome.height = 1.6
		dome.is_hemisphere = true
		_mi(city_root, dome, _mat(Color(0.2, 0.34, 0.3), 0.4), Vector3(mp.x, 50.0, mp.y))

	# Mount Chaambi in the distance
	var rock := _mat(Color(0.035, 0.04, 0.055))
	var big := PrismMesh.new()
	big.size = Vector3(900.0, 200.0, 140.0)
	_mi(city_root, big, rock, Vector3(40.0, 80.0, -620.0))
	var small := PrismMesh.new()
	small.size = Vector3(500.0, 120.0, 100.0)
	_mi(city_root, small, rock, Vector3(-380.0, 40.0, -520.0))


func _make_rotor() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 8
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		var hum := sin(TAU * 118.0 * tt) * 0.22 + sin(TAU * 236.0 * tt) * 0.1
		var am := 0.8 + 0.2 * sin(TAU * 18.0 * tt)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.3
		var v := (hum * am + lp * 0.18) * 0.8
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


# ---------- flight ----------

func _begin(cs: Node) -> void:
	played = true
	var player = cs.get("player")
	var env: Environment = cs.get("env")

	cover_layer = CanvasLayer.new()
	cover_layer.layer = 60
	cs.add_child(cover_layer)
	cover = ColorRect.new()
	cover.color = Color.BLACK
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_layer.add_child(cover)

	hud_layer = CanvasLayer.new()
	hud_layer.layer = 50
	cs.add_child(hud_layer)
	hud = DroneHud.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud)

	player.set_physics_process(false)
	_hide_layers(true)
	saved_fog = env.fog_density
	saved_vfog = env.volumetric_fog_enabled
	env.fog_density = 0.0012
	env.volumetric_fog_enabled = false
	_build_city(cs)

	dcam = Camera3D.new()
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_near_enabled = false
	attrs.exposure_multiplier = 2.2
	dcam.attributes = attrs
	dcam.fov = 72.0
	dcam.far = 3000.0
	cs.add_child(dcam)
	dcam.global_position = P0
	dcam.look_at(CITY_CENTER, Vector3.UP)
	dcam.make_current()
	last_pos = P0

	rotor = AudioStreamPlayer.new()
	rotor.stream = _make_rotor()
	rotor.volume_db = -12.0
	cs.add_child(rotor)
	rotor.play()

	t = 0.0
	active = true
	var tw := create_tween()
	tw.tween_property(cover, "modulate:a", 0.0, 1.0)


func _fly(delta: float) -> void:
	t += delta
	layer_timer -= delta
	if layer_timer <= 0.0:
		layer_timer = 0.2
		_hide_layers(true)
	var u := clampf(t / DURATION, 0.0, 1.0)
	var cam: Camera3D = lv.get("cam")
	var player = lv.get("player")
	var end_t := cam.global_transform
	var pts := [P0, P0, P1, P2, P3, end_t.origin, end_t.origin]
	var s := u * u * (3.0 - 2.0 * u)
	var f := s * 4.0
	var i := mini(int(f), 3)
	var w := f - i
	var a: Vector3 = pts[1 + i]
	var b: Vector3 = pts[2 + i]
	var pre: Vector3 = pts[i]
	var post: Vector3 = pts[3 + i]
	var pos := a.cubic_interpolate(b, pre, post, w)
	var bw := smoothstep(0.86, 1.0, u)
	pos += Vector3(sin(t * 37.0) * 0.05, sin(t * 29.0) * 0.04, 0.0) * (1.0 - bw)

	var lw := smoothstep(0.25, 0.85, u)
	var focus := CITY_CENTER.lerp(player.global_position + Vector3(0.0, 1.1, 0.0), lw)
	var dir := focus - pos
	if dir.length() < 0.5:
		dir = Vector3(0.0, 0.0, -1.0)
	var basis := Basis.looking_at(dir, Vector3.UP)
	var bank := sin(u * PI * 2.0) * 0.07 * (1.0 - bw)
	basis = basis.rotated(basis.z, bank)
	var tr := Transform3D(basis, pos)
	tr = tr.interpolate_with(end_t, bw)
	dcam.global_transform = tr
	dcam.fov = lerpf(72.0, cam.fov, bw)

	hud.alt = pos.y
	hud.spd = (pos - last_pos).length() / maxf(delta, 0.001)
	hud.blink = t
	hud.tc = "00:%02d:%02d" % [int(t), int((t - floor(t)) * 25.0)]
	hud.queue_redraw()
	last_pos = pos
	if t > DURATION - 2.0:
		rotor.volume_db = lerpf(-12.0, -50.0, (t - (DURATION - 2.0)) / 2.0)
	if u >= 1.0:
		_end(false)


func _end(skipped: bool) -> void:
	if not active:
		return
	active = false
	var cam: Camera3D = lv.get("cam")
	var player = lv.get("player")
	var env: Environment = lv.get("env")
	if skipped:
		cover.modulate.a = 1.0
	cam.make_current()
	if is_instance_valid(dcam):
		dcam.queue_free()
	if is_instance_valid(city_root):
		city_root.queue_free()
	env.fog_density = saved_fog
	env.volumetric_fog_enabled = saved_vfog
	_hide_layers(false)
	if is_instance_valid(hud_layer):
		hud_layer.queue_free()
	if is_instance_valid(rotor):
		rotor.stop()
		rotor.queue_free()
	player.set_physics_process(true)
	var tw := create_tween()
	tw.tween_property(cover, "modulate:a", 0.0, 0.5)
	tw.tween_callback(cover_layer.queue_free)

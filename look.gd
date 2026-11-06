extends Node
# "Look" layer: visual upgrade applied on top of whatever level.gd builds.

const S = preload("res://settings.gd")
const CFG := "user://look.cfg"
const RAIN_NAMES := ["OFF", "LIGHT", "NORMAL"]

const CA_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - vec2(0.5);
	float k = dot(d, d) * 0.006;
	vec3 col;
	col.r = texture(screen_tex, uv + d * k).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - d * k).b;
	COLOR = vec4(col, 1.0);
}
"""

var rain_level := 1
var lv: Node = null
var menu_done: Node = null
var t := 0.0
var look_x := 0.0
var v_off := 0.0
var shake := 0.0
var last_flash := 0.0
var bag: Node3D = null
var hood: Node3D = null
var glb_active := false


func _ready() -> void:
	S.load_cfg()
	var cf := ConfigFile.new()
	if cf.load(CFG) == OK:
		rain_level = int(cf.get_value("look", "rain", 1))


func _save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("look", "rain", rain_level)
	cf.save(CFG)


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
			bag = null
			hood = null
			glb_active = false
			_decorate(cs)
		_update(delta)
	else:
		lv = null


# ---------- menu ----------

func _inject_menu(menu: Node) -> void:
	var box = menu.get("settings_box")
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(520, 84)
	btn.add_theme_font_size_override("font_size", 36)
	btn.text = "RAIN: " + RAIN_NAMES[rain_level]
	btn.pressed.connect(func():
		rain_level = (rain_level + 1) % 3
		_save_cfg()
		btn.text = "RAIN: " + RAIN_NAMES[rain_level])
	box.add_child(btn)
	box.move_child(btn, maxi(box.get_child_count() - 2, 0))

	var about = menu.get("about_box")
	var credit := Label.new()
	credit.text = "Textures: Poly Haven (CC0)  |  polyhaven.com"
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	credit.add_theme_font_size_override("font_size", 22)
	credit.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	about.add_child(credit)
	about.move_child(credit, maxi(about.get_child_count() - 2, 0))


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


func _sph(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s


func _mi(parent: Node, mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _pbr(set_name: String, tint: Color, tile: float, rough_mul := 0.9) -> StandardMaterial3D:
	var base := "res://assets/tex/%s/" % set_name
	if not ResourceLoader.exists(base + "diff.jpg"):
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "diff.jpg")
	m.albedo_color = tint
	if ResourceLoader.exists(base + "rough.jpg"):
		m.roughness_texture = load(base + "rough.jpg")
	m.roughness = rough_mul
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(tile, tile, tile)
	return m


func _swap(mi: MeshInstance3D, mat: StandardMaterial3D, tint_k := 1.0) -> void:
	if mat == null:
		return
	var m := mat.duplicate() as StandardMaterial3D
	var old := mi.material_override as StandardMaterial3D
	if old != null:
		m.normal_enabled = old.normal_enabled
		m.normal_texture = old.normal_texture
		m.normal_scale = old.normal_scale
	m.albedo_color = Color(m.albedo_color.r * tint_k, m.albedo_color.g * tint_k, m.albedo_color.b * tint_k)
	mi.material_override = m


func _first_mesh(node: Node) -> MeshInstance3D:
	for c in node.get_children():
		if c is MeshInstance3D:
			return c
	return null


# ---------- decorate the level once ----------

func _decorate(level: Node) -> void:
	_apply_rain(level)
	_upgrade_env(level)
	var buildings := _scan(level)
	_apply_pbr(level)
	_extend_ground(level)
	_street_dressing(level, buildings)
	if S.quality >= 1:
		for x in [13.0, 47.0, 70.0]:
			_steam(level, Vector3(x, 0.05, -1.0))
		_post_fx(level)
	_use_glb(level)
	if not glb_active:
		_dress_rig(level)


func _apply_rain(level: Node) -> void:
	var w = level.get("weather")
	var rain = w.get("rain")
	var audio = level.get("audio")
	if rain != null:
		if rain_level == 0:
			rain.emitting = false
			rain.visible = false
		else:
			rain.visible = true
			rain.emitting = true
			var base_amount := 320 if rain_level == 1 else 700
			var mult := [0.6, 0.85, 1.0][S.quality]
			rain.amount = int(base_amount * mult)
			var pm := rain.draw_pass_1 as PrimitiveMesh
			if pm != null:
				var m := pm.material as StandardMaterial3D
				if m != null:
					m.albedo_color = Color(0.72, 0.8, 0.95, 0.16 if rain_level == 1 else 0.26)
	if audio != null and audio.get_child_count() > 0:
		var rp := audio.get_child(0) as AudioStreamPlayer
		if rp != null:
			rp.volume_db = [-80.0, -25.0, -19.0][rain_level]


func _upgrade_env(level: Node) -> void:
	var env: Environment = level.get("env")
	if env == null:
		return
	if S.quality >= 2:
		env.ssr_enabled = true
		env.ssr_max_steps = 64
		env.ssr_fade_in = 0.15
		env.ssr_fade_out = 2.0
		env.ssr_depth_tolerance = 0.2
	env.volumetric_fog_density = 0.028
	env.adjustment_saturation = 0.58


func _scan(level: Node) -> Array:
	var out: Array = []
	for ch in level.get_children():
		if ch is MeshInstance3D and ch.mesh is BoxMesh:
			var s: Vector3 = (ch.mesh as BoxMesh).size
			if absf(s.z - 2.0) < 0.01 and s.y >= 4.0 and s.x >= 3.0 and s.x <= 5.1 and ch.position.z < -4.0:
				out.append({"node": ch, "pos": ch.position, "size": s})
	return out


func _apply_pbr(level: Node) -> void:
	var ground := _pbr("asphalt_02", Color(0.55, 0.55, 0.6), 0.45, 0.9)
	var wall := _pbr("painted_concrete_02", Color(0.42, 0.42, 0.47), 0.5)
	var concrete := _pbr("brushed_concrete_2", Color(0.5, 0.5, 0.52), 0.5)
	for ch in level.get_children():
		if ch is StaticBody3D:
			var mi := _first_mesh(ch)
			if mi == null or not (mi.mesh is BoxMesh):
				continue
			var s: Vector3 = (mi.mesh as BoxMesh).size
			if absf(ch.position.y + 0.5) < 0.01 and absf(s.y - 1.0) < 0.01:
				_swap(mi, ground)
			else:
				_swap(mi, concrete)
		elif ch is MeshInstance3D and ch.mesh is BoxMesh:
			var s2: Vector3 = (ch.mesh as BoxMesh).size
			if absf(s2.z - 2.0) < 0.01 and s2.y >= 4.0 and ch.position.z < -4.0:
				var old := ch.material_override as StandardMaterial3D
				var k := 1.0
				if old != null:
					k = clampf(old.albedo_color.r / 0.288, 0.7, 1.3)
				_swap(ch, wall, k)


func _extend_ground(level: Node) -> void:
	var mat := _pbr("cobblestone_floor_001", Color(0.45, 0.45, 0.5), 0.6, 0.9)
	if mat == null:
		mat = _mat(Color(0.1, 0.095, 0.09), 0.5)
	_mi(level, _box(Vector3(140.0, 1.0, 8.0)), mat, Vector3(47.0, -0.5, -6.0))
	_mi(level, _box(Vector3(140.0, 1.0, 4.0)), mat, Vector3(47.0, -0.5, 4.0))
	var curb := _mat(Color(0.14, 0.14, 0.15), 0.7)
	_mi(level, _box(Vector3(140.0, 0.14, 0.2)), curb, Vector3(47.0, 0.07, -2.1))


func _street_dressing(level: Node, buildings: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var shutter := _mat(Color(0.12, 0.12, 0.14), 0.45, 0.6)
	var awnings := [
		_mat(Color(0.35, 0.08, 0.07), 0.9),
		_mat(Color(0.08, 0.22, 0.12), 0.9),
		_mat(Color(0.08, 0.14, 0.3), 0.9),
		_mat(Color(0.3, 0.25, 0.1), 0.9),
	]
	var neon_cols := [Color(0.1, 0.9, 1.0), Color(1.0, 0.2, 0.3), Color(0.3, 1.0, 0.5), Color(1.0, 0.7, 0.2)]
	var metal := _mat(Color(0.1, 0.1, 0.11), 0.6, 0.4)
	var lights := 0
	for b in buildings:
		var c: Vector3 = b["pos"]
		var size: Vector3 = b["size"]
		var w := size.x
		var h := size.y
		var fz := c.z + 1.0
		if rng.randf() < 0.55:
			var sw := w * 0.7
			_mi(level, _box(Vector3(sw, 2.0, 0.08)), shutter, Vector3(c.x, 1.0, fz + 0.05))
			var aw := _mi(level, _box(Vector3(sw + 0.2, 0.06, 0.9)), awnings[rng.randi() % awnings.size()], Vector3(c.x, 2.35, fz + 0.45))
			aw.rotation_degrees.x = 12.0
			if rng.randf() < 0.6:
				var col: Color = neon_cols[rng.randi() % neon_cols.size()]
				_mi(level, _box(Vector3(sw * 0.6, 0.22, 0.04)), _glow(col, 3.5), Vector3(c.x, 2.75, fz + 0.06))
				if lights < 6:
					lights += 1
					var ol := OmniLight3D.new()
					ol.position = Vector3(c.x, 2.4, fz + 0.9)
					ol.omni_range = 3.5
					ol.light_energy = 0.6
					ol.light_color = col
					level.add_child(ol)
		if rng.randf() < 0.5:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.28
			cyl.bottom_radius = 0.03
			cyl.height = 0.14
			var dish := _mi(level, cyl, metal, Vector3(c.x + rng.randf_range(-w / 3.0, w / 3.0), rng.randf_range(2.8, maxf(h - 1.0, 3.0)), fz + 0.12))
			dish.rotation_degrees = Vector3(-60.0, 0.0, 0.0)
		if rng.randf() < 0.3:
			for k in range(5):
				_mi(level, _box(Vector3(0.025, 0.9, 0.025)), metal, Vector3(c.x - w / 2.0 + 0.3 + k * 0.25, h + 0.45, c.z + 0.8))

	for x in [9.0, 44.0, 59.0, 75.0, 88.0, 104.0]:
		var cols := [Color(0.12, 0.12, 0.14), Color(0.2, 0.08, 0.07), Color(0.1, 0.13, 0.15)]
		_car(level, Vector3(x, 0.0, -1.35), cols[rng.randi() % cols.size()], rng.randf() < 0.5)


func _car(parent: Node, pos: Vector3, color: Color, flip: bool) -> void:
	var root := Node3D.new()
	root.position = pos
	if flip:
		root.rotation.y = PI
	parent.add_child(root)
	var body_mat := _mat(color, 0.35, 0.6)
	var glass := _mat(Color(0.02, 0.03, 0.04), 0.05, 0.9)
	_mi(root, _box(Vector3(3.8, 0.55, 1.6)), body_mat, Vector3(0, 0.55, 0))
	_mi(root, _box(Vector3(2.0, 0.5, 1.45)), glass, Vector3(-0.2, 1.05, 0))
	_mi(root, _box(Vector3(1.9, 0.08, 1.5)), body_mat, Vector3(-0.2, 1.33, 0))
	var wheel_mat := _mat(Color(0.03, 0.03, 0.03), 0.9)
	for wx in [-1.2, 1.2]:
		for wz in [-0.78, 0.78]:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.33
			cyl.bottom_radius = 0.33
			cyl.height = 0.22
			var wheel := _mi(root, cyl, wheel_mat, Vector3(wx, 0.33, wz))
			wheel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var tail := _glow(Color(1.0, 0.05, 0.03), 3.0)
	var head := _glow(Color(1.0, 0.9, 0.7), 1.2)
	for z in [-0.5, 0.5]:
		_mi(root, _box(Vector3(0.05, 0.14, 0.4)), tail, Vector3(-1.92, 0.65, z))
		_mi(root, _box(Vector3(0.05, 0.14, 0.4)), head, Vector3(1.92, 0.62, z))


func _steam(level: Node, pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = 24
	p.lifetime = 3.5
	p.preprocess = 3.0
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 8, 6))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 18.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.15, 0.1, 0.0)
	pm.scale_min = 0.8
	pm.scale_max = 1.8
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.3, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm

	var rg := Gradient.new()
	rg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	rg.offsets = PackedFloat32Array([0.0, 1.0])
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(1.0, 0.5)
	rt.width = 64
	rt.height = 64

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.6, 0.65, 0.7, 0.35)
	m.albedo_texture = rt
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	q.material = m
	p.draw_pass_1 = q
	level.add_child(p)


func _post_fx(level: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	level.add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = CA_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	rect.material = sm
	layer.add_child(rect)


# ---------- character ----------

func _use_glb(level: Node) -> void:
	var glb = load("res://character_glb.gd")
	if glb == null or not glb.call("available"):
		return
	var player = level.get("player")
	var new_rig := Node3D.new()
	new_rig.set_script(glb)
	player.add_child(new_rig)
	if not new_rig.get("ok"):
		new_rig.queue_free()
		return
	var old = player.get("rig")
	if old != null:
		old.queue_free()
	player.set("rig", new_rig)
	if level.has_method("_on_footstep"):
		new_rig.footstep.connect(level._on_footstep)
	glb_active = true


func _dress_rig(level: Node) -> void:
	var player = level.get("player")
	var rig = player.get("rig")
	if rig == null or rig.get("chest") == null or rig.get("head") == null:
		return
	var chest: Node3D = rig.get("chest")
	var neck: Node3D = rig.get("neck")
	var head: Node3D = rig.get("head")
	var foot: Array = rig.get("foot")
	var red := _mat(Color(0.5, 0.07, 0.06), 0.9)
	var dark_red := _mat(Color(0.36, 0.05, 0.045), 0.9)
	var black := _mat(Color(0.01, 0.01, 0.012), 0.5)

	hood = Node3D.new()
	hood.position = Vector3(0, 0.03, -0.075)
	neck.add_child(hood)
	var hm := _mi(hood, _sph(0.105), red, Vector3.ZERO)
	hm.scale = Vector3(1.15, 0.8, 0.85)

	_mi(chest, _box(Vector3(0.17, 0.08, 0.02)), dark_red, Vector3(0, 0.03, 0.118))

	bag = Node3D.new()
	bag.position = Vector3(0, 0.1, -0.13)
	chest.add_child(bag)
	_mi(bag, _box(Vector3(0.2, 0.26, 0.1)), _mat(Color(0.12, 0.11, 0.09), 0.8), Vector3.ZERO)
	_mi(bag, _box(Vector3(0.16, 0.1, 0.03)), _mat(Color(0.09, 0.08, 0.07), 0.8), Vector3(0, -0.05, -0.06))
	for sx in [-0.065, 0.065]:
		_mi(chest, _box(Vector3(0.03, 0.24, 0.02)), _mat(Color(0.08, 0.07, 0.06), 0.8), Vector3(sx, 0.09, 0.117))

	for sx in [-0.036, 0.036]:
		_mi(head, _sph(0.011), black, Vector3(sx, 0.105, 0.093))
	for tuft in [Vector3(0.0, 0.19, 0.02), Vector3(0.05, 0.175, -0.03), Vector3(-0.05, 0.178, -0.02)]:
		_mi(head, _sph(0.03), black, tuft)

	var sole := _mat(Color(0.75, 0.75, 0.72), 0.8)
	for f in foot:
		_mi(f, _box(Vector3(0.09, 0.016, 0.205)), sole, Vector3(0, -0.062, 0.05))


# ---------- per frame ----------

func _update(delta: float) -> void:
	var cam: Camera3D = lv.get("cam")
	var player = lv.get("player")
	var weather = lv.get("weather")
	if cam == null or player == null:
		return
	var face: float = player.get("facing")
	var crouch: bool = player.get("crouching")
	look_x = lerpf(look_x, face * 1.8, clampf(delta * 1.4, 0.0, 1.0))
	v_off = lerpf(v_off, -0.25 if crouch else 0.0, clampf(delta * 3.0, 0.0, 1.0))

	var fl := 0.0
	if weather != null:
		fl = float(weather.get("flash"))
	if fl > 0.8 and last_flash <= 0.8:
		shake = 0.7
	last_flash = fl
	shake = maxf(0.0, shake - delta * 1.6)

	cam.h_offset = look_x + sin(t * 43.0) * shake * 0.12
	cam.v_offset = v_off + cos(t * 37.0) * shake * 0.1
	cam.rotation.z = sin(t * 0.5) * 0.003 + sin(t * 47.0) * shake * 0.004

	if not glb_active and bag != null and is_instance_valid(bag) and hood != null:
		var rig = player.get("rig")
		if rig != null and rig.get("phase") != null:
			var ph: float = rig.get("phase")
			var kf: float = float(rig.get("gait")) / 0.85
			var vy: float = player.velocity.y
			var lag := -clampf(vy * 0.02, -0.15, 0.15)
			bag.rotation.x = lag + sin(ph * 2.0 + 1.0) * 0.05 * kf
			hood.rotation.x = lag * 0.6 + sin(ph * 2.0 + 0.5) * 0.04 * kf

extends Node
# Look2: lighting, sky, camera and surface pass. Works on top of any level.gd that
# exposes player / env / cam / weather (and optionally lamp_lights).

const S = preload("res://settings.gd")

var lv: Node = null
var age := 0
var t := 0.0
var sky_root: Node3D = null
var cloud_mat: StandardMaterial3D = null
var spots: Array = []
var tv_lights: Array = []
var ripples: GPUParticles3D = null
var radial_tex: GradientTexture2D = null


func _process(delta: float) -> void:
	t += delta
	var cs := get_tree().current_scene
	if cs == null:
		return
	if cs.get("player") != null and cs.get("env") != null and cs.get("cam") != null and cs.get("weather") != null:
		if lv != cs:
			lv = cs
			age = 0
			spots.clear()
			tv_lights.clear()
			sky_root = null
			cloud_mat = null
			ripples = null
		age += 1
		if age == 4:
			_setup(cs)
		elif age > 4:
			_update(delta)
	else:
		lv = null


func _setup(level: Node) -> void:
	var q: int = S.quality
	_camera(level)
	_env_tune(level, q)
	_lamps(level, q)
	_window_lights(level, q)
	_player_light(level)
	_rim(level)
	_sky(level)
	_rain_tune(level, q)
	_surfaces(level)
	_letterbox(level)


# ---------- helpers ----------

func _radial() -> GradientTexture2D:
	if radial_tex == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.25), Color(1, 1, 1, 0.0)])
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		radial_tex = GradientTexture2D.new()
		radial_tex.gradient = g
		radial_tex.fill = GradientTexture2D.FILL_RADIAL
		radial_tex.fill_from = Vector2(0.5, 0.5)
		radial_tex.fill_to = Vector2(1.0, 0.5)
		radial_tex.width = 128
		radial_tex.height = 128
	return radial_tex


func _halo(parent: Node, pos: Vector3, size: float, color: Color) -> StandardMaterial3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _radial()
	m.albedo_color = color
	m.disable_fog = true
	quad.material = m
	mi.mesh = quad
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return m


# ---------- camera and environment ----------

func _camera(level: Node) -> void:
	var cam: Camera3D = level.get("cam")
	cam.fov = 55.0
	var attrs := cam.attributes as CameraAttributesPractical
	if attrs != null:
		attrs.exposure_multiplier = 1.25


func _env_tune(level: Node, q: int) -> void:
	var env: Environment = level.get("env")
	if env == null:
		return
	env.volumetric_fog_density = 0.036
	env.glow_intensity = 1.1
	env.glow_bloom = 0.15
	env.glow_hdr_threshold = 0.9
	if q >= 2:
		RenderingServer.environment_set_volumetric_fog_volume_size(96, 96)


# ---------- lights ----------

func _lamps(level: Node, q: int) -> void:
	var lamps = level.get("lamp_lights")
	var bases = level.get("lamp_base")
	if lamps == null or bases == null:
		return
	for i in lamps.size():
		var o: OmniLight3D = lamps[i]
		var p := o.position
		var spot := SpotLight3D.new()
		spot.position = Vector3(p.x, 3.3, -1.4)
		spot.rotation_degrees = Vector3(-120.0, 0.0, 0.0)
		spot.spot_angle = 55.0
		spot.spot_range = 8.0
		spot.spot_attenuation = 1.2
		spot.light_energy = 6.0
		spot.light_color = Color(1.0, 0.72, 0.4)
		spot.light_volumetric_fog_energy = 2.5
		spot.shadow_enabled = q >= 2
		level.add_child(spot)
		var hm := _halo(level, Vector3(p.x, 3.3, -1.3), 1.8, Color(1.0, 0.75, 0.4, 0.55))
		spots.append({"spot": spot, "omni": o, "sb": 6.0, "ob": float(bases[i]), "halo": hm})


func _window_lights(level: Node, q: int) -> void:
	var count: int = [0, 4, 8][q]
	if count == 0:
		return
	for ch in level.get_children():
		if ch is MultiMeshInstance3D:
			var mat := ch.material_override as StandardMaterial3D
			if mat == null or not mat.emission_enabled:
				continue
			var mm: MultiMesh = ch.multimesh
			var n := mm.instance_count
			if n == 0:
				break
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for k in count:
				var idx := rng.randi() % n
				var pos := mm.get_instance_transform(idx).origin
				var l := OmniLight3D.new()
				l.position = pos + Vector3(0, 0, 0.7)
				l.omni_range = 3.8
				l.light_energy = 0.7
				l.light_color = Color(1.0, 0.72, 0.4)
				l.light_volumetric_fog_energy = 1.5
				level.add_child(l)
				if k % 3 == 0:
					l.light_color = Color(0.5, 0.7, 1.0)
					tv_lights.append(l)
			break


func _player_light(level: Node) -> void:
	var player = level.get("player")
	var l := OmniLight3D.new()
	l.position = Vector3(0.4, 1.9, 1.8)
	l.omni_range = 5.5
	l.light_energy = 0.8
	l.light_color = Color(0.7, 0.78, 1.0)
	l.light_volumetric_fog_energy = 0.3
	player.add_child(l)


func _rim(level: Node) -> void:
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30.0, 180.0, 0.0)
	rim.light_energy = 0.4
	rim.light_color = Color(0.5, 0.6, 1.0)
	rim.light_volumetric_fog_energy = 0.5
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	level.add_child(rim)


# ---------- sky: moon, clouds, city glow ----------

func _sky(level: Node) -> void:
	sky_root = Node3D.new()
	level.add_child(sky_root)

	# City glow on the horizon
	var gg := Gradient.new()
	gg.colors = PackedColorArray([Color(0.55, 0.3, 0.12, 0.4), Color(0.3, 0.18, 0.1, 0.12), Color(0, 0, 0, 0)])
	gg.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var gt := GradientTexture2D.new()
	gt.gradient = gg
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0, 1)
	gt.fill_to = Vector2(0, 0)
	gt.width = 32
	gt.height = 128
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.albedo_texture = gt
	glow_mat.disable_fog = true
	var glow_quad := QuadMesh.new()
	glow_quad.size = Vector2(320, 36)
	glow_quad.material = glow_mat
	var glow := MeshInstance3D.new()
	glow.mesh = glow_quad
	glow.position = Vector3(0, 4, -102)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(glow)

	# Moon
	var moon_mat := StandardMaterial3D.new()
	moon_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	moon_mat.albedo_color = Color(0.85, 0.9, 1.0)
	moon_mat.emission_enabled = true
	moon_mat.emission = Color(0.85, 0.9, 1.0)
	moon_mat.emission_energy_multiplier = 2.5
	moon_mat.disable_fog = true
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 3.5
	moon_mesh.height = 7.0
	moon_mesh.material = moon_mat
	var moon := MeshInstance3D.new()
	moon.mesh = moon_mesh
	moon.position = Vector3(-22, 44, -100)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(moon)
	_halo(sky_root, Vector3(-22, 44, -99), 36.0, Color(0.45, 0.55, 0.9, 0.35))

	# Slow clouds
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.012
	n.fractal_octaves = 4
	n.seed = 17
	var cg := Gradient.new()
	cg.colors = PackedColorArray([Color(0.02, 0.03, 0.05, 0.0), Color(0.02, 0.03, 0.05, 0.0), Color(0.015, 0.02, 0.035, 0.9)])
	cg.offsets = PackedFloat32Array([0.0, 0.5, 0.8])
	var nt := NoiseTexture2D.new()
	nt.noise = n
	nt.width = 1024
	nt.height = 256
	nt.seamless = true
	nt.color_ramp = cg
	cloud_mat = StandardMaterial3D.new()
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.albedo_texture = nt
	cloud_mat.uv1_scale = Vector3(2, 1, 1)
	cloud_mat.disable_fog = true
	var cloud_quad := QuadMesh.new()
	cloud_quad.size = Vector2(260, 40)
	cloud_quad.material = cloud_mat
	var clouds := MeshInstance3D.new()
	clouds.mesh = cloud_quad
	clouds.position = Vector3(0, 34, -98)
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(clouds)


# ---------- rain: finer drops + ground ripples ----------

func _rain_tune(level: Node, q: int) -> void:
	var w = level.get("weather")
	var rain = w.get("rain")
	if rain != null:
		var bm := rain.draw_pass_1 as BoxMesh
		if bm != null:
			bm.size = Vector3(0.008, 0.38, 0.008)
			var m := bm.material as StandardMaterial3D
			if m != null:
				m.albedo_color.a = m.albedo_color.a * 0.8
		rain.amount = int(rain.amount * 0.7)

	var amount: int = [0, 80, 140][q]
	if amount == 0:
		return
	ripples = GPUParticles3D.new()
	ripples.amount = amount
	ripples.lifetime = 0.5
	ripples.local_coords = false
	ripples.visibility_aabb = AABB(Vector3(-12, -1, -4), Vector3(24, 2, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(9.0, 0.0, 1.8)
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.0
	pm.initial_velocity_max = 0.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.2))
	curve.add_point(Vector2(1.0, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var fg := Gradient.new()
	fg.colors = PackedColorArray([Color(1, 1, 1, 0.6), Color(1, 1, 1, 0.0)])
	fg.offsets = PackedFloat32Array([0.0, 1.0])
	var ft := GradientTexture1D.new()
	ft.gradient = fg
	pm.color_ramp = ft
	ripples.process_material = pm

	var rg := Gradient.new()
	rg.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	rg.offsets = PackedFloat32Array([0.0, 0.6, 0.85, 1.0])
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(1.0, 0.5)
	rt.width = 64
	rt.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(0.75, 0.85, 1.0, 0.5)
	mat.albedo_texture = rt
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(0.8, 0.8)
	quad.material = mat
	ripples.draw_pass_1 = quad
	level.add_child(ripples)


# ---------- surfaces and framing ----------

func _surfaces(level: Node) -> void:
	_soften(level)


func _soften(node: Node) -> void:
	if node is MeshInstance3D:
		var m := node.material_override as StandardMaterial3D
		if m != null and m.normal_enabled:
			m.normal_scale = 0.3
			m.metallic_specular = 0.35
	for c in node.get_children():
		_soften(c)


func _letterbox(level: Node) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	level.add_child(layer)
	var top := ColorRect.new()
	top.color = Color.BLACK
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.anchor_bottom = 0.05
	top.offset_bottom = 0.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = Color.BLACK
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.anchor_top = 0.95
	bottom.offset_top = 0.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bottom)


# ---------- per frame ----------

func _update(delta: float) -> void:
	for d in spots:
		var o: OmniLight3D = d["omni"]
		if not is_instance_valid(o):
			continue
		var ratio: float = o.light_energy / maxf(float(d["ob"]), 0.001)
		var sp: SpotLight3D = d["spot"]
		sp.light_energy = float(d["sb"]) * ratio
		var hm: StandardMaterial3D = d["halo"]
		hm.albedo_color.a = 0.55 * clampf(ratio, 0.0, 1.2)

	for i in tv_lights.size():
		var l: OmniLight3D = tv_lights[i]
		if is_instance_valid(l):
			l.light_energy = 0.2 + 0.8 * absf(sin(t * 17.0 + i * 3.0) * sin(t * 5.3 + i))

	var cam: Camera3D = lv.get("cam")
	var player = lv.get("player")
	if cam != null and sky_root != null:
		sky_root.global_position = cam.global_position
	if cloud_mat != null:
		cloud_mat.uv1_offset.x += delta * 0.004
	if ripples != null and player != null:
		ripples.global_position = Vector3(player.global_position.x, 0.03, 0.0)

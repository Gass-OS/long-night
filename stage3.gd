extends "res://stage2.gd"
# STAGE 3: Chaambi, the mountain pass (Tunisia). Reuses the stage 2 engine
# (UI, combat, inventory, camera, death, NPC helpers) and replaces the world and the missions.

const KEYS3 := [
	{"x": -16.0, "yaw": 8.0, "h": 2.4, "dist": 10.5, "fov": 52.0},
	{"x": 30.0, "yaw": 8.0, "h": 2.4, "dist": 10.5, "fov": 52.0},
	{"x": 44.0, "yaw": -8.0, "h": 3.2, "dist": 12.5, "fov": 55.0},
	{"x": 60.0, "yaw": -10.0, "h": 3.6, "dist": 13.5, "fov": 57.0},
	{"x": 76.0, "yaw": 10.0, "h": 2.6, "dist": 10.5, "fov": 52.0},
	{"x": 110.0, "yaw": 14.0, "h": 3.0, "dist": 11.5, "fov": 55.0},
	{"x": 135.0, "yaw": -6.0, "h": 2.2, "dist": 10.0, "fov": 52.0},
	{"x": 170.0, "yaw": 0.0, "h": 2.4, "dist": 11.0, "fov": 54.0},
]

const REWARDS3 := [3, 5, 10, 5, 10, 20]

# ground profile (x, y): desert and camp, then (after the ravine) the mountain climb
const PROF1 := [[-16.0, 0.0], [6.0, 0.0], [14.0, 0.9], [22.0, 0.3], [30.0, 1.2], [40.0, 0.6], [48.0, 0.8]]
const PROF2 := [[72.0, 0.8], [80.0, 0.8], [88.0, 2.6], [92.0, 2.6], [100.0, 5.2], [104.0, 5.2], [112.0, 8.4], [118.0, 8.4], [126.0, 11.2], [134.0, 11.2], [170.0, 11.2]]

const GRASS_SHADER := """
shader_type spatial;
render_mode cull_disabled;
void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = sin(TIME * 1.6 + wp.x * 0.7 + wp.z) * 0.1 * max(VERTEX.y + 0.35, 0.0);
	VERTEX.x += sway;
}
void fragment() {
	ALBEDO = vec3(0.16, 0.13, 0.06);
	ROUGHNESS = 1.0;
}
"""

var sky_mat: ProceduralSkyMaterial
var sky_root: Node3D
var fog_p: GPUParticles3D
var planks: Array = []
var rocks: Array = []
var fire_zones: Array = []
var flask_nodes: Array = []
var flasks := 0
var lit_count := 0
var beacon_lit := false
var barricade_body: StaticBody3D
var barricade_burned := false
var follower: Node3D
var ammi: Node3D
var beacon_pos := Vector3.ZERO


# ====================================================================
# setup
# ====================================================================

func _ready() -> void:
	stage = 3
	S.load_cfg()
	_load_inventory()
	_make_textures()
	_setup_environment()
	_build_terrain()
	_build_scenery()
	_build_sky()
	_build_camp()
	_build_bridge()
	_build_climb()
	_build_summit()
	checkpoint = Vector3(0.0, _h(0.0) + 0.1, 0.0)
	checkpoints = [
		Vector3(0.0, _h(0.0) + 0.1, 0.0),
		Vector3(30.0, _h(30.0) + 0.1, 0.0),
		Vector3(46.0, _h(46.0) + 0.1, 0.0),
		Vector3(74.0, _h(74.0) + 0.1, 0.0),
		Vector3(100.0, _h(100.0) + 0.1, 0.0),
		Vector3(126.0, _h(126.0) + 0.1, 0.0),
		Vector3(146.0, _h(146.0) + 0.1, 0.0),
	]
	_spawn_player()
	follower = _npc(-2.0, Color(0.9, 0.9, 0.85))
	follower.scale = Vector3(0.75, 0.75, 0.75)
	_spawn_enemies3()
	_build_coins()
	_build_flasks()
	_build_rocks()
	_build_dust()
	_build_fog_sheets()

	var hud = CanvasLayer.new()
	hud.set_script(load("res://hud.gd"))
	hud.player = player
	add_child(hud)

	_build_audio()
	_build_overlay()
	_build_ui()
	_attach_weapons()
	_apply_quality()
	_refresh_ui()
	_intro_card()


func _h(x: float) -> float:
	for prof in [PROF1, PROF2]:
		var first: Array = prof[0]
		var last: Array = prof[prof.size() - 1]
		if x >= float(first[0]) and x <= float(last[0]):
			for i in range(prof.size() - 1):
				var a: Array = prof[i]
				var b: Array = prof[i + 1]
				if x <= float(b[0]):
					var u := (x - float(a[0])) / (float(b[0]) - float(a[0]))
					return lerpf(float(a[1]), float(b[1]), u)
	return 0.8


# ====================================================================
# environment: cold pre-dawn, orange horizon, deep fog
# ====================================================================

func _setup_environment() -> void:
	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.025, 0.06)
	sky_mat.sky_horizon_color = Color(0.3, 0.17, 0.12)
	sky_mat.ground_horizon_color = Color(0.3, 0.17, 0.12)
	sky_mat.ground_bottom_color = Color(0.03, 0.03, 0.04)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.22, 0.28, 0.4)
	env.ambient_light_energy = 0.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.14, 0.18)
	env.fog_density = 0.016
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.04
	env.volumetric_fog_albedo = Color(0.6, 0.65, 0.75)
	env.volumetric_fog_emission = Color(0.005, 0.008, 0.015)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_anisotropy = 0.6
	env.volumetric_fog_ambient_inject = 0.3
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2
	env.glow_enabled = true
	env.glow_intensity = 1.1
	env.glow_bloom = 0.18
	env.glow_hdr_threshold = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.7
	env.adjustment_contrast = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -25.0, 0.0)
	sun.light_energy = 0.6
	sun.light_color = Color(0.55, 0.65, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.light_volumetric_fog_energy = 0.8
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30.0, 180.0, 0.0)
	rim.light_energy = 0.3
	rim.light_color = Color(1.0, 0.65, 0.4)
	rim.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(rim)

	cam = Camera3D.new()
	cam_attrs = CameraAttributesPractical.new()
	cam_attrs.dof_blur_far_enabled = true
	cam_attrs.dof_blur_far_distance = 13.0
	cam_attrs.dof_blur_far_transition = 12.0
	cam_attrs.dof_blur_near_enabled = true
	cam_attrs.dof_blur_near_distance = 5.0
	cam_attrs.dof_blur_near_transition = 3.0
	cam_attrs.dof_blur_amount = 0.1
	cam_attrs.exposure_multiplier = 1.3
	cam.attributes = cam_attrs
	cam.fov = 52.0
	cam.position = Vector3(0, 4, 10)
	add_child(cam)
	cam.make_current()


# ====================================================================
# terrain: sloped boxes follow the profile, the ravine has no floor to walk on
# ====================================================================

func _terrain_chunk(prof: Array, mat: Material) -> void:
	for i in range(prof.size() - 1):
		var a: Array = prof[i]
		var b: Array = prof[i + 1]
		var ax := float(a[0])
		var ay := float(a[1])
		var bx := float(b[0])
		var by := float(b[1])
		var dx := bx - ax
		var dy := by - ay
		var length := sqrt(dx * dx + dy * dy)
		var ang := atan2(dy, dx)
		var mid := Vector2((ax + bx) / 2.0, (ay + by) / 2.0)
		var nrm := Vector2(-sin(ang), cos(ang))
		var center := mid - nrm * 0.5

		var body := StaticBody3D.new()
		body.position = Vector3(center.x, center.y, 0.0)
		body.rotation.z = ang
		var mesh := MeshInstance3D.new()
		mesh.mesh = _box(Vector3(length + 0.1, 1.0, 4.0))
		mesh.material_override = mat
		body.add_child(mesh)
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(length + 0.1, 1.0, 4.0)
		col.shape = bs
		body.add_child(col)
		add_child(body)

		for ext in [[-8.0, 12.0], [5.0, 6.0]]:
			var m2 := MeshInstance3D.new()
			m2.mesh = _box(Vector3(length + 0.1, 1.0, float(ext[1])))
			m2.material_override = mat
			m2.position = Vector3(center.x, center.y, float(ext[0]))
			m2.rotation.z = ang
			add_child(m2)


func _build_terrain() -> void:
	_terrain_chunk(PROF1, _surf(Color(0.4, 0.32, 0.22), 0.9, 0.3))
	_terrain_chunk(PROF2, _surf(Color(0.28, 0.25, 0.22), 0.9, 0.3))
	# the ravine (wadi)
	var dark := _mat(Color(0.03, 0.03, 0.04), 1.0)
	_mi(self, _box(Vector3(30.0, 1.0, 60.0)), dark, Vector3(60.0, -14.5, -8.0))
	var rock := _surf(Color(0.25, 0.22, 0.2), 0.95, 0.25)
	_mi(self, _box(Vector3(3.0, 16.0, 60.0)), rock, Vector3(46.5, -7.2, -8.0))
	_mi(self, _box(Vector3(3.0, 16.0, 60.0)), rock, Vector3(73.5, -7.2, -8.0))
	_label3d("WADI EL KHAWF", Vector3(60.0, 4.5, -2.0), 70, Color(1.0, 0.8, 0.55))


# ====================================================================
# scenery: dunes, mountain walls, pines, palms, alfa grass, camels, tents
# ====================================================================

func _pine(x: float, z: float, h: float, mat: Material, trunk_mat: Material) -> void:
	var y := _h(x)
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = h * 0.4
	_mi(self, trunk, trunk_mat, Vector3(x, y + h * 0.2, z))
	for k in 3:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 1.5 - k * 0.35
		cone.height = h * 0.45
		_mi(self, cone, mat, Vector3(x, y + h * (0.4 + k * 0.22), z))


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	# far dunes
	var sand := _mat(Color(0.2, 0.15, 0.1), 1.0)
	for i in 16:
		var d := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		d.mesh = sm
		d.material_override = sand
		d.scale = Vector3(rng.randf_range(24.0, 44.0), rng.randf_range(4.0, 9.0), rng.randf_range(14.0, 22.0))
		d.position = Vector3(i * 14.0 - 30.0, -1.5, rng.randf_range(-70.0, -34.0))
		add_child(d)

	# mountain walls behind the lane, standing on the ground or on the ravine floor
	var rock := _surf(Color(0.2, 0.18, 0.17), 0.95, 0.2)
	var x := 56.0
	while x < 190.0:
		var gh := _h(minf(x, 170.0))
		var hh := rng.randf_range(7.0, 18.0)
		var w := rng.randf_range(7.0, 12.0)
		var top := gh + hh
		var bottom := -14.0
		var m := _mi(self, _box(Vector3(w, top - bottom, rng.randf_range(4.0, 8.0))), rock, Vector3(x, (top + bottom) / 2.0, rng.randf_range(-12.0, -6.0)))
		m.rotation_degrees.y = rng.randf_range(-12.0, 12.0)
		x += w * 0.8

	# pines on the mountain, palms at the camp
	var pine_mat := _mat(Color(0.03, 0.06, 0.04), 1.0)
	var trunk_mat := _mat(Color(0.1, 0.07, 0.05), 1.0)
	var px := 76.0
	while px < 168.0:
		_pine(px + rng.randf_range(-1.5, 1.5), rng.randf_range(-7.0, -2.8), rng.randf_range(4.0, 7.0), pine_mat, trunk_mat)
		px += rng.randf_range(3.0, 6.0)
	for palm_x in [2.0, 9.0, 28.0, 36.0]:
		_palm(palm_x, rng.randf_range(-6.0, -3.0), 6.0)

	# boulders along the path
	var boulder := _surf(Color(0.3, 0.26, 0.22), 0.95, 0.4)
	for i in 26:
		var bx := rng.randf_range(-12.0, 168.0)
		if bx > 46.0 and bx < 72.0:
			continue
		var s := rng.randf_range(0.3, 0.9)
		var sm2 := SphereMesh.new()
		sm2.radius = s
		sm2.height = s * 1.4
		_mi(self, sm2, boulder, Vector3(bx, _h(bx) + s * 0.3, rng.randf_range(-2.4, -1.4)))

	_build_grass(rng)


func _build_grass(rng: RandomNumberGenerator) -> void:
	var transforms: Array = []
	for i in 420:
		var gx := rng.randf_range(-12.0, 46.0) if rng.randf() < 0.7 else rng.randf_range(72.0, 130.0)
		var gz := rng.randf_range(-1.9, -0.9) if rng.randf() < 0.5 else rng.randf_range(1.0, 2.4)
		var gy := _h(gx) + 0.3
		for b in 3:
			var basis := Basis.from_euler(Vector3(rng.randf_range(-0.25, 0.25), rng.randf() * PI, rng.randf_range(-0.3, 0.3)))
			basis = basis.scaled(Vector3(1.0, rng.randf_range(0.6, 1.4), 1.0))
			transforms.append(Transform3D(basis, Vector3(gx + b * 0.08, gy, gz)))
	var sh := Shader.new()
	sh.code = GRASS_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	_multimesh(transforms, sm, Vector3(0.04, 0.7, 0.04))


func _tent(x: float, c1: Color, c2: Color, z: float) -> void:
	var y := _h(x)
	var prism := PrismMesh.new()
	prism.size = Vector3(3.2, 1.9, 2.4)
	var cloth := _tex_mat(_stripe_tex(c1, c2), Color(0.7, 0.7, 0.7), 0.95)
	cloth.uv1_scale = Vector3(4.0, 1.0, 1.0)
	_mi(self, prism, cloth, Vector3(x, y + 0.95, z))
	_mi(self, _box(Vector3(0.9, 1.2, 0.05)), _mat(Color(0.02, 0.02, 0.025), 1.0), Vector3(x, y + 0.6, z + 1.22))


func _camel(x: float, z: float, flip: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(x, _h(x), z)
	if flip:
		root.rotation.y = PI
	add_child(root)
	var fur := _mat(Color(0.2, 0.15, 0.1), 1.0)
	_mi(root, _box(Vector3(1.8, 0.75, 0.7)), fur, Vector3(0, 1.1, 0))
	for lx in [-0.65, 0.65]:
		for lz in [-0.25, 0.25]:
			_mi(root, _box(Vector3(0.15, 0.95, 0.15)), fur, Vector3(lx, 0.47, lz))
	var hump := SphereMesh.new()
	hump.radius = 0.32
	hump.height = 0.5
	_mi(root, hump, fur, Vector3(0.1, 1.6, 0))
	var neck := _mi(root, _box(Vector3(0.25, 1.0, 0.25)), fur, Vector3(1.0, 1.6, 0))
	neck.rotation_degrees.z = -25.0
	_mi(root, _box(Vector3(0.55, 0.25, 0.25)), fur, Vector3(1.4, 2.05, 0))
	_mi(root, _box(Vector3(0.08, 0.5, 0.08)), fur, Vector3(-0.95, 1.0, 0))


func _build_sky() -> void:
	sky_root = Node3D.new()
	add_child(sky_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	# stars
	var stars: Array = []
	for i in 260:
		stars.append(Transform3D(Basis(), Vector3(rng.randf_range(-110.0, 110.0), rng.randf_range(10.0, 60.0), -120.0)))
	var star_mat := _glow(Color(1.0, 1.0, 1.0), 3.0)
	star_mat.disable_fog = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box(Vector3(0.35, 0.35, 0.05))
	mm.instance_count = stars.size()
	for i in stars.size():
		mm.set_instance_transform(i, stars[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = star_mat
	sky_root.add_child(mmi)
	# moon
	var moon_mat := _glow(Color(0.85, 0.9, 1.0), 2.5)
	moon_mat.disable_fog = true
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 3.0
	moon_mesh.height = 6.0
	moon_mesh.material = moon_mat
	var moon := MeshInstance3D.new()
	moon.mesh = moon_mesh
	moon.position = Vector3(30.0, 30.0, -100.0)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(moon)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.albedo_texture = _radial()
	hm.albedo_color = Color(0.45, 0.55, 0.9, 0.35)
	hm.disable_fog = true
	var hq := QuadMesh.new()
	hq.size = Vector2(32.0, 32.0)
	hq.material = hm
	var halo := MeshInstance3D.new()
	halo.mesh = hq
	halo.position = Vector3(30.0, 30.0, -99.0)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(halo)
	# warm glow on the horizon
	var gg := Gradient.new()
	gg.colors = PackedColorArray([Color(0.7, 0.35, 0.15, 0.45), Color(0.35, 0.18, 0.1, 0.14), Color(0, 0, 0, 0)])
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
	var gq := QuadMesh.new()
	gq.size = Vector2(320.0, 40.0)
	gq.material = glow_mat
	var glow := MeshInstance3D.new()
	glow.mesh = gq
	glow.position = Vector3(0.0, 8.0, -118.0)
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sky_root.add_child(glow)


func _build_fog_sheets() -> void:
	fog_p = GPUParticles3D.new()
	fog_p.amount = 16
	fog_p.lifetime = 14.0
	fog_p.preprocess = 14.0
	fog_p.local_coords = false
	fog_p.visibility_aabb = AABB(Vector3(-60, -3, -14), Vector3(120, 8, 28))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(50.0, 0.5, 8.0)
	pm.direction = Vector3(1.0, 0.0, 0.0)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3.ZERO
	pm.scale_min = 1.0
	pm.scale_max = 1.6
	var fg := Gradient.new()
	fg.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.5), Color(1, 1, 1, 0.0)])
	fg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var ft := GradientTexture1D.new()
	ft.gradient = fg
	pm.color_ramp = ft
	fog_p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(10.0, 3.0)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _radial()
	m.albedo_color = Color(0.6, 0.65, 0.75, 0.25)
	quad.material = m
	fog_p.draw_pass_1 = quad
	add_child(fog_p)


# ====================================================================
# fire (braziers, camp fires, barricade, beacon)
# ====================================================================

func _fire(pos: Vector3, big: bool) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	add_child(root)
	var p := GPUParticles3D.new()
	p.amount = 40 if big else 22
	p.lifetime = 0.9
	p.visibility_aabb = AABB(Vector3(-2, -1, -2), Vector3(4, 6, 4))
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.8
	pm.gravity = Vector3(0, 0.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.2))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.colors = PackedColorArray([Color(1.0, 0.9, 0.4, 0.0), Color(1.0, 0.7, 0.2, 0.9), Color(0.9, 0.3, 0.1, 0.6), Color(0.2, 0.05, 0.02, 0.0)])
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1.2, 1.2) if big else Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _radial()
	m.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	quad.material = m
	p.draw_pass_1 = quad
	root.add_child(p)
	var l := _omni(pos + Vector3(0, 0.7, 0.5), Color(1.0, 0.6, 0.3), 3.5 if big else 2.2, 12.0 if big else 9.0)
	lamp_lights.append(l)
	lamp_base.append(l.light_energy)
	lamp_halos.append(_halo(pos + Vector3(0, 0.8, 0.3), 3.0 if big else 1.8, Color(1.0, 0.6, 0.25, 0.5)))
	return root


# ====================================================================
# camp, bridge, climb, summit
# ====================================================================

func _build_camp() -> void:
	var fy := _h(21.0)
	_fire(Vector3(21.0, fy, -0.9), false)
	fire_zones.append(Vector3(21.0, fy, 9.0))
	var stone := _surf(Color(0.3, 0.27, 0.24), 0.95, 0.5)
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var sm := SphereMesh.new()
		sm.radius = 0.16
		sm.height = 0.26
		_mi(self, sm, stone, Vector3(21.0 + cos(a) * 0.7, fy + 0.1, -0.9 + sin(a) * 0.5))
	_tent(14.5, Color(0.5, 0.12, 0.08), Color(0.8, 0.75, 0.65), -2.3)
	_tent(27.5, Color(0.12, 0.28, 0.45), Color(0.8, 0.75, 0.65), -2.3)
	_camel(10.0, -2.2, false)
	_camel(32.0, -2.3, true)

	ammi = _npc(19.0, Color(0.8, 0.78, 0.7))
	ammi.position.y = fy
	var arig: Node3D = ammi.get_meta("rig")
	var robe := CylinderMesh.new()
	robe.top_radius = 0.17
	robe.bottom_radius = 0.24
	robe.height = 0.75
	_mi(arig, robe, _mat(Color(0.8, 0.78, 0.7), 0.95), Vector3(0, 0.42, 0))
	var head = arig.get("head")
	if head != null:
		var turban := SphereMesh.new()
		turban.radius = 0.13
		turban.height = 0.2
		_mi(head, turban, _mat(Color(0.85, 0.85, 0.8), 0.9), Vector3(0, 0.17, 0))
	_mi(self, _box(Vector3(0.04, 1.7, 0.04)), _mat(Color(0.2, 0.12, 0.07), 0.9), Vector3(19.6, fy + 0.85, -0.5))
	_label3d("AMMI BRAHIM", Vector3(19.0, fy + 2.0, -0.6), 40, Color(1.0, 0.9, 0.7))
	interactables.append({"x": 19.0, "y": fy, "kind": "npc", "r": 2.4})

	for hx in [36.0]:
		_hide_rock(hx)


func _hide_rock(x: float) -> void:
	var y := _h(x)
	var stone := _surf(Color(0.28, 0.25, 0.22), 0.95, 0.5)
	for k in 4:
		var sm := SphereMesh.new()
		sm.radius = 0.7 + k * 0.1
		sm.height = 1.2 + k * 0.1
		_mi(self, sm, stone, Vector3(x - 0.9 + k * 0.6, y + 0.5, -0.6))
	_label3d("HIDE", Vector3(x, y + 1.9, -0.4), 40, Color(0.4, 1.0, 0.6))
	interactables.append({"x": x, "y": y, "kind": "hide", "r": 1.8})


func _build_bridge() -> void:
	var wood := _surf(Color(0.28, 0.17, 0.09), 0.85, 0.6)
	for i in 12:
		var px := 49.0 + i * 2.0
		var plank := AnimatableBody3D.new()
		plank.position = Vector3(px, 0.65, 0.0)
		_mi(plank, _box(Vector3(1.9, 0.3, 2.0)), wood, Vector3.ZERO)
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.9, 0.3, 2.0)
		col.shape = bs
		plank.add_child(col)
		add_child(plank)
		var weak := i == 3 or i == 5 or i == 7 or i == 9
		planks.append({"node": plank, "x": px, "top": 0.8, "weak": weak, "state": 0, "t": 0.0})
	var post_mat := _mat(Color(0.2, 0.12, 0.07), 0.9)
	for side in [-1.0, 1.0]:
		_wire(Vector3(48.0, 2.0, side), Vector3(72.0, 2.0, side), 1.4)
		for px in [48.2, 71.8]:
			_mi(self, _box(Vector3(0.15, 2.0, 0.15)), post_mat, Vector3(px, 1.0, side))


func _make_brazier(x: float) -> void:
	var y := _h(x)
	var stone := _surf(Color(0.3, 0.27, 0.24), 0.95, 0.5)
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.2
	pillar.bottom_radius = 0.26
	pillar.height = 1.0
	_mi(self, pillar, stone, Vector3(x, y + 0.5, -0.8))
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.42
	bowl.bottom_radius = 0.28
	bowl.height = 0.22
	_mi(self, bowl, _mat(Color(0.08, 0.08, 0.09), 0.5, 0.7), Vector3(x, y + 1.1, -0.8))
	_label3d("BRAZIER", Vector3(x, y + 2.0, -0.6), 36, Color(1.0, 0.7, 0.4))
	interactables.append({"x": x, "y": y, "kind": "brazier", "r": 1.8, "lit": false})


func _build_climb() -> void:
	for bx in [30.0, 78.0, 118.0]:
		_make_brazier(bx)
	for hx in [86.0, 120.0]:
		_hide_rock(hx)
	# the jackal barricade
	var by := _h(132.0)
	var wood := _surf(Color(0.22, 0.13, 0.07), 0.9, 0.6)
	barricade_body = _solid(Vector3(132.0, by + 1.7, 0.0), Vector3(1.0, 3.4, 2.0), wood)
	for k in 6:
		var sp := _mi(self, _box(Vector3(0.08, 1.2, 0.08)), wood, Vector3(131.5, by + 3.6, -0.8 + k * 0.32))
		sp.rotation_degrees.z = 12.0
	_label3d("BARRICADE", Vector3(132.0, by + 4.5, 0.0), 40, Color(1.0, 0.6, 0.4))
	interactables.append({"x": 132.0, "y": by, "kind": "barricade", "r": 2.4})
	# old watch posts along the path
	_wire(Vector3(96.0, _h(96.0) + 3.0, -1.5), Vector3(112.0, _h(112.0) + 3.0, -1.5), 1.0)


func _ruin_arch(x: float) -> void:
	var y := _h(x)
	var root := CSGCombiner3D.new()
	root.position = Vector3(x, y, -3.0)
	add_child(root)
	_csg_box(root, Vector3(1.6, 6.0, 5.0), Vector3(0, 3.0, 0), false, _surf(Color(0.45, 0.4, 0.32), 0.95, 0.3))
	_csg_box(root, Vector3(2.0, 2.6, 2.4), Vector3(0, 1.3, 0), true)
	_csg_cyl_x(root, 1.2, 2.0, Vector3(0, 2.6, 0))
	_csg_box(root, Vector3(2.0, 3.0, 3.0), Vector3(0, 6.2, 1.2), true)


func _build_summit() -> void:
	_ruin_arch(140.0)
	_tent(150.0, Color(0.1, 0.1, 0.12), Color(0.45, 0.08, 0.06), -2.3)
	_tent(157.0, Color(0.1, 0.1, 0.12), Color(0.45, 0.08, 0.06), -2.3)
	var crate := _surf(Color(0.28, 0.17, 0.09), 0.9, 0.6)
	for cx in [145.0, 148.0, 153.0]:
		_mi(self, _box(Vector3(0.9, 0.9, 0.9)), crate, Vector3(cx, _h(cx) + 0.45, -1.6))
	_fire(Vector3(153.0, _h(153.0), -1.2), true)
	# the beacon
	var by := _h(162.0)
	beacon_pos = Vector3(162.0, by, -0.5)
	var stone := _surf(Color(0.35, 0.31, 0.27), 0.95, 0.4)
	_mi(self, _box(Vector3(2.4, 1.2, 1.8)), stone, Vector3(162.0, by + 0.6, -0.5))
	var pillar := CylinderMesh.new()
	pillar.top_radius = 0.45
	pillar.bottom_radius = 0.6
	pillar.height = 1.6
	_mi(self, pillar, stone, Vector3(162.0, by + 2.0, -0.5))
	var bowl := CylinderMesh.new()
	bowl.top_radius = 0.9
	bowl.bottom_radius = 0.5
	bowl.height = 0.4
	_mi(self, bowl, _mat(Color(0.08, 0.08, 0.09), 0.5, 0.7), Vector3(162.0, by + 3.0, -0.5))
	_label3d("THE BEACON", Vector3(162.0, by + 4.6, -0.5), 56, Color(1.0, 0.8, 0.5))
	interactables.append({"x": 161.2, "y": by, "kind": "beacon", "r": 2.8})


# ====================================================================
# enemies, coins, flasks, rocks
# ====================================================================

func _add_dog3(x: float, left_x: float, right_x: float) -> void:
	var d = CharacterBody3D.new()
	d.set_script(load("res://dog.gd"))
	d.target = player
	d.left_x = left_x
	d.right_x = right_x
	d.position = Vector3(x, _h(x) + 0.3, 0.0)
	d.caught.connect(_on_caught)
	d.alerted.connect(_on_alert)
	add_child(d)
	dogs.append(d)


func _spawn_enemies3() -> void:
	_add_dog3(40.0, 37.0, 44.0)
	_add_dog3(84.0, 81.0, 88.0)
	_add_dog3(100.0, 97.0, 104.0)
	_add_dog3(114.0, 111.0, 118.0)
	_add_dog3(148.0, 144.0, 152.0)
	_add_thug(92.0, 89.0, 97.0, _h(92.0) + 0.3)
	_add_thug(124.0, 121.0, 129.0, _h(124.0) + 0.3)
	_add_thug(150.0, 146.0, 154.0, _h(150.0) + 0.3)
	_add_thug(158.0, 155.0, 160.0, _h(158.0) + 0.3)
	# the Jackal chief: tougher
	var chief = thugs[thugs.size() - 1]
	chief.hp = 4
	chief.rig.scale = Vector3(1.4, 1.4, 1.4)


func _coin_positions() -> Array:
	var p: Array = []
	var x := 4.0
	while x < 46.0:
		p.append(Vector3(x, _h(x) + 0.7, 0.0))
		x += 4.0
	for px in [51.0, 55.0, 59.0, 63.0, 67.0, 71.0]:
		p.append(Vector3(px, 1.6, 0.0))
	x = 76.0
	while x < 134.0:
		p.append(Vector3(x, _h(x) + 0.7, 0.0))
		x += 4.5
	x = 137.0
	while x < 160.0:
		p.append(Vector3(x, _h(x) + 0.7, 0.0))
		x += 4.0
	return p


func _build_flasks() -> void:
	for fx in [90.0, 112.0, 140.0]:
		var a := Area3D.new()
		a.position = Vector3(fx, _h(fx) + 0.6, 0.0)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.7
		cs.shape = sh
		a.add_child(cs)
		var jar := SphereMesh.new()
		jar.radius = 0.2
		jar.height = 0.4
		_mi(a, jar, _glow(Color(1.0, 0.6, 0.15), 2.5), Vector3.ZERO)
		var neck := CylinderMesh.new()
		neck.top_radius = 0.06
		neck.bottom_radius = 0.09
		neck.height = 0.18
		_mi(a, neck, _glow(Color(1.0, 0.6, 0.15), 2.5), Vector3(0, 0.26, 0))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.2)
		l.light_energy = 1.0
		l.omni_range = 3.5
		a.add_child(l)
		add_child(a)
		a.body_entered.connect(_on_flask.bind(a))
		flask_nodes.append(a)


func _on_flask(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	flasks += 1
	flask_nodes.erase(area)
	area.queue_free()
	_sfx("coin")
	_banner("Oil flask  %d/3" % flasks, 2.5)
	_check_missions()


func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6
	var rock_mat := _surf(Color(0.3, 0.26, 0.22), 0.95, 0.5)
	for rx in [96.0, 108.0, 122.0]:
		var ground := _h(rx)
		var node := Node3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.75
		sm.height = 1.3
		_mi(node, sm, rock_mat, Vector3.ZERO)
		node.position = Vector3(rx, ground + 9.0, 0.0)
		node.visible = false
		add_child(node)
		var dm := StandardMaterial3D.new()
		dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dm.albedo_texture = _radial()
		dm.albedo_color = Color(0.0, 0.0, 0.0, 0.0)
		var dq := QuadMesh.new()
		dq.orientation = PlaneMesh.FACE_Y
		dq.size = Vector2(2.2, 2.2)
		dq.material = dm
		var decal := MeshInstance3D.new()
		decal.mesh = dq
		decal.position = Vector3(rx, ground + 0.05, 0.0)
		add_child(decal)
		rocks.append({"node": node, "decal": dm, "x": rx, "ground": ground, "state": 0, "t": rng.randf_range(1.0, 4.0)})


# ====================================================================
# missions
# ====================================================================

func _mission(i: int) -> Array:
	var px := 0.0
	if player != null:
		px = player.global_position.x
	match i:
		0:
			return ["Reach the shepherd's camp", px >= 12.0, 3]
		1:
			return ["Speak to Ammi Brahim", talked, 5]
		2:
			return ["Light the three signal braziers  (%d/3)" % lit_count, lit_count >= 3, 10]
		3:
			return ["Cross the rope bridge over the wadi", px >= 74.0, 5]
		4:
			return ["Find the oil flasks  (%d/3)" % flasks, flasks >= 3, 10]
	return ["Light the beacon on the summit", beacon_lit, 20]


func _objective_x() -> float:
	var px := player.global_position.x
	match m_idx:
		0:
			return 12.0
		1:
			return 19.0
		2:
			var best := -1.0
			var bd := 1000.0
			for it in interactables:
				if str(it["kind"]) == "brazier" and not bool(it["lit"]):
					var d := absf(float(it["x"]) - px)
					if d < bd:
						bd = d
						best = float(it["x"])
			return best
		3:
			return 74.0
		4:
			var best2 := -1.0
			var bd2 := 1000.0
			for a in flask_nodes:
				if is_instance_valid(a):
					var d2 := absf(a.position.x - px)
					if d2 < bd2:
						bd2 = d2
						best2 = a.position.x
			return best2
	return 161.2


func _check_missions() -> void:
	var guard := 0
	while m_idx < 5 and guard < 6:
		guard += 1
		var m := _mission(m_idx)
		if not m[1]:
			break
		var reward: int = REWARDS3[m_idx]
		coins += reward
		var text := "MISSION COMPLETE\n%s" % str(m[0])
		if reward > 0:
			text += "\n+%d coins" % reward
		_banner(text, 4.5)
		m_idx += 1
		_sfx("buy")
	_save_inventory()
	_refresh_ui()


# ====================================================================
# interaction
# ====================================================================

func _use() -> void:
	if hidden:
		_toggle_hide(0.0)
		return
	var it = _nearest_interactable()
	if it == null:
		return
	match str(it["kind"]):
		"npc":
			_talk_ammi()
		"brazier":
			_light_brazier(it)
		"hide":
			_toggle_hide(float(it["x"]))
		"barricade":
			_burn_barricade()
		"beacon":
			_light_beacon()


func _talk_ammi() -> void:
	if not talked:
		talked = true
		has_lantern = true
		_give_lantern()
		if has_gun:
			ammo += 6
			_save_inventory()
		_say([
			"AMMI BRAHIM:  Marhba, ya weldi. Coming out of the Medina with the boy? Allah is generous.",
			"AMMI BRAHIM:  The Jackals hunt on this mountain. But jackals fear fire. Take this torch and light the old braziers.",
			"AMMI BRAHIM:  Find three flasks of oil on the path. At the summit the old beacon will call the army post at dawn. Allah ysahel.",
		])
		_check_missions()
	else:
		_say(["AMMI BRAHIM:  Light the braziers. Jackals will not come near the flames."])


func _light_brazier(it: Dictionary) -> void:
	if not has_lantern:
		_banner("You need fire. Talk to Ammi Brahim.", 2.5)
		return
	if bool(it["lit"]):
		_banner("This brazier is already burning.", 1.8)
		return
	it["lit"] = true
	var bx := float(it["x"])
	var by := float(it["y"])
	_fire(Vector3(bx, by + 1.2, -0.8), false)
	fire_zones.append(Vector3(bx, by, 9.0))
	lit_count += 1
	checkpoint = Vector3(bx - 0.8, by + 0.2, 0.0)
	_sfx("buy")
	_banner("Brazier lit. The jackals keep away from the flames.\n(checkpoint)", 3.5)
	_check_missions()


func _burn_barricade() -> void:
	if barricade_burned:
		return
	if not has_lantern:
		_banner("Only fire can clear this barricade.", 2.5)
		return
	barricade_burned = true
	var by := _h(132.0)
	_fire(Vector3(132.0, by + 0.6, 0.0), true)
	_banner("The barricade is burning...", 3.0)
	get_tree().create_timer(3.0).timeout.connect(func():
		if is_instance_valid(barricade_body):
			barricade_body.queue_free())


func _light_beacon() -> void:
	if beacon_lit:
		return
	if flasks < 3:
		_banner("The beacon needs oil: %d/3 flasks." % flasks, 3.0)
		return
	beacon_lit = true
	_fire(beacon_pos + Vector3(0, 3.2, 0), true)
	_sfx("buy")
	_dawn()
	_banner("THE BEACON BURNS!\nThe army post will see it. Hold on until dawn.", 6.0)
	_say([
		"YASSINE:  Look! The sun is coming up over the Chaambi!",
		"YASSINE:  Jeddi will be so proud. Thank you, brave one.",
	])
	_check_missions()
	_complete_stage()


func _dawn() -> void:
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(sky_mat, "sky_horizon_color", Color(1.0, 0.55, 0.25), 6.0)
	tw.tween_property(sky_mat, "sky_top_color", Color(0.25, 0.4, 0.7), 6.0)
	tw.tween_property(sun, "light_energy", 1.4, 6.0)
	tw.tween_property(sun, "light_color", Color(1.0, 0.75, 0.5), 6.0)
	tw.tween_property(sun, "rotation_degrees", Vector3(-12.0, -60.0, 0.0), 6.0)
	tw.tween_property(env, "fog_light_color", Color(0.5, 0.35, 0.25), 6.0)
	tw.tween_property(env, "ambient_light_energy", 0.9, 6.0)


func _complete_stage() -> void:
	if finished:
		return
	finished = true
	await get_tree().create_timer(8.0).timeout
	msg_label.text = "STAGE 3 COMPLETE\nDAWN OVER CHAAMBI\nTO BE CONTINUED"
	msg_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 1.2)
	tw.parallel().tween_property(msg_label, "modulate:a", 1.0, 1.6)
	await tw.finished
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://menu.tscn")


func _intro_card() -> void:
	msg_label.text = "STAGE 3\nCHAAMBI  -  THE MOUNTAIN PASS"
	msg_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	var tw := create_tween()
	tw.tween_property(msg_label, "modulate:a", 1.0, 1.2)
	tw.tween_interval(2.0)
	tw.parallel().tween_property(fade, "modulate:a", 0.0, 2.2).set_delay(1.0)
	tw.tween_property(msg_label, "modulate:a", 0.0, 1.0)
	await tw.finished
	_banner("Mission: " + str(_mission(m_idx)[0]), 4.0)


# ====================================================================
# audio: lonely desert plucks and strong wind
# ====================================================================

func _make_oud() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 16
	var buf := PackedFloat32Array()
	buf.resize(n)
	var notes := [
		[0.0, 110.0], [2.5, 130.81], [4.0, 146.83], [7.0, 164.81], [9.5, 130.81], [12.0, 110.0],
	]
	for nt in notes:
		var start := int(float(nt[0]) * rate)
		var f: float = nt[1]
		var length := int(rate / f)
		var line := PackedFloat32Array()
		line.resize(length)
		for i in length:
			line[i] = randf() * 2.0 - 1.0
		var idx := 0
		var dur := mini(n - start, rate * 4)
		for i in dur:
			var v := line[idx]
			var nxt := line[(idx + 1) % length]
			line[idx] = (v + nxt) * 0.5 * 0.998
			idx = (idx + 1) % length
			buf[start + i] += v * 0.4 * (1.0 - float(i) / dur)
	for i in n:
		var tt := float(i) / rate
		var drone := sin(TAU * 55.0 * tt) * 0.14 + sin(TAU * 82.5 * tt) * 0.07
		var lfo := 0.7 + 0.3 * sin(TAU * tt / 16.0)
		var fade_edge := clampf(minf(tt, 16.0 - tt) / 0.2, 0.0, 1.0)
		buf[i] = (buf[i] + drone * lfo) * fade_edge
	return _to_wav(buf, rate, true)


func _make_wind() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.05
		s[i] = lp * (0.6 + 0.4 * sin(TAU * tt / 8.0)) * 3.2
	return _to_wav(s, rate, true)


# ====================================================================
# per frame
# ====================================================================

func _params(x: float) -> Dictionary:
	if x <= KEYS3[0]["x"]:
		return KEYS3[0]
	for i in range(KEYS3.size() - 1):
		var a: Dictionary = KEYS3[i]
		var b: Dictionary = KEYS3[i + 1]
		if x <= b["x"]:
			var u := clampf((x - a["x"]) / (b["x"] - a["x"]), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			return {
				"yaw": lerpf(a["yaw"], b["yaw"], u),
				"h": lerpf(a["h"], b["h"], u),
				"dist": lerpf(a["dist"], b["dist"], u),
				"fov": lerpf(a["fov"], b["fov"], u),
			}
	return KEYS3[KEYS3.size() - 1]


func _on_plank(pl: Dictionary) -> bool:
	var pp: Vector3 = player.global_position
	return absf(pp.x - float(pl["x"])) < 1.0 and absf(pp.y - float(pl["top"])) < 0.6 and player.is_on_floor()


func _physics_process(delta: float) -> void:
	if player == null:
		return
	var pp: Vector3 = player.global_position

	# collapsing planks
	for pl in planks:
		var node: AnimatableBody3D = pl["node"]
		match int(pl["state"]):
			0:
				if bool(pl["weak"]) and _on_plank(pl):
					pl["t"] = float(pl["t"]) + delta
					node.position.x = float(pl["x"]) + sin(t * 60.0) * 0.03
					if float(pl["t"]) > 0.7:
						pl["state"] = 1
						pl["t"] = 0.0
						node.position.x = float(pl["x"])
				else:
					pl["t"] = maxf(0.0, float(pl["t"]) - delta)
			1:
				node.position.y -= 14.0 * delta
				pl["t"] = float(pl["t"]) + delta
				if float(pl["t"]) > 5.0:
					node.position.y = 0.65
					pl["state"] = 0
					pl["t"] = 0.0

	# falling rocks
	for r in rocks:
		var rn: Node3D = r["node"]
		var dm: StandardMaterial3D = r["decal"]
		var ground := float(r["ground"])
		match int(r["state"]):
			0:
				rn.visible = false
				r["t"] = float(r["t"]) - delta
				if float(r["t"]) <= 0.0:
					r["state"] = 1
					r["t"] = 1.1
					rn.position.y = ground + 9.0
					rn.visible = true
			1:
				r["t"] = float(r["t"]) - delta
				dm.albedo_color.a = clampf(1.0 - float(r["t"]) / 1.1, 0.0, 1.0) * 0.8
				if float(r["t"]) <= 0.0:
					r["state"] = 2
			2:
				rn.position.y -= 24.0 * delta
				if not hidden and not dead and absf(pp.x - float(r["x"])) < 0.9 and rn.position.y < pp.y + 1.9 and rn.position.y > pp.y - 0.3:
					_on_caught()
				if rn.position.y <= ground + 0.7:
					shake = 0.5
					r["state"] = 3
					r["t"] = 0.8
			3:
				r["t"] = float(r["t"]) - delta
				if float(r["t"]) <= 0.0:
					r["state"] = 0
					r["t"] = randf_range(2.5, 4.5)
					dm.albedo_color.a = 0.0
					rn.visible = false

	# jackals fear fire
	for z in fire_zones:
		var fz: Vector3 = z
		for e in dogs:
			var ep: Vector3 = e.global_position
			if absf(ep.x - fz.x) < fz.z and absf(ep.y - fz.y) < 4.0:
				e.set("chasing", false)
				e.set("ignore_timer", 0.5)

	if not dead and not finished:
		for cp in checkpoints:
			if player.position.x >= cp.x and cp.x > checkpoint.x and absf(player.position.y - cp.y) < 2.5:
				checkpoint = cp
		if player.position.y < -4.0 and not hidden:
			_on_caught(false)


func _process(delta: float) -> void:
	t += delta
	cooldown = maxf(0.0, cooldown - delta)
	attack_t = maxf(0.0, attack_t - delta)
	shake = maxf(0.0, shake - delta * 1.5)
	if player == null or cam == null:
		return
	_camera(delta)

	# fire flicker
	for i in lamp_lights.size():
		var l: OmniLight3D = lamp_lights[i]
		var base: float = lamp_base[i]
		var f := 0.85 + 0.15 * sin(t * 11.0 + i * 1.7) * sin(t * 4.1 + i)
		l.light_energy = base * f
		(lamp_halos[i] as StandardMaterial3D).albedo_color.a = 0.5 * f
	if held_lamp != null:
		held_lamp.light_energy = 1.3 + 0.2 * sin(t * 9.0) * sin(t * 4.3)

	if dust != null:
		dust.global_position = Vector3(cam.global_position.x, cam.global_position.y, 0.0)
	if fog_p != null:
		fog_p.global_position = Vector3(cam.global_position.x, _h(cam.global_position.x) + 1.4, -2.0)
	if sky_root != null:
		sky_root.global_position = cam.global_position

	for c in coin_nodes:
		var pv = c["pivot"]
		if is_instance_valid(pv):
			pv.rotation.y += delta * 3.0

	# NPCs: Ammi looks at you, Yassine follows you
	var face: float = player.get("facing")
	var base_pos: Vector3 = hide_anchor if hidden else player.global_position
	if ammi != null:
		var arig = ammi.get_meta("rig")
		var dxa: float = player.global_position.x - ammi.global_position.x
		arig.animate(delta, 0.0, 0.0, true, false, false, signf(dxa) if absf(dxa) > 0.1 else 1.0, 0.0)
	if follower != null:
		var frig = follower.get_meta("rig")
		var fp: Vector3 = follower.position
		var tx := base_pos.x - face * 1.8
		if absf(tx - fp.x) > 12.0:
			fp.x = tx
		var nx := lerpf(fp.x, tx, 1.0 - exp(-2.5 * delta))
		var ny := lerpf(fp.y, base_pos.y, 1.0 - exp(-6.0 * delta))
		var vx := (nx - follower.position.x) / maxf(delta, 0.001)
		follower.position = Vector3(nx, ny, -0.6)
		frig.animate(delta, vx, 0.0, true, false, false, signf(vx) if absf(vx) > 0.3 else face, signf(vx) if absf(vx) > 0.3 else 0.0)

	banner_t -= delta
	if banner_label != null:
		banner_label.modulate.a = clampf(banner_t / 0.6, 0.0, 1.0)
	if banner_t <= 0.2 and not dialog_q.is_empty():
		_banner(str(dialog_q.pop_front()), 4.2)

	if not hidden:
		var px: float = player.global_position.x
		var tips := [
			[1.0, "Chaambi. Cold wind, long shadows. Jackals fear FIRE."],
			[14.0, "Talk to Ammi Brahim by the fire. Press USE."],
			[34.0, "Light braziers with USE: jackals will not cross their light."],
			[44.0, "The old rope bridge: some planks fall when you stand on them. Keep moving!"],
			[76.0, "The climb. Watch the shadows on the path: rocks fall from above."],
			[128.0, "A barricade blocks the summit. Fire will burn it."],
			[148.0, "The beacon is ahead. You need all three oil flasks."],
		]
		for i in tips.size():
			if not tips_shown.has(i) and px > float(tips[i][0]):
				tips_shown[i] = true
				_banner(str(tips[i][1]), 4.0)
				break

	ui_timer -= delta
	if ui_timer <= 0.0:
		ui_timer = 0.25
		_refresh_ui()
		_check_missions()
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
					"npc":
						txt = "TALK"
					"brazier":
						txt = "LIGHT"
					"hide":
						txt = "HIDE"
					"barricade":
						txt = "BURN"
					"beacon":
						txt = "BEACON"
		if txt != pad2.use_text or ready != pad2.use_ready:
			pad2.use_text = txt
			pad2.use_ready = ready
			pad2.queue_redraw()
	_update_weapon_visuals()

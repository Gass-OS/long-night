extends Node3D

const S = preload("res://settings.gd")
const DOOR_CLOSED_Y := 1.5
const DOOR_OPEN_Y := 4.7

const VIGNETTE := """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float v = smoothstep(0.28, 0.85, length(uv * vec2(1.15, 1.0)));
	float g = fract(sin(dot(UV * vec2(1280.0, 720.0) + vec2(TIME * 37.0, TIME * 11.0), vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(0.0, 0.0, 0.0, clamp(v * 0.75 + g * 0.07, 0.0, 1.0));
}
"""

var player: CharacterBody3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var cam_attrs: CameraAttributesPractical
var audio
var weather

var tex_alb: NoiseTexture2D
var tex_nrm: NoiseTexture2D

var plate: Area3D
var plate_mat: StandardMaterial3D
var plate_light: OmniLight3D
var door: AnimatableBody3D
var mover: AnimatableBody3D
var mover_t := 0.0

var dogs: Array = []
var crates: Array = []
var lamp_lights: Array = []
var lamp_base: Array = []
var lamp_xs: Array = []
var flick_t := 0.0
var fps_label: Label
var fps_timer := 0.0

var checkpoint := Vector3(0.0, 0.1, 0.0)
var checkpoint_xs: Array[float] = [28.5, 38.5, 66.8, 81.6, 100.8]
var dead := false
var finished := false
var fade: ColorRect
var msg_label: Label


func _ready() -> void:
	S.load_cfg()
	audio = Node.new()
	audio.set_script(load("res://audio.gd"))
	add_child(audio)

	_make_textures()
	_setup_environment()
	_build_level()
	_build_puzzle()
	_build_course()
	_build_decor()
	_build_foreground()

	player = CharacterBody3D.new()
	player.set_script(load("res://player.gd"))
	player.position = checkpoint
	add_child(player)
	player.rig.footstep.connect(_on_footstep)

	cam = Camera3D.new()
	cam.position = Vector3(0, 2.5, 9)
	cam_attrs = CameraAttributesPractical.new()
	cam_attrs.dof_blur_far_enabled = true
	cam_attrs.dof_blur_far_distance = 13.0
	cam_attrs.dof_blur_far_transition = 12.0
	cam_attrs.dof_blur_near_enabled = true
	cam_attrs.dof_blur_near_distance = 5.0
	cam_attrs.dof_blur_near_transition = 3.0
	cam_attrs.dof_blur_amount = 0.08
	cam.attributes = cam_attrs
	add_child(cam)
	cam.make_current()

	_add_dog(45.0, 43.0, 48.0)
	_add_dog(55.0, 52.5, 56.5)
	_add_dog(88.0, 85.0, 91.0)
	_build_exit()

	weather = Node3D.new()
	weather.set_script(load("res://weather.gd"))
	weather.cam = cam
	weather.sun = sun
	weather.env = env
	weather.audio = audio
	add_child(weather)

	var hud = CanvasLayer.new()
	hud.set_script(load("res://hud.gd"))
	hud.player = player
	add_child(hud)

	_build_overlay()
	_apply_quality()


func _make_textures() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.035
	n.fractal_octaves = 4
	n.seed = 3
	tex_alb = NoiseTexture2D.new()
	tex_alb.noise = n
	tex_alb.width = 512
	tex_alb.height = 512
	tex_alb.seamless = true

	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 0.09
	n2.fractal_octaves = 3
	n2.seed = 9
	tex_nrm = NoiseTexture2D.new()
	tex_nrm.noise = n2
	tex_nrm.width = 512
	tex_nrm.height = 512
	tex_nrm.seamless = true
	tex_nrm.as_normal_map = true
	tex_nrm.bump_strength = 7.0


func _surface_mat(color: Color, rough: float, tex_scale := 0.4) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r * 1.8, color.g * 1.8, color.b * 1.8)
	m.albedo_texture = tex_alb
	m.normal_enabled = true
	m.normal_texture = tex_nrm
	m.normal_scale = 1.2
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(tex_scale, tex_scale, tex_scale)
	return m


func _setup_environment() -> void:
	env = Environment.new()

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.015, 0.02, 0.04)
	sky_mat.sky_horizon_color = Color(0.07, 0.09, 0.13)
	sky_mat.ground_horizon_color = Color(0.07, 0.09, 0.13)
	sky_mat.ground_bottom_color = Color(0.02, 0.025, 0.04)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.36, 0.48)
	env.ambient_light_energy = 0.5

	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.09, 0.13)
	env.fog_density = 0.012

	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.035
	env.volumetric_fog_albedo = Color(0.5, 0.56, 0.66)
	env.volumetric_fog_emission = Color(0.01, 0.015, 0.025)
	env.volumetric_fog_length = 48.0
	env.volumetric_fog_anisotropy = 0.55
	env.volumetric_fog_ambient_inject = 0.3

	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 2.2

	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.6
	env.adjustment_contrast = 1.15

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 0.6
	sun.light_color = Color(0.6, 0.7, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.light_volumetric_fog_energy = 0.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)


func _apply_quality() -> void:
	var q: int = S.quality
	var vp := get_viewport()
	var msaa := [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X]
	var scale3d := [0.7, 0.85, 1.0]
	vp.msaa_3d = msaa[q]
	vp.scaling_3d_scale = scale3d[q]
	env.volumetric_fog_enabled = q >= 1
	env.ssao_enabled = q >= 2
	env.glow_enabled = q >= 1
	sun.shadow_enabled = q >= 1
	cam_attrs.dof_blur_far_enabled = q >= 2
	cam_attrs.dof_blur_near_enabled = q >= 2
	var rain_amounts := [600, 1000, 1500]
	weather.rain.amount = rain_amounts[q]


func _add_box(pos: Vector3, size: Vector3, color: Color, solid := true, rough := 0.85) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	mesh.material_override = _surface_mat(color, rough)
	body.add_child(mesh)
	if solid:
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
		body.add_child(col)
	add_child(body)


func _deco_box(pos: Vector3, size: Vector3, color: Color, rough := 0.9) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _surface_mat(color, rough)
	mi.position = pos
	add_child(mi)


func _ground(x0: float, x1: float) -> void:
	_add_box(Vector3((x0 + x1) / 2.0, -0.5, 0.0), Vector3(x1 - x0, 1.0, 4.0), Color(0.3, 0.26, 0.22), true, 0.28)


func _build_level() -> void:
	# Ground with two pits (64 to 66.4 and 92 to 100)
	_ground(-20.0, 64.0)
	_ground(66.4, 92.0)
	_ground(100.0, 114.0)
	_add_box(Vector3(6, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(9, 1.2, 0), Vector3(2, 0.4, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(12.5, 0.4, 0), Vector3(1.5, 0.8, 1.5), Color(0.45, 0.3, 0.2))
	# Low vent after the door: crouch to crawl under it
	_add_box(Vector3(34, 1.5, 0), Vector3(6, 1.0, 4), Color(0.2, 0.2, 0.24))
	# Safe platforms in the dog zone
	_add_box(Vector3(40.5, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(50.5, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))

	# Background buildings with details
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buildings: Array = []
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.1, 0.1, 0.11)
	metal.roughness = 0.6
	for i in range(26):
		var h := rng.randf_range(4.0, 9.0)
		var w := rng.randf_range(3.0, 5.0)
		var c := Vector3(i * 5.0 - 5.0, h / 2.0, -5.0 - rng.randf_range(0.0, 3.0))
		var tint := rng.randf_range(0.8, 1.2)
		_deco_box(c, Vector3(w, h, 2.0), Color(0.16 * tint, 0.15 * tint, 0.17 * tint), 0.95)
		buildings.append([c, w, h])
		if rng.randf() < 0.4:
			var tank := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.6
			cyl.bottom_radius = 0.6
			cyl.height = 1.2
			tank.mesh = cyl
			tank.material_override = metal
			tank.position = Vector3(c.x + rng.randf_range(-w / 3.0, w / 3.0), h + 0.6, c.z)
			add_child(tank)
		if rng.randf() < 0.4:
			var ant := MeshInstance3D.new()
			var ab := BoxMesh.new()
			ab.size = Vector3(0.04, 1.8, 0.04)
			ant.mesh = ab
			ant.material_override = metal
			ant.position = Vector3(c.x + rng.randf_range(-w / 3.0, w / 3.0), h + 0.9, c.z + 0.3)
			add_child(ant)
		for k in range(rng.randi_range(1, 3)):
			var ac := MeshInstance3D.new()
			var acb := BoxMesh.new()
			acb.size = Vector3(0.55, 0.38, 0.3)
			ac.mesh = acb
			ac.material_override = metal
			ac.position = Vector3(c.x + rng.randf_range(-w / 2.0 + 0.4, w / 2.0 - 0.4), rng.randf_range(1.5, maxf(h - 1.0, 1.6)), c.z + 1.15)
			add_child(ac)
	_build_windows(buildings)

	# Distant mountains (Chaambi silhouette)
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.05, 0.06, 0.08)
	for i in range(5):
		var pm := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(60.0, 24.0 + (i % 2) * 8.0, 10.0)
		pm.mesh = prism
		pm.material_override = mmat
		pm.position = Vector3(i * 38.0 - 10.0, 10.0, -48.0)
		add_child(pm)

	_build_rubble()


func _build_windows(buildings: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var lit: Array = []
	var dark: Array = []
	for b in buildings:
		var c: Vector3 = b[0]
		var w: float = b[1]
		var h: float = b[2]
		var cols := int(w / 1.1)
		var rows := int((h - 1.0) / 1.7)
		for ix in cols:
			for iy in rows:
				var x := c.x - w / 2.0 + (ix + 0.5) * (w / cols)
				var y := 1.4 + iy * 1.7
				var t := Transform3D(Basis(), Vector3(x, y, c.z + 1.02))
				if rng.randf() < 0.14:
					lit.append(t)
				else:
					dark.append(t)

	var lit_mat := StandardMaterial3D.new()
	lit_mat.albedo_color = Color(1.0, 0.75, 0.35)
	lit_mat.emission_enabled = true
	lit_mat.emission = Color(1.0, 0.7, 0.3)
	lit_mat.emission_energy_multiplier = 3.0
	_add_multimesh(lit, lit_mat, Vector3(0.45, 0.65, 0.04))

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.03, 0.04, 0.06)
	dark_mat.roughness = 0.2
	_add_multimesh(dark, dark_mat, Vector3(0.45, 0.65, 0.04))


func _add_multimesh(transforms: Array, mat: Material, size: Vector3) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = size
	mm.mesh = bm
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)


func _build_rubble() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var items: Array = []
	for i in range(220):
		var x := rng.randf_range(-8.0, 112.0)
		if _in_pit(x):
			continue
		var z := rng.randf_range(-1.9, -0.7) if rng.randf() < 0.5 else rng.randf_range(0.9, 1.9)
		var s := rng.randf_range(0.04, 0.2)
		var b := Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)).scaled(Vector3(s, s * 0.7, s))
		items.append(Transform3D(b, Vector3(x, s * 0.3, z)))
	_add_multimesh(items, _surface_mat(Color(0.2, 0.19, 0.19), 0.8, 1.2), Vector3(1.0, 1.0, 1.0))


func _add_crate(pos: Vector3) -> void:
	var rb := RigidBody3D.new()
	rb.position = pos
	rb.mass = 4.0
	rb.linear_damp = 5.0
	rb.gravity_scale = 2.0
	rb.axis_lock_linear_z = true
	rb.axis_lock_angular_x = true
	rb.axis_lock_angular_y = true
	rb.axis_lock_angular_z = true
	rb.add_to_group("crate")
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	mesh.mesh = bm
	mesh.material_override = _surface_mat(Color(0.45, 0.3, 0.2), 0.9, 1.0)
	rb.add_child(mesh)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1, 1, 1)
	col.shape = bs
	rb.add_child(col)
	add_child(rb)
	crates.append([rb, pos])


func _build_puzzle() -> void:
	_add_crate(Vector3(16.0, 0.52, 0.0))

	plate = Area3D.new()
	plate.position = Vector3(22.0, 0.0, 0.0)
	var pcol := CollisionShape3D.new()
	var pshape := BoxShape3D.new()
	pshape.size = Vector3(1.6, 0.4, 1.4)
	pcol.shape = pshape
	pcol.position.y = 0.2
	plate.add_child(pcol)
	var pm := MeshInstance3D.new()
	var pbox := BoxMesh.new()
	pbox.size = Vector3(1.6, 0.1, 2.0)
	pm.mesh = pbox
	plate_mat = StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.7, 0.1, 0.1)
	plate_mat.emission_enabled = true
	plate_mat.emission = Color(0.7, 0.1, 0.1)
	plate_mat.emission_energy_multiplier = 1.8
	pm.material_override = plate_mat
	pm.position.y = 0.05
	plate.add_child(pm)
	add_child(plate)

	plate_light = OmniLight3D.new()
	plate_light.position = Vector3(22.0, 1.6, 1.5)
	plate_light.omni_range = 5.0
	plate_light.light_energy = 0.8
	plate_light.light_color = Color(0.9, 0.15, 0.1)
	add_child(plate_light)

	door = AnimatableBody3D.new()
	door.position = Vector3(26.0, DOOR_CLOSED_Y, 0.0)
	var dmesh := MeshInstance3D.new()
	var dbox := BoxMesh.new()
	dbox.size = Vector3(0.5, 3.0, 4.0)
	dmesh.mesh = dbox
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.25, 0.25, 0.3)
	dmat.metallic = 0.4
	dmat.roughness = 0.5
	dmesh.material_override = dmat
	door.add_child(dmesh)
	var dcol := CollisionShape3D.new()
	var dshape := BoxShape3D.new()
	dshape.size = Vector3(0.5, 3.0, 4.0)
	dcol.shape = dshape
	door.add_child(dcol)
	add_child(door)


func _build_course() -> void:
	_add_crate(Vector3(72.0, 0.52, 0.0))
	_add_box(Vector3(80.0, 1.0, 0.0), Vector3(2.0, 2.0, 2.0), Color(0.28, 0.27, 0.3))

	mover = AnimatableBody3D.new()
	mover.position = Vector3(96.0, -0.25, 0.0)
	var mmesh := MeshInstance3D.new()
	var mbox := BoxMesh.new()
	mbox.size = Vector3(2.6, 0.5, 2.0)
	mmesh.mesh = mbox
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.3, 0.3, 0.34)
	mmat.metallic = 0.5
	mmat.roughness = 0.45
	mmesh.material_override = mmat
	mover.add_child(mmesh)
	var mcol := CollisionShape3D.new()
	var mshape := BoxShape3D.new()
	mshape.size = Vector3(2.6, 0.5, 2.0)
	mcol.shape = mshape
	mover.add_child(mcol)
	add_child(mover)


func _in_pit(x: float) -> bool:
	return (x > 63.0 and x < 67.5) or (x > 91.0 and x < 101.0)


func _build_decor() -> void:
	for x in [4.0, 17.0, 36.0, 62.0, 75.0, 94.0, 104.0]:
		_add_lamp(x)
	for i in range(lamp_xs.size() - 1):
		var xa: float = lamp_xs[i]
		var xb: float = lamp_xs[i + 1]
		_add_wire(Vector3(xa + 0.6, 3.4, -1.4), Vector3(xb, 3.4, -1.4), 0.8)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in range(18):
		var x := rng.randf_range(-6.0, 108.0)
		var z := rng.randf_range(-1.7, -1.1)
		if not _in_pit(x):
			_add_barrel(Vector3(x, 0.0, z))
	for i in range(14):
		var x := rng.randf_range(-6.0, 108.0)
		var z := rng.randf_range(0.2, 1.7)
		if not _in_pit(x):
			_add_puddle(Vector3(x, 0.006, z))

	# Cold light shafts through the fog
	for x in [18.0, 46.0, 72.0]:
		var sp := SpotLight3D.new()
		sp.position = Vector3(x, 9.0, -1.0)
		sp.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		sp.spot_range = 16.0
		sp.spot_angle = 24.0
		sp.light_energy = 5.0
		sp.light_color = Color(0.7, 0.8, 1.0)
		sp.light_volumetric_fog_energy = 3.0
		add_child(sp)


func _build_foreground() -> void:
	# Dark silhouettes close to the camera (blurred by depth of field)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.008, 0.008, 0.01)
	mat.roughness = 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var xs: Array = []
	var x := -8.0
	while x < 112.0:
		xs.append(x)
		x += rng.randf_range(14.0, 24.0)
	for px in xs:
		var pole := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.35, 14.0, 0.35)
		pole.mesh = pb
		pole.material_override = mat
		pole.position = Vector3(px, 6.0, 6.2)
		add_child(pole)
		var arm := MeshInstance3D.new()
		var ab := BoxMesh.new()
		ab.size = Vector3(3.0, 0.18, 0.18)
		arm.mesh = ab
		arm.material_override = mat
		arm.position = Vector3(px, 8.5, 6.2)
		add_child(arm)
	for i in range(xs.size() - 1):
		var xa: float = xs[i]
		var xb: float = xs[i + 1]
		_add_wire(Vector3(xa + 1.3, 8.5, 6.2), Vector3(xb - 1.3, 8.5, 6.2), 1.2)
		_add_wire(Vector3(xa - 1.3, 8.5, 6.2), Vector3(xb + 1.3, 8.5, 6.2), 1.0)


func _add_wire(a: Vector3, b: Vector3, sag: float) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(0, 17):
		var t := float(i) / 16.0
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.015, 0.015, 0.02)
	mi.material_override = mat
	add_child(mi)


func _add_lamp(x: float) -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.06, 0.06, 0.07)
	metal.roughness = 0.6

	var pole := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.12, 3.4, 0.12)
	pole.mesh = pm
	pole.material_override = metal
	pole.position = Vector3(x, 1.7, -1.4)
	add_child(pole)

	var arm := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.7, 0.08, 0.08)
	arm.mesh = am
	arm.material_override = metal
	arm.position = Vector3(x + 0.3, 3.4, -1.4)
	add_child(arm)

	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	bulb.mesh = sm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.8, 0.5)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.7, 0.35)
	bmat.emission_energy_multiplier = 4.0
	bulb.material_override = bmat
	bulb.position = Vector3(x + 0.6, 3.3, -1.4)
	add_child(bulb)

	var l := OmniLight3D.new()
	l.position = Vector3(x + 0.6, 3.2, -0.6)
	l.omni_range = 7.0
	l.light_energy = 1.6
	l.light_color = Color(1.0, 0.72, 0.4)
	add_child(l)
	lamp_lights.append(l)
	lamp_base.append(l.light_energy)
	lamp_xs.append(x)


func _add_barrel(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.32
	cyl.bottom_radius = 0.32
	cyl.height = 0.9
	mi.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.12, 0.08)
	mat.metallic = 0.3
	mat.roughness = 0.6
	mi.material_override = mat
	mi.position = Vector3(pos.x, 0.45, pos.z)
	add_child(mi)


func _add_puddle(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1.6, 0.9)
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.05, 0.07)
	mat.metallic = 0.9
	mat.roughness = 0.05
	mi.material_override = mat
	mi.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	mi.position = pos
	add_child(mi)


func _add_dog(x: float, left_x: float, right_x: float) -> void:
	var d = CharacterBody3D.new()
	d.set_script(load("res://dog.gd"))
	d.target = player
	d.left_x = left_x
	d.right_x = right_x
	d.position = Vector3(x, 0.05, 0.0)
	d.caught.connect(_on_caught)
	d.alerted.connect(_on_dog_alerted)
	add_child(d)
	dogs.append(d)


func _build_exit() -> void:
	var a := Area3D.new()
	a.position = Vector3(108.5, 0.0, 0.0)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.5, 3.0, 3.0)
	col.shape = shape
	col.position.y = 1.5
	a.add_child(col)
	add_child(a)
	a.body_entered.connect(_on_exit)

	var light := OmniLight3D.new()
	light.position = Vector3(107.8, 2.2, 1.0)
	light.omni_range = 9.0
	light.light_energy = 2.0
	light.light_color = Color(0.95, 0.85, 0.6)
	add_child(light)


func _build_overlay() -> void:
	# Vignette + film grain
	var vl := CanvasLayer.new()
	vl.layer = 5
	add_child(vl)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE
	var sm := ShaderMaterial.new()
	sm.shader = sh
	rect.material = sm
	vl.add_child(rect)

	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)

	fade = ColorRect.new()
	fade.color = Color(0.02, 0.0, 0.0, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.modulate.a = 0.0
	layer.add_child(fade)

	msg_label = Label.new()
	msg_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 90)
	msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_label.modulate.a = 0.0
	layer.add_child(msg_label)

	if S.show_fps:
		fps_label = Label.new()
		fps_label.position = Vector2(24, 16)
		fps_label.add_theme_font_size_override("font_size", 28)
		fps_label.modulate = Color(1, 1, 1, 0.7)
		layer.add_child(fps_label)


func _on_footstep(strength: float) -> void:
	if audio != null and not dead:
		audio.step(strength)


func _on_dog_alerted() -> void:
	if audio != null:
		audio.bark()


func _on_caught(use_ragdoll := true) -> void:
	if dead or finished:
		return
	dead = true
	if use_ragdoll:
		var push := 1.0
		var best := 1000000.0
		for d in dogs:
			var dist := absf(d.global_position.x - player.global_position.x)
			if dist < best:
				best = dist
				push = signf(player.global_position.x - d.global_position.x)
		player.die(push)
	player.set_physics_process(false)
	msg_label.text = "YOU DIED"
	msg_label.add_theme_color_override("font_color", Color(0.7, 0.1, 0.1))
	await get_tree().create_timer(1.2 if use_ragdoll else 0.1).timeout
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 0.5)
	tw.parallel().tween_property(msg_label, "modulate:a", 1.0, 0.8)
	await tw.finished
	await get_tree().create_timer(0.8).timeout

	player.respawn(checkpoint)
	for d in dogs:
		d.reset_state()
	for c in crates:
		var node: RigidBody3D = c[0]
		if node.position.y < -3.0:
			node.position = c[1]
			node.linear_velocity = Vector3.ZERO
	player.set_physics_process(true)
	dead = false

	var tw2 := create_tween()
	tw2.tween_property(fade, "modulate:a", 0.0, 0.6)
	tw2.parallel().tween_property(msg_label, "modulate:a", 0.0, 0.4)


func _on_exit(body: Node3D) -> void:
	if body != player or finished or dead:
		return
	finished = true
	player.set_physics_process(false)
	msg_label.text = "TO BE CONTINUED"
	msg_label.add_theme_color_override("font_color", Color(0.85, 0.82, 0.78))
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 1.0)
	tw.parallel().tween_property(msg_label, "modulate:a", 1.0, 1.4)
	await tw.finished
	await get_tree().create_timer(2.5).timeout
	get_tree().change_scene_to_file("res://menu.tscn")


func _physics_process(delta: float) -> void:
	if plate != null and door != null:
		var pressed := false
		for b in plate.get_overlapping_bodies():
			if b is CharacterBody3D or b is RigidBody3D:
				if b is CharacterBody3D and b != player:
					continue
				pressed = true
				break
		var c := Color(0.1, 0.8, 0.3) if pressed else Color(0.7, 0.1, 0.1)
		plate_mat.albedo_color = c
		plate_mat.emission = c
		plate_light.light_color = c
		var target := DOOR_OPEN_Y if pressed else DOOR_CLOSED_Y
		door.position.y = move_toward(door.position.y, target, 4.0 * delta)

	if mover != null:
		mover_t += delta
		mover.position.x = 96.0 + 2.2 * sin(mover_t * 0.9)

	if player != null and not dead and not finished:
		for cx in checkpoint_xs:
			if player.position.x >= cx and cx > checkpoint.x:
				checkpoint = Vector3(cx, 0.1, 0.0)
		if player.position.y < -8.0:
			_on_caught(false)


func _process(delta: float) -> void:
	if player != null and cam != null:
		var target := Vector3(player.position.x, player.position.y + 2.5, 9.0)
		cam.position = cam.position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))

	flick_t += delta
	for i in lamp_lights.size():
		var l: OmniLight3D = lamp_lights[i]
		var base: float = lamp_base[i]
		if i % 2 == 0:
			l.light_energy = base * (0.95 + 0.05 * sin(flick_t * 9.0 + i))
		else:
			var n := sin(flick_t * 23.0 + i * 5.0) * sin(flick_t * 3.7 + i)
			l.light_energy = base * (0.1 if n > 0.7 else 1.0)

	if fps_label != null:
		fps_timer -= delta
		if fps_timer <= 0.0:
			fps_timer = 0.5
			fps_label.text = "FPS %d" % Engine.get_frames_per_second()

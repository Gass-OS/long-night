#!/data/data/com.termux/files/usr/bin/bash
# Long Night - Step 15: STAGE 2 "Kasserine, the old medina"
# New scene (stage2.tscn). Your stage 1 files are NOT overwritten.
# Needs from earlier steps: player.gd, character.gd, dog.gd, hud.gd, audio.gd, settings.gd, menu.gd
set -e
cd ~/long-night

mkdir -p ~/long-night-backup-step15
cp -f *.gd *.tscn project.godot ~/long-night-backup-step15/ 2>/dev/null || true
git tag -f backup-before-step15 >/dev/null 2>&1 || true

cat > stage2.tscn << 'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://stage2.gd" id="1"]

[node name="Stage2" type="Node3D"]
script = ExtResource("1")
EOF

# ------------------------------------------------------------------
# Thug: human enemy with a lantern cone (uses the procedural skeleton)
# ------------------------------------------------------------------
cat > thug.gd << 'EOF'
extends CharacterBody3D
# A Jackals gang member: patrols with a lantern, sees only inside the light cone.

signal caught
signal alerted

const GRAVITY := 18.0
const PATROL_SPEED := 1.2
const CHASE_SPEED := 3.6

var target
var left_x := 0.0
var right_x := 0.0
var start_x := 0.0
var facing := 1.0
var chasing := false
var ignore_timer := 0.0
var wait_timer := 0.0
var above_timer := 0.0
var hp := 2
var assist := 1.0
var rig: Node3D
var spot: SpotLight3D


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	start_x = position.x
	var col := CollisionShape3D.new()
	var sh := CapsuleShape3D.new()
	sh.radius = 0.3
	sh.height = 1.8
	col.shape = sh
	col.position.y = 0.9
	add_child(col)

	rig = Node3D.new()
	rig.set_script(load("res://character.gd"))
	rig.scale = Vector3(1.2, 1.2, 1.2)
	add_child(rig)
	_recolor(rig)

	spot = SpotLight3D.new()
	spot.position = Vector3(0.0, 1.3, 0.3)
	spot.rotation_degrees = Vector3(-12.0, 180.0, 0.0)
	spot.spot_angle = 30.0
	spot.spot_range = 10.0
	spot.light_energy = 6.0
	spot.light_color = Color(1.0, 0.85, 0.6)
	spot.light_volumetric_fog_energy = 3.0
	rig.add_child(spot)


func _recolor(node: Node) -> void:
	if node is MeshInstance3D:
		var m := node.material_override as StandardMaterial3D
		if m != null:
			var c := m.albedo_color
			if c.is_equal_approx(Color(0.62, 0.09, 0.07)):
				m.albedo_color = Color(0.07, 0.07, 0.08)
			elif c.is_equal_approx(Color(0.1, 0.1, 0.13)):
				m.albedo_color = Color(0.16, 0.12, 0.08)
	for ch in node.get_children():
		_recolor(ch)


func reset_state() -> void:
	position = Vector3(start_x, position.y, 0.0)
	velocity = Vector3.ZERO
	chasing = false
	ignore_timer = 1.5
	wait_timer = 0.0
	above_timer = 0.0


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var dx: float = target.global_position.x - global_position.x
	var dy: float = target.global_position.y - global_position.y
	var crouched: bool = target.crouching
	ignore_timer = maxf(0.0, ignore_timer - delta)

	var sight := (4.5 if crouched else 9.0) * assist
	var hear := (0.8 if crouched else 1.8) * assist
	var sees := absf(dy) < 2.0 and ((signf(dx) == facing and absf(dx) < sight) or absf(dx) < hear)
	if ignore_timer <= 0.0 and sees:
		if not chasing:
			alerted.emit()
		chasing = true
	if chasing and absf(dx) > 13.0:
		chasing = false

	var move := 0.0
	var speed := PATROL_SPEED
	if chasing:
		if absf(dx) > 0.05:
			facing = signf(dx)
		if dy > 0.9 and absf(dx) < 1.3:
			above_timer += delta
			if above_timer > 2.5:
				chasing = false
				ignore_timer = 3.0
				above_timer = 0.0
		else:
			above_timer = 0.0
			speed = CHASE_SPEED
			if absf(dx) > 0.05:
				move = facing
	else:
		above_timer = 0.0
		if wait_timer > 0.0:
			wait_timer -= delta
		else:
			move = facing
			if (facing > 0.0 and position.x >= right_x) or (facing < 0.0 and position.x <= left_x):
				facing = -facing
				wait_timer = 1.6
				move = 0.0

	velocity.x = move * speed
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	position.z = 0.0

	if absf(dx) < 0.9 and dy < 0.9 and dy > -1.5:
		caught.emit()

	rig.animate(delta, velocity.x, velocity.y, is_on_floor(), false, false, facing, move)
	if spot != null:
		spot.light_energy = 9.0 if chasing else 6.0
		spot.light_color = Color(1.0, 0.35, 0.25) if chasing else Color(1.0, 0.85, 0.6)
EOF

# ------------------------------------------------------------------
# Medina hook (autoload): menu button + automatic jump from stage 1
# ------------------------------------------------------------------
cat > medina.gd << 'EOF'
extends Node

var menu_done: Node = null
var chain_done: Node = null


func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	if cs.get("main_box") != null and cs.get("settings_box") != null:
		if menu_done != cs:
			menu_done = cs
			_inject_menu(cs)
		return
	# Stage 1 finished: continue straight to stage 2
	if cs.get("finished") == true and cs.get("weather") != null and cs.get("dogs") != null:
		if chain_done != cs:
			chain_done = cs
			_continue(cs)


func _continue(cs: Node) -> void:
	await get_tree().create_timer(2.6).timeout
	if is_instance_valid(cs) and get_tree().current_scene == cs:
		get_tree().change_scene_to_file("res://stage2.tscn")


func _inject_menu(menu: Node) -> void:
	var box = menu.get("main_box")
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(520, 84)
	btn.add_theme_font_size_override("font_size", 36)
	btn.text = "STAGE 2  -  MEDINA"
	btn.pressed.connect(func(): get_tree().change_scene_to_file("res://stage2.tscn"))
	box.add_child(btn)
	var idx := 0
	for i in box.get_child_count():
		var c = box.get_child(i)
		if c is Button and c.text == "PLAY":
			idx = i + 1
			break
	box.move_child(btn, idx)
EOF

# ------------------------------------------------------------------
# Stage 2 level
# ------------------------------------------------------------------
cat > stage2.gd << 'EOF'
extends Node3D
# STAGE 2: Kasserine, the old medina (Tunisia). Self-contained level and gameplay.

const S = preload("res://settings.gd")

const VIGNETTE := """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float v = smoothstep(0.26, 0.85, length(uv * vec2(1.15, 1.0)));
	float g = fract(sin(dot(UV * vec2(1280.0, 720.0) + vec2(TIME * 37.0, TIME * 11.0), vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(0.02, 0.01, 0.0, clamp(v * 0.8 + g * 0.07, 0.0, 1.0));
}
"""

const KEYS := [
	{"x": -14.0, "yaw": 8.0, "h": 2.4, "dist": 10.0, "fov": 52.0},
	{"x": 30.0, "yaw": 8.0, "h": 2.4, "dist": 10.0, "fov": 52.0},
	{"x": 42.0, "yaw": -10.0, "h": 1.7, "dist": 8.6, "fov": 50.0},
	{"x": 56.0, "yaw": 12.0, "h": 2.6, "dist": 11.0, "fov": 55.0},
	{"x": 96.0, "yaw": 12.0, "h": 3.0, "dist": 12.5, "fov": 56.0},
	{"x": 114.0, "yaw": -8.0, "h": 2.2, "dist": 10.0, "fov": 52.0},
	{"x": 160.0, "yaw": 0.0, "h": 2.0, "dist": 9.0, "fov": 50.0},
]

const REWARDS := [3, 5, 10, 0, 10, 15]

var stage := 2
var player: CharacterBody3D
var cam: Camera3D
var env: Environment
var weather = null   # intentionally null: the stage 1 layers must skip this scene
var sun: DirectionalLight3D
var cam_attrs: CameraAttributesPractical
var audio

var tex_alb: NoiseTexture2D
var tex_nrm: NoiseTexture2D

var dogs: Array = []
var thugs: Array = []
var crates: Array = []
var lamp_lights: Array = []
var lamp_base: Array = []
var lamp_halos: Array = []
var interactables: Array = []
var coin_nodes: Array = []
var mark_nodes: Array = []
var mover: AnimatableBody3D
var mover_t := 0.0
var gate_l: AnimatableBody3D
var gate_r: AnimatableBody3D
var merchant: Node3D
var yassine: Node3D
var dust: GPUParticles3D
var held_lamp: OmniLight3D

var checkpoint := Vector3(0.0, 0.1, 0.0)
var checkpoints := [Vector3(0, 0.1, 0), Vector3(27, 0.1, 0), Vector3(57, 4.7, 0), Vector3(99, 4.7, 0), Vector3(116, 0.1, 0), Vector3(138, 0.1, 0)]
var dead := false
var finished := false
var deaths := 0
var death_zone := -1
var fade: ColorRect
var msg_label: Label

# camera
var focus := Vector3.ZERO
var focus_ready := false
var t := 0.0
var shake := 0.0

# inventory (shared with stage 1 through the City autoload when present)
var coins := 0
var pickups := 0
var has_sword := false
var has_gun := false
var ammo := 0
var weapon := 0

# story / missions
var m_idx := 0
var marks := 0
var talked := false
var has_lantern := false
var has_key := false
var gate_open := false
var kills := 0
var hidden := false
var hide_anchor := Vector3.ZERO

# combat / UI
var cooldown := 0.0
var attack_t := 0.0
var weapon_nodes: Array = []
var dialog_q: Array = []
var banner_t := 0.0
var shop_open := false
var ui: CanvasLayer
var pad2
var coin_label: Label
var weapon_label: Label
var mission_label: Label
var banner_label: Label
var shop_panel: Control
var shop_title: Label
var shop_coins: Label
var shop_buttons: Array = []
var ui_timer := 0.0
var sfx := {}
var gold_mat: StandardMaterial3D = null
var radial_tex: GradientTexture2D = null
var tips_shown := {}


class StagePad extends Control:
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


# ====================================================================
# setup
# ====================================================================

func _ready() -> void:
	S.load_cfg()
	_load_inventory()
	_make_textures()
	_setup_environment()
	_build_ground()
	_build_souk()
	_build_cart_climb()
	_build_covered_alleys()
	_build_kasbah()
	_build_facades()
	_build_skyline()
	_build_decor()
	_spawn_player()
	_spawn_enemies()
	_build_coins()
	_build_marks()
	_build_dust()

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


func _city():
	return get_node_or_null("/root/City")


func _load_inventory() -> void:
	var c = _city()
	if c != null:
		coins = int(c.get("coins"))
		pickups = int(c.get("pickups"))
		has_sword = bool(c.get("has_sword"))
		has_gun = bool(c.get("has_gun"))
		ammo = int(c.get("ammo"))
		weapon = int(c.get("weapon"))
		return
	var cf := ConfigFile.new()
	if cf.load("user://progress.cfg") == OK:
		coins = int(cf.get_value("p", "coins", 0))
		pickups = int(cf.get_value("p", "pickups", 0))
		has_sword = bool(cf.get_value("p", "sword", false))
		has_gun = bool(cf.get_value("p", "gun", false))
		ammo = int(cf.get_value("p", "ammo", 0))
		weapon = int(cf.get_value("p", "weapon", 0))


func _save_inventory() -> void:
	var c = _city()
	if c != null:
		c.set("coins", coins)
		c.set("pickups", pickups)
		c.set("has_sword", has_sword)
		c.set("has_gun", has_gun)
		c.set("ammo", ammo)
		c.set("weapon", weapon)
		c.call("_save")
		return
	var cf := ConfigFile.new()
	cf.load("user://progress.cfg")
	cf.set_value("p", "coins", coins)
	cf.set_value("p", "pickups", pickups)
	cf.set_value("p", "sword", has_sword)
	cf.set_value("p", "gun", has_gun)
	cf.set_value("p", "ammo", ammo)
	cf.set_value("p", "weapon", weapon)
	cf.save("user://progress.cfg")


# ====================================================================
# materials and small helpers
# ====================================================================

func _make_textures() -> void:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	n.fractal_octaves = 4
	n.seed = 5
	tex_alb = NoiseTexture2D.new()
	tex_alb.noise = n
	tex_alb.width = 512
	tex_alb.height = 512
	tex_alb.seamless = true
	var n2 := FastNoiseLite.new()
	n2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n2.frequency = 0.08
	n2.fractal_octaves = 3
	n2.seed = 12
	tex_nrm = NoiseTexture2D.new()
	tex_nrm.noise = n2
	tex_nrm.width = 512
	tex_nrm.height = 512
	tex_nrm.seamless = true
	tex_nrm.as_normal_map = true
	tex_nrm.bump_strength = 5.0


func _surf(color: Color, rough := 0.85, tile := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color.r * 1.7, color.g * 1.7, color.b * 1.7)
	m.albedo_texture = tex_alb
	m.normal_enabled = true
	m.normal_texture = tex_nrm
	m.normal_scale = 0.35
	m.roughness = rough
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3(tile, tile, tile)
	return m


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


func _solid(pos: Vector3, size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	mesh.mesh = _box(size)
	mesh.material_override = mat
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	col.shape = bs
	body.add_child(col)
	add_child(body)
	return body


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


func _halo(pos: Vector3, size: float, color: Color) -> StandardMaterial3D:
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
	add_child(mi)
	return m


func _label3d(text: String, pos: Vector3, size: int, color: Color) -> Label3D:
	var lb := Label3D.new()
	lb.text = text
	lb.font_size = size
	lb.pixel_size = 0.01
	lb.modulate = color
	lb.outline_size = 6
	lb.position = pos
	add_child(lb)
	return lb


func _omni(pos: Vector3, color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.light_volumetric_fog_energy = 1.5
	add_child(l)
	return l


func _stripe_tex(c1: Color, c2: Color) -> ImageTexture:
	var img := Image.create(32, 8, false, Image.FORMAT_RGB8)
	for x in 32:
		var c := c1 if ((x >> 2) & 1) == 0 else c2
		for y in 8:
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _zellige_tex() -> ImageTexture:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var d := absi(x - 32) + absi(y - 32)
			var c := Color(0.1, 0.28, 0.5) if (d % 16) < 8 else Color(0.78, 0.74, 0.64)
			if x % 32 == 0 or y % 32 == 0:
				c = Color(0.04, 0.04, 0.05)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func _tex_mat(tex: Texture2D, tint: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.albedo_color = tint
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	return m


func _csg_box(parent: Node, size: Vector3, pos: Vector3, sub := false, mat: Material = null) -> CSGBox3D:
	var b := CSGBox3D.new()
	b.size = size
	b.position = pos
	if sub:
		b.operation = CSGShape3D.OPERATION_SUBTRACTION
	if mat != null:
		b.material = mat
	parent.add_child(b)
	return b


func _csg_cyl_x(parent: Node, radius: float, length: float, pos: Vector3) -> CSGCylinder3D:
	var c := CSGCylinder3D.new()
	c.radius = radius
	c.height = length
	c.sides = 24
	c.position = pos
	c.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	c.operation = CSGShape3D.OPERATION_SUBTRACTION
	parent.add_child(c)
	return c


func _wire(a: Vector3, b: Vector3, sag: float) -> void:
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for i in range(0, 17):
		var u := float(i) / 16.0
		var p := a.lerp(b, u)
		p.y -= sag * 4.0 * u * (1.0 - u)
		im.surface_add_vertex(p)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.03, 0.025, 0.02)
	mi.material_override = m
	add_child(mi)


func _multimesh(transforms: Array, mat: Material, size: Vector3) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _box(size)
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)


# ====================================================================
# environment: warm dusty fog, cold moon, strong depth of field
# ====================================================================

func _setup_environment() -> void:
	env = Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.02, 0.025, 0.045)
	sky_mat.sky_horizon_color = Color(0.16, 0.11, 0.08)
	sky_mat.ground_horizon_color = Color(0.16, 0.11, 0.08)
	sky_mat.ground_bottom_color = Color(0.03, 0.025, 0.02)
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.28, 0.3, 0.4)
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_color = Color(0.16, 0.12, 0.09)
	env.fog_density = 0.02
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.05
	env.volumetric_fog_albedo = Color(0.75, 0.6, 0.45)
	env.volumetric_fog_emission = Color(0.02, 0.012, 0.006)
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
	sun.light_energy = 0.5
	sun.light_color = Color(0.6, 0.7, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.light_volumetric_fog_energy = 0.8
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-30.0, 180.0, 0.0)
	rim.light_energy = 0.35
	rim.light_color = Color(1.0, 0.7, 0.45)
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
	cam_attrs.exposure_multiplier = 1.25
	cam.attributes = cam_attrs
	cam.fov = 52.0
	cam.position = Vector3(0, 4, 10)
	add_child(cam)
	cam.make_current()


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
	if dust != null:
		dust.amount = [60, 110, 160][q]


# ====================================================================
# world: ground
# ====================================================================

func _build_ground() -> void:
	var paving := _surf(Color(0.3, 0.26, 0.21), 0.4, 0.3)
	_solid(Vector3(73.0, -0.5, 0.0), Vector3(174.0, 1.0, 4.0), paving)
	# visual ground behind and in front of the lane
	var far_mat := _surf(Color(0.14, 0.12, 0.1), 0.5, 0.25)
	_mi(self, _box(Vector3(400.0, 1.0, 140.0)), far_mat, Vector3(70.0, -0.58, -72.0))
	_mi(self, _box(Vector3(400.0, 1.0, 14.0)), far_mat, Vector3(70.0, -0.58, 9.0))
	# zellige tiles in the Kasbah courtyard
	var tiles := _tex_mat(_zellige_tex(), Color(0.45, 0.45, 0.5), 0.35)
	tiles.uv1_scale = Vector3(14.0, 1.0, 1.0)
	var q := QuadMesh.new()
	q.size = Vector2(28.0, 3.6)
	var tq := _mi(self, q, tiles, Vector3(131.0, 0.01, 0.0))
	tq.rotation_degrees = Vector3(-90.0, 0.0, 0.0)


# ====================================================================
# world: the souk
# ====================================================================

func _arch_gate(x: float) -> void:
	var root := CSGCombiner3D.new()
	root.use_collision = true
	root.position = Vector3(x, 0.0, 0.0)
	add_child(root)
	_csg_box(root, Vector3(1.6, 5.4, 8.0), Vector3(0, 2.7, 0), false, _surf(Color(0.62, 0.55, 0.45), 0.9, 0.3))
	_csg_box(root, Vector3(2.4, 2.6, 2.6), Vector3(0, 1.3, 0), true)
	_csg_cyl_x(root, 1.3, 2.4, Vector3(0, 2.6, 0))
	_label3d("BAB EL MEDINA", Vector3(x, 4.5, 0.9), 64, Color(1.0, 0.8, 0.5))


func _sabat(x0: float, x1: float) -> void:
	var length := x1 - x0
	var root := CSGCombiner3D.new()
	root.use_collision = true
	root.position = Vector3((x0 + x1) / 2.0, 0.0, 0.0)
	add_child(root)
	_csg_box(root, Vector3(length, 4.6, 4.0), Vector3(0, 2.3, 0), false, _surf(Color(0.6, 0.53, 0.43), 0.9, 0.3))
	_csg_box(root, Vector3(length + 0.4, 2.2, 2.6), Vector3(0, 1.1, 0), true)
	_csg_cyl_x(root, 1.3, length + 0.4, Vector3(0, 2.2, 0))


func _lantern(pos: Vector3, real_light: bool) -> void:
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.06
	cyl.bottom_radius = 0.1
	cyl.height = 0.28
	_mi(self, cyl, _glow(Color(1.0, 0.6, 0.25), 2.5), pos)
	var hm := _halo(pos, 1.5, Color(1.0, 0.65, 0.3, 0.5))
	if real_light:
		var l := _omni(pos + Vector3(0, 0, 0.6), Color(1.0, 0.65, 0.32), 1.4, 7.0)
		lamp_lights.append(l)
		lamp_base.append(l.light_energy)
		lamp_halos.append(hm)


func _lantern_run(x0: float, x1: float, y: float, z: float) -> void:
	_wire(Vector3(x0, y + 0.25, z), Vector3(x1, y + 0.25, z), 0.4)
	var x := x0 + 1.4
	var k := 0
	while x < x1:
		_lantern(Vector3(x, y, z), k % 4 == 1)
		x += 2.8
		k += 1


func _stall(x: float, c1: Color, c2: Color) -> void:
	var wood := _mat(Color(0.2, 0.12, 0.07), 0.8)
	var stripes := _stripe_tex(c1, c2)
	var cloth := _tex_mat(stripes, Color(0.7, 0.7, 0.7), 0.95)
	cloth.uv1_scale = Vector3(3.0, 1.0, 1.0)
	_mi(self, _box(Vector3(0.12, 2.6, 0.12)), wood, Vector3(x - 1.8, 1.3, -0.9))
	_mi(self, _box(Vector3(0.12, 2.6, 0.12)), wood, Vector3(x + 1.8, 1.3, -0.9))
	_mi(self, _box(Vector3(3.2, 0.9, 0.8)), wood, Vector3(x, 0.45, -1.5))
	var aw := _mi(self, _box(Vector3(4.0, 0.05, 1.7)), cloth, Vector3(x, 2.55, -1.3))
	aw.rotation_degrees.x = 12.0
	# hanging carpets on the back wall
	var rug_tex := _stripe_tex(Color(0.55, 0.1, 0.08), Color(0.12, 0.2, 0.4))
	for k in 3:
		var qm := QuadMesh.new()
		qm.size = Vector2(0.9, 1.5)
		var rug := _mi(self, qm, _tex_mat(rug_tex, Color(0.8, 0.75, 0.7), 1.0), Vector3(x - 1.1 + k * 1.1, 1.7, -2.2))
		rug.rotation_degrees.y = 0.0
	# clay jars
	var clay := _mat(Color(0.45, 0.22, 0.12), 0.7)
	for k in 3:
		var sm := SphereMesh.new()
		sm.radius = 0.2
		sm.height = 0.4
		_mi(self, sm, clay, Vector3(x - 1.0 + k * 0.9, 1.1, -1.5))


func _npc(x: float, robe: Color) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(x, 0.0, -0.6)
	add_child(n)
	var rig := Node3D.new()
	rig.set_script(load("res://character.gd"))
	n.add_child(rig)
	_recolor(rig, Color(0.62, 0.09, 0.07), robe)
	_recolor(rig, Color(0.1, 0.1, 0.13), Color(robe.r * 0.8, robe.g * 0.8, robe.b * 0.8))
	n.set_meta("rig", rig)
	return n


func _recolor(node: Node, from: Color, to: Color) -> void:
	if node is MeshInstance3D:
		var m := node.material_override as StandardMaterial3D
		if m != null and m.albedo_color.is_equal_approx(from):
			m.albedo_color = to
	for ch in node.get_children():
		_recolor(ch, from, to)


func _build_souk() -> void:
	_arch_gate(4.0)
	_lantern_run(6.0, 46.0, 3.4, -1.8)

	_stall(10.0, Color(0.6, 0.1, 0.08), Color(0.85, 0.8, 0.7))
	_stall(16.0, Color(0.1, 0.3, 0.5), Color(0.85, 0.8, 0.7))
	_stall(22.0, Color(0.5, 0.35, 0.1), Color(0.85, 0.8, 0.7))
	_stall(30.0, Color(0.25, 0.25, 0.28), Color(0.5, 0.2, 0.1))
	_stall(38.0, Color(0.1, 0.4, 0.25), Color(0.85, 0.8, 0.7))

	# Hajj Salah, the merchant (white robe, chechia hat)
	merchant = _npc(16.0, Color(0.78, 0.76, 0.7))
	var mrig: Node3D = merchant.get_meta("rig")
	var hat := CylinderMesh.new()
	hat.top_radius = 0.05
	hat.bottom_radius = 0.1
	hat.height = 0.16
	var head = mrig.get("head")
	if head != null:
		_mi(head, hat, _mat(Color(0.55, 0.05, 0.05), 0.9), Vector3(0, 0.2, 0))
	var robe := CylinderMesh.new()
	robe.top_radius = 0.17
	robe.bottom_radius = 0.24
	robe.height = 0.75
	_mi(mrig, robe, _mat(Color(0.78, 0.76, 0.7), 0.95), Vector3(0, 0.42, 0))
	_label3d("HAJJ SALAH", Vector3(16.0, 2.0, -0.6), 40, Color(1.0, 0.9, 0.7))
	interactables.append({"x": 16.0, "y": 0.0, "kind": "npc", "r": 2.4})

	# Blacksmith: sells sword and pistol
	_label3d("THE BLACKSMITH", Vector3(30.0, 2.95, -1.8), 60, Color(1.0, 0.55, 0.25))
	_omni(Vector3(30.0, 2.2, -0.6), Color(1.0, 0.5, 0.2), 1.2, 6.0)
	interactables.append({"x": 30.0, "y": 0.0, "kind": "shop", "r": 2.4})

	# Hide spots: big rugs hanging in a nook
	var rug_tex := _stripe_tex(Color(0.45, 0.08, 0.1), Color(0.1, 0.25, 0.3))
	for hx in [22.0, 38.0]:
		var qm := QuadMesh.new()
		qm.size = Vector2(2.2, 2.4)
		_mi(self, qm, _tex_mat(rug_tex, Color(0.7, 0.65, 0.6), 1.0), Vector3(hx, 1.3, -0.55))
		_label3d("HIDE", Vector3(hx, 2.7, -0.5), 40, Color(0.4, 1.0, 0.6))
		interactables.append({"x": hx, "y": 0.0, "kind": "hide", "r": 1.7})


func _build_cart_climb() -> void:
	var stone := _surf(Color(0.5, 0.44, 0.36), 0.9, 0.3)
	# the merchant's cart (push it against the ledge)
	_add_cart(Vector3(42.0, 0.52, 0.0))
	_solid(Vector3(48.0, 0.95, 0.0), Vector3(2.0, 1.9, 2.0), stone)
	_solid(Vector3(50.0, 1.5, 0.0), Vector3(2.0, 3.0, 2.0), stone)
	_solid(Vector3(53.0, 2.1, 0.0), Vector3(3.0, 4.2, 2.0), _surf(Color(0.42, 0.36, 0.3), 0.95, 0.3))
	# rubble decoration
	var rub := _mat(Color(0.3, 0.26, 0.22), 0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for k in 14:
		var s := rng.randf_range(0.15, 0.5)
		var b := _mi(self, _box(Vector3(s, s * 0.7, s)), rub, Vector3(rng.randf_range(51.0, 55.5), rng.randf_range(0.1, 4.3), rng.randf_range(0.8, 1.6)))
		b.rotation = Vector3(rng.randf() * 3.0, rng.randf() * 3.0, rng.randf() * 3.0)
	_label3d("COLLAPSED WALL - find another way", Vector3(48.0, 4.6, 1.0), 36, Color(1.0, 0.8, 0.5))


func _add_cart(pos: Vector3) -> void:
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
	var wood := _mat(Color(0.28, 0.16, 0.08), 0.85)
	_mi(rb, _box(Vector3(1.4, 0.7, 1.0)), wood, Vector3(0, 0.15, 0))
	_mi(rb, _box(Vector3(1.4, 0.15, 1.05)), _mat(Color(0.2, 0.12, 0.06), 0.9), Vector3(0, 0.55, 0))
	for wz in [-0.55, 0.55]:
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.33
		cyl.bottom_radius = 0.33
		cyl.height = 0.08
		var wheel := _mi(rb, cyl, _mat(Color(0.1, 0.07, 0.04), 0.9), Vector3(0, -0.17, wz))
		wheel.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.4, 1.0, 1.0)
	col.shape = bs
	rb.add_child(col)
	add_child(rb)
	crates.append([rb, pos])


# ====================================================================
# world: covered alleys (sabat) and roofs
# ====================================================================

func _build_covered_alleys() -> void:
	_sabat(56.0, 66.0)
	_sabat(68.6, 78.6)
	_sabat(81.2, 91.0)
	_sabat(98.0, 112.0)

	# roof details: parapets, water tanks, antennas
	var par := _surf(Color(0.62, 0.55, 0.45), 0.9, 0.3)
	var metal := _mat(Color(0.12, 0.12, 0.13), 0.6, 0.4)
	for r in [[56.0, 66.0], [68.6, 78.6], [81.2, 91.0], [98.0, 112.0]]:
		var cx := (float(r[0]) + float(r[1])) / 2.0
		var length := float(r[1]) - float(r[0])
		_mi(self, _box(Vector3(length, 0.5, 0.2)), par, Vector3(cx, 4.85, -1.9))
		var tank := CylinderMesh.new()
		tank.top_radius = 0.6
		tank.bottom_radius = 0.6
		tank.height = 1.2
		_mi(self, tank, metal, Vector3(cx + length * 0.3, 5.2, -1.2))
		_mi(self, _box(Vector3(0.04, 2.0, 0.04)), metal, Vector3(cx - length * 0.3, 5.6, -1.5))

	# clotheslines across the gaps
	var cols := [Color(0.7, 0.15, 0.1), Color(0.15, 0.3, 0.6), Color(0.8, 0.75, 0.6), Color(0.2, 0.5, 0.3)]
	for g in [[66.0, 68.6], [78.6, 81.2]]:
		_wire(Vector3(g[0], 5.9, -1.4), Vector3(g[1], 5.9, -1.4), 0.4)
		for k in 4:
			var qm := QuadMesh.new()
			qm.size = Vector2(0.4, 0.6)
			var cl := _mi(self, qm, _mat(cols[k], 0.95), Vector3(g[0] + 0.4 + k * 0.5, 5.5, -1.4))
			cl.rotation_degrees.y = 15.0 * (k % 2 - 0.5)
	_lantern_run(56.0, 66.0, 6.1, -1.6)
	_lantern_run(98.0, 112.0, 6.1, -1.6)

	# swinging plank over the big gap
	mover = AnimatableBody3D.new()
	mover.position = Vector3(94.5, 4.35, 0.0)
	var wood := _mat(Color(0.28, 0.17, 0.09), 0.85)
	_mi(mover, _box(Vector3(2.6, 0.5, 2.0)), wood, Vector3.ZERO)
	var mcol := CollisionShape3D.new()
	var mshape := BoxShape3D.new()
	mshape.size = Vector3(2.6, 0.5, 2.0)
	mcol.shape = mshape
	mover.add_child(mcol)
	add_child(mover)
	_wire(Vector3(91.0, 6.4, -1.0), Vector3(98.0, 6.4, -1.0), 0.5)

	# a hiding place on the third roof (sacks) and steps down to the courtyard
	_label3d("HIDE", Vector3(84.5, 6.4, -0.5), 40, Color(0.4, 1.0, 0.6))
	var sack := _mat(Color(0.5, 0.42, 0.3), 1.0)
	for k in 3:
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.7
		_mi(self, sm, sack, Vector3(84.0 + k * 0.5, 5.0, -0.9))
	interactables.append({"x": 84.5, "y": 4.6, "kind": "hide", "r": 1.8})
	var stone := _surf(Color(0.5, 0.44, 0.36), 0.9, 0.3)
	_solid(Vector3(114.0, 1.7, 0.0), Vector3(2.0, 3.4, 2.0), stone)
	_solid(Vector3(116.0, 1.1, 0.0), Vector3(2.0, 2.2, 2.0), stone)
	_solid(Vector3(118.0, 0.5, 0.0), Vector3(2.0, 1.0, 2.0), stone)


# ====================================================================
# world: the Kasbah courtyard
# ====================================================================

func _build_kasbah() -> void:
	# fountain
	var basin := CylinderMesh.new()
	basin.top_radius = 1.2
	basin.bottom_radius = 1.3
	basin.height = 0.6
	_mi(self, basin, _surf(Color(0.5, 0.45, 0.38), 0.8, 0.4), Vector3(126.0, 0.3, -1.4))
	var water := CylinderMesh.new()
	water.top_radius = 1.05
	water.bottom_radius = 1.05
	water.height = 0.05
	var wm := _mat(Color(0.03, 0.12, 0.2), 0.05, 0.9)
	_mi(self, water, wm, Vector3(126.0, 0.58, -1.4))
	var jet := CylinderMesh.new()
	jet.top_radius = 0.12
	jet.bottom_radius = 0.2
	jet.height = 1.2
	_mi(self, jet, _surf(Color(0.5, 0.45, 0.38), 0.8, 0.4), Vector3(126.0, 1.2, -1.4))
	_omni(Vector3(126.0, 1.6, -0.4), Color(0.5, 0.7, 1.0), 0.8, 5.0)

	# palms
	for px in [120.0, 142.0, 8.0, 34.0]:
		_palm(px, -3.0, 6.0)

	# lockbox with the silver key
	var box := _mi(self, _box(Vector3(0.9, 0.6, 0.6)), _mat(Color(0.25, 0.17, 0.1), 0.7, 0.3), Vector3(132.0, 0.3, -0.9))
	box.name = "Lockbox"
	_mi(self, _box(Vector3(0.95, 0.08, 0.65)), _mat(Color(0.6, 0.55, 0.4), 0.3, 0.9), Vector3(132.0, 0.62, -0.9))
	_label3d("LOCKBOX", Vector3(132.0, 1.4, -0.6), 40, Color(1.0, 0.9, 0.6))
	_omni(Vector3(132.0, 1.2, 0.2), Color(1.0, 0.8, 0.5), 0.9, 4.5)
	interactables.append({"x": 132.0, "y": 0.0, "kind": "lockbox", "r": 2.0})

	# the great gate (arch wall + two sliding leaves)
	var root := CSGCombiner3D.new()
	root.use_collision = true
	root.position = Vector3(150.0, 0.0, 0.0)
	add_child(root)
	_csg_box(root, Vector3(1.8, 7.0, 10.0), Vector3(0, 3.5, 0), false, _surf(Color(0.58, 0.5, 0.4), 0.9, 0.3))
	_csg_box(root, Vector3(2.4, 3.0, 2.8), Vector3(0, 1.5, 0), true)
	_csg_cyl_x(root, 1.4, 2.4, Vector3(0, 3.0, 0))
	var door_mat := _mat(Color(0.1, 0.25, 0.42), 0.6, 0.1)
	gate_l = _gate_leaf(Vector3(150.0, 2.0, -0.7), door_mat)
	gate_r = _gate_leaf(Vector3(150.0, 2.0, 0.7), door_mat)
	_label3d("DAR EL KASBAH", Vector3(148.9, 5.4, 0.0), 70, Color(1.0, 0.8, 0.5))
	_omni(Vector3(147.5, 3.0, 0.0), Color(1.0, 0.7, 0.35), 1.5, 8.0)
	interactables.append({"x": 148.4, "y": 0.0, "kind": "gate", "r": 2.6})

	# Yassine, locked inside until the gate opens
	yassine = _npc(154.0, Color(0.9, 0.9, 0.85))
	yassine.scale = Vector3(0.75, 0.75, 0.75)
	yassine.visible = false


func _gate_leaf(pos: Vector3, mat: Material) -> AnimatableBody3D:
	var leaf := AnimatableBody3D.new()
	leaf.position = pos
	_mi(leaf, _box(Vector3(0.25, 4.0, 1.4)), mat, Vector3.ZERO)
	for k in 6:
		var sm := SphereMesh.new()
		sm.radius = 0.06
		sm.height = 0.12
		_mi(leaf, sm, _mat(Color(0.5, 0.45, 0.3), 0.3, 0.9), Vector3(-0.15, -1.5 + k * 0.6, 0.0))
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.25, 4.0, 1.4)
	col.shape = bs
	leaf.add_child(col)
	add_child(leaf)
	return leaf


func _palm(x: float, z: float, h: float) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.09
	trunk.bottom_radius = 0.16
	trunk.height = h
	_mi(self, trunk, _mat(Color(0.14, 0.11, 0.07), 0.95), Vector3(x, h / 2.0, z))
	var leaf_mat := _mat(Color(0.05, 0.1, 0.05), 0.9)
	for k in 8:
		var a := float(k) / 8.0 * TAU
		var leaf := _mi(self, _box(Vector3(2.2, 0.04, 0.35)), leaf_mat, Vector3(x + cos(a) * 1.0, h + 0.05, z + sin(a) * 1.0))
		leaf.rotation = Vector3(0.0, -a, deg_to_rad(-22.0))


# ====================================================================
# world: facades (whitewashed walls, blue doors, mashrabiya windows) and skyline
# ====================================================================

func _build_facades() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	var tints := [Color(0.62, 0.58, 0.5), Color(0.6, 0.45, 0.3), Color(0.45, 0.5, 0.55)]
	var lit: Array = []
	var dark: Array = []
	var bars_v: Array = []
	var bars_h: Array = []
	var doors: Array = []
	var x := -14.0
	while x < 164.0:
		var w := rng.randf_range(4.5, 7.5)
		var h := rng.randf_range(4.4, 7.2)
		var c := Vector3(x + w / 2.0, h / 2.0, -3.8)
		var tint: Color = tints[rng.randi() % 3]
		_mi(self, _box(Vector3(w, h, 3.0)), _surf(tint, 0.95, 0.3), c)
		_mi(self, _box(Vector3(w + 0.2, 0.25, 3.2)), _surf(Color(tint.r * 1.1, tint.g * 1.1, tint.b * 1.1), 0.9, 0.3), Vector3(c.x, h + 0.12, c.z))
		var cols := maxi(int(w / 2.4), 1)
		for ix in cols:
			var wx := x + (ix + 0.5) * (w / cols)
			for wy in [3.0, 5.0]:
				if wy + 0.6 > h:
					continue
				var pane := Transform3D(Basis(), Vector3(wx, wy, -2.28))
				if rng.randf() < 0.28:
					lit.append(pane)
				else:
					dark.append(pane)
				for dx in [-0.2, 0.0, 0.2]:
					bars_v.append(Transform3D(Basis(), Vector3(wx + dx, wy, -2.24)))
				for dy in [-0.25, 0.0, 0.25]:
					bars_h.append(Transform3D(Basis(), Vector3(wx, wy + dy, -2.24)))
		if rng.randf() < 0.6:
			doors.append(Transform3D(Basis(), Vector3(x + w * 0.5, 1.15, -2.28)))
		if rng.randf() < 0.14:
			var dome := SphereMesh.new()
			dome.radius = minf(1.4, w * 0.3)
			dome.height = dome.radius
			dome.is_hemisphere = true
			_mi(self, dome, _mat(Color(0.62, 0.6, 0.55), 0.7), Vector3(c.x, h + 0.25, c.z))
		x += w + rng.randf_range(0.0, 0.4)

	var lit_mat := _glow(Color(1.0, 0.7, 0.3), 3.0)
	_multimesh(lit, lit_mat, Vector3(0.6, 0.8, 0.04))
	_multimesh(dark, _mat(Color(0.03, 0.025, 0.02), 0.3), Vector3(0.6, 0.8, 0.04))
	var wood := _mat(Color(0.12, 0.07, 0.04), 0.8)
	_multimesh(bars_v, wood, Vector3(0.03, 0.8, 0.03))
	_multimesh(bars_h, wood, Vector3(0.5, 0.03, 0.03))
	_multimesh(doors, _mat(Color(0.08, 0.22, 0.4), 0.6), Vector3(1.2, 2.3, 0.08))


func _minaret(x: float, z: float) -> void:
	var wall := _mat(Color(0.5, 0.45, 0.38), 0.9)
	_mi(self, _box(Vector3(2.2, 14.0, 2.2)), wall, Vector3(x, 7.0, z))
	_mi(self, _box(Vector3(2.8, 0.35, 2.8)), wall, Vector3(x, 11.0, z))
	_mi(self, _box(Vector3(3.2, 0.4, 3.2)), wall, Vector3(x, 13.6, z))
	_mi(self, _box(Vector3(1.7, 3.2, 1.7)), wall, Vector3(x, 15.4, z))
	_mi(self, _box(Vector3(3.3, 0.06, 0.06)), _glow(Color(0.1, 1.0, 0.5), 1.5), Vector3(x, 13.85, z + 1.62))
	var dome := SphereMesh.new()
	dome.radius = 1.1
	dome.height = 1.1
	dome.is_hemisphere = true
	_mi(self, dome, _mat(Color(0.2, 0.35, 0.3), 0.4, 0.5), Vector3(x, 17.0, z))
	var fin := CylinderMesh.new()
	fin.top_radius = 0.03
	fin.bottom_radius = 0.05
	fin.height = 1.4
	_mi(self, fin, _mat(Color(0.7, 0.6, 0.3), 0.3, 0.9), Vector3(x, 18.3, z))
	var tor := TorusMesh.new()
	tor.inner_radius = 0.14
	tor.outer_radius = 0.32
	var cres := _mi(self, tor, _glow(Color(1.0, 0.85, 0.5), 1.2), Vector3(x, 19.2, z))
	cres.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_mi(self, _box(Vector3(0.3, 0.6, 0.05)), _glow(Color(1.0, 0.7, 0.3), 2.0), Vector3(x, 15.4, z + 0.88))


func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73
	var mat := _mat(Color(0.06, 0.055, 0.05), 1.0)
	var lit: Array = []
	var x := -40.0
	while x < 200.0:
		var w := rng.randf_range(5.0, 9.0)
		var h := rng.randf_range(6.0, 14.0)
		var c := Vector3(x, h / 2.0, -16.0 + rng.randf_range(-2.0, 2.0))
		_mi(self, _box(Vector3(w, h, 6.0)), mat, c)
		for ix in int(w / 1.8):
			for iy in int((h - 1.5) / 2.4):
				if rng.randf() < 0.1:
					lit.append(Transform3D(Basis(), Vector3(c.x - w / 2.0 + (ix + 0.5) * (w / int(w / 1.8)), 2.0 + iy * 2.4, c.z + 3.02)))
		x += w + rng.randf_range(0.5, 2.5)
	_multimesh(lit, _glow(Color(1.0, 0.7, 0.3), 2.0), Vector3(0.6, 0.9, 0.05))
	for mx in [30.0, 82.0, 134.0]:
		_minaret(mx, -13.0)
	for px in [-6.0, 50.0, 96.0, 154.0]:
		_palm(px, -9.0, 7.0)
	# the Chaambi mountains
	var mmat := _mat(Color(0.05, 0.05, 0.06), 1.0)
	for i in 6:
		var pm := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(70.0, 20.0 + (i % 2) * 8.0, 10.0)
		pm.mesh = prism
		pm.material_override = mmat
		pm.position = Vector3(i * 38.0 - 30.0, 3.0 + (i % 2) * 2.0, -70.0)
		add_child(pm)


func _build_decor() -> void:
	# barrels and sacks in the street
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var barrel := _mat(Color(0.2, 0.11, 0.07), 0.7, 0.2)
	for i in 16:
		var bx := rng.randf_range(-8.0, 150.0)
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.3
		cyl.bottom_radius = 0.3
		cyl.height = 0.85
		_mi(self, cyl, barrel, Vector3(bx, 0.42, rng.randf_range(-1.7, -1.2)))
	# lantern runs in the Kasbah and the first alley
	_lantern_run(-12.0, 3.0, 3.4, -1.8)
	_lantern_run(114.0, 148.0, 3.8, -1.8)


# ====================================================================
# player, enemies, coins, marks
# ====================================================================

func _spawn_player() -> void:
	player = CharacterBody3D.new()
	player.set_script(load("res://player.gd"))
	player.position = checkpoint
	add_child(player)
	player.rig.footstep.connect(_on_footstep)


func _add_dog(x: float, left_x: float, right_x: float) -> void:
	var d = CharacterBody3D.new()
	d.set_script(load("res://dog.gd"))
	d.target = player
	d.left_x = left_x
	d.right_x = right_x
	d.position = Vector3(x, 0.05, 0.0)
	d.caught.connect(_on_caught)
	d.alerted.connect(_on_alert)
	add_child(d)
	dogs.append(d)


func _add_thug(x: float, left_x: float, right_x: float, y := 0.05) -> void:
	var th = CharacterBody3D.new()
	th.set_script(load("res://thug.gd"))
	th.target = player
	th.left_x = left_x
	th.right_x = right_x
	th.position = Vector3(x, y, 0.0)
	th.caught.connect(_on_caught)
	add_child(th)
	thugs.append(th)


func _spawn_enemies() -> void:
	_add_thug(36.0, 33.0, 45.0)
	_add_thug(86.0, 82.5, 90.0, 4.7)
	_add_thug(73.0, 70.0, 77.0)
	_add_thug(131.0, 127.0, 137.0)
	_add_dog(86.0, 83.0, 90.0)
	_add_dog(141.0, 138.0, 146.0)
	_add_dog(61.0, 58.0, 64.0)


func _coin_positions() -> Array:
	var p: Array = []
	for x in [2.0, 3.4, 5.6, 8.4, 11.2, 13.6, 19.5, 24.0, 27.5, 33.5, 36.0, 40.5, 44.0]:
		p.append(Vector3(x, 0.6, 0.0))
	p.append(Vector3(48.0, 2.5, 0.0))
	p.append(Vector3(50.0, 3.6, 0.0))
	p.append(Vector3(53.0, 4.8, 0.0))
	for x in [58.0, 61.0, 64.0, 70.0, 73.0, 76.0, 83.0, 86.0, 89.0, 100.0, 103.0, 106.0, 109.0]:
		p.append(Vector3(x, 5.2, 0.0))
	p.append(Vector3(92.6, 5.9, 0.0))
	p.append(Vector3(96.4, 5.9, 0.0))
	for x in [58.0, 62.0, 72.0, 76.0, 85.0, 90.0, 100.0, 105.0, 118.0, 121.0, 127.0, 135.0, 141.0, 145.0]:
		p.append(Vector3(x, 0.6, 0.0))
	return p


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


func _build_coins() -> void:
	for p in _coin_positions():
		_make_coin(p)


func _make_coin(pos: Vector3) -> void:
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
	add_child(a)
	a.body_entered.connect(_on_coin.bind(a))
	coin_nodes.append({"area": a, "pivot": pivot})


func _on_coin(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	coins += 1
	pickups += 1
	area.queue_free()
	_sfx("coin")
	_save_inventory()
	_refresh_ui()


func _build_marks() -> void:
	for pos in [Vector3(20.5, 1.2, 0.0), Vector3(43.8, 0.7, 0.0), Vector3(72.0, 5.6, 0.0)]:
		var a := Area3D.new()
		a.position = pos
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 0.7
		cs.shape = sh
		a.add_child(cs)
		var tor := TorusMesh.new()
		tor.inner_radius = 0.12
		tor.outer_radius = 0.28
		var ring := _mi(a, tor, _glow(Color(1.0, 0.1, 0.08), 3.0), Vector3.ZERO)
		ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_mi(a, _box(Vector3(0.1, 0.1, 0.04)), _glow(Color(1.0, 0.2, 0.1), 3.0), Vector3(0.05, 0.0, 0.0))
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.15, 0.1)
		l.light_energy = 1.2
		l.omni_range = 3.0
		a.add_child(l)
		a.visible = false
		a.monitoring = false
		add_child(a)
		a.body_entered.connect(_on_mark.bind(a))
		mark_nodes.append(a)


func _reveal_marks() -> void:
	for a in mark_nodes:
		if is_instance_valid(a):
			a.visible = true
			a.set_deferred("monitoring", true)


func _on_mark(body: Node3D, area: Area3D) -> void:
	if body != player:
		return
	marks += 1
	mark_nodes.erase(area)
	area.queue_free()
	_sfx("coin")
	_banner("Jackal mark found  %d/3" % marks, 2.5)
	_check_missions()


func _build_dust() -> void:
	dust = GPUParticles3D.new()
	dust.amount = 110
	dust.lifetime = 6.0
	dust.preprocess = 6.0
	dust.local_coords = false
	dust.visibility_aabb = AABB(Vector3(-16, -4, -8), Vector3(32, 10, 16))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14.0, 3.0, 5.0)
	pm.direction = Vector3(1.0, 0.1, 0.0)
	pm.spread = 40.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0.0, 0.0, 0.0)
	pm.scale_min = 0.4
	pm.scale_max = 1.0
	var fg := Gradient.new()
	fg.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.7), Color(1, 1, 1, 0.0)])
	fg.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	var ft := GradientTexture1D.new()
	ft.gradient = fg
	pm.color_ramp = ft
	dust.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1.0, 0.85, 0.6, 0.5)
	quad.material = m
	dust.draw_pass_1 = quad
	add_child(dust)


# ====================================================================
# audio: oud-style music (Karplus-Strong plucks over a drone) + wind
# ====================================================================

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


func _make_oud() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 16
	var buf := PackedFloat32Array()
	buf.resize(n)
	# Hijaz-style phrase (D, Eb, F#, G, A, Bb)
	var notes := [
		[0.0, 146.83], [1.0, 155.56], [1.7, 185.0], [3.0, 196.0], [3.8, 185.0], [4.6, 155.56],
		[5.6, 146.83], [7.0, 220.0], [7.9, 233.08], [8.8, 196.0], [10.0, 185.0], [11.0, 155.56], [12.0, 146.83],
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
			line[idx] = (v + nxt) * 0.5 * 0.9965
			idx = (idx + 1) % length
			buf[start + i] += v * 0.35 * (1.0 - float(i) / dur)
	for i in n:
		var tt := float(i) / rate
		var drone := sin(TAU * 73.4375 * tt) * 0.12 + sin(TAU * 110.0 * tt) * 0.06
		var lfo := 0.7 + 0.3 * sin(TAU * tt / 16.0)
		var fade := clampf(minf(tt, 16.0 - tt) / 0.2, 0.0, 1.0)
		buf[i] = (buf[i] + drone * lfo) * fade
	return _to_wav(buf, rate, true)


func _make_wind() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.04
		s[i] = lp * (0.6 + 0.4 * sin(TAU * tt / 8.0)) * 1.6
	return _to_wav(s, rate, true)


func _make_coin() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.28)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var tt := float(i) / rate
		var f := 988.0 if tt < 0.07 else 1319.0
		s[i] = (sin(TAU * f * tt) * 0.4 + sin(TAU * f * 2.0 * tt) * 0.1) * exp(-tt * 9.0)
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
		s[i] = sin(TAU * float(notes[idx]) * tt) * 0.35 * exp(-(tt - idx * 0.1) * 12.0)
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


func _sfx_player(stream: AudioStream, db: float, auto := false) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	if auto:
		p.play()
	return p


func _build_audio() -> void:
	audio = Node.new()
	audio.set_script(load("res://audio.gd"))
	add_child(audio)
	# no rain in the medina: silence the rain loop (first child of the audio node)
	if audio.get_child_count() > 0:
		var rp := audio.get_child(0) as AudioStreamPlayer
		if rp != null:
			rp.volume_db = -80.0
	_sfx_player(_make_oud(), -9.0, true)
	_sfx_player(_make_wind(), -22.0, true)
	sfx["coin"] = _sfx_player(_make_coin(), -9.0)
	sfx["buy"] = _sfx_player(_make_buy(), -8.0)
	sfx["gun"] = _sfx_player(_make_gun(), -4.0)
	sfx["swish"] = _sfx_player(_make_swish(), -8.0)
	sfx["kill"] = _sfx_player(_make_kill(), -6.0)


func _sfx(key: String) -> void:
	if sfx.has(key):
		var p: AudioStreamPlayer = sfx[key]
		p.pitch_scale = randf_range(0.95, 1.05)
		p.play()


func _on_footstep(strength: float) -> void:
	if audio != null and not dead:
		audio.step(strength)


func _on_alert() -> void:
	if audio != null:
		audio.bark()


# ====================================================================
# overlay + UI
# ====================================================================

func _build_overlay() -> void:
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

	var bars := CanvasLayer.new()
	bars.layer = 6
	add_child(bars)
	var top := ColorRect.new()
	top.color = Color.BLACK
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.anchor_bottom = 0.05
	top.offset_bottom = 0.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = Color.BLACK
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.anchor_top = 0.95
	bottom.offset_top = 0.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(bottom)

	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.0, 0.0, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.modulate.a = 1.0
	layer.add_child(fade)
	msg_label = Label.new()
	msg_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	msg_label.add_theme_font_size_override("font_size", 80)
	msg_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_label.modulate.a = 0.0
	layer.add_child(msg_label)


func _intro_card() -> void:
	msg_label.text = "STAGE 2\nKASSERINE  -  THE OLD MEDINA"
	msg_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	var tw := create_tween()
	tw.tween_property(msg_label, "modulate:a", 1.0, 1.2)
	tw.tween_interval(2.0)
	tw.parallel().tween_property(fade, "modulate:a", 0.0, 2.2).set_delay(1.0)
	tw.tween_property(msg_label, "modulate:a", 0.0, 1.0)
	await tw.finished
	_banner("Mission: " + str(_mission(m_idx)[0]), 4.0)


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
	add_child(ui)
	pad2 = StagePad.new()
	pad2.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(pad2)

	coin_label = _ui_label("", 30, Vector2(24, 64))
	coin_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	weapon_label = _ui_label("", 24, Vector2(24, 104))
	mission_label = _ui_label("", 24, Vector2(24, 144))
	mission_label.size = Vector2(640, 110)
	mission_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mission_label.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))

	banner_label = Label.new()
	banner_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	banner_label.offset_top = 70.0
	banner_label.offset_bottom = 240.0
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
	shop_title.text = "THE BLACKSMITH"
	shop_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_title.add_theme_font_size_override("font_size", 56)
	box.add_child(shop_title)
	shop_coins = Label.new()
	shop_coins.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	shop_coins.add_theme_font_size_override("font_size", 32)
	shop_coins.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(shop_coins)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(580, 80)
		b.add_theme_font_size_override("font_size", 32)
		b.pressed.connect(_shop_pressed.bind(i))
		box.add_child(b)
		shop_buttons.append(b)
	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(580, 80)
	close.add_theme_font_size_override("font_size", 32)
	close.pressed.connect(_close_shop)
	box.add_child(close)


func _refresh_ui() -> void:
	if coin_label == null:
		return
	coin_label.text = "COINS  %d" % coins
	var names := ["FISTS", "SWORD", "PISTOL"]
	weapon_label.text = "WEAPON  " + names[weapon] + (("   AMMO %d" % ammo) if weapon == 2 else "")
	var m := _mission(m_idx)
	var tx := _objective_x()
	var px := hide_anchor.x if hidden else player.global_position.x
	var arrow := ""
	if tx >= 0.0:
		var d := tx - px
		arrow = "   %s %d m" % ["->" if d > 0.0 else "<-", int(absf(d))]
	mission_label.text = "MISSION %d/6\n%s%s" % [m_idx + 1, str(m[0]), arrow]


func _banner(text: String, secs := 3.5) -> void:
	if banner_label == null:
		return
	banner_label.text = text
	banner_label.modulate.a = 1.0
	banner_t = secs


func _say(lines: Array) -> void:
	for l in lines:
		dialog_q.append(str(l))


# ====================================================================
# missions
# ====================================================================

func _mission(i: int) -> Array:
	var px := 0.0
	if player != null:
		px = player.global_position.x
	match i:
		0:
			return ["Walk into the souk", px >= 10.0, 3]
		1:
			return ["Speak to Hajj Salah, the merchant", talked, 5]
		2:
			return ["Find the Jackal marks  (%d/3)" % marks, marks >= 3, 10]
		3:
			return ["Cross the covered alleys to the Kasbah", px >= 114.0, 0]
		4:
			return ["Take the silver key from the lockbox", has_key, 10]
	return ["Open the Kasbah gate and free Yassine", gate_open, 15]


func _objective_x() -> float:
	match m_idx:
		0:
			return 10.0
		1:
			return 16.0
		2:
			var best := -1.0
			var px := player.global_position.x
			var bd := 1000.0
			for a in mark_nodes:
				if is_instance_valid(a):
					var d := absf(a.position.x - px)
					if d < bd:
						bd = d
						best = a.position.x
			return best
		3:
			return 114.0
		4:
			return 132.0
	return 148.4


func _check_missions() -> void:
	var guard := 0
	while m_idx < 5 and guard < 6:
		guard += 1
		var m := _mission(m_idx)
		if not m[1]:
			break
		var reward: int = REWARDS[m_idx]
		coins += reward
		var text := "MISSION COMPLETE\n%s" % str(m[0])
		if reward > 0:
			text += "\n+%d coins" % reward
		_banner(text, 4.5)
		m_idx += 1
		_sfx("buy")
		if m_idx == 2:
			_reveal_marks()
	_save_inventory()
	_refresh_ui()


# ====================================================================
# interaction
# ====================================================================

func _nearest_interactable():
	var pp: Vector3 = player.global_position
	var best = null
	var bd := 1000.0
	for it in interactables:
		var d := absf(float(it["x"]) - pp.x)
		if d < float(it["r"]) and absf(float(it["y"]) - pp.y) < 2.0 and d < bd:
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
		"npc":
			_talk_merchant()
		"shop":
			_open_shop()
		"hide":
			_toggle_hide(float(it["x"]))
		"lockbox":
			_take_key()
		"gate":
			_open_gate()


func _talk_merchant() -> void:
	if not talked:
		talked = true
		has_lantern = true
		_give_lantern()
		_say([
			"HAJJ SALAH:  Ya weldi... the Jackals took my grandson Yassine to the Kasbah.",
			"HAJJ SALAH:  Take my lantern. It shows their red marks on the walls. Follow them.",
			"HAJJ SALAH:  Bring back the silver key they stole, and my boy. Allah m'ak.",
		])
		_check_missions()
	else:
		_say(["HAJJ SALAH:  Follow the marks. The covered alleys lead to the Kasbah. Stay quiet."])


func _give_lantern() -> void:
	if held_lamp != null:
		return
	held_lamp = OmniLight3D.new()
	held_lamp.position = Vector3(0.3, 1.3, 0.5)
	held_lamp.light_color = Color(1.0, 0.7, 0.35)
	held_lamp.light_energy = 1.4
	held_lamp.omni_range = 6.5
	held_lamp.light_volumetric_fog_energy = 2.0
	player.add_child(held_lamp)
	_reveal_marks_if_ready()


func _reveal_marks_if_ready() -> void:
	if m_idx >= 2 or talked:
		_reveal_marks()


func _toggle_hide(spot_x: float) -> void:
	var rig = player.get("rig")
	if not hidden:
		hidden = true
		hide_anchor = player.global_position
		player.set_physics_process(false)
		player.global_position = Vector3(spot_x, -6.0, 0.0)
		if rig != null:
			rig.visible = false
		for d in dogs:
			d.set("chasing", false)
			d.set("ignore_timer", 5.0)
		for th in thugs:
			th.set("chasing", false)
			th.set("ignore_timer", 5.0)
		_banner("HIDDEN\nWait for the guards to leave, then press USE", 3.5)
	else:
		hidden = false
		player.global_position = hide_anchor
		player.velocity = Vector3.ZERO
		player.set_physics_process(true)
		if rig != null:
			rig.visible = true


func _take_key() -> void:
	if has_key:
		_banner("The lockbox is empty.", 2.0)
		return
	has_key = true
	_sfx("buy")
	_banner("You took the SILVER KEY.\nThe lock was loud: the guards heard it!", 4.0)
	for d in dogs:
		if absf(d.global_position.x - player.global_position.x) < 14.0:
			d.set("chasing", true)
	for th in thugs:
		if absf(th.global_position.x - player.global_position.x) < 14.0:
			th.set("chasing", true)
	_check_missions()


func _open_gate() -> void:
	if gate_open:
		return
	if not has_key:
		_banner("Locked.\nThe silver key is in the lockbox.", 3.0)
		return
	gate_open = true
	_sfx("buy")
	var tw := create_tween()
	tw.tween_property(gate_l, "position:z", -2.4, 2.5)
	tw.parallel().tween_property(gate_r, "position:z", 2.4, 2.5)
	yassine.visible = true
	yassine.position = Vector3(153.5, 0.0, -0.6)
	await tw.finished
	_say([
		"YASSINE:  Jeddi sent you? Yaatik essaha!",
		"YASSINE:  Let's go home before the Jackals come back.",
	])
	_check_missions()
	_complete_stage()


func _complete_stage() -> void:
	if finished:
		return
	finished = true
	await get_tree().create_timer(7.0).timeout
	msg_label.text = "STAGE 2 COMPLETE\nTO BE CONTINUED"
	msg_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, 1.2)
	tw.parallel().tween_property(msg_label, "modulate:a", 1.0, 1.6)
	await tw.finished
	await get_tree().create_timer(3.0).timeout
	get_tree().change_scene_to_file("res://menu.tscn")


# ====================================================================
# shop
# ====================================================================

func _open_shop() -> void:
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
	var b2: Button = shop_buttons[2]
	b0.text = "SWORD  -  OWNED" if has_sword else "SWORD  -  12 coins"
	b0.disabled = has_sword
	b1.text = "PISTOL  -  OWNED" if has_gun else "PISTOL  -  25 coins"
	b1.disabled = has_gun
	b2.text = "AMMO x6  -  4 coins"
	b2.visible = has_gun
	b2.disabled = false


func _shop_pressed(i: int) -> void:
	if i == 0 and not has_sword and coins >= 12:
		coins -= 12
		has_sword = true
		weapon = 1
		_sfx("buy")
		_banner("Sword bought! Tap ATK to swing.", 3.0)
	elif i == 1 and not has_gun and coins >= 25:
		coins -= 25
		has_gun = true
		ammo += 6
		weapon = 2
		_sfx("buy")
		_banner("Pistol bought with 6 bullets. Noise attracts guards!", 3.5)
	elif i == 2 and has_gun and coins >= 4:
		coins -= 4
		ammo += 6
		_sfx("buy")
	else:
		_banner("Not enough coins", 1.5)
	_save_inventory()
	_shop_refresh()
	_refresh_ui()


# ====================================================================
# weapons and combat
# ====================================================================

func _attach_weapons() -> void:
	var rig = player.get("rig")
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
	_save_inventory()
	_refresh_ui()


func _attack() -> void:
	if cooldown > 0.0 or hidden or shop_open:
		return
	if weapon == 2 and has_gun:
		if ammo <= 0:
			_banner("Out of ammo. Buy more from the blacksmith.", 2.5)
			return
		ammo -= 1
		_shoot()
	elif weapon == 1 and has_sword:
		_sfx("swish")
		_melee()
	else:
		_banner("No weapon equipped. The blacksmith sells a sword.", 2.5)
		return
	cooldown = 0.5
	attack_t = 0.35
	_save_inventory()
	_refresh_ui()


func _melee() -> void:
	var face: float = player.get("facing")
	var pp: Vector3 = player.global_position
	for th in thugs.duplicate():
		var tp: Vector3 = th.global_position
		var dx := tp.x - pp.x
		if signf(dx) == face and absf(dx) < 1.8 and absf(tp.y - pp.y) < 1.3:
			var behind := signf(pp.x - tp.x) != float(th.get("facing"))
			if behind:
				th.hp = 0
			else:
				th.hp -= 1
				th.chasing = true
			if th.hp <= 0:
				_kill_thug(th)
			return
	for d in dogs.duplicate():
		var dp: Vector3 = d.global_position
		var dx2 := dp.x - pp.x
		if signf(dx2) == face and absf(dx2) < 1.7 and absf(dp.y - pp.y) < 1.2:
			_kill_dog(d)
			return


func _shoot() -> void:
	var face: float = player.get("facing")
	var pp: Vector3 = player.global_position
	_sfx("gun")
	shake = 0.35
	var muzzle := Vector3(pp.x + face * 0.7, pp.y + 1.05, 0.0)
	var fl := _omni(muzzle, Color(1.0, 0.7, 0.3), 3.0, 5.0)
	get_tree().create_timer(0.08).timeout.connect(fl.queue_free)
	var target = null
	var best := 14.0
	for e in thugs + dogs:
		var ep: Vector3 = e.global_position
		var dx := ep.x - pp.x
		if signf(dx) == face and absf(dx) < best and absf(ep.y + 0.6 - (pp.y + 1.0)) < 1.5:
			best = absf(dx)
			target = e
	var end := Vector3(pp.x + face * 14.0, muzzle.y, 0.0)
	if target != null:
		end = Vector3(target.global_position.x, muzzle.y, 0.0)
	_tracer(muzzle, end)
	if target != null:
		if thugs.has(target):
			_kill_thug(target)
		else:
			_kill_dog(target)
	for e in thugs + dogs:
		if absf(e.global_position.x - pp.x) < 14.0:
			e.set("chasing", true)


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
	add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)


func _kill_thug(th: Node) -> void:
	kills += 1
	var pos: Vector3 = th.global_position
	thugs.erase(th)
	var rig = th.get("rig")
	var push := signf(pos.x - player.global_position.x)
	if rig != null:
		rig.spawn_ragdoll(self, Vector3.ZERO, push)
		rig.visible = false
	th.queue_free()
	_sfx("kill")
	for i in 3:
		_make_coin(pos + Vector3(i * 0.4 - 0.4, 0.8, 0.0))
	_banner("Jackal down! +3 coins to grab", 2.0)


func _kill_dog(d: Node) -> void:
	kills += 1
	var pos: Vector3 = d.global_position
	dogs.erase(d)
	var vis = d.get("visual")
	if vis != null:
		vis.reparent(self)
		vis.global_position.y = pos.y + 0.18
		vis.rotate_object_local(Vector3.RIGHT, deg_to_rad(88.0))
		_dim_eyes(vis)
	d.queue_free()
	_sfx("kill")
	for i in 4:
		_make_coin(pos + Vector3(i * 0.4 - 0.6, 0.8, 0.0))
	_banner("Dog down! +4 coins to grab", 2.0)


func _dim_eyes(node: Node) -> void:
	if node is MeshInstance3D:
		var m := node.material_override as StandardMaterial3D
		if m != null and m.emission_enabled:
			var m2 := m.duplicate() as StandardMaterial3D
			m2.emission_enabled = false
			node.material_override = m2
	for c in node.get_children():
		_dim_eyes(c)


# ====================================================================
# death, checkpoints, camera, per frame
# ====================================================================

func _on_caught(use_ragdoll := true) -> void:
	if dead or finished:
		return
	dead = true
	deaths += 1
	if use_ragdoll:
		var push := 1.0
		var best := 1000000.0
		for e in thugs + dogs:
			var dist := absf(e.global_position.x - player.global_position.x)
			if dist < best:
				best = dist
				push = signf(player.global_position.x - e.global_position.x)
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

	if hidden:
		hidden = false
	player.respawn(checkpoint)
	for d in dogs:
		d.reset_state()
	for th in thugs:
		th.reset_state()
		# after three deaths in a row the guards get a bit blind
		if deaths >= 3:
			th.assist = 0.75
	if deaths == 3:
		call_deferred("_help_tip")
	player.set_physics_process(true)
	dead = false
	var tw2 := create_tween()
	tw2.tween_property(fade, "modulate:a", 0.0, 0.6)
	tw2.parallel().tween_property(msg_label, "modulate:a", 0.0, 0.4)


func _help_tip() -> void:
	_banner("TIP: crouch (B) to shrink the guards' sight, hide in rugs with USE,\nor climb: they cannot follow you up.", 6.0)


func _params(x: float) -> Dictionary:
	if x <= KEYS[0]["x"]:
		return KEYS[0]
	for i in range(KEYS.size() - 1):
		var a: Dictionary = KEYS[i]
		var b: Dictionary = KEYS[i + 1]
		if x <= b["x"]:
			var u := clampf((x - a["x"]) / (b["x"] - a["x"]), 0.0, 1.0)
			u = u * u * (3.0 - 2.0 * u)
			return {
				"yaw": lerpf(a["yaw"], b["yaw"], u),
				"h": lerpf(a["h"], b["h"], u),
				"dist": lerpf(a["dist"], b["dist"], u),
				"fov": lerpf(a["fov"], b["fov"], u),
			}
	return KEYS[KEYS.size() - 1]


func _camera(delta: float) -> void:
	var p: Vector3 = hide_anchor if hidden else player.global_position
	var face: float = player.get("facing")
	var crouch: bool = player.get("crouching")
	var desired := Vector3(p.x + face * 2.0, p.y + 1.1 - (0.3 if crouch else 0.0), 0.0)
	if not focus_ready:
		focus = desired
		focus_ready = true
	focus.x = lerpf(focus.x, desired.x, 1.0 - exp(-3.0 * delta))
	focus.y = lerpf(focus.y, desired.y, 1.0 - exp(-2.2 * delta))
	var pr := _params(focus.x)
	var lag := clampf((desired.x - focus.x) * 0.012, -0.05, 0.05)
	var yaw := deg_to_rad(float(pr["yaw"])) + lag + sin(t * 0.3) * 0.012
	var dist := float(pr["dist"]) - (0.5 if crouch else 0.0)
	var h := float(pr["h"]) - (0.3 if crouch else 0.0)
	var drift := Vector3(sin(t * 0.5) * 0.04, sin(t * 0.7) * 0.03, 0.0)
	cam.global_position = focus + Vector3(sin(yaw) * dist, h, cos(yaw) * dist) + drift
	cam.look_at(focus, Vector3.UP)
	cam.rotation.z = -lag * 0.3 + sin(t * 47.0) * shake * 0.004
	cam.fov = lerpf(cam.fov, float(pr["fov"]), 1.0 - exp(-1.5 * delta))
	cam.h_offset = sin(t * 43.0) * shake * 0.12
	cam.v_offset = cos(t * 37.0) * shake * 0.1


func _physics_process(delta: float) -> void:
	if mover != null:
		mover_t += delta
		mover.position.x = 94.5 + 2.2 * sin(mover_t * 0.9)
	if player != null and not dead and not finished:
		for cp in checkpoints:
			if player.position.x >= cp.x and cp.x > checkpoint.x and absf(player.position.y - cp.y) < 2.0:
				checkpoint = cp
		if player.position.y < -8.0 and not hidden:
			_on_caught(false)


func _input(event: InputEvent) -> void:
	if shop_open or pad2 == null or get_tree().paused:
		return
	if event is InputEventScreenTouch and event.pressed:
		for b in pad2.layout():
			if (b["pos"] as Vector2).distance_to(event.position) < float(b["r"]) * 1.2:
				var id: String = b["id"]
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
				return


func _process(delta: float) -> void:
	t += delta
	cooldown = maxf(0.0, cooldown - delta)
	attack_t = maxf(0.0, attack_t - delta)
	shake = maxf(0.0, shake - delta * 1.5)
	if player == null or cam == null:
		return
	_camera(delta)

	# lantern flicker
	for i in lamp_lights.size():
		var l: OmniLight3D = lamp_lights[i]
		var base: float = lamp_base[i]
		var f := 0.9 + 0.1 * sin(t * 7.0 + i * 1.7) * sin(t * 3.1 + i)
		l.light_energy = base * f
		(lamp_halos[i] as StandardMaterial3D).albedo_color.a = 0.5 * f
	if held_lamp != null:
		held_lamp.light_energy = 1.3 + 0.2 * sin(t * 9.0) * sin(t * 4.3)

	# dust follows the camera
	if dust != null:
		dust.global_position = Vector3(cam.global_position.x, 3.0, 0.0)

	# coins spin
	for c in coin_nodes:
		var pv = c["pivot"]
		if is_instance_valid(pv):
			pv.rotation.y += delta * 3.0

	# NPCs look at the player
	for npc in [merchant, yassine]:
		if npc != null and npc.visible:
			var rig = npc.get_meta("rig")
			var dxn: float = player.global_position.x - npc.global_position.x
			rig.animate(delta, 0.0, 0.0, true, false, false, signf(dxn) if absf(dxn) > 0.1 else 1.0, 0.0)

	# banner and dialogue
	banner_t -= delta
	if banner_label != null:
		banner_label.modulate.a = clampf(banner_t / 0.6, 0.0, 1.0)
	if banner_t <= 0.2 and not dialog_q.is_empty():
		_banner(str(dialog_q.pop_front()), 4.2)

	# tips
	if not hidden:
		var px: float = player.global_position.x
		var tips := [
			[1.0, "Move with < >. Jump with A. Collect the coins."],
			[31.0, "Guards see only inside their lantern light. Crouch (B) to stay unseen."],
			[40.0, "Hold X (PUSH) beside the cart to push it against the ledge."],
			[56.0, "Roofs are safe from guards but not from the gaps. Jump!"],
			[112.0, "The Kasbah. Find the lockbox, then the great gate."],
		]
		for i in tips.size():
			if not tips_shown.has(i) and px > float(tips[i][0]):
				tips_shown[i] = true
				_banner(str(tips[i][1]), 4.0)
				break

	# USE button context + attack animation + HUD refresh
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
					"shop":
						txt = "SHOP"
					"hide":
						txt = "HIDE"
					"lockbox":
						txt = "OPEN"
					"gate":
						txt = "GATE"
		if txt != pad2.use_text or ready != pad2.use_ready:
			pad2.use_text = txt
			pad2.use_ready = ready
			pad2.queue_redraw()
	_update_weapon_visuals()


func _update_weapon_visuals() -> void:
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
		var p := 1.0 - attack_t / 0.35
		var arm: Node3D = rig.get("arm_u")[near]
		var fore: Node3D = rig.get("arm_l")[near]
		if weapon == 1:
			arm.rotation.x = lerpf(-2.9, -0.4, p * p)
			fore.rotation.x = -0.3
		else:
			arm.rotation.x = -1.55 - 0.15 * (1.0 - p)
			fore.rotation.x = -0.1
EOF

# ------------------------------------------------------------------
# Autoload registration
# ------------------------------------------------------------------
add_autoload() {
	name="$1"
	path="$2"
	if ! grep -q "^$name=" project.godot; then
		if grep -q "^\[autoload\]" project.godot; then
			sed -i "/^\[autoload\]/a $name=\"*res://$path\"" project.godot
		else
			printf '\n[autoload]\n\n%s="*res://%s"\n' "$name" "$path" >> project.godot
		fi
	fi
}
add_autoload Medina medina.gd

git add -A
git commit -m "Step 15: Stage 2 - Kasserine medina"
git push
echo "OK: pushed, build is starting. Backup: ~/long-night-backup-step15"

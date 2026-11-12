extends CharacterBody3D
# Police officer: patrols with a flashlight and SHOOTS when he sees you.
# Each shot that lands costs one hit point. Crouching, jumping and hiding make him miss.

signal caught

const GRAVITY := 18.0
const PATROL_SPEED := 1.1
const ADVANCE_SPEED := 1.5

static var shot_stream: AudioStreamWAV = null

var target
var left_x := 0.0
var right_x := 0.0
var start_x := 0.0
var start_y := 0.05
var facing := 1.0
var wait_timer := 0.0
var alert_t := 0.0
var fire_t := 1.0
var rig: Node3D
var spot: SpotLight3D
var snd: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("police")
	collision_layer = 2
	collision_mask = 1
	start_x = position.x
	start_y = position.y
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
	var head = rig.get("head")
	if head != null:
		var cap := CylinderMesh.new()
		cap.top_radius = 0.1
		cap.bottom_radius = 0.108
		cap.height = 0.07
		_add_mesh(head, cap, Color(0.05, 0.08, 0.2), Vector3(0, 0.2, 0))
		_add_mesh(head, BoxMesh.new(), Color(0.03, 0.04, 0.1), Vector3(0, 0.17, 0.1), Vector3(0.18, 0.012, 0.08))

	spot = SpotLight3D.new()
	spot.position = Vector3(0.0, 1.3, 0.3)
	spot.rotation_degrees = Vector3(-10.0, 180.0, 0.0)
	spot.spot_angle = 28.0
	spot.spot_range = 12.0
	spot.light_energy = 7.0
	spot.light_color = Color(0.85, 0.92, 1.0)
	spot.light_volumetric_fog_energy = 3.0
	rig.add_child(spot)

	if shot_stream == null:
		shot_stream = _make_shot()
	snd = AudioStreamPlayer3D.new()
	snd.stream = shot_stream
	snd.unit_size = 6.0
	snd.max_distance = 45.0
	snd.volume_db = -2.0
	add_child(snd)


func _add_mesh(parent: Node3D, mesh: Mesh, color: Color, pos: Vector3, scale_v := Vector3.ONE) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	mi.material_override = m
	mi.position = pos
	if mesh is BoxMesh:
		(mesh as BoxMesh).size = Vector3(1, 1, 1)
		mi.scale = scale_v
	parent.add_child(mi)


func _recolor(node: Node) -> void:
	if node is MeshInstance3D:
		var m := node.material_override as StandardMaterial3D
		if m != null:
			var c := m.albedo_color
			if c.is_equal_approx(Color(0.62, 0.09, 0.07)):
				m.albedo_color = Color(0.07, 0.11, 0.24)
			elif c.is_equal_approx(Color(0.1, 0.1, 0.13)):
				m.albedo_color = Color(0.05, 0.07, 0.14)
	for ch in node.get_children():
		_recolor(ch)


static func _make_shot() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.35)
	var samples := PackedByteArray()
	samples.resize(n * 2)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.5
		var v := (lp * 1.2 * exp(-tt * 16.0) + sin(TAU * 70.0 * tt) * exp(-tt * 20.0) * 0.8) * 0.9
		samples.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = samples
	return w


func reset_state() -> void:
	position = Vector3(start_x, start_y + 0.1, 0.0)
	velocity = Vector3.ZERO
	alert_t = 0.0
	fire_t = 1.5
	wait_timer = 0.0


func _fire() -> void:
	var from := global_position + Vector3(facing * 0.5, 1.15, 0.0)
	var to: Vector3 = target.global_position + Vector3(0.0, 0.9, 0.0)
	var chance := 0.6
	if target.crouching:
		chance = 0.35
	if not target.is_on_floor():
		chance = 0.3
	var hit := randf() < chance
	if not hit:
		to += Vector3(0.0, randf_range(-0.9, 0.9) + 0.6, 0.0)
	snd.play()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.9, 0.5)
	mi.material_override = m
	get_parent().add_child(mi)
	get_tree().create_timer(0.06).timeout.connect(mi.queue_free)
	var fl := OmniLight3D.new()
	fl.position = from
	fl.light_color = Color(1.0, 0.7, 0.3)
	fl.light_energy = 3.0
	fl.omni_range = 5.0
	get_parent().add_child(fl)
	get_tree().create_timer(0.08).timeout.connect(fl.queue_free)
	if hit:
		caught.emit()


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var dx: float = target.global_position.x - global_position.x
	var dy: float = target.global_position.y - global_position.y
	var crouched: bool = target.crouching
	var sight := 10.0 if not crouched else 5.0
	var hear := 2.0 if not crouched else 1.0
	var sees := absf(dy) < 2.5 and ((signf(dx) == facing and absf(dx) < sight) or absf(dx) < hear)
	if sees:
		alert_t = 3.0
	elif absf(dy) > 3.0:
		alert_t = 0.0
	else:
		alert_t = maxf(0.0, alert_t - delta)

	var move := 0.0
	var speed := PATROL_SPEED
	if alert_t > 0.0:
		if absf(dx) > 0.05:
			facing = signf(dx)
		fire_t -= delta
		if fire_t <= 0.0 and absf(dx) < 12.0:
			fire_t = 1.6
			_fire()
		if absf(dx) > 7.0:
			move = facing
			speed = ADVANCE_SPEED
	else:
		fire_t = maxf(fire_t, 0.6)
		if wait_timer > 0.0:
			wait_timer -= delta
		else:
			move = facing
			if (facing > 0.0 and position.x >= right_x) or (facing < 0.0 and position.x <= left_x):
				facing = -facing
				wait_timer = 1.8
				move = 0.0

	velocity.x = move * speed
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	position.z = 0.0

	# close contact: a grab counts as a hit
	if absf(dx) < 0.8 and dy < 0.9 and dy > -1.5:
		caught.emit()

	rig.animate(delta, velocity.x, velocity.y, is_on_floor(), false, false, facing, move)

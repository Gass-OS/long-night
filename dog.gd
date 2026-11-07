extends CharacterBody3D

signal caught
signal alerted

const PATROL_SPEED := 1.4
const CHASE_SPEED := 4.3
const GRAVITY := 18.0
const UP_LEN := [0.27, 0.27, 0.28, 0.28]
const LOW_LEN := [0.27, 0.27, 0.27, 0.27]

const FUR := Color(0.07, 0.065, 0.06)
const FUR2 := Color(0.11, 0.1, 0.09)

var target
var left_x := 0.0
var right_x := 0.0
var start_x := 0.0
var facing := 1.0
var chasing := false
var biting := false
var ignore_timer := 0.0
var wait_timer := 0.0
var above_timer := 0.0

var visual: Node3D
var body: Node3D
var neck: Node3D
var head: Node3D
var jaw: Node3D
var tail: Node3D
var up_legs: Array = []
var low_legs: Array = []
var phase := 0.0
var gallop := 0.0
var gait_amp := 0.0
var yaw := 0.0
var t_anim := 0.0


func _ready() -> void:
	# Dogs live on layer 2: they never block the player, but they bite on contact
	collision_layer = 2
	collision_mask = 1
	start_x = position.x
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.9, 0.65, 0.35)
	col.shape = sh
	col.position.y = 0.325
	add_child(col)
	_build_body()


func _mat(color: Color, glow := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 6.0
	return m


func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3, glow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color, glow)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _capsule(parent: Node3D, radius: float, length: float, color: Color, pos: Vector3, along_x := false) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(length, radius * 2.0 + 0.001)
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = pos
	if along_x:
		mi.rotation.z = PI / 2.0
	parent.add_child(mi)


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func _build_body() -> void:
	visual = Node3D.new()
	add_child(visual)
	body = _pivot(visual, Vector3(0, 0.62, 0))

	# Torso: chest, waist, rump
	_capsule(body, 0.15, 0.5, FUR, Vector3(0.18, 0.0, 0.0), true)
	_capsule(body, 0.12, 0.3, FUR2, Vector3(0.0, 0.0, 0.0), true)
	_capsule(body, 0.13, 0.45, FUR, Vector3(-0.24, -0.01, 0.0), true)

	# Neck and head
	neck = _pivot(body, Vector3(0.38, 0.1, 0.0))
	_capsule(neck, 0.075, 0.28, FUR, Vector3(0, 0.12, 0))
	head = _pivot(neck, Vector3(0, 0.26, 0))
	_box(head, Vector3(0.2, 0.16, 0.15), FUR, Vector3(0.05, 0.03, 0))
	_box(head, Vector3(0.17, 0.08, 0.09), FUR, Vector3(0.2, -0.01, 0))
	_box(head, Vector3(0.04, 0.04, 0.06), Color(0.01, 0.01, 0.01), Vector3(0.29, 0.0, 0))
	_box(head, Vector3(0.05, 0.12, 0.04), FUR2, Vector3(-0.02, 0.13, 0.06))
	_box(head, Vector3(0.05, 0.12, 0.04), FUR2, Vector3(-0.02, 0.13, -0.06))
	_box(head, Vector3(0.035, 0.035, 0.035), Color(1.0, 0.1, 0.05), Vector3(0.14, 0.06, 0.05), true)
	_box(head, Vector3(0.035, 0.035, 0.035), Color(1.0, 0.1, 0.05), Vector3(0.14, 0.06, -0.05), true)
	jaw = _pivot(head, Vector3(0.12, -0.04, 0.0))
	_box(jaw, Vector3(0.16, 0.035, 0.07), FUR, Vector3(0.08, 0.0, 0.0))
	_box(jaw, Vector3(0.1, 0.012, 0.05), Color(0.8, 0.8, 0.75), Vector3(0.09, 0.022, 0.0))

	# Tail
	tail = _pivot(body, Vector3(-0.46, 0.06, 0.0))
	_capsule(tail, 0.025, 0.38, FUR, Vector3(0, -0.19, 0))

	# Legs: FL, FR, HL, HR
	var xs := [0.3, 0.3, -0.3, -0.3]
	var zs := [0.1, -0.1, 0.1, -0.1]
	for i in 4:
		var up := _pivot(body, Vector3(xs[i], -0.05, zs[i]))
		_capsule(up, 0.055 if i < 2 else 0.065, UP_LEN[i], FUR, Vector3(0, -UP_LEN[i] * 0.5, 0))
		var low := _pivot(up, Vector3(0, -UP_LEN[i], 0))
		_capsule(low, 0.04, LOW_LEN[i], FUR, Vector3(0, -LOW_LEN[i] * 0.5, 0))
		_box(low, Vector3(0.09, 0.04, 0.06), FUR, Vector3(0.03, -LOW_LEN[i] - 0.01, 0))
		up_legs.append(up)
		low_legs.append(low)


func reset_state() -> void:
	position = Vector3(start_x, 0.05, 0.0)
	velocity = Vector3.ZERO
	chasing = false
	biting = false
	ignore_timer = 1.0
	wait_timer = 0.0
	above_timer = 0.0


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var dx: float = target.global_position.x - global_position.x
	var dy: float = target.global_position.y - global_position.y
	var crouched: bool = target.crouching
	ignore_timer = maxf(0.0, ignore_timer - delta)

	# Senses: sight in front, hearing all around. Crouching halves both.
	var sight := 4.0 if crouched else 8.0
	var hear := 1.0 if crouched else 2.2
	var sees := absf(dy) < 2.0 and ((signf(dx) == facing and absf(dx) < sight) or absf(dx) < hear)
	if ignore_timer <= 0.0 and sees:
		if not chasing:
			alerted.emit()
		chasing = true
	if chasing and absf(dx) > 14.0:
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
				wait_timer = 1.2
				move = 0.0

	velocity.x = move * speed
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	move_and_slide()
	position.z = 0.0

	if absf(dx) < 0.8 and dy < 0.75 and dy > -1.0:
		biting = true
		caught.emit()

	_animate(delta)


func _animate(delta: float) -> void:
	t_anim += delta
	yaw = lerp_angle(yaw, 0.0 if facing > 0.0 else PI, clampf(delta * 10.0, 0.0, 1.0))
	visual.rotation.y = yaw

	var moving := absf(velocity.x) > 0.1
	gallop = lerpf(gallop, 1.0 if chasing else 0.0, clampf(delta * 6.0, 0.0, 1.0))
	var amp_target := 0.0
	if moving:
		amp_target = lerpf(0.4, 0.85, gallop)
		phase += delta * lerpf(5.5, 17.0, gallop)
	gait_amp = lerpf(gait_amp, amp_target, clampf(delta * 8.0, 0.0, 1.0))
	var flex := lerpf(0.9, 1.5, gallop) * (gait_amp / 0.85)

	var trot := [0.0, PI, PI, 0.0]
	var gal := [0.0, 0.3, 2.5, 2.8]
	var front_h := 0.0
	var hind_h := 0.0
	for i in 4:
		var ph: float = phase + lerpf(trot[i], gal[i], gallop)
		var a := gait_amp * sin(ph)
		var low := -flex * maxf(0.0, cos(ph))
		up_legs[i].rotation.z = a
		low_legs[i].rotation.z = low
		var h: float = 0.05 + UP_LEN[i] * cos(a) + LOW_LEN[i] * cos(a + low) + 0.03
		if i < 2:
			front_h = maxf(front_h, h)
		else:
			hind_h = maxf(hind_h, h)

	body.position.y = (front_h + hind_h) * 0.5 + 0.004 * sin(t_anim * 2.6)
	body.rotation.z = (front_h - hind_h) / 0.6 + 0.07 * sin(phase + 0.6) * gallop * (gait_amp / 0.85)

	var k := clampf(delta * 6.0, 0.0, 1.0)
	var neck_t := lerpf(-0.55 + 0.08 * sin(t_anim * 0.9), -1.05, gallop)
	if biting:
		neck_t = -1.2
	var head_t := -neck_t + lerpf(-0.25, 0.08, gallop)
	neck.rotation.z = lerpf(neck.rotation.z, neck_t, k)
	head.rotation.z = lerpf(head.rotation.z, head_t, k)
	var jaw_t := -0.5 * gallop - 0.04 * sin(phase * 2.0) * gallop
	if biting:
		jaw_t = -0.95
	jaw.rotation.z = lerpf(jaw.rotation.z, jaw_t, clampf(delta * 12.0, 0.0, 1.0))
	tail.rotation.z = lerpf(tail.rotation.z, lerpf(-1.3, -0.5, gallop), k)
	tail.rotation.y = 0.45 * sin(t_anim * lerpf(5.0, 12.0, gallop)) * (1.0 - 0.6 * gallop)

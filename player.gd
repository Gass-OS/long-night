extends CharacterBody3D

const SPEED := 4.0
const JUMP := 7.0
const GRAVITY := 18.0

const SKIN := Color(0.86, 0.7, 0.6)
const SHIRT := Color(0.75, 0.12, 0.1)
const PANTS := Color(0.12, 0.12, 0.16)

var touch_left := false
var touch_right := false
var touch_jump := false

var visual: Node3D
var arm_l: Node3D
var arm_r: Node3D
var leg_l: Node3D
var leg_r: Node3D
var phase := 0.0


func _ready() -> void:
	var col := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = 1.5
	col.shape = shape
	col.position.y = 0.75
	add_child(col)
	_build_body()


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	return m


func _box(parent: Node3D, size: Vector3, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _limb(pos: Vector3, size: Vector3, color: Color) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	visual.add_child(pivot)
	_box(pivot, size, color, Vector3(0, -size.y / 2.0, 0))
	return pivot


func _build_body() -> void:
	visual = Node3D.new()
	visual.rotation.y = deg_to_rad(90.0)  # facing right
	add_child(visual)

	# Torso (red shirt)
	_box(visual, Vector3(0.4, 0.5, 0.22), SHIRT, Vector3(0, 0.9, 0))

	# Head
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	head.mesh = sm
	head.material_override = _mat(SKIN)
	head.position = Vector3(0, 1.32, 0)
	visual.add_child(head)

	# Arms (pivot at shoulders) with hands
	arm_l = _limb(Vector3(-0.27, 1.12, 0), Vector3(0.12, 0.5, 0.12), SHIRT)
	arm_r = _limb(Vector3(0.27, 1.12, 0), Vector3(0.12, 0.5, 0.12), SHIRT)
	_box(arm_l, Vector3(0.13, 0.13, 0.13), SKIN, Vector3(0, -0.52, 0))
	_box(arm_r, Vector3(0.13, 0.13, 0.13), SKIN, Vector3(0, -0.52, 0))

	# Legs (pivot at hips)
	leg_l = _limb(Vector3(-0.1, 0.65, 0), Vector3(0.17, 0.65, 0.17), PANTS)
	leg_r = _limb(Vector3(0.1, 0.65, 0), Vector3(0.17, 0.65, 0.17), PANTS)


func _physics_process(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or touch_left:
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D) or touch_right:
		dir += 1.0

	var want_jump := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or touch_jump

	velocity.x = dir * SPEED
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif want_jump:
		velocity.y = JUMP

	move_and_slide()
	_push_bodies(dir * SPEED)
	position.z = 0.0
	_animate(delta, dir)


func _animate(delta: float, dir: float) -> void:
	if dir != 0.0:
		var target_yaw := deg_to_rad(90.0 * signf(dir))
		visual.rotation.y = lerp_angle(visual.rotation.y, target_yaw, clampf(delta * 12.0, 0.0, 1.0))

	var ll := 0.0
	var lr := 0.0
	var al := 0.0
	var ar := 0.0
	if not is_on_floor():
		ll = -0.7
		lr = 0.5
		al = -2.4
		ar = -2.4
	elif absf(velocity.x) > 0.1:
		phase += delta * 10.0
		var s := sin(phase)
		ll = s * 0.8
		lr = -s * 0.8
		al = -s * 0.7
		ar = s * 0.7
	else:
		phase = 0.0

	var t := clampf(delta * 18.0, 0.0, 1.0)
	leg_l.rotation.x = lerpf(leg_l.rotation.x, ll, t)
	leg_r.rotation.x = lerpf(leg_r.rotation.x, lr, t)
	arm_l.rotation.x = lerpf(arm_l.rotation.x, al, t)
	arm_r.rotation.x = lerpf(arm_r.rotation.x, ar, t)


func _push_bodies(move_x: float) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var b := c.get_collider() as RigidBody3D
		if b != null and absf(c.get_normal().x) > 0.5:
			b.sleeping = false
			b.linear_velocity.x = move_x * 0.6

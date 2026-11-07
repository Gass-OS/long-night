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

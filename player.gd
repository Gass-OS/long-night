extends CharacterBody3D

const SPEED := 4.0
const CROUCH_SPEED := 1.6
const GRAB_SPEED := 1.8
const JUMP := 7.0
const GRAVITY := 18.0
const STAND_H := 1.5
const CROUCH_H := 0.9
const GRAB_REACH := 1.05

var touch_left := false
var touch_right := false
var touch_jump := false
var touch_down := false
var touch_push := false

var rig: Node3D
var ragdoll: Node3D = null
var col: CollisionShape3D
var shape: CapsuleShape3D
var crouching := false
var facing := 1.0
var grabbed: RigidBody3D = null


func _ready() -> void:
	col = CollisionShape3D.new()
	shape = CapsuleShape3D.new()
	shape.radius = 0.3
	shape.height = STAND_H
	col.shape = shape
	col.position.y = STAND_H / 2.0
	add_child(col)

	rig = Node3D.new()
	rig.set_script(load("res://character.gd"))
	add_child(rig)


func _set_crouch(v: bool) -> void:
	crouching = v
	shape.height = CROUCH_H if v else STAND_H
	col.position.y = shape.height / 2.0


func _find_crate() -> RigidBody3D:
	for n in get_tree().get_nodes_in_group("crate"):
		var c := n as RigidBody3D
		if c == null:
			continue
		var dx := c.global_position.x - global_position.x
		var dy := c.global_position.y - global_position.y
		if absf(dx) < GRAB_REACH and absf(dy - 0.5) < 0.6 and signf(dx) == facing:
			return c
	return null


func _physics_process(delta: float) -> void:
	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or touch_left:
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D) or touch_right:
		dir += 1.0
	var down_held := Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) or touch_down
	var push_held := Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SHIFT) or touch_push
	var want_jump := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or touch_jump

	if down_held and is_on_floor():
		_set_crouch(true)
	elif crouching and not down_held:
		if not test_move(global_transform, Vector3(0.0, STAND_H - CROUCH_H + 0.05, 0.0)):
			_set_crouch(false)

	if push_held and is_on_floor() and not crouching:
		if grabbed == null:
			grabbed = _find_crate()
		elif absf(grabbed.global_position.x - global_position.x) > 1.6:
			grabbed = null
	else:
		grabbed = null

	if dir != 0.0 and grabbed == null:
		facing = signf(dir)

	var spd := SPEED
	if crouching:
		spd = CROUCH_SPEED
	elif grabbed != null:
		spd = GRAB_SPEED

	velocity.x = dir * spd
	velocity.z = 0.0
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif want_jump and not crouching and grabbed == null:
		velocity.y = JUMP

	move_and_slide()
	position.z = 0.0

	if grabbed != null:
		grabbed.sleeping = false
		grabbed.linear_velocity.x = dir * spd

	rig.animate(delta, velocity.x, velocity.y, is_on_floor(), crouching, grabbed != null, facing, dir)


func die(push: float) -> void:
	if ragdoll != null:
		return
	rig.visible = false
	ragdoll = rig.spawn_ragdoll(get_parent(), velocity, push)


func respawn(pos: Vector3) -> void:
	if ragdoll != null:
		ragdoll.queue_free()
		ragdoll = null
	rig.visible = true
	position = pos
	velocity = Vector3.ZERO
	grabbed = null
	if crouching:
		_set_crouch(false)

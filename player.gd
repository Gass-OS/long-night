extends CharacterBody3D
# Player v2: acceleration and momentum, coyote time, jump buffer, variable jump height,
# 3 hit points (dog bites and police shots), knockback, stun, blood trail when wounded.

signal damaged(dir: float, left: int)
signal respawned

const SPEED := 4.0
const CROUCH_SPEED := 1.6
const GRAB_SPEED := 1.8
const JUMP := 7.0
const GRAVITY := 18.0
const FALL_MULT := 1.35
const ACCEL := 30.0
const DECEL := 38.0
const AIR_ACCEL := 16.0
const COYOTE := 0.12
const BUFFER := 0.12
const STAND_H := 1.5
const CROUCH_H := 0.9
const GRAB_REACH := 1.05
const MAX_HEALTH := 3
const INVULN := 1.4
const STUN := 0.35

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

var health := MAX_HEALTH
var invuln := 0.0
var stun := 0.0
var regen_t := 0.0
var coyote := 0.0
var buffer := 0.0
var prev_jump := false
var jumping := false
var slope_s := 0.0
var trail_dist := 0.0
var decals: Array = []

static var blood_mat: StandardMaterial3D = null


func _ready() -> void:
	floor_max_angle = deg_to_rad(50.0)
	floor_snap_length = 0.35
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


func _nearest_enemy_x() -> float:
	var best := NAN
	var bd := 1000000.0
	var lvl := get_parent()
	var lists: Array = []
	if lvl != null:
		for key in ["dogs", "thugs"]:
			var arr = lvl.get(key)
			if arr != null:
				lists.append(arr)
	lists.append(get_tree().get_nodes_in_group("police"))
	for arr in lists:
		for e in arr:
			if is_instance_valid(e):
				var d := absf(e.global_position.x - global_position.x)
				if d < bd:
					bd = d
					best = e.global_position.x
	return best


func absorb_hit() -> bool:
	# Called by the level when an enemy lands a hit. Returns true if the hit was survived.
	if invuln > 0.0:
		return true
	health -= 1
	if health <= 0:
		health = 0
		return false
	invuln = INVULN
	stun = STUN
	regen_t = 0.0
	var ex := _nearest_enemy_x()
	var away := -facing
	if not is_nan(ex):
		var d := global_position.x - ex
		if absf(d) > 0.05:
			away = signf(d)
	velocity.x = away * 5.5
	velocity.y = 3.2
	grabbed = null
	damaged.emit(away, health)
	return true


func _blood_decal() -> void:
	if blood_mat == null:
		blood_mat = StandardMaterial3D.new()
		blood_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		blood_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		blood_mat.albedo_color = Color(0.35, 0.02, 0.02, 0.85)
	var q := QuadMesh.new()
	q.orientation = PlaneMesh.FACE_Y
	var s := randf_range(0.2, 0.42)
	q.size = Vector2(s * randf_range(1.0, 1.8), s)
	q.material = blood_mat
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.position = Vector3(global_position.x, global_position.y + 0.03, randf_range(-0.35, 0.35))
	mi.rotation.y = randf() * PI
	get_parent().add_child(mi)
	decals.append(mi)
	if decals.size() > 40:
		var old = decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()


func _physics_process(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	stun = maxf(0.0, stun - delta)

	var dir := 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A) or touch_left:
		dir -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D) or touch_right:
		dir += 1.0
	var down_held := Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S) or touch_down
	var push_held := Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SHIFT) or touch_push
	var want_jump := Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP) or touch_jump
	if stun > 0.0:
		dir = 0.0
		down_held = false
		push_held = false
		want_jump = false
	var jump_pressed := want_jump and not prev_jump
	prev_jump = want_jump

	# regeneration: one hit point comes back after a while without damage
	if health < MAX_HEALTH and health > 0:
		regen_t += delta
		if regen_t > 18.0:
			regen_t = 0.0
			health += 1

	# Crouch (stay crouched if something is above)
	if down_held and is_on_floor():
		_set_crouch(true)
	elif crouching and not down_held:
		if not test_move(global_transform, Vector3(0.0, STAND_H - CROUCH_H + 0.05, 0.0)):
			_set_crouch(false)

	# Grab a crate: hold PUSH while facing it
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
	if health <= 1:
		spd *= 0.85

	# momentum
	var on_floor := is_on_floor()
	if stun <= 0.0:
		var target_vx := dir * spd
		var accel := ACCEL
		if not on_floor:
			accel = AIR_ACCEL
		elif dir == 0.0:
			accel = DECEL
		elif signf(dir) != signf(velocity.x) and absf(velocity.x) > 0.1:
			accel = DECEL
		velocity.x = move_toward(velocity.x, target_vx, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, 6.0 * delta)
	velocity.z = 0.0

	# jump: coyote time, buffer, variable height
	if on_floor:
		coyote = COYOTE
		jumping = false
	else:
		coyote -= delta
	if jump_pressed:
		buffer = BUFFER
	else:
		buffer -= delta
	if buffer > 0.0 and coyote > 0.0 and not crouching and grabbed == null:
		velocity.y = JUMP
		buffer = 0.0
		coyote = 0.0
		jumping = true
	if jumping and not want_jump and velocity.y > 3.5:
		velocity.y = 3.5
		jumping = false

	if not on_floor:
		var g := GRAVITY
		if velocity.y < 0.0:
			g *= FALL_MULT
		velocity.y -= g * delta

	move_and_slide()
	position.z = 0.0

	if grabbed != null:
		grabbed.sleeping = false
		grabbed.linear_velocity.x = velocity.x

	# blood trail while wounded
	if health <= 1 and is_on_floor() and absf(velocity.x) > 0.3 and ragdoll == null:
		trail_dist += absf(velocity.x) * delta
		if trail_dist > 0.9:
			trail_dist = 0.0
			_blood_decal()

	# feed the skeleton
	var sl := 0.0
	if is_on_floor():
		var n := get_floor_normal()
		if n.y > 0.1:
			sl = atan((-n.x / n.y) * facing)
	slope_s = lerpf(slope_s, sl, clampf(delta * 8.0, 0.0, 1.0))
	if rig.get("hurt") != null:
		rig.set("hurt", clampf(stun / STUN, 0.0, 1.0))
		rig.set("slope", slope_s)
		rig.set("wounded", health <= 1)
	if ragdoll == null:
		rig.visible = true if (invuln <= 0.0 or health <= 0) else (int(invuln * 14.0) % 2 == 0)
	rig.animate(delta, velocity.x, velocity.y, is_on_floor(), crouching, grabbed != null, facing, dir)


func die(push: float) -> void:
	if ragdoll != null:
		return
	damaged.emit(push, 0)
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
	health = MAX_HEALTH
	invuln = 1.0
	stun = 0.0
	regen_t = 0.0
	if crouching:
		_set_crouch(false)
	respawned.emit()

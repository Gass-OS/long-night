#!/data/data/com.termux/files/usr/bin/bash
# Long Night - Step 17
#  - character v2: better skeleton shape, momentum movement, coyote time, jump buffer, variable jump
#  - health: 3 hits (dog bite or police shot), knockback, blood lines, blood on screen and on the ground
#  - police officers who shoot (stage 1)
#  - opening drone flight over Kasserine, down to the hero, then the game starts
# Your old character.gd / player.gd are saved in ~/long-night-backup-step17
set -e
cd ~/long-night

mkdir -p ~/long-night-backup-step17
cp -f *.gd *.tscn project.godot ~/long-night-backup-step17/ 2>/dev/null || true
git tag -f backup-before-step17 >/dev/null 2>&1 || true

cat > character.gd << 'EOF'
extends Node3D
# Procedural skeleton for the boy (about 1.5 m tall). Local forward is +Z.
# v2: smoother body shape (joint spheres, hands, face, shoes), hurt / slope / wounded poses.
# Joints: hips, spine, chest, neck, head, shoulders, elbows, hips, knees, ankles.

signal footstep(strength: float)

const SKIN := Color(0.82, 0.66, 0.56)
const SHIRT := Color(0.62, 0.09, 0.07)
const PANTS := Color(0.1, 0.1, 0.13)
const SHOE := Color(0.05, 0.05, 0.06)
const HAIR := Color(0.03, 0.03, 0.035)

const THIGH := 0.37
const SHIN := 0.37
const ANKLE := 0.06
const HIP_DROP := 0.02
const TORSO_LOW := 0.2
const TORSO_UP := 0.2
const UPPER_ARM := 0.27
const FORE_ARM := 0.25

var hips: Node3D
var spine: Node3D
var chest: Node3D
var neck: Node3D
var head: Node3D
var arm_u: Array = []
var arm_l: Array = []
var leg_u: Array = []
var leg_l: Array = []
var foot: Array = []
var bone_defs: Array = []

# set from outside (player): damage reaction, floor slope along the facing direction, low health
var hurt := 0.0
var slope := 0.0
var wounded := false

var phase := 0.0
var gait := 0.0
var yaw := 0.0
var blend_crouch := 0.0
var blend_grab := 0.0
var blend_air := 0.0
var blend_wound := 0.0
var lean := 0.0
var lean_v := 0.0
var head_p := 0.0
var head_v := 0.0
var hip_off := 0.0
var hip_v := 0.0
var was_air := false
var idle_t := 0.0
var last_step := 0


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	return m


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.position = pos
	parent.add_child(p)
	return p


func _capsule(parent: Node3D, radius: float, length: float, color: Color, center: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(length, radius * 2.0 + 0.001)
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = center
	parent.add_child(mi)
	return mi


func _sphere(parent: Node3D, radius: float, color: Color, center: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = _mat(color)
	mi.position = center
	parent.add_child(mi)
	return mi


func _box(parent: Node3D, size: Vector3, color: Color, center: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = center
	parent.add_child(mi)
	return mi


func _cap_shape(radius: float, height: float) -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = radius
	c.height = height
	return c


func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _sphere_shape(radius: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = radius
	return s


func _def(pivots: Array, parent: int, shape: Shape3D, center: Vector3, mass: float, joint_pivot) -> int:
	bone_defs.append({"pivots": pivots, "parent": parent, "shape": shape, "center": center, "mass": mass, "joint": joint_pivot})
	return bone_defs.size() - 1


func _ready() -> void:
	# pelvis
	hips = _pivot(self, Vector3(0, 0.82, 0))
	_box(hips, Vector3(0.25, 0.13, 0.15), PANTS, Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		_sphere(hips, 0.075, PANTS, Vector3(sx * 0.085, -0.01, 0.0))

	# torso (hoodie)
	spine = _pivot(hips, Vector3(0, 0.04, 0))
	_capsule(spine, 0.095, TORSO_LOW + 0.06, SHIRT, Vector3(0, TORSO_LOW * 0.5, 0))
	_box(spine, Vector3(0.24, 0.05, 0.14), SHIRT, Vector3(0, -0.02, 0))
	chest = _pivot(spine, Vector3(0, TORSO_LOW, 0))
	_capsule(chest, 0.112, TORSO_UP + 0.12, SHIRT, Vector3(0, 0.09, 0))

	# neck and head
	neck = _pivot(chest, Vector3(0, TORSO_UP, 0))
	_capsule(neck, 0.035, 0.1, SKIN, Vector3(0, 0.025, 0))
	head = _pivot(neck, Vector3(0, 0.05, 0))
	var skull := _sphere(head, 0.1, SKIN, Vector3(0, 0.095, 0))
	skull.scale = Vector3(0.93, 1.06, 1.0)
	_sphere(head, 0.062, SKIN, Vector3(0, 0.045, 0.035))
	_sphere(head, 0.018, SKIN, Vector3(0, 0.088, 0.1))
	for sx in [-1.0, 1.0]:
		_sphere(head, 0.02, SKIN, Vector3(sx * 0.093, 0.1, -0.005))
		_sphere(head, 0.011, Color(0.01, 0.01, 0.012), Vector3(sx * 0.034, 0.108, 0.088))
		_box(head, Vector3(0.03, 0.006, 0.01), HAIR, Vector3(sx * 0.034, 0.128, 0.09))
	var hair := _sphere(head, 0.104, HAIR, Vector3(0, 0.118, -0.012))
	hair.scale = Vector3(1.0, 0.8, 1.0)
	_box(head, Vector3(0.14, 0.03, 0.05), HAIR, Vector3(0, 0.168, 0.05))

	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		# arm: shoulder, elbow, hand with thumb
		var au := _pivot(chest, Vector3(sx * 0.155, TORSO_UP - 0.03, 0))
		_sphere(au, 0.055, SHIRT, Vector3.ZERO)
		_capsule(au, 0.04, UPPER_ARM, SHIRT, Vector3(0, -UPPER_ARM * 0.5, 0))
		var al := _pivot(au, Vector3(0, -UPPER_ARM, 0))
		_sphere(al, 0.037, SKIN, Vector3.ZERO)
		_capsule(al, 0.033, FORE_ARM, SKIN, Vector3(0, -FORE_ARM * 0.5, 0))
		var hand := _sphere(al, 0.04, SKIN, Vector3(0, -FORE_ARM - 0.02, 0))
		hand.scale = Vector3(0.9, 1.25, 0.65)
		_sphere(al, 0.016, SKIN, Vector3(-sx * 0.03, -FORE_ARM - 0.005, 0.025))
		arm_u.append(au)
		arm_l.append(al)

		# leg: hip, knee, ankle, shoe
		var lu := _pivot(hips, Vector3(sx * 0.07, -HIP_DROP, 0))
		_capsule(lu, 0.058, THIGH, PANTS, Vector3(0, -THIGH * 0.5, 0))
		var ll := _pivot(lu, Vector3(0, -THIGH, 0))
		_sphere(ll, 0.05, PANTS, Vector3.ZERO)
		_capsule(ll, 0.046, SHIN, PANTS, Vector3(0, -SHIN * 0.5, 0))
		var ft := _pivot(ll, Vector3(0, -SHIN, 0))
		_sphere(ft, 0.042, PANTS, Vector3.ZERO)
		_box(ft, Vector3(0.085, 0.05, 0.19), SHOE, Vector3(0, -0.035, 0.045))
		var toe := _sphere(ft, 0.045, SHOE, Vector3(0, -0.035, 0.13))
		toe.scale = Vector3(1.0, 0.65, 1.0)
		leg_u.append(lu)
		leg_l.append(ll)
		foot.append(ft)

	# Ragdoll bone table (bodies are built from the current pose on death)
	var b_pelvis := _def([hips], -1, _box_shape(Vector3(0.25, 0.13, 0.15)), Vector3.ZERO, 4.0, null)
	var b_torso := _def([spine, chest], b_pelvis, _cap_shape(0.11, 0.5), Vector3(0, 0.2, 0), 6.0, spine)
	_def([neck, head], b_torso, _sphere_shape(0.1), Vector3(0, 0.145, 0), 2.0, neck)
	for side in 2:
		var b_ua := _def([arm_u[side]], b_torso, _cap_shape(0.04, 0.27), Vector3(0, -0.135, 0), 1.0, arm_u[side])
		_def([arm_l[side]], b_ua, _cap_shape(0.035, 0.29), Vector3(0, -0.14, 0), 0.8, arm_l[side])
		var b_th := _def([leg_u[side]], b_pelvis, _cap_shape(0.06, 0.37), Vector3(0, -0.185, 0), 2.0, leg_u[side])
		_def([leg_l[side], foot[side]], b_th, _cap_shape(0.05, 0.44), Vector3(0, -0.2, 0), 1.5, leg_l[side])


func animate(delta: float, vx: float, vy: float, on_floor: bool, crouching: bool, grabbing: bool, facing: float, input_dir: float) -> void:
	idle_t += delta
	var k := clampf(delta * 10.0, 0.0, 1.0)
	blend_crouch = lerpf(blend_crouch, 1.0 if crouching else 0.0, k)
	blend_grab = lerpf(blend_grab, 1.0 if grabbing else 0.0, k)
	blend_air = lerpf(blend_air, 0.0 if on_floor else 1.0, clampf(delta * 14.0, 0.0, 1.0))
	blend_wound = lerpf(blend_wound, 1.0 if wounded else 0.0, clampf(delta * 4.0, 0.0, 1.0))
	yaw = lerp_angle(yaw, deg_to_rad(90.0 * facing), clampf(delta * 12.0, 0.0, 1.0))
	rotation.y = yaw

	var speed := absf(vx)
	var moving := absf(input_dir) > 0.0 and speed > 0.2 and on_floor
	var walk_amt := clampf(speed / 4.0, 0.0, 1.0)
	if moving:
		phase += delta * 2.5 * speed * (1.0 - 0.2 * blend_wound)
		var step_idx := int(floor(phase / PI))
		if step_idx != last_step:
			last_step = step_idx
			if blend_crouch < 0.5:
				footstep.emit(walk_amt)
	var gait_target := lerpf(0.3, 0.85, walk_amt) * (1.0 - 0.25 * blend_wound) if moving else 0.0
	gait = lerpf(gait, gait_target, clampf(delta * 8.0, 0.0, 1.0))
	var kf := gait / 0.85
	var fall := clampf(-vy / 6.0, 0.0, 1.0)
	var sl := clampf(slope, -0.7, 0.7)

	# Legs: hip swing, knee flexion in the swing phase, flat feet (matching the slope)
	var hip_h := [0.0, 0.0]
	for i in 2:
		var ph := phase + (0.0 if i == 0 else PI)
		var a := gait * sin(ph)
		if i == 1:
			a *= 1.0 - 0.3 * blend_wound
		var knee := 1.5 * kf * pow(maxf(0.0, cos(ph)), 1.2) + 0.12 * kf
		a += 1.05 * blend_crouch + 0.12 * blend_grab
		knee += 1.8 * blend_crouch + 0.1 * blend_grab
		var a_air := (0.9 - 0.4 * fall) if i == 0 else (-0.2 + 0.2 * fall)
		var k_air := (1.3 - 0.7 * fall) if i == 0 else (0.6 - 0.3 * fall)
		a = lerpf(a, a_air, blend_air)
		knee = lerpf(knee, k_air, blend_air)
		leg_u[i].rotation.x = -a
		leg_l[i].rotation.x = knee
		foot[i].rotation.x = (a - knee) * 0.85 - sl * 0.9 * (1.0 - blend_air)
		hip_h[i] = HIP_DROP + THIGH * cos(a) + SHIN * cos(a - knee) + ANKLE

	# Pelvis height keeps the lowest foot on the ground; spring on landing
	var target_h: float = maxf(hip_h[0], hip_h[1]) + 0.1 * blend_air - 0.02 * blend_wound
	if on_floor and was_air:
		hip_v -= 1.6
	was_air = not on_floor
	hip_v += (0.0 - hip_off) * 180.0 * delta
	hip_v *= exp(-12.0 * delta)
	hip_off += hip_v * delta
	hips.position.y = target_h + hip_off

	# Torso lean (spring), slope lean, wounded stoop, hit recoil
	var lean_target := 0.06 + (0.16 * walk_amt if moving else 0.0) + 0.6 * blend_crouch + 0.28 * blend_grab
	lean_target += 0.2 * blend_wound + sl * 0.7 - 0.55 * hurt
	lean_v += (lean_target - lean) * 120.0 * delta
	lean_v *= exp(-10.0 * delta)
	lean += lean_v * delta
	spine.rotation.x = lean * 0.45
	chest.rotation.x = lean * 0.55
	spine.rotation.y = 0.1 * sin(phase) * kf
	chest.rotation.y = -0.16 * sin(phase) * kf
	chest.scale.y = 1.0 + 0.01 * sin(idle_t * 2.2) + 0.012 * blend_wound * sin(idle_t * 6.0)

	# Head keeps looking ahead, with a little lag
	var head_target := -lean * 0.85 + 0.03 * sin(idle_t * 0.9) + 0.35 * hurt - 0.12 * blend_wound
	head_v += (head_target - head_p) * 70.0 * delta
	head_v *= exp(-8.0 * delta)
	head_p += head_v * delta
	neck.rotation.x = head_p * 0.5
	head.rotation.x = head_p * 0.5 - 0.08 * sin(phase * 2.0) * kf

	# Arms: opposite swing, elbow bend, reach forward when pushing, up when jumping, flung back when hit
	for i in 2:
		var li := phase + (0.0 if i == 0 else PI)
		var alpha := -0.55 * gait * sin(li) + 0.1 + 0.015 * sin(idle_t * 1.8 + i)
		var elbow := 0.2 + 0.5 * kf * maxf(0.0, -sin(li)) + 0.2 * blend_wound
		alpha += 0.5 * blend_crouch
		alpha = lerpf(alpha, 1.45, blend_grab)
		elbow = lerpf(elbow, 0.3, blend_grab)
		alpha = lerpf(alpha, 2.25, blend_air)
		elbow = lerpf(elbow, 0.45, blend_air)
		alpha -= 0.9 * hurt
		arm_u[i].rotation.x = -alpha - lean
		arm_l[i].rotation.x = -elbow


func spawn_ragdoll(world_parent: Node, vel: Vector3, push: float) -> Node3D:
	# Planar ragdoll (rotates around world Z only), built from the current pose
	var root := Node3D.new()
	world_parent.add_child(root)
	var bodies: Array = []
	for b in bone_defs:
		var rb := RigidBody3D.new()
		rb.collision_layer = 4
		rb.collision_mask = 1
		rb.axis_lock_linear_z = true
		rb.axis_lock_angular_x = true
		rb.axis_lock_angular_y = true
		rb.linear_damp = 0.2
		rb.angular_damp = 1.5
		rb.mass = b["mass"]
		root.add_child(rb)
		var first: Node3D = b["pivots"][0]
		var tr := first.global_transform
		tr.basis = tr.basis.orthonormalized()
		rb.global_transform = tr
		var cs := CollisionShape3D.new()
		cs.shape = b["shape"]
		cs.position = b["center"]
		rb.add_child(cs)
		for pv in b["pivots"]:
			for ch in pv.get_children():
				if ch is MeshInstance3D:
					var m := ch.duplicate() as MeshInstance3D
					rb.add_child(m)
					m.global_transform = ch.global_transform
		rb.linear_velocity = vel + Vector3(push * randf_range(1.0, 3.0), randf_range(0.5, 2.5), 0.0)
		rb.angular_velocity = Vector3(0.0, 0.0, randf_range(-3.0, 3.0))
		bodies.append(rb)
	for i in bone_defs.size():
		var p: int = bone_defs[i]["parent"]
		if p < 0:
			continue
		var j := PinJoint3D.new()
		root.add_child(j)
		var jp: Node3D = bone_defs[i]["joint"]
		j.global_position = jp.global_position
		j.node_a = j.get_path_to(bodies[p])
		j.node_b = j.get_path_to(bodies[i])
	return root
EOF

cat > player.gd << 'EOF'
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
EOF

cat > police.gd << 'EOF'
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
EOF

cat > squad.gd << 'EOF'
extends Node
# Squad: puts two police officers in stage 1 (next to the police cars) and resets them on respawn.

var lv: Node = null
var age := 0
var officers: Array = []
var wired := false


func _process(_delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	var stage1 := cs.get("player") != null and cs.get("env") != null and cs.get("cam") != null and cs.get("weather") != null and cs.get("dogs") != null and cs.get("stage") == null
	if not stage1:
		lv = null
		return
	if lv != cs:
		lv = cs
		age = 0
		officers.clear()
		wired = false
	age += 1
	if age == 6:
		_spawn(60.0, 57.5, 62.5)
		_spawn(105.0, 102.0, 107.0)
	if age > 6 and not wired:
		var player = lv.get("player")
		if player != null and player.has_signal("respawned"):
			player.respawned.connect(_reset)
			wired = true


func _spawn(x: float, left_x: float, right_x: float) -> void:
	var p := CharacterBody3D.new()
	p.set_script(load("res://police.gd"))
	p.set("target", lv.get("player"))
	p.set("left_x", left_x)
	p.set("right_x", right_x)
	p.position = Vector3(x, 0.05, 0.0)
	if lv.has_method("_on_caught"):
		p.connect("caught", Callable(lv, "_on_caught"))
	lv.add_child(p)
	officers.append(p)


func _reset() -> void:
	for o in officers:
		if is_instance_valid(o):
			o.reset_state()
EOF

cat > vitals.gd << 'EOF'
extends Node
# Vitals: three "blood lines" of health, blood streaks on the screen, blood burst on hit.

class HealthLines extends Control:
	var health := 3
	var t := 0.0

	func _draw() -> void:
		var sz := get_viewport_rect().size
		var w := 64.0
		var gap := 10.0
		var x0 := sz.x * 0.5 - (3.0 * w + 2.0 * gap) * 0.5
		var y0 := 48.0
		var pulse := 0.65 + 0.35 * sin(t * 7.0) if health <= 1 else 1.0
		for i in 3:
			var r := Rect2(x0 + i * (w + gap), y0, w, 12.0)
			draw_rect(r.grow(2.0), Color(0, 0, 0, 0.6))
			if i < health:
				draw_rect(r, Color(0.75, 0.04, 0.04, pulse))
				draw_rect(Rect2(r.position.x, r.position.y, r.size.x, 3.0), Color(1.0, 0.35, 0.3, 0.7 * pulse))
			else:
				draw_rect(r, Color(0.12, 0.02, 0.02, 0.8))


class BloodOverlay extends Control:
	var intensity := 0.0
	var pulse := 0.0
	var streaks: Array = []

	func _draw() -> void:
		var sz := get_viewport_rect().size
		# red edges that grow when hurt
		var a := intensity * (0.55 + 0.25 * pulse)
		if a > 0.01:
			for i in 14:
				var e := 6.0 + i * 11.0
				var al := a * (1.0 - float(i) / 14.0) * 0.5
				var c := Color(0.5, 0.0, 0.0, al)
				draw_rect(Rect2(0, 0, sz.x, e), c)
				draw_rect(Rect2(0, sz.y - e, sz.x, e), c)
				draw_rect(Rect2(0, 0, e, sz.y), c)
				draw_rect(Rect2(sz.x - e, 0, e, sz.y), c)
		# blood streaks
		for s in streaks:
			var life: float = s["life"]
			var al2 := clampf(life / 1.2, 0.0, 1.0) * 0.8
			var p0: Vector2 = s["p"]
			var ang: float = s["a"]
			var ln: float = s["l"]
			var drip: float = (1.0 - life / float(s["max"])) * 40.0
			var p1 := p0 + Vector2(cos(ang), sin(ang)) * ln + Vector2(0.0, drip)
			draw_line(p0, p1, Color(0.45, 0.02, 0.02, al2), float(s["w"]))
			draw_circle(p1, float(s["w"]) * 0.8, Color(0.4, 0.02, 0.02, al2))


var lv: Node = null
var age := 0
var player = null
var layer: CanvasLayer = null
var lines: HealthLines = null
var overlay: BloodOverlay = null
var t := 0.0


func _process(delta: float) -> void:
	t += delta
	var cs := get_tree().current_scene
	if cs == null:
		return
	if cs.get("player") == null or cs.get("env") == null or cs.get("cam") == null:
		lv = null
		return
	if lv != cs:
		lv = cs
		age = 0
		player = null
		layer = null
	age += 1
	if age == 4:
		_setup(cs)
	elif age > 4 and layer != null and is_instance_valid(player):
		_update(delta)


func _setup(cs: Node) -> void:
	player = cs.get("player")
	if player == null or not player.has_signal("damaged"):
		return
	layer = CanvasLayer.new()
	layer.layer = 14
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	cs.add_child(layer)
	overlay = BloodOverlay.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	lines = HealthLines.new()
	lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(lines)
	player.damaged.connect(_on_damaged)
	player.respawned.connect(_on_respawn)


func _on_respawn() -> void:
	overlay.streaks.clear()


func _on_damaged(dir: float, left: int) -> void:
	var sz := get_viewport().get_visible_rect().size
	var n := 7 if left > 0 else 12
	for i in n:
		var life := randf_range(2.2, 3.4)
		overlay.streaks.append({
			"p": Vector2(randf_range(0.1, 0.9) * sz.x, randf_range(0.05, 0.6) * sz.y),
			"a": randf_range(0.3, 2.8),
			"l": randf_range(40.0, 170.0),
			"w": randf_range(3.0, 9.0),
			"life": life,
			"max": life,
		})
	_burst(dir)


func _burst(dir: float) -> void:
	var p := GPUParticles3D.new()
	p.amount = 26
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	p.visibility_aabb = AABB(Vector3(-4, -2, -4), Vector3(8, 6, 8))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.15
	pm.direction = Vector3(dir * 0.6, 1.0, 0.0)
	pm.spread = 55.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0.0, -12.0, 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.3
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.5, 0.02, 0.02)
	quad.material = m
	p.draw_pass_1 = quad
	p.position = player.global_position + Vector3(0.0, 1.0, 0.2)
	lv.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _update(delta: float) -> void:
	var hp: int = int(player.get("health"))
	lines.health = hp
	lines.t = t
	lines.queue_redraw()
	var target := (3.0 - float(hp)) / 3.0
	overlay.intensity = lerpf(overlay.intensity, target, clampf(delta * 3.0, 0.0, 1.0))
	overlay.pulse = 0.5 + 0.5 * sin(t * 7.0) if hp <= 1 else 0.0
	for i in range(overlay.streaks.size() - 1, -1, -1):
		var s: Dictionary = overlay.streaks[i]
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			overlay.streaks.remove_at(i)
	overlay.queue_redraw()
EOF

cat > drone.gd << 'EOF'
extends Node
# Drone: opening cinematic. A drone flies over Kasserine at night, dives toward the hero,
# then blends into the game camera and the game starts. Tap to skip.

const DURATION := 17.0
const P0 := Vector3(-360.0, 330.0, 200.0)
const P1 := Vector3(-220.0, 210.0, 90.0)
const P2 := Vector3(-110.0, 110.0, 40.0)
const P3 := Vector3(-30.0, 40.0, 20.0)
const CITY_CENTER := Vector3(50.0, 10.0, -200.0)

static var played := false


class DroneHud extends Control:
	var alt := 300.0
	var spd := 0.0
	var tc := "00:00:00"
	var blink := 0.0

	func _draw() -> void:
		var sz := get_viewport_rect().size
		var font := ThemeDB.fallback_font
		var c := Color(1, 1, 1, 0.85)
		var m := 56.0
		var x0 := m
		var y0 := m + 20.0
		var x1 := sz.x - m
		var y1 := sz.y - m - 20.0
		var l := 46.0
		draw_polyline(PackedVector2Array([Vector2(x0, y0 + l), Vector2(x0, y0), Vector2(x0 + l, y0)]), c, 3.0)
		draw_polyline(PackedVector2Array([Vector2(x1 - l, y0), Vector2(x1, y0), Vector2(x1, y0 + l)]), c, 3.0)
		draw_polyline(PackedVector2Array([Vector2(x0, y1 - l), Vector2(x0, y1), Vector2(x0 + l, y1)]), c, 3.0)
		draw_polyline(PackedVector2Array([Vector2(x1 - l, y1), Vector2(x1, y1), Vector2(x1, y1 - l)]), c, 3.0)
		var cx := sz.x * 0.5
		var cy := sz.y * 0.5
		draw_line(Vector2(cx - 16, cy), Vector2(cx + 16, cy), Color(1, 1, 1, 0.5), 2.0)
		draw_line(Vector2(cx, cy - 16), Vector2(cx, cy + 16), Color(1, 1, 1, 0.5), 2.0)
		if int(blink * 2.0) % 2 == 0:
			draw_circle(Vector2(x0 + 14, y0 + 40), 8.0, Color(1.0, 0.1, 0.1, 0.95))
		draw_string(font, Vector2(x0 + 32, y0 + 50), "REC", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(cx - 90, y0 + 50), tc, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(x1 - 190, y0 + 50), "BAT 87%", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(x0, y1 - 44), "KASSERINE  -  TUNISIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(x0, y1 - 12), "35.17 N    8.84 E", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.65))
		draw_string(font, Vector2(x1 - 260, y1 - 44), "ALT  %d m" % int(alt), HORIZONTAL_ALIGNMENT_LEFT, -1, 28, c)
		draw_string(font, Vector2(x1 - 260, y1 - 12), "SPD  %d m/s" % int(spd), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.65))
		draw_string(font, Vector2(cx - 80, y1 - 12), "TAP TO SKIP", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.4))


var lv: Node = null
var age := 0
var active := false
var t := 0.0
var dcam: Camera3D = null
var hud_layer: CanvasLayer = null
var hud: DroneHud = null
var cover_layer: CanvasLayer = null
var cover: ColorRect = null
var city_root: Node3D = null
var rotor: AudioStreamPlayer = null
var saved_fog := 0.0
var saved_vfog := false
var last_pos := Vector3.ZERO
var layer_timer := 0.0


func _process(delta: float) -> void:
	var cs := get_tree().current_scene
	if cs == null:
		return
	if cs.get("main_box") != null or cs.name == "Intro":
		played = false
		lv = null
		return
	var stage1 := cs.get("player") != null and cs.get("env") != null and cs.get("cam") != null and cs.get("weather") != null and cs.get("dogs") != null and cs.get("stage") == null
	if not stage1:
		lv = null
		return
	if lv != cs:
		lv = cs
		age = 0
		active = false
	age += 1
	if age == 1 and not played:
		_begin(cs)
	elif active:
		_fly(delta)


func _input(event: InputEvent) -> void:
	if active and t > 1.0 and event is InputEventScreenTouch and event.pressed:
		_end(true)


# ---------- helpers ----------

func _hide_layers(hide: bool) -> void:
	for c in lv.get_children():
		if c is CanvasLayer and c != hud_layer and c != cover_layer:
			c.visible = not hide


func _mat(color: Color, rough := 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
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
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _multimesh(parent: Node, xf: Array, size: Vector3, mat: Material, colors: Array) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors.size() == xf.size()
	mm.mesh = _box(size)
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# ---------- the city seen from the sky ----------

func _build_city(cs: Node) -> void:
	city_root = Node3D.new()
	cs.add_child(city_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	_mi(city_root, _box(Vector3(1800.0, 1.0, 1800.0)), _mat(Color(0.03, 0.03, 0.035)), Vector3(60.0, -1.2, -400.0))

	var xf: Array = []
	var colors: Array = []
	var lit: Array = []
	var lamps: Array = []
	var gx := -320.0
	while gx < 420.0:
		var gz := -75.0
		while gz > -360.0:
			if rng.randf() < 0.88:
				var w := rng.randf_range(7.0, 11.0)
				var d := rng.randf_range(7.0, 11.0)
				var h := rng.randf_range(5.0, 20.0)
				if rng.randf() < 0.08:
					h += rng.randf_range(10.0, 28.0)
				var cx := gx + rng.randf_range(-1.5, 1.5)
				var cz := gz + rng.randf_range(-1.5, 1.5)
				xf.append(Transform3D(Basis().scaled(Vector3(w, h, d)), Vector3(cx, h / 2.0, cz)))
				var tone := rng.randf_range(0.1, 0.24)
				colors.append(Color(tone, tone * 0.94, tone * 0.82))
				if rng.randf() < 0.5:
					for k in rng.randi_range(2, 6):
						lit.append(Transform3D(Basis(), Vector3(cx + rng.randf_range(-w * 0.4, w * 0.4), rng.randf_range(2.0, maxf(h - 1.0, 2.5)), cz + d / 2.0 + 0.05)))
			lamps.append(Transform3D(Basis(), Vector3(gx + 7.0, 4.5, gz + 7.0)))
			gz -= 14.0
		gx += 14.0
	var bmat := StandardMaterial3D.new()
	bmat.vertex_color_use_as_albedo = true
	bmat.roughness = 1.0
	_multimesh(city_root, xf, Vector3(1, 1, 1), bmat, colors)
	_multimesh(city_root, lit, Vector3(1.2, 1.6, 0.1), _glow(Color(1.0, 0.72, 0.3), 3.0), [])
	_multimesh(city_root, lamps, Vector3(0.6, 0.6, 0.6), _glow(Color(1.0, 0.7, 0.35), 4.0), [])

	# minarets
	var wall := _mat(Color(0.3, 0.27, 0.22))
	for mp in [Vector2(-60.0, -180.0), Vector2(140.0, -250.0), Vector2(250.0, -120.0), Vector2(0.0, -310.0)]:
		_mi(city_root, _box(Vector3(3.0, 44.0, 3.0)), wall, Vector3(mp.x, 22.0, mp.y))
		_mi(city_root, _box(Vector3(4.2, 0.8, 4.2)), wall, Vector3(mp.x, 37.0, mp.y))
		_mi(city_root, _box(Vector3(4.4, 0.35, 4.4)), _glow(Color(0.1, 1.0, 0.5), 2.5), Vector3(mp.x, 37.6, mp.y))
		_mi(city_root, _box(Vector3(2.4, 6.0, 2.4)), wall, Vector3(mp.x, 47.0, mp.y))
		var dome := SphereMesh.new()
		dome.radius = 1.6
		dome.height = 1.6
		dome.is_hemisphere = true
		_mi(city_root, dome, _mat(Color(0.2, 0.34, 0.3), 0.4), Vector3(mp.x, 50.0, mp.y))

	# Mount Chaambi in the distance
	var rock := _mat(Color(0.035, 0.04, 0.055))
	var big := PrismMesh.new()
	big.size = Vector3(900.0, 200.0, 140.0)
	_mi(city_root, big, rock, Vector3(40.0, 80.0, -620.0))
	var small := PrismMesh.new()
	small.size = Vector3(500.0, 120.0, 100.0)
	_mi(city_root, small, rock, Vector3(-380.0, 40.0, -520.0))


func _make_rotor() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 8
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	var lp := 0.0
	for i in n:
		var tt := float(i) / rate
		var hum := sin(TAU * 118.0 * tt) * 0.22 + sin(TAU * 236.0 * tt) * 0.1
		var am := 0.8 + 0.2 * sin(TAU * 18.0 * tt)
		lp += ((randf() * 2.0 - 1.0) - lp) * 0.3
		var v := (hum * am + lp * 0.18) * 0.8
		bytes.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


# ---------- flight ----------

func _begin(cs: Node) -> void:
	played = true
	var player = cs.get("player")
	var env: Environment = cs.get("env")

	cover_layer = CanvasLayer.new()
	cover_layer.layer = 60
	cs.add_child(cover_layer)
	cover = ColorRect.new()
	cover.color = Color.BLACK
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_layer.add_child(cover)

	hud_layer = CanvasLayer.new()
	hud_layer.layer = 50
	cs.add_child(hud_layer)
	hud = DroneHud.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_layer.add_child(hud)

	player.set_physics_process(false)
	_hide_layers(true)
	saved_fog = env.fog_density
	saved_vfog = env.volumetric_fog_enabled
	env.fog_density = 0.0012
	env.volumetric_fog_enabled = false
	_build_city(cs)

	dcam = Camera3D.new()
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_near_enabled = false
	attrs.exposure_multiplier = 2.2
	dcam.attributes = attrs
	dcam.fov = 72.0
	dcam.far = 3000.0
	cs.add_child(dcam)
	dcam.global_position = P0
	dcam.look_at(CITY_CENTER, Vector3.UP)
	dcam.make_current()
	last_pos = P0

	rotor = AudioStreamPlayer.new()
	rotor.stream = _make_rotor()
	rotor.volume_db = -12.0
	cs.add_child(rotor)
	rotor.play()

	t = 0.0
	active = true
	var tw := create_tween()
	tw.tween_property(cover, "modulate:a", 0.0, 1.0)


func _fly(delta: float) -> void:
	t += delta
	layer_timer -= delta
	if layer_timer <= 0.0:
		layer_timer = 0.2
		_hide_layers(true)
	var u := clampf(t / DURATION, 0.0, 1.0)
	var cam: Camera3D = lv.get("cam")
	var player = lv.get("player")
	var end_t := cam.global_transform
	var pts := [P0, P0, P1, P2, P3, end_t.origin, end_t.origin]
	var s := u * u * (3.0 - 2.0 * u)
	var f := s * 4.0
	var i := mini(int(f), 3)
	var w := f - i
	var a: Vector3 = pts[1 + i]
	var b: Vector3 = pts[2 + i]
	var pre: Vector3 = pts[i]
	var post: Vector3 = pts[3 + i]
	var pos := a.cubic_interpolate(b, pre, post, w)
	var bw := smoothstep(0.86, 1.0, u)
	pos += Vector3(sin(t * 37.0) * 0.05, sin(t * 29.0) * 0.04, 0.0) * (1.0 - bw)

	var lw := smoothstep(0.25, 0.85, u)
	var focus := CITY_CENTER.lerp(player.global_position + Vector3(0.0, 1.1, 0.0), lw)
	var dir := focus - pos
	if dir.length() < 0.5:
		dir = Vector3(0.0, 0.0, -1.0)
	var basis := Basis.looking_at(dir, Vector3.UP)
	var bank := sin(u * PI * 2.0) * 0.07 * (1.0 - bw)
	basis = basis.rotated(basis.z, bank)
	var tr := Transform3D(basis, pos)
	tr = tr.interpolate_with(end_t, bw)
	dcam.global_transform = tr
	dcam.fov = lerpf(72.0, cam.fov, bw)

	hud.alt = pos.y
	hud.spd = (pos - last_pos).length() / maxf(delta, 0.001)
	hud.blink = t
	hud.tc = "00:%02d:%02d" % [int(t), int((t - floor(t)) * 25.0)]
	hud.queue_redraw()
	last_pos = pos
	if t > DURATION - 2.0:
		rotor.volume_db = lerpf(-12.0, -50.0, (t - (DURATION - 2.0)) / 2.0)
	if u >= 1.0:
		_end(false)


func _end(skipped: bool) -> void:
	if not active:
		return
	active = false
	var cam: Camera3D = lv.get("cam")
	var player = lv.get("player")
	var env: Environment = lv.get("env")
	if skipped:
		cover.modulate.a = 1.0
	cam.make_current()
	if is_instance_valid(dcam):
		dcam.queue_free()
	if is_instance_valid(city_root):
		city_root.queue_free()
	env.fog_density = saved_fog
	env.volumetric_fog_enabled = saved_vfog
	_hide_layers(false)
	if is_instance_valid(hud_layer):
		hud_layer.queue_free()
	if is_instance_valid(rotor):
		rotor.stop()
		rotor.queue_free()
	player.set_physics_process(true)
	var tw := create_tween()
	tw.tween_property(cover, "modulate:a", 0.0, 0.5)
	tw.tween_callback(cover_layer.queue_free)
EOF

# A hit from a dog / thug / police is absorbed while the player still has hit points
for f in level.gd stage2.gd; do
	if [ -f "$f" ] && ! grep -q "absorb_hit" "$f"; then
		sed -i 's/^\tdead = true$/\tif use_ragdoll and player.has_method("absorb_hit") and player.absorb_hit():\n\t\treturn\n\tdead = true/' "$f"
	fi
done

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
add_autoload Vitals vitals.gd
add_autoload Squad squad.gd
add_autoload Drone drone.gd

echo "Duplicate function names left (nothing should be listed):"
for f in character.gd player.gd police.gd squad.gd vitals.gd drone.gd level.gd stage2.gd; do
	[ -f "$f" ] && grep -o '^func [a-zA-Z_0-9]*' "$f" | sort | uniq -d
done

git add -A
git commit -m "Step 17: character v2, health and blood, police, drone intro"
git push
echo "OK: pushed, build is starting. Backup: ~/long-night-backup-step17"

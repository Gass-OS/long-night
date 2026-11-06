extends Node3D
# Procedural skeleton for the boy (about 1.5 m tall). Local forward is +Z.
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

var phase := 0.0
var gait := 0.0
var yaw := 0.0
var blend_crouch := 0.0
var blend_grab := 0.0
var blend_air := 0.0
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


func _capsule(parent: Node3D, radius: float, length: float, color: Color, center: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(length, radius * 2.0 + 0.001)
	mi.mesh = cm
	mi.material_override = _mat(color)
	mi.position = center
	parent.add_child(mi)


func _sphere(parent: Node3D, radius: float, color: Color, center: Vector3, scale_y := 1.0) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	mi.material_override = _mat(color)
	mi.position = center
	mi.scale.y = scale_y
	parent.add_child(mi)


func _box(parent: Node3D, size: Vector3, color: Color, center: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
	mi.position = center
	parent.add_child(mi)


func _cap_shape(radius: float, height: float) -> CapsuleShape3D:
	var c := CapsuleShape3D.new()
	c.radius = radius
	c.height = height
	return c


func _def(pivots: Array, parent: int, shape: Shape3D, center: Vector3, mass: float, joint_pivot) -> int:
	bone_defs.append({"pivots": pivots, "parent": parent, "shape": shape, "center": center, "mass": mass, "joint": joint_pivot})
	return bone_defs.size() - 1


func _ready() -> void:
	hips = _pivot(self, Vector3(0, 0.82, 0))
	_box(hips, Vector3(0.25, 0.13, 0.15), PANTS, Vector3.ZERO)
	spine = _pivot(hips, Vector3(0, 0.04, 0))
	_capsule(spine, 0.10, TORSO_LOW + 0.06, SHIRT, Vector3(0, TORSO_LOW * 0.5, 0))
	chest = _pivot(spine, Vector3(0, TORSO_LOW, 0))
	_capsule(chest, 0.115, TORSO_UP + 0.1, SHIRT, Vector3(0, 0.09, 0))
	neck = _pivot(chest, Vector3(0, TORSO_UP, 0))
	_capsule(neck, 0.035, 0.1, SKIN, Vector3(0, 0.025, 0))
	head = _pivot(neck, Vector3(0, 0.05, 0))
	_sphere(head, 0.1, SKIN, Vector3(0, 0.095, 0))
	_sphere(head, 0.104, HAIR, Vector3(0, 0.115, -0.012), 0.8)

	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var au := _pivot(chest, Vector3(sx * 0.155, TORSO_UP - 0.03, 0))
		_capsule(au, 0.04, UPPER_ARM, SHIRT, Vector3(0, -UPPER_ARM * 0.5, 0))
		var al := _pivot(au, Vector3(0, -UPPER_ARM, 0))
		_capsule(al, 0.034, FORE_ARM, SKIN, Vector3(0, -FORE_ARM * 0.5, 0))
		_sphere(al, 0.04, SKIN, Vector3(0, -FORE_ARM - 0.015, 0))
		arm_u.append(au)
		arm_l.append(al)

		var lu := _pivot(hips, Vector3(sx * 0.07, -HIP_DROP, 0))
		_capsule(lu, 0.058, THIGH, PANTS, Vector3(0, -THIGH * 0.5, 0))
		var ll := _pivot(lu, Vector3(0, -THIGH, 0))
		_capsule(ll, 0.047, SHIN, PANTS, Vector3(0, -SHIN * 0.5, 0))
		var ft := _pivot(ll, Vector3(0, -SHIN, 0))
		_box(ft, Vector3(0.085, 0.06, 0.2), SHOE, Vector3(0, -0.03, 0.05))
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


func _box_shape(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b


func _sphere_shape(radius: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = radius
	return s


func animate(delta: float, vx: float, vy: float, on_floor: bool, crouching: bool, grabbing: bool, facing: float, input_dir: float) -> void:
	idle_t += delta
	var k := clampf(delta * 10.0, 0.0, 1.0)
	blend_crouch = lerpf(blend_crouch, 1.0 if crouching else 0.0, k)
	blend_grab = lerpf(blend_grab, 1.0 if grabbing else 0.0, k)
	blend_air = lerpf(blend_air, 0.0 if on_floor else 1.0, clampf(delta * 14.0, 0.0, 1.0))
	yaw = lerp_angle(yaw, deg_to_rad(90.0 * facing), clampf(delta * 12.0, 0.0, 1.0))
	rotation.y = yaw

	var speed := absf(vx)
	var moving := absf(input_dir) > 0.0 and speed > 0.2 and on_floor
	var walk_amt := clampf(speed / 4.0, 0.0, 1.0)
	if moving:
		phase += delta * 2.5 * speed
		var step_idx := int(floor(phase / PI))
		if step_idx != last_step:
			last_step = step_idx
			if blend_crouch < 0.5:
				footstep.emit(walk_amt)
	var gait_target := lerpf(0.3, 0.85, walk_amt) if moving else 0.0
	gait = lerpf(gait, gait_target, clampf(delta * 8.0, 0.0, 1.0))
	var kf := gait / 0.85
	var fall := clampf(-vy / 6.0, 0.0, 1.0)

	# Legs: hip swing, knee flexion in the swing phase, flat feet
	var hip_h := [0.0, 0.0]
	for i in 2:
		var ph := phase + (0.0 if i == 0 else PI)
		var a := gait * sin(ph)
		var knee := 1.5 * kf * pow(maxf(0.0, cos(ph)), 1.2) + 0.12 * kf
		a += 1.05 * blend_crouch + 0.12 * blend_grab
		knee += 1.8 * blend_crouch + 0.1 * blend_grab
		var a_air := (0.9 - 0.4 * fall) if i == 0 else (-0.2 + 0.2 * fall)
		var k_air := (1.3 - 0.7 * fall) if i == 0 else (0.6 - 0.3 * fall)
		a = lerpf(a, a_air, blend_air)
		knee = lerpf(knee, k_air, blend_air)
		leg_u[i].rotation.x = -a
		leg_l[i].rotation.x = knee
		foot[i].rotation.x = (a - knee) * 0.85
		hip_h[i] = HIP_DROP + THIGH * cos(a) + SHIN * cos(a - knee) + ANKLE

	# Pelvis height keeps the lowest foot on the ground; spring on landing
	var target_h: float = maxf(hip_h[0], hip_h[1]) + 0.1 * blend_air
	if on_floor and was_air:
		hip_v -= 1.6
	was_air = not on_floor
	hip_v += (0.0 - hip_off) * 180.0 * delta
	hip_v *= exp(-12.0 * delta)
	hip_off += hip_v * delta
	hips.position.y = target_h + hip_off

	# Torso lean (spring) and counter-twist
	var lean_target := 0.06 + (0.16 * walk_amt if moving else 0.0) + 0.6 * blend_crouch + 0.28 * blend_grab
	lean_v += (lean_target - lean) * 120.0 * delta
	lean_v *= exp(-10.0 * delta)
	lean += lean_v * delta
	spine.rotation.x = lean * 0.45
	chest.rotation.x = lean * 0.55
	spine.rotation.y = 0.1 * sin(phase) * kf
	chest.rotation.y = -0.16 * sin(phase) * kf
	chest.scale.y = 1.0 + 0.01 * sin(idle_t * 2.2)

	# Head keeps looking ahead, with a little lag
	var head_target := -lean * 0.85 + 0.03 * sin(idle_t * 0.9)
	head_v += (head_target - head_p) * 70.0 * delta
	head_v *= exp(-8.0 * delta)
	head_p += head_v * delta
	neck.rotation.x = head_p * 0.5
	head.rotation.x = head_p * 0.5 - 0.08 * sin(phase * 2.0) * kf

	# Arms: opposite swing, elbow bend, reach forward when pushing, up when jumping
	for i in 2:
		var li := phase + (0.0 if i == 0 else PI)
		var alpha := -0.55 * gait * sin(li) + 0.1 + 0.015 * sin(idle_t * 1.8 + i)
		var elbow := 0.2 + 0.5 * kf * maxf(0.0, -sin(li))
		alpha += 0.5 * blend_crouch
		alpha = lerpf(alpha, 1.45, blend_grab)
		elbow = lerpf(elbow, 0.3, blend_grab)
		alpha = lerpf(alpha, 2.25, blend_air)
		elbow = lerpf(elbow, 0.45, blend_air)
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

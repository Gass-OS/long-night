#!/data/data/com.termux/files/usr/bin/bash
# Long Night - Step 10
#  - procedural skeleton character + ragdoll death
#  - upgraded dogs (articulated legs, jaw, tail)
#  - Forward+ renderer: volumetric fog, SSAO, DOF, bloom, textures, foreground silhouettes
#  - menu: Settings + About developer, intro (video or in-engine cinematic)
set -e
cd ~/long-night

# 0) Safety backup (you did steps 8 and 9 yourself: nothing is lost)
mkdir -p ~/long-night-backup-step10
cp -f *.gd *.tscn project.godot ~/long-night-backup-step10/ 2>/dev/null || true
git tag -f backup-before-step10 >/dev/null 2>&1 || true

# 1) Renderer: Forward+ (Vulkan) for Adreno 8xx class GPUs
sed -i 's#^renderer/rendering_method=.*#renderer/rendering_method="forward_plus"#' project.godot
sed -i 's#^renderer/rendering_method.mobile=.*#renderer/rendering_method.mobile="forward_plus"#' project.godot
sed -i 's#^config/features=.*#config/features=PackedStringArray("4.3", "Forward Plus")#' project.godot

# 2) Settings (saved on the phone)
cat > settings.gd << 'EOF'
extends RefCounted

const PATH := "user://settings.cfg"

static var quality := 2   # 0 low, 1 medium, 2 high
static var volume := 0.9
static var show_fps := false
static var loaded := false


static func load_cfg() -> void:
	if loaded:
		return
	loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		quality = int(cf.get_value("game", "quality", 2))
		volume = float(cf.get_value("game", "volume", 0.9))
		show_fps = bool(cf.get_value("game", "show_fps", false))
	apply_audio()


static func save_cfg() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "quality", quality)
	cf.set_value("game", "volume", volume)
	cf.set_value("game", "show_fps", show_fps)
	cf.save(PATH)


static func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
EOF

# 3) Audio (generated once and cached) + footsteps
cat > audio.gd << 'EOF'
extends Node

static var cache := {}

var whisper_timer := 18.0
var thunder_p: AudioStreamPlayer
var whisper_p: AudioStreamPlayer
var bark_p: AudioStreamPlayer
var step_p: AudioStreamPlayer


func _ready() -> void:
	_add_player(_cached("rain", _make_rain), -15.0, true)
	_add_player(_cached("drone", _make_drone), -13.0, true)
	_add_player(_cached("voice", _make_voice), -19.0, true)
	thunder_p = _add_player(_cached("thunder", _make_thunder), -2.0, false)
	whisper_p = _add_player(_cached("whisper", _make_whisper), -9.0, false)
	bark_p = _add_player(_cached("bark", _make_bark), -3.0, false)
	bark_p.max_polyphony = 3
	step_p = _add_player(_cached("step", _make_step), -14.0, false)
	step_p.max_polyphony = 4


func _cached(key: String, maker: Callable) -> AudioStream:
	if not cache.has(key):
		cache[key] = maker.call()
	return cache[key]


func _process(delta: float) -> void:
	whisper_timer -= delta
	if whisper_timer <= 0.0:
		whisper_timer = randf_range(25.0, 55.0)
		whisper_p.pitch_scale = randf_range(0.75, 1.1)
		whisper_p.play()


func thunder() -> void:
	thunder_p.pitch_scale = randf_range(0.85, 1.1)
	thunder_p.play()


func bark() -> void:
	bark_p.pitch_scale = randf_range(0.85, 1.05)
	bark_p.play()


func step(strength: float) -> void:
	step_p.volume_db = -16.0 + 7.0 * clampf(strength, 0.0, 1.0)
	step_p.pitch_scale = randf_range(0.85, 1.15)
	step_p.play()


func _add_player(stream: AudioStream, db: float, auto: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	if auto:
		p.play()
	return p


func _to_wav(samples: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
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


func _make_rain() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 6
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.5
		lp2 += (lp - lp2) * 0.08
		s[i] = (lp - lp2) * 0.6
	return _to_wav(s, rate, true)


func _make_drone() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 8
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * 55.0 * t) * 0.35
		v += sin(TAU * 55.5 * t) * 0.35
		v += sin(TAU * 82.25 * t) * 0.18
		v += sin(TAU * 110.75 * t + 1.3) * 0.1
		var lfo := 0.65 + 0.35 * sin(TAU * t / 8.0)
		s[i] = v * lfo * 0.6
	return _to_wav(s, rate, true)


func _make_voice() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 8
	var s := PackedFloat32Array()
	s.resize(n)
	var f0s := [98.0, 98.5]
	var amps := [1.0, 0.8]
	var weights := []
	for j in 2:
		var row := []
		for k in range(1, 9):
			var fk: float = f0s[j] * k
			var w := exp(-pow((fk - 450.0) / 250.0, 2.0)) + 0.6 * exp(-pow((fk - 950.0) / 350.0, 2.0))
			row.append(w / pow(float(k), 0.5))
		weights.append(row)
	for i in n:
		var t := float(i) / rate
		var vib := 0.5 * sin(TAU * 0.5 * t)
		var v := 0.0
		for j in 2:
			var f0: float = f0s[j]
			var ph := TAU * f0 * t + vib * (j + 1)
			var voice := 0.0
			for k in range(1, 9):
				voice += sin(k * ph) * weights[j][k - 1]
			v += voice * amps[j]
		var env := 0.55 + 0.45 * sin(TAU * t / 8.0 - 1.0)
		s[i] = v * env * 0.12
	return _to_wav(s, rate, true)


func _make_thunder() -> AudioStreamWAV:
	var rate := 11025
	var n := rate * 5
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.06
		lp2 += (w - lp2) * 0.4
		var env := exp(-t * 0.7) * (0.65 + 0.35 * sin(t * 9.0 + sin(t * 3.0) * 2.0))
		var crack := exp(-t * 14.0) * lp2 * 1.2
		var fade := clampf((5.0 - t) / 0.3, 0.0, 1.0)
		s[i] = (lp * 5.0 * env + crack) * 0.8 * fade
	return _to_wav(s, rate, false)


func _make_whisper() -> AudioStreamWAV:
	var rate := 16000
	var n := int(rate * 2.4)
	var s := PackedFloat32Array()
	s.resize(n)
	var centers := []
	for j in 5:
		centers.append(randf_range(0.2, 2.2))
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var env := 0.0
		for c in centers:
			env += exp(-pow((t - float(c)) / 0.13, 2.0))
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.55
		lp2 += (lp - lp2) * 0.12
		s[i] = (lp - lp2) * minf(env, 1.0) * 0.8
	return _to_wav(s, rate, false)


func _make_bark() -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * 0.5)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		var tb := fmod(t, 0.24)
		var env := minf(tb / 0.008, 1.0) * exp(-tb * 14.0)
		var f := 380.0 - 700.0 * tb
		var ph := TAU * f * tb
		var tone := sin(ph) + 0.6 * sin(2.0 * ph) + 0.4 * sin(3.0 * ph) + 0.25 * sin(5.0 * ph)
		var noise := randf() * 2.0 - 1.0
		lp += (noise - lp) * 0.3
		s[i] = (tone * 0.35 + lp * 0.8) * env * 0.8
	return _to_wav(s, rate, false)


func _make_step() -> AudioStreamWAV:
	# Wet footstep: soft thud + splashy hiss
	var rate := 22050
	var n := int(rate * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / rate
		var w := randf() * 2.0 - 1.0
		lp += (w - lp) * 0.25
		lp2 += (lp - lp2) * 0.05
		var env := exp(-t * 38.0) * (1.0 - exp(-t * 600.0))
		var thud := sin(TAU * 90.0 * t) * exp(-t * 40.0) * 0.6
		s[i] = ((lp - lp2) * 1.2 + thud) * env * 0.7
	return _to_wav(s, rate, false)
EOF

# 4) Character: procedural skeleton + planar ragdoll
cat > character.gd << 'EOF'
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
EOF

# 5) Player (uses the skeleton)
cat > player.gd << 'EOF'
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
EOF

# 6) Dog: articulated legs (trot / gallop), neck, jaw, tail, glowing eyes
cat > dog.gd << 'EOF'
extends CharacterBody3D

signal caught
signal alerted

const PATROL_SPEED := 1.4
const CHASE_SPEED := 5.0
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
			if above_timer > 4.0:
				chasing = false
				ignore_timer = 4.0
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
EOF

# 7) Menu: Play / Settings / About developer / Quit
cat > menu.gd << 'EOF'
extends Control

const S = preload("res://settings.gd")
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]

var main_box: VBoxContainer
var settings_box: VBoxContainer
var about_box: VBoxContainer
var quality_btn: Button
var fps_btn: Button
var vol_label: Label
var vol_slider: HSlider
var audio


func _ready() -> void:
	S.load_cfg()
	get_tree().set_quit_on_go_back(true)
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	main_box = _box(center)
	var title := _label(main_box, "LONG NIGHT", 110, Color(0.85, 0.82, 0.78))
	_label(main_box, "KASSERINE", 34, Color(0.55, 0.15, 0.12))
	_spacer(main_box, 24)
	_button(main_box, "PLAY", _on_play)
	_button(main_box, "SETTINGS", func(): _show(settings_box))
	_button(main_box, "ABOUT", func(): _show(about_box))
	_button(main_box, "QUIT", func(): get_tree().quit())

	settings_box = _box(center)
	_label(settings_box, "SETTINGS", 64, Color(0.85, 0.82, 0.78))
	_spacer(settings_box, 10)
	vol_label = _label(settings_box, "", 30, Color(0.8, 0.8, 0.8))
	vol_slider = HSlider.new()
	vol_slider.min_value = 0.0
	vol_slider.max_value = 1.0
	vol_slider.step = 0.05
	vol_slider.value = S.volume
	vol_slider.custom_minimum_size = Vector2(520, 60)
	vol_slider.value_changed.connect(_on_volume)
	vol_slider.drag_ended.connect(func(_c): S.save_cfg())
	settings_box.add_child(vol_slider)
	quality_btn = _button(settings_box, "", _cycle_quality)
	fps_btn = _button(settings_box, "", _toggle_fps)
	_button(settings_box, "BACK", func():
		S.save_cfg()
		_show(main_box))
	_refresh_settings()

	about_box = _box(center)
	_label(about_box, "ABOUT", 64, Color(0.85, 0.82, 0.78))
	_spacer(about_box, 6)
	_label(about_box, "LONG NIGHT", 44, Color(0.85, 0.82, 0.78))
	_label(about_box, "A 2.5D horror adventure set in Kasserine, Tunisia", 26, Color(0.7, 0.7, 0.7))
	_spacer(about_box, 14)
	_label(about_box, "Created by", 26, Color(0.55, 0.15, 0.12))
	_label(about_box, "AYMEN GHARSALLI", 54, Color(0.9, 0.88, 0.84))
	_label(about_box, "Game developer", 26, Color(0.7, 0.7, 0.7))
	_spacer(about_box, 14)
	_label(about_box, "Made with Godot Engine 4  |  Version 0.10", 22, Color(0.5, 0.5, 0.5))
	_spacer(about_box, 10)
	_button(about_box, "BACK", func(): _show(main_box))

	_show(main_box)

	var tw := create_tween().set_loops()
	tw.tween_property(title, "modulate:a", 0.6, 1.6)
	tw.tween_property(title, "modulate:a", 1.0, 1.1)

	_start_audio()


func _start_audio() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	audio = Node.new()
	audio.set_script(load("res://audio.gd"))
	add_child(audio)


func _box(parent: Control) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_theme_constant_override("separation", 22)
	parent.add_child(b)
	return b


func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _spacer(parent: Control, h: float) -> void:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	parent.add_child(s)


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(520, 84)
	b.add_theme_font_size_override("font_size", 36)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _show(box: Control) -> void:
	main_box.visible = box == main_box
	settings_box.visible = box == settings_box
	about_box.visible = box == about_box


func _refresh_settings() -> void:
	vol_label.text = "VOLUME  %d%%" % int(round(S.volume * 100.0))
	quality_btn.text = "GRAPHICS: " + QUALITY_NAMES[S.quality]
	fps_btn.text = "SHOW FPS: " + ("ON" if S.show_fps else "OFF")


func _on_volume(v: float) -> void:
	S.volume = v
	S.apply_audio()
	_refresh_settings()


func _cycle_quality() -> void:
	S.quality = (S.quality + 1) % 3
	S.save_cfg()
	_refresh_settings()


func _toggle_fps() -> void:
	S.show_fps = not S.show_fps
	S.save_cfg()
	_refresh_settings()


func _on_play() -> void:
	get_tree().change_scene_to_file("res://intro.tscn")
EOF

# 8) Intro: plays res://intro.ogv if you add one, otherwise an in-engine cinematic
cat > intro.tscn << 'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://intro.gd" id="1"]

[node name="Intro" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1")
EOF

cat > intro.gd << 'EOF'
extends Control

const S = preload("res://settings.gd")
const VIDEO := "res://intro.ogv"

var label: Label
var flash: ColorRect
var audio
var finished := false
var started_at := 0


func _ready() -> void:
	S.load_cfg()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	started_at = Time.get_ticks_msec()

	var vs: VideoStream = null
	if ResourceLoader.exists(VIDEO):
		vs = load(VIDEO) as VideoStream
	if vs != null:
		_play_video(vs)
	else:
		_play_cinematic()

	var hint := Label.new()
	hint.text = "TAP TO SKIP"
	hint.add_theme_font_size_override("font_size", 22)
	hint.modulate = Color(1, 1, 1, 0.35)
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.offset_left = -240.0
	hint.offset_top = -60.0
	hint.offset_right = -30.0
	hint.offset_bottom = -20.0
	add_child(hint)


func _input(event: InputEvent) -> void:
	if Time.get_ticks_msec() - started_at < 800:
		return
	if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		_finish()


func _play_video(vs: VideoStream) -> void:
	var v := VideoStreamPlayer.new()
	v.stream = vs
	v.expand = true
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.finished.connect(_finish)
	add_child(v)
	v.play()


func _play_cinematic() -> void:
	audio = Node.new()
	audio.set_script(load("res://audio.gd"))
	add_child(audio)

	label = Label.new()
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 54)
	label.add_theme_color_override("font_color", Color(0.82, 0.8, 0.76))
	label.modulate.a = 0.0
	add_child(label)

	flash = ColorRect.new()
	flash.color = Color(0.9, 0.95, 1.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.modulate.a = 0.0
	add_child(flash)

	await get_tree().create_timer(1.2).timeout
	var lines := [
		"KASSERINE",
		"02:47 AM",
		"The rain has not stopped for three days.",
		"The streets are empty.",
		"But something is walking tonight.",
		"Do not make a sound.",
	]
	for line in lines:
		if finished:
			return
		await _show_line(line, 2.0)

	if finished:
		return
	var fl := create_tween()
	fl.tween_property(flash, "modulate:a", 1.0, 0.05)
	fl.tween_property(flash, "modulate:a", 0.0, 0.5)
	audio.thunder()
	label.text = "LONG NIGHT"
	label.add_theme_font_size_override("font_size", 120)
	label.add_theme_color_override("font_color", Color(0.75, 0.12, 0.1))
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 1.5)
	tw.tween_interval(2.5)
	tw.tween_property(label, "modulate:a", 0.0, 1.2)
	await tw.finished
	_finish()


func _show_line(text: String, hold: float) -> void:
	label.text = text
	var tw := create_tween()
	tw.tween_property(label, "modulate:a", 1.0, 1.2)
	tw.tween_interval(hold)
	tw.tween_property(label, "modulate:a", 0.0, 0.9)
	await tw.finished


func _finish() -> void:
	if finished:
		return
	finished = true
	get_tree().change_scene_to_file("res://main.tscn")
EOF

# 9) Level: Forward+ look, textures, foreground silhouettes, wires, windows, rubble, ragdoll death
cat > level.gd << 'EOF'
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
EOF

git add -A
git commit -m "Step 10: skeleton character + ragdoll, dogs, Forward+ graphics, settings/about, intro"
git push
echo "OK: pushed, build is starting. Backup of your old files: ~/long-night-backup-step10"

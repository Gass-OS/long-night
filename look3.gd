extends Node
# Look3: Inside / Little Nightmares style 2.5D camera + ground and city behind the buildings.

const KEYS := [
	{"x": -20.0, "yaw": 6.0, "h": 2.2, "dist": 10.5, "fov": 52.0},
	{"x": 26.0, "yaw": 6.0, "h": 2.2, "dist": 10.5, "fov": 52.0},
	{"x": 36.0, "yaw": -12.0, "h": 1.4, "dist": 8.2, "fov": 50.0},
	{"x": 58.0, "yaw": -12.0, "h": 1.6, "dist": 8.6, "fov": 50.0},
	{"x": 68.0, "yaw": 10.0, "h": 3.2, "dist": 11.5, "fov": 55.0},
	{"x": 92.0, "yaw": 10.0, "h": 3.2, "dist": 11.5, "fov": 55.0},
	{"x": 104.0, "yaw": -6.0, "h": 2.0, "dist": 9.5, "fov": 52.0},
	{"x": 130.0, "yaw": -6.0, "h": 2.0, "dist": 9.5, "fov": 52.0},
]

var lv: Node = null
var age := 0
var t := 0.0
var focus := Vector3.ZERO
var focus_ready := false
var shake := 0.0
var last_flash := 0.0


func _ready() -> void:
	process_priority = 1000


func _process(delta: float) -> void:
	t += delta
	var cs := get_tree().current_scene
	if cs == null:
		return
	if cs.get("player") != null and cs.get("env") != null and cs.get("cam") != null and cs.get("weather") != null:
		if lv != cs:
			lv = cs
			age = 0
			focus_ready = false
		age += 1
		if age == 6:
			_fill_world(cs)
		if age == 14:
			_fix_sky()
		_camera(delta)
	else:
		lv = null


# ---------- helpers ----------

func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
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


# ---------- camera ----------

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
	var cam: Camera3D = lv.get("cam")
	var player = lv.get("player")
	if cam == null or player == null:
		return
	var city = get_node_or_null("/root/City")
	var hidden := false
	var anchor := Vector3.ZERO
	var city_shake := 0.0
	if city != null:
		hidden = bool(city.get("hidden"))
		anchor = city.get("hide_anchor")
		city_shake = float(city.get("shake"))

	var p: Vector3 = anchor if hidden else player.global_position
	var face: float = player.get("facing")
	var crouch: bool = player.get("crouching")
	var desired := Vector3(p.x + face * 2.0, p.y + 1.1 - (0.3 if crouch else 0.0), 0.0)
	if not focus_ready:
		focus = desired
		focus_ready = true
	focus.x = lerpf(focus.x, desired.x, 1.0 - exp(-3.0 * delta))
	focus.y = lerpf(focus.y, desired.y, 1.0 - exp(-2.2 * delta))

	var weather = lv.get("weather")
	var fl := 0.0
	if weather != null:
		fl = float(weather.get("flash"))
	if fl > 0.8 and last_flash <= 0.8:
		shake = 0.7
	last_flash = fl
	shake = maxf(0.0, shake - delta * 1.6)
	var total_shake := maxf(shake, city_shake)

	var pr := _params(focus.x)
	var lag := clampf((desired.x - focus.x) * 0.012, -0.05, 0.05)
	var yaw := deg_to_rad(float(pr["yaw"])) + lag + sin(t * 0.3) * 0.012
	var dist := float(pr["dist"]) - (0.5 if crouch else 0.0)
	var h := float(pr["h"]) - (0.3 if crouch else 0.0)
	var drift := Vector3(sin(t * 0.5) * 0.04, sin(t * 0.7) * 0.03, 0.0)
	cam.global_position = focus + Vector3(sin(yaw) * dist, h, cos(yaw) * dist) + drift
	cam.look_at(focus, Vector3.UP)
	cam.rotation.z = -lag * 0.3 + sin(t * 47.0) * total_shake * 0.004
	cam.fov = lerpf(cam.fov, float(pr["fov"]), 1.0 - exp(-1.5 * delta))
	cam.h_offset = sin(t * 43.0) * total_shake * 0.12
	cam.v_offset = cos(t * 37.0) * total_shake * 0.1


# ---------- world fill ----------

func _fill_world(level: Node) -> void:
	var ground_mat: Material
	if level.has_method("_surface_mat"):
		ground_mat = level.call("_surface_mat", Color(0.12, 0.11, 0.1), 0.35, 0.3)
	else:
		ground_mat = _mat(Color(0.05, 0.05, 0.055), 0.4)
	_mi(level, _box(Vector3(400.0, 1.0, 140.0)), ground_mat, Vector3(60.0, -0.58, -72.0))
	_mi(level, _box(Vector3(400.0, 1.0, 14.0)), ground_mat, Vector3(60.0, -0.58, 9.0))

	_row(level, -16.0, 6.0, 4.0, 7.0, 6.0, 14.0, 8.0, 101, Color(0.07, 0.075, 0.09), true)
	_row(level, -32.0, 8.0, 6.0, 12.0, 10.0, 22.0, 12.0, 102, Color(0.05, 0.055, 0.07), true)
	_row(level, -55.0, 10.0, 8.0, 16.0, 16.0, 34.0, 16.0, 103, Color(0.04, 0.045, 0.06), false)

	# Lower the mountains so the sky stays visible with the new camera angle
	for ch in level.get_children():
		if ch is MeshInstance3D and ch.mesh is PrismMesh:
			var sz: Vector3 = (ch.mesh as PrismMesh).size
			ch.scale.y = 0.45
			ch.position.y = -2.0 + sz.y * 0.225


func _row(level: Node, z: float, depth: float, wmin: float, wmax: float, hmin: float, hmax: float, spacing: float, seed_v: int, color: Color, windows: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var mat := _mat(color, 1.0)
	var lit: Array = []
	var x := -70.0
	while x < 190.0:
		var w := rng.randf_range(wmin, wmax)
		var h := rng.randf_range(hmin, hmax)
		var c := Vector3(x, h / 2.0, z + rng.randf_range(-2.0, 2.0))
		_mi(level, _box(Vector3(w, h, depth)), mat, c)
		if windows:
			var cols := int(w / 1.6)
			var rows := int((h - 1.5) / 2.2)
			for ix in cols:
				for iy in rows:
					if rng.randf() < 0.1:
						var wx := c.x - w / 2.0 + (ix + 0.5) * (w / cols)
						lit.append(Transform3D(Basis(), Vector3(wx, 1.8 + iy * 2.2, c.z + depth / 2.0 + 0.02)))
		x += spacing + rng.randf_range(-1.0, 2.0)
	if lit.size() > 0:
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(1.0, 0.75, 0.35)
		wm.emission_enabled = true
		wm.emission = Color(1.0, 0.7, 0.3)
		wm.emission_energy_multiplier = 2.0
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _box(Vector3(0.6, 0.9, 0.05))
		mm.instance_count = lit.size()
		for i in lit.size():
			mm.set_instance_transform(i, lit[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = wm
		level.add_child(mmi)


func _fix_sky() -> void:
	var look2 = get_node_or_null("/root/Look2")
	if look2 == null:
		return
	var sr = look2.get("sky_root")
	if sr == null or not is_instance_valid(sr):
		return
	for c in sr.get_children():
		if c is MeshInstance3D:
			if c.mesh is SphereMesh:
				c.position = Vector3(-22, 23, -100)
			elif c.mesh is QuadMesh:
				var w: float = (c.mesh as QuadMesh).size.x
				if is_equal_approx(w, 36.0):
					c.position = Vector3(-22, 23, -99)
				elif is_equal_approx(w, 260.0):
					c.position = Vector3(0, 22, -98)
				elif is_equal_approx(w, 320.0):
					c.position = Vector3(0, 3, -102)

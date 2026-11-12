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

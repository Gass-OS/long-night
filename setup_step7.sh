#!/data/data/com.termux/files/usr/bin/bash
# Long Night - Step 7: Xbox-style pad, rain + thunder + horror audio, better graphics, new obstacles
set -e
cd ~/long-night

# 1) Better renderer (Vulkan "Mobile") + 4x MSAA, for Adreno 8xx class GPUs
sed -i 's#^renderer/rendering_method=.*#renderer/rendering_method="mobile"#' project.godot
sed -i 's#^renderer/rendering_method.mobile=.*#renderer/rendering_method.mobile="mobile"#' project.godot
sed -i 's#^config/features=.*#config/features=PackedStringArray("4.3", "Mobile")#' project.godot
grep -q "msaa_3d" project.godot || sed -i '/^\[rendering\]/a anti_aliasing/quality/msaa_3d=2' project.godot

# 2) Dog: "alerted" signal (for barking) + glowing eyes (emission, works with bloom)
grep -q "signal alerted" dog.gd || sed -i 's/^signal caught$/signal caught\nsignal alerted/' dog.gd
grep -q "alerted.emit" dog.gd || sed -i 's/^\t\tchasing = true$/\t\tif not chasing:\n\t\t\talerted.emit()\n\t\tchasing = true/' dog.gd
if grep -q "SHADING_MODE_UNSHADED" dog.gd; then
	sed -i 's/^\t\tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED$/\t\tm.emission_enabled = true\n\t\tm.emission = color\n\t\tm.emission_energy_multiplier = 5.0/' dog.gd
fi

# 3) Audio: everything is generated in code (no sound files needed)
cat > audio.gd << 'EOF'
extends Node

var whisper_timer := 18.0
var thunder_p: AudioStreamPlayer
var whisper_p: AudioStreamPlayer
var bark_p: AudioStreamPlayer


func _ready() -> void:
	_add_player(_make_rain(), -15.0, true)
	_add_player(_make_drone(), -13.0, true)
	_add_player(_make_voice(), -19.0, true)
	thunder_p = _add_player(_make_thunder(), -2.0, false)
	whisper_p = _add_player(_make_whisper(), -9.0, false)
	bark_p = _add_player(_make_bark(), -3.0, false)
	bark_p.max_polyphony = 3


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
	# All frequencies are multiples of 1/8 Hz so the 8 s loop is seamless
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
	# Ghostly choir: detuned voices with vocal formants, slow vibrato
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
EOF

# 4) Weather: rain particles + lightning flashes + thunder
cat > weather.gd << 'EOF'
extends Node3D

var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var audio

var rain: GPUParticles3D
var timer := 7.0
var flash := 0.0
var base_sun := 0.7
var base_ambient := 0.55


func _ready() -> void:
	if sun != null:
		base_sun = sun.light_energy
	if env != null:
		base_ambient = env.ambient_light_energy
	_build_rain()


func _build_rain() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.5, 0.012)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.72, 0.8, 0.95, 0.35)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14.0, 0.2, 5.0)
	pm.direction = Vector3(0.12, -1.0, 0.0)
	pm.spread = 2.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 18.0
	pm.gravity = Vector3(0.0, -10.0, 0.0)

	rain = GPUParticles3D.new()
	rain.amount = 1400
	rain.lifetime = 0.55
	rain.preprocess = 0.6
	rain.local_coords = false
	rain.visibility_aabb = AABB(Vector3(-20, -12, -10), Vector3(40, 24, 20))
	rain.process_material = pm
	rain.draw_pass_1 = mesh
	add_child(rain)


func _process(delta: float) -> void:
	if cam != null and rain != null:
		rain.global_position = Vector3(cam.global_position.x, cam.global_position.y + 5.0, 0.0)

	timer -= delta
	if timer <= 0.0:
		timer = randf_range(9.0, 24.0)
		_strike()

	flash = move_toward(flash, 0.0, delta * 3.0)
	if sun != null:
		sun.light_energy = base_sun + flash * 3.5
	if env != null:
		env.ambient_light_energy = base_ambient + flash * 1.2


func _strike() -> void:
	var tw := create_tween()
	tw.tween_property(self, "flash", 1.0, 0.04)
	tw.tween_property(self, "flash", 0.2, 0.08)
	tw.tween_property(self, "flash", 0.9, 0.04)
	await get_tree().create_timer(randf_range(0.4, 1.6)).timeout
	if audio != null:
		audio.thunder()
EOF

# 5) HUD: Xbox-style pad (D-pad cluster left, A / X / B cluster right) + pause menu
cat > hud.gd << 'EOF'
extends CanvasLayer


class Pad extends Control:
	var pressed := {}

	func layout() -> Array:
		var sz := get_viewport_rect().size
		var lc := Vector2(200.0, sz.y - 135.0)
		var rc := Vector2(sz.x - 200.0, sz.y - 205.0)
		return [
			{"id": "left", "pos": lc + Vector2(-84, 0), "r": 74.0, "label": "<", "cap": "", "col": Color(1, 1, 1)},
			{"id": "right", "pos": lc + Vector2(84, 0), "r": 74.0, "label": ">", "cap": "", "col": Color(1, 1, 1)},
			{"id": "jump", "pos": rc + Vector2(0, 104), "r": 78.0, "label": "A", "cap": "JUMP", "col": Color(0.3, 0.85, 0.4)},
			{"id": "push", "pos": rc + Vector2(-108, -8), "r": 70.0, "label": "X", "cap": "PUSH", "col": Color(0.3, 0.55, 1.0)},
			{"id": "down", "pos": rc + Vector2(108, -8), "r": 70.0, "label": "B", "cap": "DOWN", "col": Color(0.95, 0.3, 0.3)},
		]

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		for b in layout():
			var p: Vector2 = b["pos"]
			var r: float = b["r"]
			var col: Color = b["col"]
			var down: bool = pressed.get(b["id"], false)
			draw_circle(p, r, Color(col.r, col.g, col.b, 0.5 if down else 0.16))
			draw_arc(p, r, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.9 if down else 0.5), 4.0, true)
			var label: String = b["label"]
			var cap: String = b["cap"]
			var txt := Color(1, 1, 1, 0.95 if down else 0.6)
			if cap == "":
				draw_string(font, p + Vector2(-r, 22), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 64, txt)
			else:
				draw_string(font, p + Vector2(-r, 10), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 52, txt)
				draw_string(font, p + Vector2(-r, 46), cap, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 22, txt)


var player
var touches := {}
var pad: Pad
var pause_panel: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 10
	get_tree().set_quit_on_go_back(false)
	pad = Pad.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pad)
	_build_pause_button()
	_build_pause_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if get_tree().paused:
			_resume()
		else:
			_pause()


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touches[event.index] = event.position
		else:
			touches.erase(event.index)
		_update_touch()
	elif event is InputEventScreenDrag:
		touches[event.index] = event.position
		_update_touch()


func _update_touch() -> void:
	if player == null:
		return
	var size := get_viewport().get_visible_rect().size
	var specs: Array = pad.layout()
	var down := {}
	for p in touches.values():
		if p.y < size.y * 0.16:
			continue  # top strip is for the pause button
		var best := ""
		var best_d := 1000000.0
		for b in specs:
			var d: float = (b["pos"] as Vector2).distance_to(p) / float(b["r"])
			if d < 1.35 and d < best_d:
				best = b["id"]
				best_d = d
		if best != "":
			down[best] = true
	player.touch_left = down.get("left", false)
	player.touch_right = down.get("right", false)
	player.touch_jump = down.get("jump", false)
	player.touch_push = down.get("push", false)
	player.touch_down = down.get("down", false)
	pad.pressed = down
	pad.queue_redraw()


func _build_pause_button() -> void:
	var b := Button.new()
	b.text = "II"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 40)
	b.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	b.offset_left = -120.0
	b.offset_top = 20.0
	b.offset_right = -20.0
	b.offset_bottom = 100.0
	b.pressed.connect(_pause)
	add_child(b)


func _build_pause_panel() -> void:
	pause_panel = Control.new()
	pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.visible = false
	add_child(pause_panel)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_panel.add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	center.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	box.add_child(title)

	_menu_button(box, "RESUME", _resume)
	_menu_button(box, "RESTART", _restart)
	_menu_button(box, "MAIN MENU", _to_menu)


func _menu_button(parent: Control, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 90)
	b.add_theme_font_size_override("font_size", 38)
	b.pressed.connect(cb)
	parent.add_child(b)


func _pause() -> void:
	get_tree().paused = true
	pause_panel.visible = true
	touches.clear()
	_update_touch()


func _resume() -> void:
	get_tree().paused = false
	pause_panel.visible = false


func _restart() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")
EOF

# 6) Level: lamps, windows, mountains, puddles, barrels, pit, climb wall, moving platform, 3rd dog
cat > level.gd << 'EOF'
extends Node3D

const DOOR_CLOSED_Y := 1.5
const DOOR_OPEN_Y := 4.7

const VIGNETTE := """
shader_type canvas_item;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float v = smoothstep(0.30, 0.85, length(uv * vec2(1.15, 1.0)));
	float g = fract(sin(dot(UV * vec2(1280.0, 720.0) + vec2(TIME * 37.0, TIME * 11.0), vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(0.0, 0.0, 0.0, clamp(v * 0.7 + g * 0.06, 0.0, 1.0));
}
"""

var player: CharacterBody3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var audio
var weather

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
var flick_t := 0.0

var checkpoint := Vector3(0.0, 0.1, 0.0)
var checkpoint_xs: Array[float] = [28.5, 38.5, 66.8, 81.6, 100.8]
var dead := false
var finished := false
var fade: ColorRect
var msg_label: Label


func _ready() -> void:
	audio = Node.new()
	audio.set_script(load("res://audio.gd"))
	add_child(audio)

	_setup_environment()
	_build_level()
	_build_puzzle()
	_build_course()
	_build_decor()

	player = CharacterBody3D.new()
	player.set_script(load("res://player.gd"))
	player.position = checkpoint
	add_child(player)

	cam = Camera3D.new()
	cam.position = Vector3(0, 2.5, 9)
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
	env.ambient_light_color = Color(0.32, 0.38, 0.5)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color(0.07, 0.09, 0.13)
	env.fog_density = 0.025
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.1
	env.glow_hdr_threshold = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.75
	env.adjustment_contrast = 1.08

	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -25, 0)
	sun.light_energy = 0.7
	sun.light_color = Color(0.6, 0.7, 1.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)


func _add_box(pos: Vector3, size: Vector3, color: Color, solid := true, rough := 0.85) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mesh.material_override = mat
	body.add_child(mesh)
	if solid:
		var col := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		col.shape = bs
		body.add_child(col)
	add_child(body)


func _ground(x0: float, x1: float) -> void:
	_add_box(Vector3((x0 + x1) / 2.0, -0.5, 0.0), Vector3(x1 - x0, 1.0, 4.0), Color(0.3, 0.26, 0.22), true, 0.35)


func _build_level() -> void:
	# Ground with two pits (64 to 66.4 and 92 to 100)
	_ground(-20.0, 64.0)
	_ground(66.4, 92.0)
	_ground(100.0, 114.0)
	# Jump practice
	_add_box(Vector3(6, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(9, 1.2, 0), Vector3(2, 0.4, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(12.5, 0.4, 0), Vector3(1.5, 0.8, 1.5), Color(0.45, 0.3, 0.2))
	# Low vent after the door: crouch (DOWN) to crawl under it
	_add_box(Vector3(34, 1.5, 0), Vector3(6, 1.0, 4), Color(0.2, 0.2, 0.24))
	# Safe platforms in the dog zone
	_add_box(Vector3(40.5, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))
	_add_box(Vector3(50.5, 0.5, 0), Vector3(2, 1, 2), Color(0.4, 0.34, 0.28))

	# Background buildings
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var buildings: Array = []
	for i in range(26):
		var h := rng.randf_range(4.0, 9.0)
		var w := rng.randf_range(3.0, 5.0)
		var c := Vector3(i * 5.0 - 5.0, h / 2.0, -5.0 - rng.randf_range(0.0, 3.0))
		_add_box(c, Vector3(w, h, 2.0), Color(0.16, 0.15, 0.17), false)
		buildings.append([c, w, h])
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
	_add_multimesh(lit, lit_mat)

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.03, 0.04, 0.06)
	_add_multimesh(dark, dark_mat)


func _add_multimesh(transforms: Array, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.65, 0.04)
	mm.mesh = bm
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	add_child(mi)


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
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.2)
	mat.roughness = 0.9
	mesh.material_override = mat
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
	# Climb: push the crate against the wall, jump on it, then on the wall
	_add_crate(Vector3(72.0, 0.52, 0.0))
	_add_box(Vector3(80.0, 1.0, 0.0), Vector3(2.0, 2.0, 2.0), Color(0.28, 0.27, 0.3))

	# Moving platform over the big pit
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

	# Death / ending fade
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


func _on_dog_alerted() -> void:
	if audio != null:
		audio.bark()


func _on_caught() -> void:
	if dead or finished:
		return
	dead = true
	player.set_physics_process(false)
	msg_label.text = "YOU DIED"
	msg_label.add_theme_color_override("font_color", Color(0.7, 0.1, 0.1))
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
			_on_caught()


func _process(delta: float) -> void:
	if player != null and cam != null:
		var target := Vector3(player.position.x, player.position.y + 2.5, 9.0)
		cam.position = cam.position.lerp(target, clampf(delta * 4.0, 0.0, 1.0))

	# Street lamps: even ones hum, odd ones stutter
	flick_t += delta
	for i in lamp_lights.size():
		var l: OmniLight3D = lamp_lights[i]
		var base: float = lamp_base[i]
		if i % 2 == 0:
			l.light_energy = base * (0.95 + 0.05 * sin(flick_t * 9.0 + i))
		else:
			var n := sin(flick_t * 23.0 + i * 5.0) * sin(flick_t * 3.7 + i)
			l.light_energy = base * (0.1 if n > 0.7 else 1.0)
EOF

git add project.godot dog.gd audio.gd weather.gd hud.gd level.gd
git commit -m "Step 7: pad, rain, thunder, audio, graphics, new obstacles"
git push
echo "OK: pushed, build is starting"

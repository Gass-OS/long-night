#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail
cd ~/long-night

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/long-night-backups/step9-$STAMP"
mkdir -p "$BACKUP"

for f in weather.gd level.gd menu.gd intro.gd project.godot .github/workflows/build.yml; do
    cp -a "$f" "$BACKUP/"
done

echo "Backup: $BACKUP"

# ------------------------------------------------
# MODERATE RAIN
# ------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path("weather.gd")
s = p.read_text()

replacements = {
    "mesh.size = Vector3(0.012, 0.5, 0.012)":
        "mesh.size = Vector3(0.008, 0.34, 0.008)",
    "Color(0.72, 0.8, 0.95, 0.35)":
        "Color(0.72, 0.8, 0.95, 0.19)",
    "Vector3(14.0, 0.2, 5.0)":
        "Vector3(8.0, 0.2, 1.2)",
    "pm.spread = 2.0":
        "pm.spread = 1.5",
    "pm.initial_velocity_min = 15.0":
        "pm.initial_velocity_min = 11.0",
    "pm.initial_velocity_max = 18.0":
        "pm.initial_velocity_max = 14.0",
    "rain.amount = 1400":
        "rain.amount = 420",
    "rain.lifetime = 0.55":
        "rain.lifetime = 0.7",
    "rain.preprocess = 0.6":
        "rain.preprocess = 0.2",
    "rain.global_position = Vector3(cam.global_position.x, cam.global_position.y + 5.0, 0.0)":
        "rain.global_position = Vector3(cam.global_position.x, cam.global_position.y + 4.0, 3.5)"
}

for old, new in replacements.items():
    if old not in s:
        raise SystemExit("Missing expected rain setting: " + old)
    s = s.replace(old, new, 1)

p.write_text(s)
print("Rain changed to medium intensity")
PY

# ------------------------------------------------
# CHAPTER 1: CINEMATIC 2.5D CAMERA
# ------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path("level.gd")
s = p.read_text()

old = "cam.position = Vector3(0, 2.5, 9)\n\tadd_child(cam)\n\tcam.make_current()"
new = """cam.projection = Camera3D.PROJECTION_ORTHOGONAL
\tcam.size = 9.0
\tcam.position = Vector3(0, 2.5, 12)
\tadd_child(cam)
\tcam.make_current()"""

if old not in s:
    raise SystemExit("Chapter 1 camera setup not found")

s = s.replace(old, new, 1)

old = "var target := Vector3(player.position.x, player.position.y + 2.5, 9.0)"
new = "var target := Vector3(player.position.x, player.position.y + 2.5, 12.0)"

if old not in s:
    raise SystemExit("Chapter 1 camera follow not found")

s = s.replace(old, new, 1)
p.write_text(s)
print("Chapter 1 now uses an orthographic side camera")
PY

# ------------------------------------------------
# CHAPTER 2: ABANDONED SCHOOL
# ------------------------------------------------

cat > stage2.gd <<'GODOT'
extends Node3D

var player: CharacterBody3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var audio
var weather

var plate: Area3D
var plate_mat: StandardMaterial3D
var gate: AnimatableBody3D
var dog: CharacterBody3D
var exit_area: Area3D

var fade: ColorRect
var message: Label
var objective: Label
var dead := false
var finished := false
var checkpoint := Vector3(0, 0.1, 0)


func _ready() -> void:
    audio = Node.new()
    audio.set_script(load("res://audio.gd"))
    add_child(audio)

    _environment()
    _background()
    _course()

    player = CharacterBody3D.new()
    player.set_script(load("res://player.gd"))
    player.position = checkpoint
    add_child(player)
    _make_silhouette(player.visual)

    cam = Camera3D.new()
    cam.projection = Camera3D.PROJECTION_ORTHOGONAL
    cam.size = 8.5
    cam.position = Vector3(0, 2.7, 12)
    add_child(cam)
    cam.make_current()

    dog = CharacterBody3D.new()
    dog.set_script(load("res://dog.gd"))
    dog.target = player
    dog.position = Vector3(38, 0.05, 0)
    dog.left_x = 35
    dog.right_x = 43
    dog.caught.connect(_caught)
    dog.alerted.connect(_dog_alerted)
    add_child(dog)

    exit_area = Area3D.new()
    exit_area.position = Vector3(79, 0, 0)
    var ec := CollisionShape3D.new()
    var es := BoxShape3D.new()
    es.size = Vector3(2, 4, 3)
    ec.shape = es
    ec.position.y = 2
    exit_area.add_child(ec)
    add_child(exit_area)
    exit_area.body_entered.connect(_exit)

    weather = Node3D.new()
    weather.set_script(load("res://weather.gd"))
    weather.cam = cam
    weather.sun = sun
    weather.env = env
    weather.audio = audio
    add_child(weather)

    _interface()


func _mat(c: Color, emission := false) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = c
    m.roughness = 0.9
    if emission:
        m.emission_enabled = true
        m.emission = c
        m.emission_energy_multiplier = 1.4
    return m


func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color, solid := false) -> Node3D:
    var body: Node3D
    if solid:
        body = StaticBody3D.new()
    else:
        body = Node3D.new()

    body.position = pos
    var mesh := MeshInstance3D.new()
    var bm := BoxMesh.new()
    bm.size = size
    mesh.mesh = bm
    mesh.material_override = _mat(color)
    body.add_child(mesh)

    if solid:
        var col := CollisionShape3D.new()
        var shape := BoxShape3D.new()
        shape.size = size
        col.shape = shape
        body.add_child(col)

    parent.add_child(body)
    return body


func _environment() -> void:
    env = Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.012, 0.016, 0.025)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.28, 0.31, 0.4)
    env.ambient_light_energy = 0.55
    env.fog_enabled = true
    env.fog_light_color = Color(0.035, 0.045, 0.065)
    env.fog_density = 0.012
    env.glow_enabled = true
    env.glow_intensity = 0.45
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)

    sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-35, -25, 0)
    sun.light_color = Color(0.55, 0.62, 0.78)
    sun.light_energy = 0.65
    sun.shadow_enabled = true
    add_child(sun)


func _background() -> void:
    # Distant mountain silhouettes
    for i in range(7):
        var mountain := MeshInstance3D.new()
        var prism := PrismMesh.new()
        prism.size = Vector3(24, 9 + float(i % 3) * 3, 3)
        mountain.mesh = prism
        mountain.material_override = _mat(Color(0.025, 0.032, 0.05))
        mountain.position = Vector3(i * 19 - 15, 7, -30)
        add_child(mountain)

    # Far school buildings
    for i in range(13):
        var h := 5.0 + float((i * 7) % 5)
        var w := 5.0 + float(i % 3)
        _box(self, Vector3(i * 7.0 - 8, h / 2.0, -15),
            Vector3(w, h, 2.0), Color(0.055, 0.06, 0.08))

    # Foreground silhouettes create depth
    for i in range(12):
        var x := i * 7.5 - 5.0
        _box(self, Vector3(x, 3.0, -5.5),
            Vector3(0.18, 6.0, 0.3), Color(0.018, 0.022, 0.03))


func _floor(a: float, b: float) -> void:
    _box(self, Vector3((a + b) * 0.5, -0.5, 0),
        Vector3(b - a, 1.0, 4.0), Color(0.16, 0.15, 0.15), true)


func _course() -> void:
    # Broken school corridor and gaps
    _floor(-10, 24)
    _floor(26, 48)
    _floor(51, 62)
    _floor(66, 84)

    # School walls and windows
    _box(self, Vector3(7, 4.2, -3.0), Vector3(15, 8, 0.5),
        Color(0.07, 0.075, 0.085))
    _box(self, Vector3(35, 3.5, -3.0), Vector3(13, 7, 0.5),
        Color(0.065, 0.07, 0.08))
    _box(self, Vector3(59, 4.0, -3.0), Vector3(15, 8, 0.5),
        Color(0.07, 0.065, 0.07))

    for x in [2.0, 10.0, 31.0, 39.0, 56.0, 72.0]:
        _box(self, Vector3(x, 2.7, -2.65), Vector3(1.2, 1.8, 0.08),
            Color(0.38, 0.29, 0.16), false)

    # First puzzle: push the crate onto the pressure plate
    _crate(Vector3(8.5, 0.52, 0))
    plate = Area3D.new()
    plate.position = Vector3(14.0, 0, 0)
    var pc := CollisionShape3D.new()
    var ps := BoxShape3D.new()
    ps.size = Vector3(1.8, 0.4, 1.4)
    pc.shape = ps
    pc.position.y = 0.2
    plate.add_child(pc)

    var pm := MeshInstance3D.new()
    var pb := BoxMesh.new()
    pb.size = Vector3(1.8, 0.08, 1.8)
    pm.mesh = pb
    plate_mat = _mat(Color(0.65, 0.08, 0.06), true)
    pm.material_override = plate_mat
    pm.position.y = 0.04
    plate.add_child(pm)
    add_child(plate)

    # Gate opened by the pressure plate
    gate = AnimatableBody3D.new()
    gate.position = Vector3(20, 2.0, 0)
    var gm := MeshInstance3D.new()
    var gb := BoxMesh.new()
    gb.size = Vector3(0.45, 4.0, 4.0)
    gm.mesh = gb
    gm.material_override = _mat(Color(0.09, 0.09, 0.11))
    gate.add_child(gm)
    var gc := CollisionShape3D.new()
    var gs := BoxShape3D.new()
    gs.size = Vector3(0.45, 4.0, 4.0)
    gc.shape = gs
    gate.add_child(gc)
    add_child(gate)

    # Low collapsed ceiling: crouch to pass
    _box(self, Vector3(30, 1.55, 0), Vector3(7, 1.0, 4),
        Color(0.12, 0.11, 0.12), true)

    # Broken furniture and classroom debris
    _box(self, Vector3(5, 0.65, -1.0), Vector3(2.2, 0.25, 0.6),
        Color(0.16, 0.10, 0.07))
    _box(self, Vector3(55, 0.25, -1.2), Vector3(2.5, 0.5, 0.8),
        Color(0.12, 0.09, 0.08))

    # Narrow jump gap and broken floor
    _box(self, Vector3(49.5, -1.2, 0), Vector3(3.0, 0.3, 4),
        Color(0.025, 0.025, 0.03))

    # A distant red emergency light
    var light := OmniLight3D.new()
    light.position = Vector3(70, 3, 0)
    light.light_color = Color(0.65, 0.08, 0.05)
    light.light_energy = 1.2
    light.omni_range = 7
    add_child(light)


func _crate(pos: Vector3) -> void:
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
    mesh.material_override = _mat(Color(0.22, 0.15, 0.11))
    rb.add_child(mesh)

    var col := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = Vector3(1, 1, 1)
    col.shape = shape
    rb.add_child(col)
    add_child(rb)


func _make_silhouette(node: Node) -> void:
    var dark := _mat(Color(0.025, 0.025, 0.03))
    for child in node.get_children():
        if child is MeshInstance3D:
            child.material_override = dark
        else:
            _make_silhouette(child)


func _interface() -> void:
    var hud := CanvasLayer.new()
    hud.layer = 15
    add_child(hud)

    objective = Label.new()
    objective.text = "CHAPTER 02  //  THE ABANDONED SCHOOL\nFind a way into the basement"
    objective.position = Vector2(35, 28)
    objective.add_theme_font_size_override("font_size", 24)
    objective.add_theme_color_override("font_color", Color(0.83, 0.82, 0.76))
    hud.add_child(objective)

    var controls := CanvasLayer.new()
    controls.layer = 10
    controls.set_script(load("res://hud.gd"))
    controls.player = player
    add_child(controls)

    var overlay := CanvasLayer.new()
    overlay.layer = 25
    add_child(overlay)

    fade = ColorRect.new()
    fade.color = Color.BLACK
    fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    fade.modulate.a = 0
    overlay.add_child(fade)

    message = Label.new()
    message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    message.add_theme_font_size_override("font_size", 62)
    message.add_theme_color_override("font_color", Color(0.83, 0.81, 0.77))
    message.modulate.a = 0
    overlay.add_child(message)


func _dog_alerted() -> void:
    if audio != null:
        audio.bark()


func _physics_process(delta: float) -> void:
    if dead or finished:
        return

    if plate != null and gate != null:
        var pressed := false
        for body in plate.get_overlapping_bodies():
            if body == player or body.is_in_group("crate"):
                pressed = true
                break

        var target_y := 5.0 if pressed else 2.0
        gate.position.y = move_toward(gate.position.y, target_y, delta * 3.0)

        if pressed:
            plate_mat.albedo_color = Color(0.12, 0.55, 0.22)
            plate_mat.emission = Color(0.12, 0.55, 0.22)
            objective.text = "CHAPTER 02  //  THE ABANDONED SCHOOL\nThe gate is open. Find the basement."
        else:
            objective.text = "CHAPTER 02  //  THE ABANDONED SCHOOL\nPush the crate onto the red pressure plate."

    if player.position.y < -5:
        _caught()


func _process(delta: float) -> void:
    if player == null or cam == null or dead or finished:
        return

    var target := Vector3(player.position.x, player.position.y + 2.5, 12)
    cam.position = cam.position.lerp(target, clampf(delta * 3.5, 0, 1))

    if player.position.x > 25:
        objective.text = "CRAWL UNDER THE COLLAPSED CEILING"
    if player.position.x > 33:
        objective.text = "STAY LOW. SOMETHING IS HUNTING HERE."
    if player.position.x > 47:
        objective.text = "JUMP OVER THE BROKEN FLOOR"
    if player.position.x > 65:
        objective.text = "THE BASEMENT IS CLOSE..."


func _caught() -> void:
    if dead or finished:
        return
    dead = true
    player.set_physics_process(false)

    message.text = "IT FOUND YOU"
    var tw := create_tween()
    tw.tween_property(fade, "modulate:a", 1.0, 0.55)
    tw.parallel().tween_property(message, "modulate:a", 1.0, 0.7)
    await tw.finished
    await get_tree().create_timer(1.0).timeout

    player.respawn(checkpoint)
    if dog != null:
        dog.reset_state()
    player.set_physics_process(true)
    dead = false

    var back := create_tween()
    back.tween_property(fade, "modulate:a", 0.0, 0.7)
    back.parallel().tween_property(message, "modulate:a", 0.0, 0.4)


func _exit(body: Node3D) -> void:
    if body != player or finished or dead:
        return
    finished = true
    player.set_physics_process(false)

    message.text = "THE BASEMENT\nSOMETHING IS DOWN THERE"
    var tw := create_tween()
    tw.tween_property(fade, "modulate:a", 1.0, 1.1)
    tw.parallel().tween_property(message, "modulate:a", 1.0, 1.5)
    await tw.finished
    await get_tree().create_timer(3.0).timeout
    get_tree().change_scene_to_file("res://menu.tscn")
GODOT

cat > stage2.tscn <<'SCENE'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://stage2.gd" id="1"]

[node name="Stage2" type="Node3D"]
script = ExtResource("1")
SCENE

# ------------------------------------------------
# MENU: CHAPTER SELECT
# ------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path("menu.gd")
s = p.read_text()

old = '_button(box, "PLAY", _on_play)'
new = '''_button(box, "CHAPTER 1", _on_play)
\t_button(box, "CHAPTER 2  -  THE SCHOOL", _on_chapter_two)'''

if old not in s:
    raise SystemExit("Menu PLAY button not found")

s = s.replace(old, new, 1)

marker = "func _on_quit() -> void:\n"
insert = '''func _on_chapter_two() -> void:
\tget_tree().change_scene_to_file("res://stage2.tscn")


'''
if marker not in s:
    raise SystemExit("Menu quit function not found")

s = s.replace(marker, insert + marker, 1)
p.write_text(s)
print("Chapter selection added")
PY

# ------------------------------------------------
# NATURAL NEURAL NARRATOR: PIPER
# ------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path(".github/workflows/build.yml")
s = p.read_text()

start = s.find("      - name: Generate 1980 story narration")
end = s.find("      - name: Import project", start)

if start < 0 or end < 0:
    raise SystemExit("Narration workflow section not found")

block = """      - name: Generate natural 1980 story narration
        run: |
          python3 -m pip install --user piper-tts
          mkdir -p assets/audio
          MODEL=assets/audio/en_US-lessac-medium.onnx
          CONFIG=assets/audio/en_US-lessac-medium.onnx.json
          wget -q 'https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx' -O "$MODEL"
          wget -q 'https://huggingface.co/rhasspy/piper-voices/resolve/main/en/en_US/lessac/medium/en_US-lessac-medium.onnx.json' -O "$CONFIG"
          echo "I still remember Kasserine in 1980. A quiet city beneath the mountains. A place where everyone knew their neighbours. But when the lights went out, strange things began happening after midnight. People disappeared. Doors were left open. And the old streets fell silent. Nobody believed the warnings. Until that night..." | $HOME/.local/bin/piper --model "$MODEL" --config "$CONFIG" --length_scale 1.08 --noise_scale 0.667 --noise_w 0.8 --sentence_silence 0.35 --output_file assets/audio/intro_narration.wav

"""

s = s[:start] + block + s[end:]
p.write_text(s)
print("Piper neural narrator configured")
PY

# ------------------------------------------------
# CHECKS
# ------------------------------------------------

echo
echo "===== STEP 9 FILES ====="
ls -lh weather.gd level.gd stage2.gd stage2.tscn menu.gd

echo
echo "===== CHAPTER SELECT ====="
grep -n -E 'CHAPTER|_on_chapter_two' menu.gd

echo
echo "===== RAIN ====="
grep -n -E 'rain.amount|rain.lifetime|initial_velocity|albedo_color' weather.gd

echo
echo "===== NARRATOR ====="
grep -A10 'Generate natural 1980' .github/workflows/build.yml

echo
echo "===== DIFF CHECK ====="
git diff --check

echo
echo "===== WORKING TREE ====="
git status --short

echo
echo "STEP 9 PATCH READY"

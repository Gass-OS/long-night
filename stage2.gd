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
    _corridor_lighting()

    player = CharacterBody3D.new()
    player.set_script(load("res://player.gd"))
    player.position = checkpoint
    add_child(player)
    _add_player_fill_light()

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


func _add_player_fill_light() -> void:
    var light := OmniLight3D.new()
    light.position = Vector3(0, 1.5, 2.0)
    light.light_color = Color(0.72, 0.78, 0.88)
    light.light_energy = 1.25
    light.omni_range = 7.5
    light.shadow_enabled = false
    player.add_child(light)


func _corridor_lighting() -> void:
    for x in [0.0, 12.0, 27.0, 40.0, 57.0, 72.0]:
        var light := OmniLight3D.new()
        light.position = Vector3(x, 3.8, -0.2)
        light.light_color = Color(0.88, 0.76, 0.58)
        light.light_energy = 1.15
        light.omni_range = 8.5
        light.shadow_enabled = false
        add_child(light)

        var bulb := MeshInstance3D.new()
        var mesh := SphereMesh.new()
        mesh.radius = 0.11
        mesh.height = 0.22
        bulb.mesh = mesh

        var material := StandardMaterial3D.new()
        material.albedo_color = Color(1.0, 0.78, 0.48)
        material.emission_enabled = true
        material.emission = Color(1.0, 0.65, 0.32)
        material.emission_energy_multiplier = 2.0
        bulb.material_override = material
        bulb.position = light.position
        add_child(bulb)


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
    env.ambient_light_color = Color(0.42, 0.44, 0.52)
    env.ambient_light_energy = 0.85
    env.fog_enabled = true
    env.fog_light_color = Color(0.035, 0.045, 0.065)
    env.fog_density = 0.006
    env.glow_enabled = true
    env.glow_intensity = 0.45
    env.tonemap_mode = Environment.TONE_MAPPER_FILMIC

    var we := WorldEnvironment.new()
    we.environment = env
    add_child(we)

    sun = DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-35, -25, 0)
    sun.light_color = Color(0.65, 0.70, 0.82)
    sun.light_energy = 0.90
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

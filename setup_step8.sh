#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

cd ~/long-night

STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/long-night-backups/step8-$STAMP"

mkdir -p "$BACKUP"
cp -a project.godot "$BACKUP/"
cp -a .github/workflows/build.yml "$BACKUP/"

echo "Backup created: $BACKUP"

# --------------------------------------------------
# 1. INTRO SCRIPT
# --------------------------------------------------

cat > intro.gd <<'GODOT'
extends Control

var transitioning := false
var narration_player: AudioStreamPlayer
var story_label: Label
var title_label: Label
var boot_label: Label
var progress_bar: ProgressBar
var skip_button: Button

const CRT_SHADER := """
shader_type canvas_item;

void fragment() {
    float scan = 0.96 + 0.04 * sin(UV.y * 720.0 * 3.14159);
    float noise = fract(
        sin(dot(
            UV * vec2(1280.0, 720.0) + vec2(TIME * 17.0, TIME * 31.0),
            vec2(12.9898, 78.233)
        )) * 43758.5453
    );

    float vignette = smoothstep(
        0.85, 0.20,
        length((UV - vec2(0.5)) * vec2(1.2, 1.0))
    );

    float alpha = clamp(0.07 + noise * 0.045 + (1.0 - vignette) * 0.12, 0.0, 0.22);
    COLOR = vec4(vec3(0.0), alpha * scan);
}
"""


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().paused = false
    get_tree().set_quit_on_go_back(true)
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

    _build_screen()
    call_deferred("_play_sequence")


func _build_screen() -> void:
    var bg := ColorRect.new()
    bg.color = Color(0.003, 0.004, 0.009)
    bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(bg)

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var column := VBoxContainer.new()
    column.alignment = BoxContainer.ALIGNMENT_CENTER
    column.add_theme_constant_override("separation", 24)
    center.add_child(column)

    boot_label = Label.new()
    boot_label.text = "GASS OS // INITIALIZING"
    boot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    boot_label.add_theme_font_size_override("font_size", 27)
    boot_label.add_theme_color_override("font_color", Color(0.55, 0.72, 0.65))
    column.add_child(boot_label)

    progress_bar = ProgressBar.new()
    progress_bar.custom_minimum_size = Vector2(440, 12)
    progress_bar.show_percentage = false
    column.add_child(progress_bar)

    title_label = Label.new()
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title_label.add_theme_font_size_override("font_size", 64)
    title_label.add_theme_color_override("font_color", Color(0.83, 0.81, 0.76))
    title_label.modulate.a = 0.0
    column.add_child(title_label)

    story_label = Label.new()
    story_label.custom_minimum_size = Vector2(1000, 150)
    story_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    story_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    story_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    story_label.add_theme_font_size_override("font_size", 29)
    story_label.add_theme_color_override("font_color", Color(0.82, 0.80, 0.75))
    story_label.modulate.a = 0.0
    column.add_child(story_label)

    var shader := Shader.new()
    shader.code = CRT_SHADER

    var overlay := ColorRect.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var shader_material := ShaderMaterial.new()
    shader_material.shader = shader
    overlay.material = shader_material
    add_child(overlay)

    skip_button = Button.new()
    skip_button.text = "SKIP INTRO  »"
    skip_button.custom_minimum_size = Vector2(190, 58)
    skip_button.anchor_left = 1.0
    skip_button.anchor_right = 1.0
    skip_button.anchor_top = 1.0
    skip_button.anchor_bottom = 1.0
    skip_button.offset_left = -220
    skip_button.offset_right = -30
    skip_button.offset_top = -90
    skip_button.offset_bottom = -32
    skip_button.pressed.connect(_skip_intro)
    add_child(skip_button)

    narration_player = AudioStreamPlayer.new()
    narration_player.volume_db = -2.0
    add_child(narration_player)


func _play_sequence() -> void:
    # OLD COMPUTER BOOT
    boot_label.text = "GASS OS // SYSTEM STARTUP"

    for i in range(101):
        if transitioning:
            return

        progress_bar.value = i
        if i < 25:
            boot_label.text = "CHECKING MEMORY..."
        elif i < 55:
            boot_label.text = "LOADING ARCHIVE..."
        elif i < 85:
            boot_label.text = "RESTORING KASSERINE RECORDS..."
        else:
            boot_label.text = "SIGNAL FOUND // 1980"

        await get_tree().create_timer(0.035).timeout

    await get_tree().create_timer(0.7).timeout
    if transitioning:
        return

    # PRODUCTION CARD
    boot_label.text = ""
    progress_bar.visible = false

    title_label.text = "A GASS OS PRODUCTION"
    await _show_title()
    await get_tree().create_timer(1.3).timeout
    if transitioning:
        return
    await _hide_title()

    # FILM TITLE
    title_label.text = "KASSERINE CITY"
    await _show_title()
    await get_tree().create_timer(1.0).timeout
    if transitioning:
        return

    title_label.text = "TUNISIA  //  1980"
    await get_tree().create_timer(1.8).timeout
    if transitioning:
        return
    await _hide_title()

    # NARRATION
    await _start_story()


func _show_title() -> void:
    var tw := create_tween()
    tw.tween_property(title_label, "modulate:a", 1.0, 1.2)
    await tw.finished


func _hide_title() -> void:
    var tw := create_tween()
    tw.tween_property(title_label, "modulate:a", 0.0, 0.9)
    await tw.finished


func _start_story() -> void:
    if transitioning:
        return

    title_label.text = "AN OLD STORY"

    var tw := create_tween()
    tw.tween_property(title_label, "modulate:a", 1.0, 0.8)
    await tw.finished

    if transitioning:
        return

    var voice := load("res://assets/audio/intro_narration.wav")
    if voice is AudioStream:
        narration_player.stream = voice
        narration_player.play()

    var lines := [
        "I still remember Kasserine in 1980...",
        "A quiet city beneath the mountains. A place where everyone knew their neighbours.",
        "But when the lights went out, strange things began happening after midnight.",
        "People disappeared. Doors were left open. And the old streets fell silent.",
        "Nobody believed the warnings. Until that night..."
    ]

    for line in lines:
        if transitioning:
            return

        story_label.text = line
        story_label.modulate.a = 0.0

        var caption_tween := create_tween()
        caption_tween.tween_property(story_label, "modulate:a", 1.0, 0.65)
        await caption_tween.finished

        await get_tree().create_timer(3.2).timeout

        if transitioning:
            return

        var fade_tween := create_tween()
        fade_tween.tween_property(story_label, "modulate:a", 0.0, 0.45)
        await fade_tween.finished

    await get_tree().create_timer(1.0).timeout
    _finish_intro()


func _skip_intro() -> void:
    _finish_intro()


func _finish_intro() -> void:
    if transitioning:
        return

    transitioning = true

    if narration_player != null:
        narration_player.stop()

    var fade := ColorRect.new()
    fade.color = Color.BLACK
    fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    fade.modulate.a = 0.0
    fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(fade)

    var tw := create_tween()
    tw.tween_property(fade, "modulate:a", 1.0, 1.0)
    await tw.finished

    get_tree().change_scene_to_file("res://menu.tscn")
GODOT

# --------------------------------------------------
# 2. INTRO SCENE
# --------------------------------------------------

cat > intro.tscn <<'SCENE'
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
SCENE

# --------------------------------------------------
# 3. SET INTRO AS FIRST SCENE
# --------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path("project.godot")
s = p.read_text()

old = 'run/main_scene="res://menu.tscn"'
new = 'run/main_scene="res://intro.tscn"'

if old not in s:
    raise SystemExit("ERROR: expected menu main_scene setting was not found")

s = s.replace(old, new, 1)
p.write_text(s)
print("Startup scene changed to intro.tscn")
PY

# --------------------------------------------------
# 4. ADD REAL NARRATOR VOICE TO CI BUILD
# --------------------------------------------------

python3 - <<'PY'
from pathlib import Path

p = Path(".github/workflows/build.yml")
s = p.read_text()

marker = "      - name: Import project\n"

if "Generate 1980 story narration" in s:
    print("Narration build step already exists")
else:
    if marker not in s:
        raise SystemExit("ERROR: could not find Import project step")

    block = """      - name: Generate 1980 story narration
        run: |
          sudo apt-get update
          sudo apt-get install -y espeak-ng
          mkdir -p assets/audio
          espeak-ng -v en-us+m3 -s 126 -p 30 -a 165 -w assets/audio/intro_narration.wav "I still remember Kasserine in 1980. A quiet city beneath the mountains. A place where everyone knew their neighbours. But when the lights went out, strange things began happening after midnight. People disappeared. Doors were left open. And the old streets fell silent. Nobody believed the warnings. Until that night..."

"""

    s = s.replace(marker, block + marker, 1)
    p.write_text(s)
    print("Narrator generation added to GitHub Actions")

PY

mkdir -p assets/audio

# --------------------------------------------------
# 5. CHECKS
# --------------------------------------------------

echo
echo "===== STEP 8 FILES ====="
ls -lh intro.gd intro.tscn project.godot .github/workflows/build.yml

echo
echo "===== STARTUP SETTING ====="
grep 'run/main_scene' project.godot

echo
echo "===== NARRATOR BUILD STEP ====="
grep -A8 'Generate 1980 story narration' .github/workflows/build.yml

echo
echo "===== PATCH VALIDATION ====="
git diff --check

echo
echo "===== CHANGES ====="
git status --short

echo
echo "STEP 8 PATCH READY"

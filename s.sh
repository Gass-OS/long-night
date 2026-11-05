#!/data/data/com.termux/files/usr/bin/bash
# Long Night - Step 1: 2.5D movement + camera + touch controls (Godot 4)
set -e
mkdir -p ~/long-night
cd ~/long-night

cat > project.godot << 'EOF'
config_version=5

[application]

config/name="Long Night"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.3")

[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
window/handheld/orientation=0

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
EOF

cat > main.tscn << 'EOF'
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://level.gd" id="1"]

[node name="Main" type="Node3D"]

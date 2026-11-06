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

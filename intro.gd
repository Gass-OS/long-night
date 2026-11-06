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

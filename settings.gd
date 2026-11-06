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

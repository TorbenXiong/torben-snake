extends RefCounted

const DEFAULT_PATH := "user://torben_snake.cfg"

static func load_best(path: String = DEFAULT_PATH) -> int:
	var config := ConfigFile.new()
	config.load(path)
	return maxi(0, _number(config, "score", "best", 0))

static func load_unlocked(level_count: int, path: String = DEFAULT_PATH) -> int:
	var config := ConfigFile.new()
	config.load(path)
	return clampi(_number(config, "progress", "unlocked_levels", 1), 1, maxi(1, level_count))

static func save_progress(best: int, unlocked: int, level_count: int, path: String = DEFAULT_PATH) -> Error:
	# Updating either record must preserve the other and any existing save sections.
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("score", "best", maxi(0, maxi(_number(config, "score", "best", 0), best)))
	var value := clampi(maxi(_number(config, "progress", "unlocked_levels", 1), unlocked), 1, maxi(1, level_count))
	config.set_value("progress", "unlocked_levels", value)
	return config.save(path)

static func _number(config: ConfigFile, section: String, key: String, fallback: int) -> int:
	var value: Variant = config.get_value(section, key, fallback)
	return int(value) if value is int or value is float else fallback

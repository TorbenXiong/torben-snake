extends Node2D

const SnakeLogic := preload("res://scripts/game_logic.gd")
const ScoreStore := preload("res://scripts/score_store.gd")
const BOARD_W := SnakeLogic.WIDTH
const BOARD_H := SnakeLogic.HEIGHT
const MAX_FRAME_TIME := 0.1

var game := SnakeLogic.new()
var state := "menu"
var head_angle := 0.0
var pulse := 0.0
var high_score := 0
var unlocked_levels := 1
var selected_level := 0
var storage_path := ScoreStore.DEFAULT_PATH
var touch_start := Vector2.ZERO
var touch_active := false
var touch_index := -1
var ui_font: Font = ThemeDB.fallback_font
var sound_enabled := true
var audio := AudioStreamPlayer.new()
var eat_sound: AudioStreamWAV
var end_sound: AudioStreamWAV
var particles: Array[Dictionary] = []
var toast_text := ""
var toast_timer := 0.0

var colors := {
	"bg": Color("070b1e"),
	"cyan": Color("45f5ff"),
	"cyan_dark": Color("146b83"),
	"pink": Color("ff4fd8"),
	"yellow": Color("ffe27a"),
	"purple": Color("aa80ff"),
	"muted": Color("8492bd"),
	"white": Color("f1f5ff")
}

func _ready() -> void:
	high_score = ScoreStore.load_best(storage_path)
	unlocked_levels = ScoreStore.load_unlocked(SnakeLogic.LEVELS.size(), storage_path)
	var font_variation := FontVariation.new()
	font_variation.base_font = load("res://assets/fonts/NotoSansSC-VF.ttf")
	font_variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 500.0}
	ui_font = font_variation
	add_child(audio)
	eat_sound = _make_tone(740.0, 0.09)
	end_sound = _make_tone(170.0, 0.24)
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _process(delta: float) -> void:
	# A browser stall must not fast-forward several cells on the next frame.
	var frame_delta := clampf(delta, 0.0, MAX_FRAME_TIME)
	pulse += frame_delta
	if toast_timer > 0.0:
		toast_timer = maxf(0.0, toast_timer - frame_delta)
	if state == "playing":
		for event in game.advance(frame_delta):
			var result: String = event["type"]
			if result == "eat" or result == "clear":
				var eaten_kind: String = event["kind"]
				var eaten_color: Color = colors["yellow"] if eaten_kind == "normal" else colors["pink"]
				_spawn_particles(event["position"], eaten_color)
				_show_toast("奖励 +25" if eaten_kind == "bonus" else ("减速 5 秒 · +15" if eaten_kind == "slow" else "能量 +10"))
				_play_sound(eat_sound)
			if result == "dead" or result == "clear":
				_finish_game(result == "clear")
				break
		head_angle = Vector2(game.direction).angle()
	_update_particles(frame_delta)
	queue_redraw()

func _draw() -> void:
	var raw_size := get_viewport_rect().size
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(Vector2.ZERO, raw_size), colors["bg"])
	var viewport := _layout_size()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * _ui_scale())
	_draw_background(viewport)
	if state == "menu":
		_draw_menu(viewport)
	else:
		_draw_game(viewport)

func _draw_background(viewport: Vector2) -> void:
	var spacing := 48.0
	var offset := fmod(pulse * 4.0, spacing)
	for x in range(-1, int(viewport.x / spacing) + 2):
		var xpos := float(x) * spacing + offset
		draw_line(Vector2(xpos, 0), Vector2(xpos, viewport.y), Color(0.12, 0.2, 0.4, 0.16), 1.0)
	for y in range(-1, int(viewport.y / spacing) + 2):
		var ypos := float(y) * spacing + offset
		draw_line(Vector2(0, ypos), Vector2(viewport.x, ypos), Color(0.12, 0.2, 0.4, 0.16), 1.0)

func _draw_menu(viewport: Vector2) -> void:
	var center := viewport.x * 0.5
	var offset := (viewport.y - 720.0) * 0.5
	var panel_width := minf(660.0, viewport.x - 48.0)
	_draw_text(Vector2(center, 100 + offset), "TORBEN SNAKE", 46, colors["cyan"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
	_draw_text(Vector2(center, 140 + offset), "霓虹闯关 · 六段旅程", 18, colors["muted"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
	_draw_panel(Rect2(center - panel_width * 0.5, 182 + offset, panel_width, 292), Color(0.06, 0.1, 0.22, 0.92))
	_draw_text(Vector2(center, 220 + offset), "选择关卡 · 已解锁 %d / %d" % [unlocked_levels, SnakeLogic.LEVELS.size()], 22, colors["white"], HORIZONTAL_ALIGNMENT_CENTER, panel_width)
	for index in range(SnakeLogic.LEVELS.size()):
		var card := _level_rect(index)
		var unlocked := index < unlocked_levels
		var accent: Color = colors["cyan"] if index == selected_level else colors["cyan_dark"]
		draw_rect(card, Color(accent, 0.18 if unlocked else 0.07))
		draw_rect(card, accent, false, 2.0 if index == selected_level else 1.0)
		_draw_text(card.position + Vector2(card.size.x * 0.5, 26), "%d · %s" % [index + 1, SnakeLogic.LEVELS[index]["title"]], 16, colors["white"] if unlocked else colors["muted"], HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
		var status := "已选择 · 食物 %d" % SnakeLogic.LEVELS[index]["goal"] if index == selected_level else ("已解锁" if unlocked else "未解锁")
		_draw_text(card.position + Vector2(card.size.x * 0.5, 51), status, 13, colors["cyan"] if unlocked else colors["muted"], HORIZONTAL_ALIGNMENT_CENTER, card.size.x)
	_draw_button(_start_rect(), "开始第 %d 关" % (selected_level + 1), colors["pink"])
	if toast_timer > 0.0:
		_draw_text(Vector2(center, 173 + offset), toast_text, 14, colors["yellow"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
	_draw_text(Vector2(center, 520 + offset), "最高分  %05d" % high_score, 20, colors["yellow"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
	_draw_text(Vector2(center, 554 + offset), "菜单：方向键选关 / Enter 开始", 15, colors["muted"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
	_draw_text(Vector2(center, 578 + offset), "游戏：方向键 / WASD · 滑动或方向按钮", 14, colors["muted"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
	_draw_text(Vector2(center, 593 + offset), "金色 +10 · 粉色 +25 · 青色减速 5 秒", 14, colors["muted"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
	_draw_button(Rect2(center - 75, 620 + offset, 150, 38), "音效：开" if sound_enabled else "音效：关", colors["cyan_dark"])

func _draw_game(viewport: Vector2) -> void:
	var board := _board_rect(viewport)
	_draw_text(Vector2(34, 48), "TORBEN SNAKE", 24, colors["cyan"], HORIZONTAL_ALIGNMENT_LEFT, 260)
	_draw_text(Vector2(34, 75), "第 %d/%d 关 · %s" % [game.level_index + 1, SnakeLogic.LEVELS.size(), game.level()["title"]], 14, colors["muted"], HORIZONTAL_ALIGNMENT_LEFT, 280)
	_draw_text(Vector2(viewport.x - 34, 47), "得分  %05d" % game.score, 22, colors["white"], HORIZONTAL_ALIGNMENT_RIGHT, 260)
	_draw_text(Vector2(viewport.x - 34, 75), "食物  %d / %d" % [game.food_eaten, game.level()["goal"]], 16, colors["yellow"], HORIZONTAL_ALIGNMENT_RIGHT, 200)
	_draw_panel(board.grow(8), Color(0.04, 0.07, 0.16, 0.95))
	_draw_board(board)
	_draw_touch_controls(viewport)
	_draw_text(Vector2(24, viewport.y - 6), _rule_label(), 13, colors["muted"], HORIZONTAL_ALIGNMENT_LEFT, viewport.x - 48)
	if toast_timer > 0.0:
		_draw_text(Vector2(viewport.x * 0.5, board.position.y - 16), toast_text, 17, colors["yellow"], HORIZONTAL_ALIGNMENT_CENTER, 300)
	if state == "paused":
		_draw_overlay(viewport, "已暂停", "按空格 / Esc 继续")
		_draw_button(_action_rect(), "继续游戏", colors["cyan"])
		_draw_button(_menu_button_rect(), "返回菜单", colors["cyan_dark"])
	elif state == "game_over":
		_draw_overlay(viewport, "第 %d 关挑战失败" % (game.level_index + 1), "本次得分 %05d · 重试从 %05d 分开始" % [game.score, game.level_start_score])
		_draw_button(_action_rect(), "重试本关", colors["pink"])
		_draw_button(_menu_button_rect(), "返回菜单", colors["cyan_dark"])
	elif state == "level_clear":
		_draw_overlay(viewport, "第 %d 关通关！" % (game.level_index + 1), "下一关 · %s" % SnakeLogic.LEVELS[game.level_index + 1]["title"])
		_draw_text(viewport * 0.5 + Vector2(0, 47), "总分 %05d · 下一关收集 %d 份食物" % [game.score, SnakeLogic.LEVELS[game.level_index + 1]["goal"]], 16, colors["yellow"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
		_draw_button(_action_rect(), "进入下一关", colors["cyan"])
		_draw_button(_menu_button_rect(), "返回菜单", colors["cyan_dark"])
	elif state == "campaign_complete":
		_draw_overlay(viewport, "闯关完成！", "总分 %05d · 最高分 %05d" % [game.score, high_score])
		_draw_button(_action_rect(), "重新闯关", colors["pink"])
		_draw_button(_menu_button_rect(), "返回菜单", colors["cyan_dark"])

func _draw_board(board: Rect2) -> void:
	var cell := board.size.x / BOARD_W
	var grid_color := Color(0.08, 0.14, 0.29, 0.55)
	# Shared edges are drawn once: 44 lines instead of 432 four-sided rectangles.
	for x in range(BOARD_W + 1):
		var xpos := board.position.x + x * cell
		draw_line(Vector2(xpos, board.position.y), Vector2(xpos, board.end.y), grid_color, 1.0, true)
	for y in range(BOARD_H + 1):
		var ypos := board.position.y + y * cell
		draw_line(Vector2(board.position.x, ypos), Vector2(board.end.x, ypos), grid_color, 1.0, true)
	for obstacle in game.obstacles:
		var obstacle_rect := Rect2(board.position + Vector2(obstacle) * cell + Vector2(3, 3), Vector2(cell - 6, cell - 6))
		draw_rect(obstacle_rect, Color(colors["purple"], 0.32))
		draw_rect(obstacle_rect, colors["purple"], false, 2.0)
	var food_center := board.position + (Vector2(game.food_pos) + Vector2(0.5, 0.5)) * cell
	var food_color: Color = colors["yellow"] if game.food_kind == "normal" else (colors["pink"] if game.food_kind == "bonus" else colors["cyan"])
	draw_circle(food_center, cell * (0.30 + sin(pulse * 6.0) * 0.04), Color(food_color, 0.18), true, -1.0, true)
	draw_circle(food_center, cell * 0.19, food_color, true, -1.0, true)
	if game.food_kind == "bonus":
		draw_arc(food_center, cell * 0.42, -PI * 0.5, -PI * 0.5 + TAU * game.food_timer / 8.0, 24, food_color, 1.5)
	var points := game.snake
	for index in range(game.trail.size() - 1, 0, -1):
		_draw_snake_link(game.trail[index - 1], game.trail[index], board, colors["cyan"])
		_draw_snake_disc(game.trail[index], board, cell * SnakeLogic.BODY_RADIUS, colors["cyan"])
	for index in range(points.size() - 1, -1, -1):
		var segment := points[index]
		var factor := 1.0 - float(index) / maxf(1.0, float(points.size())) * 0.38
		var segment_color: Color = colors["cyan"] if index == 0 else colors["cyan_dark"].lerp(colors["cyan"], factor)
		_draw_snake_disc(segment, board, cell * (0.39 if index == 0 else 0.34), Color(segment_color, 0.18))
		_draw_snake_disc(segment, board, cell * (SnakeLogic.HEAD_RADIUS if index == 0 else SnakeLogic.BODY_RADIUS), segment_color)
		if index == 0:
			var facing := Vector2.from_angle(head_angle)
			var eye_offset := facing * 0.11
			var separation := facing.orthogonal() * 0.095
			_draw_snake_disc(segment + eye_offset - separation, board, cell * 0.045, colors["bg"])
			_draw_snake_disc(segment + eye_offset + separation, board, cell * 0.045, colors["bg"])
	for particle in particles:
		var position: Vector2 = board.position + (Vector2(particle["grid"]) + Vector2(0.5, 0.5) + particle["offset"]) * cell
		var alpha: float = particle["life"] / particle["max_life"]
		draw_circle(position, cell * (0.10 + (1.0 - alpha) * 0.18), Color(particle["color"], alpha))

func _draw_snake_disc(point: Vector2, board: Rect2, radius: float, color: Color) -> void:
	var cell := board.size.x / BOARD_W
	var center := board.position + (point + Vector2.ONE * 0.5) * cell
	draw_circle(center, radius, color, true, -1.0, true)

func _draw_snake_link(from: Vector2, to: Vector2, board: Rect2, color: Color) -> void:
	if from.is_equal_approx(to):
		return
	var cell := board.size.x / BOARD_W
	var a := board.position + (from + Vector2.ONE * 0.5) * cell
	var b := board.position + (to + Vector2.ONE * 0.5) * cell
	draw_line(a, b, Color(color, 0.18), cell * 0.78, true)
	draw_line(a, b, color, cell * SnakeLogic.BODY_RADIUS * 2.0, true)

func _draw_touch_controls(viewport: Vector2) -> void:
	var positions := _control_positions()
	var radius := 34.0 if viewport.x < 700.0 else 25.0
	var labels := ["▲", "◀", "▼", "▶", "Ⅱ"]
	for index in range(positions.size()):
		_draw_circle_button(positions[index], labels[index], radius)
	if game.slow_timer > 0.0:
		_draw_text(Vector2(24, viewport.y - 28), "减速 %.1fs" % game.slow_timer, 14, colors["cyan"], HORIZONTAL_ALIGNMENT_LEFT, 200)

func _draw_circle_button(center: Vector2, label: String, radius: float) -> void:
	draw_circle(center, radius, Color(0.1, 0.16, 0.32, 0.9))
	draw_circle(center, radius, colors["cyan_dark"], false, 1.5)
	_draw_text(center + Vector2(0, 7), label, 20, colors["white"], HORIZONTAL_ALIGNMENT_CENTER, 40)

func _draw_overlay(viewport: Vector2, title: String, subtitle: String) -> void:
	draw_rect(Rect2(Vector2.ZERO, viewport), Color(0.02, 0.03, 0.1, 0.72))
	var center := viewport * 0.5
	_draw_text(Vector2(center.x, center.y - 30), title, 38, colors["white"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)
	_draw_text(Vector2(center.x, center.y + 18), subtitle, 18, colors["muted"], HORIZONTAL_ALIGNMENT_CENTER, viewport.x)

func _draw_panel(rect: Rect2, color: Color) -> void:
	draw_rect(rect, Color(0, 0, 0, 0.2))
	draw_rect(rect, color)
	draw_rect(rect, Color(0.3, 0.5, 0.8, 0.16), false, 1.0)

func _draw_button(rect: Rect2, label: String, accent: Color) -> void:
	draw_rect(rect, Color(accent, 0.18))
	draw_rect(rect, accent, false, 2.0)
	_draw_text(rect.get_center() + Vector2(0, 7), label, 18, colors["white"], HORIZONTAL_ALIGNMENT_CENTER, rect.size.x)

func _draw_text(position: Vector2, text: String, size: int, color: Color, alignment: HorizontalAlignment, width: float) -> void:
	var text_width := ui_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var origin := position
	if alignment == HORIZONTAL_ALIGNMENT_CENTER:
		origin.x -= text_width * 0.5
	elif alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		origin.x -= text_width
	draw_string(ui_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, width, size, color)

func _ui_scale() -> float:
	var raw := get_viewport_rect().size
	var portrait := raw.x < raw.y * 0.85
	return minf(raw.x / (600.0 if portrait else 960.0), raw.y / (800.0 if portrait else 720.0))

func _layout_size() -> Vector2:
	return get_viewport_rect().size / _ui_scale()

func _start_rect() -> Rect2:
	var viewport := _layout_size()
	var offset := (viewport.y - 720.0) * 0.5
	return Rect2(viewport.x * 0.5 - 118, 402 + offset, 236, 52)

func _level_rect(index: int) -> Rect2:
	var viewport := _layout_size()
	var width := minf(660.0, viewport.x - 48.0)
	var card_width := (width - 64.0) / 3.0
	var origin := Vector2((viewport.x - width) * 0.5 + 20.0, 240.0 + (viewport.y - 720.0) * 0.5)
	return Rect2(origin + Vector2((index % 3) * (card_width + 12.0), (index / 3) * 80.0), Vector2(card_width, 68.0))

func _select_level(index: int) -> void:
	if index < 0 or index >= SnakeLogic.LEVELS.size():
		return
	if index >= unlocked_levels:
		_show_toast("此关卡尚未解锁")
	else:
		selected_level = index
		toast_timer = 0.0
	queue_redraw()

func _action_rect() -> Rect2:
	var center := _layout_size() * 0.5
	return Rect2(center.x - 116, center.y + 68, 232, 50)

func _menu_button_rect() -> Rect2:
	var center := _layout_size() * 0.5
	return Rect2(center.x - 116, center.y + 136, 232, 44)

func _control_positions() -> Array[Vector2]:
	var viewport := _layout_size()
	var portrait := viewport.x < 700.0
	var y := viewport.y - (100.0 if portrait else 75.0)
	var center := viewport.x * 0.5
	var spacing := 72.0 if portrait else 58.0
	var top := 36.0 if portrait else 28.0
	var bottom := 36.0 if portrait else 25.0
	return [Vector2(center, y - top), Vector2(center - spacing, y + bottom), Vector2(center, y + bottom), Vector2(center + spacing, y + bottom), Vector2(viewport.x - 55, y)]

func _board_rect(viewport: Vector2) -> Rect2:
	var header := 96.0
	var footer := 144.0
	var cell := minf((viewport.x - 48.0) / BOARD_W, (viewport.y - header - footer) / BOARD_H)
	cell = maxf(10.0, cell)
	var size := Vector2(cell * BOARD_W, cell * BOARD_H)
	return Rect2(Vector2((viewport.x - size.x) * 0.5, header + (viewport.y - header - footer - size.y) * 0.5), size)

func _rule_label() -> String:
	return "避开墙壁与自身 · 障碍 %d · 每份食物增长一格" % game.level()["obstacles"]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key_event := event as InputEventKey
		if key_event.keycode == KEY_ESCAPE or key_event.keycode == KEY_SPACE:
			if state == "playing" or state == "paused":
				state = "paused" if state == "playing" else "playing"
				return
		if state == "menu":
			match key_event.keycode:
				KEY_ENTER, KEY_KP_ENTER: _start_game()
				KEY_LEFT, KEY_A: _select_level(selected_level - 1)
				KEY_RIGHT, KEY_D: _select_level(selected_level + 1)
				KEY_UP, KEY_W: _select_level(selected_level - 3)
				KEY_DOWN, KEY_S: _select_level(selected_level + 3)
			return
		if state in ["game_over", "level_clear", "campaign_complete"]:
			if key_event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
				_continue_campaign()
			elif key_event.keycode == KEY_ESCAPE:
				state = "menu"
				toast_timer = 0.0
			return
		if state == "playing":
			match key_event.keycode:
				KEY_UP, KEY_W: _turn(Vector2i.UP)
				KEY_DOWN, KEY_S: _turn(Vector2i.DOWN)
				KEY_LEFT, KEY_A: _turn(Vector2i.LEFT)
				KEY_RIGHT, KEY_D: _turn(Vector2i.RIGHT)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_click(event.position / _ui_scale())
	if event is InputEventScreenTouch:
		if event.pressed and not touch_active:
			touch_index = event.index
			touch_start = event.position / _ui_scale()
			touch_active = true
			_handle_click(touch_start)
		elif not event.pressed and event.index == touch_index:
			touch_active = false
			touch_index = -1
	if event is InputEventScreenDrag and touch_active and event.index == touch_index:
		var logical_position: Vector2 = event.position / _ui_scale()
		if logical_position.distance_to(touch_start) >= 8.0:
			_handle_swipe(logical_position - touch_start)
			touch_start = logical_position

func _handle_swipe(delta: Vector2) -> void:
	if state != "playing":
		return
	if abs(delta.x) > abs(delta.y):
		_turn(Vector2i.RIGHT if delta.x > 0 else Vector2i.LEFT)
	else:
		_turn(Vector2i.DOWN if delta.y > 0 else Vector2i.UP)

func _turn(value: Vector2i) -> void:
	game.set_direction(value)
	head_angle = Vector2(game.direction).angle()
	queue_redraw()

func _handle_click(position: Vector2) -> void:
	var viewport := _layout_size()
	var center := viewport.x * 0.5
	var offset := (viewport.y - 720.0) * 0.5
	if state == "menu":
		for index in range(SnakeLogic.LEVELS.size()):
			if _level_rect(index).has_point(position):
				_select_level(index)
				return
		if _start_rect().has_point(position):
			_start_game()
			return
		if Rect2(center - 75, 620 + offset, 150, 38).has_point(position):
			sound_enabled = not sound_enabled
		return
	if state in ["game_over", "level_clear", "campaign_complete"]:
		if _action_rect().has_point(position):
			_continue_campaign()
		elif _menu_button_rect().has_point(position):
			state = "menu"
			toast_timer = 0.0
		return
	if state == "paused":
		if _action_rect().has_point(position):
			state = "playing"
		elif _menu_button_rect().has_point(position):
			_save_record()
			state = "menu"
			toast_timer = 0.0
		return
	if state == "playing":
		var positions := _control_positions()
		var radius := 36.0 if viewport.x < 700.0 else 28.0
		var directions := [Vector2i.UP, Vector2i.LEFT, Vector2i.DOWN, Vector2i.RIGHT]
		for index in range(positions.size()):
			if positions[index].distance_to(position) <= radius:
				if index == 4:
					state = "paused"
				else:
					_turn(directions[index])
				return

func _start_game() -> void:
	if selected_level < 0 or selected_level >= unlocked_levels:
		return
	game.start(selected_level)
	_reset_round_ui()

func _continue_campaign() -> void:
	match state:
		"level_clear":
			if game.advance_level():
				selected_level = game.level_index
				_reset_round_ui()
		"game_over":
			game.retry_level()
			_reset_round_ui()
		"campaign_complete":
			selected_level = 0
			_start_game()

func _reset_round_ui() -> void:
	state = "playing"
	head_angle = Vector2(game.direction).angle()
	particles.clear()
	_show_toast("收集 %d 份食物" % game.level()["goal"])

func _finish_game(victory: bool) -> void:
	if victory and game.won and game.ended and game.level_index < unlocked_levels:
		unlocked_levels = maxi(unlocked_levels, mini(SnakeLogic.LEVELS.size(), game.level_index + 2))
	state = ("campaign_complete" if game.is_final_level() else "level_clear") if victory else "game_over"
	_save_record()
	_play_sound(eat_sound if victory else end_sound)

func _save_record() -> void:
	high_score = maxi(high_score, game.score)
	var error := ScoreStore.save_progress(high_score, unlocked_levels, SnakeLogic.LEVELS.size(), storage_path)
	if error != OK:
		push_warning("Unable to persist progress: %s" % error_string(error))
		_show_toast("进度暂未保存，请检查存储权限")

func _spawn_particles(grid: Vector2, color: Color) -> void:
	for index in range(10):
		var angle := index * TAU / 10.0
		particles.append({"grid": grid, "offset": Vector2.ZERO, "velocity": Vector2.from_angle(angle) * 2.0, "color": color, "life": 0.55 + index * 0.02, "max_life": 0.55 + index * 0.02})

func _update_particles(delta: float) -> void:
	for index in range(particles.size() - 1, -1, -1):
		particles[index]["life"] -= delta
		particles[index]["offset"] += particles[index]["velocity"] * delta
		if particles[index]["life"] <= 0.0:
			particles.remove_at(index)

func _show_toast(message: String) -> void:
	toast_text = message
	toast_timer = 1.2

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		# The platform may not deliver touch release after switching apps or tabs.
		touch_active = false
		touch_index = -1
		if state == "playing":
			state = "paused"
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_record()

func _make_tone(frequency: float, duration: float) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var count := int(duration * stream.mix_rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for index in range(count):
		var envelope := (1.0 - float(index) / count) * minf(1.0, float(index) / 120.0)
		var value := sin(TAU * frequency * float(index) / stream.mix_rate) * envelope * 5000.0
		data.encode_s16(index * 2, int(value))
	stream.data = data
	return stream

func _play_sound(stream: AudioStreamWAV) -> void:
	if sound_enabled:
		audio.stream = stream
		audio.play()

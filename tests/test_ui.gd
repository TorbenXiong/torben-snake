extends SceneTree

const MainScene := preload("res://scenes/main.tscn")
const ScoreStore := preload("res://scripts/score_store.gd")
var failures: Array[String] = []
var app: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	app = MainScene.instantiate()
	app.storage_path = "user://test_torben_ui_%s.cfg" % Time.get_ticks_usec()
	root.add_child(app)
	app.set_process(false)
	app.sound_enabled = false
	await process_frame
	_check(app.state == "menu", "scene starts at menu")
	_check(app.unlocked_levels == 1 and app.selected_level == 0, "new player can only select level one")
	app._handle_click(app._level_rect(1).get_center())
	_check(app.state == "menu" and app.selected_level == 0, "locked card cannot select or start level two")
	_key(KEY_RIGHT)
	_check(app.selected_level == 0, "keyboard cannot select a locked level")
	app.selected_level = 1
	app._start_game()
	_check(app.state == "menu", "start guard prevents bypassing a locked card")
	app.selected_level = 0
	_check(app.ui_font.has_char("中".unicode_at(0)), "bundled font supports Chinese")
	_key(KEY_ENTER)
	_check(app.state == "playing" and app.game.level_index == 0, "enter starts campaign at level one")
	_key(KEY_UP)
	_check(app.game.direction == Vector2i.UP, "arrow input turns snake")
	_key(KEY_SPACE)
	_check(app.state == "paused", "space pauses")
	app.game.slow_timer = 4.0
	app.game.food_kind = "bonus"
	app.game.food_timer = 8.0
	var head: Vector2 = app.game.snake[0]
	var timer: float = app.game.slow_timer
	app._process(0.5)
	_check(app.game.snake[0] == head and app.game.slow_timer == timer and app.game.food_timer == 8.0, "paused game freezes movement and active effects")
	app._handle_click(app._action_rect().get_center())
	_check(app.state == "playing", "continue button resumes")
	app._handle_click(app._control_positions()[0])
	_check(app.game.direction == Vector2i.UP, "direction button turns snake")
	var touch := InputEventScreenTouch.new()
	touch.index = 0
	touch.pressed = true
	touch.position = Vector2(200, 200)
	app._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(200, 120)
	app._input(drag)
	_check(app.game.direction == Vector2i.UP, "touch drag turns snake")
	touch.pressed = false
	app._input(touch)
	_check(not app.touch_active, "touch release clears tracking")
	app.game.score = 25
	app.game.set_pose(PackedVector2Array([Vector2.ZERO]), Vector2i.LEFT)
	_simulate(app.game.current_interval() * 0.6)
	_check(app.state == "game_over", "finishing shows game over")
	_check(ScoreStore.load_best(app.storage_path) == app.game.score, "ending persists high score")
	_check(app.unlocked_levels == 1 and ScoreStore.load_unlocked(6, app.storage_path) == 1, "failure never unlocks the next level")
	_key(KEY_ENTER)
	_check(app.state == "playing" and app.game.score == 0 and app.game.level_index == 0, "enter retries the same level from its checkpoint")
	touch.pressed = true
	app._input(touch)
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(app.state == "paused", "focus loss automatically pauses")
	_check(not app.touch_active and app.touch_index == -1, "focus loss clears a touch whose release may be lost")
	app._handle_click(app._menu_button_rect().get_center())
	_check(app.state == "menu", "pause menu returns to menu")
	_check(app._board_rect(app._layout_size()).end.x <= app._layout_size().x, "board fits viewport")
	_check(app._start_rect().position.x >= 0 and app._start_rect().end.x <= app._layout_size().x, "start button fits viewport")
	for position in app._control_positions():
		_check(position.y + 34.0 <= app._layout_size().y, "touch controls fit viewport")
	_test_campaign_flow()
	await _test_level_selection()
	_test_smooth_movement()
	app.state = "menu"
	app.toast_timer = 0.0
	if "--capture" in OS.get_cmdline_user_args():
		var unlocked: int = app.unlocked_levels
		app.unlocked_levels = 1
		await _capture("level_select_locked")
		app.unlocked_levels = unlocked
		app.selected_level = 3
		await _capture("level_select_unlocked")
		app.selected_level = 0
		await _capture("menu")
		app._start_game()
		app.game.start(2, 150, 11)
		app.toast_timer = 0.0
		app.game.food_kind = "bonus"
		app.game.food_timer = 8.0
		await _capture("game")
		app.state = "paused"
		await _capture("paused")
		app.state = "playing"
		_clear_current_level()
		await _capture("level_clear")
		app._continue_campaign()
		app.game.score += 20
		app._finish_game(false)
		await _capture("game_over")
		app.selected_level = 0
		app._start_game()
		for index in range(app.SnakeLogic.LEVELS.size()):
			_clear_current_level()
			if app.state == "level_clear":
				app._continue_campaign()
		await _capture("campaign_complete")
	if "--capture-motion" in OS.get_cmdline_user_args():
		await _capture_motion_loop()
	DirAccess.remove_absolute(app.storage_path)
	app.queue_free()
	await process_frame
	if failures.is_empty():
		print("All UI/input/persistence tests passed.")
		quit(0)
	else:
		for message in failures:
			push_error(message)
		quit(1)

func _test_campaign_flow() -> void:
	app.high_score = 9999
	ScoreStore.save_progress(app.high_score, app.unlocked_levels, app.SnakeLogic.LEVELS.size(), app.storage_path)
	app._handle_click(app._start_rect().get_center())
	_check(app.state == "playing" and app.game.level_index == 0, "menu click starts a new campaign")
	for index in range(app.SnakeLogic.LEVELS.size()):
		_clear_current_level()
		var total: int = app.game.score
		_check(app.unlocked_levels == mini(6, index + 2), "clearing a level unlocks exactly its successor")
		_check(ScoreStore.load_unlocked(6, app.storage_path) == app.unlocked_levels, "unlock is saved before continuing or returning to menu")
		_check(ScoreStore.load_best(app.storage_path) >= total, "clearing a level persists the best total")
		if index == app.SnakeLogic.LEVELS.size() - 1:
			_check(app.state == "campaign_complete", "last level shows campaign victory")
			break
		_check(app.state == "level_clear", "food goal triggers the level transition screen")
		var head: Vector2 = app.game.snake[0]
		var slow: float = app.game.slow_timer
		var bonus: float = app.game.food_timer
		app._process(1.0)
		_check(app.game.snake[0] == head and app.game.slow_timer == slow and app.game.food_timer == bonus, "transition freezes movement and food effects")
		app._handle_click(app._control_positions()[0])
		_check(app.state == "level_clear", "direction buttons cannot bypass the transition")
		if index % 2 == 0:
			_key(KEY_ENTER)
		else:
			app._handle_click(app._action_rect().get_center())
		_check(app.state == "playing" and app.game.level_index == index + 1 and app.game.score == total, "keyboard and click advance sequentially with score retained")
		if index == 1:
			# Die in level three, then prove retry stays there and discards attempt points.
			app.game.score += 25
			app.game.set_pose(PackedVector2Array([Vector2.ZERO]), Vector2i.LEFT)
			_simulate(app.game.current_interval() * 0.6)
			_check(app.state == "game_over", "wall collision during later level shows failure")
			app._handle_click(app._action_rect().get_center())
			_check(app.state == "playing" and app.game.level_index == 2 and app.game.score == total and app.game.food_eaten == 0, "retry button keeps level and restores checkpoint score")
	_key(KEY_ENTER)
	_check(app.state == "playing" and app.game.level_index == 0 and app.game.score == 0, "victory enter begins a fresh campaign")
	_clear_current_level()
	app._handle_click(app._menu_button_rect().get_center())
	_check(app.state == "menu", "transition offers return to menu")
	app._select_level(0)
	_key(KEY_ENTER)
	_check(app.game.level_index == 0 and app.game.score == 0, "returning to menu then starting resets the campaign")

func _test_level_selection() -> void:
	app.state = "menu"
	app._handle_click(app._level_rect(3).get_center())
	_check(app.selected_level == 3 and app.state == "menu", "unlocked card selects without starting")
	_key(KEY_ENTER)
	_check(app.game.level_index == 3 and app.game.score == 0, "selected later level starts from zero score")
	app._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	app._handle_click(app._menu_button_rect().get_center())
	_check(app.unlocked_levels == 6, "returning to menu keeps unlocked levels")
	_key(KEY_LEFT)
	_check(app.selected_level == 2, "keyboard selects unlocked levels")
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.index = 0
	touch.position = app._level_rect(4).get_center() * app._ui_scale()
	app._input(touch)
	touch.pressed = false
	app._input(touch)
	_check(app.selected_level == 4, "touch selects unlocked cards")
	app._handle_click(app._start_rect().get_center())
	_check(app.game.level_index == 4 and app.game.score == 0, "start button launches selected level")
	_clear_current_level()
	_check(app.unlocked_levels == 6, "replaying a cleared level never relocks progress")
	var restored := MainScene.instantiate()
	restored.storage_path = app.storage_path
	root.add_child(restored)
	restored.set_process(false)
	await process_frame
	_check(restored.unlocked_levels == 6 and restored.high_score == app.high_score, "new scene restores unlock progress alongside the highest score")
	restored.queue_free()
	await process_frame
	app.selected_level = 0
	app.state = "menu"
	for index in range(6):
		var rect: Rect2 = app._level_rect(index)
		_check(rect.position.x >= 0 and rect.end.x <= app._layout_size().x, "all level cards fit the viewport")

func _clear_current_level() -> void:
	var goal: int = app.game.level()["goal"]
	for index in range(goal):
		app.game.set_pose(PackedVector2Array([Vector2(5, 5)]), Vector2i.RIGHT)
		app.game.obstacles.clear()
		app.game.direction = Vector2i.RIGHT
		app.game.food_pos = Vector2i(6, 5)
		app.game.food_kind = ["normal", "bonus", "slow"][index % 3]
		app.game.food_timer = 8.0
		_simulate(app.game.current_interval() * 0.6)
		if app.state != "playing":
			break

func _simulate(duration: float) -> void:
	var remaining := duration
	while remaining > 0.000001:
		var slice := minf(1.0 / 120.0, remaining)
		app._process(slice)
		remaining -= slice

func _test_smooth_movement() -> void:
	for time in [0.01, 0.05, 0.13, 0.19]:
		app._start_game()
		app.game.food_pos = Vector2i(1, 1)
		_simulate(time)
		var corner: Vector2 = app.game.snake[0]
		_key(KEY_UP)
		_check(app.game.direction == Vector2i.UP and is_equal_approx(app.head_angle, -PI * 0.5), "key input changes movement and head facing in the same input callback")
		_check(app.game.snake[0] == corner, "instant input never snaps the head to a grid point")
		app._process(1.0 / 120.0)
		_check(is_equal_approx(app.game.snake[0].x, corner.x) and app.game.snake[0].y < corner.y, "first frame after input travels only in the new direction")
		var next_corner: Vector2 = app.game.snake[0]
		app._handle_click(app._control_positions()[1])
		_check(app.game.direction == Vector2i.LEFT, "direction button responds immediately between grid points")
		app._process(1.0 / 120.0)
		_check(app.game.snake[0].x < next_corner.x and is_equal_approx(app.game.snake[0].y, next_corner.y), "button turn follows the current fractional position")
		_key(KEY_RIGHT)
		_check(app.game.direction == Vector2i.LEFT, "reverse button input is ignored")
		var paused: PackedVector2Array = app.game.trail.duplicate()
		_key(KEY_SPACE)
		app._process(0.5)
		_check(app.game.trail == paused, "pause freezes the entire continuous body path")
		_key(KEY_SPACE)
		_simulate(0.01)
		_check(app.game.snake[0].x < paused[0].x, "resume continues from the exact saved position")
	app._start_game()
	app.game.food_pos = Vector2i(1, 1)
	_simulate(0.07)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.index = 0
	touch.position = Vector2(200, 200) * app._ui_scale()
	app._input(touch)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(200, 191) * app._ui_scale()
	app._input(drag)
	_check(app.game.direction == Vector2i.UP, "short nine-unit swipe responds without waiting for a grid boundary")
	touch.pressed = false
	app._input(touch)
	app._start_game()
	app.game.food_pos = Vector2i(1, 1)
	var initial: Vector2 = app.game.snake[0]
	app._process(5.0)
	_check(app.game.snake[0].is_equal_approx(initial + Vector2(0.5, 0)), "long stalls cannot fast-forward through multiple cells")
	app._start_game()
	app.game.food_pos = Vector2i(1, 1)
	app.game.slow_timer = 0.005
	var before: Vector2 = app.game.snake[0]
	_simulate(0.015)
	_check(app.game.snake[0].x > before.x, "slowdown expiry cannot reverse continuous movement")
	app._start_game()
	_key(KEY_SPACE)
	app._handle_click(app._menu_button_rect().get_center())

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	app._input(event)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _capture(label: String) -> void:
	app.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://build/qa")
	var suffix := "_portrait" if "--portrait" in OS.get_cmdline_user_args() else ""
	var error := root.get_texture().get_image().save_png("res://build/qa/%s%s.png" % [label, suffix])
	_check(error == OK, "screenshot saved: " + label)

func _capture_motion_loop() -> void:
	app._start_game()
	app.game.set_pose(PackedVector2Array([Vector2(8.25, 11.2), Vector2(1.25, 11.2)]), Vector2i.RIGHT)
	app.game.food_pos = Vector2i(0, 0)
	app.game.food_kind = "normal"
	app.toast_timer = 0.0
	DirAccess.make_dir_recursive_absolute("res://build/qa/motion_frames")
	# Fractional corners demonstrate that steering is no longer tied to the grid.
	for frame in range(336):
		match frame % 168:
			0: app._turn(Vector2i.RIGHT)
			48: app._turn(Vector2i.UP)
			84: app._turn(Vector2i.LEFT)
			132: app._turn(Vector2i.DOWN)
		app._process(1.0 / 30.0)
		_check(app.state == "playing", "instant-steering demo stays collision-free")
		if frame >= 168:
			app.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			var board: Rect2 = app._board_rect(app._layout_size()).grow(8)
			var area := Rect2i(board.position * app._ui_scale(), board.size * app._ui_scale())
			var picture := root.get_texture().get_image().get_region(area)
			picture.resize(492, 372, Image.INTERPOLATE_LANCZOS)
			var error := picture.save_png("res://build/qa/motion_frames/%03d.png" % (frame - 168))
			_check(error == OK, "instant-steering frame saved")

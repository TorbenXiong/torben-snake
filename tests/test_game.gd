extends SceneTree

const SnakeLogic := preload("res://scripts/game_logic.gd")
const ScoreStore := preload("res://scripts/score_store.gd")
var failures: Array[String] = []

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_movement_and_turns()
	_test_collisions()
	_test_food_and_growth()
	_test_campaign()
	_test_generation()
	_test_full_board()
	_test_score_store()
	if failures.is_empty():
		print("All continuous SnakeGameLogic tests passed.")
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)

func _pose(game: SnakeLogic, points: Array, facing: Vector2i = Vector2i.RIGHT) -> void:
	game.set_pose(PackedVector2Array(points), facing)

func _test_movement_and_turns() -> void:
	for rate in [30, 60, 120]:
		var game := SnakeLogic.new()
		game.start(0, 0, 1)
		game.food_pos = Vector2i(1, 1)
		_check(game.snake.size() == 3 and game.score == 0, "new campaign starts with three segments and zero score")
		var initial := game.snake[0]
		for frame in range(rate / 5):
			var before := game.snake[0]
			game.advance(1.0 / rate)
			_check(is_equal_approx(game.snake[0].x - before.x, 5.0 / rate), "every rendered frame advances continuously at %d FPS" % rate)
		_check(game.snake[0].is_equal_approx(initial + Vector2.RIGHT), "movement speed is frame-rate independent")
	for time in [0.01, 0.05, 0.13, 0.19]:
		var game := SnakeLogic.new()
		game.start(0, 0, 2)
		game.food_pos = Vector2i(1, 1)
		game.advance(time)
		var corner := game.snake[0]
		game.set_direction(Vector2i.UP)
		_check(game.direction == Vector2i.UP and game.snake[0] == corner, "mid-cell turn changes direction immediately without moving or snapping the head")
		game.advance(1.0 / 120.0)
		_check(is_equal_approx(game.snake[0].x, corner.x) and game.snake[0].y < corner.y, "first frame after input moves only in the new direction")
		_check(game.trail.size() >= 3 and game.trail[1].is_equal_approx(corner), "body retains the actual fractional turn point")
		game.set_direction(Vector2i.DOWN)
		_check(game.direction == Vector2i.UP, "direct reversal is rejected")
		game.set_direction(Vector2i.LEFT)
		_check(game.direction == Vector2i.LEFT, "a second perpendicular turn is immediate after travel")
		game.set_direction(Vector2i(3, 0))
		_check(game.direction == Vector2i.LEFT, "invalid direction is ignored")
	var game := SnakeLogic.new()
	game.start()
	game.set_direction(Vector2i.UP)
	game.set_direction(Vector2i.LEFT)
	_check(game.direction == Vector2i.UP, "same-instant double turn cannot reverse into the neck")
	game.start(5, 0, 3)
	game.food_pos = Vector2i(1, 1)
	var fast := game.snake[0]
	game.advance(0.06)
	_check(game.snake[0].is_equal_approx(fast + Vector2(0.5, 0)), "last level moves continuously at its configured faster speed")

func _test_collisions() -> void:
	var game := SnakeLogic.new()
	game.start(0, 0, 4)
	_pose(game, [Vector2(23, 4), Vector2(21, 4)])
	game.advance(0.2)
	_check(game.ended and not game.won and game.snake[0].x <= 23.21, "wall collision respects the visible head radius")
	var frozen := game.snake[0]
	_check(game.advance(1.0).is_empty() and game.snake[0] == frozen, "ended game cannot move or repeat events")
	game.start(2, 0, 4)
	_pose(game, [Vector2(5, 5)])
	game.obstacles.assign([Vector2i(6, 5)])
	game.advance(0.2)
	_check(game.ended and game.snake[0].x < 6.0, "obstacle collision is checked continuously before the head passes through it")
	game.start(0, 0, 5)
	_pose(game, [Vector2(5, 5), Vector2(5, 7), Vector2(7, 7), Vector2(7, 5), Vector2(6, 5), Vector2(6, 4)])
	game.food_pos = Vector2i(1, 1)
	game.advance(0.2)
	_check(game.ended, "head collides with non-neck body path")
	game.start(0, 0, 5)
	_pose(game, [Vector2(5, 5), Vector2(5, 6), Vector2(7, 6), Vector2(7, 5), Vector2(6, 5)])
	game.food_pos = Vector2i(1, 1)
	game.advance(0.2)
	_check(not game.ended, "head can follow a vacating tail")
	for level_index in range(SnakeLogic.LEVELS.size()):
		for facing in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			game.start(level_index, 0, 6)
			game.obstacles.clear()
			var origin := Vector2(23, 4)
			match facing:
				Vector2i.LEFT: origin = Vector2(0, 4)
				Vector2i.UP: origin = Vector2(4, 0)
				Vector2i.DOWN: origin = Vector2(4, 17)
			_pose(game, [origin, origin - Vector2(facing) * 2.0], facing)
			game.food_pos = Vector2i(10, 10)
			var events := game.advance(0.2)
			_check(game.ended and not game.won and events.size() == 1 and events[0]["type"] == "dead", "all six levels end on every board edge")
			_check(game.snake[0].distance_to(origin) <= 0.21, "wall collision never teleports the head to the opposite side")
	game.start(0, 0, 7)
	_pose(game, [Vector2(23, 4), Vector2(21, 4)])
	game.advance(0.02)
	var corner := game.snake[0]
	game.set_direction(Vector2i.UP)
	game.advance(0.1)
	_check(not game.ended and is_equal_approx(game.snake[0].x, corner.x), "instant turn avoids the wall without waiting for a cell boundary")

func _test_food_and_growth() -> void:
	for kind in ["normal", "bonus", "slow"]:
		var game := SnakeLogic.new()
		game.start(0, 0, 8)
		game.food_pos = Vector2i(game.snake[0]) + Vector2i.RIGHT
		game.food_kind = kind
		game.food_timer = 8.0
		game.advance(0.1)
		_check(game.score == 0, "food does not score before visible contact")
		var events := game.advance(0.02)
		_check(events.size() == 1 and events[0]["kind"] == kind, "food emits one correctly typed event")
		_check(game.score == {"normal": 10, "bonus": 25, "slow": 15}[kind] and game.food_eaten == 1, "all food kinds score correctly and count once")
		_check(game.target_length == 3.0 and game.body_length < game.target_length, "growth is gradual rather than a tail jump")
		var tail := game.trail[game.trail.size() - 1]
		game.advance(0.05)
		_check(game.trail[game.trail.size() - 1].is_equal_approx(tail), "tail remains in place while the body length grows")
		if kind == "slow":
			_check(game.slow_timer > 4.0 and game.current_interval() > game.step_interval, "slow food applies a five-second effect")
			game.tick_timers(6.0)
			_check(game.current_interval() == game.step_interval, "slow effect expires")
	var game := SnakeLogic.new()
	game.start()
	game.food_kind = "bonus"
	game.food_timer = 0.01
	game.advance(0.02)
	_check(game.food_kind == "normal", "expired bonus converts into normal food")

func _test_campaign() -> void:
	var game := SnakeLogic.new()
	game.start(0, 0, 42)
	_check(not game.advance_level(), "unfinished level cannot be skipped")
	var total := 0
	for level_index in range(SnakeLogic.LEVELS.size()):
		_check(game.level_index == level_index and game.score == total, "levels advance sequentially with the score carried over")
		_check(game.food_eaten == 0 and game.snake.size() == 3 and game.slow_timer == 0.0, "next level resets attempt state")
		_check(game.obstacles.size() == int(game.level()["obstacles"]), "each level applies its own terrain")
		var goal: int = game.level()["goal"]
		for count in range(goal):
			_pose(game, [Vector2(5, 5)], Vector2i.RIGHT)
			game.obstacles.clear()
			game.food_pos = Vector2i(6, 5)
			game.food_kind = ["normal", "bonus", "slow"][count % 3]
			game.food_timer = 8.0
			game.slow_timer = 0.0
			var events := game.advance(game.current_interval() * 0.6)
			total += [10, 25, 15][count % 3]
			_check(events.size() == 1 and events[0]["type"] == ("clear" if count == goal - 1 else "eat"), "goal clears the level exactly once")
			_check(game.score == total and game.food_eaten == count + 1, "special food counts once toward the goal")
		_check(game.ended and game.won and game.advance(1.0).is_empty(), "cleared level stops simulation")
		_check(game.advance_level(42 + level_index) == (level_index < SnakeLogic.LEVELS.size() - 1), "campaign stops after the sixth level")
	game.start(3, 90, 50)
	game.score = 125
	game.food_eaten = 3
	game.ended = true
	game.slow_timer = 2.0
	game.retry_level(50)
	_check(game.level_index == 3 and game.score == 90 and game.food_eaten == 0 and not game.ended, "retry restores the current level checkpoint")
	game.start(3, 5000, 50)
	_check(is_equal_approx(game.step_interval, float(game.level()["interval"])), "carried score does not distort the level speed")
	game.start()
	_check(game.level_index == 0 and game.score == 0, "new campaign resets level and score")

func _test_generation() -> void:
	for seed_value in range(25):
		var game := SnakeLogic.new()
		game.start(5, 0, seed_value)
		_check(game.obstacles.size() == 36 and game._obstacles_connected(), "obstacle generation leaves a connected playable area")
		for cell in game.obstacles:
			var offset := Vector2(cell) - game.snake[0]
			_check(absf(offset.x) >= 4.0 or absf(offset.y) >= 3.0, "initial head has a clear movement zone")
		for count in range(10):
			game._spawn_food()
			_check(not game._food_blocked(game.food_pos), "food never overlaps the actual body path or obstacles")
	var game := SnakeLogic.new()
	game.start()
	_pose(game, [Vector2(5.3, 5.2), Vector2(5.3, 7.2), Vector2(8.3, 7.2)])
	_check(game._food_blocked(Vector2i(5, 6)), "food exclusion checks path between sampled body segments")

func _test_full_board() -> void:
	var game := SnakeLogic.new()
	game.start(0, 0, 10)
	_pose(game, [Vector2.ZERO])
	game.obstacles.clear()
	for y in range(SnakeLogic.HEIGHT):
		for x in range(SnakeLogic.WIDTH):
			if Vector2i(x, y) not in [Vector2i.ZERO, Vector2i.RIGHT]:
				game.obstacles.append(Vector2i(x, y))
	game.food_pos = Vector2i.RIGHT
	game.food_kind = "normal"
	game.advance(0.2)
	_check(game.ended and game.won, "no free food cell clears the level without looping")

func _test_score_store() -> void:
	var path := "user://test_torben_snake_scores_%s.cfg" % Time.get_ticks_usec()
	_check(ScoreStore.load_best(path) == 0, "missing save defaults to zero")
	_check(ScoreStore.load_unlocked(6, path) == 1, "new save unlocks only level one")
	_check(ScoreStore.save_progress(125, 1, 6, path) == OK, "save succeeds")
	_check(ScoreStore.load_best(path) == 125, "highest score survives reloading")
	_check(ScoreStore.load_unlocked(6, path) == 1, "score save keeps level one unlocked")
	_check(ScoreStore.save_progress(100, 3, 6, path) == OK, "unlock progress saves successfully")
	_check(ScoreStore.load_best(path) == 125 and ScoreStore.load_unlocked(6, path) == 3, "saving progress preserves the previous highest score")
	ScoreStore.save_progress(140, 2, 6, path)
	_check(ScoreStore.load_best(path) == 140 and ScoreStore.load_unlocked(6, path) == 3, "replaying earlier levels cannot relock progress")
	ScoreStore.save_progress(150, 1, 6, path)
	_check(ScoreStore.load_unlocked(6, path) == 3, "high-score updates preserve unlocked levels")
	ScoreStore.save_progress(150, 99, 6, path)
	_check(ScoreStore.load_unlocked(6, path) == 6, "unlock progress cannot exceed the final level")
	var config := ConfigFile.new()
	config.set_value("score", "best", "invalid")
	config.set_value("progress", "unlocked_levels", "invalid")
	config.save(path)
	_check(ScoreStore.load_best(path) == 0, "invalid stored value defaults safely")
	_check(ScoreStore.load_unlocked(6, path) == 1, "invalid progress defaults safely")
	config.set_value("progress", "unlocked_levels", -5)
	config.save(path)
	_check(ScoreStore.load_unlocked(6, path) == 1, "negative progress cannot lock the first level")
	ScoreStore.save_progress(-20, 1, 6, path)
	_check(ScoreStore.load_best(path) == 0, "negative score is clamped")
	DirAccess.remove_absolute(path)

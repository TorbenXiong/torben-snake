extends RefCounted
class_name SnakeGameLogic

const WIDTH := 24
const HEIGHT := 18
const HEAD_RADIUS := 0.29
const BODY_RADIUS := 0.245
const FOOD_RADIUS := 0.19
const MAX_TRAVEL_STEP := 0.04
const NECK_LENGTH := 1.15
const LEVELS := [
	{"title": "初入霓虹", "goal": 5, "interval": 0.20, "obstacles": 0},
	{"title": "疾速边境", "goal": 7, "interval": 0.18, "obstacles": 0},
	{"title": "方块巡航", "goal": 8, "interval": 0.165, "obstacles": 12},
	{"title": "密集回廊", "goal": 9, "interval": 0.15, "obstacles": 20},
	{"title": "封锁迷阵", "goal": 10, "interval": 0.135, "obstacles": 28},
	{"title": "极速终章", "goal": 12, "interval": 0.12, "obstacles": 36},
]

var level_index := 0
var level_start_score := 0
var food_eaten := 0
var snake: Array[Vector2] = []
var trail := PackedVector2Array()
var body_length := 2.0
var target_length := 2.0
var last_move_direction := Vector2i.RIGHT
var direction := Vector2i.RIGHT
var food_pos := Vector2i.ZERO
var food_kind := "normal"
var obstacles: Array[Vector2i] = []
var score := 0
var ended := false
var won := false
var step_interval := 0.20
var slow_timer := 0.0
var food_timer := 0.0
var rng := RandomNumberGenerator.new()

func start(index: int = 0, starting_score: int = 0, seed_value: int = -1) -> void:
	level_index = clampi(index, 0, LEVELS.size() - 1)
	level_start_score = maxi(0, starting_score)
	food_eaten = 0
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	score = level_start_score
	ended = false
	won = false
	slow_timer = 0.0
	food_timer = 0.0
	step_interval = level()["interval"]
	var center := Vector2(WIDTH / 2, HEIGHT / 2)
	set_pose(PackedVector2Array([center, center + Vector2.LEFT * 2.0]), Vector2i.RIGHT)
	obstacles.clear()
	_generate_obstacles(level()["obstacles"])
	_spawn_food()

func level() -> Dictionary:
	return LEVELS[level_index]

func is_final_level() -> bool:
	return level_index == LEVELS.size() - 1

func advance_level(seed_value: int = -1) -> bool:
	if not won or not ended or is_final_level():
		return false
	start(level_index + 1, score, seed_value)
	return true

func retry_level(seed_value: int = -1) -> void:
	# Discard this attempt's points so retries cannot accumulate duplicate food scores.
	start(level_index, level_start_score, seed_value)

func set_direction(new_direction: Vector2i) -> void:
	if ended:
		return
	if new_direction not in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		return
	if new_direction == -direction:
		return
	# Two key events without travel must not turn straight back into the neck.
	if new_direction == -last_move_direction and direction != last_move_direction:
		return
	if new_direction == direction:
		return
	if trail.size() > 1 and not trail[0].is_equal_approx(trail[1]):
		trail.insert(0, trail[0])
	direction = new_direction

func set_pose(path: PackedVector2Array, facing: Vector2i) -> void:
	trail = path.duplicate()
	if trail.size() == 1:
		trail.append(trail[0])
	direction = facing
	last_move_direction = facing
	body_length = 0.0
	for index in range(1, trail.size()):
		body_length += trail[index - 1].distance_to(trail[index])
	target_length = body_length
	if not (trail[0] - trail[1]).normalized().is_equal_approx(Vector2(facing)):
		trail.insert(0, trail[0])
	_refresh_snake()

func tick_timers(delta: float) -> void:
	if slow_timer > 0.0:
		slow_timer = maxf(0.0, slow_timer - delta)
	if food_kind == "bonus":
		food_timer = maxf(0.0, food_timer - delta)
		if food_timer == 0.0:
			food_kind = "normal"

func current_interval() -> float:
	return step_interval * (1.42 if slow_timer > 0.0 else 1.0)

func advance(delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var remaining := maxf(0.0, delta)
	# Spatial substeps prevent tunnelling without imposing a turn or movement timer.
	while remaining > 0.000001 and not ended:
		var interval := current_interval()
		var distance := minf(MAX_TRAVEL_STEP, remaining / interval)
		var elapsed := distance * interval
		var next := trail[0] + Vector2(direction) * distance
		if _collides(next, distance):
			ended = true
			events.append({"type": "dead", "position": snake[0]})
			break
		tick_timers(elapsed)
		remaining -= elapsed
		trail[0] = next
		last_move_direction = direction
		body_length = minf(target_length, body_length + distance)
		_trim_trail()
		_refresh_snake()
		var food := Vector2(food_pos)
		if trail[0].distance_squared_to(food) <= pow(HEAD_RADIUS + FOOD_RADIUS, 2):
			var eaten_kind := food_kind
			var position := trail[0]
			_consume_food()
			events.append({"type": "clear" if won else "eat", "kind": eaten_kind, "position": position})
	return events

func _consume_food() -> void:
	target_length += 1.0
	match food_kind:
		"bonus":
			score += 25
		"slow":
			score += 15
			slow_timer = 5.0
		_:
			score += 10
	food_eaten += 1
	step_interval = maxf(0.075, float(level()["interval"]) - float(food_eaten) * 0.0025)
	_refresh_snake()
	if food_eaten >= int(level()["goal"]):
		won = true
		ended = true
		return
	if not _spawn_food():
		won = true
		ended = true

func _collides(point: Vector2, travel: float) -> bool:
	if point.x < -0.5 + HEAD_RADIUS or point.x > WIDTH - 0.5 - HEAD_RADIUS or point.y < -0.5 + HEAD_RADIUS or point.y > HEIGHT - 0.5 - HEAD_RADIUS:
		return true
	for cell in obstacles:
		var center := Vector2(cell)
		var closest := point.clamp(center - Vector2.ONE * 0.38, center + Vector2.ONE * 0.38)
		if point.distance_squared_to(closest) <= HEAD_RADIUS * HEAD_RADIUS:
			return true
	# Ignore the attached neck and the portion of tail that vacates this substep.
	var tail_limit := body_length - maxf(0.0, travel - (target_length - body_length))
	var traversed := 0.0
	for index in range(1, trail.size()):
		var a := trail[index - 1]
		var b := trail[index]
		var length := a.distance_to(b)
		if length < 0.000001:
			continue
		var start := maxf(NECK_LENGTH, traversed)
		var end := minf(tail_limit, traversed + length)
		if end > start:
			var segment_start := a.lerp(b, (start - traversed) / length)
			var segment_end := a.lerp(b, (end - traversed) / length)
			var closest := Geometry2D.get_closest_point_to_segment(point, segment_start, segment_end)
			if point.distance_squared_to(closest) < pow(HEAD_RADIUS + BODY_RADIUS, 2):
				return true
		traversed += length
	return false

func _trim_trail() -> void:
	var remaining := body_length
	for index in range(1, trail.size()):
		var length := trail[index - 1].distance_to(trail[index])
		if length >= remaining and length > 0.000001:
			trail[index] = trail[index - 1].lerp(trail[index], remaining / length)
			trail.resize(index + 1)
			return
		remaining -= length

func _point_at(distance: float) -> Vector2:
	for index in range(1, trail.size()):
		var length := trail[index - 1].distance_to(trail[index])
		if length >= distance and length > 0.000001:
			return trail[index - 1].lerp(trail[index], distance / length)
		distance -= length
	return trail[trail.size() - 1]

func _refresh_snake() -> void:
	snake.clear()
	for index in range(int(ceil(target_length)) + 1):
		snake.append(_point_at(minf(float(index), body_length)))

func _food_blocked(cell: Vector2i) -> bool:
	if obstacles.has(cell):
		return true
	var point := Vector2(cell)
	for index in range(1, trail.size()):
		var a := trail[index - 1]
		var b := trail[index]
		var closest := Geometry2D.get_closest_point_to_segment(point, a, b)
		if point.distance_squared_to(closest) < 0.75 * 0.75:
			return true
	return false

func _generate_obstacles(count: int) -> void:
	var center := Vector2i(WIDTH / 2, HEIGHT / 2)
	var attempts := 0
	while obstacles.size() < count and attempts < 400:
		attempts += 1
		var candidate := Vector2i(rng.randi_range(1, WIDTH - 2), rng.randi_range(1, HEIGHT - 2))
		if abs(candidate.x - center.x) < 4 and abs(candidate.y - center.y) < 3:
			continue
		if not obstacles.has(candidate) and not _food_blocked(candidate):
			obstacles.append(candidate)
			# Keep the empty board connected so food cannot appear behind an enclosure.
			if not _obstacles_connected():
				obstacles.pop_back()

func _obstacles_connected() -> bool:
	var start_cell := Vector2i(snake[0].round())
	var visited := {start_cell: true}
	var queue: Array[Vector2i] = [start_cell]
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for offset in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var next_cell: Vector2i = cell + offset
			if next_cell.x < 0 or next_cell.x >= WIDTH or next_cell.y < 0 or next_cell.y >= HEIGHT:
				continue
			if not obstacles.has(next_cell) and not visited.has(next_cell):
				visited[next_cell] = true
				queue.append(next_cell)
	return visited.size() == WIDTH * HEIGHT - obstacles.size()

func _spawn_food() -> bool:
	var free_cells: Array[Vector2i] = []
	for y in range(HEIGHT):
		for x in range(WIDTH):
			var candidate := Vector2i(x, y)
			if not _food_blocked(candidate):
				free_cells.append(candidate)
	if free_cells.is_empty():
		return false
	food_pos = free_cells[rng.randi_range(0, free_cells.size() - 1)]
	food_timer = 0.0
	var roll := rng.randf()
	if roll < 0.13:
		food_kind = "bonus"
		food_timer = 8.0
	elif roll < 0.23:
		food_kind = "slow"
	else:
		food_kind = "normal"
	return true

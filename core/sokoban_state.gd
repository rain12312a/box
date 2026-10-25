class_name SokobanState
extends RefCounted
## Pure game rules for one level: movement, pushing, undo/redo, win detection.
## Rendering listens to signals and never mutates this object directly.

signal moved(result: Dictionary)
signal undone(record: Dictionary)
signal redone(record: Dictionary)
signal restarted
signal solved
## Emitted when a purchased item mutates the board (wall break, pull, teleport).
signal tool_applied(record: Dictionary)

var width := 0
var height := 0
var walls: Dictionary = {}
var goals: Dictionary = {}
var boxes: Dictionary = {}
## Temporary hazard rubble: blocks like a wall but expires after a few seconds.
var temp_walls: Dictionary = {}
var player := Vector2i(-1, -1)

var moves := 0
var pushes := 0
var solved_state := false
## Set when the level was finished by an item instead of by playing it.
var cheated := false

var _initial_boxes: Dictionary = {}
var _initial_player := Vector2i(-1, -1)
var _initial_walls: Dictionary = {}
var _history: Array = []
var _redo: Array = []


func setup(level: LevelData) -> void:
	width = level.width
	height = level.height
	walls = level.walls.duplicate()
	goals = level.goals.duplicate()
	boxes = level.boxes.duplicate()
	player = level.player
	_initial_boxes = boxes.duplicate()
	_initial_player = player
	_initial_walls = walls.duplicate()
	moves = 0
	pushes = 0
	solved_state = false
	cheated = false
	temp_walls.clear()
	_history.clear()
	_redo.clear()


func reset() -> void:
	walls = _initial_walls.duplicate()
	boxes = _initial_boxes.duplicate()
	player = _initial_player
	moves = 0
	pushes = 0
	solved_state = false
	cheated = false
	temp_walls.clear()
	_history.clear()
	_redo.clear()
	restarted.emit()


## `chain` is how many crates may be shoved at once (hydraulic ram upgrade).
func try_move(dir: Vector2i, chain := 1) -> Dictionary:
	var result := {
		"moved": false, "blocked": false, "pushed": false,
		"player_from": player, "player_to": player,
		"box_from": Vector2i(-1, -1), "box_to": Vector2i(-1, -1),
		"boxes_moved": [],
	}
	if solved_state:
		return result
	var target := player + dir
	if _is_wall(target):
		result["blocked"] = true
		return result
	var pushed := false
	var box_from := Vector2i(-1, -1)
	var box_to := Vector2i(-1, -1)
	var boxes_moved: Array = []
	if boxes.has(target):
		var line: Array = []
		var cursor := target
		while boxes.has(cursor):
			line.append(cursor)
			cursor += dir
		if _is_wall(cursor) or line.size() > maxi(chain, 1):
			result["blocked"] = true
			result["box_from"] = target
			return result
		for i in range(line.size() - 1, -1, -1):
			var cell: Vector2i = line[i]
			boxes.erase(cell)
			boxes[cell + dir] = true
			boxes_moved.append([cell, cell + dir])
		pushed = true
		box_from = target
		box_to = target + dir
		pushes += line.size()
	var from := player
	player = target
	moves += 1
	var record := {
		"player_from": from, "player_to": target, "pushed": pushed,
		"box_from": box_from, "box_to": box_to, "boxes_moved": boxes_moved,
	}
	_history.append(record)
	_redo.clear()
	var was_solved := solved_state
	solved_state = check_solved()
	result["moved"] = true
	result["pushed"] = pushed
	result["player_to"] = target
	result["box_from"] = box_from
	result["box_to"] = box_to
	result["boxes_moved"] = boxes_moved
	moved.emit(result)
	if solved_state and not was_solved:
		solved.emit()
	return result


func undo() -> bool:
	if _history.is_empty():
		return false
	var record: Dictionary = _history.pop_back()
	match str(record.get("kind", "move")):
		"wall":
			walls[record["wall"]] = true
		"jump", "pass", "phase", "warp":
			player = record["player_from"]
			moves -= 1
		"pull":
			var pull_from: Vector2i = record["box_to"]
			var pull_to: Vector2i = record["box_from"]
			boxes.erase(pull_from)
			boxes[pull_to] = true
			player = record["player_from"]
			moves -= 1
		"teleport":
			var tp_from: Vector2i = record["box_to"]
			var tp_to: Vector2i = record["box_from"]
			boxes.erase(tp_from)
			boxes[tp_to] = true
		_:
			var player_from: Vector2i = record["player_from"]
			if bool(record["pushed"]):
				var moved: Array = record.get("boxes_moved", [])
				if moved.is_empty():
					moved = [[record["box_from"], record["box_to"]]]
				# recorded farthest-first, so undo near-first
				for i in range(moved.size() - 1, -1, -1):
					var pair: Array = moved[i]
					boxes.erase(pair[1])
					boxes[pair[0]] = true
				pushes -= moved.size()
			player = player_from
			moves -= 1
	solved_state = check_solved()
	_redo.append(record)
	undone.emit(record)
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var record: Dictionary = _redo.pop_back()
	match str(record.get("kind", "move")):
		"wall":
			walls.erase(record["wall"])
		"jump", "pass", "phase", "warp":
			player = record["player_to"]
			moves += 1
		"pull":
			var pull_from: Vector2i = record["box_from"]
			var pull_to: Vector2i = record["box_to"]
			boxes.erase(pull_from)
			boxes[pull_to] = true
			player = record["player_to"]
			moves += 1
		"teleport":
			var tp_from: Vector2i = record["box_from"]
			var tp_to: Vector2i = record["box_to"]
			boxes.erase(tp_from)
			boxes[tp_to] = true
		_:
			var player_to: Vector2i = record["player_to"]
			player = player_to
			if bool(record["pushed"]):
				var moved: Array = record.get("boxes_moved", [])
				if moved.is_empty():
					moved = [[record["box_from"], record["box_to"]]]
				for pair in moved:
					boxes.erase(pair[0])
					boxes[pair[1]] = true
				pushes += moved.size()
			moves += 1
	solved_state = check_solved()
	_history.append(record)
	redone.emit(record)
	if solved_state:
		solved.emit()
	return true


## Jump actuator: hop over the crate in front and land on the free cell beyond.
func jump_over(dir: Vector2i) -> bool:
	if solved_state:
		return false
	var target := player + dir
	var landing := player + dir + dir
	if not boxes.has(target):
		return false
	if not _is_open(landing):
		return false
	_move_player_only("jump", landing)
	return true


## Claw arm: walk straight through a whole line of crates without moving them.
func pass_through_crates(dir: Vector2i) -> bool:
	if solved_state:
		return false
	if not boxes.has(player + dir):
		return false
	var landing := player + dir
	while boxes.has(landing):
		landing += dir
	if not _is_open(landing):
		return false
	_move_player_only("pass", landing)
	return true


## Phase visor: walk straight through one wall cell.
func phase_through(dir: Vector2i) -> bool:
	if solved_state:
		return false
	if not _is_wall(player + dir):
		return false
	var landing := player + dir + dir
	if not _in_bounds(landing) or not _is_open(landing):
		return false
	_move_player_only("phase", landing)
	return true


## Warp pack: teleport the worker onto any open cell.
func warp_player(to: Vector2i) -> bool:
	if solved_state or to == player:
		return false
	if not _is_open(to):
		return false
	_move_player_only("warp", to)
	return true


func _move_player_only(kind: String, landing: Vector2i) -> void:
	var from := player
	player = landing
	moves += 1
	_history.append({"kind": kind, "player_from": from, "player_to": landing})
	_redo.clear()
	var was_solved := solved_state
	solved_state = check_solved()
	tool_applied.emit(_history.back())
	if solved_state and not was_solved:
		solved.emit()


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height


func _is_open(pos: Vector2i) -> bool:
	return _in_bounds(pos) and not _is_wall(pos) and not boxes.has(pos)


## C4: blow up one adjacent wall cell.
func break_wall(pos: Vector2i) -> bool:
	if solved_state or not walls.has(pos):
		return false
	walls.erase(pos)
	_record_tool({"kind": "wall", "wall": pos})
	tool_applied.emit(_history.back())
	return true


## Pull rope: the player steps forward and the crate behind is dragged along.
func pull(dir: Vector2i) -> Dictionary:
	var result := {
		"moved": false, "blocked": false, "pulled": false,
		"player_from": player, "player_to": player,
		"box_from": Vector2i(-1, -1), "box_to": Vector2i(-1, -1),
	}
	if solved_state:
		return result
	var target := player + dir
	var behind := player - dir
	if not boxes.has(behind) or _is_wall(target) or boxes.has(target):
		result["blocked"] = true
		return result
	boxes.erase(behind)
	boxes[player] = true
	var from := player
	player = target
	moves += 1
	var record := {
		"kind": "pull", "player_from": from, "player_to": target,
		"box_from": behind, "box_to": from,
	}
	_history.append(record)
	_redo.clear()
	var was_solved := solved_state
	solved_state = check_solved()
	result["moved"] = true
	result["pulled"] = true
	result["player_to"] = target
	result["box_from"] = behind
	result["box_to"] = from
	tool_applied.emit(record)
	if solved_state and not was_solved:
		solved.emit()
	return result


## Crane: drop a crate anywhere walkable without pushing it.
func teleport_box(from: Vector2i, to: Vector2i) -> bool:
	if solved_state or from == to or not boxes.has(from):
		return false
	if _is_wall(to) or boxes.has(to) or to == player:
		return false
	boxes.erase(from)
	boxes[to] = true
	_record_tool({"kind": "teleport", "box_from": from, "box_to": to})
	var was_solved := solved_state
	solved_state = check_solved()
	tool_applied.emit(_history.back())
	if solved_state and not was_solved:
		solved.emit()
	return true


## Outside contract: snap every crate onto a goal and finish the level.
func force_win() -> void:
	if solved_state:
		return
	var goal_cells := goals.keys()
	var box_cells := boxes.keys()
	for i in mini(goal_cells.size(), box_cells.size()):
		boxes.erase(box_cells[i])
		boxes[goal_cells[i]] = true
	cheated = true
	solved_state = true
	solved.emit()


func _record_tool(record: Dictionary) -> void:
	_history.append(record)
	_redo.clear()


func can_undo() -> bool:
	return not _history.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func is_solved() -> bool:
	return check_solved()


func check_solved() -> bool:
	if boxes.size() != goals.size():
		return false
	for pos in boxes.keys():
		if not goals.has(pos):
			return false
	return true


func goals_left() -> int:
	var n := 0
	for pos in goals.keys():
		if not boxes.has(pos):
			n += 1
	return n


func box_positions() -> Array:
	return boxes.keys()


func has_box(pos: Vector2i) -> bool:
	return boxes.has(pos)


func history_size() -> int:
	return _history.size()


func last_move() -> Dictionary:
	if _history.is_empty():
		return {}
	return _history[-1]


func _is_wall(pos: Vector2i) -> bool:
	return walls.has(pos) or temp_walls.has(pos)


## Temporary hazards (falling rubble) block movement like walls but expire.
func set_temp_wall(pos: Vector2i, active: bool) -> void:
	if active:
		temp_walls[pos] = true
	else:
		temp_walls.erase(pos)


func clear_temp_walls() -> void:
	temp_walls.clear()


func remove_box(pos: Vector2i) -> void:
	boxes.erase(pos)


func floor_cells() -> Array:
	var cells: Array = []
	for y in height:
		for x in width:
			var pos := Vector2i(x, y)
			if not _is_wall(pos):
				cells.append(pos)
	return cells


func snapshot() -> Dictionary:
	return {
		"boxes": boxes.duplicate(),
		"player": player,
		"moves": moves,
		"pushes": pushes,
	}

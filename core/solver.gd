class_name SokobanSolver
extends RefCounted
## Push-optimal A* solver with static/freeze deadlock pruning.
##
## Used by the editor (validate + compute par) and by the in-game hint system.
## Levels are limited to 127 cells and 7 crates so a full box configuration fits
## in one 64 bit integer, which keeps the visited-state dictionary fast.

const MAX_CELLS := 127
const MAX_BOXES := 7
const INF := 1 << 30
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

var width := 0
var height := 0
var cell_count := 0
var goal_count := 0
var can_solve := false

var _wall := PackedByteArray()
var _goal := PackedByteArray()
var _nb: Array = []
var _goal_dist := PackedInt32Array()
var _dead := PackedByteArray()
var _blocks: Array = []
var _cell_blocks: Array = []

var _seen := PackedInt32Array()
var _dist := PackedInt32Array()
var _occ := PackedInt32Array()
var _occ_counter := 0
var _cocc := PackedInt32Array()
var _cand_counter := 0
var _stamp := 0
var _queue := PackedInt32Array()

var _best: Dictionary = {}
var _heap: Array = []
var _parent_ids := PackedInt32Array()
var _node_dir := PackedInt32Array()
var _node_walk := PackedInt32Array()
var _node_box := PackedInt32Array()
var _start_boxes: Array = []
var _start_player := 0


func setup_from_level(level: LevelData) -> bool:
	return setup(level.width, level.height, level.walls, level.goals,
			level.box_positions(), level.player)


func setup_from_state(state: SokobanState) -> bool:
	return setup(state.width, state.height, state.walls, state.goals,
			state.box_positions(), state.player)


func setup(w: int, h: int, walls: Dictionary, goals: Dictionary, boxes: Array,
		player: Vector2i) -> bool:
	width = w
	height = h
	cell_count = w * h
	goal_count = goals.size()
	can_solve = false
	if cell_count <= 0 or cell_count > MAX_CELLS or boxes.size() > MAX_BOXES:
		return false
	if boxes.size() != goals.size() or boxes.is_empty():
		return false
	if player.x < 0 or player.y < 0 or player.x >= w or player.y >= h:
		return false
	_wall = PackedByteArray()
	_goal = PackedByteArray()
	_wall.resize(cell_count)
	_goal.resize(cell_count)
	_wall.fill(0)
	_goal.fill(0)
	for y in h:
		for x in w:
			var idx := y * w + x
			if walls.has(Vector2i(x, y)):
				_wall[idx] = 1
			if goals.has(Vector2i(x, y)):
				_goal[idx] = 1
	_nb.clear()
	_nb.resize(cell_count)
	for y in h:
		for x in w:
			var idx := y * w + x
			var list := PackedInt32Array([-1, -1, -1, -1])
			for d in 4:
				var nx: int = x + DIRS[d].x
				var ny: int = y + DIRS[d].y
				if nx >= 0 and ny >= 0 and nx < w and ny < h:
					list[d] = ny * w + nx
			_nb[idx] = list
	_compute_goal_distances(goals)
	_compute_dead_cells(goals)
	_build_blocks()
	_start_boxes.clear()
	for pos in boxes:
		_start_boxes.append(pos.y * w + pos.x)
	_start_boxes.sort()
	_start_player = player.y * w + player.x
	_seen = PackedInt32Array()
	_seen.resize(cell_count)
	_seen.fill(0)
	_dist = PackedInt32Array()
	_dist.resize(cell_count)
	_occ = PackedInt32Array()
	_occ.resize(cell_count)
	_occ.fill(0)
	_cocc = PackedInt32Array()
	_cocc.resize(cell_count)
	_cocc.fill(0)
	_occ_counter = 0
	_cand_counter = 0
	_stamp = 0
	can_solve = _start_boxes.size() == goal_count
	return can_solve


func _compute_goal_distances(goals: Dictionary) -> void:
	_goal_dist = PackedInt32Array()
	_goal_dist.resize(cell_count)
	_goal_dist.fill(INF)
	var queue: Array = []
	for pos in goals.keys():
		var idx: int = pos.y * width + pos.x
		_goal_dist[idx] = 0
		queue.append(idx)
	var head := 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		var nd: int = _goal_dist[c] + 1
		for n in _nb[c]:
			if n >= 0 and _wall[n] == 0 and _goal_dist[n] == INF:
				_goal_dist[n] = nd
				queue.append(n)


func _compute_dead_cells(goals: Dictionary) -> void:
	var good := PackedByteArray()
	good.resize(cell_count)
	good.fill(0)
	var queue: Array = []
	for pos in goals.keys():
		var idx: int = pos.y * width + pos.x
		good[idx] = 1
		queue.append(idx)
	var head := 0
	while head < queue.size():
		var c: int = queue[head]
		head += 1
		for d in 4:
			var b: int = _nb[c][(d + 2) % 4]
			if b < 0 or _wall[b] == 1:
				continue
			var behind: int = _nb[b][(d + 2) % 4]
			if behind < 0 or _wall[behind] == 1:
				continue
			if good[b] == 0:
				good[b] = 1
				queue.append(b)
	_dead = PackedByteArray()
	_dead.resize(cell_count)
	for i in cell_count:
		_dead[i] = 0 if good[i] == 1 else 1


func _build_blocks() -> void:
	_blocks.clear()
	_cell_blocks.clear()
	_cell_blocks.resize(cell_count)
	for i in cell_count:
		_cell_blocks[i] = []
	for y in height - 1:
		for x in width - 1:
			var a := y * width + x
			var b := a + 1
			var c := a + width
			var d := c + 1
			var bid := _blocks.size()
			_blocks.append([a, b, c, d])
			_cell_blocks[a].append(bid)
			_cell_blocks[b].append(bid)
			_cell_blocks[c].append(bid)
			_cell_blocks[d].append(bid)


# --------------------------------------------------------------------------- #
# Search
# --------------------------------------------------------------------------- #
func solve(max_seconds := 1.5, max_nodes := 60000, weight := 1) -> Dictionary:
	if not can_solve:
		return {"solvable": false, "reason": "unsupported", "nodes": 0}
	var start_time := Time.get_ticks_msec()
	var deadline := start_time + int(max_seconds * 1000.0)
	var start_boxes: Array = _start_boxes.duplicate()
	var start_player := _start_player
	var h0 := _heuristic(start_boxes)
	_best.clear()
	_heap.clear()
	_parent_ids = PackedInt32Array([-1])
	_node_dir = PackedInt32Array([-1])
	_node_walk = PackedInt32Array([0])
	_node_box = PackedInt32Array([-1])
	_heap_push([h0 * weight, 0, start_player, start_boxes, 0])
	var nodes := 0
	while not _heap.is_empty():
		var entry: Array = _heap_pop()
		var boxes: Array = entry[3]
		var g: int = entry[1]
		var token := _mark_boxes(boxes)
		var rep := _reach(int(entry[2]), token)
		var key := _key(rep, boxes)
		if _best.has(key) and int(_best[key]) <= g:
			continue
		_best[key] = g
		nodes += 1
		if nodes >= max_nodes:
			return {"solvable": null, "reason": "nodes", "nodes": nodes}
		if (nodes & 127) == 0 and Time.get_ticks_msec() > deadline:
			return {"solvable": null, "reason": "time", "nodes": nodes}
		if boxes.size() == goal_count and _all_on_goals(boxes):
			var path: Array = []
			var moves := 0
			var cur: int = int(entry[4])
			while _parent_ids[cur] >= 0:
				var d: int = _node_dir[cur]
				var walk: int = _node_walk[cur]
				path.append({"dir": d, "walk": walk, "box": _node_box[cur]})
				moves += walk
				cur = _parent_ids[cur]
			path.reverse()
			return {"solvable": true, "pushes": g, "moves": moves,
					"path": path, "nodes": nodes,
					"elapsed": Time.get_ticks_msec() - start_time}
		var stamp := _stamp
		for bi in boxes.size():
			var b: int = boxes[bi]
			for d in 4:
				var target: int = _nb[b][d]
				var stand: int = _nb[b][(d + 2) % 4]
				if target < 0 or stand < 0:
					continue
				if _wall[target] == 1 or _occ[target] == token:
					continue
				if _seen[stand] != stamp:
					continue
				var nboxes: Array = boxes.duplicate()
				nboxes[bi] = target
				nboxes.sort()
				var box_token := _mark_candidate(nboxes)
				if _deadlocked(target, box_token):
					continue
				var walk := _dist[stand] + 1
				var nh := _heuristic(nboxes)
				var nid := _parent_ids.size()
				_parent_ids.append(int(entry[4]))
				_node_dir.append(d)
				_node_walk.append(walk)
				_node_box.append(b)
				_heap_push([g + 1 + nh * weight, g + 1, target, nboxes, nid])
	return {"solvable": false, "nodes": nodes, "reason": "exhausted"}


func _mark_boxes(boxes: Array) -> int:
	_occ_counter += 1
	for b in boxes:
		_occ[b] = _occ_counter
	return _occ_counter


func _mark_candidate(boxes: Array) -> int:
	_cand_counter += 1
	for b in boxes:
		_cocc[b] = _cand_counter
	return _cand_counter


func _heuristic(boxes: Array) -> int:
	var h := 0
	for b in boxes:
		h += _goal_dist[b]
	return h


func _all_on_goals(boxes: Array) -> bool:
	for b in boxes:
		if _goal[b] == 0:
			return false
	return true


func _reach(player_idx: int, token: int) -> int:
	_stamp += 1
	var stamp := _stamp
	_seen[player_idx] = stamp
	_dist[player_idx] = 0
	_queue.clear()
	_queue.append(player_idx)
	var head := 0
	var rep := player_idx
	while head < _queue.size():
		var c: int = _queue[head]
		head += 1
		if c < rep:
			rep = c
		var nd: int = _dist[c] + 1
		for n in _nb[c]:
			if n < 0 or _seen[n] == stamp or _wall[n] == 1 or _occ[n] == token:
				continue
			_seen[n] = stamp
			_dist[n] = nd
			_queue.append(n)
	return rep


func _deadlocked(moved_target: int, token: int) -> bool:
	if _dead[moved_target] == 1:
		return true
	for bid in _cell_blocks[moved_target]:
		var block: Array = _blocks[bid]
		var all_blocked := true
		var bad_box := false
		for c in block:
			var is_box := _cocc[c] == token
			if _wall[c] == 0 and not is_box:
				all_blocked = false
				break
			if is_box and _goal[c] == 0:
				bad_box = true
		if all_blocked and bad_box:
			return true
	return false


func _key(rep: int, boxes: Array) -> int:
	var packed := 0
	for i in boxes.size():
		packed |= int(boxes[i]) << (7 * i)
	return (packed << 7) | rep


# --------------------------------------------------------------------------- #
# Binary heap
# --------------------------------------------------------------------------- #
func _heap_push(entry: Array) -> void:
	_heap.append(entry)
	var i := _heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if _entry_less(_heap[i], _heap[parent]):
			var tmp: Array = _heap[i]
			_heap[i] = _heap[parent]
			_heap[parent] = tmp
			i = parent
		else:
			break


func _heap_pop() -> Array:
	var top: Array = _heap[0]
	var last: Array = _heap.pop_back()
	if not _heap.is_empty():
		_heap[0] = last
		var i := 0
		var size := _heap.size()
		while true:
			var left := i * 2 + 1
			var right := left + 1
			var smallest := i
			if left < size and _entry_less(_heap[left], _heap[smallest]):
				smallest = left
			if right < size and _entry_less(_heap[right], _heap[smallest]):
				smallest = right
			if smallest == i:
				break
			var tmp: Array = _heap[i]
			_heap[i] = _heap[smallest]
			_heap[smallest] = tmp
			i = smallest
	return top


func _entry_less(a: Array, b: Array) -> bool:
	if int(a[0]) != int(b[0]):
		return int(a[0]) < int(b[0])
	return int(a[1]) < int(b[1])

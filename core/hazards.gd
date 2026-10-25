class_name LevelHazards
extends RefCounted
## Per-chapter level hazards.
##
##  chapter 2+: falling rubble every 15 s, each block survives 10 s
##  chapter 3+: a thug that takes one step every two player actions and chases you
##  chapter 4+: a thief that does the same, grabs a crate for two turns and steals it.
##             It never spawns next to a crate, a crate pushed onto it only hands it
##             the loot, and a disposed thief comes back after 20 s.
##
## Everything is driven by the game screen: `tick(delta)` for time based hazards and
## `notify_action()` after every successful player action.

signal changed
signal caught(reason: String)
signal rubble_spawned(count: int)
signal thug_crushed(cell: Vector2i)
signal thief_killed(cell: Vector2i)
signal thief_respawned(cell: Vector2i)
signal crate_stolen(cell: Vector2i)
signal pry_interrupted(cell: Vector2i)

const COLLAPSE_INTERVAL := 15.0
const COLLAPSE_LIFETIME := 10.0
const ACTIONS_PER_ENEMY_STEP := 2
const THIEF_GRAB_TURNS := 2
const THIEF_RESPAWN_SECONDS := 20.0

const DIRS := [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

var state: SokobanState
var collapse_enabled := false
var thug_enabled := false
var thief_enabled := false

var blocks: Dictionary = {}
var thug := Vector2i(-1, -1)
var thief := Vector2i(-1, -1)
var thief_grab := 0
var thief_target := Vector2i(-1, -1)
var failed := false
## Seconds until a disposed thief shows up again; 0 while one is on the board.
var thief_respawn := 0.0

var _collapse_timer := COLLAPSE_INTERVAL
var _actions := 0
var _thug_dead := false
var _thief_dead := false
var _rng := RandomNumberGenerator.new()


## `flags` holds the editor's hazard toggles for custom levels; builtin campaign
## levels leave it empty and derive the mix from the chapter index instead.
func configure(level_state: SokobanState, chapter_index: int, builtin := true,
		seed_value := 0, flags: Dictionary = {}) -> void:
	state = level_state
	failed = false
	blocks.clear()
	thug = Vector2i(-1, -1)
	thief = Vector2i(-1, -1)
	thief_grab = 0
	thief_target = Vector2i(-1, -1)
	thief_respawn = 0.0
	_collapse_timer = COLLAPSE_INTERVAL
	_actions = 0
	_thug_dead = false
	_thief_dead = false
	collapse_enabled = false
	thug_enabled = false
	thief_enabled = false
	if seed_value != 0:
		_rng.seed = seed_value
	else:
		_rng.randomize()
	if state == null:
		return
	if not builtin:
		# hand authored level: the editor decided which hazards run
		collapse_enabled = bool(flags.get("collapse", false))
		thug_enabled = bool(flags.get("thug", false))
		thief_enabled = bool(flags.get("thief", false))
	elif chapter_index >= 1:
		collapse_enabled = true
		thug_enabled = chapter_index >= 2
		thief_enabled = chapter_index >= 3
	else:
		return
	if thug_enabled:
		thug = _far_cell()
	if thief_enabled:
		thief = _thief_spawn_cell()
	state.clear_temp_walls()


func has_any_hazard() -> bool:
	return collapse_enabled or thug_enabled or thief_enabled


func active() -> bool:
	return has_any_hazard() and not failed


# --------------------------------------------------------------------------- #
# Time driven: rubble and the thief respawn timer
# --------------------------------------------------------------------------- #
func tick(delta: float) -> void:
	if state == null or failed or state.solved_state:
		return
	_tick_thief_respawn(delta)
	if not collapse_enabled:
		return
	var expired := false
	for cell in blocks.keys():
		blocks[cell] = float(blocks[cell]) - delta
		if float(blocks[cell]) <= 0.0:
			blocks.erase(cell)
			state.set_temp_wall(cell, false)
			expired = true
	if expired:
		changed.emit()
	_collapse_timer -= delta
	if _collapse_timer <= 0.0:
		_collapse_timer += COLLAPSE_INTERVAL
		spawn_rubble()


## Public so tests can force a collapse instead of waiting 15 seconds.
func spawn_rubble() -> int:
	if state == null or failed:
		return 0
	var candidates: Array = []
	for cell in state.floor_cells():
		if blocks.has(cell) or state.boxes.has(cell):
			continue
		if cell == state.player or cell == thug or cell == thief:
			continue
		candidates.append(cell)
	if candidates.is_empty():
		return 0
	var count := 1
	if _rng.randf() < 0.55 and candidates.size() > 1:
		count = 2
	var spawned := 0
	for i in count:
		if candidates.is_empty():
			break
		var index := _rng.randi_range(0, candidates.size() - 1)
		var cell: Vector2i = candidates[index]
		candidates.remove_at(index)
		blocks[cell] = COLLAPSE_LIFETIME
		state.set_temp_wall(cell, true)
		spawned += 1
	if spawned > 0:
		rubble_spawned.emit(spawned)
		changed.emit()
	return spawned


func seconds_to_collapse() -> float:
	return maxf(_collapse_timer, 0.0)


func _tick_thief_respawn(delta: float) -> void:
	if not thief_enabled or not _thief_dead or thief_respawn <= 0.0:
		return
	thief_respawn = maxf(thief_respawn - delta, 0.0)
	if thief_respawn <= 0.0:
		respawn_thief()


## Brings a new thief onto the board once its 20 s timer ran out.
## Returns false when there is nowhere safe to put it yet.
func respawn_thief() -> bool:
	if not thief_enabled or thief.x >= 0:
		return false
	var cell := _thief_spawn_cell()
	if cell.x < 0:
		thief_respawn = 2.0
		return false
	thief = cell
	thief_target = Vector2i(-1, -1)
	thief_grab = 0
	_thief_dead = false
	thief_respawn = 0.0
	thief_respawned.emit(cell)
	changed.emit()
	return true


# --------------------------------------------------------------------------- #
# Action driven: thug and thief
# --------------------------------------------------------------------------- #
func notify_action() -> void:
	if state == null or failed or state.solved_state:
		return
	if not (thug_enabled or thief_enabled):
		return
	# a crate shoved onto the thug flattens it; the thief just runs off with the loot
	_crush_thug()
	# a crate moved out of the thief's hands resets its prying progress
	check_pry()
	_thief_takes_crate()
	if _touching_enemies():
		return
	_actions += 1
	if _actions < ACTIONS_PER_ENEMY_STEP:
		return
	_actions = 0
	if thug_enabled and not failed:
		_step_thug()
	if thief_enabled and not failed:
		_step_thief()
	_touching_enemies()
	if not failed:
		changed.emit()


func _touching_enemies() -> bool:
	if thug_enabled and state.player == thug:
		_fail("thug")
		return true
	# the worker is armoured: touching the thief disposes of it instead of failing
	if thief.x >= 0 and state.player == thief:
		_kill_thief()
	return false


## Contact kills the thief: no failure, the crate it was after is safe.
func _kill_thief() -> bool:
	if thief.x < 0:
		return false
	var cell := thief
	thief = Vector2i(-1, -1)
	thief_target = Vector2i(-1, -1)
	thief_grab = 0
	_thief_dead = true
	thief_respawn = THIEF_RESPAWN_SECONDS
	thief_killed.emit(cell)
	changed.emit()
	return true


## A crate moved out of the thief's hands (crane, rope, dynamite, rewind) wipes its
## prying progress: it has to walk to the loot and start over.
func check_pry() -> bool:
	if thief.x < 0 or thief_grab <= 0:
		return false
	if thief_target == thief and state.boxes.has(thief_target):
		return false
	var cell := thief
	thief_grab = 0
	thief_target = Vector2i(-1, -1)
	pry_interrupted.emit(cell)
	changed.emit()
	return true


## Shoving a crate onto the thief does not hurt it: it grabs the crate and is gone.
## That is an instant theft, so the run fails right there.
func _thief_takes_crate() -> bool:
	if not thief_enabled or thief.x < 0 or not state.boxes.has(thief):
		return false
	if thief_grab > 0 or thief_target == thief:
		return false
	var cell := thief
	thief = Vector2i(-1, -1)
	thief_target = Vector2i(-1, -1)
	thief_grab = 0
	state.remove_box(cell)
	crate_stolen.emit(cell)
	_fail("thief")
	return true


func _fail(reason: String) -> void:
	if failed:
		return
	failed = true
	caught.emit(reason)
	changed.emit()


func _step_thug() -> void:
	if thug.x < 0:
		return
	# the thug walks around crates (walking into one would flatten it), so the only
	# way to kill it is to shove a crate onto its tile
	var next := _first_step(thug, state.player, false, state.player)
	if next.x < 0:
		return
	thug = next
	if _crush_thug():
		return
	_touching_enemies()


## Any crate sharing the thug's tile destroys the thug for good. Crates only reach a
## thug by being pushed onto it, because the thug paths around them.
func _crush_thug() -> bool:
	if not thug_enabled or thug.x < 0 or not state.boxes.has(thug):
		return false
	var cell := thug
	thug = Vector2i(-1, -1)
	_thug_dead = true
	thug_crushed.emit(cell)
	return true


func _step_thief() -> void:
	if thief.x < 0:
		return
	check_pry()
	if thief_grab > 0:
		thief_grab += 1
		if thief_grab > THIEF_GRAB_TURNS:
			if thief_target.x >= 0 and state.boxes.has(thief_target):
				state.remove_box(thief_target)
				crate_stolen.emit(thief_target)
			thief = Vector2i(-1, -1)
			thief_target = Vector2i(-1, -1)
			thief_grab = 0
			_fail("thief")
		return
	var target := _nearest_box_cell()
	if target.x < 0:
		return
	if thief == target:
		thief_target = target
		thief_grab = 1
		return
	var next := _first_step(thief, target, true, target)
	if next.x < 0:
		return
	thief = next
	if state.boxes.has(thief):
		thief_target = thief
		thief_grab = 1
	_touching_enemies()


# --------------------------------------------------------------------------- #
# Pathfinding helpers (grid BFS over walls / rubble / crates)
# --------------------------------------------------------------------------- #
func _walkable(cell: Vector2i, boxes_passable: bool) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= state.width or cell.y >= state.height:
		return false
	if state.walls.has(cell) or state.temp_walls.has(cell):
		return false
	if not boxes_passable and state.boxes.has(cell):
		return false
	return true


func _first_step(from: Vector2i, target: Vector2i, boxes_passable: bool,
		goal: Vector2i) -> Vector2i:
	if from.x < 0 or target.x < 0:
		return Vector2i(-1, -1)
	var first: Dictionary = {from: from}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var cell: Vector2i = queue[head]
		head += 1
		if cell == target:
			return first[cell]
		for dir in DIRS:
			var next: Vector2i = cell + dir
			if first.has(next):
				continue
			var is_goal_cell := next == goal
			if not _walkable(next, boxes_passable or is_goal_cell):
				continue
			first[next] = first[cell] if cell != from else next
			queue.append(next)
	return Vector2i(-1, -1)


func _nearest_box_cell() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_dist := 1 << 30
	for cell in state.boxes.keys():
		var dist := absi(cell.x - thief.x) + absi(cell.y - thief.y)
		if dist < best_dist:
			best_dist = dist
			best = cell
	return best


## The thief keeps its distance: it never appears on a crate or on any of the eight
## cells surrounding one, so it has to walk to its loot first.
func _thief_spawn_cell() -> Vector2i:
	return _far_cell(thug, true)


func _far_cell(avoid := Vector2i(-1, -1), keep_off_crates := false) -> Vector2i:
	var best: Array = []
	var best_dist := -1
	for cell in state.floor_cells():
		if cell == state.player or cell == avoid or state.boxes.has(cell):
			continue
		if keep_off_crates and _touches_crate(cell):
			continue
		var dist := absi(cell.x - state.player.x) + absi(cell.y - state.player.y)
		if dist > best_dist:
			best_dist = dist
			best = [cell]
		elif dist == best_dist:
			best.append(cell)
	if best.is_empty():
		# cramped level: fall back to any free cell rather than skipping the spawn
		return Vector2i(-1, -1) if not keep_off_crates else _far_cell(avoid, false)
	return best[_rng.randi_range(0, best.size() - 1)]


func _touches_crate(cell: Vector2i) -> bool:
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			if state.boxes.has(cell + Vector2i(dx, dy)):
				return true
	return false


func status_text() -> String:
	var parts: Array = []
	if collapse_enabled:
		parts.append(Loc.t("hazard_collapse_in", [int(ceil(seconds_to_collapse()))]))
	if thug_enabled:
		parts.append(Loc.t("hazard_thug_gone") if _thug_dead else Loc.t("hazard_thug"))
	if thief_enabled:
		if _thief_dead:
			parts.append(Loc.t("hazard_thief_respawn_in", [int(ceil(thief_respawn))]))
		elif thief_grab > 0:
			parts.append(Loc.t("hazard_thief_grab"))
		else:
			parts.append(Loc.t("hazard_thief"))
	return "  ·  ".join(parts)

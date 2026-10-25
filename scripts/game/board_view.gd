class_name BoardView
extends Node2D
## Renders a LevelData + SokobanState with tweened crate and worker movement.

const CELL := 128.0

var level: LevelData
var state: SokobanState

var _floor_tex: Array = []
var _goal_tex: Texture2D
var _wall_tex: Texture2D
var _box_tex: Texture2D
var _box_goal_tex: Texture2D
var _shadow_tex: Texture2D
var _spark_tex: Texture2D
var _player_tex: Dictionary = {}

var _box_sprites: Dictionary = {}
var _box_shadows: Dictionary = {}
var _player_sprite: Sprite2D
var _player_shadow: Sprite2D
var _thug_sprite: Sprite2D
var _thief_sprite: Sprite2D
var _rubble_tex: Texture2D
var _hint: HintMarker
var _facing := "down"
var _frame_tween: Tween
var _highlight := Vector2i(-1, -1)


func setup(level_data: LevelData, game_state: SokobanState) -> void:
	level = level_data
	state = game_state
	_load_textures()
	if _hint == null:
		_hint = HintMarker.new()
		_hint.z_index = 30
		add_child(_hint)
	_hint.cell = CELL
	rebuild()
	queue_redraw()


func _load_textures() -> void:
	if not _floor_tex.is_empty():
		return
	for i in 3:
		_floor_tex.append(UIKit.art("floor_%d" % i))
	_goal_tex = UIKit.art("goal")
	_wall_tex = UIKit.art("wall")
	_box_tex = UIKit.art("box")
	_box_goal_tex = UIKit.art("box_goal")
	_shadow_tex = UIKit.art("shadow")
	_spark_tex = UIKit.art("spark")
	_rubble_tex = UIKit.art("rubble")
	for dir in ["down", "up", "left", "right"]:
		_player_tex[dir] = [UIKit.art("player_%s_0" % dir), UIKit.art("player_%s_1" % dir)]


func fit_to(area: Vector2) -> void:
	if level == null:
		return
	var board_size := Vector2(level.width * CELL, level.height * CELL)
	var padding := 28.0
	var s := minf((area.x - padding * 2.0) / board_size.x,
			(area.y - padding * 2.0) / board_size.y)
	s = clampf(s, 0.12, 1.35)
	scale = Vector2(s, s)
	position = (area - board_size * s) * 0.5


func rebuild() -> void:
	for child in _box_sprites.values():
		if is_instance_valid(child):
			child.queue_free()
	for child in _box_shadows.values():
		if is_instance_valid(child):
			child.queue_free()
	_box_sprites.clear()
	_box_shadows.clear()
	if _player_sprite != null and is_instance_valid(_player_sprite):
		_player_sprite.queue_free()
	if _player_shadow != null and is_instance_valid(_player_shadow):
		_player_shadow.queue_free()
	_player_sprite = null
	_player_shadow = null
	if state == null:
		return
	for pos in state.boxes.keys():
		_create_box(pos)
	_create_player()
	queue_redraw()


func _create_box(pos: Vector2i) -> void:
	var shadow := Sprite2D.new()
	shadow.texture = _shadow_tex
	shadow.position = _cell_center(pos) + Vector2(0, 16)
	shadow.scale = Vector2(0.66, 0.42)
	shadow.modulate = Color(1, 1, 1, 0.55)
	shadow.z_index = 3
	add_child(shadow)
	_box_shadows[pos] = shadow
	var spr := Sprite2D.new()
	spr.texture = _box_goal_tex if level.goals.has(pos) else _box_tex
	spr.position = _cell_center(pos)
	spr.scale = Vector2(0.95, 0.95)
	spr.z_index = 5
	add_child(spr)
	_box_sprites[pos] = spr


func _create_player() -> void:
	var center := _cell_center(state.player) + Vector2(0, -8)
	_player_shadow = Sprite2D.new()
	_player_shadow.texture = _shadow_tex
	_player_shadow.position = center + Vector2(0, 20)
	_player_shadow.scale = Vector2(0.55, 0.38)
	_player_shadow.modulate = Color(1, 1, 1, 0.5)
	_player_shadow.z_index = 3
	add_child(_player_shadow)
	_player_sprite = Sprite2D.new()
	_player_sprite.texture = _player_tex[_facing][0]
	_player_sprite.position = center
	_player_sprite.z_index = 7
	add_child(_player_sprite)


# --------------------------------------------------------------------------- #
# Drawing
# --------------------------------------------------------------------------- #
func _draw() -> void:
	if level == null:
		return
	var walls: Dictionary = state.walls if state != null else level.walls
	var board_size := Vector2(level.width * CELL, level.height * CELL)
	draw_rect(Rect2(-32, -32, board_size.x + 64, board_size.y + 64),
			Color(0.03, 0.045, 0.07, 0.55))
	draw_rect(Rect2(-26, -26, board_size.x + 52, board_size.y + 52),
			Color(0.055, 0.08, 0.115, 0.94), true)
	draw_rect(Rect2(-26, -26, board_size.x + 52, board_size.y + 52),
			Color(0.23, 0.31, 0.45, 0.9), false, 3.0)
	draw_rect(Rect2(-14, -14, board_size.x + 28, board_size.y + 28),
			Color(0.10, 0.14, 0.20, 0.55), false, 1.0)
	for y in level.height:
		for x in level.width:
			var pos := Vector2(x, y) * CELL
			var rect := Rect2(pos, Vector2(CELL, CELL))
			if walls.has(Vector2i(x, y)):
				draw_texture_rect(_wall_tex, rect.grow(2.0), false)
			else:
				var variant := absi((x * 92837111) ^ (y * 689287499)) % 3
				draw_texture_rect(_floor_tex[variant], rect, false)
				if level.goals.has(Vector2i(x, y)):
					draw_texture_rect(_goal_tex, rect, false)
				if state != null and state.temp_walls.has(Vector2i(x, y)) and _rubble_tex != null:
					draw_texture_rect(_rubble_tex, rect.grow(-6.0), false)
	if _highlight.x >= 0:
		var hl := Rect2(Vector2(_highlight) * CELL, Vector2(CELL, CELL)).grow(-4.0)
		draw_rect(hl, Color(0.98, 0.78, 0.35, 0.9), false, 6.0)
	draw_rect(Rect2(0, 0, board_size.x, board_size.y),
			Color(0.35, 0.45, 0.62, 0.35), false, 2.0)


# --------------------------------------------------------------------------- #
# Animation
# --------------------------------------------------------------------------- #
func animate_move(result: Dictionary) -> void:
	if state == null:
		return
	var dir: Vector2i = result["player_to"] - result["player_from"]
	_update_facing(dir)
	_tween_sprite(_player_sprite, _cell_center(result["player_to"]) + Vector2(0, -8), 0.10)
	if _player_shadow != null:
		_tween_sprite(_player_shadow, _cell_center(result["player_to"]) + Vector2(0, 12), 0.10)
	_walk_cycle()
	if bool(result["pushed"]):
		var moved_boxes: Array = result.get("boxes_moved", [])
		if moved_boxes.is_empty():
			moved_boxes = [[result["box_from"], result["box_to"]]]
		# boxes_moved is recorded far-to-near, which is also the only safe order:
		# the farthest crate vacates its cell before the next one moves in.
		if not _animate_crate_line(moved_boxes, false, 0.11):
			rebuild()
			return
		for pair in moved_boxes:
			var to: Vector2i = pair[1]
			if level.goals.has(to):
				burst(_cell_center(to), Color(0.45, 0.95, 0.85), 16)
			else:
				_update_box_at(to)


## Moves every crate of a chain push. `backward` reverses the travel direction.
func _animate_crate_line(pairs: Array, backward: bool, duration := 0.11) -> bool:
	if pairs.is_empty():
		return true
	if backward:
		for i in range(pairs.size() - 1, -1, -1):
			var pair: Array = pairs[i]
			if not _move_box_sprite(pair[1], pair[0], duration):
				return false
	else:
		for pair in pairs:
			if not _move_box_sprite(pair[0], pair[1], duration):
				return false
	return true


func _move_box_sprite(from: Vector2i, to: Vector2i, duration := 0.11) -> bool:
	var spr: Sprite2D = _box_sprites.get(from)
	var shadow: Sprite2D = _box_shadows.get(from)
	if spr == null:
		return false
	_box_sprites.erase(from)
	_box_shadows.erase(from)
	_box_sprites[to] = spr
	_tween_sprite(spr, _cell_center(to), duration)
	_update_box_texture(spr, to)
	if shadow != null:
		_box_shadows[to] = shadow
		_tween_sprite(shadow, _cell_center(to) + Vector2(0, 16), duration)
	return true


func _update_box_at(pos: Vector2i) -> void:
	if _box_sprites.has(pos):
		_update_box_texture(_box_sprites[pos], pos)


## Jump / phase / warp: the worker travels without touching any crate.
func animate_ability(record: Dictionary) -> void:
	var kind := str(record.get("kind", ""))
	var from: Vector2i = record["player_from"]
	var to: Vector2i = record["player_to"]
	_update_facing(to - from)
	var target := _cell_center(to) + Vector2(0, -8)
	_tween_sprite(_player_sprite, target, 0.18)
	if _player_shadow != null:
		_tween_sprite(_player_shadow, _cell_center(to) + Vector2(0, 12), 0.18)
	_walk_cycle()
	var color := Color(0.45, 0.95, 0.85)
	if kind == "phase":
		color = Color(0.62, 0.74, 1.0)
	elif kind == "warp":
		color = Color(0.95, 0.82, 0.48)
	elif kind == "pass":
		color = Color(0.55, 0.9, 1.0)
		wiggle_crates(from, to)
	burst(_cell_center(from), color, 12)
	burst(target, color, 14)


func animate_undo(record: Dictionary) -> void:
	var from_player: Vector2i = record["player_from"]
	var dir: Vector2i = from_player - record["player_to"]
	_update_facing(dir)
	_tween_sprite(_player_sprite, _cell_center(from_player) + Vector2(0, -8), 0.12)
	if _player_shadow != null:
		_tween_sprite(_player_shadow, _cell_center(from_player) + Vector2(0, 12), 0.12)
	_walk_cycle()
	if bool(record["pushed"]):
		var pairs: Array = record.get("boxes_moved", [])
		if pairs.is_empty():
			pairs = [[record["box_from"], record["box_to"]]]
		if not _animate_crate_line(pairs, true, 0.12):
			rebuild()


func animate_redo(record: Dictionary) -> void:
	var dir: Vector2i = record["player_to"] - record["player_from"]
	_update_facing(dir)
	_tween_sprite(_player_sprite, _cell_center(record["player_to"]) + Vector2(0, -8), 0.1)
	if _player_shadow != null:
		_tween_sprite(_player_shadow, _cell_center(record["player_to"]) + Vector2(0, 12), 0.1)
	_walk_cycle()
	if bool(record["pushed"]):
		var pairs: Array = record.get("boxes_moved", [])
		if pairs.is_empty():
			pairs = [[record["box_from"], record["box_to"]]]
		if not _animate_crate_line(pairs, false, 0.1):
			rebuild()


func blocked_feedback(pos: Vector2i, dir: Vector2i) -> void:
	var target: Node2D = _player_sprite
	if pos.x >= 0:
		target = _box_sprites.get(pos, _player_sprite)
	if target == null:
		return
	var base := target.position
	var offset := Vector2(dir) * 10.0
	var tw := target.create_tween()
	tw.tween_property(target, "position", base + offset, 0.045)
	tw.tween_property(target, "position", base, 0.09)


func play_win_jump() -> void:
	if _player_sprite == null:
		return
	var base := _player_sprite.position
	var tw := _player_sprite.create_tween()
	tw.tween_property(_player_sprite, "position", base + Vector2(0, -34), 0.18) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_player_sprite, "position", base, 0.22) \
			.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	burst(base, Color(0.98, 0.83, 0.35), 22)


func burst(pos: Vector2, color: Color, amount := 14) -> void:
	var p := CPUParticles2D.new()
	p.texture = _spark_tex
	p.position = pos
	p.amount = amount
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.95
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 22.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 320)
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 170.0
	p.scale_amount_min = 0.22
	p.scale_amount_max = 0.6
	p.angular_velocity_min = -180.0
	p.angular_velocity_max = 180.0
	p.color = color
	p.z_index = 12
	add_child(p)
	p.emitting = true
	var cleanup := Timer.new()
	cleanup.wait_time = 1.4
	cleanup.one_shot = true
	p.add_child(cleanup)
	cleanup.timeout.connect(p.queue_free)
	cleanup.start()


func set_hint(dir: Vector2i, box_pos: Vector2i) -> void:
	if _hint == null:
		return
	_hint.dir = dir
	_hint.box_pos = box_pos
	_hint.active = true
	_hint.queue_redraw()


func clear_hint() -> void:
	if _hint != null:
		_hint.active = false
		_hint.queue_redraw()


func _update_box_texture(spr: Sprite2D, pos: Vector2i) -> void:
	if spr == null:
		return
	spr.texture = _box_goal_tex if level.goals.has(pos) else _box_tex


func _update_facing(dir: Vector2i) -> void:
	if dir == Vector2i.ZERO:
		return
	if dir == Vector2i.UP:
		_facing = "up"
	elif dir == Vector2i.DOWN:
		_facing = "down"
	elif dir == Vector2i.LEFT:
		_facing = "left"
	else:
		_facing = "right"


func _walk_cycle() -> void:
	if _player_sprite == null:
		return
	_player_sprite.texture = _player_tex[_facing][1]
	if _frame_tween != null and _frame_tween.is_valid():
		_frame_tween.kill()
	_frame_tween = create_tween()
	_frame_tween.tween_interval(0.12)
	_frame_tween.tween_callback(_reset_frame)


func _reset_frame() -> void:
	if _player_sprite != null and is_instance_valid(_player_sprite):
		_player_sprite.texture = _player_tex[_facing][0]


func _tween_sprite(sprite: Node2D, target: Vector2, duration: float) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var previous: Variant = sprite.get_meta("active_tween") if sprite.has_meta("active_tween") else null
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	var tw := sprite.create_tween()
	tw.tween_property(sprite, "position", target, duration) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	sprite.set_meta("active_tween", tw)


func _cell_center(pos: Vector2i) -> Vector2:
	return (Vector2(pos) + Vector2(0.5, 0.5)) * CELL


## Public helper so screens can convert mouse/touch positions into grid cells.
func cell_center(pos: Vector2i) -> Vector2:
	return _cell_center(pos)


func cell_at_global(global_pos: Vector2) -> Vector2i:
	if level == null:
		return Vector2i(-1, -1)
	var local := to_local(global_pos) / CELL
	var cell := Vector2i(floori(local.x), floori(local.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
		return Vector2i(-1, -1)
	return cell


func set_highlight(cell: Vector2i) -> void:
	_highlight = cell
	queue_redraw()


func clear_highlight() -> void:
	_highlight = Vector2i(-1, -1)
	queue_redraw()


## Places (or hides) the chapter hazards on the board.
func set_enemies(thug: Vector2i, thief: Vector2i, grabbing := false) -> void:
	_thug_sprite = _place_actor(_thug_sprite, "thug", thug, 6)
	_thief_sprite = _place_actor(_thief_sprite, "thief", thief, 9)
	if _thief_sprite != null:
		_thief_sprite.modulate = Color(1.0, 0.82, 0.82) if grabbing else Color.WHITE


func _place_actor(existing: Sprite2D, art_name: String, cell: Vector2i,
		z: int) -> Sprite2D:
	if cell.x < 0:
		if existing != null and is_instance_valid(existing):
			existing.queue_free()
		return null
	var tex := UIKit.art(art_name)
	if tex == null:
		return existing
	var spr := existing
	if spr == null or not is_instance_valid(spr):
		spr = Sprite2D.new()
		spr.texture = tex
		spr.scale = Vector2(0.9, 0.9)
		spr.z_index = z
		add_child(spr)
	var target := _cell_center(cell) + Vector2(0, -6)
	if spr.position.distance_to(target) > 1.0:
		_tween_sprite(spr, target, 0.18)
		burst(_cell_center(cell), Color(0.9, 0.5, 0.45), 6)
	return spr


## Nudge the crates we phase through so the move reads as "passing through".
func wiggle_crates(from: Vector2i, to: Vector2i) -> void:
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var cell := from
	while cell != to:
		cell += step
		var spr: Sprite2D = _box_sprites.get(cell)
		if spr == null:
			continue
		var base := spr.position
		var tw := spr.create_tween()
		tw.tween_property(spr, "position", base + Vector2(6, 0), 0.05)
		tw.tween_property(spr, "position", base + Vector2(-5, 0), 0.05)
		tw.tween_property(spr, "position", base + Vector2(3, 0), 0.04)
		tw.tween_property(spr, "position", base, 0.05)
		burst(base, Color(0.6, 0.9, 1.0), 8)


func animate_pull(record: Dictionary) -> void:
	var player_to: Vector2i = record["player_to"]
	var box_from: Vector2i = record["box_from"]
	var box_to: Vector2i = record["box_to"]
	_update_facing(player_to - record["player_from"])
	_tween_sprite(_player_sprite, _cell_center(player_to) + Vector2(0, -8), 0.11)
	if _player_shadow != null:
		_tween_sprite(_player_shadow, _cell_center(player_to) + Vector2(0, 12), 0.11)
	_walk_cycle()
	_move_box_sprite(box_from, box_to, 0.11)
	burst(_cell_center(box_from), Color(0.45, 0.95, 0.85), 10)


func board_size() -> Vector2:
	if level == null:
		return Vector2.ZERO
	return Vector2(level.width, level.height) * CELL

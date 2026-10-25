class_name EditorBoard
extends Control
## Grid canvas for the level editor with single / rectangle / flood-fill modes.

signal paint_requested(pos: Vector2i, erase: bool)
signal rect_requested(rect: Rect2i)
signal fill_requested(pos: Vector2i, erase: bool)
signal stroke_started
signal hover_changed(pos: Vector2i)

var level: LevelData
var tool := "wall"
var mode := "single"

var hover := Vector2i(-1, -1)

var _cell := 40.0
var _origin := Vector2.ZERO
var _painting := false
var _last_paint := Vector2i(-1, -1)
var _rect_start := Vector2i(-1, -1)
var _rect_end := Vector2i(-1, -1)

var _floor_tex: Array = []
var _wall_tex: Texture2D
var _goal_tex: Texture2D
var _box_tex: Texture2D
var _box_goal_tex: Texture2D
var _player_tex: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	_floor_tex = [UIKit.art("floor_0"), UIKit.art("floor_1"), UIKit.art("floor_2")]
	_wall_tex = UIKit.art("wall")
	_goal_tex = UIKit.art("goal")
	_box_tex = UIKit.art("box")
	_box_goal_tex = UIKit.art("box_goal")
	_player_tex = UIKit.art("player_down_0")
	mouse_exited.connect(func():
		hover = Vector2i(-1, -1)
		queue_redraw()
		hover_changed.emit(hover)
	)
	resized.connect(queue_redraw)


func set_level(level_data: LevelData) -> void:
	level = level_data
	queue_redraw()


func set_tool(new_tool: String) -> void:
	tool = new_tool
	queue_redraw()


func set_mode(new_mode: String) -> void:
	mode = new_mode
	_rect_start = Vector2i(-1, -1)
	_rect_end = Vector2i(-1, -1)
	queue_redraw()


func _layout() -> void:
	if level == null:
		return
	var available := size - Vector2(56, 56)
	var c := floorf(minf(available.x / level.width, available.y / level.height))
	_cell = clampf(c, 12.0, 72.0)
	_origin = (size - Vector2(level.width, level.height) * _cell) * 0.5


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.06, 0.09, 0.55), true)
	if level == null:
		return
	_layout()
	var grid_size := Vector2(level.width, level.height) * _cell
	draw_rect(Rect2(_origin - Vector2(10, 10), grid_size + Vector2(20, 20)),
			Color(0.055, 0.08, 0.115, 0.92), true)
	draw_rect(Rect2(_origin - Vector2(10, 10), grid_size + Vector2(20, 20)),
			Color(0.24, 0.32, 0.46, 0.85), false, 2.0)

	for y in level.height:
		for x in level.width:
			var pos := Vector2i(x, y)
			var rect := Rect2(_origin + Vector2(x, y) * _cell, Vector2(_cell, _cell))
			if level.walls.has(pos):
				draw_texture_rect(_wall_tex, rect, false)
			else:
				var variant := absi((x * 92837111) ^ (y * 689287499)) % 3
				draw_texture_rect(_floor_tex[variant], rect, false)
				if level.goals.has(pos):
					draw_texture_rect(_goal_tex, rect, false)
			if level.boxes.has(pos):
				draw_texture_rect(_box_goal_tex if level.goals.has(pos) else _box_tex,
						rect, false)
	if level.player_found:
		var prect := Rect2(_origin + Vector2(level.player) * _cell, Vector2(_cell, _cell))
		draw_texture_rect(_player_tex, prect, false)

	if _cell >= 18.0:
		var line_color := Color(0.5, 0.62, 0.8, 0.10)
		for x in level.width + 1:
			var px := _origin.x + x * _cell
			draw_line(Vector2(px, _origin.y), Vector2(px, _origin.y + grid_size.y),
					line_color, 1.0)
		for y in level.height + 1:
			var py := _origin.y + y * _cell
			draw_line(Vector2(_origin.x, py), Vector2(_origin.x + grid_size.x, py),
					line_color, 1.0)

	if _rect_start.x >= 0 and _painting and mode == "rect":
		var r := _make_rect(_rect_start, _rect_end)
		var rect := Rect2(_origin + Vector2(r.position) * _cell, Vector2(r.size) * _cell)
		draw_rect(rect, Color(0.95, 0.76, 0.3, 0.16), true)
		draw_rect(rect, UIKit.COL_GOLD, false, 2.0)

	if hover.x >= 0:
		var rect := Rect2(_origin + Vector2(hover) * _cell, Vector2(_cell, _cell))
		draw_rect(rect.grow(-1.0), UIKit.COL_GOLD, false, 2.0)
		_draw_brush_preview(hover, rect)


func _draw_brush_preview(pos: Vector2i, rect: Rect2) -> void:
	match tool:
		"wall":
			draw_texture_rect(_wall_tex, rect, false, Color(1, 1, 1, 0.55))
		"goal":
			draw_texture_rect(_goal_tex, rect, false, Color(1, 1, 1, 0.7))
		"box":
			draw_texture_rect(_box_tex, rect, false, Color(1, 1, 1, 0.55))
		"player":
			draw_texture_rect(_player_tex, rect, false, Color(1, 1, 1, 0.55))
		"erase":
			draw_rect(rect, Color(0.9, 0.35, 0.35, 0.28), true)
			draw_line(rect.position + Vector2(8, 8), rect.end - Vector2(8, 8),
					Color(1, 0.5, 0.5, 0.8), 2.0)
			draw_line(Vector2(rect.end.x - 8, rect.position.y + 8),
					Vector2(rect.position.x + 8, rect.end.y - 8),
					Color(1, 0.5, 0.5, 0.8), 2.0)
		"floor":
			draw_rect(rect, Color(0.3, 0.5, 0.6, 0.2), true)


func _gui_input(event: InputEvent) -> void:
	if level == null:
		return
	if event is InputEventMouseMotion:
		var cell := _cell_at(event.position)
		if cell != hover:
			hover = cell
			queue_redraw()
			hover_changed.emit(hover)
		if _painting:
			if mode == "single" and cell.x >= 0 and cell != _last_paint:
				_last_paint = cell
				paint_requested.emit(cell, false)
			elif mode == "rect" and cell.x >= 0:
				_rect_end = cell
				queue_redraw()
		return
	if event is InputEventMouseButton:
		var cell := _cell_at(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				hover = cell
				_painting = true
				_last_paint = cell
				stroke_started.emit()
				if mode == "rect":
					_rect_start = cell
					_rect_end = cell
					queue_redraw()
				elif mode == "fill":
					if cell.x >= 0:
						fill_requested.emit(cell, false)
				else:
					if cell.x >= 0:
						paint_requested.emit(cell, false)
				accept_event()
			else:
				if _painting and mode == "rect" and _rect_start.x >= 0:
					var rect := _make_rect(_rect_start, _rect_end)
					rect_requested.emit(rect)
				_painting = false
				_rect_start = Vector2i(-1, -1)
				_rect_end = Vector2i(-1, -1)
				queue_redraw()
				accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if cell.x >= 0:
				stroke_started.emit()
				paint_requested.emit(cell, true)
				accept_event()


func _cell_at(local: Vector2) -> Vector2i:
	if level == null or _cell <= 0.0:
		return Vector2i(-1, -1)
	var rel := local - _origin
	var cell := Vector2i(floori(rel.x / _cell), floori(rel.y / _cell))
	if cell.x < 0 or cell.y < 0 or cell.x >= level.width or cell.y >= level.height:
		return Vector2i(-1, -1)
	return cell


func _make_rect(a: Vector2i, b: Vector2i) -> Rect2i:
	var p := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var q := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	return Rect2i(p, q - p + Vector2i.ONE)

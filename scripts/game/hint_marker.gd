class_name HintMarker
extends Node2D
## Pulsing ring + arrow drawn over the board to point at the next push.

var active := false
var dir := Vector2i.RIGHT
var box_pos := Vector2i.ZERO
var cell := 128.0

var _time := 0.0


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func refresh() -> void:
	queue_redraw()


func _draw() -> void:
	if not active:
		set_process(false)
		return
	set_process(true)
	var center := (Vector2(box_pos) + Vector2(0.5, 0.5)) * cell
	var pulse := 0.5 + 0.5 * sin(_time * 5.0)
	draw_circle(center, cell * 0.52 + 4.0 * pulse, Color(0.31, 0.85, 0.78, 0.10))
	draw_arc(center, cell * 0.56 + 5.0 * pulse, 0.0, TAU, 48,
			Color(0.42, 0.96, 0.88, 0.65), 5.0)
	var d := Vector2(dir)
	var start := center + d * cell * 0.62
	var tip := start + d * cell * 0.34
	var perp := Vector2(-d.y, d.x)
	var gold := Color(0.98, 0.83, 0.35, 0.95)
	draw_line(start, tip, gold, 9.0)
	draw_colored_polygon(PackedVector2Array([
		tip + d * 20.0,
		tip + perp * 17.0,
		tip - perp * 17.0,
	]), gold)

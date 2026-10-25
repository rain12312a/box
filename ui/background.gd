class_name Background
extends Control
## Animated ambient backdrop shared by the menus.

var variant := "menu"

var _dust: Array = []
var _time := 0.0
var _glow: Texture2D
var _glow_teal: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow = UIKit.radial_texture(128, Color(0.29, 0.55, 0.66, 0.20), Color(0.29, 0.55, 0.66, 0.0))
	_glow_teal = UIKit.radial_texture(128, Color(0.95, 0.72, 0.28, 0.12), Color(0.95, 0.72, 0.28, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20251024
	var count := 34 if variant == "menu" else 20
	for i in count:
		_dust.append({
			"pos": Vector2(rng.randf(), rng.randf()),
			"vel": Vector2(rng.randf_range(-0.008, 0.01), rng.randf_range(-0.014, -0.003)),
			"r": rng.randf_range(0.7, 2.4),
			"a": rng.randf_range(0.05, 0.22),
		})
	set_process(true)
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	for p in _dust:
		var pos: Vector2 = p["pos"]
		var vel: Vector2 = p["vel"]
		pos += vel * delta
		if pos.y < -0.02:
			pos.y = 1.02
			pos.x = randf()
		if pos.x < -0.02:
			pos.x = 1.02
		elif pos.x > 1.02:
			pos.x = -0.02
		p["pos"] = pos
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), UIKit.COL_BG)
	var bands := 26
	for i in bands:
		var t := float(i) / float(bands - 1)
		var col := UIKit.COL_BG.lerp(Color("17223a"), t * 0.9)
		draw_rect(Rect2(0, h * t, w, h / bands + 2.0), col)
	if _glow != null:
		var pulse := 1.0 + sin(_time * 0.35) * 0.05
		draw_texture_rect(_glow, Rect2(w * 0.58 - 460 * pulse, h * 0.08 - 320 * pulse,
				920 * pulse, 900 * pulse), false, Color(1, 1, 1, 1))
		draw_texture_rect(_glow_teal, Rect2(w * 0.18 - 330, h * 0.62 - 260,
				700, 660), false, Color(1, 1, 1, 1))
	# faint blueprint grid
	var step := 84.0
	var grid_color := Color(0.55, 0.68, 0.88, 0.035)
	var x := fmod(_time * 2.0, step)
	while x < w:
		draw_line(Vector2(x, 0), Vector2(x, h), grid_color, 1.0)
		x += step
	var y := 0.0
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), grid_color, 1.0)
		y += step
	# drifting dust
	for p in _dust:
		var pos: Vector2 = p["pos"]
		draw_circle(pos * Vector2(w, h), float(p["r"]),
				Color(0.82, 0.9, 1.0, float(p["a"]) * (0.7 + 0.3 * sin(_time + pos.x * 20.0))))
	# vignette
	var edge := Color(0.02, 0.03, 0.05, 0.55)
	draw_rect(Rect2(0, 0, w, 120), edge, false, 0.0)
	draw_line(Vector2(0, 0), Vector2(w, 0), edge, 0.0)

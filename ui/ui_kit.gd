class_name UIKit
extends RefCounted
## Shared palette, theme and widget factory used by every screen.
## Building UI in code keeps the whole look consistent and data-driven.

const COL_BG := Color("0b111c")
const COL_BG_2 := Color("121a2a")
const COL_PANEL := Color("182235")
const COL_PANEL_2 := Color("1e2a40")
const COL_PANEL_3 := Color("243350")
const COL_BORDER := Color("2c3b57")
const COL_BORDER_LIGHT := Color("3d5174")
const COL_TEXT := Color("ede6d7")
const COL_MUTED := Color("93a1ba")
const COL_DIM := Color("62708a")
const COL_GOLD := Color("f2c14e")
const COL_GOLD_LIGHT := Color("ffd982")
const COL_GOLD_DARK := Color("c99a33")
const COL_TEAL := Color("4fd1c5")
const COL_RED := Color("e57373")
const COL_GREEN := Color("8ad6a2")
const COL_INK := Color("101725")

const FONT_NAMES := ["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC",
		"Source Han Sans SC", "PingFang SC", "Segoe UI", "Arial", "sans-serif"]

static var _font_regular: SystemFont
static var _font_bold: SystemFont
static var _icon_cache: Dictionary = {}
static var _texture_cache: Dictionary = {}
static var _theme: Theme


static func font(bold := false) -> Font:
	if bold:
		if _font_bold == null:
			_font_bold = _make_font(true)
		return _font_bold
	if _font_regular == null:
		_font_regular = _make_font(false)
	return _font_regular


static func _make_font(bold: bool) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(FONT_NAMES)
	f.font_weight = 700 if bold else 400
	f.allow_system_fallback = true
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	f.multichannel_signed_distance_field = false
	return f


# --------------------------------------------------------------------------- #
# Theme
# --------------------------------------------------------------------------- #
static func build_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 18

	# Panels -----------------------------------------------------------------
	t.set_stylebox("panel", "PanelContainer", panel_style(COL_PANEL, COL_BORDER, 1, 16, 18))
	t.set_stylebox("panel", "Panel", panel_style(COL_PANEL, COL_BORDER, 1, 16, 0))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", panel_style(COL_PANEL, COL_BORDER, 1, 18, 22))
	t.set_type_variation("FlatPanel", "PanelContainer")
	t.set_stylebox("panel", "FlatPanel", panel_style(COL_PANEL_2, Color(0, 0, 0, 0), 0, 12, 14))
	t.set_type_variation("ToastPanel", "PanelContainer")
	t.set_stylebox("panel", "ToastPanel", panel_style(Color("141d2ee6"), COL_BORDER_LIGHT, 1, 12, 14))

	# Buttons ----------------------------------------------------------------
	_setup_button(t, "Button", COL_PANEL_2, COL_PANEL_3, COL_BORDER, COL_BORDER_LIGHT,
			COL_TEXT, COL_GOLD)
	t.set_type_variation("PrimaryButton", "Button")
	_setup_button(t, "PrimaryButton", COL_GOLD, COL_GOLD_LIGHT, COL_GOLD_DARK, COL_GOLD_LIGHT,
			COL_INK, COL_INK)
	t.set_color("font_disabled_color", "PrimaryButton", Color(0.3, 0.3, 0.3, 0.7))
	t.set_type_variation("GhostButton", "Button")
	_setup_button(t, "GhostButton", Color(0.07, 0.10, 0.16, 0.62), COL_PANEL_3, COL_BORDER,
			COL_BORDER_LIGHT, COL_MUTED, COL_TEXT)
	t.set_type_variation("DangerButton", "Button")
	_setup_button(t, "DangerButton", Color("3a2028"), Color("4b2833"), Color("6b3644"),
			COL_RED, COL_TEXT, COL_RED)
	t.set_type_variation("IconButton", "Button")
	_setup_button(t, "IconButton", Color(0, 0, 0, 0), COL_PANEL_2, Color(0, 0, 0, 0),
			COL_BORDER_LIGHT, COL_MUTED, COL_TEXT)
	t.set_type_variation("LevelCard", "Button")
	_setup_button(t, "LevelCard", COL_PANEL, COL_PANEL_2, COL_BORDER, COL_GOLD, COL_TEXT,
			COL_TEXT)

	# Inputs -----------------------------------------------------------------
	t.set_stylebox("normal", "LineEdit", input_style(COL_BG_2, COL_BORDER))
	t.set_stylebox("focus", "LineEdit", input_style(COL_BG_2, COL_GOLD))
	t.set_color("font_color", "LineEdit", COL_TEXT)
	t.set_color("font_placeholder_color", "LineEdit", COL_DIM)
	t.set_color("caret_color", "LineEdit", COL_GOLD)
	t.set_color("selection_color", "LineEdit", Color(0.95, 0.76, 0.3, 0.3))
	t.set_constant("minimum_character_width", "LineEdit", 6)

	t.set_stylebox("normal", "TextEdit", input_style(COL_BG_2, COL_BORDER))
	t.set_stylebox("focus", "TextEdit", input_style(COL_BG_2, COL_GOLD))
	t.set_color("font_color", "TextEdit", COL_TEXT)
	t.set_color("caret_color", "TextEdit", COL_GOLD)
	t.set_color("font_placeholder_color", "TextEdit", COL_DIM)

	t.set_stylebox("normal", "OptionButton", button_style(COL_PANEL_2, COL_BORDER, 10))
	t.set_stylebox("hover", "OptionButton", button_style(COL_PANEL_3, COL_BORDER_LIGHT, 10))
	t.set_stylebox("pressed", "OptionButton", button_style(COL_PANEL_3, COL_GOLD, 10))
	t.set_stylebox("focus", "OptionButton", focus_style(COL_GOLD, 10))
	t.set_color("font_color", "OptionButton", COL_TEXT)
	t.set_color("font_hover_color", "OptionButton", COL_GOLD)
	t.set_color("font_pressed_color", "OptionButton", COL_GOLD)

	t.set_color("font_color", "CheckButton", COL_TEXT)
	t.set_color("font_hover_color", "CheckButton", COL_GOLD)
	t.set_color("font_pressed_color", "CheckButton", COL_TEXT)
	t.set_color("font_focus_color", "CheckButton", COL_TEXT)
	t.set_constant("h_separation", "CheckButton", 12)

	t.set_stylebox("slider", "HSlider", slider_track_style())
	t.set_icon("grabber", "HSlider", circle_texture(20, COL_GOLD, COL_GOLD_LIGHT))
	t.set_icon("grabber_highlight", "HSlider", circle_texture(22, COL_GOLD_LIGHT, COL_TEXT))
	t.set_icon("grabber_disabled", "HSlider", circle_texture(20, COL_DIM, COL_DIM))
	t.set_constant("center_grabber", "HSlider", 1)

	t.set_stylebox("scroll", "VScrollBar", scroll_style(COL_BG_2))
	t.set_stylebox("grabber", "VScrollBar", button_style(COL_BORDER_LIGHT, Color(0, 0, 0, 0), 6))
	t.set_stylebox("grabber_highlight", "VScrollBar", button_style(COL_MUTED, Color(0, 0, 0, 0), 6))
	t.set_constant("minimum_grabber_size", "VScrollBar", 40)

	t.set_color("font_color", "Label", COL_TEXT)
	t.set_color("font_color", "RichTextLabel", COL_TEXT)
	t.set_color("default_color", "RichTextLabel", COL_TEXT)
	t.set_stylebox("panel", "TooltipPanel", panel_style(COL_BG_2, COL_BORDER_LIGHT, 1, 8, 10))
	t.set_color("font_color", "TooltipLabel", COL_TEXT)
	_theme = t
	return t


static func _setup_button(t: Theme, type: String, bg: Color, bg_hover: Color, border: Color,
		border_hover: Color, text_color: Color, text_hover: Color) -> void:
	var normal := button_style(bg, border, 10)
	var hover := button_style(bg_hover, border_hover, 10)
	var pressed := button_style(bg.darkened(0.12), border_hover, 10)
	var disabled := button_style(Color(bg.r, bg.g, bg.b, 0.45), Color(border.r, border.g, border.b, 0.6), 10)
	t.set_stylebox("normal", type, normal)
	t.set_stylebox("hover", type, hover)
	t.set_stylebox("pressed", type, pressed)
	t.set_stylebox("disabled", type, disabled)
	t.set_stylebox("focus", type, focus_style(COL_GOLD, 10))
	t.set_color("font_color", type, text_color)
	t.set_color("font_hover_color", type, text_hover)
	t.set_color("font_pressed_color", type, text_hover)
	t.set_color("font_focus_color", type, text_color)
	t.set_color("font_disabled_color", type, Color(text_color.r, text_color.g, text_color.b, 0.4))
	t.set_font("font", type, font())
	t.set_font_size("font_size", type, 18)


static func button_style(bg: Color, border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1 if border.a > 0.01 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.anti_aliasing = true
	return s


static func panel_style(bg: Color, border: Color, border_width: int, radius: int,
		margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_width)
	s.set_corner_radius_all(radius)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 12
	s.shadow_offset = Vector2(0, 5)
	s.anti_aliasing = true
	return s


static func input_style(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(8)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


static func focus_style(border: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(radius)
	s.expand_margin_left = 2
	s.expand_margin_right = 2
	s.expand_margin_top = 2
	s.expand_margin_bottom = 2
	return s


static func slider_track_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = COL_BORDER
	s.set_corner_radius_all(4)
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s


static func scroll_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(6)
	s.content_margin_left = 3
	s.content_margin_right = 3
	return s


# --------------------------------------------------------------------------- #
# Textures
# --------------------------------------------------------------------------- #
static func clear_cache() -> void:
	_icon_cache.clear()
	_texture_cache.clear()
	_theme = null
	_font_regular = null
	_font_bold = null


static func icon(name: String) -> Texture2D:
	if _icon_cache.has(name):
		return _icon_cache[name]
	var path := "res://assets/art/icon_%s.png" % name
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	_icon_cache[name] = tex
	return tex


static func art(name: String) -> Texture2D:
	if _texture_cache.has(name):
		return _texture_cache[name]
	var path := "res://assets/art/%s.png" % name
	if not ResourceLoader.exists(path):
		return null
	var tex: Texture2D = load(path)
	_texture_cache[name] = tex
	return tex


static func circle_texture(size: int, fill: Color, border: Color) -> ImageTexture:
	var key := "circle_%d_%s_%s" % [size, fill.to_html(), border.to_html()]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := (size - 1) / 2.0
	var r := c - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length()
			if d <= r - 1.5:
				img.set_pixel(x, y, fill)
			elif d <= r:
				img.set_pixel(x, y, border)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex


static func radial_texture(size: int, center: Color, edge: Color) -> ImageTexture:
	var key := "radial_%d_%s_%s" % [size, center.to_html(), edge.to_html()]
	if _texture_cache.has(key):
		return _texture_cache[key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var d := clampf(Vector2(x - c, y - c).length() / c, 0.0, 1.0)
			var col := center.lerp(edge, d)
			img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex


# --------------------------------------------------------------------------- #
# Widgets
# --------------------------------------------------------------------------- #
static func label(text: String, size := 18, color := COL_TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func heading(text: String, size := 34, color := COL_GOLD) -> Label:
	var l := label(text, size, color, true)
	return l


static func button(text: String, icon_name := "", variation := "", height := 46) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, height)
	b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not icon_name.is_empty():
		var tex := icon(icon_name)
		if tex != null:
			b.icon = tex
			b.add_theme_constant_override("icon_max_width", 24)
			b.expand_icon = false
	b.pressed.connect(_play_click)
	return b


static func icon_button(icon_name: String, tooltip: String, size := 44) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.custom_minimum_size = Vector2(size, size)
	b.icon = icon(icon_name)
	b.expand_icon = true
	b.tooltip_text = tooltip
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_constant_override("icon_max_width", int(size * 0.52))
	b.pressed.connect(_play_click)
	return b


static func _play_click() -> void:
	if Audio != null:
		Audio.play_sfx("click", -9.0, 0.03)


static func panel(padding := 18, variation := "CardPanel") -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	return p


static func hbox(separation := 12) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", separation)
	return h


static func vbox(separation := 12) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", separation)
	return v


static func spacer(width := 0, height := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func expand_spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func star_row(stars: int, total := 3, star_size := 20) -> HBoxContainer:
	var row := hbox(2)
	for i in total:
		var tr := TextureRect.new()
		tr.texture = icon("star")
		tr.custom_minimum_size = Vector2(star_size, star_size)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.modulate = COL_GOLD if i < stars else Color(0.35, 0.4, 0.5, 0.55)
		row.add_child(tr)
	return row


static func star_icon(size := 24, filled := true) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icon("star")
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.modulate = COL_GOLD if filled else Color(0.32, 0.38, 0.48, 0.6)
	return tr


static func pill(content: Control, bg := Color("141d2ee6"),
		border := COL_BORDER_LIGHT) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 5
	s.content_margin_right = 5
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", s)
	p.add_child(content)
	return p


static func divider(color := COL_BORDER) -> ColorRect:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(0, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func format_time(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var m := total / 60
	var s := total % 60
	return "%02d:%02d" % [m, s]


static func format_seconds_long(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	if total >= 3600:
		var h := total / 3600
		var m := (total % 3600) / 60
		return "%d:%02d:%02d" % [h, m, total % 60]
	return format_time(seconds)


static func toast(parent: Node, text: String, duration := 2.0) -> void:
	if parent == null or not is_instance_valid(parent):
		return
	var panel := panel(14, "ToastPanel")
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 320
	var l := label(text, 17, COL_TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	parent.add_child(panel)
	panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -118
	panel.offset_bottom = -64
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.16)
	tw.tween_interval(duration)
	tw.tween_property(panel, "modulate:a", 0.0, 0.25)
	tw.tween_callback(panel.queue_free)


static func confirm(parent: Node, title: String, body: String, confirm_text: String,
		on_confirm: Callable, on_cancel := Callable(), danger := false) -> void:
	if parent == null:
		return
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.z_index = 300
	parent.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := panel(26, "CardPanel")
	card.custom_minimum_size = Vector2(460, 0)
	center.add_child(card)
	var v := vbox(16)
	card.add_child(v)
	v.add_child(heading(title, 24, COL_TEXT))
	var body_label := label(body, 17, COL_MUTED)
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.custom_minimum_size = Vector2(400, 0)
	v.add_child(body_label)
	v.add_child(divider())
	var row := hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_END
	var cancel := button(Loc.t("common_cancel"), "", "GhostButton", 42)
	cancel.pressed.connect(func():
		layer.queue_free()
		if on_cancel.is_valid():
			on_cancel.call()
	)
	var ok := button(confirm_text, "", "DangerButton" if danger else "PrimaryButton", 42)
	ok.pressed.connect(func():
		layer.queue_free()
		on_confirm.call()
	)
	row.add_child(cancel)
	row.add_child(ok)
	v.add_child(row)
	cancel.grab_focus()

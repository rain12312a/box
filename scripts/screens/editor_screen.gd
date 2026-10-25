extends ScreenBase
## Workshop level editor: paint tools, metadata, solver validation, save/load and playtest.

const TOOLS := [
	{"id": "floor", "icon": "floor", "label": "editor_tool_floor"},
	{"id": "wall", "icon": "wall", "label": "editor_tool_wall"},
	{"id": "goal", "icon": "goal_png", "label": "editor_tool_goal"},
	{"id": "box", "icon": "box_png", "label": "editor_tool_box"},
	{"id": "player", "icon": "player_png", "label": "editor_tool_player"},
	{"id": "erase", "icon": "eraser", "label": "editor_tool_erase"},
]

var level: LevelData
var current_id := ""
var dirty := false

var board: EditorBoard
var tool := "wall"
var mode := "single"

var _undo_stack: Array = []
var _redo_stack: Array = []
var _tool_buttons: Dictionary = {}
var _mode_buttons: Dictionary = {}

var _name_edit: LineEdit
var _author_edit: LineEdit
var _w_option: OptionButton
var _h_option: OptionButton
var _par_label: Label
var _validation_box: VBoxContainer
var _levels_box: VBoxContainer
var _dirty_label: Label
var _hover_label: Label
var _size_label: Label
var _mode_hint: Label
var _hazard_checks: Dictionary = {}
var _hazard_hint: Label
var _modal_open := false
var _suppress_meta := false


func _build() -> void:
	add_background("editor")
	Audio.play_music("music_menu")
	var draft: Variant = params.get("draft", {})
	if draft is Dictionary and draft.get("level") is LevelData:
		level = draft["level"]
		current_id = str(draft.get("level_id", level.id))
		dirty = bool(draft.get("dirty", false))
	else:
		level = _new_level()
	level.builtin = false

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_build_top_bar(root)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 14)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_build_toolbar(body)
	_build_canvas(body)
	_build_inspector(body)

	_refresh_all()
	_refresh_tool_styles()
	_refresh_mode_styles()


func _build_top_bar(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	root.add_child(bar)
	var back := UIKit.icon_button("arrow_left", t("common_back"), 42)
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_go_back)
	bar.add_child(back)
	bar.add_child(UIKit.heading(t("editor_title"), 25, UIKit.COL_TEXT))
	_dirty_label = UIKit.label("", 12, UIKit.COL_DIM)
	_dirty_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_dirty_label)
	bar.add_child(UIKit.expand_spacer())

	var new_button := UIKit.button(t("editor_new"), "plus", "GhostButton", 42)
	new_button.focus_mode = Control.FOCUS_NONE
	new_button.pressed.connect(func(): _confirm_discard(_new_document))
	bar.add_child(new_button)

	var import_button := UIKit.button(t("editor_import"), "import", "GhostButton", 42)
	import_button.focus_mode = Control.FOCUS_NONE
	import_button.pressed.connect(_open_import)
	bar.add_child(import_button)

	var save_button := UIKit.button(t("editor_save"), "save", "GhostButton", 42)
	save_button.focus_mode = Control.FOCUS_NONE
	save_button.pressed.connect(_save)
	bar.add_child(save_button)

	var test_button := UIKit.button(t("editor_playtest"), "play", "PrimaryButton", 42)
	test_button.focus_mode = Control.FOCUS_NONE
	test_button.pressed.connect(_test_level)
	bar.add_child(test_button)


func _build_toolbar(body: HBoxContainer) -> void:
	var panel := UIKit.panel(10, "FlatPanel")
	panel.custom_minimum_size = Vector2(112, 0)
	body.add_child(panel)
	var v := UIKit.vbox(6)
	panel.add_child(v)
	v.add_child(UIKit.label(t("editor_tools"), 11, UIKit.COL_DIM, true))
	for entry in TOOLS:
		var b := UIKit.button(t(entry["label"]), "", "GhostButton", 46)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.icon = _tool_icon(entry["icon"])
		if b.icon != null:
			b.add_theme_constant_override("icon_max_width", 22)
		var tool_id: String = entry["id"]
		b.pressed.connect(func(): _set_tool(tool_id))
		v.add_child(b)
		_tool_buttons[tool_id] = b

	v.add_child(UIKit.divider())
	v.add_child(UIKit.label(t("editor_mode"), 11, UIKit.COL_DIM, true))
	for m in ["single", "rect", "fill"]:
		var b := UIKit.button(t("editor_mode_" + m), "", "GhostButton", 34)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 12)
		var mode_id: String = str(m)
		b.pressed.connect(func(): _set_mode(mode_id))
		v.add_child(b)
		_mode_buttons[mode_id] = b

	v.add_child(UIKit.expand_spacer())
	v.add_child(UIKit.divider())
	var undo_row := HBoxContainer.new()
	undo_row.add_theme_constant_override("separation", 6)
	v.add_child(undo_row)
	var undo := UIKit.icon_button("undo", "Ctrl+Z", 34)
	undo.focus_mode = Control.FOCUS_NONE
	undo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	undo.pressed.connect(_undo_action)
	undo_row.add_child(undo)
	var redo := UIKit.icon_button("redo", "Ctrl+Y", 34)
	redo.focus_mode = Control.FOCUS_NONE
	redo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redo.pressed.connect(_redo_action)
	undo_row.add_child(redo)
	var clear := UIKit.button(t("editor_clear"), "", "GhostButton", 32)
	clear.focus_mode = Control.FOCUS_NONE
	clear.add_theme_font_size_override("font_size", 12)
	clear.pressed.connect(_clear_canvas)
	v.add_child(clear)


func _build_canvas(body: HBoxContainer) -> void:
	var center := VBoxContainer.new()
	center.add_theme_constant_override("separation", 8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)

	var canvas_panel := UIKit.panel(6, "FlatPanel")
	canvas_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_panel.custom_minimum_size = Vector2(480, 420)
	center.add_child(canvas_panel)
	board = EditorBoard.new()
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_panel.add_child(board)
	board.set_level(level)
	board.stroke_started.connect(_push_undo)
	board.paint_requested.connect(_on_paint)
	board.rect_requested.connect(_on_rect)
	board.fill_requested.connect(_on_fill)
	board.hover_changed.connect(_on_hover)

	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 14)
	center.add_child(status)
	_hover_label = UIKit.label("—", 12, UIKit.COL_DIM)
	_hover_label.custom_minimum_size = Vector2(96, 0)
	status.add_child(_hover_label)
	_size_label = UIKit.label("", 12, UIKit.COL_DIM)
	status.add_child(_size_label)
	status.add_child(UIKit.expand_spacer())
	_mode_hint = UIKit.label("", 12, UIKit.COL_DIM)
	status.add_child(_mode_hint)


func _build_inspector(body: HBoxContainer) -> void:
	var panel := UIKit.panel(0, "FlatPanel")
	panel.custom_minimum_size = Vector2(318, 0)
	body.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)
	var v := UIKit.vbox(10)
	margin.add_child(v)

	v.add_child(UIKit.label(t("editor_metadata"), 15, UIKit.COL_GOLD, true))
	v.add_child(UIKit.label(t("editor_name"), 12, UIKit.COL_MUTED))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = t("editor_untitled")
	_name_edit.custom_minimum_size = Vector2(0, 38)
	_name_edit.text_changed.connect(func(text: String):
		if _suppress_meta:
			return
		level.name_zh = text
		level.name_en = text
		_mark_dirty()
	)
	v.add_child(_name_edit)
	v.add_child(UIKit.label(t("editor_author"), 12, UIKit.COL_MUTED))
	_author_edit = LineEdit.new()
	_author_edit.placeholder_text = "—"
	_author_edit.custom_minimum_size = Vector2(0, 36)
	_author_edit.text_changed.connect(func(text: String):
		if _suppress_meta:
			return
		level.author = text
		_mark_dirty()
	)
	v.add_child(_author_edit)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 6)
	v.add_child(size_row)
	size_row.add_child(UIKit.label(t("editor_size"), 12, UIKit.COL_MUTED))
	size_row.add_child(UIKit.expand_spacer())
	_w_option = OptionButton.new()
	_w_option.custom_minimum_size = Vector2(66, 34)
	_h_option = OptionButton.new()
	_h_option.custom_minimum_size = Vector2(66, 34)
	for n in range(4, 21):
		_w_option.add_item(str(n), n)
		_h_option.add_item(str(n), n)
	size_row.add_child(_w_option)
	var x := UIKit.label("×", 13, UIKit.COL_MUTED)
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_row.add_child(x)
	size_row.add_child(_h_option)
	var apply := UIKit.button(t("common_apply"), "", "GhostButton", 34)
	apply.focus_mode = Control.FOCUS_NONE
	apply.add_theme_font_size_override("font_size", 12)
	apply.pressed.connect(_apply_resize)
	size_row.add_child(apply)

	var par_row := HBoxContainer.new()
	par_row.add_theme_constant_override("separation", 8)
	v.add_child(par_row)
	_par_label = UIKit.label("", 12, UIKit.COL_MUTED)
	_par_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	par_row.add_child(_par_label)
	var calc := UIKit.button(t("editor_calc_par"), "bulb", "GhostButton", 34)
	calc.focus_mode = Control.FOCUS_NONE
	calc.add_theme_font_size_override("font_size", 12)
	calc.pressed.connect(_calculate_par)
	par_row.add_child(calc)

	var export_row := HBoxContainer.new()
	export_row.add_theme_constant_override("separation", 8)
	v.add_child(export_row)
	var export := UIKit.button(t("editor_export") + " XSB", "export", "GhostButton", 34)
	export.focus_mode = Control.FOCUS_NONE
	export.add_theme_font_size_override("font_size", 12)
	export.pressed.connect(_export_xsb)
	export_row.add_child(export)
	var export_json := UIKit.button(t("editor_export") + " JSON", "export", "GhostButton", 34)
	export_json.focus_mode = Control.FOCUS_NONE
	export_json.add_theme_font_size_override("font_size", 12)
	export_json.pressed.connect(_export_json)
	export_row.add_child(export_json)

	v.add_child(UIKit.divider())
	_build_hazard_section(v)

	v.add_child(UIKit.divider())
	v.add_child(UIKit.label(t("editor_validation"), 15, UIKit.COL_GOLD, true))
	_validation_box = UIKit.vbox(6)
	v.add_child(_validation_box)

	v.add_child(UIKit.divider())
	var levels_header := HBoxContainer.new()
	v.add_child(levels_header)
	var levels_title := UIKit.label(t("editor_custom_list"), 15, UIKit.COL_GOLD, true)
	levels_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	levels_header.add_child(levels_title)
	var new_btn := UIKit.icon_button("plus", t("levels_new_level"), 30)
	new_btn.focus_mode = Control.FOCUS_NONE
	new_btn.pressed.connect(func(): _confirm_discard(_new_document))
	levels_header.add_child(new_btn)
	_levels_box = UIKit.vbox(6)
	v.add_child(_levels_box)


## Hazards the author can switch on for a workshop level. They run in playtest too.
func _build_hazard_section(v: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	v.add_child(header)
	var title := UIKit.label(t("editor_hazards"), 15, UIKit.COL_GOLD, true)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var count := UIKit.label("", 11, UIKit.COL_MUTED)
	header.add_child(count)
	for hazard_id in LevelData.HAZARD_IDS:
		var check := CheckBox.new()
		check.text = t("hazard_name_" + str(hazard_id))
		check.focus_mode = Control.FOCUS_NONE
		check.add_theme_font_size_override("font_size", 13)
		check.tooltip_text = t("hazard_desc_" + str(hazard_id))
		check.toggled.connect(func(pressed: bool): _on_hazard_toggled(str(hazard_id), pressed))
		v.add_child(check)
		_hazard_checks[hazard_id] = check
	_hazard_hint = UIKit.label(t("editor_hazards_hint"), 11, UIKit.COL_DIM)
	_hazard_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_hazard_hint)


func _on_hazard_toggled(hazard_id: String, pressed: bool) -> void:
	if _suppress_meta or level == null:
		return
	_push_undo()
	level.set_hazard(hazard_id, pressed)
	_mark_dirty()
	Audio.play_sfx("click", -12.0, 0.02)
	_update_validation()
	_refresh_hazard_summary()


func _refresh_hazard_summary() -> void:
	if _hazard_hint == null or level == null:
		return
	var active := level.hazard_list()
	if active.is_empty():
		_hazard_hint.text = t("editor_hazards_none")
		_hazard_hint.add_theme_color_override("font_color", UIKit.COL_DIM)
	else:
		var names: Array = []
		for hazard_id in active:
			names.append(t("hazard_name_" + str(hazard_id)))
		_hazard_hint.text = t("editor_hazards_active", ["、".join(names)])
		_hazard_hint.add_theme_color_override("font_color", UIKit.COL_RED)


# --------------------------------------------------------------------------- #
# Document helpers
# --------------------------------------------------------------------------- #
func _new_level() -> LevelData:
	var lv := LevelData.new()
	lv.width = 8
	lv.height = 8
	lv.builtin = false
	for x in 8:
		lv.walls[Vector2i(x, 0)] = true
		lv.walls[Vector2i(x, 7)] = true
	for y in 8:
		lv.walls[Vector2i(0, y)] = true
		lv.walls[Vector2i(7, y)] = true
	lv.player = Vector2i(2, 3)
	lv.player_found = true
	lv.boxes[Vector2i(3, 3)] = true
	lv.goals[Vector2i(6, 3)] = true
	var number := SaveManager.get_custom_levels().size() + 1
	lv.name_zh = t("editor_new_level_name", [number])
	lv.name_en = lv.name_zh
	lv.author = ""
	return lv


func _new_document() -> void:
	level = _new_level()
	current_id = ""
	dirty = false
	_undo_stack.clear()
	_redo_stack.clear()
	board.set_level(level)
	_refresh_all()


func _refresh_all() -> void:
	if level == null:
		return
	_suppress_meta = true
	_name_edit.text = level.name_zh if not level.name_zh.is_empty() else level.display_name()
	_author_edit.text = level.author
	var wi := _w_option.get_item_index(level.width)
	if wi >= 0:
		_w_option.select(wi)
	var hi := _h_option.get_item_index(level.height)
	if hi >= 0:
		_h_option.select(hi)
	_suppress_meta = false
	_par_label.text = t("editor_par_value", [level.par_pushes, level.par_moves]) \
			if level.par_pushes > 0 else t("editor_par_unknown")
	_size_label.text = "%d × %d" % [level.width, level.height]
	for hazard_id in _hazard_checks.keys():
		var check: CheckBox = _hazard_checks[hazard_id]
		if check != null:
			check.set_pressed_no_signal(level.has_hazard(str(hazard_id)))
	_refresh_hazard_summary()
	_update_dirty_badge()
	_update_mode_hint()
	_update_validation()
	_refresh_level_list()
	board.queue_redraw()


func _update_dirty_badge() -> void:
	if _dirty_label == null:
		return
	_dirty_label.text = t("editor_unsaved_badge") if dirty else t("editor_saved_badge")
	_dirty_label.add_theme_color_override("font_color",
			UIKit.COL_GOLD if dirty else UIKit.COL_DIM)


func _mark_dirty() -> void:
	dirty = true
	_update_dirty_badge()


func _push_undo() -> void:
	if level == null:
		return
	_undo_stack.append({"level": level.to_dict(), "id": current_id})
	if _undo_stack.size() > 80:
		_undo_stack.pop_front()
	_redo_stack.clear()


func _undo_action() -> void:
	if _undo_stack.is_empty():
		toast(t("toast_undo_none"), 1.2)
		return
	_redo_stack.append({"level": level.to_dict(), "id": current_id})
	var snap: Dictionary = _undo_stack.pop_back()
	_restore_snapshot(snap)
	_mark_dirty()


func _redo_action() -> void:
	if _redo_stack.is_empty():
		toast(t("toast_redo_none"), 1.2)
		return
	_undo_stack.append({"level": level.to_dict(), "id": current_id})
	var snap: Dictionary = _redo_stack.pop_back()
	_restore_snapshot(snap)
	_mark_dirty()


func _restore_snapshot(snap: Dictionary) -> void:
	var restored := LevelData.from_dict(snap.get("level", {}))
	restored.builtin = false
	level = restored
	current_id = str(snap.get("id", ""))
	board.set_level(level)
	_refresh_all()


# --------------------------------------------------------------------------- #
# Painting
# --------------------------------------------------------------------------- #
func _set_tool(tool_id: String) -> void:
	tool = tool_id
	board.set_tool(tool_id)
	Audio.play_sfx("click", -12.0, 0.02)
	_refresh_tool_styles()
	_update_mode_hint()


func _refresh_tool_styles() -> void:
	for id in _tool_buttons.keys():
		var b: Button = _tool_buttons[id]
		b.theme_type_variation = "PrimaryButton" if id == tool else "GhostButton"


func _refresh_mode_styles() -> void:
	for id in _mode_buttons.keys():
		var b: Button = _mode_buttons[id]
		b.theme_type_variation = "PrimaryButton" if id == mode else "GhostButton"


func _set_mode(mode_id: String) -> void:
	mode = mode_id
	board.set_mode(mode_id)
	Audio.play_sfx("click", -12.0, 0.02)
	_refresh_mode_styles()
	_update_mode_hint()


func _tool_icon(id: String) -> Texture2D:
	match id:
		"floor":
			return UIKit.art("floor_1")
		"wall":
			return UIKit.art("wall")
		"goal_png":
			return UIKit.art("goal")
		"box_png":
			return UIKit.art("box")
		"player_png":
			return UIKit.art("player_down_0")
		_:
			return UIKit.icon(id)


func _update_mode_hint() -> void:
	if _mode_hint == null:
		return
	match mode:
		"rect":
			_mode_hint.text = t("editor_hover_hint") + "  ·  " + t("editor_mode_rect")
		"fill":
			_mode_hint.text = t("editor_hover_hint") + "  ·  " + t("editor_mode_fill")
		_:
			_mode_hint.text = t("editor_hover_hint")
	_mode_hint.text += "   ·   " + t("editor_test_hint")


func _on_hover(pos: Vector2i) -> void:
	if _hover_label == null:
		return
	if pos.x < 0:
		_hover_label.text = "—"
	else:
		_hover_label.text = "(%d, %d)" % [pos.x, pos.y]


func _on_paint(pos: Vector2i, erase: bool) -> void:
	_apply_paint(pos, "erase" if erase else tool)
	_after_edit()


func _on_rect(rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			_apply_paint(Vector2i(x, y), tool)
	_after_edit()


func _on_fill(pos: Vector2i, erase: bool) -> void:
	var kind := "erase" if erase else tool
	_flood_fill(pos, kind)
	_after_edit()


func _after_edit() -> void:
	_mark_dirty()
	board.queue_redraw()
	_update_validation()
	_size_label.text = "%d × %d" % [level.width, level.height]


func _apply_paint(pos: Vector2i, kind: String) -> void:
	if not level.in_bounds(pos):
		return
	match kind:
		"erase":
			level.walls.erase(pos)
			level.goals.erase(pos)
			level.boxes.erase(pos)
			if level.player_found and level.player == pos:
				level.player_found = false
				level.player = Vector2i(-1, -1)
		"floor":
			level.walls.erase(pos)
			level.goals.erase(pos)
			level.boxes.erase(pos)
		"wall":
			if level.player_found and level.player == pos:
				return
			level.walls[pos] = true
			level.goals.erase(pos)
			level.boxes.erase(pos)
		"goal":
			level.walls.erase(pos)
			level.goals[pos] = true
		"box":
			if level.player_found and level.player == pos:
				return
			level.walls.erase(pos)
			if level.boxes.has(pos):
				level.boxes.erase(pos)
			else:
				level.boxes[pos] = true
		"player":
			level.walls.erase(pos)
			level.boxes.erase(pos)
			level.player = pos
			level.player_found = true


func _flood_fill(start: Vector2i, kind: String) -> void:
	if not level.in_bounds(start):
		_apply_paint(start, kind)
		return
	var target_wall := level.walls.has(start)
	if kind == "wall":
		target_wall = false
	elif kind == "floor" or kind == "erase":
		target_wall = true
	else:
		_apply_paint(start, kind)
		return
	var seen := {start: true}
	var queue: Array = [start]
	var head := 0
	var guard := 0
	while head < queue.size() and guard < 5000:
		guard += 1
		var c: Vector2i = queue[head]
		head += 1
		var is_wall := level.walls.has(c)
		if is_wall != target_wall:
			continue
		_apply_paint(c, kind)
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			var n: Vector2i = c + d
			if level.in_bounds(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)


func _clear_canvas() -> void:
	_modal_open = true
	var do_clear := func():
		_modal_open = false
		_push_undo()
		level.walls.clear()
		level.goals.clear()
		level.boxes.clear()
		level.player_found = false
		level.player = Vector2i(-1, -1)
		for x in level.width:
			level.walls[Vector2i(x, 0)] = true
			level.walls[Vector2i(x, level.height - 1)] = true
		for y in level.height:
			level.walls[Vector2i(0, y)] = true
			level.walls[Vector2i(level.width - 1, y)] = true
		_after_edit()
		board.queue_redraw()
	var cancel_clear := func():
		_modal_open = false
	UIKit.confirm(self, t("editor_clear_title"), t("editor_clear_body"), t("editor_clear"),
			do_clear, cancel_clear, true)


# --------------------------------------------------------------------------- #
# Validation / metadata
# --------------------------------------------------------------------------- #
func _update_validation() -> void:
	if _validation_box == null:
		return
	for child in _validation_box.get_children():
		_validation_box.remove_child(child)
		child.queue_free()
	var issues := level.validate()
	if issues.is_empty():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_validation_box.add_child(row)
		var icon := TextureRect.new()
		icon.texture = UIKit.icon("check")
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = UIKit.COL_GREEN
		row.add_child(icon)
		row.add_child(UIKit.label(t("editor_valid"), 12, UIKit.COL_GREEN))
	else:
		var shown := 0
		for issue in issues:
			if shown >= 6:
				break
			shown += 1
			var is_error := str(issue.get("level", "error")) == "error"
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			_validation_box.add_child(row)
			var icon := TextureRect.new()
			icon.texture = UIKit.icon("close" if is_error else "info")
			icon.custom_minimum_size = Vector2(16, 16)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.modulate = UIKit.COL_RED if is_error else UIKit.COL_GOLD
			row.add_child(icon)
			var text := UIKit.label(t(str(issue.get("code", "")), issue.get("args", [])),
					12, UIKit.COL_RED if is_error else UIKit.COL_GOLD)
			text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(text)
	var counts := UIKit.label("箱 %d  ·  目标 %d" % [level.box_count(), level.goal_count()],
			12, UIKit.COL_MUTED)
	_validation_box.add_child(counts)


func _apply_resize() -> void:
	var nw: int = _w_option.get_item_id(_w_option.selected)
	var nh: int = _h_option.get_item_id(_h_option.selected)
	if nw == level.width and nh == level.height:
		return
	_push_undo()
	var old := level
	var lv := LevelData.new()
	lv.id = old.id
	lv.name_zh = old.name_zh
	lv.name_en = old.name_en
	lv.tip_zh = old.tip_zh
	lv.tip_en = old.tip_en
	lv.author = old.author
	lv.par_moves = old.par_moves
	lv.par_pushes = old.par_pushes
	lv.copy_hazards_from(old)
	lv.builtin = false
	lv.width = nw
	lv.height = nh
	for y in mini(old.height, nh):
		for x in mini(old.width, nw):
			var p := Vector2i(x, y)
			if old.walls.has(p):
				lv.walls[p] = true
			if old.goals.has(p):
				lv.goals[p] = true
			if old.boxes.has(p):
				lv.boxes[p] = true
			if old.player_found and old.player == p:
				lv.player = p
				lv.player_found = true
	for x in nw:
		for y in [0, nh - 1]:
			var p := Vector2i(x, y)
			if (x >= old.width or y >= old.height) and not lv.walls.has(p) \
					and not lv.goals.has(p) and not lv.boxes.has(p) \
					and lv.player != p:
				lv.walls[p] = true
	for y in nh:
		for x in [0, nw - 1]:
			var p := Vector2i(x, y)
			if (x >= old.width or y >= old.height) and not lv.walls.has(p) \
					and not lv.goals.has(p) and not lv.boxes.has(p) \
					and lv.player != p:
				lv.walls[p] = true
	level = lv
	board.set_level(level)
	_mark_dirty()
	_refresh_all()


func _calculate_par() -> void:
	_apply_meta()
	toast(t("editor_calc_running"), 1.2)
	await get_tree().process_frame
	var solver := SokobanSolver.new()
	if not solver.setup_from_level(level):
		toast(t("editor_calc_failed"), 2.5)
		return
	var result := solver.solve(3.0, 120000)
	if bool(result.get("solvable", false)):
		level.par_pushes = int(result["pushes"])
		level.par_moves = int(result["moves"])
		_mark_dirty()
		_par_label.text = t("editor_par_value", [level.par_pushes, level.par_moves])
		toast(t("editor_calc_done", [level.par_pushes, level.par_moves]), 3.0)
		Audio.play_sfx("goal", -6.0)
	elif result.get("solvable") == false:
		toast(t("editor_calc_unsolvable"), 3.0)
		Audio.play_sfx("error", -6.0)
	else:
		toast(t("editor_calc_failed"), 3.0)


func _apply_meta() -> void:
	var new_name := _name_edit.text.strip_edges()
	level.name_zh = new_name
	level.name_en = new_name
	level.author = _author_edit.text.strip_edges()


# --------------------------------------------------------------------------- #
# Save / load / import / export
# --------------------------------------------------------------------------- #
func _save() -> bool:
	_apply_meta()
	if level.display_name().is_empty() or level.name_zh.is_empty():
		toast(t("editor_need_name"), 2.0)
		_name_edit.grab_focus()
		return false
	var errors := level.error_texts()
	if not errors.is_empty():
		toast(errors[0], 2.8)
		return false
	var dict := level.to_dict()
	dict["id"] = current_id
	dict["builtin"] = false
	current_id = SaveManager.save_custom_level(dict)
	level.id = current_id
	dirty = false
	_update_dirty_badge()
	_refresh_level_list()
	toast(t("editor_saved"), 2.0)
	Audio.play_sfx("goal", -8.0)
	return true


func _test_level() -> void:
	_apply_meta()
	var errors := level.error_texts()
	if not errors.is_empty():
		_show_info_modal(t("editor_invalid_title"), errors)
		return
	if level.par_pushes <= 0:
		toast(t("editor_calc_running"), 1.0)
		await get_tree().process_frame
		var solver := SokobanSolver.new()
		if solver.setup_from_level(level):
			var result := solver.solve(2.5, 90000)
			if bool(result.get("solvable", false)):
				level.par_pushes = int(result["pushes"])
				level.par_moves = int(result["moves"])
				_mark_dirty()
			elif result.get("solvable") == false:
				_show_info_modal(t("editor_invalid_title"), [t("editor_calc_unsolvable")])
				return
	if _name_edit.text.strip_edges().is_empty():
		_name_edit.text = t("editor_untitled")
		_apply_meta()
	var draft := {
		"level": level,
		"level_id": current_id,
		"dirty": dirty,
	}
	Game.start_playtest(level, draft)


func _refresh_level_list() -> void:
	if _levels_box == null:
		return
	for child in _levels_box.get_children():
		_levels_box.remove_child(child)
		child.queue_free()
	var levels := SaveManager.get_custom_levels()
	if levels.is_empty():
		_levels_box.add_child(UIKit.label(t("editor_no_levels"), 12, UIKit.COL_DIM))
		return
	for dict in levels:
		var lv := Game.catalog.custom_level_from_dict(dict)
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = UIKit.COL_PANEL_2 if lv.id != current_id else UIKit.COL_PANEL_3
		style.border_color = UIKit.COL_GOLD if lv.id == current_id else UIKit.COL_BORDER
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.content_margin_left = 10
		style.content_margin_right = 8
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		card.add_theme_stylebox_override("panel", style)
		_levels_box.add_child(card)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		card.add_child(row)
		var info := UIKit.vbox(1)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		info.add_child(UIKit.label(lv.display_name(), 12, UIKit.COL_TEXT, true))
		var meta := "%d×%d" % [lv.width, lv.height]
		if lv.par_pushes > 0:
			meta += "  ·  %d 推" % lv.par_pushes
		var hazard_names: Array = []
		for hazard_id in lv.hazard_list():
			hazard_names.append(t("hazard_name_" + str(hazard_id)))
		if not hazard_names.is_empty():
			meta += "  ·  " + "、".join(hazard_names)
		info.add_child(UIKit.label(meta, 10, UIKit.COL_DIM))
		var open := UIKit.icon_button("folder", t("editor_open"), 26)
		open.focus_mode = Control.FOCUS_NONE
		var dict_copy: Dictionary = dict
		open.pressed.connect(func(): _confirm_discard(func(): _open_saved(dict_copy)))
		row.add_child(open)
		var del := UIKit.icon_button("trash", t("common_delete"), 26)
		del.focus_mode = Control.FOCUS_NONE
		del.pressed.connect(func(): _confirm_delete(dict_copy))
		row.add_child(del)


func _open_saved(dict: Dictionary) -> void:
	level = Game.catalog.custom_level_from_dict(dict)
	level.builtin = false
	current_id = level.id
	dirty = false
	_undo_stack.clear()
	_redo_stack.clear()
	board.set_level(level)
	_refresh_all()
	toast(t("editor_saved_badge"), 1.2)


func _confirm_delete(dict: Dictionary) -> void:
	var name := str(dict.get("name_zh", dict.get("name_en", "")))
	_modal_open = true
	var level_id := str(dict.get("id", ""))
	var do_delete := func():
		_modal_open = false
		SaveManager.delete_custom_level(level_id)
		if level_id == current_id:
			current_id = ""
		_refresh_level_list()
		toast(t("common_delete"), 1.2)
	var cancel_delete := func():
		_modal_open = false
	UIKit.confirm(self, t("editor_delete_title"), t("editor_delete_body", [name]),
			t("dialog_delete"), do_delete, cancel_delete, true)


func _export_xsb() -> void:
	DisplayServer.clipboard_set(level.to_xsb())
	toast(t("editor_exported"), 1.6)


func _export_json() -> void:
	var data := level.to_dict()
	data["author"] = _author_edit.text
	DisplayServer.clipboard_set(JSON.stringify(data, "\t"))
	toast(t("editor_exported"), 1.6)


func _open_import() -> void:
	_modal_open = true
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := UIKit.panel(24, "CardPanel")
	card.custom_minimum_size = Vector2(600, 0)
	center.add_child(card)
	var v := UIKit.vbox(12)
	card.add_child(v)
	v.add_child(UIKit.heading(t("editor_import_title"), 22, UIKit.COL_TEXT))
	var hint := UIKit.label(t("editor_import_hint"), 13, UIKit.COL_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, 240)
	edit.placeholder_text = "#######\n# @$. #\n#######"
	edit.add_theme_font_override("font", UIKit.font())
	v.add_child(edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var cancel := UIKit.button(t("common_cancel"), "", "GhostButton", 40)
	cancel.pressed.connect(func():
		_modal_open = false
		layer.queue_free()
	)
	row.add_child(cancel)
	var do_import := UIKit.button(t("editor_import"), "import", "PrimaryButton", 40)
	do_import.pressed.connect(func():
		var parsed := _parse_xsb(edit.text)
		if parsed == null:
			toast(t("editor_import_failed"), 2.2)
			return
		level = parsed
		current_id = ""
		dirty = true
		_undo_stack.clear()
		_redo_stack.clear()
		board.set_level(level)
		_refresh_all()
		_modal_open = false
		layer.queue_free()
		toast(t("editor_imported", [1]), 1.8)
	)
	row.add_child(do_import)
	do_import.grab_focus()
	edit.grab_focus()


func _parse_xsb(text: String) -> LevelData:
	var trimmed := text.strip_edges()
	if trimmed.begins_with("{"):
		var parsed: Variant = JSON.parse_string(trimmed)
		if parsed is Dictionary and (parsed as Dictionary).get("rows") is Array:
			var from_json := LevelData.from_dict(parsed)
			from_json.builtin = false
			if from_json.name_zh.is_empty():
				var number := SaveManager.get_custom_levels().size() + 1
				from_json.name_zh = t("editor_new_level_name", [number])
				from_json.name_en = from_json.name_zh
			if from_json.player_found and not from_json.boxes.is_empty() \
					and not from_json.goals.is_empty():
				return from_json
		return null
	var lines: Array = []
	for raw in text.split("\n"):
		var line := raw.trim_suffix("\r")
		if line.strip_edges().is_empty():
			if lines.is_empty():
				continue
			break
		lines.append(line)
	if lines.size() < 3:
		return null
	var lv := LevelData.from_rows(lines)
	if not lv.player_found or lv.boxes.is_empty() or lv.goals.is_empty():
		return null
	lv.builtin = false
	var number := SaveManager.get_custom_levels().size() + 1
	lv.name_zh = t("editor_new_level_name", [number])
	lv.name_en = lv.name_zh
	return lv


func _show_info_modal(title: String, lines: Array) -> void:
	_modal_open = true
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var card := UIKit.panel(26, "CardPanel")
	card.custom_minimum_size = Vector2(480, 0)
	center.add_child(card)
	var v := UIKit.vbox(12)
	card.add_child(v)
	v.add_child(UIKit.heading(title, 22, UIKit.COL_TEXT))
	for line in lines:
		var l := UIKit.label("•  " + str(line), 14, UIKit.COL_MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(l)
	var ok := UIKit.button(t("common_ok"), "", "PrimaryButton", 42)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(func():
		_modal_open = false
		layer.queue_free()
	)
	v.add_child(ok)
	ok.grab_focus()


# --------------------------------------------------------------------------- #
# Navigation
# --------------------------------------------------------------------------- #
func _go_back() -> void:
	var go_menu := func():
		Game.goto("menu")
	_confirm_discard(go_menu)


func _confirm_discard(action: Callable) -> void:
	if not dirty:
		action.call()
		return
	_modal_open = true
	var do_discard := func():
		_modal_open = false
		action.call()
	var cancel_discard := func():
		_modal_open = false
	UIKit.confirm(self, t("editor_discard_title"), t("editor_discard_body"),
			t("common_confirm"), do_discard, cancel_discard)


func _unhandled_input(event: InputEvent) -> void:
	if _modal_open:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_S:
			_save()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode == KEY_Z and not event.shift_pressed:
			_undo_action()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and (event.keycode == KEY_Y
				or (event.keycode == KEY_Z and event.shift_pressed)):
			_redo_action()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_SPACE:
			_test_level()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_go_back()
			get_viewport().set_input_as_handled()

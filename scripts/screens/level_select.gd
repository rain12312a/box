extends ScreenBase
## Campaign map: chapters on the left, level cards on the right.

var _chapter_index := 0
var _show_custom := false
var _content: VBoxContainer
var _tabs: Array[Button] = []
var _custom_tab: Button
var _stars_label: Label


func _build() -> void:
	add_background("level_select")
	Audio.play_music("music_menu")
	var chapter_param: Variant = params.get("chapter", 0)
	if chapter_param is String and str(chapter_param) == "custom":
		_show_custom = true
	else:
		_chapter_index = clampi(int(chapter_param), 0, maxi(Game.catalog.chapters.size() - 1, 0))

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 66)
	margin.add_theme_constant_override("margin_right", 66)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 30)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	# ---------------------------------------------------------------- header
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	var back := UIKit.icon_button("arrow_left", t("common_back"), 44)
	back.pressed.connect(func(): Game.goto("menu"))
	header.add_child(back)
	header.add_child(UIKit.heading(t("levels_title"), 30, UIKit.COL_TEXT))
	header.add_child(UIKit.expand_spacer())
	var star_icon := UIKit.star_icon(24)
	header.add_child(star_icon)
	_stars_label = UIKit.label("", 18, UIKit.COL_GOLD, true)
	header.add_child(_stars_label)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 26)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	# ------------------------------------------------------------- sidebar
	var sidebar := VBoxContainer.new()
	sidebar.add_theme_constant_override("separation", 8)
	sidebar.custom_minimum_size = Vector2(228, 0)
	body.add_child(sidebar)

	for i in Game.catalog.chapters.size():
		var chapter: Dictionary = Game.catalog.chapters[i]
		var btn := UIKit.button("", "", "GhostButton", 58)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 16)
		btn.toggle_mode = false
		var count := (chapter["levels"] as Array).size()
		var done := Game.catalog.chapter_completed_count(i)
		var unlocked := Game.catalog.is_chapter_unlocked(i)
		var prefix := "%02d" % (i + 1)
		btn.text = "  %s  %s" % [prefix, Loc.chapter_name(chapter)]
		if not unlocked:
			btn.icon = UIKit.icon("lock")
			btn.add_theme_constant_override("icon_max_width", 18)
		var idx := i
		btn.pressed.connect(func(): _select_chapter(idx))
		sidebar.add_child(btn)
		_tabs.append(btn)
		var mini := UIKit.label("      %d / %d" % [done, count], 12,
				UIKit.COL_DIM if unlocked else UIKit.COL_DIM)
		sidebar.add_child(mini)
		mini.mouse_filter = Control.MOUSE_FILTER_IGNORE

	sidebar.add_child(UIKit.divider())
	_custom_tab = UIKit.button("  " + t("levels_custom"), "pencil", "GhostButton", 58)
	_custom_tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_custom_tab.add_theme_font_size_override("font_size", 16)
	_custom_tab.pressed.connect(func(): _select_custom())
	sidebar.add_child(_custom_tab)
	var custom_count := UIKit.label("      %d" % SaveManager.get_custom_levels().size(), 12,
			UIKit.COL_DIM)
	sidebar.add_child(custom_count)
	sidebar.add_child(UIKit.expand_spacer())

	var legend := UIKit.label(t("levels_custom_hint"), 12, UIKit.COL_DIM)
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.custom_minimum_size = Vector2(210, 0)
	sidebar.add_child(legend)

	# ------------------------------------------------------------- content
	var content_panel := UIKit.panel(24, "CardPanel")
	content_panel.add_theme_stylebox_override("panel", UIKit.panel_style(Color("111a2b"),
			UIKit.COL_BORDER, 1, 18, 24))
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content_panel)
	_content = UIKit.vbox(16)
	content_panel.add_child(_content)

	_refresh_tabs()
	_refresh_content()


func _select_chapter(index: int) -> void:
	if not Game.catalog.is_chapter_unlocked(index):
		toast(t("toast_chapter_locked"))
		Audio.play_sfx("locked", -4.0, 0.0)
		return
	_show_custom = false
	_chapter_index = index
	Audio.play_sfx("click", -10.0)
	_refresh_tabs()
	_refresh_content()


func _select_custom() -> void:
	_show_custom = true
	Audio.play_sfx("click", -10.0)
	_refresh_tabs()
	_refresh_content()


func _refresh_tabs() -> void:
	for i in _tabs.size():
		var selected := (not _show_custom) and i == _chapter_index
		_tabs[i].theme_type_variation = "PrimaryButton" if selected else "GhostButton"
		_tabs[i].add_theme_font_override("font", UIKit.font(selected))
	_custom_tab.theme_type_variation = "PrimaryButton" if _show_custom else "GhostButton"
	_custom_tab.add_theme_font_override("font", UIKit.font(_show_custom))
	var total_stars := 0
	var max_stars := 0
	for chapter in Game.catalog.chapters:
		for level in chapter["levels"]:
			max_stars += 3
			total_stars += SaveManager.stars_for(level.id)
	_stars_label.text = t("levels_total_stars", [total_stars, max_stars])


func _refresh_content() -> void:
	for child in _content.get_children():
		child.queue_free()
	if _show_custom:
		_build_custom()
	else:
		_build_chapter()


func _build_chapter() -> void:
	var chapter: Dictionary = Game.catalog.get_chapter(_chapter_index)
	var levels: Array = chapter.get("levels", [])
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_content.add_child(header)
	var title_box := UIKit.vbox(4)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	title_box.add_child(UIKit.label("第 %d 章" % (_chapter_index + 1), 13, UIKit.COL_TEAL, true))
	title_box.add_child(UIKit.heading(Loc.chapter_name(chapter), 26, UIKit.COL_TEXT))
	var desc := UIKit.label(Loc.chapter_desc(chapter), 14, UIKit.COL_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_box.add_child(desc)
	var done := Game.catalog.chapter_completed_count(_chapter_index)
	var progress_box := UIKit.vbox(6)
	progress_box.custom_minimum_size = Vector2(210, 0)
	progress_box.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_child(progress_box)
	var prog := ProgressBar.new()
	prog.max_value = maxi(levels.size(), 1)
	prog.value = done
	prog.show_percentage = false
	prog.custom_minimum_size = Vector2(200, 8)
	prog.add_theme_stylebox_override("background", _bar_style(UIKit.COL_BG_2))
	prog.add_theme_stylebox_override("fill", _bar_style(UIKit.COL_TEAL))
	progress_box.add_child(prog)
	progress_box.add_child(UIKit.label(t("levels_chapter_progress", [done, levels.size()]),
			12, UIKit.COL_MUTED))

	_content.add_child(UIKit.divider())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var resume := Game.catalog.resume_level()
	for level in levels:
		grid.add_child(_make_level_card(level, resume != null and resume.id == level.id))


func _build_custom() -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	_content.add_child(header)
	var title_box := UIKit.vbox(4)
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)
	title_box.add_child(UIKit.label("WORKSHOP", 13, UIKit.COL_TEAL, true))
	title_box.add_child(UIKit.heading(t("levels_custom"), 26, UIKit.COL_TEXT))
	title_box.add_child(UIKit.label(t("levels_custom_hint"), 14, UIKit.COL_MUTED))
	var new_button := UIKit.button(t("levels_new_level"), "plus", "PrimaryButton", 46)
	new_button.pressed.connect(func(): Game.start_editor())
	header.add_child(new_button)
	_content.add_child(UIKit.divider())

	var custom_levels := Game.catalog.custom_levels()
	if custom_levels.is_empty():
		var empty := VBoxContainer.new()
		empty.alignment = BoxContainer.ALIGNMENT_CENTER
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.add_theme_constant_override("separation", 16)
		_content.add_child(empty)
		empty.add_child(UIKit.expand_spacer())
		var icon := TextureRect.new()
		icon.texture = UIKit.icon("pencil")
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.modulate = UIKit.COL_DIM
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty.add_child(icon)
		var l := UIKit.label(t("levels_custom_empty"), 16, UIKit.COL_MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(l)
		var open := UIKit.button(t("menu_editor"), "pencil", "GhostButton", 46)
		open.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		open.pressed.connect(func(): Game.start_editor())
		empty.add_child(open)
		empty.add_child(UIKit.expand_spacer())
		return

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	for level in custom_levels:
		var card := _make_custom_card(level)
		grid.add_child(card)


func _make_level_card(level: LevelData, is_resume: bool) -> Control:
	var unlocked := Game.catalog.is_level_unlocked(level)
	var card := Button.new()
	card.theme_type_variation = "LevelCard"
	card.custom_minimum_size = Vector2(142, 124)
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = level.display_name() if unlocked else Game.catalog.level_lock_reason(level)
	if is_resume and unlocked:
		card.add_theme_stylebox_override("normal", _card_style(UIKit.COL_PANEL_2, UIKit.COL_GOLD, 2))
		card.add_theme_stylebox_override("hover", _card_style(UIKit.COL_PANEL_3, UIKit.COL_GOLD_LIGHT, 2))
	else:
		card.add_theme_stylebox_override("normal", _card_style(UIKit.COL_PANEL_2,
				UIKit.COL_BORDER_LIGHT, 1))
		card.add_theme_stylebox_override("hover", _card_style(UIKit.COL_PANEL_3,
				UIKit.COL_GOLD, 1))

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 10
	content.offset_bottom = -10
	content.add_theme_constant_override("separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(top)
	var number := UIKit.label("%02d" % (level.index + 1), 23,
			UIKit.COL_GOLD if unlocked else UIKit.COL_DIM, true)
	top.add_child(number)
	top.add_child(UIKit.expand_spacer())
	if unlocked:
		var rec := SaveManager.get_level_record(level.id)
		var stars := int(rec.get("stars", 0))
		var star_icon := UIKit.star_icon(15, stars > 0)
		top.add_child(star_icon)
		var stars_text := UIKit.label(str(stars), 12,
				UIKit.COL_GOLD if stars > 0 else UIKit.COL_DIM)
		top.add_child(stars_text)
	else:
		var lock := TextureRect.new()
		lock.texture = UIKit.icon("lock")
		lock.custom_minimum_size = Vector2(15, 15)
		lock.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lock.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		lock.modulate = UIKit.COL_DIM
		lock.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(lock)

	var name_label := UIKit.label(level.display_name(), 13,
			UIKit.COL_TEXT if unlocked else UIKit.COL_DIM)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.custom_minimum_size = Vector2(0, 34)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)

	content.add_child(UIKit.expand_spacer())
	var bottom_text := ""
	var bottom_color := UIKit.COL_DIM
	if unlocked:
		var rec := SaveManager.get_level_record(level.id)
		if SaveManager.is_completed(level.id):
			bottom_text = t("levels_best", [int(rec.get("best_pushes", 0))])
			bottom_color = UIKit.COL_TEAL
		elif is_resume:
			bottom_text = t("levels_resume")
			bottom_color = UIKit.COL_GOLD
		else:
			bottom_text = t("levels_not_played")
	else:
		bottom_text = t("common_locked")
	var bottom := UIKit.label(bottom_text, 11, bottom_color)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bottom)

	card.pressed.connect(func():
		if unlocked:
			Game.start_campaign(level.id)
		else:
			Audio.play_sfx("locked", -4.0, 0.0)
			toast(Game.catalog.level_lock_reason(level))
	)
	return card


func _make_custom_card(level: LevelData) -> Control:
	var card := Button.new()
	card.theme_type_variation = "LevelCard"
	card.custom_minimum_size = Vector2(142, 124)
	card.focus_mode = Control.FOCUS_ALL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.tooltip_text = t("levels_custom_hint")
	card.add_theme_stylebox_override("normal", _card_style(UIKit.COL_PANEL_2,
			UIKit.COL_BORDER_LIGHT, 1))
	card.add_theme_stylebox_override("hover", _card_style(UIKit.COL_PANEL_3,
			UIKit.COL_TEAL, 1))

	var content := VBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 12
	content.offset_right = -12
	content.offset_top = 10
	content.offset_bottom = -10
	content.add_theme_constant_override("separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(content)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(top)
	var badge := UIKit.label("W", 18, UIKit.COL_TEAL, true)
	top.add_child(badge)
	top.add_child(UIKit.expand_spacer())
	var rec := SaveManager.get_level_record(level.id)
	var stars := int(rec.get("stars", 0))
	top.add_child(UIKit.star_icon(14, stars > 0))
	top.add_child(UIKit.label(str(stars), 12,
			UIKit.COL_GOLD if stars > 0 else UIKit.COL_DIM))

	var name_label := UIKit.label(level.display_name(), 13, UIKit.COL_TEXT)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.max_lines_visible = 2
	name_label.custom_minimum_size = Vector2(0, 34)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(name_label)
	content.add_child(UIKit.expand_spacer())

	var info := "‹›  %d×%d" % [level.width, level.height]
	if level.par_pushes > 0:
		info = t("levels_best", [level.par_pushes])
	var hazard_names: Array = []
	for hazard_id in level.hazard_list():
		hazard_names.append(t("hazard_name_" + str(hazard_id)))
	if not hazard_names.is_empty():
		info += "  ·  " + "、".join(hazard_names)
		card.tooltip_text = t("levels_custom_hazard_hint", ["、".join(hazard_names)])
	var bottom := UIKit.label(info, 11,
			UIKit.COL_RED if not hazard_names.is_empty() else UIKit.COL_MUTED)
	bottom.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.max_lines_visible = 1
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(bottom)

	card.pressed.connect(func(): Game.start_custom(level))
	card.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			Game.start_editor(level)
			card.accept_event()
	)
	return card


func _card_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(14)
	s.content_margin_left = 0
	s.content_margin_right = 0
	s.content_margin_top = 0
	s.content_margin_bottom = 0
	s.shadow_color = Color(0, 0, 0, 0.25)
	s.shadow_size = 8
	s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	return s


func _bar_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(4)
	return s


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		Game.goto("menu")
		get_viewport().set_input_as_handled()

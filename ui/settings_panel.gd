class_name SettingsPanel
extends VBoxContainer
## Reusable settings form used by the settings screen and the pause menu.

signal notify(text: String)

var _rebuilding := false


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_rebuild()
	Loc.language_changed.connect(_on_language_changed)


func _on_language_changed() -> void:
	if not _rebuilding:
		call_deferred("_rebuild")


func _rebuild() -> void:
	if _rebuilding:
		return
	_rebuilding = true
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_build_audio()
	_build_display()
	_build_gameplay()
	_build_controls()
	_build_data()
	_build_about()
	_rebuilding = false


func _section(title: String) -> void:
	add_child(UIKit.spacer(0, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	var bar := ColorRect.new()
	bar.color = UIKit.COL_GOLD
	bar.custom_minimum_size = Vector2(4, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	row.add_child(UIKit.label(title, 17, UIKit.COL_GOLD, true))


func _row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var l := UIKit.label(label_text, 15, UIKit.COL_TEXT)
	l.custom_minimum_size = Vector2(150, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	return row


# --------------------------------------------------------------------------- #
func _build_audio() -> void:
	_section(Loc.t("settings_audio"))
	_slider("master_volume", Loc.t("settings_master"), 0.9)
	_slider("music_volume", Loc.t("settings_music"), 0.55)
	_slider("sfx_volume", Loc.t("settings_sfx"), 0.85)


func _slider(key: String, label_text: String, fallback: float) -> void:
	var row := _row(label_text)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(SaveManager.get_setting(key, fallback))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(0, 26)
	row.add_child(slider)
	var value := UIKit.label("%d%%" % int(round(slider.value * 100.0)), 14,
			UIKit.COL_MUTED)
	value.custom_minimum_size = Vector2(52, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	slider.value_changed.connect(func(v: float):
		SaveManager.set_setting(key, v)
		value.text = "%d%%" % int(round(v * 100.0))
	)
	slider.drag_ended.connect(func(_changed: bool):
		Audio.play_sfx("click", -8.0, 0.02)
	)


func _build_display() -> void:
	_section(Loc.t("settings_display"))
	var row := _row(Loc.t("settings_fullscreen"))
	var check := CheckButton.new()
	check.button_pressed = bool(SaveManager.get_setting("fullscreen", false))
	check.text = ""
	check.focus_mode = Control.FOCUS_ALL
	row.add_child(check)
	row.add_child(UIKit.expand_spacer())
	check.toggled.connect(func(on: bool):
		SaveManager.set_setting("fullscreen", on)
	)

	var lang_row := _row(Loc.t("settings_language"))
	lang_row.add_child(UIKit.expand_spacer())
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(180, 40)
	option.add_item(Loc.t("settings_language_zh"), 0)
	option.add_item(Loc.t("settings_language_en"), 1)
	option.selected = 0 if Loc.language == "zh" else 1
	option.item_selected.connect(func(index: int):
		Loc.set_language("zh" if index == 0 else "en")
		Audio.play_sfx("click", -8.0)
	)
	lang_row.add_child(option)


func _build_gameplay() -> void:
	_section(Loc.t("settings_gameplay"))
	_check("screen_shake", Loc.t("settings_shake"), true)
	_check("show_tips", Loc.t("settings_tips"), true)


func _check(key: String, label_text: String, fallback: bool) -> void:
	var row := _row(label_text)
	var check := CheckButton.new()
	check.button_pressed = bool(SaveManager.get_setting(key, fallback))
	check.text = ""
	check.focus_mode = Control.FOCUS_ALL
	row.add_child(check)
	row.add_child(UIKit.expand_spacer())
	check.toggled.connect(func(on: bool):
		SaveManager.set_setting(key, on)
	)


func _build_controls() -> void:
	_section(Loc.t("settings_controls"))
	var text := UIKit.label(Loc.t("settings_controls_text"), 14, UIKit.COL_MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(text)


func _build_data() -> void:
	_section(Loc.t("settings_data"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	var reset := UIKit.button(Loc.t("settings_reset_progress"), "trash", "DangerButton", 44)
	reset.pressed.connect(_on_reset_pressed)
	row.add_child(reset)
	row.add_child(UIKit.expand_spacer())


func _on_reset_pressed() -> void:
	var do_reset := func():
		SaveManager.reset_progress()
		notify.emit(Loc.t("settings_reset_done"))
	var cancel_reset := func():
		pass
	UIKit.confirm(get_tree().current_scene, Loc.t("settings_reset_title"),
			Loc.t("settings_reset_body"), Loc.t("common_reset"), do_reset,
			cancel_reset, true)


func _build_about() -> void:
	_section(Loc.t("settings_about"))
	var text := UIKit.label(Loc.t("settings_about_text"), 13, UIKit.COL_MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(text)
	add_child(UIKit.label(Loc.t("settings_version_line", [Game.VERSION]), 12, UIKit.COL_DIM))
	add_child(UIKit.label(Loc.t("settings_autosave"), 12, UIKit.COL_DIM))
	add_child(UIKit.spacer(0, 10))

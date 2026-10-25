extends ScreenBase
## Full-page settings view.

var _title: Label
var _note: Label

func _build() -> void:
	add_background("settings")
	Audio.play_music("music_menu")
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 120)
	margin.add_theme_constant_override("margin_right", 120)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 32)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 16)
	root.add_child(header)
	var back := UIKit.icon_button("arrow_left", t("common_back"), 44)
	back.pressed.connect(_go_back)
	header.add_child(back)
	_title = UIKit.heading(t("settings_title"), 30, UIKit.COL_TEXT)
	header.add_child(_title)
	header.add_child(UIKit.expand_spacer())
	_note = UIKit.label(t("settings_autosave"), 12, UIKit.COL_DIM)
	header.add_child(_note)
	Loc.language_changed.connect(_retranslate)

	var card := UIKit.panel(0, "CardPanel")
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var margin_box := MarginContainer.new()
	margin_box.add_theme_constant_override("margin_left", 30)
	margin_box.add_theme_constant_override("margin_right", 30)
	margin_box.add_theme_constant_override("margin_top", 20)
	margin_box.add_theme_constant_override("margin_bottom", 20)
	margin_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin_box)
	var panel := SettingsPanel.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.notify.connect(func(text: String): toast(text))
	margin_box.add_child(panel)
	back.grab_focus()


func _retranslate() -> void:
	if _title != null:
		_title.text = t("settings_title")
	if _note != null:
		_note.text = t("settings_autosave")


func _go_back() -> void:
	var target := str(params.get("return_to", "menu"))
	Game.goto(target, params.get("return_params", {}))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_go_back()
		get_viewport().set_input_as_handled()

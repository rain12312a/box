extends ScreenBase
## Upgrade bay: a full body robot whose parts can be clicked and levelled up.

var _selected := "arm"
var _coins_label: Label
var _total_label: Label
var _art_box: Control
var _hotspots: Dictionary = {}
var _glows: Dictionary = {}
var _pip_labels: Dictionary = {}
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_level: Label
var _detail_desc: Label
var _detail_effects: VBoxContainer
var _detail_price: Label
var _detail_buy: Button
var _detail_hint: Label


func _build() -> void:
	add_background("editor")
	Audio.play_music("music_menu")
	if not SaveManager.wallet_changed.is_connected(_refresh):
		SaveManager.wallet_changed.connect(_refresh)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)
	var root := UIKit.vbox(12)
	margin.add_child(root)

	var header := UIKit.hbox(12)
	root.add_child(header)
	var back := UIKit.button(t("common_back"), "arrow_left", "GhostButton", 42)
	back.pressed.connect(func(): Game.goto("menu"))
	header.add_child(back)
	var title_box := UIKit.vbox(0)
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title_box)
	title_box.add_child(UIKit.label(t("robot_kicker"), 11, UIKit.COL_TEAL, true))
	title_box.add_child(UIKit.heading(t("robot_title"), 26, UIKit.COL_TEXT))
	header.add_child(UIKit.expand_spacer())
	var wallet := UIKit.panel(12, "FlatPanel")
	wallet.custom_minimum_size = Vector2(150, 54)
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var wallet_row := UIKit.hbox(8)
	wallet.add_child(wallet_row)
	var coin_icon := TextureRect.new()
	coin_icon.texture = UIKit.icon("coin")
	coin_icon.custom_minimum_size = Vector2(26, 26)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = UIKit.COL_GOLD
	wallet_row.add_child(coin_icon)
	var wallet_box := UIKit.vbox(0)
	wallet_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wallet_row.add_child(wallet_box)
	wallet_box.add_child(UIKit.label(t("shop_wallet"), 11, UIKit.COL_MUTED))
	_coins_label = UIKit.label("0", 20, UIKit.COL_GOLD, true)
	wallet_box.add_child(_coins_label)
	header.add_child(wallet)

	var body := UIKit.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var art_card := UIKit.panel(10, "FlatPanel")
	art_card.custom_minimum_size = Vector2(452, 0)
	body.add_child(art_card)
	_art_box = Control.new()
	_art_box.custom_minimum_size = Vector2(432, 0)
	_art_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_art_box.mouse_filter = Control.MOUSE_FILTER_PASS
	art_card.add_child(_art_box)
	var art := TextureRect.new()
	art.texture = UIKit.art("robot_body")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_box.add_child(art)
	for part_id in RobotUpgrades.ORDER:
		_build_hotspot(part_id)

	var detail := UIKit.panel(20, "CardPanel")
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(detail)
	_build_detail(detail)

	var footer := UIKit.hbox(12)
	root.add_child(footer)
	_total_label = UIKit.label("", 13, UIKit.COL_MUTED)
	footer.add_child(_total_label)
	footer.add_child(UIKit.expand_spacer())
	var reset := UIKit.button(t("robot_reset"), "restart", "GhostButton", 40)
	reset.pressed.connect(_ask_reset)
	footer.add_child(reset)

	_refresh()
	back.grab_focus()


func _build_hotspot(part_id: String) -> void:
	var point := RobotUpgrades.hotspot(part_id)
	var glow := TextureRect.new()
	glow.texture = UIKit.radial_texture(128, Color(0.31, 0.82, 0.77, 0.5),
			Color(0.31, 0.82, 0.77, 0.0))
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.set_anchors_preset(Control.PRESET_CENTER)
	glow.anchor_left = point.x
	glow.anchor_right = point.x
	glow.anchor_top = point.y
	glow.anchor_bottom = point.y
	glow.offset_left = -52
	glow.offset_right = 52
	glow.offset_top = -52
	glow.offset_bottom = 52
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_box.add_child(glow)
	_glows[part_id] = glow

	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.anchor_left = point.x
	b.anchor_right = point.x
	b.anchor_top = point.y
	b.anchor_bottom = point.y
	b.offset_left = -27
	b.offset_right = 27
	b.offset_top = -27
	b.offset_bottom = 27
	b.icon = UIKit.icon(RobotUpgrades.icon_name(part_id))
	b.expand_icon = true
	b.add_theme_constant_override("icon_max_width", 34)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _select(part_id))
	_art_box.add_child(b)
	_hotspots[part_id] = b

	var pip := UIKit.label("", 11, UIKit.COL_TEAL, true)
	pip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pip.anchor_left = point.x
	pip.anchor_right = point.x
	pip.anchor_top = point.y
	pip.anchor_bottom = point.y
	pip.offset_left = -40
	pip.offset_right = 40
	pip.offset_top = 28
	pip.offset_bottom = 48
	pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_box.add_child(pip)
	_pip_labels[part_id] = pip


func _build_detail(card: PanelContainer) -> void:
	var v := UIKit.vbox(10)
	card.add_child(v)
	var top := UIKit.hbox(12)
	v.add_child(top)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(52, 52)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_detail_icon.modulate = UIKit.COL_TEAL
	top.add_child(_detail_icon)
	var name_box := UIKit.vbox(2)
	name_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(name_box)
	_detail_name = UIKit.label("", 20, UIKit.COL_TEXT, true)
	name_box.add_child(_detail_name)
	_detail_level = UIKit.label("", 13, UIKit.COL_TEAL, true)
	name_box.add_child(_detail_level)

	_detail_desc = UIKit.label("", 13, UIKit.COL_MUTED)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(560, 0)
	v.add_child(_detail_desc)
	v.add_child(UIKit.divider())
	_detail_effects = UIKit.vbox(8)
	v.add_child(_detail_effects)
	v.add_child(UIKit.expand_spacer())
	v.add_child(UIKit.divider())

	var buy_row := UIKit.hbox(12)
	v.add_child(buy_row)
	_detail_price = UIKit.label("", 16, UIKit.COL_GOLD, true)
	_detail_price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	buy_row.add_child(_detail_price)
	buy_row.add_child(UIKit.expand_spacer())
	_detail_buy = UIKit.button(t("robot_upgrade"), "plus", "PrimaryButton", 48)
	_detail_buy.custom_minimum_size = Vector2(180, 48)
	_detail_buy.pressed.connect(_buy)
	buy_row.add_child(_detail_buy)

	_detail_hint = UIKit.label("", 12, UIKit.COL_DIM)
	_detail_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_hint.custom_minimum_size = Vector2(560, 0)
	_detail_hint.visible = false
	v.add_child(_detail_hint)


func _select(part_id: String) -> void:
	_selected = part_id
	Audio.play_sfx("click", -8.0)
	_refresh_detail()


func _buy() -> void:
	if SaveManager.upgrade_part(_selected):
		Audio.play_sfx("goal", -5.0, 0.0)
		toast(t("robot_upgraded", [RobotUpgrades.part_name(_selected),
				SaveManager.upgrade_level(_selected)]), 2.0)
	else:
		Audio.play_sfx("error", -10.0)
		var cost := SaveManager.upgrade_cost(_selected)
		toast(t("shop_need_coins", [cost]) if cost > 0 else t("robot_maxed"), 2.2)
	_refresh()


func _ask_reset() -> void:
	if SaveManager.total_upgrade_levels() <= 0:
		toast(t("robot_nothing_to_reset"), 1.8)
		return
	var refund := int(floor(SaveManager.invested_upgrade_coins() * 0.7))
	confirm(t("robot_reset_title"), t("robot_reset_body", [refund]),
			t("robot_reset"), func():
				var got := SaveManager.reset_upgrades()
				toast(t("robot_reset_done", [got]), 2.0)
				_refresh(), true)


func _refresh() -> void:
	if _coins_label == null:
		return
	_coins_label.text = str(SaveManager.wallet_coins())
	if _total_label != null:
		_total_label.text = t("robot_total", [SaveManager.total_upgrade_levels(),
				RobotUpgrades.ORDER.size() * RobotUpgrades.MAX_LEVEL])
	for part_id in _hotspots.keys():
		var level := SaveManager.upgrade_level(str(part_id))
		var b: Button = _hotspots[part_id]
		var accent := UIKit.COL_DIM
		if level >= 3:
			accent = UIKit.COL_GOLD_LIGHT
		elif level == 2:
			accent = UIKit.COL_GOLD
		elif level == 1:
			accent = UIKit.COL_TEAL
		b.add_theme_color_override("icon_normal_color", accent)
		b.add_theme_color_override("icon_hover_color", UIKit.COL_TEAL)
		b.add_theme_color_override("icon_pressed_color", UIKit.COL_GOLD)
		b.modulate = Color(1, 1, 1, 1) if level > 0 else Color(1, 1, 1, 0.72)
		var glow: TextureRect = _glows[part_id]
		glow.modulate = Color(1, 1, 1, [0.0, 0.45, 0.75, 1.0][clampi(level, 0, 3)])
		var pip: Label = _pip_labels[part_id]
		pip.text = "Lv%d" % level if level > 0 else t("robot_locked_short")
		pip.add_theme_color_override("font_color", accent)
	_refresh_detail()


func _refresh_detail() -> void:
	if _detail_name == null:
		return
	var part_id := _selected
	var level := SaveManager.upgrade_level(part_id)
	_detail_icon.texture = UIKit.icon(RobotUpgrades.icon_name(part_id))
	_detail_name.text = RobotUpgrades.part_name(part_id)
	_detail_level.text = t("robot_level", [level, RobotUpgrades.MAX_LEVEL])
	_detail_desc.text = RobotUpgrades.summary(part_id)
	for child in _detail_effects.get_children():
		child.queue_free()
	for i in range(1, RobotUpgrades.MAX_LEVEL + 1):
		var row := UIKit.hbox(10)
		var owned := i <= level
		var pip := UIKit.label("Lv%d" % i, 12,
				UIKit.COL_TEAL if owned else UIKit.COL_DIM, owned)
		pip.custom_minimum_size = Vector2(38, 0)
		row.add_child(pip)
		var text := UIKit.label(RobotUpgrades.effect_text(part_id, i), 14,
				UIKit.COL_TEXT if owned else UIKit.COL_MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		_detail_effects.add_child(row)
	var cost := SaveManager.upgrade_cost(part_id)
	if cost > 0:
		_detail_price.text = t("item_price", [cost])
		_detail_buy.disabled = not SaveManager.can_upgrade(part_id)
		_detail_buy.text = t("robot_upgrade")
	else:
		_detail_price.text = t("robot_maxed")
		_detail_buy.disabled = true
		_detail_buy.text = t("robot_maxed_short")
	if _detail_hint != null:
		var show_hint := RobotUpgrades.can_buy_charges(part_id, level)
		_detail_hint.visible = show_hint
		if show_hint:
			_detail_hint.text = t("ability_charge_price_hint",
					[RobotUpgrades.extra_charge_price(part_id)])

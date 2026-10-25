extends ScreenBase
## Title screen: continue shortcut, main navigation and a save summary.

var _crate_art: TextureRect
var _time := 0.0
var _coins_label: Label

const GM_COIN_GRANT := 100


func _build() -> void:
	add_background("menu")
	Audio.play_music("music_menu")

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 86)
	margin.add_theme_constant_override("margin_right", 78)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 34)
	add_child(margin)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 40)
	margin.add_child(columns)

	# ------------------------------------------------------------------ left
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.custom_minimum_size = Vector2(540, 0)
	columns.add_child(left)

	var logo := TextureRect.new()
	logo.texture = UIKit.art("logo")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(520, 172)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(logo)

	var tagline_row := UIKit.hbox(10)
	left.add_child(tagline_row)
	tagline_row.add_child(UIKit.label(t("app_tagline"), 14, UIKit.COL_MUTED))
	tagline_row.add_child(UIKit.expand_spacer())
	var shop_button := UIKit.button(t("menu_shop"), "shop", "GhostButton", 34)
	shop_button.custom_minimum_size = Vector2(104, 34)
	shop_button.add_theme_font_size_override("font_size", 13)
	shop_button.add_theme_constant_override("icon_max_width", 18)
	shop_button.pressed.connect(func(): Game.goto("shop"))
	tagline_row.add_child(shop_button)
	var coin_chip := UIKit.panel(8, "FlatPanel")
	coin_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var coin_row := UIKit.hbox(6)
	coin_chip.add_child(coin_row)
	var coin_icon := TextureRect.new()
	coin_icon.texture = UIKit.icon("coin")
	coin_icon.custom_minimum_size = Vector2(20, 20)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.modulate = UIKit.COL_GOLD
	coin_row.add_child(coin_icon)
	_coins_label = UIKit.label(str(SaveManager.wallet_coins()), 16, UIKit.COL_GOLD, true)
	coin_row.add_child(_coins_label)
	tagline_row.add_child(coin_chip)
	var gm_button := UIKit.button("GM +100", "", "GhostButton", 34)
	gm_button.custom_minimum_size = Vector2(96, 34)
	gm_button.add_theme_font_size_override("font_size", 13)
	gm_button.tooltip_text = t("gm_grant_tooltip")
	gm_button.pressed.connect(_grant_gm_coins)
	tagline_row.add_child(gm_button)
	if not SaveManager.wallet_changed.is_connected(_on_wallet_changed):
		SaveManager.wallet_changed.connect(_on_wallet_changed)
	left.add_child(UIKit.spacer(0, 16))

	var resume_level := Game.catalog.resume_level()
	var continue_button := UIKit.button(t("menu_continue"), "play", "PrimaryButton", 56)
	continue_button.add_theme_font_size_override("font_size", 21)
	continue_button.pressed.connect(func(): Game.continue_game())
	left.add_child(continue_button)

	var hint_text := t("menu_continue_fresh")
	if resume_level != null:
		var chapter := Game.catalog.get_chapter(resume_level.chapter_index)
		var chapter_label := t("game_chapter_format", [resume_level.chapter_index + 1,
				Loc.chapter_name(chapter)])
		hint_text = chapter_label + "  ·  " + resume_level.display_name()
	var hint := UIKit.label(hint_text, 14, UIKit.COL_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(500, 0)
	left.add_child(hint)
	left.add_child(UIKit.spacer(0, 8))

	var levels_button := UIKit.button(t("menu_levels"), "grid", "GhostButton", 48)
	levels_button.pressed.connect(func():
		var chapter := 0
		if resume_level != null:
			chapter = clampi(resume_level.chapter_index, 0, Game.catalog.chapters.size() - 1)
		Game.goto("level_select", {"chapter": chapter})
	)
	left.add_child(levels_button)

	var editor_button := UIKit.button(t("menu_editor"), "pencil", "GhostButton", 48)
	editor_button.pressed.connect(func(): Game.start_editor())
	left.add_child(editor_button)

	var settings_button := UIKit.button(t("menu_settings"), "settings", "GhostButton", 48)
	settings_button.pressed.connect(func(): Game.goto("settings", {"return_to": "menu"}))
	left.add_child(settings_button)

	var quit_button := UIKit.button(t("menu_quit"), "close", "GhostButton", 48)
	quit_button.pressed.connect(func(): get_tree().quit())
	left.add_child(quit_button)

	left.add_child(UIKit.expand_spacer())
	left.add_child(UIKit.label(t("menu_version", [Game.VERSION]), 13, UIKit.COL_DIM))

	# ----------------------------------------------------------------- right
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	columns.add_child(right)

	right.add_child(UIKit.expand_spacer())

	var crate_wrap := Control.new()
	crate_wrap.custom_minimum_size = Vector2(0, 175)
	crate_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crate_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(crate_wrap)
	var crate_glow := TextureRect.new()
	crate_glow.texture = UIKit.radial_texture(128, Color(0.95, 0.75, 0.35, 0.2),
			Color(0.95, 0.75, 0.35, 0.0))
	crate_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	crate_glow.set_anchors_preset(Control.PRESET_CENTER)
	crate_glow.size = Vector2(330, 330)
	crate_glow.position = Vector2(-165, -165)
	crate_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crate_glow.set_meta("decor", true)
	crate_wrap.add_child(crate_glow)
	_crate_art = TextureRect.new()
	_crate_art.texture = UIKit.art("box")
	_crate_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crate_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crate_art.set_anchors_preset(Control.PRESET_CENTER)
	_crate_art.size = Vector2(168, 168)
	_crate_art.position = Vector2(-84, -84)
	_crate_art.pivot_offset = Vector2(84, 84)
	_crate_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crate_wrap.add_child(_crate_art)

	right.add_child(UIKit.spacer(0, 4))

	var stats_row := HBoxContainer.new()
	stats_row.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(stats_row)
	var stats_card := UIKit.panel(24, "CardPanel")
	stats_card.custom_minimum_size = Vector2(392, 0)
	stats_row.add_child(stats_card)
	var stats := UIKit.vbox(12)
	stats_card.add_child(stats)
	stats.add_child(UIKit.heading(t("menu_stats_title"), 21, UIKit.COL_GOLD))
	stats.add_child(UIKit.divider())

	var total_levels := Game.catalog.total_levels()
	var completed := 0
	var stars := 0
	for chapter in Game.catalog.chapters:
		for level in chapter["levels"]:
			if SaveManager.is_completed(level.id):
				completed += 1
				stars += SaveManager.stars_for(level.id)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats.add_child(grid)
	_stat_row(grid, t("menu_stats_levels"), "%d / %d" % [completed, total_levels])
	_stat_row(grid, t("menu_stats_stars"), "%d / %d" % [stars, total_levels * 3], UIKit.COL_GOLD)
	_stat_row(grid, t("menu_stats_pushes"), str(SaveManager.total_pushes()))
	_stat_row(grid, t("menu_stats_time"), UIKit.format_seconds_long(SaveManager.total_play_seconds()))

	var progress := ProgressBar.new()
	progress.max_value = maxi(total_levels, 1)
	progress.value = completed
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 8)
	progress.add_theme_stylebox_override("background", _bar_style(UIKit.COL_BG_2))
	progress.add_theme_stylebox_override("fill", _bar_style(UIKit.COL_TEAL))
	stats.add_child(progress)

	var bay := UIKit.button(t("menu_robot"), "core", "GhostButton", 42)
	bay.add_theme_font_size_override("font_size", 15)
	bay.pressed.connect(func(): Game.goto("robot"))
	stats.add_child(bay)
	var bay_hint := UIKit.label(t("robot_total", [SaveManager.total_upgrade_levels(),
			RobotUpgrades.ORDER.size() * RobotUpgrades.MAX_LEVEL]), 11, UIKit.COL_DIM)
	bay_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_child(bay_hint)

	right.add_child(UIKit.expand_spacer())

	var credit := UIKit.label(t("menu_credit"), 12, UIKit.COL_DIM)
	credit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credit.custom_minimum_size = Vector2(380, 0)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(credit)

	continue_button.grab_focus()
	set_process(true)
	if SaveManager.consume_starter_gift_announce():
		_announce_starter_gift.call_deferred()


func _announce_starter_gift() -> void:
	Audio.play_sfx("goal", -6.0, 0.0)
	toast(t("starter_gift_toast"), 3.6)


func _on_wallet_changed() -> void:
	if _coins_label != null:
		_coins_label.text = str(SaveManager.wallet_coins())


## Debug grant: one press tops the wallet up by 100 coins.
func _grant_gm_coins() -> void:
	SaveManager.add_coins(GM_COIN_GRANT)
	Audio.play_sfx("goal", -6.0, 0.0)
	toast(t("gm_granted", [GM_COIN_GRANT]), 1.6)


func _stat_row(grid: GridContainer, key: String, value: String,
		color := UIKit.COL_TEXT) -> void:
	grid.add_child(UIKit.label(key, 15, UIKit.COL_MUTED))
	var v := UIKit.label(value, 17, color, true)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(v)


func _bar_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(5)
	return s


func _process(delta: float) -> void:
	_time += delta
	if _crate_art != null:
		_crate_art.rotation = sin(_time * 0.7) * 0.03
		_crate_art.position.y = -84.0 + sin(_time * 1.1) * 5.0

extends ScreenBase
## Gameplay screen: board, HUD, hint, pause menu and result overlay.

const UP := Vector2i(0, -1)
const DOWN := Vector2i(0, 1)
const LEFT := Vector2i(-1, 0)
const RIGHT := Vector2i(1, 0)
## Keeps menus, result cards and toasts above the board art (sprites sit at z 3..30).
const OVERLAY_Z := 200

var level: LevelData
var state: SokobanState
var board: BoardView
var board_holder: Control
var shake_root: Control

var _overlay: Control = null
var _pause_overlay: Control = null
var _won := false
var _elapsed := 0.0
var _hud_accum := 0.0
var _confirm_open := false
var _touch_start := Vector2.ZERO
var _touch_active := false
var _tip_panel: Control = null
var _hint_token := 0
var _deadlock_warned := false
var _hint_timer: Timer
var _win_timer: Timer
var _overlay_close: Callable = Callable()

var _moves_value: Label
var _pushes_value: Label
var _time_value: Label
var _best_value: Label
var _goals_label: Label
var _par_label: Label
var _chain_label: Label
var _hazard_label: Label
var _hazard_badge: Control
var _coins_value: Label
var _item_buttons: Dictionary = {}
var _item_badges: Dictionary = {}
var _ability_buttons: Dictionary = {}
var _ability_badges: Dictionary = {}
var _charges: Dictionary = {}
var _armed := ""
var _crane_from := Vector2i(-1, -1)
var _ad_popup: AdPopup = null
var _items_enabled := false
var _failed := false
var hazards: LevelHazards = null


func _build() -> void:
	level = Game.current_level()
	add_background("game")
	Audio.play_music("music_game")
	if level == null:
		_build_missing_level()
		return
	state = SokobanState.new()
	state.setup(level)
	state.moved.connect(_on_state_moved)
	state.undone.connect(_on_state_undone)
	state.redone.connect(_on_state_redone)
	state.restarted.connect(_on_state_restarted)
	state.solved.connect(_on_state_solved)
	state.tool_applied.connect(_on_tool_applied)
	_items_enabled = level.builtin and Game.current_mode() == "campaign"
	_reset_charges()
	hazards = LevelHazards.new()
	hazards.changed.connect(_on_hazards_changed)
	hazards.caught.connect(_on_caught)
	hazards.rubble_spawned.connect(_on_rubble_spawned)
	hazards.thug_crushed.connect(_on_thug_crushed)
	hazards.thief_killed.connect(_on_thief_killed)
	hazards.thief_respawned.connect(_on_thief_respawned)
	hazards.crate_stolen.connect(_on_crate_stolen)
	hazards.pry_interrupted.connect(_on_pry_interrupted)
	_configure_hazards()
	_hint_timer = Timer.new()
	_hint_timer.one_shot = true
	_hint_timer.wait_time = 3.2
	_hint_timer.timeout.connect(_on_hint_timeout)
	add_child(_hint_timer)
	_win_timer = Timer.new()
	_win_timer.one_shot = true
	_win_timer.wait_time = 0.45
	_win_timer.timeout.connect(_show_win)
	add_child(_win_timer)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_build_top_bar(root)

	board_holder = Control.new()
	board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_holder.clip_contents = true
	board_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(board_holder)

	shake_root = Control.new()
	shake_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shake_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_holder.add_child(shake_root)
	board = BoardView.new()
	shake_root.add_child(board)
	board.setup(level, state)
	board_holder.resized.connect(_fit_board)
	_build_hazard_badge(board_holder)

	_build_bottom_bar(root)
	_update_hud()
	_fit_board()
	_show_tip()
	set_process(true)


func _build_missing_level() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var v := UIKit.vbox(16)
	center.add_child(v)
	v.add_child(UIKit.heading("Missing level", 24, UIKit.COL_RED))
	var back := UIKit.button(t("common_back"), "", "PrimaryButton")
	back.pressed.connect(func(): Game.goto("menu"))
	v.add_child(back)


func _build_top_bar(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 14)
	root.add_child(bar)

	var pause_button := UIKit.icon_button("pause", t("common_pause"), 44)
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.pressed.connect(_open_pause)
	bar.add_child(pause_button)

	var title_box := UIKit.vbox(0)
	title_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(title_box)
	var chapter_text := ""
	if level.builtin:
		var chapter := Game.catalog.get_chapter(level.chapter_index)
		chapter_text = t("game_chapter_format", [level.chapter_index + 1,
				Loc.chapter_name(chapter)])
	else:
		chapter_text = t("game_custom_banner")
	title_box.add_child(UIKit.label(chapter_text, 12, UIKit.COL_TEAL, true))
	title_box.add_child(UIKit.label(level.display_name(), 24, UIKit.COL_TEXT, true))
	var mode := Game.current_mode()
	if mode != "campaign":
		var mode_text := t("game_playtest_banner") if mode == "playtest" else t("game_custom_banner")
		title_box.add_child(UIKit.label(mode_text, 11, UIKit.COL_GOLD))

	bar.add_child(UIKit.expand_spacer())
	_moves_value = _add_chip(bar, t("game_moves"), "0")
	_pushes_value = _add_chip(bar, t("game_pushes"), "0")
	_time_value = _add_chip(bar, t("game_time"), "00:00")
	_best_value = _add_chip(bar, t("game_best"), "—", 96)
	_coins_value = _add_chip(bar, t("game_coins"), str(SaveManager.wallet_coins()), 88)
	if not SaveManager.wallet_changed.is_connected(_on_wallet_changed):
		SaveManager.wallet_changed.connect(_on_wallet_changed)


func _add_chip(parent: HBoxContainer, title: String, initial: String, width := 84) -> Label:
	var p := UIKit.panel(10, "FlatPanel")
	p.custom_minimum_size = Vector2(width, 54)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	v.add_child(UIKit.label(title, 11, UIKit.COL_MUTED))
	var value := UIKit.label(initial, 20, UIKit.COL_TEXT, true)
	v.add_child(value)
	parent.add_child(p)
	return value


func _build_bottom_bar(root: VBoxContainer) -> void:
	var panel := UIKit.panel(12, "FlatPanel")
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(panel)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	panel.add_child(bar)

	var goal_icon := TextureRect.new()
	goal_icon.texture = UIKit.art("goal")
	goal_icon.custom_minimum_size = Vector2(28, 28)
	goal_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	goal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bar.add_child(goal_icon)
	_goals_label = UIKit.label("", 15, UIKit.COL_TEXT)
	bar.add_child(_goals_label)

	bar.add_child(UIKit.spacer(8, 0))
	var sep := ColorRect.new()
	sep.color = UIKit.COL_BORDER
	sep.custom_minimum_size = Vector2(1, 26)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(sep)
	bar.add_child(UIKit.spacer(8, 0))
	_par_label = UIKit.label("", 13, UIKit.COL_DIM)
	bar.add_child(_par_label)

	bar.add_child(UIKit.spacer(10, 0))
	_chain_label = UIKit.label("", 12, UIKit.COL_TEAL, true)
	bar.add_child(_chain_label)

	bar.add_child(UIKit.expand_spacer())

	for part_id in RobotUpgrades.ORDER:
		if RobotUpgrades.is_active(part_id):
			bar.add_child(_build_ability_button(part_id))
	var tool_sep := ColorRect.new()
	tool_sep.color = UIKit.COL_BORDER
	tool_sep.custom_minimum_size = Vector2(1, 32)
	tool_sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(tool_sep)
	for item_id in ItemCatalog.ORDER:
		bar.add_child(_build_item_button(item_id))

	_refresh_toolbar()

	var restart_button := UIKit.icon_button("restart", "%s  R" % t("common_restart"), 44)
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.pressed.connect(_request_restart)
	bar.add_child(restart_button)


func _build_ability_button(part_id: String) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(54, 0)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.custom_minimum_size = Vector2(52, 52)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.icon = UIKit.icon(RobotUpgrades.icon_name(part_id))
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_constant_override("icon_max_width", 32)
	b.pressed.connect(func(): _on_ability_pressed(part_id))
	wrap.add_child(b)
	var badge := _make_badge(b, UIKit.COL_TEAL)
	_ability_buttons[part_id] = b
	_ability_badges[part_id] = badge
	return wrap


func _make_badge(button: Button, color: Color) -> Label:
	var badge := UIKit.label("0", 12, color, true)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := UIKit.pill(badge)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT,
			Control.PRESET_MODE_MINSIZE, 1)
	button.add_child(pill)
	return badge


func _build_item_button(item_id: String) -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(58, 0)
	wrap.mouse_filter = Control.MOUSE_FILTER_PASS
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.custom_minimum_size = Vector2(56, 56)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.icon = UIKit.icon(ItemCatalog.icon_name(item_id))
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_constant_override("icon_max_width", 38)
	b.pressed.connect(func(): _on_item_pressed(item_id))
	wrap.add_child(b)
	var badge := _make_badge(b, UIKit.COL_GOLD)
	_item_buttons[item_id] = b
	_item_badges[item_id] = badge
	return wrap


func _build_hazard_badge(host: Control) -> void:
	_hazard_label = UIKit.label("", 13, UIKit.COL_RED, true)
	_hazard_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill := UIKit.pill(_hazard_label, Color("33151dE6"), Color("c9636a"))
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.z_index = 120
	host.add_child(pill)
	pill.set_anchors_preset(Control.PRESET_TOP_LEFT)
	pill.offset_left = 14
	pill.offset_top = 12
	pill.offset_right = 14
	pill.offset_bottom = 12
	pill.visible = false
	_hazard_badge = pill


func _after_build() -> void:
	await get_tree().process_frame
	_fit_board()


func _fit_board() -> void:
	if board != null and board_holder != null:
		board.fit_to(board_holder.size)


# --------------------------------------------------------------------------- #
# State responses
# --------------------------------------------------------------------------- #
func _on_state_moved(result: Dictionary) -> void:
	if board != null:
		board.animate_move(result)
	board.clear_hint()
	if bool(result["pushed"]):
		Audio.play_sfx("push", -6.0, 0.04)
		var to: Vector2i = result["box_to"]
		if level.goals.has(to):
			Audio.play_sfx("goal", -5.0, 0.0)
		elif level.goals.has(result["box_from"]):
			Audio.play_sfx("ungoal", -10.0, 0.0)
		_warn_deadlock()
	else:
		Audio.play_step()
	_update_hud()
	if hazards != null:
		hazards.notify_action()


func _on_state_undone(record: Dictionary) -> void:
	if board != null:
		if str(record.get("kind", "move")) == "move":
			board.animate_undo(record)
		else:
			board.rebuild()
		board.clear_hint()
	Audio.play_sfx("undo", -8.0, 0.03)
	# a rewound crate may have left the thief's hands
	if hazards != null:
		hazards.check_pry()
	_update_hud()


func _on_state_redone(record: Dictionary) -> void:
	if board != null:
		if str(record.get("kind", "move")) == "move":
			board.animate_redo(record)
		else:
			board.rebuild()
		board.clear_hint()
	Audio.play_sfx("push", -10.0, 0.04)
	_update_hud()


func _on_state_restarted() -> void:
	_won = false
	_deadlock_warned = false
	if board != null:
		board.rebuild()
		board.clear_hint()
	_update_hud()


func _on_state_solved() -> void:
	if _won:
		return
	_won = true
	if board != null:
		board.clear_hint()
		board.play_win_jump()
	if _win_timer != null:
		_win_timer.start()


func _warn_deadlock() -> void:
	if _deadlock_warned or state == null:
		return
	for pos in state.boxes.keys():
		if state.goals.has(pos):
			continue
		var up := state.walls.has(pos + UP)
		var down := state.walls.has(pos + DOWN)
		var left := state.walls.has(pos + LEFT)
		var right := state.walls.has(pos + RIGHT)
		if (up or down) and (left or right):
			_deadlock_warned = true
			toast(t("game_wrong"), 3.0)
			return


# --------------------------------------------------------------------------- #
# HUD
# --------------------------------------------------------------------------- #
func _update_hud() -> void:
	if state == null:
		return
	_moves_value.text = str(state.moves)
	_pushes_value.text = str(state.pushes)
	var left := state.goals_left()
	_goals_label.text = t("game_goals_left", [left]) if left > 0 else t("game_goals_done")
	_goals_label.add_theme_color_override("font_color",
			UIKit.COL_TEAL if left == 0 else UIKit.COL_TEXT)
	if level.par_pushes > 0:
		_par_label.text = t("game_par", [level.par_pushes])
		_par_label.visible = true
	else:
		_par_label.visible = false
	if _chain_label != null:
		var chain := RobotUpgrades.chain_for(SaveManager.upgrade_level("arm"))
		_chain_label.visible = chain > 1
		_chain_label.text = t("game_chain", [chain]) if chain > 1 else ""
	if _hazard_label != null:
		var show_hazard := hazards != null and hazards.has_any_hazard()
		if _hazard_badge != null:
			_hazard_badge.visible = show_hazard
		if show_hazard:
			_hazard_label.text = hazards.status_text()
	var record := SaveManager.get_level_record(level.id)
	if record.is_empty() or int(record.get("best_pushes", 0)) <= 0:
		_best_value.text = "—"
	else:
		_best_value.text = str(int(record.get("best_pushes", 0)))
		_refresh_toolbar()


func _process(delta: float) -> void:
	if state == null:
		return
	if not _won and not _failed and _overlay == null and not _confirm_open:
		_elapsed += delta
		if hazards != null:
			hazards.tick(delta)
	_hud_accum += delta
	if _hud_accum >= 0.1:
		_hud_accum = 0.0
		if _time_value != null:
			_time_value.text = UIKit.format_time(_elapsed)
		if _hazard_label != null and hazards != null and hazards.has_any_hazard():
			_hazard_label.text = hazards.status_text()

# --------------------------------------------------------------------------- #
# Input
# --------------------------------------------------------------------------- #
func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	if _confirm_open:
		return
	if _overlay != null:
		if event.is_action_pressed("pause") and _overlay_close.is_valid():
			_overlay_close.call()
			get_viewport().set_input_as_handled()
		return
	if _armed != "" and event.is_action_pressed("pause"):
		_disarm()
		toast(t("item_cancelled"), 1.2)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if Game.current_mode() == "playtest":
			Game.return_from_game()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("move_up"):
		_try_move(UP)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_try_move(DOWN)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left"):
		_try_move(LEFT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_right"):
		_try_move(RIGHT)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("restart"):
		_request_restart()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _overlay != null or _confirm_open or state == null:
		return
	# Point-and-click tools need the click position, and the board sits under HUD
	# containers, so they are handled here (only for cells inside the board).
	if _armed != "" and event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT and board != null:
		var cell := board.cell_at_global(event.position)
		if cell.x >= 0:
			if _armed == "item:crane":
				_on_board_click(cell)
			elif _armed == "ability:back":
				_try_warp(cell)
			else:
				return
			get_viewport().set_input_as_handled()
			return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_start = event.position
			_touch_active = true
		elif _touch_active:
			_touch_active = false
			var delta: Vector2 = event.position - _touch_start
			if delta.length() < 36.0:
				return
			if absf(delta.x) > absf(delta.y):
				_try_move(RIGHT if delta.x > 0 else LEFT)
			else:
				_try_move(DOWN if delta.y > 0 else UP)


func _try_move(dir: Vector2i) -> void:
	if _won or _failed or _overlay != null or _confirm_open:
		return
	if _armed != "":
		if _armed == "item:c4" and state.walls.has(state.player + dir):
			_use_c4(state.player + dir)
			return
		if _armed == "ability:head" and state.walls.has(state.player + dir):
			if state.phase_through(dir):
				_finish_ability("head", t("ability_used_phase"))
				return
		if _armed == "ability:legs" and state.boxes.has(state.player + dir):
			if state.jump_over(dir):
				_finish_ability("legs", t("ability_used_jump"))
				return
		if _armed == "ability:hook" and state.boxes.has(state.player + dir):
			if state.pass_through_crates(dir):
				_finish_ability("hook", t("ability_used_hook"))
				return
		if _armed == "item:rope":
			var pulled := state.pull(dir)
			if bool(pulled.get("moved", false)):
				_consume_and_disarm("rope")
				Audio.play_sfx("push", -6.0, 0.03)
				_update_hud()
				return
	var chain := RobotUpgrades.chain_for(SaveManager.upgrade_level("arm"))
	var result := state.try_move(dir, chain)
	if bool(result.get("moved", false)):
		return
	Audio.play_sfx("error", -14.0, 0.02)
	if board != null:
		board.blocked_feedback(result.get("box_from", Vector2i(-1, -1)), dir)
	if bool(SaveManager.get_setting("screen_shake", true)):
		_shake()
	_clear_hint()


# --------------------------------------------------------------------------- #
# Items and robot abilities
# --------------------------------------------------------------------------- #
func _reset_charges() -> void:
	_charges.clear()
	for part_id in RobotUpgrades.ORDER:
		if not RobotUpgrades.is_active(part_id):
			continue
		var level := SaveManager.upgrade_level(part_id)
		if level > 0:
			_charges[part_id] = RobotUpgrades.charges_for(part_id, level)


func _charges_left(part_id: String) -> int:
	return int(_charges.get(part_id, 0))


## Out of charges: buy one more with coins instead of being stuck.
func _buy_charge(part_id: String) -> bool:
	var price := RobotUpgrades.extra_charge_price(part_id)
	if price <= 0:
		return false
	if not SaveManager.spend_coins(price):
		Audio.play_sfx("error", -12.0)
		toast(t("ability_charge_need_coins", [price]), 2.4)
		return false
	_charges[part_id] = _charges_left(part_id) + 1
	Audio.play_sfx("goal", -8.0, 0.0)
	toast(t("ability_charge_bought", [price]), 1.8)
	_refresh_toolbar()
	return true


func _spend_charge(part_id: String) -> void:
	var left := _charges_left(part_id)
	if left > 0:
		_charges[part_id] = left - 1


func _on_wallet_changed() -> void:
	if _coins_value != null:
		_coins_value.text = str(SaveManager.wallet_coins())
	_refresh_toolbar()


func _refresh_toolbar() -> void:
	for item_id in _item_buttons.keys():
		var b: Button = _item_buttons[item_id]
		var owned := SaveManager.item_count(item_id)
		var badge: Label = _item_badges.get(item_id)
		if badge != null:
			badge.text = str(owned) if owned > 0 else str(ItemCatalog.price(item_id))
			badge.add_theme_color_override("font_color",
					UIKit.COL_GOLD if owned > 0 else UIKit.COL_DIM)
		var armed := _armed == "item:" + str(item_id)
		b.disabled = not _items_enabled
		b.tooltip_text = "%s  ·  %s" % [ItemCatalog.display_name(item_id),
				("%d" % owned) if owned > 0 else t("item_price", [ItemCatalog.price(item_id)])]
		_style_tool_button(b, armed, UIKit.COL_GOLD, owned > 0)
	for part_id in _ability_buttons.keys():
		var b: Button = _ability_buttons[part_id]
		var level := SaveManager.upgrade_level(str(part_id))
		var left := _charges_left(str(part_id))
		var price := RobotUpgrades.extra_charge_price(str(part_id))
		var badge: Label = _ability_badges.get(part_id)
		if badge != null:
			if level <= 0:
				badge.text = t("robot_locked_short")
				badge.add_theme_color_override("font_color", UIKit.COL_DIM)
			elif left < 0:
				badge.text = "∞"
				badge.add_theme_color_override("font_color", UIKit.COL_TEAL)
			elif left > 0:
				badge.text = str(left)
				badge.add_theme_color_override("font_color", UIKit.COL_TEAL)
			else:
				# depleted: show the refill price so buying a use is discoverable
				badge.text = "+%d" % price
				badge.add_theme_color_override("font_color",
						UIKit.COL_GOLD if SaveManager.wallet_coins() >= price else UIKit.COL_DIM)
		var usable := level > 0 and (left != 0)
		var armed := _armed == "ability:" + str(part_id)
		b.disabled = level <= 0
		var tip := "%s  ·  %s" % [RobotUpgrades.part_name(str(part_id)),
				RobotUpgrades.effect_text(str(part_id), level)]
		if left == 0 and level > 0:
			tip = "%s  ·  %s" % [tip, t("ability_charge_buy_tip", [price])]
		b.tooltip_text = tip
		_style_tool_button(b, armed, UIKit.COL_TEAL, usable or left == 0)


func _style_tool_button(b: Button, armed: bool, accent: Color, usable: bool) -> void:
	b.add_theme_color_override("icon_normal_color", accent if armed else UIKit.COL_MUTED)
	b.add_theme_color_override("icon_pressed_color", accent)
	b.add_theme_color_override("icon_hover_color", accent)
	b.modulate = Color(1, 1, 1, 1) if armed or usable else Color(1, 1, 1, 0.55)


func _on_item_pressed(item_id: String) -> void:
	if _won or _failed or _overlay != null or _confirm_open:
		return
	if not _items_enabled:
		toast(t("item_unavailable_here"), 2.2)
		return
	var key := "item:" + item_id
	if _armed == key and item_id != "rewind" and item_id != "guide" \
			and item_id != "contract":
		_disarm()
		return
	if SaveManager.item_count(item_id) <= 0:
		if not SaveManager.buy_item(item_id):
			Audio.play_sfx("error", -12.0)
			toast(t("item_need_coins", [ItemCatalog.price(item_id)]), 2.2)
			return
		toast(t("item_bought", [ItemCatalog.display_name(item_id)]), 1.6)
	match item_id:
		"rewind":
			_use_rewind()
		"guide":
			_use_guide()
		"contract":
			_use_contract()
		_:
			_arm(key, t("item_hint_" + item_id))


func _on_ability_pressed(part_id: String) -> void:
	if _won or _failed or _overlay != null or _confirm_open:
		return
	if not _items_enabled:
		toast(t("item_unavailable_here"), 2.2)
		return
	var level := SaveManager.upgrade_level(part_id)
	if level <= 0:
		toast(t("robot_locked_hint"), 2.4)
		return
	if _charges_left(part_id) == 0:
		if not RobotUpgrades.can_buy_charges(part_id, level):
			toast(t("robot_no_charges"), 2.2)
			return
		if not _buy_charge(part_id):
			return
	var key := "ability:" + part_id
	if _armed == key:
		_disarm()
		return
	_arm(key, t("ability_hint_" + part_id))


func _arm(key: String, hint: String) -> void:
	_armed = key
	_crane_from = Vector2i(-1, -1)
	if board != null:
		board.clear_highlight()
	_refresh_toolbar()
	Audio.play_sfx("click", -8.0)
	if not hint.is_empty():
		toast(hint, 3.0)


func _disarm() -> void:
	if _armed == "":
		return
	_armed = ""
	_crane_from = Vector2i(-1, -1)
	if board != null:
		board.clear_highlight()
	_refresh_toolbar()


func _consume_and_disarm(item_id: String) -> void:
	SaveManager.consume_item(item_id)
	_disarm()


func _finish_ability(part_id: String, message: String) -> void:
	_spend_charge(part_id)
	_disarm()
	Audio.play_sfx("hint", -8.0, 0.0)
	_update_hud()
	if not message.is_empty():
		toast(message, 1.6)


func _use_c4(target: Vector2i) -> void:
	if not SaveManager.consume_item("c4"):
		_disarm()
		return
	state.break_wall(target)
	if board != null:
		board.burst(board.cell_center(target), Color(1.0, 0.62, 0.32), 30)
		board.rebuild()
	Audio.play_sfx("boom", -3.0, 0.0)
	if bool(SaveManager.get_setting("screen_shake", true)):
		_shake()
	_disarm()
	_update_hud()
	toast(t("item_c4_used"), 1.6)


func _try_warp(cell: Vector2i) -> void:
	if not state.warp_player(cell):
		Audio.play_sfx("error", -12.0)
		toast(t("item_crane_blocked"), 2.0)
		return
	_finish_ability("back", t("ability_used_warp"))


func _on_board_click(cell: Vector2i) -> void:
	if cell.x < 0 or _won or _failed or _overlay != null or _confirm_open:
		return
	if _armed != "item:crane" or state == null:
		return
	if _crane_from.x < 0:
		if not state.boxes.has(cell):
			toast(t("item_crane_pick"), 2.0)
			return
		_crane_from = cell
		if board != null:
			board.set_highlight(cell)
		toast(t("item_crane_place"), 2.0)
		return
	if cell == _crane_from:
		_crane_from = Vector2i(-1, -1)
		if board != null:
			board.clear_highlight()
		return
	if not state.teleport_box(_crane_from, cell):
		Audio.play_sfx("error", -12.0)
		toast(t("item_crane_blocked"), 2.0)
		return
	SaveManager.consume_item("crane")
	if board != null:
		board.clear_highlight()
		board.rebuild()
	Audio.play_sfx("push", -4.0, 0.0)
	_crane_from = Vector2i(-1, -1)
	_disarm()
	_update_hud()
	toast(t("item_crane_used"), 1.6)


func _use_rewind() -> void:
	if not state.can_undo():
		Audio.play_sfx("error", -12.0)
		toast(t("toast_undo_none"), 1.6)
		return
	SaveManager.consume_item("rewind")
	state.undo()
	Audio.play_sfx("undo", -6.0, 0.03)
	_refresh_toolbar()


func _use_guide() -> void:
	var shown: bool = await _show_hint()
	if shown:
		SaveManager.consume_item("guide")
	_refresh_toolbar()


func _use_contract() -> void:
	SaveManager.consume_item("contract")
	_refresh_toolbar()
	if board != null:
		board.clear_hint()
	state.force_win()
	toast(t("item_contract_used"), 2.0)


func _on_tool_applied(record: Dictionary) -> void:
	var kind := str(record.get("kind", ""))
	if board != null:
		match kind:
			"pull":
				board.animate_pull(record)
			"jump", "pass", "phase", "warp":
				board.animate_ability(record)
			_:
				board.rebuild()
	if hazards != null:
		hazards.notify_action()
		_on_hazards_changed()


func _on_hazards_changed() -> void:
	if board == null or hazards == null:
		return
	board.set_enemies(hazards.thug, hazards.thief, hazards.thief_grab > 0)
	board.queue_redraw()


## Campaign levels derive hazards from the chapter; workshop levels carry the
## toggles their author set in the editor.
func _configure_hazards() -> void:
	if hazards == null or state == null or level == null:
		return
	hazards.configure(state, level.chapter_index if level.builtin else -1,
			level.builtin, 0, level.hazards)
	_on_hazards_changed()


func _on_rubble_spawned(count: int) -> void:
	Audio.play_sfx("boom", -9.0, 0.0)
	var msg := t("hazard_rubble_spawned", [count])
	toast(msg, 1.8)
	if bool(SaveManager.get_setting("screen_shake", true)):
		_shake()


func _on_thug_crushed(cell: Vector2i) -> void:
	_on_hazards_changed()
	if board != null:
		board.burst(board.cell_center(cell), Color(0.95, 0.4, 0.35), 24)
	Audio.play_sfx("boom", -4.0, 0.0)
	toast(t("hazard_thug_crushed"), 2.0)
	if bool(SaveManager.get_setting("screen_shake", true)):
		_shake()


func _on_thief_killed(cell: Vector2i) -> void:
	_on_hazards_changed()
	if board != null:
		board.burst(board.cell_center(cell), Color(0.55, 0.9, 1.0), 26)
	Audio.play_sfx("boom", -6.0, 0.0)
	toast(t("hazard_thief_killed"), 2.4)
	if bool(SaveManager.get_setting("screen_shake", true)):
		_shake()


func _on_thief_respawned(cell: Vector2i) -> void:
	_on_hazards_changed()
	if board != null:
		board.burst(board.cell_center(cell), Color(0.85, 0.45, 0.95), 20)
	Audio.play_sfx("locked", -8.0, 0.0)
	toast(t("hazard_thief_respawned"), 2.0)


func _on_crate_stolen(cell: Vector2i) -> void:
	if board != null:
		board.burst(board.cell_center(cell), Color(0.95, 0.35, 0.4), 30)
		board.rebuild()
	_on_hazards_changed()
	Audio.play_sfx("error", -5.0, 0.0)
	toast(t("hazard_crate_stolen"), 2.4)


func _on_pry_interrupted(cell: Vector2i) -> void:
	_on_hazards_changed()
	if board != null:
		board.burst(board.cell_center(cell), Color(0.45, 0.95, 0.85), 18)
	Audio.play_sfx("undo", -8.0, 0.0)
	toast(t("hazard_pry_interrupted"), 2.2)


func _on_caught(reason: String) -> void:
	if _failed:
		return
	if board != null:
		board.rebuild()
	_on_hazards_changed()
	Audio.play_sfx("error", -3.0, 0.0)
	_show_defeat(reason)


func _request_restart() -> void:
	if _won or _failed or _overlay != null or _confirm_open:
		return
	if state.moves <= 0:
		_restart()
		return
	_open_ad(func(): _restart())


func _open_ad(on_done: Callable) -> void:
	if _ad_popup != null or _overlay != null:
		return
	_ad_popup = AdPopup.open(self, func():
		_ad_popup = null
		_overlay = null
		_overlay_close = Callable()
		on_done.call()
	)
	_overlay = _ad_popup
	_overlay_close = Callable()


func _restart() -> void:
	_close_overlay()
	_won = false
	_failed = false
	_elapsed = 0.0
	_deadlock_warned = false
	_disarm()
	_reset_charges()
	if state != null:
		state.reset()
	_configure_hazards()
	_update_hud()


func _shake() -> void:
	if shake_root == null:
		return
	var base := Vector2.ZERO
	var tw := create_tween()
	tw.tween_property(shake_root, "position", base + Vector2(6, 2), 0.03)
	tw.tween_property(shake_root, "position", base + Vector2(-5, -2), 0.04)
	tw.tween_property(shake_root, "position", base + Vector2(3, 1), 0.03)
	tw.tween_property(shake_root, "position", base, 0.05)


# --------------------------------------------------------------------------- #
# Hint
# --------------------------------------------------------------------------- #
func _show_hint() -> bool:
	if _won or _failed or _overlay != null or _confirm_open or state == null:
		return false
	toast(t("game_hint_loading"), 0.9)
	await get_tree().process_frame
	var solver := SokobanSolver.new()
	if not solver.setup_from_state(state):
		Audio.play_sfx("error", -10.0)
		toast(t("game_hint_fail"), 2.2)
		return false
	var result := solver.solve(2.0, 80000, 2)
	if not bool(result.get("solvable", false)):
		Audio.play_sfx("error", -10.0)
		toast(t("game_hint_fail"), 2.2)
		return false
	var path: Array = result.get("path", [])
	if path.is_empty():
		toast(t("game_hint_fail"), 2.0)
		return false
	var dir_index := int(path[0]["dir"])
	var dir: Vector2i = SokobanSolver.DIRS[dir_index]
	var box_pos := Vector2i(-1, -1)
	var raw_box := int(path[0].get("box", -1))
	if raw_box >= 0 and solver.width > 0:
		var candidate := Vector2i(raw_box % solver.width, raw_box / solver.width)
		if state.boxes.has(candidate):
			box_pos = candidate
	if box_pos.x < 0:
		box_pos = _find_hint_box(dir)
	if box_pos.x < 0:
		toast(t("game_hint_fail"), 2.0)
		return false
	board.set_hint(dir, box_pos)
	Audio.play_sfx("hint", -6.0, 0.0)
	toast(t("game_hint_ready"), 2.4)
	_hint_token += 1
	if _hint_timer != null:
		_hint_timer.start()
	return true


func _on_hint_timeout() -> void:
	if board != null:
		board.clear_hint()


func _find_hint_box(dir: Vector2i) -> Vector2i:
	var reachable := _reachable_cells(state.player)
	var fallback := Vector2i(-1, -1)
	for pos in state.boxes.keys():
		var stand: Vector2i = pos - dir
		var target: Vector2i = pos + dir
		if state.walls.has(stand) or state.walls.has(target):
			continue
		if state.boxes.has(target):
			continue
		if reachable.has(stand):
			return pos
		if fallback.x < 0:
			fallback = pos
	return fallback


func _reachable_cells(from: Vector2i) -> Dictionary:
	var seen := {from: true}
	var queue: Array = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in [UP, DOWN, LEFT, RIGHT]:
			var n: Vector2i = c + d
			if state.walls.has(n) or state.boxes.has(n) or seen.has(n):
				continue
			seen[n] = true
			queue.append(n)
	return seen


func _clear_hint() -> void:
	_hint_token += 1
	if board != null:
		board.clear_hint()


# --------------------------------------------------------------------------- #
# Controls / menus
# --------------------------------------------------------------------------- #
func _open_pause() -> void:
	if _overlay != null:
		return
	_clear_hint()
	_disarm()
	_pause_overlay = Control.new()
	_pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_pause_overlay.z_index = OVERLAY_Z
	add_child(_pause_overlay)
	_overlay = _pause_overlay
	_overlay_close = _close_overlay
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.add_child(center)
	var card := UIKit.panel(28, "CardPanel")
	card.custom_minimum_size = Vector2(420, 0)
	center.add_child(card)
	var v := UIKit.vbox(12)
	card.add_child(v)
	v.add_child(UIKit.heading(t("game_pause_title"), 28, UIKit.COL_TEXT))
	v.add_child(UIKit.label(level.display_name(), 15, UIKit.COL_MUTED))
	v.add_child(UIKit.divider())
	_stat_line(v, t("game_moves"), str(state.moves))
	_stat_line(v, t("game_pushes"), str(state.pushes))
	_stat_line(v, t("game_time"), UIKit.format_time(_elapsed))
	v.add_child(UIKit.spacer(0, 4))

	var playtest := Game.current_mode() == "playtest"
	var resume := UIKit.button(t("common_resume"), "play", "PrimaryButton", 48)
	resume.pressed.connect(_close_overlay)
	v.add_child(resume)
	if playtest:
		var back_editor := UIKit.button(t("result_back_editor"), "pencil", "GhostButton", 46)
		back_editor.pressed.connect(func(): Game.return_from_game())
		v.add_child(back_editor)
	var restart := UIKit.button(t("common_restart"), "restart", "GhostButton", 46)
	restart.pressed.connect(func():
		_close_overlay()
		_request_restart()
	)
	v.add_child(restart)
	var settings := UIKit.button(t("common_settings"), "settings", "GhostButton", 46)
	settings.pressed.connect(_open_settings_from_pause)
	v.add_child(settings)
	if not playtest:
		var select := UIKit.button(t("common_level_select"), "grid", "GhostButton", 46)
		select.pressed.connect(func():
			Audio.play_sfx("click")
			if level.builtin:
				Game.goto("level_select", {"chapter": level.chapter_index})
			else:
				Game.goto("level_select", {"chapter": "custom"})
		)
		v.add_child(select)
	var menu := UIKit.button(t("common_menu"), "home", "GhostButton", 46)
	menu.pressed.connect(func(): Game.goto("menu"))
	v.add_child(menu)
	resume.grab_focus()


func _stat_line(parent: VBoxContainer, key: String, value: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(UIKit.label(key, 14, UIKit.COL_MUTED))
	row.add_child(UIKit.expand_spacer())
	row.add_child(UIKit.label(value, 16, UIKit.COL_TEXT, true))


func _open_settings_from_pause() -> void:
	if _pause_overlay == null:
		return
	_pause_overlay.visible = false
	_open_settings_modal(func():
		if is_instance_valid(_pause_overlay):
			_pause_overlay.visible = true
			_overlay = _pause_overlay
	)


func _open_settings_modal(on_close: Callable) -> void:
	var modal := Control.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	modal.z_index = OVERLAY_Z
	add_child(modal)
	_overlay = modal
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.8)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var card := UIKit.panel(0, "CardPanel")
	card.custom_minimum_size = Vector2(700, 600)
	center.add_child(card)
	var v := UIKit.vbox(0)
	card.add_child(v)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.custom_minimum_size = Vector2(0, 56)
	v.add_child(header)
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", 20)
	header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_margin)
	header_margin.add_child(UIKit.heading(t("settings_title"), 22, UIKit.COL_TEXT))
	var close_modal := func():
		if is_instance_valid(modal):
			modal.queue_free()
		if is_instance_valid(_pause_overlay):
			_overlay = _pause_overlay
			_overlay_close = _close_overlay
		on_close.call()
	_overlay_close = close_modal
	var close := UIKit.icon_button("close", t("common_close"), 38)
	close.pressed.connect(close_modal)
	var close_wrap := MarginContainer.new()
	close_wrap.add_theme_constant_override("margin_right", 14)
	close_wrap.add_theme_constant_override("margin_top", 9)
	close_wrap.add_child(close)
	header.add_child(close_wrap)
	v.add_child(UIKit.divider())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 508)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var settings := SettingsPanel.new()
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.notify.connect(func(text: String): toast(text))
	scroll.add_child(settings)
	close.grab_focus()


func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
	_overlay = null
	_pause_overlay = null
	_overlay_close = Callable()


# --------------------------------------------------------------------------- #
# Win
# --------------------------------------------------------------------------- #
func _show_win() -> void:
	if _overlay != null or not is_inside_tree():
		return
	var stars := 3 if state.cheated else level.star_rating(state.pushes)
	var mode := Game.current_mode()
	var saved: Dictionary = {}
	var award := level.builtin and mode == "campaign"
	if mode != "playtest":
		saved = SaveManager.record_result(level.id, state.moves, state.pushes, stars, _elapsed,
				award)
	Audio.play_sfx("win", -3.0, 0.0)
	_update_hud()
	_dismiss_tip()

	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.z_index = OVERLAY_Z
	add_child(_overlay)
	_overlay_close = _leave_after_result
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.045, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	_spawn_confetti()

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var card := UIKit.panel(30, "CardPanel")
	card.custom_minimum_size = Vector2(640, 0)
	center.add_child(card)
	var v := UIKit.vbox(14)
	card.add_child(v)

	var title := UIKit.heading(t("result_title"), 32, UIKit.COL_TEAL)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var name_label := UIKit.label(level.display_name(), 17, UIKit.COL_MUTED)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(name_label)

	var badges := HBoxContainer.new()
	badges.alignment = BoxContainer.ALIGNMENT_CENTER
	badges.add_theme_constant_override("separation", 10)
	v.add_child(badges)
	if bool(saved.get("first_clear", false)):
		badges.add_child(_badge(t("result_first_clear"), UIKit.COL_TEAL))
	if bool(saved.get("new_best", false)) and not bool(saved.get("first_clear", false)):
		badges.add_child(_badge(t("result_new_record"), UIKit.COL_GOLD))
	var last_of_chapter := false
	if level.builtin and level.chapter_index >= 0:
		var chapter := Game.catalog.get_chapter(level.chapter_index)
		var chapter_levels: Array = chapter.get("levels", [])
		last_of_chapter = level.index == chapter_levels.size() - 1
	if last_of_chapter:
		badges.add_child(_badge(t("result_campaign_done"), UIKit.COL_GOLD))
	if state.cheated:
		badges.add_child(_badge(t("result_contract_badge"), UIKit.COL_TEAL))

	var star_row := HBoxContainer.new()
	star_row.alignment = BoxContainer.ALIGNMENT_CENTER
	star_row.add_theme_constant_override("separation", 12)
	v.add_child(star_row)
	for i in 3:
		var star := TextureRect.new()
		star.texture = UIKit.icon("star")
		star.custom_minimum_size = Vector2(66, 66)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.pivot_offset = Vector2(33, 33)
		star.modulate = UIKit.COL_GOLD if i < stars else Color(0.33, 0.4, 0.5, 0.55)
		star.scale = Vector2(0.2, 0.2)
		star_row.add_child(star)
		var tw := star.create_tween()
		tw.tween_interval(0.18 + i * 0.16)
		if i < stars:
			tw.tween_callback(func(): Audio.play_sfx("goal", -6.0, 0.0))
			tw.tween_property(star, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK) \
					.set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(star, "scale", Vector2(0.62, 0.62), 0.24)

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 24)
	v.add_child(stats)
	_win_stat(stats, t("result_moves"), str(state.moves))
	_win_stat(stats, t("result_pushes"), str(state.pushes))
	_win_stat(stats, t("result_time"), UIKit.format_time(_elapsed))
	_win_stat(stats, t("result_best"),
			str(int((SaveManager.get_level_record(level.id) as Dictionary).get("best_moves", state.moves))))

	var coin_earned := int(saved.get("coins_earned", 0))
	if coin_earned > 0:
		var coin_row := HBoxContainer.new()
		coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
		coin_row.add_theme_constant_override("separation", 8)
		v.add_child(coin_row)
		var coin_icon := TextureRect.new()
		coin_icon.texture = UIKit.icon("coin")
		coin_icon.custom_minimum_size = Vector2(24, 24)
		coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin_icon.modulate = UIKit.COL_GOLD
		coin_row.add_child(coin_icon)
		coin_row.add_child(UIKit.label(t("result_coins", [coin_earned]), 17, UIKit.COL_GOLD, true))

	var hint_text := ""
	if level.par_pushes > 0:
		hint_text = t("result_par", [level.par_pushes])
		if stars < 3:
			hint_text += "  ·  " + t("result_star_hint_3")
	var hint := UIKit.label(hint_text, 13, UIKit.COL_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)
	v.add_child(UIKit.divider())

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	v.add_child(buttons)
	var mode_name := Game.current_mode()
	var next := Game.next_after(level)
	var primary_text := ""
	var primary_icon := "play"
	var primary_action := Callable()
	if mode_name == "playtest":
		primary_text = t("result_back_editor")
		primary_icon = "pencil"
		primary_action = func(): Game.return_from_game()
	elif mode_name == "custom":
		primary_text = t("result_replay")
		primary_icon = "restart"
		primary_action = func(): _restart()
	elif next != null:
		primary_text = t("result_next")
		primary_action = func(): Game.go_next_level(level)
	else:
		primary_text = t("result_levels")
		primary_icon = "grid"
		primary_action = func(): Game.goto("level_select",
				{"chapter": level.chapter_index if level.builtin else "custom"})
	var primary := UIKit.button(primary_text, primary_icon, "PrimaryButton", 50)
	primary.pressed.connect(primary_action)
	buttons.add_child(primary)

	if mode_name != "playtest" and mode_name != "custom":
		var replay := UIKit.button(t("result_replay"), "restart", "GhostButton", 50)
		replay.pressed.connect(func(): _restart())
		buttons.add_child(replay)
	var back := UIKit.button(t("result_levels") if mode_name == "campaign" else t("common_menu"),
			"grid" if mode_name == "campaign" else "home", "GhostButton", 50)
	back.pressed.connect(func():
		if mode_name == "campaign":
			Game.goto("level_select", {"chapter": level.chapter_index})
		elif mode_name == "custom":
			Game.goto("level_select", {"chapter": "custom"})
		else:
			Game.return_from_game()
	)
	buttons.add_child(back)
	primary.grab_focus()

	var all_done := level.builtin
	if all_done:
		for chapter in Game.catalog.chapters:
			for lv in chapter["levels"]:
				if lv.id != level.id and not SaveManager.is_completed(lv.id):
					all_done = false
					break
			if not all_done:
				break
	if all_done:
		var done_label := UIKit.label(t("result_all_done"), 14, UIKit.COL_GOLD)
		done_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(done_label)

	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(0.94, 0.94)
	var tw := card.create_tween()
	tw.tween_property(card, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_QUAD) \
			.set_ease(Tween.EASE_OUT)


func _show_defeat(reason: String) -> void:
	if _overlay != null or not is_inside_tree():
		return
	_failed = true
	_disarm()
	_dismiss_tip()
	_overlay = Control.new()
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.z_index = OVERLAY_Z
	add_child(_overlay)
	_overlay_close = Callable()
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.02, 0.03, 0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)
	var card := UIKit.panel(30, "CardPanel")
	card.custom_minimum_size = Vector2(560, 0)
	center.add_child(card)
	var v := UIKit.vbox(14)
	card.add_child(v)

	var title := UIKit.heading(t("defeat_title"), 30, UIKit.COL_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var reason_key := "defeat_" + reason
	var reason_label := UIKit.label(t(reason_key), 16, UIKit.COL_TEXT)
	reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(reason_label)
	var hint := UIKit.label(t("defeat_hint"), 13, UIKit.COL_MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 24)
	v.add_child(stats)
	_win_stat(stats, t("result_moves"), str(state.moves))
	_win_stat(stats, t("result_pushes"), str(state.pushes))
	_win_stat(stats, t("result_time"), UIKit.format_time(_elapsed))
	v.add_child(UIKit.divider())

	var buttons := UIKit.hbox(10)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(buttons)
	var retry := UIKit.button(t("defeat_retry"), "restart", "PrimaryButton", 50)
	retry.pressed.connect(func(): _restart())
	buttons.add_child(retry)
	var mode_name := Game.current_mode()
	var back := UIKit.button(t("result_levels") if mode_name == "campaign" else t("common_menu"),
			"grid" if mode_name == "campaign" else "home", "GhostButton", 50)
	back.pressed.connect(func():
		if mode_name == "campaign":
			Game.goto("level_select", {"chapter": level.chapter_index})
		elif mode_name == "custom":
			Game.goto("level_select", {"chapter": "custom"})
		else:
			Game.return_from_game()
	)
	buttons.add_child(back)
	retry.grab_focus()


func _leave_after_result() -> void:
	if Game.current_mode() == "playtest":
		Game.return_from_game()
	elif level != null and level.builtin:
		Game.goto("level_select", {"chapter": level.chapter_index})
	else:
		Game.goto("level_select", {"chapter": "custom"})


func _badge(text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.12)
	style.border_color = Color(color.r, color.g, color.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(20)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	p.add_theme_stylebox_override("panel", style)
	p.add_child(UIKit.label(text, 12, color, true))
	return p


func _win_stat(parent: HBoxContainer, title: String, value: String) -> void:
	var v := UIKit.vbox(0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.custom_minimum_size = Vector2(96, 0)
	parent.add_child(v)
	var t1 := UIKit.label(title, 11, UIKit.COL_MUTED)
	t1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t1)
	var t2 := UIKit.label(value, 24, UIKit.COL_TEXT, true)
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t2)


func _spawn_confetti() -> void:
	for i in 2:
		var p := CPUParticles2D.new()
		p.texture = UIKit.art("spark")
		p.amount = 70
		p.lifetime = 2.8
		p.one_shot = true
		p.explosiveness = 1.0
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 30.0
		p.position = size * 0.5
		p.direction = Vector2.UP
		p.spread = 180.0
		p.gravity = Vector2(0, 260)
		p.initial_velocity_min = 220.0
		p.initial_velocity_max = 520.0
		p.scale_amount_min = 0.3
		p.scale_amount_max = 0.9
		p.angular_velocity_min = -220.0
		p.angular_velocity_max = 220.0
		p.color = UIKit.COL_GOLD if i == 0 else UIKit.COL_TEAL
		p.z_index = 0
		_overlay.add_child(p)
		p.emitting = true


# --------------------------------------------------------------------------- #
# Tip banner
# --------------------------------------------------------------------------- #
func _show_tip() -> void:
	if not bool(SaveManager.get_setting("show_tips", true)):
		return
	if Game.current_mode() == "playtest":
		return
	var tip := level.tip_text()
	if tip.is_empty():
		return
	_tip_panel = UIKit.panel(14, "ToastPanel")
	_tip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_tip_panel.z_index = OVERLAY_Z
	add_child(_tip_panel)
	_tip_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tip_panel.offset_left = -330
	_tip_panel.offset_right = 330
	_tip_panel.offset_top = 84
	_tip_panel.offset_bottom = 164
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_tip_panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = UIKit.icon("bulb")
	icon.custom_minimum_size = Vector2(24, 24)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = UIKit.COL_GOLD
	row.add_child(icon)
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(v)
	v.add_child(UIKit.label(t("game_learn_tip"), 11, UIKit.COL_GOLD, true))
	var text := UIKit.label(tip, 14, UIKit.COL_TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.max_lines_visible = 2
	v.add_child(text)
	var close := UIKit.icon_button("close", t("game_tip_show"), 28)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_dismiss_tip)
	row.add_child(close)
	_tip_panel.modulate.a = 0.0
	var tw := _tip_panel.create_tween()
	tw.tween_property(_tip_panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(9.0)
	tw.tween_property(_tip_panel, "modulate:a", 0.0, 0.35)
	tw.tween_callback(_dismiss_tip)


func _dismiss_tip() -> void:
	if _tip_panel != null and is_instance_valid(_tip_panel):
		_tip_panel.queue_free()
	_tip_panel = null

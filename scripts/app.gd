extends Control
## Root shell: owns the screen container, global fade transition and theme.

## Dev-only screenshot output, kept outside res:// so captures never ship with exports.
const SHOT_DIR := "user://dev_shots"

var screen_host: Control
var current_screen: Control
var fade_rect: ColorRect
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.build_theme()
	_build_shell()
	Game.attach(self)
	DisplayServer.window_set_min_size(Vector2i(960, 540))
	Game.screen_id = "menu"
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest"):
		call_deferred("_run_self_test")
		return
	if args.has("--capture"):
		call_deferred("_run_capture")
		return
	if args.has("--flowtest"):
		call_deferred("_run_flow_test")
		return
	if args.has("--savetest"):
		call_deferred("_run_save_test")
		return
	if args.has("--dumpui"):
		call_deferred("_run_dump_ui")
		return
	call_deferred("_boot")


func _run_self_test() -> void:
	var test_script: Script = load("res://tests/self_test.gd")
	var tester: RefCounted = test_script.new()
	var code: int = tester.run()
	get_tree().quit(code)


func _run_capture() -> void:
	SaveManager.capture_mode = true
	SaveManager.add_coins(180, true)
	SaveManager.add_item("c4", 1)
	SaveManager.add_item("rewind", 2)
	SaveManager.upgrades = {"arm": 2, "hook": 1, "head": 3}
	DirAccess.make_dir_recursive_absolute(SHOT_DIR)
	_swap_screen("menu", {})
	await get_tree().process_frame
	await _fade_to(0.0, 0.4)
	await get_tree().create_timer(1.2).timeout
	_check_layout("menu")
	await _shot("01_menu")
	Game.goto("level_select", {"chapter": 1})
	await get_tree().create_timer(1.2).timeout
	_check_layout("level_select")
	await _shot("02_level_select")
	Game.start_campaign("c2_05")
	await get_tree().create_timer(1.2).timeout
	_check_layout("game")
	if current_screen != null and current_screen.get("board") != null:
		print("board holder=", current_screen.get("board_holder").size,
				" scale=", current_screen.get("board").scale, " level=",
				current_screen.get("level").id)
	await _shot("03_game")
	if current_screen != null and current_screen.get("state") != null:
		current_screen.get("state").try_move(Vector2i.RIGHT)
		await get_tree().create_timer(0.4).timeout
		current_screen.call("_request_restart")
		await get_tree().create_timer(0.6).timeout
		await _shot("04_ad_restart")
		var ad: Variant = current_screen.get("_ad_popup")
		if ad is AdPopup:
			(ad as AdPopup).finish_now()
		await get_tree().create_timer(0.6).timeout
	if current_screen != null and current_screen.has_method("_open_pause"):
		current_screen.call("_open_pause")
		await get_tree().create_timer(0.5).timeout
		await _shot("05_pause")
		current_screen.call("_close_overlay")
	Game.start_campaign("c1_01")
	await get_tree().create_timer(0.9).timeout
	if current_screen != null and current_screen.get("state") != null:
		current_screen.get("state").try_move(Vector2i.RIGHT)
	await get_tree().create_timer(1.4).timeout
	await _shot("06_win")
	Game.start_editor()
	await get_tree().create_timer(1.2).timeout
	if current_screen != null and current_screen.has_method("_on_hazard_toggled"):
		# show the workshop hazard toggles in action for the docs screenshot
		for hazard_id in ["collapse", "thug"]:
			current_screen.call("_on_hazard_toggled", str(hazard_id), true)
		if current_screen.get("_hazard_checks") != null:
			for hazard_id in ["collapse", "thug"]:
				var check: CheckBox = (current_screen.get("_hazard_checks") as Dictionary).get(hazard_id)
				if check != null:
					check.set_pressed_no_signal(true)
		await get_tree().create_timer(0.4).timeout
	_check_layout("editor")
	await _shot("07_editor")
	# workshop level list with the hazard tags it just authored
	if current_screen != null and current_screen.has_method("_save"):
		current_screen.call("_save")
		await get_tree().create_timer(0.4).timeout
		Game.goto("level_select", {"chapter": "custom"})
		await get_tree().create_timer(1.0).timeout
		_check_layout("level_select_custom")
		await _shot("14_custom_levels")
	Game.goto("settings", {"return_to": "menu"})
	await get_tree().create_timer(1.0).timeout
	_check_layout("settings")
	await _shot("08_settings")
	Game.goto("shop")
	await get_tree().create_timer(1.0).timeout
	_check_layout("shop")
	await _shot("09_shop")
	if current_screen != null and current_screen.has_method("_watch_ad"):
		current_screen.call("_watch_ad")
		await get_tree().create_timer(0.8).timeout
		await _shot("10_ad_shop")
	Game.goto("robot")
	await get_tree().create_timer(1.0).timeout
	_check_layout("robot")
	await _shot("11_robot")
	# chapter 4 hazards + defeat screen
	Game.start_campaign("c4_05")
	await get_tree().create_timer(1.0).timeout
	var hazard_screen := current_screen
	if hazard_screen != null and hazard_screen.get("hazards") != null:
		var hz: LevelHazards = hazard_screen.get("hazards")
		var st: SokobanState = hazard_screen.get("state")
		var cells: Array = st.floor_cells()
		cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			return a.distance_squared_to(st.player) < b.distance_squared_to(st.player))
		hz.spawn_rubble()
		hz.spawn_rubble()
		if cells.size() > 3:
			hz.thug = cells[2]
		if cells.size() > 6:
			hz.thief = cells[5]
		hazard_screen.call("_on_hazards_changed")
		await get_tree().create_timer(0.7).timeout
		_check_layout("hazards")
		await _shot("12_hazards")
		if cells.size() > 1:
			hz.thug = cells[1]
			hz.notify_action()
			hz.notify_action()
			await get_tree().create_timer(0.7).timeout
			await _shot("13_defeat")
	get_tree().quit()


func _check_layout(screen_name: String) -> void:
	if current_screen == null:
		return
	var view := get_viewport_rect()
	var count := 0
	for c in current_screen.find_children("*", "Control", true, false):
		if not (c is Control) or not c.is_visible_in_tree():
			continue
		var control := c as Control
		if control.size.x <= 0 or control.size.y <= 0:
			continue
		var parent := control.get_parent()
		var in_scroll := false
		while parent != null and parent != current_screen:
			if parent is ScrollContainer:
				in_scroll = true
				break
			parent = parent.get_parent()
		if in_scroll:
			continue
		var r := control.get_global_rect()
		if r.position.x < -2.0 or r.position.y < -2.0 \
				or r.end.x > view.size.x + 2.0 or r.end.y > view.size.y + 2.0:
			count += 1
			if count <= 8:
				print("LAYOUT ", screen_name, " ", control.get_path(), " ", r)
	if count > 0:
		print("LAYOUT warnings for ", screen_name, ": ", count)


func _run_dump_ui() -> void:
	_swap_screen("menu", {})
	await get_tree().process_frame
	await get_tree().process_frame
	_dump_text("menu")
	Game.goto("level_select", {"chapter": 1})
	await get_tree().create_timer(0.8).timeout
	_dump_text("levels")
	Game.start_campaign("c2_05")
	await get_tree().create_timer(0.8).timeout
	_dump_text("game")
	Game.start_editor()
	await get_tree().create_timer(0.8).timeout
	_dump_text("editor")
	Game.goto("settings", {"return_to": "menu"})
	await get_tree().create_timer(0.7).timeout
	_dump_text("settings")
	get_tree().quit()


func _dump_text(screen_name: String) -> void:
	if current_screen == null:
		return
	print("---- UI ", screen_name, " ----")
	for c in current_screen.find_children("*", "Control", true, false):
		if not c.is_visible_in_tree():
			continue
		var text := ""
		if c is Label:
			text = (c as Label).text
		elif c is Button:
			text = (c as Button).text
		if text.strip_edges().is_empty():
			continue
		var r := (c as Control).get_global_rect()
		print("  [%4d,%4d %4dx%-4d] %s" % [int(r.position.x), int(r.position.y),
				int(r.size.x), int(r.size.y), text.replace("
", " / ")])


func _run_save_test() -> void:
	var save_path := "user://save.json"
	var backup_path := "user://save.backup.json"
	var had_save := FileAccess.file_exists(save_path)
	var had_backup := FileAccess.file_exists(backup_path)
	var save_bytes := FileAccess.get_file_as_bytes(save_path) if had_save else PackedByteArray()
	var backup_bytes := FileAccess.get_file_as_bytes(backup_path) if had_backup else PackedByteArray()
	SaveManager.capture_mode = false
	SaveManager.reset_progress()
	SaveManager.coins = 0
	SaveManager.inventory = {}
	SaveManager.add_coins(90, true)
	SaveManager.add_item("c4", 2)
	SaveManager.upgrades = {"arm": 2, "core": 1}
	SaveManager.record_result("c1_01", 12, 5, 3, 21.5)
	SaveManager.save_game()
	var failures := 0
	if not FileAccess.file_exists(save_path):
		print("FAIL save file missing")
		failures += 1
	var text := FileAccess.get_file_as_string(save_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not ((parsed as Dictionary).get("progress", {}) as Dictionary).has("c1_01"):
		print("FAIL save content")
		failures += 1
	var rec := SaveManager.get_level_record("c1_01")
	if int(rec.get("best_pushes", 0)) != 5 or int(rec.get("stars", 0)) != 3:
		print("FAIL record fields: ", rec)
		failures += 1
	SaveManager.progress = {}
	SaveManager.coins = 0
	SaveManager.inventory = {}
	SaveManager.upgrades = {}
	SaveManager.load_game()
	if not SaveManager.is_completed("c1_01"):
		print("FAIL reload progress")
		failures += 1
	if SaveManager.wallet_coins() != 90:
		print("FAIL reload coins: ", SaveManager.wallet_coins())
		failures += 1
	if SaveManager.item_count("c4") != 2:
		print("FAIL reload items: ", SaveManager.inventory)
		failures += 1
	if SaveManager.upgrade_level("arm") != 2:
		print("FAIL reload upgrades: ", SaveManager.upgrades)
		failures += 1
	if SaveManager.total_upgrade_levels() != 3:
		print("FAIL reloaded upgrade total: ", SaveManager.total_upgrade_levels())
		failures += 1
	# star rewards are part of the same save round trip, boosted by the overload core
	if SaveManager.record_result("c1_02", 20, 9, 2, 30.0, true).get("coins_earned", 0) != 38:
		print("FAIL coin reward on new clear")
		failures += 1
	if SaveManager.wallet_coins() != 128:
		print("FAIL coin reward amount: ", SaveManager.wallet_coins())
		failures += 1
	# the campaign ships fully unlocked, no level is gated behind progress
	var locked_levels := 0
	for chapter in Game.catalog.chapters:
		for lv in chapter["levels"]:
			if not Game.catalog.is_level_unlocked(lv):
				locked_levels += 1
	if locked_levels != 0:
		print("FAIL locked levels: ", locked_levels)
		failures += 1
	if not Game.catalog.is_chapter_unlocked(Game.catalog.chapters.size() - 1):
		print("FAIL last chapter stays locked")
		failures += 1
	# the starter gift is handed out once to saves that predate it
	SaveManager.upgrades = {}
	SaveManager.data["starter_gift"] = false
	SaveManager.save_game()
	SaveManager.load_game()
	var gifted := 0
	for part_id in RobotUpgrades.ORDER:
		if SaveManager.upgrade_level(part_id) >= 1:
			gifted += 1
	if gifted != RobotUpgrades.ORDER.size() or not SaveManager.has_starter_gift():
		print("FAIL starter gift migration: ", SaveManager.upgrades)
		failures += 1
	# ... and never twice: bought levels survive the next reload untouched
	SaveManager.upgrades = {"arm": 2}
	SaveManager.save_game()
	SaveManager.load_game()
	if SaveManager.upgrade_level("arm") != 2 or SaveManager.upgrade_level("core") != 0:
		print("FAIL starter gift granted twice: ", SaveManager.upgrades)
		failures += 1
	var custom_id := SaveManager.save_custom_level({
		"name_zh": "????", "name_en": "Test Level",
		"rows": ["#######", "# @$. #", "#     #", "#######"],
		"par_pushes": 1, "par_moves": 1, "builtin": false,
		"hazards": {"collapse": true, "thug": true},
	})
	SaveManager.save_game()
	SaveManager.load_game()
	if SaveManager.get_custom_level(custom_id).is_empty():
		print("FAIL custom level persistence")
		failures += 1
	var reloaded_hazards: Dictionary = SaveManager.get_custom_level(custom_id).get("hazards", {})
	if not bool(reloaded_hazards.get("collapse", false)) \
			or not bool(reloaded_hazards.get("thug", false)) \
			or bool(reloaded_hazards.get("thief", false)):
		print("FAIL custom level hazards persistence: ", reloaded_hazards)
		failures += 1
	SaveManager.delete_custom_level(custom_id)
	# clean up
	SaveManager.progress = {}
	SaveManager.stats = SaveManager._default_stats()
	SaveManager.coins = 0
	SaveManager.inventory = {}
	SaveManager.upgrades = {}
	SaveManager.data["last_level"] = ""
	SaveManager.save_game()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(backup_path))
	if had_save:
		var f := FileAccess.open(save_path, FileAccess.WRITE)
		if f != null:
			f.store_buffer(save_bytes)
			f.close()
	if had_backup:
		var fb := FileAccess.open(backup_path, FileAccess.WRITE)
		if fb != null:
			fb.store_buffer(backup_bytes)
			fb.close()
	SaveManager.load_game()
	print("== save test done, failures=", failures, " ==")
	get_tree().quit(1 if failures > 0 else 0)


func _run_flow_test() -> void:
	SaveManager.capture_mode = true
	SaveManager.reset_progress()
	SaveManager.coins = 0
	SaveManager.inventory = {}
	SaveManager.upgrades = {}
	var failures := 0
	await get_tree().create_timer(1.6).timeout
	Game.goto("menu")
	await get_tree().create_timer(0.8).timeout
	# GM button on the main menu grants 100 coins per press
	var coins_menu := SaveManager.wallet_coins()
	var gm_button: Button = null
	if current_screen != null:
		for c in current_screen.find_children("*", "Button", true, false):
			if (c as Button).text.begins_with("GM"):
				gm_button = c as Button
				break
	if gm_button == null:
		print("FAIL gm button missing")
		failures += 1
	else:
		_click_at(gm_button.get_global_rect().get_center())
		await get_tree().process_frame
		_click_at(gm_button.get_global_rect().get_center())
		await get_tree().process_frame
		print("flow: gm coins ", coins_menu, " -> ", SaveManager.wallet_coins())
		if SaveManager.wallet_coins() != coins_menu + 200:
			print("FAIL gm grant")
			failures += 1
	# everything ships unlocked: any level of any chapter is playable on a fresh save
	var first := Game.catalog.first_playable_level()
	var second: LevelData = Game.catalog.get_chapter(0)["levels"][1]
	var late: LevelData = Game.catalog.get_chapter(3)["levels"].back()
	if not Game.catalog.is_level_unlocked(first):
		print("FAIL first level locked")
		failures += 1
	if not Game.catalog.is_level_unlocked(second) or not Game.catalog.is_level_unlocked(late):
		print("FAIL all levels should be unlocked from the start")
		failures += 1
	if not Game.catalog.is_chapter_unlocked(3):
		print("FAIL all chapters should be unlocked from the start")
		failures += 1
	# the starter gift hands out one level in every robot part
	SaveManager.upgrades = {}
	SaveManager.grant_starter_gift()
	var gift_parts := 0
	for part_id in RobotUpgrades.ORDER:
		if SaveManager.upgrade_level(part_id) >= 1:
			gift_parts += 1
	print("flow: starter gift parts=", gift_parts, "/", RobotUpgrades.ORDER.size())
	if gift_parts != RobotUpgrades.ORDER.size():
		print("FAIL starter gift did not upgrade every part")
		failures += 1
	if not SaveManager.has_starter_gift():
		print("FAIL starter gift flag")
		failures += 1
	# back to a clean slate for the rest of the flow
	SaveManager.upgrades = {}
	# the menu announces the gift exactly once (consume-on-read)
	SaveManager.starter_gift_announce = true
	Game.goto("menu")
	await get_tree().create_timer(0.7).timeout
	var gift_toast := ""
	if current_screen != null:
		for c in current_screen.find_children("*", "Label", true, false):
			if (c as Label).text == Loc.t("starter_gift_toast"):
				gift_toast = (c as Label).text
	print("flow: starter gift toast='", gift_toast, "'")
	if gift_toast.is_empty():
		print("FAIL starter gift toast missing")
		failures += 1
	if SaveManager.starter_gift_announce:
		print("FAIL starter gift toast not consumed")
		failures += 1
	# editor
	Game.goto("editor")
	await get_tree().create_timer(1.0).timeout
	var editor := current_screen
	if editor == null or editor.get("level") == null:
		print("FAIL editor did not open")
		get_tree().quit(1)
		return
	var lv: LevelData = editor.get("level")
	print("editor new level ", lv.width, "x", lv.height, " boxes=", lv.box_count())
	editor.call("_on_paint", Vector2i(4, 4), false)
	if not lv.walls.has(Vector2i(4, 4)):
		print("FAIL painting wall")
		failures += 1
	editor.call("_set_tool", "goal")
	editor.call("_on_paint", Vector2i(5, 4), false)
	if not lv.goals.has(Vector2i(5, 4)):
		print("FAIL painting goal")
		failures += 1
	editor.call("_on_paint", Vector2i(5, 4), true)
	var imported: LevelData = editor.call("_parse_xsb", "#######\n# @$. #\n#######")
	if imported == null or imported.box_count() != 1:
		print("FAIL xsb import parse")
		failures += 1
	var imported_json: LevelData = editor.call("_parse_xsb",
			JSON.stringify((editor.get("level") as LevelData).to_dict()))
	if imported_json == null or imported_json.box_count() != 1:
		print("FAIL json import parse")
		failures += 1
	editor.get("_name_edit").text = "Flow Test Level"
	editor.call("_apply_meta")
	var saved: bool = editor.call("_save")
	if not saved:
		print("FAIL save level")
		failures += 1
	var saved_id: String = str(editor.get("current_id"))
	print("saved custom level: ", saved_id, " total=", SaveManager.get_custom_levels().size())
	if saved_id.is_empty():
		failures += 1
	# undo/redo
	editor.call("_undo_action")
	editor.call("_redo_action")
	if not (editor.get("level") as LevelData).walls.has(Vector2i(4, 4)):
		print("FAIL undo/redo preserved wall")
		failures += 1
	# hazard toggles: switch collapse + thug + thief on for this workshop level
	for hazard_id in ["collapse", "thug", "thief"]:
		var check: CheckBox = (editor.get("_hazard_checks") as Dictionary).get(hazard_id)
		if check == null:
			print("FAIL hazard checkbox missing: ", hazard_id)
			failures += 1
			continue
		check.button_pressed = true
	await get_tree().process_frame
	var editor_level: LevelData = editor.get("level")
	print("flow: editor hazards=", editor_level.hazard_list(), " hint='",
			(editor.get("_hazard_hint") as Label).text, "'")
	if editor_level.hazard_list().size() != 3:
		print("FAIL editor hazard toggles")
		failures += 1
	if not editor.call("_save"):
		print("FAIL save level with hazards")
		failures += 1
	var stored: Dictionary = SaveManager.get_custom_level(saved_id)
	var stored_hazards: Dictionary = stored.get("hazards", {})
	print("flow: stored hazards=", stored_hazards)
	if not bool(stored_hazards.get("thug", false)) \
			or not bool(stored_hazards.get("thief", false)) \
			or not bool(stored_hazards.get("collapse", false)):
		print("FAIL hazards not persisted in the save file")
		failures += 1
	# playtest
	editor.call("_test_level")
	await get_tree().create_timer(1.5).timeout
	print("flow: screen=", Game.screen_id, " mode=", Game.current_mode(),
			" par=", Game.current_level().par_pushes)
	if Game.current_mode() != "playtest":
		print("FAIL playtest mode")
		failures += 1
	var gs := current_screen
	if gs != null:
		var hz_pt: LevelHazards = gs.get("hazards")
		print("flow: playtest hazards collapse=", hz_pt.collapse_enabled if hz_pt else "?",
				" thug=", hz_pt.thug_enabled if hz_pt else "?",
				" thief=", hz_pt.thief_enabled if hz_pt else "?")
		if hz_pt == null or not hz_pt.collapse_enabled or not hz_pt.thug_enabled \
				or not hz_pt.thief_enabled:
			print("FAIL editor hazards not active in playtest")
			failures += 1
		if hz_pt == null or hz_pt.thug.x < 0 or hz_pt.thief.x < 0:
			print("FAIL playtest enemies not spawned")
			failures += 1
		# restarting the playtest keeps the author's hazard mix
		gs.call("_restart")
		await get_tree().create_timer(0.4).timeout
		if hz_pt == null or not hz_pt.collapse_enabled:
			print("FAIL hazards lost after restart")
			failures += 1
		gs.call("_show_hint")
		await get_tree().create_timer(0.9).timeout
		var hint = gs.get("board").get("_hint")
		print("flow: hint active=", hint.active)
		if not hint.active:
			print("FAIL hint did not activate")
			failures += 1
		gs.call("_open_pause")
		await get_tree().create_timer(0.25).timeout
		if gs.get("_overlay") == null:
			print("FAIL pause overlay missing")
			failures += 1
		gs.call("_open_settings_from_pause")
		await get_tree().create_timer(0.4).timeout
		if not (gs.get("_overlay_close") as Callable).is_valid():
			print("FAIL settings modal close missing")
			failures += 1
		gs.get("_overlay_close").call()
		await get_tree().create_timer(0.3).timeout
		if gs.get("_overlay") != gs.get("_pause_overlay"):
			print("FAIL settings modal did not return to pause")
			failures += 1
		gs.get("_overlay_close").call()
		await get_tree().create_timer(0.25).timeout
	if gs != null and gs.get("state") != null:
		# real keyboard path: InputMap actions -> _unhandled_input
		var before: Vector2i = gs.get("state").player
		var moves_before: int = gs.get("state").moves
		_press_key(KEY_UP)
		await get_tree().process_frame
		print("flow: key input ", before, " -> ", gs.get("state").player,
				" moves=", gs.get("state").moves)
		if gs.get("state").player != before + Vector2i.UP \
				or int(gs.get("state").moves) != moves_before + 1:
			print("FAIL keyboard move")
			failures += 1
		_press_key(KEY_DOWN)
		await get_tree().process_frame
		if gs.get("state").player != before:
			print("FAIL keyboard move back")
			failures += 1
		# undo/redo keys are gone: shortcuts must no longer move the player
		_press_key(KEY_Z, true)
		await get_tree().process_frame
		if gs.get("state").player != before:
			print("FAIL ctrl+z still undoes for free")
			failures += 1
		_press_key(KEY_U)
		await get_tree().process_frame
		if gs.get("state").player != before:
			print("FAIL U still undoes for free")
			failures += 1
		for i in 3:
			_press_key(KEY_D)
			await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	if gs != null:
		print("flow: playtest solved=", gs.get("state").is_solved())
	Game.return_from_game()
	await get_tree().create_timer(1.2).timeout
	print("flow: returned to ", Game.screen_id, " level=",
			current_screen.get("level").name_zh if current_screen != null else "?")
	if Game.screen_id != "editor":
		print("FAIL did not return to editor")
		failures += 1
	# cleanup
	if not saved_id.is_empty():
		SaveManager.delete_custom_level(saved_id)
	# ---------------------------------------------------------------- shop items
	SaveManager.add_coins(1000, true)
	Game.start_campaign("c1_01")
	await get_tree().create_timer(0.9).timeout
	var gs2 := current_screen
	if gs2 == null or Game.screen_id != "game":
		print("FAIL campaign level did not open")
		failures += 1
	else:
		if (gs2.get("_item_buttons") as Dictionary).size() != ItemCatalog.ORDER.size():
			print("FAIL item bar missing entries")
			failures += 1
		if not bool(gs2.get("_items_enabled")):
			print("FAIL items disabled in campaign")
			failures += 1
		# rope: player (2,2), crate (3,2) -> step left drags it into (2,2)
		gs2.call("_on_item_pressed", "rope")
		if SaveManager.item_count("rope") != 1:
			print("FAIL rope not bought")
			failures += 1
		_press_key(KEY_A)
		await get_tree().process_frame
		var st: SokobanState = gs2.get("state")
		print("flow: rope -> player ", st.player, " boxes ", st.boxes.keys())
		if st.player != Vector2i(1, 2) or not st.boxes.has(Vector2i(2, 2)):
			print("FAIL rope pull")
			failures += 1
		if SaveManager.item_count("rope") != 0:
			print("FAIL rope not consumed")
			failures += 1
		# crane: pick crate (2,2) with real mouse events and drop it on (3,2)
		gs2.call("_on_item_pressed", "crane")
		var board_node: BoardView = gs2.get("board")
		_click_at(board_node.to_global(board_node.cell_center(Vector2i(2, 2))))
		await get_tree().process_frame
		print("flow: crane pick=", gs2.get("_crane_from"))
		if gs2.get("_crane_from") != Vector2i(2, 2):
			print("FAIL crane click did not reach the board")
			failures += 1
		_click_at(board_node.to_global(board_node.cell_center(Vector2i(3, 2))))
		await get_tree().process_frame
		if not st.boxes.has(Vector2i(3, 2)) or st.boxes.has(Vector2i(2, 2)):
			print("FAIL crane relocation")
			failures += 1
		# c4: player (1,2) pushes into the wall at (0,2)
		gs2.call("_on_item_pressed", "c4")
		_press_key(KEY_A)
		await get_tree().process_frame
		if st.walls.has(Vector2i(0, 2)):
			print("FAIL c4 did not break wall")
			failures += 1
		if SaveManager.item_count("c4") != 0:
			print("FAIL c4 not consumed")
			failures += 1
		# paid rewind instead of the removed free undo
		gs2.call("_on_item_pressed", "rewind")
		await get_tree().process_frame
		if not st.walls.has(Vector2i(0, 2)):
			print("FAIL rewind did not restore the wall")
			failures += 1
		# contract: instant three star clear
		gs2.call("_on_item_pressed", "guide")
		await get_tree().create_timer(0.8).timeout
		if not (gs2.get("board").get("_hint") as HintMarker).active:
			print("FAIL guide hint")
			failures += 1
		SaveManager.add_coins(200, true)
		gs2.call("_on_item_pressed", "contract")
		await get_tree().create_timer(1.3).timeout
		print("flow: contract solved=", st.is_solved(), " stars=",
				SaveManager.stars_for("c1_01"), " overlay=", gs2.get("_overlay") != null)
		if not st.is_solved() or SaveManager.stars_for("c1_01") != 3:
			print("FAIL contract clear")
			failures += 1
		if gs2.get("_overlay") == null or int(gs2.get("_overlay").z_index) <= 30:
			print("FAIL win overlay above board art")
			failures += 1
	# rewarded ad + restart gate
	Game.goto("menu")
	await get_tree().create_timer(0.8).timeout
	var coins_ads := SaveManager.wallet_coins()
	Game.goto("shop")
	await get_tree().create_timer(0.8).timeout
	var shop := current_screen
	if shop == null or Game.screen_id != "shop":
		print("FAIL shop did not open")
		failures += 1
	else:
		shop.call("_buy", "guide")
		if SaveManager.item_count("guide") < 1:
			print("FAIL shop purchase")
			failures += 1
		shop.call("_watch_ad")
		await get_tree().create_timer(0.25).timeout
		for child in shop.get_children():
			if child is AdPopup:
				(child as AdPopup).finish_now()
		await get_tree().create_timer(0.25).timeout
		print("flow: ad coins ", coins_ads, " -> ", SaveManager.wallet_coins())
		if SaveManager.wallet_coins() < coins_ads + ItemCatalog.AD_REWARD - 40:
			print("FAIL ad reward")
			failures += 1
	# restart requires watching the ad
	Game.start_campaign("c1_02")
	await get_tree().create_timer(0.9).timeout
	var gs3 := current_screen
	if gs3 != null and gs3.get("state") != null:
		_press_key(KEY_A)
		await get_tree().process_frame
		var moves_before: int = gs3.get("state").moves
		gs3.call("_request_restart")
		await get_tree().create_timer(0.25).timeout
		var popup: Variant = gs3.get("_ad_popup")
		print("flow: restart gate popup=", popup != null, " moves=", moves_before)
		if popup == null:
			print("FAIL restart not gated by ad")
			failures += 1
		else:
			if int(gs3.get("state").moves) != moves_before:
				print("FAIL level restarted before the ad finished")
				failures += 1
			(popup as AdPopup).finish_now()
			await get_tree().create_timer(0.35).timeout
			if int(gs3.get("state").moves) != 0:
				print("FAIL level did not restart after the ad")
				failures += 1
	Game.goto("menu")
	await get_tree().create_timer(0.6).timeout
	# robot upgrade bay: click a body hotspot, buy a level, use the ability in game
	SaveManager.coins = 1000
	Game.goto("robot")
	await get_tree().create_timer(0.9).timeout
	var bay := current_screen
	if bay == null or Game.screen_id != "robot":
		print("FAIL robot screen did not open")
		failures += 1
	else:
		var hotspots: Dictionary = bay.get("_hotspots")
		print("flow: robot hotspots=", hotspots.size())
		if hotspots.size() != RobotUpgrades.ORDER.size():
			print("FAIL robot hotspots")
			failures += 1
		var arm_btn: Button = hotspots.get("arm")
		_click_at(arm_btn.get_global_rect().get_center())
		await get_tree().process_frame
		if str(bay.get("_selected")) != "arm":
			print("FAIL robot hotspot select")
			failures += 1
		var buy: Button = bay.get("_detail_buy")
		_click_at(buy.get_global_rect().get_center())
		await get_tree().process_frame
		print("flow: arm level=", SaveManager.upgrade_level("arm"),
				" coins=", SaveManager.wallet_coins())
		if SaveManager.upgrade_level("arm") != 1 or SaveManager.wallet_coins() != 880:
			print("FAIL robot upgrade purchase")
			failures += 1
		SaveManager.upgrade_part("hook")
	Game.start_campaign("c1_01")
	await get_tree().create_timer(0.9).timeout
	var gs4 := current_screen
	if gs4 != null and gs4.get("state") != null:
		var chain_label: Label = gs4.get("_chain_label")
		print("flow: chain label='", chain_label.text, "' hook charges=",
				(gs4.get("_charges") as Dictionary).get("hook", -99))
		if not chain_label.visible or not chain_label.text.contains("2"):
			print("FAIL chain label")
			failures += 1
		if int((gs4.get("_charges") as Dictionary).get("hook", 0)) != 3:
			print("FAIL hook charges not granted")
			failures += 1
		var hook_btn: Button = (gs4.get("_ability_buttons") as Dictionary).get("hook")
		if hook_btn == null or hook_btn.disabled:
			print("FAIL hook ability button")
			failures += 1
		else:
			_click_at(hook_btn.get_global_rect().get_center())
			await get_tree().process_frame
			if str(gs4.get("_armed")) != "ability:hook":
				print("FAIL hook ability not armed")
				failures += 1
			_press_key(KEY_D)
			await get_tree().process_frame
			var st4: SokobanState = gs4.get("state")
			print("flow: pass-through -> player ", st4.player, " charges=",
					(gs4.get("_charges") as Dictionary).get("hook", -99))
			if int((gs4.get("_charges") as Dictionary).get("hook", 0)) != 2:
				print("FAIL claw charge not spent")
				failures += 1
			if st4.player != Vector2i(4, 2):
				print("FAIL claw pass position")
				failures += 1
		# depleted charges can be topped up with coins straight from the toolbar
		var pool: Dictionary = gs4.get("_charges")
		pool["hook"] = 0
		gs4.call("_refresh_toolbar")
		await get_tree().process_frame
		var badge: Label = (gs4.get("_ability_badges") as Dictionary).get("hook")
		var coins_before_buy := SaveManager.wallet_coins()
		print("flow: depleted badge='", badge.text if badge != null else "?",
				"' coins=", coins_before_buy)
		if badge == null or not badge.text.begins_with("+"):
			print("FAIL depleted charge badge does not offer a price")
			failures += 1
		_click_at(hook_btn.get_global_rect().get_center())
		await get_tree().process_frame
		print("flow: bought charge -> hook=", int(pool.get("hook", 0)), " coins=",
				SaveManager.wallet_coins(), " armed=", gs4.get("_armed"))
		if int(pool.get("hook", 0)) != 1:
			print("FAIL bought charge not granted")
			failures += 1
		if SaveManager.wallet_coins() != coins_before_buy - RobotUpgrades.EXTRA_CHARGE_PRICE:
			print("FAIL charge purchase price")
			failures += 1
		if str(gs4.get("_armed")) != "ability:hook":
			print("FAIL bought charge did not arm the ability")
			failures += 1
		# without coins the purchase is refused and nothing is armed
		gs4.call("_disarm")
		pool["hook"] = 0
		SaveManager.coins = 5
		gs4.call("_refresh_toolbar")
		await get_tree().process_frame
		_click_at(hook_btn.get_global_rect().get_center())
		await get_tree().process_frame
		print("flow: broke charge buy -> hook=", int(pool.get("hook", 0)),
				" coins=", SaveManager.wallet_coins(), " armed='", gs4.get("_armed"), "'")
		if int(pool.get("hook", 0)) != 0 or SaveManager.wallet_coins() != 5:
			print("FAIL broke buyer got a charge")
			failures += 1
		if str(gs4.get("_armed")) != "":
			print("FAIL broke buyer armed the ability")
			failures += 1
	Game.goto("menu")
	await get_tree().create_timer(0.6).timeout
	# chapter hazards: rubble, thug and thief
	Game.start_campaign("c2_01")
	await get_tree().create_timer(0.9).timeout
	var gs5 := current_screen
	var hz5: LevelHazards = gs5.get("hazards") if gs5 != null else null
	if hz5 == null:
		print("FAIL chapter 2 hazards missing")
		failures += 1
	else:
		print("flow: c2 collapse=", hz5.collapse_enabled, " thug=", hz5.thug_enabled,
				" thief=", hz5.thief_enabled)
		if not hz5.collapse_enabled or hz5.thug_enabled:
			print("FAIL chapter 2 hazard mix")
			failures += 1
		var rubble := hz5.spawn_rubble()
		var st5: SokobanState = gs5.get("state")
		if rubble < 1 or st5.temp_walls.is_empty():
			print("FAIL rubble spawn")
			failures += 1
		await get_tree().create_timer(0.3).timeout
		hz5.tick(LevelHazards.COLLAPSE_LIFETIME + 0.5)
		await get_tree().process_frame
		if not st5.temp_walls.is_empty():
			print("FAIL rubble did not expire")
			failures += 1
	Game.start_campaign("c3_01")
	await get_tree().create_timer(0.9).timeout
	var gs6 := current_screen
	var hz6: LevelHazards = gs6.get("hazards") if gs6 != null else null
	if hz6 == null or not hz6.thug_enabled or hz6.thief_enabled:
		print("FAIL chapter 3 hazards")
		failures += 1
	else:
		var st6: SokobanState = gs6.get("state")
		# park the thug on a free neighbour tile (a crate tile would flatten it)
		var thug_start := Vector2i(-1, -1)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cell: Vector2i = st6.player + offset
			if not st6.boxes.has(cell) and not st6.walls.has(cell):
				thug_start = cell
				break
		hz6.thug = thug_start if thug_start.x >= 0 else st6.player + Vector2i(1, 0)
		hz6.notify_action()
		hz6.notify_action()
		await get_tree().create_timer(0.4).timeout
		print("flow: thug caught? failed=", gs6.get("_failed"), " overlay=",
				gs6.get("_overlay") != null)
		if not bool(gs6.get("_failed")) or gs6.get("_overlay") == null:
			print("FAIL thug defeat overlay")
			failures += 1
		gs6.call("_restart")
		await get_tree().create_timer(0.4).timeout
		if bool(gs6.get("_failed")) or gs6.get("_overlay") != null:
			print("FAIL defeat retry")
			failures += 1
		# a crate shoved onto the thug flattens it and the run goes on
		var st6b: SokobanState = gs6.get("state")
		hz6.thug = st6b.boxes.keys()[0]
		hz6.notify_action()
		await get_tree().process_frame
		print("flow: thug after crush=", hz6.thug, " failed=", gs6.get("_failed"))
		if hz6.thug != Vector2i(-1, -1) or bool(gs6.get("_failed")):
			print("FAIL thug crush")
			failures += 1
	Game.start_campaign("c4_01")
	await get_tree().create_timer(0.9).timeout
	var gs7 := current_screen
	var hz7: LevelHazards = gs7.get("hazards") if gs7 != null else null
	if hz7 == null or not hz7.thief_enabled:
		print("FAIL chapter 4 thief missing")
		failures += 1
	else:
		var st7: SokobanState = gs7.get("state")
		var crate: Vector2i = st7.boxes.keys()[0]
		hz7.thug = Vector2i(-1, -1)
		hz7.thief = crate
		hz7.thief_target = crate
		hz7.thief_grab = 2
		hz7.notify_action()
		hz7.notify_action()
		await get_tree().create_timer(0.4).timeout
		print("flow: thief stole?", not st7.boxes.has(crate), " failed=", gs7.get("_failed"))
		if st7.boxes.has(crate) or not bool(gs7.get("_failed")):
			print("FAIL thief steal")
			failures += 1
		gs7.call("_restart")
		await get_tree().create_timer(0.35).timeout
		# walking into the thief destroys it instead of failing the run
		var st7b: SokobanState = gs7.get("state")
		var thief_cell := Vector2i(-1, -1)
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var cell: Vector2i = st7b.player + offset
			if not st7b.boxes.has(cell) and not st7b.walls.has(cell):
				thief_cell = cell
				break
		hz7.thug = Vector2i(-1, -1)
		hz7.thief = thief_cell
		var crate_before: int = st7b.boxes.size()
		var keys := {Vector2i(1, 0): KEY_D, Vector2i(-1, 0): KEY_A,
				Vector2i(0, 1): KEY_S, Vector2i(0, -1): KEY_W}
		_press_key(keys.get(thief_cell - st7b.player, KEY_D))
		await get_tree().create_timer(0.35).timeout
		print("flow: thief killed=", hz7.thief == Vector2i(-1, -1), " failed=",
				gs7.get("_failed"), " boxes=", st7b.boxes.size(), "/", crate_before)
		if hz7.thief != Vector2i(-1, -1) or bool(gs7.get("_failed")):
			print("FAIL thief contact kill")
			failures += 1
		if st7b.boxes.size() != crate_before:
			print("FAIL thief kill lost a crate")
			failures += 1
		# a new thief shows up 20 s later and never spawns next to a crate
		hz7.tick(LevelHazards.THIEF_RESPAWN_SECONDS - 1.0)
		await get_tree().process_frame
		var early: Vector2i = hz7.thief
		hz7.tick(1.5)
		await get_tree().create_timer(0.3).timeout
		var near_crate := st7b.boxes.has(hz7.thief) or hz7._touches_crate(hz7.thief)
		print("flow: thief respawn early=", early, " after=", hz7.thief,
				" near_crate=", near_crate, " failed=", gs7.get("_failed"))
		if early.x >= 0 or hz7.thief.x < 0 or near_crate:
			print("FAIL thief respawn")
			failures += 1
		# a crate on the thief's tile is handed over: instant failure + defeat overlay
		gs7.call("_restart")
		await get_tree().create_timer(0.35).timeout
		var st7c: SokobanState = gs7.get("state")
		var loot: Vector2i = st7c.boxes.keys()[0]
		hz7.thug = Vector2i(-1, -1)
		hz7.thief = loot
		hz7.thief_target = Vector2i(-1, -1)
		hz7.thief_grab = 0
		var boxes_before: int = st7c.boxes.size()
		hz7.notify_action()
		await get_tree().create_timer(0.4).timeout
		print("flow: crate handed over? boxes=", st7c.boxes.size(), "/", boxes_before,
				" failed=", gs7.get("_failed"), " overlay=", gs7.get("_overlay") != null)
		if st7c.boxes.size() != boxes_before - 1 or not bool(gs7.get("_failed")):
			print("FAIL thief takes the crate on its tile")
			failures += 1
		if gs7.get("_overlay") == null:
			print("FAIL crate theft shows no defeat overlay")
			failures += 1
		gs7.call("_restart")
		await get_tree().create_timer(0.35).timeout
		# yanking the crate away from a prying thief resets its progress
		var st7d: SokobanState = gs7.get("state")
		var pried: Vector2i = st7d.boxes.keys()[0]
		hz7.thug = Vector2i(-1, -1)
		hz7.thief = pried
		hz7.thief_target = pried
		hz7.thief_grab = 1
		var dest := Vector2i(-1, -1)
		for cell in st7d.floor_cells():
			if not st7d.boxes.has(cell) and cell != st7d.player and cell != pried:
				dest = cell
				break
		var boxes_before_pry: int = st7d.boxes.size()
		var moved: bool = st7d.teleport_box(pried, dest)
		await get_tree().create_timer(0.35).timeout
		print("flow: pry interrupt moved=", moved, " grab=", hz7.thief_grab,
				" target=", hz7.thief_target, " failed=", gs7.get("_failed"),
				" boxes=", st7d.boxes.size(), "/", boxes_before_pry)
		if not moved or hz7.thief_grab != 0 or hz7.thief_target != Vector2i(-1, -1):
			print("FAIL pry interrupt")
			failures += 1
		if bool(gs7.get("_failed")) or st7d.boxes.size() != boxes_before_pry:
			print("FAIL pry interrupt changed the run state")
			failures += 1
		gs7.call("_restart")
		await get_tree().create_timer(0.3).timeout
	Game.goto("menu")
	await get_tree().create_timer(0.6).timeout
	# chain push in a real session: crate sprites must follow the crates
	var chain_lv := LevelData.from_rows([
		"#########",
		"#       #",
		"#@$$..  #",
		"#########",
	], {"id": "flow_chain", "name": "Chain Push", "par_pushes": 4})
	Game.start_custom(chain_lv)
	await get_tree().create_timer(0.9).timeout
	var gs8 := current_screen
	if gs8 == null or gs8.get("state") == null:
		print("FAIL chain push session did not start")
		failures += 1
	else:
		var board8: BoardView = gs8.get("board")
		var st8: SokobanState = gs8.get("state")
		_press_key(KEY_D)
		await get_tree().process_frame
		_press_key(KEY_D)
		await get_tree().create_timer(0.45).timeout
		var sprites8: Dictionary = board8.get("_box_sprites")
		var aligned := sprites8.size() == st8.boxes.size()
		for cell in st8.boxes.keys():
			if not sprites8.has(cell):
				aligned = false
		var stray := 0
		for child in board8.get_children():
			if child is Sprite2D and (child as Sprite2D).z_index == 5:
				stray += 1
		print("flow: chain push boxes=", st8.boxes.keys(), " sprites=",
				sprites8.keys(), " solved=", st8.is_solved())
		if not aligned:
			print("FAIL chain push sprite desync")
			failures += 1
		if stray != sprites8.size():
			print("FAIL chain push left ", stray, " crate graphics for ", sprites8.size(), " crates")
			failures += 1
		if st8.moves != 2 or st8.pushes != 4:
			print("FAIL chain push counts moves=", st8.moves, " pushes=", st8.pushes)
			failures += 1
		if not st8.is_solved():
			print("FAIL chain push did not solve")
			failures += 1
		for goal_cell in [Vector2i(4, 2), Vector2i(5, 2)]:
			var goal8: Sprite2D = sprites8.get(goal_cell)
			if goal8 == null or goal8.texture != UIKit.art("box_goal"):
				print("FAIL chain push goal texture at ", goal_cell)
				failures += 1
	Game.goto("menu")
	await get_tree().create_timer(0.6).timeout
	# level select + settings navigation
	Game.goto("level_select", {"chapter": 0})
	await get_tree().create_timer(0.8).timeout
	Game.goto("settings", {"return_to": "menu"})
	await get_tree().create_timer(0.8).timeout
	Game.goto("menu")
	await get_tree().create_timer(0.8).timeout
	print("flow: final screen=", Game.screen_id)
	print("== flow test done, failures=", failures, " ==")
	get_tree().quit(1 if failures > 0 else 0)


func _click_at(viewport_pos: Vector2) -> void:
	# Input.parse_input_event takes window coordinates, so undo the display stretch.
	var viewport_size := get_viewport().get_visible_rect().size
	var window_size := Vector2(get_window().size)
	var pos := viewport_pos * window_size / viewport_size
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = pos
	down.global_position = pos
	Input.parse_input_event(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	Input.parse_input_event(up)


func _press_key(code: Key, ctrl := false, shift := false) -> void:
	var down := InputEventKey.new()
	down.keycode = code
	down.physical_keycode = code
	down.ctrl_pressed = ctrl
	down.shift_pressed = shift
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.ctrl_pressed = ctrl
	up.shift_pressed = shift
	up.pressed = false
	Input.parse_input_event(up)


func _shot(shot_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("screenshot failed: %s" % shot_name)
		return
	img.save_png("%s/%s.png" % [SHOT_DIR, shot_name])
	print("captured ", ProjectSettings.globalize_path(SHOT_DIR) + "/" + shot_name, ".png")


func _build_shell() -> void:
	var bg := ColorRect.new()
	bg.color = UIKit.COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	screen_host = Control.new()
	screen_host.name = "ScreenHost"
	screen_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen_host.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(screen_host)

	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.035, 0.05, 0.08, 1.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade_rect)


func _boot() -> void:
	await get_tree().process_frame
	_swap_screen("menu", {})
	await get_tree().process_frame
	await _fade_to(0.0, 0.55)


func change_screen(target: String, params: Dictionary = {}) -> void:
	if _busy:
		return
	_busy = true
	await _fade_to(1.0, 0.17)
	_swap_screen(target, params)
	await get_tree().process_frame
	await _fade_to(0.0, 0.2)
	_busy = false
	Game.screen_changed.emit(target)


func _swap_screen(target: String, params: Dictionary) -> void:
	var path := str(Game.SCREEN_PATHS.get(target, ""))
	if path.is_empty():
		push_error("Unknown screen: %s" % target)
		return
	var script: Script = load(path)
	if script == null:
		push_error("Cannot load screen script: %s" % path)
		return
	if current_screen != null and is_instance_valid(current_screen):
		screen_host.remove_child(current_screen)
		current_screen.queue_free()
		current_screen = null
	var screen: Control = script.new()
	screen.set("params", params)
	screen_host.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current_screen = screen
	Game.screen_id = target


func _fade_to(alpha: float, duration: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade_rect, "color:a", alpha, duration).set_trans(Tween.TRANS_SINE)
	await tw.finished


func _exit_tree() -> void:
	UIKit.clear_cache()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			var fs := bool(SaveManager.get_setting("fullscreen", false))
			SaveManager.set_setting("fullscreen", not fs)
			get_viewport().set_input_as_handled()

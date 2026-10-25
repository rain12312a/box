extends RefCounted
## Headless self test: run with `godot --headless --path . -- --selftest`.
## Verifies the bundled campaign, the rule engine and the GDScript solver.

var failures := 0
var checks := 0


func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("  FAIL: ", label)


func run() -> int:
	print("== self test ==")
	SaveManager.capture_mode = true
	_test_catalog()
	_test_roundtrip()
	_test_state()
	_test_validation()
	_test_xsb()
	_test_localization()
	_test_items()
	_test_robot()
	_test_robot_state()
	_test_hazards()
	_test_thug_crushed()
	_test_thief_killed()
	_test_thief_spawn_distance()
	_test_pry_interrupted()
	_test_editor_hazards()
	_test_unlocks()
	_test_starter_gift()
	_test_board_sprites()
	_test_wallet()
	_test_solver_all()
	_test_hints()
	print("== %d checks, %d failures ==" % [checks, failures])
	return 1 if failures > 0 else 0


func _test_catalog() -> void:
	var catalog := LevelCatalog.new()
	check(catalog.load_builtin(), "campaign loads")
	check(catalog.total_levels() == 44, "44 levels (got %d)" % catalog.total_levels())
	check(catalog.chapters.size() == 4, "4 chapters")
	var total_boxes := 0
	for chapter in catalog.chapters:
		check((chapter["levels"] as Array).size() == (8 if chapter["id"] == "chapter_1" else 12),
				"chapter size %s" % chapter["id"])
		for level in chapter["levels"]:
			total_boxes += level.box_count()
			check(level.box_count() == level.goal_count(), "boxes==goals %s" % level.id)
			check(level.par_pushes > 0, "par set %s" % level.id)
	check(total_boxes > 100, "campaign has crates (got %d)" % total_boxes)


func _test_roundtrip() -> void:
	var catalog := LevelCatalog.new()
	catalog.load_builtin()
	for chapter in catalog.chapters:
		for level in chapter["levels"]:
			var rows: Array = level.to_rows()
			var reparsed := LevelData.from_rows(rows)
			check(reparsed.to_rows() == rows, "roundtrip %s" % level.id)
			check(reparsed.player == level.player, "player roundtrip %s" % level.id)
			check(reparsed.box_count() == level.box_count(), "boxes roundtrip %s" % level.id)


func _test_state() -> void:
	var level := LevelData.from_rows(["#######", "#     #", "# @$. #", "#     #", "#######"])
	var state := SokobanState.new()
	state.setup(level)
	check(state.moves == 0 and state.pushes == 0, "initial counters")
	check(not state.is_solved(), "not solved initially")
	var result := state.try_move(Vector2i.RIGHT)
	check(bool(result["moved"]), "push moves")
	check(bool(result["pushed"]), "push flag")
	check(state.moves == 1 and state.pushes == 1, "counters after push")
	check(state.is_solved(), "solved after push")
	check(state.can_undo(), "can undo")
	check(state.undo(), "undo works")
	check(state.moves == 0 and state.pushes == 0, "counters after undo")
	check(not state.is_solved(), "unsolved after undo")
	check(state.can_redo(), "can redo")
	check(state.redo(), "redo works")
	check(state.is_solved(), "solved after redo")
	check(state.undo(), "undo again")
	state.reset()
	check(state.moves == 0 and not state.is_solved(), "reset restores")
	check(not state.can_undo(), "reset clears history")

	# blocked movement
	var blocked := state.try_move(Vector2i.UP)
	check(bool(blocked["moved"]), "move up")
	state.try_move(Vector2i.UP)
	var wall_hit := state.try_move(Vector2i.UP)
	check(not bool(wall_hit["moved"]) and bool(wall_hit["blocked"]), "wall blocks")

	# box against box / wall should not move
	var lv2 := LevelData.from_rows(["########", "# @$ $ #", "#      #", "########"])
	var st2 := SokobanState.new()
	st2.setup(lv2)
	var r2 := st2.try_move(Vector2i.RIGHT)
	check(bool(r2["moved"]) and bool(r2["pushed"]), "first box pushes")
	check(st2.pushes == 1, "push counted")
	var r3 := st2.try_move(Vector2i.RIGHT)
	check(not bool(r3["moved"]), "box on box blocks")


func _test_validation() -> void:
	var bad := LevelData.from_rows(["#####", "#   #", "# $ #", "#####"])
	check(not bad.is_valid(), "missing player invalid")
	var mismatch := LevelData.from_rows(["#######", "# @$ .#", "#     #", "#######"])
	# one crate, one goal -> valid
	check(mismatch.is_valid(), "one-to-one valid")
	var two_goals := LevelData.from_rows(["#######", "# @$..#", "#     #", "#######"])
	check(not two_goals.is_valid(), "mismatched counts invalid")
	var corner := LevelData.from_rows(["#####", "#@  #", "# $ #", "#  .#", "#####"])
	check(corner.is_valid(), "corner box is only a warning")


func _validate_path(level: LevelData, path: Array) -> bool:
	var sim := SokobanState.new()
	sim.setup(level)
	for step in path:
		var raw_box := int(step.get("box", -1))
		if raw_box < 0:
			return false
		var box := Vector2i(raw_box % level.width, raw_box / level.width)
		var dir: Vector2i = SokobanSolver.DIRS[int(step["dir"])]
		if not sim.has_box(box):
			return false
		sim.player = box - dir
		var r := sim.try_move(dir)
		if not bool(r["pushed"]) or r["box_from"] != box:
			return false
	return sim.is_solved()


func _test_xsb() -> void:
	var lv := LevelData.from_rows([
		"########",
		"# @$ .*#",
		"#      #",
		"#  +   #",
		"########",
	])
	check(lv.width == 8 and lv.height == 5, "xsb dimensions")
	check(lv.box_count() == 2, "xsb boxes (got %d)" % lv.box_count())
	check(lv.goal_count() == 3, "xsb goals (got %d)" % lv.goal_count())
	check(lv.player == Vector2i(3, 3), "xsb plus player")
	check(lv.has_goal(Vector2i(3, 3)), "player on goal")
	check(lv.has_goal(Vector2i(6, 1)) and lv.has_box(Vector2i(6, 1)), "box on goal")
	var roundtrip := LevelData.from_rows(lv.to_rows())
	check(roundtrip.to_rows() == lv.to_rows(), "xsb roundtrip")
	var errors := lv.validate()
	check(not errors.is_empty(), "mismatch reported")


func _test_localization() -> void:
	var old := Loc.language
	Loc.set_language("en", true)
	check(Loc.t("menu_continue") == "Continue", "english string lookup")
	check(Loc.t("editor_tool_wall") == "Wall", "editor tool english")
	Loc.set_language("zh", true)
	check(Loc.t("menu_continue") == "继续游戏", "chinese string lookup")
	check(not Loc.t("editor_tool_wall").is_empty(), "chinese tool string")
	Loc.set_language(old, true)
	check(Audio.has_sfx("push"), "push sfx loaded")
	var streams: Dictionary = Audio.get("_streams")
	var music: Variant = streams.get("music_game")
	check(music != null and music is AudioStreamWAV, "game music loaded")
	if music is AudioStreamWAV:
		check((music as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED,
				"music loops")


func _test_items() -> void:
	for item_id in ItemCatalog.ORDER:
		check(ItemCatalog.has_item(item_id), "item registered %s" % item_id)
		check(ItemCatalog.price(item_id) > 0, "item price %s" % item_id)
		check(not ItemCatalog.display_name(item_id).begins_with("item_"),
				"item name localized %s" % item_id)
		check(not ItemCatalog.description(item_id).begins_with("item_"),
				"item desc localized %s" % item_id)
		check(UIKit.icon(ItemCatalog.icon_name(item_id)) != null, "item icon %s" % item_id)
	check(ItemCatalog.price("c4") == 25, "c4 price")
	check(ItemCatalog.price("crane") == 50, "crane price")
	check(ItemCatalog.price("contract") == 100, "contract price")
	check(ItemCatalog.price("rope") == 25, "rope price")
	check(ItemCatalog.price("rewind") == 10, "rewind price")
	check(ItemCatalog.price("guide") == 10, "guide price")
	check(ItemCatalog.coins_for_stars(1) == 15, "1 star -> 15 coins")
	check(ItemCatalog.coins_for_stars(2) == 30, "2 stars -> 30 coins")
	check(ItemCatalog.coins_for_stars(3) == 45, "3 stars -> 45 coins")
	check(ItemCatalog.AD_REWARD == 25 and ItemCatalog.AD_SECONDS == 5.0, "ad config")
	# one extra ability use is a fixed 20 coin purchase, never infinite parts
	check(RobotUpgrades.EXTRA_CHARGE_PRICE == 20, "extra charge price")
	check(RobotUpgrades.extra_charge_price("head") == 20, "phase visor charges are buyable")
	check(RobotUpgrades.extra_charge_price("arm") == 0, "passive parts have no charges")
	check(RobotUpgrades.can_buy_charges("head", 1), "upgraded active part can buy charges")
	check(not RobotUpgrades.can_buy_charges("head", 0), "uninstalled parts cannot")
	check(not RobotUpgrades.can_buy_charges("arm", 2), "passive parts cannot")

	var lv := LevelData.from_rows([
		"#########",
		"#   #   #",
		"# @$ .  #",
		"#       #",
		"#########",
	])
	var st := SokobanState.new()
	st.setup(lv)
	# C4 removes an adjacent wall and can be undone
	check(st.break_wall(Vector2i(4, 1)), "c4 breaks wall")
	check(not st.walls.has(Vector2i(4, 1)), "c4 wall gone")
	st.undo()
	check(st.walls.has(Vector2i(4, 1)), "c4 undo restores wall")
	check(st.break_wall(Vector2i(4, 1)), "c4 breaks again")
	st.redo()
	check(not st.walls.has(Vector2i(4, 1)), "redo breaks wall again")
	# rope pulls the crate behind the player
	var before := st.player
	var pull := st.pull(Vector2i.LEFT)
	check(bool(pull["moved"]) and bool(pull["pulled"]), "rope pulls crate")
	check(st.player == before + Vector2i.LEFT and st.boxes.has(before), "crate follows player")
	st.undo()
	check(st.player == before and st.boxes.has(before + Vector2i.RIGHT), "pull undo")
	# crane teleports a crate, refusing walls, crates and the player cell
	check(st.teleport_box(before + Vector2i.RIGHT, Vector2i(4, 1)), "crane drops crate")
	check(st.boxes.has(Vector2i(4, 1)), "crate relocated")
	check(not st.teleport_box(Vector2i(4, 1), Vector2i(4, 0)), "crane refuses walls")
	check(not st.teleport_box(Vector2i(4, 1), before), "crane refuses the player cell")
	st.undo()
	check(st.boxes.has(before + Vector2i.RIGHT), "teleport undo")
	# outside contract finishes with three stars and snaps crates onto goals
	var cheat := SokobanState.new()
	cheat.setup(lv)
	cheat.force_win()
	check(cheat.is_solved() and cheat.cheated, "contract solves level")
	check(cheat.goals.has(cheat.boxes.keys()[0]), "contract moves crate onto a goal")
	# reset restores the original walls after a C4 blast
	st.reset()
	check(st.walls.has(Vector2i(4, 1)) and st.player == lv.player, "restart restores walls")


func _test_robot() -> void:
	check(RobotUpgrades.ORDER.size() == 6, "six robot parts")
	for part_id in RobotUpgrades.ORDER:
		check(RobotUpgrades.has_part(part_id), "robot part %s" % part_id)
		var point := RobotUpgrades.hotspot(part_id)
		check(point.x > 0.0 and point.x < 1.0 and point.y > 0.0 and point.y < 1.0,
				"hotspot inside art %s" % part_id)
		check(UIKit.icon(RobotUpgrades.icon_name(part_id)) != null,
				"robot icon %s" % part_id)
		check(not RobotUpgrades.part_name(part_id).begins_with("robot_"),
				"robot name localized %s" % part_id)
		check(not RobotUpgrades.summary(part_id).begins_with("robot_"),
				"robot summary localized %s" % part_id)
		for level in range(1, RobotUpgrades.MAX_LEVEL + 1):
			check(RobotUpgrades.price(part_id, level) > 0, "price %s lv%d" % [part_id, level])
			check(not RobotUpgrades.effect_text(part_id, level).begins_with("robot_"),
					"effect text %s lv%d" % [part_id, level])
	check(RobotUpgrades.price("arm", 1) == 120 and RobotUpgrades.price("arm", 3) == 520,
			"arm prices")
	check(RobotUpgrades.price("arm", 4) == -1, "no price past max level")
	check(RobotUpgrades.chain_for(0) == 1 and RobotUpgrades.chain_for(1) == 2
			and RobotUpgrades.chain_for(3) == 4, "ram chain grows")
	check(RobotUpgrades.charges_for("hook", 0) == 0, "no charges before upgrade")
	check(RobotUpgrades.charges_for("hook", 1) == 3, "hook lv1 charges")
	check(RobotUpgrades.charges_for("hook", 3) == -1, "hook lv3 unlimited")
	check(RobotUpgrades.charges_for("head", 3) == 3, "phase lv3 charges")
	check(is_equal_approx(RobotUpgrades.coin_bonus(0), 0.0), "core lv0 no bonus")
	check(is_equal_approx(RobotUpgrades.coin_bonus(3), 1.0), "core lv3 doubles coins")
	check(RobotUpgrades.is_active("hook") and not RobotUpgrades.is_active("arm"),
			"arm is passive")

	# wallet level API
	var coins_before := SaveManager.wallet_coins()
	var upgrades_before: Dictionary = SaveManager.upgrades.duplicate(true)
	SaveManager.coins = 500
	SaveManager.upgrades = {}
	check(SaveManager.upgrade_level("arm") == 0, "arm starts at 0")
	check(SaveManager.upgrade_cost("arm") == 120, "first arm cost")
	check(SaveManager.upgrade_part("arm"), "buy arm lv1")
	check(SaveManager.upgrade_level("arm") == 1, "arm is lv1")
	check(SaveManager.wallet_coins() == 380, "arm lv1 costs 120")
	check(SaveManager.upgrade_part("arm"), "buy arm lv2")
	check(SaveManager.wallet_coins() == 120, "arm lv2 costs 260")
	check(not SaveManager.upgrade_part("arm"), "cannot afford lv3")
	check(SaveManager.upgrade_level("arm") == 2, "arm stays lv2")
	SaveManager.coins = 2000
	check(SaveManager.upgrade_part("arm"), "buy arm lv3")
	check(SaveManager.upgrade_level("arm") == 3, "arm maxed")
	check(SaveManager.upgrade_cost("arm") == -1, "no more levels")
	check(not SaveManager.upgrade_part("arm"), "cannot exceed max level")
	check(SaveManager.total_upgrade_levels() == 3, "upgrade total counts")
	check(SaveManager.invested_upgrade_coins() == 900, "invested coins tracked")
	SaveManager.upgrades = {"core": 3}
	check(is_equal_approx(SaveManager.coin_multiplier(), 2.0), "core doubles rewards")
	var refund := SaveManager.reset_upgrades()
	check(refund == int(floor(900 * 0.7)), "reset refunds 70 percent")
	check(SaveManager.upgrade_level("arm") == 0, "reset clears levels")
	SaveManager.coins = coins_before
	SaveManager.upgrades = upgrades_before


func _test_robot_state() -> void:
	var row := LevelData.from_rows([
		"##########",
		"#        #",
		"# @$$  . #",
		"##########",
	])
	var st := SokobanState.new()
	st.setup(row)
	var single := st.try_move(Vector2i.RIGHT, 1)
	check(not bool(single["moved"]), "two crates block a plain push")
	var chain := st.try_move(Vector2i.RIGHT, 2)
	check(bool(chain["moved"]) and bool(chain["pushed"]), "ram pushes a crate line")
	check(st.boxes.has(Vector2i(4, 2)) and st.boxes.has(Vector2i(5, 2)),
			"both crates shifted")
	check(st.pushes == 2, "two crates counted as two pushes")
	check((chain.get("boxes_moved", []) as Array).size() == 2, "chain record lists crates")
	st.undo()
	check(st.boxes.has(Vector2i(3, 2)) and st.boxes.has(Vector2i(4, 2)), "chain undo")
	check(st.pushes == 0, "chain undo restores push count")

	var lane := LevelData.from_rows([
		"######",
		"#    #",
		"# @$ #",
		"#    #",
		"######",
	])
	var jump_state := SokobanState.new()
	jump_state.setup(lane)
	var blocked_jump := SokobanState.new()
	blocked_jump.setup(LevelData.from_rows([
		"######",
		"#    #",
		"# @$##",
		"#    #",
		"######",
	]))
	var before := jump_state.player
	check(not blocked_jump.jump_over(Vector2i.RIGHT), "cannot jump into a wall")
	check(jump_state.jump_over(Vector2i.RIGHT), "jump over a crate")
	check(jump_state.player == Vector2i(4, 2), "landed behind the crate")
	check(jump_state.boxes.has(Vector2i(3, 2)), "crate stays put when jumped over")
	check(jump_state.moves == 1, "jump counts a move")
	jump_state.undo()
	check(jump_state.player == before and jump_state.moves == 0, "jump undo")
	jump_state.redo()
	check(jump_state.player == Vector2i(4, 2), "jump redo")

	var wall_level := LevelData.from_rows([
		"######",
		"# @#.#",
		"######",
	])
	var phase_state := SokobanState.new()
	phase_state.setup(wall_level)
	check(not phase_state.phase_through(Vector2i.LEFT), "phase needs a wall ahead")
	check(phase_state.phase_through(Vector2i.RIGHT), "phase through a wall")
	check(phase_state.player == Vector2i(4, 1), "phased to the far side")
	check(phase_state.walls.has(Vector2i(3, 1)), "wall survives the phase")
	phase_state.undo()
	check(phase_state.player == Vector2i(2, 1), "phase undo")

	var warp_state := SokobanState.new()
	warp_state.setup(lane)
	check(not warp_state.warp_player(Vector2i(0, 0)), "warp refuses walls")
	check(not warp_state.warp_player(Vector2i(3, 2)), "warp refuses crates")
	check(not warp_state.warp_player(warp_state.player), "warp refuses the same cell")
	check(not warp_state.warp_player(Vector2i(99, 99)), "warp refuses off board cells")
	check(warp_state.warp_player(Vector2i(1, 3)), "warp to open floor")
	check(warp_state.player == Vector2i(1, 3), "warped")
	warp_state.undo()
	check(warp_state.player == Vector2i(2, 2), "warp undo")

	# claw arm walks straight through a whole row of crates
	var pass_state := SokobanState.new()
	pass_state.setup(row)
	check(not pass_state.pass_through_crates(Vector2i.LEFT), "pass needs a crate ahead")
	check(pass_state.pass_through_crates(Vector2i.RIGHT), "pass through a crate row")
	check(pass_state.player == Vector2i(5, 2), "landed past the whole row")
	check(pass_state.boxes.has(Vector2i(3, 2)) and pass_state.boxes.has(Vector2i(4, 2)),
			"crates stay put when passed through")
	check(pass_state.moves == 1, "pass counts a move")
	pass_state.undo()
	check(pass_state.player == Vector2i(2, 2), "pass undo")


func _test_hazards() -> void:
	var rows := [
		"#######",
		"#     #",
		"# @$ .#",
		"#     #",
		"#######",
	]
	var st := SokobanState.new()
	st.setup(LevelData.from_rows(rows))
	# chapter 1 stays clean
	var calm := LevelHazards.new()
	calm.configure(st, 0, true, 7)
	check(not calm.has_any_hazard(), "chapter 1 has no hazards")

	var hz := LevelHazards.new()
	hz.configure(st, 1, true, 2025)
	check(hz.collapse_enabled and not hz.thug_enabled and not hz.thief_enabled,
			"chapter 2 only has rubble")
	var spawned := hz.spawn_rubble()
	check(spawned >= 1 and spawned <= 2, "rubble spawns 1-2 cells (got %d)" % spawned)
	check(st.temp_walls.size() == spawned, "rubble blocks the board")
	var block: Vector2i = st.temp_walls.keys()[0]
	check(st.boxes.has(Vector2i(3, 2)), "crate untouched by rubble")
	st.player = block + Vector2i(-1, 0)
	var blocked := st.try_move(Vector2i(1, 0))
	check(not bool(blocked["moved"]), "rubble blocks movement")
	hz.tick(LevelHazards.COLLAPSE_LIFETIME + 0.2)
	check(st.temp_walls.is_empty(), "rubble expires after 10 seconds")
	check(not st.walls.has(block), "real walls untouched by rubble")

	var thug_st := SokobanState.new()
	thug_st.setup(LevelData.from_rows(rows))
	var thug_hz := LevelHazards.new()
	thug_hz.configure(thug_st, 2, true, 99)
	check(thug_hz.thug_enabled and not thug_hz.thief_enabled, "chapter 3 spawns a thug")
	check(thug_hz.thug != thug_st.player, "thug spawns away from the worker")
	var start_thug := thug_hz.thug
	thug_hz.notify_action()
	check(thug_hz.thug == start_thug, "thug waits for the second action")
	thug_hz.notify_action()
	check(thug_hz.thug != start_thug, "thug steps after two actions")

	var caught_log: Array = []
	thug_hz.caught.connect(func(reason: String): caught_log.append(reason))
	thug_hz.thug = thug_st.player + Vector2i(0, -1)
	thug_hz.notify_action()
	thug_hz.notify_action()
	check(caught_log.has("thug") and thug_hz.failed, "thug catches the worker")

	var thief_st := SokobanState.new()
	thief_st.setup(LevelData.from_rows(rows))
	var thief_hz := LevelHazards.new()
	var thief_log: Array = []
	thief_hz.caught.connect(func(reason: String): thief_log.append(reason))
	thief_hz.configure(thief_st, 3, true, 4242)
	check(thief_hz.thief_enabled and thief_hz.thug_enabled, "chapter 4 has both enemies")
	thief_hz.thug = Vector2i(-1, -1)
	var crate := Vector2i(3, 2)
	check(thief_st.boxes.has(crate), "crate is there before the theft")
	thief_hz.thief = crate + Vector2i(0, -1)
	thief_hz.notify_action()
	thief_hz.notify_action()
	check(thief_hz.thief == crate, "thief reaches the crate")
	check(thief_hz.thief_grab == 1, "thief starts prying")
	thief_hz.notify_action()
	thief_hz.notify_action()
	check(thief_hz.thief_grab == 2, "thief keeps prying for a turn")
	check(thief_log.is_empty(), "crate is still there after one turn")
	thief_hz.notify_action()
	thief_hz.notify_action()
	check(thief_log.has("thief") and thief_hz.failed, "thief steals the crate")
	check(not thief_st.boxes.has(crate), "stolen crate disappeared")

	var reset_st := SokobanState.new()
	reset_st.setup(LevelData.from_rows(rows))
	var reset_hz := LevelHazards.new()
	reset_hz.configure(reset_st, 1, true, 5)
	reset_hz.spawn_rubble()
	reset_st.reset()
	check(reset_st.temp_walls.is_empty(), "level reset clears rubble")


## Walking into the thief destroys it: the worker is armoured, no failure.
func _test_thief_killed() -> void:
	var st := SokobanState.new()
	st.setup(LevelData.from_rows([
		"#######",
		"#     #",
		"# @$. #",
		"#     #",
		"#######",
	]))
	var hz := LevelHazards.new()
	hz.configure(st, 3, true, 606)
	hz.thug = Vector2i(-1, -1)
	var killed: Array = []
	var caught: Array = []
	hz.thief_killed.connect(func(cell: Vector2i): killed.append(cell))
	hz.caught.connect(func(reason: String): caught.append(reason))

	# bump into the thief while it is prying a crate
	hz.thief = Vector2i(2, 2)
	hz.thief_target = Vector2i(2, 2)
	hz.thief_grab = 1
	st.player = Vector2i(2, 2)
	hz.notify_action()
	check(killed.size() == 1 and killed[0] == Vector2i(2, 2), "thief killed on contact")
	check(hz.thief == Vector2i(-1, -1), "killed thief leaves the board")
	check(hz.thief_grab == 0 and hz.thief_target == Vector2i(-1, -1),
			"killed thief releases its target")
	check(not hz.failed and caught.is_empty(), "contact with the thief never fails the run")
	check(st.boxes.has(Vector2i(3, 2)), "crate survives the rescue")
	check(hz.thief_respawn > 0.0 and hz.thief_respawn <= LevelHazards.THIEF_RESPAWN_SECONDS,
			"a killed thief starts its 20 s respawn timer")
	check(hz.status_text().contains(Loc.t("hazard_thief_respawn_in",
			[int(ceil(hz.thief_respawn))])), "hud counts down to the next thief")

	# the replacement arrives after 20 seconds, never sooner
	hz.tick(LevelHazards.THIEF_RESPAWN_SECONDS - 1.0)
	check(hz.thief == Vector2i(-1, -1), "no thief before the timer runs out")
	hz.tick(1.5)
	check(hz.thief.x >= 0, "a new thief spawns 20 s after the kill")
	check(hz.thief_respawn == 0.0, "respawn timer cleared")
	check(not hz.failed, "the replacement does not fail the run")

	# the thief walking into the worker dies as well
	var walk_st := SokobanState.new()
	walk_st.setup(LevelData.from_rows([
		"#######",
		"#     #",
		"#  $@ #",
		"#     #",
		"#######",
	]))
	var walk_hz := LevelHazards.new()
	walk_hz.configure(walk_st, 3, true, 71)
	walk_hz.thug = Vector2i(-1, -1)
	var walk_killed: Array = []
	walk_hz.thief_killed.connect(func(cell: Vector2i): walk_killed.append(cell))
	walk_hz.thief = Vector2i(4, 2) + Vector2i(0, 1)
	var contact := false
	for i in 6:
		walk_hz.notify_action()
		if not walk_killed.is_empty():
			contact = true
	check(walk_killed.size() == 1 and contact, "thief dies walking into the worker")
	check(not walk_hz.failed and walk_hz.thief == Vector2i(-1, -1),
			"walk-in kill spares the worker and the crate")
	check(walk_st.boxes.has(Vector2i(3, 2)), "crate is safe after the walk-in kill")

	# a crate pushed onto a wandering thief does not crush it: the thief takes the loot
	var crush_st := SokobanState.new()
	crush_st.setup(LevelData.from_rows([
		"#######",
		"#     #",
		"# @$ .#",
		"#     #",
		"#######",
	]))
	var crush_hz := LevelHazards.new()
	crush_hz.configure(crush_st, 3, true, 91)
	crush_hz.thug = Vector2i(-1, -1)
	var crush_killed: Array = []
	var crush_stolen: Array = []
	var crush_caught: Array = []
	crush_hz.thief_killed.connect(func(cell: Vector2i): crush_killed.append(cell))
	crush_hz.crate_stolen.connect(func(cell: Vector2i): crush_stolen.append(cell))
	crush_hz.caught.connect(func(reason: String): crush_caught.append(reason))
	crush_hz.thief = Vector2i(4, 2)
	crush_hz.thief_target = Vector2i(-1, -1)
	var shoved := crush_st.try_move(Vector2i.RIGHT)
	check(bool(shoved["pushed"]) and crush_st.boxes.has(Vector2i(4, 2)),
			"crate shoved onto the thief tile")
	crush_hz.notify_action()
	check(crush_killed.is_empty(), "a crate never crushes the thief")
	check(crush_stolen.has(Vector2i(4, 2)), "the thief makes off with the crate")
	check(not crush_st.boxes.has(Vector2i(4, 2)), "the shoved crate is gone")
	check(crush_caught.has("thief") and crush_hz.failed, "losing the crate fails the run")
	check(crush_hz.thief == Vector2i(-1, -1), "the thief escapes with the loot")

	# the thug is still lethal: only the thief is disposable
	var thug_st := SokobanState.new()
	thug_st.setup(LevelData.from_rows([
		"#######",
		"#     #",
		"# @$ .#",
		"#     #",
		"#######",
	]))
	var thug_hz := LevelHazards.new()
	thug_hz.configure(thug_st, 3, true, 5)
	thug_hz.thief = Vector2i(-1, -1)
	var thug_caught: Array = []
	thug_hz.caught.connect(func(reason: String): thug_caught.append(reason))
	thug_hz.thug = Vector2i(2, 2) + Vector2i(0, 1)
	thug_hz.notify_action()
	thug_hz.notify_action()
	check(thug_caught.has("thug") and thug_hz.failed, "thug stays lethal on contact")


## A fresh thief never appears on or next to a crate.
func _test_thief_spawn_distance() -> void:
	var spacing_rows := [
		"##########",
		"#        #",
		"# @$  $. #",
		"#        #",
		"##########",
	]
	var offenders := 0
	var spawns := 0
	for seed in range(1, 41):
		var st := SokobanState.new()
		st.setup(LevelData.from_rows(spacing_rows))
		var hz := LevelHazards.new()
		hz.configure(st, 3, true, seed)
		spawns += 1
		if hz.thief.x < 0:
			offenders += 1
			continue
		if st.boxes.has(hz.thief) or hz._touches_crate(hz.thief):
			offenders += 1
	check(spawns > 0 and offenders == 0,
			"thief spawns away from every crate and its neighbours (%d seeds)" % spawns)

	# a fresh thief keeps that distance after a respawn as well
	var st2 := SokobanState.new()
	st2.setup(LevelData.from_rows(spacing_rows))
	var hz2 := LevelHazards.new()
	hz2.configure(st2, 3, true, 4242)
	hz2.thug = Vector2i(-1, -1)
	var respawn_offenders := 0
	for i in 12:
		hz2.thief = Vector2i(-1, -1)
		hz2.thief_target = Vector2i(-1, -1)
		hz2.thief_grab = 0
		hz2._thief_dead = true
		hz2.thief_respawn = 0.1
		hz2.tick(0.2)
		if hz2.thief.x < 0:
			respawn_offenders += 1
		elif st2.boxes.has(hz2.thief) or hz2._touches_crate(hz2.thief):
			respawn_offenders += 1
	check(respawn_offenders == 0, "respawned thieves keep their distance too")

	# if every free cell touches a crate the margin is relaxed instead of skipping
	var tight := SokobanState.new()
	tight.setup(LevelData.from_rows([
		"######",
		"#@$$.#",
		"#    #",
		"######",
	]))
	var tight_hz := LevelHazards.new()
	tight_hz.configure(tight, 3, true, 3)
	check(tight_hz.thief.x >= 0, "cramped levels still spawn a thief")
	check(not tight.boxes.has(tight_hz.thief), "the fallback never uses a crate cell")


## Moving the crate out of a prying thief's hands wipes its progress.
func _test_pry_interrupted() -> void:
	var st := SokobanState.new()
	st.setup(LevelData.from_rows([
		"##########",
		"#        #",
		"# @$     #",
		"#        #",
		"##########",
	]))
	var hz := LevelHazards.new()
	hz.configure(st, 3, true, 123)
	hz.thug = Vector2i(-1, -1)
	var interrupted: Array = []
	var caught: Array = []
	hz.pry_interrupted.connect(func(cell: Vector2i): interrupted.append(cell))
	hz.caught.connect(func(reason: String): caught.append(reason))
	var crate := Vector2i(3, 2)
	check(st.boxes.has(crate), "crate ready to be pried")
	hz.thief = crate
	hz.thief_target = crate
	hz.thief_grab = 1
	hz.notify_action()
	check(not hz.check_pry(), "prying continues while the crate stays put")
	check(hz.thief_grab == 1 and hz.thief_target == crate, "prying state unchanged")

	# the crane yanks the crate out from under the thief
	check(st.teleport_box(crate, Vector2i(8, 1)), "crane relocates the crate")
	hz.notify_action()
	check(interrupted.has(crate), "moving the crate interrupts prying")
	check(hz.thief_grab == 0 and hz.thief_target == Vector2i(-1, -1),
			"prying progress is wiped")
	check(hz.thief.x >= 0 and hz.thief != crate, "the thief resumes the hunt")
	check(not hz.failed and caught.is_empty(), "an interrupt never fails the run")
	check(hz.status_text().contains(Loc.t("hazard_thief")),
			"hud drops the prying label")
	for i in 6:
		hz.notify_action()
	check(not hz.failed, "no theft while the crate is out of reach")
	check(st.boxes.has(Vector2i(8, 1)), "moved crate is still on the board")

	# pulling the crate away at the last moment buys a whole new prying cycle
	var st2 := SokobanState.new()
	st2.setup(LevelData.from_rows([
		"#######",
		"#     #",
		"# @$  #",
		"#     #",
		"#######",
	]))
	var hz2 := LevelHazards.new()
	hz2.configure(st2, 3, true, 55)
	hz2.thug = Vector2i(-1, -1)
	var crate2 := Vector2i(3, 2)
	hz2.thief = crate2
	hz2.thief_target = crate2
	hz2.thief_grab = 2
	check(st2.teleport_box(crate2, Vector2i(5, 2)), "crate yanked away at the last moment")
	hz2.notify_action()
	check(hz2.thief_grab == 0 and not hz2.failed, "last-moment interrupt resets the clock")
	for i in 6:
		hz2.notify_action()
	check(not hz2.failed and hz2.thief_grab == 2,
			"the thief has to pry from the beginning again")
	hz2.notify_action()
	hz2.notify_action()
	check(hz2.failed, "leaving the crate alone still loses it")

	# nothing to interrupt when the thief is idle
	var idle := LevelHazards.new()
	idle.configure(st, 3, true, 9)
	check(not idle.check_pry(), "no pry to interrupt for an idle thief")


## Hazard toggles authored in the editor survive save, export and reload.
func _test_editor_hazards() -> void:
	var lv := LevelData.from_rows([
		"##########",
		"#        #",
		"# @$  $ .#",
		"#      . #",
		"##########",
	], {"name": "Hazard Level"})
	check(lv.hazard_list().is_empty(), "levels start without hazards")
	lv.set_hazard("collapse", true)
	lv.set_hazard("thug", true)
	lv.set_hazard("bogus", true)
	check(lv.has_hazard("collapse") and lv.has_hazard("thug"), "hazards toggled on")
	check(not lv.has_hazard("bogus"), "unknown hazard ids are ignored")
	check(lv.hazard_list() == ["collapse", "thug"], "hazard list order")
	lv.set_hazard("thug", false)
	check(lv.hazard_list() == ["collapse"], "hazards toggle back off")

	var dict := lv.to_dict()
	check((dict.get("hazards", {}) as Dictionary).has("collapse"), "hazards serialized")
	var restored := LevelData.from_dict(dict)
	check(restored.has_hazard("collapse") and not restored.has_hazard("thug"),
			"hazards survive a dict round trip")
	var copy := restored.duplicate_level()
	check(copy.has_hazard("collapse"), "duplicated levels keep their hazards")
	check(LevelData.from_rows(LevelData.from_rows(["#####", "#@$.#", "#####"]).to_rows())
			.hazard_list().is_empty(), "plain XSB rows carry no hazards")

	# the editor flags drive LevelHazards directly for workshop levels
	var st := SokobanState.new()
	st.setup(LevelData.from_rows([
		"############",
		"#          #",
		"# @$   $  .#",
		"#          #",
		"############",
	]))
	var custom := LevelHazards.new()
	custom.configure(st, -1, false, 4321, {"collapse": true, "thug": false, "thief": true})
	check(custom.collapse_enabled and not custom.thug_enabled and custom.thief_enabled,
			"custom flags pick the hazard mix")
	check(custom.thief.x >= 0, "flagged thief spawns")
	check(custom.thug == Vector2i(-1, -1), "unflagged thug stays off the board")
	check(custom.status_text().contains(Loc.t("hazard_collapse_in", [15])),
			"custom level hud lists the enabled hazards")

	var quiet := LevelHazards.new()
	quiet.configure(st, -1, false, 99, {})
	check(not quiet.has_any_hazard(), "custom levels without flags stay peaceful")
	quiet.configure(st, -1, false, 99, {"collapse": false, "thug": false, "thief": false})
	check(not quiet.has_any_hazard(), "explicitly false flags stay peaceful")

	# reconfiguring the same instance for the campaign must reset the mix
	quiet.configure(st, 1, true, 99)
	check(quiet.collapse_enabled and not quiet.thief_enabled, "campaign chapter 2 mix")
	quiet.configure(st, 0, true, 99)
	check(not quiet.has_any_hazard(), "chapter 1 has no hazards after a reconfigure")

	# validation warns about the two ways hazards hurt a small workshop level
	var cramped := LevelData.from_rows([
		"######",
		"#    #",
		"#@$ .#",
		"######",
	])
	cramped.set_hazard("thug", true)
	cramped.set_hazard("thief", true)
	var codes: Array = []
	for issue in cramped.validate():
		codes.append(str(issue.get("code", "")))
	check(codes.has("err_hazard_cramped"), "cramped hazard level warns")
	check(codes.has("err_hazard_last_box"), "single crate plus thief warns")
	check(cramped.is_valid(), "hazard warnings are not blocking errors")


## A crate landing on the thug flattens it instead of the thug grabbing the worker.
func _test_thug_crushed() -> void:
	var crush_st := SokobanState.new()
	crush_st.setup(LevelData.from_rows([
		"#######",
		"#     #",
		"# @$  #",
		"#     #",
		"#######",
	]))
	var crush_hz := LevelHazards.new()
	crush_hz.configure(crush_st, 2, true, 31)
	check(crush_hz.thug_enabled, "thug level configured")
	var crushed: Array = []
	crush_hz.thug_crushed.connect(func(cell: Vector2i): crushed.append(cell))
	# park the thug right in front of the crate, then shove the crate onto it
	crush_hz.thug = Vector2i(4, 2)
	var push := crush_st.try_move(Vector2i.RIGHT)
	check(bool(push["pushed"]) and crush_st.boxes.has(Vector2i(4, 2)),
			"crate shoved onto the thug tile")
	crush_hz.notify_action()
	check(crushed.size() == 1 and crushed[0] == Vector2i(4, 2), "thug crushed event")
	check(crush_hz.thug == Vector2i(-1, -1), "crushed thug leaves the board")
	check(not crush_hz.failed, "crushed thug cannot catch the worker")
	crush_hz.notify_action()
	crush_hz.notify_action()
	check(crush_hz.thug == Vector2i(-1, -1) and not crush_hz.failed,
			"dead thug never returns")
	check(crush_hz.status_text().contains(Loc.t("hazard_thug_gone")),
			"hud reports the flattened thug")

	# the thug never walks into a crate: it walks around them instead
	var walk_st := SokobanState.new()
	walk_st.setup(LevelData.from_rows([
		"#######",
		"#     #",
		"# $   #",
		"#  @  #",
		"#######",
	]))
	var walk_hz := LevelHazards.new()
	walk_hz.configure(walk_st, 2, true, 8)
	var walk_crushed: Array = []
	walk_hz.thug_crushed.connect(func(cell: Vector2i): walk_crushed.append(cell))
	walk_hz.thug = Vector2i(1, 3)
	var crate_cell := Vector2i(2, 2)
	check(walk_st.boxes.has(crate_cell), "crate sits between thug and worker")
	var visited_crate := false
	for i in 8:
		walk_hz.notify_action()
		if walk_hz.thug == crate_cell:
			visited_crate = true
	check(not visited_crate and walk_crushed.is_empty(), "thug walks around the crate")
	check(walk_hz.thug != Vector2i(-1, -1), "thug survives its own pathing")
	check(walk_hz.failed, "thug still reaches the worker eventually")
	check(walk_hz.status_text().contains(Loc.t("hazard_thug")), "hud still reports a live thug")

	# a thief reaching a crate starts prying instead of being crushed by it
	var thief_st := SokobanState.new()
	thief_st.setup(LevelData.from_rows([
		"#######",
		"#     #",
		"# $  @#",
		"#     #",
		"#######",
	]))
	var thief_hz := LevelHazards.new()
	thief_hz.configure(thief_st, 3, true, 77)
	thief_hz.thug = Vector2i(-1, -1)
	thief_hz.thief = Vector2i(3, 2)
	thief_hz.notify_action()
	thief_hz.notify_action()
	check(thief_hz.thief == Vector2i(2, 2) and thief_hz.thief_grab == 1,
			"thief keeps prying a crate instead of dying")


## The whole campaign is playable from a clean save.
func _test_unlocks() -> void:
	var catalog := LevelCatalog.new()
	catalog.load_builtin()
	var locked := 0
	var total := 0
	for chapter in catalog.chapters:
		for level in chapter["levels"]:
			total += 1
			if not catalog.is_level_unlocked(level):
				locked += 1
	check(total > 0 and locked == 0, "every builtin level starts unlocked (%d levels)" % total)
	for i in catalog.chapters.size():
		check(catalog.is_chapter_unlocked(i), "chapter %d unlocked" % i)
	check(not catalog.is_chapter_unlocked(catalog.chapters.size()),
			"unknown chapter index stays locked")
	var last_level: LevelData = catalog.chapters.back()["levels"].back()
	check(catalog.level_lock_reason(last_level).is_empty(), "no lock reason when unlocked")


## The starter gift tops every robot part up to Lv1 exactly once.
func _test_starter_gift() -> void:
	var upgrades_before: Dictionary = SaveManager.upgrades.duplicate(true)
	var flag_before := bool(SaveManager.data.get("starter_gift", false))
	SaveManager.upgrades = {}
	SaveManager.data["starter_gift"] = false
	check(not SaveManager.has_starter_gift(), "gift starts unclaimed")
	check(SaveManager.grant_starter_gift(), "gift upgrades something")
	for part_id in RobotUpgrades.ORDER:
		check(SaveManager.upgrade_level(str(part_id)) == 1, "gift sets %s to Lv1" % part_id)
	check(SaveManager.has_starter_gift(), "gift marked as claimed")
	check(not SaveManager.grant_starter_gift(), "gift is not granted twice")
	SaveManager.data["starter_gift"] = false
	SaveManager.upgrades = {"arm": 2, "hook": 3}
	check(SaveManager.grant_starter_gift(), "gift tops up the remaining parts")
	check(SaveManager.upgrade_level("arm") == 2 and SaveManager.upgrade_level("hook") == 3,
			"bought levels are never reduced")
	check(SaveManager.upgrade_level("head") == 1, "gift fills the missing parts")
	SaveManager.upgrades = upgrades_before
	SaveManager.data["starter_gift"] = flag_before


func _test_board_sprites() -> void:
	# two crates in a row, three crates, vertical line, and a crate leaving a goal
	_chain_scenario("2 crates", [
		"##########",
		"#        #",
		"# @$$  . #",
		"##########",
	], Vector2i.RIGHT, 3, 2)
	_chain_scenario("3 crates", [
		"##########",
		"#        #",
		"# @$$$.  #",
		"##########",
	], Vector2i.RIGHT, 3, 2)
	_chain_scenario("vertical crates", [
		"#######",
		"#     #",
		"#  .  #",
		"#  $  #",
		"#  $  #",
		"#  @  #",
		"#######",
	], Vector2i.UP, 2, 2)
	_chain_scenario("crate leaves goal", [
		"##########",
		"#        #",
		"# @$*.   #",
		"##########",
	], Vector2i.RIGHT, 2, 1)
	# a marked crate pushed off its goal must go back to the plain texture
	_chain_scenario("goal crate pushed off", [
		"#########",
		"#       #",
		"#@*    .#",
		"#########",
	], Vector2i.RIGHT, 1, 1)


func _chain_scenario(tag: String, rows: Array, dir: Vector2i, chain: int, steps: int) -> void:
	var lv := LevelData.from_rows(rows)
	var st := SokobanState.new()
	st.setup(lv)
	var tree := Engine.get_main_loop() as SceneTree
	var host := Node2D.new()
	tree.root.add_child(host)
	var board := BoardView.new()
	host.add_child(board)
	board.setup(lv, st)
	check(_sprites_match_state(board, st), "%s: board starts aligned" % tag)

	for step in steps:
		var result := st.try_move(dir, chain)
		if not bool(result["moved"]):
			print("  chain scenario '%s' step %d blocked, player=%s boxes=%s chain=%d"
					% [tag, step, st.player, st.boxes.keys(), chain])
		check(bool(result["moved"]) and bool(result["pushed"]), "%s: push %d moved" % [tag, step])
		board.animate_move(result)
		check(_sprites_match_state(board, st), "%s: push %d keeps sprites aligned" % [tag, step])
		check(_sprite_cells(board) == _cell_set(st.boxes), "%s: push %d sprite cells" % [tag, step])
		check(_no_orphan_crate_graphics(board), "%s: push %d leaves no stuck graphic" % [tag, step])
		check(_textures_follow_goals(board, lv), "%s: push %d crate textures" % [tag, step])

	# undo every push, then redo them all
	while not (st.get("_history") as Array).is_empty():
		st.undo()
		board.animate_undo(_last_undone_record(st))
		check(_sprites_match_state(board, st), "%s: undo keeps sprites aligned" % tag)
		check(_textures_follow_goals(board, lv), "%s: undo crate textures" % tag)
	while not (st.get("_redo") as Array).is_empty():
		st.redo()
		board.animate_redo(_last_redone_record(st))
		check(_sprites_match_state(board, st), "%s: redo keeps sprites aligned" % tag)
		check(_textures_follow_goals(board, lv), "%s: redo crate textures" % tag)

	host.queue_free()


## No crate graphic may linger in the scene without being tracked by the registry:
## that is exactly what shows up as a "stuck" crate texture.
func _no_orphan_crate_graphics(board: BoardView) -> bool:
	var sprites: Dictionary = board.get("_box_sprites")
	var crate_children := 0
	for child in board.get_children():
		if child is Sprite2D and (child as Sprite2D).z_index == 5:
			crate_children += 1
	return crate_children == sprites.size()


func _textures_follow_goals(board: BoardView, level: LevelData) -> bool:
	var sprites: Dictionary = board.get("_box_sprites")
	for cell in sprites.keys():
		var spr: Sprite2D = sprites[cell]
		var want := UIKit.art("box_goal") if level.goals.has(cell) else UIKit.art("box")
		if spr == null or spr.texture != want:
			return false
	return true


func _sprites_match_state(board: BoardView, st: SokobanState) -> bool:
	var sprites: Dictionary = board.get("_box_sprites")
	var shadows: Dictionary = board.get("_box_shadows")
	if sprites.size() != st.boxes.size() or shadows.size() != st.boxes.size():
		return false
	for cell in st.boxes.keys():
		if not sprites.has(cell) or not shadows.has(cell):
			return false
		if sprites[cell] == null or not is_instance_valid(sprites[cell]):
			return false
	return true


func _sprite_cells(board: BoardView) -> Array:
	var cells: Array = []
	for cell in (board.get("_box_sprites") as Dictionary).keys():
		cells.append("%d,%d" % [cell.x, cell.y])
	cells.sort()
	return cells


func _cell_set(dict: Dictionary) -> Array:
	var cells: Array = []
	for cell in dict.keys():
		cells.append("%d,%d" % [cell.x, cell.y])
	cells.sort()
	return cells


func _last_undone_record(st: SokobanState) -> Dictionary:
	var redo: Array = st.get("_redo")
	return {} if redo.is_empty() else redo.back()


func _last_redone_record(st: SokobanState) -> Dictionary:
	var history: Array = st.get("_history")
	return {} if history.is_empty() else history.back()


func _test_wallet() -> void:
	var coins_before := SaveManager.wallet_coins()
	var inv_before: Dictionary = SaveManager.inventory.duplicate(true)
	var upgrades_before: Dictionary = SaveManager.upgrades.duplicate(true)
	var progress_before: Dictionary = SaveManager.progress.duplicate(true)
	var stats_before: Dictionary = SaveManager.stats.duplicate(true)
	SaveManager.coins = 0
	SaveManager.inventory = {}
	SaveManager.add_coins(120)
	check(SaveManager.wallet_coins() == 120, "coins added")
	check(SaveManager.buy_item("crane"), "buy crane")
	check(SaveManager.wallet_coins() == 70, "crane costs 50")
	check(SaveManager.item_count("crane") == 1, "crane in inventory")
	check(not SaveManager.buy_item("contract"), "cannot afford contract")
	check(SaveManager.wallet_coins() == 70, "failed buy keeps coins")
	check(SaveManager.consume_item("crane"), "consume crane")
	check(SaveManager.item_count("crane") == 0, "crane used up")
	check(not SaveManager.consume_item("crane"), "cannot consume what is gone")
	# every clear pays coins by the stars earned (base rate: no core multiplier)
	SaveManager.progress = {}
	SaveManager.stats = SaveManager._default_stats()
	SaveManager.upgrades = {}
	var first := SaveManager.record_result("selftest_level", 10, 5, 1, 12.0, true)
	check(int(first.get("coins_earned", 0)) == 15, "1 star clear pays 15 coins")
	var higher := SaveManager.record_result("selftest_level", 9, 4, 3, 11.0, true)
	check(int(higher.get("coins_earned", 0)) == 45, "3 star clear pays 45 coins")
	var repeat := SaveManager.record_result("selftest_level", 9, 4, 3, 11.0, true)
	check(int(repeat.get("coins_earned", 0)) == 45, "replaying still pays 45 coins")
	var custom := SaveManager.record_result("selftest_custom", 9, 4, 3, 11.0, false)
	check(int(custom.get("coins_earned", 0)) == 0, "custom levels never pay")
	SaveManager.upgrades = {"core": 3}
	var boosted := SaveManager.record_result("selftest_boost", 9, 4, 3, 11.0, true)
	check(int(boosted.get("coins_earned", 0)) == 90, "overload core doubles clear coins")
	SaveManager.upgrades = upgrades_before
	SaveManager.progress = progress_before
	SaveManager.stats = stats_before
	SaveManager.coins = coins_before
	SaveManager.inventory = inv_before
	check(SaveManager.wallet_coins() == coins_before, "wallet restored")


func _test_solver_all() -> void:
	var catalog := LevelCatalog.new()
	catalog.load_builtin()
	var solved := 0
	var mismatched := 0
	var unsolved: Array = []
	for chapter in catalog.chapters:
		for level in chapter["levels"]:
			var solver := SokobanSolver.new()
			if not solver.setup_from_level(level):
				unsolved.append(level.id + " (setup)")
				continue
			var t0 := Time.get_ticks_msec()
			var result := solver.solve(45.0, 800000)
			var elapsed := Time.get_ticks_msec() - t0
			if elapsed > 500:
				print("  slow solve %s: %d ms, nodes %d" % [level.id, elapsed,
						int(result.get("nodes", 0))])
			if result.get("solvable") == true:
				solved += 1
				if int(result["pushes"]) != level.par_pushes:
					mismatched += 1
					print("  par mismatch %s: %d vs %d" % [level.id, int(result["pushes"]),
							level.par_pushes])
				if not _validate_path(level, result.get("path", [])):
					check(false, "solution path valid %s" % level.id)
			else:
				unsolved.append(level.id + ":" + str(result.get("reason", "?")))
	check(solved == catalog.total_levels(),
			"all levels solvable in GDScript (%d/%d, %s)" % [solved, catalog.total_levels(),
			str(unsolved)])
	check(mismatched == 0, "GDScript solver matches par (%d mismatches)" % mismatched)


func _test_hints() -> void:
	var catalog := LevelCatalog.new()
	catalog.load_builtin()
	var failed: Array = []
	var worst := 0
	for chapter in catalog.chapters:
		for level in chapter["levels"]:
			var solver := SokobanSolver.new()
			if not solver.setup_from_level(level):
				failed.append(level.id)
				continue
			var t0 := Time.get_ticks_msec()
			var result := solver.solve(2.0, 80000, 2)
			var elapsed := Time.get_ticks_msec() - t0
			worst = maxi(worst, elapsed)
			if result.get("solvable") != true:
				failed.append(level.id + ":" + str(result.get("reason", "?")))
			elif not _validate_path(level, result.get("path", [])):
				failed.append(level.id + ":badpath")
			if elapsed > 900:
				print("  slow hint %s: %d ms, nodes %d" % [level.id, elapsed,
						int(result.get("nodes", 0))])
	check(failed.is_empty(), "hint solver solves all levels (failed: %s)" % str(failed))
	print("  worst hint solve: %d ms" % worst)

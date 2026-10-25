extends Node
## Global navigation, campaign catalog, session state and input bindings.

signal screen_changed(screen_id: String)

const VERSION := "1.0.0"
const SCREEN_PATHS := {
	"menu": "res://scripts/screens/main_menu.gd",
	"level_select": "res://scripts/screens/level_select.gd",
	"game": "res://scripts/screens/game_screen.gd",
	"editor": "res://scripts/screens/editor_screen.gd",
	"settings": "res://scripts/screens/settings_screen.gd",
	"shop": "res://scripts/screens/shop_screen.gd",
	"robot": "res://scripts/screens/robot_screen.gd",
}

var app: Node = null
var catalog: LevelCatalog
var session: Dictionary = {}
var editor_draft: Dictionary = {}
var screen_id := ""
var has_app := false


func _ready() -> void:
	_setup_input_map()
	catalog = LevelCatalog.new()
	if not catalog.load_builtin():
		push_error("Failed to load campaign: %s" % catalog.load_error)
	apply_window_settings()
	SaveManager.settings_changed.connect(_on_settings_changed)


func attach(app_node: Node) -> void:
	app = app_node
	has_app = true


# --------------------------------------------------------------------------- #
# Navigation
# --------------------------------------------------------------------------- #
func goto(target: String, params: Dictionary = {}) -> void:
	if app == null:
		push_warning("Game.goto called before app attached")
		return
	app.change_screen(target, params)


func continue_game() -> void:
	var level := catalog.resume_level()
	if level == null:
		start_campaign("")
		return
	start_campaign(level.id)


func start_campaign(level_id: String) -> void:
	var level := catalog.get_level(level_id)
	if level == null:
		level = catalog.first_playable_level()
	if level == null:
		goto("level_select")
		return
	session = {"level": level, "mode": "campaign", "return_to": {}}
	SaveManager.set_last_level(level.id)
	goto("game")


func start_custom(level: LevelData) -> void:
	if level == null:
		goto("level_select", {"chapter": "custom"})
		return
	session = {"level": level, "mode": "custom",
			"return_to": {"screen": "level_select", "params": {"chapter": "custom"}}}
	goto("game")


func start_playtest(level: LevelData, draft: Dictionary) -> void:
	editor_draft = draft.duplicate(true)
	session = {"level": level, "mode": "playtest",
			"return_to": {"screen": "editor", "params": {"draft": editor_draft}}}
	goto("game")


func start_editor(level: LevelData = null) -> void:
	var params := {}
	if level != null:
		params["draft"] = {"level": level, "level_id": level.id}
	goto("editor", params)


func return_from_game() -> void:
	var target: Variant = session.get("return_to", {})
	if target is Dictionary and not target.is_empty():
		goto(str(target.get("screen", "menu")), target.get("params", {}))
	else:
		goto("menu")


func next_after(level: LevelData) -> LevelData:
	if level == null or not level.builtin:
		return null
	return catalog.next_level(level)


func go_next_level(level: LevelData) -> void:
	var next := next_after(level)
	if next == null:
		goto("level_select", {"chapter": level.chapter_index if level != null else 0})
		return
	start_campaign(next.id)


func current_level() -> LevelData:
	var level: Variant = session.get("level")
	if level is LevelData:
		return level
	return null


func current_mode() -> String:
	return str(session.get("mode", "campaign"))


# --------------------------------------------------------------------------- #
# Window
# --------------------------------------------------------------------------- #
func _on_settings_changed() -> void:
	apply_window_settings()


func apply_window_settings() -> void:
	var want_fullscreen := bool(SaveManager.get_setting("fullscreen", false))
	var mode := DisplayServer.window_get_mode()
	if want_fullscreen and mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not want_fullscreen and mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


# --------------------------------------------------------------------------- #
# Input bindings
# --------------------------------------------------------------------------- #
func _setup_input_map() -> void:
	_action("move_up", 0.3)
	_action("move_down", 0.3)
	_action("move_left", 0.3)
	_action("move_right", 0.3)
	_action("restart", 0.2)
	_action("pause", 0.2)

	_key("move_up", KEY_W)
	_key("move_up", KEY_UP)
	_joy_button("move_up", JOY_BUTTON_DPAD_UP)
	_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)

	_key("move_down", KEY_S)
	_key("move_down", KEY_DOWN)
	_joy_button("move_down", JOY_BUTTON_DPAD_DOWN)
	_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)

	_key("move_left", KEY_A)
	_key("move_left", KEY_LEFT)
	_joy_button("move_left", JOY_BUTTON_DPAD_LEFT)
	_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)

	_key("move_right", KEY_D)
	_key("move_right", KEY_RIGHT)
	_joy_button("move_right", JOY_BUTTON_DPAD_RIGHT)
	_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)

	_key("restart", KEY_R)
	_joy_button("restart", JOY_BUTTON_LEFT_SHOULDER)
	_key("pause", KEY_ESCAPE)
	_joy_button("pause", JOY_BUTTON_START)


func _action(action_name: String, deadzone: float) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name, deadzone)
	else:
		InputMap.action_erase_events(action_name)


func _key(action_name: String, keycode: Key, ctrl := false, shift := false) -> void:
	var ev := InputEventKey.new()
	if ctrl:
		ev.keycode = keycode
	else:
		ev.physical_keycode = keycode
	ev.ctrl_pressed = ctrl
	ev.shift_pressed = shift
	InputMap.action_add_event(action_name, ev)


func _joy_button(action_name: String, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action_name, ev)


func _joy_axis(action_name: String, axis: JoyAxis, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action_name, ev)

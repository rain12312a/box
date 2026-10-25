class_name LevelData
extends RefCounted
## Parsed Sokoban level. Uses XSB characters for storage:
##   # wall   . goal   $ crate   @ player   * crate on goal   + player on goal

const TILE_FLOOR := 0
const TILE_WALL := 1
const TILE_GOAL := 2

var id := ""
var name_zh := ""
var name_en := ""
var tip_zh := ""
var tip_en := ""
var author := ""
var chapter_id := ""
var chapter_index := -1
var index := -1
var par_moves := 0
var par_pushes := 0
var builtin := true
## Author-chosen hazards for custom levels: {"collapse": bool, "thug": bool, "thief": bool}
var hazards: Dictionary = {}

var width := 0
var height := 0
var walls: Dictionary = {}
var goals: Dictionary = {}
var boxes: Dictionary = {}
var player := Vector2i(-1, -1)
var player_found := false


# --------------------------------------------------------------------------- #
# Construction
# --------------------------------------------------------------------------- #
static func from_rows(rows: Array, meta: Dictionary = {}) -> LevelData:
	var level := LevelData.new()
	level._parse_rows(rows)
	level.apply_meta(meta)
	return level


static func from_dict(dict: Dictionary) -> LevelData:
	var rows: Array = []
	var raw: Variant = dict.get("rows", [])
	if raw is Array:
		for r in raw:
			rows.append(str(r))
	elif raw is String:
		rows = str(raw).split("\n")
	var level := LevelData.from_rows(rows)
	level.apply_meta(dict)
	level.builtin = bool(dict.get("builtin", false))
	return level


func apply_meta(meta: Dictionary) -> void:
	id = str(meta.get("id", id))
	name_zh = str(meta.get("name_zh", meta.get("name", name_zh)))
	name_en = str(meta.get("name_en", meta.get("name", name_en)))
	tip_zh = str(meta.get("tip_zh", meta.get("tip", tip_zh)))
	tip_en = str(meta.get("tip_en", meta.get("tip", tip_en)))
	author = str(meta.get("author", author))
	chapter_id = str(meta.get("chapter_id", chapter_id))
	chapter_index = int(meta.get("chapter_index", chapter_index))
	index = int(meta.get("index", index))
	par_moves = int(meta.get("par_moves", par_moves))
	par_pushes = int(meta.get("par_pushes", par_pushes))
	if meta.has("builtin"):
		builtin = bool(meta["builtin"])
	hazards.clear()
	var raw_hazards: Variant = meta.get("hazards", {})
	if raw_hazards is Dictionary:
		for hazard_id in HAZARD_IDS:
			if bool((raw_hazards as Dictionary).get(hazard_id, false)):
				hazards[str(hazard_id)] = true


func _parse_rows(rows: Array) -> void:
	walls.clear()
	goals.clear()
	boxes.clear()
	player_found = false
	player = Vector2i(-1, -1)
	width = 0
	for r in rows:
		width = maxi(width, str(r).length())
	height = rows.size()
	for y in height:
		var row := str(rows[y])
		for x in width:
			var ch := " "
			if x < row.length():
				ch = row[x]
			var pos := Vector2i(x, y)
			match ch:
				"#":
					walls[pos] = true
				".":
					goals[pos] = true
				"$":
					boxes[pos] = true
				"*":
					boxes[pos] = true
					goals[pos] = true
				"@":
					player = pos
					player_found = true
				"+":
					player = pos
					player_found = true
					goals[pos] = true


func duplicate_level() -> LevelData:
	return LevelData.from_dict(to_dict())


# --------------------------------------------------------------------------- #
# Hazards (collapse / thug / thief), only meaningful for custom levels
# --------------------------------------------------------------------------- #
const HAZARD_IDS := ["collapse", "thug", "thief"]


func has_hazard(hazard_id: String) -> bool:
	return bool(hazards.get(hazard_id, false))


func set_hazard(hazard_id: String, enabled: bool) -> void:
	if not HAZARD_IDS.has(hazard_id):
		return
	if enabled:
		hazards[hazard_id] = true
	else:
		hazards.erase(hazard_id)


func hazard_list() -> Array:
	var out: Array = []
	for hazard_id in HAZARD_IDS:
		if has_hazard(str(hazard_id)):
			out.append(str(hazard_id))
	return out


func copy_hazards_from(other: LevelData) -> void:
	hazards = other.hazards.duplicate(true) if other != null else {}


# --------------------------------------------------------------------------- #
# Serialization
# --------------------------------------------------------------------------- #
func to_dict() -> Dictionary:
	return {
		"id": id,
		"name_zh": name_zh,
		"name_en": name_en,
		"tip_zh": tip_zh,
		"tip_en": tip_en,
		"author": author,
		"chapter_id": chapter_id,
		"par_moves": par_moves,
		"par_pushes": par_pushes,
		"builtin": builtin,
		"hazards": hazards.duplicate(true),
		"rows": to_rows(),
	}


func to_rows() -> Array:
	var rows: Array = []
	for y in height:
		var row := ""
		for x in width:
			var pos := Vector2i(x, y)
			if walls.has(pos):
				row += "#"
			elif player == pos:
				row += "+" if goals.has(pos) else "@"
			elif boxes.has(pos):
				row += "*" if goals.has(pos) else "$"
			elif goals.has(pos):
				row += "."
			else:
				row += " "
		rows.append(row)
	return rows


func to_xsb() -> String:
	return "\n".join(to_rows())


# --------------------------------------------------------------------------- #
# Queries
# --------------------------------------------------------------------------- #
func is_wall(pos: Vector2i) -> bool:
	return walls.has(pos)


func has_box(pos: Vector2i) -> bool:
	return boxes.has(pos)


func has_goal(pos: Vector2i) -> bool:
	return goals.has(pos)


func box_count() -> int:
	return boxes.size()


func goal_count() -> int:
	return goals.size()


func boxes_on_goals() -> int:
	var n := 0
	for pos in boxes.keys():
		if goals.has(pos):
			n += 1
	return n


func in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < width and pos.y < height


func display_name() -> String:
	if Loc.language == "zh" and not name_zh.is_empty():
		return name_zh
	if not name_en.is_empty():
		return name_en
	if not name_zh.is_empty():
		return name_zh
	if not id.is_empty():
		return id
	return Loc.t("editor_untitled")


func short_name() -> String:
	var n := display_name()
	if n.length() > 12:
		return n.substr(0, 11) + "…"
	return n


func tip_text() -> String:
	if Loc.language == "zh":
		return tip_zh if not tip_zh.is_empty() else tip_en
	return tip_en if not tip_en.is_empty() else tip_zh


func star_rating(pushes: int) -> int:
	if par_pushes <= 0:
		return 3
	if pushes <= par_pushes:
		return 3
	if pushes <= int(ceil(par_pushes * 1.3)) + 2:
		return 2
	return 1


func goal_positions() -> Array:
	return goals.keys()


func box_positions() -> Array:
	return boxes.keys()


# --------------------------------------------------------------------------- #
# Validation
# --------------------------------------------------------------------------- #
func validate() -> Array:
	var issues: Array = []
	if width < 4 or height < 4:
		issues.append({"code": "err_too_small", "level": "error"})
	if not player_found or player.x < 0:
		issues.append({"code": "err_no_player", "level": "error"})
	if boxes.is_empty():
		issues.append({"code": "err_no_box", "level": "error"})
	if goals.is_empty():
		issues.append({"code": "err_no_goal", "level": "error"})
	if boxes.size() != goals.size():
		issues.append({"code": "err_mismatch", "level": "error",
				"args": [boxes.size(), goals.size()]})
	if player_found and walls.has(player):
		issues.append({"code": "err_player_wall", "level": "error"})
	for pos in boxes.keys():
		if walls.has(pos):
			issues.append({"code": "err_box_wall", "level": "error"})
			break
	# static corner deadlock: a crate squeezed into a corner is gone forever
	for pos in boxes.keys():
		if goals.has(pos):
			continue
		var up := walls.has(pos + Vector2i.UP)
		var down := walls.has(pos + Vector2i.DOWN)
		var left := walls.has(pos + Vector2i.LEFT)
		var right := walls.has(pos + Vector2i.RIGHT)
		if (up or down) and (left or right):
			issues.append({"code": "err_dead_box", "level": "warning"})
			break
	# open border
	var border_open := false
	for x in width:
		if not walls.has(Vector2i(x, 0)) or not walls.has(Vector2i(x, height - 1)):
			border_open = true
			break
	if not border_open:
		for y in height:
			if not walls.has(Vector2i(0, y)) or not walls.has(Vector2i(width - 1, y)):
				border_open = true
				break
	if border_open:
		issues.append({"code": "err_open_edge", "level": "warning"})
	# hazards need breathing room: the thug/thief spawn away from the worker
	var free_cells := width * height - walls.size() - boxes.size()
	if (has_hazard("thug") or has_hazard("thief")) and free_cells < 8:
		issues.append({"code": "err_hazard_cramped", "level": "warning"})
	if has_hazard("thief") and boxes.size() <= 1:
		issues.append({"code": "err_hazard_last_box", "level": "warning"})
	return issues


func is_valid() -> bool:
	for issue in validate():
		if str(issue.get("level", "error")) == "error":
			return false
	return true


func error_texts() -> Array:
	var texts: Array = []
	for issue in validate():
		if str(issue.get("level", "error")) != "error":
			continue
		var args: Array = issue.get("args", [])
		texts.append(Loc.t(str(issue.get("code", "")), args))
	return texts

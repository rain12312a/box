class_name LevelCatalog
extends RefCounted
## Loads the bundled campaign and answers progression questions.

## The campaign ships fully unlocked: every chapter and level is playable from the start.
const ALL_LEVELS_UNLOCKED := true

var chapters: Array = []
var levels_by_id: Dictionary = {}
var load_error := ""


func load_builtin(path := "res://data/levels.json") -> bool:
	chapters.clear()
	levels_by_id.clear()
	load_error = ""
	if not FileAccess.file_exists(path):
		load_error = "missing %s" % path
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		load_error = "cannot open %s" % path
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		load_error = "invalid json"
		return false
	var raw_chapters: Array = parsed.get("chapters", [])
	var ci := 0
	for raw_chapter in raw_chapters:
		if not (raw_chapter is Dictionary):
			continue
		var chapter: Dictionary = {
			"id": str(raw_chapter.get("id", "chapter_%d" % (ci + 1))),
			"name_zh": str(raw_chapter.get("name_zh", "")),
			"name_en": str(raw_chapter.get("name_en", "")),
			"desc_zh": str(raw_chapter.get("desc_zh", "")),
			"desc_en": str(raw_chapter.get("desc_en", "")),
			"index": ci,
			"levels": [],
		}
		var raw_levels: Array = raw_chapter.get("levels", [])
		var li := 0
		for raw_level in raw_levels:
			if not (raw_level is Dictionary):
				continue
			var level := LevelData.from_dict(raw_level)
			level.builtin = true
			level.chapter_id = chapter["id"]
			level.chapter_index = ci
			level.index = li
			(chapter["levels"] as Array).append(level)
			levels_by_id[level.id] = level
			li += 1
		chapters.append(chapter)
		ci += 1
	return not chapters.is_empty()


func total_levels() -> int:
	var n := 0
	for chapter in chapters:
		n += (chapter["levels"] as Array).size()
	return n


func max_stars() -> int:
	return total_levels() * 3


func get_level(level_id: String) -> LevelData:
	return levels_by_id.get(level_id)


func get_chapter(index: int) -> Dictionary:
	if index < 0 or index >= chapters.size():
		return {}
	return chapters[index]


func chapter_index_of(level: LevelData) -> int:
	if level == null:
		return -1
	return level.chapter_index


func chapter_completed_count(index: int) -> int:
	var chapter := get_chapter(index)
	if chapter.is_empty():
		return 0
	var ids: Array = []
	for level in chapter["levels"]:
		ids.append(level.id)
	return SaveManager.count_completed(ids)


func is_chapter_unlocked(index: int) -> bool:
	if index < 0 or index >= chapters.size():
		return false
	if ALL_LEVELS_UNLOCKED:
		return true
	if index == 0:
		return true
	var prev := get_chapter(index - 1)
	var levels: Array = prev["levels"]
	if levels.is_empty():
		return false
	var required := int(ceil(levels.size() * 0.75))
	return chapter_completed_count(index - 1) >= required


func is_level_unlocked(level: LevelData) -> bool:
	if level == null:
		return false
	if ALL_LEVELS_UNLOCKED:
		return true
	if not level.builtin:
		return true
	if not is_chapter_unlocked(level.chapter_index):
		return false
	if level.index <= 0:
		return true
	var chapter := get_chapter(level.chapter_index)
	var ids: Array = chapter["levels"]
	if level.index >= ids.size():
		return false
	return SaveManager.is_completed((ids[level.index - 1] as LevelData).id)


func level_lock_reason(level: LevelData) -> String:
	if level == null or is_level_unlocked(level):
		return ""
	if not is_chapter_unlocked(level.chapter_index):
		return Loc.t("levels_locked_chapter")
	return Loc.t("levels_locked_prev")


func next_level(level: LevelData) -> LevelData:
	if level == null or not level.builtin:
		return null
	var chapter := get_chapter(level.chapter_index)
	var levels: Array = chapter.get("levels", [])
	if level.index + 1 < levels.size():
		return levels[level.index + 1]
	var next_index := level.chapter_index + 1
	if next_index < chapters.size():
		var next_chapter := get_chapter(next_index)
		var next_levels: Array = next_chapter.get("levels", [])
		if not next_levels.is_empty():
			return next_levels[0]
	return null


func first_playable_level() -> LevelData:
	if chapters.is_empty():
		return null
	return (chapters[0]["levels"] as Array)[0]


func resume_level() -> LevelData:
	var last_id := SaveManager.get_last_level()
	var last := get_level(last_id)
	if last != null and is_level_unlocked(last):
		return last
	# first incomplete unlocked level in order
	for chapter in chapters:
		for level in chapter["levels"]:
			if not SaveManager.is_completed(level.id) and is_level_unlocked(level):
				return level
	# everything is done: return the last level
	var last_chapter: Dictionary = chapters[chapters.size() - 1]
	var levels: Array = last_chapter["levels"]
	return levels[levels.size() - 1] if not levels.is_empty() else null


func first_level_of_chapter(index: int) -> LevelData:
	var chapter := get_chapter(index)
	if chapter.is_empty():
		return null
	var levels: Array = chapter["levels"]
	return levels[0] if not levels.is_empty() else null


func custom_level_from_dict(dict: Dictionary) -> LevelData:
	var level := LevelData.from_dict(dict)
	level.builtin = false
	level.chapter_id = "custom"
	level.chapter_index = chapters.size()
	return level


func custom_levels() -> Array:
	var result: Array = []
	for dict in SaveManager.get_custom_levels():
		if dict is Dictionary:
			result.append(custom_level_from_dict(dict))
	return result

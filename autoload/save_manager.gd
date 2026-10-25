extends Node
## Persistent save data: settings, campaign progress, statistics and workshop levels.
## The file lives in user:// and is written through a temp file so a crash cannot
## leave a half written save behind.

signal settings_changed
signal progress_changed
signal custom_levels_changed
signal wallet_changed

const SAVE_PATH := "user://save.json"
const BACKUP_PATH := "user://save.backup.json"
const TEMP_PATH := "user://save.tmp"
const SAVE_VERSION := 1

const DEFAULT_SETTINGS := {
	"master_volume": 0.9,
	"music_volume": 0.55,
	"sfx_volume": 0.85,
	"language": "",
	"fullscreen": false,
	"screen_shake": true,
	"confirm_restart": true,
	"show_tips": true,
}

var data: Dictionary = {}
var settings: Dictionary = {}
var progress: Dictionary = {}
var stats: Dictionary = {}
var custom_levels: Array = []
var coins := 0
var inventory: Dictionary = {}
var upgrades: Dictionary = {}

var _save_timer: Timer
var _dirty := false
var capture_mode := false
## True for one boot after the starter gift was handed out, so the menu can announce it.
var starter_gift_announce := false


func _ready() -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.2
	_save_timer.timeout.connect(save_game)
	add_child(_save_timer)
	load_game()


# --------------------------------------------------------------------------- #
# Loading / saving
# --------------------------------------------------------------------------- #
func _default_stats() -> Dictionary:
	return {"total_moves": 0, "total_pushes": 0, "play_seconds": 0.0, "levels_completed": 0,
			"coins_earned": 0}


func _default_data() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"settings": DEFAULT_SETTINGS.duplicate(true),
		"progress": {},
		"stats": _default_stats(),
		"custom_levels": [],
		"last_level": "",
		"coins": 0,
		"items": {},
		"upgrades": {},
		"starter_gift": false,
		"created_at": Time.get_datetime_string_from_system(),
	}


func load_game() -> void:
	data = _default_data()
	var loaded: Variant = _read_json(SAVE_PATH)
	if loaded == null:
		loaded = _read_json(BACKUP_PATH)
	if loaded is Dictionary:
		_merge_loaded(loaded)
	settings = data["settings"]
	progress = data["progress"]
	stats = data["stats"]
	custom_levels = data["custom_levels"]
	coins = maxi(int(data.get("coins", 0)), 0)
	inventory = {}
	var raw_items: Variant = data.get("items", {})
	if raw_items is Dictionary:
		for key in raw_items.keys():
			if ItemCatalog.has_item(str(key)):
				inventory[str(key)] = maxi(int(raw_items[key]), 0)
	upgrades = {}
	var raw_upgrades: Variant = data.get("upgrades", {})
	if raw_upgrades is Dictionary:
		for key in raw_upgrades.keys():
			if RobotUpgrades.has_part(str(key)):
				upgrades[str(key)] = clampi(int(raw_upgrades[key]), 0,
						RobotUpgrades.MAX_LEVEL)
	if not settings.has("language") or settings["language"] == null:
		settings["language"] = ""
	starter_gift_announce = false
	if not bool(data.get("starter_gift", false)):
		starter_gift_announce = grant_starter_gift()


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parsed


func _merge_loaded(loaded: Dictionary) -> void:
	var base := _default_data()
	for key in base.keys():
		if loaded.has(key):
			base[key] = loaded[key]
	# merge settings so new options appear for old saves
	var merged_settings: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	if loaded.get("settings") is Dictionary:
		for k in loaded["settings"].keys():
			merged_settings[k] = loaded["settings"][k]
	base["settings"] = merged_settings
	var merged_stats: Dictionary = _default_stats()
	if loaded.get("stats") is Dictionary:
		for k in loaded["stats"].keys():
			merged_stats[k] = loaded["stats"][k]
	base["stats"] = merged_stats
	if not (base.get("progress") is Dictionary):
		base["progress"] = {}
	if not (base.get("custom_levels") is Array):
		base["custom_levels"] = []
	data = base


func save_game() -> void:
	if capture_mode:
		return
	if _save_timer != null:
		_save_timer.stop()
	_dirty = false
	data["version"] = SAVE_VERSION
	data["settings"] = settings
	data["progress"] = progress
	data["stats"] = stats
	data["custom_levels"] = custom_levels
	data["coins"] = coins
	data["items"] = inventory
	data["upgrades"] = upgrades
	var text := JSON.stringify(data, "\t")
	# backup current file before replacing it
	if FileAccess.file_exists(SAVE_PATH):
		var old := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if old != null:
			var old_text := old.get_as_text()
			old.close()
			if not old_text.is_empty():
				var backup := FileAccess.open(BACKUP_PATH, FileAccess.WRITE)
				if backup != null:
					backup.store_string(old_text)
					backup.close()
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save file: %s" % FileAccess.get_open_error())
		return
	f.store_string(text)
	f.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(TEMP_PATH),
			ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		# Windows can refuse to replace an existing file; fall back to a direct write.
		var direct := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		if direct != null:
			direct.store_string(text)
			direct.close()


func _queue_save() -> void:
	_dirty = true
	if _save_timer != null:
		_save_timer.start()
	else:
		save_game()


# --------------------------------------------------------------------------- #
# Settings
# --------------------------------------------------------------------------- #
func get_setting(key: String, fallback: Variant = null) -> Variant:
	if settings.has(key):
		return settings[key]
	return fallback


func set_setting(key: String, value: Variant, silent := false) -> void:
	if settings.get(key) == value:
		return
	settings[key] = value
	_queue_save()
	if not silent:
		settings_changed.emit()


func reset_settings() -> void:
	settings = DEFAULT_SETTINGS.duplicate(true)
	_queue_save()
	settings_changed.emit()


# --------------------------------------------------------------------------- #
# Campaign progress
# --------------------------------------------------------------------------- #
func get_level_record(level_id: String) -> Dictionary:
	return progress.get(level_id, {})


func is_completed(level_id: String) -> bool:
	var rec: Dictionary = progress.get(level_id, {})
	return bool(rec.get("completed", false))


func stars_for(level_id: String) -> int:
	var rec: Dictionary = progress.get(level_id, {})
	return int(rec.get("stars", 0))


func total_stars() -> int:
	var total := 0
	for rec in progress.values():
		total += int(rec.get("stars", 0))
	return total


func count_completed(level_ids: Array) -> int:
	var n := 0
	for id in level_ids:
		if is_completed(str(id)):
			n += 1
	return n


func record_result(level_id: String, moves: int, pushes: int, stars: int,
		seconds: float, award_coins := false) -> Dictionary:
	var rec: Dictionary = (progress.get(level_id, {}) as Dictionary).duplicate(true)
	var first_clear := not bool(rec.get("completed", false))
	var is_new_best := false
	if first_clear:
		rec["completed"] = true
		rec["best_moves"] = moves
		rec["best_pushes"] = pushes
		rec["best_time"] = seconds
		rec["stars"] = stars
		stats["levels_completed"] = int(stats.get("levels_completed", 0)) + 1
		is_new_best = true
	else:
		if moves < int(rec.get("best_moves", 1 << 30)):
			rec["best_moves"] = moves
			is_new_best = true
		if pushes < int(rec.get("best_pushes", 1 << 30)):
			rec["best_pushes"] = pushes
			is_new_best = true
		if float(rec.get("best_time", 1e9)) > seconds and seconds > 0.0:
			rec["best_time"] = seconds
		if stars > int(rec.get("stars", 0)):
			rec["stars"] = stars
			is_new_best = true
	rec["last_played"] = Time.get_unix_time_from_system()
	rec["plays"] = int(rec.get("plays", 0)) + 1
	progress[level_id] = rec
	stats["total_moves"] = int(stats.get("total_moves", 0)) + moves
	stats["total_pushes"] = int(stats.get("total_pushes", 0)) + pushes
	stats["play_seconds"] = float(stats.get("play_seconds", 0.0)) + seconds
	var coin_gain := 0
	if award_coins:
		coin_gain = int(round(ItemCatalog.coins_for_stars(stars) * coin_multiplier()))
		if coin_gain > 0:
			coins += coin_gain
			stats["coins_earned"] = int(stats.get("coins_earned", 0)) + coin_gain
	_queue_save()
	progress_changed.emit()
	if coin_gain > 0:
		wallet_changed.emit()
	return {"first_clear": first_clear, "new_best": is_new_best, "coins_earned": coin_gain,
			"record": rec.duplicate(true)}


# --------------------------------------------------------------------------- #
# Coins and items
# --------------------------------------------------------------------------- #
func wallet_coins() -> int:
	return coins


func add_coins(amount: int, silent := false) -> void:
	if amount == 0:
		return
	coins = maxi(coins + amount, 0)
	if amount > 0:
		stats["coins_earned"] = int(stats.get("coins_earned", 0)) + amount
	_queue_save()
	if not silent:
		wallet_changed.emit()


func spend_coins(amount: int) -> bool:
	if amount <= 0 or coins < amount:
		return false
	coins -= amount
	_queue_save()
	wallet_changed.emit()
	return true


func item_count(item_id: String) -> int:
	return int(inventory.get(item_id, 0))


func add_item(item_id: String, count := 1) -> void:
	if not ItemCatalog.has_item(item_id) or count <= 0:
		return
	inventory[item_id] = item_count(item_id) + count
	_queue_save()
	wallet_changed.emit()


func consume_item(item_id: String) -> bool:
	var owned := item_count(item_id)
	if owned <= 0:
		return false
	inventory[item_id] = owned - 1
	_queue_save()
	wallet_changed.emit()
	return true


## Buys one item if the wallet allows it. Returns false when short on coins.
func buy_item(item_id: String) -> bool:
	if not ItemCatalog.has_item(item_id):
		return false
	var cost := ItemCatalog.price(item_id)
	if coins < cost:
		return false
	coins -= cost
	inventory[item_id] = item_count(item_id) + 1
	_queue_save()
	wallet_changed.emit()
	return true


## Marks one item as used, falling back to an instant purchase when out of stock.
func total_items() -> int:
	var total := 0
	for value in inventory.values():
		total += int(value)
	return total


# --------------------------------------------------------------------------- #
# Robot upgrades
# --------------------------------------------------------------------------- #
func upgrade_level(part_id: String) -> int:
	return int(upgrades.get(part_id, 0))


func upgrade_cost(part_id: String) -> int:
	if not RobotUpgrades.has_part(part_id):
		return -1
	return RobotUpgrades.price(part_id, upgrade_level(part_id) + 1)


func can_upgrade(part_id: String) -> bool:
	var cost := upgrade_cost(part_id)
	return cost > 0 and coins >= cost


## Buys the next level of a robot part. Returns true when the level went up.
func upgrade_part(part_id: String) -> bool:
	var cost := upgrade_cost(part_id)
	if cost <= 0 or coins < cost:
		return false
	coins -= cost
	upgrades[part_id] = upgrade_level(part_id) + 1
	_queue_save()
	wallet_changed.emit()
	return true


func total_upgrade_levels() -> int:
	var total := 0
	for value in upgrades.values():
		total += int(value)
	return total


func invested_upgrade_coins() -> int:
	var total := 0
	for part_id in upgrades.keys():
		for level in range(1, int(upgrades[part_id]) + 1):
			var price := RobotUpgrades.price(str(part_id), level)
			if price > 0:
				total += price
	return total


## Refunds 70% of everything invested and clears every part.
func reset_upgrades() -> int:
	var refund := int(floor(invested_upgrade_coins() * 0.7))
	upgrades = {}
	coins += refund
	_queue_save()
	wallet_changed.emit()
	return refund


## Multiplier applied to clear rewards by the overloaded core.
func coin_multiplier() -> float:
	return 1.0 + RobotUpgrades.coin_bonus(upgrade_level("core"))


## Starter gift: every robot part starts at Lv1 so a new player has the full kit.
## Returns true when at least one part was actually upgraded.
func grant_starter_gift() -> bool:
	var changed := false
	for part_id in RobotUpgrades.ORDER:
		if upgrade_level(str(part_id)) < 1:
			upgrades[str(part_id)] = 1
			changed = true
	data["starter_gift"] = true
	_queue_save()
	if changed:
		wallet_changed.emit()
	return changed


func has_starter_gift() -> bool:
	return bool(data.get("starter_gift", false))


## Main menu calls this once to know whether it should announce the gift.
func consume_starter_gift_announce() -> bool:
	if not starter_gift_announce:
		return false
	starter_gift_announce = false
	return true


func get_last_level() -> String:
	return str(data.get("last_level", ""))


func set_last_level(level_id: String) -> void:
	if data.get("last_level", "") == level_id:
		return
	data["last_level"] = level_id
	_queue_save()


func reset_progress() -> void:
	progress = {}
	stats = _default_stats()
	data["last_level"] = ""
	_queue_save()
	progress_changed.emit()


func total_play_seconds() -> float:
	return float(stats.get("play_seconds", 0.0))


func total_moves() -> int:
	return int(stats.get("total_moves", 0))


func total_pushes() -> int:
	return int(stats.get("total_pushes", 0))


# --------------------------------------------------------------------------- #
# Custom levels (workshop)
# --------------------------------------------------------------------------- #
func get_custom_levels() -> Array:
	return custom_levels


func get_custom_level(level_id: String) -> Dictionary:
	for lv in custom_levels:
		if lv is Dictionary and str(lv.get("id", "")) == level_id:
			return lv
	return {}


func save_custom_level(level_data: Dictionary) -> String:
	var copy: Dictionary = level_data.duplicate(true)
	var id := str(copy.get("id", ""))
	if id.is_empty():
		id = "custom_%d" % Time.get_unix_time_from_system()
		while not get_custom_level(id).is_empty():
			id += "x"
		copy["id"] = id
	copy["builtin"] = false
	copy["updated_at"] = Time.get_unix_time_from_system()
	if not copy.has("created_at"):
		copy["created_at"] = copy["updated_at"]
	var replaced := false
	for i in custom_levels.size():
		var lv: Dictionary = custom_levels[i]
		if str(lv.get("id", "")) == id:
			custom_levels[i] = copy
			replaced = true
			break
	if not replaced:
		custom_levels.push_front(copy)
	_queue_save()
	custom_levels_changed.emit()
	return id


func delete_custom_level(level_id: String) -> void:
	for i in custom_levels.size():
		var lv: Dictionary = custom_levels[i]
		if str(lv.get("id", "")) == level_id:
			custom_levels.remove_at(i)
			_queue_save()
			custom_levels_changed.emit()
			return


func export_custom_levels() -> String:
	return JSON.stringify({"version": 1, "levels": custom_levels}, "\t")


func import_custom_levels(text: String) -> int:
	var parsed: Variant = JSON.parse_string(text)
	var list: Array = []
	if parsed is Array:
		list = parsed
	elif parsed is Dictionary and parsed.get("levels") is Array:
		list = parsed["levels"]
	if list.is_empty():
		return 0
	var imported := 0
	for item in list:
		if not (item is Dictionary):
			continue
		var copy: Dictionary = (item as Dictionary).duplicate(true)
		if not copy.has("rows") or not (copy["rows"] is Array):
			continue
		copy["id"] = ""
		save_custom_level(copy)
		imported += 1
	return imported

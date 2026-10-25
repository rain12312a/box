class_name RobotUpgrades
extends RefCounted
## Mechanical robot upgrades: every part bends one Sokoban rule instead of
## handing out items. Levels are bought with coins and stored in the save file.
##
##  arm  - hydraulic ram       : push a whole line of crates at once
##  hook - magnetic claw       : pull the crate behind the worker
##  legs - jump actuator       : leap over one crate
##  head - phase visor         : step through one wall cell
##  back - warp pack           : teleport the worker to any open cell
##  core - overloaded core     : extra clear coins

const MAX_LEVEL := 3
const ORDER := ["arm", "hook", "legs", "head", "back", "core"]
## One extra use of an ability, bought from the in-level toolbar with coins.
const EXTRA_CHARGE_PRICE := 20

## hotspot = normalised position over assets/art/robot_body.png
const PARTS := {
	"arm": {
		"icon": "push", "hotspot": [0.77, 0.42], "price": [120, 260, 520],
		"active": false,
	},
	"hook": {
		"icon": "pass", "hotspot": [0.23, 0.42], "price": [120, 260, 520],
		"active": true, "charges": [3, 5, -1],
	},
	"legs": {
		"icon": "jump", "hotspot": [0.5, 0.72], "price": [120, 260, 520],
		"active": true, "charges": [3, 6, -1],
	},
	"head": {
		"icon": "phase", "hotspot": [0.5, 0.105], "price": [120, 260, 520],
		"active": true, "charges": [1, 2, 3],
	},
	"back": {
		"icon": "warp", "hotspot": [0.19, 0.215], "price": [120, 260, 520],
		"active": true, "charges": [1, 2, 3],
	},
	"core": {
		"icon": "core", "hotspot": [0.5, 0.305], "price": [120, 260, 520],
		"active": false, "bonus": [0.25, 0.5, 1.0],
	},
}


static func has_part(part_id: String) -> bool:
	return PARTS.has(part_id)


static func icon_name(part_id: String) -> String:
	return str((PARTS.get(part_id, {}) as Dictionary).get("icon", part_id))


static func hotspot(part_id: String) -> Vector2:
	var raw: Array = (PARTS.get(part_id, {}) as Dictionary).get("hotspot", [0.5, 0.5])
	return Vector2(float(raw[0]), float(raw[1]))


static func is_active(part_id: String) -> bool:
	return bool((PARTS.get(part_id, {}) as Dictionary).get("active", false))


static func part_name(part_id: String) -> String:
	var key := "robot_" + part_id
	return Loc.t(key)


static func summary(part_id: String) -> String:
	return Loc.t("robot_" + part_id + "_desc")


## Price of reaching `level` (1 based). Returns -1 when already maxed.
static func price(part_id: String, level: int) -> int:
	if level < 1 or level > MAX_LEVEL:
		return -1
	var raw: Array = (PARTS.get(part_id, {}) as Dictionary).get("price", [])
	if level - 1 >= raw.size():
		return -1
	return int(raw[level - 1])


static func effect_text(part_id: String, level: int) -> String:
	if level < 1 or level > MAX_LEVEL:
		return ""
	return Loc.t("robot_%s_lv%d" % [part_id, level])


## Number of crates the arm can shove in one push (1 = vanilla Sokoban).
static func chain_for(level: int) -> int:
	return clampi(1 + level, 1, 4)


## Charges per level for active parts. -1 means unlimited.
static func charges_for(part_id: String, level: int) -> int:
	if level <= 0:
		return 0
	var raw: Array = (PARTS.get(part_id, {}) as Dictionary).get("charges", [])
	if level - 1 >= raw.size():
		return 0
	return int(raw[level - 1])


## True for parts that have a finite per-level charge pool to top up.
static func can_buy_charges(part_id: String, level: int) -> bool:
	return is_active(part_id) and level > 0 and charges_for(part_id, level) >= 0


## Coins for one extra use. Unlimited parts never need one.
static func extra_charge_price(part_id: String) -> int:
	return EXTRA_CHARGE_PRICE if is_active(part_id) else 0


## Extra clear coins as a ratio (0.0 / 0.25 / 0.5 / 1.0).
static func coin_bonus(level: int) -> float:
	var raw: Array = (PARTS.get("core", {}) as Dictionary).get("bonus", [])
	if level <= 0 or level - 1 >= raw.size():
		return 0.0
	return float(raw[level - 1])


static func charges_text(part_id: String, level: int) -> String:
	var charges := charges_for(part_id, level)
	if charges < 0:
		return Loc.t("robot_charge_infinite")
	return Loc.t("robot_charge_count", [charges])

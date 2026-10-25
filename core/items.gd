class_name ItemCatalog
extends RefCounted
## Coin economy and the consumable shop items used during a campaign level.

const COIN_PER_STAR := 15
const AD_REWARD := 25
const AD_SECONDS := 5.0

const ITEMS := {
	"c4": {
		"price": 25, "icon": "c4",
		"name": "item_c4", "desc": "item_c4_desc",
	},
	"rope": {
		"price": 25, "icon": "rope",
		"name": "item_rope", "desc": "item_rope_desc",
	},
	"crane": {
		"price": 50, "icon": "crane",
		"name": "item_crane", "desc": "item_crane_desc",
	},
	"rewind": {
		"price": 10, "icon": "rewind",
		"name": "item_rewind", "desc": "item_rewind_desc",
	},
	"guide": {
		"price": 10, "icon": "guide",
		"name": "item_guide", "desc": "item_guide_desc",
	},
	"contract": {
		"price": 100, "icon": "contract",
		"name": "item_contract", "desc": "item_contract_desc",
	},
}

## Display order: cheap utility first, the big finishers last.
const ORDER := ["rewind", "guide", "c4", "rope", "crane", "contract"]


static func has_item(item_id: String) -> bool:
	return ITEMS.has(item_id)


static func price(item_id: String) -> int:
	var entry: Dictionary = ITEMS.get(item_id, {})
	return int(entry.get("price", 0))


static func icon_name(item_id: String) -> String:
	var entry: Dictionary = ITEMS.get(item_id, {})
	return str(entry.get("icon", item_id))


static func display_name(item_id: String) -> String:
	var entry: Dictionary = ITEMS.get(item_id, {})
	var key := str(entry.get("name", ""))
	return Loc.t(key) if not key.is_empty() else item_id


static func description(item_id: String) -> String:
	var entry: Dictionary = ITEMS.get(item_id, {})
	var key := str(entry.get("desc", ""))
	return Loc.t(key) if not key.is_empty() else ""


static func coins_for_stars(stars: int) -> int:
	return maxi(stars, 0) * COIN_PER_STAR

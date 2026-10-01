class_name ContentCatalog
extends RefCounted
## Explicit preloads keep all game content available in exported builds.
## Every lookup returns a new Dictionary, safe for runtime calculations.

const ROOMS: Dictionary = {
	"goblin": preload("res://data/rooms/goblin.tres"),
	"executioner": preload("res://data/rooms/executioner.tres"),
	"poison": preload("res://data/rooms/poison.tres"),
	"spider": preload("res://data/rooms/spider.tres"),
	"spikes": preload("res://data/rooms/spikes.tres"),
	"mimic": preload("res://data/rooms/mimic.tres"),
	"shackles": preload("res://data/rooms/shackles.tres"),
	"silence": preload("res://data/rooms/silence.tres"),
	"rust": preload("res://data/rooms/rust.tres"),
	"guardian": preload("res://data/rooms/guardian.tres"),
	"ogre": preload("res://data/rooms/ogre.tres"),
	"war_hound": preload("res://data/rooms/war_hound.tres"),
	"wraith": preload("res://data/rooms/wraith.tres"),
	"vampire": preload("res://data/rooms/vampire.tres"),
	"ballista": preload("res://data/rooms/ballista.tres"),
	"blade_floor": preload("res://data/rooms/blade_floor.tres"),
}
const HEROES: Dictionary = {
	"knight": preload("res://data/heroes/knight.tres"),
	"rogue": preload("res://data/heroes/rogue.tres"),
	"priest": preload("res://data/heroes/priest.tres"),
	"mage": preload("res://data/heroes/mage.tres"),
	"barbarian": preload("res://data/heroes/barbarian.tres"),
	"bard": preload("res://data/heroes/bard.tres"),
}
const ITEMS: Dictionary = {
	"sword": preload("res://data/items/sword.tres"),
	"shield": preload("res://data/items/shield.tres"),
}

static func room(id: String) -> Dictionary:
	if not ROOMS.has(id):
		return {}
	return ROOMS[id].to_dictionary()

static func hero(id: String) -> Dictionary:
	if not HEROES.has(id):
		return {}
	return HEROES[id].to_dictionary()

static func item(id: String) -> Dictionary:
	if not ITEMS.has(id):
		return {}
	return ITEMS[id].to_dictionary()

static func room_ids() -> Array[String]:
	return ["goblin", "executioner", "poison", "spider", "spikes", "mimic", "shackles", "silence", "rust", "guardian", "ogre", "war_hound", "wraith", "vampire", "ballista", "blade_floor"]

static func hero_ids() -> Array[String]:
	return ["knight", "rogue", "priest", "mage", "barbarian", "bard"]

static func room_traits_text(stats: Dictionary) -> String:
	var labels: Array[String] = []
	var names: Dictionary = {"creature": "Существо", "corporeal": "Телесное", "spirit": "Дух", "trap": "Ловушка", "poison": "Яд", "ambush": "Засада"}
	for tag in stats.get("tags", []):
		if names.has(str(tag)):
			labels.append(str(names[str(tag)]))
	if int(stats.get("armor", 0)) > 0:
		labels.append("Броня")
	return " · ".join(labels)

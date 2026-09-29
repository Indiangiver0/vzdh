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
}
const HEROES: Dictionary = {
	"knight": preload("res://data/heroes/knight.tres"),
	"rogue": preload("res://data/heroes/rogue.tres"),
	"priest": preload("res://data/heroes/priest.tres"),
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
	return ["goblin", "executioner", "poison", "spider", "spikes", "mimic"]

static func hero_ids() -> Array[String]:
	return ["knight", "rogue", "priest"]

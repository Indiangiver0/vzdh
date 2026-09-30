extends RefCounted
## Run-only talent definitions. The simulation owns ranks, offers and modifiers.
## max_rank = 0 means unlimited; all lookups return independent dictionaries.

const TALENTS: Dictionary = {
	"battle_lord": {
		"id": "battle_lord", "name": "Боевой Владыка", "category": "lord", "rarity": "common",
		"bonus": "+50% урона Владыки", "drawback": "−10% максимального HP Владыки",
		"min_level": 1, "max_rank": 1,
		"modifiers": {"lord_damage": 0.5, "lord_hp": -0.1},
	},
	"minion_fury": {
		"id": "minion_fury", "name": "Неистовые прислужники", "category": "creatures", "rarity": "common",
		"bonus": "+40% урона существ", "drawback": "−10% HP существ",
		"min_level": 1, "max_rank": 1,
		"modifiers": {"monster_damage": 0.4, "monster_hp": -0.1},
	},
	"greed": {
		"id": "greed", "name": "Жадность", "category": "economy", "rarity": "common",
		"bonus": "+50% золота за героев", "drawback": "Герои получают на 15% больше опыта за существ",
		"min_level": 1, "max_rank": 1,
		"modifiers": {"kill_gold": 0.5, "hero_room_xp": 0.15},
	},
	"lasting_poison": {
		"id": "lasting_poison", "name": "Долгий яд", "category": "traps", "rarity": "common",
		"bonus": "+50% длительности яда", "drawback": "−10% урона шипов",
		"min_level": 1, "max_rank": 1,
		"modifiers": {"poison_duration": 0.5, "spike_damage": -0.1},
	},
	"expansion": {
		"id": "expansion", "name": "Глубокие владения", "category": "economy", "rarity": "common",
		"bonus": "Этажи дешевле на 25%", "drawback": "Лечение дороже на 10%",
		"min_level": 1, "max_rank": 1,
		"modifiers": {"floor_cost": -0.25, "heal_cost": 0.1},
	},
	"opening_wrath": {
		"id": "opening_wrath", "name": "Первый гнев", "category": "lord", "rarity": "rare",
		"bonus": "Первые 3 удара Владыки в каждой волне наносят ×2 урона",
		"drawback": "Лечение дороже на 10%",
		"min_level": 4, "max_rank": 1,
		"modifiers": {"opening_strikes": 3, "opening_multiplier": 2.0, "heal_cost": 0.1},
	},
	"iron_throne": {
		"id": "iron_throne", "name": "Железный трон", "category": "lord", "rarity": "common",
		"bonus": "+15% максимального HP Владыки", "drawback": "",
		"min_level": 1, "max_rank": 0,
		"modifiers": {"lord_hp": 0.15},
	},
	"overlord_might": {
		"id": "overlord_might", "name": "Мощь Владыки", "category": "lord", "rarity": "common",
		"bonus": "+15% урона Владыки", "drawback": "",
		"min_level": 1, "max_rank": 0,
		"modifiers": {"lord_damage": 0.15},
	},
	"sturdy_minions": {
		"id": "sturdy_minions", "name": "Крепкие прислужники", "category": "creatures", "rarity": "common",
		"bonus": "+15% HP существ", "drawback": "",
		"min_level": 1, "max_rank": 0,
		"modifiers": {"monster_hp": 0.15},
	},
	"trap_mastery": {
		"id": "trap_mastery", "name": "Мастер ловушек", "category": "traps", "rarity": "common",
		"bonus": "+15% урона ловушек", "drawback": "",
		"min_level": 1, "max_rank": 0,
		"modifiers": {"trap_damage": 0.15},
	},
	"thick_armor": {
		"id": "thick_armor", "name": "Толстая броня", "category": "lord", "rarity": "common",
		"bonus": "+1 к броне Владыки", "drawback": "",
		"min_level": 1, "max_rank": 3,
		"modifiers": {"lord_armor": 1},
	},
	"blood_income": {
		"id": "blood_income", "name": "Кровавый доход", "category": "economy", "rarity": "common",
		"bonus": "+10% золота за героев", "drawback": "",
		"min_level": 1, "max_rank": 0,
		"modifiers": {"kill_gold": 0.1},
	},
}


static func ids() -> Array[String]:
	return [
		"battle_lord", "minion_fury", "greed", "lasting_poison", "expansion", "opening_wrath",
		"iron_throne", "overlord_might", "sturdy_minions", "trap_mastery", "thick_armor", "blood_income",
	]


static func get_talent(id: String) -> Dictionary:
	if not TALENTS.has(id):
		return {}
	return TALENTS[id].duplicate(true)


static func all() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for id in ids():
		definitions.append(get_talent(id))
	return definitions

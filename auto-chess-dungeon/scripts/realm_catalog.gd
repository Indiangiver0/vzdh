extends RefCounted
## Immutable faction and room evolution definitions. Runtime rules live in DungeonGame.

const EVOLUTIONS: Dictionary = {
	"assault_drill": {"id": "assault_drill", "name": "Школа натиска", "description": "+20% урона существа.", "tier": 5, "modifiers": {"damage_bonus": 0.20}},
	"assault_endurance": {"id": "assault_endurance", "name": "Закалка бойца", "description": "+25% HP существа.", "tier": 5, "modifiers": {"hp_bonus": 0.25}},
	"bastion_wall": {"id": "bastion_wall", "name": "Каменная шкура", "description": "+25% HP существа.", "tier": 5, "modifiers": {"hp_bonus": 0.25}},
	"bastion_counter": {"id": "bastion_counter", "name": "Вооружённый караул", "description": "+15% урона и +1 броня существа.", "tier": 5, "modifiers": {"damage_bonus": 0.15, "armor_bonus": 1}},
	"warlord": {"id": "warlord", "name": "Воевода", "description": "+30% урона существа.", "tier": 15, "modifiers": {"damage_bonus": 0.30}},
	"iron_veteran": {"id": "iron_veteran", "name": "Железный ветеран", "description": "+20% HP и +2 брони существа.", "tier": 15, "modifiers": {"hp_bonus": 0.20, "armor_bonus": 2}},
	"living_fortress": {"id": "living_fortress", "name": "Живая крепость", "description": "+40% HP существа.", "tier": 15, "modifiers": {"hp_bonus": 0.40}},
	"fortress_champion": {"id": "fortress_champion", "name": "Чемпион крепости", "description": "+25% урона и +1 броня существа.", "tier": 15, "modifiers": {"damage_bonus": 0.25, "armor_bonus": 1}},
	"spike_force": {"id": "spike_force", "name": "Тяжёлый механизм", "description": "+20% урона шипов.", "tier": 5, "modifiers": {"damage_bonus": 0.20}},
	"spike_safety": {"id": "spike_safety", "name": "Скрытый спуск", "description": "После обезвреживания шипы сохраняют 70% урона вместо 40%.", "tier": 5, "modifiers": {"disarm_multiplier": 0.70}},
	"spike_crusher": {"id": "spike_crusher", "name": "Сокрушитель", "description": "+35% урона шипов.", "tier": 15, "modifiers": {"damage_bonus": 0.35}},
	"spike_failsafe": {"id": "spike_failsafe", "name": "Тройной спуск", "description": "После обезвреживания шипы сохраняют 90% урона.", "tier": 15, "modifiers": {"disarm_multiplier": 0.90}},
	"poison_brewer": {"id": "poison_brewer", "name": "Сильный настой", "description": "+20% урона каждого тика яда.", "tier": 5, "modifiers": {"damage_bonus": 0.20}},
	"poison_sticky": {"id": "poison_sticky", "name": "Тягучий настой", "description": "+2 тика длительности яда.", "tier": 5, "modifiers": {"poison_turns": 2}},
	"poison_stable": {"id": "poison_stable", "name": "Стойкий настой", "description": "Следопыт сокращает яд до 5 тиков вместо 3, если исходный эффект не короче.", "tier": 5, "modifiers": {"disarm_poison_turns": 5}},
	"poison_elixir": {"id": "poison_elixir", "name": "Эликсир распада", "description": "+30% урона каждого тика яда.", "tier": 15, "modifiers": {"damage_bonus": 0.30}},
	"poison_unfading": {"id": "poison_unfading", "name": "Неугасимый яд", "description": "+4 тика длительности яда.", "tier": 15, "modifiers": {"poison_turns": 4}},
	"poison_sealed": {"id": "poison_sealed", "name": "Запечатанный сосуд", "description": "Следопыт сокращает яд до 8 тиков вместо 3, если исходный эффект не короче.", "tier": 15, "modifiers": {"disarm_poison_turns": 8}},
	"control_reinforced": {"id": "control_reinforced", "name": "Усиленная печать", "description": "После обезвреживания сохраняет полную длительность контроля. Удар печати следопыт всё ещё ослабляет.", "tier": 5, "modifiers": {"disarm_control_floor": 6}},
	"control_barbed": {"id": "control_barbed", "name": "Колючая печать", "description": "+4 прямого урона переднему герою при срабатывании.", "tier": 5, "modifiers": {"impact_bonus": 4}},
	"control_chain": {"id": "control_chain", "name": "Цепной разряд", "description": "Удар печати поражает всю группу: каждому герою достаётся 60% обычного прямого урона. Контроль действует как прежде.", "tier": 15, "modifiers": {"impact_all": true}},
	"control_master_seal": {"id": "control_master_seal", "name": "Печать мастера", "description": "После обезвреживания сохраняет полную длительность контроля. Удар печати следопыт всё ещё ослабляет.", "tier": 15, "modifiers": {"disarm_control_floor": 6}},
	"control_execution": {"id": "control_execution", "name": "Казнящая печать", "description": "+12 прямого урона переднему герою при срабатывании.", "tier": 15, "modifiers": {"impact_bonus": 12}},
}


static func factions() -> Array[Dictionary]:
	return [
		{
			"id": "horde", "name": "Орда", "color": Color("#db8b64"),
			"room_ids": ["goblin", "spider", "executioner"],
			"bonuses": [
				{"threshold": 2, "description": "2 типа: +12% HP существ Орды.", "modifiers": {"monster_hp": 0.12}},
				{"threshold": 3, "description": "3 типа: ещё +12% урона существ Орды.", "modifiers": {"monster_damage": 0.12}},
			],
		},
		{
			"id": "coven", "name": "Ковен", "color": Color("#ae8ed6"),
			"room_ids": ["poison", "mimic", "guardian"],
			"bonuses": [
				{"threshold": 2, "description": "2 типа: +10% урона комнат Ковена.", "modifiers": {"monster_damage": 0.10, "trap_damage": 0.10}},
				{"threshold": 3, "description": "3 типа: ещё +1 броня существ Ковена.", "modifiers": {"monster_armor": 1}},
			],
		},
		{
			"id": "mechanisms", "name": "Механизмы", "color": Color("#6faecb"),
			"room_ids": ["spikes", "shackles", "silence", "rust"],
			"bonuses": [
				{"threshold": 2, "description": "2 типа: +10% урона ловушек Механизмов.", "modifiers": {"trap_damage": 0.10}},
				{"threshold": 3, "description": "3 типа: ещё +1 тик контроля Механизмов, максимум 6.", "modifiers": {"control_turns": 1}},
			],
		},
	]


static func faction_for_room(room_id: String) -> Dictionary:
	for faction in factions():
		if faction.room_ids.has(room_id):
			return faction
	return {}


static func evolution(id: String) -> Dictionary:
	return EVOLUTIONS.get(id, {}).duplicate(true)


static func evolution_options(kind: String, specialization: String, tier: int, previous_id: String = "") -> Array[Dictionary]:
	var ids: Array[String] = []
	if kind == "monster":
		if tier == 5:
			ids.assign(["bastion_wall", "bastion_counter"] if specialization == "bulwark" else ["assault_drill", "assault_endurance"])
		elif tier == 15:
			ids.assign(["living_fortress", "fortress_champion"] if previous_id in ["bastion_wall", "assault_endurance"] else ["warlord", "iron_veteran"])
	elif kind == "spikes":
		if tier == 5:
			ids.assign(["spike_force", "spike_safety"])
		elif tier == 15:
			ids.assign(["spike_crusher", "spike_failsafe"])
	elif kind == "poison":
		if tier == 5:
			ids.assign(["poison_brewer", "poison_stable"] if specialization == "lingering" else ["poison_brewer", "poison_sticky"])
		elif tier == 15:
			ids.assign(["poison_elixir", "poison_unfading"] if previous_id == "poison_stable" else ["poison_elixir", "poison_sealed"])
	elif kind in ["shackles", "silence", "rust"]:
		if tier == 5:
			ids.assign(["control_reinforced", "control_barbed"])
		elif tier == 15:
			ids.assign(["control_execution", "control_chain"] if previous_id == "control_reinforced" else ["control_execution", "control_master_seal"])
	var options: Array[Dictionary] = []
	for id in ids:
		options.append(evolution(id))
	return options

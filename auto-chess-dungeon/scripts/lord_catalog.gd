extends RefCounted
## Immutable archetype and mastery data. Combat owns charges and active effects.

const MAX_MASTERY: int = 5
const UPGRADE_COSTS: Array[int] = [30, 50, 80, 120]

const LORDS: Dictionary = {
	"fallen_knight": {
		"id": "fallen_knight", "name": "Падший рыцарь", "title": "Страж последнего рубежа",
		"description": "Укрепляет прислужников и прикрывает защитника, которому предстоит принять удар.",
		"color": "#c9ad78", "icon": "res://assets/icons/lord_knight.svg", "unlock_cost": 0,
		"max_mastery": 5,
		"passive_description": "+10% HP существ во всех комнатах.",
		"ability_name": "Железная воля",
		"ability_description": "Даёт текущему защитнику щит и усиливает три следующих удара. Работает и на Владыке.",
		"variants": [
			{"id": "base", "name": "Боевой обет", "description": "Щит и три усиленных удара текущего защитника.", "min_mastery": 1},
			{"id": "bulwark", "name": "Несокрушимый бастион", "description": "Щит сильнее на 20 процентных пунктов, усиления ударов нет.", "min_mastery": 3},
		],
	},
	"necromancer": {
		"id": "necromancer", "name": "Некромант", "title": "Хозяин возвращённых",
		"description": "Лишает героев части опыта и позволяет выбранному защитнику пережить смертельный удар.",
		"color": "#b09ac8", "icon": "res://assets/icons/lord_necromancer.svg", "unlock_cost": 40,
		"max_mastery": 5,
		"passive_description": "Герои получают на 15% меньше XP за существ.",
		"ability_name": "Восстань",
		"ability_description": "Помечает текущего защитника: после смертельного урона он один раз возвращается с частью HP. Работает и на Владыке.",
		"variants": [
			{"id": "base", "name": "Печать возврата", "description": "Возвращает помеченного защитника с частью максимального HP.", "min_mastery": 1},
			{"id": "revenant", "name": "Мстительный призрак", "description": "Возвращает на 10 процентных пунктов меньше HP, зато даёт +30% урона до конца боя в комнате.", "min_mastery": 3},
		],
	},
	"plague_alchemist": {
		"id": "plague_alchemist", "name": "Чумной алхимик", "title": "Мастер ядов",
		"description": "Продлевает отравление и наказывает группы, уже ослабленные ядовитыми камерами.",
		"color": "#79b99a", "icon": "res://assets/icons/lord_alchemist.svg", "unlock_cost": 60,
		"max_mastery": 5,
		"passive_description": "+20% длительности яда.",
		"ability_name": "Чумной выброс",
		"ability_description": "Отравляет всех живых героев. Те, кто был отравлен до применения, дополнительно получают мгновенный урон.",
		"variants": [
			{"id": "base", "name": "Чумной выброс", "description": "Яд на всю группу и вспышка по уже отравленным героям.", "min_mastery": 1},
			{"id": "corrosion", "name": "Едкая вспышка", "description": "Мгновенный урон ×1,5, но длительность накладываемого яда меньше на 2 тика.", "min_mastery": 3},
		],
	},
}


static func ids() -> Array[String]:
	return ["fallen_knight", "necromancer", "plague_alchemist"]


static func get_lord(id: String) -> Dictionary:
	if not LORDS.has(id):
		return {}
	return LORDS[id].duplicate(true)


static func ability_values(id: String, mastery: int = 1, variant: String = "base") -> Dictionary:
	if not LORDS.has(id):
		return {}
	var level: int = clampi(mastery, 1, MAX_MASTERY)
	var chosen_variant: String = "base"
	for option in LORDS[id]["variants"]:
		if str(option["id"]) == variant and level >= int(option["min_mastery"]):
			chosen_variant = variant
			break
	var values: Dictionary = {
		"id": id, "mastery": level, "variant": chosen_variant, "charges": 2,
		"monster_hp_bonus": 0.0, "hero_xp_bonus": 0.0, "poison_duration_bonus": 0.0,
		"shield_fraction": 0.0, "attack_bonus": 0.0, "empowered_attacks": 0,
		"revive_fraction": 0.0, "revive_damage_bonus": 0.0,
		"poison_damage": 0, "poison_ticks": 0, "burst_damage": 0,
	}
	var additional_levels: int = level - 1
	match id:
		"fallen_knight":
			values["monster_hp_bonus"] = 0.10
			values["shield_fraction"] = 0.30 + 0.04 * additional_levels
			values["attack_bonus"] = 0.35 + 0.05 * additional_levels
			values["empowered_attacks"] = 3
			if chosen_variant == "bulwark":
				values["shield_fraction"] += 0.20
				values["attack_bonus"] = 0.0
				values["empowered_attacks"] = 0
		"necromancer":
			values["hero_xp_bonus"] = -0.15
			values["revive_fraction"] = 0.35 + 0.05 * additional_levels
			if chosen_variant == "revenant":
				values["revive_fraction"] -= 0.10
				values["revive_damage_bonus"] = 0.30
		"plague_alchemist":
			values["poison_duration_bonus"] = 0.20
			values["poison_damage"] = 3 + floori(float(additional_levels) / 2.0)
			values["poison_ticks"] = 6 + additional_levels
			values["burst_damage"] = 6 + 2 * additional_levels
			if chosen_variant == "corrosion":
				values["burst_damage"] = ceili(float(values["burst_damage"]) * 1.5)
				values["poison_ticks"] = maxi(1, int(values["poison_ticks"]) - 2)
	return values


static func upgrade_cost(current_level: int) -> int:
	if current_level < 1 or current_level >= MAX_MASTERY:
		return 0
	return UPGRADE_COSTS[current_level - 1]

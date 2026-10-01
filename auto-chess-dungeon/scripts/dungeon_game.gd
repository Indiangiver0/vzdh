extends RefCounted
## The complete run state and deterministic battle rules. No scene or UI dependencies.

const Content = preload("res://scripts/content_catalog.gd")
const Talents = preload("res://scripts/talent_catalog.gd")
const Lords = preload("res://scripts/lord_catalog.gd")
const Expedition = preload("res://scripts/expedition_catalog.gd")
const Realm = preload("res://scripts/realm_catalog.gd")
const SLOTS_PER_FLOOR: int = 5
const MAX_LOGS: int = 70
const RELIC_WAVE_INTERVAL: int = 10
const BLUEPRINT_WAVE_INTERVAL: int = 7

var phase: String = "prepare"
var wave: int = 1
var gold: int = 18
var floor_count: int = 1
var floor_traits: Array[String] = ["plain"]
var pending_floor: int = -1
var rooms: Array[Dictionary] = []
var heroes: Array[Dictionary] = []
var lord: Dictionary = {}
var upgrades: Dictionary = {"hp": 0, "damage": 0, "trap": 0}
var selected_talents: Dictionary = {}
var talent_offers: Array[String] = []
var lord_strikes: int = 0
var lord_archetype: String = ""
var lord_mastery: int = 1
var lord_variant: String = "base"
var ability_charges: int = 0
var shop: Dictionary = {}
var logs: Array[String] = []
var current_slot: int = -1
var defender: Dictionary = {}
var tick: int = 0
var combat_tick: int = 0
var rage: int = 0
var report: Dictionary = {}
var total_kills: int = 0
var cleared_waves: int = 0
var pending_upgrades: int = 0
var unlocked_paths: Array[String] = []
var wave_title: String = ""
var wave_description: String = ""
var elite_id: String = ""
var last_action: Dictionary = {}
var active_target_id: String = ""
var seed_value: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var talent_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var expedition_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var deal_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var selected_blueprints: Array[String] = []
var selected_relics: Array[String] = []
var blueprint_offers: Array[String] = []
var relic_offers: Array[String] = []
var tutorial_run: bool = false

var _waiting_for_entry: bool = true
var _instance_counter: int = 0
var _has_started_raid: bool = false
var _lord_ability_values: Dictionary = {}
var _pending_blueprint: bool = false
var _pending_relic: bool = false
var _echo_floors: Array[int] = []
var _deal_state: Dictionary = {}
var _battle_rooms: Array[Dictionary] = []
var _battle_room_indices: Dictionary = {}


func _init() -> void:
	restart()


func restart(new_seed: int = 0) -> void:
	if new_seed == 0:
		rng.randomize()
		seed_value = rng.seed
	else:
		seed_value = new_seed
		rng.seed = new_seed
	# Talent draws must never consume the party/shop random sequence.
	talent_rng.seed = seed_value ^ 0x54A1E17
	expedition_rng.seed = seed_value ^ 0x73D19A2
	deal_rng.seed = seed_value ^ 0x4D3A115
	_deal_state.clear()
	_battle_rooms.clear()
	_battle_room_indices.clear()
	tutorial_run = false
	selected_blueprints.clear()
	selected_relics.clear()
	blueprint_offers.clear()
	relic_offers.clear()
	_pending_blueprint = false
	_pending_relic = false
	_echo_floors.clear()
	phase = "prepare"
	wave = 1
	gold = 18
	floor_count = 1
	floor_traits.assign(["plain"])
	pending_floor = -1
	rooms.clear()
	for _slot in range(SLOTS_PER_FLOOR):
		rooms.append({})
	heroes.clear()
	lord = {
		"id": "lord", "name": "Лорд Подземелья", "hp": 120, "max_hp": 120,
		"damage": 10, "armor": 1, "level": 1, "xp": 0,
	}
	upgrades = {"hp": 0, "damage": 0, "trap": 0}
	selected_talents.clear()
	talent_offers.clear()
	lord_strikes = 0
	lord_archetype = ""
	lord_mastery = 1
	lord_variant = "base"
	ability_charges = 0
	_lord_ability_values.clear()
	_has_started_raid = false
	shop.clear()
	logs.clear()
	current_slot = -1
	defender = {}
	tick = 0
	combat_tick = 0
	rage = 0
	total_kills = 0
	cleared_waves = 0
	pending_upgrades = 0
	last_action = {}
	active_target_id = ""
	_instance_counter = 0
	_waiting_for_entry = true
	_reset_report()
	_generate_party()
	_generate_shop()
	_log("Подземелье открыто. Постройте защиту и запустите первую волну.")


func begin_tutorial() -> void:
	# A disposable run: the caller must exclude it from permanent rewards.
	restart(7102026)
	tutorial_run = true
	unlocked_paths.clear()
	gold = 90
	configure_lord("fallen_knight")
	shop = {"goblin": 2, "executioner": 2, "spikes": 2, "poison": 2}
	var novice: Dictionary = heroes[0]
	var definition: Dictionary = Content.hero("knight")
	novice.id = "knight"
	novice.instance_id = "1_knight"
	novice.name = "Рыцарь-послушник"
	novice.icon = definition.icon
	novice.color = definition.color
	novice.trait = "Учебный противник: 120 HP, 4 урона. Способность Владыки активируется вручную."
	novice.hp = 120
	novice.max_hp = 120
	novice.damage = 4
	novice.armor = 1
	novice.disarm_max = 0
	novice.disarm_charges = 0
	heroes.assign([novice])
	wave_title = "Первый налёт · обучение"
	wave_description = "Рыцарь-послушник покажет работу комнат и способности Владыки."
	_log("Учебные 90 золотых действуют только в этом тренировочном забеге.")


func configure_lord(id: String, mastery: int = 1, variant: String = "base") -> String:
	if phase != "prepare" or wave != 1 or _has_started_raid:
		return "Владыку выбирают до первого рейда нового забега."
	var definition: Dictionary = Lords.get_lord(id)
	var values: Dictionary = Lords.ability_values(id, mastery, variant)
	if definition.is_empty() or values.is_empty():
		return "Неизвестный Владыка."
	lord_archetype = id
	lord_mastery = int(values.mastery)
	lord_variant = str(values.variant)
	# Mastery and variant are snapshots: profile changes cannot alter a running raid.
	_lord_ability_values = values.duplicate(true)
	ability_charges = int(values.charges)
	lord.name = str(definition.name)
	_clear_defender_effects(lord)
	_log("Владыка: %s · мастерство %d." % [lord.name, lord_mastery])
	return ""


func lord_passive_modifiers() -> Dictionary:
	return {
		"monster_hp": float(_lord_ability_values.get("monster_hp_bonus", 0.0)),
		"hero_room_xp": float(_lord_ability_values.get("hero_xp_bonus", 0.0)),
		"poison_duration": float(_lord_ability_values.get("poison_duration_bonus", 0.0)),
	}


func ability_status() -> Dictionary:
	var definition: Dictionary = Lords.get_lord(lord_archetype)
	var name: String = str(definition.get("ability_name", "Способность Владыки"))
	var description: String = str(definition.get("ability_description", ""))
	if not _lord_ability_values.is_empty():
		if lord_archetype == "fallen_knight":
			description = "Щит: %d%% максимального HP защитника." % roundi(float(_lord_ability_values.shield_fraction) * 100.0)
			if int(_lord_ability_values.empowered_attacks) > 0:
				description += " Следующие %d удара: +%d%% урона." % [_lord_ability_values.empowered_attacks, roundi(float(_lord_ability_values.attack_bonus) * 100.0)]
		elif lord_archetype == "necromancer":
			description = "Метка возвращает защитника после смертельного удара с %d%% HP." % roundi(float(_lord_ability_values.revive_fraction) * 100.0)
			if float(_lord_ability_values.revive_damage_bonus) > 0.0:
				description += " После возвращения: +%d%% урона до конца комнаты." % roundi(float(_lord_ability_values.revive_damage_bonus) * 100.0)
		elif lord_archetype == "plague_alchemist":
			description = "Вся группа: яд %d × %d тиков. Уже отравленным — ещё %d урона яда." % [_lord_ability_values.poison_damage, _scaled_poison_duration(int(_lord_ability_values.poison_ticks)), _lord_ability_values.burst_damage]
	var effect_parts: Array[String] = []
	if int(defender.get("shield", 0)) > 0:
		effect_parts.append("Щит %d" % int(defender.shield))
	if int(defender.get("ability_attacks", 0)) > 0:
		effect_parts.append("Усиленных ударов: %d" % int(defender.ability_attacks))
	if bool(defender.get("revive_mark", false)):
		effect_parts.append("Метка возвращения: %d%% HP" % roundi(float(defender.revive_fraction) * 100.0))
	if float(defender.get("revenant_damage_bonus", 0.0)) > 0.0:
		effect_parts.append("Возвращённый: +%d%% урона" % roundi(float(defender.revenant_damage_bonus) * 100.0))
	var reason: String = _ability_block_reason()
	return {
		"name": name, "description": description, "charges": ability_charges,
		"max_charges": int(_lord_ability_values.get("charges", 0)),
		"can_cast": reason.is_empty(), "reason": reason, "effect": " · ".join(effect_parts),
		"shield": int(defender.get("shield", 0)),
		"empowered_attacks": int(defender.get("ability_attacks", 0)),
		"revive_mark": bool(defender.get("revive_mark", false)),
	}


func _ability_block_reason() -> String:
	if lord_archetype.is_empty() or _lord_ability_values.is_empty():
		return "Для этого забега Владыка не выбран."
	if phase != "raid":
		return "Способность доступна во время рейда."
	if int(lord.hp) <= 0:
		return "Владыка погиб."
	if ability_charges <= 0:
		return "Заряды этой волны закончились."
	if _waiting_for_entry or defender.is_empty() or int(defender.get("hp", 0)) <= 0 or _living().is_empty():
		return "Дождитесь боя с живым защитником."
	if current_slot < 0 or current_slot > rooms.size():
		return "Сейчас нет активного боя."
	if current_slot < rooms.size() and str(defender.get("kind", "")) != "monster":
		return "Способность применяется в боевой комнате или тронном зале."
	if lord_archetype == "fallen_knight" and (int(defender.get("shield", 0)) > 0 or int(defender.get("ability_attacks", 0)) > 0):
		return "У этого защитника ещё действует предыдущий щит или усиление."
	if lord_archetype == "necromancer" and bool(defender.get("revive_mark", false)):
		return "Этот защитник уже отмечен для возвращения."
	return ""


func cast_ability() -> String:
	var reason: String = _ability_block_reason()
	if not reason.is_empty():
		return reason
	ability_charges -= 1
	var message: String = ""
	var amount: int = 0
	var target_id: String = _defender_actor()
	if lord_archetype == "fallen_knight":
		var shield: int = maxi(1, ceili(float(defender.max_hp) * float(_lord_ability_values.shield_fraction)))
		defender.shield = shield
		defender.ability_attacks = int(_lord_ability_values.empowered_attacks)
		defender.ability_attack_bonus = float(_lord_ability_values.attack_bonus)
		amount = shield
		message = "%s: щит +%d, усиленных ударов %d." % [defender.name, shield, defender.ability_attacks]
	elif lord_archetype == "necromancer":
		defender.revive_mark = true
		defender.revive_fraction = float(_lord_ability_values.revive_fraction)
		defender.revive_damage_bonus = float(_lord_ability_values.revive_damage_bonus)
		amount = maxi(1, ceili(float(defender.max_hp) * float(defender.revive_fraction)))
		message = "%s отмечен: смертельный удар вернёт его с %d HP." % [defender.name, amount]
	elif lord_archetype == "plague_alchemist":
		var targets: Array[Dictionary] = _living()
		var duration: int = _scaled_poison_duration(int(_lord_ability_values.poison_ticks))
		var burst_total: int = 0
		for hero in targets:
			var was_poisoned: bool = int(hero.poison_ticks) > 0
			if was_poisoned:
				var burst: int = _poison_hit(hero, int(_lord_ability_values.burst_damage))
				burst_total += _inflict_hero_damage(hero, burst, "lord")
			else:
				hero.poison_heal_factor = 1.0
			_apply_hero_poison(hero, int(_lord_ability_values.poison_damage), duration, "lord")
		amount = burst_total
		target_id = str(targets[0].instance_id)
		active_target_id = target_id
		message = "Чумная волна: яд %d × %d тиков всей группе; вспышка %d урона уже отравленным." % [_lord_ability_values.poison_damage, duration, burst_total]
		_process_deaths()
		if _living().is_empty():
			_mark_room_held()
			_finish_wave()
	_log(message)
	_action("ability", "lord", target_id, amount, message)
	last_action.lord_archetype = lord_archetype
	last_action.charges = ability_charges
	return ""


func _clear_defender_effects(target: Dictionary) -> void:
	if target.is_empty():
		return
	for key in ["shield", "ability_attacks", "ability_attack_bonus", "revive_mark", "revive_fraction", "revive_damage_bonus", "revenant_damage_bonus"]:
		target.erase(key)


func _scaled_poison_duration(base_ticks: int) -> int:
	return maxi(1, ceili(float(base_ticks) * (1.0 + float(talent_modifiers().poison_duration) + float(lord_passive_modifiers().poison_duration))))


func _poison_hit(hero: Dictionary, raw_damage: int) -> int:
	return maxi(1, floori(float(raw_damage) * float(hero.get("poison_resistance", 1.0))))


func _try_revive_defender() -> bool:
	if int(defender.hp) > 0 or not bool(defender.get("revive_mark", false)):
		return false
	defender.revive_mark = false
	defender.hp = clampi(ceili(float(defender.max_hp) * float(defender.revive_fraction)), 1, int(defender.max_hp))
	defender.revenant_damage_bonus = maxf(float(defender.get("revenant_damage_bonus", 0.0)), float(defender.get("revive_damage_bonus", 0.0)))
	_log("%s возвращается с %d HP: метка израсходована." % [defender.name, defender.hp])
	return true


func buy_room(index: int, id: String) -> String:
	if phase != "prepare":
		return "Строительство доступно между волнами."
	if not _valid_slot(index):
		return "Выберите строительный слот."
	if not rooms[index].is_empty():
		return "Этот слот уже занят. Выберите пустое место."
	if not Content.room_ids().has(id):
		return "Такой комнаты нет."
	if Expedition.blueprint_ids().has(id) and not selected_blueprints.has(id):
		return "Сначала выберите чертёж этой комнаты после волны."
	if int(shop.get(id, 0)) <= 0:
		return "Запас этой комнаты на текущую волну закончился."
	var definition: Dictionary = Content.room(id)
	var price: int = int(definition.cost)
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	gold -= price
	shop[id] = int(shop[id]) - 1
	_instance_counter += 1
	rooms[index] = {
		"id": id, "rank": 1, "invested": price, "used": false,
		"instance_id": _instance_counter, "status": "ready",
		"specialization": "",
	}
	_log("%s: построено, этаж %d · место %d." % [definition.name, index / 5 + 1, index % 5 + 1])
	return ""


func move_room(from_index: int, to_index: int) -> String:
	if phase != "prepare":
		return "Перестановка доступна между волнами."
	if not _valid_slot(from_index) or not _valid_slot(to_index):
		return "Выберите два строительных слота."
	if rooms[from_index].is_empty():
		return "Сначала выберите построенную комнату."
	if from_index == to_index:
		return ""
	var previous: Dictionary = rooms[to_index]
	rooms[to_index] = rooms[from_index]
	rooms[from_index] = previous
	_log("Порядок комнат изменён.")
	return ""


func upgrade_room(index: int) -> String:
	if phase != "prepare":
		return "Улучшения доступны между волнами."
	if not _valid_slot(index) or rooms[index].is_empty():
		return "Выберите построенную комнату."
	var stats: Dictionary = room_stats(index)
	if int(stats.max_rank) > 0 and int(stats.rank) >= int(stats.max_rank):
		return "Комната достигла максимального ранга %d." % int(stats.max_rank)
	var price: int = upgrade_cost(index)
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	gold -= price
	rooms[index].rank = int(rooms[index].rank) + 1
	rooms[index].invested = int(rooms[index].invested) + price
	_log("%s: ранг %d." % [Content.room(str(rooms[index].id)).name, rooms[index].rank])
	return ""


func sell_room(index: int) -> String:
	if phase != "prepare":
		return "Продажа доступна между волнами."
	if not _valid_slot(index) or rooms[index].is_empty():
		return "Выберите построенную комнату."
	var refund: int = sell_value(index)
	var id: String = str(rooms[index].id)
	var cancel_deal: bool = int(rooms[index].get("deal_wave", 0)) == wave and not bool(rooms[index].used)
	if cancel_deal:
		_deal_state.accepted = false
		_deal_state.erase("instance_id")
		_set_deal_risk(false)
	elif not bool(rooms[index].used):
		shop[id] = int(shop.get(id, 0)) + 1
	gold += refund
	rooms[index] = {}
	_log("%s: возвращено %d золота." % [Content.room(id).name, refund])
	return ""


func buy_floor() -> String:
	if phase != "prepare":
		return "Этаж можно купить между волнами."
	var price: int = floor_cost()
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	gold -= price
	floor_count += 1
	floor_traits.append("plain")
	pending_floor = floor_count - 1
	for _slot in range(SLOTS_PER_FLOOR):
		rooms.append({})
	phase = "floor_choice"
	_log("Куплен этаж %d: ещё 5 мест перед тронным залом." % floor_count)
	return ""


func choose_floor_trait(id: String) -> String:
	if phase != "floor_choice" or pending_floor < 0:
		return "Сейчас нет нового этажа для настройки."
	var selected: Dictionary = {}
	for option in floor_trait_options():
		if str(option.id) == id:
			selected = option
	if selected.is_empty():
		return "Выберите свойство из предложенных."
	floor_traits[pending_floor] = id
	_log("Этаж %d: %s. %s" % [pending_floor + 1, selected.name, selected.description])
	pending_floor = -1
	phase = "prepare"
	return ""


static func floor_trait_options() -> Array[Dictionary]:
	return [
		{"id": "laboratory", "name": "Лаборатория", "description": "Яд действует на 2 тика дольше; HP существ −15%."},
		{"id": "barracks", "name": "Казармы", "description": "HP существ +25%; урон ловушек −15%."},
		{"id": "workshop", "name": "Мастерская", "description": "Урон ловушек +25%; урон существ −10%."},
	]


func specialization_options(index: int) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not _valid_slot(index) or rooms[index].is_empty():
		return options
	var state: Dictionary = rooms[index]
	if int(state.rank) < 1 or not str(state.get("specialization", "")).is_empty():
		return options
	var id: String = str(state.id)
	return _specialization_definitions(id)


func _specialization_definitions(id: String) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if id == "poison":
		options.assign([
			{"id": "virulent", "name": "Едкий яд", "description": "+1 урон каждого тика яда."},
			{"id": "lingering", "name": "Долгий яд", "description": "Яд действует на 3 тика дольше."},
		])
		if unlocked_paths.has("plague"):
			options.append({"id": "plague", "name": "Чума", "description": "Отравленные получают на 50% меньше лечения."})
	elif id == "blade_floor":
		options.assign([
			{"id": "volley", "name": "Круговой рез", "description": "+20% урона каждому живому герою."},
			{"id": "piercing", "name": "Направленный рез", "description": "+60% урона переднему герою; остальные больше не получают урон."},
		])
	elif str(Content.room(id).kind) == "spikes":
		options.assign([
			{"id": "volley", "name": "Залп", "description": "По 45% урона каждому живому герою."},
			{"id": "piercing", "name": "Пробой", "description": "+60% урона заднему герою." if id == "ballista" else "+60% урона переднему герою."},
		])
	elif str(Content.room(id).kind) in ["shackles", "silence", "rust"]:
		options.assign([
			{"id": "control_lingering", "name": "Долгое действие", "description": "+1 тик действия в следующем бою, максимум 6."},
			{"id": "warded", "name": "Защитная печать", "description": "Следопыт уменьшает длительность лишь на 1 тик вместо сокращения до 1."},
		])
	else:
		options.assign([
			{"id": "fury", "name": "Ярость", "description": "+30% урона, −10% HP существа."},
			{"id": "bulwark", "name": "Бастион", "description": "+40% HP, −10% урона существа."},
		])
		if id == "mimic" and unlocked_paths.has("ambush"):
			options.append({"id": "ambush", "name": "Засада", "description": "Первый удар мимика по тылу наносит +75% урона."})
	return options


func specialize_room(index: int, id: String) -> String:
	if phase != "prepare":
		return "Ветку комнаты выбирают между волнами."
	for option in specialization_options(index):
		if str(option.id) == id:
			rooms[index].specialization = id
			_log("%s: выбрана ветка «%s»." % [Content.room(str(rooms[index].id)).name, option.name])
			return ""
	return "Ветка недоступна: нужен ранг 1 и ещё не выбранная специализация."


static func room_faction(id: String) -> Dictionary:
	return Realm.faction_for_room(id)


func faction_status() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in Realm.factions():
		var owned: Array[String] = []
		for room in rooms:
			if not room.is_empty() and definition.room_ids.has(str(room.id)) and not owned.has(str(room.id)):
				owned.append(str(room.id))
		var status: Dictionary = definition.duplicate(true)
		status.count = owned.size()
		status.thresholds = []
		status.active = []
		for bonus in status.bonuses:
			bonus.active = owned.size() >= int(bonus.threshold)
			status.thresholds.append(int(bonus.threshold))
			if bool(bonus.active):
				status.active.append(str(bonus.description))
		result.append(status)
	return result


func _faction_modifiers(id: String) -> Dictionary:
	var result: Dictionary = {}
	for status in faction_status():
		if not status.room_ids.has(id):
			continue
		for bonus in status.bonuses:
			if not bool(bonus.active):
				continue
			for key in bonus.modifiers:
				result[key] = float(result.get(key, 0.0)) + float(bonus.modifiers[key])
	return result


func room_evolution_options(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _valid_slot(index) or rooms[index].is_empty():
		return result
	var state: Dictionary = rooms[index]
	var specialization: String = str(state.get("specialization", ""))
	if specialization.is_empty():
		for option in specialization_options(index):
			var choice: Dictionary = option.duplicate(true)
			choice.tier = 1
			result.append(choice)
		return result
	var evolutions: Dictionary = state.get("evolutions", {})
	for tier in [5, 15]:
		if not str(evolutions.get(str(tier), "")).is_empty():
			continue
		if int(state.rank) < tier:
			return result
		var previous: String = str(evolutions.get("5", "")) if tier == 15 else ""
		for option in Realm.evolution_options(str(Content.room(str(state.id)).kind), specialization, tier, previous):
			var choice: Dictionary = option.duplicate(true)
			choice.tier = tier
			result.append(choice)
		return result
	return result


func choose_room_evolution(index: int, id: String) -> String:
	if phase != "prepare":
		return "Развитие комнаты доступно между волнами."
	for option in room_evolution_options(index):
		if str(option.id) != id:
			continue
		if int(option.tier) == 1:
			return specialize_room(index, id)
		var evolutions: Dictionary = rooms[index].get("evolutions", {}).duplicate(true)
		evolutions[str(option.tier)] = id
		rooms[index].evolutions = evolutions
		_log("%s: ступень %d — %s." % [Content.room(str(rooms[index].id)).name, option.tier, option.name])
		return ""
	return "Выберите доступную ступень развития этой комнаты."


func room_progression(index: int) -> Dictionary:
	if not _valid_slot(index) or rooms[index].is_empty():
		return {}
	var state: Dictionary = rooms[index]
	var stages: Array[Dictionary] = []
	var next_tier: int = 0
	var specialization: String = str(state.get("specialization", ""))
	var evolutions: Dictionary = state.get("evolutions", {})
	for tier in [1, 5, 15]:
		var id: String = specialization if tier == 1 else str(evolutions.get(str(tier), ""))
		var chosen: bool = not id.is_empty()
		if not chosen and next_tier == 0:
			next_tier = tier
		var title: String = "Выбор ветки" if tier == 1 else "Развитие комнаты"
		var description: String = ""
		if chosen:
			title = str(room_stats(index).branch) if tier == 1 else str(Realm.evolution(id).get("name", id))
			if tier == 1:
				for option in _specialization_definitions(str(state.id)):
					if str(option.id) == id:
						description = str(option.description)
			else:
				description = str(Realm.evolution(id).get("description", ""))
		stages.append({"tier": tier, "name": title, "description": description, "chosen": chosen, "id": id, "available": not chosen and next_tier == tier and int(state.rank) >= tier})
	return {"rank": int(state.rank), "specialization": specialization, "stages": stages, "next_tier": next_tier}


func _evolution_modifiers(state: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var evolutions: Dictionary = state.get("evolutions", {})
	for id in evolutions.values():
		var definition: Dictionary = Realm.evolution(str(id))
		for key in definition.get("modifiers", {}):
			var value: float = float(definition.modifiers[key])
			if str(key).begins_with("disarm_"):
				result[key] = maxf(float(result.get(key, 0.0)), value)
			else:
				result[key] = float(result.get(key, 0.0)) + value
	return result


func _prepare_deal() -> void:
	if tutorial_run or wave % 6 != 0 or not _deal_state.is_empty():
		return
	var available: Array[String] = []
	for id in Content.room_ids():
		if not Expedition.blueprint_ids().has(id) or selected_blueprints.has(id):
			available.append(id)
	if available.is_empty():
		return
	var id: String = available[deal_rng.randi_range(0, available.size() - 1)]
	var definition: Dictionary = Content.room(id)
	var offered_rank: int = 2 + floori(float(wave) / 6.0)
	if str(definition.kind) in ["shackles", "silence", "rust"]:
		offered_rank = mini(15, offered_rank)
	_deal_state = {
		"room_id": id, "rank": offered_rank, "price": int(definition.cost), "accepted": false,
		"description": "%s сразу ранга %d по обычной цене." % [str(definition.name), offered_rank],
		"risk_text": "Герои этой волны: +10% HP. Продажа комнаты до рейда отменит сделку.",
	}


func deal_offer() -> Dictionary:
	if _deal_state.is_empty():
		return {}
	var result: Dictionary = _deal_state.duplicate(true)
	result.available = phase == "prepare" and not bool(result.accepted)
	return result


func buy_deal_room(index: int) -> String:
	if phase != "prepare" or _deal_state.is_empty() or bool(_deal_state.get("accepted", false)):
		return "Сейчас нет доступной сделки."
	if not _valid_slot(index) or not rooms[index].is_empty():
		return "Для сделки выберите пустое место."
	var price: int = int(_deal_state.price)
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	gold -= price
	_instance_counter += 1
	rooms[index] = {
		"id": str(_deal_state.room_id), "rank": int(_deal_state.rank), "invested": price, "used": false,
		"instance_id": _instance_counter, "status": "ready", "specialization": "", "deal_wave": wave,
	}
	_deal_state.accepted = true
	_deal_state.instance_id = _instance_counter
	_set_deal_risk(true)
	_log("Сделка принята: %s. Герои волны %d получают +10%% HP." % [_deal_state.description, wave])
	return ""


func _set_deal_risk(enabled: bool) -> void:
	for hero in heroes:
		hero.deal_hp_multiplier = 1.1 if enabled else 1.0
		_recalculate_hero(hero)
		hero.hp = hero.max_hp


static func unlock_catalog() -> Array[Dictionary]:
	return [
		{"id": "ambush", "name": "Засада мимика", "description": "Новая ветка мимика: первый удар по тылу +75% урона.", "wave": 5},
		{"id": "plague", "name": "Чумная камера", "description": "Новая ветка яда: лечение отравленных уменьшается вдвое.", "wave": 10},
	]


func heal_lord() -> String:
	if phase != "prepare":
		return "Лечение доступно между волнами."
	if int(lord.hp) >= int(lord.max_hp):
		return "Лорд уже полностью здоров."
	var price: int = heal_cost()
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	gold -= price
	var restored: int = mini(ceili(float(lord.max_hp) * 0.25), int(lord.max_hp) - int(lord.hp))
	lord.hp = int(lord.hp) + restored
	_log("Лорд восстановил %d HP." % restored)
	return ""


func start_raid() -> String:
	if phase != "prepare":
		return "Сначала завершите текущую волну и выберите усиления."
	if int(lord.hp) <= 0:
		return "Лорд погиб. Начните новый забег."
	_has_started_raid = true
	_clear_defender_effects(defender)
	_clear_defender_effects(lord)
	ability_charges = int(_lord_ability_values.get("charges", 0))
	phase = "raid"
	current_slot = -1
	defender = {}
	tick = 0
	combat_tick = 0
	rage = 0
	lord_strikes = 0
	_echo_floors.clear()
	_waiting_for_entry = true
	last_action = {}
	active_target_id = ""
	_reset_report()
	_begin_battle_room_report()
	for hero in heroes:
		hero.disarm_charges = int(hero.get("disarm_max", 2 if str(hero.id) == "rogue" else 0))
		_clear_hero_control(hero)
		hero.erase("goblin_mark_slot")
	for index in range(rooms.size()):
		if rooms[index].is_empty():
			continue
		rooms[index].used = true
		rooms[index].status = "ready"
		rooms[index].current_hp = int(room_stats(index).hp)
	_log("Волна %d: героев в группе — %d." % [wave, heroes.size()])
	return ""


func step() -> void:
	if phase != "raid":
		return
	last_action = {}
	if int(lord.hp) <= 0:
		_finish_defeat()
		return
	if _living().is_empty():
		_finish_wave()
		return
	if _waiting_for_entry:
		_enter_next_room()
	else:
		_combat_step()


func next_wave() -> String:
	if phase != "result":
		return "Текущая волна ещё не завершена."
	wave += 1
	_clear_defender_effects(defender)
	ability_charges = int(_lord_ability_values.get("charges", 0))
	current_slot = -1
	defender = {}
	combat_tick = 0
	rage = 0
	lord_strikes = 0
	last_action = {}
	active_target_id = ""
	for room in rooms:
		if not room.is_empty():
			room.status = "ready"
	_deal_state.clear()
	_generate_party()
	_generate_shop()
	_advance_reward_choice()
	_log("Приближается волна %d. Подготовьте подземелье." % wave)
	return ""


func choose_upgrade(id: String) -> String:
	# Compatibility entry point: only the current offered talent IDs are accepted.
	return choose_talent(id)


func choose_talent(id: String) -> String:
	if phase != "level_up" or pending_upgrades <= 0:
		return "Сейчас нет доступного выбора таланта."
	if not talent_offers.has(id):
		return "Выберите один из трёх предложенных талантов."
	var definition: Dictionary = Talents.get_talent(id)
	if definition.is_empty() or not _talent_is_eligible(definition):
		return "Этот талант сейчас недоступен."
	selected_talents[id] = int(selected_talents.get(id, 0)) + 1
	_recalculate_lord()
	pending_upgrades -= 1
	var drawback_text: String = ""
	if not str(definition.drawback).is_empty():
		drawback_text = " Цена: %s" % definition.drawback
	_log("Талант «%s» · ранг %d. %s%s" % [definition.name, selected_talents[id], definition.bonus, drawback_text])
	talent_offers.clear()
	_advance_reward_choice()
	return ""


func talent_options() -> Array[Dictionary]:
	# A read-only view: repainting the UI cannot reroll choices or change health.
	var options: Array[Dictionary] = []
	for id in talent_offers:
		var definition: Dictionary = Talents.get_talent(id).duplicate(true)
		if definition.is_empty():
			continue
		definition.current_rank = int(selected_talents.get(id, 0))
		definition.rank = int(definition.current_rank) + 1
		options.append(definition)
	return options


func _advance_reward_choice() -> void:
	# Every earned reward is mandatory, with one shared continuation point.
	if pending_upgrades > 0:
		phase = "level_up"
		if talent_offers.is_empty():
			_generate_talent_offers()
		return
	talent_offers.clear()
	if _pending_blueprint:
		var available: Array[String] = _available_blueprint_ids()
		for index in range(blueprint_offers.size() - 1, -1, -1):
			if not available.has(blueprint_offers[index]):
				blueprint_offers.remove_at(index)
		if blueprint_offers.is_empty():
			blueprint_offers.assign(_draw_run_choices(available))
		if not blueprint_offers.is_empty():
			phase = "blueprint"
			return
		_pending_blueprint = false
	if _pending_relic:
		var available: Array[String] = _available_relic_ids()
		for index in range(relic_offers.size() - 1, -1, -1):
			if not available.has(relic_offers[index]):
				relic_offers.remove_at(index)
		if relic_offers.is_empty():
			relic_offers.assign(_draw_run_choices(available))
		if not relic_offers.is_empty():
			phase = "relic"
			return
		_pending_relic = false
	phase = "prepare"
	_prepare_deal()


func _draw_run_choices(available: Array[String]) -> Array[String]:
	var pool: Array[String] = available.duplicate()
	var choices: Array[String] = []
	for _offer in range(mini(3, pool.size())):
		var index: int = expedition_rng.randi_range(0, pool.size() - 1)
		choices.append(pool[index])
		pool.remove_at(index)
	return choices


func _available_blueprint_ids() -> Array[String]:
	var available: Array[String] = []
	for id in Expedition.blueprint_ids():
		if not selected_blueprints.has(id) and not available.has(id):
			available.append(id)
	return available


func blueprint_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var available: Array[String] = _available_blueprint_ids()
	for id in blueprint_offers:
		if not available.has(id):
			continue
		var definition: Dictionary = Content.room(id).duplicate(true)
		definition.description = str(definition.get("description", "")) + " Открывает покупку этой комнаты до конца забега."
		options.append(definition)
	return options


func choose_blueprint(id: String) -> String:
	if phase != "blueprint" or not _pending_blueprint:
		return "Сейчас нет доступного чертежа."
	if not blueprint_offers.has(id) or not _available_blueprint_ids().has(id):
		return "Выберите один из предложенных чертежей."
	selected_blueprints.append(id)
	# A reward must be useful immediately, even if the shop was already drawn.
	if not shop.has(id) and shop.size() >= 4:
		var replaceable: Array = shop.keys()
		replaceable.reverse()
		for previous in replaceable:
			if str(previous) not in ["goblin", "spikes"]:
				shop.erase(previous)
				break
	shop[id] = maxi(2, int(shop.get(id, 0)))
	blueprint_offers.clear()
	_pending_blueprint = false
	_log("Чертёж «%s»: комната открыта в магазине до конца забега." % Content.room(id).name)
	_advance_reward_choice()
	return ""


static func relic_definitions() -> Array[Dictionary]:
	return Expedition.relics()


func _available_relic_ids() -> Array[String]:
	var available: Array[String] = []
	for definition in Expedition.relics():
		var id: String = str(definition.id)
		if not selected_relics.has(id):
			available.append(id)
	return available


func relic_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for id in relic_offers:
		if selected_relics.has(id):
			continue
		var definition: Dictionary = Expedition.relic(id)
		if not definition.is_empty():
			options.append(definition)
	return options


func choose_relic(id: String) -> String:
	if phase != "relic" or not _pending_relic:
		return "Сейчас нет доступной реликвии."
	if not relic_offers.has(id) or not _available_relic_ids().has(id):
		return "Выберите одну из предложенных реликвий."
	selected_relics.append(id)
	relic_offers.clear()
	_pending_relic = false
	var definition: Dictionary = Expedition.relic(id)
	_log("Реликвия «%s». %s" % [definition.name, definition.description])
	_advance_reward_choice()
	return ""


static func combo_catalog() -> Array[Dictionary]:
	return Expedition.combos()


func active_combos() -> Array[Dictionary]:
	var combos: Array[Dictionary] = []
	for index in range(rooms.size()):
		var link: Dictionary = _outgoing_combo(index)
		if not link.is_empty():
			combos.append(link)
	return combos


func room_combo(index: int) -> Dictionary:
	var outgoing: Dictionary = _outgoing_combo(index)
	if not outgoing.is_empty():
		return outgoing
	var previous: int = _previous_route_slot(index)
	return _outgoing_combo(previous) if previous >= 0 else {}


func _previous_route_slot(index: int) -> int:
	if not _valid_slot(index):
		return -1
	var floor_index: int = index / SLOTS_PER_FLOOR
	var previous: int = index - (1 if floor_index % 2 == 0 else -1)
	return previous if _valid_slot(previous) and previous / SLOTS_PER_FLOOR == floor_index else -1


func _outgoing_combo(index: int) -> Dictionary:
	if not _valid_slot(index) or rooms[index].is_empty():
		return {}
	var following: int = next_route_slot(index)
	if not _valid_slot(following) or rooms[following].is_empty() or index / SLOTS_PER_FLOOR != following / SLOTS_PER_FLOOR:
		return {}
	for definition in combo_catalog():
		if str(rooms[index].id) == str(definition.first) and str(rooms[following].id) == str(definition.second):
			var link: Dictionary = definition.duplicate(true)
			link["from"] = index
			link["to"] = following
			return link
	return {}


func talent_modifiers() -> Dictionary:
	var modifiers: Dictionary = {
		"lord_hp": 0.0, "lord_damage": 0.0, "lord_armor": 0.0,
		"monster_hp": 0.0, "monster_damage": 0.0, "trap_damage": 0.0,
		"spike_damage": 0.0, "poison_duration": 0.0, "kill_gold": 0.0,
		"hero_room_xp": 0.0, "floor_cost": 0.0, "heal_cost": 0.0,
		"opening_strikes": 0.0, "opening_multiplier": 1.0,
	}
	for id in selected_talents:
		var rank: int = maxi(0, int(selected_talents[id]))
		var definition: Dictionary = Talents.get_talent(str(id))
		if definition.is_empty() or rank == 0:
			continue
		var effects: Dictionary = definition.get("modifiers", {})
		for key in effects:
			if str(key) == "opening_multiplier":
				# Catalog stores the absolute multiplier (2 means double), not +200%.
				modifiers[key] = float(modifiers[key]) + (float(effects[key]) - 1.0) * rank
			else:
				modifiers[key] = float(modifiers.get(key, 0.0)) + float(effects[key]) * rank
	return modifiers


func opening_strikes_remaining() -> int:
	return maxi(0, int(talent_modifiers().opening_strikes) - lord_strikes)


func _talent_is_eligible(definition: Dictionary) -> bool:
	if int(lord.level) < int(definition.get("min_level", 1)):
		return false
	var rank: int = int(selected_talents.get(str(definition.id), 0))
	var maximum: int = int(definition.get("max_rank", 0))
	return maximum == 0 or rank < maximum


func _generate_talent_offers() -> void:
	talent_offers.clear()
	if phase != "level_up" or pending_upgrades <= 0:
		return
	var eligible: Array[String] = []
	for id in Talents.ids():
		var definition: Dictionary = Talents.get_talent(id)
		if not definition.is_empty() and _talent_is_eligible(definition):
			eligible.append(id)
	for _offer in range(mini(3, eligible.size())):
		var index: int = talent_rng.randi_range(0, eligible.size() - 1)
		talent_offers.append(eligible[index])
		eligible.remove_at(index)


func _recalculate_lord() -> void:
	var old_hp: int = int(lord.hp)
	var damage_taken: int = maxi(0, int(lord.max_hp) - old_hp)
	var levels: int = int(lord.level) - 1
	var modifiers: Dictionary = talent_modifiers()
	lord.max_hp = maxi(1, ceili(float(120 + 10 * levels) * (1.0 + float(modifiers.lord_hp))))
	lord.damage = maxi(1, ceili(float(10 + levels) * (1.0 + float(modifiers.lord_damage))))
	lord.armor = maxi(0, 1 + int(modifiers.lord_armor))
	# Increasing max HP preserves wounds; lowering it cannot kill a living lord.
	# Repeated calls with the same base/modifiers neither heal nor resurrect.
	lord.hp = clampi(int(lord.max_hp) - damage_taken, 1, int(lord.max_hp)) if old_hp > 0 else 0


func room_stats(index: int) -> Dictionary:
	if not _valid_slot(index) or rooms[index].is_empty():
		return {}
	var state: Dictionary = rooms[index]
	var result: Dictionary = Content.room(str(state.id)).duplicate(true)
	var rank: int = int(state.rank)
	var rank_factor: float = 1.0 + 0.25 * float(rank - 1)
	var is_monster: bool = str(result.kind) == "monster"
	var modifiers: Dictionary = talent_modifiers()
	var faction: Dictionary = _faction_modifiers(str(state.id))
	var evolution: Dictionary = _evolution_modifiers(state)
	var hp_factor: float = 1.0 + 0.1 * float(upgrades.hp) + float(modifiers.monster_hp) + float(lord_passive_modifiers().monster_hp)
	hp_factor += float(faction.get("monster_hp", 0.0)) + float(evolution.get("hp_bonus", 0.0))
	var damage_factor: float = 1.0 + 0.1 * float(upgrades.damage if is_monster else upgrades.trap)
	damage_factor += float(modifiers.monster_damage if is_monster else modifiers.trap_damage)
	damage_factor += float(faction.get("monster_damage" if is_monster else "trap_damage", 0.0)) + float(evolution.get("damage_bonus", 0.0))
	if str(state.id) == "spikes":
		damage_factor += float(modifiers.spike_damage)
	var floor_index: int = index / SLOTS_PER_FLOOR
	var floor_trait: String = floor_traits[floor_index] if floor_index < floor_traits.size() else "plain"
	var specialization: String = str(state.get("specialization", ""))
	var duration: int = 6 + int(evolution.get("poison_turns", 0))
	if floor_trait == "laboratory":
		hp_factor *= 0.85
		duration += 2
	elif floor_trait == "barracks":
		hp_factor *= 1.25
		if not is_monster:
			damage_factor *= 0.85
	elif floor_trait == "workshop":
		damage_factor *= 0.9 if is_monster else 1.25
	var branch_names: Dictionary = {
		"virulent": "Едкий яд", "lingering": "Долгий яд", "plague": "Чума",
		"volley": "Залп", "piercing": "Пробой", "fury": "Ярость",
		"bulwark": "Бастион", "ambush": "Засада",
		"control_lingering": "Долгое действие", "warded": "Защитная печать",
	}
	if str(state.id) == "blade_floor":
		branch_names.volley = "Круговой рез"
		branch_names.piercing = "Направленный рез"
	if specialization == "fury":
		hp_factor *= 0.9
		damage_factor *= 1.3
	elif specialization == "bulwark":
		hp_factor *= 1.4
		damage_factor *= 0.9
	elif specialization == "volley":
		damage_factor *= 1.2 if str(state.id) == "blade_floor" else 0.45
	elif specialization == "piercing":
		damage_factor *= 1.6
	elif specialization == "lingering":
		duration += 3
	duration = _scaled_poison_duration(duration)
	result.hp = ceili(float(result.hp) * rank_factor * hp_factor) if is_monster else 0
	result.max_hp = result.hp
	result.damage = ceili(float(result.damage) * rank_factor * damage_factor)
	if is_monster:
		result.armor = int(result.armor) + int(faction.get("monster_armor", 0)) + int(evolution.get("armor_bonus", 0))
	if specialization == "virulent":
		result.damage = int(result.damage) + 1
	var base_xp: int = int(result.xp) + 2 * (rank - 1) if is_monster else 0
	result.xp = hero_room_xp(base_xp)
	result.rank = rank
	result.max_rank = 15 if str(result.kind) in ["shackles", "silence", "rust"] else 0
	result.invested = state.invested
	result.used = state.used
	result.specialization = specialization
	result.branch = str(branch_names.get(specialization, ""))
	result.floor_trait = floor_trait
	result.poison_ticks = duration
	result.impact_damage = 0
	result.impact_all = bool(evolution.get("impact_all", false))
	result.disarm_multiplier = maxf(0.4, float(evolution.get("disarm_multiplier", 0.0)))
	result.disarm_poison_turns = maxi(3, int(evolution.get("disarm_poison_turns", 0)))
	result.disarm_control_floor = int(evolution.get("disarm_control_floor", 0))
	if str(result.kind) in ["shackles", "silence", "rust"]:
		result.effect_turns = mini(5, int(result.get("effect_turns", 2)) + rank - 1)
		var bonus_turns: int = int(faction.get("control_turns", 0)) + int(evolution.get("control_turns", 0))
		bonus_turns += 1 if specialization == "control_lingering" else 0
		result.effect_turns = mini(6, int(result.effect_turns) + bonus_turns)
		result.impact_damage = ceili(float(maxi(0, rank - 1) + int(evolution.get("impact_bonus", 0))) * damage_factor)
	if str(state.id) == "guardian" and selected_relics.has("guardian_oath"):
		result.armor = int(result.armor) + 1
	result.role = "Атакует переднего героя"
	if str(state.id) == "mimic":
		result.role = "Охотится на барда, жрицу, чародея и следопыта в тылу"
	elif str(state.id) == "spider":
		result.role = "Добивает слабейшего, предпочитает отравленных"
	elif str(state.id) == "poison":
		result.role = "Отравляет всю группу на %d тиков" % duration
	elif str(state.id) == "spikes":
		result.role = "Бьёт всю группу" if specialization == "volley" else "Бьёт переднего героя в обход брони"
	elif str(state.id) == "ballista":
		result.role = "Бьёт всю группу в обход брони" if specialization == "volley" else "Бьёт заднего живого героя в обход брони"
	elif str(state.id) == "blade_floor":
		result.role = "Бьёт переднего героя в обход брони" if specialization == "piercing" else "Бьёт всю группу в обход брони"
	elif str(state.id) == "ogre":
		result.role = "Бьёт переднего героя; каждый третий удар ×1,5"
	elif str(state.id) == "war_hound":
		result.role = "Атакует самого раненого; +30% урона по цели с HP не выше 40%"
	elif str(state.id) == "wraith":
		result.role = "Бьёт переднего героя, игнорируя 2 брони"
	elif str(state.id) == "vampire":
		result.role = "Бьёт переднего героя; лечится на 25% снятых HP, если пережил ответ"
	elif str(state.id) == "shackles":
		result.role = "Группа пропускает атаки в чётные из первых %d тиков следующего боя" % int(result.effect_turns)
	elif str(state.id) == "silence":
		result.role = "Блокирует спецдействия на первые %d тика следующего боя" % int(result.effect_turns)
	elif str(state.id) == "rust":
		result.role = "Группа: −1 брони в первые %d тика следующего боя" % int(result.effect_turns)
	elif str(state.id) == "guardian":
		result.role = "Долго удерживает отряд, пока действует яд"
	result.combo = room_combo(index)
	result.status = state.get("status", "ready")
	result.current_hp = int(state.get("current_hp", result.hp)) if phase in ["raid", "result", "defeat"] else int(result.hp)
	return result


func hero_room_xp(base_xp: int) -> int:
	# Round the shared pool to the nearest integer: a small greed penalty must not
	# turn a 3 XP room into 4 XP (+33%) before its rank has even increased.
	return maxi(0, roundi(float(base_xp) * (1.0 + float(talent_modifiers().hero_room_xp) + float(lord_passive_modifiers().hero_room_xp))))


func floor_cost() -> int:
	var next_floor: int = floor_count + 1
	return maxi(1, ceili(float(5 * next_floor * next_floor) * (1.0 + float(talent_modifiers().floor_cost))))


func heal_cost() -> int:
	var base_cost: int = 6 + 2 * floori(float(wave - 1) / 5.0)
	return maxi(1, ceili(float(base_cost) * (1.0 + float(talent_modifiers().heal_cost))))


func upgrade_cost(index: int) -> int:
	if not _valid_slot(index) or rooms[index].is_empty():
		return 0
	return int(Content.room(str(rooms[index].id)).cost) * (int(rooms[index].rank) + 1)


func sell_value(index: int) -> int:
	if not _valid_slot(index) or rooms[index].is_empty():
		return 0
	var invested: int = int(rooms[index].invested)
	return floori(float(invested) / 2.0) if bool(rooms[index].used) else invested


func _generate_party() -> void:
	heroes.clear()
	_configure_wave()
	var templates: Array[Dictionary] = Expedition.party_templates(wave)
	var template: Dictionary = templates[rng.randi_range(0, templates.size() - 1)]
	var party_ids: Array[String] = []
	party_ids.assign(template.ids)
	# The sapper expedition must contain the specialist its preview promises.
	if elite_id == "sappers" and not party_ids.has("rogue"):
		party_ids[party_ids.size() - 1] = "rogue"
	var elite_description: String = wave_description
	if elite_id.is_empty():
		wave_title = str(template.name)
		wave_description = str(template.description)
	else:
		var names: Array[String] = []
		for id in party_ids:
			names.append(str(Content.hero(id).name))
		wave_description += " Отряд: %s." % ", ".join(names)
	var group_factor: float = 1.0
	if party_ids.size() == 2:
		group_factor = 0.75
	elif party_ids.size() == 3:
		group_factor = 0.65
	var pressure: float = 1.0 + 0.01 * pow(maxi(0, wave - 12), 2)
	var starting_level: int = 1 + floori(float(wave - 1) / 4.0)
	var disarm_supply: int = 2 + floori(float(wave - 1) / 6.0)
	if elite_id == "sappers":
		disarm_supply += 2
	for id in party_ids:
		var definition: Dictionary = Content.hero(id)
		var hero: Dictionary = {
			"id": id, "instance_id": "%d_%s" % [wave, id],
			"name": definition.name, "level": starting_level, "xp": 0,
			"hp": 0, "max_hp": 0, "damage": 0, "armor": 0,
			"items": [], "poison_ticks": 0, "poison_damage": 0,
			"poison_heal_factor": 1.0, "poison_resistance": 0.65 if elite_id == "alchemy" else 1.0,
			"elite_armor": 1 if elite_id == "armor" else 0,
			"disarm_max": disarm_supply if id == "rogue" else 0,
			"disarm_charges": disarm_supply if id == "rogue" else 0,
			"elite_modifier": elite_description,
			"death_processed": false, "group_factor": group_factor,
			"pressure": pressure, "icon": definition.icon, "color": definition.color,
			"trait": definition.trait,
		}
		_recalculate_hero(hero)
		_clear_hero_control(hero)
		hero.hp = hero.max_hp
		heroes.append(hero)


func _configure_wave() -> void:
	elite_id = ""
	wave_title = "Налёт приключенцев"
	wave_description = ""
	if wave % 5 != 0:
		return
	var variant: int = ((wave / 5) - 1) % 3
	if variant == 0:
		elite_id = "armor"
		wave_title = "Железный авангард"
		wave_description = "Элита: каждому герою +1 брони. Яд и шипы обходят броню. Награда +8 золота."
	elif variant == 1:
		elite_id = "alchemy"
		wave_title = "Орден алхимиков"
		wave_description = "Элита: герои получают на 35% меньше урона яда. Награда +8 золота."
	else:
		elite_id = "sappers"
		wave_title = "Экспедиция сапёров"
		wave_description = "Элита: у следопыта +2 заряда обезвреживания сверх запаса волны. Награда +8 золота."


func _generate_shop() -> void:
	shop = {"goblin": 2, "spikes": 2}
	var remaining: Array[String] = ["executioner", "poison", "spider", "mimic"]
	remaining.append_array(selected_blueprints)
	for _offer in range(2):
		var index: int = rng.randi_range(0, remaining.size() - 1)
		shop[remaining[index]] = 2
		remaining.remove_at(index)


func _reorder_party(room_kind: String, announce: bool = true) -> void:
	var priority: Array[String] = ["knight", "barbarian", "rogue", "priest", "mage", "bard"]
	if room_kind != "monster":
		priority.assign(["rogue", "knight", "barbarian", "priest", "mage", "bard"])
	var ordered: Array[Dictionary] = []
	for archetype in priority:
		for hero in heroes:
			if int(hero.hp) > 0 and str(hero.id) == archetype:
				ordered.append(hero)
	for hero in heroes:
		if int(hero.hp) > 0 and not priority.has(str(hero.id)):
			ordered.append(hero)
	for hero in heroes:
		if int(hero.hp) <= 0:
			ordered.append(hero)
	heroes.assign(ordered)
	if announce and not _living().is_empty():
		var leader: Dictionary = _living()[0]
		_log("%s ведёт группу: %s." % [leader.name, "бой с защитником" if room_kind == "monster" else "проверка ловушки"])


func _spend_disarm() -> bool:
	for hero in _living():
		if str(hero.id) == "rogue" and int(hero.get("disarm_charges", 0)) > 0:
			hero.disarm_charges = int(hero.disarm_charges) - 1
			_log("Следопыт ослабляет ловушку. Зарядов осталось: %d." % int(hero.disarm_charges))
			_action("disarm", str(hero.instance_id), _defender_actor(), 1, "Следопыт ослабляет ловушку")
			return true
	return false


func _select_defender_target(survivors: Array[Dictionary], poisoned_at_start: Array[String] = []) -> Dictionary:
	if survivors.is_empty():
		return {}
	if str(defender.get("id", "")) == "mimic":
		for archetype in ["bard", "priest", "mage", "rogue", "barbarian", "knight"]:
			for hero in survivors:
				if str(hero.id) == archetype:
					return hero
	if str(defender.get("id", "")) == "executioner" and combat_tick <= 1:
		for hero in survivors:
			if int(hero.get("goblin_mark_slot", -1)) == current_slot:
				return hero
	if str(defender.get("id", "")) == "spider":
		var poisoned: Array[Dictionary] = []
		for hero in survivors:
			if int(hero.poison_ticks) > 0 or poisoned_at_start.has(str(hero.instance_id)):
				poisoned.append(hero)
		return _most_wounded(poisoned if not poisoned.is_empty() else survivors)
	if str(defender.get("id", "")) == "war_hound":
		return _most_wounded(survivors)
	for hero in survivors:
		if str(hero.id) == "knight":
			return hero
	return survivors[0]


func _defender_actor() -> String:
	return "lord" if current_slot == rooms.size() else "room_%d" % current_slot


func _action(kind: String, actor: String, target: String, amount: int, message: String) -> void:
	last_action = {"kind": kind, "actor": actor, "target": target, "amount": amount, "text": message}


func next_route_slot(index: int) -> int:
	# Slots keep their physical left-to-right IDs; traversal alternates per floor.
	if index < 0:
		return 0
	if index >= rooms.size():
		return rooms.size()
	var floor_index: int = index / SLOTS_PER_FLOOR
	var direction: int = 1 if floor_index % 2 == 0 else -1
	var next_column: int = index % SLOTS_PER_FLOOR + direction
	if next_column >= 0 and next_column < SLOTS_PER_FLOOR:
		return index + direction
	var next_floor: int = floor_index + 1
	if next_floor >= floor_count:
		return rooms.size()
	return next_floor * SLOTS_PER_FLOOR + (0 if next_floor % 2 == 0 else SLOTS_PER_FLOOR - 1)


func _enter_next_room() -> void:
	_clear_defender_effects(defender)
	current_slot = next_route_slot(current_slot)
	while current_slot < rooms.size() and rooms[current_slot].is_empty():
		current_slot = next_route_slot(current_slot)
	combat_tick = 0
	rage = 0
	for hero in heroes:
		for effect in ["shackles", "silence", "rust"]:
			hero["%s_ticks" % effect] = 0
		if int(hero.get("goblin_mark_slot", -1)) != current_slot:
			hero.erase("goblin_mark_slot")
	if current_slot >= rooms.size():
		current_slot = rooms.size()
		defender = lord
		_battle_visit("lord")
		_reorder_party("monster")
		_begin_combat_effects()
		active_target_id = str(_select_defender_target(_living()).instance_id)
		_waiting_for_entry = false
		_log("Группа вошла в тронный зал. Лорд вступает в бой!")
		_action("enter", "lord", active_target_id, 0, "Группа входит в тронный зал")
		return
	var stats: Dictionary = room_stats(current_slot)
	_battle_visit(_battle_source())
	rooms[current_slot].status = "active"
	defender = stats.duplicate(true)
	_reorder_party(str(stats.kind))
	_log("Этаж %d · комната %d: %s." % [current_slot / 5 + 1, current_slot % 5 + 1, stats.name])
	if str(stats.kind) == "monster":
		_begin_combat_effects()
		active_target_id = str(_select_defender_target(_living()).instance_id)
		_waiting_for_entry = false
		_action("enter", _defender_actor(), active_target_id, 0, "Группа входит: %s" % stats.name)
		return
	var disarmed: bool = _spend_disarm()
	_trigger_trap(stats, disarmed)
	_process_deaths()
	if _living().is_empty():
		rooms[current_slot].status = "held"
		_finish_wave()
		return
	# Traps grant exactly one status-only tick, without priest healing.
	tick += 1
	_apply_poison()
	_process_deaths()
	if _living().is_empty():
		rooms[current_slot].status = "held"
		_finish_wave()
	else:
		rooms[current_slot].status = "cleared"
		_waiting_for_entry = true


func _trigger_trap(stats: Dictionary, disarmed: bool) -> void:
	var floor_index: int = current_slot / SLOTS_PER_FLOOR
	var echo: bool = selected_relics.has("trap_echo") and not _echo_floors.has(floor_index)
	if echo:
		_echo_floors.append(floor_index)
		_log("Эхо механизмов: первая ловушка этажа срабатывает ещё раз с ослабленным эффектом.")
	if str(stats.kind) == "spikes":
		var targets: Array[Dictionary] = _living()
		var attacks_group: bool = str(stats.specialization) == "volley" or (str(stats.id) == "blade_floor" and str(stats.specialization) != "piercing")
		if not attacks_group:
			var selected_target: Dictionary = targets[targets.size() - 1] if str(stats.id) == "ballista" else targets[0]
			targets.assign([selected_target])
		for target in targets:
			var hit: int = maxi(1, ceili(float(stats.damage) * (float(stats.disarm_multiplier) if disarmed else 1.0)))
			if echo:
				hit += maxi(1, floori(float(hit) * 0.4))
			hit = _inflict_hero_damage(target, hit, _battle_source())
			active_target_id = str(target.instance_id)
			var text: String = "%s: %s теряет %d HP%s." % [stats.name, target.name, hit, " (следопыт ослабил)" if disarmed else ""]
			_log(text)
			_action("trap", _defender_actor(), active_target_id, hit, text)
	elif str(stats.kind) == "poison":
		var duration: int = mini(int(stats.disarm_poison_turns), int(stats.poison_ticks)) if disarmed else int(stats.poison_ticks)
		var targets: Array[Dictionary] = _living()
		for hero in targets:
			_apply_hero_poison(hero, int(stats.damage), duration, _battle_source())
			if str(stats.specialization) == "plague":
				hero.poison_heal_factor = 0.5
			if echo:
				_inflict_hero_damage(hero, _poison_hit(hero, maxi(1, floori(float(stats.damage) * 0.4))), _battle_source())
		active_target_id = str(targets[0].instance_id)
		var text: String = "Вся группа отравлена: %d урона × %d тиков%s." % [stats.damage, duration, " (следопыт сократил эффект)" if disarmed else ""]
		_log(text)
		_action("poison", _defender_actor(), active_target_id, int(stats.damage), text)
	elif str(stats.kind) in ["shackles", "silence", "rust"]:
		var duration: int = int(stats.effect_turns)
		if disarmed:
			duration = maxi(1, duration - 1) if str(stats.specialization) == "warded" else 1
			duration = maxi(duration, mini(int(stats.effect_turns), int(stats.disarm_control_floor)))
		if echo:
			duration = mini(6, duration + 1)
		var key: String = "pending_%s" % str(stats.kind)
		for hero in _living():
			# Repeated traps refresh the strongest duration, never add stacks.
			if duration >= int(hero.get(key, 0)):
				hero["pending_%s_source" % str(stats.kind)] = _battle_source()
			hero[key] = maxi(int(hero.get(key, 0)), duration)
			if str(stats.kind) == "rust":
				hero.rust_amount = maxi(int(hero.get("rust_amount", 0)), int(stats.effect_power))
		var targets: Array[Dictionary] = _living()
		active_target_id = str(targets[0].instance_id)
		if not bool(stats.impact_all):
			targets.resize(1)
		var impact: int = int(stats.impact_damage)
		if bool(stats.impact_all):
			impact = ceili(float(impact) * 0.6)
		if disarmed:
			impact = ceili(float(impact) * 0.4)
		var impact_total: int = 0
		for target in targets:
			impact_total += _inflict_hero_damage(target, impact, _battle_source())
		var text: String = "%s: эффект на первые %d тика следующего боя%s." % [stats.name, duration, " (следопыт ослабил)" if disarmed else ""]
		if impact_total > 0:
			text += " Удар печати: −%d HP%s." % [impact_total, " по группе" if bool(stats.impact_all) else ""]
		_log(text)
		_action("trap", _defender_actor(), active_target_id, duration, text)


func _clear_hero_control(hero: Dictionary) -> void:
	for effect in ["shackles", "silence", "rust"]:
		hero["pending_%s" % effect] = 0
		hero["%s_ticks" % effect] = 0
		hero.erase("pending_%s_source" % effect)
		hero.erase("%s_source" % effect)
	hero.rust_amount = 0


func _begin_combat_effects() -> void:
	for hero in _living():
		for effect in ["shackles", "silence", "rust"]:
			hero["%s_ticks" % effect] = int(hero.get("pending_%s" % effect, 0))
			hero["%s_source" % effect] = str(hero.get("pending_%s_source" % effect, ""))
			hero["pending_%s" % effect] = 0
			hero.erase("pending_%s_source" % effect)
	var incoming_combo: Dictionary = _outgoing_combo(_previous_route_slot(current_slot))
	if str(incoming_combo.get("id", "")) == "dungeon_cell":
		defender.cell_advantage = true
		defender.cell_source = _battle_source(int(incoming_combo.from))
		_log("Темница: страж получает первый удар, герои пропустят первую атаку.")


func _decay_hero_control() -> void:
	for hero in heroes:
		for effect in ["shackles", "silence", "rust"]:
			var key: String = "%s_ticks" % effect
			hero[key] = maxi(0, int(hero.get(key, 0)) - 1)


func _combat_step() -> void:
	tick += 1
	combat_tick += 1
	_battle_add(_battle_source(), "ticks")
	var poisoned_at_start: Array[String] = []
	for hero in _living():
		if int(hero.poison_ticks) > 0:
			poisoned_at_start.append(str(hero.instance_id))
	_apply_poison()
	_process_deaths()
	var survivors: Array[Dictionary] = _living()
	if survivors.is_empty():
		_mark_room_held()
		_finish_wave()
		return
	var healer_id: String = ""
	if combat_tick % 3 == 0:
		for hero in survivors:
			if str(hero.id) != "priest":
				continue
			var healing_target: Dictionary = _most_wounded(survivors)
			if int(healing_target.hp) < int(healing_target.max_hp):
				if int(hero.get("silence_ticks", 0)) > 0:
					_battle_add(str(hero.get("silence_source", "")), "control_actions")
					continue
				var base_heal: int = 6 + 2 * (int(hero.level) - 1)
				if int(healing_target.poison_ticks) > 0:
					base_heal = maxi(1, floori(float(base_heal) * float(healing_target.get("poison_heal_factor", 1.0))))
				var heal: int = mini(base_heal, int(healing_target.max_hp) - int(healing_target.hp))
				healing_target.hp = int(healing_target.hp) + heal
				healer_id = str(hero.instance_id)
				_log("Жрица восстановила %s %d HP." % [healing_target.name, heal])
				_action("heal", healer_id, str(healing_target.instance_id), heal, "Жрица лечит %s: +%d HP" % [healing_target.name, heal])
	var previous_rage: int = rage
	rage = 0 if combat_tick <= 40 else 1 + floori(float(combat_tick - 41) / 10.0)
	if rage > previous_rage:
		_log("Ярость защитника: +%d урона." % rage)
	var target: Dictionary = _select_defender_target(survivors, poisoned_at_start)
	active_target_id = str(target.instance_id)
	var empowered_strike: bool = false
	var ability_strike: bool = int(defender.get("ability_attacks", 0)) > 0
	var active_attack_bonus: float = float(defender.get("revenant_damage_bonus", 0.0))
	var combo_strike: bool = str(defender.get("id", "")) == "executioner" and combat_tick == 1 and int(target.get("goblin_mark_slot", -1)) == current_slot
	if combo_strike:
		_battle_add(_battle_source(), "combos")
		active_attack_bonus += 0.15
		target.erase("goblin_mark_slot")
		_log("Засада: первый удар палача по отмеченному герою +15%.")
	if current_slot < rooms.size() and combat_tick == 1 and selected_relics.has("war_banner"):
		active_attack_bonus += 0.15
	if ability_strike:
		active_attack_bonus += float(defender.get("ability_attack_bonus", 0.0))
		defender.ability_attacks = int(defender.ability_attacks) - 1
	var scaled_attack: float = float(defender.damage) * (1.0 + active_attack_bonus)
	var special_strike: String = ""
	if str(defender.id) == "ogre" and combat_tick % 3 == 0:
		scaled_attack *= 1.5
		special_strike = "Тяжёлый удар ×1,5"
		_log("Огр наносит тяжёлый третий удар: ×1,5 урона.")
	elif str(defender.id) == "war_hound" and int(target.hp) * 5 <= int(target.max_hp) * 2:
		scaled_attack *= 1.3
		special_strike = "Запах крови +30%"
		_log("Боевая гончая чует кровь: +30% урона по раненой цели.")
	if current_slot == rooms.size():
		var modifiers: Dictionary = talent_modifiers()
		if lord_strikes < int(modifiers.opening_strikes):
			scaled_attack *= float(modifiers.opening_multiplier)
			empowered_strike = true
		lord_strikes += 1
	# Add temporary attack bonuses, multiply opening wrath, then round once.
	# Rage and target armor remain outside these multipliers.
	var defender_attack: int = ceili(scaled_attack)
	defender_attack += rage
	if str(defender.id) == "spider" and poisoned_at_start.has(str(target.instance_id)):
		defender_attack += 3
		if str(_outgoing_combo(_previous_route_slot(current_slot)).get("id", "")) == "venom_hunt":
			_battle_add(_battle_source(), "combos")
	if str(defender.get("specialization", "")) == "ambush" and combat_tick == 1:
		defender_attack = ceili(float(defender_attack) * 1.75)
	var target_armor: int = int(target.armor)
	var room_armor_bypass: int = 2 if str(defender.id) == "wraith" else 0
	if int(target.get("rust_ticks", 0)) > 0:
		target_armor = maxi(0, target_armor - int(target.get("rust_amount", 1)))
		if maxi(0, target_armor - room_armor_bypass) < maxi(0, int(target.armor) - room_armor_bypass):
			_battle_add(str(target.get("rust_source", "")), "control_actions")
	target_armor = maxi(0, target_armor - room_armor_bypass)
	var outgoing: int = maxi(1, defender_attack - target_armor)
	var fighting_monster: bool = current_slot < rooms.size()
	if fighting_monster and str(target.id) == "knight":
		outgoing = maxi(1, ceili(float(outgoing) * 0.8))
	var incoming: int = 0
	var living_bard: String = ""
	var silenced_bard_source: String = ""
	var ally_attacked: bool = false
	var cell_triggered: bool = false
	for hero in survivors:
		if str(hero.id) == "bard":
			if int(hero.get("silence_ticks", 0)) == 0:
				living_bard = str(hero.instance_id)
			else:
				silenced_bard_source = str(hero.get("silence_source", ""))
	for hero in survivors:
		if str(hero.instance_id) == healer_id:
			continue
		var held_by_cell: bool = bool(defender.get("cell_advantage", false)) and combat_tick == 1
		var held_by_shackles: bool = int(hero.get("shackles_ticks", 0)) > 0 and combat_tick % 2 == 0
		if held_by_cell or held_by_shackles:
			var source: String = str(defender.get("cell_source", "")) if held_by_cell else str(hero.get("shackles_source", ""))
			_battle_add(source, "control_actions")
			cell_triggered = cell_triggered or held_by_cell
			_log("%s пропускает атаку: %s." % [hero.name, "Темница" if held_by_cell else "оковы"])
			continue
		var special_allowed: bool = int(hero.get("silence_ticks", 0)) == 0
		if str(hero.id) != "bard":
			ally_attacked = true
		var hero_attack: float = float(hero.damage)
		var armor_bypass: int = 0
		if str(hero.id) == "mage" and combat_tick % 3 == 0:
			if special_allowed:
				hero_attack *= 1.5
				armor_bypass = 1
				_log("Чародей выпускает заклинание: ×1,5 урона, обход 1 брони.")
			else:
				_battle_add(str(hero.get("silence_source", "")), "control_actions")
		if str(hero.id) == "barbarian" and int(hero.hp) * 5 <= int(hero.max_hp) * 2:
			if special_allowed:
				hero_attack *= 1.25
				_log("Раненый варвар впадает в ярость: +25% урона.")
			else:
				_battle_add(str(hero.get("silence_source", "")), "control_actions")
		if not living_bard.is_empty() and str(hero.id) != "bard":
			hero_attack *= 1.15
		var effective_armor: int = maxi(0, int(defender.armor) - armor_bypass)
		var hero_hit: int = maxi(1, ceili(hero_attack) - effective_armor)
		if fighting_monster and str(hero.id) == "knight":
			hero_hit = ceili(float(hero_hit) * 1.25)
		incoming += hero_hit
	if cell_triggered:
		_battle_add(_battle_source(), "combos")
	if living_bard.is_empty() and ally_attacked and not silenced_bard_source.is_empty():
		_battle_add(silenced_bard_source, "control_actions")
	if not living_bard.is_empty() and survivors.size() > 1:
		_log("Песня барда усиливает атаки союзников на 15%.")
	if str(defender.get("id", "")) == "goblin":
		var linked: Dictionary = _outgoing_combo(current_slot)
		if str(linked.get("id", "")) == "marked_ambush":
			for hero in heroes:
				hero.erase("goblin_mark_slot")
			target.goblin_mark_slot = int(linked.to)
			_log("Гоблины пометили %s для соседнего палача." % target.name)
	# All attacks are computed before either side loses HP.
	var old_defender_hp: int = int(defender.hp)
	outgoing = _inflict_hero_damage(target, outgoing, _battle_source())
	var absorbed: int = mini(int(defender.get("shield", 0)), incoming)
	if absorbed > 0:
		defender.shield = int(defender.shield) - absorbed
		_log("Щит %s поглотил %d урона." % [defender.name, absorbed])
	defender.hp = maxi(0, old_defender_hp - (incoming - absorbed))
	var hp_lost: int = old_defender_hp - int(defender.hp)
	var lifesteal: int = 0
	# Resolve the simultaneous reply first: blood healing never revives a killed
	# vampire, including the tick when a separate necromancer mark returns it.
	if str(defender.id) == "vampire" and int(defender.hp) > 0 and outgoing > 0:
		lifesteal = mini(ceili(float(outgoing) * 0.25), int(defender.max_hp) - int(defender.hp))
		defender.hp = int(defender.hp) + lifesteal
		if lifesteal > 0:
			_log("Вампир выпивает кровь: +%d HP от %d нанесённого урона." % [lifesteal, outgoing])
	var revived: bool = _try_revive_defender()
	if current_slot == rooms.size():
		report.lord_damage = int(report.lord_damage) + hp_lost
	else:
		rooms[current_slot].current_hp = defender.hp
	_log("%s → %s: %d урона · группа → %s: %d." % [defender.name, target.name, outgoing, defender.name, incoming])
	var action_text: String = "%s → %s: −%d HP" % [defender.name, target.name, outgoing]
	if empowered_strike:
		action_text = "Первый гнев · удар %d: %s" % [lord_strikes, action_text]
		_log(action_text)
	if ability_strike:
		action_text += " · усиление щита"
	if not special_strike.is_empty():
		action_text += " · " + special_strike
	if lifesteal > 0:
		action_text += " · кровопийство +%d HP" % lifesteal
	if revived:
		action_text += " · защитник возвращается"
	_action("attack", _defender_actor(), active_target_id, outgoing, action_text)
	last_action.incoming = incoming
	last_action.defender_hp = int(defender.hp)
	last_action.empowered = empowered_strike
	last_action.ability_empowered = ability_strike
	last_action.shield_absorbed = absorbed
	last_action.shield = int(defender.get("shield", 0))
	last_action.revived = revived
	last_action.lifesteal = lifesteal
	last_action.special_strike = special_strike
	last_action.combo = combo_strike
	last_action.bard = not living_bard.is_empty()
	if current_slot == rooms.size():
		last_action.lord_strikes = lord_strikes
		last_action.opening_remaining = opening_strikes_remaining()
	_decay_hero_control()
	_process_deaths()
	# A consumed necromancer mark has already revived the defender, if present.
	# Unprevented mutual death in the throne room is still a player defeat.
	if current_slot == rooms.size() and int(lord.hp) <= 0:
		_finish_defeat()
		return
	if _living().is_empty():
		_mark_room_held()
		_finish_wave()
		return
	if int(defender.hp) <= 0:
		rooms[current_slot].status = "cleared"
		_log("%s повержен. Герои забирают награду." % defender.name)
		_award_room_loot(defender)
		_clear_defender_effects(defender)
		_waiting_for_entry = true


func _apply_poison() -> void:
	for hero in _living():
		if int(hero.poison_ticks) <= 0:
			continue
		var damage: int = _poison_hit(hero, int(hero.poison_damage))
		damage = _inflict_hero_damage(hero, damage, str(hero.get("poison_source", "")))
		hero.poison_ticks = int(hero.poison_ticks) - 1
		_log("Яд: %s −%d HP (%d тиков осталось)." % [hero.name, damage, hero.poison_ticks])
		_action("poison", "poison", str(hero.instance_id), damage, "Яд → %s: −%d HP" % [hero.name, damage])
		if int(hero.poison_ticks) == 0:
			hero.poison_damage = 0
			hero.poison_heal_factor = 1.0
			hero.erase("poison_source")


func _process_deaths() -> void:
	var changed: bool = false
	for hero in heroes:
		if int(hero.hp) > 0 or bool(hero.death_processed):
			continue
		hero.death_processed = true
		changed = true
		hero.items = []
		var base_coins: int = 3 + floori(float(wave - 1) / 3.0)
		var coins: int = maxi(0, ceili(float(base_coins) * (1.0 + float(talent_modifiers().kill_gold))))
		var experience: int = 5 + int(hero.level)
		gold += coins
		lord.xp = int(lord.xp) + experience
		total_kills += 1
		report.killed = int(report.killed) + 1
		report.gold = int(report.gold) + coins
		report.xp = int(report.xp) + experience
		_log("%s погиб: +%d золота, +%d XP Лорду." % [hero.name, coins, experience])
	if changed:
		var current_kind: String = "monster"
		if _valid_slot(current_slot) and not rooms[current_slot].is_empty():
			current_kind = str(Content.room(str(rooms[current_slot].id)).kind)
		_reorder_party(current_kind, false)


func _award_room_loot(stats: Dictionary) -> void:
	var survivors: Array[Dictionary] = _living()
	if survivors.is_empty():
		return
	var reward: int = int(stats.xp)
	var equal_share: int = floori(float(reward) / float(survivors.size()))
	var remainder: int = reward % survivors.size()
	for index in range(survivors.size()):
		var hero: Dictionary = survivors[index]
		var share: int = equal_share + (1 if index < remainder else 0)
		hero.xp = int(hero.xp) + share
		while int(hero.xp) >= 8 + 4 * (int(hero.level) - 1):
			hero.xp = int(hero.xp) - (8 + 4 * (int(hero.level) - 1))
			hero.level = int(hero.level) + 1
			_recalculate_hero(hero)
			var level_heal: int = 15
			if int(hero.poison_ticks) > 0:
				level_heal = maxi(1, floori(float(level_heal) * float(hero.get("poison_heal_factor", 1.0))))
			hero.hp = mini(int(hero.max_hp), int(hero.hp) + level_heal)
			report.hero_levels = int(report.hero_levels) + 1
			_log("%s достиг уровня %d и восстановил до %d HP!" % [hero.name, hero.level, level_heal])
	var item_id: String = str(stats.get("item", ""))
	if item_id.is_empty():
		return
	var priority: Array[String] = ["knight", "barbarian", "rogue", "priest", "mage", "bard"]
	if item_id == "sword":
		priority.assign(["rogue", "barbarian", "knight", "mage", "bard", "priest"])
	for archetype in priority:
		for hero in survivors:
			if str(hero.id) != archetype or hero.items.has(item_id):
				continue
			hero.items.append(item_id)
			_recalculate_hero(hero)
			report.items = int(report.items) + 1
			_log("%s получает %s." % [hero.name, Content.item(item_id).name])
			return
	_log("У всех выживших уже есть %s; дубликат пропадает." % Content.item(item_id).name)


func _recalculate_hero(hero: Dictionary) -> void:
	var base: Dictionary = Content.hero(str(hero.id))
	var levels: int = int(hero.level) - 1
	var multiplier: float = float(hero.group_factor) * float(hero.pressure)
	hero.max_hp = ceili(float(int(base.hp) + 10 * levels) * multiplier * float(hero.get("deal_hp_multiplier", 1.0)))
	hero.damage = ceili(float(int(base.damage) + 2 * levels) * multiplier)
	hero.armor = int(base.armor) + int(hero.get("elite_armor", 0))
	for item_id in hero.items:
		var item_stats: Dictionary = Content.item(str(item_id))
		hero.damage = int(hero.damage) + int(item_stats.damage)
		hero.armor = int(hero.armor) + int(item_stats.armor)


func _finish_wave() -> void:
	if phase != "raid":
		return
	if int(lord.hp) <= 0:
		_finish_defeat()
		return
	_clear_defender_effects(defender)
	_clear_defender_effects(lord)
	gold += 4
	report.gold = int(report.gold) + 4
	if selected_relics.has("tithe_seal"):
		gold += 2
		report.gold = int(report.gold) + 2
		_log("Печать дани: +2 золота за отражённую волну.")
	if not elite_id.is_empty():
		gold += 8
		report.gold = int(report.gold) + 8
		_log("Элитная волна разбита: дополнительно +8 золота!")
	for unlock in unlock_catalog():
		if wave == int(unlock.wave) and not unlocked_paths.has(str(unlock.id)):
			unlocked_paths.append(str(unlock.id))
			report.unlock = str(unlock.id)
			_log("Открыто для будущих забегов: %s!" % unlock.name)
	cleared_waves += 1
	while int(lord.xp) >= 10 + 6 * (int(lord.level) - 1):
		lord.xp = int(lord.xp) - (10 + 6 * (int(lord.level) - 1))
		var previous_max_hp: int = int(lord.max_hp)
		var previous_damage: int = int(lord.damage)
		lord.level = int(lord.level) + 1
		_recalculate_lord()
		pending_upgrades += 1
		_log("Лорд достиг уровня %d! +%d HP, +%d урона и выбор таланта." % [lord.level, int(lord.max_hp) - previous_max_hp, int(lord.damage) - previous_damage])
	_pending_blueprint = wave % BLUEPRINT_WAVE_INTERVAL == 0 and not _available_blueprint_ids().is_empty()
	_pending_relic = wave % RELIC_WAVE_INTERVAL == 0 and not _available_relic_ids().is_empty()
	if tutorial_run and wave == 1:
		if int(lord.level) < 2:
			lord.level = 2
			_recalculate_lord()
		pending_upgrades = maxi(1, pending_upgrades)
		_pending_blueprint = true
		_pending_relic = true
		_log("Учебные награды: талант, чертёж и реликвия. Они действуют только в тренировке.")
	phase = "result"
	_log("Волна %d отражена! +4 золота за защиту." % wave)


func _finish_defeat() -> void:
	if phase == "defeat":
		return
	phase = "defeat"
	_clear_defender_effects(defender)
	_clear_defender_effects(lord)
	_log("Лорд пал. Пережито волн: %d · убито героев: %d." % [cleared_waves, total_kills])


func _living() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hero in heroes:
		if int(hero.hp) > 0:
			result.append(hero)
	return result


func _most_wounded(survivors: Array[Dictionary]) -> Dictionary:
	var target: Dictionary = survivors[0]
	for hero in survivors:
		# Strict comparison preserves party order when health ratios are equal.
		if float(hero.hp) / float(hero.max_hp) < float(target.hp) / float(target.max_hp):
			target = hero
	return target


func _mark_room_held() -> void:
	if _valid_slot(current_slot) and not rooms[current_slot].is_empty():
		rooms[current_slot].status = "held"


func _valid_slot(index: int) -> bool:
	return index >= 0 and index < rooms.size()


func battle_room_report() -> Array[Dictionary]:
	return _battle_rooms.duplicate(true)


func _battle_source(index: int = -2) -> String:
	var slot: int = current_slot if index == -2 else index
	if slot == rooms.size():
		return "lord"
	if not _valid_slot(slot) or rooms[slot].is_empty():
		return ""
	return "room_instance_%d" % int(rooms[slot].get("instance_id", slot))


func _begin_battle_room_report() -> void:
	_battle_rooms.clear()
	_battle_room_indices.clear()
	for index in range(rooms.size() + 1):
		if index < rooms.size() and rooms[index].is_empty():
			continue
		var source: String = _battle_source(index)
		var id: String = "lord" if index == rooms.size() else str(rooms[index].id)
		var title: String = str(lord.name) if id == "lord" else str(Content.room(id).name)
		_battle_room_indices[source] = _battle_rooms.size()
		_battle_rooms.append({
			"instance_id": source, "slot": index, "room_id": id, "name": title,
			"damage": 0, "kills": 0, "ticks": 0, "control_actions": 0, "combos": 0, "visited": false,
		})


func _battle_visit(source: String) -> void:
	if _battle_room_indices.has(source):
		_battle_rooms[int(_battle_room_indices[source])].visited = true


func _battle_add(source: String, key: String, value: int = 1) -> void:
	if not _battle_room_indices.has(source) or value <= 0:
		return
	var row: Dictionary = _battle_rooms[int(_battle_room_indices[source])]
	row[key] = int(row.get(key, 0)) + value


func _inflict_hero_damage(hero: Dictionary, raw_damage: int, source: String) -> int:
	# Count actual HP removed, never overkill, and credit the lethal hit once.
	var before: int = int(hero.hp)
	var damage: int = mini(maxi(0, raw_damage), maxi(0, before))
	hero.hp = before - damage
	_battle_add(source, "damage", damage)
	if before > 0 and int(hero.hp) == 0:
		_battle_add(source, "kills")
	return damage


func _apply_hero_poison(hero: Dictionary, damage: int, duration: int, source: String) -> void:
	# The strongest poison keeps ownership when a weaker trap refreshes its time.
	# Equal potency with a refreshed duration transfers ownership to the new source.
	if int(hero.poison_ticks) <= 0 or damage > int(hero.poison_damage) or (damage == int(hero.poison_damage) and duration >= int(hero.poison_ticks)):
		hero.poison_source = source
	hero.poison_damage = maxi(int(hero.poison_damage), damage)
	hero.poison_ticks = maxi(int(hero.poison_ticks), duration)


func _reset_report() -> void:
	report = {"killed": 0, "gold": 0, "xp": 0, "lord_damage": 0, "hero_levels": 0, "items": 0, "unlock": ""}


func _log(message: String) -> void:
	logs.append(message)
	if logs.size() > MAX_LOGS:
		logs.pop_front()

extends RefCounted
## The complete run state and deterministic battle rules. No scene or UI dependencies.

const Content = preload("res://scripts/content_catalog.gd")
const SLOTS_PER_FLOOR: int = 5
const MAX_LOGS: int = 70

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

var _waiting_for_entry: bool = true
var _instance_counter: int = 0


func _init() -> void:
	restart()


func restart(new_seed: int = 0) -> void:
	if new_seed == 0:
		rng.randomize()
		seed_value = rng.seed
	else:
		seed_value = new_seed
		rng.seed = new_seed
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


func buy_room(index: int, id: String) -> String:
	if phase != "prepare":
		return "Строительство доступно между волнами."
	if not _valid_slot(index):
		return "Выберите строительный слот."
	if not rooms[index].is_empty():
		return "Этот слот уже занят. Выберите пустое место."
	if not Content.room_ids().has(id):
		return "Такой комнаты нет."
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
	if not bool(rooms[index].used):
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
	if int(state.rank) < 2 or not str(state.get("specialization", "")).is_empty():
		return options
	var id: String = str(state.id)
	if id == "poison":
		options.assign([
			{"id": "virulent", "name": "Едкий яд", "description": "+1 урон каждого тика яда."},
			{"id": "lingering", "name": "Долгий яд", "description": "Яд действует на 3 тика дольше."},
		])
		if unlocked_paths.has("plague"):
			options.append({"id": "plague", "name": "Чума", "description": "Отравленные получают на 50% меньше лечения."})
	elif id == "spikes":
		options.assign([
			{"id": "volley", "name": "Залп", "description": "По 45% урона каждому живому герою."},
			{"id": "piercing", "name": "Пробой", "description": "+60% урона переднему герою."},
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
	return "Ветка недоступна: нужен ранг 2 и ещё не выбранная специализация."


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
	phase = "raid"
	current_slot = -1
	defender = {}
	tick = 0
	combat_tick = 0
	rage = 0
	_waiting_for_entry = true
	last_action = {}
	active_target_id = ""
	_reset_report()
	for hero in heroes:
		hero.disarm_charges = int(hero.get("disarm_max", 2 if str(hero.id) == "rogue" else 0))
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
	current_slot = -1
	defender = {}
	combat_tick = 0
	rage = 0
	last_action = {}
	active_target_id = ""
	for room in rooms:
		if not room.is_empty():
			room.status = "ready"
	_generate_party()
	_generate_shop()
	phase = "level_up" if pending_upgrades > 0 else "prepare"
	_log("Приближается волна %d. Подготовьте подземелье." % wave)
	return ""


func choose_upgrade(id: String) -> String:
	if phase != "level_up" or pending_upgrades <= 0:
		return "Сейчас нет доступных усилений."
	if not upgrades.has(id):
		return "Неизвестное усиление."
	upgrades[id] = int(upgrades[id]) + 1
	pending_upgrades -= 1
	var names: Dictionary = {
		"hp": "Крепкие прислужники: +10% HP существ",
		"damage": "Жестокие прислужники: +10% урона существ",
		"trap": "Опасные ловушки: +10% урона яда и шипов",
	}
	_log(str(names[id]))
	if pending_upgrades == 0:
		phase = "prepare"
	return ""


func room_stats(index: int) -> Dictionary:
	if not _valid_slot(index) or rooms[index].is_empty():
		return {}
	var state: Dictionary = rooms[index]
	var result: Dictionary = Content.room(str(state.id)).duplicate(true)
	var rank: int = int(state.rank)
	var rank_factor: float = 1.0 + 0.25 * float(rank - 1)
	var is_monster: bool = str(result.kind) == "monster"
	var hp_factor: float = 1.0 + 0.1 * float(upgrades.hp)
	var damage_factor: float = 1.0 + 0.1 * float(upgrades.damage if is_monster else upgrades.trap)
	var floor_index: int = index / SLOTS_PER_FLOOR
	var floor_trait: String = floor_traits[floor_index] if floor_index < floor_traits.size() else "plain"
	var specialization: String = str(state.get("specialization", ""))
	var duration: int = 6
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
	}
	if specialization == "fury":
		hp_factor *= 0.9
		damage_factor *= 1.3
	elif specialization == "bulwark":
		hp_factor *= 1.4
		damage_factor *= 0.9
	elif specialization == "volley":
		damage_factor *= 0.45
	elif specialization == "piercing":
		damage_factor *= 1.6
	elif specialization == "lingering":
		duration += 3
	result.hp = ceili(float(result.hp) * rank_factor * hp_factor) if is_monster else 0
	result.max_hp = result.hp
	result.damage = ceili(float(result.damage) * rank_factor * damage_factor)
	if specialization == "virulent":
		result.damage = int(result.damage) + 1
	result.xp = int(result.xp) + 2 * (rank - 1) if is_monster else 0
	result.rank = rank
	result.invested = state.invested
	result.used = state.used
	result.specialization = specialization
	result.branch = str(branch_names.get(specialization, ""))
	result.floor_trait = floor_trait
	result.poison_ticks = duration
	result.role = "Атакует переднего героя"
	if str(state.id) == "mimic":
		result.role = "Охотится на жрицу и следопыта в тылу"
	elif str(state.id) == "spider":
		result.role = "Добивает слабейшего, предпочитает отравленных"
	elif str(state.id) == "poison":
		result.role = "Отравляет всю группу на %d тиков" % duration
	elif str(state.id) == "spikes":
		result.role = "Бьёт всю группу" if specialization == "volley" else "Бьёт переднего героя в обход брони"
	result.status = state.get("status", "ready")
	result.current_hp = int(state.get("current_hp", result.hp)) if phase in ["raid", "result", "defeat"] else int(result.hp)
	return result


func floor_cost() -> int:
	var next_floor: int = floor_count + 1
	return 5 * next_floor * next_floor


func heal_cost() -> int:
	return 6 + 2 * floori(float(wave - 1) / 5.0)


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
	var ordered_ids: Array[String] = ["knight", "rogue", "priest"]
	var party_ids: Array[String] = []
	if wave <= 3:
		party_ids.append(ordered_ids[rng.randi_range(0, 2)])
	elif wave <= 7:
		var omitted: int = rng.randi_range(0, 2)
		for index in range(3):
			if index != omitted:
				party_ids.append(ordered_ids[index])
	else:
		party_ids.assign(ordered_ids)
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
			"elite_modifier": wave_description if not elite_id.is_empty() else "",
			"death_processed": false, "group_factor": group_factor,
			"pressure": pressure, "icon": definition.icon, "color": definition.color,
			"trait": definition.trait,
		}
		_recalculate_hero(hero)
		hero.hp = hero.max_hp
		heroes.append(hero)
	if elite_id.is_empty():
		wave_description = "Одиночный приключенец" if heroes.size() == 1 else "Группа из %d героев: роли дополняют друг друга" % heroes.size()


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
	for _offer in range(2):
		var index: int = rng.randi_range(0, remaining.size() - 1)
		shop[remaining[index]] = 2
		remaining.remove_at(index)


func _reorder_party(room_kind: String, announce: bool = true) -> void:
	var priority: Array[String] = ["knight", "rogue", "priest"]
	if room_kind != "monster":
		priority.assign(["rogue", "knight", "priest"])
	var ordered: Array[Dictionary] = []
	for archetype in priority:
		for hero in heroes:
			if int(hero.hp) > 0 and str(hero.id) == archetype:
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
		for archetype in ["priest", "rogue", "knight"]:
			for hero in survivors:
				if str(hero.id) == archetype:
					return hero
	if str(defender.get("id", "")) == "spider":
		var poisoned: Array[Dictionary] = []
		for hero in survivors:
			if int(hero.poison_ticks) > 0 or poisoned_at_start.has(str(hero.instance_id)):
				poisoned.append(hero)
		return _most_wounded(poisoned if not poisoned.is_empty() else survivors)
	for hero in survivors:
		if str(hero.id) == "knight":
			return hero
	return survivors[0]


func _defender_actor() -> String:
	return "lord" if current_slot == rooms.size() else "room_%d" % current_slot


func _action(kind: String, actor: String, target: String, amount: int, message: String) -> void:
	last_action = {"kind": kind, "actor": actor, "target": target, "amount": amount, "text": message}


func _enter_next_room() -> void:
	current_slot += 1
	while current_slot < rooms.size() and rooms[current_slot].is_empty():
		current_slot += 1
	combat_tick = 0
	rage = 0
	if current_slot >= rooms.size():
		current_slot = rooms.size()
		defender = lord
		_reorder_party("monster")
		active_target_id = str(_select_defender_target(_living()).instance_id)
		_waiting_for_entry = false
		_log("Группа вошла в тронный зал. Лорд вступает в бой!")
		_action("enter", "lord", active_target_id, 0, "Группа входит в тронный зал")
		return
	var stats: Dictionary = room_stats(current_slot)
	rooms[current_slot].status = "active"
	defender = stats.duplicate(true)
	_reorder_party(str(stats.kind))
	_log("Этаж %d · комната %d: %s." % [current_slot / 5 + 1, current_slot % 5 + 1, stats.name])
	if str(stats.kind) == "monster":
		active_target_id = str(_select_defender_target(_living()).instance_id)
		_waiting_for_entry = false
		_action("enter", _defender_actor(), active_target_id, 0, "Группа входит: %s" % stats.name)
		return
	var disarmed: bool = _spend_disarm()
	if str(stats.kind) == "spikes":
		var targets: Array[Dictionary] = _living()
		if str(stats.specialization) != "volley":
			targets.resize(1)
		for target in targets:
			var hit: int = maxi(1, ceili(float(stats.damage) * (0.4 if disarmed else 1.0)))
			target.hp = maxi(0, int(target.hp) - hit)
			active_target_id = str(target.instance_id)
			var text: String = "Шипы: %s теряет %d HP%s." % [target.name, hit, " (обезврежены на 60%)" if disarmed else ""]
			_log(text)
			_action("trap", _defender_actor(), active_target_id, hit, text)
	elif str(stats.kind) == "poison":
		var duration: int = mini(3, int(stats.poison_ticks)) if disarmed else int(stats.poison_ticks)
		for hero in _living():
			hero.poison_ticks = maxi(int(hero.poison_ticks), duration)
			hero.poison_damage = maxi(int(hero.poison_damage), int(stats.damage))
			if str(stats.specialization) == "plague":
				hero.poison_heal_factor = 0.5
		active_target_id = str(_living()[0].instance_id)
		var text: String = "Вся группа отравлена: %d урона × %d тиков%s." % [stats.damage, duration, " (следопыт сократил эффект)" if disarmed else ""]
		_log(text)
		_action("poison", _defender_actor(), active_target_id, int(stats.damage), text)
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


func _combat_step() -> void:
	tick += 1
	combat_tick += 1
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
	var defender_attack: int = int(defender.damage) + rage
	if str(defender.id) == "spider" and poisoned_at_start.has(str(target.instance_id)):
		defender_attack += 3
	if str(defender.get("specialization", "")) == "ambush" and combat_tick == 1:
		defender_attack = ceili(float(defender_attack) * 1.75)
	var outgoing: int = maxi(1, defender_attack - int(target.armor))
	var fighting_monster: bool = current_slot < rooms.size()
	if fighting_monster and str(target.id) == "knight":
		outgoing = maxi(1, ceili(float(outgoing) * 0.8))
	var incoming: int = 0
	for hero in survivors:
		if str(hero.instance_id) != healer_id:
			var hero_hit: int = maxi(1, int(hero.damage) - int(defender.armor))
			if fighting_monster and str(hero.id) == "knight":
				hero_hit = ceili(float(hero_hit) * 1.25)
			incoming += hero_hit
	# All attacks are computed before either side loses HP.
	var old_defender_hp: int = int(defender.hp)
	target.hp = maxi(0, int(target.hp) - outgoing)
	defender.hp = maxi(0, old_defender_hp - incoming)
	if current_slot == rooms.size():
		report.lord_damage = int(report.lord_damage) + old_defender_hp - int(defender.hp)
	else:
		rooms[current_slot].current_hp = defender.hp
	_log("%s → %s: %d урона · группа → %s: %d." % [defender.name, target.name, outgoing, defender.name, incoming])
	_action("attack", _defender_actor(), active_target_id, outgoing, "%s → %s: −%d HP" % [defender.name, target.name, outgoing])
	last_action.incoming = incoming
	last_action.defender_hp = int(defender.hp)
	_process_deaths()
	# Mutual death in the throne room is always a player defeat.
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
		_waiting_for_entry = true


func _apply_poison() -> void:
	for hero in _living():
		if int(hero.poison_ticks) <= 0:
			continue
		var damage: int = int(hero.poison_damage)
		damage = maxi(1, floori(float(damage) * float(hero.get("poison_resistance", 1.0))))
		hero.hp = maxi(0, int(hero.hp) - damage)
		hero.poison_ticks = int(hero.poison_ticks) - 1
		_log("Яд: %s −%d HP (%d тиков осталось)." % [hero.name, damage, hero.poison_ticks])
		_action("poison", "poison", str(hero.instance_id), damage, "Яд → %s: −%d HP" % [hero.name, damage])
		if int(hero.poison_ticks) == 0:
			hero.poison_damage = 0
			hero.poison_heal_factor = 1.0


func _process_deaths() -> void:
	var changed: bool = false
	for hero in heroes:
		if int(hero.hp) > 0 or bool(hero.death_processed):
			continue
		hero.death_processed = true
		changed = true
		hero.items = []
		var coins: int = 3 + floori(float(wave - 1) / 3.0)
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
	var priority: Array[String] = ["knight", "rogue", "priest"]
	if item_id == "sword":
		priority.assign(["rogue", "knight", "priest"])
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
	hero.max_hp = ceili(float(int(base.hp) + 10 * levels) * multiplier)
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
	gold += 4
	report.gold = int(report.gold) + 4
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
		lord.level = int(lord.level) + 1
		lord.max_hp = int(lord.max_hp) + 10
		lord.damage = int(lord.damage) + 1
		lord.hp = mini(int(lord.max_hp), int(lord.hp) + 10)
		pending_upgrades += 1
		_log("Лорд достиг уровня %d! +10 HP, +1 урона и выбор усиления." % int(lord.level))
	phase = "result"
	_log("Волна %d отражена! +4 золота за защиту." % wave)


func _finish_defeat() -> void:
	if phase == "defeat":
		return
	phase = "defeat"
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


func _reset_report() -> void:
	report = {"killed": 0, "gold": 0, "xp": 0, "lord_damage": 0, "hero_levels": 0, "items": 0, "unlock": ""}


func _log(message: String) -> void:
	logs.append(message)
	if logs.size() > MAX_LOGS:
		logs.pop_front()

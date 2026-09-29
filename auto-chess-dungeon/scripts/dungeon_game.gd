extends RefCounted
## The complete run state and deterministic battle rules. No scene or UI dependencies.

const Content = preload("res://scripts/content_catalog.gd")
const SLOTS_PER_FLOOR: int = 5
const MAX_LOGS: int = 70

var phase: String = "prepare"
var wave: int = 1
var gold: int = 18
var floor_count: int = 1
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
	for _slot in range(SLOTS_PER_FLOOR):
		rooms.append({})
	_log("Куплен этаж %d: ещё 5 мест перед тронным залом." % floor_count)
	return ""


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
	_reset_report()
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
	result.hp = ceili(float(result.hp) * rank_factor * hp_factor) if is_monster else 0
	result.max_hp = result.hp
	result.damage = ceili(float(result.damage) * rank_factor * damage_factor)
	result.xp = int(result.xp) + 2 * (rank - 1) if is_monster else 0
	result.rank = rank
	result.invested = state.invested
	result.used = state.used
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
	for id in party_ids:
		var definition: Dictionary = Content.hero(id)
		var hero: Dictionary = {
			"id": id, "instance_id": "%d_%s" % [wave, id],
			"name": definition.name, "level": starting_level, "xp": 0,
			"hp": 0, "max_hp": 0, "damage": 0, "armor": 0,
			"items": [], "poison_ticks": 0, "poison_damage": 0,
			"death_processed": false, "group_factor": group_factor,
			"pressure": pressure, "icon": definition.icon, "color": definition.color,
			"trait": definition.trait,
		}
		_recalculate_hero(hero)
		hero.hp = hero.max_hp
		heroes.append(hero)


func _generate_shop() -> void:
	shop = {"goblin": 2, "spikes": 2}
	var remaining: Array[String] = ["executioner", "poison", "spider", "mimic"]
	for _offer in range(2):
		var index: int = rng.randi_range(0, remaining.size() - 1)
		shop[remaining[index]] = 2
		remaining.remove_at(index)


func _enter_next_room() -> void:
	current_slot += 1
	while current_slot < rooms.size() and rooms[current_slot].is_empty():
		current_slot += 1
	combat_tick = 0
	rage = 0
	if current_slot >= rooms.size():
		current_slot = rooms.size()
		defender = lord
		_waiting_for_entry = false
		_log("Группа вошла в тронный зал. Лорд вступает в бой!")
		return
	var stats: Dictionary = room_stats(current_slot)
	rooms[current_slot].status = "active"
	defender = stats.duplicate(true)
	_log("Этаж %d · комната %d: %s." % [current_slot / 5 + 1, current_slot % 5 + 1, stats.name])
	if str(stats.kind) == "monster":
		_waiting_for_entry = false
		return
	if str(stats.kind) == "spikes":
		var target: Dictionary = _living()[0]
		var hit: int = int(stats.damage)
		if str(target.id) == "rogue":
			hit = ceili(float(hit) / 2.0)
		target.hp = maxi(0, int(target.hp) - hit)
		_log("Шипы: %s теряет %d HP." % [target.name, hit])
	elif str(stats.kind) == "poison":
		for hero in _living():
			hero.poison_ticks = maxi(int(hero.poison_ticks), 6)
			hero.poison_damage = maxi(int(hero.poison_damage), int(stats.damage))
		_log("Вся группа отравлена: %d урона × 6 тиков." % int(stats.damage))
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
				var heal: int = mini(6 + 2 * (int(hero.level) - 1), int(healing_target.max_hp) - int(healing_target.hp))
				healing_target.hp = int(healing_target.hp) + heal
				healer_id = str(hero.instance_id)
				_log("Жрица восстановила %s %d HP." % [healing_target.name, heal])
	var previous_rage: int = rage
	rage = 0 if combat_tick <= 40 else 1 + floori(float(combat_tick - 41) / 10.0)
	if rage > previous_rage:
		_log("Ярость защитника: +%d урона." % rage)
	var target: Dictionary = survivors[0]
	var defender_attack: int = int(defender.damage) + rage
	if str(defender.id) == "spider" and poisoned_at_start.has(str(target.instance_id)):
		defender_attack += 3
	var outgoing: int = maxi(1, defender_attack - int(target.armor))
	var incoming: int = 0
	for hero in survivors:
		if str(hero.instance_id) != healer_id:
			incoming += maxi(1, int(hero.damage) - int(defender.armor))
	# All attacks are computed before either side loses HP.
	var old_defender_hp: int = int(defender.hp)
	target.hp = maxi(0, int(target.hp) - outgoing)
	defender.hp = maxi(0, old_defender_hp - incoming)
	if current_slot == rooms.size():
		report.lord_damage = int(report.lord_damage) + old_defender_hp - int(defender.hp)
	else:
		rooms[current_slot].current_hp = defender.hp
	_log("%s → %s: %d урона · группа → %s: %d." % [defender.name, target.name, outgoing, defender.name, incoming])
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
		hero.hp = maxi(0, int(hero.hp) - damage)
		hero.poison_ticks = int(hero.poison_ticks) - 1
		_log("Яд: %s −%d HP (%d тиков осталось)." % [hero.name, damage, hero.poison_ticks])
		if int(hero.poison_ticks) == 0:
			hero.poison_damage = 0


func _process_deaths() -> void:
	for hero in heroes:
		if int(hero.hp) > 0 or bool(hero.death_processed):
			continue
		hero.death_processed = true
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
			hero.hp = mini(int(hero.max_hp), int(hero.hp) + 15)
			report.hero_levels = int(report.hero_levels) + 1
			_log("%s достиг уровня %d и восстановил до 15 HP!" % [hero.name, hero.level])
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
	hero.armor = int(base.armor)
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
	report = {"killed": 0, "gold": 0, "xp": 0, "lord_damage": 0, "hero_levels": 0, "items": 0}


func _log(message: String) -> void:
	logs.append(message)
	if logs.size() > MAX_LOGS:
		logs.pop_front()

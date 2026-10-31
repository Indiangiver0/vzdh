extends RefCounted
## The complete run state and deterministic battle rules. No scene or UI dependencies.

const Content = preload("res://scripts/content_catalog.gd")
const RunSkills = preload("res://scripts/run_skill_catalog.gd")
const Lords = preload("res://scripts/lord_catalog.gd")
const Expedition = preload("res://scripts/expedition_catalog.gd")
const Realm = preload("res://scripts/realm_catalog.gd")
const Evolutions = preload("res://scripts/room_evolution_catalog.gd")
const HeroRules = preload("res://scripts/hero_rules.gd")
const EncounterRules = preload("res://scripts/encounter_rules.gd")
const CampRules = preload("res://scripts/camp_rules.gd")
const LabyrinthRules = preload("res://scripts/labyrinth_rules.gd")
const SLOTS_PER_FLOOR: int = 5
const MAX_LOGS: int = 70
const RELIC_WAVE_INTERVAL: int = 10
const BLUEPRINT_WAVE_INTERVAL: int = 7

signal run_souls_changed(total: int, delta: int)
signal run_skill_learned(id: String)

var run_souls: int = 0
var learned_skills: Dictionary = {}
var run_skill_runtime: Dictionary = {}
var soul_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var soul_failures: int = 0
var _skill_preparation: Dictionary = {}
var _greed_remainder: int = 0
var _trophy_metal: bool = false
var _ability_price_snapshot: int = 0
var _ability_income_snapshot: int = 0
var _camp_state: Dictionary = {}
var _camp_processed_floors: Dictionary = {}
var _camp_interruptions: int = 0
var phase: String = "prepare"
var wave: int = 1
var gold: int = LabyrinthRules.STARTING_GOLD
var floor_count: int = 1
var floor_traits: Array[String] = ["plain"]
var pending_floor: int = -1
var rooms: Array[Dictionary] = []
var heroes: Array[Dictionary] = []
var lord: Dictionary = {}
var upgrades: Dictionary = {"hp": 0, "damage": 0, "trap": 0}
var selected_talents: Dictionary = {}
# Legacy pending_upgrades/talent_offers are kept only for in-memory migration.
var skill_points: int = 0
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
var defenders: Array[Dictionary] = []
var combat_events: Array[Dictionary] = []
var action_seq: int = 0
var _encounter = EncounterRules.new()
var tick: int = 0
var combat_tick: int = 0
var rage: int = 0
var report: Dictionary = {}
var total_kills: int = 0
var cleared_waves: int = 0
var pending_upgrades: int = 0
var unlocked_paths: Array[String] = []
var wave_is_boss: bool = false
var boss_id: String = ""
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
var labyrinth_enabled: bool = true
var current_place: int = -1
var visit_id: int = 0
var _route_from_place: int = -1
var movement_mode: String = "exploring"
var last_completed_wave: int = 0
var last_defended_wave: int = 0
var defended_waves: Array[int] = []
var defeated_special_waves: Array[int] = []
var _labyrinth = LabyrinthRules.new()
var _loot_shares: Dictionary = {}
var _treasury_robbed: bool = false
var _departure_checked: bool = false
var _camp_processed_places: Dictionary = {}

var _waiting_for_entry: bool = true
var _instance_counter: int = 0
var _has_started_raid: bool = false
var _lord_ability_values: Dictionary = {}
var _pending_blueprint: bool = false
var _pending_relic: bool = false
var _talent_reward_pending: bool = false
var _echo_floors: Array[int] = []
var _deal_state: Dictionary = {}
var _battle_rooms: Array[Dictionary] = []
var _battle_room_indices: Dictionary = {}


func _init(initialize_run: bool = true) -> void:
	# Read-only progression previews create an unstarted calculation snapshot.
	if initialize_run:
		restart()


func restart(new_seed: int = 0) -> void:
	if new_seed == 0:
		rng.randomize()
		seed_value = rng.seed
	else:
		seed_value = new_seed
		rng.seed = new_seed
	# Keep the legacy stream isolated; tree choices no longer draw random offers.
	talent_rng.seed = seed_value ^ 0x54A1E17
	expedition_rng.seed = seed_value ^ 0x73D19A2
	deal_rng.seed = seed_value ^ 0x4D3A115
	soul_rng.seed = seed_value ^ 0x5A01721
	run_souls = 0
	learned_skills.clear()
	run_skill_runtime.clear()
	soul_failures = 0
	_skill_preparation.clear()
	_greed_remainder = 0
	_trophy_metal = false
	_ability_price_snapshot = 0
	_ability_income_snapshot = 0
	_reset_camps()
	_deal_state.clear()
	_battle_rooms.clear()
	_battle_room_indices.clear()
	tutorial_run = false
	labyrinth_enabled = true
	_labyrinth.reset_layout()
	current_place = -1
	visit_id = 0
	_route_from_place = -1
	movement_mode = "exploring"
	last_completed_wave = 0
	last_defended_wave = 0
	defended_waves.clear()
	defeated_special_waves.clear()
	_loot_shares.clear()
	_treasury_robbed = false
	_departure_checked = false
	selected_blueprints.clear()
	selected_relics.clear()
	blueprint_offers.clear()
	relic_offers.clear()
	_pending_blueprint = false
	_pending_relic = false
	_talent_reward_pending = false
	_echo_floors.clear()
	phase = "prepare"
	wave = 1
	gold = LabyrinthRules.STARTING_GOLD
	floor_count = 1
	floor_traits.assign(["plain"])
	pending_floor = -1
	rooms.clear()
	for _slot in range(_labyrinth.positions.size()):
		rooms.append({})
	heroes.clear()
	lord = {
		"id": "lord", "name": "Лорд Подземелья", "hp": 120, "max_hp": 120,
		"damage": 10, "armor": 1, "level": 1, "xp": 0,
	}
	upgrades = {"hp": 0, "damage": 0, "trap": 0}
	selected_talents.clear()
	skill_points = 0
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
	defenders.clear()
	_encounter = EncounterRules.new()
	combat_events.clear()
	action_seq = 0
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
	_recalculate_lord()
	_generate_party()
	_generate_shop()
	_log("Подземелье открыто. Постройте защиту и запустите первую волну.")


func prepare_linear_showcase() -> void:
	# Caller has just restarted a disposable title-screen/capture run.
	labyrinth_enabled = false
	floor_count = 1
	floor_traits.assign(["plain"])
	pending_floor = -1
	current_slot = -1
	current_place = -1
	rooms.clear()
	for _slot in range(SLOTS_PER_FLOOR):
		rooms.append({})


func begin_tutorial() -> void:
	# A disposable run: the caller must exclude it from permanent rewards.
	restart(7102026)
	tutorial_run = true
	labyrinth_enabled = false
	rooms.clear()
	for _slot in range(SLOTS_PER_FLOOR):
		rooms.append({})
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
	if not learned_skills.is_empty() and not lord_archetype.is_empty() and id != lord_archetype:
		return "После покупки навыков Владыка закреплён за текущим забегом."
	lord_archetype = id
	lord_mastery = int(values.mastery)
	lord_variant = str(values.variant)
	# Mastery and variant are snapshots: profile changes cannot alter a running raid.
	_lord_ability_values = values.duplicate(true)
	ability_charges = 2
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
	var next_cast: int = int(run_skill_runtime.get("q_casts", 0)) + 1 if phase in ["raid", "camp"] else 1
	var next_great: float = 0.2 if next_cast == 2 and has_run_skill("ritual_great_ritual") else 0.0
	if not _lord_ability_values.is_empty():
		if lord_archetype == "fallen_knight":
			description = "Щит: %d%% максимального HP защитника." % roundi(float(_lord_ability_values.shield_fraction) * (1.0 + next_great + (0.1 if has_run_skill("ritual_knightly_ritual") else 0.0)) * 100.0)
			if int(_lord_ability_values.empowered_attacks) > 0:
				description += " Следующие %d удара: +%d%% урона." % [_lord_ability_values.empowered_attacks, roundi(float(_lord_ability_values.attack_bonus) * 100.0)]
		elif lord_archetype == "necromancer":
			description = "Метка возвращает защитника после смертельного удара с %d%% HP." % roundi(minf(1.0, float(_lord_ability_values.revive_fraction) * (1.0 + next_great + (0.1 if has_run_skill("ritual_necrotic_bond") else 0.0))) * 100.0)
			if float(_lord_ability_values.revive_damage_bonus) > 0.0:
				description += " После возвращения: +%d%% урона до конца комнаты." % roundi(float(_lord_ability_values.revive_damage_bonus) * 100.0)
		elif lord_archetype == "plague_alchemist":
			description = "Вся группа: яд %.2f × %d тиков. Уже отравленным — вспышка %.2f до защиты от яда." % [float(_lord_ability_values.poison_damage) * (1.0 + float(run_skill_modifiers().get("poison_damage", 0.0)) + next_great), poison_application_duration(_scaled_poison_duration(int(_lord_ability_values.poison_ticks))), float(_lord_ability_values.burst_damage) * (1.25 if has_run_skill("ritual_plague_reaction") else 1.0)]
	var effect_parts: Array[String] = []
	if int(defender.get("shield", 0)) > 0:
		effect_parts.append("Щит %d" % int(defender.shield))
	if int(defender.get("ability_attacks", 0)) > 0:
		effect_parts.append("Усиленных ударов: %d" % int(defender.ability_attacks))
	if bool(defender.get("revive_mark", false)):
		effect_parts.append("Метка возвращения: %d%% HP" % roundi(float(defender.revive_fraction) * 100.0))
	if float(defender.get("revenant_damage_bonus", 0.0)) > 0.0:
		effect_parts.append("Возвращённый: +%d%% урона" % roundi(float(defender.revenant_damage_bonus) * 100.0))
	if int(defender.get("run_impulse_count", 0)) > 0:
		effect_parts.append("Ритуальных импульсов: %d" % int(defender.run_impulse_count))
	if int(defender.get("run_cover_shield", 0)) > 0:
		effect_parts.append("Покров: %d" % int(defender.run_cover_shield))
	if bool(defender.get("run_barrier", false)):
		effect_parts.append("Барьер от заклинания")
	var reason: String = _ability_block_reason()
	return {
		"name": name, "description": description, "charges": ability_charges,
		"max_charges": 2 if not _lord_ability_values.is_empty() else 0,
		"gold_cost": ability_gold_cost(), "base_income": base_wave_income(),
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
	if gold < ability_gold_cost():
		return "Не хватает золота: нужно %d." % ability_gold_cost()
	if _waiting_for_entry or defender.is_empty() or int(defender.get("hp", 0)) <= 0 or _living().is_empty():
		return "Дождитесь боя с живым защитником."
	if int(defender.get("delay", 0)) > 0:
		return "Защитник ещё выходит из-за решётки."
	if current_slot < 0 or current_slot > rooms.size():
		return "Сейчас нет активного боя."
	if current_slot < rooms.size() and str(defender.get("kind", "")) != "monster":
		return "Способность применяется в боевой комнате или тронном зале."
	if lord_archetype == "fallen_knight" and (int(defender.get("shield", 0)) - int(defender.get("run_cover_shield", 0)) > 0 or int(defender.get("ability_attacks", 0)) > 0):
		return "У этого защитника ещё действует предыдущий щит или усиление."
	if lord_archetype == "necromancer" and bool(defender.get("revive_mark", false)):
		return "Этот защитник уже отмечен для возвращения."
	return ""


func base_wave_income() -> int:
	if _ability_income_snapshot > 0 and phase in ["raid", "camp", "result", "defeat"]:
		return _ability_income_snapshot
	return heroes.size() * (3 + floori(float(wave - 1) / 3.0)) + 4


func ability_gold_cost() -> int:
	if _ability_price_snapshot > 0 and phase in ["raid", "camp", "result", "defeat"]:
		return _ability_price_snapshot
	var discounts: int = int(has_run_skill("ritual_economy_1")) + int(has_run_skill("ritual_economy_2")) + int(has_run_skill("ritual_economy_3"))
	# Integer numerator avoids a spurious extra coin at exact float boundaries.
	return maxi(1, ceili(float(base_wave_income() * (100 - 5 * discounts)) / 200.0))


func cast_ability() -> String:
	var reason: String = _ability_block_reason()
	if not reason.is_empty():
		return reason
	var price: int = ability_gold_cost()
	var casts: int = int(run_skill_runtime.get("q_casts", 0)) + 1
	var great: float = 0.2 if casts == 2 and has_run_skill("ritual_great_ritual") else 0.0
	gold -= price
	ability_charges -= 1
	run_skill_runtime.q_casts = casts
	var message: String = ""
	var amount: int = 0
	var target_id: String = _defender_actor()
	if lord_archetype == "fallen_knight":
		var bonus: float = great + (0.1 if has_run_skill("ritual_knightly_ritual") else 0.0)
		var shield: int = maxi(1, ceili(float(defender.max_hp) * float(_lord_ability_values.shield_fraction) * (1.0 + bonus)))
		defender.shield = shield + int(defender.get("run_cover_shield", 0))
		defender.ability_attacks = int(_lord_ability_values.empowered_attacks)
		defender.ability_attack_bonus = float(_lord_ability_values.attack_bonus)
		amount = shield
		message = "%s: щит +%d, усиленных ударов %d." % [defender.name, shield, defender.ability_attacks]
	elif lord_archetype == "necromancer":
		var bonus: float = great + (0.1 if has_run_skill("ritual_necrotic_bond") else 0.0)
		defender.revive_mark = true
		defender.revive_fraction = minf(1.0, float(_lord_ability_values.revive_fraction) * (1.0 + bonus))
		defender.revive_damage_bonus = float(_lord_ability_values.revive_damage_bonus)
		amount = maxi(1, ceili(float(defender.max_hp) * float(defender.revive_fraction)))
		message = "%s отмечен: смертельный удар вернёт его с %d HP." % [defender.name, amount]
	# Ritual statuses are attached before a lethal alchemist burst ends the battle.
	if has_run_skill("ritual_impulse"):
		defender.run_impulse_count = 2 if has_run_skill("ritual_echo") else 1
		defender.run_impulse_bonus = 0.15 if has_run_skill("ritual_enhanced_impulse") else 0.1
		if has_run_skill("ritual_on_the_edge") and not bool(run_skill_runtime.get("edge_used", false)) and float(defender.hp) < float(defender.max_hp) * 0.3:
			defender.run_edge_bonus = 0.15
			run_skill_runtime.edge_used = true
	if casts == 1:
		if has_run_skill("ritual_cover"):
			var cover: int = maxi(1, ceili(float(defender.max_hp) * (0.07 if has_run_skill("ritual_dense_cover") else 0.05)))
			defender.run_cover_shield = cover
			defender.shield = int(defender.get("shield", 0)) + cover
		if has_run_skill("ritual_barrier"):
			defender.run_barrier = true
	_encounter.sync_primary(self)
	if lord_archetype == "plague_alchemist":
		var targets: Array[Dictionary] = _living()
		var poison_aura: float = _poison_aura_multiplier()
		var duration: int = _scaled_poison_duration(int(_lord_ability_values.poison_ticks))
		var burst_total: int = 0
		for hero in targets:
			if int(hero.hp) <= 0:
				continue
			var was_poisoned: bool = int(hero.poison_ticks) > 0
			if was_poisoned:
				var burst_power: float = float(_lord_ability_values.burst_damage) * (1.0 + (0.25 if has_run_skill("ritual_plague_reaction") else 0.0))
				burst_total += _inflict_hero_damage(hero, _poison_hit(hero, burst_power, poison_aura), "lord")
			else:
				hero.poison_heal_factor = 1.0
			if int(hero.hp) > 0:
				_apply_hero_poison(hero, float(_lord_ability_values.poison_damage), duration, "lord", great)
		amount = burst_total
		target_id = str(targets[0].instance_id)
		active_target_id = target_id
		message = "Чумная волна: яд всей группе; вспышка %d урона уже отравленным." % burst_total
		_process_deaths()
		if _living().is_empty():
			_mark_room_held()
			_finish_wave()
	message += " Потрачено %d золота." % price
	_log(message)
	_action("ability", "lord", target_id, amount, message)
	last_action.lord_archetype = lord_archetype
	last_action.charges = ability_charges
	last_action.gold_cost = price
	return ""


func _clear_defender_effects(target: Dictionary) -> void:
	if target.is_empty():
		return
	for key in ["shield", "ability_attacks", "ability_attack_bonus", "revive_mark", "revive_fraction", "revive_damage_bonus", "revenant_damage_bonus", "run_impulse_count", "run_impulse_bonus", "run_edge_bonus", "run_barrier", "run_cover_shield"]:
		target.erase(key)


func _scaled_poison_duration(base_ticks: int) -> int:
	return maxi(1, ceili(float(base_ticks) * (1.0 + float(talent_modifiers().poison_duration) + float(lord_passive_modifiers().poison_duration))))


func poison_application_duration(base_duration: int) -> int:
	return base_duration + int(has_run_skill("poison_stable_formula")) + (2 if has_run_skill("poison_long_poison") else 0)


func _poison_aura_multiplier() -> float:
	if int(_encounter.effects.get("aura_suppressed", 0)) > 0:
		return 1.0
	for hero in _living():
		if str(hero.id) == "priest" and int(hero.get("silence_ticks", 0)) == 0 and int(hero.get("cocoon_ticks", 0)) == 0:
			return 0.75
	return 1.0


func _poison_hit(hero: Dictionary, raw_damage: float, aura_multiplier: float = 1.0) -> int:
	# Callers snapshot the aura before a group hit, so a priest dying during
	# that same hit cannot change protection according to party order.
	var resistance: float = float(hero.get("poison_resistance", 1.0))
	var multiplier: float = maxf(0.5, resistance * aura_multiplier)
	if aura_multiplier < 1.0 and has_run_skill("poison_penetrating_venom"):
		var without_priest: float = maxf(0.5, resistance)
		multiplier = without_priest - (without_priest - multiplier) * 0.9
	# Fractions accumulate per target until whole HP can be removed. Application,
	# comparison, maturity and consumption keep the original floating strength.
	var exact: float = maxf(0.0, raw_damage) * multiplier + float(hero.get("run_poison_damage_carry", 0.0))
	var damage: int = floori(exact + 0.000001)
	hero.run_poison_damage_carry = maxf(0.0, exact - float(damage))
	return damage


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
	if is_treasury_slot(index) or is_throne_slot(index):
		return "Казна и трон занимают отдельные места."
	if not rooms[index].is_empty():
		return "Этот слот уже занят. Выберите пустое место."
	if reserved_room_slots().has(index):
		return "Это место занимает пасть живой комнаты."
	if not Content.room_ids().has(id):
		return "Такой комнаты нет."
	if Expedition.blueprint_ids().has(id) and not selected_blueprints.has(id):
		return "Сначала выберите чертёж этой комнаты после волны."
	if int(shop.get(id, 0)) <= 0:
		return "Запас этой комнаты на текущую волну закончился."
	var definition: Dictionary = Content.room(id)
	var price: int = shop_room_cost(id)
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
	_consume_building_discounts(rooms[index])
	_log("%s: построено в клетке %s." % [definition.name, str(_labyrinth.positions[index])] if labyrinth_enabled else "%s: построено, этаж %d · место %d." % [definition.name, index / 5 + 1, index % 5 + 1])
	return ""


func move_room(from_index: int, to_index: int) -> String:
	if phase != "prepare":
		return "Перестановка доступна между волнами."
	if not _valid_slot(from_index) or not _valid_slot(to_index):
		return "Выберите два строительных слота."
	if is_treasury_slot(to_index) or is_throne_slot(to_index) or is_treasury_slot(from_index) or is_throne_slot(from_index):
		return "Переместите казну или трон отдельным действием."
	if rooms[from_index].is_empty():
		return "Сначала выберите построенную комнату."
	if from_index == to_index:
		return ""
	var reserved: Dictionary = reserved_room_slots()
	if reserved.has(to_index) and int(reserved[to_index]) != from_index:
		return "Это место занимает пасть живой комнаты."
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
	if has_run_skill("traps_workshop") and str(stats.kind) != "monster" and not bool(rooms[index].get("run_workshop_used", false)):
		rooms[index].run_workshop_used = true
	if _trophy_metal:
		_trophy_metal = false
	if has_run_skill("economy_military_order"):
		_skill_preparation.military_used = true
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
	if not bool(rooms[index].used) and int(rooms[index].get("run_discount_wave", -1)) == wave:
		if bool(rooms[index].get("run_supply_used", false)):
			_skill_preparation.supply_used = false
		if bool(rooms[index].get("run_contract_used", false)):
			_skill_preparation.contract_available = true
	gold += refund
	rooms[index] = {}
	_log("%s: возвращено %d золота." % [Content.room(id).name, refund])
	return ""


func buy_floor() -> String:
	if labyrinth_enabled:
		return buy_depth_access()
	if phase != "prepare":
		return "Этаж можно купить между волнами."
	var price: int = floor_cost()
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	gold -= price
	if has_run_skill("economy_construction_contract") and not bool(_skill_preparation.get("contract_granted", false)):
		_skill_preparation.contract_granted = true
		_skill_preparation.contract_available = true
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
	if not str(state.get("evolution_path", "")).is_empty():
		return options
	for path in Evolutions.paths(str(state.id)):
		options.append(Evolutions.stage(str(path.id), 2).duplicate(true))
	return options


func _specialization_definitions(id: String, include_locked: bool = false) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if id == "poison":
		options.assign([
			{"id": "virulent", "name": "Едкий яд", "description": "+1 урон каждого тика яда."},
			{"id": "lingering", "name": "Долгий яд", "description": "Яд действует на 3 тика дольше."},
		])
		if include_locked or unlocked_paths.has("plague"):
			options.append({"id": "plague", "name": "Чума", "description": "Отравленные получают на 50% меньше лечения.", "unlock_id": "plague", "unlock_wave": 10})
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
		if id == "mimic" and (include_locked or unlocked_paths.has("ambush")):
			options.append({"id": "ambush", "name": "Засада", "description": "Первый удар мимика по тылу наносит +75% урона.", "unlock_id": "ambush", "unlock_wave": 5})
	return options


func specialize_room(index: int, id: String) -> String:
	if not Evolutions.node(id).is_empty():
		return choose_room_evolution(index, id)
	if phase != "prepare":
		return "Ветку комнаты выбирают между волнами."
	for option in specialization_options(index):
		if str(option.id) == id:
			rooms[index].specialization = id
			_log("%s: выбрана ветка «%s»." % [Content.room(str(rooms[index].id)).name, option.name])
			return ""
	return "Ветка недоступна: нужен ранг 2 и ещё не выбранная специализация."


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
	if str(state.get("specialization", "")).is_empty() or not str(state.get("evolution_path", "")).is_empty():
		var path: String = str(state.get("evolution_path", ""))
		var current: int = int(state.get("evolution_stage", 0))
		if path.is_empty():
			return specialization_options(index)
		for required in [5, 15]:
			if current < required:
				if int(state.rank) >= required:
					result.append(Evolutions.stage(path, required).duplicate(true))
				return result
		return result
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
		if not Evolutions.node(id).is_empty():
			rooms[index].evolution_path = str(option.path_id)
			rooms[index].evolution_stage = int(option.tier)
			_log("%s: %s." % [Content.room(str(rooms[index].id)).name, option.name])
			return ""
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
	if str(state.get("specialization", "")).is_empty() or not str(state.get("evolution_path", "")).is_empty():
		var path: String = str(state.get("evolution_path", ""))
		var stages_new: Array[Dictionary] = []
		var next: int = 0
		for required in [2, 5, 15]:
			var chosen: bool = int(state.get("evolution_stage", 0)) >= required
			if not chosen and next == 0:
				next = required
			var definition: Dictionary = Evolutions.stage(path, required)
			stages_new.append({"tier": required, "rank_required": required, "chosen": chosen, "id": str(definition.get("id", "")), "name": str(definition.get("name", "Выбор пути")), "description": str(definition.get("description", "Выберите, во что превратится комната.")), "available": not chosen and next == required and int(state.rank) >= required})
		return {"rank": int(state.rank), "specialization": path, "stages": stages_new, "next_tier": next}
	var stages: Array[Dictionary] = []
	var next_tier: int = 0
	var specialization: String = str(state.get("specialization", ""))
	var evolutions: Dictionary = state.get("evolutions", {})
	for tier in [1, 5, 15]:
		var display_rank: int = 2 if tier == 1 else tier
		var id: String = specialization if tier == 1 else str(evolutions.get(str(tier), ""))
		var chosen: bool = not id.is_empty()
		if not chosen and next_tier == 0:
			next_tier = display_rank
		var title: String = "Выбор ветки" if tier == 1 else "Развитие комнаты"
		var description: String = ""
		if chosen:
			title = str(room_stats(index).branch) if tier == 1 else str(Realm.evolution(id).get("name", id))
			if tier == 1:
				for option in _specialization_definitions(str(state.id), true):
					if str(option.id) == id:
						description = str(option.description)
			else:
				description = str(Realm.evolution(id).get("description", ""))
		stages.append({"tier": tier, "rank_required": display_rank, "name": title, "description": description, "chosen": chosen, "id": id, "available": not chosen and next_tier == display_rank and int(state.rank) >= display_rank})
	return {"rank": int(state.rank), "specialization": specialization, "stages": stages, "next_tier": next_tier}


func room_tree(index: int) -> Array[Dictionary]:
	# Occurrence IDs include ancestors: a shared terminal effect can be displayed
	# below two different paths without suggesting that both parents are required.
	var nodes: Array[Dictionary] = []
	if not _valid_slot(index) or rooms[index].is_empty():
		return nodes
	var state: Dictionary = rooms[index]
	if str(state.get("specialization", "")).is_empty() or not str(state.get("evolution_path", "")).is_empty():
		return _evolution_tree(index)
	var definition: Dictionary = Content.room(str(state.id))
	var root_id: String = "room:%s" % str(state.get("instance_id", 0))
	var stats: Dictionary = room_stats(index)
	nodes.append({
		"id": root_id, "effect_id": "", "instance_id": state.get("instance_id", 0),
		"parents": [], "path": [], "depth": 0, "tier": 0, "rank_required": 1,
		"name": str(definition.name), "description": "Построена. Ранг %d." % int(state.rank),
		"icon": str(definition.get("icon", "")), "state": "acquired",
		"status": "Ранг %d" % int(state.rank), "can_buy": false,
		"preview": {"before": stats.duplicate(true), "after": stats.duplicate(true), "rank": int(state.rank), "projected": false},
	})
	for first in _specialization_definitions(str(state.id), true):
		var first_path: Array[String] = [str(first.id)]
		var first_node: Dictionary = _room_tree_node(index, first, first_path, root_id, first)
		nodes.append(first_node)
		for middle in Realm.evolution_options(str(definition.kind), str(first.id), 5):
			var middle_path: Array[String] = [str(first.id), str(middle.id)]
			var middle_node: Dictionary = _room_tree_node(index, middle, middle_path, str(first_node.id), first)
			nodes.append(middle_node)
			for last in Realm.evolution_options(str(definition.kind), str(first.id), 15, str(middle.id)):
				var last_path: Array[String] = [str(first.id), str(middle.id), str(last.id)]
				nodes.append(_room_tree_node(index, last, last_path, str(middle_node.id), first))
	return nodes


func _evolution_tree(index: int) -> Array[Dictionary]:
	var room: Dictionary = rooms[index]
	var root_id: String = "room:%s" % str(room.get("instance_id", index))
	var base: Dictionary = Content.room(str(room.id))
	var stats: Dictionary = room_stats(index)
	var nodes: Array[Dictionary] = [{"id": root_id, "effect_id": "", "parents": [], "path": [], "depth": 0, "tier": 0, "rank_required": 1, "name": base.name, "description": "Комната ранга %d" % int(room.rank), "icon": base.icon, "state": "acquired", "status": "Построена", "can_buy": false, "preview": {"before": stats, "after": stats, "rank": int(room.rank), "projected": false}}]
	var chosen_path: String = str(room.get("evolution_path", ""))
	var chosen_stage: int = int(room.get("evolution_stage", 0))
	for path in Evolutions.paths(str(room.id)):
		var parent: String = root_id
		var chain: Array[String] = []
		var depth: int = 0
		for required in [2, 5, 15]:
			depth += 1
			var node: Dictionary = Evolutions.stage(str(path.id), required).duplicate(true)
			var acquired: bool = chosen_path == str(path.id) and chosen_stage >= required
			var other: bool = not chosen_path.is_empty() and chosen_path != str(path.id)
			var prerequisites: bool = required == 2 or (chosen_path == str(path.id) and chosen_stage >= (2 if required == 5 else 5))
			var available: bool = not acquired and not other and prerequisites and int(room.rank) >= required and phase == "prepare"
			var status: String = "Выбрано" if acquired else ("Другая ветвь" if other else ("Бесплатное развитие" if available else ("Нужен ранг %d" % required if int(room.rank) < required else "Сначала предыдущая ступень")))
			var effect_id: String = str(node.id)
			chain.append(effect_id)
			var node_id: String = root_id + "/" + effect_id
			var preview: Dictionary = room.duplicate(true)
			preview.rank = maxi(int(room.rank), required)
			preview.evolution_path = str(path.id)
			preview.evolution_stage = required
			node.merge({"id": node_id, "effect_id": effect_id, "parents": [parent], "path": chain.duplicate(), "depth": depth, "rank_required": required, "icon": base.icon, "state": "acquired" if acquired else ("other_branch" if other else ("available" if available else "locked")), "status": status, "can_buy": available, "preview": {"before": stats, "after": _room_stats_for_state(index, preview), "rank": int(preview.rank), "projected": true}}, true)
			nodes.append(node)
			parent = node_id
	return nodes


func reserved_room_slots() -> Dictionary:
	var result: Dictionary = {}
	for slot in range(rooms.size()):
		if rooms[slot].is_empty() or str(rooms[slot].get("evolution_path", "")) != "mimic_living_chamber":
			continue
		var stage: int = int(rooms[slot].get("evolution_stage", 2))
		var limit: int = 2 if stage >= 15 else (1 if stage >= 5 else 0)
		var neighbors: Array = layout_neighbors(slot) if labyrinth_enabled else [slot - 1, slot + 1]
		for n in neighbors:
			if limit <= 0:
				break
			if n < 0 or n >= rooms.size() or layout_effect_scope(n) != layout_effect_scope(slot) or is_treasury_slot(n) or is_throne_slot(n) or not rooms[n].is_empty() or result.has(n):
				continue
			result[n] = slot
			limit -= 1
	return result


func throne_guard_room_slot() -> int:
	var selected: int = -1
	var strongest: float = -1.0
	var candidates: Array[int] = []
	if labyrinth_enabled:
		for index in range(rooms.size()):
			candidates.append(index)
	else:
		var cursor: int = next_route_slot(-1)
		while cursor < rooms.size():
			candidates.append(cursor)
			cursor = next_route_slot(cursor)
	for slot in candidates:
		if not rooms[slot].is_empty() and str(rooms[slot].get("evolution_path", "")) == "wraith_throne_guardian":
			var stats: Dictionary = room_stats(slot)
			var strength: float = float(stats.hp) * float(stats.get("evolution_params", {}).get("reserve_hp_factor", 1.0))
			if strength > strongest:
				strongest = strength
				selected = slot
	return selected


func room_evolution_controls(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _valid_slot(index) or rooms[index].is_empty() or int(rooms[index].get("evolution_stage", 0)) < 15:
		return result
	var room: Dictionary = rooms[index]
	if str(room.get("evolution_path", "")) == "wraith_twilight_hall":
		result.append({"id": "spirit_direction", "label": "Призрачный покров", "selected": str(room.get("spirit_direction", "next")), "options": [{"id": "next", "name": "Следующий сосед"}, {"id": "previous", "name": "Предыдущий сосед"}]})
	if str(room.get("evolution_path", "")) == "vampire_sire":
		var memory: Dictionary = room.get("evolution_memory", {})
		var choices: Array[Dictionary] = []
		for id in memory.get("thrall_candidates", []):
			choices.append({"id": str(id), "name": str(Content.hero(str(id)).get("name", id))})
		if not choices.is_empty() and int(memory.get("thrall_wave", 0)) == wave:
			result.append({"id": "thrall_class", "label": "Слуга этой волны", "selected": str(memory.get("thrall", choices[0].id)), "options": choices})
	return result


func set_room_evolution_control(index: int, control_id: String, value: String) -> String:
	if phase != "prepare":
		return "Настройка доступна между волнами."
	for control in room_evolution_controls(index):
		if str(control.id) != control_id:
			continue
		for option in control.options:
			if str(option.id) != value:
				continue
			if control_id == "spirit_direction":
				rooms[index].spirit_direction = value
			else:
				rooms[index].evolution_memory.thrall = value
			return ""
	return "Такой вариант сейчас недоступен."


func _room_tree_node(index: int, definition: Dictionary, path: Array[String], parent_id: String, first: Dictionary) -> Dictionary:
	var room: Dictionary = rooms[index]
	var evolutions: Dictionary = room.get("evolutions", {})
	var selected_path: Array[String] = [
		str(room.get("specialization", "")), str(evolutions.get("5", "")), str(evolutions.get("15", "")),
	]
	var tier: int = int(definition.get("tier", 1))
	var rank_required: int = 2 if tier == 1 else tier
	var acquired: bool = true
	var parents_chosen: bool = true
	var other_branch: bool = false
	for step_index in range(path.size()):
		if selected_path[step_index] != path[step_index]:
			acquired = false
			if step_index < path.size() - 1:
				parents_chosen = false
		if not selected_path[step_index].is_empty() and selected_path[step_index] != path[step_index]:
			other_branch = true
	var unlock_id: String = str(first.get("unlock_id", ""))
	# Existing choices remain valid even if an older profile lacks their unlock.
	var unlocked: bool = unlock_id.is_empty() or unlocked_paths.has(unlock_id) or selected_path[0] == path[0]
	var node_state: String = "locked"
	var status: String = ""
	var can_buy: bool = false
	if acquired:
		node_state = "acquired"
		status = "Выбрано"
	elif not unlocked:
		status = "Победите волну %d" % int(first.get("unlock_wave", 0))
	elif other_branch:
		node_state = "other_branch"
		status = "Другая ветвь"
	elif int(room.rank) < rank_required:
		status = "Нужен ранг %d" % rank_required
	elif not parents_chosen:
		status = "Сначала выберите предыдущую ступень"
	elif phase != "prepare":
		status = "Выбор между волнами"
	else:
		node_state = "available"
		status = "Бесплатный выбор"
		can_buy = true
	var projected_rank: int = maxi(int(room.rank), rank_required)
	var before_room: Dictionary = room.duplicate(true)
	before_room.rank = projected_rank
	before_room.specialization = ""
	before_room.evolutions = {}
	for step_index in range(path.size() - 1):
		_set_room_path_step(before_room, step_index, path[step_index])
	var after_room: Dictionary = before_room.duplicate(true)
	_set_room_path_step(after_room, path.size() - 1, path[path.size() - 1])
	var node_id: String = "room:%s/%s" % [str(room.get("instance_id", 0)), "/".join(path)]
	return {
		"id": node_id, "effect_id": str(definition.id), "instance_id": room.get("instance_id", 0),
		"parents": [parent_id], "path": path.duplicate(), "depth": path.size(),
		"tier": tier, "rank_required": rank_required, "name": str(definition.name),
		"description": str(definition.description), "icon": str(Content.room(str(room.id)).get("icon", "")),
		"state": node_state, "status": status, "can_buy": can_buy,
		"unlock_id": unlock_id, "unlock_wave": int(first.get("unlock_wave", 0)),
		"preview": {
			"before": _room_stats_for_state(index, before_room), "after": _room_stats_for_state(index, after_room),
			"rank": projected_rank, "projected": projected_rank != int(room.rank) or not parents_chosen or other_branch,
		},
	}


func _set_room_path_step(state: Dictionary, step_index: int, id: String) -> void:
	if step_index == 0:
		state.specialization = id
	else:
		state.evolutions["5" if step_index == 1 else "15"] = id


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
	result.price = _discounted_room_price(int(_deal_state.price))
	return result


func buy_deal_room(index: int) -> String:
	if phase != "prepare" or _deal_state.is_empty() or bool(_deal_state.get("accepted", false)):
		return "Сейчас нет доступной сделки."
	if not _valid_slot(index) or not rooms[index].is_empty():
		return "Для сделки выберите пустое место."
	if is_treasury_slot(index) or is_throne_slot(index):
		return "Казна и трон занимают отдельные места."
	if reserved_room_slots().has(index):
		return "Это место занимает пасть живой комнаты."
	var price: int = _discounted_room_price(int(_deal_state.price))
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	gold -= price
	_instance_counter += 1
	rooms[index] = {
		"id": str(_deal_state.room_id), "rank": int(_deal_state.rank), "invested": price, "used": false,
		"instance_id": _instance_counter, "status": "ready", "specialization": "", "deal_wave": wave,
	}
	_consume_building_discounts(rooms[index])
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
	var restored: int = paid_heal_amount()
	lord.hp = int(lord.hp) + restored
	_log("Лорд восстановил %d HP." % restored)
	return ""


func start_raid() -> String:
	if phase != "prepare":
		return "Сначала завершите текущую волну и выберите усиления."
	if int(lord.hp) <= 0:
		return "Лорд погиб. Начните новый забег."
	if labyrinth_enabled:
		var layout_error: String = _layout_validation_error()
		if not layout_error.is_empty():
			return layout_error
	migrate_legacy_talents()
	# Unspent points are banked; they are not a pending reward on the next wave.
	_talent_reward_pending = false
	_ability_income_snapshot = base_wave_income()
	_ability_price_snapshot = ability_gold_cost()
	run_skill_runtime.clear()
	_reset_camps()
	_has_started_raid = true
	_clear_defender_effects(defender)
	_clear_defender_effects(lord)
	ability_charges = 2 if not _lord_ability_values.is_empty() else 0
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
	current_place = -1
	visit_id = 0
	_route_from_place = -1
	movement_mode = "exploring"
	_loot_shares.clear()
	_treasury_robbed = false
	_departure_checked = false
	if labyrinth_enabled:
		_labyrinth.begin_wave(seed_value, wave, heroes)
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
	_encounter.start_wave(self)
	_log("Волна %d: героев в группе — %d." % [wave, heroes.size()])
	return ""


func step() -> void:
	if phase != "raid":
		return
	last_action = {}
	combat_events.clear()
	if int(lord.hp) <= 0:
		_finish_defeat()
		return
	if _living().is_empty():
		_finish_wave()
		return
	_encounter.advance_recovery(self)
	if _waiting_for_entry:
		_enter_next_room()
	else:
		_combat_step()
	if phase == "raid" and _waiting_for_entry:
		_try_start_route_camp()


func next_wave() -> String:
	if phase != "result":
		return "Текущая волна ещё не завершена."
	wave += 1
	current_place = -1
	movement_mode = "exploring"
	_reset_camps()
	_skill_preparation.clear()
	_ability_price_snapshot = 0
	_ability_income_snapshot = 0
	_encounter.next_wave(self)
	_clear_defender_effects(defender)
	defenders.clear()
	_encounter = EncounterRules.new()
	ability_charges = 2 if not _lord_ability_values.is_empty() else 0
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
	# Compatibility entry point: the model validates the same tree prerequisites.
	return choose_talent(id)


func migrate_legacy_talents() -> void:
	# Legacy talent points have no exchange rate into the run's soul wallet.
	selected_talents.clear()
	skill_points = 0
	pending_upgrades = 0
	talent_offers.clear()
	_talent_reward_pending = false
	if phase == "level_up":
		phase = "prepare"


func has_run_skill(id: String) -> bool:
	return bool(learned_skills.get(id, false))


func run_skill_definition(id: String) -> Dictionary:
	return RunSkills.get_skill(id)


func run_skill_number(id: String, key: String, fallback: float = 0.0) -> float:
	return RunSkills.get_number(id, key, fallback)


func run_skill_modifiers() -> Dictionary:
	return RunSkills.modifiers(learned_skills)


func run_skill_state(id: String) -> Dictionary:
	var node: Dictionary = run_skill_definition(id).duplicate(true)
	if node.is_empty():
		return {"id": id, "learned": false, "available": false, "reason": "Неизвестный навык."}
	var requirements: Dictionary = node.get("requirements", {})
	var all_of: Array = node.get("requires_all", requirements.get("all_of", []))
	var any_of: Array = node.get("requires_any", requirements.get("any_of", []))
	var parent: String = str(node.get("parent", ""))
	if all_of.is_empty() and any_of.is_empty() and not parent.is_empty() and parent != "start":
		all_of = [parent]
	node.requires_all = all_of.duplicate()
	node.requires_any = any_of.duplicate()
	node.parents = node.get("parents", all_of if not all_of.is_empty() else any_of).duplicate()
	node.mode = str(node.get("mode", "any" if all_of.is_empty() and not any_of.is_empty() else "all"))
	node.cost = int(node.get("cost", node.get("soul_price", 0)))
	node.required_lord = str(node.get("required_lord", ""))
	node.description = _layout_skill_description(id, str(node.get("description", "")))
	node.category = str(node.get("category", ""))
	node.x = float(node.get("x", 0.0))
	node.y = float(node.get("y", 0.0))
	node.position = Vector2(node.x, node.y)
	node.learned = has_run_skill(id)
	var reason: String = ""
	if bool(node.learned):
		reason = "Уже изучено в этом забеге."
	elif labyrinth_enabled and id == "traps_hidden_drive":
		reason = "Скрытый привод временно недоступен: его новый эффект после переделки обезвреживания ещё не выбран."
	elif phase != "prepare":
		reason = "Покупка навыков доступна между волнами."
	elif not str(node.required_lord).is_empty() and str(node.required_lord) != lord_archetype:
		reason = "Нужен Владыка: %s." % str(Lords.get_lord(str(node.required_lord)).get("name", node.required_lord))
	else:
		for required in all_of:
			if str(required) != "start" and not has_run_skill(str(required)):
				reason = "Сначала изучите: %s." % str(run_skill_definition(str(required)).get("name", required))
				break
		if reason.is_empty() and not any_of.is_empty():
			var met: bool = false
			for required in any_of:
				met = met or str(required) == "start" or has_run_skill(str(required))
			if not met:
				reason = "Нужно изучить хотя бы один соединённый навык."
		if reason.is_empty() and run_souls < int(node.cost):
			reason = "Не хватает душ: нужно %d." % int(node.cost)
	node.reason = reason
	node.available = reason.is_empty()
	node.can_buy = node.available
	return node


func run_skill_tree() -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	for definition in RunSkills.all_skills():
		nodes.append(run_skill_state(str(definition.id)))
	return nodes


func buy_run_skill(id: String) -> bool:
	var state: Dictionary = run_skill_state(id)
	if not bool(state.get("available", false)):
		return false
	# Validation above and mutations below are one synchronous model action.
	run_souls -= int(state.cost)
	learned_skills[id] = true
	_recalculate_lord()
	_log("Изучено: %s · −%d душ. Навык действует до конца забега." % [state.name, state.cost])
	run_souls_changed.emit(run_souls, -int(state.cost))
	run_skill_learned.emit(id)
	return true


func choose_talent(id: String) -> String:
	var state: Dictionary = run_skill_state(id)
	return "" if buy_run_skill(id) else str(state.get("reason", "Не удалось изучить навык."))


func defer_talents() -> String:
	migrate_legacy_talents()
	return ""


func talent_options() -> Array[Dictionary]:
	return run_skill_tree()


func talent_tree() -> Array[Dictionary]:
	return run_skill_tree()


func talent_preview(id: String) -> Dictionary:
	if run_skill_definition(id).is_empty():
		return {}
	var snapshot: Variant = _progression_snapshot()
	var before: Dictionary = snapshot._progression_metrics()
	snapshot.learned_skills[id] = true
	snapshot._recalculate_lord()
	return {"before": before, "after": snapshot._progression_metrics()}


func _progression_snapshot() -> Variant:
	# No restart, random draw, save operation or reference to live mutable data.
	var snapshot: Variant = get_script().new(false)
	snapshot.labyrinth_enabled = labyrinth_enabled
	_labyrinth.copy_layout_to(snapshot._labyrinth)
	snapshot.phase = phase
	snapshot.wave = wave
	snapshot.floor_count = floor_count
	snapshot.floor_traits.assign(floor_traits)
	snapshot.rooms.assign(rooms.duplicate(true))
	snapshot.lord = lord.duplicate(true)
	snapshot.upgrades = upgrades.duplicate(true)
	snapshot.learned_skills = learned_skills.duplicate(true)
	snapshot._skill_preparation = _skill_preparation.duplicate(true)
	snapshot._trophy_metal = _trophy_metal
	snapshot.selected_relics.assign(selected_relics)
	snapshot._lord_ability_values = _lord_ability_values.duplicate(true)
	return snapshot


func _progression_metrics() -> Dictionary:
	var modifiers: Dictionary = talent_modifiers()
	var room_values: Array[Dictionary] = []
	for index in range(rooms.size()):
		if rooms[index].is_empty():
			continue
		var stats: Dictionary = room_stats(index)
		stats.slot = index
		room_values.append(stats)
	var base_coins: int = 3 + floori(float(wave - 1) / 3.0)
	var opening_multiplier: float = float(modifiers.opening_multiplier) if int(modifiers.opening_strikes) > 0 else 1.0
	return {
		"lord_hp": int(lord.hp), "lord_max_hp": int(lord.max_hp),
		"lord_damage": int(lord.damage), "lord_armor": int(lord.armor),
		"floor_cost": floor_cost(), "heal_cost": heal_cost(),
		"kill_gold": maxi(0, ceili(float(base_coins) * (1.0 + float(modifiers.kill_gold)))),
		"poison_ticks": _scaled_poison_duration(8),
		"opening_strikes": int(modifiers.opening_strikes),
		"opening_damage": ceili(float(lord.damage) * opening_multiplier),
		"modifiers": modifiers, "rooms": room_values,
	}


func _advance_reward_choice() -> void:
	migrate_legacy_talents()
	_talent_reward_pending = false
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
			relic_offers.assign(_draw_relic_choices())
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
		if str(definition.get("kind", "passive")) == "instant" or not selected_relics.has(id):
			available.append(id)
	return available


func _draw_relic_choices() -> Array[String]:
	var passives: Array[String] = []
	var instants: Array[String] = []
	for definition in Expedition.relics():
		var id: String = str(definition.id)
		if str(definition.get("kind", "passive")) == "instant":
			# Filter only while drawing. Reading an issued offer never replaces it.
			if str(definition.get("effect", "")) == "lord_heal" and _instant_relic_amount(definition) <= 0:
				continue
			instants.append(id)
		elif not selected_relics.has(id):
			passives.append(id)
	var choices: Array[String] = []
	for _offer in range(mini(2, passives.size())):
		var index: int = expedition_rng.randi_range(0, passives.size() - 1)
		choices.append(passives[index])
		passives.remove_at(index)
	while choices.size() < 3 and not instants.is_empty():
		var index: int = expedition_rng.randi_range(0, instants.size() - 1)
		choices.append(instants[index])
		instants.remove_at(index)
	return choices


func _instant_relic_amount(definition: Dictionary) -> int:
	match str(definition.get("effect", "")):
		"gold", "run_souls":
			return maxi(0, int(definition.get("amount", 0)))
		"lord_heal":
			if int(lord.get("hp", 0)) <= 0:
				return 0
			var capacity: int = maxi(0, int(lord.max_hp) - int(lord.hp))
			return mini(capacity, ceili(float(lord.max_hp) * float(definition.get("heal_fraction", 0.0))))
	return 0


func relic_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for id in relic_offers:
		var definition: Dictionary = Expedition.relic(id)
		if definition.is_empty():
			continue
		var kind: String = str(definition.get("kind", "passive"))
		if kind == "passive" and selected_relics.has(id):
			continue
		definition.kind = kind
		definition.status = "offered"
		if kind == "instant":
			definition.actual_amount = _instant_relic_amount(definition)
			if str(definition.get("effect", "")) == "lord_heal":
				definition.description = "Сразу восстановить %d HP Владыки: до 50%% максимума с округлением вверх, без превышения максимального HP. Не воскрешает." % int(definition.actual_amount)
		options.append(definition)
	return options


func choose_relic(id: String) -> String:
	if phase != "relic" or not _pending_relic:
		return "Сейчас нет доступной реликвии."
	if not relic_offers.has(id) or not _available_relic_ids().has(id):
		return "Выберите одну из предложенных реликвий."
	var definition: Dictionary = Expedition.relic(id)
	var instant: bool = str(definition.get("kind", "passive")) == "instant"
	var effect: String = str(definition.get("effect", ""))
	if instant and effect not in ["gold", "lord_heal", "run_souls"]:
		return "У этой реликвии нет доступного эффекта."
	if instant and effect == "lord_heal" and int(lord.hp) <= 0:
		return "Кубок не может воскресить погибшего Владыку."
	var amount: int = _instant_relic_amount(definition) if instant else 0
	# Consume this saved offer before mutation/signals: a repeated selection cannot pay twice.
	relic_offers.clear()
	_pending_relic = false
	if instant:
		match effect:
			"gold":
				gold += amount
				_log("%s: +%d золота." % [definition.name, amount])
			"lord_heal":
				lord.hp = int(lord.hp) + amount
				_log("%s: восстановлено %d HP Владыки." % [definition.name, amount])
			"run_souls":
				run_souls += amount
				_log("%s: +%d души текущего забега." % [definition.name, amount])
				run_souls_changed.emit(run_souls, amount)
	else:
		selected_relics.append(id)
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
	if labyrinth_enabled:
		if phase in ["raid", "camp"] and index == current_slot:
			if _valid_slot(_route_from_place) and _labyrinth.neighbors(current_place).has(_route_from_place) and layout_effect_scope(current_place) == layout_effect_scope(_route_from_place):
				var source: int = int(reserved_room_slots().get(_route_from_place, _route_from_place))
				return source if source != index else -1
			return -1
		return layout_previous_neighbor(index)
	if not _valid_slot(index):
		return -1
	var floor_index: int = index / SLOTS_PER_FLOOR
	var previous: int = index - (1 if floor_index % 2 == 0 else -1)
	return previous if _valid_slot(previous) and previous / SLOTS_PER_FLOOR == floor_index else -1


func _outgoing_combo(index: int) -> Dictionary:
	if not _valid_slot(index) or rooms[index].is_empty():
		return {}
	var following: int = layout_next_neighbor(index) if labyrinth_enabled else next_route_slot(index)
	if not _valid_slot(following) or rooms[following].is_empty() or layout_effect_scope(index) != layout_effect_scope(following):
		return {}
	for definition in combo_catalog():
		if str(rooms[index].id) == str(definition.first) and str(rooms[following].id) == str(definition.second):
			var link: Dictionary = definition.duplicate(true)
			link["from"] = index
			link["to"] = following
			return link
	return {}


func talent_modifiers() -> Dictionary:
	# Compatibility read API: only the new one-purchase tree contributes.
	var modifiers: Dictionary = {
		"lord_hp": 0.0, "lord_damage": 0.0, "lord_armor": 0.0,
		"monster_hp": 0.0, "monster_damage": 0.0, "trap_damage": 0.0,
		"spike_damage": 0.0, "poison_duration": 0.0, "kill_gold": 0.0,
		"hero_room_xp": 0.0, "floor_cost": 0.0, "heal_cost": 0.0,
		"opening_strikes": 0.0, "opening_multiplier": 1.0,
	}
	var skill_modifiers: Dictionary = run_skill_modifiers()
	for key in skill_modifiers:
		modifiers[key] = float(skill_modifiers[key])
	modifiers.trap_damage = float(modifiers.get("direct_trap_damage", 0.0))
	if has_run_skill("creatures_frenzied_servants"):
		modifiers.monster_hp = float(modifiers.monster_hp) - 0.08
	if has_run_skill("economy_greed"):
		modifiers.kill_gold = 0.2
		modifiers.hero_room_xp = 0.15
	modifiers.floor_cost = -0.05 * (int(has_run_skill("economy_building_estimate")) + int(has_run_skill("economy_building_estimate_2")))
	modifiers.heal_cost = -0.1 if has_run_skill("economy_court_healer") else 0.0
	return modifiers


func opening_strikes_remaining() -> int:
	return 0


func _recalculate_lord() -> void:
	var old_hp: int = int(lord.hp)
	var damage_taken: int = maxi(0, int(lord.max_hp) - old_hp)
	var levels: int = int(lord.level) - 1
	var modifiers: Dictionary = talent_modifiers()
	lord.max_hp = maxi(1, ceili(float(120 + 10 * levels) * (1.0 + float(modifiers.lord_hp))))
	lord.tree_base_damage = float(10 + levels)
	lord.tree_damage_bonus = float(modifiers.lord_damage)
	lord.damage = maxi(1, ceili(float(lord.tree_base_damage) * (1.0 + float(lord.tree_damage_bonus) + (0.05 if has_run_skill("shared_unity_of_power") else 0.0))))
	lord.armor = maxi(0, 1 + int(modifiers.lord_armor))
	# Increasing max HP preserves wounds; lowering it cannot kill a living lord.
	# Repeated calls with the same base/modifiers neither heal nor resurrect.
	lord.hp = clampi(int(lord.max_hp) - damage_taken, 1, int(lord.max_hp)) if old_hp > 0 else 0


func room_stats(index: int) -> Dictionary:
	if not _valid_slot(index) or rooms[index].is_empty():
		return {}
	return _room_stats_for_state(index, rooms[index])


func _room_stats_for_state(index: int, state: Dictionary) -> Dictionary:
	var result: Dictionary = Content.room(str(state.id)).duplicate(true)
	var rank: int = int(state.rank)
	var rank_factor: float = 1.0 + 0.25 * float(rank - 1)
	var is_monster: bool = str(result.kind) == "monster"
	var modifiers: Dictionary = talent_modifiers()
	var faction: Dictionary = _faction_modifiers(str(state.id))
	var evolution: Dictionary = _evolution_modifiers(state)
	var hp_factor: float = 1.0 + float(lord_passive_modifiers().monster_hp)
	hp_factor += float(faction.get("monster_hp", 0.0)) + float(evolution.get("hp_bonus", 0.0))
	var damage_factor: float = 1.0
	damage_factor += float(faction.get("monster_damage" if is_monster else "trap_damage", 0.0)) + float(evolution.get("damage_bonus", 0.0))
	var floor_index: int = layout_effect_scope(index)
	var floor_trait: String = floor_traits[floor_index] if floor_index < floor_traits.size() else "plain"
	var specialization: String = str(state.get("specialization", ""))
	var duration: int = (8 if str(state.id) == "poison" else 6) + int(evolution.get("poison_turns", 0))
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
	result.tree_base_hp = float(result.hp) * rank_factor * hp_factor if is_monster else 0.0
	result.tree_hp_bonus = float(modifiers.monster_hp) if is_monster else 0.0
	result.hp = ceili(float(result.tree_base_hp) * (1.0 + float(result.tree_hp_bonus))) if is_monster else 0
	result.max_hp = result.hp
	result.tree_base_damage = float(result.damage) * rank_factor * damage_factor
	if str(state.id) in ["spikes", "ballista", "blade_floor"]:
		result.tree_base_damage *= 1.10
	if specialization == "virulent":
		result.tree_base_damage = float(result.tree_base_damage) + 1.0
	result.tree_damage_bonus = float(modifiers.monster_damage) if is_monster else _direct_trap_bonus(index, state, result)
	var preview_bonus: float = float(result.tree_damage_bonus)
	if is_monster:
		preview_bonus += 0.15 if has_run_skill("creatures_frenzied_servants") else 0.0
		preview_bonus += 0.05 if has_run_skill("shared_unity_of_power") else 0.0
		if str(state.id) in ["spider", "war_hound"] and has_run_skill("creatures_beast_ferocity"):
			preview_bonus += 0.1
	result.damage = ceili(float(result.tree_base_damage) * (1.0 + preview_bonus))
	result.tree_bone_armor = 1 if is_monster and result.get("tags", []).has("corporeal") and has_run_skill("creatures_bone_carapace") else 0
	if is_monster:
		result.armor = int(result.armor) + int(faction.get("monster_armor", 0)) + int(evolution.get("armor_bonus", 0)) + int(result.tree_bone_armor)
	if str(result.kind) == "poison":
		result.damage = float(result.tree_base_damage)
		result.poison_power_display = float(result.damage) * (1.0 + float(modifiers.get("poison_damage", 0.0)))
	var base_xp: int = int(result.xp) + 2 * (rank - 1) if is_monster else 0
	result.xp = hero_room_xp(base_xp)
	result.rank = rank
	result.max_rank = 15 if str(result.kind) in ["shackles", "silence", "rust"] else 0
	result.invested = state.invested
	result.used = state.used
	result.specialization = specialization
	result.branch = str(branch_names.get(specialization, ""))
	result.floor_trait = floor_trait
	result.deadly_corridor_receiver = labyrinth_enabled and has_run_skill("traps_deadly_corridor") and _is_direct_trap(state) and _last_layout_trap(index)
	result.poison_ticks = duration
	result.poison_ticks_display = poison_application_duration(duration)
	result.impact_damage = 0
	result.tree_base_impact = 0.0
	result.impact_all = bool(evolution.get("impact_all", false))
	result.disarm_multiplier = maxf(0.4, float(evolution.get("disarm_multiplier", 0.0)))
	result.disarm_poison_turns = maxi(3, int(evolution.get("disarm_poison_turns", 0)))
	result.disarm_control_floor = int(evolution.get("disarm_control_floor", 0))
	if str(result.kind) in ["shackles", "silence", "rust"]:
		result.effect_turns = mini(5, int(result.get("effect_turns", 2)) + rank - 1)
		var bonus_turns: int = int(faction.get("control_turns", 0)) + int(evolution.get("control_turns", 0))
		bonus_turns += 1 if specialization == "control_lingering" else 0
		result.effect_turns = mini(6, int(result.effect_turns) + bonus_turns)
		result.tree_impact_base_damage = float(maxi(0, rank - 1) + int(evolution.get("impact_bonus", 0))) * damage_factor
		result.tree_base_impact = result.tree_impact_base_damage
		result.impact_damage = ceili(float(result.tree_impact_base_damage) * (1.0 + float(result.tree_damage_bonus)))
	if str(state.id) == "guardian" and selected_relics.has("guardian_oath"):
		result.armor = int(result.armor) + 1
	result.role = "Атакует переднего героя"
	if str(state.id) == "mimic":
		result.role = "Засада на поддержку в тылу; живой следопыт ослабляет первый удар на 35%"
	elif str(state.id) == "spider":
		result.role = "Добивает слабейшего, предпочитает отравленных"
	elif str(state.id) == "poison":
		result.role = "Отравляет всю группу на %d тиков" % int(result.poison_ticks_display)
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
		result.role = "Подавляет магию, лечение, защиту от яда и песню на первые %d тика следующего боя" % int(result.effect_turns)
	elif str(state.id) == "rust":
		result.role = "Группа: −1 брони в первые %d тика следующего боя" % int(result.effect_turns)
	elif str(state.id) == "guardian":
		result.role = "Долго удерживает отряд, пока действует яд"
	result.combo = room_combo(index)
	result.status = state.get("status", "ready")
	result.current_hp = int(state.get("current_hp", result.hp)) if phase in ["raid", "result", "defeat"] else int(result.hp)
	result.evolution_path = str(state.get("evolution_path", ""))
	result.evolution_stage = int(state.get("evolution_stage", 0))
	result.visual_key = result.evolution_path
	result.instance_id = state.get("instance_id", index)
	result.evolution_memory = state.get("evolution_memory", {}).duplicate(true)
	if not str(result.evolution_path).is_empty():
		var form: Dictionary = Evolutions.stage(str(result.evolution_path), int(result.evolution_stage))
		result.branch = str(form.get("name", ""))
		result.name = str(form.get("name", result.name))
		result.role = str(form.get("description", result.role))
		result.evolution_params = form.get("params", {})
	return result


func _is_direct_trap(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	var kind: String = str(Content.room(str(state.get("id", ""))).get("kind", ""))
	if kind == "spikes":
		return str(state.get("evolution_path", "")) not in ["blade_floor_partition_corridor", "blade_floor_corpse_reclaimer"]
	if kind in ["shackles", "silence", "rust"]:
		var path: String = str(state.get("evolution_path", ""))
		if not path.is_empty():
			return path == "rust_shard_chamber"
		return int(state.get("rank", 1)) > 1
	return false


func _last_direct_trap_on_floor(index: int) -> bool:
	if labyrinth_enabled:
		return _last_layout_trap(index)
	var candidate: int = next_route_slot(index)
	while candidate < rooms.size() and candidate / SLOTS_PER_FLOOR == index / SLOTS_PER_FLOOR:
		if _is_direct_trap(rooms[candidate]):
			return false
		candidate = next_route_slot(candidate)
	return true


func _direct_trap_bonus(index: int, state: Dictionary, definition: Dictionary) -> float:
	if str(definition.kind) in ["monster", "poison"]:
		return 0.0
	var bonus: float = float(run_skill_modifiers().get("direct_trap_damage", 0.0))
	if str(state.id) in ["spikes", "blade_floor"] and has_run_skill("traps_sharpening"):
		bonus += 0.12
	if str(state.id) == "ballista" and has_run_skill("traps_tension"):
		bonus += 0.12
	if has_run_skill("shared_unity_of_power"):
		bonus += 0.05
	if has_run_skill("poison_long_poison"):
		bonus -= 0.08
	if has_run_skill("traps_deadly_corridor") and _is_direct_trap(state) and _last_direct_trap_on_floor(index):
		bonus += 0.15
	return bonus


func hero_room_xp(base_xp: int) -> int:
	# Round the shared pool to the nearest integer: a small greed penalty must not
	# turn a 3 XP room into 4 XP (+33%) before its rank has even increased.
	return maxi(0, roundi(float(base_xp) * (1.0 + float(talent_modifiers().hero_room_xp) + float(lord_passive_modifiers().hero_room_xp))))


func floor_price_details() -> Dictionary:
	if labyrinth_enabled:
		return depth_access_price_details()
	var next_floor: int = floor_count + 1
	var base: int = 5 * next_floor * next_floor
	var price: int = maxi(1, ceili(float(base) * (1.0 + float(talent_modifiers().floor_cost))))
	return {"base": base, "price": price, "saving": base - price}


func floor_cost() -> int:
	return int(floor_price_details().price)


func heal_price_details() -> Dictionary:
	var base: int = 6 + 2 * floori(float(wave - 1) / 5.0)
	var price: int = maxi(1, ceili(float(base) * (1.0 + float(talent_modifiers().heal_cost))))
	return {"base": base, "price": price, "saving": base - price}


func heal_cost() -> int:
	return int(heal_price_details().price)


func paid_heal_amount() -> int:
	return maxi(0, mini(ceili(float(lord.max_hp) * 0.25 * (1.1 if has_run_skill("shared_dark_recovery") else 1.0)), int(lord.max_hp) - int(lord.hp)))


func _discounted_room_price(base_price: int) -> int:
	var saving: int = 0
	if has_run_skill("economy_supply") and not bool(_skill_preparation.get("supply_used", false)):
		saving += 1
	if bool(_skill_preparation.get("contract_available", false)):
		saving += 2
	return maxi(1, base_price - saving)


func shop_room_cost(id: String) -> int:
	var definition: Dictionary = Content.room(id)
	return _discounted_room_price(int(definition.get("cost", 0))) if not definition.is_empty() else 0


func _consume_building_discounts(room: Dictionary) -> void:
	room.run_discount_wave = wave
	if has_run_skill("economy_supply") and not bool(_skill_preparation.get("supply_used", false)):
		room.run_supply_used = true
		_skill_preparation.supply_used = true
	if bool(_skill_preparation.get("contract_available", false)):
		room.run_contract_used = true
		_skill_preparation.contract_available = false


func upgrade_price_details(index: int) -> Dictionary:
	var details: Dictionary = {"base": 0, "price": 0, "saving": 0, "discounts": []}
	if not _valid_slot(index) or rooms[index].is_empty():
		return details
	var state: Dictionary = rooms[index]
	var definition: Dictionary = Content.room(str(state.id))
	var price: int = int(definition.cost) * (int(state.rank) + 1)
	details.base = price
	if has_run_skill("traps_workshop") and str(definition.kind) != "monster" and not bool(state.get("run_workshop_used", false)):
		var after: int = maxi(1, price - 1)
		details.discounts.append({"name": "Мастерская", "saving": price - after})
		price = after
	if _trophy_metal:
		var after: int = maxi(1, price - 2)
		details.discounts.append({"name": "Трофейный металл", "saving": price - after})
		price = after
	if has_run_skill("economy_military_order") and not bool(_skill_preparation.get("military_used", false)):
		var after: int = maxi(1, ceili(float(price) - minf(5.0, float(price) * 0.2)))
		details.discounts.append({"name": "Военный заказ", "saving": price - after})
		price = after
	details.price = price
	details.saving = int(details.base) - price
	return details


func upgrade_cost(index: int) -> int:
	return int(upgrade_price_details(index).price)


func record_direct_trap_kill() -> void:
	if not has_run_skill("shared_trophy_metal") or bool(run_skill_runtime.get("trophy_kill_used", false)):
		return
	run_skill_runtime.trophy_kill_used = true
	if not _trophy_metal:
		_trophy_metal = true
		_log("Трофейный металл: следующее улучшение комнаты дешевле на 2 золота.")


func sell_value(index: int) -> int:
	if not _valid_slot(index) or rooms[index].is_empty():
		return 0
	var invested: int = int(rooms[index].invested)
	var fraction: float = 0.6 if has_run_skill("economy_buyer") else 0.5
	return floori(float(invested) * fraction) if bool(rooms[index].used) else invested


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
	var group_factors: Dictionary = HeroRules.party_factors(party_ids.size(), wave)
	var pressure: float = 1.0
	var starting_level: int = 1 + floori(float(wave - 1) / 4.0)
	var disarm_supply: int = mini(6, 2 + floori(float(wave - 1) / 6.0))
	if elite_id == "sappers":
		disarm_supply += 2
	for id in party_ids:
		var definition: Dictionary = Content.hero(id)
		var hero: Dictionary = {
			"id": id, "instance_id": "%d_%s" % [wave, id],
			"name": definition.name, "level": starting_level, "starting_level": starting_level, "wave": wave, "xp": 0,
			"equipment": HeroRules.initial_equipment(id, wave, rng), "equipment_state": {}, "effects": {},
			"hp": 0, "max_hp": 0, "damage": 0, "armor": 0,
			"items": [], "poison_ticks": 0, "poison_damage": 0,
			"poison_heal_factor": 1.0, "poison_resistance": 0.65 if elite_id == "alchemy" else 1.0,
			"elite_armor": 1 if elite_id == "armor" else 0,
			"disarm_max": disarm_supply if id == "rogue" else 0,
			"disarm_charges": disarm_supply if id == "rogue" else 0,
			"elite_modifier": elite_description,
			"death_processed": false, "group_factor": group_factors.hp,
			"group_hp_factor": group_factors.hp, "group_damage_factor": group_factors.damage,
			"soul_special": not elite_id.is_empty(), "boss_id": boss_id, "wave_is_boss": wave_is_boss,
			"pressure": pressure, "icon": definition.icon, "color": definition.color,
			"trait": definition.trait,
		}
		_recalculate_hero(hero)
		_clear_hero_control(hero)
		hero.hp = hero.max_hp
		heroes.append(hero)
	HeroRules.roll_party_equipment(heroes, wave, rng)
	for hero in heroes:
		_recalculate_hero(hero)
		hero.hp = hero.max_hp


func _configure_wave() -> void:
	wave_is_boss = Expedition.is_boss_wave(wave)
	boss_id = ""
	elite_id = ""
	wave_title = "Налёт приключенцев"
	wave_description = ""
	if wave_is_boss:
		var boss: Dictionary = Expedition.boss_definition(wave)
		boss_id = str(boss.id)
		elite_id = "boss"
		wave_title = str(boss.name)
		wave_description = str(boss.description)
		return
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


func _spend_disarm(preferred_hero: Dictionary = {}) -> bool:
	var candidates: Array[Dictionary] = _living()
	if not preferred_hero.is_empty():
		candidates.clear()
		for hero in _living():
			if str(hero.instance_id) == str(preferred_hero.get("instance_id", "")):
				candidates.append(hero)
				break
	for hero in candidates:
		if str(hero.id) == "rogue" and int(hero.get("disarm_charges", 0)) > 0:
			hero.disarm_charges = int(hero.disarm_charges) - 1
			var message: String = "Следопыт пытается обезвредить ловушку" if labyrinth_enabled else "Следопыт ослабляет ловушку"
			_log("%s. Инструментов осталось: %d." % [message, int(hero.disarm_charges)])
			_action("disarm_attempt" if labyrinth_enabled else "disarm", str(hero.instance_id), _defender_actor(), 1, message)
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
	return survivors[0]


func _defender_actor() -> String:
	return str(defender.get("actor_id", "lord" if current_slot == rooms.size() else "room_%d" % current_slot))


func _action(kind: String, actor: String, target: String, amount: int, message: String) -> void:
	action_seq += 1
	last_action = {"seq": action_seq, "tick": tick, "kind": kind, "actor": actor, "target": target, "amount": amount, "text": message, "source_slot": current_slot, "meta": {}}
	combat_events.append(last_action)
	if combat_events.size() > 128:
		combat_events.pop_front()


func next_route_slot(index: int) -> int:
	if labyrinth_enabled:
		if index < 0:
			return _labyrinth.entrance_slot
		if index >= rooms.size():
			return rooms.size()
		var following: int = layout_next_neighbor(index)
		return following if following >= 0 else rooms.size()
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
	if _try_start_route_camp():
		return
	_encounter.enter(self)


func _trigger_trap(stats: Dictionary, disarmed: bool) -> void:
	var floor_index: int = layout_effect_scope(current_slot)
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
		var poison_aura: float = _poison_aura_multiplier()
		for hero in targets:
			_apply_hero_poison(hero, float(stats.get("tree_base_damage", stats.damage)), duration, _battle_source())
			if str(stats.specialization) == "plague":
				hero.poison_heal_factor = 0.5
			if echo:
				_inflict_hero_damage(hero, _poison_hit(hero, float(stats.get("tree_base_damage", stats.damage)) * 0.4 * (1.0 + float(run_skill_modifiers().get("poison_damage", 0.0))), poison_aura), _battle_source())
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
	_encounter.step(self)


func poison_tick_power(hero: Dictionary, natural: bool = false) -> float:
	if int(hero.get("poison_ticks", 0)) <= 0:
		return 0.0
	var base: float = float(hero.get("run_poison_base", hero.get("poison_damage", 0.0)))
	var bonus: float = float(hero.get("run_poison_bonus", 0.0))
	if has_run_skill("poison_mature_formula") and int(hero.get("run_poison_maturity", 0)) >= 2:
		bonus += 0.15
	if natural and int(hero.poison_ticks) == 1 and has_run_skill("poison_last_drop"):
		bonus += 1.0 if has_run_skill("poison_final_sediment") else 0.5
	return base * (1.0 + bonus)


func clear_poison(hero: Dictionary) -> void:
	hero.poison_ticks = 0
	hero.poison_damage = 0.0
	hero.poison_heal_factor = 1.0
	hero.run_poison_maturity = 0
	hero.run_poison_uninterrupted = 0
	hero.run_poison_corrosion = 0
	hero.run_heavy_breathing = false
	hero.erase("poison_source")
	hero.erase("run_poison_base")
	hero.erase("run_poison_bonus")


func consume_poison_tick(hero: Dictionary, natural: bool = false) -> float:
	var power: float = poison_tick_power(hero, natural)
	if int(hero.get("poison_ticks", 0)) <= 0:
		return 0.0
	if natural:
		hero.run_poison_maturity = int(hero.get("run_poison_maturity", 0)) + 1
		hero.run_poison_uninterrupted = int(hero.get("run_poison_uninterrupted", 0)) + 1
		if int(hero.run_poison_uninterrupted) >= 3 and has_run_skill("poison_corrosive_formula"):
			hero.run_poison_corrosion = 1
		if int(hero.run_poison_maturity) >= 3 and has_run_skill("poison_heavy_breathing"):
			hero.run_heavy_breathing = true
	hero.poison_ticks = maxi(0, int(hero.poison_ticks) - 1)
	if int(hero.poison_ticks) == 0:
		clear_poison(hero)
	return power


func _apply_poison() -> void:
	var poison_aura: float = _poison_aura_multiplier()
	for hero in _living():
		if int(hero.poison_ticks) <= 0 or int(hero.hp) <= 0:
			continue
		var damage: int = _poison_hit(hero, poison_tick_power(hero, true), poison_aura)
		# The lethal natural final tick still counts as dying while poisoned.
		damage = _encounter.hero_damage(self, hero, damage, str(hero.get("poison_source", "")))
		consume_poison_tick(hero, true)
		_log("Яд: %s −%d HP (%d тиков осталось)." % [hero.name, damage, hero.poison_ticks])
		_action("poison", "poison", str(hero.instance_id), damage, "Яд → %s: −%d HP" % [hero.name, damage])
		last_action.meta = {"maturity": int(hero.get("run_poison_maturity", 0)), "corrosion": int(hero.get("run_poison_corrosion", 0)), "heavy_breathing": bool(hero.get("run_heavy_breathing", false))}


func _trigger_plague_focus(victim: Dictionary) -> void:
	if not has_run_skill("poison_plague_focus") or int(victim.get("poison_ticks", 0)) <= 0 or bool(run_skill_runtime.get("plague_burst_active", false)):
		return
	var floor_index: int = layout_effect_scope(current_slot)
	var key: String = "plague_floor_%d" % floor_index
	if bool(run_skill_runtime.get(key, false)):
		return
	run_skill_runtime[key] = true
	run_skill_runtime.plague_burst_active = true
	var power: float = poison_tick_power(victim)
	var aura: float = _poison_aura_multiplier()
	var source: String = str(victim.get("poison_source", _battle_source()))
	for target in _living():
		var damage: int = _inflict_hero_damage(target, _poison_hit(target, power, aura), source)
		_action("plague_focus", str(victim.instance_id), str(target.instance_id), damage, "Чумной очаг: −%d HP" % damage)
	run_skill_runtime.plague_burst_active = false


func _process_deaths() -> void:
	_encounter.process_hero_deaths(self)


func _reward_dead_heroes() -> void:
	var changed: bool = false
	for hero in heroes:
		if int(hero.hp) > 0 or bool(hero.death_processed) or bool(hero.get("escaped", false)):
			continue
		_settle_stolen_gold(hero, false)
		hero.death_processed = true
		changed = true
		hero.items = []
		var base_coins: int = 3 + floori(float(wave - 1) / 3.0)
		var coins: int = base_coins
		if has_run_skill("economy_greed"):
			_greed_remainder += base_coins * 20
			coins += _greed_remainder / 100
			_greed_remainder %= 100
		_reward_hero_souls(hero)
		var experience: int = 5 + int(hero.level)
		gold += coins
		lord.xp = int(lord.xp) + experience
		total_kills += 1
		report.killed = int(report.killed) + 1
		report.gold = int(report.gold) + coins
		report.xp = int(report.xp) + experience
		_log("%s погиб: +%d золота, +%d XP Лорду." % [hero.name, coins, experience])
	# Surviving formation is stable inside the encounter: death never silently
	# pulls a resting knight back in front of the hero who covered them.


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
	# A finite, class-compatible special can replace the ordinary room trophy.
	# This 18% chance is a tuning default; start-wave caps do not cap earned loot.
	if wave >= 10 and int(stats.get("rank", 1)) >= 5 and rng.randf() < 0.18:
		for hero in survivors:
			var candidate: String = str(HeroRules.SPECIAL_BY_CLASS.get(str(hero.id), ""))
			if not candidate.is_empty() and not hero.items.has(candidate):
				item_id = candidate
				break
	if item_id.is_empty():
		return
	var priority: Array[String] = ["knight", "barbarian", "rogue", "priest", "mage", "bard"]
	if item_id == "sword":
		priority.assign(["rogue", "barbarian", "knight", "mage", "bard", "priest"])
	for archetype in priority:
		for hero in survivors:
			if str(hero.id) != archetype or hero.items.has(item_id):
				continue
			if not HeroRules.equip_item(hero, item_id):
				continue
			_recalculate_hero(hero)
			report.items = int(report.items) + 1
			_log("%s получает %s." % [hero.name, HeroRules.item(item_id).name])
			return
	_log("%s не улучшает снаряжение выживших; трофей оставлен." % HeroRules.item(item_id).name)


func effective_hero_armor(hero: Dictionary) -> int:
	var armor: int = int(hero.get("armor", 0)) - int(hero.get("run_poison_corrosion", 0))
	if int(hero.get("rust_ticks", 0)) > 0:
		armor -= int(hero.get("rust_amount", 1))
	return maxi(0, armor)


func _recalculate_hero(hero: Dictionary) -> void:
	var base: Dictionary = Content.hero(str(hero.id))
	HeroRules.ensure_equipment(hero)
	var values: Dictionary = HeroRules.scaled_stats(base, hero)
	hero.max_hp = int(values.max_hp)
	hero.damage = int(values.damage)
	hero.armor = int(values.armor)
	hero.items = [str(hero.equipment.get("weapon", "")), str(hero.equipment.get("protection", ""))]


func _finish_wave(outcome: String = "defended") -> void:
	if phase not in ["raid", "camp"]:
		return
	if int(lord.hp) <= 0:
		_finish_defeat()
		return
	_clear_defender_effects(defender)
	_clear_defender_effects(lord)
	_camp_state.clear()
	last_completed_wave = wave
	report.outcome = outcome
	if outcome == "robbed":
		_pending_blueprint = false
		_pending_relic = false
		_grant_lord_levels()
		phase = "result"
		_log("Отряд отступил, добыча возвращена." if int(report.get("escaped_gold", 0)) == 0 else "Отряд скрылся с добычей: унесено %d золота." % int(report.escaped_gold))
		return
	last_defended_wave = wave
	if not defended_waves.has(wave):
		defended_waves.append(wave)
	if not elite_id.is_empty() and not defeated_special_waves.has(wave):
		defeated_special_waves.append(wave)
	# Reserve observes the wallet before every completion reward, including saved Q.
	var reserve: int = mini(3, gold / 20) if has_run_skill("economy_gold_reserve") else 0
	var tribute: int = int(has_run_skill("economy_tribute_1")) + int(has_run_skill("economy_tribute_2")) + int(has_run_skill("economy_tribute_3"))
	var saved: int = mini(2, ability_charges) if has_run_skill("shared_saved_power") else 0
	gold += 4 + reserve + tribute + saved
	report.gold = int(report.gold) + 4 + reserve + tribute + saved
	report.skill_gold = {"tribute": tribute, "reserve": reserve, "saved_power": saved}
	if reserve + tribute + saved > 0:
		_log("Навыки: дань +%d, запас +%d, сбережённые заряды +%d золота." % [tribute, reserve, saved])
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
	_grant_lord_levels()
	_pending_blueprint = wave % BLUEPRINT_WAVE_INTERVAL == 0 and not _available_blueprint_ids().is_empty()
	_pending_relic = wave % RELIC_WAVE_INTERVAL == 0 and not _available_relic_ids().is_empty()
	if tutorial_run and wave == 1:
		if int(lord.level) < 2:
			lord.level = 2
			_recalculate_lord()
		var tutorial_souls: int = maxi(0, 3 - run_souls)
		run_souls += tutorial_souls
		report.souls = int(report.get("souls", 0)) + tutorial_souls
		report.tutorial_souls = tutorial_souls
		run_souls_changed.emit(run_souls, tutorial_souls)
		_pending_blueprint = true
		_pending_relic = true
		_log("Учебные награды: души, чертёж и реликвия. Они действуют только в тренировке.")
	phase = "result"
	_log("Волна %d отражена! +4 золота за защиту." % wave)


func _grant_lord_levels() -> void:
	while int(lord.xp) >= 10 + 6 * (int(lord.level) - 1):
		lord.xp = int(lord.xp) - (10 + 6 * (int(lord.level) - 1))
		var previous_max_hp: int = int(lord.max_hp)
		var previous_damage: int = int(lord.damage)
		lord.level = int(lord.level) + 1
		_recalculate_lord()
		_log("Лорд достиг уровня %d! +%d HP и +%d урона." % [lord.level, int(lord.max_hp) - previous_max_hp, int(lord.damage) - previous_damage])


func _finish_defeat() -> void:
	if phase == "defeat":
		return
	phase = "defeat"
	report.outcome = "defeat"
	_camp_state.clear()
	_clear_defender_effects(defender)
	_clear_defender_effects(lord)
	_log("Лорд пал. Пережито волн: %d · убито героев: %d." % [cleared_waves, total_kills])


func _living() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for hero in heroes:
		if int(hero.hp) > 0 and not bool(hero.get("escaped", false)):
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
	if _valid_slot(current_slot) and not rooms[current_slot].is_empty() and str(rooms[current_slot].get("status", "")) != "retreated":
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
		_trigger_plague_focus(hero)
	return damage


func _apply_hero_poison(hero: Dictionary, damage: float, duration: int, source: String, extra_bonus: float = 0.0) -> void:
	if damage <= 0.0 or duration <= 0 or int(hero.hp) <= 0:
		return
	var ongoing: bool = int(hero.get("poison_ticks", 0)) > 0
	var bonus: float = float(run_skill_modifiers().get("poison_damage", 0.0)) + extra_bonus
	var strength: float = damage * (1.0 + bonus)
	var full_duration: int = poison_application_duration(duration)
	# Stronger poison retains its owner/base. Equal power with a refreshed
	# duration transfers ownership. No intermediate integer rounding occurs.
	if not ongoing or strength > float(hero.get("poison_damage", 0.0)) or (is_equal_approx(strength, float(hero.get("poison_damage", 0.0))) and full_duration >= int(hero.poison_ticks)):
		hero.poison_source = source
		hero.run_poison_base = damage
		hero.run_poison_bonus = bonus
		hero.poison_damage = strength
	hero.poison_ticks = maxi(int(hero.get("poison_ticks", 0)), full_duration)
	if not ongoing:
		hero.run_poison_uninterrupted = 0
		hero.run_poison_corrosion = 0
	if not ongoing or not has_run_skill("poison_unbroken_maturity"):
		hero.run_poison_maturity = 0
		hero.run_heavy_breathing = false


func soul_drop_probabilities(special: bool = false) -> Dictionary:
	var guaranteed: bool = soul_failures >= 2
	if not special:
		return {"0": 0.0 if guaranteed else (0.45 if has_run_skill("ritual_soul_catcher") else 0.5), "1": 1.0 if guaranteed else (0.55 if has_run_skill("ritual_soul_catcher") else 0.5), "2": 0.0, "guaranteed": guaranteed}
	var two: float = 0.25 if has_run_skill("shared_art_of_harvest") else 0.2
	var zero: float = 0.0 if guaranteed else (0.25 if has_run_skill("ritual_soul_catcher") else 0.3)
	return {"0": zero, "1": 1.0 - zero - two, "2": two, "guaranteed": guaranteed}


func _reward_hero_souls(hero: Dictionary) -> void:
	if bool(hero.get("soul_rewarded", false)):
		return
	hero.soul_rewarded = true
	var probabilities: Dictionary = soul_drop_probabilities(bool(hero.get("soul_special", not elite_id.is_empty())))
	# Exactly one isolated weighted draw for each defeated hero, including pity.
	var roll: float = float(soul_rng.randi_range(0, 99)) / 100.0
	var reward: int = 0 if roll < float(probabilities["0"]) else (1 if roll < float(probabilities["0"]) + float(probabilities["1"]) else 2)
	soul_failures = soul_failures + 1 if reward == 0 else 0
	run_souls += reward
	report.souls = int(report.get("souls", 0)) + reward
	run_souls_changed.emit(run_souls, reward)
	var message: String = "Душа %s разбилась." % str(hero.name) if reward == 0 else "%s: +%d душ." % [hero.name, reward]
	_log(message)
	_action("soul_shatter" if reward == 0 else "soul", str(hero.instance_id), "lord", reward, message)
	last_action.meta = {"run_souls": run_souls, "failure_count": soul_failures, "special": bool(hero.get("soul_special", false)), "guaranteed": bool(probabilities.guaranteed)}


func _reset_report() -> void:
	report = {"killed": 0, "gold": 0, "xp": 0, "lord_damage": 0, "hero_levels": 0, "items": 0, "unlock": "", "skill_points": 0, "souls": 0, "outcome": "", "stolen_gold": 0, "returned_gold": 0, "escaped_gold": 0}


func _log(message: String) -> void:
	logs.append(message)
	if logs.size() > MAX_LOGS:
		logs.pop_front()


func _reset_camps() -> void:
	_camp_state.clear()
	_camp_processed_floors.clear()
	_camp_processed_places.clear()
	_camp_interruptions = 0


func _camp_floor_exit(floor_index: int) -> int:
	return floor_index * SLOTS_PER_FLOOR + (SLOTS_PER_FLOOR - 1 if floor_index % 2 == 0 else 0)


func _camp_floor_has_rooms(floor_index: int) -> bool:
	for slot in range(floor_index * SLOTS_PER_FLOOR, mini((floor_index + 1) * SLOTS_PER_FLOOR, rooms.size())):
		if not rooms[slot].is_empty():
			return true
	return false


func _camp_party_needs_healing() -> bool:
	for hero in heroes:
		if int(hero.hp) > 0 and int(hero.hp) < int(hero.max_hp):
			return true
	return false


func _try_start_route_camp() -> bool:
	if labyrinth_enabled:
		return _try_start_labyrinth_camp()
	if phase != "raid" or not _waiting_for_entry or current_slot >= rooms.size() or int(lord.hp) <= 0 or _living().is_empty():
		return false
	# Mirror Encounter.enter's empty/consumed scan without entering a room or
	# running end_combat: camp time must not clear or advance any combat state.
	var cursor: int = current_slot
	while cursor < rooms.size():
		var next_slot: int = next_route_slot(cursor)
		if cursor >= 0 and (next_slot >= rooms.size() or cursor / SLOTS_PER_FLOOR != next_slot / SLOTS_PER_FLOOR):
			var floor_index: int = cursor / SLOTS_PER_FLOOR
			if not _camp_processed_floors.has(floor_index):
				_camp_processed_floors[floor_index] = true
				if _camp_floor_has_rooms(floor_index) and _camp_party_needs_healing():
					_start_camp(floor_index)
					return true
		if next_slot >= rooms.size():
			return false
		if not rooms[next_slot].is_empty() and not _encounter.consumed.has(next_slot):
			return false
		cursor = next_slot
	return false


func _start_camp(floor_index: int) -> void:
	# Resolve the highest learned replacement once; status reads use this snapshot.
	var duration: int = CampRules.duration(learned_skills)
	for tier in [3, 2, 1]:
		var id: String = "shared_restless_dungeons_%d" % tier
		if has_run_skill(id):
			duration = maxi(1, int(run_skill_definition(id).get("camp_duration_seconds", duration)))
			break
	if not labyrinth_enabled:
		current_slot = _camp_floor_exit(floor_index)
	_camp_state = {
		"floor_index": floor_index, "slot": current_place if labyrinth_enabled else current_slot, "place": current_place,
		"elapsed": 0.0, "duration": duration,
		"pulses": 0, "carry": {}, "healed_total": 0,
	}
	phase = "camp"
	_waiting_for_entry = true
	active_target_id = ""
	var message: String = "Отряд отдыхает в клетке %s: %d секунд." % [str(_labyrinth.positions[current_place]), duration] if labyrinth_enabled else "Отряд разбивает лагерь на этаже %d: %d секунд." % [floor_index + 1, duration]
	_log(message)
	_action("camp_start", "camp", "", 0, message)
	last_action.meta = {"floor_index": floor_index, "duration": int(_camp_state.duration)}


func camp_interrupt_cost() -> int:
	# Only successful interruptions advance the wave-local price step.
	# Q and paid E share the immutable ordinary income snapshot, without discounts.
	if _camp_interruptions == 0:
		return 0
	var divisor: float = 4.0 if _camp_interruptions == 1 else 2.0
	return maxi(1, ceili(float(base_wave_income()) / divisor))


func camp_status() -> Dictionary:
	# A UI read is pure: it never consumes fractions, advances time, or creates state.
	var active: bool = phase == "camp" and not _camp_state.is_empty()
	var duration: int = int(_camp_state.get("duration", CampRules.duration(learned_skills)))
	var elapsed: float = float(_camp_state.get("elapsed", 0.0))
	var pulses: int = int(_camp_state.get("pulses", 0))
	var remaining_pulses: int = maxi(0, duration - pulses) if active else 0
	var carry: Dictionary = _camp_state.get("carry", {})
	var rows: Array[Dictionary] = []
	var remaining_total: int = 0
	var vapors: bool = has_run_skill("poison_caustic_vapors")
	for hero in heroes:
		var factor: float = CampRules.healing_factor(hero, heroes, vapors)
		var remaining: int = CampRules.remaining_healing(hero, float(carry.get(str(hero.instance_id), 0.0)), remaining_pulses, factor)
		remaining_total += remaining
		rows.append({
			"instance_id": str(hero.instance_id), "hp": int(hero.hp), "max_hp": int(hero.max_hp),
			"healing_factor": factor, "remaining_healing": remaining,
		})
	var price: int = camp_interrupt_cost()
	var reason: String = ""
	if not active:
		reason = "Сейчас нет лагеря для срыва."
	elif int(lord.hp) <= 0 or _living().is_empty():
		reason = "Отдых уже завершён."
	elif remaining_total <= 0:
		reason = "В этом лагере больше нет доступного лечения."
	elif gold < price:
		reason = "Не хватает золота: нужно %d." % price
	return {
		"active": active, "floor_index": int(_camp_state.get("floor_index", -1)),
		"slot": int(_camp_state.get("slot", -1)), "elapsed": elapsed, "duration": duration,
		"remaining_seconds": maxf(0.0, float(duration) - elapsed) if active else 0.0,
		"remaining_pulses": remaining_pulses, "progress": clampf(elapsed / float(duration), 0.0, 1.0) if active else 0.0,
		"pulse_progress": clampf(elapsed - float(pulses), 0.0, 1.0) if active else 0.0,
		"heroes": rows, "remaining_healing": remaining_total, "can_interrupt": reason.is_empty(),
		"reason": reason, "gold_cost": price, "successful_interruptions": _camp_interruptions,
	}


func advance_camp(delta_game_seconds: float) -> void:
	if phase != "camp" or _camp_state.is_empty() or not is_finite(delta_game_seconds) or delta_game_seconds <= 0.0:
		return
	last_action = {}
	combat_events.clear()
	if int(lord.hp) <= 0:
		_finish_defeat()
		return
	if _living().is_empty():
		_finish_wave()
		return
	if not _camp_party_needs_healing():
		_end_camp("healthy")
		return
	var target_elapsed: float = minf(float(_camp_state.duration), float(_camp_state.elapsed) + delta_game_seconds)
	var due_pulses: int = mini(int(_camp_state.duration), floori(target_elapsed))
	while phase == "camp" and int(_camp_state.pulses) < due_pulses:
		_camp_state.pulses = int(_camp_state.pulses) + 1
		_camp_state.elapsed = float(_camp_state.pulses)
		_camp_heal_pulse()
		if not _camp_party_needs_healing() or int(_camp_state.pulses) >= int(_camp_state.duration):
			_end_camp("healthy" if not _camp_party_needs_healing() else "completed")
			return
	_camp_state.elapsed = target_elapsed


func _camp_heal_pulse() -> void:
	var carry: Dictionary = _camp_state.carry
	var vapors: bool = has_run_skill("poison_caustic_vapors")
	for hero in heroes:
		if int(hero.hp) <= 0 or int(hero.hp) >= int(hero.max_hp):
			continue
		var identity: String = str(hero.instance_id)
		var factor: float = CampRules.healing_factor(hero, heroes, vapors)
		var exact: float = float(carry.get(identity, 0.0)) + CampRules.pulse_power(hero, factor)
		var whole: int = CampRules.whole_hp(exact)
		carry[identity] = maxf(0.0, exact - float(whole))
		var actual: int = mini(int(hero.max_hp) - int(hero.hp), whole)
		if actual <= 0:
			continue
		hero.hp = int(hero.hp) + actual
		_camp_state.healed_total = int(_camp_state.healed_total) + actual
		var message: String = "Лагерь: %s восстанавливает %d HP." % [hero.name, actual]
		_log(message)
		_action("camp_heal", "camp", identity, actual, message)
		last_action.meta = {"floor_index": int(_camp_state.floor_index), "pulse": int(_camp_state.pulses), "healing_factor": factor}


func interrupt_camp() -> String:
	var status: Dictionary = camp_status()
	if not bool(status.can_interrupt):
		return str(status.reason)
	# No callback/yield between validation, payment and closing this camp.
	var price: int = int(status.gold_cost)
	gold -= price
	_camp_interruptions += 1
	last_action = {}
	combat_events.clear()
	var message: String = "Лагерь сорван: потрачено %d золота, оставшееся лечение отменено." % price
	_log(message)
	_action("camp_interrupt", "lord", "camp", 0, message)
	last_action.meta = {"floor_index": int(_camp_state.floor_index), "gold_cost": price, "cancelled_healing": int(status.remaining_healing), "successful_interruptions": _camp_interruptions}
	_end_camp("interrupted")
	return ""


func _end_camp(reason: String) -> void:
	if phase != "camp" or _camp_state.is_empty():
		return
	var floor_index: int = int(_camp_state.floor_index)
	var elapsed: float = float(_camp_state.elapsed)
	var healed_total: int = int(_camp_state.healed_total)
	_camp_state.clear()
	phase = "raid"
	_waiting_for_entry = true
	var message: String = "Отряд продолжает путь из клетки %s." % str(_labyrinth.positions[current_place]) if labyrinth_enabled else "Отряд покидает лагерь на этаже %d." % (floor_index + 1)
	_log(message)
	_action("camp_end", "camp", "", 0, message)
	last_action.meta = {"floor_index": floor_index, "reason": reason, "elapsed": elapsed, "healed_total": healed_total}


# Grid coordinates and room indexes are distinct. Appending a cell never moves an ID.
func layout_snapshot() -> Dictionary:
	var places: Array[Dictionary] = []
	var edges: Array[Dictionary] = []
	var reserved: Dictionary = reserved_room_slots() if labyrinth_enabled else {}
	for slot in range(_labyrinth.positions.size()):
		var kind: String = "throne" if is_throne_slot(slot) else ("treasury" if is_treasury_slot(slot) else "room")
		places.append({"slot": slot, "position": _labyrinth.positions[slot], "type": kind, "combat_slot": rooms.size() if kind == "throne" else int(reserved.get(slot, slot))})
	for boundary in _labyrinth.boundaries.values():
		edges.append(boundary.duplicate(true))
	var expansion: Array[Vector2i] = []
	for position in _labyrinth.expansion_cells():
		if position.y < floor_count * LabyrinthRules.LAYER_HEIGHT:
			expansion.append(position)
	return {
		"places": places, "boundaries": edges, "expansion_cells": expansion,
		"validation_error": _layout_validation_error(), "throne_slot": _labyrinth.throne_slot,
		"entrance_position": _labyrinth.entrance_position, "current_place": current_place,
		"depth_layers": floor_count, "depth_layer_height": LabyrinthRules.LAYER_HEIGHT,
		"next_depth_y": floor_count * LabyrinthRules.LAYER_HEIGHT,
		"recovering_vampires": _encounter.recovery_snapshot(),
	}


func _layout_validation_error() -> String:
	var error: String = _labyrinth.validation_error(rooms.size())
	if not error.is_empty():
		return error
	if not rooms[_labyrinth.treasury_slot].is_empty() or not rooms[_labyrinth.throne_slot].is_empty():
		return "Казна и трон не могут занимать место другой комнаты."
	return ""


func set_boundary_state(id: String, opened: bool) -> String:
	if not labyrinth_enabled or phase != "prepare":
		return "Проходы меняются между волнами."
	if not _labyrinth.boundaries.has(id):
		return "Такой общей границы нет."
	_labyrinth.boundaries[id].open = opened
	return ""


func is_treasury_slot(index: int) -> bool:
	return labyrinth_enabled and index >= 0 and index == _labyrinth.treasury_slot


func is_throne_slot(index: int) -> bool:
	return labyrinth_enabled and index >= 0 and index == _labyrinth.throne_slot


func _special_place_error(index: int) -> String:
	if not labyrinth_enabled or phase != "prepare":
		return "Казна и трон перемещаются между волнами."
	if not _valid_slot(index) or not rooms[index].is_empty() or reserved_room_slots().has(index):
		return "Выберите свободное место."
	return ""


func set_treasury_slot(index: int) -> String:
	var error: String = _special_place_error(index)
	if not error.is_empty():
		return error
	if is_throne_slot(index):
		return "Трон и казна должны стоять отдельно."
	_labyrinth.treasury_slot = index
	return ""


func set_throne_slot(index: int) -> String:
	var error: String = _special_place_error(index)
	if not error.is_empty():
		return error
	if is_treasury_slot(index):
		return "Трон и казна должны стоять отдельно."
	_labyrinth.throne_slot = index
	return ""


func grid_expansion_cost() -> int:
	return LabyrinthRules.EXPANSION_BASE_COST


func expand_grid_at(position: Vector2i) -> String:
	if not labyrinth_enabled or phase != "prepare":
		return "Раскопка доступна между волнами."
	if position.y < 0:
		return "Выше входного слоя копать нельзя."
	if position.y >= floor_count * LabyrinthRules.LAYER_HEIGHT:
		return "Сначала откройте следующий слой глубины."
	if not _labyrinth.expansion_cells().has(position):
		return "Выберите новую клетку рядом с подземельем."
	var price: int = grid_expansion_cost()
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	var slot: int = _labyrinth.append_cell(position)
	if slot < 0:
		return "Это место уже недоступно для раскопки."
	rooms.append({})
	gold -= price
	_log("Раскопана клетка %s: −%d золота." % [str(position), price])
	return ""


func depth_layer_for_slot(slot: int) -> int:
	if not labyrinth_enabled:
		return maxi(0, slot / SLOTS_PER_FLOOR)
	var real_slot: int = _labyrinth.throne_slot if slot == rooms.size() else slot
	if real_slot < 0 or real_slot >= _labyrinth.positions.size():
		return 0
	return _labyrinth.positions[real_slot].y / LabyrinthRules.LAYER_HEIGHT


func layout_effect_scope(slot: int) -> int:
	return depth_layer_for_slot(slot)


func depth_access_price_details() -> Dictionary:
	# Retain the existing depth-access curve and its skill discounts.
	var next_layer: int = floor_count + 1
	var base: int = LabyrinthRules.depth_access_base_cost(next_layer)
	var price: int = maxi(1, ceili(float(base) * (1.0 + float(talent_modifiers().floor_cost))))
	return {"base": base, "price": price, "saving": base - price}


func depth_access_cost() -> int:
	return int(depth_access_price_details().price)


func buy_depth_access() -> String:
	if not labyrinth_enabled or phase != "prepare":
		return "Доступ к глубине покупают между волнами."
	var price: int = depth_access_cost()
	if gold < price:
		return "Не хватает золота: нужно %d." % price
	gold -= price
	floor_count += 1
	floor_traits.append("plain")
	pending_floor = floor_count - 1
	if has_run_skill("economy_construction_contract") and not bool(_skill_preparation.get("contract_granted", false)):
		_skill_preparation.contract_granted = true
		_skill_preparation.contract_available = true
	phase = "floor_choice"
	_log("Открыт слой глубины %d. Новые клетки раскапываются отдельно." % floor_count)
	return ""


func layout_neighbors(slot: int) -> Array[int]:
	var result: Array[int] = []
	if not labyrinth_enabled:
		for other in [slot - 1, slot + 1]:
			if _valid_slot(other) and layout_effect_scope(slot) == layout_effect_scope(other):
				result.append(other)
		return result
	for other in _labyrinth.neighbors(slot):
		if _valid_slot(other):
			result.append(other)
	return result


func layout_next_neighbor(slot: int) -> int:
	if not labyrinth_enabled:
		var following: int = next_route_slot(slot)
		return following if _valid_slot(following) and layout_effect_scope(slot) == layout_effect_scope(following) else -1
	return _layout_directional_neighbor(slot, true)


func layout_previous_neighbor(slot: int) -> int:
	if not labyrinth_enabled:
		if not _valid_slot(slot):
			return -1
		var previous: int = slot - (1 if (slot / SLOTS_PER_FLOOR) % 2 == 0 else -1)
		return previous if _valid_slot(previous) and layout_effect_scope(slot) == layout_effect_scope(previous) else -1
	return _layout_directional_neighbor(slot, false)


func _layout_directional_neighbor(slot: int, forward: bool) -> int:
	var distances: Dictionary = _labyrinth.distances_from_entrance()
	if not distances.has(slot):
		return -1
	var selected: int = -1
	var source_distance: int = int(distances[slot])
	for other in layout_neighbors(slot):
		if not distances.has(other) or layout_effect_scope(other) != layout_effect_scope(slot):
			continue
		var distance: int = int(distances[other])
		var follows: bool = distance > source_distance or (distance == source_distance and other > slot)
		if follows != forward:
			continue
		if selected < 0:
			selected = other
			continue
		var selected_distance: int = int(distances[selected])
		var nearer_order: bool = distance < selected_distance or (distance == selected_distance and other < selected)
		if nearer_order == forward:
			selected = other
	return selected


func _last_layout_trap(index: int) -> bool:
	var distances: Dictionary = _labyrinth.distances_from_entrance()
	var selected: int = -1
	var farthest: int = -1
	for slot in range(rooms.size()):
		if not distances.has(slot) or layout_effect_scope(slot) != layout_effect_scope(index) or not _is_direct_trap(rooms[slot]):
			continue
		# Ascending stable slots retain the first candidate on equal distance.
		if int(distances[slot]) > farthest:
			farthest = int(distances[slot])
			selected = slot
	return selected == index


func vampire_retreat_destination(from_place: int, source_slot: int = -1) -> int:
	if not labyrinth_enabled or not _valid_slot(from_place):
		return -1
	var distances: Dictionary = _labyrinth.distances_from_entrance()
	var reserved: Dictionary = reserved_room_slots()
	var layer: int = depth_layer_for_slot(from_place)
	var destination: int = -1
	var farthest: int = -1
	for slot in range(rooms.size()):
		if slot == from_place or slot == current_place or slot == source_slot or is_treasury_slot(slot) or is_throne_slot(slot) or reserved.has(slot):
			continue
		if depth_layer_for_slot(slot) != layer or not distances.has(slot):
			continue
		# Ascending stable slots keep the lowest ID on equal entrance distance.
		if int(distances[slot]) > farthest:
			farthest = int(distances[slot])
			destination = slot
	return destination


func labyrinth_disarm_roll() -> bool:
	return _labyrinth.disarm_roll()


func _advance_labyrinth_route() -> bool:
	if phase != "raid" or not _waiting_for_entry:
		return false
	var previous: int = current_place
	var destination: int = _labyrinth.next_place(self, current_place, movement_mode == "returning")
	if not _labyrinth.neighbors(previous).has(destination):
		# Topology is frozen during raids; this guard never teleports a party.
		_log("Отряд не может перейти через закрытую границу.")
		return false
	_route_from_place = previous
	current_place = destination
	visit_id += 1
	current_slot = rooms.size() if is_throne_slot(destination) else destination
	active_target_id = ""
	defender = {}
	var message: String = "Отряд выходит из подземелья." if destination < 0 else "Отряд переходит в клетку %s." % str(_labyrinth.positions[destination])
	_log(message)
	_action("move", "party", "place_%d" % destination, 0, message)
	last_action.meta = {"from_place": previous, "to_place": destination, "visit_id": visit_id, "boundary_id": LabyrinthRules.boundary_key(previous, destination), "movement_mode": movement_mode}
	if destination < 0:
		for hero in _living():
			_settle_stolen_gold(hero, true)
			hero.escaped = true
		movement_mode = "escaped"
		_finish_wave("robbed")
		return false
	if is_treasury_slot(destination):
		_rob_treasury()
		return false
	if is_throne_slot(destination):
		return true
	var reserved: Dictionary = reserved_room_slots()
	if reserved.has(destination):
		current_slot = int(reserved[destination])
	if _encounter.has_coffin_at(current_place):
		return true
	if rooms[current_slot].is_empty() or _encounter.consumed.has(current_slot):
		return false
	if _labyrinth.is_false_treasury(self, current_slot) and _labyrinth.reveal_mimic(int(rooms[current_slot].instance_id)):
		_log("Ложная сокровищница раскрылась: отряд вступает в бой с мимиком. Казна не затронута.")
		_action("mimic_revealed", _battle_source(current_slot), "party", 0, "Вместо сокровищ — мимик")
	return true


func _rob_treasury() -> void:
	if _treasury_robbed:
		return
	_treasury_robbed = true
	var party: Array[Dictionary] = []
	for uid in _labyrinth.roster_ids:
		for hero in _living():
			if str(hero.instance_id) == uid:
				party.append(hero)
	if party.is_empty():
		return
	var stolen: int = gold / 2
	gold -= stolen
	report.stolen_gold = stolen
	var share: int = stolen / party.size()
	var remainder: int = stolen % party.size()
	for index in range(party.size()):
		_loot_shares[str(party[index].instance_id)] = share + (1 if index < remainder else 0)
	_log("Казна ограблена: отряд забрал %d золота." % stolen)
	_action("treasury_robbed", "party", "treasury", stolen, "Герои забрали половину золота из казны")
	# No gold means no departure roll and no withdrawal caused by the robbery.
	if stolen <= 0:
		return
	if not _departure_checked:
		_departure_checked = true
		if _labyrinth.departure_roll(party):
			movement_mode = "returning"
			_log("Отряд поворачивает к выходу с добычей.")
		else:
			_log("Отряд продолжает поход с добычей.")


func _settle_stolen_gold(hero: Dictionary, escaped: bool) -> void:
	var uid: String = str(hero.get("instance_id", ""))
	if not _loot_shares.has(uid):
		return
	var amount: int = int(_loot_shares[uid])
	_loot_shares.erase(uid)
	if escaped:
		report.escaped_gold = int(report.get("escaped_gold", 0)) + amount
	else:
		gold += amount
		report.returned_gold = int(report.get("returned_gold", 0)) + amount
		if amount > 0:
			_log("%s потерял добычу: возвращено %d золота." % [hero.name, amount])
			_action("loot_returned", uid, "treasury", amount, "Доля погибшего возвращена в казну")


func _try_start_labyrinth_camp() -> bool:
	if phase != "raid" or not _waiting_for_entry or current_place < 0 or is_throne_slot(current_place) or int(lord.hp) <= 0 or _living().is_empty():
		return false
	if _encounter.has_coffin_at(current_place):
		return false
	if _camp_processed_places.has(current_place) or not _camp_party_needs_healing():
		return false
	var room_slot: int = int(reserved_room_slots().get(current_place, current_place))
	if not rooms[room_slot].is_empty():
		var is_monster: bool = str(Content.room(str(rooms[room_slot].id)).kind) == "monster"
		if is_monster and not _encounter.consumed.has(room_slot):
			return false
		var empty_magazine: bool = str(rooms[room_slot].get("evolution_path", "")) == "ballista_reserve_magazine" and int(rooms[room_slot].get("evolution_memory", {}).get("ammo", 0)) <= 0
		if not is_monster and not empty_magazine and not bool(_encounter.disarmed.get(room_slot, false)) and not _encounter.consumed.has(room_slot):
			return false
	var junction: bool = _labyrinth.neighbors(current_place).size() >= 3
	var critically_wounded: bool = false
	for hero in _living():
		if int(hero.hp) < float(hero.max_hp) * LabyrinthRules.LOW_HP_FRACTION:
			critically_wounded = true
			break
	if not junction and not critically_wounded:
		return false
	_camp_processed_places[current_place] = true
	_start_camp(layout_effect_scope(current_place))
	return true


func progression_reward_facts() -> Dictionary:
	return {
		"defended_waves": defended_waves.duplicate(),
		"defeated_special_waves": defeated_special_waves.duplicate(),
		"last_completed_wave": last_completed_wave, "last_defended_wave": last_defended_wave,
		"kills": total_kills, "outcome": str(report.get("outcome", "")),
	}


func _layout_skill_description(id: String, original: String) -> String:
	if not labyrinth_enabled:
		return original
	if id == "traps_deadly_corridor":
		return "Одна ударная ловушка каждого слоя получает +15% урона: самая дальняя от входа по открытым проходам. При равенстве выбирается место с меньшим постоянным номером. Недостижимые ловушки не участвуют."
	if id == "traps_hidden_drive":
		return "Временно недоступен: новый эффект после переделки обезвреживания ещё не выбран."
	if id in ["economy_building_estimate", "economy_building_estimate_2"]:
		return "Доступ к следующему слою глубины дешевле на 5%. Сметы складываются, цена округляется вверх, минимум 1 золото. Раскопка отдельной клетки стоит 4 золота."
	if id == "economy_construction_contract":
		return "После покупки доступа к глубине одна следующая новая комната в этой подготовке дешевле на 2 золота, минимум 1. Один купон на подготовку; раскопка клетки его не выдаёт. Отмена постройки возвращает право."
	if id == "shared_fire_support":
		return "Баллиста в следующем соседнем месте поддерживает бой с существом перед ней: один настоящий выстрел на орудие за волну в том же слое. Болт расходуется; следопыт может обезвредить орудие с шансом 50%, при провале выстрел полный."
	if id == "traps_tension":
		return "+12% прямого урона баллисты всех форм. Следопыт может выключить её до конца волны с шансом 50% за один инструмент; при провале урон полный."
	return original.replace("этажа", "слоя глубины").replace("этаже", "слое глубины").replace("этажей", "слоёв глубины").replace("этажи", "слои глубины").replace("этаж", "слой глубины")


func layout_runtime_snapshot() -> Dictionary:
	# Cheap observation only: no topology search, random draw, or lazy combat state.
	var disabled_slots: Array[int] = []
	if phase in ["raid", "camp", "result"]:
		for key in _encounter.disarmed:
			var slot: int = int(key)
			if bool(_encounter.disarmed[key]) and _valid_slot(slot) and not rooms[slot].is_empty() and str(Content.room(str(rooms[slot].id)).kind) != "monster":
				disabled_slots.append(slot)
	disabled_slots.sort()
	var carried_gold: int = 0
	for amount in _loot_shares.values():
		carried_gold += int(amount)
	return {"current_place": current_place, "movement_mode": movement_mode, "loot_shares": _loot_shares.duplicate(true), "disabled_slots": disabled_slots, "carried_gold": carried_gold, "recovering_vampires": _encounter.recovery_snapshot()}

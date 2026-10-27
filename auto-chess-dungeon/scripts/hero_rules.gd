class_name HeroRules
extends RefCounted
## Pure stat/catalog rules; combat triggers belong to DungeonGame.
## Class bases already include the ordinary starting kit. Its item bonuses are zero,
## so equipping the same-quality special does not apply the starting kit twice.

const HP_CURVE_STEP: float = 0.02469507659595993
const DAMAGE_CURVE_STEP: float = 0.014889156509221957
const GAINED_LEVEL_HP: int = 10
const GAINED_LEVEL_DAMAGE: int = 2
const SLOT_IDS: Array[String] = ["weapon", "protection"]
const SPECIAL_ROLL_CHANCE: float = 0.7 # Initial tuning; the wave limits are hard caps.
const STARTING_KITS: Dictionary = {
	"knight": {"weapon": "knight_sword", "protection": "knight_shield"},
	"barbarian": {"weapon": "barbarian_axe", "protection": "barbarian_hide"},
	"rogue": {"weapon": "rogue_bow", "protection": "rogue_charm"},
	"priest": {"weapon": "priest_mace", "protection": "priest_robe"},
	"mage": {"weapon": "mage_staff", "protection": "mage_mantle"},
	"bard": {"weapon": "bard_lute", "protection": "bard_cloak"},
}
const SPECIAL_BY_CLASS: Dictionary = {
	"knight": "item_cover_shield", "barbarian": "item_armour_splitter",
	"priest": "item_last_prayer", "mage": "item_memory_staff",
	"rogue": "item_sapper_crossbow", "bard": "item_broken_rhythm_drum",
}
static var _items: Dictionary = {}


static func item(id: String) -> Dictionary:
	_ensure_items()
	return _items.get(id, {})


static func item_ids() -> Array[String]:
	_ensure_items()
	var result: Array[String] = []
	result.assign(_items.keys())
	return result


static func hp_multiplier(wave: int) -> float:
	return pow(1.0 + HP_CURVE_STEP * float(maxi(0, wave - 1)), 2.0)


static func damage_multiplier(wave: int) -> float:
	return pow(1.0 + DAMAGE_CURVE_STEP * float(maxi(0, wave - 1)), 2.0)


static func party_factors(size: int, wave: int) -> Dictionary:
	if size >= 3:
		var progress: float = clampf(float(wave - 8) / 12.0, 0.0, 1.0)
		return {"hp": lerpf(0.65, 0.8, progress), "damage": lerpf(0.65, 0.75, progress)}
	var factor: float = 0.75 if size == 2 else 1.0
	return {"hp": factor, "damage": factor}


static func scaled_stats(class_base: Dictionary, hero: Dictionary) -> Dictionary:
	var wave: int = maxi(1, int(hero.get("wave", 1)))
	# Existing saves lacking starting_level retain their former gained-level meaning.
	var gained_levels: int = maxi(0, int(hero.get("level", 1)) - int(hero.get("starting_level", 1)))
	var group_hp: float = maxf(0.0, float(hero.get("group_hp_factor", hero.get("group_factor", 1.0))))
	var group_damage: float = maxf(0.0, float(hero.get("group_damage_factor", hero.get("group_factor", 1.0))))
	var bonus: Dictionary = equipment_stats(hero)
	var base_hp: float = float(class_base.get("hp", class_base.get("max_hp", 1)))
	var base_damage: float = float(class_base.get("damage", 1))
	var scaled_hp: float = (base_hp * hp_multiplier(wave) + float(GAINED_LEVEL_HP * gained_levels)) * group_hp
	var scaled_damage: float = (base_damage * damage_multiplier(wave) + float(GAINED_LEVEL_DAMAGE * gained_levels)) * group_damage
	return {
		"max_hp": maxi(1, ceili(scaled_hp * float(hero.get("deal_hp_multiplier", 1.0))) + int(bonus.hp)),
		"damage": maxi(1, ceili(scaled_damage) + int(bonus.damage)),
		"armor": maxi(0, int(class_base.get("armor", 0)) + int(hero.get("elite_armor", 0)) + int(bonus.armor)),
	}


static func initial_equipment(class_id: String, _wave: int, _rng: RandomNumberGenerator) -> Dictionary:
	# No RNG is consumed here: the party-wide pass controls the special allowance.
	var kit: Dictionary = STARTING_KITS.get(class_id, {})
	return kit.duplicate()


static func special_limit(wave: int) -> int:
	return clampi(floori(float(maxi(0, wave)) / 10.0), 0, 3)


static func roll_party_equipment(heroes: Array, wave: int, rng: RandomNumberGenerator) -> void:
	var candidates: Array[Dictionary] = []
	var equipped_specials: int = 0
	for value in heroes:
		if not value is Dictionary:
			continue
		var hero: Dictionary = value
		ensure_equipment(hero)
		var hero_specials: int = 0
		for slot in SLOT_IDS:
			if bool(item(str(hero.equipment.get(slot, ""))).get("special", false)):
				hero_specials += 1
		equipped_specials += hero_specials
		if int(hero.get("equipment_roll_wave", -1)) == wave:
			continue
		hero.equipment_roll_wave = wave
		if hero_specials == 0 and SPECIAL_BY_CLASS.has(str(hero.get("id", ""))):
			candidates.append(hero)
	var available: int = mini(heroes.size(), special_limit(wave)) - equipped_specials
	if available <= 0:
		return
	# Fisher-Yates uses only the supplied seeded RNG, never Array.shuffle().
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index: int = rng.randi_range(0, index)
		var previous: Dictionary = candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = previous
	for hero in candidates:
		if available <= 0:
			break
		if rng.randf() > SPECIAL_ROLL_CHANCE:
			continue
		var special_id: String = str(SPECIAL_BY_CLASS[str(hero.id)])
		if equip_item(hero, special_id):
			available -= 1


static func ensure_equipment(hero: Dictionary) -> void:
	if not hero.get("equipment", null) is Dictionary:
		hero.equipment = _equipment_from_legacy(hero)
	if not hero.get("equipment_state", null) is Dictionary:
		hero.equipment_state = {}
	if not hero.get("equipment_disabled_slots", null) is Array:
		hero.equipment_disabled_slots = []


static func equipment_stats(hero: Dictionary) -> Dictionary:
	var result: Dictionary = {"hp": 0, "damage": 0, "armor": 0}
	var equipment: Dictionary = _equipment_of(hero)
	var disabled: Array = hero.get("equipment_disabled_slots", [])
	for slot in SLOT_IDS:
		if disabled.has(slot):
			continue
		var definition: Dictionary = item(str(equipment.get(slot, "")))
		result.hp = int(result.hp) + int(definition.get("hp", 0))
		result.damage = int(result.damage) + int(definition.get("damage", 0))
		result.armor = int(result.armor) + int(definition.get("armor", 0))
	# Weapon-swap damage is applied to ordinary physical hits by combat, not here.
	return result


static func item_active(hero: Dictionary, id: String) -> bool:
	var definition: Dictionary = item(id)
	if definition.is_empty():
		return false
	var slot: String = str(definition.slot)
	if str(_equipment_of(hero).get(slot, "")) != id:
		return false
	var disabled: Array = hero.get("equipment_disabled_slots", [])
	if disabled.has(slot):
		return false
	if slot == "weapon" and (bool(hero.get("weapon_swapped", false)) or int(hero.get("weapon_swap_battles", 0)) > 0):
		return false
	return true


static func can_equip(hero: Dictionary, id: String) -> bool:
	var definition: Dictionary = item(id)
	if definition.is_empty():
		return false
	var compatible: Array = definition.get("compatible_classes", [])
	return compatible.is_empty() or compatible.has(str(hero.get("id", "")))


static func equip_item(hero: Dictionary, id: String, force: bool = false) -> bool:
	if not can_equip(hero, id):
		return false
	ensure_equipment(hero)
	var definition: Dictionary = item(id)
	var slot: String = str(definition.slot)
	var previous_id: String = str(hero.equipment.get(slot, ""))
	if previous_id == id:
		return false
	if not force and item_score(id) <= item_score(previous_id):
		return false
	# Slot replacement removes old bonuses. Per-battle/per-wave uses are NOT reset.
	var next_equipment: Dictionary = hero.equipment.duplicate()
	next_equipment[slot] = id
	hero.equipment = next_equipment
	_sync_legacy_items(hero)
	return true


static func item_score(id: String) -> float:
	var definition: Dictionary = item(id)
	if definition.is_empty():
		return -1.0
	# A simple deterministic loot preference, not a visible party power rating.
	return float(definition.get("damage", 0)) * 3.0 + float(definition.get("armor", 0)) * 4.0 + float(definition.get("hp", 0)) * 0.25 + (12.0 if bool(definition.get("special", false)) else 0.0)


static func equipment_summary(hero: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var equipment: Dictionary = _equipment_of(hero)
	for slot in SLOT_IDS:
		var id: String = str(equipment.get(slot, ""))
		var definition: Dictionary = item(id)
		if definition.is_empty():
			continue
		result.append({
			"id": id, "slot": slot, "name": str(definition.name),
			"description": str(definition.description), "special": bool(definition.special),
			"visual_key": str(definition.visual_key), "icon": str(definition.icon),
			"active": item_active(hero, id),
		})
	return result


static func armor_absorbed(eligible_damage: int, actual_armor: int) -> int:
	return mini(maxi(0, actual_armor), floori(float(maxi(0, eligible_damage)) * 0.5))


static func physical_damage_after_armor(eligible_damage: int, actual_armor: int) -> int:
	return maxi(0, eligible_damage) - armor_absorbed(eligible_damage, actual_armor)


static func _equipment_of(hero: Dictionary) -> Dictionary:
	if hero.get("equipment", null) is Dictionary:
		return hero.equipment
	return _equipment_from_legacy(hero)


static func _equipment_from_legacy(hero: Dictionary) -> Dictionary:
	var kit: Dictionary = STARTING_KITS.get(str(hero.get("id", "")), {})
	var result: Dictionary = kit.duplicate()
	for value in hero.get("items", []):
		var id: String = str(value)
		var definition: Dictionary = item(id)
		if definition.is_empty() or not can_equip(hero, id):
			continue
		var slot: String = str(definition.slot)
		if item_score(id) > item_score(str(result.get(slot, ""))):
			result[slot] = id
	return result


static func _sync_legacy_items(hero: Dictionary) -> void:
	var ids: Array[String] = []
	for slot in SLOT_IDS:
		var id: String = str(hero.equipment.get(slot, ""))
		if not id.is_empty():
			ids.append(id)
	hero.items = ids


static func _add_item(id: String, name: String, slot: String, classes: Array, description: String, visual_key: String, stats: Dictionary = {}, special_params: Dictionary = {}) -> void:
	classes.make_read_only()
	special_params.make_read_only()
	var entry: Dictionary = {
		"id": id, "name": name, "slot": slot, "compatible_classes": classes,
		"compatible_class": str(classes[0]) if classes.size() == 1 else "",
		"description": description, "visual_key": visual_key,
		"special": not special_params.is_empty(), "params": special_params,
		"hp": int(stats.get("hp", 0)), "damage": int(stats.get("damage", 0)), "armor": int(stats.get("armor", 0)),
		"icon": "res://assets/icons/%s.svg" % ("sword" if slot == "weapon" else "shield"),
	}
	entry.make_read_only()
	_items[id] = entry


static func _ensure_items() -> void:
	if not _items.is_empty():
		return
	_add_item("knight_sword", "Рыцарский меч", "weapon", ["knight"], "Обычный меч рыцаря.", "sword")
	_add_item("knight_shield", "Рыцарский щит", "protection", ["knight"], "Обычная защита рыцаря.", "shield")
	_add_item("barbarian_axe", "Боевой топор", "weapon", ["barbarian"], "Тяжёлый топор варвара.", "axe")
	_add_item("barbarian_hide", "Звериная шкура", "protection", ["barbarian"], "Лёгкая шкура без брони.", "hide")
	_add_item("rogue_bow", "Лук следопыта", "weapon", ["rogue"], "Походный лук разведчика.", "bow")
	_add_item("rogue_charm", "Лесной оберег", "protection", ["rogue"], "Оберег следопыта без тяжёлой брони.", "charm")
	_add_item("priest_mace", "Храмовая булава", "weapon", ["priest"], "Оружие жрицы для обычных ударов.", "mace")
	_add_item("priest_robe", "Храмовое облачение", "protection", ["priest"], "Защитное облачение жрицы.", "robe")
	_add_item("mage_staff", "Посох чародея", "weapon", ["mage"], "Простой посох без запаса заклинаний.", "staff")
	_add_item("mage_mantle", "Мантия ученика", "protection", ["mage"], "Лёгкая мантия чародея.", "mantle")
	_add_item("bard_lute", "Походная лютня", "weapon", ["bard"], "Инструмент для песни и обычных атак барда.", "lute")
	_add_item("bard_cloak", "Плащ менестреля", "protection", ["bard"], "Дорожный плащ без тяжёлой брони.", "cloak")
	# Stable legacy trophy IDs remain compatible with every class.
	_add_item("sword", "Меч палача", "weapon", [], "Трофей: +3 урона вместо прежнего оружия.", "executioner_sword", {"damage": 3})
	_add_item("shield", "Щит мимика", "protection", [], "Трофей: +1 брони вместо прежнего защитного предмета.", "mimic_shield", {"armor": 1})
	_add_item("item_cover_shield", "Щит прикрытия", "protection", ["knight"],
		"Раз за бой при ротации с участием рыцаря новый ведущий получает на 30% меньше урона от первого обычного физического удара следующего раунда.",
		"cover_shield", {}, {"damage_factor": 0.7, "uses_per_battle": 1, "duration_rounds": 1})
	_add_item("item_armour_splitter", "Топор раскола", "weapon", ["barbarian"],
		"Три успешных удара по одному защитнику раскрывают 1 броню на следующие два раунда. Раз за бой; полностью поглощённые удары не считаются.",
		"armour_splitter", {}, {"hits_required": 3, "armor_reduction": 1, "duration_rounds": 2, "uses_per_battle": 1})
	_add_item("item_last_prayer", "Оберег последней молитвы", "protection", ["priest"],
		"При гибели жрицы один раз лечит наиболее раненого живого союзника как обычная молитва. Безмолвие, кокон и перегородки мешают.",
		"last_prayer", {}, {"healing_factor": 1.0, "uses_per_wave": 1})
	_add_item("item_memory_staff", "Посох памяти", "weapon", ["mage"],
		"Раз за бой сохраняет готовое заклинание под безмолвием. После освобождения выпускает его следующим действием вместо атаки, без второго заряда.",
		"memory_staff", {}, {"stored_charges": 1, "uses_per_battle": 1})
	_add_item("item_sapper_crossbow", "Арбалет сапёра", "weapon", ["rogue"],
		"Раз за волну вместе с обычной атакой тратит инструмент и заранее ослабляет следующую соседнюю ловушку того же этажа.",
		"sapper_crossbow", {}, {"uses_per_wave": 1, "tool_cost": 1})
	_add_item("item_broken_rhythm_drum", "Барабан сбитого ритма", "weapon", ["bard"],
		"Раз за бой вместо атаки задерживает подготовленный тяжёлый физический удар существа на один раунд. Один замах нельзя задержать повторно.",
		"broken_rhythm_drum", {}, {"delay_rounds": 1, "uses_per_battle": 1})
	_items.make_read_only()

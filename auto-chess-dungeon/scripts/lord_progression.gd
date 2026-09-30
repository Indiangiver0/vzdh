extends RefCounted
## Persistent lord collection. Every rejected action leaves the input untouched.
## Callers save the returned/mutated subprofile under profile["lords"].

const Catalog = preload("res://scripts/lord_catalog.gd")
const DEFAULT_LORD: String = "fallen_knight"


static func default_profile() -> Dictionary:
	var unlocked: Array[String] = [DEFAULT_LORD]
	return {
		"souls": 0,
		"unlocked": unlocked,
		"levels": {DEFAULT_LORD: 1},
		"variants": {DEFAULT_LORD: "base"},
		"selected": DEFAULT_LORD,
	}


static func sanitize(data: Variant) -> Dictionary:
	var result: Dictionary = default_profile()
	if not data is Dictionary:
		return result
	result["souls"] = maxi(0, _safe_int(data.get("souls", 0)))
	var owned = data.get("unlocked", [])
	if owned is Array or owned is PackedStringArray:
		for candidate in owned:
			if not candidate is String:
				continue
			if Catalog.ids().has(candidate) and not result["unlocked"].has(candidate):
				result["unlocked"].append(candidate)
	var raw_levels = data.get("levels", {})
	var raw_variants = data.get("variants", {})
	for id in result["unlocked"]:
		var level: int = 1
		if raw_levels is Dictionary:
			level = clampi(_safe_int(raw_levels.get(id, 1), 1), 1, Catalog.MAX_MASTERY)
		result["levels"][id] = level
		var requested_variant: String = "base"
		if raw_variants is Dictionary and raw_variants.get(id, "base") is String:
			requested_variant = str(raw_variants.get(id, "base"))
		result["variants"][id] = str(Catalog.ability_values(id, level, requested_variant)["variant"])
	var selected = data.get("selected", DEFAULT_LORD)
	if selected is String and result["unlocked"].has(selected):
		result["selected"] = selected
	return result


static func purchase(profile: Dictionary, id: String) -> String:
	var definition: Dictionary = Catalog.get_lord(id)
	if definition.is_empty():
		return "Такого Владыки нет."
	var state: Dictionary = sanitize(profile)
	if state["unlocked"].has(id):
		return "Этот Владыка уже открыт."
	var price: int = int(definition["unlock_cost"])
	if int(state["souls"]) < price:
		return "Не хватает душ: нужно %d." % price
	state["souls"] = int(state["souls"]) - price
	state["unlocked"].append(id)
	state["levels"][id] = 1
	state["variants"][id] = "base"
	_commit(profile, state)
	return ""


static func upgrade(profile: Dictionary, id: String) -> String:
	if Catalog.get_lord(id).is_empty():
		return "Такого Владыки нет."
	var state: Dictionary = sanitize(profile)
	if not state["unlocked"].has(id):
		return "Сначала откройте этого Владыку."
	var level: int = int(state["levels"][id])
	if level >= Catalog.MAX_MASTERY:
		return "Достигнут максимальный уровень мастерства."
	var price: int = Catalog.upgrade_cost(level)
	if int(state["souls"]) < price:
		return "Не хватает душ: нужно %d." % price
	state["souls"] = int(state["souls"]) - price
	state["levels"][id] = level + 1
	_commit(profile, state)
	return ""


static func select(profile: Dictionary, id: String) -> String:
	if Catalog.get_lord(id).is_empty():
		return "Такого Владыки нет."
	var state: Dictionary = sanitize(profile)
	if not state["unlocked"].has(id):
		return "Сначала откройте этого Владыку."
	state["selected"] = id
	_commit(profile, state)
	return ""


static func select_variant(profile: Dictionary, id: String, variant_id: String) -> String:
	var definition: Dictionary = Catalog.get_lord(id)
	if definition.is_empty():
		return "Такого Владыки нет."
	var state: Dictionary = sanitize(profile)
	if not state["unlocked"].has(id):
		return "Сначала откройте этого Владыку."
	var found: Dictionary = {}
	for option in definition["variants"]:
		if str(option["id"]) == variant_id:
			found = option
			break
	if found.is_empty():
		return "Такого варианта способности нет."
	if int(state["levels"][id]) < int(found["min_mastery"]):
		return "Нужно мастерство уровня %d." % int(found["min_mastery"])
	state["variants"][id] = variant_id
	_commit(profile, state)
	return ""


static func mastery(profile: Dictionary, id: String) -> int:
	var state: Dictionary = sanitize(profile)
	return int(state["levels"].get(id, 1))


static func variant(profile: Dictionary, id: String) -> String:
	var state: Dictionary = sanitize(profile)
	return str(state["variants"].get(id, "base"))


static func reward(cleared: int, kills: int, previous_best: int) -> Dictionary:
	var completed: int = maxi(0, cleared)
	var kill_count: int = maxi(0, kills)
	var record: int = maxi(0, previous_best)
	var wave_reward: int = 2 * completed
	var kill_reward: int = floori(float(kill_count) / 3.0)
	var elite_reward: int = 5 * floori(float(completed) / 5.0)
	var new_milestones: int = maxi(0, floori(float(completed) / 5.0) - floori(float(record) / 5.0))
	var milestone_reward: int = 10 * new_milestones
	return {
		"waves": wave_reward, "kills": kill_reward,
		"elites": elite_reward, "milestones": milestone_reward,
		"total": wave_reward + kill_reward + elite_reward + milestone_reward,
	}


static func _safe_int(value: Variant, fallback: int = 0) -> int:
	if value is int:
		return int(value)
	if value is float and is_finite(float(value)):
		return int(value)
	return fallback


static func _commit(profile: Dictionary, state: Dictionary) -> void:
	profile.clear()
	profile.merge(state, true)

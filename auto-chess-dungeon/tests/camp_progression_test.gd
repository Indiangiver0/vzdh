extends SceneTree
## Focused 2.1.1 progression regressions. Uses only synthetic in-memory runs.
const Game = preload("res://scripts/dungeon_game.gd")
const Catalog = preload("res://scripts/run_skill_catalog.gd")
const SEED: int = 20261027
const NEW_IDS: Array[String] = ["shared_restless_dungeons_1", "shared_restless_dungeons_2", "shared_restless_dungeons_3", "poison_caustic_vapors"]
const PARENTS: Array[String] = ["traps_mechanisms_2", "shared_restless_dungeons_1", "shared_restless_dungeons_2", "poison_bitter_medicine"]
const COSTS: Array[int] = [2, 4, 6, 4]
var checks: int = 0
var failures: Array[String] = []
var observations: Array[Dictionary] = []
var groups: Array[String] = []
var artifact_dir: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	artifact_dir = OS.get_environment("CAMP_PROGRESSION_ARTIFACTS").replace("\\", "/")
	var user_dir: String = OS.get_user_data_dir().replace("\\", "/")
	print("USER_DIR=", user_dir)
	print("SEED=", SEED)
	_check(not artifact_dir.is_empty() and user_dir.to_lower().begins_with(artifact_dir.to_lower() + "/"), "user_dir belongs to isolated artifact directory")
	if not failures.is_empty():
		_finish(user_dir)
		return
	_catalog_contract()
	_purchase_contract()
	_read_purity()
	_bought_camp_effects()
	_lifecycle()
	_check(groups == ["catalog", "purchases", "read_purity", "camp_effects", "lifecycle"], "all five test groups completed")
	_finish(user_dir)

func _finish(user_dir: String) -> void:
	var result: Dictionary = {"suite": "camp_progression_test", "seed": SEED, "checks": checks, "failures": failures, "completed_groups": groups, "user_dir": user_dir, "artifact_dir": artifact_dir, "observations": observations, "status": "PASS" if failures.is_empty() and groups.size() == 5 else "FAIL"}
	var output := FileAccess.open(artifact_dir.path_join("result.json"), FileAccess.WRITE)
	if output == null:
		print("FAIL cannot write result.json")
		quit(2)
		return
	output.store_string(JSON.stringify(result, "\t"))
	output.close()
	print("CAMP PROGRESSION ", result.status, ": ", checks, " checks, ", failures.size(), " failures")
	quit(0 if result.status == "PASS" else 1)

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL ", message)

func _new_game() -> RefCounted:
	var game = Game.new(false)
	game.restart(SEED)
	return game

func _json_document(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_check(file != null, "read catalog " + path)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	_check(value is Dictionary, "catalog is JSON object " + path)
	return value if value is Dictionary else {}

func _catalog_contract() -> void:
	var live: Dictionary = _json_document("res://data/run_skills.json")
	var baseline: Dictionary = _json_document(OS.get_environment("CAMP_PROGRESSION_BASELINE"))
	var current: Dictionary = {}
	var old: Dictionary = {}
	for row: Dictionary in live.get("skills", []):
		var id: String = str(row.id)
		_check(not id.is_empty() and not current.has(id), "unique current ID " + id)
		current[id] = row
	for row: Dictionary in baseline.get("skills", []):
		var id: String = str(row.id)
		_check(not id.is_empty() and not old.has(id), "unique baseline ID " + id)
		old[id] = row
	_check(current.size() == 124, "exactly 124 current IDs")
	_check(old.size() == 120, "exactly 120 baseline IDs")
	var added: Array[String] = []
	for id: String in current:
		if not old.has(id):
			added.append(id)
	added.sort()
	var expected_added: Array[String] = NEW_IDS.duplicate()
	expected_added.sort()
	_check(added == expected_added, "exactly four approved added IDs")
	for id: String in old:
		_check(current.has(id) and current[id] == old[id], "unchanged full old definition " + id)
	var game = _new_game()
	for index in range(NEW_IDS.size()):
		var id: String = NEW_IDS[index]
		var node: Dictionary = game.run_skill_state(id)
		_check(int(node.cost) == COSTS[index] and int(node.soul_price) == COSTS[index], "approved price " + id)
		_check(node.requires_all == [PARENTS[index]] and node.requires_any.is_empty(), "approved prerequisite " + id)
		_check(node.parents == [PARENTS[index]] and node.requirements.all_of == [PARENTS[index]] and node.prerequisites.all_of == [PARENTS[index]], "all prerequisite representations agree " + id)
		_check(int(node.purchases_per_node) == 1 and str(node.required_lord).is_empty(), "one purchase and no lord restriction " + id)
		if index < 3:
			_check(int(node.camp_duration_seconds) == [8, 6, 5][index], "approved duration " + id)
	for definition: Dictionary in Catalog.all_skills():
		var id: String = str(definition.id)
		var expected: Dictionary = Catalog.get_skill(id)
		definition.cost = -999
		definition.requires_all.append("mutated_return")
		definition.requirements.all_of.append("mutated_nested_return")
		_check(Catalog.get_skill(id) == expected, "all_skills returns deep independent definition " + id)
		var single: Dictionary = Catalog.get_skill(id)
		single.requirements.all_of.append("mutated_single_return")
		single.cost = -42
		_check(Catalog.get_skill(id) == expected, "get_skill returns deep independent definition " + id)
		var state: Dictionary = game.run_skill_state(id)
		var expected_state: Dictionary = state.duplicate(true)
		state.requires_all.append("mutated_state")
		state.requirements.all_of.append("mutated_state_nested")
		_check(game.run_skill_state(id) == expected_state, "run_skill_state returns independent definition " + id)
	observations.append({"catalog_count": current.size(), "baseline_count": old.size(), "baseline_revision": "682938c", "added_ids": added})
	groups.append("catalog")

func _rng_state(game) -> Array:
	return [game.rng.state, game.talent_rng.state, game.expedition_rng.state, game.deal_rng.state, game.soul_rng.state]

func _snapshot(game) -> Dictionary:
	return {"gold": game.gold, "souls": game.run_souls, "learned": game.learned_skills.duplicate(true), "runtime": game.run_skill_runtime.duplicate(true), "rng": _rng_state(game), "lord": game.lord.duplicate(true), "heroes": game.heroes.duplicate(true), "rooms": game.rooms.duplicate(true), "logs": game.logs.duplicate(), "report": game.report.duplicate(true), "phase": game.phase, "camp": game._camp_state.duplicate(true), "camp_floors": game._camp_processed_floors.duplicate(true), "camp_interruptions": game._camp_interruptions, "action_seq": game.action_seq, "last_action": game.last_action.duplicate(true), "soul_failures": game.soul_failures, "ability_charges": game.ability_charges, "income_snapshot": game._ability_income_snapshot, "price_snapshot": game._ability_price_snapshot}

func _signals(game) -> Dictionary:
	var observed: Dictionary = {"souls": [], "skills": [], "wallets": [], "learned_during_souls": []}
	var weak_game: WeakRef = weakref(game)
	game.run_souls_changed.connect(func(total: int, delta: int):
		observed.souls.append([total, delta])
		observed.wallets.append(weak_game.get_ref().run_souls)
		observed.learned_during_souls.append(weak_game.get_ref().learned_skills.duplicate(true)))
	game.run_skill_learned.connect(func(id: String): observed.skills.append(id))
	return observed

func _reject(game, id: String, reason_part: String, label: String) -> void:
	var observed: Dictionary = _signals(game)
	var before: Dictionary = _snapshot(game)
	var state: Dictionary = game.run_skill_state(id)
	_check(not bool(state.available) and not bool(state.get("can_buy", false)), label + " unavailable state")
	_check(str(state.reason).contains(reason_part), label + " correct reason: " + str(state.reason))
	_check(not game.buy_run_skill(id), label + " purchase refused")
	_check(_snapshot(game) == before, label + " atomic unchanged state")
	_check(observed.souls.is_empty() and observed.skills.is_empty(), label + " zero purchase signals")

func _buy_chain(game, id: String, depth: int = 0) -> void:
	if game.has_run_skill(id) or id == "start":
		return
	_check(depth < 32, "bounded prerequisite traversal " + id)
	if depth >= 32:
		return
	var state: Dictionary = game.run_skill_state(id)
	for required: String in state.get("requires_all", []):
		_buy_chain(game, required, depth + 1)
	var any_of: Array = state.get("requires_any", [])
	if not any_of.is_empty():
		var met: bool = false
		for required: String in any_of:
			met = met or game.has_run_skill(required) or required == "start"
		if not met:
			_buy_chain(game, str(any_of[0]), depth + 1)
	game.run_souls = int(state.cost)
	_check(game.buy_run_skill(id), "real prerequisite purchase " + id)
	_check(game.run_souls == 0 and game.has_run_skill(id), "exact payment for prerequisite " + id)

func _purchase_contract() -> void:
	for index in range(NEW_IDS.size()):
		var id: String = NEW_IDS[index]
		var cost: int = COSTS[index]
		var game = _new_game()
		game.run_souls = 100
		_reject(game, id, "Сначала изучите", id + " missing prerequisite")
		_buy_chain(game, PARENTS[index])
		for budget: int in [0, cost - 1]:
			game.run_souls = budget
			_reject(game, id, "Не хватает душ", id + " insufficient souls " + str(budget))
		game.run_souls = cost
		for locked_phase: String in ["raid", "camp", "result"]:
			game.phase = locked_phase
			_reject(game, id, "между волнами", id + " phase " + locked_phase)
		game.phase = "prepare"
		var observed: Dictionary = _signals(game)
		var previous_skills: int = game.learned_skills.size()
		var previous_rng: Array = _rng_state(game)
		var previous_gold: int = game.gold
		_check(bool(game.run_skill_state(id).available), id + " available with exact souls")
		_check(game.buy_run_skill(id), id + " exact payment succeeds")
		_check(game.run_souls == 0 and game.gold == previous_gold, id + " exact souls debit and unchanged gold")
		_check(game.has_run_skill(id) and game.learned_skills.size() == previous_skills + 1, id + " learned once")
		_check(observed.souls == [[0, -cost]] and observed.skills == [id], id + " one signal of each type")
		_check(observed.wallets == [0] and bool(observed.learned_during_souls[0].get(id, false)), id + " listeners see committed purchase")
		_check(_rng_state(game) == previous_rng, id + " purchase does not consume RNG")
		game.run_souls = cost + 1
		_reject(game, id, "Уже изучено", id + " repeat with enough souls")
		_check(observed.souls.size() == 1 and observed.skills.size() == 1, id + " repeated purchase emits no additional signals")
	var unknown_game = _new_game()
	unknown_game.run_souls = 99
	_reject(unknown_game, "nonexistent_camp_skill", "Неизвестный", "unknown skill")
	groups.append("purchases")

func _read_purity() -> void:
	var game = _new_game()
	_buy_chain(game, NEW_IDS[2])
	_buy_chain(game, NEW_IDS[3])
	game.run_souls = 19
	var tree: Array[Dictionary] = game.run_skill_tree()
	var before: Dictionary = _snapshot(game)
	for iteration in range(8):
		_check(game.run_skill_tree() == tree, "stable tree read " + str(iteration))
		for id: String in NEW_IDS:
			game.run_skill_state(id)
			game.run_skill_definition(id)
			game.run_skill_number(id, "camp_duration_seconds", 10.0)
		game.run_skill_modifiers()
		game.camp_status()
		game.camp_interrupt_cost()
		_check(_snapshot(game) == before, "view/read preserves wallets RNG and state " + str(iteration))
	tree[0].requires_all.append("mutated_tree")
	tree[0].cost = -7
	_check(game.run_skill_tree()[0].cost != -7 and not game.run_skill_tree()[0].requires_all.has("mutated_tree"), "tree result is independent")
	groups.append("read_purity")

func _reach_camp(game, with_priest: bool = false) -> bool:
	game.gold = 100
	game.shop["spikes"] = 1
	_check(game.buy_room(0, "spikes").is_empty(), "fixture buys route trap through model")
	var hero: Dictionary = game.heroes[0].duplicate(true)
	hero.id = "knight"
	hero.instance_id = "progression_knight"
	hero.name = "Progression Knight"
	hero.hp = 100
	hero.max_hp = 1000
	hero.tree_base_hp = 1000.0
	hero.damage = 0
	hero.tree_base_damage = 0.0
	hero.armor = 0
	hero.poison_ticks = 0
	hero.poison_damage = 0
	hero.poison_heal_factor = 1.0
	hero.items = []
	hero.equipment = {}
	hero.effects = {}
	game.heroes.assign([hero])
	if with_priest:
		var priest: Dictionary = hero.duplicate(true)
		priest.id = "priest"
		priest.instance_id = "progression_priest"
		priest.name = "Progression Priest"
		priest.level = 5
		priest.hp = 1000
		game.heroes.append(priest)
	_check(game.start_raid().is_empty(), "fixture starts real raid")
	for iteration in range(80):
		if game.phase != "raid":
			break
		game.step()
	_check(game.phase == "camp", "bounded route reaches real camp")
	return game.phase == "camp"

func _bought_camp_effects() -> void:
	for tier in range(4):
		var game = _new_game()
		if tier > 0:
			_buy_chain(game, NEW_IDS[tier - 1])
		if not _reach_camp(game):
			continue
		var duration: int = [10, 8, 6, 5][tier]
		_check(int(game.camp_status().duration) == duration, "bought tier " + str(tier) + " actual camp duration")
		var hp_before: int = int(game.heroes[0].hp)
		var expected_hp: int = hp_before + duration * 50
		game.advance_camp(float(duration))
		_check(game.phase == "raid" and int(game.heroes[0].hp) == expected_hp, "bought tier " + str(tier) + " expected total healing")
		observations.append({"tier": tier, "duration": duration, "healed_hp": int(game.heroes[0].hp) - hp_before, "max_hp": 1000})
	for learned_vapors: bool in [false, true]:
		var game = _new_game()
		_buy_chain(game, PARENTS[3])
		if learned_vapors:
			_buy_chain(game, NEW_IDS[3])
		if not _reach_camp(game, true):
			continue
		game.heroes[0].poison_ticks = 4
		game.heroes[0].poison_damage = 2.0
		var expected_factor: float = 0.9 if learned_vapors else 0.95
		var before: Dictionary = _snapshot(game)
		var status: Dictionary = game.camp_status()
		_check(is_equal_approx(float(status.heroes[0].healing_factor), expected_factor), "bought vapors " + str(learned_vapors) + " actual camp factor")
		_check(int(status.heroes[0].remaining_healing) == (450 if learned_vapors else 475), "bought vapors expected remaining healing")
		status.heroes[0].hp = -99
		_check(_snapshot(game) == before and int(game.camp_status().heroes[0].hp) > 0, "active camp status is pure independent copy")
		var hp_before: int = int(game.heroes[0].hp)
		game.advance_camp(2.0)
		_check(int(game.heroes[0].hp) - hp_before == (90 if learned_vapors else 95), "bought vapors actual two-pulse healing")
		_check(int(game.heroes[0].poison_ticks) == 4, "bought vapors camp preserves poison duration")
		observations.append({"caustic_vapors_purchased": learned_vapors, "healing_factor": expected_factor, "two_pulse_healing": int(game.heroes[0].hp) - hp_before})
	groups.append("camp_effects")

func _lifecycle() -> void:
	var game = _new_game()
	for id: String in NEW_IDS:
		_buy_chain(game, id)
	game.run_souls = 23
	var learned: Dictionary = game.learned_skills.duplicate(true)
	if not _reach_camp(game):
		return
	_check(game.learned_skills == learned and game.run_souls == 23, "skills and souls survive start_raid and camp entry")
	var locked_id: String = "creatures_vitality_1"
	# Pick a genuinely available unlearned root in a temporary prepare view, then restore camp.
	game.phase = "prepare"
	for node: Dictionary in game.run_skill_tree():
		if bool(node.available):
			locked_id = str(node.id)
			break
	game.phase = "camp"
	_reject(game, locked_id, "между волнами", "purchase in actual active camp")
	game.advance_camp(5.0)
	_check(game.phase == "raid", "camp ends after purchased tier III duration")
	# Small synthetic encounter, retaining real step/finish/next_wave transitions.
	for hero: Dictionary in game.heroes:
		hero.hp = 1
		hero.damage = 0
		hero.tree_base_damage = 0.0
	game.lord.hp = 100000
	game.lord.max_hp = 100000
	game.lord.tree_base_hp = 100000.0
	game.lord.damage = 100000
	game.lord.tree_base_damage = 100000.0
	var steps: int = 0
	while game.phase in ["raid", "camp"] and steps < 120:
		if game.phase == "camp":
			game.advance_camp(1.0)
		else:
			game.step()
		steps += 1
	_check(game.phase == "result", "bounded lifecycle reaches actual result")
	_check(game.learned_skills == learned, "learned skills survive completed wave")
	_reject(game, locked_id, "между волнами", "purchase in actual result")
	var souls_after_rewards: int = game.run_souls
	_check(game.next_wave().is_empty() and game.wave == 2 and game.phase == "prepare", "actual next_wave enters wave 2 preparation")
	_check(game.learned_skills == learned and game.run_souls == souls_after_rewards, "next_wave retains learned skills and earned wallet")
	for id: String in NEW_IDS:
		_check(bool(game.run_skill_state(id).learned), "next_wave state shows learned " + id)
	var catalog_before: Array[Dictionary] = Catalog.all_skills()
	game.restart(SEED)
	_check(game.run_souls == 0 and game.learned_skills.is_empty() and game.run_skill_runtime.is_empty(), "restart resets run souls skills and runtime")
	_check(game.phase == "prepare" and game.wave == 1 and game.gold == 18, "restart restores new-run state")
	_check(Catalog.all_skills() == catalog_before, "restart preserves immutable definitions")
	for id: String in NEW_IDS:
		_check(not bool(game.run_skill_state(id).learned), "restart state shows unlearned " + id)
	observations.append({"lifecycle_battle_steps": steps, "souls_before_battle": 23, "souls_after_rewards": souls_after_rewards, "learned_before_restart": learned.keys()})
	groups.append("lifecycle")
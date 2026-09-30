extends SceneTree
## Bounded economy probe: only normal model actions, with no injected gold or stats.

const Game = preload("res://scripts/dungeon_game.gd")
const Content = preload("res://scripts/content_catalog.gd")
const WAVE_LIMIT: int = 40
const STEP_LIMIT: int = 20000
var failed: bool = false


func _initialize() -> void:
	print("BALANCE PROBE: normal purchases, seed-controlled shops, no state cheats")
	for policy in ["mixed", "traps", "creatures"]:
		var scores: Array[int] = []
		for run_seed in [11, 42, 93, 517, 2026, 7319, 8812, 44119, 55107, 99001]:
			scores.append(_run_strategy(run_seed, policy))
		var total: int = 0
		for score in scores:
			total += score
		print("SUMMARY policy=%s runs=%d min=%d mean=%.1f max=%d" % [policy, scores.size(), scores.min(), float(total) / scores.size(), scores.max()])
	quit(1 if failed else 0)


func _run_strategy(run_seed: int, policy: String) -> int:
	var game = Game.new()
	game.restart(run_seed)
	var floor_2_wave: int = 0
	var floor_3_wave: int = 0
	var lord_damage: int = 0
	var total_healing_gold: int = 0
	var step_count: int = 0
	while game.wave <= WAVE_LIMIT and game.phase != "defeat":
		if game.phase == "result":
			game.next_wave()
		while game.phase == "level_up":
			game.choose_upgrade("trap" if policy == "traps" else ("damage" if int(game.upgrades.damage) <= int(game.upgrades.hp) else "hp"))
		_resolve_floor_choice(game, policy)
		if game.wave > WAVE_LIMIT:
			break
		# Restore a moderately healthy lord before spending on construction.
		while float(game.lord.hp) < float(game.lord.max_hp) * 0.65 and game.gold >= game.heal_cost():
			total_healing_gold += game.heal_cost()
			game.heal_lord()
		_fill_slots(game, policy)
		if _first_empty(game) == -1 and game.floor_count < 3 and game.gold >= game.floor_cost() + 3:
			game.buy_floor()
			_resolve_floor_choice(game, policy)
			if game.floor_count == 2:
				floor_2_wave = game.wave
			if game.floor_count == 3:
				floor_3_wave = game.wave
			_fill_slots(game, policy)
		if game.floor_count >= 3 and _first_empty(game) == -1:
			_upgrade_cheapest(game, policy)
		_specialize_rooms(game, policy)
		_order_rooms(game)
		var start_error: String = game.start_raid()
		if not start_error.is_empty():
			push_error("Probe cannot start raid: " + start_error)
			failed = true
			return game.cleared_waves
		var raid_steps: int = 0
		while game.phase == "raid" and raid_steps < STEP_LIMIT:
			game.step()
			raid_steps += 1
		step_count += raid_steps
		lord_damage += int(game.report.lord_damage)
		if game.phase == "raid":
			push_error("Probe exceeded per-wave step limit")
			failed = true
			return game.cleared_waves
	print("policy=%s seed=%d survived=%d floors=%d floor2@%d floor3@%d kills=%d lordLv=%d gold=%d healSpent=%d lordDamage=%d steps=%d end=%s" % [policy, run_seed, game.cleared_waves, game.floor_count, floor_2_wave, floor_3_wave, game.total_kills, int(game.lord.level), game.gold, total_healing_gold, lord_damage, step_count, game.phase])
	return game.cleared_waves


func _resolve_floor_choice(game, policy: String) -> void:
	if game.phase != "floor_choice":
		return
	var trait_id: String = "workshop"
	if policy == "traps":
		trait_id = "laboratory"
	elif policy == "creatures":
		trait_id = "barracks"
	var error: String = game.choose_floor_trait(trait_id)
	if not error.is_empty():
		push_error("Probe floor choice failed: " + error)
		failed = true


func _specialize_rooms(game, policy: String) -> void:
	for index in range(game.rooms.size()):
		var options: Array = game.specialization_options(index)
		if options.is_empty():
			continue
		var id: String = str(game.rooms[index].id)
		var desired: String = "fury" if policy == "creatures" else "bulwark"
		if id == "poison":
			desired = "virulent" if policy == "traps" else "lingering"
		elif id == "spikes":
			desired = "volley" if policy == "traps" else "piercing"
		for option in options:
			if str(option.id) == desired:
				game.specialize_room(index, desired)
				break


func _first_empty(game) -> int:
	for index in range(game.rooms.size()):
		if game.rooms[index].is_empty():
			return index
	return -1


func _fill_slots(game, policy: String) -> void:
	var preference: Array[String] = ["poison", "spikes", "executioner", "mimic", "spider", "goblin"]
	if policy == "mixed":
		preference.assign(["poison", "executioner", "spider", "spikes", "mimic", "goblin"])
	elif policy == "traps":
		preference.assign(["poison", "spikes"])
	elif policy == "creatures":
		preference.assign(["executioner", "spider", "goblin", "mimic"])
	for id in preference:
		while int(game.shop.get(id, 0)) > 0 and game.gold >= int(Content.room(id).cost):
			var empty: int = _first_empty(game)
			if empty == -1:
				return
			# One poison room per floor lets status damage tick against defenders.
			if id == "poison" and _count(game, id) >= game.floor_count:
				break
			if not game.buy_room(empty, id).is_empty():
				break


func _count(game, id: String) -> int:
	var count: int = 0
	for room in game.rooms:
		if not room.is_empty() and str(room.id) == id:
			count += 1
	return count


func _upgrade_cheapest(game, policy: String) -> void:
	for _buy in range(20):
		var target: int = -1
		var price: int = 2147483647
		for index in range(game.rooms.size()):
			var id: String = str(game.rooms[index].id)
			if policy == "traps" and id not in ["spikes", "poison"]:
				continue
			if policy == "mixed" and id in ["goblin", "mimic"]:
				continue
			var candidate: int = game.upgrade_cost(index)
			if candidate < price:
				target = index
				price = candidate
		if target == -1 or game.gold < price:
			break
		game.upgrade_room(target)


func _order_rooms(game) -> void:
	# Poison first, then efficient damage; expensive rewards are delayed.
	var preference: Array[String] = ["poison", "spikes", "spider", "executioner", "mimic", "goblin"]
	var target: int = 0
	for id in preference:
		for index in range(target, game.rooms.size()):
			if not game.rooms[index].is_empty() and str(game.rooms[index].id) == id:
				game.move_room(index, target)
				target += 1

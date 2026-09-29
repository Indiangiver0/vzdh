extends SceneTree
## Headless regression checks for the deterministic game model.
## Run: Godot_console.exe --headless --path . --script res://tests/smoke_test.gd

const Game = preload("res://scripts/dungeon_game.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_test_start_and_economy()
	_test_healing_and_insufficient_funds()
	_test_wave_generation()
	_test_unlimited_floors_and_throne()
	_test_room_isolation_and_movement()
	_test_raid_determinism()
	_test_defeat_and_rewards()
	_test_old_room_sale_and_persistence()
	_test_party_targeting_and_healing()
	_test_poison_order_and_traps()
	_test_hero_xp_and_equipment()
	_test_lord_levels_and_rage()
	if failures.is_empty():
		print("PASS: %d game checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d game checks failed" % [failures.size(), checks])
		quit(1)


func _game(seed_value: int = 7319):
	var game = Game.new()
	game.restart(seed_value)
	return game


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _ok(result: String, description: String) -> void:
	_expect(result.is_empty(), "%s: %s" % [description, result])


func _finish_raid(game, batch_size: int = 1) -> int:
	var steps: int = 0
	while game.phase == "raid" and steps < 10000:
		for _tick in range(batch_size):
			if game.phase != "raid":
				break
			game.step()
			steps += 1
	_expect(steps < 10000, "Raid terminates within bounded simulation time")
	return steps


func _test_start_and_economy() -> void:
	var game = _game()
	_expect(game.phase == "prepare", "New run starts in preparation")
	_expect(game.wave == 1 and game.floor_count == 1 and game.rooms.size() == 5, "New run has wave 1 and five build slots")
	_expect(game.gold == 18, "New run has design starting gold")
	_expect(game.shop.size() == 4 and game.shop.has("goblin") and game.shop.has("spikes"), "Shop has four distinct types including guaranteed rooms")
	var initial_gold: int = game.gold
	var initial_stock: int = game.shop["goblin"]
	_ok(game.buy_room(0, "goblin"), "Buy guaranteed goblin room")
	_expect(game.gold == initial_gold - 3 and game.shop["goblin"] == initial_stock - 1, "Purchase charges exact cost and stock")
	_ok(game.upgrade_room(0), "Upgrade a new room")
	_expect(game.gold == initial_gold - 9, "Rank 2 costs twice base room cost")
	_ok(game.sell_room(0), "Cancel new room including upgrade")
	_expect(game.gold == initial_gold and game.shop["goblin"] == initial_stock, "Cancellation refunds full investment and stock")
	_expect(game.rooms[0].is_empty(), "Cancellation clears slot")
	_expect(not game.buy_room(-1, "goblin").is_empty(), "Negative slot index is rejected")
	_expect(not game.buy_room(5, "goblin").is_empty(), "Throne position is not a build slot")
	_expect(not game.buy_room(0, "missing-room").is_empty(), "Unknown room type is rejected")
	_expect(game.gold == initial_gold, "Rejected purchases do not spend gold")
	_ok(game.buy_room(0, "goblin"), "Buy first of two stocked goblins")
	_ok(game.buy_room(1, "goblin"), "Buy second of two stocked goblins")
	_expect(not game.buy_room(2, "goblin").is_empty(), "Shop prevents buying an unavailable third copy")
	var gold_before_raid: int = game.gold
	_ok(game.start_raid(), "Start raid")
	_expect(not game.buy_room(2, "spikes").is_empty(), "Buying is blocked during raid")
	_expect(not game.sell_room(0).is_empty(), "Selling is blocked during raid")
	_expect(not game.move_room(0, 2).is_empty(), "Moving is blocked during raid")
	_expect(not game.buy_floor().is_empty(), "Expanding is blocked during raid")
	_expect(game.gold == gold_before_raid, "Blocked preparation actions do not spend gold")


func _test_unlimited_floors_and_throne() -> void:
	var game = _game()
	game.gold = 10000
	_ok(game.buy_room(0, "goblin"), "Build room before expansion")
	var original_room: Dictionary = game.rooms[0].duplicate(true)
	for floor_number in range(2, 7):
		var before: int = game.gold
		_ok(game.buy_floor(), "Buy floor %d" % floor_number)
		_expect(game.floor_count == floor_number and game.rooms.size() == floor_number * 5, "Every floor adds five slots, including beyond 15")
		_expect(before - game.gold == 5 * floor_number * floor_number, "Floor price follows design curve")
	_expect(game.rooms[0] == original_room, "Expansion preserves built rooms")
	for slot in range(game.rooms.size()):
		game.rooms[slot] = {}
	_ok(game.start_raid(), "Start empty 30-slot dungeon")
	for _tick in range(50):
		if game.current_slot >= game.rooms.size() or game.phase != "raid":
			break
		game.step()
	_expect(game.current_slot == game.rooms.size(), "Throne follows the last purchased floor")


func _test_healing_and_insufficient_funds() -> void:
	var game = _game()
	var initial_gold: int = game.gold
	_expect(not game.heal_lord().is_empty(), "Healing a full-health lord is rejected")
	_expect(game.gold == initial_gold, "Full-health rejection does not spend gold")
	game.lord["hp"] = 70
	_ok(game.heal_lord(), "Heal injured lord")
	_expect(game.lord["hp"] == 100 and game.gold == initial_gold - 6, "Healing restores 25 percent maximum HP for current wave cost")
	_ok(game.heal_lord(), "Heal near-full lord")
	_expect(game.lord["hp"] == 120, "Healing clamps at maximum HP")
	_ok(game.buy_room(0, "goblin"), "Build before testing insufficient funds")
	game.gold = 0
	game.lord["hp"] = 80
	var rooms_before: Array = game.rooms.duplicate(true)
	_expect(not game.buy_room(1, "goblin").is_empty(), "Purchase checks available gold")
	_expect(not game.upgrade_room(0).is_empty(), "Upgrade checks available gold")
	_expect(not game.buy_floor().is_empty(), "Floor purchase checks available gold")
	_expect(not game.heal_lord().is_empty(), "Healing checks available gold")
	_expect(game.gold == 0 and game.rooms == rooms_before and game.lord["hp"] == 80, "Unaffordable actions leave state unchanged")


func _test_wave_generation() -> void:
	var game = _game()
	for wave_number in [1, 4, 8, 50]:
		game.wave = wave_number
		game._generate_party()
		var expected_count: int = 1 if wave_number < 4 else (2 if wave_number < 8 else 3)
		var expected_level: int = 1 + int((wave_number - 1) / 4)
		_expect(game.heroes.size() == expected_count, "Wave %d has the correct party size" % wave_number)
		var found: Array[String] = []
		for hero in game.heroes:
			_expect(not found.has(hero["id"]), "Wave %d does not duplicate hero archetypes" % wave_number)
			found.append(hero["id"])
			_expect(hero["level"] == expected_level, "Wave %d generates expected hero level" % wave_number)
			_expect(hero["hp"] == hero["max_hp"] and hero["xp"] == 0 and hero["items"].is_empty(), "New heroes have full health, no XP, and no items")
			_expect(hero["poison_ticks"] == 0 and not hero["death_processed"], "New heroes have no stale combat state")
		_expect(found == _ordered_archetypes(found), "Hero order preserves knight protection and priest support")
		if wave_number == 50:
			_expect(game.heroes[0]["max_hp"] > 1000 and game.heroes[0]["damage"] > 100, "Late wave pressure keeps scaling beyond early content")


func _ordered_archetypes(present: Array[String]) -> Array[String]:
	var ordered: Array[String] = []
	for archetype in ["knight", "rogue", "priest"]:
		if present.has(archetype):
			ordered.append(archetype)
	return ordered


func _test_room_isolation_and_movement() -> void:
	var game = _game()
	game.gold = 1000
	_ok(game.buy_room(0, "goblin"), "Buy first identical room")
	_ok(game.buy_room(1, "goblin"), "Buy second identical room")
	_ok(game.upgrade_room(0), "Upgrade one room instance")
	_expect(game.room_stats(0)["rank"] == 2 and game.room_stats(1)["rank"] == 1, "Identical room instances have independent ranks")
	_ok(game.buy_floor(), "Buy destination floor")
	_ok(game.move_room(0, 9), "Move room across floors")
	_expect(game.rooms[0].is_empty() and game.room_stats(9)["rank"] == 2, "Cross-floor move preserves upgraded room")
	_ok(game.move_room(9, 1), "Swap two occupied rooms")
	_expect(game.room_stats(1)["rank"] == 2 and game.room_stats(9)["rank"] == 1, "Swap preserves both independent room states")


func _test_raid_determinism() -> void:
	var first = _game(55107)
	var second = _game(55107)
	_expect(first.shop == second.shop and first.heroes == second.heroes, "Same seed creates the same shop and heroes")
	for game in [first, second]:
		_ok(game.buy_room(0, "spikes"), "Build deterministic front trap")
		_ok(game.buy_room(1, "goblin"), "Build deterministic defender")
		_ok(game.buy_room(2, "goblin"), "Build second deterministic defender")
		_ok(game.start_raid(), "Start deterministic raid")
	var first_steps: int = _finish_raid(first, 1)
	var second_steps: int = _finish_raid(second, 4)
	_expect(first_steps == second_steps, "Batching one versus four ticks preserves simulation length")
	_expect(first.phase == second.phase and first.heroes == second.heroes and first.lord == second.lord, "Batching ticks preserves combat outcome")
	_expect(first.gold == second.gold and first.total_kills == second.total_kills and first.rooms == second.rooms, "Batching ticks preserves rewards and dungeon state")


func _test_defeat_and_rewards() -> void:
	var game = _game()
	game.lord["hp"] = 1
	game.lord["damage"] = 1000000
	_ok(game.start_raid(), "Start mutual-destruction scenario")
	_finish_raid(game)
	_expect(game.phase == "defeat", "Mutual destruction in throne is a defeat")
	_expect(game.lord["hp"] <= 0, "Defeat stores dead lord health")
	var gold_after: int = game.gold
	var kills_after: int = game.total_kills
	for _tick in range(5):
		game.step()
	_expect(game.gold == gold_after and game.total_kills == kills_after, "Terminal simulation steps cannot duplicate death rewards")
	_expect(not game.start_raid().is_empty(), "Defeat cannot start another raid")
	game.restart(7319)
	_expect(game.phase == "prepare" and game.wave == 1 and game.gold == 18 and game.rooms.size() == 5, "Restart resets the run after defeat")


func _test_old_room_sale_and_persistence() -> void:
	var game = _game()
	_ok(game.buy_room(0, "goblin"), "Buy room for an actual raid")
	_ok(game.upgrade_room(0), "Include upgrade cost in room investment")
	game.lord["damage"] = 10000
	game.lord["hp"] = 10000
	game.lord["max_hp"] = 10000
	_ok(game.start_raid(), "Start raid with invested room")
	_finish_raid(game)
	_expect(game.phase == "result", "Surviving lord reaches wave result")
	var gold_after: int = game.gold
	var hp_after: int = game.lord["hp"]
	_ok(game.next_wave(), "Advance after successful defense")
	while game.phase == "level_up":
		_ok(game.choose_upgrade("hp"), "Resolve pending upgrade")
	_expect(game.gold == gold_after and game.lord["hp"] == hp_after, "Preparation preserves gold and injured lord health")
	_expect(game.rooms[0]["rank"] == 2 and game.rooms[0]["used"], "Used room and its rank persist after wave")
	var stock_before: int = game.shop["goblin"]
	_ok(game.sell_room(0), "Sell a used upgraded room")
	_expect(game.gold == gold_after + 4, "Used room refunds half of all nine invested coins, rounded down")
	_expect(game.shop["goblin"] == stock_before, "Used room sale does not replenish shop stock")


func _battle_party(room_id: String = "goblin"):
	var game = _game()
	game.wave = 8
	game._generate_party()
	game.shop[room_id] = 2
	_ok(game.buy_room(0, room_id), "Build controlled combat room")
	_ok(game.start_raid(), "Start controlled party combat")
	game.step()
	game.defender["hp"] = 10000
	game.defender["max_hp"] = 10000
	game.defender["damage"] = 1
	game.defender["armor"] = 0
	for hero in game.heroes:
		hero["armor"] = 0
	return game


func _test_party_targeting_and_healing() -> void:
	var game = _battle_party()
	game.heroes[0]["hp"] = 2
	game.defender["damage"] = 5
	var rogue_hp: int = game.heroes[1]["hp"]
	game.step()
	_expect(game.heroes[0]["hp"] == 0 and game.heroes[1]["hp"] == rogue_hp, "Knight takes first hit; excess damage does not spill to rogue")
	game.step()
	_expect(game.heroes[1]["hp"] == rogue_hp - 5 and game.total_kills == 1, "Next tick retargets rogue after knight death, without duplicate rewards")

	game = _battle_party()
	game.heroes[0]["hp"] = 40
	game.heroes[1]["hp"] = 10
	game.combat_tick = 2
	var incoming: int = int(game.heroes[0]["damage"]) + int(game.heroes[1]["damage"])
	game.step()
	_expect(game.heroes[1]["hp"] == 18, "Third combat tick heals the most wounded living ally by eight HP")
	_expect(game.defender["hp"] == 10000 - incoming, "Healing priest does not also attack on the same tick")

	game = _battle_party()
	for hero in game.heroes:
		hero["max_hp"] = 100
		hero["hp"] = 50
	game.heroes[2]["hp"] = 100
	game.combat_tick = 2
	game.step()
	_expect(game.heroes[0]["hp"] == 57 and game.heroes[1]["hp"] == 50, "Equal health ratios prefer first party member for healing")

	game = _battle_party()
	game.heroes[0]["hp"] = 0
	game._process_deaths()
	game.heroes[1]["hp"] = 10
	game.combat_tick = 2
	game.step()
	_expect(game.heroes[0]["hp"] == 0 and game.heroes[1]["hp"] == 17, "Priest heals living rogue and never resurrects dead knight")


func _test_poison_order_and_traps() -> void:
	var game = _battle_party()
	game.heroes[0]["hp"] = 20
	game.heroes[1]["hp"] = 10
	game.heroes[2]["hp"] = 1
	game.heroes[2]["poison_ticks"] = 1
	game.heroes[2]["poison_damage"] = 2
	game.combat_tick = 2
	var incoming: int = int(game.heroes[0]["damage"]) + int(game.heroes[1]["damage"])
	game.step()
	_expect(game.heroes[2]["hp"] == 0 and game.heroes[2]["death_processed"], "Poison kills priest before third-tick action")
	_expect(game.heroes[1]["hp"] == 10, "Priest killed by poison cannot heal")
	_expect(game.defender["hp"] == 10000 - incoming, "Priest killed by poison cannot attack")

	game = _battle_party("spider")
	var front_hp: int = game.heroes[0]["hp"]
	game.heroes[0]["poison_ticks"] = 1
	game.heroes[0]["poison_damage"] = 2
	game.defender["damage"] = 7
	game.step()
	_expect(game.heroes[0]["hp"] == front_hp - 12, "Spider retains poison synergy on final poison tick")
	game.step()
	_expect(game.heroes[0]["hp"] == front_hp - 19, "Spider loses poison bonus after poison expires")

	game = _game()
	game.wave = 8
	game._generate_party()
	game.shop["poison"] = 2
	_ok(game.buy_room(0, "poison"), "Build poison chamber")
	_ok(game.buy_room(1, "spikes"), "Build follow-up spike trap")
	var starting_hp: Array[int] = []
	for hero in game.heroes:
		starting_hp.append(hero["hp"])
	_ok(game.start_raid(), "Start trap sequence")
	game.step()
	for index in range(3):
		_expect(game.heroes[index]["hp"] == starting_hp[index] - 2 and game.heroes[index]["poison_ticks"] == 5, "Poison chamber applies one status-only tick per hero")
	game.step()
	_expect(game.heroes[0]["hp"] == starting_hp[0] - 20, "Spikes bypass knight armor then advance poison once")
	_expect(game.heroes[1]["hp"] == starting_hp[1] - 4 and game.heroes[2]["hp"] == starting_hp[2] - 4, "Trap status tick damages rear party members without priest healing")
	game.step()
	_expect(game.current_slot == game.rooms.size() and game.combat_tick == 0 and game.heroes[2]["poison_ticks"] == 4, "Empty slots and throne entry do not add combat or poison ticks")


func _test_hero_xp_and_equipment() -> void:
	var game = _game()
	game.wave = 8
	game._generate_party()
	game._award_room_loot({"xp": 8, "item": ""})
	_expect(game.heroes[0]["xp"] == 3 and game.heroes[1]["xp"] == 3 and game.heroes[2]["xp"] == 2, "Eight XP is conserved and divided 3/3/2")
	var base_damage: Array[int] = []
	for hero in game.heroes:
		base_damage.append(hero["damage"])
	game._award_room_loot({"xp": 0, "item": "sword"})
	_expect(game.heroes[1]["items"].has("sword") and not game.heroes[0]["items"].has("sword"), "Sword prioritizes rogue")
	for _copy in range(3):
		game._award_room_loot({"xp": 0, "item": "sword"})
	for index in range(3):
		_expect(game.heroes[index]["items"].size() == 1 and game.heroes[index]["damage"] == base_damage[index] + 3, "Duplicate swords are distributed once and never stack")
	game._award_room_loot({"xp": 0, "item": "shield"})
	_expect(game.heroes[0]["items"].has("shield") and game.heroes[0]["armor"] == 3, "Shield prioritizes knight and adds one armor")
	game.heroes[0]["hp"] = 0
	game._process_deaths()
	_expect(game.heroes[0]["items"].is_empty() and not game.heroes[1]["items"].has("shield"), "Dead hero equipment disappears without transfer")
	game._award_room_loot({"xp": 8, "item": "shield"})
	_expect(game.heroes[0]["xp"] == 3 and game.heroes[1]["xp"] == 7 and game.heroes[2]["xp"] == 6, "Loot XP excludes dead hero and conserves all XP among survivors")
	_expect(game.heroes[1]["items"].has("shield"), "Shield priority skips dead knight")

	game = _game()
	var previous_max: int = game.heroes[0]["max_hp"]
	var previous_damage: int = game.heroes[0]["damage"]
	game.heroes[0]["hp"] = 1
	game._award_room_loot({"xp": 80, "item": ""})
	_expect(game.heroes[0]["level"] == 6 and game.heroes[0]["xp"] == 0, "Large XP rewards resolve multiple levels and subtract every threshold")
	_expect(game.heroes[0]["max_hp"] == previous_max + 50 and game.heroes[0]["damage"] == previous_damage + 10, "Hero levels recalculate health and damage without a cap")
	_expect(game.heroes[0]["hp"] == 76, "Each earned hero level heals exactly fifteen current HP")


func _test_lord_levels_and_rage() -> void:
	var game = _game()
	_ok(game.buy_room(0, "goblin"), "Build room for permanent modifier check")
	game.lord["xp"] = 100
	game.lord["hp"] = 50
	_ok(game.start_raid(), "Start reward-resolution scenario")
	for hero in game.heroes:
		hero["hp"] = 0
	game._process_deaths()
	game.step()
	_expect(game.lord["level"] == 5 and game.pending_upgrades == 4 and game.lord["xp"] == 30, "Lord resolves multiple earned levels after surviving wave")
	_expect(game.lord["hp"] == 90 and game.lord["max_hp"] == 160 and game.lord["damage"] == 14, "Lord level bonuses apply once per earned level")
	_ok(game.next_wave(), "Advance into mandatory upgrade choices")
	_expect(game.phase == "level_up", "Pending level choices block preparation")
	_expect(not game.start_raid().is_empty(), "Cannot start next raid before choosing upgrades")
	for _choice in range(4):
		_ok(game.choose_upgrade("hp"), "Choose repeatable creature health boost")
	_expect(game.phase == "prepare" and game.upgrades["hp"] == 4 and game.room_stats(0)["hp"] == 34, "Repeated health choices add to forty percent and round once")
	_expect(game.lord["max_hp"] == 160, "Creature passive health bonuses do not multiply lord health")

	game = _battle_party()
	game.combat_tick = 40
	game.step()
	_expect(game.rage == 1, "Anti-stall rage starts on combat tick 41")
	game.combat_tick = 50
	game.step()
	_expect(game.rage == 2, "Anti-stall rage increases on combat tick 51")
	game._enter_next_room()
	_expect(game.rage == 0 and game.combat_tick == 0, "Entering next room resets rage and priest tick counter")
	for index in range(100):
		game._log("bounded log %d" % index)
	_expect(game.logs.size() == 70, "Long runs retain only bounded recent battle events")

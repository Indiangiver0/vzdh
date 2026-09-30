extends SceneTree
## Regressions for specialist counters, room branches, floor tradeoffs and elites.

const Game = preload("res://scripts/dungeon_game.gd")

var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_test_floor_choices()
	_test_room_branches()
	_test_specialist_counters()
	_test_defender_targeting()
	_test_elites_and_unlocks()
	_test_branch_combat_effects()
	if failures.is_empty():
		print("PASS: %d v2 rules checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d v2 rules checks failed" % [failures.size(), checks])
		quit(1)


func _game():
	var game = Game.new()
	game.restart(7319)
	game.gold = 10000
	for id in ["goblin", "executioner", "poison", "spider", "spikes", "mimic"]:
		game.shop[id] = 20
	return game


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _ok(error: String, description: String) -> void:
	_expect(error.is_empty(), description + ": " + error)


func _hero(game, id: String) -> Dictionary:
	for hero in game.heroes:
		if str(hero.id) == id:
			return hero
	return {}


func _single_hero(game, id: String) -> Dictionary:
	game.wave = 8
	game._generate_party()
	var hero: Dictionary = _hero(game, id)
	hero.level = 1
	hero.group_factor = 1.0
	hero.pressure = 1.0
	hero.disarm_max = 2 if id == "rogue" else 0
	game._recalculate_hero(hero)
	hero.hp = hero.max_hp
	game.heroes.assign([hero])
	return hero


func _test_floor_choices() -> void:
	for trait_id in ["laboratory", "barracks", "workshop"]:
		var game = _game()
		var incoming_party: Array = game.heroes.duplicate(true)
		_ok(game.buy_floor(), "Purchase specialized floor")
		_expect(game.phase == "floor_choice", "Floor purchase requires a strategic choice")
		_expect(not game.start_raid().is_empty(), "Unresolved floor choice blocks next raid")
		_expect(not game.buy_room(5, "goblin").is_empty(), "Unresolved floor choice blocks construction")
		_expect(not game.choose_floor_trait("invalid").is_empty(), "Unknown floor trait is rejected")
		_ok(game.choose_floor_trait(trait_id), "Choose " + trait_id)
		_expect(game.phase == "prepare" and game.heroes == incoming_party, "Floor choice returns to preparation without rerolling incoming heroes")
		_expect(not game.choose_floor_trait("workshop").is_empty(), "Floor specialization cannot be chosen twice")
		_ok(game.buy_room(0, "executioner"), "Build unmodified comparison defender")
		_ok(game.buy_room(5, "executioner"), "Build specialized-floor defender")
		_ok(game.buy_room(6, "spikes"), "Build specialized-floor trap")
		if trait_id == "laboratory":
			_expect(game.room_stats(5)["hp"] == 40 and game.room_stats(5)["damage"] == 14, "Laboratory weakens creature HP by fifteen percent")
		elif trait_id == "barracks":
			_expect(game.room_stats(5)["hp"] == 58, "Barracks adds twenty-five percent creature HP")
			_expect(game.room_stats(6)["damage"] == 14, "Barracks weakens spike damage by fifteen percent")
		else:
			_expect(game.room_stats(5)["damage"] == 13, "Workshop weakens creature damage by ten percent")
			_expect(game.room_stats(6)["damage"] == 20, "Workshop strengthens trap damage by twenty-five percent")
		_ok(game.move_room(5, 1), "Move defender out of specialized floor")
		_expect(game.room_stats(1)["hp"] == 46 and game.room_stats(1)["damage"] == 14, "Moving room removes previous floor bonuses and penalties")
		_expect(game.room_stats(0)["hp"] == 46 and game.room_stats(0)["damage"] == 14, "Floor specialization leaves other floors unchanged")
		if trait_id == "laboratory":
			_ok(game.buy_room(7, "poison"), "Build laboratory poison room")
			_expect(game.room_stats(7)["poison_ticks"] == 8, "Laboratory extends poison by two ticks")


func _test_room_branches() -> void:
	var game = _game()
	_ok(game.buy_room(0, "executioner"), "Build branching creature room")
	_expect(game.specialization_options(0).is_empty(), "Rank-one room has no specialization choice")
	_expect(not game.specialize_room(0, "fury").is_empty(), "Cannot select branch before rank two")
	_ok(game.upgrade_room(0), "Upgrade to branching rank")
	_expect(game.specialization_options(0).size() == 2, "Rank-two creature offers distinct branch choices")
	_expect(not game.specialize_room(0, "virulent").is_empty(), "Room rejects branch belonging to another room type")
	_ok(game.specialize_room(0, "fury"), "Choose fury branch")
	_expect(game.room_stats(0)["hp"] == 52 and game.room_stats(0)["damage"] == 23, "Fury trades creature HP for damage, rounding once")
	_expect(game.specialization_options(0).is_empty() and not game.specialize_room(0, "bulwark").is_empty(), "Branch choice is permanent for that room instance")
	_ok(game.buy_room(1, "executioner"), "Build independent branch comparison")
	_ok(game.upgrade_room(1), "Upgrade independent room")
	_ok(game.specialize_room(1, "bulwark"), "Choose bulwark branch")
	_expect(game.room_stats(1)["hp"] == 81 and game.room_stats(1)["damage"] == 16, "Bulwark trades creature damage for HP")
	_expect(game.room_stats(0)["damage"] == 23, "Specializing a second room cannot mutate the first room")
	for data in [[2, "spikes", "volley", 9], [3, "spikes", "piercing", 32], [4, "poison", "virulent", 4]]:
		var index: int = int(data[0])
		_ok(game.buy_room(index, str(data[1])), "Build trap with a strategic branch")
		_ok(game.upgrade_room(index), "Upgrade trap to rank two")
		_ok(game.specialize_room(index, str(data[2])), "Choose " + str(data[2]))
		_expect(game.room_stats(index)["damage"] == int(data[3]), "Trap branch changes numerical damage: " + str(data[2]))


func _test_specialist_counters() -> void:
	var game = _game()
	var ranger: Dictionary = _single_hero(game, "rogue")
	for index in range(3):
		_ok(game.buy_room(index, "spikes"), "Build repeated spike counter scenario")
	_ok(game.start_raid(), "Start ranger charge scenario")
	game.step()
	_expect(ranger.hp == 53 and ranger.disarm_charges == 1, "Ranger spends one charge to reduce sixteen trap damage to seven")
	game.step()
	_expect(ranger.hp == 46 and ranger.disarm_charges == 0, "Ranger can weaken a second trap with final charge")
	game.step()
	_expect(ranger.hp == 30, "Exhausted ranger takes full trap damage instead of permanent resistance")
	print("COUNTER ranger traps: first=7 second=7 exhausted=16; prevented 18 damage")

	var taken: Dictionary = {}
	var dealt: Dictionary = {}
	for id in ["knight", "rogue"]:
		game = _game()
		var hero: Dictionary = _single_hero(game, id)
		_ok(game.buy_room(0, "executioner"), "Build creature-counter scenario")
		_ok(game.start_raid(), "Start creature-counter scenario")
		game.step()
		game.step()
		taken[id] = int(hero.max_hp) - int(hero.hp)
		dealt[id] = 46 - int(game.defender.hp)
	_expect(taken.knight == 10 and taken.rogue == 14, "Knight protects himself better against room creatures")
	_expect(dealt.knight == 9 and dealt.rogue == 9, "Knight creature bonus raises attack after armor calculation")
	print("COUNTER executioner: knight taken=%d dealt=%d; ranger taken=%d dealt=%d" % [taken.knight, dealt.knight, taken.rogue, dealt.rogue])

	game = _game()
	var knight: Dictionary = _single_hero(game, "knight")
	_ok(game.start_raid(), "Start lord-specific counter exception")
	game.step()
	game.step()
	_expect(knight.hp == 72 and game.lord.hp == 113, "Knight creature bonuses do not apply in the throne room")

	game = _game()
	game.wave = 8
	game._generate_party()
	_ok(game.buy_room(0, "poison"), "Build party trap-routing scenario")
	_ok(game.buy_room(1, "goblin"), "Build party creature-routing scenario")
	_ok(game.start_raid(), "Start role-based marching order")
	game.step()
	_expect(game.heroes[0].id == "rogue", "Ranger leads the group into a trap")
	for hero in game.heroes:
		_expect(hero.poison_ticks == 2, "Ranger reduces poison duration for each party member")
	game.step()
	_expect(game.heroes[0].id == "knight", "Knight retakes lead before room creature combat")


func _test_defender_targeting() -> void:
	for id in ["mimic", "spider"]:
		var game = _game()
		game.wave = 8
		game._generate_party()
		_ok(game.buy_room(0, id), "Build specialized targeting room")
		_ok(game.start_raid(), "Start specialized targeting scenario")
		game.step()
		game.defender.hp = 10000
		var knight: Dictionary = _hero(game, "knight")
		var ranger: Dictionary = _hero(game, "rogue")
		var priest: Dictionary = _hero(game, "priest")
		var knight_hp: int = int(knight.hp)
		var priest_hp: int = int(priest.hp)
		if id == "spider":
			ranger.hp = 10
		game.step()
		_expect(knight.hp == knight_hp, "Specialized defender can bypass knight protection")
		if id == "mimic":
			_expect(priest.hp == priest_hp - 9, "Mimic attacks priest in the rear")
		else:
			_expect(ranger.hp == 2 and priest.hp == priest_hp, "Spider targets the lowest living health fraction")
			priest.poison_ticks = 2
			priest.poison_damage = 2
			game.step()
			_expect(priest.hp == priest_hp - 12 and ranger.hp == 2, "Spider prioritizes poisoned prey over a weaker unpoisoned ranger")


func _test_elites_and_unlocks() -> void:
	var game = _game()
	for wave_number in [4, 5, 10, 15, 20, 50]:
		game.wave = wave_number
		game._generate_party()
		_expect(game.elite_id.is_empty() == (wave_number % 5 != 0), "Elite frequency remains every fifth wave through wave fifty")
		if wave_number % 5 == 0:
			_expect(not game.wave_title.is_empty() and not game.wave_description.is_empty(), "Elite wave communicates its modifier before raid")
		if wave_number == 5:
			for hero in game.heroes:
				var base_armor: int = 2 if hero.id == "knight" else (1 if hero.id == "priest" else 0)
				_expect(hero.armor == base_armor + 1, "Iron elite grants exactly one extra armor")
		elif wave_number == 10:
			for hero in game.heroes:
				hero.poison_damage = 10
				hero.poison_ticks = 1
			var hp_before: int = game.heroes[0].hp
			game._apply_poison()
			_expect(game.heroes[0].hp == hp_before - 6, "Alchemical elite reduces poison damage with rounding down")
		elif wave_number == 15:
			_expect(_hero(game, "rogue").disarm_max == 6, "Sapper elite adds two charges above wave-scaled ranger supply")

	game = _game()
	game.wave = 5
	game._generate_party()
	var gold_before: int = game.gold
	_ok(game.start_raid(), "Start elite reward scenario")
	for hero in game.heroes:
		hero.hp = 0
	game._process_deaths()
	game.step()
	_expect(game.gold == gold_before + 20, "Elite group grants eight kill coins plus twelve victory coins")
	_expect(game.unlocked_paths.has("ambush") and game.report.unlock == "ambush", "First fifth-wave victory unlocks mimic ambush")
	var paid_gold: int = game.gold
	game.step()
	game._finish_wave()
	_expect(game.gold == paid_gold and game.unlocked_paths.count("ambush") == 1, "Terminal elite processing cannot duplicate reward or unlock")
	game.restart(7319)
	_expect(game.unlocked_paths.has("ambush") and not game.unlocked_paths.has("plague"), "Unlocked room branch persists through restart without unlocking later reward")
	game.gold = 100
	game.shop["mimic"] = 2
	_ok(game.buy_room(0, "mimic"), "Build unlocked specialization carrier")
	_ok(game.upgrade_room(0), "Upgrade carrier to specialization rank")
	_expect(game.specialization_options(0).size() == 3, "Unlocked room offers a third strategic branch")
	_ok(game.specialize_room(0, "ambush"), "Choose unlocked ambush branch")
	game.wave = 10
	game._generate_party()
	_ok(game.start_raid(), "Start tenth-wave trophy scenario")
	for hero in game.heroes:
		hero.hp = 0
	game._process_deaths()
	game.step()
	_expect(game.unlocked_paths.has("plague") and game.report.unlock == "plague", "Tenth-wave victory unlocks plague branch")


func _test_branch_combat_effects() -> void:
	var losses: Dictionary = {}
	for branch in ["volley", "piercing"]:
		var game = _game()
		game.wave = 8
		game._generate_party()
		_ok(game.buy_room(0, "spikes"), "Build trap branch scenario")
		_ok(game.upgrade_room(0), "Upgrade trap branch scenario")
		_ok(game.specialize_room(0, branch), "Specialize actual trap combat")
		_ok(game.start_raid(), "Start actual trap branch combat")
		_hero(game, "rogue").disarm_charges = 0
		game.step()
		var branch_losses: Dictionary = {}
		for hero in game.heroes:
			branch_losses[hero.id] = int(hero.max_hp) - int(hero.hp)
		losses[branch] = branch_losses
	_expect(losses.volley.knight == 9 and losses.volley.rogue == 9 and losses.volley.priest == 9, "Volley damages the whole party in actual combat")
	_expect(losses.piercing.rogue == 32 and losses.piercing.knight == 0 and losses.piercing.priest == 0, "Piercing concentrates actual damage on the front specialist")

	var game = _game()
	game.unlocked_paths.append("plague")
	game.wave = 8
	game._generate_party()
	_ok(game.buy_room(0, "poison"), "Build plague scenario")
	_ok(game.upgrade_room(0), "Upgrade plague room")
	_ok(game.specialize_room(0, "plague"), "Choose permanent plague unlock")
	_ok(game.buy_room(1, "goblin"), "Build room where priest can heal")
	_ok(game.start_raid(), "Start healing counter scenario")
	_hero(game, "rogue").disarm_charges = 0
	game.step()
	game.step()
	game.defender.hp = 10000
	game.defender.damage = 1
	var ranger: Dictionary = _hero(game, "rogue")
	ranger.hp = 10
	game.combat_tick = 2
	game.step()
	_expect(ranger.hp == 11, "Plague halves eight-point priest heal to four after three poison damage")
	_expect(ranger.poison_heal_factor == 0.5, "Plague debuff is represented on affected hero state")

	game = _game()
	_ok(game.buy_floor(), "Buy laboratory for duration synergy")
	_ok(game.choose_floor_trait("laboratory"), "Choose longer poison floor")
	_ok(game.buy_room(5, "poison"), "Build laboratory poison")
	_ok(game.upgrade_room(5), "Upgrade laboratory poison")
	_ok(game.specialize_room(5, "lingering"), "Choose lingering poison")
	_expect(game.room_stats(5).poison_ticks == 11, "Floor and lingering branch combine into eleven poison ticks")

	game = _game()
	var knight: Dictionary = _single_hero(game, "knight")
	knight.hp = 1
	knight.poison_ticks = 3
	knight.poison_heal_factor = 0.5
	game._award_room_loot({"xp": 8, "item": ""})
	_expect(knight.level == 2 and knight.hp == 8, "Plague also halves fifteen-point level-up healing, rounding down")
	knight.hp = 1
	knight.poison_ticks = 0
	game._award_room_loot({"xp": 12, "item": ""})
	_expect(knight.level == 3 and knight.hp == 16, "Expired poison restores full level-up healing")

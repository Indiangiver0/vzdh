extends SceneTree
## Restored feature regression checks. UI persistence stays entirely in memory.

const Game = preload("res://scripts/dungeon_game.gd")
const Progression = preload("res://scripts/lord_progression.gd")
const MainScene = preload("res://scenes/main.tscn")

class TestMain:
	extends "res://scripts/main.gd"
	var saved: Dictionary = {}

	func _read_json(path: String) -> Dictionary:
		return saved.get(path, {}).duplicate(true)

	func _write_json(path: String, data: Dictionary) -> void:
		saved[path] = data.duplicate(true)
		saved[path]["schema_version"] = 1

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func _ok(error: String, description: String) -> void:
	_expect(error.is_empty(), description + ": " + error)

func _combat(archetype: String, room: bool = false):
	var game = Game.new()
	game.restart(7319)
	_ok(game.configure_lord(archetype), "Configure " + archetype)
	if room:
		_ok(game.buy_room(0, "goblin"), "Build combat target")
	game.heroes[0].hp = 1000
	game.heroes[0].max_hp = 1000
	_ok(game.start_raid(), "Start controlled raid")
	game.step()
	return game

func _test_abilities() -> void:
	var knight = _combat("fallen_knight", true)
	_expect(knight.defender.max_hp == 33, "Knight passive adds ten percent creature HP")
	knight.heroes[0].damage = 1
	_ok(knight.cast_ability(), "Knight grants shield")
	_expect(knight.ability_charges == 1 and knight.defender.shield == 10 and knight.defender.ability_attacks == 3, "Shield and three attacks consume one charge")
	_expect(not knight.cast_ability().is_empty() and knight.ability_charges == 1, "Cannot waste a charge stacking an active shield")
	var hp_before: int = knight.defender.hp
	knight.step()
	_expect(knight.defender.hp == hp_before and knight.defender.shield < 10, "Shield absorbs damage before HP")
	_expect(knight.defender.ability_attacks == 2, "Actual attack consumes one enhanced strike")
	_expect(not knight.configure_lord("necromancer").is_empty(), "Cannot change Lord after raid starts")
	for hero in knight.heroes:
		hero.hp = 0
	knight.step()
	_ok(knight.next_wave(), "Advance after shielded victory")
	_expect(knight.ability_charges == 2 and not knight.ability_status().can_cast, "New wave resets charges and preparation blocks casts")

	var necro = _combat("necromancer", true)
	necro.heroes[0].damage = 1000
	_ok(necro.cast_ability(), "Mark defender for revival")
	necro.step()
	_expect(necro.phase == "raid" and necro.defender.hp == 11, "Marked creature returns with rounded thirty-five percent HP")
	_expect(not necro.defender.revive_mark and necro.heroes[0].xp == 0, "Revival consumes mark and grants no creature loot")
	_ok(necro.cast_ability(), "Second charge may mark revived defender")
	necro.step()
	_expect(necro.ability_charges == 0 and necro.defender.hp == 11 and necro.heroes[0].xp == 0, "Second revival is finite and does not duplicate XP")
	necro.step()
	_expect(necro.defender.hp == 0 and necro.heroes[0].xp == necro.hero_room_xp(5), "Unprotected death finally grants one XP reward")

	var throne = _combat("necromancer")
	throne.heroes[0].damage = 1000
	_ok(throne.cast_ability(), "Mark Lord in throne room")
	throne.step()
	_expect(throne.phase == "raid" and throne.lord.hp == 42, "Lord revives before defeat is resolved")

	var alchemist = _combat("plague_alchemist")
	_ok(alchemist.cast_ability(), "Apply group poison")
	_expect(alchemist.heroes[0].hp == 1000 and alchemist.heroes[0].poison_ticks == 8, "First cast applies duration including passive without burst")
	_ok(alchemist.cast_ability(), "Burst existing poison")
	_expect(alchemist.heroes[0].hp == 994 and alchemist.ability_charges == 0, "Second cast bursts only already-poisoned targets")
	_expect(not alchemist.cast_ability().is_empty(), "No casts after charges are spent")
	var finisher = _combat("plague_alchemist")
	finisher.heroes[0].hp = 4
	finisher.heroes[0].poison_ticks = 1
	_ok(finisher.cast_ability(), "Lethal poison burst")
	_expect(finisher.phase == "result" and finisher.total_kills == 1, "Ability kill immediately ends wave and awards once")

func _test_talents_and_route() -> void:
	var game = Game.new()
	game.restart(7319)
	game.phase = "level_up"
	game.lord.level = 4
	game.pending_upgrades = 2
	game._generate_talent_offers()
	var offers: Array = game.talent_offers.duplicate()
	_expect(offers.size() == 3 and offers[0] != offers[1] and offers[1] != offers[2] and offers[0] != offers[2], "Three distinct talents are offered")
	game.talent_options()[0].name = "Changed copy"
	_expect(game.talent_offers == offers and game.talent_options()[0].name != "Changed copy", "Offer reads are stable and independent")
	_expect(not game.choose_talent("unknown").is_empty() and game.pending_upgrades == 2, "Unlisted talent cannot spend a level")
	_ok(game.choose_talent(str(offers[0])), "Choose offered talent")
	_expect(game.pending_upgrades == 1 and game.talent_offers.size() == 3, "Pending level receives another offer")
	_ok(game.choose_talent(game.talent_offers[0]), "Resolve final pending talent")
	_expect(game.phase == "prepare" and game.talent_offers.is_empty(), "Final talent unlocks preparation")
	game.restart(7319)
	_expect(game.selected_talents.is_empty(), "New run clears temporary talents")
	game.gold = 1000
	for _floor in range(2):
		_ok(game.buy_floor(), "Buy floor for snake route")
		_ok(game.choose_floor_trait("laboratory"), "Complete floor choice")
	var expected: Array[int] = [0, 1, 2, 3, 4, 9, 8, 7, 6, 5, 10, 11, 12, 13, 14, 15]
	var position: int = -1
	for slot in expected:
		position = game.next_route_slot(position)
		_expect(position == slot, "Snake visits physical slot %d" % slot)
	_ok(game.buy_room(9, "goblin"), "Build first room on second floor")
	_ok(game.buy_room(5, "goblin"), "Build last room on second floor")
	_ok(game.start_raid(), "Start snake route")
	game.step()
	_expect(game.current_slot == 9, "Empty first floor leads to rightmost second-floor room")
	game._enter_next_room()
	_expect(game.current_slot == 5, "Empty second-floor rooms are skipped right to left")
	game._enter_next_room()
	_expect(game.current_slot == 15, "Empty third floor still leads to final throne")

func _test_profile() -> void:
	var profile: Dictionary = Progression.default_profile()
	_expect(profile.unlocked == ["fallen_knight"] and profile.souls == 0, "Default Lord is free with zero currency")
	var before: Dictionary = profile.duplicate(true)
	_expect(not Progression.purchase(profile, "necromancer").is_empty() and profile == before, "Rejected purchase changes nothing")
	profile.souls = 1000
	_ok(Progression.purchase(profile, "necromancer"), "Unlock necromancer")
	_expect(profile.souls == 960, "Unlock costs forty souls")
	_expect(not Progression.purchase(profile, "necromancer").is_empty() and profile.souls == 960, "Duplicate unlock does not charge")
	_expect(not Progression.select_variant(profile, "necromancer", "revenant").is_empty(), "Variant remains locked before mastery three")
	for _rank in range(4):
		_ok(Progression.upgrade(profile, "necromancer"), "Increase mastery")
	_expect(Progression.mastery(profile, "necromancer") == 5 and profile.souls == 680, "Mastery caps at five with total cost 280")
	_expect(not Progression.upgrade(profile, "necromancer").is_empty() and profile.souls == 680, "Capped mastery does not charge")
	_ok(Progression.select_variant(profile, "necromancer", "revenant"), "Select unlocked variant")
	var normalized: Dictionary = Progression.sanitize({"souls": -7, "unlocked": ["unknown"], "selected": "unknown"})
	_expect(normalized.souls == 0 and normalized.selected == "fallen_knight", "Invalid legacy data normalizes safely")
	_expect(Progression.reward(10, 18, 7).total == 46 and Progression.reward(0, 0, 0).total == 0, "Rewards use prior best and do not reward empty runs")

func _test_ui() -> void:
	root.size = Vector2i(1280, 800)
	var ui = MainScene.instantiate()
	ui.set_script(TestMain)
	root.add_child(ui)
	ui.set_process(false)
	ui.sound_on = false
	ui._begin_run()
	ui._open_lords()
	ui.lords_profile.souls = 200
	ui._purchase_lord("necromancer")
	ui._upgrade_lord("necromancer")
	ui._upgrade_lord("necromancer")
	ui._select_lord_variant("necromancer", "revenant")
	await process_frame
	await process_frame
	_expect(ui.menu_section == "lords" and ui.page.get_combined_minimum_size().x <= root.size.x, "Lord collection fits viewport width")
	_expect(ui.game.lord_archetype == "fallen_knight" and ui.game.lord_mastery == 1, "Menu purchases do not alter current run")
	ui._begin_run()
	_expect(ui.game.lord_archetype == "necromancer" and ui.game.lord_mastery == 3 and ui.game.lord_variant == "revenant", "Next run snapshots purchased Lord configuration")
	_ok(ui.game.start_raid(), "Start UI ability scenario")
	ui.game.step()
	ui.paused = true
	ui._refresh()
	var key = InputEventKey.new()
	key.physical_keycode = KEY_Q
	key.pressed = true
	ui._input(key)
	_expect(ui.paused and ui.game.ability_charges == 1 and ui.game.defender.revive_mark, "Physical Q casts while preserving pause")
	ui._show_talents()
	ui._input(key)
	_expect(ui.game.ability_charges == 1, "Modal blocks ability hotkey")
	ui._close_modal()
	ui.game.cleared_waves = 7
	ui.game.total_kills = 15
	ui.game.lord.hp = 0
	ui.game.step()
	ui._update_record()
	_expect(ui.lords_profile.souls == 114 and ui.last_run_reward.total == 34, "Defeat awards correct souls including first milestone")
	ui._update_record()
	_expect(ui.lords_profile.souls == 114, "Repeated record update cannot duplicate reward")
	_expect(ui.saved["user://profile.json"]["lords"]["souls"] == 114, "Soul balance is persisted through storage interface")
	ui._begin_run()
	_expect(ui.lords_profile.souls == 114, "Restart after defeat cannot duplicate reward")
	ui.queue_free()
	await process_frame
	await process_frame

func _run() -> void:
	_test_abilities()
	_test_talents_and_route()
	_test_profile()
	await _test_ui()
	if failures.is_empty():
		print("PASS: %d progression and route checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d progression checks" % [failures.size(), checks])
		quit(1)

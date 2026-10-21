extends SceneTree
## Lord ability regression against the current encounter engine; no player saves.
const Game = preload("res://scripts/dungeon_game.gd")
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
	_expect(necro.rooms[0].status == "cleared" and necro.heroes[0].xp == necro.hero_room_xp(5), "Unprotected death finally grants one XP reward")

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


func _run() -> void:
	_test_abilities()
	print("LORD ABILITIES: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

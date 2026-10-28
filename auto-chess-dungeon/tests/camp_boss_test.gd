extends SceneTree
## 2.1.1 model regressions. In-memory fixtures; no profile reads/writes.
## Run in an isolated project: --headless --script res://tests/camp_boss_test.gd
## Explicit HP/status fixtures test arithmetic; route tests use actual model actions.
const Game = preload("res://scripts/dungeon_game.gd")
const Hero = preload("res://scripts/hero_rules.gd")
const Content = preload("res://scripts/content_catalog.gd")
const SEED: int = 20261027
const MAX_STEPS: int = 1200
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	print("CAMP_BOSS_BEGIN seed=%d max_steps=%d user_dir=%s" % [SEED, MAX_STEPS, OS.get_user_data_dir()])
	_test_bosses()
	_test_rewards()
	_test_routes()
	_test_complete_raids()
	_test_durations_and_rounding()
	_test_poison()
	_test_frozen_combat()
	_test_interruptions()
	_test_terminal_boundaries()
	if failures.is_empty():
		print("PASS: %d camp/boss checks; seed=%d" % [checks, SEED])
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d camp/boss checks; seed=%d" % [failures.size(), checks, SEED])
		quit(1)

func _expect(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("CHECK_FAIL: " + label)

func _equal(actual: Variant, expected: Variant, label: String) -> void:
	_expect(actual == expected, "%s expected=%s actual=%s" % [label, str(expected), str(actual)])

func _ok(result: String, label: String) -> void:
	_expect(result.is_empty(), label + ": " + result)

func _game(wave_number: int = 25):
	var g = Game.new(false)
	g.restart(SEED)
	_ok(g.configure_lord("fallen_knight"), "fixture configure lord")
	g.wave = wave_number
	g._generate_party()
	return g

func _party_without_hp(g) -> Array:
	var result: Array = g.heroes.duplicate(true)
	for h in result:
		h.erase("hp")
	return result

func _camp(maximum: int = 200, health: int = 1, skills: Dictionary = {}):
	var g = _game()
	g.learned_skills = skills.duplicate(true)
	_ok(g.start_raid(), "fixture start raid")
	var h: Dictionary = g.heroes[0]
	g.heroes.assign([h])
	h.max_hp = maximum
	h.hp = health
	g._start_camp(0)
	return g

func _test_bosses() -> void:
	for w in [1, 5, 24, 25, 26, 49, 50, 51, 74, 75, 99, 100, 101, 125, 250]:
		var g = _game(w)
		var boss: bool = w % 25 == 0
		_equal(g.wave_is_boss, boss, "boss cadence wave %d" % w)
		if not boss:
			_expect(g.heroes.size() <= 3, "ordinary party size wave %d" % w)
			continue
		_equal(g.heroes.size(), 5, "five heroes wave %d" % w)
		_equal(g.boss_id, "oath_of_the_five", "stable boss ID")
		_equal(g.elite_id, "boss", "boss replaces ordinary elite")
		var ids: Array[String] = []
		for h in g.heroes:
			_expect(not ids.has(str(h.id)), "unique boss class " + str(h.id))
			ids.append(str(h.id))
			_equal(h.group_hp_factor, 0.75, "stored HP factor")
			_equal(h.group_damage_factor, 0.75, "stored damage factor")
			_equal(h.poison_resistance, 1.0, "no alchemy elite overlay")
			_equal(h.elite_armor, 0, "no armor elite overlay")
			_expect(bool(h.soul_special), "boss hero has special soul distribution")
			var base: Dictionary = Content.hero(str(h.id))
			var equipment: Dictionary = Hero.equipment_stats(h)
			var expected_hp: int = ceili(float(base.hp) * pow(1.0 + 0.02469507659595993 * (w - 1), 2.0) * 0.75) + int(equipment.hp)
			var expected_damage: int = ceili(float(base.damage) * pow(1.0 + 0.014889156509221957 * (w - 1), 2.0) * 0.75) + int(equipment.damage)
			_equal(h.max_hp, expected_hp, "single HP factor wave=%d class=%s" % [w, h.id])
			_equal(h.damage, expected_damage, "single damage factor wave=%d class=%s" % [w, h.id])
		_equal(ids, ["knight", "rogue", "priest", "mage", "bard"], "approved boss composition")
		var survivor: Dictionary = g.heroes[1]
		var before: Vector2i = Vector2i(survivor.max_hp, survivor.damage)
		g.heroes[0].hp = 0
		g._recalculate_hero(survivor)
		_equal(Vector2i(survivor.max_hp, survivor.damage), before, "death does not rescale surviving party")
		var same = _game(w)
		_equal(g.heroes[2], same.heroes[2], "seeded party/equipment determinism")
	var growth = _game(100)
	var growing: Dictionary = growth.heroes[0]
	growing.level = int(growing.starting_level) + 1
	growth._recalculate_hero(growing)
	var base: Dictionary = Content.hero("knight")
	var equipment: Dictionary = Hero.equipment_stats(growing)
	_equal(growing.max_hp, ceili((float(base.hp) * pow(1.0 + 0.02469507659595993 * 99, 2.0) + 10.0) * 0.75) + int(equipment.hp), "earned level preserves 75 percent HP factor")
	_equal(growing.damage, ceili((float(base.damage) * pow(1.0 + 0.014889156509221957 * 99, 2.0) + 2.0) * 0.75) + int(equipment.damage), "earned level preserves 75 percent damage factor")

func _test_rewards() -> void:
	for w in [25, 50, 100]:
		var g = _game(w)
		_ok(g.start_raid(), "reward fixture raid")
		var wallet: int = g.gold
		for h in g.heroes:
			h.hp = 0
		g._reward_dead_heroes()
		var killed_wallet: int = g.gold
		var soul_state: int = g.soul_rng.state
		g._reward_dead_heroes()
		_equal(g.gold, killed_wallet, "hero payouts once")
		_equal(g.soul_rng.state, soul_state, "soul roll once per hero")
		g.step()
		_equal(g.phase, "result", "all dead finishes boss wave")
		_equal(g.gold - wallet, 5 * (3 + floori(float(w - 1) / 3.0)) + 4 + 8, "five ordinary payouts plus existing 8 only")
		_equal(g.total_kills, 5, "five kills")
		_equal(g.cleared_waves, 1, "one cleared wave")
		wallet = g.gold
		var souls: int = g.run_souls
		g.step()
		g._finish_wave()
		g.advance_camp(100.0)
		_equal(g.gold, wallet, "repeated finish cannot pay twice")
		_equal(g.run_souls, souls, "no repeat souls at finish")

func _route(w: int, occupied_floors: Array):
	var g = _game(w)
	g.gold = 10000
	for _floor in range(2):
		_ok(g.buy_floor(), "route buy floor")
		_ok(g.choose_floor_trait("workshop"), "route choose floor trait")
	g.shop.spikes = 5
	for f in occupied_floors:
		_ok(g.buy_room(int(f) * 5 + 2, "spikes"), "route build trap")
	_ok(g.start_raid(), "route start raid")
	for h in g.heroes:
		h.max_hp = 1000
		h.hp = 100
	return g

func _test_routes() -> void:
	for w in [8, 25]:
		for occupied in [[0, 1, 2], [0, 2], [1], []]:
			var g = _route(w, occupied)
			var seen: Array[int] = []
			var steps: int = 0
			while g.phase in ["raid", "camp"] and g.current_slot < g.rooms.size() and steps < MAX_STEPS:
				if g.phase == "camp":
					var status: Dictionary = g.camp_status()
					var floor_id: int = status.floor_index
					_expect(not seen.has(floor_id), "at most one camp per floor")
					seen.append(floor_id)
					_equal(status.slot, [4, 5, 14][floor_id], "snake route camp exit")
					g.advance_camp(10.0)
				else:
					g.step()
				steps += 1
			_expect(steps < MAX_STEPS, "bounded route")
			_equal(seen, occupied, "all and only nonempty floors wave=%d floors=%s" % [w, str(occupied)])
			_equal(g.current_slot, 15, "throne follows last camp")
			_expect(not g._try_start_route_camp(), "no camp at or beyond throne")
	# Gate checks use the real route entrance, independently of arithmetic fixtures.
	for scenario in ["full", "dead", "lord_dead", "finished"]:
		var g = _route(25, [0])
		g.current_slot = 4
		g._waiting_for_entry = true
		if scenario == "full":
			for h in g.heroes:
				h.hp = h.max_hp
		elif scenario == "dead":
			for h in g.heroes:
				h.hp = 0
		elif scenario == "lord_dead":
			g.lord.hp = 0
		else:
			g.phase = "result"
		_expect(not g._try_start_route_camp(), "camp gate " + scenario)
		_expect(not bool(g.camp_status().active), "camp inactive " + scenario)

func _test_durations_and_rounding() -> void:
	for tier in range(4):
		var skills: Dictionary = {}
		for t in range(1, tier + 1):
			skills["shared_restless_dungeons_%d" % t] = true
		var g = _camp(200, 1, skills)
		var duration: int = [10, 8, 6, 5][tier]
		_equal(g.camp_status().duration, duration, "replacement duration tier %d" % tier)
		g.advance_camp(0.75)
		_equal(g.heroes[0].hp, 1, "first pulse waits a whole second")
		g.advance_camp(0.25)
		_equal(g.heroes[0].hp, 11, "one pulse remains 5 percent")
		g.advance_camp(100.0)
		_equal(g.heroes[0].hp, 1 + 10 * duration, "duration controls total healing")
		_equal(g.phase, "raid", "camp completes")
	var fractional = _camp(11, 1)
	fractional.advance_camp(1.0)
	_equal(fractional.heroes[0].hp, 1, "no forced minimum one")
	fractional.advance_camp(1.0)
	_equal(fractional.heroes[0].hp, 2, "fraction accumulates")
	fractional.advance_camp(8.0)
	_equal(fractional.heroes[0].hp, 6, "floor final 5.5 HP")
	var reset = _camp(11, 1)
	reset.advance_camp(1.0)
	_ok(reset.interrupt_camp(), "end fractional camp")
	reset._start_camp(0)
	reset.advance_camp(1.0)
	_equal(reset.heroes[0].hp, 1, "fraction does not cross camps")
	var separate = _camp(11, 1)
	var second: Dictionary = separate.heroes[0].duplicate(true)
	second.instance_id = "other"
	second.max_hp = 13
	separate.heroes.append(second)
	separate.advance_camp(1.0)
	_equal([separate.heroes[0].hp, second.hp], [1, 1], "no shared hero fraction")
	separate.advance_camp(2.0)
	_equal([separate.heroes[0].hp, second.hp], [2, 2], "independent accumulated fractions")
	separate.advance_camp(7.0)
	_equal([separate.heroes[0].hp, second.hp], [6, 7], "separate final fractions")
	var capped = _camp(101, 100)
	capped.advance_camp(1.0)
	_equal(capped.heroes[0].hp, 101, "healing never exceeds max HP")
	_equal(capped.phase, "raid", "healthy party leaves early")
	var exact = _camp(40, 1)
	exact.advance_camp(10.0)
	_equal(exact.heroes[0].hp, 21, "integer boundary no lost HP")
	for delta in [0.0, -1.0, INF, -INF, NAN]:
		var invalid = _camp()
		var before: Dictionary = invalid.camp_status()
		invalid.advance_camp(delta)
		_equal(invalid.camp_status(), before, "invalid delta ignored")
	var one = _camp(137, 1)
	var many = _camp(137, 1)
	one.advance_camp(10.0)
	for _n in range(40):
		many.advance_camp(0.25)
	_equal(one.heroes, many.heroes, "time batching deterministic HP")
	_equal(one.phase, many.phase, "time batching deterministic phase")

func _test_poison() -> void:
	# [priest current level, priest alive, vapors, stronger factor, expected heal]
	for row in [[0, false, false, 1.0, 50], [0, false, true, 1.0, 50], [4, true, false, 1.0, 90], [4, true, true, 1.0, 90], [5, true, false, 1.0, 95], [5, true, true, 1.0, 90], [5, false, false, 1.0, 50], [5, true, false, 0.5, 50], [5, true, true, 0.2, 20], [5, true, false, 0.0, 0]]:
		var g = _camp()
		var target: Dictionary = g.heroes[0]
		target.poison_ticks = 7
		target.poison_damage = 40.0
		target.poison_heal_factor = row[3]
		g.learned_skills.poison_caustic_vapors = row[2]
		if int(row[0]) > 0:
			var priest: Dictionary = target.duplicate(true)
			priest.id = "priest"
			priest.instance_id = "priest_fixture"
			priest.level = row[0]
			priest.hp = 200 if bool(row[1]) else 0
			g.heroes.append(priest)
		var status: Dictionary = g.camp_status()
		_equal(status.remaining_healing, row[4], "poison forecast " + str(row))
		g.advance_camp(10.0)
		_equal(target.hp, 1 + int(row[4]), "poison actual " + str(row))
		_equal(target.poison_ticks, 7, "poison duration frozen")
		_equal(target.poison_damage, 40.0, "poison damage frozen")
	var healthy = _camp()
	healthy.learned_skills.poison_caustic_vapors = true
	healthy.advance_camp(10.0)
	_equal(healthy.heroes[0].hp, 101, "nonpoisoned hero unaffected by vapors")
	var odd = _camp(101, 1)
	odd.heroes[0].poison_ticks = 1
	odd.advance_camp(10.0)
	_equal(odd.heroes[0].hp, 26, "poison fractional total floors 25.25")
	var partial = _camp(11, 1)
	partial.heroes[0].poison_ticks = 3
	partial.advance_camp(3.0)
	_equal(partial.camp_status().remaining_healing, 2, "forecast includes accumulated fraction")
	partial.advance_camp(7.0)
	_equal(partial.heroes[0].hp, 3, "forecast equals remaining actual heal")

func _frozen(g) -> Dictionary:
	return {"party": _party_without_hp(g), "lord": g.lord.duplicate(true), "defender": g.defender.duplicate(true), "actors": g._encounter.actors.duplicate(true), "effects": g._encounter.effects.duplicate(true), "pending": g._encounter.pending.duplicate(true), "runtime": g.run_skill_runtime.duplicate(true), "tick": g.tick, "combat_tick": g.combat_tick, "rage": g.rage, "gold": g.gold, "q": g.ability_charges, "qprice": g.ability_gold_cost(), "souls": g.run_souls, "rng": g.rng.state, "soul_rng": g.soul_rng.state, "report": g.report.duplicate(true)}

func _test_frozen_combat() -> void:
	var g = _game()
	g.gold = 100
	g.shop.mimic = 1
	_ok(g.buy_room(0, "mimic"), "freeze fixture mimic")
	g.learned_skills.poison_bitter_medicine = true
	_ok(g.start_raid(), "freeze fixture raid")
	for h in g.heroes:
		h.max_hp = 200
		h.hp = 1
		h.poison_ticks = 6
		h.poison_damage = 19.0
		h.silence_ticks = 4
		h.cocoon_ticks = 2
		h.equipment_state = {"spell_clock": 2, "stored_spell": true, "memory_used": false}
		h.effects = {"duel_ticks": 3}
		h.cursed_cup = {"uses": 2, "used_this_battle": false, "source": "fixture", "heal_fraction": 0.1}
	var mimic: Dictionary = g._encounter.make_actor(g, 0, g.room_stats(0))
	mimic.hp = 1
	mimic.charges = {"decoys": 1}
	mimic.effects = {"duel_ticks": 3}
	g._encounter.actors.assign([mimic])
	g.defender = mimic
	g.tick = 7
	g.combat_tick = 3
	g.rage = 2
	g._encounter.effects = {"mass": {"fraction": 0.5}, "fog": {"charges": 2}, "partitions": {"ticks": 4}}
	g._encounter.pending.assign([{"kind": "mass", "fraction": 0.5}])
	g.run_skill_runtime = {"q_casts": 1}
	g._start_camp(0)
	var before: Dictionary = _frozen(g)
	var initial: Dictionary = g.camp_status()
	for _n in range(20):
		g.camp_status()
	_equal(g.camp_status(), initial, "status reads are pure")
	for _n in range(5):
		g.step()
	_equal(g.camp_status(), initial, "combat step does not advance camp")
	_expect(not g.cast_ability().is_empty(), "Q rejected during camp")
	g.advance_camp(5.0)
	_equal(_frozen(g), before, "combat state RNG rewards resources frozen during camp")
	for h in g.heroes:
		_equal(h.hp, 48, "developed priest camp aura survives control; no bitter medicine or cup reaction")
	for event in g.combat_events:
		_equal(event.kind, "camp_heal", "camp emits only camp healing events")
	g.advance_camp(5.0)
	_equal(_frozen(g), before, "camp completion preserves combat states")
	_equal(g.phase, "raid", "combat resumes after camp")

func _test_interruptions() -> void:
	var g = _camp()
	g.gold = 1000
	var income: int = g.base_wave_income()
	var first: int = ceili(float(income) / 4.0)
	var later: int = ceili(float(income) / 2.0)
	var charges: int = g.ability_charges
	var qprice: int = g.ability_gold_cost()
	g.advance_camp(2.0)
	_equal(g.heroes[0].hp, 21, "healing before E")
	for use in range(4):
		if use > 0:
			g._start_camp(0)
		var expected: int = first if use == 0 else later
		_equal(g.camp_interrupt_cost(), expected, "E first25 later50 without escalation")
		var wallet: int = g.gold
		_ok(g.interrupt_camp(), "successful E")
		_equal(wallet - g.gold, expected, "E charges once")
		_equal(g.camp_status().successful_interruptions, use + 1, "count successful E only")
		_equal(g.heroes[0].hp, 21, "E keeps already healed HP")
		_expect(not g.interrupt_camp().is_empty(), "duplicate E refused")
		_equal(wallet - g.gold, expected, "duplicate E free")
		g.advance_camp(10.0)
		_equal(g.heroes[0].hp, 21, "cancelled healing never arrives")
		_equal(g.ability_charges, charges, "E does not consume/refill Q")
		_equal(g.ability_gold_cost(), qprice, "E does not change Q price")
	for refusal in ["outside", "poor", "full", "dead", "zero_heal", "lord_dead"]:
		var r = _camp()
		r.gold = 100
		if refusal == "outside":
			r._end_camp("fixture")
		elif refusal == "poor":
			r.gold = r.camp_interrupt_cost() - 1
		elif refusal == "full":
			r.heroes[0].hp = r.heroes[0].max_hp
		elif refusal == "dead":
			r.heroes[0].hp = 0
		elif refusal == "zero_heal":
			r.heroes[0].max_hp = 2
			r.heroes[0].hp = 1
			r.heroes[0].poison_ticks = 1
		else:
			r.lord.hp = 0
		var wallet: int = r.gold
		_expect(not r.interrupt_camp().is_empty(), "E refusal " + refusal)
		_equal(r.gold, wallet, "refusal no spending " + refusal)
		_equal(r.camp_status().successful_interruptions, 0, "refusal no counter " + refusal)
	var discounted = _game()
	discounted.learned_skills = {"ritual_economy_1": true, "ritual_economy_2": true, "ritual_economy_3": true, "economy_tribute_1": true}
	_ok(discounted.start_raid(), "discount snapshot raid")
	var frozen_income: int = discounted.base_wave_income()
	_equal(frozen_income, 59, "boss income excludes elite8 and skill bonuses")
	_equal(discounted.ability_gold_cost(), 26, "existing Q discounts retained")
	_equal(discounted.camp_interrupt_cost(), 15, "E ceil ignores Q discounts")
	discounted.heroes[0].hp = 0
	discounted._reward_dead_heroes()
	discounted.gold += 99
	discounted.heroes.pop_front()
	_equal(discounted.base_wave_income(), frozen_income, "income snapshot stable after rewards/sale fixture and party changes")
	_equal(discounted.camp_interrupt_cost(), 15, "E price snapshot stable")
	for base in [1, 2, 3, 4, 5, 20, 21, 59]:
		var price = _camp()
		price._ability_income_snapshot = base
		_equal(price.camp_interrupt_cost(), maxi(1, ceili(float(base) / 4.0)), "ceil/min first base=%d" % base)
		price._camp_interruptions = 1
		_equal(price.camp_interrupt_cost(), maxi(1, ceili(float(base) / 2.0)), "ceil/min later base=%d" % base)
	var reset = _camp()
	reset.gold = 100
	_ok(reset.interrupt_camp(), "reset fixture E")
	for h in reset.heroes:
		h.hp = 0
	reset._reward_dead_heroes()
	reset.step()
	_ok(reset.next_wave(), "advance next wave")
	_equal(reset.camp_status().successful_interruptions, 0, "next wave resets E count")
	_equal(reset.camp_interrupt_cost(), ceili(float(reset.base_wave_income()) / 4.0), "next wave first E cheap again")

func _test_terminal_boundaries() -> void:
	var dead = _camp()
	dead.heroes[0].hp = 0
	dead.advance_camp(1.0)
	_equal(dead.phase, "result", "no living heroes ends active camp")
	_equal(dead.heroes[0].hp, 0, "camp cannot resurrect")
	var lord_dead = _camp()
	lord_dead.lord.hp = 0
	lord_dead.advance_camp(1.0)
	_equal(lord_dead.phase, "defeat", "dead lord ends camp")
	_equal(lord_dead.heroes[0].hp, 1, "no healing after defeat")
	var healthy = _camp()
	healthy.heroes[0].hp = healthy.heroes[0].max_hp
	healthy.advance_camp(1.0)
	_equal(healthy.phase, "raid", "externally healthy party leaves camp")
	var dead_member = _camp()
	var corpse: Dictionary = dead_member.heroes[0].duplicate(true)
	corpse.instance_id = "corpse"
	corpse.hp = 0
	dead_member.heroes.append(corpse)
	dead_member.advance_camp(10.0)
	_equal(corpse.hp, 0, "dead party member receives no healing")
	_equal(dead_member.heroes[0].hp, 101, "living ally receives full healing")


func _test_complete_raids() -> void:
	for w in [8, 25]:
		var outcomes: Array = []
		for time_slice in [1.0, 0.25]:
			var g = _game(w)
			g.gold = 10000
			_ok(g.buy_floor(), "complete raid second floor")
			_ok(g.choose_floor_trait("workshop"), "complete raid floor choice")
			g.shop.goblin = 1
			g.shop.poison = 1
			_ok(g.buy_room(0, "goblin"), "complete raid creature floor")
			_ok(g.buy_room(8, "poison"), "complete raid poison floor")
			_ok(g.start_raid(), "complete raid start")
			g.lord.hp = 1000000
			g.lord.max_hp = 1000000
			g.lord.damage = 10000
			g.lord.tree_base_damage = 10000.0
			for h in g.heroes:
				h.hp = 100
				h.max_hp = 1000
				h.damage = 1000
			var steps: int = 0
			var camps: Array[int] = []
			while g.phase in ["raid", "camp"] and steps < MAX_STEPS:
				if g.phase == "camp":
					var floor_id: int = g.camp_status().floor_index
					if not camps.has(floor_id):
						camps.append(floor_id)
					g.advance_camp(time_slice)
				else:
					g.step()
				steps += 1
			_expect(steps < MAX_STEPS, "bounded complete raid wave=%d" % w)
			_equal(g.phase, "result", "complete raid reaches result")
			_equal(camps, [0, 1], "creature and poison floors each camp before throne")
			_equal(g.total_kills, 5 if w == 25 else 3, "complete raid counts all heroes once")
			_expect(not bool(g.camp_status().active), "no camp after final throne battle")
			outcomes.append({"heroes": g.heroes.duplicate(true), "lord_hp": g.lord.hp, "gold": g.gold, "souls": g.run_souls, "report": g.report.duplicate(true)})
		_equal(outcomes[0], outcomes[1], "complete raid deterministic across camp time batches")

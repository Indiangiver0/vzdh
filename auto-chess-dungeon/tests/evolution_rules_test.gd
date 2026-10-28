extends SceneTree
## Behavioral regression cases for approved mutations. All state is in memory.
const Game = preload("res://scripts/dungeon_game.gd")
const Catalog = preload("res://scripts/room_evolution_catalog.gd")
const Heroes = preload("res://scripts/hero_rules.gd")
const Damage = preload("res://scripts/damage_rules.gd")
const SEED: int = 20261021
var checks: int = 0
var failures: Array[String] = []
var context: String = ""

func _initialize() -> void:
	_run.call_deferred()

func _expect(ok: bool, text: String) -> void:
	checks += 1
	if not ok:
		failures.append(context + " | " + text)

func _game():
	var g = Game.new(false)
	g.restart(SEED)
	g.gold = 1000000
	g.selected_blueprints.assign(g.Content.room_ids())
	for id in g.Content.room_ids():
		g.shop[id] = 20
	g.lord.hp = 10000
	g.lord.max_hp = 10000
	g.lord.damage = 40
	return g

func _hero(g, id: String, hp: int = 2000, damage: int = 10, armor: int = 0) -> Dictionary:
	var d: Dictionary = g.Content.hero(id)
	var h: Dictionary = {
		"id": id, "instance_id": "fixture_" + id, "name": d.name,
		"level": 1, "starting_level": 1, "wave": 1, "xp": 0,
		"hp": hp, "max_hp": hp, "damage": damage, "armor": armor,
		"group_factor": 1.0, "pressure": 1.0, "items": [],
		"equipment": Heroes.initial_equipment(id, 1, g.rng), "equipment_state": {},
		"equipment_disabled_slots": [], "effects": {}, "death_processed": false,
		"poison_ticks": 0, "poison_damage": 0, "poison_heal_factor": 1.0,
		"poison_resistance": 1.0, "disarm_max": 4 if id == "rogue" else 0,
		"disarm_charges": 4 if id == "rogue" else 0,
		"icon": d.icon, "color": d.color, "trait": d.trait,
	}
	g._clear_hero_control(h)
	return h

func _party(g, roles: Array = ["knight", "barbarian", "priest"]) -> void:
	g.heroes.clear()
	for id in roles:
		g.heroes.append(_hero(g, str(id)))

func _room(g, slot: int, id: String, path: String = "", stage: int = 2) -> void:
	_expect(g.buy_room(slot, id).is_empty(), "fixture builds " + id)
	if path.is_empty():
		return
	g.rooms[slot].rank = stage
	for threshold in [2, 5, 15]:
		if threshold > stage:
			break
		var choice: String = path if threshold == 2 else "%s:%d" % [path, threshold]
		_expect(g.choose_room_evolution(slot, choice).is_empty(), "public path selection " + choice)

func _start(g) -> void:
	_expect(g.start_raid().is_empty(), "fixture starts raid")
	g.step()

func _normalize_actor(g) -> Dictionary:
	var a: Dictionary = g.defender
	a.hp = 1000
	a.max_hp = 1000
	a.tree_base_hp = 1000.0
	a.tree_hp_bonus = 0.0
	a.damage = 20
	a.tree_base_damage = 20.0
	a.tree_damage_bonus = 0.0
	a.armor = 0
	return a

func _advance(g, count: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for _i in range(count):
		# count describes combat steps; the separate camp clock pauses those steps.
		if g.phase == "camp":
			g.advance_camp(float(g.camp_status().remaining_seconds))
			events.append_array(g.combat_events.duplicate(true))
		if g.phase != "raid":
			break
		g.step()
		events.append_array(g.combat_events.duplicate(true))
	return events

func _seen(events: Array, kind: String) -> bool:
	for e in events:
		if str(e.kind) == kind:
			return true
	return false

func _pending(g, kind: String) -> bool:
	for p in g._encounter.pending:
		if str(p.kind) == kind:
			return true
	return false

func _kill(g, actor: Dictionary) -> void:
	actor.hp = 0
	g._encounter.resolve_actor_deaths(g)
	g._encounter.finish_owners(g)

func _catalog_and_finite() -> void:
	context = "catalog"
	_expect(Catalog.path_ids().size() == 49, "48 approved primary paths plus approved cursed cup")
	for rejected in ["war_hound_cerberus", "war_hound_pack", "mimic_abductor", "mimic_armory", "wraith_mirror", "wraith_memory_keeper", "spikes_double_floor"]:
		_expect(Catalog.path(rejected).is_empty(), "rejected path absent: " + rejected)
	for id in Game.Content.room_ids():
		_expect(Catalog.paths(id).size() == (4 if id == "mimic" else 3), "approved path count for " + id)
	for path in Catalog.path_ids():
		for stage in [2, 5, 15]:
			context = "%s rank%d finite" % [path, stage]
			var entry: Dictionary = Catalog.stage(path, stage)
			_expect(int(entry.tier) == stage and str(entry.path_id) == path, "catalog stage and stable path ID")
			var g = _game()
			_room(g, 0, str(entry.room_id), path, stage)
			_party(g, ["knight", "mage", "priest"])
			_start(g)
			var steps: int = 0
			while g.phase in ["raid", "camp"] and steps < 600:
				if g.phase == "camp":
					g.advance_camp(0.5)
				else:
					g.step()
				steps += 1
			_expect(g.phase in ["result", "defeat"], "finite real encounter and throne result")
			_expect(g.combat_events.size() <= 128, "event lifetime bounded")

func _path_effect(path: String, stage: int) -> void:
	context = "%s rank%d effect" % [path, stage]
	var entry: Dictionary = Catalog.stage(path, stage)
	var g = _game()
	var slot: int = 1 if path == "blade_floor_corpse_reclaimer" else 0
	if slot == 1:
		_room(g, 0, "goblin")
	_room(g, slot, str(entry.room_id), path, stage)
	if path == "mimic_living_chamber":
		pass
	elif path == "ballista_clear_sight":
		g.rooms[2] = g.rooms[0]
		g.rooms[0] = {}
		_room(g, 0, "guardian")
	else:
		_room(g, slot + 1, "guardian")
		if path == "shackles_garrison_gallery":
			_room(g, slot + 2, "executioner")
	_party(g, ["knight", "rogue", "priest"] if path == "war_hound_sapper_hunter" else ["knight", "barbarian", "priest"])
	if path == "pickpockets":
		Heroes.equip_item(g.heroes[0], "sword", true)
	if path == "poison_distiller":
		g.heroes[0].poison_ticks = 8
		g.heroes[0].poison_damage = 4
	if path == "shackles_prisoner_scales":
		g.heroes[2].hp = 500
	if path in ["rust_fracture_window", "rust_shard_chamber", "rust_reforging", "spikes_armour_press"]:
		g.heroes[0].armor = 7
	if path == "spikes_blood_surge":
		g.heroes[0].hp = 1
	if path == "ballista_reserve_magazine":
		g.rooms[slot].evolution_memory = {"ammo": 2}
	if path == "silence_null_bell":
		g.heroes[0].poison_ticks = 8
		g.heroes[0].poison_damage = 1
	_start(g)
	var a: Dictionary = {}
	if str(entry.room_id) in ["spider", "goblin", "executioner", "guardian", "ogre", "war_hound", "mimic", "wraith", "vampire"] and path != "wraith_throne_guardian":
		a = _normalize_actor(g)
	match path:
		"venom_hunter":
			_advance(g, 1)
			_expect(int(g.heroes[0].poison_ticks) > 0, "venom bite applies actual poison")
		"cocoon_weaver":
			var ev: Array = _advance(g, 5)
			_expect(int(g.heroes[0].effects.get("web_ticks", 0)) > 0 if stage == 2 else _seen(ev, "cocoon"), "web or cocoon actually applied")
		"brood_mother":
			_kill(g, a)
			_expect(g._encounter.living_actors().size() >= 1 and not bool(g._encounter.owners[0].rewarded), "offspring fight before room reward")
		"war_banner":
			_advance(g, 1)
			var states: Dictionary = g.run_skill_runtime.get("combat_rooms", {})
			var mark: Dictionary = states.get(g._battle_source(1), {}).get("incoming_banner", {})
			_expect(str(mark.get("target", "")) == str(g.heroes[0].instance_id) and int(mark.get("source_slot", -1)) == 0, "banner marks next defender's target")
			_kill(g, a)
			g._waiting_for_entry = true
			g.step()
			_expect(g.current_slot == 1 and not g.defender.is_empty(), "party reaches banner's adjacent recipient")
			if not g.defender.is_empty():
				var directed: Dictionary = g._encounter.actor_strike(g, g.defender, g.heroes[1])
				_expect(str(directed.to.instance_id) == str(g.heroes[0].instance_id), "banner redirects actual ordinary strike to its marked hero")
		"saboteurs":
			var hp: int = g.heroes[0].hp
			_kill(g, a)
			_expect(int(g.heroes[0].hp) < hp and _seen(g.combat_events, "explosion"), "final barrel inflicts damage")
		"pickpockets":
			_advance(g, 1)
			var stolen: bool = false
			for h in g.heroes:
				stolen = stolen or h.get("equipment_disabled_slots", []).has("weapon")
			_expect(stolen, "successful hit disables equipped weapon")
		"guillotine":
			g.heroes[2].hp = 600
			var hp: int = g.heroes[2].hp
			var ev: Array = _advance(g, 7)
			_expect(_seen(ev, "prepare") and int(g.heroes[2].hp) < hp, "guillotine prepares and hits wounded rear")
		"duelist":
			_expect(not g._encounter.duel_allows(g, g.heroes[1], a), "duel blocks other ordinary attackers")
			_advance(g, 5)
			_expect(g._encounter.duel_allows(g, g.heroes[1], a), "duel expires")
		"cleaver":
			g.heroes[0].hp = 1
			var ev: Array = _advance(g, 1)
			_expect(_seen(ev, "cleave") and int(g.heroes[1].hp) < 2000, "overkill damages next living hero")
		"guardian_parry":
			_expect(_seen(_advance(g, 1), "parry"), "finite parry reacts to actual attack")
		"guardian_aegis":
			_advance(g, 2)
			_kill(g, a)
			_expect(_pending(g, "shield"), "charged guardian transfers shield on final death")
		"guardian_possessed":
			_kill(g, a)
			var spirit: bool = false
			for actor in g.defenders:
				spirit = spirit or (int(actor.hp) > 0 and actor.tags.has("spirit"))
			_expect(spirit and not bool(g._encounter.owners[0].rewarded), "body leaves live spirit without early XP")
		"ogre_earthshaker":
			var hp: int = g.heroes[1].hp
			_expect(_seen(_advance(g, 5), "prepare") and int(g.heroes[1].hp) < hp, "earthshaker damages rear as well as front")
		"ogre_stonethrower":
			var hp: int = g.heroes[2].hp
			_expect(_seen(_advance(g, 5), "prepare") and int(g.heroes[2].hp) < hp, "boulder reaches rear hero")
		"ogre_maneater":
			a.hp = 500
			g.heroes[0].hp = 1
			_expect(_seen(_advance(g, 4), "heal"), "personal kill enables one feast heal")
		"war_hound_hellfire":
			_expect(_seen(_advance(g, 5), "fire"), "prepared breath ignites actual room")
		"war_hound_lycanthrope":
			a.hp = 390
			var ev: Array = _advance(g, 1)
			_expect(_seen(ev, "transform") and int(a.hp) <= 390, "living werewolf transforms without healing")
			if stage >= 5:
				_expect(str(g.heroes[0].id) == "priest", "werewolf moves support to front")
			_kill(g, a)
			_expect(str(g.heroes[0].id) == "knight", "werewolf death immediately restores knight")
		"war_hound_sapper_hunter":
			var rogue: Dictionary = g.heroes[1]
			_advance(g, 3)
			_expect(int(rogue.disarm_charges) == 3, "hound destroys exactly one tool")
		"poison_fog_crypt":
			_expect(int(g.heroes[0].poison_ticks) > 0 and _pending(g, "fog"), "fog poisons and persists into later battle")
		"poison_spore_garden":
			_expect(g.heroes[0].has("spore"), "spore has visible carrier")
			_advance(g, 5)
			_expect(int(g.heroes[1].poison_ticks) > 0 or _seen(g.combat_events, "spore"), "carrier attacks spread poison")
		"poison_distiller":
			_expect(int(g.heroes[0].poison_ticks) == 0 and int(g.heroes[0].hp) < 2000, "distiller consumes poison into damage")
		"mimic_weapon_swap":
			_advance(g, 1)
			var swapped: bool = false
			for h in g.heroes:
				swapped = swapped or bool(h.get("weapon_swapped", false))
			_expect(swapped, "mimic replaces a real hero weapon")
		"mimic_cursed_gift":
			_expect(g.heroes[0].has("cursed_cup"), "cursed treasury gives real traveling gift")
			_kill(g, a)
			g._waiting_for_entry = true
			g.step()
			g.heroes[0].hp = int(g.heroes[0].max_hp) / 2
			var wounded_hp: int = g.heroes[0].hp
			g.combat_tick = 2
			g._encounter.heal_phase(g)
			_expect(int(g.heroes[0].hp) > wounded_hp and int(g.heroes[0].cursed_cup.uses) == 1, "gift really heals in following battle")
		"mimic_false_treasury":
			_expect(_seen(_advance(g, 1), "decoy"), "first directed attack consumes decoy")
		"mimic_living_chamber":
			if stage == 2:
				_expect(g.defenders.size() == 1 and str(g.defender.path_id) == path and _seen(_advance(g, 1), "attack"), "rank2 living center fights without premature extensions")
			else:
				_expect(g.defenders.size() > 1 and not g.reserved_room_slots().is_empty(), "empty adjacent cell becomes attacking mouth")
		"wraith_twilight_hall":
			_kill(g, a)
			g._waiting_for_entry = true
			g.step()
			_expect(g.defender.tags.has("spirit") and not g.defender.tags.has("corporeal"), "neighbour changes damage category")
		"wraith_banshee":
			var hp: int = g.heroes[1].hp
			_expect(_seen(_advance(g, 5), "prepare") and int(g.heroes[1].hp) < hp, "banshee scream deals group damage")
		"wraith_throne_guardian":
			_expect(g.current_slot == 1, "empty guardian altar skipped without battle")
			_kill(g, g.defender)
			g._waiting_for_entry = true
			g.step()
			_expect(g.current_slot == g.rooms.size() and g.defenders.size() == 2, "spirit joins Lord at throne")
			var lord_hp: int = g.lord.hp
			var hero_hp: int = g.heroes[0].hp
			_advance(g, 1)
			_expect(int(g.lord.hp) == lord_hp and int(g.heroes[0].hp) < hero_hp, "bodyguard absorbs while Lord attacks")
		"vampire_hypnotist":
			_expect(_seen(_advance(g, 4), "hypnosis"), "hypnosis prepared and applied")
		"vampire_sire":
			g.heroes[0].hp = 1
			_advance(g, 1)
			_expect(str(g.rooms[0].get("evolution_memory", {}).get("thrall", "")) == "knight", "personal kill records next-wave thrall")
		"vampire_sarcophagus_master":
			a.hp = 300
			_advance(g, 1)
			_expect(str(a.phase_id) == "sarcophagus", "living wounded vampire hides in coffin")
			_advance(g, 4)
			_expect(str(a.phase_id) == "base" and int(a.hp) > 300, "surviving ritual restores vampire")
		"spikes_armour_press":
			_expect(int(g.heroes[0].hp) < 2000, "armored front takes press damage")
		"spikes_collapsing_walkway":
			_expect(int(g.heroes[0].hp) == 2000 and int(g.heroes[1].hp) < 2000, "front crosses; rear falls")
		"spikes_blood_surge":
			_expect(int(g.heroes[0].hp) == 0 and int(g.heroes[1].hp) < 2000, "lethal spike triggers one secondary volley")
		"shackles_shared_chain":
			g.step()
			var before: int = g.heroes[0].hp + g.heroes[2].hp
			g._encounter.hero_damage(g, g.heroes[0], 20, "fixture")
			_expect(before - int(g.heroes[0].hp + g.heroes[2].hp) == 20 and int(g.heroes[2].hp) < 2000, "chain conserves damage and hurts linked rear")
		"shackles_prisoner_scales":
			_expect(int(g.heroes[0].hp) + int(g.heroes[2].hp) == 2500 and int(g.heroes[0].hp) < 2000 and int(g.heroes[2].hp) > 500, "scales preserve total HP and bring fractions closer")
			if stage == 15:
				_expect(int(g.heroes[0].hp) == 1250 and int(g.heroes[2].hp) == 1250, "final scales equalize fractions exactly")
		"shackles_garrison_gallery":
			g.step()
			_expect(g.defenders.size() == 2 and g._encounter.consumed.has(2), "two neighbours share one encounter")
		"silence_black_mass":
			g.step()
			a = _normalize_actor(g)
			a.hp = 500
			g.heroes[0].hp = 1000
			g._encounter.heal(g, g.heroes[2], g.heroes[0], 10)
			_expect(int(a.hp) > 500 and int(g.heroes[0].hp) < 1010, "one heal flows into defender")
		"silence_null_bell":
			g.step()
			_expect(int(g.heroes[0].poison_ticks) == 0, "null bell actually removes harmful poison")
		"silence_funeral_peal":
			g.step()
			g.heroes[0].hp = 0
			g._encounter.process_hero_deaths(g)
			_expect(int(g.heroes[2].get("silence_ticks", 0)) > 0, "first death suppresses surviving support")
		"rust_fracture_window":
			g.step()
			_expect(int(g.heroes[0].rust_ticks) > 0 and int(g.heroes[0].rust_amount) > 0, "next fight opens armor window")
		"rust_shard_chamber":
			_expect(int(g.heroes[1].hp) < 2000 and int(g.heroes[0].armor) == 7, "metal hurts group without permanent armor loss")
		"rust_reforging":
			g.step()
			_expect(int(g.defender.get("shield", 0)) > 0 and int(g.heroes[0].rust_amount) > 0, "armor becomes shield on next defender")
		"ballista_clear_sight":
			_expect(g._encounter.spent.has(2) and int(g.heroes[2].hp) < 2000, "ballista supports through empty cell")
		"ballista_reserve_magazine":
			_expect(int(g.rooms[0].evolution_memory.ammo) == 0 and int(g.heroes[1].hp) < 2000 and int(g.heroes[2].hp) == 2000, "finite ammunition spends at most one per hero")
		"ballista_siege":
			_expect(int(g.heroes[0].hp) < 2000 and int(g.heroes[1].hp) > int(g.heroes[0].hp) and int(g.heroes[1].hp) < 2000, "piercing bolt loses power after front target")
		"blade_floor_blood_mill":
			_expect(not g._encounter.trap_sequence.is_empty(), "mill enters finite sequence")
			_advance(g, 1)
			_expect(int(g.heroes[1].hp) < 2000, "separate mill section damages group")
		"blade_floor_partition_corridor":
			g.step()
			_expect(int(g._encounter.effects.get("partitions", {}).get("ticks", 0)) > 0, "next adjacent combat raises partitions")
			g.heroes[0].hp = 1000
			g.combat_tick = 3
			g._encounter.heal_phase(g)
			_expect(int(g.heroes[0].hp) == 1000, "partition prevents ally healing")
		"blade_floor_corpse_reclaimer":
			var expected: int = g.room_stats(0).xp
			_kill(g, g.defender)
			var total: int = 0
			for h in g.heroes:
				total += int(h.xp)
			_expect(total > 0 and total < expected and _seen(g.combat_events, "reclaim"), "mill withholds only part of owner reward")
		_:
			_expect(false, "missing explicit behavioral assertion")

func _hero_invariants() -> void:
	context = "hero arithmetic"
	_expect(Damage.hero_hit(10, 7) == 5 and Damage.hero_hit(20, 7) == 13, "armor cap examples")
	_expect(Damage.hero_hit(10, 7, "magic") == 10 and Damage.hero_hit(10, 7, "physical", true) == 10, "magic and bypass avoid armor")
	_expect(Damage.defender_hit(100, 0, PackedStringArray(["spirit"]), "physical") == 20, "spirit receives 20 percent physical")
	_expect(Damage.defender_hit(100, 0, PackedStringArray(["spirit"]), "magic") == 150, "spirit receives 150 percent magic")
	for pair in [[11, 155.4886, 13.1995], [21, 223.1742, 16.8424], [51, 499.4125, 30.4313]]:
		_expect(absf(Heroes.hp_multiplier(pair[0]) * 100.0 - pair[1]) < 0.01, "approved HP curve wave%d" % pair[0])
		_expect(absf(Heroes.damage_multiplier(pair[0]) * 10.0 - pair[2]) < 0.01, "approved damage curve wave%d" % pair[0])
	for wave in [1, 9, 10, 19, 20, 29, 30, 60]:
		for trial in range(8):
			var g = _game()
			g.wave = wave
			g.rng.seed = SEED + trial
			g._generate_party()
			var total: int = 0
			for h in g.heroes:
				var own: int = 0
				_expect(h.equipment.size() == 2, "two equipment slots")
				for item in h.equipment.values():
					if bool(Heroes.item(str(item)).get("special", false)):
						own += 1
				_expect(own <= 1, "one starting special per owner")
				total += own
			_expect(total <= Heroes.special_limit(wave), "party special cap wave%d" % wave)
			var before: Array = [g.heroes.duplicate(true), g.rng.state]
			Heroes.roll_party_equipment(g.heroes, wave, g.rng)
			_expect(before == [g.heroes, g.rng.state], "repeated equipment pass cannot reroll")
	context = "rotation and item state"
	var g = _game()
	_room(g, 0, "guardian")
	_party(g)
	Heroes.equip_item(g.heroes[0], "item_cover_shield", true)
	_start(g)
	_normalize_actor(g)
	var knight: Dictionary = g.heroes[0]
	knight.hp = 400
	g._encounter.rotate_party(g)
	_expect(str(g.heroes[0].id) == "barbarian" and int(knight.skip_attack) == 1, "rotation changes actual front and spends next attack")
	_expect(str(g._encounter.select_actor_target(g, g.defender).id) == "barbarian", "normal attack respects rotated front")
	_expect(bool(knight.equipment_state.get("cover_used", false)), "shield cover consumed")
	var covered: Dictionary = g.heroes[0]
	var same_round: Dictionary = g._encounter.actor_strike(g, g.defender, covered)
	_expect(int(same_round.hit) == 20, "cover does not protect prior round retroactively")
	g.combat_tick += 1
	var special: Dictionary = g._encounter.actor_strike(g, g.defender, covered, 1.0, true)
	_expect(int(special.hit) == 20, "cover does not block prepared special attack")
	var protected_hit: Dictionary = g._encounter.actor_strike(g, g.defender, covered)
	var second_hit: Dictionary = g._encounter.actor_strike(g, g.defender, covered)
	_expect(int(protected_hit.hit) == 14 and int(second_hit.hit) == 20, "cover reduces only first ordinary next-round hit by30percent")
	Heroes.equip_item(knight, "knight_shield", true)
	Heroes.equip_item(knight, "item_cover_shield", true)
	_expect(bool(knight.equipment_state.get("cover_used", false)), "re-equipping cannot refresh charge")
	knight.hp = 1500
	g._encounter.rotate_party(g)
	_expect(str(g.heroes[0].id) == "knight", "recovered knight returns")
	knight.hp = 1
	g._encounter.rotate_party(g)
	_expect(str(g.heroes[0].id) == "knight", "second voluntary retreat forbidden")

func _death_and_reward_invariants() -> void:
	for blocked in ["", "silence_ticks", "cocoon_ticks", "partitions"]:
		context = "last prayer " + blocked
		var g = _game()
		_room(g, 0, "goblin")
		_party(g)
		Heroes.equip_item(g.heroes[2], "item_last_prayer", true)
		_start(g)
		var priest: Dictionary = g.heroes[2]
		g.heroes[0].hp = 100
		g.heroes[1].hp = 0
		priest.hp = 0
		if blocked == "partitions":
			g._encounter.effects.partitions = {"ticks": 1}
		elif not blocked.is_empty():
			priest[blocked] = 1
		g._encounter.process_hero_deaths(g)
		_expect(int(g.heroes[0].hp) == (106 if blocked.is_empty() else 100), "death snapshot preserves healing restrictions")
		_expect(int(g.heroes[1].hp) == 0, "simultaneously dead ally never revived")
		var state: Array = [g.gold, g.lord.xp, g.heroes[0].hp]
		g._encounter.process_hero_deaths(g)
		_expect(state == [g.gold, g.lord.xp, g.heroes[0].hp], "repeated death processing is idempotent")
	for path in ["brood_mother", "guardian_possessed"]:
		context = "owner reward " + path
		var g = _game()
		_room(g, 0, str(Catalog.path(path).room_id), path, 15)
		_party(g)
		_start(g)
		g.defender.revive_mark = true
		g.defender.revive_fraction = 0.5
		_kill(g, g.defender)
		_expect(int(g.defender.hp) > 0 and not bool(g._encounter.owners[0].rewarded), "revival precedes final phase and XP")
		for _i in range(10):
			for actor in g.defenders.duplicate():
				if int(actor.hp) > 0:
					actor.hp = 0
			g._encounter.resolve_actor_deaths(g)
			g._encounter.finish_owners(g)
		_expect(bool(g._encounter.owners[0].rewarded) and not g._encounter.owner_alive(0), "finite offspring/phases end in one owner reward")
		var before: Array = g.heroes.duplicate(true)
		g._encounter.finish_owners(g)
		_expect(before == g.heroes, "owner reward cannot repeat")

func _route_and_state_invariants() -> void:
	context = "route and preview"
	var g = _game()
	g.floor_count = 2
	g.floor_traits.append("plain")
	for _i in range(5):
		g.rooms.append({})
	_expect(g._encounter.next_neighbor(g, 4) == -1 and g._encounter.next_neighbor(g, 5) == -1, "links never cross floor boundary")
	_expect(g._encounter.next_neighbor(g, 9) == 8 and g._encounter.next_neighbor(g, 0) == 1, "links follow snake direction")
	_room(g, 7, "mimic", "mimic_living_chamber", 15)
	_expect(g.reserved_room_slots().has(6) and g.reserved_room_slots().has(8), "living chamber reserves both real empty neighbours")
	_expect(not g.buy_room(6, "goblin").is_empty(), "cannot build inside reserved mouth")
	var snapshot: Array = [g.rooms.duplicate(true), g.gold, g.rng.state, g.deal_rng.state, g.expedition_rng.state]
	for _i in range(5):
		g.room_stats(7)
		g.room_tree(7)
		g.reserved_room_slots()
	_expect(snapshot == [g.rooms, g.gold, g.rng.state, g.deal_rng.state, g.expedition_rng.state], "previews are pure")
	_expect(g.sell_room(7).is_empty() and g.reserved_room_slots().is_empty(), "selling center releases mouths")
	context = "sapper persistence"
	g = _game()
	_room(g, 0, "guardian")
	_room(g, 1, "spikes", "spikes_armour_press", 2)
	_party(g, ["knight", "rogue", "priest"])
	Heroes.equip_item(g.heroes[1], "item_sapper_crossbow", true)
	_start(g)
	var rogue: Dictionary = g.heroes[1]
	g._encounter.try_sapper_shot(g, rogue)
	_expect(int(rogue.disarm_charges) == 3 and bool(g._encounter.disarmed.get(1, false)), "sapper prep spends exactly one tool")
	rogue.hp = 0
	g._encounter.process_hero_deaths(g)
	_expect(g._encounter.disarm(g, 1) and int(rogue.disarm_charges) == 3, "prepared disarm survives sapper death without second spend")
	context = "event monotonicity"
	var last: int = -1
	for _i in range(5):
		g.step()
		for event in g.combat_events:
			var sequence: int = int(event.get("sequence", event.get("seq", -1)))
			_expect(sequence > last, "events have increasing unique sequence")
			last = sequence
		_expect(g.combat_events.size() <= 128, "events bounded per step")

func _special_item_invariants() -> void:
	context = "splitter successful hits"
	var g = _game()
	_room(g, 0, "guardian")
	_party(g, ["barbarian"])
	Heroes.equip_item(g.heroes[0], "item_armour_splitter", true)
	_start(g)
	var a: Dictionary = _normalize_actor(g)
	a.armor = 3
	var hero: Dictionary = g.heroes[0]
	_advance(g, 2)
	_expect(int(a.effects.get("split_ticks", 0)) == 0, "two hits do not split armor")
	_expect(_seen(_advance(g, 1), "armor_break") and int(a.effects.get("split_ticks", 0)) == 2, "third successful hit splits armor for next two rounds")
	_advance(g, 3)
	_expect(int(a.effects.get("split_ticks", 0)) == 0 and bool(hero.equipment_state.get("split_used", false)), "split expires and cannot repeat")
	context = "memory staff"
	g = _game()
	_room(g, 0, "guardian")
	_party(g, ["mage"])
	Heroes.equip_item(g.heroes[0], "item_memory_staff", true)
	_start(g)
	a = _normalize_actor(g)
	hero = g.heroes[0]
	hero.silence_ticks = 3
	_advance(g, 3)
	_expect(bool(hero.equipment_state.get("stored_spell", false)), "silenced ready spell is stored")
	var strike: Dictionary = g._encounter.plan_hero_attack(g, hero, a)
	_expect(bool(strike.get("charged", false)) and not bool(hero.equipment_state.get("stored_spell", false)), "stored spell uses first available action exactly once")
	_expect(int(hero.equipment_state.get("spell_clock", -1)) == 0, "stored spell resets ordinary charge cycle")
	hero.equipment_state.stored_spell = true
	hero.equipment_disabled_slots = ["weapon"]
	g._encounter.plan_hero_attack(g, hero, a)
	_expect(not bool(hero.equipment_state.get("stored_spell", false)) and bool(hero.equipment_state.get("memory_used", false)), "disabled staff loses stored charge without refreshing use")
	context = "drum delays one prepared physical attack"
	g = _game()
	_room(g, 0, "ogre", "ogre_earthshaker", 15)
	_party(g, ["bard"])
	Heroes.equip_item(g.heroes[0], "item_broken_rhythm_drum", true)
	_start(g)
	a = _normalize_actor(g)
	hero = g.heroes[0]
	_advance(g, 2)
	_expect(a.effects.has("preparing"), "real ogre begins preparation")
	var wait_before: int = a.effects.preparing.remaining
	var hp_before: int = a.hp
	var ev: Array = _advance(g, 1)
	_expect(_seen(ev, "delay") and int(a.effects.preparing.remaining) == wait_before, "drum offsets one preparation tick")
	_expect(int(a.hp) == hp_before, "bard replaces ordinary attack with drum action")
	_expect(not g._encounter.play_drum(g, hero, g._encounter.living_actors()), "same drum cannot delay a second time")
	context = "sword replacement removes old bonus"
	g = _game()
	hero = _hero(g, "knight")
	g._recalculate_hero(hero)
	var base_damage: int = hero.damage
	Heroes.equip_item(hero, "sword", true)
	g._recalculate_hero(hero)
	_expect(int(hero.damage) == base_damage + 3, "single weapon bonus applied once")
	Heroes.equip_item(hero, "knight_sword", true)
	g._recalculate_hero(hero)
	_expect(int(hero.damage) == base_damage and hero.equipment.size() == 2, "replacing weapon removes prior bonus")

func _encounter_edge_cases() -> void:
	context = "chain plus cleaver conserves declared damage"
	var chained = _game()
	_room(chained, 0, "executioner", "cleaver", 2)
	_party(chained, ["barbarian", "priest"])
	_start(chained)
	var executioner: Dictionary = _normalize_actor(chained)
	chained.heroes[0].hp = 5
	chained._encounter.effects.chain = {"ids": [chained.heroes[0].instance_id, chained.heroes[1].instance_id], "charges": 1, "fraction": 0.25}
	var combined_hp: int = chained.heroes[0].hp + chained.heroes[1].hp
	var declared: Dictionary = chained._encounter.actor_strike(chained, executioner, chained.heroes[0])
	var batch: Array[Dictionary] = [declared]
	chained._encounter.resolve_strikes(chained, batch)
	_expect(combined_hp - int(chained.heroes[0].hp + chained.heroes[1].hp) == int(declared.hit), "cleaver never carries again the portion already transferred by chain")
	context = "cocoon timing and source death"
	var g = _game()
	_room(g, 0, "spider", "cocoon_weaver", 15)
	_party(g, ["knight"])
	_start(g)
	var a: Dictionary = _normalize_actor(g)
	var casts: Array[int] = []
	var first_cast: int = -1
	var blocked: int = 0
	for _i in range(24):
		var was_blocked: bool = not g._encounter.can_act(g.heroes[0])
		var before: int = a.hp
		g.step()
		if was_blocked:
			blocked += 1
			_expect(int(a.hp) == before, "cocoon prevents ordinary attack")
		if _seen(g.combat_events, "cocoon"):
			casts.append(g.tick)
			if first_cast < 0:
				first_cast = g.tick
				_expect(int(g.heroes[0].cocoon_ticks) == 4, "final cocoon lasts four half-second ticks")
	_expect(casts.size() >= 2 and casts[1] - casts[0] == 16, "cocoon cooldown is eight simulated seconds")
	_expect(blocked >= 4, "cocoon really blocks actions")
	g.heroes[0].cocoon_ticks = 4
	g.heroes[0].effects.cocoon_source = a.actor_id
	_kill(g, a)
	_expect(int(g.heroes[0].cocoon_ticks) == 0, "caster death immediately releases cocoon")
	context = "cocoon blocks passive support"
	g = _game()
	_room(g, 0, "guardian")
	_party(g, ["knight", "bard", "priest"])
	_start(g)
	a = _normalize_actor(g)
	var fighter: Dictionary = g.heroes[0]
	var bard: Dictionary = g.heroes[1]
	var priest: Dictionary = g.heroes[2]
	var sung: Dictionary = g._encounter.plan_hero_attack(g, fighter, a)
	bard.cocoon_ticks = 4
	priest.cocoon_ticks = 4
	var unsung: Dictionary = g._encounter.plan_hero_attack(g, fighter, a)
	_expect(int(unsung.hit) < int(sung.hit), "cocoon suppresses bard song")
	_expect(is_equal_approx(g._poison_aura_multiplier(), 1.0), "cocoon suppresses priest poison aura")
	fighter.hp = 1000
	g.combat_tick = 3
	g._encounter.heal_phase(g)
	_expect(int(fighter.hp) == 1000, "cocoon prevents priest active healing")
	context = "initial web survives to first attack"
	g = _game()
	_room(g, 0, "spider", "cocoon_weaver", 2)
	_party(g, ["knight"])
	_start(g)
	a = _normalize_actor(g)
	var unwebbed: Dictionary = g._encounter.plan_hero_attack(g, g.heroes[0], a)
	_advance(g, 1)
	var webbed: Dictionary = g._encounter.plan_hero_attack(g, g.heroes[0], a)
	_expect(int(webbed.hit) < int(unwebbed.hit), "rank2 web weakens next actual attack")
	context = "gallery separate owner budgets"
	g = _game()
	_room(g, 0, "shackles", "shackles_garrison_gallery", 15)
	_room(g, 1, "goblin")
	_room(g, 2, "executioner")
	_room(g, 3, "guardian")
	_party(g)
	_start(g)
	g.step()
	_expect(g.defenders.size() == 2, "gallery creates both defenders")
	var expected: int = int(g.room_stats(1).xp) + int(g.room_stats(2).xp)
	for actor in g.defenders:
		actor.hp = 0
	g._encounter.resolve_actor_deaths(g)
	g._encounter.finish_owners(g)
	var total: int = 0
	for h in g.heroes:
		total += int(h.xp)
	_expect(total == expected, "gallery awards each independent room exactly once")
	g._waiting_for_entry = true
	g.step()
	_expect(g.current_slot == 3, "second gallery slot cannot fight again")
	context = "banshee finite echo"
	g = _game()
	_room(g, 0, "wraith", "wraith_banshee", 15)
	_room(g, 1, "goblin")
	_room(g, 2, "guardian")
	_party(g)
	_start(g)
	a = _normalize_actor(g)
	_advance(g, 5)
	_kill(g, a)
	g._waiting_for_entry = true
	var before: int = g.heroes[1].hp
	g.step()
	_expect(_seen(g.combat_events, "echo") and int(g.heroes[1].hp) < before, "rank15 scream echoes in next encounter")
	_kill(g, g.defender)
	g._waiting_for_entry = true
	g.step()
	_expect(not _seen(g.combat_events, "echo"), "banshee echo cannot repeat")
	context = "throne guard reservation"
	g = _game()
	_room(g, 0, "wraith", "wraith_throne_guardian", 15)
	_room(g, 1, "goblin")
	_party(g)
	_start(g)
	_kill(g, g.defender)
	_expect(not bool(g._encounter.owners[0].rewarded), "unengaged reserve never grants premature XP")
	context = "arsenal refill"
	g = _game()
	_room(g, 0, "ballista", "ballista_reserve_magazine", 15)
	for _i in range(6):
		g.phase = "result"
		g.next_wave()
		g.phase = "prepare"
	_expect(int(g.rooms[0].get("evolution_memory", {}).get("ammo", 0)) == 4, "arsenal obeys finite capacity")
	var ammo: int = g.rooms[0].evolution_memory.ammo
	g.room_tree(0)
	g.move_room(0, 3)
	g.room_stats(3)
	_expect(int(g.rooms[3].evolution_memory.ammo) == ammo, "preview and relocation add no ammunition")
	context = "werewolf lethal hit"
	g = _game()
	_room(g, 0, "war_hound", "war_hound_lycanthrope", 15)
	_party(g)
	_start(g)
	a = _normalize_actor(g)
	a.hp = 1
	var ev: Array = _advance(g, 1)
	_expect(not _seen(ev, "transform") and int(a.hp) == 0, "lethal hit cannot trigger living transformation")
	context = "one throne reserve per wave"
	g = _game()
	_room(g, 0, "wraith", "wraith_throne_guardian", 15)
	_room(g, 1, "wraith", "wraith_throne_guardian", 15)
	_party(g)
	_start(g)
	var guards: int = 0
	for actor in g.defenders:
		if str(actor.phase_id) == "throne_guard":
			guards += 1
	_expect(guards <= 1, "approved throne reserve cap applies across multiple altars")

func _cup_invariants() -> void:
	context = "cursed cup limited lifetime"
	var g = _game()
	_room(g, 0, "mimic", "mimic_cursed_gift", 15)
	for slot in [1, 2, 3]:
		_room(g, slot, "guardian")
	_party(g)
	_start(g)
	var carrier: Dictionary = g.heroes[0]
	for use in range(1, 4):
		_kill(g, g.defender)
		g._waiting_for_entry = true
		g.step()
		carrier.hp = int(carrier.max_hp) / 2
		var wounded_hp: int = carrier.hp
		g.combat_tick = 2
		g._encounter.heal_phase(g)
		if use < 3:
			_expect(int(carrier.hp) > wounded_hp and int(carrier.cursed_cup.uses) == use, "cup count survives room transition")
			var before: int = carrier.hp
			g._encounter.heal_phase(g)
			_expect(int(carrier.hp) == before and int(carrier.cursed_cup.uses) == use, "cup cannot heal twice in one battle")
		else:
			_expect(not carrier.has("cursed_cup") and int(carrier.hp) < wounded_hp and _seen(g.combat_events, "curse"), "third real healing bites and destroys cup")
	context = "rogue recognizes cursed gift"
	g = _game()
	_room(g, 0, "mimic", "mimic_cursed_gift", 15)
	_party(g, ["knight", "rogue", "priest"])
	_start(g)
	var gift: bool = false
	for h in g.heroes:
		gift = gift or h.has("cursed_cup")
	_expect(not gift, "living rogue recognizes false gift before pickup")

func _servant_regressions() -> void:
	context = "vampire candidate preparation"
	var g = _game()
	_room(g, 0, "vampire", "vampire_sire", 15)
	_party(g, ["knight", "mage", "priest"])
	_start(g)
	var vampire: Dictionary = _normalize_actor(g)
	for victim in g.heroes:
		if str(victim.id) not in ["knight", "mage"]:
			continue
		victim.hp = 1
		var strikes: Array[Dictionary] = [g._encounter.actor_strike(g, vampire, victim)]
		g._encounter.resolve_strikes(g, strikes)
		g._encounter.process_hero_deaths(g)
	var memory: Dictionary = g.rooms[0].get("evolution_memory", {})
	_expect(memory.get("thrall_candidates", []).has("knight") and memory.get("thrall_candidates", []).has("mage"), "final sire records distinct personally defeated candidates")
	_expect(not g.set_room_evolution_control(0, "thrall_class", "mage").is_empty(), "cannot select servant during combat")
	g.phase = "result"
	_expect(g.next_wave().is_empty(), "candidate wave advances normally")
	_expect(g.set_room_evolution_control(0, "thrall_class", "mage").is_empty(), "choose earned candidate in next preparation")
	_expect(not g.set_room_evolution_control(0, "thrall_class", "bard").is_empty(), "cannot invent unearned servant")
	_expect(str(g.rooms[0].evolution_memory.thrall) == "mage", "selected candidate persists in room memory")
	_party(g)
	_start(g)
	var servants: Array[Dictionary] = []
	for actor in g.defenders:
		if str(actor.phase_id) == "servant":
			servants.append(actor)
	_expect(servants.size() == 1 and str(servants[0].servant_class) == "mage", "selected candidate appears as exactly one servant")
	g.phase = "result"
	g.next_wave()
	g.phase = "prepare"
	_party(g)
	_start(g)
	var repeated: bool = false
	for actor in g.defenders:
		repeated = repeated or str(actor.phase_id) == "servant"
	_expect(not repeated, "unearned old servant never appears in a second wave")
	for role in ["knight", "rogue", "barbarian", "bard", "mage", "priest"]:
		context = "servant class action " + role
		g = _game()
		_room(g, 0, "vampire", "vampire_sire", 15)
		g.rooms[0].evolution_memory = {"thrall": role, "thrall_candidates": [role], "thrall_wave": g.wave}
		_party(g, ["barbarian"])
		g.heroes[0].armor = 8
		_start(g)
		vampire = _normalize_actor(g)
		vampire.hp = 500
		var servant: Dictionary = {}
		for actor in g.defenders:
			if str(actor.phase_id) == "servant":
				servant = actor
		_expect(not servant.is_empty(), "fixture creates selected servant")
		if servant.is_empty():
			continue
		servant.hp = 300 if role == "barbarian" else 1000
		servant.max_hp = 1000
		servant.tree_base_hp = 1000.0
		servant.tree_hp_bonus = 0.0
		servant.damage = 20
		servant.tree_base_damage = 20.0
		servant.tree_damage_bonus = 0.0
		servant.age = 3 if role in ["mage", "priest"] else 1
		var attacks: Array[Dictionary] = []
		g._encounter.plan_actor(g, servant, attacks)
		_expect(bool(servant.charges.get("class_used", false)), "class action consumes its finite use")
		match role:
			"knight":
				_expect(int(servant.get("shield", 0)) > 0, "knight servant gains real damage shield")
			"rogue":
				_expect(not attacks.is_empty() and int(attacks[0].hit) == 20, "rogue servant's one shot bypasses target armor")
			"barbarian":
				_expect(not attacks.is_empty() and int(attacks[0].hit) > Damage.hero_hit(20, 8), "wounded barbarian servant makes a stronger physical strike")
			"bard":
				var sung: Dictionary = g._encounter.actor_strike(g, vampire, g.heroes[0])
				_expect(int(sung.hit) > Damage.hero_hit(20, 8), "bard servant empowers one ally strike")
				var plain: Dictionary = g._encounter.actor_strike(g, vampire, g.heroes[0])
				_expect(int(plain.hit) == Damage.hero_hit(20, 8), "bard servant buff is finite")
			"mage":
				_expect(not attacks.is_empty() and str(attacks[0].type) == "magic" and int(attacks[0].hit) == 30, "mage servant casts a genuine charged magic strike")
			"priest":
				g._encounter.resolve_strikes(g, attacks)
				_expect(int(vampire.hp) > 500, "priest servant actually restores ally HP")

func _twilight_and_deal_regressions() -> void:
	for source_slot in [2, 7]:
		for direction in ["previous", "next"]:
			context = "twilight selection slot%d %s" % [source_slot, direction]
			var g = _game()
			g.floor_count = 2
			g.floor_traits.append("plain")
			for _i in range(5):
				g.rooms.append({})
			_room(g, source_slot - 1, "guardian")
			_room(g, source_slot + 1, "goblin")
			_room(g, source_slot, "wraith", "wraith_twilight_hall", 15)
			_expect(g.set_room_evolution_control(source_slot, "spirit_direction", direction).is_empty(), "final twilight direction can be chosen in preparation")
			var next: int = g.next_route_slot(source_slot)
			var previous: int = g._previous_route_slot(source_slot)
			var chosen: int = previous if direction == "previous" else next
			var unchosen: int = next if direction == "previous" else previous
			_party(g)
			_expect(g.start_raid().is_empty(), "start routed twilight encounter")
			_expect(not g.set_room_evolution_control(source_slot, "spirit_direction", "next" if direction == "previous" else "previous").is_empty(), "cannot redirect twilight mid-wave")
			var covered: Dictionary = g._encounter.make_actor(g, chosen, g.room_stats(chosen))
			var ordinary: Dictionary = g._encounter.make_actor(g, unchosen, g.room_stats(unchosen))
			_expect(covered.tags.has("spirit") and not covered.tags.has("corporeal") and not ordinary.tags.has("spirit"), "only selected snake neighbour becomes spirit")
	context = "twilight lower rank and phase guard"
	var g = _game()
	_room(g, 0, "wraith", "wraith_twilight_hall", 5)
	_expect(not g.set_room_evolution_control(0, "spirit_direction", "previous").is_empty(), "previous-neighbour control unavailable before rank15")
	context = "deal cannot occupy living mouth"
	g = _game()
	_room(g, 2, "mimic", "mimic_living_chamber", 15)
	g.wave = 6
	g._prepare_deal()
	var before: Array = [g.gold, g.rooms.duplicate(true), g.heroes.duplicate(true), g.deal_offer()]
	_expect(not g.buy_deal_room(1).is_empty(), "deal rejects empty but reserved mouth cell")
	_expect(before == [g.gold, g.rooms, g.heroes, g.deal_offer()], "rejected mouth deal does not charge gold or add hero risk")
	_expect(g.buy_deal_room(0).is_empty(), "same valid deal still works on free unreserved cell")

func _echo_fixture(path: String, enabled: bool) -> Dictionary:
	var g = _game()
	if enabled:
		g.selected_relics.append("trap_echo")
	var slot: int = 1 if path == "blade_floor_corpse_reclaimer" else 0
	if slot == 1:
		_room(g, 0, "goblin")
	_room(g, slot, str(Catalog.path(path).room_id), path, 15)
	if slot == 0:
		_room(g, 1, "guardian")
		if path == "shackles_garrison_gallery":
			_room(g, 2, "executioner")
	_room(g, 4, "spikes", "spikes_armour_press", 2)
	_party(g)
	g.heroes[0].armor = 7
	g.heroes[2].hp = 500
	_start(g)
	if slot == 1:
		_kill(g, g.defender)
	elif path != "shackles_prisoner_scales":
		g.step()
	var state: Array = []
	for h in g.heroes:
		state.append([h.hp, h.xp, h.armor, h.get("rust_amount", 0)])
	state.append(g.defenders.size())
	state.append(g.defender.get("shield", 0))
	state.append(g._encounter.effects.duplicate(true))
	_expect(g._echo_floors.is_empty(), "unsupported mechanism preserves floor echo charge")
	return {"game": g, "signature": state}

func _echo_regressions() -> void:
	for path in ["shackles_shared_chain", "shackles_prisoner_scales", "shackles_garrison_gallery", "blade_floor_corpse_reclaimer", "rust_reforging", "silence_black_mass"]:
		context = "trap echo excluded " + path
		var normal: Dictionary = _echo_fixture(path, false)
		var echoed: Dictionary = _echo_fixture(path, true)
		_expect(normal.signature == echoed.signature, "echo cannot duplicate HP transfer, defenders, shields, reward, or healing transfer")
		var g = echoed.game
		# Continue to an untouched compatible trap on the same floor. The skip
		# isolates echo consumption from combat duration and unrelated deaths.
		g.current_slot = 3
		g._waiting_for_entry = true
		g.step()
		_expect(g._echo_floors == [0] and _seen(g.combat_events, "echo"), "next compatible trap consumes the preserved echo once")
		var hp: Array = []
		for h in g.heroes:
			hp.append(h.hp)
		g.combat_events.clear()
		g._encounter.trigger_trap(g, 4, g.room_stats(4), false)
		var after: Array = []
		for h in g.heroes:
			after.append(h.hp)
		_expect(hp == after and not _seen(g.combat_events, "echo") and g._echo_floors == [0], "spent compatible trap cannot repeat damage or echo")

func _run() -> void:
	print("Evolution rules: seed=%d; isolated in-memory models; no player saves" % SEED)
	_catalog_and_finite()
	for path in Catalog.path_ids():
		for stage in [2, 5, 15]:
			_path_effect(path, stage)
	_hero_invariants()
	_death_and_reward_invariants()
	_route_and_state_invariants()
	_special_item_invariants()
	_encounter_edge_cases()
	_cup_invariants()
	_servant_regressions()
	_twilight_and_deal_regressions()
	_echo_regressions()
	for failure in failures:
		push_error(failure)
	print("%s: %d checks; %d failures; %d paths x 3 stages" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size(), Catalog.path_ids().size()])
	quit(0 if failures.is_empty() else 1)

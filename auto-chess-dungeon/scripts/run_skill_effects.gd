extends RefCounted
## Run-tree combat state belongs to the wave, never to a temporary actor form.
## The caller supplies base values before tree percentages and final rounding.

static func has(g, id: String) -> bool:
	return g.has_run_skill(id)


static func value(g, id: String, key: String, fallback: float = 0.0) -> float:
	return g.run_skill_number(id, key, fallback) if has(g, id) else 0.0


static func room(g, slot: int) -> Dictionary:
	if not g.run_skill_runtime.has("combat_rooms"):
		g.run_skill_runtime.combat_rooms = {}
	var key: String = g._battle_source(slot)
	if not g.run_skill_runtime.combat_rooms.has(key):
		g.run_skill_runtime.combat_rooms[key] = {}
	return g.run_skill_runtime.combat_rooms[key]


static func wave(g) -> Dictionary:
	if not g.run_skill_runtime.has("combat_wave"):
		g.run_skill_runtime.combat_wave = {}
	return g.run_skill_runtime.combat_wave


static func once(state: Dictionary, key: String) -> bool:
	if bool(state.get(key, false)):
		return false
	state[key] = true
	return true


static func extra_actor(actor: Dictionary) -> bool:
	return str(actor.get("phase_id", "")) in ["spiderling", "servant"]


static func mark(actor: Dictionary, id: String, remaining: int) -> void:
	if not actor.effects.has("run_skills"):
		actor.effects.run_skills = {}
	actor.effects.run_skills[id] = remaining


static func base_damage(actor: Dictionary) -> float:
	return float(actor.get("tree_base_damage", actor.get("damage", 0.0)))


static func damage(actor: Dictionary, bonus: float = 0.0, factor: float = 1.0) -> float:
	return base_damage(actor) * (1.0 + float(actor.get("tree_damage_bonus", 0.0)) + bonus) * factor


static func heal_amount(g, amount: float, mass: bool = false) -> int:
	var bonus: float = value(g, "shared_dark_recovery", "creature_healing_amount_bonus")
	if mass:
		bonus += value(g, "shared_mass_conduit", "redirected_healing_received_by_defender_bonus")
	return maxi(0, ceili(amount * (1.0 + bonus)))


static func actor_spawn(g, actor: Dictionary) -> void:
	var slot: int = int(actor.source_slot)
	var state: Dictionary = room(g, slot)
	if str(actor.actor_id) == "lord":
		return
	if extra_actor(actor) and has(g, "creatures_hardy_brood"):
		var hp_base: float = float(actor.get("tree_base_hp", actor.max_hp))
		actor.max_hp = maxi(1, ceili(hp_base * (1.0 + float(actor.get("tree_hp_bonus", 0.0)) + value(g, "creatures_hardy_brood", "extra_max_health_fraction"))))
		actor.hp = actor.max_hp
		mark(actor, "creatures_hardy_brood", 1)
	if actor.get("tags", PackedStringArray()).has("spirit"):
		actor.armor = maxi(0, int(actor.armor) - int(actor.get("tree_bone_armor", 0)))
		actor.tree_bone_armor = 0
	if not bool(state.get("entered", false)):
		state.entered = true
		var prev: int = g._previous_route_slot(slot)
		if has(g, "creatures_discipline") and prev >= 0 and prev < g.rooms.size() and prev / 5 == slot / 5 and not g.rooms[prev].is_empty() and str(g.room_stats(prev).kind) == "monster" and str(g.rooms[prev].get("status", "")) == "cleared":
			state.discipline = 2
	mark(actor, "creatures_discipline", int(state.get("discipline", 0)))
	mark(actor, "creatures_united_pack", int(state.get("pack", 0)))


static func attack_bonus(g, actor: Dictionary, target: Dictionary, ordinary: bool, ability: String = "") -> Dictionary:
	var state: Dictionary = room(g, int(actor.source_slot))
	var global: Dictionary = wave(g)
	var bonus: float = 0.0
	var bypass: int = 0
	var lord: bool = str(actor.actor_id) == "lord"
	if ordinary:
		bonus += value(g, "shared_unity_of_power", "ordinary_lord_attack_damage_bonus" if lord else "ordinary_creature_attack_damage_bonus")
		if lord:
			if has(g, "lord_throne_wrath") and once(global, "wrath"):
				bonus += value(g, "lord_throne_wrath", "first_ordinary_attack_damage_bonus")
			if bool(global.get("last_word_ready", false)):
				global.last_word_ready = false
				bonus += value(g, "lord_last_word", "next_ordinary_attack_damage_bonus")
			if bool(global.get("counter_ready", false)):
				global.counter_ready = false
				bonus += value(g, "lord_counterstrike", "next_ordinary_attack_damage_bonus")
			if int(global.get("oath", 0)) > 0:
				global.oath = int(global.oath) - 1
				bonus += value(g, "shared_oath_of_the_fallen", "ordinary_attack_bonus_per_spent_mark")
		else:
			bonus += value(g, "creatures_frenzied_servants", "ordinary_creature_attack_damage_bonus")
			if str(actor.id) in ["spider", "war_hound"]:
				bonus += value(g, "creatures_beast_ferocity", "ordinary_attack_damage_bonus")
			if extra_actor(actor):
				bonus += value(g, "creatures_trained_brood", "additional_actor_ordinary_attack_damage_bonus")
			if str(actor.phase_id) == "appendage":
				bonus += value(g, "creatures_hungry_extensions", "extension_ordinary_attack_damage_bonus")
			if has(g, "creatures_battle_rhythm"):
				state.rhythm = int(state.get("rhythm", 0)) + 1
				if int(state.rhythm) % 4 == 0:
					bonus += value(g, "creatures_battle_rhythm", "fourth_attack_bonus")
				mark(actor, "creatures_battle_rhythm", 4 - int(state.rhythm) % 4)
			for key in ["stubborn", "discipline", "hunt", "pack"]:
				if int(state.get(key, 0)) <= 0 or (key == "pack" and not extra_actor(actor)):
					continue
				state[key] = int(state[key]) - 1
				var id: String = {"stubborn": "creatures_stubbornness", "discipline": "creatures_discipline", "hunt": "creatures_hunting_instinct", "pack": "creatures_united_pack"}[key]
				bonus += value(g, id, "ordinary_attack_bonus")
				mark(actor, id, int(state[key]))
				if key == "hunt":
					bypass = int(value(g, "creatures_onslaught", "ignored_armor"))
				if key == "stubborn" and int(state.stubborn) == 0:
					state.defiance_expire = true
		if int(actor.get("run_impulse_count", 0)) > 0:
			bonus += float(actor.get("run_impulse_bonus", 0.1)) + float(actor.get("run_edge_bonus", 0.0))
			actor.run_impulse_count = int(actor.run_impulse_count) - 1
			actor.run_edge_bonus = 0.0
			mark(actor, "ritual_impulse", int(actor.run_impulse_count))
	if not lord:
		if ability in ["earthshaker", "boulder"]:
			bonus += value(g, "creatures_heavy_swing", "prepared_physical_attack_damage_bonus")
		elif ability in ["banshee", "banshee_echo"]:
			bonus += value(g, "creatures_power_of_lament", "scream_damage_bonus")
		elif ability == "parry":
			bonus += value(g, "creatures_retaliatory_steel", "parry_counterattack_damage_bonus")
		if str(actor.id) == "executioner" and (ordinary or ability in ["guillotine", "cleaver"]) and int(target.hp) * 10 < int(target.max_hp) * 3 and has(g, "creatures_anatomy_knowledge") and once(state, "anatomy"):
			bonus += value(g, "creatures_anatomy_knowledge", "damage_bonus")
	return {"bonus": bonus, "armor_bypass": bypass}


static func protect(g, actor: Dictionary, hit: float, ordinary: bool, kind: String, charged: bool) -> int:
	var state: Dictionary = room(g, int(actor.source_slot))
	var global: Dictionary = wave(g)
	var reduction: float = 0.0
	if str(actor.actor_id) != "lord":
		if kind == "magic" and actor.get("tags", PackedStringArray()).has("spirit") and has(g, "creatures_spectral_resilience"):
			hit *= value(g, "creatures_spectral_resilience", "spirit_form_received_magic_damage_multiplier")
		if ordinary and kind == "physical":
			if has(g, "creatures_tough_hide") and once(state, "hide"):
				reduction += value(g, "creatures_tough_hide", "damage_reduction")
				mark(actor, "creatures_tough_hide", 0)
			if bool(state.get("defiance", false)):
				state.defiance = false
				reduction += value(g, "creatures_defiance", "damage_reduction")
	# shield is the TOTAL pool; run_cover_shield is only its tracked subset.
	elif ordinary and kind == "physical" and hit > int(actor.get("shield", 0)) and has(g, "lord_fortified_throne") and once(global, "fortified"):
		reduction += value(g, "lord_fortified_throne", "damage_reduction")
	hit *= maxf(0.0, 1.0 - reduction)
	if charged and bool(actor.get("run_barrier", false)):
		actor.run_barrier = false
		hit *= 1.0 - value(g, "ritual_barrier", "damage_reduction", 0.2)
		mark(actor, "ritual_barrier", 0)
	return maxi(0, ceili(hit))


static func after_received(g, actor: Dictionary, strike: Dictionary) -> void:
	if int(strike.actual) <= 0 or int(actor.hp) <= 0:
		return
	var state: Dictionary = room(g, int(actor.source_slot))
	var global: Dictionary = wave(g)
	if str(actor.actor_id) == "lord":
		if has(g, "lord_last_word") and int(actor.hp) * 4 < int(actor.max_hp) and once(global, "last_word"):
			global.last_word_ready = true
			mark(actor, "lord_last_word", 1)
		if bool(strike.ordinary) and has(g, "lord_counterstrike"):
			global.counter_hits = int(global.get("counter_hits", 0)) + 1
			if int(global.counter_hits) >= 3 and once(global, "counterstrike"):
				global.counter_ready = true
				mark(actor, "lord_counterstrike", 1)
	else:
		if has(g, "creatures_stubbornness") and int(actor.hp) * 10 < int(actor.max_hp) * 3 and once(state, "stubborn_used"):
			state.stubborn = 2
			state.defiance = has(g, "creatures_defiance")
			mark(actor, "creatures_stubbornness", 2)


static func personal_kill(g, actor: Dictionary, ordinary: bool) -> int:
	if int(actor.hp) <= 0:
		return 0
	var amount: int = 0
	if str(actor.actor_id) == "lord":
		if ordinary and has(g, "lord_blood_throne") and once(wave(g), "blood_throne"):
			amount = ceili(actor.max_hp * value(g, "lord_blood_throne", "max_hp_heal_fraction"))
	elif has(g, "creatures_dark_legion") and once(room(g, int(actor.source_slot)), "dark_legion"):
		amount = heal_amount(g, actor.max_hp * value(g, "creatures_dark_legion", "max_health_heal_fraction"))
	amount = mini(amount, int(actor.max_hp) - int(actor.hp))
	actor.hp = int(actor.hp) + amount
	return amount


static func final_death(g, actor: Dictionary) -> void:
	if str(actor.actor_id) == "lord":
		return
	var state: Dictionary = room(g, int(actor.source_slot))
	if str(actor.phase_id) not in ["spiderling", "servant", "appendage", "throne_guard"] and has(g, "creatures_united_pack") and once(state, "pack_used"):
		state.pack = 2
	if int(actor.get("run_impulse_count", 0)) > 0 and has(g, "shared_impulse_legacy") and once(wave(g), "impulse_legacy"):
		g.lord.run_impulse_count = mini(2, maxi(int(g.lord.get("run_impulse_count", 0)), int(actor.run_impulse_count)))
		g.lord.run_impulse_bonus = 0.15 if has(g, "ritual_enhanced_impulse") else 0.1
		actor.run_impulse_count = 0


static func room_defeated(g, slot: int) -> void:
	if has(g, "shared_oath_of_the_fallen") and once(room(g, slot), "oath"):
		var global: Dictionary = wave(g)
		if int(global.get("oath_granted", 0)) < 3:
			global.oath_granted = int(global.get("oath_granted", 0)) + 1
			global.oath = int(global.get("oath", 0)) + 1


static func voluntary_retreat(g, active: Array[Dictionary]) -> void:
	if not has(g, "creatures_hunting_instinct"):
		return
	for actor in active:
		if str(actor.actor_id) == "lord":
			continue
		var state: Dictionary = room(g, int(actor.source_slot))
		if once(state, "hunt_used"):
			state.hunt = 1
			mark(actor, "creatures_hunting_instinct", 1)


static func trap_bonus(g, slot: int, target: Dictionary, extra: float = 0.0) -> float:
	var state: Dictionary = room(g, slot)
	var bonus: float = extra
	var previous: int = g._previous_route_slot(slot)
	if has(g, "traps_cascade") and previous >= 0 and previous < g.rooms.size() and previous / 5 == slot / 5 and not g.rooms[previous].is_empty() and bool(room(g, previous).get("direct_damage", false)) and str(g.room_stats(previous).kind) != "monster" and once(state, "cascade"):
		bonus += value(g, "traps_cascade", "first_direct_hit_damage_bonus")
	if has(g, "traps_finishing_mechanisms") and int(target.hp) * 10 < int(target.max_hp) * 3 and once(state, "finishing"):
		bonus += value(g, "traps_finishing_mechanisms", "hit_damage_bonus")
	return bonus


static func trap_after_hit(g, slot: int, stats: Dictionary, target: Dictionary, actual: int, killed: bool) -> void:
	if actual <= 0:
		return
	var state: Dictionary = room(g, slot)
	state.direct_damage = true
	if killed:
		g.record_direct_trap_kill()
	elif str(stats.id) in ["spikes", "blade_floor"] and has(g, "shared_poisoned_edges") and once(state, "poisoned_edges"):
		g._apply_hero_poison(target, float(actual) * value(g, "shared_poisoned_edges", "poison_damage_per_tick_fraction_of_actual_direct_damage"), g._scaled_poison_duration(2), g._battle_source(slot))


static func healing_factor(g, hero: Dictionary, amount: int) -> float:
	var factor: float = float(hero.get("poison_heal_factor", 1.0)) if int(hero.poison_ticks) > 0 else 1.0
	var missing: int = int(hero.max_hp) - int(hero.hp)
	var ordinary_gain: int = mini(missing, maxi(1, floori(amount * factor)))
	var bitter_gain: int = mini(missing, maxi(1, floori(amount * 0.8)))
	if int(hero.poison_ticks) > 0 and ordinary_gain > bitter_gain and factor > 0.8 and has(g, "poison_bitter_medicine"):
		var global: Dictionary = wave(g)
		var key: String = "bitter:" + str(hero.instance_id)
		if once(global, key):
			g.consume_poison_tick(hero, false)
			return 0.8
	return factor


static func transfer_neighbor(g, slot: int, skill_id: String) -> int:
	var next: int = g.next_route_slot(slot)
	if next >= g.rooms.size() or next / 5 != slot / 5:
		return -1
	if g.rooms[next].is_empty() and has(g, skill_id):
		next = g.next_route_slot(next)
	if next >= g.rooms.size() or next / 5 != slot / 5 or g.rooms[next].is_empty() or str(g.room_stats(next).kind) != "monster":
		return -1
	return next


static func publish(g, actor: Dictionary) -> void:
	var state: Dictionary = room(g, int(actor.source_slot))
	var global: Dictionary = wave(g)
	var status: Dictionary = {}
	if str(actor.actor_id) == "lord":
		for id in ["lord_last_word", "lord_counterstrike", "lord_throne_wrath", "lord_fortified_throne", "shared_oath_of_the_fallen"]:
			if not has(g, id):
				continue
			match id:
				"lord_last_word": status[id] = int(bool(global.get("last_word_ready", false)))
				"lord_counterstrike": status[id] = int(bool(global.get("counter_ready", false)))
				"lord_throne_wrath": status[id] = int(not bool(global.get("wrath", false)))
				"lord_fortified_throne": status[id] = int(not bool(global.get("fortified", false)))
				"shared_oath_of_the_fallen": status[id] = int(global.get("oath", 0))
	else:
		var keys: Dictionary = {"creatures_stubbornness": "stubborn", "creatures_discipline": "discipline", "creatures_hunting_instinct": "hunt", "creatures_united_pack": "pack"}
		for id in keys:
			if has(g, str(id)):
				status[id] = int(state.get(keys[id], 0))
		if has(g, "creatures_battle_rhythm"):
			status.creatures_battle_rhythm = 4 - int(state.get("rhythm", 0)) % 4
		if has(g, "creatures_tough_hide"):
			status.creatures_tough_hide = int(not bool(state.get("hide", false)))
		if has(g, "creatures_defiance"):
			status.creatures_defiance = int(bool(state.get("defiance", false)))
		if extra_actor(actor) and has(g, "creatures_hardy_brood"):
			status.creatures_hardy_brood = 1
	if has(g, "ritual_impulse"):
		status.ritual_impulse = int(actor.get("run_impulse_count", 0))
	if has(g, "ritual_barrier"):
		status.ritual_barrier = int(bool(actor.get("run_barrier", false)))
	if has(g, "ritual_cover"):
		status.ritual_cover = int(actor.get("run_cover_shield", 0))
	var banner: Dictionary = state.get("incoming_banner", {})
	if not banner.is_empty():
		var remaining: int = int(room(g, int(banner.source_slot)).get("banner_remaining", 0))
		actor.effects.banner = {"target": str(banner.target), "hits": remaining}
		status.goblins_directed_orders = remaining
	actor.effects.run_skills = status


static func expire_after_exchange(g) -> void:
	for state in g.run_skill_runtime.get("combat_rooms", {}).values():
		if bool(state.get("defiance_expire", false)):
			state.defiance = false
			state.erase("defiance_expire")

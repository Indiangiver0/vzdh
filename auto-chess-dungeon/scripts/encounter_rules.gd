extends RefCounted
## Finite encounters. Only simulation steps advance timers (one step = 0.5 s).
## No Node, scene, timer, wall clock, or global random state is used here.

const Damage = preload("res://scripts/damage_rules.gd")
const HeroRules = preload("res://scripts/hero_rules.gd")
const Skills = preload("res://scripts/run_skill_effects.gd")
var actors: Array[Dictionary] = []
var owners: Dictionary = {}
var consumed: Dictionary = {}
var disarmed: Dictionary = {}
var spent: Dictionary = {}
# Physical trap visits are distinct from wave-wide support and skill charges.
var trap_visits: Dictionary = {}
var encounter_open: bool = false
var last_entry_visit: int = -1
# Relocated vampires keep the same actor, source-room owner, and wave charges.
var recovering: Dictionary = {}
var pending: Array[Dictionary] = []
var throne_guards: Array[Dictionary] = []
var spirit_cover: Dictionary = {}
var effects: Dictionary = {}
var rotation: Dictionary = {}
var serial: int = 0
var trap_sequence: Dictionary = {}
var processing_deaths: bool = false


func start_wave(g) -> void:
	actors.clear()
	owners.clear()
	consumed.clear()
	disarmed.clear()
	spent.clear()
	trap_visits.clear()
	encounter_open = false
	last_entry_visit = -1
	recovering.clear()
	pending.clear()
	throne_guards.clear()
	spirit_cover.clear()
	effects.clear()
	rotation.clear()
	trap_sequence.clear()
	serial = 0
	var reserve_slot: int = g.throne_guard_room_slot()
	for hero in g.heroes:
		hero.effects = {}
		hero.equipment_state = {}
		hero.equipment_disabled_slots = []
		hero.weapon_swap_battles = 0
		hero.weapon_swapped = false
		hero.cocoon_ticks = 0
	for slot in range(g.rooms.size()):
		if g.rooms[slot].is_empty():
			continue
		var stats: Dictionary = g.room_stats(slot)
		if str(stats.get("evolution_path", "")) == "wraith_twilight_hall":
			var destination: int = next_neighbor(g, slot)
			if int(stats.evolution_stage) >= 15 and str(g.rooms[slot].get("spirit_direction", "next")) == "previous":
				destination = g.layout_previous_neighbor(slot)
			if same_floor(g, slot, destination) and not g.rooms[destination].is_empty() and str(g.room_stats(destination).kind) == "monster" and g.room_stats(destination).tags.has("corporeal"):
				spirit_cover[destination] = slot
		if str(stats.get("evolution_path", "")) == "wraith_throne_guardian":
			consumed[slot] = true
			if slot != reserve_slot:
				continue
			var guard: Dictionary = make_actor(g, slot, stats, "throne_guard")
			guard.hp = ceili(guard.hp * float(params(guard).get("reserve_hp_factor", 1.0)))
			guard.max_hp = guard.hp
			guard.damage = 0
			throne_guards.append(guard)
	g.defenders = actors


func next_wave(g) -> void:
	for room in g.rooms:
		if room.is_empty() or str(room.get("evolution_path", "")) != "ballista_reserve_magazine":
			continue
		var memory: Dictionary = room.get("evolution_memory", {})
		var stage: int = int(room.get("evolution_stage", 2))
		memory.ammo = mini(1 + tier(stage) + int(Skills.value(g, "traps_expanded_arsenal", "extra_ammunition_capacity")), int(memory.get("ammo", 0)) + 1)
		room.evolution_memory = memory


func tier(stage: int) -> int:
	return 3 if stage >= 15 else (2 if stage >= 5 else 1)


func params(actor: Dictionary) -> Dictionary:
	return actor.get("evolution_params", {})


func same_floor(g, a: int, b: int) -> bool:
	# Depth layers retain their biome/once-per-layer rules; array positions do not.
	return a >= 0 and b >= 0 and a < g.rooms.size() and b < g.rooms.size() and g.layout_effect_scope(a) == g.layout_effect_scope(b)


func next_neighbor(g, slot: int) -> int:
	var n: int = g.layout_next_neighbor(slot)
	return n if same_floor(g, slot, n) else -1


func path_at(g, slot: int) -> String:
	return str(g.rooms[slot].get("evolution_path", "")) if slot >= 0 and slot < g.rooms.size() and not g.rooms[slot].is_empty() else ""


func living_actors() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for actor in actors:
		if int(actor.hp) > 0 and int(actor.get("delay", 0)) <= 0:
			result.append(actor)
	return result


func living_hero(g, uid: String) -> Dictionary:
	for hero in g.heroes:
		if str(hero.instance_id) == uid and int(hero.hp) > 0:
			return hero
	return {}


func event(g, kind: String, actor: String, target: String, amount: int, message: String, slot: int = -1) -> void:
	g._action(kind, actor, target, amount, message)
	g.last_action.source_slot = slot
	g._log(message)


func make_actor(g, slot: int, stats: Dictionary, form: String = "base", scale: float = 1.0) -> Dictionary:
	serial += 1
	var actor: Dictionary = stats.duplicate(true)
	actor.source_slot = slot
	actor.source_room_uid = g._battle_source(slot)
	actor.actor_id = "lord" if slot == g.rooms.size() else ("room_%d" % slot if form == "base" else "room_%d:%s:%d" % [slot, form, serial])
	actor.phase_id = form
	actor.path_id = str(stats.get("evolution_path", ""))
	actor.stage = int(stats.get("evolution_stage", 0))
	actor.hp = maxi(1, ceili(float(stats.hp) * scale))
	actor.max_hp = actor.hp
	actor.damage = maxi(1, ceili(float(stats.damage) * scale))
	actor.tree_base_damage = float(stats.get("tree_base_damage", stats.damage)) * scale
	actor.tree_base_hp = float(stats.get("tree_base_hp", stats.hp)) * scale
	actor.effects = {}
	actor.charges = {}
	actor.age = 0
	actor.finalized = false
	if spirit_cover.has(slot) and form == "base":
		var tags: PackedStringArray = actor.get("tags", PackedStringArray())
		tags.erase("corporeal")
		if not tags.has("spirit"):
			tags.append("spirit")
		actor.tags = tags
		actor.effects.spirit = true
	if slot == g.rooms.size():
		actor = g.lord
		actor.source_slot = slot
		actor.source_room_uid = "lord"
		actor.actor_id = "lord"
		actor.phase_id = "base"
		actor.path_id = ""
		actor.stage = 0
		actor.effects = {}
		actor.charges = {}
		actor.age = 0
		actor.finalized = false
	elif not owners.has(slot):
		owners[slot] = {"stats": stats.duplicate(true), "rewarded": false, "engaged": false, "queues": [], "flags": {}}
	Skills.actor_spawn(g, actor)
	return actor


func add_actor(g, actor: Dictionary) -> void:
	actors.append(actor)
	if owners.has(int(actor.source_slot)):
		owners[int(actor.source_slot)].engaged = true
	g.defenders = actors
	Skills.publish(g, actor)
	event(g, "spawn", str(actor.actor_id), "", 0, "%s вступает в бой" % actor.name, int(actor.source_slot))


func sync_primary(g) -> void:
	var alive: Array[Dictionary] = living_actors()
	if alive.is_empty():
		for actor in actors:
			if int(actor.hp) > 0:
				alive.append(actor)
	if not alive.is_empty():
		g.defender = alive[0]
		# Publication follows the encounter owner without reordering attacks.
		for actor in alive:
			var owns_encounter: bool = str(actor.get("actor_id", "")) == "lord" if g.current_slot == g.rooms.size() else int(actor.source_slot) == g.current_slot and str(actor.get("phase_id", "")) != "appendage"
			if owns_encounter:
				g.defender = actor
				break
	elif g.labyrinth_enabled:
		g.defender = {}
	g.defenders = actors
	for actor in actors:
		Skills.publish(g, actor)
		var slot: int = int(actor.source_slot)
		# A living chamber has one vulnerable heart; its untargetable mouths
		# keep their own actor state without replacing the room's displayed HP.
		if slot >= 0 and slot < g.rooms.size() and not g.rooms[slot].is_empty() and str(actor.get("phase_id", "")) != "appendage":
			g.rooms[slot].current_hp = int(actor.hp)


func enter(g) -> void:
	if g.labyrinth_enabled:
		# A route step may visit an empty place, treasury, or defeated room.
		# It never skips physical visits or recreates an unfinished encounter.
		if not g._waiting_for_entry:
			return
		if encounter_open:
			end_combat(g)
		if not g._advance_labyrinth_route():
			return
		if last_entry_visit == int(g.visit_id):
			return
		last_entry_visit = int(g.visit_id)
		if g.current_slot < g.rooms.size() and consumed.has(g.current_slot) and not has_coffin_at(g.current_place):
			g._waiting_for_entry = true
			return
	else:
		end_combat(g)
		var slot: int = g.next_route_slot(g.current_slot)
		while slot < g.rooms.size() and (g.rooms[slot].is_empty() or consumed.has(slot)):
			slot = g.next_route_slot(slot)
		g.current_slot = mini(slot, g.rooms.size())
	encounter_open = true
	g.combat_tick = 0
	g.rage = 0
	actors.clear()
	trap_sequence.clear()
	effects.clear()
	rotation = {"used": false, "retreat": "", "front": ""}
	for hero in g.heroes:
		hero.effects = {}
		hero.cocoon_ticks = 0
		hero.equipment_disabled_slots = []
		var state: Dictionary = hero.get("equipment_state", {})
		for key in state.keys():
			if not str(key).begins_with("wave:"):
				state.erase(key)
		hero.equipment_state = state
	if g.current_slot == g.rooms.size():
		g._reorder_party("monster")
		# Keep the established guard/Lord order; reinforcements join behind them.
		for guard in throne_guards:
			add_actor(g, guard)
		add_actor(g, make_actor(g, g.rooms.size(), g.lord))
		join_ready_vampires(g)
		g._battle_visit("lord")
		begin_combat(g)
		return
	var has_room: bool = not g.rooms[g.current_slot].is_empty() and not consumed.has(g.current_slot)
	var stats: Dictionary = g.room_stats(g.current_slot) if has_room else {}
	if has_room:
		g.rooms[g.current_slot].status = "active"
		g._battle_visit(g._battle_source())
		g._reorder_party(str(stats.kind))
	if has_room and str(stats.kind) == "monster":
		add_actor(g, make_actor(g, g.current_slot, stats))
		var gallery: Dictionary = take_pending("gallery", g.current_slot)
		if not gallery.is_empty() and not consumed.has(int(gallery.second)) and int(gallery.second) != g.current_slot:
			var second: int = int(gallery.second)
			var ally: Dictionary = make_actor(g, second, g.room_stats(second))
			ally.delay = int(gallery.get("delay", 0))
			add_actor(g, ally)
			consumed[second] = true
			g.rooms[second].status = "active"
			g._battle_visit(g._battle_source(second))
		catch_coffins(g)
		join_ready_vampires(g)
		begin_combat(g)
	elif has_room:
		catch_coffins(g)
		var disabled: bool = disarm(g, g.current_slot)
		trigger_trap(g, g.current_slot, stats, disabled)
		if not trap_sequence.is_empty():
			g._waiting_for_entry = false
			return
		finish_trap(g)
	else:
		# A coffin can occupy a physically empty or already defeated room.
		catch_coffins(g)
		if not living_actors().is_empty():
			g._reorder_party("monster")
			join_ready_vampires(g)
			begin_combat(g)
		else:
			g._waiting_for_entry = true


func finish_trap(g) -> void:
	process_hero_deaths(g)
	if not g._living().is_empty():
		g.tick += 1
		g._apply_poison()
		process_hero_deaths(g)
	if g._living().is_empty():
		g._mark_room_held()
		g._finish_wave()
	else:
		complete_trap_visit(g)


func complete_trap_visit(g) -> void:
	g.rooms[g.current_slot].status = "cleared"
	if not living_actors().is_empty():
		# The trap resolves first; an intercepted coffin then holds the party.
		g.combat_tick = 0
		g.rage = 0
		g._reorder_party("monster")
		join_ready_vampires(g)
		begin_combat(g)
	else:
		g._waiting_for_entry = true


func take_pending(kind: String, slot: int) -> Dictionary:
	for index in range(pending.size()):
		if str(pending[index].kind) == kind and int(pending[index].get("slot", slot)) == slot:
			var result: Dictionary = pending[index]
			pending.remove_at(index)
			return result
	return {}


func disarm(g, slot: int, preferred_hero: Dictionary = {}) -> bool:
	if disarmed.has(slot):
		return bool(disarmed[slot])
	# Creature explosives keep their existing counterplay; the new roll belongs
	# to actual traps. The tutorial also keeps its original weakening rules.
	if not g.labyrinth_enabled or str(g.room_stats(slot).kind) == "monster":
		var weakened: bool = g._spend_disarm()
		disarmed[slot] = weakened
		return weakened
	var scout: Dictionary = preferred_hero
	if scout.is_empty():
		for hero in g._living():
			if str(hero.id) == "rogue" and int(hero.get("disarm_charges", 0)) > 0:
				scout = hero
				break
	# No available tool is not a failed roll and does not consume the attempt.
	if scout.is_empty() or not g._spend_disarm(scout):
		return false
	var result: bool = g.labyrinth_disarm_roll()
	disarmed[slot] = result
	var message: String = "Следопыт обезвредил ловушку до конца волны." if result else "Следопыт не смог обезвредить ловушку: повторной попытки не будет."
	event(g, "disarm", str(scout.instance_id), "room_%d" % slot, 1, message, slot)
	g.last_action.meta = {"success": result, "tools_spent": 1, "room_instance_id": int(g.rooms[slot].get("instance_id", slot)), "wave_id": g.wave, "visit_id": g.visit_id}
	return result


func hero_damage(g, hero: Dictionary, amount: int, source: String, allow_chain: bool = true) -> int:
	return int(hero_damage_breakdown(g, hero, amount, source, allow_chain).actual)


func hero_damage_breakdown(g, hero: Dictionary, amount: int, source: String, allow_chain: bool = true) -> Dictionary:
	var result: Dictionary = {"actual": 0, "primary_amount": 0, "redirected": 0, "overkill": 0}
	if amount <= 0 or int(hero.hp) <= 0:
		return result
	var chain: Dictionary = effects.get("chain", {})
	if allow_chain and not chain.is_empty() and int(chain.get("charges", 0)) > 0 and chain.ids.has(str(hero.instance_id)):
		for other_id in chain.ids:
			var other: Dictionary = living_hero(g, str(other_id))
			if other.is_empty() or str(other_id) == str(hero.instance_id):
				continue
			var share: int = floori(float(amount) * float(chain.fraction))
			chain.charges = int(chain.charges) - 1
			g._inflict_hero_damage(other, share, source)
			amount -= share
			result.redirected = share
			event(g, "chain", str(hero.instance_id), str(other_id), share, "Цепь передаёт часть удара")
			break
	result.primary_amount = amount
	result.actual = g._inflict_hero_damage(hero, amount, source)
	# Only the damage left on the primary target can overflow. A redirected
	# share has already spent that part of the original hit's damage budget.
	result.overkill = maxi(0, amount - int(result.actual))
	if int(hero.hp) <= 0:
		clear_ended_duels(g)
	return result


func poison(g, hero: Dictionary, damage: float, duration: int, source: String, extra_bonus: float = 0.0) -> void:
	g._apply_hero_poison(hero, maxf(0.0, damage), g._scaled_poison_duration(maxi(1, duration)), source, extra_bonus)


func has_coffin_at(place_id: int) -> bool:
	for record in recovering.values():
		if int(record.place_id) == place_id and int(record.actor.hp) > 0:
			return true
	return false


func recovery_snapshot() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for record in recovering.values():
		var actor: Dictionary = record.actor
		if int(actor.hp) <= 0:
			continue
		result.append({"actor_id": str(actor.actor_id), "source_slot": int(actor.source_slot), "place_id": int(record.place_id), "hp": int(actor.hp), "max_hp": int(actor.max_hp), "remaining_steps": int(record.remaining_steps), "ready": bool(record.ready), "in_combat": bool(record.in_combat)})
	return result


func advance_recovery(g) -> void:
	# Called exactly once at the beginning of a model raid step, never by UI/camp.
	if not g.labyrinth_enabled or g.phase != "raid":
		return
	for identity in recovering.keys():
		var record: Dictionary = recovering[identity]
		var actor: Dictionary = record.actor
		if int(actor.hp) <= 0 or bool(record.ready):
			continue
		record.remaining_steps = maxi(0, int(record.remaining_steps) - 1)
		actor.effects.ritual_ticks = int(record.remaining_steps)
		if int(record.remaining_steps) > 0:
			continue
		wake_vampire(g, actor)
		record.ready = true
		event(g, "coffin_ready", str(actor.actor_id), "place_%d" % int(record.place_id), int(actor.hp) - int(actor.effects.body_hp), "Вампир завершает восстановление в гробу", int(actor.source_slot))
		g.last_action.meta = {"actor_id": str(actor.actor_id), "source_slot": int(actor.source_slot), "place_id": int(record.place_id), "remaining_steps": 0, "in_combat": bool(record.in_combat), "healed": int(actor.hp) - int(actor.effects.body_hp)}
		if bool(record.in_combat):
			# An intercepted coffin wakes in its current encounter, without a copy.
			recovering.erase(identity)


func wake_vampire(g, actor: Dictionary) -> void:
	actor.effects.erase("release_coffin")
	actor.phase_id = "base"
	actor.max_hp = int(actor.effects.body_max)
	actor.hp = mini(int(actor.max_hp), int(actor.effects.body_hp) + Skills.heal_amount(g, actor.max_hp * float(params(actor).get("heal_fraction", 0.35))))
	actor.charges.empowered_bite = tier(int(actor.stage)) == 3


func retreat_vampire(g, actor: Dictionary) -> bool:
	if not g.labyrinth_enabled:
		return false
	var destination: int = g.vampire_retreat_destination(g.current_place, int(actor.source_slot))
	if destination < 0:
		return false
	var slot: int = int(actor.source_slot)
	actor.display_slot = destination
	actor.relocated = true
	recovering[str(actor.actor_id)] = {"actor": actor, "place_id": destination, "remaining_steps": int(actor.effects.ritual_ticks), "ready": false, "in_combat": false, "origin_visit_id": int(g.visit_id), "combat_closed": false}
	actors.erase(actor)
	consumed[slot] = true
	owners[slot].flags.relocated = true
	g.rooms[slot].status = "retreated"
	event(g, "bat_retreat", str(actor.actor_id), "place_%d" % destination, 0, "Вампир улетает в гроб в другой комнате", slot)
	g.last_action.meta = {"actor_id": str(actor.actor_id), "source_slot": slot, "from_place": int(g.current_place), "to_place": destination, "remaining_steps": int(actor.effects.ritual_ticks)}
	return true


func catch_coffins(g) -> void:
	if not g.labyrinth_enabled:
		return
	for identity in recovering.keys():
		var record: Dictionary = recovering[identity]
		var actor: Dictionary = record.actor
		if int(record.place_id) != int(g.current_place) or int(actor.hp) <= 0 or bool(record.in_combat):
			continue
		record.in_combat = true
		actor.display_slot = int(g.current_place)
		actors.append(actor)
		g._battle_visit(str(actor.source_room_uid))
		if bool(record.ready):
			recovering.erase(identity)
			event(g, "reinforcement", str(actor.actor_id), "place_%d" % int(g.current_place), int(actor.hp), "Восстановившийся вампир встречает отряд у своего гроба", int(actor.source_slot))
			g.last_action.meta = {"actor_id": str(actor.actor_id), "source_slot": int(actor.source_slot), "from_place": int(record.place_id), "to_place": int(g.current_place), "intercepted": true}
		g.defenders = actors


func join_ready_vampires(g) -> void:
	if not g.labyrinth_enabled:
		return
	for identity in recovering.keys():
		var record: Dictionary = recovering[identity]
		var actor: Dictionary = record.actor
		if not bool(record.ready) or bool(record.in_combat) or int(actor.hp) <= 0:
			continue
		var previous: int = int(record.place_id)
		recovering.erase(identity)
		actor.display_slot = int(g.current_place)
		actors.append(actor)
		g._battle_visit(str(actor.source_room_uid))
		event(g, "reinforcement", str(actor.actor_id), "place_%d" % int(g.current_place), int(actor.hp), "Восстановившийся вампир вступает в следующий бой", int(actor.source_slot))
		g.last_action.meta = {"actor_id": str(actor.actor_id), "source_slot": int(actor.source_slot), "from_place": previous, "to_place": int(g.current_place)}
	g.defenders = actors


func begin_combat(g) -> void:
	sync_primary(g)
	g._waiting_for_entry = false
	g._begin_combat_effects()
	for actor in actors.duplicate():
		if not bool(actor.get("relocated", false)):
			setup_actor(g, actor)
	for index in range(pending.size() - 1, -1, -1):
		var p: Dictionary = pending[index]
		if int(p.get("slot", g.current_slot)) != g.current_slot:
			continue
		var kind: String = str(p.kind)
		if kind == "fog":
			effects.fog = p.duplicate(true)
			p.battles = int(p.battles) - 1
			if int(p.battles) > 0:
				continue
		elif kind in ["chain", "mass", "funeral", "partitions"]:
			effects[kind] = p.duplicate(true)
		elif kind == "shield":
			g.defender.shield = int(g.defender.get("shield", 0)) + int(p.amount)
		elif kind == "spirit":
			var tags: PackedStringArray = g.defender.tags
			tags.erase("corporeal")
			if not tags.has("spirit"):
				tags.append("spirit")
			g.defender.tags = tags
			g.defender.effects.spirit = true
			g.defender.armor = maxi(0, int(g.defender.armor) - int(g.defender.get("tree_bone_armor", 0)))
			g.defender.tree_bone_armor = 0
		elif kind == "banner":
			g.defender.effects.banner = p.duplicate(true)
		elif kind == "rust_window":
			var victim: Dictionary = living_hero(g, str(p.target))
			if not victim.is_empty():
				victim.rust_ticks = int(p.ticks)
				victim.rust_amount = int(p.amount)
		elif kind == "null":
			var max_effects: int = int(p.get("count", 99))
			for hero in g.heroes:
				var cleared: int = 0
				for key in ["poison_ticks", "shackles_ticks", "silence_ticks", "rust_ticks", "cocoon_ticks"]:
					if cleared >= max_effects or int(hero.get(key, 0)) <= 0:
						continue
					if key == "poison_ticks":
						g.clear_poison(hero)
					hero[key] = 0
					cleared += 1
			for actor in actors:
				var cleared: int = 0
				for key in ["shield", "ability_attacks", "revenant_damage_bonus", "revive_mark"]:
					if cleared < max_effects and float(actor.get(key, 0)) > 0:
						actor[key] = 0
						cleared += 1
			effects.aura_suppressed = int(p.ticks)
		elif kind == "banshee_echo":
			for hero in g._living():
				hero_damage(g, hero, int(p.damage), str(p.source))
			event(g, "echo", str(p.source), "", int(p.damage), "Отзвук баньши проходит по залу")
		pending.remove_at(index)
	for actor in actors:
		if not bool(actor.get("relocated", false)):
			support_from_future(g, actor)
	sync_primary(g)
	if not g._living().is_empty():
		g.active_target_id = str(g._living()[0].instance_id)
	event(g, "enter", str(g.defender.actor_id), g.active_target_id, 0, "Бой: %s" % g.defender.name, g.current_slot)


func setup_actor(g, actor: Dictionary) -> void:
	var path: String = str(actor.path_id)
	var t: int = tier(int(actor.stage))
	var slot: int = int(actor.source_slot)
	if path == "guardian_parry":
		actor.charges.parry = int(params(actor).get("parry_charges", t))
	elif path == "mimic_false_treasury":
		actor.charges.decoys = 0 if has_class(g, "rogue") else 1 + int(Skills.value(g, "shared_spare_decoy", "extra_initial_decoys"))
	elif path == "mimic_living_chamber":
		for reserved_slot in g.reserved_room_slots():
			if int(g.reserved_room_slots()[reserved_slot]) != slot:
				continue
			var mouth: Dictionary = make_actor(g, slot, actor, "appendage", float(params(actor).get("extension_damage_factor", 0.3)))
			mouth.path_id = ""
			mouth.name = "Пасть мимика"
			mouth.display_slot = int(reserved_slot)
			mouth.untargetable = true
			add_actor(g, mouth)
	elif path == "vampire_sire":
		var memory: Dictionary = g.rooms[slot].get("evolution_memory", {})
		if memory.has("thrall") and int(memory.get("thrall_wave", 0)) == g.wave:
			var servant: Dictionary = make_actor(g, slot, actor, "servant", float(params(actor).get("servant_hp_factor", 0.3)))
			servant.tree_base_damage = Skills.base_damage(actor) * float(params(actor).get("servant_damage_factor", 0.3))
			servant.damage = maxi(1, ceili(Skills.damage(servant)))
			servant.class_skill = bool(params(actor).get("class_skill", false))
			servant.path_id = ""
			servant.servant_class = str(memory.thrall)
			servant.name = "Обращённый %s" % str(memory.thrall)
			add_actor(g, servant)
			memory.erase("thrall")
			g.rooms[slot].evolution_memory = memory
	elif path == "mimic_cursed_gift":
		give_cup(g, actor)
	if path == "duelist" and not g._living().is_empty():
		actor.effects.duel = str(g._living()[0].instance_id)
		actor.effects.duel_ticks = 2 if t == 1 else 3


func has_class(g, id: String) -> bool:
	for hero in g._living():
		if str(hero.id) == id:
			return true
	return false


func trigger_trap(g, slot: int, stats: Dictionary, disabled: bool, physical_visit: bool = true) -> void:
	if g.labyrinth_enabled:
		if physical_visit:
			if int(trap_visits.get(slot, -1)) == int(g.visit_id):
				return
			trap_visits[slot] = int(g.visit_id)
			var state: Dictionary = Skills.room(g, slot)
			state.shot_ids = []
			state.shot_visit_id = int(g.visit_id)
		if disabled:
			event(g, "trap_disabled", "room_%d" % slot, "", 0, "Обезвреженная ловушка пропускает отряд.", slot)
			return
	elif spent.has(slot):
		return
	spent[slot] = true
	var path: String = str(stats.get("evolution_path", ""))
	if path.is_empty():
		g.defender = stats
		trigger_plain_trap(g, slot, stats, disabled)
		return
	var t: int = tier(int(stats.get("evolution_stage", 2)))
	var p: Dictionary = params(stats)
	var power: float = 0.4 if disabled else 1.0
	var source: String = g._battle_source(slot)
	var party: Array[Dictionary] = g._living()
	if party.is_empty():
		return
	var front: Dictionary = party[0]
	var before_hp: Dictionary = {}
	for hero in party:
		before_hp[str(hero.instance_id)] = int(hero.hp)
	var pending_start: int = pending.size()
	var n: int = next_neighbor(g, slot)
	var hit: float = Skills.base_damage(stats) * power
	var monster_next: bool = n >= 0 and not g.rooms[n].is_empty() and str(g.room_stats(n).kind) == "monster"
	match path:
		"spikes_armour_press":
			trap_hit(g, slot, stats, front, Skills.base_damage(stats) * float(p.get("base_damage_factor", 0.6)) + mini(int(p.get("bonus_cap", 18)), g.effective_hero_armor(front) * int(p.get("damage_per_armor", 3))), power)
		"spikes_collapsing_walkway":
			for hero in party.slice(1, mini(party.size(), int(p.get("rear_targets", 1)) + 1)):
				trap_hit(g, slot, stats, hero, Skills.base_damage(stats) * float(p.get("damage_factor", 0.9)), power)
		"spikes_blood_surge":
			trap_hit(g, slot, stats, front, Skills.base_damage(stats), power)
			if int(front.hp) <= 0:
				for hero in party.slice(1):
					trap_hit(g, slot, stats, hero, Skills.base_damage(stats) * float(p.get("surge_factor", 0.4)), power, Skills.value(g, "traps_runic_volley", "post_kill_volley_damage_bonus"))
		"poison_fog_crypt":
			var poison_ticks: int = int(p.get("poison_ticks", 3))
			pending.append({"kind": "fog", "damage": hit, "charges": 1 if disabled else int(p.get("pulses", 2)) + int(Skills.value(g, "poison_gas_reserve", "extra_cloud_pulses")), "battles": int(p.get("battles", 1)), "poison_ticks": poison_ticks, "source": source})
			for hero in party:
				poison(g, hero, hit, poison_ticks, source)
		"poison_spore_garden":
			front.spore = {"attacks": int(p.get("attacks_to_burst", 3)), "damage": hit, "duration": int(p.get("poison_ticks", 4)), "on_death": bool(p.get("death_burst", false)), "source": source}
		"poison_distiller":
			var reacted: int = 0
			var aura: float = g._poison_aura_multiplier()
			for hero in party:
				if int(hero.poison_ticks) <= 0 or reacted >= int(p.get("targets", 1)):
					continue
				var burst: float = minf(float(hero.poison_ticks) * float(hero.poison_damage), maxf(8.0, hit * 5.0))
				burst *= minf(1.0, float(p.get("remaining_poison_factor", 0.5)) + Skills.value(g, "poison_clean_distillation", "remaining_poison_conversion_addition")) * power
				hero_damage(g, hero, g._poison_hit(hero, burst, aura), source)
				g.clear_poison(hero)
				reacted += 1
		"shackles_shared_chain":
			if party.size() >= 2:
				var ids: Array[String] = [str(front.instance_id), str(party[-1].instance_id)]
				if t == 3 and party.size() >= 3:
					ids.append(str(party[1].instance_id))
				pending.append({"kind": "chain", "ids": ids, "charges": 1 if disabled else int(p.get("charges", 1)) + int(Skills.value(g, "traps_strong_links", "extra_damage_transfer_charges")), "fraction": 0.15 if disabled else float(p.get("share_fraction", 0.25)), "source": source})
		"shackles_prisoner_scales":
			if party.size() >= 2:
				var other: Dictionary = g._most_wounded(party)
				var healthiest: Dictionary = party[0]
				for hero in party:
					if float(hero.hp) / hero.max_hp > float(healthiest.hp) / healthiest.max_hp:
						healthiest = hero
				var total: int = int(healthiest.hp) + int(other.hp)
				var wanted: int = floori(float(total) * float(healthiest.max_hp) / float(int(healthiest.max_hp) + int(other.max_hp)))
				var transfer: int = maxi(0, int(healthiest.hp) - wanted)
				transfer = mini(int(other.max_hp) - int(other.hp), floori(transfer * power * float(p.get("equalize_fraction", 1.0))))
				healthiest.hp = int(healthiest.hp) - transfer
				other.hp = int(other.hp) + transfer
		"shackles_garrison_gallery":
			var second: int = next_neighbor(g, n) if n >= 0 else -1
			if monster_next and second >= 0 and second != slot and not consumed.has(n) and not consumed.has(second) and not g.rooms[second].is_empty() and str(g.room_stats(second).kind) == "monster" and path_at(g, second) != "wraith_throne_guardian":
				pending.append({"kind": "gallery", "slot": n, "second": second, "delay": int(p.get("join_delay_rounds", 0)) + (int(p.get("disarmed_extra_rounds", 2)) if disabled else 0)})
		"silence_black_mass":
			pending.append({"kind": "mass", "fraction": float(p.get("redirect_fraction", 0.5)) * (0.5 if disabled else 1.0), "source": source})
		"silence_null_bell":
			pending.append({"kind": "null", "ticks": int(p.get("aura_suppression_rounds", 1)), "count": 1 if disabled else int(p.get("effects_per_actor", 1)), "disarmed": disabled})
		"silence_funeral_peal":
			pending.append({"kind": "funeral", "ticks": 1 if disabled else int(p.get("silence_rounds", 1)), "source": source})
		"rust_fracture_window":
			var armored: Dictionary = most_armored(g, party)
			pending.append({"kind": "rust_window", "target": str(armored.instance_id), "amount": mini(g.effective_hero_armor(armored), 1 if disabled else int(p.get("armor_reduction", 1))), "ticks": 1 if disabled else int(p.get("duration_rounds", 3)), "source": source})
		"rust_shard_chamber":
			var metal: int = mini(int(p.get("damage_cap", 12)), g.effective_hero_armor(most_armored(g, party)) * int(p.get("damage_per_armor", 3)))
			for hero in party:
				trap_hit(g, slot, stats, hero, float(metal), power)
		"rust_reforging":
			n = Skills.transfer_neighbor(g, slot, "shared_runic_channel")
			if n >= 0:
				var armored: Dictionary = most_armored(g, party)
				var metal: int = mini(g.effective_hero_armor(armored), 1 if disabled else int(p.get("armor_reduction", 1)))
				pending.append({"kind": "rust_window", "slot": n, "target": str(armored.instance_id), "amount": metal, "ticks": 1000000, "source": source})
				pending.append({"kind": "shield", "slot": n, "amount": ceili(minf(float(p.get("shield_cap", 8)), metal * float(p.get("shield_per_armor", 8))) * (1.2 if Skills.has(g, "traps_dense_casting") else 1.0))})
		"ballista_clear_sight":
			trap_hit(g, slot, stats, party[-1], Skills.base_damage(stats) * float(p.get("shot_factor", 1.0)), power)
		"ballista_reserve_magazine":
			var memory: Dictionary = g.rooms[slot].get("evolution_memory", {})
			var ammunition: int = int(memory.get("ammo", 0))
			for hero in party:
				if ammunition <= 0:
					break
				var shot_ids: Array = Skills.room(g, slot).get("shot_ids", [])
				if shot_ids.has(str(hero.instance_id)):
					continue
				trap_hit(g, slot, stats, hero, Skills.base_damage(stats) * float(p.get("shot_factor", 0.8)), power)
				shot_ids.append(str(hero.instance_id))
				Skills.room(g, slot).shot_ids = shot_ids
				ammunition -= 1
			memory.ammo = ammunition
			g.rooms[slot].evolution_memory = memory
		"ballista_siege":
			for i in range(mini(party.size(), int(p.get("targets", 2)))):
				var falloff: float = minf(0.9, float(p.get("falloff", 0.6)) + Skills.value(g, "traps_heavy_tip", "piercing_damage_retention_addition"))
				trap_hit(g, slot, stats, party[i], Skills.base_damage(stats) * float(p.get("shot_factor", 0.8)) * pow(falloff, i), power)
		"blade_floor_blood_mill":
			trap_sequence = {"slot": slot, "remaining": 1 if disabled else int(p.get("sections", 2)), "damage": Skills.base_damage(stats) * float(p.get("section_damage_factor", 0.55)), "source": source, "section": 0, "power": power, "disabled": disabled, "stats": stats.duplicate(true)}
		"blade_floor_partition_corridor":
			if monster_next:
				pending.append({"kind": "partitions", "slot": n, "ticks": 1 if disabled else int(p.get("partition_rounds", 2)), "source": source})
		"blade_floor_corpse_reclaimer":
			pass
	apply_trap_echo(g, slot, stats, party, before_hp, pending_start, power)
	event(g, "trap", "room_%d" % slot, str(front.instance_id), ceili(hit), str(stats.name) + (" · механизм ослаблен" if disabled else ""), slot)


func apply_trap_echo(g, slot: int, stats: Dictionary, party: Array[Dictionary], before_hp: Dictionary, pending_start: int, power: float) -> void:
	var floor_index: int = g.layout_effect_scope(slot)
	if not g.selected_relics.has("trap_echo") or g._echo_floors.has(floor_index):
		return
	var path: String = str(stats.get("evolution_path", ""))
	# These effects have neither a damage pulse nor a finite control duration.
	# Repeating them would duplicate actors/rewards or change their HP budget.
	if path in ["shackles_shared_chain", "shackles_prisoner_scales", "shackles_garrison_gallery", "silence_black_mass", "rust_reforging", "blade_floor_corpse_reclaimer"]:
		return
	var activated: bool = false
	var source: String = g._battle_source(slot)
	var total: int = 0
	if str(stats.kind) == "poison":
		for hero in party:
			if int(hero.hp) > 0:
				var pulse: int = g._poison_hit(hero, Skills.base_damage(stats) * (1.0 + float(g.run_skill_modifiers().get("poison_damage", 0.0))) * power * 0.4, g._poison_aura_multiplier())
				total += hero_damage(g, hero, pulse, source)
		activated = true
	elif not trap_sequence.is_empty() and int(trap_sequence.slot) == slot:
		trap_sequence.damage = float(trap_sequence.damage) * 1.4
		activated = true
	else:
		for hero in party:
			var dealt: int = int(before_hp.get(str(hero.instance_id), int(hero.hp))) - int(hero.hp)
			if dealt > 0:
				activated = true
				var actual: int = hero_damage(g, hero, maxi(1, floori(float(dealt) * 0.4)), source)
				total += actual
				Skills.trap_after_hit(g, slot, stats, hero, actual, int(hero.hp) <= 0)
		for index in range(pending_start, pending.size()):
			if pending[index].has("ticks") and int(pending[index].ticks) < 6:
				pending[index].ticks = int(pending[index].ticks) + 1
				activated = true
	if activated:
		g._echo_floors.append(floor_index)
		event(g, "echo", "room_%d" % slot, "", total, "Эхо механизмов усиливает ловушку", slot)


func most_armored(g, party: Array[Dictionary]) -> Dictionary:
	var result: Dictionary = party[0]
	for hero in party:
		if g.effective_hero_armor(hero) > g.effective_hero_armor(result):
			result = hero
	return result


func step(g) -> void:
	g.tick += 1
	g.combat_tick += 1
	g.rage = 0 if g.combat_tick <= 40 else 1 + floori(float(g.combat_tick - 41) / 10.0)
	if not trap_sequence.is_empty():
		g._apply_poison()
		for hero in g._living():
			var acceleration: float = minf(0.15, float(trap_sequence.section) * 0.05) if Skills.has(g, "traps_flywheel_acceleration") and not bool(trap_sequence.disabled) else 0.0
			trap_hit(g, int(trap_sequence.slot), trap_sequence.stats, hero, float(trap_sequence.damage), float(trap_sequence.power), acceleration)
		if not bool(trap_sequence.disabled):
			trap_sequence.section = int(trap_sequence.section) + 1
		heal_phase(g)
		process_hero_deaths(g)
		trap_sequence.remaining = int(trap_sequence.remaining) - 1
		event(g, "trap", "room_%d" % g.current_slot, "", int(trap_sequence.damage), "Пила проходит через отряд", g.current_slot)
		if g._living().is_empty():
			g._mark_room_held()
			g._finish_wave()
		elif int(trap_sequence.remaining) <= 0:
			trap_sequence.clear()
			complete_trap_visit(g)
		return
	for actor in actors:
		if int(actor.get("delay", 0)) > 0:
			actor.delay = int(actor.delay) - 1
			if int(actor.delay) > 0:
				continue
		actor.age = int(actor.age) + 1
		g._battle_add(str(actor.source_room_uid), "ticks")
	var fog: Dictionary = effects.get("fog", {})
	if not fog.is_empty() and int(fog.charges) > 0 and g.combat_tick % 2 == 1:
		for hero in g._living():
			poison(g, hero, float(fog.damage), int(fog.get("poison_ticks", 3)), str(fog.source))
		fog.charges = int(fog.charges) - 1
	g._apply_poison()
	process_hero_deaths(g)
	if g._living().is_empty():
		g._mark_room_held()
		g._finish_wave()
		return
	var healed: Array[String] = heal_phase(g)
	var strikes: Array[Dictionary] = []
	var party: Array[Dictionary] = g._living()
	var available: Array[Dictionary] = living_actors()
	for hero in party:
		if healed.has(str(hero.instance_id)) or not can_act(hero):
			continue
		if g.combat_tick == 1 and bool(g.defender.get("cell_advantage", false)):
			g._battle_add(str(g.defender.get("cell_source", "")), "control_actions")
			continue
		if int(hero.get("skip_attack", 0)) > 0:
			hero.skip_attack = int(hero.skip_attack) - 1
			continue
		if int(hero.get("shackles_ticks", 0)) > 0 and g.combat_tick % 2 == 0:
			continue
		if available.is_empty():
			break
		if play_drum(g, hero, available):
			continue
		var target: Dictionary = select_hero_target(hero, available)
		if target.is_empty():
			continue
		var attack: Dictionary = plan_hero_attack(g, hero, target)
		if not attack.is_empty():
			strikes.append(attack)
		if hero.has("spore"):
			hero.spore.attacks = int(hero.spore.attacks) - 1
			if int(hero.spore.attacks) <= 0:
				burst_spore(g, hero)
		try_sapper_shot(g, hero)
	for actor in available:
		plan_actor(g, actor, strikes)
	# All direct hits are prepared before HP changes. No reward/level-up can
	# alter the second hit of the same simultaneous exchange.
	resolve_strikes(g, strikes)
	process_hero_deaths(g)
	resolve_actor_deaths(g)
	if int(g.lord.hp) <= 0:
		g._finish_defeat()
		return
	if g._living().is_empty():
		g._mark_room_held()
		g._finish_wave()
		return
	finish_owners(g)
	rotate_party(g)
	decay(g)
	sync_primary(g)
	var still_alive: bool = false
	for actor in actors:
		still_alive = still_alive or int(actor.hp) > 0
	if not still_alive:
		g._waiting_for_entry = true


func can_act(hero: Dictionary) -> bool:
	return int(hero.hp) > 0 and int(hero.get("cocoon_ticks", 0)) <= 0


func can_cast(hero: Dictionary) -> bool:
	return can_act(hero) and int(hero.get("silence_ticks", 0)) <= 0


func heal_phase(g) -> Array[String]:
	var acted: Array[String] = []
	var party: Array[Dictionary] = g._living()
	if party.is_empty():
		return acted
	for hero in party:
		if hero.has("cursed_cup") and can_act(hero) and not bool(hero.cursed_cup.get("used_this_battle", false)) and g.combat_tick >= 2:
			if int(hero.hp) < int(hero.max_hp):
				hero.cursed_cup.used_this_battle = true
				hero.cursed_cup.uses = int(hero.cursed_cup.uses) + 1
				heal(g, hero, hero, maxi(1, ceili(hero.max_hp * float(hero.cursed_cup.get("heal_fraction", 0.08)))))
				if int(hero.cursed_cup.uses) >= int(hero.cursed_cup.get("uses_to_bite", 3)):
					hero_damage(g, hero, maxi(1, ceili(hero.max_hp * float(hero.cursed_cup.get("bite_fraction", 0.3)) * (1.0 + Skills.value(g, "shared_sharp_teeth", "final_cup_bite_damage_bonus")))), str(hero.cursed_cup.source))
					event(g, "curse", "cup", str(hero.instance_id), 0, "Кубок раскрывает зубы")
					hero.erase("cursed_cup")
		if str(hero.id) != "priest" or g.combat_tick % 3 != 0 or not can_cast(hero):
			continue
		var target: Dictionary = hero if int(effects.get("partitions", {}).get("ticks", 0)) > 0 else g._most_wounded(party)
		if int(target.hp) < int(target.max_hp):
			heal(g, hero, target, 6 + 2 * (int(hero.level) - 1))
			acted.append(str(hero.instance_id))
	return acted


func heal(g, healer: Dictionary, target: Dictionary, amount: int) -> int:
	if int(target.hp) <= 0:
		return 0
	var value: int = maxi(1, floori(amount * Skills.healing_factor(g, target, amount)))
	var mass: Dictionary = effects.get("mass", {})
	if not mass.is_empty() and str(healer.id) == "priest":
		effects.erase("mass")
		var active: Array[Dictionary] = living_actors()
		if not active.is_empty():
			var stolen: int = floori(value * float(mass.fraction))
			var defender: Dictionary = active[0]
			var gain: int = mini(Skills.heal_amount(g, stolen, true), int(defender.max_hp) - int(defender.hp))
			defender.hp = int(defender.hp) + gain
			value -= stolen
			event(g, "steal_heal", str(healer.instance_id), str(defender.actor_id), gain, "Чёрная месса перехватывает лечение")
	value = mini(value, int(target.max_hp) - int(target.hp))
	target.hp = int(target.hp) + value
	event(g, "heal", str(healer.instance_id), str(target.instance_id), value, "%s: +%d HP" % [target.name, value])
	return value


func select_hero_target(hero: Dictionary, available: Array[Dictionary]) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for actor in available:
		if not bool(actor.get("untargetable", false)):
			candidates.append(actor)
	if candidates.is_empty():
		return {}
	# Class targeting is fixed and visible: front fighters attack the first
	# defender; ranged specialists can exploit the frailer second defender.
	if str(hero.id) in ["mage", "rogue"] and candidates.size() > 1:
		var result: Dictionary = candidates[0]
		for actor in candidates:
			if str(actor.phase_id) == "throne_guard":
				return actor
			if int(actor.hp) < int(result.hp):
				result = actor
		return result
	return candidates[0]


func duel_allows(g, hero: Dictionary, _target: Dictionary) -> bool:
	clear_ended_duels(g)
	for actor in living_actors():
		if int(actor.effects.get("duel_ticks", 0)) > 0 and str(actor.effects.get("duel", "")) != str(hero.instance_id):
			g._battle_add(str(actor.source_room_uid), "control_actions")
			return false
	return true


func plan_hero_attack(g, hero: Dictionary, target: Dictionary) -> Dictionary:
	var state: Dictionary = hero.get("equipment_state", {})
	var charged: bool = false
	if str(hero.id) == "mage":
		var clock: int = int(state.get("spell_clock", 0)) + 1
		state.spell_clock = clock
		if clock >= 3:
			if can_cast(hero):
				charged = true
				state.spell_clock = 0
			elif HeroRules.item_active(hero, "item_memory_staff") and not bool(state.get("memory_used", false)):
				state.memory_used = true
				state.stored_spell = true
				state.spell_clock = 0
			else:
				state.spell_clock = 0
		if bool(state.get("stored_spell", false)) and can_cast(hero) and HeroRules.item_active(hero, "item_memory_staff"):
			charged = true
			state.stored_spell = false
			state.spell_clock = 0
		if not HeroRules.item_active(hero, "item_memory_staff"):
			state.stored_spell = false
	hero.equipment_state = state
	# Backline mages keep their charge clock during a duel; only a charged
	# spell may act outside the two duel participants.
	if not charged and not duel_allows(g, hero, target):
		return {}
	var raw: float = float(hero.damage)
	var kind: String = "magic" if str(hero.id) == "mage" and can_cast(hero) else "physical"
	if charged:
		raw *= 1.5
		var prep: Dictionary = target.effects.get("preparing", {})
		if str(prep.get("kind", "")) in ["banshee", "hypnosis"]:
			target.effects.erase("preparing")
			target.charges.interrupted = true
			event(g, "interrupt", str(hero.instance_id), str(target.actor_id), 0, "Заклинание срывает подготовку")
	if str(hero.id) == "barbarian" and int(hero.hp) * 5 <= int(hero.max_hp) * 2:
		raw *= 1.25
	if bool(hero.get("weapon_swapped", false)) and not charged:
		raw *= 0.75 if Skills.has(g, "shared_convincing_counterfeit") else 0.8
	if not charged and bool(hero.get("run_heavy_breathing", false)):
		raw *= 0.9
	if int(hero.effects.get("web_ticks", 0)) > 0:
		raw *= 0.8
	if int(effects.get("aura_suppressed", 0)) <= 0:
		for bard in g._living():
			if str(bard.id) == "bard" and can_cast(bard) and (int(effects.get("partitions", {}).get("ticks", 0)) <= 0 or bard == hero):
				raw *= 1.15
				break
	var tags: PackedStringArray = target.get("tags", PackedStringArray())
	if tags.has("corporeal"):
		if str(hero.id) == "knight":
			raw *= 1.25
		elif str(hero.id) == "barbarian":
			raw *= 1.2
	var armor: int = maxi(0, int(target.armor) - (1 if int(target.effects.get("split_ticks", 0)) > 0 else 0))
	var hit: float = Damage.defender_raw(raw, armor, tags, kind, 1 if charged else 0)
	var hypnotist: String = str(hero.effects.get("hypnotized_by", ""))
	if not hypnotist.is_empty() and not charged:
		hero.effects.erase("hypnotized_by")
		for ally in g._living():
			if ally != hero:
				return {"from": hero, "to": ally, "hero_target": true, "hit": Damage.hero_hit(raw, g.effective_hero_armor(ally)), "raw": raw, "type": "physical", "ordinary": true, "source": hypnotist, "hypnosis": true}
	if int(target.charges.get("decoys", 0)) > 0:
		target.charges.decoys = int(target.charges.decoys) - 1
		event(g, "decoy", str(hero.instance_id), str(target.actor_id), 0, "Ложный сундук рассыпается")
		return {}
	if int(target.charges.get("parry", 0)) > 0 and not charged:
		var parried: Array = target.charges.get("parried_heroes", [])
		if not parried.has(str(hero.instance_id)):
			target.charges.parry = int(target.charges.parry) - 1
			parried.append(str(hero.instance_id))
			target.charges.parried_heroes = parried
			event(g, "parry", str(target.actor_id), str(hero.instance_id), 0, "Страж парирует и отвечает")
			return actor_strike(g, target, hero, 0.65, true, "physical", false, "parry")
	return {"from": hero, "to": target, "hero_target": false, "hit": hit, "raw": raw, "type": kind, "ordinary": not charged, "source": str(hero.instance_id), "charged": charged}


func play_drum(g, hero: Dictionary, available: Array[Dictionary]) -> bool:
	if str(hero.id) != "bard" or not can_cast(hero) or not HeroRules.item_active(hero, "item_broken_rhythm_drum"):
		return false
	var state: Dictionary = hero.get("equipment_state", {})
	if bool(state.get("drum_used", false)):
		return false
	for actor in available:
		var prep: Dictionary = actor.effects.get("preparing", {})
		if prep.is_empty() or bool(prep.get("delayed", false)) or str(prep.kind) not in ["earthshaker", "boulder", "guillotine", "cleaver"]:
			continue
		prep.remaining = int(prep.remaining) + 1
		prep.delayed = true
		state.drum_used = true
		hero.equipment_state = state
		event(g, "delay", str(hero.instance_id), str(actor.actor_id), 1, "Барабан задерживает замах")
		return true
	return false


func select_actor_target(g, actor: Dictionary) -> Dictionary:
	var party: Array[Dictionary] = g._living()
	if party.is_empty():
		return {}
	var path: String = str(actor.path_id)
	if (path == "pickpockets" and bool(params(actor).get("target_best_item", false))) or (path == "mimic_weapon_swap" and bool(params(actor).get("best_weapon", false))):
		var best: Dictionary = {}
		var score: float = -1.0
		for hero in party:
			if path == "mimic_weapon_swap" and bool(hero.get("weapon_swapped", false)):
				continue
			var value: float = HeroRules.item_score(str(hero.get("equipment", {}).get("weapon", ""))) + float(hero.damage)
			if value > score:
				best = hero
				score = value
		if not best.is_empty():
			return best
	if int(actor.effects.get("duel_ticks", 0)) > 0:
		var rival: Dictionary = living_hero(g, str(actor.effects.duel))
		if not rival.is_empty():
			return rival
	if str(actor.path_id) == "war_hound_sapper_hunter" and not bool(actor.charges.get("sabotage", false)):
		for hero in party:
			if str(hero.id) == "rogue" and int(hero.disarm_charges) > 0:
				return hero
	if str(actor.id) == "mimic":
		for id in ["bard", "priest", "mage", "rogue", "barbarian", "knight"]:
			for hero in party:
				if str(hero.id) == id:
					return hero
	if str(actor.id) == "executioner" and int(actor.age) == 1:
		for hero in party:
			if int(hero.get("goblin_mark_slot", -1)) == int(actor.source_slot):
				return hero
	if str(actor.id) == "spider":
		var poisoned: Array[Dictionary] = []
		for hero in party:
			if int(hero.poison_ticks) > 0:
				poisoned.append(hero)
		return g._most_wounded(poisoned if not poisoned.is_empty() else party)
	if str(actor.id) == "war_hound" and str(actor.path_id) != "war_hound_lycanthrope":
		return g._most_wounded(party)
	return party[0]


func actor_strike(g, actor: Dictionary, target: Dictionary, multiplier: float = 1.0, special: bool = false, kind: String = "physical", bypass: bool = false, ability_override: String = "") -> Dictionary:
	# Reserve one directed ordinary strike at declaration time. The shared
	# source-room budget survives forms and cannot be refilled by later marks.
	if not special and int(actor.effects.get("duel_ticks", 0)) <= 0:
		var banner: Dictionary = Skills.room(g, int(actor.source_slot)).get("incoming_banner", {})
		if not banner.is_empty():
			var orders: Dictionary = Skills.room(g, int(banner.source_slot))
			var marked: Dictionary = living_hero(g, str(banner.target))
			if int(orders.get("banner_remaining", 0)) > 0 and not marked.is_empty():
				target = marked
				orders.banner_remaining = int(orders.banner_remaining) - 1
				g.active_target_id = str(target.instance_id)
	var ability: String = ability_override if not ability_override.is_empty() else str(actor.effects.get("resolving_ability", ""))
	var tree: Dictionary = Skills.attack_bonus(g, actor, target, not special, ability)
	var raw: float = Skills.damage(actor, float(tree.bonus), multiplier)
	var bonus: float = float(actor.get("revenant_damage_bonus", 0.0))
	if int(actor.get("ability_attacks", 0)) > 0:
		bonus += float(actor.get("ability_attack_bonus", 0.0))
		actor.ability_attacks = int(actor.ability_attacks) - 1
	if str(actor.actor_id) == "lord":
		var modifiers: Dictionary = g.talent_modifiers()
		if g.lord_strikes < int(modifiers.opening_strikes):
			raw *= float(modifiers.opening_multiplier)
		g.lord_strikes += 1
	elif int(actor.age) == 1 and g.selected_relics.has("war_banner"):
		bonus += 0.15
	raw *= 1.0 + bonus
	raw += 0 if g.combat_tick <= 40 else 1 + floori(float(g.combat_tick - 41) / 10.0)
	if str(actor.id) == "spider" and int(target.poison_ticks) > 0:
		raw += 3
	if str(actor.id) == "executioner" and int(actor.age) == 1 and int(target.get("goblin_mark_slot", -1)) == int(actor.source_slot):
		raw *= 1.15
		target.erase("goblin_mark_slot")
		g._battle_add(str(actor.source_room_uid), "combos")
	if str(actor.id) == "war_hound" and int(target.hp) * 5 <= int(target.max_hp) * 2:
		raw *= 1.3
	if str(actor.path_id) == "war_hound_sapper_hunter" and str(target.id) == "rogue" and not bool(actor.charges.get("sabotage", false)):
		raw *= float(params(actor).get("sapper_bite_factor", 1.0))
	if str(actor.get("specialization", "")) == "ambush" and int(actor.age) == 1:
		raw *= 1.75
	var armor: int = maxi(0, g.effective_hero_armor(target) - int(tree.armor_bypass))
	if str(actor.id) == "wraith":
		armor = maxi(0, armor - int(actor.get("armor_bypass", 2)))
	var value: int = Damage.hero_hit(raw, armor, kind, bypass)
	var tags: PackedStringArray = actor.get("tags", PackedStringArray())
	if tags.has("corporeal") and str(target.id) == "knight":
		value = maxi(1, ceili(value * 0.8))
	if tags.has("ambush") and int(actor.age) == 1 and has_class(g, "rogue"):
		value = maxi(1, ceili(value * 0.65))
	if not special and kind == "physical" and int(target.effects.get("cover_until", -1)) == g.combat_tick:
		value = maxi(1, ceili(value * 0.7))
		target.effects.erase("cover_until")
	return {"from": actor, "to": target, "hero_target": true, "hit": value, "raw": raw, "type": kind, "ordinary": not special, "source": str(actor.source_room_uid), "ability": ability}


func prepare(g, actor: Dictionary, kind: String, duration: int, target: Dictionary = {}) -> void:
	actor.effects.preparing = {"kind": kind, "remaining": duration, "total": duration, "target": str(target.get("instance_id", "")), "delayed": false}
	event(g, "prepare", str(actor.actor_id), str(target.get("instance_id", "")), duration, "%s готовит приём" % actor.name, int(actor.source_slot))


func plan_actor(g, actor: Dictionary, strikes: Array[Dictionary]) -> void:
	if int(actor.hp) <= 0 or int(actor.get("delay", 0)) > 0:
		return
	var target: Dictionary = select_actor_target(g, actor)
	if target.is_empty():
		return
	g.active_target_id = str(target.instance_id)
	var path: String = str(actor.path_id)
	var t: int = tier(int(actor.stage))
	var age: int = int(actor.age)
	var p: Dictionary = params(actor)
	if str(actor.phase_id) == "throne_guard":
		return
	if str(actor.phase_id) == "sarcophagus":
		if bool(actor.get("relocated", false)):
			return
		actor.effects.ritual_ticks = int(actor.effects.get("ritual_ticks", 3)) - 1
		if int(actor.effects.ritual_ticks) <= 0:
			actor.effects.release_coffin = true
		return
	if str(actor.phase_id) == "servant" and bool(actor.get("class_skill", false)) and not bool(actor.charges.get("class_used", false)):
		var role: String = str(actor.get("servant_class", ""))
		if role == "priest" and age >= 3:
			actor.charges.class_used = true
			for ally in living_actors():
				if int(ally.source_slot) == int(actor.source_slot) and ally != actor:
					ally.effects.pending_heal = int(ally.effects.get("pending_heal", 0)) + maxi(1, ceili(actor.max_hp * 0.15))
			return
		elif role == "knight":
			actor.shield = maxi(1, ceili(actor.max_hp * 0.15))
			actor.charges.class_used = true
		elif role == "mage" and age == 3:
			actor.charges.class_used = true
			strikes.append(actor_strike(g, actor, target, 1.5, true, "magic"))
			return
		elif role == "barbarian" and int(actor.hp) * 5 <= int(actor.max_hp) * 2:
			actor.charges.class_used = true
			strikes.append(actor_strike(g, actor, target, 1.25, true))
			return
		elif role == "bard":
			actor.charges.class_used = true
			for ally in living_actors():
				if int(ally.source_slot) == int(actor.source_slot) and ally != actor:
					ally.ability_attacks = 1
					ally.ability_attack_bonus = 0.15
		elif role == "rogue":
			actor.charges.class_used = true
			strikes.append(actor_strike(g, actor, target, 1.0, true, "physical", true))
			return
	var prep: Dictionary = actor.effects.get("preparing", {})
	if not prep.is_empty():
		prep.remaining = int(prep.remaining) - 1
		if int(prep.remaining) > 0:
			return
		actor.effects.erase("preparing")
		actor.effects.resolving_ability = str(prep.kind)
		var locked: Dictionary = living_hero(g, str(prep.target))
		if not locked.is_empty():
			target = locked
		match str(prep.kind):
			"earthshaker":
				for hero in g._living():
					strikes.append(actor_strike(g, actor, hero, float(p.get("heavy_factor", 0.65)), true))
			"boulder", "guillotine":
				strikes.append(actor_strike(g, actor, target, float(p.get("heavy_factor", 1.7)), true))
			"cleaver":
				strikes.append(actor_strike(g, actor, target, float(p.get("followup_factor", 1.35)), true))
			"banshee":
				for hero in g._living():
					strikes.append(actor_strike(g, actor, hero, float(p.get("scream_factor", 1.4)), true, "magic", true))
				actor.charges.scream = true
				if t == 3:
					pending.append({"kind": "banshee_echo", "damage": maxi(1, ceili(Skills.damage(actor, Skills.value(g, "creatures_power_of_lament", "existing_echo_damage_bonus"), float(p.get("echo_factor", 0.35))))), "source": str(actor.source_room_uid)})
			"hellfire":
				actor.effects.fire_ticks = int(p.get("fire_rounds", 3)) + 1
				event(g, "fire", str(actor.actor_id), "", 2 + t, "Пол охвачен пламенем", int(actor.source_slot))
			"hypnosis":
				var strong: Dictionary = g._living()[0]
				for hero in g._living():
					if int(hero.damage) > int(strong.damage):
						strong = hero
				if g._living().size() > 1:
					strong.effects.hypnotized_by = str(actor.source_room_uid)
					event(g, "hypnosis", str(actor.actor_id), str(strong.instance_id), 1, "Гипнотический взгляд", int(actor.source_slot))
				actor.charges.hypnosis_count = int(actor.charges.get("hypnosis_count", 0)) + 1
			"feast":
				actor.effects.pending_heal = ceili(actor.max_hp * float(p.get("heal_fraction", 0.2)))
		return
	if path == "cocoon_weaver" and t >= 2 and age >= ceili(float(p.get("warmup_seconds", 2.0)) * 2.0) and g.tick >= int(actor.charges.get("cocoon_next", 0)):
		var duration: int = maxi(1, ceili(float(p.get("duration_seconds", 2.0)) * 2.0))
		if has_class(g, "rogue"):
			duration = maxi(1, duration / 2)
		target.cocoon_ticks = duration + 1
		target.effects.cocoon_ticks = duration
		target.effects.cocoon_total = duration
		target.effects.cocoon_source = str(actor.actor_id)
		actor.charges.cocoon_next = g.tick + ceili(float(p.get("cooldown_seconds", 8.0)) * 2.0)
		event(g, "cocoon", str(actor.actor_id), str(target.instance_id), duration, "Герой оплетён коконом", int(actor.source_slot))
		return
	if path == "brood_mother" and t == 3 and age >= ceili(float(p.get("guardian_after_seconds", 3.0)) * 2.0) and not bool(actor.charges.get("living_child", false)):
		actor.charges.living_child = true
		var child: Dictionary = make_actor(g, int(actor.source_slot), owners[int(actor.source_slot)].stats, "spiderling", 0.2)
		child.path_id = ""
		child.name = "Защитник выводка"
		add_actor(g, child)
	if path in ["ogre_earthshaker", "ogre_stonethrower"] and age % int(p.get("cooldown_rounds", 4)) == 2:
		prepare(g, actor, "earthshaker" if path == "ogre_earthshaker" else "boulder", int(p.get("windup_rounds", 2)), g._living()[-1] if path == "ogre_stonethrower" else target)
		return
	if path == "guillotine" and int(actor.charges.get("blade", 0)) >= int(p.get("charge_hits", 3)):
		actor.charges.blade = 0
		prepare(g, actor, "guillotine", int(p.get("windup_rounds", 1)), g._most_wounded(g._living()))
		return
	if path == "wraith_banshee" and not bool(actor.charges.get("scream", false)) and not bool(actor.charges.get("interrupted", false)):
		prepare(g, actor, "banshee", int(p.get("windup_rounds", 3)), target)
		return
	if path == "war_hound_hellfire" and age % int(p.get("cooldown_rounds", 10)) == 1:
		prepare(g, actor, "hellfire", int(p.get("windup_rounds", 2)), target)
		return
	if path == "vampire_hypnotist" and not bool(actor.charges.get("interrupted", false)) and int(actor.charges.get("hypnosis_count", 0)) < (2 if t == 3 else 1) and (age == 1 or age == 12):
		prepare(g, actor, "hypnosis", int(p.get("windup_rounds", 2)), target)
		return
	if path == "ogre_maneater" and bool(actor.charges.get("earned_feast", false)) and not bool(actor.charges.get("feast", false)):
		actor.charges.feast = true
		prepare(g, actor, "feast", int(p.get("feast_rounds", 1)))
		return
	if path == "cleaver" and bool(actor.charges.get("earned_cleave", false)) and not bool(actor.charges.get("cleave", false)) and int(p.get("followup_uses", 0)) > 0:
		actor.charges.cleave = true
		prepare(g, actor, "cleaver", 1, target)
		return
	if path == "duelist" and t == 3 and age == 12 and not bool(actor.charges.get("second_duel", false)):
		actor.charges.second_duel = true
		actor.effects.duel = str(g._living()[0].instance_id)
		actor.effects.duel_ticks = 3
		return
	if path == "saboteurs" and t >= 2 and age >= 5 and not bool(actor.charges.get("bomb", false)):
		actor.charges.bomb = true
		bomb(g, actor, false)
		return
	clear_ended_duels(g)
	for duelist in living_actors():
		if int(duelist.effects.get("duel_ticks", 0)) > 0 and duelist != actor:
			return
	var multiplier: float = 1.0
	actor.effects.erase("resolving_ability")
	if str(actor.id) == "ogre" and path.is_empty() and age % 3 == 0:
		multiplier = 1.5
	if bool(actor.charges.get("empowered_bite", false)):
		actor.charges.empowered_bite = false
		multiplier *= float(p.get("bite_factor", 1.5))
	strikes.append(actor_strike(g, actor, target, multiplier))
	if path == "guillotine":
		actor.charges.blade = int(actor.charges.get("blade", 0)) + 1
	if path == "guardian_aegis" and age >= 2:
		actor.charges.aegis = true


func resolve_strikes(g, strikes: Array[Dictionary]) -> void:
	var hits: Array[Dictionary] = []
	# Reserve finite shield absorption in declared order before resolving HP.
	for strike in strikes:
		var target: Dictionary = strike.to
		var amount: int = ceili(float(strike.hit))
		if not bool(strike.hero_target):
			amount = Skills.protect(g, target, float(strike.hit), bool(strike.ordinary), str(strike.type), bool(strike.get("charged", false)))
			var absorbed: int = mini(amount, int(target.get("shield", 0)))
			# Cover is already inside shield; spend that subset first, never add it twice.
			target.shield = int(target.get("shield", 0)) - absorbed
			target.run_cover_shield = maxi(0, int(target.get("run_cover_shield", 0)) - absorbed)
			amount -= absorbed
			strike.absorbed = absorbed
		strike.amount = amount
		hits.append(strike)
	for strike in hits:
		var target: Dictionary = strike.to
		var attacker: Dictionary = strike.from
		var before: int = int(target.hp)
		var actual: int = mini(before, int(strike.amount))
		if bool(strike.hero_target):
			var breakdown: Dictionary = hero_damage_breakdown(g, target, int(strike.amount), str(strike.source))
			actual = int(breakdown.actual)
			strike.overkill = int(breakdown.overkill)
			strike.redirected = int(breakdown.redirected)
		else:
			target.hp = maxi(0, before - int(strike.amount))
			if str(target.actor_id) == "lord":
				g.report.lord_damage = int(g.report.lord_damage) + actual
		strike.actual = actual
		strike.killed = before > 0 and int(target.hp) <= 0
		var attacker_id: String = str(attacker.get("actor_id", attacker.get("instance_id", "")))
		var target_id: String = str(target.get("actor_id", target.get("instance_id", "")))
		event(g, "attack", attacker_id, target_id, actual, "%s → %s: −%d HP" % [attacker.name, target.name, actual], int(attacker.get("source_slot", -1)))
		g.last_action.meta = {"damage_type": str(strike.type), "ordinary": bool(strike.ordinary), "ability": str(strike.get("ability", "")), "prepared_kind": str(strike.get("ability", "")), "charged": bool(strike.get("charged", false)), "shield_absorbed": int(strike.get("absorbed", 0))}
	clear_ended_duels(g)
	# Reactions follow the complete direct damage batch. A slain vampire cannot
	# heal; a pending death remains a death for prayer and formation decisions.
	for strike in hits:
		if bool(strike.hero_target) and strike.from.has("actor_id"):
			after_actor_hit(g, strike)
		elif not bool(strike.hero_target):
			after_hero_hit(g, strike)
	for actor in actors.duplicate():
		if int(actor.hp) <= 0:
			continue
		var path: String = str(actor.path_id)
		var t: int = tier(int(actor.stage))
		if bool(actor.effects.get("release_coffin", false)):
			wake_vampire(g, actor)
			event(g, "transform", str(actor.actor_id), "", int(actor.hp), "Вампир покидает саркофаг", int(actor.source_slot))
		if int(actor.effects.get("pending_heal", 0)) > 0:
			var gain: int = mini(int(actor.max_hp) - int(actor.hp), Skills.heal_amount(g, float(actor.effects.pending_heal)))
			actor.effects.erase("pending_heal")
			actor.hp = int(actor.hp) + gain
			event(g, "heal", str(actor.actor_id), str(actor.actor_id), gain, "Защитник восстанавливает здоровье", int(actor.source_slot))
		if path == "war_hound_lycanthrope" and int(actor.hp) * 5 <= int(actor.max_hp) * 2 and not bool(actor.charges.get("transformed", false)):
			actor.charges.transformed = true
			actor.effects.transformed = true
			actor.tree_base_damage = Skills.base_damage(actor) * float(params(actor).get("transformed_damage_factor", 1.2))
			actor.damage = ceili(Skills.damage(actor))
			if t >= 2:
				for hero in g._living():
					if str(hero.id) in ["priest", "bard", "mage"]:
						actor.effects.original_order = hero_order(g)
						g.heroes.erase(hero)
						g.heroes.push_front(hero)
						hero.effects.forced_front = true
						break
			event(g, "transform", str(actor.actor_id), "", 0, "Гончая превращается в оборотня", int(actor.source_slot))
		if path == "vampire_sarcophagus_master" and float(actor.hp) / actor.max_hp <= float(params(actor).get("hide_hp_fraction", 0.35)) and not bool(actor.charges.get("coffin", false)):
			actor.charges.coffin = true
			actor.effects.body_hp = int(actor.hp)
			actor.effects.body_max = int(actor.max_hp)
			actor.effects.ritual_ticks = int(params(actor).get("ritual_rounds", 3))
			actor.phase_id = "sarcophagus"
			actor.max_hp = maxi(1, ceili(float(actor.get("tree_base_hp", actor.max_hp)) * float(params(actor).get("coffin_hp_factor", 0.2)) * (1.0 + float(actor.get("tree_hp_bonus", 0.0)) + Skills.value(g, "creatures_sturdy_lid", "coffin_hp_bonus"))))
			actor.hp = actor.max_hp
			if not retreat_vampire(g, actor):
				event(g, "transform", str(actor.actor_id), "", int(actor.effects.ritual_ticks), "Вампир скрывается в саркофаге", int(actor.source_slot))
		if path == "mimic_false_treasury" and t >= 2 and float(actor.hp) / actor.max_hp < float(params(actor).get("relocate_hp_fraction", 0.5)) and not bool(actor.charges.get("second_shell", false)):
			actor.charges.second_shell = true
			actor.charges.decoys = 0 if has_class(g, "rogue") else 1
			event(g, "transform", str(actor.actor_id), "", 0, "Мимик меняет оболочку", int(actor.source_slot))

	Skills.expire_after_exchange(g)


func after_actor_hit(g, strike: Dictionary) -> void:
	var actor: Dictionary = strike.from
	var target: Dictionary = strike.to
	var path: String = str(actor.path_id)
	var t: int = tier(int(actor.stage))
	var dealt: int = int(strike.actual)
	if dealt <= 0:
		return
	if str(actor.id) == "goblin":
		var linked: Dictionary = g._outgoing_combo(int(actor.source_slot))
		if str(linked.get("id", "")) == "marked_ambush":
			for hero in g.heroes:
				hero.erase("goblin_mark_slot")
			target.goblin_mark_slot = int(linked.to)
	if str(actor.id) == "vampire" and int(actor.hp) > 0 and str(actor.phase_id) != "sarcophagus":
		actor.hp = mini(int(actor.max_hp), int(actor.hp) + Skills.heal_amount(g, dealt * 0.25))
	if path == "venom_hunter" and int(target.hp) > 0:
		if t >= 2 and int(target.poison_ticks) > 0:
			var consumed_ticks: int = mini(int(target.poison_ticks), int(params(actor).get("consume_ticks", 2)))
			var burst: float = 0.0
			for _tick in range(consumed_ticks):
				burst += g.consume_poison_tick(target, false)
			hero_damage(g, target, g._poison_hit(target, burst, g._poison_aura_multiplier()), str(actor.source_room_uid))
		poison(g, target, Skills.base_damage(actor) * float(params(actor).get("poison_damage_factor", 0.2)), int(params(actor).get("poison_ticks", 3)), str(actor.source_room_uid), float(actor.get("tree_damage_bonus", 0.0)))
	elif path == "cocoon_weaver" and t == 1:
		target.effects.web_ticks = 2
	elif path == "war_banner":
		var source_slot: int = int(actor.source_slot)
		var n: int = Skills.transfer_neighbor(g, source_slot, "shared_distant_orders")
		if n >= 0:
			var orders: Dictionary = Skills.room(g, source_slot)
			if not orders.has("banner_remaining"):
				orders.banner_remaining = t + int(Skills.value(g, "creatures_loud_command", "extra_directed_ordinary_attacks"))
			if int(orders.banner_remaining) > 0:
				var receiving_room: Dictionary = Skills.room(g, n)
				receiving_room.incoming_banner = {"source_slot": source_slot, "target": str(target.instance_id)}
	elif path == "pickpockets":
		var slots: Array = target.get("equipment_disabled_slots", [])
		if not bool(actor.charges.get("weapon_stolen", false)):
			actor.charges.weapon_stolen = true
			slots.append("weapon")
		elif t == 3 and not bool(actor.charges.get("shield_stolen", false)):
			actor.charges.shield_stolen = true
			slots.append("protection")
		target.equipment_disabled_slots = slots
		g._recalculate_hero(target)
	elif path == "mimic_weapon_swap" and int(actor.charges.get("swapped_count", 0)) < int(params(actor).get("targets", 1)) and not bool(target.get("weapon_swapped", false)):
		actor.charges.swapped_count = int(actor.charges.get("swapped_count", 0)) + 1
		if has_class(g, "rogue") and not bool(actor.charges.get("swap_detected", false)):
			actor.charges.swap_detected = true
			event(g, "disarm", "rogue", str(actor.actor_id), 0, "Следопыт распознаёт подделку", int(actor.source_slot))
			return
		target.weapon_swapped = true
		target.effects.weapon_swap = true
		event(g, "swap_weapon", str(actor.actor_id), str(target.instance_id), 0, "Мимик подменил оружие до конца волны", int(actor.source_slot))
	elif path == "war_hound_sapper_hunter" and str(target.id) == "rogue" and not bool(actor.charges.get("sabotage", false)):
		actor.charges.sabotage = true
		target.disarm_charges = maxi(0, int(target.disarm_charges) - 1)
	if bool(strike.killed):
		var recovery: int = Skills.personal_kill(g, actor, bool(strike.ordinary))
		if recovery > 0:
			event(g, "heal", str(actor.actor_id), str(actor.actor_id), recovery, "Душа поверженного укрепляет защитника", int(actor.source_slot))
		if path == "ogre_maneater":
			actor.charges.earned_feast = true
		elif path == "vampire_sire" and (not bool(actor.charges.get("sired", false)) or t == 3):
			actor.charges.sired = true
			var memory: Dictionary = g.rooms[int(actor.source_slot)].get("evolution_memory", {})
			if int(memory.get("thrall_wave", 0)) != g.wave + 1:
				memory.thrall_candidates = []
				memory.thrall = str(target.id)
			var candidates: Array = memory.get("thrall_candidates", [])
			if not candidates.has(str(target.id)):
				candidates.append(str(target.id))
			memory.thrall_candidates = candidates
			memory.thrall_wave = g.wave + 1
			g.rooms[int(actor.source_slot)].evolution_memory = memory
		elif path == "cleaver":
			actor.charges.earned_cleave = true
			var overflow: int = int(strike.get("overkill", 0))
			if overflow > 0 and not g._living().is_empty():
				var other: Dictionary = g._living()[0]
				var actual: int = hero_damage(g, other, Damage.hero_hit(overflow, g.effective_hero_armor(other)), str(actor.source_room_uid), false)
				event(g, "cleave", str(actor.actor_id), str(other.instance_id), actual, "Тесак переносит остаток удара", int(actor.source_slot))


func after_hero_hit(g, strike: Dictionary) -> void:
	var hero: Dictionary = strike.from
	var target: Dictionary = strike.to
	Skills.after_received(g, target, strike)
	if str(target.actor_id) == "lord" and int(target.hp) > 0 and int(strike.actual) > 0 and bool(strike.get("charged", false)) and Skills.has(g, "lord_vengeful_seal") and Skills.once(Skills.wave(g), "vengeful_seal"):
		var reply: int = hero_damage(g, hero, Damage.hero_hit(float(strike.actual) * Skills.value(g, "lord_vengeful_seal", "reply_damage_fraction_of_actual_lord_hp_lost"), g.effective_hero_armor(hero), "magic"), "lord")
		event(g, "spell", "lord", str(hero.instance_id), reply, "Мстительная печать отвечает магу")
	if int(strike.actual) > 0 and bool(strike.ordinary) and HeroRules.item_active(hero, "item_armour_splitter"):
		var state: Dictionary = hero.get("equipment_state", {})
		var identity: String = "%s:%s" % [target.actor_id, target.phase_id]
		if str(state.get("split_target", "")) != identity:
			state.split_target = identity
			state.split_hits = 0
		if int(target.armor) > 0 and not bool(state.get("split_used", false)):
			state.split_hits = int(state.get("split_hits", 0)) + 1
			if int(state.split_hits) >= 3:
				state.split_used = true
				if not bool(target.charges.get("split_received", false)):
					target.charges.split_received = true
					target.effects.split_ticks = 3
					event(g, "armor_break", str(hero.instance_id), str(target.actor_id), 1, "Топор раскалывает броню", int(target.source_slot))
		hero.equipment_state = state
	if bool(strike.ordinary) and str(strike.type) == "physical" and int(hero.hp) > 0:
		burn_floor(g, hero)


func bomb(g, actor: Dictionary, final: bool) -> void:
	var party: Array[Dictionary] = g._living()
	if party.is_empty():
		return
	var disabled: bool = disarm(g, int(actor.source_slot))
	var t: int = tier(int(actor.stage))
	var hit: int = maxi(1, ceili(Skills.damage(actor, 0.0, float(params(actor).get("explosion_factor" if final else "throw_factor", 1.0))) * (0.4 if disabled else 1.0)))
	if not final or t < 3:
		party.resize(1)
	for hero in party:
		creature_direct_damage(g, actor, hero, hit)
	event(g, "explosion", str(actor.actor_id), "", hit, "Пороховая бочка взрывается", int(actor.source_slot))


func give_cup(g, actor: Dictionary) -> void:
	if g._living().is_empty() or has_class(g, "rogue"):
		return
	var hero: Dictionary = g._living()[0]
	if not hero.has("cursed_cup"):
		hero.cursed_cup = {"uses": 0, "used_this_battle": true, "source": str(actor.source_room_uid), "heal_fraction": float(params(actor).get("heal_fraction", 0.08)), "bite_fraction": float(params(actor).get("bite_fraction", 0.3)), "uses_to_bite": int(params(actor).get("uses_to_bite", 3))}
		event(g, "gift", str(actor.actor_id), str(hero.instance_id), 0, "Герой подбирает проклятый кубок", int(actor.source_slot))


func process_hero_deaths(g) -> void:
	if processing_deaths:
		return
	processing_deaths = true
	var deaths: Array[Dictionary] = []
	# Snapshot every death before rewards, cleanup, prayer, or funeral silence.
	for hero in g.heroes:
		if int(hero.hp) <= 0 and not bool(hero.get("death_processed", false)):
			deaths.append({"hero": hero, "prayer": str(hero.id) == "priest" and HeroRules.item_active(hero, "item_last_prayer") and int(hero.get("silence_ticks", 0)) <= 0 and int(hero.get("cocoon_ticks", 0)) <= 0 and int(effects.get("partitions", {}).get("ticks", 0)) <= 0 and not bool(hero.get("equipment_state", {}).get("wave:prayer", false))})
	for record in deaths:
		var hero: Dictionary = record.hero
		clear_ended_duels(g)
		if hero.has("spore") and bool(hero.spore.get("on_death", false)):
			burst_spore(g, hero)
		if bool(record.prayer) and not g._living().is_empty():
			hero.equipment_state["wave:prayer"] = true
			heal(g, hero, g._most_wounded(g._living()), 6 + 2 * (int(hero.level) - 1))
		for actor in actors:
			if str(actor.path_id) == "venom_hunter" and tier(int(actor.stage)) == 3 and int(hero.poison_ticks) > 0 and str(hero.get("poison_source", "")) == str(actor.source_room_uid) and not bool(actor.charges.get("infection", false)):
				actor.charges.infection = true
				for living in g._living():
					poison(g, living, float(hero.get("run_poison_base", hero.poison_damage)), 3, str(actor.source_room_uid))
	if not deaths.is_empty():
		var funeral: Dictionary = effects.get("funeral", {})
		if not funeral.is_empty():
			effects.erase("funeral")
			for hero in g._living():
				hero.silence_ticks = maxi(int(hero.get("silence_ticks", 0)), int(funeral.ticks) + 1)
				hero.silence_source = str(funeral.source)
			event(g, "silence", str(funeral.source), "", int(funeral.ticks), "Похоронный звон подавляет поддержку")
		g._reward_dead_heroes()
	processing_deaths = false


func burst_spore(g, carrier: Dictionary) -> void:
	if not carrier.has("spore"):
		return
	var spore: Dictionary = carrier.spore
	carrier.erase("spore")
	for hero in g._living():
		if hero != carrier:
			poison(g, hero, float(spore.damage), int(spore.duration), str(spore.source))
	event(g, "spore", str(carrier.instance_id), "", int(spore.damage), "Спора заражает отряд")


func resolve_actor_deaths(g) -> void:
	for actor in actors.duplicate():
		if int(actor.hp) > 0 or bool(actor.get("finalized", false)):
			continue
		if bool(actor.get("revive_mark", false)):
			actor.revive_mark = false
			actor.hp = clampi(ceili(actor.max_hp * float(actor.get("revive_fraction", 0.3))), 1, int(actor.max_hp))
			actor.revenant_damage_bonus = float(actor.get("revive_damage_bonus", 0.0))
			event(g, "revive", str(actor.actor_id), str(actor.actor_id), int(actor.hp), "Метка возвращает защитника", int(actor.source_slot))
			continue
		actor.finalized = true
		recovering.erase(str(actor.actor_id))
		var slot: int = int(actor.source_slot)
		var path: String = str(actor.path_id)
		var t: int = tier(int(actor.stage))
		for hero in g.heroes:
			if str(hero.effects.get("cocoon_source", "")) == str(actor.actor_id):
				hero.cocoon_ticks = 0
				hero.effects.erase("cocoon_ticks")
				hero.effects.erase("cocoon_source")
		if path == "war_hound_lycanthrope" and actor.effects.has("original_order"):
			restore_order(g, actor.effects.original_order)
			for hero in g.heroes:
				hero.effects.erase("forced_front")
			g._reorder_party("monster", false)
			rotation.resume_after = g.combat_tick + 1
		if path == "mimic_living_chamber":
			for mouth in actors:
				if int(mouth.source_slot) == slot and str(mouth.phase_id) == "appendage":
					mouth.hp = 0
					mouth.finalized = true
		if path == "saboteurs" and not bool(actor.charges.get("barrel", false)):
			actor.charges.barrel = true
			bomb(g, actor, true)
		if path == "guardian_aegis" and bool(actor.charges.get("aegis", false)):
			var n: int = Skills.transfer_neighbor(g, slot, "shared_runic_channel")
			if n >= 0 and not g.rooms[n].is_empty() and str(g.room_stats(n).kind) == "monster":
				var amount: int = maxi(1, ceili(actor.max_hp * float(params(actor).get("shield_hp_factor", 0.2)) * (1.0 + Skills.value(g, "creatures_fortified_aegis", "transferred_shield_bonus"))))
				var recipient: Dictionary = {}
				for ally in actors:
					if int(ally.source_slot) == n and int(ally.hp) > 0:
						recipient = ally
						break
				if recipient.is_empty():
					pending.append({"kind": "shield", "slot": n, "amount": amount})
				else:
					recipient.shield = int(recipient.get("shield", 0)) + amount
					event(g, "shield", str(actor.actor_id), str(recipient.actor_id), amount, "Эгида передаёт щит соседнему защитнику", slot)
		if path == "guardian_possessed" and str(actor.phase_id) == "base":
			var spirit: Dictionary = make_actor(g, slot, owners[slot].stats, "spirit", float(params(actor).get("spirit_hp_factor", 0.25)))
			spirit.tree_base_damage = Skills.base_damage(owners[slot].stats) * float(params(actor).get("spirit_damage_factor", 0.6))
			spirit.damage = maxi(1, ceili(Skills.damage(spirit)))
			spirit.path_id = ""
			spirit.name = "Освобождённый дух"
			spirit.tags = PackedStringArray(["spirit"])
			spirit.armor = maxi(0, int(spirit.armor) - int(spirit.get("tree_bone_armor", 0)))
			spirit.tree_bone_armor = 0
			for key in ["run_impulse_count", "run_impulse_bonus", "run_edge_bonus", "run_barrier", "run_cover_shield", "shield"]:
				spirit[key] = actor.get(key, 0)
			add_actor(g, spirit)
		if not (path == "guardian_possessed" and str(actor.phase_id) == "base"):
			Skills.final_death(g, actor)
		if path == "brood_mother" and str(actor.phase_id) == "base":
			owners[slot].queues = []
			for _brood in range(int(params(actor).get("brood_waves", 1))):
				owners[slot].queues.append(int(params(actor).get("brood_size", 2)))
			spawn_brood(g, slot)
		event(g, "death", str(actor.actor_id), "", 0, "%s повержен" % actor.name, slot)
	process_hero_deaths(g)
	for slot in owners:
		if owner_alive(int(slot)):
			continue
		if not owners[slot].queues.is_empty():
			spawn_brood(g, int(slot))


func owner_alive(slot: int) -> bool:
	for record in recovering.values():
		if int(record.actor.source_slot) == slot and int(record.actor.hp) > 0:
			return true
	for actor in actors:
		if int(actor.source_slot) == slot and int(actor.hp) > 0:
			return true
	return false


func spawn_brood(g, slot: int) -> void:
	var queue: Array = owners[slot].queues
	if queue.is_empty():
		return
	var count: int = int(queue.pop_front())
	owners[slot].queues = queue
	var config: Dictionary = params(owners[slot].stats)
	for _index in range(count):
		var child: Dictionary = make_actor(g, slot, owners[slot].stats, "spiderling", float(config.get("brood_hp_factor", 0.2)))
		child.tree_base_damage = Skills.base_damage(owners[slot].stats) * float(config.get("brood_damage_factor", 0.35))
		child.damage = maxi(1, ceili(Skills.damage(child)))
		child.path_id = ""
		child.name = "Паучонок"
		add_actor(g, child)


func finish_owners(g) -> void:
	for slot in owners:
		var owner: Dictionary = owners[slot]
		if not bool(owner.get("engaged", false)) or bool(owner.rewarded) or owner_alive(int(slot)) or not owner.queues.is_empty():
			continue
		owner.rewarded = true
		Skills.room_defeated(g, int(slot))
		if int(slot) >= g.rooms.size():
			continue
		g.rooms[int(slot)].status = "retreated" if bool(owner.flags.get("relocated", false)) else "cleared"
		consumed[int(slot)] = true
		var reward: Dictionary = owner.stats.duplicate(true)
		var n: int = next_neighbor(g, int(slot))
		if path_at(g, n) == "blade_floor_corpse_reclaimer":
			var weak: bool = disarm(g, n)
			spent[n] = true
			if not (g.labyrinth_enabled and weak):
				var fraction: float = float(params(g.room_stats(n)).get("xp_reduction_fraction", 0.2)) * (0.5 if weak else 1.0)
				var withheld: int = mini(maxi(0, int(reward.xp) - 1), floori(reward.xp * fraction))
				reward.xp = int(reward.xp) - withheld
				event(g, "reclaim", "room_%d" % n, str(slot), withheld, "Мельница костей: −%d XP героям" % withheld, n)
		g._award_room_loot(reward)


func support_from_future(g, actor: Dictionary) -> void:
	fire_support(g, actor)
	var slot: int = int(actor.source_slot)
	if slot >= g.rooms.size():
		return
	var n: int = next_neighbor(g, slot)
	var gap: int = 0
	while n >= 0 and g.rooms[n].is_empty() and gap < 2:
		gap += 1
		n = next_neighbor(g, n)
	if gap <= 0 or n < 0 or path_at(g, n) != "ballista_clear_sight" or (not g.labyrinth_enabled and spent.has(n)):
		return
	var state: Dictionary = Skills.room(g, n)
	if g.labyrinth_enabled and bool(state.get("support", false)):
		return
	var stats: Dictionary = g.room_stats(n)
	if gap > int(params(stats).get("max_empty_slots", 1)):
		return
	var disabled: bool = disarm(g, n)
	if g.labyrinth_enabled:
		state.support = true
		if disabled:
			return
	spent[n] = true
	if not g._living().is_empty():
		var target: Dictionary = g._living()[-1]
		var party: Array[Dictionary] = g._living()
		var before_hp: Dictionary = {}
		for hero in party:
			before_hp[str(hero.instance_id)] = int(hero.hp)
		var hit: int = trap_hit(g, n, stats, target, Skills.base_damage(stats) * float(params(stats).get("shot_factor", 1.0)), 0.4 if disabled else 1.0)
		apply_trap_echo(g, n, stats, party, before_hp, pending.size(), 0.4 if disabled else 1.0)
		event(g, "bolt", "room_%d" % n, str(target.instance_id), hit, "Баллиста стреляет через свободный проход", n)
	process_hero_deaths(g)


func try_sapper_shot(g, hero: Dictionary) -> void:
	if str(hero.id) != "rogue" or not HeroRules.item_active(hero, "item_sapper_crossbow") or int(hero.disarm_charges) <= 0:
		return
	var state: Dictionary = hero.get("equipment_state", {})
	if bool(state.get("wave:sapper", false)):
		return
	var n: int = next_neighbor(g, g.current_slot)
	if n < 0 or g.rooms[n].is_empty() or str(g.room_stats(n).kind) == "monster" or (not g.labyrinth_enabled and spent.has(n)) or disarmed.has(n):
		return
	if g.labyrinth_enabled:
		disarm(g, n, hero)
		if disarmed.has(n):
			state["wave:sapper"] = true
			hero.equipment_state = state
		return
	hero.disarm_charges = int(hero.disarm_charges) - 1
	state["wave:sapper"] = true
	hero.equipment_state = state
	disarmed[n] = true
	event(g, "disarm", str(hero.instance_id), "room_%d" % n, 1, "Сапёрный болт заранее ослабляет ловушку", n)


func hero_order(g) -> Array[String]:
	var result: Array[String] = []
	for hero in g.heroes:
		result.append(str(hero.instance_id))
	return result


func restore_order(g, ids: Array) -> void:
	var order: Array[Dictionary] = []
	for uid in ids:
		for hero in g.heroes:
			if str(hero.instance_id) == str(uid):
				order.append(hero)
	g.heroes.assign(order)


func rotate_party(g) -> void:
	if g.combat_tick < int(rotation.get("resume_after", 0)):
		return
	for actor in living_actors():
		if int(actor.effects.get("duel_ticks", 0)) > 0:
			return
	for hero in g._living():
		if bool(hero.effects.get("forced_front", false)):
			return
	var party: Array[Dictionary] = g._living()
	if party.size() < 2:
		return
	var retreat: Dictionary = living_hero(g, str(rotation.get("retreat", "")))
	if not retreat.is_empty() and float(retreat.hp) / retreat.max_hp >= 0.6 and can_act(retreat):
		g.heroes.erase(retreat)
		g.heroes.push_front(retreat)
		retreat.effects.retreating = false
		rotation.retreat = ""
		event(g, "rotate", str(retreat.instance_id), "", 0, "Восстановившийся боец возвращается вперёд")
		return
	if bool(rotation.get("used", false)) or int(party[0].hp) * 10 >= int(party[0].max_hp) * 3 or not can_act(party[0]):
		return
	var replacement: Dictionary = {}
	for role in ["knight", "barbarian", "rogue"]:
		for hero in party.slice(1):
			if str(hero.id) == role and int(hero.hp) * 10 >= int(hero.max_hp) * 6 and can_act(hero):
				replacement = hero
				break
		if not replacement.is_empty():
			break
	if replacement.is_empty():
		return
	var wounded: Dictionary = party[0]
	Skills.voluntary_retreat(g, living_actors())
	rotation.used = true
	rotation.retreat = str(wounded.instance_id)
	wounded.skip_attack = 1
	wounded.effects.retreating = true
	g.heroes.erase(replacement)
	g.heroes.push_front(replacement)
	for knight in [wounded, replacement]:
		if str(knight.id) == "knight" and HeroRules.item_active(knight, "item_cover_shield") and not bool(knight.equipment_state.get("cover_used", false)):
			knight.equipment_state.cover_used = true
			replacement.effects.cover_until = g.combat_tick + 1
	event(g, "rotate", str(wounded.instance_id), str(replacement.instance_id), 0, "Здоровый союзник прикрывает раненого")


func decay(g) -> void:
	g._decay_hero_control()
	for hero in g.heroes:
		hero.cocoon_ticks = maxi(0, int(hero.get("cocoon_ticks", 0)) - 1)
		hero.effects.cocoon_ticks = int(hero.cocoon_ticks)
		hero.effects.weapon_swap = bool(hero.get("weapon_swapped", false))
		if hero.has("spore"):
			hero.effects.spore_attacks = int(hero.spore.attacks)
		if hero.effects.has("web_ticks"):
			hero.effects.web_ticks = maxi(0, int(hero.effects.web_ticks) - 1)
	for actor in actors:
		for key in ["duel_ticks", "fire_ticks", "split_ticks"]:
			if actor.effects.has(key):
				actor.effects[key] = maxi(0, int(actor.effects[key]) - 1)
		actor.effects.cocoon_ready_in = maxi(0, int(actor.charges.get("cocoon_next", 0)) - g.tick)
		actor.effects.cocoon_cooldown_total = 16
	for hero in g.heroes:
		hero.effects.partition_ticks = int(effects.get("partitions", {}).get("ticks", 0))
		hero.effects.chain_with = effects.get("chain", {}).get("ids", [])
	for key in ["partitions"]:
		if effects.has(key):
			effects[key].ticks = maxi(0, int(effects[key].ticks) - 1)
	if effects.has("aura_suppressed"):
		effects.aura_suppressed = maxi(0, int(effects.aura_suppressed) - 1)


func end_combat(g) -> void:
	if g.labyrinth_enabled and not encounter_open:
		return
	encounter_open = false
	var fog: Dictionary = effects.get("fog", {})
	if not fog.is_empty():
		for next in pending:
			if str(next.kind) == "fog" and str(next.source) == str(fog.source):
				next.charges = int(fog.charges)
	for hero in g.heroes:
		if not hero.get("equipment_disabled_slots", []).is_empty():
			hero.equipment_disabled_slots = []
			g._recalculate_hero(hero)
		hero.cocoon_ticks = 0
		for key in ["shackles_ticks", "silence_ticks", "rust_ticks"]:
			hero[key] = 0
		if hero.has("cursed_cup"):
			hero.cursed_cup.used_this_battle = false
	for actor in actors:
		g._clear_defender_effects(actor)
		for key in ["run_impulse_count", "run_edge_bonus", "run_barrier", "run_cover_shield"]:
			actor.erase(key)
	for record in recovering.values():
		if bool(record.in_combat) or bool(record.combat_closed) or int(record.origin_visit_id) != int(g.visit_id):
			continue
		# Leaving the actor list cannot extend temporary effects beyond its fight.
		# Body/ritual state and the actor's wave-wide charges survive this cleanup.
		var actor: Dictionary = record.actor
		g._clear_defender_effects(actor)
		for key in actor.effects.keys():
			if str(key) not in ["body_hp", "body_max", "ritual_ticks"]:
				actor.effects.erase(key)
		record.combat_closed = true


func clear_ended_duels(g) -> void:
	for actor in actors:
		if int(actor.effects.get("duel_ticks", 0)) > 0 and (int(actor.hp) <= 0 or living_hero(g, str(actor.effects.get("duel", ""))).is_empty()):
			actor.effects.duel_ticks = 0
			actor.effects.erase("duel")


func burn_floor(g, hero: Dictionary) -> void:
	# Multiple living hounds never burn the same ordinary physical action twice.
	var strongest: Dictionary = {}
	var raw: float = 0.0
	for actor in living_actors():
		if int(actor.effects.get("fire_ticks", 0)) <= 0:
			continue
		var candidate: float = Skills.damage(actor, Skills.value(g, "creatures_hellish_heat", "burning_floor_damage_bonus"), float(params(actor).get("burn_factor", 0.2)))
		if candidate > raw:
			raw = candidate
			strongest = actor
	if strongest.is_empty():
		return
	var slot: int = int(strongest.source_slot)
	var dealt: int = creature_direct_damage(g, strongest, hero, maxi(1, ceili(raw)))
	event(g, "fire", str(strongest.actor_id), str(hero.instance_id), dealt, "Раскалённый пол обжигает героя", slot)
	if int(hero.hp) > 0 and int(hero.poison_ticks) > 0 and Skills.has(g, "shared_burning_toxin") and Skills.once(Skills.room(g, slot), "burning_toxin:" + str(hero.instance_id)):
		var toxin: float = g.consume_poison_tick(hero, false)
		var actual: int = hero_damage(g, hero, g._poison_hit(hero, toxin, g._poison_aura_multiplier()), str(strongest.source_room_uid))
		event(g, "poison", str(strongest.actor_id), str(hero.instance_id), actual, "Пылающий токсин расходует один тик яда", slot)


func trap_hit(g, slot: int, stats: Dictionary, target: Dictionary, raw: float, power: float = 1.0, extra: float = 0.0) -> int:
	if int(target.hp) <= 0 or raw <= 0.0:
		return 0
	var bonus: float = Skills.trap_bonus(g, slot, target, extra)
	# Hidden drive reduces the amount prevented, never the remaining damage.
	if not g.labyrinth_enabled and power < 1.0 and Skills.has(g, "traps_hidden_drive"):
		power = 1.0 - (1.0 - power) * Skills.value(g, "traps_hidden_drive", "prevented_direct_damage_multiplier")
	var amount: int = maxi(1, ceili(raw * (1.0 + float(stats.get("tree_damage_bonus", 0.0)) + bonus) * power))
	var before: int = int(target.hp)
	var actual: int = hero_damage(g, target, amount, g._battle_source(slot))
	Skills.trap_after_hit(g, slot, stats, target, actual, before > 0 and int(target.hp) <= 0)
	return actual


func trigger_plain_trap(g, slot: int, stats: Dictionary, disabled: bool) -> void:
	if g.labyrinth_enabled and disabled:
		return
	var party: Array[Dictionary] = g._living()
	if party.is_empty():
		return
	var source: String = g._battle_source(slot)
	var kind: String = str(stats.kind)
	var before_hp: Dictionary = {}
	for hero in party:
		before_hp[str(hero.instance_id)] = int(hero.hp)
	var echo: bool = g.selected_relics.has("trap_echo") and not g._echo_floors.has(g.layout_effect_scope(slot))
	if kind == "spikes":
		var targets: Array[Dictionary] = party.duplicate()
		var group: bool = str(stats.specialization) == "volley" or (str(stats.id) == "blade_floor" and str(stats.specialization) != "piercing")
		if not group:
			targets.assign([party[-1] if str(stats.id) == "ballista" else party[0]])
		for hero in targets:
			var dealt: int = trap_hit(g, slot, stats, hero, Skills.base_damage(stats), float(stats.disarm_multiplier) if disabled else 1.0)
			event(g, "trap", "room_%d" % slot, str(hero.instance_id), dealt, "%s: −%d HP" % [stats.name, dealt], slot)
		apply_trap_echo(g, slot, stats, party, before_hp, pending.size(), float(stats.disarm_multiplier) if disabled else 1.0)
	elif kind == "poison":
		var duration: int = mini(int(stats.disarm_poison_turns), int(stats.poison_ticks)) if disabled else int(stats.poison_ticks)
		for hero in party:
			g._apply_hero_poison(hero, Skills.base_damage(stats), duration, source)
			if str(stats.specialization) == "plague":
				hero.poison_heal_factor = 0.5
		apply_trap_echo(g, slot, stats, party, before_hp, pending.size(), 1.0)
		event(g, "poison", "room_%d" % slot, "", duration, "Ядовитая камера заражает отряд", slot)
	elif kind in ["shackles", "silence", "rust"]:
		var duration: int = int(stats.effect_turns)
		if disabled:
			duration = maxi(1, duration - 1) if str(stats.specialization) == "warded" else 1
			duration = maxi(duration, mini(int(stats.effect_turns), int(stats.disarm_control_floor)))
		if echo:
			duration = mini(6, duration + 1)
			g._echo_floors.append(g.layout_effect_scope(slot))
		for hero in party:
			var key: String = "pending_" + kind
			if duration >= int(hero.get(key, 0)):
				hero[key + "_source"] = source
			hero[key] = maxi(int(hero.get(key, 0)), duration)
			if kind == "rust":
				hero.rust_amount = maxi(int(hero.get("rust_amount", 0)), int(stats.effect_power))
		var targets: Array[Dictionary] = party.duplicate()
		if not bool(stats.impact_all):
			targets.resize(1)
		var raw: float = float(stats.get("tree_base_impact", stats.impact_damage)) * (0.6 if bool(stats.impact_all) else 1.0)
		for hero in targets:
			trap_hit(g, slot, stats, hero, raw, 0.4 if disabled else 1.0)
		event(g, "trap", "room_%d" % slot, "", duration, "%s: контроль на %d тика" % [stats.name, duration], slot)


func fire_support(g, actor: Dictionary) -> void:
	if not Skills.has(g, "shared_fire_support") or str(actor.actor_id) == "lord":
		return
	var slot: int = next_neighbor(g, int(actor.source_slot))
	if slot < 0 or g.rooms[slot].is_empty() or str(g.rooms[slot].id) != "ballista" or (not g.labyrinth_enabled and spent.has(slot)) or g._living().is_empty():
		return
	var state: Dictionary = Skills.room(g, slot)
	if bool(state.get("support", false)):
		return
	var stats: Dictionary = g.room_stats(slot)
	var path: String = str(stats.get("evolution_path", ""))
	if path == "ballista_reserve_magazine":
		var memory: Dictionary = g.rooms[slot].get("evolution_memory", {})
		if int(memory.get("ammo", 0)) <= 0:
			return
		state.support = true
		var disabled: bool = disarm(g, slot)
		if g.labyrinth_enabled and disabled:
			return
		var hero: Dictionary = g._living()[0]
		var dealt: int = trap_hit(g, slot, stats, hero, Skills.base_damage(stats) * float(params(stats).get("shot_factor", 0.8)), 0.4 if disabled else 1.0)
		if not g.labyrinth_enabled:
			state.shot_ids = [str(hero.instance_id)]
		memory.ammo = int(memory.ammo) - 1
		g.rooms[slot].evolution_memory = memory
		event(g, "bolt", "room_%d" % slot, str(hero.instance_id), dealt, "Огневая поддержка расходует запасной болт", slot)
	else:
		state.support = true
		trigger_trap(g, slot, stats, disarm(g, slot), false)
	sync_primary(g)
	process_hero_deaths(g)


func creature_direct_damage(g, actor: Dictionary, hero: Dictionary, amount: int) -> int:
	var before: int = int(hero.hp)
	var actual: int = hero_damage(g, hero, amount, str(actor.source_room_uid))
	if before > 0 and int(hero.hp) <= 0 and actual > 0:
		var gain: int = Skills.personal_kill(g, actor, false)
		if gain > 0:
			event(g, "heal", str(actor.actor_id), str(actor.actor_id), gain, "Тёмный легион восстанавливает защитника", int(actor.source_slot))
	return actual

extends RefCounted
## Original procedural art. Normalized chamber coordinates keep the same forms
## readable in the field, on a phone and in the progression preview.
## All arguments are snapshots. This module never reads or changes the game model.

const INK = Color("172124")
const WOOD = Color("725238")
const STONE = Color("687476")
const STEEL = Color("a8bdc3")
const GOLD = Color("d6aa60")
const BLOOD = Color("bc5964")
const VENOM = Color("91bb69")
const SPIRIT = Color("ae9bdd")
const WEB = Color("c9d3c2")


static func chamber(c: CanvasItem, rect: Rect2, path: String, tier: int, clock: float, cleared: bool, state: Dictionary = {}) -> void:
	if path.is_empty():
		return
	_transform(c, rect.position, 0, rect.size / Vector2(120, 84))
	var growth: int = 1 if tier < 5 else 2 if tier < 15 else 3
	var dim: float = 0.36 if cleared else 1.0
	var stone := Color(STONE, dim)
	var wood := Color(WOOD, dim)
	var gold := Color(GOLD, dim)
	var metal := Color(STEEL, dim)
	var blood := Color(BLOOD, dim)
	var spirit := Color(SPIRIT, dim)
	var venom := Color(VENOM, dim)
	var web := Color(WEB, dim)
	var pulse: float = (sin(clock * 2.2) + 1.0) * 0.5
	match path:
		"venom_hunter":
			for i in range(growth + 1):
				_flask(c, Vector2(13 + i * 11, 69), venom, 0.7)
		"cocoon_weaver":
			for i in range(growth + 1):
				var x: float = 14 + i * 23
				c.draw_line(Vector2(x, 2), Vector2(x, 32), web, 1)
				_cocoon(c, Vector2(x, 33), 6.0, web)
			_web(c, Vector2(110, 8), 35 + growth * 6, web)
		"brood_mother":
			for i in range(2 + growth * 2):
				var at := Vector2(12 + i * 13, 71 + (i % 2) * 3)
				c.draw_circle(at, 4 + growth, Color("819279", dim))
				c.draw_arc(at, 4 + growth, PI, TAU, 8, web, 1.2)
				if str(state.get("phase_id", "")) == "spiderling":
					c.draw_polyline(PackedVector2Array([at + Vector2(-3, 0), at + Vector2(1, -3), at + Vector2(-1, 3)]), INK, 1.5)
		"war_banner":
			for i in range(growth):
				_tent(c, Vector2(12 + i * 23, 66), wood)
			_banner(c, Vector2(81, 5), Vector2(20 + growth * 4, 31 + growth * 6), Color("31343a", dim), gold)
			_drum(c, Vector2(52, 69), 8 + growth, wood, gold)
		"saboteurs":
			for i in range(growth + 1):
				_barrel(c, Vector2(12 + i * 22, 69), wood, metal)
				c.draw_line(Vector2(12 + i * 22, 48), Vector2(17 + i * 22, 43), gold, 1.5)
				c.draw_circle(Vector2(17 + i * 22, 43), 1.5 + pulse, blood)
			c.draw_line(Vector2(8, 74), Vector2(110, 74), gold, 1)
		"pickpockets":
			c.draw_line(Vector2(8, 16), Vector2(110, 16), wood, 2)
			for i in range(growth + 1):
				var x: float = 18 + i * 23
				c.draw_line(Vector2(x, 16), Vector2(x, 38), metal, 1)
				_sword(c, Vector2(x, 42), metal, 0.6)
			c.draw_colored_polygon(PackedVector2Array([Vector2(25, 69), Vector2(30, 53), Vector2(48, 53), Vector2(54, 69)]), wood)
		"guillotine":
			var tall: float = 39 + growth * 8
			c.draw_line(Vector2(34, 73), Vector2(34, 73 - tall), wood, 6)
			c.draw_line(Vector2(87, 73), Vector2(87, 73 - tall), wood, 6)
			c.draw_line(Vector2(31, 73 - tall), Vector2(90, 73 - tall), wood, 7)
			var blade_y: float = 83 - tall
			var prep: Dictionary = state.get("effects", {}).get("preparing", {})
			if not prep.is_empty():
				blade_y += 15 * float(prep.get("remaining", 1)) / maxf(1, float(prep.get("total", 1)))
			c.draw_colored_polygon(PackedVector2Array([Vector2(39, blade_y), Vector2(82, blade_y), Vector2(82, blade_y + 5), Vector2(39, blade_y + 16)]), metal)
			c.draw_rect(Rect2(28, 68, 67, 7), blood)
		"duelist":
			c.draw_arc(Vector2(60, 71), 37 + growth * 2, PI, TAU, 24, gold, 2)
			for x in [14, 106]:
				_gate(c, Rect2(x - 8, 19, 16, 55), metal, growth)
			for x in [43, 79]:
				c.draw_arc(Vector2(x, 67), 10, 0, TAU, 16, blood, 2)
		"cleaver":
			c.draw_rect(Rect2(24, 59, 70, 16), wood)
			for i in range(growth + 1):
				c.draw_line(Vector2(26 + i * 18, 60), Vector2(36 + i * 18, 74), blood, 3)
			c.draw_line(Vector2(80, 63), Vector2(62, 25), wood, 4)
			c.draw_colored_polygon(PackedVector2Array([Vector2(63, 27), Vector2(94, 23), Vector2(103, 40), Vector2(70, 43)]), metal)
		"guardian_parry":
			for i in range(growth):
				_sword(c, Vector2(14 + i * 18, 51), metal, 1)
			_shield(c, Vector2(85, 47), 15 + growth * 3, stone, gold)
		"guardian_aegis":
			for x in [15, 105]:
				c.draw_rect(Rect2(x - 4, 31 - growth * 5, 8, 43 + growth * 5), stone)
				_rune(c, Vector2(x, 27), spirit, 6)
			c.draw_arc(Vector2(60, 72), 25 + growth * 7, PI, TAU, 28, spirit, 2)
			c.draw_line(Vector2(60, 73), Vector2(119, 73), spirit, 2)
		"guardian_possessed":
			c.draw_rect(Rect2(36, 26, 49, 47), stone)
			for i in range(growth):
				var x: float = 45 + i * 12
				c.draw_polyline(PackedVector2Array([Vector2(x, 28), Vector2(x - 5, 43), Vector2(x + 4, 53), Vector2(x - 3, 72)]), spirit, 2)
			c.draw_circle(Vector2(60, 40), 8, Color(SPIRIT, dim * 0.3))
		"ogre_earthshaker":
			for i in range(growth + 1):
				c.draw_polyline(PackedVector2Array([Vector2(60, 68), Vector2(23 + i * 25, 74), Vector2(12 + i * 29, 80)]), blood, 1.5)
			c.draw_rect(Rect2(89, 21 - growth * 4, 10 + growth * 3, 48 + growth * 4), stone)
			c.draw_line(Vector2(88, 29), Vector2(108, 29), metal, 2)
		"ogre_stonethrower":
			for i in range(growth + 2):
				c.draw_circle(Vector2(13 + i * 14, 67 - (i % 2) * 6), 7 + growth, stone)
			if growth >= 2:
				c.draw_polyline(PackedVector2Array([Vector2(81, 65), Vector2(99, 24), Vector2(115, 61)]), wood, 4)
				c.draw_arc(Vector2(99, 26), 9 + growth, 0, PI, 16, gold, 2)
		"ogre_maneater":
			c.draw_rect(Rect2(16, 59, 83, 9), wood)
			for x in [23, 90]:
				c.draw_line(Vector2(x, 65), Vector2(x, 77), wood, 4)
			for i in range(growth + 1):
				_bone(c, Vector2(29 + i * 17, 55), web)
			c.draw_arc(Vector2(99, 52), 12, 0, PI, 18, metal, 4)
		"war_hound_hellfire":
			for x in [14, 106]:
				c.draw_rect(Rect2(x - 5, 29 - growth * 5, 10, 46 + growth * 5), stone)
			for i in range(growth + 2):
				_flame(c, Vector2(16 + i * 20, 75), 6 + growth + pulse * 2, gold, blood)
		"war_hound_lycanthrope":
			c.draw_circle(Vector2(86, 20), 9 + growth * 3, web)
			c.draw_circle(Vector2(91, 17), 9 + growth * 3, INK)
			_gate(c, Rect2(9, 33, 25, 40), metal, growth)
			c.draw_line(Vector2(20, 49), Vector2(30, 61), metal, 3)
			c.draw_line(Vector2(20, 49), Vector2(14, 37), metal, 3)
		"war_hound_sapper_hunter":
			for i in range(growth + 1):
				var at := Vector2(17 + i * 24, 64)
				c.draw_rect(Rect2(at - Vector2(7, 13), Vector2(14, 17)), wood)
				c.draw_line(at + Vector2(-8, -3), at + Vector2(10, -11), metal, 2)
				c.draw_arc(at + Vector2(6, -9), 3, PI / 2, PI * 2, 10, metal, 2)
		"poison_fog_crypt":
			for i in range(growth + 1):
				var at := Vector2(15 + i * 25, 61)
				_barrel(c, at, stone, venom)
				c.draw_line(at + Vector2(4, -23), at + Vector2(11, -30), metal, 3)
			for i in range(7):
				c.draw_circle(Vector2(8 + i * 17, 73 + sin(clock + i) * 3), 11, Color(VENOM, dim * 0.16))
		"poison_spore_garden":
			for i in range(3 + growth * 2):
				var at := Vector2(10 + i * 12, 72 - (i % 2) * 11)
				c.draw_line(at, at + Vector2(0, -9 - growth * 3), web, 3)
				c.draw_arc(at + Vector2(0, -9 - growth * 3), 6 + growth, PI, TAU, 12, venom, 5)
				c.draw_circle(at + Vector2(2, -13 - growth * 3), 1.5, gold)
		"poison_distiller":
			for i in range(growth):
				_flask(c, Vector2(18 + i * 20, 65), venom, 1)
			c.draw_rect(Rect2(79, 17, 25, 53), stone)
			c.draw_rect(Rect2(83, 28, 17, 37), Color(VENOM, dim * 0.5))
			c.draw_polyline(PackedVector2Array([Vector2(26, 54), Vector2(26, 27), Vector2(91, 27)]), metal, 3)
		"mimic_false_treasury":
			for i in range(growth + 1):
				_chest(c, Vector2(17 + i * 25, 69 - (i % 2) * 5), wood, gold, false)
		"mimic_living_chamber":
			c.draw_polyline(PackedVector2Array([Vector2(5, 73), Vector2(8, 13), Vector2(60, 6), Vector2(112, 13), Vector2(115, 73)]), blood, 5 + growth * 2)
			for i in range(4 + growth * 2):
				var x: float = 13 + i * (94.0 / (3 + growth * 2))
				_tri(c, Vector2(x, 18), 4, 11, web)
			c.draw_circle(Vector2(60, 49), 10 + pulse * 2, blood)
			c.draw_line(Vector2(60, 57), Vector2(60, 79), Color("9b5262", dim), 12)
		"mimic_weapon_swap":
			_chest(c, Vector2(66, 70), wood, gold, true)
			for i in range(growth + 1):
				_sword(c, Vector2(16 + i * 14, 40), metal if i == 0 else Color("9b7caa", dim), 0.7)
		"mimic_cursed_gift":
			for i in range(growth + 1):
				_chest(c, Vector2(15 + i * 25, 73), wood, gold, false)
			c.draw_rect(Rect2(44, 53, 33, 22), stone)
			_cup(c, Vector2(61, 37), 1.0 + growth * 0.12, gold, growth)
		"wraith_twilight_hall":
			for x in [22, 98]:
				c.draw_rect(Rect2(x - 5, 15, 10, 60), stone)
			c.draw_arc(Vector2(60, 36), 31 + growth * 2, PI, TAU, 24, spirit, 4)
			for i in range(growth):
				c.draw_line(Vector2(36 + i * 13, 22), Vector2(43 + i * 13, 70), Color(SPIRIT, dim * 0.3), 5)
		"wraith_banshee":
			for i in range(growth + 1):
				_banner(c, Vector2(12 + i * 27, 9), Vector2(9, 48 + i % 2 * 12), Color("595261", dim), spirit)
			c.draw_arc(Vector2(66, 39), 12 + pulse * 9, -0.8, 0.8, 18, Color(SPIRIT, dim * 0.4), 2)
		"wraith_throne_guardian":
			c.draw_rect(Rect2(34, 58, 54, 15), stone)
			c.draw_rect(Rect2(43, 49, 36, 10), stone)
			_rune(c, Vector2(61, 32), spirit, 11 + growth * 3)
			for x in [29, 94]:
				c.draw_line(Vector2(x, 72), Vector2(x, 51), gold, 3)
				_flame(c, Vector2(x, 51), 6, spirit, web)
		"vampire_hypnotist":
			for x in [10, 90]:
				_banner(c, Vector2(x, 5), Vector2(23, 55 + growth * 4), blood.darkened(0.35), gold)
			for i in range(growth):
				_rune(c, Vector2(46 + i * 15, 23), blood, 5)
		"vampire_sire":
			_coffin(c, Rect2(12, 34, 26, 40), wood, blood)
			if growth >= 2:
				c.draw_line(Vector2(25, 40), Vector2(25, 57), gold, 2)
				c.draw_line(Vector2(18, 47), Vector2(32, 47), gold, 2)
			if growth == 3:
				_banner(c, Vector2(89, 6), Vector2(17, 52), blood, gold)
		"vampire_sarcophagus_master":
			_coffin(c, Rect2(34, 17, 50, 57), stone, blood)
			for i in range(growth):
				c.draw_line(Vector2(40, 29 + i * 15), Vector2(76, 38 + i * 12), blood, 2)
		"spikes_armour_press":
			c.draw_rect(Rect2(17, 11, 87, 9 + growth * 3), stone)
			for i in range(5 + growth):
				_tri(c, Vector2(23 + i * 10, 22), 4, 14 + growth * 2, metal)
			c.draw_rect(Rect2(22, 70, 75, 6), wood)
			for x in [11, 109]:
				_chain(c, Vector2(x, 6), Vector2(x, 70), metal)
		"spikes_collapsing_walkway":
			c.draw_rect(Rect2(8, 50, 105, 27), Color("0a1014"))
			for i in range(7):
				_tri(c, Vector2(16 + i * 14, 76), 5, -18, metal)
			for i in range(4 + growth):
				var x: float = 9 + i * 15
				c.draw_line(Vector2(x, 49), Vector2(x + 12, 49 + (9 if cleared and i > 0 else 0)), wood, 6)
		"spikes_blood_surge":
			c.draw_line(Vector2(8, 72), Vector2(113, 72), blood, 4)
			for i in range(4 + growth):
				_tri(c, Vector2(13 + i * 15, 71), 5, -19 - (i % 2) * growth * 7, metal)
				_rune(c, Vector2(13 + i * 15, 76), blood, 3)
		"shackles_shared_chain":
			for i in range(growth + 1):
				_chain(c, Vector2(14 + i * 31, 10), Vector2(28 + i * 28, 62), metal)
				c.draw_arc(Vector2(28 + i * 28, 66), 7, 0, TAU, 12, metal, 3)
		"shackles_prisoner_scales":
			c.draw_line(Vector2(60, 9), Vector2(60, 76), wood, 6)
			c.draw_line(Vector2(18, 23), Vector2(102, 23), gold, 4)
			for x in [29, 91]:
				_chain(c, Vector2(x, 23), Vector2(x, 46), metal)
				_gate(c, Rect2(x - 13, 45, 26, 22 + growth * 3), metal, growth)
		"shackles_garrison_gallery":
			_gate(c, Rect2(11, 14, 96, 59), metal, growth + 1)
			c.draw_line(Vector2(0, 68), Vector2(120, 68), wood, 5)
		"silence_black_mass":
			_chapel(c, growth, stone, spirit)
			c.draw_arc(Vector2(60, 54), 13, 0, PI, 14, gold, 4)
			c.draw_line(Vector2(60, 64), Vector2(60, 75), gold, 3)
		"silence_null_bell":
			c.draw_arc(Vector2(60, 42), 22 + growth * 5, 0, TAU, 32, web, 6)
			c.draw_arc(Vector2(60, 42), 15 + growth * 5, 0, TAU, 32, gold, 1)
			c.draw_line(Vector2(22, 76), Vector2(98, 76), web, 3)
		"silence_funeral_peal":
			_chapel(c, growth, stone, blood)
			for i in range(3 + growth):
				c.draw_line(Vector2(20 + i * 15, 75), Vector2(20 + i * 15, 62), web, 3)
			_banner(c, Vector2(52, 27), Vector2(16, 39), Color("292635"), gold)
		"rust_fracture_window":
			c.draw_rect(Rect2(29, 56, 62, 15), stone)
			for i in range(growth):
				var x: float = 27 + i * 27
				c.draw_polyline(PackedVector2Array([Vector2(x - 9, 20), Vector2(x + 4, 48), Vector2(x + 12, 17)]), metal, 3)
				_flame(c, Vector2(x, 73), 7, gold, blood)
		"rust_shard_chamber":
			_gear(c, Vector2(60, 45), 20 + growth * 5, metal, clock * 0.25)
			for i in range(3 + growth):
				var p := Vector2(60, 45) + Vector2.from_angle(i * TAU / (3 + growth)) * 40
				_tri(c, p, 4, 7, blood)
		"rust_reforging":
			c.draw_rect(Rect2(12, 27, 43, 46), stone)
			c.draw_arc(Vector2(33, 56), 12, PI, TAU, 16, blood, 7)
			c.draw_line(Vector2(35, 67), Vector2(86, 72), gold, 4)
			_shield(c, Vector2(90, 49), 13 + growth * 2, metal, gold)
		"ballista_clear_sight":
			var lift: float = growth * 11
			for x in [39, 88]:
				c.draw_line(Vector2(x, 76), Vector2(x, 69 - lift), wood, 5)
			c.draw_line(Vector2(33, 68 - lift), Vector2(97, 68 - lift), wood, 7)
			_ballista(c, Vector2(63, 57 - lift), 1.0, wood, metal)
			c.draw_line(Vector2(0, 53 - lift), Vector2(34, 53 - lift), Color(GOLD, dim * 0.3), 1)
		"ballista_reserve_magazine":
			c.draw_polyline(PackedVector2Array([Vector2(8, 73), Vector2(8, 27), Vector2(60, 8), Vector2(112, 27), Vector2(112, 73)]), wood, 5)
			var bolts: int = int(state.get("ammo", growth + 1))
			for i in range(mini(8, bolts)):
				_arrow(c, Vector2(15 + i * 7, 65), Vector2(15 + i * 7, 38), metal)
			_ballista(c, Vector2(80, 56), 0.7, wood, metal)
		"ballista_siege":
			_ballista(c, Vector2(60, 43), 1.1 + growth * 0.15, wood, metal)
			c.draw_rect(Rect2(88, 53, 17, 21), stone)
			_chain(c, Vector2(88, 53), Vector2(79, 25), metal)
		"blade_floor_blood_mill":
			for i in range(growth + 1):
				var x: float = 16 + i * 27
				c.draw_line(Vector2(x, 15), Vector2(x, 74), wood, 5)
				_gear(c, Vector2(x, 48), 12 + growth, metal, clock * (1 if i % 2 == 0 else -1))
		"blade_floor_partition_corridor":
			for i in range(growth + 1):
				_gate(c, Rect2(13 + i * 28, 23, 17, 51), metal, 2)
		"blade_floor_corpse_reclaimer":
			c.draw_rect(Rect2(52, 30, 52, 43), stone)
			_gear(c, Vector2(76, 49), 12 + growth * 3, metal, clock * 0.4)
			c.draw_line(Vector2(9, 56), Vector2(55, 70), wood, 8)
			for i in range(growth):
				_bone(c, Vector2(16 + i * 12, 53 + i * 4), web)
	_transform(c, Vector2.ZERO)


static func actor(c: CanvasItem, at: Vector2, scale_factor: float, path: String, phase: String, effects: Dictionary, clock: float) -> bool:
	# Return true only when this form replaces the base creature portrait.
	_transform(c, at, 0, Vector2.ONE * scale_factor)
	var drawn := true
	var spectral: bool = bool(effects.get("spirit", false))
	var pale := Color("c4d9f0", 0.5) if spectral else WEB
	var cold := Color("8f9ec7", 0.42)
	if phase == "spiderling":
		_spider(c, Vector2(0, -11), 0.64, Color("354f55"), Color("f3d27d"), clock)
		c.draw_arc(Vector2(0, -16), 8, PI * 0.9, TAU, 14, WEB, 1.2)
	elif phase in ["spirit", "throne_guard"]:
		_ghost(c, Vector2(0, -25), 1.0, SPIRIT)
		if phase == "throne_guard":
			_shield(c, Vector2(12, -16), 11, Color(SPIRIT, 0.4), GOLD)
	elif phase == "sarcophagus":
		_coffin(c, Rect2(-18, -47, 36, 47), STONE, BLOOD)
	elif phase == "appendage":
		_mouth(c, Vector2(0, -17), 17)
	elif path == "war_hound_lycanthrope" and bool(effects.get("transformed", false)):
		c.draw_colored_polygon(PackedVector2Array([Vector2(-14, 0), Vector2(-13, -28), Vector2(-20, -31), Vector2(-11, -36), Vector2(-10, -50), Vector2(-2, -44), Vector2(9, -47), Vector2(17, -32), Vector2(8, -27), Vector2(16, 0)]), cold if spectral else Color("9a817c"))
		for x in [-20, 20]:
			c.draw_line(Vector2(signf(x) * 10, -30), Vector2(x, -12), cold if spectral else STONE, 7)
			for j in range(3):
				c.draw_line(Vector2(x + j * 2, -12), Vector2(x + j * 2 - 2, -5), pale, 1.5)
		c.draw_circle(Vector2(5, -39), 2, pale if spectral else BLOOD)
	elif path == "war_hound_hellfire":
		c.draw_colored_polygon(PackedVector2Array([Vector2(-24, -12), Vector2(-18, -29), Vector2(13, -27), Vector2(26, -38), Vector2(30, -25), Vector2(22, -12)]), cold if spectral else Color("5b4943"))
		for x in [-16, 15]:
			c.draw_line(Vector2(x, -14), Vector2(x - 3, 1), cold if spectral else WOOD, 6)
		for j in range(3):
			_flame(c, Vector2(-10 + j * 10, -27), 7 + sin(clock * 4 + j) * 2, pale if spectral else GOLD, cold if spectral else BLOOD)
	elif path == "wraith_banshee":
		_ghost(c, Vector2(0, -24), 1, SPIRIT)
		c.draw_circle(Vector2(1, -31), 6, INK)
		c.draw_arc(Vector2(1, -31), 7, 0, TAU, 16, WEB, 1)
	elif path == "mimic_living_chamber":
		_mouth(c, Vector2(0, -20), 20)
	elif path in ["venom_hunter", "cocoon_weaver", "brood_mother"]:
		var body: Color = Color("a4aaa0") if path == "cocoon_weaver" else Color("72886e")
		var detail: Color = VENOM if path == "venom_hunter" else WEB
		if bool(effects.get("spirit", false)):
			body = Color(SPIRIT, 0.45)
			detail = Color(WEB, 0.6)
		_spider(c, Vector2(0, -17), 0.95 if path != "brood_mother" else 1.2, body, detail, clock)
		if path == "venom_hunter":
			for x in [-9, 9]:
				c.draw_circle(Vector2(x, -23), 5, VENOM)
	else:
		drawn = false
	_transform(c, Vector2.ZERO)
	return drawn


static func hero_equipment(c: CanvasItem, at: Vector2, scale_factor: float, equipment: Dictionary, effects: Dictionary, clock: float) -> void:
	_transform(c, at, 0, Vector2.ONE * scale_factor)
	var weapon: String = str(equipment.get("weapon", ""))
	var protection: String = str(equipment.get("protection", ""))
	var metal: Color = Color("a579b2") if bool(effects.get("weapon_swap", false)) else STEEL
	if bool(effects.get("weapon_swap", false)):
		# An unmistakable crooked living counterfeit replaces every weapon shape.
		c.draw_polyline(PackedVector2Array([Vector2(13, 0), Vector2(16, -12), Vector2(12, -22), Vector2(20, -34)]), Color("a579b2"), 4)
		c.draw_line(Vector2(8, -12), Vector2(22, -10), WOOD, 3)
		for j in range(3):
			_tri(c, Vector2(14 + j * 2, -23 - j * 4), 2.5, 4, WEB)
	elif "staff" in weapon:
		c.draw_line(Vector2(13, -2), Vector2(13, -37), WOOD, 2.5)
		_rune(c, Vector2(13, -39), SPIRIT, 5)
		if bool(effects.get("stored_spell", false)):
			c.draw_circle(Vector2(13, -39), 8, Color(SPIRIT, 0.25 + sin(clock * 4) * 0.1))
	elif "crossbow" in weapon or "bow" in weapon:
		c.draw_arc(Vector2(16, -15), 10, -PI * 0.5, PI * 0.5, 12, WOOD, 2.5)
		c.draw_line(Vector2(16, -25), Vector2(16, -5), WEB, 1)
		_arrow(c, Vector2(9, -15), Vector2(29, -15), metal)
	elif "drum" in weapon or "rhythm" in weapon:
		_drum(c, Vector2(14, -9), 8, WOOD, GOLD)
	elif "lute" in weapon:
		c.draw_circle(Vector2(13, -13), 7, WOOD)
		c.draw_line(Vector2(13, -13), Vector2(22, -33), WOOD, 4)
		for i in range(3):
			c.draw_line(Vector2(11 + i, -9), Vector2(21 + i, -33), GOLD, 0.7)
	elif "mace" in weapon:
		c.draw_line(Vector2(12, 0), Vector2(17, -26), WOOD, 3)
		c.draw_circle(Vector2(18, -29), 5, metal)
		_rune(c, Vector2(18, -29), GOLD, 6)
	elif "axe" in weapon or "splitter" in weapon:
		c.draw_line(Vector2(12, 0), Vector2(18, -34), WOOD, 3)
		c.draw_colored_polygon(PackedVector2Array([Vector2(17, -33), Vector2(29, -35), Vector2(27, -22), Vector2(17, -25)]), metal)
	elif not weapon.is_empty():
		_sword(c, Vector2(15, -15), metal, 0.65)
	if "shield" in protection:
		_shield(c, Vector2(-11, -15), 9, Color("526a73"), GOLD if "cover" in protection else STEEL)
	elif "prayer" in protection or "charm" in protection or "amulet" in protection:
		_rune(c, Vector2(1, -19), GOLD, 3)
	elif "hide" in protection:
		c.draw_arc(Vector2(0, -22), 11, PI, TAU, 9, WOOD, 4)
	elif "cloak" in protection or "mantle" in protection or "robe" in protection:
		c.draw_polyline(PackedVector2Array([Vector2(-11, -23), Vector2(-13, 0), Vector2(-4, -5)]), SPIRIT if "mantle" in protection else GOLD.darkened(0.2), 2)
	elif not protection.is_empty():
		c.draw_arc(Vector2(0, -22), 11, PI, TAU, 12, SPIRIT if "robe" in protection else STEEL, 2)
	if bool(effects.get("weapon_swap", false)):
		c.draw_line(Vector2(8, -34), Vector2(22, -4), BLOOD, 1.3)
	if int(effects.get("cocoon_ticks", 0)) > 0:
		_cocoon(c, Vector2(0, -19), 15, WEB)
		var remaining: float = float(effects.get("cocoon_ticks", 0)) / maxf(1, float(effects.get("cocoon_total", 4)))
		c.draw_rect(Rect2(-14, -43, 28, 3), INK)
		c.draw_rect(Rect2(-14, -43, 28 * remaining, 3), WEB)
	if not str(effects.get("hypnotized_by", "")).is_empty():
		_rune(c, Vector2(0, -41), BLOOD, 8)
	if bool(effects.get("has_spore", false)) or int(effects.get("spore_attacks", 0)) > 0:
		c.draw_circle(Vector2(-8, -22), 5 + sin(clock * 3), VENOM)
	if bool(effects.get("forced_front", false)):
		_chain(c, Vector2(3, -14), Vector2(25, -12), BLOOD)
	if bool(effects.get("cover_active", false)):
		c.draw_arc(Vector2(0, -18), 23, -PI * 0.7, PI * 0.7, 22, STEEL, 2)
	if effects.has("cursed_cup"):
		var cup: Dictionary = effects.cursed_cup
		_cup(c, Vector2(-17, -12), 0.45, GOLD, int(cup.get("uses", 0)))
		for i in range(int(cup.get("uses_to_bite", 3))):
			c.draw_circle(Vector2(-23 + i * 4, 1), 1.2, BLOOD if i < int(cup.get("uses", 0)) else GOLD)
	_transform(c, Vector2.ZERO)


static func _spider(c: CanvasItem, p: Vector2, s: float, body: Color, accent: Color, clock: float) -> void:
	for side in [-1, 1]:
		for i in range(4):
			var joint := p + Vector2(side * (17 + i * 2), -9 + i * 5) * s
			var foot := p + Vector2(side * (26 + i), -12 + i * 10 + sin(clock * 2 + i) * 1.5) * s
			c.draw_polyline(PackedVector2Array([p, joint, foot]), body, 2.8 * s)
	c.draw_circle(p + Vector2(0, -8) * s, 13 * s, body)
	c.draw_circle(p + Vector2(0, 5) * s, 8 * s, body.lightened(0.1))
	for x in [-4, 4]:
		c.draw_circle(p + Vector2(x, 5) * s, 2 * s, accent)
		c.draw_line(p + Vector2(x, 10) * s, p + Vector2(x * 1.5, 16) * s, accent, 2 * s)


static func _cocoon(c: CanvasItem, p: Vector2, radius: float, color: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -radius * 1.5), p + Vector2(radius, -radius * 0.6), p + Vector2(radius * 0.8, radius), p + Vector2(0, radius * 1.5), p + Vector2(-radius * 0.8, radius), p + Vector2(-radius, -radius * 0.6)]), Color(color, 0.78))
	for i in range(6):
		var y: float = -radius + i * radius * 0.4
		c.draw_line(p + Vector2(-radius * 0.7, y), p + Vector2(radius * 0.7, y + radius * 0.3), color, 1)


static func _web(c: CanvasItem, p: Vector2, span: float, color: Color) -> void:
	for i in range(5):
		c.draw_line(p, p + Vector2(-cos(i * PI / 8), sin(i * PI / 8)) * span, Color(color, 0.4), 1)
	for r in [0.4, 0.7, 1.0]:
		c.draw_arc(p, span * r, PI * 0.5, PI, 14, Color(color, 0.5), 1)


static func _tri(c: CanvasItem, p: Vector2, half_width: float, height: float, color: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-half_width, 0), p + Vector2(half_width, 0), p + Vector2(0, height)]), color)


static func _rune(c: CanvasItem, p: Vector2, color: Color, radius: float) -> void:
	c.draw_polyline(PackedVector2Array([p + Vector2(0, -radius), p + Vector2(radius * 0.65, 0), p + Vector2(0, radius), p + Vector2(-radius * 0.65, 0), p + Vector2(0, -radius)]), color, 1.8)
	c.draw_line(p + Vector2(0, -radius), p + Vector2(0, radius), color, 1)


static func _flask(c: CanvasItem, p: Vector2, color: Color, s: float) -> void:
	c.draw_circle(p + Vector2(0, -7) * s, 7 * s, Color(color, 0.45))
	c.draw_arc(p + Vector2(0, -7) * s, 7 * s, 0, TAU, 16, color, 1.5)
	c.draw_line(p + Vector2(0, -20) * s, p + Vector2(0, -12) * s, STEEL, 4 * s)


static func _shield(c: CanvasItem, p: Vector2, r: float, color: Color, edge: Color) -> void:
	var points := PackedVector2Array([p + Vector2(-r * 0.7, -r), p + Vector2(r * 0.7, -r), p + Vector2(r * 0.6, r * 0.3), p + Vector2(0, r), p + Vector2(-r * 0.6, r * 0.3)])
	c.draw_colored_polygon(points, color)
	points.append(points[0])
	c.draw_polyline(points, edge, 1.5)


static func _sword(c: CanvasItem, p: Vector2, color: Color, s: float) -> void:
	c.draw_line(p + Vector2(0, 14) * s, p + Vector2(0, -23) * s, color, 3 * s)
	c.draw_line(p + Vector2(-6, 5) * s, p + Vector2(6, 5) * s, GOLD, 2 * s)


static func _banner(c: CanvasItem, p: Vector2, size: Vector2, color: Color, edge: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p, p + Vector2(size.x, 0), p + size, p + Vector2(size.x / 2, size.y - 7), p + Vector2(0, size.y)]), color)
	c.draw_line(p - Vector2(3, 0), p + Vector2(size.x + 3, 0), edge, 2)
	_rune(c, p + size * Vector2(0.5, 0.4), edge, size.x * 0.25)


static func _tent(c: CanvasItem, p: Vector2, color: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p, p + Vector2(13, -25), p + Vector2(29, 0)]), color)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(8, 0), p + Vector2(13, -17), p + Vector2(19, 0)]), INK)


static func _drum(c: CanvasItem, p: Vector2, r: float, color: Color, edge: Color) -> void:
	c.draw_rect(Rect2(p + Vector2(-r, -r), Vector2(r * 2, r * 1.5)), color)
	c.draw_line(p + Vector2(-r, -r), p + Vector2(r, -r), edge, 3)
	c.draw_line(p + Vector2(-r, r * 0.5), p + Vector2(r, r * 0.5), edge, 2)


static func _barrel(c: CanvasItem, p: Vector2, color: Color, edge: Color) -> void:
	c.draw_rect(Rect2(p - Vector2(8, 23), Vector2(16, 23)), color)
	for y in [-19, -5]:
		c.draw_line(p + Vector2(-9, y), p + Vector2(9, y), edge, 2)


static func _gate(c: CanvasItem, rect: Rect2, color: Color, bars: int) -> void:
	c.draw_rect(rect, color, false, 2)
	for i in range(bars + 2):
		var x: float = rect.position.x + rect.size.x * (i + 1) / (bars + 3)
		c.draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), color, 2)


static func _bone(c: CanvasItem, p: Vector2, color: Color) -> void:
	c.draw_line(p + Vector2(-6, -2), p + Vector2(6, 2), color, 3)
	for x in [-6, 6]:
		c.draw_circle(p + Vector2(x, x / 3.0), 3, color)


static func _flame(c: CanvasItem, p: Vector2, r: float, inner: Color, outer: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-r, 0), p + Vector2(-r * 0.6, -r), p + Vector2(0, -r * 2), p + Vector2(r * 0.6, -r), p + Vector2(r, 0)]), outer)
	_tri(c, p, r * 0.5, -r * 1.4, inner)


static func _chest(c: CanvasItem, p: Vector2, wood: Color, edge: Color, teeth: bool) -> void:
	c.draw_rect(Rect2(p - Vector2(13, 22), Vector2(26, 22)), wood)
	c.draw_line(p + Vector2(-13, -13), p + Vector2(13, -13), edge, 3)
	for x in [-8, 8]:
		c.draw_line(p + Vector2(x, -22), p + Vector2(x, 0), edge, 2)
	if teeth:
		for x in [-8, 0, 8]:
			_tri(c, p + Vector2(x, -13), 3, 7, WEB)


static func _cup(c: CanvasItem, p: Vector2, s: float, color: Color, teeth: int) -> void:
	c.draw_arc(p, 9 * s, 0, PI, 18, color, 3 * s)
	c.draw_line(p + Vector2(-10, 0) * s, p + Vector2(10, 0) * s, color, 2 * s)
	c.draw_line(p + Vector2(0, 9) * s, p + Vector2(0, 17) * s, color, 3 * s)
	c.draw_line(p + Vector2(-6, 17) * s, p + Vector2(6, 17) * s, color, 2 * s)
	for i in range(mini(3, teeth)):
		_tri(c, p + Vector2(-6 + i * 6, 0) * s, 2 * s, 5 * s, WEB)


static func _coffin(c: CanvasItem, rect: Rect2, color: Color, edge: Color) -> void:
	var p := rect.position
	var s := rect.size
	var points := PackedVector2Array([p + s * Vector2(0.2, 0), p + s * Vector2(0.8, 0), p + s * Vector2(1, 0.2), p + s * Vector2(0.8, 1), p + s * Vector2(0.2, 1), p + s * Vector2(0, 0.2)])
	c.draw_colored_polygon(points, color)
	points.append(points[0])
	c.draw_polyline(points, edge, 2)


static func _chain(c: CanvasItem, a: Vector2, b: Vector2, color: Color) -> void:
	var count: int = maxi(2, mini(20, int(a.distance_to(b) / 6)))
	for i in range(count + 1):
		c.draw_arc(a.lerp(b, float(i) / count), 3, 0, TAU, 8, color, 1)


static func _chapel(c: CanvasItem, growth: int, stone: Color, glow: Color) -> void:
	c.draw_polyline(PackedVector2Array([Vector2(29, 75), Vector2(29, 31), Vector2(60, 8), Vector2(91, 31), Vector2(91, 75)]), stone, 5 + growth)
	c.draw_line(Vector2(60, 15), Vector2(60, 28), glow, 2)
	c.draw_arc(Vector2(60, 39), 12, PI, TAU, 16, glow, 5)
	c.draw_line(Vector2(46, 40), Vector2(74, 40), glow, 4)


static func _gear(c: CanvasItem, p: Vector2, r: float, color: Color, angle: float) -> void:
	c.draw_circle(p, r * 0.77, color.darkened(0.3))
	c.draw_arc(p, r * 0.78, 0, TAU, 20, color, 2)
	for i in range(12):
		var d := Vector2.from_angle(i * TAU / 12 + angle)
		c.draw_line(p + d * r * 0.72, p + d * r, color, 3)
	c.draw_circle(p, r * 0.2, INK)


static func _arrow(c: CanvasItem, a: Vector2, b: Vector2, color: Color) -> void:
	c.draw_line(a, b, color, 2)
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	c.draw_colored_polygon(PackedVector2Array([b + d * 3, b - d * 5 + n * 3, b - d * 5 - n * 3]), color)


static func _ballista(c: CanvasItem, p: Vector2, s: float, wood: Color, metal: Color) -> void:
	c.draw_polyline(PackedVector2Array([p + Vector2(-27, -15) * s, p + Vector2(-34, 0) * s, p + Vector2(-27, 15) * s]), wood, 5 * s)
	c.draw_line(p + Vector2(-27, -15) * s, p + Vector2(12, 0) * s, WEB, 1)
	c.draw_line(p + Vector2(-27, 15) * s, p + Vector2(12, 0) * s, WEB, 1)
	c.draw_line(p + Vector2(-30, 0) * s, p + Vector2(28, 0) * s, wood, 6 * s)
	_arrow(c, p + Vector2(15, 0) * s, p + Vector2(-43, 0) * s, metal)
	for x in [-12, 17]:
		c.draw_line(p + Vector2(x, 2) * s, p + Vector2(x, 21) * s, wood, 4 * s)


static func _ghost(c: CanvasItem, p: Vector2, s: float, color: Color) -> void:
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-17, 22) * s, p + Vector2(-13, -12) * s, p + Vector2(0, -21) * s, p + Vector2(13, -12) * s, p + Vector2(17, 22) * s, p + Vector2(7, 14) * s, p + Vector2(0, 23) * s, p + Vector2(-7, 14) * s]), Color(color, 0.6))
	for x in [-5, 5]:
		c.draw_circle(p + Vector2(x, -7) * s, 2 * s, WEB)


static func _mouth(c: CanvasItem, p: Vector2, radius: float) -> void:
	c.draw_circle(p, radius, BLOOD.darkened(0.4))
	c.draw_circle(p, radius * 0.75, INK)
	for i in range(5):
		var x: float = (i - 2) * radius * 0.3
		_tri(c, p + Vector2(x, -radius * 0.65), radius * 0.11, radius * 0.5, WEB)
		_tri(c, p + Vector2(x, radius * 0.65), radius * 0.11, -radius * 0.5, WEB)


static func _transform(c: CanvasItem, at: Vector2, rotation: float = 0.0, scale_factor: Vector2 = Vector2.ONE) -> void:
	# Keep the host camera when a form draws in its own local coordinates.
	if c.has_method("_visual_transform"):
		c.call("_visual_transform", at, rotation, scale_factor)
	else:
		c.draw_set_transform(at, rotation, scale_factor)
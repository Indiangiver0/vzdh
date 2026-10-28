extends RefCounted
## Camp-only arithmetic: no combat reactions, RNG, status cleanup, or timers.

const HeroRules = preload("res://scripts/hero_rules.gd")
const DEFAULT_DURATION: int = 10
const HEAL_PERCENT_PER_PULSE: int = 5
const ROUNDING_EPSILON: float = 0.000000001


static func duration(learned: Dictionary) -> int:
	if bool(learned.get("shared_restless_dungeons_3", false)):
		return 5
	if bool(learned.get("shared_restless_dungeons_2", false)):
		return 6
	if bool(learned.get("shared_restless_dungeons_1", false)):
		return 8
	return DEFAULT_DURATION


static func healing_factor(hero: Dictionary, party: Array[Dictionary], caustic_vapors: bool) -> float:
	if int(hero.get("poison_ticks", 0)) <= 0:
		return 1.0
	var factor: float = 0.5
	for ally in party:
		if int(ally.get("hp", 0)) <= 0 or str(ally.get("id", "")) != "priest":
			continue
		var protection: float = 0.95 if HeroRules.is_developed_priest(ally) and not caustic_vapors else 0.9
		factor = maxf(factor, protection)
	# The existing plague-room penalty is a separate stronger restriction.
	# Bitter Medicine is a combat reaction and is deliberately not called here.
	return clampf(minf(factor, float(hero.get("poison_heal_factor", 1.0))), 0.0, 1.0)


static func pulse_power(hero: Dictionary, factor: float) -> float:
	return float(maxi(0, int(hero.get("max_hp", 0))) * HEAL_PERCENT_PER_PULSE) * factor / 100.0


static func whole_hp(exact: float) -> int:
	return maxi(0, floori(exact + ROUNDING_EPSILON))


static func remaining_healing(hero: Dictionary, carry: float, pulses: int, factor: float) -> int:
	if int(hero.get("hp", 0)) <= 0 or pulses <= 0:
		return 0
	var missing: int = maxi(0, int(hero.get("max_hp", 0)) - int(hero.hp))
	return mini(missing, whole_hp(carry + pulse_power(hero, factor) * float(pulses)))

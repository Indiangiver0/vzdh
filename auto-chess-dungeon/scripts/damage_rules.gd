extends RefCounted
## Pure damage arithmetic. Multipliers never depend on rendering time.

static func hero_hit(raw: float, armor: int, damage_type: String = "physical", bypass: bool = false) -> int:
	var hit: int = maxi(0, ceili(raw))
	if hit == 0:
		return 0
	if damage_type == "physical" and not bypass:
		hit -= mini(maxi(0, armor), floori(float(hit) * 0.5))
	return maxi(1, hit)


static func defender_hit(raw: float, armor: int, tags: PackedStringArray, damage_type: String, bypass: int = 0) -> int:
	return maxi(0, ceili(defender_raw(raw, armor, tags, damage_type, bypass)))


static func defender_raw(raw: float, armor: int, tags: PackedStringArray, damage_type: String, bypass: int = 0) -> float:
	if raw <= 0.0:
		return 0
	var hit: float = raw
	if damage_type == "physical":
		hit = maxf(1.0, ceili(hit) - maxi(0, armor - bypass))
	elif damage_type == "magic":
		hit = maxf(1.0, ceili(hit) - maxi(0, armor - bypass))
	if tags.has("spirit"):
		hit *= 0.2 if damage_type == "physical" else (1.5 if damage_type == "magic" else 1.0)
	return maxf(1.0, hit)

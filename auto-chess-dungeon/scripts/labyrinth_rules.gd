extends RefCounted
## Grid topology and private, seeded exploration memory. No scene dependencies.
## Initial size and cell price are prototype parameters, not measured balance.
const INITIAL_SIZE: Vector2i = Vector2i(3, 3)
const STARTING_GOLD: int = 100
const LAYER_HEIGHT: int = 3
const EXPANSION_BASE_COST: int = 4
const DEPTH_ACCESS_BASE_FACTOR: int = 5
const DISARM_CHANCE: float = 0.5
const DEPARTURE_MIN: float = 0.25
const DEPARTURE_MAX: float = 0.75
const LOW_HP_FRACTION: float = 0.30
# Recognition tuning defaults; not an approved final balance.
const MIMIC_RECOGNITION_BASE: float = 0.20
const MIMIC_OBSERVATION_WEIGHT: float = 0.50
const MIMIC_LEVEL_BONUS: float = 0.02
const MIMIC_RECOGNITION_CAP: float = 0.95
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]

var positions: Array[Vector2i] = []
var boundaries: Dictionary = {}
var entrance_position: Vector2i = Vector2i(-1, 1)
var entrance_slot: int = -1
var treasury_slot: int = -1
var throne_slot: int = -1
var roster_ids: Array[String] = []
var _characters: Dictionary = {}
var _mimic_recognition: Dictionary = {}
var _revealed_mimics: Dictionary = {}
var _crossed: Dictionary = {}
var _trail: Array[int] = [-1]
var _entered: bool = false
var _route_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _disarm_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _recognition_rng: RandomNumberGenerator = RandomNumberGenerator.new()


func reset_layout(empty: bool = true) -> void:
	positions.clear()
	boundaries.clear()
	entrance_position = Vector2i(-1, 1)
	entrance_slot = -1
	treasury_slot = -1
	throne_slot = -1
	if empty:
		return
	# Retained only for explicitly authored layouts; normal runs start at the entrance.
	entrance_slot = 3
	treasury_slot = 2
	throne_slot = 8
	for y in range(INITIAL_SIZE.y):
		for x in range(INITIAL_SIZE.x):
			positions.append(Vector2i(x, y))
	for slot in range(positions.size()):
		for other in range(slot):
			if adjacent(positions[slot], positions[other]):
				_add_boundary(slot, other, false)
	_add_boundary(-1, entrance_slot, true)
	# A visible fork at the centre, a treasury branch and a separate throne branch.
	for pair in [[3, 4], [4, 1], [1, 0], [1, 2], [4, 5], [5, 8], [4, 7], [7, 6]]:
		boundaries[boundary_key(int(pair[0]), int(pair[1]))].open = true


static func adjacent(a: Vector2i, b: Vector2i) -> bool:
	return absi(a.x - b.x) + absi(a.y - b.y) == 1


static func boundary_key(a: int, b: int) -> String:
	return "edge:%d:%d" % [mini(a, b), maxi(a, b)]


func _add_boundary(a: int, b: int, opened: bool) -> void:
	var key: String = boundary_key(a, b)
	boundaries[key] = {"id": key, "a": mini(a, b), "b": maxi(a, b), "open": opened}


func expansion_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if positions.is_empty():
		result.append(entrance_position + Vector2i.RIGHT)
		return result
	for position in positions:
		for direction in DIRECTIONS:
			var candidate: Vector2i = position + direction
			if candidate.y >= 0 and candidate != entrance_position and not positions.has(candidate) and not result.has(candidate):
				result.append(candidate)
	return result


func append_cell(position: Vector2i) -> int:
	if not expansion_cells().has(position):
		return -1
	var slot: int = positions.size()
	positions.append(position)
	if entrance_slot < 0:
		entrance_slot = slot
		_add_boundary(-1, slot, true)
	for other in range(slot):
		if adjacent(position, positions[other]):
			_add_boundary(slot, other, true)
	return slot


func neighbors(slot: int) -> Array[int]:
	var result: Array[int] = []
	for boundary in boundaries.values():
		if not bool(boundary.open):
			continue
		var other: int = -2
		if int(boundary.a) == slot:
			other = int(boundary.b)
		elif int(boundary.b) == slot:
			other = int(boundary.a)
		if other >= -1 and not result.has(other):
			result.append(other)
	result.sort()
	return result


func _reachable(target: int, blocked: int = -2) -> bool:
	var seen: Dictionary = {-1: true}
	var queue: Array[int] = [-1]
	var cursor: int = 0
	while cursor < queue.size():
		var slot: int = queue[cursor]
		cursor += 1
		if slot == target:
			return true
		for other in neighbors(slot):
			if other != blocked and not seen.has(other):
				seen[other] = true
				queue.append(other)
	return false


func validation_error(room_count: int) -> String:
	if room_count != positions.size():
		return "Планировка не соответствует построенным местам."
	if positions.is_empty():
		return "Раскопайте клетки и бесплатно установите казну и трон."
	if treasury_slot < 0 or treasury_slot >= room_count:
		return "Разместите настоящую казну."
	if throne_slot < 0 or throne_slot >= room_count or throne_slot == treasury_slot:
		return "Трону и казне нужны отдельные места."
	if not _reachable(throne_slot):
		return "Откройте путь от входа к трону."
	if not _reachable(treasury_slot):
		return "Откройте путь от входа к казне."
	if not _reachable(treasury_slot, throne_slot):
		return "Казна должна быть доступна без прохода через трон."
	return ""


func begin_wave(seed_value: int, wave: int, heroes: Array[Dictionary]) -> void:
	_route_rng.seed = seed_value ^ 0x1AB71A7 ^ (wave * 8191)
	_disarm_rng.seed = seed_value ^ 0xD15A4 ^ (wave * 65537)
	_recognition_rng.seed = seed_value ^ 0xA11CE ^ (wave * 104729)
	roster_ids.clear()
	_characters.clear()
	_mimic_recognition.clear()
	_revealed_mimics.clear()
	_crossed.clear()
	_trail.assign([-1])
	_entered = false
	for hero in heroes:
		var uid: String = str(hero.instance_id)
		roster_ids.append(uid)
		_characters[uid] = {"greed": _route_rng.randf(), "caution": _route_rng.randf(), "observation": _route_rng.randf()}


func _mean_character(heroes: Array[Dictionary], key: String) -> float:
	var total: float = 0.0
	var count: int = 0
	for hero in heroes:
		if int(hero.hp) <= 0 or bool(hero.get("escaped", false)):
			continue
		total += float(_characters.get(str(hero.instance_id), {}).get(key, 0.5))
		count += 1
	return total / float(count) if count > 0 else 0.5


func departure_roll(heroes: Array[Dictionary]) -> bool:
	# Each survivor contributes equally; the private character is never in hero UI data.
	var inclination: float = _mean_character(heroes, "greed")
	return _route_rng.randf() < lerpf(DEPARTURE_MIN, DEPARTURE_MAX, clampf(inclination, 0.0, 1.0))


func disarm_roll() -> bool:
	return _disarm_rng.randf() < DISARM_CHANCE


func next_place(g, current: int, returning: bool) -> int:
	if not _entered:
		_entered = true
		_crossed[boundary_key(-1, entrance_slot)] = true
		_trail.append(entrance_slot)
		return entrance_slot
	if returning:
		if _trail.size() <= 1:
			return -1
		_trail.pop_back()
		return _trail.back()
	var candidates: Array[int] = []
	for other in neighbors(current):
		if other >= 0 and not _crossed.has(boundary_key(current, other)):
			candidates.append(other)
	if not candidates.is_empty():
		# Only adjacent rooms contribute. No reachability or shortest path lookup here.
		var weights: Array[float] = []
		var total: float = 0.0
		var greed: float = _mean_character(g.heroes, "greed")
		var caution: float = _mean_character(g.heroes, "caution")
		for other in candidates:
			var weight: float = 1.0
			if other == treasury_slot:
				weight += 3.0 * greed
			elif is_false_treasury(g, other):
				weight = 1.0 - caution * 0.6 if _recognize_mimic(g, other) else 1.0 + 3.0 * greed
			elif other == throne_slot:
				weight = 1.2 - caution
			elif not g.rooms[other].is_empty():
				weight = 1.0 - caution * 0.6
			weights.append(weight)
			total += weight
		var roll: float = _route_rng.randf() * total
		var chosen: int = candidates.back()
		for index in range(candidates.size()):
			roll -= weights[index]
			if roll < 0.0:
				chosen = candidates[index]
				break
		_crossed[boundary_key(current, chosen)] = true
		_trail.append(chosen)
		return chosen
	# Exhausted places backtrack along their actual traversal stack. Each edge is
	# explored once, then retraced at most once; a ring cannot cause an infinite walk.
	if _trail.size() > 1:
		_trail.pop_back()
		return _trail.back()
	return -1


func copy_layout_to(target) -> void:
	target.positions.assign(positions)
	target.boundaries = boundaries.duplicate(true)
	target.entrance_position = entrance_position
	target.entrance_slot = entrance_slot
	target.treasury_slot = treasury_slot
	target.throne_slot = throne_slot


func distances_from_entrance() -> Dictionary:
	# Structural effects/validation only. The private route chooser never reads this.
	var result: Dictionary = {-1: 0}
	var queue: Array[int] = [-1]
	var cursor: int = 0
	while cursor < queue.size():
		var slot: int = queue[cursor]
		cursor += 1
		for other in neighbors(slot):
			if not result.has(other):
				result[other] = int(result[slot]) + 1
				queue.append(other)
	return result


func is_false_treasury(g, slot: int) -> bool:
	return slot >= 0 and slot < g.rooms.size() and str(g.rooms[slot].get("id", "")) == "mimic" and str(g.rooms[slot].get("evolution_path", "")) == "mimic_false_treasury"


func _recognize_mimic(g, slot: int) -> bool:
	var identity: int = int(g.rooms[slot].instance_id)
	if _revealed_mimics.has(identity):
		return true
	if _mimic_recognition.has(identity):
		return bool(_mimic_recognition[identity])
	var level_total: float = 0.0
	var count: int = 0
	for hero in g._living():
		level_total += float(hero.level)
		count += 1
	var mean_level: float = level_total / float(count) if count > 0 else 1.0
	var probability: float = clampf(MIMIC_RECOGNITION_BASE + MIMIC_OBSERVATION_WEIGHT * _mean_character(g.heroes, "observation") + MIMIC_LEVEL_BONUS * maxf(0.0, mean_level - 1.0), 0.0, MIMIC_RECOGNITION_CAP)
	var recognized: bool = _recognition_rng.randf() < probability
	_mimic_recognition[identity] = recognized
	if recognized:
		g._log("Отряд замечает подвох в соседней сокровищнице и относится к ней осторожнее.")
	return recognized


func reveal_mimic(instance_id: int) -> bool:
	if _revealed_mimics.has(instance_id):
		return false
	_revealed_mimics[instance_id] = true
	return true


static func depth_access_base_cost(next_layer: int) -> int:
	return DEPTH_ACCESS_BASE_FACTOR * next_layer * next_layer

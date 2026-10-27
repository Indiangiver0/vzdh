extends RefCounted
## Approved run skills, global for all eligible rooms in the current run.
## Layout and prerequisites follow the selected snowflake; effect values retain
## the approved catalog. Reads return independent copies and never mutate a run.

const DATA_PATH: String = "res://data/run_skills.json"
const MODIFIER_KEYS: Array[String] = [
	"monster_hp", "monster_damage", "direct_trap_damage", "poison_damage",
	"lord_hp", "lord_damage", "lord_armor",
]

static var _loaded: bool = false
static var _skills: Array[Dictionary] = []
static var _by_id: Dictionary = {}


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var file: FileAccess = FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		push_error("Run skill catalog is unavailable: %s" % DATA_PATH)
		return
	var document: Variant = JSON.parse_string(file.get_as_text())
	if not document is Dictionary:
		push_error("Run skill catalog must contain a JSON object")
		return
	for value: Variant in document.get("skills", []):
		if not value is Dictionary:
			continue
		var definition: Dictionary = value.duplicate(true)
		var id: String = str(definition.get("id", ""))
		if id.is_empty() or _by_id.has(id):
			push_error("Invalid or duplicate run skill ID: %s" % id)
			continue
		definition.position = Vector2(float(definition.get("x", 0.0)), float(definition.get("y", 0.0)))
		_skills.append(definition)
		_by_id[id] = definition


static func all_skills() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	result.assign(_skills.duplicate(true))
	return result


static func get_skill(id: String) -> Dictionary:
	_ensure_loaded()
	return _by_id[id].duplicate(true) if _by_id.has(id) else {}


static func get_number(id: String, key: String, fallback: float = 0.0) -> float:
	# Numeric combat reads do not need a deep copy of the immutable description.
	_ensure_loaded()
	return float(_by_id[id].get(key, fallback)) if _by_id.has(id) else fallback


static func modifiers(learned: Dictionary) -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = {}
	for key: String in MODIFIER_KEYS:
		result[key] = 0.0
	for id: Variant in learned:
		if not bool(learned[id]) or not _by_id.has(str(id)):
			continue
		var bonuses: Dictionary = _by_id[str(id)].get("modifiers", {})
		for key: Variant in bonuses:
			result[str(key)] = float(result.get(str(key), 0.0)) + float(bonuses[key])
	# Conditional, ordinary-attack-only and tradeoff effects are applied by the
	# simulation at their own event, exactly once; this function only sums the
	# explicit approved modifiers shared by every eligible actor.
	return result

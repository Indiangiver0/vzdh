class_name RoomDefinition
extends Resource
## Immutable room preset. Runtime HP and upgrades belong to the run state.

@export var id: String = ""
@export var display_name: String = ""
@export var short_name: String = ""
@export_multiline var description: String = ""
@export var cost: int = 0
@export_enum("monster", "poison", "spikes", "shackles", "silence", "rust") var kind: String = "monster"
## Combat traits are independent of faction and may overlap.
@export var tags: PackedStringArray = PackedStringArray()
@export var hp: int = 0
@export var damage: int = 0
@export var armor: int = 0
@export var xp: int = 0
@export var item: String = ""
## Base duration in combat ticks and strength for the control traps.
@export var effect_turns: int = 0
@export var effect_power: float = 0.0
@export var color: Color = Color.WHITE
@export_file("*.svg") var icon: String = ""

func to_dictionary() -> Dictionary:
	return {
		"id": id, "name": display_name, "short_name": short_name,
		"description": description, "cost": cost, "kind": kind, "tags": tags.duplicate(),
		"hp": hp, "damage": damage, "armor": armor, "xp": xp,
		"item": item, "color": color, "icon": icon,
		"effect_turns": effect_turns, "effect_power": effect_power,
	}

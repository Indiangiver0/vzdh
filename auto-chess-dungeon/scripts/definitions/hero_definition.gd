class_name HeroDefinition
extends Resource
## Starting archetype. Level, equipment and poison are stored per hero.

@export var id: String = ""
@export var display_name: String = ""
@export var hp: int = 0
@export var damage: int = 0
@export var armor: int = 0
@export_multiline var ability_description: String = ""
@export var color: Color = Color.WHITE
@export_file("*.svg") var icon: String = ""

func to_dictionary() -> Dictionary:
	return {
		"id": id, "name": display_name, "hp": hp, "damage": damage,
		"armor": armor, "trait": ability_description, "color": color, "icon": icon,
	}

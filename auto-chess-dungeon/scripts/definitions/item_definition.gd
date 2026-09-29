class_name ItemDefinition
extends Resource
## Equipment rewards. Duplicate items do not stack.

@export var id: String = ""
@export var display_name: String = ""
@export var damage: int = 0
@export var armor: int = 0
@export_file("*.svg") var icon: String = ""

func to_dictionary() -> Dictionary:
	return {"id": id, "name": display_name, "damage": damage, "armor": armor, "icon": icon}

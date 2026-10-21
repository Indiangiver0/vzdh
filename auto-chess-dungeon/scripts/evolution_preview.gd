extends Control
## The same renderer as the actual dungeon, not a separate mockup.

const Visuals = preload("res://scripts/evolution_visuals.gd")
const Content = preload("res://scripts/content_catalog.gd")

var path_id: String = ""
var room_id: String = ""
var tier: int = 2
var _clock: float = 0.0
var _portrait: Texture2D
var _monster: bool = false


func configure(path: String, room: String, stage: int) -> void:
	path_id = path
	room_id = room
	tier = stage
	custom_minimum_size = Vector2(100, 98)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var definition: Dictionary = Content.room(room)
	_monster = str(definition.get("kind", "")) == "monster"
	var icon: String = str(definition.get("icon", ""))
	if not icon.is_empty():
		_portrait = load(icon)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_clock += delta
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(3, 3, size.x - 6, size.y - 6)
	draw_rect(rect, Color("182022"))
	draw_rect(rect, Color("52615c"), false, 1)
	Visuals.chamber(self, rect, path_id, tier, _clock, false)
	if not _monster or path_id == "wraith_throne_guardian":
		return
	var at := Vector2(size.x * 0.62, size.y * 0.84)
	var scale_factor: float = minf(size.x / 160.0, 1.0)
	var effects := {"transformed": path_id == "war_hound_lycanthrope" and tier >= 5}
	if not Visuals.actor(self, at, scale_factor, path_id, "base", effects, _clock) and _portrait != null:
		draw_texture_rect(_portrait, Rect2(at - Vector2(22, 44) * scale_factor, Vector2(44, 44) * scale_factor), false)

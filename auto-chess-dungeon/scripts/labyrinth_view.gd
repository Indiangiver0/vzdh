extends "res://scripts/dungeon_view.gd"
## Free-grid presentation. Geometry and actions are supplied by the run model.
signal boundary_clicked(id: String)
signal expansion_clicked(position: Vector2i)
signal room_dragged(from_index: int, to_index: int)

const FortressArt = preload("res://scripts/fortress_art.gd")
const CELL_SIZE := Vector2(300, 150)
const CELL_STEP := Vector2(328, 178)
const THRONE_GUARD_TINT := Color(0.92, 0.92, 1.0, 0.9)
const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 2.2

var room_drag_enabled: bool = true
var _layout: Dictionary = {}
var _places: Dictionary = {}
var _grid_camera := Vector2.ZERO
var _camera_target := Vector2.ZERO
var _grid_zoom: float = 1.0
var _zoom_target: float = 1.0
var _camera_ready: bool = false
var _fit_pending: bool = false
var _pointer_down: bool = false
var _pointer_start := Vector2.ZERO
var _pointer_last := Vector2.ZERO
var _pointer_moved: bool = false
var _pointer_button: int = 0
var _pointer_key: String = ""
var _pointer_phase: String = ""
var _pointer_wave: int = -1
var _pointer_touch: int = -1
var _pointer_game_id: int = 0
var _pointer_slot: int = -1
var _pointer_source_identity: String = ""
var _pointer_serial: int = 0
var _grid_touches: Dictionary = {}
var _pinch_distance: float = 0.0
var _pinch_center := Vector2.ZERO
var _hover_key: String = ""
var _grid_styles: Dictionary = {}
var _room_drag_from: int = -1
var _room_drag_active: bool = false
var _hold_time: float = 0.0
var _grid_route_seq: int = -1
const ROOM_HOLD_SECONDS: float = 0.35
const MOUSE_DRAG_DISTANCE: float = 8.0
const TOUCH_DRAG_DISTANCE: float = 12.0


func configure(game_ref, slot: int = -1, room_id: String = "") -> void:
	if game != game_ref or (game != null and int(game.wave) == 1 and _last_wave > 1):
		_cancel_grid_pointer()
		_camera_ready = false
		_grid_route_seq = -1
	super.configure(game_ref, slot, room_id)


func refresh() -> void:
	if game != null:
		_layout = game.layout_snapshot()
		_layout.merge(game.layout_runtime_snapshot(), true)
		_places.clear()
		for place in _layout.get("places", []):
			_places[int(place.slot)] = place
		_places[-1] = {"slot": -1, "position": _layout.get("entrance_position", Vector2i(-1, 0)), "type": "entrance"}
	super.refresh()
	custom_minimum_size = Vector2(180, (60 if get_viewport_rect().size.y < 500 else 120) if compact else 180)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	texture_repeat = CanvasItem.TEXTURE_REPEAT_MIRROR
	if not _camera_ready and size.x > 1 and size.y > 1:
		fit_map.call_deferred()


func refresh_runtime() -> void:
	if game != null:
		_layout.merge(game.layout_runtime_snapshot(), true)
	super.refresh_runtime()

func visual_to_global(at: Vector2) -> Vector2:
	return get_global_transform() * (_grid_camera + at * _grid_zoom)


func _on_resized() -> void:
	_cancel_grid_pointer()
	if not _camera_ready:
		fit_map.call_deferred()
	queue_redraw()


func cancel_interaction() -> void:
	_cancel_grid_pointer()
	queue_redraw()


func has_active_interaction() -> bool:
	return _pointer_down


func reset_camera() -> void:
	_camera_ready = false
	_cancel_grid_pointer()


func fit_map() -> void:
	_cancel_grid_pointer()
	if _fit_pending or not is_inside_tree():
		return
	_fit_pending = true
	# Containers settle after configure; fitting their minimum size shrinks the
	# first view and leaves it small after the actual map panel expands.
	await get_tree().process_frame
	await get_tree().process_frame
	_fit_pending = false
	if _places.is_empty() or size.x <= 1 or size.y <= 1:
		return
	var bounds := Rect2()
	var first: bool = true
	for place in _places.values():
		var rect := _place_rect(place)
		bounds = rect if first else bounds.merge(rect)
		first = false
	if _places.size() <= 1:
		for coordinate in _layout.get("expansion_cells", []):
			bounds = bounds.merge(Rect2(Vector2(coordinate) * CELL_STEP, CELL_SIZE))
	bounds = bounds.grow(32)
	_zoom_target = clampf(minf(size.x / bounds.size.x, size.y / bounds.size.y), MIN_ZOOM, 1.1)
	_camera_target = size * 0.5 - bounds.get_center() * _zoom_target
	if not _camera_ready:
		_grid_zoom = _zoom_target
		_grid_camera = _camera_target
	_camera_ready = true
	queue_redraw()


func focus_party() -> void:
	_cancel_grid_pointer()
	if game == null:
		return
	_camera_target = size * 0.5 - _position_for_slot(int(_layout.get("current_place", -1))) * _zoom_target


func is_party_transition_active() -> bool:
	return not _waypoints.is_empty() or _party_position.distance_to(_party_goal) > 1.0


func zoom_by(factor: float) -> void:
	_cancel_grid_pointer()
	_zoom_at(size * 0.5, factor)


func _zoom_at(anchor: Vector2, factor: float) -> void:
	var world: Vector2 = (anchor - _camera_target) / _zoom_target
	_zoom_target = clampf(_zoom_target * factor, MIN_ZOOM, MAX_ZOOM)
	_camera_target = anchor - world * _zoom_target


func _process(delta: float) -> void:
	if _pointer_down and not _pointer_context_valid():
		_cancel_grid_pointer()
	if _pointer_down and _pointer_touch >= 0 and _room_drag_from >= 0 and not _pointer_moved and not _room_drag_active:
		_hold_time += delta
	var blend: float = 1.0 - exp(-18.0 * delta)
	_grid_zoom = lerpf(_grid_zoom, _zoom_target, blend)
	_grid_camera = _grid_camera.lerp(_camera_target, blend)
	super._process(delta)


func _place_rect(place: Dictionary) -> Rect2:
	var coordinate: Vector2 = Vector2(place.get("position", Vector2i.ZERO))
	return Rect2(coordinate * CELL_STEP, CELL_SIZE)


func _slot_rect(index: int) -> Rect2:
	var actual: int = int(_layout.get("throne_slot", -999)) if game != null and index == game.rooms.size() else index
	if _places.has(actual):
		return _place_rect(_places[actual])
	if _places.has(index):
		return _place_rect(_places[index])
	return Rect2(Vector2(_layout.get("entrance_position", Vector2i(-1, 0))) * CELL_STEP, CELL_SIZE)


func _position_for_slot(index: int) -> Vector2:
	return _slot_rect(index).position + Vector2(90, 132)


func _queue_confirmed_transition(from_place: int, to_place: int) -> void:
	# These two places come from one model move, never from a predicted route.
	var origin: Rect2 = _slot_rect(from_place)
	var destination: Rect2 = _slot_rect(to_place)
	var direction: Vector2 = (destination.get_center() - origin.get_center()).normalized()
	var extent: float = CELL_SIZE.x * 0.5 if absf(direction.x) > 0.5 else CELL_SIZE.y * 0.5
	_waypoints.append(origin.get_center() + direction * extent)
	_waypoints.append(destination.get_center() - direction * extent)
	_party_goal = _position_for_slot(to_place)
	_waypoints.append(_party_goal)
	_last_slot = to_place


func _update_party(delta: float) -> void:
	if game == null:
		return
	var current: int = int(_layout.get("current_place", -1))
	var phase: String = str(game.phase)
	var new_wave: bool = int(game.wave) != _last_wave or (phase == "raid" and _last_phase == "prepare")
	if new_wave:
		_hero_positions.clear()
		_actor_positions.clear()
		_events.clear()
		_waypoints.clear()
		_party_position = _position_for_slot(-1)
		_party_goal = _party_position
		_last_slot = -1
		_last_wave = int(game.wave)
		_grid_route_seq = _last_action_seq
	if _grid_route_seq > int(game.action_seq):
		_grid_route_seq = -1
	_camp_exit_slot = current if phase == "camp" else -1
	if phase in ["raid", "camp", "result", "defeat"]:
		for event in game.combat_events:
			var sequence: int = int(event.get("seq", -1))
			if sequence <= _grid_route_seq:
				continue
			_grid_route_seq = sequence
			if str(event.get("kind", "")) != "move" or str(event.get("actor", "")) != "party":
				continue
			var meta: Dictionary = event.get("meta", {})
			if not meta.has("from_place") or not meta.has("to_place"):
				continue
			var origin: int = int(meta.from_place)
			var destination: int = int(meta.to_place)
			if not _places.has(origin) or not _places.has(destination):
				continue
			if origin != _last_slot:
				# A missing snapshot is resynchronized, not filled with invented moves.
				_waypoints.clear()
				_party_position = _position_for_slot(origin)
			_queue_confirmed_transition(origin, destination)
		if current != _last_slot:
			_waypoints.clear()
			_party_position = _position_for_slot(current)
			_party_goal = _party_position
			_last_slot = current
	if delta > 0 and not _waypoints.is_empty():
		var distance: float = 0.0
		var previous: Vector2 = _party_position
		for waypoint in _waypoints:
			distance += previous.distance_to(waypoint)
			previous = waypoint
		var travel: float = delta * maxf(220, distance * 6)
		while travel > 0 and not _waypoints.is_empty():
			var target: Vector2 = _waypoints[0]
			var segment: float = _party_position.distance_to(target)
			if absf(target.x - _party_position.x) > 0.1:
				_party_direction = signf(target.x - _party_position.x)
			if segment <= travel:
				_party_position = target
				travel -= segment
				_waypoints.pop_front()
			else:
				_party_position = _party_position.move_toward(target, travel)
				travel = 0
	_last_phase = phase


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	if game == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("10171d"))
	_actor_positions.clear()
	var visible := Rect2(-_grid_camera / _grid_zoom, size / _grid_zoom).grow(150)
	draw_set_transform(_grid_camera, 0, Vector2.ONE * _grid_zoom)
	_draw_terrain_layers(visible)
	_draw_depth_layers(visible)
	for boundary in _layout.get("boundaries", []):
		_draw_boundary(boundary)
	if str(game.phase) == "prepare":
		for coordinate in _layout.get("expansion_cells", []):
			var rect := Rect2(Vector2(coordinate) * CELL_STEP, CELL_SIZE)
			if not visible.intersects(rect):
				continue
			draw_rect(rect.grow(-3), Color(TEAL, 0.45), false, 1.5)
			_center_text("+", rect.get_center() + Vector2(0, -3), 28, TEAL)
			_center_text("%d зол." % game.grid_expansion_cost(), rect.get_center() + Vector2(0, 24), 13, MUTED)
	for place in _places.values():
		if visible.intersects(_place_rect(place)):
			_draw_place(place)
	# Wall handles are drawn over cell edges, but never over room content.
	if str(game.phase) == "prepare":
		for boundary in _layout.get("boundaries", []):
			var midpoint: Vector2 = (_slot_rect(int(boundary.a)).get_center() + _slot_rect(int(boundary.b)).get_center()) * 0.5
			var tint: Color = TEAL if bool(boundary.open) else CORAL
			draw_circle(midpoint, 12, Color("111c22"))
			draw_arc(midpoint, 12, 0, TAU, 24, tint, 1.5, true)
			_center_text("·" if bool(boundary.open) else "×", midpoint + Vector2(0, 5), 18, tint)
	_draw_mimic_links()
	_draw_recovering_vampires()
	_draw_camp()
	if show_party and str(game.phase) in ["raid", "camp", "result", "defeat"]:
		_draw_grid_party()
	_draw_event_feedback()
	_draw_vampire_flights()
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_draw_room_drag()
	if str(game.phase) in ["raid", "camp"]:
		var carried: int = int(_layout.get("carried_gold", 0))
		var travelling: String = "Возвращаются к выходу" if str(_layout.get("movement_mode", "")) == "returning" else "Исследуют подземелье"
		if carried > 0:
			travelling += " · несут %d зол." % carried
		_text(travelling, Vector2(12, 20), 12, GOLD)
	draw_rect(Rect2(0, size.y - 27, size.x, 27), Color(0.06, 0.09, 0.11, 0.94))
	var hint: String = "Зажмите комнату — перенос / обмен · колесо — масштаб" if not compact else "Зажмите комнату — перенос · щипок — масштаб"
	_text(hint, Vector2(12, size.y - 12), 11, Color(MUTED, 0.8))
	_text("%d%%" % roundi(_grid_zoom * 100), Vector2(size.x - 48, size.y - 12), 11, GOLD)


func _draw_boundary(boundary: Dictionary) -> void:
	var a: Vector2 = _slot_rect(int(boundary.a)).get_center()
	var b: Vector2 = _slot_rect(int(boundary.b)).get_center()
	var middle: Vector2 = (a + b) * 0.5
	var side: Vector2 = Vector2(-(b - a).y, (b - a).x).normalized()
	if bool(boundary.open):
		draw_line(a, b, Color("33463f"), 19, true)
		draw_line(a, b, Color("8b9e7e"), 1.5, true)
	else:
		draw_line(a, b, Color("20282d"), 9, true)
		draw_line(middle - side * 21, middle + side * 21, Color("9e7365"), 6, true)
		for offset in [-12, 0, 12]:
			var mark: Vector2 = middle + side * float(offset)
			draw_line(mark - Vector2(3, 3), mark + Vector2(3, 3), Color("d0a68c"), 1, true)


func _living_chamber_cleared(index: int) -> bool:
	if str(game.phase) == "prepare" or index < 0 or index >= game.rooms.size():
		return false
	var room: Dictionary = game.rooms[index]
	if str(room.get("evolution_path", "")) != "mimic_living_chamber" or str(room.get("status", "")) != "cleared":
		return false
	# Persistent owner status is final; a temporary zero HP is not a cleared room.
	for actors in _slot_actors.values():
		for actor_data in actors:
			if int(actor_data.get("source_slot", -1)) == index and str(actor_data.get("phase_id", "")) == "appendage" and int(actor_data.get("hp", 0)) > 0:
				return false
	return true


func _draw_place(place: Dictionary) -> void:
	var index: int = int(place.slot)
	var kind: String = str(place.get("type", "room"))
	var rect: Rect2 = _place_rect(place)
	var center: Vector2 = rect.get_center()
	var active: bool = str(game.phase) in ["raid", "camp"] and int(_layout.get("current_place", -1)) == index
	var selected: bool = index >= 0 and index == selected_slot
	var tint: Color = GOLD if kind in ["treasury", "throne"] else TEAL
	var room: Dictionary = game.rooms[index] if index >= 0 and index < game.rooms.size() else {}
	var stats: Dictionary = _room_snapshot[index] if index >= 0 and index < _room_snapshot.size() else {}
	var room_id: String = str(stats.get("id", room.get("id", "empty"))) if kind == "room" else kind
	var path: String = str(stats.get("evolution_path", ""))
	var tier: int = int(stats.get("evolution_stage", 1))
	var depth: int = maxi(1, floori(float(place.position.y) / float(_layout.get("depth_layer_height", 3))) + 1)
	var background_phase: String = "cleared" if path == "mimic_living_chamber" and _living_chamber_cleared(index) else "base"
	draw_rect(rect.grow(3), Color("4b493c"))
	var has_background: bool = FortressArt.draw_background(self, rect, room_id, path, tier, depth, background_phase)
	if not has_background:
		draw_rect(rect, Color("232a22"))
		_draw_masonry(rect)
	draw_rect(rect.grow(2), GOLD if active else (tint if selected else Color("66604b")), false, 2.0 if active or selected else 1.0)
	if _hover_key == "s:%d" % index and str(game.phase) == "prepare":
		draw_rect(rect.grow(4), Color(tint, 0.7), false, 1.0)
	if kind == "entrance":
		_draw_grid_caption(rect, "ВХОД / ВЫХОД", TEAL)
		if not has_background:
			draw_arc(center + Vector2(0, 6), 22, PI, TAU, 24, MUTED, 4, true)
			draw_line(center + Vector2(-22, 6), center + Vector2(-22, 31), MUTED, 4)
			draw_line(center + Vector2(22, 6), center + Vector2(22, 31), MUTED, 4)
			_draw_direction_arrow(center + Vector2(-11, 14), center + Vector2(12, 14), TEAL)
		return
	if kind == "treasury":
		_draw_grid_caption(rect, "КАЗНА", GOLD)
		if not has_background:
			draw_rect(Rect2(center + Vector2(-28, -9), Vector2(56, 34)), Color("755333"))
			draw_rect(Rect2(center + Vector2(-31, -17), Vector2(62, 14)), GOLD)
			draw_rect(Rect2(center + Vector2(-5, -6), Vector2(10, 16)), Color("f0d788"))
		_draw_guest_actors(rect, index)
		return
	if kind == "throne":
		_draw_grid_caption(rect, "ТРОН", GOLD)
		var visual: Dictionary = _lord_visual()
		var foot: Vector2 = rect.position + Vector2(246, 132)
		_actor_positions["lord"] = foot + Vector2(0, -32)
		if int(game.lord.hp) > 0:
			if not FortressArt.draw_actor(self, foot, Vector2(92, 90), "lord", str(game.lord_archetype)):
				_icon(str(visual.get("icon", "lord")), Rect2(foot + Vector2(-25, -50), Vector2(50, 50)))
			_draw_defender_wards(foot + Vector2(0, -32), 0.75, game.lord)
		_bar(Rect2(foot + Vector2(-26, 7), Vector2(52, 4)), float(game.lord.hp) / maxf(1, int(game.lord.max_hp)), GOLD)
		_draw_guest_actors(rect, game.rooms.size())
		if str(game.phase) == "prepare" and _throne_guard_slot >= 0 and _throne_guard_slot < _room_snapshot.size():
			var guard_stats: Dictionary = _room_snapshot[_throne_guard_slot]
			_draw_grid_actor(rect.position + Vector2(170, 130), Vector2(56, 84), "wraith", "wraith_throne_guardian", int(guard_stats.get("evolution_stage", 2)), "throne_guard", {}, THRONE_GUARD_TINT)
		return
	if index < 0 or index >= game.rooms.size():
		return
	if room.is_empty():
		_draw_grid_caption(rect, "ПАСТЬ" if _reserved_snapshot.has(index) else "СВОБОДНО", MUTED)
		if _reserved_snapshot.has(index):
			_draw_reserved_growth(rect, index)
		elif _slot_actors.has(index):
			_draw_guest_actors(rect, index)
		elif not selected_room.is_empty() and str(game.phase) == "prepare":
			if not FortressArt.draw_actor(self, center + Vector2(55, 48), Vector2(84, 74), "room", selected_room, "", 1, Color(1, 1, 1, 0.42)):
				_icon(selected_room, Rect2(center + Vector2(-23, -20), Vector2(46, 46)), Color(1, 1, 1, 0.42))
			_center_text("РАЗМЕСТИТЬ", center + Vector2(0, 47), 11, TEAL)
		elif not has_background:
			_center_text("+", center + Vector2(0, 8), 25, Color(MUTED, 0.55))
		return
	if stats.is_empty():
		return
	var cleared: bool = str(room.get("status", "")) == "cleared" and str(stats.get("kind", "")) == "monster"
	if path == "mimic_living_chamber":
		cleared = background_phase == "cleared"
	var status: String = "Ранг %d" % int(room.get("rank", 1))
	if bool(stats.get("deadly_corridor_receiver", false)):
		status += " · РУБЕЖ"
	if index in _layout.get("disabled_slots", []):
		status = "ОБЕЗВРЕЖЕНА"
	elif path == "ballista_reserve_magazine":
		status += " · Болты %d" % int(room.get("evolution_memory", {}).get("ammo", 0))
	var title: String = str(stats.get("name", "")) if path in ["mimic_living_chamber", "wraith_throne_guardian"] else str(stats.get("short_name", stats.get("name", "")))
	_draw_grid_caption(rect, title, CREAM, status)
	if str(room.get("status", "")) == "retreated" and not _slot_actors.has(index):
		_center_text("ВАМПИР УЛЕТЕЛ", rect.position + Vector2(232, 142), 9, MUTED)
		return
	if not path.is_empty() and not has_background:
		if path == "mimic_living_chamber" and cleared:
			_draw_rubble(rect.position + Vector2(240, 128), 0.75)
		else:
			_draw_evolution_props(rect, index, stats, cleared)
	elif int(_room_visual_state.get(index, {}).get("effects", {}).get("fire_ticks", 0)) > 0:
		for flame in range(5):
			_draw_torch(rect.position + Vector2(30 + flame * 58, 134), float(flame), 0.6)
	if str(stats.get("kind", "")) == "monster":
		_draw_evolution_actors(rect, index, stats, cleared)
	else:
		if not has_background:
			_icon(str(stats.id), Rect2(center + Vector2(-25, -24), Vector2(50, 50)))
		_actor_positions["room_%d" % index] = rect.position + Vector2(230, 102)
		_draw_guest_actors(rect, index)
	if int(stats.get("hp", 0)) > 0:
		var hp: float = float(room.get("current_hp", stats.hp))
		var maximum: float = float(stats.hp)
		if _slot_actors.has(index):
			hp = _actors_health(index, "hp")
			maximum = _actors_health(index, "max_hp")
		_bar(Rect2(rect.position + Vector2(211, 140), Vector2(58, 4)), hp / maxf(1, maximum), CORAL)


func _draw_grid_caption(rect: Rect2, title: String, color: Color, detail: String = "") -> void:
	# Keep the centre of the inter-cell gap free for vertical boundaries.
	draw_rect(Rect2(rect.position + Vector2(4, -21), Vector2(131, 16)), Color("192017"))
	_center_text_fitted(title, rect.position + Vector2(69, -9), 11, color, 125)
	if not detail.is_empty():
		draw_rect(Rect2(rect.position + Vector2(168, -21), Vector2(128, 16)), Color("192017"))
		_center_text_fitted(detail, rect.position + Vector2(232, -9), 10, MUTED, 122)


func _draw_grid_actor(foot: Vector2, maximum: Vector2, room_id: String, path_id: String, tier: int, phase_id: String, effects: Dictionary, tint: Color, servant_class: String = "") -> void:
	var art_phase: String = phase_id
	if phase_id == "base":
		if path_id == "war_hound_lycanthrope" and bool(effects.get("transformed", false)):
			art_phase = "werewolf"
		elif bool(effects.get("spirit", false)) or bool(effects.get("spectral", false)):
			art_phase = "spirit"
	if FortressArt.draw_actor(self, foot, maximum, "room", room_id, path_id, tier, tint, false, art_phase):
		return
	# Special phases preserve their existing live shape, never a second base actor.
	var fallback_scale: float = minf(maximum.x / 60.0, maximum.y / 56.0)
	if EvolutionVisuals.actor(self, foot, fallback_scale, path_id, phase_id, effects, _clock):
		return
	var icon_id: String = servant_class if phase_id == "servant" and not servant_class.is_empty() else room_id
	var icon_size: float = minf(maximum.x, maximum.y)
	_icon(icon_id, Rect2(foot + Vector2(-icon_size * 0.5, -icon_size), Vector2.ONE * icon_size), tint)


func _draw_evolution_actors(rect: Rect2, index: int, stats: Dictionary, cleared: bool) -> void:
	if str(stats.get("kind", "")) != "monster":
		return
	var path: String = str(stats.get("evolution_path", ""))
	if path == "wraith_throne_guardian":
		return
	var actors: Array = _slot_actors.get(index, [])
	var live: bool = not actors.is_empty()
	if path == "mimic_living_chamber" and cleared:
		if live:
			_draw_guest_actors(rect, index)
		return
	if cleared and not live:
		_draw_rubble(rect.position + Vector2(240, 128), 0.75)
		return
	if not live:
		actors = [{"id": stats.id, "phase_id": "base", "path_id": path, "effects": {}, "hp": stats.get("hp", 0), "max_hp": stats.get("hp", 0)}]
	var count: int = actors.size()
	for actor_index in range(count):
		var actor_data: Dictionary = actors[actor_index]
		var column: int = actor_index % 3
		var row: int = actor_index / 3
		var columns: int = mini(3, count)
		var foot: Vector2 = rect.position + Vector2(235 + (column - (columns - 1) * 0.5) * 33, 130 - row * 48)
		var maximum: Vector2 = Vector2(100, 86) if count == 1 else Vector2(31, 46)
		if str(actor_data.get("path_id", path)) == "mimic_living_chamber" and str(actor_data.get("phase_id", "base")) == "base":
			maximum = Vector2(46, 48)
		var effects: Dictionary = actor_data.get("effects", {})
		var tint: Color = Color.WHITE
		if "spirit" in actor_data.get("tags", []) or bool(effects.get("spectral", false)) or bool(effects.get("spirit", false)):
			tint = Color(0.72, 0.65, 0.93, 0.6)
		var identity: String = str(actor_data.get("actor_id", "room_%d" % index))
		if live:
			_actor_positions[identity] = foot + Vector2(0, -maximum.y * 0.4)
		_draw_grid_actor(foot, maximum, str(actor_data.get("id", stats.id)), str(actor_data.get("path_id", path)), int(actor_data.get("stage", stats.get("evolution_stage", 1))), str(actor_data.get("phase_id", "base")), effects, tint, str(actor_data.get("servant_class", "")))
		if not live:
			continue
		_draw_defender_wards(foot + Vector2(0, -maximum.y * 0.45), 0.7 if count == 1 else 0.45, actor_data)
		if count > 1 and not bool(actor_data.get("untargetable", false)):
			_bar(Rect2(foot + Vector2(-12, 4), Vector2(24, 3)), float(actor_data.hp) / maxf(1, float(actor_data.max_hp)), CORAL)
		var preparation: Dictionary = effects.get("preparing", {})
		if not preparation.is_empty():
			var ratio: float = 1.0 - float(preparation.get("remaining", 0)) / maxf(1, float(preparation.get("total", 1)))
			_bar(Rect2(foot + Vector2(-15, -maximum.y - 5), Vector2(30, 3)), ratio, GOLD)
		elif int(effects.get("cocoon_ready_in", 0)) > 0:
			var total: float = float(effects.get("cocoon_cooldown_total", effects.cocoon_ready_in))
			_bar(Rect2(foot + Vector2(-15, -maximum.y - 5), Vector2(30, 3)), 1.0 - float(effects.cocoon_ready_in) / maxf(1, total), Color("c9d3c2"))


func _draw_reserved_growth(rect: Rect2, index: int) -> void:
	if not _reserved_snapshot.has(index):
		return
	var owner: int = int(_reserved_snapshot[index])
	if owner < 0 or owner >= game.rooms.size() or game.rooms[owner].is_empty():
		return
	if _living_chamber_cleared(owner):
		return
	var owner_stage: int = int(game.rooms[owner].get("evolution_stage", 2))
	var anchor: Vector2 = rect.position + Vector2(238, 127)
	var mouths: Array = _slot_actors.get(index, [])
	if mouths.is_empty():
		_draw_grid_actor(anchor, Vector2(80, 64), "mimic", "mimic_living_chamber", owner_stage, "appendage", {}, Color.WHITE)
		return
	for mouth in mouths:
		if str(mouth.get("phase_id", "")) != "appendage":
			continue
		_actor_positions[str(mouth.actor_id)] = anchor + Vector2(0, -18)
		_draw_grid_actor(anchor, Vector2(80, 64), "mimic", "mimic_living_chamber", int(mouth.get("stage", owner_stage)), "appendage", mouth.get("effects", {}), Color.WHITE)
	# The mouth has no separate health pool; the heart remains the sole owner.


func _camp_fire_position(slot: int) -> Vector2:
	return _slot_rect(slot).position + Vector2(236, 120)


func _draw_camp() -> void:
	if not bool(_camp_snapshot.get("active", false)):
		return
	var slot: int = int(_camp_snapshot.get("slot", -1))
	if not _places.has(slot):
		return
	var rect: Rect2 = _slot_rect(slot)
	var fire: Vector2 = _camp_fire_position(slot)
	draw_rect(rect.grow(2), Color(GOLD, 0.65), false, 2.0)
	draw_ellipse_shadow(fire + Vector2(0, 4), 13)
	draw_line(fire + Vector2(-10, 3), fire + Vector2(10, -2), Color("725238"), 4)
	draw_line(fire + Vector2(-10, -2), fire + Vector2(10, 3), Color("a97945"), 3)
	_draw_torch(fire + Vector2(0, -5), float(slot), 1.15)
	_actor_positions["camp"] = fire
	_center_text("ПРИВАЛ · %.1f с" % float(_camp_snapshot.get("remaining_seconds", 0.0)), fire + Vector2(0, -36), 10, GOLD)
	_bar(Rect2(fire + Vector2(-27, 14), Vector2(54, 4)), float(_camp_snapshot.get("pulse_progress", 0.0)), GOLD)


func _grid_hero_offset(index: int, count: int, walking: bool) -> Vector2:
	if walking:
		return Vector2(-index * 8.0 * _party_direction, -index * 2.0)
	if count == 1:
		return Vector2.ZERO
	if count == 2:
		return Vector2(-20 + index * 48, 0)
	if count == 3:
		return [Vector2(20, 0), Vector2(-46, -43), Vector2(0, -43)][index]
	if count == 4:
		return [Vector2(-20, 0), Vector2(28, 0), Vector2(-46, -43), Vector2(0, -43)][index]
	return [Vector2(-20, 0), Vector2(28, 0), Vector2(-50, -43), Vector2(-10, -43), Vector2(30, -43)][index]


func _draw_grid_party() -> void:
	var living: Array[Dictionary] = []
	var walking: bool = not _waypoints.is_empty() or _party_position.distance_to(_party_goal) > 1.0
	var finishing_exit: bool = walking and str(_layout.get("movement_mode", "")) == "escaped"
	for hero in game.heroes:
		if int(hero.hp) > 0 and (not bool(hero.get("escaped", false)) or finishing_exit):
			living.append(hero)
	if living.is_empty():
		return
	var order: Array[int] = []
	# This changes paint order only; model order determines every formation slot.
	for hero_index in range(2, living.size()):
		order.append(hero_index)
	for hero_index in range(mini(2, living.size())):
		order.append(hero_index)
	var bars: Array[Dictionary] = []
	for hero_index in order:
		var hero: Dictionary = living[hero_index]
		var identity: String = str(hero.get("instance_id", hero.id))
		var foot: Vector2 = _party_position + _grid_hero_offset(hero_index, living.size(), walking)
		if walking and str(game.phase) != "camp":
			foot.y += sin(_clock * 12.0 + hero_index) * 1.1
		_hero_positions[identity] = foot
		var maximum: Vector2 = Vector2(24, 30) if walking else Vector2(36, 48 if hero_index < 2 else 40)
		draw_ellipse_shadow(foot + Vector2(0, 2), maximum.x * 0.35)
		if not FortressArt.draw_actor(self, foot, maximum, "hero", str(hero.id), "", 1, Color.WHITE, walking and _party_direction < 0.0):
			var icon_size: float = minf(maximum.x, maximum.y)
			_icon(str(hero.id), Rect2(foot + Vector2(-icon_size * 0.5, -icon_size), Vector2.ONE * icon_size))
		EvolutionVisuals.hero_equipment(self, foot, 0.5 if walking else 0.65, _hero_equipment.get(identity, {}), _hero_effects.get(identity, {}), _clock)
		if int(hero.get("poison_ticks", 0)) > 0:
			draw_circle(foot + Vector2(12, -maximum.y + 5), 2.5, Color("92b957"))
		if int(hero.get("silence_ticks", 0)) > 0 or int(hero.get("pending_silence", 0)) > 0:
			draw_line(foot + Vector2(-11, -maximum.y + 5), foot + Vector2(11, -9), Color("b4a0d5"), 1.5)
		if int(hero.get("shackles_ticks", 0)) > 0 or int(hero.get("pending_shackles", 0)) > 0:
			draw_arc(foot + Vector2(0, 2), 7, 0, PI, 12, MUTED, 1.5)
		if int(hero.get("goblin_mark_slot", -1)) >= 0:
			var mark: Vector2 = foot + Vector2(0, -maximum.y - 7)
			draw_colored_polygon(PackedVector2Array([mark + Vector2(0, -3), mark + Vector2(3, 0), mark + Vector2(0, 3), mark + Vector2(-3, 0)]), GOLD)
		if str(game.get("active_target_id")) == identity and str(game.phase) == "raid" and _camp_exit_slot < 0:
			draw_rect(Rect2(foot + Vector2(-maximum.x * 0.5 - 2, -maximum.y - 2), maximum + Vector2(4, 4)), CORAL, false, 1.2)
		var loot: int = int(_layout.get("loot_shares", {}).get(identity, 0))
		if loot > 0:
			_center_text(str(loot), foot + Vector2(0, -maximum.y - 6), 9, GOLD)
		bars.append({"foot": foot, "hero": hero})
	_draw_party_links(living)
	for entry in bars:
		var foot: Vector2 = entry.foot
		var hero: Dictionary = entry.hero
		_bar(Rect2(foot + Vector2(-9, 4), Vector2(18, 3)), float(hero.hp) / maxf(1, int(hero.max_hp)), TEAL)


func _hit(at: Vector2) -> Dictionary:
	var world: Vector2 = (at - _grid_camera) / _grid_zoom
	# Room interiors always own their press, including at the smallest zoom.
	# Expanded boundary targets are clipped to the actual inter-room gap below.
	for place in _places.values():
		if _place_rect(place).has_point(world):
			return {"kind": "slot", "slot": int(place.slot), "key": "s:%d" % int(place.slot)}
	if game != null and str(game.phase) == "prepare":
		var best: Dictionary = {}
		var best_distance: float = 22.0 if compact or _pointer_touch >= 0 or not _grid_touches.is_empty() else 14.0
		var canvas: Transform2D = get_global_transform_with_canvas()
		var pointer: Vector2 = canvas * at
		for boundary in _layout.get("boundaries", []):
			if not _boundary_gap(boundary).has_point(world):
				continue
			var middle: Vector2 = (_slot_rect(int(boundary.a)).get_center() + _slot_rect(int(boundary.b)).get_center()) * 0.5
			var distance: float = pointer.distance_to(canvas * (_grid_camera + middle * _grid_zoom))
			if distance < best_distance:
				best_distance = distance
				best = {"kind": "boundary", "id": str(boundary.id), "key": "b:" + str(boundary.id)}
		if not best.is_empty():
			return best
		for coordinate in _layout.get("expansion_cells", []):
			if Rect2(Vector2(coordinate) * CELL_STEP, CELL_SIZE).has_point(world):
				return {"kind": "expansion", "position": coordinate, "key": "e:%s" % str(coordinate)}
	return {}


func _boundary_gap(boundary: Dictionary) -> Rect2:
	var a: int = int(boundary.a)
	var b: int = int(boundary.b)
	if not _places.has(a) or not _places.has(b):
		return Rect2()
	var first: Rect2 = _place_rect(_places[a])
	var second: Rect2 = _place_rect(_places[b])
	if first.end.x <= second.position.x or second.end.x <= first.position.x:
		var start := Vector2(minf(first.end.x, second.end.x), maxf(first.position.y, second.position.y))
		var end := Vector2(maxf(first.position.x, second.position.x), minf(first.end.y, second.end.y))
		return Rect2(start, Vector2(maxf(0.0, end.x - start.x), maxf(0.0, end.y - start.y)))
	if first.end.y <= second.position.y or second.end.y <= first.position.y:
		var start := Vector2(maxf(first.position.x, second.position.x), minf(first.end.y, second.end.y))
		var end := Vector2(minf(first.end.x, second.end.x), maxf(first.position.y, second.position.y))
		return Rect2(start, Vector2(maxf(0.0, end.x - start.x), maxf(0.0, end.y - start.y)))
	return Rect2()


func _slot_at(at: Vector2) -> int:
	return int(_hit(at).get("slot", -1))


func _get_tooltip(at_position: Vector2) -> String:
	var hit: Dictionary = _hit(at_position)
	if hit.is_empty():
		return ""
	if str(hit.kind) == "boundary":
		return "Нажмите границу, чтобы открыть проход или возвести стену."
	if str(hit.kind) == "expansion":
		return "Раскопать клетку · %d зол." % game.grid_expansion_cost()
	var index: int = int(hit.slot)
	var place: Dictionary = _places.get(index, {})
	if str(place.get("type", "")) == "treasury":
		return "Казна: при первом ограблении герои забирают половину текущего золота. Добычу можно отбить на обратном пути."
	if str(place.get("type", "")) == "throne":
		return "Трон Лорда. Его гибель завершает забег."
	if index < 0:
		return "Вход героев и выход с добычей."
	if _reserved_snapshot.has(index):
		var owner: int = int(_reserved_snapshot[index])
		return "Пасть Живой комнаты: помогает центру в общем бою, примерно 30% его урона. Отдельного боя здесь нет. После гибели сердца пасть исчезает. Центр: %s." % str(_places.get(owner, {}).get("position", ""))
	if game.rooms[index].is_empty():
		return "Пустая клетка. Выберите комнату в магазине или перенесите сюда существующую."
	return super._get_tooltip(at_position)


func _input(event: InputEvent) -> void:
	# Observe only our existing gesture. Never consume global events: main tracks
	# every touch release, including releases over a modal or outside this field.
	if not _pointer_down and _grid_touches.is_empty():
		return
	if event is InputEventScreenTouch:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if event.pressed:
			if not Rect2(Vector2.ZERO, size).has_point(local):
				_grid_touches[event.index] = local
				_cancel_grid_pointer()
		elif _grid_touches.has(event.index):
			if event.canceled or not _pointer_down or not Rect2(Vector2.ZERO, size).has_point(local):
				_grid_touches.erase(event.index)
				_cancel_grid_pointer()
			else:
				_cancel_unhandled_touch_release.call_deferred(event.index, _pointer_serial)
	elif event is InputEventMouseButton and event.device != -1 and _pointer_down and _pointer_touch < 0:
		if not event.pressed and event.button_index == _pointer_button:
			var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
			if not Rect2(Vector2.ZERO, size).has_point(local):
				_cancel_grid_pointer()
			else:
				_cancel_unhandled_mouse_release.call_deferred(_pointer_serial)
	elif _pointer_down and event is InputEventMouseMotion and event.device != -1 and _pointer_touch < 0:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, size).has_point(local):
			_drag_grid_pointer(local)
	elif _pointer_down and event is InputEventScreenDrag and _grid_touches.has(event.index):
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse() * event.position
		if not Rect2(Vector2.ZERO, size).has_point(local) and _grid_touches.size() == 1:
			_grid_touches[event.index] = local
			_drag_grid_pointer(local)


func _cancel_unhandled_mouse_release(serial: int) -> void:
	if _pointer_down and _pointer_serial == serial:
		_cancel_grid_pointer()


func _cancel_unhandled_touch_release(index: int, serial: int) -> void:
	if (_pointer_serial == serial or not _pointer_down) and _grid_touches.has(index):
		_grid_touches.erase(index)
		_cancel_grid_pointer()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if event.device == -1 or not _grid_touches.is_empty():
			accept_event()
			return
	if event is InputEventMagnifyGesture:
		if _grid_touches.is_empty() and is_finite(event.factor) and event.factor > 0.0:
			_cancel_grid_pointer()
			_zoom_at(event.position, event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		if _grid_touches.is_empty():
			_cancel_grid_pointer()
			_camera_target -= event.delta * 22
		accept_event()
	elif event is InputEventMouseButton and event.device != -1:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_cancel_grid_pointer()
			_zoom_at(event.position, exp((0.14 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.14) * maxf(0.1, event.factor)))
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed and not _pointer_down:
				_start_grid_pointer(event.position, event.button_index)
			elif not event.pressed and _pointer_down and event.button_index == _pointer_button:
				_finish_grid_pointer(event.position)
			accept_event()
	elif event is InputEventMouseMotion and event.device != -1:
		if _pointer_down:
			_drag_grid_pointer(event.position)
		_hover_key = str(_hit(event.position).get("key", ""))
	elif event is InputEventScreenTouch:
		if event.pressed:
			if _pointer_down and _pointer_touch < 0:
				_cancel_grid_pointer()
			_grid_touches[event.index] = event.position
			if _grid_touches.size() == 1:
				_start_grid_pointer(event.position, MOUSE_BUTTON_LEFT, event.index)
			else:
				_room_drag_active = false
				_room_drag_from = -1
				_pointer_moved = true
				_reset_pinch()
		else:
			if not _grid_touches.has(event.index):
				accept_event()
				return
			var was_single: bool = _grid_touches.size() == 1
			_grid_touches.erase(event.index)
			if event.canceled:
				_cancel_grid_pointer()
			elif was_single and _pointer_down:
				_finish_grid_pointer(event.position)
			elif _grid_touches.is_empty():
				_cancel_grid_pointer()
			else:
				_pointer_moved = true
				_room_drag_from = -1
				_room_drag_active = false
				_pointer_touch = int(_grid_touches.keys()[0])
				_pointer_last = _grid_touches.values()[0]
				_reset_pinch()
		accept_event()
	elif event is InputEventScreenDrag:
		if _pointer_down and _grid_touches.has(event.index):
			_grid_touches[event.index] = event.position
			if _grid_touches.size() >= 2:
				var points: Array = _grid_touches.values()
				var middle: Vector2 = (Vector2(points[0]) + Vector2(points[1])) * 0.5
				var distance: float = Vector2(points[0]).distance_to(Vector2(points[1]))
				if _pinch_distance > 1:
					_zoom_at(_pinch_center, distance / _pinch_distance)
					_camera_target += middle - _pinch_center
				_pinch_center = middle
				_pinch_distance = distance
				_pointer_moved = true
			else:
				_drag_grid_pointer(event.position)
		accept_event()


func _reset_pinch() -> void:
	if _grid_touches.size() < 2:
		return
	var points: Array = _grid_touches.values()
	_pinch_distance = Vector2(points[0]).distance_to(Vector2(points[1]))
	_pinch_center = (Vector2(points[0]) + Vector2(points[1])) * 0.5


func _start_grid_pointer(at: Vector2, button: int, touch_index: int = -1) -> void:
	if game == null or not is_visible_in_tree() or not Rect2(Vector2.ZERO, size).has_point(at):
		return
	_pointer_serial += 1
	_pointer_down = true
	# Movement thresholds are in viewport pixels, never in zoomed map units.
	_pointer_start = get_global_transform_with_canvas() * at
	_pointer_last = at
	_pointer_moved = false
	_pointer_button = button
	_pointer_key = str(_hit(at).get("key", ""))
	_pointer_phase = str(game.phase)
	_pointer_wave = int(game.wave)
	_pointer_touch = touch_index
	_pointer_game_id = game.get_instance_id()
	_hold_time = 0.0
	_room_drag_from = -1
	_room_drag_active = false
	var hit: Dictionary = _hit(at)
	var index: int = int(hit.get("slot", -1))
	_pointer_slot = index
	_pointer_source_identity = _source_identity(index)
	if button == MOUSE_BUTTON_LEFT and room_drag_enabled and game.phase == "prepare" and selected_room.is_empty() and not _pointer_source_identity.is_empty() and _pointer_source_identity != "empty":
		_room_drag_from = index
	# Stop camera easing under the pressed target without changing its position.
	_camera_target = _grid_camera
	_zoom_target = _grid_zoom


func _source_identity(index: int) -> String:
	if game == null or index < 0 or index >= game.rooms.size() or not _places.has(index):
		return ""
	if game.is_treasury_slot(index):
		return "treasury"
	if game.is_throne_slot(index):
		return "throne"
	if game.rooms[index].is_empty():
		return "empty"
	return "room:%d" % int(game.rooms[index].get("instance_id", -1))


func _pointer_context_valid() -> bool:
	if game == null or not is_visible_in_tree() or game.get_instance_id() != _pointer_game_id:
		return false
	if str(game.phase) != _pointer_phase or int(game.wave) != _pointer_wave:
		return false
	if _pointer_slot >= 0 and _source_identity(_pointer_slot) != _pointer_source_identity:
		return false
	return _room_drag_from < 0 or (room_drag_enabled and selected_room.is_empty())


func _pointer_distance(at: Vector2) -> float:
	return (get_global_transform_with_canvas() * at).distance_to(_pointer_start)


func _drag_grid_pointer(at: Vector2) -> void:
	if not _pointer_down:
		return
	if not _pointer_context_valid():
		_cancel_grid_pointer()
		return
	if _room_drag_active:
		_pointer_last = at
		queue_redraw()
		return
	var threshold: float = TOUCH_DRAG_DISTANCE if _pointer_touch >= 0 else MOUSE_DRAG_DISTANCE
	if _pointer_distance(at) > threshold:
		_pointer_moved = true
		if _room_drag_from >= 0 and (_pointer_touch < 0 or _hold_time >= ROOM_HOLD_SECONDS):
			_room_drag_active = true
			_pointer_last = at
			queue_redraw()
			return
		# Early touch movement permanently becomes pan until the next touch.
		_room_drag_from = -1
	if _pointer_moved:
		_camera_target += at - _pointer_last
		_grid_camera = _camera_target
	_pointer_last = at


func _finish_grid_pointer(at: Vector2) -> void:
	if not _pointer_down:
		return
	if not Rect2(Vector2.ZERO, size).has_point(at) or not _pointer_context_valid():
		_cancel_grid_pointer()
		return
	# A release can arrive without the last motion event. It may cancel a tap,
	# but cannot begin and commit a room drag in this one event.
	var threshold: float = TOUCH_DRAG_DISTANCE if _pointer_touch >= 0 else MOUSE_DRAG_DISTANCE
	if not _room_drag_active and _pointer_distance(at) > threshold:
		_cancel_grid_pointer()
		return
	var hit: Dictionary = _hit(at)
	if _room_drag_active:
		var origin: int = _room_drag_from
		var destination: int = int(hit.get("slot", -1))
		var valid: bool = destination >= 0 and _places.has(destination) and destination != origin
		_cancel_grid_pointer()
		if valid:
			room_dragged.emit(origin, destination)
		return
	var commit: bool = not _pointer_moved and _pointer_button == MOUSE_BUTTON_LEFT and str(hit.get("key", "")) == _pointer_key and not _pointer_key.is_empty()
	_cancel_grid_pointer()
	if not commit or not is_visible_in_tree():
		return
	match str(hit.kind):
		"boundary": boundary_clicked.emit(str(hit.id))
		"expansion": expansion_clicked.emit(Vector2i(hit.position))
		"slot": slot_clicked.emit(int(hit.slot))


func _cancel_grid_pointer(clear_touches: bool = false) -> void:
	_pointer_serial += 1
	_room_drag_active = false
	_room_drag_from = -1
	_hold_time = 0.0
	_pointer_down = false
	_pointer_button = 0
	_pointer_touch = -1
	_pointer_key = ""
	_pointer_slot = -1
	_pointer_source_identity = ""
	# Keep physical contacts until release so cancellation cannot re-arm the
	# remaining finger. Focus loss may swallow releases, so it clears contacts.
	if clear_touches:
		_grid_touches.clear()
	_pinch_distance = 0
	queue_redraw()


func _notification(what: int) -> void:
	super._notification(what)
	if what in [NOTIFICATION_EXIT_TREE, NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_cancel_grid_pointer(true)

func _draw_terrain_layers(visible: Rect2) -> void:
	var layer_height: float = maxi(1, int(_layout.get("depth_layer_height", 3))) * CELL_STEP.y
	var top: float = visible.position.y
	# Match the depth markers at the midpoint of the inter-row gap.
	# Layer one continues above the map; access rules do not limit the terrain.
	var depth: int = maxi(1, floori((top + 14.0) / layer_height) + 1)
	while top < visible.end.y:
		var bottom: float = minf(visible.end.y, depth * layer_height - 14.0)
		var strip := Rect2(Vector2(visible.position.x, top), Vector2(visible.size.x, bottom - top))
		if not FortressArt.draw_terrain(self, strip, depth):
			draw_rect(strip, Color("282b2b"))
		top = bottom
		depth += 1


func _draw_depth_layers(visible: Rect2) -> void:
	var height: int = int(_layout.get("depth_layer_height", 3))
	var count: int = int(_layout.get("depth_layers", game.floor_count))
	for layer in range(count + 1):
		var y: float = layer * height * CELL_STEP.y - 14
		if y < visible.position.y - 30 or y > visible.end.y + 30:
			continue
		var locked: bool = layer == count
		var color: Color = CORAL if locked else Color(MUTED, 0.35)
		draw_line(Vector2(visible.position.x, y), Vector2(visible.end.x, y), color, 1.5)
		var label: String = "СЛОЙ %d · ДОСТУП ЗАКРЫТ" % (layer + 1) if locked else "СЛОЙ %d" % (layer + 1)
		_text(label, Vector2(visible.position.x + 150, y - 6), 11, color)

func _draw_room_drag() -> void:
	if not _room_drag_active or not _pointer_context_valid():
		return
	var hit: Dictionary = _hit(_pointer_last)
	var target: int = int(hit.get("slot", -1))
	var existing_target: bool = Rect2(Vector2.ZERO, size).has_point(_pointer_last) and target >= 0 and _places.has(target)
	var error: String = game.room_move_error(_room_drag_from, target) if existing_target else "Выберите клетку"
	var valid: bool = existing_target and target != _room_drag_from and error.is_empty()
	var tint: Color = TEAL if valid else CORAL
	if existing_target:
		var area: Rect2 = _slot_rect(target)
		draw_rect(Rect2(_grid_camera + area.position * _grid_zoom, area.size * _grid_zoom), Color(tint, 0.18))
		draw_rect(Rect2(_grid_camera + area.position * _grid_zoom, area.size * _grid_zoom), tint, false, 2)
	draw_circle(_pointer_last, 30, Color(0.04, 0.07, 0.08, 0.9))
	if _pointer_source_identity in ["treasury", "throne"]:
		_center_text("К" if _pointer_source_identity == "treasury" else "Т", _pointer_last + Vector2(0, 7), 22, GOLD)
	else:
		_icon(str(game.rooms[_room_drag_from].id), Rect2(_pointer_last - Vector2(23, 23), Vector2(46, 46)))
	var label: String = "Отмена переноса" if target == _room_drag_from else error
	if valid:
		label = "Перенести" if _source_identity(target) == "empty" else "Поменять местами"
	_center_text(label, _pointer_last + Vector2(0, -37), 13, tint)


func _draw_mimic_links() -> void:
	var labelled: Dictionary = {}
	for key in _reserved_snapshot:
		var slot: int = int(key)
		var owner: int = int(_reserved_snapshot[key])
		if not _places.has(slot) or not _places.has(owner):
			continue
		var cleared: bool = _living_chamber_cleared(owner)
		var tint: Color = Color(CORAL, 0.2 if cleared else 0.75)
		var owner_rect: Rect2 = _slot_rect(owner)
		var mouth_rect: Rect2 = _slot_rect(slot)
		var direction: Vector2 = (mouth_rect.get_center() - owner_rect.get_center()).normalized()
		var extent: float = CELL_SIZE.x * 0.5 if absf(direction.x) > 0.5 else CELL_SIZE.y * 0.5
		# Link only the passage, keeping lines off the room art and actual sprites.
		draw_line(owner_rect.get_center() + direction * extent, mouth_rect.get_center() - direction * extent, tint, 2, true)
		if not cleared and not labelled.has(owner):
			_center_text("СЕРДЦЕ", owner_rect.position + Vector2(235, 75), 9, GOLD)
			labelled[owner] = true
		_center_text("ПАСТЬ · общий бой" if not cleared else "СЕРДЦЕ УНИЧТОЖЕНО", mouth_rect.get_center() + Vector2(0, 68), 9, tint)


func _visual_transform(at: Vector2, rotation: float = 0.0, scale_factor: Vector2 = Vector2.ONE) -> void:
	draw_set_transform(_grid_camera + at * _grid_zoom, rotation, scale_factor * _grid_zoom)

func _draw_recovering_vampires() -> void:
	var per_place: Dictionary = {}
	for recovery in _layout.get("recovering_vampires", []):
		var slot: int = int(recovery.get("place_id", -1))
		if not _places.has(slot):
			continue
		var offset: int = int(per_place.get(slot, 0))
		per_place[slot] = offset + 1
		var at: Vector2 = _slot_rect(slot).get_center() + Vector2(45 - 36 * offset, 17)
		var identity: String = str(recovery.get("actor_id", ""))
		if _actor_positions.has(identity):
			continue
		_actor_positions[identity] = at + Vector2(0, -18)
		var ready: bool = bool(recovery.get("ready", false))
		if ready:
			_icon("vampire", Rect2(at + Vector2(-18, -32), Vector2(36, 36)))
		else:
			var coffin := PackedVector2Array([at + Vector2(-10, -36), at + Vector2(10, -36), at + Vector2(15, -26), at + Vector2(10, 6), at + Vector2(-10, 6), at + Vector2(-15, -26)])
			draw_colored_polygon(coffin, Color("40343d"))
			coffin.append(coffin[0])
			draw_polyline(coffin, CORAL, 2, true)
			draw_line(at + Vector2(0, -28), at + Vector2(0, -3), GOLD, 2)
			draw_line(at + Vector2(-6, -20), at + Vector2(6, -20), GOLD, 2)
		_bar(Rect2(at + Vector2(-16, 11), Vector2(32, 3)), float(recovery.get("hp", 0)) / maxf(1.0, float(recovery.get("max_hp", 1))), CORAL)
		_center_text("ГОТОВ ПОМОЧЬ" if ready else "СОН · %d" % int(recovery.get("remaining_steps", 0)), at + Vector2(0, 28), 9, TEAL if ready else GOLD)


func _draw_vampire_flights() -> void:
	for item in _events:
		var event: Dictionary = item.event
		var kind: String = str(event.get("kind", ""))
		if kind not in ["bat_retreat", "reinforcement", "coffin_ready"]:
			continue
		var meta: Dictionary = event.get("meta", {})
		var progress: float = clampf(float(item.age) / 0.7, 0.0, 1.0)
		var alpha: float = 1.0 - progress
		if kind == "coffin_ready":
			var slot: int = int(meta.get("place_id", event.get("source_slot", -1)))
			if _places.has(slot):
				_center_text("ПРОБУЖДЕНИЕ", _slot_rect(slot).get_center() + Vector2(0, -15 - progress * 22), 11, Color(TEAL, alpha))
			continue
		var origin: int = int(meta.get("from_place", -1))
		var destination: int = int(meta.get("to_place", -1))
		if not _places.has(origin) or not _places.has(destination):
			continue
		var start: Vector2 = _slot_rect(origin).get_center() + Vector2(0, -18)
		var finish: Vector2 = _slot_rect(destination).get_center() + Vector2(0, -18)
		var at: Vector2 = start.lerp(finish, progress) + Vector2(0, -sin(progress * PI) * 35)
		draw_line(start, at, Color(CORAL, alpha * 0.35), 2, true)
		var flap: float = sin(progress * TAU * 3) * 7
		var bat := PackedVector2Array([at + Vector2(-20, -9 + flap), at + Vector2(-9, -3), at + Vector2(-4, -9), at + Vector2(0, -4), at + Vector2(4, -9), at + Vector2(9, -3), at + Vector2(20, -9 + flap), at + Vector2(12, 8), at + Vector2(4, 4), at + Vector2(0, 10), at + Vector2(-4, 4), at + Vector2(-12, 8)])
		draw_colored_polygon(bat, Color("a67494", maxf(0.4, alpha)))
		_center_text("К ГРОБУ" if kind == "bat_retreat" else "ПОДКРЕПЛЕНИЕ", at + Vector2(0, -22), 10, Color(CREAM, alpha))

func _draw_guest_actors(rect: Rect2, slot: int) -> void:
	# An empty cell, trap or throne can host a moved defender without owning it.
	var number: int = 0
	var at_throne: bool = slot == game.rooms.size()
	var guest_count: int = 0
	for actor_data in _slot_actors.get(slot, []):
		if str(actor_data.get("id", "")) != "lord":
			guest_count += 1
	for actor_data in _slot_actors.get(slot, []):
		if str(actor_data.get("id", "")) == "lord":
			continue
		var column: int = number % 2
		var row: int = number / 2
		var at: Vector2 = rect.position + Vector2((178 if at_throne else 217) + column * 34, 130 - row * 45)
		var maximum := Vector2(30, 40)
		if at_throne and guest_count == 1 and str(actor_data.get("phase_id", "")) == "throne_guard" and str(actor_data.get("path_id", "")) == "wraith_throne_guardian":
			at = rect.position + Vector2(170, 130)
			maximum = Vector2(56, 84)
		number += 1
		var identity: String = str(actor_data.get("actor_id", ""))
		_actor_positions[identity] = at + Vector2(0, -18)
		var effects: Dictionary = actor_data.get("effects", {})
		var tint: Color = Color(0.72, 0.65, 0.93, 0.6) if "spirit" in actor_data.get("tags", []) or bool(effects.get("spectral", false)) or bool(effects.get("spirit", false)) else Color.WHITE
		if str(actor_data.get("phase_id", "")) == "throne_guard":
			tint = THRONE_GUARD_TINT
		_draw_grid_actor(at, maximum, str(actor_data.get("id", "vampire")), str(actor_data.get("path_id", "")), int(actor_data.get("stage", 1)), str(actor_data.get("phase_id", "base")), effects, tint, str(actor_data.get("servant_class", "")))
		_bar(Rect2(at + Vector2(-12, 4), Vector2(24, 3)), float(actor_data.get("hp", 0)) / maxf(1.0, float(actor_data.get("max_hp", 1))), CORAL)
		_draw_defender_wards(at + Vector2(0, -18), 0.5, actor_data)
	if number > 0:
		_center_text("ПОДКРЕПЛЕНИЕ", rect.position + Vector2(198 if at_throne else 235, 148), 8, TEAL)

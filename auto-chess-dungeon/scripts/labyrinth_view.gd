extends "res://scripts/dungeon_view.gd"
## Free-grid presentation. Geometry and actions are supplied by the run model.
signal boundary_clicked(id: String)
signal expansion_clicked(position: Vector2i)
signal room_dragged(from_index: int, to_index: int)

const CELL_SIZE := Vector2(174, 146)
const CELL_STEP := Vector2(202, 174)
const MIN_ZOOM: float = 0.25
const MAX_ZOOM: float = 2.2

var build_mode: String = "rooms"
var _layout: Dictionary = {}
var _places: Dictionary = {}
var _grid_camera := Vector2.ZERO
var _camera_target := Vector2.ZERO
var _grid_zoom: float = 1.0
var _zoom_target: float = 1.0
var _camera_ready: bool = false
var _pointer_down: bool = false
var _pointer_start := Vector2.ZERO
var _pointer_last := Vector2.ZERO
var _pointer_moved: bool = false
var _pointer_button: int = 0
var _pointer_key: String = ""
var _pointer_phase: String = ""
var _pointer_wave: int = -1
var _grid_touches: Dictionary = {}
var _pinch_distance: float = 0.0
var _pinch_center := Vector2.ZERO
var _hover_key: String = ""
var _grid_styles: Dictionary = {}
var _room_drag_from: int = -1
var _room_drag_uid: int = -1
var _room_drag_active: bool = false
var _hold_time: float = 0.0
const ROOM_HOLD_SECONDS: float = 0.30


func configure(game_ref, slot: int = -1, room_id: String = "") -> void:
	if game != game_ref or (game != null and int(game.wave) == 1 and _last_wave > 1):
		_camera_ready = false
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


func reset_camera() -> void:
	_camera_ready = false
	_cancel_grid_pointer()


func fit_map() -> void:
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
	if game == null:
		return
	_camera_target = size * 0.5 - _position_for_slot(int(_layout.get("current_place", -1))) * _zoom_target


func zoom_by(factor: float) -> void:
	_zoom_at(size * 0.5, factor)


func _zoom_at(anchor: Vector2, factor: float) -> void:
	var world: Vector2 = (anchor - _camera_target) / _zoom_target
	_zoom_target = clampf(_zoom_target * factor, MIN_ZOOM, MAX_ZOOM)
	_camera_target = anchor - world * _zoom_target


func _process(delta: float) -> void:
	if _pointer_down and _room_drag_from >= 0 and not _pointer_moved and not _room_drag_active:
		_hold_time += delta
		if _hold_time >= ROOM_HOLD_SECONDS and _grid_touches.size() <= 1:
			_room_drag_active = true
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
	return _slot_rect(index).get_center() + Vector2(0, 40)


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
		_last_slot = -2
		_last_wave = int(game.wave)
	_camp_exit_slot = current if phase == "camp" else -1
	if current != _last_slot:
		_party_goal = _position_for_slot(current)
		_waypoints.append(_party_goal)
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
	_draw_depth_layers(visible)
	for boundary in _layout.get("boundaries", []):
		_draw_boundary(boundary)
	if str(game.phase) == "prepare" and build_mode == "excavate":
		for coordinate in _layout.get("expansion_cells", []):
			var rect := Rect2(Vector2(coordinate) * CELL_STEP, CELL_SIZE)
			if not visible.intersects(rect):
				continue
			draw_rect(rect.grow(-3), Color("15232a"))
			draw_rect(rect.grow(-3), Color(TEAL, 0.45), false, 1.5)
			_center_text("+", rect.get_center() + Vector2(0, -3), 28, TEAL)
			_center_text("%d зол." % game.grid_expansion_cost(), rect.get_center() + Vector2(0, 24), 13, MUTED)
	for place in _places.values():
		if visible.intersects(_place_rect(place)):
			_draw_place(place)
	# Wall handles are drawn over cell edges, but never over room content.
	if build_mode == "walls" and str(game.phase) == "prepare":
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


func _draw_place(place: Dictionary) -> void:
	var index: int = int(place.slot)
	var kind: String = str(place.get("type", "room"))
	var rect: Rect2 = _place_rect(place)
	var center: Vector2 = rect.get_center()
	var active: bool = str(game.phase) in ["raid", "camp"] and int(_layout.get("current_place", -1)) == index
	var selected: bool = index >= 0 and index == selected_slot
	var tint: Color = GOLD if kind in ["treasury", "throne"] else TEAL
	var style_key: String = "%s:%s:%s" % [kind, selected, active]
	if not _grid_styles.has(style_key):
		var frame := StyleBoxFlat.new()
		frame.bg_color = Color("1a2529") if not selected else Color("203d39")
		frame.border_color = tint if selected or active else Color("49534f")
		frame.set_border_width_all(2 if active or selected else 1)
		frame.set_corner_radius_all(9)
		_grid_styles[style_key] = frame
	draw_style_box(_grid_styles[style_key], rect)
	_text("%d : %d" % [int(place.position.x), int(place.position.y)], rect.position + Vector2(10, 18), 10, MUTED)
	if kind == "entrance":
		_center_text("ВХОД / ВЫХОД", center + Vector2(0, -28), 13, TEAL)
		draw_arc(center + Vector2(0, 6), 22, PI, TAU, 24, MUTED, 4, true)
		draw_line(center + Vector2(-22, 6), center + Vector2(-22, 31), MUTED, 4)
		draw_line(center + Vector2(22, 6), center + Vector2(22, 31), MUTED, 4)
		_draw_direction_arrow(center + Vector2(-11, 14), center + Vector2(12, 14), TEAL)
		return
	if kind == "treasury":
		_center_text("СОКРОВИЩНИЦА", center + Vector2(0, -29), 13, GOLD)
		draw_rect(Rect2(center + Vector2(-28, -9), Vector2(56, 34)), Color("755333"))
		draw_rect(Rect2(center + Vector2(-31, -17), Vector2(62, 14)), GOLD)
		draw_rect(Rect2(center + Vector2(-5, -6), Vector2(10, 16)), Color("f0d788"))
		_center_text("Половина золота под угрозой", rect.position + Vector2(CELL_SIZE.x * 0.5, 128), 10, MUTED)
		return
	if kind == "throne":
		_center_text("ТРОН", center + Vector2(0, -29), 14, GOLD)
		var visual: Dictionary = _lord_visual()
		_icon(str(visual.get("icon", "lord")), Rect2(center + Vector2(-25, -20), Vector2(50, 50)))
		_actor_positions["lord"] = center
		_bar(Rect2(center + Vector2(-31, 37), Vector2(62, 4)), float(game.lord.hp) / maxf(1, int(game.lord.max_hp)), GOLD)
		_draw_defender_wards(center, 0.65, game.lord)
		_draw_guest_actors(rect, game.rooms.size())
		return
	if index < 0 or index >= game.rooms.size():
		return
	var room: Dictionary = game.rooms[index]
	if room.is_empty():
		if _reserved_snapshot.has(index):
			_draw_reserved_growth(rect, index)
		elif _slot_actors.has(index):
			_draw_guest_actors(rect, index)
		elif not selected_room.is_empty() and str(game.phase) == "prepare" and build_mode == "rooms":
			_icon(selected_room, Rect2(center + Vector2(-23, -20), Vector2(46, 46)), Color(1, 1, 1, 0.42))
			_center_text("РАЗМЕСТИТЬ", center + Vector2(0, 47), 11, TEAL)
		else:
			_center_text("+", center + Vector2(0, 8), 25, Color(MUTED, 0.55))
			_center_text("ПУСТАЯ КОМНАТА", center + Vector2(0, 43), 10, MUTED)
		return
	var stats: Dictionary = _room_snapshot[index] if index < _room_snapshot.size() else {}
	if stats.is_empty():
		return
	if bool(stats.get("deadly_corridor_receiver", false)):
		_text("РУБЕЖ", rect.position + Vector2(63, 18), 9, GOLD)
	var cleared: bool = str(room.get("status", "")) == "cleared" and str(stats.get("kind", "")) == "monster"
	_center_text_fitted(str(stats.get("short_name", stats.get("name", ""))), center + Vector2(0, -39), 12, CREAM, CELL_SIZE.x - 20)
	_text("R%d" % int(room.get("rank", 1)), rect.position + Vector2(140, 18), 10, GOLD)
	if str(room.get("status", "")) == "retreated" and not _slot_actors.has(index):
		_center_text("ВАМПИР УЛЕТЕЛ", center + Vector2(0, 9), 11, MUTED)
		return
	if not str(stats.get("evolution_path", "")).is_empty():
		_draw_evolution_props(rect, index, stats, cleared)
	if str(stats.get("kind", "")) == "monster":
		_draw_evolution_actors(rect, index, stats, cleared)
	else:
		_icon(str(stats.id), Rect2(center + Vector2(-25, -24), Vector2(50, 50)))
		_actor_positions["room_%d" % index] = center
		_draw_guest_actors(rect, index)
	if int(stats.get("hp", 0)) > 0:
		var hp: float = float(room.get("current_hp", stats.hp))
		var maximum: float = float(stats.hp)
		if _slot_actors.has(index):
			hp = _actors_health(index, "hp")
			maximum = _actors_health(index, "max_hp")
		_bar(Rect2(center + Vector2(-29, 33), Vector2(58, 4)), hp / maxf(1, maximum), CORAL)
	if index in _layout.get("disabled_slots", []):
		_center_text("ОБЕЗВРЕЖЕНА", center + Vector2(0, 51), 10, CORAL)
	elif str(stats.get("evolution_path", "")) == "ballista_reserve_magazine":
		_center_text("Болты: %d" % int(room.get("evolution_memory", {}).get("ammo", 0)), center + Vector2(0, 51), 10, GOLD)


func _draw_grid_party() -> void:
	var living: Array[Dictionary] = []
	for hero in game.heroes:
		if int(hero.hp) > 0 and not bool(hero.get("escaped", false)):
			living.append(hero)
	for i in range(living.size()):
		var hero: Dictionary = living[i]
		var id: String = str(hero.get("instance_id", hero.id))
		var at: Vector2 = _party_position + Vector2((i - (living.size() - 1) * 0.5) * 28, 10)
		_hero_positions[id] = at
		draw_circle(at + Vector2(0, -9), 15, Color("0e181e"))
		_icon(str(hero.id), Rect2(at + Vector2(-11, -22), Vector2(22, 22)))
		_bar(Rect2(at + Vector2(-10, 3), Vector2(20, 3)), float(hero.hp) / maxf(1, int(hero.max_hp)), TEAL)
		if int(hero.get("poison_ticks", 0)) > 0:
			draw_circle(at + Vector2(9, -20), 2, Color("92b957"))
		var loot: int = int(_layout.get("loot_shares", {}).get(id, 0))
		if loot > 0:
			_center_text(str(loot), at + Vector2(0, -29), 10, GOLD)
	_draw_party_links(living)


func _hit(at: Vector2) -> Dictionary:
	var world: Vector2 = (at - _grid_camera) / _grid_zoom
	if build_mode == "walls":
		var best: Dictionary = {}
		var best_distance: float = 23.0 / _grid_zoom
		for boundary in _layout.get("boundaries", []):
			var middle: Vector2 = (_slot_rect(int(boundary.a)).get_center() + _slot_rect(int(boundary.b)).get_center()) * 0.5
			var distance: float = world.distance_to(middle)
			if distance < best_distance:
				best_distance = distance
				best = {"kind": "boundary", "id": str(boundary.id), "key": "b:" + str(boundary.id)}
		return best
	if build_mode == "excavate":
		for coordinate in _layout.get("expansion_cells", []):
			if Rect2(Vector2(coordinate) * CELL_STEP, CELL_SIZE).has_point(world):
				return {"kind": "expansion", "position": coordinate, "key": "e:%s" % str(coordinate)}
	for place in _places.values():
		if _place_rect(place).has_point(world):
			return {"kind": "slot", "slot": int(place.slot), "key": "s:%d" % int(place.slot)}
	return {}


func _slot_at(at: Vector2) -> int:
	return int(_hit(at).get("slot", -1))


func _get_tooltip(at_position: Vector2) -> String:
	var hit: Dictionary = _hit(at_position)
	if hit.is_empty():
		return ""
	if str(hit.kind) == "boundary":
		return "Выберите границу, чтобы открыть проход или возвести стену."
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


func _input(_event: InputEvent) -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMagnifyGesture:
		_cancel_grid_pointer()
		_zoom_at(event.position, event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		_cancel_grid_pointer()
		_camera_target -= event.delta * 22
		accept_event()
	elif event is InputEventMouseButton and event.device != -1:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_cancel_grid_pointer()
			_zoom_at(event.position, exp((0.14 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -0.14) * maxf(0.1, event.factor)))
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				_start_grid_pointer(event.position, event.button_index)
			elif _pointer_down:
				_finish_grid_pointer(event.position)
			accept_event()
	elif event is InputEventMouseMotion and event.device != -1:
		if _pointer_down:
			_drag_grid_pointer(event.position)
		_hover_key = str(_hit(event.position).get("key", ""))
	elif event is InputEventScreenTouch:
		if event.pressed:
			_grid_touches[event.index] = event.position
			if _grid_touches.size() == 1:
				_start_grid_pointer(event.position, MOUSE_BUTTON_LEFT)
			else:
				_room_drag_active = false
				_room_drag_from = -1
				_pointer_moved = true
				_reset_pinch()
		else:
			var was_single: bool = _grid_touches.size() == 1
			_grid_touches.erase(event.index)
			if was_single and not event.canceled:
				_finish_grid_pointer(event.position)
			elif _grid_touches.is_empty():
				_cancel_grid_pointer()
			else:
				_pointer_moved = true
				_pointer_last = _grid_touches.values()[0]
		accept_event()
	elif event is InputEventScreenDrag:
		if _grid_touches.has(event.index):
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


func _start_grid_pointer(at: Vector2, button: int) -> void:
	_pointer_down = true
	_pointer_start = at
	_pointer_last = at
	_pointer_moved = false
	_pointer_button = button
	_pointer_key = str(_hit(at).get("key", ""))
	_pointer_phase = str(game.phase)
	_pointer_wave = int(game.wave)
	_hold_time = 0.0
	_room_drag_from = -1
	_room_drag_active = false
	var hit: Dictionary = _hit(at)
	var index: int = int(hit.get("slot", -1))
	if button == MOUSE_BUTTON_LEFT and build_mode == "rooms" and game.phase == "prepare" and selected_room.is_empty() and index >= 0 and index < game.rooms.size() and not game.rooms[index].is_empty():
		_room_drag_from = index
		_room_drag_uid = int(game.rooms[index].get("instance_id", -1))


func _drag_grid_pointer(at: Vector2) -> void:
	if _room_drag_active:
		_pointer_last = at
		queue_redraw()
		return
	if at.distance_to(_pointer_start) > TAP_DRAG_DISTANCE:
		_pointer_moved = true
		_room_drag_from = -1
	if _pointer_moved:
		_camera_target += at - _pointer_last
		_grid_camera = _camera_target
	_pointer_last = at


func _finish_grid_pointer(at: Vector2) -> void:
	var hit: Dictionary = _hit(at)
	if _room_drag_active:
		var origin: int = _room_drag_from
		var destination: int = int(hit.get("slot", -1))
		var valid: bool = is_visible_in_tree() and str(game.phase) == _pointer_phase and int(game.wave) == _pointer_wave and origin >= 0 and origin < game.rooms.size() and int(game.rooms[origin].get("instance_id", -2)) == _room_drag_uid
		_cancel_grid_pointer()
		if valid and destination >= 0 and destination != origin:
			room_dragged.emit(origin, destination)
		return
	var commit: bool = _pointer_down and not _pointer_moved and at.distance_to(_pointer_start) <= TAP_DRAG_DISTANCE and _pointer_button == MOUSE_BUTTON_LEFT and str(hit.get("key", "")) == _pointer_key and not _pointer_key.is_empty() and str(game.phase) == _pointer_phase and int(game.wave) == _pointer_wave
	_cancel_grid_pointer()
	if not commit or not is_visible_in_tree():
		return
	match str(hit.kind):
		"boundary": boundary_clicked.emit(str(hit.id))
		"expansion": expansion_clicked.emit(Vector2i(hit.position))
		"slot": slot_clicked.emit(int(hit.slot))


func _cancel_grid_pointer() -> void:
	_room_drag_active = false
	_room_drag_from = -1
	_room_drag_uid = -1
	_hold_time = 0.0
	_pointer_down = false
	_pointer_key = ""
	_grid_touches.clear()
	_pinch_distance = 0


func _notification(what: int) -> void:
	super._notification(what)
	if what in [NOTIFICATION_EXIT_TREE, NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_cancel_grid_pointer()

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
	if not _room_drag_active or _room_drag_from < 0 or _room_drag_from >= game.rooms.size():
		return
	var hit: Dictionary = _hit(_pointer_last)
	var target: int = int(hit.get("slot", -1))
	var valid: bool = target >= 0 and target < game.rooms.size() and not game.is_treasury_slot(target) and not game.is_throne_slot(target) and (not _reserved_snapshot.has(target) or int(_reserved_snapshot[target]) == _room_drag_from)
	var tint: Color = TEAL if valid else CORAL
	if target >= 0 and _places.has(target):
		var area: Rect2 = _slot_rect(target)
		draw_rect(Rect2(_grid_camera + area.position * _grid_zoom, area.size * _grid_zoom), Color(tint, 0.18))
		draw_rect(Rect2(_grid_camera + area.position * _grid_zoom, area.size * _grid_zoom), tint, false, 2)
	draw_circle(_pointer_last, 30, Color(0.04, 0.07, 0.08, 0.9))
	_icon(str(game.rooms[_room_drag_from].id), Rect2(_pointer_last - Vector2(23, 23), Vector2(46, 46)))
	var label: String = "Выберите клетку"
	if valid:
		label = "Перенести" if game.rooms[target].is_empty() else "Поменять местами"
	_center_text(label, _pointer_last + Vector2(0, -37), 13, tint)


func _draw_mimic_links() -> void:
	for key in _reserved_snapshot:
		var slot: int = int(key)
		var owner: int = int(_reserved_snapshot[key])
		if not _places.has(slot) or not _places.has(owner):
			continue
		var cleared: bool = str(game.rooms[owner].get("status", "")) == "cleared"
		var tint: Color = Color(CORAL, 0.2 if cleared else 0.75)
		var centre: Vector2 = _slot_rect(owner).get_center()
		var mouth: Vector2 = _slot_rect(slot).get_center()
		draw_line(centre, mouth, tint, 2, true)
		draw_circle(centre + Vector2(-50, -45), 5, tint)
		_center_text("СЕРДЦЕ", centre + Vector2(0, -52), 10, tint)
		_center_text("ПАСТЬ · общий бой" if not cleared else "СЕРДЦЕ УНИЧТОЖЕНО", mouth + Vector2(0, 52), 10, tint)


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
	for actor_data in _slot_actors.get(slot, []):
		if str(actor_data.get("id", "")) == "lord":
			continue
		var at: Vector2 = rect.get_center() + Vector2(48 - number * 40, 24)
		number += 1
		var identity: String = str(actor_data.get("actor_id", ""))
		_actor_positions[identity] = at + Vector2(0, -18)
		var rendered: bool = EvolutionVisuals.actor(self, at, 0.62, str(actor_data.get("path_id", "")), str(actor_data.get("phase_id", "base")), actor_data.get("effects", {}), _clock)
		if not rendered:
			_icon(str(actor_data.get("id", "vampire")), Rect2(at + Vector2(-17, -34), Vector2(34, 34)))
		_bar(Rect2(at + Vector2(-17, 4), Vector2(34, 3)), float(actor_data.get("hp", 0)) / maxf(1.0, float(actor_data.get("max_hp", 1))), CORAL)
		_draw_defender_wards(at + Vector2(0, -18), 0.5, actor_data)
		_center_text("ПОДКРЕПЛЕНИЕ", at + Vector2(0, 20), 8, TEAL)
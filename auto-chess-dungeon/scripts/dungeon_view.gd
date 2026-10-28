extends Control
## Presentation only: a living cutaway of the deterministic dungeon model.
## The view never advances combat or modifies the run state.

signal slot_clicked(index: int)
signal soul_visual_requested(origin: Vector2, amount: int)

const Content = preload("res://scripts/content_catalog.gd")
const Lords = preload("res://scripts/lord_catalog.gd")
const EvolutionVisuals = preload("res://scripts/evolution_visuals.gd")
const HeroRules = preload("res://scripts/hero_rules.gd")
const FLOOR_HEIGHT: float = 160.0
const THRONE_HEIGHT: float = 170.0
const INK = Color("101719")
const STONE = Color("343838")
const MORTAR = Color("23292a")
const CREAM = Color("e1d4b2")
const MUTED = Color("8f978e")
const GOLD = Color("d6aa60")
const TEAL = Color("77bbab")
const CORAL = Color("df8070")
const TAP_DRAG_DISTANCE: float = 12.0

var game = null
var selected_slot: int = -1
var selected_room: String = ""
var cinematic: bool = false
var show_party: bool = true
var tutorial_slot: int = -1
## Set by the UI before configure/refresh; floor and model indices stay unchanged.
var compact: bool = false

var _clock: float = 0.0
var _hit_rects: Array[Rect2] = []
var _textures: Dictionary = {}
var _font: Font
var _hovered_slot: int = -1
var _party_position: Vector2 = Vector2(-40, 96)
var _party_goal: Vector2 = Vector2(-40, 96)
var _party_direction: float = 1.0
var _last_slot: int = -2
var _last_phase: String = ""
var _last_wave: int = -1
var _waypoints: Array[Vector2] = []
var _last_action_seq: int = -1
var _room_snapshot: Array[Dictionary] = []
var _combo_snapshot: Array = []
var _reserved_snapshot: Dictionary = {}
var _hero_definitions: Dictionary = {}
var _hero_equipment: Dictionary = {}
var _hero_effects: Dictionary = {}
var _slot_actors: Dictionary = {}
var _room_visual_state: Dictionary = {}
var _camp_snapshot: Dictionary = {}
## Retained until the party leaves the exit, including a paused E interruption.
var _camp_exit_slot: int = -1
var _defeated_centers: Dictionary = {}
var _throne_guard_slot: int = -1
var _actor_positions: Dictionary = {}
var _hero_positions: Dictionary = {}
var _events: Array[Dictionary] = []
var _last_event_seq: int = -1
## Set by the host: presentation clocks stop with the combat clock.
var animation_paused: bool = false
var animation_speed: float = 1.0
var _frame_blend: float = 1.0
var _hit_flash: float = 0.0
var _pressed_slot: int = -1
var _press_position: Vector2 = Vector2.ZERO
var _press_dragged: bool = false
var _touch_index: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_font = ThemeDB.fallback_font
	mouse_exited.connect(_on_mouse_exited)
	resized.connect(_on_resized)
	refresh()


func configure(game_ref, slot: int = -1, room_id: String = "") -> void:
	if game != game_ref:
		_last_slot = -2
		_last_wave = -1
		_last_phase = ""
		_camp_exit_slot = -1
		_camp_snapshot.clear()
		_waypoints.clear()
		_last_action_seq = -1
		_last_event_seq = -1
		_events.clear()
		_hero_positions.clear()
	game = game_ref
	selected_slot = slot
	selected_room = room_id
	refresh()


func refresh() -> void:
	var floors: int = 1 if game == null else int(game.floor_count)
	# Let the enclosing ScrollContainer receive touch drags before committing a tap.
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = Vector2(280 if compact else 500, (280 if compact else 500) if cinematic else floors * FLOOR_HEIGHT + THRONE_HEIGHT)
	_room_snapshot.clear()
	_combo_snapshot.clear()
	_reserved_snapshot.clear()
	_throne_guard_slot = -1
	if game != null:
		# Catalog/faction calculations happen once per structural UI refresh,
		# never from _draw or _process. Raid HP/effects remain live actor data.
		for index in range(game.rooms.size()):
			_room_snapshot.append({} if game.rooms[index].is_empty() else game.room_stats(index))
		_combo_snapshot = game.active_combos()
		if game.has_method("reserved_room_slots"):
			_reserved_snapshot = game.reserved_room_slots()
		if game.has_method("throne_guard_room_slot"):
			_throne_guard_slot = game.throne_guard_room_slot()
		for hero in game.heroes:
			_hero_definitions[str(hero.id)] = Content.hero(str(hero.id))
	refresh_runtime()
	queue_redraw()


func refresh_runtime() -> void:
	_slot_actors.clear()
	_hero_equipment.clear()
	_hero_effects.clear()
	_room_visual_state.clear()
	_defeated_centers.clear()
	_camp_snapshot.clear()
	if game == null:
		return
	var seq_value = game.get("action_seq")
	var seq: int = int(seq_value) if seq_value != null else int(game.tick)
	if seq < _last_action_seq:
		# Game.restart reuses the same object but starts a new event sequence.
		_last_action_seq = -1
		_last_event_seq = -1
		_events.clear()
		_hero_positions.clear()
		_actor_positions.clear()
		_waypoints.clear()
		_last_wave = -1
		_last_slot = -2
		_last_phase = ""
		_camp_exit_slot = -1
	if str(game.phase) == "camp":
		_camp_snapshot = game.camp_status()
	if not cinematic:
		# Synchronize phase/route even on pause, before accepting this frame's events.
		_update_party(0.0)
	for hero in game.heroes:
		var gear: Dictionary = {}
		for item in HeroRules.equipment_summary(hero):
			if bool(item.get("active", true)):
				gear[str(item.slot)] = str(item.visual_key)
		_hero_equipment[str(hero.get("instance_id", hero.id))] = gear
		var effects: Dictionary = hero.get("effects", {}).duplicate()
		effects.has_spore = hero.has("spore")
		if hero.has("cursed_cup"):
			effects.cursed_cup = hero.cursed_cup
		effects.stored_spell = bool(hero.get("equipment_state", {}).get("stored_spell", false))
		effects.cover_active = int(effects.get("cover_until", -1)) >= int(game.combat_tick)
		_hero_effects[str(hero.get("instance_id", hero.id))] = effects
	var actors = game.get("defenders")
	if actors is Array:
		for actor_data in actors:
			if int(actor_data.get("hp", 0)) <= 0:
				if str(actor_data.get("phase_id", "")) == "base":
					_defeated_centers[int(actor_data.get("source_slot", -1))] = true
				continue
			var slot: int = int(actor_data.get("display_slot", actor_data.get("source_slot", game.current_slot)))
			if str(actor_data.get("phase_id", "")) == "throne_guard" or str(actor_data.get("id", "")) == "lord":
				slot = game.rooms.size()
			if not _slot_actors.has(slot):
				_slot_actors[slot] = []
			_slot_actors[slot].append(actor_data)
	elif not game.defender.is_empty():
		_slot_actors[int(game.current_slot)] = [game.defender]
	for slot in range(game.rooms.size()):
		var room: Dictionary = game.rooms[slot]
		if room.is_empty():
			continue
		var actors_here: Array = _slot_actors.get(slot, [])
		var state: Dictionary = (actors_here[0] if not actors_here.is_empty() else room).duplicate()
		state.ammo = int(room.get("evolution_memory", {}).get("ammo", 0))
		_room_visual_state[slot] = state
	if seq != _last_action_seq:
		_last_action_seq = seq
		_hit_flash = 1.0 if str(game.phase) == "raid" and _camp_exit_slot < 0 else 0.0
		var combat_events = game.get("combat_events")
		if combat_events is Array:
			for event in combat_events:
				var event_seq: int = int(event.get("seq", 0))
				if event_seq <= _last_event_seq:
					continue
				_last_event_seq = event_seq
				_events.append({"event": event.duplicate(true), "age": 0.0})
				if str(event.get("kind", "")) in ["soul", "soul_shatter"]:
					var origin: Vector2 = _hero_positions.get(str(event.get("actor", "")), _party_position) + Vector2(0, -20)
					soul_visual_requested.emit(get_global_transform() * origin, int(event.get("amount", 0)))
			while _events.size() > 24:
				_events.pop_front()
	queue_redraw()


func refresh_camp_time() -> void:
	# The simulation is frozen between camp pulses; retain room/equipment caches.
	_camp_snapshot = game.camp_status() if game != null and str(game.phase) == "camp" else {}
	queue_redraw()


func _on_resized() -> void:
	_cancel_press()
	# Old pixel coordinates must not survive a phone rotation or a layout change.
	if game != null and not cinematic:
		_waypoints.clear()
		_party_position = _position_for_slot(int(game.current_slot))
		_party_goal = _party_position
		_last_slot = int(game.current_slot)
		_hero_positions.clear()
		_actor_positions.clear()
	queue_redraw()


func _process(delta: float) -> void:
	var visual_delta: float = 0.0 if animation_paused else delta * animation_speed
	_frame_blend = minf(1.0, visual_delta * 12.0)
	_clock += visual_delta
	_hit_flash = maxf(0.0, _hit_flash - visual_delta * 3.6)
	for item in _events:
		item.age += visual_delta
	while not _events.is_empty() and float(_events[0].age) > 0.8:
		_events.pop_front()
	if game != null and not cinematic:
		_update_party(visual_delta)
	queue_redraw()


func _update_party(delta: float) -> void:
	var phase: String = str(game.phase)
	var current: int = int(game.current_slot)
	var new_wave: bool = int(game.wave) != _last_wave or (phase == "raid" and _last_phase == "prepare")
	if new_wave:
		_hero_positions.clear()
		_actor_positions.clear()
		_events.clear()
		_camp_exit_slot = -1
		_party_position = Vector2(18, _floor_walk_y(0))
		_party_direction = 1.0
		_waypoints.clear()
		_last_slot = -2
		_last_wave = int(game.wave)
	if phase == "camp":
		_camp_exit_slot = int(_camp_snapshot.get("slot", current))
	elif current != _camp_exit_slot:
		_camp_exit_slot = -1
	if current != _last_slot or (phase == "camp" and _last_phase != "camp"):
		var goal: Vector2 = _position_for_slot(current)
		# Preserve pending stairs when simulation advances ahead of the animation.
		# Empty floors still contribute both landings to the visible route.
		if current >= 0:
			var from_floor: int = maxi(0, _last_slot) / 5
			var to_floor: int = mini(current / 5, int(game.floor_count))
			for floor_index in range(from_floor, to_floor):
				var shaft_x: float = _floor_exit_x(floor_index)
				_waypoints.append(Vector2(shaft_x, _floor_walk_y(floor_index)))
				_waypoints.append(Vector2(shaft_x, _floor_walk_y(floor_index + 1)))
		_waypoints.append(goal)
		_party_goal = goal
		_last_slot = current
	if delta > 0.0 and not _waypoints.is_empty():
		var remaining_distance: float = 0.0
		var previous: Vector2 = _party_position
		for waypoint in _waypoints:
			remaining_distance += previous.distance_to(waypoint)
			previous = waypoint
		var travel: float = delta * maxf(260.0, remaining_distance * 7.0)
		while not _waypoints.is_empty() and travel > 0.0:
			var target: Vector2 = _waypoints[0]
			var distance: float = _party_position.distance_to(target)
			if absf(target.x - _party_position.x) > 0.1:
				_party_direction = signf(target.x - _party_position.x)
			if distance <= travel:
				_party_position = target
				travel -= distance
				_waypoints.pop_front()
			else:
				_party_position = _party_position.move_toward(target, travel)
				travel = 0.0
	_last_phase = phase


func _position_for_slot(index: int) -> Vector2:
	if game == null or index < 0:
		return Vector2(18, _floor_walk_y(0))
	if index >= game.rooms.size():
		return Vector2(size.x * 0.5 + (0 if compact else 18) - (66 if compact else 80) * _floor_direction(int(game.floor_count)), _floor_walk_y(int(game.floor_count)))
	var room_rect: Rect2 = _slot_rect(index)
	var approach: float = 0.5 if compact or index == _camp_exit_slot else (0.30 if _floor_direction(index / 5) > 0.0 else 0.70)
	return Vector2(room_rect.position.x + room_rect.size.x * approach, _floor_walk_y(index / 5))


func _floor_direction(floor_index: int) -> float:
	return 1.0 if floor_index % 2 == 0 else -1.0


func _floor_exit_x(floor_index: int) -> float:
	var inset: float = 8.0 if compact else 18.0
	return size.x - inset if _floor_direction(floor_index) > 0.0 else inset


func _floor_walk_y(floor_index: int) -> float:
	return floor_index * FLOOR_HEIGHT + 114.0


func _slot_rect(index: int) -> Rect2:
	var inset: float = 16.0 if compact else 49.0
	var room_width: float = maxf(1.0, (size.x - inset * 2.0) / 5.0)
	return Rect2(inset + (index % 5) * room_width, floori(float(index) / 5.0) * FLOOR_HEIGHT + 28, room_width, 120)


func _draw() -> void:
	if _font == null:
		_font = ThemeDB.fallback_font
	if cinematic:
		_draw_cinematic()
		return
	if game == null:
		return
	_hit_rects.clear()
	_hit_rects.resize(game.rooms.size())
	_actor_positions.clear()
	draw_rect(Rect2(Vector2.ZERO, size), Color("171c1d"))
	var visible_start: int = 0
	var visible_end: int = int(game.floor_count)
	if get_parent() is ScrollContainer:
		var scroll := get_parent() as ScrollContainer
		visible_start = maxi(0, floori(float(scroll.scroll_vertical) / FLOOR_HEIGHT) - 1)
		visible_end = mini(int(game.floor_count), ceili((scroll.scroll_vertical + scroll.size.y) / FLOOR_HEIGHT) + 1)
	_draw_bedrock(Rect2(Vector2(0, visible_start * FLOOR_HEIGHT), Vector2(size.x, (visible_end - visible_start) * FLOOR_HEIGHT + THRONE_HEIGHT)))
	for floor_index in range(visible_start, visible_end):
		_draw_floor(floor_index)
	_draw_combos()
	_draw_throne()
	_draw_camp()
	if show_party and str(game.phase) in ["raid", "camp", "result", "defeat"]:
		_draw_party()
	_draw_event_feedback()
	if tutorial_slot >= 0 and tutorial_slot < game.rooms.size():
		var target: Rect2 = _slot_rect(tutorial_slot).grow(-3)
		var glow: Color = GOLD
		glow.a = 0.72 + sin(_clock * 4) * 0.22
		draw_rect(target, glow, false, 3.0)
		var point: Vector2 = target.get_center() + Vector2(0, -14 + sin(_clock * 4) * 3)
		draw_colored_polygon(PackedVector2Array([point + Vector2(-7, -12), point + Vector2(7, -12), point]), GOLD)
		_center_text("СЮДА" if compact else "НАЖМИТЕ", Vector2(target.get_center().x, target.end.y - 27), 10, GOLD)


func _draw_bedrock(area: Rect2) -> void:
	var y: float = area.position.y + 10
	var row: int = 0
	while y < area.end.y:
		for column in range(13):
			var x: float = area.position.x + column * 73.0 + (-29.0 if row % 2 == 0 else 0.0)
			draw_line(Vector2(x, y), Vector2(x + 43, y + 9), Color(0.22, 0.25, 0.24, 0.20), 1)
		y += 53
		row += 1


func _draw_floor(floor_index: int) -> void:
	var top: float = floor_index * FLOOR_HEIGHT
	var label_text: String = "ЭТАЖ %02d" % (floor_index + 1)
	var floor_kind: String = "plain"
	var floor_types = game.get("floor_traits")
	if floor_types is Array and floor_index < floor_types.size():
		floor_kind = str(floor_types[floor_index])
	var floor_names: Dictionary = {"plain": "КАЗЕМАТЫ", "laboratory": "ЛАБОРАТОРИЯ", "barracks": "КАЗАРМЫ", "workshop": "МАСТЕРСКАЯ"}
	var floor_colors: Dictionary = {"plain": MUTED, "laboratory": TEAL, "barracks": CORAL, "workshop": GOLD}
	_text(label_text, Vector2(8 if compact else 17, top + 19), 11 if compact else 12, GOLD)
	_text(str(floor_names.get(floor_kind, "КАЗЕМАТЫ")), Vector2(83 if compact else 102, top + 19), 9 if compact else 10, floor_colors.get(floor_kind, MUTED))
	var route_direction: float = _floor_direction(floor_index)
	var route_length: float = 25.0 if compact else 48.0
	var route_inset: float = 12.0 if compact else 18.0
	var arrow_tip: Vector2 = Vector2(size.x - route_inset - (route_length if route_direction < 0 else 0.0), top + 15)
	_draw_direction_arrow(arrow_tip - Vector2(route_length * route_direction, 0), arrow_tip, MUTED)
	for column in range(5):
		var index: int = floor_index * 5 + column
		var rect: Rect2 = _slot_rect(index)
		_hit_rects[index] = rect
		_draw_chamber(rect, index)
	var platform_inset: float = 13.0 if compact else 40.0
	_draw_platform(Rect2(platform_inset, top + 144, size.x - platform_inset * 2, 15), floor_index)
	_draw_stairway(floor_index)


func _draw_chamber(rect: Rect2, index: int) -> void:
	if compact:
		_draw_compact_chamber(rect, index)
		return
	var room: Dictionary = game.rooms[index]
	var active: bool = str(game.phase) == "raid" and int(game.current_slot) == index and index != _camp_exit_slot
	var chosen: bool = selected_slot == index
	var hovered: bool = _hovered_slot == index and str(game.phase) == "prepare"
	var cleared: bool = str(room.get("status", "")) == "cleared"
	var ceiling: float = rect.position.y
	var ground: float = rect.end.y - 16
	var center: Vector2 = Vector2(rect.get_center().x, ground)
	var cavity: Rect2 = rect.grow(-5)
	draw_rect(cavity, Color("151c1d") if index % 2 == 0 else Color("182021"))
	_draw_masonry(cavity)
	if active:
		draw_rect(cavity, Color(0.63, 0.38, 0.14, 0.13 + 0.04 * sin(_clock * 3)))
	elif chosen or hovered:
		draw_rect(cavity, Color(0.31, 0.61, 0.52, 0.12 if chosen else 0.06))
	_draw_arch(rect, GOLD if active else (TEAL if chosen else Color("515550")))
	if chosen or hovered:
		draw_line(Vector2(rect.position.x + 5, ground + 1), Vector2(rect.end.x - 5, ground + 1), TEAL if chosen else Color("658078"), 3)
	_text("%02d" % (index % 5 + 1), Vector2(rect.position.x + 10, ceiling + 21), 9, Color("626f69"))
	if index % 2 == 0:
		_draw_torch(Vector2(rect.end.x - 17, ceiling + 38), float(index))
	if index == _camp_exit_slot:
		# The geometric exit may be empty; it never supplies a camp defender.
		if not room.is_empty():
			_draw_rubble(Vector2(center.x, ground), 0.5)
		return
	if room.is_empty():
		if _reserved_snapshot.has(index):
			_draw_reserved_growth(rect, index)
		else:
			_draw_empty_room(rect, hovered)
		return
	var stats: Dictionary = _room_snapshot[index] if index < _room_snapshot.size() else {}
	if stats.is_empty():
		return
	var id: String = str(stats.id)
	var tint: Color = Color(0.54, 0.56, 0.54, 0.40) if cleared else Color.WHITE
	var path: String = str(stats.get("evolution_path", ""))
	if path.is_empty():
		_draw_room_props(id, rect, cleared)
	else:
		_draw_evolution_props(rect, index, stats, cleared)
	var figure_size: float = clampf(rect.size.x * 0.47, 38, 55)
	if id == "ogre":
		figure_size *= 1.12
	var offset: float = 15.0 * _floor_direction(index / 5) if active else 0.0
	var monster_at: Vector2 = center + Vector2(offset, -8)
	var idle: float = sin(_clock * 2.1 + index * 1.7) * 1.2
	if not path.is_empty() or _slot_actors.has(index):
		_draw_evolution_actors(rect, index, stats, cleared)
	elif id == "poison":
		_icon(id, Rect2(monster_at.x - figure_size / 2, monster_at.y - figure_size - 1, figure_size, figure_size), tint)
		_draw_poison_motes(monster_at, float(index), cleared)
	elif str(stats.get("kind", "")) != "monster":
		_icon(id, Rect2(center.x - figure_size / 2, center.y - figure_size + 3, figure_size, figure_size), tint)
	else:
		_draw_creature_body(id, monster_at + Vector2(0, idle), figure_size, tint)
		_icon(id, Rect2(monster_at.x - figure_size / 2, monster_at.y - figure_size - 8 + idle, figure_size, figure_size), tint)
		if active:
			_draw_defender_wards(monster_at + Vector2(0, -figure_size * 0.5 - 8 + idle), figure_size / 55.0)
	var name_size: int = 10 if rect.size.x < 112 else 12
	_center_text(str(stats.short_name), Vector2(center.x, rect.end.y - 8), name_size, Color("929c91") if cleared else CREAM)
	var rank: int = int(room.get("rank", 1))
	draw_rect(Rect2(rect.end.x - 30, ceiling + 13, 19, 13), Color("242e2b"))
	_center_text("I".repeat(mini(rank, 3)) if rank <= 3 else "R%d" % rank, Vector2(rect.end.x - 20.5, ceiling + 23), 9, GOLD)
	var branch_name: String = str(stats.get("branch", ""))
	if not branch_name.is_empty():
		_center_text(branch_name.to_upper(), Vector2(center.x, ceiling + 38), 8, TEAL)
	if int(stats.hp) > 0:
		var max_hp: int = int(stats.hp)
		var current_hp: int = int(room.get("current_hp", max_hp))
		if _slot_actors.has(index):
			current_hp = _actors_health(index, "hp")
			max_hp = _actors_health(index, "max_hp")
		_bar(Rect2(center.x - 21, ground - 3, 42, 3), float(current_hp) / maxf(1, max_hp), CORAL, 0.4 if cleared else 1.0)
	if cleared:
		_draw_cleared_mark(Vector2(rect.position.x + 18, ground - 12), Color("656966"))
	elif active:
		_draw_combat_sparks(Vector2(center.x - 7 * _floor_direction(index / 5), ground - 36))


func _draw_compact_chamber(rect: Rect2, index: int) -> void:
	# A narrow room separates its label, defender and party into three rows.
	# Full statistics and branch names remain available in the room inspector.
	var room: Dictionary = game.rooms[index]
	var active: bool = str(game.phase) == "raid" and int(game.current_slot) == index and index != _camp_exit_slot
	var chosen: bool = selected_slot == index
	var hovered: bool = _hovered_slot == index and str(game.phase) == "prepare"
	var cleared: bool = str(room.get("status", "")) == "cleared"
	var center_x: float = rect.get_center().x
	var top: float = rect.position.y
	var cavity: Rect2 = rect.grow(-3)
	draw_rect(cavity, Color("151c1d") if index % 2 == 0 else Color("182021"))
	_draw_masonry(cavity)
	if active:
		draw_rect(cavity, Color(0.63, 0.38, 0.14, 0.17 + 0.04 * sin(_clock * 3)))
	elif chosen or hovered:
		draw_rect(cavity, Color(0.31, 0.61, 0.52, 0.20 if chosen else 0.08))
	_draw_arch(rect, GOLD if active else (TEAL if chosen else Color("515550")))
	if chosen:
		draw_rect(rect.grow(-3), TEAL, false, 2.0)
	_text(str(index % 5 + 1), Vector2(rect.position.x + 7, top + 16), 9, MUTED)
	if index == _camp_exit_slot:
		if not room.is_empty():
			_draw_rubble(Vector2(center_x, top + 81), 0.5)
		return
	if room.is_empty():
		if _reserved_snapshot.has(index):
			_draw_reserved_growth(rect, index)
			return
		var preview_size: float = minf(30.0, rect.size.x - 14.0)
		if not selected_room.is_empty() and str(game.phase) == "prepare":
			_icon(selected_room, Rect2(Vector2(center_x - preview_size / 2, top + 43), Vector2.ONE * preview_size), Color(0.66, 0.83, 0.74, 0.4 if hovered else 0.22))
		else:
			draw_line(Vector2(center_x - 6, top + 60), Vector2(center_x + 6, top + 60), MUTED, 1.5)
			draw_line(Vector2(center_x, top + 54), Vector2(center_x, top + 66), MUTED, 1.5)
		_center_text_fitted("СВОБОДНО", Vector2(center_x, top + 32), 9, MUTED, rect.size.x - 8)
		_draw_reserved_growth(rect, index)
		return
	var stats: Dictionary = _room_snapshot[index] if index < _room_snapshot.size() else {}
	if stats.is_empty():
		return
	var rank: int = int(room.get("rank", 1))
	var rank_text: String = str(rank)
	var rank_width: float = maxf(16.0, _font.get_string_size(rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 6)
	draw_rect(Rect2(rect.end.x - rank_width - 5, top + 4, rank_width, 16), Color("242e2b"))
	_center_text(rank_text, Vector2(rect.end.x - rank_width / 2 - 5, top + 16), 10, GOLD)
	_center_text_fitted(str(stats.short_name), Vector2(center_x, top + 33), 10, Color("929c91") if cleared else CREAM, rect.size.x - 8)
	var figure_size: float = clampf(rect.size.x - 16.0, 28.0, 38.0)
	var idle: float = sin(_clock * 2.1 + index * 1.7) * 1.0 if not cleared else 0.0
	var figure: Rect2 = Rect2(center_x - figure_size / 2, top + 44 + idle, figure_size, figure_size)
	if str(stats.get("evolution_path", "")).is_empty() and not _slot_actors.has(index):
		_icon(str(stats.id), figure, Color(0.54, 0.56, 0.54, 0.40) if cleared else Color.WHITE)
	else:
		_draw_evolution_props(Rect2(rect.position + Vector2(0, 26), Vector2(rect.size.x, 65)), index, stats, cleared)
		_draw_evolution_actors(rect, index, stats, cleared)
	if active:
		_draw_defender_wards(figure.get_center(), figure_size / 70.0)
		_draw_combat_sparks(figure.get_center())
	if int(stats.hp) > 0:
		var max_hp: int = int(stats.hp)
		var current_hp: int = int(room.get("current_hp", max_hp))
		if _slot_actors.has(index):
			current_hp = _actors_health(index, "hp")
			max_hp = _actors_health(index, "max_hp")
		var bar_width: float = minf(34.0, rect.size.x - 14.0)
		_bar(Rect2(center_x - bar_width / 2, top + 84, bar_width, 4), float(current_hp) / maxf(1, max_hp), CORAL, 0.4 if cleared else 1.0)
	if cleared:
		_draw_cleared_mark(Vector2(center_x, top + 102), MUTED)


func _camp_fire_position(slot: int) -> Vector2:
	var rect: Rect2 = _slot_rect(slot)
	return Vector2(rect.get_center().x, rect.position.y + 62)


func _draw_camp() -> void:
	if not bool(_camp_snapshot.get("active", false)):
		return
	var slot: int = int(_camp_snapshot.get("slot", -1))
	if slot < 0 or slot >= game.rooms.size():
		return
	var rect: Rect2 = _slot_rect(slot)
	var center_x: float = rect.get_center().x
	var label_width: float = rect.size.x - 6
	draw_rect(Rect2(rect.position + Vector2(3, 3), Vector2(rect.size.x - 6, 78)), Color(0.09, 0.10, 0.08, 0.93))
	draw_rect(rect.grow(-3), Color(GOLD, 0.6), false, 1.5)
	_center_text_fitted("ПРИВАЛ", Vector2(center_x, rect.position.y + 18), 9 if compact else 11, GOLD, label_width)
	_center_text_fitted("%.1f с" % float(_camp_snapshot.get("remaining_seconds", 0.0)), Vector2(center_x, rect.position.y + 35), 10 if compact else 12, CREAM, label_width)
	var fire: Vector2 = _camp_fire_position(slot)
	draw_ellipse_shadow(fire + Vector2(0, 4), 13)
	draw_line(fire + Vector2(-10, 3), fire + Vector2(10, -2), Color("725238"), 4, true)
	draw_line(fire + Vector2(-10, -2), fire + Vector2(10, 3), Color("a97945"), 3, true)
	_draw_torch(fire + Vector2(0, -5), float(slot), 1.15)
	_actor_positions["camp"] = fire
	# Both values are model snapshots. Visual time never completes a healing pulse.
	var bar_width: float = minf(54.0, rect.size.x - 12)
	_bar(Rect2(center_x - bar_width / 2, rect.position.y + 73, bar_width, 4), float(_camp_snapshot.get("pulse_progress", 0.0)), GOLD)


func _draw_direction_arrow(origin: Vector2, tip: Vector2, color: Color) -> void:
	# Draw navigation symbols directly so every export uses the same clear shape.
	var direction: Vector2 = (tip - origin).normalized()
	var side: Vector2 = Vector2(-direction.y, direction.x)
	draw_line(origin, tip, color, 1.5, true)
	draw_polyline(PackedVector2Array([tip - direction * 5 + side * 4, tip, tip - direction * 5 - side * 4]), color, 1.5, true)


func _actors_health(slot: int, key: String) -> int:
	var total: int = 0
	for actor_data in _slot_actors.get(slot, []):
		if not bool(actor_data.get("untargetable", false)):
			total += int(actor_data.get(key, 0))
	return total


func _draw_reserved_growth(rect: Rect2, index: int) -> void:
	if not _reserved_snapshot.has(index):
		return
	var owner: int = int(_reserved_snapshot[index])
	if owner < 0 or owner >= game.rooms.size() or game.rooms[owner].is_empty():
		return
	if str(game.rooms[owner].get("status", "")) == "cleared" or _defeated_centers.has(owner):
		return
	var anchor: Vector2 = rect.get_center() + Vector2(0, 20)
	_center_text("ПАСТЬ", Vector2(rect.get_center().x, rect.end.y - 8), 8, Color("b98c94"))
	draw_line(Vector2(_slot_rect(owner).get_center().x, anchor.y), anchor, Color(0.65, 0.28, 0.35, 0.6), 5, true)
	var mouths: Array = _slot_actors.get(index, [])
	if mouths.is_empty():
		# Before combat the reserved footprint previews the coming extension.
		EvolutionVisuals.actor(self, anchor, 0.55 if compact else 0.85, "mimic_living_chamber", "appendage", {}, _clock)
		return
	for mouth in mouths:
		if str(mouth.get("phase_id", "")) != "appendage":
			continue
		_actor_positions[str(mouth.actor_id)] = anchor + Vector2(0, -14)
		EvolutionVisuals.actor(self, anchor, 0.55 if compact else 0.85, "mimic_living_chamber", "appendage", mouth.get("effects", {}), _clock)
	# Appendages share the heart: no independent HP or target marker here.


func _draw_evolution_props(rect: Rect2, index: int, stats: Dictionary, cleared: bool) -> void:
	var state: Dictionary = _room_visual_state.get(index, {})
	var inset: Vector2 = Vector2(3, 5) if compact else Vector2(7, 22)
	var canvas_rect := Rect2(rect.position + inset, rect.size - inset * 2)
	EvolutionVisuals.chamber(self, canvas_rect, str(stats.get("evolution_path", "")), int(stats.get("evolution_stage", 2)), _clock, cleared, state)
	if int(state.get("effects", {}).get("fire_ticks", 0)) > 0:
		var ground: float = rect.end.y - 19
		for i in range(5):
			var at := Vector2(rect.position.x + rect.size.x * (i + 1) / 6.0, ground)
			_draw_torch(at, i, 0.6)


func _draw_evolution_actors(rect: Rect2, index: int, stats: Dictionary, cleared: bool) -> void:
	if str(stats.get("kind", "")) != "monster":
		return
	var path: String = str(stats.get("evolution_path", ""))
	if path == "wraith_throne_guardian":
		return
	var actors: Array = _slot_actors.get(index, [])
	var live: bool = not actors.is_empty()
	if cleared and not live:
		_draw_rubble(Vector2(rect.get_center().x, rect.position.y + (76 if compact else 98)), 0.75)
		return
	if not live:
		actors = [{"phase_id": "base", "path_id": path, "effects": {}, "hp": stats.get("hp", 0), "max_hp": stats.get("hp", 0)}]
	var count: int = actors.size()
	for i in range(count):
		var actor_data: Dictionary = actors[i]
		var offset: float = minf(22, rect.size.x * 0.15) * _floor_direction(index / 5) if live and not compact else 0.0
		var at := Vector2(rect.get_center().x + offset + (i - (count - 1) * 0.5) * minf(27, rect.size.x / (count + 1)), rect.position.y + (76 if compact else 98))
		var scale_factor: float = (0.48 if compact else 0.78) * (0.8 if count > 1 else 1.0)
		var phase: String = str(actor_data.get("phase_id", "base"))
		var effects: Dictionary = actor_data.get("effects", {})
		var tint: Color = Color(0.54, 0.56, 0.54, 0.40) if cleared else Color.WHITE
		if "spirit" in actor_data.get("tags", []) or bool(effects.get("spectral", false)):
			tint = Color(0.72, 0.65, 0.93, 0.6 if not cleared else 0.25)
		if live:
			_actor_positions[str(actor_data.get("actor_id", ""))] = at + Vector2(0, -20 * scale_factor)
			if count > 1:
				draw_circle(at + Vector2(0, -14 * scale_factor), 17 * scale_factor, Color("111a1e"))
				draw_arc(at + Vector2(0, -14 * scale_factor), 17 * scale_factor, 0, TAU, 20, Color(TEAL, 0.5), 1, true)
		var rendered: bool = EvolutionVisuals.actor(self, at, scale_factor, str(actor_data.get("path_id", path)), phase, effects, _clock)
		if not rendered:
			var icon_id: String = str(actor_data.get("servant_class", stats.id)) if phase == "servant" else str(stats.id)
			var icon_size: float = 46 * scale_factor
			_icon(icon_id, Rect2(at + Vector2(-icon_size / 2, -icon_size), Vector2.ONE * icon_size), tint)
		if not live:
			continue
		_draw_defender_wards(at + Vector2(0, -24 * scale_factor), scale_factor * 0.7, actor_data)
		if count > 1 and not bool(actor_data.get("untargetable", false)):
			_bar(Rect2(at + Vector2(-10, 3), Vector2(20, 3)), float(actor_data.hp) / maxf(1, float(actor_data.max_hp)), CORAL)
		var preparation: Dictionary = effects.get("preparing", {})
		if not preparation.is_empty():
			var ratio: float = 1.0 - float(preparation.get("remaining", 0)) / maxf(1, float(preparation.get("total", 1)))
			_bar(Rect2(at + Vector2(-15, -42 * scale_factor), Vector2(30, 3)), ratio, GOLD)
		elif int(effects.get("cocoon_ready_in", 0)) > 0:
			var total: float = float(effects.get("cocoon_cooldown_total", effects.cocoon_ready_in))
			_bar(Rect2(at + Vector2(-15, -42 * scale_factor), Vector2(30, 3)), 1.0 - float(effects.cocoon_ready_in) / maxf(1, total), Color("c9d3c2"))


func _draw_event_feedback() -> void:
	# A bounded event queue consumes only new seq IDs. It never infers damage.
	for item in _events:
		var event: Dictionary = item.event
		var progress: float = clampf(float(item.age) / 0.7, 0, 1)
		var alpha: float = 1.0 - progress
		var kind: String = str(event.get("kind", ""))
		if _camp_exit_slot >= 0 and not kind.begins_with("camp_"):
			continue
		var target_id: String = str(event.get("target", ""))
		var actor_id: String = str(event.get("actor", ""))
		var slot: int = int(event.get("source_slot", game.current_slot))
		var fallback := _position_for_slot(slot) + Vector2(0, -25)
		var target: Vector2 = _hero_positions.get(target_id, _actor_positions.get(target_id, fallback))
		var source: Vector2 = _actor_positions.get(actor_id, _hero_positions.get(actor_id, fallback))
		var tint := Color(TEAL if "heal" in kind else GOLD if "shield" in kind else CORAL, alpha)
		var amount: int = int(event.get("amount", 0))
		var meta: Dictionary = event.get("meta", {})
		if kind.begins_with("camp_"):
			var fire: Vector2 = _camp_fire_position(slot)
			if kind == "camp_heal" and amount > 0:
				# Only actual, already applied HP is shown; forecasts are never pulses.
				var label: String = "+%d" % amount
				var label_size: int = 10 if compact else 12
				var label_width: float = 28.0 if compact else 32.0
				while label_size > 6 and _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x > label_width:
					label_size -= 1
				_center_text(label, target + Vector2(0, -26 - progress * 16), label_size, Color(TEAL, alpha))
				draw_arc(target + Vector2(0, -8), 10 + progress * 3, 0, TAU, 16, Color(TEAL, alpha * 0.65), 1.5, true)
			elif kind == "camp_interrupt":
				draw_arc(fire, 11 + progress * 19, 0, TAU, 20, Color(CORAL, alpha), 2, true)
				var caption_x: float = clampf(fire.x, 52, size.x - 52)
				_center_text("ПРИВАЛ СОРВАН", Vector2(caption_x, fire.y - 29), 9 if compact else 11, Color(CORAL, alpha))
			elif kind == "camp_start" and bool(_camp_snapshot.get("active", false)):
				draw_arc(fire, 12 + progress * 14, 0, TAU, 20, Color(GOLD, alpha * 0.5), 1.5, true)
			elif kind == "camp_end" and str(meta.get("reason", "")) != "interrupted":
				_center_text("В ПУТЬ", fire + Vector2(0, -24 - progress * 8), 9 if compact else 11, Color(GOLD, alpha))
			continue
		if amount != 0 and kind in ["attack", "heal", "steal_heal", "poison", "cleave", "chain", "bolt"]:
			_center_text(("+" if "heal" in kind else "−") + str(absi(amount)), target + Vector2(0, -24 - progress * 19), 10 if compact else 12, tint)
		var special: String = str(meta.get("prepared_kind", meta.get("ability", "")))
		if kind == "attack" and _draw_ability_feedback(special, source, target, progress, alpha):
			pass
		elif kind == "attack" and str(meta.get("damage_type", "")) == "magic":
			var spark: Vector2 = source.lerp(target, minf(1, progress * 2.5)) + Vector2(0, -12)
			draw_line(source + Vector2(0, -12), spark, Color("ae9bdd", alpha * 0.6), 2, true)
			draw_circle(spark, (5 if bool(meta.get("charged", false)) else 2.5), Color("c5c1f1", alpha))
		elif "bolt" in kind or "bomb" in kind or "spell" in kind or "stone" in kind or "shot" in kind or "transfer" in kind:
			var p: Vector2 = source.lerp(target, minf(1, progress * 2))
			draw_line(source.lerp(p, 0.7), p, tint, 2, true)
			draw_circle(p, 2.5 if compact else 4, tint)
		elif kind in ["rotate", "spawn", "revive"] or "transform" in kind or "hatch" in kind or "cocoon" in kind or "hypno" in kind:
			draw_arc(target, 12 + progress * 12, 0, TAU, 18, tint, 1.6, true)
		elif kind == "plague_focus":
			var cloud: Vector2 = source.lerp(target, minf(1.0, progress * 2))
			draw_circle(cloud, 8 + progress * 12, Color(0.53, 0.73, 0.34, alpha * 0.4))
			_center_text("−%d" % amount, target + Vector2(0, -30 - progress * 15), 11, Color(0.64, 0.82, 0.42, alpha))
		elif "scream" in kind or "cleanse" in kind or "shock" in kind:
			draw_arc(source, 10 + progress * 60, -PI * 0.7, PI * 0.7, 24, tint, 2, true)
		elif kind in ["parry", "decoy", "armor_break", "disarm", "swap_weapon"]:
			draw_polyline(PackedVector2Array([target + Vector2(-9, -24), target + Vector2(0, -14), target + Vector2(9, -24)]), Color(GOLD, alpha), 2, true)
		if int(meta.get("shield_absorbed", 0)) > 0:
			draw_arc(target + Vector2(0, -15), 19, PI * 0.6, PI * 1.4, 14, Color(TEAL, alpha), 3, true)


func _draw_ability_feedback(ability: String, source: Vector2, target: Vector2, progress: float, alpha: float) -> bool:
	# Event metadata describes an attack that actually happened. These traces
	# do not schedule a second strike or add their own damage/timers to the model.
	var metal := Color("a8bdc3", alpha)
	var red := Color(CORAL, alpha)
	var reach: float = 0.65 if compact else 1.0
	match ability:
		"boulder":
			var at: Vector2 = source.lerp(target, minf(1, progress * 2)) + Vector2(0, -sin(minf(1, progress * 2) * PI) * 35 * reach - 10)
			var radius: float = 7 * reach
			draw_colored_polygon(PackedVector2Array([at + Vector2(-radius, -radius * 0.5), at + Vector2(radius * 0.2, -radius), at + Vector2(radius, 0), at + Vector2(radius * 0.2, radius), at + Vector2(-radius, radius * 0.4)]), metal)
			draw_line(at - Vector2(radius * 0.6, 0), at + Vector2(radius * 0.2, -radius * 0.4), Color(INK, alpha), 1.3)
		"guillotine":
			var at := target + Vector2(0, -45 + minf(1, progress * 2) * 35) * reach
			draw_line(at + Vector2(-13, -20) * reach, at + Vector2(-13, 16) * reach, Color(GOLD, alpha * 0.6), 1.5)
			draw_line(at + Vector2(13, -20) * reach, at + Vector2(13, 16) * reach, Color(GOLD, alpha * 0.6), 1.5)
			draw_colored_polygon(PackedVector2Array([at + Vector2(-11, -7) * reach, at + Vector2(11, -7) * reach, at + Vector2(11, 0) * reach, at + Vector2(-11, 9) * reach]), metal)
		"earthshaker":
			var width: float = (15 + progress * 80) * reach
			var floor_at := source + Vector2(0, 16)
			for side in [-1, 1]:
				draw_polyline(PackedVector2Array([floor_at, floor_at + Vector2(side * width * 0.35, -6), floor_at + Vector2(side * width * 0.65, 3), floor_at + Vector2(side * width, -7)]), Color(GOLD, alpha), 2, true)
		"cleaver":
			draw_arc(target + Vector2(0, -12), (13 + progress * 25) * reach, PI * 0.85, PI * 1.9, 18, metal, 4 * reach, true)
			draw_arc(target + Vector2(0, -12), (10 + progress * 24) * reach, PI * 0.85, PI * 1.9, 18, red, 2, true)
		"banshee":
			for i in range(3):
				draw_arc(source + Vector2(0, -12), (10 + i * 9 + progress * 55) * reach, 0, TAU, 24, Color("ae9bdd", alpha / (1 + i * 0.4)), 2, true)
		"hellfire":
			var tip: Vector2 = source.lerp(target + Vector2(0, 12), minf(1, progress * 3))
			draw_colored_polygon(PackedVector2Array([source, tip + Vector2(0, -10) * reach, tip + Vector2(0, 7) * reach]), Color(CORAL, alpha * 0.55))
			draw_line(source, tip, Color(GOLD, alpha), 3 * reach, true)
		_:
			return false
	return true


func _draw_cleared_mark(at: Vector2, color: Color) -> void:
	draw_line(at + Vector2(-4, -4), at + Vector2(4, 4), color, 1.5, true)
	draw_line(at + Vector2(-4, 4), at + Vector2(4, -4), color, 1.5, true)


func _draw_masonry(rect: Rect2) -> void:
	for row in range(4):
		var line_y: float = rect.position.y + row * 25 + 10
		draw_line(Vector2(rect.position.x + 2, line_y), Vector2(rect.end.x - 2, line_y), MORTAR, 1)
		var middle: float = rect.get_center().x + (12 if row % 2 == 0 else -12)
		draw_line(Vector2(middle, line_y), Vector2(middle, line_y + 25), MORTAR, 1)


func _draw_arch(rect: Rect2, accent: Color) -> void:
	var left: float = rect.position.x + 3
	var right: float = rect.end.x - 3
	var top: float = rect.position.y + 2
	var bottom: float = rect.end.y - 14
	var arch_points: PackedVector2Array = PackedVector2Array([
		Vector2(left, bottom), Vector2(left, top + 23), Vector2(left + 17, top + 5),
		Vector2(rect.get_center().x, top), Vector2(right - 17, top + 5),
		Vector2(right, top + 23), Vector2(right, bottom),
	])
	draw_polyline(arch_points, Color("373d3c"), 8, true)
	draw_polyline(arch_points, accent.darkened(0.18), 1, true)
	for side in [left, right]:
		for y_offset in [38, 63, 88]:
			draw_line(Vector2(side - 3, top + y_offset), Vector2(side + 3, top + y_offset), INK, 2)
	draw_line(Vector2(rect.get_center().x - 4, top - 2), Vector2(rect.get_center().x - 3, top + 8), Color("646452"), 3)


func _draw_platform(rect: Rect2, floor_index: int) -> void:
	draw_rect(rect, Color("3d413e"))
	draw_line(rect.position, Vector2(rect.end.x, rect.position.y), Color("73705a"), 2)
	draw_line(Vector2(rect.position.x, rect.end.y), rect.end, INK, 4)
	var tile_count: int = ceili(rect.size.x / 27.0)
	for tile in range(tile_count):
		var x: float = rect.position.x + tile * 27
		draw_line(Vector2(x, rect.position.y + 3), Vector2(x - 2, rect.end.y), Color("232b2c"), 1)
		if (tile + floor_index) % 4 == 1:
			draw_line(Vector2(x + 5, rect.position.y + 4), Vector2(x + 16, rect.position.y + 5), Color("51584d"), 1)


func _draw_stairway(floor_index: int) -> void:
	var x: float = _floor_exit_x(floor_index)
	var top: float = _floor_walk_y(floor_index)
	var direction: float = _floor_direction(floor_index)
	var half_width: float = 6.0 if compact else 16.0
	draw_rect(Rect2(x - half_width, top - 10, half_width * 2, FLOOR_HEIGHT + 20), Color("12191a"))
	for step in range(17):
		var step_y: float = top + step * FLOOR_HEIGHT / 16.0
		var tread: float = half_width - (1 if compact else 5)
		draw_line(Vector2(x - tread, step_y - 2 * direction), Vector2(x + tread, step_y + 2 * direction), Color("5e635b"), 2 if compact else 3)
	var rail: float = half_width - (0 if compact else 3)
	draw_line(Vector2(x - rail, top - 5), Vector2(x - rail, top + FLOOR_HEIGHT + 5), Color("343e3d"), 1 if compact else 2)
	draw_line(Vector2(x + rail, top - 5), Vector2(x + rail, top + FLOOR_HEIGHT + 5), Color("343e3d"), 1 if compact else 2)
	if not compact:
		_draw_direction_arrow(Vector2(x, top - 30), Vector2(x, top - 17), GOLD.darkened(0.25))


func _draw_empty_room(rect: Rect2, hovered: bool) -> void:
	var center: Vector2 = rect.get_center() + Vector2(0, 9)
	if not selected_room.is_empty() and str(game.phase) == "prepare":
		_icon(selected_room, Rect2(center - Vector2(22, 28), Vector2(44, 44)), Color(0.66, 0.83, 0.74, 0.28 if hovered else 0.12))
	else:
		draw_line(center + Vector2(-7, -5), center + Vector2(7, -5), Color("46534b"), 1)
		draw_line(center + Vector2(0, -12), center + Vector2(0, 2), Color("46534b"), 1)
		_draw_rubble(Vector2(rect.position.x + 17, rect.end.y - 20), 0.55)
	_center_text("ПОСТРОИТЬ" if hovered else "СВОБОДНО", Vector2(center.x, rect.end.y - 8), 8, TEAL if hovered else Color("687a70"))


func _draw_room_props(id: String, rect: Rect2, cleared: bool) -> void:
	var at: Vector2 = Vector2(rect.position.x + 15, rect.end.y - 19)
	var prop_color: Color = Color("39423b") if cleared else Color("68765e")
	match id:
		"goblin":
			draw_rect(Rect2(at.x - 4, at.y - 15, 13, 14), Color("4e4634"))
			draw_line(at + Vector2(-5, -12), at + Vector2(10, -12), Color("84764e"), 2)
			draw_line(at + Vector2(-5, -4), at + Vector2(10, -4), Color("84764e"), 2)
		"executioner":
			draw_line(at + Vector2(1, -2), at + Vector2(1, -40), Color("584434"), 4)
			draw_line(at + Vector2(-3, -39), at + Vector2(19, -39), Color("584434"), 4)
			draw_line(at + Vector2(17, -39), at + Vector2(17, -26), Color("918365"), 1)
			draw_arc(at + Vector2(17, -22), 4, 0, TAU, 12, Color("918365"), 1)
		"poison":
			draw_rect(Rect2(at.x - 2, at.y - 23, 9, 21), Color("365349"))
			draw_rect(Rect2(at.x - 1, at.y - 20, 7, 4), TEAL.darkened(0.45))
			draw_circle(at + Vector2(11, -4), 4, Color("3b5543"))
		"spider":
			_draw_web(Vector2(rect.position.x + 7, rect.position.y + 8), 31)
			_draw_web(Vector2(rect.end.x - 7, rect.position.y + 8), -24)
		"spikes":
			for mark in range(3):
				draw_circle(at + Vector2(mark * 12, -2), 2, Color("733f39") if not cleared else Color("44413b"))
		"mimic":
			for coin in range(5):
				draw_circle(at + Vector2(coin * 4, -2 - (coin % 2) * 3), 2, GOLD.darkened(0.3 if not cleared else 0.7))
		"shackles":
			for chain in range(4):
				draw_arc(at + Vector2(2, -37 + chain * 7), 4, 0, TAU, 10, Color("86918f"), 1.5)
		"silence":
			draw_line(at + Vector2(-3, -38), at + Vector2(15, -38), Color("7b6548"), 3)
			draw_line(at + Vector2(6, -38), at + Vector2(6, -22), GOLD.darkened(0.3), 2)
		"rust":
			for mark in range(3):
				var rune: Vector2 = at + Vector2(mark * 8, -9)
				draw_line(rune, rune + Vector2(4, -10), CORAL.darkened(0.25), 2)
		"guardian":
			draw_rect(Rect2(at + Vector2(-5, -22), Vector2(19, 22)), Color("464c55"))
			draw_line(at + Vector2(4, -20), at + Vector2(4, -6), MUTED, 2)
		"ogre":
			draw_circle(at + Vector2(3, -4), 8, Color("746552") if not cleared else Color("49473f"))
			draw_line(at + Vector2(-3, -8), at + Vector2(7, -2), INK, 2)
		"war_hound":
			for link in range(4):
				draw_arc(at + Vector2(link * 5, -5), 3, 0, TAU, 8, Color("8d8072"), 1.5)
		"wraith":
			var mist: Color = Color(0.55, 0.51, 0.69, 0.18 if cleared else 0.4)
			for mote in range(3):
				draw_circle(at + Vector2(mote * 9, -10 - sin(_clock * 1.5 + mote) * 5), 3, mist)
		"vampire":
			draw_rect(Rect2(at + Vector2(-5, -31), Vector2(13, 30)), Color("4b3545"))
			draw_line(at + Vector2(1, -27), at + Vector2(1, -11), Color("ae8ed6").darkened(0.3), 2)
		"ballista":
			for bolt in range(3):
				draw_line(at + Vector2(bolt * 5, -2), at + Vector2(bolt * 5 + 3, -27), Color("987d59"), 2)
				draw_line(at + Vector2(bolt * 5 + 1, -24), at + Vector2(bolt * 5 + 3, -29), Color("6faecb"), 2)
		"blade_floor":
			for groove in range(3):
				draw_line(at + Vector2(groove * 10 - 3, -2), at + Vector2(groove * 10 + 4, -7), Color("6faecb").darkened(0.4), 2)
	_draw_rubble(Vector2(rect.end.x - 17, rect.end.y - 18), 0.6)
	if id not in ["spider", "executioner"]:
		draw_line(at + Vector2(0, -28), at + Vector2(-4, -37), prop_color.darkened(0.45), 1)


func _draw_creature_body(id: String, at: Vector2, figure_size: float, tint: Color) -> void:
	if id in ["mimic", "spider", "war_hound", "wraith"]:
		return
	var body: Color = Color("425947") if id == "goblin" else (Color("505768") if id == "guardian" else Color("523c40"))
	body.a = tint.a
	draw_circle(at + Vector2(0, -3), figure_size * 0.21, body)
	draw_line(at + Vector2(-5, -1), at + Vector2(-8, 7), body.lightened(0.1), 5)
	draw_line(at + Vector2(5, -1), at + Vector2(8, 7), body.lightened(0.1), 5)
	draw_line(at + Vector2(-9, 7), at + Vector2(-2, 7), INK, 3)
	draw_line(at + Vector2(3, 7), at + Vector2(10, 7), INK, 3)


func _draw_web(origin: Vector2, span: float) -> void:
	var direction: float = signf(span)
	var length: float = absf(span)
	var web_color: Color = Color(0.64, 0.64, 0.54, 0.22)
	for angle in [0.0, 0.5, 1.0, 1.57]:
		draw_line(origin, origin + Vector2(cos(angle) * length * direction, sin(angle) * length), web_color, 1)
	for radius in [length * 0.4, length * 0.7, length]:
		var points: PackedVector2Array = PackedVector2Array()
		for segment in range(4):
			var angle: float = segment * PI / 6
			points.append(origin + Vector2(cos(angle) * radius * direction, sin(angle) * radius))
		draw_polyline(points, web_color, 1, true)


func _draw_rubble(at: Vector2, opacity: float) -> void:
	var color: Color = Color(0.45, 0.46, 0.39, opacity)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-5, 0), at + Vector2(-3, -4), at + Vector2(2, -3), at + Vector2(4, 0)]), color)
	draw_line(at + Vector2(7, 0), at + Vector2(10, -2), color, 2)


func _draw_torch(at: Vector2, seed_offset: float, scale_factor: float = 1.0) -> void:
	var flicker: float = 1.0 + 0.12 * sin(_clock * 9 + seed_offset * 2) + 0.07 * sin(_clock * 17 + seed_offset)
	for radius in [24.0, 15.0, 9.0]:
		draw_circle(at + Vector2(0, -4), radius * scale_factor * flicker, Color(0.96, 0.53, 0.18, 0.025 + 0.03 * (1.0 - radius / 25)))
	draw_line(at + Vector2(0, 1) * scale_factor, at + Vector2(0, 12) * scale_factor, Color("503e2d"), 4 * scale_factor)
	draw_line(at + Vector2(-4, 7) * scale_factor, at + Vector2(4, 7) * scale_factor, Color("858074"), 2 * scale_factor)
	draw_colored_polygon(PackedVector2Array([at + Vector2(-4, 0) * scale_factor, at + Vector2(-2, -8 * flicker) * scale_factor, at + Vector2(1, -12 * flicker) * scale_factor, at + Vector2(4, -2) * scale_factor, at + Vector2(1, 3) * scale_factor]), Color("de8a47"))
	draw_colored_polygon(PackedVector2Array([at + Vector2(-2, 0) * scale_factor, at + Vector2(1, -7 * flicker) * scale_factor, at + Vector2(2, 1) * scale_factor]), Color("efd38a"))


func _draw_poison_motes(at: Vector2, seed_offset: float, cleared: bool) -> void:
	if cleared:
		return
	for mote in range(3):
		var cycle: float = fmod(_clock * 0.45 + mote * 0.33 + seed_offset, 1.0)
		var point: Vector2 = at + Vector2(sin(cycle * 5 + mote) * 13, -34 - cycle * 25)
		draw_circle(point, 2.0 + cycle * 2, Color(0.40, 0.76, 0.54, (1.0 - cycle) * 0.26))


func _draw_combat_sparks(at: Vector2) -> void:
	if _hit_flash <= 0.0:
		return
	for spark in range(3):
		var angle: float = spark * 2.0 + _clock
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		draw_line(at + direction * (5 + (1 - _hit_flash) * 7), at + direction * (11 + (1 - _hit_flash) * 12), Color(0.94, 0.70, 0.38, _hit_flash), 2, true)


func _draw_throne() -> void:
	var lord_visual: Dictionary = _lord_visual()
	var lord_icon: String = str(lord_visual.get("icon", "res://assets/icons/lord.svg"))
	var banner_color: Color = Color(str(lord_visual.get("color", "#b86b60"))).darkened(0.45)
	var top: float = int(game.floor_count) * FLOOR_HEIGHT
	_text("ТРОННЫЙ ЗАЛ", Vector2(8 if compact else 17, top + 21), 12, GOLD)
	if not compact:
		_text("ПОСЛЕДНЯЯ ЛИНИЯ ЗАЩИТЫ", Vector2(size.x - 212, top + 21), 9, MUTED)
	var inset: float = 16.0 if compact else 49.0
	var hall: Rect2 = Rect2(inset, top + 30, size.x - inset * 2, 117)
	draw_rect(hall, Color("1b1b20"))
	_draw_masonry(hall)
	var active: bool = str(game.phase) == "raid" and int(game.current_slot) >= game.rooms.size()
	_draw_arch(hall, GOLD if active else Color("6f6250"))
	var center: Vector2 = Vector2(size.x * 0.5 + (0 if compact else 18), top + 115)
	_draw_throne_furniture(center, 0.82 if compact else 1.0)
	var lord_tint: Color = Color.WHITE if int(game.lord.hp) > 0 else Color(0.42, 0.42, 0.42, 0.75)
	_icon(lord_icon, Rect2(center + (Vector2(-25, -54) if compact else Vector2(-31, -65)), Vector2.ONE * (50 if compact else 62)), lord_tint)
	_actor_positions["lord"] = center + Vector2(0, -30)
	_draw_throne_guards(center)
	if active:
		_draw_defender_wards(center + Vector2(0, -34), 1.12)
	_draw_torch(Vector2(hall.position.x + (17 if compact else 41), top + 72), 22, 0.8 if compact else 1.25)
	_draw_torch(Vector2(hall.end.x - (17 if compact else 40), top + 72), 31, 0.8 if compact else 1.25)
	_draw_banner(Vector2(center.x - (74 if compact else 95), top + 36), banner_color, 16 if compact else 22, 54 if compact else 60)
	_draw_banner(Vector2(center.x + (58 if compact else 79), top + 36), banner_color, 16 if compact else 22, 54 if compact else 60)
	_bar(Rect2(center.x - 46, top + 127, 92, 5), float(game.lord.hp) / maxf(1, int(game.lord.max_hp)), CORAL)
	_center_text("ЛОРД · УР. %d" % int(game.lord.level), Vector2(center.x, top + 144), 10, CREAM)
	var platform_inset: float = 13.0 if compact else 40.0
	_draw_platform(Rect2(platform_inset, top + 150, size.x - platform_inset * 2, 15), int(game.floor_count))
	if active:
		_draw_combat_sparks(center + Vector2(-31 * _floor_direction(int(game.floor_count)), -30))


func _draw_throne_furniture(at: Vector2, scale_factor: float) -> void:
	var back: PackedVector2Array = PackedVector2Array([
		at + Vector2(-27, 6) * scale_factor, at + Vector2(-32, -62) * scale_factor,
		at + Vector2(-20, -54) * scale_factor, at + Vector2(-14, -78) * scale_factor,
		at + Vector2(0, -65) * scale_factor, at + Vector2(14, -78) * scale_factor,
		at + Vector2(20, -54) * scale_factor, at + Vector2(32, -62) * scale_factor,
		at + Vector2(27, 6) * scale_factor,
	])
	draw_colored_polygon(back, Color("665136"))
	draw_polyline(back, GOLD.darkened(0.18), 2 * scale_factor, true)
	draw_rect(Rect2(at + Vector2(-23, -47) * scale_factor, Vector2(46, 51) * scale_factor), Color("5d333d"))
	draw_rect(Rect2(at + Vector2(-37, -12) * scale_factor, Vector2(12, 26) * scale_factor), Color("857045"))
	draw_rect(Rect2(at + Vector2(25, -12) * scale_factor, Vector2(12, 26) * scale_factor), Color("857045"))
	draw_rect(Rect2(at + Vector2(-42, 14) * scale_factor, Vector2(84, 7) * scale_factor), Color("67624c"))


func _draw_throne_guards(center: Vector2) -> void:
	var guards: Array = []
	for actor_data in _slot_actors.get(game.rooms.size(), []):
		if str(actor_data.get("phase_id", "")) == "throne_guard":
			guards.append(actor_data)
	if guards.is_empty() and (str(game.phase) == "prepare" or (int(game.current_slot) < game.rooms.size() and str(game.phase) in ["raid", "result"])):
		if _throne_guard_slot >= 0:
			guards.append({})
	for i in range(guards.size()):
		var at := center + Vector2((-42 - i * 25) * _floor_direction(game.floor_count), 0)
		var guard: Dictionary = guards[i]
		EvolutionVisuals.actor(self, at, 0.7 if compact else 0.95, "wraith_throne_guardian", "throne_guard", {}, _clock)
		if not guard.is_empty():
			_actor_positions[str(guard.get("actor_id", ""))] = at + Vector2(0, -25)
			_bar(Rect2(at + Vector2(-14, -51), Vector2(28, 3)), float(guard.hp) / maxf(1, float(guard.max_hp)), Color("ae9bdd"))


func _draw_banner(at: Vector2, color: Color, width: float, height: float) -> void:
	draw_colored_polygon(PackedVector2Array([at, at + Vector2(width, 0), at + Vector2(width, height), at + Vector2(width / 2, height - 8), at + Vector2(0, height)]), color)
	draw_line(at + Vector2(-3, 1), at + Vector2(width + 3, 1), GOLD.darkened(0.35), 3)
	var emblem: Vector2 = at + Vector2(width / 2, height * 0.43)
	draw_colored_polygon(PackedVector2Array([emblem + Vector2(0, -8), emblem + Vector2(5, 0), emblem + Vector2(0, 8), emblem + Vector2(-5, 0)]), GOLD.darkened(0.13))


func _draw_party() -> void:
	if game.heroes.is_empty() or int(game.current_slot) < 0:
		return
	var living: Array[Dictionary] = []
	for hero in game.heroes:
		if int(hero.hp) > 0:
			living.append(hero)
	if living.is_empty():
		return
	var walking: bool = str(game.phase) != "camp" and (_party_position.distance_to(_party_goal) > 5 or not _waypoints.is_empty())
	if compact or game.heroes.size() > 3 or _camp_exit_slot == int(game.current_slot):
		_draw_compact_party(living, walking)
		return
	for index in range(living.size() - 1, -1, -1):
		var hero: Dictionary = living[index]
		var goal: Vector2 = _party_position + Vector2(-index * 19.5 * _party_direction, -index * 4)
		var hero_at: Vector2 = _animated_hero_position(hero, goal)
		var foot_swing: float = sin(_clock * (14 if walking else 2.6) + index) * (3 if walking else 0.5)
		var bob: float = absf(foot_swing) * 0.5
		var definition: Dictionary = _hero_definitions.get(str(hero.id), {})
		var body_color: Color = definition.color.darkened(0.48)
		draw_ellipse_shadow(hero_at + Vector2(0, 7), 10)
		draw_line(hero_at + Vector2(-3, 0), hero_at + Vector2(-5 + foot_swing, 8), body_color, 4)
		draw_line(hero_at + Vector2(3, 0), hero_at + Vector2(5 - foot_swing, 8), body_color, 4)
		draw_rect(Rect2(hero_at + Vector2(-6, -10 - bob), Vector2(12, 13)), body_color)
		_icon(str(hero.id), Rect2(hero_at + Vector2(-14, -32 - bob), Vector2(28, 28)))
		EvolutionVisuals.hero_equipment(self, hero_at + Vector2(0, -bob), 0.75, _hero_equipment.get(str(hero.get("instance_id", hero.id)), {}), _hero_effects.get(str(hero.get("instance_id", hero.id)), {}), _clock)
		_bar(Rect2(hero_at + Vector2(-11, -38 - bob), Vector2(22, 3)), float(hero.hp) / maxf(1, int(hero.max_hp)), TEAL)
		if int(hero.get("poison_ticks", 0)) > 0:
			draw_circle(hero_at + Vector2(11, -29), 3, Color("92b957"))
		if int(hero.get("silence_ticks", 0)) > 0 or int(hero.get("pending_silence", 0)) > 0:
			draw_line(hero_at + Vector2(-11, -26), hero_at + Vector2(11, -9), Color("b4a0d5"), 2)
		if int(hero.get("shackles_ticks", 0)) > 0 or int(hero.get("pending_shackles", 0)) > 0:
			draw_arc(hero_at + Vector2(0, 3), 7, 0, PI, 12, MUTED, 2)
		if int(hero.get("goblin_mark_slot", -1)) >= 0:
			var mark: Vector2 = hero_at + Vector2(0, -47)
			draw_colored_polygon(PackedVector2Array([mark + Vector2(0, -4), mark + Vector2(4, 0), mark + Vector2(0, 4), mark + Vector2(-4, 0)]), GOLD)
		if str(game.get("active_target_id")) == str(hero.get("instance_id", "")) and str(game.phase) == "raid":
			var marker: Vector2 = hero_at + Vector2(0, -45 - bob)
			draw_colored_polygon(PackedVector2Array([marker + Vector2(-3, -4), marker + Vector2(3, -4), marker]), CORAL)
	_draw_party_links(living)


func _draw_compact_party(living: Array[Dictionary], walking: bool) -> void:
	# Five separate icons fit in one row even at 280 px. Keeping the row below
	# defenders avoids hiding them with a second rank inside a 160 px floor.
	var icon_size: float = 18.0 if compact else 22.0
	var stride: float = icon_size + 12
	var group_width: float = (living.size() - 1) * stride + icon_size + 10
	var center_x: float = clampf(_party_position.x, group_width * 0.5 + 4, size.x - group_width * 0.5 - 4)
	for index in range(living.size()):
		var hero: Dictionary = living[index]
		var identity: String = str(hero.get("instance_id", hero.id))
		var resting: bool = str(game.phase) == "camp"
		var bob: float = 0.0 if resting else sin(_clock * (14 if walking else 2.6) + index) * (1.2 if walking else 0.3)
		var at := Vector2(center_x + (index - (living.size() - 1) * 0.5) * stride * -_party_direction, _party_position.y + 20 + bob)
		# Clamp the formation, not each hero. Per-hero clamping collapses ranks
		# on stairs, and per-hero interpolation crosses HP bars during reordering.
		_hero_positions[identity] = at
		var frame := Rect2(at + Vector2(-icon_size * 0.5 - 4, -icon_size - 3), Vector2(icon_size + 8, icon_size + 10))
		draw_rect(frame, Color(0.04, 0.07, 0.07, 0.9))
		draw_rect(frame, Color(GOLD if bool(game.get("wave_is_boss")) else MUTED, 0.4), false, 1)
		_icon(str(hero.id), Rect2(at + Vector2(-icon_size * 0.5, -icon_size), Vector2.ONE * icon_size))
		EvolutionVisuals.hero_equipment(self, at, icon_size / 35.0, _hero_equipment.get(identity, {}), _hero_effects.get(identity, {}), _clock)
		_bar(Rect2(at + Vector2(-icon_size * 0.5, 3), Vector2(icon_size, 3)), float(hero.hp) / maxf(1, int(hero.max_hp)), TEAL)
		if int(hero.get("poison_ticks", 0)) > 0:
			draw_circle(at + Vector2(icon_size * 0.5 - 1, -icon_size + 1), 2, Color("92b957"))
		if int(hero.get("silence_ticks", 0)) > 0 or int(hero.get("pending_silence", 0)) > 0:
			draw_line(at + Vector2(-icon_size * 0.4, -icon_size + 1), at + Vector2(icon_size * 0.4, -1), Color("b4a0d5"), 1.5)
		if str(game.get("active_target_id")) == identity and str(game.phase) == "raid" and _camp_exit_slot < 0:
			draw_rect(frame, CORAL, false, 1.5)
	_draw_party_links(living)


func _animated_hero_position(hero: Dictionary, goal: Vector2) -> Vector2:
	var id: String = str(hero.get("instance_id", hero.get("id", "")))
	var previous: Vector2 = _hero_positions.get(id, goal)
	var at: Vector2 = previous.lerp(goal, _frame_blend)
	_hero_positions[id] = at
	return at


func _draw_party_links(living: Array[Dictionary]) -> void:
	for hero in living:
		var id: String = str(hero.get("instance_id", ""))
		var at: Vector2 = _hero_positions.get(id, _party_position)
		var effects: Dictionary = hero.get("effects", {})
		if int(hero.get("run_poison_corrosion", 0)) > 0:
			draw_polyline(PackedVector2Array([at + Vector2(-4, -27), at + Vector2(1, -23), at + Vector2(-1, -19), at + Vector2(4, -15)]), Color("a3c46e"), 2, true)
		if bool(hero.get("run_heavy_breathing", false)):
			_center_text("↓", at + Vector2(12, -19), 12, Color("a3c46e"))
		if int(hero.get("poison_ticks", 0)) > 0:
			var maturity: int = mini(3, int(hero.get("run_poison_maturity", 0)))
			for i in range(maturity):
				draw_circle(at + Vector2(-5 + i * 4, 9), 1.2, Color("a3c46e"))
		for other in effects.get("chain_with", []):
			if str(other) < id or not _hero_positions.has(str(other)):
				continue
			var target: Vector2 = _hero_positions[str(other)]
			draw_line(at + Vector2(0, -9), target + Vector2(0, -9), GOLD, 2, true)
			for i in range(1, 5):
				draw_arc(at.lerp(target, i / 5.0) + Vector2(0, -9), 2, 0, TAU, 8, Color("a8bdc3"), 1)
		if int(effects.get("partition_ticks", 0)) > 0:
			draw_line(at + Vector2(9, -36), at + Vector2(9, 4), MUTED, 3)


func draw_ellipse_shadow(at: Vector2, radius: float) -> void:
	draw_set_transform(at, 0, Vector2(1, 0.32))
	draw_circle(Vector2.ZERO, radius, Color(0, 0, 0, 0.23))
	draw_set_transform(Vector2.ZERO)


func _draw_cinematic() -> void:
	var scale_factor: float = minf(1.0, size.x / 500.0) if compact else 1.0
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE * scale_factor)
	_draw_cinematic_scene(size / scale_factor)
	draw_set_transform(Vector2.ZERO)


func _draw_cinematic_scene(canvas_size: Vector2) -> void:
	# The menu owns a separate illustration panel, so the keep fills this canvas.
	var lord_visual: Dictionary = _lord_visual()
	var lord_icon: String = str(lord_visual.get("icon", "res://assets/icons/lord.svg"))
	var banner_color: Color = Color(str(lord_visual.get("color", "#b86b60"))).darkened(0.5)
	draw_rect(Rect2(Vector2.ZERO, canvas_size), Color("10191c"))
	var moon: Vector2 = Vector2(canvas_size.x * 0.70, canvas_size.y * 0.15)
	for radius in [150.0, 112.0, 84.0]:
		draw_circle(moon, radius, Color(0.45, 0.62, 0.55, 0.025))
	draw_circle(moon, 62, Color("718074"))
	draw_circle(moon + Vector2(-15, -12), 62, Color("10191c"))
	var left: float = canvas_size.x * 0.075
	var hall_width: float = canvas_size.x * 0.84
	var floor_y: float = canvas_size.y * 0.34
	for tower in range(4):
		var tower_x: float = left + tower * hall_width * 0.24
		var tower_height: float = 72 + (tower % 2) * 52
		draw_rect(Rect2(tower_x, floor_y - tower_height, hall_width * 0.16, tower_height + 70), Color("1b272a"))
		for tooth in range(3):
			draw_rect(Rect2(tower_x + tooth * hall_width * 0.053, floor_y - tower_height - 11, hall_width * 0.025, 14), Color("1b272a"))
		_draw_torch(Vector2(tower_x + 15, floor_y - tower_height + 27), float(tower + 4), 0.6)
	var hall: Rect2 = Rect2(left + 10, floor_y, hall_width - 10, canvas_size.y * 0.33)
	draw_rect(hall, Color("192124"))
	_draw_masonry(hall)
	_draw_arch(hall, Color("5e6154"))
	var throne_at: Vector2 = Vector2(hall.get_center().x, hall.end.y - 32)
	_draw_throne_furniture(throne_at, 1.65)
	_icon(lord_icon, Rect2(throne_at + Vector2(-50, -110), Vector2(100, 100)))
	_draw_banner(Vector2(hall.position.x + 44, hall.position.y + 20), banner_color, 32, 94)
	_draw_banner(Vector2(hall.end.x - 72, hall.position.y + 20), banner_color, 32, 94)
	_draw_torch(Vector2(hall.position.x + 48, hall.end.y - 55), 12, 1.6)
	_draw_torch(Vector2(hall.end.x - 50, hall.end.y - 55), 42, 1.6)
	_draw_platform(Rect2(hall.position.x - 10, hall.end.y, hall_width + 10, 17), 0)
	var basement: float = hall.end.y + 25
	for bay in range(4):
		var bay_rect: Rect2 = Rect2(hall.position.x + bay * hall.size.x / 4, basement, hall.size.x / 4, 110)
		draw_rect(bay_rect, Color("151c1d"))
		_draw_arch(bay_rect, Color("424c45"))
		var creature: String = ["goblin", "poison", "spider", "mimic"][bay]
		_icon(creature, Rect2(bay_rect.get_center() + Vector2(-26, -18), Vector2(52, 52)), Color(0.75, 0.80, 0.71, 0.9))
		_draw_torch(bay_rect.position + Vector2(bay_rect.size.x - 14, 33), bay + 8, 0.7)
	# Foreground earth silhouettes give the scene depth without obscuring the UI.
	for rock in range(17):
		var rock_x: float = left - 80 + rock * 45
		var rock_y: float = canvas_size.y - 13 + sin(rock * 2.3) * 14
		draw_colored_polygon(PackedVector2Array([Vector2(rock_x, canvas_size.y), Vector2(rock_x + 5, rock_y - 19), Vector2(rock_x + 30, rock_y - 30), Vector2(rock_x + 52, canvas_size.y)]), Color("0d1518"))
	for mote in range(20):
		var x: float = left + fmod(mote * 61.0 + sin(_clock * 0.3 + mote) * 8, hall_width)
		var y: float = fmod(mote * 73.0 - _clock * (4 + mote % 3) + canvas_size.y * 10, canvas_size.y)
		draw_circle(Vector2(x, y), 1 if mote % 3 else 2, Color(0.80, 0.58, 0.26, 0.12 + 0.08 * sin(_clock + mote)))


func _bar(rect: Rect2, ratio: float, color: Color, opacity: float = 1.0) -> void:
	draw_rect(rect.grow(1), Color(0.03, 0.05, 0.05, opacity))
	var fill: Rect2 = rect
	fill.size.x *= clampf(ratio, 0, 1)
	color.a *= opacity
	draw_rect(fill, color)


func _icon(id: String, rect: Rect2, tint: Color = Color.WHITE) -> void:
	var path: String = id if id.begins_with("res://") else "res://assets/icons/%s.svg" % id
	if not _textures.has(path):
		if ResourceLoader.exists(path):
			_textures[path] = load(path)
		else:
			return
	draw_texture_rect(_textures[path], rect, false, tint)


func _lord_visual() -> Dictionary:
	if game == null:
		return {}
	var archetype = game.get("lord_archetype")
	if not archetype is String:
		return {}
	return Lords.get_lord(str(archetype))


func _draw_defender_wards(at: Vector2, scale_factor: float = 1.0, actor_data: Dictionary = {}) -> void:
	# Only renders existing model state. Casting and expiry belong to DungeonGame.
	if game == null or (actor_data.is_empty() and game.defender.is_empty()):
		return
	var current: Dictionary = game.defender if actor_data.is_empty() else actor_data
	var radius: float = 30.0 * scale_factor
	_draw_run_skill_marks(at + Vector2(0, -radius - 14), current)
	if int(current.get("shield", 0)) > 0:
		draw_arc(at, radius, 0, TAU, 40, Color(0.46, 0.75, 0.79, 0.8), 2.0 * scale_factor, true)
		var badge: Vector2 = at + Vector2(radius - 3, -radius + 8)
		var shield: PackedVector2Array = PackedVector2Array([
			badge + Vector2(-6, -6) * scale_factor, badge + Vector2(6, -6) * scale_factor,
			badge + Vector2(5, 2) * scale_factor, badge + Vector2(0, 7) * scale_factor,
			badge + Vector2(-5, 2) * scale_factor,
		])
		draw_colored_polygon(shield, INK)
		shield.append(shield[0])
		draw_polyline(shield, Color("9dced0"), 2.0 * scale_factor, true)
	if bool(current.get("revive_mark", false)) or float(current.get("revenant_damage_bonus", 0.0)) > 0.0:
		var tint: Color = Color("b09ac8")
		for segment in range(4):
			var start: float = float(segment) * PI * 0.5 + _clock * 0.18
			draw_arc(at, radius, start, start + PI * 0.32, 12, tint, 1.8 * scale_factor, true)
		if bool(current.get("revive_mark", false)):
			var rune: Vector2 = at + Vector2(-radius + 3, -radius + 7)
			draw_circle(rune, 6.0 * scale_factor, INK)
			draw_line(rune + Vector2(0, -5) * scale_factor, rune + Vector2(0, 5) * scale_factor, tint, 2.0 * scale_factor)
			draw_line(rune + Vector2(-4, -1) * scale_factor, rune + Vector2(4, -1) * scale_factor, tint, 2.0 * scale_factor)
	if int(current.get("ability_attacks", 0)) > 0:
		var crest: Vector2 = at + Vector2(0, -radius - 3)
		draw_polyline(PackedVector2Array([
			crest + Vector2(-6, 5) * scale_factor, crest,
			crest + Vector2(6, 5) * scale_factor,
		]), GOLD, 2.0 * scale_factor, true)


func _draw_run_skill_marks(at: Vector2, actor: Dictionary) -> void:
	var skills: Dictionary = actor.get("effects", {}).get("run_skills", {})
	var labels := {"creatures_tough_hide": "Ш", "creatures_stubbornness": "У", "creatures_defiance": "Н", "creatures_discipline": "Д", "creatures_hunting_instinct": "О", "creatures_united_pack": "С", "creatures_battle_rhythm": "Р", "lord_last_word": "!", "lord_counterstrike": "↗", "lord_throne_wrath": "Г", "lord_fortified_throne": "Т", "shared_oath_of_the_fallen": "К", "ritual_impulse": "Q", "ritual_barrier": "Б", "ritual_cover": "Щ", "goblins_directed_orders": "П"}
	var active: Array = []
	for id in labels:
		if int(skills.get(id, 0)) > 0:
			active.append(id)
	for i in range(active.size()):
		var id: String = str(active[i])
		var row: int = i / 5
		var count: int = mini(5, active.size() - row * 5)
		var point: Vector2 = at + Vector2((i % 5 - (count - 1) * 0.5) * 17, -row * 18)
		var color: Color = TEAL if id.begins_with("ritual") else GOLD
		draw_circle(point, 7, INK)
		draw_arc(point, 7, 0, TAU, 16, color, 1, true)
		_center_text(str(labels[id]), point + Vector2(0, 3), 9, color)
		var charges: int = int(skills[id])
		if id == "ritual_cover":
			_center_text(str(charges), point + Vector2(0, 13), 8, color)
		elif charges > 1:
			for tick_index in range(mini(4, charges)):
				draw_circle(point + Vector2((tick_index - (charges - 1) * 0.5) * 3, 10), 1, color)


func _text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	draw_string(_font, at, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _center_text(value: String, at: Vector2, font_size: int, color: Color) -> void:
	var text_width: float = _font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_text(value, at - Vector2(text_width / 2, 0), font_size, color)


func _center_text_fitted(value: String, at: Vector2, font_size: int, color: Color, width: float) -> void:
	var result: String = value
	if _font.get_string_size(result, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		while result.length() > 1 and _font.get_string_size(result + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
			result = result.left(result.length() - 1)
		result += "…"
	_center_text(result, at, font_size, color)


func _input(event: InputEvent) -> void:
	# Track in viewport coordinates: the Control itself moves during a scroll.
	# Tracking here also catches a drag which has already left the room's bounds.
	if _pressed_slot < 0:
		return
	if event is InputEventScreenDrag and event.index == _touch_index:
		_track_drag(event.position)
	elif event is InputEventScreenTouch and event.pressed and _touch_index >= 0 and event.index != _touch_index:
		_press_dragged = true
	elif event is InputEventMouseMotion and _touch_index < 0 and event.device != -1:
		_track_drag(event.position)


func _notification(what: int) -> void:
	if what in [NOTIFICATION_SCROLL_BEGIN, NOTIFICATION_EXIT_TREE, NOTIFICATION_VISIBILITY_CHANGED, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_cancel_press()


func _gui_input(event: InputEvent) -> void:
	if cinematic:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if _touch_index < 0:
				_touch_index = event.index
				_begin_press(event.position)
		elif event.index == _touch_index:
			if event.canceled:
				_cancel_press()
			else:
				_finish_press(event.position)
		return
	if event is InputEventScreenDrag:
		return
	# Godot also emits mouse events for a touch. The original touch owns the tap.
	if event.device == -1:
		return
	if event is InputEventMouseMotion:
		var next_hover: int = _slot_at(event.position)
		if next_hover != _hovered_slot:
			_hovered_slot = next_hover
			queue_redraw()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_press(event.position)
		else:
			_finish_press(event.position)


func _begin_press(at: Vector2) -> void:
	_pressed_slot = _slot_at(at)
	_press_position = get_global_transform_with_canvas() * at
	_press_dragged = false


func _track_drag(at: Vector2) -> void:
	if at.distance_to(_press_position) > TAP_DRAG_DISTANCE:
		_press_dragged = true


func _finish_press(at: Vector2) -> void:
	_track_drag(get_global_transform_with_canvas() * at)
	var index: int = _slot_at(at)
	var is_tap: bool = not _press_dragged and index >= 0 and index == _pressed_slot
	var was_touch: bool = _touch_index >= 0
	_cancel_press()
	if is_tap:
		# Reset before emitting: main.gd may rebuild and reparent this Control.
		if was_touch:
			# The parent must receive touch-up to end its drag state. Rebuild only
			# after that event has propagated through the ScrollContainer.
			_emit_slot_tap.call_deferred(index)
		else:
			accept_event()
			slot_clicked.emit(index)


func _emit_slot_tap(index: int) -> void:
	if is_inside_tree() and is_visible_in_tree() and game != null and index < game.rooms.size():
		slot_clicked.emit(index)


func _cancel_press() -> void:
	_pressed_slot = -1
	_touch_index = -1
	_press_dragged = false


func _slot_at(at: Vector2) -> int:
	for index in range(_hit_rects.size()):
		if _hit_rects[index].has_point(at):
			return index
	return -1


func _on_mouse_exited() -> void:
	_hovered_slot = -1
	queue_redraw()


func _get_tooltip(at_position: Vector2) -> String:
	if cinematic or game == null:
		return ""
	var index: int = _slot_at(at_position)
	if index < 0:
		return ""
	if game.rooms[index].is_empty():
		return "Этаж %d · место %d\nВыберите комнату в магазине, затем нажмите здесь." % [index / 5 + 1, index % 5 + 1]
	var stats: Dictionary = game.room_stats(index)
	var result: String = "%s · ранг %d\n%s\n%s\n" % [stats.name, stats.rank, Content.room_traits_text(stats), stats.description]
	if str(stats.id) in ["ballista", "blade_floor"]:
		result += str(stats.get("role", "")) + "\n"
	var faction: Dictionary = game.room_faction(str(stats.id))
	result += "Фракция: %s\n" % str(faction.get("name", ""))
	if int(stats.hp) > 0:
		result += "Здоровье: %d · урон: %d · броня: %d\n" % [stats.hp, stats.damage, stats.armor]
	elif str(stats.get("kind", "")) == "poison":
		result += "Яд: %.2f за тик, %d тиков · до защиты жрицы\n" % [float(stats.get("poison_power_display", stats.get("damage", 0))), int(stats.get("poison_ticks_display", stats.get("poison_ticks", 0)))]
	elif str(stats.get("kind", "")) in ["shackles", "silence", "rust"]:
		result += "Длительность: %d боевых т. · эффект в следующем бою\n" % int(stats.get("effect_turns", 0))
		result += "Прямой удар: %d\n" % int(stats.get("impact_damage", 0))
		if bool(stats.get("impact_all", false)):
			result += "Удар по группе: 60% каждому живому герою\n"
	else:
		result += "Урон: %d, в обход брони\n" % int(stats.damage)
	result += "Награда героям: %d XP" % int(stats.xp)
	if not str(stats.item).is_empty():
		result += " и " + str(Content.item(str(stats.item)).name)
	var branch_name: String = str(stats.get("branch", ""))
	if not branch_name.is_empty():
		result += "\nСпециализация: " + branch_name
	var progression: Dictionary = game.room_progression(index)
	for stage in progression.get("stages", []):
		if int(stage.get("tier", 1)) > 1 and bool(stage.get("chosen", false)):
			result += "\nРанг %d: %s" % [int(stage.tier), str(stage.get("name", ""))]
	for actor_data in _slot_actors.get(index, []):
		var ready: PackedStringArray = []
		for skill_id in actor_data.get("effects", {}).get("run_skills", {}):
			var remaining: int = int(actor_data.effects.run_skills[skill_id])
			if remaining <= 0:
				continue
			var skill_name: String = "Приказы знамени" if str(skill_id) == "goblins_directed_orders" else str(game.run_skill_definition(str(skill_id)).get("name", skill_id))
			ready.append("%s: %d%s" % [skill_name, remaining, " HP щита" if str(skill_id) == "ritual_cover" else ""])
		if not ready.is_empty():
			result += "\n%s · %s" % [str(actor_data.get("name", "Защитник")), "; ".join(ready)]
	var combo: Dictionary = game.room_combo(index)
	if not combo.is_empty():
		result += "\nСВЯЗКА · %s\n%s" % [combo.name, combo.description]
	return result


func _draw_combos() -> void:
	# Model decides the pair and direction, including right-to-left floors.
	for combo in _combo_snapshot:
		var first: Rect2 = _slot_rect(int(combo.from))
		var second: Rect2 = _slot_rect(int(combo.to))
		var direction: float = signf(second.get_center().x - first.get_center().x)
		var start: Vector2 = Vector2(first.get_center().x, first.position.y + (39 if compact else 44))
		var finish: Vector2 = Vector2(second.get_center().x, second.position.y + (39 if compact else 44))
		var glow: Color = GOLD
		glow.a = 0.75
		draw_line(start, finish, Color(0.06, 0.07, 0.06, 0.85), 4 if compact else 6, true)
		draw_line(start, finish, glow, 1.5 if compact else 2, true)
		var tip_size: float = 3.0 if compact else 4.0
		draw_colored_polygon(PackedVector2Array([finish, finish + Vector2(-tip_size * 1.75 * direction, -tip_size), finish + Vector2(-tip_size * 1.75 * direction, tip_size)]), GOLD)
		var center: Vector2 = (start + finish) * 0.5
		draw_circle(center, 4 if compact else 8, INK)
		draw_arc(center, 4 if compact else 8, 0, TAU, 20, GOLD, 1.0 if compact else 1.5, true)
		_center_text("+", center + Vector2(0, 3 if compact else 4), 8 if compact else 12, GOLD)

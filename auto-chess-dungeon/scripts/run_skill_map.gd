extends Control
## View-only snowflake. Purchases and prerequisites belong to DungeonGame.
signal node_selected(id: String)
signal camera_changed(zoom: float)

const INK = Color("#10151c")
const PAPER = Color("#ede5d5")
const MUTED = Color("#8796a7")
const GOLD = Color("#dfba70")
const COLORS = {"lord": Color("#c5b4e3"), "creatures": Color("#82bda6"), "traps": Color("#c9a174"), "poison": Color("#a6bf76"), "economy": Color("#dfba70"), "ritual": Color("#89afd6"), "shared": Color("#b0bac9")}
const ICONS = {"lord": "lord", "creatures": "goblin", "traps": "ballista", "poison": "poison", "economy": "shop", "ritual": "lord_necromancer", "shared": "shield"}
var nodes: Array[Dictionary] = []
var selected_id: String = "root"
var zoom: float = 0.55
var pan: Vector2 = Vector2.ZERO
var _by_id: Dictionary = {}
var _textures: Dictionary = {}
var _bounds := Rect2(-1600, -1600, 3200, 3200)
var _hovered: String = ""
var _dragging: bool = false
var _moved: bool = false
var _pressed_at: Vector2 = Vector2.ZERO
var _touches: Dictionary = {}
var _touch_start: Vector2 = Vector2.ZERO
var _touch_moved: bool = false
var _initialized: bool = false
var _search: String = ""

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_resize_camera)

func configure(data: Array[Dictionary], selection: String = "root") -> void:
	nodes = data.duplicate(true)
	_by_id.clear()
	if not nodes.any(func(n): return str(n.id) == "root"):
		nodes.push_front({"id": "root", "name": "Владыка подземелья", "position": Vector2.ZERO, "parents": [], "learned": true, "category": "lord"})
	for node in nodes:
		var point = node.get("position", Vector2(float(node.get("x", 0)), float(node.get("y", 0))))
		if point is Array:
			point = Vector2(float(point[0]), float(point[1]))
		node.position = point
		_by_id[str(node.id)] = node
		var icon: String = _icon_for(node)
		if not _textures.has(icon):
			_textures[icon] = load("res://assets/icons/%s.svg" % icon)
	selected_id = selection if _by_id.has(selection) else "root"
	_bounds = Rect2(Vector2.ZERO, Vector2.ONE)
	for node in nodes:
		_bounds = _bounds.expand(node.position)
	_bounds = _bounds.grow(110)
	queue_redraw()

func set_selection(id: String, focus_camera: bool = false) -> void:
	if not _by_id.has(id):
		return
	selected_id = id
	if focus_camera:
		zoom = maxf(zoom, 0.85)
		pan = -Vector2(_by_id[id].position) * zoom
		camera_changed.emit(zoom)
	queue_redraw()

func set_search(query: String) -> void:
	_search = query.strip_edges().to_lower()
	queue_redraw()

func restore_camera(saved_zoom: float, saved_pan: Vector2) -> void:
	_initialized = true
	zoom = clampf(saved_zoom, 0.035, 2.4)
	pan = saved_pan
	camera_changed.emit(zoom)
	queue_redraw()

func reset_center() -> void:
	zoom = 0.55
	pan = Vector2.ZERO
	camera_changed.emit(zoom)
	queue_redraw()

func fit_all() -> void:
	zoom = clampf(minf((size.x - 60) / _bounds.size.x, (size.y - 70) / _bounds.size.y), 0.035, 1.0)
	pan = -_bounds.get_center() * zoom
	camera_changed.emit(zoom)
	queue_redraw()

func zoom_by(factor: float, at: Vector2 = Vector2(-1, -1)) -> void:
	if at.x < 0:
		at = size * 0.5
	var world: Vector2 = (at - size * 0.5 - pan) / zoom
	zoom = clampf(zoom * factor, 0.035, 2.4)
	pan = at - size * 0.5 - world * zoom
	camera_changed.emit(zoom)
	queue_redraw()

func _resize_camera() -> void:
	if not _initialized and size.x > 40:
		_initialized = true
		fit_all()
	queue_redraw()

func _screen(world: Vector2) -> Vector2:
	return size * 0.5 + pan + world * zoom

func _radius(node: Dictionary) -> float:
	return clampf((42.0 if str(node.id) == "root" else 32.0) * zoom, 6.0, 55.0)

func _learned(node: Dictionary) -> bool:
	return bool(node.get("learned", false)) or str(node.get("state", "")) in ["acquired", "learned"]

func _available(node: Dictionary) -> bool:
	return bool(node.get("available", node.get("can_buy", false)))

func _parents(node: Dictionary) -> Array:
	if node.has("parents"):
		return node.parents
	var result: Array = []
	result.append_array(node.get("requires_all", []))
	result.append_array(node.get("requires_any", []))
	return result

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	var viewport := Rect2(Vector2(-80, -80), size + Vector2(160, 160))
	# All prerequisite lines are drawn, including locked and alternative routes.
	for node in nodes:
		var end: Vector2 = _screen(node.position)
		for parent_id in _parents(node):
			if not _by_id.has(str(parent_id)):
				continue
			var parent: Dictionary = _by_id[str(parent_id)]
			var start: Vector2 = _screen(parent.position)
			var direction: Vector2 = (end - start).normalized()
			var color := Color("#4e5e70")
			var width: float = 1.2
			if _learned(parent) and _learned(node):
				color = COLORS.get(str(node.get("category", "shared")), PAPER)
				width = 2.1
			elif str(node.id) == selected_id:
				color = GOLD
				width = 2.0
			draw_line(start + direction * _radius(parent), end - direction * _radius(node), color, width, true)
	for node in nodes:
		var pos: Vector2 = _screen(node.position)
		if not viewport.has_point(pos):
			continue
		var radius: float = _radius(node)
		var id: String = str(node.id)
		var category: String = str(node.get("category", "shared"))
		var accent: Color = COLORS.get(category, PAPER)
		var selected: bool = id == selected_id
		var hovered: bool = id == _hovered
		var learned: bool = _learned(node)
		var matches: bool = _search.is_empty() or str(node.get("name", "")).to_lower().contains(_search)
		var edge: Color = accent if learned else GOLD if _available(node) else Color("#627084")
		if not matches and not selected:
			edge.a = 0.38
		if selected or hovered:
			draw_circle(pos, radius + 5, Color(0.87, 0.73, 0.44, 0.12))
			edge = GOLD if hovered else PAPER
		draw_circle(pos, radius, INK.lerp(accent, 0.22 if learned else 0.045))
		draw_arc(pos, radius, 0, TAU, 36, edge, 2.2 if selected or learned else 1.3, true)
		var icon: String = _icon_for(node)
		if radius > 12 and _textures.has(icon):
			var extent: float = radius * 1.25
			draw_texture_rect(_textures[icon], Rect2(pos - Vector2.ONE * extent * 0.5, Vector2.ONE * extent), false, Color.WHITE if matches else Color(0.5, 0.5, 0.5))
		if learned and id != "root":
			var mark: Vector2 = pos + Vector2(radius * 0.7, radius * 0.7)
			draw_circle(mark, 6, INK)
			draw_polyline(PackedVector2Array([mark + Vector2(-3, 0), mark + Vector2(-1, 2), mark + Vector2(3, -3)]), accent, 1.8, true)
		elif radius > 15 and not _available(node) and id != "root":
			var mark: Vector2 = pos + Vector2(radius * 0.7, radius * 0.7)
			draw_circle(mark, 7, INK)
			draw_arc(mark + Vector2(0, -1), 3, PI, TAU, 10, MUTED, 1.1, true)
			draw_rect(Rect2(mark + Vector2(-3, -1), Vector2(6, 5)), MUTED, false, 1)
		if selected or hovered or (zoom >= 0.9 and matches):
			_draw_caption(pos + Vector2(0, radius + 16), str(node.get("name", id)), PAPER if selected else accent)
	_draw_minimap()

func _draw_caption(pos: Vector2, text: String, color: Color) -> void:
	var font: Font = get_theme_default_font()
	var width: float = minf(210, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	draw_rect(Rect2(pos + Vector2(-width * 0.5 - 4, -12), Vector2(width + 8, 18)), INK)
	draw_string(font, pos - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, width, 12, color)

func _mini_rect() -> Rect2:
	return Rect2(Vector2(12, size.y - 112), Vector2(130, 100))

func _draw_minimap() -> void:
	if size.x < 360 or size.y < 260:
		return
	var box: Rect2 = _mini_rect()
	draw_rect(box, Color("#171e27"))
	draw_rect(box, Color("#3b4858"), false)
	var scale_value: float = minf((box.size.x - 10) / _bounds.size.x, (box.size.y - 10) / _bounds.size.y)
	var origin: Vector2 = box.get_center() - _bounds.get_center() * scale_value
	for node in nodes:
		draw_circle(origin + Vector2(node.position) * scale_value, 1.7 if _learned(node) else 1.1, COLORS.get(str(node.get("category", "shared")), MUTED))
	var top: Vector2 = (-size * 0.5 - pan) / zoom
	var visible_world := Rect2(top, size / zoom)
	var view := Rect2(origin + visible_world.position * scale_value, visible_world.size * scale_value).intersection(box)
	if view.has_area():
		draw_rect(view, GOLD, false, 1.2)

func _hit(point: Vector2) -> String:
	var best: String = ""
	var distance: float = INF
	for node in nodes:
		var d: float = point.distance_to(_screen(node.position))
		if d <= maxf(12, _radius(node) + 4) and d < distance:
			best = str(node.id)
			distance = d
	return best

func _select_at(point: Vector2) -> void:
	if size.x >= 360 and size.y >= 260 and _mini_rect().has_point(point):
		var box: Rect2 = _mini_rect()
		var mini_scale: float = minf((box.size.x - 10) / _bounds.size.x, (box.size.y - 10) / _bounds.size.y)
		pan = -(_bounds.get_center() + (point - box.get_center()) / mini_scale) * zoom
		queue_redraw()
		return
	var id: String = _hit(point)
	if not id.is_empty():
		set_selection(id)
		node_selected.emit(id)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if not _touches.is_empty():
			accept_event()
			return
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			zoom_by(1.18 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.18, event.position)
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				grab_focus()
				_dragging = true
				_moved = false
				_pressed_at = event.position
			else:
				if _dragging and not _moved and event.button_index == MOUSE_BUTTON_LEFT:
					_select_at(event.position)
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		if _dragging:
			_moved = _moved or event.position.distance_to(_pressed_at) > 5
			if _moved:
				pan += event.relative
		else:
			_hovered = _hit(event.position)
			tooltip_text = str(_by_id.get(_hovered, {}).get("name", ""))
		queue_redraw()
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by(event.factor, event.position)
		accept_event()
	elif event is InputEventPanGesture:
		pan -= event.delta * 18
		queue_redraw()
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
			_touch_start = event.position
			_touch_moved = _touches.size() > 1
		else:
			if not event.canceled and _touches.size() == 1 and not _touch_moved:
				_select_at(event.position)
			_touches.erase(event.index)
			_touch_moved = true
		accept_event()
	elif event is InputEventScreenDrag:
		if _touches.has(event.index):
			if _touches.size() == 2:
				var points: Array = _touches.values()
				var old_distance: float = Vector2(points[0]).distance_to(points[1])
				var old_center: Vector2 = (Vector2(points[0]) + Vector2(points[1])) * 0.5
				_touches[event.index] = event.position
				points = _touches.values()
				var new_center: Vector2 = (Vector2(points[0]) + Vector2(points[1])) * 0.5
				if old_distance > 4:
					zoom_by(Vector2(points[0]).distance_to(points[1]) / old_distance, old_center)
				pan += new_center - old_center
				_touch_moved = true
			else:
				_touch_moved = _touch_moved or event.position.distance_to(_touch_start) > 5
				if _touch_moved:
					pan += event.relative
				_touches[event.index] = event.position
			queue_redraw()
		accept_event()
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_PLUS, KEY_EQUAL, KEY_KP_ADD: zoom_by(1.18)
			KEY_MINUS, KEY_KP_SUBTRACT: zoom_by(1.0 / 1.18)
			KEY_HOME: reset_center()
			KEY_LEFT: _keyboard_node(Vector2.LEFT)
			KEY_RIGHT: _keyboard_node(Vector2.RIGHT)
			KEY_UP: _keyboard_node(Vector2.UP)
			KEY_DOWN: _keyboard_node(Vector2.DOWN)
			_: return
		accept_event()

func _keyboard_node(direction: Vector2) -> void:
	var point: Vector2 = _by_id.get(selected_id, {}).get("position", Vector2.ZERO)
	var best: String = ""
	var score: float = INF
	for node in nodes:
		var delta: Vector2 = Vector2(node.position) - point
		if delta.dot(direction) <= 0:
			continue
		var candidate: float = delta.length() * (2.0 - delta.normalized().dot(direction))
		if candidate < score:
			score = candidate
			best = str(node.id)
	if not best.is_empty():
		set_selection(best, true)
		node_selected.emit(best)

func _icon_for(node: Dictionary) -> String:
	var id: String = str(node.id)
	for fragment in ["strength", "might", "onslaught", "anatomy", "counterstrike", "frenzied"]:
		if id.contains(fragment):
			return "sword"
	for fragment in ["armor", "hide", "barrier", "cover", "aegis", "carapace", "bulwark"]:
		if id.contains(fragment):
			return "shield"
	for fragment in ["brood", "pack", "beast"]:
		if id.contains(fragment):
			return "spider"
	for fragment in ["spectral", "lament", "will", "soul", "legacy"]:
		if id.contains(fragment):
			return "wraith"
	return str(ICONS.get(str(node.get("category", "shared")), "lord"))

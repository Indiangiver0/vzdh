extends Control
## View-only snowflake. Purchases and prerequisites belong to DungeonGame.
signal node_selected(id: String)
signal camera_changed(zoom: float)

const MIN_ZOOM: float = 0.035
const MAX_ZOOM: float = 2.4
const CAMERA_RESPONSE: float = 16.0
const ZOOM_EPSILON: float = 0.00001
const PAN_EPSILON: float = 0.02
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
var _configured: bool = false
var _initial_fit_pending: bool = false
var _camera_active: bool = false
var _target_zoom: float = 0.55
var _target_pan: Vector2 = Vector2.ZERO
var _zoom_anchored: bool = false
var _anchor_world: Vector2 = Vector2.ZERO
var _anchor_offset: Vector2 = Vector2.ZERO
var _pointer_known: bool = false
var _pointer_position: Vector2 = Vector2.ZERO
var _drag_button: int = MOUSE_BUTTON_NONE

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	resized.connect(_resize_camera)
	mouse_exited.connect(func():
		_pointer_known = false
		_set_hovered(""))
	set_process(false)


func _ready() -> void:
	set_process(_camera_active)
	_queue_initial_fit()


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
	_configured = not data.is_empty()
	_queue_initial_fit()
	queue_redraw()

func set_selection(id: String, focus_camera: bool = false) -> void:
	if not _by_id.has(id):
		return
	var changed: bool = selected_id != id
	selected_id = id
	if focus_camera:
		var focused_zoom: float = maxf(zoom, 0.85)
		_move_camera(focused_zoom, -Vector2(_by_id[id].position) * focused_zoom, _initialized)
	if changed:
		queue_redraw()


func set_search(query: String) -> void:
	var normalized: String = query.strip_edges().to_lower()
	if normalized == _search:
		return
	_search = normalized
	queue_redraw()


func restore_camera(saved_zoom: float, saved_pan: Vector2) -> void:
	if not is_finite(saved_zoom) or not saved_pan.is_finite():
		return
	_move_camera(clampf(saved_zoom, MIN_ZOOM, MAX_ZOOM), saved_pan, false)


func reset_center() -> void:
	var root: Vector2 = _by_id.get("root", {}).get("position", Vector2.ZERO)
	_move_camera(zoom, -root * zoom, _initialized)


func fit_all() -> void:
	if not _configured or size.x <= 40.0 or size.y <= 40.0:
		_queue_initial_fit()
		return
	var fitted_zoom: float = clampf(minf((size.x - 60.0) / _bounds.size.x, (size.y - 70.0) / _bounds.size.y), MIN_ZOOM, 1.0)
	_move_camera(fitted_zoom, -_bounds.get_center() * fitted_zoom, _initialized)


func set_zoom(value: float, at: Vector2 = Vector2(-1, -1), animate: bool = true) -> void:
	if not is_finite(value) or not at.is_finite():
		return
	if at.x < 0:
		at = size * 0.5
	var requested_zoom: float = clampf(value, MIN_ZOOM, MAX_ZOOM)
	var offset: Vector2 = at - size * 0.5
	var world: Vector2 = (offset - pan) / zoom
	var requested_pan: Vector2 = offset - world * requested_zoom
	if not world.is_finite() or not requested_pan.is_finite():
		return
	_move_camera(requested_zoom, requested_pan, animate)
	if _camera_active:
		_zoom_anchored = true
		_anchor_world = world
		_anchor_offset = offset


func zoom_by(factor: float, at: Vector2 = Vector2(-1, -1)) -> void:
	if not is_finite(factor) or factor <= 0.0 or not at.is_finite() or factor == 1.0:
		return
	var direction: float = signf(factor - 1.0)
	var base: float = zoom
	# Repeated input accumulates, but reversal immediately starts at the shown zoom.
	if _camera_active and _zoom_anchored and signf(_target_zoom - zoom) == direction:
		base = _target_zoom
	set_zoom(clampf(base * factor, MIN_ZOOM, MAX_ZOOM), at)


func _move_camera(next_zoom: float, next_pan: Vector2, animate: bool) -> void:
	if not is_finite(next_zoom) or not next_pan.is_finite():
		return
	_initialized = true
	_cancel_camera()
	_target_zoom = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	_target_pan = next_pan
	if not animate or (_target_zoom == zoom and _target_pan == pan):
		_apply_camera(_target_zoom, _target_pan)
		return
	_camera_active = true
	set_process(true)


func _cancel_camera() -> void:
	_camera_active = false
	_zoom_anchored = false
	_target_zoom = zoom
	_target_pan = pan
	set_process(false)


func _apply_camera(next_zoom: float, next_pan: Vector2) -> void:
	if not is_finite(next_zoom) or not next_pan.is_finite():
		return
	next_zoom = clampf(next_zoom, MIN_ZOOM, MAX_ZOOM)
	if next_zoom == zoom and next_pan == pan:
		return
	zoom = next_zoom
	pan = next_pan
	if _pointer_known and not _dragging and _touches.is_empty():
		_set_hovered(_hit(_pointer_position), false)
	camera_changed.emit(zoom)
	queue_redraw()


func _process(delta: float) -> void:
	if not _camera_active:
		set_process(false)
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	# Exponential interpolation follows elapsed time, independent of frame rate.
	var weight: float = 1.0 - exp(-CAMERA_RESPONSE * delta)
	var shown_zoom: float = lerpf(zoom, _target_zoom, weight)
	var shown_pan: Vector2 = _anchor_offset - _anchor_world * shown_zoom if _zoom_anchored else pan.lerp(_target_pan, weight)
	if absf(shown_zoom - _target_zoom) <= ZOOM_EPSILON and shown_pan.distance_to(_target_pan) <= PAN_EPSILON:
		_apply_camera(_target_zoom, _target_pan)
		_cancel_camera()
	else:
		_apply_camera(shown_zoom, shown_pan)


func _queue_initial_fit() -> void:
	if _initialized or not _configured or _initial_fit_pending or not is_inside_tree():
		return
	_initial_fit_pending = true
	_finish_initial_fit.call_deferred()


func _finish_initial_fit() -> void:
	if not is_inside_tree():
		_initial_fit_pending = false
		return
	# A child can be configured before its Container has assigned the real size.
	await get_tree().process_frame
	_initial_fit_pending = false
	if _initialized or not _configured or not is_inside_tree():
		return
	if size.x <= 40.0 or size.y <= 40.0:
		return
	fit_all()


func _resize_camera() -> void:
	_queue_initial_fit()
	queue_redraw()


func _set_hovered(id: String, redraw: bool = true) -> void:
	if id == _hovered:
		return
	_hovered = id
	tooltip_text = str(_by_id.get(_hovered, {}).get("name", ""))
	if redraw:
		queue_redraw()


func _drag_camera(offset: Vector2) -> void:
	if not offset.is_finite():
		return
	_initialized = true
	_cancel_camera()
	_apply_camera(zoom, pan + offset)

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
		var caption_alpha: float = 1.0 if selected or hovered else smoothstep(0.72, 1.05, zoom) if matches else 0.0
		if caption_alpha > 0.0:
			_draw_caption(pos + Vector2(0, radius + 16), str(node.get("name", id)), PAPER if selected else accent, caption_alpha)
	_draw_minimap()

func _draw_caption(pos: Vector2, text: String, color: Color, opacity: float = 1.0) -> void:
	var font: Font = get_theme_default_font()
	var width: float = minf(210, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x)
	var background: Color = INK
	background.a *= opacity
	color.a *= opacity
	draw_rect(Rect2(pos + Vector2(-width * 0.5 - 4, -12), Vector2(width + 8, 18)), background)
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
		_move_camera(zoom, -(_bounds.get_center() + (point - box.get_center()) / mini_scale) * zoom, _initialized)
		return
	var id: String = _hit(point)
	if not id.is_empty():
		set_selection(id)
		node_selected.emit(id)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# A touch owns its gesture, including the emulated mouse release after it.
		if event.device == -1 or not _touches.is_empty():
			accept_event()
			return
		if not event.position.is_finite():
			accept_event()
			return
		_pointer_known = true
		_pointer_position = event.position
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var amount: float = absf(event.factor) if event.factor != 0.0 else 1.0
			if is_finite(amount):
				var direction: float = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
				zoom_by(pow(1.18, direction * minf(amount, 100.0)), event.position)
				_moved = _moved or _dragging
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			if event.pressed:
				grab_focus()
				_cancel_camera()
				_dragging = true
				_drag_button = event.button_index
				_moved = false
				_pressed_at = event.position
			elif event.button_index == _drag_button:
				var select: bool = _dragging and not _moved and event.button_index == MOUSE_BUTTON_LEFT
				_dragging = false
				_drag_button = MOUSE_BUTTON_NONE
				if select:
					_select_at(event.position)
		accept_event()
	elif event is InputEventMouseMotion:
		if event.device == -1 or not _touches.is_empty() or not event.position.is_finite():
			accept_event()
			return
		_pointer_known = true
		_pointer_position = event.position
		if _dragging:
			var was_moved: bool = _moved
			_moved = _moved or event.position.distance_to(_pressed_at) > 5.0
			if _moved:
				_drag_camera(event.relative if was_moved else event.position - _pressed_at)
		else:
			_set_hovered(_hit(event.position))
		accept_event()
	elif event is InputEventMagnifyGesture:
		if _touches.is_empty() and is_finite(event.factor) and event.factor > 0.0:
			set_zoom(clampf(zoom * event.factor, MIN_ZOOM, MAX_ZOOM), event.position, false)
			_moved = _moved or _dragging
		accept_event()
	elif event is InputEventPanGesture:
		if _touches.is_empty():
			_drag_camera(-event.delta * 18.0)
			_moved = _moved or _dragging
		accept_event()
	elif event is InputEventScreenTouch:
		if not event.position.is_finite():
			accept_event()
			return
		if event.pressed:
			_cancel_camera()
			_dragging = false
			_drag_button = MOUSE_BUTTON_NONE
			_pointer_known = false
			_set_hovered("")
			if _touches.is_empty():
				_touch_start = event.position
				_touch_moved = false
			_touches[event.index] = event.position
			_touch_moved = _touch_moved or _touches.size() > 1
		elif _touches.has(event.index):
			var select: bool = not event.canceled and _touches.size() == 1 and not _touch_moved
			_touches.erase(event.index)
			_touch_moved = true
			if select:
				_select_at(event.position)
		accept_event()
	elif event is InputEventScreenDrag:
		if _touches.has(event.index) and event.position.is_finite():
			if _touches.size() == 2:
				var points: Array = _touches.values()
				var old_distance: float = Vector2(points[0]).distance_to(points[1])
				var old_center: Vector2 = (Vector2(points[0]) + Vector2(points[1])) * 0.5
				_touches[event.index] = event.position
				points = _touches.values()
				var new_center: Vector2 = (Vector2(points[0]) + Vector2(points[1])) * 0.5
				var ratio: float = Vector2(points[0]).distance_to(points[1]) / old_distance if old_distance > 4.0 else 1.0
				var world: Vector2 = (old_center - size * 0.5 - pan) / zoom
				var next_zoom: float = clampf(zoom * ratio, MIN_ZOOM, MAX_ZOOM)
				# Scale and centroid motion share one transform; no second pan offset.
				_move_camera(next_zoom, new_center - size * 0.5 - world * next_zoom, false)
				_touch_moved = true
			elif _touches.size() == 1:
				var was_moved: bool = _touch_moved
				_touch_moved = _touch_moved or event.position.distance_to(_touch_start) > 5.0
				if _touch_moved:
					var offset: Vector2 = event.position - Vector2(_touches[event.index]) if was_moved else event.position - _touch_start
					_drag_camera(offset)
				_touches[event.index] = event.position
			else:
				_touches[event.index] = event.position
				_touch_moved = true
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

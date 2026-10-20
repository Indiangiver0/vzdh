extends Control
## View-only progression graph. The caller owns selection details and purchases.
##
## nodes: {id, name, parents: Array[String], depth: int,
##         state: acquired|available|locked|maxed|unaffordable|other,
##         status: String, icon: String (optional resource path or icon basename)}
## Every node remains selectable, including future and unchosen branches.

signal node_selected(id: String)

const PAPER = Color("#ede5d5")
const MUTED = Color("#929eaf")
const GOLD = Color("#dfba70")
const GREEN = Color("#83bfa6")
const LINE = Color("#333e4e")
const PANEL = Color("#181e28")
const TILE = Color("#212938")

var _nodes: Array[Dictionary] = []
var _selected_id: String = ""
var _compact: bool = false
var _buttons: Dictionary = {}
var _statuses: Dictionary = {}
var _emblems: Dictionary = {}
var _rows: Dictionary = {}
var _layout_pending: bool = false
var _laying_out: bool = false
var _last_width: float = -1.0


class Emblem extends Control:
	var texture: Texture2D
	var state: String = "locked"
	var selected: bool = false

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var ink := Color("#0e1118")
		var accent := Color("#dfba70") if selected or state == "available" else Color("#59687b")
		if state in ["acquired", "maxed"] and not selected:
			accent = Color("#83bfa6")
		draw_circle(center, 22.0, ink)
		draw_arc(center, 21.0, 0.0, TAU, 32, accent, 1.4, true)
		if texture != null:
			var tint := Color.WHITE
			if state in ["locked", "other"]:
				tint = Color(0.72, 0.76, 0.82)
			draw_texture_rect(texture, Rect2(center - Vector2(17, 17), Vector2(34, 34)), false, tint)
		else:
			var diamond := PackedVector2Array([
				center + Vector2(0, -9), center + Vector2(7, 0),
				center + Vector2(0, 9), center + Vector2(-7, 0),
				center + Vector2(0, -9),
			])
			draw_polyline(diamond, accent, 1.5, true)
			draw_circle(center, 2.0, accent)
		if state in ["acquired", "maxed"]:
			var mark := center + Vector2(16, 14)
			draw_circle(mark, 8.0, ink)
			draw_polyline(PackedVector2Array([
				mark + Vector2(-4, 0), mark + Vector2(-1, 3), mark + Vector2(5, -4),
			]), Color("#83bfa6"), 2.0, true)
		elif state == "locked":
			var lock_center := center + Vector2(16, 14)
			draw_circle(lock_center, 8.0, ink)
			draw_arc(lock_center + Vector2(0, -2), 3.0, PI, TAU, 12, accent, 1.5, true)
			draw_rect(Rect2(lock_center + Vector2(-4, -2), Vector2(8, 6)), accent, false, 1.5)
			draw_line(lock_center, lock_center + Vector2(0, 2), accent, 1.0, true)


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_meta("progression_tree", true)
	resized.connect(_request_layout)


func _ready() -> void:
	_request_layout()


func configure(nodes: Array[Dictionary], selected_id: String = "", compact: bool = false) -> void:
	_nodes = nodes.duplicate(true)
	_selected_id = selected_id
	_compact = compact
	_buttons.clear()
	_statuses.clear()
	_emblems.clear()
	_rows.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for data in _nodes:
		var id: String = str(data.get("id", ""))
		if id.is_empty() or _buttons.has(id):
			continue
		_create_node(data)
	_last_width = -1.0
	_request_layout()


func focus_node(id: String) -> void:
	if _buttons.has(id):
		var button: Button = _buttons[id]
		if is_instance_valid(button) and button.is_inside_tree():
			button.grab_focus()


func _create_node(data: Dictionary) -> void:
	var id: String = str(data.id)
	var button := Button.new()
	button.name = "Progression_" + id.validate_node_name()
	button.text = str(data.get("name", id))
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# A long word must wrap inside the chosen column, not enlarge its minimum width.
	button.clip_text = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.tooltip_text = button.text
	var status_text: String = str(data.get("status", ""))
	if not status_text.is_empty():
		button.tooltip_text += "\n" + status_text
	button.pressed.connect(_select_node.bind(id))
	button.focus_entered.connect(_focus_node.bind(id))
	button.mouse_entered.connect(queue_redraw)
	button.mouse_exited.connect(queue_redraw)
	add_child(button)
	_buttons[id] = button

	var status := Label.new()
	status.text = status_text
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(status)
	_statuses[id] = status

	var emblem := Emblem.new()
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.state = str(data.get("state", "locked"))
	var icon_path: String = str(data.get("icon", ""))
	if not icon_path.is_empty():
		if not icon_path.begins_with("res://"):
			icon_path = "res://assets/icons/" + icon_path.trim_suffix(".svg") + ".svg"
		if ResourceLoader.exists(icon_path):
			emblem.texture = load(icon_path) as Texture2D
	button.add_child(emblem)
	_emblems[id] = emblem


func _request_layout() -> void:
	if _layout_pending or _laying_out:
		return
	_layout_pending = true
	_layout_nodes.call_deferred()


func _layout_nodes() -> void:
	_layout_pending = false
	if not is_inside_tree() or size.x < 40.0:
		return
	_laying_out = true
	var width: float = maxf(1.0, size.x)
	var narrow: bool = _compact or width < 620.0
	var gap: float = 10.0 if narrow else 16.0
	var outer: float = 18.0
	var usable: float = maxf(1.0, width - outer * 2.0)
	var font_size: int = 15 if narrow else 17
	var status_size: int = 12 if narrow else 13
	var font: Font = get_theme_font("font", "Button")
	var groups: Dictionary = {}
	for data in _nodes:
		var id: String = str(data.get("id", ""))
		if not _buttons.has(id):
			continue
		var depth: int = int(data.get("depth", 0))
		if not groups.has(depth):
			groups[depth] = []
		groups[depth].append(data)
	var depths: Array = groups.keys()
	depths.sort()
	var y: float = 4.0
	var row_number: int = 0
	_rows.clear()
	for depth in depths:
		var group: Array = groups[depth]
		var columns: int = mini(4, maxi(1, int((usable + gap) / (154.0 + gap))))
		if narrow:
			columns = 2 if group.size() == 2 and usable >= 236.0 else 1
		columns = mini(columns, group.size())
		for start in range(0, group.size(), columns):
			var count: int = mini(columns, group.size() - start)
			var node_width: float = minf(248.0, (usable - gap * float(count - 1)) / float(count))
			var x: float = (width - (node_width * count + gap * (count - 1))) * 0.5
			var row_height: float = 0.0
			var metrics: Array[Dictionary] = []
			for column in range(count):
				var data: Dictionary = group[start + column]
				var title_height: float = maxf(22.0, _text_height(
					font, str(data.get("name", "")), node_width - 20.0, font_size
				))
				var status_height: float = 0.0
				if not str(data.get("status", "")).is_empty():
					status_height = maxf(18.0, _text_height(
						font, str(data.status), node_width - 20.0, status_size
					))
				var height: float = 60.0 + title_height + status_height + 16.0
				metrics.append({"status_height": status_height})
				row_height = maxf(row_height, maxf(110.0, height))
			for column in range(count):
				var data: Dictionary = group[start + column]
				var id: String = str(data.id)
				var button: Button = _buttons[id]
				var status: Label = _statuses[id]
				var emblem: Emblem = _emblems[id]
				var status_height: float = float(metrics[column].status_height)
				_style_node(data, font_size, status_size, status_height)
				button.position = Vector2(x, y)
				button.size = Vector2(node_width, row_height)
				status.position = Vector2(10.0, row_height - status_height - 12.0)
				status.size = Vector2(maxf(1.0, node_width - 20.0), status_height)
				status.visible = status_height > 0.0
				emblem.position = Vector2((node_width - 48.0) * 0.5, 8.0)
				emblem.size = Vector2(48, 48)
				emblem.queue_redraw()
				_rows[id] = row_number
				x += node_width + gap
			y += row_height + 38.0
			row_number += 1
	custom_minimum_size = Vector2(0.0, maxf(0.0, y - 30.0))
	_last_width = width
	_laying_out = false
	queue_redraw()


func _text_height(font: Font, text: String, width: float, font_size: int) -> float:
	# Match AUTOWRAP_WORD_SMART, including words longer than the entire column.
	var flags: int = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
	return ceilf(font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, maxf(1.0, width), font_size, -1, flags
	).y) + 2.0


func _style_node(data: Dictionary, font_size: int, status_size: int, status_height: float) -> void:
	var id: String = str(data.id)
	var state: String = str(data.get("state", "locked"))
	var button: Button = _buttons[id]
	var status: Label = _statuses[id]
	var emblem: Emblem = _emblems[id]
	var selected: bool = id == _selected_id
	var edge: Color = LINE
	var background: Color = PANEL
	var caption: Color = MUTED
	if state in ["acquired", "maxed"]:
		edge = GREEN.darkened(0.3)
		caption = GREEN
	elif state == "available":
		edge = GOLD.darkened(0.25)
		caption = GOLD
	elif state == "other":
		background = Color("#141922")
	if selected:
		edge = GOLD
		background = Color("#2c2b29")
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", PAPER if state != "other" else MUTED)
	button.add_theme_color_override("font_hover_color", PAPER)
	button.add_theme_color_override("font_pressed_color", PAPER)
	button.add_theme_color_override("font_focus_color", PAPER)
	for style_name in ["normal", "hover", "pressed"]:
		var fill: Color = background
		var border: Color = edge
		if style_name == "hover":
			fill = background.lightened(0.07)
			border = GOLD
		elif style_name == "pressed":
			fill = TILE
			border = GOLD
		button.add_theme_stylebox_override(style_name, _card_style(fill, border, 2 if selected else 1, status_height))
	var focus := _card_style(Color.TRANSPARENT, PAPER, 2, status_height)
	focus.draw_center = false
	button.add_theme_stylebox_override("focus", focus)
	status.add_theme_font_size_override("font_size", status_size)
	status.add_theme_color_override("font_color", caption)
	emblem.selected = selected


func _card_style(fill: Color, edge: Color, border_width: int, status_height: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(10)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 60.0
	style.content_margin_bottom = status_height + 16.0
	return style


func _select_node(id: String) -> void:
	_selected_id = id
	# Do not rebuild controls: keyboard focus and the caller's scroll stay put.
	_layout_nodes()
	node_selected.emit(id)


func _focus_node(_id: String) -> void:
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_request_layout()


func _draw() -> void:
	if not is_equal_approx(_last_width, size.x):
		_request_layout()
	for data in _nodes:
		var child_id: String = str(data.get("id", ""))
		if not _buttons.has(child_id):
			continue
		var child: Button = _buttons[child_id]
		for parent_id_value in data.get("parents", []):
			var parent_id: String = str(parent_id_value)
			if not _buttons.has(parent_id):
				continue
			var parent: Button = _buttons[parent_id]
			var start: Vector2 = parent.position + Vector2(parent.size.x * 0.5, parent.size.y)
			var finish: Vector2 = child.position + Vector2(child.size.x * 0.5, 0.0)
			if finish.y <= start.y:
				continue
			var state: String = str(data.get("state", "locked"))
			var color: Color = GOLD.darkened(0.35) if child_id == _selected_id else LINE.lightened(0.12)
			if state in ["acquired", "maxed"] and child_id != _selected_id:
				color = GREEN.darkened(0.35)
			var points := PackedVector2Array()
			if int(_rows.get(child_id, 0)) - int(_rows.get(parent_id, 0)) > 1:
				# A wrapped tier uses the outside gutter, never another card's face.
				var gutter: float = 7.0 if finish.x <= size.x * 0.5 else size.x - 7.0
				points = PackedVector2Array([
					start, start + Vector2(0, 14), Vector2(gutter, start.y + 14),
					Vector2(gutter, finish.y - 14), finish - Vector2(0, 14), finish,
				])
			else:
				var middle: float = (start.y + finish.y) * 0.5
				points = PackedVector2Array([start, Vector2(start.x, middle), Vector2(finish.x, middle), finish])
			draw_polyline(points, color, 1.5, true)
			draw_circle(finish, 2.5, color)

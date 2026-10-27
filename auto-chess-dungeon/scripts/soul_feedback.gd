extends Control
## A presentation-only flight from the defeated hero to the soul wallet.
var paused: bool = false
var speed: float = 1.0
var _flights: Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func show_soul(origin: Vector2, target: Vector2, amount: int) -> void:
	_flights.append({"from": origin, "to": target, "amount": amount, "age": 0.0})
	while _flights.size() > 16:
		_flights.pop_front()
	queue_redraw()

func _process(delta: float) -> void:
	if paused or _flights.is_empty():
		return
	for flight in _flights:
		flight.age += delta * speed
	for i in range(_flights.size() - 1, -1, -1):
		if float(_flights[i].age) > 0.9:
			_flights.remove_at(i)
	queue_redraw()

func _draw() -> void:
	var font: Font = ThemeDB.fallback_font
	for flight in _flights:
		var t: float = clampf(float(flight.age) / 0.9, 0.0, 1.0)
		var alpha: float = 1.0 - t * t
		var start: Vector2 = flight.from
		var color := Color(0.60, 0.85, 0.79, alpha)
		if int(flight.amount) == 0:
			for i in range(5):
				var direction := Vector2.from_angle(i * TAU / 5.0 - PI * 0.5)
				var point: Vector2 = start + direction * (4 + t * 30)
				draw_line(point - direction * 3, point + direction * 3, Color(0.53, 0.59, 0.65, alpha), 2, true)
			draw_string(font, start + Vector2(-43, -20 - t * 10), "Душа рассыпалась", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.70, 0.75, alpha))
			continue
		var eased: float = 1.0 - pow(1.0 - t, 2)
		var point: Vector2 = start.lerp(flight.to, eased) + Vector2(0, -sin(t * PI) * 55)
		draw_circle(point, 10 - t * 5, Color(color, alpha * 0.12))
		draw_circle(point, 4 - t, color)
		draw_line(point + Vector2(0, 4), point + Vector2(-8, 15) * (1.0 - t), color, 2, true)
		if int(flight.amount) > 1:
			draw_circle(point + Vector2(9, 7), 3, color)
		draw_string(font, point + Vector2(10, -8), "+%d" % int(flight.amount), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)

extends SceneTree
## Navigation regressions. Run in an isolated project copy; no personal saves.
const SkillMap = preload("res://scripts/run_skill_map.gd")
const Catalog = preload("res://scripts/run_skill_catalog.gd")
const MainScene = preload("res://scenes/main.tscn")
class IsolatedMain:
	extends "res://scripts/main.gd"
	var saved: Dictionary = {}
	func _read_json(path: String) -> Dictionary:
		return saved.get(path, {"tutorial_skipped": true} if path.ends_with("profile.json") else {}).duplicate(true)
	func _write_json(path: String, data: Dictionary) -> void:
		saved[path] = data.duplicate(true)
var checks: int = 0
var failures: Array[String] = []
var capture_dir: String = ""
var chosen: int = 0

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()

func _expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		print("FAIL: " + message)

func _frames() -> void:
	for _frame in range(6):
		await process_frame

func _finish(map) -> void:
	for _frame in range(240):
		if not map.is_processing():
			break
		map._process(1.0 / 60.0)
	_expect(not map.is_processing(), "Camera stops processing after settling")

func _world(map, point: Vector2) -> Vector2:
	return (point - map.size * 0.5 - map.pan) / map.zoom

func _mouse(map, button: MouseButton, pressed: bool, at: Vector2, factor: float = 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = at
	event.factor = factor
	map._gui_input(event)

func _touch(map, index: int, pressed: bool, point: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = point
	map._gui_input(event)

func _navigation(map) -> void:
	var at := Vector2(235, 170)
	map.restore_camera(0.6, Vector2(17, -24))
	_expect(is_equal_approx(map.zoom, 0.6) and map.pan == Vector2(17, -24), "Restore is immediate and exact")
	var world: Vector2 = _world(map, at)
	map.zoom_by(1.5, at)
	_expect(is_equal_approx(map.zoom, 0.6), "Zoom request does not jump the rendered scale")
	map._process(1.0 / 60.0)
	_expect(map.zoom > 0.6 and map.zoom < 0.9, "First frame contains an intermediate scale")
	_expect(_world(map, at).distance_to(world) < 0.01, "Cursor anchor remains stationary during interpolation")
	_finish(map)
	_expect(absf(map.zoom - 0.9) < 0.0001, "Zoom reaches requested scale")
	_expect(_world(map, at).distance_to(world) < 0.01, "Cursor anchor remains stationary at destination")
	map.restore_camera(0.6, Vector2.ZERO)
	map.zoom_by(1.1, at)
	map.zoom_by(1.1, at)
	map.zoom_by(1.1, at)
	_finish(map)
	_expect(absf(map.zoom - 0.6 * pow(1.1, 3)) < 0.0001, "Rapid wheel input accumulates rather than losing notches")
	map.restore_camera(0.6, Vector2.ZERO)
	map.zoom_by(1.5, at)
	map._process(1.0 / 60.0)
	var before: float = map.zoom
	map.zoom_by(1.0 / 1.5, at)
	_expect(is_equal_approx(map.zoom, before), "Direction change never snaps rendered camera")
	map._process(1.0 / 60.0)
	_expect(map.zoom < before, "Reversing zoom responds on the next frame")
	_finish(map)
	map.restore_camera(0.6, Vector2.ZERO)
	map.zoom_by(1.5, at)
	for _frame in range(6):
		map._process(1.0 / 30.0)
	var z30: float = map.zoom
	var p30: Vector2 = map.pan
	map.restore_camera(0.6, Vector2.ZERO)
	map.zoom_by(1.5, at)
	for _frame in range(24):
		map._process(1.0 / 120.0)
	_expect(absf(map.zoom - z30) < 0.0001 and map.pan.distance_to(p30) < 0.01, "Equal elapsed time at 30 and 120 fps gives equal camera position")
	map.restore_camera(0.6, Vector2.ZERO)
	_mouse(map, MOUSE_BUTTON_WHEEL_UP, true, at, 0.25)
	_finish(map)
	var fine: float = map.zoom
	map.restore_camera(0.6, Vector2.ZERO)
	_mouse(map, MOUSE_BUTTON_WHEEL_UP, true, at, 1.0)
	_finish(map)
	var full: float = map.zoom
	_expect(fine > 0.6 and fine < full, "High precision wheel factor produces a smaller continuous change")
	map.restore_camera(0.6, Vector2.ZERO)
	_mouse(map, MOUSE_BUTTON_WHEEL_UP, true, at, 0.0)
	_finish(map)
	_expect(absf(map.zoom - full) < 0.0001, "Unsupported wheel factor zero uses one ordinary notch")
	map.restore_camera(0.6, Vector2.ZERO)
	map.zoom_by(1.5, at)
	map._process(1.0 / 60.0)
	before = map.zoom
	var old_pan: Vector2 = map.pan
	_mouse(map, MOUSE_BUTTON_LEFT, true, at)
	var move := InputEventMouseMotion.new()
	move.position = at + Vector2(30, 12)
	move.relative = Vector2(30, 12)
	map._gui_input(move)
	_mouse(map, MOUSE_BUTTON_LEFT, false, move.position)
	_expect(is_equal_approx(map.zoom, before), "Drag interrupts zoom at the displayed scale")
	_expect(map.pan.distance_to(old_pan + move.relative) < 0.01, "Drag follows pointer directly without easing delay")
	_expect(chosen == 0, "Dragging does not select a node")
	_finish(map)
	_expect(is_equal_approx(map.zoom, before), "Interrupted zoom does not resume after drag")
	map.restore_camera(0.6, Vector2(17, -24))
	world = _world(map, Vector2(200, 100))
	_touch(map, 0, true, Vector2(100, 100))
	_touch(map, 1, true, Vector2(300, 100))
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = Vector2(80, 120)
	drag.relative = Vector2(-20, 20)
	map._gui_input(drag)
	_finish(map)
	_expect(_world(map, Vector2(190, 110)).distance_to(world) < 0.02, "Pinch scales at midpoint and translates that midpoint once")
	_touch(map, 0, false, Vector2(80, 120))
	_touch(map, 1, false, Vector2(300, 100))
	_expect(chosen == 0, "Pinch release does not select a node")
	map.restore_camera(0.7321, Vector2(37, -81))
	map.configure(Catalog.all_skills())
	_expect(is_equal_approx(map.zoom, 0.7321) and map.pan == Vector2(37, -81), "Refreshing skill data preserves intermediate scale and pan")
	map.set_zoom(0.876543, Vector2(-1, -1), false)
	_expect(absf(map.zoom - 0.876543) < 0.00001, "Arbitrary zoom is preserved without preset quantization")
	map.set_zoom(SkillMap.MAX_ZOOM * 3, Vector2(-1, -1), false)
	_expect(is_equal_approx(map.zoom, SkillMap.MAX_ZOOM), "Upper zoom bound is enforced")
	map.set_zoom(SkillMap.MIN_ZOOM * 0.1, Vector2(-1, -1), false)
	_expect(is_equal_approx(map.zoom, SkillMap.MIN_ZOOM), "Lower zoom bound is enforced")
	map.restore_camera(0.7321, Vector2(37, -81))
	var id: String = str(Catalog.all_skills()[10].id)
	map.set_selection(id, true)
	_expect(is_equal_approx(map.zoom, 0.7321) and map.pan == Vector2(37, -81), "Focus request does not teleport")
	_finish(map)
	var node: Dictionary = map._by_id[id]
	_expect(map._screen(node.position).distance_to(map.size * 0.5) < 0.02, "Focus finishes centered on requested skill")
	var position: Vector2 = map.pan
	before = map.zoom
	map.reset_center()
	_expect(map.pan == position, "Center request starts smoothly")
	_finish(map)
	_expect(map.pan.length() < 0.02, "Center reaches the root")
	_expect(is_equal_approx(map.zoom, before), "Center preserves the chosen zoom rather than forcing a preset")
	before = map.zoom
	map.fit_all()
	_expect(is_equal_approx(map.zoom, before), "Fit all starts smoothly after initial layout")
	_finish(map)
	for n in map.nodes:
		_expect(Rect2(Vector2.ZERO, map.size).has_point(map._screen(n.position)), "Fit all includes node " + str(n.id))

func _capture(name: String) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	_expect(picture.save_png(capture_dir.path_join(name + ".png")) == OK, "Saved " + name)

func _controls(node: Node) -> Array[Control]:
	var found: Array[Control] = []
	if node is Control and node.is_visible_in_tree():
		found.append(node)
	for child in node.get_children():
		found.append_array(_controls(child))
	return found

func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = code
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func _integration() -> void:
	var ui = MainScene.instantiate()
	ui.set_script(IsolatedMain)
	root.add_child(ui)
	ui.set_process(false)
	ui.sound_on = false
	await _frames()
	ui._begin_run()
	ui.set_process(false)
	for extent in [Vector2i(1280, 800), Vector2i(390, 844), Vector2i(320, 600)]:
		root.size = extent
		ui._apply_screen_layout()
		ui._close_modal()
		ui.run_skill_camera.clear()
		ui.paused = false
		ui._show_talents()
		await _frames()
		var map = ui.modal.map
		_finish(map)
		_expect(map.nodes.size() == 125, "124 skills and root remain visible in data")
		_expect(ui.paused, "Skill map pauses the game")
		var visible: Rect2 = ui.get_viewport_rect()
		_expect(visible.encloses(ui.modal.get_global_rect()), "Modal fits " + str(extent))
		_expect(visible.encloses(map.get_global_rect()), "Map fits " + str(extent))
		var slider: HSlider
		for control in _controls(ui.modal._map_frame):
			if control is HSlider:
				slider = control
			if control is BaseButton or control is HSlider:
				_expect(visible.encloses(control.get_global_rect()), "Navigation control fits " + str(extent))
		_expect(is_instance_valid(slider), "Continuous slider is available at " + str(extent))
		if is_instance_valid(slider):
			_expect(slider.step == 0, "Slider has no fixed mouse step")
			slider.value = 0.54321
			var expected: float = exp(lerpf(log(SkillMap.MIN_ZOOM), log(SkillMap.MAX_ZOOM), slider.value))
			_expect(absf(map.zoom - expected) < 0.0001, "Slider sets an arbitrary exact scale without easing lag")
			_expect(not map.is_processing(), "Direct slider adjustment leaves no stale animation")
			slider.grab_focus()
			var old_value: float = slider.value
			_key(KEY_RIGHT)
			_expect(absf(slider.value - old_value - 0.01) < 0.00001, "Right arrow moves slider by one fine step")
			_expect(root.gui_get_focus_owner() == slider, "Right arrow keeps focus in slider")
			_key(KEY_LEFT)
			_expect(absf(slider.value - old_value) < 0.00001, "Left arrow reverses slider by one fine step")
			var wheel := InputEventMouseButton.new()
			wheel.button_index = MOUSE_BUTTON_WHEEL_UP
			wheel.position = slider.get_global_rect().get_center()
			wheel.global_position = wheel.position
			wheel.pressed = true
			wheel.factor = 0.25
			root.push_input(wheel)
			_finish(map)
			_expect(slider.value > old_value and slider.value - old_value < 0.1, "Wheel over slider does not jump across the range")
		map.restore_camera(0.7321, Vector2(37, -81))
		map.zoom_by(1.4)
		map._process(1.0 / 60.0)
		var saved_zoom: float = map.zoom
		var saved_pan: Vector2 = map.pan
		ui._close_modal()
		_expect(not ui.paused, "Closing restores previous unpaused state")
		ui._show_talents()
		await _frames()
		map = ui.modal.map
		_expect(absf(map.zoom - saved_zoom) < 0.0001 and map.pan.distance_to(saved_pan) < 0.01, "Reopening restores rendered camera mid-animation")
		map.fit_all()
		_finish(map)
		await _frames()
		await _capture("skills-" + str(extent.x))
		if extent.x >= 390:
			ui.modal._focus("traps_mechanisms_2")
			_finish(map)
			await _frames()
			_expect(ui.modal.selected_id == "traps_mechanisms_2" and ui.modal._title.text == "Механизмы II", "Focus updates selected skill details")
			await _capture("skills-focus-" + str(extent.x))
	ui.free()
	await _frames()

func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	var map = SkillMap.new()
	map.size = Vector2(900, 620)
	map.configure([])
	root.add_child(map)
	await _frames()
	_expect(not map._initialized, "Empty snapshot does not initialize camera against root-only bounds")
	map.configure(Catalog.all_skills())
	await _frames()
	_expect(map._initialized and not map.is_processing(), "First populated layout fits immediately")
	for node in map.nodes:
		_expect(Rect2(Vector2.ZERO, map.size).has_point(map._screen(node.position)), "Initial fit includes " + str(node.id))
	map.node_selected.connect(func(_id): chosen += 1)
	_navigation(map)
	map.free()
	await _integration()
	print("SKILL CAMERA: %d checks, %d failures; renderer=%s" % [checks, failures.size(), DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)

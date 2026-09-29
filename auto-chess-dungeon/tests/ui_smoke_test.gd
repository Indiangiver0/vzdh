extends SceneTree
## Real scene and callbacks, with persistence isolated in memory for the test.

const MainScene = preload("res://scenes/main.tscn")

class TestMain:
	extends "res://scripts/main.gd"
	var saved: Dictionary = {}

	func _read_json(_path: String) -> Dictionary:
		return {}

	func _write_json(path: String, data: Dictionary) -> void:
		saved[path] = data.duplicate(true)


var checks: int = 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _layout_ready() -> void:
	await process_frame
	await process_frame
	await process_frame


func _run() -> void:
	root.size = Vector2i(1280, 800)
	var ui = MainScene.instantiate()
	ui.set_script(TestMain)
	root.add_child(ui)
	ui.set_process(false)
	ui.sound_on = false
	ui.game.restart(7319)
	ui._refresh()
	await _layout_ready()
	_expect(ui.game.phase == "prepare" and is_instance_valid(ui.page), "Main scene creates preparation UI")
	_check_layout(ui, "one hero")

	ui._select_shop("goblin")
	_expect(ui.selected_room == "goblin", "Shop callback selects room")
	ui._slot_clicked(0)
	_expect(ui.game.rooms[0].get("id") == "goblin" and ui.game.gold == 15, "Slot callback purchases selected room")
	ui._cancel_selection()
	ui._slot_clicked(0)
	_expect(ui.selected_slot == 0, "Built-room callback selects inspector target")
	ui._upgrade()
	_expect(ui.game.rooms[0]["rank"] == 2, "Inspector callback upgrades selected room")
	ui._select_shop("goblin")
	ui._slot_clicked(1)
	_expect(ui.selected_room.is_empty(), "Exhausted shop stock clears placement mode")
	ui.game.gold = 200
	ui._buy_floor()
	_expect(ui.game.floor_count == 2 and ui.game.rooms.size() == 10, "Floor callback adds five build slots")
	ui._slot_clicked(0)
	ui._slot_clicked(9)
	_expect(ui.game.rooms[0].is_empty() and ui.game.rooms[9]["rank"] == 2, "Slot callbacks move upgraded room to another floor")
	ui._slot_clicked(9)
	ui._slot_clicked(1)
	_expect(ui.game.rooms[9]["rank"] == 1 and ui.game.rooms[1]["rank"] == 2, "Slot callbacks swap occupied rooms")
	ui._slot_clicked(9)
	ui._sell()
	_expect(ui.game.rooms[9].is_empty() and ui.selected_slot == -1, "Sell callback clears room and selection")
	ui.game.lord["hp"] = 50
	ui._heal()
	_expect(ui.game.lord["hp"] == 80, "Heal callback applies current lord heal")
	ui._set_speed(4)
	_expect(ui.speed == 4 and ui.saved["user://settings.json"]["speed"] == 4, "Speed callback applies and persists selected speed")
	ui._toggle_sound()
	_expect(ui.sound_on and ui.saved["user://settings.json"]["sound"], "Sound callback applies and persists setting")
	ui.sound_on = false
	ui._show_help()
	_expect(is_instance_valid(ui.modal), "Help callback creates modal")
	ui._close_modal()
	_expect(not is_instance_valid(ui.modal), "Close callback removes help modal")

	ui.game.lord["hp"] = 100000
	ui.game.lord["max_hp"] = 100000
	ui.game.lord["damage"] = 100000
	ui.game.lord["xp"] = 100
	ui._start()
	_expect(ui.game.phase == "raid" and ui.selected_slot == -1 and ui.selected_room.is_empty(), "Start callback starts raid and clears selection")
	ui._show_help()
	_expect(ui.paused and is_instance_valid(ui.modal), "Opening help during raid pauses simulation")
	var space_event = InputEventKey.new()
	space_event.keycode = KEY_SPACE
	space_event.pressed = true
	ui._input(space_event)
	_expect(ui.paused, "Space cannot resume a raid behind an open help modal")
	ui._close_modal()
	var initial_tick: int = ui.game.tick
	ui._process(2.0)
	_expect(ui.game.tick == initial_tick, "Paused UI process does not advance battle")
	ui._toggle_pause()
	ui._process(0.125)
	_expect(ui.game.current_slot >= 0, "Speed-four UI process advances a half-second simulation tick")
	var safety: int = 0
	while ui.game.phase == "raid" and safety < 1000:
		ui._process(0.125)
		safety += 1
	_expect(safety < 1000 and ui.game.phase == "result", "UI process drives complete raid to result")
	_expect(is_instance_valid(ui.modal), "Completed raid displays result modal")
	_expect(ui.saved.has("user://profile.json") and ui.profile["wave"] == 1, "Result callback records run progress through persistence interface")
	ui._next_wave()
	_expect(ui.game.phase == "level_up" and is_instance_valid(ui.modal), "Continue callback displays earned level choices")
	var pending: int = ui.game.pending_upgrades
	for _choice in range(pending):
		ui._choose_upgrade("trap")
	_expect(ui.game.phase == "prepare" and ui.game.upgrades["trap"] == pending and not is_instance_valid(ui.modal), "Upgrade callbacks resolve all choices and return to preparation")
	ui._restart()
	_expect(ui.game.wave == 1 and ui.game.gold == 18 and ui.game.rooms.size() == 5 and ui.profile["wave"] == 1, "Restart callback resets run and preserves record")

	ui.game.wave = 8
	ui.game._generate_party()
	ui.game.gold = 500
	ui.game.buy_floor()
	ui.game.buy_floor()
	ui._refresh()
	await _layout_ready()
	_expect(ui.game.heroes.size() == 3 and ui.game.rooms.size() == 15, "Main scene renders three heroes and three floors")
	_check_layout(ui, "three heroes")
	_expect(ui.floor_scroll.get_v_scroll_bar().max_value > ui.floor_scroll.size.y, "Additional floors have vertical scrolling")
	root.size = Vector2i(1280, 720)
	await _layout_ready()
	_check_layout(ui, "three heroes at 1280x720")
	root.size = Vector2i(
		int(ProjectSettings.get_setting("display/window/size/min_width", 1100)),
		int(ProjectSettings.get_setting("display/window/size/min_height", 720))
	)
	await _layout_ready()
	_check_layout(ui, "configured minimum window")
	ui.free()
	await process_frame
	if failures.is_empty():
		print("PASS: %d UI integration checks" % checks)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL: %d of %d UI integration checks failed" % [failures.size(), checks])
		quit(1)


func _check_layout(ui, scenario: String) -> void:
	var minimum: Vector2 = ui.page.get_combined_minimum_size()
	var viewport_size: Vector2 = ui.get_viewport_rect().size
	print("LAYOUT %s: page minimum=%s logical viewport=%s window=%s" % [scenario, minimum, viewport_size, root.size])
	_expect(minimum.x <= viewport_size.x - 40.0, "%s fits horizontal viewport" % scenario)
	_expect(minimum.y <= viewport_size.y - 40.0, "%s keeps shop and footer within vertical viewport" % scenario)

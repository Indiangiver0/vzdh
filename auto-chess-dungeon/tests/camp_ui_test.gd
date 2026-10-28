extends SceneTree
## Real Main scene with synthetic camp fixtures; persistence stays in memory.
## Run only in an isolated project copy; optional --capture-dir=<absolute path>.
const MainScene = preload("res://scenes/main.tscn")
const SEED = 20261027
const NEW_SKILLS = ["shared_restless_dungeons_1", "shared_restless_dungeons_2", "shared_restless_dungeons_3", "poison_caustic_vapors"]
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
var ui
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	_run.call_deferred()
func _expect(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		print("FAIL: " + description)
func _settle() -> void:
	for _frame in range(6):
		await process_frame
func _settle_skill_camera(map: Control) -> void:
	# Focus now animates; wait for its completion instead of assuming six frames.
	var deadline: int = Time.get_ticks_msec() + 3000
	while map.is_processing() and Time.get_ticks_msec() < deadline:
		await process_frame
	_expect(not map.is_processing(), "Skill camera finishes its focus transition")

func _key(code: Key, physical: bool = false, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.pressed = true
	event.echo = echo
	if physical:
		event.physical_keycode = code
	else:
		event.keycode = code
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
func _mouse_click(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.global_position = point
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)
func _rapid_windows() -> void:
	_fixture()
	var gold: int = ui.game.gold
	for _repeat in range(3):
		ui._show_help()
		ui._modal_back()
		ui._show_party()
		ui._modal_back()
		ui._show_settings()
		ui._modal_back()
	await _settle()
	_expect(not is_instance_valid(ui.modal) and ui.game.gold == gold, "Rapid modal open/close leaves no stale focus target; engine log must be clean")
func _fixture() -> void:
	ui._close_modal()
	ui.menu_open = false
	ui.has_run = true
	ui.paused = false
	ui.speed = 1
	ui.accumulator = 0.0
	ui.message = ""
	ui.remembered_scrolls.clear()
	ui.run_skill_camera.clear()
	ui.talent_tree_focus = "root"
	ui.game.restart(SEED)
	ui.game.wave = 25
	ui.game._generate_party()
	ui.game.gold = 1000
	ui.game.shop = {"goblin": 1}
	_expect(ui.game.buy_room(0, "goblin").is_empty(), "Fixture buys occupied floor")
	_expect(ui.game.start_raid().is_empty(), "Fixture starts actual wave")
	for i in range(ui.game.heroes.size()):
		ui.game.heroes[i].max_hp = 100
		ui.game.heroes[i].hp = 10 + i * 10
		ui.game.heroes[i].effects = {}
	ui.game._start_camp(0)
	ui._refresh()
func _hp() -> Array:
	var result: Array = []
	for hero in ui.game.heroes:
		result.append(int(hero.hp))
	return result
func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_descendants(child))
	return result
func _e_button() -> Button:
	for node in _descendants(ui.page):
		if node is Button and node.text.begins_with("E ·"):
			return node
	return null
func _view_events(kind: String) -> int:
	var count: int = 0
	for item in ui.dungeon_view._events:
		if str(item.event.get("kind", "")) == kind:
			count += 1
	return count
func _time_checks() -> void:
	for multiplier in [1, 2, 4]:
		_fixture()
		ui._set_speed(multiplier)
		var tick: int = ui.game.tick
		var combat_tick: int = ui.game.combat_tick
		_expect(ui.game.phase == "camp" and ui.game.camp_status().duration == 10, "x%d camp begins with ten seconds" % multiplier)
		_expect(_hp() == [10, 20, 30, 40, 50], "x%d no immediate healing" % multiplier)
		_expect(_view_events("camp_start") == 1, "x%d camp_start reaches view once" % multiplier)
		ui._process(0.5 / multiplier)
		_expect(_hp() == [10, 20, 30, 40, 50] and is_equal_approx(ui.game.camp_status().elapsed, 0.5), "x%d first half-second has no healing" % multiplier)
		ui._process(0.5 / multiplier)
		_expect(_hp() == [15, 25, 35, 45, 55], "x%d first healing occurs at one game second" % multiplier)
		_expect(_view_events("camp_heal") == 5, "x%d five healing events reach view before next advance" % multiplier)
		var event_count: int = ui.dungeon_view._events.size()
		ui.dungeon_view.refresh_runtime()
		_expect(ui.dungeon_view._events.size() == event_count, "x%d refresh does not replay events" % multiplier)
		for _second in range(8):
			ui._process(1.0 / multiplier)
		_expect(ui.game.phase == "camp" and _hp() == [55, 65, 75, 85, 95], "x%d camp remains after nine seconds" % multiplier)
		ui._process(1.0 / multiplier)
		_expect(ui.game.phase == "raid" and _hp() == [60, 70, 80, 90, 100], "x%d ten seconds restore at most fifty percent" % multiplier)
		_expect(ui.game.tick == tick and ui.game.combat_tick == combat_tick and ui.accumulator == 0.0, "x%d camp never advances battle clock or carries elapsed time" % multiplier)
		_expect(_view_events("camp_end") == 1, "x%d completion event reaches view" % multiplier)
	_fixture()
	ui._cycle_speed()
	_expect(ui.speed == 2, "Speed control cycles x1 to x2")
	ui._cycle_speed()
	_expect(ui.speed == 4, "Speed control cycles x2 to x4")
	ui._cycle_speed()
	_expect(ui.speed == 1, "Speed control cycles x4 to x1")
func _pause_checks() -> void:
	for paused_before in [false, true]:
		for window in ["menu", "help", "settings", "talents", "party"]:
			_fixture()
			ui.paused = paused_before
			var gold: int = ui.game.gold
			match window:
				"menu": ui._open_menu()
				"help": ui._show_help()
				"settings": ui._show_settings()
				"talents": ui._show_talents()
				"party": ui._show_party()
			await _settle()
			if window in ["help", "settings", "party"]:
				var focus: Control = root.gui_get_focus_owner()
				_expect(is_instance_valid(focus) and focus is Button and focus.text == "Назад" and focus.is_inside_tree(), window + " focuses its live Back button")
			ui._process(20.0)
			_expect(ui.game.phase == "camp" and ui.game.camp_status().elapsed == 0.0 and _hp() == [10, 20, 30, 40, 50], "%s freezes camp with prior pause %s" % [window, paused_before])
			_key(KEY_E, true)
			_key(KEY_SPACE)
			_expect(ui.game.gold == gold and ui.game.phase == "camp", "%s blocks physical E and space through window" % window)
			if window == "menu":
				ui._resume_run()
			else:
				ui._modal_back()
			_expect(ui.paused == paused_before, "%s restores prior pause %s" % [window, paused_before])
	_fixture()
	_key(KEY_SPACE)
	ui._process(20.0)
	_expect(ui.paused and ui.game.camp_status().elapsed == 0.0, "Space pauses camp")
	var gold: int = ui.game.gold
	var cost: int = ui.game.camp_interrupt_cost()
	var charges: int = ui.game.ability_charges
	_key(KEY_E, true)
	_expect(ui.paused and ui.game.phase == "raid" and ui.game.gold == gold - cost, "Physical E with empty logical keycode interrupts on pause")
	_expect(ui.game.ability_charges == charges, "E preserves Q charges")
	_key(KEY_E, true)
	_expect(ui.game.gold == gold - cost and ui.game._camp_interruptions == 1, "Immediate second E does not charge twice")
	_expect(_view_events("camp_interrupt") == 1 and _view_events("camp_end") == 1, "Interrupt and end reach view exactly once")
func _price_checks() -> void:
	_fixture()
	ui.game._ability_income_snapshot = 21
	ui._refresh_camp_values()
	var button: Button = _e_button()
	_expect(is_instance_valid(button) and button.text.contains("6 зол.") and not button.disabled, "E button shows ceil of first 25 percent")
	ui.game.gold = 5
	ui._refresh_camp_values()
	_expect(button.disabled and button.tooltip_text.contains("Не хватает золота"), "E button reports insufficient gold")
	_key(KEY_E, true)
	_expect(ui.game.gold == 5 and ui.game._camp_interruptions == 0 and ui.game.phase == "camp", "Rejected E leaves gold and first price unchanged")
	ui.game.gold = 100
	ui._refresh_camp_values()
	_key(KEY_E, true, true)
	_expect(ui.game.gold == 100 and ui.game.phase == "camp", "Keyboard repeat does not interrupt")
	ui._process(1.0)
	var healed: Array = _hp()
	_key(KEY_E, true)
	_expect(ui.game.gold == 94 and _hp() == healed, "Successful E retains healing already received")
	for count in range(2, 7):
		ui.game._start_camp(0) # Synthetic later camp; route eligibility belongs to combat suite.
		ui._refresh()
		button = _e_button()
		_expect(button.text.contains("11 зол.") and not button.disabled, "Later E %d displays fixed ceil fifty percent" % count)
		var before: int = ui.game.gold
		_key(KEY_E, true)
		_expect(ui.game.gold == before - 11 and ui.game._camp_interruptions == count, "Successful E %d has no charge cap" % count)
		_key(KEY_E, true)
		_expect(ui.game.gold == before - 11, "Duplicate E %d stays free" % count)
	_fixture()
	ui.game._ability_income_snapshot = 1
	_expect(ui.game.camp_interrupt_cost() == 1, "Minimum first E is one gold")
	ui.game._camp_interruptions = 3
	_expect(ui.game.camp_interrupt_cost() == 1, "Minimum later E is one gold")
	for hero in ui.game.heroes:
		hero.hp = hero.max_hp
	ui._refresh_camp_values()
	var gold: int = ui.game.gold
	button = _e_button()
	_expect(button.disabled and button.tooltip_text.contains("нет доступного лечения"), "E button disables when no healing remains")
	_key(KEY_E, true)
	_expect(ui.game.gold == gold and ui.game._camp_interruptions == 3, "No-healing E does not spend gold or increment counter")
func _capture(name: String) -> void:
	if capture_dir.is_empty():
		return
	await _settle()
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	_expect(not picture.is_empty() and picture.get_size() == root.size, name + " has exact viewport pixels")
	var error: Error = picture.save_png(capture_dir.path_join(name + ".png"))
	_expect(error == OK, name + " PNG saved")
	print("CAPTURE " + name + " " + str(picture.get_size()))
func _layout_checks() -> void:
	for dimensions in [Vector2i(1280, 800), Vector2i(390, 844)]:
		root.size = dimensions
		ui._apply_screen_layout()
		_fixture()
		ui.paused = true
		ui._refresh()
		await _settle()
		var suffix: String = "%dx%d" % [dimensions.x, dimensions.y]
		var viewport: Rect2 = ui.get_viewport_rect()
		var button: Button = _e_button()
		_expect(is_instance_valid(button) and viewport.encloses(button.get_global_rect()), suffix + " camp E is fully on screen")
		_expect(ui.page.get_combined_minimum_size().x <= viewport.size.x and ui.page.get_combined_minimum_size().y <= viewport.size.y, suffix + " main page fits viewport")
		_expect(ui.game.heroes.size() == 5 and ui.game.wave_title.contains("Клятва пяти"), suffix + " boss name and five heroes available")
		await _capture("camp-" + suffix)
		if ui.compact_ui:
			ui._show_party()
			await _settle()
			var overview: GridContainer
			for node in _descendants(ui.modal):
				if node is GridContainer and node.has_meta("party_overview"):
					overview = node
			_expect(is_instance_valid(overview) and overview.columns == 3 and overview.get_child_count() == 5, "Phone overview places five heroes in 3+2 grid")
			if is_instance_valid(overview):
				for i in range(5):
					var found: bool = false
					for node in _descendants(overview.get_child(i)):
						if node is Label and node.text == "%d / 100 HP" % (10 + i * 10):
							found = viewport.encloses(node.get_global_rect()) and ui.modal_scroll.get_global_rect().encloses(node.get_global_rect())
					_expect(found, "Phone overview has visible individual HP %d" % i)
			await _capture("party-" + suffix)
			ui._modal_back()
		else:
			var party_scroll: ScrollContainer = ui.live_scrolls["party"]
			for i in range(5):
				var hp_label: Label
				for node in _descendants(ui.page):
					if node is Label and node.text.begins_with("%d/100 HP" % (10 + i * 10)):
						hp_label = node
				_expect(is_instance_valid(hp_label), "Desktop scrollable party exposes individual HP %d" % i)
				if is_instance_valid(hp_label):
					party_scroll.ensure_control_visible(hp_label)
					await _settle()
					_expect(viewport.encloses(hp_label.get_global_rect()) and party_scroll.get_global_rect().encloses(hp_label.get_global_rect()), "Desktop scrolling brings individual HP %d into view" % i)
					await _capture("party-hero-%d-" % (i + 1) + suffix)
		var gold_before_click: int = ui.game.gold
		var e_cost: int = ui.game.camp_interrupt_cost()
		_mouse_click(_e_button().get_global_rect().get_center())
		_expect(ui.game.phase == "raid" and ui.game.gold == gold_before_click - e_cost, suffix + " actual pointer click activates E button once")
		_fixture()
		ui.paused = true
		ui._refresh()
		await _settle()
		var behind_e: Vector2 = _e_button().get_global_rect().get_center()
		var camp_gold: int = ui.game.gold
		ui._show_talents()
		await _settle()
		_mouse_click(behind_e)
		_expect(ui.game.phase == "camp" and ui.game.gold == camp_gold, suffix + " modal blocks pointer click through to E")
		_expect(ui.modal._nodes.size() == 124 and ui.modal.map.nodes.size() == 125, suffix + " displays 124 skills plus visual root")
		_expect(viewport.encloses(ui.modal.get_global_rect()) and viewport.encloses(ui.modal._buy.get_global_rect()), suffix + " skill screen and action fit viewport")
		ui.modal.map.fit_all()
		await _capture("tree-" + suffix)
		for id in NEW_SKILLS:
			_expect(ui.modal._by_id.has(id) and ui.modal.map._by_id.has(id), suffix + " new skill on map " + id)
			ui.modal._select(id)
			ui.modal.map.set_selection(id, true)
			await _settle_skill_camera(ui.modal.map)
			await _settle()
			_expect(ui.modal._title.text == ui.game.run_skill_state(id).name and ui.modal._buy.disabled, suffix + " selected skill has real title and camp purchase locked " + id)
			var node: Dictionary = ui.modal.map._by_id[id]
			_expect(Rect2(Vector2.ZERO, ui.modal.map.size).has_point(ui.modal.map._screen(node.position)), suffix + " focused new skill is visible " + id)
			if id == NEW_SKILLS[0] or id == NEW_SKILLS[3]:
				await _capture(id + "-" + suffix)
		ui._modal_back()
		_expect(ui.paused, suffix + " closing tree keeps user pause")
func _narrow_header_checks() -> void:
	root.size = Vector2i(320, 600)
	ui._apply_screen_layout()
	_fixture()
	ui.paused = true
	ui._refresh()
	await _settle()
	var viewport: Rect2 = ui.get_viewport_rect()
	var wallet: Button = ui.skill_wallet_button
	_expect(viewport.encloses(wallet.get_global_rect()) and wallet.text == "Навыки\n0", "320x600 wallet keeps the skill name and count on two lines")
	var heading: Control = ui.page.get_child(0)
	_expect(viewport.encloses(heading.get_global_rect()), "320x600 header fits viewport")
	for child in heading.get_children():
		_expect(viewport.encloses(child.get_global_rect()), "320x600 header item stays within viewport")
	_expect(viewport.encloses(_e_button().get_global_rect()), "320x600 E button remains accessible")
	await _capture("camp-320x600")
func _run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 800)
	ui = MainScene.instantiate()
	ui.set_script(IsolatedMain)
	root.add_child(ui)
	ui.set_process(false)
	ui.sound_on = false
	await _settle()
	ui._begin_run()
	ui.set_process(false)
	_time_checks()
	await _pause_checks()
	await _rapid_windows()
	_price_checks()
	await _layout_checks()
	await _narrow_header_checks()
	ui.free()
	await _settle()
	print("CAMP UI: %d checks, %d failures; seed=%d; renderer=%s" % [checks, failures.size(), SEED, DisplayServer.get_name()])
	quit(0 if failures.is_empty() else 1)

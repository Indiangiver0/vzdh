extends SceneTree
## Focused regression checks for the progression trees. Saves stay in memory.

const Game = preload("res://scripts/dungeon_game.gd")
const MainScene = preload("res://scenes/main.tscn")
const DungeonView = preload("res://scripts/dungeon_view.gd")

class IsolatedMain:
	extends "res://scripts/main.gd"

	func _load_local() -> void:
		sound_on = false

	func _save_profile() -> void:
		pass

	func _save_settings() -> void:
		pass

	func _read_json(_path: String) -> Dictionary:
		return {}

	func _write_json(_path: String, _data: Dictionary) -> void:
		pass

var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _model() -> RefCounted:
	var game = Game.new()
	game.restart(20261020)
	game.gold = 100000
	game.shop = {"goblin": 5, "poison": 5, "mimic": 5}
	return game

func _node(nodes: Array[Dictionary], effect: String) -> Dictionary:
	for node in nodes:
		if str(node.get("effect_id", node.get("id", ""))) == effect:
			return node
	return {}

func _available(nodes: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in nodes:
		if bool(node.get("can_buy", false)):
			result.append(node)
	return result

func _snapshot(game: RefCounted) -> Array:
	return [
		game.rooms.duplicate(true), game.lord.duplicate(true),
		game.selected_talents.duplicate(true), game.gold, game.phase,
		game.rng.state, game.talent_rng.state,
		game.expedition_rng.state, game.deal_rng.state,
		game.logs.duplicate(),
	]

func _check_room_model() -> void:
	var game = _model()
	_expect(game.buy_room(0, "goblin").is_empty(), "Build a room through the model")
	_expect(_available(game.room_tree(0)).is_empty(), "Rank 1 has no selectable specialization")
	_expect(game.upgrade_room(0).is_empty(), "First paid rank upgrade succeeds")
	var first: Array[Dictionary] = _available(game.room_tree(0))
	_expect(first.size() == 3 and int(first[0].rank_required) == 2, "Rank 2 exposes all three approved paths")
	var gold: int = game.gold
	_expect(game.choose_room_evolution(0, "war_banner").is_empty(), "Choose the first branch")
	_expect(game.gold == gold, "Branch choice itself does not charge gold")
	_expect(not game.choose_room_evolution(0, "saboteurs").is_empty(), "A chosen branch cannot be replaced")
	for _rank in range(3):
		game.upgrade_room(0)
	var middle: Array[Dictionary] = _available(game.room_tree(0))
	_expect(middle.size() == 1 and str(middle[0].effect_id) == "war_banner:5", "Rank 5 exposes only the chosen path's second form")
	_expect(game.choose_room_evolution(0, str(middle[0].effect_id)).is_empty(), "Choose a rank 5 continuation")
	for _rank in range(10):
		game.upgrade_room(0)
	var last: Array[Dictionary] = _available(game.room_tree(0))
	_expect(last.size() == 1 and str(last[0].effect_id) == "war_banner:15", "Rank 15 exposes only the chosen path's terminal form")
	_expect(game.choose_room_evolution(0, str(last[0].effect_id)).is_empty(), "Choose the final branch")
	var selected: Dictionary = game.rooms[0].duplicate(true)
	var tree: Array[Dictionary] = game.room_tree(0)
	_expect(game.move_room(0, 3).is_empty(), "Move an evolved room")
	_expect(game.rooms[3] == selected and game.room_tree(3) == tree, "Moving preserves instance, path, and stable graph IDs")

	var poison = _model()
	poison.buy_room(0, "poison")
	poison.upgrade_room(0)
	var prior: Array = _snapshot(poison)
	var poison_tree: Array[Dictionary] = poison.room_tree(0)
	var spores: Dictionary = _node(poison_tree, "poison_spore_garden")
	_expect(int(spores.preview.after.evolution_params.attacks_to_burst) == 3 and str(spores.preview.after.visual_key) == "poison_spore_garden", "Spore preview includes its actual trigger and changed visual form")
	_expect(str(_node(poison_tree, "poison_spore_garden:5").state) == "locked", "Later form remains locked before its rank and prerequisite")
	poison.talent_preview("lasting_poison")
	poison.room_tree(0)
	_expect(_snapshot(poison) == prior, "Tree and talent previews do not mutate gameplay state or any random stream")
	poison.choose_room_evolution(0, "poison_spore_garden")
	_expect(poison.room_stats(0) == spores.preview.after, "Poison preview matches the selected room's actual resulting stats")
	var legacy = _model()
	legacy.buy_room(0, "goblin")
	legacy.rooms[0].rank = 5
	legacy.rooms[0].specialization = "fury"
	_expect(_node(legacy.room_tree(0), "fury").state == "acquired", "Existing legacy specialization remains visible without random conversion")
	_expect(legacy.rooms[0].get("evolution_path", "") == "", "Reading a legacy tree never changes the saved room path")

func _check_talent_model() -> void:
	var game = _model()
	game.skill_points = 20
	_expect(not game.choose_talent("lasting_poison").is_empty() and game.skill_points == 20, "Missing parent rejects talent without consuming a point")
	_expect(game.choose_talent("trap_mastery").is_empty() and game.choose_talent("lasting_poison").is_empty(), "Parent unlocks its child")
	var remaining: int = game.skill_points
	_expect(not game.choose_talent("lasting_poison").is_empty() and game.skill_points == remaining, "Unique talent cannot be purchased twice")
	game.choose_talent("iron_throne")
	for _rank in range(3):
		_expect(game.choose_talent("thick_armor").is_empty(), "Armor talent accepts its three ranks")
	remaining = game.skill_points
	_expect(not game.choose_talent("thick_armor").is_empty() and game.skill_points == remaining, "Armor rejects a fourth rank without charging")
	game.choose_talent("overlord_might")
	game.choose_talent("battle_lord")
	_expect(not game.choose_talent("opening_wrath").is_empty(), "Opening wrath still requires Lord level 4")
	game.lord.level = 4
	_expect(game.choose_talent("opening_wrath").is_empty(), "Level and parent together unlock opening wrath")
	game.phase = "raid"
	remaining = game.skill_points
	_expect(not game.choose_talent("iron_throne").is_empty() and game.skill_points == remaining, "Combat cannot spend talent points")

	var rewards = _model()
	rewards.wave = 70
	rewards.phase = "raid"
	rewards.lord.xp = 48 # 10 + 16 + 22: three levels in this wave.
	rewards._finish_wave()
	_expect(rewards.lord.level == 4 and rewards.skill_points == 3 and int(rewards.report.skill_points) == 3, "One victorious wave can grant exactly three points for three levels")
	_expect(rewards.next_wave().is_empty() and rewards.phase == "level_up", "New points open one tree before other rewards")
	_expect(rewards.defer_talents().is_empty() and rewards.phase == "blueprint" and rewards.skill_points == 3, "Deferring banks all points and proceeds to blueprint")
	rewards.choose_blueprint(str(rewards.blueprint_options()[0].id))
	_expect(rewards.phase == "relic" and rewards.skill_points == 3, "Blueprint proceeds to relic without losing banked points")
	rewards.choose_relic(str(rewards.relic_options()[0].id))
	_expect(rewards.phase == "prepare" and rewards.skill_points == 3, "Reward queue completes with saved points available")
	_expect(rewards.start_raid().is_empty(), "Banked talent points do not block the next wave")
	rewards._finish_wave()
	rewards.next_wave()
	_expect(rewards.phase == "prepare" and rewards.skill_points == 3, "Old banked points do not force the tree again next wave")

	var legacy = _model()
	legacy.skill_points = 1
	legacy.pending_upgrades = 2
	legacy.talent_offers.assign(["greed"])
	legacy.selected_talents = {"greed": 1}
	legacy.migrate_legacy_talents()
	legacy.migrate_legacy_talents()
	_expect(legacy.skill_points == 3 and legacy.pending_upgrades == 0 and legacy.talent_offers.is_empty(), "Repeated legacy conversion grants pending points exactly once")
	_expect(legacy.selected_talents.get("greed") == 1 and str(_node(legacy.talent_tree(), "greed").state) == "maxed", "Previously owned legacy talent remains owned without its new parent")

func _settle() -> void:
	for _frame in range(5):
		await process_frame

func _graphs(node: Node) -> Array[Control]:
	var result: Array[Control] = []
	if node is Control and node.has_meta("progression_tree"):
		result.append(node)
	for child in node.get_children():
		result.append_array(_graphs(child))
	return result

func _check_modal(ui: Control, expected_kind: String, minimum_nodes: int) -> void:
	_expect(is_instance_valid(ui.modal) and ui.modal_kind == expected_kind, expected_kind + " modal exists")
	var graphs: Array[Control] = _graphs(ui.modal)
	var count: int = 0
	var valid_layout: bool = not graphs.is_empty()
	for graph in graphs:
		count += graph._buttons.size()
		valid_layout = valid_layout and graph.is_visible_in_tree() and graph.size.x > 0
		for id in graph._buttons:
			var button: Button = graph._buttons[id]
			valid_layout = valid_layout and button.is_visible_in_tree() and button.size.x > 0 and button.size.y >= 44
			valid_layout = valid_layout and button.position.x >= -1 and button.position.x + button.size.x <= graph.size.x + 1
	_expect(count >= minimum_nodes and valid_layout, expected_kind + " has visible, sized nodes inside graph bounds")
	_expect(is_instance_valid(ui.modal_footer) and ui.modal_footer.is_visible_in_tree(), expected_kind + " keeps its action footer visible")
	var viewport: Rect2 = ui.get_viewport_rect()
	var footer_rect: Rect2 = ui.modal_footer.get_global_rect()
	_expect(viewport.encloses(footer_rect), expected_kind + " action footer fits the viewport")

func _check_ui() -> void:
	root.size = Vector2i(1280, 800)
	var ui = MainScene.instantiate()
	ui.set_script(IsolatedMain)
	root.add_child(ui)
	ui.set_process(false)
	await _settle()
	ui._begin_run()
	ui.game.restart(20261020)
	ui.game.shop = {"goblin": 5}
	ui.game.gold = 1000
	ui.game.buy_room(0, "goblin")
	ui.selected_slot = 0
	ui._upgrade()
	await _settle()
	_check_modal(ui, "room_tree", 3)
	var paid: int = ui.game.gold
	ui._modal_back()
	ui._upgrade()
	await _settle()
	_expect(ui.game.gold == paid and int(ui.game.rooms[0].rank) == 2, "Reopening an unresolved room branch does not buy another rank")
	ui._specialize(0, "war_banner")
	ui.game.skill_points = 2
	ui._show_talents()
	await _settle()
	_check_modal(ui, "talents", 12)
	ui._show_talents("lasting_poison")
	await _settle()
	_check_modal(ui, "talents", 12)
	ui._show_mastery_tree("fallen_knight")
	await _settle()
	_check_modal(ui, "mastery", 7)
	ui.lords_profile.souls = 100
	ui._upgrade_lord("fallen_knight")
	await _settle()
	_expect(ui.lords_profile.levels.fallen_knight == 2 and ui.lords_profile.souls == 70, "Mastery action upgrades once using the isolated profile")
	_check_modal(ui, "mastery", 7)
	root.size = Vector2i(390, 844)
	ui._apply_screen_layout()
	await _settle()
	_expect(ui.compact_ui, "A portrait phone viewport activates compact layout")
	ui._show_talents()
	await _settle()
	_check_modal(ui, "talents", 2)
	ui._show_room_tree(0)
	await _settle()
	_check_modal(ui, "room_tree", 3)
	ui._show_mastery_tree("fallen_knight")
	await _settle()
	_check_modal(ui, "mastery", 7)
	ui._close_modal()
	ui.queue_free()
	await _settle()

func _check_view_lifecycle() -> void:
	var game = Game.new()
	var view = DungeonView.new()
	root.add_child(view)
	view.set_process(false)
	game.restart(771)
	view.configure(game)
	game.start_raid()
	for _step in range(4):
		game.step()
		view.refresh_runtime()
	var previous_seq: int = view._last_event_seq
	_expect(previous_seq > 0, "View observes real encounter events before restart")
	view._hero_positions["previous_run_hero"] = Vector2.ONE
	# Reuse both objects as Main does; a new object would hide this regression.
	game.restart(771)
	view.configure(game)
	_expect(view._last_event_seq == -1, "Restart resets the view's old event threshold")
	_expect(view._hero_positions.is_empty(), "Restart releases old hero coordinates")
	game.start_raid()
	game.step()
	view.refresh_runtime()
	_expect(not view._events.is_empty(), "A restarted run immediately displays its first new events")
	_expect(view._last_event_seq < previous_seq, "The new event sequence can be smaller than the previous run")
	view._last_wave = game.wave
	view._hero_positions["previous_wave_hero"] = Vector2.ONE
	view._actor_positions["previous_wave_actor"] = Vector2.ONE
	game.wave += 1
	view._update_party(0)
	_expect(view._hero_positions.is_empty(), "Wave transitions do not accumulate old hero positions")
	_expect(view._actor_positions.is_empty(), "Wave transitions do not accumulate old defender positions")
	view.queue_free()
	await _settle()

func _run() -> void:
	_check_room_model()
	_check_talent_model()
	await _check_ui()
	await _check_view_lifecycle()
	print("PROGRESSION TREE: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		print("FAIL: " + failure)
	quit(0 if failures.is_empty() else 1)

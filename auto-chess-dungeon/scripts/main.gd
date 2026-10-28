extends Control

const Game = preload("res://scripts/dungeon_game.gd")
const Content = preload("res://scripts/content_catalog.gd")
const SoulFeedback = preload("res://scripts/soul_feedback.gd")
const RunSkillScreen = preload("res://scripts/run_skill_screen.gd")
const Lords = preload("res://scripts/lord_catalog.gd")
const LordProgression = preload("res://scripts/lord_progression.gd")
const DungeonView = preload("res://scripts/dungeon_view.gd")
const TutorialGuide = preload("res://scripts/tutorial_guide.gd")
const ProgressionTree = preload("res://scripts/progression_tree.gd")
const EvolutionPreview = preload("res://scripts/evolution_preview.gd")
const RoomEvolutions = preload("res://scripts/room_evolution_catalog.gd")
const HeroRules = preload("res://scripts/hero_rules.gd")
const INK = Color("#0e1118")
const PANEL = Color("#181e28")
const TILE = Color("#212938")
const LINE = Color("#333e4e")
const PAPER = Color("#ede5d5")
const MUTED = Color("#929eaf")
const GOLD = Color("#dfba70")
const RED = Color("#d97e78")
const GREEN = Color("#83bfa6")
const VIOLET = Color("#ae97d4")

var game = Game.new()
var selected_slot: int = -1
var selected_room: String = ""
var selecting_deal: bool = false
var speed: int = 1
var paused: bool = false
var sound_on: bool = true
var accumulator: float = 0.0
var message: String = ""
var profile: Dictionary = {"wave": 0, "kills": 0, "floors": 1, "level": 1, "unlocked_paths": []}
var page: VBoxContainer
var floor_scroll: ScrollContainer
var log_box: RichTextLabel
var scroll_position: int = 0
var active_floor: int = -1
var modal: PanelContainer
var modal_shade: ColorRect
var audio_player: AudioStreamPlayer
var sounds: Dictionary = {}
var screenshot_path: String = ""
var demo_mode: bool = false
var preview_raid: bool = false
var menu_open: bool = true
var has_run: bool = false
var volume: float = 0.65
var dungeon_view: Control
var menu_preview: Control
var resume_paused: bool = false
var lords_profile: Dictionary = LordProgression.default_profile()
var menu_section: String = "home"
var inspected_lord: String = "fallen_knight"
var lord_message: String = ""
var run_best_at_start: int = 0
var run_reward_claimed: bool = true
var last_run_reward: Dictionary = {}
var tutorial = TutorialGuide.new()
var tutorial_saved_speed: int = 1
var compact_ui: bool = false
var short_ui: bool = false
var last_room_tap: int = -1
var last_room_tap_msec: int = 0
var shell_margin: MarginContainer
var layout_size: Vector2i = Vector2i.ZERO
var layout_pending: bool = false
var layout_poll: float = 0.0
var remembered_scrolls: Dictionary = {}
var live_scrolls: Dictionary = {}
var modal_scroll: ScrollContainer
var modal_content: VBoxContainer
var modal_frame: VBoxContainer
var modal_width: int = 560
var modal_is_compact: bool = false
var touch_points: Dictionary = {}
var refresh_after_touch: bool = false
var refresh_keeps_modal: bool = false
var modal_kind: String = ""
var phase_modal_dismissed: bool = false
var modal_footer: VBoxContainer
var tree_room_index: int = -1
var room_tree_focus: String = ""
var talent_tree_focus: String = "root"
var run_skill_camera: Dictionary = {}
var run_skill_pause_before: bool = false
var run_skill_pause_owned: bool = false
var run_skill_previous_focus: WeakRef
var mastery_tree_focus: String = ""
var _live_ui: Array[Dictionary] = []
var _camp_live_ui: Array[Dictionary] = []
var _camp_ui_state: Dictionary = {}
var skill_wallet_button: Button
var soul_feedback: Control

func _ready() -> void:
	_apply_screen_layout()
	get_window().size_changed.connect(_request_screen_layout)
	_load_local()
	game.unlocked_paths.assign(profile.get("unlocked_paths", []))
	game.restart()
	run_skill_camera.clear()
	talent_tree_focus = "root"
	_configure_selected_lord(game)
	get_tree().auto_accept_quit = false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture="):
			screenshot_path = argument.trim_prefix("--capture=")
		if argument == "--demo":
			demo_mode = true
		if argument == "--preview-raid":
			preview_raid = true
	if demo_mode:
		menu_open = false
		has_run = true
		_make_demo()
		if preview_raid:
			game.start_raid()
			for step_index in range(5):
				game.step()
			paused = true
	_make_theme()
	audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	for key in ["click", "hit", "win", "lose"]:
		sounds[key] = _make_sound(key)
	_build_shell()
	soul_feedback = SoulFeedback.new()
	add_child(soul_feedback)
	_refresh()
	if not screenshot_path.is_empty():
		_capture.call_deferred()

func _screen_css_size() -> Vector2i:
	if OS.has_feature("web"):
		var dimensions = JavaScriptBridge.eval("(function(){var c=document.getElementById('canvas');var r=c?c.getBoundingClientRect():null;return JSON.stringify([Math.round(r&&r.width?r.width:window.innerWidth),Math.round(r&&r.height?r.height:window.innerHeight)]);})()")
		if dimensions is String:
			var parsed = JSON.parse_string(dimensions)
			if parsed is Array and parsed.size() == 2:
				return Vector2i(maxi(320, int(parsed[0])), maxi(240, int(parsed[1])))
	return Vector2i(maxi(320, get_window().size.x), maxi(240, get_window().size.y))

func _request_screen_layout() -> void:
	if layout_pending:
		return
	layout_pending = true
	_apply_screen_layout.call_deferred()

func _apply_screen_layout() -> void:
	layout_pending = false
	var available: Vector2i = _screen_css_size()
	if available == layout_size:
		return
	layout_size = available
	compact_ui = available.x < 980 or (available.y < 600 and available.x < 1180)
	short_ui = compact_ui and available.y < 500 and available.x > available.y
	var target: Vector2i = available if compact_ui else Vector2i(1280, 800)
	if get_window().content_scale_size != target:
		get_window().content_scale_size = target
	if not is_instance_valid(page):
		return
	_apply_shell_spacing()
	_refresh(true)
	if is_instance_valid(modal):
		match modal_kind:
			"room_tree":
				_show_room_tree(tree_room_index, room_tree_focus)
			"talents":
				_show_talents(modal.selected_id)
			"mastery":
				_show_mastery_tree(inspected_lord, mastery_tree_focus)
			_:
				_adapt_modal_controls(modal)
				_resize_modal.call_deferred()

func _apply_shell_spacing() -> void:
	var insets: Dictionary = {}
	if OS.has_feature("web"):
		var data = JavaScriptBridge.eval("(function(){var c=document.getElementById('canvas');if(document.fullscreenElement!==c)return '{}';var s=getComputedStyle(document.documentElement),o={};['left','right','top','bottom'].forEach(function(k){o[k]=parseFloat(s.getPropertyValue('--safe-'+k))||0;});return JSON.stringify(o);})()")
		if data is String:
			var parsed = JSON.parse_string(data)
			if parsed is Dictionary:
				insets = parsed
	var logical_scale: float = 1.0 if compact_ui else maxf(1280.0 / maxf(1.0, layout_size.x), 800.0 / maxf(1.0, layout_size.y))
	for edge in ["left", "right", "top", "bottom"]:
		shell_margin.add_theme_constant_override("margin_" + edge, (6 if compact_ui else 20) + ceili(float(insets.get(edge, 0.0)) * logical_scale))
	page.add_theme_constant_override("separation", 6 if compact_ui else 14)

func _remember_scrolls() -> void:
	for key in live_scrolls:
		var scroll = live_scrolls[key]
		if is_instance_valid(scroll):
			remembered_scrolls[key] = scroll.scroll_vertical
	live_scrolls.clear()

func _track_scroll(scroll: ScrollContainer, key: String) -> void:
	if compact_ui:
		scroll.scroll_deadzone = 12
	live_scrolls[key] = scroll
	scroll.set_deferred("scroll_vertical", int(remembered_scrolls.get(key, 0)))

func _responsive_box() -> BoxContainer:
	var box = BoxContainer.new()
	box.vertical = compact_ui
	box.set_meta("responsive_box", true)
	return box

func _make_theme() -> void:
	var ui_theme = Theme.new()
	ui_theme.default_font_size = 15
	ui_theme.set_color("font_color", "Label", PAPER)
	ui_theme.set_color("font_color", "Button", PAPER)
	ui_theme.set_color("font_disabled_color", "Button", Color("#606b7c"))
	ui_theme.set_color("font_hover_color", "Button", Color.WHITE)
	ui_theme.set_constant("outline_size", "Label", 0)
	ui_theme.set_constant("separation", "VBoxContainer", 8)
	ui_theme.set_constant("separation", "HBoxContainer", 10)
	ui_theme.set_stylebox("normal", "Button", _style(TILE, LINE, 8, 10))
	ui_theme.set_stylebox("hover", "Button", _style(Color("#303a49"), GOLD, 8, 10))
	ui_theme.set_stylebox("pressed", "Button", _style(Color("#393a36"), GOLD, 8, 10))
	ui_theme.set_stylebox("disabled", "Button", _style(Color("#181e27"), Color("#283140"), 8, 10))
	ui_theme.set_stylebox("focus", "Button", _style(Color.TRANSPARENT, GOLD, 8, 2))
	ui_theme.set_stylebox("background", "ProgressBar", _style(Color("#10151d"), Color.TRANSPARENT, 4, 0))
	ui_theme.set_stylebox("fill", "ProgressBar", _style(GREEN, Color.TRANSPARENT, 4, 0))
	theme = ui_theme

func _build_shell() -> void:
	var bg = ColorRect.new()
	bg.color = INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	shell_margin = MarginContainer.new()
	shell_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shell_margin)
	page = VBoxContainer.new()
	shell_margin.add_child(page)
	_apply_shell_spacing()

func _refresh(keep_modal: bool = false) -> void:
	if tutorial.observe(game):
		paused = true
		accumulator = 0.0
	if compact_ui and not touch_points.is_empty():
		refresh_after_touch = true
		refresh_keeps_modal = refresh_keeps_modal or keep_modal
		return
	refresh_after_touch = false
	_live_ui.clear()
	_camp_live_ui.clear()
	_camp_ui_state = game.camp_status() if game.phase == "camp" else {}
	if is_instance_valid(floor_scroll):
		scroll_position = floor_scroll.scroll_vertical
	floor_scroll = null
	_remember_scrolls()
	if is_instance_valid(dungeon_view) and dungeon_view.get_parent():
		dungeon_view.get_parent().remove_child(dungeon_view)
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	if menu_open:
		if menu_section == "lords":
			if compact_ui:
				_build_mobile_lords()
			else:
				_build_lords_page()
		else:
			if compact_ui:
				_build_mobile_menu()
			else:
				_build_menu()
		return
	if compact_ui:
		_build_mobile_game()
	else:
		_header()
		if tutorial.active():
			_tutorial_banner(page)
		var body = HBoxContainer.new()
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		body.add_theme_constant_override("separation", 12)
		page.add_child(body)
		_party_panel(body)
		_dungeon_panel(body)
		if selected_slot >= 0 and game.phase == "prepare":
			_inspector_panel(body)
		_shop_panel()
		_footer()
	if is_instance_valid(floor_scroll):
		floor_scroll.set_deferred("scroll_vertical", scroll_position)
	if game.phase in ["raid", "camp"]:
		var target_floor: int = mini(game.current_slot / 5, game.floor_count)
		if target_floor != active_floor and game.current_slot >= 0:
			active_floor = target_floor
			scroll_position = target_floor * 160
			if is_instance_valid(floor_scroll):
				floor_scroll.set_deferred("scroll_vertical", scroll_position)
	if not keep_modal and not phase_modal_dismissed:
		_show_phase_modal()
	_refresh_live_values()


func _bind_live(node: Object, property: String, read: Callable) -> void:
	_live_ui.append({"node": node, "property": property, "read": read})
	node.set(property, read.call())


func _live_label(read: Callable, font_size: int = 15, color: Color = PAPER, wrap: bool = false) -> Label:
	var label := _label(str(read.call()), font_size, color, wrap)
	_bind_live(label, "text", func(): return _ui_text(str(read.call())))
	return label


func _live_bar(hp: Callable, maximum: Callable, tint: Color) -> ProgressBar:
	var bar := _bar(float(hp.call()), float(maximum.call()), tint)
	_bind_live(bar, "max_value", func(): return maxf(1, float(maximum.call())))
	_bind_live(bar, "value", func(): return maxf(0, float(hp.call())))
	return bar


func _refresh_live_values() -> void:
	_refresh_camp_values()
	if is_instance_valid(soul_feedback):
		soul_feedback.paused = paused or is_instance_valid(modal) or menu_open
		soul_feedback.speed = float(speed)
	for binding in _live_ui:
		if is_instance_valid(binding.node):
			binding.node.set(str(binding.property), binding.read.call())
	if is_instance_valid(dungeon_view):
		dungeon_view.animation_paused = paused or is_instance_valid(modal) or menu_open
		dungeon_view.animation_speed = float(speed)


func _bind_camp(node: Object, property: String, read: Callable) -> void:
	_camp_live_ui.append({"node": node, "property": property, "read": read})
	node.set(property, read.call())


func _refresh_camp_values() -> void:
	# One model snapshot feeds the timer, pulse bars, price and availability.
	_camp_ui_state = game.camp_status() if game.phase == "camp" else {}
	for binding in _camp_live_ui:
		if is_instance_valid(binding.node):
			binding.node.set(str(binding.property), binding.read.call())


func _camp_panel(parent: Control) -> void:
	var body = _vbox(parent, 3)
	var timer = _label("", 13, GOLD, true)
	body.add_child(timer)
	_bind_camp(timer, "text", func():
		if short_ui:
			return _ui_text("Привал · %.1f с · порций: %d · до %d HP" % [
				float(_camp_ui_state.get("remaining_seconds", 0.0)),
				int(_camp_ui_state.get("remaining_pulses", 0)),
				int(_camp_ui_state.get("remaining_healing", 0))])
		return _ui_text("Привал · этаж %d · ещё %.1f с из %d" % [
			int(_camp_ui_state.get("floor_index", 0)) + 1,
			float(_camp_ui_state.get("remaining_seconds", 0.0)),
			int(_camp_ui_state.get("duration", 0))]))
	var bars: Control = body
	if short_ui:
		bars = HBoxContainer.new()
		bars.add_theme_constant_override("separation", 6)
		body.add_child(bars)
	var total = _bar(0.0, 1.0, GOLD, 7)
	total.step = 0.001
	total.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bars.add_child(total)
	_bind_camp(total, "value", func(): return float(_camp_ui_state.get("progress", 0.0)))
	var portions = _label("", 12, PAPER, true)
	portions.visible = not short_ui
	body.add_child(portions)
	_bind_camp(portions, "text", func(): return _ui_text("Осталось порций: %d · ещё до %d HP отряду" % [
		int(_camp_ui_state.get("remaining_pulses", 0)),
		int(_camp_ui_state.get("remaining_healing", 0))]))
	var pulse = _bar(0.0, 1.0, GREEN, 4)
	pulse.step = 0.001
	pulse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pulse.tooltip_text = "До следующей порции лечения"
	bars.add_child(pulse)
	_bind_camp(pulse, "value", func(): return float(_camp_ui_state.get("pulse_progress", 0.0)))
	var reason = _label("", 12, MUTED, true)
	body.add_child(reason)
	_bind_camp(reason, "text", func():
		var unavailable: String = str(_camp_ui_state.get("reason", ""))
		var available: String = "E — срыв за золото · Q недоступна" if short_ui else "E отменит оставшееся лечение; доступна на паузе. Q недоступна."
		return _ui_text(unavailable if not unavailable.is_empty() else available))
	_bind_camp(reason, "theme_override_colors/font_color", func(): return RED if not str(_camp_ui_state.get("reason", "")).is_empty() else MUTED)


func _camp_interrupt_button() -> Button:
	var button = _button("", _interrupt_camp)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_color_override("font_color", GOLD)
	_bind_camp(button, "text", func(): return _ui_text("E · Сорвать привал · %d зол." % int(_camp_ui_state.get("gold_cost", 0))))
	_bind_camp(button, "disabled", func(): return not bool(_camp_ui_state.get("can_interrupt", false)))
	_bind_camp(button, "tooltip_text", func(): return _ui_text("Отменить ещё до %d HP лечения за %d зол. Уже полученные HP остаются. Доступна на паузе.\n%s" % [
		int(_camp_ui_state.get("remaining_healing", 0)),
		int(_camp_ui_state.get("gold_cost", 0)),
		str(_camp_ui_state.get("reason", ""))]))
	return button


func _wave_summary() -> String:
	return "%s · отряд: %d" % [game.wave_title, game.heroes.size()]


func _combat_guidance() -> String:
	if not message.is_empty():
		return message
	if game.phase == "camp":
		return "Герои отдыхают. Пауза останавливает привал; E срывает его за золото."
	var action: String = str(game.last_action.get("text", ""))
	return action if not action.is_empty() else "Группа спускается в подземелье."


func _refresh_raid() -> void:
	# Actor numbers change every step; layout, scroll and buttons stay alive.
	# This also keeps touch targets stable on mobile during fast combat.
	if tutorial.observe(game):
		paused = true
		accumulator = 0.0
		_refresh()
		return
	_refresh_live_values()
	if is_instance_valid(dungeon_view):
		dungeon_view.refresh_runtime()
	var target_floor: int = mini(game.current_slot / 5, game.floor_count)
	if target_floor != active_floor and game.current_slot >= 0:
		active_floor = target_floor
		scroll_position = target_floor * 160
		if is_instance_valid(floor_scroll):
			floor_scroll.set_deferred("scroll_vertical", scroll_position)

func _build_mobile_game() -> void:
	var header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 6)
	page.add_child(header)
	var numbers = _vbox(header, 1)
	numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	numbers.add_child(_live_label(func(): return "Волна %d  ·  %d зол." % [game.wave, game.gold], 16, GOLD))
	numbers.add_child(_live_label(func(): return "Лорд %d/%d HP · Q: %d зол." % [maxi(0, game.lord.hp), game.lord.max_hp, int(game.ability_status().get("gold_cost", 0))], 12, PAPER))
	var talents = _button("", _show_talents)
	talents.custom_minimum_size = Vector2(82, 44)
	talents.autowrap_mode = TextServer.AUTOWRAP_OFF
	talents.set_meta("accessible_label", "Навыки")
	skill_wallet_button = talents
	_bind_live(talents, "text", func(): return "Навыки\n%d" % game.run_souls)
	_bind_live(talents, "tooltip_text", func(): return "Навыки · душ: %d" % game.run_souls)
	if game.run_souls > 0:
		talents.add_theme_stylebox_override("normal", _style(Color("#353025"), GOLD, 8, 6))
	header.add_child(talents)
	var tools = header if short_ui else HBoxContainer.new()
	if not short_ui:
		var menu_button = _button("Меню", _open_menu)
		menu_button.custom_minimum_size.x = 64
		header.add_child(menu_button)
		page.add_child(tools)
	tools.add_theme_constant_override("separation", 6)
	var shop_button = _icon_button("res://assets/icons/shop.svg", "Магазин", _show_shop)
	shop_button.disabled = game.phase != "prepare"
	if tutorial.active() and tutorial.target().begins_with("shop:"):
		shop_button.add_theme_stylebox_override("normal", _style(Color("#353025"), GOLD, 8, 8))
	tools.add_child(shop_button)
	tools.add_child(_icon_button("res://assets/icons/knight.svg", "Герои · отряд: %d" % game.heroes.size(), _show_party))
	var heal_button = _heal_button()
	heal_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(heal_button)
	if short_ui:
		var menu_button = _button("Меню", _open_menu)
		menu_button.custom_minimum_size.x = 64
		tools.add_child(menu_button)
	page.add_child(_label(_wave_summary(), 13, GOLD if game.wave_is_boss else MUTED, true))
	if tutorial.active():
		_tutorial_banner(page)
	var body = HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	_dungeon_panel(body)
	_mobile_actions()

func _icon_button(path: String, title: String, callback: Callable) -> Button:
	var button = _button("", callback)
	button.icon = load(path)
	button.expand_icon = true
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.custom_minimum_size = Vector2(44, 44)
	button.add_theme_constant_override("icon_max_width", 26)
	button.tooltip_text = _ui_text(title)
	button.set_meta("accessible_label", title)
	return button

func _heal_button() -> Button:
	var button = _button("Лечить Лорда · %d зол." % game.heal_cost(), _heal, game.phase != "prepare" or game.gold < game.heal_cost() or game.lord.hp >= game.lord.max_hp)
	button.add_theme_font_size_override("font_size", 13)
	var price: Dictionary = game.heal_price_details()
	button.tooltip_text = "Восстановит %d HP." % game.paid_heal_amount()
	if int(price.saving) > 0:
		button.tooltip_text += " Придворный лекарь: экономия %d зол." % int(price.saving)
	_tutorial_mark(button, "heal")
	return button

func _show_shop() -> void:
	if game.phase != "prepare" or menu_open:
		return
	_close_modal()
	modal_kind = "shop"
	var body = _new_modal(650, true)
	_shop_panel(body)

func _show_party() -> void:
	_close_modal()
	modal_kind = "party"
	var body = _new_modal(520, true)
	_party_contents(body, false)

func _show_room_details() -> void:
	if selected_slot < 0 or selected_slot >= game.rooms.size() or game.rooms[selected_slot].is_empty():
		return
	_close_modal()
	modal_kind = "room"
	var body = _new_modal(440, true)
	_room_details(body, selected_slot)

func _mobile_actions() -> void:
	if game.phase == "camp":
		_camp_panel(page)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	page.add_child(row)
	if game.phase == "prepare":
		if selected_slot >= 0 or not selected_room.is_empty() or selecting_deal:
			var cancel = _button("Отмена", _cancel_selection)
			cancel.custom_minimum_size.x = 76
			row.add_child(cancel)
		var start = _button("НАЧАТЬ ВОЛНУ %d" % game.wave, _start)
		start.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		start.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 8, 8))
		start.add_theme_color_override("font_color", INK)
		row.add_child(start)
		_tutorial_mark(start, "start")
	elif game.phase in ["raid", "camp"]:
		var pause_button = _button("Далее" if paused else "Пауза", _toggle_pause)
		pause_button.custom_minimum_size.x = 68
		pause_button.disabled = not tutorial.allows("pause")
		row.add_child(pause_button)
		var speed_button = _button("x%d" % speed, _cycle_speed)
		speed_button.custom_minimum_size.x = 44
		speed_button.disabled = not tutorial.allows("speed")
		row.add_child(speed_button)
		if game.phase == "camp":
			var interrupt = _camp_interrupt_button()
			interrupt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			interrupt.add_theme_font_size_override("font_size", 13)
			row.add_child(interrupt)
			return
		var ability: Dictionary = game.ability_status()
		var cast = _button("%s · %d/%d" % [ability.name, ability.charges, ability.max_charges], _cast_lord_ability, not bool(ability.can_cast))
		_bind_ability_button(cast, false)
		cast.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cast.add_theme_color_override("font_color", GREEN)
		cast.add_theme_font_size_override("font_size", 13)
		cast.tooltip_text = _ui_text(str(ability.description) + "\n" + str(ability.reason))
		row.add_child(cast)
		_tutorial_mark(cast, "ability")
	else:
		var result = _button(_phase_action_text(), _show_phase_modal)
		result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(result)

func _cycle_speed() -> void:
	if menu_open or is_instance_valid(modal) or game.phase not in ["raid", "camp"]:
		return
	_set_speed(2 if speed == 1 else 4 if speed == 2 else 1)


func _bind_ability_button(button: Button, keyboard: bool) -> void:
	_bind_live(button, "disabled", func(): return not bool(game.ability_status().can_cast))
	_bind_live(button, "text", func():
		var state: Dictionary = game.ability_status()
		return ("Q · " if keyboard else "") + "%s · %d/%d · %d зол." % [state.name, state.charges, state.max_charges, state.get("gold_cost", 0)])
	_bind_live(button, "tooltip_text", func():
		var state: Dictionary = game.ability_status()
		return _ui_text(str(state.description) + "\nЦена: %d зол. · зафиксирована на волну, без бонусов дохода\n" % int(state.get("gold_cost", 0)) + str(state.reason)))


func _hero_item(hero: Dictionary, slot: String) -> Dictionary:
	for item in HeroRules.equipment_summary(hero):
		if str(item.slot) == slot:
			return item
	return {}


func _equipment_row(parent: Control, hero: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	parent.add_child(row)
	for slot in ["weapon", "protection"]:
		var label: String = "Оружие" if slot == "weapon" else "Защита"
		var button := _button(label, _show_equipment_details.bind(hero, slot))
		button.custom_minimum_size = Vector2(0, 30)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.add_theme_font_size_override("font_size", 10)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_bind_live(button, "text", func():
			var item: Dictionary = _hero_item(hero, slot)
			return ("• " if bool(item.get("special", false)) else "") + str(item.get("name", label)))
		_bind_live(button, "tooltip_text", func():
			var item: Dictionary = _hero_item(hero, slot)
			return _ui_text(str(item.get("name", label)) + "\n" + str(item.get("description", "")) + ("\nВременно отключено" if not bool(item.get("active", true)) else "")))
		_bind_live(button, "modulate", func():
			var item: Dictionary = _hero_item(hero, slot)
			return Color(1, 1, 1, 0.45) if not bool(item.get("active", true)) else (GOLD if bool(item.get("special", false)) else Color.WHITE))
		row.add_child(button)


func _show_equipment_details(hero: Dictionary, slot: String) -> void:
	var item: Dictionary = _hero_item(hero, slot)
	_close_modal()
	modal_kind = "equipment"
	var body := _new_modal(460, true)
	body.add_child(_eyebrow("ОРУЖИЕ" if slot == "weapon" else "ЗАЩИТА"))
	body.add_child(_label(str(item.get("name", "Пустой слот")), 24, GOLD, true))
	body.add_child(_label(str(item.get("description", "")), 15, PAPER, true))
	if not bool(item.get("active", true)):
		body.add_child(_label("Временно отключено эффектом комнаты", 13, RED, true))
	if slot == "weapon" and bool(hero.get("effects", {}).get("weapon_swap", false)):
		body.add_child(_label("Оружие подменено мимиком до конца волны", 13, RED, true))

func _header() -> void:
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	page.add_child(head)
	var mark = _icon_button("res://assets/icons/lord.svg", "Навыки · душ: %d" % game.run_souls, _show_talents)
	mark.custom_minimum_size = Vector2(56, 56)
	skill_wallet_button = mark
	_bind_live(mark, "text", func(): return "Навыки · %d" % game.run_souls)
	if game.run_souls > 0:
		mark.add_theme_stylebox_override("normal", _style(Color("#353025"), GOLD, 8, 6))
	head.add_child(mark)
	var brand = VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	head.add_child(brand)
	brand.add_child(_label("NO HERO RETURNS", 25, PAPER))
	_stat(head, "ВОЛНА", str(game.wave), PAPER)
	_stat(head, "ЗОЛОТО", str(game.gold), GOLD, func(): return str(game.gold))
	_stat(head, "РЕКОРД", str(int(profile.get("wave", 0))), VIOLET)
	var small = VBoxContainer.new()
	head.add_child(small)
	small.add_child(_button("Меню", _open_menu))

func _party_panel(parent: Control) -> void:
	var box = _panel(parent, 222)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL if compact_ui else Control.SIZE_FILL
	var outer_scroll = ScrollContainer.new()
	outer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(outer_scroll)
	_track_scroll(outer_scroll, "party")
	var side = _vbox(outer_scroll)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_contents(side)

func _party_overview_columns() -> int:
	return 3 if get_viewport_rect().size.x >= 390.0 else 2


func _party_overview(parent: Control) -> void:
	var grid = GridContainer.new()
	grid.columns = _party_overview_columns()
	grid.set_meta("party_overview", true)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for hero in game.heroes:
		var card = _panel(grid)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel", _style(TILE, LINE, 6, 5))
		var body = _vbox(card, 3)
		var definition: Dictionary = Content.hero(str(hero.id))
		var portrait = _icon(str(definition.get("icon", "")), 24)
		body.add_child(portrait)
		_bind_live(portrait, "modulate", func(): return Color(1, 1, 1, 1.0 if hero.hp > 0 else 0.3))
		body.add_child(_label(str(definition.get("name", hero.id)), 13, PAPER, true))
		body.add_child(_live_bar(func(): return hero.hp, func(): return hero.max_hp, RED))
		body.add_child(_live_label(func(): return "%d / %d HP" % [maxi(0, hero.hp), hero.max_hp], 13, MUTED, true))


func _hero_camp_text(hero: Dictionary) -> String:
	for state in _camp_ui_state.get("heroes", []):
		if str(state.get("instance_id", "")) == str(hero.get("instance_id", "")):
			return "Привал: ещё до %d HP · сила лечения %d%%" % [
				int(state.get("remaining_healing", 0)),
				roundi(float(state.get("healing_factor", 1.0)) * 100.0)]
	return ""


func _party_contents(side: Control, show_lord: bool = true) -> void:
	side.add_child(_eyebrow("РАЗВЕДКА"))
	side.add_child(_label("Приключенцы", 23))
	var state_text: String = "Следующая группа" if game.phase == "prepare" else "Группа в подземелье"
	side.add_child(_label(state_text + " · %d чел." % game.heroes.size(), 12, MUTED))
	var expedition: String = game.wave_title
	var expedition_label = _label(expedition, 12, GOLD, true)
	expedition_label.tooltip_text = _ui_text(game.wave_description)
	side.add_child(expedition_label)
	if game.wave_is_boss:
		side.add_child(_label(game.wave_description, 12, GOLD, true))
	if compact_ui and game.heroes.size() >= 5:
		_party_overview(side)
	var party_scroll = ScrollContainer.new()
	party_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	party_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(party_scroll)
	var heroes_col = VBoxContainer.new()
	heroes_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_scroll.add_child(heroes_col)
	for hero in game.heroes:
		var card = PanelContainer.new()
		var compact: bool = game.heroes.size() > 1
		if compact_ui:
			compact = false
		card.add_theme_stylebox_override("panel", _style(TILE if hero.hp > 0 else Color("#1d2027"), LINE, 8, 7 if compact else 10))
		heroes_col.add_child(card)
		var inner = _vbox(card, 3 if compact else 5)
		var row = HBoxContainer.new()
		inner.add_child(row)
		var definition: Dictionary = Content.hero(str(hero.id))
		var portrait = _icon(str(definition.get("icon", "")), 28 if compact else 36)
		portrait.modulate.a = 1.0 if hero.hp > 0 else 0.3
		row.add_child(portrait)
		var names = VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_theme_constant_override("separation", 1)
		row.add_child(names)
		names.add_child(_label(str(definition.get("name", hero.id)), 14 if compact else 16, PAPER if hero.hp > 0 else MUTED, true))
		names.add_child(_live_label(func(): return "Уровень %d" % hero.level, 11, VIOLET))
		_bind_live(portrait, "modulate", func(): return Color(1, 1, 1, 1.0 if hero.hp > 0 else 0.3))
		inner.add_child(_live_bar(func(): return hero.hp, func(): return hero.max_hp, RED))
		inner.add_child(_live_label(func(): return "%d/%d HP    Урон %d  ·  Броня %d" % [maxi(0, hero.hp), hero.max_hp, hero.damage, game.effective_hero_armor(hero)], 11, MUTED, true))
		if game.phase == "camp":
			inner.add_child(_live_label(func(): return _hero_camp_text(hero), 12, GREEN, true))
		_equipment_row(inner, hero)
		_bind_live(card, "tooltip_text", func(): return _ui_text(str(definition.get("trait", "")) + "\n" + _hero_status(hero, definition)))
		var status_label = _live_label(func(): return _hero_status(hero, definition), 10 if compact else 11, MUTED, true)
		status_label.max_lines_visible = 2 if show_lord else -1
		status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		inner.add_child(status_label)
	if tutorial.active():
		_tutorial_context(side, "party")
	if show_lord:
		side.add_child(HSeparator.new())
		_lord_status(side)
		side.add_child(_heal_button())

func _lord_status(parent: Control) -> void:
	var identity: Dictionary = Lords.get_lord(game.lord_archetype)
	var row = HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_icon(str(identity.get("icon", "res://assets/icons/lord.svg")), 30))
	var name_label = _label(str(identity.get("name", "Лорд Подземелья")), 16, GOLD, true)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = _ui_text(str(identity.get("passive_description", "")))
	row.add_child(name_label)
	parent.add_child(_live_label(func(): return "Уровень %d · мастерство %d / 5" % [game.lord.level, game.lord_mastery], 11, VIOLET))
	parent.add_child(_live_bar(func(): return game.lord.hp, func(): return game.lord.max_hp, GOLD))
	parent.add_child(_live_label(func(): return "%d/%d HP · Урон %d · Броня %d" % [maxi(0, game.lord.hp), game.lord.max_hp, game.lord.damage, game.lord.armor], 11, MUTED, true))
	parent.add_child(_live_label(func(): return "Опыт Лорда: %d / %d" % [game.lord.xp, 10 + 6 * (int(game.lord.level) - 1)], 11, VIOLET))
	var skills_button := _button("Навыки", _show_talents)
	_bind_live(skills_button, "text", func(): return "Навыки · душ: %d" % game.run_souls)
	parent.add_child(skills_button)
	parent.add_child(_live_label(func(): return "Q: %d зол. за применение" % int(game.ability_status().get("gold_cost", 0)), 11, GOLD))

func _dungeon_panel(parent: Control, floor_actions: Control = null) -> void:
	var box = _panel(parent)
	if floor_actions != null:
		box.add_theme_stylebox_override("panel", _style(PANEL, LINE, 10, 6))
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center = _vbox(box, 8)
	var title_row = HBoxContainer.new()
	title_row.visible = floor_actions == null
	center.add_child(title_row)
	var title = _label("Подземелье · %d этаж." % game.floor_count if compact_ui else "Подземелье", 15 if compact_ui else 21, PAPER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	if not compact_ui:
		title_row.add_child(_label("%d этаж. / %d мест" % [game.floor_count, game.rooms.size()], 11, GOLD))
	if not short_ui:
		_faction_counters(center)
	var guidance: String = message
	if selecting_deal and game.phase == "prepare":
		guidance = "Сделка: выберите пустое место." if compact_ui else "Сделка: выберите пустое место. Отмена — Esc или «Снять выбор»."
	elif not selected_room.is_empty() and game.phase == "prepare":
		guidance = "Разместить: %s. Выберите пустую комнату." % Content.room(selected_room).name
	elif selected_slot >= 0 and game.phase == "prepare":
		guidance = "Двойное нажатие: улучшить. Другое место: перенести." if compact_ui else "Выберите другое место для переноса."
	elif game.phase in ["raid", "camp"]:
		guidance = _combat_guidance()
	if short_ui:
		title.text = _ui_text(guidance if not guidance.is_empty() else "Этажей: %d" % game.floor_count)
		title.add_theme_font_size_override("font_size", 13)
		title.max_lines_visible = 2
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var caption = _label(guidance, 12, GOLD if game.phase in ["raid", "camp"] else MUTED, true)
	if game.phase in ["raid", "camp"]:
		_bind_live(title if short_ui else caption, "text", func(): return _ui_text(_combat_guidance()))
	caption.custom_minimum_size.y = 0
	if not short_ui and (not guidance.is_empty() or game.phase in ["raid", "camp"]):
		caption.max_lines_visible = 2 if compact_ui else -1
		caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		center.add_child(caption)
	else:
		caption.free()
	floor_scroll = ScrollContainer.new()
	floor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	floor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(floor_scroll)
	if compact_ui:
		floor_scroll.scroll_deadzone = 12
	if not is_instance_valid(dungeon_view):
		dungeon_view = DungeonView.new()
		dungeon_view.soul_visual_requested.connect(_show_soul_feedback)
		dungeon_view.slot_clicked.connect(_slot_clicked)
	dungeon_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_scroll.add_child(dungeon_view)
	var preview_room: String = str(game.deal_offer().get("room_id", "")) if selecting_deal else selected_room
	dungeon_view.compact = compact_ui
	dungeon_view.configure(game, selected_slot, preview_room)
	dungeon_view.tutorial_slot = _tutorial_slot()
	var floor_button = _button("+ Этаж · %d зол." % game.floor_cost() if compact_ui else "+ УГЛУБИТЬ ПОДЗЕМЕЛЬЕ · %d зол." % game.floor_cost(), _buy_floor, game.phase != "prepare" or game.gold < game.floor_cost())
	floor_button.custom_minimum_size.y = 44 if compact_ui else 38
	floor_button.visible = not (compact_ui and game.phase == "camp")
	floor_button.tooltip_text = _ui_text("Пять новых комнат и выбор свойства этажа: лаборатория, казармы или мастерская.")
	var floor_price: Dictionary = game.floor_price_details()
	if int(floor_price.saving) > 0:
		floor_button.tooltip_text += "\nСтроительная смета: экономия %d зол." % int(floor_price.saving)
	if floor_actions != null:
		floor_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		floor_actions.add_child(floor_button)
	elif compact_ui:
		floor_button.custom_minimum_size.x = 126
		title_row.add_child(floor_button)
	else:
		center.add_child(floor_button)
	_tutorial_mark(floor_button, "floor")

func _inspector_panel(parent: Control) -> void:
	var box = _panel(parent, 238)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_track_scroll(scroll, "room")
	var right = _vbox(scroll, 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_details(right, selected_slot)

func _room_details(parent: Control, index: int) -> void:
	if index < 0 or index >= game.rooms.size() or game.rooms[index].is_empty():
		return
	var stats: Dictionary = game.room_stats(index)
	var faction: Dictionary = Game.room_faction(str(stats.id))
	parent.add_child(_label("%s · %d" % [stats.name, stats.get("rank", 1)], 20, faction.get("color", GOLD), true))
	var values: String
	if str(stats.get("kind", "")) == "monster":
		values = "HP %d · Урон %d · Броня %d" % [stats.get("hp", 0), stats.get("damage", 0), stats.get("armor", 0)]
	elif str(stats.get("kind", "")) == "poison":
		values = "Яд %.2f за тик · %d тиков" % [float(stats.get("poison_power_display", stats.get("damage", 0))), int(stats.get("poison_ticks_display", stats.get("poison_ticks", 0)))]
	elif str(stats.get("kind", "")) in ["shackles", "silence", "rust"]:
		values = "Действует %d т. · Урон %d" % [int(stats.get("effect_turns", 0)), int(stats.get("impact_damage", 0))]
	else:
		values = "Урон %d" % int(stats.get("damage", 0))
	parent.add_child(_label(values, 13, PAPER, true))
	var description = _label(str(stats.get("role", stats.get("description", ""))), 13, MUTED, true)
	parent.add_child(description)
	if str(stats.get("evolution_path", "")) == "wraith_throne_guardian":
		parent.add_child(_label("У трона действует один самый сильный страж", 12, MUTED, true))
	var progression: Dictionary = game.room_progression(index)
	var path_names: PackedStringArray = []
	for stage in progression.get("stages", []):
		if bool(stage.get("chosen", false)):
			path_names.append(str(stage.get("name", stage.get("title", ""))))
	var path_text: String = "Ранги 2 / 5 / 15" if path_names.is_empty() else " / ".join(path_names)
	var next_tier: int = int(progression.get("next_tier", 0))
	if next_tier > 0 and not path_names.is_empty():
		path_text += "\nСледующий выбор: ранг %d" % next_tier
	var path = _button(path_text, _show_room_tree.bind(index, ""))
	path.add_theme_font_size_override("font_size", 12)
	path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path.tooltip_text = "Посмотреть путь и будущие развилки"
	parent.add_child(path)
	_room_evolution_controls(parent, index)
	_room_combo_details(parent, index)
	var pending: bool = _has_pending_evolution(index)
	var rank_limit: int = int(stats.get("max_rank", 0))
	var capped: bool = rank_limit > 0 and int(stats.get("rank", 1)) >= rank_limit
	var cost: int = game.upgrade_cost(index)
	var upgrade_label: String = "Улучшить · выбор без доплаты" if pending else "Максимальный ранг" if capped else "Улучшить · %d зол." % cost
	var upgrade_button = _button(upgrade_label, _upgrade, game.phase != "prepare" or (not pending and (capped or game.gold < cost)))
	upgrade_button.tooltip_text = _ui_text("Продолжить уже доступный выбор. Золото не списывается." if pending else "Повысить ранг. Доступный выбор усиления откроется сразу.")
	if not pending and not capped:
		upgrade_button.tooltip_text += _upgrade_savings_text(index)
		var savings: int = int(game.upgrade_price_details(index).saving)
		if savings > 0:
			parent.add_child(_label("Скидки навыков: −%d зол." % savings, 12, GREEN, true))
	parent.add_child(upgrade_button)
	_tutorial_mark(upgrade_button, "upgrade")
	parent.add_child(_button("Продать · +%d зол." % game.sell_value(index), _sell, game.phase != "prepare" or not tutorial.allows("sell")))

func _upgrade_savings_text(index: int) -> String:
	var details: Dictionary = game.upgrade_price_details(index)
	var lines: PackedStringArray = []
	for discount in details.discounts:
		if int(discount.saving) > 0:
			lines.append("%s: −%d зол." % [discount.name, discount.saving])
	return "\n" + "\n".join(lines) if not lines.is_empty() else ""


func _has_pending_evolution(index: int) -> bool:
	return index >= 0 and index < game.rooms.size() and not game.rooms[index].is_empty() and int(game.rooms[index].get("rank", 1)) >= 2 and not game.room_evolution_options(index).is_empty()


func _room_evolution_controls(parent: Control, index: int) -> void:
	if not game.has_method("room_evolution_controls"):
		return
	for control in game.room_evolution_controls(index):
		parent.add_child(_label(str(control.get("label", "")), 12, MUTED, true))
		var choice := OptionButton.new()
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.custom_minimum_size.y = 36
		choice.disabled = game.phase != "prepare"
		var options: Array = control.get("options", [])
		for option in options:
			choice.add_item(str(option.get("name", option.get("id", ""))))
			if str(option.get("id", "")) == str(control.get("selected", "")):
				choice.select(choice.item_count - 1)
		choice.item_selected.connect(func(option_index: int):
			var error: String = game.set_room_evolution_control(index, str(control.id), str(options[option_index].id))
			_action(error)
			if compact_ui and error.is_empty():
				_show_room_details())
		parent.add_child(choice)

func _shop_panel(parent: Control = null) -> void:
	var shop_area = _vbox(page if parent == null else parent, 7)
	shop_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header = _responsive_box()
	shop_area.add_child(header)
	var title = _eyebrow("МАГАЗИН")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var offer: Dictionary = game.deal_offer()
	if not offer.is_empty():
		_deal_card(header, offer)
	var row = GridContainer.new()
	row.columns = (2 if short_ui else 1) if compact_ui else maxi(1, game.shop.size())
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	shop_area.add_child(row)
	for id in game.shop:
		var definition: Dictionary = Content.room(str(id))
		var faction: Dictionary = Game.room_faction(str(id))
		var faction_color: Color = faction.get("color", MUTED)
		var stock: int = int(game.shop[id])
		var room_price: int = game.shop_room_cost(str(id))
		var button = Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 94 if compact_ui else 88
		button.disabled = game.phase != "prepare" or stock <= 0 or game.gold < room_price
		button.tooltip_text = _ui_text(str(definition.description))
		if room_price < int(definition.cost):
			button.tooltip_text += "\nСкидка навыков: %d зол." % (int(definition.cost) - room_price)
		button.pressed.connect(_select_shop.bind(str(id)))
		_style_faction_card(button, faction_color, selected_room == str(id))
		row.add_child(button)
		var margin = MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 9)
		button.add_child(margin)
		var contents = HBoxContainer.new()
		margin.add_child(contents)
		contents.add_child(_icon(str(definition.icon), 36))
		var text_col = _vbox(contents, 3)
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var room_name = _label(str(definition.name), 15 if compact_ui else 13, PAPER if not button.disabled else MUTED, compact_ui)
		room_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		room_name.max_lines_visible = 2 if compact_ui else 1
		text_col.add_child(room_name)
		var price: String = "%d зол. · %d шт." % [room_price, stock]
		if stock <= 0:
			price = "Раскуплено"
		elif game.gold < room_price:
			price += " · мало золота"
		text_col.add_child(_label(price, 12, GOLD if not button.disabled else MUTED, compact_ui))
		var role = _label(_room_role(definition), 12 if compact_ui else 10, MUTED, true)
		role.max_lines_visible = 2
		role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		text_col.add_child(role)
		_ignore_mouse(margin)
		margin.minimum_size_changed.connect(_fit_card_button.bind(button, margin))
		_fit_card_button.call_deferred(button, margin)
		_tutorial_mark(button, "shop:" + str(id))
		if tutorial.active() and tutorial.target() == "shop:" + str(id) and not button.disabled:
			_style_faction_card(button, faction_color, true)

func _room_role(definition: Dictionary) -> String:
	var role: String = str(definition.get("role", ""))
	if not role.is_empty():
		return role
	return str(definition.get("description", "")).get_slice(". ", 0)

func _footer() -> void:
	if game.phase == "camp":
		_camp_panel(page)
	var row = HBoxContainer.new()
	page.add_child(row)
	var desc = _label("Подготовка · Q: %d зол. за применение" % int(game.ability_status().get("gold_cost", 0)) if game.phase == "prepare" else "Защита действует автоматически", 13, MUTED, true)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc)
	if game.phase == "prepare":
		if selected_slot >= 0 or not selected_room.is_empty() or selecting_deal:
			row.add_child(_button("Снять выбор", _cancel_selection))
		var start = _button("НАЧАТЬ ВОЛНУ %d" % game.wave, _start)
		start.custom_minimum_size = Vector2(255, 42)
		start.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 8, 12))
		start.add_theme_color_override("font_color", INK)
		start.add_theme_color_override("font_hover_color", GOLD)
		row.add_child(start)
		_tutorial_mark(start, "start")
	elif game.phase in ["raid", "camp"]:
		row.add_child(_button("Продолжить" if paused else "Пауза", _toggle_pause))
		row.add_child(_button("x%d" % speed, _cycle_speed))
		if game.phase == "camp":
			desc.text = _ui_text("Пробел — пауза · E — сорвать привал")
			var interrupt = _camp_interrupt_button()
			interrupt.custom_minimum_size = Vector2(300, 42)
			row.add_child(interrupt)
			return
		var ability: Dictionary = game.ability_status()
		desc.text = _ui_text("Пробел — пауза · Q — сила Лорда" if bool(ability.can_cast) else str(ability.reason))
		var cast = _button("Q · %s · %d/%d" % [ability.name, ability.charges, ability.max_charges], _cast_lord_ability, not bool(ability.can_cast))
		_bind_ability_button(cast, true)
		cast.custom_minimum_size = Vector2(300, 42)
		cast.tooltip_text = _ui_text(str(ability.description) + "\n" + str(ability.reason))
		cast.add_theme_color_override("font_color", GREEN)
		row.add_child(cast)
		_tutorial_mark(cast, "ability")
	else:
		row.add_child(_button(_phase_action_text(), _show_phase_modal))

func _process(delta: float) -> void:
	var suspended: bool = paused or is_instance_valid(modal) or menu_open
	if is_instance_valid(soul_feedback):
		soul_feedback.paused = suspended
		soul_feedback.speed = float(speed)
	if is_instance_valid(dungeon_view):
		dungeon_view.animation_paused = suspended
	layout_poll += delta
	if layout_poll >= 0.5:
		layout_poll = 0.0
		if _screen_css_size() != layout_size:
			_request_screen_layout()
	if suspended or game.phase not in ["raid", "camp"]:
		return
	if game.phase == "camp":
		# Camp time is independent of combat ticks and never carries into a raid step.
		accumulator = 0.0
		game.advance_camp(delta * float(speed))
		if is_instance_valid(dungeon_view):
			if game.phase != "camp" or not game.combat_events.is_empty():
				# Consume events before advance_camp clears them next frame.
				dungeon_view.refresh_runtime()
			else:
				# Between healing pulses only the camp clock has changed.
				dungeon_view.refresh_camp_time()
		if game.phase != "camp":
			message = ""
			if game.phase != "raid":
				_sound("lose" if game.phase == "defeat" else "win")
				_update_record()
			_refresh()
		elif not game.combat_events.is_empty():
			_refresh_live_values()
		else:
			_refresh_camp_values()
		return
	accumulator += delta * float(speed)
	if accumulator >= 0.5:
		accumulator -= 0.5
		message = ""
		game.step()
		if game.phase == "raid":
			_sound("hit")
			_refresh_raid()
		else:
			accumulator = 0.0
			if is_instance_valid(dungeon_view):
				# A touch can defer _refresh; capture camp_start before the next frame.
				dungeon_view.refresh_runtime()
			if game.phase != "camp":
				_sound("lose" if game.phase == "defeat" else "win")
				_update_record()
			_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = true
		else:
			touch_points.erase(event.index)
			if touch_points.is_empty() and refresh_after_touch:
				_flush_touch_refresh.call_deferred()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11:
			_toggle_fullscreen()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB and modal_kind == "talents" and is_instance_valid(modal):
			modal.cycle_focus(event.shift_pressed)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Q or event.physical_keycode == KEY_Q:
			if not menu_open and not is_instance_valid(modal):
				_cast_lord_ability()
				get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_E or event.physical_keycode == KEY_E:
			if not menu_open and not is_instance_valid(modal):
				_interrupt_camp()
				get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_SPACE and not menu_open and game.phase in ["raid", "camp"] and not is_instance_valid(modal):
			_toggle_pause()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE:
			if is_instance_valid(modal):
				_modal_back()
			elif tutorial.active() and not menu_open:
				_open_menu()
			elif menu_open:
				if menu_section == "lords":
					_leave_lords()
				else:
					_resume_run()
			elif selected_slot >= 0 or not selected_room.is_empty() or selecting_deal:
				_cancel_selection()
			else:
				_open_menu()
			get_viewport().set_input_as_handled()

func _flush_touch_refresh() -> void:
	if refresh_after_touch and touch_points.is_empty():
		var keep_modal: bool = refresh_keeps_modal
		refresh_keeps_modal = false
		_refresh(keep_modal)

func _toggle_fullscreen() -> void:
	var window: Window = get_window()
	if window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]:
		window.mode = Window.MODE_WINDOWED
	else:
		window.mode = Window.MODE_FULLSCREEN

func _slot_clicked(index: int) -> void:
	if menu_open or is_instance_valid(modal) or game.phase != "prepare" or not _tutorial_allow("slot:" + str(index)):
		return
	if selecting_deal or not selected_room.is_empty():
		var error: String = game.buy_deal_room(index) if selecting_deal else game.buy_room(index, selected_room)
		if error.is_empty():
			tutorial.accepted("slot:" + str(index))
			selecting_deal = false
			selected_room = ""
			selected_slot = -1
			last_room_tap = -1
		_action(error)
		return
	var now: int = Time.get_ticks_msec()
	if compact_ui and selected_slot == index and not game.rooms[index].is_empty():
		var double_tap: bool = last_room_tap == index and now - last_room_tap_msec <= 550
		last_room_tap = index
		last_room_tap_msec = now
		if double_tap:
			last_room_tap = -1
			_show_room_details()
		return
	if selected_slot >= 0:
		if selected_slot == index:
			_cancel_selection()
		else:
			var error: String = game.move_room(selected_slot, index)
			if error.is_empty():
				selected_slot = -1
				last_room_tap = -1
			_action(error)
	elif not game.rooms[index].is_empty():
		selected_slot = index
		last_room_tap = index
		last_room_tap_msec = now
		tutorial.accepted("slot:" + str(index))
		_refresh()
	else:
		message = "Выберите комнату в магазине."
		_refresh()

func _select_shop(id: String) -> void:
	if not _tutorial_allow("shop:" + id):
		return
	_close_modal()
	selected_slot = -1
	last_room_tap = -1
	selecting_deal = false
	selected_room = id if tutorial.active() else ("" if selected_room == id else id)
	tutorial.accepted("shop:" + id)
	_sound("click")
	_refresh()

func _cancel_selection() -> void:
	if not _tutorial_allow("cancel"):
		return
	selected_slot = -1
	selected_room = ""
	selecting_deal = false
	message = ""
	_refresh()

func _upgrade() -> void:
	if not _tutorial_allow("upgrade"):
		return
	var index: int = selected_slot
	var from_tree: bool = modal_kind == "room_tree"
	if _has_pending_evolution(index):
		_show_specializations(index)
		return
	var error: String = game.upgrade_room(index)
	if error.is_empty():
		tutorial.accepted("upgrade")
	_close_modal()
	_action(error)
	if error.is_empty() and not game.room_evolution_options(index).is_empty():
		_show_specializations(index)
	elif from_tree:
		_show_room_tree(index)
	elif compact_ui and selected_slot >= 0:
		_show_room_details()

func _sell() -> void:
	if not _tutorial_allow("sell"):
		return
	var error: String = game.sell_room(selected_slot)
	if error.is_empty():
		selected_slot = -1
		last_room_tap = -1
	_close_modal()
	_action(error)

func _buy_floor() -> void:
	if not _tutorial_allow("floor"):
		return
	var error: String = game.buy_floor()
	if error.is_empty():
		tutorial.accepted("floor")
	_action(error)
	scroll_position = (game.floor_count - 1) * 160
	if is_instance_valid(floor_scroll):
		floor_scroll.set_deferred("scroll_vertical", scroll_position)

func _heal() -> void:
	if not _tutorial_allow("heal"):
		return
	_action(game.heal_lord())

func _cast_lord_ability() -> void:
	if menu_open or is_instance_valid(modal) or game.phase != "raid":
		return
	if not _tutorial_allow("ability"):
		return
	var error: String = game.cast_ability()
	message = error if not error.is_empty() else str(game.last_action.get("text", "Сила Лорда применена."))
	if error.is_empty():
		if tutorial.step == "ability":
			tutorial.accepted("ability")
			paused = false
			accumulator = 0.0
		_sound("hit")
		if game.phase not in ["raid", "camp"]:
			_update_record()
		if game.phase != "raid":
			accumulator = 0.0
	_refresh()

func _interrupt_camp() -> void:
	if menu_open or is_instance_valid(modal) or game.phase != "camp":
		return
	var error: String = game.interrupt_camp()
	if not error.is_empty():
		message = error
		_refresh_camp_values()
		return
	accumulator = 0.0
	message = "Привал сорван."
	for event in game.combat_events:
		if str(event.get("kind", "")) == "camp_interrupt":
			message = str(event.get("text", message))
			break
	if is_instance_valid(dungeon_view):
		dungeon_view.refresh_runtime()
	_sound("click")
	_refresh()


func _start() -> void:
	if menu_open or is_instance_valid(modal) or game.phase != "prepare":
		return
	if not _tutorial_allow("start"):
		return
	selected_slot = -1
	selected_room = ""
	selecting_deal = false
	active_floor = -1
	paused = false
	accumulator = 0.0
	var error: String = game.start_raid()
	if error.is_empty():
		tutorial.accepted("start")
	_action(error)

func _action(error: String) -> void:
	message = error if not error.is_empty() else ""
	_sound("click")
	_refresh()

func _set_speed(value: int) -> void:
	if not _tutorial_allow("speed"):
		return
	speed = value
	_save_settings()
	_refresh()

func _toggle_pause() -> void:
	if menu_open or is_instance_valid(modal) or game.phase not in ["raid", "camp"]:
		return
	if not _tutorial_allow("pause"):
		return
	paused = not paused
	_refresh()

func _toggle_sound() -> void:
	sound_on = not sound_on
	_save_settings()
	_sound("click")
	_refresh()

func _show_phase_modal() -> void:
	if menu_open or game.phase not in ["result", "level_up", "floor_choice", "defeat", "blueprint", "relic"]:
		return
	phase_modal_dismissed = false
	if game.phase == "level_up":
		game.defer_talents()
		return
	_close_modal()
	var content = _new_modal(940 if game.phase == "level_up" else 640)
	modal_kind = "reward"
	if game.phase in ["blueprint", "relic"]:
		var is_blueprint: bool = game.phase == "blueprint"
		content.add_child(_eyebrow("НАГРАДА ЗА РУБЕЖ"))
		content.add_child(_label("Новый чертёж" if is_blueprint else "Древняя реликвия", 28, GOLD))
		content.add_child(_label("Выберите комнату для магазина этого забега. Она появится в ближайшем предложении." if is_blueprint else "Выберите одно правило, которое усилит вашу сборку до конца забега.", 14, MUTED, true))
		var options: Array = game.blueprint_options() if is_blueprint else game.relic_options()
		for option in options:
			var card = _panel(content)
			var body = _vbox(card, 6)
			var title = HBoxContainer.new()
			body.add_child(title)
			var icon_path: String = str(option.get("icon", ""))
			if not icon_path.is_empty():
				title.add_child(_icon(icon_path, 32))
			var name_label = _label(str(option.name), 19, PAPER, true)
			name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			title.add_child(name_label)
			body.add_child(_label(str(option.description), 14, MUTED, true))
			var choose = _button("ВЫБРАТЬ", _choose_run_reward.bind(str(option.id), is_blueprint))
			body.add_child(choose)
			_tutorial_mark(choose, "choice")
	elif game.phase == "floor_choice":
		content.add_child(_eyebrow("НОВЫЙ ЭТАЖ · НОВЫЕ ВОЗМОЖНОСТИ"))
		content.add_child(_label("Выберите свойство этажа", 26, GOLD))
		content.add_child(_label("Свойство влияет на пять комнат этого этажа и сохраняется до конца забега.", 14, MUTED, true))
		for option in game.floor_trait_options():
			var floor_choice = _button(str(option.name), _choose_floor.bind(str(option.id)))
			content.add_child(floor_choice)
			_tutorial_mark(floor_choice, "choice")
			content.add_child(_label(str(option.description), 13, MUTED, true))
	elif game.phase == "result":
		content.add_child(_eyebrow("ПОДЗЕМЕЛЬЕ УСТОЯЛО"))
		content.add_child(_label("Волна %d отражена" % game.wave, 30, GOLD))
		content.add_child(_label("Герои стали частью вашей истории.", 15, MUTED))
		content.add_child(_label("Убито: %d   ·   Золото: +%d   ·   XP: +%d" % [game.report.get("killed", 0), game.report.get("gold", 0), game.report.get("xp", 0)], 17, PAPER, true))
		content.add_child(_label("Здоровье Лорда: %d / %d" % [game.lord.hp, game.lord.max_hp], 15, GOLD))
		content.add_child(_label("Урон Лорду: %d HP\nГерои получили: %d уровней и %d предметов" % [game.report.get("lord_damage", 0), game.report.get("hero_levels", 0), game.report.get("items", 0)], 14, MUTED, true))
		content.add_child(_label("Комнаты восстановлены. Золото и этажи остаются с вами.", 14, MUTED, true))
		content.add_child(_label("Души за волну: +%d · в запасе: %d" % [game.report.get("souls", 0), game.run_souls], 15, VIOLET, true))
		content.add_child(_label("Кнопка «Навыки» доступна в подготовке. Можно потратить души или сохранить их.", 13, MUTED, true))
		var unlock: String = str(game.report.get("unlock", ""))
		if not unlock.is_empty():
			for entry in game.unlock_catalog():
				if str(entry.id) == unlock:
					content.add_child(_label("ОТКРЫТА ВЕТКА: " + str(entry.name), 19, GREEN, true))
					content.add_child(_label(str(entry.description), 14, MUTED, true))
					content.add_child(_label("Сохраняется между забегами", 12, VIOLET))
		var continue_button = _button("ПРОДОЛЖИТЬ", _next_wave)
		content.add_child(continue_button)
		_tutorial_mark(continue_button, "continue")
	else:
		if game.tutorial_run:
			content.add_child(_label("Попробуем ещё раз?", 28, GOLD))
			content.add_child(_label("Учебный забег не меняет рекорды, Печати и постоянные открытия.", 15, MUTED, true))
			content.add_child(_button("Повторить обучение", _begin_tutorial))
			content.add_child(_button("Начать обычную игру", _skip_tutorial))
			return
		content.add_theme_constant_override("separation", 12)
		content.add_child(_eyebrow("ТРОН ПАЛ"))
		content.add_child(_label("Каждое подземелье\nоставляет легенду.", 30, GOLD))
		content.add_child(_label("Пережито волн: %d\nУбито героев: %d\nЭтажей: %d  ·  Уровень Лорда: %d" % [game.cleared_waves, game.total_kills, game.floor_count, game.lord.level], 18, PAPER))
		content.add_child(_label("Рекорд: %d волн. Следующая крепость будет сильнее." % int(profile.get("wave", 0)), 14, MUTED, true))
		var reward: Dictionary = last_run_reward if run_reward_claimed else _pending_run_reward()
		content.add_child(_label("+%d ПЕЧАТЕЙ ВЛАДЫКИ" % int(reward.get("total", 0)), 23, VIOLET))
		content.add_child(_label(_reward_details(reward), 12, MUTED, true))
		content.add_child(_button("Лорды · открыть и улучшить", _open_lords))
		content.add_child(_button("Навыки этого забега", _show_talents))
		content.add_child(_button("НОВОЕ ПОДЗЕМЕЛЬЕ", _restart))
		content.add_child(_button("Главное меню", _open_menu))

func _show_help() -> void:
	_close_modal()
	var content = _new_modal(650, true)
	content.add_child(_label("Справочник", 27, GOLD))
	for id in Content.hero_ids():
		var hero: Dictionary = Content.hero(str(id))
		_disclosure(content, str(hero.name), str(hero.get("trait", "")))
	_disclosure(content, "Типы угроз", "Телесные существа уязвимы к рыцарю и варвару. Духи — к чародею. Следопыт ослабляет все ловушки и первый удар засад. Жрица защищает группу от яда. Бард усиливает весь отряд. Признаки комнаты указаны в её подсказке.")
	_disclosure(content, "Навыки и души", "Души иногда сохраняются после гибели героев. После двух неудач следующая награда гарантирована. Кнопка «Навыки» открывает общее дерево: один узел — одна покупка за забег. Покупать можно в подготовке; в бою и на привале карта ставит игру на паузу, закрытие возвращает прежнюю паузу. Души и дерево сбрасываются после забега, Печати Владыки сохраняются.")
	_disclosure(content, "Способность Q", "Два заряда на волну. Каждое применение стоит половину базового дохода этой волны, без бонусов заработка. Цена видна заранее и не меняется в бою; неудачное нажатие ничего не списывает.")
	_disclosure(content, "Босс-отряд", "Каждые 25 волн приходит «Босс: Клятва пяти»: пять разных классов. Состав, индивидуальные HP и снаряжение заранее видны в разведке.")
	_disclosure(content, "Привал и E", "После непустого этажа раненые герои отдыхают. Таймер, оставшиеся порции и возможное лечение показаны у кнопки E. Пауза, меню и окна останавливают отдых. E за золото отменяет оставшееся лечение текущего привала и работает на паузе. Лимита зарядов нет: первое успешное применение за волну стоит 25% базового дохода, следующие — 50%. Неудача ничего не списывает. Q на привале недоступна.")
	_disclosure(content, "Управление", "Магазин > пустое место. Комната > другой слот для переноса. Пробел — пауза, Q — сила Лорда, E — сорвать текущий привал, Esc — меню, F11 — полный экран.")
	_disclosure(content, "Улучшение комнат", "Нажмите «Улучшить» в сведениях о комнате. Первый выбор усиления откроется сразу после прокачки; следующие - на рангах 5 и 15. На телефоне сведения открываются двойным нажатием. После «Назад» тот же выбор доступен без доплаты.")
	content.add_child(_button("Пройти обучение в игре", _request_tutorial))


func _percent(value: float) -> String:
	var amount: int = roundi(value * 100.0)
	return ("+" if amount > 0 else "") + str(amount) + "%"


func _tree_footer() -> VBoxContainer:
	modal_footer = _vbox(modal_frame, 6)
	modal_footer.minimum_size_changed.connect(_resize_modal)
	modal_footer.add_child(HSeparator.new())
	return modal_footer

func _tree_badge(text: String) -> void:
	var badge = _label(text, 13, GOLD, true)
	badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	modal_frame.get_child(0).add_child(badge)

func _restore_tree_position(scroll: ScrollContainer, offset: int, tree: Control, focused_id: String) -> void:
	# Card heights settle after their container has assigned the available width.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(scroll) or scroll != modal_scroll:
		return
	if is_instance_valid(tree):
		tree.focus_node(focused_id)
	if offset >= 0:
		scroll.set_deferred("scroll_vertical", offset)

func _tree_details(body: Control, footer: Control, title: String, description: String, detail: String = "", warning: String = "") -> void:
	# On short screens only the action stays fixed; all explanatory text scrolls.
	var host: Control = body if get_viewport_rect().size.y < 500.0 else footer
	var panel = _panel(host)
	var info = _vbox(panel, 4)
	info.add_child(_label(title, 18, GOLD, true))
	if not description.is_empty():
		info.add_child(_label(description, 13, PAPER, true))
	if not warning.is_empty():
		info.add_child(_label(warning, 12, RED, true))
	if not detail.is_empty():
		info.add_child(_label(detail, 12, GREEN, true))

func _tree_action(parent: Control, title: String, callback: Callable, disabled: bool = false) -> Button:
	var button = _button(title, callback, disabled)
	button.custom_minimum_size.y = 46
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 8, 9))
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", PAPER)
	parent.add_child(button)
	return button

func _find_tree_node(nodes: Array[Dictionary], id: String) -> Dictionary:
	for node in nodes:
		if str(node.id) == id:
			return node
	return {}


func _show_talents(focused_id: String = "") -> void:
	if not focused_id.is_empty():
		talent_tree_focus = focused_id
	if modal_kind == "talents" and is_instance_valid(modal):
		if focused_id.is_empty():
			talent_tree_focus = modal.selected_id
		modal.configure(game.run_skill_tree(), game.run_souls, game.phase, talent_tree_focus)
		modal.configure_drop_info(game.soul_drop_probabilities(false), game.soul_drop_probabilities(true), game.soul_failures)
		return
	_close_modal()
	var previous_focus: Control = get_viewport().gui_get_focus_owner()
	run_skill_previous_focus = weakref(previous_focus) if is_instance_valid(previous_focus) else null
	run_skill_pause_before = paused
	run_skill_pause_owned = true
	paused = true
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.035, 0.05, 0.96)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal_shade)
	modal = RunSkillScreen.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.offset_left = 10
	modal.offset_top = 10
	modal.offset_right = -10
	modal.offset_bottom = -10
	modal_shade.add_child(modal)
	modal_kind = "talents"
	modal.configure(game.run_skill_tree(), game.run_souls, game.phase, talent_tree_focus)
	modal.configure_drop_info(game.soul_drop_probabilities(false), game.soul_drop_probabilities(true), game.soul_failures)
	modal.close_requested.connect(_modal_back)
	modal.purchase_requested.connect(_buy_run_skill)
	modal.focus_default.call_deferred()
	if not run_skill_camera.is_empty():
		modal.map.restore_camera(float(run_skill_camera.zoom), run_skill_camera.pan)
	_refresh_live_values()

func _new_modal(width: int = 560, compact: bool = false) -> VBoxContainer:
	modal_width = width
	modal_is_compact = compact
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.035, 0.05, 0.88)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal_shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_shade.add_child(center)
	modal = PanelContainer.new()
	center.add_child(modal)
	modal_frame = _vbox(modal, 8)
	var navigation = HBoxContainer.new()
	modal_frame.add_child(navigation)
	var back = _button("Назад", _modal_back)
	back.custom_minimum_size.x = 76
	navigation.add_child(back)
	_focus_modal_control.call_deferred(weakref(back))
	modal_scroll = ScrollContainer.new()
	modal_scroll.follow_focus = true
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.scroll_deadzone = 12
	modal_frame.add_child(modal_scroll)
	modal_content = _vbox(modal_scroll, 14)
	modal_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tutorial.active() and not menu_open:
		_tutorial_banner(modal_content)
	elif tutorial.active():
		modal_content.add_child(_button("Пропустить обучение", _skip_tutorial))
	modal_content.minimum_size_changed.connect(_resize_modal)
	_resize_modal()
	_resize_modal.call_deferred()
	return modal_content


func _focus_modal_control(reference: WeakRef) -> void:
	var control: Control = reference.get_ref() as Control
	# A modal can close before the deferred focus request reaches the next frame.
	if is_instance_valid(control) and control.is_inside_tree() and control.is_visible_in_tree() and not control.is_queued_for_deletion():
		control.grab_focus()


func _resize_modal() -> void:
	if not is_instance_valid(modal) or not is_instance_valid(modal_content):
		return
	var available: Vector2 = get_viewport_rect().size
	# Fullscreen puts the canvas outside the HTML safe-area frame. Modal windows
	# use the same extra insets as the main page, including on a rotated phone.
	var base_margin: int = 6 if compact_ui else 20
	var safe_left: int = maxi(0, shell_margin.get_theme_constant("margin_left") - base_margin)
	var safe_right: int = maxi(0, shell_margin.get_theme_constant("margin_right") - base_margin)
	var safe_top: int = maxi(0, shell_margin.get_theme_constant("margin_top") - base_margin)
	var safe_bottom: int = maxi(0, shell_margin.get_theme_constant("margin_bottom") - base_margin)
	var center: Control = modal.get_parent()
	center.offset_left = safe_left
	center.offset_right = -safe_right
	center.offset_top = safe_top
	center.offset_bottom = -safe_bottom
	available -= Vector2(safe_left + safe_right, safe_top + safe_bottom)
	var padding: int = 12 if compact_ui else 28
	var width: float = minf(float(modal_width), available.x - 16.0)
	modal.custom_minimum_size.x = width
	if int(modal.get_meta("layout_padding", -1)) != padding:
		modal.set_meta("layout_padding", padding)
		modal.add_theme_stylebox_override("panel", _style(PANEL, Color("#756143"), 12 if compact_ui else 16, padding))
	var fixed_height: float = 0.0
	for child in modal_frame.get_children():
		if child != modal_scroll and child is Control and child.visible:
			fixed_height += child.get_combined_minimum_size().y
	fixed_height += modal_frame.get_theme_constant("separation") * maxi(0, modal_frame.get_child_count() - 1)
	var height_limit: float = maxf(32.0, minf(560.0, available.y - padding * 2 - fixed_height - 20.0))
	var content_height: float = modal_content.get_combined_minimum_size().y
	modal_scroll.custom_minimum_size = Vector2(maxf(0.0, width - padding * 2), clampf(content_height, minf(80.0, height_limit), height_limit) if modal_is_compact else height_limit)

func _adapt_modal_controls(node: Node) -> void:
	if node.has_meta("progression_tree"):
		return
	if node is BoxContainer and node.has_meta("responsive_box"):
		node.vertical = compact_ui
	if node is GridContainer and node.has_meta("party_overview"):
		node.columns = _party_overview_columns()
	elif node is GridContainer and node.has_meta("responsive_columns"):
		node.columns = 1 if compact_ui else int(node.get_meta("responsive_columns"))
	if node is Label and node.has_meta("original_font_size"):
		var original: int = int(node.get_meta("original_font_size"))
		node.add_theme_font_size_override("font_size", clampi(original, 13, 24) if compact_ui else original)
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if compact_ui or bool(node.get_meta("original_wrap", false)) else TextServer.AUTOWRAP_OFF
		if compact_ui:
			node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if node is Button:
		node.custom_minimum_size.y = maxf(node.custom_minimum_size.y, 44.0 if compact_ui else 0.0)
		node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if compact_ui else TextServer.AUTOWRAP_OFF
	for child in node.get_children():
		_adapt_modal_controls(child)

func _fit_compact_modal(scroll: ScrollContainer, content: VBoxContainer) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(content):
		return
	var height_limit: float = minf(520.0, get_viewport_rect().size.y - (44.0 if compact_ui else 160.0))
	scroll.custom_minimum_size.y = clampf(content.get_combined_minimum_size().y, 80.0, maxf(80.0, height_limit))

func _close_modal() -> void:
	if modal_kind == "talents" and is_instance_valid(modal):
		talent_tree_focus = modal.selected_id
		run_skill_camera = {"zoom": modal.map.zoom, "pan": modal.map.pan}
		_restore_skill_focus.call_deferred()
	if run_skill_pause_owned:
		paused = run_skill_pause_before
		run_skill_pause_owned = false
	if is_instance_valid(modal_shade):
		remove_child(modal_shade)
		modal_shade.queue_free()
	modal = null
	modal_shade = null
	modal_scroll = null
	modal_content = null
	modal_frame = null
	modal_footer = null
	modal_kind = ""

func _restore_skill_focus() -> void:
	if is_instance_valid(modal):
		return
	var previous: Control = run_skill_previous_focus.get_ref() if run_skill_previous_focus != null else null
	run_skill_previous_focus = null
	if is_instance_valid(previous) and previous.is_inside_tree() and previous.is_visible_in_tree():
		previous.grab_focus()
	elif not menu_open and is_instance_valid(skill_wallet_button) and skill_wallet_button.is_inside_tree():
		skill_wallet_button.grab_focus()


func _modal_back() -> void:
	if modal_kind == "talents" and game.phase == "level_up":
		var error: String = game.defer_talents()
		if not error.is_empty():
			message = error
			return
		phase_modal_dismissed = false
		_close_modal()
		_refresh()
		return
	if game.phase in ["result", "level_up", "floor_choice", "defeat", "blueprint", "relic"]:
		phase_modal_dismissed = true
	_close_modal()
	_refresh(true)

func _phase_action_text() -> String:
	match str(game.phase):
		"result":
			return "Итоги волны"
		"defeat":
			return "Итоги забега"
		"floor_choice":
			return "Выбрать свойство этажа"
		"level_up":
			return "Навыки · душ: %d" % game.run_souls
		_:
			return "Выбрать награду"

func _next_wave() -> void:
	phase_modal_dismissed = false
	_close_modal()
	var error: String = game.next_wave()
	if error.is_empty():
		tutorial.accepted("continue")
	_action(error)

func _show_soul_feedback(origin: Vector2, amount: int) -> void:
	if not is_instance_valid(soul_feedback) or not is_instance_valid(skill_wallet_button):
		return
	var target: Vector2 = skill_wallet_button.get_global_rect().get_center()
	soul_feedback.show_soul(origin, target, amount)

func _buy_run_skill(id: String) -> void:
	var bought: bool = game.buy_run_skill(id)
	var state: Dictionary = game.run_skill_state(id)
	message = "Изучен навык: %s" % str(state.get("name", id)) if bought else str(state.get("reason", "Не удалось изучить навык"))
	if bought:
		_sound("click")
	talent_tree_focus = id
	_refresh(true)
	_show_talents(id)


func _restart() -> void:
	_begin_run()

func _update_record() -> void:
	if demo_mode or not screenshot_path.is_empty() or game.tutorial_run:
		return
	if game.phase == "defeat":
		_settle_run()
	var previous: int = int(profile.get("wave", 0))
	var kills: int = int(profile.get("kills", 0))
	if game.cleared_waves > previous or (game.cleared_waves == previous and game.total_kills > kills):
		profile.wave = game.cleared_waves
		profile.kills = game.total_kills
	profile.floors = maxi(int(profile.get("floors", 1)), game.floor_count)
	profile.level = maxi(int(profile.get("level", 1)), int(game.lord.level))
	profile["unlocked_paths"] = game.unlocked_paths.duplicate()
	_save_profile()

func _save_profile() -> void:
	if demo_mode or not screenshot_path.is_empty():
		return
	profile["lords"] = lords_profile.duplicate(true)
	_write_json("user://profile.json", profile)

func _pending_run_reward() -> Dictionary:
	if game.tutorial_run:
		return {"total": 0, "waves": 0, "kills": 0, "elites": 0, "milestones": 0}
	return LordProgression.reward(game.cleared_waves, game.total_kills, run_best_at_start)

func _settle_run() -> void:
	if not has_run or run_reward_claimed or demo_mode or not screenshot_path.is_empty() or game.tutorial_run:
		return
	last_run_reward = _pending_run_reward()
	lords_profile.souls = int(lords_profile.souls) + int(last_run_reward.total)
	run_reward_claimed = true

func _reward_details(reward: Dictionary) -> String:
	return "Волны: %d · герои: %d · особые отряды: %d · новые рубежи: %d" % [reward.get("waves", 0), reward.get("kills", 0), reward.get("elites", 0), reward.get("milestones", 0)]

func _configure_selected_lord(target) -> void:
	var id: String = str(lords_profile.selected)
	target.configure_lord(id, LordProgression.mastery(lords_profile, id), LordProgression.variant(lords_profile, id))

func _load_local() -> void:
	var loaded: Dictionary = _read_json("user://profile.json")
	for key in ["tutorial_completed", "tutorial_skipped"]:
		profile[key] = loaded.get(key, false) == true
	for key in ["wave", "kills", "floors", "level"]:
		if typeof(loaded.get(key)) in [TYPE_INT, TYPE_FLOAT]:
			profile[key] = maxi(0, int(loaded[key]))
	profile["unlocked_paths"] = []
	if loaded.get("unlocked_paths", []) is Array:
		for unlock in loaded.get("unlocked_paths", []):
			if unlock in ["ambush", "plague"] and not profile.unlocked_paths.has(unlock):
				profile.unlocked_paths.append(unlock)
	lords_profile = LordProgression.sanitize(loaded.get("lords", {}))
	inspected_lord = str(lords_profile.selected)
	var settings: Dictionary = _read_json("user://settings.json")
	sound_on = bool(settings.get("sound", true))
	volume = clampf(float(settings.get("volume", 0.65)), 0.0, 1.0)
	speed = int(settings.get("speed", 1))
	if speed not in [1, 2, 4]:
		speed = 1

func _save_settings() -> void:
	_write_json("user://settings.json", {"schema_version": 1, "sound": sound_on, "speed": tutorial_saved_speed if game.tutorial_run else speed, "volume": volume})

func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary and data.get("schema_version", 0) == 1:
		return data
	return {}

func _write_json(path: String, data: Dictionary) -> void:
	data["schema_version"] = 1
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func _make_sound(kind: String) -> AudioStreamWAV:
	var stream = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 22050
	var duration: float = 0.065 if kind == "click" else 0.1
	if kind in ["win", "lose"]:
		duration = 0.4
	var count: int = int(22050 * duration)
	var bytes = PackedByteArray()
	bytes.resize(count * 2)
	var freq: float = 440.0
	if kind == "hit":
		freq = 130.0
	if kind == "win":
		freq = 660.0
	if kind == "lose":
		freq = 180.0
	for i in range(count):
		var t: float = float(i) / 22050.0
		var envelope: float = pow(1.0 - float(i) / count, 2.0)
		var sample: int = int(sin(TAU * freq * t) * envelope * 2200.0)
		bytes.encode_s16(i * 2, sample)
	stream.data = bytes
	return stream

func _sound(kind: String) -> void:
	if sound_on and is_instance_valid(audio_player):
		audio_player.volume_db = linear_to_db(maxf(volume, 0.001))
		audio_player.stream = sounds[kind]
		audio_player.play()

func _style(bg: Color, border: Color, radius: int = 8, padding: int = 12) -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func _panel(parent: Control, min_width: int = 0) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size.x = 0 if compact_ui else min_width
	panel.add_theme_stylebox_override("panel", _style(PANEL, LINE, 10, 8 if compact_ui else 14))
	parent.add_child(panel)
	return panel

func _vbox(parent: Control, spacing: int = 8) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	parent.add_child(box)
	return box

func _ui_text(value: String) -> String:
	var replacements: Dictionary = {
		"\u2192": ">", "\u2190": "<", "\u2194": "<>", "\u2197": "",
		"\u25b8": "+", "\u25be": "-", "\u25c7": "", "\u2713": "*",
		"\u00d7": "x", "\u2212": "-", "\u2264": "<=", "\u2265": ">=",
		"\ufe0f": "", "\ufe0e": "", "\u200b": "",
	}
	for source in replacements:
		value = value.replace(str(source), str(replacements[source]))
	return value

func _label(text: String, font_size: int = 15, color: Color = PAPER, wrap: bool = false) -> Label:
	var label = Label.new()
	label.text = _ui_text(text)
	label.set_meta("original_font_size", font_size)
	label.set_meta("original_wrap", wrap)
	label.add_theme_font_size_override("font_size", clampi(font_size, 13, 24) if compact_ui else font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap or compact_ui:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if compact_ui:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _eyebrow(text: String) -> Label:
	return _label(text, 10, GOLD)

func _button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button = Button.new()
	button.text = _ui_text(text)
	button.disabled = disabled
	if compact_ui:
		button.custom_minimum_size = Vector2(44, 44)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 14)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if callback.is_valid():
		button.pressed.connect(callback)
	return button

func _fit_card_button(button: Button, contents: Control) -> void:
	if is_instance_valid(button) and is_instance_valid(contents):
		button.custom_minimum_size.y = maxf(88.0, contents.get_combined_minimum_size().y)

func _icon(path: String, dimension: int) -> TextureRect:
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(dimension, dimension)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not path.is_empty() and ResourceLoader.exists(path):
		icon.texture = load(path)
	return icon

func _bar(value: float, max_value: float, tint: Color, height: int = 7) -> ProgressBar:
	var bar = ProgressBar.new()
	bar.custom_minimum_size.y = height
	bar.max_value = maxf(1.0, max_value)
	bar.value = maxf(0.0, value)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_theme_stylebox_override("fill", _style(tint, Color.TRANSPARENT, 3, 0))
	return bar

func _stat(parent: Control, title: String, value: String, tint: Color, read: Callable = Callable()) -> void:
	var box = VBoxContainer.new()
	box.custom_minimum_size.x = 78
	box.add_theme_constant_override("separation", 1)
	parent.add_child(box)
	box.add_child(_label(title, 10, MUTED))
	box.add_child(_label(value, 27, tint) if not read.is_valid() else _live_label(read, 27, tint))

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)

func _make_demo() -> void:
	_fill_showcase(game)
	message = "Лаборатория продлевает яд. Мастерская усиливает ловушки."
	game.gold = 100
	game.upgrade_room(10)
	game.specialize_room(10, "volley")
	game.upgrade_room(5)
	game.specialize_room(5, "lingering")
	game.gold = 27

func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output = get_viewport().get_texture().get_image()
	output.save_png(screenshot_path)
	get_tree().quit()
func _build_mobile_menu() -> void:
	var header = HBoxContainer.new()
	page.add_child(header)
	var brand = _label("NO HERO RETURNS", 20, GOLD)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(brand)
	var record = _label("Рекорд %d" % int(profile.get("wave", 0)), 13, MUTED)
	record.custom_minimum_size.x = 80
	header.add_child(record)
	page.add_child(_label("ПОХОД ГЕРОЕВ · " + str(ProjectSettings.get_setting("application/config/version", "2.1.1")), 10, MUTED))
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_track_scroll(scroll, "menu")
	var columns = BoxContainer.new()
	columns.vertical = not short_ui
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 14)
	scroll.add_child(columns)
	var selected: Dictionary = Lords.get_lord(str(lords_profile.selected))
	var introduction = _panel(columns)
	introduction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if short_ui:
		introduction.size_flags_stretch_ratio = 0.7
	var intro = _vbox(introduction, 8)
	var identity = HBoxContainer.new()
	intro.add_child(identity)
	identity.add_child(_icon(str(selected.icon), 58))
	var motto = _label("Ваш трон.\nИх последний рейд.", 23, PAPER, true)
	motto.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_child(motto)
	intro.add_child(_label(str(selected.name) + " · мастерство %d/5" % LordProgression.mastery(lords_profile, str(selected.id)), 15, GOLD, true))
	intro.add_child(_label("Стройте защиту. В бой вступайте силой Лорда.", 14, MUTED, true))
	intro.add_child(_label("Печати Владыки: %d" % int(lords_profile.souls), 14, VIOLET))
	var actions = _vbox(columns, 8)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if has_run and game.phase != "defeat":
		actions.add_child(_button("Назад к подземелью", _resume_run))
	var first_lesson: bool = not bool(profile.get("tutorial_completed", false)) and not bool(profile.get("tutorial_skipped", false))
	var lesson = _button("НАУЧИТЬСЯ ИГРАЯ" if first_lesson else "Обучение · сыграть с подсказками", _request_tutorial)
	var start = _button("НОВОЕ ПОДЗЕМЕЛЬЕ", _request_new_run)
	var primary: Button = lesson if first_lesson else start
	primary.custom_minimum_size.y = 50
	primary.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 8, 10))
	primary.add_theme_color_override("font_color", INK)
	if first_lesson:
		actions.add_child(lesson)
	actions.add_child(start)
	if not first_lesson:
		actions.add_child(lesson)
	if tutorial.active():
		actions.add_child(_button("Пропустить обучение", _skip_tutorial))
	var links = GridContainer.new()
	links.columns = 2
	links.add_theme_constant_override("h_separation", 8)
	links.add_theme_constant_override("v_separation", 8)
	actions.add_child(links)
	for item in [["Лорды", _open_lords], ["Коллекция", _show_collection], ["Как играть", _show_help], ["Настройки", _show_settings]]:
		var button = _button(str(item[0]), item[1])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		links.add_child(button)
	if not OS.has_feature("web"):
		actions.add_child(_button("Выйти из игры", _quit_game))
	actions.add_child(_label("Покупайте этажи, собирайте комбо и переживите следующую волну.", 13, MUTED, true))

func _build_mobile_lords() -> void:
	var header = HBoxContainer.new()
	page.add_child(header)
	var title = _label("Лорды · %d печатей" % int(lords_profile.souls), 22, GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back = _button("Назад", _leave_lords)
	back.custom_minimum_size.x = 72
	header.add_child(back)
	var roster = GridContainer.new()
	roster.columns = 3
	roster.add_theme_constant_override("h_separation", 5)
	page.add_child(roster)
	for id in Lords.ids():
		var definition: Dictionary = Lords.get_lord(id)
		var label: String = str(definition.name)
		if str(lords_profile.selected) == id:
			label += " *"
		var button = _button(label, _inspect_lord.bind(id))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 54
		button.add_theme_font_size_override("font_size", 13)
		button.add_theme_stylebox_override("normal", _style(TILE, Color(str(definition.color)) if inspected_lord == id else LINE, 8, 6))
		roster.add_child(button)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_track_scroll(scroll, "lords")
	var details = _vbox(scroll, 12)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not lord_message.is_empty():
		details.add_child(_label(lord_message, 14, VIOLET, true))
	_lord_details(details, inspected_lord)
	details.add_child(_label("Печати Владыки за завершённые забеги открывают Лордов и мастерство. Изменения применятся в новом забеге.", 13, MUTED, true))
	var selected: Dictionary = Lords.get_lord(str(lords_profile.selected))
	page.add_child(_button("В БОЙ · %s" % str(selected.name), _request_new_run))

func _build_menu() -> void:
	var topline = HBoxContainer.new()
	page.add_child(topline)
	var edition = _eyebrow("NO HERO RETURNS     /     ПОХОД ГЕРОЕВ · " + str(ProjectSettings.get_setting("application/config/version", "2.1.1")))
	edition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topline.add_child(edition)
	topline.add_child(_label("ПЕЧАТИ  %d" % int(lords_profile.souls), 12, VIOLET))
	topline.add_child(_label("РЕКОРД  %d ВОЛН" % int(profile.get("wave", 0)), 12, GOLD))
	var main_row = HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 32)
	page.add_child(main_row)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 390
	left.add_theme_constant_override("separation", 10)
	var menu_scroll = ScrollContainer.new()
	menu_scroll.custom_minimum_size.x = 410
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_row.add_child(menu_scroll)
	menu_scroll.add_child(left)
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 8
	left.add_child(spacer)
	var selected: Dictionary = Lords.get_lord(str(lords_profile.selected))
	var crown = _icon(str(selected.icon), 64)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(crown)
	left.add_child(_label("ВАШ ТРОН.\nВАШЕ ПОДЗЕМЕЛЬЕ.\nИХ ПОСЛЕДНИЙ РЕЙД.", 29, PAPER))
	var intro = _label("Стройте глубже. Командуйте защитой.\nВмешивайтесь в бой силой своего Лорда.", 14, MUTED, true)
	intro.custom_minimum_size.y = 44
	left.add_child(intro)
	var lords_button = _button("ЛОРДЫ · %s" % str(selected.name), _open_lords)
	lords_button.custom_minimum_size.y = 44
	lords_button.add_theme_color_override("font_color", VIOLET)
	left.add_child(lords_button)
	if has_run and game.phase != "defeat":
		var resume = _button("Назад к подземелью", _resume_run)
		resume.custom_minimum_size.y = 38
		left.add_child(resume)
	var start = _button("НОВОЕ ПОДЗЕМЕЛЬЕ", _request_new_run)
	start.custom_minimum_size.y = 46
	start.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 5, 12))
	start.add_theme_color_override("font_color", INK)
	var first_lesson: bool = not bool(profile.get("tutorial_completed", false)) and not bool(profile.get("tutorial_skipped", false))
	var lesson = _button("НАУЧИТЬСЯ ИГРАЯ" if first_lesson else "Обучение · сыграть с подсказками", _request_tutorial)
	lesson.custom_minimum_size.y = 42
	if first_lesson:
		lesson.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 5, 10))
		lesson.add_theme_color_override("font_color", INK)
		start.add_theme_stylebox_override("normal", _style(TILE, LINE, 8, 10))
		start.add_theme_color_override("font_color", PAPER)
		left.add_child(lesson)
	left.add_child(start)
	if not first_lesson:
		left.add_child(lesson)
	if tutorial.active():
		left.add_child(_button("Пропустить обучение", _skip_tutorial))
	var actions = HBoxContainer.new()
	left.add_child(actions)
	actions.add_child(_button("Коллекция", _show_collection))
	actions.add_child(_button("Как играть", _show_help))
	actions.add_child(_button("Настройки", _show_settings))
	left.add_child(_button("Выйти из игры", _quit_game))
	var preview_box = _panel(main_row)
	preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preview_col = _vbox(preview_box, 10)
	preview_col.add_child(_eyebrow("ВАШ СЛЕДУЮЩИЙ ПРАВИТЕЛЬ"))
	preview_col.add_child(_label("%s · мастерство %d / 5" % [selected.name, LordProgression.mastery(lords_profile, str(selected.id))], 20, GOLD, true))
	var preview_scroll = ScrollContainer.new()
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_col.add_child(preview_scroll)
	var showcase = Game.new()
	_fill_showcase(showcase)
	menu_preview = DungeonView.new()
	menu_preview.compact = false
	menu_preview.cinematic = true
	menu_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(menu_preview)
	menu_preview.configure(showcase)
	preview_col.add_child(_label("%s\nQ · %s — два заряда на волну." % [selected.passive_description, selected.ability_name], 13, MUTED, true))
	var foot = HBoxContainer.new()
	page.add_child(foot)
	var progress = _label("ЛОРДЫ %d / 3    ·    ВЕТКИ %d / 2    ·    Особые отряды на каждой 5-й волне" % [lords_profile.unlocked.size(), profile.get("unlocked_paths", []).size()], 12, VIOLET)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(progress)
	foot.add_child(_label("%d комнат · %d классов · комбо" % [Content.room_ids().size(), Content.hero_ids().size()], 12, MUTED))

func _open_lords() -> void:
	if not menu_open:
		_open_menu()
	_close_modal()
	menu_section = "lords"
	inspected_lord = str(lords_profile.selected)
	lord_message = ""
	_refresh()

func _leave_lords() -> void:
	_close_modal()
	menu_section = "home"
	_refresh()

func _inspect_lord(id: String) -> void:
	inspected_lord = id
	lord_message = ""
	if compact_ui and live_scrolls.has("lords") and is_instance_valid(live_scrolls["lords"]):
		live_scrolls["lords"].scroll_vertical = 0
	_refresh()

func _build_lords_page() -> void:
	var heading = HBoxContainer.new()
	page.add_child(heading)
	var titles = _vbox(heading, 3)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_child(_eyebrow("КОРОНА ПЕРЕХОДИТ К СЛЕДУЮЩЕМУ"))
	titles.add_child(_label("Лорды подземелья", 30, GOLD))
	_stat(heading, "ПЕЧАТИ", str(lords_profile.souls), VIOLET)
	if tutorial.active():
		heading.add_child(_button("Пропустить обучение", _skip_tutorial))
	heading.add_child(_button("Назад", _leave_lords))
	var columns = HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 18)
	page.add_child(columns)
	var roster = _vbox(columns, 12)
	roster.custom_minimum_size.x = 285
	for id in Lords.ids():
		_lord_roster_card(roster, id)
	roster.add_child(HSeparator.new())
	roster.add_child(_label("Печати выдаются за волны, поверженных героев, особые отряды и новые рубежи. Их можно потратить на открытие Лордов или мастерство.", 13, MUTED, true))
	if not last_run_reward.is_empty():
		roster.add_child(_label("Последний забег: +%d печатей" % int(last_run_reward.total), 14, VIOLET, true))
	if has_run and not run_reward_claimed:
		roster.add_child(_label("В текущем забеге заработано: %d. Получите после его завершения." % int(_pending_run_reward().total), 12, MUTED, true))
	var panel = _panel(columns)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var detail = _vbox(scroll, 12)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lord_details(detail, inspected_lord)
	var footer = HBoxContainer.new()
	page.add_child(footer)
	var note = _label(lord_message if not lord_message.is_empty() else "Выбор Лорда, мастерство и вариант способности применяются в новом забеге.", 13, VIOLET, true)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(note)
	var selected: Dictionary = Lords.get_lord(str(lords_profile.selected))
	var start = _button("В БОЙ · %s" % str(selected.name), _request_new_run)
	start.custom_minimum_size.y = 44
	footer.add_child(start)

func _lord_roster_card(parent: Control, id: String) -> void:
	var definition: Dictionary = Lords.get_lord(id)
	var owned: bool = lords_profile.unlocked.has(id)
	var chosen: bool = str(lords_profile.selected) == id
	var tint = Color(str(definition.color))
	var button = _button("", _inspect_lord.bind(id))
	button.custom_minimum_size.y = 108
	button.add_theme_stylebox_override("normal", _style(TILE if inspected_lord == id else PANEL, tint if inspected_lord == id else LINE, 10, 10))
	parent.add_child(button)
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 12)
	button.add_child(margin)
	var row = HBoxContainer.new()
	margin.add_child(row)
	var portrait = _icon(str(definition.icon), 58)
	portrait.modulate.a = 1.0 if owned else 0.5
	row.add_child(portrait)
	var names = _vbox(row, 6)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(_label(str(definition.name), 17, tint, true))
	names.add_child(_label("%sМастерство %d / 5" % ["Выбран · " if chosen else "", LordProgression.mastery(lords_profile, id)] if owned else "Открыть: %d печатей" % int(definition.unlock_cost), 11, MUTED, true))
	_ignore_mouse(margin)

func _lord_details(parent: Control, id: String) -> void:
	var definition: Dictionary = Lords.get_lord(id)
	var owned: bool = lords_profile.unlocked.has(id)
	var mastery: int = LordProgression.mastery(lords_profile, id)
	var selected_variant: String = LordProgression.variant(lords_profile, id)
	var tint = Color(str(definition.color))
	var identity = HBoxContainer.new()
	parent.add_child(identity)
	identity.add_child(_icon(str(definition.icon), 54 if compact_ui else 80))
	var names = _vbox(identity, 4)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_child(_label(str(definition.title).to_upper(), 10, tint, true))
	names.add_child(_label(str(definition.name), 29, PAPER, true))
	parent.add_child(_label(str(definition.passive_description), 14, tint, true))
	var ability_panel = _panel(parent)
	var ability = _vbox(ability_panel, 6)
	ability.add_child(_label("Q · " + str(definition.ability_name), 21, tint, true))
	ability.add_child(_label(_lord_ability_text(id, mastery, selected_variant), 13, PAPER, true))
	ability.add_child(_label("Два заряда на волну", 12, MUTED))
	if not owned:
		var price: int = int(definition.unlock_cost)
		parent.add_child(_button("Открыть и выбрать · %d печатей" % price, _purchase_lord.bind(id), int(lords_profile.souls) < price))
	else:
		parent.add_child(_button("Выбран для нового забега" if str(lords_profile.selected) == id else "Выбрать Лорда", _select_lord.bind(id), str(lords_profile.selected) == id))
	var path_button = _button("Мастерство %d / 5 · посмотреть дерево" % mastery if owned else "Посмотреть дерево мастерства", _show_mastery_tree.bind(id, ""))
	path_button.custom_minimum_size.y = 56
	path_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_button.add_theme_stylebox_override("normal", _style(TILE, tint.darkened(0.25), 8, 10))
	parent.add_child(path_button)
	parent.add_child(_label("Сохраняется между забегами. Второй вариант силы — на мастерстве 3.", 12, MUTED, true))

func _mastery_nodes(id: String) -> Array[Dictionary]:
	var definition: Dictionary = Lords.get_lord(id)
	var owned: bool = lords_profile.unlocked.has(id)
	var mastery: int = LordProgression.mastery(lords_profile, id)
	var selected_variant: String = LordProgression.variant(lords_profile, id)
	var nodes: Array[Dictionary] = []
	for rank in range(1, Lords.MAX_MASTERY + 1):
		var acquired: bool = owned and rank <= mastery
		var available: bool = owned and rank == mastery + 1
		var price: int = Lords.upgrade_cost(rank - 1) if rank > 1 else int(definition.unlock_cost)
		var parents: Array[String] = []
		if rank > 1:
			parents.append("mastery:%d" % (rank - 1))
		nodes.append({"id": "mastery:%d" % rank, "name": "Мастерство %d" % rank, "depth": rank - 1, "parents": parents, "state": "acquired" if acquired else "available" if available else "locked", "status": "Получено" if acquired else "%d печатей" % price if available else "После мастерства %d" % (rank - 1) if rank > 1 else "Откройте Лорда", "rank": rank, "icon": str(definition.icon)})
		for variant in definition.variants:
			if int(variant.min_mastery) != rank:
				continue
			var is_selected: bool = owned and str(variant.id) == selected_variant
			var unlocked: bool = owned and mastery >= rank
			nodes.append({"id": "variant:" + str(variant.id), "name": str(variant.name), "depth": rank, "parents": ["mastery:%d" % rank], "state": "acquired" if is_selected else "available" if unlocked else "locked", "status": "Выбрано" if is_selected else "Сменить бесплатно" if unlocked else "Мастерство %d" % rank, "variant": str(variant.id), "rank": rank, "description": str(variant.description), "icon": str(definition.icon)})
	return nodes

func _show_mastery_tree(id: String, focused_id: String = "") -> void:
	var previous_scroll: int = modal_scroll.scroll_vertical if modal_kind == "mastery" and is_instance_valid(modal_scroll) else -1
	var definition: Dictionary = Lords.get_lord(id)
	if definition.is_empty():
		return
	inspected_lord = id
	var owned: bool = lords_profile.unlocked.has(id)
	var mastery: int = LordProgression.mastery(lords_profile, id)
	var selected_variant: String = LordProgression.variant(lords_profile, id)
	var nodes: Array[Dictionary] = _mastery_nodes(id)
	var selected: Dictionary = _find_tree_node(nodes, focused_id)
	if selected.is_empty():
		selected = _find_tree_node(nodes, "mastery:%d" % mini(5, mastery + 1) if owned else "mastery:1")
	mastery_tree_focus = str(selected.id)
	_close_modal()
	var body = _new_modal(760)
	modal_kind = "mastery"
	_tree_badge("%d печатей · навсегда" % int(lords_profile.souls))
	body.add_child(_eyebrow("СОХРАНЯЕТСЯ МЕЖДУ ЗАБЕГАМИ"))
	body.add_child(_label("Мастерство Лорда", 27, GOLD, true))
	body.add_child(_label("%s · %d печатей" % [definition.name, int(lords_profile.souls)], 17, PAPER, true))
	var tree = ProgressionTree.new()
	body.add_child(tree)
	tree.configure(nodes, mastery_tree_focus, compact_ui)
	tree.node_selected.connect(func(node_id: String): _show_mastery_tree(id, node_id))
	var footer = _tree_footer()
	var rank: int = int(selected.rank)
	var is_variant: bool = selected.has("variant")
	var preview_variant: String = str(selected.variant) if is_variant else selected_variant
	var preview_rank: int = maxi(rank, mastery) if is_variant else rank
	var description: String = str(selected.get("description", ""))
	var details: String = _lord_ability_text(id, preview_rank, preview_variant)
	if not is_variant:
		description = "Усиление способности · мастерство %d" % rank
		if owned and rank == mastery + 1:
			details = _mastery_change_text(id, mastery, selected_variant)
	_tree_details(body, footer, str(selected.name), description, details)
	if not owned:
		var price: int = int(definition.unlock_cost)
		var title: String = "Открыть Лорда · %d печатей" % price
		if int(lords_profile.souls) < price:
			title = "Не хватает %d печатей" % (price - int(lords_profile.souls))
		_tree_action(footer, title, _purchase_lord.bind(id), int(lords_profile.souls) < price)
	elif is_variant and mastery >= rank:
		var chosen: bool = str(selected.variant) == selected_variant
		_tree_action(footer, "Выбрано" if chosen else "Выбрать бесплатно", _select_lord_variant.bind(id, str(selected.variant)), chosen)
	elif mastery < Lords.MAX_MASTERY:
		var cost: int = Lords.upgrade_cost(mastery)
		var title: String = "Мастерство %d · %d печатей" % [mastery + 1, cost]
		if int(lords_profile.souls) < cost:
			title = "Не хватает %d печатей" % (cost - int(lords_profile.souls))
		_tree_action(footer, title, _upgrade_lord.bind(id), int(lords_profile.souls) < cost)
	else:
		_tree_action(footer, "Мастерство полностью развито", Callable(), true)
	body.add_child(_label("Выбранная сила и мастерство применятся в новом забеге.", 12, MUTED, true))
	_restore_tree_position(modal_scroll, previous_scroll, tree, mastery_tree_focus)
	_resize_modal.call_deferred()

func _lord_ability_text(id: String, mastery: int, variant_id: String) -> String:
	var values: Dictionary = Lords.ability_values(id, mastery, variant_id)
	match id:
		"fallen_knight":
			var text: String = "Щит: %d%% максимального HP защитника." % roundi(float(values.shield_fraction) * 100.0)
			if int(values.empowered_attacks) > 0:
				text += " Три следующих удара: %s урона." % _percent(float(values.attack_bonus))
			return text
		"necromancer":
			var text: String = "Одно возвращение с %d%% HP." % roundi(float(values.revive_fraction) * 100.0)
			if float(values.revive_damage_bonus) > 0.0:
				text += " После возвращения: %s урона." % _percent(float(values.revive_damage_bonus))
			return text
		"plague_alchemist":
			var duration: int = ceili(float(values.poison_ticks) * (1.0 + float(values.poison_duration_bonus)))
			return "Яд: %d урона x %d тиков. Вспышка: %d урона. Учтена пассивная сила; навыки забега усиливают длительность." % [values.poison_damage, duration, values.burst_damage]
	return ""

func _mastery_change_text(id: String, mastery: int, variant_id: String) -> String:
	var before: Dictionary = Lords.ability_values(id, mastery, variant_id)
	var after: Dictionary = Lords.ability_values(id, mastery + 1, variant_id)
	var text: String = ""
	match id:
		"fallen_knight":
			text = "щит %d%% > %d%% HP" % [roundi(float(before.shield_fraction) * 100.0), roundi(float(after.shield_fraction) * 100.0)]
			if int(after.empowered_attacks) > 0:
				text += "; усиление ударов %s > %s" % [_percent(float(before.attack_bonus)), _percent(float(after.attack_bonus))]
		"necromancer":
			text = "возвращение с %d%% > %d%% HP" % [roundi(float(before.revive_fraction) * 100.0), roundi(float(after.revive_fraction) * 100.0)]
		"plague_alchemist":
			text = "вспышка %d > %d урона; яд %d > %d, длительность +1 базовый тик" % [before.burst_damage, after.burst_damage, before.poison_damage, after.poison_damage]
	if mastery == 2:
		text += ". Откроется второй вариант способности"
	return text

func _lord_purchase_result(error: String, success: String) -> void:
	lord_message = error if not error.is_empty() else success
	if error.is_empty():
		_save_profile()
		_sound("click")
	_refresh()
	if modal_kind == "mastery":
		_show_mastery_tree(inspected_lord)

func _purchase_lord(id: String) -> void:
	var error: String = LordProgression.purchase(lords_profile, id)
	if error.is_empty():
		LordProgression.select(lords_profile, id)
	_lord_purchase_result(error, "%s открыт и выбран для нового забега." % str(Lords.get_lord(id).get("name", id)))

func _select_lord(id: String) -> void:
	_lord_purchase_result(LordProgression.select(lords_profile, id), "Лорд выбран. Новый правитель вступит в бой в следующем забеге.")

func _upgrade_lord(id: String) -> void:
	var error: String = LordProgression.upgrade(lords_profile, id)
	_lord_purchase_result(error, "Мастерство повышено до %d. Усиление действует со следующего забега." % LordProgression.mastery(lords_profile, id))

func _select_lord_variant(id: String, variant_id: String) -> void:
	_lord_purchase_result(LordProgression.select_variant(lords_profile, id, variant_id), "Вариант способности выбран для следующего забега.")

func _request_new_run() -> void:
	if has_run and game.phase != "defeat":
		_close_modal()
		var body = _new_modal()
		body.add_child(_label("Начать новое подземелье?", 26, GOLD))
		body.add_child(_label("Текущий забег закончится. Получите %d печатей за достигнутые результаты. Новый Лорд: %s." % [int(_pending_run_reward().total), str(Lords.get_lord(str(lords_profile.selected)).name)], 16, MUTED, true))
		body.add_child(_button("НАЧАТЬ НОВЫЙ ЗАБЕГ", _begin_run))
	else:
		_begin_run()

func _begin_run() -> void:
	phase_modal_dismissed = false
	_close_modal()
	remembered_scrolls.clear()
	live_scrolls.clear()
	selecting_deal = false
	if tutorial.active():
		_end_tutorial(false)
	if has_run:
		_settle_run()
		_update_record()
	game.unlocked_paths.assign(profile.get("unlocked_paths", []))
	game.restart()
	run_skill_camera.clear()
	talent_tree_focus = "root"
	_configure_selected_lord(game)
	run_best_at_start = int(profile.get("wave", 0))
	run_reward_claimed = false
	last_run_reward = {}
	menu_open = false
	menu_section = "home"
	has_run = true
	paused = false
	resume_paused = false
	accumulator = 0.0
	selected_slot = -1
	selected_room = ""
	scroll_position = 0
	active_floor = -1
	message = ""
	_sound("click")
	_refresh()

func _open_menu() -> void:
	if menu_open:
		return
	_close_modal()
	resume_paused = paused
	paused = true
	menu_open = true
	menu_section = "home"
	_refresh()

func _resume_run() -> void:
	if not has_run or game.phase == "defeat":
		return
	_close_modal()
	menu_open = false
	menu_section = "home"
	paused = resume_paused
	_refresh()

func _show_collection() -> void:
	_close_modal()
	var body = _new_modal(610, true)
	if has_run:
		body.add_child(_button("Навыки забега", _show_talents))
	body.add_child(_label("Постоянные открытия", 26, GOLD))
	for entry in game.unlock_catalog():
		var unlocked: bool = profile.get("unlocked_paths", []).has(str(entry.id))
		_disclosure(body, str(entry.name), str(entry.description) + "\nОткрывается победой на волне %d и остаётся в следующих забегах." % int(entry.wave), "Открыто" if unlocked else "Волна %d" % int(entry.wave), GREEN if unlocked else GOLD)
	if not game.selected_relics.is_empty():
		body.add_child(_eyebrow("РЕЛИКВИИ ЗАБЕГА"))
		for relic in game.relic_definitions():
			if game.selected_relics.has(str(relic.id)):
				body.add_child(_label(str(relic.name), 16, VIOLET, true))
				body.add_child(_label(str(relic.description), 13, MUTED, true))

func _show_settings() -> void:
	_close_modal()
	var body = _new_modal()
	body.add_child(_label("Настройки", 28, GOLD))
	body.add_child(_button("Полный экран / окно · F11", _toggle_fullscreen))
	body.add_child(_button("Звук: " + ("включён" if sound_on else "выключен"), _settings_toggle_sound))
	body.add_child(_label("Громкость", 15, MUTED))
	var slider = HSlider.new()
	if compact_ui:
		slider.custom_minimum_size.y = 44
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = volume
	slider.value_changed.connect(_set_volume)
	body.add_child(slider)
	body.add_child(_label("Скорость просмотра рейда", 15, MUTED))
	var buttons = HBoxContainer.new()
	body.add_child(buttons)
	for value in [1, 2, 4]:
		buttons.add_child(_button("x%d%s" % [value, " *" if speed == value else ""], _settings_speed.bind(value)))

func _settings_toggle_sound() -> void:
	sound_on = not sound_on
	_save_settings()
	_sound("click")
	_show_settings()

func _settings_speed(value: int) -> void:
	speed = value
	_save_settings()
	_show_settings()

func _set_volume(value: float) -> void:
	volume = value
	_save_settings()

func _exit_tree() -> void:
	if is_instance_valid(dungeon_view) and dungeon_view.get_parent() == null:
		dungeon_view.free()

func _quit_game() -> void:
	if has_run:
		_settle_run()
		_update_record()
	get_tree().quit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_game()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		# Mobile browsers may swallow the final touch event during app switching.
		touch_points.clear()
		if refresh_after_touch:
			_flush_touch_refresh.call_deferred()

func _fill_showcase(target) -> void:
	target.restart(2042)
	_configure_selected_lord(target)
	target.gold = 500
	target.buy_floor()
	target.choose_floor_trait("laboratory")
	target.buy_floor()
	target.choose_floor_trait("workshop")
	var layout: Array[String] = ["goblin", "executioner", "spider", "mimic", "goblin", "poison", "spider", "poison", "spider", "executioner", "spikes", "spikes", "mimic", "poison", "executioner"]
	for index in range(layout.size()):
		target.shop[layout[index]] = 10
		target.buy_room(index, layout[index])
	target.wave = 8
	target._generate_party()
	target._generate_shop()
	target.gold = 27
func _matchup_text(stats: Dictionary) -> String:
	var path: Dictionary = RoomEvolutions.path(str(stats.get("evolution_path", "")))
	if not path.is_empty():
		return str(path.get("counter", ""))
	match str(stats.get("id", "")):
		"mimic":
			return "Цель: бард, жрица, чародей — поддержка за передним бойцом. Живой следопыт ослабляет первый удар засады на 35%."
		"spider":
			return "Цель: ослабленный герой. Яд усиливает укус."
		"ogre":
			return "Каждый третий удар x1,5. Долгий бой помогает нанести тяжёлый удар."
		"war_hound":
			return "Охотится на слабейшего; +30% урона целям с HP <= 40%."
		"wraith":
			return "Дух получает 20% физического и 150% магического урона. Чародей особенно опасен."
		"vampire":
			return "Если пережил ответ, лечится на 25% реально нанесённого урона."
		"ballista", "blade_floor":
			return str(stats.get("role", "")) + " Следопыт ослабит ловушку, пока есть инструменты."
		"spikes":
			return "Следопыт ослабит ловушку, пока есть инструменты. Заставьте его потратить их раньше."
		"poison":
			return "Следопыт сокращает отравление за инструмент. Жрица снижает урон яда всей группе на 25%, пока жива и не заглушена."
		"shackles":
			return "Задерживает атаки в следующем бою. Соседний страж дополняет оковы связкой «Темница»."
		"silence":
			return "Подавляет магию чародея, лечение и защиту от яда жрицы, песню барда. Следопыт может сократить эффект. Ярость варвара сохраняется."
		"rust":
			return "Ослабляет броню группы перед следующим боем. Поставьте перед сильным существом."
		"guardian":
			return "Удерживает героев: дайте яду время. Оковы перед стражем образуют «Темницу»."
		_:
			return "Рыцарь и варвар сильны против телесных существ. Ловушки, духи и нападение на поддержку ослабят их группу."

func _show_specializations(index: int) -> void:
	if _tutorial_allow("evolution"):
		_show_room_tree(index)

func _room_stat_changes(before: Dictionary, after: Dictionary) -> String:
	var parts: PackedStringArray = []
	var fields: Dictionary = {"hp": "HP", "damage": "урон", "armor": "броня", "effect_turns": "контроль", "impact_damage": "удар печати"}
	if str(after.get("kind", "")) == "poison":
		fields.erase("damage")
		fields.poison_power_display = "яд за тик"
		fields.poison_ticks_display = "тики яда"
	for key in fields:
		if before.has(key) and after.has(key) and before[key] != after[key]:
			parts.append("%s %s > %s" % [fields[key], before[key], after[key]])
	return " · ".join(parts)

func _visible_room_tree(nodes: Array[Dictionary], focus: Dictionary) -> Array[Dictionary]:
	# Keep every immediate choice readable, expanding one first-tier path at a time.
	var first_id: String = ""
	var cursor: Dictionary = focus
	while not cursor.is_empty() and int(cursor.get("depth", 0)) > 0:
		if int(cursor.depth) == 1:
			first_id = str(cursor.id)
			break
		var parents: Array = cursor.get("parents", [])
		cursor = _find_tree_node(nodes, str(parents[0])) if not parents.is_empty() else {}
	if first_id.is_empty():
		for node in nodes:
			if int(node.get("depth", 0)) == 1 and str(node.get("state", "")) == "acquired":
				first_id = str(node.id)
				break
	if first_id.is_empty():
		for node in nodes:
			if int(node.get("depth", 0)) == 1:
				first_id = str(node.id)
				break
	var visible: Array[Dictionary] = []
	var ids: Array[String] = []
	for node in nodes:
		var depth: int = int(node.get("depth", 0))
		var include: bool = depth <= 1
		for parent_id in node.get("parents", []):
			if (depth == 2 and str(parent_id) == first_id) or (depth > 2 and ids.has(str(parent_id))):
				include = true
		if include:
			var copy: Dictionary = node.duplicate(true)
			if str(copy.get("state", "")) == "other_branch":
				copy.state = "other"
			visible.append(copy)
			ids.append(str(copy.id))
	return visible

func _show_room_tree(index: int, focused_id: String = "") -> void:
	if index < 0 or index >= game.rooms.size() or game.rooms[index].is_empty():
		return
	var previous_scroll: int = modal_scroll.scroll_vertical if modal_kind == "room_tree" and is_instance_valid(modal_scroll) else -1
	var nodes: Array[Dictionary] = game.room_tree(index)
	if nodes.is_empty():
		return
	var selected: Dictionary = _find_tree_node(nodes, focused_id)
	if selected.is_empty():
		for node in nodes:
			if bool(node.get("can_buy", false)):
				selected = node
				break
	if selected.is_empty():
		selected = nodes[0]
		for node in nodes:
			if str(node.get("state", "")) == "acquired":
				selected = node
	tree_room_index = index
	room_tree_focus = str(selected.id)
	var stats: Dictionary = game.room_stats(index)
	_close_modal()
	var body = _new_modal(940)
	modal_kind = "room_tree"
	_tree_badge("Ранг %d · %d зол." % [int(stats.get("rank", 1)), game.gold])
	body.add_child(_eyebrow("КОМНАТА · ДО КОНЦА ЗАБЕГА"))
	body.add_child(_label(str(stats.name), 27, GOLD, true))
	body.add_child(_label("Ранг %d · развилки 2 / 5 / 15" % int(stats.get("rank", 1)), 14, PAPER, true))
	var tree = ProgressionTree.new()
	body.add_child(tree)
	tree.configure(_visible_room_tree(nodes, selected), room_tree_focus, compact_ui)
	tree.node_selected.connect(func(id: String): _show_room_tree(index, id))
	var footer = _tree_footer()
	var preview: Dictionary = selected.get("preview", {})
	var before: Dictionary = preview.get("before", {})
	var after: Dictionary = preview.get("after", {})
	_evolution_previews(body if get_viewport_rect().size.y < 500.0 else footer, selected, stats, after)
	var change: String = _room_stat_changes(before, after)
	if bool(preview.get("projected", false)) and not change.is_empty():
		change = "На ранге %d: %s" % [int(preview.get("rank", 1)), change]
	var description: String = str(selected.get("description", ""))
	var status: String = str(selected.get("status", ""))
	var selected_title: String = str(selected.name)
	if not status.is_empty():
		selected_title += " · " + status
	_tree_details(body, footer, selected_title, description, change)
	var matchups = _label(_matchup_text(after if not after.is_empty() else stats).get_slice(". ", 0), 12, MUTED, true)
	body.add_child(matchups)
	var pending: bool = _has_pending_evolution(index)
	if pending:
		var can_choose: bool = bool(selected.get("can_buy", false)) and game.phase == "prepare"
		var confirm = _tree_action(footer, "Выбрать" if can_choose else "Выберите доступный узел", _specialize.bind(index, str(selected.get("effect_id", ""))), not can_choose)
		_tutorial_mark(confirm, "evolution_choice")
	else:
		var rank: int = int(stats.get("rank", 1))
		var cap: int = int(stats.get("max_rank", 0))
		var cost: int = game.upgrade_cost(index)
		var capped: bool = cap > 0 and rank >= cap
		var label: String = "Максимальный ранг" if capped else "Ранг %d · улучшить за %d зол." % [rank + 1, cost]
		if not capped and game.gold < cost:
			label = "Не хватает %d зол." % (cost - game.gold)
		var upgrade = _tree_action(footer, label, _upgrade, game.phase != "prepare" or capped or game.gold < cost)
		upgrade.tooltip_text = _upgrade_savings_text(index).strip_edges()
		_tutorial_mark(upgrade, "upgrade")
	_restore_tree_position(modal_scroll, previous_scroll, tree, room_tree_focus)
	_resize_modal.call_deferred()


func _evolution_previews(parent: Control, selected: Dictionary, stats: Dictionary, after: Dictionary) -> void:
	var candidate: String = str(after.get("evolution_path", selected.get("effect_id", ""))).get_slice(":", 0)
	var path: Dictionary = RoomEvolutions.path(candidate)
	if path.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var tiers: Array = [int(selected.get("tier", selected.get("required_rank", 2)))] if compact_ui else [2, 5, 15]
	for rank in tiers:
		var stage: Dictionary = RoomEvolutions.stage(candidate, int(rank))
		var col := _vbox(row, 3)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var art := EvolutionPreview.new()
		art.configure(candidate, str(stats.id), int(stage.get("tier", rank)))
		art.custom_minimum_size.y = 72 if compact_ui else 76
		col.add_child(art)
		var label := _label("%d · %s" % [int(stage.get("tier", rank)), str(stage.get("name", ""))], 11, GOLD, true)
		label.max_lines_visible = 1
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		col.add_child(label)

func _specialize(index: int, id: String) -> void:
	if not _tutorial_allow("evolution_choice"):
		return
	var error: String = game.choose_room_evolution(index, id)
	if error.is_empty():
		tutorial.accepted("evolution_choice")
	_close_modal()
	_action(error)
	if not error.is_empty() or not game.room_evolution_options(index).is_empty():
		_show_specializations(index)

func _choose_floor(id: String) -> void:
	phase_modal_dismissed = false
	_close_modal()
	var error: String = game.choose_floor_trait(id)
	if error.is_empty():
		tutorial.accepted("floor_choice")
	_action(error)


func _choose_run_reward(id: String, blueprint: bool) -> void:
	phase_modal_dismissed = false
	_close_modal()
	var error: String = game.choose_blueprint(id) if blueprint else game.choose_relic(id)
	_action(error)


func _hero_status(hero: Dictionary, definition: Dictionary) -> String:
	if int(hero.hp) <= 0:
		return "Повержен"
	var parts: PackedStringArray = []
	match str(hero.id):
		"knight":
			parts.append("Силен против телесных · слаб против духов")
		"rogue":
			parts.append("Инструменты: %d · все ловушки · раскрывает засады" % int(hero.get("disarm_charges", 2)))
		"priest":
			parts.append("Лечение · защита группы от яда -25%" if int(hero.get("silence_ticks", 0)) <= 0 else "Лечение и защита от яда заглушены")
		"mage":
			parts.append("Магия особенно опасна духам · заряжает заклинание" if int(hero.get("silence_ticks", 0)) <= 0 else "Магия заглушена")
		"barbarian":
			parts.append("Силен против телесных · духи почти неуязвимы к топору")
			parts.append("ЯРОСТЬ +25%" if int(hero.hp) <= float(hero.max_hp) * 0.4 else "Ярость при HP <= 40%")
		"bard":
			parts.append("Песня: +15% урона всему отряду" if int(hero.get("silence_ticks", 0)) <= 0 else "Песня заглушена")
		_:
			parts.append(str(definition.get("trait", "")))
	if int(hero.get("poison_ticks", 0)) > 0:
		parts.append("Яд: %d т." % int(hero.poison_ticks))
		if int(hero.get("run_poison_corrosion", 0)) > 0:
			parts.append("Коррозия: −1 брони")
		if bool(hero.get("run_heavy_breathing", false)):
			parts.append("Тяжёлое дыхание: −10% обычного удара")
	for effect in ["shackles", "silence", "rust"]:
		var current: int = int(hero.get(effect + "_ticks", 0))
		var pending: int = int(hero.get("pending_" + effect, 0))
		var names: Dictionary = {"shackles": "Оковы", "silence": "Безмолвие", "rust": "Ржавчина"}
		if current > 0:
			parts.append("%s: %d т." % [names[effect], current])
		elif pending > 0:
			parts.append("%s > следующий бой" % names[effect])
	if int(hero.get("goblin_mark_slot", -1)) >= 0:
		parts.append("Метка засады")
	var effects: Dictionary = hero.get("effects", {})
	if int(effects.get("cocoon_ticks", 0)) > 0:
		parts.insert(0, "В коконе")
	if bool(effects.get("retreating", false)):
		parts.insert(0, "Отходит под прикрытием")
	if bool(effects.get("forced_front", false)):
		parts.insert(0, "Вытащен вперёд")
	if not str(effects.get("hypnotized_by", "")).is_empty():
		parts.insert(0, "Под гипнозом")
	if bool(effects.get("weapon_swap", false)):
		parts.append("Оружие подменено")
	if int(effects.get("spore_attacks", 0)) > 0:
		parts.append("Спора")
	if hero.has("cursed_cup"):
		parts.append("Кубок: %d/%d" % [int(hero.cursed_cup.get("uses", 0)), int(hero.cursed_cup.get("uses_to_bite", 3))])
	return " · ".join(parts)


func _room_combo_details(parent: Control, index: int) -> void:
	var link: Dictionary = game.room_combo(index)
	if link.is_empty():
		return
	var label = _label("Комбо: " + str(link.name), 12, GOLD, true)
	label.tooltip_text = _ui_text(str(link.description))
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(label)

func _style_faction_card(button: Button, color: Color, selected: bool) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill: Color = Color("#343127") if selected else TILE
		if state == "hover":
			fill = Color("#303a49")
		elif state == "disabled":
			fill = Color("#181e27")
		elif state == "focus":
			fill = Color.TRANSPARENT
		var card_style = _style(fill, color, 9, 10)
		card_style.set_border_width_all(3 if selected else 2)
		button.add_theme_stylebox_override(state, card_style)


func _faction_counters(parent: Control) -> void:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	for faction in game.faction_status():
		var count: int = int(faction.count)
		var label = _label("%s %d" % [faction.name, count], 11, faction.color if count > 0 else MUTED)
		label.tooltip_text = _ui_text(_faction_rules(faction))
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(label)

func _faction_rules(faction: Dictionary) -> String:
	var lines: PackedStringArray = ["Считаются разные типы на поле, а не количество копий."]
	var names: PackedStringArray = []
	for id in faction.get("room_ids", []):
		names.append(str(Content.room(str(id)).get("short_name", id)))
	if not names.is_empty():
		lines.append("Комнаты: " + ", ".join(names))
	for bonus in faction.get("bonuses", []):
		lines.append(("* " if bool(bonus.get("active", false)) else "") + str(bonus.get("description", "")))
	return "\n".join(lines)


func _deal_card(parent: Control, offer: Dictionary) -> void:
	var column = _vbox(parent, 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var definition: Dictionary = Content.room(str(offer.get("room_id", "")))
	var accepted: bool = bool(offer.get("accepted", false))
	var label: String = "Сделка принята · " if accepted else "* Разместить · " if selecting_deal else "Сделка · "
	label += "%s · ранг %d · %d зол." % [definition.get("short_name", "Комната"), int(offer.get("rank", 3)), int(offer.get("price", 0))]
	var button = _button(label, _select_deal, accepted or not bool(offer.get("available", false)) or game.gold < int(offer.get("price", 0)))
	button.add_theme_font_size_override("font_size", 12)
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var faction: Dictionary = Game.room_faction(str(offer.get("room_id", "")))
	_style_faction_card(button, faction.get("color", GOLD), selecting_deal)
	button.tooltip_text = _ui_text(Content.room_traits_text(definition) + "\n" + str(offer.get("description", "")) + "\n" + str(offer.get("risk_text", "")) + "\nРанг растёт с номером волны. Отмена выбора не меняет предложение.\nДо начала волны продажа этой комнаты снимает риск.")
	column.add_child(button)
	column.add_child(_label(str(offer.get("risk_text", "")), 11, RED, true))


func _select_deal() -> void:
	if game.phase != "prepare" or not _tutorial_allow("deal"):
		return
	var offer: Dictionary = game.deal_offer()
	if offer.is_empty() or not bool(offer.get("available", false)) or bool(offer.get("accepted", false)):
		return
	_close_modal()
	last_room_tap = -1
	selecting_deal = not selecting_deal
	selected_room = ""
	selected_slot = -1
	message = "Выберите свободное место для комнаты по сделке." if selecting_deal else "Размещение сделки отменено."
	_sound("click")
	_refresh()


func _disclosure(parent: Control, title: String, details: String, status: String = "", tint: Color = MUTED) -> void:
	var column = _vbox(parent, 4)
	var button = _button("+ " + title + (" · " + status if not status.is_empty() else ""), Callable())
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", tint)
	button.tooltip_text = _ui_text(details)
	column.add_child(button)
	var description = _label(details, 12, MUTED, true)
	description.visible = false
	column.add_child(description)
	button.toggled.connect(func(opened: bool):
		description.visible = opened
		button.text = _ui_text(("- " if opened else "+ ") + title + (" · " + status if not status.is_empty() else ""))
	)


func _tutorial_context(parent: Control, area: String) -> void:
	var hint: Dictionary = tutorial.context_hint(area)
	if hint.is_empty():
		return
	var panel = _panel(parent)
	panel.add_theme_stylebox_override("panel", _style(Color("#29271f"), GOLD, 8, 9))
	var body = _vbox(panel, 5)
	body.add_child(_label(str(hint.get("title", "Подсказка")), 12, GOLD, true))
	body.add_child(_label(str(hint.get("text", "")), 12, PAPER, true))


func _tutorial_slot() -> int:
	if tutorial.active() and not menu_open:
		var target: String = tutorial.target()
		if target.begins_with("slot:"):
			return int(target.trim_prefix("slot:"))
	return -1


func _tutorial_mark(button: Button, action: String) -> void:
	if not tutorial.active() or menu_open:
		return
	if action not in ["choice", "continue"] and not tutorial.allows(action):
		button.disabled = true
	if (action == tutorial.target() or (action == "evolution_choice" and tutorial.step == "evolution")) and not button.disabled:
		var border = _style(Color("#353025"), GOLD, 8, 10)
		border.set_border_width_all(3)
		button.add_theme_stylebox_override("normal", border)
		button.add_theme_color_override("font_color", GOLD)
		button.tooltip_text = _ui_text(tutorial.prompt(str(game.phase)) + "\n" + button.tooltip_text)


func _tutorial_allow(action: String) -> bool:
	if tutorial.allows(action):
		return true
	message = "Сейчас выполните подсвеченный шаг. «Пропустить» начинает обычную игру."
	_refresh()
	return false


func _tutorial_banner(parent: Control) -> void:
	var panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("#29271f"), GOLD, 8, 9))
	parent.add_child(panel)
	var row = HBoxContainer.new()
	panel.add_child(row)
	var caption = _label(("УЧИМСЯ · " + _mobile_tutorial_prompt()) if compact_ui else "ОБУЧЕНИЕ  ·  " + tutorial.prompt(str(game.phase)), 13 if compact_ui else 14, GOLD, true)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	if tutorial.step == "finish":
		var finish = _button("Мой забег", _complete_tutorial)
		finish.custom_minimum_size.x = 88 if compact_ui else 0
		row.add_child(finish)
	var skip = _button("Пропуск" if compact_ui else "Пропустить", _skip_tutorial)
	skip.custom_minimum_size.x = 88 if compact_ui else 0
	row.add_child(skip)

func _mobile_tutorial_prompt() -> String:
	var prompts: Dictionary = {
		"select_goblin": "Откройте магазин кнопкой с сумкой и выберите гоблинов.",
		"place_goblin": "Поставьте гоблинов в первое место.",
		"select_executioner": "Откройте магазин и выберите палача.",
		"place_executioner": "Поставьте палача сразу справа от гоблинов.",
		"start": "Комбо готово. Начните волну.",
		"ability_wait": "Бой идёт сам. Сейчас попробуем силу Лорда.",
		"ability": "Бой на паузе. Нажмите золотую силу Лорда внизу.",
		"watch": "Наблюдайте за боем. Внизу - пауза и скорость.",
		"reward": "Победа! Нажмите «Продолжить» в итогах волны.",
		"select_upgrade": "Дважды нажмите гоблинов в первом месте.",
		"upgrade": "Нажмите «Улучшить»: выбор усиления появится сразу." if modal_kind == "room" else "Дважды нажмите гоблинов, затем «Улучшить».",
		"evolution": "Выберите усиление. Новые решения - на рангах 5 и 15." if modal_kind == "evolution" else "Дважды нажмите гоблинов и «Улучшить»: выбор уже оплачен.",
		"floor": "Нажмите «+ Этаж» над полем: ещё пять мест.",
		"floor_choice": "Выберите свойство нового этажа.",
		"finish": "Готово! Начните свой забег.",
	}
	return str(prompts.get(tutorial.step, tutorial.prompt(str(game.phase))))

func _request_tutorial() -> void:
	_close_modal()
	if has_run and game.phase != "defeat" and not game.tutorial_run:
		var body = _new_modal()
		body.add_child(_label("Начать учебное подземелье?", 26, GOLD, true))
		body.add_child(_label("Текущий забег закончится; его %d печатей будут сохранены. В обучении — отдельное золото, без постоянных Печатей и рекордов. Прошлые достижения останутся с вами." % int(_pending_run_reward().total), 15, MUTED, true))
		body.add_child(_button("Начать обучение", _begin_tutorial))
	else:
		_begin_tutorial()


func _begin_tutorial() -> void:
	phase_modal_dismissed = false
	_close_modal()
	remembered_scrolls.clear()
	live_scrolls.clear()
	selecting_deal = false
	if has_run:
		_settle_run()
		_update_record()
	if not game.tutorial_run:
		tutorial_saved_speed = speed
	game.begin_tutorial()
	run_skill_camera.clear()
	talent_tree_focus = "root"
	tutorial.begin()
	speed = 1
	has_run = true
	menu_open = false
	menu_section = "home"
	paused = false
	resume_paused = false
	accumulator = 0.0
	selected_slot = -1
	selected_room = ""
	scroll_position = 0
	active_floor = -1
	run_reward_claimed = true
	last_run_reward = {}
	message = "Учебные ресурсы действуют только здесь. Следуйте золотой подсветке."
	_refresh()


func _end_tutorial(completed: bool) -> void:
	if not tutorial.active():
		return
	profile["tutorial_completed" if completed else "tutorial_skipped"] = true
	tutorial.step = ""
	speed = tutorial_saved_speed
	if is_instance_valid(dungeon_view):
		dungeon_view.tutorial_slot = -1
	_save_profile()


func _complete_tutorial() -> void:
	_end_tutorial(true)
	_begin_run()


func _skip_tutorial() -> void:
	_end_tutorial(false)
	_begin_run()

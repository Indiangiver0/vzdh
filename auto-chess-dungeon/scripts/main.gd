extends Control

const Game = preload("res://scripts/dungeon_game.gd")
const Content = preload("res://scripts/content_catalog.gd")
const DungeonView = preload("res://scripts/dungeon_view.gd")
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
var speed: int = 1
var paused: bool = false
var sound_on: bool = true
var accumulator: float = 0.0
var message: String = "Выберите комнату в магазине, затем свободное место на этаже."
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

func _ready() -> void:
	_load_local()
	game.unlocked_paths.assign(profile.get("unlocked_paths", []))
	game.restart()
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
	_refresh()
	if not screenshot_path.is_empty():
		_capture.call_deferred()

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
	var margin = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	add_child(margin)
	page = VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margin.add_child(page)

func _refresh() -> void:
	if is_instance_valid(floor_scroll):
		scroll_position = floor_scroll.scroll_vertical
	if is_instance_valid(dungeon_view) and dungeon_view.get_parent():
		dungeon_view.get_parent().remove_child(dungeon_view)
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	if menu_open:
		_build_menu()
		return
	_header()
	var body = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	page.add_child(body)
	_party_panel(body)
	_dungeon_panel(body)
	_inspector_panel(body)
	_shop_panel()
	_footer()
	floor_scroll.set_deferred("scroll_vertical", scroll_position)
	if game.phase == "raid":
		var target_floor: int = mini(game.current_slot / 5, game.floor_count)
		if target_floor != active_floor and game.current_slot >= 0:
			active_floor = target_floor
			floor_scroll.set_deferred("scroll_vertical", target_floor * 160)
	_show_phase_modal()

func _header() -> void:
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	page.add_child(head)
	var mark = _icon("res://assets/icons/lord.svg", 52)
	head.add_child(mark)
	var brand = VBoxContainer.new()
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.add_theme_constant_override("separation", 0)
	head.add_child(brand)
	brand.add_child(_label("ЛОРД ПОДЗЕМЕЛЬЯ", 25, PAPER))
	brand.add_child(_label("ПОСТРОЙ ИМПЕРИЮ. ПЕРЕЖИВИ СЛЕДУЮЩУЮ ВОЛНУ.", 10, MUTED))
	_stat(head, "ВОЛНА", str(game.wave), PAPER)
	_stat(head, "ЗОЛОТО", str(game.gold), GOLD)
	_stat(head, "РЕКОРД", str(int(profile.get("wave", 0))), VIOLET)
	var small = VBoxContainer.new()
	head.add_child(small)
	small.add_child(_button("Меню", _open_menu))
	small.add_child(_button("Звук: " + ("вкл" if sound_on else "выкл"), _toggle_sound))

func _party_panel(parent: Control) -> void:
	var box = _panel(parent, 222)
	var side = _vbox(box)
	side.add_child(_eyebrow("РАЗВЕДКА"))
	side.add_child(_label("Приключенцы", 23))
	var state_text: String = "Следующая группа" if game.phase == "prepare" else "Группа в подземелье"
	side.add_child(_label(state_text + " · %d чел." % game.heroes.size(), 12, MUTED))
	var expedition: String = game.wave_title if game.wave % 5 == 0 else "Цель: особый отряд на волне %d" % (game.wave + 5 - game.wave % 5)
	var expedition_label = _label(expedition, 12, GOLD, true)
	expedition_label.tooltip_text = game.wave_description
	side.add_child(expedition_label)
	var party_scroll = ScrollContainer.new()
	party_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	party_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(party_scroll)
	var heroes_col = VBoxContainer.new()
	heroes_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_scroll.add_child(heroes_col)
	for hero in game.heroes:
		var card = PanelContainer.new()
		var compact: bool = game.heroes.size() > 1
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
		names.add_child(_label(str(definition.get("name", hero.id)), 14 if compact else 16, PAPER if hero.hp > 0 else MUTED))
		names.add_child(_label("Ур. %d  ·  XP %d/%d" % [hero.level, hero.xp, 8 + 4 * (int(hero.level) - 1)], 11, VIOLET))
		inner.add_child(_bar(float(hero.hp), float(hero.max_hp), RED if hero.hp > 0 else MUTED))
		inner.add_child(_label("%d/%d HP    Урон %d  ·  Броня %d" % [maxi(0, hero.hp), hero.max_hp, hero.damage, hero.armor], 11, MUTED))
		var status: String = str(definition.get("trait", ""))
		if str(hero.id) == "rogue":
			status = "Инструменты: %d · ловушки" % int(hero.get("disarm_charges", 2))
		if hero.hp <= 0:
			status = "Повержен"
		elif int(hero.get("poison_ticks", 0)) > 0:
			status = "Яд: %d тиков" % int(hero.poison_ticks)
		var items: Array = hero.get("items", [])
		if not items.is_empty():
			var names_list: PackedStringArray = []
			for id in items:
				names_list.append(str(Content.item(str(id)).get("name", id)))
			status += " · " + ", ".join(names_list)
		card.tooltip_text = status
		if not compact or str(hero.id) == "rogue" or int(hero.get("poison_ticks", 0)) > 0 or not items.is_empty():
			var status_label = _label(status, 10 if compact else 11, GREEN if int(hero.get("poison_ticks", 0)) > 0 else MUTED, not compact)
			if compact:
				status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			inner.add_child(status_label)
	var tip: String = "Убитые монстры дают героям опыт. Иногда пустая комната лучше лёгкой добычи."
	if game.heroes.size() > 1:
		tip = "В бой ведёт рыцарь, к ловушкам выходит следопыт. Мимик нападает на лекаря."
	if game.heroes.size() == 1:
		side.add_child(_label(tip, 12, MUTED, true))
	side.add_child(HSeparator.new())
	_lord_status(side)

func _lord_status(parent: Control) -> void:
	var row = HBoxContainer.new()
	parent.add_child(row)
	row.add_child(_icon("res://assets/icons/lord.svg", 30))
	row.add_child(_label("Лорд · уровень %d" % game.lord.level, 17, GOLD))
	parent.add_child(_bar(float(game.lord.hp), float(game.lord.max_hp), GOLD))
	parent.add_child(_label("%d/%d HP   ·   Урон %d   ·   XP %d/%d" % [maxi(0, game.lord.hp), game.lord.max_hp, game.lord.damage, game.lord.xp, 10 + 6 * (int(game.lord.level) - 1)], 11, MUTED))

func _dungeon_panel(parent: Control) -> void:
	var box = _panel(parent)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var center = _vbox(box, 8)
	var title_row = HBoxContainer.new()
	center.add_child(title_row)
	var title = _label("Глубины вашего подземелья", 21, PAPER)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	title_row.add_child(_label("%d этаж. / %d мест" % [game.floor_count, game.rooms.size()], 11, GOLD))
	var guidance: String = message
	if not selected_room.is_empty() and game.phase == "prepare":
		guidance = "Разместить: %s. Выберите пустую комнату." % Content.room(selected_room).name
	elif selected_slot >= 0 and game.phase == "prepare":
		guidance = "Выберите другой слот для переноса или обмена."
	elif game.phase == "raid":
		guidance = str(game.last_action.get("text", "Группа спускается в подземелье."))
		if guidance.is_empty():
			guidance = "Группа спускается в подземелье."
	var caption = _label(guidance, 12, GOLD if game.phase == "raid" else MUTED, true)
	caption.custom_minimum_size.y = 34
	center.add_child(caption)
	floor_scroll = ScrollContainer.new()
	floor_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	floor_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(floor_scroll)
	if not is_instance_valid(dungeon_view):
		dungeon_view = DungeonView.new()
		dungeon_view.slot_clicked.connect(_slot_clicked)
	dungeon_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	floor_scroll.add_child(dungeon_view)
	dungeon_view.configure(game, selected_slot, selected_room)
	var floor_button = _button("+ УГЛУБИТЬ ПОДЗЕМЕЛЬЕ · %d зол." % game.floor_cost(), _buy_floor, game.phase != "prepare" or game.gold < game.floor_cost())
	floor_button.custom_minimum_size.y = 38
	floor_button.tooltip_text = "Пять новых комнат и выбор свойства этажа: лаборатория, казармы или мастерская."
	center.add_child(floor_button)

func _inspector_panel(parent: Control) -> void:
	var box = _panel(parent, 242)
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var right = _vbox(scroll)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(_eyebrow("КОМАНДНЫЙ ПУНКТ"))
	var is_raid: bool = game.phase == "raid"
	right.add_child(_label("Ход рейда" if is_raid else "Управление", 21))
	if is_raid:
		var defender_name: String = str(game.defender.get("name", "Герои входят…"))
		right.add_child(_label(defender_name, 17, GOLD, true))
		if not game.defender.is_empty() and int(game.defender.get("max_hp", 0)) > 0:
			right.add_child(_bar(float(game.defender.get("hp", 0)), float(game.defender.get("max_hp", 1)), RED))
			right.add_child(_label("HP %d · Урон %d" % [maxi(0, int(game.defender.get("hp", 0))), game.defender.get("damage", 0)], 12, MUTED, true))
			if game.rage > 0:
				right.add_child(_label("Ярость: +%d урона" % game.rage, 12, RED))
		elif not game.defender.is_empty():
			right.add_child(_label("Ловушка · эффект при входе", 12, MUTED, true))
		var controls = HBoxContainer.new()
		right.add_child(controls)
		controls.add_child(_button("▶" if paused else "Ⅱ", _toggle_pause))
		for value in [1, 2, 4]:
			var speed_btn = _button("×%d" % value, _set_speed.bind(value))
			if speed == value:
				speed_btn.add_theme_color_override("font_color", GOLD)
			controls.add_child(speed_btn)
		right.add_child(_label(game.wave_description, 12, MUTED, true))
	elif selected_slot >= 0 and selected_slot < game.rooms.size() and not game.rooms[selected_slot].is_empty():
		var stats: Dictionary = game.room_stats(selected_slot)
		right.add_child(_label(str(stats.name), 18, GOLD, true))
		right.add_child(_label(str(stats.description), 12, MUTED, true))
		right.add_child(_label("HP %d  ·  Урон %d\nБроня %d  ·  XP врагу %d" % [stats.get("hp", 0), stats.get("damage", 0), stats.get("armor", 0), stats.get("xp", 0)], 12, PAPER, true))
		right.add_child(_label(_matchup_text(stats), 12, GREEN, true))
		var branch: String = str(stats.get("branch", ""))
		if not branch.is_empty():
			right.add_child(_label("Ветка: " + branch, 13, VIOLET, true))
		right.add_child(_button("Улучшить · %d зол." % game.upgrade_cost(selected_slot), _upgrade, game.phase != "prepare" or game.gold < game.upgrade_cost(selected_slot)))
		if not game.specialization_options(selected_slot).is_empty():
			right.add_child(_button("Выбрать специализацию", _show_specializations.bind(selected_slot), game.phase != "prepare"))
		elif int(stats.get("rank", 1)) < 2:
			right.add_child(_label("С ранга 2 — выбор ветки", 11, VIOLET))
		right.add_child(_button("Продать · +%d зол." % game.sell_value(selected_slot), _sell, game.phase != "prepare"))
		right.add_child(_button("Отменить выбор", _cancel_selection))
	else:
		right.add_child(_label("Прочитайте их план.\nПостройте свой.", 17, PAPER, true))
		right.add_child(_label("Следопыт тратит инструменты на первые ловушки. Утомите его перед опасным этажом.", 12, MUTED, true))
		right.add_child(_label("Мимик добирается до жрицы за рыцарем. Пауки охотятся на ослабленных.", 12, MUTED, true))
		right.add_child(_button("Лечить Лорда · %d зол." % game.heal_cost(), _heal, game.phase != "prepare" or game.gold < game.heal_cost() or game.lord.hp >= game.lord.max_hp))
		right.add_child(_label("HP +%d%% · урон +%d%%\nЛовушки +%d%%" % [int(game.upgrades.get("hp", 0)) * 10, int(game.upgrades.get("damage", 0)) * 10, int(game.upgrades.get("trap", 0)) * 10], 11, VIOLET))
	right.add_child(HSeparator.new())
	right.add_child(_eyebrow("ЛЕТОПИСЬ"))
	log_box = RichTextLabel.new()
	log_box.custom_minimum_size.y = 130
	log_box.bbcode_enabled = false
	log_box.scroll_following = true
	log_box.add_theme_font_size_override("normal_font_size", 11)
	log_box.add_theme_color_override("default_color", MUTED)
	right.add_child(log_box)
	for line in game.logs:
		log_box.append_text(str(line) + "\n\n")

func _shop_panel() -> void:
	var shop_area = VBoxContainer.new()
	shop_area.add_theme_constant_override("separation", 7)
	page.add_child(shop_area)
	var header = HBoxContainer.new()
	shop_area.add_child(header)
	var title = _eyebrow("МАГАЗИН КОМНАТ")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_label("Комнаты сохраняются · новые можно вернуть за полную цену", 11, MUTED))
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	shop_area.add_child(row)
	for id in game.shop:
		var definition: Dictionary = Content.room(str(id))
		var stock: int = int(game.shop[id])
		var button = Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 90
		button.disabled = game.phase != "prepare" or stock <= 0 or game.gold < int(definition.cost)
		button.tooltip_text = "%s\nHP: %d · Урон: %d · Броня: %d\nНаграда врагу: %d XP" % [definition.description, definition.hp, definition.damage, definition.armor, definition.xp]
		button.pressed.connect(_select_shop.bind(str(id)))
		if selected_room == str(id):
			button.add_theme_stylebox_override("normal", _style(Color("#343127"), GOLD, 9, 10))
		row.add_child(button)
		var margin = MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + edge, 10)
		button.add_child(margin)
		var contents = HBoxContainer.new()
		margin.add_child(contents)
		contents.add_child(_icon(str(definition.icon), 45))
		var text_col = VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text_col.add_theme_constant_override("separation", 4)
		contents.add_child(text_col)
		text_col.add_child(_label(str(definition.name), 14, PAPER if not button.disabled else MUTED))
		text_col.add_child(_label("%d зол.   ·   запас %d" % [definition.cost, stock], 12, GOLD))
		text_col.add_child(_label("Врагу: %d XP%s" % [definition.xp, " + предмет" if not str(definition.item).is_empty() else ""] if str(definition.kind) == "monster" else "Ловушка · без XP врагу", 10, MUTED))
		_ignore_mouse(margin)

func _footer() -> void:
	var row = HBoxContainer.new()
	page.add_child(row)
	var desc = _label("Подготовка · продумайте порядок комнат" if game.phase == "prepare" else "Защита действует автоматически", 13, MUTED)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(desc)
	if game.phase == "prepare":
		if selected_slot >= 0 or not selected_room.is_empty():
			row.add_child(_button("Снять выбор", _cancel_selection))
		var start = _button("НАЧАТЬ ВОЛНУ %d   →" % game.wave, _start)
		start.custom_minimum_size = Vector2(255, 42)
		start.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 8, 12))
		start.add_theme_color_override("font_color", INK)
		start.add_theme_color_override("font_hover_color", GOLD)
		row.add_child(start)
	elif game.phase == "raid":
		row.add_child(_label(("ПАУЗА" if paused else "РЕЙД ИДЁТ") + "   ×%d" % speed, 17, GOLD))
	else:
		row.add_child(_button("Показать результат", _show_phase_modal))

func _process(delta: float) -> void:
	if menu_open or game.phase != "raid" or paused or is_instance_valid(modal):
		return
	accumulator += delta * speed
	if accumulator >= 0.5:
		accumulator -= 0.5
		game.step()
		_sound("hit" if game.phase == "raid" else ("lose" if game.phase == "defeat" else "win"))
		if game.phase != "raid":
			_update_record()
		_refresh()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE and not menu_open and game.phase == "raid" and not is_instance_valid(modal):
			_toggle_pause()
		if event.keycode == KEY_ESCAPE:
			if is_instance_valid(modal):
				if game.phase in ["prepare", "raid"] or menu_open:
					_close_modal()
			elif menu_open:
				_resume_run()
			elif selected_slot >= 0 or not selected_room.is_empty():
				_cancel_selection()
			else:
				_open_menu()

func _slot_clicked(index: int) -> void:
	if game.phase != "prepare":
		return
	if not selected_room.is_empty():
		_action(game.buy_room(index, selected_room))
		if int(game.shop.get(selected_room, 0)) <= 0:
			selected_room = ""
		_refresh()
	elif selected_slot >= 0:
		if selected_slot == index:
			_cancel_selection()
		else:
			_action(game.move_room(selected_slot, index))
			selected_slot = -1
			_refresh()
	elif not game.rooms[index].is_empty():
		selected_slot = index
		_refresh()
	else:
		message = "Сначала выберите тип комнаты в магазине внизу."
		_refresh()

func _select_shop(id: String) -> void:
	selected_slot = -1
	selected_room = "" if selected_room == id else id
	_sound("click")
	_refresh()

func _cancel_selection() -> void:
	selected_slot = -1
	selected_room = ""
	message = "Выберите комнату в магазине или улучшите построенную."
	_refresh()

func _upgrade() -> void:
	var error: String = game.upgrade_room(selected_slot)
	_action(error)
	if error.is_empty() and not game.specialization_options(selected_slot).is_empty():
		_show_specializations(selected_slot)

func _sell() -> void:
	var error: String = game.sell_room(selected_slot)
	if error.is_empty():
		selected_slot = -1
	_action(error)

func _buy_floor() -> void:
	_action(game.buy_floor())
	scroll_position = (game.floor_count - 1) * 160
	if is_instance_valid(floor_scroll):
		floor_scroll.set_deferred("scroll_vertical", scroll_position)

func _heal() -> void:
	_action(game.heal_lord())

func _start() -> void:
	selected_slot = -1
	selected_room = ""
	active_floor = -1
	paused = false
	accumulator = 0.0
	_action(game.start_raid())

func _action(error: String) -> void:
	message = error if not error.is_empty() else "Приказ выполнен. Подземелье готовится к рейду."
	_sound("click")
	_refresh()

func _set_speed(value: int) -> void:
	speed = value
	_save_settings()
	_refresh()

func _toggle_pause() -> void:
	paused = not paused
	_refresh()

func _toggle_sound() -> void:
	sound_on = not sound_on
	_save_settings()
	_sound("click")
	_refresh()

func _show_phase_modal() -> void:
	if menu_open or game.phase not in ["result", "level_up", "floor_choice", "defeat"]:
		return
	_close_modal()
	var content = _new_modal()
	if game.phase == "floor_choice":
		content.add_child(_eyebrow("НОВЫЙ ЭТАЖ · НОВЫЕ ВОЗМОЖНОСТИ"))
		content.add_child(_label("Выберите свойство этажа", 26, GOLD))
		content.add_child(_label("Свойство влияет на пять комнат этого этажа и сохраняется до конца забега.", 14, MUTED, true))
		for option in game.floor_trait_options():
			content.add_child(_button(str(option.name), _choose_floor.bind(str(option.id))))
			content.add_child(_label(str(option.description), 13, MUTED, true))
	elif game.phase == "level_up":
		content.add_child(_eyebrow("НОВАЯ СИЛА"))
		content.add_child(_label("Ваше подземелье растёт", 28, GOLD))
		content.add_child(_label("Выберите усиление. Осталось выборов: %d" % game.pending_upgrades, 15, MUTED, true))
		var options = [["hp", "Крепкие прислужники", "+10% HP всем существам"], ["damage", "Жестокие прислужники", "+10% урона всем существам"], ["trap", "Опасные ловушки", "+10% урона шипов и яда"]]
		for option in options:
			var button = _button(str(option[1]) + "\n" + str(option[2]), _choose_upgrade.bind(str(option[0])))
			button.custom_minimum_size.y = 64
			content.add_child(button)
	elif game.phase == "result":
		content.add_child(_eyebrow("ПОДЗЕМЕЛЬЕ УСТОЯЛО"))
		content.add_child(_label("Волна %d отражена" % game.wave, 30, GOLD))
		content.add_child(_label("Герои стали частью вашей истории.", 15, MUTED))
		content.add_child(_label("Убито: %d   ·   Золото: +%d   ·   XP: +%d" % [game.report.get("killed", 0), game.report.get("gold", 0), game.report.get("xp", 0)], 17, PAPER, true))
		content.add_child(_label("Здоровье Лорда: %d / %d" % [game.lord.hp, game.lord.max_hp], 15, GOLD))
		content.add_child(_label("Урон Лорду: %d HP\nГерои получили: %d уровней и %d предметов" % [game.report.get("lord_damage", 0), game.report.get("hero_levels", 0), game.report.get("items", 0)], 14, MUTED, true))
		content.add_child(_label("Комнаты восстановлены. Золото и этажи остаются с вами.", 14, MUTED, true))
		var unlock: String = str(game.report.get("unlock", ""))
		if not unlock.is_empty():
			for entry in game.unlock_catalog():
				if str(entry.id) == unlock:
					content.add_child(_label("НОВЫЙ ЧЕРТЁЖ: " + str(entry.name), 19, GREEN, true))
					content.add_child(_label(str(entry.description), 14, MUTED, true))
		content.add_child(_button("ПРОДОЛЖИТЬ →", _next_wave))
	else:
		content.add_child(_eyebrow("ТРОН ПАЛ"))
		content.add_child(_label("Каждое подземелье\nоставляет легенду.", 30, GOLD))
		content.add_child(_label("Пережито волн: %d\nУбито героев: %d\nЭтажей: %d  ·  Уровень Лорда: %d" % [game.cleared_waves, game.total_kills, game.floor_count, game.lord.level], 18, PAPER))
		content.add_child(_label("Рекорд: %d волн. Следующая крепость будет сильнее." % int(profile.get("wave", 0)), 14, MUTED, true))
		content.add_child(_button("НОВОЕ ПОДЗЕМЕЛЬЕ", _restart))
		content.add_child(_button("Главное меню", _open_menu))

func _show_help() -> void:
	if game.phase == "raid":
		paused = true
	_close_modal()
	var content = _new_modal()
	content.add_child(_eyebrow("ПОЗНАЙТЕ СВОИХ ВРАГОВ"))
	content.add_child(_label("Порядок комнат —\nваше главное оружие.", 27, GOLD))
	content.add_child(_label("Рыцарь ведёт бои с монстрами и выдерживает их удары. Следопыт выходит к ловушкам, но инструменты заканчиваются. Жрица сохраняет группу в живых.", 15, PAPER, true))
	content.add_child(_label("Мимик нападает на поддержку. Пауки добивают слабых. Убитые защитники дают героям опыт и предметы — не кормите их перед тронным залом.", 15, PAPER, true))
	content.add_child(_label("Покупайте этажи и выбирайте их свойства. Со второго ранга комнаты получают специализации. Особые отряды на волнах 5 и 10 открывают чертежи для будущих забегов.", 15, MUTED, true))
	content.add_child(_label("Магазин → свободная комната. Построенная комната → улучшение или другой слот для переноса. Пробел — пауза, Esc — меню.", 13, MUTED, true))
	content.add_child(_button("ПОНЯТНО", _close_modal))

func _new_modal() -> VBoxContainer:
	modal_shade = ColorRect.new()
	modal_shade.color = Color(0.025, 0.035, 0.05, 0.88)
	modal_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(modal_shade)
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_shade.add_child(center)
	modal = PanelContainer.new()
	modal.custom_minimum_size.x = 560
	modal.add_theme_stylebox_override("panel", _style(PANEL, Color("#756143"), 16, 28))
	center.add_child(modal)
	var content = _vbox(modal, 18)
	content.custom_minimum_size.x = 504
	return content

func _close_modal() -> void:
	if is_instance_valid(modal_shade):
		remove_child(modal_shade)
		modal_shade.queue_free()
	modal = null
	modal_shade = null

func _next_wave() -> void:
	_close_modal()
	_action(game.next_wave())

func _choose_upgrade(id: String) -> void:
	_close_modal()
	_action(game.choose_upgrade(id))

func _restart() -> void:
	_begin_run()

func _update_record() -> void:
	var previous: int = int(profile.get("wave", 0))
	var kills: int = int(profile.get("kills", 0))
	if game.cleared_waves > previous or (game.cleared_waves == previous and game.total_kills > kills):
		profile.wave = game.cleared_waves
		profile.kills = game.total_kills
	profile.floors = maxi(int(profile.get("floors", 1)), game.floor_count)
	profile.level = maxi(int(profile.get("level", 1)), int(game.lord.level))
	profile["unlocked_paths"] = game.unlocked_paths.duplicate()
	_write_json("user://profile.json", profile)

func _load_local() -> void:
	var loaded: Dictionary = _read_json("user://profile.json")
	for key in profile:
		if typeof(loaded.get(key)) in [TYPE_INT, TYPE_FLOAT]:
			profile[key] = maxi(0, int(loaded[key]))
	profile["unlocked_paths"] = []
	if loaded.get("unlocked_paths", []) is Array:
		for unlock in loaded.get("unlocked_paths", []):
			if unlock in ["ambush", "plague"] and not profile.unlocked_paths.has(unlock):
				profile.unlocked_paths.append(unlock)
	var settings: Dictionary = _read_json("user://settings.json")
	sound_on = bool(settings.get("sound", true))
	volume = clampf(float(settings.get("volume", 0.65)), 0.0, 1.0)
	speed = int(settings.get("speed", 1))
	if speed not in [1, 2, 4]:
		speed = 1

func _save_settings() -> void:
	_write_json("user://settings.json", {"schema_version": 1, "sound": sound_on, "speed": speed, "volume": volume})

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
	panel.custom_minimum_size.x = min_width
	panel.add_theme_stylebox_override("panel", _style(PANEL, LINE, 10, 14))
	parent.add_child(panel)
	return panel

func _vbox(parent: Control, spacing: int = 8) -> VBoxContainer:
	var box = VBoxContainer.new()
	box.add_theme_constant_override("separation", spacing)
	parent.add_child(box)
	return box

func _label(text: String, font_size: int = 15, color: Color = PAPER, wrap: bool = false) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _eyebrow(text: String) -> Label:
	return _label(text, 10, GOLD)

func _button(text: String, callback: Callable, disabled: bool = false) -> Button:
	var button = Button.new()
	button.text = text
	button.disabled = disabled
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	return button

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

func _stat(parent: Control, title: String, value: String, tint: Color) -> void:
	var box = VBoxContainer.new()
	box.custom_minimum_size.x = 78
	box.add_theme_constant_override("separation", 1)
	parent.add_child(box)
	box.add_child(_label(title, 10, MUTED))
	box.add_child(_label(value, 27, tint))

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
func _build_menu() -> void:
	var topline = HBoxContainer.new()
	page.add_child(topline)
	var edition = _eyebrow("ЛОРД ПОДЗЕМЕЛЬЯ     /     БЕСКОНЕЧНАЯ ОСАДА")
	edition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	topline.add_child(edition)
	topline.add_child(_label("РЕКОРД  %d ВОЛН" % int(profile.get("wave", 0)), 12, GOLD))
	var main_row = HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 32)
	page.add_child(main_row)
	var left = VBoxContainer.new()
	left.custom_minimum_size.x = 390
	left.add_theme_constant_override("separation", 12)
	main_row.add_child(left)
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 22
	left.add_child(spacer)
	var crown = _icon("res://assets/icons/lord.svg", 84)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(crown)
	left.add_child(_label("ВАШЕ\nПОДЗЕМЕЛЬЕ.\nИХ ПОСЛЕДНИЙ\nРЕЙД.", 38, PAPER))
	var intro = _label("Стройте глубже. Изучайте незваных гостей.\nВыбирайте, какой страх ждёт их внизу.", 15, MUTED, true)
	intro.custom_minimum_size.y = 58
	left.add_child(intro)
	if has_run and game.phase != "defeat":
		var resume = _button("ВЕРНУТЬСЯ · ВОЛНА %d  →" % game.wave, _resume_run)
		resume.custom_minimum_size.y = 46
		left.add_child(resume)
	var start = _button("НОВОЕ ПОДЗЕМЕЛЬЕ  →", _request_new_run)
	start.custom_minimum_size.y = 50
	start.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 5, 12))
	start.add_theme_color_override("font_color", INK)
	left.add_child(start)
	var actions = HBoxContainer.new()
	left.add_child(actions)
	actions.add_child(_button("Коллекция", _show_collection))
	actions.add_child(_button("Как играть", _show_help))
	actions.add_child(_button("Настройки", _show_settings))
	left.add_child(_button("Выйти из игры", _quit_game))
	var preview_box = _panel(main_row)
	preview_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preview_col = _vbox(preview_box, 10)
	preview_col.add_child(_eyebrow("КАЖДЫЙ ЭТАЖ — ВАША СТРАТЕГИЯ"))
	preview_col.add_child(_label("Казармы. Лаборатории. Ловушки.", 20, GOLD, true))
	var preview_scroll = ScrollContainer.new()
	preview_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_col.add_child(preview_scroll)
	var showcase = Game.new()
	_fill_showcase(showcase)
	menu_preview = DungeonView.new()
	menu_preview.cinematic = true
	menu_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(menu_preview)
	menu_preview.configure(showcase)
	preview_col.add_child(_label("Рыцари сдерживают монстров. Следопыты расходуют инструменты на ловушках. Найдите слабое место их группы.", 13, MUTED, true))
	var foot = HBoxContainer.new()
	page.add_child(foot)
	var progress = _label("ОТКРЫТО %d / 2 ЧЕРТЕЖЕЙ    ·    Особые отряды на каждой 5-й волне" % game.unlocked_paths.size(), 12, VIOLET)
	progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(progress)
	foot.add_child(_label("Шесть комнат. Десятки сочетаний.", 12, MUTED))

func _request_new_run() -> void:
	if has_run and game.phase != "defeat":
		_close_modal()
		var body = _new_modal()
		body.add_child(_label("Начать новое подземелье?", 26, GOLD))
		body.add_child(_label("Текущий забег закончится. Рекорд и открытые чертежи сохранятся.", 16, MUTED, true))
		body.add_child(_button("НАЧАТЬ НОВЫЙ ЗАБЕГ", _begin_run))
		body.add_child(_button("Вернуться", _close_modal))
	else:
		_begin_run()

func _begin_run() -> void:
	_close_modal()
	game.unlocked_paths.assign(profile.get("unlocked_paths", []))
	game.restart()
	menu_open = false
	has_run = true
	paused = false
	resume_paused = false
	accumulator = 0.0
	selected_slot = -1
	selected_room = ""
	scroll_position = 0
	active_floor = -1
	message = "Выберите комнату в магазине. Герои уязвимы по-разному."
	_sound("click")
	_refresh()

func _open_menu() -> void:
	if menu_open:
		return
	resume_paused = paused
	paused = true
	menu_open = true
	_close_modal()
	_refresh()

func _resume_run() -> void:
	if not has_run or game.phase == "defeat":
		return
	_close_modal()
	menu_open = false
	paused = resume_paused
	_refresh()

func _show_collection() -> void:
	_close_modal()
	var body = _new_modal()
	body.add_child(_eyebrow("ЧЕРТЕЖИ ПОДЗЕМЕЛЬЯ"))
	body.add_child(_label("Новый способ строить", 28, GOLD))
	body.add_child(_label("Победы над особыми отрядами открывают дополнительные ветки комнат для всех следующих забегов.", 15, MUTED, true))
	for entry in game.unlock_catalog():
		var unlocked: bool = game.unlocked_paths.has(str(entry.id))
		body.add_child(_label(("ОТКРЫТО · " if unlocked else "ВОЛНА %d · " % int(entry.wave)) + str(entry.name), 18, GREEN if unlocked else GOLD, true))
		body.add_child(_label(str(entry.description), 14, MUTED, true))
	body.add_child(_button("Назад", _close_modal))

func _show_settings() -> void:
	_close_modal()
	var body = _new_modal()
	body.add_child(_label("Настройки", 28, GOLD))
	body.add_child(_button("Звук: " + ("включён" if sound_on else "выключен"), _settings_toggle_sound))
	body.add_child(_label("Громкость", 15, MUTED))
	var slider = HSlider.new()
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
		buttons.add_child(_button("×%d%s" % [value, " ✓" if speed == value else ""], _settings_speed.bind(value)))
	body.add_child(_button("Готово", _close_modal))

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
	get_tree().quit()

func _fill_showcase(target) -> void:
	target.restart(2042)
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
	match str(stats.get("id", "")):
		"mimic":
			return "Цель: жрица и задний ряд. Обходит прикрытие рыцаря."
		"spider":
			return "Цель: ослабленный герой. Яд усиливает укус."
		"spikes", "poison":
			return "Следопыт ослабит ловушку, пока есть инструменты. Заставьте его потратить их раньше."
		_:
			return "Рыцарь силён против монстров. Ловушки и нападение на поддержку ослабят его группу."

func _show_specializations(index: int) -> void:
	_close_modal()
	var content = _new_modal()
	content.add_child(_eyebrow("КОМНАТА ПОЛУЧАЕТ ХАРАКТЕР"))
	content.add_child(_label("Выберите специализацию", 26, GOLD))
	content.add_child(_label("Одна ветка на комнату. Выбор сохраняется до её продажи.", 14, MUTED, true))
	for option in game.specialization_options(index):
		var button = _button(str(option.name), _specialize.bind(index, str(option.id)))
		button.custom_minimum_size.y = 44
		content.add_child(button)
		content.add_child(_label(str(option.description), 13, MUTED, true))
	content.add_child(_button("Выбрать позже", _close_modal))

func _specialize(index: int, id: String) -> void:
	_close_modal()
	_action(game.specialize_room(index, id))

func _choose_floor(id: String) -> void:
	_close_modal()
	_action(game.choose_floor_trait(id))
